//! The ready-made flows in `examples/flows/` ("quick solutions"): each one compiles as the
//! engine compiles a deploy, the engine's `validate` accepts it on a test site, and some of
//! them give the values their README promises when they run on the mock link.

use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::Duration;
use wyrm_client::{SigningTokens, WyrmClient};
use wyrm_core::{Sample, Value};
use wyrm_flow::{def, Engine, EngineStart, FlowHost};
use wyrm_link_mock::{Mock, MockConfig};
use wyrm_link_sdk::harness::{isolated_config, TEST_KEY_SEED};
use wyrm_link_sdk::{LinkConfig, LinkHandle};

const SITE: &str = "test";

fn dir() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../../examples/flows")
}

/// `(file stem, definition)` of every recipe, sorted by name.
fn recipes() -> Vec<(String, Value)> {
    let mut files: Vec<PathBuf> = std::fs::read_dir(dir())
        .expect("examples/flows")
        .map(|e| e.unwrap().path())
        .filter(|p| p.extension().is_some_and(|x| x == "json"))
        .collect();
    files.sort();
    files
        .into_iter()
        .map(|p| {
            let stem = p.file_stem().unwrap().to_string_lossy().into_owned();
            let text = std::fs::read_to_string(&p).unwrap();
            let j: serde_json::Value =
                serde_json::from_str(&text).unwrap_or_else(|e| panic!("{stem}.json: {e}"));
            (stem, json_to_value(&j))
        })
        .collect()
}

/// JSON → wire value, the mapping of `wyr flow` and `wyrmd`.
fn json_to_value(j: &serde_json::Value) -> Value {
    match j {
        serde_json::Value::Null => Value::Null,
        serde_json::Value::Bool(b) => Value::Bool(*b),
        serde_json::Value::Number(n) => {
            if let Some(u) = n.as_u64() {
                Value::UInt(u)
            } else if let Some(i) = n.as_i64() {
                Value::Int(i)
            } else {
                Value::Float(n.as_f64().unwrap_or(f64::NAN))
            }
        }
        serde_json::Value::String(s) => Value::Str(s.clone()),
        serde_json::Value::Array(a) => Value::Array(a.iter().map(json_to_value).collect()),
        serde_json::Value::Object(o) => Value::Map(
            o.iter()
                .map(|(k, v)| (k.clone(), json_to_value(v)))
                .collect(),
        ),
    }
}

fn get<'a>(v: &'a Value, k: &str) -> Option<&'a Value> {
    match v {
        Value::Map(m) => m.get(k),
        _ => None,
    }
}

fn text(v: &Value) -> Option<&str> {
    match v {
        Value::Str(s) => Some(s),
        _ => None,
    }
}

fn map(kv: &[(&str, Value)]) -> Value {
    Value::Map(
        kv.iter()
            .map(|(k, v)| ((*k).to_owned(), v.clone()))
            .collect(),
    )
}

#[test]
fn every_recipe_compiles() {
    let all = recipes();
    assert!(
        (10..=14).contains(&all.len()),
        "{} recipes, the README promises 10 to 14",
        all.len()
    );
    let readme = std::fs::read_to_string(dir().join("README.md")).unwrap();
    for (stem, d) in &all {
        assert_eq!(
            get(d, "id").and_then(text),
            Some(stem.as_str()),
            "{stem}.json: id is the file name"
        );
        assert!(
            get(d, "description").and_then(text).is_some(),
            "{stem}.json: a description"
        );
        assert!(
            readme.contains(&format!("{stem}.json")),
            "README.md: a line for {stem}.json"
        );
        let (flow, _) = def::compile(d).unwrap_or_else(|e| panic!("{stem}.json: {}", e.0));
        let targets = wyrm_flow::command_targets(d, SITE).unwrap();
        // a recipe never acts at a start on its own
        for (id, n) in &flow.nodes {
            if n.ty == "set" || n.ty == "invoke" {
                assert_ne!(
                    n.cfg.get("run_on_start"),
                    Some(&Value::Bool(true)),
                    "{stem}.json: nodes.{id}.run_on_start"
                );
            }
        }
        let maxperm = get(d, "permissions")
            .and_then(|p| get(p, "maxperm"))
            .and_then(text);
        if targets.is_empty() {
            assert_eq!(maxperm, None, "{stem}.json: no commands, no maxperm");
        } else {
            assert_eq!(maxperm, Some("write"), "{stem}.json: maxperm write");
        }
    }
}

struct Env {
    client: WyrmClient,
    mock: Option<LinkHandle<Mock>>,
    engine: Option<LinkHandle<Engine>>,
}

impl Env {
    async fn start(name: &str) -> Self {
        let dir = std::env::temp_dir().join(format!("wyrm-recipes-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let session = zenoh::open(isolated_config()).await.unwrap();
        let key = ed25519_dalek::SigningKey::from_bytes(&TEST_KEY_SEED);
        let host = FlowHost::open(&dir, b"flow-test-hmac-key", SITE).unwrap();
        let mut lcfg = LinkConfig::new(SITE, "mock");
        lcfg.admin_keys = vec![key.verifying_key(), host.verifying_key()];
        let mock = wyrm_link_sdk::spawn::<Mock>(
            session.clone(),
            lcfg,
            MockConfig {
                points: 4,
                rate_hz: 20.0,
                depth: 0,
                fanout: 1,
                writable: true,
            },
        )
        .await
        .unwrap();
        let mut ecfg = LinkConfig::new(SITE, "dataflows");
        ecfg.root = Some(format!("wy/{SITE}/dataflows"));
        ecfg.admin_keys = vec![key.verifying_key()];
        let engine = wyrm_link_sdk::spawn::<Engine>(
            session.clone(),
            ecfg,
            EngineStart {
                host,
                admin_keys: vec![key.verifying_key()],
                proof_keys: Vec::new(),
            },
        )
        .await
        .unwrap();
        let client = WyrmClient::new(session)
            .with_tokens(Arc::new(SigningTokens::new(key, SITE)))
            .with_timeout(Duration::from_secs(3));
        Self {
            client,
            mock: Some(mock),
            engine: Some(engine),
        }
    }

    /// The engine's own check of a deploy (`dataflows ▸ validate`): `None` when it passes.
    async fn validate(&self, def: &Value) -> Option<String> {
        let r = self
            .client
            .invoke_one(
                &format!("wy/{SITE}/dataflows"),
                "validate",
                map(&[("def", def.clone())]),
            )
            .await
            .unwrap()
            .unwrap_or(Value::Null);
        match get(&r, "ok") {
            Some(Value::Bool(true)) => None,
            _ => Some(format!("{r:?}")),
        }
    }

    async fn deploy(&self, def: Value) {
        let proofs = wyrm_flow::command_targets(&def, SITE)
            .unwrap()
            .into_iter()
            .filter_map(|t| self.client.proof(&t).map(|p| (t, Value::Bytes(p))))
            .collect();
        self.client
            .invoke_one(
                &format!("wy/{SITE}/dataflows"),
                "deploy",
                map(&[("def", def), ("proofs", Value::Map(proofs))]),
            )
            .await
            .unwrap();
    }

    fn last(&self, path: &str) -> Option<Sample> {
        self.engine.as_ref().unwrap().ctx().last(path)
    }

    async fn stop(mut self) {
        if let Some(e) = self.engine.take() {
            e.stop().await;
        }
        if let Some(m) = self.mock.take() {
            m.stop().await;
        }
    }
}

/// The flow value `<flow>/nodes/<node>` once `ok` accepts it.
async fn wait_for(env: &Env, path: &str, ok: impl Fn(&Value) -> bool) -> Value {
    let deadline = tokio::time::Instant::now() + Duration::from_secs(8);
    loop {
        let last = env.last(path);
        if let Some(s) = &last {
            if ok(&s.v) {
                return s.v.clone();
            }
        }
        assert!(
            tokio::time::Instant::now() < deadline,
            "timeout: {path}, last {last:?}"
        );
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
}

fn near(want: f64) -> impl Fn(&Value) -> bool {
    move |v| v.as_f64().is_some_and(|x| (x - want).abs() < 1e-9)
}

#[tokio::test(flavor = "multi_thread")]
async fn recipes_validate_deploy_and_run_on_the_mock() {
    let env = Env::start("all").await;
    // fixed values before any flow reads them: p0 25 °C (or kW), p1 12 mA, p2 30 °C
    for (p, v) in [("p0", 25.0), ("p1", 12.0), ("p2", 30.0)] {
        env.client
            .set(&format!("wy/{SITE}/downstream/mock/{p}"), v)
            .await
            .unwrap();
    }
    tokio::time::sleep(Duration::from_millis(200)).await;
    let p3_before = env.mock.as_ref().unwrap().ctx().last("p3");

    for (stem, d) in recipes() {
        if let Some(e) = env.validate(&d).await {
            panic!("{stem}.json: the engine refuses it: {e}");
        }
        if stem == "json_fields" {
            continue; // runs below with a text in place of its source point
        }
        env.deploy(d).await;
    }

    // a JSON text in place of the storage point
    let mut json = recipes()
        .into_iter()
        .find(|(s, _)| s == "json_fields")
        .unwrap()
        .1;
    if let Value::Map(m) = &mut json {
        if let Some(Value::Map(nodes)) = m.get_mut("nodes") {
            nodes.insert(
                "src".into(),
                map(&[
                    ("type", Value::from("string")),
                    (
                        "value",
                        Value::from(
                            r#"{"temperature": 21.5, "status": "running", "alarms": ["a1"]}"#,
                        ),
                    ),
                ]),
            );
        }
    }
    env.deploy(json).await;

    // average_min_max: (25 + 12 + 30) / 3
    wait_for(&env, "average_min_max/nodes/avg", near(22.33)).await;
    wait_for(&env, "average_min_max/nodes/max", near(30.0)).await;
    wait_for(&env, "average_min_max/nodes/min", near(12.0)).await;
    // unit_conversion: 25 °C = 77 °F; 12 mA in 4–20 = 5 bar
    wait_for(&env, "unit_conversion/nodes/temp_f", near(77.0)).await;
    wait_for(&env, "unit_conversion/nodes/pressure", near(5.0)).await;
    wait_for(&env, "unit_conversion/nodes/sensor_fault", |v| {
        *v == Value::Bool(false)
    })
    .await;
    // status_text
    wait_for(&env, "status_text/nodes/status", |v| {
        text(v) == Some("Tank 1: 25.0 °C, OK")
    })
    .await;
    // threshold_alarm: 25 is below 28, and an alarm sends `out` only when it changes
    assert!(
        env.last("threshold_alarm/nodes/active")
            .is_none_or(|s| s.v == Value::Bool(false)),
        "threshold_alarm raised at 25"
    );
    // running_hours: 25 > 20, so the pump runs and the stopwatch counts
    wait_for(&env, "running_hours/nodes/running", |v| {
        *v == Value::Bool(true)
    })
    .await;
    wait_for(&env, "running_hours/nodes/seconds", |v| {
        v.as_f64().is_some_and(|x| x >= 1.0)
    })
    .await;
    // daily_energy: 25 kW for a moment is more than 0 kWh
    wait_for(&env, "daily_energy/nodes/energy_today", |v| {
        v.as_f64().is_some_and(|x| x > 0.0)
    })
    .await;
    // rate_of_change: a constant has no slope
    wait_for(&env, "rate_of_change/nodes/rate_per_min", |v| {
        v.as_f64().is_some_and(|x| x.abs() < 1e-6)
    })
    .await;
    // stale_watchdog: fresh samples, the link is up
    wait_for(&env, "stale_watchdog/nodes/stale", |v| {
        *v == Value::Bool(false)
    })
    .await;
    wait_for(&env, "stale_watchdog/nodes/link_up", |v| {
        *v == Value::Bool(true)
    })
    .await;
    // rolling_table: rows of 25
    wait_for(
        &env,
        "rolling_table/nodes/last_samples",
        |v| matches!(get(v, "rows"), Some(Value::Array(r)) if !r.is_empty()),
    )
    .await;
    wait_for(&env, "rolling_table/nodes/avg_last", near(25.0)).await;
    // json_fields
    wait_for(&env, "json_fields/nodes/temperature", near(21.5)).await;
    wait_for(&env, "json_fields/nodes/state", |v| {
        text(v) == Some("running")
    })
    .await;
    wait_for(&env, "json_fields/nodes/first_alarm", |v| {
        text(v) == Some("a1")
    })
    .await;
    wait_for(&env, "json_fields/nodes/parse_error", |v| {
        *v == Value::Bool(false)
    })
    .await;
    // setpoint_schedule shows the setpoint at once, and writes nothing at deploy
    wait_for(&env, "setpoint_schedule/nodes/setpoint", |v| {
        v.as_f64().is_some_and(|x| x == 17.0 || x == 21.0)
    })
    .await;
    tokio::time::sleep(Duration::from_millis(500)).await;
    let p3 = env.mock.as_ref().unwrap().ctx().last("p3");
    let written = p3
        .as_ref()
        .and_then(|s| s.v.as_f64())
        .is_some_and(|x| [0.0, 1.0, 17.0, 21.0].contains(&x));
    assert!(
        !written,
        "a deploy wrote p3: before {p3_before:?}, now {p3:?}"
    );
    env.stop().await;
}
