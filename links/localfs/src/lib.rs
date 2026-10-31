//! Local file system link: one directory of the host per connection — a
//! local disk, a USB stick or SD card, or anything mounted into the file
//! system (NFS, SMB/CIFS, sshfs, a NAS volume, a cloud drive's sync
//! folder). Only `std::fs`: the same code on Linux, macOS, Windows and the
//! BSDs, on x86-64 and ARM edge boards, embedded in `wyrmd` or as a
//! process link (`wyrm-link-localfs`), which may run on another host than
//! the broker and show that host's directory.
//!
//! **Confined to the root.** Paths are built name by name below the root;
//! names are checked (no `/`, `\`, `.` or `..`, nor what Windows refuses:
//! `<>:"|?*`, `CON`, `NUL`, …); before every change the parent folder is
//! resolved (`canonicalize`) and must still be inside the resolved root,
//! so a folder swapped for a symlink cannot lead out. Symbolic links are
//! not shown unless `follow_symlinks`, and then only those that resolve
//! inside the root (a loop is cut by the depth limit).
//!
//! **Bounded calls.** Every file system call runs on the blocking pool
//! with `timeout_ms`: a hung network mount fails the request (and the
//! connection, which probes again) instead of the link. A call that hangs
//! in the kernel keeps its blocking thread until the kernel returns.
//!
//! Uploads with `overwrite` are written to a hidden temporary file and
//! renamed over the old one (no half-written file is ever seen); without
//! it, the file is created new (`create_new`), so a file made meanwhile is
//! never replaced. `fsync` (default on) syncs the file and its folder:
//! SD cards and power cuts. `read_only` refuses every change.

#![forbid(unsafe_code)]

use bytes::Bytes;
use std::collections::VecDeque;
use std::fs;
use std::io::{ErrorKind, Read, Write};
use std::path::{Path, PathBuf};
use std::time::{Duration, UNIX_EPOCH};
use tracing::debug;
use wyrm_filestore::backend::join;
use wyrm_filestore::util::{check_name, fnv64, guess_content_type, now_us};
use wyrm_filestore::{Backend, Entry, Error, FileStore, Limits, Scan};
use wyrm_link_sdk::{LinkError, Params};

/// The `localfs` link.
pub type LocalFs = FileStore<LocalStore>;

/// A connection's params (no secrets: the link's own permissions on the
/// host decide what it may read and write).
#[derive(Debug, Clone, PartialEq, Params)]
pub struct LocalParams {
    #[param(
        display = "Directory",
        placeholder = "/srv/plant/reports",
        desc = "an absolute path of the host: a disk, a USB/SD card, an NFS/SMB mount; Windows: D:\\reports or \\\\nas\\share",
        dest
    )]
    pub root: String,
    #[param(
        default = false,
        display = "Create Directory",
        desc = "create the directory (and its parents) when it is missing"
    )]
    pub create_root: bool,
    #[param(
        default = false,
        display = "Read Only",
        desc = "refuse Create Folder, Upload File and Delete"
    )]
    pub read_only: bool,
    #[param(
        default = false,
        display = "Show Hidden",
        desc = "show names starting with '.'"
    )]
    pub show_hidden: bool,
    #[param(
        default = false,
        display = "Follow Symlinks",
        desc = "show symbolic links that resolve inside the directory; off = links are left out"
    )]
    pub follow_symlinks: bool,
    #[param(
        default = true,
        display = "Sync Writes",
        desc = "fsync each upload and its folder (safe on power loss; slower on SD cards)"
    )]
    pub fsync: bool,
    #[param(
        default = 10000,
        min = 500,
        max = 120000,
        display = "Timeout (ms)",
        desc = "bound on each file system call (a hung network mount)"
    )]
    pub timeout_ms: u32,
}

pub struct LocalStore {
    /// As given (made absolute, not resolved): resolved again on every
    /// probe, so a remount is seen.
    root: PathBuf,
    create_root: bool,
    read_only: bool,
    show_hidden: bool,
    follow: bool,
    fsync: bool,
    timeout: Duration,
}

fn bad(name: &str, what: impl std::fmt::Display) -> LinkError {
    LinkError::invalid_parameter(format!("{name}: {what}"))
}

/// Names Windows refuses (any case, with or without an extension).
const WINDOWS_RESERVED: [&str; 22] = [
    "CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8",
    "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9",
];

/// A name a new file or folder may take on every system this link runs
/// on (so a tree copied to another host stays valid).
pub fn portable_name(name: &str) -> Result<(), String> {
    check_name(name)?;
    if let Some(c) = name.chars().find(|c| "<>:\"|?*".contains(*c)) {
        return Err(format!("character {c:?} is not allowed on Windows"));
    }
    if name.ends_with(['.', ' ']) {
        return Err("no '.' or space at the end (Windows)".into());
    }
    let stem = name.split('.').next().unwrap_or("").trim_end();
    if WINDOWS_RESERVED
        .iter()
        .any(|r| r.eq_ignore_ascii_case(stem))
    {
        return Err(format!("{stem} is a reserved name on Windows"));
    }
    Ok(())
}

fn io_error(e: std::io::Error, what: &str) -> Error {
    let msg = format!("{what}: {e}");
    match e.kind() {
        ErrorKind::NotFound => Error::NotFound(msg),
        ErrorKind::AlreadyExists => Error::Exists(msg),
        ErrorKind::TimedOut | ErrorKind::WouldBlock => Error::Timeout(msg),
        _ => Error::Refused(msg),
    }
}

fn modified(m: &fs::Metadata) -> Option<u64> {
    m.modified()
        .ok()?
        .duration_since(UNIX_EPOCH)
        .ok()
        .map(|d| d.as_micros() as u64)
}

/// A change tag of a file: size and time (no content hash: that would read
/// every file on every refresh).
fn tag(m: &fs::Metadata) -> String {
    format!("{:x}-{:x}", m.len(), modified(m).unwrap_or(0))
}

impl LocalStore {
    /// Run `f` on the blocking pool within the timeout.
    async fn blocking<T: Send + 'static>(
        &self,
        what: &str,
        f: impl FnOnce() -> Result<T, Error> + Send + 'static,
    ) -> Result<T, Error> {
        match tokio::time::timeout(self.timeout, tokio::task::spawn_blocking(f)).await {
            Err(_) => Err(Error::Timeout(format!(
                "{what}: no answer in {} ms (a hung mount?)",
                self.timeout.as_millis()
            ))),
            Ok(Err(e)) => Err(Error::Unreachable(format!("{what}: {e}"))),
            Ok(Ok(r)) => r,
        }
    }

    /// The host path of a tree path: the root, then one name per segment.
    fn host_path(root: &Path, path: &str) -> Result<PathBuf, Error> {
        let mut p = root.to_path_buf();
        if path.is_empty() {
            return Ok(p);
        }
        for seg in path.split('/') {
            check_name(seg).map_err(|e| Error::Refused(format!("{path}: {e}")))?;
            p.push(seg);
        }
        Ok(p)
    }

    /// The resolved root, and `dir` resolved and checked to be inside it.
    fn confined(root: &Path, dir: &Path) -> Result<PathBuf, Error> {
        let r = fs::canonicalize(root)
            .map_err(|e| Error::Unreachable(format!("{}: {e}", root.display())))?;
        let d = fs::canonicalize(dir).map_err(|e| io_error(e, &dir.display().to_string()))?;
        if !d.starts_with(&r) {
            return Err(Error::Refused(format!(
                "{} leads out of the directory",
                dir.display()
            )));
        }
        Ok(d)
    }

    fn writable(&self) -> Result<(), Error> {
        if self.read_only {
            Err(Error::Refused("read only (read_only)".into()))
        } else {
            Ok(())
        }
    }
}

/// One folder read: its children as entries, folders to read next.
fn read_folder(
    root: &Path,
    resolved_root: &Path,
    path: &str,
    show_hidden: bool,
    follow: bool,
) -> Result<Vec<Entry>, Error> {
    let dir = LocalStore::host_path(root, path)?;
    let rd = fs::read_dir(&dir).map_err(|e| io_error(e, &format!("read /{path}")))?;
    let mut out = Vec::new();
    for item in rd {
        let Ok(item) = item else { continue };
        let Ok(name) = item.file_name().into_string() else {
            debug!(folder = %path, "a name that is not UTF-8 is left out");
            continue;
        };
        if (!show_hidden && name.starts_with('.')) || check_name(&name).is_err() {
            continue;
        }
        let Ok(mut meta) = fs::symlink_metadata(item.path()) else {
            continue; // gone meanwhile
        };
        if meta.file_type().is_symlink() {
            if !follow {
                continue;
            }
            match fs::canonicalize(item.path()) {
                Ok(t) if t.starts_with(resolved_root) => match fs::metadata(&t) {
                    Ok(m) => meta = m,
                    Err(_) => continue,
                },
                _ => continue, // dangling, or outside the root
            }
        }
        let p = join(path, &name);
        let e = if meta.is_dir() {
            let mut e = Entry::dir(p);
            e.modified = modified(&meta);
            e
        } else if meta.is_file() {
            let mut e = Entry::file(p, meta.len());
            e.modified = modified(&meta);
            e.etag = Some(tag(&meta));
            e.content_type = Some(guess_content_type(&name).to_owned());
            e
        } else {
            continue; // sockets, devices, FIFOs
        };
        out.push(e);
    }
    out.sort_by(|a, b| a.path.cmp(&b.path));
    Ok(out)
}

impl Backend for LocalStore {
    const NAME: &'static str = "localfs";
    const VERSION: &'static str = env!("CARGO_PKG_VERSION");
    const DISPLAY: &'static str = "Local Directory";
    type Params = LocalParams;

    fn new(p: &LocalParams) -> Result<Self, LinkError> {
        let raw = p.root.trim();
        if raw.is_empty() {
            return Err(bad("root", "required"));
        }
        let root = PathBuf::from(raw);
        if !root.is_absolute() {
            return Err(bad("root", "an absolute path"));
        }
        if root
            .components()
            .any(|c| matches!(c, std::path::Component::ParentDir))
        {
            return Err(bad("root", "no '..'"));
        }
        Ok(Self {
            root,
            create_root: p.create_root,
            read_only: p.read_only,
            show_hidden: p.show_hidden,
            follow: p.follow_symlinks,
            fsync: p.fsync,
            timeout: Duration::from_millis(p.timeout_ms.into()),
        })
    }

    fn timeout(&self) -> Duration {
        self.timeout
    }

    /// The broker's data directory (`<data_dir>/links/<id>/data` is the
    /// link's) is off limits, and so is every directory that holds it.
    fn check_place(&self, data_dir: Option<&Path>) -> Result<(), LinkError> {
        let Some(d) = data_dir else { return Ok(()) };
        let broker = match d.ancestors().nth(2) {
            Some(links) if links.file_name().is_some_and(|n| n == "links") => {
                links.parent().unwrap_or(links)
            }
            _ => d,
        };
        let resolve = |p: &Path| fs::canonicalize(p).unwrap_or_else(|_| p.to_path_buf());
        let (root, broker) = (resolve(&self.root), resolve(broker));
        if root.starts_with(&broker) || broker.starts_with(&root) {
            return Err(bad(
                "root",
                "overlaps the broker's data directory (registry, keys, link data)",
            ));
        }
        Ok(())
    }

    fn root(&self) -> Entry {
        Entry::root(None)
    }

    async fn check(&self) -> Result<(), Error> {
        let root = self.root.clone();
        let create = self.create_root && !self.read_only;
        self.blocking("probe", move || {
            if create && !root.exists() {
                fs::create_dir_all(&root)
                    .map_err(|e| Error::Unreachable(format!("create {}: {e}", root.display())))?;
            }
            let m = fs::metadata(&root)
                .map_err(|e| Error::Unreachable(format!("{}: {e}", root.display())))?;
            if !m.is_dir() {
                return Err(Error::Unreachable(format!(
                    "{} is not a directory",
                    root.display()
                )));
            }
            fs::read_dir(&root)
                .map(|_| ())
                .map_err(|e| Error::Auth(format!("{}: {e}", root.display())))
        })
        .await
    }

    async fn scan(&self, dir: &Entry, limits: Limits) -> Result<Scan, Error> {
        let root = self.root.clone();
        let resolved = self
            .blocking("probe", move || {
                fs::canonicalize(&root)
                    .map_err(|e| Error::Unreachable(format!("{}: {e}", root.display())))
            })
            .await?;
        let mut scan = Scan::default();
        let mut queue = VecDeque::from([(dir.path.clone(), 0usize)]);
        while let Some((path, depth)) = queue.pop_front() {
            let (root, res, p) = (self.root.clone(), resolved.clone(), path.clone());
            let (hidden, follow) = (self.show_hidden, self.follow);
            let found = self
                .blocking(&format!("read /{path}"), move || {
                    read_folder(&root, &res, &p, hidden, follow)
                })
                .await;
            let found = match found {
                Ok(f) => f,
                // the root gone (unmounted, removed): the connection fails
                Err(e) if path == dir.path => {
                    return Err(match e {
                        Error::NotFound(m) => Error::Unreachable(m),
                        other => other,
                    })
                }
                // a timeout below: the mount hangs
                Err(e @ Error::Timeout(_)) => return Err(e),
                // a folder we may not read, or one gone meanwhile
                Err(e) => {
                    debug!("{e}");
                    scan.truncated = true;
                    continue;
                }
            };
            for e in found {
                if scan.entries.len() >= limits.max_entries {
                    scan.truncated = true;
                    return Ok(scan);
                }
                if e.dir {
                    if depth + 1 < limits.max_depth {
                        queue.push_back((e.path.clone(), depth + 1));
                    } else {
                        scan.truncated = true;
                    }
                }
                scan.entries.push(e);
            }
        }
        Ok(scan)
    }

    async fn mkdir(&self, parent: &Entry, name: &str) -> Result<Entry, Error> {
        self.writable()?;
        portable_name(name).map_err(|e| Error::Refused(format!("{name}: {e}")))?;
        let (root, ppath, name_s) = (self.root.clone(), parent.path.clone(), name.to_owned());
        let path = join(&parent.path, name);
        self.blocking(&format!("create folder {path}"), move || {
            let p = LocalStore::host_path(&root, &ppath)?;
            let p = LocalStore::confined(&root, &p)?;
            let target = p.join(&name_s);
            fs::create_dir(&target)
                .map_err(|e| io_error(e, &format!("create folder {}", join(&ppath, &name_s))))?;
            let mut e = Entry::dir(join(&ppath, &name_s));
            e.modified = fs::metadata(&target).ok().as_ref().and_then(modified);
            Ok(e)
        })
        .await
    }

    async fn put(
        &self,
        parent: &Entry,
        name: &str,
        data: Bytes,
        content_type: &str,
        existing: Option<&Entry>,
    ) -> Result<Entry, Error> {
        self.writable()?;
        portable_name(name).map_err(|e| Error::Refused(format!("{name}: {e}")))?;
        let (root, ppath, name_s) = (self.root.clone(), parent.path.clone(), name.to_owned());
        let (overwrite, fsync, ctype) = (existing.is_some(), self.fsync, content_type.to_owned());
        let path = join(&parent.path, name);
        // large files: time to write them too (at 4 MiB/s at least)
        let t = self.timeout + Duration::from_secs(data.len() as u64 / (4 * 1024 * 1024));
        let what = format!("upload {path}");
        let w = what.clone();
        let job = tokio::task::spawn_blocking(move || -> Result<Entry, Error> {
            let p = LocalStore::host_path(&root, &ppath)?;
            let dir = LocalStore::confined(&root, &p)?;
            let target = dir.join(&name_s);
            if overwrite {
                if fs::symlink_metadata(&target).is_ok_and(|m| !m.is_file()) {
                    return Err(Error::Refused(format!("{w}: not a regular file")));
                }
                let tmp = dir.join(format!(
                    ".{}.wyrm-{:08x}.tmp",
                    name_s,
                    fnv64(&format!("{name_s}{}", now_us())) as u32
                ));
                let written = (|| {
                    let mut f = fs::OpenOptions::new()
                        .write(true)
                        .create_new(true)
                        .open(&tmp)?;
                    f.write_all(&data)?;
                    if fsync {
                        f.sync_all()?;
                    }
                    drop(f);
                    fs::rename(&tmp, &target)
                })();
                if let Err(e) = written {
                    let _ = fs::remove_file(&tmp);
                    return Err(io_error(e, &w));
                }
            } else {
                let written = (|| {
                    let mut f = fs::OpenOptions::new()
                        .write(true)
                        .create_new(true)
                        .open(&target)?;
                    f.write_all(&data)?;
                    if fsync {
                        f.sync_all()?;
                    }
                    Ok::<_, std::io::Error>(())
                })();
                if let Err(e) = written {
                    if e.kind() != ErrorKind::AlreadyExists {
                        // a partial file of ours must not stay
                        let _ = fs::remove_file(&target);
                    }
                    return Err(io_error(e, &w));
                }
            }
            if fsync {
                // the folder entry too (not possible on every system)
                if let Ok(d) = fs::File::open(&dir) {
                    let _ = d.sync_all();
                }
            }
            let m = fs::metadata(&target).map_err(|e| io_error(e, &w))?;
            let mut e = Entry::file(join(&ppath, &name_s), m.len());
            e.modified = modified(&m);
            e.etag = Some(tag(&m));
            e.content_type = Some(ctype);
            Ok(e)
        });
        match tokio::time::timeout(t, job).await {
            Err(_) => Err(Error::Timeout(format!(
                "{what}: no answer in {} ms (a hung mount?)",
                t.as_millis()
            ))),
            Ok(Err(e)) => Err(Error::Unreachable(format!("{what}: {e}"))),
            Ok(Ok(r)) => r,
        }
    }

    async fn get(&self, file: &Entry, max: usize) -> Result<Bytes, Error> {
        let (root, path) = (self.root.clone(), file.path.clone());
        self.blocking(&format!("download {}", file.path), move || {
            let p = LocalStore::host_path(&root, &path)?;
            let parent = p
                .parent()
                .map(Path::to_path_buf)
                .unwrap_or_else(|| root.clone());
            LocalStore::confined(&root, &parent)?;
            let what = format!("download {path}");
            let m = fs::symlink_metadata(&p).map_err(|e| io_error(e, &what))?;
            if m.file_type().is_symlink() {
                // only links inside the root (shown with follow_symlinks)
                LocalStore::confined(&root, &p)?;
            }
            let f = fs::File::open(&p).map_err(|e| io_error(e, &what))?;
            let mut buf = Vec::new();
            f.take(max as u64 + 1)
                .read_to_end(&mut buf)
                .map_err(|e| io_error(e, &what))?;
            if buf.len() > max {
                return Err(Error::TooLarge(format!("{what}: more than {max} bytes")));
            }
            Ok(Bytes::from(buf))
        })
        .await
    }

    async fn delete(&self, e: &Entry, _below: &[Entry]) -> Result<(), Error> {
        self.writable()?;
        if e.path.is_empty() {
            return Err(Error::Refused("the directory itself".into()));
        }
        let (root, path, dir) = (self.root.clone(), e.path.clone(), e.dir);
        self.blocking(&format!("delete {}", e.path), move || {
            let what = format!("delete {path}");
            let p = LocalStore::host_path(&root, &path)?;
            let parent = p
                .parent()
                .map(Path::to_path_buf)
                .unwrap_or_else(|| root.clone());
            LocalStore::confined(&root, &parent)?;
            let m = fs::symlink_metadata(&p).map_err(|e| io_error(e, &what))?;
            let r = if m.file_type().is_symlink() {
                // the link, never what it points to
                fs::remove_file(&p).or_else(|_| fs::remove_dir(&p))
            } else if dir && m.is_dir() {
                // does not follow symbolic links inside
                fs::remove_dir_all(&p)
            } else if !dir && m.is_file() {
                fs::remove_file(&p)
            } else {
                return Err(Error::Refused(format!("{what}: changed type meanwhile")));
            };
            match r {
                Ok(()) => Ok(()),
                Err(e) if e.kind() == ErrorKind::NotFound => Ok(()),
                Err(e) => Err(io_error(e, &what)),
            }
        })
        .await
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use wyrm_core::Value;
    use wyrm_link_sdk::driver::Params as _;

    #[test]
    fn names() {
        assert!(portable_name("report 2026.csv").is_ok());
        assert!(portable_name("Звіт.pdf").is_ok());
        for bad in [
            "a:b", "a?", "CON", "nul.txt", "com1.log", "end.", "end ", "a/b", "..",
        ] {
            assert!(portable_name(bad).is_err(), "{bad}");
        }
    }

    #[test]
    fn params() {
        let p = |root: &str| {
            let m = [("root".to_owned(), Value::Str(root.into()))].into();
            LocalStore::new(&LocalParams::from_value(&Value::Map(m)).unwrap())
        };
        assert!(p("relative/dir").is_err());
        assert!(p("").is_err());
        let abs = std::env::temp_dir();
        assert!(p(abs.to_str().unwrap()).is_ok());
        let up = abs.join("..").join("x");
        assert!(p(up.to_str().unwrap()).is_err());
    }
}
