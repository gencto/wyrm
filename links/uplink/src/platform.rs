//! What an upstream is: its kind, the fields each kind takes (one table that both the Add/Edit
//! forms and the validation use), the parsed [`Def`], and the pieces every kind shares (URL
//! parsing, JSON values, device and metric names from keys, the Azure SAS token).

use std::collections::BTreeMap;
use std::net::IpAddr;

use base64::Engine as _;
use hmac::{Hmac, Mac};
use sha2::Sha256;
use wyrm_core::{Quality, Sample, TypeCode, Value};
use wyrm_link_api::net::NetPolicy;

pub type Map = BTreeMap<String, Value>;

/// The platforms (ADR 0034).
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum Kind {
    /// Any MQTT broker, one topic per point (a Unified Namespace).
    Mqtt,
    /// Sparkplug B 3.0: the site as an edge node, links as devices.
    Sparkplug,
    /// ThingsBoard's gateway API over MQTT.
    ThingsBoard,
    /// Azure IoT Hub, a device with a SAS token over MQTT.
    Azure,
    /// AWS IoT Core over HTTPS, Signature V4.
    Aws,
}

impl Kind {
    pub const ALL: [Kind; 5] = [
        Kind::Mqtt,
        Kind::Sparkplug,
        Kind::ThingsBoard,
        Kind::Azure,
        Kind::Aws,
    ];

    pub fn name(self) -> &'static str {
        match self {
            Kind::Mqtt => "mqtt",
            Kind::Sparkplug => "sparkplug",
            Kind::ThingsBoard => "thingsboard",
            Kind::Azure => "azure",
            Kind::Aws => "aws",
        }
    }

    pub fn display(self) -> &'static str {
        match self {
            Kind::Mqtt => "MQTT (UNS)",
            Kind::Sparkplug => "Sparkplug B",
            Kind::ThingsBoard => "ThingsBoard",
            Kind::Azure => "Azure IoT Hub",
            Kind::Aws => "AWS IoT Core",
        }
    }

    pub fn from_name(s: &str) -> Option<Self> {
        Self::ALL.into_iter().find(|k| k.name() == s)
    }

    /// What ▸ Set Password keeps for this kind.
    pub fn secret_about(self) -> &'static str {
        match self {
            Kind::Mqtt | Kind::Sparkplug => {
                "The MQTT password (with `username`), if the broker asks for one."
            }
            Kind::ThingsBoard => {
                "The gateway's access token (ThingsBoard: the gateway device's credentials)."
            }
            Kind::Azure => "The device's primary or secondary key (base64), from IoT Hub.",
            Kind::Aws => "The secret access key of `access_key_id`.",
        }
    }

    /// The kind cannot connect without a secret.
    pub fn needs_secret(self) -> bool {
        matches!(self, Kind::ThingsBoard | Kind::Azure | Kind::Aws)
    }

    pub fn is_mqtt(self) -> bool {
        !matches!(self, Kind::Aws)
    }
}

/// One field of a form.
pub struct Field {
    pub name: &'static str,
    pub ty: TypeCode,
    pub required: bool,
    pub display: &'static str,
    pub about: &'static str,
    pub placeholder: &'static str,
}

const fn f(
    name: &'static str,
    ty: TypeCode,
    required: bool,
    display: &'static str,
    about: &'static str,
    placeholder: &'static str,
) -> Field {
    Field {
        name,
        ty,
        required,
        display,
        about,
        placeholder,
    }
}

/// The fields every kind takes (`name` only on Add).
pub const COMMON: &[Field] = &[
    f("name", TypeCode::String, true, "Name", "One key segment: the upstream's node under this link.", "central-uns"),
    f("url", TypeCode::String, false, "Url", "mqtt://host:1883, mqtts://host:8883 (Azure: made from `hub` when empty; AWS: https://<endpoint>:8443).", "mqtts://broker.example:8883"),
    f("select", TypeCode::String, false, "Keys", "Full node keys whose values go up, one per line or comma: everything under each. Default: this site's downstream.", "wy/site/downstream/plc1, wy/site/storage"),
    f("max_hz", TypeCode::Number, false, "Max rate per point (Hz)", "At most this many values per point per second, the latest kept while over; 0 = every change (default).", "1"),
    f("queue_max", TypeCode::Number, false, "Queue", "Values held while the platform is slower than the site; the oldest go when it is full (default 10000, up to 100000).", "10000"),
    f("flush_ms", TypeCode::Number, false, "Flush (ms)", "How often queued values are sent (default 250; 50 to 60000).", "250"),
    f("ca_pem", TypeCode::String, false, "CA (PEM)", "Trust only this CA for TLS; empty: the system roots.", ""),
    f("timeout_ms", TypeCode::Number, false, "Timeout (ms)", "Of a connect or a request (default 5000; 500 to 30000).", "5000"),
    f("retry_s", TypeCode::Number, false, "Retry (s)", "The longest wait between connection attempts (default 60; 1 to 3600).", "60"),
    f("insecure_plaintext", TypeCode::Bool, false, "Insecure plaintext", "Send the secret over mqtt:// or http:// to a host that is not loopback.", ""),
    f("enabled", TypeCode::Bool, false, "Enabled", "", ""),
];

const MQTT_SESSION: &[Field] = &[
    f(
        "client_id",
        TypeCode::String,
        false,
        "Client id",
        "Default wyrm-<site>-<name>.",
        "",
    ),
    f(
        "username",
        TypeCode::String,
        false,
        "Username",
        "The MQTT user name; the password goes in with Set Password.",
        "",
    ),
    f(
        "keep_alive_s",
        TypeCode::Number,
        false,
        "Keep alive (s)",
        "Default 60; 5 to 3600.",
        "60",
    ),
];

pub const MQTT: &[Field] = &[
    f(
        "topic_prefix",
        TypeCode::String,
        false,
        "Topic prefix",
        "Topics are <prefix>/<site>/<path> (default wyrm).",
        "wyrm",
    ),
    f(
        "qos",
        TypeCode::Number,
        false,
        "QoS",
        "0 (default) or 1.",
        "0",
    ),
    f(
        "retain",
        TypeCode::Bool,
        false,
        "Retain",
        "Keep the last value on the broker (default on: a UNS reads it at once).",
        "",
    ),
    f(
        "payload",
        TypeCode::String,
        false,
        "Payload",
        "json: {\"v\", \"q\", \"t\"} (default); value: the value alone.",
        "json",
    ),
];

pub const SPARKPLUG: &[Field] = &[
    f(
        "group_id",
        TypeCode::String,
        false,
        "Group id",
        "spBv1.0/<group>/… (default wyrm).",
        "wyrm",
    ),
    f(
        "edge_node_id",
        TypeCode::String,
        false,
        "Edge node id",
        "Default: the site's name.",
        "",
    ),
];

pub const THINGSBOARD: &[Field] = &[f(
    "device_prefix",
    TypeCode::String,
    false,
    "Device prefix",
    "Devices are <prefix>-<link> (default: the site's name).",
    "",
)];

pub const AZURE: &[Field] = &[
    f(
        "hub",
        TypeCode::String,
        true,
        "IoT Hub",
        "The hub's name (myhub) or host (myhub.azure-devices.net).",
        "myhub",
    ),
    f(
        "device_id",
        TypeCode::String,
        true,
        "Device id",
        "",
        "edge-01",
    ),
    f(
        "sas_ttl_s",
        TypeCode::Number,
        false,
        "SAS lifetime (s)",
        "The token is made again before it runs out (default 3600; 300 to 86400).",
        "3600",
    ),
];

pub const AWS: &[Field] = &[
    f(
        "region",
        TypeCode::String,
        true,
        "Region",
        "",
        "eu-central-1",
    ),
    f(
        "access_key_id",
        TypeCode::String,
        true,
        "Access key id",
        "The secret access key goes in with Set Password.",
        "AKIA…",
    ),
    f(
        "topic",
        TypeCode::String,
        false,
        "Topic",
        "Where the samples go, one JSON array per flush (default wyrm/<site>).",
        "wyrm/site",
    ),
];

/// The kind's own fields, after [`COMMON`].
pub fn fields(kind: Kind) -> Vec<&'static Field> {
    let mut out: Vec<&Field> = match kind {
        Kind::Mqtt => MQTT.iter().chain(MQTT_SESSION).collect(),
        Kind::Sparkplug => SPARKPLUG.iter().chain(MQTT_SESSION).collect(),
        Kind::ThingsBoard => THINGSBOARD.iter().chain(MQTT_SESSION).collect(),
        Kind::Azure => AZURE.iter().collect(),
        Kind::Aws => AWS.iter().collect(),
    };
    // the kinds that have no MQTT session fields still take `keep_alive_s`
    if matches!(kind, Kind::Azure) {
        out.push(&MQTT_SESSION[2]);
    }
    out
}

pub const DEFAULT_QUEUE: usize = 10_000;
pub const MAX_QUEUE: usize = 100_000;
pub const DEFAULT_FLUSH_MS: u64 = 250;
pub const DEFAULT_TIMEOUT_MS: u32 = 5_000;
pub const DEFAULT_RETRY_S: u64 = 60;
pub const DEFAULT_KEEP_ALIVE_S: u16 = 60;
pub const DEFAULT_SAS_TTL_S: u64 = 3_600;
pub const MAX_SELECT: usize = 32;

/// `payload` of an `mqtt` upstream.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Payload {
    Json,
    Value,
}

/// An upstream as stored: the common fields typed, the kind's own in `extra` (validated).
#[derive(Debug, Clone, PartialEq)]
pub struct Def {
    pub name: String,
    pub kind: Kind,
    pub url: String,
    pub enabled: bool,
    pub select: Vec<String>,
    pub max_hz: f64,
    pub queue_max: usize,
    pub flush_ms: u64,
    pub ca_pem: Option<String>,
    pub timeout_ms: u32,
    pub retry_s: u64,
    pub insecure_plaintext: bool,
    /// From `wyrmd.json5`: shown, not edited.
    pub from_config: bool,
    pub extra: Map,
}

/// A URL's parts: TLS, host, port, the path (AWS: ignored).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Endpoint {
    pub tls: bool,
    pub host: String,
    pub port: u16,
}

fn text(m: &Map, k: &str) -> Result<Option<String>, String> {
    match m.get(k) {
        None | Some(Value::Null) => Ok(None),
        Some(Value::Str(s)) if s.trim().is_empty() => Ok(None),
        Some(Value::Str(s)) => Ok(Some(s.trim().to_owned())),
        Some(_) => Err(format!("{k}: text")),
    }
}

fn number(m: &Map, k: &str) -> Result<Option<f64>, String> {
    match m.get(k) {
        None | Some(Value::Null) => Ok(None),
        Some(Value::Str(s)) if s.trim().is_empty() => Ok(None),
        Some(Value::Str(s)) => s
            .trim()
            .parse::<f64>()
            .map(Some)
            .map_err(|_| format!("{k}: a number")),
        Some(v) => v.as_f64().map(Some).ok_or_else(|| format!("{k}: a number")),
    }
}

fn bounded(m: &Map, k: &str, default: f64, min: f64, max: f64) -> Result<f64, String> {
    match number(m, k)? {
        None => Ok(default),
        Some(n) if n.is_finite() && (min..=max).contains(&n) => Ok(n),
        Some(_) => Err(format!("{k}: {min} to {max}")),
    }
}

fn boolean(m: &Map, k: &str, default: bool) -> Result<bool, String> {
    match m.get(k) {
        None | Some(Value::Null) => Ok(default),
        Some(Value::Bool(b)) => Ok(*b),
        Some(Value::Str(s)) if s.is_empty() => Ok(default),
        Some(Value::Str(s)) => match s.trim().to_ascii_lowercase().as_str() {
            "true" | "1" | "on" | "yes" => Ok(true),
            "false" | "0" | "off" | "no" => Ok(false),
            _ => Err(format!("{k}: true or false")),
        },
        Some(_) => Err(format!("{k}: true or false")),
    }
}

/// `select` as a list: an array of keys, or text with one key per line or comma.
fn select_of(m: &Map, site: Option<&str>) -> Result<Vec<String>, String> {
    let items: Vec<String> = match m.get("select") {
        None | Some(Value::Null) => Vec::new(),
        Some(Value::Array(a)) => a
            .iter()
            .map(|v| match v {
                Value::Str(s) => Ok(s.trim().to_owned()),
                _ => Err("select: text keys".to_owned()),
            })
            .collect::<Result<_, _>>()?,
        Some(Value::Str(s)) => s
            .split([',', '\n', ';', ' '])
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .map(str::to_owned)
            .collect(),
        Some(_) => return Err("select: keys".into()),
    };
    let mut out: Vec<String> = Vec::new();
    for k in items {
        check_key(&k)?;
        if !out.contains(&k) {
            out.push(k);
        }
    }
    if out.is_empty() {
        let site = site.ok_or("select: at least one key (this host does not know the site)")?;
        out.push(format!("wy/{site}/downstream"));
    }
    if out.len() > MAX_SELECT {
        return Err(format!("select: at most {MAX_SELECT} keys"));
    }
    Ok(out)
}

/// A full node key, `wy/<site>/<section>[/…]`, no wildcards.
pub fn check_key(k: &str) -> Result<(), String> {
    let rest = k
        .strip_prefix("wy/")
        .ok_or_else(|| format!("select: {k}: a full key, wy/<site>/…"))?;
    let segs: Vec<&str> = rest.split('/').collect();
    if segs.len() < 2 {
        return Err(format!("select: {k}: at least wy/<site>/<section>"));
    }
    if segs
        .iter()
        .any(|s| s.is_empty() || s.contains(['*', '$', '~']) || *s == "." || *s == "..")
    {
        return Err(format!("select: {k}: a plain node key"));
    }
    if k.len() > 512 {
        return Err("select: a key over 512 bytes".into());
    }
    Ok(())
}

/// `scheme://host[:port][/…]` → the endpoint; `schemes`: what the kind takes, with the TLS
/// flag and the default port.
pub fn parse_url(url: &str, schemes: &[(&str, bool, u16)]) -> Result<Endpoint, String> {
    let (scheme, rest) = url
        .split_once("://")
        .ok_or_else(|| format!("url {url}: <scheme>://host[:port]"))?;
    let (_, tls, default_port) = schemes
        .iter()
        .find(|(s, _, _)| s.eq_ignore_ascii_case(scheme))
        .ok_or_else(|| {
            let names: Vec<&str> = schemes.iter().map(|(s, _, _)| *s).collect();
            format!("url {url}: the scheme must be one of {}", names.join(", "))
        })?;
    let authority = rest.split(['/', '?', '#']).next().unwrap_or_default();
    if authority.contains('@') {
        return Err("url: no credentials in the URL (use Set Password)".into());
    }
    let (host, port) = if let Some(h) = authority.strip_prefix('[') {
        let (h, p) = h.split_once(']').ok_or("url: bad IPv6 host")?;
        (h.to_owned(), p.strip_prefix(':'))
    } else {
        match authority.rsplit_once(':') {
            Some((h, p)) => (h.to_owned(), Some(p)),
            None => (authority.to_owned(), None),
        }
    };
    let port = match port {
        None | Some("") => *default_port,
        Some(p) => p
            .parse::<u16>()
            .ok()
            .filter(|p| *p > 0)
            .ok_or("url: bad port")?,
    };
    if host.is_empty()
        || host.len() > 253
        || host.contains(|c: char| c.is_whitespace() || c == '/' || c == '\\')
    {
        return Err("url: bad host".into());
    }
    Ok(Endpoint {
        tls: *tls,
        host: host.to_ascii_lowercase(),
        port,
    })
}

pub const MQTT_SCHEMES: &[(&str, bool, u16)] = &[
    ("mqtt", false, 1883),
    ("tcp", false, 1883),
    ("mqtts", true, 8883),
    ("ssl", true, 8883),
    ("tls", true, 8883),
];
pub const HTTPS_SCHEMES: &[(&str, bool, u16)] = &[("https", true, 8443), ("http", false, 80)];

pub fn loopback(host: &str) -> bool {
    host == "localhost" || host.parse::<IpAddr>().is_ok_and(|ip| ip.is_loopback())
}

impl Def {
    /// The upstream's fields from an Add or Edit form. `site`: the host's site when known
    /// (defaults); `net`: the link's allowlist as text, to refuse a host it does not cover.
    pub fn parse(
        kind: Kind,
        name: &str,
        m: &Map,
        site: Option<&str>,
        net: Option<&str>,
        from_config: bool,
    ) -> Result<Self, String> {
        let known: Vec<&str> = COMMON
            .iter()
            .chain(fields(kind))
            .map(|f| f.name)
            .chain(["kind"])
            .collect();
        if let Some(k) = m.keys().find(|k| !known.contains(&k.as_str())) {
            return Err(format!("{k}: not a field of a {} upstream", kind.display()));
        }
        wyrm_core::keyspace::validate_segment(name).map_err(|e| format!("name: {e}"))?;
        if name.starts_with('.') || name == crate::tree::STATS {
            return Err(format!("name: {name:?} is reserved"));
        }
        let mut extra = Map::new();
        let mut url = text(m, "url")?;
        let hub_host = |h: &str| -> String {
            if h.contains('.') {
                h.to_owned()
            } else {
                format!("{h}.azure-devices.net")
            }
        };
        match kind {
            Kind::Mqtt => {
                let prefix = text(m, "topic_prefix")?.unwrap_or_else(|| "wyrm".into());
                check_topic_part(&prefix, "topic_prefix")?;
                extra.insert("topic_prefix".into(), Value::Str(prefix));
                let qos = bounded(m, "qos", 0.0, 0.0, 1.0)?;
                extra.insert("qos".into(), Value::UInt(qos as u64));
                extra.insert("retain".into(), Value::Bool(boolean(m, "retain", true)?));
                let payload = text(m, "payload")?.unwrap_or_else(|| "json".into());
                if !["json", "value"].contains(&payload.as_str()) {
                    return Err("payload: json or value".into());
                }
                extra.insert("payload".into(), Value::Str(payload));
            }
            Kind::Sparkplug => {
                let group = text(m, "group_id")?.unwrap_or_else(|| "wyrm".into());
                check_sparkplug_id(&group, "group_id")?;
                extra.insert("group_id".into(), Value::Str(group));
                let node = match text(m, "edge_node_id")? {
                    Some(n) => n,
                    None => site
                        .ok_or("edge_node_id: required (this host does not know the site)")?
                        .to_owned(),
                };
                check_sparkplug_id(&node, "edge_node_id")?;
                extra.insert("edge_node_id".into(), Value::Str(node));
            }
            Kind::ThingsBoard => {
                let p = match text(m, "device_prefix")? {
                    Some(p) => p,
                    None => site
                        .ok_or("device_prefix: required (this host does not know the site)")?
                        .to_owned(),
                };
                check_sparkplug_id(&p, "device_prefix")?;
                extra.insert("device_prefix".into(), Value::Str(p));
            }
            Kind::Azure => {
                let hub = text(m, "hub")?.ok_or("hub: required")?;
                let device = text(m, "device_id")?.ok_or("device_id: required")?;
                if hub.contains(['/', ' ', '?', '&'])
                    || device.contains(['/', ' ', '?', '&', '#', '+'])
                {
                    return Err("hub, device_id: no / ? & # + or spaces".into());
                }
                let host = hub_host(&hub);
                extra.insert("hub".into(), Value::Str(host.clone()));
                extra.insert("device_id".into(), Value::Str(device));
                extra.insert(
                    "sas_ttl_s".into(),
                    Value::UInt(
                        bounded(m, "sas_ttl_s", DEFAULT_SAS_TTL_S as f64, 300.0, 86_400.0)? as u64,
                    ),
                );
                if url.is_none() {
                    url = Some(format!("mqtts://{host}:8883"));
                }
            }
            Kind::Aws => {
                let region = text(m, "region")?.ok_or("region: required")?;
                let key = text(m, "access_key_id")?.ok_or("access_key_id: required")?;
                if !region
                    .bytes()
                    .all(|b| b.is_ascii_alphanumeric() || b == b'-')
                {
                    return Err("region: letters, digits and -".into());
                }
                if !key.bytes().all(|b| b.is_ascii_alphanumeric()) {
                    return Err("access_key_id: letters and digits".into());
                }
                extra.insert("region".into(), Value::Str(region));
                extra.insert("access_key_id".into(), Value::Str(key));
                let topic = match text(m, "topic")? {
                    Some(t) => t,
                    None => format!(
                        "wyrm/{}",
                        site.ok_or("topic: required (this host does not know the site)")?
                    ),
                };
                check_topic_part(&topic, "topic")?;
                extra.insert("topic".into(), Value::Str(topic));
            }
        }
        if kind.is_mqtt() {
            if kind != Kind::Azure {
                if let Some(c) = text(m, "client_id")? {
                    if c.len() > 128 || c.contains(['\0', ' ']) {
                        return Err("client_id: at most 128 characters, no spaces".into());
                    }
                    extra.insert("client_id".into(), Value::Str(c));
                }
                if let Some(u) = text(m, "username")? {
                    if u.len() > 256 {
                        return Err("username: at most 256 characters".into());
                    }
                    extra.insert("username".into(), Value::Str(u));
                }
            }
            extra.insert(
                "keep_alive_s".into(),
                Value::UInt(bounded(
                    m,
                    "keep_alive_s",
                    f64::from(DEFAULT_KEEP_ALIVE_S),
                    5.0,
                    3600.0,
                )? as u64),
            );
        }
        let url = url.ok_or("url: required")?;
        let ep = parse_url(
            &url,
            if kind.is_mqtt() {
                MQTT_SCHEMES
            } else {
                HTTPS_SCHEMES
            },
        )?;
        let insecure_plaintext = boolean(m, "insecure_plaintext", false)?;
        if !ep.tls && !loopback(&ep.host) && !insecure_plaintext {
            return Err(format!(
                "url {url}: the secret would go in the clear; use TLS (mqtts://, https://), or set insecure_plaintext"
            ));
        }
        let ca_pem = text(m, "ca_pem")?;
        if ca_pem.is_some() && !ep.tls {
            return Err("ca_pem: only with TLS".into());
        }
        if let Some(net) = net {
            check_net(net, &ep)?;
        }
        Ok(Def {
            name: name.to_owned(),
            kind,
            url,
            enabled: boolean(m, "enabled", true)?,
            select: select_of(m, site)?,
            max_hz: bounded(m, "max_hz", 0.0, 0.0, 1000.0)?,
            queue_max: bounded(m, "queue_max", DEFAULT_QUEUE as f64, 1.0, MAX_QUEUE as f64)?
                as usize,
            flush_ms: bounded(m, "flush_ms", DEFAULT_FLUSH_MS as f64, 50.0, 60_000.0)? as u64,
            ca_pem,
            timeout_ms: bounded(
                m,
                "timeout_ms",
                f64::from(DEFAULT_TIMEOUT_MS),
                500.0,
                30_000.0,
            )? as u32,
            retry_s: bounded(m, "retry_s", DEFAULT_RETRY_S as f64, 1.0, 3600.0)? as u64,
            insecure_plaintext,
            from_config,
            extra,
        })
    }

    pub fn endpoint(&self) -> Endpoint {
        parse_url(
            &self.url,
            if self.kind.is_mqtt() {
                MQTT_SCHEMES
            } else {
                HTTPS_SCHEMES
            },
        )
        .unwrap_or(Endpoint {
            tls: true,
            host: String::new(),
            port: 0,
        })
    }

    pub fn str(&self, k: &str) -> &str {
        match self.extra.get(k) {
            Some(Value::Str(s)) => s,
            _ => "",
        }
    }

    pub fn uint(&self, k: &str, default: u64) -> u64 {
        match self.extra.get(k) {
            Some(Value::UInt(u)) => *u,
            _ => default,
        }
    }

    pub fn flag(&self, k: &str, default: bool) -> bool {
        match self.extra.get(k) {
            Some(Value::Bool(b)) => *b,
            _ => default,
        }
    }

    pub fn payload(&self) -> Payload {
        if self.str("payload") == "value" {
            Payload::Value
        } else {
            Payload::Json
        }
    }

    /// The MQTT client id: the field, or `wyrm-<site>-<name>`.
    pub fn client_id(&self, site: Option<&str>) -> String {
        let c = self.str("client_id");
        if !c.is_empty() {
            return c.to_owned();
        }
        if self.kind == Kind::Azure {
            return self.str("device_id").to_owned();
        }
        format!("wyrm-{}-{}", site.unwrap_or("site"), self.name)
    }

    /// What is shown of it: the fields as a map (never a secret, which is not in here).
    pub fn to_value(&self) -> Value {
        let mut m = self.extra.clone();
        let s = |v: &str| Value::Str(v.to_owned());
        m.insert("name".into(), s(&self.name));
        m.insert("kind".into(), s(self.kind.name()));
        m.insert("url".into(), s(&self.url));
        m.insert("enabled".into(), Value::Bool(self.enabled));
        m.insert(
            "select".into(),
            Value::Array(self.select.iter().cloned().map(Value::Str).collect()),
        );
        m.insert("max_hz".into(), Value::Float(self.max_hz));
        m.insert("queue_max".into(), Value::UInt(self.queue_max as u64));
        m.insert("flush_ms".into(), Value::UInt(self.flush_ms));
        if let Some(c) = &self.ca_pem {
            m.insert("ca_pem".into(), s(c));
        }
        m.insert("timeout_ms".into(), Value::UInt(u64::from(self.timeout_ms)));
        m.insert("retry_s".into(), Value::UInt(self.retry_s));
        m.insert(
            "insecure_plaintext".into(),
            Value::Bool(self.insecure_plaintext),
        );
        m.insert("from_config".into(), Value::Bool(self.from_config));
        Value::Map(m)
    }

    /// A stored or configured upstream back: `kind` and `name` are in the map.
    pub fn from_value(v: &Value, site: Option<&str>) -> Result<Self, String> {
        let Value::Map(m) = v else {
            return Err("not a map".into());
        };
        let kind = match m.get("kind") {
            Some(Value::Str(k)) => {
                Kind::from_name(k).ok_or_else(|| format!("kind {k}: unknown"))?
            }
            _ => return Err("kind: missing".into()),
        };
        let name = match m.get("name") {
            Some(Value::Str(n)) => n.clone(),
            _ => return Err("name: missing".into()),
        };
        let from_config = matches!(m.get("from_config"), Some(Value::Bool(true)));
        let mut m = m.clone();
        m.remove("from_config");
        m.remove("name");
        Self::parse(kind, &name, &m, site, None, from_config)
    }
}

/// A topic prefix or topic: no wildcards, no leading `/`, no `$`, no NUL.
pub fn check_topic_part(t: &str, what: &str) -> Result<(), String> {
    if t.is_empty()
        || t.len() > 256
        || t.contains(['+', '#', '\0'])
        || t.starts_with(['/', '$'])
        || t.ends_with('/')
    {
        return Err(format!(
            "{what}: no + # or $, no leading or trailing /, at most 256 characters"
        ));
    }
    Ok(())
}

/// A Sparkplug group, node or device id, also a ThingsBoard device prefix: no `/`, `+`, `#`.
pub fn check_sparkplug_id(s: &str, what: &str) -> Result<(), String> {
    if s.is_empty() || s.len() > 128 || s.contains(['/', '+', '#', '\0']) {
        return Err(format!("{what}: no / + or #, at most 128 characters"));
    }
    Ok(())
}

/// The link's `net` covers the endpoint: an IP entry for a literal, a name entry for a name
/// (checked with an ordinary address: the real one is checked by the host when it connects).
pub fn check_net(net: &str, ep: &Endpoint) -> Result<(), String> {
    let policy = NetPolicy::parse(net).map_err(|e| format!("net: {e}"))?;
    let ok = match ep.host.parse::<IpAddr>() {
        Ok(ip) => policy.allows(ip, ep.port),
        Err(_) if ep.host == "localhost" => policy.allows(
            "127.0.0.1"
                .parse()
                .unwrap_or(IpAddr::V4(std::net::Ipv4Addr::LOCALHOST)),
            ep.port,
        ),
        Err(_) => policy.allows_named(
            &ep.host,
            IpAddr::V4(std::net::Ipv4Addr::new(198, 51, 100, 1)),
            ep.port,
        ),
    };
    if ok {
        Ok(())
    } else {
        Err(format!(
            "{}:{} is not in the link's net allowlist: add `{}:{}` to uplink.net in wyrmd.json5 (or the package's net)",
            ep.host, ep.port, ep.host, ep.port
        ))
    }
}

/// A tree value as JSON (bytes as base64, maps and arrays as they are).
pub fn json_value(v: &Value) -> serde_json::Value {
    match v {
        Value::Null => serde_json::Value::Null,
        Value::Bool(b) => serde_json::Value::Bool(*b),
        Value::Int(i) => serde_json::Value::from(*i),
        Value::UInt(u) => serde_json::Value::from(*u),
        Value::Float(f) => serde_json::Number::from_f64(*f)
            .map(serde_json::Value::Number)
            .unwrap_or(serde_json::Value::Null),
        Value::Str(s) => serde_json::Value::String(s.clone()),
        Value::Bytes(b) => {
            serde_json::Value::String(base64::engine::general_purpose::STANDARD.encode(b))
        }
        Value::Array(a) => serde_json::Value::Array(a.iter().map(json_value).collect()),
        Value::Map(m) => {
            serde_json::Value::Object(m.iter().map(|(k, v)| (k.clone(), json_value(v))).collect())
        }
    }
}

/// `{"v", "q", "t"}` of a sample (`t` in µs, as the tree has it).
pub fn json_sample(s: &Sample) -> serde_json::Value {
    serde_json::json!({ "v": json_value(&s.v), "q": quality_name(s.q), "t": s.t })
}

pub fn quality_name(q: Quality) -> &'static str {
    q.name()
}

/// A key `wy/<site>/<section>/…` as `(site, section, rest)`.
pub fn split_key(key: &str) -> Option<(&str, &str, &str)> {
    let rest = key.strip_prefix("wy/")?;
    let (site, rest) = rest.split_once('/')?;
    let (section, rest) = rest.split_once('/').unwrap_or((rest, ""));
    Some((site, section, rest))
}

/// The device and metric of a key for Sparkplug and ThingsBoard: a link under `downstream` is a
/// device (`<link>`, another site's `<site>.<link>`); `dataflows` and `storage` are devices of
/// their own. The metric is the path below the device (`_` for the device node itself).
pub fn device_and_metric<'a>(key: &'a str, own_site: Option<&str>) -> Option<(String, &'a str)> {
    let (site, section, rest) = split_key(key)?;
    let own = own_site == Some(site);
    let (device, metric) = match section {
        "downstream" => {
            let (link, path) = rest.split_once('/').unwrap_or((rest, ""));
            if link.is_empty() {
                return None;
            }
            (link.to_owned(), path)
        }
        "dataflows" | "storage" => (section.to_owned(), rest),
        _ => return None,
    };
    let device = if own {
        device
    } else {
        format!("{site}.{device}")
    };
    Some((device, if metric.is_empty() { "_" } else { metric }))
}

/// An Azure IoT Hub SAS token for a device: `SharedAccessSignature sr=…&sig=…&se=…`.
pub fn azure_sas(
    hub: &str,
    device_id: &str,
    key_b64: &str,
    expiry_s: u64,
) -> Result<String, String> {
    let key = base64::engine::general_purpose::STANDARD
        .decode(key_b64.trim())
        .map_err(|_| "the device key is not base64".to_owned())?;
    let sr = url_encode(&format!("{hub}/devices/{device_id}"));
    let to_sign = format!("{sr}\n{expiry_s}");
    let mut mac = Hmac::<Sha256>::new_from_slice(&key).map_err(|_| "bad key".to_owned())?;
    mac.update(to_sign.as_bytes());
    let sig = base64::engine::general_purpose::STANDARD.encode(mac.finalize().into_bytes());
    Ok(format!(
        "SharedAccessSignature sr={sr}&sig={}&se={expiry_s}",
        url_encode(&sig)
    ))
}

/// Percent-encoding of everything but the unreserved characters (RFC 3986).
pub fn url_encode(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for b in s.bytes() {
        if b.is_ascii_alphanumeric() || b"-_.~".contains(&b) {
            out.push(b as char);
        } else {
            out.push_str(&format!("%{b:02X}"));
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn m(pairs: &[(&str, Value)]) -> Map {
        pairs
            .iter()
            .map(|(k, v)| ((*k).to_owned(), v.clone()))
            .collect()
    }

    #[test]
    fn urls_and_defaults() {
        let d = Def::parse(
            Kind::Mqtt,
            "uns",
            &m(&[("url", Value::from("mqtts://Broker.Example"))]),
            Some("plant"),
            None,
            false,
        )
        .unwrap();
        assert_eq!(
            d.endpoint(),
            Endpoint {
                tls: true,
                host: "broker.example".into(),
                port: 8883
            }
        );
        assert_eq!(d.select, ["wy/plant/downstream"]);
        assert_eq!(d.str("topic_prefix"), "wyrm");
        assert!(d.flag("retain", false));
        assert_eq!(d.client_id(Some("plant")), "wyrm-plant-uns");
        // plaintext off loopback is refused without the flag; loopback is fine
        let plain = m(&[("url", Value::from("mqtt://10.0.0.5"))]);
        assert!(Def::parse(Kind::Mqtt, "x", &plain, Some("s"), None, false).is_err());
        let local = m(&[("url", Value::from("mqtt://127.0.0.1:1884"))]);
        assert_eq!(
            Def::parse(Kind::Mqtt, "x", &local, Some("s"), None, false)
                .unwrap()
                .endpoint()
                .port,
            1884
        );
        // a round trip through the stored form keeps everything
        let v = d.to_value();
        assert_eq!(Def::from_value(&v, Some("plant")).unwrap(), d);
    }

    #[test]
    fn kinds_check_their_fields() {
        let az = Def::parse(
            Kind::Azure,
            "az",
            &m(&[
                ("hub", Value::from("myhub")),
                ("device_id", Value::from("edge-01")),
                ("select", Value::from("wy/s/downstream")),
            ]),
            None,
            None,
            false,
        )
        .unwrap();
        assert_eq!(az.url, "mqtts://myhub.azure-devices.net:8883");
        assert_eq!(az.client_id(None), "edge-01");
        assert!(Def::parse(
            Kind::Azure,
            "az",
            &m(&[("hub", Value::from("h"))]),
            None,
            None,
            false
        )
        .is_err());
        let aws = m(&[
            (
                "url",
                Value::from("https://abc-ats.iot.eu-central-1.amazonaws.com"),
            ),
            ("region", Value::from("eu-central-1")),
            ("access_key_id", Value::from("AKIAXXXX")),
        ]);
        let a = Def::parse(Kind::Aws, "aws", &aws, Some("s"), None, false).unwrap();
        assert_eq!(a.endpoint().port, 8443);
        assert_eq!(a.str("topic"), "wyrm/s");
        assert!(
            Def::parse(Kind::Aws, "aws", &aws, None, None, false).is_err(),
            "no site, no topic"
        );
        let sp = Def::parse(
            Kind::Sparkplug,
            "ign",
            &m(&[
                ("url", Value::from("mqtt://localhost")),
                ("select", Value::from("wy/s/downstream/plc, wy/s/storage")),
            ]),
            Some("s"),
            None,
            false,
        )
        .unwrap();
        assert_eq!(sp.str("edge_node_id"), "s");
        assert_eq!(sp.select.len(), 2);
        let bad = m(&[
            ("url", Value::from("mqtt://localhost")),
            ("select", Value::from("wy/s/downstream/*")),
        ]);
        assert!(Def::parse(Kind::Sparkplug, "ign", &bad, Some("s"), None, false).is_err());
        let unknown = m(&[
            ("url", Value::from("mqtt://localhost")),
            ("region", Value::from("x")),
        ]);
        assert!(Def::parse(Kind::Mqtt, "u", &unknown, Some("s"), None, false).is_err());
    }

    #[test]
    fn net_is_checked_by_name_or_address() {
        let ep = |h: &str, p: u16| Endpoint {
            tls: true,
            host: h.into(),
            port: p,
        };
        assert!(check_net(
            "*.azure-devices.net:8883",
            &ep("myhub.azure-devices.net", 8883)
        )
        .is_ok());
        assert!(check_net(
            "*.azure-devices.net:8883",
            &ep("myhub.azure-devices.net", 443)
        )
        .is_err());
        assert!(check_net("10.0.0.0/8:1883", &ep("10.1.2.3", 1883)).is_ok());
        assert!(check_net("10.0.0.0/8:1883", &ep("broker.example", 1883)).is_err());
        assert!(check_net("", &ep("broker.example", 1883)).is_err());
    }

    #[test]
    fn devices_metrics_and_sas() {
        assert_eq!(
            device_and_metric("wy/s/downstream/plc/d0/temp", Some("s")),
            Some(("plc".into(), "d0/temp"))
        );
        assert_eq!(
            device_and_metric("wy/edge/downstream/plc/t", Some("s")),
            Some(("edge.plc".into(), "t"))
        );
        assert_eq!(
            device_and_metric("wy/s/storage/a/b", Some("s")),
            Some(("storage".into(), "a/b"))
        );
        assert_eq!(device_and_metric("wy/s/sys/x", Some("s")), None);
        assert_eq!(
            device_and_metric("wy/s/downstream/plc", Some("s")),
            Some(("plc".into(), "_"))
        );
        // the Azure sample from the docs: a known key and time give a stable signature
        let t = azure_sas("myhub.azure-devices.net", "dev1", "AAAA", 1_700_000_000).unwrap();
        assert!(
            t.starts_with("SharedAccessSignature sr=myhub.azure-devices.net%2Fdevices%2Fdev1&sig=")
        );
        assert!(t.ends_with("&se=1700000000"));
        assert!(azure_sas("h", "d", "not base64!", 1).is_err());
        assert_eq!(url_encode("a b/c"), "a%20b%2Fc");
        assert_eq!(
            json_sample(&Sample {
                v: Value::Float(1.5),
                q: Quality::Good,
                t: 7
            })
            .to_string(),
            r#"{"q":"good","t":7,"v":1.5}"#
        );
    }
}
