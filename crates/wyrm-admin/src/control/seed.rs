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
//! every package directory without a registry record. So on its first start
//! the admin installs each entry through [`Admin::install_package`], the path
//! of `sys/links ▸ install_zip`, with every check it makes for a new link, as
//! the subject `broker:seed`. One entry that fails does not stop the others.
//! When every entry was tried, `data_dir/seed.done` records the outcome of
//! each and the time, and the seed never runs again.
//!
//! A run that ends before the marker (a crash, a power cut, the broker
//! stopped or rebuilt meanwhile) runs again at the next start of the admin,
//! and so does a promoted standby (`seed.done` is not replicated). That is
//! safe: an entry whose link exists is skipped before its file is read, so a
//! package installed by the first run is neither installed again nor
//! updated, and only the entries left are tried. A `seed.json` that is
//! missing or cannot be read installs nothing and writes no marker: it is
//! tried again at every start, with a warning.

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
/// Who installs the seed, in the audit journal.
pub const SEED_SUBJECT: &str = "broker:seed";
/// What the marker says of a link that was there before the seed.
const SKIPPED: &str = "skipped: the link exists";
/// The largest `seed.json`.
const MAX_SEED_FILE: usize = 64 << 10;
/// The most entries of one seed.
const MAX_ENTRIES: usize = 256;
/// How long the seed waits for a router rebuild to end before it gives up
/// for this start.
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
    /// Per link: `ok`, [`SKIPPED`] or the message of `success: false`.
    links: &'a BTreeMap<String, String>,
}

/// Why the seed or one of its entries did not install.
#[derive(Debug, thiserror::Error)]
pub enum SeedError {
    /// The seed directory was not resolved.
    #[error("seed directory {}: {source}", .path.display())]
    Dir {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    /// A file did not open inside the seed directory without following a
    /// symlink.
    #[error(transparent)]
    Open(#[from] NofollowError),
    #[error("{name}: {source}")]
    Read {
        name: String,
        #[source]
        source: std::io::Error,
    },
    #[error("{name}: larger than {max_mib} MiB")]
    TooLarge { name: String, max_mib: usize },
    #[error("{SEED_FILE}: {0}")]
    Parse(#[source] serde_json::Error),
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
    #[error("{0}")]
    Join(#[source] tokio::task::JoinError),
    #[error("{}: {source}", .path.display())]
    Marker {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("{SEED_DONE}: {0}")]
    Encode(#[source] serde_json::Error),
}

/// What one entry did.
enum Seeded {
    /// Installed; holds the install's message.
    Installed(String),
    /// Its link was there.
    Skipped,
}

impl Admin {
    /// Install the seed in `dir` once (see the module): nothing when
    /// `seed.done` is there; else each entry, then the marker.
    pub(super) async fn apply_seed(&self, dir: &Path) {
        let marker = self.ctl.cfg.data_dir.join(SEED_DONE);
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
        // one operation for the whole seed: a router rebuild that one of
        // its process links asks for waits until the marker is written
        let Some(_busy) = self.wait_busy().await else {
            warn!("seed: the broker stays busy; tried again at its next start");
            return;
        };
        let mut links = BTreeMap::new();
        for e in &seed.links {
            let outcome = match self.seed_entry(dir, e).await {
                Ok(Seeded::Installed(message)) => {
                    info!(link = %e.link, "seed: link {} installed: {message}", e.link);
                    "ok".to_owned()
                }
                Ok(Seeded::Skipped) => {
                    info!(link = %e.link, "seed: link {} skipped (exists)", e.link);
                    SKIPPED.to_owned()
                }
                Err(err) => {
                    warn!(link = %e.link, "seed: link {} not installed: {err}", e.link);
                    err.to_string()
                }
            };
            links.insert(e.link.clone(), outcome);
        }
        match write_marker(&marker, &links) {
            Ok(()) => info!("seed: done, {} links ({})", links.len(), marker.display()),
            Err(e) => warn!("seed: {e}; the seed runs again at the next start"),
        }
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

    /// Install entry `e`, unless its link is there: then its file is not
    /// even read (a restored backup is not updated by the seed).
    async fn seed_entry(&self, dir: &Path, e: &SeedEntry) -> Result<Seeded, SeedError> {
        if self.ctl.registry().links.contains_key(&e.link) {
            return Ok(Seeded::Skipped);
        }
        let name = plain_name(&e.file)?.to_owned();
        let zip = {
            let dir = dir.to_owned();
            tokio::task::spawn_blocking(move || read_zip(&dir, &name))
                .await
                .map_err(SeedError::Join)??
        };
        let opts = UpdateOpts {
            accept: e.accept,
            ..UpdateOpts::default()
        };
        let source = format!("seed:{}", e.file);
        let message = self
            .install_package(&e.link, zip, source, SEED_SUBJECT, opts)
            .await?;
        Ok(Seeded::Installed(message))
    }
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
    let seed: SeedFile = serde_json::from_slice(&bytes).map_err(SeedError::Parse)?;
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
        max_mib: max >> 20,
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

/// `seed.done` with `links` and the time, written whole or not at all
/// (a new file renamed into place).
fn write_marker(path: &Path, links: &BTreeMap<String, String>) -> Result<(), SeedError> {
    let done = SeedDone {
        time: iso_utc(now_s()),
        links,
    };
    let bytes = serde_json::to_vec_pretty(&done).map_err(SeedError::Encode)?;
    crate::secret::write_private(path, &bytes).map_err(|source| SeedError::Marker {
        path: path.to_owned(),
        source,
    })
}

#[cfg(test)]
mod tests {
    #![allow(
        clippy::unwrap_used,
        reason = "test code: a failed step fails the test"
    )]
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
            Err(SeedError::Parse(_))
        ));
        assert!(matches!(
            read(r#"{"format": "wyrm-seed/1", "links": [{"link": "a", "file": "a.zip", "x": 1}]}"#),
            Err(SeedError::Parse(_))
        ));
        assert!(matches!(
            read(
                r#"{"format": "wyrm-seed/1", "links": [{"link": "a", "file": "a.zip"},
                   {"link": "a", "file": "b.zip"}]}"#
            ),
            Err(SeedError::Duplicate(l)) if l == "a"
        ));
        std::fs::write(d.join(SEED_FILE), vec![b' '; MAX_SEED_FILE + 1]).unwrap();
        assert!(matches!(read_seed(&d), Err(SeedError::TooLarge { .. })));
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
        write_marker(&d.join(SEED_DONE), &links).unwrap();
        let v: serde_json::Value =
            serde_json::from_slice(&std::fs::read(d.join(SEED_DONE)).unwrap()).unwrap();
        assert_eq!(v["links"]["a"], "ok");
        assert_eq!(v["links"]["b"], SKIPPED);
        assert!(v["time"].as_str().unwrap().ends_with('Z'));
    }
}
