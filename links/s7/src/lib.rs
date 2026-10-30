//! Siemens S7 connector (S7comm over ISO-on-TCP) on the driver framework
//! (ADR 0004), for S7-300/400/1200/1500 CPUs with absolute addressing.
//!
//! Tree: `<conn>/<device>/<point>`; kinds [`Conn`] (a PLC: host, port 102,
//! rack, slot, connection type, PDU size) → [`Dev`] (one CPU: ping and
//! batching) → [`Point`] (an address in Siemens notation, `DB10.DBX4.3`,
//! `DB10.DBD8:REAL`, `MW20`, `IB0`, `T5`, `C3`, with a data type). The
//! framework owns states, scheduling, edits, polling (all the time by
//! default), read-back writes and the quality ladder; this crate only does
//! protocol I/O, with its own codec ([`proto`]: TPKT, COTP class 0, S7
//! setup, Read Var, Write Var, SZL):
//!
//! * reads: the points of a poll group merge into spans per area and DB
//!   when at most `max_gap` bytes apart ([`plan`]); spans become Read Var
//!   items packed into as few requests as the negotiated PDU and
//!   `max_items` allow, a span longer than one reply is cut into several
//!   items. An item's return code fails the points of that item only, and
//!   a failed merged item is read again point by point, so one bad address
//!   never fails its neighbours (it is read alone from then on, when a
//!   neighbour read OK alone).
//! * writes: one Write Var per point (a BOOL with the bit transport size,
//!   no read-modify-write of its byte; a STRING from its actual-length
//!   byte, never its maximum, and bounded by the maximum the PLC holds);
//!   a value longer than one request is written in parts. The framework
//!   reads the point back.
//! * ping: SZL 0x0011 (module identification) or a 1-byte read of a
//!   configured address; any answer, an error included, means alive.
//! * every request carries a PDU reference; a late reply to a request that
//!   timed out is dropped and counted (`late_replies`, [`client`]).
//!
//! Error classes ([`DriverError`]): an I/O error, a closed socket or a
//! garbled frame → `Transport` (reconnect with backoff); no reply in time →
//! `Device` (quality ladder); a header error class/code or an item return
//! code → `Point` with the PLC's error text (S7-1200/1500 without PUT/GET
//! access answer 0x8104).
//!
//! Driver actions (run between polls): connection `connection_info` (level
//! read: the negotiated PDU size and parallel jobs, the TSAPs), device
//! `read_szl` (one SZL list, the order code of 0x0011) and `read_address`
//! (one value at any address, unscaled), both commissioning at level
//! config (they hold the connection).
//!
//! Not supported: S7comm-plus (symbolic access, the protected protocol of
//! newer 1200/1500 firmware), optimized DBs, the protection-level
//! password of S7-300/400, program upload/download, alarms, writes to
//! inputs, timers and counters.

#![forbid(unsafe_code)]

pub mod addr;
pub mod client;
pub mod plan;
pub mod proto;
#[cfg(feature = "sim")]
pub mod sim;

use addr::{Address, Area, Conv, DType, DTYPE_NAMES};
use client::{Client, Target as ClientTarget, LATE_REPLIES, MIN_PDU};
use plan::{Chunk, Loc, Span};
use proto::Item;
use std::collections::{BTreeMap, BTreeSet};
use std::sync::{Arc, Mutex};
use std::time::Duration;
use wyrm_core::meta::{ActionResult, ParamMeta, Writable};
use wyrm_core::{ActionMeta, NodeMeta, Perm, Status, TypeCode, Value};
use wyrm_link_sdk::driver::params::{field, ParamSpec};
// Traits (type namespace) beside the derive macros of the same name.
use wyrm_link_sdk::driver::{
    Driver, DriverError, Framework, Level, Outcome, Params, PointId, Target,
};
use wyrm_link_sdk::LinkError;
use wyrm_link_sdk::{ParamEnum, Params};

/// The `s7` link: the framework running [`S7Driver`].
pub type S7 = Framework<S7Driver>;

/// The connection resource type of the remote TSAP.
#[derive(Debug, Clone, Copy, PartialEq, Eq, ParamEnum)]
pub enum ConnType {
    /// Programming device (PG), 0x01.
    Pg,
    /// Operator panel (OP), 0x02.
    Op,
    /// S7 basic communication, 0x03.
    S7Basic,
}

impl ConnType {
    fn code(self) -> u8 {
        match self {
            ConnType::Pg => 1,
            ConnType::Op => 2,
            ConnType::S7Basic => 3,
        }
    }
}

/// A PLC.
#[derive(Debug, Clone, PartialEq, Params)]
pub struct Conn {
    #[param(display = "Host", placeholder = "192.168.0.1", dest)]
    pub host: String,
    #[param(default = 102, display = "Port", dest)]
    pub port: u16,
    #[param(default = 0, min = 0, max = 7, display = "Rack")]
    pub rack: u8,
    /// The CPU's slot: 1 on S7-1200/1500, 2 on S7-300, as configured on
    /// S7-400.
    #[param(
        default = 1,
        min = 0,
        max = 31,
        display = "Slot",
        desc = "1 for S7-1200/1500, 2 for S7-300"
    )]
    pub slot: u8,
    #[param(enum, default = "pg", display = "Connection Type")]
    pub conn_type: ConnType,
    /// Bound on each request (and on each step of connecting).
    #[param(default = 2000, min = 100, max = 10000, display = "Timeout (ms)")]
    pub timeout_ms: u32,
    /// The PDU size asked for; the PLC may agree on less
    /// (`connection_info` shows it).
    #[param(default = 480, min = 240, max = 960, display = "PDU Size")]
    pub pdu_size: u16,
}

impl Conn {
    fn timeout(&self) -> Duration {
        Duration::from_millis(self.timeout_ms.into())
    }

    fn target(&self) -> ClientTarget {
        ClientTarget {
            host: self.host.clone(),
            port: self.port,
            local_tsap: proto::LOCAL_TSAP,
            remote_tsap: proto::remote_tsap(self.conn_type.code(), self.rack, self.slot),
            pdu: self.pdu_size,
            timeout: self.timeout(),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, ParamEnum)]
pub enum Ping {
    /// Read SZL 0x0011 (module identification).
    Szl,
    /// Read 1 byte at `ping_address`.
    Read,
    None,
}

/// The fields of a device (one CPU).
#[derive(Debug, Clone, PartialEq, Params)]
pub struct DevParams {
    #[param(enum, default = "szl", display = "Ping")]
    pub ping: Ping,
    #[param(
        default = "MB0",
        display = "Ping Address",
        desc = "read 1 byte here when Ping is read"
    )]
    pub ping_address: String,
    #[param(default = 5.0, min = 0.1, max = 3600.0, display = "Ping Rate (s)")]
    pub ping_s: f64,
    /// Points of one area and DB at most this many bytes apart are read
    /// as one item (0 = only touching ones).
    #[param(
        default = 4,
        min = 0,
        max = 256,
        display = "Max Gap (bytes)",
        desc = "read points this close as one item"
    )]
    pub max_gap: u32,
    #[param(default = 20, min = 1, max = 20, display = "Max Items per Read")]
    pub max_items: u8,
    /// The PLC clock's offset from UTC (DATE_AND_TIME values).
    #[param(
        default = 0,
        min = -720,
        max = 840,
        display = "PLC Clock Offset (min)",
        desc = "DATE_AND_TIME: the PLC clock's offset from UTC"
    )]
    pub tz_offset_min: i32,
    /// Publish an unchanged value again after this long (0 = only on a
    /// change).
    #[param(
        default = 0.0,
        min = 0.0,
        max = 3600.0,
        display = "Republish Unchanged Values (s)"
    )]
    pub republish_s: f64,
}

/// A device: its fields and the parsed ping address.
#[derive(Debug, Clone, PartialEq)]
pub struct Dev {
    pub p: DevParams,
    pub ping_addr: Address,
}

impl Params for Dev {
    fn schema() -> Vec<ParamSpec> {
        DevParams::schema()
    }

    fn from_map(m: &BTreeMap<String, Value>) -> wyrm_link_sdk::Result<Self> {
        let p = DevParams::from_map(m)?;
        let ping_addr = Address::parse(&p.ping_address)
            .map_err(|e| LinkError::invalid_parameter(format!("ping_address: {e}")))?;
        Ok(Dev { p, ping_addr })
    }

    fn to_map(&self) -> BTreeMap<String, Value> {
        self.p.to_map()
    }
}

/// One point. Hand-written `Params`: the address is parsed and checked
/// against the data type, and the rules cross fields.
#[derive(Debug, Clone, PartialEq)]
pub struct Point {
    /// The address as entered.
    pub address: String,
    /// The `dtype` param as entered (`auto` or a type name).
    pub dtype: String,
    pub poll_s: f64,
    pub scale: f64,
    pub offset: f64,
    pub writable: bool,
    pub unit: String,
    pub addr: Address,
    /// The resolved data type.
    pub ty: DType,
}

impl Point {
    fn loc(&self) -> Loc {
        Loc {
            area: self.addr.area,
            db: self.addr.db,
            start: self.addr.start,
            units: if self.addr.area.is_tc() {
                1
            } else {
                self.ty.size()
            },
        }
    }

    fn conv(&self, dev: &Dev) -> Conv {
        Conv {
            scale: self.scale,
            offset: self.offset,
            tz_min: dev.p.tz_offset_min,
        }
    }
}

impl Params for Point {
    fn schema() -> Vec<ParamSpec> {
        vec![
            ParamSpec::new("address", TypeCode::String)
                .placeholder("DB1.DBW0")
                .desc("DB10.DBX4.3, DB10.DBD8:REAL, DB1.DBB0:STRING[16], MW20, IB0, QX1.0, T5, C3")
                .display("Address"),
            ParamSpec::new("dtype", TypeCode::Enum)
                .one_of(DTYPE_NAMES)
                .default("auto")
                .desc("auto: the address's :TYPE, else X bool, B byte, W word, D dword, T s5time, C word")
                .display("Data Type"),
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

    fn from_map(m: &BTreeMap<String, Value>) -> wyrm_link_sdk::Result<Self> {
        let bad = |e: String| LinkError::invalid_parameter(e);
        let address = field::string(m, "address")?.trim().to_owned();
        let dtype = field::string(m, "dtype")?;
        let addr = Address::parse(&address).map_err(bad)?;
        let ty = addr
            .resolve(DType::from_param(&dtype).map_err(bad)?)
            .map_err(bad)?;
        let p = Point {
            address,
            dtype,
            poll_s: field::f64(m, "poll_s")?,
            scale: field::f64(m, "scale")?,
            offset: field::f64(m, "offset")?,
            writable: field::bool(m, "writable")?,
            unit: field::string(m, "unit")?,
            addr,
            ty,
        };
        if p.scale == 0.0 || !p.scale.is_finite() || !p.offset.is_finite() {
            return Err(bad("scale: must be a finite number other than 0".into()));
        }
        if !ty.is_number() && (p.scale != 1.0 || p.offset != 0.0) {
            return Err(bad(format!(
                "scale: {} is not a number; scale and offset apply to numbers only",
                ty.name()
            )));
        }
        if p.writable && matches!(addr.area, Area::Input | Area::Timer | Area::Counter) {
            return Err(bad(
                "writable: inputs, timers and counters are not written by this link".into(),
            ));
        }
        Ok(p)
    }

    fn to_map(&self) -> BTreeMap<String, Value> {
        BTreeMap::from([
            ("address".into(), Value::Str(self.address.clone())),
            ("dtype".into(), Value::Str(self.dtype.clone())),
            ("poll_s".into(), Value::Float(self.poll_s)),
            ("scale".into(), Value::Float(self.scale)),
            ("offset".into(), Value::Float(self.offset)),
            ("writable".into(), Value::Bool(self.writable)),
            ("unit".into(), Value::Str(self.unit.clone())),
        ])
    }
}

/// Spans and requests at one PDU size.
struct Packed {
    pdu: u16,
    /// Points read alone when this was packed.
    alone: usize,
    spans: Vec<Span>,
    reqs: Vec<Vec<Chunk>>,
}

/// The read plan of one `(device, poll period)` group: the points, and
/// their spans and requests packed for the negotiated PDU (cached).
pub struct Plan {
    points: Vec<(PointId, Point)>,
    locs: Vec<Loc>,
    max_gap: u32,
    max_items: usize,
    /// Points whose merged read failed and that failed alone while a
    /// neighbour of the same span read OK alone: never merged again in
    /// this plan.
    alone: Mutex<BTreeSet<usize>>,
    cache: Mutex<Option<Arc<Packed>>>,
    /// Requests of one poll at the smallest PDU, a read again point by
    /// point included (the poll's bound).
    worst_requests: usize,
}

fn lock<T>(m: &Mutex<T>) -> std::sync::MutexGuard<'_, T> {
    m.lock().unwrap_or_else(|p| p.into_inner())
}

impl Plan {
    fn new(dev: &Dev, points: &[(PointId, Point)]) -> Plan {
        let locs: Vec<Loc> = points.iter().map(|(_, p)| p.loc()).collect();
        let max_items = usize::from(dev.p.max_items);
        // the first pass merged, or with points read alone (at most every
        // point alone); then the points of failed merged items again, one
        // by one (at most all of them)
        let merged = plan::pack(
            &plan::merge(&locs, dev.p.max_gap, |_| false),
            MIN_PDU,
            max_items,
        )
        .len();
        let singles = plan::pack(&plan::merge(&locs, 0, |_| true), MIN_PDU, max_items).len();
        let worst_requests = merged.max(singles) + singles;
        Plan {
            points: points.to_vec(),
            locs,
            max_gap: dev.p.max_gap,
            max_items,
            alone: Mutex::new(BTreeSet::new()),
            cache: Mutex::new(None),
            worst_requests,
        }
    }

    /// Spans and requests for `pdu`, packed once per PDU size (and again
    /// when a point was found to be read alone).
    fn packed(&self, pdu: u16) -> Arc<Packed> {
        let alone = lock(&self.alone).clone();
        let mut cache = lock(&self.cache);
        if let Some(p) = cache.as_ref() {
            if p.pdu == pdu && p.alone == alone.len() {
                return p.clone();
            }
        }
        let spans = plan::merge(&self.locs, self.max_gap, |i| alone.contains(&i));
        let reqs = plan::pack(&spans, pdu, self.max_items);
        let p = Arc::new(Packed {
            pdu,
            alone: alone.len(),
            spans,
            reqs,
        });
        *cache = Some(p.clone());
        p
    }
}

/// What [`read_spans`] read.
struct Reads {
    /// The bytes of each span.
    bufs: Vec<Vec<u8>>,
    /// The error of each span, if any.
    errs: Vec<Option<DriverError>>,
    /// The span failed by an item return code only: reading its points
    /// one by one may help. A header error (the whole request refused,
    /// PUT/GET for one) fails them all alike, so it never does.
    by_item: Vec<bool>,
    /// The error that stopped the reads (a broken transport or no reply;
    /// the requests after it were not sent).
    stop: Option<DriverError>,
}

/// The bytes of `spans` read by `reqs`.
async fn read_spans(c: &mut Client, spans: &[Span], reqs: &[Vec<Chunk>]) -> Reads {
    let mut bufs: Vec<Vec<u8>> = spans.iter().map(|s| vec![0; s.bytes()]).collect();
    let mut errs: Vec<Option<DriverError>> = vec![None; spans.len()];
    let mut item = vec![false; spans.len()];
    let mut other = vec![false; spans.len()];
    let mut stop: Option<DriverError> = None;
    for req in reqs {
        if let Some(e) = &stop {
            for ch in req {
                errs[ch.span] = Some(e.clone());
                other[ch.span] = true;
            }
            continue;
        }
        let items: Vec<Item> = req
            .iter()
            .map(|ch| {
                let s = &spans[ch.span];
                Item::bytes(s.area, s.db, s.start + ch.offset, ch.units as u16)
            })
            .collect();
        match c.read(&items).await {
            Ok(res) => {
                for (ch, r) in req.iter().zip(res) {
                    let ub = spans[ch.span].area.unit_bytes() as usize;
                    let (from, want) = (ch.offset as usize * ub, ch.units as usize * ub);
                    match r {
                        Ok(data) if data.len() >= want => {
                            bufs[ch.span][from..from + want].copy_from_slice(&data[..want]);
                        }
                        Ok(data) => {
                            other[ch.span] = true;
                            errs[ch.span].get_or_insert(DriverError::Point(format!(
                                "short reply: {} of {want} bytes",
                                data.len()
                            )));
                        }
                        Err(rc) => {
                            item[ch.span] = true;
                            errs[ch.span].get_or_insert(DriverError::Point(proto::item_text(rc)));
                        }
                    }
                }
            }
            Err(e @ DriverError::Point(_)) => {
                for ch in req {
                    other[ch.span] = true;
                    errs[ch.span].get_or_insert(e.clone());
                }
            }
            Err(e) => {
                for ch in req {
                    other[ch.span] = true;
                    errs[ch.span] = Some(e.clone());
                }
                stop = Some(e);
            }
        }
    }
    let by_item = item.iter().zip(&other).map(|(i, o)| *i && !*o).collect();
    Reads {
        bufs,
        errs,
        by_item,
        stop,
    }
}

fn decode(p: &Point, dev: &Dev, bytes: &[u8]) -> Result<Value, DriverError> {
    addr::decode(p.ty, bytes, p.addr.bit, &p.conv(dev))
        .map_err(|e| DriverError::Point(e.to_string()))
}

/// Bound on the read actions: a STRING[254] at the smallest PDU and the
/// longest timeout.
const READ_ACTION_MS: u32 = 32_000;

fn param(display: &str, desc: &str, ty: TypeCode) -> ParamMeta {
    ParamMeta::of(ty).display(display).description(desc)
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

fn arg_u16(
    args: &BTreeMap<String, Value>,
    name: &str,
    default: Option<u16>,
) -> Result<u16, LinkError> {
    let Some(v) = args.get(name) else {
        return default.ok_or_else(|| LinkError::invalid_parameter(format!("missing {name}")));
    };
    let n = match v {
        Value::UInt(u) => u16::try_from(*u).ok(),
        Value::Int(i) => u16::try_from(*i).ok(),
        Value::Float(f) if f.fract() == 0.0 && (0.0..=65535.0).contains(f) => Some(*f as u16),
        _ => None,
    };
    n.ok_or_else(|| LinkError::invalid_parameter(format!("{name}: expected 0…65535")))
}

/// Device action `read_szl {id, index = 0}`.
async fn read_szl(c: &mut Client, args: &BTreeMap<String, Value>) -> Result<Value, LinkError> {
    let id = arg_u16(args, "id", None)?;
    let index = arg_u16(args, "index", Some(0))?;
    let s = c.szl(id, index).await.map_err(action_err)?;
    if s.error != 0 {
        return Err(LinkError::new(
            Status::NotAvailable,
            proto::error_text(s.error),
        ));
    }
    let mut out = BTreeMap::from([
        ("id".to_owned(), Value::UInt(s.id.into())),
        ("index".to_owned(), Value::UInt(s.index.into())),
        ("record_length".to_owned(), Value::UInt(s.record_len.into())),
        ("more".to_owned(), Value::Bool(s.more)),
    ]);
    // SZL 0x0011: the record with index 1 holds the order code (MLFB)
    if s.id & 0x00FF == 0x11 {
        let code = s
            .records
            .iter()
            .find(|r| r.len() >= 22 && r[..2] == [0, 1])
            .map(|r| r[2..22].iter().map(|&b| char::from(b)).collect::<String>());
        if let Some(code) = code {
            out.insert("order_code".into(), Value::Str(code.trim().to_owned()));
        }
    }
    out.insert(
        "records".into(),
        Value::Array(s.records.into_iter().map(Value::Bytes).collect()),
    );
    Ok(Value::Map(out))
}

/// Device action `read_address {address, dtype = auto}`: one value,
/// unscaled.
async fn read_address(
    c: &mut Client,
    dev: &Dev,
    args: &BTreeMap<String, Value>,
) -> Result<Value, LinkError> {
    let Some(Value::Str(text)) = args.get("address") else {
        return Err(LinkError::invalid_parameter("missing address"));
    };
    let a = Address::parse(text).map_err(LinkError::invalid_parameter)?;
    let dtype = match args.get("dtype") {
        None => None,
        Some(Value::Str(s)) => DType::from_param(s).map_err(LinkError::invalid_parameter)?,
        Some(_) => return Err(LinkError::invalid_parameter("dtype: expected a name")),
    };
    let ty = a.resolve(dtype).map_err(LinkError::invalid_parameter)?;
    let span = Span {
        area: a.area,
        db: a.db,
        start: a.start,
        units: if a.area.is_tc() { 1 } else { ty.size() },
        members: vec![0],
    };
    let reqs = plan::pack(
        std::slice::from_ref(&span),
        c.pdu(),
        usize::from(dev.p.max_items),
    );
    let Reads { bufs, errs, .. } = read_spans(c, std::slice::from_ref(&span), &reqs).await;
    if let Some(e) = errs.into_iter().next().flatten() {
        return Err(action_err(e));
    }
    let conv = Conv {
        tz_min: dev.p.tz_offset_min,
        ..Conv::RAW
    };
    let v = addr::decode(ty, &bufs[0], a.bit, &conv)
        .map_err(|e| LinkError::new(Status::NotAvailable, e.to_string()))?;
    Ok(Value::Map(BTreeMap::from([
        ("value".to_owned(), v),
        ("dtype".to_owned(), Value::Str(ty.to_string())),
    ])))
}

/// Connection action `connection_info`.
fn connection_info(c: &Client) -> Value {
    let hex = |x: u16| Value::Str(format!("0x{x:04X}"));
    Value::Map(BTreeMap::from([
        ("pdu_size".to_owned(), Value::UInt(c.setup.pdu.into())),
        (
            "max_amq_calling".to_owned(),
            Value::UInt(c.setup.amq_calling.into()),
        ),
        (
            "max_amq_called".to_owned(),
            Value::UInt(c.setup.amq_called.into()),
        ),
        ("local_tsap".to_owned(), hex(c.local_tsap)),
        ("remote_tsap".to_owned(), hex(c.remote_tsap)),
        ("late_replies".to_owned(), Value::UInt(c.late)),
    ]))
}

/// Requests a write of `p` takes at the smallest PDU (a STRING's one more:
/// the read of its maximum-length byte).
fn write_requests(p: &Point) -> u64 {
    let per = usize::from(MIN_PDU) - proto::WRITE_FIXED;
    let parts: u64 = p.ty.size().div_ceil(per as u32).max(1).into();
    parts + u64::from(matches!(p.ty, DType::String(_)))
}

/// The maximum-length byte the PLC holds for the STRING at `a`.
async fn string_max(c: &mut Client, a: &Address) -> Result<u8, DriverError> {
    let res = c.read(&[Item::bytes(a.area, a.db, a.start, 1)]).await?;
    match res.into_iter().next() {
        Some(Ok(data)) => data.first().copied().ok_or_else(|| {
            DriverError::Point("short reply: 0 of 1 bytes (the STRING's maximum length)".into())
        }),
        Some(Err(rc)) => Err(DriverError::Point(proto::item_text(rc))),
        None => Err(DriverError::Point(
            "no reply item (the STRING's maximum length)".into(),
        )),
    }
}

pub struct S7Driver;

impl Driver for S7Driver {
    const NAME: &'static str = "s7";
    const VERSION: &'static str = env!("CARGO_PKG_VERSION");
    type Conn = Conn;
    type Dev = Dev;
    type Point = Point;
    type Transport = Client;
    type Plan = Plan;

    async fn open(conn: &Conn) -> Result<Client, DriverError> {
        Client::connect(&conn.target()).await
    }

    async fn ping(c: &mut Client, dev: &Dev) -> Result<(), DriverError> {
        let r = match dev.p.ping {
            Ping::None => return Ok(()),
            Ping::Szl => c.szl(0x0011, 0).await.map(|_| ()),
            Ping::Read => {
                let a = dev.ping_addr;
                c.read(&[Item::bytes(a.area, a.db, a.start, 1)])
                    .await
                    .map(|_| ())
            }
        };
        match r {
            // the PLC answered, with an error or not: it is alive
            Ok(()) | Err(DriverError::Point(_)) => Ok(()),
            Err(e) => Err(e),
        }
    }

    fn plan(dev: &Dev, points: &[(PointId, Point)]) -> Plan {
        Plan::new(dev, points)
    }

    async fn poll(
        c: &mut Client,
        dev: &Dev,
        plan: &Plan,
    ) -> Vec<(PointId, Result<Value, DriverError>)> {
        let pdu = c.pdu();
        let packed = plan.packed(pdu);
        let Reads {
            bufs,
            errs,
            by_item,
            stop,
        } = read_spans(c, &packed.spans, &packed.reqs).await;
        let mut out = Vec::with_capacity(plan.points.len());
        // points to read one by one, with the merged span each came from
        let mut again: Vec<usize> = Vec::new();
        let mut from: Vec<usize> = Vec::new();
        for (si, s) in packed.spans.iter().enumerate() {
            match &errs[si] {
                // a merged item failed by its return code: read its
                // points one by one
                Some(DriverError::Point(_))
                    if by_item[si] && s.members.len() > 1 && stop.is_none() =>
                {
                    again.extend(&s.members);
                    from.extend(std::iter::repeat_n(si, s.members.len()));
                }
                Some(e) => {
                    for &i in &s.members {
                        out.push((plan.points[i].0.clone(), Err(e.clone())));
                    }
                }
                None => {
                    for &i in &s.members {
                        let (id, p) = &plan.points[i];
                        let r = s.range(&plan.locs[i]);
                        out.push((id.clone(), decode(p, dev, &bufs[si][r])));
                    }
                }
            }
        }
        if again.is_empty() {
            return out;
        }
        let singles: Vec<Span> = again
            .iter()
            .map(|&i| {
                let l = plan.locs[i];
                Span {
                    area: l.area,
                    db: l.db,
                    start: l.start,
                    units: l.units,
                    members: vec![i],
                }
            })
            .collect();
        let reqs = plan::pack(&singles, pdu, plan.max_items);
        let Reads {
            bufs,
            errs,
            by_item,
            ..
        } = read_spans(c, &singles, &reqs).await;
        // merged spans of which at least one point read OK alone
        let isolated: BTreeSet<usize> = (0..singles.len())
            .filter(|&k| errs[k].is_none())
            .map(|k| from[k])
            .collect();
        let mut alone = Vec::new();
        for (si, s) in singles.iter().enumerate() {
            let i = s.members[0];
            let (id, p) = &plan.points[i];
            match &errs[si] {
                Some(e) => {
                    // it fails alone by its own return code while a
                    // neighbour of its span reads: read it alone from now
                    // on. When all fail (the DB is gone for a while),
                    // there is nothing to isolate and merging stays.
                    if by_item[si] && isolated.contains(&from[si]) {
                        alone.push(i);
                    }
                    out.push((id.clone(), Err(e.clone())));
                }
                None => out.push((id.clone(), decode(p, dev, &bufs[si]))),
            }
        }
        if !alone.is_empty() {
            tracing::debug!(points = alone.len(), "s7: points read alone from now on");
            lock(&plan.alone).extend(alone);
        }
        out
    }

    async fn write(
        c: &mut Client,
        dev: &Dev,
        _id: &str,
        p: &Point,
        v: &Value,
    ) -> Result<(), DriverError> {
        if !p.writable {
            return Err(DriverError::Point("point is read-only".into()));
        }
        let bytes =
            addr::encode(p.ty, v, &p.conv(dev)).map_err(|e| DriverError::Point(e.to_string()))?;
        let a = p.addr;
        if p.ty == DType::Bool {
            return c
                .write(&Item::bit(a.area, a.db, a.start, a.bit), &bytes)
                .await;
        }
        if let DType::String(_) = p.ty {
            // the PLC does not stop a byte write at the string's end: bound
            // the text by its own maximum-length byte, not the configured `n`
            let max = string_max(c, &a).await?;
            let len = bytes.len() - 1;
            if len > usize::from(max) {
                return Err(DriverError::Point(format!(
                    "text of {len} characters does not fit the PLC's STRING[{max}]"
                )));
            }
        }
        // a STRING from its actual-length byte: the maximum stays the PLC's
        let start = a.start + u32::from(matches!(p.ty, DType::String(_)));
        let per = (usize::from(c.pdu()) - proto::WRITE_FIXED) & !1;
        let parts = bytes.len().div_ceil(per);
        // the last part first: a STRING's actual-length byte goes last, so
        // a part that fails leaves the old length (and the old text valid
        // up to it), and the PLC program never sees the new length with
        // old characters
        for (done, (k, part)) in bytes.chunks(per).enumerate().rev().enumerate() {
            let at = u32::try_from(k * per)
                .map_err(|_| DriverError::Point("value too long".into()))?;
            let len = u16::try_from(part.len())
                .map_err(|_| DriverError::Point("value too long".into()))?;
            let item = Item::bytes(a.area, a.db, start + at, len);
            if let Err(e) = c.write(&item, part).await {
                if done == 0 {
                    return Err(e);
                }
                let m = format!("{e} (after {done} of {parts} parts were written)");
                return Err(match e {
                    DriverError::Transport(_) => DriverError::Transport(m),
                    DriverError::Device(_) => DriverError::Device(m),
                    DriverError::Point(_) => DriverError::Point(m),
                });
            }
        }
        Ok(())
    }

    fn point_meta(p: &Point) -> NodeMeta {
        let mut m = NodeMeta::leaf(p.ty.type_code());
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

    fn ping_period(dev: &Dev) -> Option<Duration> {
        (dev.p.ping != Ping::None).then(|| Duration::from_secs_f64(dev.p.ping_s))
    }

    /// Opening takes three round trips (TCP, COTP, setup); a ping one.
    fn io_timeout(conn: &Conn) -> Duration {
        conn.timeout() * 3 + Duration::from_secs(1)
    }

    /// `timeout_ms` per request of the worst case (smallest PDU, every
    /// merged item read again) + 1 s.
    fn poll_timeout(conn: &Conn, plan: &Plan) -> Duration {
        let n = u32::try_from(plan.worst_requests).unwrap_or(u32::MAX);
        conn.timeout().saturating_mul(n.max(1)) + Duration::from_secs(1)
    }

    fn write_timeout(conn: &Conn, p: &Point) -> Duration {
        let n = u32::try_from(write_requests(p)).unwrap_or(u32::MAX);
        (conn.timeout().saturating_mul(n) + Duration::from_secs(1)).max(Self::io_timeout(conn))
    }

    /// A value written in parts may have gone through in part.
    fn read_back_on_error(_dev: &Dev) -> bool {
        true
    }

    fn republish(dev: &Dev) -> Option<Duration> {
        (dev.p.republish_s > 0.0).then(|| Duration::from_secs_f64(dev.p.republish_s))
    }

    /// `connection_info` (no I/O) at read; `read_szl` and `read_address`
    /// send a request and hold the connection while they wait, so they are
    /// commissioning actions at config.
    fn actions(level: Level, _kind: &str) -> Vec<(&'static str, ActionMeta)> {
        let at = |perm: Perm, display: &str| {
            ActionMeta::new()
                .level(perm)
                .display(display)
                .timeout_ms(READ_ACTION_MS)
                .result(ActionResult::Type(TypeCode::Map))
        };
        let read = |display: &str| at(Perm::Config, display);
        match level {
            Level::Connection => vec![("connection_info", at(Perm::Read, "Connection Info"))],
            Level::Device => vec![
                (
                    "read_szl",
                    read("Read SZL")
                        .param(
                            "id",
                            param("SZL ID", "0x0011: module identification", TypeCode::Number)
                                .required(true),
                        )
                        .param(
                            "index",
                            ParamMeta {
                                default: Some(Value::UInt(0)),
                                ..param("Index", "SZL index", TypeCode::Number)
                            },
                        ),
                ),
                (
                    "read_address",
                    read("Read Address")
                        .param(
                            "address",
                            param("Address", "DB1.DBW0, MW20, T5, …", TypeCode::String)
                                .required(true),
                        )
                        .param(
                            "dtype",
                            ParamMeta::of(TypeCode::String)
                                .enum_values(DTYPE_NAMES.iter().copied())
                                .display("Data Type"),
                        ),
                ),
            ],
        }
    }

    async fn invoke(
        c: &mut Client,
        _conn: &Conn,
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
            (Target::Connection, "connection_info") => Ok(connection_info(c)),
            (Target::Device { .. }, "read_szl") => read_szl(c, args).await,
            (Target::Device { dev, .. }, "read_address") => read_address(c, dev, args).await,
            _ => Err(LinkError::not_supported(format!("action {action}"))),
        }
    }

    const DIAGNOSTICS: bool = true;
    const DIAG_EXTRA: &'static [&'static str] = &[LATE_REPLIES];
    /// Folders below a device, as the other framework drivers.
    const FOLDERS: bool = true;

    fn take_outcomes(c: &mut Client) -> Vec<Outcome> {
        c.take_outcomes()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn point(address: &str) -> (PointId, Point) {
        let m = BTreeMap::from([("address".to_owned(), Value::from(address))]);
        (address.to_owned(), Point::from_value(&Value::Map(m)).unwrap())
    }

    /// The poll's bound counts the requests of a read again point by point
    /// at the smallest PDU, not one per point: a STRING[254] takes 4 there
    /// (78 data bytes per reply item, one item per reply).
    #[test]
    fn the_poll_bound_counts_long_strings_read_again() {
        let dev = Dev::from_value(&Value::Map(BTreeMap::new())).unwrap();
        let points = [
            point("DB1.DBB0:STRING[254]"),
            point("DB1.DBB256:STRING[254]"),
        ];
        let plan = Plan::new(&dev, &points);
        // the first pass: merged, 512 bytes in 7 requests, or (points read
        // alone) 4 + 4; then again alone: 4 + 4
        assert_eq!(plan.worst_requests, 8 + 8);
    }
}
