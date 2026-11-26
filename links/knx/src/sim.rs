//! A KNX installation behind KNXnet/IP for tests and demos: a tunnelling
//! server ([`spawn`]) or a routing node ([`spawn_router`]) over a small
//! table of group addresses.
//!
//! * A GroupValue_Write is stored and confirmed (L_Data.con), and shown to
//!   the other tunnels.
//! * A GroupValue_Read of an address in the table is answered with a
//!   GroupValue_Response from [`DEVICE`].
//! * [`Gateway::inject`] sends a GroupValue_Write as a device would.
//! * Failures on request ([`Faults`]): no answers at all, no acknowledge,
//!   no confirmation, a negative confirmation, a refused connect, reads
//!   left without an answer; [`Gateway::close_tunnels`] ends every tunnel
//!   from the gateway's side.

use crate::addr::{GroupAddr, IndividualAddr};
use crate::bus::{multicast_socket, OpenError};
use crate::cemi::{Apci, Data, LData, MessageCode};
use crate::proto::{DeviceInfo, ErrorCode, Frame, Hpai, Medium};
use std::collections::{BTreeMap, BTreeSet};
use std::net::{Ipv4Addr, SocketAddr, SocketAddrV4};
use std::sync::{Arc, Mutex, MutexGuard};
use tokio::net::UdpSocket;
use tokio::sync::mpsc;
use tokio::task::JoinHandle;
use tracing::{debug, trace};

/// The individual address of the simulated bus device.
pub const DEVICE: IndividualAddr = IndividualAddr(0x110A);
/// The gateway's own individual address.
pub const GATEWAY: IndividualAddr = IndividualAddr(0x1100);
/// Tunnels of one gateway at most.
const MAX_TUNNELS: usize = 8;

/// Failures a test asks for.
#[derive(Debug, Clone, Default)]
pub struct Faults {
    /// Answer nothing at all.
    pub silent: bool,
    /// Do not acknowledge (nor take) tunnelling requests.
    pub no_ack: bool,
    /// Acknowledge a tunnelling request, send no L_Data.con.
    pub no_confirm: bool,
    /// Confirm with the error flag: nothing on the bus acknowledged.
    pub not_acknowledged: bool,
    /// Refuse a connect with this status.
    pub refuse: Option<ErrorCode>,
    /// Reads of these addresses get no answer.
    pub mute: BTreeSet<u16>,
}

/// What the simulated installation holds and saw.
#[derive(Debug, Default)]
pub struct Table {
    /// The value of each group address.
    pub groups: BTreeMap<u16, Data>,
    pub faults: Faults,
    /// GroupValue_Write telegrams received, in order.
    pub writes: Vec<(GroupAddr, Data)>,
    /// GroupValue_Read telegrams received, in order.
    pub reads: Vec<GroupAddr>,
    pub connects: u32,
    pub disconnects: u32,
    pub heartbeats: u32,
    /// Tunnels open now.
    pub tunnels: usize,
}

enum Cmd {
    Inject(GroupAddr, Data),
    CloseTunnels,
    Busy(u16),
    Lost(u16),
}

/// A running simulator; dropping it stops it.
pub struct Gateway {
    addr: SocketAddrV4,
    table: Arc<Mutex<Table>>,
    cmds: mpsc::UnboundedSender<Cmd>,
    task: JoinHandle<()>,
}

impl Drop for Gateway {
    fn drop(&mut self) {
        self.task.abort();
    }
}

fn lock(table: &Mutex<Table>) -> MutexGuard<'_, Table> {
    table.lock().unwrap_or_else(|p| p.into_inner())
}

impl Gateway {
    /// Where the gateway listens (a router: the group and port).
    pub fn addr(&self) -> SocketAddrV4 {
        self.addr
    }

    pub fn table(&self) -> MutexGuard<'_, Table> {
        lock(&self.table)
    }

    /// Put a value in the table without a telegram.
    pub fn set(&self, to: GroupAddr, data: Data) {
        self.table().groups.insert(to.0, data);
    }

    fn tell(&self, cmd: Cmd) {
        if self.cmds.send(cmd).is_err() {
            debug!("knx sim: stopped");
        }
    }

    /// A device writes `data` to `to`: stored, and sent to every listener.
    pub fn inject(&self, to: GroupAddr, data: Data) {
        self.tell(Cmd::Inject(to, data));
    }

    /// The gateway ends every tunnel with a DISCONNECT_REQUEST.
    pub fn close_tunnels(&self) {
        self.tell(Cmd::CloseTunnels);
    }

    /// A router says it is busy for `wait_ms`.
    pub fn busy(&self, wait_ms: u16) {
        self.tell(Cmd::Busy(wait_ms));
    }

    /// A router says it lost `count` telegrams.
    pub fn lost(&self, count: u16) {
        self.tell(Cmd::Lost(count));
    }
}

fn v4(addr: SocketAddr) -> Option<SocketAddrV4> {
    match addr {
        SocketAddr::V4(a) => Some(a),
        SocketAddr::V6(_) => None,
    }
}

async fn send(sock: &UdpSocket, frame: &Frame, to: SocketAddrV4) {
    let bytes = match frame.encode() {
        Ok(b) => b,
        Err(e) => {
            debug!("knx sim: frame not encoded: {e}");
            return;
        }
    };
    if let Err(e) = sock.send_to(&bytes, to).await {
        debug!("knx sim: send to {to}: {e}");
    }
}

fn bus_telegram(
    code: MessageCode,
    from: IndividualAddr,
    to: GroupAddr,
    apci: Apci,
    data: Data,
) -> LData {
    LData::group(code, from, to, apci, data)
}

/// What a telegram from a client does to the table: the answer of the bus
/// device to a read, if it gives one.
fn take(table: &mut Table, telegram: &LData) -> Option<LData> {
    let (to, apci, data) = telegram.as_group()?;
    match apci {
        Apci::Write => {
            table.groups.insert(to.0, data.clone());
            table.writes.push((to, data.clone()));
            None
        }
        Apci::Read => {
            table.reads.push(to);
            if table.faults.mute.contains(&to.0) {
                return None;
            }
            let value = table.groups.get(&to.0)?.clone();
            Some(bus_telegram(
                MessageCode::DataInd,
                DEVICE,
                to,
                Apci::Response,
                value,
            ))
        }
        Apci::Response => None,
    }
}

struct Channel {
    id: u8,
    control: SocketAddrV4,
    data: SocketAddrV4,
    address: IndividualAddr,
    send_seq: u8,
    recv_seq: u8,
}

struct Server {
    sock: UdpSocket,
    local: SocketAddrV4,
    table: Arc<Mutex<Table>>,
    channels: Vec<Channel>,
    next_id: u8,
}

/// A tunnelling server (it answers search requests too) on `listen`.
pub async fn spawn(listen: &str) -> std::io::Result<Gateway> {
    let sock = UdpSocket::bind(listen).await?;
    let local = v4(sock.local_addr()?)
        .ok_or_else(|| std::io::Error::other("the simulator listens on IPv4 only"))?;
    let table = Arc::new(Mutex::new(Table::default()));
    let (cmds, mut rx) = mpsc::unbounded_channel();
    let mut server = Server {
        sock,
        local,
        table: table.clone(),
        channels: Vec::new(),
        next_id: 1,
    };
    let task = tokio::spawn(async move {
        let mut buf = vec![0u8; 1024];
        loop {
            tokio::select! {
                got = server.sock.recv_from(&mut buf) => {
                    let Ok((n, from)) = got else { continue };
                    if let (Some(from), Some(bytes)) = (v4(from), buf.get(..n)) {
                        server.on_datagram(bytes, from).await;
                    }
                }
                cmd = rx.recv() => match cmd {
                    Some(Cmd::Inject(to, data)) => {
                        lock(&server.table).groups.insert(to.0, data.clone());
                        let telegram = bus_telegram(MessageCode::DataInd, DEVICE, to, Apci::Write, data);
                        server.forward_all(&telegram, None).await;
                    }
                    Some(Cmd::CloseTunnels) => server.close_all().await,
                    Some(Cmd::Busy(_) | Cmd::Lost(_)) => {}
                    None => return,
                },
            }
        }
    });
    Ok(Gateway {
        addr: local,
        table,
        cmds,
        task,
    })
}

impl Server {
    fn info(&self) -> DeviceInfo {
        DeviceInfo {
            medium: Medium::Tp1.code(),
            address: GATEWAY,
            serial: [0x00, 0xFA, 0x57, 0x59, 0x52, 0x4D],
            mac: [0x02, 0x00, 0x57, 0x59, 0x52, 0x4D],
            name: "WYRM KNX simulator".into(),
        }
    }

    async fn on_datagram(&mut self, bytes: &[u8], from: SocketAddrV4) {
        if lock(&self.table).faults.silent {
            return;
        }
        let frame = match Frame::decode(bytes) {
            Ok(f) => f,
            Err(e) => {
                trace!("knx sim: datagram dropped: {e}");
                return;
            }
        };
        match frame {
            Frame::SearchRequest { discovery } => {
                let answer = Frame::SearchResponse {
                    control: Hpai(self.local),
                    device: self.info(),
                };
                send(&self.sock, &answer, discovery.or(from)).await;
            }
            Frame::ConnectRequest { control, data } => {
                self.connect(control.or(from), data.or(from)).await;
            }
            Frame::ConnectionStateRequest { channel, control } => {
                lock(&self.table).heartbeats += 1;
                let known = self.channels.iter().any(|c| c.id == channel);
                let status = if known {
                    ErrorCode::NoError
                } else {
                    ErrorCode::ConnectionId
                };
                let answer = Frame::ConnectionStateResponse {
                    channel,
                    status: status.code(),
                };
                send(&self.sock, &answer, control.or(from)).await;
            }
            Frame::DisconnectRequest { channel, control } => {
                self.channels.retain(|c| c.id != channel);
                {
                    let mut table = lock(&self.table);
                    table.disconnects += 1;
                    table.tunnels = self.channels.len();
                }
                let answer = Frame::DisconnectResponse { channel, status: 0 };
                send(&self.sock, &answer, control.or(from)).await;
            }
            Frame::TunnellingRequest { channel, seq, cemi } => {
                self.on_request(channel, seq, &cemi).await;
            }
            other => trace!(service = other.service().name(), "knx sim: frame ignored"),
        }
    }

    async fn connect(&mut self, control: SocketAddrV4, data: SocketAddrV4) {
        let refuse = lock(&self.table).faults.refuse;
        let full = self.channels.len() >= MAX_TUNNELS;
        let refusal = refuse.or(full.then_some(ErrorCode::NoMoreConnections));
        if let Some(status) = refusal {
            let answer = Frame::ConnectResponse {
                channel: 0,
                status: status.code(),
                address: None,
                data: None,
            };
            send(&self.sock, &answer, control).await;
            return;
        }
        let id = self.next_id;
        self.next_id = self.next_id.wrapping_add(1).max(1);
        // 1.1.240 and up: the tunnel's address on the line
        let address = IndividualAddr(0x11F0 | u16::from(id & 0x0F));
        self.channels.push(Channel {
            id,
            control,
            data,
            address,
            send_seq: 0,
            recv_seq: 0,
        });
        {
            let mut table = lock(&self.table);
            table.connects += 1;
            table.tunnels = self.channels.len();
        }
        let answer = Frame::ConnectResponse {
            channel: id,
            status: 0,
            address: Some(address),
            data: Some(Hpai(self.local)),
        };
        send(&self.sock, &answer, control).await;
    }

    async fn on_request(&mut self, id: u8, seq: u8, cemi: &[u8]) {
        let faults = lock(&self.table).faults.clone();
        if faults.no_ack {
            return;
        }
        let Some(ch) = self.channels.iter_mut().find(|c| c.id == id) else {
            return;
        };
        let repeat = seq == ch.recv_seq.wrapping_sub(1);
        if seq != ch.recv_seq && !repeat {
            return;
        }
        let (to, address) = (ch.data, ch.address);
        if !repeat {
            ch.recv_seq = ch.recv_seq.wrapping_add(1);
        }
        let ack = Frame::TunnellingAck {
            channel: id,
            seq,
            status: 0,
        };
        send(&self.sock, &ack, to).await;
        let Ok(mut telegram) = LData::decode(cemi) else {
            return;
        };
        if repeat || faults.no_confirm || telegram.code != MessageCode::DataReq {
            return;
        }
        telegram.source = address;
        let mut confirm = telegram.with_code(MessageCode::DataCon);
        confirm.failed = faults.not_acknowledged;
        self.forward(id, &confirm).await;
        if faults.not_acknowledged {
            return;
        }
        let answer = take(&mut lock(&self.table), &telegram);
        self.forward_all(&telegram.with_code(MessageCode::DataInd), Some(id))
            .await;
        if let Some(answer) = answer {
            self.forward_all(&answer, None).await;
        }
    }

    /// `telegram` to the tunnel `id` as its next tunnelling request.
    async fn forward(&mut self, id: u8, telegram: &LData) {
        let Some(ch) = self.channels.iter_mut().find(|c| c.id == id) else {
            return;
        };
        let Ok(cemi) = telegram.encode() else {
            return;
        };
        let frame = Frame::TunnellingRequest {
            channel: id,
            seq: ch.send_seq,
            cemi,
        };
        ch.send_seq = ch.send_seq.wrapping_add(1);
        let to = ch.data;
        send(&self.sock, &frame, to).await;
    }

    /// `telegram` to every tunnel but `except`.
    async fn forward_all(&mut self, telegram: &LData, except: Option<u8>) {
        let ids: Vec<u8> = self.channels.iter().map(|c| c.id).collect();
        for id in ids {
            if Some(id) != except {
                self.forward(id, telegram).await;
            }
        }
    }

    async fn close_all(&mut self) {
        for ch in std::mem::take(&mut self.channels) {
            let bye = Frame::DisconnectRequest {
                channel: ch.id,
                control: Hpai(self.local),
            };
            send(&self.sock, &bye, ch.control).await;
        }
        lock(&self.table).tunnels = 0;
    }
}

/// A routing node on `group:port`, member of the group on `interface`.
pub fn spawn_router(group: Ipv4Addr, port: u16, interface: Ipv4Addr) -> Result<Gateway, OpenError> {
    let sock = multicast_socket(group, port, interface, 1)?;
    let to = SocketAddrV4::new(group, port);
    let table = Arc::new(Mutex::new(Table::default()));
    let shared = table.clone();
    let (cmds, mut rx) = mpsc::unbounded_channel();
    let task = tokio::spawn(async move {
        let mut buf = vec![0u8; 1024];
        loop {
            let frame = tokio::select! {
                got = sock.recv_from(&mut buf) => {
                    let Ok((n, _from)) = got else { continue };
                    buf.get(..n).and_then(|b| heard(&shared, b))
                }
                cmd = rx.recv() => match cmd {
                    Some(Cmd::Inject(to, data)) => {
                        lock(&shared).groups.insert(to.0, data.clone());
                        indication(&bus_telegram(MessageCode::DataInd, DEVICE, to, Apci::Write, data))
                    }
                    Some(Cmd::Busy(wait_ms)) => Some(Frame::RoutingBusy { wait_ms }),
                    Some(Cmd::Lost(lost)) => Some(Frame::RoutingLostMessage { lost }),
                    Some(Cmd::CloseTunnels) => None,
                    None => return,
                },
            };
            if let Some(frame) = frame {
                send(&sock, &frame, to).await;
            }
        }
    });
    Ok(Gateway {
        addr: to,
        table,
        cmds,
        task,
    })
}

fn indication(telegram: &LData) -> Option<Frame> {
    let cemi = telegram.encode().ok()?;
    Some(Frame::RoutingIndication { cemi })
}

/// A routing datagram heard by the router: the frame it answers with.
fn heard(table: &Mutex<Table>, bytes: &[u8]) -> Option<Frame> {
    let Ok(Frame::RoutingIndication { cemi }) = Frame::decode(bytes) else {
        return None;
    };
    let telegram = LData::decode(&cemi).ok()?;
    // the group delivers our own telegrams to us too
    if telegram.source == DEVICE {
        return None;
    }
    let mut table = lock(table);
    if table.faults.silent {
        return None;
    }
    indication(&take(&mut table, &telegram)?)
}
