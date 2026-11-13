//! Reading and writing a link's private data directory
//! (`data_dir/links/<id>/data`) without ever following a symlink.
//!
//! A link owns that directory and may run while the broker copies it (a
//! backup, a restore point before a package update: ADR 0048 §1.3, §3.5).
//! Nothing read from a path is trusted there: [`walk_files`] opens every
//! entry once with `O_NOFOLLOW`, takes its type and size from that handle,
//! checks it against the held handle of its parent directory, and hands the
//! open file to the caller. A symlink, socket, FIFO or device is counted and
//! never opened; a file or directory swapped after it was listed is refused.
//! The write side ([`make_dirs`], [`create_new`]) makes every directory and
//! file new and follows no symlink either.

use std::fs::File;
use std::path::{Path, PathBuf};

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
/// entry is opened once without following a symlink, its type and size come
/// from that handle, and it must be the entry of that name in the held
/// parent. `Ok(None)`: it went away. Anything else that is not what the
/// listing said (a file swapped for a symlink, a directory swapped on the
/// way) is refused.
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

/// Open the regular file `rel` (`/` separators, plain segments) under the
/// directory `root` for reading, following no symlink in any part of the
/// path below `root`: every directory on the way and the file itself are
/// opened once with `O_NOFOLLOW` and checked against the held handle of
/// their parent. `Ok(None)`: it is not there. For a file whose name came
/// from a listing made earlier (the standby asks for it by name).
pub fn open_under(root: &Path, rel: &str) -> Result<Option<File>, String> {
    let mut dir = open_nofollow(root, true).map_err(|e| format!("{}: {e}", root.display()))?;
    let mut path = root.to_owned();
    let segs: Vec<&str> = rel.split('/').collect();
    for (i, seg) in segs.iter().enumerate() {
        if seg.is_empty() || *seg == "." || *seg == ".." {
            return Err(format!("{rel}: not a plain path"));
        }
        let last = i + 1 == segs.len();
        let Some(e) = open_entry(&dir, &path, std::ffi::OsStr::new(seg), !last)? else {
            return Ok(None);
        };
        if last {
            return Ok(Some(e.file));
        }
        dir = e.file;
        path.push(seg);
    }
    Err(format!("{rel}: not a plain path"))
}

/// What a walk found beside what it handed out.
#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct Walked {
    /// Regular files handed to the caller.
    pub files: usize,
    /// Entries that are neither a regular file nor a directory (symlinks,
    /// sockets, FIFOs, devices): never opened, never copied.
    pub skipped: u32,
}

/// What a walk is asked to leave out and where it stops.
pub struct Rules<'a> {
    /// `true` for an entry name that is scratch (a spool, a temp file).
    pub scratch: &'a dyn Fn(&str) -> bool,
    /// Most files; one more is an error.
    pub max_files: usize,
}

/// The file handed to the caller of [`walk_files`]: its path relative to
/// the root (`/` separators), the open handle, the handle's metadata.
pub type Emit<'a> = dyn FnMut(&str, File, &std::fs::Metadata) -> Result<(), String> + 'a;

fn walk(
    dir: &File,
    path: &Path,
    rel: &str,
    rules: &Rules,
    seen: &mut Walked,
    emit: &mut Emit,
) -> Result<(), String> {
    let rd = std::fs::read_dir(path).map_err(|e| format!("{}: {e}", path.display()))?;
    let mut entries: Vec<_> = rd.flatten().collect();
    entries.sort_by_key(|e| e.file_name());
    for e in entries {
        let os_name = e.file_name();
        let name = os_name.to_string_lossy().into_owned();
        if (rules.scratch)(&name) {
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
            walk(&entry.file, &path.join(&os_name), &child, rules, seen, emit)?;
        } else {
            seen.files += 1;
            if seen.files > rules.max_files {
                return Err(format!("more than {} files", rules.max_files));
            }
            emit(&child, entry.file, &entry.meta)?;
        }
    }
    Ok(())
}

/// Every regular file under the directory `root`, in name order, handed to
/// `emit` as an open handle. A missing `root` is an empty one; a `root`
/// that is a symlink or no directory is refused. See the module
/// documentation for what is never followed.
pub fn walk_files(root: &Path, rules: &Rules, emit: &mut Emit) -> Result<Walked, String> {
    let mut seen = Walked::default();
    let dir = match open_nofollow(root, true) {
        Ok(d) => d,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(seen),
        Err(e) => {
            return Err(format!(
                "{}: not opened without following links ({e})",
                root.display()
            ))
        }
    };
    let kind = dir
        .metadata()
        .map_err(|e| format!("{}: {e}", root.display()))?
        .file_type();
    if kind.is_symlink() || !kind.is_dir() {
        return Err(format!("{}: not a directory", root.display()));
    }
    walk(&dir, root, "", rules, &mut seen, emit)?;
    Ok(seen)
}

/// A new file `path` for writing (it must not exist, and a symlink there
/// is not followed), readable by its owner (`mode` on unix).
pub fn create_new(path: &Path, mode: Option<u32>) -> std::io::Result<File> {
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
    o.open(path)
}

/// The directories of `rel` under `root`, made one by one: one that is
/// there must be a real directory (never a symlink to follow).
pub fn make_dirs(root: &Path, rel: &Path) -> Result<PathBuf, String> {
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

/// A new directory only its owner enters: refused when the name is taken.
pub fn new_private_dir(dir: &Path) -> Result<(), String> {
    let mut b = std::fs::DirBuilder::new();
    #[cfg(unix)]
    std::os::unix::fs::DirBuilderExt::mode(&mut b, 0o700);
    b.create(dir).map_err(|e| format!("{}: {e}", dir.display()))
}

/// Remove what is at `path` as what it is: a directory with its content, a
/// file or a symlink by its own name (never its target).
pub fn remove_any(path: &Path) {
    match std::fs::symlink_metadata(path) {
        Ok(m) if m.is_dir() => {
            let _ = std::fs::remove_dir_all(path);
        }
        Ok(_) => {
            let _ = std::fs::remove_file(path);
        }
        Err(_) => {}
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Read;

    /// A file asked for by name (replication to a standby): a symlink
    /// anywhere below the root is refused, never read through.
    #[test]
    #[cfg(unix)]
    fn a_file_by_name_is_opened_through_no_symlink() {
        use std::os::unix::fs::symlink;
        let d = tmp("open-under");
        let root = d.join("root");
        write(&root.join("links/l1/data/store/p0"), b"page");
        write(&d.join("outside/secret"), b"BROKER-SECRET");
        let read = |rel: &str| -> Result<Option<Vec<u8>>, String> {
            Ok(match open_under(&root, rel)? {
                Some(mut f) => {
                    let mut b = Vec::new();
                    f.read_to_end(&mut b).unwrap();
                    Some(b)
                }
                None => None,
            })
        };
        assert_eq!(read("links/l1/data/store/p0").unwrap().unwrap(), b"page");
        assert_eq!(read("links/l1/data/store/none").unwrap(), None);
        assert_eq!(read("links/l2/data/x").unwrap(), None);
        assert!(read("links/l1/data/../../../outside/secret").is_err());
        assert!(
            read("links/l1/data/store").is_err(),
            "a directory is no file"
        );
        // the file is a symlink
        symlink(d.join("outside/secret"), root.join("links/l1/data/leak")).unwrap();
        assert!(read("links/l1/data/leak").is_err());
        // a directory on the way is one
        symlink(d.join("outside"), root.join("links/l1/data/dir")).unwrap();
        assert!(read("links/l1/data/dir/secret").is_err());
        // the listed directory was swapped for one
        std::fs::rename(
            root.join("links/l1/data/store"),
            root.join("links/l1/data/store.real"),
        )
        .unwrap();
        symlink(d.join("outside"), root.join("links/l1/data/store")).unwrap();
        assert!(read("links/l1/data/store/secret").is_err());
    }

    fn tmp(name: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("wyrm-nofollow-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        d
    }

    fn write(path: &Path, bytes: &[u8]) {
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(path, bytes).unwrap();
    }

    /// `(relative path, content)` of every file a walk hands out.
    type Files = Vec<(String, Vec<u8>)>;

    fn collect(root: &Path, max_files: usize) -> Result<(Files, Walked), String> {
        let mut out = Vec::new();
        let scratch = |n: &str| n == "uploads" || n.ends_with(".tmp");
        let rules = Rules {
            scratch: &scratch,
            max_files,
        };
        let seen = walk_files(root, &rules, &mut |rel, mut f, _| {
            let mut b = Vec::new();
            f.read_to_end(&mut b).map_err(|e| e.to_string())?;
            out.push((rel.to_owned(), b));
            Ok(())
        })?;
        Ok((out, seen))
    }

    #[test]
    fn files_in_name_order_without_scratch() {
        let d = tmp("walk");
        let data = d.join("data");
        assert_eq!(collect(&data, 10).unwrap().1, Walked::default(), "missing");
        write(&data.join("b"), b"2");
        write(&data.join("a/x"), b"1");
        write(&data.join("uploads/spool"), b"scratch");
        write(&data.join("y.tmp"), b"scratch");
        let (files, seen) = collect(&data, 10).unwrap();
        assert_eq!(
            files,
            [
                ("a/x".to_owned(), b"1".to_vec()),
                ("b".to_owned(), b"2".to_vec())
            ]
        );
        assert_eq!(
            seen,
            Walked {
                files: 2,
                skipped: 0
            }
        );
        assert!(collect(&data, 1).unwrap_err().contains("more than 1"));
    }

    /// Security review of the restore point (commit 0784257), now for every
    /// copy of a link's data: the link runs while its data is copied and
    /// owns the directory. A symlink there is never followed (so no file of
    /// the broker's is copied out), a file or directory swapped for a
    /// symlink after it was listed is refused, and the write side never
    /// writes through a symlink.
    #[cfg(unix)]
    #[test]
    fn symlinks_are_never_followed() {
        use std::os::unix::fs::symlink;
        let d = tmp("symlink");
        let data = d.join("links/l1/data");
        let outside = d.join("outside");
        write(&outside.join("secret"), b"BROKER-SECRET-0123456789");
        write(&data.join("own"), b"mine");
        write(&data.join("sub/own2"), b"mine2");
        symlink(outside.join("secret"), data.join("leak")).unwrap();
        symlink(&outside, data.join("leakdir")).unwrap();
        symlink(outside.join("secret"), data.join("sub/leak2")).unwrap();
        let (files, seen) = collect(&data, 100).unwrap();
        assert_eq!(seen.skipped, 3, "the three symlinks are counted, not read");
        // the link's two files, nothing from outside
        assert_eq!(
            files,
            [
                ("own".to_owned(), b"mine".to_vec()),
                ("sub/own2".to_owned(), b"mine2".to_vec())
            ]
        );

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
        assert!(collect(&fake, 100).is_err());

        // the write side: a directory name taken by a symlink is refused,
        // a file name taken by one is not written through
        let target = d.join("unpack");
        std::fs::create_dir_all(&target).unwrap();
        symlink(&outside, target.join("sub")).unwrap();
        let err = make_dirs(&target, Path::new("sub")).unwrap_err();
        assert!(err.contains("not a directory"), "{err}");
        assert!(make_dirs(&target, Path::new("../x")).is_err());
        symlink(outside.join("secret"), target.join("own")).unwrap();
        assert!(create_new(&target.join("own"), None).is_err());
        assert!(create_new(&target.join("new"), None).is_ok());
        // a stale name is removed as what it is, never through it
        symlink(&outside, d.join("stale")).unwrap();
        remove_any(&d.join("stale"));
        assert!(!d.join("stale").exists() && outside.join("secret").is_file());
        assert_eq!(
            std::fs::read(outside.join("secret")).unwrap(),
            b"BROKER-SECRET-0123456789"
        );
        let mut out: Vec<_> = std::fs::read_dir(&outside)
            .unwrap()
            .flatten()
            .map(|e| e.file_name())
            .collect();
        out.sort();
        assert_eq!(out, ["secret"], "nothing was written outside");
    }
}
