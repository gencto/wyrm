//! "Install Link ▸ from Git" (ADR 0011): a shallow `git clone` of a built
//! package, zipped in memory (without `.git`) so it goes through the same
//! checks as a zip ([`crate::packages::unpack`]).

use std::io::{Cursor, Write};
use std::path::{Path, PathBuf};
use std::time::Duration;
use wyrm_core::weburl::{split_scheme, HttpUrl, SchemeCase, UrlError};
use zip::write::SimpleFileOptions;

const CLONE_TIMEOUT: Duration = Duration::from_secs(120);
const MAX_FILES: usize = 1000;
const MAX_BYTES: u64 = 256 << 20;

/// Why a clone gave no package.
#[derive(Debug, thiserror::Error)]
pub enum GitError {
    /// A user or password in the URL; never repeated.
    #[error("url: no credentials in the URL (only public repositories)")]
    Credentials,
    /// Not `https://` (`dev`: nor `file://` where the dev profile takes it),
    /// with whitespace, or longer than 512 bytes.
    #[error("url {url}: https:// only{}", if *.dev { " (or file:// in dev)" } else { "" })]
    Url { url: String, dev: bool },
    /// Not a branch or tag name (it could be read as an option).
    #[error("ref {0:?}: a branch or tag name")]
    Ref(String),
    /// The directory the clone goes to was not made.
    #[error("{0}")]
    Root(#[source] std::io::Error),
    #[error("{0}")]
    Random(#[source] wyrm_core::rand::NoRandomness),
    /// `git clone` did not end in time; it was stopped.
    #[error("git clone: no result in {0} s")]
    Timeout(u64),
    /// `git` did not start.
    #[error("git: {0} (is git installed?)")]
    NotStarted(#[source] std::io::Error),
    /// `git clone` ended with a failure: its exit status and what it said.
    #[error("git clone: {stderr}")]
    Clone {
        status: std::process::ExitStatus,
        stderr: String,
    },
    /// `git rev-parse` did not start.
    #[error("git: {0}")]
    Commit(#[source] std::io::Error),
    /// The task that zips the clone did not end.
    #[error("{0}")]
    Task(#[source] tokio::task::JoinError),
    #[error("{}: symlinks are not allowed", .0.display())]
    Symlink(PathBuf),
    /// A socket, a FIFO, a device.
    #[error("{}: not a regular file", .0.display())]
    NotRegular(PathBuf),
    #[error("more than {0} files")]
    TooManyFiles(usize),
    /// The files are larger in all than this many MiB.
    #[error("more than {0} MiB")]
    TooLarge(u64),
    /// A directory or a file of the clone was not read.
    #[error("{0}")]
    Read(#[source] std::io::Error),
    /// A file that is not under the directory it was found in.
    #[error("{0}")]
    Outside(#[source] std::path::StripPrefixError),
    /// The zip was not written.
    #[error("{0}")]
    Zip(#[source] zip::result::ZipError),
    #[error("{0}")]
    ZipWrite(#[source] std::io::Error),
}

/// A git ref: a branch or tag name, never an option.
fn valid_ref(r: &str) -> bool {
    !r.is_empty()
        && r.len() <= 128
        && !r.starts_with(['-', '/', '.'])
        && !r.contains("..")
        && r.bytes()
            .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'.' | b'_' | b'-' | b'/'))
}

/// Check the clone source: `https://` always; `file://` only when
/// `allow_file` (the `dev` profile, for tests). Never an option, never
/// credentials in the URL: it is kept as the package source (registry,
/// `sys/packages`, audit), so a token in it would be on show.
pub fn check_url(url: &str, allow_file: bool) -> Result<(), GitError> {
    // `file://` has no host for the URL parser: it is the dev profile's alone
    let file = allow_file
        && split_scheme(url).is_some_and(|(scheme, _)| scheme == "file")
        && !url.contains('@');
    let ok = match HttpUrl::parse(url, SchemeCase::Lower) {
        Err(UrlError::Credentials) => return Err(GitError::Credentials),
        Ok(u) => u.tls,
        Err(_) => file,
    };
    if !ok || url.contains(char::is_whitespace) || url.len() > 512 {
        return Err(GitError::Url {
            url: url.to_owned(),
            dev: allow_file,
        });
    }
    Ok(())
}

/// Clone `url` at `git_ref` (default branch when empty) into a temp
/// directory under `root`, then return the files as a zip and the commit
/// id. The temp directory is removed in every case.
pub async fn clone_zip(
    url: &str,
    git_ref: &str,
    allow_file: bool,
    root: &Path,
) -> Result<(Vec<u8>, String), GitError> {
    check_url(url, allow_file)?;
    if !git_ref.is_empty() && !valid_ref(git_ref) {
        return Err(GitError::Ref(git_ref.to_owned()));
    }
    std::fs::create_dir_all(root).map_err(GitError::Root)?;
    let mut rnd = [0u8; 8];
    wyrm_core::rand::fill(&mut rnd).map_err(GitError::Random)?;
    let dir = root.join(format!(".git-{}", hex::encode(rnd)));
    let result = clone_in(url, git_ref, allow_file, &dir).await;
    wyrm_core::files::discard_dir(&dir);
    result
}

async fn clone_in(
    url: &str,
    git_ref: &str,
    allow_file: bool,
    dir: &Path,
) -> Result<(Vec<u8>, String), GitError> {
    let mut cmd = tokio::process::Command::new("git");
    cmd.env_clear()
        .env("PATH", std::env::var_os("PATH").unwrap_or_default())
        .env("GIT_TERMINAL_PROMPT", "0")
        .env("GIT_CONFIG_NOSYSTEM", "1")
        .env("GIT_CONFIG_GLOBAL", "/dev/null")
        .args([
            "-c",
            "protocol.allow=never",
            "-c",
            "protocol.https.allow=always",
        ]);
    if allow_file {
        cmd.args(["-c", "protocol.file.allow=always"]);
    }
    cmd.args([
        "-c",
        "core.hooksPath=/dev/null",
        "clone",
        "--quiet",
        "--depth",
        "1",
        "--no-recurse-submodules",
    ]);
    if !git_ref.is_empty() {
        cmd.args(["--branch", git_ref]);
    }
    cmd.arg("--").arg(url).arg(dir).kill_on_drop(true);
    let out = match tokio::time::timeout(CLONE_TIMEOUT, cmd.output()).await {
        Ok(out) => out.map_err(GitError::NotStarted)?,
        Err(tokio::time::error::Elapsed { .. }) => {
            return Err(GitError::Timeout(CLONE_TIMEOUT.as_secs()))
        }
    };
    if !out.status.success() {
        let err = String::from_utf8_lossy(&out.stderr);
        return Err(GitError::Clone {
            status: out.status,
            stderr: err.trim().to_owned(),
        });
    }
    let head = tokio::process::Command::new("git")
        .env_clear()
        .env("PATH", std::env::var_os("PATH").unwrap_or_default())
        .arg("-C")
        .arg(dir)
        .args(["rev-parse", "HEAD"])
        .output()
        .await
        .map_err(GitError::Commit)?;
    let commit = String::from_utf8_lossy(&head.stdout).trim().to_owned();
    let dir = dir.to_owned();
    let zip = tokio::task::spawn_blocking(move || zip_dir(&dir))
        .await
        .map_err(GitError::Task)??;
    Ok((zip, commit))
}

/// The files under `dir` (without `.git`) as a zip, in name order, with
/// their unix modes; symlinks and special files are refused.
pub fn zip_dir(dir: &Path) -> Result<Vec<u8>, GitError> {
    let mut files: Vec<PathBuf> = Vec::new();
    let mut stack = vec![dir.to_owned()];
    while let Some(d) = stack.pop() {
        let mut entries: Vec<_> = std::fs::read_dir(&d)
            .map_err(GitError::Read)?
            .collect::<Result<_, _>>()
            .map_err(GitError::Read)?;
        entries.sort_by_key(|e| e.file_name());
        for e in entries {
            let path = e.path();
            if d == dir && e.file_name() == ".git" {
                continue;
            }
            let ty = e.file_type().map_err(GitError::Read)?;
            if ty.is_symlink() {
                return Err(GitError::Symlink(path));
            } else if ty.is_dir() {
                stack.push(path);
            } else if ty.is_file() {
                files.push(path);
            } else {
                return Err(GitError::NotRegular(path));
            }
        }
        if files.len() > MAX_FILES {
            return Err(GitError::TooManyFiles(MAX_FILES));
        }
    }
    files.sort();
    let mut w = zip::ZipWriter::new(Cursor::new(Vec::new()));
    let mut total = 0u64;
    for path in files {
        let rel = path
            .strip_prefix(dir)
            .map_err(GitError::Outside)?
            .to_string_lossy()
            .replace('\\', "/");
        let data = std::fs::read(&path).map_err(GitError::Read)?;
        total += data.len() as u64;
        if total > MAX_BYTES {
            return Err(GitError::TooLarge(MAX_BYTES >> 20));
        }
        let mut opt =
            SimpleFileOptions::default().compression_method(zip::CompressionMethod::Stored);
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mode = std::fs::metadata(&path)
                .map_err(GitError::Read)?
                .permissions()
                .mode();
            opt = opt.unix_permissions(mode & 0o777);
        }
        w.start_file(rel, opt).map_err(GitError::Zip)?;
        w.write_all(&data).map_err(GitError::ZipWrite)?;
    }
    Ok(w.finish().map_err(GitError::Zip)?.into_inner())
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The check before review S4, kept to compare.
    fn old_check_url(url: &str, allow_file: bool) -> Result<(), String> {
        let ok = url.starts_with("https://") || (allow_file && url.starts_with("file://"));
        let authority = url
            .split_once("://")
            .map(|(_, rest)| rest.split('/').next().unwrap_or(""))
            .unwrap_or("");
        if authority.contains('@') {
            return Err("url: no credentials in the URL (only public repositories)".into());
        }
        if !ok || url.contains(char::is_whitespace) || url.len() > 512 {
            return Err(format!(
                "url {url}: https:// only{}",
                if allow_file {
                    " (or file:// in dev)"
                } else {
                    ""
                }
            ));
        }
        Ok(())
    }

    /// Review S4: every clone URL the old check took is taken, and what it refused stays
    /// refused; a credential in a `file://` URL is refused too.
    #[test]
    fn urls_check_as_before() {
        for (s, dev) in [
            ("https://git.example/x.git", false),
            ("https://github.com/acme/links.git", false),
            ("https://git.example:8443/a/b", true),
            ("file:///tmp/x", true),
        ] {
            assert_eq!(
                check_url(s, dev).is_ok(),
                old_check_url(s, dev).is_ok(),
                "{s}"
            );
            assert!(check_url(s, dev).is_ok(), "{s}");
        }
        for (s, dev) in [
            ("file:///tmp/x", false),
            ("-c x", true),
            ("ssh://git@h/x", true),
            ("https://user:tok3n@git.example/x.git", false),
            ("http://git.example/x.git", true),
            ("https://git.example/a b", false),
            ("HTTPS://git.example/x", false),
        ] {
            assert!(old_check_url(s, dev).is_err(), "old took {s}");
            assert!(check_url(s, dev).is_err(), "{s}");
        }
        // refused now, taken before: a host that is no host, a bad port
        for s in ["https://[x/y", "https://h:99999/x", "https:///x"] {
            assert!(old_check_url(s, false).is_ok(), "{s}");
            assert!(check_url(s, false).is_err(), "{s}");
        }
    }

    #[test]
    fn refs_and_urls() {
        for ok in ["main", "v1.2.0", "release/2026-10"] {
            assert!(valid_ref(ok), "{ok}");
        }
        for bad in ["-c", "--upload-pack=x", "../x", "/abs", "a..b", "a b", ""] {
            assert!(!valid_ref(bad), "{bad}");
        }
        assert!(check_url("https://git.example/x.git", false).is_ok());
        assert!(check_url("file:///tmp/x", false).is_err());
        assert!(check_url("file:///tmp/x", true).is_ok());
        assert!(check_url("-c x", true).is_err());
        assert!(check_url("ssh://git@h/x", true).is_err());
        let err = check_url("https://user:tok3n@git.example/x.git", false).unwrap_err();
        assert!(matches!(err, GitError::Credentials), "{err}");
        let shown = format!("{err} {err:?}");
        assert!(!shown.contains("tok3n"), "{shown}");
        assert!(matches!(
            check_url("http://git.example/x.git", true),
            Err(GitError::Url { dev: true, .. })
        ));
    }

    /// Every refusal says what it said as text: these are the answers of
    /// `install_git`.
    #[test]
    fn refusals_read_as_before() {
        fn said(e: &GitError, text: &str) {
            assert_eq!(e.to_string(), text);
        }
        type E = GitError;
        let io = || std::io::Error::other("no");
        let p = || PathBuf::from("/d/f");
        said(
            &E::Credentials,
            "url: no credentials in the URL (only public repositories)",
        );
        said(
            &E::Url {
                url: "ftp://h/x".into(),
                dev: false,
            },
            "url ftp://h/x: https:// only",
        );
        said(
            &E::Url {
                url: "ftp://h/x".into(),
                dev: true,
            },
            "url ftp://h/x: https:// only (or file:// in dev)",
        );
        said(&E::Ref("-c".into()), "ref \"-c\": a branch or tag name");
        said(&E::Root(io()), "no");
        said(&E::Timeout(120), "git clone: no result in 120 s");
        said(&E::NotStarted(io()), "git: no (is git installed?)");
        said(
            &E::Clone {
                status: std::process::ExitStatus::default(),
                stderr: "fatal: no".into(),
            },
            "git clone: fatal: no",
        );
        said(&E::Commit(io()), "git: no");
        said(&E::Symlink(p()), "/d/f: symlinks are not allowed");
        said(&E::NotRegular(p()), "/d/f: not a regular file");
        said(&E::TooManyFiles(MAX_FILES), "more than 1000 files");
        said(&E::TooLarge(MAX_BYTES >> 20), "more than 256 MiB");
        said(&E::Read(io()), "no");
        let outside = Path::new("/a").strip_prefix("/b").unwrap_err();
        said(&E::Outside(outside), "prefix not found");
        said(
            &E::Zip(zip::result::ZipError::FileNotFound),
            "specified file not found in archive",
        );
        said(&E::ZipWrite(io()), "no");
        // `E::Random` shows its cause alone, as `e.to_string()` did; the cause
        // is made only by `wyrm_core::rand`. `E::Task` shows the runtime's text
        let join = tokio::runtime::Builder::new_current_thread()
            .build()
            .unwrap()
            .block_on(async {
                let task = tokio::spawn(std::future::pending::<()>());
                task.abort();
                task.await.unwrap_err()
            });
        let text = join.to_string();
        said(&E::Task(join), &text);
    }

    /// What is refused before `git` runs is told apart by type; a clone
    /// that fails carries the exit status of `git`.
    #[tokio::test]
    async fn clone_failures_are_told_apart() {
        let d = std::env::temp_dir().join(format!("wyrm-clone-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        let root = d.join("root");
        let none = format!("file://{}", d.join("none").display());
        let e = clone_zip(&none, "--upload-pack=x", true, &root)
            .await
            .unwrap_err();
        assert!(
            matches!(&e, GitError::Ref(r) if r == "--upload-pack=x"),
            "{e:?}"
        );
        let e = clone_zip(&none, "", false, &root).await.unwrap_err();
        assert!(matches!(e, GitError::Url { dev: false, .. }), "{e:?}");
        assert!(!root.exists(), "refused before anything is made");
        match clone_zip(&none, "", true, &root).await.unwrap_err() {
            GitError::Clone { status, stderr } => {
                assert!(!status.success() && !stderr.is_empty(), "{status} {stderr}");
            }
            // a host without git
            GitError::NotStarted(_) => {}
            e => panic!("{e:?}"),
        }
        let left = std::fs::read_dir(&root).unwrap().count();
        assert_eq!(left, 0, "the temp directory is removed");
    }

    #[test]
    fn zips_a_directory_without_git() {
        let d = std::env::temp_dir().join(format!("wyrm-zipdir-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(d.join(".git")).unwrap();
        std::fs::create_dir_all(d.join("bin")).unwrap();
        std::fs::write(d.join(".git/config"), "x").unwrap();
        std::fs::write(d.join("wyrm-link.json"), "{}").unwrap();
        std::fs::write(d.join("bin/run"), "#!/bin/sh").unwrap();
        let z = zip_dir(&d).unwrap();
        let a = zip::ZipArchive::new(Cursor::new(z)).unwrap();
        let mut names: Vec<String> = a.file_names().map(|n| n.unwrap().into_owned()).collect();
        names.sort();
        assert_eq!(names, ["bin/run", "wyrm-link.json"]);
        #[cfg(unix)]
        {
            std::os::unix::fs::symlink("/etc/passwd", d.join("bin/link")).unwrap();
            let link = d.join("bin/link");
            assert!(matches!(zip_dir(&d), Err(GitError::Symlink(p)) if p == link));
        }
    }
}
