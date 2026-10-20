//! Host-side `LinkConfig` options: `open_actions`, `root`, `republish_on`.

use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;
use std::time::Duration;
use wyrm_core::{ActionMeta, NodeMeta, Perm, Quality, Sample, Status, Value};
use wyrm_link_sdk::{Caller, Link, LinkCtx, ReplySink, TestHarness};

type Calls = Arc<AtomicUsize>;

struct Host {
    calls: Calls,
}

impl Link for Host {
    const NAME: &'static str = "host";
    const VERSION: &'static str = "0.1.0";
    type Config = Calls;

    async fn start(calls: Calls, ctx: LinkCtx) -> wyrm_link_sdk::Result<Self> {
        ctx.declare_node("n", NodeMeta::folder()).await?;
        ctx.declare_action("n", "hello", ActionMeta::new().level(Perm::Config))
            .await?;
        // no level, node not invokable: never callable
        ctx.declare_action("n", "closed", ActionMeta::new()).await?;
        ctx.declare_node("p", NodeMeta::number()).await?;
        Ok(Self { calls })
    }

    async fn on_invoke(
        &mut self,
        _path: &str,
        _action: &str,
        _args: Value,
        _who: &Caller,
        out: ReplySink,
    ) -> wyrm_link_sdk::Result<()> {
        self.calls.fetch_add(1, Ordering::SeqCst);
        out.reply("hi").await
    }
}

fn status(a: &wyrm_core::Attachment) -> Status {
    match a.status.expect("status present") {
        wyrm_core::status::StatusCode::Known(s) => s,
        other => panic!("unexpected status {other:?}"),
    }
}

fn empty() -> Value {
    Value::Map(Default::default())
}

#[tokio::test(flavor = "multi_thread")]
async fn open_actions_skip_ptok_only_when_host_configured() {
    let calls = Calls::default();
    let h = TestHarness::<Host>::start(calls.clone()).await;
    let r = h.invoke("n", "hello", empty(), None).await;
    assert_eq!(status(&r[0].att), Status::PermissionDenied);
    assert_eq!(calls.load(Ordering::SeqCst), 0, "driver not called");
    h.stop().await;

    let calls = Calls::default();
    let h = TestHarness::<Host>::start_with(calls.clone(), |c| {
        c.open_actions = vec!["hello".into()];
    })
    .await;
    let r = h.invoke("n", "hello", empty(), None).await;
    assert_eq!(status(&r[0].att), Status::Ok);
    assert_eq!(r[0].value(), Some(Value::from("hi")));
    assert_eq!(calls.load(Ordering::SeqCst), 1);
    // declarations cannot open an action: still not invokable
    let r = h
        .invoke("n", "closed", empty(), Some(h.ptok(Perm::Config)))
        .await;
    assert_eq!(status(&r[0].att), Status::NotSupported);
    assert_eq!(calls.load(Ordering::SeqCst), 1);
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn root_override_moves_prefix_and_liveliness() {
    let h = TestHarness::<Host>::start_with(Calls::default(), |c| {
        c.root = Some("wy/test/sys".into());
    })
    .await;
    assert_eq!(h.key("", "~meta"), "wy/test/sys/~meta");
    let (att, m) = h.meta("").await;
    assert_eq!(status(&att), Status::Ok);
    assert_eq!(m.unwrap().children.unwrap(), ["n", "p"]);
    let r = h.session().liveliness().get("wy/test/**").await.unwrap();
    let mut keys = Vec::new();
    while let Ok(rep) = r.recv_async().await {
        keys.push(rep.result().unwrap().key_expr().to_string());
    }
    assert_eq!(keys, ["wy/test/sys"]);
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn republish_when_broker_token_returns() {
    let h = TestHarness::<Host>::start_with(Calls::default(), |c| {
        c.republish_on = Some("wy/test/sys/broker".into());
    })
    .await;
    h.ctx().update("p", 21.5, Quality::Good, 7).await.unwrap();
    let vals = h
        .session()
        .declare_subscriber(h.key("p", "~val"))
        .await
        .unwrap();
    let metas = h
        .session()
        .declare_subscriber(h.key("p", "~meta"))
        .await
        .unwrap();
    // the watcher's liveliness subscriber must be up before the token appears
    tokio::time::sleep(Duration::from_millis(200)).await;
    let _broker = h
        .session()
        .liveliness()
        .declare_token("wy/test/sys/broker")
        .await
        .unwrap();
    let s = tokio::time::timeout(Duration::from_secs(2), vals.recv_async())
        .await
        .expect("value re-published")
        .unwrap();
    let v: Sample = wyrm_core::codec::from_slice(&s.payload().to_bytes()).unwrap();
    assert_eq!(v.v, Value::Float(21.5));
    assert_eq!(v.t, 7, "the original sample, not a new measurement");
    let m = tokio::time::timeout(Duration::from_secs(2), metas.recv_async())
        .await
        .expect("~meta re-put")
        .unwrap();
    let meta: NodeMeta = wyrm_core::codec::from_slice(&m.payload().to_bytes()).unwrap();
    assert_eq!(meta.ty, Some(wyrm_core::TypeCode::Number));
    h.stop().await;
}
