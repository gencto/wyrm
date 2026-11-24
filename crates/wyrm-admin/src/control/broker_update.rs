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

use super::backups::{BackupRequest, FileError, SealWith};
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

wyrm_core::name_enum! {
    /// `updates.mode` in `wyrmd.json5`; another name refuses the file.
    #[derive(Default)]
    pub enum UpdateMode as "updates.mode" {
        /// Nothing is fetched and nothing is updated.
        #[default]
        Off => "off",
        /// The broker says that a newer version exists; it is updated outside
        /// (a container image, a distribution package).
        External => "external",
        /// The broker replaces itself.
        SelfUpdate => "self",
    }
}

/// `updates` in `wyrmd.json5`, and what `wyrmd` knows that the admin does not.
#[derive(Debug, Clone)]
pub struct UpdateConfig {
    pub mode: UpdateMode,
    /// URL of the signed releases index (`https://`, or `http://` to
    /// loopback): the channel file, the index and its signature in one.
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

/// `sys ▸ update`.
#[derive(Args)]
pub(super) struct Update {
    #[param(
        display = "Version",
        desc = "Of the releases index; empty: the latest",
        trim,
        absent = String::new()
    )]
    pub version: String,
    #[param(display = "Site name", desc = "Type the name of this site to confirm")]
    pub confirm_site: String,
    #[param(
        display = "Upload",
        desc = "Without updates.channel: the id of the archive uploaded in parts \
                (sys/backups restore_begin, restore_part)",
        absent = String::new()
    )]
    pub upload: String,
    #[param(
        display = "Release",
        desc = "With upload: the release document of the archive (JSON)"
    )]
    pub release: Option<String>,
    #[param(
        display = "Signature",
        desc = "With upload: the Ed25519 signature of the release (hex)",
        absent = String::new()
    )]
    pub signature: String,
    /// Which broker of a pair to update (left out or empty: the active).
    #[param(
        choice,
        nonempty,
        display = "Target",
        desc = "A standby pair: the standby is updated first"
    )]
    pub target: Option<release::UpdateRole>,
    #[param(
        display = "Without the standby",
        desc = "A standby pair whose standby is down: update this broker alone",
        absent = false
    )]
    pub without_standby: bool,
}

impl Update {
    fn target(&self) -> release::UpdateRole {
        self.target.unwrap_or(release::UpdateRole::Active)
    }
}

/// `sys ▸ rollback_update`.
#[derive(Args)]
pub(super) struct RollbackUpdate {
    #[param(display = "Site name", desc = "Type the name of this site to confirm")]
    pub confirm_site: String,
}

/// The standby's word for "no update of its own" (`sys/replication/update/<v>/none/-`).
pub(crate) const NO_UPDATE: &str = "none";

/// What a standby's update state is called on the wire and in `sys`.
fn said_name(s: Option<release::UpdateState>) -> &'static str {
    s.map_or(NO_UPDATE, release::UpdateState::name)
}

/// What the standby said about itself with its last poll.
#[derive(Debug, Clone, Default, PartialEq)]
struct StandbySaid {
    version: String,
    /// The state of the standby's own update; `None`: it has none (`none` on the wire).
    state: Option<release::UpdateState>,
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

/// Remove the directory of a version that was not proven or not kept. One that
/// stays is never started (the guard starts only a binary a kept signed release
/// names) and the next update of that version replaces it; it is logged by name.
fn remove_version(dir: &Path) {
    if let Err(e) = std::fs::remove_dir_all(dir).or_else(wyrm_core::files::gone_ok) {
        tracing::error!("{} stays: {e}", dir.display());
    }
}

fn lock<T>(m: &Mutex<T>) -> std::sync::MutexGuard<'_, T> {
    m.lock().unwrap_or_else(|p| p.into_inner())
}

impl BrokerUpdate {
    pub(super) fn open(data_dir: &Path) -> Self {
        // what a broker that stopped left half done
        for scratch in ["update.fetch", "update.check"] {
            wyrm_core::files::discard_dir(&data_dir.join(scratch));
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

/// A file or a directory of an update that was not read, written, copied or
/// removed: `<path>: <cause>`.
fn at(path: &Path) -> impl FnOnce(std::io::Error) -> FileError + '_ {
    move |source| FileError::new(path, source)
}

/// `updates.channel` does not say where the archive of a release is
/// ([`asset_url`]).
#[derive(Debug, thiserror::Error)]
pub enum ChannelUrlError {
    #[error("updates.channel: the URL of a file ({0})")]
    Url(#[source] wyrm_core::weburl::UrlError),
    /// The URL has no path.
    #[error("updates.channel: the URL of a file")]
    NoFile,
}

/// Why there is no copy of the control plane ([`state_copy`]). No variant
/// holds a key: a key file is named by its path only.
#[derive(Debug, thiserror::Error)]
pub enum StateCopyError {
    /// A file or directory of the copy, or a key file, by its path.
    #[error(transparent)]
    File(#[from] FileError),
    /// A key file that is no hex text; holds its name in `data_dir`.
    #[error("{0}: not a key")]
    NotKey(&'static str),
    /// A store was not copied as of one sequence number.
    #[error("{dir}: {source}")]
    Store {
        dir: &'static str,
        #[source]
        source: wyrm_state::StateError,
    },
}

/// Why a version was not staged ([`stage`]): the archive, or what the binary
/// in it said of itself and of this broker's configuration and state.
#[derive(Debug, thiserror::Error)]
pub enum StageError {
    #[error("this broker was not started from a configuration file")]
    NoConfig,
    /// The release is the version that runs.
    #[error("wyrmd {0} is the version that runs")]
    Runs(String),
    /// The archive is not the one of the release, or does not unpack.
    #[error(transparent)]
    Archive(#[from] release::ArchiveError),
    /// The signed release was not kept beside the binary; the version
    /// directory was removed again.
    #[error(transparent)]
    Keep(release::LayoutError),
    #[error("{0}")]
    Join(#[source] tokio::task::JoinError),
    /// `release-info` of the new binary did not run.
    #[error(transparent)]
    Info(release::RunError),
    #[error("release-info of the new binary: {0}")]
    Identity(#[source] serde_json::Error),
    /// The binary is not what the signed release says.
    #[error(
        "the binary in the archive says it is wyrmd {} for {} (schemas {:?}, \
         replication {}); the signed release says {} (schemas {:?}, replication {})",
        .said.version, .said.target, .said.schemas, .said.replication,
        .signed.version, .signed.schemas, .signed.replication
    )]
    Mismatch {
        said: Box<Identity>,
        /// What the signed release says; its `target` is this host's.
        signed: Box<Identity>,
    },
    #[error(transparent)]
    StateCopy(#[from] StateCopyError),
    /// `check --state` of the new binary failed.
    #[error("the new version refuses this broker's configuration or state: {0}")]
    Refused(#[source] release::RunError),
}

/// Why the releases index was not read ([`Control::poll_index`]). The text
/// is `releases index: <this>` in `sys/update_hint` and in the answers of
/// `update` and `check_updates`.
#[derive(Debug, thiserror::Error)]
pub enum IndexError {
    #[error("no updates.channel")]
    NoChannel,
    /// The channel file was not fetched.
    #[error(transparent)]
    Fetch(#[from] crate::fetch::FetchError),
    /// The file is not a signed index, or an older one than was read before.
    #[error(transparent)]
    Release(#[from] release::ReleaseError),
}

/// Why the standby gets no part of the archive staged for it.
#[derive(Debug, thiserror::Error)]
pub enum OrderPartError {
    #[error("no update is staged for the standby")]
    NoOrder,
    #[error("offset: beyond the archive")]
    Offset,
    #[error(transparent)]
    File(#[from] FileError),
}

/// Why an update that was begun did not reach its restart ([`run`]). The
/// text is the `reason` of `sys/update_last` and the detail of the audit
/// record. Nothing was switched when one of these is returned.
#[derive(Debug, thiserror::Error)]
pub enum UpdateRunError {
    /// The archive was not fetched.
    #[error(transparent)]
    Fetch(#[from] crate::fetch::FetchError),
    #[error(transparent)]
    File(#[from] FileError),
    #[error("{0}")]
    Join(#[source] tokio::task::JoinError),
    #[error("the upload is gone")]
    UploadGone,
    /// The broker does not run from the install layout.
    #[error(transparent)]
    Layout(release::LayoutError),
    #[error(transparent)]
    Stage(#[from] StageError),
    /// The control plane was not backed up; the staged version was removed.
    #[error("pre-update backup: {0}")]
    Backup(#[source] super::backups::NowError),
    /// Another job began meanwhile; holds it in words.
    #[error("{0}")]
    OtherJob(String),
    /// The standby is not where it must be before the active updates.
    #[error("{}", .0.message)]
    Standby(LinkError),
    /// `update.json` was not written.
    #[error(transparent)]
    Save(release::LayoutError),
    /// `current` was not switched; `update.json` was removed again.
    #[error(transparent)]
    Switch(release::LayoutError),
    /// `current` was not switched and `update.json` stays.
    #[error("{switch}; {} stays: {source}", .state.display())]
    SwitchLeft {
        switch: release::LayoutError,
        state: PathBuf,
        #[source]
        source: std::io::Error,
    },
    /// The archive brought for the standby is not the one the release names.
    #[error("the archive is not the one of the release (size or SHA-256)")]
    NotTheArchive,
    #[error(transparent)]
    Sha(#[from] release::FileError),
    /// The order for the standby was not written as JSON.
    #[error("{0}")]
    Order(#[source] serde_json::Error),
}

/// What a new version in its trial lacks ([`healthy`]); the text is `failed`
/// of `update.json` and the reason the trial is given up with.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum Unhealthy {
    #[error("the admin does not answer on sys")]
    Admin,
    #[error("the gateway does not listen on {0}")]
    Gateway(SocketAddr),
    /// Links that ran before the update and are not back: how many, of how
    /// many, and the first ten.
    #[error("{missing} of {of} links are not back: {}", .shown.join(", "))]
    Links {
        missing: usize,
        of: usize,
        shown: Vec<String>,
    },
}

/// Why `update` cannot run now, from what does not depend on the release.
struct Gate<'a> {
    mode: UpdateMode,
    site: &'a str,
    confirm: &'a str,
    /// Another job (a backup, a restore, a package update, an update).
    other_job: Option<String>,
    /// The install layout of this broker, or what is missing.
    layout: Result<(), release::LayoutError>,
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
        return Err(LinkError::not_supported(e.to_string()));
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
fn asset_url(channel: &str, asset: &Asset) -> Result<String, ChannelUrlError> {
    if !asset.url.is_empty() {
        return Ok(asset.url.clone());
    }
    // the channel's directory: its scheme, authority and path up to the last `/`
    let u = wyrm_core::weburl::Url::parse(channel).map_err(ChannelUrlError::Url)?;
    let dir = u
        .path
        .rsplit_once('/')
        .map(|(d, _)| d)
        .ok_or(ChannelUrlError::NoFile)?;
    Ok(format!(
        "{}://{}{dir}/{}",
        u.scheme, u.authority, asset.file
    ))
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
pub fn state_copy(data_dir: &Path, dest: &Path) -> Result<(), StateCopyError> {
    if dest.symlink_metadata().is_ok() {
        std::fs::remove_dir_all(dest).map_err(at(dest))?;
    }
    super::backups::make_private_dir(dest)?;
    for (dir, key_file) in STATE_STORES {
        let src = data_dir.join(dir);
        if !src.is_dir() {
            continue;
        }
        let key_path = data_dir.join(key_file);
        let text = Zeroizing::new(std::fs::read(&key_path).map_err(at(&key_path))?);
        let key = Zeroizing::new(
            std::str::from_utf8(&text)
                .ok()
                .and_then(|t| hex::decode(t.trim()).ok())
                .ok_or(StateCopyError::NotKey(key_file))?,
        );
        wyrm_state::replicate::copy_to(&src, &key, &dest.join(dir))
            .map_err(|source| StateCopyError::Store { dir, source })?;
        let to = dest.join(key_file);
        if !to.exists() {
            secret::write_private(&to, &text).map_err(at(&to))?;
        }
    }
    Ok(())
}

/// Removes the directory when dropped (a state copy holds key files).
struct Scratch(PathBuf);

impl Drop for Scratch {
    fn drop(&mut self) {
        wyrm_core::files::discard_dir(&self.0);
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
    signed: &release::Signed,
    asset: &Asset,
) -> Result<PathBuf, StageError> {
    let (release, document, signature) = (&signed.release, &signed.document, &signed.signature);
    let config = config_file.ok_or(StageError::NoConfig)?.to_owned();
    let (versions, version) = (layout.versions(), release.version.clone());
    if layout.current_version().as_deref() == Some(version.as_str()) {
        return Err(StageError::Runs(version));
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
            // a version without its signed release: the guard never starts it
            remove_version(&vs2.join(&v2));
            return Err(StageError::Keep(e));
        }
        Ok::<_, StageError>(bin)
    })
    .await
    .map_err(StageError::Join)??;
    let proved = async {
        let said = release::run_binary(&bin, &["release-info".into()], BINARY_TIMEOUT)
            .await
            .map_err(StageError::Info)?;
        let id: Identity = serde_json::from_str(said.trim()).map_err(StageError::Identity)?;
        if id.version != release.version
            || id.schemas != release.schemas
            || id.replication != release.replication
            || id.target != release::identity().target
        {
            return Err(StageError::Mismatch {
                said: Box::new(id),
                signed: Box::new(Identity {
                    version: release.version.clone(),
                    target: release::identity().target.clone(),
                    schemas: release.schemas.clone(),
                    replication: release.replication,
                }),
            });
        }
        let copy = Scratch(data_dir.join("update.check"));
        let (d, c) = (data_dir.to_owned(), copy.0.clone());
        tokio::task::spawn_blocking(move || state_copy(&d, &c))
            .await
            .map_err(StageError::Join)??;
        let argv: Vec<std::ffi::OsString> = vec![
            "-c".into(),
            config.into_os_string(),
            "check".into(),
            "--state".into(),
            copy.0.clone().into_os_string(),
        ];
        release::run_binary(&bin, &argv, BINARY_TIMEOUT)
            .await
            .map_err(StageError::Refused)?;
        Ok::<_, StageError>(())
    }
    .await;
    if let Err(e) = proved {
        remove_version(&versions.join(&version));
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
        ("result".to_owned(), Value::from(u.state.name())),
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
    if let Some(role) = u.role {
        m.insert("role".to_owned(), Value::from(role.name()));
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

    fn layout(&self) -> Result<Layout, release::LayoutError> {
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
        if self
            .backups()
            .list()
            .iter()
            .any(|j| j.status == super::backups::JobStatus::Running)
        {
            return Some("a backup is being made".into());
        }
        if self
            .backups()
            .list()
            .iter()
            .any(|j| j.send_status == Some(super::backups::SendStatus::Sending))
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
                Some(u) => (u.state.name().to_owned(), upd_map(u)),
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
                    Err(e) => e.to_string(),
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
    async fn poll_index(&self) -> Result<(), IndexError> {
        let u = &self.cfg.updates;
        let Some(channel) = u.channel.as_deref().filter(|_| u.mode != UpdateMode::Off) else {
            return Err(IndexError::NoChannel);
        };
        // one file holds the index and its signature: a reader never has one
        // without the other
        let r = async {
            let bytes = crate::fetch::get(channel, release::MAX_CHANNEL, FETCH_TIMEOUT).await?;
            let index = release::read_channel(&bytes, &u.keys)?;
            // an older index than one read before was put back
            release::note_sequence(&self.cfg.data_dir, index.sequence)?;
            Ok::<_, IndexError>(index)
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
                *lock(&self.update.index_error) = e.to_string();
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
        if matches!(
            u.state,
            release::UpdateState::RolledBack | release::UpdateState::Failed
        ) && !u.audited
        {
            let status = if u.state == release::UpdateState::Failed {
                Status::InternalError
            } else {
                Status::Ok
            };
            self.record(
                "system",
                AuditOp::UpdateRollback,
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
        if u.state == release::UpdateState::RolledBack && !u.settled {
            return;
        }
        let now = now_s();
        // how long this process has seen the clock past `keep_until`
        let past_s = {
            let mut since = lock(&self.update.past_since);
            if u.state == release::UpdateState::Confirmed && now > u.keep_until {
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
        let state = match state {
            NO_UPDATE => Some(None),
            s => release::UpdateState::from_name(s).map(Some),
        };
        let ok = release::check_version(version).is_ok()
            && (to == "-" || release::check_version(to).is_ok());
        let (true, Some(state)) = (ok, state) else {
            return Value::Map(BTreeMap::from([(
                "error".to_owned(),
                Value::from("version, state, to"),
            )]));
        };
        let said = StandbySaid {
            version: version.to_owned(),
            state,
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
            use release::UpdateState as U;
            let done = version == o.version && matches!(state, Some(U::Confirmed) | None);
            let refused = to == o.version && matches!(state, Some(U::RolledBack | U::Failed));
            if done || refused {
                *lock(&self.update.order) = None;
                let order = self.cfg.data_dir.join(ORDER_DIR);
                if let Err(e) = std::fs::remove_dir_all(&order).or_else(wyrm_core::files::gone_ok) {
                    // the order is read again at the next start and ends there the same way
                    tracing::error!("{} stays: {e}", order.display());
                }
                let (op, status, text) = if done {
                    (AuditOp::UpdateConfirmed, Status::Ok, U::Confirmed.name())
                } else {
                    (
                        AuditOp::UpdateRollback,
                        Status::InternalError,
                        said_name(state),
                    )
                };
                *lock(&self.update.order_result) = format!("{} {text}", o.version);
                self.record(
                    &o.by,
                    op,
                    "standby",
                    status,
                    &format!("the standby runs {version}; wyrmd {}: {text}", o.version),
                );
            } else if version != o.version && state != Some(U::Trial) {
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
    pub(super) fn standby_update_part(
        &self,
        offset: u64,
        len: u64,
    ) -> Result<Vec<u8>, OrderPartError> {
        use std::io::{Read, Seek, SeekFrom};
        let order = lock(&self.update.order)
            .clone()
            .ok_or(OrderPartError::NoOrder)?;
        if offset > order.size {
            return Err(OrderPartError::Offset);
        }
        let path = self.cfg.data_dir.join(ORDER_DIR).join(ORDER_ARCHIVE);
        let mut f = std::fs::File::open(&path).map_err(at(&path))?;
        f.seek(SeekFrom::Start(offset)).map_err(at(&path))?;
        let want = len.clamp(1, ORDER_PART).min(order.size - offset) as usize;
        let mut buf = vec![0u8; want];
        f.read_exact(&mut buf).map_err(at(&path))?;
        Ok(buf)
    }

    /// `(version, what it does with an update)` of the standby, while it is
    /// connected.
    fn standby_said(&self) -> Option<(String, String)> {
        let s = lock(&self.update.standby).clone();
        s.at.filter(|t| t.elapsed() < STANDBY_SEEN)?;
        let about = if s.to == "-" {
            said_name(s.state).to_owned()
        } else {
            format!("{} {}", s.to, said_name(s.state))
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
        if said.version == r.version
            && matches!(said.state, None | Some(release::UpdateState::Confirmed))
        {
            return Ok(());
        }
        Err(LinkError::new(
            Status::Busy,
            format!(
                "the standby runs wyrmd {} ({}): update the standby first (update with \
                 target: \"standby\") and wait until it follows again on {}",
                said.version,
                said_name(said.state),
                r.version
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
    a: &Update,
    sub: &str,
    fresh: bool,
) -> Result<Plan, LinkError> {
    let u = &ctl.cfg.updates;
    let for_standby = a.target() == release::UpdateRole::Standby;
    if for_standby && !u.standby {
        return Err(LinkError::invalid_parameter(
            "target: this broker has no standby (no standby section in wyrmd.json5)",
        ));
    }
    let (version, upload) = (a.version.clone(), a.upload.clone());
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
        let url =
            asset_url(&channel, asset).map_err(|e| LinkError::invalid_parameter(e.to_string()))?;
        (
            signed.release,
            signed.document,
            signed.signature,
            Source::Url(url),
        )
    } else {
        let text = a
            .release
            .clone()
            .ok_or_else(|| {
                LinkError::invalid_parameter(
                    "release: the release document that came with the archive",
                )
            })?
            .into_bytes();
        let signature = a.signature.clone();
        let r = release::read_release(&text, &signature, &u.keys)
            .map_err(|e| LinkError::invalid_parameter(e.to_string()))?;
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
        .map_err(|e| LinkError::new(Status::InvalidParameter, e.to_string()))?
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
fn gate_now(ctl: &Control, confirm: &str) -> Result<(), LinkError> {
    gates(&Gate {
        mode: ctl.cfg.updates.mode,
        site: &ctl.cfg.site,
        confirm,
        other_job: ctl.other_job(),
        layout: ctl.layout().map(|_| ()),
        guard_ran: ctl.guard_ran(),
        trial: UpdateFile::load(&ctl.cfg.data_dir).is_some_and(|u| u.in_trial()),
    })
}

/// `sys/~act/update?check` (spec 05 0.2.33): everything `update` refuses
/// before it fetches the archive.
pub(super) async fn check(ctl: &Arc<Control>, a: &Update, sub: &str) -> Result<(), LinkError> {
    gate_now(ctl, &a.confirm_site)?;
    let plan = plan_of(ctl, a, sub, false).await?;
    if !plan.for_standby {
        ctl.standby_first(&plan.release, a.without_standby)?;
    }
    Ok(())
}

/// `sys/~act/update`: check, answer, and go on in the background.
pub(super) async fn update(
    ctl: &Arc<Control>,
    ctx: &LinkCtx,
    a: Update,
    sub: &str,
) -> wyrm_link_sdk::Result<Option<Value>> {
    gate_now(ctl, &a.confirm_site)?;
    let plan = plan_of(ctl, &a, sub, true).await?;
    let without = a.without_standby;
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
                return Err(e.into());
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
        wyrm_core::files::discard_dir(&ctl2.cfg.data_dir.join("update.fetch"));
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
                let e = e.to_string();
                ctl2.record(&by, AuditOp::UpdateStart, key, Status::InternalError, &e);
                *lock(&ctl2.update.failed) = Some(BTreeMap::from([
                    ("to".to_owned(), Value::from(to)),
                    (
                        "result".to_owned(),
                        Value::from(release::UpdateState::Failed.name()),
                    ),
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
) -> Result<(), UpdateRunError> {
    let d = ctl.cfg.data_dir.clone();
    let me = release::identity();
    // 1. the archive
    ctl.update.set_step("fetching");
    let archive = match (archive, &plan.source) {
        (Some(p), _) => p,
        (None, Source::Url(url)) => {
            let bytes = crate::fetch::get(url, plan.asset.size as usize, ARCHIVE_TIMEOUT).await?;
            let dir = d.join("update.fetch");
            // a fresh directory: nothing an earlier fetch left goes with this one
            std::fs::remove_dir_all(&dir)
                .or_else(wyrm_core::files::gone_ok)
                .map_err(at(&dir))?;
            super::backups::make_private_dir(&dir)?;
            let path = dir.join(ORDER_ARCHIVE);
            let p2 = path.clone();
            tokio::task::spawn_blocking(move || secret::write_private(&p2, &bytes))
                .await
                .map_err(UpdateRunError::Join)?
                .map_err(at(&path))?;
            path
        }
        (None, Source::Upload(_)) => return Err(UpdateRunError::UploadGone),
    };
    if plan.for_standby {
        return stage_for_standby(ctl, &plan, &archive).await;
    }
    // 2. unpack and prove the binary
    ctl.update.set_step("checking");
    let layout = ctl.layout().map_err(UpdateRunError::Layout)?;
    let bin = stage(
        &d,
        ctl.cfg.updates.config_file.as_deref(),
        &layout,
        &archive,
        &release::Signed {
            release: plan.release.clone(),
            document: plan.release_bytes.clone(),
            signature: plan.signature.clone(),
        },
        &plan.asset,
    )
    .await?;
    ctl.update.set_step("staged");
    let undo = |e: UpdateRunError| {
        remove_version(&layout.versions().join(&plan.release.version));
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
                label: super::backups::JobKind::PreUpdate,
                pinned: true,
                remote: false,
            },
            &by2,
        )
    })
    .await
    .map_err(UpdateRunError::Join)?
    .map_err(|e| undo(UpdateRunError::Backup(e)))?;
    // nothing else may have started meanwhile, and the standby is where it was
    if let Some(job) = other_job_but_update(ctl) {
        return Err(undo(UpdateRunError::OtherJob(job)));
    }
    ctl.standby_first(&plan.release, without_standby)
        .map_err(|e| undo(UpdateRunError::Standby(e)))?;
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
        state: release::UpdateState::Trial,
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
        role: Some(release::UpdateRole::Active),
        ..Default::default()
    };
    let exe = ctl.cfg.link_exe.clone();
    let (layout2, u2, d2) = (layout.clone(), u.clone(), d.clone());
    tokio::task::spawn_blocking(move || -> Result<(), UpdateRunError> {
        if !layout2.guard_is(&exe) {
            // a unit that keeps `bin/` from the broker's user refreshes the
            // guard itself (`guard-refresh`): it is then one start behind
            if let Err(e) = layout2.refresh_guard(&exe) {
                warn!("broker update: the guard is not replaced: {e}");
            }
        }
        u2.save(&d2).map_err(UpdateRunError::Save)?;
        if let Err(e) = layout2.switch(&u2.to) {
            // a state file that stayed would start a trial of a version not switched to
            let state = d2.join(release::STATE_FILE);
            if let Err(r) = std::fs::remove_file(&state).or_else(wyrm_core::files::gone_ok) {
                tracing::error!("{} stays: {r}", state.display());
                return Err(UpdateRunError::SwitchLeft {
                    switch: e,
                    state,
                    source: r,
                });
            }
            return Err(UpdateRunError::Switch(e));
        }
        // the version before the one that runs can no longer be gone back to
        layout2.prune(&[u2.from.as_str(), u2.to.as_str()]);
        Ok(())
    })
    .await
    .map_err(UpdateRunError::Join)?
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
    // `update.json` says trial from here on: the journal writes what the version
    // that may run next, whichever it is, can open
    ctl.audit_follows_update();
    debug!(bin = %bin.display(), "broker update: staged");
    ctl.record(
        &plan.by,
        AuditOp::UpdateStart,
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
async fn stage_for_standby(
    ctl: &Arc<Control>,
    plan: &Plan,
    archive: &Path,
) -> Result<(), UpdateRunError> {
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
    tokio::task::spawn_blocking(move || -> Result<(), UpdateRunError> {
        let (sha, size) = release::sha256_file(&archive)?;
        if size != asset.size || sha != asset.sha256 {
            return Err(UpdateRunError::NotTheArchive);
        }
        std::fs::remove_dir_all(&dir2)
            .or_else(wyrm_core::files::gone_ok)
            .map_err(at(&dir2))?;
        super::backups::make_private_dir(&dir2)?;
        let to = dir2.join(ORDER_ARCHIVE);
        std::fs::copy(&archive, &to).map_err(at(&to))?;
        // said with the directory, as before these errors had a type
        secret::write_private(&dir2.join(ORDER_RELEASE), &release_bytes).map_err(at(&dir2))?;
        let text = serde_json::to_vec_pretty(&order2).map_err(UpdateRunError::Order)?;
        secret::write_private(&dir2.join(ORDER_FILE), &text).map_err(at(&dir2))?;
        Ok(())
    })
    .await
    .map_err(UpdateRunError::Join)??;
    *lock(&ctl.update.order_result) = String::new();
    *lock(&ctl.update.order) = Some(order.clone());
    ctl.record(
        &plan.by,
        AuditOp::UpdateStart,
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

/// `rollback_update` is done on the broker's own gateway: a caller whose
/// authority comes from an upstream (`remote`) is refused, before its
/// arguments are read.
pub(super) fn rollback_is_local(remote: bool) -> Result<(), LinkError> {
    if remote {
        return Err(LinkError::new(
            Status::PermissionDenied,
            "rollback_update puts the control plane back as it was before the update: it is \
             done on the broker's own gateway, not through its upstream",
        ));
    }
    Ok(())
}

/// `sys/~act/rollback_update`: go back to the version before a confirmed
/// update, on purpose. The guard does it at the next start. The caller is
/// checked first ([`rollback_is_local`]).
pub(super) async fn rollback(
    ctl: &Arc<Control>,
    a: RollbackUpdate,
    sub: &str,
) -> wyrm_link_sdk::Result<Option<Value>> {
    let d = &ctl.cfg.data_dir;
    let me = &release::identity().version;
    let mut u = UpdateFile::load(d)
        .filter(|u| u.state == release::UpdateState::Confirmed && &u.to == me)
        .ok_or_else(|| LinkError::not_found("no confirmed update to roll back"))?;
    gates(&Gate {
        mode: ctl.cfg.updates.mode,
        site: &ctl.cfg.site,
        confirm: &a.confirm_site,
        other_job: ctl.other_job(),
        layout: ctl.layout().map(|_| ()),
        guard_ran: ctl.guard_ran(),
        trial: false,
    })?;
    // while the old version and the backup are kept: the clock alone does
    // not end it (see `UpdateFile::expire`)
    let layout = ctl
        .layout()
        .map_err(|e| LinkError::not_supported(e.to_string()))?;
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
    // Once `update.json` names who asked, the guard starts the previous version
    // next, however this process ends. So the journal switches first, and the
    // file is written only after its writer answered: a batch in flight is on
    // disk, the anchor is the plain head, every later record is written alone.
    // The other order left a window (file durable, a batch announced in the
    // anchor, a kill) after which the previous version refused the journal.
    let asked = ctl.audit_one_by_one().and_then(|()| {
        ctl.save_update(&u).inspect_err(|_| {
            // not asked after all: back to what the file on disk says
            ctl.audit_follows_update();
        })
    });
    if let Err(e) = asked {
        let _ = ctl.replacing(false);
        return Err(e);
    }
    ctl.record(
        sub,
        AuditOp::UpdateRollback,
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
        Update::action()
            .display("Update broker")
            .result(ActionResult::Type(TypeCode::Map))
            // the releases index is read before the answer
            .timeout_ms(150_000)
            .level(Perm::Config),
    )
    .await?;
    ctx.declare_action(
        "",
        "rollback_update",
        RollbackUpdate::action()
            .display("Roll back the broker update")
            .result(ActionResult::Type(TypeCode::Map))
            .level(Perm::Config),
    )
    .await?;
    ctx.declare_action(
        "",
        "check_updates",
        <()>::action()
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
async fn healthy(ctl: &Control, session: &Session, u: &UpdateFile) -> Result<(), Unhealthy> {
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
        return Err(Unhealthy::Admin);
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
            return Err(Unhealthy::Gateway(addr));
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
        return Err(Unhealthy::Links {
            missing: missing.len(),
            of: u.links.len(),
            shown: missing.iter().take(10).map(|s| (*s).clone()).collect(),
        });
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
    if let Some(mut u) = UpdateFile::load(d).filter(|u| {
        matches!(
            u.state,
            release::UpdateState::RolledBack | release::UpdateState::Failed
        ) && !u.settled
    }) {
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
            u.state = release::UpdateState::Confirmed;
            u.ended = now;
            u.keep_until = now + u64::from(ctl.cfg.updates.keep_days) * 86_400;
            u.audited = true;
            // confirmed: the guard no longer goes back by itself, so the journal
            // may write batches again
            if let Err(e) = ctl.save_update(&u) {
                warn!("update.json: {}", e.message);
                return;
            }
            ctl.record(
                &u.by,
                AuditOp::UpdateConfirmed,
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
            u.failed = why.to_string();
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

    /// `update.target` is a role of the pair: left out or empty is the active; another
    /// text is refused (review of #127: it was matched by literals).
    #[test]
    fn the_target_is_a_role() {
        use release::UpdateRole;
        let target = |t: Option<&str>| {
            let mut m = BTreeMap::from([("confirm_site".to_owned(), Value::from("plant"))]);
            if let Some(t) = t {
                m.insert("target".to_owned(), Value::from(t));
            }
            Update::decode(Value::Map(m)).map(|a| a.target())
        };
        assert_eq!(target(None), Ok(UpdateRole::Active));
        assert_eq!(target(Some("")), Ok(UpdateRole::Active));
        assert_eq!(target(Some("active")), Ok(UpdateRole::Active));
        assert_eq!(target(Some("standby")), Ok(UpdateRole::Standby));
        let e = target(Some("Standby")).unwrap_err();
        assert_eq!(e.field, "target");
        assert!(e.to_string().contains("active, standby"), "{e}");
        // `release` is declared as text; the reader took bytes too
        let e = Update::decode(Value::Map(BTreeMap::from([
            ("confirm_site".to_owned(), Value::from("plant")),
            ("release".to_owned(), Value::Bytes(vec![b'{'])),
        ])))
        .map(|_| ())
        .unwrap_err();
        assert_eq!(e.field, "release");
        // audit of #136: who may roll back is decided before the arguments are read
        assert!(rollback_is_local(false).is_ok());
        assert_eq!(
            rollback_is_local(true).unwrap_err().status,
            Status::PermissionDenied
        );
        // the confirmation is required
        let e = Update::decode(Value::Map(BTreeMap::new()))
            .map(|_| ())
            .unwrap_err();
        assert_eq!(e.field, "confirm_site");
    }

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
                layout: Err(release::LayoutError::NotInLayout {
                    exe: "/usr/local/bin/wyrmd".into(),
                    version: "0.1.0".into(),
                }),
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

    /// Audit of #152, round 2: `rollback_update` hands the files to the previous
    /// version (the guard goes back at the next start, however this process ends).
    /// Through the action itself: when it answers, `update.json` names who asked
    /// and the audit journal writes record by record, its own `update_rollback`
    /// record included.
    #[cfg(unix)]
    #[tokio::test]
    async fn a_rollback_asked_switches_the_journal_before_it_answers() {
        let me = release::identity().version.clone();
        let prefix =
            std::env::temp_dir().join(format!("wyrm-rollback-asked-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&prefix);
        std::fs::create_dir_all(&prefix).unwrap();
        let built = prefix.join("built");
        std::fs::write(&built, b"this version").unwrap();
        let l = Layout::install(&prefix.join("opt"), &built, &me).unwrap();
        std::fs::create_dir_all(l.versions().join("0.0.1")).unwrap();
        std::fs::write(l.bin_of("0.0.1"), b"the version before").unwrap();
        let exe = l.bin_of(&me);
        let exe2 = exe.clone();
        let ctl = super::super::tests::control_tweaked("rollback-asked", move |c| {
            c.updates.mode = UpdateMode::SelfUpdate;
            c.link_exe = exe2;
        });
        let d = ctl.cfg.data_dir.clone();
        release::stamp_guard(&d, &me);
        UpdateFile {
            from: "0.0.1".into(),
            to: me.clone(),
            state: release::UpdateState::Confirmed,
            ..Default::default()
        }
        .save(&d)
        .unwrap();
        ctl.audit_follows_update();
        assert!(!ctl.audit.is_one_by_one(), "confirmed: batches");
        // a wrong site name is refused and changes nothing
        let refused = rollback(
            &ctl,
            RollbackUpdate {
                confirm_site: "another".into(),
            },
            "user:root",
        )
        .await;
        assert!(refused.is_err());
        assert!(!ctl.audit.is_one_by_one());
        let site = ctl.cfg.site.clone();
        let answer = rollback(&ctl, RollbackUpdate { confirm_site: site }, "user:root")
            .await
            .unwrap();
        assert!(answer.is_some());
        // at the answer: the state file, the switch, and the record written under it
        assert_eq!(UpdateFile::load(&d).unwrap().rollback, "user:root");
        assert!(
            ctl.audit.is_one_by_one(),
            "the previous version starts next"
        );
        let last = ctl.audit_tail(1).pop().unwrap();
        assert_eq!(last.op, AuditOp::UpdateRollback.into());
        let _ = std::fs::remove_dir_all(&prefix);
    }

    /// Audit of #152, round 3: the order. At the moment `update.json` with
    /// `rollback` is on disk, the journal has already switched and its writer has
    /// answered: the batch that was in flight is written, the anchor is the plain
    /// head. With the file first, a kill between the two left an anchor that
    /// announces a batch, which the previous version refuses.
    #[cfg(unix)]
    #[tokio::test]
    async fn a_rollback_switches_the_journal_before_update_json_says_so() {
        use std::sync::Mutex;
        let me = release::identity().version.clone();
        let prefix =
            std::env::temp_dir().join(format!("wyrm-rollback-order-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&prefix);
        std::fs::create_dir_all(&prefix).unwrap();
        let built = prefix.join("built");
        std::fs::write(&built, b"this version").unwrap();
        let l = Layout::install(&prefix.join("opt"), &built, &me).unwrap();
        std::fs::create_dir_all(l.versions().join("0.0.1")).unwrap();
        std::fs::write(l.bin_of("0.0.1"), b"the version before").unwrap();
        let exe = l.bin_of(&me);
        let anchors = prefix.join("anchors");
        std::fs::create_dir_all(&anchors).unwrap();
        let anchors2 = anchors.clone();
        let ctl = super::super::tests::control_tweaked("rollback-order", move |c| {
            c.updates.mode = UpdateMode::SelfUpdate;
            c.link_exe = exe;
            c.anchor_dir = Some(anchors2);
            c.anchor_init = true;
        });
        let d = ctl.cfg.data_dir.clone();
        release::stamp_guard(&d, &me);
        UpdateFile {
            from: "0.0.1".into(),
            to: me.clone(),
            state: release::UpdateState::Confirmed,
            ..Default::default()
        }
        .save(&d)
        .unwrap();
        ctl.audit_follows_update();
        assert!(!ctl.audit.is_one_by_one(), "confirmed: batches");
        // a batch in flight: taken by the writer, not yet written
        let before = ctl.audit.lsn();
        ctl.audit.hold(true);
        for n in 0..3 {
            let rec = super::super::audit_record(
                "user:a",
                AuditOp::Event,
                "k",
                Status::Ok,
                &n.to_string(),
            );
            ctl.audit.push_record(rec).await.unwrap();
        }
        tokio::time::sleep(Duration::from_millis(50)).await;
        assert_eq!(ctl.audit.lsn(), before, "held");
        // what is true at the moment the file is on disk
        let seen = Arc::new(Mutex::new(Vec::new()));
        ctl.on_update_saved({
            let (seen, head) = (seen.clone(), anchors.join("audit.head"));
            move |ctl| {
                let asked = UpdateFile::load(&ctl.cfg.data_dir).is_some_and(|u| {
                    u.state == release::UpdateState::Confirmed && !u.rollback.is_empty()
                });
                seen.lock().unwrap().push((
                    asked,
                    ctl.audit.is_one_by_one(),
                    ctl.audit.lsn(),
                    std::fs::read_to_string(&head).unwrap(),
                ));
            }
        });
        let release_writer = std::thread::spawn({
            let ctl = ctl.clone();
            move || {
                std::thread::sleep(Duration::from_millis(200));
                ctl.audit.hold(false);
            }
        });
        let site = ctl.cfg.site.clone();
        let answer = rollback(&ctl, RollbackUpdate { confirm_site: site }, "user:root").await;
        release_writer.join().unwrap();
        assert!(answer.unwrap().is_some());
        let seen = seen.lock().unwrap();
        assert_eq!(seen.len(), 1, "update.json is written once");
        let (asked, one_by_one, lsn, head) = &seen[0];
        assert!(asked, "the file on disk says a rollback is asked");
        assert!(
            one_by_one,
            "update.json said rollback while the journal still wrote batches"
        );
        assert_eq!(
            *lsn,
            before + 3,
            "update.json said rollback before the batch in flight was on disk"
        );
        let head: Vec<&str> = head.split_whitespace().collect();
        assert_eq!(head.len(), 2, "the anchor announces a batch: {head:?}");
        assert_eq!(head[0], (before + 3).to_string(), "the plain head");
        // and the record of the rollback itself came after, alone
        assert!(ctl.audit.is_one_by_one());
        assert_eq!(ctl.audit.lsn(), before + 4);
        let _ = std::fs::remove_dir_all(&prefix);
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
                    label: super::backups::JobKind::PreUpdate,
                    pinned: true,
                    remote: false,
                },
                "user:ann",
            )
            .unwrap()
        };
        let job = pre_update(SealWith::Broker);
        assert_eq!(job.sealed, Some(crate::backup::How::Broker));
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
                state: release::UpdateState::Trial,
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
        assert_eq!(
            (u.state, u.restored),
            (release::UpdateState::RolledBack, true)
        );

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
            assert_eq!(u.state, release::UpdateState::Failed, "{name}");
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
            .any(|r| r.op.name() == "update_rollback" && r.status == Status::InternalError.code()));
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
        assert!(matches!(
            asset_url("https://dl.example", &asset("")),
            Err(ChannelUrlError::NoFile)
        ));
        assert!(matches!(
            asset_url("dl.example/releases.json", &asset("")),
            Err(ChannelUrlError::Url(_))
        ));
    }

    /// Every text of this file's errors, byte for byte as before they had a
    /// type: `sys/update_last.reason`, `sys/update_hint`, `update.json`
    /// `failed`, the audit detail and the answers of the actions.
    #[test]
    fn errors_read_as_before() {
        use std::error::Error as _;
        let io = || std::io::Error::other("no");
        let said = |e: &dyn std::error::Error, text: &str| assert_eq!(e.to_string(), text);
        let file = || at(Path::new("/d/x"))(io());
        said(&file(), "/d/x: no");
        assert!(file().source().is_some());

        let url = wyrm_core::weburl::UrlError::NoHost;
        said(
            &ChannelUrlError::Url(url),
            "updates.channel: the URL of a file (no host)",
        );
        said(
            &ChannelUrlError::NoFile,
            "updates.channel: the URL of a file",
        );

        said(&StateCopyError::File(file()), "/d/x: no");
        said(&StateCopyError::NotKey("state.key"), "state.key: not a key");
        said(
            &StateCopyError::Store {
                dir: "audit",
                source: wyrm_state::StateError::Rejected("r".into()),
            },
            "audit: operation rejected: r",
        );

        let run = || release::RunError::Timeout {
            bin: "/p/wyrmd".into(),
            secs: 120,
            source: tokio::runtime::Builder::new_current_thread()
                .enable_time()
                .build()
                .unwrap()
                .block_on(async {
                    tokio::time::timeout(Duration::ZERO, std::future::pending::<()>()).await
                })
                .unwrap_err(),
        };
        let json = || serde_json::from_str::<Identity>("x").unwrap_err();
        said(
            &StageError::NoConfig,
            "this broker was not started from a configuration file",
        );
        said(
            &StageError::Runs("0.2.0".into()),
            "wyrmd 0.2.0 is the version that runs",
        );
        said(
            &StageError::Archive(release::ArchiveError::HashMismatch),
            "the archive's SHA-256 is not the one of the release",
        );
        said(
            &StageError::Keep(release::LayoutError::Unsupported),
            "updates.mode \"self\" works on Linux and macOS only",
        );
        said(&StageError::Info(run()), "/p/wyrmd: no answer in 120 s");
        said(
            &StageError::Identity(json()),
            &format!("release-info of the new binary: {}", json()),
        );
        let id = |version: &str, replication| {
            Box::new(Identity {
                version: version.into(),
                target: "x86_64-linux".into(),
                schemas: BTreeMap::from([("registry".to_owned(), 20)]),
                replication,
            })
        };
        said(
            &StageError::Mismatch {
                said: id("0.3.0", 2),
                signed: id("0.2.0", 1),
            },
            "the binary in the archive says it is wyrmd 0.3.0 for x86_64-linux (schemas \
             {\"registry\": 20}, replication 2); the signed release says 0.2.0 (schemas \
             {\"registry\": 20}, replication 1)",
        );
        said(
            &StageError::StateCopy(StateCopyError::NotKey("flows.key")),
            "flows.key: not a key",
        );
        said(
            &StageError::Refused(run()),
            "the new version refuses this broker's configuration or state: /p/wyrmd: no \
             answer in 120 s",
        );
        assert!(StageError::Refused(run()).source().is_some());

        said(&IndexError::NoChannel, "no updates.channel");
        said(
            &IndexError::Fetch(crate::fetch::FetchError::Scheme),
            "url: https:// only",
        );
        said(
            &IndexError::Release(release::ReleaseError::NoPinnedKey),
            &release::ReleaseError::NoPinnedKey.to_string(),
        );

        said(
            &OrderPartError::NoOrder,
            "no update is staged for the standby",
        );
        said(&OrderPartError::Offset, "offset: beyond the archive");
        said(&OrderPartError::File(file()), "/d/x: no");

        use UpdateRunError as U;
        said(
            &U::Fetch(crate::fetch::FetchError::Credentials),
            "url: no credentials in the URL",
        );
        said(&U::File(file()), "/d/x: no");
        said(&U::UploadGone, "the upload is gone");
        said(
            &U::Layout(release::LayoutError::Unsupported),
            "updates.mode \"self\" works on Linux and macOS only",
        );
        said(
            &U::Stage(StageError::NoConfig),
            "this broker was not started from a configuration file",
        );
        said(
            &U::Backup(super::super::backups::NowError::Gone),
            "pre-update backup: the backup is gone",
        );
        said(
            &U::OtherJob("a backup is being made".into()),
            "a backup is being made",
        );
        said(
            &U::Standby(LinkError::new(Status::Busy, "the standby is away")),
            "the standby is away",
        );
        said(
            &U::Save(release::LayoutError::NoPrefix("/x".into())),
            "/x: no prefix",
        );
        said(
            &U::Switch(release::LayoutError::NoSuchVersion("/p/versions/9".into())),
            "/p/versions/9: no such version",
        );
        said(
            &U::SwitchLeft {
                switch: release::LayoutError::NoSuchVersion("/p/versions/9".into()),
                state: "/d/update.json".into(),
                source: io(),
            },
            "/p/versions/9: no such version; /d/update.json stays: no",
        );
        said(
            &U::NotTheArchive,
            "the archive is not the one of the release (size or SHA-256)",
        );
        said(&U::Order(json()), &json().to_string());

        said(&Unhealthy::Admin, "the admin does not answer on sys");
        said(
            &Unhealthy::Gateway(SocketAddr::from(([127, 0, 0, 1], 8443))),
            "the gateway does not listen on 127.0.0.1:8443",
        );
        said(
            &Unhealthy::Links {
                missing: 2,
                of: 5,
                shown: vec!["plc1".into(), "plc2".into()],
            },
            "2 of 5 links are not back: plc1, plc2",
        );
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
                op: crate::audit::AuditOp::Hello.into(),
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
