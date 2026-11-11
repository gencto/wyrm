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
/// (`builtin`, `wasm`, `process`) and `official` (the manifest names it; a
/// label, not a check: the SHA-256 of the index is the check).
pub fn catalog(drivers: &[&str], repo: &[RepoEntry], broker_version: &str) -> Value {
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
        let known = o.by_package(&e.name);
        let pick = |own: &str, from: fn(&official::OfficialLink) -> &str| -> String {
            if own.is_empty() {
                known.map_or("", |(l, _)| from(l)).to_owned()
            } else {
                own.to_owned()
            }
        };
        let title = pick(&e.title, |l| &l.title);
        let form = e
            .kind
            .clone()
            .or_else(|| known.map(|(_, f)| f.to_owned()))
            .unwrap_or_else(|| {
                if e.assets.is_empty() {
                    "wasm"
                } else {
                    "process"
                }
                .to_owned()
            });
        rows.push(row([
            ("id", s(&format!("package:{}", e.name))),
            ("code", s(&e.name)),
            ("link", s(&pick(&e.link, |l| &l.id))),
            ("title", s(if title.is_empty() { &e.name } else { &title })),
            ("summary", s(&pick(&e.description, |l| &l.summary))),
            ("category", s(&pick(&e.category, |l| &l.category))),
            ("version", s(&e.version)),
            ("form", s(&form)),
            ("official", Value::Bool(known.is_some())),
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

    #[test]
    fn catalog_rows_carry_title_and_version() {
        let host = platform();
        let sha = "a".repeat(64);
        let repo = vec![
            // an official index entry: its own fields
            RepoEntry {
                name: "alarm".into(),
                version: "0.2.0".into(),
                url: Some("alarm.zip".into()),
                sha256: Some(sha.clone()),
                title: "Alarms".into(),
                kind: Some("wasm".into()),
                link: "alarm".into(),
                ..RepoEntry::default()
            },
            // an ADR 0021 index (wyr repo add): the manifest fills in
            RepoEntry {
                name: "alarm-process".into(),
                version: "0.1.9".into(),
                assets: [(
                    host.clone(),
                    wyrm_link_sdk::package::Asset {
                        url: "a.zip".into(),
                        sha256: sha.clone(),
                    },
                )]
                .into(),
                ..RepoEntry::default()
            },
            // not built for this host: not offered
            RepoEntry {
                name: "elsewhere".into(),
                version: "1.0.0".into(),
                assets: [(
                    "plan9-mips".to_owned(),
                    wyrm_link_sdk::package::Asset {
                        url: "e.zip".into(),
                        sha256: sha.clone(),
                    },
                )]
                .into(),
                ..RepoEntry::default()
            },
            RepoEntry {
                name: "third-party".into(),
                version: "3.0.0".into(),
                url: Some("t.zip".into()),
                sha256: Some(sha),
                ..RepoEntry::default()
            },
        ];
        let Value::Array(rows) = catalog(&["modbus", "wasm"], &repo, "0.1.0") else {
            panic!("an array")
        };
        assert_eq!(rows.len(), 5);
        assert_eq!(field(&rows[0], "id"), "driver:modbus");
        assert_eq!(field(&rows[0], "title"), "Modbus");
        assert_eq!(field(&rows[0], "category"), "Equipment");
        assert_eq!(field(&rows[0], "version"), "0.1.0");
        assert_eq!(field(&rows[0], "form"), "builtin");
        assert_eq!(
            field(&rows[1], "title"),
            "wasm",
            "no manifest entry: its name"
        );
        assert_eq!(field(&rows[2], "id"), "package:alarm");
        assert_eq!(field(&rows[2], "version"), "0.2.0");
        assert_eq!(field(&rows[3], "title"), "Alarms");
        assert_eq!(field(&rows[3], "link"), "alarm");
        assert_eq!(field(&rows[3], "form"), "process");
        assert_eq!(field(&rows[3], "version"), "0.1.9");
        assert_eq!(field(&rows[4], "title"), "third-party");
        assert_eq!(field(&rows[4], "form"), "wasm");
        let Value::Map(m) = &rows[4] else { panic!() };
        assert_eq!(m.get("official"), Some(&Value::Bool(false)));
    }
}
