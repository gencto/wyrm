//! Slave (server) mode (ruling 15, ADR 0024): the connection kinds
//! `ip_slave` (Modbus TCP on a listener, loopback by default) and
//! `serial_slave` (RTU on a serial port). Devices are the unit ids served;
//! points are views on the served coils, discrete inputs, input and holding
//! registers of their unit (devices with the same unit share them, and
//! overlapping points show the same registers).
//!
//! Every request of a master goes through a queue to the connection's owner
//! task ([`Slave::remote`]), which also applies the tree's sets
//! ([`Slave::set`]): one order for both, so the last writer wins and the
//! value published is the value the next master read returns. The master
//! gets its reply after the framework published what its write changed.
//!
//! * A point the tree never set has no value (ruling P24): nothing is
//!   published for it, and a master read touching it answers exception 4
//!   (server device failure). Bits are known one by one (ruling P28): a bit
//!   point has a value once its bit is known, a word view once all its bits
//!   are; a master read of an address needs the bits its points read (a bit
//!   no point reads is served as 0). A new point never takes over the words
//!   or bits of a removed or changed one.
//! * An address no point covers answers exception 2 (illegal data address);
//!   a write touching a point without `writable_by_master` answers
//!   exception 3 (illegal data value), and so does a write that a point it
//!   touches cannot decode or that makes a float not finite (ruling P25),
//!   and a read or write of more registers or bits than one request
//!   carries; a tree set that would make an overlapping point of another
//!   type undecodable is refused the same way. A refused request changes
//!   nothing. FC22 needs the bits its register's points read, as a read
//!   does (else 4). Function codes other than FC1–6, 15, 16 and 22 answer
//!   exception 1.
//! * A unit no device serves: no reply on RTU (another slave on the bus may
//!   have it), exception 0x0B (gateway target failed to respond) on TCP.
//!   An RTU broadcast (unit 0) write goes to every served unit that takes
//!   it, with no reply; a broadcast read is ignored (ruling P26). A device
//!   with unit 0 under `serial_slave` is refused (it is the broadcast).
//! * A request received before the plan in force began (a re-plan while it
//!   waited) answers busy and changes nothing, as a tree set does; one whose
//!   master stopped waiting (it got busy) is dropped, never applied late.
//! * A master write is logged at info with the points it changed (never the
//!   value) and counted in the diagnostics; it is not in the site's audit
//!   trail (no WYRM caller, ruling P4).

use crate::codec::{self, DType};
use crate::{serial_builder, serial_path_ok, Conn, Point, Table, NO_RTU_BROADCAST};
use std::collections::{BTreeMap, HashMap, HashSet};
use std::future::Future;
use std::net::SocketAddr;
use std::pin::Pin;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::{mpsc, oneshot, OwnedSemaphorePermit, Semaphore};
use tokio::task::JoinHandle;
use tokio::time::Instant;
use tokio_modbus::server::Service;
use tokio_modbus::{ExceptionCode, Request, Response, SlaveRequest};
use tracing::{debug, info};
use wyrm_core::Value;
use wyrm_link_sdk::driver::{Changed, DriverError, Outcome, PointId, Remote, Served};

/// Master requests waiting for the owner task.
const QUEUE: usize = 64;

/// How long a master request waits for the owner task before it is
/// answered busy (TCP) or not at all (RTU).
const ANSWER: Duration = Duration::from_secs(1);

/// How long a listener waits for its port: one closed just before (a
/// restart or an edit of the connection) frees it a moment later.
const BIND_WAIT: Duration = Duration::from_millis(1500);

/// TCP masters an `ip_slave` serves at once (on all its addresses): the
/// queue bounds requests, this bounds sockets. Another master is closed as
/// soon as it connects.
const MAX_MASTERS: usize = 16;

/// Bits one FC15 request writes (FC16: [`codec::MAX_WRITE_REGISTERS`]).
const MAX_WRITE_BITS: u16 = 1968;

type Answer = Result<Option<Response>, ExceptionCode>;

/// A master request for the owner task.
struct Ask {
    unit: u8,
    req: Request<'static>,
    at: Instant,
    reply: oneshot::Sender<Answer>,
}

enum Msg {
    Ask(Ask),
    /// The listener or the serial port stopped (why).
    Down(String),
}

/// The `tokio-modbus` service: hands each request to the owner task.
#[derive(Clone)]
struct Front {
    tx: mpsc::Sender<Msg>,
    rtu: bool,
    /// A TCP master's place among [`MAX_MASTERS`], held while its
    /// connection is served (the service lives as long as it).
    _place: Option<Arc<OwnedSemaphorePermit>>,
    /// When the TCP master's last complete request came ([`Idle`]).
    last: Option<Arc<std::sync::Mutex<Instant>>>,
}

/// A TCP master's socket that ends (reads as closed) once the master sent
/// no complete request for `idle`: an idle master does not hold one of the
/// [`MAX_MASTERS`] places for ever (security review). Bytes alone do not
/// count, so a master that trickles a partial frame is closed too.
struct Idle {
    stream: tokio::net::TcpStream,
    last: Arc<std::sync::Mutex<Instant>>,
    idle: Duration,
    timer: Pin<Box<tokio::time::Sleep>>,
}

impl Idle {
    fn new(stream: tokio::net::TcpStream, idle: Duration) -> Self {
        let now = Instant::now();
        Idle {
            stream,
            last: Arc::new(std::sync::Mutex::new(now)),
            idle,
            timer: Box::pin(tokio::time::sleep_until(now + idle)),
        }
    }
}

impl tokio::io::AsyncRead for Idle {
    fn poll_read(
        mut self: Pin<&mut Self>,
        cx: &mut std::task::Context<'_>,
        buf: &mut tokio::io::ReadBuf<'_>,
    ) -> std::task::Poll<std::io::Result<()>> {
        while self.timer.as_mut().poll(cx).is_ready() {
            let due = *self.last.lock().unwrap_or_else(|e| e.into_inner()) + self.idle;
            if Instant::now() >= due {
                debug!("master closed: idle for {:?}", self.idle);
                // End of stream: the request loop ends, the place is freed.
                return std::task::Poll::Ready(Ok(()));
            }
            self.timer.as_mut().reset(due);
        }
        Pin::new(&mut self.stream).poll_read(cx, buf)
    }
}

impl tokio::io::AsyncWrite for Idle {
    fn poll_write(
        mut self: Pin<&mut Self>,
        cx: &mut std::task::Context<'_>,
        buf: &[u8],
    ) -> std::task::Poll<std::io::Result<usize>> {
        Pin::new(&mut self.stream).poll_write(cx, buf)
    }

    fn poll_flush(
        mut self: Pin<&mut Self>,
        cx: &mut std::task::Context<'_>,
    ) -> std::task::Poll<std::io::Result<()>> {
        Pin::new(&mut self.stream).poll_flush(cx)
    }

    fn poll_shutdown(
        mut self: Pin<&mut Self>,
        cx: &mut std::task::Context<'_>,
    ) -> std::task::Poll<std::io::Result<()>> {
        Pin::new(&mut self.stream).poll_shutdown(cx)
    }
}

impl Service for Front {
    type Request = SlaveRequest<'static>;
    type Response = Option<Response>;
    type Exception = ExceptionCode;
    type Future = Pin<Box<dyn Future<Output = Answer> + Send>>;

    fn call(&self, req: SlaveRequest<'static>) -> Self::Future {
        if let Some(last) = &self.last {
            *last.lock().unwrap_or_else(|e| e.into_inner()) = Instant::now();
        }
        let (tx, rtu) = (self.tx.clone(), self.rtu);
        Box::pin(async move {
            // Busy: an exception on TCP; silence on RTU, where the unit may
            // be another slave's.
            let busy = if rtu {
                Ok(None)
            } else {
                Err(ExceptionCode::ServerDeviceBusy)
            };
            let (reply, answer) = oneshot::channel();
            let ask = Ask {
                unit: req.slave,
                req: req.request,
                at: Instant::now(),
                reply,
            };
            if tx.try_send(Msg::Ask(ask)).is_err() {
                return busy;
            }
            match tokio::time::timeout(ANSWER, answer).await {
                Ok(Ok(a)) => a,
                _ => busy,
            }
        })
    }
}

/// A served register or bit: `(unit, table, address)`.
type Addr = (u8, Table, u16);

/// A served word and the mask of its bits that are known (ruling P28); an
/// unknown bit is 0 in the word. A coil or discrete input is 0 or 1, all
/// known.
#[derive(Debug, Clone, Copy, PartialEq)]
struct Word {
    v: u16,
    known: u16,
}

/// Every bit known.
const ALL: u16 = 0xFFFF;

impl Word {
    fn whole(v: u16) -> Self {
        Word { v, known: ALL }
    }

    /// The word when every bit of `need` is known.
    fn read(self, need: u16) -> Option<u16> {
        (self.known & need == need).then_some(self.v)
    }
}

/// The bits of a word that `p` reads: one for a bit point on a register,
/// all of them otherwise.
fn needs(p: &Point) -> u16 {
    if !p.table.is_bits() && p.dtype == DType::Binary {
        1 << p.bit
    } else {
        ALL
    }
}

struct ServedPoint {
    dev: String,
    id: PointId,
    unit: u8,
    point: Point,
}

/// A running slave: the server task, the served values and the points.
pub struct Slave {
    rx: mpsc::Receiver<Msg>,
    task: JoinHandle<()>,
    /// RTU framing (serial).
    rtu: bool,
    note: Option<String>,
    /// The request received by [`Slave::remote`], applied by
    /// [`Slave::apply_remote`].
    pending: Option<Ask>,
    /// Served words with their known bits. Absent: no bit known (the tree
    /// never set it).
    words: HashMap<Addr, Word>,
    points: Vec<ServedPoint>,
    /// The points that cover each address.
    cover: HashMap<Addr, Vec<usize>>,
    /// The device of each unit served (the first by name).
    units: BTreeMap<u8, String>,
    changed: Vec<Changed>,
    outcomes: Vec<Outcome>,
}

impl Drop for Slave {
    /// Closes the listener (and, through its cancel guard, every master's
    /// connection) or the serial port.
    fn drop(&mut self) {
        self.task.abort();
    }
}

/// Open the listener or serial port of a slave connection.
pub(crate) async fn open(conn: &Conn) -> Result<Slave, DriverError> {
    let (tx, rx) = mpsc::channel(QUEUE);
    match conn {
        Conn::IpSlave(c) => {
            let target = format!("{}:{}", c.listen_host, c.listen_port);
            let mut addrs: Vec<SocketAddr> = tokio::net::lookup_host(&target)
                .await
                .map_err(|e| DriverError::Transport(format!("resolve {target}: {e}")))?
                .collect();
            addrs.sort_unstable();
            addrs.dedup();
            // Every address the name resolves to (`localhost`: `::1` and
            // `127.0.0.1`); one the host lacks is left out, none is an error.
            // Any other bind error (the port in use) fails the connection:
            // listening on the other addresses only would let masters of
            // that one reach another process.
            let mut listeners = Vec::new();
            let mut missing = None;
            for addr in addrs {
                match bind(addr).await {
                    Ok(l) => listeners.push(l),
                    Err(e) if host_lacks(&e) => {
                        debug!(%addr, "not listening there: {e}");
                        missing.get_or_insert(format!("listen on {addr}: {e}"));
                    }
                    Err(e) => return Err(DriverError::Transport(format!("listen on {addr}: {e}"))),
                }
            }
            if listeners.is_empty() {
                return Err(DriverError::Transport(
                    missing.unwrap_or_else(|| format!("resolve {target}: no address")),
                ));
            }
            // Judged on the addresses bound, not on the name given.
            let wide: Vec<String> = listeners
                .iter()
                .filter_map(|l| l.local_addr().ok())
                .filter(|a| !a.ip().is_loopback())
                .map(|a| a.to_string())
                .collect();
            let note = (!wide.is_empty()).then(|| {
                format!(
                    "listening on {}, not loopback: Modbus has no authentication, any host \
                     that reaches this port reads the served values and writes those a \
                     master may write",
                    wide.join(", ")
                )
            });
            let front = Front {
                tx: tx.clone(),
                rtu: false,
                _place: None,
                last: None,
            };
            let masters = Arc::new(Semaphore::new(MAX_MASTERS));
            let idle = Duration::from_secs(c.master_idle_s.into());
            let task = tokio::spawn(async move {
                // Dropped (the task aborted): every listener's task ends.
                let mut set = tokio::task::JoinSet::new();
                for l in listeners {
                    set.spawn(serve_tcp(
                        l,
                        front.clone(),
                        masters.clone(),
                        idle,
                        tx.clone(),
                    ));
                }
                while set.join_next().await.is_some() {}
            });
            Ok(Slave::new(rx, task, false, note))
        }
        Conn::SerialSlave(c) => {
            if !serial_path_ok(&c.serial_port) {
                return Err(DriverError::Transport(format!(
                    "serial_port {:?}: not a serial device path",
                    c.serial_port
                )));
            }
            let b = serial_builder(
                &c.serial_port,
                c.baud_rate,
                c.data_bits,
                c.stop_bits,
                c.parity,
            );
            let stream = tokio_serial::SerialStream::open(&b)
                .map_err(|e| DriverError::Transport(format!("open {}: {e}", c.serial_port)))?;
            Ok(Slave::rtu(stream, tx, rx))
        }
        Conn::Ip(_) | Conn::Serial(_) => {
            Err(DriverError::Transport("not a slave connection".to_owned()))
        }
    }
}

/// `EAFNOSUPPORT`: std has no `ErrorKind` for it.
#[cfg(unix)]
const EAFNOSUPPORT: i32 = libc::EAFNOSUPPORT;
/// `WSAEAFNOSUPPORT`.
#[cfg(not(unix))]
const EAFNOSUPPORT: i32 = 10047;

/// A bind error that says the host lacks the address, or its whole
/// address family (an IPv6-disabled Linux host binding `::1` for
/// `localhost`): that address is left out. Any other error (the port in
/// use, no permission) fails the connection.
fn host_lacks(e: &std::io::Error) -> bool {
    e.kind() == std::io::ErrorKind::AddrNotAvailable || e.raw_os_error() == Some(EAFNOSUPPORT)
}

/// Bind `addr`, waiting up to [`BIND_WAIT`] while the port is in use.
async fn bind(addr: SocketAddr) -> std::io::Result<tokio::net::TcpListener> {
    let deadline = Instant::now() + BIND_WAIT;
    loop {
        match tokio::net::TcpListener::bind(addr).await {
            Err(e) if e.kind() == std::io::ErrorKind::AddrInUse && Instant::now() < deadline => {
                tokio::time::sleep(Duration::from_millis(50)).await;
            }
            r => return r,
        }
    }
}

/// Serve the masters of one listener; `masters` holds the places of the
/// whole connection ([`MAX_MASTERS`]); a master idle for `idle` is closed.
async fn serve_tcp(
    listener: tokio::net::TcpListener,
    front: Front,
    masters: Arc<Semaphore>,
    idle: Duration,
    down: mpsc::Sender<Msg>,
) {
    use tokio_modbus::server::tcp::Server;
    let on_connected = |stream: tokio::net::TcpStream, addr: SocketAddr| {
        let front = front.clone();
        let masters = masters.clone();
        async move {
            let Ok(place) = masters.try_acquire_owned() else {
                // Dropping the stream closes it; the listener goes on.
                debug!(%addr, "master refused: {MAX_MASTERS} masters connected");
                return Ok(None);
            };
            let stream = Idle::new(stream, idle);
            let front = Front {
                _place: Some(Arc::new(place)),
                last: Some(stream.last.clone()),
                ..front
            };
            Ok(Some((front, stream)))
        }
    };
    let why = match Server::new(listener)
        .serve(&on_connected, |e| debug!("slave connection: {e}"))
        .await
    {
        Ok(()) => "listener closed".to_owned(),
        Err(e) => format!("listener: {e}"),
    };
    let _ = down.send(Msg::Down(why)).await;
}

async fn serve_rtu(stream: tokio_serial::SerialStream, front: Front, down: mpsc::Sender<Msg>) {
    let why = match tokio_modbus::server::rtu::Server::new(stream)
        .serve_forever(front)
        .await
    {
        Ok(()) => "serial port closed".to_owned(),
        Err(e) => format!("serial port: {e}"),
    };
    let _ = down.send(Msg::Down(why)).await;
}

/// `true` → 1.
fn bit(on: bool) -> u16 {
    u16::from(on)
}

impl Slave {
    fn new(rx: mpsc::Receiver<Msg>, task: JoinHandle<()>, rtu: bool, note: Option<String>) -> Self {
        Slave {
            rx,
            task,
            rtu,
            note,
            pending: None,
            words: HashMap::new(),
            points: Vec::new(),
            cover: HashMap::new(),
            units: BTreeMap::new(),
            changed: Vec::new(),
            outcomes: Vec::new(),
        }
    }

    /// A slave serving RTU on `stream`.
    fn rtu(
        stream: tokio_serial::SerialStream,
        tx: mpsc::Sender<Msg>,
        rx: mpsc::Receiver<Msg>,
    ) -> Self {
        let front = Front {
            tx: tx.clone(),
            rtu: true,
            _place: None,
            last: None,
        };
        let task = tokio::spawn(serve_rtu(stream, front, tx));
        Slave::new(rx, task, true, None)
    }

    pub(crate) fn note(&self) -> Option<String> {
        self.note.clone()
    }

    /// The changes since the last call, each point once with its last
    /// value (in the order of those last changes): a drain publishes the
    /// final state, never an intermediate one.
    pub(crate) fn take_changed(&mut self) -> Vec<Changed> {
        let mut seen = HashSet::new();
        let mut last: Vec<Changed> = std::mem::take(&mut self.changed)
            .into_iter()
            .rev()
            .filter(|(dev, id, _)| seen.insert((dev.clone(), id.clone())))
            .collect();
        last.reverse();
        last
    }

    pub(crate) fn take_outcomes(&mut self) -> Vec<Outcome> {
        std::mem::take(&mut self.outcomes)
    }

    /// The devices and points to serve; the value of every point that has
    /// one goes to `changed`. A word keeps only the bits that points staying
    /// in the plan read; the bits of points new to it (added, or with other
    /// params or another unit) are dropped: such a point has no value until
    /// the tree sets one (the framework writes the tree's next). Refuses
    /// (`(device, why)`) a unit-0 device on RTU.
    pub(crate) fn serve(
        &mut self,
        devs: &[Served<'_, crate::ModbusDriver>],
    ) -> Vec<(String, String)> {
        let before: HashMap<(String, PointId), (u8, Point)> = self
            .points
            .drain(..)
            .map(|p| ((p.dev, p.id), (p.unit, p.point)))
            .collect();
        self.cover.clear();
        self.units.clear();
        let mut refused = Vec::new();
        let mut fresh = HashSet::new();
        for d in devs {
            let unit = d.dev.unit;
            if self.rtu && unit == 0 {
                refused.push((d.name.to_owned(), NO_RTU_BROADCAST.to_owned()));
                continue;
            }
            self.units.entry(unit).or_insert_with(|| d.name.to_owned());
            for (id, p) in d.points {
                let i = self.points.len();
                let key = (d.name.to_owned(), id.clone());
                if before.get(&key) != Some(&(unit, p.clone())) {
                    fresh.insert(i);
                }
                for a in span(p) {
                    self.cover.entry((unit, p.table, a)).or_default().push(i);
                }
                self.points.push(ServedPoint {
                    dev: d.name.to_owned(),
                    id: id.clone(),
                    unit,
                    point: p.clone(),
                });
            }
        }
        let (cover, points) = (&self.cover, &self.points);
        self.words.retain(|a, w| {
            let kept = cover.get(a).map_or(0, |pts| {
                pts.iter()
                    .filter(|i| !fresh.contains(*i))
                    .fold(0, |m, &i| m | needs(&points[i].point))
            });
            w.known &= kept;
            w.v &= w.known;
            w.known != 0
        });
        for i in 0..self.points.len() {
            self.push_changed(i);
        }
        refused
    }

    /// A value set in the tree: `v` goes into the served words of `p` (a
    /// bit point: its bit only, which becomes known). Refused, changing
    /// nothing, for a unit not served (a refused device) and when a point
    /// overlapping `p` could not decode the new words (ruling P25).
    pub(crate) fn set(&mut self, unit: u8, p: &Point, v: &Value) -> Result<(), DriverError> {
        if !self.units.contains_key(&unit) {
            return Err(DriverError::Point(format!("unit {unit} is not served")));
        }
        let want_bool = || match v {
            Value::Bool(b) => Ok(*b),
            _ => Err(DriverError::Point("expected true or false".into())),
        };
        let words = if p.table.is_bits() {
            vec![Word::whole(bit(want_bool()?))]
        } else if p.dtype == DType::Binary {
            let (and, or) = codec::bit_masks(p.bit, want_bool()?);
            let cur = self
                .word((unit, p.table, p.addr))
                .unwrap_or(Word { v: 0, known: 0 });
            vec![Word {
                v: codec::apply_masks(cur.v, and, or),
                known: cur.known | needs(p),
            }]
        } else {
            codec::encode(p.dtype, v, p.regs, p.scale, p.offset)
                .map_err(|e| DriverError::Point(e.to_string()))?
                .into_iter()
                .map(Word::whole)
                .collect()
        };
        self.put(unit, p.table, p.addr, &words, false).map_err(|_| {
            DriverError::Point("an overlapping point cannot hold the words of that value".into())
        })
    }

    /// Wait for the next master request (cancel-safe: only the receipt is
    /// awaited, and a request is kept as soon as it is taken). One whose
    /// master stopped waiting is dropped: it got busy, and a late write
    /// would change what it was told was not changed.
    pub(crate) async fn remote(&mut self) -> Result<(), DriverError> {
        if self.pending.is_some() {
            return Ok(());
        }
        loop {
            match self.rx.recv().await {
                Some(Msg::Ask(a)) if a.reply.is_closed() => {
                    debug!(unit = a.unit, "request dropped: its master gave up");
                }
                Some(Msg::Ask(a)) => {
                    self.pending = Some(a);
                    return Ok(());
                }
                Some(Msg::Down(why)) => return Err(DriverError::Transport(why)),
                None => return Err(DriverError::Transport("server stopped".into())),
            }
        }
    }

    /// Answer the request [`Slave::remote`] took. One received before
    /// `since` (the start of the plan in force) was asked of an older plan:
    /// busy, nothing applied. The reply goes out in [`Remote::done`].
    pub(crate) fn apply_remote(&mut self, since: Instant) -> Remote {
        let idle = Remote {
            dev: None,
            done: None,
        };
        let Some(Ask {
            unit,
            req,
            at,
            reply,
        }) = self.pending.take()
        else {
            return idle;
        };
        if reply.is_closed() {
            debug!(unit, "request dropped: its master gave up");
            return idle;
        }
        let dev = self.units.get(&unit).cloned();
        let broadcast = self.rtu && unit == 0;
        let answer = if at < since {
            debug!(unit, "request of an older plan: busy");
            self.busy()
        } else if broadcast {
            // A broadcast write is a request to this slave (counted on the
            // connection), though never answered.
            match self.broadcast(req) {
                Some(0) => self.outcomes.push(Outcome::Exception(at.elapsed())),
                Some(_) => self.outcomes.push(Outcome::Reply(at.elapsed())),
                None => {}
            }
            Ok(None)
        } else {
            self.answer(unit, req)
        };
        match &answer {
            Ok(Some(_)) => self.outcomes.push(Outcome::Reply(at.elapsed())),
            Err(_) => self.outcomes.push(Outcome::Exception(at.elapsed())),
            // Not ours to answer (RTU), or a broadcast (counted above).
            Ok(None) => {}
        }
        Remote {
            dev,
            done: Some(Box::new(move || {
                let _ = reply.send(answer);
            })),
        }
    }

    /// Busy: an exception on TCP, silence on RTU.
    fn busy(&self) -> Answer {
        if self.rtu {
            Ok(None)
        } else {
            Err(ExceptionCode::ServerDeviceBusy)
        }
    }

    /// An RTU broadcast: a write goes to every served unit that takes it
    /// (how many: `Some(n)`); a read is ignored (`None`). Never answered.
    fn broadcast(&mut self, req: Request<'static>) -> Option<usize> {
        if !is_write(&req) {
            return None;
        }
        let units: Vec<u8> = self.units.keys().copied().collect();
        let mut applied = 0;
        for u in units {
            match self.apply(u, req.clone()) {
                Ok(_) => applied += 1,
                Err(e) => debug!(unit = u, "broadcast not applied: {e:?}"),
            }
        }
        Some(applied)
    }

    fn answer(&mut self, unit: u8, req: Request<'static>) -> Answer {
        if !self.units.contains_key(&unit) {
            return if self.rtu {
                Ok(None)
            } else {
                Err(ExceptionCode::GatewayTargetDevice)
            };
        }
        self.apply(unit, req).map(Some)
    }

    /// One request to a served unit.
    fn apply(&mut self, unit: u8, req: Request<'static>) -> Result<Response, ExceptionCode> {
        use Request as R;
        let bits = |w: Vec<u16>| w.into_iter().map(|b| b != 0).collect::<Vec<_>>();
        Ok(match req {
            R::ReadCoils(a, n) => Response::ReadCoils(bits(self.read(unit, Table::Coil, a, n)?)),
            R::ReadDiscreteInputs(a, n) => {
                Response::ReadDiscreteInputs(bits(self.read(unit, Table::Discrete, a, n)?))
            }
            R::ReadHoldingRegisters(a, n) => {
                Response::ReadHoldingRegisters(self.read(unit, Table::Holding, a, n)?)
            }
            R::ReadInputRegisters(a, n) => {
                Response::ReadInputRegisters(self.read(unit, Table::Input, a, n)?)
            }
            R::WriteSingleCoil(a, on) => {
                self.write(unit, Table::Coil, a, &[bit(on)])?;
                Response::WriteSingleCoil(a, on)
            }
            R::WriteMultipleCoils(a, on) => {
                let w: Vec<u16> = on.iter().map(|b| bit(*b)).collect();
                self.write(unit, Table::Coil, a, &w)?;
                Response::WriteMultipleCoils(a, len(&w))
            }
            R::WriteSingleRegister(a, w) => {
                self.write(unit, Table::Holding, a, &[w])?;
                Response::WriteSingleRegister(a, w)
            }
            R::WriteMultipleRegisters(a, w) => {
                self.write(unit, Table::Holding, a, &w)?;
                Response::WriteMultipleRegisters(a, len(&w))
            }
            R::MaskWriteRegister(a, and, or) => {
                self.check_write(unit, Table::Holding, a, 1)?;
                let k = (unit, Table::Holding, a);
                let cur = self
                    .word(k)
                    .filter(|w| w.read(self.need_at(k)).is_some())
                    .ok_or(ExceptionCode::ServerDeviceFailure)?;
                // The bits the mask writes become known.
                let w = Word {
                    v: codec::apply_masks(cur.v, and, or),
                    known: cur.known | !and,
                };
                self.put(unit, Table::Holding, a, &[w], true)?;
                Response::MaskWriteRegister(a, and, or)
            }
            _ => return Err(ExceptionCode::IllegalFunction),
        })
    }

    /// A served word, `None` while no bit of it is known.
    fn word(&self, a: Addr) -> Option<Word> {
        self.words.get(&a).copied()
    }

    /// The bits of the word at `a` that its points read.
    fn need_at(&self, a: Addr) -> u16 {
        self.cover.get(&a).map_or(0, |pts| {
            pts.iter().fold(0, |m, &i| m | needs(&self.points[i].point))
        })
    }

    /// `n` words or bits from `a`, every one covered by a point and with the
    /// bits its points read known.
    fn read(&self, unit: u8, table: Table, a: u16, n: u16) -> Result<Vec<u16>, ExceptionCode> {
        let max = if table.is_bits() {
            codec::MAX_BITS
        } else {
            codec::MAX_REGISTERS
        };
        if n == 0 || n > max {
            return Err(ExceptionCode::IllegalDataValue);
        }
        let addrs: Vec<u16> = range(a, n)
            .ok_or(ExceptionCode::IllegalDataAddress)?
            .collect();
        if addrs
            .iter()
            .any(|x| !self.cover.contains_key(&(unit, table, *x)))
        {
            return Err(ExceptionCode::IllegalDataAddress);
        }
        addrs
            .iter()
            .map(|x| {
                let k = (unit, table, *x);
                self.word(k)
                    .and_then(|w| w.read(self.need_at(k)))
                    .ok_or(ExceptionCode::ServerDeviceFailure)
            })
            .collect()
    }

    /// A master may write `n` words or bits from `a`: each is covered, and
    /// every point covering one is `writable_by_master`.
    fn check_write(&self, unit: u8, table: Table, a: u16, n: u16) -> Result<(), ExceptionCode> {
        let max = if table.is_bits() {
            MAX_WRITE_BITS
        } else {
            codec::MAX_WRITE_REGISTERS
        };
        if n == 0 || n > max {
            return Err(ExceptionCode::IllegalDataValue);
        }
        let addrs = range(a, n).ok_or(ExceptionCode::IllegalDataAddress)?;
        let mut read_only = false;
        for x in addrs {
            let Some(pts) = self.cover.get(&(unit, table, x)) else {
                return Err(ExceptionCode::IllegalDataAddress);
            };
            read_only |= pts
                .iter()
                .any(|&i| !self.points[i].point.writable_by_master);
        }
        if read_only {
            return Err(ExceptionCode::IllegalDataValue);
        }
        Ok(())
    }

    /// A master write of `w` from `a`, checked first (see [`Slave::put`]):
    /// nothing changes on a refusal.
    fn write(&mut self, unit: u8, table: Table, a: u16, w: &[u16]) -> Result<(), ExceptionCode> {
        let n = u16::try_from(w.len()).map_err(|_| ExceptionCode::IllegalDataValue)?;
        self.check_write(unit, table, a, n)?;
        let words: Vec<Word> = w.iter().map(|v| Word::whole(*v)).collect();
        self.put(unit, table, a, &words, true)
    }

    /// Store `w` from `a` once every point it touches decodes the words as
    /// they would be, to a finite value where it is a float (ruling P25); a
    /// point that would still lack a bit it reads has no value yet and is
    /// not checked. Then each point it touches goes to `changed` (a
    /// master's write is logged by point). Nothing changes on a refusal.
    fn put(
        &mut self,
        unit: u8,
        table: Table,
        a: u16,
        w: &[Word],
        master: bool,
    ) -> Result<(), ExceptionCode> {
        let new: HashMap<Addr, Word> = (a..=u16::MAX)
            .zip(w)
            .map(|(x, v)| ((unit, table, x), *v))
            .collect();
        let n = len(w);
        for i in self.covering(unit, table, a, n) {
            let p = &self.points[i];
            if let Some(Err(_)) = self.value_with(p.unit, &p.point, &new) {
                return Err(ExceptionCode::IllegalDataValue);
            }
        }
        self.words.extend(new);
        self.changed_at(unit, table, a, n, master);
        Ok(())
    }

    /// Every point covering `n` words or bits from `a` goes to `changed`
    /// (once); a master's write is logged by point.
    fn changed_at(&mut self, unit: u8, table: Table, a: u16, n: u16, master: bool) {
        for i in self.covering(unit, table, a, n) {
            if master {
                let p = &self.points[i];
                info!(point = %format!("{}/{}", p.dev, p.id), "written by a master");
            }
            self.push_changed(i);
        }
    }

    /// The points covering `n` words or bits from `a`, each once.
    fn covering(&self, unit: u8, table: Table, a: u16, n: u16) -> Vec<usize> {
        let mut hit: Vec<usize> = range(a, n)
            .into_iter()
            .flatten()
            .filter_map(|x| self.cover.get(&(unit, table, x)))
            .flatten()
            .copied()
            .collect();
        hit.sort_unstable();
        hit.dedup();
        hit
    }

    /// The point's value to `changed`; a point without one (a word never
    /// set) is left out.
    fn push_changed(&mut self, i: usize) {
        let p = &self.points[i];
        match self.value_with(p.unit, &p.point, &HashMap::new()) {
            None => {}
            Some(Ok(v)) => self.changed.push((p.dev.clone(), p.id.clone(), v)),
            // Not from a write or a set (both are checked first, `put`):
            // a point that a re-plan put over words it cannot decode (an
            // edit to another data type) keeps no value until set.
            Some(Err(e)) => debug!(point = %format!("{}/{}", p.dev, p.id), "not decoded: {e}"),
        }
    }

    /// The value of `p` with the words of `over` in place of the served
    /// ones: `None` while a bit it reads is unknown; an error for words its
    /// data type cannot hold or a float that is not finite.
    fn value_with(
        &self,
        unit: u8,
        p: &Point,
        over: &HashMap<Addr, Word>,
    ) -> Option<Result<Value, codec::CodecError>> {
        let need = needs(p);
        let w: Option<Vec<u16>> = span(p)
            .map(|x| {
                let k = (unit, p.table, x);
                over.get(&k)
                    .copied()
                    .or_else(|| self.word(k))
                    .and_then(|w| w.read(need))
            })
            .collect();
        let w = w?;
        if p.table.is_bits() {
            return Some(Ok(Value::Bool(w.first().is_some_and(|b| *b != 0))));
        }
        Some(
            codec::decode(p.dtype, &w, p.bit, p.scale, p.offset).and_then(|v| match v {
                Value::Float(f) if !f.is_finite() => Err(codec::CodecError::OutOfRange),
                v => Ok(v),
            }),
        )
    }
}

/// A write function code (a broadcast applies these only).
fn is_write(r: &Request<'_>) -> bool {
    matches!(
        r,
        Request::WriteSingleCoil(..)
            | Request::WriteMultipleCoils(..)
            | Request::WriteSingleRegister(..)
            | Request::WriteMultipleRegisters(..)
            | Request::MaskWriteRegister(..)
    )
}

/// `n` addresses from `a`, `None` when they run past 65535.
fn range(a: u16, n: u16) -> Option<impl Iterator<Item = u16>> {
    (u32::from(a) + u32::from(n) <= 65_536).then(|| (0..n).map(move |i| a + i))
}

/// The addresses a point occupies.
fn span(p: &Point) -> impl Iterator<Item = u16> {
    let (a, n) = (p.addr, p.words());
    (0..n).filter_map(move |i| a.checked_add(i))
}

fn len<T>(w: &[T]) -> u16 {
    u16::try_from(w.len()).unwrap_or(u16::MAX)
}

#[cfg(all(test, unix))]
mod pty_tests {
    use super::*;
    use crate::ModbusDriver;
    use std::sync::{Arc, Mutex};
    use tokio_modbus::client::rtu;
    use tokio_modbus::prelude::{Reader, Writer};
    use wyrm_link_sdk::driver::Params;

    fn params(kv: &[(&str, Value)]) -> Value {
        Value::Map(
            kv.iter()
                .map(|(k, v)| ((*k).to_owned(), v.clone()))
                .collect(),
        )
    }

    fn holding(addr: u64, master_writes: bool) -> Point {
        Point::from_value(&params(&[
            ("table", "holding".into()),
            ("addr", Value::UInt(addr)),
            ("writable_by_master", Value::Bool(master_writes)),
        ]))
        .unwrap()
    }

    /// RTU framing on a pseudo-terminal pair (Linux and macOS): the slave
    /// serves unit 3, takes a master's write to a writable point, refuses
    /// one to a read-only point (exception 3), and stays silent for a unit
    /// it does not serve (another slave's on the bus).
    #[tokio::test(flavor = "multi_thread")]
    async fn rtu_slave_answers_over_a_pty() {
        let (port, other_end) = tokio_serial::SerialStream::pair().expect("a pty pair");
        let (tx, rx) = mpsc::channel(QUEUE);
        let mut s = Slave::rtu(port, tx, rx);
        let dev = crate::Device::from_value(&params(&[("unit", Value::UInt(3))])).unwrap();
        let points = BTreeMap::from([
            ("sp".to_owned(), holding(10, true)),
            ("ro".to_owned(), holding(11, false)),
        ]);
        let served: [Served<'_, ModbusDriver>; 1] = [Served {
            name: "d3",
            dev: &dev,
            points: &points,
        }];
        s.serve(&served);
        s.set(3, &points["sp"], &Value::UInt(0)).unwrap();
        s.set(3, &points["ro"], &Value::UInt(42)).unwrap();
        s.take_changed();
        // The owner task's part: apply each request, then answer it.
        let changed = Arc::new(Mutex::new(Vec::new()));
        let seen = changed.clone();
        let owner = tokio::spawn(async move {
            loop {
                let r = next(&mut s).await;
                seen.lock().unwrap().extend(s.take_changed());
                if let Some(done) = r.done {
                    done();
                }
            }
        });
        let mut m = rtu::attach_slave(other_end, tokio_modbus::Slave(3));
        let t = Duration::from_secs(2);
        let read = tokio::time::timeout(t, m.read_holding_registers(10, 2)).await;
        assert_eq!(read.unwrap().unwrap(), Ok(vec![0, 42]));
        let write = tokio::time::timeout(t, m.write_single_register(10, 7)).await;
        assert_eq!(write.unwrap().unwrap(), Ok(()));
        assert_eq!(
            changed.lock().unwrap().as_slice(),
            &[("d3".to_owned(), "sp".to_owned(), Value::UInt(7))]
        );
        let refused = tokio::time::timeout(t, m.write_single_register(11, 1)).await;
        assert_eq!(
            refused.unwrap().unwrap(),
            Err(ExceptionCode::IllegalDataValue)
        );
        let read = tokio::time::timeout(t, m.read_holding_registers(10, 2)).await;
        assert_eq!(read.unwrap().unwrap(), Ok(vec![7, 42]));
        // unit 5 is not served here: no reply at all
        tokio_modbus::slave::SlaveContext::set_slave(&mut m, tokio_modbus::Slave(5));
        let silent =
            tokio::time::timeout(Duration::from_millis(300), m.read_holding_registers(10, 1)).await;
        assert!(silent.is_err(), "unit 5 answered: {silent:?}");
        owner.abort();
    }

    /// The owner task's part: take the next master request and answer it.
    async fn next(s: &mut Slave) -> Remote {
        s.remote().await.expect("a request");
        // a plan in force since before every request of the test
        let since = Instant::now()
            .checked_sub(Duration::from_secs(60))
            .unwrap_or_else(Instant::now);
        s.apply_remote(since)
    }

    fn served(s: &mut Slave, devs: &[(&str, u8)], points: &BTreeMap<String, Point>) {
        let cfgs: Vec<crate::Device> = devs
            .iter()
            .map(|(_, u)| {
                crate::Device::from_value(&params(&[("unit", Value::UInt((*u).into()))])).unwrap()
            })
            .collect();
        let served: Vec<Served<'_, ModbusDriver>> = devs
            .iter()
            .zip(&cfgs)
            .map(|((name, _), dev)| Served { name, dev, points })
            .collect();
        let _ = s.serve(&served);
    }

    fn ask(unit: u8, req: Request<'static>) -> (Msg, oneshot::Receiver<Answer>) {
        let (reply, answer) = oneshot::channel();
        let at = Instant::now();
        (
            Msg::Ask(Ask {
                unit,
                req,
                at,
                reply,
            }),
            answer,
        )
    }

    /// Ruling 3 of the review: a write whose master already got `busy` (its
    /// `Front` stopped waiting) is never applied later.
    #[tokio::test]
    async fn a_write_whose_master_gave_up_is_not_applied() {
        let (tx, rx) = mpsc::channel(QUEUE);
        let mut s = Slave::new(rx, tokio::spawn(async {}), false, None);
        let points = BTreeMap::from([("sp".to_owned(), holding(10, true))]);
        served(&mut s, &[("d1", 1)], &points);
        let (write, gone) = ask(1, Request::WriteSingleRegister(10, 9));
        drop(gone);
        let (read, mut answer) = ask(1, Request::ReadHoldingRegisters(10, 1));
        tx.send(write).await.unwrap();
        tx.send(read).await.unwrap();
        let mut got = None;
        for _ in 0..2 {
            if let Some(done) = next(&mut s).await.done {
                done();
            }
            if let Ok(a) = answer.try_recv() {
                got = Some(a);
                break;
            }
        }
        // nothing was written: the point has no value yet
        assert_eq!(got, Some(Err(ExceptionCode::ServerDeviceFailure)));
        assert!(s.take_changed().is_empty());
    }

    /// Ruling P26: an RTU broadcast (unit 0) write goes to every served unit
    /// that has the address, with no reply; a broadcast read is ignored.
    #[tokio::test(flavor = "multi_thread")]
    async fn rtu_broadcast_writes_every_unit() {
        let (port, other_end) = tokio_serial::SerialStream::pair().expect("a pty pair");
        let (tx, rx) = mpsc::channel(QUEUE);
        let mut s = Slave::rtu(port, tx, rx);
        let points = BTreeMap::from([("sp".to_owned(), holding(10, true))]);
        served(&mut s, &[("d3", 3), ("d4", 4)], &points);
        let changed = Arc::new(Mutex::new(Vec::new()));
        let seen = changed.clone();
        let owner = tokio::spawn(async move {
            loop {
                let r = next(&mut s).await;
                seen.lock().unwrap().extend(s.take_changed());
                if let Some(done) = r.done {
                    done();
                }
            }
        });
        let mut m = rtu::attach_slave(other_end, tokio_modbus::Slave(0));
        let quiet = Duration::from_millis(300);
        let w = tokio::time::timeout(quiet, m.write_single_register(10, 5)).await;
        assert!(w.is_err(), "a broadcast is not answered: {w:?}");
        let r = tokio::time::timeout(quiet, m.read_holding_registers(10, 1)).await;
        assert!(r.is_err(), "a broadcast read is ignored: {r:?}");
        for unit in [3, 4] {
            tokio_modbus::slave::SlaveContext::set_slave(&mut m, tokio_modbus::Slave(unit));
            let r = tokio::time::timeout(Duration::from_secs(2), m.read_holding_registers(10, 1));
            assert_eq!(r.await.unwrap().unwrap(), Ok(vec![5]), "unit {unit}");
        }
        let mut c = changed.lock().unwrap().clone();
        c.sort_by(|a, b| a.0.cmp(&b.0));
        assert_eq!(
            c,
            [
                ("d3".to_owned(), "sp".to_owned(), Value::UInt(5)),
                ("d4".to_owned(), "sp".to_owned(), Value::UInt(5)),
            ]
        );
        owner.abort();
    }

    /// Review finding 10: a unit-0 device under `serial_slave` is the RTU
    /// broadcast address; the server refuses it (the device shows `Failed`)
    /// and serves the others.
    #[tokio::test(flavor = "multi_thread")]
    async fn rtu_unit_0_is_refused() {
        let (port, _other_end) = tokio_serial::SerialStream::pair().expect("a pty pair");
        let (tx, rx) = mpsc::channel(QUEUE);
        let mut s = Slave::rtu(port, tx, rx);
        let points = BTreeMap::from([("sp".to_owned(), holding(10, true))]);
        let cfgs: Vec<crate::Device> = [0u64, 3]
            .iter()
            .map(|u| crate::Device::from_value(&params(&[("unit", Value::UInt(*u))])).unwrap())
            .collect();
        let served: Vec<Served<'_, ModbusDriver>> = ["d0", "d3"]
            .iter()
            .zip(&cfgs)
            .map(|(name, dev)| Served {
                name,
                dev,
                points: &points,
            })
            .collect();
        assert_eq!(
            s.serve(&served),
            vec![("d0".to_owned(), NO_RTU_BROADCAST.to_owned())]
        );
        assert_eq!(s.units.keys().copied().collect::<Vec<_>>(), vec![3]);
    }

    /// Review finding 6: a request received before the plan in force began
    /// (a re-plan came while it waited) answers busy and changes nothing.
    #[tokio::test]
    async fn a_request_of_an_older_plan_is_busy() {
        let (tx, rx) = mpsc::channel(QUEUE);
        let mut s = Slave::new(rx, tokio::spawn(async {}), false, None);
        let points = BTreeMap::from([("sp".to_owned(), holding(10, true))]);
        served(&mut s, &[("d1", 1)], &points);
        let (write, mut answer) = ask(1, Request::WriteSingleRegister(10, 9));
        tx.send(write).await.unwrap();
        s.remote().await.unwrap();
        // the plan in force began after the request came
        let r = s.apply_remote(Instant::now() + Duration::from_millis(1));
        r.done.expect("answered")();
        assert_eq!(answer.try_recv(), Ok(Err(ExceptionCode::ServerDeviceBusy)));
        assert!(s.take_changed().is_empty());
        assert_eq!(s.word((1, Table::Holding, 10)), None, "not applied");
    }

    /// N1: one drain gives each point once, with its last value (a re-plan
    /// publishes the final state, no intermediate one).
    #[tokio::test]
    async fn take_changed_keeps_the_last_value_per_point() {
        let (_tx, rx) = mpsc::channel(QUEUE);
        let mut s = Slave::new(rx, tokio::spawn(async {}), false, None);
        let points = BTreeMap::from([("sp".to_owned(), holding(10, true))]);
        served(&mut s, &[("d1", 1)], &points);
        s.set(1, &points["sp"], &Value::UInt(1)).unwrap();
        s.set(1, &points["sp"], &Value::UInt(2)).unwrap();
        assert_eq!(
            s.take_changed(),
            vec![("d1".to_owned(), "sp".to_owned(), Value::UInt(2))]
        );
    }

    /// N5: a value set for a unit the slave does not serve (a refused
    /// unit-0 device on RTU) is an error, not stored.
    #[tokio::test]
    async fn a_set_for_a_unit_not_served_is_refused() {
        let (_tx, rx) = mpsc::channel(QUEUE);
        let mut s = Slave::new(rx, tokio::spawn(async {}), true, None);
        let points = BTreeMap::from([("sp".to_owned(), holding(10, true))]);
        served(&mut s, &[("d0", 0), ("d3", 3)], &points);
        assert!(s.set(0, &points["sp"], &Value::UInt(1)).is_err());
        assert_eq!(s.word((0, Table::Holding, 10)), None);
        assert!(s.set(3, &points["sp"], &Value::UInt(1)).is_ok());
    }

    /// R1: a missing address or address family leaves that address out;
    /// a port in use or no permission fails the connection.
    #[test]
    fn bind_errors_that_leave_an_address_out() {
        use std::io::{Error, ErrorKind};
        let no_family = Error::from_raw_os_error(EAFNOSUPPORT);
        // the kind alone (the rule before R1) does not catch it
        assert_ne!(no_family.kind(), ErrorKind::AddrNotAvailable);
        assert!(host_lacks(&no_family));
        assert!(host_lacks(&Error::from(ErrorKind::AddrNotAvailable)));
        assert!(!host_lacks(&Error::from(ErrorKind::AddrInUse)));
        assert!(!host_lacks(&Error::from(ErrorKind::PermissionDenied)));
        // as the OS reports them (the module runs on unix only)
        assert!(host_lacks(&Error::from_raw_os_error(libc::EADDRNOTAVAIL)));
        assert!(!host_lacks(&Error::from_raw_os_error(libc::EADDRINUSE)));
        assert!(!host_lacks(&Error::from_raw_os_error(libc::EACCES)));
    }

    /// N6: an RTU broadcast write is counted in the connection's
    /// diagnostics (one request), though it gets no reply.
    #[tokio::test]
    async fn a_broadcast_write_is_counted() {
        let (tx, rx) = mpsc::channel(QUEUE);
        let mut s = Slave::new(rx, tokio::spawn(async {}), true, None);
        let points = BTreeMap::from([("sp".to_owned(), holding(10, true))]);
        served(&mut s, &[("d3", 3), ("d4", 4)], &points);
        let (write, mut answer) = ask(0, Request::WriteSingleRegister(10, 5));
        tx.send(write).await.unwrap();
        let r = next(&mut s).await;
        assert_eq!(r.dev, None, "the connection's count");
        r.done.expect("answered")();
        assert_eq!(answer.try_recv(), Ok(Ok(None)), "no reply");
        let out = s.take_outcomes();
        assert_eq!(out.len(), 1, "{out:?}");
        assert!(matches!(out[0], Outcome::Reply(_)), "{out:?}");
    }
}
