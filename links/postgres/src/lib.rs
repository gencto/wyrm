//! History sync to PostgreSQL (ADR 0026), TimescaleDB too: the [`Pg`] target writes a history
//! sink's batches into one table over the v3 wire protocol, with TLS by `SSLRequest` and
//! SCRAM-SHA-256 (or a cleartext password over TLS or loopback; MD5 is refused).
//!
//! The table (made with `create_table`, default on):
//! `site text, key text, t timestamptz, value double precision, value_text text,
//! quality smallint, PRIMARY KEY (key, t)`; a row with the same `(key, t)` is replaced, so a
//! batch sent twice changes nothing. A number goes to `value` (a bool as 1 or 0, its text too),
//! text to `value_text`, null to neither; a row holding bytes, a list or a map is skipped.
//!
//! Params (besides `sink`, `batch`, `idle_s`, `retry_s`): `host`, `port` (5432), `database`,
//! `user`, `table` (`wyrm_history`, or `schema.table`), `sslmode` (`require`, the default, or
//! `disable`: only to loopback unless `insecure_plaintext`), `ca_pem`, `timeout_ms` (10 000),
//! `create_table` (true). The password goes in with ▸ Set Password.

mod scram;

use std::collections::HashMap;
use wyrm_core::Value;
use wyrm_history_sync::http::loopback;
use wyrm_history_sync::{Map, Row, SyncApp, Target, TargetError};
use wyrm_link_api::{ConnId, Host};

/// The app: `Portable<PgSync>` embedded or as a process, `export!(PgSync)` in WASM.
pub type PgSync = SyncApp<Pg>;

const KEYS: [&str; 10] = [
    "host",
    "port",
    "database",
    "user",
    "table",
    "sslmode",
    "ca_pem",
    "timeout_ms",
    "create_table",
    "insecure_plaintext",
];
const DEFAULT_TIMEOUT_MS: u32 = 10_000;
/// The largest backend message it reads.
const MAX_MESSAGE: usize = 1 << 20;

#[derive(Debug, Clone, PartialEq)]
struct Cfg {
    host: String,
    port: u16,
    database: String,
    user: String,
    /// Quoted identifier(s), ready for SQL.
    table: String,
    tls: bool,
    ca_pem: Option<String>,
    timeout_ms: u32,
    create_table: bool,
}

fn text(cfg: &Map, key: &str) -> Result<Option<String>, String> {
    match cfg.get(key) {
        None | Some(Value::Null) => Ok(None),
        Some(Value::Str(s)) if s.trim().is_empty() => Ok(None),
        Some(Value::Str(s)) => Ok(Some(s.trim().to_owned())),
        Some(_) => Err(format!("params.{key}: text")),
    }
}

/// `name` or `schema.name`, plain identifiers only, quoted.
fn table_ident(s: &str) -> Result<String, String> {
    let ok = |p: &str| {
        !p.is_empty()
            && p.len() <= 63
            && p.starts_with(|c: char| c.is_ascii_alphabetic() || c == '_')
            && p.chars().all(|c| c.is_ascii_alphanumeric() || c == '_')
    };
    let parts: Vec<&str> = s.split('.').collect();
    if parts.len() > 2 || !parts.iter().all(|p| ok(p)) {
        return Err(format!(
            "params.table: {s:?}: name or schema.name, letters, digits and _"
        ));
    }
    Ok(parts
        .iter()
        .map(|p| format!("\"{p}\""))
        .collect::<Vec<_>>()
        .join("."))
}

fn parse(cfg: &Map) -> Result<Cfg, String> {
    if let Some(k) = cfg.keys().find(|k| !KEYS.contains(&k.as_str())) {
        return Err(format!("params.{k}: unknown"));
    }
    let host = text(cfg, "host")?.ok_or("params.host: the server")?;
    let port = match cfg.get("port") {
        None => 5432,
        Some(v) => v
            .as_f64()
            .filter(|p| (1.0..=65535.0).contains(p))
            .map(|p| p as u16)
            .ok_or("params.port: 1 to 65535")?,
    };
    let tls = match text(cfg, "sslmode")?.as_deref() {
        None | Some("require") => true,
        Some("disable") => false,
        Some(m) => return Err(format!("params.sslmode: {m:?}: require or disable")),
    };
    let insecure = matches!(cfg.get("insecure_plaintext"), Some(Value::Bool(true)));
    if !tls && !loopback(&host) && !insecure {
        return Err(
            "params.sslmode: disable sends the password and the data in the clear; \
             only to loopback, or with insecure_plaintext"
                .into(),
        );
    }
    let timeout_ms = match cfg.get("timeout_ms") {
        None => DEFAULT_TIMEOUT_MS,
        Some(v) => v
            .as_f64()
            .filter(|t| (100.0..=60_000.0).contains(t))
            .map(|t| t as u32)
            .ok_or("params.timeout_ms: 100 to 60000")?,
    };
    let create_table = !matches!(cfg.get("create_table"), Some(Value::Bool(false)));
    Ok(Cfg {
        host,
        port,
        database: text(cfg, "database")?.ok_or("params.database: the database")?,
        user: text(cfg, "user")?.ok_or("params.user: the role")?,
        table: table_ident(&text(cfg, "table")?.unwrap_or_else(|| "wyrm_history".into()))?,
        tls,
        ca_pem: text(cfg, "ca_pem")?,
        timeout_ms,
        create_table,
    })
}

/// A string literal (`standard_conforming_strings` is on, checked at startup): quotes doubled;
/// NUL, which a text value cannot hold, is dropped.
fn literal(s: &str) -> String {
    format!("'{}'", s.replace('\0', "").replace('\'', "''"))
}

/// One row's VALUES tuple, or `None` for a value the table cannot hold.
fn tuple(r: &Row) -> Option<String> {
    let (value, value_text) = match &r.v {
        Value::Float(f) if f.is_finite() => (format!("{f:?}"), "NULL".to_owned()),
        Value::Float(_) => return None,
        Value::Int(i) => (format!("{i}"), "NULL".into()),
        Value::UInt(u) => (format!("{u}"), "NULL".into()),
        Value::Bool(b) => (u8::from(*b).to_string(), literal(&b.to_string())),
        Value::Str(s) => ("NULL".into(), literal(s)),
        Value::Null => ("NULL".into(), "NULL".into()),
        Value::Bytes(_) | Value::Array(_) | Value::Map(_) => return None,
    };
    Some(format!(
        "({}, {}, TIMESTAMPTZ 'epoch' + {} * INTERVAL '1 microsecond', {value}, {value_text}, {})",
        literal(&r.site),
        literal(&r.key),
        r.t,
        r.q.code()
    ))
}

/// The upsert of a batch, or `None` when no row can be written. A `(key, t)` that comes twice
/// keeps its last row: one statement may not change a row twice.
pub fn upsert(table: &str, rows: &[Row]) -> Option<String> {
    let mut last: HashMap<(&str, u64), usize> = HashMap::new();
    for (i, r) in rows.iter().enumerate() {
        last.insert((r.key.as_str(), r.t), i);
    }
    let tuples: Vec<String> = rows
        .iter()
        .enumerate()
        .filter(|(i, r)| last.get(&(r.key.as_str(), r.t)) == Some(i))
        .filter_map(|(_, r)| tuple(r))
        .collect();
    if tuples.is_empty() {
        return None;
    }
    Some(format!(
        "INSERT INTO {table} (site, key, t, value, value_text, quality) VALUES {} \
         ON CONFLICT (key, t) DO UPDATE SET site = EXCLUDED.site, value = EXCLUDED.value, \
         value_text = EXCLUDED.value_text, quality = EXCLUDED.quality",
        tuples.join(", ")
    ))
}

fn create(table: &str) -> String {
    format!(
        "CREATE TABLE IF NOT EXISTS {table} (site text NOT NULL, key text NOT NULL, \
         t timestamptz NOT NULL, value double precision, value_text text, \
         quality smallint NOT NULL, PRIMARY KEY (key, t))"
    )
}

/// A server error: its SQLSTATE and message.
#[derive(Debug, Clone, PartialEq)]
struct PgError {
    code: String,
    message: String,
}

impl PgError {
    /// What it means for the batch: a broken connection, something to wait for, or a stop.
    fn class(self) -> TargetError {
        let msg = format!("postgres {}: {}", self.code, self.message);
        let c = self.code.as_str();
        if c.starts_with("08") || c.starts_with("57P") {
            TargetError::Reconnect(msg)
        } else if c.starts_with("53") || matches!(c, "40001" | "40P01" | "55P03" | "57014") {
            TargetError::Retry(msg)
        } else {
            TargetError::Fatal(msg)
        }
    }
}

fn parse_error(body: &[u8]) -> PgError {
    let (mut code, mut message) = (String::new(), String::new());
    for f in body.split(|b| *b == 0) {
        match f.split_first() {
            Some((b'C', v)) => code = String::from_utf8_lossy(v).into_owned(),
            Some((b'M', v)) => message = String::from_utf8_lossy(v).into_owned(),
            _ => {}
        }
    }
    PgError { code, message }
}

/// One frontend message: type, length, body.
fn frame(kind: u8, body: &[u8]) -> Vec<u8> {
    let mut out = vec![kind];
    out.extend_from_slice(&((body.len() + 4) as u32).to_be_bytes());
    out.extend_from_slice(body);
    out
}

fn cstr(out: &mut Vec<u8>, s: &str) {
    out.extend_from_slice(s.as_bytes());
    out.push(0);
}

fn lost(e: impl std::fmt::Display) -> TargetError {
    TargetError::Reconnect(format!("postgres: {e}"))
}

/// PostgreSQL over one connection.
pub struct Pg {
    cfg: Cfg,
    conn: ConnId,
    /// Bytes read past the last message.
    buf: Vec<u8>,
}

impl Pg {
    fn send(&mut self, net: &mut dyn Host, bytes: &[u8]) -> Result<(), TargetError> {
        for chunk in bytes.chunks(64 << 10) {
            net.tcp_send(self.conn, chunk).map_err(|e| lost(e.msg))?;
        }
        Ok(())
    }

    /// The next backend message: its type and body.
    fn read(&mut self, net: &mut dyn Host) -> Result<(u8, Vec<u8>), TargetError> {
        loop {
            if self.buf.len() >= 5 {
                let len = u32::from_be_bytes([self.buf[1], self.buf[2], self.buf[3], self.buf[4]])
                    as usize;
                if !(4..=MAX_MESSAGE).contains(&len) {
                    return Err(lost(format!("message length {len}")));
                }
                if self.buf.len() > len {
                    let kind = self.buf[0];
                    let body = self.buf[5..1 + len].to_vec();
                    self.buf.drain(..1 + len);
                    return Ok((kind, body));
                }
            }
            let got = net
                .tcp_recv(self.conn, 64 << 10, self.cfg.timeout_ms)
                .map_err(|e| lost(e.msg))?;
            if got.is_empty() {
                return Err(lost("the server closed the connection"));
            }
            self.buf.extend_from_slice(&got);
        }
    }

    /// Run one statement (simple query) to ReadyForQuery; the first error wins.
    fn query(&mut self, net: &mut dyn Host, sql: &str) -> Result<(), TargetError> {
        let mut body = Vec::with_capacity(sql.len() + 1);
        cstr(&mut body, sql);
        self.send(net, &frame(b'Q', &body))?;
        let mut err = None;
        loop {
            let (kind, body) = self.read(net)?;
            match kind {
                b'E' if err.is_none() => err = Some(parse_error(&body)),
                b'Z' => break,
                _ => {}
            }
        }
        match err {
            Some(e) => Err(e.class()),
            None => Ok(()),
        }
    }

    /// Startup and authentication, to the first ReadyForQuery.
    fn startup(
        &mut self,
        net: &mut dyn Host,
        password: Option<&str>,
        tls: bool,
    ) -> Result<(), TargetError> {
        let mut body = 196_608u32.to_be_bytes().to_vec();
        for (k, v) in [
            ("user", self.cfg.user.as_str()),
            ("database", self.cfg.database.as_str()),
            ("application_name", "wyrm"),
            ("client_encoding", "UTF8"),
        ] {
            cstr(&mut body, k);
            cstr(&mut body, v);
        }
        body.push(0);
        let mut start = ((body.len() + 4) as u32).to_be_bytes().to_vec();
        start.extend_from_slice(&body);
        self.send(net, &start)?;
        let need =
            || TargetError::Fatal("postgres: the server asks for a password: Set Password".into());
        let mut scram: Option<(String, String, Option<String>)> = None;
        let mut conforming = false;
        loop {
            let (kind, body) = self.read(net)?;
            match kind {
                b'R' => {
                    let code = body
                        .get(..4)
                        .map(|b| u32::from_be_bytes([b[0], b[1], b[2], b[3]]))
                        .ok_or_else(|| lost("short auth message"))?;
                    let rest = &body[4..];
                    match code {
                        0 => {}
                        3 => {
                            if !tls && !loopback(&self.cfg.host) {
                                return Err(TargetError::Fatal(
                                    "postgres: the server wants the password in the clear \
                                     without TLS"
                                        .into(),
                                ));
                            }
                            let mut b = Vec::new();
                            cstr(&mut b, password.ok_or_else(need)?);
                            self.send(net, &frame(b'p', &b))?;
                        }
                        10 => {
                            let mechs: Vec<&[u8]> =
                                rest.split(|b| *b == 0).filter(|m| !m.is_empty()).collect();
                            if !mechs.contains(&&b"SCRAM-SHA-256"[..]) {
                                return Err(TargetError::Fatal(
                                    "postgres: no SCRAM-SHA-256 (channel binding only?)".into(),
                                ));
                            }
                            // no password: stop here, before any SASL message goes out
                            password.ok_or_else(need)?;
                            let nonce = scram::nonce(net.now_us(), self.conn.0);
                            let (first, bare) = scram::client_first("", &nonce);
                            let mut b = Vec::new();
                            cstr(&mut b, "SCRAM-SHA-256");
                            b.extend_from_slice(&(first.len() as u32).to_be_bytes());
                            b.extend_from_slice(first.as_bytes());
                            self.send(net, &frame(b'p', &b))?;
                            scram = Some((nonce, bare, None));
                        }
                        11 => {
                            let (nonce, bare, sig) = scram
                                .as_mut()
                                .ok_or_else(|| lost("SASL continue before start"))?;
                            let server_first = String::from_utf8_lossy(rest).into_owned();
                            let pw = password.ok_or_else(need)?;
                            let (fin, expected) =
                                scram::client_final(pw, nonce, bare, &server_first)
                                    .map_err(TargetError::Fatal)?;
                            *sig = Some(expected);
                            self.send(net, &frame(b'p', fin.as_bytes()))?;
                        }
                        12 => {
                            let expected = scram
                                .as_ref()
                                .and_then(|s| s.2.clone())
                                .ok_or_else(|| lost("SASL final before continue"))?;
                            scram::check_server_final(&String::from_utf8_lossy(rest), &expected)
                                .map_err(TargetError::Fatal)?;
                        }
                        5 => {
                            return Err(TargetError::Fatal(
                                "postgres: MD5 passwords are not supported: use scram-sha-256"
                                    .into(),
                            ))
                        }
                        c => return Err(TargetError::Fatal(format!("postgres: auth method {c}"))),
                    }
                }
                b'S' => {
                    let mut f = body.split(|b| *b == 0);
                    if f.next() == Some(b"standard_conforming_strings") {
                        conforming = f.next() == Some(b"on");
                    }
                }
                b'E' => return Err(parse_error(&body).class()),
                b'Z' => break,
                _ => {}
            }
        }
        if !conforming {
            return Err(TargetError::Fatal(
                "postgres: standard_conforming_strings is off".into(),
            ));
        }
        Ok(())
    }
}

impl Target for Pg {
    const KIND: &'static str = "postgres";
    const VERSION: &'static str = env!("CARGO_PKG_VERSION");

    fn check(cfg: &Map) -> Result<(), String> {
        parse(cfg).map(|_| ())
    }

    fn connect(net: &mut dyn Host, cfg: &Map, secret: Option<&str>) -> Result<Self, TargetError> {
        let cfg = parse(cfg).map_err(TargetError::Fatal)?;
        let conn = net
            .tcp_connect(&cfg.host, cfg.port, cfg.timeout_ms)
            .map_err(|e| lost(e.msg))?;
        let tls = cfg.tls;
        let mut pg = Pg {
            cfg,
            conn,
            buf: Vec::new(),
        };
        let r = (|| {
            if tls {
                // SSLRequest; the answer is one byte and nothing may follow it in the clear
                pg.send(net, &[0, 0, 0, 8, 4, 210, 22, 47])?;
                let got = net
                    .tcp_recv(pg.conn, 1, pg.cfg.timeout_ms)
                    .map_err(|e| lost(e.msg))?;
                match got.as_slice() {
                    b"S" => net
                        .tls_upgrade(
                            pg.conn,
                            &pg.cfg.host,
                            pg.cfg.timeout_ms,
                            pg.cfg.ca_pem.as_deref(),
                        )
                        .map_err(|e| lost(e.msg))?,
                    b"N" => {
                        return Err(TargetError::Fatal(
                            "postgres: the server refuses TLS (sslmode require)".into(),
                        ))
                    }
                    _ => return Err(lost("bad answer to SSLRequest")),
                }
            }
            pg.startup(net, secret, tls)
        })();
        if let Err(e) = r {
            net.tcp_close(pg.conn);
            return Err(e);
        }
        Ok(pg)
    }

    fn prepare(&mut self, net: &mut dyn Host) -> Result<(), TargetError> {
        if self.cfg.create_table {
            let sql = create(&self.cfg.table);
            self.query(net, &sql)?;
        }
        Ok(())
    }

    fn write(&mut self, net: &mut dyn Host, rows: &[Row]) -> Result<(), TargetError> {
        match upsert(&self.cfg.table, rows) {
            Some(sql) => self.query(net, &sql),
            None => Ok(()),
        }
    }

    fn ping(&mut self, net: &mut dyn Host) -> Result<(), TargetError> {
        self.query(net, "SELECT 1")
    }

    fn close(mut self, net: &mut dyn Host) {
        let _ = self.send(net, &frame(b'X', &[]));
        net.tcp_close(self.conn);
    }
}

// Only on wasm32: natively the exports would be bare global symbols.
#[cfg(all(feature = "wasm", target_arch = "wasm32"))]
wyrm_link_guest::export!(PgSync);

#[cfg(test)]
mod tests;
