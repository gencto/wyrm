//! Warm standby (ADR 0036, option 3, stage A): what the active broker hands
//! its standby over the peer link, from one queryable on
//! `wy/<site>/sys/replication/**` that the ACL opens to the CN
//! `standby:<site>` alone.
//!
//! * `wal/<store>/<after>/<max>`: the records of one control-plane WAL
//!   after LSN `after` (`state`: the registry, `flows`, `users`: the
//!   gateway's users), with the chain MAC at `after` and the last LSN:
//!   `{chain, last, records: [[lsn, mac, op], …]}`. The standby checks every
//!   record against its own chain with the shared key.
//! * `files`: `[{name, sha256}]` of the files that are not WALs and must
//!   follow the active: `secrets.bin` and every `links/<id>/token`.
//! * `file/<name>`: `{name, sha256, sealed}`: the file sealed with a key
//!   derived from `secrets.key` (both brokers hold it): the peer link is
//!   mTLS, and still no secret crosses it in clear.
//!
//! Each `wal/state` query tells how far the standby is: `sys/standby_connected`
//! and `sys/standby_lag` show it.

use super::*;
use sha2::Digest;
use wyrm_state::replicate::records_after;

/// The control-plane WALs a standby follows: name on the wire, directory
/// under `data_dir`, its HMAC key file.
pub const STORES: [(&str, &str, &str); 3] = [
    ("state", "state", "state.key"),
    ("flows", "flows/state", "flows.key"),
    ("users", "gateway/users", "gateway/hmac.key"),
];

/// Most records in one answer.
pub const MAX_RECORDS: usize = 512;

/// A standby counts as connected while its last query is younger than this.
pub const SEEN_FOR: Duration = Duration::from_secs(15);

/// When the standby last asked for the registry WAL, and how far behind it was.
#[derive(Debug, Clone, Copy)]
pub struct StandbySeen {
    pub at: std::time::Instant,
    /// The standby's LSN of the registry WAL.
    pub lsn: u64,
    /// Records of the registry WAL it had not received.
    pub lag: u64,
}

/// `wy/<site>/sys/replication`.
pub fn replication_key(site: &str) -> String {
    format!("wy/{site}/sys/replication")
}

/// The key the files travel under: derived from `secrets.key`, which both
/// brokers hold from the key bundle.
pub fn file_key(secrets_key: &[u8]) -> [u8; 32] {
    let mut h = sha2::Sha256::new();
    h.update(b"wyrm-replication-files");
    h.update(secrets_key);
    h.finalize().into()
}

/// The non-WAL files a standby follows, by name relative to `data_dir`.
pub fn files_of(data_dir: &Path) -> Vec<String> {
    let mut out = Vec::new();
    if data_dir.join("secrets.bin").is_file() {
        out.push("secrets.bin".to_owned());
    }
    if let Ok(links) = std::fs::read_dir(data_dir.join("links")) {
        let mut ids: Vec<String> = links
            .flatten()
            .filter(|e| e.path().join("token").is_file())
            .map(|e| e.file_name().to_string_lossy().into_owned())
            .collect();
        ids.sort();
        out.extend(ids.into_iter().map(|id| format!("links/{id}/token")));
    }
    out
}

/// `true` for a name [`files_of`] may give: no other file is served.
pub fn is_file_name(name: &str) -> bool {
    name == "secrets.bin"
        || name
            .strip_prefix("links/")
            .and_then(|r| r.strip_suffix("/token"))
            .is_some_and(|id| wyrm_core::keyspace::validate_segment(id).is_ok())
}

fn sha256(bytes: &[u8]) -> Vec<u8> {
    sha2::Sha256::digest(bytes).to_vec()
}

/// SHA-256 of each replicated file under `data_dir`, by name.
pub fn digests_of(data_dir: &Path) -> BTreeMap<String, Vec<u8>> {
    files_of(data_dir)
        .into_iter()
        .filter_map(|name| {
            let bytes = std::fs::read(data_dir.join(&name)).ok()?;
            Some((name, sha256(&bytes)))
        })
        .collect()
}

/// A page of one WAL as a value: `{chain, last, records: [[lsn, mac, op], …]}`.
pub fn page_value(page: &wyrm_state::replicate::Page) -> Value {
    Value::Map(BTreeMap::from([
        ("chain".to_owned(), Value::Bytes(page.chain.to_vec())),
        ("last".to_owned(), Value::UInt(page.last)),
        (
            "records".to_owned(),
            Value::Array(
                page.records
                    .iter()
                    .map(|r| {
                        Value::Array(vec![
                            Value::UInt(r.lsn),
                            Value::Bytes(r.mac.to_vec()),
                            Value::Bytes(r.payload.clone()),
                        ])
                    })
                    .collect(),
            ),
        ),
    ]))
}

/// The page a value of [`page_value`] holds, or `None` for anything else.
pub fn parse_page(v: Value) -> Option<wyrm_state::replicate::Page> {
    let Value::Map(mut m) = v else {
        return None;
    };
    let Some(Value::Bytes(chain)) = m.remove("chain") else {
        return None;
    };
    let chain: [u8; 32] = chain.try_into().ok()?;
    let Some(Value::UInt(last)) = m.remove("last") else {
        return None;
    };
    let Some(Value::Array(recs)) = m.remove("records") else {
        return None;
    };
    let mut records = Vec::with_capacity(recs.len());
    for r in recs {
        let Value::Array(mut parts) = r else {
            return None;
        };
        if parts.len() != 3 {
            return None;
        }
        let Value::Bytes(payload) = parts.remove(2) else {
            return None;
        };
        let Value::Bytes(mac) = parts.remove(1) else {
            return None;
        };
        let Value::UInt(lsn) = parts.remove(0) else {
            return None;
        };
        records.push(wyrm_state::replicate::RawRecord {
            lsn,
            mac: mac.try_into().ok()?,
            payload,
        });
    }
    Some(wyrm_state::replicate::Page {
        chain,
        last,
        records,
    })
}

fn error_value(why: &str) -> Value {
    Value::Map(BTreeMap::from([("error".to_owned(), Value::from(why))]))
}

impl Control {
    /// The standby's last registry query, if any.
    pub fn standby_seen(&self) -> Option<StandbySeen> {
        *self.standby_seen.lock().unwrap_or_else(|p| p.into_inner())
    }

    fn note_standby(&self, lsn: u64, last: u64) {
        *self.standby_seen.lock().unwrap_or_else(|p| p.into_inner()) = Some(StandbySeen {
            at: std::time::Instant::now(),
            lsn,
            lag: last.saturating_sub(lsn),
        });
    }

    /// Answer one replication query by its suffix under `sys/replication/`.
    fn replication_answer(&self, suffix: &str, file_key: &[u8; 32]) -> Value {
        let d = &self.cfg.data_dir;
        let parts: Vec<&str> = suffix.split('/').collect();
        match parts.as_slice() {
            ["wal", store, after, max] => {
                let Some((_, dir, _)) = STORES.iter().find(|(n, _, _)| n == store) else {
                    return error_value("unknown store");
                };
                let (Ok(after), Ok(max)) = (after.parse::<u64>(), max.parse::<usize>()) else {
                    return error_value("after and max: numbers");
                };
                match records_after(&d.join(dir), after, max.clamp(1, MAX_RECORDS)) {
                    Ok(page) => {
                        if *store == "state" {
                            self.note_standby(after, page.last);
                        }
                        page_value(&page)
                    }
                    Err(e) => error_value(&e.to_string()),
                }
            }
            ["files"] => Value::Array(
                files_of(d)
                    .into_iter()
                    .filter_map(|name| {
                        let bytes = std::fs::read(d.join(&name)).ok()?;
                        Some(Value::Map(BTreeMap::from([
                            ("name".to_owned(), Value::from(name)),
                            ("sha256".to_owned(), Value::Bytes(sha256(&bytes))),
                        ])))
                    })
                    .collect(),
            ),
            ["file", rest @ ..] => {
                let name = rest.join("/");
                if !is_file_name(&name) {
                    return error_value("not a replicated file");
                }
                match std::fs::read(d.join(&name)) {
                    Ok(bytes) => Value::Map(BTreeMap::from([
                        ("name".to_owned(), Value::from(name)),
                        ("sha256".to_owned(), Value::Bytes(sha256(&bytes))),
                        (
                            "sealed".to_owned(),
                            Value::Bytes(wyrm_link_sdk::seal::seal(file_key, &bytes)),
                        ),
                    ])),
                    Err(e) => error_value(&e.to_string()),
                }
            }
            _ => error_value("unknown replication key"),
        }
    }
}

/// Serve `wy/<site>/sys/replication/**` for the standby (one complete
/// queryable; the admin's own `sys/**` queryable is not complete, so the
/// standby asks this one alone).
pub(super) async fn serve_replication(ctl: Arc<Control>, session: Session) {
    let prefix = replication_key(&ctl.cfg.site);
    let file_key = match secret::load_or_create_key(&ctl.cfg.data_dir.join("secrets.key")) {
        Ok(k) => file_key(&k),
        Err(e) => {
            warn!("replication: secrets.key: {e}");
            return;
        }
    };
    let q = match session
        .declare_queryable(format!("{prefix}/**"))
        .complete(true)
        .await
    {
        Ok(q) => q,
        Err(e) => {
            warn!("replication queryable: {e}");
            return;
        }
    };
    while let Ok(query) = q.recv_async().await {
        let key = query.key_expr().to_string();
        let Some(suffix) = key.strip_prefix(&prefix).and_then(|s| s.strip_prefix('/')) else {
            continue;
        };
        let ctl = ctl.clone();
        let suffix = suffix.to_owned();
        // Reading a WAL is file I/O: off the session's thread.
        let value = tokio::task::spawn_blocking(move || ctl.replication_answer(&suffix, &file_key))
            .await
            .unwrap_or_else(|e| error_value(&e.to_string()));
        match wyrm_core::codec::to_vec(&value) {
            Ok(bytes) => {
                if let Err(e) = query.reply(&key, bytes).await {
                    debug!("replication reply: {e}");
                }
            }
            Err(e) => warn!("replication: {e}"),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pages_roundtrip_and_file_names() {
        let page = wyrm_state::replicate::Page {
            chain: [7; 32],
            last: 9,
            records: vec![wyrm_state::replicate::RawRecord {
                lsn: 9,
                mac: [1; 32],
                payload: vec![1, 2, 3],
            }],
        };
        let v = page_value(&page);
        let bytes = wyrm_core::codec::to_vec(&v).unwrap();
        let back = parse_page(wyrm_core::codec::from_slice(&bytes).unwrap()).unwrap();
        assert_eq!(back, page);
        assert!(parse_page(error_value("x")).is_none());
        assert!(is_file_name("secrets.bin"));
        assert!(is_file_name("links/plc1/token"));
        assert!(!is_file_name("links/../token"));
        assert!(!is_file_name("state.key"));
        assert!(!is_file_name("links/plc1/key"));
        assert_ne!(file_key(b"a"), file_key(b"b"));
    }
}
