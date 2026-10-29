//! `wyr new link|flow`: scaffolds from the templates in `tools/wyr/templates`
//! (embedded at build time). Placeholders, in file contents and paths:
//! `__NAME__` (link name = key segment, `Driver::NAME` or `App::NAME`),
//! `__CRATE__` (`wyrm-link-<name>`), `__LIB__` (its Rust name), `__TYPE__`
//! (CamelCase type prefix), `__ID__` (flow id).

use crate::Error;
use clap::{Subcommand, ValueEnum};
use std::path::{Path, PathBuf};

#[derive(Subcommand, Debug)]
pub enum NewCmd {
    /// Scaffold a driver crate on the driver framework (ADR 0004) with a
    /// simulator and a test that passes as generated.
    Link {
        /// Link/driver name: a key segment, `[a-z][a-z0-9_-]*`.
        name: String,
        #[arg(long, value_enum, default_value_t = Proto::Generic)]
        proto: Proto,
        /// A portable link instead (ADR 0023): one `App` that runs embedded,
        /// as a process (`--features process`) and as a WASM component
        /// (`wyr link pack`).
        #[arg(long, conflicts_with = "proto")]
        app: bool,
        /// Parent directory; the crate goes to `<dir>/<name>`.
        #[arg(long, default_value = "links")]
        dir: PathBuf,
    },
    /// Write a `~def` template `<dir>/<id>.json5` (spec 06).
    Flow {
        id: String,
        #[arg(long, default_value = "flows")]
        dir: PathBuf,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, ValueEnum)]
pub enum Proto {
    /// TCP line protocol placeholder with its own simulator.
    Generic,
    /// Modbus TCP device (tokio-modbus) tested on the `links/modbus` simulator.
    Modbus,
}

const GENERIC: [(&str, &str); 4] = [
    (
        "Cargo.toml",
        include_str!("../templates/link/generic/Cargo.toml.tmpl"),
    ),
    (
        "src/lib.rs",
        include_str!("../templates/link/generic/lib.rs.tmpl"),
    ),
    (
        "src/sim.rs",
        include_str!("../templates/link/generic/sim.rs.tmpl"),
    ),
    (
        "tests/sim.rs",
        include_str!("../templates/link/generic/test.rs.tmpl"),
    ),
];

const MODBUS: [(&str, &str); 4] = [
    (
        "Cargo.toml",
        include_str!("../templates/link/modbus/Cargo.toml.tmpl"),
    ),
    (
        "src/lib.rs",
        include_str!("../templates/link/modbus/lib.rs.tmpl"),
    ),
    (
        "src/sim.rs",
        include_str!("../templates/link/modbus/sim.rs.tmpl"),
    ),
    (
        "tests/sim.rs",
        include_str!("../templates/link/modbus/test.rs.tmpl"),
    ),
];

const APP: [(&str, &str); 4] = [
    (
        "Cargo.toml",
        include_str!("../templates/link/app/Cargo.toml.tmpl"),
    ),
    (
        "src/lib.rs",
        include_str!("../templates/link/app/lib.rs.tmpl"),
    ),
    (
        "src/bin/__CRATE__.rs",
        include_str!("../templates/link/app/main.rs.tmpl"),
    ),
    (
        "tests/app.rs",
        include_str!("../templates/link/app/test.rs.tmpl"),
    ),
];

/// What `wyr new link` writes.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    /// A driver on the framework (ADR 0004) for a protocol.
    Driver(Proto),
    /// A portable link (ADR 0023).
    App,
}

pub const FLOW: &str = include_str!("../templates/flow/flow.json5.tmpl");

/// Type names the generated files already use at their roots (templates,
/// imports, the std prelude): a driver type of the same name would not
/// compile.
const RESERVED_TYPES: &[&str] = &[
    // template items and imports
    "Conn",
    "Dev",
    "Point",
    "Transport",
    "Table",
    "Span",
    "Reply",
    "Driver",
    "DriverError",
    "Framework",
    "PointId",
    "Params",
    "ParamEnum",
    "Value",
    "NodeMeta",
    "Writable",
    "Duration",
    "TcpStream",
    "BufReader",
    "AsyncBufReadExt",
    "AsyncWriteExt",
    "SocketAddr",
    "Context",
    "Reader",
    "Writer",
    "SlaveContext",
    "ExceptionCode",
    "Slave",
    "Tree",
    "TestHarness",
    "H",
    "Perm",
    "Quality",
    "Status",
    // the app template (ADR 0023)
    "App",
    "AppError",
    "Host",
    "Who",
    "ActionMeta",
    "Sample",
    "Link",
    "Portable",
    "PortableConfig",
    "Secret",
    "StatusCode",
    "BTreeMap",
    // keyword and prelude
    "Self",
    "Option",
    "Result",
    "String",
    "Vec",
    "Box",
    "Send",
    "Sync",
    "Sized",
    "Unpin",
    "Clone",
    "Copy",
    "Debug",
    "Default",
    "Drop",
    "Eq",
    "PartialEq",
    "Ord",
    "PartialOrd",
    "Fn",
    "FnMut",
    "FnOnce",
    "From",
    "Into",
    "Iterator",
    "IntoIterator",
    "Extend",
    "ToOwned",
    "ToString",
    "AsRef",
    "AsMut",
];

/// Names derived from a link name.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Names {
    pub name: String,
    pub krate: String,
    pub lib: String,
    pub ty: String,
}

impl Names {
    pub fn new(name: &str) -> Result<Self, Error> {
        wyrm_core::keyspace::validate_segment(name).map_err(|e| format!("name {name:?}: {e}"))?;
        let mut chars = name.chars();
        let ok = chars.next().is_some_and(|c| c.is_ascii_lowercase())
            && chars.all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '_' || c == '-');
        if !ok {
            return Err(format!(
                "name {name:?}: use [a-z][a-z0-9_-]* (it names the crate, the driver and the key segment)"
            )
            .into());
        }
        let ty = name
            .split(['-', '_'])
            .filter(|p| !p.is_empty())
            .map(|p| {
                let mut c = p.chars();
                c.next()
                    .map(|f| f.to_ascii_uppercase().to_string() + c.as_str())
                    .unwrap_or_default()
            })
            .collect::<String>();
        if RESERVED_TYPES.contains(&ty.as_str()) {
            return Err(format!(
                "name {name:?}: its type name {ty} clashes with an item of the generated crate; choose another name"
            )
            .into());
        }
        Ok(Self {
            name: name.to_owned(),
            krate: format!("wyrm-link-{name}"),
            lib: format!("wyrm_link_{}", name.replace('-', "_")),
            ty,
        })
    }

    fn render(&self, tmpl: &str) -> String {
        tmpl.replace("__CRATE__", &self.krate)
            .replace("__LIB__", &self.lib)
            .replace("__TYPE__", &self.ty)
            .replace("__NAME__", &self.name)
    }
}

/// Rendered files of a link crate: (relative path, text).
pub fn render_link(n: &Names, kind: Kind) -> Vec<(String, String)> {
    let files = match kind {
        Kind::Driver(Proto::Generic) => &GENERIC,
        Kind::Driver(Proto::Modbus) => &MODBUS,
        Kind::App => &APP,
    };
    files
        .iter()
        .map(|(p, t)| (n.render(p), n.render(t)))
        .collect()
}

pub fn render_flow(id: &str) -> Result<String, Error> {
    wyrm_core::keyspace::validate_segment(id).map_err(|e| format!("flow id {id:?}: {e}"))?;
    Ok(FLOW.replace("__ID__", id))
}

/// Write a new crate under `dir/<name>`; never overwrites. Returns its path.
pub fn write_link(dir: &Path, n: &Names, kind: Kind) -> Result<PathBuf, Error> {
    let root = dir.join(&n.name);
    std::fs::create_dir_all(dir).map_err(|e| format!("{}: {e}", dir.display()))?;
    // `create_dir` (not `_all`) fails when the directory exists.
    std::fs::create_dir(&root).map_err(|e| format!("{}: {e}", root.display()))?;
    for (rel, text) in render_link(n, kind) {
        let path = root.join(rel);
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        write_new(&path, &text)?;
    }
    Ok(root)
}

pub fn write_flow(dir: &Path, id: &str) -> Result<PathBuf, Error> {
    let text = render_flow(id)?;
    std::fs::create_dir_all(dir).map_err(|e| format!("{}: {e}", dir.display()))?;
    let path = dir.join(format!("{id}.json5"));
    write_new(&path, &text)?;
    Ok(path)
}

fn write_new(path: &Path, text: &str) -> Result<(), Error> {
    use std::io::Write;
    let mut f = std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(path)
        .map_err(|e| format!("{}: {e}", path.display()))?;
    f.write_all(text.as_bytes())?;
    Ok(())
}

pub fn run(cmd: NewCmd) -> Result<(), Error> {
    match cmd {
        NewCmd::Link {
            name,
            proto,
            app,
            dir,
        } => {
            let n = Names::new(&name)?;
            let kind = if app { Kind::App } else { Kind::Driver(proto) };
            let root = write_link(&dir, &n, kind)?;
            let member = root.display().to_string().replace('\\', "/");
            out!("created {member} ({})", n.krate);
            out!("next:");
            out!("  1. add \"{member}\" to [workspace] members in Cargo.toml");
            out!(
                "  2. add `{} = {{ path = \"{member}\" }}` to [workspace.dependencies]",
                n.krate
            );
            out!("  3. cargo test -p {}", n.krate);
            if app {
                out!(
                    "  4. wyr link pack -p {} → a wasm package (Install Link ▸ from Zip); --kind process for a binary",
                    n.krate
                );
            } else {
                out!(
                    "  4. to run it from wyrmd: register \"{}\" => {}::{} in crates/wyrmd/src/lib.rs (validation, start_boxed, run_link)",
                    n.name,
                    n.lib,
                    n.ty
                );
            }
            Ok(())
        }
        NewCmd::Flow { id, dir } => {
            let path = write_flow(&dir, &id)?;
            out!("created {}", path.display());
            out!("check it: wyr flow validate <site> {}", path.display());
            Ok(())
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn names() {
        let n = Names::new("acme-x_2").unwrap();
        assert_eq!(n.krate, "wyrm-link-acme-x_2");
        assert_eq!(n.lib, "wyrm_link_acme_x_2");
        assert_eq!(n.ty, "AcmeX2");
        assert_eq!(Names::new("bacnet").unwrap().ty, "Bacnet");
        for bad in [
            "",
            "~x",
            "a/b",
            "a.b",
            "1abc",
            "Acme",
            "a b",
            "-x",
            "point",
            "dev",
            "conn",
            "self",
            "result",
            "h",
            "table",
            "driver",
            "test_harness",
        ] {
            assert!(Names::new(bad).is_err(), "{bad:?} accepted");
        }
    }

    #[test]
    fn link_templates_render() {
        let n = Names::new("acme-x").unwrap();
        for proto in [Proto::Generic, Proto::Modbus] {
            let files = render_link(&n, Kind::Driver(proto));
            let paths: Vec<&str> = files.iter().map(|(p, _)| p.as_str()).collect();
            assert_eq!(
                paths,
                ["Cargo.toml", "src/lib.rs", "src/sim.rs", "tests/sim.rs"]
            );
            for (p, text) in &files {
                assert!(!text.contains("__"), "{proto:?} {p}: placeholder left");
            }
            let get = |p: &str| &files.iter().find(|(q, _)| q == p).unwrap().1;
            assert!(get("Cargo.toml").contains("name = \"wyrm-link-acme-x\""));
            assert!(get("Cargo.toml").contains("wyrm-link-acme-x = { path = \".\""));
            let lib = get("src/lib.rs");
            assert!(lib.contains("const NAME: &'static str = \"acme-x\";"));
            assert!(lib.contains("pub type AcmeX = Framework<AcmeXDriver>;"));
            assert!(lib.contains("impl Driver for AcmeXDriver"));
            assert!(lib.contains("#[derive(Debug, Clone, PartialEq, Params)]\npub struct Point"));
            assert!(get("tests/sim.rs").contains("use wyrm_link_acme_x::{sim, AcmeX};"));
        }
        let files = render_link(&n, Kind::App);
        let paths: Vec<&str> = files.iter().map(|(p, _)| p.as_str()).collect();
        assert_eq!(
            paths,
            [
                "Cargo.toml",
                "src/lib.rs",
                "src/bin/wyrm-link-acme-x.rs",
                "tests/app.rs"
            ]
        );
        for (p, text) in &files {
            assert!(!text.contains("__"), "app {p}: placeholder left");
        }
        let get = |p: &str| &files.iter().find(|(q, _)| q == p).unwrap().1;
        let toml = get("Cargo.toml");
        assert!(toml.contains("crate-type = [\"cdylib\", \"rlib\"]"));
        assert!(toml.contains("[package.metadata.wyrm-link]\nname = \"acme-x\"\nkind = \"wasm\""));
        let lib = get("src/lib.rs");
        assert!(lib.contains("impl App for AcmeX"));
        assert!(lib.contains("const NAME: &'static str = \"acme-x\";"));
        assert!(lib.contains("#[cfg(feature = \"wasm\")]\nwyrm_link_guest::export!(AcmeX);"));
        assert!(get("src/bin/wyrm-link-acme-x.rs")
            .contains("wyrm_link_sdk::process::main::<Portable<wyrm_link_acme_x::AcmeX>>()"));
    }

    #[test]
    fn flow_template_compiles() {
        let text = render_flow("peak_1").unwrap();
        let def = crate::flow::parse_def(&text).unwrap();
        let (d, _) = wyrm_flow::def::compile(&def).unwrap();
        assert_eq!(d.id, "peak_1");
        assert_eq!(d.version, 1);
        assert!(render_flow("a/b").is_err());
        assert!(render_flow("~x").is_err());
    }

    /// Generated crates build, pass their own tests and clippy, in a
    /// temporary workspace outside the repo (cargo refuses a non-member
    /// crate inside it) that reuses the repo's dependency table, lock file
    /// and target directory. Slow (~30 s warm, minutes cold):
    /// `cargo test -p wyr -- --ignored generated_crates`.
    #[test]
    #[ignore]
    fn generated_crates_build_and_pass() {
        let repo = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
        let repo = repo.canonicalize().unwrap();
        let ws = std::env::temp_dir().join(format!("wyr-gen-ws-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&ws);
        std::fs::create_dir_all(&ws).unwrap();
        let root = std::fs::read_to_string(repo.join("Cargo.toml")).unwrap();
        let manifest: String = root
            .lines()
            .map(|l| {
                if l.starts_with("members = ") {
                    "members = [\"links/gen-generic\", \"links/gen-modbus\"]".to_owned()
                } else {
                    l.replace("path = \"", &format!("path = \"{}/", repo.display()))
                }
            })
            .collect::<Vec<_>>()
            .join("\n");
        std::fs::write(ws.join("Cargo.toml"), manifest).unwrap();
        std::fs::copy(repo.join("Cargo.lock"), ws.join("Cargo.lock")).unwrap();
        for (name, proto) in [
            ("gen-generic", Proto::Generic),
            ("gen-modbus", Proto::Modbus),
        ] {
            write_link(
                &ws.join("links"),
                &Names::new(name).unwrap(),
                Kind::Driver(proto),
            )
            .unwrap();
        }
        let cargo = std::env::var("CARGO").unwrap_or_else(|_| "cargo".into());
        for args in [
            &["test", "--offline"][..],
            &[
                "clippy",
                "--offline",
                "--all-targets",
                "--",
                "-D",
                "warnings",
            ][..],
            &["fmt", "--check"][..],
        ] {
            let st = std::process::Command::new(&cargo)
                .args(args)
                .current_dir(&ws)
                .env("CARGO_TARGET_DIR", repo.join("target"))
                .status()
                .unwrap();
            assert!(st.success(), "cargo {args:?} failed in {}", ws.display());
        }
        let _ = std::fs::remove_dir_all(&ws);
    }

    /// The `--app` crate (ADR 0023) builds, passes its test on the native adapter, clippy and
    /// fmt, and `wyr link pack` makes a `wyrm:app` component package of it (when the wasm32
    /// target is installed), all in a temporary workspace like
    /// `generated_crates_build_and_pass` (whose `[profile.release]` strips: the component type
    /// must survive it). Slow: `cargo test -p wyr -- --ignored app_template`.
    #[test]
    #[ignore]
    fn app_template_builds_and_passes() {
        let repo = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
        let repo = repo.canonicalize().unwrap();
        let ws = std::env::temp_dir().join(format!("wyr-gen-app-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&ws);
        std::fs::create_dir_all(&ws).unwrap();
        let root = std::fs::read_to_string(repo.join("Cargo.toml")).unwrap();
        let manifest: String = root
            .lines()
            .map(|l| {
                if l.starts_with("members = ") {
                    "members = [\"links/gen-app\"]".to_owned()
                } else if l.starts_with("exclude = ") {
                    String::new()
                } else {
                    l.replace("path = \"", &format!("path = \"{}/", repo.display()))
                }
            })
            .collect::<Vec<_>>()
            .join("\n");
        std::fs::write(ws.join("Cargo.toml"), manifest).unwrap();
        std::fs::copy(repo.join("Cargo.lock"), ws.join("Cargo.lock")).unwrap();
        let n = Names::new("gen-app").unwrap();
        let krate = write_link(&ws.join("links"), &n, Kind::App).unwrap();
        assert!(krate.join("src/bin/wyrm-link-gen-app.rs").is_file());
        let cargo = std::env::var("CARGO").unwrap_or_else(|_| "cargo".into());
        let target = repo.join("target");
        for args in [
            &["test", "--offline"][..],
            &[
                "clippy",
                "--offline",
                "--all-targets",
                "--features",
                "process",
                "--",
                "-D",
                "warnings",
            ][..],
            &["fmt", "--check"][..],
        ] {
            let st = std::process::Command::new(&cargo)
                .args(args)
                .current_dir(&ws)
                .env("CARGO_TARGET_DIR", &target)
                .status()
                .unwrap();
            assert!(st.success(), "cargo {args:?} failed in {}", ws.display());
        }
        let wasm32 = std::process::Command::new("rustc")
            .args([
                "--print",
                "target-libdir",
                "--target",
                "wasm32-unknown-unknown",
            ])
            .output()
            .ok()
            .filter(|o| o.status.success())
            .is_some_and(|o| Path::new(String::from_utf8_lossy(&o.stdout).trim()).exists());
        if !wasm32 {
            eprintln!("SKIP the wasm pack: target wasm32-unknown-unknown is not installed");
        } else {
            // `wyr link pack` on the crate: plan from its metadata, build, componentize, zip
            let manifest_path = krate.join("Cargo.toml");
            let md = crate::pack::tests::metadata(&manifest_path);
            let out = ws.join("out");
            let zip = crate::pack::tests::pack_wasm(&md, &manifest_path, &target, &out);
            assert_eq!(zip, out.join("gen-app-0.1.0.zip"));
            let bytes = std::fs::read(&zip).unwrap();
            let m = wyrm_link_sdk::package::read_manifest(&bytes).unwrap();
            assert_eq!(m.kind, "wasm");
            assert_eq!(m.world.as_deref(), Some("app"));
            assert_eq!(m.capabilities.unwrap().store_mb, Some(1));
            let mut a = zip::ZipArchive::new(std::io::Cursor::new(bytes)).unwrap();
            let mut component = Vec::new();
            std::io::Read::read_to_end(&mut a.by_name("gen-app.wasm").unwrap(), &mut component)
                .unwrap();
            assert_eq!(
                wyrm_wasm_host::component_world(&component).unwrap(),
                wyrm_wasm_host::ComponentWorld::App
            );
        }
        let _ = std::fs::remove_dir_all(&ws);
    }

    #[test]
    fn refuses_to_overwrite() {
        let dir = std::env::temp_dir().join(format!("wyr-new-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let n = Names::new("demo").unwrap();
        let root = write_link(&dir, &n, Kind::Driver(Proto::Generic)).unwrap();
        assert!(root.join("tests/sim.rs").is_file());
        assert!(write_link(&dir, &n, Kind::App).is_err());
        let f = write_flow(&dir, "f1").unwrap();
        assert!(f.is_file());
        assert!(write_flow(&dir, "f1").is_err());
        let _ = std::fs::remove_dir_all(&dir);
    }
}
