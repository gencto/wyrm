//! The official links (ADR 0043): `wyr repo check` holds
//! `links/official.json` against the workspace, `wyr repo build` packs every
//! official link in one form, `wyr repo index` writes the repository index
//! (ADR 0021 format) of the zips it built.

use super::{cargo_metadata, plan, run_link, Artifact, CargoPackage, LinkCmd};
use crate::Error;
use std::path::{Path, PathBuf};
use wyrm_link_sdk::official::{self, Built, Official};
use wyrm_link_sdk::package;

/// Where the manifest and the workspace are.
#[derive(clap::Args, Debug)]
pub struct Source {
    /// The official links manifest.
    #[arg(long, default_value = official::PATH)]
    pub manifest: PathBuf,
    /// The workspace's Cargo.toml.
    #[arg(long, default_value = "Cargo.toml")]
    pub workspace: PathBuf,
}

fn load(path: &Path) -> Result<Official, Error> {
    let bytes = std::fs::read(path).map_err(|e| format!("{}: {e}", path.display()))?;
    Ok(official::parse(&bytes).map_err(|e| format!("{}: {e}", path.display()))?)
}

/// Every disagreement between the manifest and the crates, one line each.
pub(crate) fn check(o: &Official, crates: &[CargoPackage]) -> Vec<String> {
    let mut bad = Vec::new();
    for l in &o.links {
        let mut say = |what: String| bad.push(format!("{}: {what}", l.id));
        let Some(p) = crates.iter().find(|p| p.name == l.krate) else {
            say(format!("no crate {} in the workspace", l.krate));
            continue;
        };
        if p.version != l.version {
            say(format!(
                "version {}, crate {} is {}",
                l.version, p.name, p.version
            ));
        }
        if l.wyrm_link != wyrm_link_sdk::LINK_PROTOCOL {
            say(format!(
                "wyrm_link {}, the SDK builds {}",
                l.wyrm_link,
                wyrm_link_sdk::LINK_PROTOCOL
            ));
        }
        let own = plan(p, None).ok();
        if let Some(name) = &l.forms.wasm {
            match &own {
                Some(pl) if matches!(pl.artifact, Artifact::Component(_)) => {
                    if &pl.manifest.name != name {
                        say(format!(
                            "wasm form {name}, the crate packs {}",
                            pl.manifest.name
                        ));
                    }
                }
                _ => say("wasm form: the crate is not kind = \"wasm\" with a cdylib".into()),
            }
        }
        if let Some(name) = &l.forms.process {
            match plan(p, Some("process")) {
                Ok(pl) if matches!(pl.artifact, Artifact::Bin(_)) => {
                    // a process crate packs under its own name; a wasm crate's
                    // process twin takes `--name`, any free name
                    let natural = own
                        .as_ref()
                        .is_some_and(|o| matches!(o.artifact, Artifact::Bin(_)));
                    if natural && &pl.manifest.name != name {
                        say(format!(
                            "process form {name}, the crate packs {}",
                            pl.manifest.name
                        ));
                    }
                }
                Ok(_) => say("process form: no binary".into()),
                Err(e) => say(format!("process form: {e}")),
            }
        }
    }
    bad
}

fn workspace_crates(src: &Source) -> Result<Vec<CargoPackage>, Error> {
    Ok(cargo_metadata(&src.workspace)?.packages)
}

fn checked(src: &Source) -> Result<Official, Error> {
    let o = load(&src.manifest)?;
    let bad = check(&o, &workspace_crates(src)?);
    if !bad.is_empty() {
        return Err(format!(
            "{} does not match the workspace:\n  {}",
            src.manifest.display(),
            bad.join("\n  ")
        )
        .into());
    }
    Ok(o)
}

pub fn check_cmd(src: &Source) -> Result<(), Error> {
    let o = checked(src)?;
    let forms: usize = o.links.iter().map(|l| l.forms.names().len()).sum();
    println!(
        "{}: {} links, {forms} forms, match the workspace",
        src.manifest.display(),
        o.links.len()
    );
    Ok(())
}

pub fn build_cmd(
    src: &Source,
    form: &str,
    targets: &[String],
    only: &[String],
    no_build: bool,
    out: &Path,
) -> Result<(), Error> {
    let o = checked(src)?;
    if form == "wasm" && !targets.is_empty() {
        return Err("a wasm form runs on every host: no --target".into());
    }
    for t in targets {
        match package::host_of_triple(t) {
            Some(h) if o.hosts.iter().any(|x| x == h) => {}
            Some(h) => return Err(format!("target {t}: host {h} is not in `hosts`").into()),
            None => return Err(format!("target {t}: not a host a broker runs on").into()),
        }
    }
    if let Some(id) = only.iter().find(|id| !o.links.iter().any(|l| &&l.id == id)) {
        return Err(format!("--only {id}: no such official link").into());
    }
    for l in &o.links {
        if !only.is_empty() && !only.contains(&l.id) {
            continue;
        }
        let name = match form {
            "wasm" => &l.forms.wasm,
            _ => &l.forms.process,
        };
        let Some(name) = name else { continue };
        println!("== {} ({form}: {name})", l.id);
        run_link(LinkCmd::Pack {
            manifest_path: src.workspace.clone(),
            package: Some(l.krate.clone()),
            targets: targets.to_vec(),
            no_build,
            kind: Some(form.to_owned()),
            out: Some(out.to_owned()),
            component: None,
            name: Some(name.clone()),
            version: None,
            description: String::new(),
        })?;
    }
    Ok(())
}

/// The zips of `dir`, read and hashed.
fn read_zips(dir: &Path) -> Result<Vec<Built>, Error> {
    let mut files: Vec<PathBuf> = std::fs::read_dir(dir)
        .map_err(|e| format!("{}: {e}", dir.display()))?
        .filter_map(|e| e.ok().map(|e| e.path()))
        .filter(|p| p.extension().is_some_and(|x| x == "zip"))
        .collect();
    files.sort();
    files
        .into_iter()
        .map(|p| {
            let bytes = std::fs::read(&p).map_err(|e| format!("{}: {e}", p.display()))?;
            let manifest =
                package::read_manifest(&bytes).map_err(|e| format!("{}: {e}", p.display()))?;
            let file = p
                .file_name()
                .and_then(|f| f.to_str())
                .ok_or_else(|| format!("{}: not a file name", p.display()))?
                .to_owned();
            Ok(Built {
                file,
                manifest,
                sha256: package::sha256_hex(&bytes),
            })
        })
        .collect()
}

pub fn index_cmd(
    src: &Source,
    zips: &Path,
    out: &Path,
    tag: Option<&str>,
    base: Option<&str>,
    partial: bool,
) -> Result<(), Error> {
    // the zips decide; the manifest file is the one of the tag being released
    let o = load(&src.manifest)?;
    let built = read_zips(zips)?;
    let base = match (tag, base) {
        (Some(t), _) => Some(o.asset_base(t)),
        (None, b) => b.map(str::to_owned),
    };
    let index = o.index(&built, base.as_deref(), partial)?;
    let text = serde_json::to_string_pretty(&index)? + "\n";
    std::fs::write(out, text).map_err(|e| format!("{}: {e}", out.display()))?;
    println!(
        "{}: {} packages from {} zips",
        out.display(),
        index.len(),
        built.len()
    );
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::super::CargoTarget;
    use super::*;

    fn root() -> PathBuf {
        Path::new(env!("CARGO_MANIFEST_DIR")).join("../..")
    }

    /// The checked-in manifest and the workspace agree (ADR 0043); this
    /// fails when a link's version, name or kind moves without the manifest.
    #[test]
    fn official_manifest_matches_the_workspace() {
        let src = Source {
            manifest: root().join(official::PATH),
            workspace: root().join("Cargo.toml"),
        };
        let o = checked(&src).unwrap();
        assert!(o.links.iter().any(|l| l.forms.wasm.is_some()));
        assert!(o.links.iter().any(|l| l.forms.process.is_some()));
    }

    fn krate(name: &str, version: &str, meta: serde_json::Value, cdylib: bool) -> CargoPackage {
        let mut targets = vec![CargoTarget {
            name: name.into(),
            kind: vec!["bin".into()],
        }];
        if cdylib {
            targets.push(CargoTarget {
                name: name.replace('-', "_"),
                kind: vec!["cdylib".into(), "rlib".into()],
            });
        }
        CargoPackage {
            name: name.into(),
            version: version.into(),
            description: Some("d".into()),
            manifest_path: "Cargo.toml".into(),
            metadata: Some(serde_json::json!({ "wyrm-link": meta })),
            targets,
        }
    }

    fn manifest(links: serde_json::Value) -> Official {
        let o = serde_json::json!({
            "format": official::FORMAT,
            "releases": "https://github.com/acme/wyrm/releases",
            "hosts": ["linux-x86_64"],
            "links": links,
        });
        official::parse(o.to_string().as_bytes()).unwrap()
    }

    fn link(id: &str, krate: &str, forms: serde_json::Value) -> serde_json::Value {
        serde_json::json!({ "id": id, "crate": krate, "title": id, "summary": "s",
            "category": "Apps", "version": "1.0.0", "wyrm_link": 1, "min_broker": "0.1.0",
            "forms": forms })
    }

    #[test]
    fn check_names_each_disagreement() {
        let crates = vec![
            krate(
                "wyrm-link-alarm",
                "1.0.0",
                serde_json::json!({ "name": "alarm", "kind": "wasm", "features": ["process"] }),
                true,
            ),
            krate(
                "wyrm-link-modbus",
                "1.0.1",
                serde_json::json!({ "name": "modbus", "features": ["process"] }),
                false,
            ),
        ];
        let ok = manifest(serde_json::json!([
            link(
                "alarm",
                "wyrm-link-alarm",
                serde_json::json!({ "wasm": "alarm", "process": "alarm-process" })
            ),
            link(
                "agent",
                "wyrm-link-alarm",
                serde_json::json!({ "builtin": "agent" })
            ),
        ]));
        assert_eq!(check(&ok, &crates), Vec::<String>::new());
        let bad = manifest(serde_json::json!([
            link(
                "gone",
                "wyrm-link-gone",
                serde_json::json!({ "builtin": "gone" })
            ),
            link(
                "modbus",
                "wyrm-link-modbus",
                serde_json::json!({ "wasm": "modbus-wasm", "process": "modbus-tcp" })
            ),
            link(
                "alarm",
                "wyrm-link-alarm",
                serde_json::json!({ "wasm": "alarms" })
            ),
        ]));
        let got = check(&bad, &crates).join("\n");
        for want in [
            "gone: no crate wyrm-link-gone",
            "modbus: version 1.0.0, crate wyrm-link-modbus is 1.0.1",
            "modbus: wasm form: the crate is not kind",
            "modbus: process form modbus-tcp, the crate packs modbus",
            "alarm: wasm form alarms, the crate packs alarm",
        ] {
            assert!(got.contains(want), "{want}\n{got}");
        }
    }
}
