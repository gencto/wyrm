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

/// Why a path of a link's data was not read or made. Every refusal names the
/// path and, where the system said why, carries its error as the source.
#[derive(Debug, thiserror::Error)]
pub enum NofollowError {
    /// A directory was not opened, listed or made.
    #[error("{}: {source}", .path.display())]
    Io {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    /// A name that is not `/`-separated plain segments (empty, `.`, `..`).
    #[error("{0}: not a plain path")]
    NotPlain(String),
    /// A listed entry did not open without following a link: a symlink took
    /// its name, or it is not what the listing said.
    #[error(
        "{}: not opened without following links ({source}); the link's data changed while it was copied",
        .path.display()
    )]
    EntryNotOpened {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    /// The open entry's type and size were not read from its handle.
    #[error("{}: {source}; the link's data changed while it was copied", .path.display())]
    EntryNotRead {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    /// What opened is not the kind of entry that was listed.
    #[error(
        "{}: not the file or directory that was listed; the link's data changed while it was copied",
        .0.display()
    )]
    EntrySwapped(PathBuf),
    /// What opened through the path is not an entry of the held directory:
    /// a directory on the way was swapped.
    #[error(
        "{}: not an entry of the directory that was listed; the link's data changed while it was copied",
        .0.display()
    )]
    EntryMoved(PathBuf),
    /// One file more than the walk's bound.
    #[error("more than {0} files")]
    TooManyFiles(usize),
    /// The root of a walk did not open without following a link.
    #[error("{}: not opened without following links ({source})", .path.display())]
    RootNotOpened {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    /// A symlink or something else that is no directory where one must be.
    #[error("{}: not a directory", .0.display())]
    NotDirectory(PathBuf),
    /// A relative path with a part that is no plain name (`..`, a root).
    #[error("unsafe path {}", .0.display())]
    UnsafePath(PathBuf),
    /// The new directory was not made its owner's alone.
    #[error("{source}")]
    NotPrivate {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
}

/// Why [`walk_files`] ended: its own refusal, or what the caller's function
/// answered for a file (`E`, as the caller said it).
#[derive(Debug, thiserror::Error)]
pub enum WalkError<E> {
    #[error(transparent)]
    Walk(#[from] NofollowError),
    #[error("{0}")]
    Emit(E),
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
fn same_entry(parent: &File, name: &std::ffi::OsStr, file: &File) -> bool {
    use std::os::unix::io::AsRawFd;
    // both sides from `stat(2)` itself: the same field types on every unix
    // target (`dev_t` is `i32` on macOS, `u64` on Linux), so nothing is cast
    let listed = nix::sys::stat::fstatat(
        Some(parent.as_raw_fd()),
        name,
        nix::fcntl::AtFlags::AT_SYMLINK_NOFOLLOW,
    );
    match (listed, nix::sys::stat::fstat(file.as_raw_fd())) {
        (Ok(a), Ok(b)) => a.st_dev == b.st_dev && a.st_ino == b.st_ino,
        _ => false,
    }
}

#[cfg(not(unix))]
fn same_entry(_: &File, _: &std::ffi::OsStr, _: &File) -> bool {
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
) -> Result<Option<Entry>, NofollowError> {
    let path = parent_path.join(name);
    let file = match open_nofollow(&path, dir) {
        Ok(f) => f,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(source) => return Err(NofollowError::EntryNotOpened { path, source }),
    };
    let meta = match file.metadata() {
        Ok(m) => m,
        Err(source) => return Err(NofollowError::EntryNotRead { path, source }),
    };
    let kind = meta.file_type();
    if kind.is_symlink() || (dir && !kind.is_dir()) || (!dir && !kind.is_file()) {
        return Err(NofollowError::EntrySwapped(path));
    }
    if !same_entry(parent, name, &file) {
        return Err(NofollowError::EntryMoved(path));
    }
    Ok(Some(Entry { file, meta }))
}

/// Open the regular file `rel` (`/` separators, plain segments) under the
/// directory `root` for reading, following no symlink in any part of the
/// path below `root`: every directory on the way and the file itself are
/// opened once with `O_NOFOLLOW` and checked against the held handle of
/// their parent. `Ok(None)`: it is not there. For a file whose name came
/// from a listing made earlier (the standby asks for it by name).
pub fn open_under(root: &Path, rel: &str) -> Result<Option<File>, NofollowError> {
    let mut dir = open_nofollow(root, true).map_err(|source| NofollowError::Io {
        path: root.to_owned(),
        source,
    })?;
    let mut path = root.to_owned();
    let segs: Vec<&str> = rel.split('/').collect();
    for (i, seg) in segs.iter().enumerate() {
        if seg.is_empty() || *seg == "." || *seg == ".." {
            return Err(NofollowError::NotPlain(rel.to_owned()));
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
    Err(NofollowError::NotPlain(rel.to_owned()))
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
/// the root (`/` separators), the open handle, the handle's metadata. Its
/// error `E` ends the walk as [`WalkError::Emit`].
pub type Emit<'a, E> = dyn FnMut(&str, File, &std::fs::Metadata) -> Result<(), E> + 'a;

fn walk<E>(
    dir: &File,
    path: &Path,
    rel: &str,
    rules: &Rules,
    seen: &mut Walked,
    emit: &mut Emit<E>,
) -> Result<(), WalkError<E>> {
    let rd = std::fs::read_dir(path).map_err(|source| NofollowError::Io {
        path: path.to_owned(),
        source,
    })?;
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
            Err(source) => {
                let path = e.path();
                return Err(NofollowError::Io { path, source }.into());
            }
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
                return Err(NofollowError::TooManyFiles(rules.max_files).into());
            }
            emit(&child, entry.file, &entry.meta).map_err(WalkError::Emit)?;
        }
    }
    Ok(())
}

/// Every regular file under the directory `root`, in name order, handed to
/// `emit` as an open handle. A missing `root` is an empty one; a `root`
/// that is a symlink or no directory is refused. See the module
/// documentation for what is never followed.
pub fn walk_files<E>(
    root: &Path,
    rules: &Rules,
    emit: &mut Emit<E>,
) -> Result<Walked, WalkError<E>> {
    let mut seen = Walked::default();
    let path = || root.to_owned();
    let dir = match open_nofollow(root, true) {
        Ok(d) => d,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(seen),
        Err(source) => {
            let path = path();
            return Err(NofollowError::RootNotOpened { path, source }.into());
        }
    };
    let kind = dir
        .metadata()
        .map_err(|source| {
            let path = path();
            NofollowError::Io { path, source }
        })?
        .file_type();
    if kind.is_symlink() || !kind.is_dir() {
        return Err(NofollowError::NotDirectory(path()).into());
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
pub fn make_dirs(root: &Path, rel: &Path) -> Result<PathBuf, NofollowError> {
    let mut dir = root.to_path_buf();
    for c in rel.components() {
        let std::path::Component::Normal(c) = c else {
            return Err(NofollowError::UnsafePath(rel.to_owned()));
        };
        dir.push(c);
        match std::fs::create_dir(&dir) {
            Ok(()) => {}
            Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => {
                let real = std::fs::symlink_metadata(&dir).is_ok_and(|m| m.is_dir());
                if !real {
                    return Err(NofollowError::NotDirectory(dir));
                }
            }
            Err(source) => return Err(NofollowError::Io { path: dir, source }),
        }
    }
    Ok(dir)
}

/// A new directory only its owner enters: refused when the name is taken
/// (a symlink there too), then checked and set as `secret::private_dir_of`.
pub fn new_private_dir(dir: &Path) -> Result<(), NofollowError> {
    let mut b = std::fs::DirBuilder::new();
    #[cfg(unix)]
    std::os::unix::fs::DirBuilderExt::mode(&mut b, 0o700);
    b.create(dir).map_err(|source| NofollowError::Io {
        path: dir.to_owned(),
        source,
    })?;
    crate::secret::private_dir_of(dir)
        .map(drop)
        .map_err(|source| NofollowError::NotPrivate {
            path: dir.to_owned(),
            source,
        })
}

/// Remove what is at `path` as what it is: a directory with its content, a
/// file or a symlink by its own name (never its target). Nothing there is
/// done; any other failure is the caller's to handle (rule 10): what it removes
/// holds state (restored data, opened secrets, a package).
pub fn remove_any(path: &Path) -> std::io::Result<()> {
    match std::fs::symlink_metadata(path) {
        Ok(m) if m.is_dir() => std::fs::remove_dir_all(path),
        Ok(_) => std::fs::remove_file(path),
        Err(e) => wyrm_core::files::gone_ok(e),
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
        let read = |rel: &str| -> Result<Option<Vec<u8>>, NofollowError> {
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
        assert!(matches!(
            read("links/l1/data/../../../outside/secret"),
            Err(NofollowError::NotPlain(_))
        ));
        assert!(
            matches!(
                read("links/l1/data/store"),
                Err(NofollowError::EntrySwapped(_))
            ),
            "a directory is no file"
        );
        // the file is a symlink
        symlink(d.join("outside/secret"), root.join("links/l1/data/leak")).unwrap();
        assert!(matches!(
            read("links/l1/data/leak"),
            Err(NofollowError::EntryNotOpened { .. })
        ));
        // a directory on the way is one
        symlink(d.join("outside"), root.join("links/l1/data/dir")).unwrap();
        assert!(matches!(
            read("links/l1/data/dir/secret"),
            Err(NofollowError::EntryNotOpened { .. })
        ));
        // the listed directory was swapped for one
        std::fs::rename(
            root.join("links/l1/data/store"),
            root.join("links/l1/data/store.real"),
        )
        .unwrap();
        symlink(d.join("outside"), root.join("links/l1/data/store")).unwrap();
        assert!(matches!(
            read("links/l1/data/store/secret"),
            Err(NofollowError::EntryNotOpened { .. })
        ));
    }

    /// Every refusal says what it said as text: these reach the answers of
    /// backups, restores and the replication to a standby.
    #[test]
    fn refusals_read_as_before() {
        fn said(e: &dyn std::fmt::Display, text: &str) {
            assert_eq!(e.to_string(), text);
        }
        let io = || std::io::Error::other("no");
        let p = || PathBuf::from("/d/f");
        type E = NofollowError;
        said(
            &E::Io {
                path: p(),
                source: io(),
            },
            "/d/f: no",
        );
        said(&E::NotPlain("a/../b".into()), "a/../b: not a plain path");
        said(
            &E::EntryNotOpened {
                path: p(),
                source: io(),
            },
            "/d/f: not opened without following links (no); the link's data changed while it was copied",
        );
        said(
            &E::EntryNotRead {
                path: p(),
                source: io(),
            },
            "/d/f: no; the link's data changed while it was copied",
        );
        said(
            &E::EntrySwapped(p()),
            "/d/f: not the file or directory that was listed; the link's data changed while it was copied",
        );
        said(
            &E::EntryMoved(p()),
            "/d/f: not an entry of the directory that was listed; the link's data changed while it was copied",
        );
        said(&E::TooManyFiles(7), "more than 7 files");
        said(
            &E::RootNotOpened {
                path: p(),
                source: io(),
            },
            "/d/f: not opened without following links (no)",
        );
        said(&E::NotDirectory(p()), "/d/f: not a directory");
        said(&E::UnsafePath("../x".into()), "unsafe path ../x");
        said(
            &E::NotPrivate {
                path: p(),
                source: io(),
            },
            "no",
        );
        said(
            &WalkError::<String>::Walk(E::TooManyFiles(7)),
            "more than 7 files",
        );
        said(
            &WalkError::Emit("as the caller said it"),
            "as the caller said it",
        );
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

    fn collect(
        root: &Path,
        max_files: usize,
    ) -> Result<(Files, Walked), WalkError<std::io::Error>> {
        let mut out = Vec::new();
        let scratch = |n: &str| n == "uploads" || n.ends_with(".tmp");
        let rules = Rules {
            scratch: &scratch,
            max_files,
        };
        let seen = walk_files(root, &rules, &mut |rel, mut f, _| {
            let mut b = Vec::new();
            f.read_to_end(&mut b)?;
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
        assert!(matches!(
            collect(&data, 1),
            Err(WalkError::Walk(NofollowError::TooManyFiles(1)))
        ));
        // what the caller's function answers ends the walk as it said it
        let rules = Rules {
            scratch: &|_| false,
            max_files: 10,
        };
        let mut handed = Vec::new();
        let end = walk_files(&data, &rules, &mut |rel, _, _| {
            handed.push(rel.to_owned());
            Err(7u8)
        });
        assert!(matches!(end, Err(WalkError::Emit(7))), "{end:?}");
        assert_eq!(handed, ["a/x"], "nothing is handed out after a refusal");
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
        assert!(matches!(err, NofollowError::EntryNotOpened { .. }), "{err}");
        let err = open_entry(&dir, &data, std::ffi::OsStr::new("leakdir"), true)
            .err()
            .unwrap();
        assert!(matches!(err, NofollowError::EntryNotOpened { .. }), "{err}");
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
        assert!(matches!(err, NofollowError::EntryMoved(_)), "{err}");
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
        assert!(matches!(
            collect(&fake, 100),
            Err(WalkError::Walk(NofollowError::RootNotOpened { .. }))
        ));

        // the write side: a directory name taken by a symlink is refused,
        // a file name taken by one is not written through
        let target = d.join("unpack");
        std::fs::create_dir_all(&target).unwrap();
        symlink(&outside, target.join("sub")).unwrap();
        let err = make_dirs(&target, Path::new("sub")).unwrap_err();
        assert!(matches!(err, NofollowError::NotDirectory(_)), "{err}");
        assert!(matches!(
            make_dirs(&target, Path::new("../x")),
            Err(NofollowError::UnsafePath(_))
        ));
        symlink(outside.join("secret"), target.join("own")).unwrap();
        assert!(create_new(&target.join("own"), None).is_err());
        assert!(create_new(&target.join("new"), None).is_ok());
        // a stale name is removed as what it is, never through it
        symlink(&outside, d.join("stale")).unwrap();
        remove_any(&d.join("stale")).unwrap();
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
