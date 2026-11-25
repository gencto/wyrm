//! KNX connector (KNXnet/IP tunnelling and routing) on the driver framework
//! (ADR 0004).
//!
//! Tree: `<conn>/<device>/[<folder>/…]<point>`. A connection is a tunnel to
//! one KNXnet/IP interface ([`TunnelConn`]) or the routing multicast group
//! ([`RoutingConn`]). KNX has no devices to poll: every value travels to a
//! group address. So a device ([`Dev`]) is only a group of points for
//! people, and a point ([`Point`]) is one group address with a datapoint
//! type ([`dpt`]). The framework owns the tree, the generated actions,
//! edits, states, read-back writes and the quality ladder; this crate does
//! the protocol, with its own codec ([`proto`], [`cemi`]).
//!
//! * **Values are events.** The connection listens all the time
//!   ([`bus`]) and keeps the last GroupValue_Write or GroupValue_Response
//!   of every group address. A poll of the framework reads that table (no
//!   bus traffic), every [`TICK`]. A telegram that repeats the value it
//!   had is not published again.
//! * **Reads** are sent only where a point asks for them: `read_on_start`
//!   (one GroupValue_Read per connection, spread by the rate limit) and
//!   `poll_s` (a cyclic read). A read with no answer within `timeout_ms`
//!   is a miss of that point: `uncertain/stale`, and `bad/comm_fail` after
//!   three in a row (a start read is asked three times). The next value
//!   telegram of the address makes the point good again.
//! * **Writes** are a GroupValue_Write. The point takes the value only
//!   once the telegram is on the bus (the L_Data.con of a tunnel; routing
//!   has no confirmation, so: once the datagram left).
//! * A broken connection (no acknowledge, no answer to the connection
//!   state request, a disconnect by the interface) is `Transport`: the
//!   framework reconnects with backoff.
//!
//! Driver actions: connection `search_gateways`, `recent_telegrams`,
//! `connection_info`; device `read_group`, `write_group`.
//!
//! Not supported: KNX IP Secure and KNX Data Secure, the bus monitor
//! layer, device management (programming, properties), answering reads of
//! other devices, TCP tunnelling (KNXnet/IP v2), extended frames (values
//! over 14 octets).

#![forbid(unsafe_code)]

pub mod addr;
pub mod bus;
pub mod cemi;
pub mod dpt;
pub mod proto;
#[cfg(feature = "sim")]
pub mod sim;

use addr::{GroupAddr, IndividualAddr};
use bus::{Bus, RoutingCfg, SendError, State, TunnelCfg};
use cemi::Apci;
use dpt::Dpt;
use std::collections::BTreeMap;
use std::net::{Ipv4Addr, SocketAddrV4};
use std::sync::Mutex;
use std::time::Duration;
use tokio::time::Instant;
use wyrm_core::meta::{ActionResult, Writable};
use wyrm_core::{ActionMeta, NodeMeta, Perm, Status, TypeCode, Value};
use wyrm_link_sdk::driver::params::{field, ParamSpec};
// Traits (type namespace) beside the derive macros of the same name.
use wyrm_link_sdk::driver::{Driver, DriverError, Framework, Level, Params, PointId, Target};
use wyrm_link_sdk::{Args, LinkError, Params};

/// The `knx` link: the framework running [`KnxDriver`].
pub type Knx = Framework<KnxDriver>;

/// How often the framework reads the table of seen values.
pub const TICK: Duration = Duration::from_millis(200);
/// How often a device asks whether the connection is still there.
const PING: Duration = Duration::from_secs(2);
/// Reads without an answer before a point is `bad/comm_fail`.
const MISSES: u32 = 3;

/// A tunnel to one KNXnet/IP interface (tunnelling over UDP).
#[derive(Debug, Clone, PartialEq, Params)]
pub struct TunnelConn {
    #[param(display = "Host", placeholder = "192.168.1.10", dest)]
    pub host: String,
    #[param(default = 3671, min = 1, display = "Port", dest)]
    pub port: u16,
    /// Our endpoints are sent as `0.0.0.0:0`: the interface answers to the
    /// address the datagrams come from.
    #[param(
        default = false,
        display = "NAT mode",
        desc = "the interface is behind address translation"
    )]
    pub nat: bool,
    /// Bound on the connect answer, a confirmation and a read's answer.
    #[param(default = 3000, min = 100, max = 30000, display = "Timeout (ms)")]
    pub timeout_ms: u32,
    #[param(
        default = 60,
        min = 1,
        max = 60,
        display = "Heartbeat (s)",
        desc = "connection state request; KNXnet/IP says 60"
    )]
    pub heartbeat_s: u32,
    #[param(
        default = 20,
        min = 1,
        max = 100,
        display = "Telegrams per second",
        desc = "a twisted-pair line carries about 25"
    )]
    pub rate_per_s: u32,
}

/// The fields of a routing connection.
#[derive(Debug, Clone, PartialEq, Params)]
pub struct RoutingParams {
    #[param(default = "224.0.23.12", display = "Multicast address", dest)]
    pub group: String,
    #[param(default = 3671, min = 1, display = "Port", dest)]
    pub port: u16,
    #[param(
        default = "",
        display = "Interface address",
        placeholder = "192.168.1.20",
        desc = "IPv4 address of this host on the KNX network; empty: the system decides"
    )]
    pub interface: String,
    #[param(
        default = "15.15.255",
        display = "Individual address",
        desc = "the source address of our telegrams: a free address of the IP line"
    )]
    pub individual_address: String,
    /// Bound on a read's answer.
    #[param(default = 3000, min = 100, max = 30000, display = "Timeout (ms)")]
    pub timeout_ms: u32,
    #[param(
        default = 20,
        min = 1,
        max = 50,
        display = "Telegrams per second",
        desc = "KNXnet/IP routing allows 50"
    )]
    pub rate_per_s: u32,
    #[param(default = 16, min = 1, max = 255, display = "Multicast TTL")]
    pub ttl: u8,
}

/// The routing multicast group: the fields and what they parse to.
#[derive(Debug, Clone, PartialEq)]
pub struct RoutingConn {
    pub p: RoutingParams,
    group: Ipv4Addr,
    interface: Ipv4Addr,
    address: IndividualAddr,
}

impl Params for RoutingConn {
    fn schema() -> Vec<ParamSpec> {
        RoutingParams::schema()
    }

    fn from_map(m: &BTreeMap<String, Value>) -> wyrm_link_sdk::Result<Self> {
        let bad = |name: &str, why: String| LinkError::invalid_parameter(format!("{name}: {why}"));
        let p = RoutingParams::from_map(m)?;
        let group: Ipv4Addr = p
            .group
            .trim()
            .parse()
            .map_err(|e: std::net::AddrParseError| bad("group", e.to_string()))?;
        if !group.is_multicast() {
            return Err(bad("group", format!("{group} is not a multicast address")));
        }
        let interface = match p.interface.trim() {
            "" => Ipv4Addr::UNSPECIFIED,
            text => text
                .parse()
                .map_err(|e: std::net::AddrParseError| bad("interface", e.to_string()))?,
        };
        let address = IndividualAddr::parse(&p.individual_address)
            .map_err(|e| bad("individual_address", e.to_string()))?;
        Ok(RoutingConn {
            p,
            group,
            interface,
            address,
        })
    }

    fn to_map(&self) -> BTreeMap<String, Value> {
        self.p.to_map()
    }
}

/// A connection: one of two kinds, each with its own `add_*` action.
#[derive(Debug, Clone, PartialEq, Params)]
pub enum Conn {
    #[param(name = "tunnel_connection", display = "Tunnel connection")]
    Tunnel(TunnelConn),
    #[param(name = "routing_connection", display = "Routing connection")]
    Routing(RoutingConn),
}

impl Conn {
    fn timeout(&self) -> Duration {
        let ms = match self {
            Conn::Tunnel(c) => c.timeout_ms,
            Conn::Routing(c) => c.p.timeout_ms,
        };
        Duration::from_millis(ms.into())
    }
}

/// The fields of a device.
#[derive(Debug, Clone, PartialEq, Params)]
pub struct DevParams {
    #[param(
        default = "",
        display = "Individual address",
        placeholder = "1.1.5",
        desc = "a label for people; KNX values travel to group addresses"
    )]
    pub individual_address: String,
}

/// A device: a group of points. Its individual address is a label only.
#[derive(Debug, Clone, PartialEq)]
pub struct Dev {
    pub p: DevParams,
}

impl Params for Dev {
    fn schema() -> Vec<ParamSpec> {
        DevParams::schema()
    }

    fn from_map(m: &BTreeMap<String, Value>) -> wyrm_link_sdk::Result<Self> {
        let mut p = DevParams::from_map(m)?;
        let text = p.individual_address.trim();
        if !text.is_empty() {
            let a = IndividualAddr::parse(text)
                .map_err(|e| LinkError::invalid_parameter(format!("individual_address: {e}")))?;
            p.individual_address = a.to_string();
        }
        Ok(Dev { p })
    }

    fn to_map(&self) -> BTreeMap<String, Value> {
        self.p.to_map()
    }
}

/// One point: a group address and a datapoint type. Hand-written
/// `Params`: both are parsed, and the rules cross fields.
#[derive(Debug, Clone, PartialEq)]
pub struct Point {
    /// The group address as entered.
    pub address: String,
    /// The datapoint type as entered.
    pub dpt: String,
    pub read_on_start: bool,
    pub poll_s: f64,
    pub writable: bool,
    pub unit: String,
    pub to: GroupAddr,
    pub ty: Dpt,
}

impl Params for Point {
    fn schema() -> Vec<ParamSpec> {
        vec![
            ParamSpec::new("address", TypeCode::String)
                .placeholder("1/2/3")
                .desc("three levels 1/2/3, two levels 1/515, or the number 2563")
                .display("Group address"),
            ParamSpec::new("dpt", TypeCode::String)
                .placeholder("9.001")
                .desc("9.001 or DPST-9-1; a type the link does not know is raw octets")
                .display("Datapoint type"),
            ParamSpec::new("read_on_start", TypeCode::Bool)
                .default(false)
                .desc("send a GroupValue_Read when the connection opens")
                .display("Read on start"),
            ParamSpec::new("poll_s", TypeCode::Number)
                .default(0.0)
                .bounds(0.0, 86_400.0)
                .desc("send a GroupValue_Read this often; 0: only listen")
                .display("Poll rate (s)"),
            ParamSpec::new("writable", TypeCode::Bool)
                .default(false)
                .display("Writable"),
            ParamSpec::new("unit", TypeCode::String)
                .default("")
                .desc("empty: the unit of the datapoint type")
                .display("Unit"),
        ]
    }

    fn from_map(m: &BTreeMap<String, Value>) -> wyrm_link_sdk::Result<Self> {
        let address = field::string(m, "address")?.trim().to_owned();
        let dpt = field::string(m, "dpt")?.trim().to_owned();
        let to = GroupAddr::parse(&address)
            .map_err(|e| LinkError::invalid_parameter(format!("address: {e}")))?;
        let ty = Dpt::parse(&dpt).map_err(|e| LinkError::invalid_parameter(format!("dpt: {e}")))?;
        let poll_s = field::f64(m, "poll_s")?;
        if poll_s != 0.0 && poll_s < 1.0 {
            return Err(LinkError::invalid_parameter(
                "poll_s: 0 (only listen) or at least 1 second: every read is a telegram on the bus",
            ));
        }
        Ok(Point {
            address,
            dpt,
            read_on_start: field::bool(m, "read_on_start")?,
            poll_s,
            writable: field::bool(m, "writable")?,
            unit: field::string(m, "unit")?,
            to,
            ty,
        })
    }

    fn to_map(&self) -> BTreeMap<String, Value> {
        BTreeMap::from([
            ("address".into(), Value::Str(self.address.clone())),
            ("dpt".into(), Value::Str(self.dpt.clone())),
            ("read_on_start".into(), Value::Bool(self.read_on_start)),
            ("poll_s".into(), Value::Float(self.poll_s)),
            ("writable".into(), Value::Bool(self.writable)),
            ("unit".into(), Value::Str(self.unit.clone())),
        ])
    }
}

/// What a plan remembers of one point's reads.
#[derive(Debug, Clone, Default)]
struct Ask {
    /// The value counter of the address this point last saw.
    seen: u64,
    /// A read of ours is queued or on the bus since then.
    asked: Option<Instant>,
    /// Reads in a row without an answer.
    misses: u32,
    /// Ask again on the next turn (a start read that got no answer).
    again: bool,
    /// When the next cyclic read is due.
    next: Option<Instant>,
}

/// The points of one `(device, poll period)` group and their reads.
pub struct Plan {
    points: Vec<(PointId, Point)>,
    /// The reads of each point on the connection opened at that moment: a
    /// plan outlives a reconnect, what was asked of the old connection does
    /// not.
    asks: Mutex<(Option<Instant>, Vec<Ask>)>,
}

/// The open connection as the driver holds it.
pub struct Transport {
    bus: Bus,
    opened: Instant,
    /// Bound on a read's answer.
    answer: Duration,
    /// Where a search goes by default, and from which interface.
    search: (SocketAddrV4, Ipv4Addr),
}

fn send_error(e: SendError) -> DriverError {
    match e {
        SendError::Dead(why) => DriverError::Transport(why),
        e @ (SendError::NoConfirm | SendError::NoAnswer(_)) => DriverError::Device(e.to_string()),
        e @ (SendError::NotAcknowledged | SendError::Frame(_)) => DriverError::Point(e.to_string()),
    }
}

/// A failed action request as the caller sees it. A broken connection is
/// `disconnected`: the framework reconnects.
fn action_error(e: SendError) -> LinkError {
    match send_error(e) {
        DriverError::Transport(m) => LinkError::new(Status::Disconnected, m),
        DriverError::Device(m) => LinkError::timeout(m),
        DriverError::Point(m) => LinkError::invalid_parameter(m),
    }
}

/// One turn of one point: queue the read it is due, count the read that
/// got no answer, and give what the tree shows. `None`: nothing to say
/// (no value seen yet, or the point waits on a miss).
fn turn(
    bus: &Bus,
    state: &mut State,
    ask: &mut Ask,
    p: &Point,
    now: Instant,
    answer: Duration,
) -> Option<Result<Value, DriverError>> {
    let to = p.to.0;
    let seq = state.values.get(&to).map_or(0, |s| s.seq);
    if seq != ask.seen {
        // a value came: whatever was asked is answered
        *ask = Ask {
            seen: seq,
            next: ask.next,
            ..Ask::default()
        };
    }
    let mut missed = false;
    if let Some(asked) = ask.asked {
        let sent = state.reads.get(&to).filter(|sent| **sent >= asked);
        if sent.is_some_and(|sent| now.duration_since(*sent) >= answer) {
            ask.asked = None;
            ask.misses += 1;
            ask.again = p.poll_s == 0.0 && ask.misses < MISSES;
            missed = true;
        }
    }
    let start = p.read_on_start && !state.started.contains(&to);
    let cyclic = p.poll_s > 0.0 && ask.next.is_none_or(|at| now >= at);
    if ask.asked.is_none() && (start || cyclic || ask.again) && bus.queue_read(p.to) {
        ask.asked = Some(now);
        ask.again = false;
        state.started.insert(to);
        if p.poll_s > 0.0 {
            ask.next = Some(now + Duration::from_secs_f64(p.poll_s));
        }
    }
    // The framework counts a miss per poll, the bus per read. So the
    // first unanswered read is told once (`uncertain/stale`), the next ones
    // are not, and from the third on every poll tells it (`bad/comm_fail`,
    // and a device none of whose points answers is `Failed`).
    if (missed && ask.misses == 1) || ask.misses >= MISSES {
        return Some(Err(DriverError::Device(format!(
            "no answer to GroupValue_Read {}",
            p.to
        ))));
    }
    if ask.misses > 0 {
        return None;
    }
    let seen = state.values.get(&to)?;
    Some(
        p.ty.decode(&seen.data)
            .map_err(|e| DriverError::Point(e.to_string())),
    )
}

/// `search_gateways`.
#[derive(Args)]
struct SearchGateways {
    #[param(
        display = "Address",
        placeholder = "224.0.23.12",
        desc = "Where to ask: empty for the connection's network (the multicast group, or the \
                tunnel's interface), or one host."
    )]
    address: Option<String>,
    #[param(display = "Wait (ms)", default = 3000, min = 100, max = 10_000)]
    wait_ms: u64,
}

/// `recent_telegrams`.
#[derive(Args)]
struct RecentTelegrams {
    #[param(display = "Telegrams at most", default = 100, min = 1, max = 500)]
    max: u64,
}

/// `read_group`.
#[derive(Args)]
struct ReadGroup {
    #[param(display = "Group address", placeholder = "1/2/3")]
    address: String,
    #[param(display = "Datapoint type", placeholder = "9.001")]
    dpt: String,
}

/// `write_group`.
#[derive(Args)]
struct WriteGroup {
    #[param(display = "Group address", placeholder = "1/2/3")]
    address: String,
    #[param(display = "Datapoint type", placeholder = "9.001")]
    dpt: String,
    #[param(display = "Value")]
    value: Value,
}

fn group_arg(address: &str, dpt: &str) -> Result<(GroupAddr, Dpt), LinkError> {
    let to = GroupAddr::parse(address)
        .map_err(|e| LinkError::invalid_parameter(format!("address: {e}")))?;
    let ty = Dpt::parse(dpt).map_err(|e| LinkError::invalid_parameter(format!("dpt: {e}")))?;
    Ok((to, ty))
}

fn row<const N: usize>(fields: [(&str, Value); N]) -> Value {
    Value::Map(fields.into_iter().map(|(k, v)| (k.to_owned(), v)).collect())
}

async fn search_gateways(t: &Transport, args: SearchGateways) -> Result<Value, LinkError> {
    let (default, interface) = t.search;
    let target = match args.address.as_deref().map(str::trim) {
        None | Some("") => default,
        Some(text) => match (text.parse::<SocketAddrV4>(), text.parse::<Ipv4Addr>()) {
            (Ok(addr), _) => addr,
            (_, Ok(ip)) => SocketAddrV4::new(ip, proto::PORT),
            (Err(e), _) => {
                return Err(LinkError::invalid_parameter(format!(
                    "address: an IPv4 address, with a port or without ({e})"
                )))
            }
        },
    };
    let wait = Duration::from_millis(args.wait_ms);
    let found = bus::search(target, interface, wait)
        .await
        .map_err(|e| LinkError::internal(format!("search: {e}")))?;
    let rows = found.into_iter().map(|f| {
        let medium = match proto::Medium::try_from(f.device.medium) {
            Ok(m) => m.name().to_owned(),
            Err(code) => format!("0x{}", wyrm_core::hex::encode_upper([code])),
        };
        row([
            ("name", Value::Str(f.device.name)),
            ("address", Value::Str(f.endpoint.to_string())),
            ("medium", Value::Str(medium)),
            (
                "individual_address",
                Value::Str(f.device.address.to_string()),
            ),
            (
                "serial",
                Value::Str(wyrm_core::hex::encode_upper(f.device.serial)),
            ),
            (
                "mac",
                Value::Str(wyrm_core::hex::encode_sep(&f.device.mac, ":")),
            ),
        ])
    });
    Ok(Value::Array(rows.collect()))
}

fn recent_telegrams(t: &Transport, args: &RecentTelegrams) -> Value {
    let max = usize::try_from(args.max).unwrap_or(bus::RING);
    let rows = t.bus.recent(max).into_iter().map(|g| {
        let destination = if g.group {
            GroupAddr(g.destination).to_string()
        } else {
            IndividualAddr(g.destination).to_string()
        };
        let service = g.apci.map_or("other", Apci::name);
        row([
            ("time", Value::UInt(g.time_us)),
            ("sent", Value::Bool(g.sent)),
            ("source", Value::Str(g.source.to_string())),
            ("destination", Value::Str(destination)),
            ("service", Value::Str(service.to_owned())),
            ("data", Value::Bytes(g.data)),
            ("acknowledged", Value::Bool(!g.failed)),
        ])
    });
    Value::Array(rows.collect())
}

fn connection_info(t: &Transport) -> Value {
    let info = t.bus.info();
    let (lost, busy) = {
        let state = t.bus.state();
        (state.lost, state.busy)
    };
    row([
        ("individual_address", Value::Str(info.address.to_string())),
        ("peer", Value::Str(info.peer.to_string())),
        ("local", Value::Str(info.local.to_string())),
        ("lost_telegrams", Value::UInt(lost)),
        ("busy_signals", Value::UInt(busy)),
    ])
}

async fn read_group(t: &Transport, args: &ReadGroup) -> Result<Value, LinkError> {
    let (to, ty) = group_arg(&args.address, &args.dpt)?;
    let data = t.bus.read(to, t.answer).await.map_err(action_error)?;
    let value = ty
        .decode(&data)
        .map_err(|e| LinkError::new(Status::InvalidMessage, e.to_string()))?;
    Ok(row([
        ("value", value),
        ("dpt", Value::Str(ty.to_string())),
        ("unit", Value::Str(ty.unit().to_owned())),
        ("data", Value::Bytes(data.bytes)),
    ]))
}

async fn write_group(t: &Transport, args: &WriteGroup) -> Result<Value, LinkError> {
    let (to, ty) = group_arg(&args.address, &args.dpt)?;
    let data = ty
        .encode(&args.value)
        .map_err(|e| LinkError::invalid_parameter(format!("value: {e}")))?;
    let sent = data.bytes.clone();
    t.bus
        .send(to, Apci::Write, data)
        .await
        .map_err(action_error)?;
    Ok(row([
        ("address", Value::Str(to.to_string())),
        ("data", Value::Bytes(sent)),
    ]))
}

pub struct KnxDriver;

impl Driver for KnxDriver {
    const NAME: &'static str = "knx";
    const VERSION: &'static str = env!("CARGO_PKG_VERSION");
    type Conn = Conn;
    type Dev = Dev;
    type Point = Point;
    type Transport = Transport;
    type Plan = Plan;

    const FOLDERS: bool = true;

    async fn open(conn: &Conn) -> Result<Transport, DriverError> {
        let opened = match conn {
            Conn::Tunnel(c) => {
                let cfg = TunnelCfg {
                    host: c.host.clone(),
                    port: c.port,
                    nat: c.nat,
                    timeout: conn.timeout(),
                    heartbeat: Duration::from_secs(c.heartbeat_s.into()),
                    rate_per_s: c.rate_per_s,
                };
                Bus::tunnel(cfg).await
            }
            Conn::Routing(c) => {
                let cfg = RoutingCfg {
                    group: c.group,
                    port: c.p.port,
                    interface: c.interface,
                    address: c.address,
                    ttl: c.p.ttl.into(),
                    rate_per_s: c.p.rate_per_s,
                };
                Bus::routing(cfg).await
            }
        };
        let bus = opened.map_err(|e| DriverError::Transport(e.to_string()))?;
        let search = match conn {
            // a tunnel's own interface: it answers a search sent to it
            Conn::Tunnel(_) => (bus.info().peer, Ipv4Addr::UNSPECIFIED),
            Conn::Routing(c) => (bus.info().peer, c.interface),
        };
        Ok(Transport {
            bus,
            opened: Instant::now(),
            answer: conn.timeout(),
            search,
        })
    }

    /// A device is a group of points: it is "there" while the connection
    /// is.
    async fn ping(t: &mut Transport, _dev: &Dev) -> Result<(), DriverError> {
        match t.bus.dead() {
            Some(why) => Err(DriverError::Transport(why)),
            None => Ok(()),
        }
    }

    fn plan(_dev: &Dev, points: &[(PointId, Point)]) -> Plan {
        Plan {
            points: points.to_vec(),
            asks: Mutex::new((None, vec![Ask::default(); points.len()])),
        }
    }

    /// No bus traffic: what the connection has seen for each point, and
    /// the reads that are due go to the connection's queue.
    async fn poll(
        t: &mut Transport,
        _dev: &Dev,
        plan: &Plan,
    ) -> Vec<(PointId, Result<Value, DriverError>)> {
        let now = Instant::now();
        let mut state = t.bus.state();
        if let Some(why) = &state.dead {
            let broken = DriverError::Transport(why.clone());
            return plan
                .points
                .iter()
                .map(|(id, _)| (id.clone(), Err(broken.clone())))
                .collect();
        }
        let mut asks = plan.asks.lock().unwrap_or_else(|p| p.into_inner());
        if asks.0 != Some(t.opened) {
            *asks = (Some(t.opened), vec![Ask::default(); plan.points.len()]);
        }
        let mut out = Vec::new();
        for ((id, p), ask) in plan.points.iter().zip(asks.1.iter_mut()) {
            if let Some(r) = turn(&t.bus, &mut state, ask, p, now, t.answer) {
                out.push((id.clone(), r));
            }
        }
        out
    }

    async fn write(
        t: &mut Transport,
        _dev: &Dev,
        _id: &str,
        p: &Point,
        v: &Value,
    ) -> Result<(), DriverError> {
        if !p.writable {
            return Err(DriverError::Point("point is read-only".into()));
        }
        let data =
            p.ty.encode(v)
                .map_err(|e| DriverError::Point(e.to_string()))?;
        t.bus
            .send(p.to, Apci::Write, data)
            .await
            .map_err(send_error)
    }

    fn point_meta(p: &Point) -> NodeMeta {
        let mut m = NodeMeta::leaf(p.ty.type_code());
        let names = p.ty.enum_values();
        if !names.is_empty() {
            m = m.enum_values(names.iter().copied());
        }
        let unit = if p.unit.is_empty() {
            p.ty.unit()
        } else {
            &p.unit
        };
        if !unit.is_empty() {
            m = m.unit(unit);
        }
        m.writable(if p.writable {
            Writable::Write
        } else {
            Writable::Never
        })
    }

    fn poll_period(_p: &Point) -> Duration {
        TICK
    }

    fn ping_period(_dev: &Dev) -> Option<Duration> {
        Some(PING)
    }

    /// Bound on opening the connection (one connect answer).
    fn io_timeout(conn: &Conn) -> Duration {
        conn.timeout() + Duration::from_secs(2)
    }

    /// A write waits for its turn under the rate limit, the acknowledge
    /// (1 s, one repeat) and the confirmation.
    fn write_timeout(conn: &Conn, _p: &Point) -> Duration {
        conn.timeout() + Duration::from_secs(5)
    }

    fn stale_misses() -> u32 {
        MISSES
    }

    fn actions(level: Level, _kind: &str) -> Vec<(&'static str, ActionMeta)> {
        let map = ActionResult::Type(TypeCode::Map);
        let list = ActionResult::Type(TypeCode::Array);
        match level {
            Level::Connection => vec![
                (
                    "search_gateways",
                    SearchGateways::action()
                        .level(Perm::Config)
                        .display("Search gateways")
                        .timeout_ms(SEARCH_MS)
                        .result(list.clone()),
                ),
                (
                    "recent_telegrams",
                    RecentTelegrams::action()
                        .level(Perm::Read)
                        .display("Recent telegrams")
                        .result(list),
                ),
                (
                    "connection_info",
                    <()>::action()
                        .level(Perm::Read)
                        .display("Connection info")
                        .result(map),
                ),
            ],
            Level::Device => vec![
                (
                    "read_group",
                    ReadGroup::action()
                        .level(Perm::Read)
                        .display("Read group")
                        .timeout_ms(GROUP_MS)
                        .result(map.clone()),
                ),
                (
                    "write_group",
                    WriteGroup::action()
                        .level(Perm::Write)
                        .display("Write group")
                        .timeout_ms(GROUP_MS)
                        .result(map),
                ),
            ],
        }
    }

    async fn invoke(
        t: &mut Transport,
        _conn: &Conn,
        target: Target<'_, Self>,
        action: &str,
        args: &Value,
    ) -> Result<Value, LinkError> {
        if let Some(why) = t.bus.dead() {
            return Err(LinkError::new(Status::Disconnected, why));
        }
        let args = args.clone();
        match (target, action) {
            (Target::Connection, "search_gateways") => {
                search_gateways(t, SearchGateways::decode(args)?).await
            }
            (Target::Connection, "recent_telegrams") => {
                Ok(recent_telegrams(t, &RecentTelegrams::decode(args)?))
            }
            (Target::Connection, "connection_info") => {
                <()>::decode(args)?;
                Ok(connection_info(t))
            }
            (Target::Device { .. }, "read_group") => read_group(t, &ReadGroup::decode(args)?).await,
            (Target::Device { .. }, "write_group") => {
                write_group(t, &WriteGroup::decode(args)?).await
            }
            _ => Err(LinkError::not_supported(format!("action {action}"))),
        }
    }
}

/// Bound on `search_gateways`: the longest wait and the socket work.
const SEARCH_MS: u32 = 12_000;
/// Bound on `read_group` and `write_group`: the longest timeout twice (the
/// telegram, then the answer) and the acknowledge.
const GROUP_MS: u32 = 65_000;
