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
