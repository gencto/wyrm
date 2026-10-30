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
//! * writes FC5/FC15 (coils), FC6/FC16 (registers, `write_mode`; `single`
//!   writes a multi-word value as a series of FC6), FC22 mask write for a
//!   bit in a register with a read-modify-write fallback that is cached per
//!   unit when the device lacks FC22;
//! * device ping by reading a probe register (an exception reply = alive) or
//!   FC17 Report Server ID.
//!
//! Unit ids are 0…255. On Modbus TCP 0 and 255 are ordinary units. On RTU
//! (serial and RTU over TCP) 0 is the broadcast address, which needs a
//! request without a reply; `tokio-modbus` 0.17 always waits for one, so a
//! unit-0 device on RTU sends nothing and fails with that reason.
//!
//! Every request is bounded by `timeout_ms` and sent again up to `retries`
//! times after a timeout (never after an exception); a last timeout is a
//! device miss, an I/O or protocol error drops the connection. A reply that
//! comes after its timeout would be taken for the next request of the same
//! unit and function on RTU (`tokio-modbus` cannot drain input), and would
//! fail the next request with a transaction id mismatch on Modbus TCP, so
//! the next request after a timeout reopens the transport first; a
//! reopened serial port waits out the late reply and clears its input. A
//! poll is bounded by `timeout_ms × (1 + retries) × requests + 1 s`, a
//! write likewise by its requests, and a failed write is read back. `republish_s` on a
//! device publishes unchanged values again (a heartbeat). Modbus ASCII and
//! UDP are not supported.
//!
//! Diagnostics (framework, ruling 12): every request sent (a retry too) is
//! counted for its device and connection as answered, an exception, a
//! timeout or an I/O or protocol error, with its round trip; `reopens`
//! counts the reopens after an unanswered request.
//!
//! Commissioning actions (ruling 13), run on the connection's owner task
//! between polls: device `read_registers` (one read of up to 125 registers
//! or bits, raw and decoded) and `read_device_id` (FC43/14 basic and
//! regular objects), both at level read; connection `scan_units` (one
//! probe read per unit id, config level). A scan holds the owner for its
//! whole run, so the connection's polls wait until it ends.

#![forbid(unsafe_code)]

pub mod codec;
#[cfg(feature = "sim")]
pub mod sim;

use codec::{DType, Span};
use std::collections::{BTreeMap, HashSet};
use std::net::SocketAddr;
use std::sync::LazyLock;
use std::time::Duration;
use tokio_modbus::client::{rtu, tcp, Client, Context};
use tokio_modbus::prelude::ReadCode;
use tokio_modbus::slave::SlaveContext;
use tokio_modbus::{ExceptionCode, Request, Response, Slave};
use tracing::debug;
use wyrm_core::meta::{ActionResult, ParamMeta, Writable};
use wyrm_core::{ActionMeta, NodeMeta, Perm, Status, TypeCode, Value};
use wyrm_link_sdk::driver::params::{field, normalize, ParamSpec};
// Traits (type namespace) beside the derive macros of the same name.
use wyrm_link_sdk::driver::{
    Driver, DriverError, Framework, Level, Outcome, ParamEnum, Params, PointId, Target,
};
use wyrm_link_sdk::LinkError;
use wyrm_link_sdk::{ParamEnum, Params};

/// The `modbus` link: the framework running [`ModbusDriver`].
pub type Modbus = Framework<ModbusDriver>;

#[derive(Debug, Clone, Copy, PartialEq, Eq, ParamEnum)]
pub enum WriteMode {
    /// FC6/FC5 for one word or bit, FC16 for more.
    Auto,
    /// FC6/FC5 only: a multi-word value is a series of FC6, lowest
    /// address first (DSA "Never").
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

    fn retries(&self) -> u8 {
        match self {
            Conn::Ip(c) => c.retries,
            Conn::Serial(c) => c.retries,
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
    /// Repeats of a request after a timeout (not after an exception).
    #[param(default = 0, min = 0, max = 5, display = "Retries")]
    pub retries: u8,
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
    /// Repeats of a request after a timeout (not after an exception); 1 is
    /// a good value on RS485.
    #[param(default = 0, min = 0, max = 5, display = "Retries")]
    pub retries: u8,
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
    /// Publish an unchanged value again after this long (0 = only on a
    /// change; DSA republishes every 60 s).
    #[param(
        default = 0.0,
        min = 0.0,
        max = 3600.0,
        display = "Republish Unchanged Values (s)"
    )]
    pub republish_s: f64,
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
    /// Kept to reopen the transport (ruling 7).
    conn: Conn,
    timeout: Duration,
    retries: u8,
    write_mode: WriteMode,
    /// RTU framing (serial or RTU over TCP): unit 0 is broadcast there.
    rtu: bool,
    /// The unit addressed (set again on a reopened transport).
    unit: u8,
    /// A request went out and its reply was not taken (timed out, or the
    /// framework's bound cut the operation). The reply may still come:
    /// `tokio-modbus` cannot drain it on RTU (it would be taken for the next
    /// request of the same unit and function), and on Modbus TCP its old
    /// transaction id fails the next request and drops the connection. So
    /// the next request reopens the transport first (ruling 7, P8).
    unanswered: bool,
    /// When the unanswered request's reply window ends (it went out with
    /// its own timeout; the serial guard waits out the rest of it).
    window_end: Option<tokio::time::Instant>,
    /// Reopens after an unanswered request (also counted in `outcomes`).
    reopens: u64,
    /// Outcomes of the requests since the framework last took them.
    outcomes: Vec<Outcome>,
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

impl Plan {
    /// Read requests of one poll.
    fn requests(&self) -> usize {
        self.tables.iter().map(|t| t.spans.len()).sum()
    }
}

type Reply<T> = Result<Result<T, ExceptionCode>, DriverError>;

fn exception(e: ExceptionCode) -> DriverError {
    DriverError::Point(format!("device exception {e:?}"))
}

fn codec_err(e: codec::CodecError) -> DriverError {
    DriverError::Point(e.to_string())
}

/// A reply of another kind than the request (`tokio-modbus` checks the
/// function code, so this does not happen).
fn unexpected(r: &Response) -> DriverError {
    DriverError::Transport(format!(
        "unexpected reply (function {})",
        r.function_code().value()
    ))
}

/// Diagnostics counter of transport reopens (ruling P1).
const REOPENS: &str = "reopens";

/// Why a unit-0 device on RTU sends nothing.
const NO_RTU_BROADCAST: &str = "broadcast (unit 0) is not supported on RTU";

/// Bits on the wire per character: start, data, parity, stop.
fn char_bits(c: &SerialConn) -> u32 {
    1 + u32::from(c.data_bits) + u32::from(c.parity != Parity::None) + u32::from(c.stop_bits)
}

/// Ruling P10: how long a reopened serial port waits before its first
/// request: 3.5 character times (the RTU frame gap), at least 50 ms, plus
/// the rest of the unanswered request's window (`rest`), so a late reply
/// still on the wire has ended before the input is cleared.
fn serial_guard(c: &SerialConn, rest: Duration) -> Duration {
    let gap =
        Duration::from_secs_f64(3.5 * f64::from(char_bits(c)) / f64::from(c.baud_rate.max(1)));
    gap.max(Duration::from_millis(50)) + rest
}

/// A port whose received, unread bytes can be thrown away.
trait ClearInput {
    fn clear_input(&self) -> std::io::Result<()>;
}

impl ClearInput for tokio_serial::SerialStream {
    fn clear_input(&self) -> std::io::Result<()> {
        use tokio_serial::SerialPort;
        self.clear(tokio_serial::ClearBuffer::Input)
            .map_err(std::io::Error::from)
    }
}

/// Wait `guard`, then drop whatever arrived meanwhile (the tail of a late
/// reply), so the next request reads only its own reply.
async fn settle(port: &impl ClearInput, guard: Duration) -> std::io::Result<()> {
    tokio::time::sleep(guard).await;
    port.clear_input()
}

/// Open the connection's socket or serial port (unit 1 addressed). A
/// serial port reopened after an unanswered request first waits `guard`
/// and clears its input ([`serial_guard`]); a socket needs nothing (bytes
/// sent to the closed one are gone).
async fn connect(
    conn: &Conn,
    timeout: Duration,
    guard: Option<Duration>,
) -> Result<Context, DriverError> {
    Ok(match conn {
        Conn::Ip(c) => {
            let target = format!("{}:{}", c.host, c.port);
            let addr: SocketAddr = tokio::time::timeout(timeout, tokio::net::lookup_host(&target))
                .await
                .map_err(|_| DriverError::Transport(format!("resolve {target}: timeout")))?
                .map_err(|e| DriverError::Transport(format!("resolve {target}: {e}")))?
                .next()
                .ok_or_else(|| DriverError::Transport(format!("resolve {target}: no address")))?;
            match c.transport {
                IpTransport::Tcp => {
                    tokio::time::timeout(timeout, tcp::connect_slave(addr, Slave(1)))
                        .await
                        .map_err(|_| DriverError::Transport(format!("connect {target}: timeout")))?
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
            if let Some(guard) = guard {
                settle(&stream, guard)
                    .await
                    .map_err(|e| DriverError::Transport(format!("clear {}: {e}", c.serial_port)))?;
            }
            rtu::attach_slave(stream, Slave(1))
        }
    })
}

impl Transport {
    /// Address `unit`; `false` = it is the RTU broadcast address, which
    /// `tokio-modbus` cannot send (it always waits for a reply).
    fn select(&mut self, unit: u8) -> bool {
        self.unit = unit;
        self.ctx.set_slave(Slave(unit));
        !(self.rtu && unit == 0)
    }

    /// Close the transport and open it again (ruling 7, P8): a late reply
    /// to the unanswered request then arrives on the closed socket, or (a
    /// serial port) is waited out and cleared (P10).
    async fn reopen(&mut self) -> Result<(), DriverError> {
        // Close first: a serial port opens exclusively.
        let _ = tokio::time::timeout(self.timeout, self.ctx.disconnect()).await;
        let guard = match &self.conn {
            Conn::Serial(c) => {
                let rest = self
                    .window_end
                    .map(|end| end.saturating_duration_since(tokio::time::Instant::now()))
                    .unwrap_or_default();
                Some(serial_guard(c, rest))
            }
            Conn::Ip(_) => None,
        };
        self.ctx = connect(&self.conn, self.timeout, guard).await?;
        self.ctx.set_slave(Slave(self.unit));
        self.unanswered = false;
        self.window_end = None;
        self.reopens += 1;
        self.outcomes.push(Outcome::Count(REOPENS));
        debug!(
            reopens = self.reopens,
            "transport reopened after an unanswered request"
        );
        Ok(())
    }

    /// One request, bounded by `timeout_ms`, sent again up to `retries`
    /// times after a timeout only (an exception is an answer; an I/O or
    /// protocol error drops the connection). A request after an unanswered
    /// one goes out on a reopened transport.
    async fn call(&mut self, req: Request<'static>) -> Reply<Response> {
        self.call_with(req, self.timeout, self.retries).await
    }

    /// [`Transport::call`] with its own bound and retries (the actions);
    /// the connection's stay as they are, even when the call is cut.
    async fn call_with(
        &mut self,
        req: Request<'static>,
        timeout: Duration,
        retries: u8,
    ) -> Reply<Response> {
        let mut retry = 0;
        loop {
            if self.unanswered {
                self.reopen().await?;
            }
            self.unanswered = true;
            let sent = tokio::time::Instant::now();
            self.window_end = Some(sent + timeout);
            let r = tokio::time::timeout(timeout, self.ctx.call(req.clone())).await;
            self.outcomes.push(match &r {
                Err(_) => Outcome::Timeout,
                Ok(Ok(Ok(_))) => Outcome::Reply(sent.elapsed()),
                Ok(Ok(Err(_))) => Outcome::Exception(sent.elapsed()),
                Ok(Err(_)) => Outcome::Error,
            });
            match r {
                Err(_) if retry < retries => {
                    retry += 1;
                    debug!(retry, "request timed out; sending it again");
                }
                Err(_) => return Err(DriverError::Device("request timed out".into())),
                Ok(r) => {
                    self.unanswered = false;
                    self.window_end = None;
                    return r.map_err(|e| DriverError::Transport(e.to_string()));
                }
            }
        }
    }

    /// A write request: `Ok` on any normal reply.
    async fn write_req(&mut self, req: Request<'static>) -> Result<(), DriverError> {
        self.call(req).await?.map(|_| ()).map_err(exception)
    }

    async fn read(&mut self, table: Table, addr: u16, n: u16) -> Reply<Vec<u16>> {
        let req = match table {
            Table::Coil => Request::ReadCoils(addr, n),
            Table::Discrete => Request::ReadDiscreteInputs(addr, n),
            Table::Input => Request::ReadInputRegisters(addr, n),
            Table::Holding => Request::ReadHoldingRegisters(addr, n),
        };
        Ok(match self.call(req).await? {
            Err(e) => Err(e),
            // Bits come padded to whole bytes.
            Ok(Response::ReadCoils(b) | Response::ReadDiscreteInputs(b)) => {
                Ok(b.into_iter().take(n.into()).map(u16::from).collect())
            }
            Ok(Response::ReadInputRegisters(w) | Response::ReadHoldingRegisters(w)) => Ok(w),
            Ok(other) => return Err(unexpected(&other)),
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
            match self.call(Request::MaskWriteRegister(addr, and, or)).await? {
                Ok(_) => return Ok(()),
                Err(ExceptionCode::IllegalFunction) => {
                    self.no_fc22.insert(unit);
                }
                Err(e) => return Err(exception(e)),
            }
        }
        let cur = self
            .read(Table::Holding, addr, 1)
            .await?
            .map_err(exception)?;
        let cur = *cur
            .first()
            .ok_or_else(|| DriverError::Point("short read".into()))?;
        self.write_req(Request::WriteSingleRegister(
            addr,
            codec::apply_masks(cur, and, or),
        ))
        .await
    }

    /// Registers from `addr`: FC6 for one word (unless `multiple`), FC16
    /// for more, or a series of FC6 in `single` mode (lowest address first;
    /// a failure part-way names how many went out).
    async fn write_words(&mut self, addr: u16, words: Vec<u16>) -> Result<(), DriverError> {
        match (self.write_mode, words.as_slice()) {
            (WriteMode::Auto | WriteMode::Single, [w]) => {
                self.write_req(Request::WriteSingleRegister(addr, *w)).await
            }
            (WriteMode::Single, _) => {
                let n = words.len();
                for (i, w) in words.into_iter().enumerate() {
                    let a = u16::try_from(i)
                        .ok()
                        .and_then(|i| addr.checked_add(i))
                        .ok_or_else(|| DriverError::Point("addr: value runs past 65535".into()))?;
                    let r = self.write_req(Request::WriteSingleRegister(a, w)).await;
                    if let Err(e) = r {
                        if i == 0 {
                            return Err(e);
                        }
                        let partial = format!("{e} (after {i} of {n} registers were written)");
                        return Err(match e {
                            DriverError::Transport(_) => DriverError::Transport(partial),
                            DriverError::Device(_) => DriverError::Device(partial),
                            DriverError::Point(_) => DriverError::Point(partial),
                        });
                    }
                }
                Ok(())
            }
            _ => {
                self.write_req(Request::WriteMultipleRegisters(addr, words.into()))
                    .await
            }
        }
    }
}

/// Bound on `read_registers` and `read_device_id` (ruling 13, P12): they
/// send each request once (no retries) at the connection's `timeout_ms`,
/// so one request at the longest timeout (10 s) and a reopen fit.
const READ_ACTION_MS: u32 = 12_000;

/// Bound on `scan_units`: 247 units at 200 ms with a reopen after each
/// silent one take about 62 s; below the gateway's 180 s wait on an action
/// (its `timeout_ms` + 5 s).
const SCAN_ACTION_MS: u32 = 170_000;

/// `scan_units` per-unit timeout: default, min, max (ms).
const SCAN_UNIT_MS: (u32, u32, u32) = (200, 20, 1000);

/// Requests of one FC43/14 category (`more follows` continuations).
const MAX_ID_REQUESTS: usize = 4;

/// FC43/14 basic and regular object names, by object id.
const ID_OBJECTS: [&str; 7] = [
    "vendor_name",
    "product_code",
    "revision",
    "vendor_url",
    "product_name",
    "model_name",
    "user_application_name",
];

fn uint_param(display: &str, desc: &str, default: Option<u64>) -> ParamMeta {
    ParamMeta {
        default: default.map(Value::UInt),
        ..ParamMeta::of(TypeCode::Number)
            .display(display)
            .description(desc)
    }
}

/// A choice by name, as the framework's forms declare one (`string` with
/// `enum_values`).
fn enum_param(display: &str, names: &[&str]) -> ParamMeta {
    ParamMeta::of(TypeCode::String)
        .enum_values(names.iter().copied())
        .display(display)
}

/// A whole-number arg in `min..=max`, `default` when absent (the SDK checks
/// types, not bounds).
fn arg_uint(
    args: &BTreeMap<String, Value>,
    name: &str,
    default: Option<u64>,
    (min, max): (u64, u64),
) -> Result<u64, LinkError> {
    let Some(v) = args.get(name) else {
        return default.ok_or_else(|| LinkError::invalid_parameter(format!("missing {name}")));
    };
    let n = match v {
        Value::UInt(u) => Some(*u),
        Value::Int(i) => u64::try_from(*i).ok(),
        Value::Float(f) if f.fract() == 0.0 && *f >= 0.0 && *f <= u64::MAX as f64 => {
            Some(*f as u64)
        }
        _ => None,
    }
    .ok_or_else(|| LinkError::invalid_parameter(format!("{name}: expected a whole number")))?;
    if !(min..=max).contains(&n) {
        return Err(LinkError::invalid_parameter(format!(
            "{name}: {n} is not in {min}…{max}"
        )));
    }
    Ok(n)
}

fn arg_enum<E: ParamEnum>(
    args: &BTreeMap<String, Value>,
    name: &str,
) -> Result<Option<E>, LinkError> {
    match args.get(name) {
        None => Ok(None),
        Some(Value::Str(s)) => E::from_name(s)
            .map(Some)
            .ok_or_else(|| LinkError::invalid_parameter(format!("{name}: unknown {s}"))),
        Some(_) => Err(LinkError::invalid_parameter(format!(
            "{name}: expected a name"
        ))),
    }
}

/// A failed action request as the caller sees it. A broken transport is
/// `disconnected`: the framework reconnects.
fn action_err(e: DriverError) -> LinkError {
    match e {
        DriverError::Transport(m) => LinkError::new(Status::Disconnected, m),
        DriverError::Device(m) => LinkError::timeout(m),
        DriverError::Point(m) => LinkError::new(Status::NotAvailable, m),
    }
}

fn exception_err(e: ExceptionCode) -> LinkError {
    let m = format!("device exception {e:?}");
    match e {
        ExceptionCode::IllegalFunction => LinkError::not_supported(m),
        ExceptionCode::IllegalDataAddress | ExceptionCode::IllegalDataValue => {
            LinkError::invalid_parameter(m)
        }
        _ => LinkError::new(Status::NotAvailable, m),
    }
}

/// Device action `read_registers {table, addr, count = 1, dtype?}`: one read
/// of up to 125 registers or bits → `{words}` or `{bits}`, and with `dtype`
/// the `value` decoded from the first words (unscaled; `error` instead when
/// they do not decode).
async fn read_registers(
    t: &mut Transport,
    dev: &Device,
    args: &BTreeMap<String, Value>,
) -> Result<Value, LinkError> {
    let table: Table =
        arg_enum(args, "table")?.ok_or_else(|| LinkError::invalid_parameter("missing table"))?;
    let addr = arg_uint(args, "addr", None, (0, 65_535))?;
    let max = u64::from(codec::MAX_REGISTERS);
    let count = arg_uint(args, "count", Some(1), (1, max))?;
    if addr + count > 65_536 {
        return Err(LinkError::invalid_parameter(
            "addr: the read runs past 65535",
        ));
    }
    let dtype: Option<DType> = match args.get("dtype") {
        None => None,
        Some(Value::Str(s)) => Some(
            DType::parse(s)
                .ok_or_else(|| LinkError::invalid_parameter(format!("dtype: unknown {s}")))?,
        ),
        Some(_) => return Err(LinkError::invalid_parameter("dtype: expected a name")),
    };
    let in_range = |_| LinkError::invalid_parameter("addr: out of range");
    let (addr, count) = (
        u16::try_from(addr).map_err(in_range)?,
        u16::try_from(count).map_err(in_range)?,
    );
    let regs = u8::try_from(count).unwrap_or(u8::MAX);
    match dtype {
        Some(d) if table.is_bits() && d != DType::Binary => {
            return Err(LinkError::invalid_parameter(
                "dtype: coil and discrete tables hold binary values only",
            ));
        }
        Some(d) if !table.is_bits() && d.words(regs) > count => {
            return Err(LinkError::invalid_parameter(format!(
                "dtype: {} needs {} registers, count is {count}",
                d.name(),
                d.words(regs)
            )));
        }
        _ => {}
    }
    if !t.select(dev.unit) {
        return Err(LinkError::invalid_parameter(NO_RTU_BROADCAST));
    }
    let req = match table {
        Table::Coil => Request::ReadCoils(addr, count),
        Table::Discrete => Request::ReadDiscreteInputs(addr, count),
        Table::Input => Request::ReadInputRegisters(addr, count),
        Table::Holding => Request::ReadHoldingRegisters(addr, count),
    };
    let reply = t.call_with(req, t.timeout, 0).await.map_err(action_err)?;
    let mut out = BTreeMap::new();
    match reply.map_err(exception_err)? {
        Response::ReadCoils(b) | Response::ReadDiscreteInputs(b) => {
            let bits: Vec<Value> = b.into_iter().take(count.into()).map(Value::Bool).collect();
            if dtype.is_some() {
                if let Some(first) = bits.first() {
                    out.insert("value".into(), first.clone());
                }
            }
            out.insert("bits".into(), Value::Array(bits));
        }
        Response::ReadInputRegisters(w) | Response::ReadHoldingRegisters(w) => {
            if let Some(d) = dtype {
                let n = usize::from(d.words(regs)).min(w.len());
                match codec::decode(d, &w[..n], 0, 1.0, 0.0) {
                    Ok(v) => out.insert("value".into(), v),
                    Err(e) => out.insert("error".into(), Value::Str(e.to_string())),
                };
            }
            let words = w.into_iter().map(|x| Value::UInt(x.into())).collect();
            out.insert("words".into(), Value::Array(words));
        }
        other => return Err(action_err(unexpected(&other))),
    }
    Ok(Value::Map(out))
}

/// One FC43/14 category from object `start` into `objects`, following
/// `more follows` (at most [`MAX_ID_REQUESTS`] requests; a next object id
/// that does not advance ends it). The device's conformity level.
async fn read_id_category(
    t: &mut Transport,
    code: ReadCode,
    start: u8,
    objects: &mut BTreeMap<u8, String>,
) -> Result<Result<u8, ExceptionCode>, LinkError> {
    let mut next = start;
    let mut level = 0;
    for _ in 0..MAX_ID_REQUESTS {
        let req = Request::ReadDeviceIdentification(code, next);
        let r = match t.call_with(req, t.timeout, 0).await.map_err(action_err)? {
            Err(e) => return Ok(Err(e)),
            Ok(Response::ReadDeviceIdentification(r)) => r,
            Ok(other) => return Err(action_err(unexpected(&other))),
        };
        level = r.conformity_level.value();
        for o in &r.device_id_objects {
            objects.insert(o.id, String::from_utf8_lossy(&o.value).into_owned());
        }
        if !r.more_follows {
            break;
        }
        if r.next_object_id <= next {
            debug!(
                next = r.next_object_id,
                "FC43: next object id does not advance"
            );
            break;
        }
        next = r.next_object_id;
    }
    Ok(Ok(level))
}

/// Device action `read_device_id`: FC43/14 basic objects, and the regular
/// ones when the device's conformity level has them → `{vendor_name,
/// product_code, revision, vendor_url, …}` (strings; an object without a
/// name of its own as `object_<id>`).
async fn read_device_id(t: &mut Transport, dev: &Device) -> Result<Value, LinkError> {
    if !t.select(dev.unit) {
        return Err(LinkError::invalid_parameter(NO_RTU_BROADCAST));
    }
    let mut objects = BTreeMap::new();
    let level = read_id_category(t, ReadCode::Basic, 0, &mut objects)
        .await?
        .map_err(|e| match e {
            ExceptionCode::IllegalFunction => LinkError::not_supported(
                "the device does not support FC43/14 Read Device Identification",
            ),
            e => exception_err(e),
        })?;
    // Conformity 0x02/0x03 (stream only) or 0x82/0x83: regular objects too.
    if level & 0x7F >= 2 {
        if let Err(e) = read_id_category(t, ReadCode::Regular, 3, &mut objects).await? {
            debug!("FC43 regular objects: device exception {e:?}");
        }
    }
    let named = objects
        .into_iter()
        .map(|(id, v)| {
            let name = ID_OBJECTS
                .get(usize::from(id))
                .map_or_else(|| format!("object_{id}"), |n| (*n).to_owned());
            (name, Value::Str(v))
        })
        .collect();
    Ok(Value::Map(named))
}

/// Connection action `scan_units {from = 1, to = 247, timeout_ms = 200}`:
/// one probe read (holding register 0) per unit, sent once with its own
/// timeout; any reply but a gateway's "target did not respond" counts, a
/// timeout skips the unit, a transport error stops the scan
/// (`disconnected`). Unit 0 is skipped on RTU (broadcast). → the answering
/// units. Holds the connection's owner for the whole scan: its polls wait.
async fn scan_units(
    t: &mut Transport,
    conn: &Conn,
    args: &BTreeMap<String, Value>,
) -> Result<Value, LinkError> {
    let from = arg_uint(args, "from", Some(1), (0, 255))?;
    let to = arg_uint(args, "to", Some(247), (0, 255))?;
    let (dflt, min, max) = SCAN_UNIT_MS;
    let per_unit = arg_uint(
        args,
        "timeout_ms",
        Some(dflt.into()),
        (min.into(), max.into()),
    )?;
    if from > to {
        return Err(LinkError::invalid_parameter(format!(
            "from: {from} is above to ({to})"
        )));
    }
    // Every silent unit costs its timeout and a reopen (ruling 7, P8).
    let reopen = match conn {
        Conn::Serial(c) => {
            u64::try_from(serial_guard(c, Duration::ZERO).as_millis()).unwrap_or(u64::MAX)
        }
        Conn::Ip(_) => 50,
    };
    let worst = (to - from + 1).saturating_mul(per_unit.saturating_add(reopen));
    let budget = u64::from(SCAN_ACTION_MS) - 1000;
    if worst > budget {
        return Err(LinkError::invalid_parameter(format!(
            "a scan of {} units at {per_unit} ms may take {} s, more than the {} s an action \
             may run: scan a smaller range or use a shorter timeout_ms",
            to - from + 1,
            worst / 1000,
            budget / 1000
        )));
    }
    let timeout = Duration::from_millis(per_unit);
    let unit_id = |u| u8::try_from(u).map_err(|_| LinkError::invalid_parameter("unit id"));
    let mut found = Vec::new();
    for unit in unit_id(from)?..=unit_id(to)? {
        if !t.select(unit) {
            continue;
        }
        match t
            .call_with(Request::ReadHoldingRegisters(0, 1), timeout, 0)
            .await
        {
            Ok(Ok(_)) => found.push(Value::UInt(unit.into())),
            // A gateway answers for a silent unit behind it.
            Ok(Err(ExceptionCode::GatewayTargetDevice | ExceptionCode::GatewayPathUnavailable)) => {
            }
            Ok(Err(_)) => found.push(Value::UInt(unit.into())),
            Err(DriverError::Transport(e)) => {
                return Err(LinkError::new(
                    Status::Disconnected,
                    format!("scan stopped at unit {unit}: {e}; answering before it: {found:?}"),
                ));
            }
            // No reply in time.
            Err(_) => {}
        }
    }
    Ok(Value::Array(found))
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
        let ctx = connect(conn, timeout, None).await?;
        let rtu = match conn {
            Conn::Ip(c) => c.transport == IpTransport::RtuOverTcp,
            Conn::Serial(_) => true,
        };
        Ok(Transport {
            ctx,
            conn: conn.clone(),
            timeout,
            retries: conn.retries(),
            write_mode: conn.write_mode(),
            rtu,
            unit: 1,
            unanswered: false,
            window_end: None,
            reopens: 0,
            outcomes: Vec::new(),
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
            Ping::Fc17 => t
                .call(Request::Custom(0x11, Vec::new().into()))
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
        match (p.table, p.dtype) {
            (Table::Coil, _) => {
                let Value::Bool(on) = v else {
                    return Err(DriverError::Point("expected true or false".into()));
                };
                t.write_req(if t.write_mode == WriteMode::Multiple {
                    Request::WriteMultipleCoils(p.addr, vec![*on].into())
                } else {
                    Request::WriteSingleCoil(p.addr, *on)
                })
                .await
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
                t.write_words(p.addr, words).await
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

    /// Bound on a ping and on opening the connection (each request inside
    /// is bounded by `timeout_ms`, with its retries).
    fn io_timeout(conn: &Conn) -> Duration {
        Duration::from_millis(u64::from(conn.timeout_ms()) * 4 * (1 + u64::from(conn.retries())))
    }

    /// Ruling 8: `timeout_ms × (1 + retries) × requests + 1 s`.
    fn poll_timeout(conn: &Conn, plan: &Plan) -> Duration {
        let per = u64::from(conn.timeout_ms()) * (1 + u64::from(conn.retries()));
        let n = u64::try_from(plan.requests()).unwrap_or(u64::MAX);
        Duration::from_millis(per.saturating_mul(n).saturating_add(1000))
    }

    /// Ruling P9: `timeout_ms × (1 + retries) × requests + 1 s`, where a
    /// register value written as a series of FC6 takes one request per
    /// word and a bit in a register up to three (FC22, then read and FC6);
    /// never below [`ModbusDriver::io_timeout`].
    fn write_timeout(conn: &Conn, p: &Point) -> Duration {
        let requests = match (p.table, p.dtype) {
            (Table::Holding, DType::Binary) => 3,
            _ => u64::from(p.words()),
        };
        let per = u64::from(conn.timeout_ms()) * (1 + u64::from(conn.retries()));
        let bound = Duration::from_millis(per.saturating_mul(requests).saturating_add(1000));
        bound.max(Self::io_timeout(conn))
    }

    /// Ruling P7: a series of FC6 may fail part-way; the read-back shows
    /// what the device holds.
    fn read_back_on_error(_dev: &Device) -> bool {
        true
    }

    fn republish(dev: &Device) -> Option<Duration> {
        (dev.republish_s > 0.0).then(|| Duration::from_secs_f64(dev.republish_s))
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

    /// Commissioning actions (ruling 13): `read_registers` and
    /// `read_device_id` on a device (level read), `scan_units` on a
    /// connection (level config).
    fn actions(level: Level, _kind: &str) -> Vec<(&'static str, ActionMeta)> {
        let read = |display: &str| {
            ActionMeta::new()
                .level(Perm::Read)
                .display(display)
                .timeout_ms(READ_ACTION_MS)
                .result(ActionResult::Type(TypeCode::Map))
        };
        match level {
            Level::Device => vec![
                (
                    "read_registers",
                    read("Read Registers")
                        .param(
                            "table",
                            enum_param("Object Type", Table::NAMES).required(true),
                        )
                        .param(
                            "addr",
                            uint_param("Offset", "first register or bit", None).required(true),
                        )
                        .param(
                            "count",
                            uint_param("Count", "registers or bits, 1…125", Some(1)),
                        )
                        .param(
                            "dtype",
                            enum_param("Data Type", &DTYPE_NAMES)
                                .description("decode the first registers (unscaled)"),
                        ),
                ),
                ("read_device_id", read("Read Device Identification")),
            ],
            Level::Connection => vec![(
                "scan_units",
                ActionMeta::new()
                    .level(Perm::Config)
                    .display("Scan Unit IDs")
                    .timeout_ms(SCAN_ACTION_MS)
                    .result(ActionResult::Type(TypeCode::Array))
                    .param("from", uint_param("From", "first unit id", Some(1)))
                    .param("to", uint_param("To", "last unit id", Some(247)))
                    .param(
                        "timeout_ms",
                        uint_param(
                            "Timeout per Unit (ms)",
                            "20…1000; polling of this connection waits during a scan",
                            Some(SCAN_UNIT_MS.0.into()),
                        ),
                    ),
            )],
        }
    }

    async fn invoke(
        t: &mut Transport,
        conn: &Conn,
        target: Target<'_, Self>,
        action: &str,
        args: &Value,
    ) -> Result<Value, LinkError> {
        let empty = BTreeMap::new();
        let args = match args {
            Value::Map(m) => m,
            _ => &empty,
        };
        match (target, action) {
            (Target::Device { dev, .. }, "read_registers") => read_registers(t, dev, args).await,
            (Target::Device { dev, .. }, "read_device_id") => read_device_id(t, dev).await,
            (Target::Connection, "scan_units") => scan_units(t, conn, args).await,
            _ => Err(LinkError::not_supported(format!("action {action}"))),
        }
    }

    const DIAGNOSTICS: bool = true;
    const DIAG_EXTRA: &'static [&'static str] = &[REOPENS];

    fn take_outcomes(t: &mut Transport) -> Vec<Outcome> {
        std::mem::take(&mut t.outcomes)
    }
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

#[cfg(test)]
mod guard_tests {
    use super::{serial_guard, settle, ClearInput, Conn, SerialConn};
    use std::sync::Mutex;
    use std::time::Duration;
    use wyrm_core::Value;
    use wyrm_link_sdk::driver::Params;

    fn serial(kv: &[(&str, Value)]) -> SerialConn {
        let mut m: std::collections::BTreeMap<String, Value> = kv
            .iter()
            .map(|(k, v)| ((*k).to_owned(), v.clone()))
            .collect();
        m.insert("serial_port".into(), "/dev/ttyUSB0".into());
        match Conn::from_kind_value("serial_connection", &Value::Map(m)).unwrap() {
            Conn::Serial(c) => c,
            Conn::Ip(_) => unreachable!(),
        }
    }

    /// Ruling P10: 3.5 character times, at least 50 ms, plus the rest of
    /// the unanswered request's window.
    #[test]
    fn guard_is_the_frame_gap_or_50_ms_plus_the_rest() {
        let ms = Duration::from_millis;
        // 9600 8N1: 10 bits, 3.5 chars = 3.6 ms → 50 ms
        assert_eq!(serial_guard(&serial(&[]), Duration::ZERO), ms(50));
        assert_eq!(serial_guard(&serial(&[]), ms(120)), ms(170));
        // 300 baud 8E2: 12 bits, 3.5 chars = 140 ms
        let slow = serial(&[
            ("baud_rate", Value::UInt(300)),
            ("parity", "even".into()),
            ("stop_bits", Value::UInt(2)),
        ]);
        assert_eq!(serial_guard(&slow, Duration::ZERO), ms(140));
        // 1200 7O1: 10 bits, 3.5 chars ≈ 29 ms → 50 ms
        let seven = serial(&[
            ("baud_rate", Value::UInt(1200)),
            ("data_bits", Value::UInt(7)),
            ("parity", "odd".into()),
        ]);
        assert_eq!(serial_guard(&seven, ms(10)), ms(60));
    }

    /// A port that records when its input was cleared.
    struct Fake {
        cleared: Mutex<Vec<tokio::time::Instant>>,
    }

    impl ClearInput for Fake {
        fn clear_input(&self) -> std::io::Result<()> {
            self.cleared
                .lock()
                .unwrap()
                .push(tokio::time::Instant::now());
            Ok(())
        }
    }

    /// The input is cleared once, after the whole guard.
    #[tokio::test(start_paused = true)]
    async fn settle_waits_then_clears_once() {
        let port = Fake {
            cleared: Mutex::new(Vec::new()),
        };
        let t0 = tokio::time::Instant::now();
        settle(&port, Duration::from_millis(170)).await.unwrap();
        let cleared = port.cleared.lock().unwrap();
        assert_eq!(cleared.len(), 1);
        assert!(cleared[0] - t0 >= Duration::from_millis(170));
    }
}
