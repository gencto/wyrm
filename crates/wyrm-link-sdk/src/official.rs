//! The official links manifest (ADR 0043): `links/official.json`, the one
//! checked-in list of the links this project releases, and the repository
//! index (ADR 0021) made from it.
//!
//! The manifest states intent: which links are official, in which forms and
//! at which version. It holds no URL of a file and no hash. The release job
//! builds the packages and [`Official::index`] writes the index with their
//! URLs and SHA-256; a broker reads that index like any other repository.
//! The broker also carries the manifest it was built with (`wyrm-admin`
//! embeds it), so it knows the title and category of its built-in drivers
//! with no network.

use crate::package::{self, Asset, Manifest, RepoEntry};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, HashSet};

/// `format` of the manifest.
pub const FORMAT: &str = "wyrm-official-links/1";
/// The index file among the assets of a release.
pub const INDEX_FILE: &str = "links-index.json";
/// The release that always holds the current index (its one asset is
/// replaced by each links release); the packages stay in their own release.
pub const INDEX_TAG: &str = "links-index";
/// `packages.repository` value that means [`Official::index_url`].
pub const KEYWORD: &str = "official";
/// The manifest's place in the workspace.
pub const PATH: &str = "links/official.json";
/// Hosts a process package can be built for ([`package::host_of_triple`]).
pub const HOSTS: [&str; 4] = [
    "linux-aarch64",
    "linux-x86_64",
    "macos-aarch64",
    "macos-x86_64",
];

const MAX_TITLE: usize = 64;
const MAX_SUMMARY: usize = 200;
const MAX_CATEGORY: usize = 32;

/// `links/official.json`. Unknown fields are refused.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Official {
    pub format: String,
    /// The releases of the project, `https://github.com/<owner>/<repo>/releases`:
    /// the index is `<releases>/download/links-index/links-index.json`, a
    /// package of release `<tag>` is `<releases>/download/<tag>/<file>`.
    pub releases: String,
    /// Hosts every process form is built for (`<os>-<arch>`).
    pub hosts: Vec<String>,
    pub links: Vec<OfficialLink>,
}

/// One official link.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct OfficialLink {
    /// The link's name in lists: a key segment, unique.
    pub id: String,
    /// The workspace crate it is built from.
    #[serde(rename = "crate")]
    pub krate: String,
    pub title: String,
    pub summary: String,
    pub category: String,
    /// The crate's version (checked by `wyr repo check`).
    pub version: String,
    /// The link protocol its packages are built for.
    pub wyrm_link: u32,
    /// The oldest broker that runs it, `major.minor.patch`.
    pub min_broker: String,
    pub forms: Forms,
}

/// The forms a link ships in; at least one.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Forms {
    /// A driver compiled into `wyrmd`: its name in `sys/links` ▸ `install`.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub builtin: Option<String>,
    /// A WASM package (one file for every host): its package name.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub wasm: Option<String>,
    /// A process package (one file per host): its package name.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub process: Option<String>,
}

impl Forms {
    /// `builtin`, `wasm`, `process`, those present.
    pub fn names(&self) -> Vec<&'static str> {
        [
            ("builtin", &self.builtin),
            ("wasm", &self.wasm),
            ("process", &self.process),
        ]
        .into_iter()
        .filter_map(|(n, f)| f.as_ref().map(|_| n))
        .collect()
    }
}

/// A package zip that was built: its file name, manifest and SHA-256.
#[derive(Debug, Clone)]
pub struct Built {
    pub file: String,
    pub manifest: Manifest,
    pub sha256: String,
}

fn text(what: &str, v: &str, max: usize) -> Result<(), String> {
    if v.trim().is_empty() || v.len() > max || v.chars().any(char::is_control) || v.trim() != v {
        return Err(format!("{what} {v:?}: 1 to {max} bytes, one line"));
    }
    Ok(())
}

/// `1`, `1.2` or `1.2.3` as numbers; a suffix after `-` or `+` is dropped.
fn triple(v: &str) -> Option<[u64; 3]> {
    let core = v.split(['-', '+']).next()?;
    let mut out = [0; 3];
    let mut n = 0;
    for part in core.split('.') {
        *out.get_mut(n)? = part.parse().ok()?;
        n += 1;
    }
    (n > 0).then_some(out)
}

/// `have` is `min` or newer. A version that is not numbers is not.
pub fn version_at_least(have: &str, min: &str) -> bool {
    matches!((triple(have), triple(min)), (Some(h), Some(m)) if h >= m)
}

/// `min_broker` is a version [`version_at_least`] can compare.
pub fn valid_min_broker(v: &str) -> bool {
    triple(v).is_some() && package::valid_version(v)
}

/// Parse and check a manifest.
pub fn parse(bytes: &[u8]) -> Result<Official, String> {
    let o: Official = serde_json::from_slice(bytes).map_err(|e| format!("manifest: {e}"))?;
    if o.format != FORMAT {
        return Err(format!("manifest: format {:?}, not {FORMAT}", o.format));
    }
    if !o.releases.starts_with("https://") || o.releases.ends_with('/') || o.releases.contains('?')
    {
        return Err(format!(
            "manifest: releases {:?}: an https URL without a trailing '/'",
            o.releases
        ));
    }
    let mut hosts = HashSet::new();
    for h in &o.hosts {
        if !HOSTS.contains(&h.as_str()) || !hosts.insert(h.as_str()) {
            return Err(format!(
                "manifest: host {h:?}: one of {}, once",
                HOSTS.join(", ")
            ));
        }
    }
    let (mut ids, mut names, mut drivers) = (HashSet::new(), HashSet::new(), HashSet::new());
    for l in &o.links {
        let bad = |what: String| format!("manifest: {}: {what}", l.id);
        package::valid_name(&l.id).map_err(|e| format!("manifest: id: {e}"))?;
        if !ids.insert(l.id.as_str()) {
            return Err(bad("twice".into()));
        }
        text("title", &l.title, MAX_TITLE).map_err(bad)?;
        text("summary", &l.summary, MAX_SUMMARY).map_err(bad)?;
        text("category", &l.category, MAX_CATEGORY).map_err(bad)?;
        if l.krate.is_empty() {
            return Err(bad("crate: required".into()));
        }
        if !package::valid_version(&l.version) {
            return Err(bad(format!("version {:?}", l.version)));
        }
        if !valid_min_broker(&l.min_broker) {
            return Err(bad(format!(
                "min_broker {:?}: major.minor.patch",
                l.min_broker
            )));
        }
        if l.forms.names().is_empty() {
            return Err(bad("no form: builtin, wasm or process".into()));
        }
        if l.forms.process.is_some() && o.hosts.is_empty() {
            return Err(bad("a process form needs `hosts`".into()));
        }
        for name in [&l.forms.wasm, &l.forms.process].into_iter().flatten() {
            package::valid_name(name).map_err(|e| bad(format!("package: {e}")))?;
            if !names.insert(name.as_str()) {
                return Err(bad(format!("package {name} twice in the manifest")));
            }
        }
        if let Some(d) = &l.forms.builtin {
            package::valid_name(d).map_err(|e| bad(format!("builtin: {e}")))?;
            if !drivers.insert(d.as_str()) {
                return Err(bad(format!("driver {d} twice in the manifest")));
            }
        }
    }
    Ok(o)
}

impl Official {
    /// Where a broker reads the official index.
    pub fn index_url(&self) -> String {
        format!("{}/download/{INDEX_TAG}/{INDEX_FILE}", self.releases)
    }

    /// The directory of the files of release `tag`.
    pub fn asset_base(&self, tag: &str) -> String {
        format!("{}/download/{tag}", self.releases)
    }

    /// The link that has built-in driver `driver`.
    pub fn by_driver(&self, driver: &str) -> Option<&OfficialLink> {
        self.links
            .iter()
            .find(|l| l.forms.builtin.as_deref() == Some(driver))
    }

    /// The link that ships package `name`, and the form (`wasm`, `process`).
    pub fn by_package(&self, name: &str) -> Option<(&OfficialLink, &'static str)> {
        self.links.iter().find_map(|l| {
            if l.forms.wasm.as_deref() == Some(name) {
                Some((l, "wasm"))
            } else if l.forms.process.as_deref() == Some(name) {
                Some((l, "process"))
            } else {
                None
            }
        })
    }

    /// The repository index of this manifest from the packages `built`:
    /// one entry per package form, each file at `<base>/<file>` (`base`
    /// absent: relative to the index, for a mirror). Refused: a zip that is
    /// no form of an official link, a zip of another version, kind or
    /// protocol, a host outside `hosts`, the same file twice. A form or a
    /// host with no zip is refused too, unless `partial` (a local run).
    pub fn index(
        &self,
        built: &[Built],
        base: Option<&str>,
        partial: bool,
    ) -> Result<Vec<RepoEntry>, String> {
        let url = |file: &str| match base {
            Some(b) => format!("{}/{file}", b.trim_end_matches('/')),
            None => file.to_owned(),
        };
        for b in built {
            if self.by_package(&b.manifest.name).is_none() {
                return Err(format!(
                    "{}: package {} is not in the manifest",
                    b.file, b.manifest.name
                ));
            }
        }
        let mut index = Vec::new();
        for l in &self.links {
            for (form, name) in [("wasm", &l.forms.wasm), ("process", &l.forms.process)] {
                let Some(name) = name else { continue };
                let zips: Vec<&Built> = built.iter().filter(|b| &b.manifest.name == name).collect();
                for b in &zips {
                    let m = &b.manifest;
                    let bad = |what: String| format!("{}: {what}", b.file);
                    if m.kind != form {
                        return Err(bad(format!("kind {}, the manifest says {form}", m.kind)));
                    }
                    if m.version != l.version {
                        return Err(bad(format!(
                            "version {}, the manifest says {}",
                            m.version, l.version
                        )));
                    }
                    if m.wyrm_link != l.wyrm_link {
                        return Err(bad(format!(
                            "link protocol {}, the manifest says {}",
                            m.wyrm_link, l.wyrm_link
                        )));
                    }
                    // one entry per form: its hosts write and read the same store format
                    let first = &zips[0].manifest;
                    if (m.state(), m.reads_state()) != (first.state(), first.reads_state()) {
                        return Err(bad(format!(
                            "state {} reads {:?}, {} says state {} reads {:?}",
                            m.state(),
                            m.reads_state(),
                            zips[0].file,
                            first.state(),
                            first.reads_state()
                        )));
                    }
                }
                let mut e = RepoEntry {
                    name: name.clone(),
                    version: l.version.clone(),
                    description: l.summary.clone(),
                    title: l.title.clone(),
                    category: l.category.clone(),
                    link: l.id.clone(),
                    kind: Some(form.to_owned()),
                    wyrm_link: Some(l.wyrm_link),
                    min_broker: Some(l.min_broker.clone()),
                    // ADR 0048: what the zips' manifests name
                    state: zips.first().and_then(|b| b.manifest.state),
                    reads_state: zips.first().and_then(|b| b.manifest.reads_state.clone()),
                    ..RepoEntry::default()
                };
                if form == "wasm" {
                    match zips.as_slice() {
                        [] if partial => continue,
                        [] => return Err(format!("{name}: no zip of the wasm form")),
                        [b] => {
                            e.url = Some(url(&b.file));
                            e.sha256 = Some(b.sha256.clone());
                        }
                        _ => return Err(format!("{name}: more than one zip of the wasm form")),
                    }
                } else {
                    let mut assets = BTreeMap::new();
                    for b in &zips {
                        for host in b.manifest.entries.keys() {
                            if !self.hosts.contains(host) {
                                return Err(format!("{}: host {host} is not official", b.file));
                            }
                            let a = Asset {
                                url: url(&b.file),
                                sha256: b.sha256.clone(),
                            };
                            if assets.insert(host.clone(), a).is_some() {
                                return Err(format!("{name}: more than one zip for {host}"));
                            }
                        }
                    }
                    if let Some(h) = self.hosts.iter().find(|h| !assets.contains_key(*h)) {
                        if !partial {
                            return Err(format!("{name}: no zip for {h}"));
                        }
                    }
                    if assets.is_empty() {
                        continue;
                    }
                    e.assets = assets;
                }
                index.push(e);
            }
        }
        index.sort_by(|a, b| a.name.cmp(&b.name));
        // what a broker will read must pass its check
        let text = serde_json::to_vec(&index).map_err(|e| e.to_string())?;
        package::parse_index(&text)?;
        Ok(index)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn manifest() -> Official {
        parse(
            br#"{
            "format": "wyrm-official-links/1",
            "releases": "https://github.com/acme/wyrm/releases",
            "hosts": ["linux-x86_64", "macos-aarch64"],
            "links": [
              { "id": "alarm", "crate": "wyrm-link-alarm", "title": "Alarms", "summary": "Alarm records",
                "category": "Apps", "version": "1.2.0", "wyrm_link": 1, "min_broker": "0.1.0",
                "forms": { "wasm": "alarm", "process": "alarm-process" } },
              { "id": "modbus", "crate": "wyrm-link-modbus", "title": "Modbus", "summary": "Modbus devices",
                "category": "Equipment", "version": "1.0.0", "wyrm_link": 1, "min_broker": "0.1.0",
                "forms": { "builtin": "modbus", "process": "modbus" } }
            ] }"#,
        )
        .unwrap()
    }

    fn built(name: &str, version: &str, host: Option<&str>) -> Built {
        Built {
            file: match host {
                Some(h) => format!("{name}-{version}-{h}.zip"),
                None => format!("{name}-{version}.zip"),
            },
            manifest: Manifest {
                state: None,
                reads_state: None,
                name: name.into(),
                version: version.into(),
                description: String::new(),
                wyrm_link: 1,
                kind: if host.is_some() { "process" } else { "wasm" }.into(),
                entries: host
                    .map(|h| (h.to_owned(), format!("bin/{h}/run")))
                    .into_iter()
                    .collect(),
                args: vec![],
                entry: host.is_none().then(|| format!("{name}.wasm")),
                requester: vec![],
                world: None,
                capabilities: None,
            },
            sha256: "a".repeat(64),
        }
    }

    fn all() -> Vec<Built> {
        vec![
            built("alarm", "1.2.0", None),
            built("alarm-process", "1.2.0", Some("linux-x86_64")),
            built("alarm-process", "1.2.0", Some("macos-aarch64")),
            built("modbus", "1.0.0", Some("linux-x86_64")),
            built("modbus", "1.0.0", Some("macos-aarch64")),
        ]
    }

    #[test]
    fn index_from_manifest_and_zips() {
        let o = manifest();
        let base = o.asset_base("v1.0.0");
        let index = o.index(&all(), Some(&base), false).unwrap();
        assert_eq!(
            index.iter().map(|e| e.name.as_str()).collect::<Vec<_>>(),
            ["alarm", "alarm-process", "modbus"]
        );
        let wasm = &index[0];
        assert_eq!(
            wasm.url.as_deref(),
            Some("https://github.com/acme/wyrm/releases/download/v1.0.0/alarm-1.2.0.zip")
        );
        assert_eq!(
            (wasm.title.as_str(), wasm.category.as_str()),
            ("Alarms", "Apps")
        );
        assert_eq!(wasm.description, "Alarm records");
        assert_eq!(
            (wasm.link.as_str(), wasm.kind.as_deref()),
            ("alarm", Some("wasm"))
        );
        assert_eq!(wasm.version, "1.2.0");
        let proc = &index[1];
        assert_eq!(proc.link, "alarm");
        assert_eq!(proc.kind.as_deref(), Some("process"));
        assert_eq!(proc.assets.len(), 2);
        // a mirror: file names beside the index
        let rel = o.index(&all(), None, false).unwrap();
        assert_eq!(rel[0].url.as_deref(), Some("alarm-1.2.0.zip"));
    }

    #[test]
    fn index_refuses_what_the_manifest_does_not_say() {
        let o = manifest();
        let err = |b: Vec<Built>| o.index(&b, None, false).unwrap_err();
        let mut b = all();
        b.push(built("rogue", "1.0.0", None));
        assert!(err(b).contains("not in the manifest"));
        let mut b = all();
        b[0] = built("alarm", "1.3.0", None);
        assert!(err(b).contains("version 1.3.0"));
        let mut b = all();
        b.remove(4);
        assert!(err(b.clone()).contains("modbus: no zip for macos-aarch64"));
        // a local run may build less
        let part = o.index(&b, None, true).unwrap();
        assert_eq!(part[2].assets.len(), 1);
        let part = o.index(&b[..1], None, true).unwrap();
        assert_eq!(part.len(), 1);
        let mut b = all();
        b.remove(0);
        assert!(err(b).contains("alarm: no zip of the wasm form"));
        let mut b = all();
        b.push(built("modbus", "1.0.0", Some("linux-aarch64")));
        assert!(err(b).contains("not official"));
        let mut b = all();
        b.push(built("modbus", "1.0.0", Some("linux-x86_64")));
        assert!(err(b).contains("more than one zip"));
        // the process form's name with a wasm zip
        let mut b = all();
        b[1] = built("alarm-process", "1.2.0", None);
        assert!(err(b).contains("kind wasm"));
        let mut b = all();
        b[0].manifest.wyrm_link = 2;
        assert!(err(b).contains("link protocol 2"));
    }

    #[test]
    fn manifest_checks() {
        let edit = |from: &str, to: &str| {
            let text = serde_json::to_string(&manifest()).unwrap();
            assert!(text.contains(from), "{from}");
            parse(text.replacen(from, to, 1).as_bytes())
        };
        assert!(edit("\"alarm\"", "\"alarm\"").is_ok());
        for (from, to, why) in [
            ("wyrm-official-links/1", "wyrm-official-links/9", "format"),
            ("https://github.com", "http://github.com", "releases"),
            ("\"linux-x86_64\"", "\"plan9-mips\"", "host"),
            ("\"id\":\"modbus\"", "\"id\":\"alarm\"", "twice"),
            ("\"Alarms\"", "\"\"", "title"),
            ("\"0.1.0\"", "\"soon\"", "min_broker"),
            (
                "{\"wasm\":\"alarm\",\"process\":\"alarm-process\"}",
                "{}",
                "no form",
            ),
            ("\"alarm-process\"", "\"modbus\"", "package modbus twice"),
            ("\"1.2.0\"", "\"1 2\"", "version"),
        ] {
            let e = edit(from, to).unwrap_err();
            assert!(e.contains(why), "{why}: {e}");
        }
        assert!(parse(br#"{"format":"wyrm-official-links/1","releases":"https://x/r","hosts":[],"links":[],"sha":1}"#).is_err());
    }

    #[test]
    fn versions_compare_as_numbers() {
        assert!(version_at_least("0.10.0", "0.9.3"));
        assert!(version_at_least("1.0.0", "1"));
        assert!(version_at_least("0.1.0-rc1", "0.1.0"));
        assert!(!version_at_least("0.1.0", "0.2.0"));
        assert!(!version_at_least("next", "0.1.0"));
        assert!(!valid_min_broker("1.2.3.4"));
        assert!(!valid_min_broker(""));
    }
}
