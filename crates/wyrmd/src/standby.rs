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
//! host, so that a cold start of both ends with the primary active). A
//! promotion is a plain `Daemon::open` on the followed `data_dir`. When a
//! non-primary broker is active and sees the primary's broker token, it
//! steps down and follows again; the primary never steps down.

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
        Ok(())
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

/// Copy what the active has beyond us, store by store. `Err` when the
/// active did not answer (it is away or this session is dead).
async fn sync_wals(session: &Session, prefix: &str, stores: &mut [Followed]) -> Result<(), String> {
    for s in stores.iter_mut() {
        for _ in 0..PAGES_PER_POLL {
            let key = format!(
                "{prefix}/wal/{}/{}/{}",
                s.name,
                s.follower.lsn(),
                replication::MAX_RECORDS
            );
            let page = replication::parse_page(ask(session, &key).await.ok_or("no answer")?)
                .ok_or("bad page")?;
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
    let prefix = replication::replication_key(&cfg.site);
    let broker = format!("wy/{}/sys/broker", cfg.site);
    tokio::pin!(shutdown);
    // Until the active answers it counts as away: a lone start takes over
    // after the takeover time.
    let mut gone_since: Option<Instant> = Some(Instant::now());
    tracing::info!(peer = %sb.peer, primary = sb.primary, takeover_s = takeover.as_secs(), "standby: following");
    loop {
        let deadline = gone_since.map(|t| t + takeover);
        let session = tokio::select! {
            _ = &mut shutdown => return Ok(Outcome::Stopped),
            _ = async { match deadline { Some(d) => tokio::time::sleep_until(d).await, None => std::future::pending().await } } => return Ok(Outcome::Takeover),
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
            let deadline = gone_since.map(|t| t + takeover);
            tokio::select! {
                _ = &mut shutdown => {
                    let _ = session.close().await;
                    return Ok(Outcome::Stopped);
                }
                _ = async { match deadline { Some(d) => tokio::time::sleep_until(d).await, None => std::future::pending().await } } => {
                    let _ = session.close().await;
                    tracing::warn!("standby: the active has been away for {takeover:?}: taking over");
                    return Ok(Outcome::Takeover);
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
                    let r = match sync_wals(&session, &prefix, &mut stores).await {
                        Ok(()) => match sync_storage(&session, &prefix, &storage, &mut storage_at).await {
                            Ok(()) if polls % FILES_EVERY == 1 => sync_files(&session, &prefix, &cfg.data_dir, &file_key, &mut files).await,
                            r => r,
                        },
                        r => r,
                    };
                    match r {
                        Ok(()) => {
                            failures = 0;
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

/// Where the standby keeps its own certificate.
pub fn standby_dir(data_dir: &Path) -> PathBuf {
    data_dir.join("standby")
}
