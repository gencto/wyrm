//! The broker's own update (ADR 0048 §2), opt-in with `updates.mode`.
//!
//! * `off` (the default): nothing is fetched, `update` is refused.
//! * `external`: the releases index is read and `sys` says that a newer
//!   version exists and what to run outside the broker; `update` is refused.
//! * `self`: `sys/~act/update` replaces the broker. The release document is
//!   checked against the pinned keys, the archive against the release, the
//!   new binary is asked what it is and run against a copy of the control
//!   plane, a pre-update backup is made, `update.json` is written,
//!   `current` is switched and the broker stops. The supervisor starts the
//!   new version; [`trial`] judges it at the end of its trial and the
//!   guard ([`crate::release::guard`]) takes a failed one back.
//!
//! The format, the unpack, the layout and the guard are in
//! [`crate::release`]; this module is what a running broker does.

use super::backups::{BackupRequest, SealWith};
use super::*;
use crate::backup::Kind;
use crate::release::{self, Asset, Identity, Layout, Release, UpdateFile};
use std::net::SocketAddr;
use std::sync::atomic::{AtomicBool, AtomicI32, Ordering};
use zeroize::Zeroizing;

/// How often the releases index is read.
const INDEX_EVERY: Duration = Duration::from_secs(6 * 3600);
/// When a read of the index failed: the next one.
const INDEX_RETRY: Duration = Duration::from_secs(300);
/// The index and one release document over the network.
const FETCH_TIMEOUT: Duration = Duration::from_secs(60);
/// An archive over the network.
const ARCHIVE_TIMEOUT: Duration = Duration::from_secs(900);
/// The new binary's `release-info` and `check`.
const BINARY_TIMEOUT: Duration = Duration::from_secs(120);
/// How often a version in its trial writes how long it has run.
const TRIAL_BEAT_S: u64 = 5;
/// How long the health of a trial is asked again at its end.
const TRIAL_GRACE: Duration = Duration::from_secs(10);
/// How long before a start the guard must have run (it runs right before).
const GUARD_FRESH_S: u64 = 300;
/// A standby that asked this long ago is connected.
const STANDBY_SEEN: Duration = Duration::from_secs(20);
/// How long the standby is asked to wait while the active restarts.
const STANDBY_HOLD: Duration = Duration::from_secs(120);
/// One part of the archive a standby fetches.
pub const ORDER_PART: u64 = 1 << 20;

/// `updates.mode` in `wyrmd.json5`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum UpdateMode {
    /// Nothing is fetched and nothing is updated.
    #[default]
    Off,
    /// The broker says that a newer version exists; it is updated outside
    /// (a container image, a distribution package).
    External,
    /// The broker replaces itself.
    SelfUpdate,
}

impl UpdateMode {
    pub fn name(self) -> &'static str {
        match self {
            Self::Off => "off",
            Self::External => "external",
            Self::SelfUpdate => "self",
        }
    }
}

/// `updates` in `wyrmd.json5`, and what `wyrmd` knows that the admin does not.
#[derive(Debug, Clone)]
pub struct UpdateConfig {
    pub mode: UpdateMode,
    /// URL of the signed releases index (`https://`, or `http://` to
    /// loopback); its signature is at `<channel>.sig`.
    pub channel: Option<String>,
    /// The pinned release keys: the built-in ones and `updates.keys`.
    pub keys: Vec<VerifyingKey>,
    /// Seconds the new version has to prove itself.
    pub trial_s: u64,
    /// Days a confirmed update can be rolled back (the old version and the
    /// pre-update backup are kept).
    pub keep_days: u32,
    /// `wyrmd.json5`, for the new binary's check.
    pub config_file: Option<PathBuf>,
    /// Where the user gateway listens, if it runs: part of the health of a
    /// trial.
    pub gateway: Option<SocketAddr>,
    /// This broker is one of a standby pair (ADR 0036).
    pub standby: bool,
    /// Unix seconds this process started (`wyrmd`): the guard ran before
    /// that, not before the daemon opened (a promoted standby opens it
    /// hours after its start). `None`: the daemon's own start.
    pub process_start: Option<u64>,
}

impl Default for UpdateConfig {
    fn default() -> Self {
        Self {
            mode: UpdateMode::Off,
            channel: None,
            keys: Vec::new(),
            trial_s: 180,
            keep_days: 7,
            config_file: None,
            gateway: None,
            standby: false,
            process_start: None,
        }
    }
}

/// What the standby said about itself with its last poll.
#[derive(Debug, Clone, Default, PartialEq)]
struct StandbySaid {
    version: String,
    /// `none`, `trial`, `confirmed`, `rolled_back`, `failed`.
    state: String,
    /// The version that state is about.
    to: String,
    at: Option<std::time::Instant>,
}

/// A release staged for the standby to fetch.
#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
struct Order {
    version: String,
    signature: String,
    size: u64,
    sha256: String,
    by: String,
}

const ORDER_DIR: &str = "update.standby";
const ORDER_FILE: &str = "order.json";
const ORDER_RELEASE: &str = "release.json";
const ORDER_ARCHIVE: &str = "archive.tar.gz";

/// The update state of a broker; lives in [`Control`], outlives rebuilds.
pub struct BrokerUpdate {
    /// An update is being prepared (one at a time).
    running: AtomicBool,
    /// What the running job does now (`checking`, `staged`, …).
    step: Mutex<String>,
    /// An update that ended before the broker stopped for it.
    failed: Mutex<Option<BTreeMap<String, Value>>>,
    /// The last releases index that verified, and why the last read
    /// failed (empty: it did not). A failed read never replaces a good
    /// index.
    index: Mutex<Option<release::Index>>,
    index_error: Mutex<String>,
    /// Since when this process sees the clock past `keep_until`.
    past_since: Mutex<Option<std::time::Instant>>,
    standby: Mutex<StandbySaid>,
    order: Mutex<Option<Order>>,
    /// What the standby did with the last order.
    order_result: Mutex<String>,
    /// Exit code the daemon's owner ends the process with; 0: none.
    exit: AtomicI32,
    changed: tokio::sync::watch::Sender<u64>,
}

fn lock<T>(m: &Mutex<T>) -> std::sync::MutexGuard<'_, T> {
    m.lock().unwrap_or_else(|p| p.into_inner())
}

impl BrokerUpdate {
    pub(super) fn open(data_dir: &Path) -> Self {
        // what a broker that stopped left half done
        for scratch in ["update.fetch", "update.check"] {
            let _ = std::fs::remove_dir_all(data_dir.join(scratch));
        }
        let order = std::fs::read(data_dir.join(ORDER_DIR).join(ORDER_FILE))
            .ok()
            .and_then(|b| serde_json::from_slice::<Order>(&b).ok())
            .filter(|o| release::check_version(&o.version).is_ok());
        Self {
            running: AtomicBool::new(false),
            step: Mutex::default(),
            failed: Mutex::default(),
            index: Mutex::default(),
            index_error: Mutex::default(),
            past_since: Mutex::default(),
            standby: Mutex::default(),
            order: Mutex::new(order),
            order_result: Mutex::default(),
            exit: AtomicI32::new(0),
            changed: tokio::sync::watch::channel(0).0,
        }
    }

    fn notify(&self) {
        self.changed.send_modify(|n| *n += 1);
    }

    fn set_step(&self, step: &str) {
        *lock(&self.step) = step.to_owned();
        self.notify();
    }
}

/// Why `update` cannot run now, from what does not depend on the release.
struct Gate<'a> {
    mode: UpdateMode,
    site: &'a str,
    confirm: &'a str,
    /// Another job (a backup, a restore, a package update, an update).
    other_job: Option<String>,
    /// The install layout of this broker, or what is missing.
    layout: Result<(), String>,
    /// The guard ran before this start.
    guard_ran: bool,
    /// An update is in its trial.
    trial: bool,
}

fn gates(g: &Gate) -> Result<(), LinkError> {
    match g.mode {
        UpdateMode::Off => {
            return Err(LinkError::not_supported(
                "updates.mode is \"off\" in wyrmd.json5: this broker does not update itself \
                 (set \"self\" with the install layout of docs/operations.md §2, or \
                 \"external\" to be told about new versions)",
            ))
        }
        UpdateMode::External => return Err(LinkError::not_supported(external_hint(""))),
        UpdateMode::SelfUpdate => {}
    }
    if g.confirm != g.site {
        return Err(LinkError::invalid_parameter(format!(
            "confirm_site: type the site name {:?} to confirm",
            g.site
        )));
    }
    if let Err(e) = &g.layout {
        return Err(LinkError::not_supported(e.clone()));
    }
    if !g.guard_ran {
        return Err(LinkError::not_supported(
            "updates.mode \"self\": the guard did not run before this start, so a failed \
             update could not be taken back. Add ExecStartPre=<prefix>/bin/wyrmd-guard \
             update-guard -c <config> to the unit (docs/operations.md §2) and restart",
        ));
    }
    if g.trial {
        return Err(LinkError::new(
            Status::Busy,
            "an update is in its trial; wait until it is confirmed or rolled back",
        ));
    }
    if let Some(job) = &g.other_job {
        return Err(LinkError::new(
            Status::Busy,
            format!("{job}; the broker is updated when nothing else runs"),
        ));
    }
    Ok(())
}

/// Did the guard run right before the process that started at `started`?
pub fn guard_fresh(stamp: Option<u64>, started: u64) -> bool {
    stamp.is_some_and(|at| at <= started + 2 && at + GUARD_FRESH_S >= started)
}

/// What to do in `external` mode, shown as `sys/update_hint` and as the
/// refusal of `update`.
fn external_hint(latest: &str) -> String {
    let v = if latest.is_empty() {
        "the new version".to_owned()
    } else {
        format!("wyrmd {latest}")
    };
    format!(
        "updates.mode is \"external\": this broker is updated outside it. Make a backup \
         (sys/backups create), then replace the image or the package with {v} and start it \
         again. A container: change the image tag where the container is defined, then \
         `docker compose pull && docker compose up -d`. A package: install it, then \
         `systemctl restart wyrmd`"
    )
}

/// Where the archive of `asset` is: its own URL, or the file beside the
/// index.
fn asset_url(channel: &str, asset: &Asset) -> Result<String, String> {
    if !asset.url.is_empty() {
        return Ok(asset.url.clone());
    }
    let base = channel.split(['?', '#']).next().unwrap_or(channel);
    let (dir, _) = base
        .rsplit_once('/')
        .filter(|(d, _)| d.contains("://") && !d.ends_with(':') && !d.ends_with('/'))
        .ok_or("updates.channel: the URL of a file")?;
    Ok(format!("{dir}/{}", asset.file))
}

/// The control-plane WAL stores and their key files, relative to `data_dir`.
pub const STATE_STORES: [(&str, &str); 4] = [
    ("state", "state.key"),
    ("audit", "state.key"),
    ("flows/state", "flows.key"),
    ("gateway/users", "gateway/hmac.key"),
];

/// A copy of the control plane of `data_dir` in the new private directory
/// `dest`, laid out as a `data_dir`: each WAL as of one sequence number
/// ([`wyrm_state::replicate::copy_to`]) and the key file it is checked
/// with. It is what the new binary's `check --state` opens: the live
/// stores are never written.
pub fn state_copy(data_dir: &Path, dest: &Path) -> Result<(), String> {
    let io = |p: &Path, e: std::io::Error| format!("{}: {e}", p.display());
    if dest.symlink_metadata().is_ok() {
        std::fs::remove_dir_all(dest).map_err(|e| io(dest, e))?;
    }
    super::backups::make_private_dir(dest)?;
    for (dir, key_file) in STATE_STORES {
        let src = data_dir.join(dir);
        if !src.is_dir() {
            continue;
        }
        let key_path = data_dir.join(key_file);
        let text = Zeroizing::new(std::fs::read(&key_path).map_err(|e| io(&key_path, e))?);
        let key = Zeroizing::new(
            std::str::from_utf8(&text)
                .ok()
                .and_then(|t| hex::decode(t.trim()).ok())
                .ok_or_else(|| format!("{key_file}: not a key"))?,
        );
        wyrm_state::replicate::copy_to(&src, &key, &dest.join(dir))
            .map_err(|e| format!("{dir}: {e}"))?;
        let to = dest.join(key_file);
        if !to.exists() {
            secret::write_private(&to, &text).map_err(|e| io(&to, e))?;
        }
    }
    Ok(())
}

/// Removes the directory when dropped (a state copy holds key files).
struct Scratch(PathBuf);

impl Drop for Scratch {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

/// Unpack the archive of `release` and prove the binary in it, without
/// touching what runs: the archive against `asset` (SHA-256 first), the
/// binary's own `release-info` against the signed release, and its `check`
/// of this configuration against a copy of the control plane. Returns the
/// binary's path in `<prefix>/versions/<version>`; on an error the version
/// directory is removed.
pub async fn stage(
    data_dir: &Path,
    config_file: Option<&Path>,
    layout: &Layout,
    archive: &Path,
    release: &Release,
    asset: &Asset,
    document: &[u8],
    signature: &str,
) -> Result<PathBuf, String> {
    let config = config_file
        .ok_or("this broker was not started from a configuration file")?
        .to_owned();
    let (versions, version) = (layout.versions(), release.version.clone());
    if layout.current_version().as_deref() == Some(version.as_str()) {
        return Err(format!("wyrmd {version} is the version that runs"));
    }
    let (a, asset2, v2, vs2) = (
        archive.to_owned(),
        asset.clone(),
        version.clone(),
        versions.clone(),
    );
    let (doc2, sig2) = (document.to_vec(), signature.to_owned());
    let bin = tokio::task::spawn_blocking(move || {
        let bin = release::unpack(&a, &asset2, &vs2, &v2)?;
        // the signed release stays with the binary: the guard and the
        // broker check the binary against it before every start
        if let Err(e) = release::keep_release(&vs2, &v2, &doc2, &sig2) {
            let _ = std::fs::remove_dir_all(vs2.join(&v2));
            return Err(e);
        }
        Ok::<_, String>(bin)
    })
    .await
    .map_err(|e| e.to_string())??;
    let proved = async {
        let said = release::run_binary(&bin, &["release-info".into()], BINARY_TIMEOUT).await?;
        let id: Identity = serde_json::from_str(said.trim())
            .map_err(|e| format!("release-info of the new binary: {e}"))?;
        if id.version != release.version
            || id.schemas != release.schemas
            || id.replication != release.replication
            || id.target != release::identity().target
        {
            return Err(format!(
                "the binary in the archive says it is wyrmd {} for {} (schemas {:?}, \
                 replication {}); the signed release says {} (schemas {:?}, replication {})",
                id.version,
                id.target,
                id.schemas,
                id.replication,
                release.version,
                release.schemas,
                release.replication
            ));
        }
        let copy = Scratch(data_dir.join("update.check"));
        let (d, c) = (data_dir.to_owned(), copy.0.clone());
        tokio::task::spawn_blocking(move || state_copy(&d, &c))
            .await
            .map_err(|e| e.to_string())??;
        let args: Vec<std::ffi::OsString> = vec![
            "-c".into(),
            config.into_os_string(),
            "check".into(),
            "--state".into(),
            copy.0.clone().into_os_string(),
        ];
        release::run_binary(&bin, &args, BINARY_TIMEOUT)
            .await
            .map_err(|e| {
                format!("the new version refuses this broker's configuration or state: {e}")
            })?;
        Ok(())
    }
    .await;
    if let Err(e) = proved {
        let _ = std::fs::remove_dir_all(versions.join(&version));
        return Err(e);
    }
    Ok(bin)
}

/// One update to do, checked as far as the request itself goes.
struct Plan {
    release: Release,
    release_bytes: Vec<u8>,
    signature: String,
    asset: Asset,
    source: Source,
    by: String,
    /// For the standby to fetch, not for this broker.
    for_standby: bool,
}

enum Source {
    Url(String),
    /// An upload of `sys/backups/~act/restore_begin`.
    Upload(String),
}

fn upd_map(u: &UpdateFile) -> BTreeMap<String, Value> {
    let at = if u.ended != 0 { u.ended } else { u.started };
    let mut m = BTreeMap::from([
        ("from".to_owned(), Value::from(u.from.clone())),
        ("to".to_owned(), Value::from(u.to.clone())),
        ("result".to_owned(), Value::from(u.state.clone())),
        ("at".to_owned(), Value::UInt(at)),
        ("started".to_owned(), Value::UInt(u.started)),
        ("by".to_owned(), Value::from(u.by.clone())),
        ("reason".to_owned(), Value::from(u.reason.clone())),
        ("attempts".to_owned(), Value::UInt(u.attempts.into())),
        ("deadline".to_owned(), Value::UInt(u.deadline)),
        ("trial_s".to_owned(), Value::UInt(u.trial_s)),
        ("ran_s".to_owned(), Value::UInt(u.ran_s)),
        ("keep_until".to_owned(), Value::UInt(u.keep_until)),
        ("restored".to_owned(), Value::Bool(u.restored)),
        ("without_s".to_owned(), Value::UInt(u.without_s)),
        ("links".to_owned(), Value::UInt(u.links.len() as u64)),
        ("backup".to_owned(), Value::from(u.backup_id.clone())),
        (
            "schemas_moved".to_owned(),
            Value::Array(u.moved().into_iter().map(Value::from).collect()),
        ),
    ]);
    if !u.role.is_empty() {
        m.insert("role".to_owned(), Value::from(u.role.clone()));
    }
    m
}

impl Control {
    pub fn updates(&self) -> &UpdateConfig {
        &self.cfg.updates
    }

    /// The exit code the process must end with after the daemon stopped
    /// (76: a new version gave its trial up, ADR 0048 §2.5).
    pub fn exit_code(&self) -> Option<i32> {
        match self.update.exit.load(Ordering::SeqCst) {
            0 => None,
            c => Some(c),
        }
    }

    fn layout(&self) -> Result<Layout, String> {
        Layout::of_broker(&self.cfg.link_exe, &release::identity().version)
    }

    fn guard_ran(&self) -> bool {
        // the guard runs right before the process starts
        let started = self.cfg.updates.process_start.unwrap_or(self.started);
        guard_fresh(release::guard_stamp(&self.cfg.data_dir), started)
    }

    /// Another job that runs now, in words.
    fn other_job(&self) -> Option<String> {
        if self.update.running.load(Ordering::SeqCst) {
            return Some("an update of the broker is being prepared".into());
        }
        if self.backups().list().iter().any(|j| j.status == "running") {
            return Some("a backup is being made".into());
        }
        if self
            .backups()
            .list()
            .iter()
            .any(|j| j.send_status == "sending")
        {
            return Some("a backup is being sent".into());
        }
        if self
            .cfg
            .data_dir
            .join(super::restore_broker::PENDING)
            .exists()
        {
            return Some("a restore is staged for the next start".into());
        }
        if let Some(name) = lock(&self.updating).keys().next() {
            return Some(format!(
                "package {name} is being installed, updated or rolled back"
            ));
        }
        if let Some(id) = lock(&self.link_ops).iter().next() {
            return Some(format!("link {id} is being restored"));
        }
        None
    }

    fn latest_release(&self) -> Option<Release> {
        lock(&self.update.index).as_ref().and_then(|i| {
            i.latest(&release::identity().target)
                .map(|s| s.release.clone())
        })
    }

    /// `(latest, update_available, update_state, update_last, hint)` as
    /// `sys` shows them.
    fn update_view(&self) -> (String, bool, String, BTreeMap<String, Value>, String) {
        let me = release::identity();
        let latest = self.latest_release();
        let latest_v = latest
            .as_ref()
            .map(|r| r.version.clone())
            .unwrap_or_default();
        let available = latest.is_some_and(|r| release::newer(&r.version, &me.version));
        let file = UpdateFile::load(&self.cfg.data_dir);
        let step = lock(&self.update.step).clone();
        let (state, mut last) = if self.update.running.load(Ordering::SeqCst) {
            let s = if step == "staged" { "staged" } else { "none" };
            (
                s.to_owned(),
                BTreeMap::from([("step".to_owned(), Value::from(step))]),
            )
        } else if let Some(f) = lock(&self.update.failed).clone() {
            ("none".to_owned(), f)
        } else {
            match &file {
                Some(u) => (u.state.clone(), upd_map(u)),
                None => ("none".to_owned(), BTreeMap::new()),
            }
        };
        if let Some(r) = self.latest_release() {
            last.insert("latest_date".to_owned(), Value::from(r.date));
            last.insert("latest_notes".to_owned(), Value::from(r.notes));
        }
        let hint = match self.cfg.updates.mode {
            UpdateMode::Off => String::new(),
            UpdateMode::External => external_hint(&latest_v),
            UpdateMode::SelfUpdate => {
                let index_error = lock(&self.update.index_error).clone();
                match self.layout() {
                    Err(e) => e,
                    Ok(_) if !self.guard_ran() => "the guard did not run before this start: \
                                                   update is refused (docs/operations.md §2)"
                        .into(),
                    Ok(_) if !index_error.is_empty() => format!("releases index: {index_error}"),
                    Ok(_) if self.cfg.updates.channel.is_none() => {
                        "no updates.channel: an update is brought as a signed archive".into()
                    }
                    Ok(_) => String::new(),
                }
            }
        };
        (latest_v, available, state, last, hint)
    }

    /// Read the releases index of `updates.channel` now.
    async fn poll_index(&self) -> Result<(), String> {
        let u = &self.cfg.updates;
        let Some(channel) = u.channel.as_deref().filter(|_| u.mode != UpdateMode::Off) else {
            return Err("no updates.channel".into());
        };
        // one file holds the index and its signature: a reader never has one
        // without the other
        let r = async {
            let bytes = crate::fetch::get(channel, release::MAX_CHANNEL, FETCH_TIMEOUT).await?;
            let index = release::read_channel(&bytes, &u.keys)?;
            // an older index than one read before was put back
            release::note_sequence(&self.cfg.data_dir, index.sequence)?;
            Ok::<_, String>(index)
        }
        .await;
        let out = match r {
            Ok(index) => {
                *lock(&self.update.index) = Some(index);
                lock(&self.update.index_error).clear();
                Ok(())
            }
            Err(e) => {
                debug!("releases index: {e}");
                // the index read before stays; the read is tried again soon
                lock(&self.update.index_error).clone_from(&e);
                Err(e)
            }
        };
        self.update.notify();
        out
    }

    /// At the start of the daemon, once the audit is open: the record of an
    /// update the guard took back (or could not), and the files of an
    /// update that is over.
    pub fn update_started(&self) {
        let d = &self.cfg.data_dir;
        let Some(mut u) = UpdateFile::load(d) else {
            return;
        };
        if matches!(u.state.as_str(), "rolled_back" | "failed") && !u.audited {
            let status = if u.state == "failed" {
                Status::InternalError
            } else {
                Status::Ok
            };
            self.record(
                "system",
                "update_rollback",
                &u.to,
                status,
                &format!(
                    "{} to {}: {}; control plane restored: {}",
                    u.to, u.from, u.reason, u.restored
                ),
            );
            warn!(from = %u.to, to = %u.from, state = %u.state, "broker update: {}", u.reason);
            u.audited = true;
            if let Err(e) = u.save(d) {
                warn!("update.json: {e}");
            }
        }
        self.update_housekeeping(true);
    }

    /// Unpin the pre-update backup and remove version directories nobody
    /// can go back to.
    fn update_housekeeping(&self, at_start: bool) {
        let d = &self.cfg.data_dir;
        let Some(mut u) = UpdateFile::load(d) else {
            return;
        };
        // after a rollback: only once the version it left current came up
        if u.state == "rolled_back" && !u.settled {
            return;
        }
        let now = now_s();
        // how long this process has seen the clock past `keep_until`
        let past_s = {
            let mut since = lock(&self.update.past_since);
            if u.state == "confirmed" && now > u.keep_until {
                since
                    .get_or_insert_with(std::time::Instant::now)
                    .elapsed()
                    .as_secs()
            } else {
                *since = None;
                0
            }
        };
        let counted = u.expired_starts;
        let over = u.expire(now, at_start, past_s);
        if u.expired_starts != counted {
            if let Err(e) = u.save(d) {
                warn!("update.json: {e}");
            }
        }
        if !over {
            return;
        }
        if !u.backup_id.is_empty() && self.backups().get(&u.backup_id).is_some_and(|j| j.pinned) {
            self.backups().update(&u.backup_id, |j| j.pinned = false);
            if let Some(j) = self.backups().get(&u.backup_id) {
                self.save_job(&j);
            }
        }
        if let Ok(layout) = self.layout() {
            let me = release::identity().version.clone();
            let gone = layout.prune(&[me.as_str()]);
            if !gone.is_empty() {
                info!(versions = ?gone, "old wyrmd versions removed");
            }
        }
    }

    /// The standby's report with one poll (`sys/replication/update/…`), and
    /// the order for it, if there is one.
    pub(super) fn standby_update_report(&self, version: &str, state: &str, to: &str) -> Value {
        let ok = release::check_version(version).is_ok()
            && matches!(
                state,
                "none" | "trial" | "confirmed" | "rolled_back" | "failed"
            )
            && (to == "-" || release::check_version(to).is_ok());
        if !ok {
            return Value::Map(BTreeMap::from([(
                "error".to_owned(),
                Value::from("version, state, to"),
            )]));
        }
        let said = StandbySaid {
            version: version.to_owned(),
            state: state.to_owned(),
            to: to.to_owned(),
            at: Some(std::time::Instant::now()),
        };
        let changed = {
            let mut s = lock(&self.update.standby);
            let changed = s.version != said.version || s.state != said.state || s.to != said.to;
            *s = said;
            changed
        };
        let order = lock(&self.update.order).clone();
        let mut out = BTreeMap::new();
        if let Some(o) = order {
            let done = version == o.version && matches!(state, "confirmed" | "none");
            let refused = to == o.version && matches!(state, "rolled_back" | "failed");
            if done || refused {
                *lock(&self.update.order) = None;
                let _ = std::fs::remove_dir_all(self.cfg.data_dir.join(ORDER_DIR));
                let (op, status, text) = if done {
                    ("update_confirmed", Status::Ok, "confirmed")
                } else {
                    ("update_rollback", Status::InternalError, state)
                };
                *lock(&self.update.order_result) = format!("{} {text}", o.version);
                self.record(
                    &o.by,
                    op,
                    "standby",
                    status,
                    &format!("the standby runs {version}; wyrmd {}: {text}", o.version),
                );
            } else if version != o.version && state != "trial" {
                let release = std::fs::read(self.cfg.data_dir.join(ORDER_DIR).join(ORDER_RELEASE))
                    .unwrap_or_default();
                out.insert(
                    "order".to_owned(),
                    Value::Map(BTreeMap::from([
                        ("version".to_owned(), Value::from(o.version)),
                        ("release".to_owned(), Value::Bytes(release)),
                        ("signature".to_owned(), Value::from(o.signature)),
                        ("size".to_owned(), Value::UInt(o.size)),
                        ("sha256".to_owned(), Value::from(o.sha256)),
                    ])),
                );
            }
        }
        if changed {
            self.update.notify();
        }
        Value::Map(out)
    }

    /// One part of the archive staged for the standby.
    pub(super) fn standby_update_part(&self, offset: u64, len: u64) -> Result<Vec<u8>, String> {
        use std::io::{Read, Seek, SeekFrom};
        let order = lock(&self.update.order)
            .clone()
            .ok_or("no update is staged for the standby")?;
        if offset > order.size {
            return Err("offset: beyond the archive".into());
        }
        let path = self.cfg.data_dir.join(ORDER_DIR).join(ORDER_ARCHIVE);
        let io = |e: std::io::Error| format!("{}: {e}", path.display());
        let mut f = std::fs::File::open(&path).map_err(io)?;
        f.seek(SeekFrom::Start(offset)).map_err(io)?;
        let want = len.clamp(1, ORDER_PART).min(order.size - offset) as usize;
        let mut buf = vec![0u8; want];
        f.read_exact(&mut buf).map_err(io)?;
        Ok(buf)
    }

    /// `(version, what it does with an update)` of the standby, while it is
    /// connected.
    fn standby_said(&self) -> Option<(String, String)> {
        let s = lock(&self.update.standby).clone();
        s.at.filter(|t| t.elapsed() < STANDBY_SEEN)?;
        let about = if s.to == "-" {
            s.state
        } else {
            format!("{} {}", s.to, s.state)
        };
        Some((s.version, about))
    }

    /// With a standby pair: may the active go to `r` now? The standby goes
    /// first and must run that version, proven, and follow this broker.
    fn standby_first(&self, r: &Release, without: bool) -> Result<(), LinkError> {
        if !self.cfg.updates.standby {
            return Ok(());
        }
        if r.replication != release::identity().replication {
            return Err(LinkError::not_supported(format!(
                "wyrmd {} changes the replication protocol of a standby pair ({} to {}): \
                 the pair cannot update itself one host after the other. Update both hosts \
                 by hand with the standby stopped (docs/operations.md §2)",
                r.version,
                release::identity().replication,
                r.replication
            )));
        }
        let said = lock(&self.update.standby).clone();
        let seen = said.at.is_some_and(|t| t.elapsed() < STANDBY_SEEN);
        if !seen {
            if without {
                return Ok(());
            }
            return Err(LinkError::new(
                Status::Busy,
                "the standby does not follow this broker now: start it, update it first \
                 (update with target: \"standby\"), then update this broker. \
                 without_standby: true updates this broker alone",
            ));
        }
        if said.version == r.version && matches!(said.state.as_str(), "none" | "confirmed") {
            return Ok(());
        }
        Err(LinkError::new(
            Status::Busy,
            format!(
                "the standby runs wyrmd {} ({}): update the standby first (update with \
                 target: \"standby\") and wait until it follows again on {}",
                said.version, said.state, r.version
            ),
        ))
    }
}

/// A caller's `update` arguments checked against this broker: the release
/// under the pinned keys, and whether this broker may go to it.
///
/// `fresh`: read the releases index now; else the one read last is enough
/// (a dry run answers within the admin's own time limit).
async fn plan_of(
    ctl: &Arc<Control>,
    args: &Value,
    sub: &str,
    fresh: bool,
) -> Result<Plan, LinkError> {
    let u = &ctl.cfg.updates;
    let for_standby = match arg_str(args, "target").unwrap_or("active") {
        "" | "active" => false,
        "standby" => true,
        _ => return Err(LinkError::invalid_parameter("target: active or standby")),
    };
    if for_standby && !u.standby {
        return Err(LinkError::invalid_parameter(
            "target: this broker has no standby (no standby section in wyrmd.json5)",
        ));
    }
    let version = arg_str(args, "version")
        .unwrap_or_default()
        .trim()
        .to_owned();
    let upload = arg_str(args, "upload").unwrap_or_default().to_owned();
    let (release, release_bytes, signature, source) = if upload.is_empty() {
        let channel = u.channel.clone().ok_or_else(|| {
            LinkError::invalid_parameter(
                "no updates.channel: bring the archive (upload) with its release and signature",
            )
        })?;
        let cached = lock(&ctl.update.index).is_some();
        if !fresh && cached {
            // nothing to read
        } else if let Err(e) = ctl.poll_index().await {
            return Err(LinkError::new(
                Status::InternalError,
                format!("releases index: {e}"),
            ));
        }
        let Some(index) = lock(&ctl.update.index).clone() else {
            return Err(LinkError::internal("releases index: not read"));
        };
        // an entry of the index is a release document under its own
        // signature (checked when the index was read): those bytes go on
        let signed = if version.is_empty() {
            index.latest(&release::identity().target).cloned()
        } else {
            index.get(&version).cloned()
        }
        .ok_or_else(|| {
            LinkError::not_found(format!(
                "the releases index has no wyrmd {} for {}",
                if version.is_empty() {
                    "at all"
                } else {
                    &version
                },
                release::identity().target
            ))
        })?;
        let asset = signed
            .release
            .targets
            .get(&release::identity().target)
            .ok_or_else(|| LinkError::not_found("no build for this host"))?;
        let url = asset_url(&channel, asset).map_err(LinkError::invalid_parameter)?;
        (
            signed.release,
            signed.document,
            signed.signature,
            Source::Url(url),
        )
    } else {
        let text = match arg(args, "release") {
            Some(Value::Str(s)) => s.clone().into_bytes(),
            Some(Value::Bytes(b)) => b.clone(),
            _ => {
                return Err(LinkError::invalid_parameter(
                    "release: the release document that came with the archive",
                ))
            }
        };
        let signature = arg_str(args, "signature").unwrap_or_default().to_owned();
        let r = release::read_release(&text, &signature, &u.keys)
            .map_err(LinkError::invalid_parameter)?;
        if !version.is_empty() && version != r.version {
            return Err(LinkError::invalid_parameter(format!(
                "version: the release is wyrmd {}",
                r.version
            )));
        }
        (r, text, signature, Source::Upload(upload))
    };
    let asset = release
        .compatible(release::identity())
        .map_err(|e| LinkError::new(Status::InvalidParameter, e))?
        .clone();
    if !release.moves(release::identity()).is_empty() && ctl.cfg.anchor_dir.is_some() {
        return Err(LinkError::not_supported(format!(
            "wyrmd {} moves the SCHEMA of {} and state_anchor_dir is set: a rollback would \
             restore a WAL older than its anchor. Update this broker by hand \
             (docs/operations.md §2)",
            release.version,
            release.moves(release::identity()).join(", ")
        )));
    }
    Ok(Plan {
        release,
        release_bytes,
        signature,
        asset,
        source,
        by: sub.to_owned(),
        for_standby,
    })
}

/// The gates of `update` that do not need the release.
fn gate_now(ctl: &Control, args: &Value) -> Result<(), LinkError> {
    gates(&Gate {
        mode: ctl.cfg.updates.mode,
        site: &ctl.cfg.site,
        confirm: arg_str(args, "confirm_site").unwrap_or_default(),
        other_job: ctl.other_job(),
        layout: ctl.layout().map(|_| ()),
        guard_ran: ctl.guard_ran(),
        trial: UpdateFile::load(&ctl.cfg.data_dir).is_some_and(|u| u.in_trial()),
    })
}

/// `sys/~act/update?check` (spec 05 0.2.33): everything `update` refuses
/// before it fetches the archive.
pub(super) async fn check(ctl: &Arc<Control>, args: &Value, sub: &str) -> Result<(), LinkError> {
    gate_now(ctl, args)?;
    let plan = plan_of(ctl, args, sub, false).await?;
    if !plan.for_standby {
        let without = matches!(arg(args, "without_standby"), Some(Value::Bool(true)));
        ctl.standby_first(&plan.release, without)?;
    }
    Ok(())
}

/// `sys/~act/update`: check, answer, and go on in the background.
pub(super) async fn update(
    ctl: &Arc<Control>,
    ctx: &LinkCtx,
    args: &Value,
    sub: &str,
) -> wyrm_link_sdk::Result<Option<Value>> {
    gate_now(ctl, args)?;
    let plan = plan_of(ctl, args, sub, true).await?;
    let without = matches!(arg(args, "without_standby"), Some(Value::Bool(true)));
    if !plan.for_standby {
        ctl.standby_first(&plan.release, without)?;
    }
    // counted like a long action: a rebuild of the router waits for it
    ctl.inflight.fetch_add(1, Ordering::SeqCst);
    let busy = BusyOwned(ctl.clone());
    if ctl.closing.load(Ordering::SeqCst) {
        return Err(LinkError::new(
            Status::Busy,
            "the broker is restarting; try again",
        ));
    }
    if ctl.update.running.swap(true, Ordering::SeqCst) {
        return Err(LinkError::new(
            Status::Busy,
            "an update of the broker is being prepared",
        ));
    }
    // The broker is taken as a restore with `mode: replace` takes it (the
    // claim of ADR 0048 §1.9): refused while a package or a link is held by
    // an operation, and no install, update, rollback or restore starts
    // until this update ends or the broker has restarted.
    let exclusive = !plan.for_standby;
    if exclusive {
        if let Err(e) = ctl.replacing(true) {
            ctl.update.running.store(false, Ordering::SeqCst);
            return Err(e);
        }
    }
    // the upload is taken now: a wrong id is refused in the answer
    let archive = match &plan.source {
        Source::Upload(id) => match ctl.upload_take(id) {
            Ok(p) => Some(p),
            Err(e) => {
                if exclusive {
                    let _ = ctl.replacing(false);
                }
                ctl.update.running.store(false, Ordering::SeqCst);
                return Err(e);
            }
        },
        Source::Url(_) => None,
    };
    *lock(&ctl.update.failed) = None;
    ctl.update.set_step("starting");
    let (to, standby) = (plan.release.version.clone(), plan.for_standby);
    let message = if standby {
        format!("wyrmd {to} is being staged for the standby; follow sys/standby_update")
    } else {
        format!(
            "wyrmd {to} is being checked; the broker restarts once when it is ready. \
             Follow sys/update_state and sys/update_last"
        )
    };
    let (ctl2, session) = (ctl.clone(), ctx.client().clone());
    tokio::spawn(async move {
        let _busy = busy;
        let (by, to) = (plan.by.clone(), plan.release.version.clone());
        let upload = match &plan.source {
            Source::Upload(id) => Some(id.clone()),
            Source::Url(_) => None,
        };
        let r = run(&ctl2, &session, plan, archive, without).await;
        if let Some(id) = upload {
            ctl2.upload_release(&id, true);
        }
        let _ = std::fs::remove_dir_all(ctl2.cfg.data_dir.join("update.fetch"));
        ctl2.update.running.store(false, Ordering::SeqCst);
        match r {
            Ok(()) => ctl2.update.set_step(""),
            Err(e) => {
                // nothing was switched: the broker is free again
                if exclusive {
                    let _ = ctl2.replacing(false);
                }
                warn!(to = %to, "broker update: {e}");
                let key = if standby { "standby" } else { to.as_str() };
                ctl2.record(&by, "update_start", key, Status::InternalError, &e);
                *lock(&ctl2.update.failed) = Some(BTreeMap::from([
                    ("to".to_owned(), Value::from(to)),
                    ("result".to_owned(), Value::from("failed")),
                    ("reason".to_owned(), Value::from(e)),
                    ("at".to_owned(), Value::UInt(now_s())),
                    ("by".to_owned(), Value::from(by)),
                ]));
                ctl2.update.set_step("");
            }
        }
    });
    Ok(Some(Value::Map(BTreeMap::from([
        ("success".to_owned(), Value::Bool(true)),
        ("message".to_owned(), Value::from(message)),
        ("version".to_owned(), Value::from(to)),
        ("restart".to_owned(), Value::Bool(!standby)),
    ]))))
}

/// The update itself, after the answer.
async fn run(
    ctl: &Arc<Control>,
    session: &Session,
    plan: Plan,
    archive: Option<PathBuf>,
    without_standby: bool,
) -> Result<(), String> {
    let d = ctl.cfg.data_dir.clone();
    let me = release::identity();
    // 1. the archive
    ctl.update.set_step("fetching");
    let archive = match (archive, &plan.source) {
        (Some(p), _) => p,
        (None, Source::Url(url)) => {
            let bytes = crate::fetch::get(url, plan.asset.size as usize, ARCHIVE_TIMEOUT).await?;
            let dir = d.join("update.fetch");
            let _ = std::fs::remove_dir_all(&dir);
            super::backups::make_private_dir(&dir)?;
            let path = dir.join(ORDER_ARCHIVE);
            let p2 = path.clone();
            tokio::task::spawn_blocking(move || secret::write_private(&p2, &bytes))
                .await
                .map_err(|e| e.to_string())?
                .map_err(|e| format!("{}: {e}", path.display()))?;
            path
        }
        (None, Source::Upload(_)) => return Err("the upload is gone".into()),
    };
    if plan.for_standby {
        return stage_for_standby(ctl, &plan, &archive).await;
    }
    // 2. unpack and prove the binary
    ctl.update.set_step("checking");
    let layout = ctl.layout()?;
    let bin = stage(
        &d,
        ctl.cfg.updates.config_file.as_deref(),
        &layout,
        &archive,
        &plan.release,
        &plan.asset,
        &plan.release_bytes,
        &plan.signature,
    )
    .await?;
    ctl.update.set_step("staged");
    let undo = |e: String| {
        let _ = std::fs::remove_dir_all(layout.versions().join(&plan.release.version));
        e
    };
    // 3. the pre-update backup: the control plane as it is now
    ctl.update.set_step("backup");
    let (ctl2, by2) = (ctl.clone(), plan.by.clone());
    let job = tokio::task::spawn_blocking(move || {
        ctl2.backup_now(
            BackupRequest {
                kind: Kind::Broker,
                sections: Vec::new(),
                links: None,
                link: None,
                history_days: None,
                // sealed for this broker: the guard checks the manifest
                // with the key of secrets.key before it restores from it
                seal: SealWith::Broker,
                label: "pre-update".into(),
                pinned: true,
                remote: false,
                estimate: false,
            },
            &by2,
        )
    })
    .await
    .map_err(|e| e.to_string())?
    .map_err(|e| undo(format!("pre-update backup: {e}")))?;
    // nothing else may have started meanwhile, and the standby is where it was
    if let Some(job) = other_job_but_update(ctl) {
        return Err(undo(job));
    }
    ctl.standby_first(&plan.release, without_standby)
        .map_err(|e| undo(e.message))?;
    // 4. commit: the guard is the version that runs, then the state, then
    //    the switch
    ctl.update.set_step("staged");
    let reg = ctl.registry();
    let (_, live) = live_tokens(session, &ctl.cfg.site).await;
    let links: Vec<String> = reg
        .links
        .keys()
        .filter(|id| live.contains(*id))
        .cloned()
        .collect();
    let now = now_s();
    let previous = UpdateFile::load(&d);
    let u = UpdateFile {
        from: me.version.clone(),
        to: plan.release.version.clone(),
        state: "trial".into(),
        attempts: 0,
        // the trial begins when the new version starts
        trial_s: ctl.cfg.updates.trial_s,
        deadline: 0,
        backup_id: job.id.clone(),
        backup: job.file.clone(),
        backup_sha256: job.sha256.clone(),
        from_schemas: me.schemas.clone(),
        to_schemas: plan.release.schemas.clone(),
        stores: release::stores_of(&d),
        links,
        by: plan.by.clone(),
        started: now,
        role: "active".into(),
        ..Default::default()
    };
    let exe = ctl.cfg.link_exe.clone();
    let (layout2, u2, d2) = (layout.clone(), u.clone(), d.clone());
    tokio::task::spawn_blocking(move || -> Result<(), String> {
        if !layout2.guard_is(&exe) {
            layout2.refresh_guard(&exe)?;
        }
        u2.save(&d2)?;
        if let Err(e) = layout2.switch(&u2.to) {
            let _ = std::fs::remove_file(d2.join(release::STATE_FILE));
            return Err(e);
        }
        // the version before the one that runs can no longer be gone back to
        layout2.prune(&[u2.from.as_str(), u2.to.as_str()]);
        Ok(())
    })
    .await
    .map_err(|e| e.to_string())?
    .map_err(|e| {
        // the backup of an update that never began is an ordinary one
        ctl.backups().update(&job.id, |j| j.pinned = false);
        undo(e)
    })?;
    // the backup of the update before this one is no longer needed
    if let Some(p) = previous.filter(|p| !p.backup_id.is_empty() && p.backup_id != job.id) {
        ctl.backups().update(&p.backup_id, |j| j.pinned = false);
        if let Some(j) = ctl.backups().get(&p.backup_id) {
            ctl.save_job(&j);
        }
    }
    debug!(bin = %bin.display(), "broker update: staged");
    ctl.record(
        &plan.by,
        "update_start",
        &u.to,
        Status::Ok,
        &format!(
            "{} to {}; archive sha256 {}; pre-update backup {}; SCHEMA moved: {}; trial {} s",
            u.from,
            u.to,
            plan.asset.sha256,
            job.id,
            match u.moved() {
                m if m.is_empty() => "none".to_owned(),
                m => m.join(", "),
            },
            ctl.cfg.updates.trial_s
        ),
    );
    warn!(from = %u.from, to = %u.to, by = %plan.by, "broker update: stopping for wyrmd {}", u.to);
    // a standby must not take the restart for an absence
    if ctl.cfg.updates.standby {
        ctl.hold_standby(STANDBY_HOLD);
        if ctl.standby_recent(Duration::from_secs(5)) {
            tokio::time::sleep(Duration::from_millis(2500)).await;
        }
    }
    ctl.request_stop();
    Ok(())
}

fn other_job_but_update(ctl: &Control) -> Option<String> {
    let was = ctl.update.running.swap(false, Ordering::SeqCst);
    let job = ctl.other_job();
    ctl.update.running.store(was, Ordering::SeqCst);
    job
}

/// Keep the checked archive and its release for the standby to fetch.
async fn stage_for_standby(ctl: &Arc<Control>, plan: &Plan, archive: &Path) -> Result<(), String> {
    ctl.update.set_step("staging for the standby");
    let dir = ctl.cfg.data_dir.join(ORDER_DIR);
    let (archive, asset, dir2) = (archive.to_owned(), plan.asset.clone(), dir.clone());
    let (release_bytes, signature) = (plan.release_bytes.clone(), plan.signature.clone());
    let order = Order {
        version: plan.release.version.clone(),
        signature,
        size: asset.size,
        sha256: asset.sha256.clone(),
        by: plan.by.clone(),
    };
    let order2 = order.clone();
    tokio::task::spawn_blocking(move || -> Result<(), String> {
        let io = |p: &Path, e: std::io::Error| format!("{}: {e}", p.display());
        let (sha, size) = release::sha256_file(&archive)?;
        if size != asset.size || sha != asset.sha256 {
            return Err("the archive is not the one of the release (size or SHA-256)".into());
        }
        let _ = std::fs::remove_dir_all(&dir2);
        super::backups::make_private_dir(&dir2)?;
        let to = dir2.join(ORDER_ARCHIVE);
        std::fs::copy(&archive, &to).map_err(|e| io(&to, e))?;
        secret::write_private(&dir2.join(ORDER_RELEASE), &release_bytes)
            .map_err(|e| io(&dir2, e))?;
        let text = serde_json::to_vec_pretty(&order2).map_err(|e| e.to_string())?;
        secret::write_private(&dir2.join(ORDER_FILE), &text).map_err(|e| io(&dir2, e))
    })
    .await
    .map_err(|e| e.to_string())??;
    *lock(&ctl.update.order_result) = String::new();
    *lock(&ctl.update.order) = Some(order.clone());
    ctl.record(
        &plan.by,
        "update_start",
        "standby",
        Status::Ok,
        &format!(
            "wyrmd {} staged for the standby; archive sha256 {}",
            order.version, order.sha256
        ),
    );
    ctl.update.notify();
    Ok(())
}

/// `sys/~act/rollback_update`: go back to the version before a confirmed
/// update, on purpose. The guard does it at the next start.
pub(super) async fn rollback(
    ctl: &Arc<Control>,
    args: &Value,
    sub: &str,
    remote: bool,
) -> wyrm_link_sdk::Result<Option<Value>> {
    if remote {
        return Err(LinkError::new(
            Status::PermissionDenied,
            "rollback_update puts the control plane back as it was before the update: it is \
             done on the broker's own gateway, not through its upstream",
        ));
    }
    let d = &ctl.cfg.data_dir;
    let me = &release::identity().version;
    let mut u = UpdateFile::load(d)
        .filter(|u| u.state == "confirmed" && &u.to == me)
        .ok_or_else(|| LinkError::not_found("no confirmed update to roll back"))?;
    gates(&Gate {
        mode: ctl.cfg.updates.mode,
        site: &ctl.cfg.site,
        confirm: arg_str(args, "confirm_site").unwrap_or_default(),
        other_job: ctl.other_job(),
        layout: ctl.layout().map(|_| ()),
        guard_ran: ctl.guard_ran(),
        trial: false,
    })?;
    // while the old version and the backup are kept: the clock alone does
    // not end it (see `UpdateFile::expire`)
    let layout = ctl.layout().map_err(LinkError::not_supported)?;
    if !layout.bin_of(&u.from).is_file() {
        return Err(LinkError::not_found(format!(
            "wyrmd {} is no longer kept (updates.keep_days are over)",
            u.from
        )));
    }
    if !u.moved().is_empty() && ctl.backups().get(&u.backup_id).is_none() {
        return Err(LinkError::not_found(format!(
            "the pre-update backup {} is gone and the update moved the SCHEMA of {}",
            u.backup_id,
            u.moved().join(", ")
        )));
    }
    let _busy = ctl.busy()?;
    // held until the broker has stopped (see `update`)
    ctl.replacing(true)?;
    u.rollback = sub.to_owned();
    if let Err(e) = u.save(d) {
        let _ = ctl.replacing(false);
        return Err(LinkError::internal(e));
    }
    ctl.record(
        sub,
        "update_rollback",
        &u.to,
        Status::Ok,
        &format!(
            "asked: {} back to {}; done by the guard at the next start; control plane \
             restored from {}: {}",
            u.to,
            u.from,
            u.backup_id,
            !u.moved().is_empty()
        ),
    );
    warn!(by = sub, from = %u.to, to = %u.from, "broker update: rollback asked; stopping");
    if ctl.cfg.updates.standby {
        ctl.hold_standby(STANDBY_HOLD);
    }
    let stop = ctl.clone();
    tokio::spawn(async move {
        tokio::time::sleep(Duration::from_millis(500)).await;
        stop.request_stop();
    });
    Ok(Some(Value::Map(BTreeMap::from([
        ("success".to_owned(), Value::Bool(true)),
        (
            "message".to_owned(),
            Value::from(format!(
                "the broker restarts on wyrmd {}; changes made after the update are lost \
                 where the update moved a SCHEMA",
                u.from
            )),
        ),
        ("restart".to_owned(), Value::Bool(true)),
    ]))))
}

/// `sys/~act/check_updates`: read the releases index now.
pub(super) async fn check_updates(ctl: &Arc<Control>) -> wyrm_link_sdk::Result<Option<Value>> {
    if ctl.cfg.updates.mode == UpdateMode::Off {
        return Err(LinkError::not_supported("updates.mode is \"off\""));
    }
    ctl.poll_index()
        .await
        .map_err(|e| LinkError::new(Status::InternalError, format!("releases index: {e}")))?;
    let (latest, available, ..) = ctl.update_view();
    Ok(Some(Value::Map(BTreeMap::from([
        ("latest".to_owned(), Value::from(latest)),
        ("update_available".to_owned(), Value::Bool(available)),
    ]))))
}

const VALUES: [(&str, TypeCode, &str); 6] = [
    (
        "latest",
        TypeCode::String,
        "The newest wyrmd of the releases index for this host; empty without an index.",
    ),
    (
        "update_available",
        TypeCode::Bool,
        "The releases index has a newer wyrmd than the one that runs.",
    ),
    (
        "update_state",
        TypeCode::String,
        "Of the broker's own update: none, staged, trial, confirmed, rolled_back, failed.",
    ),
    (
        "update_last",
        TypeCode::Map,
        "The last update: from, to, result, at, by, reason, attempts, deadline, keep_until, \
         restored, without_s, links, backup, schemas_moved; step while one is prepared.",
    ),
    (
        "update_mode",
        TypeCode::String,
        "updates.mode of wyrmd.json5: off, external, self.",
    ),
    (
        "update_hint",
        TypeCode::String,
        "What stands in the way of an update, or how this broker is updated outside it.",
    ),
];

const STANDBY_VALUES: [(&str, &str); 2] = [
    (
        "standby_version",
        "The wyrmd version of the standby that follows this broker; empty while none does.",
    ),
    (
        "standby_update",
        "What the standby does with an update: ordered <v>, <v> trial, <v> confirmed, \
         <v> rolled_back, <v> failed.",
    ),
];

fn site_param() -> ParamMeta {
    str_param()
        .required(true)
        .display("Site name")
        .description("Type the name of this site to confirm")
}

/// The values and actions of `sys` for the broker's update.
pub(super) async fn declare(ctx: &LinkCtx, ctl: &Control) -> wyrm_link_sdk::Result<()> {
    for (key, ty, about) in VALUES {
        ctx.declare_node(key, NodeMeta::leaf(ty).attr("description", about))
            .await?;
    }
    if ctl.cfg.updates.standby {
        for (key, about) in STANDBY_VALUES {
            ctx.declare_node(
                key,
                NodeMeta::leaf(TypeCode::String).attr("description", about),
            )
            .await?;
        }
    }
    ctx.declare_action(
        "",
        "update",
        ActionMeta::new()
            .display("Update broker")
            .param(
                "version",
                str_param()
                    .display("Version")
                    .description("Of the releases index; empty: the latest"),
            )
            .param("confirm_site", site_param())
            .param(
                "upload",
                str_param().display("Upload").description(
                    "Without updates.channel: the id of the archive uploaded in parts \
                     (sys/backups restore_begin, restore_part)",
                ),
            )
            .param(
                "release",
                str_param()
                    .display("Release")
                    .description("With upload: the release document of the archive (JSON)"),
            )
            .param(
                "signature",
                str_param()
                    .display("Signature")
                    .description("With upload: the Ed25519 signature of the release (hex)"),
            )
            .param(
                "target",
                str_param()
                    .display("Target")
                    .enum_values(["active", "standby"])
                    .description("A standby pair: the standby is updated first"),
            )
            .param(
                "without_standby",
                ParamMeta::of(TypeCode::Bool)
                    .display("Without the standby")
                    .description("A standby pair whose standby is down: update this broker alone"),
            )
            .result(ActionResult::Type(TypeCode::Map))
            // the releases index is read before the answer
            .timeout_ms(150_000)
            .level(Perm::Config),
    )
    .await?;
    ctx.declare_action(
        "",
        "rollback_update",
        ActionMeta::new()
            .display("Roll back the broker update")
            .param("confirm_site", site_param())
            .result(ActionResult::Type(TypeCode::Map))
            .level(Perm::Config),
    )
    .await?;
    ctx.declare_action(
        "",
        "check_updates",
        ActionMeta::new()
            .display("Check for updates")
            .result(ActionResult::Type(TypeCode::Map))
            .timeout_ms(150_000)
            .level(Perm::Config),
    )
    .await?;
    publish(ctx, ctl).await;
    Ok(())
}

async fn publish(ctx: &LinkCtx, ctl: &Control) {
    let (latest, available, state, last, hint) = ctl.update_view();
    let mut values = vec![
        ("latest", Value::Str(latest)),
        ("update_available", Value::Bool(available)),
        ("update_state", Value::Str(state)),
        ("update_last", Value::Map(last)),
        ("update_mode", Value::from(ctl.cfg.updates.mode.name())),
        ("update_hint", Value::Str(hint)),
    ];
    if ctl.cfg.updates.standby {
        let (version, mut about) = ctl.standby_said().unwrap_or_default();
        if let Some(o) = &*lock(&ctl.update.order) {
            if !about.starts_with(&o.version) {
                about = format!("ordered {}", o.version);
            }
        } else if about == "none" || about.is_empty() {
            about = lock(&ctl.update.order_result).clone();
        }
        values.push(("standby_version", Value::Str(version)));
        values.push(("standby_update", Value::Str(about)));
    }
    for (key, v) in values {
        if let Err(e) = ctx.update(key, v, Quality::Good, now_us()).await {
            debug!("sys/{key}: {e}");
        }
    }
}

/// Is the new version healthy? `Err` says what is missing.
async fn healthy(ctl: &Control, session: &Session, u: &UpdateFile) -> Result<(), String> {
    let site = &ctl.cfg.site;
    // the admin answers through the router
    let key = format!("wy/{site}/sys/version/~val");
    let answered = async {
        let r = session
            .get(&key)
            .timeout(Duration::from_secs(3))
            .await
            .ok()?;
        r.recv_async().await.ok()?.result().ok().map(|_| ())
    }
    .await;
    if answered.is_none() {
        return Err("the admin does not answer on sys".into());
    }
    if let Some(addr) = ctl.cfg.updates.gateway {
        let addr = if addr.ip().is_unspecified() {
            SocketAddr::from(([127, 0, 0, 1], addr.port()))
        } else {
            addr
        };
        let up = tokio::time::timeout(Duration::from_secs(2), tokio::net::TcpStream::connect(addr))
            .await
            .is_ok_and(|r| r.is_ok());
        if !up {
            return Err(format!("the gateway does not listen on {addr}"));
        }
    }
    let reg = ctl.registry();
    let (_, live) = live_tokens(session, site).await;
    let missing: Vec<&String> = u
        .links
        .iter()
        .filter(|id| reg.links.contains_key(*id) && !live.contains(*id))
        .collect();
    if !missing.is_empty() {
        let shown: Vec<&str> = missing.iter().take(10).map(|s| s.as_str()).collect();
        return Err(format!(
            "{} of {} links are not back: {}",
            missing.len(),
            u.links.len(),
            shown.join(", ")
        ));
    }
    Ok(())
}

/// The trial of a new version (ADR 0048 §2.5), on every router of it: at
/// the end of the trial the version is healthy and confirmed, or it gives
/// up and the process ends with [`release::TRIAL_EXIT`] for the guard.
async fn trial(ctl: &Arc<Control>, session: &Session) {
    let d = &ctl.cfg.data_dir;
    let me = &release::identity().version;
    // the version a rollback left current came up: the guard leaves it
    if let Some(mut u) = UpdateFile::load(d)
        .filter(|u| matches!(u.state.as_str(), "rolled_back" | "failed") && !u.settled)
    {
        u.settled = true;
        u.starts = 0;
        if let Err(e) = u.save(d) {
            warn!("update.json: {e}");
        }
        let ctl2 = ctl.clone();
        let _ = tokio::task::spawn_blocking(move || ctl2.update_housekeeping(false)).await;
        ctl.update.notify();
    }
    let mine = |u: &UpdateFile| u.in_trial() && &u.to == me;
    let Some(mut u) = UpdateFile::load(d).filter(mine) else {
        return;
    };
    if u.without_s == 0 {
        u.without_s = now_s().saturating_sub(u.started).max(1);
        if let Err(e) = u.save(d) {
            warn!("update.json: {e}");
        }
        ctl.update.notify();
    }
    let trial_s = match u.trial_s {
        0 => ctl.cfg.updates.trial_s,
        s => s,
    };
    info!(
        from = %u.from, ran_s = u.ran_s, trial_s,
        "broker update: wyrmd {me} is in its trial"
    );
    // The trial is counted in the time this version ran, written as it
    // runs: a host that was off, or a broker that was down, comes back into
    // the trial it left. The wall clock decides nothing.
    let mut part_ms = 0u128;
    while u.ran_s < trial_s {
        let step = Duration::from_secs((trial_s - u.ran_s).min(TRIAL_BEAT_S));
        let t = tokio::time::Instant::now();
        tokio::time::sleep(step).await;
        part_ms += t.elapsed().as_millis();
        let Some(mut now) = UpdateFile::load(d).filter(mine) else {
            return;
        };
        now.ran_s += (part_ms / 1000) as u64;
        part_ms %= 1000;
        now.deadline = now_s() + trial_s.saturating_sub(now.ran_s);
        if let Err(e) = now.save(d) {
            warn!("update.json: {e}");
        }
        u = now;
    }
    let until = tokio::time::Instant::now() + TRIAL_GRACE;
    let verdict = loop {
        match healthy(ctl, session, &u).await {
            Ok(()) => break Ok(()),
            Err(e) if tokio::time::Instant::now() >= until => break Err(e),
            Err(_) => tokio::time::sleep(Duration::from_secs(1)).await,
        }
    };
    // the file may have moved meanwhile (attempts): read it again
    let Some(mut u) = UpdateFile::load(d).filter(|u| u.in_trial() && &u.to == me) else {
        return;
    };
    match verdict {
        Ok(()) => {
            let now = now_s();
            u.state = "confirmed".into();
            u.ended = now;
            u.keep_until = now + u64::from(ctl.cfg.updates.keep_days) * 86_400;
            u.audited = true;
            if let Err(e) = u.save(d) {
                warn!("update.json: {e}");
                return;
            }
            ctl.record(
                &u.by,
                "update_confirmed",
                &u.to,
                Status::Ok,
                &format!(
                    "{} to {}; {} links back; {} s without the broker; rollback until {}",
                    u.from,
                    u.to,
                    u.links.len(),
                    u.without_s,
                    iso_utc(u.keep_until)
                ),
            );
            info!(from = %u.from, "broker update: wyrmd {me} is confirmed");
            // the guard is now this version
            let (layout, exe) = (ctl.layout(), ctl.cfg.link_exe.clone());
            let r = tokio::task::spawn_blocking(move || match layout {
                Ok(l) if !l.guard_is(&exe) => l.refresh_guard(&exe),
                Ok(_) => Ok(()),
                Err(e) => Err(e),
            })
            .await;
            if let Ok(Err(e)) = r {
                warn!("broker update: the guard is not replaced: {e}");
            }
            ctl.update.notify();
        }
        Err(why) => {
            u.failed = why.clone();
            if let Err(e) = u.save(d) {
                warn!("update.json: {e}");
            }
            warn!("broker update: wyrmd {me} gives its trial up: {why}");
            ctl.update.exit.store(release::TRIAL_EXIT, Ordering::SeqCst);
            ctl.request_stop();
        }
    }
}

/// For as long as this router runs: publishes the update values when they
/// move, reads the releases index, judges a trial, tidies up.
pub(super) async fn watch(ctl: Arc<Control>, ctx: LinkCtx) {
    let session = ctx.client().clone();
    let judge = {
        let (ctl, session) = (ctl.clone(), session.clone());
        tokio::spawn(async move { trial(&ctl, &session).await })
    };
    let mut rx = ctl.update.changed.subscribe();
    let polls = ctl.cfg.updates.mode != UpdateMode::Off && ctl.cfg.updates.channel.is_some();
    let mut next_index = tokio::time::Instant::now();
    let mut tidy = tokio::time::interval(Duration::from_secs(3600));
    let mut standby = tokio::time::interval(Duration::from_secs(5));
    loop {
        if ctx.is_closed() {
            break;
        }
        publish(&ctx, &ctl).await;
        tokio::select! {
            r = rx.changed() => {
                if r.is_err() {
                    break;
                }
                rx.borrow_and_update();
            }
            _ = tokio::time::sleep_until(next_index), if polls => {
                // a read that failed (the file was being replaced, the
                // network was away) is not kept for hours
                let every = match ctl.poll_index().await {
                    Ok(()) => INDEX_EVERY,
                    Err(_) => INDEX_RETRY,
                };
                next_index = tokio::time::Instant::now() + every;
            }
            _ = tidy.tick() => {
                let ctl = ctl.clone();
                let _ = tokio::task::spawn_blocking(move || ctl.update_housekeeping(false)).await;
            }
            // a standby that went quiet drops out of the values
            _ = standby.tick(), if ctl.cfg.updates.standby => {}
        }
    }
    judge.abort();
}

#[cfg(test)]
mod tests {
    use super::*;

    fn gate<'a>() -> Gate<'a> {
        Gate {
            mode: UpdateMode::SelfUpdate,
            site: "plant",
            confirm: "plant",
            other_job: None,
            layout: Ok(()),
            guard_ran: true,
            trial: false,
        }
    }

    #[test]
    fn update_is_refused_with_a_reason_and_an_error_status() {
        assert!(gates(&gate()).is_ok());
        let refused = |g: Gate, status: Status, want: &str| {
            let e = gates(&g).unwrap_err();
            assert_eq!(e.status, status, "{}", e.message);
            assert!(e.message.contains(want), "{}", e.message);
            // a refusal is never a code that reads as success
            assert_eq!(
                wyrm_core::StatusGroup::of(e.status.code()),
                wyrm_core::StatusGroup::Error
            );
        };
        refused(
            Gate {
                mode: UpdateMode::Off,
                ..gate()
            },
            Status::NotSupported,
            "\"off\"",
        );
        refused(
            Gate {
                mode: UpdateMode::External,
                ..gate()
            },
            Status::NotSupported,
            "updated outside",
        );
        refused(
            Gate {
                confirm: "plant2",
                ..gate()
            },
            Status::InvalidParameter,
            "confirm_site",
        );
        refused(
            Gate {
                confirm: "",
                ..gate()
            },
            Status::InvalidParameter,
            "confirm_site",
        );
        refused(
            Gate {
                layout: Err("this broker runs /usr/local/bin/wyrmd, not <prefix>".into()),
                ..gate()
            },
            Status::NotSupported,
            "/usr/local/bin/wyrmd",
        );
        refused(
            Gate {
                guard_ran: false,
                ..gate()
            },
            Status::NotSupported,
            "ExecStartPre",
        );
        refused(
            Gate {
                trial: true,
                ..gate()
            },
            Status::Busy,
            "trial",
        );
        for job in [
            "a backup is being made",
            "a restore is staged for the next start",
            "package demo is being updated",
        ] {
            refused(
                Gate {
                    other_job: Some(job.into()),
                    ..gate()
                },
                Status::Busy,
                job,
            );
        }
    }

    /// The update and the other jobs keep each other out, through the claim
    /// of the package and link operations.
    #[test]
    fn an_update_and_another_job_exclude_each_other() {
        let ctl = super::super::tests::control("broker-update-claims", false, |_| {});
        let d = ctl.cfg.data_dir.clone();
        assert_eq!(ctl.other_job(), None);
        // a package operation: the update sees it and cannot take the broker
        let claim = ctl.claim_package("pkg").unwrap();
        assert!(ctl.other_job().is_some_and(|j| j.contains("package pkg")));
        assert_eq!(ctl.replacing(true).unwrap_err().status, Status::Busy);
        drop(claim);
        // a restore of a link
        let claim = ctl.claim_link("l1").unwrap();
        assert!(ctl.other_job().is_some_and(|j| j.contains("link l1")));
        drop(claim);
        // a staged restore
        std::fs::create_dir_all(d.join(crate::control::restore_broker::PENDING)).unwrap();
        assert!(ctl.other_job().is_some_and(|j| j.contains("restore")));
        std::fs::remove_dir_all(d.join(crate::control::restore_broker::PENDING)).unwrap();
        // the update holds the broker: nothing else starts
        ctl.replacing(true).unwrap();
        assert_eq!(ctl.claim_package("pkg").err().unwrap().status, Status::Busy);
        assert_eq!(ctl.claim_link("l1").err().unwrap().status, Status::Busy);
        // an update that ended before the switch gives it back
        ctl.replacing(false).unwrap();
        drop(ctl.claim_package("pkg").unwrap());
        // one update at a time
        ctl.update.running.store(true, Ordering::SeqCst);
        assert!(ctl
            .other_job()
            .is_some_and(|j| j.contains("update of the broker")));
        let _ = std::fs::remove_dir_all(&d);
    }

    /// The guard ran before the process started; the daemon of a promoted
    /// standby opens hours later.
    #[test]
    fn the_guard_is_looked_for_before_the_process_start() {
        let (stamp, process_start) = (Some(50_000), 50_001);
        assert!(guard_fresh(stamp, process_start));
        // against the time the daemon opened on a promoted standby: stale,
        // which refused every update until the process was started again
        assert!(!guard_fresh(stamp, process_start + 6 * 3600));
        // no guard, a guard of an earlier start, a stamp from the future
        assert!(!guard_fresh(None, process_start));
        assert!(!guard_fresh(Some(50_001 - 3600), process_start));
        assert!(!guard_fresh(Some(50_001 + 60), process_start));
        // the control plane uses the process start when `wyrmd` gives it
        let ctl = super::super::tests::control("broker-update-guard-ran", false, |_| {});
        release::stamp_guard(&ctl.cfg.data_dir, "0.1.0");
        assert!(ctl.guard_ran(), "stamped just now, daemon opened just now");
        assert_eq!(ctl.cfg.updates.process_start, None);
    }

    /// The guard's restore, on a real pre-update backup: a store that was
    /// there comes back, a store that was not is moved aside, and a backup
    /// that cannot be used leaves the old version to start on what is
    /// there. The guard never returns an error for it.
    #[cfg(unix)]
    #[test]
    fn a_rollback_restores_what_was_there_and_never_blocks_the_start() {
        let ctl = super::super::tests::control("broker-update-restore", false, |_| {});
        let d = ctl.cfg.data_dir.clone();
        let pre_update = |seal: SealWith| {
            ctl.backup_now(
                BackupRequest {
                    kind: Kind::Broker,
                    sections: Vec::new(),
                    links: None,
                    link: None,
                    history_days: None,
                    seal,
                    label: "pre-update".into(),
                    pinned: true,
                    remote: false,
                    estimate: false,
                },
                "user:ann",
            )
            .unwrap()
        };
        let job = pre_update(SealWith::Broker);
        assert_eq!(job.sealed, "broker");
        let stores = release::stores_of(&d);
        assert!(stores.contains(&"registry".to_owned()), "{stores:?}");
        assert!(!stores.contains(&"users".to_owned()), "no gateway here");
        // the layout: 0.1.0 put there by hand, 0.2.0 current, in its trial
        let exe = d.join("built");
        std::fs::write(&exe, b"v1").unwrap();
        let l = Layout::install(&d.join("opt"), &exe, "0.1.0").unwrap();
        std::fs::create_dir_all(l.versions().join("0.2.0")).unwrap();
        std::fs::write(l.bin_of("0.2.0"), b"v2").unwrap();
        let schemas = |registry: u32, users: u32| {
            BTreeMap::from([
                ("registry".to_owned(), registry),
                ("users".to_owned(), users),
            ])
        };
        let failed_trial = |backup: &backups::Job, sha: &str| {
            l.switch("0.2.0").unwrap();
            UpdateFile {
                from: "0.1.0".into(),
                to: "0.2.0".into(),
                state: "trial".into(),
                failed: "link plc1 is not back".into(),
                from_schemas: schemas(20, 4),
                to_schemas: schemas(21, 5),
                stores: stores.clone(),
                backup_id: backup.id.clone(),
                backup: backup.file.clone(),
                backup_sha256: sha.to_owned(),
                ..Default::default()
            }
            .save(&d)
            .unwrap();
        };
        // what the new version wrote: into the registry, and a users store
        // that was not there before (this broker had no gateway)
        std::fs::write(d.join("state/written-by-0.2.0"), b"x").unwrap();
        std::fs::create_dir_all(d.join("gateway/users")).unwrap();
        std::fs::write(d.join("gateway/users/wal.new"), b"x").unwrap();

        failed_trial(&job, &job.sha256);
        let r = release::guard(&l, &d, "0.1.0", None).unwrap();
        assert!(
            matches!(&r, release::Guarded::RolledBack { restored: true, .. }),
            "{r:?}"
        );
        assert_eq!(l.current_version().as_deref(), Some("0.1.0"));
        // the registry of before the update
        assert!(!d.join("state/written-by-0.2.0").exists());
        assert!(d.join("update.aside/state/written-by-0.2.0").is_file());
        assert!(std::fs::read_dir(d.join("state")).unwrap().count() > 0);
        // the store that was not there is not there again, and is kept aside
        assert!(!d.join("gateway/users").exists());
        assert!(d.join("update.aside/users/wal.new").is_file());
        let u = UpdateFile::load(&d).unwrap();
        assert_eq!((u.state.as_str(), u.restored), ("rolled_back", true));

        // a backup that is gone, one that was changed (with its hash in
        // update.json changed to match), one that is not sealed for this
        // broker: the old version starts on the state as it is
        let open = pre_update(SealWith::None);
        let changed = {
            let path = d.join("backups").join(&job.file);
            let mut bytes = std::fs::read(&path).unwrap();
            // through every file in it, the registry's among them
            let (from, to) = (bytes.len() / 10, bytes.len() * 9 / 10);
            for b in bytes[from..to].iter_mut().step_by(16) {
                *b ^= 0xff;
            }
            std::fs::write(&path, &bytes).unwrap();
            release::sha256_file(&path).unwrap().0
        };
        let gone = backups::Job {
            file: "no-such.wyrm-backup".into(),
            ..job.clone()
        };
        for (name, backup, sha) in [
            ("gone", &gone, job.sha256.as_str()),
            ("changed, hash not", &job, job.sha256.as_str()),
            ("changed, hash too", &job, changed.as_str()),
            ("not sealed", &open, open.sha256.as_str()),
        ] {
            std::fs::write(d.join("state/written-by-0.2.0"), b"x").unwrap();
            failed_trial(backup, sha);
            let r = release::guard(&l, &d, "0.1.0", None)
                .unwrap_or_else(|e| panic!("{name}: the guard must not fail: {e}"));
            assert!(
                matches!(&r, release::Guarded::Stuck(why) if why.contains("was not restored")),
                "{name}: {r:?}"
            );
            assert_eq!(l.current_version().as_deref(), Some("0.1.0"), "{name}");
            assert!(
                d.join("state/written-by-0.2.0").is_file(),
                "{name}: the state is left as it is"
            );
            let u = UpdateFile::load(&d).unwrap();
            assert_eq!(u.state, "failed", "{name}");
            assert!(
                u.reason.contains("link plc1 is not back"),
                "{name}: {}",
                u.reason
            );
            assert!(!u.restored && !u.audited, "{name}");
        }
        // the version that serves says it: sys shows `failed` with the reason
        ctl.update_started();
        let (_, _, state, last, _) = ctl.update_view();
        assert_eq!(state, "failed");
        assert!(
            matches!(last.get("reason"), Some(Value::Str(r)) if r.contains("was not restored"))
        );
        assert!(ctl
            .audit_tail(20)
            .iter()
            .any(|r| r.op == "update_rollback" && r.status == Status::InternalError.code()));
    }

    #[test]
    fn an_archive_is_fetched_from_its_url_or_beside_the_index() {
        let asset = |url: &str| Asset {
            file: "wyrmd-0.2.0-x86_64-linux.tar.gz".into(),
            sha256: "a".repeat(64),
            size: 1,
            url: url.into(),
            bin_sha256: "b".repeat(64),
        };
        assert_eq!(
            asset_url("https://dl.example/wyrmd/releases.json", &asset("")).unwrap(),
            "https://dl.example/wyrmd/wyrmd-0.2.0-x86_64-linux.tar.gz"
        );
        assert_eq!(
            asset_url("https://dl.example/releases.json?x=1", &asset("")).unwrap(),
            "https://dl.example/wyrmd-0.2.0-x86_64-linux.tar.gz"
        );
        assert_eq!(
            asset_url(
                "https://dl.example/releases.json",
                &asset("https://cdn.example/a.tar.gz")
            )
            .unwrap(),
            "https://cdn.example/a.tar.gz"
        );
        assert!(asset_url("https://dl.example", &asset("")).is_err());
    }

    #[test]
    fn a_state_copy_is_a_data_dir_of_wals_and_their_keys() {
        let d = std::env::temp_dir().join(format!("wyrm-update-copy-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        let (live, copy) = (d.join("data"), d.join("copy"));
        std::fs::create_dir_all(&live).unwrap();
        let key = secret::load_or_create_key(&live.join("state.key")).unwrap();
        {
            let mut s = wyrm_state::Store::<crate::audit::AuditLog>::open(live.join("audit"), &key)
                .unwrap();
            s.apply(crate::audit::AuditRecord {
                t: 1,
                sub: "a".into(),
                op: "b".into(),
                key: "c".into(),
                status: 0,
                detail: String::new(),
            })
            .unwrap();
        }
        state_copy(&live, &copy).unwrap();
        assert!(copy.join("state.key").is_file());
        // a store that does not exist is left out
        assert!(!copy.join("flows").exists());
        let copied = secret::load_or_create_key(&copy.join("state.key")).unwrap();
        assert_eq!(*copied, *key);
        let s =
            wyrm_state::Store::<crate::audit::AuditLog>::open(copy.join("audit"), &copied).unwrap();
        assert_eq!(s.lsn(), 1);
        drop(s);
        // the scratch goes with its guard
        drop(Scratch(copy.clone()));
        assert!(!copy.exists());
        let _ = std::fs::remove_dir_all(&d);
    }
}
