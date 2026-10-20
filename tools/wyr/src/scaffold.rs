//! `wyr new link|flow`: scaffolds from the templates in `tools/wyr/templates`
//! (embedded at build time). Placeholders: `__NAME__` (link name = key
//! segment and `Driver::NAME`), `__CRATE__` (`wyrm-link-<name>`), `__LIB__`
//! (its Rust name), `__TYPE__` (CamelCase type prefix), `__ID__` (flow id).

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
pub fn render_link(n: &Names, proto: Proto) -> Vec<(&'static str, String)> {
    let files = match proto {
        Proto::Generic => &GENERIC,
        Proto::Modbus => &MODBUS,
    };
    files.iter().map(|(p, t)| (*p, n.render(t))).collect()
}

pub fn render_flow(id: &str) -> Result<String, Error> {
    wyrm_core::keyspace::validate_segment(id).map_err(|e| format!("flow id {id:?}: {e}"))?;
    Ok(FLOW.replace("__ID__", id))
}

/// Write a new crate under `dir/<name>`; never overwrites. Returns its path.
pub fn write_link(dir: &Path, n: &Names, proto: Proto) -> Result<PathBuf, Error> {
    let root = dir.join(&n.name);
    std::fs::create_dir_all(dir).map_err(|e| format!("{}: {e}", dir.display()))?;
    // `create_dir` (not `_all`) fails when the directory exists.
    std::fs::create_dir(&root).map_err(|e| format!("{}: {e}", root.display()))?;
    for (rel, text) in render_link(n, proto) {
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
        NewCmd::Link { name, proto, dir } => {
            let n = Names::new(&name)?;
            let root = write_link(&dir, &n, proto)?;
            let member = root.display().to_string().replace('\\', "/");
            out!("created {member} ({})", n.krate);
            out!("next:");
            out!("  1. add \"{member}\" to [workspace] members in Cargo.toml");
            out!(
                "  2. add `{} = {{ path = \"{member}\" }}` to [workspace.dependencies]",
                n.krate
            );
            out!("  3. cargo test -p {}", n.krate);
            out!(
                "  4. to run it from wyrmd: register \"{}\" => {}::{} in crates/wyrmd/src/lib.rs (validation, start_boxed, run_link)",
                n.name,
                n.lib,
                n.ty
            );
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
            let files = render_link(&n, proto);
            let paths: Vec<&str> = files.iter().map(|(p, _)| *p).collect();
            assert_eq!(
                paths,
                ["Cargo.toml", "src/lib.rs", "src/sim.rs", "tests/sim.rs"]
            );
            for (p, text) in &files {
                assert!(!text.contains("__"), "{proto:?} {p}: placeholder left");
            }
            let get = |p: &str| &files.iter().find(|(q, _)| *q == p).unwrap().1;
            assert!(get("Cargo.toml").contains("name = \"wyrm-link-acme-x\""));
            assert!(get("Cargo.toml").contains("wyrm-link-acme-x = { path = \".\""));
            let lib = get("src/lib.rs");
            assert!(lib.contains("const NAME: &'static str = \"acme-x\";"));
            assert!(lib.contains("pub type AcmeX = Framework<AcmeXDriver>;"));
            assert!(lib.contains("impl Driver for AcmeXDriver"));
            assert!(lib.contains("#[derive(Debug, Clone, PartialEq, Params)]\npub struct Point"));
            assert!(get("tests/sim.rs").contains("use wyrm_link_acme_x::{sim, AcmeX};"));
        }
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
            write_link(&ws.join("links"), &Names::new(name).unwrap(), proto).unwrap();
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

    #[test]
    fn refuses_to_overwrite() {
        let dir = std::env::temp_dir().join(format!("wyr-new-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let n = Names::new("demo").unwrap();
        let root = write_link(&dir, &n, Proto::Generic).unwrap();
        assert!(root.join("tests/sim.rs").is_file());
        assert!(write_link(&dir, &n, Proto::Modbus).is_err());
        let f = write_flow(&dir, "f1").unwrap();
        assert!(f.is_file());
        assert!(write_flow(&dir, "f1").is_err());
        let _ = std::fs::remove_dir_all(&dir);
    }
}
