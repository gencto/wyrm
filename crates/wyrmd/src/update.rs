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
use wyrm_admin::control::broker_update::{stage, ORDER_PART, STATE_STORES};
use wyrm_admin::release::{self, Identity, Layout, UpdateFile};
use wyrm_admin::{UpdateConfig, UpdateMode};
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
    #[serde(default = "default_mode")]
    pub mode: String,
    /// URL of the signed releases index (`releases.json`; its signature is
    /// at `<url>.sig`). `https://`, or `http://` to loopback (a mirror).
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

fn default_mode() -> String {
    "off".to_owned()
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
            mode: default_mode(),
            channel: None,
            keys: Vec::new(),
            trial_s: default_trial_s(),
            keep_days: default_keep_days(),
        }
    }
}

impl UpdatesSection {
    pub fn mode(&self) -> Result<UpdateMode, String> {
        match self.mode.as_str() {
            "off" => Ok(UpdateMode::Off),
            "external" => Ok(UpdateMode::External),
            "self" => Ok(UpdateMode::SelfUpdate),
            m => Err(format!("updates.mode {m:?}: off, external or self")),
        }
    }

    pub fn validate(&self) -> Result<(), String> {
        let mode = self.mode()?;
        release::pinned_keys(&self.keys)?;
        if !(10..=3600).contains(&self.trial_s) {
            return Err(format!("updates.trial_s {}: 10 to 3600", self.trial_s));
        }
        if !(1..=90).contains(&self.keep_days) {
            return Err(format!("updates.keep_days {}: 1 to 90", self.keep_days));
        }
        if let Some(c) = &self.channel {
            let loopback = ["http://127.0.0.1", "http://localhost", "http://[::1]"]
                .iter()
                .any(|p| {
                    c.strip_prefix(p)
                        .is_some_and(|r| r.starts_with(':') || r.starts_with('/'))
                });
            if !c.starts_with("https://") && !loopback {
                return Err("updates.channel: an https:// URL (plain http only to loopback)".into());
            }
        }
        if mode == UpdateMode::External && self.channel.is_none() {
            return Err(
                "updates.mode \"external\" needs updates.channel (where new versions are listed)"
                    .into(),
            );
        }
        Ok(())
    }
}

/// What the admin needs of `cfg` for the broker's update.
pub fn update_config(cfg: &Config) -> Result<UpdateConfig, String> {
    let u = &cfg.updates;
    Ok(UpdateConfig {
        mode: u.mode()?,
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
    })
}

/// A build that says it is another version than the workspace's: for the
/// tests of the update alone (`examples/wyrmd_next.rs`). `wyrmd` itself
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
pub fn check_state(dir: &Path) -> Result<Vec<String>, String> {
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
        .map_err(|e| format!("{store}: {e}"))?;
        done.push(format!("{store}: {lsn} records"));
    }
    Ok(done)
}

/// Unix seconds this process started (set by [`trial_start`]).
static STARTED: AtomicU64 = AtomicU64::new(0);
/// The standby made one complete sync since it started.
static SYNCED: AtomicBool = AtomicBool::new(false);

/// First thing at a start of the broker: the trial of a new version
/// begins with its first start (ADR 0048 §2.5). The starts are counted by
/// the guard.
pub fn trial_start(data_dir: &Path, trial_s: u64) {
    STARTED.store(release::now_s(), Ordering::SeqCst);
    let me = &release::identity().version;
    if let Some(mut u) = UpdateFile::load(data_dir).filter(|u| u.in_trial() && &u.to == me) {
        if u.deadline == 0 {
            let s = if u.trial_s == 0 { trial_s } else { u.trial_s };
            u.deadline = release::now_s() + s;
            if let Err(e) = u.save(data_dir) {
                tracing::warn!("update.json: {e}");
            }
        }
        tracing::info!(
            attempt = u.attempts,
            from = %u.from,
            "broker update: wyrmd {me} starts in its trial"
        );
    }
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
    let mine = |u: &UpdateFile| u.in_trial() && &u.to == me && u.role == "standby";
    let Some(u) = UpdateFile::load(data_dir).filter(mine) else {
        return std::future::pending().await;
    };
    let left = u.deadline.saturating_sub(release::now_s());
    tokio::time::sleep(Duration::from_secs(left)).await;
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
        u.state = "confirmed".into();
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
pub async fn standby_poll(session: &Session, prefix: &str, cfg: &Config) -> Result<bool, String> {
    let me = release::identity();
    let file = UpdateFile::load(&cfg.data_dir).filter(|u| u.role == "standby");
    let (state, to) = match &file {
        Some(u) => (u.state.clone(), u.to.clone()),
        None => ("none".to_owned(), "-".to_owned()),
    };
    let key = format!("{prefix}/update/{}/{state}/{to}", me.version);
    let answer = crate::standby::ask(session, &key)
        .await
        .ok_or("the active does not answer")?;
    let Some(order) = map_get(&answer, "order") else {
        return Ok(false);
    };
    let Some(Value::Str(version)) = map_get(order, "version") else {
        return Err("order: no version".into());
    };
    release::check_version(version)?;
    // an order this host refused or rolled back is not tried again
    if file.is_some_and(|u| &u.to == version && u.state != "confirmed") {
        return Ok(false);
    }
    match standby_apply(session, prefix, cfg, order, version).await {
        Ok(()) => Ok(true),
        Err(e) => {
            tracing::warn!(version = %version, "broker update: the standby refuses it: {e}");
            let u = UpdateFile {
                from: me.version.clone(),
                to: version.clone(),
                state: "failed".into(),
                reason: e.clone(),
                ended: release::now_s(),
                role: "standby".into(),
                audited: true,
                ..Default::default()
            };
            u.save(&cfg.data_dir)?;
            let _ = std::fs::remove_dir_all(cfg.data_dir.join("update.fetch"));
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
) -> Result<(), String> {
    let me = release::identity();
    if cfg.updates.mode()? != UpdateMode::SelfUpdate {
        return Err("updates.mode is not \"self\" on the standby".into());
    }
    let exe = std::env::current_exe().map_err(|e| e.to_string())?;
    let layout = Layout::of_broker(&exe, &me.version)?;
    let started = STARTED.load(Ordering::SeqCst);
    let guard_ran = release::guard_stamp(&cfg.data_dir)
        .is_some_and(|at| at <= started + 2 && at + 300 >= started);
    if !guard_ran {
        return Err("the guard did not run before the standby started".into());
    }
    let (Some(Value::Bytes(doc)), Some(Value::Str(signature))) =
        (map_get(order, "release"), map_get(order, "signature"))
    else {
        return Err("order: no release or signature".into());
    };
    // under this host's own pinned keys: the active is not trusted for it
    let keys = release::pinned_keys(&cfg.updates.keys)?;
    let rel = release::read_release(doc, signature, &keys)?;
    if rel.version != version {
        return Err(format!("order: the release is wyrmd {}", rel.version));
    }
    let asset = rel.compatible(me)?.clone();
    if rel.replication != me.replication {
        return Err(format!(
            "wyrmd {} changes the replication protocol: a standby cannot go first",
            rel.version
        ));
    }
    // the archive, part by part, into a new private file
    let dir = cfg.data_dir.join("update.fetch");
    let _ = std::fs::remove_dir_all(&dir);
    let archive = dir.join("archive.tar.gz");
    {
        use std::io::Write;
        let mut b = std::fs::DirBuilder::new();
        #[cfg(unix)]
        std::os::unix::fs::DirBuilderExt::mode(&mut b, 0o700);
        b.create(&dir)
            .map_err(|e| format!("{}: {e}", dir.display()))?;
        let mut out = std::fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&archive)
            .map_err(|e| format!("{}: {e}", archive.display()))?;
        let mut offset = 0u64;
        while offset < asset.size {
            let key = format!("{prefix}/update_part/{offset}/{ORDER_PART}");
            let part = crate::standby::ask(session, &key)
                .await
                .ok_or("the active does not answer")?;
            let Some(Value::Bytes(data)) = map_get(&part, "data") else {
                return Err("the active has no such archive any more".into());
            };
            if data.is_empty() || offset + data.len() as u64 > asset.size {
                return Err("the archive of the active is not the one of the release".into());
            }
            out.write_all(data).map_err(|e| e.to_string())?;
            offset += data.len() as u64;
        }
        out.sync_all().map_err(|e| e.to_string())?;
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
        &rel,
        &asset,
    )
    .await?;
    let _ = std::fs::remove_dir_all(&dir);
    let now = release::now_s();
    let u = UpdateFile {
        from: me.version.clone(),
        to: rel.version.clone(),
        state: "trial".into(),
        trial_s: cfg.updates.trial_s,
        from_schemas: me.schemas.clone(),
        to_schemas: rel.schemas.clone(),
        by: "the active broker".into(),
        started: now,
        role: "standby".into(),
        ..Default::default()
    };
    if !layout.guard_is(&exe) {
        layout.refresh_guard(&exe)?;
    }
    u.save(&cfg.data_dir)?;
    if let Err(e) = layout.switch(&u.to) {
        let _ = std::fs::remove_file(cfg.data_dir.join(release::STATE_FILE));
        return Err(e);
    }
    tracing::warn!(from = %u.from, to = %u.to, "broker update: the standby stops for wyrmd {}", u.to);
    Ok(())
}

/// `wyrmd update-guard`: see [`release::guard`]. An error ends the process
/// with code 1: the supervisor does not start the broker and tries again.
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
    match release::guard(&layout, &cfg.data_dir, me)? {
        release::Guarded::Nothing => {}
        release::Guarded::RolledBack { from, to, restored } => eprintln!(
            "update-guard: wyrmd {to} is taken back; current is wyrmd {from} again \
             (control plane restored from the pre-update backup: {restored})"
        ),
        release::Guarded::Stuck(why) => eprintln!("update-guard: {why}"),
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
    /// Put the release document RELEASE into the index INDEX (made new when
    /// it does not exist; a release of the same version is replaced).
    Index { release: PathBuf, index: PathBuf },
    /// Sign FILE (a release document, or an index with --index) with the
    /// seed in WYRMD_RELEASE_KEY; writes FILE.sig.
    Sign {
        file: PathBuf,
        #[arg(long)]
        index: bool,
    },
    /// Check FILE against FILE.sig with the keys built into this binary and
    /// the ones given.
    Verify {
        file: PathBuf,
        #[arg(long)]
        index: bool,
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

pub fn release_cmd(cmd: ReleaseCmd) -> Result<(), Error> {
    use ed25519_dalek::SigningKey;
    let read = |p: &Path| std::fs::read(p).map_err(|e| format!("{}: {e}", p.display()));
    match cmd {
        ReleaseCmd::Keygen => {
            let mut seed = zeroize::Zeroizing::new([0u8; 32]);
            getrandom::fill(seed.as_mut()).map_err(|e| format!("no randomness: {e}"))?;
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
            let me = release::identity().clone();
            std::fs::create_dir_all(&dir)?;
            let out = dir.join(format!("wyrmd-{}-{}.tar.gz", me.version, me.target));
            let asset = release::pack(
                &std::env::current_exe()?,
                &[],
                &out,
                flate2::Compression::best(),
            )?;
            let packed = Packed {
                identity: me,
                asset,
            };
            let mut side = out.clone().into_os_string();
            side.push(".json");
            std::fs::write(&side, pretty(&packed)?)?;
            println!("{}", out.display());
        }
        ReleaseCmd::Doc {
            dir,
            date,
            notes,
            min_from,
            base_url,
        } => {
            let mut packed: Vec<Packed> = Vec::new();
            for e in std::fs::read_dir(&dir)? {
                let path = e?.path();
                if path.to_string_lossy().ends_with(".tar.gz.json") {
                    packed.push(
                        serde_json::from_slice(&read(&path)?)
                            .map_err(|e| format!("{}: {e}", path.display()))?,
                    );
                }
            }
            let first = packed.first().ok_or("no packed archive in the directory")?;
            let id = first.identity.clone();
            let mut targets = BTreeMap::new();
            for p in &packed {
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
                let mut asset = p.asset.clone();
                if !base_url.is_empty() {
                    asset.url = format!("{}/{}", base_url.trim_end_matches('/'), asset.file);
                }
                if targets.insert(p.identity.target.clone(), asset).is_some() {
                    return Err(format!("target {} twice", p.identity.target).into());
                }
            }
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
            rel.check()?;
            let out = dir.join(format!("wyrmd-{}.release.json", rel.version));
            std::fs::write(&out, pretty(&rel)?)?;
            println!("{}", out.display());
        }
        ReleaseCmd::Index {
            release: doc,
            index,
        } => {
            let rel: release::Release = serde_json::from_slice(&read(&doc)?)
                .map_err(|e| format!("{}: {e}", doc.display()))?;
            rel.check()?;
            let mut idx = match std::fs::read(&index) {
                Ok(b) => serde_json::from_slice::<release::Index>(&b)
                    .map_err(|e| format!("{}: {e}", index.display()))?,
                Err(_) => release::Index {
                    wyrmd_releases: release::FORMAT,
                    releases: Vec::new(),
                },
            };
            idx.releases.retain(|r| r.version != rel.version);
            idx.releases.push(rel);
            std::fs::write(&index, pretty(&idx)?)?;
            println!("{}: {} releases", index.display(), idx.releases.len());
        }
        ReleaseCmd::Sign { file, index } => {
            let seed = zeroize::Zeroizing::new(
                std::env::var(RELEASE_KEY_ENV)
                    .map_err(|_| format!("{RELEASE_KEY_ENV} is not set"))?,
            );
            let raw: zeroize::Zeroizing<[u8; 32]> = zeroize::Zeroizing::new(
                hex::decode(seed.trim())
                    .ok()
                    .and_then(|b| b.try_into().ok())
                    .ok_or_else(|| format!("{RELEASE_KEY_ENV}: 64 hex digits"))?,
            );
            let key = SigningKey::from_bytes(&raw);
            let bytes = read(&file)?;
            let sig = if index {
                release::sign_index(&bytes, &key)
            } else {
                release::sign_release(&bytes, &key)
            };
            let out = sig_path(&file);
            std::fs::write(&out, format!("{sig}\n"))?;
            println!(
                "{} (public key {})",
                out.display(),
                hex::encode(key.verifying_key().to_bytes())
            );
        }
        ReleaseCmd::Verify { file, index, key } => {
            let keys = release::pinned_keys(&key)?;
            let bytes = read(&file)?;
            let sig =
                String::from_utf8(read(&sig_path(&file))?).map_err(|_| "signature: not text")?;
            if index {
                let i = release::read_index(&bytes, &sig, &keys)?;
                println!("ok: {} releases", i.releases.len());
            } else {
                let r = release::read_release(&bytes, &sig, &keys)?;
                println!("ok: wyrmd {}", r.version);
            }
        }
    }
    Ok(())
}

fn pretty<T: serde::Serialize>(v: &T) -> Result<Vec<u8>, String> {
    serde_json::to_vec_pretty(v).map_err(|e| e.to_string())
}
