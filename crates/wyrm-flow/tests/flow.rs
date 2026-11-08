//! Flow engine end to end on an in-memory session: a mock link as the
//! data source and command target, the engine on `wy/test/dataflows`.

use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;
use wyrm_client::{SigningTokens, ValEvent, WyrmClient};
use wyrm_core::{Sample, Value};
use wyrm_flow::{def, Engine, EngineStart, FlowHost};
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
    let d = std::env::temp_dir().join(format!("wyrm-flow-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&d);
    d
}

/// Peak shaving (wiki example): two meters → sum → alarm → shed command.
fn peak(version: u64, expr: &str) -> Value {
    map(&[
        ("id", s("peak")),
        ("version", Value::UInt(version)),
        (
            "nodes",
            map(&[
                (
                    "a",
                    map(&[("type", s("subscribe")), ("key", s("downstream/mock/p0"))]),
                ),
                (
                    "b",
                    map(&[("type", s("subscribe")), ("key", s("downstream/mock/p1"))]),
                ),
                (
                    "sum",
                    map(&[
                        ("type", s("expression")),
                        ("inputs", arr(&[s("a"), s("b")])),
                        ("expr", s(expr)),
                    ]),
                ),
                (
                    "count",
                    map(&[
                        ("type", s("expression")),
                        ("inputs", arr(&[s("a")])),
                        ("expr", s("state.n = (state.n ?? 0) + 1; state.n")),
                    ]),
                ),
                (
                    "alarm",
                    map(&[("type", s("alarm")), ("high", Value::Float(30.0))]),
                ),
                (
                    "total",
                    map(&[
                        ("type", s("publish")),
                        ("node", s("total")),
                        ("meta", map(&[("type", s("number")), ("unit", s("kW"))])),
                    ]),
                ),
                ("n", map(&[("type", s("publish")), ("node", s("n"))])),
                (
                    "shed",
                    map(&[
                        ("type", s("invoke")),
                        ("path", s("downstream/mock")),
                        ("action", s("reset")),
                        ("on", s("rising")),
                    ]),
                ),
                (
                    "shed_result",
                    map(&[("type", s("publish")), ("node", s("shed"))]),
                ),
                ("al", map(&[("type", s("publish")), ("node", s("al"))])),
            ]),
        ),
        (
            "edges",
            arr(&[
                edge("a.out", "sum.in.a"),
                edge("b.out", "sum.in.b"),
                edge("a.out", "count.in.a"),
                edge("count.out", "n.in"),
                edge("sum.out", "alarm.in"),
                edge("sum.out", "total.in"),
                edge("alarm.out", "shed.in"),
                edge("shed.out", "shed_result.in"),
                edge("alarm.out", "al.in"),
            ]),
        ),
        ("policy", map(&[("state_flush_s", Value::UInt(1))])),
        ("permissions", map(&[("maxperm", s("write"))])),
    ])
}

struct Env {
    session: zenoh::Session,
    client: WyrmClient,
    mock: Option<LinkHandle<Mock>>,
    engine: Option<LinkHandle<Engine>>,
    dir: PathBuf,
}

async fn engine_on(session: &zenoh::Session, dir: &std::path::Path) -> LinkHandle<Engine> {
    let host = FlowHost::open(dir, b"flow-test-hmac-key", SITE).unwrap();
    let key = ed25519_dalek::SigningKey::from_bytes(&TEST_KEY_SEED);
    let mut lcfg = LinkConfig::new(SITE, "dataflows");
    lcfg.root = Some(format!("wy/{SITE}/dataflows"));
    lcfg.admin_keys = vec![key.verifying_key()];
    wyrm_link_sdk::spawn::<Engine>(
        session.clone(),
        lcfg,
        EngineStart {
            host,
            admin_keys: vec![key.verifying_key()],
            proof_keys: Vec::new(),
        },
    )
    .await
    .unwrap()
}

impl Env {
    async fn start(name: &str) -> Self {
        let dir = temp(name);
        let session = zenoh::open(isolated_config()).await.unwrap();
        let key = ed25519_dalek::SigningKey::from_bytes(&TEST_KEY_SEED);
        // links trust the operator key and the engine's own key
        let flow_key = FlowHost::open(&dir, b"flow-test-hmac-key", SITE)
            .unwrap()
            .verifying_key();
        let mut lcfg = LinkConfig::new(SITE, "mock");
        lcfg.admin_keys = vec![key.verifying_key(), flow_key];
        let mock = wyrm_link_sdk::spawn::<Mock>(
            session.clone(),
            lcfg,
            MockConfig {
                points: 2,
                rate_hz: 20.0,
                depth: 0,
                fanout: 1,
                writable: true,
            },
        )
        .await
        .unwrap();
        let engine = engine_on(&session, &dir).await;
        let client = WyrmClient::new(session.clone())
            .with_tokens(Arc::new(SigningTokens::new(key, SITE)))
            .with_timeout(Duration::from_secs(3));
        Self {
            session,
            client,
            mock: Some(mock),
            engine: Some(engine),
            dir,
        }
    }

    async fn deploy(&self, def: Value) -> Result<(), wyrm_client::ClientError> {
        self.client
            .invoke_one(
                &format!("wy/{SITE}/dataflows"),
                "deploy",
                deploy_args(&self.client, def),
            )
            .await
            .map(|_| ())
    }

    fn last(&self, path: &str) -> Option<Sample> {
        self.engine.as_ref().unwrap().ctx().last(path)
    }

    async fn restart_engine(&mut self) {
        self.engine.take().unwrap().stop().await;
        self.engine = Some(engine_on(&self.session, &self.dir).await);
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

/// `{def, proofs}`: one token from the deployer per command target.
fn deploy_args(c: &WyrmClient, def: Value) -> Value {
    let proofs = wyrm_flow::command_targets(&def, SITE)
        .unwrap_or_default()
        .into_iter()
        .filter_map(|t| c.proof(&t).map(|p| (t, Value::Bytes(p))))
        .collect();
    map(&[("def", def), ("proofs", Value::Map(proofs))])
}

async fn wait<T>(what: &str, mut f: impl FnMut() -> Option<T>) -> T {
    let deadline = tokio::time::Instant::now() + Duration::from_secs(5);
    loop {
        if let Some(v) = f() {
            return v;
        }
        assert!(tokio::time::Instant::now() < deadline, "timeout: {what}");
        tokio::time::sleep(Duration::from_millis(30)).await;
    }
}

fn num(s: &Sample) -> f64 {
    s.v.as_f64().unwrap_or(f64::NAN)
}

#[test]
fn compiler_checks() {
    assert!(def::compile(&peak(1, "a.v + b.v")).is_ok());
    let e = def::compile(&peak(1, "a.v + c.v")).unwrap_err();
    assert!(e.0.starts_with("nodes.sum.expr:"), "{e}");
    // maxperm below what invoke needs
    let mut d = peak(1, "a.v + b.v");
    if let Value::Map(m) = &mut d {
        m.insert("permissions".into(), map(&[("maxperm", s("read"))]));
    }
    let e = def::compile(&d).unwrap_err();
    assert!(e.0.starts_with("permissions.maxperm"), "{e}");
    // flows never get config (spec 06 step 7)
    if let Value::Map(m) = &mut d {
        m.insert("permissions".into(), map(&[("maxperm", s("config"))]));
    }
    let e = def::compile(&d).unwrap_err();
    assert!(e.0.contains("at most write"), "{e}");
    // cycle without delay, then through delay
    let cyc = |via_delay: bool| {
        map(&[
            ("id", s("c")),
            (
                "nodes",
                map(&[
                    ("x", map(&[("type", s("scale"))])),
                    (
                        "y",
                        if via_delay {
                            map(&[("type", s("delay")), ("ms", Value::UInt(10))])
                        } else {
                            map(&[("type", s("scale"))])
                        },
                    ),
                ]),
            ),
            (
                "edges",
                arr(&[edge("x.out", "y.in"), edge("y.out", "x.in")]),
            ),
        ])
    };
    assert!(def::compile(&cyc(false)).unwrap_err().0.contains("cycle"));
    assert!(def::compile(&cyc(true)).is_ok());
    // bad port and unknown type
    let bad = map(&[
        ("id", s("p")),
        ("nodes", map(&[("x", map(&[("type", s("scale"))]))])),
        ("edges", arr(&[edge("x.nope", "x.in")])),
    ]);
    assert!(def::compile(&bad).unwrap_err().0.contains("no output nope"));
    let unk = map(&[
        ("id", s("u")),
        ("nodes", map(&[("x", map(&[("type", s("teleport"))]))])),
    ]);
    assert!(def::compile(&unk)
        .unwrap_err()
        .0
        .contains("unknown node type"));
    // an editor's layout (spec 06 0.2.5): checked, and not part of a node
    let with = |xy: Value| {
        let mut d = peak(1, "a.v + b.v");
        if let Value::Map(m) = &mut d {
            m.insert("layout".into(), map(&[("sum", xy)]));
        }
        d
    };
    let a = def::compile(&with(arr(&[Value::UInt(10), Value::Float(20.5)]))).unwrap();
    let b = def::compile(&with(arr(&[Value::UInt(300), Value::UInt(40)]))).unwrap();
    assert_eq!(
        a.0.nodes["sum"].hash, b.0.nodes["sum"].hash,
        "moving keeps the state"
    );
    let e = def::compile(&with(s("left"))).unwrap_err();
    assert!(e.0.starts_with("layout.sum"), "{e}");
    // at most MAX_NODES nodes (step 8): each is a task and an inbox
    let many = |n: usize| {
        let nodes = (0..n)
            .map(|i| (format!("n{i}"), map(&[("type", s("not"))])))
            .collect();
        map(&[("id", s("many")), ("nodes", Value::Map(nodes))])
    };
    assert!(def::compile(&many(def::MAX_NODES)).is_ok());
    let e = def::compile(&many(def::MAX_NODES + 1)).unwrap_err();
    assert!(e.0.starts_with("nodes: 1001 nodes > 1000"), "{e}");
}

#[tokio::test(flavor = "multi_thread")]
async fn peak_shaving_hot_swap_and_restart() {
    let mut env = Env::start("peak").await;
    // fixed meter values (the mock holds written values): sum 35 > alarm 30
    env.client
        .set(&format!("wy/{SITE}/downstream/mock/p0"), 20.0)
        .await
        .unwrap();
    env.client
        .set(&format!("wy/{SITE}/downstream/mock/p1"), 15.0)
        .await
        .unwrap();
    env.deploy(peak(1, "a.v + b.v")).await.unwrap();

    // total = p0 + p1 (≈ 20..60), published as a flow node
    let total = wait("total", || env.last("peak/nodes/total")).await;
    assert!(num(&total) > 0.0);
    // alarm (high 30) fires on the rising edge → `reset` on the mock → result published
    let mut vals = env
        .client
        .subscribe(&format!("wy/{SITE}/dataflows/peak/nodes/shed"))
        .await
        .unwrap();
    let _ = tokio::time::timeout(Duration::from_secs(5), async {
        loop {
            if let Some(ValEvent::Sample { .. }) = vals.next().await {
                break;
            }
        }
    })
    .await;
    // the invoke result appears once the alarm has risen; with p0+p1 ≈ 40 it does
    wait("shed invoked", || env.last("peak/nodes/shed")).await;

    // hot swap: a new expression without restart; `count` keeps its state
    let before = wait("count", || {
        env.last("peak/nodes/n").filter(|s| num(s) >= 3.0)
    })
    .await;
    env.deploy(peak(2, "a.v + b.v + 1000")).await.unwrap();
    wait("new expression", || {
        env.last("peak/nodes/total").filter(|s| num(s) > 1000.0)
    })
    .await;
    let after = wait("count continues", || env.last("peak/nodes/n")).await;
    assert!(
        num(&after) >= num(&before),
        "unchanged node kept its state ({} → {})",
        num(&before),
        num(&after)
    );

    // a broken draft keeps the running version
    let err = env.deploy(peak(3, "a.v + nope.v")).await.unwrap_err();
    assert!(err.message.contains("nodes.sum.expr"), "{err}");
    tokio::time::sleep(Duration::from_millis(200)).await;
    let t0 = env.last("peak/nodes/total").unwrap().t;
    wait("still running", || {
        env.last("peak/nodes/total").filter(|s| s.t > t0)
    })
    .await;

    // node state survives an engine restart
    let n_before = num(&env.last("peak/nodes/n").unwrap());
    env.restart_engine().await;
    let n_after = wait("count after restart", || env.last("peak/nodes/n")).await;
    assert!(
        num(&n_after) > n_before,
        "state restored: {n_before} → {}",
        num(&n_after)
    );

    // stop / start / remove
    let flow = format!("wy/{SITE}/dataflows/peak");
    env.client
        .invoke_one(&flow, "stop", Value::Map(Default::default()))
        .await
        .unwrap();
    tokio::time::sleep(Duration::from_millis(200)).await;
    let t1 = env.last("peak/nodes/total").map(|s| s.t).unwrap_or(0);
    tokio::time::sleep(Duration::from_millis(300)).await;
    assert_eq!(
        env.last("peak/nodes/total").map(|s| s.t).unwrap_or(0),
        t1,
        "stopped"
    );
    env.client
        .invoke_one(&flow, "start", Value::Map(Default::default()))
        .await
        .unwrap();
    wait("running again", || {
        env.last("peak/nodes/total").filter(|s| s.t > t1)
    })
    .await;
    env.client
        .invoke_one(&flow, "remove", Value::Map(Default::default()))
        .await
        .unwrap();
    assert!(env.client.meta(&flow).await.is_err());
    env.stop().await;
}

/// Deploying needs `config`; a flow never gets more than its deployer.
#[tokio::test(flavor = "multi_thread")]
async fn deploy_needs_config() {
    let env = Env::start("deployer").await;
    let key = ed25519_dalek::SigningKey::from_bytes(&TEST_KEY_SEED);
    let writer = SigningTokens::new(key, SITE).max(wyrm_core::Perm::Write);
    let c = WyrmClient::new(env.session.clone())
        .with_tokens(Arc::new(writer))
        .with_timeout(Duration::from_secs(3));
    let e = c
        .invoke_one(
            &format!("wy/{SITE}/dataflows"),
            "deploy",
            deploy_args(&c, peak(1, "a.v + b.v")),
        )
        .await
        .unwrap_err();
    assert!(e.is(wyrm_core::Status::PermissionDenied), "{e}");
    env.stop().await;
}

/// `config` on `dataflows/**` alone does not let a flow command devices: the
/// deployer proves its own rights on every target.
#[tokio::test(flavor = "multi_thread")]
async fn deploy_needs_proofs_for_targets() {
    let env = Env::start("proofs").await;
    let flows = format!("wy/{SITE}/dataflows");
    // no proofs
    let e = env
        .client
        .invoke_one(&flows, "deploy", map(&[("def", peak(1, "a.v + b.v"))]))
        .await
        .unwrap_err();
    assert!(e.is(wyrm_core::Status::PermissionDenied), "{e}");
    // a deployer whose grants cover only dataflows/** cannot mint proofs
    let key = ed25519_dalek::SigningKey::from_bytes(&TEST_KEY_SEED);
    let flows_only = SigningTokens::new(key, SITE).grants(vec![wyrm_core::ptok::Grant {
        k: format!("{flows}/**"),
        p: wyrm_core::Perm::Config,
    }]);
    let c = WyrmClient::new(env.session.clone())
        .with_tokens(Arc::new(flows_only))
        .with_timeout(Duration::from_secs(3));
    let e = c
        .invoke_one(&flows, "deploy", deploy_args(&c, peak(1, "a.v + b.v")))
        .await
        .unwrap_err();
    assert!(e.is(wyrm_core::Status::PermissionDenied), "{e}");
    // targets outside wy/<site>/downstream/ or with wildcards are refused
    for path in ["sys/links/mock", "downstream/*"] {
        let mut d = peak(1, "a.v + b.v");
        if let Value::Map(m) = &mut d {
            if let Some(Value::Map(nodes)) = m.get_mut("nodes") {
                if let Some(Value::Map(shed)) = nodes.get_mut("shed") {
                    shed.insert("path".into(), s(path));
                }
            }
        }
        let e = env.deploy(d).await.unwrap_err();
        assert!(e.is(wyrm_core::Status::InvalidParameter), "{path}: {e}");
    }
    // review FLOW-1: the deployer must be able to read every source (its token's `auth`)
    let key = ed25519_dalek::SigningKey::from_bytes(&TEST_KEY_SEED);
    let blind = SigningTokens::new(key, SITE).grants(vec![
        wyrm_core::ptok::Grant {
            k: format!("wy/{SITE}/downstream/mock/p0"),
            p: wyrm_core::Perm::None,
        },
        wyrm_core::ptok::Grant {
            k: format!("wy/{SITE}/**"),
            p: wyrm_core::Perm::Config,
        },
    ]);
    let c = WyrmClient::new(env.session.clone())
        .with_tokens(Arc::new(blind))
        .with_timeout(Duration::from_secs(3));
    let e = c
        .invoke_one(&flows, "deploy", deploy_args(&c, peak(1, "a.v + b.v")))
        .await
        .unwrap_err();
    // (the same flow deploys below with the p0 grant gone; the denial carries no detail)
    assert!(e.is(wyrm_core::Status::PermissionDenied), "{e}");
    // review FLOW-1: sources read this site's downstream, dataflows or storage only
    for key in [
        "sys/audit/mock".to_owned(),
        "pub/x".to_owned(),
        "upstream/central".to_owned(),
        "wy/other/downstream/mock/p0".to_owned(),
        format!("wy/{SITE}/sys/status"),
        format!("wy/{SITE}/downstreamx/p"),
        "wy/*/downstream/mock/p0".to_owned(),
    ] {
        let mut d = peak(1, "a.v + b.v");
        if let Value::Map(m) = &mut d {
            if let Some(Value::Map(nodes)) = m.get_mut("nodes") {
                if let Some(Value::Map(a)) = nodes.get_mut("a") {
                    a.insert("key".into(), s(&key));
                }
            }
        }
        let e = env.deploy(d).await.unwrap_err();
        assert!(e.is(wyrm_core::Status::InvalidParameter), "{key}: {e}");
        assert!(e.to_string().contains("a source reads"), "{key}: {e}");
    }
    assert!(env.deploy(peak(1, "a.v + b.v")).await.is_ok());
    env.stop().await;
}

/// `const 5 → wasm(artifact) → publish w` (+ an optional spinning wasm node).
fn wasm_flow(version: u64, artifact: &str, spin: Option<&str>) -> Value {
    let mut nodes = vec![
        ("c", map(&[("type", s("const")), ("value", Value::UInt(5))])),
        (
            "x",
            map(&[
                ("type", s("wasm")),
                ("artifact", s(artifact)),
                ("config", map(&[("k", Value::UInt(1))])),
            ]),
        ),
        ("w", map(&[("type", s("publish")), ("node", s("w"))])),
    ];
    let mut edges = vec![edge("c.out", "x.in"), edge("x.out", "w.in")];
    if let Some(a) = spin {
        nodes.push((
            "spin",
            map(&[
                ("type", s("wasm")),
                ("artifact", s(a)),
                ("fuel", Value::UInt(100_000)),
            ]),
        ));
        edges.push(edge("c.out", "spin.in"));
    }
    map(&[
        ("id", s("wf")),
        ("version", Value::UInt(version)),
        ("nodes", map(&nodes)),
        ("edges", arr(&edges)),
    ])
}

async fn put_artifact(env: &Env, bytes: Vec<u8>) -> Result<String, wyrm_client::ClientError> {
    let r = env
        .client
        .invoke_one(
            &format!("wy/{SITE}/dataflows"),
            "put_artifact",
            map(&[("bytes", Value::Bytes(bytes))]),
        )
        .await?;
    match r {
        Some(Value::Map(m)) => match m.get("artifact") {
            Some(Value::Str(a)) => Ok(a.clone()),
            other => panic!("artifact: {other:?}"),
        },
        other => panic!("put_artifact: {other:?}"),
    }
}

/// Iteration 8 criterion: a `.wasm` node is loaded and replaced without a
/// restart; a fuel trap in one node does not stop the flow.
#[tokio::test(flavor = "multi_thread")]
async fn wasm_node_hot_load() {
    let mut env = Env::start("wasm").await;
    let a = put_artifact(&env, guests::add(1)).await.unwrap();
    assert_eq!(a, wyrm_wasm_host::sha256_hex(&guests::add(1)));
    let spin = put_artifact(&env, guests::spin()).await.unwrap();
    // flow `~val` states (no storage here: watch the publications)
    let states = Arc::new(std::sync::Mutex::new(Vec::new()));
    let mut sub = env
        .client
        .subscribe(&format!("wy/{SITE}/dataflows/wf"))
        .await
        .unwrap();
    let st2 = states.clone();
    tokio::spawn(async move {
        while let Some(ev) = sub.next().await {
            if let ValEvent::Sample { sample, .. } = ev {
                if let Value::Map(m) = sample.v {
                    st2.lock().unwrap().push(m.get("state").cloned());
                }
            }
        }
    });
    env.deploy(wasm_flow(1, &a, Some(&spin))).await.unwrap();
    let v = wait("wasm output", || env.last("wf/nodes/w")).await;
    assert_eq!(v.v, Value::UInt(6));
    // the spinning node ran out of fuel; the flow never left `running`
    tokio::time::sleep(Duration::from_millis(300)).await;
    let seen = states.lock().unwrap().clone();
    assert!(!seen.is_empty());
    assert!(seen.iter().all(|s| *s == Some(Value::UInt(0))), "{seen:?}");

    // hot load: a new artifact and a new definition, same engine
    let b = put_artifact(&env, guests::add(10)).await.unwrap();
    env.deploy(wasm_flow(2, &b, None)).await.unwrap();
    wait("new code", || {
        env.last("wf/nodes/w").filter(|s| s.v == Value::UInt(15))
    })
    .await;

    // unknown artifact, sandbox violation, wrong world: refused, v2 keeps running
    let missing = "0".repeat(64);
    let e = env.deploy(wasm_flow(3, &missing, None)).await.unwrap_err();
    assert!(e.message.contains("nodes.x.artifact: no artifact"), "{e}");
    let e = put_artifact(&env, guests::importing("wasi:filesystem/types@0.2.0"))
        .await
        .unwrap_err();
    assert!(e.message.contains("wasi:filesystem/types@0.2.0"), "{e}");
    assert!(put_artifact(&env, guests::register()).await.is_err());
    assert!(put_artifact(&env, b"not wasm".to_vec()).await.is_err());

    // artifacts and the flow survive an engine restart
    env.restart_engine().await;
    wait("after restart", || {
        env.last("wf/nodes/w").filter(|s| s.v == Value::UInt(15))
    })
    .await;
    env.stop().await;
}

#[test]
fn wasm_config_checks() {
    let ok = |cfg: Value| def::compile(&cfg).map(|_| ()).map_err(|e| e.0);
    let a = "ab".repeat(32);
    assert!(ok(wasm_flow(1, &a, None)).is_ok());
    let e = ok(wasm_flow(1, "sha256:abc", None)).unwrap_err();
    assert!(e.contains("nodes.x: artifact"), "{e}");
    let mut d = wasm_flow(1, &a, None);
    if let Value::Map(m) = &mut d {
        if let Some(Value::Map(nodes)) = m.get_mut("nodes") {
            if let Some(Value::Map(x)) = nodes.get_mut("x") {
                x.insert("memory_mb".into(), Value::UInt(4096));
            }
        }
    }
    assert!(ok(d).unwrap_err().contains("memory_mb"));
}

/// T11: replaced definitions are kept; `rollback` redeploys one as a new
/// version with the same checks as `deploy` (proofs required).
#[tokio::test(flavor = "multi_thread")]
async fn history_and_rollback() {
    let env = Env::start("history").await;
    // The flow's `~val` names its deployer (ADR 0008: flows outlive their
    // deployer's rights, so operators need to find them).
    let by = Arc::new(std::sync::Mutex::new(None));
    let mut sub = env
        .client
        .subscribe(&format!("wy/{SITE}/dataflows/peak"))
        .await
        .unwrap();
    let by2 = by.clone();
    tokio::spawn(async move {
        while let Some(ev) = sub.next().await {
            if let ValEvent::Sample { sample, .. } = ev {
                if let Value::Map(m) = sample.v {
                    *by2.lock().unwrap() = m.get("deployed_by").cloned();
                }
            }
        }
    });
    env.deploy(peak(1, "a.v + b.v")).await.unwrap();
    env.deploy(peak(2, "a.v - b.v")).await.unwrap();
    let flow = format!("wy/{SITE}/dataflows/peak");
    let h = env
        .client
        .invoke_one(&flow, "history", map(&[]))
        .await
        .unwrap();
    let Some(Value::Array(defs)) = h else {
        panic!("history is an array: {h:?}")
    };
    assert_eq!(defs.len(), 2, "v1 and the current v2");
    wait("deployed_by", || by.lock().unwrap().clone()).await;
    assert_eq!(*by.lock().unwrap(), Some(s("svc:wyr")));
    // rollback without proofs is refused (the flow has an invoke sink)
    let e = env
        .client
        .invoke_one(&flow, "rollback", map(&[("version", Value::UInt(1))]))
        .await
        .unwrap_err();
    assert!(e.is(wyrm_core::Status::PermissionDenied), "{e}");
    // with proofs: v1's definition comes back as version 3
    let Value::Map(mut args) = deploy_args(&env.client, peak(1, "a.v + b.v")) else {
        panic!()
    };
    args.remove("def");
    args.insert("version".into(), Value::UInt(1));
    env.client
        .invoke_one(&flow, "rollback", Value::Map(args))
        .await
        .unwrap();
    let h = env
        .client
        .invoke_one(&flow, "history", map(&[]))
        .await
        .unwrap();
    let Some(Value::Array(defs)) = h else {
        panic!()
    };
    let last = defs.last().unwrap();
    let Value::Map(m) = last else { panic!() };
    assert_eq!(m["version"], Value::UInt(3));
    let Value::Map(nodes) = &m["nodes"] else {
        panic!()
    };
    let Value::Map(sum) = &nodes["sum"] else {
        panic!()
    };
    assert_eq!(sum["expr"], s("a.v + b.v"));
    // unknown version
    let e = env
        .client
        .invoke_one(&flow, "rollback", map(&[("version", Value::UInt(42))]))
        .await
        .unwrap_err();
    assert!(e.is(wyrm_core::Status::NotFound), "{e}");
    env.stop().await;
}

/// ADR 0032: logic blocks run in a deployed flow: a variable at start, an operator on its
/// inputs, a value published.
#[tokio::test(flavor = "multi_thread")]
async fn logic_blocks_in_a_deployed_flow() {
    let env = Env::start("blocks").await;
    let def = map(&[
        ("id", s("calc")),
        ("version", Value::UInt(1)),
        (
            "nodes",
            map(&[
                (
                    "a",
                    map(&[("type", s("number")), ("value", Value::UInt(40))]),
                ),
                ("b", map(&[("type", s("number")), ("value", s("2"))])),
                ("sum", map(&[("type", s("add"))])),
                (
                    "label",
                    map(&[
                        ("type", s("if")),
                        ("op", s(">")),
                        ("then", s("big")),
                        ("else", s("small")),
                    ]),
                ),
                ("show", map(&[("type", s("publish")), ("node", s("total"))])),
                ("word", map(&[("type", s("publish")), ("node", s("label"))])),
            ]),
        ),
        (
            "edges",
            arr(&[
                edge("a.out", "sum.in.0"),
                edge("b.out", "sum.in.1"),
                edge("sum.out", "show.in"),
                edge("sum.out", "label.in.0"),
                edge("a.out", "label.in.1"),
                edge("label.out", "word.in"),
            ]),
        ),
    ]);
    env.deploy(def).await.unwrap();
    let total = wait("total", || {
        env.last("calc/nodes/total")
            .filter(|s| s.v.as_f64() == Some(42.0))
    })
    .await;
    assert_eq!(total.q, wyrm_core::Quality::Good);
    wait("label", || {
        env.last("calc/nodes/label")
            .filter(|s| s.v == Value::from("big"))
    })
    .await;
    env.stop().await;
}

fn at<'a>(v: &'a Value, path: &[&str]) -> Option<&'a Value> {
    path.iter().try_fold(v, |v, k| match v {
        Value::Map(m) => m.get(*k),
        _ => None,
    })
}

fn keys(v: Option<&Value>) -> Vec<String> {
    match v {
        Some(Value::Map(m)) => m.keys().cloned().collect(),
        _ => Vec::new(),
    }
}

/// A source, a round block whose parameter and input feed other blocks (ADR 0038 §1).
fn watched(version: u64) -> Value {
    map(&[
        ("id", s("w")),
        ("version", Value::UInt(version)),
        (
            "nodes",
            map(&[
                (
                    "a",
                    map(&[("type", s("subscribe")), ("key", s("downstream/mock/p0"))]),
                ),
                (
                    "r",
                    map(&[("type", s("round")), ("precision", Value::UInt(1))]),
                ),
                ("x", map(&[("type", s("number"))])),
                ("out", map(&[("type", s("publish")), ("node", s("out"))])),
                ("prec", map(&[("type", s("publish")), ("node", s("prec"))])),
                ("rin", map(&[("type", s("publish")), ("node", s("rin"))])),
            ]),
        ),
        (
            "edges",
            arr(&[
                edge("a.out", "r.in"),
                edge("r.out", "out.in"),
                // a parameter's echo and an input's echo
                edge("r.precision", "x.in"),
                edge("x.out", "prec.in"),
                edge("r.in", "rin.in"),
            ]),
        ),
    ])
}

#[tokio::test(flavor = "multi_thread")]
async fn echo_outputs_feed_other_blocks() {
    let env = Env::start("echo").await;
    env.deploy(watched(1)).await.unwrap();
    // the parameter's effective value, sent once at start
    wait("precision echo", || {
        env.last("w/nodes/prec")
            .filter(|s| s.v.as_f64() == Some(1.0))
    })
    .await;
    // the input's samples, as the block got them; the block rounds them
    let rin = wait("input echo", || env.last("w/nodes/rin")).await;
    let out = wait("rounded", || env.last("w/nodes/out")).await;
    assert!(rin.v.as_f64().is_some() && out.v.as_f64().is_some());
    env.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn watch_streams_live_values() {
    let env = Env::start("watch").await;
    env.deploy(watched(1)).await.unwrap();
    let flow = format!("wy/{SITE}/dataflows/w");
    let mut st = env
        .client
        .invoke(&flow, "watch", map(&[("max_hz", Value::UInt(4))]))
        .await
        .unwrap();
    let first = st.next().await.unwrap().unwrap().unwrap();
    assert_eq!(at(&first, &["snapshot"]), Some(&Value::Bool(true)));
    assert!(matches!(at(&first, &["t"]), Some(Value::UInt(_))));
    assert_eq!(
        at(&first, &["nodes", "r", "params", "precision"]),
        Some(&Value::UInt(1))
    );
    assert_eq!(
        keys(at(&first, &["nodes"])),
        ["a", "out", "prec", "r", "rin", "x"]
    );
    // changes: the samples the round block takes and sends, at most 4 rows a second
    let t0 = tokio::time::Instant::now();
    let mut rows = 0;
    let mut seen_in = false;
    while t0.elapsed() < Duration::from_millis(1600) {
        let row = st.next().await.unwrap().unwrap().unwrap();
        assert_eq!(at(&row, &["snapshot"]), Some(&Value::Bool(false)));
        if let Some(Value::Array(pair)) = at(&row, &["nodes", "r", "in", "in"]) {
            assert!(pair[0].as_f64().is_some());
            assert_eq!(pair[1], Value::UInt(0), "quality good");
            seen_in = true;
        }
        // the wired echo goes out, the unwired ones are never built
        for k in keys(at(&row, &["nodes", "r", "out"])) {
            assert!(["out", "in"].contains(&k.as_str()), "r.{k}");
        }
        if at(&row, &["nodes", "a"]).is_some() {
            assert_eq!(keys(at(&row, &["nodes", "a", "out"])), ["out"]);
        }
        rows += 1;
    }
    assert!(seen_in, "a change row with r.in");
    assert!((2..=8).contains(&rows), "{rows} rows in 1.6 s at 4 Hz");
    // `ports`: row 1, here while the watch records
    let snap = env
        .client
        .invoke_one(&flow, "ports", map(&[("nodes", arr(&[s("r")]))]))
        .await
        .unwrap()
        .unwrap();
    assert_eq!(keys(at(&snap, &["nodes"])), ["r"]);
    assert!(at(&snap, &["nodes", "r", "out", "out"]).is_some());
    // a redeploy ends the watch with its version
    env.deploy(watched(2)).await.unwrap();
    let last = loop {
        let row = st.next().await.unwrap().unwrap().unwrap();
        if at(&row, &["redeployed"]).is_some() {
            break row;
        }
    };
    assert_eq!(at(&last, &["redeployed"]), Some(&Value::UInt(2)));
    assert!(st.next().await.is_none(), "the stream ended");
    env.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn watch_needs_the_rights_on_the_sources() {
    use wyrm_core::ptok::Grant;
    use wyrm_core::Perm;
    let env = Env::start("watch-rights").await;
    env.deploy(watched(1)).await.unwrap();
    let flow = format!("wy/{SITE}/dataflows/w");
    let key = ed25519_dalek::SigningKey::from_bytes(&TEST_KEY_SEED);
    // may read the flow, not its source
    let tokens = SigningTokens::new(key.clone(), SITE)
        .subject("user:viewer")
        .max(Perm::Read)
        .grants(vec![Grant {
            k: format!("wy/{SITE}/dataflows/**"),
            p: Perm::Read,
        }]);
    let viewer = WyrmClient::new(env.session.clone())
        .with_tokens(Arc::new(tokens))
        .with_timeout(Duration::from_secs(3));
    for action in ["watch", "ports"] {
        let e = match viewer.invoke(&flow, action, map(&[])).await {
            Ok(mut s) => s.next().await.unwrap().unwrap_err(),
            Err(e) => e,
        };
        assert_eq!(
            e.status,
            wyrm_core::status::StatusCode::Known(wyrm_core::Status::PermissionDenied),
            "{action}: {e}"
        );
        // the SDK sends `permission_denied` without its text (the engine names the key)
    }
    // with the right on the source it opens
    let tokens = SigningTokens::new(key, SITE)
        .subject("user:viewer")
        .max(Perm::Read)
        .grants(vec![
            Grant {
                k: format!("wy/{SITE}/dataflows/**"),
                p: Perm::Read,
            },
            Grant {
                k: format!("wy/{SITE}/downstream/mock/**"),
                p: Perm::Read,
            },
        ]);
    let reader = WyrmClient::new(env.session.clone())
        .with_tokens(Arc::new(tokens))
        .with_timeout(Duration::from_secs(3));
    let snap = reader
        .invoke_one(&flow, "ports", map(&[]))
        .await
        .unwrap()
        .unwrap();
    assert_eq!(at(&snap, &["snapshot"]), Some(&Value::Bool(true)));
    // bad arguments
    let e = env
        .client
        .invoke_one(&flow, "ports", map(&[("nodes", arr(&[s("nope")]))]))
        .await
        .unwrap_err();
    assert_eq!(
        e.status,
        wyrm_core::status::StatusCode::Known(wyrm_core::Status::InvalidParameter),
        "{e}"
    );
    env.stop().await;
}

/// The engine cannot see a caller that went away: a caller's watches past the cap end its
/// oldest one, and another caller's are `busy`.
#[tokio::test(flavor = "multi_thread")]
async fn watch_caps_end_the_same_callers_oldest() {
    let env = Env::start("watch-caps").await;
    env.deploy(watched(1)).await.unwrap();
    let flow = format!("wy/{SITE}/dataflows/w");
    let mut open = Vec::new();
    for _ in 0..wyrm_flow::watch::MAX_PER_FLOW {
        let mut st = env.client.invoke(&flow, "watch", map(&[])).await.unwrap();
        st.next().await.unwrap().unwrap();
        open.push(st);
    }
    // a dropped stream still holds its place: the engine never hears of it
    drop(open.pop());
    let key = ed25519_dalek::SigningKey::from_bytes(&TEST_KEY_SEED);
    let other = WyrmClient::new(env.session.clone())
        .with_tokens(Arc::new(
            SigningTokens::new(key, SITE).subject("user:other"),
        ))
        .with_timeout(Duration::from_secs(3));
    tokio::time::sleep(Duration::from_millis(300)).await;
    let e = other
        .invoke(&flow, "watch", map(&[]))
        .await
        .unwrap()
        .next()
        .await
        .unwrap()
        .unwrap_err();
    assert_eq!(
        e.status,
        wyrm_core::status::StatusCode::Known(wyrm_core::Status::Busy),
        "{e}"
    );
    // the same caller again: its oldest watch ends, the new one runs
    let mut st = env.client.invoke(&flow, "watch", map(&[])).await.unwrap();
    st.next().await.unwrap().unwrap();
    let mut oldest = open.remove(0);
    let ended = tokio::time::timeout(Duration::from_secs(3), async {
        while let Some(r) = oldest.next().await {
            r.unwrap();
        }
    })
    .await;
    assert!(ended.is_ok(), "the oldest watch ended");
    env.stop().await;
}

/// An `invoke` node's output carries its target's answer: a watcher reads the targets too.
#[tokio::test(flavor = "multi_thread")]
async fn watch_needs_the_rights_on_the_command_targets() {
    use wyrm_core::ptok::Grant;
    use wyrm_core::Perm;
    let env = Env::start("watch-targets").await;
    let def = map(&[
        ("id", s("cmd")),
        ("version", Value::UInt(1)),
        (
            "nodes",
            map(&[
                (
                    "a",
                    map(&[("type", s("subscribe")), ("key", s("downstream/mock/p0"))]),
                ),
                (
                    "go",
                    map(&[
                        ("type", s("invoke")),
                        ("path", s("downstream/mock")),
                        ("action", s("reset")),
                        ("on", s("change")),
                    ]),
                ),
            ]),
        ),
        ("edges", arr(&[edge("a.out", "go.in")])),
        ("permissions", map(&[("maxperm", s("write"))])),
    ]);
    env.deploy(def).await.unwrap();
    let flow = format!("wy/{SITE}/dataflows/cmd");
    let key = ed25519_dalek::SigningKey::from_bytes(&TEST_KEY_SEED);
    let viewer = |grants: Vec<Grant>| {
        let tokens = SigningTokens::new(key.clone(), SITE)
            .subject("user:viewer")
            .max(Perm::Read)
            .grants(grants);
        WyrmClient::new(env.session.clone())
            .with_tokens(Arc::new(tokens))
            .with_timeout(Duration::from_secs(3))
    };
    let g = |k: &str| Grant {
        k: format!("wy/{SITE}/{k}"),
        p: Perm::Read,
    };
    // the source, not the target `downstream/mock`
    let sources_only = viewer(vec![g("dataflows/**"), g("downstream/mock/p0")]);
    for action in ["watch", "ports"] {
        let e = match sources_only.invoke(&flow, action, map(&[])).await {
            Ok(mut st) => st.next().await.unwrap().unwrap_err(),
            Err(e) => e,
        };
        assert_eq!(
            e.status,
            wyrm_core::status::StatusCode::Known(wyrm_core::Status::PermissionDenied),
            "{action}: {e}"
        );
    }
    let both = viewer(vec![g("dataflows/**"), g("downstream/mock/**")]);
    let snap = both
        .invoke_one(&flow, "ports", map(&[]))
        .await
        .unwrap()
        .unwrap();
    assert_eq!(at(&snap, &["snapshot"]), Some(&Value::Bool(true)));
    env.stop().await;
}

// ---------- preview (ADR 0038 §5) ----------

/// A stand-in link at `downstream/spy` that counts every command query it gets (`~set`,
/// `~act/*`): the only queryable on its keys, so the count is exact.
struct Spy {
    count: Arc<std::sync::atomic::AtomicUsize>,
    _q: zenoh::query::Queryable<()>,
}

impl Spy {
    async fn on(session: &zenoh::Session) -> Self {
        let count = Arc::new(std::sync::atomic::AtomicUsize::new(0));
        let n = count.clone();
        let q = session
            .declare_queryable(format!("wy/{SITE}/downstream/spy/**"))
            .callback(move |q| {
                let k = q.key_expr().as_str();
                if k.contains("/~set") || k.contains("/~act/") {
                    n.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
                }
            })
            .await
            .unwrap();
        Self { count, _q: q }
    }

    fn commands(&self) -> usize {
        self.count.load(std::sync::atomic::Ordering::SeqCst)
    }
}

/// The owner's case: two variables into `concat` into `set`; a source through `round` into
/// `invoke` and `publish`. Every command aims at the spy.
fn draft() -> Value {
    map(&[
        ("id", s("pv")),
        ("version", Value::UInt(1)),
        (
            "nodes",
            map(&[
                (
                    "a",
                    map(&[("type", s("number")), ("value", Value::UInt(2))]),
                ),
                ("b", map(&[("type", s("string")), ("value", s("x"))])),
                ("c", map(&[("type", s("concat"))])),
                (
                    "w",
                    map(&[
                        ("type", s("set")),
                        ("path", s("downstream/spy/x")),
                        ("on", s("any")),
                    ]),
                ),
                (
                    "src",
                    map(&[("type", s("subscribe")), ("key", s("downstream/mock/p0"))]),
                ),
                (
                    "r",
                    map(&[("type", s("round")), ("precision", Value::UInt(1))]),
                ),
                (
                    "go",
                    map(&[
                        ("type", s("invoke")),
                        ("path", s("downstream/spy")),
                        ("action", s("go")),
                        ("args", map(&[("v", s("$in"))])),
                    ]),
                ),
                ("show", map(&[("type", s("publish")), ("node", s("show"))])),
            ]),
        ),
        (
            "edges",
            arr(&[
                edge("a.out", "c.in.0"),
                edge("b.out", "c.in.1"),
                edge("c.out", "w.in"),
                edge("src.out", "r.in"),
                edge("r.out", "go.in"),
                edge("r.out", "show.in"),
            ]),
        ),
        ("permissions", map(&[("maxperm", s("write"))])),
    ])
}

fn node_name(m: &std::collections::BTreeMap<String, Value>) -> String {
    match m.get("node") {
        Some(Value::Str(n)) => n.clone(),
        _ => String::new(),
    }
}

fn sinks_of(row: &Value) -> Vec<std::collections::BTreeMap<String, Value>> {
    match at(row, &["sinks"]) {
        Some(Value::Array(a)) => a
            .iter()
            .filter_map(|v| match v {
                Value::Map(m) => Some(m.clone()),
                _ => None,
            })
            .collect(),
        _ => Vec::new(),
    }
}

/// A preview streams `watch`'s rows from the start (the variables' start values in the
/// snapshot), reports what its sinks would do, and sends no `~set` or `~act` query at all;
/// the same definition deployed does (the control).
#[tokio::test(flavor = "multi_thread")]
async fn preview_runs_a_draft_and_writes_nothing() {
    use std::collections::BTreeMap;
    let env = Env::start("preview").await;
    let spy = Spy::on(&env.session).await;
    let root = format!("wy/{SITE}/dataflows");
    let mut st = env
        .client
        .invoke(
            &root,
            "preview",
            map(&[("def", draft()), ("max_hz", Value::UInt(10))]),
        )
        .await
        .unwrap();
    let first = st.next().await.unwrap().unwrap().unwrap();
    assert_eq!(at(&first, &["snapshot"]), Some(&Value::Bool(true)));
    // recorded from the start: what the variables sent when they started
    assert_eq!(
        at(&first, &["nodes", "a", "out", "out"]),
        Some(&arr(&[Value::UInt(2), Value::UInt(0)]))
    );
    assert_eq!(
        at(&first, &["nodes", "b", "out", "out"]),
        Some(&arr(&[s("x"), Value::UInt(0)]))
    );
    assert_eq!(
        keys(at(&first, &["nodes"])),
        ["a", "b", "c", "go", "r", "show", "src", "w"]
    );
    // the sinks: what each would do, never done
    let mut seen: BTreeMap<String, BTreeMap<String, Value>> = sinks_of(&first)
        .into_iter()
        .map(|m| (node_name(&m), m))
        .collect();
    let t0 = tokio::time::Instant::now();
    while seen.len() < 3 && t0.elapsed() < Duration::from_secs(5) {
        let row = st.next().await.unwrap().unwrap().unwrap();
        for m in sinks_of(&row) {
            seen.insert(node_name(&m), m);
        }
    }
    let w = &seen["w"];
    assert_eq!(w["op"], s("set"));
    assert_eq!(w["key"], s("wy/test/downstream/spy/x/~set"));
    assert_eq!(w["value"], s("2x"));
    let go = &seen["go"];
    assert_eq!(go["op"], s("invoke"));
    assert_eq!(go["key"], s("wy/test/downstream/spy/~act/go"));
    assert!(matches!(&go["value"], Value::Map(m) if m["v"].as_f64().is_some()));
    let show = &seen["show"];
    assert_eq!(show["op"], s("publish"));
    assert_eq!(show["key"], s("wy/test/dataflows/pv/nodes/show"));
    // values flow on, nothing is written, nothing is in the tree
    let t1 = tokio::time::Instant::now();
    while t1.elapsed() < Duration::from_millis(1500) {
        st.next().await.unwrap().unwrap().unwrap();
    }
    assert_eq!(spy.commands(), 0, "a preview sent a command");
    assert!(env.last("pv/nodes/show").is_none());
    let names: Vec<String> = env
        .client
        .children(&root)
        .await
        .unwrap()
        .into_iter()
        .map(|c| c.name)
        .collect();
    assert!(!names.contains(&"pv".to_owned()), "{names:?}");
    // the control: the same definition deployed writes to the spy
    env.deploy(draft()).await.unwrap();
    wait("deployed commands", || (spy.commands() >= 2).then_some(())).await;
    drop(st);
    env.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn preview_checks_the_draft_and_the_rights() {
    use wyrm_core::ptok::Grant;
    use wyrm_core::status::StatusCode;
    use wyrm_core::{Perm, Status};
    let env = Env::start("preview-checks").await;
    let root = format!("wy/{SITE}/dataflows");
    let err = |c: WyrmClient, args: Value| {
        let root = root.clone();
        async move {
            match c.invoke(&root, "preview", args).await {
                Ok(mut st) => st.next().await.unwrap().unwrap_err(),
                Err(e) => e,
            }
        }
    };
    // the compiler's message
    let bad = map(&[
        ("id", s("pv")),
        ("nodes", map(&[("x", map(&[("type", s("nope"))]))])),
    ]);
    let e = err(env.client.clone(), map(&[("def", bad)])).await;
    assert_eq!(e.status, StatusCode::Known(Status::InvalidParameter), "{e}");
    assert!(e.message.contains("nodes.x"), "{e}");
    let e = err(
        env.client.clone(),
        map(&[("def", draft()), ("max_hz", Value::UInt(21))]),
    )
    .await;
    assert_eq!(e.status, StatusCode::Known(Status::InvalidParameter), "{e}");
    // a reader of the flows who may not read the targets
    let key = ed25519_dalek::SigningKey::from_bytes(&TEST_KEY_SEED);
    let viewer = |grants: Vec<&str>| {
        let tokens = SigningTokens::new(key.clone(), SITE)
            .subject("user:viewer")
            .max(Perm::Read)
            .grants(
                grants
                    .into_iter()
                    .map(|k| Grant {
                        k: format!("wy/{SITE}/{k}"),
                        p: Perm::Read,
                    })
                    .collect(),
            );
        WyrmClient::new(env.session.clone())
            .with_tokens(Arc::new(tokens))
            .with_timeout(Duration::from_secs(3))
    };
    let e = err(
        viewer(vec!["dataflows/**", "downstream/mock/**"]),
        map(&[("def", draft())]),
    )
    .await;
    assert_eq!(e.status, StatusCode::Known(Status::PermissionDenied), "{e}");
    // with read on the sources and the targets it runs: no `write` needed
    let reader = viewer(vec!["dataflows/**", "downstream/**"]);
    let mut st = reader
        .invoke(&root, "preview", map(&[("def", draft())]))
        .await
        .unwrap();
    let first = st.next().await.unwrap().unwrap().unwrap();
    assert_eq!(at(&first, &["snapshot"]), Some(&Value::Bool(true)));
    // `nodes` narrows the rows, sinks included
    let mut st = reader
        .invoke(
            &root,
            "preview",
            map(&[("def", draft()), ("nodes", arr(&[s("w")]))]),
        )
        .await
        .unwrap();
    let first = st.next().await.unwrap().unwrap().unwrap();
    assert_eq!(keys(at(&first, &["nodes"])), ["w"]);
    for m in sinks_of(&first) {
        assert_eq!(m["node"], s("w"));
    }
    env.stop().await;
}

/// Two previews per subject (a third ends that subject's oldest), sixteen per site (`busy`).
#[tokio::test(flavor = "multi_thread")]
async fn preview_caps() {
    use wyrm_core::status::StatusCode;
    use wyrm_core::Status;
    use wyrm_flow::preview::{PER_SITE, PER_SUBJECT};
    let env = Env::start("preview-caps").await;
    let root = format!("wy/{SITE}/dataflows");
    let key = ed25519_dalek::SigningKey::from_bytes(&TEST_KEY_SEED);
    let as_user = |n: usize| {
        WyrmClient::new(env.session.clone())
            .with_tokens(Arc::new(
                SigningTokens::new(key.clone(), SITE).subject(format!("user:u{n}")),
            ))
            .with_timeout(Duration::from_secs(3))
    };
    // blocks only: no sources, no targets
    let small = map(&[
        ("id", s("small")),
        (
            "nodes",
            map(&[
                (
                    "a",
                    map(&[("type", s("number")), ("value", Value::UInt(1))]),
                ),
                ("n", map(&[("type", s("not"))])),
            ]),
        ),
        ("edges", arr(&[edge("a.out", "n.in")])),
    ]);
    let open = |c: WyrmClient| {
        let (root, small) = (root.clone(), small.clone());
        async move {
            let mut st = c
                .invoke(&root, "preview", map(&[("def", small)]))
                .await
                .unwrap();
            let first = st.next().await.unwrap();
            (st, first)
        }
    };
    let u0 = as_user(0);
    let (mut oldest, first) = open(u0.clone()).await;
    first.unwrap();
    let mut held = Vec::new();
    for _ in 1..PER_SUBJECT {
        let (st, first) = open(u0.clone()).await;
        first.unwrap();
        held.push(st);
    }
    // the same subject once more: its oldest ends
    let (st, first) = open(u0.clone()).await;
    first.unwrap();
    held.push(st);
    let ended = tokio::time::timeout(Duration::from_secs(3), async {
        while let Some(r) = oldest.next().await {
            r.unwrap();
        }
    })
    .await;
    assert!(ended.is_ok(), "the subject's oldest preview ended");
    // the site: other subjects up to the cap, then busy
    let mut n = 1;
    while held.len() < PER_SITE {
        let (st, first) = open(as_user(n)).await;
        first.unwrap();
        held.push(st);
        if held.len() % PER_SUBJECT == 0 {
            n += 1;
        }
    }
    let (_st, first) = open(as_user(99)).await;
    let e = first.unwrap_err();
    assert_eq!(e.status, StatusCode::Known(Status::Busy), "{e}");
    env.stop().await;
}
