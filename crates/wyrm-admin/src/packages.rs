//! Link packages (ADR 0011): a zip with `wyrm-link.json` at its root,
//! unpacked under `data_dir/packages/<name>/<version>/`.
//!
//! A package is checked in a temp directory first ([`unpack`]) and moved
//! into place in one rename ([`Unpacked::commit`]), so a failed install
//! leaves nothing behind.
//!
//! A `wasm` package's world comes from its component's exports
//! ([`wyrm_wasm_host::component_world`]), not from the manifest: an `app`
//! component (ADR 0023) runs as driver `app` with the manifest's
//! `capabilities` as link params ([`link_params`]); a `driver` or `point`
//! component runs on the framework `wasm` driver (ADR 0012). A `process`
//! package may carry `capabilities` too (a portable app run as a process):
//! they become its link params the same way, without `component`.

use crate::registry::{PackageDef, PackageKind};
use sha2::{Digest, Sha256};
use std::collections::BTreeMap;
use std::io::{Cursor, Read, Write};
use std::path::{Path, PathBuf};
use wyrm_core::Value;
use wyrm_link_sdk::package::{Capabilities, Manifest};
use wyrm_wasm_host::ComponentWorld;

// The format is the SDK's (ADR 0021): `wyr` builds what this checks.
pub use wyrm_link_sdk::package::{platform, RepoEntry, MANIFEST, MAX_INDEX, MAX_ZIP};
const MAX_UNPACKED: u64 = 256 << 20;
const MAX_FILES: usize = 1000;
/// Driver name of a link that runs a package: `pkg:<package>`.
pub const DRIVER_PREFIX: &str = "pkg:";

/// Parse and check a repository index (the SDK's rules), with names a
/// link may take here.
pub fn parse_index(bytes: &[u8]) -> Result<Vec<RepoEntry>, String> {
    let list = wyrm_link_sdk::package::parse_index(bytes)?;
    for e in &list {
        crate::registry::validate_link_id(&e.name).map_err(|x| format!("index: {x}"))?;
    }
    Ok(list)
}

/// "Install Link ▸ from WASM": one component as a `wasm` package named
/// `name` (version `0+<sha256 prefix>`), so it takes the same path as a zip.
pub fn wrap_component(name: &str, wasm: &[u8]) -> Result<Vec<u8>, String> {
    if wasm.len() > MAX_ZIP {
        return Err(format!("component larger than {} MiB", MAX_ZIP >> 20));
    }
    let sha = wyrm_link_sdk::package::sha256_hex(wasm);
    let manifest = Manifest {
        name: name.to_owned(),
        version: format!("0+{}", &sha[..12]),
        description: String::new(),
        wyrm_link: wyrm_link_sdk::LINK_PROTOCOL,
        kind: "wasm".into(),
        entries: Default::default(),
        args: Vec::new(),
        entry: Some("component.wasm".into()),
        requester: Vec::new(),
        world: None,
        capabilities: None,
    };
    wyrm_link_sdk::package::pack(
        &manifest,
        &[wyrm_link_sdk::package::PackFile {
            path: "component.wasm".into(),
            data: wasm.to_vec(),
            mode: 0o644,
        }],
    )
}

/// Directory of an installed package.
pub fn dir(root: &Path, def: &PackageDef) -> PathBuf {
    root.join(&def.name).join(&def.version)
}

/// A checked package in a temp directory, not yet in place. Dropped
/// without [`Unpacked::commit`], it removes the temp directory.
pub struct Unpacked {
    pub def: PackageDef,
    /// The capabilities that become the link's params: a `wasm` package of
    /// world `app` always has them (defaults when the manifest has none); a
    /// `process` package when its manifest names them (a portable app).
    /// `None`: a driver/point component or a process package without them.
    pub app: Option<Capabilities>,
    tmp: PathBuf,
}

/// The params of a new link on the package `name`: for an app (`app` = its
/// capabilities) `net` (the allowlist joined by `,`), `store_mb`,
/// `memory_mb` and `call_ms`, which the portable runtime takes out of the
/// params, so the app's own config starts empty, plus `component` for a
/// `wasm` one; for a driver or point component one connection `main` on it
/// (ADR 0012); `Null` for a process package without capabilities.
pub fn link_params(name: &str, kind: PackageKind, app: Option<&Capabilities>) -> Value {
    let map = |pairs: Vec<(&str, Value)>| {
        Value::Map(
            pairs
                .into_iter()
                .map(|(k, v)| (k.to_owned(), v))
                .collect::<BTreeMap<_, _>>(),
        )
    };
    match (kind, app) {
        (_, Some(c)) => {
            let mut v = vec![
                ("net", Value::Str(c.net.join(","))),
                ("store_mb", Value::UInt(c.store_mb().into())),
                ("memory_mb", Value::UInt(c.memory_mb().into())),
                ("call_ms", Value::UInt(c.call_ms().into())),
            ];
            if kind == PackageKind::Wasm {
                v.push(("component", Value::from(name)));
            }
            map(v)
        }
        (PackageKind::Process, None) => Value::Null,
        (PackageKind::Wasm, None) => map(vec![(
            "connections",
            map(vec![("main", map(vec![("component", Value::from(name))]))]),
        )]),
    }
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

/// The world of a `wasm` package's component, against the manifest: `Some`
/// capabilities for an app, `None` for a driver or point component. A world
/// in the manifest must be the component's; capabilities belong to an app
/// and their `net` must parse as the link will parse it.
fn wasm_world(m: &Manifest, path: &Path, entry: &str) -> Result<Option<Capabilities>, String> {
    let bytes = std::fs::read(path).map_err(|e| format!("{entry}: {e}"))?;
    let world = wyrm_wasm_host::component_world(&bytes).map_err(|e| format!("{entry}: {e}"))?;
    let actual = world.name();
    if let Some(w) = m.world.as_deref().filter(|w| *w != actual) {
        return Err(format!(
            "invalid_parameter: the manifest says world {w:?}, the component is {actual:?}"
        ));
    }
    if world != ComponentWorld::App {
        if m.capabilities.is_some() {
            return Err(format!(
                "invalid_parameter: capabilities: only an app component has them, this one is {actual:?}"
            ));
        }
        return Ok(None);
    }
    let caps = m.capabilities.clone().unwrap_or_default();
    check_net(&caps)?;
    Ok(Some(caps))
}

/// `capabilities.net` parses as the link will parse it.
fn check_net(caps: &Capabilities) -> Result<(), String> {
    wyrm_wasm_host::NetPolicy::parse(&caps.net.join(","))
        .map(|_| ())
        .map_err(|e| format!("invalid_parameter: capabilities.net: {e}"))
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
        app: None,
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
    m.check()?;
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
    if kind == PackageKind::Wasm {
        out.app = wasm_world(&m, &entry_path, &entry)?;
    } else if let Some(caps) = &m.capabilities {
        check_net(caps)?;
        out.app = Some(caps.clone());
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
        if matches!(
            g.path.as_str(),
            "wy/{site}/downstream" | "wy/{site}/dataflows"
        ) {
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

    /// A component exporting `exports` (names are all `component_world` reads), importing
    /// `wyrm:link/tcp` when `tcp`.
    fn component(exports: &[&str], tcp: bool) -> Vec<u8> {
        let mut text = String::from("(component ");
        if tcp {
            text += r#"(import "wyrm:link/tcp@0.1.0" (instance)) "#;
        }
        text += r#"(core module $m (func (export "f"))) (core instance $i (instantiate $m))"#;
        for e in exports {
            text += &format!(r#" (func (export "{e}") (canon lift (core func $i "f")))"#);
        }
        wat::parse_str(text + ")").expect("component WAT")
    }

    fn app_component() -> Vec<u8> {
        component(
            &[
                "start",
                "on-set",
                "on-invoke",
                "on-timer",
                "on-value",
                "on-reply",
                "stop",
            ],
            false,
        )
    }

    fn driver_component() -> Vec<u8> {
        component(&["init", "read", "write"], true)
    }

    /// A `wasm` package `demo` of `component` with `extra` manifest fields.
    fn wasm_zip(component: &[u8], extra: &str) -> Vec<u8> {
        let m = format!(
            r#"{{ "name": "demo", "version": "1.0.0", "wyrm_link": {}, "kind": "wasm",
                 "entry": "demo.wasm" {extra} }}"#,
            wyrm_link_sdk::LINK_PROTOCOL
        );
        zip_of(&[
            (MANIFEST, m.as_bytes(), 0o644),
            ("demo.wasm", component, 0o644),
        ])
    }

    #[test]
    fn install_picks_world_from_exports() {
        let root = root("world");
        let map = |pairs: Vec<(&str, Value)>| {
            Value::Map(pairs.into_iter().map(|(k, v)| (k.to_owned(), v)).collect())
        };
        // a driver component: the framework `wasm` driver, one connection on it
        let u = unpack(&wasm_zip(&driver_component(), ""), &root, "zip", 0).unwrap();
        assert_eq!(u.app, None);
        assert_eq!(
            link_params(&u.def.name, u.def.kind, u.app.as_ref()),
            map(vec![(
                "connections",
                map(vec![(
                    "main",
                    map(vec![("component", Value::from("demo"))])
                )])
            )])
        );
        // an app component (the manifest's world is optional): driver `app` params from its
        // capabilities, defaults for the rest
        for world in ["", r#", "world": "app""#] {
            let extra = format!(
                r#"{world}, "capabilities": {{ "store_mb": 4, "net": ["127.0.0.1:502"] }}"#
            );
            let u = unpack(&wasm_zip(&app_component(), &extra), &root, "zip", 0).unwrap();
            let caps = u.app.clone().expect("an app");
            assert_eq!(caps.store_mb, Some(4));
            assert_eq!(
                link_params(&u.def.name, u.def.kind, Some(&caps)),
                map(vec![
                    ("component", Value::from("demo")),
                    ("net", Value::from("127.0.0.1:502")),
                    ("store_mb", Value::UInt(4)),
                    ("memory_mb", Value::UInt(64)),
                    ("call_ms", Value::UInt(2000)),
                ])
            );
        }
        // "from WASM" (no manifest of its own): an app with the default capabilities
        let zip = wrap_component("demo", &app_component()).unwrap();
        let u = unpack(&zip, &root, "wasm", 0).unwrap();
        assert_eq!(u.app, Some(Default::default()));
        // refused: a world that lies, capabilities on a driver, a bad net entry, no component
        for (zip, why) in [
            (
                wasm_zip(&driver_component(), r#", "world": "app""#),
                r#"world "app", the component is "driver""#,
            ),
            (
                wasm_zip(&app_component(), r#", "world": "point""#),
                r#"world "point", the component is "app""#,
            ),
            (
                wasm_zip(&driver_component(), r#", "capabilities": {}"#),
                "capabilities: only an app component",
            ),
            (
                wasm_zip(&app_component(), r#", "capabilities": { "net": ["host"] }"#),
                "capabilities.net",
            ),
            (wasm_zip(b"junk", ""), "demo.wasm:"),
        ] {
            let err = unpack(&zip, &root, "zip", 0).err().unwrap_or_default();
            assert!(err.contains(why), "{why}: got {err:?}");
        }
    }

    /// A process package may carry capabilities (a portable app run as a
    /// process): the same params as its WASM twin, without `component`.
    #[test]
    fn process_capabilities_become_params() {
        let root = root("proccaps");
        let map = |pairs: Vec<(&str, Value)>| {
            Value::Map(pairs.into_iter().map(|(k, v)| (k.to_owned(), v)).collect())
        };
        let zip = |extra: &str| {
            zip_of(&[
                (MANIFEST, &manifest(extra), 0o644),
                ("bin/run", b"#!/bin/sh\n", 0o644),
            ])
        };
        let u = unpack(&zip(""), &root, "zip", 0).unwrap();
        assert_eq!(u.app, None);
        assert_eq!(link_params("demo", u.def.kind, None), Value::Null);
        let u = unpack(
            &zip(r#", "capabilities": { "store_mb": 2, "net": ["127.0.0.1:502"] }"#),
            &root,
            "zip",
            0,
        )
        .unwrap();
        assert_eq!(
            link_params(&u.def.name, u.def.kind, u.app.as_ref()),
            map(vec![
                ("net", Value::from("127.0.0.1:502")),
                ("store_mb", Value::UInt(2)),
                ("memory_mb", Value::UInt(64)),
                ("call_ms", Value::UInt(2000)),
            ])
        );
        let err = unpack(
            &zip(r#", "capabilities": { "net": ["host"] }"#),
            &root,
            "zip",
            0,
        )
        .err()
        .unwrap_or_default();
        assert!(err.contains("capabilities.net"), "{err}");
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
                grant("wy/{site}/downstream", "read"),
                "a whole root needs Grant Access",
            ),
            (
                grant("wy/{site}/dataflows", "list"),
                "a whole root needs Grant Access",
            ),
            (grant("wy/{site}/sys", "read"), "never sys"),
            (
                grant("wy/{site}/downstream/mock", "config"),
                "at most write",
            ),
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
