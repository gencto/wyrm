//! Restore points of links (ADR 0048 §1.3, §3.5): a link backup without
//! history (`.wyrm-link`, sealed for this broker) and the link's key list,
//! taken before a package update stops the link or before a restore
//! replaces it, under `data_dir/restore/<link>/<UTC>.{wyrm-link,meta}`.
//!
//! This module keeps the directory: [`make`] names a point and writes its
//! description, [`file`] finds its archive, [`list`], [`newest_before`] and
//! [`prune`] read and trim it. The archive itself is made and applied by
//! the backup code (`Control::link_backup_to`, `Control::link_restore_data`),
//! handed in as a function: this module knows no archive format.

use minicbor::{Decode, Encode};
use std::path::{Path, PathBuf};

/// Extension of the archive: a link backup.
const ARCHIVE: &str = crate::backup::EXT_LINK;
/// Extension of the description beside it.
const META: &str = "meta";
/// An archive being written (`<archive>.part`), left by a broker that
/// ended: removed by [`prune`] after this long.
const PART_STALE_S: u64 = 3600;

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

/// Take a restore point of `link` now. `write` makes the archive at the
/// path it is given, whole or not at all, and answers its size and how many
/// entries of the link's data it skipped (not files); `keys` is the link's
/// key list (`None`: the link did not answer). Nothing of the link is
/// touched. `root` is `data_dir/restore`.
pub fn make(
    root: &Path,
    link: &str,
    package: &str,
    version: &str,
    keys: Option<Vec<String>>,
    now: u64,
    write: impl FnOnce(&Path) -> Result<(u64, u32), String>,
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
    let (size, skipped) = write(&archive)?;
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

/// The archive of the restore point `id` of `link`.
pub fn file(root: &Path, link: &str, id: &str) -> Result<PathBuf, String> {
    let dir = link_dir(root, link)?;
    if id.is_empty() || id.contains(['/', '\\', '.']) {
        return Err(format!("restore point {id:?}"));
    }
    let archive = dir.join(format!("{id}.{ARCHIVE}"));
    if !archive.is_file() {
        return Err(format!("restore point {id} of {link}: not found"));
    }
    Ok(archive)
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
        // what a broker that ended left: an archive being written, or one
        // whose description was never written
        for f in std::fs::read_dir(e.path()).into_iter().flatten().flatten() {
            let path = f.path();
            let age = f
                .metadata()
                .ok()
                .and_then(|m| m.modified().ok())
                .and_then(|t| t.elapsed().ok())
                .map_or(0, |d| d.as_secs());
            let part = path.extension().is_some_and(|x| x == "part");
            let orphan = path.extension().is_some_and(|x| x == ARCHIVE)
                && !path.with_extension(META).exists();
            if (part && age > PART_STALE_S) || (orphan && age > keep_s) {
                let _ = std::fs::remove_file(&path);
            }
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

    /// An archive of `bytes`, as the backup code would write one.
    fn archive(
        bytes: &'static [u8],
        skipped: u32,
    ) -> impl FnOnce(&Path) -> Result<(u64, u32), String> {
        move |path| {
            std::fs::write(path, bytes).map_err(|e| e.to_string())?;
            Ok((bytes.len() as u64, skipped))
        }
    }

    #[test]
    fn stamps() {
        assert_eq!(stamp(0), "19700101T000000Z");
        assert_eq!(stamp(1_794_564_902), "20261113T101502Z");
    }

    #[test]
    fn a_point_is_an_archive_and_its_description() {
        let d = tmp("make");
        let root = d.join("restore");
        let keys = vec!["a".to_owned(), "a/b".to_owned()];
        let p = make(
            &root,
            "l1",
            "pkg",
            "1.0.0",
            Some(keys.clone()),
            100,
            archive(b"sealed", 2),
        )
        .unwrap();
        assert_eq!(
            (p.at, p.version.as_str(), p.keys_known, p.size, p.skipped),
            (100, "1.0.0", true, 6, 2)
        );
        assert_eq!(p.keys, keys);
        let path = file(&root, "l1", &p.id).unwrap();
        assert_eq!(path, root.join(format!("l1/{}.wyrm-link", p.id)));
        assert_eq!(std::fs::read(&path).unwrap(), b"sealed");
        assert_eq!(list(&root, "l1"), vec![p.clone()]);
        // a link that did not answer: no key list
        let q = make(&root, "l1", "pkg", "1", None, 200, archive(b"x", 0)).unwrap();
        assert!(!q.keys_known && q.keys.is_empty());
        // an archive that was not written leaves no point
        let e = make(&root, "l1", "pkg", "1", None, 300, |_| Err("disk".into())).unwrap_err();
        assert_eq!(e, "disk");
        assert_eq!(list(&root, "l1").len(), 2);
        // a name that would leave the directory
        assert!(file(&root, "l1", "../x").is_err());
        assert!(file(&root, "..", &p.id).is_err());
        assert!(file(&root, "l1", "19700101T000000Z").is_err(), "not there");
        assert!(make(&root, "..", "pkg", "1", None, 1, archive(b"x", 0)).is_err());
    }

    #[test]
    fn listing_choosing_and_pruning() {
        let d = tmp("prune");
        let root = d.join("restore");
        let mk = |link: &str, version: &str, at: u64| {
            make(&root, link, "pkg", version, None, at, archive(b"1", 0)).unwrap()
        };
        let a = mk("l1", "1.0.0", 1_000);
        let b = mk("l1", "1.0.0", 1_000);
        let c = mk("l1", "1.1.0", 2_000);
        let other = mk("l2", "1.0.0", 3_000);
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
        std::fs::remove_file(root.join(format!("l1/{}.wyrm-link", a.id))).unwrap();
        assert_eq!(ids("l1"), [b.id.clone(), c.id.clone()]);

        assert_eq!(prune(&root, 1_000 + 500, 600), Vec::<String>::new());
        assert_eq!(prune(&root, 1_000 + 601, 600), ["l1"]);
        assert_eq!(ids("l1"), std::slice::from_ref(&c.id));
        // an archive whose description was never written stays while it is
        // young (the file's own time), and goes once it is older than that
        let orphan = root.join("l1/20200101T000000Z.wyrm-link");
        std::fs::write(&orphan, b"x").unwrap();
        prune(&root, 2_000, 600);
        assert!(orphan.is_file());
        std::thread::sleep(std::time::Duration::from_millis(1100));
        prune(&root, 2_000, 0);
        assert!(!orphan.exists());
        assert_eq!(prune(&root, 10_000, 600), ["l1", "l2"]);
        assert!(ids("l1").is_empty() && ids("l2").is_empty());
        assert!(!root.join("l2").exists(), "an empty directory goes");
        let _ = other;
        mk("l2", "1.0.0", 3_000);
        remove_link(&root, "l2");
        assert!(!root.join("l2").exists());
    }
}
