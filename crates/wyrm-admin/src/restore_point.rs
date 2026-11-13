//! Restore points of links (ADR 0048 §1.3): a copy of a link's private
//! data directory (`data_dir/links/<id>/data`) and its key list, taken
//! before a package update stops the link, under
//! `data_dir/restore/<link>/<UTC>.{restore,meta}`.
//!
//! [`make`] writes one, [`apply`] puts one back, [`list`] and [`prune`]
//! keep the directory. The archive itself goes through two functions only,
//! [`write_archive`] and [`read_archive`]: **the seam** for the link backup
//! (`.wyrm-link`, ADR 0048 §3.5). Until that format is merged they hold a
//! provisional one: a zip of the directory, sealed as a whole with a key
//! derived from `secrets.key` ([`key`]). What a link sealed with its own
//! store key stays sealed inside; nothing is ever written in clear.

use minicbor::{Decode, Encode};
use sha2::Digest;
use std::fs::File;
use std::io::{Cursor, Read, Write};
use std::path::{Path, PathBuf};

/// Largest private data a restore point holds (the provisional archive is
/// built in memory).
pub const MAX_BYTES: u64 = 128 << 20;
/// Most files of one restore point.
pub const MAX_FILES: usize = 10_000;
/// Extension of the sealed archive.
const ARCHIVE: &str = "restore";
/// Extension of the description beside it.
const META: &str = "meta";

/// One restore point of a link, as its `.meta` file (CBOR) says.
#[derive(Debug, Clone, PartialEq, Eq, Encode, Decode)]
pub struct Point {
    /// Its name in the link's directory: `<UTC>` (`20261113T101502Z`).
    #[n(0)]
    pub id: String,
    /// Unix seconds.
    #[n(1)]
    pub at: u64,
    /// The package the link ran.
    #[n(2)]
    pub package: String,
    /// The version it ran.
    #[n(3)]
    pub version: String,
    /// Bytes of the archive.
    #[n(4)]
    pub size: u64,
    /// The link's keys then (`~meta?view=keys` of its root); empty with
    /// `keys_known: false` when the link did not answer.
    #[n(5)]
    pub keys: Vec<String>,
    #[n(6)]
    pub keys_known: bool,
    /// Entries of the data directory that were not copied: neither a
    /// regular file nor a directory (a symlink, a socket, a FIFO).
    #[n(7)]
    #[cbor(default)]
    pub skipped: u32,
}

/// The key restore points are sealed with: derived from `secrets.key`, so
/// whoever reads a restore point without the broker's keys reads nothing.
pub fn key(secrets_key: &[u8]) -> [u8; 32] {
    let mut h = sha2::Sha256::new();
    h.update(b"wyrm-restore-points");
    h.update(secrets_key);
    h.finalize().into()
}

/// `secs` since the epoch as a file name: `20261113T101502Z`.
pub fn stamp(secs: u64) -> String {
    let (y, m, d) = crate::secret::civil_from_days((secs / 86_400) as i64);
    let t = secs % 86_400;
    format!(
        "{y:04}{m:02}{d:02}T{:02}{:02}{:02}Z",
        t / 3600,
        t % 3600 / 60,
        t % 60
    )
}

/// A directory entry that is scratch (a spool, a temp file, a lock): not
/// part of a restore point, as it is not replicated to a standby.
fn scratch(name: &str) -> bool {
    name.ends_with(".tmp")
        || name.starts_with(".tmp")
        || name == "tmp"
        || name == "uploads"
        || name == "LOCK"
}

/// Open `path` for reading without following a symlink in its last
/// component, and without waiting on a FIFO. `dir`: it must be a directory.
#[cfg(unix)]
fn open_nofollow(path: &Path, dir: bool) -> std::io::Result<File> {
    use nix::fcntl::OFlag;
    use std::os::unix::fs::OpenOptionsExt;
    let mut flags = OFlag::O_NOFOLLOW | OFlag::O_NONBLOCK | OFlag::O_CLOEXEC;
    if dir {
        flags |= OFlag::O_DIRECTORY;
    }
    std::fs::OpenOptions::new()
        .read(true)
        .custom_flags(flags.bits())
        .open(path)
}

#[cfg(not(unix))]
fn open_nofollow(path: &Path, _dir: bool) -> std::io::Result<File> {
    let mut o = std::fs::OpenOptions::new();
    o.read(true);
    #[cfg(windows)]
    {
        use std::os::windows::fs::OpenOptionsExt;
        // FILE_FLAG_OPEN_REPARSE_POINT | FILE_FLAG_BACKUP_SEMANTICS: the
        // link itself, never its target; directories open too
        o.custom_flags(0x0020_0000 | 0x0200_0000);
    }
    o.open(path)
}

/// Is the entry `name` of the open directory `parent` the very object
/// `meta` was read from (same device and inode, not followed)? A path is
/// resolved again at every use, so a directory on the way may have been
/// swapped for a symlink since the walk entered it: the held handle of the
/// parent is what cannot be swapped.
#[cfg(unix)]
// the widths of `st_dev` and `st_ino` differ between unix targets
#[allow(clippy::unnecessary_cast)]
fn same_entry(parent: &File, name: &std::ffi::OsStr, meta: &std::fs::Metadata) -> bool {
    use std::os::unix::fs::MetadataExt;
    use std::os::unix::io::AsRawFd;
    match nix::sys::stat::fstatat(
        Some(parent.as_raw_fd()),
        name,
        nix::fcntl::AtFlags::AT_SYMLINK_NOFOLLOW,
    ) {
        Ok(st) => st.st_dev as u64 == meta.dev() && st.st_ino as u64 == meta.ino(),
        Err(_) => false,
    }
}

#[cfg(not(unix))]
fn same_entry(_: &File, _: &std::ffi::OsStr, _: &std::fs::Metadata) -> bool {
    true
}

/// One entry of a directory of the link's data, opened once.
struct Entry {
    file: File,
    /// From the handle, never from the path.
    meta: std::fs::Metadata,
}

/// Open the entry `name` of the directory `parent` (at `parent_path`),
/// which the listing said is a directory (`dir`) or a regular file. The
/// link runs while its data is copied and owns this directory, so nothing
/// read from a path is trusted: the entry is opened once without following
/// a symlink, its type and size come from that handle, and it must be the
/// entry of that name in the held parent. `Ok(None)`: it went away.
/// Anything else that is not what the listing said (a file swapped for a
/// symlink, a directory swapped on the way) is refused.
fn open_entry(
    parent: &File,
    parent_path: &Path,
    name: &std::ffi::OsStr,
    dir: bool,
) -> Result<Option<Entry>, String> {
    let path = parent_path.join(name);
    let refused = |why: &str| {
        format!(
            "{}: {why}; the link's data changed while it was copied",
            path.display()
        )
    };
    let file = match open_nofollow(&path, dir) {
        Ok(f) => f,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(e) => {
            return Err(refused(&format!(
                "not opened without following links ({e})"
            )))
        }
    };
    let meta = file.metadata().map_err(|e| refused(&e.to_string()))?;
    let kind = meta.file_type();
    if kind.is_symlink() || (dir && !kind.is_dir()) || (!dir && !kind.is_file()) {
        return Err(refused("not the file or directory that was listed"));
    }
    if !same_entry(parent, name, &meta) {
        return Err(refused("not an entry of the directory that was listed"));
    }
    Ok(Some(Entry { file, meta }))
}

/// What a walk of the link's data found beside what it copied.
#[derive(Debug, Default)]
struct Walked {
    files: usize,
    /// Entries that are neither a regular file nor a directory (symlinks,
    /// sockets, FIFOs, devices): never opened, never copied.
    skipped: u32,
}

/// Every regular file under the open directory `dir` (at `path`), in name
/// order, handed to `emit` as `(relative path, open handle, its metadata)`.
/// Scratch names are left out; what is not a file or directory is counted.
fn walk(
    dir: &File,
    path: &Path,
    rel: &str,
    seen: &mut Walked,
    emit: &mut dyn FnMut(&str, File, &std::fs::Metadata) -> Result<(), String>,
) -> Result<(), String> {
    let rd = std::fs::read_dir(path).map_err(|e| format!("{}: {e}", path.display()))?;
    let mut entries: Vec<_> = rd.flatten().collect();
    entries.sort_by_key(|e| e.file_name());
    for e in entries {
        let os_name = e.file_name();
        let name = os_name.to_string_lossy().into_owned();
        if scratch(&name) {
            continue;
        }
        // the listing's own type (not followed) says how to open it
        let is_dir = match e.file_type() {
            Ok(t) if t.is_dir() => true,
            Ok(t) if t.is_file() => false,
            // a symlink, a socket, a FIFO, a device: not the link's data
            Ok(_) => {
                seen.skipped += 1;
                continue;
            }
            Err(x) if x.kind() == std::io::ErrorKind::NotFound => continue,
            Err(x) => return Err(format!("{}: {x}", e.path().display())),
        };
        let Some(entry) = open_entry(dir, path, &os_name, is_dir)? else {
            continue;
        };
        let child = if rel.is_empty() {
            name
        } else {
            format!("{rel}/{name}")
        };
        if is_dir {
            walk(&entry.file, &path.join(&os_name), &child, seen, emit)?;
        } else {
            seen.files += 1;
            if seen.files > MAX_FILES {
                return Err(format!("more than {MAX_FILES} files"));
            }
            emit(&child, entry.file, &entry.meta)?;
        }
    }
    Ok(())
}

#[cfg(unix)]
fn mode_of(m: &std::fs::Metadata) -> u32 {
    use std::os::unix::fs::PermissionsExt;
    m.permissions().mode() & 0o777
}

#[cfg(not(unix))]
fn mode_of(_: &std::fs::Metadata) -> u32 {
    0o600
}

/// SEAM (write side): the private data directory `data` as one sealed file
/// `out`; returns its size and how many entries were skipped (not a file,
/// not a directory). Provisional format, to be replaced by the `.wyrm-link`
/// writer of ADR 0048 §3.5 (sections `data` without history).
///
/// The link is running (ADR 0048 §1.3: before anything stops) and owns the
/// directory: every entry is opened once without following symlinks and
/// read from that handle ([`open_entry`]), so the copy never leaves `data`.
fn write_archive(data: &Path, out: &Path, key: &[u8; 32]) -> Result<(u64, u32), String> {
    use zip::write::SimpleFileOptions;
    let mut w = zip::ZipWriter::new(Cursor::new(Vec::new()));
    let mut total = 0u64;
    let mut seen = Walked::default();
    match open_nofollow(data, true) {
        Ok(root) => {
            let kind = root
                .metadata()
                .map_err(|e| format!("{}: {e}", data.display()))?
                .file_type();
            if kind.is_symlink() || !kind.is_dir() {
                return Err(format!("{}: not a directory", data.display()));
            }
            let mut emit = |rel: &str, file: File, meta: &std::fs::Metadata| {
                let left = MAX_BYTES - total;
                let mut bytes = Vec::new();
                // one byte past the budget tells "fits" from "too big",
                // whatever size the file says it has
                file.take(left + 1)
                    .read_to_end(&mut bytes)
                    .map_err(|e| format!("{rel}: {e}"))?;
                if bytes.len() as u64 > left {
                    return Err(format!(
                        "the link's private data is over {} MiB",
                        MAX_BYTES >> 20
                    ));
                }
                total += bytes.len() as u64;
                // stored: what a link keeps is sealed already and does not compress
                let opt = SimpleFileOptions::default()
                    .compression_method(zip::CompressionMethod::Stored)
                    .unix_permissions(mode_of(meta));
                w.start_file(rel, opt).map_err(|e| format!("{rel}: {e}"))?;
                w.write_all(&bytes).map_err(|e| format!("{rel}: {e}"))
            };
            walk(&root, data, "", &mut seen, &mut emit)?;
        }
        // no directory yet: an empty restore point
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
        Err(e) => {
            return Err(format!(
                "{}: not opened without following links ({e})",
                data.display()
            ))
        }
    }
    let plain = w.finish().map_err(|e| e.to_string())?.into_inner();
    let sealed = wyrm_link_sdk::seal::seal(key, &plain);
    crate::secret::write_private(out, &sealed).map_err(|e| format!("{}: {e}", out.display()))?;
    Ok((sealed.len() as u64, seen.skipped))
}

/// A new file `path` (it must not exist, and a symlink there is not
/// followed) with `bytes`, readable by its owner (`mode` on unix).
fn write_new(path: &Path, bytes: &[u8], mode: Option<u32>) -> std::io::Result<()> {
    let mut o = std::fs::OpenOptions::new();
    o.write(true).create_new(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        o.mode(mode.map_or(0o600, |m| m & 0o777))
            .custom_flags(nix::fcntl::OFlag::O_NOFOLLOW.bits());
    }
    #[cfg(not(unix))]
    let _ = mode;
    let mut f = o.open(path)?;
    f.write_all(bytes)?;
    f.sync_all()
}

/// The directories of `rel` under `root`, made one by one: one that is
/// there must be a real directory (never a symlink to follow).
fn make_dirs(root: &Path, rel: &Path) -> Result<PathBuf, String> {
    let mut dir = root.to_path_buf();
    for c in rel.components() {
        let std::path::Component::Normal(c) = c else {
            return Err(format!("unsafe path {}", rel.display()));
        };
        dir.push(c);
        match std::fs::create_dir(&dir) {
            Ok(()) => {}
            Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => {
                let real = std::fs::symlink_metadata(&dir).is_ok_and(|m| m.is_dir());
                if !real {
                    return Err(format!("{}: not a directory", dir.display()));
                }
            }
            Err(e) => return Err(format!("{}: {e}", dir.display())),
        }
    }
    Ok(dir)
}

/// SEAM (read side): unpack what [`write_archive`] made into the new, empty
/// directory `data` (made by the caller, swapped into place afterwards).
/// Provisional format, as [`write_archive`]. Every file is created new and
/// no symlink is followed, so nothing is written outside `data`.
fn read_archive(file: &Path, data: &Path, key: &[u8; 32]) -> Result<(), String> {
    let sealed = std::fs::read(file).map_err(|e| format!("{}: {e}", file.display()))?;
    let plain = wyrm_link_sdk::seal::open(key, &sealed)
        .ok_or("the restore point does not open with this broker's keys")?;
    let mut archive =
        zip::ZipArchive::new(Cursor::new(plain)).map_err(|e| format!("restore point: {e}"))?;
    if archive.len() > MAX_FILES {
        return Err(format!("more than {MAX_FILES} files"));
    }
    let mut total = 0u64;
    for i in 0..archive.len() {
        let mut f = archive
            .by_index(i)
            .map_err(|e| format!("restore point: {e}"))?;
        let rel = f
            .enclosed_name()
            .ok_or_else(|| format!("unsafe path {:?}", f.name()))?;
        if f.is_symlink() || !f.is_file() {
            return Err(format!("{}: not a regular file", rel.display()));
        }
        let name = rel
            .file_name()
            .ok_or_else(|| format!("unsafe path {}", rel.display()))?
            .to_owned();
        let dir = make_dirs(data, rel.parent().unwrap_or(Path::new("")))?;
        let mode = f.unix_mode();
        let mut bytes = Vec::new();
        (&mut f)
            .take(MAX_BYTES - total + 1)
            .read_to_end(&mut bytes)
            .map_err(|e| format!("{}: {e}", rel.display()))?;
        total += bytes.len() as u64;
        if total > MAX_BYTES {
            return Err(format!("restore point over {} MiB", MAX_BYTES >> 20));
        }
        write_new(&dir.join(name), &bytes, mode).map_err(|e| format!("{}: {e}", rel.display()))?;
    }
    Ok(())
}

/// A directory only its owner enters.
fn private_dir(dir: &Path) -> Result<(), String> {
    let mut b = std::fs::DirBuilder::new();
    b.recursive(true);
    #[cfg(unix)]
    std::os::unix::fs::DirBuilderExt::mode(&mut b, 0o700);
    b.create(dir).map_err(|e| format!("{}: {e}", dir.display()))
}

/// A new directory only its owner enters: refused when the name is taken.
fn new_private_dir(dir: &Path) -> Result<(), String> {
    let mut b = std::fs::DirBuilder::new();
    #[cfg(unix)]
    std::os::unix::fs::DirBuilderExt::mode(&mut b, 0o700);
    b.create(dir).map_err(|e| format!("{}: {e}", dir.display()))
}

fn link_dir(root: &Path, link: &str) -> Result<PathBuf, String> {
    crate::registry::validate_link_id(link)?;
    Ok(root.join(link))
}

/// Take a restore point of `link` now: its private data `data` (a missing
/// directory is an empty one) and its `keys` (`None`: the link did not
/// answer). Nothing of the link is touched. `root` is `data_dir/restore`.
#[allow(clippy::too_many_arguments)]
pub fn make(
    root: &Path,
    link: &str,
    data: &Path,
    key: &[u8; 32],
    package: &str,
    version: &str,
    keys: Option<Vec<String>>,
    now: u64,
) -> Result<Point, String> {
    let dir = link_dir(root, link)?;
    private_dir(&dir)?;
    // two points in one second: the later one gets a suffix
    let mut id = stamp(now);
    let mut n = 1;
    while dir.join(format!("{id}.{META}")).exists() || dir.join(format!("{id}.{ARCHIVE}")).exists()
    {
        n += 1;
        id = format!("{}-{n}", stamp(now));
    }
    let archive = dir.join(format!("{id}.{ARCHIVE}"));
    let (size, skipped) = write_archive(data, &archive, key)?;
    let point = Point {
        id: id.clone(),
        at: now,
        package: package.to_owned(),
        version: version.to_owned(),
        size,
        skipped,
        keys_known: keys.is_some(),
        keys: keys.unwrap_or_default(),
    };
    // the description last: a point without it is not listed
    let meta = minicbor::to_vec(&point).map_err(|e| e.to_string())?;
    if let Err(e) = crate::secret::write_private(&dir.join(format!("{id}.{META}")), &meta) {
        let _ = std::fs::remove_file(&archive);
        return Err(format!("restore point {id}: {e}"));
    }
    Ok(point)
}

/// Put the restore point `id` of `link` back as its private data directory
/// `data`: what is there now is replaced as a whole (in two renames; on a
/// failure the directory stays as it was). The link must not run.
pub fn apply(root: &Path, link: &str, id: &str, data: &Path, key: &[u8; 32]) -> Result<(), String> {
    let dir = link_dir(root, link)?;
    if id.is_empty() || id.contains(['/', '\\', '.']) {
        return Err(format!("restore point {id:?}"));
    }
    let archive = dir.join(format!("{id}.{ARCHIVE}"));
    let parent = data
        .parent()
        .ok_or_else(|| format!("{}: no parent", data.display()))?;
    let fresh = parent.join("data.restoring");
    let old = parent.join("data.replaced");
    // left by an apply that was cut: removed as what they are (a symlink
    // planted under these names is unlinked, never followed)
    for stale in [&fresh, &old] {
        match std::fs::symlink_metadata(stale) {
            Ok(m) if m.is_dir() => {
                let _ = std::fs::remove_dir_all(stale);
            }
            Ok(_) => {
                let _ = std::fs::remove_file(stale);
            }
            Err(_) => {}
        }
    }
    new_private_dir(&fresh)?;
    if let Err(e) = read_archive(&archive, &fresh, key) {
        let _ = std::fs::remove_dir_all(&fresh);
        return Err(e);
    }
    let had = data.exists();
    if had {
        std::fs::rename(data, &old).map_err(|e| format!("{}: {e}", data.display()))?;
    }
    if let Err(e) = std::fs::rename(&fresh, data) {
        if had {
            let _ = std::fs::rename(&old, data);
        }
        let _ = std::fs::remove_dir_all(&fresh);
        return Err(format!("{}: {e}", data.display()));
    }
    let _ = std::fs::remove_dir_all(&old);
    Ok(())
}

/// The restore points of `link`, oldest first. A point whose description
/// does not read is left out.
pub fn list(root: &Path, link: &str) -> Vec<Point> {
    let Ok(dir) = link_dir(root, link) else {
        return Vec::new();
    };
    let Ok(rd) = std::fs::read_dir(&dir) else {
        return Vec::new();
    };
    let mut out: Vec<Point> = rd
        .flatten()
        .filter(|e| e.path().extension().is_some_and(|x| x == META))
        .filter_map(|e| {
            let bytes = std::fs::read(e.path()).ok()?;
            let p: Point = minicbor::decode(&bytes).ok()?;
            // the name is the file's, whatever the description says
            let id = e.path().file_stem()?.to_string_lossy().into_owned();
            (p.id == id && dir.join(format!("{id}.{ARCHIVE}")).is_file()).then_some(p)
        })
        .collect();
    out.sort_by(|a, b| (a.at, &a.id).cmp(&(b.at, &b.id)));
    out
}

/// The newest restore point of `link` taken at or before `at` while it ran
/// `version` of `package`.
pub fn newest_before(
    root: &Path,
    link: &str,
    at: u64,
    package: &str,
    version: &str,
) -> Option<Point> {
    list(root, link)
        .into_iter()
        .rev()
        .find(|p| p.at <= at && p.package == package && p.version == version)
}

fn remove_point(dir: &Path, id: &str) {
    let _ = std::fs::remove_file(dir.join(format!("{id}.{META}")));
    let _ = std::fs::remove_file(dir.join(format!("{id}.{ARCHIVE}")));
}

/// Remove the restore points older than `keep_s` seconds (and directories
/// left empty); returns the links that lost one.
pub fn prune(root: &Path, now: u64, keep_s: u64) -> Vec<String> {
    let Ok(rd) = std::fs::read_dir(root) else {
        return Vec::new();
    };
    let mut touched = Vec::new();
    for e in rd.flatten() {
        let link = e.file_name().to_string_lossy().into_owned();
        if !e.path().is_dir() || crate::registry::validate_link_id(&link).is_err() {
            continue;
        }
        let mut removed = false;
        for p in list(root, &link) {
            if p.at.saturating_add(keep_s) < now {
                remove_point(&e.path(), &p.id);
                removed = true;
            }
        }
        if removed {
            touched.push(link);
        }
        // only an empty directory goes
        let _ = std::fs::remove_dir(e.path());
    }
    touched.sort();
    touched
}

/// Forget every restore point of `link` (the link was removed).
pub fn remove_link(root: &Path, link: &str) {
    if let Ok(dir) = link_dir(root, link) {
        let _ = std::fs::remove_dir_all(dir);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tmp(name: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("wyrm-restore-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        d
    }

    fn write(path: &Path, bytes: &[u8]) {
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(path, bytes).unwrap();
    }

    #[test]
    fn stamps() {
        assert_eq!(stamp(0), "19700101T000000Z");
        assert_eq!(stamp(1_794_564_902), "20261113T101502Z");
    }

    #[test]
    fn a_point_brings_the_data_back_and_is_sealed() {
        let d = tmp("roundtrip");
        let (root, data) = (d.join("restore"), d.join("links/l1/data"));
        write(&data.join("framework.tree"), b"TREE-v1 secret-pw-123456");
        write(&data.join("store/p/0"), b"page0");
        write(&data.join("uploads/c1/spool"), b"scratch");
        write(&data.join("x.tmp"), b"scratch");
        let k = key(b"secrets-key");
        let keys = vec!["a".to_owned(), "a/b".to_owned()];
        let p = make(
            &root,
            "l1",
            &data,
            &k,
            "pkg",
            "1.0.0",
            Some(keys.clone()),
            100,
        )
        .unwrap();
        assert_eq!(
            (p.at, p.version.as_str(), p.keys_known),
            (100, "1.0.0", true)
        );
        assert_eq!(p.keys, keys);
        let file = root.join(format!("l1/{}.restore", p.id));
        let sealed = std::fs::read(&file).unwrap();
        assert_eq!(sealed.len() as u64, p.size);
        assert!(
            !sealed.windows(9).any(|w| w == b"pw-123456"),
            "nothing in clear"
        );
        assert_eq!(list(&root, "l1"), vec![p.clone()]);

        // the new version writes over the data; the point puts it back whole
        std::fs::write(data.join("framework.tree"), b"TREE-v2").unwrap();
        std::fs::remove_dir_all(data.join("store")).unwrap();
        write(&data.join("v2-only"), b"x");
        apply(&root, "l1", &p.id, &data, &k).unwrap();
        assert_eq!(
            std::fs::read(data.join("framework.tree")).unwrap(),
            b"TREE-v1 secret-pw-123456"
        );
        assert_eq!(std::fs::read(data.join("store/p/0")).unwrap(), b"page0");
        assert!(!data.join("v2-only").exists(), "replaced as a whole");
        assert!(!data.join("uploads").exists() && !data.join("x.tmp").exists());
        assert!(!d.join("links/l1/data.restoring").exists());
        assert!(!d.join("links/l1/data.replaced").exists());

        // another broker's keys open nothing, and the data stays
        let err = apply(&root, "l1", &p.id, &data, &key(b"other")).unwrap_err();
        assert!(err.contains("keys"), "{err}");
        assert!(data.join("framework.tree").is_file());
        // a name that would leave the directory
        assert!(apply(&root, "l1", "../x", &data, &k).is_err());
        assert!(apply(&root, "..", &p.id, &data, &k).is_err());
    }

    #[test]
    fn a_link_without_data_and_without_an_answer() {
        let d = tmp("empty");
        let (root, data) = (d.join("restore"), d.join("links/l1/data"));
        let k = key(b"k");
        let p = make(&root, "l1", &data, &k, "pkg", "1", None, 5).unwrap();
        assert!(!p.keys_known && p.keys.is_empty());
        write(&data.join("new"), b"x");
        apply(&root, "l1", &p.id, &data, &k).unwrap();
        assert!(data.is_dir() && !data.join("new").exists());
    }

    #[test]
    fn listing_choosing_and_pruning() {
        let d = tmp("prune");
        let (root, data) = (d.join("restore"), d.join("links/l1/data"));
        write(&data.join("f"), b"1");
        let k = key(b"k");
        let a = make(&root, "l1", &data, &k, "pkg", "1.0.0", None, 1_000).unwrap();
        let b = make(&root, "l1", &data, &k, "pkg", "1.0.0", None, 1_000).unwrap();
        let c = make(&root, "l1", &data, &k, "pkg", "1.1.0", None, 2_000).unwrap();
        let other = make(&root, "l2", &data, &k, "pkg", "1.0.0", None, 3_000).unwrap();
        assert_ne!(a.id, b.id, "two in one second");
        let ids = |l: &str| -> Vec<String> { list(&root, l).into_iter().map(|p| p.id).collect() };
        assert_eq!(ids("l1"), [a.id.clone(), b.id.clone(), c.id.clone()]);
        assert_eq!(
            newest_before(&root, "l1", 2_500, "pkg", "1.0.0")
                .unwrap()
                .id,
            b.id
        );
        assert_eq!(
            newest_before(&root, "l1", 2_500, "pkg", "1.1.0")
                .unwrap()
                .id,
            c.id
        );
        assert!(newest_before(&root, "l1", 1_500, "pkg", "1.1.0").is_none());
        assert!(newest_before(&root, "l1", 2_500, "other", "1.0.0").is_none());
        // a point without its archive is not listed
        std::fs::remove_file(root.join(format!("l1/{}.restore", a.id))).unwrap();
        assert_eq!(ids("l1"), [b.id.clone(), c.id.clone()]);

        assert_eq!(prune(&root, 1_000 + 500, 600), Vec::<String>::new());
        assert_eq!(prune(&root, 1_000 + 601, 600), ["l1"]);
        assert_eq!(ids("l1"), std::slice::from_ref(&c.id));
        assert_eq!(prune(&root, 10_000, 600), ["l1", "l2"]);
        assert!(ids("l1").is_empty() && ids("l2").is_empty());
        assert!(!root.join("l2").exists(), "an empty directory goes");
        let _ = other;
        make(&root, "l2", &data, &k, "pkg", "1.0.0", None, 3_000).unwrap();
        remove_link(&root, "l2");
        assert!(!root.join("l2").exists());
    }

    /// Security review of the restore point: the link runs while its data
    /// is copied and owns the directory. A symlink there is never followed
    /// (so no file of the broker's is copied out), a file or directory
    /// swapped for a symlink after it was listed is refused, and a restore
    /// never writes through a symlink.
    #[cfg(unix)]
    #[test]
    fn symlinks_are_never_followed() {
        use std::os::unix::fs::symlink;
        let d = tmp("symlink");
        let (root, data) = (d.join("restore"), d.join("links/l1/data"));
        let outside = d.join("outside");
        write(&outside.join("secret"), b"BROKER-SECRET-0123456789");
        write(&data.join("own"), b"mine");
        write(&data.join("sub/own2"), b"mine2");
        symlink(outside.join("secret"), data.join("leak")).unwrap();
        symlink(&outside, data.join("leakdir")).unwrap();
        symlink(outside.join("secret"), data.join("sub/leak2")).unwrap();
        let k = key(b"k");
        let p = make(&root, "l1", &data, &k, "pkg", "1", None, 10).unwrap();
        assert_eq!(p.skipped, 3, "the three symlinks are counted, not copied");
        // what the point holds: the link's two files, nothing from outside
        let sealed = std::fs::read(root.join(format!("l1/{}.restore", p.id))).unwrap();
        let plain = wyrm_link_sdk::seal::open(&k, &sealed).unwrap();
        assert!(!plain.windows(13).any(|w| w == b"BROKER-SECRET"));
        let mut names: Vec<String> = zip::ZipArchive::new(Cursor::new(plain))
            .unwrap()
            .file_names()
            .map(|n| n.unwrap().into_owned())
            .collect();
        names.sort();
        assert_eq!(names, ["own", "sub/own2"]);

        // a file swapped for a symlink after the listing: opened without
        // following, so it is refused, not read
        let dir = open_nofollow(&data, true).unwrap();
        let leak = std::ffi::OsStr::new("leak");
        let err = open_entry(&dir, &data, leak, false).err().unwrap();
        assert!(err.contains("changed while it was copied"), "{err}");
        let err = open_entry(&dir, &data, std::ffi::OsStr::new("leakdir"), true)
            .err()
            .unwrap();
        assert!(err.contains("changed while it was copied"), "{err}");
        // a directory on the way swapped for a symlink: what opens through
        // the path is not an entry of the directory the walk holds
        let sub = open_nofollow(&data.join("sub"), true).unwrap();
        std::fs::rename(data.join("sub"), data.join("sub.real")).unwrap();
        symlink(&outside, data.join("sub")).unwrap();
        let err = open_entry(
            &sub,
            &data.join("sub"),
            std::ffi::OsStr::new("secret"),
            false,
        )
        .err()
        .unwrap();
        assert!(err.contains("not an entry of the directory"), "{err}");
        // the real entry of the held directory still opens
        std::fs::remove_file(data.join("sub")).unwrap();
        std::fs::rename(data.join("sub.real"), data.join("sub")).unwrap();
        let own2 = std::ffi::OsStr::new("own2");
        assert!(open_entry(&sub, &data.join("sub"), own2, false)
            .unwrap()
            .is_some());
        // an entry that went away is not an error
        let gone = std::ffi::OsStr::new("gone");
        assert!(open_entry(&dir, &data, gone, false).unwrap().is_none());
        // a data directory that is itself a symlink is refused
        let fake = d.join("links/l2/data");
        std::fs::create_dir_all(fake.parent().unwrap()).unwrap();
        symlink(&outside, &fake).unwrap();
        assert!(make(&root, "l2", &fake, &k, "pkg", "1", None, 10).is_err());

        // apply: the fresh directory's name taken by a symlink to outside
        // (left there by the link): it is unlinked, and nothing is written
        // through it
        symlink(&outside, d.join("links/l1/data.restoring")).unwrap();
        symlink(&outside, d.join("links/l1/data.replaced")).unwrap();
        apply(&root, "l1", &p.id, &data, &k).unwrap();
        assert_eq!(std::fs::read(data.join("own")).unwrap(), b"mine");
        assert_eq!(std::fs::read(data.join("sub/own2")).unwrap(), b"mine2");
        assert!(
            !data.join("leak").exists(),
            "the symlinks did not come back"
        );
        let mut out: Vec<_> = std::fs::read_dir(&outside)
            .unwrap()
            .flatten()
            .map(|e| e.file_name())
            .collect();
        out.sort();
        assert_eq!(out, ["secret"], "nothing was written outside");
        assert_eq!(
            std::fs::read(outside.join("secret")).unwrap(),
            b"BROKER-SECRET-0123456789"
        );
        // unpacking never writes over or through what is there
        let target = d.join("unpack");
        std::fs::create_dir_all(&target).unwrap();
        symlink(&outside, target.join("sub")).unwrap();
        let file = root.join(format!("l1/{}.restore", p.id));
        let err = read_archive(&file, &target, &k).unwrap_err();
        assert!(err.contains("not a directory"), "{err}");
        let target = d.join("unpack2");
        std::fs::create_dir_all(&target).unwrap();
        symlink(outside.join("secret"), target.join("own")).unwrap();
        assert!(read_archive(&file, &target, &k).is_err());
        assert_eq!(
            std::fs::read(outside.join("secret")).unwrap(),
            b"BROKER-SECRET-0123456789"
        );
    }

    #[test]
    fn data_over_the_bound_is_refused() {
        let d = tmp("big");
        let (root, data) = (d.join("restore"), d.join("links/l1/data"));
        std::fs::create_dir_all(&data).unwrap();
        let f = std::fs::File::create(data.join("big")).unwrap();
        f.set_len(MAX_BYTES + 1).unwrap();
        let err = make(&root, "l1", &data, &key(b"k"), "pkg", "1", None, 1).unwrap_err();
        assert!(err.contains("MiB"), "{err}");
        assert!(list(&root, "l1").is_empty());
    }
}
