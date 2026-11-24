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
use std::collections::BTreeMap;
use std::io::{Cursor, Read, Write};
use std::path::{Path, PathBuf};
use wyrm_core::Value;
use wyrm_link_sdk::package::{Capabilities, Manifest, PackageForm, PackageWorld};
use wyrm_wasm_host::ComponentWorld;

// The format is the SDK's (ADR 0021): `wyr` builds what this checks.
pub use wyrm_link_sdk::package::{platform, RepoEntry, MANIFEST, MAX_INDEX, MAX_ZIP};
pub(crate) const MAX_UNPACKED: u64 = 256 << 20;
const MAX_FILES: usize = 1000;
/// Driver name of a link that runs a package: `pkg:<package>`.
pub const DRIVER_PREFIX: &str = "pkg:";

/// Why a package or a repository index is refused, or was not packed,
/// unpacked or put in place. Where the text is another module's (the SDK's
/// format rules, the registry's name and grant rules), the variant says
/// which rule and carries that text.
#[derive(Debug, thiserror::Error)]
pub enum PackageError {
    /// The repository index breaks the SDK's rules; as the SDK says it.
    #[error("{0}")]
    Index(String),
    /// A package of the index has a name no link may take.
    #[error("index: {0}")]
    IndexName(String),
    /// The component is larger than a package zip may be (MiB).
    #[error("component larger than {0} MiB")]
    ComponentTooLarge(usize),
    /// The component was not packed; as the SDK says it.
    #[error("{0}")]
    Pack(String),
    /// The zip is larger than a package zip may be (MiB).
    #[error("zip larger than {0} MiB")]
    ZipTooLarge(usize),
    /// More files than a package may have.
    #[error("more than {0} files")]
    TooManyFiles(usize),
    /// The files of a directory are larger in all than a package may be (MiB).
    #[error("package over {0} MiB")]
    PackageTooLarge(u64),
    /// The files of the zip are larger unpacked than a package may be (MiB).
    #[error("unpacked size over {0} MiB")]
    UnpackedTooLarge(u64),
    /// The zip does not read as one.
    #[error("zip: {0}")]
    Zip(#[source] zip::result::ZipError),
    /// The zip of a directory was not written.
    #[error("{0}")]
    ZipWrite(#[source] zip::result::ZipError),
    #[error("{0}")]
    ZipWriteIo(#[source] std::io::Error),
    /// A name in the zip that leaves the package's directory; the name as
    /// the archive reader shows it.
    #[error("unsafe path {0}")]
    UnsafePath(String),
    #[error("{}: symlinks are not allowed", .0.display())]
    Symlink(PathBuf),
    /// A socket, a FIFO, a device, or (in a directory) a symlink.
    #[error("{}: not a regular file", .0.display())]
    NotRegular(PathBuf),
    /// A file or directory was not read or written; the text names it.
    #[error("{}: {source}", .path.display())]
    File {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    /// A file or directory was not read, made or moved; the text is the
    /// system's alone.
    #[error("{source}")]
    Io {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("{0}")]
    Random(#[source] wyrm_core::rand::NoRandomness),
    #[error("no {MANIFEST} at the zip root")]
    NoManifest(#[source] std::io::Error),
    /// The manifest is no JSON of a manifest.
    #[error("{MANIFEST}: {0}")]
    ManifestJson(#[source] serde_json::Error),
    /// The package's name is one no link may take.
    #[error("name: {0}")]
    Name(String),
    /// The manifest breaks the SDK's rules (link protocol, version, state
    /// formats, capabilities); as the SDK says it.
    #[error("{0}")]
    Manifest(String),
    /// A process package with no entry for this host's platform.
    #[error("no entry for this host ({0})")]
    NoEntryForHost(String),
    #[error("a wasm package needs `entry`")]
    NoWasmEntry,
    /// The entry names no regular file inside the package.
    #[error("entry {0}: not a file of the package")]
    EntryNotFile(String),
    #[error("{entry}: {source}")]
    EntryNotRead {
        entry: String,
        #[source]
        source: std::io::Error,
    },
    /// The entry of a `wasm` package is no component this broker runs.
    #[error("{entry}: {source}")]
    Component {
        entry: String,
        #[source]
        source: wyrm_wasm_host::Error,
    },
    /// An app component of a `wyrm:app/host` version no package names.
    #[error("{entry}: wyrm:app@{version}: not a world a package names")]
    AppVersion {
        entry: String,
        version: &'static str,
    },
    /// The manifest names another world than the component's (`actual` as
    /// the manifest would say it: with the version when it names one).
    #[error(
        "invalid_parameter: the manifest says world \"{said}\", the component is \"{actual}\""
    )]
    World {
        said: PackageWorld,
        actual: PackageWorld,
    },
    #[error(
        "invalid_parameter: capabilities: only an app component has them, this one is \"{0}\""
    )]
    CapabilitiesNotApp(PackageWorld),
    /// `capabilities.net` does not parse as the link will parse it.
    #[error("invalid_parameter: capabilities.net: {0}")]
    Net(String),
    /// A requested grant with no level; the level's name.
    #[error("requester level {0:?}: list, read or write")]
    RequesterLevel(String),
    /// A requested grant the registry refuses (never `sys`, at most write).
    #[error("requester: {0}")]
    Requester(String),
    /// A requested grant on a whole root.
    #[error("requester {0}: name a link or flow under it (a whole root needs Grant access)")]
    RequesterRoot(String),
    #[error("{name} {version} is already installed")]
    AlreadyInstalled { name: String, version: String },
}

/// Parse and check a repository index (the SDK's rules), with names a
/// link may take here.
pub fn parse_index(bytes: &[u8]) -> Result<Vec<RepoEntry>, PackageError> {
    let list = wyrm_link_sdk::package::parse_index(bytes).map_err(PackageError::Index)?;
    for e in &list {
        crate::registry::validate_link_id(&e.name)
            .map_err(|e| PackageError::IndexName(e.to_string()))?;
    }
    Ok(list)
}

/// "Install Link ▸ from WASM": one component as a `wasm` package named
/// `name` (version `0+<sha256 prefix>`), so it takes the same path as a zip.
pub fn wrap_component(name: &str, wasm: &[u8]) -> Result<Vec<u8>, PackageError> {
    if wasm.len() > MAX_ZIP {
        return Err(PackageError::ComponentTooLarge(MAX_ZIP >> 20));
    }
    let sha = wyrm_link_sdk::package::sha256_hex(wasm);
    let manifest = Manifest {
        state: None,
        reads_state: None,
        name: name.to_owned(),
        version: format!("0+{}", &sha[..12]),
        description: String::new(),
        wyrm_link: wyrm_link_sdk::LINK_PROTOCOL,
        kind: PackageForm::Wasm,
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
    .map_err(PackageError::Pack)
}

/// The files of a package directory as a zip again: the same bytes for
/// the same files (sorted paths, fixed times, mode 0755 for what the owner
/// may execute and 0644 for the rest), within the bounds of a package zip.
/// A package that arrives in a backup as files (ADR 0048 §3.5) is packed
/// with this and then goes through [`unpack`], the validator of every
/// install; two directories with the same files give the same SHA-256.
pub fn repack(dir: &Path) -> Result<Vec<u8>, PackageError> {
    use std::io::Write;
    use zip::write::SimpleFileOptions;
    fn walk(root: &Path, rel: &Path, out: &mut Vec<PathBuf>) -> Result<(), PackageError> {
        let at = root.join(rel);
        let mut entries: Vec<_> = match std::fs::read_dir(&at) {
            Ok(rd) => rd.flatten().collect(),
            Err(source) => return Err(PackageError::File { path: at, source }),
        };
        entries.sort_by_key(|e| e.file_name());
        for e in entries {
            let path = rel.join(e.file_name());
            // not followed: a link out of the directory is no file of it
            let meta = match e.metadata() {
                Ok(m) => m,
                Err(source) => return Err(PackageError::Io { path, source }),
            };
            if meta.is_dir() {
                walk(root, &path, out)?;
            } else if meta.is_file() {
                out.push(path);
            } else {
                return Err(PackageError::NotRegular(path));
            }
            if out.len() > MAX_FILES {
                return Err(PackageError::TooManyFiles(MAX_FILES));
            }
        }
        Ok(())
    }
    let mut files = Vec::new();
    walk(dir, Path::new(""), &mut files)?;
    let mut w = zip::ZipWriter::new(Cursor::new(Vec::new()));
    let mut total = 0u64;
    for rel in files {
        let path = dir.join(&rel);
        let meta = match std::fs::metadata(&path) {
            Ok(m) => m,
            Err(source) => return Err(PackageError::File { path, source }),
        };
        total += meta.len();
        if total > MAX_UNPACKED {
            return Err(PackageError::PackageTooLarge(MAX_UNPACKED >> 20));
        }
        #[cfg(unix)]
        let exec = std::os::unix::fs::PermissionsExt::mode(&meta.permissions()) & 0o100 != 0;
        #[cfg(not(unix))]
        let exec = false;
        let name = rel
            .components()
            .map(|c| c.as_os_str().to_string_lossy().into_owned())
            .collect::<Vec<_>>()
            .join("/");
        let opt = SimpleFileOptions::default()
            .compression_method(zip::CompressionMethod::Deflated)
            .last_modified_time(zip::DateTime::default())
            .unix_permissions(if exec { 0o755 } else { 0o644 });
        w.start_file(name, opt).map_err(PackageError::ZipWrite)?;
        let bytes = match std::fs::read(&path) {
            Ok(b) => b,
            Err(source) => return Err(PackageError::File { path, source }),
        };
        w.write_all(&bytes).map_err(PackageError::ZipWriteIo)?;
    }
    let zip = w.finish().map_err(PackageError::ZipWrite)?.into_inner();
    if zip.len() > MAX_ZIP {
        return Err(PackageError::ZipTooLarge(MAX_ZIP >> 20));
    }
    Ok(zip)
}

/// Directory of an installed package.
pub fn dir(root: &Path, def: &PackageDef) -> PathBuf {
    root.join(&def.name).join(&def.version)
}

/// Remove what an install or a git fetch that never ended left under
/// `root`: `.tmp-*` and `.git-*` directories, and every version directory
/// that neither a package of `known` nor its kept previous version names
/// (a broker that ended between the move of the files and the registry
/// record; ADR 0048 §1). Call it at a start, before anything installs.
/// Returns what it removed, relative to `root`.
pub fn clean_orphans(
    root: &Path,
    known: &std::collections::BTreeMap<String, PackageDef>,
) -> Vec<String> {
    let mut removed = Vec::new();
    let mut gone = |path: &Path| {
        if let Err(e) = crate::nofollow::remove_any(path) {
            tracing::warn!(path = %path.display(), "an orphan of an install stays: {e}");
            return;
        }
        if let Ok(rel) = path.strip_prefix(root) {
            removed.push(rel.to_string_lossy().into_owned());
        }
    };
    for e in std::fs::read_dir(root).into_iter().flatten().flatten() {
        let name = e.file_name().to_string_lossy().into_owned();
        if name.starts_with(".tmp-") || name.starts_with(".git-") {
            gone(&e.path());
            continue;
        }
        // the component store and anything else that is not a package
        if name.starts_with('.') || !e.path().is_dir() {
            continue;
        }
        let Some(def) = known.get(&name) else {
            gone(&e.path());
            continue;
        };
        let kept = def.previous.as_deref().map(|p| p.def.version.as_str());
        for v in std::fs::read_dir(e.path()).into_iter().flatten().flatten() {
            let version = v.file_name().to_string_lossy().into_owned();
            if version != def.version && Some(version.as_str()) != kept {
                gone(&v.path());
            }
        }
    }
    removed.sort();
    removed
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
    /// The store formats this version reads (`wyrm-link.json` `reads_state`,
    /// ADR 0048); what it writes is `def.state`.
    pub reads_state: Vec<u32>,
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
    pub fn commit(self, root: &Path) -> Result<PathBuf, PackageError> {
        let to = dir(root, &self.def);
        if to.exists() {
            return Err(PackageError::AlreadyInstalled {
                name: self.def.name.clone(),
                version: self.def.version.clone(),
            });
        }
        let parent = root.join(&self.def.name);
        if let Err(source) = std::fs::create_dir_all(&parent) {
            return Err(PackageError::Io {
                path: parent,
                source,
            });
        }
        if let Err(source) = std::fs::rename(&self.tmp, &to) {
            return Err(PackageError::Io { path: to, source });
        }
        Ok(to)
    }
}

impl Drop for Unpacked {
    fn drop(&mut self) {
        wyrm_core::files::discard_dir(&self.tmp);
    }
}

/// The world of a `wasm` package's component, against the manifest: `Some`
/// capabilities for an app, `None` for a driver or point component. A world
/// in the manifest must be the component's (`wyrm:app@<v>`: also its version,
/// ADR 0030; plain `app`: any version); capabilities belong to an app and
/// their `net` must parse as the link will parse it.
fn wasm_world(
    m: &Manifest,
    path: &Path,
    entry: &str,
) -> Result<Option<Capabilities>, PackageError> {
    let component = |source| PackageError::Component {
        entry: entry.to_owned(),
        source,
    };
    let bytes = std::fs::read(path).map_err(|source| PackageError::EntryNotRead {
        entry: entry.to_owned(),
        source,
    })?;
    let world = wyrm_wasm_host::component_world(&bytes).map_err(component)?;
    let actual = match world {
        // a `wyrm:app/host` version this broker does not run is refused here
        ComponentWorld::App => {
            let v = wyrm_wasm_host::app_version(&bytes).map_err(component)?;
            PackageWorld::of_app_version(v).ok_or_else(|| PackageError::AppVersion {
                entry: entry.to_owned(),
                version: v,
            })?
        }
        ComponentWorld::Driver => PackageWorld::Driver,
        ComponentWorld::Point => PackageWorld::Point,
    };
    if let Some(w) = m.world.filter(|w| !w.admits(actual)) {
        // said as the manifest says it: with the version when it names one
        let shown = if w.app_version().is_some() {
            actual
        } else {
            actual.plain()
        };
        return Err(PackageError::World {
            said: w,
            actual: shown,
        });
    }
    if world != ComponentWorld::App {
        if m.capabilities.is_some() {
            return Err(PackageError::CapabilitiesNotApp(actual));
        }
        return Ok(None);
    }
    let caps = m.capabilities.clone().unwrap_or_default();
    check_net(&caps)?;
    Ok(Some(caps))
}

/// `capabilities.net` parses as the link will parse it.
fn check_net(caps: &Capabilities) -> Result<(), PackageError> {
    wyrm_wasm_host::NetPolicy::parse(&caps.net.join(","))
        .map(|_| ())
        .map_err(PackageError::Net)
}

/// Unpack `zip` into a new temp directory under `root` and check it: size
/// and file limits, safe relative paths, no symlinks, a manifest for this
/// link protocol, and an entry for this host. `source` and `now` go into
/// the returned [`PackageDef`].
pub fn unpack(zip: &[u8], root: &Path, source: &str, now: u64) -> Result<Unpacked, PackageError> {
    /// A failure the text does not name the path of.
    fn io(path: &Path) -> impl FnOnce(std::io::Error) -> PackageError + '_ {
        move |source| PackageError::Io {
            path: path.to_owned(),
            source,
        }
    }
    if zip.len() > MAX_ZIP {
        return Err(PackageError::ZipTooLarge(MAX_ZIP >> 20));
    }
    let mut archive = zip::ZipArchive::new(Cursor::new(zip)).map_err(PackageError::Zip)?;
    if archive.len() > MAX_FILES {
        return Err(PackageError::TooManyFiles(MAX_FILES));
    }
    std::fs::create_dir_all(root).map_err(io(root))?;
    let mut rnd = [0u8; 8];
    wyrm_core::rand::fill(&mut rnd).map_err(PackageError::Random)?;
    let tmp = root.join(format!(".tmp-{}", hex::encode(rnd)));
    std::fs::create_dir(&tmp).map_err(io(&tmp))?;
    // From here on, Drop cleans up.
    let mut out = Unpacked {
        def: PackageDef {
            name: String::new(),
            version: String::new(),
            kind: PackageKind::Process,
            entry: String::new(),
            args: Vec::new(),
            sha256: wyrm_core::hex::sha256_hex(zip),
            source: source.to_owned(),
            description: String::new(),
            installed: now,
            requester: Vec::new(),
            state: wyrm_link_sdk::package::DEFAULT_STATE,
            previous: None,
            last_update: None,
        },
        app: None,
        reads_state: vec![wyrm_link_sdk::package::DEFAULT_STATE],
        tmp,
    };
    let mut total = 0u64;
    for i in 0..archive.len() {
        let mut f = archive.by_index(i).map_err(PackageError::Zip)?;
        let rel = f
            .enclosed_name()
            .ok_or_else(|| PackageError::UnsafePath(format!("{:?}", f.name())))?;
        if f.is_symlink() {
            return Err(PackageError::Symlink(rel));
        }
        let path = out.tmp.join(&rel);
        if f.is_dir() {
            std::fs::create_dir_all(&path).map_err(io(&path))?;
            continue;
        }
        if !f.is_file() {
            return Err(PackageError::NotRegular(rel));
        }
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent).map_err(io(parent))?;
        }
        let mut w = std::fs::File::create(&path).map_err(io(&path))?;
        let left = MAX_UNPACKED - total;
        // Read one byte past the budget to tell "fits" from "too big".
        let mut limited = (&mut f).take(left + 1);
        let n = match std::io::copy(&mut limited, &mut w) {
            Ok(n) => n,
            Err(source) => return Err(PackageError::File { path: rel, source }),
        };
        if n > left {
            return Err(PackageError::UnpackedTooLarge(MAX_UNPACKED >> 20));
        }
        total += n;
        w.flush().map_err(io(&path))?;
    }
    let text = std::fs::read_to_string(out.tmp.join(MANIFEST)).map_err(PackageError::NoManifest)?;
    let m: Manifest = serde_json::from_str(&text).map_err(PackageError::ManifestJson)?;
    crate::registry::validate_link_id(&m.name).map_err(|e| PackageError::Name(e.to_string()))?;
    m.check().map_err(PackageError::Manifest)?;
    let (kind, entry) = match m.kind {
        PackageForm::Process => {
            let p = platform();
            let Some(e) = m.entries.get(&p) else {
                return Err(PackageError::NoEntryForHost(p));
            };
            (PackageKind::Process, e.clone())
        }
        PackageForm::Wasm => (
            PackageKind::Wasm,
            m.entry.clone().ok_or(PackageError::NoWasmEntry)?,
        ),
    };
    // The entry must be one of the unpacked regular files.
    let entry_path = out.tmp.join(&entry);
    let inside = Path::new(&entry)
        .components()
        .all(|c| matches!(c, std::path::Component::Normal(_)));
    if !inside || !entry_path.is_file() {
        return Err(PackageError::EntryNotFile(entry));
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
            .map_err(io(&entry_path))?;
    }
    for g in &m.requester {
        let level = Some(g.level)
            .filter(|p| *p != wyrm_core::Perm::None)
            .ok_or_else(|| PackageError::RequesterLevel(g.level.name().to_owned()))?;
        crate::registry::check_grant(&g.path, level)
            .map_err(|e| PackageError::Requester(e.to_string()))?;
        // A package names the branches it needs; a whole root (every link,
        // every flow) only an operator grants, with Grant access.
        if matches!(
            g.path.as_str(),
            "wy/{site}/downstream" | "wy/{site}/dataflows"
        ) {
            return Err(PackageError::RequesterRoot(g.path.clone()));
        }
        out.def
            .requester
            .push(crate::registry::LinkGrant::new(g.path.clone(), level));
    }
    out.def.state = m.state();
    out.reads_state = m.reads_state();
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

    /// Review of PR 72, item 10: a broker that ended between the move of a
    /// package's files and its registry record leaves a version directory
    /// nothing names; the next install of that version said "is on disk
    /// with other content". A start removes what no record names.
    #[test]
    fn directories_no_record_names_are_removed_at_a_start() {
        let root = std::env::temp_dir().join(format!("wyrm-pkg-orphans-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        let put = |rel: &str| {
            let p = root.join(rel);
            std::fs::create_dir_all(p.parent().unwrap()).unwrap();
            std::fs::write(p, b"x").unwrap();
        };
        let def = |name: &str, version: &str| PackageDef {
            name: name.into(),
            version: version.into(),
            kind: PackageKind::Process,
            entry: "run".into(),
            args: Vec::new(),
            sha256: "00".into(),
            source: "zip".into(),
            description: String::new(),
            installed: 1,
            requester: Vec::new(),
            state: 1,
            previous: None,
            last_update: None,
        };
        let mut a = def("a", "1.1.0");
        a.previous = Some(Box::new(crate::registry::PreviousDef {
            def: def("a", "1.0.0"),
            keep_until: u64::MAX,
            replaced: 1,
            changes_state: false,
            points: Vec::new(),
        }));
        let known: std::collections::BTreeMap<String, PackageDef> = [a, def("b", "2.0.0")]
            .into_iter()
            .map(|d| (d.name.clone(), d))
            .collect();
        for rel in [
            "a/1.1.0/run",
            "a/1.0.0/run",
            "a/1.2.0/run",
            "b/2.0.0/run",
            "b/2.1.0/run",
            "c/1.0.0/run",
            ".tmp-0123/run",
            ".git-4567/x",
            ".wasm/a.wasm",
        ] {
            put(rel);
        }
        assert_eq!(
            clean_orphans(&root, &known),
            [".git-4567", ".tmp-0123", "a/1.2.0", "b/2.1.0", "c"]
        );
        for kept in ["a/1.1.0/run", "a/1.0.0/run", "b/2.0.0/run", ".wasm/a.wasm"] {
            assert!(root.join(kept).is_file(), "{kept}");
        }
        assert!(clean_orphans(&root, &known).is_empty());
        // a root that is not there yet
        assert!(clean_orphans(&root.join("none"), &known).is_empty());
    }
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
        assert!(matches!(
            again.commit(&root),
            Err(PackageError::AlreadyInstalled { name, version })
                if name == "demo" && version == "1.0.0"
        ));
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
        for world in ["", r#", "world": "app""#, r#", "world": "wyrm:app@0.1.0""#] {
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
        use PackageWorld as W;
        type Is = fn(&PackageError) -> bool;
        let cases: [(Vec<u8>, Is); 7] = [
            (wasm_zip(&driver_component(), r#", "world": "app""#), |e| {
                matches!(
                    e,
                    PackageError::World {
                        said: W::App,
                        actual: W::Driver
                    }
                )
            }),
            // the component is said as the manifest says a world: without a version
            (wasm_zip(&app_component(), r#", "world": "point""#), |e| {
                matches!(
                    e,
                    PackageError::World {
                        said: W::Point,
                        actual: W::App
                    }
                )
            }),
            // a versioned app world must be the component's version (ADR 0030)
            (
                wasm_zip(&app_component(), r#", "world": "wyrm:app@0.3.0""#),
                |e| {
                    matches!(
                        e,
                        PackageError::World {
                            said: W::App030,
                            actual: W::App010
                        }
                    )
                },
            ),
            (
                wasm_zip(&driver_component(), r#", "world": "wyrm:app@0.3.0""#),
                |e| {
                    matches!(
                        e,
                        PackageError::World {
                            said: W::App030,
                            actual: W::Driver
                        }
                    )
                },
            ),
            (
                wasm_zip(&driver_component(), r#", "capabilities": {}"#),
                |e| matches!(e, PackageError::CapabilitiesNotApp(W::Driver)),
            ),
            // the SDK's check of the manifest refuses it first, in its own words
            (
                wasm_zip(&app_component(), r#", "capabilities": { "net": ["host"] }"#),
                |e| matches!(e, PackageError::Manifest(why) if why.starts_with("capabilities.net")),
            ),
            (wasm_zip(b"junk", ""), |e| {
                matches!(
                    e,
                    PackageError::Component { entry, source: wyrm_wasm_host::Error::Invalid(_) }
                        if entry == "demo.wasm"
                )
            }),
        ];
        for (i, (zip, is)) in cases.into_iter().enumerate() {
            let err = unpack(&zip, &root, "zip", 0).err().expect("refused");
            assert!(is(&err), "case {i}: got {err:?}");
        }
    }

    /// Every refusal says what it said as text: these are the answers of the
    /// install actions (`{success, message}`), of a package update and of a
    /// restore, and the lines of the repository index in the log.
    #[test]
    fn refusals_read_as_before() {
        fn said(e: &PackageError, text: &str) {
            assert_eq!(e.to_string(), text);
        }
        type E = PackageError;
        let io = || std::io::Error::other("no");
        let p = || PathBuf::from("bin/run");
        let zip = || zip::result::ZipError::FileNotFound;
        said(&E::Index("index: m twice".into()), "index: m twice");
        said(
            &E::IndexName("link id: empty segment".into()),
            "index: link id: empty segment",
        );
        said(
            &E::ComponentTooLarge(MAX_ZIP >> 20),
            "component larger than 64 MiB",
        );
        said(&E::Pack("no".into()), "no");
        said(&E::ZipTooLarge(MAX_ZIP >> 20), "zip larger than 64 MiB");
        said(&E::TooManyFiles(MAX_FILES), "more than 1000 files");
        said(
            &E::PackageTooLarge(MAX_UNPACKED >> 20),
            "package over 256 MiB",
        );
        said(
            &E::UnpackedTooLarge(MAX_UNPACKED >> 20),
            "unpacked size over 256 MiB",
        );
        said(&E::Zip(zip()), "zip: specified file not found in archive");
        said(&E::ZipWrite(zip()), "specified file not found in archive");
        said(&E::ZipWriteIo(io()), "no");
        said(
            &E::UnsafePath(r#"Ok("../evil")"#.into()),
            r#"unsafe path Ok("../evil")"#,
        );
        said(&E::Symlink(p()), "bin/run: symlinks are not allowed");
        said(&E::NotRegular(p()), "bin/run: not a regular file");
        said(
            &E::File {
                path: p(),
                source: io(),
            },
            "bin/run: no",
        );
        said(
            &E::Io {
                path: p(),
                source: io(),
            },
            "no",
        );
        // `E::Random` shows its cause alone, as `e.to_string()` did; the cause
        // is made only by `wyrm_core::rand`
        said(&E::NoManifest(io()), "no wyrm-link.json at the zip root");
        let json = serde_json::from_str::<u8>("x").unwrap_err();
        said(
            &E::ManifestJson(json),
            "wyrm-link.json: expected value at line 1 column 1",
        );
        said(
            &E::Name("link id: empty segment".into()),
            "name: link id: empty segment",
        );
        said(&E::Manifest("no".into()), "no");
        said(
            &E::NoEntryForHost("linux-x86_64".into()),
            "no entry for this host (linux-x86_64)",
        );
        said(&E::NoWasmEntry, "a wasm package needs `entry`");
        said(
            &E::EntryNotFile("bin/run".into()),
            "entry bin/run: not a file of the package",
        );
        said(
            &E::EntryNotRead {
                entry: "demo.wasm".into(),
                source: io(),
            },
            "demo.wasm: no",
        );
        said(
            &E::Component {
                entry: "demo.wasm".into(),
                source: wyrm_wasm_host::Error::Invalid("no".into()),
            },
            "demo.wasm: invalid component: no",
        );
        said(
            &E::AppVersion {
                entry: "demo.wasm".into(),
                version: "0.9.0",
            },
            "demo.wasm: wyrm:app@0.9.0: not a world a package names",
        );
        said(
            &E::World {
                said: PackageWorld::App030,
                actual: PackageWorld::Driver,
            },
            r#"invalid_parameter: the manifest says world "wyrm:app@0.3.0", the component is "driver""#,
        );
        said(
            &E::CapabilitiesNotApp(PackageWorld::Point),
            r#"invalid_parameter: capabilities: only an app component has them, this one is "point""#,
        );
        said(
            &E::Net("no".into()),
            "invalid_parameter: capabilities.net: no",
        );
        said(
            &E::RequesterLevel("none".into()),
            r#"requester level "none": list, read or write"#,
        );
        said(&E::Requester("no".into()), "requester: no");
        said(
            &E::RequesterRoot("wy/{site}/downstream".into()),
            "requester wy/{site}/downstream: name a link or flow under it (a whole root needs Grant access)",
        );
        said(
            &E::AlreadyInstalled {
                name: "demo".into(),
                version: "1.0.0".into(),
            },
            "demo 1.0.0 is already installed",
        );
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
        .expect("refused");
        assert!(
            matches!(&err, PackageError::Manifest(why) if why.starts_with("capabilities.net")),
            "{err:?}"
        );
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
        type Is = fn(&PackageError) -> bool;
        let cases: Vec<(Vec<u8>, Is)> = vec![
            (zip_of(&[run]), |e| matches!(e, PackageError::NoManifest(_))),
            (
                zip_of(&[(MANIFEST, br#"{"name":"demo"}"#, 0o644), run]),
                |e| matches!(e, PackageError::ManifestJson(_)),
            ),
            (
                zip_of(&[
                    (MANIFEST, &manifest(""), 0o644),
                    ("../evil", b"x", 0o644),
                ]),
                |e| matches!(e, PackageError::UnsafePath(name) if name.contains("../evil")),
            ),
            (
                zip_of(&[(
                    MANIFEST,
                    br#"{ "name": "demo", "version": "1", "wyrm_link": 999, "kind": "process", "entries": {} }"#,
                    0o644,
                )]),
                |e| matches!(e, PackageError::Manifest(why) if why.contains("link protocol")),
            ),
            (zip_of(&[(MANIFEST, &manifest(""), 0o644)]), |e| {
                matches!(e, PackageError::EntryNotFile(entry) if entry == "bin/run")
            }),
            (b"not a zip".to_vec(), |e| matches!(e, PackageError::Zip(_))),
        ];
        // Requested grants: a whole root, sys and config are refused.
        let grant = |path: &str, level: &str| {
            let m = manifest(&format!(
                r#", "requester": [{{"path": "{path}", "level": "{level}"}}]"#
            ));
            zip_of(&[(MANIFEST, &m, 0o644), ("bin/run", b"x", 0o755)])
        };
        let more: [(Vec<u8>, Is); 5] = [
            (
                grant("wy/{site}/downstream", "read"),
                |e| matches!(e, PackageError::RequesterRoot(path) if path == "wy/{site}/downstream"),
            ),
            (
                grant("wy/{site}/dataflows", "list"),
                |e| matches!(e, PackageError::RequesterRoot(path) if path == "wy/{site}/dataflows"),
            ),
            // the registry's rules of a grant, in its own words
            (
                grant("wy/{site}/sys", "read"),
                |e| matches!(e, PackageError::Requester(why) if why.contains("never sys")),
            ),
            (
                grant("wy/{site}/downstream/mock", "config"),
                |e| matches!(e, PackageError::Requester(why) if why.contains("at most write")),
            ),
            (
                grant("wy/{site}/downstream/mock", "none"),
                |e| matches!(e, PackageError::RequesterLevel(level) if level == "none"),
            ),
        ];
        for (i, (z, is)) in cases.into_iter().chain(more).enumerate() {
            let err = unpack(&z, &root, "zip", 0).err().expect("refused");
            assert!(is(&err), "case {i}: got {err:?}");
        }
        // nothing of a refused package stays
        let left = std::fs::read_dir(&root).unwrap().count();
        assert_eq!(left, 0, "temp directories removed");
        let symlink = {
            let mut w = zip::ZipWriter::new(Cursor::new(Vec::new()));
            w.start_file(MANIFEST, SimpleFileOptions::default())
                .unwrap();
            w.write_all(&manifest("")).unwrap();
            w.add_symlink("bin/run", "/etc/passwd", SimpleFileOptions::default())
                .unwrap();
            w.finish().unwrap().into_inner()
        };
        let err = unpack(&symlink, &root, "zip", 0).err().expect("refused");
        assert!(
            matches!(&err, PackageError::Symlink(p) if p == Path::new("bin/run")),
            "{err:?}"
        );
    }
}
