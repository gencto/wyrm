//! History sync to InfluxDB (ADR 0026): the [`Influx`] target writes a history sink's batches
//! with the v2 write API (`POST /api/v2/write`, InfluxDB 2.x and 3.x), line protocol at µs
//! precision. One point per row: measurement `measurement` (default `wyrm`), tags `site` and
//! `key` (the point's full key), fields `value` and `quality`, time `t`. The same series, tags
//! and time overwrite, so a batch sent twice changes nothing.
//!
//! Params (besides `sink`, `batch`, `idle_s`, `retry_s` of [`wyrm_history_sync`]): `url`
//! (`https://host[:port][/base]`, or `http://` to an IP), `org`, `bucket`, `measurement`,
//! `ca_pem` (trust only this CA), `timeout_ms` (default 10 000), `insecure_plaintext` (send the
//! token over `http://` to a host that is not loopback). The token goes in with ▸ Set Password.
//! A row whose value is not a number, a bool or text (or a number that is not finite) is skipped.

use wyrm_core::{Quality, Value};
use wyrm_history_sync::http::{self, loopback, parse_url, query_value, Request};
use wyrm_history_sync::{Map, Row, SyncApp, Target, TargetError};
use wyrm_link_api::{ConnId, Host};

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
        measurement: text(cfg, "measurement")?.unwrap_or_else(|| "wyrm".into()),
        ca_pem: text(cfg, "ca_pem")?,
        timeout_ms,
    })
}

/// Line protocol escapes: `,` and space in a measurement; also `=` in a tag.
fn escape(s: &str, also_eq: bool) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        if c == ',' || c == ' ' || (also_eq && c == '=') || c == '\\' {
            out.push('\\');
        }
        if c == '\n' || c == '\r' {
            out.push(' ');
        } else {
            out.push(c);
        }
    }
    out
}

/// The `value` field of a row, or `None` for a value line protocol cannot hold.
fn field(v: &Value) -> Option<String> {
    Some(match v {
        Value::Float(f) if f.is_finite() => format!("{f:?}"),
        Value::Int(i) => format!("{i}i"),
        Value::UInt(u) => format!("{u}u"),
        Value::Bool(b) => b.to_string(),
        Value::Str(s) => {
            let s = s
                .replace('\\', "\\\\")
                .replace('"', "\\\"")
                .replace(['\n', '\r'], " ");
            format!("\"{s}\"")
        }
        _ => return None,
    })
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
            "{m},site={},key={} value={value},quality={}i {}\n",
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
    conn: Option<ConnId>,
}

impl Influx {
    fn open(&mut self, net: &mut dyn Host) -> Result<ConnId, TargetError> {
        if let Some(c) = self.conn {
            return Ok(c);
        }
        let c = &self.cfg;
        let r = if c.tls {
            net.tls_connect(&c.host, c.port, c.timeout_ms, c.ca_pem.as_deref())
        } else {
            let ip = if c.host == "localhost" {
                "127.0.0.1"
            } else {
                &c.host
            };
            net.tcp_connect(ip, c.port, c.timeout_ms)
        };
        let conn = r.map_err(|e| TargetError::Reconnect(format!("influxdb: {}", e.msg)))?;
        self.conn = Some(conn);
        Ok(conn)
    }

    fn shut(&mut self, net: &mut dyn Host) {
        if let Some(c) = self.conn.take() {
            net.tcp_close(c);
        }
    }

    /// One request; a keep-alive connection the server closed meanwhile is
    /// opened again once.
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
        let host = self.cfg.host.clone();
        for attempt in 0..2 {
            let conn = self.open(net)?;
            let req = Request {
                method,
                path,
                host: &host,
                headers: &headers,
                body,
            };
            match http::send(net, conn, &req, self.cfg.timeout_ms) {
                Ok(r) => {
                    if r.close {
                        self.shut(net);
                    }
                    return Ok(r);
                }
                Err(TargetError::Reconnect(m)) => {
                    self.shut(net);
                    if attempt == 1 {
                        return Err(TargetError::Reconnect(m));
                    }
                }
                Err(e) => return Err(e),
            }
        }
        Err(TargetError::Reconnect("influxdb: no connection".into()))
    }
}

/// What a status means for the batch.
fn judge(r: &http::Response, what: &str) -> Result<(), TargetError> {
    let msg = || format!("influxdb {what}: {} {}", r.status, r.text(300));
    match r.status {
        200..=299 => Ok(()),
        429 | 500..=599 => Err(TargetError::Retry(msg())),
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
        let mut t = Influx {
            cfg,
            token: secret.map(str::to_owned),
            conn: None,
        };
        t.open(net)?;
        Ok(t)
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
        self.shut(net);
    }
}

// Only on wasm32: natively the exports would be bare global symbols.
#[cfg(all(feature = "wasm", target_arch = "wasm32"))]
wyrm_link_guest::export!(InfluxSync);

#[cfg(test)]
mod tests;
