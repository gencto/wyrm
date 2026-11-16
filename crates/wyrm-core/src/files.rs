//! Removing files: the one place a failed removal of a scratch file is not an error.
//!
//! docs/rust-rules.md rule 10: the result of a removal is never dropped. A file or
//! directory that holds state (a key, a certificate, a role or update marker, a
//! backup, a package, a link's data) is removed with `std::fs::remove_*` and the
//! error is handled: `?`, a refusal, or a logged error that names what stays. The
//! rules check (C8) counts every dropped `remove_file`, `remove_dir_all` and
//! `create_dir_all`.
//!
//! A *scratch* file is different: a temporary file before or after a write, a
//! staging or download directory, a part of an upload. It holds nothing anyone
//! reads again (the next run removes or replaces it), so a failed removal changes
//! no state, and the caller has nothing to refuse. [`discard`] (a file) and
//! [`discard_dir`] (a directory) remove one and log a failure with the path; they
//! are the only way a removal's error is not returned. They are never for a file
//! that holds state.

use std::io;
use std::path::Path;

/// Remove the scratch file `path` (a symlink by its own name). Absent is done; a
/// directory at the name is not removed (`remove_file` fails on it, as it did where
/// this replaced a bare `remove_file`). Any failure is logged with the path and
/// not returned: see the module doc.
pub fn discard(path: &Path) {
    log_left(path, std::fs::remove_file(path));
}

/// Remove the scratch directory `path` with all it holds (`remove_dir_all`: a
/// symlink is removed, never followed). Absent is done; a failure is logged with
/// the path and not returned: see the module doc.
pub fn discard_dir(path: &Path) {
    log_left(path, std::fs::remove_dir_all(path));
}

fn log_left(path: &Path, removed: io::Result<()>) {
    match removed {
        Ok(()) => {}
        Err(e) if e.kind() == io::ErrorKind::NotFound => {}
        Err(e) => tracing::warn!(
            path = %path.display(),
            "a scratch file stays (nothing reads it; the next run removes it): {e}"
        ),
    }
}

/// For `std::fs::remove_file(p).or_else(files::gone_ok)?`: a file that is not
/// there is removed; every other error stays an error.
pub fn gone_ok(e: io::Error) -> io::Result<()> {
    if e.kind() == io::ErrorKind::NotFound {
        Ok(())
    } else {
        Err(e)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn discard_removes_what_it_names_and_follows_no_link() {
        let base = std::env::temp_dir().join(format!("wyrm-files-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&base);
        std::fs::create_dir_all(base.join("dir/sub")).unwrap();
        std::fs::write(base.join("dir/sub/a"), b"x").unwrap();
        std::fs::write(base.join("file"), b"x").unwrap();
        discard_dir(&base.join("dir"));
        discard(&base.join("file"));
        discard(&base.join("absent"));
        discard_dir(&base.join("absent"));
        assert!(!base.join("dir").exists());
        assert!(!base.join("file").exists());
        // a directory is no scratch file: it stays (and is logged)
        std::fs::create_dir_all(base.join("kept/x")).unwrap();
        discard(&base.join("kept"));
        assert!(base.join("kept/x").exists());
        #[cfg(unix)]
        {
            let target = base.join("target");
            std::fs::create_dir_all(&target).unwrap();
            std::fs::write(target.join("kept"), b"x").unwrap();
            std::os::unix::fs::symlink(&target, base.join("link")).unwrap();
            discard_dir(&base.join("link"));
            assert!(std::fs::symlink_metadata(base.join("link")).is_err());
            assert!(target.join("kept").exists(), "the target is not followed");
        }
        std::fs::remove_dir_all(&base).unwrap();
    }

    #[test]
    fn gone_ok_keeps_every_other_error() {
        let base = std::env::temp_dir().join(format!("wyrm-gone-{}", std::process::id()));
        std::fs::create_dir_all(base.join("full")).unwrap();
        std::fs::write(base.join("full/a"), b"x").unwrap();
        assert!(std::fs::remove_file(base.join("absent"))
            .or_else(gone_ok)
            .is_ok());
        // a directory is no file: the error stays
        assert!(std::fs::remove_file(base.join("full"))
            .or_else(gone_ok)
            .is_err());
        std::fs::remove_dir_all(&base).unwrap();
    }
}
