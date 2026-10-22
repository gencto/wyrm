//! Link packages (ADR 0011): a zip with `wyrm-link.json` at its root,
//! unpacked under `data_dir/packages/<name>/<version>/`.
//!
//! A package is checked in a temp directory first ([`unpack`]) and moved
//! into place in one rename ([`Unpacked::commit`]), so a failed install
//! leaves nothing behind.

use crate::registry::{PackageDef, PackageKind};
use serde::Deserialize;
use sha2::{Digest, Sha256};
use std::collections::BTreeMap;
use std::io::{Cursor, Read, Write};
use std::path::{Path, PathBuf};

pub const MANIFEST: &str = "wyrm-link.json";
/// Largest accepted zip.
pub const MAX_ZIP: usize = 64 << 20;
const MAX_UNPACKED: u64 = 256 << 20;
const MAX_FILES: usize = 1000;
/// Driver name of a link that runs a package: `pkg:<package>`.
pub const DRIVER_PREFIX: &str = "pkg:";

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Manifest {
    name: String,
    version: String,
    #[serde(default)]
    description: String,
    wyrm_link: u32,
    kind: String,
    #[serde(default)]
    entries: BTreeMap<String, String>,
    #[serde(default)]
    args: Vec<String>,
    #[serde(default)]
    entry: Option<String>,
    /// Grants the link needs as a requester: `[{path, level}]`.
    #[serde(default)]
    requester: Vec<RequestedGrant>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct RequestedGrant {
    path: String,
    level: String,
}

/// One package of a repository index (`packages.repository`, as DSA's
/// `linkRepositoryUrl`): `[{name, version, description, url, sha256}]`.
#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct RepoEntry {
    pub name: String,
    pub version: String,
    #[serde(default)]
    pub description: String,
    pub url: String,
    pub sha256: String,
}

/// Largest repository index.
pub const MAX_INDEX: usize = 4 << 20;

/// Parse and check a repository index: at most 1000 entries, unique valid
/// names, a 64-hex SHA-256 each.
pub fn parse_index(bytes: &[u8]) -> Result<Vec<RepoEntry>, String> {
    let list: Vec<RepoEntry> = serde_json::from_slice(bytes).map_err(|e| format!("index: {e}"))?;
    if list.len() > MAX_FILES {
        return Err(format!("index: more than {MAX_FILES} packages"));
    }
    let mut seen = std::collections::HashSet::new();
    for e in &list {
        crate::registry::validate_link_id(&e.name).map_err(|x| format!("index: {x}"))?;
        if !seen.insert(e.name.as_str()) {
            return Err(format!("index: {} twice", e.name));
        }
        if e.sha256.len() != 64 || !e.sha256.bytes().all(|b| b.is_ascii_hexdigit()) {
            return Err(format!("index: {}: sha256 must be 64 hex digits", e.name));
        }
    }
    Ok(list)
}

/// "Install Link ▸ from WASM": one component as a `wasm` package named
/// `name` (version `0+<sha256 prefix>`), so it takes the same path as a zip.
pub fn wrap_component(name: &str, wasm: &[u8]) -> Result<Vec<u8>, String> {
    use std::io::Write;
    use zip::write::SimpleFileOptions;
    if wasm.len() > MAX_ZIP {
        return Err(format!("component larger than {} MiB", MAX_ZIP >> 20));
    }
    let sha = hex::encode(Sha256::digest(wasm));
    let manifest = serde_json::json!({
        "name": name,
        "version": format!("0+{}", &sha[..12]),
        "wyrm_link": wyrm_link_sdk::LINK_PROTOCOL,
        "kind": "wasm",
        "entry": "component.wasm",
    });
    let mut w = zip::ZipWriter::new(Cursor::new(Vec::new()));
    let opt = SimpleFileOptions::default().compression_method(zip::CompressionMethod::Stored);
    let mut put = |path: &str, data: &[u8]| -> Result<(), String> {
        w.start_file(path, opt).map_err(|e| e.to_string())?;
        w.write_all(data).map_err(|e| e.to_string())
    };
    put(MANIFEST, manifest.to_string().as_bytes())?;
    put("component.wasm", wasm)?;
    Ok(w.finish().map_err(|e| e.to_string())?.into_inner())
}

/// Key of this host in a manifest's `entries`: `<os>-<arch>`
/// (`linux-aarch64`, `macos-aarch64`, `linux-x86_64`).
pub fn platform() -> String {
    format!("{}-{}", std::env::consts::OS, std::env::consts::ARCH)
}

/// Directory of an installed package.
pub fn dir(root: &Path, def: &PackageDef) -> PathBuf {
    root.join(&def.name).join(&def.version)
}

/// A checked package in a temp directory, not yet in place. Dropped
/// without [`Unpacked::commit`], it removes the temp directory.
pub struct Unpacked {
    pub def: PackageDef,
    tmp: PathBuf,
}

impl Unpacked {
    /// Move into `<root>/<name>/<version>`; an installed version is refused.
    pub fn commit(self, root: &Path) -> Result<PathBuf, String> {
        let to = dir(root, &self.def);
        if to.exists() {
            return Err(format!(
                "{} {} is already installed",
                self.def.name, self.def.version
            ));
        }
        std::fs::create_dir_all(root.join(&self.def.name)).map_err(|e| e.to_string())?;
        std::fs::rename(&self.tmp, &to).map_err(|e| e.to_string())?;
        Ok(to)
    }
}

impl Drop for Unpacked {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.tmp);
    }
}

fn valid_version(v: &str) -> bool {
    !v.is_empty()
        && v.len() <= 32
        && !v.starts_with('.')
        && v.bytes()
            .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'.' | b'_' | b'-' | b'+'))
}

/// Unpack `zip` into a new temp directory under `root` and check it: size
/// and file limits, safe relative paths, no symlinks, a manifest for this
/// link protocol, and an entry for this host. `source` and `now` go into
/// the returned [`PackageDef`].
pub fn unpack(zip: &[u8], root: &Path, source: &str, now: u64) -> Result<Unpacked, String> {
    if zip.len() > MAX_ZIP {
        return Err(format!("zip larger than {} MiB", MAX_ZIP >> 20));
    }
    let mut archive = zip::ZipArchive::new(Cursor::new(zip)).map_err(|e| format!("zip: {e}"))?;
    if archive.len() > MAX_FILES {
        return Err(format!("more than {MAX_FILES} files"));
    }
    std::fs::create_dir_all(root).map_err(|e| e.to_string())?;
    let mut rnd = [0u8; 8];
    getrandom::fill(&mut rnd).map_err(|e| e.to_string())?;
    let tmp = root.join(format!(".tmp-{}", hex::encode(rnd)));
    std::fs::create_dir(&tmp).map_err(|e| e.to_string())?;
    // From here on, Drop cleans up.
    let mut out = Unpacked {
        def: PackageDef {
            name: String::new(),
            version: String::new(),
            kind: PackageKind::Process,
            entry: String::new(),
            args: Vec::new(),
            sha256: hex::encode(Sha256::digest(zip)),
            source: source.to_owned(),
            description: String::new(),
            installed: now,
            requester: Vec::new(),
        },
        tmp,
    };
    let mut total = 0u64;
    for i in 0..archive.len() {
        let mut f = archive.by_index(i).map_err(|e| format!("zip: {e}"))?;
        let rel = f
            .enclosed_name()
            .ok_or_else(|| format!("unsafe path {:?}", f.name()))?;
        if f.is_symlink() {
            return Err(format!("{}: symlinks are not allowed", rel.display()));
        }
        let path = out.tmp.join(&rel);
        if f.is_dir() {
            std::fs::create_dir_all(&path).map_err(|e| e.to_string())?;
            continue;
        }
        if !f.is_file() {
            return Err(format!("{}: not a regular file", rel.display()));
        }
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
        }
        let mut w = std::fs::File::create(&path).map_err(|e| e.to_string())?;
        let left = MAX_UNPACKED - total;
        // Read one byte past the budget to tell "fits" from "too big".
        let mut limited = (&mut f).take(left + 1);
        let n =
            std::io::copy(&mut limited, &mut w).map_err(|e| format!("{}: {e}", rel.display()))?;
        if n > left {
            return Err(format!("unpacked size over {} MiB", MAX_UNPACKED >> 20));
        }
        total += n;
        w.flush().map_err(|e| e.to_string())?;
    }
    let text = std::fs::read_to_string(out.tmp.join(MANIFEST))
        .map_err(|_| format!("no {MANIFEST} at the zip root"))?;
    let m: Manifest = serde_json::from_str(&text).map_err(|e| format!("{MANIFEST}: {e}"))?;
    crate::registry::validate_link_id(&m.name).map_err(|e| format!("name: {e}"))?;
    if !valid_version(&m.version) {
        return Err(format!("version {:?}: 1-32 of [A-Za-z0-9._+-]", m.version));
    }
    if m.wyrm_link != wyrm_link_sdk::LINK_PROTOCOL {
        return Err(format!(
            "built for link protocol {}, this broker speaks {}",
            m.wyrm_link,
            wyrm_link_sdk::LINK_PROTOCOL
        ));
    }
    let (kind, entry) = match m.kind.as_str() {
        "process" => {
            let p = platform();
            let e = m
                .entries
                .get(&p)
                .ok_or_else(|| format!("no entry for this host ({p})"))?;
            (PackageKind::Process, e.clone())
        }
        "wasm" => (
            PackageKind::Wasm,
            m.entry.clone().ok_or("a wasm package needs `entry`")?,
        ),
        k => return Err(format!("kind {k:?}: process or wasm")),
    };
    // The entry must be one of the unpacked regular files.
    let entry_path = out.tmp.join(&entry);
    let inside = Path::new(&entry)
        .components()
        .all(|c| matches!(c, std::path::Component::Normal(_)));
    if !inside || !entry_path.is_file() {
        return Err(format!("entry {entry}: not a file of the package"));
    }
    #[cfg(unix)]
    if kind == PackageKind::Process {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(&entry_path, std::fs::Permissions::from_mode(0o755))
            .map_err(|e| e.to_string())?;
    }
    for g in &m.requester {
        let level = wyrm_core::Perm::ALL
            .iter()
            .copied()
            .find(|p| p.name() == g.level && *p != wyrm_core::Perm::None)
            .ok_or_else(|| format!("requester level {:?}: list, read or write", g.level))?;
        crate::registry::check_grant(&g.path, level).map_err(|e| format!("requester: {e}"))?;
        // A package names the branches it needs; a whole root (every link,
        // every flow) only an operator grants, with Grant Access.
        if matches!(g.path.as_str(), "wy/{site}/down" | "wy/{site}/flows") {
            return Err(format!(
                "requester {}: name a link or flow under it (a whole root needs Grant Access)",
                g.path
            ));
        }
        out.def.requester.push((g.path.clone(), level.code()));
    }
    out.def.name = m.name;
    out.def.version = m.version;
    out.def.description = m.description;
    out.def.kind = kind;
    out.def.entry = entry;
    out.def.args = m.args;
    Ok(out)
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;
    use std::io::Write;
    use zip::write::SimpleFileOptions;

    /// A zip of `(path, content, unix mode)` entries.
    pub(crate) fn zip_of(files: &[(&str, &[u8], u32)]) -> Vec<u8> {
        let mut w = zip::ZipWriter::new(Cursor::new(Vec::new()));
        for (path, data, mode) in files {
            w.start_file(*path, SimpleFileOptions::default().unix_permissions(*mode))
                .unwrap();
            w.write_all(data).unwrap();
        }
        w.finish().unwrap().into_inner()
    }

    fn manifest(extra: &str) -> Vec<u8> {
        format!(
            r#"{{ "name": "demo", "version": "1.0.0", "wyrm_link": {}, "kind": "process",
                 "entries": {{ "{}": "bin/run" }}, "args": ["link", "mock"] {extra} }}"#,
            wyrm_link_sdk::LINK_PROTOCOL,
            platform()
        )
        .into_bytes()
    }

    fn root(name: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("wyrm-pkg-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        d
    }

    #[test]
    fn unpack_check_commit() {
        let root = root("ok");
        let z = zip_of(&[
            (MANIFEST, &manifest(""), 0o644),
            ("bin/run", b"#!/bin/sh\n", 0o644),
        ]);
        let u = unpack(&z, &root, "zip", 7).unwrap();
        assert_eq!(u.def.name, "demo");
        assert_eq!(u.def.entry, "bin/run");
        assert_eq!(u.def.args, ["link", "mock"]);
        assert_eq!(u.def.sha256.len(), 64);
        let dir = u.commit(&root).unwrap();
        assert!(dir.join("bin/run").is_file());
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mode = std::fs::metadata(dir.join("bin/run"))
                .unwrap()
                .permissions()
                .mode();
            assert_eq!(mode & 0o777, 0o755, "entry is executable");
        }
        // the same version again is refused; no temp dir is left
        let again = unpack(&z, &root, "zip", 8).unwrap();
        assert!(again.commit(&root).is_err());
        let left: Vec<_> = std::fs::read_dir(&root)
            .unwrap()
            .filter_map(|e| e.ok())
            .filter(|e| e.file_name().to_string_lossy().starts_with(".tmp"))
            .collect();
        assert!(left.is_empty(), "temp dirs removed");
    }

    #[test]
    fn repository_index() {
        let h = "a".repeat(64);
        let ok =
            format!(r#"[{{"name":"m1","version":"1","url":"https://x/m1.zip","sha256":"{h}"}}]"#);
        assert_eq!(parse_index(ok.as_bytes()).unwrap()[0].name, "m1");
        for bad in [
            r#"[{"name":"m1","version":"1","url":"u","sha256":"zz"}]"#.to_string(),
            format!(r#"[{{"name":"../x","version":"1","url":"u","sha256":"{h}"}}]"#),
            format!(
                r#"[{{"name":"m","version":"1","url":"u","sha256":"{h}"}},{{"name":"m","version":"2","url":"u","sha256":"{h}"}}]"#
            ),
            "{}".to_string(),
        ] {
            assert!(parse_index(bad.as_bytes()).is_err(), "{bad}");
        }
    }

    #[test]
    fn bad_packages_are_refused() {
        let root = root("bad");
        let run: (&str, &[u8], u32) = ("bin/run", b"x", 0o644);
        let cases: Vec<(Vec<u8>, &str)> = vec![
            (zip_of(&[run]), "no wyrm-link.json"),
            (
                zip_of(&[(MANIFEST, br#"{"name":"demo"}"#, 0o644), run]),
                "wyrm-link.json:",
            ),
            (
                zip_of(&[
                    (MANIFEST, &manifest(""), 0o644),
                    ("../evil", b"x", 0o644),
                ]),
                "unsafe path",
            ),
            (
                zip_of(&[(
                    MANIFEST,
                    br#"{ "name": "demo", "version": "1", "wyrm_link": 999, "kind": "process", "entries": {} }"#,
                    0o644,
                )]),
                "link protocol",
            ),
            (zip_of(&[(MANIFEST, &manifest(""), 0o644)]), "not a file of the package"),
            (b"not a zip".to_vec(), "zip:"),
        ];
        // Requested grants: a whole root, sys and config are refused.
        let grant = |path: &str, level: &str| {
            let m = manifest(&format!(
                r#", "requester": [{{"path": "{path}", "level": "{level}"}}]"#
            ));
            zip_of(&[(MANIFEST, &m, 0o644), ("bin/run", b"x", 0o755)])
        };
        let cases = cases.into_iter().chain([
            (
                grant("wy/{site}/down", "read"),
                "a whole root needs Grant Access",
            ),
            (
                grant("wy/{site}/flows", "list"),
                "a whole root needs Grant Access",
            ),
            (grant("wy/{site}/sys", "read"), "never sys"),
            (grant("wy/{site}/down/mock", "config"), "at most write"),
        ]);
        for (z, why) in cases {
            let err = unpack(&z, &root, "zip", 0).err().unwrap_or_default();
            assert!(err.contains(why), "{why}: got {err:?}");
        }
        let symlink = {
            let mut w = zip::ZipWriter::new(Cursor::new(Vec::new()));
            w.start_file(MANIFEST, SimpleFileOptions::default())
                .unwrap();
            w.write_all(&manifest("")).unwrap();
            w.add_symlink("bin/run", "/etc/passwd", SimpleFileOptions::default())
                .unwrap();
            w.finish().unwrap().into_inner()
        };
        let err = unpack(&symlink, &root, "zip", 0).err().unwrap_or_default();
        assert!(err.contains("symlink"), "{err}");
    }
}
