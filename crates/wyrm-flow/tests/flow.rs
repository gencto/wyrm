//! Flow engine end to end on an in-memory session: a mock link as the
//! data source and command target, the engine on `wy/test/flows`.

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
                    map(&[("type", s("subscribe")), ("key", s("down/mock/p0"))]),
                ),
                (
                    "b",
                    map(&[("type", s("subscribe")), ("key", s("down/mock/p1"))]),
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
                        ("path", s("down/mock")),
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
    let mut lcfg = LinkConfig::new(SITE, "flows");
    lcfg.root = Some(format!("wy/{SITE}/flows"));
    lcfg.admin_keys = vec![key.verifying_key()];
    wyrm_link_sdk::spawn::<Engine>(
        session.clone(),
        lcfg,
        EngineStart {
            host,
            admin_keys: vec![key.verifying_key()],
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
                &format!("wy/{SITE}/flows"),
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
}

#[tokio::test(flavor = "multi_thread")]
async fn peak_shaving_hot_swap_and_restart() {
    let mut env = Env::start("peak").await;
    // fixed meter values (the mock holds written values): sum 35 > alarm 30
    env.client
        .set(&format!("wy/{SITE}/down/mock/p0"), 20.0)
        .await
        .unwrap();
    env.client
        .set(&format!("wy/{SITE}/down/mock/p1"), 15.0)
        .await
        .unwrap();
    env.deploy(peak(1, "a.v + b.v")).await.unwrap();

    // total = p0 + p1 (≈ 20..60), published as a flow node
    let total = wait("total", || env.last("peak/nodes/total")).await;
    assert!(num(&total) > 0.0);
    // alarm (high 30) fires on the rising edge → `reset` on the mock → result published
    let mut vals = env
        .client
        .subscribe(&format!("wy/{SITE}/flows/peak/nodes/shed"))
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
    let flow = format!("wy/{SITE}/flows/peak");
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
            &format!("wy/{SITE}/flows"),
            "deploy",
            deploy_args(&c, peak(1, "a.v + b.v")),
        )
        .await
        .unwrap_err();
    assert!(e.is(wyrm_core::Status::PermissionDenied), "{e}");
    env.stop().await;
}

/// `config` on `flows/**` alone does not let a flow command devices: the
/// deployer proves its own rights on every target.
#[tokio::test(flavor = "multi_thread")]
async fn deploy_needs_proofs_for_targets() {
    let env = Env::start("proofs").await;
    let flows = format!("wy/{SITE}/flows");
    // no proofs
    let e = env
        .client
        .invoke_one(&flows, "deploy", map(&[("def", peak(1, "a.v + b.v"))]))
        .await
        .unwrap_err();
    assert!(e.is(wyrm_core::Status::PermissionDenied), "{e}");
    // a deployer whose grants cover only flows/** cannot mint proofs
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
    // targets outside wy/<site>/down/ or with wildcards are refused
    for path in ["sys/links/mock", "down/*"] {
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
            &format!("wy/{SITE}/flows"),
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
        .subscribe(&format!("wy/{SITE}/flows/wf"))
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
    env.deploy(peak(1, "a.v + b.v")).await.unwrap();
    env.deploy(peak(2, "a.v - b.v")).await.unwrap();
    let flow = format!("wy/{SITE}/flows/peak");
    let h = env
        .client
        .invoke_one(&flow, "history", map(&[]))
        .await
        .unwrap();
    let Some(Value::Array(defs)) = h else {
        panic!("history is an array: {h:?}")
    };
    assert_eq!(defs.len(), 2, "v1 and the current v2");
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
