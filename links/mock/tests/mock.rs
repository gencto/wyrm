use std::time::Duration;
use wyrm_core::{Perm, Quality, Sample, Status, Value};
use wyrm_link_mock::{point_paths, Mock, MockConfig};
use wyrm_link_sdk::TestHarness;

fn status(a: &wyrm_core::Attachment) -> Option<Status> {
    match a.status? {
        wyrm_core::status::StatusCode::Known(s) => Some(s),
        _ => None,
    }
}

#[test]
fn layout_is_deterministic() {
    let cfg = MockConfig {
        points: 5,
        depth: 2,
        fanout: 2,
        ..Default::default()
    };
    assert_eq!(
        point_paths(&cfg),
        ["g0/g0/p0", "g0/g1/p1", "g1/g0/p2", "g1/g1/p3", "g0/g0/p4"]
    );
    let flat = MockConfig {
        points: 2,
        depth: 0,
        ..Default::default()
    };
    assert_eq!(point_paths(&flat), ["p0", "p1"]);
}

#[tokio::test(flavor = "multi_thread")]
async fn tree_and_ticks() {
    let cfg = MockConfig {
        points: 6,
        rate_hz: 50.0,
        depth: 1,
        fanout: 3,
        writable: true,
    };
    let paths = point_paths(&cfg);
    let h = TestHarness::<Mock>::start(cfg).await;
    let (_, top) = h.list("").await;
    assert_eq!(top.len(), 3);
    let (_, keys) = h.keys("", "match=type:1").await;
    assert_eq!(keys.len(), 6);

    let sub = h
        .session()
        .declare_subscriber(h.key("**", "~val"))
        .await
        .unwrap();
    let mut n = 0;
    while n < 12 {
        let s = tokio::time::timeout(Duration::from_secs(2), sub.recv_async())
            .await
            .expect("ticks arrive")
            .unwrap();
        let v: Sample = wyrm_core::codec::from_slice(&s.payload().to_bytes()).unwrap();
        assert_eq!(v.q, Quality::Good);
        n += 1;
    }

    // a written value is held by the ticker
    let p = &paths[0];
    let att = h.set(p, 99.0, Some(h.ptok(Perm::Write))).await;
    assert_eq!(status(&att), Some(Status::Ok));
    tokio::time::sleep(Duration::from_millis(100)).await;
    assert_eq!(h.ctx().last(p).unwrap().v, Value::Float(99.0));

    let mut args = std::collections::BTreeMap::new();
    args.insert("n".to_owned(), Value::UInt(5));
    let r = h
        .invoke("", "count", Value::Map(args), Some(h.ptok(Perm::Read)))
        .await;
    assert_eq!(r.len(), 6);
    assert_eq!(r[5].att.last, Some(true));
    h.stop().await;
}
