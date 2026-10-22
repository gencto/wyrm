//! The historian on an in-memory Zenoh session: logging types, flush on
//! detach, and a new session after a "rebuild".

use std::time::Duration;
use wyrm_core::{codec, Quality, Sample, Value};
use wyrm_history::{GroupCfg, Historian, Logging, WatchCfg};

const P: &str = "wy/s/down/mock/p";
const Q: &str = "wy/s/down/mock/q";
const R: &str = "wy/s/down/mock/r";

fn temp(name: &str) -> std::path::PathBuf {
    let d = std::env::temp_dir().join(format!("wyrm-hist-e-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&d);
    d
}

async fn session() -> zenoh::Session {
    zenoh::open(wyrm_link_sdk::harness::isolated_config())
        .await
        .unwrap()
}

async fn put(s: &zenoh::Session, key: &str, v: f64, t: u64) {
    let payload = codec::to_vec(&Sample {
        v: Value::Float(v),
        q: Quality::Good,
        t,
    })
    .unwrap();
    s.put(format!("{key}/~val"), payload).await.unwrap();
}

fn group(name: &str, logging: Logging, keys: &[&str]) -> GroupCfg {
    GroupCfg {
        name: name.into(),
        logging,
        interval_ms: 200,
        flush_ms: 100,
        watches: keys
            .iter()
            .enumerate()
            .map(|(i, k)| WatchCfg {
                id: format!("w{}", i + 1),
                key: (*k).into(),
                enabled: true,
            })
            .collect(),
    }
}

fn values(h: &Historian, key: &str) -> Vec<Value> {
    let st = h.store();
    let Some(s) = st.series_id(key, false).unwrap() else {
        return Vec::new();
    };
    st.read(s, 0, u64::MAX, 1000)
        .unwrap()
        .into_iter()
        .map(|r| r.v)
        .collect()
}

async fn eventually(what: &str, mut f: impl FnMut() -> bool) {
    for _ in 0..100 {
        if f() {
            return;
        }
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
    panic!("{what}");
}

#[tokio::test(flavor = "multi_thread")]
async fn logging_types_and_rebuilds() {
    let dir = temp("types");
    let h = Historian::open(&dir).unwrap();
    let s = session().await;
    h.attach(
        s.clone(),
        vec![
            group("all", Logging::AllData, &[P]),
            group("change", Logging::PointChange, &[Q]),
        ],
    );
    tokio::time::sleep(Duration::from_millis(300)).await; // subscribers up
    let t0 = wyrm_history::engine::now_us();
    for (i, v) in [1.0, 1.0, 2.0, 2.0, 3.0].into_iter().enumerate() {
        put(&s, P, v, t0 + i as u64).await;
        put(&s, Q, v, t0 + i as u64).await;
    }
    eventually("all data: every update", || values(&h, P).len() == 5).await;
    eventually("point change: changes only", || values(&h, Q).len() == 3).await;
    assert_eq!(
        values(&h, Q),
        [Value::Float(1.0), Value::Float(2.0), Value::Float(3.0)]
    );
    assert_eq!(h.last_written(P).unwrap().v, Value::Float(3.0));

    // A rebuild: detach flushes, a new session continues; an old sample
    // again (as storage would replay it) is not stored twice.
    h.detach().await;
    let s2 = session().await;
    h.attach(
        s2.clone(),
        vec![
            group("all", Logging::AllData, &[P]),
            group("change", Logging::PointChange, &[Q]),
        ],
    );
    tokio::time::sleep(Duration::from_millis(300)).await;
    put(&s2, P, 3.0, t0 + 4).await;
    put(&s2, Q, 3.0, t0 + 9).await;
    put(&s2, P, 4.0, t0 + 10).await;
    eventually("new session records", || values(&h, P).len() == 6).await;
    tokio::time::sleep(Duration::from_millis(300)).await;
    assert_eq!(values(&h, Q).len(), 3, "unchanged after the rebuild");

    // Reconfigure: interval logging samples the last value.
    h.configure(vec![group("all", Logging::Interval, &[P])]);
    tokio::time::sleep(Duration::from_millis(300)).await;
    put(&s2, P, 5.0, t0 + 20).await;
    eventually("interval rows", || {
        values(&h, P)
            .iter()
            .filter(|v| **v == Value::Float(5.0))
            .count()
            >= 2
    })
    .await;
    // A source clock far off: neither a day ahead nor a year back is stored.
    let dropped = || {
        h.counters()
            .dropped
            .load(std::sync::atomic::Ordering::Relaxed)
    };
    let before = dropped();
    h.configure(vec![group("all", Logging::AllData, &[P, R])]);
    tokio::time::sleep(Duration::from_millis(300)).await;
    let now = wyrm_history::engine::now_us();
    put(&s2, P, 6.0, now + 86_400_000_000).await;
    put(&s2, R, 7.0, now - 365 * 86_400_000_000).await;
    eventually("implausible times dropped", || dropped() >= before + 2).await;
    tokio::time::sleep(Duration::from_millis(300)).await;
    assert!(!values(&h, P).contains(&Value::Float(6.0)));
    assert!(values(&h, R).is_empty());
    assert_eq!(h.store().days().len(), 1, "no day file for them");
    h.detach().await;
    assert_eq!(
        h.counters()
            .pending
            .load(std::sync::atomic::Ordering::Relaxed),
        0
    );
    let _ = std::fs::remove_dir_all(dir);
}
