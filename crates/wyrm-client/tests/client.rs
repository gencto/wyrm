use std::collections::BTreeMap;
use std::sync::Arc;
use std::time::Duration;
use wyrm_client::{ListEvent, SigningTokens, ValEvent, WyrmClient};
use wyrm_core::{NodeMeta, Status, Value};
use wyrm_link_mock::{point_paths, Mock, MockConfig};
use wyrm_link_sdk::harness::{SITE, TEST_KEY_SEED};
use wyrm_link_sdk::TestHarness;

fn cfg() -> MockConfig {
    MockConfig {
        points: 6,
        rate_hz: 20.0,
        depth: 1,
        fanout: 2,
        writable: true,
    }
}

async fn setup() -> (TestHarness<Mock>, WyrmClient, String) {
    let h = TestHarness::<Mock>::start(cfg()).await;
    let key = ed25519_dalek::SigningKey::from_bytes(&TEST_KEY_SEED);
    let client = WyrmClient::new(h.session().clone())
        .with_tokens(Arc::new(SigningTokens::new(key, SITE)))
        .with_timeout(Duration::from_secs(2));
    let root = h.key("", "");
    (h, client, root)
}

async fn next<T>(s: &mut wyrm_client::EventStream<T>) -> T {
    tokio::time::timeout(Duration::from_secs(3), s.next())
        .await
        .expect("event in time")
        .expect("stream open")
}

#[tokio::test(flavor = "multi_thread")]
async fn meta_children_resolve() {
    let (h, c, root) = setup().await;
    let m = c.meta(&root).await.unwrap();
    assert_eq!(m.children.unwrap(), ["g0", "g1"]);
    let kids = c.children(&format!("{root}/g0")).await.unwrap();
    let names: Vec<_> = kids.iter().map(|k| k.name.as_str()).collect();
    assert_eq!(names, ["p0", "p2", "p4"]);
    assert!(kids
        .iter()
        .all(|k| k.meta.ty == Some(wyrm_core::TypeCode::Number)));
    let keys = c.resolve(&root, Some("type:1"), None).await.unwrap();
    assert_eq!(keys.len(), 6);
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn list_is_reactive() {
    let (h, c, root) = setup().await;
    let node = format!("{root}/g0");
    let mut s = c.list(&node).await.unwrap();
    let ListEvent::Refreshed(snap) = next(&mut s).await else {
        panic!("first event must be Refreshed")
    };
    assert_eq!(snap.len(), 3);

    h.ctx()
        .declare_node("g0/extra", NodeMeta::number())
        .await
        .unwrap();
    match next(&mut s).await {
        ListEvent::Added(child) => assert_eq!(child.name, "extra"),
        e => panic!("expected Added, got {e:?}"),
    }
    h.ctx()
        .declare_node("g0/extra", NodeMeta::number().unit("kW"))
        .await
        .unwrap();
    assert!(matches!(next(&mut s).await, ListEvent::Changed(c) if c.name == "extra"));
    h.ctx().remove_node("g0/extra").await.unwrap();
    assert_eq!(next(&mut s).await, ListEvent::Removed("extra".into()));

    h.ctx().set_dynamic("g0/p0", true).await.unwrap();
    assert_eq!(next(&mut s).await, ListEvent::Connected("p0".into()));
    h.ctx().set_dynamic("g0/p0", false).await.unwrap();
    assert_eq!(
        next(&mut s).await,
        ListEvent::Disconnected(Some("p0".into()))
    );
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn list_links_root_and_owner_disconnect() {
    let session = zenoh::open(wyrm_link_sdk::harness::isolated_config())
        .await
        .unwrap();
    let c = WyrmClient::new(session.clone()).with_timeout(Duration::from_secs(2));
    let handle = wyrm_link_sdk::spawn::<Mock>(
        session.clone(),
        wyrm_link_sdk::LinkConfig::new(SITE, "mock"),
        cfg(),
    )
    .await
    .unwrap();

    let links_root = format!("wy/{SITE}/down");
    let mut links = c.list(&links_root).await.unwrap();
    let ListEvent::Refreshed(snap) = next(&mut links).await else {
        panic!()
    };
    assert_eq!(snap.len(), 1);
    assert_eq!(snap[0].name, "mock");

    let mut inside = c.list(&format!("{links_root}/mock")).await.unwrap();
    assert!(matches!(next(&mut inside).await, ListEvent::Refreshed(_)));

    handle.stop().await;
    assert_eq!(next(&mut links).await, ListEvent::Removed("mock".into()));
    assert_eq!(next(&mut inside).await, ListEvent::Disconnected(None));

    // no responder any more: set maps to disconnected, not timeout
    let e = c
        .set(&format!("{links_root}/mock/g0/p0"), 1.0)
        .await
        .unwrap_err();
    assert!(e.is(Status::Disconnected), "{e}");
}

#[tokio::test(flavor = "multi_thread")]
async fn subscribe_set_invoke() {
    let (h, c, root) = setup().await;
    let paths = point_paths(&cfg());
    let mut vals = c.subscribe(&format!("{root}/**")).await.unwrap();
    let ValEvent::Sample { key, .. } = next(&mut vals).await else {
        panic!()
    };
    assert!(key.starts_with(&root));

    let p0 = format!("{root}/{}", paths[0]);
    c.set(&p0, 42.0).await.unwrap();
    loop {
        if let ValEvent::Sample { key, sample, .. } = next(&mut vals).await {
            if key == p0 && sample.v == Value::Float(42.0) {
                break;
            }
        }
    }

    // without tokens: denied, never reaches the driver
    let anon = WyrmClient::new(h.session().clone());
    let e = anon.set(&p0, 1.0).await.unwrap_err();
    assert!(e.is(Status::PermissionDenied));
    let e = c.set(&p0, "x").await.unwrap_err();
    assert!(e.is(Status::InvalidParameter));

    let mut args = BTreeMap::new();
    args.insert("n".to_owned(), Value::UInt(4));
    let mut s = c.invoke(&root, "count", Value::Map(args)).await.unwrap();
    let mut got = Vec::new();
    while let Some(v) = s.next().await {
        got.push(v.unwrap().unwrap());
    }
    assert_eq!(got, (0..4u64).map(Value::UInt).collect::<Vec<_>>());

    assert_eq!(
        c.invoke_one(&root, "reset", Value::Map(Default::default()))
            .await
            .unwrap(),
        None
    );
    h.stop().await;
}

/// A responder that breaks spec 04 must not look like success.
#[tokio::test(flavor = "multi_thread")]
async fn reply_without_readable_status_is_an_error() {
    let session = zenoh::open(wyrm_link_sdk::harness::isolated_config())
        .await
        .unwrap();
    let q = session
        .declare_queryable("wy/t/down/fake/**")
        .await
        .unwrap();
    tokio::spawn(async move {
        while let Ok(query) = q.recv_async().await {
            let key = query.key_expr().clone();
            let r = if key.as_str().contains("garbage") {
                query
                    .reply(key, Vec::<u8>::new())
                    .attachment(vec![0xffu8, 0x00])
                    .await
            } else {
                query.reply(key, Vec::<u8>::new()).await
            };
            r.unwrap();
        }
    });
    let c = WyrmClient::new(session).with_timeout(Duration::from_secs(2));
    let e = c.set("wy/t/down/fake/x", 1.0).await.unwrap_err();
    assert!(e.is(Status::InvalidMessage), "{e}");
    let e = c.set("wy/t/down/fake/garbage", 1.0).await.unwrap_err();
    assert!(e.is(Status::InvalidMessage), "{e}");
    let e = c
        .invoke_one("wy/t/down/fake/x", "a", Value::Map(Default::default()))
        .await
        .unwrap_err();
    assert!(e.is(Status::InvalidMessage), "{e}");
}

/// QoS 2: a late subscriber gets the publisher's cached samples.
#[tokio::test(flavor = "multi_thread")]
async fn reliable_subscribe_gets_history() {
    let (h, c, root) = setup().await;
    h.ctx()
        .declare_node(
            "g0/hist",
            NodeMeta::number().cfg("qos", 2u64).cfg("qos_cache", 3u64),
        )
        .await
        .unwrap();
    for i in 0..5u64 {
        h.ctx()
            .update("g0/hist", i as f64, wyrm_core::Quality::Good, 1 + i)
            .await
            .unwrap();
    }
    let mut s = c
        .subscribe_reliable(&format!("{root}/g0/hist"))
        .await
        .unwrap();
    let mut got = Vec::new();
    while got.len() < 3 {
        if let ValEvent::Sample { sample, .. } = next(&mut s).await {
            got.push(sample.v);
        }
    }
    assert_eq!(
        got,
        [2.0, 3.0, 4.0].map(Value::Float),
        "last 3 cached samples"
    );
    h.ctx()
        .update("g0/hist", 9.0, wyrm_core::Quality::Good, 10)
        .await
        .unwrap();
    loop {
        if let ValEvent::Sample { sample, .. } = next(&mut s).await {
            if sample.v == Value::Float(9.0) {
                break;
            }
        }
    }
    h.stop().await;
}
