//! Flow metrics in `dataflows/<id>/~val.stats` (ADR 0045, spec 06 0.2.31): counters of
//! samples, drops and commands; reset by a redeploy; published at once on a state change
//! and otherwise at most once per period, and only when they moved.

use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::time::Duration;
use wyrm_client::{SigningTokens, ValEvent, WyrmClient};
use wyrm_core::Value;
use wyrm_flow::{Engine, EngineStart, FlowHost};
use wyrm_link_mock::{Mock, MockConfig};
use wyrm_link_sdk::harness::{isolated_config, TEST_KEY_SEED};
use wyrm_link_sdk::{LinkConfig, LinkHandle};

const SITE: &str = "test";

#[path = "../../wyrm-wasm-host/tests/guests/mod.rs"]
mod guests;

fn map(kv: &[(&str, Value)]) -> Value {
    Value::Map(
        kv.iter()
            .map(|(k, v)| ((*k).to_owned(), v.clone()))
            .collect(),
    )
}

fn arr(items: &[Value]) -> Value {
    Value::Array(items.to_vec())
}

fn edge(a: &str, b: &str) -> Value {
    arr(&[a.into(), b.into()])
}

fn s(x: &str) -> Value {
    Value::from(x)
}

fn temp(name: &str) -> PathBuf {
    let d = std::env::temp_dir().join(format!("wyrm-flow-stats-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&d);
    d
}

struct Env {
    client: WyrmClient,
    mock: Option<LinkHandle<Mock>>,
    engine: Option<LinkHandle<Engine>>,
}

impl Env {
    /// A mock link (it trusts the flow key) and an engine whose counters go out every `every`.
    async fn start(name: &str, every: Duration) -> Self {
        let dir = temp(name);
        let session = zenoh::open(isolated_config()).await.unwrap();
        let key = ed25519_dalek::SigningKey::from_bytes(&TEST_KEY_SEED);
        let host = FlowHost::open(&dir, b"flow-test-hmac-key", SITE).unwrap();
        host.set_stats_every(every);
        let mut lcfg = LinkConfig::new(SITE, "mock");
        lcfg.admin_keys = vec![key.verifying_key(), host.verifying_key()];
        let mock = wyrm_link_sdk::spawn::<Mock>(
            session.clone(),
            lcfg,
            MockConfig {
                points: 1,
                rate_hz: 0.0,
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

    async fn deploy(&self, def: Value) {
        let proofs = wyrm_flow::command_targets(&def, SITE)
            .unwrap_or_default()
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

    /// Every `~val` of flow `id` from now on, with the time it arrived.
    async fn vals(&self, id: &str) -> Vals {
        let seen: Vals = Arc::new(Mutex::new(Vec::new()));
        let mut sub = self
            .client
            .subscribe(&format!("wy/{SITE}/dataflows/{id}"))
            .await
            .unwrap();
        let into = seen.clone();
        tokio::spawn(async move {
            while let Some(ev) = sub.next().await {
                if let ValEvent::Sample { sample, .. } = ev {
                    into.lock()
                        .unwrap()
                        .push((tokio::time::Instant::now(), sample.v));
                }
            }
        });
        seen
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

type Vals = Arc<Mutex<Vec<(tokio::time::Instant, Value)>>>;

fn at<'a>(v: &'a Value, path: &[&str]) -> Option<&'a Value> {
    path.iter().try_fold(v, |v, k| match v {
        Value::Map(m) => m.get(*k),
        _ => None,
    })
}

fn count(v: &Value, path: &[&str]) -> u64 {
    match at(v, path) {
        Some(Value::UInt(n)) => *n,
        other => panic!("{path:?}: {other:?} in {v:?}"),
    }
}

fn version(v: &Value) -> u64 {
    count(v, &["version"])
}

/// The first `~val` (in arrival order) that `ok` accepts, waiting at most 10 s.
async fn first(vals: &Vals, what: &str, ok: impl Fn(&Value) -> bool) -> Value {
    let deadline = tokio::time::Instant::now() + Duration::from_secs(10);
    loop {
        if let Some((_, v)) = vals.lock().unwrap().iter().find(|(_, v)| ok(v)) {
            return v.clone();
        }
        assert!(
            tokio::time::Instant::now() < deadline,
            "timeout: {what}: {:?}",
            vals.lock().unwrap().last()
        );
        tokio::time::sleep(Duration::from_millis(30)).await;
    }
}

/// A clock every 10 ms into a node that spins for its 100 ms wall-time limit on each sample,
/// behind an inbox of one with `drop_oldest`: the inbox must drop.
fn slow(version: u64, artifact: &str) -> Value {
    map(&[
        ("id", s("slow")),
        ("version", Value::UInt(version)),
        (
            "nodes",
            map(&[
                (
                    "clock",
                    map(&[("type", s("timer")), ("period_ms", Value::UInt(10))]),
                ),
                (
                    "spin",
                    map(&[
                        ("type", s("wasm")),
                        ("artifact", s(artifact)),
                        ("fuel", Value::UInt(1_000_000_000)),
                    ]),
                ),
            ]),
        ),
        ("edges", arr(&[edge("clock.out", "spin.in")])),
        (
            "policy",
            map(&[("queue", Value::UInt(1)), ("overflow", s("drop_oldest"))]),
        ),
    ])
}

#[tokio::test(flavor = "multi_thread")]
async fn counters_grow_and_a_redeploy_resets_them() {
    let env = Env::start("drops", Duration::from_millis(200)).await;
    let r = env
        .client
        .invoke_one(
            &format!("wy/{SITE}/dataflows"),
            "put_artifact",
            map(&[("bytes", Value::Bytes(guests::spin()))]),
        )
        .await
        .unwrap();
    let spin = match at(r.as_ref().unwrap(), &["artifact"]) {
        Some(Value::Str(a)) => a.clone(),
        other => panic!("artifact: {other:?}"),
    };
    let vals = env.vals("slow").await;
    env.deploy(slow(1, &spin)).await;

    // the deploy's own `~val` carries the counters at once, and the size of the flow
    let at_deploy = first(&vals, "deploy", |v| version(v) == 1).await;
    assert_eq!(count(&at_deploy, &["stats", "nodes"]), 2);
    assert_eq!(count(&at_deploy, &["stats", "edges"]), 1);

    let busy = first(&vals, "drops", |v| {
        version(v) == 1
            && count(v, &["stats", "dropped"]) >= 5
            && count(v, &["stats", "samples_in"]) >= 2
            && count(v, &["stats", "samples_out"]) >= 5
    })
    .await;
    assert!(
        count(&busy, &["stats", "samples_out"]) > count(&busy, &["stats", "samples_in"]),
        "the clock sends more than the slow node takes in: {busy:?}"
    );
    assert!(at(&busy, &["stats", "last_sample_t"]).is_some(), "{busy:?}");
    assert_eq!(count(&busy, &["state"]), 0, "still running");
    assert_eq!(count(&busy, &["stats", "commands", "sent"]), 0);

    // a redeploy counts from zero: its first `~val` is below what version 1 had reached
    let before = vals
        .lock()
        .unwrap()
        .iter()
        .rev()
        .find(|(_, v)| version(v) == 1)
        .map(|(_, v)| v.clone())
        .unwrap();
    env.deploy(slow(2, &spin)).await;
    let fresh = first(&vals, "redeploy", |v| version(v) == 2).await;
    for c in ["samples_in", "samples_out", "dropped"] {
        assert!(
            count(&fresh, &["stats", c]) < count(&before, &["stats", c]),
            "{c} reset: {before:?} → {fresh:?}"
        );
    }
    env.stop().await;
}

fn commands(version: u64) -> Value {
    let every = |action: &str| {
        map(&[
            ("type", s("invoke")),
            ("path", s("downstream/mock")),
            ("action", s(action)),
            ("interval_ms", Value::UInt(100)),
        ])
    };
    map(&[
        ("id", s("cmds")),
        ("version", Value::UInt(version)),
        (
            "nodes",
            map(&[("good", every("reset")), ("bad", every("no_such_action"))]),
        ),
        ("edges", arr(&[])),
        ("permissions", map(&[("maxperm", s("write"))])),
    ])
}

#[tokio::test(flavor = "multi_thread")]
async fn command_answers_count_as_ok_and_error() {
    let env = Env::start("commands", Duration::from_millis(200)).await;
    let vals = env.vals("cmds").await;
    env.deploy(commands(1)).await;
    let v = first(&vals, "answers", |v| {
        count(v, &["stats", "commands", "ok"]) >= 2
            && count(v, &["stats", "commands", "error"]) >= 2
    })
    .await;
    let sent = count(&v, &["stats", "commands", "sent"]);
    assert!(sent >= 4, "{v:?}");
    assert!(
        count(&v, &["stats", "commands", "ok"]) + count(&v, &["stats", "commands", "error"])
            <= sent,
        "an answer follows its run: {v:?}"
    );
    // a command's answer is no sample: nothing came in through an edge or a source
    assert_eq!(count(&v, &["stats", "samples_in"]), 0, "{v:?}");
    assert_eq!(count(&v, &["stats", "dropped"]), 0, "{v:?}");
    env.stop().await;
}

fn ticking(id: &str, period_ms: u64) -> Value {
    map(&[
        ("id", s(id)),
        ("version", Value::UInt(1)),
        (
            "nodes",
            map(&[
                (
                    "clock",
                    map(&[("type", s("timer")), ("period_ms", Value::UInt(period_ms))]),
                ),
                ("out", map(&[("type", s("publish")), ("node", s("n"))])),
            ]),
        ),
        ("edges", arr(&[edge("clock.out", "out.in")])),
    ])
}

fn idle() -> Value {
    map(&[
        ("id", s("idle")),
        ("version", Value::UInt(1)),
        (
            "nodes",
            map(&[
                ("c", map(&[("type", s("const")), ("value", Value::UInt(1))])),
                ("out", map(&[("type", s("publish")), ("node", s("c"))])),
            ]),
        ),
        ("edges", arr(&[edge("c.out", "out.in")])),
    ])
}

#[tokio::test(flavor = "multi_thread")]
async fn counters_are_published_at_a_bounded_rate_and_only_when_they_moved() {
    let every = Duration::from_millis(300);
    let env = Env::start("rate", every).await;
    let busy = env.vals("busy").await;
    let quiet = env.vals("idle").await;
    env.deploy(ticking("busy", 10)).await;
    env.deploy(idle()).await;
    tokio::time::sleep(Duration::from_millis(2000)).await;

    // a clock of 100 samples/s: one `~val` at deploy, then at most one per period
    let seen = busy.lock().unwrap().clone();
    assert!(seen.len() >= 3, "counters were published: {}", seen.len());
    assert!(
        seen.len() <= 2000 / 300 + 2,
        "rate bounded: {} `~val`s in 2 s",
        seen.len()
    );
    for w in seen.windows(2).skip(1) {
        assert!(
            w[1].0 - w[0].0 >= every.mul_f64(0.6),
            "at most one per period: {:?}",
            w[1].0 - w[0].0
        );
    }
    let ins: Vec<u64> = seen
        .iter()
        .map(|(_, v)| count(v, &["stats", "samples_in"]))
        .collect();
    assert!(
        ins.windows(2).all(|w| w[1] > w[0]),
        "each one moved: {ins:?}"
    );

    // a flow that sent once at start: its counters settle and then nothing more goes out
    let n = quiet.lock().unwrap().len();
    assert!((1..=2).contains(&n), "idle flow: {n} `~val`s");
    tokio::time::sleep(Duration::from_millis(1000)).await;
    assert_eq!(
        quiet.lock().unwrap().len(),
        n,
        "nothing moved, nothing sent"
    );

    // a state change goes out at once, not at the next period
    let before = busy.lock().unwrap().len();
    env.client
        .invoke_one(
            &format!("wy/{SITE}/dataflows/busy"),
            "stop",
            Value::Map(Default::default()),
        )
        .await
        .unwrap();
    let stopped = first(&busy, "stopped", |v| count(v, &["state"]) == 1).await;
    assert!(
        count(&stopped, &["stats", "samples_in"]) > 0,
        "a stop keeps the totals"
    );
    // a stopped flow's counters stand still: no more `~val` after the stop's own
    tokio::time::sleep(Duration::from_millis(1000)).await;
    let after = busy.lock().unwrap().len();
    assert!(after - before <= 2, "{before} → {after}");
    env.stop().await;
}
