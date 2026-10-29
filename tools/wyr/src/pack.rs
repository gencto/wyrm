//! `wyr link pack` and `wyr repo add` (ADR 0021): a link package from the
//! crate's `Cargo.toml` (`[package.metadata.wyrm-link]`) and a repository
//! directory with its `index.json`, in the SDK's package format.
//!
//! `kind = "wasm"` (ADR 0023): the crate's cdylib built for
//! `wasm32-unknown-unknown` with feature `wasm`, made a component of world
//! `wyrm:app` in-process (`wit-component`), packed with its `capabilities`.

use crate::Error;
use clap::Subcommand;
use serde::Deserialize;
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::process::Command;
use wyrm_link_sdk::package::{self, Asset, Capabilities, Grant, Manifest, PackFile, RepoEntry};
use wyrm_wasm_host::ComponentWorld;

/// The target a `wasm` crate is built for.
const WASM_TARGET: &str = "wasm32-unknown-unknown";

#[derive(Subcommand, Debug)]
pub enum LinkCmd {
    /// Build the link's release binary and write one package zip per host,
    /// `<name>-<version>-<host>.zip`; for `kind = "wasm"`, build the crate
    /// as a component and write `<name>-<version>.zip`; or pack a prebuilt
    /// WASM component.
    Pack {
        /// The link crate's Cargo.toml.
        #[arg(long, default_value = "Cargo.toml")]
        manifest_path: PathBuf,
        /// The crate, when the manifest is a workspace's.
        #[arg(short, long)]
        package: Option<String>,
        /// Rust target triples to build for (one zip each); the host when
        /// none.
        #[arg(long = "target")]
        targets: Vec<String>,
        /// Use the binaries built before, without `cargo build`.
        #[arg(long)]
        no_build: bool,
        /// Override `kind` of `[package.metadata.wyrm-link]`.
        #[arg(long, value_parser = ["process", "wasm"])]
        kind: Option<String>,
        /// Where the zips go (default `<target dir>/wyrm-link`).
        #[arg(long)]
        out: Option<PathBuf>,
        /// Pack this WASM component instead of a crate (with --name and
        /// --version).
        #[arg(long, requires_all = ["name", "version"])]
        component: Option<PathBuf>,
        /// The package name: of the component, or instead of the crate's
        /// (for example the process form of a portable link beside its wasm
        /// form).
        #[arg(long)]
        name: Option<String>,
        #[arg(long)]
        version: Option<String>,
        #[arg(long, default_value = "")]
        description: String,
    },
}

#[derive(Subcommand, Debug)]
pub enum RepoCmd {
    /// Put package zips in a repository directory and update its
    /// `index.json`: a new version replaces the entry, the same version
    /// adds the zip's hosts to it.
    Add {
        zips: Vec<PathBuf>,
        /// The repository directory (created when missing).
        #[arg(long)]
        repo: PathBuf,
        /// Base URL for the index entries; without it they are relative to
        /// the index, and the directory can move as it is.
        #[arg(long)]
        url: Option<String>,
    },
}

/// `[package.metadata.wyrm-link]`: what Cargo does not say.
#[derive(Debug, Default, Deserialize)]
#[serde(deny_unknown_fields)]
struct Meta {
    /// Package name (default: the crate name).
    name: Option<String>,
    /// Default: the crate's description.
    description: Option<String>,
    /// `process` (a binary per host) or `wasm` (a `wyrm:app` component).
    #[serde(default = "process")]
    kind: String,
    /// The binary (default: the crate's only one).
    bin: Option<String>,
    /// Cargo features of a process build (a wasm build uses `wasm`).
    #[serde(default)]
    features: Vec<String>,
    #[serde(default)]
    args: Vec<String>,
    #[serde(default)]
    requester: Vec<Grant>,
    /// `wasm`: what the app link may use, granted at install (ADR 0023).
    capabilities: Option<Capabilities>,
}

fn process() -> String {
    "process".into()
}

/// The crate as `cargo metadata` describes it.
#[derive(Debug, Deserialize)]
struct CargoPackage {
    name: String,
    version: String,
    description: Option<String>,
    manifest_path: PathBuf,
    #[serde(default)]
    metadata: Option<serde_json::Value>,
    targets: Vec<CargoTarget>,
}

#[derive(Debug, Deserialize)]
struct CargoTarget {
    name: String,
    kind: Vec<String>,
}

#[derive(Debug, Deserialize)]
pub(crate) struct CargoMetadata {
    packages: Vec<CargoPackage>,
    target_directory: PathBuf,
}

/// What a crate build makes.
#[derive(Debug, PartialEq)]
enum Artifact {
    /// A process binary.
    Bin(String),
    /// A WASM component from this cdylib (its Rust name).
    Component(String),
}

/// What to build and how to name it, from the crate.
#[derive(Debug, PartialEq)]
struct Plan {
    krate: String,
    artifact: Artifact,
    features: Vec<String>,
    /// The manifest; a process one without `entries` (one host per zip).
    manifest: Manifest,
}

impl Plan {
    /// Another package name (`--name`); a component entry follows it.
    fn rename(&mut self, name: &str) -> Result<(), Error> {
        let m = &mut self.manifest;
        m.name = name.to_owned();
        if m.entry.is_some() {
            m.entry = Some(format!("{name}.wasm"));
        }
        package::valid_name(name).map_err(|e| format!("--name {name}: {e}").into())
    }
}

/// The plan of crate `p`; `kind` overrides the metadata's.
fn plan(p: &CargoPackage, kind: Option<&str>) -> Result<Plan, Error> {
    let mut meta: Meta = match p.metadata.as_ref().and_then(|m| m.get("wyrm-link")) {
        Some(v) => serde_json::from_value(v.clone())
            .map_err(|e| format!("[package.metadata.wyrm-link]: {e}"))?,
        None => Meta {
            kind: process(),
            ..Meta::default()
        },
    };
    if let Some(k) = kind {
        meta.kind = k.to_owned();
    }
    let name = meta.name.clone().unwrap_or_else(|| p.name.clone());
    let description = meta
        .description
        .clone()
        .or_else(|| p.description.clone())
        .unwrap_or_default();
    match meta.kind.as_str() {
        "process" => {}
        "wasm" => {
            let lib = p
                .targets
                .iter()
                .find(|t| t.kind.iter().any(|k| k == "cdylib"))
                .map(|t| t.name.replace('-', "_"))
                .ok_or_else(|| {
                    format!(
                        "{}: kind wasm needs a cdylib (crate-type = [\"cdylib\", \"rlib\"])",
                        p.name
                    )
                })?;
            let manifest = Manifest {
                entry: Some(format!("{name}.wasm")),
                name,
                version: p.version.clone(),
                description,
                wyrm_link: wyrm_link_sdk::LINK_PROTOCOL,
                kind: "wasm".into(),
                entries: BTreeMap::new(),
                args: Vec::new(),
                requester: meta.requester,
                world: Some("app".into()),
                capabilities: meta.capabilities,
            };
            // before a long build
            manifest.check().map_err(|e| format!("{}: {e}", p.name))?;
            return Ok(Plan {
                krate: p.name.clone(),
                artifact: Artifact::Component(lib),
                features: vec!["wasm".into()],
                manifest,
            });
        }
        k => return Err(format!("kind {k:?}: process or wasm").into()),
    }
    let bins: Vec<&str> = p
        .targets
        .iter()
        .filter(|t| t.kind.iter().any(|k| k == "bin"))
        .map(|t| t.name.as_str())
        .collect();
    let bin = match (meta.bin, bins.as_slice()) {
        (Some(b), _) if bins.contains(&b.as_str()) => b,
        (Some(b), _) => return Err(format!("{}: no binary {b}", p.name).into()),
        (None, [one]) => (*one).to_owned(),
        (None, []) => return Err(format!("{}: no binary to pack", p.name).into()),
        (None, _) => {
            return Err(format!(
                "{}: several binaries ({}): set bin in [package.metadata.wyrm-link]",
                p.name,
                bins.join(", ")
            )
            .into())
        }
    };
    Ok(Plan {
        krate: p.name.clone(),
        artifact: Artifact::Bin(bin),
        features: meta.features,
        manifest: Manifest {
            name,
            version: p.version.clone(),
            description,
            wyrm_link: wyrm_link_sdk::LINK_PROTOCOL,
            kind: "process".into(),
            entries: BTreeMap::new(),
            args: meta.args,
            entry: None,
            requester: meta.requester,
            world: None,
            capabilities: None,
        },
    })
}

/// A core module built with `wyrm-link-guest` as a component, which must be of world `wyrm:app`.
fn componentize(core: &[u8]) -> Result<Vec<u8>, Error> {
    let component = wit_component::ComponentEncoder::default()
        .module(core)
        .map_err(|e| format!("component type: {e:#} (is `wyrm_link_guest::export!` in the lib?)"))?
        .validate(true)
        .encode()
        .map_err(|e| format!("componentize: {e:#}"))?;
    match wyrm_wasm_host::component_world(&component) {
        Ok(ComponentWorld::App) => Ok(component),
        Ok(w) => Err(format!("the component is of world {}, not app", w.name()).into()),
        Err(e) => Err(format!("the component: {e}").into()),
    }
}

/// `kind = "wasm"`: build the cdylib for wasm32 with feature `wasm`, make it a component and
/// pack `<name>-<version>.zip` into `out`.
fn pack_component(
    plan: &Plan,
    lib: &str,
    manifest_path: &Path,
    target_dir: &Path,
    no_build: bool,
    out: &Path,
) -> Result<PathBuf, Error> {
    if !no_build {
        let mut c = Command::new("cargo");
        c.args(["build", "--release", "--lib", "-p", &plan.krate])
            .args(["--target", WASM_TARGET])
            .arg("--features")
            .arg(plan.features.join(","))
            .arg("--manifest-path")
            .arg(manifest_path)
            .arg("--target-dir")
            .arg(target_dir);
        if !c.status()?.success() {
            return Err(format!(
                "cargo build of {} for {WASM_TARGET} failed (rustup target add {WASM_TARGET})",
                plan.krate
            )
            .into());
        }
    }
    let wasm = target_dir
        .join(WASM_TARGET)
        .join("release")
        .join(format!("{lib}.wasm"));
    let core = std::fs::read(&wasm).map_err(|e| format!("{}: {e}", wasm.display()))?;
    let component = componentize(&core).map_err(|e| format!("{}: {e}", wasm.display()))?;
    let m = &plan.manifest;
    let zip = package::pack(
        m,
        &[PackFile {
            path: m.entry.clone().unwrap_or_default(),
            data: component,
            mode: 0o644,
        }],
    )?;
    write_zip(out, &format!("{}-{}.zip", m.name, m.version), &zip)
}

fn cargo_metadata(manifest_path: &Path) -> Result<CargoMetadata, Error> {
    let out = Command::new("cargo")
        .args([
            "metadata",
            "--format-version",
            "1",
            "--no-deps",
            "--manifest-path",
        ])
        .arg(manifest_path)
        .output()
        .map_err(|e| format!("cargo metadata: {e}"))?;
    if !out.status.success() {
        return Err(format!("cargo metadata: {}", String::from_utf8_lossy(&out.stderr)).into());
    }
    Ok(serde_json::from_slice(&out.stdout)?)
}

/// The crate of `manifest_path` (a member's own manifest), or `name`.
fn pick<'a>(
    md: &'a CargoMetadata,
    manifest_path: &Path,
    name: Option<&str>,
) -> Result<&'a CargoPackage, Error> {
    if let Some(n) = name {
        return md
            .packages
            .iter()
            .find(|p| p.name == n)
            .ok_or_else(|| format!("no crate {n} here").into());
    }
    let want = std::fs::canonicalize(manifest_path)?;
    md.packages
        .iter()
        .find(|p| std::fs::canonicalize(&p.manifest_path).is_ok_and(|m| m == want))
        .ok_or_else(|| {
            format!(
                "{} is a workspace: name the link crate with --package",
                manifest_path.display()
            )
            .into()
        })
}

fn write_zip(out: &Path, file: &str, zip: &[u8]) -> Result<PathBuf, Error> {
    std::fs::create_dir_all(out)?;
    let path = out.join(file);
    std::fs::write(&path, zip)?;
    println!("{}  sha256 {}", path.display(), package::sha256_hex(zip));
    Ok(path)
}

pub fn run_link(cmd: LinkCmd) -> Result<(), Error> {
    let LinkCmd::Pack {
        manifest_path,
        package: krate,
        targets,
        no_build,
        kind,
        out,
        component,
        name,
        version,
        description,
    } = cmd;
    if let Some(wasm) = component {
        let (name, version) = (name.unwrap_or_default(), version.unwrap_or_default());
        let file = format!("{name}.wasm");
        let data = std::fs::read(&wasm).map_err(|e| format!("{}: {e}", wasm.display()))?;
        let world = wyrm_wasm_host::component_world(&data)
            .map_err(|e| format!("{}: {e}", wasm.display()))?;
        let m = Manifest {
            name: name.clone(),
            version: version.clone(),
            description,
            wyrm_link: wyrm_link_sdk::LINK_PROTOCOL,
            kind: "wasm".into(),
            entries: BTreeMap::new(),
            args: Vec::new(),
            entry: Some(file.clone()),
            requester: Vec::new(),
            world: Some(world.name().into()),
            capabilities: None,
        };
        let zip = package::pack(
            &m,
            &[PackFile {
                path: file,
                data,
                mode: 0o644,
            }],
        )?;
        write_zip(
            &out.unwrap_or_else(|| ".".into()),
            &format!("{name}-{version}.zip"),
            &zip,
        )?;
        return Ok(());
    }
    let md = cargo_metadata(&manifest_path)?;
    let p = pick(&md, &manifest_path, krate.as_deref())?;
    let mut plan = plan(p, kind.as_deref())?;
    if let Some(n) = &name {
        plan.rename(n)?;
    }
    let out = out.unwrap_or_else(|| md.target_directory.join("wyrm-link"));
    let bin = match &plan.artifact {
        Artifact::Component(lib) => {
            if !targets.is_empty() {
                return Err("a wasm package runs on every host: no --target".into());
            }
            pack_component(
                &plan,
                lib,
                &manifest_path,
                &md.target_directory,
                no_build,
                &out,
            )?;
            return Ok(());
        }
        Artifact::Bin(bin) => bin.clone(),
    };
    // before a long build: the manifest as it will be, with one entry
    let mut probe = plan.manifest.clone();
    probe.entries.insert(package::platform(), bin.clone());
    probe.check().map_err(|e| format!("{}: {e}", plan.krate))?;
    let builds: Vec<(Option<String>, String)> = if targets.is_empty() {
        vec![(None, package::platform())]
    } else {
        targets
            .into_iter()
            .map(|t| {
                let host = package::host_of_triple(&t)
                    .ok_or_else(|| format!("target {t}: not a host a broker runs on"))?;
                Ok((Some(t), host.to_owned()))
            })
            .collect::<Result<_, Error>>()?
    };
    for (triple, host) in builds {
        if !no_build {
            let mut c = Command::new("cargo");
            c.args(["build", "--release", "-p", &plan.krate, "--bin", &bin])
                .arg("--manifest-path")
                .arg(&manifest_path);
            if !plan.features.is_empty() {
                c.arg("--features").arg(plan.features.join(","));
            }
            if let Some(t) = &triple {
                c.args(["--target", t]);
            }
            if !c.status()?.success() {
                return Err(format!("cargo build of {} failed", plan.krate).into());
            }
        }
        let dir = match &triple {
            Some(t) => md.target_directory.join(t).join("release"),
            None => md.target_directory.join("release"),
        };
        let exe = dir.join(&bin);
        let data = std::fs::read(&exe).map_err(|e| format!("{}: {e}", exe.display()))?;
        let entry = format!("bin/{host}/{bin}");
        let mut m = plan.manifest.clone();
        m.entries.insert(host.clone(), entry.clone());
        let zip = package::pack(
            &m,
            &[PackFile {
                path: entry,
                data,
                mode: 0o755,
            }],
        )?;
        write_zip(&out, &format!("{}-{}-{host}.zip", m.name, m.version), &zip)?;
    }
    Ok(())
}

/// `index` with the zip `file` (manifest `m`, `sha256`) added: published as
/// `url`. A new version replaces the entry; the same version adds hosts.
fn add_to_index(index: &mut Vec<RepoEntry>, m: &Manifest, url: String, sha256: String) {
    let fresh = |m: &Manifest| RepoEntry {
        name: m.name.clone(),
        version: m.version.clone(),
        description: m.description.clone(),
        url: None,
        sha256: None,
        assets: BTreeMap::new(),
    };
    let i = match index.iter().position(|e| e.name == m.name) {
        Some(i) if index[i].version == m.version => i,
        Some(i) => {
            index[i] = fresh(m);
            i
        }
        None => {
            index.push(fresh(m));
            index.len() - 1
        }
    };
    let e = &mut index[i];
    e.description.clone_from(&m.description);
    if m.kind == "wasm" {
        e.url = Some(url);
        e.sha256 = Some(sha256);
    } else {
        for host in m.entries.keys() {
            e.assets.insert(
                host.clone(),
                Asset {
                    url: url.clone(),
                    sha256: sha256.clone(),
                },
            );
        }
    }
    index.sort_by(|a, b| a.name.cmp(&b.name));
}

pub fn run_repo(cmd: RepoCmd) -> Result<(), Error> {
    let RepoCmd::Add { zips, repo, url } = cmd;
    if zips.is_empty() {
        return Err("no zip to add".into());
    }
    std::fs::create_dir_all(&repo)?;
    let index_path = repo.join("index.json");
    let mut index = match std::fs::read(&index_path) {
        Ok(b) => package::parse_index(&b)?,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Vec::new(),
        Err(e) => return Err(format!("{}: {e}", index_path.display()).into()),
    };
    for z in zips {
        let bytes = std::fs::read(&z).map_err(|e| format!("{}: {e}", z.display()))?;
        let m = package::read_manifest(&bytes).map_err(|e| format!("{}: {e}", z.display()))?;
        let file = z
            .file_name()
            .and_then(|f| f.to_str())
            .ok_or_else(|| format!("{}: not a file name", z.display()))?;
        let rel = format!("{}/{}/{file}", m.name, m.version);
        let dest = repo.join(&rel);
        std::fs::create_dir_all(dest.parent().expect("a directory"))?;
        std::fs::write(&dest, &bytes)?;
        let url = match &url {
            Some(base) => format!("{}/{rel}", base.trim_end_matches('/')),
            None => rel.clone(),
        };
        add_to_index(&mut index, &m, url, package::sha256_hex(&bytes));
        println!("{} {} → {rel}", m.name, m.version);
    }
    let text = serde_json::to_string_pretty(&index)? + "\n";
    // what a broker will read must pass its check
    package::parse_index(text.as_bytes())?;
    std::fs::write(&index_path, text)?;
    println!("{}: {} packages", index_path.display(), index.len());
    Ok(())
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;

    /// `cargo metadata` of a crate (for the scaffold test).
    pub(crate) fn metadata(manifest_path: &Path) -> CargoMetadata {
        cargo_metadata(manifest_path).unwrap()
    }

    /// What `wyr link pack` does for the `kind = "wasm"` crate of `manifest_path`, building in
    /// `target_dir`: the path of the zip.
    pub(crate) fn pack_wasm(
        md: &CargoMetadata,
        manifest_path: &Path,
        target_dir: &Path,
        out: &Path,
    ) -> PathBuf {
        let p = pick(md, manifest_path, None).unwrap();
        let plan = plan(p, None).unwrap();
        let Artifact::Component(lib) = &plan.artifact else {
            panic!("not a wasm crate: {:?}", plan.artifact)
        };
        pack_component(&plan, lib, manifest_path, target_dir, false, out).unwrap()
    }

    fn cargo_pkg(metadata: serde_json::Value, bins: &[&str]) -> CargoPackage {
        CargoPackage {
            name: "wyrm-example-recorder".into(),
            version: "1.2.0".into(),
            description: Some("records values".into()),
            manifest_path: "Cargo.toml".into(),
            metadata: Some(metadata),
            targets: bins
                .iter()
                .map(|b| CargoTarget {
                    name: (*b).into(),
                    kind: vec!["bin".into()],
                })
                .chain([CargoTarget {
                    name: "lib".into(),
                    kind: vec!["lib".into()],
                }])
                .collect(),
        }
    }

    #[test]
    fn plan_from_cargo_metadata() {
        let p = cargo_pkg(
            serde_json::json!({ "wyrm-link": {
                "name": "recorder",
                "features": ["bin"],
                "requester": [{ "path": "wy/{site}/downstream/mock", "level": "read" }],
            }}),
            &["wyrm-example-recorder"],
        );
        let got = plan(&p, None).unwrap();
        assert_eq!(got.artifact, Artifact::Bin("wyrm-example-recorder".into()));
        assert_eq!(got.features, ["bin"]);
        assert_eq!(got.manifest.name, "recorder");
        assert_eq!(got.manifest.version, "1.2.0");
        assert_eq!(got.manifest.description, "records values");
        assert_eq!(got.manifest.requester[0].level, "read");
        // without the section: the crate as it is
        let plain = plan(&cargo_pkg(serde_json::json!({}), &["a"]), None).unwrap();
        assert_eq!(plain.manifest.name, "wyrm-example-recorder");
        // several binaries need `bin`; a typo is refused
        assert!(plan(&cargo_pkg(serde_json::json!({}), &["a", "b"]), None).is_err());
        let typo = serde_json::json!({ "wyrm-link": { "reqester": [] } });
        assert!(plan(&cargo_pkg(typo, &["a"]), None).is_err());
        let jar = serde_json::json!({ "wyrm-link": { "kind": "jar" } });
        assert!(plan(&cargo_pkg(jar, &["a"]), None).is_err());
    }

    /// A crate with a cdylib and a process binary, as `wyr new link --app` writes it.
    fn app_pkg(metadata: serde_json::Value) -> CargoPackage {
        let mut p = cargo_pkg(metadata, &["wyrm-link-acme"]);
        p.name = "wyrm-link-acme".into();
        p.targets.push(CargoTarget {
            name: "wyrm_link_acme".into(),
            kind: vec!["cdylib".into(), "rlib".into()],
        });
        p
    }

    #[test]
    fn plan_wasm_kind_reads_capabilities() {
        let meta = serde_json::json!({ "wyrm-link": {
            "name": "acme",
            "kind": "wasm",
            "features": ["process"],
            "capabilities": { "store_mb": 4, "net": ["127.0.0.1:502"] },
            "requester": [{ "path": "wy/{site}/downstream/mock", "level": "read" }],
        }});
        let got = plan(&app_pkg(meta.clone()), None).unwrap();
        assert_eq!(got.artifact, Artifact::Component("wyrm_link_acme".into()));
        assert_eq!(got.manifest.kind, "wasm");
        assert_eq!(got.manifest.world.as_deref(), Some("app"));
        assert_eq!(got.manifest.entry.as_deref(), Some("acme.wasm"));
        let caps = got.manifest.capabilities.clone().unwrap();
        assert_eq!(caps.store_mb, Some(4));
        assert_eq!(caps.net, ["127.0.0.1:502"]);
        assert_eq!(got.manifest.requester[0].level, "read");
        // `--kind process` packs the binary of the same crate, without capabilities
        let proc = plan(&app_pkg(meta), Some("process")).unwrap();
        assert_eq!(proc.artifact, Artifact::Bin("wyrm-link-acme".into()));
        assert_eq!(proc.features, ["process"]);
        assert_eq!(proc.manifest.capabilities, None);
        assert_eq!(proc.manifest.world, None);
        // over the bounds, before any build
        let big = serde_json::json!({ "wyrm-link": {
            "kind": "wasm", "capabilities": { "store_mb": 65 } } });
        let err = plan(&app_pkg(big), None).unwrap_err().to_string();
        assert!(err.contains("store_mb 65"), "{err}");
        // a wasm crate needs a cdylib
        let wasm = serde_json::json!({ "wyrm-link": { "kind": "wasm" } });
        let err = plan(&cargo_pkg(wasm, &["a"]), None)
            .unwrap_err()
            .to_string();
        assert!(err.contains("cdylib"), "{err}");
        let typo = serde_json::json!({ "wyrm-link": { "kind": "wasm",
            "capabilities": { "store": 4 } } });
        assert!(plan(&app_pkg(typo), None).is_err());
    }

    /// `--name` renames a crate's package: both forms of one portable link in one repository.
    #[test]
    fn name_overrides_the_crate_package() {
        let meta = serde_json::json!({ "wyrm-link": { "name": "acme", "kind": "wasm" } });
        let mut wasm = plan(&app_pkg(meta.clone()), None).unwrap();
        wasm.rename("acme-wasm").unwrap();
        assert_eq!(wasm.manifest.name, "acme-wasm");
        assert_eq!(wasm.manifest.entry.as_deref(), Some("acme-wasm.wasm"));
        let mut proc = plan(&app_pkg(meta), Some("process")).unwrap();
        proc.rename("acme-process").unwrap();
        assert_eq!(proc.manifest.name, "acme-process");
        assert_eq!(proc.manifest.entry, None);
        assert!(proc.rename("bad name").is_err());
    }

    fn manifest(version: &str, hosts: &[&str]) -> Manifest {
        Manifest {
            name: "acme".into(),
            version: version.into(),
            description: format!("acme {version}"),
            wyrm_link: wyrm_link_sdk::LINK_PROTOCOL,
            kind: "process".into(),
            entries: hosts
                .iter()
                .map(|h| (h.to_string(), format!("bin/{h}/acme")))
                .collect(),
            args: vec![],
            entry: None,
            requester: vec![],
            world: None,
            capabilities: None,
        }
    }

    #[test]
    fn index_hosts_and_versions() {
        let mut index = Vec::new();
        let sha = |c: char| c.to_string().repeat(64);
        add_to_index(
            &mut index,
            &manifest("1.0.0", &["linux-x86_64"]),
            "a".into(),
            sha('a'),
        );
        add_to_index(
            &mut index,
            &manifest("1.0.0", &["macos-aarch64"]),
            "b".into(),
            sha('b'),
        );
        assert_eq!(index.len(), 1);
        assert_eq!(index[0].assets.len(), 2, "same version: hosts add up");
        add_to_index(
            &mut index,
            &manifest("1.1.0", &["linux-x86_64"]),
            "c".into(),
            sha('c'),
        );
        assert_eq!(index[0].version, "1.1.0");
        assert_eq!(index[0].assets.len(), 1, "a new version starts again");
        assert_eq!(index[0].asset("linux-x86_64").unwrap().url, "c");
        let text = serde_json::to_string(&index).unwrap();
        assert!(package::parse_index(text.as_bytes()).is_ok());
    }

    #[test]
    fn repo_add_writes_files_and_index() {
        let dir = std::env::temp_dir().join(format!("wyr-repo-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let m = manifest("1.0.0", &["linux-x86_64"]);
        let zip = package::pack(
            &m,
            &[PackFile {
                path: "bin/linux-x86_64/acme".into(),
                data: b"x".to_vec(),
                mode: 0o755,
            }],
        )
        .unwrap();
        let z = dir.join("acme-1.0.0-linux-x86_64.zip");
        std::fs::write(&z, &zip).unwrap();
        let repo = dir.join("repo");
        run_repo(RepoCmd::Add {
            zips: vec![z],
            repo: repo.clone(),
            url: None,
        })
        .unwrap();
        let index = package::parse_index(&std::fs::read(repo.join("index.json")).unwrap()).unwrap();
        let a = index[0].asset("linux-x86_64").unwrap();
        assert_eq!(a.url, "acme/1.0.0/acme-1.0.0-linux-x86_64.zip");
        assert_eq!(std::fs::read(repo.join(&a.url)).unwrap(), zip);
        assert_eq!(a.sha256, package::sha256_hex(&zip));
        let _ = std::fs::remove_dir_all(&dir);
    }
}
