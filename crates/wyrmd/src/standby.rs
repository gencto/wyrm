//! The warm standby of a site (ADR 0036, option 3, stage A).
//!
//! Two brokers of one site, on two hosts, hold the same keys (the bundle of
//! `wyrmd keys export` / `import`) and name each other's QUIC peer
//! listener in `standby.peer`. Exactly one is active; the other follows:
//! it runs no router and no link, it opens one client session to the
//! active (mTLS with a `standby:<site>` certificate its copy of the site CA
//! issues) and copies the control-plane WALs (registry, flows, users),
//! `secrets.bin` and the link tokens through `sys/replication/**`.
//!
//! The follower takes over when the active has been away for
//! `standby.takeover_s` (`primary: true`), or three times that (the other
//! host, so that a cold start of both ends with the primary active), and
//! only while it reaches at least one of `standby.witness` (TCP addresses
//! on the plant network: the gateway, a switch, a PLC). A host that sees
//! no witness is cut off and must not control the plant. A promotion is a
//! plain `Daemon::open` on the followed `data_dir`.
//!
//! An active broker of a pair steps down and follows again when
//! * it is not primary and sees the primary's broker token (both became
//!   active across a split that has healed), or
//! * it reaches no witness and its standby has stopped asking, for half the
//!   takeover time ([`isolated`]): it is the cut-off side, and the other
//!   side takes over only after the full takeover time.
//!
//! Before it rebuilds its router (an ACL change closes its listeners), the
//! active tells the standby to wait (`hold_until` in the registry page);
//! the standby then counts the active as away only after that time.

use crate::{Config, Error};
use serde::Deserialize;
use std::collections::BTreeMap;
use std::future::Future;
use std::path::{Path, PathBuf};
use std::time::Duration;
use tokio::time::Instant;
use wyrm_admin::control::replication::{self, STORES};
use wyrm_admin::secret::{self, CertFiles, Pki};
use wyrm_core::Value;
use wyrm_state::replicate::Follower;
use zenoh::Session;

/// `standby` in `wyrmd.json5`.
#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct StandbySection {
    /// The other broker's `peers.listen` (`quic/<host>:<port>`); its host
    /// must be a SAN of that broker's certificate (`tls_names`).
    pub peer: String,
    /// Seconds the active may be away before the standby takes over.
    #[serde(default = "default_takeover_s")]
    pub takeover_s: u64,
    /// This host wins a cold start and a healed split: it takes over after
    /// `takeover_s`, the other after three times that, and only the other
    /// steps down when both are active.
    #[serde(default)]
    pub primary: bool,
    /// TCP addresses (`host:port`) this host must reach to take over, and
    /// without which an active broker steps down when its standby is gone
    /// too. At least one; any one reachable is enough.
    #[serde(default)]
    pub witness: Vec<String>,
}

/// One TCP connect to a witness may take this long.
const WITNESS_TIMEOUT: Duration = Duration::from_secs(1);
/// The standby asks once a second: quiet for this long, it is gone.
const STANDBY_QUIET: Duration = Duration::from_secs(3);
/// Longest hold the active can ask for (a value further out is cut).
const MAX_HOLD: Duration = Duration::from_secs(120);

/// `true` when at least one of `list` accepts a TCP connection (all are
/// tried at once, each for at most [`WITNESS_TIMEOUT`]).
pub async fn witness_reachable(list: &[String]) -> bool {
    let mut set = tokio::task::JoinSet::new();
    for w in list {
        let w = w.clone();
        set.spawn(async move {
            matches!(
                tokio::time::timeout(WITNESS_TIMEOUT, tokio::net::TcpStream::connect(w)).await,
                Ok(Ok(_))
            )
        });
    }
    while let Some(r) = set.join_next().await {
        if r.unwrap_or(false) {
            set.abort_all();
            return true;
        }
    }
    false
}

fn default_takeover_s() -> u64 {
    10
}

impl StandbySection {
    pub fn validate(&self, peers_listen: bool) -> Result<(), Error> {
        if !self.peer.starts_with("quic/") || self.peer.contains(['#', '?', '"', '\\']) {
            return Err(format!("standby.peer {}: expected quic/<host>:<port>", self.peer).into());
        }
        if self.takeover_s == 0 {
            return Err("standby.takeover_s: at least 1".into());
        }
        if !peers_listen {
            return Err(
                "standby needs peers.listen (the other broker follows this one through it)".into(),
            );
        }
        if self.witness.is_empty() {
            return Err("standby.witness: at least one host:port on the plant network (a gateway, a switch, a PLC): without it a network split makes both brokers active".into());
        }
        for w in &self.witness {
            let ok = w
                .rsplit_once(':')
                .is_some_and(|(h, p)| !h.is_empty() && p.parse::<u16>().is_ok_and(|p| p > 0))
                && !w.chars().any(|c| c.is_whitespace() || c == '/');
            if !ok {
                return Err(format!("standby.witness {w:?}: expected host:port").into());
            }
        }
        Ok(())
    }

    /// How long an active broker may be cut off (no witness, no standby)
    /// before it steps down: half the takeover time, so it is gone before
    /// the other side can take over.
    pub fn isolation(&self) -> Duration {
        Duration::from_millis((self.takeover_s * 1000 / 2).max(1000))
    }

    /// How long this host waits before it takes over.
    pub fn takeover(&self) -> Duration {
        Duration::from_secs(self.takeover_s * if self.primary { 1 } else { 3 })
    }
}

/// Why [`follow`] returned.
#[derive(Debug, PartialEq, Eq)]
pub enum Outcome {
    /// The active was away for long enough: open the daemon.
    Takeover,
    /// `shutdown` resolved.
    Stopped,
}

/// Replication poll period.
const POLL: Duration = Duration::from_secs(1);
/// The file list is asked for every this many polls.
const FILES_EVERY: u32 = 5;
/// One poll answers within this, or the active counts as away.
const ASK_TIMEOUT: Duration = Duration::from_secs(3);
/// Pages fetched per store per poll (catch-up after a long gap).
const PAGES_PER_POLL: usize = 20;
/// A broker that is active and not primary asks this often whether the
/// primary is back.
const PRIMARY_CHECK: Duration = Duration::from_secs(5);

fn read_key(path: &Path) -> Option<Vec<u8>> {
    let text = std::fs::read_to_string(path).ok()?;
    hex::decode(text.trim()).ok().filter(|k| k.len() == 32)
}

/// The standby's own certificate (`standby:<site>`) from the site CA.
fn standby_cert(cfg: &Config) -> Result<CertFiles, Error> {
    let pki = Pki::open_or_create(&cfg.data_dir.join("pki"))?;
    pki.issue(
        &format!("standby:{}", cfg.site),
        &[],
        false,
        &cfg.data_dir.join("standby"),
        "standby",
    )
}

/// A client session to the other broker's peer listener, mTLS.
async fn open_session(cfg: &Config, peer: &str, files: &CertFiles) -> Result<Session, Error> {
    let mut zc = zenoh::Config::default();
    let set = |zc: &mut zenoh::Config, k: &str, v: &str| {
        zc.insert_json5(k, v)
            .map_err(|e| format!("zenoh config {k}: {e}"))
    };
    set(&mut zc, "mode", r#""client""#)?;
    set(&mut zc, "connect/endpoints", &format!("[{peer:?}]"))?;
    set(&mut zc, "connect/timeout_ms", "3000")?;
    set(&mut zc, "scouting/multicast/enabled", "false")?;
    let ca = cfg.data_dir.join("pki/ca.pem");
    set(
        &mut zc,
        "transport/link/tls",
        &serde_json::json!({
            "root_ca_certificate": ca,
            "connect_certificate": files.cert,
            "connect_private_key": files.key,
            "enable_mtls": true,
        })
        .to_string(),
    )?;
    zenoh::open(zc).await
}

/// One `get` on the active's replication queryable; `None` without an answer.
async fn ask(session: &Session, key: &str) -> Option<Value> {
    let replies = session
        .get(key)
        .target(zenoh::query::QueryTarget::AllComplete)
        .timeout(ASK_TIMEOUT)
        .await
        .ok()?;
    while let Ok(reply) = replies.recv_async().await {
        if let Ok(s) = reply.result() {
            if let Ok(v) = wyrm_core::codec::from_slice::<Value>(&s.payload().to_bytes()) {
                return Some(v);
            }
        }
    }
    None
}

/// `true` when the liveliness token `key` answers on this session.
async fn token_present(session: &Session, key: &str) -> bool {
    let Ok(replies) = session.liveliness().get(key).timeout(ASK_TIMEOUT).await else {
        return false;
    };
    while let Ok(r) = replies.recv_async().await {
        if r.result().is_ok() {
            return true;
        }
    }
    false
}

struct Followed {
    name: &'static str,
    follower: Follower,
}

/// The followed stores: those whose key this host holds (the users' only
/// with a gateway).
fn open_followers(cfg: &Config) -> Result<Vec<Followed>, Error> {
    let mut out = Vec::new();
    for (name, dir, key) in STORES {
        let Some(k) = read_key(&cfg.data_dir.join(key)) else {
            if name == "state" {
                return Err(format!(
                    "{}: not found; import the site's key bundle first (wyrmd keys import)",
                    cfg.data_dir.join(key).display()
                )
                .into());
            }
            continue;
        };
        let mut f = Follower::open(cfg.data_dir.join(dir), &k)?;
        if let Some(a) = &cfg.state_anchor_dir {
            f = f.with_anchor(a.join(format!("{name}.head")))?;
        }
        out.push(Followed { name, follower: f });
    }
    Ok(out)
}

/// The hold the active asks for in its registry page (`hold_until`, unix
/// ms): the instant until which an absence does not count, or `None`.
fn hold_of(v: &Value) -> Option<Instant> {
    let Value::Map(m) = v else { return None };
    let Some(Value::UInt(until)) = m.get(replication::HOLD_UNTIL) else {
        return None;
    };
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0);
    let left = Duration::from_millis(until.checked_sub(now)?).min(MAX_HOLD);
    Some(Instant::now() + left)
}

/// Copy what the active has beyond us, store by store. `Err` when the
/// active did not answer (it is away or this session is dead). `hold` gets
/// the active's hold from its registry page.
async fn sync_wals(
    session: &Session,
    prefix: &str,
    stores: &mut [Followed],
    hold: &mut Option<Instant>,
) -> Result<(), String> {
    for s in stores.iter_mut() {
        for _ in 0..PAGES_PER_POLL {
            let key = format!(
                "{prefix}/wal/{}/{}/{}",
                s.name,
                s.follower.lsn(),
                replication::MAX_RECORDS
            );
            let answer = ask(session, &key).await.ok_or("no answer")?;
            if s.name == "state" {
                *hold = hold_of(&answer);
            }
            let page = replication::parse_page(answer).ok_or("bad page")?;
            if page.chain != s.follower.chain() {
                // the active's history is not ours (ours has records of a
                // former active that never reached it): start again
                let stale = s.follower.reset().map_err(|e| e.to_string())?;
                tracing::warn!(store = s.name, moved = %stale.display(), "history forked: following from the start");
                continue;
            }
            let full = page.records.len() >= replication::MAX_RECORDS;
            for r in &page.records {
                s.follower
                    .append(r)
                    .map_err(|e| format!("{}: {e}", s.name))?;
            }
            if !full {
                break;
            }
        }
    }
    Ok(())
}

/// What the standby holds of the replicated files: the active's listing
/// of each one it fetched, and the paths it saw locally at start (those
/// the active does not list are removed at the first sync).
struct Files {
    have: BTreeMap<String, (u64, u64)>,
    local_at_start: Option<Vec<String>>,
    too_large: std::collections::BTreeSet<String>,
}

fn sha256(bytes: &[u8]) -> Vec<u8> {
    replication::sha256(bytes)
}

/// Copy `entry` from the active in parts into `data_dir`: skipped when the
/// local file already has the active's digest.
async fn fetch_file(
    session: &Session,
    prefix: &str,
    data_dir: &Path,
    file_key: &[u8; 32],
    entry: &replication::FileEntry,
) -> Result<(), String> {
    let path = data_dir.join(&entry.name);
    let mut buf: Vec<u8> = Vec::with_capacity(entry.len as usize);
    let mut digest: Option<Vec<u8>> = None;
    let mut offset = 0u64;
    loop {
        let key = format!(
            "{prefix}/file/{offset}/{}/{}",
            replication::PART_LEN,
            entry.name
        );
        let part = replication::parse_part(ask(session, &key).await.ok_or("no answer")?)
            .ok_or("bad part")?;
        if part.total != entry.len || part.name != entry.name {
            return Err("changed while copied".into());
        }
        if offset == 0 {
            digest = part.sha256;
            if let (Some(d), Ok(local)) = (&digest, std::fs::read(&path)) {
                if local.len() as u64 == part.total && &sha256(&local) == d {
                    return Ok(()); // the same file already
                }
            }
        }
        let bytes = wyrm_link_sdk::seal::open(file_key, &part.sealed)
            .ok_or("cannot open (another secrets.key?)")?;
        offset += bytes.len() as u64;
        buf.extend(bytes);
        if offset >= part.total {
            break;
        }
    }
    if digest.as_deref() != Some(&sha256(&buf)[..]) {
        return Err("digest differs".into());
    }
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let _ = std::fs::set_permissions(parent, std::fs::Permissions::from_mode(0o700));
        }
    }
    // a scratch name the listings leave out, then one rename
    let tmp = path.with_extension("tmp");
    secret::write_private(&tmp, &buf).map_err(|e| e.to_string())?;
    #[cfg(unix)]
    if entry.exec {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(&tmp, std::fs::Permissions::from_mode(0o700))
            .map_err(|e| e.to_string())?;
    }
    std::fs::rename(&tmp, &path).map_err(|e| e.to_string())?;
    Ok(())
}

/// Bring the replicated files in line with the active's list: fetch what
/// is new or changed, remove what it no longer lists.
async fn sync_files(
    session: &Session,
    prefix: &str,
    data_dir: &Path,
    file_key: &[u8; 32],
    files: &mut Files,
) -> Result<(), String> {
    let list = replication::parse_files(
        ask(session, &format!("{prefix}/files"))
            .await
            .ok_or("no file list")?,
    )
    .ok_or("bad file list")?;
    let listed: std::collections::BTreeSet<&str> = list.iter().map(|f| f.name.as_str()).collect();
    for entry in &list {
        if entry.len > replication::MAX_FILE_LEN {
            if files.too_large.insert(entry.name.clone()) {
                tracing::warn!(file = %entry.name, len = entry.len, "standby: too large to replicate");
            }
            continue;
        }
        if files.have.get(&entry.name) == Some(&(entry.len, entry.mtime)) {
            continue;
        }
        fetch_file(session, prefix, data_dir, file_key, entry)
            .await
            .map_err(|e| format!("{}: {e}", entry.name))?;
        tracing::debug!(file = %entry.name, "standby: replicated");
        files
            .have
            .insert(entry.name.clone(), (entry.len, entry.mtime));
    }
    let gone: Vec<String> = files
        .have
        .keys()
        .chain(files.local_at_start.iter().flatten())
        .filter(|n| !listed.contains(n.as_str()))
        .cloned()
        .collect();
    files.local_at_start = None;
    for name in gone {
        if replication::is_file_name(&name) {
            let _ = std::fs::remove_file(data_dir.join(&name));
            tracing::info!(file = %name, "standby: removed (gone on the active)");
        }
        files.have.remove(&name);
    }
    Ok(())
}

/// Bring the broker storage in line with the active's: its changes after
/// what we hold, or the whole tree after a restart of the active.
async fn sync_storage(
    session: &Session,
    prefix: &str,
    storage: &wyrm_storage::Store,
    at: &mut (u64, u64),
) -> Result<(), String> {
    for _ in 0..PAGES_PER_POLL {
        let key = format!(
            "{prefix}/storage/{}/{}/{}",
            at.0,
            at.1,
            replication::MAX_STORAGE_PATHS
        );
        let c = replication::parse_changes(ask(session, &key).await.ok_or("no answer")?)
            .ok_or("bad changes")?;
        let paths = c.put.len() + c.delete.len();
        let delete = if c.full {
            let keep: std::collections::BTreeSet<&str> =
                c.put.iter().map(|(p, _)| p.as_str()).collect();
            storage
                .snapshot()
                .into_keys()
                .filter(|p| !keep.contains(p.as_str()))
                .collect()
        } else {
            c.delete
        };
        if !c.put.is_empty() || !delete.is_empty() {
            storage.apply(c.put, delete)?;
        }
        *at = (c.epoch, c.rev);
        if c.full || paths < replication::MAX_STORAGE_PATHS {
            break;
        }
    }
    Ok(())
}

/// Bring the historian's rows in line with the active's journal: the
/// cursor is kept in the standby's own store under a sink name made of
/// the active store's identity, so a new active (another store) starts a
/// cursor of its own. Rows are written as the active did (a row with the
/// same series and time replaces the stored one).
async fn sync_history(
    session: &Session,
    prefix: &str,
    store: &wyrm_history::Store,
    cursor: &mut Option<(u64, u64)>,
) -> Result<(), String> {
    for _ in 0..PAGES_PER_POLL {
        let after = cursor.map_or(0, |c| c.1);
        let key = format!("{prefix}/history/{after}/{}", replication::MAX_HISTORY_ROWS);
        let page = replication::parse_history(ask(session, &key).await.ok_or("no answer")?)
            .ok_or("bad history page")?;
        let sink = format!("standby-{:016x}", page.id);
        if cursor.map(|c| c.0) != Some(page.id) {
            // another active store: its own cursor, from what we confirmed
            // of it before (0 for a new one)
            let after = store.sink_seq(&sink).map_err(|e| e.to_string())?;
            *cursor = Some((page.id, after));
            if after != 0 {
                continue;
            }
        }
        let mut rows: Vec<wyrm_history::store::NewRow> = Vec::with_capacity(page.rows.len());
        for (_, key, t, v, q) in &page.rows {
            let Some(series) = store.series_id(key, true).map_err(|e| e.to_string())? else {
                continue;
            };
            rows.push((series, *t, wyrm_history::encode_row(v, *q)));
        }
        if !rows.is_empty() {
            store.write(&rows).map_err(|e| e.to_string())?;
        }
        let full = page.rows.len() >= replication::MAX_HISTORY_ROWS;
        if page.next != after {
            store
                .set_sink_seq(&sink, Some(page.next))
                .map_err(|e| e.to_string())?;
            *cursor = Some((page.id, page.next));
        }
        if !full {
            break;
        }
    }
    Ok(())
}

/// Follow the active broker until it has been away for this host's
/// takeover time ([`Outcome::Takeover`]) or `shutdown` resolves.
pub async fn follow(cfg: &Config, shutdown: impl Future<Output = ()>) -> Result<Outcome, Error> {
    let sb = cfg.standby.as_ref().ok_or("no standby section")?;
    let takeover = sb.takeover();
    let cert = standby_cert(cfg)?;
    let secrets_key = read_key(&cfg.data_dir.join("secrets.key"))
        .ok_or("secrets.key: not found; import the site's key bundle first")?;
    let file_key = replication::file_key(&secrets_key);
    let mut stores = open_followers(cfg)?;
    let mut files = Files {
        have: BTreeMap::new(),
        local_at_start: Some(
            replication::files_of(&cfg.data_dir)
                .into_iter()
                .map(|f| f.name)
                .collect(),
        ),
        too_large: Default::default(),
    };
    let storage = wyrm_storage::Store::open(&cfg.data_dir.join("storage"))?;
    let mut storage_at = (0u64, 0u64);
    let history = wyrm_history::Store::open(&cfg.data_dir.join("history"))
        .map_err(|e| format!("history: {e}"))?;
    let mut history_at: Option<(u64, u64)> = None;
    let prefix = replication::replication_key(&cfg.site);
    let broker = format!("wy/{}/sys/broker", cfg.site);
    tokio::pin!(shutdown);
    // Until the active answers it counts as away: a lone start takes over
    // after the takeover time (with a witness).
    let mut gone_since: Option<Instant> = Some(Instant::now());
    // The active's hold (it is rebuilding its router), and the next witness
    // check after one found none.
    let mut hold: Option<Instant> = None;
    let mut retry_at: Option<Instant> = None;
    let mut no_witness_said = false;
    let due = |gone: Option<Instant>, hold: Option<Instant>, retry: Option<Instant>| {
        gone.map(|t| {
            let mut d = t + takeover;
            if let Some(h) = hold {
                d = d.max(h);
            }
            if let Some(r) = retry {
                d = d.max(r);
            }
            d
        })
    };
    tracing::info!(peer = %sb.peer, primary = sb.primary, takeover_s = takeover.as_secs(), "standby: following");
    loop {
        let deadline = due(gone_since, hold, retry_at);
        let session = tokio::select! {
            _ = &mut shutdown => return Ok(Outcome::Stopped),
            _ = async { match deadline { Some(d) => tokio::time::sleep_until(d).await, None => std::future::pending().await } } => {
                if witness_reachable(&sb.witness).await {
                    tracing::warn!("standby: the active has been away for {takeover:?}: taking over");
                    return Ok(Outcome::Takeover);
                }
                if !std::mem::replace(&mut no_witness_said, true) {
                    tracing::warn!("standby: the active is away, but no witness answers: this host may be the one cut off; not taking over");
                }
                retry_at = Some(Instant::now() + POLL);
                continue;
            }
            r = open_session(cfg, &sb.peer, &cert) => match r {
                Ok(s) => s,
                Err(e) => {
                    tracing::debug!("standby: cannot reach {}: {e}", sb.peer);
                    tokio::select! {
                        _ = &mut shutdown => return Ok(Outcome::Stopped),
                        _ = tokio::time::sleep(POLL) => continue,
                    }
                }
            },
        };
        let watch = match session.liveliness().declare_subscriber(&broker).await {
            Ok(w) => w,
            Err(e) => {
                tracing::warn!("standby: liveliness: {e}");
                let _ = session.close().await;
                continue;
            }
        };
        let mut tick = tokio::time::interval(POLL);
        tick.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
        let mut polls = 0u32;
        let mut failures = 0u32;
        loop {
            let deadline = due(gone_since, hold, retry_at);
            tokio::select! {
                _ = &mut shutdown => {
                    let _ = session.close().await;
                    return Ok(Outcome::Stopped);
                }
                _ = async { match deadline { Some(d) => tokio::time::sleep_until(d).await, None => std::future::pending().await } } => {
                    if witness_reachable(&sb.witness).await {
                        let _ = session.close().await;
                        tracing::warn!("standby: the active has been away for {takeover:?}: taking over");
                        return Ok(Outcome::Takeover);
                    }
                    if !std::mem::replace(&mut no_witness_said, true) {
                        tracing::warn!("standby: the active is away, but no witness answers: this host may be the one cut off; not taking over");
                    }
                    retry_at = Some(Instant::now() + POLL);
                }
                s = watch.recv_async() => match s {
                    Ok(sample) if sample.kind() == zenoh::sample::SampleKind::Delete => {
                        if gone_since.is_none() {
                            tracing::warn!("standby: the active's broker token is gone");
                            gone_since = Some(Instant::now());
                        }
                    }
                    Ok(_) => {}
                    Err(_) => break,
                },
                _ = tick.tick() => {
                    polls += 1;
                    let r = match sync_wals(&session, &prefix, &mut stores, &mut hold).await {
                        Ok(()) => match sync_storage(&session, &prefix, &storage, &mut storage_at).await {
                            Ok(()) => match sync_history(&session, &prefix, &history, &mut history_at).await {
                                Ok(()) if polls % FILES_EVERY == 1 => sync_files(&session, &prefix, &cfg.data_dir, &file_key, &mut files).await,
                                r => r,
                            },
                            r => r,
                        },
                        r => r,
                    };
                    match r {
                        Ok(()) => {
                            failures = 0;
                            retry_at = None;
                            no_witness_said = false;
                            if gone_since.take().is_some() {
                                tracing::info!("standby: the active answers again");
                            }
                        }
                        Err(e) => {
                            failures += 1;
                            if gone_since.is_none() {
                                tracing::warn!("standby: the active does not answer: {e}");
                                gone_since = Some(Instant::now());
                            }
                            // a dead session is opened again; Zenoh's own
                            // reconnect keeps a live one
                            if failures >= 3 && !token_present(&session, &broker).await {
                                break;
                            }
                        }
                    }
                }
            }
        }
        let _ = session.close().await;
    }
}

/// For a broker that is active and not primary: resolves when the
/// primary's broker token is seen on the peer (both are active: this one
/// steps down). Pending for ever on the primary.
pub async fn primary_is_back(cfg: &Config) {
    let Some(sb) = cfg.standby.as_ref() else {
        return std::future::pending().await;
    };
    if sb.primary {
        return std::future::pending().await;
    }
    let Ok(files) = standby_cert(cfg) else {
        return std::future::pending().await;
    };
    let broker = format!("wy/{}/sys/broker", cfg.site);
    loop {
        tokio::time::sleep(PRIMARY_CHECK).await;
        if let Ok(session) = open_session(cfg, &sb.peer, &files).await {
            let present = token_present(&session, &broker).await;
            let _ = session.close().await;
            if present {
                return;
            }
        }
    }
}

/// For an active broker of a pair: resolves when it has been cut off for
/// [`StandbySection::isolation`]: no witness answers and its standby has
/// not asked for [`STANDBY_QUIET`]. The caller steps down: the other side,
/// which may still reach the plant, takes over only after the full takeover
/// time, so the two are never active together across a split. Pending for
/// ever without a standby section.
pub async fn isolated(cfg: &Config, ctl: &wyrm_admin::Control) {
    let Some(sb) = cfg.standby.as_ref() else {
        return std::future::pending().await;
    };
    let limit = sb.isolation();
    let mut since: Option<Instant> = None;
    loop {
        tokio::time::sleep(POLL).await;
        let standby_asks = ctl
            .standby_seen()
            .is_some_and(|s| s.at.elapsed() < STANDBY_QUIET);
        if standby_asks || witness_reachable(&sb.witness).await {
            if since.take().is_some() {
                tracing::info!("standby: a witness or the standby answers again");
            }
            continue;
        }
        let t = *since.get_or_insert_with(|| {
            tracing::warn!("standby: no witness answers and the standby is quiet");
            Instant::now()
        });
        if t.elapsed() >= limit {
            return;
        }
    }
}

/// Where the standby keeps its own certificate.
pub fn standby_dir(data_dir: &Path) -> PathBuf {
    data_dir.join("standby")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn section(witness: &[&str]) -> StandbySection {
        StandbySection {
            peer: "quic/10.0.0.2:7449".into(),
            takeover_s: 10,
            primary: false,
            witness: witness.iter().map(|w| w.to_string()).collect(),
        }
    }

    #[test]
    fn witnesses_are_required_and_checked() {
        assert!(section(&[]).validate(true).is_err(), "at least one witness");
        assert!(section(&["10.0.0.254:443"]).validate(true).is_ok());
        assert!(section(&["gw.plant:443", "[::1]:502"])
            .validate(true)
            .is_ok());
        for bad in [
            "10.0.0.254",
            ":443",
            "host:0",
            "host:99999",
            "tcp/host:1",
            "a b:1",
        ] {
            assert!(section(&[bad]).validate(true).is_err(), "{bad}");
        }
        assert_eq!(section(&["h:1"]).isolation(), Duration::from_secs(5));
        let mut s = section(&["h:1"]);
        s.takeover_s = 1;
        assert_eq!(s.isolation(), Duration::from_secs(1), "at least a second");
    }

    #[tokio::test]
    async fn a_witness_answers_or_not() {
        let l = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let open = format!("127.0.0.1:{}", l.local_addr().unwrap().port());
        let closed = {
            let c = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
            format!("127.0.0.1:{}", c.local_addr().unwrap().port())
        };
        assert!(witness_reachable(std::slice::from_ref(&open)).await);
        assert!(witness_reachable(&[closed.clone(), open]).await, "any one");
        assert!(!witness_reachable(&[closed]).await);
        assert!(!witness_reachable(&[]).await);
    }

    #[test]
    fn a_hold_is_read_and_capped() {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_millis() as u64;
        let page = |until: u64| {
            Value::Map(BTreeMap::from([(
                replication::HOLD_UNTIL.to_owned(),
                Value::UInt(until),
            )]))
        };
        assert!(hold_of(&page(now - 1000)).is_none(), "past");
        assert!(hold_of(&Value::Map(BTreeMap::new())).is_none());
        let h = hold_of(&page(now + 30_000)).unwrap();
        assert!(h > Instant::now() + Duration::from_secs(25));
        let far = hold_of(&page(now + 3_600_000)).unwrap();
        assert!(far <= Instant::now() + MAX_HOLD, "capped");
    }
}
