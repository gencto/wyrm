//! ADR 0040 on an in-memory session: keys from a port inside a scope, the action block's
//! behaviours, custom blocks and the blocks of the second set. A mock link is the data source
//! and the command target; the engine is on `wy/test/dataflows`.

use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;
use wyrm_client::{ClientError, SigningTokens, WyrmClient};
use wyrm_core::ptok::Grant;
use wyrm_core::status::StatusCode;
use wyrm_core::{Perm, Sample, Status, Value};
use wyrm_flow::{def, Engine, EngineStart, FlowHost};
use wyrm_link_mock::{Mock, MockConfig};
use wyrm_link_sdk::harness::{isolated_config, TEST_KEY_SEED};
use wyrm_link_sdk::{LinkConfig, LinkHandle};

const SITE: &str = "test";

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
    arr(&[Value::from(a), Value::from(b)])
}

fn s(x: &str) -> Value {
    Value::from(x)
}

fn node(ty: &str, kv: &[(&str, Value)]) -> Value {
    let mut all = vec![("type", s(ty))];
    all.extend(kv.iter().cloned());
    map(&all)
}

fn publish(name: &str) -> Value {
    node("publish", &[("node", s(name))])
}

fn flow(id: &str, nodes: &[(&str, Value)], edges: &[(&str, &str)]) -> Value {
    map(&[
        ("id", s(id)),
        ("version", Value::UInt(1)),
        ("nodes", map(nodes)),
        (
            "edges",
            arr(&edges.iter().map(|(a, b)| edge(a, b)).collect::<Vec<_>>()),
        ),
        ("permissions", map(&[("maxperm", s("write"))])),
    ])
}

fn at<'a>(v: &'a Value, path: &[&str]) -> Option<&'a Value> {
    path.iter().try_fold(v, |v, k| match v {
        Value::Map(m) => m.get(*k),
        _ => None,
    })
}

fn temp(name: &str) -> PathBuf {
    let d = std::env::temp_dir().join(format!("wyrm-behaviours-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&d);
    d
}

struct Env {
    session: zenoh::Session,
    client: WyrmClient,
    mock: Option<LinkHandle<Mock>>,
    engine: Option<LinkHandle<Engine>>,
    dir: PathBuf,
}

fn admin_key() -> ed25519_dalek::SigningKey {
    ed25519_dalek::SigningKey::from_bytes(&TEST_KEY_SEED)
}

impl Env {
    async fn start(name: &str) -> Self {
        let dir = temp(name);
        let session = zenoh::open(isolated_config()).await.unwrap();
        let key = admin_key();
        let host = FlowHost::open(&dir, b"flow-test-hmac-key", SITE).unwrap();
        // links trust the operator key and the engine's own key
        let mut lcfg = LinkConfig::new(SITE, "mock");
        lcfg.admin_keys = vec![key.verifying_key(), host.verifying_key()];
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

    /// A client of `sub` with these grants.
    fn user(&self, sub: &str, grants: &[(&str, Perm)]) -> WyrmClient {
        let tokens = SigningTokens::new(admin_key(), SITE)
            .subject(sub)
            .max(Perm::Config)
            .grants(
                grants
                    .iter()
                    .map(|(k, p)| Grant {
                        k: format!("wy/{SITE}/{k}"),
                        p: *p,
                    })
                    .collect(),
            );
        WyrmClient::new(self.session.clone())
            .with_tokens(Arc::new(tokens))
            .with_timeout(Duration::from_secs(3))
    }

    async fn deploy_as(&self, c: &WyrmClient, def: Value) -> Result<(), ClientError> {
        let proofs = wyrm_flow::command_targets(&def, SITE)
            .unwrap_or_default()
            .into_iter()
            .filter_map(|t| c.proof(&t).map(|p| (t, Value::Bytes(p))))
            .collect();
        c.invoke_one(
            &format!("wy/{SITE}/dataflows"),
            "deploy",
            map(&[("def", def), ("proofs", Value::Map(proofs))]),
        )
        .await
        .map(|_| ())
    }

    async fn deploy(&self, def: Value) -> Result<(), ClientError> {
        self.deploy_as(&self.client, def).await
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
        let _ = std::fs::remove_dir_all(&self.dir);
    }
}

async fn wait<T>(what: &str, mut f: impl FnMut() -> Option<T>) -> T {
    let deadline = tokio::time::Instant::now() + Duration::from_secs(8);
    loop {
        if let Some(v) = f() {
            return v;
        }
        assert!(tokio::time::Instant::now() < deadline, "timeout: {what}");
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
}

fn status(e: &ClientError) -> StatusCode {
    e.status
}

fn denied(e: &ClientError) -> bool {
    status(e) == StatusCode::Known(Status::PermissionDenied)
}

/// The first reply of an action that may answer as a stream or as an error.
async fn first(
    c: &WyrmClient,
    node: &str,
    action: &str,
    args: Value,
) -> Result<Value, ClientError> {
    match c.invoke(node, action, args).await {
        Ok(mut st) => match st.next().await {
            Some(Ok(v)) => Ok(v.unwrap_or(Value::Null)),
            Some(Err(e)) => Err(e),
            None => Ok(Value::Null),
        },
        Err(e) => Err(e),
    }
}

// ---------- A. keys from a port, inside a scope (ADR 0040 §1) ----------

/// A timer walks three names; a `case` turns each into a key; the key drives a `subscribe`.
/// The third name is outside the scope.
fn walker(scope: &str) -> Value {
    flow(
        "walk",
        &[
            ("t", node("timer", &[("period_ms", Value::UInt(350))])),
            ("m", node("modulo", &[("modulo", Value::UInt(3))])),
            (
                "pick",
                node(
                    "case",
                    &[
                        ("inputs", arr(&[s("c0"), s("k0"), s("c1"), s("k1")])),
                        (
                            "values",
                            map(&[
                                ("in.c0", Value::UInt(1)),
                                ("in.k0", s("downstream/mock/p0")),
                                ("in.c1", Value::UInt(2)),
                                ("in.k1", s("downstream/mock/p1")),
                            ]),
                        ),
                        ("else", s("downstream/other/p0")),
                    ],
                ),
            ),
            ("sub", node("subscribe", &[("key_scope", s(scope))])),
            ("val", publish("val")),
            ("key", publish("key")),
            ("err", publish("err")),
        ],
        &[
            ("t.out", "m.in"),
            ("m.remainder", "pick.in"),
            ("pick.out", "sub.in.key"),
            ("sub.out", "val.in"),
            ("sub.key", "key.in"),
            ("sub.error", "err.in"),
        ],
    )
}

#[test]
fn a_key_from_a_port_needs_a_scope() {
    let src = |kv: &[(&str, Value)]| {
        flow(
            "f",
            &[("k", node("string", &[])), ("a", node("subscribe", kv))],
            &[("k.out", "a.in.key")],
        )
    };
    let e = def::compile(&src(&[("key", s("downstream/mock/p0"))])).unwrap_err();
    assert!(
        e.0.contains("nodes.a.key_scope: required when in.key is wired"),
        "{e}"
    );
    def::compile(&src(&[("key_scope", s("downstream/mock/*"))])).unwrap();
    // a start key and a scope together
    def::compile(&src(&[
        ("key", s("downstream/mock/p0")),
        ("key_scope", s("downstream/mock/*")),
    ]))
    .unwrap();
    // neither a key nor a scope
    let e = def::compile(&flow("f", &[("a", node("subscribe", &[]))], &[])).unwrap_err();
    assert!(e.0.contains("nodes.a: key: required"), "{e}");
    // the same for liveliness
    let e = def::compile(&flow(
        "f",
        &[
            ("k", node("string", &[])),
            ("a", node("liveliness", &[("key", s("downstream/mock"))])),
        ],
        &[("k.out", "a.in.key")],
    ))
    .unwrap_err();
    assert!(e.0.contains("nodes.a.key_scope"), "{e}");
}

#[tokio::test(flavor = "multi_thread")]
async fn a_subscribe_follows_the_key_on_its_port() {
    let env = Env::start("walk").await;
    // a scope outside the site's sections does not compile
    let e = env.deploy(walker("sys/**")).await.unwrap_err();
    assert_eq!(status(&e), StatusCode::Known(Status::InvalidParameter));
    assert!(e.message.contains("nodes.sub.key_scope"), "{e}");
    env.deploy(walker("downstream/mock/*")).await.unwrap();
    // both points are read in turn: the node's effective key says which
    let mut seen = std::collections::BTreeSet::new();
    wait("both keys read", || {
        if let Some(Value::Str(k)) = env.last("walk/nodes/key").map(|s| s.v) {
            if env
                .last("walk/nodes/val")
                .is_some_and(|s| s.v.as_f64().is_some())
            {
                seen.insert(k);
            }
        }
        (seen.len() == 2).then_some(())
    })
    .await;
    assert!(seen.contains("downstream/mock/p0") && seen.contains("downstream/mock/p1"));
    // the third name is outside the scope: an error, no key, and nothing read
    let why = wait("refused", || {
        env.last("walk/nodes/err").and_then(|s| match s.v {
            Value::Str(e) => Some(e),
            _ => None,
        })
    })
    .await;
    assert!(why.contains("outside the scope downstream/mock/*"), "{why}");
    // while it is refused, `out` stays null and uncertain (20 Hz of the mock would show)
    wait("null while refused", || {
        let (err, val, key) = (
            env.last("walk/nodes/err")?,
            env.last("walk/nodes/val")?,
            env.last("walk/nodes/key")?,
        );
        (matches!(err.v, Value::Str(_))
            && val.v == Value::Null
            && val.q == wyrm_core::Quality::Uncertain
            && key.v == Value::Null)
            .then_some(())
    })
    .await;
    // and the error clears with the next good key
    wait("error cleared", || {
        env.last("walk/nodes/err")
            .filter(|s| s.v == Value::Null)
            .map(|_| ())
    })
    .await;
    env.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn a_scope_needs_the_rights_of_the_deployer_and_of_the_watcher() {
    let env = Env::start("scope-rights").await;
    let flows = format!("wy/{SITE}/dataflows");
    // config on the flows, read on one point only: the scope is wider
    let narrow = env.user(
        "user:narrow",
        &[
            ("dataflows/**", Perm::Config),
            ("downstream/mock/p0", Perm::Read),
        ],
    );
    let e = env
        .deploy_as(&narrow, walker("downstream/mock/*"))
        .await
        .unwrap_err();
    assert!(denied(&e), "{e}");
    // a deny grant inside the scope refuses it too, whatever comes after
    let holed = env.user(
        "user:holed",
        &[
            ("dataflows/**", Perm::Config),
            ("downstream/mock/p1", Perm::None),
            ("downstream/**", Perm::Read),
        ],
    );
    let e = env
        .deploy_as(&holed, walker("downstream/mock/*"))
        .await
        .unwrap_err();
    assert!(denied(&e), "{e}");
    // a preview of the same draft asks the same
    let e = first(
        &narrow,
        &flows,
        "preview",
        map(&[("def", walker("downstream/mock/*"))]),
    )
    .await
    .unwrap_err();
    assert!(denied(&e), "{e}");
    // with read on all of the scope it deploys
    let wide = env.user(
        "user:wide",
        &[
            ("dataflows/**", Perm::Config),
            ("downstream/mock/**", Perm::Read),
        ],
    );
    env.deploy_as(&wide, walker("downstream/mock/*"))
        .await
        .unwrap();
    let row = first(
        &wide,
        &flows,
        "preview",
        map(&[("def", walker("downstream/mock/*"))]),
    )
    .await
    .unwrap();
    assert_eq!(at(&row, &["snapshot"]), Some(&Value::Bool(true)));
    // watch and ports of the deployed flow: the narrow reader is refused, the wide one not
    let flow = format!("{flows}/walk");
    for action in ["watch", "ports"] {
        let e = first(&narrow, &flow, action, map(&[])).await.unwrap_err();
        assert!(denied(&e), "{action}: {e}");
        let row = first(&wide, &flow, action, map(&[])).await.unwrap();
        assert_eq!(
            at(&row, &["snapshot"]),
            Some(&Value::Bool(true)),
            "{action}"
        );
    }
    env.stop().await;
}

// ---------- B. the action block and its behaviours (ADR 0040 §2) ----------

fn ev_id(s: &Sample) -> Option<u64> {
    match at(&s.v, &["id"]) {
        Some(Value::UInt(i)) => Some(*i),
        _ => None,
    }
}

/// Command blocks with every new behaviour set, fed only by what a start brings: variables
/// (alone and through blocks), a parameter's echo, a `const` and a timer's first tick.
fn armed(version: u64) -> Value {
    let mut d = flow(
        "armed",
        &[
            ("yes", node("bool", &[("value", Value::Bool(true))])),
            ("no", node("not", &[])),
            ("three", node("number", &[("value", Value::UInt(3))])),
            (
                "sum",
                node("add", &[("values", map(&[("in.1", Value::UInt(1))]))]),
            ),
            ("k", node("const", &[("value", Value::UInt(7))])),
            (
                "slow",
                node("timer", &[("period_ms", Value::UInt(3_600_000))]),
            ),
            ("r", node("round", &[("precision", Value::UInt(2))])),
            ("hub", node("hub", &[])),
            (
                "call",
                node(
                    "invoke",
                    &[
                        ("path", s("downstream/mock")),
                        ("action", s("count")),
                        ("args", map(&[("n", Value::UInt(1))])),
                        ("auto_run", Value::Bool(true)),
                        ("interval_ms", Value::UInt(3_600_000)),
                    ],
                ),
            ),
            (
                "tick",
                node(
                    "invoke",
                    &[("path", s("downstream/mock")), ("action", s("reset"))],
                ),
            ),
            (
                "echo",
                node(
                    "invoke",
                    &[("path", s("downstream/mock")), ("action", s("reset"))],
                ),
            ),
            (
                "w",
                node(
                    "set",
                    &[
                        ("path", s("downstream/mock/p0")),
                        ("auto_run", Value::Bool(false)),
                        ("interval_ms", Value::UInt(3_600_000)),
                    ],
                ),
            ),
            ("s1", publish("call_sent")),
            ("s2", publish("tick_sent")),
            ("s3", publish("echo_sent")),
            ("s4", publish("w_sent")),
            ("seen", publish("seen")),
        ],
        &[
            // a variable through a block, into a trigger
            ("yes.out", "no.in"),
            ("no.out", "call.trigger"),
            // a variable through a block, into an argument of an auto_run block
            ("three.out", "sum.in.0"),
            ("sum.out", "call.arg.n"),
            // a timer's tick at the start, and a hub's event caused by a const
            ("slow.out", "tick.trigger"),
            ("k.out", "hub.in.0"),
            ("hub.on_change", "echo.trigger"),
            // a parameter's echo into a set that waits for its trigger
            ("r.precision", "w.in"),
            ("yes.out", "w.trigger"),
            ("call.sent", "s1.in"),
            ("tick.sent", "s2.in"),
            ("echo.sent", "s3.in"),
            ("w.sent", "s4.in"),
            // the start values did arrive
            ("sum.out", "seen.in"),
        ],
    );
    if let Value::Map(m) = &mut d {
        m.insert("version".into(), Value::UInt(version));
    }
    d
}

#[tokio::test(flavor = "multi_thread")]
async fn a_deploy_never_runs_a_command_through_the_new_behaviours() {
    let env = Env::start("armed").await;
    let nothing_ran = |env: &Env, when: &str| {
        for n in ["call_sent", "tick_sent", "echo_sent", "w_sent"] {
            assert!(
                env.last(&format!("armed/nodes/{n}")).is_none(),
                "{n} ran {when}"
            );
        }
    };
    env.deploy(armed(1)).await.unwrap();
    // the start values went through the blocks: 3 + 1
    wait("start values", || {
        env.last("armed/nodes/seen")
            .filter(|s| s.v.as_f64() == Some(4.0))
    })
    .await;
    tokio::time::sleep(Duration::from_millis(500)).await;
    nothing_ran(&env, "at deploy");
    // a hot swap (another version, the same nodes) and a reload
    env.deploy(armed(2)).await.unwrap();
    tokio::time::sleep(Duration::from_millis(400)).await;
    nothing_ran(&env, "at a hot swap");
    env.client
        .invoke_one(&format!("wy/{SITE}/dataflows/armed"), "reload", map(&[]))
        .await
        .unwrap();
    tokio::time::sleep(Duration::from_millis(400)).await;
    nothing_ran(&env, "at a reload");
    // the blocks are alive: the action runs each of them
    let flow = format!("wy/{SITE}/dataflows/armed");
    for n in ["call", "w"] {
        env.client
            .invoke_one(&flow, "trigger", map(&[("node", s(n))]))
            .await
            .unwrap();
    }
    wait("the action ran both", || {
        (env.last("armed/nodes/call_sent").is_some() && env.last("armed/nodes/w_sent").is_some())
            .then_some(())
    })
    .await;
    // the set wrote the value it held (the echo of precision) to the mock, which keeps it
    wait("the mock holds 2", || {
        env.mock
            .as_ref()
            .unwrap()
            .ctx()
            .last("p0")
            .filter(|s| s.v.as_f64() == Some(2.0))
    })
    .await;
    env.stop().await;
}

/// An action block with one argument, and what it reports.
fn action(n: Value, more: &[(&str, Value)]) -> Value {
    let mut cfg = vec![
        ("path", s("downstream/mock")),
        ("action", s("count")),
        ("args", map(&[("n", n)])),
    ];
    cfg.extend(more.iter().cloned());
    flow(
        "act",
        &[
            ("call", node("invoke", &cfg)),
            ("sent", publish("sent")),
            ("ok", publish("ok")),
            ("error", publish("error")),
            ("result", publish("result")),
            ("running", publish("running")),
            ("last_run", publish("last_run")),
        ],
        &[
            ("call.sent", "sent.in"),
            ("call.ok", "ok.in"),
            ("call.error", "error.in"),
            ("call.result", "result.in"),
            ("call.running", "running.in"),
            ("call.last_run", "last_run.in"),
        ],
    )
}

async fn trigger(c: &WyrmClient, flow: &str, node: &str) -> Result<(), ClientError> {
    c.invoke_one(flow, "trigger", map(&[("node", s(node))]))
        .await
        .map(|_| ())
}

#[tokio::test(flavor = "multi_thread")]
async fn the_trigger_action_runs_a_block_and_the_block_reports() {
    let env = Env::start("act").await;
    let flow = format!("wy/{SITE}/dataflows/act");
    env.deploy(action(Value::UInt(3), &[])).await.unwrap();
    tokio::time::sleep(Duration::from_millis(300)).await;
    assert!(
        env.last("act/nodes/sent").is_none(),
        "nothing ran at deploy"
    );
    trigger(&env.client, &flow, "call").await.unwrap();
    // sent, then ok with the action's result; running went up and down
    let ok = wait("ok", || env.last("act/nodes/ok")).await;
    assert_eq!(at(&ok.v, &["event"]), Some(&s("ok")));
    let sent = env.last("act/nodes/sent").unwrap();
    assert_eq!(at(&sent.v, &["event"]), Some(&s("sent")));
    assert!(ev_id(&sent) < ev_id(&ok), "{sent:?} {ok:?}");
    wait("the result", || {
        env.last("act/nodes/result")
            .filter(|s| s.v.as_f64() == Some(0.0))
    })
    .await;
    wait("idle again", || {
        env.last("act/nodes/running")
            .filter(|s| s.v == Value::Bool(false))
    })
    .await;
    assert!(matches!(
        env.last("act/nodes/last_run").unwrap().v,
        Value::UInt(t) if t > 1_600_000_000_000_000
    ));
    assert!(env.last("act/nodes/error").is_none());
    // rights: the caller itself needs write on the block's target
    let reader = env.user(
        "user:reader",
        &[("dataflows/**", Perm::Write), ("downstream/**", Perm::Read)],
    );
    let e = trigger(&reader, &flow, "call").await.unwrap_err();
    assert!(denied(&e), "{e}");
    let other = env.user(
        "user:other",
        &[
            ("dataflows/**", Perm::Write),
            ("downstream/mock/p0/**", Perm::Write),
        ],
    );
    let e = trigger(&other, &flow, "call").await.unwrap_err();
    assert!(denied(&e), "{e}");
    // a reader of the flow may not call the action at all (level write)
    let viewer = env.user("user:viewer", &[("**", Perm::Read)]);
    let e = trigger(&viewer, &flow, "call").await.unwrap_err();
    assert!(denied(&e), "{e}");
    let writer = env.user(
        "user:writer",
        &[
            ("dataflows/**", Perm::Write),
            ("downstream/mock/**", Perm::Write),
        ],
    );
    let before = ev_id(&env.last("act/nodes/sent").unwrap());
    trigger(&writer, &flow, "call").await.unwrap();
    wait("the writer's run", || {
        env.last("act/nodes/sent").filter(|s| ev_id(s) > before)
    })
    .await;
    // a node that is not a command block, and a node the flow does not have
    for bad in ["sent", "nope"] {
        let e = trigger(&env.client, &flow, bad).await.unwrap_err();
        assert_eq!(
            status(&e),
            StatusCode::Known(Status::InvalidParameter),
            "{bad}"
        );
    }
    // a stopped flow runs nothing
    env.client
        .invoke_one(&flow, "stop", map(&[]))
        .await
        .unwrap();
    let e = trigger(&env.client, &flow, "call").await.unwrap_err();
    assert_eq!(status(&e), StatusCode::Known(Status::NotSupported), "{e}");
    env.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn an_action_that_fails_gives_an_error_event() {
    let env = Env::start("act-error").await;
    let flow = format!("wy/{SITE}/dataflows/act");
    // the mock refuses a negative count with out_of_range
    env.deploy(action(Value::Int(-1), &[])).await.unwrap();
    trigger(&env.client, &flow, "call").await.unwrap();
    let err = wait("error", || env.last("act/nodes/error")).await;
    assert_eq!(at(&err.v, &["event"]), Some(&s("error")));
    assert_eq!(
        at(&err.v, &["code"]),
        Some(&Value::UInt(u64::from(Status::OutOfRange.code())))
    );
    assert!(
        matches!(at(&err.v, &["message"]), Some(Value::Str(m)) if m.contains("out_of_range")),
        "{err:?}"
    );
    assert!(env.last("act/nodes/sent").is_some());
    assert!(env.last("act/nodes/ok").is_none() && env.last("act/nodes/result").is_none());
    wait("idle again", || {
        env.last("act/nodes/running")
            .filter(|s| s.v == Value::Bool(false))
    })
    .await;
    env.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn interval_and_auto_run_run_a_deployed_action() {
    let env = Env::start("act-auto").await;
    // every 150 ms; and a stopwatch that counts 1, 2, … into the argument
    let mut d = action(
        Value::UInt(1),
        &[
            ("interval_ms", Value::UInt(150)),
            ("auto_run", Value::Bool(true)),
        ],
    );
    if let Value::Map(m) = &mut d {
        if let Some(Value::Map(nodes)) = m.get_mut("nodes") {
            nodes.insert(
                "sw".into(),
                node(
                    "stopwatch",
                    &[
                        ("enabled", Value::Bool(true)),
                        ("interval", Value::Float(0.1)),
                        ("reset_value", Value::UInt(1)),
                    ],
                ),
            );
        }
        if let Some(Value::Array(edges)) = m.get_mut("edges") {
            edges.push(edge("sw.out", "call.arg.n"));
        }
    }
    env.deploy(d).await.unwrap();
    wait("several runs", || {
        env.last("act/nodes/ok").filter(|s| ev_id(s) >= Some(8))
    })
    .await;
    assert!(env.last("act/nodes/error").is_none());
    env.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn a_preview_reports_sent_and_never_an_answer() {
    let env = Env::start("act-preview").await;
    let draft = flow(
        "draft",
        &[
            (
                "call",
                node(
                    "invoke",
                    &[
                        ("path", s("downstream/mock")),
                        ("action", s("count")),
                        ("args", map(&[("n", Value::UInt(2))])),
                        ("interval_ms", Value::UInt(100)),
                    ],
                ),
            ),
            ("v", node("number", &[("value", Value::UInt(4242))])),
            (
                "w",
                node(
                    "set",
                    &[
                        ("path", s("downstream/mock/p0")),
                        ("auto_run", Value::Bool(false)),
                        ("interval_ms", Value::UInt(100)),
                    ],
                ),
            ),
        ],
        &[("v.out", "w.in")],
    );
    let mut st = env
        .client
        .invoke(
            &format!("wy/{SITE}/dataflows"),
            "preview",
            map(&[("def", draft), ("max_hz", Value::UInt(20))]),
        )
        .await
        .unwrap();
    let first = st.next().await.unwrap().unwrap().unwrap();
    assert_eq!(at(&first, &["snapshot"]), Some(&Value::Bool(true)));
    assert_eq!(at(&first, &["sinks"]), None, "nothing runs at the start");
    let (mut called, mut wrote) = (0, 0);
    let deadline = tokio::time::Instant::now() + Duration::from_secs(8);
    while called < 2 || wrote < 2 {
        assert!(tokio::time::Instant::now() < deadline, "{called} {wrote}");
        let row = st.next().await.unwrap().unwrap().unwrap();
        for n in ["call", "w"] {
            let out = at(&row, &["nodes", n, "out"]);
            for answer in ["ok", "error", "result", "out", "running"] {
                assert!(
                    out.and_then(|o| at(o, &[answer])).is_none(),
                    "{n}.{answer}: {row:?}"
                );
            }
            if out.and_then(|o| at(o, &["sent"])).is_some() {
                if n == "call" {
                    called += 1;
                } else {
                    wrote += 1;
                }
            }
        }
        if let Some(Value::Array(sinks)) = at(&row, &["sinks"]) {
            for sk in sinks {
                match at(sk, &["node"]) {
                    Some(Value::Str(n)) if n == "call" => {
                        assert_eq!(at(sk, &["value", "n"]), Some(&Value::UInt(2)));
                        assert_eq!(
                            at(sk, &["key"]),
                            Some(&s("wy/test/downstream/mock/~act/count"))
                        );
                    }
                    _ => assert_eq!(at(sk, &["value"]), Some(&Value::UInt(4242))),
                }
            }
        }
    }
    // nothing reached the link: the point never held the value
    let p0 = env.mock.as_ref().unwrap().ctx().last("p0").unwrap();
    assert_ne!(p0.v.as_f64(), Some(4242.0));
    // a preview has no trigger action: the draft is not a flow
    let e = trigger(&env.client, &format!("wy/{SITE}/dataflows/draft"), "call")
        .await
        .unwrap_err();
    assert!(status(&e).is_error());
    drop(st);
    env.stop().await;
}
