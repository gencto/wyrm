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

/// `(relative path, absolute path)` of every regular file under `dir`,
/// sorted; symlinks and scratch names are left out.
fn files_of(dir: &Path) -> Result<Vec<(String, PathBuf)>, String> {
    fn walk(dir: &Path, rel: &str, out: &mut Vec<(String, PathBuf)>) -> Result<(), String> {
        let rd = match std::fs::read_dir(dir) {
            Ok(rd) => rd,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(()),
            Err(e) => return Err(format!("{}: {e}", dir.display())),
        };
        let mut entries: Vec<_> = rd.flatten().collect();
        entries.sort_by_key(|e| e.file_name());
        for e in entries {
            let name = e.file_name().to_string_lossy().into_owned();
            if scratch(&name) {
                continue;
            }
            // not followed: a link out of the directory is not the link's data
            let meta = std::fs::symlink_metadata(e.path())
                .map_err(|x| format!("{}: {x}", e.path().display()))?;
            let path = if rel.is_empty() {
                name
            } else {
                format!("{rel}/{name}")
            };
            if meta.is_dir() {
                walk(&e.path(), &path, out)?;
            } else if meta.is_file() {
                if out.len() >= MAX_FILES {
                    return Err(format!("more than {MAX_FILES} files"));
                }
                out.push((path, e.path()));
            }
        }
        Ok(())
    }
    let mut out = Vec::new();
    walk(dir, "", &mut out)?;
    Ok(out)
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
/// `out`; returns its size. Provisional format, to be replaced by the
/// `.wyrm-link` writer of ADR 0048 §3.5 (sections `data` without history).
fn write_archive(data: &Path, out: &Path, key: &[u8; 32]) -> Result<u64, String> {
    use zip::write::SimpleFileOptions;
    let mut w = zip::ZipWriter::new(Cursor::new(Vec::new()));
    let mut total = 0u64;
    for (rel, path) in files_of(data)? {
        let meta = std::fs::metadata(&path).map_err(|e| format!("{rel}: {e}"))?;
        total += meta.len();
        if total > MAX_BYTES {
            return Err(format!(
                "the link's private data is over {} MiB",
                MAX_BYTES >> 20
            ));
        }
        let bytes = std::fs::read(&path).map_err(|e| format!("{rel}: {e}"))?;
        // stored: what a link keeps is sealed already and does not compress
        let opt = SimpleFileOptions::default()
            .compression_method(zip::CompressionMethod::Stored)
            .unix_permissions(mode_of(&meta));
        w.start_file(rel.as_str(), opt)
            .map_err(|e| format!("{rel}: {e}"))?;
        w.write_all(&bytes).map_err(|e| format!("{rel}: {e}"))?;
    }
    let plain = w.finish().map_err(|e| e.to_string())?.into_inner();
    let sealed = wyrm_link_sdk::seal::seal(key, &plain);
    crate::secret::write_private(out, &sealed).map_err(|e| format!("{}: {e}", out.display()))?;
    Ok(sealed.len() as u64)
}

/// SEAM (read side): unpack what [`write_archive`] made into the new, empty
/// directory `data`. Provisional format, as [`write_archive`].
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
        let path = data.join(&rel);
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
        }
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
        crate::secret::write_private(&path, &bytes)
            .map_err(|e| format!("{}: {e}", rel.display()))?;
        #[cfg(unix)]
        if let Some(mode) = mode {
            use std::os::unix::fs::PermissionsExt;
            std::fs::set_permissions(&path, std::fs::Permissions::from_mode(mode & 0o777))
                .map_err(|e| format!("{}: {e}", rel.display()))?;
        }
        #[cfg(not(unix))]
        let _ = mode;
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
    let size = write_archive(data, &archive, key)?;
    let point = Point {
        id: id.clone(),
        at: now,
        package: package.to_owned(),
        version: version.to_owned(),
        size,
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
    let _ = std::fs::remove_dir_all(&fresh);
    let _ = std::fs::remove_dir_all(&old);
    private_dir(&fresh)?;
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
