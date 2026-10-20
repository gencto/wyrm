//! Modbus TCP connector on the driver framework (ADR 0004).
//!
//! Tree: `<conn>/<device>/<point>`; kinds [`IpConn`] → [`Device`] → [`Point`].
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
//! Every request is bounded by `timeout_ms`; a timeout is a device miss, an
//! I/O or protocol error drops the connection. Serial (RTU) is not supported
//! yet.

#![forbid(unsafe_code)]

pub mod codec;
#[cfg(feature = "sim")]
pub mod sim;

use codec::{DType, Span};
use std::collections::{BTreeMap, HashSet};
use std::net::SocketAddr;
use std::sync::LazyLock;
use std::time::Duration;
use tokio_modbus::client::{tcp, Client, Context, Reader, Writer};
use tokio_modbus::slave::SlaveContext;
use tokio_modbus::{ExceptionCode, Request, Slave};
use wyrm_core::meta::Writable;
use wyrm_core::{NodeMeta, TypeCode, Value};
use wyrm_link_sdk::driver::params::{field, ParamSpec};
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

#[derive(Debug, Clone, PartialEq, Params)]
pub struct IpConn {
    pub host: String,
    #[param(default = 502)]
    pub port: u16,
    /// Bound on each request.
    #[param(default = 1000, min = 100, max = 10000)]
    pub timeout_ms: u32,
    #[param(enum, default = "auto")]
    pub write_mode: WriteMode,
}

#[derive(Debug, Clone, PartialEq, Params)]
pub struct Device {
    #[param(min = 1, max = 247)]
    pub unit: u8,
    #[param(enum, default = "probe")]
    pub ping: Ping,
    #[param(enum, default = "holding")]
    pub probe_table: Table,
    #[param(default = 0)]
    pub probe_addr: u16,
    #[param(default = 5.0, min = 0.1, max = 3600.0)]
    pub ping_s: f64,
    /// Read gaps between points (`false`) or only adjacent registers.
    #[param(default = false)]
    pub contiguous_only: bool,
    #[param(default = 125, min = 1, max = 125)]
    pub max_regs: u16,
    #[param(default = 2000, min = 1, max = 2000)]
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

impl Params for Point {
    fn schema() -> Vec<ParamSpec> {
        vec![
            ParamSpec::new("table", TypeCode::Enum).one_of(Table::NAMES),
            ParamSpec::new("addr", TypeCode::Number).bounds(0.0, 65535.0),
            ParamSpec::new("dtype", TypeCode::Enum)
                .one_of(*DTYPE_NAMES)
                .default("u16"),
            ParamSpec::new("bit", TypeCode::Number)
                .default(0u64)
                .bounds(0.0, 15.0)
                .desc("bit of a register for dtype binary"),
            ParamSpec::new("regs", TypeCode::Number)
                .default(1u64)
                .bounds(1.0, 125.0)
                .desc("registers of a char/varchar value"),
            ParamSpec::new("poll_s", TypeCode::Number)
                .default(1.0)
                .bounds(0.01, 86_400.0),
            ParamSpec::new("scale", TypeCode::Number).default(1.0),
            ParamSpec::new("offset", TypeCode::Number).default(0.0),
            ParamSpec::new("writable", TypeCode::Bool).default(false),
            ParamSpec::new("unit", TypeCode::String).default(""),
        ]
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

pub struct Transport {
    ctx: Context,
    timeout: Duration,
    write_mode: WriteMode,
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

impl Transport {
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
    type Conn = IpConn;
    type Dev = Device;
    type Point = Point;
    type Transport = Transport;
    type Plan = Plan;

    async fn open(conn: &IpConn) -> Result<Transport, DriverError> {
        let timeout = Duration::from_millis(conn.timeout_ms.into());
        let target = format!("{}:{}", conn.host, conn.port);
        let addr: SocketAddr = tokio::time::timeout(timeout, tokio::net::lookup_host(&target))
            .await
            .map_err(|_| DriverError::Transport(format!("resolve {target}: timeout")))?
            .map_err(|e| DriverError::Transport(format!("resolve {target}: {e}")))?
            .next()
            .ok_or_else(|| DriverError::Transport(format!("resolve {target}: no address")))?;
        let ctx = tokio::time::timeout(timeout, tcp::connect_slave(addr, Slave(1)))
            .await
            .map_err(|_| DriverError::Transport(format!("connect {target}: timeout")))?
            .map_err(|e| DriverError::Transport(format!("connect {target}: {e}")))?;
        Ok(Transport {
            ctx,
            timeout,
            write_mode: conn.write_mode,
            no_fc22: HashSet::new(),
        })
    }

    async fn ping(t: &mut Transport, dev: &Device) -> Result<(), DriverError> {
        t.ctx.set_slave(Slave(dev.unit));
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
        t.ctx.set_slave(Slave(dev.unit));
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
        t.ctx.set_slave(Slave(dev.unit));
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
    fn io_timeout(conn: &IpConn) -> Duration {
        Duration::from_millis(u64::from(conn.timeout_ms) * 4)
    }
}
