//! The official links manifest in the broker (ADR 0043): the copy of
//! `links/official.json` this build was made with, `packages.repository:
//! "official"`, and the catalogue of `sys/links` (`attr.catalog`): one row
//! per built-in driver and per repository package this host can install,
//! with its title, summary, category, version and form.

use crate::packages::{platform, RepoEntry};
use std::collections::BTreeMap;
use wyrm_core::Value;
use wyrm_link_sdk::official::{self, Official};

/// `links/official.json` as this broker was built.
pub const EMBEDDED: &str = include_str!("../../../links/official.json");

/// The manifest this broker was built with.
pub fn embedded() -> &'static Official {
    static CELL: std::sync::OnceLock<Official> = std::sync::OnceLock::new();
    CELL.get_or_init(|| {
        official::parse(EMBEDDED.as_bytes()).expect("links/official.json is checked by a test")
    })
}

/// `packages.repository` as fetched: `official` is the official index of
/// the manifest this broker was built with; anything else as it is.
pub fn repository_url(configured: Option<&str>) -> Option<String> {
    match configured.map(str::trim) {
        None | Some("") => None,
        Some(official::KEYWORD) => Some(embedded().index_url()),
        Some(url) => Some(url.to_owned()),
    }
}

/// `url` (already resolved) is the official index of the embedded manifest.
pub fn is_official_index(url: Option<&str>) -> bool {
    url == Some(embedded().index_url().as_str())
}

fn row(fields: [(&str, Value); 9]) -> Value {
    Value::Map(
        fields
            .into_iter()
            .map(|(k, v)| (k.to_owned(), v))
            .collect::<BTreeMap<_, _>>(),
    )
}

fn s(v: &str) -> Value {
    Value::Str(v.to_owned())
}

/// The catalogue of `sys/links`: the `drivers` this broker hosts (version =
/// the broker's), then the repository packages built for this host (version
/// = the index's). Each row: `id` (`driver:<code>` or `package:<code>`),
/// `code` (the name `install` / `install_repo` takes), `link` (official link
/// id, empty when none), `title`, `summary`, `category`, `version`, `form`
/// (`builtin`, `wasm`, `process`) and `official`.
///
/// A driver is official when the embedded manifest names it (it is compiled
/// into this binary). A package is official only when `official_repo` (the
/// configured repository is the official index URL) and the embedded
/// manifest lists that package name with the same version and form. A
/// package's `title`, `summary`, `category` and `link` always come from its
/// own index entry, never from the manifest: a repository cannot borrow an
/// official name's description. The manifest holds no hashes; the SHA-256
/// of the index entry is checked at install (ADR 0021).
pub fn catalog(
    drivers: &[&str],
    repo: &[RepoEntry],
    official_repo: bool,
    broker_version: &str,
) -> Value {
    let o = embedded();
    let mut rows = Vec::new();
    for d in drivers {
        let l = o.by_driver(d);
        rows.push(row([
            ("id", s(&format!("driver:{d}"))),
            ("code", s(d)),
            ("link", s(l.map_or("", |l| &l.id))),
            ("title", s(l.map_or(d, |l| &l.title))),
            ("summary", s(l.map_or("", |l| &l.summary))),
            ("category", s(l.map_or("", |l| &l.category))),
            ("version", s(broker_version)),
            ("form", s("builtin")),
            ("official", Value::Bool(l.is_some())),
        ]));
    }
    let host = platform();
    for e in repo.iter().filter(|e| e.asset(&host).is_some()) {
        // what the zip is, from the index alone: a process package has a
        // file per host, one for every host is wasm
        let form = if e.assets.is_empty() {
            "wasm"
        } else {
            "process"
        };
        let official = official_repo
            && e.kind.as_deref().is_none_or(|k| k == form)
            && o.by_package(&e.name)
                .is_some_and(|(l, f)| f == form && l.version == e.version);
        let title = if e.title.is_empty() {
            &e.name
        } else {
            &e.title
        };
        rows.push(row([
            ("id", s(&format!("package:{}", e.name))),
            ("code", s(&e.name)),
            ("link", s(&e.link)),
            ("title", s(title)),
            ("summary", s(&e.description)),
            ("category", s(&e.category)),
            ("version", s(&e.version)),
            ("form", s(form)),
            ("official", Value::Bool(official)),
        ]));
    }
    Value::Array(rows)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_embedded_manifest_is_valid() {
        let o = embedded();
        assert!(!o.links.is_empty());
        for l in &o.links {
            assert_eq!(l.wyrm_link, wyrm_link_sdk::LINK_PROTOCOL, "{}", l.id);
            assert!(
                official::version_at_least(env!("CARGO_PKG_VERSION"), &l.min_broker),
                "{}: min_broker {} is newer than this broker",
                l.id,
                l.min_broker
            );
        }
    }

    #[test]
    fn official_keyword_and_plain_urls() {
        assert_eq!(repository_url(None), None);
        assert_eq!(repository_url(Some(" ")), None);
        let url = repository_url(Some("official")).unwrap();
        assert_eq!(
            url,
            "https://github.com/gencto/wyrm/releases/download/links-index/links-index.json"
        );
        assert_eq!(
            repository_url(Some("https://mirror.plant/links/index.json")).as_deref(),
            Some("https://mirror.plant/links/index.json")
        );
    }

    fn field<'a>(row: &'a Value, k: &str) -> &'a str {
        let Value::Map(m) = row else { panic!("a row") };
        match m.get(k) {
            Some(Value::Str(v)) => v,
            other => panic!("{k}: {other:?}"),
        }
    }

    fn wasm(name: &str, version: &str, title: &str) -> RepoEntry {
        RepoEntry {
            name: name.into(),
            version: version.into(),
            url: Some(format!("{name}.zip")),
            sha256: Some("a".repeat(64)),
            title: title.into(),
            ..RepoEntry::default()
        }
    }

    fn process(name: &str, version: &str, host: &str, title: &str) -> RepoEntry {
        RepoEntry {
            name: name.into(),
            version: version.into(),
            assets: [(
                host.to_owned(),
                wyrm_link_sdk::package::Asset {
                    url: format!("{name}.zip"),
                    sha256: "a".repeat(64),
                },
            )]
            .into(),
            title: title.into(),
            ..RepoEntry::default()
        }
    }

    fn rows(drivers: &[&str], repo: &[RepoEntry], official_repo: bool) -> Vec<Value> {
        match catalog(drivers, repo, official_repo, "0.1.0") {
            Value::Array(rows) => rows,
            v => panic!("an array: {v:?}"),
        }
    }

    fn official(row: &Value) -> bool {
        let Value::Map(m) = row else { panic!("a row") };
        m.get("official") == Some(&Value::Bool(true))
    }

    fn version_of(id: &str) -> String {
        embedded()
            .links
            .iter()
            .find(|l| l.id == id)
            .unwrap()
            .version
            .clone()
    }

    #[test]
    fn catalog_rows_carry_title_and_version() {
        let host = platform();
        let v = version_of("alarm");
        let repo = vec![
            RepoEntry {
                category: "Apps".into(),
                kind: Some("wasm".into()),
                link: "alarm".into(),
                ..wasm("alarm", &v, "Alarms")
            },
            // not the manifest's version: a package, not an official one
            process("alarm-process", "9.0.0", &host, ""),
            // not built for this host: not offered
            process("elsewhere", "1.0.0", "plan9-mips", "Elsewhere"),
        ];
        let rows = rows(&["modbus", "wasm"], &repo, true);
        assert_eq!(rows.len(), 4);
        assert_eq!(field(&rows[0], "id"), "driver:modbus");
        assert_eq!(field(&rows[0], "title"), "Modbus");
        assert_eq!(field(&rows[0], "category"), "Equipment");
        assert_eq!(field(&rows[0], "version"), "0.1.0");
        assert_eq!(field(&rows[0], "form"), "builtin");
        assert!(official(&rows[0]));
        assert_eq!(field(&rows[1], "title"), "wasm", "not in the manifest");
        assert!(!official(&rows[1]));
        assert_eq!(field(&rows[2], "id"), "package:alarm");
        assert_eq!(field(&rows[2], "title"), "Alarms");
        assert_eq!(field(&rows[2], "version"), v);
        assert_eq!(field(&rows[2], "form"), "wasm");
        assert!(official(&rows[2]));
        assert_eq!(field(&rows[3], "version"), "9.0.0");
        assert_eq!(field(&rows[3], "form"), "process");
        assert_eq!(
            field(&rows[3], "title"),
            "alarm-process",
            "never the manifest's"
        );
        assert_eq!(field(&rows[3], "category"), "");
        assert!(!official(&rows[3]), "another version than the manifest's");
    }

    /// A repository that is not the official index cannot make a package
    /// official by its name, nor borrow the manifest's description.
    #[test]
    fn a_third_party_index_is_never_official() {
        let host = platform();
        let repo = vec![
            process("modbus", &version_of("modbus"), &host, "Better Modbus"),
            wasm("alarm", &version_of("alarm"), ""),
        ];
        let third = rows(&[], &repo, false);
        assert_eq!(field(&third[0], "title"), "Better Modbus");
        assert_eq!(field(&third[0], "summary"), "");
        assert_eq!(field(&third[0], "link"), "");
        assert!(!official(&third[0]));
        assert_eq!(field(&third[1], "title"), "alarm");
        assert!(!official(&third[1]));
        // the same entries from the official index: official, own title kept
        let from_official = rows(&[], &repo, true);
        assert!(official(&from_official[0]));
        assert_eq!(field(&from_official[0], "title"), "Better Modbus");
        // the wasm form's name with a process zip is not the official form
        let wrong = rows(
            &[],
            &[process("alarm", &version_of("alarm"), &host, "")],
            true,
        );
        assert!(!official(&wrong[0]));
        assert!(is_official_index(
            repository_url(Some("official")).as_deref()
        ));
        assert!(!is_official_index(Some("https://mirror.plant/index.json")));
        assert!(!is_official_index(None));
    }
}
