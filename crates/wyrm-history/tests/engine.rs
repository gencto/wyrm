//! The historian on an in-memory Zenoh session: logging types, flush on
//! detach, and a new session after a "rebuild".

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::unreachable,
    clippy::print_stdout,
    reason = "test code: a failed step fails the test"
)]

use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;
use std::time::Duration;
use wyrm_core::{codec, HistRow, Quality, Sample, Value};
use wyrm_history::{GroupCfg, Historian, Logging, WatchCfg};

const P: &str = "wy/s/downstream/mock/p";
const Q: &str = "wy/s/downstream/mock/q";
const R: &str = "wy/s/downstream/mock/r";

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

/// The array replies of a `get` (other replies are skipped).
async fn history(s: &zenoh::Session, selector: &str) -> Vec<Vec<HistRow>> {
    let rx = s
        .get(selector)
        .consolidation(zenoh::query::ConsolidationMode::None)
        .timeout(Duration::from_secs(2))
        .await
        .unwrap();
    let mut out = Vec::new();
    while let Ok(r) = rx.recv_async().await {
        if let Ok(smp) = r.result() {
            if let Ok(rows) = codec::from_slice::<Vec<HistRow>>(&smp.payload().to_bytes()) {
                out.push(rows);
            }
        }
    }
    out
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
        vec!["wy/s/downstream/**/~val".into()],
        Some("wy/s/sys/history".into()),
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
        vec!["wy/s/downstream/**/~val".into()],
        Some("wy/s/sys/history".into()),
    );
    tokio::time::sleep(Duration::from_millis(300)).await;
    put(&s2, P, 3.0, t0 + 4).await;
    put(&s2, Q, 3.0, t0 + 9).await;
    put(&s2, P, 4.0, t0 + 10).await;
    eventually("new session records", || values(&h, P).len() == 6).await;
    tokio::time::sleep(Duration::from_millis(300)).await;
    assert_eq!(values(&h, Q).len(), 3, "unchanged after the rebuild");

    // `get <point>/~val?history=…` (spec 03): arrays of rows; a point that
    // is not recorded and a plain `~val` get get no answer from it.
    let rows = history(&s2, &format!("{P}/~val?history=2020-01-01..")).await;
    assert_eq!(rows.len(), 1, "one reply");
    assert_eq!(rows[0].len(), 6);
    assert_eq!(rows[0][5].v, Value::Float(4.0));
    assert!(rows[0].iter().all(|r| r.q == Some(Quality::Good)));
    let agg = history(&s2, &format!("{P}/~val?history=2020-01-01..&agg=max")).await;
    assert_eq!(
        agg[0],
        [HistRow {
            t: agg[0][0].t,
            v: Value::Float(4.0),
            q: None
        }]
    );
    assert!(
        history(&s2, "wy/s/downstream/mock/none/~val?history=2020-01-01..")
            .await
            .is_empty()
    );
    assert!(history(&s2, &format!("{P}/~val")).await.is_empty());
    // At the watch key too (ADR 0020): a downstream site's point is read
    // there; an unknown watch gets no answer.
    let at_watch = history(&s2, "wy/s/sys/history/all/w1/~val?history=2020-01-01..").await;
    assert_eq!(at_watch, rows);
    assert!(
        history(&s2, "wy/s/sys/history/all/w9/~val?history=2020-01-01..")
            .await
            .is_empty()
    );

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
    // Sent again until both are counted: on a slow machine the new watches
    // may subscribe after the first samples went by.
    let now = wyrm_history::engine::now_us();
    for _ in 0..100 {
        put(&s2, P, 6.0, now + 86_400_000_000).await;
        put(&s2, R, 7.0, now - 365 * 86_400_000_000).await;
        tokio::time::sleep(Duration::from_millis(50)).await;
        if dropped() >= before + 2 {
            break;
        }
    }
    assert!(dropped() >= before + 2, "implausible times dropped");
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

/// Run `body` on a runtime of `workers` threads (the body itself on the
/// calling thread, as `block_on` does) and fail when `progress` stays still
/// for `stall`: a stalled runtime fires no timer of its own, so the watch is
/// a thread outside it. A slow machine is not a stall: only no progress is.
fn without_stall<F>(
    workers: usize,
    stall: Duration,
    progress: Arc<AtomicUsize>,
    body: impl FnOnce() -> F + Send + 'static,
) where
    F: std::future::Future<Output = ()>,
{
    let (tx, rx) = std::sync::mpsc::channel();
    std::thread::spawn(move || {
        let rt = tokio::runtime::Builder::new_multi_thread()
            .worker_threads(workers)
            .enable_all()
            .build()
            .unwrap();
        rt.block_on(body());
        let _ = tx.send(());
    });
    let (mut seen, mut since) = (usize::MAX, std::time::Instant::now());
    loop {
        match rx.recv_timeout(Duration::from_millis(200)) {
            Ok(()) => return,
            Err(std::sync::mpsc::RecvTimeoutError::Disconnected) => panic!("the body failed"),
            Err(std::sync::mpsc::RecvTimeoutError::Timeout) => {}
        }
        let now = progress.load(Ordering::Relaxed);
        if now != seen {
            (seen, since) = (now, std::time::Instant::now());
        } else if since.elapsed() > stall {
            panic!("no progress in {stall:?} at {now}: the runtime stalled");
        }
    }
}

/// docs/backlog.md §14: a group of many new watches opens one `get ~val` per
/// point, and the historian's own `~val?history=` queryable matches every
/// one. Its handler was a FIFO of 256 drained by a task of the same runtime:
/// a follow that found it full blocked its worker in the send, and once
/// every worker did, the task that drains it never ran again. Before the
/// fix this stalled 5 runs of 5 (4 workers, 3000 watches, every worker in
/// `flume::Sender<Query>::send`); after it the group starts in seconds.
#[test]
fn many_new_watches_do_not_stall_the_runtime() {
    let n = 3000;
    let recorded = Arc::new(AtomicUsize::new(0));
    let seen = recorded.clone();
    without_stall(4, Duration::from_secs(30), recorded, move || async move {
        let dir = temp("many");
        let h = Historian::open(&dir).unwrap();
        let s = session().await;
        let keys: Vec<String> = (0..n).map(|i| format!("wy/s/downstream/m/p{i}")).collect();
        let refs: Vec<&str> = keys.iter().map(String::as_str).collect();
        h.attach(
            s.clone(),
            vec![group("many", Logging::AllData, &refs)],
            vec!["wy/s/downstream/**/~val".into()],
            Some("wy/s/sys/history".into()),
        );
        // every point followed: a put on each is recorded
        let started = std::time::Instant::now();
        let mut t = wyrm_history::engine::now_us();
        loop {
            t += 1;
            for k in &keys {
                put(&s, k, 1.0, t).await;
            }
            tokio::time::sleep(Duration::from_millis(300)).await;
            let count = keys.iter().filter(|k| !values(&h, k).is_empty()).count();
            seen.store(count, Ordering::Relaxed);
            if count == n {
                break;
            }
        }
        println!("{n} watches recorded in {:?}", started.elapsed());
        h.detach().await;
        let _ = std::fs::remove_dir_all(dir);
    });
}

/// Many more history queries at once than the historian takes
/// (`QUERY_QUEUE` waiting, `MAX_ANSWERS` with a task, `MAX_QUERIES`
/// reading): every one ends with rows, with a refusal or with nothing, none
/// holds a worker, and the historian answers the next one as before.
#[test]
fn a_flood_of_history_queries_ends() {
    let n = 3000;
    let ended = Arc::new(AtomicUsize::new(0));
    let seen = ended.clone();
    without_stall(2, Duration::from_secs(30), ended, move || async move {
        let dir = temp("flood");
        let h = Historian::open(&dir).unwrap();
        let s = session().await;
        h.attach(
            s.clone(),
            vec![group("all", Logging::AllData, &[P])],
            vec!["wy/s/downstream/**/~val".into()],
            Some("wy/s/sys/history".into()),
        );
        let mut t = wyrm_history::engine::now_us();
        while values(&h, P).is_empty() {
            t += 1;
            put(&s, P, 1.0, t).await;
            tokio::time::sleep(Duration::from_millis(100)).await;
        }
        let selector = format!("{P}/~val?history=2020-01-01..");
        let mut gets = tokio::task::JoinSet::new();
        for _ in 0..n {
            let (s, selector, seen) = (s.clone(), selector.clone(), seen.clone());
            gets.spawn(async move {
                let rows = history(&s, &selector).await;
                seen.fetch_add(1, Ordering::Relaxed);
                !rows.is_empty()
            });
        }
        let mut answered = 0;
        while let Some(r) = gets.join_next().await {
            answered += usize::from(r.unwrap());
        }
        println!("{answered} of {n} history queries answered with rows");
        assert!(answered > 0, "no query of the flood got rows");
        // the flood left nothing behind: one more read is answered
        let mut rows = Vec::new();
        for _ in 0..50 {
            rows = history(&s, &selector).await;
            if !rows.is_empty() {
                break;
            }
            tokio::time::sleep(Duration::from_millis(200)).await;
        }
        assert!(!rows.is_empty(), "no answer after the flood");
        h.detach().await;
        let _ = std::fs::remove_dir_all(dir);
    });
}

/// One link holds every read of its points open (a hung link process), and
/// its watches come first in the group. The points of another link are
/// followed all the same, at once: their stored values are recorded, then
/// their live ones. Before, a follow waited for a turn of the one window
/// before it declared its subscriber, the hung link's reads held every turn
/// to their timeout (64 per 10 s), and the other link's points had no
/// subscriber and no stored value for all that time.
#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn a_link_that_answers_no_read_delays_no_other_point() {
    let n = 400;
    let dir = temp("hung");
    let h = Historian::open(&dir).unwrap();
    let s = session().await;
    // the hung link: every query kept, none answered
    let held = Arc::new(std::sync::Mutex::new(Vec::new()));
    let keep = held.clone();
    let _hung = s
        .declare_queryable("wy/s/downstream/hung/**")
        .callback(move |q| keep.lock().unwrap().push(q))
        .await
        .unwrap();
    // the storage of the healthy link's points: a stored value of each
    let stored = codec::to_vec(&Sample {
        v: Value::Float(42.0),
        q: Quality::Good,
        t: wyrm_history::engine::now_us(),
    })
    .unwrap();
    let _storage = s
        .declare_queryable("wy/s/downstream/ok/*/~val")
        .callback(move |q| {
            if q.parameters().as_str().is_empty() {
                let _ = zenoh::Wait::wait(q.reply(q.key_expr(), stored.clone()));
            }
        })
        .await
        .unwrap();
    let hung: Vec<String> = (0..n)
        .map(|i| format!("wy/s/downstream/hung/p{i}"))
        .collect();
    let ok: Vec<String> = (0..n).map(|i| format!("wy/s/downstream/ok/p{i}")).collect();
    let refs: Vec<&str> = hung.iter().chain(&ok).map(String::as_str).collect();
    h.attach(
        s.clone(),
        vec![group("mixed", Logging::AllData, &refs)],
        vec!["wy/s/downstream/**/~val".into()],
        Some("wy/s/sys/history".into()),
    );
    // Each step well inside the 10 s a hung read holds its turn. First the
    // stored values, with no live value sent: the reads of the healthy
    // link's points do not wait behind the hung link's.
    let started = std::time::Instant::now();
    loop {
        tokio::time::sleep(Duration::from_millis(200)).await;
        let got = ok
            .iter()
            .filter(|k| values(&h, k) == vec![Value::Float(42.0)])
            .count();
        if got == n {
            break;
        }
        assert!(
            started.elapsed() < Duration::from_secs(8),
            "the stored value of {got} of {n} points recorded"
        );
    }
    // Then a live value of each.
    let started = std::time::Instant::now();
    let mut t = wyrm_history::engine::now_us();
    loop {
        t += 1;
        for k in &ok {
            put(&s, k, 1.0, t).await;
        }
        tokio::time::sleep(Duration::from_millis(200)).await;
        let got = ok.iter().filter(|k| values(&h, k).len() > 1).count();
        if got == n {
            break;
        }
        assert!(
            started.elapsed() < Duration::from_secs(8),
            "a live value of {got} of {n} points recorded"
        );
    }
    assert!(!held.lock().unwrap().is_empty(), "the hung link got reads");
    h.detach().await;
    let _ = std::fs::remove_dir_all(dir);
}
