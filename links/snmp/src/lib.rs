//! SNMP poller on the driver framework (ADR 0004).
//!
//! Tree: `<conn>/<device>/<point>`. Connection kinds [`Conn`]: `Add SNMP
//! v2c` ([`V2cConn`]: community) and `Add SNMP v3` ([`V3Conn`]: USM user,
//! HMAC-SHA-1 or HMAC-192-SHA-256, AES-128 privacy, engine id discovery).
//! A connection is one agent address; a [`Device`] is one view of that
//! agent (a v3 context, or a v2c community of its own); a [`Point`] is one
//! OID, a scalar or a cell of a table column, with a value conversion
//! ([`Conv`]).
//!
//! The framework owns the tree, actions, edits, states, scheduling and the
//! quality ladder; this driver does the protocol (an SNMP codec of its own:
//! [`ber`], [`msg`], [`usm`], [`client`]):
//!
//! * scalars are read with GET, at most `max_varbinds` per request; a
//!   `tooBig` answer splits the request, an error status with an index
//!   fails that point and reads the others again;
//! * table cells are read with GETBULK per column, from just before the
//!   first wanted row, at most `max_pages` requests per column and poll;
//! * `noSuchObject`/`noSuchInstance`/`endOfMibView` fail that point only;
//!   `authorizationError` and USM reports (wrong digest, unknown user,
//!   unsupported security level, decryption error) fail the device with a
//!   clear message; no answer is a device miss; an ICMP port unreachable
//!   or an engine id that changed drops the connection (it reopens);
//! * `rate_per_s` is the difference of a counter between two polls per
//!   second (Counter32 wraps; a Counter64 that goes down, or a `sysUpTime`
//!   that goes down, starts again without a sample);
//! * SET for writable points (INTEGER, OCTET STRING, Gauge32), read back
//!   by the framework;
//! * device ping: GET `sysUpTime.0` (any answer, `noSuchObject` too, means
//!   alive); device action `walk {oid, max}` for commissioning.
//!
//! `open` asks the agent for `sysUpTime.0` (v3: after engine discovery):
//! UDP has no connection, so this is how an unreachable agent fails the
//! connection. A wrong v2c community gets no answer at all (agents drop
//! such requests, RFC 3584): it shows as an agent that does not answer.

#![forbid(unsafe_code)]

pub mod ber;
pub mod client;
pub mod convert;
pub mod msg;
#[cfg(feature = "sim")]
pub mod sim;
pub mod usm;

use ber::{Oid, SnmpValue};
use client::{Scope, Security, Session, V3};
use convert::{Linear, SetType};
use std::collections::{BTreeMap, HashMap};
use std::net::{IpAddr, SocketAddr};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::Duration;
use tokio::time::Instant;
use tracing::debug;
use wyrm_core::meta::{ActionResult, ParamMeta, Writable};
use wyrm_core::{ActionMeta, NodeMeta, Perm, Status, TypeCode, Value};
use wyrm_link_sdk::driver::params::{field, ParamSpec};
// Traits (type namespace) beside the derive macros of the same name.
use wyrm_link_sdk::driver::{
    Driver, DriverError, Framework, Level, Outcome, ParamEnum, Params, PointId, Target,
};
use wyrm_link_sdk::LinkError;
use wyrm_link_sdk::{ParamEnum, Params};
use zeroize::Zeroizing;

pub use convert::Conv;

/// The `snmp` link: the framework running [`SnmpDriver`].
pub type Snmp = Framework<SnmpDriver>;

#[derive(Debug, Clone, Copy, PartialEq, Eq, ParamEnum)]
pub enum AuthProtocol {
    /// usmHMACSHAAuthProtocol (HMAC-SHA-96).
    Sha1,
    /// usmHMAC192SHA256AuthProtocol (RFC 7860).
    Sha256,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, ParamEnum)]
pub enum PrivProtocol {
    /// usmAesCfb128Protocol (RFC 3826).
    Aes128,
    /// authNoPriv: values travel unencrypted.
    None,
}

/// The connection kinds.
#[derive(Clone, PartialEq, Params)]
pub enum Conn {
    #[param(name = "snmp_v2c", display = "SNMP v2c")]
    V2c(V2cConn),
    #[param(name = "snmp_v3", display = "SNMP v3")]
    V3(V3Conn),
}

impl std::fmt::Debug for Conn {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let (kind, host, port) = match self {
            Conn::V2c(c) => ("snmp_v2c", &c.host, c.port),
            Conn::V3(c) => ("snmp_v3", &c.host, c.port),
        };
        write!(f, "{kind} {host}:{port} (secrets hidden)")
    }
}

impl Conn {
    fn host(&self) -> &str {
        match self {
            Conn::V2c(c) => &c.host,
            Conn::V3(c) => &c.host,
        }
    }

    fn port(&self) -> u16 {
        match self {
            Conn::V2c(c) => c.port,
            Conn::V3(c) => c.port,
        }
    }

    fn timeout_ms(&self) -> u32 {
        match self {
            Conn::V2c(c) => c.timeout_ms,
            Conn::V3(c) => c.timeout_ms,
        }
    }

    fn retries(&self) -> u8 {
        match self {
            Conn::V2c(c) => c.retries,
            Conn::V3(c) => c.retries,
        }
    }

    /// Bound on one request with its retries.
    fn per_request(&self) -> Duration {
        Duration::from_millis(u64::from(self.timeout_ms()) * (1 + u64::from(self.retries())))
    }
}

/// An SNMPv2c agent. The community is a secret, sent in clear text: a
/// connection beyond loopback says so on its `status`.
#[derive(Clone, PartialEq, Params)]
pub struct V2cConn {
    #[param(display = "Host", placeholder = "192.0.2.10", dest)]
    pub host: String,
    #[param(default = 161, min = 1, max = 65535, display = "Port", dest)]
    pub port: u16,
    #[param(secret, display = "Community")]
    pub community: String,
    /// Bound on each request.
    #[param(default = 1000, min = 100, max = 10000, display = "Timeout (ms)")]
    pub timeout_ms: u32,
    /// Repeats of a request after a timeout.
    #[param(default = 1, min = 0, max = 5, display = "Retries")]
    pub retries: u8,
}

/// An SNMPv3 agent (USM). Hand-written `Params`: passphrases have at
/// least 8 characters, and AES needs a privacy passphrase.
#[derive(Clone, PartialEq)]
pub struct V3Conn {
    pub host: String,
    pub port: u16,
    pub user: String,
    pub auth_protocol: AuthProtocol,
    auth_passphrase: String,
    pub priv_protocol: PrivProtocol,
    priv_passphrase: String,
    pub timeout_ms: u32,
    pub retries: u8,
}

impl Params for V3Conn {
    fn schema() -> Vec<ParamSpec> {
        vec![
            ParamSpec::new("host", TypeCode::String)
                .display("Host")
                .placeholder("192.0.2.10")
                .dest(),
            ParamSpec::new("port", TypeCode::Number)
                .default(161u64)
                .bounds(1.0, 65535.0)
                .display("Port")
                .dest(),
            ParamSpec::new("user", TypeCode::String)
                .display("User")
                .desc("USM user name (1 to 32 characters)")
                .dest(),
            ParamSpec::new("auth_protocol", TypeCode::Enum)
                .one_of(AuthProtocol::NAMES)
                .default("sha256")
                .display("Auth Protocol")
                .dest(),
            ParamSpec::new("auth_passphrase", TypeCode::String)
                .secret()
                .desc("at least 8 characters")
                .display("Auth Passphrase"),
            ParamSpec::new("priv_protocol", TypeCode::Enum)
                .one_of(PrivProtocol::NAMES)
                .default("aes128")
                .display("Privacy Protocol")
                .dest(),
            ParamSpec::new("priv_passphrase", TypeCode::String)
                .secret()
                .default("")
                .desc("at least 8 characters; required with aes128")
                .display("Privacy Passphrase"),
            ParamSpec::new("timeout_ms", TypeCode::Number)
                .default(1000u64)
                .bounds(100.0, 10_000.0)
                .display("Timeout (ms)"),
            ParamSpec::new("retries", TypeCode::Number)
                .default(1u64)
                .bounds(0.0, 5.0)
                .display("Retries"),
        ]
    }

    fn from_map(m: &BTreeMap<String, Value>) -> wyrm_link_sdk::Result<Self> {
        let c = V3Conn {
            host: field::string(m, "host")?,
            port: field::int(m, "port")?,
            user: field::string(m, "user")?,
            auth_protocol: field::enumv(m, "auth_protocol")?,
            auth_passphrase: field::string(m, "auth_passphrase")?,
            priv_protocol: field::enumv(m, "priv_protocol")?,
            priv_passphrase: field::string(m, "priv_passphrase")?,
            timeout_ms: field::int(m, "timeout_ms")?,
            retries: field::int(m, "retries")?,
        };
        if c.user.is_empty() || c.user.len() > 32 {
            return Err(LinkError::invalid_parameter("user: 1 to 32 characters"));
        }
        if c.auth_passphrase.chars().count() < usm::MIN_PASSPHRASE {
            return Err(LinkError::invalid_parameter(
                "auth_passphrase: at least 8 characters",
            ));
        }
        if c.priv_protocol == PrivProtocol::Aes128
            && c.priv_passphrase.chars().count() < usm::MIN_PASSPHRASE
        {
            return Err(LinkError::invalid_parameter(
                "priv_passphrase: at least 8 characters with priv_protocol aes128",
            ));
        }
        Ok(c)
    }

    fn to_map(&self) -> BTreeMap<String, Value> {
        BTreeMap::from([
            ("host".into(), Value::Str(self.host.clone())),
            ("port".into(), Value::UInt(self.port.into())),
            ("user".into(), Value::Str(self.user.clone())),
            (
                "auth_protocol".into(),
                Value::Str(self.auth_protocol.name().into()),
            ),
            (
                "auth_passphrase".into(),
                Value::Str(self.auth_passphrase.clone()),
            ),
            (
                "priv_protocol".into(),
                Value::Str(self.priv_protocol.name().into()),
            ),
            (
                "priv_passphrase".into(),
                Value::Str(self.priv_passphrase.clone()),
            ),
            ("timeout_ms".into(), Value::UInt(self.timeout_ms.into())),
            ("retries".into(), Value::UInt(self.retries.into())),
        ])
    }
}

/// One view of the agent: a v3 context, or (v2c) a community of its own.
#[derive(Clone, PartialEq, Params)]
pub struct Device {
    /// SNMPv3 context name (`contextName`); empty = the default context.
    #[param(default = "", display = "Context", dest)]
    pub context: String,
    /// v2c: this device's community instead of the connection's (some
    /// agents select a VLAN or an instance by community); empty = the
    /// connection's. Ignored on v3.
    #[param(secret, default = "", display = "Community Override")]
    pub community: String,
    #[param(default = 20, min = 1, max = 100, display = "Max Varbinds per Request")]
    pub max_varbinds: u16,
    #[param(
        default = 25,
        min = 1,
        max = 100,
        display = "Max Repetitions (GETBULK)"
    )]
    pub max_repetitions: u16,
    /// GETBULK requests per table column and poll.
    #[param(
        default = 20,
        min = 1,
        max = 200,
        display = "Max GETBULK Requests per Column"
    )]
    pub max_pages: u16,
    #[param(default = true, display = "Ping")]
    pub ping: bool,
    #[param(default = 10.0, min = 0.1, max = 3600.0, display = "Ping Rate (s)")]
    pub ping_s: f64,
    /// Publish an unchanged value again after this long (0 = on a change only).
    #[param(
        default = 0.0,
        min = 0.0,
        max = 3600.0,
        display = "Republish Unchanged Values (s)"
    )]
    pub republish_s: f64,
}

impl std::fmt::Debug for Device {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "device context {:?} (secrets hidden)", self.context)
    }
}

impl Device {
    fn scope(&self) -> Scope<'_> {
        Scope {
            community: (!self.community.is_empty()).then_some(self.community.as_bytes()),
            context: self.context.as_bytes(),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, ParamEnum)]
pub enum Kind {
    /// GET of `oid`.
    Scalar,
    /// The cell `oid.index` of the column `oid`, read by GETBULK.
    TableColumn,
}

/// One OID. Hand-written `Params`: the OID is normalized and the rules
/// cross fields (index, scaling, writes).
#[derive(Debug, Clone, PartialEq)]
pub struct Point {
    /// Scalar OID or column OID (normalized dotted form).
    pub oid: Oid,
    pub kind: Kind,
    /// Row index of a table cell (`3`, `1.4.192.0.2.1`).
    pub index: Vec<u32>,
    pub conv: Conv,
    pub scale: f64,
    pub offset: f64,
    pub unit: String,
    pub poll_s: f64,
    pub writable: bool,
    pub set_type: SetType,
}

impl Point {
    /// The OID read.
    pub fn full_oid(&self) -> Oid {
        self.oid.join(&self.index)
    }

    fn linear(&self) -> Linear {
        Linear {
            scale: self.scale,
            offset: self.offset,
        }
    }
}

fn parse_index(s: &str) -> Result<Vec<u32>, String> {
    let t = s.trim().trim_start_matches('.');
    if t.is_empty() {
        return Ok(Vec::new());
    }
    t.split('.')
        .map(|a| {
            if a.is_empty() || !a.bytes().all(|b| b.is_ascii_digit()) {
                return Err(format!("index: {s:?} is not dotted numbers"));
            }
            a.parse::<u32>()
                .map_err(|_| format!("index: arc {a} is above 4294967295"))
        })
        .collect()
}

fn dotted(arcs: &[u32]) -> String {
    arcs.iter()
        .map(u32::to_string)
        .collect::<Vec<_>>()
        .join(".")
}

impl Params for Point {
    fn schema() -> Vec<ParamSpec> {
        vec![
            ParamSpec::new("oid", TypeCode::String)
                .display("OID")
                .placeholder("1.3.6.1.2.1.1.3.0")
                .desc(
                    "numeric: 1.3.6.1…, .1.3.6.1… or iso.3.6.1…; the column OID for table_column",
                ),
            ParamSpec::new("kind", TypeCode::Enum)
                .one_of(Kind::NAMES)
                .default("scalar")
                .display("Kind"),
            ParamSpec::new("index", TypeCode::String)
                .default("")
                .placeholder("1")
                .desc("row index of a table_column point (dotted numbers)")
                .display("Index"),
            ParamSpec::new("conv", TypeCode::Enum)
                .one_of(Conv::NAMES)
                .default("auto")
                .display("Conversion"),
            ParamSpec::new("scale", TypeCode::Number)
                .default(1.0)
                .display("Scale"),
            ParamSpec::new("offset", TypeCode::Number)
                .default(0.0)
                .display("Offset"),
            ParamSpec::new("unit", TypeCode::String)
                .default("")
                .display("Unit"),
            ParamSpec::new("poll_s", TypeCode::Number)
                .default(10.0)
                .bounds(0.01, 86_400.0)
                .display("Poll Rate (s)"),
            ParamSpec::new("writable", TypeCode::Bool)
                .default(false)
                .display("Writable"),
            ParamSpec::new("set_type", TypeCode::Enum)
                .one_of(SetType::NAMES)
                .default("integer")
                .desc("SMI type of a SET: integer, octet_string or gauge32")
                .display("Set Type"),
        ]
    }

    fn from_map(m: &BTreeMap<String, Value>) -> wyrm_link_sdk::Result<Self> {
        fn bad(m: impl Into<String>) -> LinkError {
            LinkError::invalid_parameter(m)
        }
        let oid_text = field::string(m, "oid")?;
        let oid = Oid::parse(&oid_text).map_err(|e| bad(format!("oid: {e}")))?;
        let index = parse_index(&field::string(m, "index")?).map_err(bad)?;
        let p = Point {
            oid,
            kind: field::enumv(m, "kind")?,
            index,
            conv: field::enumv(m, "conv")?,
            scale: field::f64(m, "scale")?,
            offset: field::f64(m, "offset")?,
            unit: field::string(m, "unit")?,
            poll_s: field::f64(m, "poll_s")?,
            writable: field::bool(m, "writable")?,
            set_type: field::enumv(m, "set_type")?,
        };
        match p.kind {
            Kind::TableColumn if p.index.is_empty() => {
                return Err(bad("index: a table_column point needs the row index"));
            }
            Kind::Scalar if !p.index.is_empty() => {
                return Err(bad(
                    "index: only for table_column (a scalar's OID ends in .0)",
                ));
            }
            _ => {}
        }
        if p.full_oid().0.len() > ber::MAX_ARCS {
            return Err(bad("index: the OID gets longer than 128 arcs"));
        }
        if p.scale == 0.0 {
            return Err(bad("scale: must not be 0"));
        }
        let scaled = p.scale != 1.0 || p.offset != 0.0;
        if scaled && !(p.conv.is_numeric() || p.conv == Conv::Auto) {
            return Err(bad(format!(
                "scale: conv {} is not a number",
                p.conv.name()
            )));
        }
        if p.writable && !p.conv.writable_as(p.set_type) {
            return Err(bad(format!(
                "writable: conv {} cannot be written as {} (integer and gauge32: auto or \
                 gauge; octet_string: auto or string)",
                p.conv.name(),
                p.set_type.name()
            )));
        }
        if p.writable && p.set_type == SetType::OctetString && scaled {
            return Err(bad("scale: an octet_string is not scaled"));
        }
        Ok(p)
    }

    fn to_map(&self) -> BTreeMap<String, Value> {
        BTreeMap::from([
            ("oid".into(), Value::Str(self.oid.to_string())),
            ("kind".into(), Value::Str(self.kind.name().into())),
            ("index".into(), Value::Str(dotted(&self.index))),
            ("conv".into(), Value::Str(self.conv.name().into())),
            ("scale".into(), Value::Float(self.scale)),
            ("offset".into(), Value::Float(self.offset)),
            ("unit".into(), Value::Str(self.unit.clone())),
            ("poll_s".into(), Value::Float(self.poll_s)),
            ("writable".into(), Value::Bool(self.writable)),
            ("set_type".into(), Value::Str(self.set_type.name().into())),
        ])
    }
}

/// One point of a plan.
#[derive(Debug, Clone)]
struct Member {
    id: PointId,
    oid: Oid,
    point: Point,
}

/// Cells of one table column.
#[derive(Debug, Clone)]
struct Column {
    column: Oid,
    /// Sorted by OID.
    members: Vec<Member>,
}

/// The reads of one `(device, poll period)` group.
pub struct Plan {
    /// Keys the `rate_per_s` state in the transport.
    id: u64,
    /// GET requests; with rate points, the first carries `sysUpTime.0`.
    batches: Vec<Vec<Member>>,
    columns: Vec<Column>,
    /// The plan has `rate_per_s` points.
    rates: bool,
    max_repetitions: u16,
    max_pages: u16,
}

impl Plan {
    /// Requests of one poll at most (a split or an error retry aside).
    fn requests(&self) -> u64 {
        let pages = u64::from(self.max_pages);
        u64::try_from(self.batches.len()).unwrap_or(u64::MAX)
            + u64::try_from(self.columns.len())
                .unwrap_or(u64::MAX)
                .saturating_mul(pages)
    }
}

static PLAN_IDS: AtomicU64 = AtomicU64::new(1);

/// Id of the varbind `sysUpTime.0` that a plan with rates reads beside its
/// points (never a point id: those are node names).
const UPTIME_ID: &str = "\0sysUpTime";

/// The last sample of a `rate_per_s` point.
#[derive(Debug, Clone, Copy)]
struct Sample {
    raw: u64,
    bits: u32,
    at: Instant,
}

/// Rate state of one plan.
#[derive(Default)]
struct PlanRates {
    samples: HashMap<PointId, Sample>,
    uptime: Option<u32>,
}

/// Plans whose rate state is kept; more (many edits) clears it.
const MAX_RATE_PLANS: usize = 4096;

/// An open connection.
pub struct Transport {
    s: Session,
    rates: HashMap<u64, PlanRates>,
    note: Option<String>,
}

fn is_loopback(host: &str) -> bool {
    host.eq_ignore_ascii_case("localhost") || host.parse::<IpAddr>().is_ok_and(|a| a.is_loopback())
}

/// Why an answer's error status fails the whole request: `authorizationError`
/// is the device's (its access control refuses this view).
fn authorization(status: i32) -> Option<DriverError> {
    (status == msg::AUTHORIZATION_ERROR).then(|| {
        DriverError::Device(
            "authorizationError: the agent's access control (VACM) refuses this request; \
             check the community, user or context"
                .into(),
        )
    })
}

/// The result of one member's varbind.
type Read = Result<SnmpValue, String>;

/// GET of `members` in one request; `tooBig` splits it, an error status
/// with an index fails that member and reads the rest again. `Err`: no
/// answer, a broken transport, or `authorizationError`.
async fn get_batch(
    s: &mut Session,
    scope: Scope<'_>,
    oids: &[Oid],
) -> Result<Vec<Read>, DriverError> {
    let mut out: Vec<Option<Read>> = vec![None; oids.len()];
    let mut work: Vec<Vec<usize>> = vec![(0..oids.len()).collect()];
    while let Some(set) = work.pop() {
        if set.is_empty() {
            continue;
        }
        let ask: Vec<Oid> = set.iter().map(|&i| oids[i].clone()).collect();
        let pdu = s.get(scope, &ask).await?;
        if let Some(e) = authorization(pdu.error_status) {
            return Err(e);
        }
        match pdu.error_status {
            0 if pdu.varbinds.len() == set.len() => {
                for (&i, (oid, v)) in set.iter().zip(pdu.varbinds) {
                    out[i] = Some(if oid == oids[i] {
                        Ok(v)
                    } else {
                        Err(format!("the agent answered for another OID ({oid})"))
                    });
                }
            }
            0 => {
                for &i in &set {
                    out[i] = Some(Err("malformed answer: varbinds missing".into()));
                }
            }
            msg::TOO_BIG if set.len() > 1 => {
                let (a, b) = set.split_at(set.len() / 2);
                work.push(b.to_vec());
                work.push(a.to_vec());
            }
            status => {
                let at = usize::try_from(pdu.error_index).unwrap_or(0);
                let name = msg::error_name(status);
                if (1..=set.len()).contains(&at) && set.len() > 1 {
                    out[set[at - 1]] = Some(Err(name));
                    let rest: Vec<usize> = set
                        .iter()
                        .enumerate()
                        .filter(|(k, _)| *k != at - 1)
                        .map(|(_, &i)| i)
                        .collect();
                    work.push(rest);
                } else {
                    for &i in &set {
                        out[i] = Some(Err(name.clone()));
                    }
                }
            }
        }
    }
    Ok(out
        .into_iter()
        .map(|r| r.unwrap_or_else(|| Err("not read".into())))
        .collect())
}

/// An OID just below `oid` in SNMP order: a GETNEXT/GETBULK from it
/// returns `oid` first when the agent has it.
fn before(oid: &Oid) -> Oid {
    let mut a = oid.0.clone();
    match a.last_mut() {
        Some(last) if *last > 0 => *last -= 1,
        _ => {
            a.pop();
        }
    }
    Oid(a)
}

/// The wanted cells of one column by GETBULK from just below the first
/// one, jumping over gaps; at most `pages` requests.
async fn get_column(
    s: &mut Session,
    scope: Scope<'_>,
    col: &Column,
    max_repetitions: u16,
    pages: u16,
) -> Result<Vec<Read>, DriverError> {
    let mut want: BTreeMap<Oid, usize> = col
        .members
        .iter()
        .enumerate()
        .map(|(i, m)| (m.oid.clone(), i))
        .collect();
    let mut out: Vec<Option<Read>> = vec![None; col.members.len()];
    let mut cursor: Option<Oid> = None;
    let mut sent = 0u16;
    let mut end = false;
    while !want.is_empty() && sent < pages && !end {
        let Some((first, _)) = want.first_key_value() else {
            break;
        };
        // Jump to just below the next wanted cell when that is ahead.
        let next = before(first);
        let from = match &cursor {
            Some(c) if *c >= next => c.clone(),
            _ => next,
        };
        let pdu = s
            .get_bulk(
                scope,
                i32::from(max_repetitions),
                std::slice::from_ref(&from),
            )
            .await?;
        sent += 1;
        if let Some(e) = authorization(pdu.error_status) {
            return Err(e);
        }
        if pdu.error_status != 0 {
            let name = msg::error_name(pdu.error_status);
            for (_, i) in std::mem::take(&mut want) {
                out[i] = Some(Err(name.clone()));
            }
            break;
        }
        if pdu.varbinds.is_empty() {
            break;
        }
        let mut prev = from;
        for (oid, v) in pdu.varbinds {
            // Out of the column, or not ascending (a broken agent): stop.
            if v == SnmpValue::EndOfMibView || !oid.starts_with(&col.column) || oid <= prev {
                end = true;
                break;
            }
            prev = oid.clone();
            if let Some(i) = want.remove(&oid) {
                out[i] = Some(Ok(v));
            }
            // Cells below `oid` that were not returned do not exist.
            let gone: Vec<Oid> = want.range(..oid.clone()).map(|(o, _)| o.clone()).collect();
            for o in gone {
                if let Some(i) = want.remove(&o) {
                    out[i] = Some(Ok(SnmpValue::NoSuchInstance));
                }
            }
            cursor = Some(oid);
        }
    }
    let left = if end || sent < pages {
        "noSuchInstance: no such row in the column".to_owned()
    } else {
        format!("not reached in {pages} GETBULK requests (max_pages)")
    };
    for (_, i) in want {
        out[i] = Some(Err(left.clone()));
    }
    Ok(out
        .into_iter()
        .map(|r| r.unwrap_or_else(|| Err("not read".into())))
        .collect())
}

/// One member's value from its varbind (`rate_per_s`: from the last
/// sample; `None` = no value yet).
fn value_of(
    rates: &mut PlanRates,
    m: &Member,
    r: Read,
    now: Instant,
) -> Option<Result<Value, DriverError>> {
    let v = match r {
        Ok(v) => v,
        Err(e) => return Some(Err(DriverError::Point(e))),
    };
    if m.point.conv != Conv::RatePerS {
        return Some(
            convert::convert(m.point.conv, &v, m.point.linear()).map_err(DriverError::Point),
        );
    }
    if let Some(e) = convert::exception(&v) {
        rates.samples.remove(&m.id);
        return Some(Err(DriverError::Point(e.into())));
    }
    let (raw, bits) = match convert::counter(&v) {
        Ok(x) => x,
        Err(e) => return Some(Err(DriverError::Point(e))),
    };
    let new = Sample { raw, bits, at: now };
    let old = rates.samples.insert(m.id.clone(), new)?;
    if old.bits != bits {
        return None;
    }
    let secs = now.saturating_duration_since(old.at).as_secs_f64();
    convert::rate(old.raw, raw, bits, secs, m.point.linear()).map(Ok)
}

/// Device action `walk {oid, max = 500}`: GETBULK from `oid` while the
/// answers stay below it, at most `max` entries → `[{oid, type, value}]`.
async fn walk(
    s: &mut Session,
    dev: &Device,
    args: &BTreeMap<String, Value>,
) -> Result<Value, LinkError> {
    let root = match args.get("oid") {
        Some(Value::Str(t)) => {
            Oid::parse(t).map_err(|e| LinkError::invalid_parameter(format!("oid: {e}")))?
        }
        _ => return Err(LinkError::invalid_parameter("oid: required")),
    };
    let max = match args.get("max") {
        None => WALK_DEFAULT,
        Some(v) => {
            let n = v
                .as_f64()
                .filter(|n| n.fract() == 0.0)
                .ok_or_else(|| LinkError::invalid_parameter("max: a whole number"))?;
            if !(1.0..=WALK_MAX as f64).contains(&n) {
                return Err(LinkError::invalid_parameter(format!(
                    "max: {n} is not in 1…{WALK_MAX}"
                )));
            }
            n as usize
        }
    };
    let started = Instant::now();
    let budget = Duration::from_millis(WALK_BUDGET_MS.into());
    let mut out = Vec::new();
    let mut cursor = root.clone();
    'pages: while out.len() < max {
        if started.elapsed() + s.timeout * (1 + u32::from(s.retries)) > budget {
            break;
        }
        let reps =
            i32::try_from((max - out.len()).min(usize::from(dev.max_repetitions))).unwrap_or(1);
        let pdu = s
            .get_bulk(dev.scope(), reps, std::slice::from_ref(&cursor))
            .await
            .map_err(action_err)?;
        if pdu.error_status != 0 {
            return Err(LinkError::new(
                Status::NotAvailable,
                msg::error_name(pdu.error_status),
            ));
        }
        if pdu.varbinds.is_empty() {
            break;
        }
        for (oid, v) in pdu.varbinds {
            if v == SnmpValue::EndOfMibView || !oid.starts_with(&root) || oid <= cursor {
                break 'pages;
            }
            let value = match &v {
                SnmpValue::NoSuchObject | SnmpValue::NoSuchInstance => Value::Null,
                _ => convert::convert(Conv::Auto, &v, NEUTRAL).unwrap_or(Value::Null),
            };
            out.push(Value::Map(BTreeMap::from([
                ("oid".into(), Value::Str(oid.to_string())),
                ("type".into(), Value::Str(v.type_name().into())),
                ("value".into(), value),
            ])));
            cursor = oid;
            if out.len() >= max {
                break 'pages;
            }
        }
    }
    Ok(Value::Array(out))
}

const NEUTRAL: Linear = Linear {
    scale: 1.0,
    offset: 0.0,
};

const WALK_DEFAULT: usize = 500;
const WALK_MAX: usize = 10_000;
/// Bound on `walk` (the action's `timeout_ms`); the walk itself stops
/// before it with what it has.
const WALK_ACTION_MS: u32 = 60_000;
const WALK_BUDGET_MS: u32 = WALK_ACTION_MS - 5_000;

fn action_err(e: DriverError) -> LinkError {
    match e {
        DriverError::Transport(m) => LinkError::new(Status::Disconnected, m),
        DriverError::Device(m) => LinkError::timeout(m),
        DriverError::Point(m) => LinkError::new(Status::NotAvailable, m),
    }
}

/// Key localization hashes 1 MB per passphrase: time allowed for it in
/// `open` (slow boards, debug builds).
const KEY_MS: u64 = 3000;

pub struct SnmpDriver;

impl Driver for SnmpDriver {
    const NAME: &'static str = "snmp";
    const VERSION: &'static str = env!("CARGO_PKG_VERSION");
    type Conn = Conn;
    type Dev = Device;
    type Point = Point;
    type Transport = Transport;
    type Plan = Plan;

    async fn open(conn: &Conn) -> Result<Transport, DriverError> {
        let timeout = Duration::from_millis(conn.timeout_ms().into());
        let target = format!("{}:{}", conn.host(), conn.port());
        let addr: SocketAddr = tokio::time::timeout(timeout, tokio::net::lookup_host(&target))
            .await
            .map_err(|_| DriverError::Transport(format!("resolve {target}: timeout")))?
            .map_err(|e| DriverError::Transport(format!("resolve {target}: {e}")))?
            .next()
            .ok_or_else(|| DriverError::Transport(format!("resolve {target}: no address")))?;
        let loopback = is_loopback(conn.host());
        let (sec, note) = match conn {
            Conn::V2c(c) => {
                if c.community.is_empty() {
                    return Err(DriverError::Transport("community: not set".into()));
                }
                (
                    Security::V2c {
                        community: Zeroizing::new(c.community.as_bytes().to_vec()),
                    },
                    (!loopback).then(|| {
                        "SNMPv2c sends the community and the values in clear text: use \
                         snmp_v3 with priv_protocol aes128 beyond a trusted network"
                            .to_owned()
                    }),
                )
            }
            Conn::V3(c) => (
                Security::V3(V3 {
                    user: c.user.as_bytes().to_vec(),
                    auth: match c.auth_protocol {
                        AuthProtocol::Sha1 => usm::Auth::Sha1,
                        AuthProtocol::Sha256 => usm::Auth::Sha256,
                    },
                    auth_pass: Zeroizing::new(c.auth_passphrase.as_bytes().to_vec()),
                    priv_pass: (c.priv_protocol == PrivProtocol::Aes128)
                        .then(|| Zeroizing::new(c.priv_passphrase.as_bytes().to_vec())),
                }),
                (!loopback && c.priv_protocol == PrivProtocol::None).then(|| {
                    "priv_protocol none: values travel unencrypted (authNoPriv)".to_owned()
                }),
            ),
        };
        let s = Session::open(addr, timeout, conn.retries(), sec).await?;
        debug!(v3 = s.is_v3(), private = s.is_private(), "agent answered");
        Ok(Transport {
            s,
            rates: HashMap::new(),
            note,
        })
    }

    /// GET `sysUpTime.0`: any answer means the agent is alive, unless its
    /// access control refuses the device's view.
    async fn ping(t: &mut Transport, dev: &Device) -> Result<(), DriverError> {
        let pdu =
            t.s.get(dev.scope(), &[Oid(client::SYS_UPTIME.to_vec())])
                .await?;
        match authorization(pdu.error_status) {
            Some(e) => Err(e),
            None => Ok(()),
        }
    }

    fn plan(dev: &Device, points: &[(PointId, Point)]) -> Plan {
        let mut scalars: Vec<Member> = Vec::new();
        let mut columns: BTreeMap<Oid, Vec<Member>> = BTreeMap::new();
        let mut rates = false;
        for (id, p) in points {
            rates |= p.conv == Conv::RatePerS;
            let m = Member {
                id: id.clone(),
                oid: p.full_oid(),
                point: p.clone(),
            };
            match p.kind {
                Kind::Scalar => scalars.push(m),
                Kind::TableColumn => columns.entry(p.oid.clone()).or_default().push(m),
            }
        }
        if rates {
            // Read with the points: a restarted agent (uptime went down)
            // starts every rate again.
            let up = Oid(client::SYS_UPTIME.to_vec());
            scalars.insert(
                0,
                Member {
                    id: UPTIME_ID.into(),
                    oid: up.clone(),
                    point: Point {
                        oid: up,
                        kind: Kind::Scalar,
                        index: Vec::new(),
                        conv: Conv::Auto,
                        scale: 1.0,
                        offset: 0.0,
                        unit: String::new(),
                        poll_s: 1.0,
                        writable: false,
                        set_type: SetType::Integer,
                    },
                },
            );
        }
        let per = usize::from(dev.max_varbinds.max(1));
        let batches = scalars.chunks(per).map(<[Member]>::to_vec).collect();
        let columns = columns
            .into_iter()
            .map(|(column, mut members)| {
                members.sort_by(|a, b| a.oid.cmp(&b.oid));
                Column { column, members }
            })
            .collect();
        Plan {
            id: PLAN_IDS.fetch_add(1, Ordering::Relaxed),
            batches,
            columns,
            rates,
            max_repetitions: dev.max_repetitions,
            max_pages: dev.max_pages,
        }
    }

    async fn poll(
        t: &mut Transport,
        dev: &Device,
        plan: &Plan,
    ) -> Vec<(PointId, Result<Value, DriverError>)> {
        let scope = dev.scope();
        let mut reads: Vec<(&Member, Read)> = Vec::new();
        let mut failed: Option<DriverError> = None;
        for batch in &plan.batches {
            let oids: Vec<Oid> = batch.iter().map(|m| m.oid.clone()).collect();
            match get_batch(&mut t.s, scope, &oids).await {
                Ok(r) => reads.extend(batch.iter().zip(r)),
                Err(e) => {
                    failed = Some(e);
                    break;
                }
            }
        }
        if failed.is_none() {
            for col in &plan.columns {
                match get_column(&mut t.s, scope, col, plan.max_repetitions, plan.max_pages).await {
                    Ok(r) => reads.extend(col.members.iter().zip(r)),
                    Err(e) => {
                        failed = Some(e);
                        break;
                    }
                }
            }
        }
        let now = Instant::now();
        if t.rates.len() > MAX_RATE_PLANS {
            t.rates.clear();
        }
        let rates = t.rates.entry(plan.id).or_default();
        let mut out = Vec::new();
        if plan.rates {
            let up = reads.iter().find(|(m, _)| m.id == UPTIME_ID);
            if let Some((_, Ok(SnmpValue::TimeTicks(ticks)))) = up {
                if rates.uptime.is_some_and(|old| *ticks < old) {
                    debug!("agent restarted (sysUpTime went down): rates start again");
                    rates.samples.clear();
                }
                rates.uptime = Some(*ticks);
            }
        }
        let mut seen = std::collections::HashSet::new();
        for (m, r) in reads {
            if m.id == UPTIME_ID {
                continue;
            }
            seen.insert(m.id.as_str());
            if let Some(v) = value_of(rates, m, r, now) {
                out.push((m.id.clone(), v));
            }
        }
        if let Some(e) = failed {
            // No answer or a broken transport: the rest fails with it.
            let all = plan
                .batches
                .iter()
                .flatten()
                .chain(plan.columns.iter().flat_map(|c| c.members.iter()));
            for m in all {
                if m.id != UPTIME_ID && !seen.contains(m.id.as_str()) {
                    out.push((m.id.clone(), Err(e.clone())));
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
        if !p.writable {
            return Err(DriverError::Point("point is not writable".into()));
        }
        let value = convert::encode_set(p.set_type, v, p.linear()).map_err(DriverError::Point)?;
        let pdu = t.s.set(dev.scope(), vec![(p.full_oid(), value)]).await?;
        match pdu.error_status {
            0 => Ok(()),
            status => Err(DriverError::Point(format!(
                "the agent refused the SET: {}",
                msg::error_name(status)
            ))),
        }
    }

    fn point_meta(p: &Point) -> NodeMeta {
        let ty = if p.writable {
            match p.set_type {
                SetType::OctetString => TypeCode::String,
                SetType::Integer | SetType::Gauge32 => TypeCode::Number,
            }
        } else {
            p.conv.type_code()
        };
        let mut m = NodeMeta::leaf(ty);
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
        dev.ping.then(|| Duration::from_secs_f64(dev.ping_s))
    }

    /// Bound on a ping and on `open` (v3: discovery, the probe and a time
    /// window resync, and the key localization).
    fn io_timeout(conn: &Conn) -> Duration {
        let per = conn.per_request();
        match conn {
            Conn::V2c(_) => per + Duration::from_secs(1),
            Conn::V3(_) => per * 3 + Duration::from_millis(KEY_MS + 1000),
        }
    }

    /// `timeout_ms × (1 + retries) × requests + 1 s`, a request counted
    /// twice for a split or an error retry.
    fn poll_timeout(conn: &Conn, plan: &Plan) -> Duration {
        let per = u64::try_from(conn.per_request().as_millis()).unwrap_or(u64::MAX);
        let n = plan.requests().saturating_mul(2).max(1);
        Duration::from_millis(per.saturating_mul(n).saturating_add(1000))
    }

    /// One SET (twice with a v3 time window resync).
    fn write_timeout(conn: &Conn, _p: &Point) -> Duration {
        conn.per_request() * 2 + Duration::from_secs(1)
    }

    fn republish(dev: &Device) -> Option<Duration> {
        (dev.republish_s > 0.0).then(|| Duration::from_secs_f64(dev.republish_s))
    }

    /// Device action `walk` at level config: it reads any subtree with the
    /// link's credentials, beyond the configured points, and costs the
    /// agent up to hundreds of requests (commissioning is a config task).
    fn actions(level: Level, _kind: &str) -> Vec<(&'static str, ActionMeta)> {
        if level != Level::Device {
            return Vec::new();
        }
        let max = ParamMeta {
            default: Some(Value::UInt(WALK_DEFAULT as u64)),
            ..ParamMeta::of(TypeCode::Number)
                .display("Max Entries")
                .description("1…10000")
        };
        vec![(
            "walk",
            ActionMeta::new()
                .level(Perm::Config)
                .display("Walk")
                .timeout_ms(WALK_ACTION_MS)
                .result(ActionResult::Type(TypeCode::Array))
                .param(
                    "oid",
                    ParamMeta::of(TypeCode::String)
                        .display("OID")
                        .description("subtree to walk, e.g. 1.3.6.1.2.1.2.2.1")
                        .required(true),
                )
                .param("max", max),
        )]
    }

    async fn invoke(
        t: &mut Transport,
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
            (Target::Device { dev, .. }, "walk") => walk(&mut t.s, dev, args).await,
            _ => Err(LinkError::not_supported(format!("action {action}"))),
        }
    }

    const DIAGNOSTICS: bool = true;
    const DIAG_EXTRA: &'static [&'static str] = &[client::LATE];

    fn take_outcomes(t: &mut Transport) -> Vec<Outcome> {
        t.s.take_outcomes()
    }

    fn status_note(t: &Transport) -> Option<String> {
        t.note.clone()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn map(kv: &[(&str, Value)]) -> Value {
        Value::Map(
            kv.iter()
                .map(|(k, v)| ((*k).to_owned(), v.clone()))
                .collect(),
        )
    }

    fn point(kv: &[(&str, Value)]) -> wyrm_link_sdk::Result<Point> {
        Point::from_value(&map(kv))
    }

    #[test]
    fn points_normalize_and_roundtrip() {
        let p = point(&[("oid", "iso.3.6.1.2.1.1.3.0".into())]).unwrap();
        assert_eq!(p.oid.to_string(), "1.3.6.1.2.1.1.3.0");
        assert_eq!(Point::from_value(&p.to_value()).unwrap(), p);
        let c = point(&[
            ("oid", ".1.3.6.1.2.1.2.2.1.10".into()),
            ("kind", "table_column".into()),
            ("index", "3".into()),
            ("conv", "rate_per_s".into()),
            ("scale", Value::Float(8.0)),
        ])
        .unwrap();
        assert_eq!(c.full_oid().to_string(), "1.3.6.1.2.1.2.2.1.10.3");
        assert_eq!(Point::from_value(&c.to_value()).unwrap(), c);
    }

    #[test]
    fn point_rules() {
        let oid = ("oid", Value::from("1.3.6.1.2.1.1.4.0"));
        for (bad, what) in [
            (vec![("oid", Value::from("1.3.x"))], "oid"),
            (vec![oid.clone(), ("kind", "table_column".into())], "index"),
            (vec![oid.clone(), ("index", "1".into())], "index"),
            (
                vec![
                    oid.clone(),
                    ("kind", "table_column".into()),
                    ("index", "1..2".into()),
                ],
                "index",
            ),
            (vec![oid.clone(), ("scale", Value::Float(0.0))], "scale"),
            (
                vec![
                    oid.clone(),
                    ("conv", "mac".into()),
                    ("scale", Value::Float(2.0)),
                ],
                "scale",
            ),
            (
                vec![
                    oid.clone(),
                    ("conv", "rate_per_s".into()),
                    ("writable", Value::Bool(true)),
                ],
                "writable",
            ),
            (
                vec![
                    oid.clone(),
                    ("conv", "string".into()),
                    ("writable", Value::Bool(true)),
                ],
                "writable",
            ),
            (vec![oid.clone(), ("poll_s", Value::Float(0.0))], "poll_s"),
        ] {
            let e = point(&bad).unwrap_err();
            assert!(e.message.starts_with(what), "{bad:?}: {}", e.message);
        }
        let w = point(&[
            oid.clone(),
            ("conv", "string".into()),
            ("writable", Value::Bool(true)),
            ("set_type", "octet_string".into()),
        ])
        .unwrap();
        assert_eq!(SnmpDriver::point_meta(&w).ty, Some(TypeCode::String));
        let auto = point(std::slice::from_ref(&oid)).unwrap();
        assert_eq!(SnmpDriver::point_meta(&auto).ty, Some(TypeCode::Dynamic));
    }

    fn v3(kv: &[(&str, Value)]) -> wyrm_link_sdk::Result<Conn> {
        let mut m = vec![
            ("host", Value::from("127.0.0.1")),
            ("user", "ops".into()),
            ("auth_passphrase", "auth-pass-1".into()),
            ("priv_passphrase", "priv-pass-1".into()),
        ];
        for (k, v) in kv {
            m.retain(|(n, _)| n != k);
            m.push((k, v.clone()));
        }
        Conn::from_kind_value("snmp_v3", &map(&m))
    }

    #[test]
    fn v3_params() {
        let c = v3(&[]).unwrap();
        let Conn::V3(v) = &c else { panic!("v3") };
        assert_eq!(v.auth_protocol, AuthProtocol::Sha256);
        assert_eq!(v.priv_protocol, PrivProtocol::Aes128);
        let public = format!("{:?}", c.public_map());
        assert!(!public.contains("auth-pass-1") && !public.contains("priv-pass-1"));
        assert!(!format!("{c:?}").contains("pass"));
        let e = v3(&[("auth_passphrase", "short".into())]).unwrap_err();
        assert_eq!(e.message, "auth_passphrase: at least 8 characters");
        assert!(!e.message.contains("short"));
        assert!(v3(&[("priv_passphrase", "".into())]).is_err());
        assert!(v3(&[
            ("priv_passphrase", "".into()),
            ("priv_protocol", "none".into())
        ])
        .is_ok());
        assert!(v3(&[("user", "".into())]).is_err());
        assert!(v3(&[("timeout_ms", Value::UInt(50))]).is_err());
        assert!(v3(&[("retries", Value::UInt(6))]).is_err());
    }

    #[test]
    fn plans_batch_scalars_and_group_columns() {
        let dev = Device::from_value(&map(&[("max_varbinds", Value::UInt(3))])).unwrap();
        let mut pts = Vec::new();
        for i in 0..7u32 {
            pts.push((
                format!("s{i}"),
                point(&[("oid", Value::from(format!("1.3.6.1.4.1.9.{i}.0")))]).unwrap(),
            ));
        }
        for row in [4u32, 2, 9] {
            pts.push((
                format!("in{row}"),
                point(&[
                    ("oid", "1.3.6.1.2.1.2.2.1.10".into()),
                    ("kind", "table_column".into()),
                    ("index", Value::from(row.to_string())),
                ])
                .unwrap(),
            ));
        }
        pts.push((
            "out1".into(),
            point(&[
                ("oid", "1.3.6.1.2.1.2.2.1.16".into()),
                ("kind", "table_column".into()),
                ("index", "1".into()),
                ("conv", "rate_per_s".into()),
            ])
            .unwrap(),
        ));
        let plan = SnmpDriver::plan(&dev, &pts);
        // 7 scalars + sysUpTime (rates) in batches of 3
        let sizes: Vec<usize> = plan.batches.iter().map(Vec::len).collect();
        assert_eq!(sizes, [3, 3, 2]);
        assert_eq!(plan.batches[0][0].id, UPTIME_ID);
        assert_eq!(plan.columns.len(), 2);
        let rows: Vec<&str> = plan.columns[0]
            .members
            .iter()
            .map(|m| m.id.as_str())
            .collect();
        assert_eq!(rows, ["in2", "in4", "in9"]);
        assert!(plan.rates);
        let other = SnmpDriver::plan(&dev, &pts[..1]);
        assert_ne!(plan.id, other.id);
        assert!(!other.rates);
        assert_eq!(other.batches.len(), 1);
    }

    #[test]
    fn before_is_below() {
        let o = Oid(vec![1, 3, 6, 5]);
        assert!(before(&o) < o);
        let z = Oid(vec![1, 3, 6, 0]);
        assert_eq!(before(&z), Oid(vec![1, 3, 6]));
        assert!(before(&z) < z);
    }
}
