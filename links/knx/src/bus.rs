//! The open connection to a KNX installation: one task owns the UDP socket
//! (a tunnel to one KNXnet/IP interface, or the routing multicast group)
//! and keeps what the bus said; the driver reads that and queues telegrams.
//!
//! KNX is event driven: a value arrives when a device sends it, not when
//! it is asked. So the task listens all the time and keeps, per group
//! address, the last value seen (GroupValue_Write or GroupValue_Response)
//! with a change counter; a poll of the framework only reads that table.
//!
//! * **Tunnelling**: CONNECT_REQUEST, then TUNNELLING_REQUEST frames with a
//!   sequence counter per direction. A request is acknowledged within 1 s
//!   or repeated once; without an acknowledge the tunnel is given up. A
//!   frame from the interface is acknowledged when its counter is the
//!   expected one (processed) or the one before (a repeat, dropped). A
//!   CONNECTIONSTATE_REQUEST goes out every `heartbeat`; three without an
//!   answer end the tunnel. One telegram is in flight at a time: the next
//!   is sent after the L_Data.con of the one before.
//! * **Routing**: ROUTING_INDICATION datagrams to and from the multicast
//!   group. There is no confirmation: a telegram counts as sent once the
//!   datagram left. ROUTING_BUSY holds our telegrams for the time it
//!   names; ROUTING_LOST_MESSAGE is counted.
//!
//! Telegrams leave at most `rate_per_s` per second. Writes and one-shot
//! reads go before the reads a poll queues.

use crate::addr::{GroupAddr, IndividualAddr};
use crate::cemi::{Apci, Data, FrameError, LData, MessageCode};
use crate::proto::{self, DeviceInfo, Frame, Hpai, ProtoError};
use std::collections::{BTreeMap, BTreeSet, VecDeque};
use std::net::{Ipv4Addr, SocketAddr, SocketAddrV4};
use std::sync::{Arc, Mutex, MutexGuard};
use std::time::Duration;
use tokio::net::UdpSocket;
use tokio::sync::{mpsc, oneshot, Notify};
use tokio::time::Instant;
use tracing::{debug, trace, warn};

/// Telegrams kept for `recent_telegrams`.
pub const RING: usize = 500;
/// Wait for a TUNNELLING_ACK (KNXnet/IP tunnelling: 1 s, one repeat).
const ACK_WAIT: Duration = Duration::from_secs(1);
/// Connection state requests without an answer before the tunnel ends.
const STATE_TRIES: u8 = 3;
/// Wait for a CONNECTIONSTATE_RESPONSE at most (KNXnet/IP core: 10 s).
const STATE_WAIT: Duration = Duration::from_secs(10);
/// Writes and one-shot reads waiting for the task.
const QUEUE_FIRST: usize = 32;
/// Reads of the polls waiting for the task.
const QUEUE_READS: usize = 256;
/// Our own routing telegrams remembered to tell their multicast echo.
const ECHOES: usize = 32;
/// Search responses kept at most.
const MAX_FOUND: usize = 64;

/// Why a connection does not open.
#[derive(Debug, thiserror::Error)]
pub enum OpenError {
    #[error("{what}: {source}")]
    Io {
        what: &'static str,
        source: std::io::Error,
    },
    #[error("{0} has no IPv4 address")]
    NoAddress(String),
    #[error("no answer from the interface within {0} ms")]
    Timeout(u128),
    #[error("the interface refused the tunnel: {0}")]
    Refused(String),
    #[error(transparent)]
    Proto(#[from] ProtoError),
}

fn io(what: &'static str) -> impl FnOnce(std::io::Error) -> OpenError {
    move |source| OpenError::Io { what, source }
}

/// Why a telegram was not sent.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum SendError {
    /// The connection is gone: the framework opens a new one.
    #[error("{0}")]
    Dead(String),
    #[error("no confirmation (L_Data.con) from the interface in time")]
    NoConfirm,
    #[error("the bus did not acknowledge the telegram")]
    NotAcknowledged,
    #[error("no answer to GroupValue_Read {0} in time")]
    NoAnswer(GroupAddr),
    #[error(transparent)]
    Frame(#[from] FrameError),
}

/// One telegram of `recent_telegrams`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Telegram {
    pub time_us: u64,
    /// Sent by this link (else: seen on the bus).
    pub sent: bool,
    pub source: IndividualAddr,
    pub destination: u16,
    pub group: bool,
    /// The group service, when it is one.
    pub apci: Option<Apci>,
    pub data: Vec<u8>,
    /// A sent telegram the bus did not acknowledge.
    pub failed: bool,
}

/// The last value of a group address.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Seen {
    pub data: Data,
    /// Grows with every value telegram of the address.
    pub seq: u64,
}

/// What the task keeps for the driver.
#[derive(Debug, Default)]
pub struct State {
    pub values: BTreeMap<u16, Seen>,
    /// When a GroupValue_Read of ours went out and has no answer yet.
    pub reads: BTreeMap<u16, Instant>,
    /// Addresses read once since the connection opened (`read_on_start`).
    pub started: BTreeSet<u16>,
    pub ring: VecDeque<Telegram>,
    /// Why the connection ended.
    pub dead: Option<String>,
    /// Routing: telegrams a router says it lost.
    pub lost: u64,
    /// Routing: ROUTING_BUSY frames seen.
    pub busy: u64,
}

impl State {
    fn record(&mut self, f: &LData, sent: bool) {
        let (apci, data) = match f.as_group() {
            Some((_, apci, data)) => (Some(apci), data.bytes.clone()),
            None => (None, Vec::new()),
        };
        if self.ring.len() >= RING {
            self.ring.pop_front();
        }
        self.ring.push_back(Telegram {
            time_us: wyrm_core::clock::now_us(),
            sent,
            source: f.source,
            destination: f.destination,
            group: f.group,
            apci,
            data,
            failed: f.failed,
        });
    }

    /// A telegram that is on the bus: a value replaces the group's last
    /// one and answers a read of ours; a read of ours starts its wait.
    fn apply(&mut self, f: &LData, ours: bool) {
        let Some((to, apci, data)) = f.as_group() else {
            return;
        };
        match apci {
            Apci::Read if ours => {
                self.reads.insert(to.0, Instant::now());
            }
            Apci::Read => {}
            Apci::Write | Apci::Response => {
                let seq = self.values.get(&to.0).map_or(0, |s| s.seq) + 1;
                self.values.insert(
                    to.0,
                    Seen {
                        data: data.clone(),
                        seq,
                    },
                );
                self.reads.remove(&to.0);
            }
        }
    }
}

struct Shared {
    state: Mutex<State>,
    changed: Notify,
}

fn lock(shared: &Shared) -> MutexGuard<'_, State> {
    shared.state.lock().unwrap_or_else(|p| p.into_inner())
}

/// A telegram for the task.
struct Cmd {
    to: GroupAddr,
    apci: Apci,
    data: Data,
    done: Option<oneshot::Sender<Result<(), SendError>>>,
}

impl Cmd {
    fn finish(self, r: Result<(), SendError>) {
        if let Some(done) = self.done {
            if done.send(r).is_err() {
                trace!("knx: the caller of a telegram stopped waiting");
            }
        }
    }
}

/// How a tunnel is opened.
#[derive(Debug, Clone)]
pub struct TunnelCfg {
    pub host: String,
    pub port: u16,
    /// Send `0.0.0.0:0` as our endpoints: the interface answers to the
    /// address our datagrams come from.
    pub nat: bool,
    /// Bound on the connect answer and on an L_Data.con.
    pub timeout: Duration,
    pub heartbeat: Duration,
    pub rate_per_s: u32,
}

/// How the routing group is joined.
#[derive(Debug, Clone)]
pub struct RoutingCfg {
    pub group: Ipv4Addr,
    pub port: u16,
    /// The local interface by its address; unspecified = the system's
    /// choice.
    pub interface: Ipv4Addr,
    /// Our source address in the telegrams.
    pub address: IndividualAddr,
    pub ttl: u32,
    pub rate_per_s: u32,
}

/// What an open connection is.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Info {
    /// Our individual address (a tunnel: given by the interface).
    pub address: IndividualAddr,
    /// The interface or the multicast group.
    pub peer: SocketAddrV4,
    pub local: SocketAddrV4,
}

/// An interface that answered a search.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Found {
    pub endpoint: SocketAddrV4,
    pub device: DeviceInfo,
}

/// The open connection. Dropping it (its last clone) ends the task, which
/// closes a tunnel with a DISCONNECT_REQUEST.
#[derive(Clone)]
pub struct Bus {
    shared: Arc<Shared>,
    first: mpsc::Sender<Cmd>,
    reads: mpsc::Sender<Cmd>,
    info: Info,
}

fn interval(rate_per_s: u32) -> Duration {
    Duration::from_secs(1) / rate_per_s.max(1)
}

fn v4(addr: SocketAddr) -> Option<SocketAddrV4> {
    match addr {
        SocketAddr::V4(a) => Some(a),
        SocketAddr::V6(_) => None,
    }
}

async fn resolve(host: &str, port: u16) -> Result<SocketAddrV4, OpenError> {
    let mut found = tokio::net::lookup_host((host, port))
        .await
        .map_err(io("resolve the host"))?;
    found
        .find_map(v4)
        .ok_or_else(|| OpenError::NoAddress(host.to_owned()))
}

/// The local address datagrams to `peer` leave from.
async fn local_ip(peer: SocketAddrV4) -> Result<Ipv4Addr, OpenError> {
    let probe = UdpSocket::bind((Ipv4Addr::UNSPECIFIED, 0))
        .await
        .map_err(io("bind"))?;
    probe.connect(peer).await.map_err(io("route to the peer"))?;
    let local = probe.local_addr().map_err(io("local address"))?;
    Ok(v4(local).map_or(Ipv4Addr::UNSPECIFIED, |a| *a.ip()))
}

async fn send(sock: &UdpSocket, frame: &Frame, to: SocketAddrV4) -> Result<(), String> {
    let bytes = frame.encode().map_err(|e| e.to_string())?;
    match sock.send_to(&bytes, to).await {
        Ok(_) => Ok(()),
        Err(e) => Err(format!("send to {to}: {e}")),
    }
}

impl Bus {
    fn start(info: Info) -> (Bus, Arc<Shared>, mpsc::Receiver<Cmd>, mpsc::Receiver<Cmd>) {
        let shared = Arc::new(Shared {
            state: Mutex::new(State::default()),
            changed: Notify::new(),
        });
        let (first, first_rx) = mpsc::channel(QUEUE_FIRST);
        let (reads, reads_rx) = mpsc::channel(QUEUE_READS);
        let bus = Bus {
            shared: shared.clone(),
            first,
            reads,
            info,
        };
        (bus, shared, first_rx, reads_rx)
    }

    /// Open a tunnel to a KNXnet/IP interface.
    pub async fn tunnel(cfg: TunnelCfg) -> Result<Bus, OpenError> {
        let gateway = resolve(&cfg.host, cfg.port).await?;
        let ip = local_ip(gateway).await?;
        let sock = UdpSocket::bind((ip, 0)).await.map_err(io("bind"))?;
        let local = sock
            .local_addr()
            .ok()
            .and_then(v4)
            .unwrap_or(SocketAddrV4::new(ip, 0));
        let hpai = if cfg.nat { Hpai::NAT } else { Hpai(local) };
        let request = Frame::ConnectRequest {
            control: hpai,
            data: hpai,
        };
        sock.send_to(&request.encode()?, gateway)
            .await
            .map_err(io("send the connect request"))?;
        let deadline = Instant::now() + cfg.timeout;
        let mut buf = vec![0u8; 512];
        let (channel, address, data) = loop {
            let got = tokio::time::timeout_at(deadline, sock.recv_from(&mut buf)).await;
            let Ok(got) = got else {
                return Err(OpenError::Timeout(cfg.timeout.as_millis()));
            };
            let (n, from) = got.map_err(io("receive"))?;
            if v4(from).map(|a| *a.ip()) != Some(*gateway.ip()) {
                continue;
            }
            match buf.get(..n).map(Frame::decode) {
                Some(Ok(Frame::ConnectResponse {
                    channel,
                    status: 0,
                    address: Some(address),
                    data: Some(data),
                })) => break (channel, address, data.or(gateway)),
                Some(Ok(Frame::ConnectResponse { status, .. })) => {
                    return Err(OpenError::Refused(proto::status_text(status)));
                }
                other => trace!(?other, "knx: not a connect response"),
            }
        };
        let info = Info {
            address,
            peer: gateway,
            local,
        };
        let (bus, shared, first, reads) = Bus::start(info);
        let now = Instant::now();
        let tunnel = Tunnel {
            sock,
            control: gateway,
            data,
            hpai,
            channel,
            send_seq: 0,
            recv_seq: 0,
            inflight: None,
            next_send: now,
            interval: interval(cfg.rate_per_s),
            heartbeat: cfg.heartbeat,
            beat_at: now + cfg.heartbeat,
            beat_wait: None,
            confirm: cfg.timeout,
            shared,
        };
        tokio::spawn(tunnel.run(first, reads));
        Ok(bus)
    }

    /// Join the routing multicast group.
    pub async fn routing(cfg: RoutingCfg) -> Result<Bus, OpenError> {
        let sock = multicast_socket(cfg.group, cfg.port, cfg.interface, cfg.ttl)?;
        let info = Info {
            address: cfg.address,
            peer: SocketAddrV4::new(cfg.group, cfg.port),
            local: SocketAddrV4::new(cfg.interface, cfg.port),
        };
        let (bus, shared, first, reads) = Bus::start(info);
        let routing = Routing {
            sock,
            group: SocketAddrV4::new(cfg.group, cfg.port),
            address: cfg.address,
            next_send: Instant::now(),
            interval: interval(cfg.rate_per_s),
            echoes: VecDeque::new(),
            shared,
        };
        tokio::spawn(routing.run(first, reads));
        Ok(bus)
    }

    pub fn info(&self) -> &Info {
        &self.info
    }

    /// The table the task keeps.
    pub fn state(&self) -> MutexGuard<'_, State> {
        lock(&self.shared)
    }

    /// Why the connection ended, if it did.
    pub fn dead(&self) -> Option<String> {
        self.state().dead.clone()
    }

    fn gone(&self) -> SendError {
        SendError::Dead(
            self.dead()
                .unwrap_or_else(|| "the connection is closed".to_owned()),
        )
    }

    /// Queue a GroupValue_Read for a poll; `false` when the queue is full
    /// (the poll asks again on its next turn).
    pub fn queue_read(&self, to: GroupAddr) -> bool {
        let cmd = Cmd {
            to,
            apci: Apci::Read,
            data: Data::default(),
            done: None,
        };
        self.reads.try_send(cmd).is_ok()
    }

    /// Send one telegram and wait until it is on the bus: confirmed by the
    /// interface (a tunnel) or handed to the network (routing).
    pub async fn send(&self, to: GroupAddr, apci: Apci, data: Data) -> Result<(), SendError> {
        if let Some(why) = self.dead() {
            return Err(SendError::Dead(why));
        }
        let (done, wait) = oneshot::channel();
        let cmd = Cmd {
            to,
            apci,
            data,
            done: Some(done),
        };
        if self.first.send(cmd).await.is_err() {
            return Err(self.gone());
        }
        match wait.await {
            Ok(r) => r,
            Err(_closed) => Err(self.gone()),
        }
    }

    /// Send a GroupValue_Read and wait for the next value of the group.
    pub async fn read(&self, to: GroupAddr, wait: Duration) -> Result<Data, SendError> {
        let before = self.state().values.get(&to.0).map_or(0, |s| s.seq);
        self.send(to, Apci::Read, Data::default()).await?;
        let deadline = Instant::now() + wait;
        loop {
            let changed = self.shared.changed.notified();
            tokio::pin!(changed);
            // registered before the check, so no value slips between them
            changed.as_mut().enable();
            {
                let state = self.state();
                if let Some(seen) = state.values.get(&to.0).filter(|s| s.seq != before) {
                    return Ok(seen.data.clone());
                }
                if let Some(why) = &state.dead {
                    return Err(SendError::Dead(why.clone()));
                }
            }
            if tokio::time::timeout_at(deadline, changed).await.is_err() {
                return Err(SendError::NoAnswer(to));
            }
        }
    }

    /// The last `max` telegrams, oldest first.
    pub fn recent(&self, max: usize) -> Vec<Telegram> {
        let state = self.state();
        let skip = state.ring.len().saturating_sub(max);
        state.ring.iter().skip(skip).cloned().collect()
    }
}

/// A telegram sent through the tunnel and not confirmed yet.
struct Inflight {
    cmd: Cmd,
    datagram: Vec<u8>,
    seq: u8,
    tries: u8,
    /// `None` once the TUNNELLING_ACK came.
    ack_by: Option<Instant>,
    confirm_by: Instant,
}

struct Tunnel {
    sock: UdpSocket,
    control: SocketAddrV4,
    data: SocketAddrV4,
    hpai: Hpai,
    channel: u8,
    send_seq: u8,
    recv_seq: u8,
    inflight: Option<Inflight>,
    next_send: Instant,
    interval: Duration,
    heartbeat: Duration,
    beat_at: Instant,
    /// A connection state request without its answer: until when, and
    /// which try it is.
    beat_wait: Option<(Instant, u8)>,
    confirm: Duration,
    shared: Arc<Shared>,
}

impl Tunnel {
    async fn run(mut self, mut first: mpsc::Receiver<Cmd>, mut reads: mpsc::Receiver<Cmd>) {
        let ended = self.serve(&mut first, &mut reads).await;
        let bye = Frame::DisconnectRequest {
            channel: self.channel,
            control: self.hpai,
        };
        if let Err(e) = send(&self.sock, &bye, self.control).await {
            debug!("knx: disconnect request not sent: {e}");
        }
        let why = ended.unwrap_or_else(|| "the connection is closed".to_owned());
        if let Some(flight) = self.inflight.take() {
            flight.cmd.finish(Err(SendError::Dead(why.clone())));
        }
        lock(&self.shared).dead = Some(why);
        self.shared.changed.notify_waiters();
    }

    /// Until the tunnel ends: `Some(why)` when it broke, `None` when the
    /// driver dropped the connection.
    async fn serve(
        &mut self,
        first: &mut mpsc::Receiver<Cmd>,
        reads: &mut mpsc::Receiver<Cmd>,
    ) -> Option<String> {
        let mut buf = vec![0u8; 1024];
        loop {
            let now = Instant::now();
            if let Err(why) = self.on_time(now).await {
                return Some(why);
            }
            let idle = self.inflight.is_none() && now >= self.next_send;
            let wake = self.wake();
            tokio::select! {
                biased;
                got = self.sock.recv_from(&mut buf) => {
                    let (n, from) = match got {
                        Ok(g) => g,
                        Err(e) => return Some(format!("receive: {e}")),
                    };
                    let known = v4(from).is_some_and(|a| a.ip() == self.control.ip());
                    if let (true, Some(bytes)) = (known, buf.get(..n)) {
                        if let Err(why) = self.on_datagram(bytes).await {
                            return Some(why);
                        }
                    }
                }
                cmd = first.recv(), if idle => match cmd {
                    Some(cmd) => {
                        if let Err(why) = self.begin(cmd).await {
                            return Some(why);
                        }
                    }
                    None => return None,
                },
                cmd = reads.recv(), if idle => match cmd {
                    Some(cmd) => {
                        if let Err(why) = self.begin(cmd).await {
                            return Some(why);
                        }
                    }
                    None => return None,
                },
                () = tokio::time::sleep_until(wake) => {}
            }
        }
    }

    /// The next moment a timer of the tunnel is due.
    fn wake(&self) -> Instant {
        let mut wake = self.beat_at;
        if let Some((by, _)) = self.beat_wait {
            wake = wake.min(by);
        }
        match &self.inflight {
            Some(f) => wake.min(f.ack_by.unwrap_or(f.confirm_by)),
            // a telegram may wait for its turn under the rate limit
            None if self.next_send > Instant::now() => wake.min(self.next_send),
            None => wake,
        }
    }

    /// Timers: the acknowledge and confirmation of the telegram in flight,
    /// and the connection state heartbeat.
    async fn on_time(&mut self, now: Instant) -> Result<(), String> {
        let due = self
            .inflight
            .as_ref()
            .map(|f| (f.ack_by, f.confirm_by, f.tries));
        match due {
            Some((Some(by), _, tries)) if now >= by && tries >= 2 => {
                return Err("the interface did not acknowledge a tunnelling request".into());
            }
            Some((Some(by), _, _)) if now >= by => self.repeat(now).await?,
            Some((None, by, _)) if now >= by => self.finish(Err(SendError::NoConfirm)),
            _ => {}
        }
        match self.beat_wait {
            Some((by, tries)) if now >= by && tries >= STATE_TRIES => {
                return Err("the interface does not answer the connection state request".into());
            }
            Some((by, tries)) if now >= by => self.beat(now, tries + 1).await?,
            None if now >= self.beat_at => self.beat(now, 1).await?,
            _ => {}
        }
        Ok(())
    }

    /// The tunnelling request in flight once more (its one repeat).
    async fn repeat(&mut self, now: Instant) -> Result<(), String> {
        let Some(f) = self.inflight.as_mut() else {
            return Ok(());
        };
        f.tries += 1;
        f.ack_by = Some(now + ACK_WAIT);
        debug!(seq = f.seq, "knx: tunnelling request repeated");
        match self.sock.send_to(&f.datagram, self.data).await {
            Ok(_) => Ok(()),
            Err(e) => Err(format!("send to {}: {e}", self.data)),
        }
    }

    async fn beat(&mut self, now: Instant, tries: u8) -> Result<(), String> {
        let frame = Frame::ConnectionStateRequest {
            channel: self.channel,
            control: self.hpai,
        };
        send(&self.sock, &frame, self.control).await?;
        self.beat_wait = Some((now + STATE_WAIT.min(self.heartbeat), tries));
        self.beat_at = now + self.heartbeat;
        Ok(())
    }

    /// Put `cmd` on the wire as the telegram in flight.
    async fn begin(&mut self, cmd: Cmd) -> Result<(), String> {
        // the interface puts its own address in as the source
        let telegram = LData::group(
            MessageCode::DataReq,
            IndividualAddr(0),
            cmd.to,
            cmd.apci,
            cmd.data.clone(),
        );
        let cemi = match telegram.encode() {
            Ok(c) => c,
            Err(e) => {
                cmd.finish(Err(e.into()));
                return Ok(());
            }
        };
        let frame = Frame::TunnellingRequest {
            channel: self.channel,
            seq: self.send_seq,
            cemi,
        };
        let datagram = frame.encode().map_err(|e| e.to_string())?;
        if let Err(e) = self.sock.send_to(&datagram, self.data).await {
            cmd.finish(Err(SendError::Dead(e.to_string())));
            return Err(format!("send to {}: {e}", self.data));
        }
        let now = Instant::now();
        self.next_send = now + self.interval;
        self.inflight = Some(Inflight {
            cmd,
            datagram,
            seq: self.send_seq,
            tries: 1,
            ack_by: Some(now + ACK_WAIT),
            confirm_by: now + ACK_WAIT + self.confirm,
        });
        Ok(())
    }

    /// The telegram in flight is done: tell its caller. A read starts its
    /// wait for an answer whatever became of it, so a poll sees the miss.
    fn finish(&mut self, r: Result<(), SendError>) {
        let Some(flight) = self.inflight.take() else {
            return;
        };
        if flight.cmd.apci == Apci::Read && r.is_err() {
            lock(&self.shared)
                .reads
                .insert(flight.cmd.to.0, Instant::now());
        }
        flight.cmd.finish(r);
    }

    async fn on_datagram(&mut self, bytes: &[u8]) -> Result<(), String> {
        let frame = match Frame::decode(bytes) {
            Ok(f) => f,
            Err(e) => {
                trace!("knx: datagram dropped: {e}");
                return Ok(());
            }
        };
        match frame {
            Frame::TunnellingRequest { channel, seq, cemi } if channel == self.channel => {
                self.on_request(seq, &cemi).await
            }
            Frame::TunnellingAck {
                channel,
                seq,
                status,
            } if channel == self.channel => {
                let Some(f) = self.inflight.as_mut().filter(|f| f.seq == seq) else {
                    return Ok(());
                };
                if status != 0 {
                    return Err(format!(
                        "the interface refused a tunnelling request: {}",
                        proto::status_text(status)
                    ));
                }
                if f.ack_by.take().is_some() {
                    f.confirm_by = Instant::now() + self.confirm;
                    self.send_seq = self.send_seq.wrapping_add(1);
                }
                Ok(())
            }
            Frame::ConnectionStateResponse { channel, status } if channel == self.channel => {
                if status != 0 {
                    return Err(format!(
                        "the interface ended the tunnel: {}",
                        proto::status_text(status)
                    ));
                }
                self.beat_wait = None;
                Ok(())
            }
            Frame::DisconnectRequest { channel, .. } if channel == self.channel => {
                let answer = Frame::DisconnectResponse { channel, status: 0 };
                send(&self.sock, &answer, self.control).await?;
                Err("the interface closed the tunnel".into())
            }
            other => {
                trace!(service = other.service().name(), "knx: frame ignored");
                Ok(())
            }
        }
    }

    /// A TUNNELLING_REQUEST of the interface: acknowledge the expected
    /// counter and the one before (a repeat), take only the expected one.
    async fn on_request(&mut self, seq: u8, cemi: &[u8]) -> Result<(), String> {
        let repeat = seq == self.recv_seq.wrapping_sub(1);
        if seq != self.recv_seq && !repeat {
            debug!(seq, expected = self.recv_seq, "knx: sequence out of order");
            return Ok(());
        }
        let ack = Frame::TunnellingAck {
            channel: self.channel,
            seq,
            status: 0,
        };
        send(&self.sock, &ack, self.data).await?;
        if repeat {
            return Ok(());
        }
        self.recv_seq = self.recv_seq.wrapping_add(1);
        let telegram = match LData::decode(cemi) {
            Ok(t) => t,
            Err(e) => {
                trace!("knx: cEMI frame dropped: {e}");
                return Ok(());
            }
        };
        match telegram.code {
            MessageCode::DataInd => {
                let mut state = lock(&self.shared);
                state.record(&telegram, false);
                state.apply(&telegram, false);
            }
            MessageCode::DataCon => self.on_confirm(&telegram),
            MessageCode::DataReq => {}
        }
        self.shared.changed.notify_waiters();
        Ok(())
    }

    /// An L_Data.con: the telegram in flight is on the bus, or was not
    /// acknowledged there.
    fn on_confirm(&mut self, telegram: &LData) {
        let ours = self.inflight.as_ref().is_some_and(|f| {
            telegram
                .as_group()
                .is_some_and(|(to, apci, _)| to == f.cmd.to && apci == f.cmd.apci)
        });
        if !ours {
            return;
        }
        {
            let mut state = lock(&self.shared);
            state.record(telegram, true);
            if !telegram.failed {
                state.apply(telegram, true);
            }
        }
        // an acknowledge lost on the way: the confirmation says it arrived
        if let Some(f) = self.inflight.as_mut() {
            if f.ack_by.take().is_some() {
                self.send_seq = self.send_seq.wrapping_add(1);
            }
        }
        self.finish(if telegram.failed {
            Err(SendError::NotAcknowledged)
        } else {
            Ok(())
        });
    }
}

struct Routing {
    sock: UdpSocket,
    group: SocketAddrV4,
    address: IndividualAddr,
    next_send: Instant,
    interval: Duration,
    /// cEMI frames we sent and whose multicast echo has not come back.
    echoes: VecDeque<Vec<u8>>,
    shared: Arc<Shared>,
}

impl Routing {
    async fn run(mut self, mut first: mpsc::Receiver<Cmd>, mut reads: mpsc::Receiver<Cmd>) {
        let ended = self.serve(&mut first, &mut reads).await;
        let why = ended.unwrap_or_else(|| "the connection is closed".to_owned());
        lock(&self.shared).dead = Some(why);
        self.shared.changed.notify_waiters();
    }

    async fn serve(
        &mut self,
        first: &mut mpsc::Receiver<Cmd>,
        reads: &mut mpsc::Receiver<Cmd>,
    ) -> Option<String> {
        let mut buf = vec![0u8; 1024];
        loop {
            let now = Instant::now();
            let idle = now >= self.next_send;
            let wake = self.next_send.max(now + Duration::from_millis(1));
            tokio::select! {
                biased;
                got = self.sock.recv_from(&mut buf) => match got {
                    Ok((n, _from)) => {
                        if let Some(bytes) = buf.get(..n) {
                            self.on_datagram(bytes);
                        }
                    }
                    Err(e) => return Some(format!("receive: {e}")),
                },
                cmd = first.recv(), if idle => match cmd {
                    Some(cmd) => {
                        if let Err(why) = self.begin(cmd).await {
                            return Some(why);
                        }
                    }
                    None => return None,
                },
                cmd = reads.recv(), if idle => match cmd {
                    Some(cmd) => {
                        if let Err(why) = self.begin(cmd).await {
                            return Some(why);
                        }
                    }
                    None => return None,
                },
                () = tokio::time::sleep_until(wake), if !idle => {}
            }
        }
    }

    async fn begin(&mut self, cmd: Cmd) -> Result<(), String> {
        let telegram = LData::group(
            MessageCode::DataInd,
            self.address,
            cmd.to,
            cmd.apci,
            cmd.data.clone(),
        );
        let cemi = match telegram.encode() {
            Ok(c) => c,
            Err(e) => {
                cmd.finish(Err(e.into()));
                return Ok(());
            }
        };
        if self.echoes.len() >= ECHOES {
            self.echoes.pop_front();
        }
        self.echoes.push_back(cemi.clone());
        let frame = Frame::RoutingIndication { cemi };
        if let Err(why) = send(&self.sock, &frame, self.group).await {
            cmd.finish(Err(SendError::Dead(why.clone())));
            return Err(why);
        }
        self.next_send = self.next_send.max(Instant::now()) + self.interval;
        {
            let mut state = lock(&self.shared);
            state.record(&telegram, true);
            state.apply(&telegram, true);
        }
        self.shared.changed.notify_waiters();
        cmd.finish(Ok(()));
        Ok(())
    }

    fn on_datagram(&mut self, bytes: &[u8]) {
        let frame = match Frame::decode(bytes) {
            Ok(f) => f,
            Err(e) => {
                trace!("knx: datagram dropped: {e}");
                return;
            }
        };
        match frame {
            Frame::RoutingIndication { cemi } => {
                // the group delivers our own datagram to us too
                if let Some(i) = self.echoes.iter().position(|e| *e == cemi) {
                    self.echoes.remove(i);
                    return;
                }
                match LData::decode(&cemi) {
                    Ok(telegram) => {
                        let mut state = lock(&self.shared);
                        state.record(&telegram, false);
                        state.apply(&telegram, false);
                    }
                    Err(e) => trace!("knx: cEMI frame dropped: {e}"),
                }
                self.shared.changed.notify_waiters();
            }
            Frame::RoutingBusy { wait_ms } => {
                lock(&self.shared).busy += 1;
                let until = Instant::now() + Duration::from_millis(wait_ms.into());
                self.next_send = self.next_send.max(until);
                debug!(wait_ms, "knx: a router is busy, sending held");
            }
            Frame::RoutingLostMessage { lost } => {
                lock(&self.shared).lost += u64::from(lost);
                warn!(lost, "knx: a router lost telegrams");
            }
            other => trace!(service = other.service().name(), "knx: frame ignored"),
        }
    }
}

/// A UDP socket on `port` that several programs of the host may share,
/// member of `group` on `interface`.
pub fn multicast_socket(
    group: Ipv4Addr,
    port: u16,
    interface: Ipv4Addr,
    ttl: u32,
) -> Result<UdpSocket, OpenError> {
    use socket2::{Domain, Protocol, Socket, Type};
    let sock =
        Socket::new(Domain::IPV4, Type::DGRAM, Some(Protocol::UDP)).map_err(io("open a socket"))?;
    sock.set_reuse_address(true).map_err(io("share the port"))?;
    #[cfg(unix)]
    sock.set_reuse_port(true).map_err(io("share the port"))?;
    sock.set_nonblocking(true).map_err(io("open a socket"))?;
    sock.bind(&SocketAddrV4::new(Ipv4Addr::UNSPECIFIED, port).into())
        .map_err(io("bind the routing port"))?;
    sock.join_multicast_v4(&group, &interface)
        .map_err(io("join the multicast group"))?;
    if !interface.is_unspecified() {
        sock.set_multicast_if_v4(&interface)
            .map_err(io("select the interface"))?;
    }
    // other KNX programs on this host must hear us
    sock.set_multicast_loop_v4(true)
        .map_err(io("set the multicast loop"))?;
    sock.set_multicast_ttl_v4(ttl)
        .map_err(io("set the multicast TTL"))?;
    UdpSocket::from_std(sock.into()).map_err(io("open a socket"))
}

/// Ask for KNXnet/IP interfaces at `target` (the multicast group, or one
/// host) and collect the answers for `wait`.
pub async fn search(
    target: SocketAddrV4,
    interface: Ipv4Addr,
    wait: Duration,
) -> Result<Vec<Found>, OpenError> {
    let ip = if interface.is_unspecified() {
        local_ip(target).await?
    } else {
        interface
    };
    let sock = if target.ip().is_multicast() {
        use socket2::{Domain, Protocol, Socket, Type};
        let s = Socket::new(Domain::IPV4, Type::DGRAM, Some(Protocol::UDP))
            .map_err(io("open a socket"))?;
        s.set_nonblocking(true).map_err(io("open a socket"))?;
        s.bind(&SocketAddrV4::new(ip, 0).into())
            .map_err(io("bind"))?;
        s.set_multicast_if_v4(&ip)
            .map_err(io("select the interface"))?;
        UdpSocket::from_std(s.into()).map_err(io("open a socket"))?
    } else {
        UdpSocket::bind((ip, 0)).await.map_err(io("bind"))?
    };
    let local = sock.local_addr().map_err(io("local address"))?;
    let request = Frame::SearchRequest {
        discovery: v4(local).map_or(Hpai::NAT, Hpai),
    };
    sock.send_to(&request.encode()?, target)
        .await
        .map_err(io("send the search request"))?;
    let deadline = Instant::now() + wait;
    let mut buf = vec![0u8; 1024];
    let mut found: Vec<Found> = Vec::new();
    while found.len() < MAX_FOUND {
        let Ok(got) = tokio::time::timeout_at(deadline, sock.recv_from(&mut buf)).await else {
            break;
        };
        let (n, from) = got.map_err(io("receive"))?;
        let (Some(from), Some(bytes)) = (v4(from), buf.get(..n)) else {
            continue;
        };
        if let Ok(Frame::SearchResponse { control, device }) = Frame::decode(bytes) {
            let endpoint = control.or(from);
            if !found.iter().any(|f| f.endpoint == endpoint) {
                found.push(Found { endpoint, device });
            }
        }
    }
    Ok(found)
}
