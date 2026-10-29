//! Modbus connector on the driver framework (ADR 0004), shaped like the
//! DSA `dslink-java-v2-modbus`.
//!
//! Tree: `<conn>/<device>/<point>`; connection kinds [`Conn`]: `Add IP
//! Connection` ([`IpConn`]: Modbus TCP, or RTU framing over TCP for serial
//! gateways) and `Add Serial Connection` ([`SerialConn`]: RTU on a serial
//! port; the root action `Rescan For Serial Ports` refreshes the found
//! ports in the forms) → [`Device`] → [`Point`].
//! The framework owns states, scheduling, edits and the quality ladder; this
//! driver only does protocol I/O:
//!
//! * reads (FC1–4) batched per table by [`codec::plan`] (`max_regs`,
//!   `max_bits`, `contiguous_only`); a span-level exception fails its
//!   member points only;
//! * writes FC5/FC15 (coils), FC6/FC16 (registers, `write_mode`), FC22 mask
//!   write for a bit in a register with a read-modify-write fallback that is
//!   cached per unit when the device lacks FC22;
//! * device ping by reading a probe register (an exception reply = alive) or
//!   FC17 Report Server ID.
//!
//! Unit ids are 0…255. On Modbus TCP 0 and 255 are ordinary units. On RTU
//! (serial and RTU over TCP) 0 is the broadcast address, which needs a
//! request without a reply; `tokio-modbus` 0.17 always waits for one, so a
//! unit-0 device on RTU sends nothing and fails with that reason.
//!
//! Every request is bounded by `timeout_ms`; a timeout is a device miss, an
//! I/O or protocol error drops the connection. Modbus ASCII and UDP are not
//! supported.

#![forbid(unsafe_code)]

pub mod codec;
#[cfg(feature = "sim")]
pub mod sim;

use codec::{DType, Span};
use std::collections::{BTreeMap, HashSet};
use std::net::SocketAddr;
use std::sync::LazyLock;
use std::time::Duration;
use tokio_modbus::client::{rtu, tcp, Client, Context, Reader, Writer};
use tokio_modbus::slave::SlaveContext;
use tokio_modbus::{ExceptionCode, Request, Slave};
use wyrm_core::meta::Writable;
use wyrm_core::{NodeMeta, TypeCode, Value};
use wyrm_link_sdk::driver::params::{field, normalize, ParamSpec};
// Traits (type namespace) beside the derive macros of the same name.
use wyrm_link_sdk::driver::{Driver, DriverError, Framework, ParamEnum, Params, PointId};
use wyrm_link_sdk::LinkError;
use wyrm_link_sdk::{ParamEnum, Params};

/// The `modbus` link: the framework running [`ModbusDriver`].
pub type Modbus = Framework<ModbusDriver>;

#[derive(Debug, Clone, Copy, PartialEq, Eq, ParamEnum)]
pub enum WriteMode {
    /// FC6/FC5 for one word or bit, FC16 for more.
    Auto,
    /// FC6/FC5 only (multi-word values still need FC16).
    Single,
    /// FC16/FC15 always.
    Multiple,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, ParamEnum)]
pub enum Ping {
    /// Read `probe_table`/`probe_addr`; an exception reply means alive.
    Probe,
    /// FC17 Report Server ID (often unsupported by devices).
    Fc17,
    None,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, ParamEnum)]
pub enum Table {
    Coil,
    Discrete,
    Input,
    Holding,
}

impl Table {
    fn is_bits(self) -> bool {
        matches!(self, Table::Coil | Table::Discrete)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, ParamEnum)]
pub enum IpTransport {
    /// Modbus TCP (MBAP header).
    Tcp,
    /// RTU frames (CRC, no MBAP) over TCP, as serial-to-Ethernet gateways send.
    RtuOverTcp,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, ParamEnum)]
pub enum Parity {
    None,
    Odd,
    Even,
}

/// The connection kinds of a Modbus link (DSA: `Add IP Connection`, `Add
/// Serial Connection`).
#[derive(Debug, Clone, PartialEq, Params)]
pub enum Conn {
    #[param(name = "ip_connection", display = "IP Connection")]
    Ip(IpConn),
    #[param(name = "serial_connection", display = "Serial Connection")]
    Serial(SerialConn),
}

impl Conn {
    fn timeout_ms(&self) -> u32 {
        match self {
            Conn::Ip(c) => c.timeout_ms,
            Conn::Serial(c) => c.timeout_ms,
        }
    }

    fn write_mode(&self) -> WriteMode {
        match self {
            Conn::Ip(c) => c.write_mode,
            Conn::Serial(c) => c.write_mode,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Params)]
pub struct IpConn {
    #[param(display = "Host", placeholder = "10.0.1.199", dest)]
    pub host: String,
    #[param(default = 502, display = "Port", dest)]
    pub port: u16,
    #[param(enum, default = "tcp", display = "Transport Type", dest)]
    pub transport: IpTransport,
    /// Bound on each request.
    #[param(default = 1000, min = 100, max = 10000, display = "Timeout (ms)")]
    pub timeout_ms: u32,
    #[param(enum, default = "auto", display = "Write Mode")]
    pub write_mode: WriteMode,
}

#[derive(Debug, Clone, PartialEq, Params)]
pub struct SerialConn {
    #[param(display = "Serial Port", placeholder = "/dev/ttyUSB0", dest)]
    pub serial_port: String,
    #[param(default = 9600, min = 300, max = 4000000, display = "Baud Rate")]
    pub baud_rate: u32,
    #[param(default = 8, min = 5, max = 8, display = "Data Bits")]
    pub data_bits: u8,
    #[param(default = 1, min = 1, max = 2, display = "Stop Bits")]
    pub stop_bits: u8,
    #[param(enum, default = "none", display = "Parity")]
    pub parity: Parity,
    #[param(default = 1000, min = 100, max = 10000, display = "Timeout (ms)")]
    pub timeout_ms: u32,
    #[param(enum, default = "auto", display = "Write Mode")]
    pub write_mode: WriteMode,
}

#[derive(Debug, Clone, PartialEq, Params)]
pub struct Device {
    /// 0 and 255 are ordinary units on Modbus TCP; 0 (broadcast) is refused
    /// on RTU.
    #[param(default = 1, min = 0, max = 255, display = "Slave ID")]
    pub unit: u8,
    #[param(enum, default = "probe", display = "Ping")]
    pub ping: Ping,
    #[param(enum, default = "holding", display = "Probe Table")]
    pub probe_table: Table,
    #[param(default = 0, display = "Probe Address")]
    pub probe_addr: u16,
    #[param(default = 5.0, min = 0.1, max = 3600.0, display = "Ping Rate (s)")]
    pub ping_s: f64,
    /// Read gaps between points (`false`) or only adjacent registers.
    #[param(default = false, display = "Contiguous Batch Reads Only")]
    pub contiguous_only: bool,
    #[param(default = 125, min = 1, max = 125, display = "Max Registers per Read")]
    pub max_regs: u16,
    #[param(default = 2000, min = 1, max = 2000, display = "Max Bits per Read")]
    pub max_bits: u16,
}

/// One point. Hand-written `Params` because `dtype` uses the codec names and
/// the rules cross fields (coil/discrete ⇔ binary, writable tables, scale).
#[derive(Debug, Clone, PartialEq)]
pub struct Point {
    pub table: Table,
    pub addr: u16,
    pub dtype: DType,
    pub bit: u8,
    pub regs: u8,
    pub poll_s: f64,
    pub scale: f64,
    pub offset: f64,
    pub writable: bool,
    pub unit: String,
}

static DTYPE_NAMES: LazyLock<&'static [&'static str]> = LazyLock::new(|| {
    let names: Vec<&'static str> = DType::ALL.iter().map(|d| d.name()).collect();
    Box::leak(names.into_boxed_slice())
});

impl Point {
    /// Words (registers) or bits one value occupies.
    fn words(&self) -> u16 {
        if self.table.is_bits() {
            1
        } else {
            self.dtype.words(self.regs)
        }
    }
}

/// A coil or discrete point without `dtype` is `binary`: the schema default
/// (`u16`) is for registers.
fn bit_table_default(v: &Value) -> Value {
    let Value::Map(m) = v else {
        return v.clone();
    };
    let bits = matches!(m.get("table"), Some(Value::Str(t)) if t == "coil" || t == "discrete");
    let mut m = m.clone();
    if bits && !m.contains_key("dtype") {
        m.insert("dtype".into(), Value::Str(DType::Binary.name().into()));
    }
    Value::Map(m)
}

impl Params for Point {
    fn schema() -> Vec<ParamSpec> {
        vec![
            ParamSpec::new("table", TypeCode::Enum)
                .one_of(Table::NAMES)
                .display("Object Type"),
            ParamSpec::new("addr", TypeCode::Number)
                .bounds(0.0, 65535.0)
                .display("Offset"),
            ParamSpec::new("dtype", TypeCode::Enum)
                .one_of(*DTYPE_NAMES)
                .default("u16")
                .desc("u16 for registers, binary for coil and discrete")
                .display("Data Type"),
            ParamSpec::new("bit", TypeCode::Number)
                .default(0u64)
                .bounds(0.0, 15.0)
                .desc("bit of a register for dtype binary")
                .display("Bit"),
            ParamSpec::new("regs", TypeCode::Number)
                .default(1u64)
                .bounds(1.0, 125.0)
                .desc("registers of a char/varchar value")
                .display("Number of Registers"),
            ParamSpec::new("poll_s", TypeCode::Number)
                .default(1.0)
                .bounds(0.01, 86_400.0)
                .display("Poll Rate (s)"),
            ParamSpec::new("scale", TypeCode::Number)
                .default(1.0)
                .display("Scaling"),
            ParamSpec::new("offset", TypeCode::Number)
                .default(0.0)
                .display("Scaling Offset"),
            ParamSpec::new("writable", TypeCode::Bool)
                .default(false)
                .display("Writable"),
            ParamSpec::new("unit", TypeCode::String)
                .default("")
                .display("Unit"),
        ]
    }

    fn from_value(v: &Value) -> wyrm_link_sdk::Result<Self> {
        Self::from_map(&normalize(&Self::schema(), &bit_table_default(v))?)
    }

    fn from_kind_value(kind: &str, v: &Value) -> wyrm_link_sdk::Result<Self> {
        Self::from_kind_map(
            kind,
            &normalize(&Self::kind_schema(kind)?, &bit_table_default(v))?,
        )
    }

    fn from_map(m: &BTreeMap<String, Value>) -> wyrm_link_sdk::Result<Self> {
        let dtype_name = field::string(m, "dtype")?;
        let p = Point {
            table: field::enumv(m, "table")?,
            addr: field::int(m, "addr")?,
            dtype: DType::parse(&dtype_name).ok_or_else(|| {
                LinkError::invalid_parameter(format!("dtype: unknown {dtype_name}"))
            })?,
            bit: field::int(m, "bit")?,
            regs: field::int(m, "regs")?,
            poll_s: field::f64(m, "poll_s")?,
            scale: field::f64(m, "scale")?,
            offset: field::f64(m, "offset")?,
            writable: field::bool(m, "writable")?,
            unit: field::string(m, "unit")?,
        };
        if p.table.is_bits() && p.dtype != DType::Binary {
            return Err(LinkError::invalid_parameter(
                "dtype: coil and discrete tables hold binary values only",
            ));
        }
        if p.writable && !matches!(p.table, Table::Coil | Table::Holding) {
            return Err(LinkError::invalid_parameter(
                "writable: only coil and holding points can be written",
            ));
        }
        if p.scale == 0.0 {
            return Err(LinkError::invalid_parameter("scale: must not be 0"));
        }
        if u32::from(p.addr) + u32::from(p.words()) > 65_536 {
            return Err(LinkError::invalid_parameter("addr: value runs past 65535"));
        }
        Ok(p)
    }

    fn to_map(&self) -> BTreeMap<String, Value> {
        BTreeMap::from([
            ("table".into(), Value::Str(self.table.name().into())),
            ("addr".into(), Value::UInt(self.addr.into())),
            ("dtype".into(), Value::Str(self.dtype.name().into())),
            ("bit".into(), Value::UInt(self.bit.into())),
            ("regs".into(), Value::UInt(self.regs.into())),
            ("poll_s".into(), Value::Float(self.poll_s)),
            ("scale".into(), Value::Float(self.scale)),
            ("offset".into(), Value::Float(self.offset)),
            ("writable".into(), Value::Bool(self.writable)),
            ("unit".into(), Value::Str(self.unit.clone())),
        ])
    }
}

/// Only serial device paths may be opened: a `config` user must not make
/// the link open another device file (some have side effects on open).
fn serial_path_ok(p: &str) -> bool {
    if p.contains("..") || p.contains('\0') {
        return false;
    }
    let com = |s: &str| {
        s.strip_prefix("COM")
            .is_some_and(|n| !n.is_empty() && n.len() <= 3 && n.bytes().all(|b| b.is_ascii_digit()))
    };
    if cfg!(windows) {
        return com(p) || p.strip_prefix(r"\\.\").is_some_and(com);
    }
    let Some(rest) = p.strip_prefix("/dev/") else {
        return false;
    };
    let name_ok = |s: &str| {
        !s.is_empty()
            && s.bytes()
                .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'.' | b'_' | b'-' | b':'))
    };
    // Known serial port names only: not `/dev/tty` (the controlling
    // terminal), `/dev/ttyN` (consoles) or `/dev/ttyprintk` (kernel log).
    let numbered = |s: &str, prefixes: &[&str]| {
        prefixes.iter().any(|pre| {
            s.strip_prefix(pre).is_some_and(|n| {
                !n.is_empty() && n.len() <= 3 && n.bytes().all(|b| b.is_ascii_digit())
            })
        })
    };
    const LINUX: &[&str] = &[
        "ttyS",
        "ttyUSB",
        "ttyACM",
        "ttyAMA",
        "ttyTHS",
        "ttyXRUSB",
        "ttymxc",
        "ttyO",
        "ttySAC",
        "ttyLP",
        "ttyGS",
        "rfcomm",
        "ttySC",
        "ttyM",
        "ttyMXUSB",
        "ttyMI",
        "ttyRP",
        "ttyXR",
        "ttyCH343USB",
        "ttyHS",
        "ttyMSM",
    ];
    match rest.split_once('/') {
        None => {
            numbered(rest, LINUX)
                || ["tty.", "cu."]
                    .iter()
                    .any(|pre| rest.strip_prefix(pre).is_some_and(name_ok))
        }
        Some(("serial", sub)) => match sub.split_once('/') {
            Some(("by-id" | "by-path", name)) => name_ok(name),
            _ => false,
        },
        Some(_) => false,
    }
}

fn serial_builder(c: &SerialConn) -> tokio_serial::SerialPortBuilder {
    use tokio_serial::{DataBits, StopBits};
    let data_bits = match c.data_bits {
        5 => DataBits::Five,
        6 => DataBits::Six,
        7 => DataBits::Seven,
        _ => DataBits::Eight,
    };
    let stop_bits = if c.stop_bits == 2 {
        StopBits::Two
    } else {
        StopBits::One
    };
    let parity = match c.parity {
        Parity::None => tokio_serial::Parity::None,
        Parity::Odd => tokio_serial::Parity::Odd,
        Parity::Even => tokio_serial::Parity::Even,
    };
    tokio_serial::new(&c.serial_port, c.baud_rate)
        .data_bits(data_bits)
        .stop_bits(stop_bits)
        .parity(parity)
        .timeout(Duration::from_millis(c.timeout_ms.into()))
}

pub struct Transport {
    ctx: Context,
    timeout: Duration,
    write_mode: WriteMode,
    /// RTU framing (serial or RTU over TCP): unit 0 is broadcast there.
    rtu: bool,
    /// Units that answered FC22 with `IllegalFunction`.
    no_fc22: HashSet<u8>,
}

/// Reads of one table.
pub struct TableReads {
    table: Table,
    spans: Vec<Span>,
    /// Indexed like the requests given to `codec::plan`.
    members: Vec<(PointId, Point)>,
}

pub struct Plan {
    tables: Vec<TableReads>,
}

type Reply<T> = Result<Result<T, ExceptionCode>, DriverError>;

/// Run one request with the timeout and sort the outcome.
async fn io<T>(
    timeout: Duration,
    f: impl std::future::Future<Output = tokio_modbus::Result<T>>,
) -> Reply<T> {
    match tokio::time::timeout(timeout, f).await {
        Err(_) => Err(DriverError::Device("request timed out".into())),
        Ok(Err(e)) => Err(DriverError::Transport(e.to_string())),
        Ok(Ok(r)) => Ok(r),
    }
}

fn exception(e: ExceptionCode) -> DriverError {
    DriverError::Point(format!("device exception {e:?}"))
}

fn codec_err(e: codec::CodecError) -> DriverError {
    DriverError::Point(e.to_string())
}

/// Why a unit-0 device on RTU sends nothing.
const NO_RTU_BROADCAST: &str = "broadcast (unit 0) is not supported on RTU";

impl Transport {
    /// Address `unit`; `false` = it is the RTU broadcast address, which
    /// `tokio-modbus` cannot send (it always waits for a reply).
    fn select(&mut self, unit: u8) -> bool {
        self.ctx.set_slave(Slave(unit));
        !(self.rtu && unit == 0)
    }

    async fn read(&mut self, table: Table, addr: u16, n: u16) -> Reply<Vec<u16>> {
        let t = self.timeout;
        fn bits(r: Result<Vec<bool>, ExceptionCode>) -> Result<Vec<u16>, ExceptionCode> {
            r.map(|b| b.into_iter().map(u16::from).collect())
        }
        Ok(match table {
            Table::Coil => bits(io(t, self.ctx.read_coils(addr, n)).await?),
            Table::Discrete => bits(io(t, self.ctx.read_discrete_inputs(addr, n)).await?),
            Table::Input => io(t, self.ctx.read_input_registers(addr, n)).await?,
            Table::Holding => io(t, self.ctx.read_holding_registers(addr, n)).await?,
        })
    }

    /// Set one bit of a holding register: FC22, or read-modify-write when the
    /// unit does not support FC22 (remembered for this connection).
    async fn write_bit(
        &mut self,
        unit: u8,
        addr: u16,
        bit: u8,
        on: bool,
    ) -> Result<(), DriverError> {
        let (and, or) = codec::bit_masks(bit, on);
        if !self.no_fc22.contains(&unit) {
            match io(self.timeout, self.ctx.masked_write_register(addr, and, or)).await? {
                Ok(()) => return Ok(()),
                Err(ExceptionCode::IllegalFunction) => {
                    self.no_fc22.insert(unit);
                }
                Err(e) => return Err(exception(e)),
            }
        }
        let cur = io(self.timeout, self.ctx.read_holding_registers(addr, 1))
            .await?
            .map_err(exception)?;
        let cur = *cur
            .first()
            .ok_or_else(|| DriverError::Point("short read".into()))?;
        io(
            self.timeout,
            self.ctx
                .write_single_register(addr, codec::apply_masks(cur, and, or)),
        )
        .await?
        .map_err(exception)
    }
}

pub struct ModbusDriver;

impl Driver for ModbusDriver {
    const NAME: &'static str = "modbus";
    const VERSION: &'static str = env!("CARGO_PKG_VERSION");
    type Conn = Conn;
    type Dev = Device;
    type Point = Point;
    type Transport = Transport;
    type Plan = Plan;

    async fn open(conn: &Conn) -> Result<Transport, DriverError> {
        let timeout = Duration::from_millis(conn.timeout_ms().into());
        let ctx = match conn {
            Conn::Ip(c) => {
                let target = format!("{}:{}", c.host, c.port);
                let addr: SocketAddr =
                    tokio::time::timeout(timeout, tokio::net::lookup_host(&target))
                        .await
                        .map_err(|_| DriverError::Transport(format!("resolve {target}: timeout")))?
                        .map_err(|e| DriverError::Transport(format!("resolve {target}: {e}")))?
                        .next()
                        .ok_or_else(|| {
                            DriverError::Transport(format!("resolve {target}: no address"))
                        })?;
                match c.transport {
                    IpTransport::Tcp => {
                        tokio::time::timeout(timeout, tcp::connect_slave(addr, Slave(1)))
                            .await
                            .map_err(|_| {
                                DriverError::Transport(format!("connect {target}: timeout"))
                            })?
                            .map_err(|e| DriverError::Transport(format!("connect {target}: {e}")))?
                    }
                    IpTransport::RtuOverTcp => {
                        let stream =
                            tokio::time::timeout(timeout, tokio::net::TcpStream::connect(addr))
                                .await
                                .map_err(|_| {
                                    DriverError::Transport(format!("connect {target}: timeout"))
                                })?
                                .map_err(|e| {
                                    DriverError::Transport(format!("connect {target}: {e}"))
                                })?;
                        rtu::attach_slave(stream, Slave(1))
                    }
                }
            }
            Conn::Serial(c) => {
                if !serial_path_ok(&c.serial_port) {
                    return Err(DriverError::Transport(format!(
                        "serial_port {:?}: not a serial device path (/dev/tty*, /dev/cu.*, \
                         /dev/serial/by-id/*, /dev/serial/by-path/*, /dev/rfcomm*, COMn)",
                        c.serial_port
                    )));
                }
                let stream = tokio_serial::SerialStream::open(&serial_builder(c))
                    .map_err(|e| DriverError::Transport(format!("open {}: {e}", c.serial_port)))?;
                rtu::attach_slave(stream, Slave(1))
            }
        };
        let rtu = match conn {
            Conn::Ip(c) => c.transport == IpTransport::RtuOverTcp,
            Conn::Serial(_) => true,
        };
        Ok(Transport {
            ctx,
            timeout,
            write_mode: conn.write_mode(),
            rtu,
            no_fc22: HashSet::new(),
        })
    }

    async fn ping(t: &mut Transport, dev: &Device) -> Result<(), DriverError> {
        if !t.select(dev.unit) {
            return Err(DriverError::Device(NO_RTU_BROADCAST.into()));
        }
        match dev.ping {
            Ping::None => Ok(()),
            // Any answer, exception included, means the device is alive.
            Ping::Probe => t.read(dev.probe_table, dev.probe_addr, 1).await.map(|_| ()),
            Ping::Fc17 => io(
                t.timeout,
                t.ctx.call(Request::Custom(0x11, Vec::new().into())),
            )
            .await
            .map(|_| ()),
        }
    }

    fn plan(dev: &Device, points: &[(PointId, Point)]) -> Plan {
        let mut by_table: BTreeMap<u8, Vec<(PointId, Point)>> = BTreeMap::new();
        for (id, p) in points {
            by_table
                .entry(p.table as u8)
                .or_default()
                .push((id.clone(), p.clone()));
        }
        let tables = by_table
            .into_values()
            .map(|members| {
                let table = members[0].1.table;
                let reqs: Vec<(u16, u16)> =
                    members.iter().map(|(_, p)| (p.addr, p.words())).collect();
                let max = if table.is_bits() {
                    dev.max_bits
                } else {
                    dev.max_regs
                };
                TableReads {
                    table,
                    spans: codec::plan(&reqs, max, dev.contiguous_only),
                    members,
                }
            })
            .collect();
        Plan { tables }
    }

    async fn poll(
        t: &mut Transport,
        dev: &Device,
        plan: &Plan,
    ) -> Vec<(PointId, Result<Value, DriverError>)> {
        if !t.select(dev.unit) {
            let refused = DriverError::Device(NO_RTU_BROADCAST.into());
            return plan
                .tables
                .iter()
                .flat_map(|tr| tr.members.iter())
                .map(|(id, _)| (id.clone(), Err(refused.clone())))
                .collect();
        }
        let mut out = Vec::new();
        for tr in &plan.tables {
            for span in &tr.spans {
                let r = t.read(tr.table, span.start, span.count).await;
                for &i in &span.members {
                    let (id, p) = &tr.members[i];
                    let v = match &r {
                        Err(e) => Err(e.clone()),
                        Ok(Err(e)) => Err(exception(*e)),
                        Ok(Ok(words)) => {
                            let w = codec::slice(span, words, p.addr, p.words());
                            if tr.table.is_bits() {
                                w.first()
                                    .map(|b| Value::Bool(*b != 0))
                                    .ok_or_else(|| DriverError::Point("short read".into()))
                            } else {
                                codec::decode(p.dtype, w, p.bit, p.scale, p.offset)
                                    .map_err(codec_err)
                            }
                        }
                    };
                    out.push((id.clone(), v));
                }
                // A broken connection: the framework reconnects; stop here.
                if matches!(r, Err(DriverError::Transport(_))) {
                    return out;
                }
            }
        }
        out
    }

    async fn write(
        t: &mut Transport,
        dev: &Device,
        _id: &str,
        p: &Point,
        v: &Value,
    ) -> Result<(), DriverError> {
        if !t.select(dev.unit) {
            return Err(DriverError::Point(NO_RTU_BROADCAST.into()));
        }
        let timeout = t.timeout;
        match (p.table, p.dtype) {
            (Table::Coil, _) => {
                let Value::Bool(on) = v else {
                    return Err(DriverError::Point("expected true or false".into()));
                };
                let r = if t.write_mode == WriteMode::Multiple {
                    io(timeout, t.ctx.write_multiple_coils(p.addr, &[*on])).await?
                } else {
                    io(timeout, t.ctx.write_single_coil(p.addr, *on)).await?
                };
                r.map_err(exception)
            }
            (Table::Holding, DType::Binary) => {
                let Value::Bool(on) = v else {
                    return Err(DriverError::Point("expected true or false".into()));
                };
                t.write_bit(dev.unit, p.addr, p.bit, *on).await
            }
            (Table::Holding, _) => {
                // One FC16 request per value. Checked here, not in
                // `from_map`: a stored writable point with more registers
                // still loads and polls (the framework parses stored, added
                // and edited points alike).
                if p.words() > codec::MAX_WRITE_REGISTERS {
                    return Err(DriverError::Point(format!(
                        "regs: a value of {} registers cannot be written; one write \
                         carries at most {} registers",
                        p.words(),
                        codec::MAX_WRITE_REGISTERS
                    )));
                }
                let words =
                    codec::encode(p.dtype, v, p.regs, p.scale, p.offset).map_err(codec_err)?;
                let r = if words.len() == 1 && t.write_mode != WriteMode::Multiple {
                    io(timeout, t.ctx.write_single_register(p.addr, words[0])).await?
                } else {
                    io(timeout, t.ctx.write_multiple_registers(p.addr, &words)).await?
                };
                r.map_err(exception)
            }
            _ => Err(DriverError::Point("point is not writable".into())),
        }
    }

    fn point_meta(p: &Point) -> NodeMeta {
        let mut m = NodeMeta::leaf(if p.table.is_bits() {
            TypeCode::Bool
        } else {
            p.dtype.type_code()
        });
        if !p.unit.is_empty() {
            m = m.unit(p.unit.clone());
        }
        m.writable(if p.writable {
            Writable::Write
        } else {
            Writable::Never
        })
    }

    fn poll_period(p: &Point) -> Duration {
        Duration::from_secs_f64(p.poll_s)
    }

    fn ping_period(dev: &Device) -> Option<Duration> {
        (dev.ping != Ping::None).then(|| Duration::from_secs_f64(dev.ping_s))
    }

    /// Whole-operation bound; each request inside is bounded by `timeout_ms`.
    fn io_timeout(conn: &Conn) -> Duration {
        Duration::from_millis(u64::from(conn.timeout_ms()) * 4)
    }

    /// Serial ports found on this host, for the `serial_port` field.
    fn choices(param: &str) -> Vec<String> {
        if param != "serial_port" {
            return Vec::new();
        }
        tokio_serial::available_ports()
            .map(|ports| ports.into_iter().map(|p| p.port_name).collect())
            .unwrap_or_default()
    }

    const RESCAN: Option<&'static str> = Some("Rescan For Serial Ports");
}

#[cfg(test)]
mod serial_tests {
    use super::serial_path_ok;

    #[test]
    #[cfg(not(windows))]
    fn only_serial_device_paths() {
        for ok in [
            "/dev/ttyUSB0",
            "/dev/ttyS1",
            "/dev/ttyAMA0",
            "/dev/cu.usbserial-1410",
            "/dev/tty.usbmodem14101",
            "/dev/rfcomm0",
            // industrial gateways and SoC UARTs (Linux)
            "/dev/ttySC0",
            "/dev/ttyM0",
            "/dev/ttyMXUSB3",
            "/dev/ttyMI1",
            "/dev/ttyRP12",
            "/dev/ttyXR0",
            "/dev/ttyCH343USB0",
            "/dev/ttyHS1",
            "/dev/ttyMSM0",
            "/dev/serial/by-id/usb-FTDI_FT232R-if00-port0",
            "/dev/serial/by-path/pci-0000:00:14.0-usb-0:2:1.0-port0",
        ] {
            assert!(serial_path_ok(ok), "{ok}");
        }
        for bad in [
            "/dev/watchdog",
            "/dev/tty",
            "/dev/tty0",
            "/dev/tty63",
            "/dev/ttyprintk",
            "/dev/ttyp0",
            "/dev/ttyUSB",
            "/dev/ttySC",
            "/dev/ttyM",
            "/dev/ttyMXUSB",
            "/dev/ttyMSM1000",
            "/dev/ttyHSx",
            "/dev/cu.",
            "/dev/sda",
            "/dev/mem",
            "/etc/passwd",
            "/dev/tty/../sda",
            "/dev/serial/by-id/../../sda",
            "/dev/serial/other/x",
            "ttyUSB0",
            "",
        ] {
            assert!(!serial_path_ok(bad), "{bad}");
        }
    }
}
