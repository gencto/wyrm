//! `wyr dev`: hot reload of flow definitions. Polls `<dir>/*.json5` every
//! 500 ms (no file-watcher dependency); on a new or changed file: parse →
//! the engine's `validate` → `deploy` with one proof per command target
//! (as `wyr flow deploy`). The engine ignores a version ≤ the deployed one,
//! so a save without a version bump is deployed as `current + 1` (the file
//! is not rewritten). A deleted file leaves the deployed flow alone.

use crate::flow::{deploy_args, get_def, parse_def, root, validate};
use crate::{fmt_value, Error};
use std::collections::hash_map::DefaultHasher;
use std::collections::{BTreeMap, BTreeSet};
use std::hash::{Hash, Hasher};
use std::path::{Path, PathBuf};
use std::time::Duration;
use wyrm_client::WyrmClient;
use wyrm_core::Value;

pub const POLL: Duration = Duration::from_millis(500);

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Change {
    /// New or changed file with its text.
    Changed(PathBuf, String),
    Removed(PathBuf),
}

/// Content hashes of the files seen so far (the last attempt per file).
#[derive(Debug, Default)]
pub struct Scanner {
    seen: BTreeMap<PathBuf, u64>,
}

impl Scanner {
    /// Changes in `dir/*.json5` since the previous scan. A file that cannot
    /// be read now is skipped and tried again on the next scan.
    pub fn scan(&mut self, dir: &Path) -> Result<Vec<Change>, Error> {
        let mut now = BTreeSet::new();
        let mut out = Vec::new();
        let entries = std::fs::read_dir(dir).map_err(|e| format!("{}: {e}", dir.display()))?;
        let mut paths: Vec<PathBuf> = entries
            .filter_map(|e| e.ok().map(|e| e.path()))
            .filter(|p| p.extension().is_some_and(|x| x == "json5") && p.is_file())
            .collect();
        paths.sort();
        for p in paths {
            now.insert(p.clone());
            let Ok(text) = std::fs::read_to_string(&p) else {
                continue;
            };
            let mut h = DefaultHasher::new();
            text.hash(&mut h);
            let h = h.finish();
            if self.seen.insert(p.clone(), h) != Some(h) {
                out.push(Change::Changed(p, text));
            }
        }
        let gone: Vec<PathBuf> = self
            .seen
            .keys()
            .filter(|p| !now.contains(*p))
            .cloned()
            .collect();
        for p in gone {
            self.seen.remove(&p);
            out.push(Change::Removed(p));
        }
        Ok(out)
    }
}

fn get_str<'a>(m: &'a BTreeMap<String, Value>, k: &str) -> Option<&'a str> {
    match m.get(k) {
        Some(Value::Str(s)) => Some(s),
        _ => None,
    }
}

fn version_of(def: &Value) -> u64 {
    match def {
        Value::Map(m) => match m.get("version") {
            Some(Value::UInt(v)) => *v,
            _ => 0,
        },
        _ => 0,
    }
}

/// Validate and deploy one definition text. Returns what happened.
pub async fn apply(c: &WyrmClient, site: &str, text: &str) -> Result<String, Error> {
    let mut def = parse_def(text)?;
    let Value::Map(m) = &def else {
        return Err("flow definition must be an object".into());
    };
    let id = get_str(m, "id").ok_or("id: required")?.to_owned();
    validate(c, site, def.clone()).await?;
    let file_version = version_of(&def);
    let current = get_def(c, &format!("{}/{id}", root(site)))
        .await
        .ok()
        .map(|d| version_of(&d));
    let mut note = String::new();
    if let Some(cur) = current.filter(|cur| file_version <= *cur) {
        if let Value::Map(m) = &mut def {
            m.insert("version".into(), Value::UInt(cur + 1));
        }
        note = format!(" (file says v{file_version}, deployed v{cur})");
    }
    let version = version_of(&def);
    let args = deploy_args(def, site, &|k| c.proof(k))?;
    match c.invoke_one(&root(site), "deploy", args).await? {
        None => {}
        Some(Value::Map(m)) if m.is_empty() => {}
        Some(v) => note.push_str(&format!(" → {}", fmt_value(&v))),
    }
    Ok(format!("{id} v{version} deployed{note}"))
}

pub async fn run(c: &WyrmClient, site: &str, dir: &Path) -> Result<(), Error> {
    if !dir.is_dir() {
        return Err(format!("{}: not a directory", dir.display()).into());
    }
    let mut scanner = Scanner::default();
    out!(
        "watching {}/*.json5 → {} (Ctrl-C to stop)",
        dir.display(),
        root(site)
    );
    let mut tick = tokio::time::interval(POLL);
    tick.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
    loop {
        tokio::select! {
            _ = tokio::signal::ctrl_c() => return Ok(()),
            _ = tick.tick() => {}
        }
        let changes = match scanner.scan(dir) {
            Ok(c) => c,
            Err(e) => {
                out!("{e}");
                continue;
            }
        };
        for ch in changes {
            match ch {
                Change::Changed(p, text) => match apply(c, site, &text).await {
                    Ok(msg) => out!("{}: {msg}", p.display()),
                    Err(e) => out!("{}: {e}", p.display()),
                },
                Change::Removed(p) => out!(
                    "{}: removed; the deployed flow stays (wyr flow remove {site} <id>)",
                    p.display()
                ),
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Arc;
    use wyrm_client::SigningTokens;
    use wyrm_flow::{Engine, EngineStart, FlowHost};
    use wyrm_link_sdk::harness::{isolated_config, TEST_KEY_SEED};
    use wyrm_link_sdk::LinkConfig;

    fn temp(name: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("wyr-dev-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        d
    }

    #[test]
    fn scanner_sees_new_changed_and_removed_files() {
        let d = temp("scan");
        let mut s = Scanner::default();
        assert_eq!(s.scan(&d).unwrap(), vec![]);
        std::fs::write(d.join("a.json5"), "{id: \"a\"}").unwrap();
        std::fs::write(d.join("notes.txt"), "ignored").unwrap();
        assert_eq!(
            s.scan(&d).unwrap(),
            vec![Change::Changed(d.join("a.json5"), "{id: \"a\"}".into())]
        );
        assert_eq!(s.scan(&d).unwrap(), vec![], "no change, no event");
        std::fs::write(d.join("a.json5"), "{id: \"a\", version: 2}").unwrap();
        assert!(matches!(&s.scan(&d).unwrap()[..], [Change::Changed(..)]));
        std::fs::remove_file(d.join("a.json5")).unwrap();
        assert_eq!(
            s.scan(&d).unwrap(),
            vec![Change::Removed(d.join("a.json5"))]
        );
        assert!(s.scan(&d.join("missing")).is_err());
        let _ = std::fs::remove_dir_all(&d);
    }

    const SITE: &str = "test";

    fn def(version: u64, expr: &str) -> String {
        format!(
            r#"{{
                id: "f1", version: {version},
                nodes: {{
                    a: {{ type: "subscribe", key: "downstream/mock/p0" }},
                    x: {{ type: "expression", inputs: ["a"], expr: "{expr}" }},
                    o: {{ type: "publish", node: "o" }},
                }},
                edges: [["a.out", "x.in.a"], ["x.out", "o.in"]],
            }}"#
        )
    }

    /// Validate + deploy against an in-process engine, as `wyr dev` does
    /// against a dev broker.
    #[tokio::test(flavor = "multi_thread")]
    async fn validates_deploys_and_bumps_versions() {
        let dir = temp("engine");
        let session = zenoh::open(isolated_config()).await.unwrap();
        let key = ed25519_dalek::SigningKey::from_bytes(&TEST_KEY_SEED);
        let host = FlowHost::open(&dir, b"wyr-dev-test-hmac", SITE).unwrap();
        let mut lcfg = LinkConfig::new(SITE, "dataflows");
        lcfg.root = Some(format!("wy/{SITE}/dataflows"));
        lcfg.admin_keys = vec![key.verifying_key()];
        let engine = wyrm_link_sdk::spawn::<Engine>(
            session.clone(),
            lcfg,
            EngineStart {
                host,
                admin_keys: vec![key.verifying_key()],
                proof_keys: Vec::new(),
            },
        )
        .await
        .unwrap();
        let c = WyrmClient::new(session.clone())
            .with_tokens(Arc::new(SigningTokens::new(key, SITE)))
            .with_timeout(Duration::from_secs(3));

        let r = apply(&c, SITE, &def(1, "a.v * 2.0")).await.unwrap();
        assert_eq!(r, "f1 v1 deployed");
        // same version saved again: deployed as current + 1
        let r = apply(&c, SITE, &def(1, "a.v * 3.0")).await.unwrap();
        assert!(r.starts_with("f1 v2 deployed"), "{r}");
        let d = get_def(&c, &format!("wy/{SITE}/dataflows/f1"))
            .await
            .unwrap();
        assert_eq!(version_of(&d), 2);
        // a newer file version is kept
        let r = apply(&c, SITE, &def(7, "a.v")).await.unwrap();
        assert_eq!(r, "f1 v7 deployed");
        // compile errors come from the engine; nothing is deployed
        let e = apply(&c, SITE, &def(8, "b.v")).await.unwrap_err();
        assert!(e.to_string().contains("nodes.x.expr"), "{e}");
        let d = get_def(&c, &format!("wy/{SITE}/dataflows/f1"))
            .await
            .unwrap();
        assert_eq!(version_of(&d), 7);
        assert!(apply(&c, SITE, "{ broken").await.is_err());

        // the watcher path end to end: file → scan → apply
        let flows = dir.join("flows");
        std::fs::create_dir_all(&flows).unwrap();
        std::fs::write(flows.join("f1.json5"), def(7, "a.v + 1.0")).unwrap();
        let mut s = Scanner::default();
        let changes = s.scan(&flows).unwrap();
        let [Change::Changed(_, text)] = &changes[..] else {
            panic!("{changes:?}")
        };
        let r = apply(&c, SITE, text).await.unwrap();
        assert!(r.starts_with("f1 v8 deployed"), "{r}");

        engine.stop().await;
        let _ = std::fs::remove_dir_all(&dir);
    }
}
