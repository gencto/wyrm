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
//! * An address no point covers answers exception 2 (illegal data address);
//!   a write touching a point without `writable_by_master` answers
//!   exception 3 (illegal data value), and so does a read or write of more
//!   registers or bits than one request carries. A refused request changes
//!   nothing. Function codes other than FC1–6, 15, 16 and 22 answer
//!   exception 1.
//! * A unit no device serves: no reply on RTU (another slave on the bus may
//!   have it; unit 0 is the broadcast, which needs no reply and is not
//!   applied), exception 0x0B (gateway target failed to respond) on TCP.
//! * A master write is logged at info with the points it changed (never the
//!   value) and counted in the diagnostics; it is not in the site's audit
//!   trail (no WYRM caller, ruling P4).

use crate::codec::{self, DType};
use crate::{serial_builder, serial_path_ok, Conn, Device, Plan, Point, Table};
use std::collections::{BTreeMap, HashMap};
use std::future::Future;
use std::net::SocketAddr;
use std::pin::Pin;
use std::time::Duration;
use tokio::sync::{mpsc, oneshot};
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
}

impl Service for Front {
    type Request = SlaveRequest<'static>;
    type Response = Option<Response>;
    type Exception = ExceptionCode;
    type Future = Pin<Box<dyn Future<Output = Answer> + Send>>;

    fn call(&self, req: SlaveRequest<'static>) -> Self::Future {
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
    /// Served words; a coil or discrete input is 0 or 1. Absent = 0.
    words: HashMap<Addr, u16>,
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
            let addr: SocketAddr = tokio::net::lookup_host(&target)
                .await
                .map_err(|e| DriverError::Transport(format!("resolve {target}: {e}")))?
                .next()
                .ok_or_else(|| DriverError::Transport(format!("resolve {target}: no address")))?;
            let listener = tokio::net::TcpListener::bind(addr)
                .await
                .map_err(|e| DriverError::Transport(format!("listen on {target}: {e}")))?;
            let local = listener
                .local_addr()
                .map_err(|e| DriverError::Transport(format!("listen on {target}: {e}")))?;
            // Judged on the address bound, not on the name given.
            let note = (!local.ip().is_loopback()).then(|| {
                format!(
                    "listening on {local}, not loopback: Modbus has no authentication, any \
                     host that reaches this port reads the served values and writes those a \
                     master may write"
                )
            });
            let front = Front {
                tx: tx.clone(),
                rtu: false,
            };
            let task = tokio::spawn(serve_tcp(listener, front, tx));
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

async fn serve_tcp(listener: tokio::net::TcpListener, front: Front, down: mpsc::Sender<Msg>) {
    use tokio_modbus::server::tcp::{accept_tcp_connection, Server};
    let on_connected = |stream, addr: SocketAddr| {
        let front = front.clone();
        async move { accept_tcp_connection(stream, addr, move |_| Ok(Some(front.clone()))) }
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
        };
        let task = tokio::spawn(serve_rtu(stream, front, tx));
        Slave::new(rx, task, true, None)
    }

    pub(crate) fn note(&self) -> Option<String> {
        self.note.clone()
    }

    pub(crate) fn take_changed(&mut self) -> Vec<Changed> {
        std::mem::take(&mut self.changed)
    }

    pub(crate) fn take_outcomes(&mut self) -> Vec<Outcome> {
        std::mem::take(&mut self.outcomes)
    }

    /// The devices and points to serve; every point's value goes to
    /// `changed`. Values no point covers any more are dropped (a point
    /// added there later starts from 0).
    pub(crate) fn serve(&mut self, devs: &[Served<'_, crate::ModbusDriver>]) {
        self.points.clear();
        self.cover.clear();
        self.units.clear();
        for d in devs {
            let unit = d.dev.unit;
            self.units.entry(unit).or_insert_with(|| d.name.to_owned());
            for (id, p) in d.points {
                let i = self.points.len();
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
        let cover = &self.cover;
        self.words.retain(|a, _| cover.contains_key(a));
        for i in 0..self.points.len() {
            self.push_changed(i);
        }
    }

    /// A value set in the tree: `v` goes into the served words of `p`.
    pub(crate) fn set(&mut self, unit: u8, p: &Point, v: &Value) -> Result<(), DriverError> {
        let want_bool = || match v {
            Value::Bool(b) => Ok(*b),
            _ => Err(DriverError::Point("expected true or false".into())),
        };
        let words = if p.table.is_bits() {
            vec![bit(want_bool()?)]
        } else if p.dtype == DType::Binary {
            let (and, or) = codec::bit_masks(p.bit, want_bool()?);
            vec![codec::apply_masks(
                self.word((unit, p.table, p.addr)),
                and,
                or,
            )]
        } else {
            codec::encode(p.dtype, v, p.regs, p.scale, p.offset)
                .map_err(|e| DriverError::Point(e.to_string()))?
        };
        self.store(unit, p.table, p.addr, &words);
        self.changed_at(unit, p.table, p.addr, len(&words), false);
        Ok(())
    }

    /// The values of `plan`'s points as served.
    pub(crate) fn values(
        &self,
        dev: &Device,
        plan: &Plan,
    ) -> Vec<(PointId, Result<Value, DriverError>)> {
        plan.tables
            .iter()
            .flat_map(|t| t.members.iter())
            .map(|(id, p)| {
                let v = self
                    .decode(dev.unit, p)
                    .map_err(|e| DriverError::Point(e.to_string()));
                (id.clone(), v)
            })
            .collect()
    }

    /// Wait for the next master request and answer it (cancel-safe: only
    /// the receipt is awaited). The reply goes out in [`Remote::done`].
    pub(crate) async fn remote(&mut self) -> Result<Remote, DriverError> {
        let ask = match self.rx.recv().await {
            Some(Msg::Ask(a)) => a,
            Some(Msg::Down(why)) => return Err(DriverError::Transport(why)),
            None => return Err(DriverError::Transport("server stopped".into())),
        };
        let Ask {
            unit,
            req,
            at,
            reply,
        } = ask;
        let dev = self.units.get(&unit).cloned();
        let answer = self.answer(unit, req);
        match &answer {
            Ok(Some(_)) => self.outcomes.push(Outcome::Reply(at.elapsed())),
            Err(_) => self.outcomes.push(Outcome::Exception(at.elapsed())),
            // Not ours to answer (RTU).
            Ok(None) => {}
        }
        Ok(Remote {
            dev,
            done: Some(Box::new(move || {
                let _ = reply.send(answer);
            })),
        })
    }

    fn answer(&mut self, unit: u8, req: Request<'static>) -> Answer {
        if self.rtu && unit == 0 {
            // A broadcast: never answered (and not applied).
            return Ok(None);
        }
        if !self.units.contains_key(&unit) {
            return if self.rtu {
                Ok(None)
            } else {
                Err(ExceptionCode::GatewayTargetDevice)
            };
        }
        use Request as R;
        let bits = |w: Vec<u16>| w.into_iter().map(|b| b != 0).collect::<Vec<_>>();
        Ok(Some(match req {
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
                let cur = self.word((unit, Table::Holding, a));
                let w = codec::apply_masks(cur, and, or);
                self.write(unit, Table::Holding, a, &[w])?;
                Response::MaskWriteRegister(a, and, or)
            }
            _ => return Err(ExceptionCode::IllegalFunction),
        }))
    }

    fn word(&self, a: Addr) -> u16 {
        self.words.get(&a).copied().unwrap_or(0)
    }

    /// `n` words or bits from `a`, every one covered by a point.
    fn read(&self, unit: u8, table: Table, a: u16, n: u16) -> Result<Vec<u16>, ExceptionCode> {
        let max = if table.is_bits() {
            codec::MAX_BITS
        } else {
            codec::MAX_REGISTERS
        };
        if n == 0 || n > max {
            return Err(ExceptionCode::IllegalDataValue);
        }
        let addrs = range(a, n).ok_or(ExceptionCode::IllegalDataAddress)?;
        addrs
            .map(|x| {
                let k = (unit, table, x);
                self.cover
                    .contains_key(&k)
                    .then(|| self.word(k))
                    .ok_or(ExceptionCode::IllegalDataAddress)
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

    /// A master write of `w` from `a`, checked first: nothing changes on a
    /// refusal.
    fn write(&mut self, unit: u8, table: Table, a: u16, w: &[u16]) -> Result<(), ExceptionCode> {
        let n = u16::try_from(w.len()).map_err(|_| ExceptionCode::IllegalDataValue)?;
        self.check_write(unit, table, a, n)?;
        self.store(unit, table, a, w);
        self.changed_at(unit, table, a, n, true);
        Ok(())
    }

    fn store(&mut self, unit: u8, table: Table, a: u16, w: &[u16]) {
        for (x, v) in (a..=u16::MAX).zip(w) {
            self.words.insert((unit, table, x), *v);
        }
    }

    /// Every point covering `n` words or bits from `a` goes to `changed`
    /// (once); a master's write is logged by point.
    fn changed_at(&mut self, unit: u8, table: Table, a: u16, n: u16, master: bool) {
        let mut hit: Vec<usize> = range(a, n)
            .into_iter()
            .flatten()
            .filter_map(|x| self.cover.get(&(unit, table, x)))
            .flatten()
            .copied()
            .collect();
        hit.sort_unstable();
        hit.dedup();
        for i in hit {
            if master {
                let p = &self.points[i];
                info!(point = %format!("{}/{}", p.dev, p.id), "written by a master");
            }
            self.push_changed(i);
        }
    }

    fn push_changed(&mut self, i: usize) {
        let p = &self.points[i];
        match self.decode(p.unit, &p.point) {
            Ok(v) => self.changed.push((p.dev.clone(), p.id.clone(), v)),
            // A value no data type of the point can hold (a master wrote
            // it): the tree keeps the last one.
            Err(e) => debug!(point = %format!("{}/{}", p.dev, p.id), "not decoded: {e}"),
        }
    }

    fn decode(&self, unit: u8, p: &Point) -> Result<Value, codec::CodecError> {
        let w: Vec<u16> = span(p).map(|x| self.word((unit, p.table, x))).collect();
        if p.table.is_bits() {
            return Ok(Value::Bool(w.first().is_some_and(|b| *b != 0)));
        }
        codec::decode(p.dtype, &w, p.bit, p.scale, p.offset)
    }
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

fn len(w: &[u16]) -> u16 {
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
        s.set(3, &points["ro"], &Value::UInt(42)).unwrap();
        s.take_changed();
        // The owner task's part: apply each request, then answer it.
        let changed = Arc::new(Mutex::new(Vec::new()));
        let seen = changed.clone();
        let owner = tokio::spawn(async move {
            while let Ok(r) = s.remote().await {
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
        // unit 4 is not served here: no reply at all
        tokio_modbus::slave::SlaveContext::set_slave(&mut m, tokio_modbus::Slave(4));
        let silent =
            tokio::time::timeout(Duration::from_millis(300), m.read_holding_registers(10, 1)).await;
        assert!(silent.is_err(), "unit 4 answered: {silent:?}");
        owner.abort();
    }
}
