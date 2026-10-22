//! "Install Link ▸ from Git" (ADR 0011): a shallow `git clone` of a built
//! package, zipped in memory (without `.git`) so it goes through the same
//! checks as a zip ([`crate::packages::unpack`]).

use std::io::{Cursor, Write};
use std::path::{Path, PathBuf};
use std::time::Duration;
use zip::write::SimpleFileOptions;

const CLONE_TIMEOUT: Duration = Duration::from_secs(120);
const MAX_FILES: usize = 1000;
const MAX_BYTES: u64 = 256 << 20;

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
/// `allow_file` (the `dev` profile, for tests). Never an option.
pub fn check_url(url: &str, allow_file: bool) -> Result<(), String> {
    let ok = url.starts_with("https://") || (allow_file && url.starts_with("file://"));
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

/// Clone `url` at `git_ref` (default branch when empty) into a temp
/// directory under `root`, then return the files as a zip and the commit
/// id. The temp directory is removed in every case.
pub async fn clone_zip(
    url: &str,
    git_ref: &str,
    allow_file: bool,
    root: &Path,
) -> Result<(Vec<u8>, String), String> {
    check_url(url, allow_file)?;
    if !git_ref.is_empty() && !valid_ref(git_ref) {
        return Err(format!("ref {git_ref:?}: a branch or tag name"));
    }
    std::fs::create_dir_all(root).map_err(|e| e.to_string())?;
    let mut rnd = [0u8; 8];
    getrandom::fill(&mut rnd).map_err(|e| e.to_string())?;
    let dir = root.join(format!(".git-{}", hex::encode(rnd)));
    let result = clone_in(url, git_ref, allow_file, &dir).await;
    let _ = std::fs::remove_dir_all(&dir);
    result
}

async fn clone_in(
    url: &str,
    git_ref: &str,
    allow_file: bool,
    dir: &Path,
) -> Result<(Vec<u8>, String), String> {
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
    let out = tokio::time::timeout(CLONE_TIMEOUT, cmd.output())
        .await
        .map_err(|_| format!("git clone: no result in {} s", CLONE_TIMEOUT.as_secs()))?
        .map_err(|e| format!("git: {e} (is git installed?)"))?;
    if !out.status.success() {
        let err = String::from_utf8_lossy(&out.stderr);
        return Err(format!("git clone: {}", err.trim()));
    }
    let head = tokio::process::Command::new("git")
        .env_clear()
        .env("PATH", std::env::var_os("PATH").unwrap_or_default())
        .arg("-C")
        .arg(dir)
        .args(["rev-parse", "HEAD"])
        .output()
        .await
        .map_err(|e| format!("git: {e}"))?;
    let commit = String::from_utf8_lossy(&head.stdout).trim().to_owned();
    let dir = dir.to_owned();
    let zip = tokio::task::spawn_blocking(move || zip_dir(&dir))
        .await
        .map_err(|e| e.to_string())??;
    Ok((zip, commit))
}

/// The files under `dir` (without `.git`) as a zip, in name order, with
/// their unix modes; symlinks and special files are refused.
pub fn zip_dir(dir: &Path) -> Result<Vec<u8>, String> {
    let mut files: Vec<PathBuf> = Vec::new();
    let mut stack = vec![dir.to_owned()];
    while let Some(d) = stack.pop() {
        let mut entries: Vec<_> = std::fs::read_dir(&d)
            .map_err(|e| e.to_string())?
            .collect::<Result<_, _>>()
            .map_err(|e| e.to_string())?;
        entries.sort_by_key(|e| e.file_name());
        for e in entries {
            let path = e.path();
            if d == dir && e.file_name() == ".git" {
                continue;
            }
            let ty = e.file_type().map_err(|e| e.to_string())?;
            if ty.is_symlink() {
                return Err(format!("{}: symlinks are not allowed", path.display()));
            } else if ty.is_dir() {
                stack.push(path);
            } else if ty.is_file() {
                files.push(path);
            } else {
                return Err(format!("{}: not a regular file", path.display()));
            }
        }
        if files.len() > MAX_FILES {
            return Err(format!("more than {MAX_FILES} files"));
        }
    }
    files.sort();
    let mut w = zip::ZipWriter::new(Cursor::new(Vec::new()));
    let mut total = 0u64;
    for path in files {
        let rel = path
            .strip_prefix(dir)
            .map_err(|e| e.to_string())?
            .to_string_lossy()
            .replace('\\', "/");
        let data = std::fs::read(&path).map_err(|e| e.to_string())?;
        total += data.len() as u64;
        if total > MAX_BYTES {
            return Err(format!("more than {} MiB", MAX_BYTES >> 20));
        }
        let mut opt =
            SimpleFileOptions::default().compression_method(zip::CompressionMethod::Stored);
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mode = std::fs::metadata(&path)
                .map_err(|e| e.to_string())?
                .permissions()
                .mode();
            opt = opt.unix_permissions(mode & 0o777);
        }
        w.start_file(rel, opt).map_err(|e| e.to_string())?;
        w.write_all(&data).map_err(|e| e.to_string())?;
    }
    Ok(w.finish().map_err(|e| e.to_string())?.into_inner())
}

#[cfg(test)]
mod tests {
    use super::*;

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
            assert!(zip_dir(&d).unwrap_err().contains("symlink"));
        }
    }
}
