//! History sync to InfluxDB (ADR 0026): the [`Influx`] target writes a history sink's batches
//! with the v2 write API (`POST /api/v2/write`, InfluxDB 2.x and 3.x), line protocol at µs
//! precision. One point per row: measurement `measurement` (default `wyrm`), tags `site` and
//! `key` (the point's full key), fields `value` and `quality`, time `t`. The same series, tags
//! and time overwrite, so a batch sent twice changes nothing.
//!
//! The field types never change for a series (security review HS-1): InfluxDB refuses a field
//! whose type differs from what the series already holds, so a point that is `5` once and `5.5`
//! later would stop its rows. A number (integer or not) and a bool (`1.0`/`0.0`) are the float
//! field `value`; text is the string field `value_text`. Integers beyond 2^53 lose precision.
//!
//! Params (besides `sink`, `batch`, `idle_s`, `retry_s` of [`wyrm_history_sync`]): `url`
//! (`https://host[:port][/base]`, or `http://` to an IP), `org`, `bucket`, `measurement`,
//! `ca_pem` (trust only this CA), `timeout_ms` (default 10 000), `insecure_plaintext` (send the
//! token over `http://` to a host that is not loopback). The token goes in with ▸ Set Password.
//! A row whose value is not a number, a bool or text (or a number that is not finite) is skipped.

use wyrm_core::{Quality, Value};
use wyrm_history_sync::http::{self, loopback, parse_url, query_value, Client};
use wyrm_history_sync::{Map, Row, SyncApp, Target, TargetError};
use wyrm_link_api::Host;

/// The app: `Portable<InfluxSync>` embedded or as a process, `export!(InfluxSync)` in WASM.
pub type InfluxSync = SyncApp<Influx>;

const KEYS: [&str; 7] = [
    "url",
    "org",
    "bucket",
    "measurement",
    "ca_pem",
    "timeout_ms",
    "insecure_plaintext",
];
const DEFAULT_TIMEOUT_MS: u32 = 10_000;

#[derive(Debug, Clone, PartialEq)]
struct Cfg {
    tls: bool,
    host: String,
    port: u16,
    base: String,
    org: String,
    bucket: String,
    measurement: String,
    ca_pem: Option<String>,
    timeout_ms: u32,
}

fn text(cfg: &Map, key: &str) -> Result<Option<String>, String> {
    match cfg.get(key) {
        None | Some(Value::Null) => Ok(None),
        Some(Value::Str(s)) if s.trim().is_empty() => Ok(None),
        Some(Value::Str(s)) => Ok(Some(s.trim().to_owned())),
        Some(_) => Err(format!("params.{key}: text")),
    }
}

fn parse(cfg: &Map) -> Result<Cfg, String> {
    if let Some(k) = cfg.keys().find(|k| !KEYS.contains(&k.as_str())) {
        return Err(format!("params.{k}: unknown"));
    }
    let url = text(cfg, "url")?.ok_or("params.url: https://host[:port]")?;
    let (tls, host, port, base) = parse_url(&url)?;
    let insecure = matches!(cfg.get("insecure_plaintext"), Some(Value::Bool(true)));
    if !tls && !loopback(&host) && !insecure {
        return Err(format!(
            "params.url: {url} sends the token in the clear; use https://, or insecure_plaintext"
        ));
    }
    let timeout_ms = match cfg.get("timeout_ms") {
        None => DEFAULT_TIMEOUT_MS,
        Some(v) => v
            .as_f64()
            .filter(|t| (100.0..=60_000.0).contains(t))
            .map(|t| t as u32)
            .ok_or("params.timeout_ms: 100 to 60000")?,
    };
    Ok(Cfg {
        tls,
        host,
        port,
        base,
        org: text(cfg, "org")?.ok_or("params.org: the organization")?,
        bucket: text(cfg, "bucket")?.ok_or("params.bucket: the bucket")?,
        measurement: match text(cfg, "measurement")? {
            None => "wyrm".into(),
            // `#` makes every line a comment (written as nothing, then purged); `_` is reserved
            Some(m) if m.is_empty() || m.starts_with(['#', '_']) => {
                return Err("params.measurement: not empty, not starting with # or _".into())
            }
            Some(m) => m,
        },
        ca_pem: text(cfg, "ca_pem")?,
        timeout_ms,
    })
}

/// Line protocol escapes: `,` and space in a measurement; also `=` in a tag.
fn escape(s: &str, also_eq: bool) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        // a line break becomes a space first, and that space is escaped like any other: an
        // unescaped space would end the tag set (line protocol injection)
        let c = if c == '\n' || c == '\r' { ' ' } else { c };
        if c == ',' || c == ' ' || (also_eq && c == '=') || c == '\\' {
            out.push('\\');
        }
        out.push(c);
    }
    out
}

/// The value field of a row (`value=<float>` or `value_text="…"`), or `None` for a value line
/// protocol cannot hold. One type per field, whatever the value's CBOR type.
fn field(v: &Value) -> Option<String> {
    let float = |f: f64| f.is_finite().then(|| format!("value={f:?}"));
    match v {
        Value::Float(f) => float(*f),
        Value::Int(i) => float(*i as f64),
        Value::UInt(u) => float(*u as f64),
        Value::Bool(b) => float(if *b { 1.0 } else { 0.0 }),
        Value::Str(s) => {
            let s = s
                .replace('\\', "\\\\")
                .replace('"', "\\\"")
                .replace(['\n', '\r'], " ");
            Some(format!("value_text=\"{s}\""))
        }
        _ => None,
    }
}

/// The batch as line protocol; rows it cannot hold are left out.
pub fn lines(measurement: &str, rows: &[Row]) -> String {
    let m = escape(measurement, false);
    let mut out = String::new();
    for r in rows {
        let Some(value) = field(&r.v) else {
            continue;
        };
        out.push_str(&format!(
            "{m},site={},key={} {value},quality={}i {}\n",
            escape(&r.site, true),
            escape(&r.key, true),
            quality_code(r.q),
            r.t
        ));
    }
    out
}

fn quality_code(q: Quality) -> u8 {
    q.code()
}

/// InfluxDB over one keep-alive connection.
pub struct Influx {
    cfg: Cfg,
    token: Option<String>,
    http: Client,
}

impl Influx {
    fn request(
        &mut self,
        net: &mut dyn Host,
        method: &str,
        path: &str,
        body: &[u8],
    ) -> Result<http::Response, TargetError> {
        let auth = self.token.as_ref().map(|t| format!("Token {t}"));
        let mut headers = vec![("Content-Type", "text/plain; charset=utf-8")];
        if let Some(a) = &auth {
            headers.push(("Authorization", a.as_str()));
        }
        self.http.request(net, method, path, &headers, body)
    }
}

/// What a status means for the batch: 400 (a line it cannot parse, a partial write), 413 (too
/// large) and 422 (a field type conflict) refuse the data, not the connection.
fn judge(r: &http::Response, what: &str) -> Result<(), TargetError> {
    let msg = || format!("influxdb {what}: {} {}", r.status, r.text(300));
    match r.status {
        200..=299 => Ok(()),
        429 | 500..=599 => Err(TargetError::Retry(msg())),
        400 | 413 | 422 => Err(TargetError::Refused(msg())),
        _ => Err(TargetError::Fatal(msg())),
    }
}

impl Target for Influx {
    const KIND: &'static str = "influxdb";
    const VERSION: &'static str = env!("CARGO_PKG_VERSION");

    fn check(cfg: &Map) -> Result<(), String> {
        parse(cfg).map(|_| ())
    }

    fn connect(net: &mut dyn Host, cfg: &Map, secret: Option<&str>) -> Result<Self, TargetError> {
        let cfg = parse(cfg).map_err(TargetError::Fatal)?;
        let mut http = Client::new(
            cfg.tls,
            cfg.host.clone(),
            cfg.port,
            cfg.ca_pem.clone(),
            cfg.timeout_ms,
        );
        http.open(net)?;
        Ok(Influx {
            cfg,
            token: secret.map(str::to_owned),
            http,
        })
    }

    fn write(&mut self, net: &mut dyn Host, rows: &[Row]) -> Result<(), TargetError> {
        let body = lines(&self.cfg.measurement, rows);
        if body.is_empty() {
            return Ok(());
        }
        let path = format!(
            "{}/api/v2/write?org={}&bucket={}&precision=us",
            self.cfg.base,
            query_value(&self.cfg.org),
            query_value(&self.cfg.bucket)
        );
        let r = self.request(net, "POST", &path, body.as_bytes())?;
        judge(&r, "write")
    }

    fn ping(&mut self, net: &mut dyn Host) -> Result<(), TargetError> {
        let path = format!("{}/ping", self.cfg.base);
        let r = self.request(net, "GET", &path, b"")?;
        judge(&r, "ping")
    }

    fn close(mut self, net: &mut dyn Host) {
        self.http.close(net);
    }
}

// Only on wasm32: natively the exports would be bare global symbols.
#[cfg(all(feature = "wasm", target_arch = "wasm32"))]
wyrm_link_guest::export!(InfluxSync);

#[cfg(test)]
mod tests;
