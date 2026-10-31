//! History sync to MongoDB (ADR 0026): the [`Mongo`] target writes a history sink's batches
//! into one collection over OP_MSG, TLS from the first byte (Atlas) or plain to loopback, with
//! SCRAM-SHA-256. One document per row, `_id: {k: <key>, t: <µs>}` with `site`, `key`, `t`
//! (µs), `ts` (a date, for queries and a TTL index), `value` and `quality`; a batch is one
//! `update` of replace-upserts with `ordered: false`, so a batch sent twice changes nothing.
//!
//! Params (besides `sink`, `batch`, `idle_s`, `retry_s`): `host` (the primary, or a mongos:
//! `mongodb+srv` names are not resolved), `port` (27017), `database`, `collection`
//! (`wyrm_history`), `user`, `auth_source` (`admin`), `tls` (true; false only to loopback
//! unless `insecure_plaintext`), `ca_pem`, `timeout_ms` (10 000), `ttl_days` (0: no TTL index).
//! The password goes in with ▸ Set Password (ASCII: it is not SASLprep-normalised).

mod bson;

use bson::{doc, get, num, Doc, B};
use std::collections::HashMap;
use wyrm_core::Value;
use wyrm_history_sync::http::loopback;
use wyrm_history_sync::{scram, Map, Row, SyncApp, Target, TargetError};
use wyrm_link_api::{ConnId, Host};

/// The app: `Portable<MongoSync>` embedded or as a process, `export!(MongoSync)` in WASM.
pub type MongoSync = SyncApp<Mongo>;

const KEYS: [&str; 11] = [
    "host",
    "port",
    "database",
    "collection",
    "user",
    "auth_source",
    "tls",
    "ca_pem",
    "timeout_ms",
    "ttl_days",
    "insecure_plaintext",
];
const DEFAULT_TIMEOUT_MS: u32 = 10_000;
/// The largest server message it reads (MongoDB's own bound is 48 MB).
const MAX_MESSAGE: usize = 16 << 20;
const OP_MSG: i32 = 2013;

#[derive(Debug, Clone, PartialEq)]
struct Cfg {
    host: String,
    port: u16,
    database: String,
    collection: String,
    user: Option<String>,
    auth_source: String,
    tls: bool,
    ca_pem: Option<String>,
    timeout_ms: u32,
    ttl_s: Option<i64>,
}

fn text(cfg: &Map, key: &str) -> Result<Option<String>, String> {
    match cfg.get(key) {
        None | Some(Value::Null) => Ok(None),
        Some(Value::Str(s)) if s.trim().is_empty() => Ok(None),
        Some(Value::Str(s)) => Ok(Some(s.trim().to_owned())),
        Some(_) => Err(format!("params.{key}: text")),
    }
}

/// A database or collection name MongoDB takes, without `$`, `.`-tricks or NUL.
fn name(s: &str, what: &str) -> Result<String, String> {
    if s.is_empty()
        || s.len() > 64
        || !s
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-')
    {
        return Err(format!("params.{what}: {s:?}: letters, digits, _ and -"));
    }
    Ok(s.to_owned())
}

fn parse(cfg: &Map) -> Result<Cfg, String> {
    if let Some(k) = cfg.keys().find(|k| !KEYS.contains(&k.as_str())) {
        return Err(format!("params.{k}: unknown"));
    }
    let host = text(cfg, "host")?.ok_or("params.host: the primary or a mongos")?;
    let port = match cfg.get("port") {
        None => 27017,
        Some(v) => v
            .as_f64()
            .filter(|p| (1.0..=65535.0).contains(p))
            .map(|p| p as u16)
            .ok_or("params.port: 1 to 65535")?,
    };
    let tls = !matches!(cfg.get("tls"), Some(Value::Bool(false)));
    let insecure = matches!(cfg.get("insecure_plaintext"), Some(Value::Bool(true)));
    if !tls && !loopback(&host) && !insecure {
        return Err(
            "params.tls: false sends the password and the data in the clear; only to \
                    loopback, or with insecure_plaintext"
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
    let ttl_s = match cfg.get("ttl_days") {
        None => None,
        Some(v) => {
            let d = v
                .as_f64()
                .filter(|d| (0.0..=36_500.0).contains(d))
                .ok_or("params.ttl_days: 0 to 36500")?;
            (d > 0.0).then_some((d * 86_400.0) as i64)
        }
    };
    Ok(Cfg {
        host,
        port,
        database: name(
            &text(cfg, "database")?.ok_or("params.database: the database")?,
            "database",
        )?,
        collection: name(
            &text(cfg, "collection")?.unwrap_or_else(|| "wyrm_history".into()),
            "collection",
        )?,
        user: text(cfg, "user")?,
        auth_source: name(
            &text(cfg, "auth_source")?.unwrap_or_else(|| "admin".into()),
            "auth_source",
        )?,
        tls,
        ca_pem: text(cfg, "ca_pem")?,
        timeout_ms,
        ttl_s,
    })
}

/// A row's value as BSON, or `None` for one a document cannot hold here.
fn value(v: &Value) -> Option<B> {
    Some(match v {
        Value::Float(f) if f.is_finite() => B::Double(*f),
        Value::Float(_) => return None,
        Value::Int(i) => B::Int64(*i),
        Value::UInt(u) => i64::try_from(*u).map_or(B::Double(*u as f64), B::Int64),
        Value::Bool(b) => B::Bool(*b),
        Value::Str(s) => B::Str(s.clone()),
        Value::Null => B::Null,
        Value::Bytes(_) | Value::Array(_) | Value::Map(_) => return None,
    })
}

/// The `update` command of a batch: one replace-upsert per `(key, t)` (its last row).
pub fn update_command(database: &str, collection: &str, rows: &[Row]) -> Option<Doc> {
    let mut last: HashMap<(&str, u64), usize> = HashMap::new();
    for (i, r) in rows.iter().enumerate() {
        last.insert((r.key.as_str(), r.t), i);
    }
    let updates: Vec<B> = rows
        .iter()
        .enumerate()
        .filter(|(i, r)| last.get(&(r.key.as_str(), r.t)) == Some(i))
        .filter_map(|(_, r)| {
            let t = i64::try_from(r.t).ok()?;
            let id = B::Doc(doc([("k", B::Str(r.key.clone())), ("t", B::Int64(t))]));
            let d = doc([
                ("_id", id.clone()),
                ("site", B::Str(r.site.clone())),
                ("key", B::Str(r.key.clone())),
                ("t", B::Int64(t)),
                ("ts", B::Date(t / 1000)),
                ("value", value(&r.v)?),
                ("quality", B::Int32(i32::from(r.q.code()))),
            ]);
            Some(B::Doc(doc([
                ("q", B::Doc(doc([("_id", id)]))),
                ("u", B::Doc(d)),
                ("upsert", B::Bool(true)),
            ])))
        })
        .collect();
    if updates.is_empty() {
        return None;
    }
    Some(doc([
        ("update", B::Str(collection.to_owned())),
        ("updates", B::Arr(updates)),
        ("ordered", B::Bool(false)),
        ("$db", B::Str(database.to_owned())),
    ]))
}

/// What a server error code means for the batch.
fn class(code: i64, msg: String) -> TargetError {
    match code {
        // not the primary any more, shutting down, network
        6 | 7 | 89 | 91 | 189 | 9001 | 10107 | 11600 | 11602 | 13435 | 13436 => {
            TargetError::Reconnect(msg)
        }
        // time limits, write conflicts, too busy
        50 | 112 | 262 | 16500 | 462 => TargetError::Retry(msg),
        _ => TargetError::Fatal(msg),
    }
}

/// An answer's failure: `ok: 0`, or the first write error.
fn judge(d: &Doc, what: &str) -> Result<(), TargetError> {
    if num(d, "ok") != Some(1.0) {
        let code = num(d, "code").unwrap_or(0.0) as i64;
        let msg = match get(d, "errmsg") {
            Some(B::Str(s)) => s.clone(),
            _ => String::new(),
        };
        return Err(class(code, format!("mongodb {what}: {code} {msg}")));
    }
    if let Some(B::Arr(errs)) = get(d, "writeErrors") {
        if let Some(B::Doc(e)) = errs.first() {
            let code = num(e, "code").unwrap_or(0.0) as i64;
            let msg = match get(e, "errmsg") {
                Some(B::Str(s)) => s.clone(),
                _ => String::new(),
            };
            return Err(class(
                code,
                format!(
                    "mongodb {what}: {} write errors, first {code} {msg}",
                    errs.len()
                ),
            ));
        }
    }
    Ok(())
}

fn lost(e: impl std::fmt::Display) -> TargetError {
    TargetError::Reconnect(format!("mongodb: {e}"))
}

/// MongoDB over one connection.
pub struct Mongo {
    cfg: Cfg,
    conn: ConnId,
    buf: Vec<u8>,
    request: i32,
}

impl Mongo {
    /// One command (OP_MSG, one body section) and its answer.
    fn command(&mut self, net: &mut dyn Host, cmd: &Doc) -> Result<Doc, TargetError> {
        let body = bson::write(cmd);
        self.request = self.request.wrapping_add(1);
        let len = 16 + 4 + 1 + body.len();
        if len > MAX_MESSAGE {
            return Err(TargetError::Fatal(
                "mongodb: a command over 16 MiB: lower batch".into(),
            ));
        }
        let mut msg = Vec::with_capacity(len);
        msg.extend_from_slice(&(len as i32).to_le_bytes());
        msg.extend_from_slice(&self.request.to_le_bytes());
        msg.extend_from_slice(&0i32.to_le_bytes());
        msg.extend_from_slice(&OP_MSG.to_le_bytes());
        msg.extend_from_slice(&0u32.to_le_bytes());
        msg.push(0);
        msg.extend_from_slice(&body);
        for chunk in msg.chunks(64 << 10) {
            net.tcp_send(self.conn, chunk).map_err(|e| lost(e.msg))?;
        }
        loop {
            if self.buf.len() >= 4 {
                let n = i32::from_le_bytes([self.buf[0], self.buf[1], self.buf[2], self.buf[3]]);
                let n = usize::try_from(n)
                    .ok()
                    .filter(|n| (21..=MAX_MESSAGE).contains(n))
                    .ok_or_else(|| lost("bad message length"))?;
                if self.buf.len() >= n {
                    let m: Vec<u8> = self.buf.drain(..n).collect();
                    let to = i32::from_le_bytes([m[8], m[9], m[10], m[11]]);
                    let op = i32::from_le_bytes([m[12], m[13], m[14], m[15]]);
                    if op != OP_MSG || to != self.request || m[20] != 0 {
                        return Err(lost("an answer that is not ours"));
                    }
                    return bson::read(&m[21..]).map_err(lost);
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

    /// SCRAM-SHA-256 through saslStart and saslContinue.
    fn login(&mut self, net: &mut dyn Host, user: &str, password: &str) -> Result<(), TargetError> {
        let db = self.cfg.auth_source.clone();
        let nonce = scram::nonce(net.now_us(), self.conn.0);
        let (first, bare) = scram::client_first(user, &nonce);
        let r = self.command(
            net,
            &doc([
                ("saslStart", B::Int32(1)),
                ("mechanism", B::Str("SCRAM-SHA-256".into())),
                ("payload", B::Bin(first.into_bytes())),
                ("autoAuthorize", B::Int32(1)),
                ("$db", B::Str(db.clone())),
            ]),
        )?;
        judge(&r, "login").map_err(|e| TargetError::Fatal(e.message().to_owned()))?;
        let conversation = get(&r, "conversationId")
            .cloned()
            .ok_or_else(|| lost("no conversation"))?;
        let Some(B::Bin(server_first)) = get(&r, "payload") else {
            return Err(lost("no server-first message"));
        };
        let (fin, expected) = scram::client_final(
            password,
            &nonce,
            &bare,
            &String::from_utf8_lossy(server_first),
        )
        .map_err(TargetError::Fatal)?;
        let mut payload = fin.into_bytes();
        let mut checked = false;
        for _ in 0..3 {
            let r = self.command(
                net,
                &doc([
                    ("saslContinue", B::Int32(1)),
                    ("conversationId", conversation.clone()),
                    ("payload", B::Bin(std::mem::take(&mut payload))),
                    ("$db", B::Str(db.clone())),
                ]),
            )?;
            judge(&r, "login").map_err(|e| TargetError::Fatal(e.message().to_owned()))?;
            if !checked {
                let Some(B::Bin(server_final)) = get(&r, "payload") else {
                    return Err(lost("no server-final message"));
                };
                scram::check_server_final(&String::from_utf8_lossy(server_final), &expected)
                    .map_err(TargetError::Fatal)?;
                checked = true;
            }
            if matches!(get(&r, "done"), Some(B::Bool(true))) {
                return Ok(());
            }
        }
        Err(lost("login did not end"))
    }
}

impl Target for Mongo {
    const KIND: &'static str = "mongodb";
    const VERSION: &'static str = env!("CARGO_PKG_VERSION");

    fn check(cfg: &Map) -> Result<(), String> {
        parse(cfg).map(|_| ())
    }

    fn connect(net: &mut dyn Host, cfg: &Map, secret: Option<&str>) -> Result<Self, TargetError> {
        let cfg = parse(cfg).map_err(TargetError::Fatal)?;
        if cfg.user.is_some() && secret.is_none() {
            return Err(TargetError::Fatal(
                "mongodb: a user and no password: Set Password".into(),
            ));
        }
        let conn = if cfg.tls {
            net.tls_connect(&cfg.host, cfg.port, cfg.timeout_ms, cfg.ca_pem.as_deref())
        } else {
            net.tcp_connect(&cfg.host, cfg.port, cfg.timeout_ms)
        }
        .map_err(|e| lost(e.msg))?;
        let mut m = Mongo {
            cfg,
            conn,
            buf: Vec::new(),
            request: 0,
        };
        let r = match (m.cfg.user.clone(), secret) {
            (Some(user), Some(pw)) => m.login(net, &user, pw),
            _ => Ok(()),
        };
        if let Err(e) = r {
            net.tcp_close(m.conn);
            return Err(e);
        }
        Ok(m)
    }

    fn prepare(&mut self, net: &mut dyn Host) -> Result<(), TargetError> {
        let Some(ttl) = self.cfg.ttl_s else {
            return Ok(());
        };
        let r = self.command(
            net,
            &doc([
                ("createIndexes", B::Str(self.cfg.collection.clone())),
                (
                    "indexes",
                    B::Arr(vec![B::Doc(doc([
                        ("key", B::Doc(doc([("ts", B::Int32(1))]))),
                        ("name", B::Str("wyrm_ttl".into())),
                        ("expireAfterSeconds", B::Int64(ttl)),
                    ]))]),
                ),
                ("$db", B::Str(self.cfg.database.clone())),
            ]),
        )?;
        judge(&r, "create index")
    }

    fn write(&mut self, net: &mut dyn Host, rows: &[Row]) -> Result<(), TargetError> {
        let Some(cmd) = update_command(&self.cfg.database, &self.cfg.collection, rows) else {
            return Ok(());
        };
        let r = self.command(net, &cmd)?;
        judge(&r, "write")
    }

    fn ping(&mut self, net: &mut dyn Host) -> Result<(), TargetError> {
        let r = self.command(
            net,
            &doc([("ping", B::Int32(1)), ("$db", B::Str("admin".into()))]),
        )?;
        judge(&r, "ping")
    }

    fn close(self, net: &mut dyn Host) {
        net.tcp_close(self.conn);
    }
}

// Only on wasm32: natively the exports would be bare global symbols.
#[cfg(all(feature = "wasm", target_arch = "wasm32"))]
wyrm_link_guest::export!(MongoSync);

#[cfg(test)]
mod tests;
