//! A stream whose consumer stalls must never stall the client's session.
//!
//! Two sessions over TCP on loopback: the "broker" side runs the mock link
//! and a raw publisher, the client side runs `WyrmClient`. A full Zenoh
//! FIFO handler blocks the receive path of the session that owns it, so a
//! stalled stream on the client side would also stop every reply to its
//! other queries. One session would not show it: a local put calls the
//! subscriber on the publisher's own task.

use std::collections::{BTreeSet, HashMap};
use std::sync::Arc;
use std::time::{Duration, Instant};
use wyrm_client::{ListEvent, SigningTokens, ValEvent, WyrmClient};
use wyrm_core::codec::to_vec;
use wyrm_core::{NodeMeta, Quality, Sample, Status, Value};
use wyrm_link_mock::{Mock, MockConfig};
use wyrm_link_sdk::harness::{SITE, TEST_KEY_SEED};
use wyrm_link_sdk::LinkConfig;

/// A query that normally answers in milliseconds must answer within this,
/// while a stream of the same session is stalled.
const QUERY_BUDGET: Duration = Duration::from_millis(800);

fn free_port() -> u16 {
    std::net::TcpListener::bind("127.0.0.1:0")
        .unwrap()
        .local_addr()
        .unwrap()
        .port()
}

fn cfg(listen: Option<u16>, connect: Option<u16>) -> zenoh::Config {
    let mut c = zenoh::Config::default();
    let ep = |p: Option<u16>| match p {
        Some(p) => format!(r#"["tcp/127.0.0.1:{p}"]"#),
        None => "[]".to_owned(),
    };
    for (k, v) in [
        ("mode", r#""peer""#.to_owned()),
        ("listen/endpoints", ep(listen)),
        ("connect/endpoints", ep(connect)),
        ("scouting/multicast/enabled", "false".to_owned()),
        ("scouting/gossip/enabled", "false".to_owned()),
    ] {
        c.insert_json5(k, &v).unwrap();
    }
    c
}

struct Pair {
    broker: zenoh::Session,
    client: WyrmClient,
    mock: wyrm_link_sdk::LinkHandle<Mock>,
    root: String,
}

async fn pair() -> Pair {
    let port = free_port();
    let broker = zenoh::open(cfg(Some(port), None)).await.unwrap();
    let session = zenoh::open(cfg(None, Some(port))).await.unwrap();
    let key = ed25519_dalek::SigningKey::from_bytes(&TEST_KEY_SEED);
    let mut lcfg = LinkConfig::new(SITE, "mock");
    lcfg.admin_keys = vec![key.verifying_key()];
    let mock = wyrm_link_sdk::spawn::<Mock>(
        broker.clone(),
        lcfg,
        MockConfig {
            points: 4,
            rate_hz: 1.0,
            depth: 1,
            fanout: 2,
            writable: false,
        },
    )
    .await
    .unwrap();
    let client = WyrmClient::new(session)
        .with_tokens(Arc::new(SigningTokens::new(key, SITE)))
        .with_timeout(Duration::from_secs(4));
    let root = format!("wy/{SITE}/downstream/mock");
    // the TCP link and the link's queryable are up
    let until = Instant::now() + Duration::from_secs(10);
    while client.meta(&root).await.is_err() {
        assert!(Instant::now() < until, "the client never reached the mock");
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
    Pair {
        broker,
        client,
        mock,
        root,
    }
}

/// Ask `meta` of the mock every 100 ms until `stop`; the slowest answer.
async fn probe_queries(c: WyrmClient, root: String, stop: Instant) -> Duration {
    let mut worst = Duration::ZERO;
    while Instant::now() < stop {
        let t0 = Instant::now();
        let r = tokio::time::timeout(Duration::from_secs(5), c.meta(&root)).await;
        let took = t0.elapsed();
        assert!(
            matches!(r, Ok(Ok(_))),
            "meta failed while a stream was stalled after {took:?}: {r:?}"
        );
        worst = worst.max(took);
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
    eprintln!("slowest meta during the stall: {worst:?}");
    worst
}

const KEYS: u64 = 20;

fn val_key(k: u64) -> String {
    format!("wy/{SITE}/downstream/fake/p{k}/~val")
}

/// `n` rounds of one sample per key, 20 keys per 10 ms (about 2000/s).
async fn publish(broker: zenoh::Session, rounds: u64) {
    let mut tick = tokio::time::interval(Duration::from_millis(10));
    for r in 1..=rounds {
        tick.tick().await;
        for k in 0..KEYS {
            let s = Sample {
                v: Value::UInt(r),
                q: Quality::Good,
                t: r,
            };
            broker.put(val_key(k), to_vec(&s).unwrap()).await.unwrap();
        }
    }
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn a_stalled_subscription_does_not_stall_the_session() {
    let p = pair().await;
    let mut vals = p
        .client
        .subscribe(&format!("wy/{SITE}/downstream/fake/**"))
        .await
        .unwrap();
    // the subscription is not read while about 8000 samples arrive in 4 s
    let rounds = 400;
    let stop = Instant::now() + Duration::from_secs(4);
    let probe = tokio::spawn(probe_queries(p.client.clone(), p.root.clone(), stop));
    publish(p.broker.clone(), rounds).await;
    let worst = probe.await.expect("queries kept answering");
    assert!(worst < QUERY_BUDGET, "slowest meta {worst:?}");

    // after the stall: per key, time order, and the last value arrives
    let mut last: HashMap<String, u64> = HashMap::new();
    let mut got = 0usize;
    let until = Instant::now() + Duration::from_secs(10);
    while last.len() < KEYS as usize || last.values().any(|t| *t < rounds) {
        assert!(Instant::now() < until, "last values missing: {last:?}");
        let ev = tokio::time::timeout(Duration::from_secs(3), vals.next())
            .await
            .expect("an event in time")
            .expect("stream open");
        let ValEvent::Sample { key, sample, .. } = ev else {
            panic!("unexpected {ev:?}")
        };
        got += 1;
        if let Some(prev) = last.insert(key.clone(), sample.t) {
            assert!(sample.t > prev, "{key}: {} after {prev}", sample.t);
        }
    }
    // Zenoh itself may drop a few `~val` puts (congestion control Drop)
    let published = (rounds * KEYS) as usize;
    assert!(vals.dropped() > 0, "the coalesced samples are reported");
    assert!(vals.dropped() as usize + got <= published);
    // the first `VALUE_BUFFER` in order, then the newest per key
    assert!(got < published, "{got} of {published}: not coalesced");
    assert!(
        got >= wyrm_client::VALUE_BUFFER,
        "{got}: the queue was not lossless"
    );
    p.mock.stop().await;
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn a_stalled_list_resyncs_and_does_not_stall_the_session() {
    let p = pair().await;
    let node = format!("{}/g0", p.root);
    let mut list = p.client.list(&node).await.unwrap();
    // more `~meta` changes than a list stream buffers, none of them read
    let burst = 3 * wyrm_client::LIST_BUFFER;
    let stop = Instant::now() + Duration::from_secs(3);
    let probe = tokio::spawn(probe_queries(p.client.clone(), p.root.clone(), stop));
    for i in 0..burst {
        p.mock
            .ctx()
            .declare_node(&format!("g0/x{i}"), NodeMeta::number())
            .await
            .unwrap();
    }
    let worst = probe.await.expect("queries kept answering");
    assert!(worst < QUERY_BUDGET, "slowest meta {worst:?}");

    let mut want: BTreeSet<String> = ["p0", "p2"].map(str::to_owned).into();
    want.extend((0..burst).map(|i| format!("x{i}")));
    let mut have: BTreeSet<String> = BTreeSet::new();
    let mut refreshed = 0;
    let until = Instant::now() + Duration::from_secs(20);
    while have != want {
        assert!(
            Instant::now() < until,
            "{} of {} children",
            have.len(),
            want.len()
        );
        let ev = tokio::time::timeout(Duration::from_secs(5), list.next())
            .await
            .expect("an event in time")
            .expect("stream open");
        match ev {
            ListEvent::Refreshed(kids) => {
                refreshed += 1;
                have = kids.into_iter().map(|c| c.name).collect();
            }
            ListEvent::Added(c) | ListEvent::Changed(c) => {
                have.insert(c.name);
            }
            ListEvent::Removed(n) => {
                have.remove(&n);
            }
            _ => {}
        }
    }
    assert!(
        refreshed >= 2,
        "an overflow is followed by a fresh snapshot"
    );
    assert!(list.dropped() > 0, "the overflow is reported");
    p.mock.stop().await;
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn a_stalled_invoke_stream_ends_with_an_error_and_does_not_stall_the_session() {
    let p = pair().await;
    let n = 4 * wyrm_client::INVOKE_BUFFER as u64;
    let mut args = std::collections::BTreeMap::new();
    args.insert("n".to_owned(), Value::UInt(n));
    let mut s = p
        .client
        .invoke(&p.root, "count", Value::Map(args))
        .await
        .unwrap();
    // the action streams its elements; none is read for 2 s
    let stop = Instant::now() + Duration::from_secs(2);
    let worst = probe_queries(p.client.clone(), p.root.clone(), stop).await;
    assert!(worst < QUERY_BUDGET, "slowest meta {worst:?}");

    // the replies held arrive in order, then the error ends the stream
    let mut next = 0u64;
    let err = loop {
        let item = tokio::time::timeout(Duration::from_secs(3), s.next())
            .await
            .expect("an item in time")
            .expect("the stream ends with an error, not silently");
        match item {
            Ok(Some(v)) => {
                assert_eq!(v, Value::UInt(next));
                next += 1;
            }
            Ok(None) => {}
            Err(e) => break e,
        }
    };
    assert!(err.is(Status::ResourceExhausted), "{err}");
    assert!(next < n, "{next} of {n}");
    assert!(s.dropped() > 0);
    assert!(s.next().await.is_none());
    p.mock.stop().await;
}
