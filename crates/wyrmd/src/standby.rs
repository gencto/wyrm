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
    Ok(pki.issue(
        &format!("standby:{}", cfg.site),
        &[],
        false,
        &cfg.data_dir.join("standby"),
        "standby",
    )?)
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
    Ok(zenoh::open(zc).await?)
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

/// Fetch the non-WAL files whose digest differs from ours.
async fn sync_files(
    session: &Session,
    prefix: &str,
    data_dir: &Path,
    file_key: &[u8; 32],
    have: &mut BTreeMap<String, Vec<u8>>,
) -> Result<(), String> {
    let Some(Value::Array(list)) = ask(session, &format!("{prefix}/files")).await else {
        return Err("no file list".into());
    };
    for entry in list {
        let Value::Map(mut m) = entry else { continue };
        let (Some(Value::Str(name)), Some(Value::Bytes(sha))) =
            (m.remove("name"), m.remove("sha256"))
        else {
            continue;
        };
        if !replication::is_file_name(&name) || have.get(&name) == Some(&sha) {
            continue;
        }
        let Some(Value::Map(mut f)) = ask(session, &format!("{prefix}/file/{name}")).await else {
            return Err(format!("{name}: no answer"));
        };
        let Some(Value::Bytes(sealed)) = f.remove("sealed") else {
            return Err(format!("{name}: no content"));
        };
        let bytes = wyrm_link_sdk::seal::open(file_key, &sealed)
            .ok_or_else(|| format!("{name}: cannot open (another secrets.key?)"))?;
        let path = data_dir.join(&name);
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
            #[cfg(unix)]
            {
                use std::os::unix::fs::PermissionsExt;
                let _ = std::fs::set_permissions(parent, std::fs::Permissions::from_mode(0o700));
            }
        }
        secret::write_private(&path, &bytes).map_err(|e| format!("{name}: {e}"))?;
        tracing::info!(file = %name, "replicated");
        have.insert(name, sha);
    }
    Ok(())
}

/// Follow the active broker until it has been away for this host's
/// takeover time ([`Outcome::Takeover`]) or `shutdown` resolves.
pub async fn follow(cfg: &Config, shutdown: impl Future<Output = ()>) -> Result<Outcome, Error> {
    let sb = cfg.standby.as_ref().ok_or("no standby section")?;
    let takeover = sb.takeover();
    let files = standby_cert(cfg)?;
    let secrets_key = read_key(&cfg.data_dir.join("secrets.key"))
        .ok_or("secrets.key: not found; import the site's key bundle first")?;
    let file_key = replication::file_key(&secrets_key);
    let mut stores = open_followers(cfg)?;
    let mut have = replication::digests_of(&cfg.data_dir);
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
            r = open_session(cfg, &sb.peer, &files) => match r {
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
                        Ok(()) if polls % FILES_EVERY == 1 => sync_files(&session, &prefix, &cfg.data_dir, &file_key, &mut have).await,
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
