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
    /// Lease arbiters (`host:port` of `wyrmd arbiter serve`, on a third
    /// host): with them, a standby takes over only once a majority grants
    /// it the site's lease, and an active broker that another host has
    /// taken it from steps down (a split where both hosts still reach a
    /// witness). Optional; one or an odd number.
    #[serde(default)]
    pub arbiter: Vec<String>,
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
        let host_port = |w: &str| {
            w.rsplit_once(':')
                .is_some_and(|(h, p)| !h.is_empty() && p.parse::<u16>().is_ok_and(|p| p > 0))
                && !w.chars().any(|c| c.is_whitespace() || c == '/')
        };
        for w in &self.witness {
            if !host_port(w) {
                return Err(format!("standby.witness {w:?}: expected host:port").into());
            }
        }
        for a in &self.arbiter {
            if !host_port(a) || a.starts_with('[') {
                return Err(format!(
                    "standby.arbiter {a:?}: expected host:port (a host name of its certificate, or an IPv4 address)"
                )
                .into());
            }
        }
        if self.arbiter.len() > 9 {
            return Err("standby.arbiter: at most 9".into());
        }
        Ok(())
    }

    /// The lease asked of the arbiters: half the takeover time, within
    /// [`crate::arbiter::MIN_TTL`]..[`crate::arbiter::MAX_TTL`].
    pub fn lease_ttl(&self) -> Duration {
        Duration::from_millis(self.takeover_s * 1000 / 2)
            .clamp(crate::arbiter::MIN_TTL, crate::arbiter::MAX_TTL)
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
pub(crate) fn standby_cert(cfg: &Config) -> Result<CertFiles, Error> {
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

/// The active has been away for the takeover time: take over only while a
/// witness answers (else this host may be the one cut off) and, with
/// arbiters, once a majority grants this host the site's lease (else the
/// active may run on, out of this host's sight). `said` keeps the first
/// refusal's warning from repeating every second.
async fn may_take_over(
    sb: &StandbySection,
    arbiters: Option<&crate::arbiter::Arbiters>,
    said: &mut bool,
) -> bool {
    if !witness_reachable(&sb.witness).await {
        if !std::mem::replace(said, true) {
            tracing::warn!("standby: the active is away, but no witness answers: this host may be the one cut off; not taking over");
        }
        return false;
    }
    let Some(arb) = arbiters else { return true };
    match arb.acquire().await {
        crate::arbiter::Verdict::Granted => true,
        v => {
            if !std::mem::replace(said, true) {
                tracing::warn!(?v, "standby: the active is out of sight, but the arbiters do not grant the lease (it may still run): not taking over");
            }
            false
        }
    }
}

/// Copy what the active has beyond us, store by store. `Err` when the
/// active did not answer (it is away or this session is dead). `hold` gets
/// the active's hold from its registry page.
async fn sync_wals(
    session: &Session,
    prefix: &str,
    stores: &mut [Followed],
    hold: &mut Option<Instant>,
    forks: &mut Forks,
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
                let had = s.follower.lsn();
                let stale = s.follower.reset().map_err(|e| e.to_string())?;
                tracing::warn!(store = s.name, records = had, moved = %stale.display(), "history forked: following from the start");
                let n = stale
                    .extension()
                    .and_then(|e| e.to_str())
                    .and_then(|e| e.parse().ok())
                    .unwrap_or(0);
                forks.push(Fork {
                    t_ms: now_ms(),
                    what: s.name.to_owned(),
                    count: had,
                    n,
                });
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

fn now_ms() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

/// One set of records moved aside after a healed split, to report to the
/// active (`sys/replication/forked/<t_ms>/<what>/<count>/<n>`).
#[derive(Debug, Clone, PartialEq, Eq)]
struct Fork {
    t_ms: u64,
    what: String,
    count: u64,
    n: u32,
}

/// The reports not yet answered, kept in `standby/forks` (CBOR) so that a
/// restart sends them still.
struct Forks {
    path: PathBuf,
    list: Vec<Fork>,
}

impl Forks {
    fn load(data_dir: &Path) -> Self {
        let path = standby_dir(data_dir).join("forks");
        let list = std::fs::read(&path)
            .ok()
            .and_then(|b| wyrm_core::codec::from_slice::<Value>(&b).ok())
            .map(|v| match v {
                Value::Array(a) => a
                    .into_iter()
                    .filter_map(|f| match f {
                        Value::Array(f) => match f.as_slice() {
                            [Value::UInt(t), Value::Str(w), Value::UInt(c), Value::UInt(n)] => {
                                Some(Fork {
                                    t_ms: *t,
                                    what: w.clone(),
                                    count: *c,
                                    n: u32::try_from(*n).ok()?,
                                })
                            }
                            _ => None,
                        },
                        _ => None,
                    })
                    .collect(),
                _ => Vec::new(),
            })
            .unwrap_or_default();
        Self { path, list }
    }

    fn save(&self) {
        let v = Value::Array(
            self.list
                .iter()
                .map(|f| {
                    Value::Array(vec![
                        Value::UInt(f.t_ms),
                        Value::from(f.what.clone()),
                        Value::UInt(f.count),
                        Value::UInt(f.n.into()),
                    ])
                })
                .collect(),
        );
        let r = if self.list.is_empty() {
            match std::fs::remove_file(&self.path) {
                Err(e) if e.kind() != std::io::ErrorKind::NotFound => Err(e.to_string()),
                _ => Ok(()),
            }
        } else {
            wyrm_core::codec::to_vec(&v)
                .map_err(|e| e.to_string())
                .and_then(|b| {
                    if let Some(d) = self.path.parent() {
                        std::fs::create_dir_all(d).map_err(|e| e.to_string())?;
                    }
                    let tmp = self.path.with_extension("tmp");
                    secret::write_private(&tmp, &b).map_err(|e| e.to_string())?;
                    std::fs::rename(&tmp, &self.path).map_err(|e| e.to_string())
                })
        };
        if let Err(e) = r {
            tracing::warn!("standby: {}: {e}", self.path.display());
        }
    }

    fn push(&mut self, f: Fork) {
        self.list.push(f);
        self.save();
    }
}

/// Send the reports the active has not answered yet. Any answer counts
/// (an older active answers an unknown key with an error, and will never
/// know more).
async fn report_forks(session: &Session, prefix: &str, forks: &mut Forks) {
    if forks.list.is_empty() {
        return;
    }
    let before = forks.list.len();
    let mut left = Vec::new();
    for f in std::mem::take(&mut forks.list) {
        let key = format!("{prefix}/forked/{}/{}/{}/{}", f.t_ms, f.what, f.count, f.n);
        if ask(session, &key).await.is_none() {
            left.push(f);
        }
    }
    forks.list = left;
    if forks.list.len() != before {
        forks.save();
    }
}

/// A former active's first follow (the mark [`ACTIVE_MARK`] was there):
/// what the active does not hold is moved into `standby/stale/<t_ms>/`
/// instead of being removed or overwritten.
struct Aside {
    t_ms: u64,
    dir: PathBuf,
    files: u64,
    storage: u64,
}

impl Aside {
    fn new(data_dir: &Path) -> Self {
        let t_ms = now_ms();
        Self {
            t_ms,
            dir: standby_dir(data_dir).join("stale").join(t_ms.to_string()),
            files: 0,
            storage: 0,
        }
    }

    /// Move the local file `name` (under `data_dir`) aside.
    fn keep_file(&mut self, data_dir: &Path, name: &str) {
        let from = data_dir.join(name);
        if !from.is_file() {
            return;
        }
        let to = self.dir.join("files").join(name);
        let r = to
            .parent()
            .map_or(Ok(()), std::fs::create_dir_all)
            .and_then(|()| std::fs::rename(&from, &to));
        match r {
            Ok(()) => {
                self.files += 1;
                tracing::warn!(file = %name, to = %to.display(), "standby: moved aside (the active does not hold it)");
            }
            Err(e) => tracing::warn!(file = %name, "standby: cannot move aside: {e}"),
        }
    }

    /// The reports of this follow's sets, if any were moved.
    fn forks(&self) -> Vec<Fork> {
        [("files", self.files), ("storage", self.storage)]
            .into_iter()
            .filter(|(_, c)| *c > 0)
            .map(|(what, count)| Fork {
                t_ms: self.t_ms,
                what: what.to_owned(),
                count,
                n: 0,
            })
            .collect()
    }
}

/// The sinks whose cursor a follower must not move, kept in
/// `standby/own_sinks` until this host is active again: a former active's
/// sinks that had not confirmed all of its own rows (with `history`, at
/// the first follow after it was active, they are added).
fn own_sinks(
    data_dir: &Path,
    history: Option<&wyrm_history::Store>,
) -> Result<BTreeMap<String, u64>, Error> {
    let path = standby_dir(data_dir).join("own_sinks");
    let mut own: BTreeMap<String, u64> = std::fs::read(&path)
        .ok()
        .and_then(|b| wyrm_core::codec::from_slice::<Value>(&b).ok())
        .and_then(|v| match v {
            Value::Map(m) => Some(
                m.into_iter()
                    .filter_map(|(k, v)| match v {
                        Value::UInt(s) => Some((k, s)),
                        _ => None,
                    })
                    .collect(),
            ),
            _ => None,
        })
        .unwrap_or_default();
    let Some(h) = history else {
        return Ok(own);
    };
    let last = h.last_seq();
    let mut added = false;
    for (n, s) in h
        .sink_seqs()
        .map_err(|e| Error::from(format!("history: {e}")))?
    {
        if !n.starts_with(replication::STANDBY_SINK) && s < last && !own.contains_key(&n) {
            tracing::info!(sink = %n, confirmed = s, last, "standby: the sink has rows of this host to send; its cursor stays");
            own.insert(n, s);
            added = true;
        }
    }
    if added {
        let v = Value::Map(
            own.iter()
                .map(|(k, s)| (k.clone(), Value::UInt(*s)))
                .collect(),
        );
        let bytes = wyrm_core::codec::to_vec(&v).map_err(|e| Error::from(e.to_string()))?;
        std::fs::create_dir_all(standby_dir(data_dir))?;
        secret::write_private(&path, &bytes)?;
    }
    Ok(own)
}

/// Present while this host is (or was last) the active broker of its pair:
/// written at promotion, removed after the first complete sync of a follow.
const ACTIVE_MARK: &str = "active";

/// Mark this host as the active one (called after a promotion): its sinks
/// send from their own cursors again.
pub fn mark_active(data_dir: &Path) {
    let dir = standby_dir(data_dir);
    let _ = std::fs::remove_file(dir.join("own_sinks"));
    let r = std::fs::create_dir_all(&dir).and_then(|()| std::fs::write(dir.join(ACTIVE_MARK), b""));
    if let Err(e) = r {
        tracing::warn!("standby: {}: {e}", dir.join(ACTIVE_MARK).display());
    }
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
    aside: Option<&mut Aside>,
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
    if let Some(a) = aside {
        // the local file differs (an equal one returned above): written here
        // while the other side was active too
        a.keep_file(data_dir, &entry.name);
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
    mut aside: Option<&mut Aside>,
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
        // a former active's own file, before its first copy: kept aside when it differs
        let first = files.local_at_start.is_some();
        fetch_file(
            session,
            prefix,
            data_dir,
            file_key,
            entry,
            aside.as_deref_mut().filter(|_| first),
        )
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
    let local_at_start = files.local_at_start.take().unwrap_or_default();
    for name in gone {
        if replication::is_file_name(&name) {
            match aside.as_deref_mut() {
                Some(a) if local_at_start.contains(&name) => a.keep_file(data_dir, &name),
                _ => {
                    let _ = std::fs::remove_file(data_dir.join(&name));
                    tracing::info!(file = %name, "standby: removed (gone on the active)");
                }
            }
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
    aside: Option<&mut Aside>,
) -> Result<(), String> {
    let mut aside = aside;
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
        if let (true, Some(a)) = (c.full, aside.take()) {
            keep_storage(storage, &c.put, a);
        }
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

/// A former active's first full storage tree from the active: when its own
/// tree differs, it is exported (`wyrm-storage` JSON) into the aside
/// directory before it is replaced.
fn keep_storage(storage: &wyrm_storage::Store, put: &[(String, wyrm_storage::Rec)], a: &mut Aside) {
    let theirs: BTreeMap<&str, &wyrm_storage::Rec> =
        put.iter().map(|(p, r)| (p.as_str(), r)).collect();
    let ours = storage.snapshot();
    let differs = ours
        .iter()
        .filter(|(p, r)| theirs.get(p.as_str()) != Some(r))
        .count();
    if differs == 0 {
        return;
    }
    let nodes: Vec<(String, wyrm_storage::Rec)> = ours.into_iter().collect();
    let Some(text) = wyrm_storage::json::export("", &nodes, usize::MAX) else {
        return;
    };
    let path = a.dir.join("storage.json");
    let r = std::fs::create_dir_all(&a.dir).and_then(|()| std::fs::write(&path, text));
    match r {
        Ok(()) => {
            a.storage = differs as u64;
            tracing::warn!(paths = differs, to = %path.display(), "standby: the storage tree differs from the active's: exported");
        }
        Err(e) => tracing::warn!("standby: {}: {e}", path.display()),
    }
}

/// Where the standby is in an active's history journal, and how the
/// active's journal numbers map onto its own.
struct HistoryAt {
    /// The active store's identity and the last of its numbers copied.
    id: u64,
    after: u64,
    /// `active seq → local last_seq` after each copied page: every active
    /// row up to the key is a local row up to the value.
    marks: BTreeMap<u64, u64>,
}

/// Marks kept per active store (the oldest go first): a sink further
/// behind than this many pages keeps its local cursor until it catches up.
const HISTORY_MARKS: usize = 4096;

/// Bring the historian's rows in line with the active's journal: the
/// cursor is kept in the standby's own store under a sink name made of
/// the active store's identity, so a new active (another store) starts a
/// cursor of its own. Rows are written as the active did (a row with the
/// same series and time replaces the stored one). The active's sink
/// cursors are carried over in local numbers ([`carry_sinks`]); `own`
/// holds the sinks a former active must not move (rows of its own that
/// they have not confirmed).
async fn sync_history(
    session: &Session,
    prefix: &str,
    store: &wyrm_history::Store,
    at: &mut Option<HistoryAt>,
    own: &BTreeMap<String, u64>,
) -> Result<(), String> {
    for _ in 0..PAGES_PER_POLL {
        let after = at.as_ref().map_or(0, |c| c.after);
        let key = format!("{prefix}/history/{after}/{}", replication::MAX_HISTORY_ROWS);
        let page = replication::parse_history(ask(session, &key).await.ok_or("no answer")?)
            .ok_or("bad history page")?;
        let sink = format!("{}{:016x}", replication::STANDBY_SINK, page.id);
        if at.as_ref().map(|c| c.id) != Some(page.id) {
            // another active store: its own cursor, from what we confirmed
            // of it before (0 for a new one); every local row so far holds
            // its rows up to there
            let after = store.sink_seq(&sink).map_err(|e| e.to_string())?;
            *at = Some(HistoryAt {
                id: page.id,
                after,
                marks: BTreeMap::from([(after, store.last_seq())]),
            });
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
        let c = at.as_mut().expect("set above");
        if page.next != after {
            store
                .set_sink_seq(&sink, Some(page.next))
                .map_err(|e| e.to_string())?;
            c.after = page.next;
            c.marks.insert(page.next, store.last_seq());
            while c.marks.len() > HISTORY_MARKS {
                c.marks.pop_first();
            }
        }
        if let Some(sinks) = &page.sinks {
            carry_sinks(store, &c.marks, sinks, own).map_err(|e| e.to_string())?;
        }
        if !full {
            break;
        }
    }
    Ok(())
}

/// Set the local cursor of every sink of the active to the local number of
/// the last row it confirmed there (at the mark at or below its cursor:
/// rows between the mark and the cursor are sent again after a failover,
/// which the targets take, since they replace on `(key, t)`). A sink below
/// every mark keeps its cursor; a sink in `own` keeps its own; a local
/// sink the active no longer has is forgotten. Never a row skipped.
fn carry_sinks(
    store: &wyrm_history::Store,
    marks: &BTreeMap<u64, u64>,
    sinks: &[(String, u64)],
    own: &BTreeMap<String, u64>,
) -> Result<(), wyrm_history::store::Error> {
    let theirs: BTreeMap<&str, u64> = sinks.iter().map(|(n, s)| (n.as_str(), *s)).collect();
    for (name, _) in store.sink_seqs()? {
        let skip = name.starts_with(replication::STANDBY_SINK) || own.contains_key(&name);
        if !skip && !theirs.contains_key(name.as_str()) {
            store.set_sink_seq(&name, None)?;
        }
    }
    for (name, seq) in theirs {
        if own.contains_key(name) {
            continue;
        }
        let Some((_, &local)) = marks.range(..=seq).next_back() else {
            continue;
        };
        if store.sink_seq(name)? != local {
            store.set_sink_seq(name, Some(local))?;
        }
    }
    Ok(())
}

/// `open` again while it fails because the store is still held (a daemon
/// in this process that is closing), for at most [`OPEN_WAIT`].
async fn retry_open<T>(mut open: impl FnMut() -> Result<T, Error>) -> Result<T, Error> {
    let deadline = Instant::now() + OPEN_WAIT;
    loop {
        match open() {
            Ok(v) => return Ok(v),
            Err(e) => {
                let held = {
                    let m = e.to_string();
                    m.contains("in use") || m.contains("already open")
                };
                if !held || Instant::now() >= deadline {
                    return Err(e);
                }
                tokio::time::sleep(Duration::from_millis(200)).await;
            }
        }
    }
}

/// Longest wait for a store held by a closing daemon.
const OPEN_WAIT: Duration = Duration::from_secs(30);

/// Follow the active broker until it has been away for this host's
/// takeover time ([`Outcome::Takeover`]) or `shutdown` resolves.
pub async fn follow(cfg: &Config, shutdown: impl Future<Output = ()>) -> Result<Outcome, Error> {
    follow_with(cfg, crate::arbiter::Arbiters::of(cfg)?, shutdown).await
}

/// [`follow`] with the caller's arbiters: after [`Outcome::Takeover`] their
/// [`granted_at`](crate::arbiter::Arbiters::granted_at) is the takeover's
/// grant, from which the active renews the lease.
pub async fn follow_with(
    cfg: &Config,
    arbiters: Option<crate::arbiter::Arbiters>,
    shutdown: impl Future<Output = ()>,
) -> Result<Outcome, Error> {
    let sb = cfg.standby.as_ref().ok_or("no standby section")?;
    // With arbiters an active that cannot renew its lease steps down once
    // its standby has been quiet for STANDBY_QUIET: never take over before.
    let takeover = match &arbiters {
        Some(_) => sb.takeover().max(STANDBY_QUIET + POLL * 2),
        None => sb.takeover(),
    };
    let secrets_key = read_key(&cfg.data_dir.join("secrets.key"))
        .ok_or("secrets.key: not found; import the site's key bundle first")?;
    let file_key = replication::file_key(&secrets_key);
    // A broker that just stepped down may still close its stores for a
    // moment (tasks that outlive its daemon): wait for them.
    let mut stores = retry_open(|| open_followers(cfg)).await?;
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
    let storage = retry_open(|| {
        wyrm_storage::Store::open(&cfg.data_dir.join("storage")).map_err(Error::from)
    })
    .await?;
    let mut storage_at = (0u64, 0u64);
    let history = retry_open(|| {
        wyrm_history::Store::open(&cfg.data_dir.join("history"))
            .map_err(|e| Error::from(format!("history: {e}")))
    })
    .await?;
    let mut history_at: Option<HistoryAt> = None;
    // A former active (its mark is there) keeps aside what the active does
    // not hold, and its sinks that have not confirmed its own rows keep
    // their cursors.
    let was_active = standby_dir(&cfg.data_dir).join(ACTIVE_MARK).exists();
    let mut aside = was_active.then(|| Aside::new(&cfg.data_dir));
    let own = own_sinks(&cfg.data_dir, was_active.then_some(&history))?;
    let mut forks = Forks::load(&cfg.data_dir);
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
                if may_take_over(sb, arbiters.as_ref(), &mut no_witness_said).await {
                    tracing::warn!("standby: the active has been away for {takeover:?}: taking over");
                    return Ok(Outcome::Takeover);
                }
                retry_at = Some(Instant::now() + POLL);
                continue;
            }
            // issued again when it is due (a long follow outlives a certificate)
            r = async { open_session(cfg, &sb.peer, &standby_cert(cfg)?).await } => match r {
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
                    if may_take_over(sb, arbiters.as_ref(), &mut no_witness_said).await {
                        let _ = session.close().await;
                        tracing::warn!("standby: the active has been away for {takeover:?}: taking over");
                        return Ok(Outcome::Takeover);
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
                    let r = match sync_wals(&session, &prefix, &mut stores, &mut hold, &mut forks).await {
                        Ok(()) => match sync_storage(&session, &prefix, &storage, &mut storage_at, aside.as_mut()).await {
                            Ok(()) => match sync_history(&session, &prefix, &history, &mut history_at, &own).await {
                                Ok(()) if polls % FILES_EVERY == 1 => sync_files(&session, &prefix, &cfg.data_dir, &file_key, &mut files, aside.as_mut()).await,
                                r => r,
                            },
                            r => r,
                        },
                        r => r,
                    };
                    match r {
                        Ok(()) => {
                            if polls % FILES_EVERY == 1 {
                                // a complete sync, files included: the
                                // former active's own sets are reported,
                                // and it is a standby like any other
                                if let Some(a) = aside.take() {
                                    for f in a.forks() {
                                        forks.push(f);
                                    }
                                    let _ = std::fs::remove_file(standby_dir(&cfg.data_dir).join(ACTIVE_MARK));
                                }
                            }
                            report_forks(&session, &prefix, &mut forks).await;
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

/// For an active broker with arbiters: resolves when another host holds
/// the lease (at once), or when this host's lease has run out (it could
/// not renew it) and its standby has not asked for [`STANDBY_QUIET`]: a
/// standby that asks follows this broker and cannot take over. The
/// returned text is the audit detail.
pub async fn lease_lost(
    held: std::sync::Arc<std::sync::Mutex<crate::arbiter::Held>>,
    ctl: &wyrm_admin::Control,
) -> &'static str {
    let mut said = false;
    loop {
        tokio::time::sleep(POLL).await;
        let (lost, until) = {
            let h = held.lock().unwrap_or_else(|p| p.into_inner());
            (h.lost, h.until)
        };
        ctl.set_arbiter_lease(until.filter(|_| !lost));
        if lost {
            return "another broker holds the arbiters' lease";
        }
        let run_out = until.is_none_or(|u| std::time::Instant::now() >= u);
        if !run_out {
            said = false;
            continue;
        }
        if ctl.standby_recent(STANDBY_QUIET) {
            if !std::mem::replace(&mut said, true) {
                tracing::warn!("standby: the arbiters' lease ran out (no answer); the standby still follows this broker: running on");
            }
            continue;
        }
        return "the arbiters' lease ran out and the standby is quiet";
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
            arbiter: Vec::new(),
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

    fn scratch(name: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!(
            "wyrmd-standby-{name}-{}-{}",
            std::process::id(),
            now_ms()
        ));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        d
    }

    #[test]
    fn sink_cursors_are_carried_in_local_numbers() {
        let dir = scratch("carry");
        let st = wyrm_history::Store::open(&dir).unwrap();
        let series = st.series_id("wy/s/downstream/m/p", true).unwrap().unwrap();
        let row = |t: u64| {
            (
                series,
                t,
                wyrm_history::encode_row(&Value::Float(1.0), wyrm_core::Quality::Good),
            )
        };
        // a page of the active's numbers 1..=10 arrives as local 1..=3
        // (purged entries and rows written twice make the numbers differ)
        st.write(&[row(1), row(2), row(3)]).unwrap();
        let mut marks = BTreeMap::from([(0, 0)]);
        marks.insert(10, st.last_seq());
        st.write(&[row(4), row(5)]).unwrap();
        marks.insert(20, st.last_seq());
        st.set_sink_seq("gone", Some(1)).unwrap();
        st.set_sink_seq("standby-00000000000000aa", Some(7))
            .unwrap();
        let none = BTreeMap::new();
        let sinks = vec![
            ("pg".to_owned(), 15),
            ("influx".to_owned(), 20),
            ("new".to_owned(), 0),
        ];
        carry_sinks(&st, &marks, &sinks, &none).unwrap();
        assert_eq!(
            st.sink_seq("pg").unwrap(),
            3,
            "the mark at or below 15: rows 4, 5 again"
        );
        assert_eq!(st.sink_seq("influx").unwrap(), 5);
        assert_eq!(st.sink_seq("new").unwrap(), 0);
        assert_eq!(
            st.sink_seq("gone").unwrap(),
            0,
            "the active no longer has it"
        );
        assert_eq!(
            st.sink_seq("standby-00000000000000aa").unwrap(),
            7,
            "our own cursor"
        );
        // a former active's sink with rows of its own keeps its cursor
        st.set_sink_seq("pg", Some(1)).unwrap();
        let own = BTreeMap::from([("pg".to_owned(), 1)]);
        carry_sinks(&st, &marks, &sinks, &own).unwrap();
        assert_eq!(st.sink_seq("pg").unwrap(), 1);
        // a sink behind every mark keeps what it has
        let late = BTreeMap::from([(10, 3)]);
        st.set_sink_seq("influx", Some(2)).unwrap();
        carry_sinks(&st, &late, &[("influx".to_owned(), 4)], &none).unwrap();
        assert_eq!(st.sink_seq("influx").unwrap(), 2);
        drop(st);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn own_sinks_are_kept_until_this_host_is_active() {
        let dir = scratch("own");
        let st = wyrm_history::Store::open(&dir.join("history")).unwrap();
        let series = st.series_id("k", true).unwrap().unwrap();
        let row = |t: u64| {
            (
                series,
                t,
                wyrm_history::encode_row(&Value::Float(1.0), wyrm_core::Quality::Good),
            )
        };
        st.write(&[row(1), row(2), row(3)]).unwrap();
        st.set_sink_seq("behind", Some(1)).unwrap();
        st.set_sink_seq("done", Some(3)).unwrap();
        assert!(own_sinks(&dir, None).unwrap().is_empty());
        let own = own_sinks(&dir, Some(&st)).unwrap();
        assert_eq!(own, BTreeMap::from([("behind".to_owned(), 1)]));
        assert_eq!(own_sinks(&dir, None).unwrap(), own, "kept over a restart");
        mark_active(&dir);
        assert!(own_sinks(&dir, None).unwrap().is_empty(), "active again");
        assert!(standby_dir(&dir).join(ACTIVE_MARK).exists());
        drop(st);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn fork_reports_survive_a_restart() {
        let dir = scratch("forks");
        let mut f = Forks::load(&dir);
        assert!(f.list.is_empty());
        let one = Fork {
            t_ms: 5,
            what: "state".into(),
            count: 3,
            n: 2,
        };
        f.push(one.clone());
        assert_eq!(Forks::load(&dir).list, vec![one]);
        f.list.clear();
        f.save();
        assert!(!standby_dir(&dir).join("forks").exists());
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn a_former_actives_files_are_moved_aside() {
        let dir = scratch("aside");
        std::fs::create_dir_all(dir.join("links/a/data")).unwrap();
        std::fs::write(dir.join("links/a/data/p_1"), b"ours").unwrap();
        let mut a = Aside::new(&dir);
        a.keep_file(&dir, "links/a/data/p_1");
        a.keep_file(&dir, "links/a/data/missing");
        assert!(!dir.join("links/a/data/p_1").exists());
        assert_eq!(
            std::fs::read(a.dir.join("files/links/a/data/p_1")).unwrap(),
            b"ours"
        );
        let forks = a.forks();
        assert_eq!(forks.len(), 1);
        assert_eq!((forks[0].what.as_str(), forks[0].count), ("files", 1));
        assert!(replication::fork_detail("files", 1, 0, a.t_ms).is_some());
        assert!(replication::fork_detail("flows", 4, 1, 0)
            .unwrap()
            .contains("flows/state.stale.1"));
        assert!(replication::fork_detail("secrets", 1, 0, 0).is_none());
        let _ = std::fs::remove_dir_all(&dir);
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
