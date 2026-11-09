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

/// `run_on_start` (owner decision 2026-11-09): the one sanctioned exception. A deployed block
/// with it runs exactly once at each start; a preview reports the run and writes nothing.
#[tokio::test(flavor = "multi_thread")]
async fn run_on_start_runs_exactly_once_at_each_start() {
    let env = Env::start("act-start").await;
    let flow_key = format!("wy/{SITE}/dataflows/act");
    let def = |version: u64| {
        let mut d = action(Value::UInt(3), &[("run_on_start", Value::Bool(true))]);
        if let Value::Map(m) = &mut d {
            m.insert("version".into(), Value::UInt(version));
        }
        d
    };
    env.deploy(def(1)).await.unwrap();
    let ok = wait("the start run", || env.last("act/nodes/ok")).await;
    assert_eq!(ev_id(&ok), Some(2), "sent is 1, ok is 2");
    tokio::time::sleep(Duration::from_millis(700)).await;
    assert_eq!(
        ev_id(&env.last("act/nodes/ok").unwrap()),
        Some(2),
        "exactly one run"
    );
    assert_eq!(ev_id(&env.last("act/nodes/sent").unwrap()), Some(1));
    // each start is one more run: a reload restarts the node
    let before = env.last("act/nodes/sent").unwrap().t;
    env.client
        .invoke_one(&flow_key, "reload", map(&[]))
        .await
        .unwrap();
    wait("the run of the second start", || {
        env.last("act/nodes/sent").filter(|s| s.t > before)
    })
    .await;
    // a preview of the same draft reports the run in `sinks` and never an answer
    let mut st = env
        .client
        .invoke(
            &format!("wy/{SITE}/dataflows"),
            "preview",
            map(&[("def", def(9)), ("max_hz", Value::UInt(20))]),
        )
        .await
        .unwrap();
    let deadline = tokio::time::Instant::now() + Duration::from_secs(8);
    loop {
        assert!(tokio::time::Instant::now() < deadline, "no sinks row");
        let row = st.next().await.unwrap().unwrap().unwrap();
        let out = at(&row, &["nodes", "call", "out"]);
        assert!(out.and_then(|o| at(o, &["ok"])).is_none(), "{row:?}");
        if let Some(Value::Array(sinks)) = at(&row, &["sinks"]) {
            assert_eq!(at(&sinks[0], &["op"]), Some(&s("invoke")));
            assert_eq!(at(&sinks[0], &["value", "n"]), Some(&Value::UInt(3)));
            break;
        }
    }
    drop(st);
    env.stop().await;
}

// ---------- C. custom blocks (ADR 0040 §3) ----------

fn port(name: &str, key: &str, to: Value, more: &[(&str, Value)]) -> Value {
    let mut kv = vec![("name", s(name)), (key, to)];
    kv.extend(more.iter().cloned());
    map(&kv)
}

/// `(a + b) / k`, with `k` a field whose default is 2.
fn mean_block() -> Value {
    map(&[
        ("description", s("The mean of two values.")),
        (
            "inputs",
            arr(&[
                port("a", "to", arr(&[s("sum.in.0")]), &[]),
                port("b", "to", s("sum.in.1"), &[]),
                port(
                    "k",
                    "to",
                    arr(&[s("div.in.1")]),
                    &[("default", Value::UInt(2))],
                ),
            ]),
        ),
        ("outputs", arr(&[port("out", "from", s("div.out"), &[])])),
        (
            "nodes",
            map(&[("sum", node("add", &[])), ("div", node("divide", &[]))]),
        ),
        ("edges", arr(&[edge("sum.out", "div.in.0")])),
        (
            "layout",
            map(&[("sum", arr(&[Value::UInt(1), Value::UInt(2)]))]),
        ),
    ])
}

fn with_blocks(mut d: Value, blocks: &[(&str, Value)]) -> Value {
    if let Value::Map(m) = &mut d {
        m.insert("blocks".into(), map(blocks));
    }
    d
}

fn mean_flow() -> Value {
    with_blocks(
        flow(
            "cb",
            &[
                ("x", node("number", &[("value", Value::UInt(4))])),
                ("y", node("number", &[("value", Value::UInt(8))])),
                ("m1", node("block:mean", &[])),
                (
                    "m2",
                    node("block:mean", &[("values", map(&[("k", Value::UInt(4))]))]),
                ),
                ("r1", publish("r1")),
                ("r2", publish("r2")),
                ("a1", publish("a1")),
            ],
            &[
                ("x.out", "m1.a"),
                ("y.out", "m1.b"),
                ("x.out", "m2.a"),
                ("y.out", "m2.b"),
                ("m1.out", "r1.in"),
                ("m2.out", "r2.in"),
                // an input of an instance is an output of its name too
                ("m1.a", "a1.in"),
            ],
        ),
        &[("mean", mean_block())],
    )
}

#[test]
fn a_custom_block_is_replaced_by_its_inner_nodes() {
    let (d, _) = def::compile(&mean_flow()).unwrap();
    let ids: Vec<&str> = d.nodes.keys().map(String::as_str).collect();
    assert_eq!(
        ids,
        ["a1", "m1/div", "m1/sum", "m2/div", "m2/sum", "r1", "r2", "x", "y"]
    );
    assert_eq!(d.instances.get("m1").map(String::as_str), Some("mean"));
    // the input's constant is the inner input's constant: the default, or the instance's
    let k = |id: &str| at(&Value::Map(d.nodes[id].cfg.clone()), &["values", "in.1"]).cloned();
    assert_eq!(k("m1/div"), Some(Value::UInt(2)));
    assert_eq!(k("m2/div"), Some(Value::UInt(4)));
    let has = |from: &str, to: &str| {
        d.edges.iter().any(|e| {
            format!("{}.{}", e.from.node, e.from.port) == from
                && format!("{}.{}", e.to.node, e.to.port) == to
        })
    };
    assert!(has("x.out", "m1/sum.in.0") && has("y.out", "m2/sum.in.1"));
    assert!(has("m1/sum.out", "m1/div.in.0") && has("m1/div.out", "r1.in"));
    assert!(
        has("m1/sum.in.0", "a1.in"),
        "an input's echo: {:?}",
        d.edges
    );
    // an instance with other values is another node config; the same one keeps its hash
    assert_ne!(d.nodes["m1/div"].hash, d.nodes["m2/div"].hash);
    assert_eq!(d.nodes["m1/sum"].hash, d.nodes["m2/sum"].hash);
}

#[test]
fn custom_block_errors_name_their_place() {
    let bad = |d: Value| def::compile(&d).unwrap_err().0;
    let one = |blocks: &[(&str, Value)], nodes: &[(&str, Value)], edges: &[(&str, &str)]| {
        with_blocks(flow("f", nodes, edges), blocks)
    };
    let inst = [("m", node("block:mean", &[]))];
    // a block the definition does not have
    let e = bad(one(&[], &inst, &[]));
    assert!(e.contains("nodes.m.type: unknown custom block mean"), "{e}");
    // an instance takes `values` only, for inputs the block has
    let e = bad(one(
        &[("mean", mean_block())],
        &[("m", node("block:mean", &[("k", Value::UInt(1))]))],
        &[],
    ));
    assert!(e.contains("nodes.m.k: unknown field"), "{e}");
    let e = bad(one(
        &[("mean", mean_block())],
        &[(
            "m",
            node("block:mean", &[("values", map(&[("z", Value::UInt(1))]))]),
        )],
        &[],
    ));
    assert!(e.contains("nodes.m.values.z: mean has no input z"), "{e}");
    // edges to ports an instance does not have
    let e = bad(one(
        &[("mean", mean_block())],
        &[("m", node("block:mean", &[])), ("x", node("number", &[]))],
        &[("x.out", "m.nope")],
    ));
    assert!(e.contains("edges[0]: m (mean) has no input nope"), "{e}");
    let e = bad(one(
        &[("mean", mean_block())],
        &[("m", node("block:mean", &[])), ("x", node("number", &[]))],
        &[("m.nope", "x.in")],
    ));
    assert!(e.contains("edges[0]: m (mean) has no output nope"), "{e}");
    // the shape of a block
    let shape = |kv: &[(&str, Value)]| bad(one(&[("b", map(kv))], &[], &[]));
    assert!(shape(&[("ports", arr(&[]))]).contains("blocks.b.ports: unknown field"));
    let e = shape(&[
        ("nodes", map(&[("n", node("not", &[]))])),
        ("inputs", arr(&[port("a", "to", s("gone.in"), &[])])),
    ]);
    assert!(
        e.contains("blocks.b.inputs[0].to: b has no inner node gone"),
        "{e}"
    );
    let e = shape(&[
        ("nodes", map(&[("n", node("not", &[]))])),
        ("outputs", arr(&[port("o", "from", s("gone.out"), &[])])),
    ]);
    assert!(e.contains("blocks.b.outputs[0].from"), "{e}");
    let e = shape(&[
        ("nodes", map(&[("n", node("not", &[]))])),
        (
            "inputs",
            arr(&[
                port("a", "to", s("n.in"), &[]),
                port("a", "to", s("n.in"), &[]),
            ]),
        ),
    ]);
    assert!(e.contains("blocks.b.inputs[1].name: a twice"), "{e}");
    let e = shape(&[
        ("nodes", map(&[("n", node("not", &[]))])),
        ("inputs", arr(&[port("a", "to", s("n.in"), &[])])),
        ("outputs", arr(&[port("a", "from", s("n.out"), &[])])),
    ]);
    assert!(e.contains("a is an input"), "{e}");
    let e = shape(&[
        ("nodes", map(&[("n", node("not", &[]))])),
        ("edges", arr(&[edge("n.out", "gone.in")])),
    ]);
    assert!(
        e.contains("blocks.b.edges[0]: b has no inner node gone"),
        "{e}"
    );
    assert!(bad(one(&[("b-1", map(&[]))], &[], &[])).contains("blocks.b-1: a block's name"));
    // an inner edge to a port that is not there is found where the block is used
    let broken = map(&[
        (
            "nodes",
            map(&[("n", node("not", &[])), ("o", node("not", &[]))]),
        ),
        ("edges", arr(&[edge("n.nope", "o.in")])),
    ]);
    let e = bad(one(&[("b", broken)], &[("u", node("block:b", &[]))], &[]));
    assert!(
        e.contains("blocks.b.edges[0] in u: u/n has no output nope"),
        "{e}"
    );
    // a constant on an inner input that takes none
    let gate = map(&[
        (
            "nodes",
            map(&[("f", node("filter", &[("expr", s("v > 1"))]))]),
        ),
        (
            "inputs",
            arr(&[port("x", "to", s("f.in"), &[("default", Value::UInt(1))])]),
        ),
    ]);
    let e = bad(one(&[("g", gate)], &[("u", node("block:g", &[]))], &[]));
    assert!(
        e.contains("nodes.u.values.x: f.in takes no constant"),
        "{e}"
    );
    // a publish inside a block has one name: the block can be used once
    let pubs = map(&[("nodes", map(&[("p", publish("same"))]))]);
    def::compile(&one(
        &[("p", pubs.clone())],
        &[("u", node("block:p", &[]))],
        &[],
    ))
    .unwrap();
    let e = bad(one(
        &[("p", pubs)],
        &[("u", node("block:p", &[])), ("v", node("block:p", &[]))],
        &[],
    ));
    assert!(e.contains("same is published by"), "{e}");
    // ids: a `/` is the engine's, not the author's
    let e = bad(flow("f", &[("a/b", node("not", &[]))], &[]));
    assert!(e.contains("nodes.a/b: id must be"), "{e}");
}

#[test]
fn custom_blocks_nest_four_deep_and_stay_within_the_node_limit() {
    // b1 holds a `not`; b<n> holds one b<n-1>
    let chain = |depth: usize| -> Vec<(String, Value)> {
        let mut blocks = vec![(
            "b1".to_owned(),
            map(&[
                ("nodes", map(&[("n", node("not", &[]))])),
                ("inputs", arr(&[port("x", "to", s("n.in"), &[])])),
                ("outputs", arr(&[port("y", "from", s("n.out"), &[])])),
            ]),
        )];
        for i in 2..=depth {
            blocks.push((
                format!("b{i}"),
                map(&[
                    (
                        "nodes",
                        map(&[("i", node(&format!("block:b{}", i - 1), &[]))]),
                    ),
                    ("inputs", arr(&[port("x", "to", s("i.x"), &[])])),
                    ("outputs", arr(&[port("y", "from", s("i.y"), &[])])),
                ]),
            ));
        }
        blocks
    };
    let using = |depth: usize, top: &str| {
        let blocks = chain(depth);
        let blocks: Vec<(&str, Value)> = blocks
            .iter()
            .map(|(n, v)| (n.as_str(), v.clone()))
            .collect();
        with_blocks(
            flow(
                "f",
                &[
                    ("v", node("bool", &[])),
                    ("u", node(top, &[])),
                    ("o", node("not", &[])),
                ],
                &[("v.out", "u.x"), ("u.y", "o.in")],
            ),
            &blocks,
        )
    };
    let (d, _) = def::compile(&using(4, "block:b4")).unwrap();
    assert!(d.nodes.contains_key("u/i/i/i/n"), "{:?}", d.nodes.keys());
    // the edges go through every level to the one plain node
    assert!(d
        .edges
        .iter()
        .any(|e| e.from.node == "v" && e.to.node == "u/i/i/i/n" && e.to.port == "in"));
    assert!(d
        .edges
        .iter()
        .any(|e| e.from.node == "u/i/i/i/n" && e.to.node == "o"));
    let e = def::compile(&using(5, "block:b5")).unwrap_err();
    assert!(e.0.contains("custom blocks nest at most 4 deep"), "{e}");
    // a block that holds itself
    let own = map(&[("nodes", map(&[("me", node("block:r", &[]))]))]);
    let e = def::compile(&with_blocks(
        flow("f", &[("u", node("block:r", &[]))], &[]),
        &[("r", own)],
    ))
    .unwrap_err();
    assert!(
        e.0.contains("blocks.r: a custom block may not contain itself (r → r)"),
        "{e}"
    );
    // through another block: found on the definitions, before anything is expanded
    let a = map(&[("nodes", map(&[("x", node("block:b", &[]))]))]);
    let b = map(&[("nodes", map(&[("y", node("block:a", &[]))]))]);
    let e = def::compile(&with_blocks(flow("f", &[], &[]), &[("a", a), ("b", b)])).unwrap_err();
    assert!(e.0.contains("may not contain itself (a → b → a)"), "{e}");
    // 40 nodes in a block, 26 instances: more than 1000 nodes
    let many: Vec<(String, Value)> = (0..40)
        .map(|i| (format!("n{i}"), node("not", &[])))
        .collect();
    let many: Vec<(&str, Value)> = many.iter().map(|(n, v)| (n.as_str(), v.clone())).collect();
    let big = map(&[("nodes", map(&many))]);
    let uses: Vec<(String, Value)> = (0..26)
        .map(|i| (format!("u{i}"), node("block:big", &[])))
        .collect();
    let uses: Vec<(&str, Value)> = uses.iter().map(|(n, v)| (n.as_str(), v.clone())).collect();
    let e = def::compile(&with_blocks(flow("f", &uses, &[]), &[("big", big)])).unwrap_err();
    assert!(e.0.contains("more than 1000 nodes"), "{e}");
}

#[tokio::test(flavor = "multi_thread")]
async fn a_flow_with_a_custom_block_runs_and_shows_its_inside() {
    let env = Env::start("custom").await;
    env.deploy(mean_flow()).await.unwrap();
    // (4 + 8) / 2 and (4 + 8) / 4
    wait("both instances", || {
        (env.last("cb/nodes/r1")?.v.as_f64() == Some(6.0)
            && env.last("cb/nodes/r2")?.v.as_f64() == Some(3.0))
        .then_some(())
    })
    .await;
    wait("the input's echo", || {
        env.last("cb/nodes/a1")
            .filter(|s| s.v.as_f64() == Some(4.0))
    })
    .await;
    // `ports` of the instance: its inner nodes under `<instance>/<inner>`
    let fl = format!("wy/{SITE}/dataflows/cb");
    let row = env
        .client
        .invoke_one(&fl, "ports", map(&[("nodes", arr(&[s("m2")]))]))
        .await
        .unwrap()
        .unwrap();
    let Some(Value::Map(nodes)) = at(&row, &["nodes"]) else {
        panic!("{row:?}")
    };
    assert_eq!(nodes.keys().collect::<Vec<_>>(), ["m2/div", "m2/sum"]);
    // the constant of the instance's field shows as the inner input's value
    assert_eq!(
        at(&row, &["nodes", "m2/div", "in", "in.1"]),
        Some(&arr(&[Value::UInt(4), Value::UInt(0)]))
    );
    assert_eq!(
        at(&row, &["nodes", "m2/div", "out", "out"]),
        Some(&arr(&[Value::Float(3.0), Value::UInt(0)]))
    );
    // one inner node alone, and a preview of the same draft
    let one = env
        .client
        .invoke_one(&fl, "ports", map(&[("nodes", arr(&[s("m1/sum")]))]))
        .await
        .unwrap()
        .unwrap();
    assert!(
        at(&one, &["nodes", "m1/sum", "out", "out"]).is_some(),
        "{one:?}"
    );
    let first = first(
        &env.client,
        &format!("wy/{SITE}/dataflows"),
        "preview",
        map(&[("def", mean_flow())]),
    )
    .await
    .unwrap();
    assert_eq!(
        at(&first, &["nodes", "m1/div", "out", "out"]),
        Some(&arr(&[Value::Float(6.0), Value::UInt(0)]))
    );
    // the stored definition is the one that was sent: the blocks are still in it
    let hist = env
        .client
        .invoke_one(&fl, "history", map(&[]))
        .await
        .unwrap()
        .unwrap();
    let Value::Array(defs) = hist else { panic!() };
    assert!(at(&defs[0], &["blocks", "mean", "inputs"]).is_some());
    assert_eq!(
        at(&defs[0], &["nodes", "m1", "type"]),
        Some(&s("block:mean"))
    );
    env.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn the_library_keeps_custom_blocks_for_every_flow() {
    let env = Env::start("library").await;
    let root = format!("wy/{SITE}/dataflows");
    let put = |c: WyrmClient, name: &'static str, def: Value| {
        let root = root.clone();
        async move {
            c.invoke_one(&root, "put_block", map(&[("name", s(name)), ("def", def)]))
                .await
        }
    };
    let r = put(env.client.clone(), "mean", mean_block())
        .await
        .unwrap()
        .unwrap();
    assert_eq!(at(&r, &["version"]), Some(&Value::UInt(1)));
    let r = put(env.client.clone(), "mean", mean_block())
        .await
        .unwrap()
        .unwrap();
    assert_eq!(
        at(&r, &["version"]),
        Some(&Value::UInt(2)),
        "each put is a version"
    );
    // a block that uses a library block; one that uses a block nobody has
    let twice = map(&[
        ("nodes", map(&[("m", node("block:mean", &[]))])),
        ("inputs", arr(&[port("a", "to", s("m.a"), &[])])),
        ("outputs", arr(&[port("out", "from", s("m.out"), &[])])),
    ]);
    put(env.client.clone(), "twice", twice).await.unwrap();
    let orphan = map(&[("nodes", map(&[("m", node("block:gone", &[]))]))]);
    let e = put(env.client.clone(), "orphan", orphan).await.unwrap_err();
    assert_eq!(status(&e), StatusCode::Known(Status::InvalidParameter));
    assert!(e.message.contains("gone"), "{e}");
    // a block that does not compile is refused with the compiler's message
    let broken = map(&[("nodes", map(&[("n", node("nope", &[]))]))]);
    let e = put(env.client.clone(), "broken", broken).await.unwrap_err();
    assert!(e.message.contains("unknown node type nope"), "{e}");
    let e = put(env.client.clone(), "bad-name", mean_block())
        .await
        .unwrap_err();
    assert_eq!(status(&e), StatusCode::Known(Status::InvalidParameter));
    // list and get: read is enough; get brings the blocks it uses
    let viewer = env.user("user:viewer", &[("dataflows/**", Perm::Read)]);
    let list = viewer
        .invoke_one(&root, "list_blocks", map(&[]))
        .await
        .unwrap()
        .unwrap();
    let Value::Array(rows) = &list else {
        panic!("{list:?}")
    };
    assert_eq!(rows.len(), 2);
    assert_eq!(at(&rows[0], &["name"]), Some(&s("mean")));
    assert_eq!(
        at(&rows[0], &["inputs"]),
        Some(&arr(&[s("a"), s("b"), s("k")]))
    );
    assert_eq!(at(&rows[0], &["outputs"]), Some(&arr(&[s("out")])));
    assert_eq!(
        at(&rows[0], &["description"]),
        Some(&s("The mean of two values."))
    );
    let got = viewer
        .invoke_one(&root, "get_block", map(&[("name", s("twice"))]))
        .await
        .unwrap()
        .unwrap();
    assert_eq!(at(&got, &["version"]), Some(&Value::UInt(1)));
    assert_eq!(at(&got, &["requires", "mean"]), Some(&mean_block()));
    // an editor copies it into the definition it deploys: the flow is self-contained
    let mut blocks = vec![("twice", at(&got, &["def"]).unwrap().clone())];
    if let Some(Value::Map(req)) = at(&got, &["requires"]) {
        for (n, d) in req {
            blocks.push((n.as_str(), d.clone()));
        }
    }
    let d = with_blocks(
        flow(
            "lib",
            &[
                ("x", node("number", &[("value", Value::UInt(10))])),
                ("t", node("block:twice", &[])),
                ("r", publish("r")),
            ],
            &[("x.out", "t.a"), ("t.out", "r.in")],
        ),
        &blocks,
    );
    env.deploy(d).await.unwrap();
    wait("the library block ran", || {
        env.last("lib/nodes/r")
            .filter(|s| s.v.as_f64() == Some(5.0))
    })
    .await;
    // writing needs config
    let e = put(viewer.clone(), "mine", mean_block()).await.unwrap_err();
    assert!(denied(&e), "{e}");
    let e = viewer
        .invoke_one(&root, "remove_block", map(&[("name", s("mean"))]))
        .await
        .unwrap_err();
    assert!(denied(&e), "{e}");
    // remove: the deployed flow keeps its copy
    env.client
        .invoke_one(&root, "remove_block", map(&[("name", s("mean"))]))
        .await
        .unwrap();
    let e = env
        .client
        .invoke_one(&root, "get_block", map(&[("name", s("mean"))]))
        .await
        .unwrap_err();
    assert_eq!(status(&e), StatusCode::Known(Status::NotFound));
    let e = env
        .client
        .invoke_one(&root, "remove_block", map(&[("name", s("mean"))]))
        .await
        .unwrap_err();
    assert_eq!(status(&e), StatusCode::Known(Status::NotFound));
    assert!(env.last("lib/nodes/r").is_some());
    env.stop().await;
}

/// Security review 2026-11-09: a definition is compiled for `validate` and `preview` at level
/// `read`, so the expansion of custom blocks is charged against the limits while it is made.
/// A block that multiplies is refused after bounded work, whatever its shape.
#[test]
fn expansion_bombs_are_refused_quickly() {
    let quick = |what: &str, d: &Value, why: &str| {
        let t = std::time::Instant::now();
        let e = def::compile(d).unwrap_err();
        let took = t.elapsed();
        assert!(e.0.contains(why), "{what}: {e}");
        assert!(took < Duration::from_millis(50), "{what}: {took:?}");
    };
    // a fan-out bomb, 4 deep: each block holds 64 instances of the one below (64⁴ nodes)
    let mut blocks = vec![(
        "b1".to_owned(),
        map(&[("nodes", map(&[("n", node("not", &[]))]))]),
    )];
    for i in 2..=4 {
        let inner: Vec<(String, Value)> = (0..64)
            .map(|k| (format!("i{k}"), node(&format!("block:b{}", i - 1), &[])))
            .collect();
        let inner: Vec<(&str, Value)> =
            inner.iter().map(|(n, v)| (n.as_str(), v.clone())).collect();
        blocks.push((format!("b{i}"), map(&[("nodes", map(&inner))])));
    }
    let blocks: Vec<(&str, Value)> = blocks
        .iter()
        .map(|(n, v)| (n.as_str(), v.clone()))
        .collect();
    let bomb = with_blocks(flow("f", &[("u", node("block:b4", &[]))], &[]), &blocks);
    quick("instances in instances", &bomb, "more than 1000 nodes");
    // instances alone count too: blocks that hold nothing but instances
    let hollow: Vec<(String, Value)> = (2..=4)
        .map(|i| {
            let inner: Vec<(String, Value)> = (0..64)
                .map(|k| (format!("i{k}"), node(&format!("block:h{}", i - 1), &[])))
                .collect();
            let inner: Vec<(&str, Value)> =
                inner.iter().map(|(n, v)| (n.as_str(), v.clone())).collect();
            (format!("h{i}"), map(&[("nodes", map(&inner))]))
        })
        .chain([("h1".to_owned(), map(&[]))])
        .collect();
    let hollow: Vec<(&str, Value)> = hollow
        .iter()
        .map(|(n, v)| (n.as_str(), v.clone()))
        .collect();
    let bomb = with_blocks(flow("f", &[("u", node("block:h4", &[]))], &[]), &hollow);
    quick("hollow instances", &bomb, "more than 1000 nodes");
    // an edge bomb: one input feeds 16 inner inputs at each of 4 levels (16⁴ edges per wire)
    let to16 =
        |target: &dyn Fn(usize) -> String| arr(&(0..16).map(|k| s(&target(k))).collect::<Vec<_>>());
    let mut fan = vec![(
        "e1".to_owned(),
        map(&[
            (
                "nodes",
                map(&[(
                    "h",
                    node(
                        "hub",
                        &[(
                            "inputs",
                            arr(&(0..16).map(|k| s(&format!("p{k}"))).collect::<Vec<_>>()),
                        )],
                    ),
                )]),
            ),
            (
                "inputs",
                arr(&[port("x", "to", to16(&|k| format!("h.in.p{k}")), &[])]),
            ),
        ]),
    )];
    for i in 2..=4 {
        fan.push((
            format!("e{i}"),
            map(&[
                (
                    "nodes",
                    map(&[("i", node(&format!("block:e{}", i - 1), &[]))]),
                ),
                (
                    "inputs",
                    arr(&[port("x", "to", to16(&|_| "i.x".to_owned()), &[])]),
                ),
            ]),
        ));
    }
    let fan: Vec<(&str, Value)> = fan.iter().map(|(n, v)| (n.as_str(), v.clone())).collect();
    let bomb = with_blocks(
        flow(
            "f",
            &[("v", node("number", &[])), ("u", node("block:e4", &[]))],
            &[("v.out", "u.x")],
        ),
        &fan,
    );
    quick(
        "an input that fans out at every level",
        &bomb,
        "more than 4000 edges",
    );
    // more than 64 instances inside one block, and too many plain edges
    let inner: Vec<(String, Value)> = (0..65)
        .map(|k| (format!("i{k}"), node("block:b1", &[])))
        .collect();
    let inner: Vec<(&str, Value)> = inner.iter().map(|(n, v)| (n.as_str(), v.clone())).collect();
    let wide = with_blocks(
        flow("f", &[], &[]),
        &[
            ("b1", map(&[("nodes", map(&[("n", node("not", &[]))]))])),
            ("wide", map(&[("nodes", map(&inner))])),
        ],
    );
    quick(
        "too many instances in a block",
        &wide,
        "65 instances of custom blocks > 64",
    );
}

/// The worst definition the limits allow still compiles in bounded time (ADR 0040 §3): 1000
/// nodes, all inside custom blocks 4 deep, and 4000 edges.
#[test]
fn the_largest_definition_compiles_in_bounded_time() {
    // b1: 12 plain nodes in a chain; b2..b4 hold 4 instances each and wire them in a chain
    let n1: Vec<(String, Value)> = (0..12)
        .map(|k| (format!("n{k}"), node("add", &[])))
        .collect();
    let n1: Vec<(&str, Value)> = n1.iter().map(|(n, v)| (n.as_str(), v.clone())).collect();
    let e1: Vec<Value> = (0..11)
        .flat_map(|k| {
            [
                edge(&format!("n{k}.out"), &format!("n{}.in.0", k + 1)),
                edge(&format!("n{k}.out"), &format!("n{}.in.1", k + 1)),
            ]
        })
        .collect();
    let mut blocks = vec![(
        "b1".to_owned(),
        map(&[
            ("nodes", map(&n1)),
            ("edges", arr(&e1)),
            (
                "inputs",
                arr(&[port("x", "to", arr(&[s("n0.in.0"), s("n0.in.1")]), &[])]),
            ),
            ("outputs", arr(&[port("y", "from", s("n11.out"), &[])])),
        ]),
    )];
    for i in 2..=4 {
        let inner: Vec<(String, Value)> = (0..4)
            .map(|k| (format!("i{k}"), node(&format!("block:b{}", i - 1), &[])))
            .collect();
        let inner: Vec<(&str, Value)> =
            inner.iter().map(|(n, v)| (n.as_str(), v.clone())).collect();
        let wires: Vec<Value> = (0..3)
            .map(|k| edge(&format!("i{k}.y"), &format!("i{}.x", k + 1)))
            .collect();
        blocks.push((
            format!("b{i}"),
            map(&[
                ("nodes", map(&inner)),
                ("edges", arr(&wires)),
                ("inputs", arr(&[port("x", "to", s("i0.x"), &[])])),
                ("outputs", arr(&[port("y", "from", s("i3.y"), &[])])),
            ]),
        ));
    }
    let blocks: Vec<(&str, Value)> = blocks
        .iter()
        .map(|(n, v)| (n.as_str(), v.clone()))
        .collect();
    // one b4 is 64 × 12 = 768 nodes and 85 instances; plain nodes fill the rest
    let mut nodes = vec![
        ("v".to_owned(), node("number", &[])),
        ("u".to_owned(), node("block:b4", &[])),
    ];
    nodes.extend((0..140).map(|k| (format!("p{k}"), node("add", &[]))));
    let nodes: Vec<(&str, Value)> = nodes.iter().map(|(n, v)| (n.as_str(), v.clone())).collect();
    let mut edges = vec![("v.out".to_owned(), "u.x".to_owned())];
    edges.extend((0..140).flat_map(|k| {
        [
            ("u.y".to_owned(), format!("p{k}.in.0")),
            ("v.out".to_owned(), format!("p{k}.in.1")),
        ]
    }));
    let edges: Vec<(&str, &str)> = edges
        .iter()
        .map(|(a, b)| (a.as_str(), b.as_str()))
        .collect();
    let d = with_blocks(flow("f", &nodes, &edges), &blocks);
    let t = std::time::Instant::now();
    let parsed = def::parse(&d).unwrap();
    let parse_took = t.elapsed();
    def::check(&parsed).unwrap();
    println!("parse {parse_took:?}, check {:?}", t.elapsed() - parse_took);
    let t = std::time::Instant::now();
    let (def, _) = def::compile(&d).unwrap();
    let took = t.elapsed();
    assert_eq!(def.nodes.len(), 768 + 141);
    assert!(def.nodes.len() + def.instances.len() <= 1000);
    assert!(def.edges.len() > 1500, "{}", def.edges.len());
    println!(
        "compile of {} nodes, {} edges: {took:?}",
        def.nodes.len(),
        def.edges.len()
    );
    // measured 2026-11-09 (Apple M4 Max): 12 ms in a debug build, 2.6 ms in release
    assert!(took < Duration::from_millis(250), "{took:?}");
}

// ---------- D. the readers (ADR 0040 §4) ----------

fn readers() -> Value {
    flow(
        "rd",
        &[
            // a static read at the start, then every 150 ms
            (
                "lv",
                node(
                    "load_value",
                    &[
                        ("key", s("downstream/mock/p0")),
                        ("interval_ms", Value::UInt(150)),
                    ],
                ),
            ),
            // the children of the link, once at the start
            (
                "ls",
                node("list_children", &[("path", s("downstream/mock"))]),
            ),
            // a key from a port: p1, then a point that is not there, then one outside the scope
            ("t", node("timer", &[("period_ms", Value::UInt(400))])),
            ("m3", node("modulo", &[("modulo", Value::UInt(3))])),
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
                                ("in.k0", s("downstream/mock/p1")),
                                ("in.c1", Value::UInt(2)),
                                ("in.k1", s("downstream/mock/nope")),
                            ]),
                        ),
                        ("else", s("downstream/other/p0")),
                    ],
                ),
            ),
            (
                "dyn",
                node("load_value", &[("key_scope", s("downstream/mock/*"))]),
            ),
            ("v", publish("v")),
            ("ok", publish("ok")),
            ("lerr", publish("lerr")),
            ("rows", publish("rows")),
            ("dv", publish("dv")),
            ("dk", publish("dk")),
            ("derr", publish("derr")),
        ],
        &[
            ("lv.out", "v.in"),
            ("lv.ok", "ok.in"),
            ("lv.error", "lerr.in"),
            ("ls.out", "rows.in"),
            ("t.out", "m3.in"),
            ("m3.remainder", "pick.in"),
            ("pick.out", "dyn.in.key"),
            ("dyn.out", "dv.in"),
            ("dyn.key", "dk.in"),
            ("dyn.error", "derr.in"),
        ],
    )
}

#[tokio::test(flavor = "multi_thread")]
async fn load_value_and_list_children_read_inside_their_scope() {
    let env = Env::start("readers").await;
    env.deploy(readers()).await.unwrap();
    // The static read runs at the start and again every period. This in-memory session has
    // no storage of values (wyrmd has one; its e2e test reads a value), so each read answers
    // `not_found`: an `error` event per read, and never `ok`.
    let err = wait("periodic reads", || {
        env.last("rd/nodes/lerr").filter(|s| ev_id(s) >= Some(4))
    })
    .await;
    assert_eq!(
        at(&err.v, &["code"]),
        Some(&Value::UInt(u64::from(Status::NotFound.code())))
    );
    assert!(env.last("rd/nodes/ok").is_none() && env.last("rd/nodes/v").is_none());
    // the children of the mock: its two points, each a row
    let rows = wait("the rows", || {
        env.last("rd/nodes/rows").and_then(|s| match s.v {
            Value::Array(a) => Some(a),
            _ => None,
        })
    })
    .await;
    assert_eq!(rows.len(), 2, "{rows:?}");
    assert_eq!(at(&rows[0], &["name"]), Some(&s("p0")));
    assert_eq!(at(&rows[0], &["path"]), Some(&s("downstream/mock/p0")));
    assert_eq!(at(&rows[0], &["type"]), Some(&s("number")));
    assert_eq!(at(&rows[0], &["unit"]), Some(&s("°C")));
    assert_eq!(at(&rows[0], &["writable"]), Some(&Value::Bool(true)));
    assert_eq!(at(&rows[1], &["name"]), Some(&s("p1")));
    // the key from the port: p1 is read
    wait("the dynamic key is taken", || {
        env.last("rd/nodes/dk")
            .filter(|k| k.v == s("downstream/mock/p1"))
    })
    .await;
    // a point that is not there: not_found; a key outside the scope: invalid_parameter
    let mut codes = std::collections::BTreeSet::new();
    wait("both errors", || {
        if let Some(Value::UInt(c)) = env
            .last("rd/nodes/derr")
            .and_then(|s| at(&s.v, &["code"]).cloned())
        {
            codes.insert(c);
        }
        (codes.len() == 2).then_some(())
    })
    .await;
    assert!(
        codes.contains(&u64::from(Status::NotFound.code())),
        "{codes:?}"
    );
    assert!(
        codes.contains(&u64::from(Status::InvalidParameter.code())),
        "{codes:?}"
    );
    env.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn a_reader_is_a_source_for_the_rights_checks() {
    let env = Env::start("reader-rights").await;
    // a wired path needs its scope
    let wired = |scope: Option<&str>| {
        let mut cfg = vec![("path", s("downstream/mock"))];
        if let Some(sc) = scope {
            cfg.push(("path_scope", s(sc)));
        }
        flow(
            "ls",
            &[
                ("k", node("string", &[])),
                ("l", node("list_children", &cfg)),
            ],
            &[("k.out", "l.in.path")],
        )
    };
    let e = def::compile(&wired(None)).unwrap_err();
    assert!(
        e.0.contains("nodes.l.path_scope: required when in.path is wired"),
        "{e}"
    );
    // a reader outside the site's sections does not compile (as a subscribe)
    let e = env
        .deploy(flow(
            "x",
            &[("l", node("load_value", &[("key", s("sys/audit"))]))],
            &[],
        ))
        .await
        .unwrap_err();
    assert!(e.message.contains("nodes.l.key"), "{e}");
    let e = env.deploy(wired(Some("sys/**"))).await.unwrap_err();
    assert!(e.message.contains("nodes.l.path_scope"), "{e}");
    // the deployer reads the static path and all of the scope
    let narrow = env.user(
        "user:narrow",
        &[
            ("dataflows/**", Perm::Config),
            ("downstream/mock", Perm::Read),
        ],
    );
    let e = env
        .deploy_as(&narrow, wired(Some("downstream/**")))
        .await
        .unwrap_err();
    assert!(denied(&e), "{e}");
    let wide = env.user(
        "user:wide",
        &[
            ("dataflows/**", Perm::Config),
            ("downstream/**", Perm::Read),
        ],
    );
    env.deploy_as(&wide, wired(Some("downstream/**")))
        .await
        .unwrap();
    // and so does whoever watches it
    let e = first(
        &narrow,
        &format!("wy/{SITE}/dataflows/ls"),
        "ports",
        map(&[]),
    )
    .await
    .unwrap_err();
    assert!(denied(&e), "{e}");
    env.stop().await;
}
