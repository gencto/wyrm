//! History sync to MySQL and MariaDB (ADR 0026): the [`My`] target writes a history sink's
//! batches into one table over the client/server protocol 41, with TLS by `SSLRequest`,
//! `caching_sha2_password` (the full login sends the password only over TLS: no RSA exchange)
//! or `mysql_native_password`.
//!
//! The table (made with `create_table`, default on): `` site VARCHAR(255), `key`
//! VARCHAR(700), t DATETIME(6), value DOUBLE, value_text TEXT, quality SMALLINT, PRIMARY KEY
//! (`key`, t) ``, utf8mb4; a row with the same `(key, t)` is replaced. Text goes in as hex
//! literals, so no `sql_mode` changes what it means. A number goes to `value` (a bool as 1 or 0,
//! its text too), text to `value_text`, null to neither; a row holding bytes, a list or a map,
//! or a key over 700 characters, is skipped.
//!
//! Params (besides `sink`, `batch`, `idle_s`, `retry_s`): `host`, `port` (3306), `database`,
//! `user`, `table` (`wyrm_history`), `ssl` (`require`, default, or `disable`: only to loopback
//! unless `insecure_plaintext`), `ca_pem`, `timeout_ms` (10 000), `create_table` (true). The
//! password goes in with ▸ Set Password.

use sha1::Sha1;
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use wyrm_core::Value;
use wyrm_history_sync::http::loopback;
use wyrm_history_sync::{Map, Row, SyncApp, Target, TargetError};
use wyrm_link_api::{ConnId, Host};

/// The app: `Portable<MySync>` embedded or as a process, `export!(MySync)` in WASM.
pub type MySync = SyncApp<My>;

const KEYS: [&str; 10] = [
    "host",
    "port",
    "database",
    "user",
    "table",
    "ssl",
    "ca_pem",
    "timeout_ms",
    "create_table",
    "insecure_plaintext",
];
const DEFAULT_TIMEOUT_MS: u32 = 10_000;
/// The longest key that fits the primary key (utf8mb4, InnoDB's 3072 bytes).
const MAX_KEY: usize = 700;
/// The largest packet either side sends (one packet per statement, no splitting).
const MAX_PACKET: usize = (1 << 24) - 1;
/// utf8mb4_general_ci: MySQL and MariaDB both know it.
const UTF8MB4: u8 = 45;

const CLIENT_CONNECT_WITH_DB: u32 = 0x8;
const CLIENT_PROTOCOL_41: u32 = 0x200;
const CLIENT_SSL: u32 = 0x800;
const CLIENT_TRANSACTIONS: u32 = 0x2000;
const CLIENT_SECURE_CONNECTION: u32 = 0x8000;
const CLIENT_PLUGIN_AUTH: u32 = 0x8_0000;
const CLIENT_PLUGIN_AUTH_LENENC: u32 = 0x20_0000;

#[derive(Debug, Clone, PartialEq)]
struct Cfg {
    host: String,
    port: u16,
    database: String,
    user: String,
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

/// A plain identifier, quoted with backticks.
fn ident(s: &str, what: &str) -> Result<String, String> {
    if s.is_empty()
        || s.len() > 64
        || !s.starts_with(|c: char| c.is_ascii_alphabetic() || c == '_')
        || !s.chars().all(|c| c.is_ascii_alphanumeric() || c == '_')
    {
        return Err(format!("params.{what}: {s:?}: letters, digits and _"));
    }
    Ok(format!("`{s}`"))
}

fn parse(cfg: &Map) -> Result<Cfg, String> {
    if let Some(k) = cfg.keys().find(|k| !KEYS.contains(&k.as_str())) {
        return Err(format!("params.{k}: unknown"));
    }
    let host = text(cfg, "host")?.ok_or("params.host: the server")?;
    let port = match cfg.get("port") {
        None => 3306,
        Some(v) => v
            .as_f64()
            .filter(|p| (1.0..=65535.0).contains(p))
            .map(|p| p as u16)
            .ok_or("params.port: 1 to 65535")?,
    };
    let tls = match text(cfg, "ssl")?.as_deref() {
        None | Some("require") => true,
        Some("disable") => false,
        Some(m) => return Err(format!("params.ssl: {m:?}: require or disable")),
    };
    let insecure = matches!(cfg.get("insecure_plaintext"), Some(Value::Bool(true)));
    if !tls && !loopback(&host) && !insecure {
        return Err(
            "params.ssl: disable sends the data in the clear; only to loopback, or \
                    with insecure_plaintext"
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
    let database = text(cfg, "database")?.ok_or("params.database: the database")?;
    ident(&database, "database")?;
    Ok(Cfg {
        host,
        port,
        database,
        user: text(cfg, "user")?.ok_or("params.user: the user")?,
        table: ident(
            &text(cfg, "table")?.unwrap_or_else(|| "wyrm_history".into()),
            "table",
        )?,
        tls,
        ca_pem: text(cfg, "ca_pem")?,
        timeout_ms,
        create_table: !matches!(cfg.get("create_table"), Some(Value::Bool(false))),
    })
}

/// Text as a utf8mb4 hex literal: nothing in it is ever read as SQL.
fn hex_text(s: &str) -> String {
    let hex: String = s.bytes().map(|b| format!("{b:02X}")).collect();
    format!("CONVERT(X'{hex}' USING utf8mb4)")
}

fn tuple(r: &Row) -> Option<String> {
    if r.key.chars().count() > MAX_KEY {
        return None;
    }
    let (value, value_text) = match &r.v {
        Value::Float(f) if f.is_finite() => (format!("{f:?}"), "NULL".to_owned()),
        Value::Float(_) => return None,
        Value::Int(i) => (i.to_string(), "NULL".into()),
        Value::UInt(u) => (u.to_string(), "NULL".into()),
        Value::Bool(b) => (u8::from(*b).to_string(), hex_text(&b.to_string())),
        Value::Str(s) => ("NULL".into(), hex_text(s)),
        Value::Null => ("NULL".into(), "NULL".into()),
        Value::Bytes(_) | Value::Array(_) | Value::Map(_) => return None,
    };
    Some(format!(
        "({}, {}, TIMESTAMP '1970-01-01 00:00:00' + INTERVAL {} MICROSECOND, {value}, {value_text}, {})",
        hex_text(&r.site),
        hex_text(&r.key),
        r.t,
        r.q.code()
    ))
}

/// The upsert of a batch, or `None` when no row can be written; the last row of each `(key, t)`.
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
        "INSERT INTO {table} (site, `key`, t, value, value_text, quality) VALUES {} \
         ON DUPLICATE KEY UPDATE site = VALUES(site), value = VALUES(value), \
         value_text = VALUES(value_text), quality = VALUES(quality)",
        tuples.join(", ")
    ))
}

fn create(table: &str) -> String {
    format!(
        "CREATE TABLE IF NOT EXISTS {table} (site VARCHAR(255) NOT NULL, `key` VARCHAR({MAX_KEY}) \
         NOT NULL, t DATETIME(6) NOT NULL, value DOUBLE NULL, value_text TEXT NULL, \
         quality SMALLINT NOT NULL, PRIMARY KEY (`key`, t)) CHARACTER SET utf8mb4"
    )
}

/// `mysql_native_password`: SHA1(pw) XOR SHA1(nonce + SHA1(SHA1(pw))).
fn native_scramble(password: &str, nonce: &[u8]) -> Vec<u8> {
    let p1 = Sha1::digest(password.as_bytes());
    let p2 = Sha1::digest(p1);
    let mut h = Sha1::new();
    h.update(nonce);
    h.update(p2);
    p1.iter().zip(h.finalize()).map(|(a, b)| a ^ b).collect()
}

/// `caching_sha2_password`: SHA256(pw) XOR SHA256(SHA256(SHA256(pw)) + nonce).
fn sha2_scramble(password: &str, nonce: &[u8]) -> Vec<u8> {
    let p1 = Sha256::digest(password.as_bytes());
    let p2 = Sha256::digest(p1);
    let mut h = Sha256::new();
    h.update(p2);
    h.update(nonce);
    p1.iter().zip(h.finalize()).map(|(a, b)| a ^ b).collect()
}

/// The answer to an auth plugin's challenge (an empty password answers nothing).
fn scramble(plugin: &str, password: &str, nonce: &[u8]) -> Result<Vec<u8>, TargetError> {
    if password.is_empty() {
        return Ok(Vec::new());
    }
    match plugin {
        "mysql_native_password" => Ok(native_scramble(password, nonce)),
        "caching_sha2_password" => Ok(sha2_scramble(password, nonce)),
        p => Err(TargetError::Fatal(format!(
            "mysql: auth plugin {p} is not supported"
        ))),
    }
}

fn lost(e: impl std::fmt::Display) -> TargetError {
    TargetError::Reconnect(format!("mysql: {e}"))
}

/// An ERR packet: its code, SQL state and message, as what it means for the batch.
fn err_packet(p: &[u8]) -> TargetError {
    let code = p.get(1..3).map_or(0, |c| u16::from_le_bytes([c[0], c[1]]));
    let rest = p.get(3..).unwrap_or_default();
    let (state, msg) = match rest.strip_prefix(b"#") {
        Some(r) if r.len() >= 5 => (
            String::from_utf8_lossy(&r[..5]).into_owned(),
            String::from_utf8_lossy(&r[5..]).into_owned(),
        ),
        _ => (String::new(), String::from_utf8_lossy(rest).into_owned()),
    };
    let m = format!("mysql {code} ({state}): {msg}");
    match code {
        // server going away, connection killed
        1053 | 1077 | 1152 | 1153 | 1154 | 1156 | 1159 | 1161 => TargetError::Reconnect(m),
        // deadlock, lock wait, too many connections, out of resources
        1040 | 1041 | 1203 | 1205 | 1213 | 1226 => TargetError::Retry(m),
        _ => TargetError::Fatal(m),
    }
}

/// MySQL over one connection.
pub struct My {
    cfg: Cfg,
    conn: ConnId,
    buf: Vec<u8>,
    seq: u8,
}

impl My {
    fn send(&mut self, net: &mut dyn Host, payload: &[u8]) -> Result<(), TargetError> {
        if payload.len() >= MAX_PACKET {
            return Err(TargetError::Fatal(
                "mysql: a statement over 16 MiB: lower batch".into(),
            ));
        }
        let len = payload.len() as u32;
        let mut out = len.to_le_bytes()[..3].to_vec();
        out.push(self.seq);
        self.seq = self.seq.wrapping_add(1);
        out.extend_from_slice(payload);
        for chunk in out.chunks(64 << 10) {
            net.tcp_send(self.conn, chunk).map_err(|e| lost(e.msg))?;
        }
        Ok(())
    }

    fn read(&mut self, net: &mut dyn Host) -> Result<Vec<u8>, TargetError> {
        loop {
            if self.buf.len() >= 4 {
                let len = u32::from_le_bytes([self.buf[0], self.buf[1], self.buf[2], 0]) as usize;
                if len >= MAX_PACKET {
                    return Err(lost("a packet over 16 MiB"));
                }
                if self.buf.len() >= 4 + len {
                    self.seq = self.buf[3].wrapping_add(1);
                    let p = self.buf[4..4 + len].to_vec();
                    self.buf.drain(..4 + len);
                    return Ok(p);
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

    /// One command; OK is success, ERR its error. Statements here return no rows.
    fn command(&mut self, net: &mut dyn Host, cmd: u8, arg: &[u8]) -> Result<(), TargetError> {
        self.seq = 0;
        let mut p = vec![cmd];
        p.extend_from_slice(arg);
        self.send(net, &p)?;
        let r = self.read(net)?;
        match r.first() {
            Some(0x00) => Ok(()),
            Some(0xff) => Err(err_packet(&r)),
            _ => Err(lost("unexpected answer (a result set?)")),
        }
    }

    fn query(&mut self, net: &mut dyn Host, sql: &str) -> Result<(), TargetError> {
        self.command(net, 0x03, sql.as_bytes())
    }

    /// The greeting, TLS, the login.
    fn handshake(&mut self, net: &mut dyn Host, password: &str) -> Result<(), TargetError> {
        let g = self.read(net)?;
        if g.first() == Some(&0xff) {
            return Err(err_packet(&g));
        }
        if g.first() != Some(&10) {
            return Err(lost("not protocol 10"));
        }
        let short = || lost("short greeting");
        let ver_end = g[1..].iter().position(|b| *b == 0).ok_or_else(short)? + 1;
        let mut i = ver_end + 1 + 4; // connection id
        let mut nonce = g.get(i..i + 8).ok_or_else(short)?.to_vec();
        i += 9;
        let caps_lo = u16::from_le_bytes(
            g.get(i..i + 2)
                .ok_or_else(short)?
                .try_into()
                .map_err(|_| short())?,
        );
        i += 2 + 1 + 2; // caps low, charset, status
        let caps_hi = u16::from_le_bytes(
            g.get(i..i + 2)
                .ok_or_else(short)?
                .try_into()
                .map_err(|_| short())?,
        );
        let server_caps = u32::from(caps_lo) | (u32::from(caps_hi) << 16);
        i += 2;
        let auth_len = usize::from(*g.get(i).ok_or_else(short)?);
        i += 1 + 10;
        let part2 = auth_len.saturating_sub(8).max(13);
        let p2 = g.get(i..i + part2).ok_or_else(short)?;
        nonce.extend_from_slice(p2.strip_suffix(&[0]).unwrap_or(p2));
        i += part2;
        let plugin = g
            .get(i..)
            .and_then(|r| r.split(|b| *b == 0).next())
            .map(|p| String::from_utf8_lossy(p).into_owned())
            .unwrap_or_else(|| "mysql_native_password".into());
        let need = CLIENT_PROTOCOL_41 | CLIENT_SECURE_CONNECTION | CLIENT_PLUGIN_AUTH;
        if server_caps & need != need {
            return Err(TargetError::Fatal("mysql: the server is too old".into()));
        }
        let mut caps = need
            | CLIENT_CONNECT_WITH_DB
            | CLIENT_TRANSACTIONS
            | (server_caps & CLIENT_PLUGIN_AUTH_LENENC);
        let head = |caps: u32| {
            let mut h = caps.to_le_bytes().to_vec();
            h.extend_from_slice(&(MAX_PACKET as u32).to_le_bytes());
            h.push(UTF8MB4);
            h.extend_from_slice(&[0u8; 23]);
            h
        };
        if self.cfg.tls {
            if server_caps & CLIENT_SSL == 0 {
                return Err(TargetError::Fatal(
                    "mysql: the server has no TLS (ssl require)".into(),
                ));
            }
            caps |= CLIENT_SSL;
            // Nothing may come between the greeting and the handshake: bytes read in the clear
            // must never pass for what TLS protects (STARTTLS injection).
            if !self.buf.is_empty() {
                return Err(TargetError::Fatal(
                    "mysql: the server sent data before TLS".into(),
                ));
            }
            self.send(net, &head(caps))?;
            net.tls_upgrade(
                self.conn,
                &self.cfg.host,
                self.cfg.timeout_ms,
                self.cfg.ca_pem.as_deref(),
            )
            .map_err(|e| lost(e.msg))?;
        }
        let answer = scramble(&plugin, password, &nonce)?;
        let mut p = head(caps);
        p.extend_from_slice(self.cfg.user.as_bytes());
        p.push(0);
        // 20 or 32 bytes: one length byte, plain or length-encoded alike
        p.push(u8::try_from(answer.len()).map_err(|_| lost("auth answer too long"))?);
        p.extend_from_slice(&answer);
        p.extend_from_slice(self.cfg.database.as_bytes());
        p.push(0);
        p.extend_from_slice(plugin.as_bytes());
        p.push(0);
        self.send(net, &p)?;
        self.login(net, plugin, password)
    }

    /// The rest of the login: OK, ERR, an auth switch or caching_sha2's more data.
    fn login(
        &mut self,
        net: &mut dyn Host,
        mut plugin: String,
        password: &str,
    ) -> Result<(), TargetError> {
        for _ in 0..4 {
            let r = self.read(net)?;
            match r.first() {
                Some(0x00) => return Ok(()),
                Some(0xff) => return Err(err_packet(&r)),
                Some(0xfe) => {
                    // AuthSwitchRequest: plugin name, then its challenge
                    let rest = &r[1..];
                    let end = rest.iter().position(|b| *b == 0).unwrap_or(rest.len());
                    plugin = String::from_utf8_lossy(&rest[..end]).into_owned();
                    let nonce = rest.get(end + 1..).unwrap_or_default();
                    let nonce = nonce.strip_suffix(&[0]).unwrap_or(nonce);
                    let answer = scramble(&plugin, password, nonce)?;
                    self.send(net, &answer)?;
                }
                Some(0x01) if plugin == "caching_sha2_password" => match r.get(1) {
                    Some(3) => {} // fast auth: OK follows
                    Some(4) => {
                        // full auth: the password itself, only over TLS (no RSA exchange)
                        if !self.cfg.tls {
                            return Err(TargetError::Fatal(
                                "mysql: caching_sha2 full login needs TLS (ssl require)".into(),
                            ));
                        }
                        let mut p = password.as_bytes().to_vec();
                        p.push(0);
                        self.send(net, &p)?;
                    }
                    _ => return Err(lost("bad auth data")),
                },
                _ => return Err(lost("unexpected login answer")),
            }
        }
        Err(lost("login did not end"))
    }
}

impl Target for My {
    const KIND: &'static str = "mysql";
    const VERSION: &'static str = env!("CARGO_PKG_VERSION");

    fn check(cfg: &Map) -> Result<(), String> {
        parse(cfg).map(|_| ())
    }

    fn connect(net: &mut dyn Host, cfg: &Map, secret: Option<&str>) -> Result<Self, TargetError> {
        let cfg = parse(cfg).map_err(TargetError::Fatal)?;
        let conn = net
            .tcp_connect(&cfg.host, cfg.port, cfg.timeout_ms)
            .map_err(|e| lost(e.msg))?;
        let mut my = My {
            cfg,
            conn,
            buf: Vec::new(),
            seq: 0,
        };
        if let Err(e) = my.handshake(net, secret.unwrap_or_default()) {
            net.tcp_close(my.conn);
            return Err(e);
        }
        Ok(my)
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
        self.command(net, 0x0e, &[])
    }

    fn close(mut self, net: &mut dyn Host) {
        self.seq = 0;
        let _ = self.send(net, &[0x01]);
        net.tcp_close(self.conn);
    }
}

// Only on wasm32: natively the exports would be bare global symbols.
#[cfg(all(feature = "wasm", target_arch = "wasm32"))]
wyrm_link_guest::export!(MySync);

#[cfg(test)]
mod tests;
