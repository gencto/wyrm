//! `uplink`: platform upstreams (ADR 0035) as a portable link (ADR 0023), as the scheduler and
//! DQL are. One source runs embedded in `wyrmd` (`wy/<site>/downstream/uplink`), as a process
//! (`--features process`) and as a WASM component (`--features wasm`).
//!
//! An upstream is a platform the site's live values go to: an MQTT broker as a Unified
//! Namespace, a Sparkplug B host, ThingsBoard, Azure IoT Hub or AWS IoT Core. It is added with
//! one action per kind (`add_mqtt`, …), as an upstream broker is added on `sys/upstream`, and
//! shows as a node with `status`, `error`, `url`, `enabled` and counters. Its one secret goes in
//! with ▸ Set Password and stays in the link's sealed store.
//!
//! The link subscribes to the subtrees the upstreams select (`<key>/**`), keeps the latest value
//! per point while a point is over its `max_hz`, queues values per upstream (the oldest go when
//! the queue is full) and sends them every `flush_ms` with an MQTT 3.1.1 client of its own
//! ([`mqtt`]) or over HTTPS (AWS). Sparkplug births, sequence numbers and rebirth commands are
//! handled here ([`sparkplug`]).
//!
//! Params: `site` (the host's site: defaults for `select`, `edge_node_id`, `device_prefix`,
//! `topic`), `own` (the link's own key, never sent), `net` (the link's allowlist as text, so an
//! Add can refuse a host it does not cover), `upstreams` (definitions from `wyrmd.json5`, shown
//! as `origin: config`).

pub mod mqtt;
pub mod platform;
pub mod sparkplug;
mod store;
pub mod tree;

use std::collections::{BTreeMap, BTreeSet, HashMap, VecDeque};

use wyrm_core::{Perm, Quality, Sample, Status, Value};
use wyrm_history_sync::http::Client as HttpClient;
use wyrm_history_sync::{sigv4, TargetError};
use wyrm_link_api::{App, AppError, ConnId, Host, Level, ReqId, Rights, SubId, TimerId, Who};

use platform::{azure_sas, device_and_metric, json_sample, json_value, url_encode, Map, Payload};
pub use platform::{Def, Kind};
use sparkplug::{DataType, Metric};

/// Upstreams at once.
pub const MAX_UPSTREAMS: usize = 16;
/// How long a CONNACK may take.
const CONNACK_WAIT_US: u64 = 10_000_000;
/// QoS 1 packets without a PUBACK at once.
const INFLIGHT_MAX: usize = 32;
/// A PUBACK this late means the connection is gone.
const PUBACK_WAIT_US: u64 = 30_000_000;
/// Bytes of one `tcp_send` (the host takes 64 KiB) and sends per flush.
const SEND_CHUNK: usize = 60 << 10;
const SENDS_PER_FLUSH: usize = 8;
const RECV_MAX: u32 = 64 << 10;
const RECV_TIMEOUT_MS: u32 = 1;
const FIRST_RETRY_MS: u64 = 1_000;
/// While a CONNACK is awaited.
const HANDSHAKE_POLL_MS: u64 = 100;
/// A SAS token is made again this long before it runs out.
const SAS_MARGIN_US: u64 = 120_000_000;
const AZURE_API: &str = "2021-04-12";

type Args = BTreeMap<String, Value>;

fn invalid(msg: impl Into<String>) -> AppError {
    AppError::new(Status::InvalidParameter, msg)
}

/// The rights of whoever adds or edits an upstream (ADR 0029): the uplink reads the whole site,
/// so an upstream sends only what its author may read. A token without `auth` is refused.
fn author_rights(who: &Who, select: &[String]) -> Result<Rights, AppError> {
    let rights = Rights::of(who).ok_or_else(|| {
        AppError::new(
            Status::PermissionDenied,
            "the caller's rights are unknown (its token carries no auth): an upstream sends \
             with its author's rights",
        )
    })?;
    if let Some(k) = select.iter().find(|k| !rights.may(k, Perm::Read)) {
        return Err(AppError::new(
            Status::PermissionDenied,
            format!("select: {k} is outside the caller's rights"),
        ));
    }
    Ok(rights)
}

fn args_of(args: Value) -> Result<Args, AppError> {
    match args {
        Value::Map(m) => Ok(m),
        Value::Null => Ok(Args::new()),
        _ => Err(invalid("args: a map")),
    }
}

/// `YYYY-MM-DDTHH:MM:SSZ` of UTC microseconds.
pub fn rfc3339(us: u64) -> String {
    let d = sigv4::amz_date(us);
    // YYYYMMDDTHHMMSSZ → YYYY-MM-DDTHH:MM:SSZ
    format!(
        "{}-{}-{}T{}:{}:{}Z",
        &d[0..4],
        &d[4..6],
        &d[6..8],
        &d[9..11],
        &d[11..13],
        &d[13..15]
    )
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum State {
    Disabled,
    Connecting,
    Connected,
    Waiting,
    Failed,
}

impl State {
    fn name(self) -> &'static str {
        match self {
            State::Disabled => "disabled",
            State::Connecting => "connecting",
            State::Connected => "connected",
            State::Waiting => "waiting",
            State::Failed => "failed",
        }
    }
}

/// Why a send or receive ended the connection.
enum Lost {
    /// Connect again after the back-off.
    Reconnect(String),
    /// Stop until a change (credentials refused).
    Fatal(String),
}

struct Item {
    key: String,
    s: Sample,
}

/// An MQTT session on a host connection.
struct Session {
    conn: ConnId,
    parser: mqtt::Parser,
    next_id: u16,
    /// Packet id → sent at (µs).
    inflight: BTreeMap<u16, u64>,
    last_send_us: u64,
    last_recv_us: u64,
    ping_outstanding: bool,
    /// CONNACK received.
    up: bool,
    opened_us: u64,
    /// Azure: when the SAS token runs out.
    sas_until_us: Option<u64>,
}

impl Session {
    fn packet_id(&mut self) -> u16 {
        loop {
            self.next_id = self.next_id.wrapping_add(1);
            if self.next_id != 0 && !self.inflight.contains_key(&self.next_id) {
                return self.next_id;
            }
        }
    }
}

/// A metric a Sparkplug device has shown: the type it was born with, the last value and time.
struct Known {
    ty: Option<DataType>,
    v: Value,
    t_ms: u64,
}

#[derive(Default)]
struct Sparkplug {
    bd_seq: u64,
    seq: u64,
    /// Device → metric → what was last seen (the BIRTH set).
    known: BTreeMap<String, BTreeMap<String, Known>>,
    born: BTreeSet<String>,
    node_born: bool,
}

/// One upstream at run time.
struct Up {
    def: Def,
    state: State,
    error: String,
    session: Option<Session>,
    http: Option<HttpClient>,
    queue: VecDeque<Item>,
    /// The latest value of a point over its rate, until the rate allows it.
    held: BTreeMap<String, Sample>,
    last_sent: HashMap<String, u64>,
    published: u64,
    dropped: u64,
    connected_since: u64,
    last_publish: u64,
    retry_ms: u64,
    timer: Option<TimerId>,
    sp: Sparkplug,
    /// ThingsBoard devices announced in this session.
    announced: BTreeSet<String>,
    /// What the tree shows, to update only on a change.
    shown: BTreeMap<&'static str, Value>,
    /// Its author's rights (ADR 0029); `None` for an entry of `wyrmd.json5` (the operator's).
    rights: Option<Rights>,
    /// Keys decided against `rights`, so a sample costs one lookup.
    readable: HashMap<String, bool>,
}

impl Up {
    /// A sample of `key` may go up: a `wyrmd.json5` entry sends all it selects, a runtime one
    /// only what its author may read (a runtime one without rights sends nothing).
    fn may_send(&mut self, key: &str) -> bool {
        if self.def.from_config {
            return true;
        }
        let Some(r) = &self.rights else {
            return false;
        };
        if let Some(ok) = self.readable.get(key) {
            return *ok;
        }
        let ok = r.may(key, Perm::Read);
        if self.readable.len() >= 65_536 {
            self.readable.clear();
        }
        self.readable.insert(key.to_owned(), ok);
        ok
    }

    fn new(def: Def, rights: Option<Rights>) -> Self {
        let state = if def.enabled {
            State::Connecting
        } else {
            State::Disabled
        };
        Up {
            def,
            state,
            error: String::new(),
            session: None,
            http: None,
            queue: VecDeque::new(),
            held: BTreeMap::new(),
            last_sent: HashMap::new(),
            published: 0,
            dropped: 0,
            connected_since: 0,
            last_publish: 0,
            retry_ms: FIRST_RETRY_MS,
            timer: None,
            sp: Sparkplug::default(),
            announced: BTreeSet::new(),
            shown: BTreeMap::new(),
            rights,
            readable: HashMap::new(),
        }
    }

    fn period_us(&self) -> u64 {
        if self.def.max_hz > 0.0 {
            (1_000_000.0 / self.def.max_hz) as u64
        } else {
            0
        }
    }

    /// A value of a selected point.
    fn take(&mut self, now: u64, key: &str, s: Sample, own_site: Option<&str>) {
        if self.state == State::Disabled {
            return;
        }
        if self.def.kind == Kind::Sparkplug {
            self.learn(key, &s, own_site);
        }
        let period = self.period_us();
        if period > 0 {
            let last = self.last_sent.get(key).copied().unwrap_or(0);
            if now.saturating_sub(last) < period {
                self.held.insert(key.to_owned(), s);
                return;
            }
            self.last_sent.insert(key.to_owned(), now);
        }
        self.push(Item {
            key: key.to_owned(),
            s,
        });
    }

    fn push(&mut self, item: Item) {
        if self.queue.len() >= self.def.queue_max {
            self.queue.pop_front();
            self.dropped += 1;
        }
        self.queue.push_back(item);
    }

    /// Held values whose rate allows them again go to the queue.
    fn release(&mut self, now: u64) {
        let period = self.period_us();
        if period == 0 || self.held.is_empty() {
            return;
        }
        let due: Vec<String> = self
            .held
            .keys()
            .filter(|k| now.saturating_sub(self.last_sent.get(*k).copied().unwrap_or(0)) >= period)
            .cloned()
            .collect();
        for k in due {
            if let Some(s) = self.held.remove(&k) {
                self.last_sent.insert(k.clone(), now);
                self.push(Item { key: k, s });
            }
        }
    }

    /// Sparkplug: remember the metric for the device's BIRTH; a type change means a new BIRTH.
    fn learn(&mut self, key: &str, s: &Sample, own_site: Option<&str>) {
        let Some((device, metric)) = device_and_metric(key, own_site) else {
            return;
        };
        let ty = DataType::of(&s.v);
        let dev = self.sp.known.entry(device.clone()).or_default();
        match dev.get_mut(metric) {
            Some(k) => {
                if ty.is_some() && k.ty.is_some() && ty != k.ty {
                    k.ty = ty;
                    self.sp.born.remove(&device);
                } else if k.ty.is_none() {
                    k.ty = ty;
                }
                k.v = s.v.clone();
                k.t_ms = s.t / 1000;
            }
            None => {
                dev.insert(
                    metric.to_owned(),
                    Known {
                        ty,
                        v: s.v.clone(),
                        t_ms: s.t / 1000,
                    },
                );
                self.sp.born.remove(&device);
            }
        }
    }

    fn show(&mut self, host: &mut dyn Host, now: u64) {
        let mut set = |name: &'static str, v: Value, shown: &mut BTreeMap<&'static str, Value>| {
            if shown.get(name) != Some(&v) {
                shown.insert(name, v.clone());
                host.update(
                    &tree::leaf(&self.def.name, name),
                    Sample {
                        v,
                        q: Quality::Good,
                        t: now,
                    },
                );
            }
        };
        let since = if self.connected_since > 0 {
            rfc3339(self.connected_since)
        } else {
            String::new()
        };
        let last = if self.last_publish > 0 {
            rfc3339(self.last_publish)
        } else {
            String::new()
        };
        let queued = (self.queue.len() + self.held.len()) as u64;
        let mut shown = std::mem::take(&mut self.shown);
        set("status", Value::from(self.state.name()), &mut shown);
        set("error", Value::from(self.error.as_str()), &mut shown);
        set("url", Value::from(self.def.url.as_str()), &mut shown);
        set("connected_since", Value::from(since), &mut shown);
        set("published", Value::UInt(self.published), &mut shown);
        set("dropped", Value::UInt(self.dropped), &mut shown);
        set("queued", Value::UInt(queued), &mut shown);
        set("last_publish", Value::from(last), &mut shown);
        set("enabled", Value::Bool(self.def.enabled), &mut shown);
        self.shown = shown;
    }

    fn close(&mut self, host: &mut dyn Host) {
        if let Some(s) = self.session.take() {
            if s.up {
                let _ = host.tcp_send(s.conn, &mqtt::disconnect());
            }
            host.tcp_close(s.conn);
        }
        if let Some(mut h) = self.http.take() {
            h.close(host);
        }
        self.connected_since = 0;
        self.sp.node_born = false;
        self.sp.born.clear();
        self.announced.clear();
    }

    fn lost(&mut self, host: &mut dyn Host, e: Lost) {
        self.close(host);
        match e {
            Lost::Reconnect(m) => {
                self.state = State::Waiting;
                self.error = m;
            }
            Lost::Fatal(m) => {
                self.state = State::Failed;
                self.error = m;
                host.log(
                    Level::Error,
                    &format!("uplink {}: {}", self.def.name, self.error),
                );
            }
        }
    }

    /// The MQTT CONNECT of this kind, with the secret where the kind puts it.
    fn connect_packet(
        &self,
        now: u64,
        site: Option<&str>,
        secret: Option<&str>,
    ) -> Result<(Vec<u8>, Option<u64>), String> {
        let d = &self.def;
        let client_id = d.client_id(site);
        let keep = d.uint("keep_alive_s", u64::from(platform::DEFAULT_KEEP_ALIVE_S)) as u16;
        let (username, password, sas_until, will);
        match d.kind {
            Kind::Mqtt | Kind::Sparkplug => {
                let u = d.str("username");
                username = (!u.is_empty()).then(|| u.to_owned());
                password = secret.map(|s| s.as_bytes().to_vec());
                sas_until = None;
                will = if d.kind == Kind::Sparkplug {
                    Some((
                        format!(
                            "{}/{}/NDEATH/{}",
                            sparkplug::NAMESPACE,
                            d.str("group_id"),
                            d.str("edge_node_id")
                        ),
                        sparkplug::payload(now / 1000, None, Some(self.sp.bd_seq), &[]),
                    ))
                } else {
                    None
                };
            }
            Kind::ThingsBoard => {
                username = Some(
                    secret
                        .ok_or("no access token: use Set Password")?
                        .to_owned(),
                );
                password = None;
                sas_until = None;
                will = None;
            }
            Kind::Azure => {
                let key = secret.ok_or("no device key: use Set Password")?;
                let ttl = d.uint("sas_ttl_s", platform::DEFAULT_SAS_TTL_S);
                let expiry = now / 1_000_000 + ttl;
                let token = azure_sas(d.str("hub"), d.str("device_id"), key, expiry)?;
                username = Some(format!(
                    "{}/{}/?api-version={AZURE_API}",
                    d.str("hub"),
                    d.str("device_id")
                ));
                password = Some(token.into_bytes());
                sas_until = Some(expiry * 1_000_000);
                will = None;
            }
            Kind::Aws => return Err("not MQTT".into()),
        }
        let packet = mqtt::connect(&mqtt::Connect {
            client_id: &client_id,
            username: username.as_deref(),
            password: password.as_deref(),
            keep_alive_s: keep,
            clean_session: true,
            will: will.as_ref().map(|(t, p)| mqtt::Will {
                topic: t,
                payload: p,
                qos: 1,
                retain: false,
            }),
        });
        Ok((packet, sas_until))
    }

    /// Open the connection and send CONNECT; the CONNACK comes on a later tick.
    fn connect(&mut self, host: &mut dyn Host, now: u64, site: Option<&str>) {
        let secret = store::secret(host, &self.def.name);
        if self.def.kind.needs_secret() && secret.is_none() {
            self.state = State::Failed;
            self.error = "no secret: use Set Password".into();
            return;
        }
        self.state = State::Connecting;
        let ep = self.def.endpoint();
        if self.def.kind == Kind::Aws {
            let mut http = HttpClient::new(
                ep.tls,
                ep.host.clone(),
                ep.port,
                self.def.ca_pem.clone(),
                self.def.timeout_ms,
            );
            match http.open(host) {
                Ok(_) => {
                    self.http = Some(http);
                    self.state = State::Connected;
                    self.connected_since = now;
                    self.error.clear();
                    self.retry_ms = FIRST_RETRY_MS;
                }
                Err(e) => self.lost(host, Lost::Reconnect(e.message().to_owned())),
            }
            return;
        }
        if self.def.kind == Kind::Sparkplug {
            self.sp.bd_seq = store::next_bdseq(host, &self.def.name);
            self.sp.seq = 0;
        }
        let (packet, sas_until) = match self.connect_packet(now, site, secret.as_deref()) {
            Ok(p) => p,
            Err(e) => return self.lost(host, Lost::Fatal(e)),
        };
        let conn = if ep.tls {
            host.tls_connect(
                &ep.host,
                ep.port,
                self.def.timeout_ms,
                self.def.ca_pem.as_deref(),
            )
        } else {
            host.tcp_connect(&ep.host, ep.port, self.def.timeout_ms)
        };
        let conn = match conn {
            Ok(c) => c,
            Err(e) if e.status == Status::PermissionDenied || e.status == Status::NotSupported => {
                return self.lost(
                    host,
                    Lost::Fatal(format!("connect {}:{}: {}", ep.host, ep.port, e.msg)),
                )
            }
            Err(e) => {
                return self.lost(
                    host,
                    Lost::Reconnect(format!("connect {}:{}: {}", ep.host, ep.port, e.msg)),
                )
            }
        };
        if let Err(e) = host.tcp_send(conn, &packet) {
            host.tcp_close(conn);
            return self.lost(host, Lost::Reconnect(format!("send CONNECT: {}", e.msg)));
        }
        self.session = Some(Session {
            conn,
            parser: mqtt::Parser::default(),
            next_id: 0,
            inflight: BTreeMap::new(),
            last_send_us: now,
            last_recv_us: now,
            ping_outstanding: false,
            up: false,
            opened_us: now,
            sas_until_us: sas_until,
        });
    }

    /// Read what the broker sent and act on it. `Ok(true)` once the CONNACK came in this call.
    fn receive(&mut self, host: &mut dyn Host, now: u64) -> Result<(), Lost> {
        let Some(mut s) = self.session.take() else {
            return Ok(());
        };
        let r = self.receive_into(host, now, &mut s);
        self.session = Some(s);
        r
    }

    fn receive_into(&mut self, host: &mut dyn Host, now: u64, s: &mut Session) -> Result<(), Lost> {
        for _ in 0..4 {
            let bytes = match host.tcp_recv(s.conn, RECV_MAX, RECV_TIMEOUT_MS) {
                Ok(b) if b.is_empty() => {
                    return Err(Lost::Reconnect("the broker closed the connection".into()))
                }
                Ok(b) => b,
                Err(e) if e.status == Status::Timeout => break,
                Err(e) => return Err(Lost::Reconnect(format!("recv: {}", e.msg))),
            };
            s.last_recv_us = now;
            let full = bytes.len() as u32 >= RECV_MAX;
            s.parser.feed(&bytes).map_err(Lost::Reconnect)?;
            while let Some(p) = s.parser.packet().map_err(Lost::Reconnect)? {
                self.packet(host, now, s, p)?;
            }
            if !full {
                break;
            }
        }
        Ok(())
    }

    fn packet(
        &mut self,
        host: &mut dyn Host,
        now: u64,
        s: &mut Session,
        p: mqtt::Packet,
    ) -> Result<(), Lost> {
        match p {
            mqtt::Packet::ConnAck { code: 0, .. } => {
                s.up = true;
                self.state = State::Connected;
                self.connected_since = now;
                self.error.clear();
                self.retry_ms = FIRST_RETRY_MS;
                if self.def.kind == Kind::Sparkplug {
                    let (g, n) = (self.def.str("group_id"), self.def.str("edge_node_id"));
                    let ncmd = format!("{}/{g}/NCMD/{n}", sparkplug::NAMESPACE);
                    let dcmd = format!("{}/{g}/DCMD/{n}/+", sparkplug::NAMESPACE);
                    let id = s.packet_id();
                    host.tcp_send(s.conn, &mqtt::subscribe(id, &[(&ncmd, 0), (&dcmd, 0)]))
                        .map_err(|e| Lost::Reconnect(format!("send SUBSCRIBE: {}", e.msg)))?;
                    s.last_send_us = now;
                }
            }
            mqtt::Packet::ConnAck { code, .. } => {
                let text = mqtt::connack_text(code);
                return Err(if matches!(code, 4 | 5) {
                    Lost::Fatal(format!("CONNACK: {text}"))
                } else {
                    Lost::Reconnect(format!("CONNACK: {text}"))
                });
            }
            mqtt::Packet::PubAck(id) => {
                s.inflight.remove(&id);
            }
            mqtt::Packet::PingResp => s.ping_outstanding = false,
            mqtt::Packet::SubAck { .. } | mqtt::Packet::Other(_) => {}
            mqtt::Packet::Publish {
                topic,
                payload,
                qos,
                id,
                ..
            } => {
                if qos == 1 {
                    if let Some(id) = id {
                        let _ = host.tcp_send(s.conn, &mqtt::puback(id));
                        s.last_send_us = now;
                    }
                }
                if self.def.kind == Kind::Sparkplug && topic.contains("CMD/") {
                    let rebirth = sparkplug::command_metrics(&payload)
                        .unwrap_or_default()
                        .into_iter()
                        .any(|(n, on)| {
                            on && (n == sparkplug::REBIRTH || n == sparkplug::DEVICE_REBIRTH)
                        });
                    if rebirth {
                        host.log(
                            Level::Info,
                            &format!("uplink {}: rebirth requested", self.def.name),
                        );
                        self.sp.node_born = false;
                        self.sp.born.clear();
                    }
                }
            }
        }
        Ok(())
    }

    fn send(&mut self, host: &mut dyn Host, now: u64, frames: &[u8]) -> Result<(), Lost> {
        if frames.is_empty() {
            return Ok(());
        }
        let Some(s) = self.session.as_mut() else {
            return Err(Lost::Reconnect("no session".into()));
        };
        host.tcp_send(s.conn, frames)
            .map_err(|e| Lost::Reconnect(format!("send: {}", e.msg)))?;
        s.last_send_us = now;
        Ok(())
    }

    /// Keep-alive and the QoS 1 window; the SAS token's end.
    fn housekeeping(&mut self, host: &mut dyn Host, now: u64) -> Result<(), Lost> {
        let keep_us = self.def.uint("keep_alive_s", 60) * 1_000_000;
        let Some(s) = self.session.as_mut() else {
            return Ok(());
        };
        if s.inflight
            .values()
            .any(|t| now.saturating_sub(*t) > PUBACK_WAIT_US)
        {
            return Err(Lost::Reconnect("no PUBACK in 30 s".into()));
        }
        if s.ping_outstanding && now.saturating_sub(s.last_recv_us) > keep_us + keep_us / 2 {
            return Err(Lost::Reconnect("no PINGRESP".into()));
        }
        if let Some(until) = s.sas_until_us {
            if until.saturating_sub(now) < SAS_MARGIN_US {
                return Err(Lost::Reconnect("SAS token renewed".into()));
            }
        }
        if now.saturating_sub(s.last_send_us) >= keep_us / 2 {
            host.tcp_send(s.conn, &mqtt::pingreq())
                .map_err(|e| Lost::Reconnect(format!("send PINGREQ: {}", e.msg)))?;
            s.last_send_us = now;
            s.ping_outstanding = true;
        }
        Ok(())
    }

    /// A PUBLISH frame; QoS 1 takes a packet id while the window has room.
    fn publish_frame(
        &mut self,
        now: u64,
        topic: &str,
        payload: &[u8],
        qos: u8,
        retain: bool,
    ) -> Option<Vec<u8>> {
        let s = self.session.as_mut()?;
        let id = if qos > 0 {
            if s.inflight.len() >= INFLIGHT_MAX {
                return None;
            }
            let id = s.packet_id();
            s.inflight.insert(id, now);
            Some(id)
        } else {
            None
        };
        Some(mqtt::publish(topic, payload, qos, retain, id))
    }

    /// Send what is queued (and, for Sparkplug, the births that are due).
    fn flush(&mut self, host: &mut dyn Host, now: u64, site: Option<&str>) -> Result<(), Lost> {
        self.release(now);
        match self.def.kind {
            Kind::Mqtt => self.flush_mqtt(host, now),
            Kind::Sparkplug => self.flush_sparkplug(host, now, site),
            Kind::ThingsBoard => self.flush_thingsboard(host, now, site),
            Kind::Azure => self.flush_azure(host, now),
            Kind::Aws => self.flush_aws(host, now),
        }
    }

    fn flush_mqtt(&mut self, host: &mut dyn Host, now: u64) -> Result<(), Lost> {
        let prefix = self.def.str("topic_prefix").to_owned();
        let qos = self.def.uint("qos", 0) as u8;
        let retain = self.def.flag("retain", true);
        let mode = self.def.payload();
        let mut sends = 0;
        while !self.queue.is_empty() && sends < SENDS_PER_FLUSH {
            let mut frames = Vec::new();
            let mut n = 0u64;
            while frames.len() < SEND_CHUNK {
                let Some(item) = self.queue.front() else {
                    break;
                };
                let topic = format!("{prefix}/{}", &item.key[3.min(item.key.len())..]);
                let payload = match mode {
                    Payload::Json => json_sample(&item.s).to_string(),
                    Payload::Value => match &item.s.v {
                        Value::Str(s) => s.clone(),
                        v => json_value(v).to_string(),
                    },
                };
                let Some(f) = self.publish_frame(now, &topic, payload.as_bytes(), qos, retain)
                else {
                    break; // the QoS 1 window is full: later
                };
                frames.extend(f);
                self.queue.pop_front();
                n += 1;
            }
            if n == 0 {
                break;
            }
            self.send(host, now, &frames)?;
            self.published += n;
            self.last_publish = now;
            sends += 1;
        }
        Ok(())
    }

    fn sparkplug_topic(&self, kind: &str, device: Option<&str>) -> String {
        let (g, n) = (self.def.str("group_id"), self.def.str("edge_node_id"));
        match device {
            Some(d) => format!("{}/{g}/{kind}/{n}/{d}", sparkplug::NAMESPACE),
            None => format!("{}/{g}/{kind}/{n}", sparkplug::NAMESPACE),
        }
    }

    fn next_seq(&mut self) -> u64 {
        let s = self.sp.seq;
        self.sp.seq = (self.sp.seq + 1) % 256;
        s
    }

    fn flush_sparkplug(
        &mut self,
        host: &mut dyn Host,
        now: u64,
        site: Option<&str>,
    ) -> Result<(), Lost> {
        let now_ms = now / 1000;
        let mut frames = Vec::new();
        if !self.sp.node_born {
            // NBIRTH: bdSeq and the required Node Control/Rebirth, seq 0
            self.sp.seq = 0;
            let rebirth = Value::Bool(false);
            let m = [Metric {
                name: sparkplug::REBIRTH,
                t_ms: now_ms,
                value: &rebirth,
                datatype: None,
                with_type: true,
            }];
            let seq = self.next_seq();
            let p = sparkplug::payload(now_ms, Some(seq), Some(self.sp.bd_seq), &m);
            let topic = self.sparkplug_topic("NBIRTH", None);
            if let Some(f) = self.publish_frame(now, &topic, &p, 0, false) {
                frames.extend(f);
            }
            self.sp.node_born = true;
            self.sp.born.clear();
        }
        // births of devices with metrics the host has not seen
        let unborn: Vec<String> = self
            .sp
            .known
            .keys()
            .filter(|d| !self.sp.born.contains(*d))
            .cloned()
            .collect();
        let mut born_now: BTreeSet<String> = BTreeSet::new();
        for device in unborn {
            born_now.insert(device.clone());
            let metrics: Vec<(String, Value, u64, Option<DataType>)> = self.sp.known[&device]
                .iter()
                .map(|(n, k)| (n.clone(), k.v.clone(), k.t_ms, k.ty))
                .collect();
            let ms: Vec<Metric<'_>> = metrics
                .iter()
                .map(|(n, v, t, ty)| Metric {
                    name: n,
                    t_ms: *t,
                    value: v,
                    datatype: *ty,
                    with_type: true,
                })
                .collect();
            let seq = self.next_seq();
            let p = sparkplug::payload(now_ms, Some(seq), None, &ms);
            let topic = self.sparkplug_topic("DBIRTH", Some(&device));
            if let Some(f) = self.publish_frame(now, &topic, &p, 0, false) {
                frames.extend(f);
            }
            self.sp.born.insert(device);
            if frames.len() >= SEND_CHUNK {
                self.send(host, now, &std::mem::take(&mut frames))?;
            }
        }
        // DDATA: the queued values, one payload per device per flush
        let mut per_device: BTreeMap<String, Vec<(String, Sample)>> = BTreeMap::new();
        let mut n = 0u64;
        let mut budget = SENDS_PER_FLUSH * SEND_CHUNK;
        while let Some(front) = self.queue.front() {
            if budget < 64 {
                break;
            }
            let dm = device_and_metric(&front.key, site).map(|(d, m)| (d, m.to_owned()));
            let Some(item) = self.queue.pop_front() else {
                break;
            };
            let Some((device, metric)) = dm else { continue };
            n += 1;
            if born_now.contains(&device) {
                // its BIRTH of this flush carries the latest value already
                continue;
            }
            budget = budget.saturating_sub(metric.len() + 32);
            per_device.entry(device).or_default().push((metric, item.s));
        }
        for (device, samples) in per_device {
            let ms: Vec<Metric<'_>> = samples
                .iter()
                .map(|(name, s)| Metric {
                    name,
                    t_ms: s.t / 1000,
                    value: &s.v,
                    datatype: None,
                    with_type: false,
                })
                .collect();
            let seq = self.next_seq();
            let p = sparkplug::payload(now_ms, Some(seq), None, &ms);
            let topic = self.sparkplug_topic("DDATA", Some(&device));
            if let Some(f) = self.publish_frame(now, &topic, &p, 0, false) {
                frames.extend(f);
            }
            if frames.len() >= SEND_CHUNK {
                self.send(host, now, &std::mem::take(&mut frames))?;
            }
        }
        if !frames.is_empty() {
            self.send(host, now, &frames)?;
        }
        if n > 0 {
            self.published += n;
            self.last_publish = now;
        }
        Ok(())
    }

    fn flush_thingsboard(
        &mut self,
        host: &mut dyn Host,
        now: u64,
        site: Option<&str>,
    ) -> Result<(), Lost> {
        if self.queue.is_empty() {
            return Ok(());
        }
        // the telemetry and every connect need a packet id: room in the window first
        if self
            .session
            .as_ref()
            .is_some_and(|s| s.inflight.len() + 2 >= INFLIGHT_MAX)
        {
            return Ok(());
        }
        let prefix = self.def.str("device_prefix").to_owned();
        let mut frames = Vec::new();
        let mut telemetry = serde_json::Map::new();
        let mut n = 0u64;
        let mut size = 0usize;
        while let Some(front) = self.queue.front() {
            if size > SEND_CHUNK / 2 {
                break;
            }
            let dm = device_and_metric(&front.key, site).map(|(d, m)| (d, m.to_owned()));
            let Some(item) = self.queue.pop_front() else {
                break;
            };
            let Some((device, metric)) = dm else { continue };
            let device = format!("{prefix}-{device}");
            if self.announced.insert(device.clone()) {
                let p = serde_json::json!({ "device": device }).to_string();
                if let Some(f) =
                    self.publish_frame(now, "v1/gateway/connect", p.as_bytes(), 1, false)
                {
                    frames.extend(f);
                }
            }
            size += metric.len() + 48;
            let row = serde_json::json!({ "ts": item.s.t / 1000, "values": { metric: json_value(&item.s.v) } });
            if let Some(a) = telemetry
                .entry(device)
                .or_insert_with(|| serde_json::Value::Array(Vec::new()))
                .as_array_mut()
            {
                a.push(row);
            }
            n += 1;
        }
        if n > 0 {
            let p = serde_json::Value::Object(telemetry).to_string();
            if let Some(f) = self.publish_frame(now, "v1/gateway/telemetry", p.as_bytes(), 1, false)
            {
                frames.extend(f);
            }
        }
        self.send(host, now, &frames)?;
        if n > 0 {
            self.published += n;
            self.last_publish = now;
        }
        Ok(())
    }

    /// A JSON array of `{"key", "v", "q", "t"}` from the front of the queue, within `max` bytes.
    fn json_batch(&mut self, max: usize) -> (String, u64) {
        let mut out = String::from("[");
        let mut n = 0u64;
        while let Some(item) = self.queue.front() {
            let mut row = json_sample(&item.s);
            if let Some(o) = row.as_object_mut() {
                o.insert(
                    "key".into(),
                    serde_json::Value::String(item.key[3.min(item.key.len())..].to_owned()),
                );
            }
            let row = row.to_string();
            if out.len() + row.len() + 2 > max && n > 0 {
                break;
            }
            if n > 0 {
                out.push(',');
            }
            out.push_str(&row);
            self.queue.pop_front();
            n += 1;
        }
        out.push(']');
        (out, n)
    }

    fn flush_azure(&mut self, host: &mut dyn Host, now: u64) -> Result<(), Lost> {
        let topic = format!(
            "devices/{}/messages/events/%24.ct=application%2Fjson&%24.ce=utf-8",
            self.def.str("device_id")
        );
        let mut sends = 0;
        while !self.queue.is_empty() && sends < SENDS_PER_FLUSH {
            if self
                .session
                .as_ref()
                .is_some_and(|s| s.inflight.len() >= INFLIGHT_MAX)
            {
                break;
            }
            let (body, n) = self.json_batch(SEND_CHUNK);
            let Some(f) = self.publish_frame(now, &topic, body.as_bytes(), 1, false) else {
                break;
            };
            self.send(host, now, &f)?;
            self.published += n;
            self.last_publish = now;
            sends += 1;
        }
        Ok(())
    }

    fn flush_aws(&mut self, host: &mut dyn Host, now: u64) -> Result<(), Lost> {
        let mut sends = 0;
        while !self.queue.is_empty() && sends < 2 {
            let (body, n) = self.json_batch(SEND_CHUNK);
            self.aws_publish(host, now, body.as_bytes())?;
            self.published += n;
            self.last_publish = now;
            sends += 1;
        }
        Ok(())
    }

    /// `POST /topics/<topic>?qos=1` with Signature V4 (service `iotdata`).
    fn aws_publish(&mut self, host: &mut dyn Host, now: u64, body: &[u8]) -> Result<(), Lost> {
        let secret =
            store::secret(host, &self.def.name).ok_or_else(|| Lost::Fatal("no secret".into()))?;
        let Some(http) = self.http.as_mut() else {
            return Err(Lost::Reconnect("no connection".into()));
        };
        let date = sigv4::amz_date(now);
        let host_header = http.host_header();
        let path = format!("/topics/{}", url_encode(self.def.str("topic")));
        let payload_hash = sigv4::sha256_hex(body);
        let signed = [
            ("host", host_header.as_str()),
            ("x-amz-content-sha256", payload_hash.as_str()),
            ("x-amz-date", date.as_str()),
        ];
        let auth = sigv4::authorization(
            &sigv4::Signing {
                access_key: self.def.str("access_key_id"),
                secret_key: &secret,
                region: self.def.str("region"),
                service: "iotdata",
                amz_date: &date,
            },
            "POST",
            &path,
            "qos=1",
            &signed,
            body,
        );
        let headers = [
            ("Authorization", auth.as_str()),
            ("Content-Type", "application/json"),
            ("x-amz-content-sha256", payload_hash.as_str()),
            ("x-amz-date", date.as_str()),
        ];
        let r = http
            .request(host, "POST", &format!("{path}?qos=1"), &headers, body)
            .map_err(|e| match e {
                TargetError::Fatal(m) => Lost::Fatal(m),
                other => Lost::Reconnect(other.message().to_owned()),
            })?;
        match r.status {
            200..=299 => Ok(()),
            401 | 403 => Err(Lost::Fatal(format!("aws: {} {}", r.status, r.text(200)))),
            _ => Err(Lost::Reconnect(format!(
                "aws: {} {}",
                r.status,
                r.text(200)
            ))),
        }
    }

    /// One step of the connection; what to do next is decided by the state after it.
    fn tick(&mut self, host: &mut dyn Host, now: u64, site: Option<&str>) {
        match self.state {
            State::Disabled | State::Failed => {}
            State::Waiting => {
                self.connect(host, now, site);
                if self.state == State::Connected {
                    if let Err(e) = self.flush(host, now, site) {
                        self.lost(host, e);
                    }
                }
            }
            State::Connecting => {
                if self.session.is_none() {
                    self.connect(host, now, site);
                    if self.state == State::Connected {
                        if let Err(e) = self.flush(host, now, site) {
                            self.lost(host, e);
                        }
                    }
                    return;
                }
                if let Err(e) = self.receive(host, now) {
                    return self.lost(host, e);
                }
                if self.state == State::Connected {
                    if let Err(e) = self.flush(host, now, site) {
                        self.lost(host, e);
                    }
                } else if self
                    .session
                    .as_ref()
                    .is_some_and(|s| now.saturating_sub(s.opened_us) > CONNACK_WAIT_US)
                {
                    self.lost(host, Lost::Reconnect("no CONNACK in 10 s".into()));
                }
            }
            State::Connected => {
                let r = if self.def.kind == Kind::Aws {
                    self.flush(host, now, site)
                } else {
                    self.receive(host, now)
                        .and_then(|_| self.flush(host, now, site))
                        .and_then(|_| self.receive(host, now))
                        .and_then(|_| self.housekeeping(host, now))
                };
                if let Err(e) = r {
                    self.lost(host, e);
                }
            }
        }
    }

    /// When the next tick is due, in ms; `None` for nothing to do.
    fn next_delay_ms(&mut self) -> Option<u64> {
        match self.state {
            State::Disabled | State::Failed => None,
            State::Connecting => Some(if self.session.is_some() {
                HANDSHAKE_POLL_MS
            } else {
                1
            }),
            State::Connected => Some(self.def.flush_ms),
            State::Waiting => {
                let ms = self.retry_ms;
                self.retry_ms = (self.retry_ms * 2)
                    .min(self.def.retry_s * 1000)
                    .max(FIRST_RETRY_MS);
                Some(ms)
            }
        }
    }

    /// Start again after a change (Edit, Set Password, Enable): the queue stays.
    fn restart(&mut self, host: &mut dyn Host) {
        self.close(host);
        self.retry_ms = FIRST_RETRY_MS;
        self.error.clear();
        self.state = if self.def.enabled {
            State::Connecting
        } else {
            State::Disabled
        };
    }

    /// ▸ Test Connection: a whole MQTT handshake (or one AWS request) now, on a connection of
    /// its own, within the call's time. A connected MQTT upstream answers from its live session:
    /// a second CONNECT with the same client id would make the broker close the live one (and
    /// publish its will, a Sparkplug NDEATH), and another client id is not allowed everywhere
    /// (Azure: the device id).
    fn test(
        &mut self,
        host: &mut dyn Host,
        now: u64,
        site: Option<&str>,
    ) -> Result<String, String> {
        let secret = store::secret(host, &self.def.name);
        if self.def.kind.needs_secret() && secret.is_none() {
            return Err("no secret: use Set Password".into());
        }
        let ep = self.def.endpoint();
        if self.def.kind != Kind::Aws && self.state == State::Connected {
            return Ok(format!(
                "connected to {}:{} (the live session)",
                ep.host, ep.port
            ));
        }
        let timeout = self.def.timeout_ms.min(4_000);
        if self.def.kind == Kind::Aws {
            let mut http = HttpClient::new(
                ep.tls,
                ep.host.clone(),
                ep.port,
                self.def.ca_pem.clone(),
                timeout,
            );
            http.open(host).map_err(|e| e.message().to_owned())?;
            let saved = self.http.replace(http);
            let r = self.aws_publish(host, now, b"[]");
            if let Some(mut h) = self.http.take() {
                h.close(host);
            }
            self.http = saved;
            return match r {
                Ok(()) => Ok(format!(
                    "published an empty batch to {}",
                    self.def.str("topic")
                )),
                Err(Lost::Fatal(m) | Lost::Reconnect(m)) => Err(m),
            };
        }
        let (packet, _) = self.connect_packet(now, site, secret.as_deref())?;
        let conn = if ep.tls {
            host.tls_connect(&ep.host, ep.port, timeout, self.def.ca_pem.as_deref())
        } else {
            host.tcp_connect(&ep.host, ep.port, timeout)
        }
        .map_err(|e| format!("connect {}:{}: {}", ep.host, ep.port, e.msg))?;
        let result = (|| {
            host.tcp_send(conn, &packet)
                .map_err(|e| format!("send CONNECT: {}", e.msg))?;
            let mut parser = mqtt::Parser::default();
            for _ in 0..8 {
                let bytes = host
                    .tcp_recv(conn, RECV_MAX, timeout / 8)
                    .map_err(|e| format!("CONNACK: {}", e.msg))?;
                if bytes.is_empty() {
                    return Err("the broker closed the connection".into());
                }
                parser.feed(&bytes)?;
                if let Some(mqtt::Packet::ConnAck { code, .. }) = parser.packet()? {
                    return if code == 0 {
                        Ok(format!("connected to {}:{}", ep.host, ep.port))
                    } else {
                        Err(format!("CONNACK: {}", mqtt::connack_text(code)))
                    };
                }
            }
            Err("no CONNACK".into())
        })();
        if result.is_ok() {
            let _ = host.tcp_send(conn, &mqtt::disconnect());
        }
        host.tcp_close(conn);
        result
    }
}

/// The link.
pub struct Uplink {
    site: Option<String>,
    own: Option<String>,
    net: Option<String>,
    ups: BTreeMap<String, Up>,
    timers: HashMap<u64, String>,
    /// `(upstream, selected prefix)` → its subscription. Each upstream has its own, so the
    /// current values that come with a subscription reach an upstream added or edited after
    /// another one selected the same prefix.
    subs: BTreeMap<(String, String), SubId>,
    /// Subscription → `(upstream, prefix)`.
    sub_owner: HashMap<u64, (String, String)>,
    total_published: u64,
    total_dropped: u64,
    stats_shown: BTreeMap<&'static str, u64>,
}

/// `(site, own, net, upstreams)` of the params.
struct Params {
    site: Option<String>,
    own: Option<String>,
    net: Option<String>,
    upstreams: Vec<Value>,
}

fn params_of(config: Value) -> Result<Params, AppError> {
    let m = match config {
        Value::Map(m) => m,
        Value::Null => Map::new(),
        _ => return Err(invalid("params: a map")),
    };
    let text = |k: &str| match m.get(k) {
        None | Some(Value::Null) => Ok(None),
        Some(Value::Str(s)) if s.is_empty() => Ok(None),
        Some(Value::Str(s)) => Ok(Some(s.clone())),
        Some(_) => Err(invalid(format!("params.{k}: text"))),
    };
    for k in m.keys() {
        if !["site", "own", "net", "upstreams"].contains(&k.as_str()) {
            return Err(invalid(format!("params.{k}: unknown")));
        }
    }
    let ups = match m.get("upstreams") {
        None | Some(Value::Null) => Vec::new(),
        Some(Value::Array(a)) => a.clone(),
        Some(_) => return Err(invalid("params.upstreams: an array of upstreams")),
    };
    Ok(Params {
        site: text("site")?,
        own: text("own")?,
        net: text("net")?,
        upstreams: ups,
    })
}

impl Uplink {
    fn declare(&self, host: &mut dyn Host, up: &Up) {
        let d = &up.def;
        host.declare_node(
            &d.name,
            tree::upstream_node(d.kind, d.from_config, &d.select),
        );
        for (l, ty, about) in tree::LEAVES {
            let meta = if l == "status" {
                tree::status_node()
            } else {
                wyrm_core::NodeMeta::leaf(ty).attr("description", about)
            };
            host.declare_node(&tree::leaf(&d.name, l), meta);
        }
        host.declare_node(
            &tree::leaf(&d.name, "enabled"),
            tree::enabled_node(d.from_config),
        );
        for (name, a) in tree::upstream_actions(d.kind, d.from_config) {
            host.declare_action(&d.name, name, a);
        }
    }

    fn arm(&mut self, host: &mut dyn Host, name: &str) {
        let Some(up) = self.ups.get_mut(name) else {
            return;
        };
        if let Some(t) = up.timer.take() {
            host.cancel_timer(t);
            self.timers.remove(&t.0);
        }
        if let Some(ms) = up.next_delay_ms() {
            match host.set_timer(ms.max(1)) {
                Ok(t) => {
                    up.timer = Some(t);
                    self.timers.insert(t.0, name.to_owned());
                }
                Err(e) => host.log(Level::Error, &format!("timer: {}", e.msg)),
            }
        }
    }

    fn subscribe_all(&mut self, host: &mut dyn Host, name: &str) {
        let Some(up) = self.ups.get(name) else {
            return;
        };
        for p in up.def.select.clone() {
            let k = (name.to_owned(), p.clone());
            match self.subs.get(&k) {
                Some(_) => {}
                None => match host.subscribe(&format!("{p}/**")) {
                    Ok(id) => {
                        self.subs.insert(k.clone(), id);
                        self.sub_owner.insert(id.0, k);
                    }
                    Err(e) => {
                        host.log(
                            Level::Warn,
                            &format!("uplink {name}: subscribe {p}: {}", e.msg),
                        );
                        if let Some(up) = self.ups.get_mut(name) {
                            up.error = format!("subscribe {p}: {}", e.msg);
                        }
                    }
                },
            }
        }
    }

    fn unsubscribe_all(&mut self, host: &mut dyn Host, name: &str, select: &[String]) {
        for p in select {
            if let Some(id) = self.subs.remove(&(name.to_owned(), p.clone())) {
                host.unsubscribe(id);
                self.sub_owner.remove(&id.0);
            }
        }
    }

    fn show_stats(&mut self, host: &mut dyn Host, now: u64) {
        let connected = self
            .ups
            .values()
            .filter(|u| u.state == State::Connected)
            .count() as u64;
        let published: u64 =
            self.ups.values().map(|u| u.published).sum::<u64>() + self.total_published;
        let dropped: u64 = self.ups.values().map(|u| u.dropped).sum::<u64>() + self.total_dropped;
        for (name, v) in [
            ("upstreams", self.ups.len() as u64),
            ("connected", connected),
            ("published", published),
            ("dropped", dropped),
        ] {
            if self.stats_shown.get(name) != Some(&v) {
                self.stats_shown.insert(name, v);
                host.update(
                    &tree::stat(name),
                    Sample {
                        v: Value::UInt(v),
                        q: Quality::Good,
                        t: now,
                    },
                );
            }
        }
    }

    fn add(
        &mut self,
        host: &mut dyn Host,
        def: Def,
        rights: Option<Rights>,
    ) -> Result<(), AppError> {
        if self.ups.contains_key(&def.name) {
            return Err(invalid(format!("name: {} exists", def.name)));
        }
        if self.ups.len() >= MAX_UPSTREAMS {
            return Err(AppError::new(
                Status::ResourceExhausted,
                format!("at most {MAX_UPSTREAMS} upstreams"),
            ));
        }
        if !def.from_config {
            if let Some(r) = &rights {
                store::put_rights(host, &def.name, r)?;
            }
            store::put_def(host, &def)?;
            let names: Vec<String> = self
                .ups
                .values()
                .filter(|u| !u.def.from_config)
                .map(|u| u.def.name.clone())
                .chain([def.name.clone()])
                .collect();
            store::put_index(host, &names)?;
        }
        let name = def.name.clone();
        let up = Up::new(def, rights);
        self.declare(host, &up);
        self.ups.insert(name.clone(), up);
        self.subscribe_all(host, &name);
        let now = host.now_us();
        if let Some(up) = self.ups.get_mut(&name) {
            up.show(host, now);
        }
        self.arm(host, &name);
        Ok(())
    }

    fn remove(&mut self, host: &mut dyn Host, name: &str) -> Result<(), AppError> {
        let Some(mut up) = self.ups.remove(name) else {
            return Err(AppError::new(Status::NotFound, name));
        };
        if up.def.from_config {
            self.ups.insert(name.to_owned(), up);
            return Err(AppError::new(
                Status::NotSupported,
                "configured in wyrmd.json5: removed there",
            ));
        }
        if let Some(t) = up.timer.take() {
            host.cancel_timer(t);
            self.timers.remove(&t.0);
        }
        up.close(host);
        self.total_published += up.published;
        self.total_dropped += up.dropped;
        self.unsubscribe_all(host, name, &up.def.select);
        host.remove_node(name);
        store::delete(host, name);
        let names: Vec<String> = self
            .ups
            .values()
            .filter(|u| !u.def.from_config)
            .map(|u| u.def.name.clone())
            .collect();
        store::put_index(host, &names)?;
        Ok(())
    }

    /// The form of an Edit: the stored fields with the given ones over them.
    fn edited(&self, name: &str, args: &Args) -> Result<Def, AppError> {
        let up = self
            .ups
            .get(name)
            .ok_or_else(|| AppError::new(Status::NotFound, name))?;
        let Value::Map(mut m) = up.def.to_value() else {
            unreachable!()
        };
        for k in ["name", "kind", "from_config"] {
            m.remove(k);
        }
        for (k, v) in args {
            match v {
                Value::Null => {
                    m.remove(k);
                }
                Value::Str(s) if s.is_empty() && k != "select" => {
                    m.remove(k);
                }
                v => {
                    m.insert(k.clone(), v.clone());
                }
            }
        }
        Def::parse(
            up.def.kind,
            name,
            &m,
            self.site.as_deref(),
            self.net.as_deref(),
            false,
        )
        .map_err(invalid)
    }
}

impl App for Uplink {
    const NAME: &'static str = "uplink";
    const VERSION: &'static str = env!("CARGO_PKG_VERSION");

    fn start(host: &mut dyn Host, config: Value) -> Result<Self, AppError> {
        let Params {
            site,
            own,
            net,
            upstreams: configured,
        } = params_of(config)?;
        // the link root belongs to the host; the actions go on it
        for kind in Kind::ALL {
            let (name, a) = tree::add_action(kind);
            host.declare_action("", &name, a);
        }
        host.declare_node(tree::STATS, wyrm_core::NodeMeta::folder());
        for n in tree::STAT_NAMES {
            host.declare_node(
                &tree::stat(n),
                wyrm_core::NodeMeta::leaf(wyrm_core::TypeCode::Number),
            );
        }
        let mut app = Uplink {
            site,
            own,
            net,
            ups: BTreeMap::new(),
            timers: HashMap::new(),
            subs: BTreeMap::new(),
            sub_owner: HashMap::new(),
            total_published: 0,
            total_dropped: 0,
            stats_shown: BTreeMap::new(),
        };
        // from wyrmd.json5 first: a name there wins over a stored one
        for v in configured {
            match Def::from_value(&v, app.site.as_deref()).and_then(|mut d| {
                d.from_config = true;
                if let Some(net) = app.net.as_deref() {
                    platform::check_net(net, &d.endpoint())?;
                }
                Ok(d)
            }) {
                Ok(d) => {
                    if let Err(e) = app.add(host, d, None) {
                        host.log(Level::Error, &format!("uplink.upstreams: {}", e.msg));
                    }
                }
                Err(e) => host.log(Level::Error, &format!("uplink.upstreams: {e}")),
            }
        }
        let index = match store::load_index(host) {
            Ok(i) => i,
            Err(e) => {
                host.log(Level::Error, &format!("store index unreadable: {e}"));
                Vec::new()
            }
        };
        for name in index {
            if app.ups.contains_key(&name) {
                host.log(
                    Level::Warn,
                    &format!("uplink {name}: the stored one is hidden by wyrmd.json5"),
                );
                continue;
            }
            match store::load_def(host, &name, app.site.as_deref()) {
                Ok(d) => {
                    let rights = store::load_rights(host, &name);
                    let none = rights.is_none();
                    if let Err(e) = app.add(host, d, rights) {
                        host.log(Level::Error, &format!("uplink {name}: {}", e.msg));
                    } else if none {
                        // kept before its author's rights were: it sends nothing until an Edit
                        let msg = "no author rights kept: Edit it";
                        host.log(Level::Warn, &format!("uplink {name}: {msg}"));
                        if let Some(up) = app.ups.get_mut(&name) {
                            up.close(host);
                            up.state = State::Failed;
                            up.error = msg.into();
                            let now = host.now_us();
                            up.show(host, now);
                        }
                    }
                }
                Err(e) => host.log(Level::Error, &format!("uplink {name}: {e}")),
            }
        }
        let now = host.now_us();
        app.show_stats(host, now);
        Ok(app)
    }

    fn on_set(
        &mut self,
        host: &mut dyn Host,
        path: &str,
        value: Value,
        _who: &Who,
    ) -> Result<(), AppError> {
        let Some(name) = path.strip_suffix("/enabled") else {
            return Err(AppError::new(Status::NotSupported, path));
        };
        let Value::Bool(on) = value else {
            return Err(invalid("enabled: true or false"));
        };
        let up = self
            .ups
            .get_mut(name)
            .ok_or_else(|| AppError::new(Status::NotFound, name))?;
        if up.def.from_config {
            return Err(AppError::new(
                Status::NotSupported,
                "configured in wyrmd.json5",
            ));
        }
        up.def.enabled = on;
        store::put_def(host, &up.def)?;
        up.restart(host);
        let now = host.now_us();
        up.show(host, now);
        self.arm(host, name);
        self.show_stats(host, now);
        Ok(())
    }

    fn on_invoke(
        &mut self,
        host: &mut dyn Host,
        path: &str,
        action: &str,
        args: Value,
        who: &Who,
    ) -> Result<Value, AppError> {
        let m = args_of(args)?;
        let now = host.now_us();
        if path.is_empty() {
            let kind = action
                .strip_prefix("add_")
                .and_then(Kind::from_name)
                .ok_or_else(|| AppError::new(Status::NotSupported, action))?;
            let name = match m.get("name") {
                Some(Value::Str(s)) if !s.trim().is_empty() => s.trim().to_owned(),
                _ => return Err(invalid("name: required")),
            };
            let mut fields = m.clone();
            fields.remove("name");
            let def = Def::parse(
                kind,
                &name,
                &fields,
                self.site.as_deref(),
                self.net.as_deref(),
                false,
            )
            .map_err(invalid)?;
            let rights = author_rights(who, &def.select)?;
            self.add(host, def, Some(rights))?;
            self.show_stats(host, now);
            return Ok(Value::Null);
        }
        let name = path.to_owned();
        if !self.ups.contains_key(&name) {
            return Err(AppError::new(Status::NotFound, path));
        }
        match action {
            "set_password" => {
                let pw = match m.get("password") {
                    Some(Value::Str(s)) => s.clone(),
                    None | Some(Value::Null) => String::new(),
                    Some(_) => return Err(invalid("password: text")),
                };
                if pw.is_empty() {
                    host.store_delete(&store::secret_key(&name));
                } else {
                    host.store_put(&store::secret_key(&name), pw.as_bytes())?;
                }
                let up = self.ups.get_mut(&name).unwrap_or_else(|| unreachable!());
                up.restart(host);
                up.show(host, now);
                self.arm(host, &name);
                Ok(Value::Null)
            }
            "test_connection" => {
                let site = self.site.clone();
                let up = self.ups.get_mut(&name).unwrap_or_else(|| unreachable!());
                let (ok, message) = match up.test(host, now, site.as_deref()) {
                    Ok(m) => (true, m),
                    Err(m) => (false, m),
                };
                Ok(Value::Map(BTreeMap::from([
                    ("success".to_owned(), Value::Bool(ok)),
                    ("message".to_owned(), Value::Str(message)),
                ])))
            }
            "edit" => {
                if self.ups[&name].def.from_config {
                    return Err(AppError::new(
                        Status::NotSupported,
                        "configured in wyrmd.json5",
                    ));
                }
                let def = self.edited(&name, &m)?;
                // the editor's rights from now on: they must cover the new `select`
                let rights = author_rights(who, &def.select)?;
                let old = &self.ups[&name].def;
                let old_select = old.select.clone();
                // a secret goes only where it was set for: a new endpoint, TLS setting or CA
                // drops it (Set Password again), so an edit cannot send it elsewhere
                let moved = old.endpoint() != def.endpoint()
                    || old.insecure_plaintext != def.insecure_plaintext
                    || old.ca_pem != def.ca_pem;
                store::put_rights(host, &name, &rights)?;
                store::put_def(host, &def)?;
                if moved {
                    host.store_delete(&store::secret_key(&name));
                }
                let up = self.ups.get_mut(&name).unwrap_or_else(|| unreachable!());
                up.def = def;
                up.rights = Some(rights);
                up.readable.clear();
                up.sp.known.clear();
                up.held.clear();
                up.last_sent.clear();
                up.restart(host);
                self.declare(host, &self.ups[&name]);
                // subscribed again even with the same `select`: the current values come with
                // the new subscriptions, and the edit cleared what the upstream had sent
                self.unsubscribe_all(host, &name, &old_select);
                self.subscribe_all(host, &name);
                let up = self.ups.get_mut(&name).unwrap_or_else(|| unreachable!());
                up.show(host, now);
                self.arm(host, &name);
                Ok(Value::Null)
            }
            "remove" => {
                self.remove(host, &name)?;
                self.show_stats(host, now);
                Ok(Value::Null)
            }
            _ => Err(AppError::new(Status::NotSupported, action)),
        }
    }

    fn on_timer(&mut self, host: &mut dyn Host, timer: TimerId) {
        let Some(name) = self.timers.remove(&timer.0) else {
            return;
        };
        let now = host.now_us();
        let site = self.site.clone();
        let Some(up) = self.ups.get_mut(&name) else {
            return;
        };
        if up.timer != Some(timer) {
            return;
        }
        up.timer = None;
        up.tick(host, now, site.as_deref());
        up.show(host, now);
        self.arm(host, &name);
        self.show_stats(host, now);
    }

    fn on_value(&mut self, host: &mut dyn Host, sub: SubId, key: &str, sample: Sample) {
        let Some((name, _)) = self.sub_owner.get(&sub.0) else {
            return;
        };
        if let Some(own) = &self.own {
            if key == own || key.starts_with(&format!("{own}/")) {
                return;
            }
        }
        let now = host.now_us();
        if let Some(up) = self.ups.get_mut(name) {
            if up.may_send(key) {
                up.take(now, key, sample, self.site.as_deref());
            }
        }
    }

    fn on_reply(&mut self, _host: &mut dyn Host, _req: ReqId, _result: Result<Value, AppError>) {}

    fn stop(&mut self, host: &mut dyn Host) {
        for up in self.ups.values_mut() {
            up.close(host);
        }
    }
}

// Only on wasm32: natively the exports would be bare global symbols.
#[cfg(all(feature = "wasm", target_arch = "wasm32"))]
wyrm_link_guest::export!(Uplink);
