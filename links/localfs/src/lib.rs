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
//! **Allowed directories.** A connection's directory must be below one of
//! the link's `allowed_roots` (bootstrap params: only the broker's admin
//! sets them, in `sys/links`; empty = none), may not be under `/proc`,
//! `/sys` or `/dev`, and may not overlap the broker's data directory.
//! Checked on add, edit, start and before every probe.
//!
//! **Bounded calls.** Every file system call runs on the blocking pool
//! with `timeout_ms`: a hung network mount fails the request (and the
//! connection, which probes again) instead of the link. A call that hangs
//! in the kernel keeps its blocking thread until the kernel returns; while
//! one does, the connection's next calls answer `Timeout` at once
//! ([`Gate`]), so one hung mount holds one thread, not one per retry.
//!
//! **Races left.** The checks resolve paths, then act on them: on a shared
//! NFS/SMB mount another writer could swap a folder for a link between the
//! two. Hidden names are never written while they are not shown.
//!
//! Uploads with `overwrite` are written to a hidden temporary file and
//! renamed over the old one (no half-written file is ever seen); without
//! it, the file is created new (`create_new`), so a file made meanwhile is
//! never replaced. `fsync` (default on) syncs the file and its folder:
//! SD cards and power cuts. `read_only` refuses every change.

#![forbid(unsafe_code)]

use bytes::Bytes;
use std::collections::BTreeMap;
use std::collections::HashMap;
use std::collections::VecDeque;
use std::fs;
use std::io::{ErrorKind, Read, Seek, SeekFrom, Write};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU8, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, UNIX_EPOCH};
use tracing::debug;
use wyrm_core::{TypeCode, Value};
use wyrm_filestore::backend::{join, not_empty};
use wyrm_filestore::util::{check_name, fnv64, guess_content_type, now_us};
use wyrm_filestore::{Backend, Entry, Error, FileStore, Limits, Scan};
use wyrm_link_sdk::driver::ParamSpec;
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
    gate: Gate,
    /// What the last place check found (allowed roots, the broker's data
    /// directory), so the probe can check the root again once it exists.
    place: Arc<Mutex<Option<Place>>>,
    /// The root as the last probe resolved and checked it. Every change
    /// resolves the root again and refuses when it moved (a root swapped
    /// for a symlink after the probe).
    pinned: Arc<Mutex<Option<PathBuf>>>,
}

/// The bounds a root must keep, resolved.
#[derive(Debug, Clone)]
struct Place {
    allowed: Vec<PathBuf>,
    broker: Option<PathBuf>,
}

impl Place {
    /// `root` (resolved) is below an allowed root, not a kernel file
    /// system, and does not overlap the broker's data directory.
    fn admits(&self, root: &Path) -> Result<(), Error> {
        if self.allowed.is_empty() {
            return Err(Error::Refused(
                "root: no allowed_roots: the broker's admin lists the directories this link may use in its params".into(),
            ));
        }
        if !self.allowed.iter().any(|a| root.starts_with(a)) {
            return Err(Error::Refused(format!(
                "root: {} is not below one of the link's allowed_roots",
                root.display()
            )));
        }
        if PSEUDO.iter().any(|p| root.starts_with(p)) {
            return Err(Error::Refused(
                "root: a kernel file system (/proc, /sys, /dev)".into(),
            ));
        }
        if let Some(b) = &self.broker {
            if root.starts_with(b) || b.starts_with(root) {
                return Err(Error::Refused(
                    "root: overlaps the broker's data directory (registry, keys, link data)".into(),
                ));
            }
        }
        Ok(())
    }
}

fn lock<T>(m: &Mutex<T>) -> std::sync::MutexGuard<'_, T> {
    m.lock().unwrap_or_else(|e| e.into_inner())
}

/// `p` with every symlink resolved, also when it does not exist yet: the
/// longest existing ancestor resolved, the rest appended. A missing path
/// below a link that leads elsewhere resolves to where the link leads, so
/// it is checked where `create_dir_all` would put it.
pub fn resolve(p: &Path) -> PathBuf {
    let mut rest = Vec::new();
    let mut at = p;
    loop {
        if let Ok(real) = fs::canonicalize(at) {
            let mut out = real;
            for c in rest.iter().rev() {
                out.push(c);
            }
            return out;
        }
        match (at.parent(), at.file_name()) {
            (Some(parent), Some(name)) => {
                rest.push(name.to_owned());
                at = parent;
            }
            _ => return p.to_path_buf(),
        }
    }
}

fn bad(name: &str, what: impl std::fmt::Display) -> LinkError {
    LinkError::invalid_parameter(format!("{name}: {what}"))
}

/// Names Windows refuses (any case, with or without an extension).
const WINDOWS_RESERVED: [&str; 26] = [
    "CON", "PRN", "AUX", "NUL", "CONIN$", "CONOUT$", "COM0", "COM1", "COM2", "COM3", "COM4",
    "COM5", "COM6", "COM7", "COM8", "COM9", "LPT0", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6",
    "LPT7", "LPT8", "LPT9",
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
    // COM¹ … LPT³: Windows reads superscript digits as digits here
    let stem_n: String = stem
        .chars()
        .map(|c| match c {
            '¹' => '1',
            '²' => '2',
            '³' => '3',
            c => c,
        })
        .collect();
    if WINDOWS_RESERVED
        .iter()
        .any(|r| r.eq_ignore_ascii_case(&stem_n))
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

/// File systems that are the kernel's, not data: never a root.
const PSEUDO: [&str; 3] = ["/proc", "/sys", "/dev"];

/// The roots the broker's admin allows (`allowed_roots`, one absolute path
/// per line), resolved.
fn allowed_roots(options: &BTreeMap<String, Value>) -> Vec<PathBuf> {
    let text = match options.get(ALLOWED_ROOTS) {
        Some(Value::Str(s)) => s.as_str(),
        _ => "",
    };
    text.lines()
        .map(str::trim)
        .filter(|l| !l.is_empty())
        .map(PathBuf::from)
        .filter(|p| {
            p.is_absolute()
                && !p
                    .components()
                    .any(|c| matches!(c, std::path::Component::ParentDir))
        })
        .map(|p| resolve(&p))
        .collect()
}

/// The link option that lists the directories connections may use.
pub const ALLOWED_ROOTS: &str = "allowed_roots";

/// Blocking calls on one directory on the shared blocking pool, each under
/// a timeout. A call that times out keeps its thread until the kernel
/// returns; while one does, new calls answer `Timeout` at once, so a hung
/// mount holds at most one thread per directory (and the probe every
/// backoff does not leave one more behind each time). The count is kept
/// per directory for the life of the process ([`Gate::for_root`]): a Stop
/// and Start, or an Edit, does not forget a call that still hangs.
#[derive(Default)]
pub struct Gate {
    stuck: Arc<AtomicUsize>,
}

/// The stuck calls of every directory, by root as given.
static STUCK: std::sync::LazyLock<Mutex<HashMap<PathBuf, Arc<AtomicUsize>>>> =
    std::sync::LazyLock::new(Default::default);

const RUNNING: u8 = 0;
const DONE: u8 = 1;
const ABANDONED: u8 = 2;

impl Gate {
    /// The gate of the directory `root`, shared by every connection on it.
    pub fn for_root(root: &Path) -> Self {
        let stuck = lock(&STUCK).entry(root.to_path_buf()).or_default().clone();
        Self { stuck }
    }

    /// Calls that timed out and still run.
    pub fn stuck(&self) -> usize {
        self.stuck.load(Ordering::Acquire)
    }

    pub async fn run<T: Send + 'static>(
        &self,
        what: &str,
        timeout: Duration,
        f: impl FnOnce() -> Result<T, Error> + Send + 'static,
    ) -> Result<T, Error> {
        if self.stuck() > 0 {
            return Err(Error::Timeout(format!(
                "{what}: an earlier call on this directory still hangs (a hung mount?)"
            )));
        }
        let state = Arc::new(AtomicU8::new(RUNNING));
        let (st, stuck) = (state.clone(), self.stuck.clone());
        let job = tokio::task::spawn_blocking(move || {
            let r = f();
            if st.swap(DONE, Ordering::AcqRel) == ABANDONED {
                stuck.fetch_sub(1, Ordering::AcqRel);
            }
            r
        });
        match tokio::time::timeout(timeout, job).await {
            Err(_) => {
                self.stuck.fetch_add(1, Ordering::AcqRel);
                if state
                    .compare_exchange(RUNNING, ABANDONED, Ordering::AcqRel, Ordering::Acquire)
                    .is_err()
                {
                    // it finished just now
                    self.stuck.fetch_sub(1, Ordering::AcqRel);
                }
                Err(Error::Timeout(format!(
                    "{what}: no answer in {} ms (a hung mount?)",
                    timeout.as_millis()
                )))
            }
            Ok(Err(e)) => Err(Error::Unreachable(format!("{what}: {e}"))),
            Ok(Ok(r)) => r,
        }
    }
}

impl LocalStore {
    /// Run `f` on the blocking pool within the timeout.
    async fn blocking<T: Send + 'static>(
        &self,
        what: &str,
        f: impl FnOnce() -> Result<T, Error> + Send + 'static,
    ) -> Result<T, Error> {
        self.gate.run(what, self.timeout, f).await
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

    /// `dir` resolved and checked to be inside the root, which must still
    /// resolve to where the probe pinned it.
    fn confined(pinned: &Option<PathBuf>, root: &Path, dir: &Path) -> Result<PathBuf, Error> {
        let r = fs::canonicalize(root)
            .map_err(|e| Error::Unreachable(format!("{}: {e}", root.display())))?;
        if pinned.as_deref() != Some(r.as_path()) {
            // the probe checks the place again before it pins the new one
            return Err(Error::Unreachable(format!(
                "{} resolves elsewhere than when it was checked: connecting again",
                root.display()
            )));
        }
        let d = fs::canonicalize(dir).map_err(|e| io_error(e, &dir.display().to_string()))?;
        if !d.starts_with(&r) {
            return Err(Error::Refused(format!(
                "{} leads out of the directory",
                dir.display()
            )));
        }
        Ok(d)
    }

    /// Write `src` as the file `name` in `parent` (see [`Backend::put`]).
    async fn store(
        &self,
        parent: &Entry,
        name: &str,
        src: Src,
        size: u64,
        content_type: &str,
        existing: Option<&Entry>,
    ) -> Result<Entry, Error> {
        self.writable()?;
        self.new_name(name)?;
        let (root, ppath, name_s) = (self.root.clone(), parent.path.clone(), name.to_owned());
        let (overwrite, fsync, ctype) = (existing.is_some(), self.fsync, content_type.to_owned());
        let path = join(&parent.path, name);
        // large files: time to write them too (at 4 MiB/s at least)
        let t = self.timeout + Duration::from_secs(size / (4 * 1024 * 1024));
        let what = format!("upload {path}");
        let w = what.clone();
        let pin = lock(&self.pinned).clone();
        let job = move || -> Result<Entry, Error> {
            let p = LocalStore::host_path(&root, &ppath)?;
            let dir = LocalStore::confined(&pin, &root, &p)?;
            let target = dir.join(&name_s);
            if overwrite {
                let old = match fs::symlink_metadata(&target) {
                    Ok(m) if !m.is_file() => {
                        return Err(Error::Refused(format!("{w}: not a regular file")))
                    }
                    Ok(m) => Some(m),
                    Err(_) => None,
                };
                // a short name nobody can guess: any file name fits beside it,
                // and `create_new` fails rather than take another's file
                let tmp = dir.join(format!(".wyrm-{:016x}.tmp", unguessable(&name_s)));
                // `write_new` removes a temporary file it made and could not
                // finish; one it could not make is not ours
                write_new(&tmp, &src, fsync).map_err(|e| io_error(e, &w))?;
                // the old file's permission bits stay, never setuid, setgid
                // or sticky (owner and xattrs do not stay)
                if let Some(m) = &old {
                    let _ = fs::set_permissions(&tmp, plain_permissions(m));
                }
                if let Err(e) = fs::rename(&tmp, &target) {
                    // ours: made above
                    let _ = fs::remove_file(&tmp);
                    return Err(io_error(e, &w));
                }
            } else {
                write_new(&target, &src, fsync).map_err(|e| io_error(e, &w))?;
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
        };
        self.gate.run(&what, t, job).await
    }

    fn writable(&self) -> Result<(), Error> {
        if self.read_only {
            Err(Error::Refused("read only (read_only)".into()))
        } else {
            Ok(())
        }
    }

    /// A name a change may take: portable, and not hidden unless hidden
    /// names are shown (an upload must not write `.bashrc` or `.ssh`).
    fn new_name(&self, name: &str) -> Result<(), Error> {
        portable_name(name).map_err(|e| Error::Refused(format!("{name}: {e}")))?;
        if !self.show_hidden && name.starts_with('.') {
            return Err(Error::Refused(format!(
                "{name}: hidden names are not shown, so not written (show_hidden)"
            )));
        }
        Ok(())
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

/// What an upload writes: bytes, or a file the link spooled.
enum Src {
    Bytes(Bytes),
    File(PathBuf),
}

/// A value nobody outside this process can predict (std's per-process
/// random hash keys, the time, a counter).
fn unguessable(name: &str) -> u64 {
    use std::hash::{BuildHasher, Hasher};
    static N: AtomicUsize = AtomicUsize::new(0);
    static KEYS: std::sync::LazyLock<std::collections::hash_map::RandomState> =
        std::sync::LazyLock::new(Default::default);
    let mut h = KEYS.build_hasher();
    h.write(name.as_bytes());
    h.write_u64(now_us());
    h.write_usize(N.fetch_add(1, Ordering::Relaxed));
    h.finish() ^ fnv64(name)
}

/// The permissions of `m` without setuid, setgid and sticky bits.
fn plain_permissions(m: &fs::Metadata) -> fs::Permissions {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::Permissions::from_mode(m.permissions().mode() & 0o777)
    }
    #[cfg(not(unix))]
    {
        m.permissions()
    }
}

/// Write `data` to `target`, which must not exist. A file this call made
/// and could not finish is removed; a file someone else made is never
/// touched.
fn write_new(target: &Path, src: &Src, fsync: bool) -> std::io::Result<()> {
    let mut f = fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(target)?;
    // from here the file is ours
    let written = match src {
        Src::Bytes(b) => f.write_all(b),
        // a file received in parts: copied as it is read
        Src::File(p) => {
            fs::File::open(p).and_then(|mut r| std::io::copy(&mut r, &mut f).map(|_| ()))
        }
    }
    .and_then(|()| if fsync { f.sync_all() } else { Ok(()) });
    if written.is_err() {
        drop(f);
        let _ = fs::remove_file(target);
    }
    written
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
            create_root: p.create_root,
            read_only: p.read_only,
            show_hidden: p.show_hidden,
            follow: p.follow_symlinks,
            fsync: p.fsync,
            timeout: Duration::from_millis(p.timeout_ms.into()),
            gate: Gate::for_root(&root),
            root,
            place: Arc::default(),
            pinned: Arc::default(),
        })
    }

    fn timeout(&self) -> Duration {
        self.timeout
    }

    fn link_options() -> Vec<ParamSpec> {
        vec![ParamSpec::new(ALLOWED_ROOTS, TypeCode::String)
            .default("")
            .editor("textarea")
            .display("Allowed Directories")
            .desc("one absolute path per line; a connection's directory must be one of them or below one; empty = none")]
    }

    /// Below an allowed root (set by the broker's admin in the link's
    /// params, never by a connection), not a kernel file system, and not
    /// overlapping the broker's data directory (`<data_dir>/links/<id>/data`
    /// is the link's) in either direction. The root is resolved through
    /// its existing part, on the blocking pool behind the gate.
    async fn check_place(
        &self,
        data_dir: Option<&Path>,
        options: &BTreeMap<String, Value>,
    ) -> Result<(), LinkError> {
        let (root, options, place) = (self.root.clone(), options.clone(), self.place.clone());
        let data_dir = data_dir.map(Path::to_path_buf);
        self.blocking("place check", move || {
            let broker = data_dir.map(|d| {
                let b = match d.ancestors().nth(2) {
                    Some(links) if links.file_name().is_some_and(|n| n == "links") => {
                        links.parent().unwrap_or(links).to_path_buf()
                    }
                    _ => d.clone(),
                };
                resolve(&b)
            });
            let p = Place {
                allowed: allowed_roots(&options),
                broker,
            };
            p.admits(&resolve(&root))?;
            *lock(&place) = Some(p);
            Ok(())
        })
        .await
        .map_err(LinkError::from)
    }

    fn root(&self) -> Entry {
        Entry::root(None)
    }

    async fn check(&self) -> Result<(), Error> {
        let root = self.root.clone();
        let create = self.create_root && !self.read_only;
        let (place, pinned) = (self.place.clone(), self.pinned.clone());
        self.blocking("probe", move || {
            let Some(place) = lock(&place).clone() else {
                return Err(Error::Refused("root: not checked yet".into()));
            };
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
            // where it is now: the place again, then pinned for the changes
            let real = fs::canonicalize(&root)
                .map_err(|e| Error::Unreachable(format!("{}: {e}", root.display())))?;
            place
                .admits(&real)
                .map_err(|e| Error::Auth(e.message().to_owned()))?;
            fs::read_dir(&real).map_err(|e| Error::Auth(format!("{}: {e}", root.display())))?;
            *lock(&pinned) = Some(real);
            Ok(())
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
        self.new_name(name)?;
        let (root, ppath, name_s) = (self.root.clone(), parent.path.clone(), name.to_owned());
        let path = join(&parent.path, name);
        let pin = lock(&self.pinned).clone();
        self.blocking(&format!("create folder {path}"), move || {
            let p = LocalStore::host_path(&root, &ppath)?;
            let p = LocalStore::confined(&pin, &root, &p)?;
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
        let size = data.len() as u64;
        self.store(parent, name, Src::Bytes(data), size, content_type, existing)
            .await
    }

    async fn put_file(
        &self,
        parent: &Entry,
        name: &str,
        src: &Path,
        size: u64,
        content_type: &str,
        existing: Option<&Entry>,
    ) -> Result<Entry, Error> {
        self.store(
            parent,
            name,
            Src::File(src.to_path_buf()),
            size,
            content_type,
            existing,
        )
        .await
    }

    async fn get_range(&self, file: &Entry, offset: u64, len: usize) -> Result<Bytes, Error> {
        let (root, path) = (self.root.clone(), file.path.clone());
        let pin = lock(&self.pinned).clone();
        self.blocking(&format!("download {}", file.path), move || {
            let what = format!("download {path}");
            let p = LocalStore::host_path(&root, &path)?;
            let real = LocalStore::confined(&pin, &root, &p)?;
            let mut f = fs::File::open(&real).map_err(|e| io_error(e, &what))?;
            if !f.metadata().map_err(|e| io_error(e, &what))?.is_file() {
                return Err(Error::Refused(format!("{what}: not a regular file")));
            }
            f.seek(SeekFrom::Start(offset))
                .map_err(|e| io_error(e, &what))?;
            let mut buf = Vec::with_capacity(len);
            f.take(len as u64)
                .read_to_end(&mut buf)
                .map_err(|e| io_error(e, &what))?;
            Ok(Bytes::from(buf))
        })
        .await
    }

    async fn get(&self, file: &Entry, max: usize) -> Result<Bytes, Error> {
        let (root, path) = (self.root.clone(), file.path.clone());
        let pin = lock(&self.pinned).clone();
        self.blocking(&format!("download {}", file.path), move || {
            let what = format!("download {path}");
            let p = LocalStore::host_path(&root, &path)?;
            // the file itself resolved inside the root (a link swapped in
            // for it is refused), then opened by that resolved path
            let real = LocalStore::confined(&pin, &root, &p)?;
            let f = fs::File::open(&real).map_err(|e| io_error(e, &what))?;
            if !f.metadata().map_err(|e| io_error(e, &what))?.is_file() {
                return Err(Error::Refused(format!("{what}: not a regular file")));
            }
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

    async fn delete(&self, e: &Entry, _below: &[Entry], recursive: bool) -> Result<(), Error> {
        self.writable()?;
        if e.path.is_empty() {
            return Err(Error::Refused("the directory itself".into()));
        }
        let (root, path, dir) = (self.root.clone(), e.path.clone(), e.dir);
        let pin = lock(&self.pinned).clone();
        self.blocking(&format!("delete {}", e.path), move || {
            let what = format!("delete {path}");
            let p = LocalStore::host_path(&root, &path)?;
            let parent = p
                .parent()
                .map(Path::to_path_buf)
                .unwrap_or_else(|| root.clone());
            LocalStore::confined(&pin, &root, &parent)?;
            let m = fs::symlink_metadata(&p).map_err(|e| io_error(e, &what))?;
            let r = if m.file_type().is_symlink() {
                // the link, never what it points to
                fs::remove_file(&p).or_else(|_| fs::remove_dir(&p))
            } else if dir && m.is_dir() && recursive {
                // does not follow symbolic links inside
                fs::remove_dir_all(&p)
            } else if dir && m.is_dir() {
                // the file system says whether it is empty, not the tree
                match fs::remove_dir(&p) {
                    Err(e) if e.kind() == ErrorKind::DirectoryNotEmpty => {
                        return Err(not_empty(&path))
                    }
                    r => r,
                }
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
    use wyrm_link_sdk::driver::Params as _;

    #[test]
    fn names() {
        assert!(portable_name("report 2026.csv").is_ok());
        assert!(portable_name("Звіт.pdf").is_ok());
        for bad in [
            "a:b",
            "a?",
            "CON",
            "nul.txt",
            "com1.log",
            "end.",
            "end ",
            "a/b",
            "..",
            "CONIN$",
            "conout$.txt",
            "COM0",
            "lpt0",
            "COM¹",
            "LPT³.log",
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

#[cfg(test)]
mod gate {
    use super::*;

    /// A call that hangs past its timeout holds the gate: the next one is
    /// refused at once; when the first returns, calls go again.
    #[tokio::test(flavor = "multi_thread")]
    async fn a_hung_call_holds_one_thread() {
        let g = Gate::default();
        let (tx, rx) = std::sync::mpsc::channel::<()>();
        let r = g
            .run("first", Duration::from_millis(50), move || {
                let _ = rx.recv();
                Ok(())
            })
            .await;
        assert!(matches!(r, Err(Error::Timeout(_))));
        assert_eq!(g.stuck(), 1);
        let started = std::time::Instant::now();
        let r = g.run("second", Duration::from_secs(5), || Ok(())).await;
        assert!(matches!(r, Err(Error::Timeout(m)) if m.contains("still hangs")));
        assert!(
            started.elapsed() < Duration::from_secs(1),
            "refused at once"
        );
        tx.send(()).unwrap();
        for _ in 0..100 {
            if g.stuck() == 0 {
                break;
            }
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
        assert_eq!(g.stuck(), 0);
        assert!(g
            .run("third", Duration::from_secs(5), || Ok(7))
            .await
            .is_ok());
    }
}
