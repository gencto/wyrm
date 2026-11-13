//! Warm standby (ADR 0036, option 3): what the active broker hands its
//! standby over the peer link, from one queryable on
//! `wy/<site>/sys/replication/**` that the ACL opens to the CN
//! `standby:<site>` alone.
//!
//! Stage A:
//! * `wal/<store>/<after>/<max>`: the records of one control-plane WAL
//!   after LSN `after` (`state`: the registry, `flows`, `users`: the
//!   gateway's users), with the chain MAC at `after` and the last LSN:
//!   `{chain, last, records: [[lsn, mac, op], …]}`. The standby checks every
//!   record against its own chain with the shared key.
//!
//! Stage B, files and the broker storage:
//! * `files`: `[{name, len, mtime}]` of every replicated file (see
//!   [`files_of`]): `secrets.bin`, `links/<id>/token`, the links' private
//!   data (`links/<id>/data/**`: portable stores, framework trees, the
//!   agent's store) and the installed packages (`packages/**`). The list is
//!   complete: a file not in it is gone.
//! * `file/<offset>/<len>/<name>`: one part of a file, `{name, offset,
//!   total, sha256?, sealed}`; `sha256` of the whole file comes with the
//!   first part. Every part is sealed with a key derived from
//!   `secrets.key` (both brokers hold it): the peer link is mTLS, and still
//!   no secret crosses it in clear.
//! * `storage/<epoch>/<since>/<max>`: the broker storage's changes after
//!   revision `since` of `epoch` (`wyrm_storage::Store::changes_since`):
//!   `{epoch, rev, full, put: [[path, rec]], delete: [path]}`.
//!
//! Stage C, the historian:
//! * `history/<after>/<max>`: the historian's change journal after `seq`
//!   `after` (`wyrm_history::Store::changes`, every series), as
//!   `{id, next, last, rows: [[seq, key, t, v, q], …]}`; `id` is the store's
//!   identity, so a standby keys its cursor by it; `sinks: {name: seq}`
//!   carries the confirmed cursor of every history sink, which the standby
//!   translates into its own journal numbers.
//!
//! A healed split: the former active, now following, moves aside what it
//! wrote while the other side was active too (a forked WAL, files the
//! active does not hold, a storage tree that differs) and reports each set
//! once with `forked/<t_ms>/<what>/<count>/<n>`: `what` = `state`,
//! `flows`, `users` (`count` WAL records, moved to `<dir>.stale.<n>`),
//! `files` or `storage` (`count` files or paths, moved to
//! `standby/stale/<t_ms>/`). The active writes one `standby_forked` audit
//! record per report and counts them in `sys/standby_forks`.
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
/// Most storage paths in one answer.
pub const MAX_STORAGE_PATHS: usize = 500;
/// Most history rows in one answer, and their stored bytes.
pub const MAX_HISTORY_ROWS: usize = 2000;
pub const MAX_HISTORY_BYTES: usize = 4 << 20;
/// Longest part of a file in one answer.
pub const PART_LEN: u64 = 1 << 20;
/// Files larger than this are not replicated (a package asset, an upload
/// spool): they are listed with their size and skipped by the standby.
pub const MAX_FILE_LEN: u64 = 64 << 20;
/// Most files listed.
pub const MAX_FILES: usize = 50_000;

/// A standby counts as connected while its last query is younger than this.
pub const SEEN_FOR: Duration = Duration::from_secs(15);

/// The key of the registry page that carries the active's hold: until this
/// time (unix ms) the standby does not count it as away (it rebuilds its
/// router and its listeners are closed).
pub const HOLD_UNTIL: &str = "hold_until";

/// The prefix of the cursor a standby keeps of an active's journal in its
/// own historian store (`standby-<id>`): not a sink of the site, never
/// carried over.
pub const STANDBY_SINK: &str = "standby-";

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

/// One replicated file as listed: its name relative to `data_dir`, length
/// and modification time (ns since the epoch, 0 when unknown).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FileEntry {
    pub name: String,
    pub len: u64,
    pub mtime: u64,
    /// The owner may execute it (a package's entry script or binary).
    pub exec: bool,
}

fn is_exec(m: &std::fs::Metadata) -> bool {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        m.permissions().mode() & 0o100 != 0
    }
    #[cfg(not(unix))]
    {
        let _ = m;
        false
    }
}

fn mtime_ns(m: &std::fs::Metadata) -> u64 {
    m.modified()
        .ok()
        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|d| d.as_nanos() as u64)
        .unwrap_or(0)
}

/// A directory entry name that is being written or is scratch: left out.
pub(super) fn skipped(name: &str) -> bool {
    name.ends_with(".tmp")
        || name.starts_with(".tmp")
        || name == "tmp"
        || name == "uploads"
        || name == "agent.next"
        || name == "LOCK"
}

pub(super) fn walk(root: &Path, rel: &str, out: &mut Vec<FileEntry>) {
    let Ok(dir) = std::fs::read_dir(root.join(rel)) else {
        return;
    };
    let mut entries: Vec<_> = dir.flatten().collect();
    entries.sort_by_key(|e| e.file_name());
    for e in entries {
        if out.len() >= MAX_FILES {
            return;
        }
        let name = e.file_name().to_string_lossy().into_owned();
        if skipped(&name) {
            continue;
        }
        let Ok(meta) = e.metadata() else { continue };
        let path = if rel.is_empty() {
            name
        } else {
            format!("{rel}/{name}")
        };
        if meta.is_dir() {
            walk(root, &path, out);
        } else if meta.is_file() {
            out.push(FileEntry {
                name: path,
                len: meta.len(),
                mtime: mtime_ns(&meta),
                exec: is_exec(&meta),
            });
        }
    }
}

/// The replicated files under `data_dir`, by name relative to it, sorted:
/// `secrets.bin`, every `links/<id>/token` and `links/<id>/data/**`, and
/// `packages/**`. Scratch names ([`skipped`]) are left out.
pub fn files_of(data_dir: &Path) -> Vec<FileEntry> {
    let mut out = Vec::new();
    if let Ok(meta) = std::fs::metadata(data_dir.join("secrets.bin")) {
        if meta.is_file() {
            out.push(FileEntry {
                name: "secrets.bin".to_owned(),
                len: meta.len(),
                mtime: mtime_ns(&meta),
                exec: false,
            });
        }
    }
    if let Ok(links) = std::fs::read_dir(data_dir.join("links")) {
        let mut ids: Vec<String> = links
            .flatten()
            .filter(|e| e.path().is_dir())
            .map(|e| e.file_name().to_string_lossy().into_owned())
            .filter(|id| wyrm_core::keyspace::validate_segment(id).is_ok())
            .collect();
        ids.sort();
        for id in ids {
            let token = format!("links/{id}/token");
            if let Ok(meta) = std::fs::metadata(data_dir.join(&token)) {
                if meta.is_file() {
                    out.push(FileEntry {
                        name: token,
                        len: meta.len(),
                        mtime: mtime_ns(&meta),
                        exec: false,
                    });
                }
            }
            walk(data_dir, &format!("links/{id}/data"), &mut out);
        }
    }
    walk(data_dir, "packages", &mut out);
    out
}

/// `true` for a name [`files_of`] may give: no other file is served or
/// written. Every segment is a plain name (no `.`, `..`, separators).
pub fn is_file_name(name: &str) -> bool {
    let segs: Vec<&str> = name.split('/').collect();
    if segs
        .iter()
        .any(|s| s.is_empty() || *s == "." || *s == ".." || s.contains('\\') || skipped(s))
    {
        return false;
    }
    match segs.as_slice() {
        ["secrets.bin"] => true,
        ["links", id, "token"] => wyrm_core::keyspace::validate_segment(id).is_ok(),
        ["links", id, "data", _, ..] => wyrm_core::keyspace::validate_segment(id).is_ok(),
        ["packages", _, ..] => true,
        _ => false,
    }
}

/// SHA-256 of `bytes`.
pub fn sha256(bytes: &[u8]) -> Vec<u8> {
    sha2::Sha256::digest(bytes).to_vec()
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

/// The file list as a value: `[{name, len, mtime}]`.
pub fn files_value(files: &[FileEntry]) -> Value {
    Value::Array(
        files
            .iter()
            .map(|f| {
                Value::Map(BTreeMap::from([
                    ("name".to_owned(), Value::from(f.name.clone())),
                    ("len".to_owned(), Value::UInt(f.len)),
                    ("mtime".to_owned(), Value::UInt(f.mtime)),
                    ("exec".to_owned(), Value::Bool(f.exec)),
                ]))
            })
            .collect(),
    )
}

/// What [`files_value`] made; entries with a name this side would not
/// serve are dropped.
pub fn parse_files(v: Value) -> Option<Vec<FileEntry>> {
    let Value::Array(list) = v else {
        return None;
    };
    let mut out = Vec::with_capacity(list.len());
    for e in list {
        let Value::Map(mut m) = e else {
            return None;
        };
        let (Some(Value::Str(name)), Some(Value::UInt(len)), Some(Value::UInt(mtime))) =
            (m.remove("name"), m.remove("len"), m.remove("mtime"))
        else {
            return None;
        };
        let exec = matches!(m.remove("exec"), Some(Value::Bool(true)));
        if is_file_name(&name) {
            out.push(FileEntry {
                name,
                len,
                mtime,
                exec,
            });
        }
    }
    Some(out)
}

/// One part of a file as a value.
pub struct FilePart {
    pub name: String,
    pub offset: u64,
    pub total: u64,
    /// SHA-256 of the whole file, with the first part.
    pub sha256: Option<Vec<u8>>,
    pub sealed: Vec<u8>,
}

pub fn parse_part(v: Value) -> Option<FilePart> {
    let Value::Map(mut m) = v else {
        return None;
    };
    let (Some(Value::Str(name)), Some(Value::UInt(offset)), Some(Value::UInt(total))) =
        (m.remove("name"), m.remove("offset"), m.remove("total"))
    else {
        return None;
    };
    let sha256 = match m.remove("sha256") {
        Some(Value::Bytes(b)) => Some(b),
        _ => None,
    };
    let Some(Value::Bytes(sealed)) = m.remove("sealed") else {
        return None;
    };
    Some(FilePart {
        name,
        offset,
        total,
        sha256,
        sealed,
    })
}

/// The storage changes as a value.
pub fn changes_value(c: &wyrm_storage::Changes) -> Value {
    Value::Map(BTreeMap::from([
        ("epoch".to_owned(), Value::UInt(c.epoch)),
        ("rev".to_owned(), Value::UInt(c.rev)),
        ("full".to_owned(), Value::Bool(c.full)),
        (
            "put".to_owned(),
            Value::Array(
                c.put
                    .iter()
                    .map(|(p, r)| {
                        Value::Array(vec![Value::from(p.clone()), Value::Bytes(r.to_bytes())])
                    })
                    .collect(),
            ),
        ),
        (
            "delete".to_owned(),
            Value::Array(c.delete.iter().map(|p| Value::from(p.clone())).collect()),
        ),
    ]))
}

pub fn parse_changes(v: Value) -> Option<wyrm_storage::Changes> {
    let Value::Map(mut m) = v else {
        return None;
    };
    let (Some(Value::UInt(epoch)), Some(Value::UInt(rev)), Some(Value::Bool(full))) =
        (m.remove("epoch"), m.remove("rev"), m.remove("full"))
    else {
        return None;
    };
    let Some(Value::Array(put)) = m.remove("put") else {
        return None;
    };
    let Some(Value::Array(delete)) = m.remove("delete") else {
        return None;
    };
    let mut puts = Vec::with_capacity(put.len());
    for e in put {
        let Value::Array(mut pair) = e else {
            return None;
        };
        if pair.len() != 2 {
            return None;
        }
        let Value::Bytes(rec) = pair.remove(1) else {
            return None;
        };
        let Value::Str(path) = pair.remove(0) else {
            return None;
        };
        puts.push((path, wyrm_storage::Rec::from_bytes(&rec)?));
    }
    let mut deletes = Vec::with_capacity(delete.len());
    for e in delete {
        let Value::Str(p) = e else {
            return None;
        };
        deletes.push(p);
    }
    Some(wyrm_storage::Changes {
        epoch,
        rev,
        full,
        put: puts,
        delete: deletes,
    })
}

/// One page of the historian's journal.
#[derive(Debug, Clone, PartialEq)]
pub struct HistoryPage {
    pub id: u64,
    pub next: u64,
    pub last: u64,
    /// `(seq, key, t, v, q)`.
    pub rows: Vec<(u64, String, u64, Value, Quality)>,
    /// The confirmed cursor of every history sink on the active (in its
    /// journal numbers; `standby-*` names left out), so the standby can
    /// carry them over; `None` from an active that does not send them.
    pub sinks: Option<Vec<(String, u64)>>,
}

pub fn history_value(p: &HistoryPage) -> Value {
    let mut m = BTreeMap::from([
        ("id".to_owned(), Value::UInt(p.id)),
        ("next".to_owned(), Value::UInt(p.next)),
        ("last".to_owned(), Value::UInt(p.last)),
        (
            "rows".to_owned(),
            Value::Array(
                p.rows
                    .iter()
                    .map(|(seq, key, t, v, q)| {
                        Value::Array(vec![
                            Value::UInt(*seq),
                            Value::from(key.clone()),
                            Value::UInt(*t),
                            v.clone(),
                            Value::UInt(q.code().into()),
                        ])
                    })
                    .collect(),
            ),
        ),
    ]);
    if let Some(sinks) = &p.sinks {
        m.insert(
            "sinks".to_owned(),
            Value::Map(
                sinks
                    .iter()
                    .map(|(n, s)| (n.clone(), Value::UInt(*s)))
                    .collect(),
            ),
        );
    }
    Value::Map(m)
}

pub fn parse_history(v: Value) -> Option<HistoryPage> {
    let Value::Map(mut m) = v else {
        return None;
    };
    let (Some(Value::UInt(id)), Some(Value::UInt(next)), Some(Value::UInt(last))) =
        (m.remove("id"), m.remove("next"), m.remove("last"))
    else {
        return None;
    };
    let Some(Value::Array(rows)) = m.remove("rows") else {
        return None;
    };
    let mut out = Vec::with_capacity(rows.len());
    for r in rows {
        let Value::Array(mut parts) = r else {
            return None;
        };
        if parts.len() != 5 {
            return None;
        }
        let Value::UInt(q) = parts.remove(4) else {
            return None;
        };
        let q = Quality::try_from(u8::try_from(q).ok()?).ok()?;
        let v = parts.remove(3);
        let Value::UInt(t) = parts.remove(2) else {
            return None;
        };
        let Value::Str(key) = parts.remove(1) else {
            return None;
        };
        let Value::UInt(seq) = parts.remove(0) else {
            return None;
        };
        out.push((seq, key, t, v, q));
    }
    let sinks = match m.remove("sinks") {
        None => None,
        Some(Value::Map(s)) => Some(
            s.into_iter()
                .map(|(n, v)| match v {
                    Value::UInt(seq) => Some((n, seq)),
                    _ => None,
                })
                .collect::<Option<Vec<_>>>()?,
        ),
        Some(_) => return None,
    };
    Some(HistoryPage {
        id,
        next,
        last,
        rows: out,
        sinks,
    })
}

/// One part of a file: its total length, the bytes `[offset, offset +
/// len)`, and with the first part the SHA-256 of the whole file (read
/// through once, in blocks). Later parts read only their own range.
/// A part as [`read_part`] gives it: the file's total length, the part's
/// bytes, and the whole file's SHA-256 with the first part.
type Part = (u64, Vec<u8>, Option<Vec<u8>>);

fn read_part(path: &Path, offset: u64, len: u64) -> Result<Part, String> {
    use std::io::{Read, Seek, SeekFrom};
    let mut f = std::fs::File::open(path).map_err(|e| e.to_string())?;
    let total = f.metadata().map_err(|e| e.to_string())?.len();
    if total > MAX_FILE_LEN {
        return Err("file too large to replicate".into());
    }
    let digest = if offset == 0 {
        let mut h = sha2::Sha256::new();
        let mut block = vec![0u8; 64 << 10];
        loop {
            let n = f.read(&mut block).map_err(|e| e.to_string())?;
            if n == 0 {
                break;
            }
            h.update(&block[..n]);
        }
        Some(h.finalize().to_vec())
    } else {
        None
    };
    let start = offset.min(total);
    let want = len.min(total - start) as usize;
    f.seek(SeekFrom::Start(start)).map_err(|e| e.to_string())?;
    let mut part = vec![0u8; want];
    f.read_exact(&mut part).map_err(|e| e.to_string())?;
    Ok((total, part, digest))
}

/// The audit detail of a `forked` report, `None` for an unknown set.
pub fn fork_detail(what: &str, count: u64, n: u32, t_ms: u64) -> Option<String> {
    Some(match what {
        "files" | "storage" => {
            format!(
            "the standby, active before, moved aside {count} {} that differ from this broker's \
             to standby/stale/{t_ms}/ in its data_dir: its own writes from while it was active, \
             or older copies (ADR 0036)",
            if what == "files" { "files" } else { "storage paths" }
        )
        }
        _ => {
            let (_, dir, _) = STORES.iter().find(|(name, _, _)| *name == what)?;
            format!(
                "the standby moved aside its {what} WAL ({count} records, forked from this \
                 broker's) to {dir}.stale.{n} in its data_dir: records it wrote while both brokers \
                 were active (a healed split, ADR 0036)"
            )
        }
    })
}

/// How many fork reports the active remembers to drop a repeated one.
const FORKS_REMEMBERED: usize = 64;

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

    /// Until when this broker holds the arbiters' lease (ADR 0036), as its
    /// daemon's owner keeps it; `None`: no arbiters, or not held.
    pub fn set_arbiter_lease(&self, until: Option<std::time::Instant>) {
        *self.arbiter_lease.lock().unwrap_or_else(|p| p.into_inner()) = until;
    }

    /// Seconds left of the arbiters' lease (`sys/arbiter_lease_s`).
    pub fn arbiter_lease_s(&self) -> f64 {
        self.arbiter_lease
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .map_or(0.0, |u| {
                u.saturating_duration_since(std::time::Instant::now())
                    .as_secs_f64()
            })
    }

    /// Sets of records the standby moved aside after a healed split and
    /// reported to this broker (`sys/standby_forks`).
    pub fn standby_forks(&self) -> u64 {
        self.standby_forks
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .0
    }

    /// One `forked` report: an audit record, once per `(t, what)` (the
    /// standby sends a report again until it has an answer).
    fn note_fork(&self, t: u64, what: &str, detail: &str) {
        {
            let mut f = self.standby_forks.lock().unwrap_or_else(|p| p.into_inner());
            let id = (t, what.to_owned());
            if f.1.contains(&id) {
                return;
            }
            if f.1.len() >= FORKS_REMEMBERED {
                f.1.pop_front();
            }
            f.1.push_back(id);
            f.0 += 1;
        }
        warn!(set = what, "{detail}");
        self.record("system", "standby_forked", what, Status::Ok, detail);
    }

    /// Ask the standby to wait for `d` (the router is about to be rebuilt).
    pub fn hold_standby(&self, d: Duration) {
        let until = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|n| (n + d).as_millis() as u64)
            .unwrap_or(0);
        self.standby_hold
            .store(until, std::sync::atomic::Ordering::SeqCst);
    }

    /// The router is up again: no hold.
    pub fn release_standby(&self) {
        self.standby_hold
            .store(0, std::sync::atomic::Ordering::SeqCst);
    }

    /// A standby asked within the last `d`.
    pub fn standby_recent(&self, d: Duration) -> bool {
        self.standby_seen().is_some_and(|s| s.at.elapsed() < d)
    }

    /// The broker storage, for the standby to follow (set by the daemon).
    pub fn set_storage(&self, storage: &Arc<wyrm_storage::Store>) {
        *self.storage.lock().unwrap_or_else(|p| p.into_inner()) = Arc::downgrade(storage);
    }

    pub(super) fn storage(&self) -> Option<Arc<wyrm_storage::Store>> {
        self.storage
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .upgrade()
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
                        let mut v = page_value(&page);
                        if *store == "state" {
                            self.note_standby(after, page.last);
                            let hold = self.standby_hold.load(std::sync::atomic::Ordering::SeqCst);
                            if let (Value::Map(m), true) = (&mut v, hold != 0) {
                                m.insert(HOLD_UNTIL.to_owned(), Value::UInt(hold));
                            }
                        }
                        v
                    }
                    Err(e) => error_value(&e.to_string()),
                }
            }
            ["forked", t, what, count, n] => {
                let (Ok(t), Ok(count), Ok(n)) =
                    (t.parse::<u64>(), count.parse::<u64>(), n.parse::<u32>())
                else {
                    return error_value("t, count and n: numbers");
                };
                let Some(detail) = fork_detail(what, count, n, t) else {
                    return error_value("unknown set");
                };
                self.note_fork(t, what, &detail);
                Value::Map(BTreeMap::from([("ok".to_owned(), Value::Bool(true))]))
            }
            ["files"] => files_value(&files_of(d)),
            ["file", offset, len, rest @ ..] => {
                let name = rest.join("/");
                if !is_file_name(&name) {
                    return error_value("not a replicated file");
                }
                let (Ok(offset), Ok(len)) = (offset.parse::<u64>(), len.parse::<u64>()) else {
                    return error_value("offset and len: numbers");
                };
                let len = len.clamp(1, PART_LEN);
                match read_part(&d.join(&name), offset, len) {
                    Ok((total, part, digest)) => {
                        let mut m = BTreeMap::from([
                            ("name".to_owned(), Value::from(name)),
                            ("offset".to_owned(), Value::UInt(offset)),
                            ("total".to_owned(), Value::UInt(total)),
                            (
                                "sealed".to_owned(),
                                Value::Bytes(wyrm_link_sdk::seal::seal(file_key, &part)),
                            ),
                        ]);
                        if let Some(d) = digest {
                            m.insert("sha256".to_owned(), Value::Bytes(d));
                        }
                        Value::Map(m)
                    }
                    Err(e) => error_value(&e),
                }
            }
            ["history", after, max] => {
                let (Ok(after), Ok(max)) = (after.parse::<u64>(), max.parse::<usize>()) else {
                    return error_value("after and max: numbers");
                };
                let store = self.history.store();
                let limit = wyrm_history::ChangeLimit {
                    rows: max.clamp(1, MAX_HISTORY_ROWS),
                    bytes: MAX_HISTORY_BYTES,
                };
                let sinks = match store.sink_seqs() {
                    Ok(s) => s
                        .into_iter()
                        .filter(|(n, _)| !n.starts_with(STANDBY_SINK))
                        .collect(),
                    Err(e) => return error_value(&e.to_string()),
                };
                match store.changes(after, limit, |_| true) {
                    Ok(batch) => history_value(&HistoryPage {
                        sinks: Some(sinks),
                        id: store.id(),
                        next: batch.next,
                        last: store.last_seq(),
                        rows: batch
                            .rows
                            .into_iter()
                            .filter_map(|c| {
                                let key = store.series_key(c.series)?;
                                Some((c.seq, key, c.row.t, c.row.v, c.row.q))
                            })
                            .collect(),
                    }),
                    Err(e) => error_value(&e.to_string()),
                }
            }
            ["storage", epoch, since, max] => {
                let (Ok(epoch), Ok(since), Ok(max)) = (
                    epoch.parse::<u64>(),
                    since.parse::<u64>(),
                    max.parse::<usize>(),
                ) else {
                    return error_value("epoch, since and max: numbers");
                };
                match self.storage() {
                    Some(s) => changes_value(&s.changes_since(
                        epoch,
                        since,
                        max.clamp(1, MAX_STORAGE_PATHS),
                    )),
                    None => error_value("no storage"),
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
        // Reading a WAL or a file is I/O: off the session's thread.
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
        assert!(is_file_name("links/plc1/data/framework.tree"));
        assert!(is_file_name("links/alarm/data/store/0a1b"));
        assert!(is_file_name("packages/demo/1.0.0/bin/run"));
        assert!(is_file_name("packages/.wasm/demo.wasm"));
        assert!(!is_file_name("links/../token"));
        assert!(!is_file_name("links/plc1/data"));
        assert!(!is_file_name("links/plc1/data/uploads/x"));
        assert!(!is_file_name("links/plc1/data/store/0a1b.tmp"));
        assert!(!is_file_name("packages/.tmp-abc/x"));
        assert!(!is_file_name("state.key"));
        assert!(!is_file_name("links/plc1/key"));
        assert_ne!(file_key(b"a"), file_key(b"b"));
    }

    #[test]
    fn file_lists_walk_the_replicated_roots_only() {
        let d = std::env::temp_dir().join(format!("wyrm-repl-files-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        for p in [
            "secrets.bin",
            "state.key",
            "links/a/token",
            "links/a/cert.pem",
            "links/a/data/framework.tree",
            "links/a/data/framework.tmp",
            "links/a/data/store/00ff",
            "links/a/data/uploads/c-x/spool",
            "links/b/data/agent/wal.00000000000000000001.wyw",
            "links/b/data/agent.next/x",
            "packages/demo/1.0.0/bin/run",
            "packages/.wasm/demo.wasm",
            "packages/.tmp-123/x",
            "history/days/2026-11-05.redb",
        ] {
            let path = d.join(p);
            std::fs::create_dir_all(path.parent().unwrap()).unwrap();
            std::fs::write(&path, p.as_bytes()).unwrap();
        }
        let names: Vec<String> = files_of(&d).into_iter().map(|f| f.name).collect();
        assert_eq!(
            names,
            [
                "secrets.bin",
                "links/a/token",
                "links/a/data/framework.tree",
                "links/a/data/store/00ff",
                "links/b/data/agent/wal.00000000000000000001.wyw",
                "packages/.wasm/demo.wasm",
                "packages/demo/1.0.0/bin/run",
            ]
        );
        assert!(names.iter().all(|n| is_file_name(n)));
        let v = files_value(&files_of(&d));
        let back = parse_files(v).unwrap();
        assert_eq!(back.len(), 7);
        assert_eq!(back[0].len, "secrets.bin".len() as u64);
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            std::fs::set_permissions(
                d.join("packages/demo/1.0.0/bin/run"),
                std::fs::Permissions::from_mode(0o755),
            )
            .unwrap();
            let again = files_of(&d);
            assert!(
                again
                    .iter()
                    .find(|f| f.name.ends_with("bin/run"))
                    .unwrap()
                    .exec
            );
            assert!(!again[0].exec);
        }
    }

    #[test]
    fn history_pages_roundtrip() {
        let p = HistoryPage {
            id: 9,
            next: 12,
            last: 11,
            rows: vec![(
                11,
                "wy/s/downstream/m/p".into(),
                5,
                Value::Float(1.5),
                Quality::Good,
            )],
            sinks: Some(vec![("pg".into(), 7)]),
        };
        let round = |p: &HistoryPage| {
            let bytes = wyrm_core::codec::to_vec(&history_value(p)).unwrap();
            parse_history(wyrm_core::codec::from_slice(&bytes).unwrap()).unwrap()
        };
        assert_eq!(round(&p), p);
        // an older active sends no cursors
        let old = HistoryPage { sinks: None, ..p };
        assert_eq!(round(&old), old);
    }

    #[test]
    fn storage_changes_roundtrip() {
        let c = wyrm_storage::Changes {
            epoch: 5,
            rev: 7,
            full: false,
            put: vec![(
                "plant/temp".into(),
                wyrm_storage::Rec {
                    ty: Some(wyrm_core::TypeCode::Number),
                    editor: None,
                    value: Some(Value::Float(21.5)),
                    t: Some(3),
                },
            )],
            delete: vec!["plant/old".into()],
        };
        let bytes = wyrm_core::codec::to_vec(&changes_value(&c)).unwrap();
        let back = parse_changes(wyrm_core::codec::from_slice(&bytes).unwrap()).unwrap();
        assert_eq!(back, c);
    }
}
