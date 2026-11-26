//! Seed packages (ADR 0051 §1).
//!
//! A board image carries link packages in a read-only seed directory
//! (`packages.seed_dir`) with `seed.json`:
//!
//! ```json
//! {"format": "wyrm-seed/1", "links": [{"link": "modbus", "file": "modbus.zip", "accept": true}]}
//! ```
//!
//! A package cannot be put into `data_dir/packages` when the image is built:
//! `data_dir` is made at the first start, and [`super::Control::open`] removes
//! every package directory without a registry record. So the admin installs
//! each entry through [`Admin::install_package`], the path of
//! `sys/links ▸ install_zip`, with every check it makes for a new link, as
//! the subject `broker:seed`. One entry that fails does not stop the others.
//! When every entry was tried, `data_dir/seed.done` records the outcome of
//! each and the time, and the seed never runs again. It runs at the first
//! start that finds `seed.json` without `seed.done`: normally the first
//! start, or the start after an image update that added a seed.
//!
//! Each install is one long operation of its own ([`super::Control::busy`]):
//! a router rebuild waits for it, never for the whole seed. Before an
//! install, `data_dir/seed.progress.json` records that the entry started;
//! after it, the outcome. Both files are written whole (a new file renamed
//! into place) and replicated to a warm standby, with `seed.done`.
//!
//! A run that stops before the marker (a rebuild, a stop, a crash, a power
//! cut) goes on at the next start of the admin, on this broker or on a
//! promoted standby, from the progress file:
//! * an entry with an outcome keeps it and is not tried again;
//! * an entry that started and has no outcome was cut short during its
//!   install: it is reported as [`NOT_FINISHED`] (a warning and the marker)
//!   and not installed again; its link or package may be half made, and the
//!   operator decides (nothing repairs it on its own);
//! * an entry whose link exists (a restored backup) is skipped before its
//!   file is read, so the seed never updates that link's package;
//! * the other entries are tried.
//!
//! A `seed.json` that is missing or cannot be read installs nothing and
//! writes no marker: it is tried again at every start, with a warning.

use super::updates::UpdateOpts;
use super::{iso_utc, Admin, Busy, InstallError};
use crate::nofollow::{self, NofollowError};
use crate::packages::MAX_ZIP;
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};
use std::io::Read;
use std::path::{Path, PathBuf};
use std::time::Duration;
use tracing::{debug, info, warn};
use wyrm_core::clock::now_s;

/// The list of the seed directory.
pub const SEED_FILE: &str = "seed.json";
/// The one format of [`SEED_FILE`].
pub const SEED_FORMAT: &str = "wyrm-seed/1";
/// The marker in `data_dir`: the seed has run.
pub const SEED_DONE: &str = "seed.done";
/// In `data_dir` while the seed runs: per link, started and the outcome.
pub const SEED_PROGRESS: &str = "seed.progress.json";
/// Who installs the seed, in the audit journal.
pub const SEED_SUBJECT: &str = "broker:seed";
/// What the marker says of a link that was there before the seed.
const SKIPPED: &str = "skipped: the link exists";
/// What the marker says of an entry whose install was cut short.
pub const NOT_FINISHED: &str = "started and not finished: the broker stopped during its install; \
     check the link and its package (install it again with install_zip, or remove it)";
/// The largest `seed.json`.
const MAX_SEED_FILE: usize = 64 << 10;
/// The largest `seed.progress.json` (256 entries with long messages).
const MAX_PROGRESS_FILE: usize = 1 << 20;
/// The most entries of one seed.
const MAX_ENTRIES: usize = 256;
/// How long the seed waits for a router rebuild to end before it stops
/// for this router.
const BUSY_WAIT: Duration = Duration::from_secs(60);
const BUSY_RETRY: Duration = Duration::from_millis(500);

/// `seed.json`, a user file (principle 5: JSON).
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct SeedFile {
    format: String,
    links: Vec<SeedEntry>,
}

/// One link to make from one package of the seed directory.
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct SeedEntry {
    /// The id of the new link.
    link: String,
    /// The package zip: a plain file name in the seed directory.
    file: String,
    /// The package's network allowlist and grants are accepted, as
    /// `install_zip`'s `accept`.
    #[serde(default)]
    accept: bool,
}

/// `seed.done`: the outcome of each link and when the seed ran.
#[derive(Debug, Serialize)]
struct SeedDone<'a> {
    time: String,
    /// Per link: `ok`, [`SKIPPED`], [`NOT_FINISHED`] or the message of
    /// `success: false`.
    links: &'a BTreeMap<String, String>,
}

/// `seed.progress.json`: what a run that has not ended did so far.
#[derive(Debug, Default, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Progress {
    links: BTreeMap<String, Step>,
}

/// One entry of [`Progress`].
#[derive(Debug, Default, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Step {
    /// When its install started (ISO 8601 UTC).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    started: Option<String>,
    /// As in the marker.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    outcome: Option<String>,
}

/// Why the seed or one of its entries did not install. Each message holds
/// its cause: the marker keeps the text.
#[derive(Debug, thiserror::Error)]
pub enum SeedError {
    /// The seed directory was not resolved.
    #[error("seed directory {}: {source}", .path.display())]
    Dir {
        path: PathBuf,
        source: std::io::Error,
    },
    /// A file did not open inside the seed directory without following a
    /// symlink.
    #[error(transparent)]
    Open(#[from] NofollowError),
    #[error("{name}: {source}")]
    Read {
        name: String,
        source: std::io::Error,
    },
    #[error("{name}: larger than {max} bytes")]
    TooLarge { name: String, max: usize },
    #[error("{name}: {source}")]
    Parse {
        name: &'static str,
        source: serde_json::Error,
    },
    #[error("{SEED_FILE}: format {0:?}, expected {SEED_FORMAT:?}")]
    Format(String),
    #[error("{SEED_FILE}: link {0:?} is listed twice")]
    Duplicate(String),
    #[error("{SEED_FILE}: more than {MAX_ENTRIES} links")]
    TooMany,
    /// A `file` with a separator, a leading dot or nothing.
    #[error("{0:?}: not a plain file name in the seed directory")]
    FileName(String),
    #[error("{0}: not in the seed directory")]
    Missing(String),
    #[error(transparent)]
    Install(#[from] InstallError),
    /// A task that read files ended.
    #[error("a task of the seed ended: {0}")]
    Join(tokio::task::JoinError),
    /// `seed.done` or `seed.progress.json` was not written or read.
    #[error("{}: {source}", .path.display())]
    State {
        path: PathBuf,
        source: std::io::Error,
    },
    #[error("{name}: {source}")]
    Encode {
        name: &'static str,
        source: serde_json::Error,
    },
}

/// Why a run stopped before its marker; the next start goes on.
enum Stopped {
    /// The broker is closing (a rebuild, a stop).
    Busy,
    /// The progress file was not written.
    Progress(SeedError),
}

impl Admin {
    /// Install the seed in `dir` once (see the module): nothing when
    /// `seed.done` is there; else each entry left, then the marker.
    pub(super) async fn apply_seed(&self, dir: &Path) {
        let data = &self.ctl.cfg.data_dir;
        let marker = data.join(SEED_DONE);
        if marker.symlink_metadata().is_ok() {
            debug!("seed: done before ({})", marker.display());
            return;
        }
        let read = {
            let dir = dir.to_owned();
            tokio::task::spawn_blocking(move || read_seed(&dir)).await
        };
        let seed = match read.map_err(SeedError::Join) {
            Ok(Ok(Some(s))) => s,
            Ok(Ok(None)) => {
                warn!(
                    "seed: no {SEED_FILE} in {}; nothing installed, tried again at the next start",
                    dir.display()
                );
                return;
            }
            Ok(Err(e)) | Err(e) => {
                warn!("seed: {e}; nothing installed, tried again at the next start");
                return;
            }
        };
        let progress_path = data.join(SEED_PROGRESS);
        let mut progress = match read_progress(&progress_path) {
            Ok(p) => p,
            Err(e) => {
                warn!("seed: {e}; nothing installed, tried again at the next start");
                return;
            }
        };
        for e in &seed.links {
            match self.run_entry(dir, e, &mut progress, &progress_path).await {
                Ok(()) => {}
                Err(Stopped::Busy) => {
                    info!("seed: the broker is closing; the seed goes on at its next start");
                    return;
                }
                Err(Stopped::Progress(err)) => {
                    warn!("seed: {err}; the seed goes on at the next start");
                    return;
                }
            }
        }
        let links: BTreeMap<String, String> = seed
            .links
            .iter()
            .map(|e| {
                let outcome = progress
                    .links
                    .get(&e.link)
                    .and_then(|s| s.outcome.clone())
                    .unwrap_or_else(|| NOT_FINISHED.to_owned());
                (e.link.clone(), outcome)
            })
            .collect();
        if let Err(e) = write_json(
            &marker,
            SEED_DONE,
            &SeedDone {
                time: iso_utc(now_s()),
                links: &links,
            },
        ) {
            warn!("seed: {e}; the seed goes on at the next start");
            return;
        }
        info!("seed: done, {} links ({})", links.len(), marker.display());
        // the marker says all of it now
        if let Err(e) = std::fs::remove_file(&progress_path).or_else(wyrm_core::files::gone_ok) {
            warn!(
                "seed: {}: {e}; it stays, the marker is in force",
                progress_path.display()
            );
        }
    }

    /// One entry of the seed, its outcome recorded in `progress`. Stops
    /// (without an outcome) only while the broker closes or when the progress
    /// file is not written.
    async fn run_entry(
        &self,
        dir: &Path,
        e: &SeedEntry,
        progress: &mut Progress,
        path: &Path,
    ) -> Result<(), Stopped> {
        let id = e.link.as_str();
        let step = progress.links.entry(e.link.clone()).or_default();
        if step.outcome.is_some() {
            // an earlier run of this seed tried it
            return Ok(());
        }
        let outcome = if step.started.is_some() {
            warn!(link = %id, "seed: link {id}: {NOT_FINISHED}");
            NOT_FINISHED.to_owned()
        } else if self.ctl.registry().links.contains_key(id) {
            // a restored backup: its link is not touched, its file not read
            info!(link = %id, "seed: link {id} skipped (exists)");
            SKIPPED.to_owned()
        } else {
            match self.read_entry(dir, e).await {
                Err(err) => {
                    warn!(link = %id, "seed: link {id} not installed: {err}");
                    err.to_string()
                }
                Ok(zip) => {
                    // one long operation per install: a rebuild waits for it
                    let Some(_busy) = self.wait_busy().await else {
                        return Err(Stopped::Busy);
                    };
                    step.started = Some(iso_utc(now_s()));
                    write_json(path, SEED_PROGRESS, progress).map_err(Stopped::Progress)?;
                    let opts = UpdateOpts {
                        accept: e.accept,
                        ..UpdateOpts::default()
                    };
                    let source = format!("seed:{}", e.file);
                    match self
                        .install_package(id, zip, source, SEED_SUBJECT, opts)
                        .await
                    {
                        Ok(message) => {
                            info!(link = %id, "seed: link {id} installed: {message}");
                            "ok".to_owned()
                        }
                        Err(err) => {
                            warn!(link = %id, "seed: link {id} not installed: {err}");
                            err.to_string()
                        }
                    }
                }
            }
        };
        progress.links.entry(e.link.clone()).or_default().outcome = Some(outcome);
        write_json(path, SEED_PROGRESS, progress).map_err(Stopped::Progress)
    }

    /// One long operation, once no router rebuild holds the broker: `None`
    /// after [`BUSY_WAIT`] or when this router has stopped.
    async fn wait_busy(&self) -> Option<Busy<'_>> {
        let until = tokio::time::Instant::now() + BUSY_WAIT;
        loop {
            if self.ctx.is_closed() {
                return None;
            }
            match self.ctl.busy() {
                Ok(b) => return Some(b),
                Err(e) if tokio::time::Instant::now() >= until => {
                    debug!("seed: {}", e.message);
                    return None;
                }
                Err(_) => tokio::time::sleep(BUSY_RETRY).await,
            }
        }
    }

    /// The package of entry `e`: a plain file name of the seed directory.
    async fn read_entry(&self, dir: &Path, e: &SeedEntry) -> Result<Vec<u8>, SeedError> {
        let name = plain_name(&e.file)?.to_owned();
        let dir = dir.to_owned();
        tokio::task::spawn_blocking(move || read_zip(&dir, &name))
            .await
            .map_err(SeedError::Join)?
    }
}

/// `seed.progress.json` at `path`; empty when it is not there.
fn read_progress(path: &Path) -> Result<Progress, SeedError> {
    let state = |source| SeedError::State {
        path: path.to_owned(),
        source,
    };
    let file = match std::fs::File::open(path) {
        Ok(f) => f,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(Progress::default()),
        Err(e) => return Err(state(e)),
    };
    let bytes = read_bounded(file, SEED_PROGRESS, MAX_PROGRESS_FILE)?;
    serde_json::from_slice(&bytes).map_err(|source| SeedError::Parse {
        name: SEED_PROGRESS,
        source,
    })
}

/// `seed.json` of `dir`; `None` when the directory or the file is not
/// there.
fn read_seed(dir: &Path) -> Result<Option<SeedFile>, SeedError> {
    let Some(root) = resolve(dir)? else {
        return Ok(None);
    };
    let Some(file) = nofollow::open_under(&root, SEED_FILE)? else {
        return Ok(None);
    };
    let bytes = read_bounded(file, SEED_FILE, MAX_SEED_FILE)?;
    let seed: SeedFile = serde_json::from_slice(&bytes).map_err(|source| SeedError::Parse {
        name: SEED_FILE,
        source,
    })?;
    if seed.format != SEED_FORMAT {
        return Err(SeedError::Format(seed.format));
    }
    if seed.links.len() > MAX_ENTRIES {
        return Err(SeedError::TooMany);
    }
    let mut seen = BTreeSet::new();
    if let Some(e) = seed.links.iter().find(|e| !seen.insert(e.link.as_str())) {
        return Err(SeedError::Duplicate(e.link.clone()));
    }
    Ok(Some(seed))
}

/// The package `name` of the seed directory `dir`, read without following a
/// symlink and bounded as an `install_zip` argument.
fn read_zip(dir: &Path, name: &str) -> Result<Vec<u8>, SeedError> {
    let root = resolve(dir)?.ok_or_else(|| SeedError::Missing(name.to_owned()))?;
    let file =
        nofollow::open_under(&root, name)?.ok_or_else(|| SeedError::Missing(name.to_owned()))?;
    read_bounded(file, name, MAX_ZIP)
}

/// The seed directory as the operator named it, symlinks of its own path
/// resolved (an image may link it); `None` when it is not there. Files are
/// then opened inside it without following any symlink.
fn resolve(dir: &Path) -> Result<Option<PathBuf>, SeedError> {
    match std::fs::canonicalize(dir) {
        Ok(p) => Ok(Some(p)),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(source) => Err(SeedError::Dir {
            path: dir.to_owned(),
            source,
        }),
    }
}

/// At most `max` bytes of `file`: refused by its size first, and read no
/// further than one byte past it (a file that grows meanwhile).
fn read_bounded(file: std::fs::File, name: &str, max: usize) -> Result<Vec<u8>, SeedError> {
    let too_large = || SeedError::TooLarge {
        name: name.to_owned(),
        max,
    };
    let read = |source| SeedError::Read {
        name: name.to_owned(),
        source,
    };
    let len = file.metadata().map_err(read)?.len();
    if usize::try_from(len).map_or(true, |n| n > max) {
        return Err(too_large());
    }
    let limit = u64::try_from(max).map_or(u64::MAX, |m| m.saturating_add(1));
    let mut bytes = Vec::new();
    file.take(limit).read_to_end(&mut bytes).map_err(read)?;
    if bytes.len() > max {
        return Err(too_large());
    }
    Ok(bytes)
}

/// `file` when it is a plain name inside the seed directory: not empty, no
/// `/` or `\`, no leading `.` (so neither `.` nor `..`), no control
/// character.
fn plain_name(file: &str) -> Result<&str, SeedError> {
    let plain = !file.is_empty()
        && !file.starts_with('.')
        && !file.contains(['/', '\\'])
        && !file.chars().any(char::is_control);
    if plain {
        Ok(file)
    } else {
        Err(SeedError::FileName(file.to_owned()))
    }
}

/// `value` as JSON into `path` (`seed.done`, `seed.progress.json`), written
/// whole or not at all: a new file renamed into place.
fn write_json<T: Serialize>(path: &Path, name: &'static str, value: &T) -> Result<(), SeedError> {
    let bytes =
        serde_json::to_vec_pretty(value).map_err(|source| SeedError::Encode { name, source })?;
    crate::secret::write_private(path, &bytes).map_err(|source| SeedError::State {
        path: path.to_owned(),
        source,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn dir(name: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("wyrm-seed-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        d
    }

    #[test]
    fn file_names_are_plain() {
        for ok in ["a.zip", "modbus-1.0.0.zip", "a b.zip"] {
            assert_eq!(plain_name(ok).unwrap(), ok);
        }
        for bad in [
            "", ".", "..", "../x.zip", "d/x.zip", "d\\x.zip", ".hidden", "a\n.zip",
        ] {
            assert!(
                matches!(plain_name(bad), Err(SeedError::FileName(_))),
                "{bad:?}"
            );
        }
    }

    #[test]
    fn the_seed_file_is_read_strictly() {
        let d = dir("strict");
        let read = |text: &str| {
            std::fs::write(d.join(SEED_FILE), text).unwrap();
            read_seed(&d)
        };
        let s = read(r#"{"format": "wyrm-seed/1", "links": [{"link": "a", "file": "a.zip"}]}"#)
            .unwrap()
            .unwrap();
        assert_eq!(s.links.len(), 1);
        assert!(!s.links[0].accept);
        assert!(matches!(
            read(r#"{"format": "wyrm-seed/2", "links": []}"#),
            Err(SeedError::Format(f)) if f == "wyrm-seed/2"
        ));
        assert!(matches!(
            read(r#"{"format": "wyrm-seed/1", "links": [], "more": 1}"#),
            Err(SeedError::Parse {
                name: SEED_FILE,
                ..
            })
        ));
        assert!(matches!(
            read(r#"{"format": "wyrm-seed/1", "links": [{"link": "a", "file": "a.zip", "x": 1}]}"#),
            Err(SeedError::Parse {
                name: SEED_FILE,
                ..
            })
        ));
        assert!(matches!(
            read(
                r#"{"format": "wyrm-seed/1", "links": [{"link": "a", "file": "a.zip"},
                   {"link": "a", "file": "b.zip"}]}"#
            ),
            Err(SeedError::Duplicate(l)) if l == "a"
        ));
        std::fs::write(d.join(SEED_FILE), vec![b' '; MAX_SEED_FILE + 1]).unwrap();
        let e = read_seed(&d).unwrap_err();
        assert!(matches!(e, SeedError::TooLarge { .. }));
        // the bound in a unit that is not zero
        assert_eq!(e.to_string(), "seed.json: larger than 65536 bytes");
    }

    #[test]
    fn no_directory_or_no_seed_file_is_no_seed() {
        let d = dir("none");
        assert!(read_seed(&d).unwrap().is_none());
        assert!(read_seed(&d.join("absent")).unwrap().is_none());
    }

    #[cfg(unix)]
    #[test]
    fn a_symlink_out_of_the_seed_directory_is_not_followed() {
        let base = dir("symlink");
        let seed = base.join("seed");
        std::fs::create_dir_all(&seed).unwrap();
        std::fs::write(base.join("x.zip"), b"outside").unwrap();
        std::os::unix::fs::symlink(base.join("x.zip"), seed.join("link.zip")).unwrap();
        std::fs::write(seed.join("in.zip"), b"inside").unwrap();
        assert!(matches!(
            read_zip(&seed, "link.zip"),
            Err(SeedError::Open(_))
        ));
        assert!(matches!(
            read_zip(&seed, "gone.zip"),
            Err(SeedError::Missing(n)) if n == "gone.zip"
        ));
        assert_eq!(read_zip(&seed, "in.zip").unwrap(), b"inside");
        // the directory itself may be a link (an image's layout)
        let linked = base.join("linked");
        std::os::unix::fs::symlink(&seed, &linked).unwrap();
        assert_eq!(read_zip(&linked, "in.zip").unwrap(), b"inside");
    }

    #[test]
    fn the_marker_holds_each_outcome_and_the_time() {
        let d = dir("marker");
        let links = BTreeMap::from([
            ("a".to_owned(), "ok".to_owned()),
            ("b".to_owned(), SKIPPED.to_owned()),
        ]);
        let done = SeedDone {
            time: iso_utc(now_s()),
            links: &links,
        };
        write_json(&d.join(SEED_DONE), SEED_DONE, &done).unwrap();
        let v: serde_json::Value =
            serde_json::from_slice(&std::fs::read(d.join(SEED_DONE)).unwrap()).unwrap();
        assert_eq!(v["links"]["a"], "ok");
        assert_eq!(v["links"]["b"], SKIPPED);
        assert!(v["time"].as_str().unwrap().ends_with('Z'));
    }

    #[test]
    fn progress_is_kept_between_runs() {
        let d = dir("progress");
        let path = d.join(SEED_PROGRESS);
        assert!(read_progress(&path).unwrap().links.is_empty());
        let mut p = Progress::default();
        p.links.insert(
            "a".into(),
            Step {
                started: Some("2026-11-25T00:00:00Z".into()),
                outcome: Some("ok".into()),
            },
        );
        p.links.insert(
            "b".into(),
            Step {
                started: Some("2026-11-25T00:00:01Z".into()),
                outcome: None,
            },
        );
        write_json(&path, SEED_PROGRESS, &p).unwrap();
        let back = read_progress(&path).unwrap();
        assert_eq!(back.links["a"].outcome.as_deref(), Some("ok"));
        assert!(back.links["b"].started.is_some() && back.links["b"].outcome.is_none());
        std::fs::write(&path, br#"{"links": {}, "x": 1}"#).unwrap();
        assert!(matches!(
            read_progress(&path),
            Err(SeedError::Parse {
                name: SEED_PROGRESS,
                ..
            })
        ));
    }

    #[test]
    fn a_join_error_is_said_once() {
        use std::error::Error as _;
        let e = SeedError::Join(
            tokio::runtime::Runtime::new()
                .unwrap()
                .block_on(async { tokio::spawn(async { panic!("boom") }).await })
                .unwrap_err(),
        );
        assert!(e.source().is_none(), "the cause is in the message only");
        assert!(e.to_string().starts_with("a task of the seed ended: "));
    }
}
