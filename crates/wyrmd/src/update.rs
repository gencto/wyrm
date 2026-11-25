//! `wyrmd`'s part of the broker's own update (ADR 0048 §2): what this
//! binary is, the check mode a newer binary is run in, the start of a
//! trial, and the standby's side of an update (ADR 0036). The format, the
//! layout and the guard are in [`wyrm_admin::release`], what a running
//! broker does in `wyrm_admin::control::broker_update`.

use crate::{Config, Error};
use serde::Deserialize;
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::time::Duration;
use wyrm_admin::control::broker_update::{guard_fresh, stage, ORDER_PART, STATE_STORES};
use wyrm_admin::release::{self, Identity, Layout, UpdateFile};
use wyrm_admin::{UpdateConfig, UpdateMode};
use wyrm_core::weburl::{HttpUrl, SchemeCase, UrlError};
use wyrm_core::Value;
use zenoh::Session;

/// `updates` in `wyrmd.json5`.
#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct UpdatesSection {
    /// `off` (default): the broker neither looks for releases nor updates.
    /// `external`: it says that a newer version exists and how to update
    /// outside it (containers, distribution packages). `self`: it replaces
    /// itself (`sys/~act/update`); needs the install layout and the guard
    /// (docs/operations.md §2).
    #[serde(default)]
    pub mode: UpdateMode,
    /// URL of the channel file (`releases.json`: the releases index and its
    /// signature in one file). `https://`, or `http://` to loopback (a
    /// mirror).
    #[serde(default)]
    pub channel: Option<String>,
    /// Ed25519 public keys (hex) trusted for releases besides the ones
    /// built into this binary: a company mirror, a test.
    #[serde(default)]
    pub keys: Vec<String>,
    /// Seconds a new version has to prove itself (10 to 3600).
    #[serde(default = "default_trial_s")]
    pub trial_s: u64,
    /// Days a confirmed update can be rolled back (1 to 90).
    #[serde(default = "default_keep_days")]
    pub keep_days: u32,
}

fn default_trial_s() -> u64 {
    180
}

fn default_keep_days() -> u32 {
    7
}

impl Default for UpdatesSection {
    fn default() -> Self {
        Self {
            mode: UpdateMode::Off,
            channel: None,
            keys: Vec::new(),
            trial_s: default_trial_s(),
            keep_days: default_keep_days(),
        }
    }
}

/// Why the `updates` section is refused when the configuration is read.
#[derive(thiserror::Error)]
pub enum UpdatesError {
    /// `updates.keys` holds something that is no release key.
    #[error(transparent)]
    Keys(#[from] release::ReleaseError),
    #[error("updates.trial_s {0}: 10 to 3600")]
    TrialS(u64),
    #[error("updates.keep_days {0}: 1 to 90")]
    KeepDays(u32),
    #[error(transparent)]
    Channel(#[from] ChannelError),
    #[error("updates.mode \"external\" needs updates.channel (where new versions are listed)")]
    NoChannel,
}

/// Why `updates.channel` is refused ([`check_channel`]). No text repeats
/// the URL.
#[derive(Clone, PartialEq, Eq, thiserror::Error)]
pub enum ChannelError {
    /// The text is no URL of the kind a channel is.
    #[error("{}", CHANNEL_HELP)]
    Url(#[source] UrlError),
    /// A URL, but too long, without a path, or plain http to another host.
    #[error("{}", CHANNEL_HELP)]
    Form,
    #[error(
        "updates.channel: no name or password before the host (the URL is shown in sys and in \
         backups); a channel is a public URL"
    )]
    Credentials,
    #[error(
        "updates.channel: no query string and no fragment (the URL is shown in sys and in \
         backups); a channel is a public URL"
    )]
    Query,
}

const CHANNEL_HELP: &str = "updates.channel: https://<host>/<path to releases.json> \
    (plain http only to a loopback address)";

crate::debug_as_text!(
    UpdatesError,
    ChannelError,
    StateCheckError,
    VerifySelfError,
    StandbyUpdateError,
);

impl UpdatesSection {
    pub fn validate(&self) -> Result<(), UpdatesError> {
        let mode = self.mode;
        release::pinned_keys(&self.keys)?;
        if !(10..=3600).contains(&self.trial_s) {
            return Err(UpdatesError::TrialS(self.trial_s));
        }
        if !(1..=90).contains(&self.keep_days) {
            return Err(UpdatesError::KeepDays(self.keep_days));
        }
        if let Some(c) = &self.channel {
            check_channel(c)?;
        }
        if mode == UpdateMode::External && self.channel.is_none() {
            return Err(UpdatesError::NoChannel);
        }
        Ok(())
    }
}

/// `updates.channel`: `https://<host>[:port]/<path>`, or `http://` to a
/// loopback address (a mirror on the broker host, tests). No user or
/// password before the host and no `?query` or `#fragment`: the URL is
/// shown in `sys` and in the config copy of a backup, so it holds no
/// credential. The message never repeats the URL.
pub fn check_channel(url: &str) -> Result<(), ChannelError> {
    if url.len() > 1024 {
        return Err(ChannelError::Form);
    }
    let u = HttpUrl::parse(url, SchemeCase::Lower).map_err(|e| match e {
        UrlError::Credentials => ChannelError::Credentials,
        e => ChannelError::Url(e),
    })?;
    if u.url.query.is_some() || u.url.fragment.is_some() {
        return Err(ChannelError::Query);
    }
    if u.url.path.is_empty() {
        return Err(ChannelError::Form);
    }
    if !u.tls && !matches!(u.host().text().as_str(), "127.0.0.1" | "localhost" | "::1") {
        return Err(ChannelError::Form);
    }
    Ok(())
}

/// What the admin needs of `cfg` for the broker's update.
pub fn update_config(cfg: &Config) -> Result<UpdateConfig, UpdatesError> {
    let u = &cfg.updates;
    Ok(UpdateConfig {
        mode: u.mode,
        channel: u.channel.clone(),
        keys: release::pinned_keys(&u.keys)?,
        trial_s: u.trial_s,
        keep_days: u.keep_days,
        // the new binary is run from another directory
        config_file: cfg
            .config_file
            .as_ref()
            .map(|p| std::path::absolute(p).unwrap_or_else(|_| p.clone())),
        gateway: cfg.gateway.as_ref().map(|g| g.listen),
        standby: cfg.standby.is_some(),
        process_start: match STARTED.load(Ordering::SeqCst) {
            0 => None,
            t => Some(t),
        },
    })
}

/// A build that says it is another version than the workspace's: for the
/// tests of the update alone (`src/bin/wyrmd_next.rs`). `wyrmd` itself
/// never makes one.
#[derive(Debug, Clone, Default, Deserialize)]
pub struct TestBuild {
    pub version: String,
    /// Added to the SCHEMA this build says it writes, by store.
    #[serde(default)]
    pub schema_bump: BTreeMap<String, u32>,
}

/// What this binary is: the version, the target, the SCHEMA of every
/// control-plane store it writes and its replication protocol.
pub fn identity(test: Option<&TestBuild>) -> Identity {
    let mut id = release::built();
    id.schemas.insert(
        "users".to_owned(),
        <wyrm_gateway::users::UserDb as wyrm_state::State>::SCHEMA,
    );
    id.schemas.insert(
        "flows".to_owned(),
        <wyrm_flow::store::FlowStore as wyrm_state::State>::SCHEMA,
    );
    if let Some(t) = test {
        id.version.clone_from(&t.version);
        for (store, n) in &t.schema_bump {
            if let Some(s) = id.schemas.get_mut(store) {
                *s += n;
            }
        }
    }
    id
}

/// `wyrmd check --state <dir>`: open every control-plane store of `dir` (a
/// copy laid out as a `data_dir`, made by the version that runs) with this
/// binary's own state types: every record is decoded and applied. The live
/// `data_dir` is not opened.
pub fn check_state(dir: &Path) -> Result<Vec<String>, StateCheckError> {
    use wyrm_state::Store;
    let mut done = Vec::new();
    for (store, key_file) in STATE_STORES {
        let at = dir.join(store);
        if !at.is_dir() {
            continue;
        }
        let key = crate::read_key(&dir.join(key_file))?;
        let lsn = match store {
            "state" => Store::<wyrm_admin::registry::Registry>::open(&at, &key).map(|s| s.lsn()),
            "audit" => Store::<wyrm_admin::audit::AuditLog>::open(&at, &key).map(|s| s.lsn()),
            "flows/state" => Store::<wyrm_flow::store::FlowStore>::open(&at, &key).map(|s| s.lsn()),
            _ => Store::<wyrm_gateway::users::UserDb>::open(&at, &key).map(|s| s.lsn()),
        }
        .map_err(|source| StateCheckError::Store { store, source })?;
        done.push(format!("{store}: {lsn} records"));
    }
    Ok(done)
}

/// Why a copy of the control plane is not read by this binary
/// ([`check_state`]).
#[derive(thiserror::Error)]
pub enum StateCheckError {
    /// The key file of a store.
    #[error(transparent)]
    Key(#[from] crate::KeyFileError),
    /// The store did not open with this binary's state type.
    #[error("{store}: {source}")]
    Store {
        store: &'static str,
        #[source]
        source: wyrm_state::StateError,
    },
}

/// Unix seconds this process started (set by [`trial_start`]).
static STARTED: AtomicU64 = AtomicU64::new(0);
/// The standby made one complete sync since it started.
static SYNCED: AtomicBool = AtomicBool::new(false);

/// First thing at a start of the broker: when this process started (the
/// guard ran right before it), and for a version in its trial (ADR 0048
/// §2.5) the time at which the trial ends if it keeps running. The trial
/// itself is counted in the time the version ran, and its starts by the
/// guard.
pub fn trial_start(data_dir: &Path, trial_s: u64) {
    STARTED.store(release::now_s(), Ordering::SeqCst);
    let me = &release::identity().version;
    if let Some(mut u) = UpdateFile::load(data_dir).filter(|u| u.in_trial() && &u.to == me) {
        let s = if u.trial_s == 0 { trial_s } else { u.trial_s };
        u.deadline = release::now_s() + s.saturating_sub(u.ran_s);
        if let Err(e) = u.save(data_dir) {
            tracing::warn!("update.json: {e}");
        }
        tracing::info!(
            attempt = u.attempts,
            ran_s = u.ran_s,
            from = %u.from,
            "broker update: wyrmd {me} starts in its trial"
        );
    }
}

/// At the start of a broker in `updates.mode: "self"` that sits in the
/// install layout: its own binary is the one a signed release names (or
/// one `wyrmd install-layout` put there). The guard checks the same before
/// it lets a version start; this is the second look, for a unit without
/// the guard. A binary outside the layout is not checked (it cannot update
/// itself either).
pub fn verify_self(cfg: &Config, exe: &Path) -> Result<(), VerifySelfError> {
    if cfg.updates.mode != UpdateMode::SelfUpdate {
        return Ok(());
    }
    let me = &release::identity().version;
    let Ok(layout) = Layout::of_broker(exe, me) else {
        return Ok(());
    };
    let keys = release::pinned_keys(&cfg.updates.keys)?;
    layout
        .verify(me, &keys)
        .map_err(VerifySelfError::NotVerified)
}

/// Why a broker in `updates.mode: "self"` does not start ([`verify_self`]).
#[derive(thiserror::Error)]
pub enum VerifySelfError {
    /// `updates.keys` holds something that is no release key.
    #[error(transparent)]
    Keys(#[from] release::ReleaseError),
    /// Its own binary is not one a signed release or the trust list names.
    #[error("{0}. This broker does not start: updates.mode \"self\" runs only a verified binary")]
    NotVerified(#[source] release::LayoutError),
}

/// The standby has everything the active has (a complete sync, files
/// included).
pub fn standby_synced() {
    SYNCED.store(true, Ordering::SeqCst);
}

/// For a broker that follows: resolves when its trial as a standby ended
/// badly (it never followed the active again); the process then ends with
/// [`release::TRIAL_EXIT`]. At the end of a good trial the update is
/// confirmed and this stays pending.
pub async fn standby_trial(data_dir: &Path, exe: &Path) {
    let me = &release::identity().version;
    let mine = |u: &UpdateFile| {
        u.in_trial() && &u.to == me && u.role == Some(release::UpdateRole::Standby)
    };
    let Some(mut u) = UpdateFile::load(data_dir).filter(mine) else {
        return std::future::pending().await;
    };
    // counted in the time this version ran, as the active's trial is
    let trial_s = u.trial_s.max(10);
    let mut part_ms = 0u128;
    while u.ran_s < trial_s {
        let step = Duration::from_secs((trial_s - u.ran_s).min(5));
        let t = tokio::time::Instant::now();
        tokio::time::sleep(step).await;
        part_ms += t.elapsed().as_millis();
        let Some(mut now) = UpdateFile::load(data_dir).filter(mine) else {
            return std::future::pending().await;
        };
        now.ran_s += (part_ms / 1000) as u64;
        part_ms %= 1000;
        now.deadline = release::now_s() + trial_s.saturating_sub(now.ran_s);
        if let Err(e) = now.save(data_dir) {
            tracing::warn!("update.json: {e}");
        }
        u = now;
    }
    // some more polls for a sync that is under way
    for _ in 0..10 {
        if SYNCED.load(Ordering::SeqCst) {
            break;
        }
        tokio::time::sleep(Duration::from_secs(1)).await;
    }
    let Some(mut u) = UpdateFile::load(data_dir).filter(mine) else {
        return std::future::pending().await;
    };
    if SYNCED.load(Ordering::SeqCst) {
        u.state = release::UpdateState::Confirmed;
        u.ended = release::now_s();
        u.audited = true;
        if let Err(e) = u.save(data_dir) {
            tracing::warn!("update.json: {e}");
        }
        tracing::info!("broker update: wyrmd {me} follows the active: confirmed");
        match Layout::of_broker(exe, me) {
            Ok(l) if !l.guard_is(exe) => {
                if let Err(e) = l.refresh_guard(exe) {
                    tracing::warn!("broker update: the guard is not replaced: {e}");
                }
            }
            Ok(_) => {}
            Err(e) => tracing::warn!("broker update: {e}"),
        }
        return std::future::pending().await;
    }
    u.failed = "the standby did not follow the active again in its trial".into();
    tracing::warn!("broker update: wyrmd {me} gives its trial up: {}", u.failed);
    if let Err(e) = u.save(data_dir) {
        tracing::warn!("update.json: {e}");
    }
}

fn map_get<'a>(v: &'a Value, k: &str) -> Option<&'a Value> {
    match v {
        Value::Map(m) => m.get(k),
        _ => None,
    }
}

/// One poll of a standby for its own update: it tells the active what it
/// runs and takes the release staged for it, if there is one. `Ok(true)`:
/// the new version is unpacked, proven and made current; the process must
/// stop so that its supervisor starts it.
pub async fn standby_poll(
    session: &Session,
    prefix: &str,
    cfg: &Config,
) -> Result<bool, StandbyUpdateError> {
    let me = release::identity();
    let file =
        UpdateFile::load(&cfg.data_dir).filter(|u| u.role == Some(release::UpdateRole::Standby));
    let (state, to) = match &file {
        Some(u) => (u.state.name().to_owned(), u.to.clone()),
        None => ("none".to_owned(), "-".to_owned()),
    };
    let key = format!("{prefix}/update/{}/{state}/{to}", me.version);
    let answer = crate::standby::ask(session, &key)
        .await
        .ok_or(StandbyUpdateError::NoAnswer)?;
    let Some(order) = map_get(&answer, "order") else {
        return Ok(false);
    };
    let Some(Value::Str(version)) = map_get(order, "version") else {
        return Err(StandbyUpdateError::NoVersion);
    };
    release::check_version(version)?;
    // an order this host refused or rolled back is not tried again
    if file.is_some_and(|u| &u.to == version && u.state != release::UpdateState::Confirmed) {
        return Ok(false);
    }
    match standby_apply(session, prefix, cfg, order, version).await {
        Ok(()) => Ok(true),
        Err(e) => {
            tracing::warn!(version = %version, "broker update: the standby refuses it: {e}");
            let u = UpdateFile {
                from: me.version.clone(),
                to: version.clone(),
                state: release::UpdateState::Failed,
                reason: e.to_string(),
                ended: release::now_s(),
                role: Some(release::UpdateRole::Standby),
                audited: true,
                ..Default::default()
            };
            u.save(&cfg.data_dir)?;
            wyrm_core::files::discard_dir(&cfg.data_dir.join("update.fetch"));
            Err(e)
        }
    }
}

async fn standby_apply(
    session: &Session,
    prefix: &str,
    cfg: &Config,
    order: &Value,
    version: &str,
) -> Result<(), StandbyUpdateError> {
    let me = release::identity();
    if cfg.updates.mode != UpdateMode::SelfUpdate {
        return Err(StandbyUpdateError::NotSelf);
    }
    let exe = std::env::current_exe().map_err(StandbyUpdateError::Exe)?;
    let layout = Layout::of_broker(&exe, &me.version)?;
    let started = STARTED.load(Ordering::SeqCst);
    if !guard_fresh(release::guard_stamp(&cfg.data_dir), started) {
        return Err(StandbyUpdateError::NoGuard);
    }
    let (Some(Value::Bytes(doc)), Some(Value::Str(signature))) =
        (map_get(order, "release"), map_get(order, "signature"))
    else {
        return Err(StandbyUpdateError::NoRelease);
    };
    // under this host's own pinned keys: the active is not trusted for it
    let keys = release::pinned_keys(&cfg.updates.keys)?;
    let rel = release::read_release(doc, signature, &keys)?;
    if rel.version != version {
        return Err(StandbyUpdateError::OtherRelease(rel.version));
    }
    let asset = rel.compatible(me)?.clone();
    if rel.replication != me.replication {
        return Err(StandbyUpdateError::Replication(rel.version));
    }
    // the archive, part by part, into a new private file
    let dir = cfg.data_dir.join("update.fetch");
    let at = |path: &Path| {
        let path = path.to_path_buf();
        move |source| StandbyUpdateError::Path { path, source }
    };
    std::fs::remove_dir_all(&dir)
        .or_else(wyrm_core::files::gone_ok)
        .map_err(at(&dir))?;
    let archive = dir.join("archive.tar.gz");
    {
        use std::io::Write;
        let mut b = std::fs::DirBuilder::new();
        #[cfg(unix)]
        std::os::unix::fs::DirBuilderExt::mode(&mut b, 0o700);
        b.create(&dir).map_err(at(&dir))?;
        let mut out = std::fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&archive)
            .map_err(at(&archive))?;
        let mut offset = 0u64;
        while offset < asset.size {
            let key = format!("{prefix}/update_part/{offset}/{ORDER_PART}");
            let part = crate::standby::ask(session, &key)
                .await
                .ok_or(StandbyUpdateError::NoAnswer)?;
            let Some(Value::Bytes(data)) = map_get(&part, "data") else {
                return Err(StandbyUpdateError::NoArchive);
            };
            if data.is_empty() || offset + data.len() as u64 > asset.size {
                return Err(StandbyUpdateError::OtherArchive);
            }
            out.write_all(data).map_err(StandbyUpdateError::Write)?;
            offset += data.len() as u64;
        }
        out.sync_all().map_err(StandbyUpdateError::Write)?;
    }
    let config = cfg
        .config_file
        .as_ref()
        .map(|p| std::path::absolute(p).unwrap_or_else(|_| p.clone()));
    stage(
        &cfg.data_dir,
        config.as_deref(),
        &layout,
        &archive,
        &release::Signed {
            release: rel.clone(),
            document: doc.clone(),
            signature: signature.clone(),
        },
        &asset,
    )
    .await?;
    wyrm_core::files::discard_dir(&dir);
    let now = release::now_s();
    let u = UpdateFile {
        from: me.version.clone(),
        to: rel.version.clone(),
        state: release::UpdateState::Trial,
        trial_s: cfg.updates.trial_s,
        from_schemas: me.schemas.clone(),
        to_schemas: rel.schemas.clone(),
        by: "the active broker".into(),
        started: now,
        role: Some(release::UpdateRole::Standby),
        ..Default::default()
    };
    if !layout.guard_is(&exe) {
        // kept by a root step where `bin/` is not the broker's to write
        if let Err(e) = layout.refresh_guard(&exe) {
            tracing::warn!("broker update: the guard is not replaced: {e}");
        }
    }
    u.save(&cfg.data_dir)?;
    if let Err(e) = layout.switch(&u.to) {
        // a state file that stayed would start a trial of a version not switched to
        let state = cfg.data_dir.join(release::STATE_FILE);
        if let Err(r) = std::fs::remove_file(&state).or_else(wyrm_core::files::gone_ok) {
            tracing::error!("{} stays: {r}", state.display());
            return Err(StandbyUpdateError::SwitchAndState {
                switch: e,
                state,
                source: r,
            });
        }
        return Err(e.into());
    }
    tracing::warn!(from = %u.from, to = %u.to, "broker update: the standby stops for wyrmd {}", u.to);
    Ok(())
}

/// Why a standby did not take the update the active ordered
/// ([`standby_poll`]). Its text is the `reason` of the standby's
/// `update.json` and of its log line.
#[derive(thiserror::Error)]
pub enum StandbyUpdateError {
    #[error("the active does not answer")]
    NoAnswer,
    #[error("order: no version")]
    NoVersion,
    #[error(transparent)]
    Version(#[from] release::BadVersion),
    #[error("updates.mode is not \"self\" on the standby")]
    NotSelf,
    /// The path of this process is not known.
    #[error(transparent)]
    Exe(std::io::Error),
    /// The install layout, the state file or the switch to the new version.
    #[error(transparent)]
    Layout(#[from] release::LayoutError),
    #[error("the guard did not run before the standby started")]
    NoGuard,
    #[error("order: no release or signature")]
    NoRelease,
    /// This host's pinned keys, or the release document under them.
    #[error(transparent)]
    Release(#[from] release::ReleaseError),
    /// The signed release is another version than the order names.
    #[error("order: the release is wyrmd {0}")]
    OtherRelease(String),
    #[error(transparent)]
    Incompatible(#[from] release::Incompatible),
    #[error("wyrmd {0} changes the replication protocol: a standby cannot go first")]
    Replication(String),
    /// The directory or the file the archive is fetched into.
    #[error("{}: {source}", .path.display())]
    Path {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("the active has no such archive any more")]
    NoArchive,
    #[error("the archive of the active is not the one of the release")]
    OtherArchive,
    /// A part of the archive was not written.
    #[error(transparent)]
    Write(std::io::Error),
    #[error(transparent)]
    Stage(#[from] wyrm_admin::control::broker_update::StageError),
    /// The switch failed and the state file written for it stays.
    #[error("{switch}; {} stays: {source}", .state.display())]
    SwitchAndState {
        switch: release::LayoutError,
        state: PathBuf,
        #[source]
        source: std::io::Error,
    },
}

/// `wyrmd update-guard`: see [`release::guard`]. With `updates.mode:
/// "self"` the version it lets start is verified. `Err` (exit code 1, the
/// broker is not started) only when no verified version can be started.
pub fn run_guard(cfg: &Config) -> Result<(), Error> {
    let me = &release::identity().version;
    let exe: PathBuf = std::env::current_exe()?;
    let layout = match Layout::of_guard(&exe) {
        Ok(l) => l,
        Err(e) => {
            // not the layout of a self-updating broker: nothing to guard,
            // and `update` is refused (no stamp is written)
            eprintln!("update-guard: {e}; nothing done");
            return Ok(());
        }
    };
    let keys = match cfg.updates.mode {
        UpdateMode::SelfUpdate => Some(release::pinned_keys(&cfg.updates.keys).map_err(said)?),
        _ => None,
    };
    match release::guard(&layout, &cfg.data_dir, me, keys.as_deref()).map_err(said)? {
        release::Guarded::Nothing => {}
        release::Guarded::RolledBack { from, to, restored } => eprintln!(
            "update-guard: wyrmd {to} is taken back; current is wyrmd {from} again \
             (control plane restored from the pre-update backup: {restored})"
        ),
        release::Guarded::Stuck(why) => eprintln!("update-guard: {why}"),
    }
    Ok(())
}

/// `wyrmd guard-refresh`: for a unit that keeps `<prefix>/bin` out of the
/// broker user's reach (`ExecStartPre=+…`, run as root after
/// `update-guard`). It makes the guard the binary of the version that is
/// current, when that version is verified and no trial runs (in a trial
/// the guard stays the previous version). It writes nothing but the guard.
pub fn run_guard_refresh(cfg: &Config) -> Result<(), Error> {
    let exe: PathBuf = std::env::current_exe()?;
    let layout = Layout::of_guard(&exe).map_err(said)?;
    if cfg.updates.mode != UpdateMode::SelfUpdate {
        return Ok(());
    }
    if UpdateFile::load(&cfg.data_dir).is_some_and(|u| u.in_trial()) {
        return Ok(());
    }
    let keys = release::pinned_keys(&cfg.updates.keys).map_err(said)?;
    if layout.refresh_guard_verified(&keys).map_err(said)? {
        eprintln!(
            "guard-refresh: the guard is wyrmd {}",
            layout.current_version().unwrap_or_default()
        );
    }
    Ok(())
}

/// `wyrmd release …`: what the release workflow runs (`packaging/wyrmd`),
/// and what makes a signed archive to bring to a broker by hand. None of
/// them reads `wyrmd.json5`.
#[derive(clap::Subcommand, Debug)]
pub enum ReleaseCmd {
    /// Print a new release key: the secret seed (for the signer alone) and
    /// the public key (for `updates.keys`, or to build into wyrmd).
    Keygen,
    /// Pack this binary as wyrmd-<version>-<target>.tar.gz in DIR, with
    /// what it is beside it (<archive>.json).
    Pack { dir: PathBuf },
    /// Write wyrmd-<version>.release.json in DIR from the archives packed
    /// there (one per target, all of one version).
    Doc {
        dir: PathBuf,
        /// YYYY-MM-DD.
        #[arg(long, default_value = "")]
        date: String,
        /// URL of the release notes (https).
        #[arg(long, default_value = "")]
        notes: String,
        /// The oldest version that may update to this one.
        #[arg(long, default_value = "")]
        min_from: String,
        /// Where the archives will be: <base-url>/<file> (https); without
        /// it a broker looks beside the index.
        #[arg(long, default_value = "")]
        base_url: String,
    },
    /// Write the index INDEX: the one of the published channel file
    /// (--from) with the release document RELEASE added (a release of the
    /// same version is replaced) and its sequence one higher. Nothing is
    /// taken on trust: RELEASE must verify against RELEASE.sig, the channel
    /// file against the signature in it, and every entry of it against its
    /// own signature, all with the keys built into this binary and the ones
    /// given. The channel's index must hold every version named with
    /// --have (the releases that exist): an old index put back is refused.
    /// INDEX is then signed (`release sign --index`) and made the channel
    /// file (`release bundle`). --new starts an index (sequence 1) without
    /// a channel file.
    Index {
        release: PathBuf,
        index: PathBuf,
        /// The channel file that is published now.
        #[arg(long, conflicts_with = "new")]
        from: Option<PathBuf>,
        #[arg(long)]
        key: Vec<String>,
        /// Start an empty index; refused when INDEX exists.
        #[arg(long)]
        new: bool,
        /// A version the channel's index must hold.
        #[arg(long)]
        have: Vec<String>,
        /// YYYY-MM-DD.
        #[arg(long, default_value = "")]
        created: String,
    },
    /// Write the channel file CHANNEL (what `updates.channel` serves): the
    /// index INDEX and its signature INDEX.sig in one file. Both are
    /// checked first.
    Bundle {
        index: PathBuf,
        channel: PathBuf,
        #[arg(long)]
        key: Vec<String>,
    },
    /// Sign FILE (a release document, or an index with --index) with the
    /// seed in WYRMD_RELEASE_KEY; writes FILE.sig.
    Sign {
        file: PathBuf,
        #[arg(long)]
        index: bool,
    },
    /// Check FILE against FILE.sig with the keys built into this binary and
    /// the ones given; with --channel, FILE is a channel file (it holds its
    /// signature).
    Verify {
        file: PathBuf,
        #[arg(long)]
        index: bool,
        #[arg(long)]
        channel: bool,
        #[arg(long)]
        key: Vec<String>,
    },
}

/// The environment variable `release sign` reads the seed from (hex).
pub const RELEASE_KEY_ENV: &str = "WYRMD_RELEASE_KEY";

#[derive(serde::Serialize, Deserialize)]
struct Packed {
    identity: Identity,
    asset: release::Asset,
}

fn sig_path(file: &Path) -> PathBuf {
    let mut s = file.as_os_str().to_owned();
    s.push(".sig");
    PathBuf::from(s)
}

#[allow(
    clippy::print_stdout,
    reason = "`wyrmd release`, a command line: what it prints is its result"
)]
pub fn release_cmd(cmd: ReleaseCmd) -> Result<(), Error> {
    use ed25519_dalek::SigningKey;
    match cmd {
        ReleaseCmd::Keygen => {
            let mut seed = zeroize::Zeroizing::new([0u8; 32]);
            wyrm_core::rand::fill(seed.as_mut()).map_err(|e| e.to_string())?;
            let key = SigningKey::from_bytes(&seed);
            println!(
                "secret seed ({RELEASE_KEY_ENV}): {}",
                hex::encode(seed.as_ref())
            );
            println!(
                "public key: {}",
                hex::encode(key.verifying_key().to_bytes())
            );
        }
        ReleaseCmd::Pack { dir } => {
            let out = pack_this(&dir)?;
            println!("{}", out.display());
        }
        ReleaseCmd::Doc {
            dir,
            date,
            notes,
            min_from,
            base_url,
        } => {
            let packed = packed_in(&dir)?;
            let first = packed.first().ok_or("no packed archive in the directory")?;
            let id = first.identity.clone();
            let targets = checked_targets(&dir, &packed, first, &base_url)?;
            let rel = release::Release {
                wyrmd_release: release::FORMAT,
                version: id.version.clone(),
                date,
                notes,
                min_from,
                schemas: id.schemas,
                replication: id.replication,
                targets,
            };
            rel.check().map_err(said)?;
            let out = dir.join(format!("wyrmd-{}.release.json", rel.version));
            std::fs::write(&out, pretty(&rel).map_err(said)?)?;
            println!("{}", out.display());
        }
        ReleaseCmd::Index {
            release: doc,
            index,
            from,
            key,
            new,
            have,
            created,
        } => {
            let keys = release::pinned_keys(&key).map_err(said)?;
            let text = |p: &Path| {
                String::from_utf8(read(p)?).map_err(|_| format!("{}: not text", p.display()))
            };
            let old = index_to_add_to(from.as_deref(), new, &index, &keys)?;
            // every release that exists is in it: an old index was not put back
            if let Some(missing) = have.iter().find(|v| old.get(v).is_none()) {
                return Err(format!(
                    "the published index (sequence {}) does not hold wyrmd {missing}, which \
                     was released: an older index was put back. Nothing is added to it",
                    old.sequence
                )
                .into());
            }
            let idx = old
                .with(&read(&doc)?, &text(&sig_path(&doc))?, &keys, &created)
                .map_err(said)?;
            // not signed yet: an old signature does not cover it
            std::fs::remove_file(sig_path(&index)).or_else(wyrm_core::files::gone_ok)?;
            std::fs::write(&index, pretty(&idx.to_file().map_err(said)?).map_err(said)?)?;
            println!(
                "{}: sequence {}, {} releases",
                index.display(),
                idx.sequence,
                idx.releases.len()
            );
        }
        ReleaseCmd::Bundle {
            index,
            channel,
            key,
        } => {
            let keys = release::pinned_keys(&key).map_err(said)?;
            let bytes = read(&index)?;
            let sig =
                String::from_utf8(read(&sig_path(&index))?).map_err(|_| "signature: not text")?;
            let checked = release::read_index(&bytes, &sig, &keys).map_err(said)?;
            std::fs::write(&channel, release::bundle(&bytes, &sig).map_err(said)?)?;
            println!(
                "{}: sequence {}, {} releases",
                channel.display(),
                checked.sequence,
                checked.releases.len()
            );
        }
        ReleaseCmd::Sign { file, index } => {
            let (out, public) = sign_file(&file, index)?;
            println!("{} (public key {public})", out.display());
        }
        ReleaseCmd::Verify {
            file,
            index,
            channel,
            key,
        } => println!("{}", verify_file(&file, index, channel, &key)?),
    }
    Ok(())
}

/// A file read, its error naming it.
fn read(p: &Path) -> Result<Vec<u8>, String> {
    std::fs::read(p).map_err(|e| format!("{}: {e}", p.display()))
}

/// `release pack`: this binary packed into `dir`, with the description of the archive
/// beside it. The archive's path.
fn pack_this(dir: &Path) -> Result<PathBuf, Error> {
    let me = release::identity().clone();
    std::fs::create_dir_all(dir)?;
    let out = dir.join(format!("wyrmd-{}-{}.tar.gz", me.version, me.target));
    let asset = release::pack(
        &std::env::current_exe()?,
        &[],
        &out,
        flate2::Compression::best(),
    )
    .map_err(said)?;
    let packed = Packed {
        identity: me,
        asset,
    };
    let mut side = out.clone().into_os_string();
    side.push(".json");
    std::fs::write(&side, pretty(&packed).map_err(said)?)?;
    Ok(out)
}

/// `release doc`: the descriptions of the packed archives in `dir`.
fn packed_in(dir: &Path) -> Result<Vec<Packed>, Error> {
    let mut packed: Vec<Packed> = Vec::new();
    for e in std::fs::read_dir(dir)? {
        let path = e?.path();
        if path.to_string_lossy().ends_with(".tar.gz.json") {
            packed.push(
                serde_json::from_slice(&read(&path)?)
                    .map_err(|e| format!("{}: {e}", path.display()))?,
            );
        }
    }
    Ok(packed)
}

/// `release doc`: each archive of `packed` checked (one version, schemas and replication as
/// `first`; it unpacks to the binary it describes), as the asset of its target.
fn checked_targets(
    dir: &Path,
    packed: &[Packed],
    first: &Packed,
    base_url: &str,
) -> Result<BTreeMap<String, release::Asset>, Error> {
    let id = &first.identity;
    let mut targets = BTreeMap::new();
    for p in packed {
        if p.identity.version != id.version
            || p.identity.schemas != id.schemas
            || p.identity.replication != id.replication
        {
            return Err(format!(
                "{}: not the same version, schemas and replication as {}",
                p.asset.file, first.asset.file
            )
            .into());
        }
        // the archive beside the description is the one it describes,
        // and the binary in it has the hash that will be signed
        let archive = dir.join(&p.asset.file);
        let scratch = dir.join(".doc-check");
        wyrm_core::files::discard_dir(&scratch);
        let checked = release::unpack(&archive, &p.asset, &scratch, &p.identity.version);
        wyrm_core::files::discard_dir(&scratch);
        checked.map_err(|e| format!("{}: {e}", archive.display()))?;
        let mut asset = p.asset.clone();
        if !base_url.is_empty() {
            asset.url = format!("{}/{}", base_url.trim_end_matches('/'), asset.file);
        }
        if targets.insert(p.identity.target.clone(), asset).is_some() {
            return Err(format!("target {} twice", p.identity.target).into());
        }
    }
    Ok(targets)
}

/// `release index`: the index a release is added to, the published one (`from`, checked) or,
/// with `new`, an empty one that replaces no `index`.
fn index_to_add_to(
    from: Option<&Path>,
    new: bool,
    index: &Path,
    keys: &[ed25519_dalek::VerifyingKey],
) -> Result<release::Index, Error> {
    Ok(match (from, new) {
        (None, false) => return Err("--from <channel file>, or --new to start an index".into()),
        (None, true) if index.exists() => {
            return Err(format!(
                "{} exists: --new starts an empty index and replaces none",
                index.display()
            )
            .into())
        }
        (None, true) => release::Index::default(),
        // the published index is checked before anything is added
        // to it: what is signed next is only what verified
        (Some(channel), _) => release::read_channel(&read(channel)?, keys)
            .map_err(|e| format!("{}: not added to: {e}", channel.display()))?,
    })
}

/// `release sign`: `file` signed with the seed in [`RELEASE_KEY_ENV`] into `file.sig`. The
/// signature's path and the public key, in hex.
fn sign_file(file: &Path, index: bool) -> Result<(PathBuf, String), Error> {
    use ed25519_dalek::SigningKey;
    let seed = zeroize::Zeroizing::new(
        std::env::var(RELEASE_KEY_ENV).map_err(|_| format!("{RELEASE_KEY_ENV} is not set"))?,
    );
    let raw: zeroize::Zeroizing<[u8; 32]> = zeroize::Zeroizing::new(
        hex::decode(seed.trim())
            .ok()
            .and_then(|b| b.try_into().ok())
            .ok_or_else(|| format!("{RELEASE_KEY_ENV}: 64 hex digits"))?,
    );
    let key = SigningKey::from_bytes(&raw);
    let bytes = read(file)?;
    let sig = if index {
        release::sign_index(&bytes, &key)
    } else {
        release::sign_release(&bytes, &key)
    };
    let out = sig_path(file);
    std::fs::write(&out, format!("{sig}\n"))?;
    let public = hex::encode(key.verifying_key().to_bytes());
    Ok((out, public))
}

/// `release verify`: what `file` (a release, an index or a channel file) holds, once it
/// verified.
fn verify_file(file: &Path, index: bool, channel: bool, key: &[String]) -> Result<String, Error> {
    let keys = release::pinned_keys(key).map_err(said)?;
    let bytes = read(file)?;
    if channel {
        let i = release::read_channel(&bytes, &keys).map_err(said)?;
        return Ok(format!(
            "ok: sequence {}, {} releases",
            i.sequence,
            i.releases.len()
        ));
    }
    let sig = String::from_utf8(read(&sig_path(file))?).map_err(|_| "signature: not text")?;
    Ok(if index {
        let i = release::read_index(&bytes, &sig, &keys).map_err(said)?;
        format!("ok: sequence {}, {} releases", i.sequence, i.releases.len())
    } else {
        let r = release::read_release(&bytes, &sig, &keys).map_err(said)?;
        format!("ok: wyrmd {}", r.version)
    })
}

/// The text of an error of [`release`], for a function whose error is text
/// and for the command line: `main` prints an [`Error`] with `Debug`, which
/// for a text is the text in quotes and for a typed error would be the name
/// of its variant.
fn said(e: impl std::fmt::Display) -> String {
    e.to_string()
}

fn pretty<T: serde::Serialize>(v: &T) -> Result<Vec<u8>, serde_json::Error> {
    serde_json::to_vec_pretty(v)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The check before review S4, kept to compare.
    fn old_check_channel(url: &str) -> Result<(), String> {
        const HELP: &str = "updates.channel: https://<host>/<path to releases.json> \
            (plain http only to a loopback address)";
        let (tls, rest) = if let Some(r) = url.strip_prefix("https://") {
            (true, r)
        } else if let Some(r) = url.strip_prefix("http://") {
            (false, r)
        } else {
            return Err(HELP.into());
        };
        if rest.contains(['?', '#']) {
            return Err(
                "updates.channel: no query string and no fragment (the URL is shown in sys and in \
                 backups); a channel is a public URL"
                    .into(),
            );
        }
        let authority = rest.split('/').next().unwrap_or_default();
        if authority.contains('@') {
            return Err(
                "updates.channel: no name or password before the host (the URL is shown in sys \
                 and in backups); a channel is a public URL"
                    .into(),
            );
        }
        if url.chars().any(|c| c.is_whitespace() || c.is_control()) || url.len() > 1024 {
            return Err(HELP.into());
        }
        let host = match authority.strip_prefix('[') {
            Some(v6) => v6.split(']').next().unwrap_or_default(),
            None => authority.rsplit_once(':').map_or(authority, |(h, _)| h),
        };
        if host.is_empty() || !rest.contains('/') {
            return Err(HELP.into());
        }
        if !tls && !matches!(host, "127.0.0.1" | "localhost" | "::1") {
            return Err(HELP.into());
        }
        Ok(())
    }

    /// The refusal as the text the old check gave.
    fn text(r: Result<(), ChannelError>) -> Result<(), String> {
        r.map_err(|e| e.to_string())
    }

    /// Review S4: every channel the old check took is taken, what it refused stays
    /// refused, with the same reason.
    #[test]
    fn channels_check_as_before() {
        for s in [
            "https://dl.example/wyrmd/releases.json",
            "https://dl.example:8443/r.json",
            "http://127.0.0.1:8000/releases.json",
            "http://[::1]:8000/releases.json",
            "http://localhost/r.json",
            "https://dl.example/",
        ] {
            assert_eq!(text(check_channel(s)), old_check_channel(s), "{s}");
            assert!(check_channel(s).is_ok(), "{s}");
        }
        for s in [
            "ftp://dl.example/r.json",
            "http://dl.example/r.json",
            "https://dl.example",
            "https://dl.example/r.json?token=x",
            "https://dl.example/r.json#f",
            "https://u:p@dl.example/r.json",
            "https://dl.example/a b",
            "HTTPS://dl.example/r.json",
        ] {
            assert_eq!(text(check_channel(s)), old_check_channel(s), "{s}");
        }
        // refused now, taken before: a bad port, a host that is no host
        for s in [
            "https://dl.example:99999/r.json",
            "https://[x/r.json",
            "https://h%2e/r",
        ] {
            assert!(old_check_channel(s).is_ok(), "{s}");
            assert!(check_channel(s).is_err(), "{s}");
        }
    }

    /// The text `main` prints for an error it returns (`Error: …`).
    fn printed(e: impl Into<Error>) -> String {
        format!("{:?}", e.into())
    }

    /// Every refusal reads as it did when these errors were strings, and
    /// `main` prints it as a text in quotes.
    #[test]
    fn errors_read_as_before() {
        let io = || std::io::Error::other("cause");
        let keys = || release::pinned_keys(&["abc".to_owned()]).unwrap_err();
        let layout = || release::LayoutError::Version(release::BadVersion("x y".into()));
        const HELP: &str = "updates.channel: https://<host>/<path to releases.json> \
            (plain http only to a loopback address)";
        const KEYS: &str = "updates.keys: an Ed25519 public key is 64 hex digits";
        const VERSION: &str = "version \"x y\": not a version name";
        for (e, want) in [
            (UpdatesError::Keys(keys()).to_string(), KEYS),
            (
                UpdatesError::TrialS(5).to_string(),
                "updates.trial_s 5: 10 to 3600",
            ),
            (
                UpdatesError::KeepDays(91).to_string(),
                "updates.keep_days 91: 1 to 90",
            ),
            (UpdatesError::Channel(ChannelError::Form).to_string(), HELP),
            (
                UpdatesError::NoChannel.to_string(),
                "updates.mode \"external\" needs updates.channel (where new versions are listed)",
            ),
            (ChannelError::Url(UrlError::NoScheme).to_string(), HELP),
            (ChannelError::Form.to_string(), HELP),
            (
                ChannelError::Credentials.to_string(),
                "updates.channel: no name or password before the host (the URL is shown in sys \
                 and in backups); a channel is a public URL",
            ),
            (
                ChannelError::Query.to_string(),
                "updates.channel: no query string and no fragment (the URL is shown in sys and in \
                 backups); a channel is a public URL",
            ),
            (
                StateCheckError::Key(crate::KeyFileError::Length("/d/state.key".into()))
                    .to_string(),
                "/d/state.key: expected 32 bytes",
            ),
            (
                StateCheckError::Store {
                    store: "flows/state",
                    source: wyrm_state::StateError::InUse("/d/flows/state".into()),
                }
                .to_string(),
                "flows/state: /d/flows/state is in use by another process",
            ),
            (VerifySelfError::Keys(keys()).to_string(), KEYS),
            (
                VerifySelfError::NotVerified(layout()).to_string(),
                "version \"x y\": not a version name. This broker does not start: updates.mode \
                 \"self\" runs only a verified binary",
            ),
            (
                StandbyUpdateError::NoAnswer.to_string(),
                "the active does not answer",
            ),
            (
                StandbyUpdateError::NoVersion.to_string(),
                "order: no version",
            ),
            (
                StandbyUpdateError::Version(release::BadVersion("x y".into())).to_string(),
                VERSION,
            ),
            (
                StandbyUpdateError::NotSelf.to_string(),
                "updates.mode is not \"self\" on the standby",
            ),
            (StandbyUpdateError::Exe(io()).to_string(), "cause"),
            (StandbyUpdateError::Layout(layout()).to_string(), VERSION),
            (
                StandbyUpdateError::NoGuard.to_string(),
                "the guard did not run before the standby started",
            ),
            (
                StandbyUpdateError::NoRelease.to_string(),
                "order: no release or signature",
            ),
            (StandbyUpdateError::Release(keys()).to_string(), KEYS),
            (
                StandbyUpdateError::OtherRelease("0.3.0".into()).to_string(),
                "order: the release is wyrmd 0.3.0",
            ),
            (
                StandbyUpdateError::Incompatible(release::Incompatible::NoBuild {
                    version: "0.3.0".into(),
                    target: "riscv".into(),
                    has: "x86".into(),
                })
                .to_string(),
                "wyrmd 0.3.0 has no build for riscv (it has x86)",
            ),
            (
                StandbyUpdateError::Replication("0.3.0".into()).to_string(),
                "wyrmd 0.3.0 changes the replication protocol: a standby cannot go first",
            ),
            (
                StandbyUpdateError::Path {
                    path: "/d/update.fetch".into(),
                    source: io(),
                }
                .to_string(),
                "/d/update.fetch: cause",
            ),
            (
                StandbyUpdateError::NoArchive.to_string(),
                "the active has no such archive any more",
            ),
            (
                StandbyUpdateError::OtherArchive.to_string(),
                "the archive of the active is not the one of the release",
            ),
            (StandbyUpdateError::Write(io()).to_string(), "cause"),
            (
                StandbyUpdateError::Stage(wyrm_admin::control::broker_update::StageError::NoConfig)
                    .to_string(),
                "this broker was not started from a configuration file",
            ),
            (
                StandbyUpdateError::SwitchAndState {
                    switch: layout(),
                    state: "/d/update.json".into(),
                    source: io(),
                }
                .to_string(),
                "version \"x y\": not a version name; /d/update.json stays: cause",
            ),
        ] {
            assert_eq!(e, want);
        }
        // what `wyrmd` prints when `main` returns one of them
        assert_eq!(
            printed(UpdatesError::TrialS(5)),
            "\"updates.trial_s 5: 10 to 3600\""
        );
        assert_eq!(
            printed(UpdatesError::NoChannel),
            "\"updates.mode \\\"external\\\" needs updates.channel (where new versions are \
             listed)\""
        );
        assert_eq!(printed(ChannelError::Form), format!("{HELP:?}"));
        assert_eq!(printed(UpdatesError::Keys(keys())), format!("{KEYS:?}"));
        assert_eq!(
            printed(StateCheckError::Key(crate::KeyFileError::Length(
                "/d/state.key".into()
            ))),
            "\"/d/state.key: expected 32 bytes\""
        );
        assert_eq!(
            printed(VerifySelfError::NotVerified(layout())),
            "\"version \\\"x y\\\": not a version name. This broker does not start: \
             updates.mode \\\"self\\\" runs only a verified binary\""
        );
        assert_eq!(
            printed(StandbyUpdateError::NotSelf),
            "\"updates.mode is not \\\"self\\\" on the standby\""
        );
    }

    /// The section and the channel are refused by variant.
    #[test]
    fn the_updates_section_is_refused_by_variant() {
        let section = |trial_s, keep_days| UpdatesSection {
            trial_s,
            keep_days,
            ..Default::default()
        };
        assert!(section(180, 7).validate().is_ok());
        assert!(matches!(
            section(9, 0).validate(),
            Err(UpdatesError::TrialS(9))
        ));
        assert!(matches!(
            section(10, 0).validate(),
            Err(UpdatesError::KeepDays(0))
        ));
        let mut s = section(180, 7);
        s.mode = UpdateMode::External;
        assert!(matches!(s.validate(), Err(UpdatesError::NoChannel)));
        s.channel = Some("https://u:p@dl.example/r.json".into());
        assert!(matches!(
            s.validate(),
            Err(UpdatesError::Channel(ChannelError::Credentials))
        ));
        s.keys = vec!["abc".into()];
        assert!(matches!(s.validate(), Err(UpdatesError::Keys(_))));
        assert_eq!(
            check_channel("ftp://dl.example/r.json"),
            Err(ChannelError::Url(UrlError::Scheme))
        );
        assert_eq!(check_channel("https://dl.example"), Err(ChannelError::Form));
        assert_eq!(
            check_channel("http://dl.example/r.json"),
            Err(ChannelError::Form)
        );
        assert_eq!(
            check_channel("https://dl.example/r.json#f"),
            Err(ChannelError::Query)
        );
    }
}
