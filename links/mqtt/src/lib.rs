//! MQTT connector on the driver framework (ADR 0004).
//!
//! Tree: `<conn>/<device>/<point>`; kinds [`Conn`] (one broker client) →
//! [`Device`] (`plain` topics or one Sparkplug B edge node/device) →
//! [`Point`] (a topic or a Sparkplug metric).
//!
//! MQTT pushes and the framework polls, so a background task drives the
//! rumqttc event loop and caches the last payload per topic (and the
//! Sparkplug state); `poll` reads that cache at `poll_s`. Topics are
//! subscribed on the first poll or ping that needs them. The event-loop
//! task stops at its first error and the framework reconnects with its own
//! backoff: broker loss is a transport failure (connection `failed`, points
//! `bad/disconnected`). A Sparkplug NDEATH/DDEATH is a device miss
//! (`uncertain/stale`, then `bad/comm_fail`). BIRTH certificates are not
//! retained, so a new subscription to an edge node sends a rebirth request
//! (NCMD `Node Control/Rebirth`) when the device has `rebirth` on.
//!
//! Writes publish to the point's `cmd_topic` (plain) or as NCMD/DCMD
//! (Sparkplug); there is no optimistic update — the tree shows what the
//! device reports back on its state topic.
//!
//! Credentials, as in DSA, come with the connection: `password` and the TLS
//! client key `key_pem` are secret parameters of `add_connection`/`edit`.
//! The framework keeps them sealed in the link's `data_dir` and never shows
//! them in `~meta`, `export` or replies; an `edit` that changes the
//! destination (`host`, `port`, `tls`, `ca_file`, `ca_pem`) drops them
//! unless it supplies them again. Alternatively `auth_ref` names a link
//! secret (`links/<id>/~act/set_secret`), bound to the destinations of the
//! install params. A password is sent in plaintext only to loopback.

#![forbid(unsafe_code)]

pub mod payload;
pub mod sparkplug;

use payload::{Format, Kind};
use prost::Message;
use rumqttc::{AsyncClient, Event, EventLoop, MqttOptions, Packet, QoS, TlsConfiguration};
use std::collections::{BTreeMap, HashMap, HashSet};
use std::net::IpAddr;
use std::sync::{Arc, Mutex, MutexGuard};
use std::time::{Duration, Instant};
use tokio::task::JoinHandle;
use tracing::debug;
use wyrm_core::meta::Writable;
use wyrm_core::{NodeMeta, TypeCode, Value};
use wyrm_link_sdk::driver::params::{field, ParamSpec};
// Traits (type namespace) beside the derive macro of the same name.
use wyrm_link_sdk::driver::{Driver, DriverError, Framework, ParamEnum, Params, PointId, Tree};
use wyrm_link_sdk::{Caller, Link, LinkCtx, LinkError, ParamEnum, ReplySink, Secret, SecretStore};

/// Incoming and outgoing MQTT packet limit.
const MAX_PACKET: usize = 256 * 1024;

tokio::task_local! {
    /// The link's secrets while connection params are parsed (see [`Mqtt`]).
    static SECRETS: SecretStore;
    /// Where each secret may be sent (see [`Bindings`]).
    static BINDINGS: Bindings;
}

/// Where a password goes: host, port, tls, CA file.
type Dest = (String, u16, bool, String);

/// Each `auth_ref` is bound to the destinations of the connections that
/// use it in the bootstrap tree (`~def`, set by the admin at install).
/// Connections added or edited at runtime (`config` on the link's tree,
/// a lower bar) may use a secret only for one of those destinations, so
/// a tree edit cannot redirect the password to another host.
#[derive(Clone, Default)]
struct Bindings {
    /// `true` while the bootstrap tree is parsed: record instead of check.
    recording: bool,
    map: Arc<Mutex<HashMap<String, HashSet<Dest>>>>,
}

impl Bindings {
    fn admit(&self, auth_ref: &str, dest: Dest) -> wyrm_link_sdk::Result<()> {
        let mut m = self.map.lock().unwrap_or_else(|p| p.into_inner());
        if self.recording {
            m.entry(auth_ref.to_owned()).or_default().insert(dest);
            return Ok(());
        }
        if m.get(auth_ref).is_some_and(|d| d.contains(&dest)) {
            Ok(())
        } else {
            Err(bad(
                "auth_ref",
                "this secret is bound to the destinations in the link's install \
                 params; change host/port/tls/ca_file there",
            ))
        }
    }
}

fn bad(name: &str, what: impl std::fmt::Display) -> LinkError {
    LinkError::invalid_parameter(format!("{name}: {what}"))
}

/// A topic name for publish or an exact subscription: no wildcards.
fn check_topic(name: &str, t: &str) -> wyrm_link_sdk::Result<()> {
    if t.is_empty() || t.len() > 1024 || t.contains(['+', '#', '\0']) {
        return Err(bad(name, "a topic without wildcards, 1..1024 bytes"));
    }
    Ok(())
}

/// A Sparkplug id (group, edge node, device): one topic level.
fn check_level(name: &str, s: &str) -> wyrm_link_sdk::Result<()> {
    if s.contains(['/', '+', '#', '\0']) {
        return Err(bad(name, "must not contain / + #"));
    }
    Ok(())
}

fn is_loopback(host: &str) -> bool {
    host.eq_ignore_ascii_case("localhost") || host.parse::<IpAddr>().is_ok_and(|a| a.is_loopback())
}

// ---------- parameters ----------

/// One broker connection.
#[derive(Debug, Clone)]
pub struct Conn {
    pub host: String,
    pub port: u16,
    /// Empty: `wyrm-<random>` on each connect.
    pub client_id: String,
    pub keepalive_s: u16,
    /// Bound on connect (CONNACK), subscribe and publish.
    pub timeout_ms: u32,
    pub tls: bool,
    /// PEM file with the CA certificates; empty = system roots.
    pub ca_file: String,
    /// PEM CA certificates (instead of `ca_file`); empty = `ca_file` or
    /// system roots.
    pub ca_pem: String,
    /// PEM client certificate chain for mutual TLS; empty = none.
    pub cert_pem: String,
    /// PEM private key of `cert_pem` (secret parameter).
    key_pem: Secret,
    pub username: String,
    /// Name of the link secret with the broker password; empty = none.
    pub auth_ref: String,
    /// The `password` parameter (secret), or resolved from `auth_ref`.
    password: Option<Secret>,
    /// `password` was given as a parameter (kept in the sealed tree).
    password_param: bool,
}

impl PartialEq for Conn {
    fn eq(&self, o: &Self) -> bool {
        self.to_map() == o.to_map()
            && self.password.as_ref().map(Secret::expose) == o.password.as_ref().map(Secret::expose)
            && self.key_pem.expose() == o.key_pem.expose()
    }
}

fn resolve_secret(name: &str) -> wyrm_link_sdk::Result<Secret> {
    match SECRETS.try_with(|s| s.get(name).cloned()) {
        Ok(Some(s)) => Ok(s),
        Ok(None) => Err(bad(
            "auth_ref",
            format!("link secret {name:?} is not set (links/<id>/~act/set_secret)"),
        )),
        Err(_) => Err(bad("auth_ref", "no link secrets in this context")),
    }
}

impl Params for Conn {
    fn schema() -> Vec<ParamSpec> {
        vec![
            ParamSpec::new("host", TypeCode::String).dest(),
            ParamSpec::new("port", TypeCode::Number)
                .default(1883u64)
                .bounds(1.0, 65535.0)
                .dest(),
            ParamSpec::new("client_id", TypeCode::String)
                .default("")
                .desc("empty: wyrm-<random> per connect"),
            ParamSpec::new("keepalive_s", TypeCode::Number)
                .default(30u64)
                .bounds(5.0, 3600.0),
            ParamSpec::new("timeout_ms", TypeCode::Number)
                .default(3000u64)
                .bounds(100.0, 60_000.0),
            ParamSpec::new("tls", TypeCode::Bool).default(false).dest(),
            ParamSpec::new("ca_file", TypeCode::String)
                .default("")
                .desc("PEM CA file for tls; empty = system roots")
                .dest(),
            ParamSpec::new("ca_pem", TypeCode::String)
                .default("")
                .desc("PEM CA certificates for tls (instead of ca_file)")
                .dest(),
            ParamSpec::new("cert_pem", TypeCode::String)
                .default("")
                .desc("PEM client certificate for mutual TLS"),
            ParamSpec::new("key_pem", TypeCode::String)
                .default("")
                .secret()
                .desc("PEM private key of cert_pem"),
            ParamSpec::new("username", TypeCode::String).default(""),
            ParamSpec::new("password", TypeCode::String)
                .default("")
                .secret()
                .desc("broker password (kept sealed by the link)"),
            ParamSpec::new("auth_ref", TypeCode::String)
                .default("")
                .desc("name of the link secret that holds the broker password"),
        ]
    }

    fn from_map(m: &BTreeMap<String, Value>) -> wyrm_link_sdk::Result<Self> {
        let mut c = Conn {
            host: field::string(m, "host")?,
            port: field::int(m, "port")?,
            client_id: field::string(m, "client_id")?,
            keepalive_s: field::int(m, "keepalive_s")?,
            timeout_ms: field::int(m, "timeout_ms")?,
            tls: field::bool(m, "tls")?,
            ca_file: field::string(m, "ca_file")?,
            ca_pem: field::string(m, "ca_pem")?,
            cert_pem: field::string(m, "cert_pem")?,
            key_pem: Secret::new(field::string(m, "key_pem")?),
            username: field::string(m, "username")?,
            auth_ref: field::string(m, "auth_ref")?,
            password: None,
            password_param: false,
        };
        let password = field::string(m, "password")?;
        if c.host.is_empty() {
            return Err(bad("host", "required"));
        }
        if c.client_id.len() > 64 {
            return Err(bad("client_id", "at most 64 bytes"));
        }
        if !c.tls && !c.ca_file.is_empty() {
            return Err(bad("ca_file", "only with tls"));
        }
        if !c.tls && (!c.ca_pem.is_empty() || !c.cert_pem.is_empty()) {
            return Err(bad("ca_pem", "ca_pem and cert_pem only with tls"));
        }
        if !c.ca_pem.is_empty() && !c.ca_file.is_empty() {
            return Err(bad("ca_pem", "give ca_pem or ca_file, not both"));
        }
        if c.cert_pem.is_empty() != c.key_pem.expose().is_empty() {
            return Err(bad("cert_pem", "cert_pem and key_pem go together"));
        }
        if !c.ca_pem.is_empty() || !c.cert_pem.is_empty() {
            // Parse now: a bad PEM is an edit error, not a connect failure.
            tls_config(&c).map_err(|e| bad("tls", e))?;
        }
        if !password.is_empty() {
            if !c.auth_ref.is_empty() {
                return Err(bad("password", "give password or auth_ref, not both"));
            }
            if c.username.is_empty() {
                return Err(bad("username", "required with password"));
            }
            if !c.tls && !is_loopback(&c.host) {
                return Err(bad(
                    "tls",
                    "a password is never sent in plaintext to a non-loopback host",
                ));
            }
            c.password = Some(Secret::new(password));
            c.password_param = true;
        }
        if !c.auth_ref.is_empty() {
            if c.auth_ref.len() > 64
                || !c
                    .auth_ref
                    .bytes()
                    .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
            {
                return Err(bad("auth_ref", "[A-Za-z0-9_-]{1,64}"));
            }
            if c.username.is_empty() {
                return Err(bad("username", "required with auth_ref"));
            }
            if !c.tls && !is_loopback(&c.host) {
                return Err(bad(
                    "tls",
                    "a password is never sent in plaintext to a non-loopback host",
                ));
            }
            let dest = (c.host.clone(), c.port, c.tls, c.ca_file.clone());
            match BINDINGS.try_with(|b| b.admit(&c.auth_ref, dest)) {
                Ok(r) => r?,
                Err(_) => return Err(bad("auth_ref", "no secret bindings in this context")),
            }
            let s = resolve_secret(&c.auth_ref)?;
            if s.expose_str().is_none() {
                return Err(bad("auth_ref", "the password must be UTF-8"));
            }
            c.password = Some(s);
        }
        Ok(c)
    }

    fn to_map(&self) -> BTreeMap<String, Value> {
        BTreeMap::from([
            ("host".into(), Value::Str(self.host.clone())),
            ("port".into(), Value::UInt(self.port.into())),
            ("client_id".into(), Value::Str(self.client_id.clone())),
            ("keepalive_s".into(), Value::UInt(self.keepalive_s.into())),
            ("timeout_ms".into(), Value::UInt(self.timeout_ms.into())),
            ("tls".into(), Value::Bool(self.tls)),
            ("ca_file".into(), Value::Str(self.ca_file.clone())),
            ("ca_pem".into(), Value::Str(self.ca_pem.clone())),
            ("cert_pem".into(), Value::Str(self.cert_pem.clone())),
            (
                "key_pem".into(),
                Value::Str(self.key_pem.expose_str().unwrap_or_default().to_owned()),
            ),
            ("username".into(), Value::Str(self.username.clone())),
            (
                "password".into(),
                Value::Str(match (&self.password, self.password_param) {
                    (Some(p), true) => p.expose_str().unwrap_or_default().to_owned(),
                    _ => String::new(),
                }),
            ),
            ("auth_ref".into(), Value::Str(self.auth_ref.clone())),
        ])
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, ParamEnum)]
pub enum DevKind {
    /// Points are topics.
    Plain,
    /// Points are metrics of one Sparkplug B edge node or device.
    Sparkplug,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Device {
    pub kind: DevKind,
    /// Sparkplug group id.
    pub group: String,
    /// Sparkplug edge node id.
    pub edge: String,
    /// Sparkplug device id; empty = the edge node's own metrics.
    pub device: String,
    /// Ask the edge node to rebirth when DATA cannot be mapped.
    pub rebirth: bool,
    pub ping_s: f64,
}

impl Params for Device {
    fn schema() -> Vec<ParamSpec> {
        vec![
            ParamSpec::new("kind", TypeCode::Enum)
                .one_of(DevKind::NAMES)
                .default("plain"),
            ParamSpec::new("group", TypeCode::String).default(""),
            ParamSpec::new("edge", TypeCode::String).default(""),
            ParamSpec::new("device", TypeCode::String)
                .default("")
                .desc("empty: the edge node's own metrics"),
            ParamSpec::new("rebirth", TypeCode::Bool).default(true),
            ParamSpec::new("ping_s", TypeCode::Number)
                .default(1.0)
                .bounds(0.1, 3600.0),
        ]
    }

    fn from_map(m: &BTreeMap<String, Value>) -> wyrm_link_sdk::Result<Self> {
        let d = Device {
            kind: field::enumv(m, "kind")?,
            group: field::string(m, "group")?,
            edge: field::string(m, "edge")?,
            device: field::string(m, "device")?,
            rebirth: field::bool(m, "rebirth")?,
            ping_s: field::f64(m, "ping_s")?,
        };
        match d.kind {
            DevKind::Sparkplug => {
                for (n, v) in [("group", &d.group), ("edge", &d.edge)] {
                    if v.is_empty() {
                        return Err(bad(n, "required for sparkplug"));
                    }
                }
                for (n, v) in [
                    ("group", &d.group),
                    ("edge", &d.edge),
                    ("device", &d.device),
                ] {
                    check_level(n, v)?;
                }
            }
            DevKind::Plain => {
                if !(d.group.is_empty() && d.edge.is_empty() && d.device.is_empty()) {
                    return Err(bad("kind", "group/edge/device are for sparkplug"));
                }
            }
        }
        Ok(d)
    }

    fn to_map(&self) -> BTreeMap<String, Value> {
        BTreeMap::from([
            ("kind".into(), Value::Str(self.kind.name().into())),
            ("group".into(), Value::Str(self.group.clone())),
            ("edge".into(), Value::Str(self.edge.clone())),
            ("device".into(), Value::Str(self.device.clone())),
            ("rebirth".into(), Value::Bool(self.rebirth)),
            ("ping_s".into(), Value::Float(self.ping_s)),
        ])
    }
}

/// One point: a `topic` (plain device) or a `metric` (Sparkplug device).
#[derive(Debug, Clone, PartialEq)]
pub struct Point {
    pub topic: String,
    pub metric: String,
    pub format: Format,
    /// RFC 6901 pointer into a JSON payload; empty = the whole document.
    pub pointer: String,
    pub kind: Kind,
    /// Plain points: where writes are published.
    pub cmd_topic: String,
    pub writable: bool,
    pub qos: u8,
    pub retain: bool,
    /// How often the last received value is published into the tree.
    pub poll_s: f64,
    pub unit: String,
}

fn qos(q: u8) -> QoS {
    match q {
        0 => QoS::AtMostOnce,
        1 => QoS::AtLeastOnce,
        _ => QoS::ExactlyOnce,
    }
}

impl Params for Point {
    fn schema() -> Vec<ParamSpec> {
        vec![
            ParamSpec::new("topic", TypeCode::String)
                .default("")
                .desc("state topic (plain devices)"),
            ParamSpec::new("metric", TypeCode::String)
                .default("")
                .desc("metric name (sparkplug devices)"),
            ParamSpec::new("format", TypeCode::Enum)
                .one_of(Format::NAMES)
                .default("raw"),
            ParamSpec::new("pointer", TypeCode::String)
                .default("")
                .desc("JSON pointer, e.g. /data/temp"),
            ParamSpec::new("kind", TypeCode::Enum)
                .one_of(Kind::NAMES)
                .default("number"),
            ParamSpec::new("cmd_topic", TypeCode::String)
                .default("")
                .desc("topic for writes (plain devices)"),
            ParamSpec::new("writable", TypeCode::Bool).default(false),
            ParamSpec::new("qos", TypeCode::Number)
                .default(1u64)
                .bounds(0.0, 2.0),
            ParamSpec::new("retain", TypeCode::Bool).default(false),
            ParamSpec::new("poll_s", TypeCode::Number)
                .default(0.5)
                .bounds(0.01, 86_400.0),
            ParamSpec::new("unit", TypeCode::String).default(""),
        ]
    }

    fn from_map(m: &BTreeMap<String, Value>) -> wyrm_link_sdk::Result<Self> {
        let p = Point {
            topic: field::string(m, "topic")?,
            metric: field::string(m, "metric")?,
            format: field::enumv(m, "format")?,
            pointer: field::string(m, "pointer")?,
            kind: field::enumv(m, "kind")?,
            cmd_topic: field::string(m, "cmd_topic")?,
            writable: field::bool(m, "writable")?,
            qos: field::int(m, "qos")?,
            retain: field::bool(m, "retain")?,
            poll_s: field::f64(m, "poll_s")?,
            unit: field::string(m, "unit")?,
        };
        match (p.topic.is_empty(), p.metric.is_empty()) {
            (false, true) => {
                check_topic("topic", &p.topic)?;
                if p.writable {
                    check_topic("cmd_topic", &p.cmd_topic)?;
                }
            }
            (true, false) => {
                if !p.cmd_topic.is_empty() || p.format != Format::Raw || !p.pointer.is_empty() {
                    return Err(bad(
                        "metric",
                        "cmd_topic, format and pointer are for topic points",
                    ));
                }
            }
            _ => return Err(bad("topic", "set exactly one of topic or metric")),
        }
        if !p.pointer.is_empty() {
            if p.format != Format::Json {
                return Err(bad("pointer", "only with format json"));
            }
            if !p.pointer.starts_with('/') {
                return Err(bad("pointer", "must start with /"));
            }
        }
        Ok(p)
    }

    fn to_map(&self) -> BTreeMap<String, Value> {
        BTreeMap::from([
            ("topic".into(), Value::Str(self.topic.clone())),
            ("metric".into(), Value::Str(self.metric.clone())),
            ("format".into(), Value::Str(self.format.name().into())),
            ("pointer".into(), Value::Str(self.pointer.clone())),
            ("kind".into(), Value::Str(self.kind.name().into())),
            ("cmd_topic".into(), Value::Str(self.cmd_topic.clone())),
            ("writable".into(), Value::Bool(self.writable)),
            ("qos".into(), Value::UInt(self.qos.into())),
            ("retain".into(), Value::Bool(self.retain)),
            ("poll_s".into(), Value::Float(self.poll_s)),
            ("unit".into(), Value::Str(self.unit.clone())),
        ])
    }
}

// ---------- transport ----------

#[derive(Default)]
struct Shared {
    /// Set once by the event-loop task when the connection broke.
    error: Option<String>,
    /// Exact plain topics this connection subscribed.
    plain: HashSet<String>,
    /// Last payload per plain topic.
    last: HashMap<String, Vec<u8>>,
    sp: sparkplug::State,
    /// Edge nodes `(group, edge)` that may be asked to rebirth.
    rebirth: HashSet<(String, String)>,
}

fn lock(s: &Mutex<Shared>) -> MutexGuard<'_, Shared> {
    s.lock().unwrap_or_else(|p| p.into_inner())
}

fn now_ms() -> u64 {
    wyrm_link_sdk::now_us() / 1000
}

pub struct Transport {
    client: AsyncClient,
    shared: Arc<Mutex<Shared>>,
    task: JoinHandle<()>,
    /// Filter → QoS of subscriptions sent on this connection.
    subscribed: HashMap<String, u8>,
    timeout: Duration,
}

impl Drop for Transport {
    fn drop(&mut self) {
        self.task.abort();
    }
}

impl Transport {
    fn check(&self) -> Result<(), DriverError> {
        match &lock(&self.shared).error {
            Some(e) => Err(DriverError::Transport(e.clone())),
            None => Ok(()),
        }
    }

    async fn subscribe(&mut self, filter: &str, q: u8) -> Result<(), DriverError> {
        if self.subscribed.get(filter).is_some_and(|have| *have >= q) {
            return Ok(());
        }
        match tokio::time::timeout(self.timeout, self.client.subscribe(filter, qos(q))).await {
            Err(_) => Err(DriverError::Device("subscribe timed out".into())),
            Ok(Err(e)) => Err(DriverError::Transport(e.to_string())),
            Ok(Ok(())) => {
                self.subscribed.insert(filter.to_owned(), q);
                Ok(())
            }
        }
    }

    async fn ensure_device(&mut self, dev: &Device) -> Result<(), DriverError> {
        if dev.kind != DevKind::Sparkplug {
            return Ok(());
        }
        if dev.rebirth {
            lock(&self.shared)
                .rebirth
                .insert((dev.group.clone(), dev.edge.clone()));
        }
        let filter = sparkplug::edge_filter(&dev.group, &dev.edge);
        let first = !self.subscribed.contains_key(&filter);
        self.subscribe(&filter, 1).await?;
        // BIRTH certificates are not retained: on a new subscription, ask
        // the edge node for them (sent after SUBSCRIBE on the same session).
        if first && dev.rebirth {
            lock(&self.shared)
                .sp
                .note_rebirth(&dev.group, &dev.edge, Instant::now());
            let req = sparkplug::rebirth_request(now_ms()).encode_to_vec();
            self.publish(
                sparkplug::cmd_topic(&dev.group, &dev.edge, ""),
                0,
                false,
                req,
            )
            .await?;
        }
        Ok(())
    }

    async fn publish(
        &self,
        topic: String,
        q: u8,
        retain: bool,
        body: Vec<u8>,
    ) -> Result<(), DriverError> {
        match tokio::time::timeout(
            self.timeout,
            self.client.publish(topic, qos(q), retain, body),
        )
        .await
        {
            Err(_) => Err(DriverError::Device("publish timed out".into())),
            Ok(Err(e)) => Err(DriverError::Transport(e.to_string())),
            Ok(Ok(())) => Ok(()),
        }
    }
}

fn on_publish(client: &AsyncClient, shared: &Mutex<Shared>, topic: &str, body: &[u8]) {
    let mut s = lock(shared);
    if s.plain.contains(topic) {
        s.last.insert(topic.to_owned(), body.to_vec());
    }
    let Some(t) = sparkplug::parse_topic(topic) else {
        return;
    };
    let p = match sparkplug::Payload::decode(body) {
        Ok(p) => p,
        Err(e) => {
            debug!(topic, "sparkplug payload not decoded: {e}");
            return;
        }
    };
    let wants = s.rebirth.contains(&(t.group.to_owned(), t.edge.to_owned()));
    if s.sp.apply(&t, &p, Instant::now()) && wants {
        drop(s);
        let req = sparkplug::rebirth_request(now_ms()).encode_to_vec();
        // Never await here: this task drives the event loop.
        let r = client.try_publish(
            sparkplug::cmd_topic(t.group, t.edge, ""),
            QoS::AtLeastOnce,
            false,
            req,
        );
        debug!(
            group = t.group,
            edge = t.edge,
            ok = r.is_ok(),
            "sparkplug rebirth requested"
        );
    }
}

/// Drive the event loop until its first error; then stop (no silent
/// reconnect: the framework reconnects with backoff).
async fn run_event_loop(mut el: EventLoop, client: AsyncClient, shared: Arc<Mutex<Shared>>) {
    loop {
        match el.poll().await {
            Ok(Event::Incoming(Packet::Publish(p))) => {
                on_publish(&client, &shared, &p.topic, &p.payload)
            }
            Ok(Event::Incoming(Packet::Disconnect)) => {
                lock(&shared).error = Some("broker disconnected".into());
                return;
            }
            Ok(_) => {}
            Err(e) => {
                lock(&shared).error = Some(e.to_string());
                return;
            }
        }
    }
}

fn tls_config(c: &Conn) -> Result<rustls::ClientConfig, DriverError> {
    use rustls_pki_types::pem::PemObject;
    use rustls_pki_types::{CertificateDer, PrivateKeyDer};
    let tls_err =
        |what: &str, e: &dyn std::fmt::Display| DriverError::Transport(format!("{what}: {e}"));
    let mut roots = rustls::RootCertStore::empty();
    let pem = if !c.ca_pem.is_empty() {
        Some(("ca_pem".to_owned(), c.ca_pem.as_bytes().to_vec()))
    } else if !c.ca_file.is_empty() {
        let what = format!("ca_file {}", c.ca_file);
        let b = std::fs::read(&c.ca_file).map_err(|e| tls_err(&what, &e))?;
        Some((what, b))
    } else {
        None
    };
    match pem {
        None => {
            let found = rustls_native_certs::load_native_certs();
            roots.add_parsable_certificates(found.certs);
        }
        Some((what, pem)) => {
            for cert in CertificateDer::pem_slice_iter(&pem) {
                let cert = cert.map_err(|e| tls_err(&what, &e))?;
                roots.add(cert).map_err(|e| tls_err(&what, &e))?;
            }
        }
    }
    if roots.is_empty() {
        return Err(DriverError::Transport("tls: no CA certificates".into()));
    }
    // ring only: never the process default provider (aws-lc is forbidden).
    let b = rustls::ClientConfig::builder_with_provider(Arc::new(
        rustls::crypto::ring::default_provider(),
    ))
    .with_safe_default_protocol_versions()
    .map_err(|e| tls_err("tls", &e))?
    .with_root_certificates(roots);
    if c.cert_pem.is_empty() {
        return Ok(b.with_no_client_auth());
    }
    let chain = CertificateDer::pem_slice_iter(c.cert_pem.as_bytes())
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| tls_err("cert_pem", &e))?;
    if chain.is_empty() {
        return Err(DriverError::Transport("cert_pem: no certificate".into()));
    }
    // Never echo the key's content in an error.
    let key = PrivateKeyDer::from_pem_slice(c.key_pem.expose())
        .map_err(|_| DriverError::Transport("key_pem: not a PEM private key".into()))?;
    b.with_client_auth_cert(chain, key)
        .map_err(|e| tls_err("cert_pem/key_pem", &e))
}

fn random_client_id() -> String {
    let n = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    let mut x = (n as u64) ^ 0x9E37_79B9_7F4A_7C15 ^ u64::from(std::process::id()).rotate_left(32);
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    format!("wyrm-{x:016x}")
}

// ---------- driver ----------

pub struct Plan {
    /// Exact plain topics with their QoS.
    topics: Vec<(String, u8)>,
    points: Vec<(PointId, Point)>,
}

pub struct MqttDriver;

impl Driver for MqttDriver {
    const NAME: &'static str = "mqtt";
    const VERSION: &'static str = env!("CARGO_PKG_VERSION");
    type Conn = Conn;
    type Dev = Device;
    type Point = Point;
    type Transport = Transport;
    type Plan = Plan;

    async fn open(c: &Conn) -> Result<Transport, DriverError> {
        let timeout = Duration::from_millis(c.timeout_ms.into());
        let id = if c.client_id.is_empty() {
            random_client_id()
        } else {
            c.client_id.clone()
        };
        let mut o = MqttOptions::new(id, c.host.clone(), c.port);
        o.set_keep_alive(Duration::from_secs(c.keepalive_s.into()))
            .set_clean_session(true)
            .set_max_packet_size(MAX_PACKET, MAX_PACKET);
        match &c.password {
            Some(pw) => {
                let pw = pw
                    .expose_str()
                    .ok_or_else(|| DriverError::Transport("password is not UTF-8".into()))?;
                o.set_credentials(c.username.clone(), pw);
            }
            None if !c.username.is_empty() => {
                o.set_credentials(c.username.clone(), "");
            }
            None => {}
        }
        if c.tls {
            let cfg = tls_config(c)?;
            o.set_transport(rumqttc::Transport::tls_with_config(
                TlsConfiguration::Rustls(Arc::new(cfg)),
            ));
        }
        let (client, mut el) = AsyncClient::new(o, 64);
        // Connected only after CONNACK: a refused login is an open failure.
        let connack = tokio::time::timeout(timeout, async {
            loop {
                match el.poll().await {
                    Ok(Event::Incoming(Packet::ConnAck(a))) => {
                        return if a.code == rumqttc::ConnectReturnCode::Success {
                            Ok(())
                        } else {
                            Err(format!("connection refused: {:?}", a.code))
                        };
                    }
                    Ok(_) => {}
                    Err(e) => return Err(e.to_string()),
                }
            }
        })
        .await;
        let target = format!("{}:{}", c.host, c.port);
        match connack {
            Err(_) => return Err(DriverError::Transport(format!("connect {target}: timeout"))),
            Ok(Err(e)) => return Err(DriverError::Transport(format!("connect {target}: {e}"))),
            Ok(Ok(())) => {}
        }
        let shared = Arc::new(Mutex::new(Shared::default()));
        let task = tokio::spawn(run_event_loop(el, client.clone(), shared.clone()));
        Ok(Transport {
            client,
            shared,
            task,
            subscribed: HashMap::new(),
            timeout,
        })
    }

    async fn ping(t: &mut Transport, dev: &Device) -> Result<(), DriverError> {
        t.check()?;
        t.ensure_device(dev).await?;
        if dev.kind == DevKind::Sparkplug {
            lock(&t.shared)
                .sp
                .alive(&dev.group, &dev.edge, &dev.device)
                .map_err(|e| DriverError::Device(e.into()))?;
        }
        Ok(())
    }

    fn plan(_dev: &Device, points: &[(PointId, Point)]) -> Plan {
        let mut topics: BTreeMap<String, u8> = BTreeMap::new();
        for (_, p) in points {
            if !p.topic.is_empty() {
                let q = topics.entry(p.topic.clone()).or_default();
                *q = (*q).max(p.qos);
            }
        }
        Plan {
            topics: topics.into_iter().collect(),
            points: points.to_vec(),
        }
    }

    async fn poll(
        t: &mut Transport,
        dev: &Device,
        plan: &Plan,
    ) -> Vec<(PointId, Result<Value, DriverError>)> {
        let first = plan
            .points
            .first()
            .map(|(id, _)| id.clone())
            .unwrap_or_default();
        if let Err(e) = t.check() {
            return vec![(first, Err(e))];
        }
        if let Err(e) = t.ensure_device(dev).await {
            return vec![(first, Err(e))];
        }
        if dev.kind == DevKind::Plain {
            for (topic, q) in &plan.topics {
                lock(&t.shared).plain.insert(topic.clone());
                if let Err(e) = t.subscribe(topic, *q).await {
                    return vec![(first, Err(e))];
                }
            }
        }
        let s = lock(&t.shared);
        let mut out = Vec::new();
        for (id, p) in &plan.points {
            let r = match (dev.kind, p.topic.is_empty()) {
                (DevKind::Plain, false) => match s.last.get(&p.topic) {
                    // Nothing received yet: no value, no error.
                    None => continue,
                    Some(body) => payload::decode(body, p.format, &p.pointer, p.kind)
                        .map_err(DriverError::Point),
                },
                (DevKind::Sparkplug, true) => {
                    match s.sp.alive(&dev.group, &dev.edge, &dev.device) {
                        Err(e) => Err(DriverError::Device(e.into())),
                        Ok(()) => match s.sp.value(&dev.group, &dev.edge, &dev.device, &p.metric) {
                            None => continue,
                            Some(v) => payload::coerce(v, p.kind).map_err(DriverError::Point),
                        },
                    }
                }
                (DevKind::Plain, true) => Err(DriverError::Point(
                    "metric points belong to sparkplug devices".into(),
                )),
                (DevKind::Sparkplug, false) => Err(DriverError::Point(
                    "topic points belong to plain devices".into(),
                )),
            };
            out.push((id.clone(), r));
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
        t.check()?;
        if !p.writable {
            return Err(DriverError::Point("point is not writable".into()));
        }
        match dev.kind {
            DevKind::Plain => {
                if p.topic.is_empty() {
                    return Err(DriverError::Point(
                        "metric points belong to sparkplug devices".into(),
                    ));
                }
                let body = payload::encode(v, p.format, &p.pointer).map_err(DriverError::Point)?;
                t.publish(p.cmd_topic.clone(), p.qos, p.retain, body).await
            }
            DevKind::Sparkplug => {
                if p.metric.is_empty() {
                    return Err(DriverError::Point(
                        "topic points belong to plain devices".into(),
                    ));
                }
                let dt = {
                    let s = lock(&t.shared);
                    s.sp.alive(&dev.group, &dev.edge, &dev.device)
                        .map_err(|e| DriverError::Device(e.into()))?;
                    s.sp.datatype(&dev.group, &dev.edge, &dev.device, &p.metric)
                };
                let cmd =
                    sparkplug::command(&p.metric, dt, v, now_ms()).map_err(DriverError::Point)?;
                // Sparkplug commands are QoS 0 and never retained.
                t.publish(
                    sparkplug::cmd_topic(&dev.group, &dev.edge, &dev.device),
                    0,
                    false,
                    cmd.encode_to_vec(),
                )
                .await
            }
        }
    }

    fn point_meta(p: &Point) -> NodeMeta {
        let mut m = NodeMeta::leaf(match p.kind {
            Kind::Number => TypeCode::Number,
            Kind::String => TypeCode::String,
            Kind::Bool => TypeCode::Bool,
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
        Some(Duration::from_secs_f64(dev.ping_s))
    }

    /// Bounds `open` (CONNACK) and each poll/ping/write; requests inside are
    /// bounded by `timeout_ms` too.
    fn io_timeout(conn: &Conn) -> Duration {
        Duration::from_millis(u64::from(conn.timeout_ms) * 2)
    }
}

// ---------- the link ----------

/// The `mqtt` link: [`Framework`] running [`MqttDriver`], with the link's
/// secrets in scope while connection params are parsed (start, `add_connection`,
/// `edit`), so `auth_ref` resolves without the password entering the tree.
pub struct Mqtt {
    inner: Framework<MqttDriver>,
    secrets: SecretStore,
    bindings: Bindings,
}

impl Link for Mqtt {
    const NAME: &'static str = MqttDriver::NAME;
    const VERSION: &'static str = MqttDriver::VERSION;
    type Config = Tree;

    async fn start(tree: Tree, ctx: LinkCtx) -> wyrm_link_sdk::Result<Self> {
        let secrets = ctx.secrets().clone();
        let recording = Bindings {
            recording: true,
            ..Default::default()
        };
        let inner = SECRETS
            .scope(
                secrets.clone(),
                BINDINGS.scope(
                    recording.clone(),
                    <Framework<MqttDriver> as Link>::start(tree, ctx),
                ),
            )
            .await?;
        let bindings = Bindings {
            recording: false,
            map: recording.map,
        };
        Ok(Self {
            inner,
            secrets,
            bindings,
        })
    }

    async fn on_set(
        &mut self,
        path: &str,
        value: Value,
        who: &Caller,
    ) -> wyrm_link_sdk::Result<()> {
        self.inner.on_set(path, value, who).await
    }

    async fn on_invoke(
        &mut self,
        path: &str,
        action: &str,
        args: Value,
        who: &Caller,
        out: ReplySink,
    ) -> wyrm_link_sdk::Result<()> {
        SECRETS
            .scope(
                self.secrets.clone(),
                BINDINGS.scope(
                    self.bindings.clone(),
                    self.inner.on_invoke(path, action, args, who, out),
                ),
            )
            .await
    }

    async fn stop(&mut self) {
        self.inner.stop().await
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

    #[test]
    fn point_rules() {
        let ok = Point::from_value(&map(&[("topic", "a/b".into())])).unwrap();
        assert_eq!(ok.qos, 1);
        assert_eq!(Point::from_value(&ok.to_value()).unwrap(), ok);
        for bad in [
            map(&[]),
            map(&[("topic", "a/+".into())]),
            map(&[("topic", "a".into()), ("metric", "m".into())]),
            map(&[("topic", "a".into()), ("writable", true.into())]),
            map(&[("topic", "a".into()), ("pointer", "/x".into())]),
            map(&[
                ("topic", "a".into()),
                ("format", "json".into()),
                ("pointer", "x".into()),
            ]),
            map(&[("metric", "m".into()), ("format", "json".into())]),
        ] {
            assert!(Point::from_value(&bad).is_err(), "{bad:?}");
        }
    }

    #[test]
    fn device_rules() {
        assert!(Device::from_value(&map(&[])).is_ok());
        assert!(Device::from_value(&map(&[("kind", "sparkplug".into())])).is_err());
        assert!(Device::from_value(&map(&[
            ("kind", "sparkplug".into()),
            ("group", "g".into()),
            ("edge", "e/x".into())
        ]))
        .is_err());
        assert!(Device::from_value(&map(&[("edge", "e".into())])).is_err());
    }

    #[tokio::test]
    async fn conn_secret_by_reference() {
        let args = map(&[
            ("host", "127.0.0.1".into()),
            ("username", "u".into()),
            ("auth_ref", "broker".into()),
        ]);
        // outside a link: no store
        assert!(Conn::from_value(&args).is_err());
        let store: SecretStore = [("broker", Secret::new("pw"))].into_iter().collect();
        let rec = Bindings {
            recording: true,
            ..Default::default()
        };
        let c = SECRETS
            .scope(
                store.clone(),
                BINDINGS.scope(rec.clone(), async { Conn::from_value(&args) }),
            )
            .await
            .unwrap();
        assert_eq!(c.password.as_ref().and_then(Secret::expose_str), Some("pw"));
        assert!(!format!("{c:?}").contains("pw\""));
        assert!(!c.public_map().values().any(|v| *v == Value::from("pw")));
        assert!(!c.to_map().values().any(|v| *v == Value::from("pw")));
        // missing secret, plaintext to a remote host
        let empty = SecretStore::default();
        assert!(SECRETS
            .scope(
                empty,
                BINDINGS.scope(rec.clone(), async { Conn::from_value(&args) }),
            )
            .await
            .is_err());
        let remote = map(&[
            ("host", "broker.example".into()),
            ("username", "u".into()),
            ("auth_ref", "broker".into()),
        ]);
        let e = SECRETS
            .scope(
                store.clone(),
                BINDINGS.scope(rec.clone(), async { Conn::from_value(&remote) }),
            )
            .await
            .unwrap_err();
        assert!(e.message.starts_with("tls:"), "{}", e.message);
        // at runtime the secret goes only where the install params sent it
        let runtime = Bindings {
            recording: false,
            map: rec.map,
        };
        let parse = |v: Value| {
            SECRETS.scope(
                store.clone(),
                BINDINGS.scope(runtime.clone(), async move { Conn::from_value(&v) }),
            )
        };
        assert!(parse(args.clone()).await.is_ok(), "bound destination");
        let moved = map(&[
            ("host", "127.0.0.1".into()),
            ("port", 1884u64.into()),
            ("username", "u".into()),
            ("auth_ref", "broker".into()),
        ]);
        let e = parse(moved).await.unwrap_err();
        assert!(e.message.contains("bound"), "{}", e.message);
    }

    #[test]
    fn tls_with_ring_provider() {
        // system roots may be empty in a sandbox; the builder must not panic
        let conn = |extra: &[(&str, Value)]| {
            let mut m = BTreeMap::from([
                ("host".to_owned(), Value::from("localhost")),
                ("tls".to_owned(), Value::Bool(true)),
            ]);
            m.extend(extra.iter().map(|(k, v)| ((*k).to_owned(), v.clone())));
            wyrm_link_sdk::driver::params::normalize(&Conn::schema(), &Value::Map(m))
                .and_then(|m| Conn::from_map(&m))
        };
        let _ = tls_config(&conn(&[]).unwrap());
        let missing = conn(&[("ca_file", "/nonexistent/ca.pem".into())]).unwrap();
        assert!(tls_config(&missing).is_err());
        // a client key's content never appears in an error
        let e = conn(&[
            ("ca_pem", "x".into()),
            ("cert_pem", "y".into()),
            ("key_pem", "very-private".into()),
        ])
        .unwrap_err();
        assert!(!e.message.contains("very-private"), "{}", e.message);
        assert!(
            conn(&[("cert_pem", "y".into())]).is_err(),
            "cert without key"
        );
    }
}
