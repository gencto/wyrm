//! Backups of a running broker (ADR 0048 §3): `sys/backups`.
//!
//! * `create {sections, links?, history_days?, passphrase?}` → `{id}` starts
//!   the one job that may run; `sys/backups/<id>` shows `status`,
//!   `progress`, `step`, `size`, `sha256`, `created`, `expires`, `error`.
//!   `estimate` gives the bytes of each section before anything is made.
//! * `sys/backups/<id>`: `download_part {offset, len}` (as ADR 0028: up to
//!   16 MiB a part, `{data, offset, size, eof}`), `remove`.
//! * Files stay in `data_dir/backups` (0700) for `backups.keep_days` within
//!   `backups.max_mb` (oldest removed first; a pinned one never).
//!
//! Every section is a consistent copy made while the broker runs, with the
//! standby's primitives (ADR 0036), not copies of them:
//! * control-plane WALs as of one sequence number each
//!   (`wyrm_state::replicate::copy_to`, the leader side of the standby);
//! * the broker storage as the whole tree at one revision
//!   (`wyrm_storage::Store::changes_since`, the standby's page);
//! * history day files and the index, each inside one read transaction
//!   (`wyrm_history::Store::copy_day`, then `copy_index`);
//! * link data, tokens, `secrets.bin` and packages from the standby's file
//!   list ([`replication::files_of`]), secrets sealed.
//!
//! A job stages its files under `data_dir/backups/.stage-*`, then writes
//! the zip (`wyrm_admin::backup`). The passphrase lives in the job's memory
//! only: never in the audit, the log, the tree or a file.

use super::*;
use crate::backup::{self as format, Head, Kind, LinkInfo, MasterKey, Staged, StagedSection};
use serde::{Deserialize, Serialize};
use std::sync::atomic::{AtomicBool, Ordering};
use zeroize::Zeroizing;

/// Longest part of one `download_part`, and the default.
pub const MAX_PART: u64 = 16 << 20;
pub const DEFAULT_PART: u64 = 4 << 20;
/// Kept free on the disk of `data_dir` when a job starts.
const KEEP_FREE: u64 = 64 << 20;
/// Jobs remembered (files kept): the oldest are removed beyond it.
const MAX_JOBS: usize = 200;
/// How often kept backups are checked against `keep_days` and `max_mb`.
const PRUNE_EVERY: Duration = Duration::from_secs(600);

/// `backups` in `wyrmd.json5`, and what `wyrmd` knows that the admin does not.
#[derive(Debug, Clone)]
pub struct BackupConfig {
    /// Days a backup is kept on the broker.
    pub keep_days: u32,
    /// Most MiB of kept backups; the oldest go first.
    pub max_mb: u64,
    /// Secrets may leave this broker in a backup sealed with a passphrase
    /// the caller picks (`backups.export_secrets`, default `false`; set on
    /// the host alone): the `keys` section, and link secrets and private
    /// data that open on any broker. While `false`, `keys` is refused and
    /// link secrets are sealed for this site only.
    pub export_secrets: bool,
    /// `wyrmd.json5` as read at start, as JSON with every secret masked
    /// ([`crate::secrets::mask_config`]), for the `config` section.
    pub config: Option<String>,
    /// `State::SCHEMA` of the stores other crates own: `users`, `flows`.
    pub schemas: BTreeMap<String, u32>,
}

impl Default for BackupConfig {
    fn default() -> Self {
        Self {
            keep_days: 7,
            max_mb: 2048,
            export_secrets: false,
            config: None,
            schemas: BTreeMap::new(),
        }
    }
}

/// What seals the secrets of a new backup.
pub enum SealWith {
    /// No secret goes in: `keys` and link data are refused.
    None,
    Passphrase(Zeroizing<Vec<u8>>),
    /// A key from this broker's `secrets.key`: restore points and
    /// pre-update backups, opened by this broker alone.
    Broker,
}

impl SealWith {
    fn name(&self) -> &'static str {
        match self {
            SealWith::None => "none",
            SealWith::Passphrase(_) => "passphrase",
            SealWith::Broker => "broker",
        }
    }
}

/// One backup to make.
pub struct BackupRequest {
    pub kind: Kind,
    /// Section names of `kind`; `control` (broker) and `settings` (link)
    /// are always made.
    pub sections: Vec<String>,
    /// Broker: the links of the `links` section (`None`: all).
    pub links: Option<Vec<String>>,
    /// Link: the link.
    pub link: Option<String>,
    /// History of the last N UTC days (`None`: all of it).
    pub history_days: Option<u32>,
    pub seal: SealWith,
    /// `full`, `link`, `pre-update`, `pre-restore`: shown as the job's kind.
    pub label: String,
    /// Never pruned (the pre-update backup of an unconfirmed update).
    pub pinned: bool,
    /// The caller's authority comes from another site (an upstream with
    /// `allow_config`, ADR 0018): this site's secrets never travel up.
    pub remote: bool,
    /// Only sizes are asked for: nothing is made, so nothing is gated.
    pub estimate: bool,
}

/// One backup job, kept beside its file as `<file>.json`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Job {
    pub id: String,
    /// `full`, `link`, `pre-update`, `pre-restore`.
    pub kind: String,
    #[serde(default)]
    pub link: String,
    pub sections: Vec<String>,
    /// `running`, `done`, `failed`.
    pub status: String,
    /// 0 to 100.
    pub progress: u8,
    /// What it does now (a section name, `writing`).
    #[serde(default)]
    pub step: String,
    pub size: u64,
    pub sha256: String,
    /// Unix seconds.
    pub created: u64,
    pub expires: u64,
    #[serde(default)]
    pub error: String,
    /// File name in `data_dir/backups`.
    pub file: String,
    /// `none`, `passphrase`, `broker`.
    #[serde(default)]
    pub sealed: String,
    #[serde(default)]
    pub by: String,
    #[serde(default)]
    pub pinned: bool,
}

/// The backup jobs of a broker; lives in [`Control`], outlives rebuilds.
pub struct Backups {
    jobs: Mutex<BTreeMap<String, Job>>,
    running: AtomicBool,
    /// Bumped on every change of a job: [`watch_backups`] publishes.
    changed: tokio::sync::watch::Sender<u64>,
    /// Files being uploaded for a restore or a link install (stage 3, 4).
    pub(super) uploads: Mutex<BTreeMap<String, super::restore::Upload>>,
}

impl Backups {
    /// Load the kept backups of `dir` (a file with its `.json`); anything
    /// half made by a broker that stopped (`.stage-*`, `*.part`) is removed.
    pub(super) fn open(dir: &Path) -> Self {
        let mut jobs = BTreeMap::new();
        for e in std::fs::read_dir(dir).into_iter().flatten().flatten() {
            let name = e.file_name().to_string_lossy().into_owned();
            let path = e.path();
            if name.starts_with(".stage-") || name.starts_with(".upload-") {
                let _ = std::fs::remove_dir_all(&path);
                let _ = std::fs::remove_file(&path);
            } else if name.ends_with(".part") {
                let _ = std::fs::remove_file(&path);
            } else if let Some(file) = name.strip_suffix(".json") {
                let job = std::fs::read(&path)
                    .ok()
                    .and_then(|b| serde_json::from_slice::<Job>(&b).ok())
                    .filter(|j| j.file == file && j.status == "done" && dir.join(file).is_file())
                    .filter(|j| wyrm_core::keyspace::validate_segment(&j.id).is_ok());
                match job {
                    Some(j) => {
                        jobs.insert(j.id.clone(), j);
                    }
                    None => {
                        let _ = std::fs::remove_file(&path);
                    }
                }
            }
        }
        Self {
            jobs: Mutex::new(jobs),
            running: AtomicBool::new(false),
            changed: tokio::sync::watch::channel(0).0,
            uploads: Mutex::default(),
        }
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, BTreeMap<String, Job>> {
        self.jobs.lock().unwrap_or_else(|p| p.into_inner())
    }

    fn notify(&self) {
        self.changed.send_modify(|n| *n += 1);
    }

    /// Every job, oldest first.
    pub fn list(&self) -> Vec<Job> {
        let mut v: Vec<Job> = self.lock().values().cloned().collect();
        v.sort_by(|a, b| (a.created, &a.id).cmp(&(b.created, &b.id)));
        v
    }

    pub fn get(&self, id: &str) -> Option<Job> {
        self.lock().get(id).cloned()
    }

    fn update(&self, id: &str, f: impl FnOnce(&mut Job)) {
        if let Some(j) = self.lock().get_mut(id) {
            f(j);
        }
        self.notify();
    }
}

/// The control-plane WALs of a backup: section file directory, directory
/// under `data_dir`, HMAC key file, name in `schemas`. The standby's three
/// ([`replication::STORES`]) and the audit journal, which a standby keeps
/// of its own.
pub(super) fn wal_stores() -> Vec<(&'static str, &'static str, &'static str, &'static str)> {
    let mut v: Vec<_> = replication::STORES
        .iter()
        .map(|(name, dir, key)| {
            let schema = match *name {
                "state" => "registry",
                other => other,
            };
            (*name, *dir, *key, schema)
        })
        .collect();
    v.push(("audit", "audit", "state.key", "audit"));
    v
}

/// Key files of the `keys` section, relative to `data_dir`: the key bundle
/// of a standby ([`crate::keys::FILES`]) and the flow engine's signing key.
pub(super) fn key_files() -> Vec<&'static str> {
    let mut v = crate::keys::FILES.to_vec();
    v.push("flows/flow.key");
    v
}

fn id_of(secs: u64) -> String {
    iso_utc(secs)
        .chars()
        .filter(|c| c.is_ascii_alphanumeric())
        .collect::<String>()
        .to_ascii_lowercase()
}

fn json_map<const N: usize>(
    pairs: [(&str, serde_json::Value); N],
) -> serde_json::Map<String, serde_json::Value> {
    pairs.into_iter().map(|(k, v)| (k.to_owned(), v)).collect()
}

pub(super) fn io_err(path: &Path, e: std::io::Error) -> String {
    format!("{}: {e}", path.display())
}

/// The stage directory of one job, removed when the job ends.
pub(super) struct StageDir(pub(super) PathBuf);

impl StageDir {
    pub(super) fn new(backups: &Path) -> Result<Self, String> {
        let mut r = [0u8; 8];
        getrandom::fill(&mut r).map_err(|e| format!("no randomness: {e}"))?;
        let dir = backups.join(format!(".stage-{}", hex::encode(r)));
        make_private_dir(&dir)?;
        Ok(Self(dir))
    }
}

impl Drop for StageDir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

pub(super) fn make_private_dir(dir: &Path) -> Result<(), String> {
    let mut b = std::fs::DirBuilder::new();
    b.recursive(true);
    #[cfg(unix)]
    std::os::unix::fs::DirBuilderExt::mode(&mut b, 0o700);
    b.create(dir).map_err(|e| io_err(dir, e))
}

/// Puts files of one backup into its stage directory.
struct Stager<'a> {
    dir: &'a Path,
    key: Option<&'a MasterKey>,
}

impl Stager<'_> {
    fn place(&self, path: &str) -> Result<PathBuf, String> {
        format::check_path(path)?;
        let p = self.dir.join(path);
        if let Some(d) = p.parent() {
            std::fs::create_dir_all(d).map_err(|e| io_err(d, e))?;
        }
        Ok(p)
    }

    fn key(&self, path: &str) -> Result<&MasterKey, String> {
        self.key
            .ok_or_else(|| format!("{path}: holds secrets; the backup needs a passphrase"))
    }

    /// `bytes` as the plain file `path`.
    fn bytes(&self, path: &str, bytes: &[u8]) -> Result<Staged, String> {
        let p = self.place(path)?;
        std::fs::write(&p, bytes).map_err(|e| io_err(&p, e))?;
        Ok(Staged {
            path: path.to_owned(),
            source: p,
            sealed: false,
            exec: false,
        })
    }

    /// `bytes` as the sealed file `path`.
    fn sealed_bytes(&self, path: &str, bytes: &[u8]) -> Result<Staged, String> {
        let key = self.key(path)?;
        let p = self.place(path)?;
        std::fs::write(&p, format::seal_bytes(key, path, bytes)).map_err(|e| io_err(&p, e))?;
        Ok(Staged {
            path: path.to_owned(),
            source: p,
            sealed: true,
            exec: false,
        })
    }

    /// The file `src` as the sealed file `path`.
    fn sealed_file(&self, path: &str, src: &Path) -> Result<Staged, String> {
        let key = self.key(path)?;
        let p = self.place(path)?;
        let from = std::io::BufReader::new(std::fs::File::open(src).map_err(|e| io_err(src, e))?);
        let to = std::io::BufWriter::new(std::fs::File::create(&p).map_err(|e| io_err(&p, e))?);
        format::seal_stream(key, path, from, to).map_err(|e| io_err(src, e))?;
        Ok(Staged {
            path: path.to_owned(),
            source: p,
            sealed: true,
            exec: false,
        })
    }

    /// The file `src` itself as the plain file `path` (not copied: the
    /// writer fails the backup if it changes meanwhile).
    fn direct(&self, path: &str, src: PathBuf, exec: bool) -> Result<Staged, String> {
        format::check_path(path)?;
        Ok(Staged {
            path: path.to_owned(),
            source: src,
            sealed: false,
            exec,
        })
    }
}

/// `true` for a link secret that is the link's identity on one broker,
/// made by that broker: its requester key and an agent's signing key. They
/// never leave the broker in a backup and are never taken from one; the
/// broker that restores a link makes new ones. (A link's token is not a
/// secret of the store: it is in no link backup at all, and in a broker
/// backup only in `keys`.) The store key is not one of them: it is the key
/// of the link's private files, which are useless without it, and travels
/// sealed beside them.
pub(super) fn broker_made_secret(name: &str) -> bool {
    name == wyrm_link_sdk::REQUESTER_KEY || name == AGENT_KEY_REF
}

/// The secrets of a link that go into a backup: all but the broker-made.
fn exported_secrets(
    all: BTreeMap<String, Zeroizing<Vec<u8>>>,
) -> BTreeMap<String, Zeroizing<Vec<u8>>> {
    all.into_iter()
        .filter(|(name, _)| !broker_made_secret(name))
        .collect()
}

/// What a link backup made by [`Control::link_backup_to`] holds.
#[derive(Debug, Clone, PartialEq)]
pub struct LinkBackup {
    pub link: String,
    /// The link's package version (empty for a built-in driver).
    pub version: String,
    /// Bytes of the file.
    pub size: u64,
    /// SHA-256 (hex) of the file.
    pub sha256: String,
    pub sections: Vec<String>,
}

impl Control {
    /// `data_dir/backups` (0700).
    pub fn backups_dir(&self) -> PathBuf {
        self.cfg.data_dir.join("backups")
    }

    /// The backup jobs (`sys/backups`).
    pub fn backups(&self) -> &Backups {
        &self.backups
    }

    pub(super) fn schemas(&self) -> BTreeMap<String, u32> {
        use wyrm_state::State;
        let mut m = self.cfg.backups.schemas.clone();
        m.insert("registry".into(), Registry::SCHEMA);
        m.insert("audit".into(), AuditLog::SCHEMA);
        m
    }

    /// The package a link runs (`pkg:<name>`), if any.
    fn package_of(&self, def: &LinkDef) -> Option<PackageDef> {
        let name = def.driver.strip_prefix(packages::DRIVER_PREFIX)?;
        self.registry().packages.get(name).cloned()
    }

    /// Check a request before a job is made for it: section names, links,
    /// the passphrase, what needs sealing. The canonical section list is
    /// returned (the order of the format, the always-made one included).
    fn check_request(&self, req: &BackupRequest) -> Result<Vec<String>, String> {
        let all = req.kind.sections();
        if let Some(s) = req.sections.iter().find(|s| !all.contains(&s.as_str())) {
            return Err(format!(
                "sections: no section {s:?} (one of {})",
                all.join(", ")
            ));
        }
        let always = match req.kind {
            Kind::Broker => "control",
            Kind::Link => "settings",
        };
        let chosen: Vec<String> = all
            .iter()
            .filter(|s| **s == always || req.sections.iter().any(|c| c == *s))
            .map(|s| (*s).to_owned())
            .collect();
        if let SealWith::Passphrase(p) = &req.seal {
            if p.len() < crate::keys::MIN_PASSPHRASE {
                return Err(format!(
                    "passphrase: at least {} characters",
                    crate::keys::MIN_PASSPHRASE
                ));
            }
        }
        let has = |s: &str| chosen.iter().any(|c| c == s);
        // Secrets leave the site only when the host said so, and never
        // towards an upstream (ADR 0048 §3.4, §4).
        let passphrase = matches!(req.seal, SealWith::Passphrase(_));
        if passphrase || (has("keys") && !req.estimate) {
            let what = if has("keys") {
                "keys: the site's keys and secrets"
            } else {
                "passphrase: secrets sealed with a passphrase"
            };
            if !self.cfg.backups.export_secrets {
                return Err(format!(
                    "{what} do not leave this broker: backups.export_secrets is false in \
                     wyrmd.json5 (set it on the host to allow it). Without a passphrase, link \
                     secrets and private data are sealed for this site and open only on a \
                     broker that holds its keys"
                ));
            }
            if req.remote {
                return Err(format!(
                    "{what} never travel to another site: make this backup on the broker's \
                     own gateway, not through its upstream"
                ));
            }
        }
        let reg = self.registry();
        match req.kind {
            Kind::Broker => {
                if has("keys") && !passphrase && !req.estimate {
                    return Err("keys: the keys and secrets need a passphrase".into());
                }
                if let Some(l) = req
                    .links
                    .iter()
                    .flatten()
                    .find(|l| !reg.links.contains_key(*l))
                {
                    return Err(format!("links: no link {l}"));
                }
                if has("config") && self.cfg.backups.config.is_none() {
                    return Err("config: this broker was not started from a file".into());
                }
            }
            Kind::Link => {
                let id = req.link.as_deref().ok_or("link: required")?;
                let def = reg.links.get(id).ok_or_else(|| format!("no link {id}"))?;
                if has("data") && def.mode == Mode::External {
                    return Err(
                        "data: an external link keeps its data on its own host, not here".into(),
                    );
                }
                if has("package") && self.package_of(def).is_none() {
                    return Err(format!(
                        "package: {id} runs the built-in driver {}, not a package",
                        def.driver
                    ));
                }
            }
        }
        Ok(chosen)
    }

    /// Bytes each section of `req` would take, before compression.
    pub fn backup_estimate(&self, req: &BackupRequest) -> Result<BTreeMap<String, u64>, String> {
        let chosen = self.check_request(req)?;
        let d = &self.cfg.data_dir;
        let len = |p: PathBuf| std::fs::metadata(p).map_or(0, |m| m.len());
        let files = replication::files_of(d);
        let under = |prefix: &str| -> u64 {
            files
                .iter()
                .filter(|f| f.name.starts_with(prefix))
                .map(|f| f.len)
                .sum()
        };
        let reg = self.registry();
        let link_ids: Vec<String> = match (&req.links, &req.link) {
            (_, Some(l)) => vec![l.clone()],
            (Some(l), _) => l.clone(),
            (None, None) => reg.links.keys().cloned().collect(),
        };
        let history = || -> u64 {
            let store = self.history.store();
            let days = history_days(store, req.history_days);
            let all: u64 = days.iter().map(|day| store.day_bytes(*day)).sum();
            match req.kind {
                Kind::Broker => all + len(d.join("history").join("index.redb")),
                // a share by series, as a guide: the link's rows are read to know
                Kind::Link => {
                    let n = store.series_count().max(1) as u64;
                    let own = req.link.as_deref().map_or(0, |l| {
                        store.series_under(&link_prefix(&self.cfg.site, l)).len()
                    }) as u64;
                    all / n * own
                }
            }
        };
        let mut out = BTreeMap::new();
        for s in chosen {
            let bytes = match s.as_str() {
                "control" => wal_stores()
                    .iter()
                    .map(|(_, dir, _, _)| dir_bytes(&d.join(dir)))
                    .sum(),
                "keys" => {
                    key_files().iter().map(|f| len(d.join(f))).sum::<u64>()
                        + len(d.join("secrets.bin"))
                }
                "dataflows" => dir_bytes(&d.join("flows").join("artifacts")),
                "storage" => self.storage().map_or(0, |s| s.bytes() as u64),
                "history" => history(),
                "links" => link_ids
                    .iter()
                    .map(|l| under(&format!("links/{l}/data/")) + 1024)
                    .sum(),
                "packages" => under("packages/"),
                "config" => self
                    .cfg
                    .backups
                    .config
                    .as_ref()
                    .map_or(0, |c| c.len() as u64),
                "settings" => 1024,
                "data" => under(&format!("links/{}/data/", link_ids[0])),
                "package" => reg
                    .links
                    .get(&link_ids[0])
                    .and_then(|l| self.package_of(l))
                    .map_or(0, |p| under(&format!("packages/{}/{}/", p.name, p.version))),
                _ => 0,
            };
            out.insert(s, bytes);
        }
        Ok(out)
    }

    /// Make the backup of `req` at `out` (blocking; call it off the async
    /// runtime). `progress(step, percent)`. Nothing of the broker stops.
    pub(super) fn write_backup(
        &self,
        req: &BackupRequest,
        out: &Path,
        progress: &dyn Fn(&str, u8),
    ) -> Result<format::Written, String> {
        let chosen = self.check_request(req)?;
        let backups = self.backups_dir();
        make_private_dir(&backups)?;
        let stage = StageDir::new(&backups)?;
        let secrets_key;
        // without a passphrase, what holds secrets is sealed for this site
        let secret_parts = chosen.iter().any(|c| c == "links" || c == "data");
        let sealing = match &req.seal {
            SealWith::None if !secret_parts => format::Sealing::None,
            SealWith::Passphrase(p) => format::Sealing::Passphrase(p),
            SealWith::None | SealWith::Broker => {
                secrets_key = secret::load_or_create_key(&self.cfg.data_dir.join("secrets.key"))
                    .map_err(|e| format!("secrets.key: {e}"))?;
                format::Sealing::Broker(&secrets_key)
            }
        };
        let (sealed, key) = sealing.start()?;
        let st = Stager {
            dir: &stage.0,
            key: key.as_ref(),
        };
        let reg = self.registry();
        let mut link = None;
        let mut sections = Vec::with_capacity(chosen.len() + 1);
        // the packages of the chosen links go with them when `packages`
        // (all of them) was not asked for
        let mut link_packages: BTreeSet<String> = BTreeSet::new();
        for (i, name) in chosen.iter().enumerate() {
            progress(name, (i * 50 / chosen.len().max(1)) as u8);
            let s = match (req.kind, name.as_str()) {
                (Kind::Broker, "control") => self.stage_control(&st)?,
                (Kind::Broker, "keys") => self.stage_keys(&st)?,
                (Kind::Broker, "dataflows") => self.stage_dataflows(&st)?,
                (Kind::Broker, "storage") => self.stage_storage(&st)?,
                (Kind::Broker, "history") => self.stage_history(&st, req.history_days)?,
                (Kind::Broker, "links") => {
                    let ids: Vec<String> = match &req.links {
                        Some(l) => l.clone(),
                        None => reg.links.keys().cloned().collect(),
                    };
                    let mut s = StagedSection {
                        name: "links".into(),
                        ..Default::default()
                    };
                    for id in ids {
                        let def = reg.links.get(&id).ok_or_else(|| format!("no link {id}"))?;
                        let base = format!("links/{id}");
                        s.files.extend(self.stage_link_settings(&st, def, &base)?);
                        // an external link keeps its data on its own host
                        let data = def.mode != Mode::External;
                        if data {
                            s.files.extend(self.stage_link_data(&st, def, &base)?);
                        }
                        if let Some(p) = self.package_of(def) {
                            link_packages.insert(p.name);
                        }
                        s.info.insert(
                            id.clone(),
                            serde_json::json!({"driver": def.driver, "mode": def.mode.name(), "data": data}),
                        );
                    }
                    s
                }
                (Kind::Broker, "packages") => {
                    let all: Vec<PackageDef> = reg.packages.values().cloned().collect();
                    self.stage_packages(&st, &all, false)?
                }
                (Kind::Broker, "config") => {
                    let text = self
                        .cfg
                        .backups
                        .config
                        .as_ref()
                        .ok_or("config: this broker was not started from a file")?;
                    StagedSection {
                        name: "config".into(),
                        info: json_map([("restored", false.into()), ("secrets", "masked".into())]),
                        files: vec![st.bytes("config/wyrmd.json", text.as_bytes())?],
                    }
                }
                (Kind::Link, section) => {
                    let id = req.link.as_deref().ok_or("link: required")?;
                    let def = reg.links.get(id).ok_or_else(|| format!("no link {id}"))?;
                    let package = self.package_of(def);
                    link.get_or_insert_with(|| LinkInfo {
                        id: def.id.clone(),
                        driver: def.driver.clone(),
                        mode: def.mode.name().to_owned(),
                        package: package.as_ref().map(|p| p.name.clone()).unwrap_or_default(),
                        version: package
                            .as_ref()
                            .map(|p| p.version.clone())
                            .unwrap_or_default(),
                    });
                    match section {
                        "settings" => StagedSection {
                            name: "settings".into(),
                            info: json_map([
                                ("driver", def.driver.clone().into()),
                                ("mode", def.mode.name().into()),
                                ("rev", def.rev.into()),
                            ]),
                            files: self.stage_link_settings(&st, def, "settings")?,
                        },
                        "data" => {
                            let files = self.stage_link_data(&st, def, "data")?;
                            StagedSection {
                                name: "data".into(),
                                info: json_map([("files", (files.len().saturating_sub(1)).into())]),
                                files,
                            }
                        }
                        "package" => {
                            let p = package
                                .ok_or_else(|| format!("package: {id} does not run a package"))?;
                            let mut s = self.stage_packages(&st, &[p], true)?;
                            s.name = "package".into();
                            s
                        }
                        "history" => self.stage_link_history(&st, id, req.history_days)?,
                        other => return Err(format!("no section {other}")),
                    }
                }
                (_, other) => return Err(format!("no section {other}")),
            };
            sections.push(s);
        }
        if req.kind == Kind::Broker && !chosen.iter().any(|c| c == "packages") {
            let defs: Vec<PackageDef> = link_packages
                .iter()
                .filter_map(|n| reg.packages.get(n).cloned())
                .collect();
            if !defs.is_empty() {
                let mut s = self.stage_packages(&st, &defs, false)?;
                s.info.insert("only_of_links".into(), true.into());
                // in the order of the format: after `links`
                let at = sections
                    .iter()
                    .position(|x: &StagedSection| x.name == "config")
                    .unwrap_or(sections.len());
                sections.insert(at, s);
            }
        }
        let head = Head {
            kind: req.kind,
            site: self.cfg.site.clone(),
            broker: env!("CARGO_PKG_VERSION").to_owned(),
            created: iso_utc(now_s()),
            schemas: self.schemas(),
            sealed,
            link,
        };
        progress("writing", 50);
        format::write(out, head, sections, key.as_ref(), |done, total| {
            let pct = 50 + (done.saturating_mul(50) / total.max(1)).min(50);
            progress("writing", pct as u8);
        })
    }

    /// `control`: each control-plane WAL as of one sequence number.
    fn stage_control(&self, st: &Stager) -> Result<StagedSection, String> {
        let d = &self.cfg.data_dir;
        let mut s = StagedSection {
            name: "control".into(),
            ..Default::default()
        };
        for (name, dir, key_file, _) in wal_stores() {
            let src = d.join(dir);
            if !src.is_dir() {
                continue;
            }
            let key = secret::load_or_create_key(&d.join(key_file))
                .map_err(|e| format!("{key_file}: {e}"))?;
            let dest = st.dir.join("control").join(name);
            let head = wyrm_state::replicate::copy_to(&src, &key, &dest)
                .map_err(|e| format!("{name}: {e}"))?;
            s.info.insert(name.to_owned(), head.lsn.into());
            for e in std::fs::read_dir(&dest).map_err(|e| io_err(&dest, e))? {
                let e = e.map_err(|e| io_err(&dest, e))?;
                let file = e.file_name().to_string_lossy().into_owned();
                s.files
                    .push(st.direct(&format!("control/{name}/{file}"), e.path(), false)?);
            }
        }
        s.files.sort_by(|a, b| a.path.cmp(&b.path));
        Ok(s)
    }

    /// `keys`: the key files, `secrets.bin` and the link tokens, all sealed.
    fn stage_keys(&self, st: &Stager) -> Result<StagedSection, String> {
        let d = &self.cfg.data_dir;
        let mut names: Vec<String> = key_files().into_iter().map(str::to_owned).collect();
        names.push("secrets.bin".into());
        names.extend(
            replication::files_of(d)
                .into_iter()
                .map(|f| f.name)
                .filter(|n| {
                    matches!(
                        n.split('/').collect::<Vec<_>>().as_slice(),
                        ["links", _, "token"]
                    )
                }),
        );
        let mut s = StagedSection {
            name: "keys".into(),
            ..Default::default()
        };
        for name in names {
            let src = d.join(&name);
            if !src.is_file() {
                continue;
            }
            s.files.push(st.sealed_file(&format!("keys/{name}"), &src)?);
        }
        for must in ["pki/ca.key", "state.key", "secrets.key"] {
            if !s.files.iter().any(|f| f.path == format!("keys/{must}")) {
                return Err(format!("keys: {must} not found in the data_dir"));
            }
        }
        Ok(s)
    }

    /// `dataflows`: the flow engine's artifacts. Its store is the WAL
    /// `control/flows`, which every backup holds.
    fn stage_dataflows(&self, st: &Stager) -> Result<StagedSection, String> {
        let root = self.cfg.data_dir.join("flows");
        let mut found = Vec::new();
        replication::walk(&root, "artifacts", &mut found);
        let mut s = StagedSection {
            name: "dataflows".into(),
            info: json_map([("store", "control/flows".into())]),
            files: Vec::new(),
        };
        for f in found {
            s.files
                .push(st.direct(&format!("dataflows/{}", f.name), root.join(&f.name), false)?);
        }
        Ok(s)
    }

    /// `storage`: the whole tree at one revision, as the standby gets it,
    /// and as the JSON of the storage's own `export`.
    fn stage_storage(&self, st: &Stager) -> Result<StagedSection, String> {
        let store = self.storage().ok_or("storage: not open")?;
        // epoch 0 is never the store's: the answer is the whole tree
        let tree = store.changes_since(0, 0, 1);
        let bytes = wyrm_core::codec::to_vec(&replication::changes_value(&tree))
            .map_err(|e| format!("storage: {e}"))?;
        let mut s = StagedSection {
            name: "storage".into(),
            info: json_map([("rev", tree.rev.into()), ("nodes", tree.put.len().into())]),
            files: vec![st.bytes("storage/tree.cbor", &bytes)?],
        };
        if let Some(text) = wyrm_storage::json::export("", &tree.put, 256 << 20) {
            s.files
                .push(st.bytes("storage/export.json", text.as_bytes())?);
        }
        Ok(s)
    }

    /// `history`: the day files of the range, then the index, each a copy
    /// from inside one read transaction.
    fn stage_history(&self, st: &Stager, days: Option<u32>) -> Result<StagedSection, String> {
        let store = self.history.store();
        let chosen = history_days(store, days);
        let mut s = StagedSection {
            name: "history".into(),
            ..Default::default()
        };
        let mut rows = 0u64;
        let mut names = Vec::new();
        for day in chosen {
            let name = wyrm_history::time::day_name(day);
            let path = format!("history/days/{name}.redb");
            let dest = st.place(&path)?;
            match store.copy_day(day, &dest).map_err(|e| e.to_string())? {
                Some(n) => rows += n,
                None => continue,
            }
            names.push(serde_json::Value::from(name));
            s.files.push(st.direct(&path, dest, false)?);
        }
        let dest = st.place("history/index.redb")?;
        store.copy_index(&dest).map_err(|e| e.to_string())?;
        s.files.push(st.direct("history/index.redb", dest, false)?);
        s.info = json_map([
            ("days", names.into()),
            ("rows", rows.into()),
            ("store", store.id().into()),
        ]);
        Ok(s)
    }

    /// A link's definition as `<base>/link.cbor`, without its token hash
    /// (a restored link gets a token of its own).
    fn stage_link_settings(
        &self,
        st: &Stager,
        def: &LinkDef,
        base: &str,
    ) -> Result<Vec<Staged>, String> {
        let mut def = def.clone();
        def.token_hash.clear();
        let bytes = minicbor::to_vec(&def).map_err(|e| format!("{}: {e}", def.id))?;
        Ok(vec![st.bytes(&format!("{base}/link.cbor"), &bytes)?])
    }

    /// A link's secrets as `<base>/secrets` and the files of its private
    /// directory as `<base>/files/**`, all sealed.
    fn stage_link_data(
        &self,
        st: &Stager,
        def: &LinkDef,
        base: &str,
    ) -> Result<Vec<Staged>, String> {
        let secrets = Zeroizing::new(
            wyrm_core::codec::to_vec(&Value::Map(
                exported_secrets(self.secrets.for_link(&def.id))
                    .into_iter()
                    .map(|(k, v)| (k, Value::Bytes(v.to_vec())))
                    .collect(),
            ))
            .map_err(|e| format!("{}: {e}", def.id))?,
        );
        let mut out = vec![st.sealed_bytes(&format!("{base}/secrets"), &secrets)?];
        let prefix = format!("links/{}/data/", def.id);
        for f in replication::files_of(&self.cfg.data_dir) {
            let Some(rel) = f.name.strip_prefix(&prefix) else {
                continue;
            };
            let src = self.cfg.data_dir.join(&f.name);
            match st.sealed_file(&format!("{base}/files/{rel}"), &src) {
                Ok(s) => out.push(s),
                // a file the link removed since the list was made
                Err(_) if !src.exists() => {}
                Err(e) => return Err(e),
            }
        }
        Ok(out)
    }

    /// Packages as `packages/<name>/files/**`, or the one of a link backup
    /// as `package/files/**` (`single`): the files of the installed
    /// directory, `wyrm-link.json` among them. No record of the registry
    /// goes with them: a restore builds it from the files, through the
    /// validator of every install.
    fn stage_packages(
        &self,
        st: &Stager,
        defs: &[PackageDef],
        single: bool,
    ) -> Result<StagedSection, String> {
        let root = self.packages_root();
        let files = replication::files_of(&self.cfg.data_dir);
        let mut s = StagedSection {
            name: "packages".into(),
            ..Default::default()
        };
        for def in defs {
            let base = if single {
                "package".to_owned()
            } else {
                format!("packages/{}", def.name)
            };
            let prefix = format!("packages/{}/{}/", def.name, def.version);
            let mut n = 0;
            for f in files.iter().filter(|f| f.name.starts_with(&prefix)) {
                let rel = &f.name[prefix.len()..];
                let src = packages::dir(&root, def).join(rel);
                s.files
                    .push(st.direct(&format!("{base}/files/{rel}"), src, f.exec)?);
                n += 1;
            }
            if n == 0 {
                return Err(format!(
                    "package {} {}: no files under {}",
                    def.name,
                    def.version,
                    packages::dir(&root, def).display()
                ));
            }
            s.info.insert(
                def.name.clone(),
                serde_json::json!({"version": def.version, "kind": def.kind.name(), "sha256": def.sha256}),
            );
        }
        Ok(s)
    }

    /// A link backup's `history`: the rows of the link's points in pages
    /// `history/rows-<n>.cbor`, each an array of `[key below the link, t, v, q]`.
    fn stage_link_history(
        &self,
        st: &Stager,
        id: &str,
        days: Option<u32>,
    ) -> Result<StagedSection, String> {
        let store = self.history.store();
        let prefix = link_prefix(&self.cfg.site, id);
        let from = match days {
            Some(n) => {
                let today = (wyrm_history::engine::now_us() / US_PER_DAY) as i64;
                ((today - i64::from(n.max(1)) + 1).max(0) as u64) * US_PER_DAY
            }
            None => 0,
        };
        let mut s = StagedSection {
            name: "history".into(),
            ..Default::default()
        };
        let mut page: Vec<Value> = Vec::new();
        let mut total = 0u64;
        let flush = |page: &mut Vec<Value>, s: &mut StagedSection| -> Result<(), String> {
            if page.is_empty() {
                return Ok(());
            }
            let bytes = wyrm_core::codec::to_vec(&Value::Array(std::mem::take(page)))
                .map_err(|e| e.to_string())?;
            let path = format!("history/rows-{:05}.cbor", s.files.len());
            s.files.push(st.bytes(&path, &bytes)?);
            Ok(())
        };
        let series = store.series_under(&prefix);
        for (key, sid) in &series {
            let rel = key[prefix.len()..].to_owned();
            let mut rows = Vec::new();
            store
                .scan(*sid, from, u64::MAX, |r| {
                    rows.push(r);
                    true
                })
                .map_err(|e| e.to_string())?;
            for r in rows {
                page.push(Value::Array(vec![
                    Value::from(rel.clone()),
                    Value::UInt(r.t),
                    r.v,
                    Value::UInt(r.q.code().into()),
                ]));
                total += 1;
                if page.len() >= LINK_HISTORY_PAGE {
                    flush(&mut page, &mut s)?;
                }
            }
        }
        flush(&mut page, &mut s)?;
        s.info = json_map([("rows", total.into()), ("series", series.len().into())]);
        Ok(s)
    }

    /// A backup of the link `id` **without history** at `path`: its
    /// settings, its private data and secrets, and its package when it runs
    /// one. Sealed for this broker (a key from `secrets.key`), so it needs
    /// no passphrase and only this broker opens it: the restore point of a
    /// package update (ADR 0048 §1.3). Blocking: call it off the async
    /// runtime. The link is not stopped. `path` is written whole or not at
    /// all (`<path>.part` meanwhile); its directory must exist.
    pub fn link_backup_to(&self, id: &str, path: &Path) -> Result<LinkBackup, String> {
        let def = self
            .registry()
            .links
            .get(id)
            .cloned()
            .ok_or_else(|| format!("no link {id}"))?;
        let mut sections = vec!["settings".to_owned()];
        if def.mode != Mode::External {
            sections.push("data".into());
        }
        let package = self.package_of(&def);
        if package.is_some() {
            sections.push("package".into());
        }
        let req = BackupRequest {
            kind: Kind::Link,
            sections: sections.clone(),
            links: None,
            link: Some(id.to_owned()),
            history_days: None,
            seal: SealWith::Broker,
            label: "link".into(),
            pinned: false,
            remote: false,
            estimate: false,
        };
        let w = self.write_backup(&req, path, &|_, _| {})?;
        Ok(LinkBackup {
            link: id.to_owned(),
            version: package.map(|p| p.version).unwrap_or_default(),
            size: w.size,
            sha256: w.sha256,
            sections,
        })
    }

    /// Remove kept backups past `expires` and, oldest first, those beyond
    /// `max_mb` and [`MAX_JOBS`]; never a pinned one, the running one or
    /// the newest. Returns the ids removed.
    pub fn prune_backups(&self) -> Vec<String> {
        let now = now_s();
        let max = self.cfg.backups.max_mb.saturating_mul(1 << 20);
        let jobs = self.backups.list();
        let newest = jobs
            .iter()
            .filter(|j| j.status == "done")
            .map(|j| j.id.clone())
            .next_back();
        let mut total: u64 = jobs.iter().map(|j| j.size).sum();
        let mut count = jobs.len();
        let mut gone = Vec::new();
        for j in &jobs {
            if j.status == "running" || j.pinned {
                continue;
            }
            let failed_old = j.status == "failed" && j.created + 86_400 < now;
            let expired = j.expires <= now;
            let over = (total > max || count > MAX_JOBS) && Some(&j.id) != newest.as_ref();
            if expired || over || failed_old {
                total = total.saturating_sub(j.size);
                count -= 1;
                self.drop_backup(&j.id);
                gone.push(j.id.clone());
            }
        }
        if !gone.is_empty() {
            info!(removed = ?gone, "backups pruned");
        }
        gone
    }

    /// Forget a job and remove its files.
    fn drop_backup(&self, id: &str) -> Option<Job> {
        let job = self.backups.lock().remove(id)?;
        if !job.file.is_empty() {
            let dir = self.backups_dir();
            let _ = std::fs::remove_file(dir.join(&job.file));
            let _ = std::fs::remove_file(dir.join(format!("{}.json", job.file)));
        }
        self.backups.notify();
        Some(job)
    }

    /// Start the job of `req`; `Err(busy)` while another runs. The id of
    /// the new job is returned at once.
    pub fn backup_start(
        self: &Arc<Self>,
        req: BackupRequest,
        sub: &str,
    ) -> Result<String, LinkError> {
        self.backup_launch(req, sub, false)
    }

    /// Make the backup of `req` as a job and wait for it (blocking: call
    /// it off the async runtime). `Err` when it is refused or fails.
    pub(super) fn backup_now(
        self: &Arc<Self>,
        req: BackupRequest,
        sub: &str,
    ) -> Result<Job, String> {
        let id = self.backup_launch(req, sub, true).map_err(|e| e.message)?;
        match self.backups.get(&id) {
            Some(j) if j.status == "done" => Ok(j),
            Some(j) => Err(j.error),
            None => Err("the backup is gone".into()),
        }
    }

    fn backup_launch(
        self: &Arc<Self>,
        req: BackupRequest,
        sub: &str,
        wait: bool,
    ) -> Result<String, LinkError> {
        let chosen = self
            .check_request(&req)
            .map_err(LinkError::invalid_parameter)?;
        let need: u64 = self
            .backup_estimate(&req)
            .map_err(LinkError::invalid_parameter)?
            .values()
            .sum();
        if let Some(free) = disk_free_mib(&self.cfg.data_dir) {
            // staged once and written once
            let want = (need.saturating_mul(2) + KEEP_FREE) as f64 / f64::from(1 << 20);
            if free < want {
                return Err(LinkError::new(
                    Status::ResourceExhausted,
                    format!(
                        "the backup needs about {want:.0} MiB on the disk of data_dir, {free:.0} MiB are free"
                    ),
                ));
            }
        }
        if self.backups.running.swap(true, Ordering::SeqCst) {
            return Err(LinkError::new(
                Status::Busy,
                "a backup is being made; one at a time",
            ));
        }
        let now = now_s();
        let (id, file) = {
            let mut jobs = self.backups.lock();
            let mut id = id_of(now);
            let mut n = 1;
            while jobs.contains_key(&id) {
                n += 1;
                id = format!("{}-{n}", id_of(now));
            }
            let file = match &req.link {
                Some(l) => format!("{}-{l}-{id}.{}", self.cfg.site, req.kind.extension()),
                None => format!("{}-{id}.{}", self.cfg.site, req.kind.extension()),
            };
            jobs.insert(
                id.clone(),
                Job {
                    id: id.clone(),
                    kind: req.label.clone(),
                    link: req.link.clone().unwrap_or_default(),
                    sections: chosen.clone(),
                    status: "running".into(),
                    progress: 0,
                    step: String::new(),
                    size: 0,
                    sha256: String::new(),
                    created: now,
                    expires: now + u64::from(self.cfg.backups.keep_days.max(1)) * 86_400,
                    error: String::new(),
                    file: file.clone(),
                    sealed: match &req.seal {
                        SealWith::None if chosen.iter().any(|c| c == "links" || c == "data") => {
                            "broker"
                        }
                        s => s.name(),
                    }
                    .to_owned(),
                    by: sub.to_owned(),
                    pinned: req.pinned,
                },
            );
            (id, file)
        };
        self.backups.notify();
        let (op, key) = match &req.link {
            Some(l) => ("link_backup", l.clone()),
            None => ("backup_create", id.clone()),
        };
        // the request as it is audited: never the passphrase
        let has = |s: &str| chosen.iter().any(|c| c == s);
        let exported = matches!(req.seal, SealWith::Passphrase(_));
        if exported {
            warn!(
                backup = %id, by = sub, keys = has("keys"),
                "a backup with secrets sealed by a passphrase is being made: with that \
                 passphrase it opens anywhere (backups.export_secrets)"
            );
        }
        let detail = format!(
            "{id}: sections {}; sealed {}; keys: {}; secrets: {}{}",
            chosen.join(", "),
            match &req.seal {
                SealWith::None if has("links") || has("data") => "broker",
                s => s.name(),
            },
            has("keys"),
            exported && (has("keys") || has("links") || has("data")),
            req.history_days
                .map(|d| format!("; history {d} days"))
                .unwrap_or_default()
        );
        self.record(sub, op, &key, Status::Ok, &detail);
        let ctl = self.clone();
        let (sub, job_id) = (sub.to_owned(), id.clone());
        let run = move || {
            let out = ctl.backups_dir().join(&file);
            let r = ctl.write_backup(&req, &out, &|step, pct| {
                ctl.backups.update(&job_id, |j| {
                    j.step = step.to_owned();
                    j.progress = pct.min(99);
                });
            });
            // the passphrase goes with the request
            drop(req);
            match r {
                Ok(w) => {
                    ctl.backups.update(&job_id, |j| {
                        j.status = "done".into();
                        j.progress = 100;
                        j.step.clear();
                        j.size = w.size;
                        j.sha256 = w.sha256.clone();
                    });
                    if let Some(j) = ctl.backups.get(&job_id) {
                        let side = ctl.backups_dir().join(format!("{file}.json"));
                        let saved = serde_json::to_vec_pretty(&j)
                            .map_err(|e| e.to_string())
                            .and_then(|b| {
                                secret::write_private(&side, &b).map_err(|e| e.to_string())
                            });
                        if let Err(e) = saved {
                            warn!(backup = %job_id, "the backup is made, its record is not saved: {e}");
                        }
                    }
                    info!(backup = %job_id, size = w.size, "backup made");
                }
                Err(e) => {
                    warn!(backup = %job_id, "backup failed: {e}");
                    let _ = std::fs::remove_file(&out);
                    ctl.record(
                        &sub,
                        op,
                        &key,
                        Status::InternalError,
                        &format!("{job_id}: {e}"),
                    );
                    ctl.backups.update(&job_id, |j| {
                        j.status = "failed".into();
                        j.step.clear();
                        j.error = e;
                    });
                }
            }
            ctl.backups.running.store(false, Ordering::SeqCst);
            ctl.prune_backups();
            ctl.backups.notify();
        };
        if wait {
            run();
        } else {
            tokio::task::spawn_blocking(run);
        }
        Ok(id)
    }

    /// One part of a finished backup's file: `(bytes, total size)`.
    pub fn backup_part(
        &self,
        id: &str,
        offset: u64,
        len: u64,
    ) -> Result<(Vec<u8>, u64), LinkError> {
        use std::io::{Read, Seek, SeekFrom};
        let job = self
            .backups
            .get(id)
            .ok_or_else(|| LinkError::not_found(format!("backup {id}")))?;
        if job.status != "done" {
            return Err(LinkError::new(
                Status::Busy,
                format!("backup {id} is {}", job.status),
            ));
        }
        if len == 0 || len > MAX_PART {
            return Err(LinkError::invalid_parameter(format!(
                "len: 1 to {MAX_PART} bytes"
            )));
        }
        if offset > job.size {
            return Err(LinkError::new(
                Status::OutOfRange,
                format!("offset {offset}: the file has {} bytes", job.size),
            ));
        }
        let path = self.backups_dir().join(&job.file);
        let internal = |e: std::io::Error| LinkError::internal(io_err(&path, e));
        let mut f = std::fs::File::open(&path).map_err(internal)?;
        f.seek(SeekFrom::Start(offset)).map_err(internal)?;
        let want = len.min(job.size - offset) as usize;
        let mut data = vec![0u8; want];
        f.read_exact(&mut data).map_err(internal)?;
        Ok((data, job.size))
    }
}

/// Rows in one page of a link backup's history.
const LINK_HISTORY_PAGE: usize = 20_000;
const US_PER_DAY: u64 = 86_400_000_000;

/// `wy/<site>/downstream/<link>/`: the keys of a link's points.
pub(super) fn link_prefix(site: &str, link: &str) -> String {
    format!("wy/{site}/downstream/{link}/")
}

/// The days of the store a backup of the last `days` UTC days holds
/// (`None`: every day).
fn history_days(store: &wyrm_history::Store, days: Option<u32>) -> Vec<i64> {
    let all = store.days();
    match days {
        None => all,
        Some(n) => {
            let today = (wyrm_history::engine::now_us() / US_PER_DAY) as i64;
            let first = today - i64::from(n.max(1)) + 1;
            all.into_iter().filter(|d| *d >= first).collect()
        }
    }
}

fn list_arg(args: &Value, name: &str) -> Result<Option<Vec<String>>, LinkError> {
    let bad = || LinkError::invalid_parameter(format!("{name}: a list of names"));
    match arg(args, name) {
        None | Some(Value::Null) => Ok(None),
        Some(Value::Array(a)) => a
            .iter()
            .map(|v| match v {
                Value::Str(s) => Ok(s.clone()),
                _ => Err(bad()),
            })
            .collect::<Result<Vec<_>, _>>()
            .map(Some),
        // a form field: names separated by commas or spaces
        Some(Value::Str(s)) => Ok(Some(
            s.split([',', ' '])
                .filter(|p| !p.is_empty())
                .map(str::to_owned)
                .collect(),
        )),
        Some(_) => Err(bad()),
    }
}

pub(super) fn uint_arg(args: &Value, name: &str) -> Result<Option<u64>, LinkError> {
    match arg(args, name) {
        None | Some(Value::Null) => Ok(None),
        Some(Value::UInt(n)) => Ok(Some(*n)),
        Some(v) => match v.as_f64() {
            Some(f) if f >= 0.0 && f.fract() == 0.0 && f < 9.0e15 => Ok(Some(f as u64)),
            _ => Err(LinkError::invalid_parameter(format!(
                "{name}: a whole number"
            ))),
        },
    }
}

/// The passphrase of a call, out of its arguments.
pub(super) fn passphrase_arg(args: &Value) -> Result<Option<Zeroizing<Vec<u8>>>, LinkError> {
    match arg(args, "passphrase") {
        None | Some(Value::Null) => Ok(None),
        Some(Value::Str(s)) if s.is_empty() => Ok(None),
        Some(Value::Str(s)) => Ok(Some(Zeroizing::new(s.as_bytes().to_vec()))),
        Some(_) => Err(LinkError::invalid_parameter("passphrase: text")),
    }
}

/// The request of `create` / `estimate` (broker) or `backup` (link `Some`).
pub(super) fn request_of(
    args: &Value,
    link: Option<&str>,
    remote: bool,
) -> Result<BackupRequest, LinkError> {
    let sections = list_arg(args, "sections")?.unwrap_or_default();
    let history_days = match uint_arg(args, "history_days")? {
        Some(0) | None => None,
        Some(n) => Some(
            u32::try_from(n).map_err(|_| LinkError::invalid_parameter("history_days: too many"))?,
        ),
    };
    Ok(BackupRequest {
        kind: if link.is_some() {
            Kind::Link
        } else {
            Kind::Broker
        },
        sections,
        links: if link.is_some() {
            None
        } else {
            list_arg(args, "links")?
        },
        link: link.map(str::to_owned),
        history_days,
        seal: match passphrase_arg(args)? {
            Some(p) => SealWith::Passphrase(p),
            None => SealWith::None,
        },
        label: if link.is_some() { "link" } else { "full" }.to_owned(),
        pinned: false,
        remote,
        estimate: false,
    })
}

fn passphrase_param() -> ParamMeta {
    str_param()
        .display("Passphrase")
        .editor(EDITOR_PASSWORD)
        .description(format!(
            "At least {} characters; only with backups.export_secrets. Without it, link secrets are sealed for this site",
            crate::keys::MIN_PASSPHRASE
        ))
}

fn sections_param(kind: Kind) -> ParamMeta {
    ParamMeta::of(TypeCode::Array)
        .display("Sections")
        .description(format!("Of: {}", kind.sections().join(", ")))
}

fn history_days_param() -> ParamMeta {
    ParamMeta::of(TypeCode::Number)
        .display("History days")
        .description("History of the last N days (UTC); empty: all of it")
}

/// The `backup` action of a link node (`sys/links/<id>`).
pub(super) fn link_backup_action() -> ActionMeta {
    ActionMeta::new()
        .display("Back up")
        .param("sections", sections_param(Kind::Link))
        .param("history_days", history_days_param())
        .param("passphrase", passphrase_param())
        .result(ActionResult::Type(TypeCode::Map))
        .level(Perm::Config)
}

/// `sys/backups` and its actions.
pub(super) async fn declare(ctx: &LinkCtx, ctl: &Control) -> wyrm_link_sdk::Result<()> {
    ctx.declare_node(
        "backups",
        NodeMeta::folder()
            .attr("keep_days", u64::from(ctl.cfg.backups.keep_days))
            .attr("max_mb", ctl.cfg.backups.max_mb)
            .attr("export_secrets", ctl.cfg.backups.export_secrets)
            .attr(
                "sections",
                Value::Array(
                    format::BROKER_SECTIONS
                        .iter()
                        .map(|s| Value::from(*s))
                        .collect(),
                ),
            ),
    )
    .await?;
    let request = |m: ActionMeta| {
        m.param("sections", sections_param(Kind::Broker))
            .param(
                "links",
                ParamMeta::of(TypeCode::Array)
                    .display("Links")
                    .description("Links of the section links; empty: all"),
            )
            .param("history_days", history_days_param())
            .result(ActionResult::Type(TypeCode::Map))
            .level(Perm::Config)
    };
    ctx.declare_action(
        "backups",
        "create",
        request(ActionMeta::new().display("Back up").group(GROUP_NEW))
            .param("passphrase", passphrase_param()),
    )
    .await?;
    ctx.declare_action(
        "backups",
        "estimate",
        request(ActionMeta::new().display("Estimate")),
    )
    .await?;
    super::restore::declare(ctx).await?;
    super::restore::declare_broker(ctx).await
}

fn job_node(j: &Job) -> NodeMeta {
    let mut n = NodeMeta::folder()
        .is("wy:backup")
        .attr("kind", j.kind.as_str())
        .attr("name", j.file.as_str())
        .attr(
            "sections",
            Value::Array(j.sections.iter().map(|s| Value::from(s.clone())).collect()),
        )
        .attr("sealed", j.sealed.as_str())
        .attr("by", j.by.as_str());
    if !j.link.is_empty() {
        n = n.attr("link", j.link.as_str());
    }
    n
}

const JOB_TEXT: [&str; 6] = ["status", "step", "sha256", "created", "expires", "error"];

async fn declare_job(ctx: &LinkCtx, j: &Job) -> wyrm_link_sdk::Result<()> {
    let path = format!("backups/{}", j.id);
    ctx.declare_node(&path, job_node(j)).await?;
    for name in JOB_TEXT {
        ctx.declare_node(&format!("{path}/{name}"), NodeMeta::leaf(TypeCode::String))
            .await?;
    }
    ctx.declare_node(&format!("{path}/progress"), NodeMeta::number().unit("%"))
        .await?;
    ctx.declare_node(&format!("{path}/size"), NodeMeta::number().unit("B"))
        .await?;
    ctx.declare_action(
        &path,
        "download_part",
        ActionMeta::new()
            .display("Download part")
            .param(
                "offset",
                ParamMeta::of(TypeCode::Number)
                    .required(true)
                    .display("Offset (bytes)"),
            )
            .param(
                "len",
                ParamMeta::of(TypeCode::Number)
                    .display("Length (bytes)")
                    .description("default 4 MiB, at most 16 MiB"),
            )
            .result(ActionResult::Type(TypeCode::Map))
            .timeout_ms(60_000)
            .level(Perm::Config),
    )
    .await?;
    ctx.declare_action(
        &path,
        "remove",
        ActionMeta::new()
            .display("Remove")
            .group(GROUP_EDIT)
            .level(Perm::Config),
    )
    .await?;
    super::restore::declare_send(ctx, &path).await
}

async fn publish_job(ctx: &LinkCtx, j: &Job) -> wyrm_link_sdk::Result<()> {
    let path = format!("backups/{}", j.id);
    let t = now_us();
    let text = [
        ("status", j.status.clone()),
        ("step", j.step.clone()),
        ("sha256", j.sha256.clone()),
        ("created", iso_utc(j.created)),
        ("expires", iso_utc(j.expires)),
        ("error", j.error.clone()),
    ];
    for (name, v) in text {
        ctx.update(&format!("{path}/{name}"), Value::Str(v), Quality::Good, t)
            .await?;
    }
    ctx.update(
        &format!("{path}/progress"),
        Value::UInt(j.progress.into()),
        Quality::Good,
        t,
    )
    .await?;
    ctx.update(
        &format!("{path}/size"),
        Value::UInt(j.size),
        Quality::Good,
        t,
    )
    .await
}

/// Shows the jobs under `sys/backups` for as long as this router runs:
/// declares each, publishes its values when they move, removes the nodes
/// of removed ones; prunes kept backups every ten minutes.
pub(super) async fn watch_backups(ctl: Arc<Control>, ctx: LinkCtx) {
    let mut rx = ctl.backups.changed.subscribe();
    let mut shown: BTreeMap<String, Job> = BTreeMap::new();
    let mut prune = tokio::time::interval(PRUNE_EVERY);
    loop {
        let now: BTreeMap<String, Job> = ctl
            .backups
            .list()
            .into_iter()
            .map(|j| (j.id.clone(), j))
            .collect();
        for (id, j) in &now {
            let old = shown.get(id);
            if old == Some(j) {
                continue;
            }
            let r = async {
                if old.is_none() {
                    declare_job(&ctx, j).await?;
                }
                publish_job(&ctx, j).await
            }
            .await;
            if let Err(e) = r {
                debug!(backup = %id, "sys/backups: {e}");
            }
        }
        for id in shown.keys().filter(|id| !now.contains_key(*id)) {
            if let Err(e) = ctx.remove_node(&format!("backups/{id}")).await {
                debug!(backup = %id, "sys/backups: {e}");
            }
        }
        shown = now;
        tokio::select! {
            r = rx.changed() => {
                if r.is_err() {
                    return;
                }
                // a running job moves often: publish at most five times a second
                tokio::time::sleep(Duration::from_millis(200)).await;
                rx.borrow_and_update();
            }
            _ = prune.tick() => {
                let ctl = ctl.clone();
                let _ = tokio::task::spawn_blocking(move || {
                    ctl.prune_backups();
                    ctl.drop_stale_uploads();
                })
                .await;
            }
        }
    }
}

/// Show a job that just started, before its id is answered: the caller
/// can use `sys/backups/<id>` at once (the watcher keeps it up to date).
pub(super) async fn show_job(ctx: &LinkCtx, ctl: &Control, id: &str) {
    let Some(j) = ctl.backups.get(id) else {
        return;
    };
    let r = async {
        declare_job(ctx, &j).await?;
        publish_job(ctx, &j).await
    }
    .await;
    if let Err(e) = r {
        debug!(backup = %id, "sys/backups: {e}");
    }
}

/// Actions under `sys/backups` (`rest`: the path below it).
pub(super) async fn invoke(
    ctl: &Arc<Control>,
    ctx: &LinkCtx,
    rest: &[&str],
    action: &str,
    args: &Value,
    sub: &str,
    remote: bool,
) -> wyrm_link_sdk::Result<Option<Value>> {
    match (rest, action) {
        ([], "create") => {
            let id = ctl.backup_start(request_of(args, None, remote)?, sub)?;
            show_job(ctx, ctl, &id).await;
            Ok(Some(Value::Map(BTreeMap::from([(
                "id".to_owned(),
                Value::Str(id),
            )]))))
        }
        ([], "estimate") => {
            // sizes do not depend on the sealing: every section is estimated,
            // also one this caller could not make
            let mut req = request_of(args, None, false)?;
            req.seal = SealWith::Broker;
            req.estimate = true;
            let ctl2 = ctl.clone();
            let sizes = tokio::task::spawn_blocking(move || ctl2.backup_estimate(&req))
                .await
                .map_err(|e| LinkError::internal(e.to_string()))?
                .map_err(LinkError::invalid_parameter)?;
            let total: u64 = sizes.values().sum();
            Ok(Some(Value::Map(BTreeMap::from([
                (
                    "sections".to_owned(),
                    Value::Map(
                        sizes
                            .into_iter()
                            .map(|(k, v)| (k, Value::UInt(v)))
                            .collect(),
                    ),
                ),
                ("total".to_owned(), Value::UInt(total)),
            ]))))
        }
        ([id], "download_part") => {
            let offset = uint_arg(args, "offset")?
                .ok_or_else(|| LinkError::invalid_parameter("offset: required"))?;
            let len = match uint_arg(args, "len")? {
                Some(n) => n,
                None => uint_arg(args, "length")?.unwrap_or(DEFAULT_PART),
            };
            let (ctl2, id2) = (ctl.clone(), (*id).to_owned());
            let (data, size) =
                tokio::task::spawn_blocking(move || ctl2.backup_part(&id2, offset, len))
                    .await
                    .map_err(|e| LinkError::internal(e.to_string()))??;
            if offset == 0 {
                ctl.record(
                    sub,
                    "backup_download",
                    id,
                    Status::Ok,
                    &format!("{size} bytes"),
                );
            }
            let end = offset + data.len() as u64;
            Ok(Some(Value::Map(BTreeMap::from([
                ("offset".to_owned(), Value::UInt(offset)),
                ("size".to_owned(), Value::UInt(size)),
                ("eof".to_owned(), Value::Bool(end >= size)),
                ("data".to_owned(), Value::Bytes(data)),
            ]))))
        }
        ([id], "remove") => {
            match ctl.backups.get(id) {
                None => return Err(LinkError::not_found(format!("backup {id}"))),
                Some(j) if j.status == "running" => {
                    return Err(LinkError::new(Status::Busy, "the backup is being made"))
                }
                Some(_) => {}
            }
            if let Some(j) = ctl.drop_backup(id) {
                ctl.record(sub, "backup_remove", id, Status::Ok, &j.file);
            }
            Ok(None)
        }
        _ => super::restore::invoke(ctl, rest, action, args, sub).await,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ids_are_segments_in_time_order() {
        let a = id_of(1_794_564_900);
        assert_eq!(a.len(), 16);
        assert!(wyrm_core::keyspace::validate_segment(&a).is_ok());
        assert!(a < id_of(1_794_564_901));
        assert!(a.starts_with("20") && a.ends_with('z') && a.contains('t'));
    }

    #[test]
    fn the_stores_of_a_backup_are_the_standbys_and_the_audit() {
        let names: Vec<&str> = wal_stores().iter().map(|s| s.0).collect();
        assert_eq!(names, ["state", "flows", "users", "audit"]);
        assert!(wal_stores().iter().any(|s| s.3 == "registry"));
        assert!(key_files().contains(&"pki/ca.key") && key_files().contains(&"flows/flow.key"));
    }

    #[test]
    fn arguments() {
        let args = Value::Map(BTreeMap::from([
            (
                "sections".to_owned(),
                Value::Array(vec!["storage".into(), "keys".into()]),
            ),
            ("links".to_owned(), Value::from("a, b")),
            ("history_days".to_owned(), Value::Float(7.0)),
            (
                "passphrase".to_owned(),
                Value::from("correct horse battery"),
            ),
        ]));
        let r = request_of(&args, None, false).unwrap();
        assert_eq!(r.sections, ["storage", "keys"]);
        assert_eq!(r.links, Some(vec!["a".to_owned(), "b".to_owned()]));
        assert_eq!(r.history_days, Some(7));
        assert!(matches!(r.seal, SealWith::Passphrase(_)));
        let r = request_of(&Value::Map(BTreeMap::new()), Some("plc"), true).unwrap();
        assert!(r.remote);
        assert!(r.kind == Kind::Link && r.link.as_deref() == Some("plc"));
        assert!(matches!(r.seal, SealWith::None) && r.history_days.is_none());
        let bad = Value::Map(BTreeMap::from([("sections".to_owned(), Value::UInt(1))]));
        assert!(request_of(&bad, None, false).is_err());
        let bad = Value::Map(BTreeMap::from([(
            "history_days".to_owned(),
            Value::Float(1.5),
        )]));
        assert!(request_of(&bad, None, false).is_err());
    }

    #[test]
    fn broker_made_secrets_stay_out_of_a_backup() {
        let secret = |v: &[u8]| Zeroizing::new(v.to_vec());
        let all = BTreeMap::from([
            (wyrm_link_sdk::REQUESTER_KEY.to_owned(), secret(b"seed")),
            (AGENT_KEY_REF.to_owned(), secret(b"agent")),
            (
                wyrm_link_sdk::driver::persist::STORE_KEY.to_owned(),
                secret(b"store"),
            ),
            ("password".to_owned(), secret(b"pw")),
        ]);
        let out = exported_secrets(all);
        let names: Vec<&str> = out.keys().map(String::as_str).collect();
        // the identity keys stay; the key of the private files and what a
        // person entered go, sealed
        assert_eq!(
            names,
            [wyrm_link_sdk::driver::persist::STORE_KEY, "password"]
        );
        assert!(broker_made_secret(wyrm_link_sdk::REQUESTER_KEY));
        assert!(broker_made_secret("agent_key"));
    }
}
