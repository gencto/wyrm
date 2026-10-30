//! A device that answers for some points only (one batch of its poll timed
//! out): the points without an answer take the quality ladder on their own,
//! while the device stays connected. A point never goes up in quality
//! without an answer (final review M1), and a ping that answers does not
//! undo the misses of polls that do not (M2).

use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, LazyLock, Mutex};
use std::time::Duration;
use wyrm_core::meta::Writable;
use wyrm_core::{NodeMeta, Quality, Sample, Value};
use wyrm_link_sdk::driver::{Driver, DriverError, Framework, NodeState, PointId, Tree};
use wyrm_link_sdk::{Params, TestHarness};

/// Which points get no answer, per connection `tag`.
#[derive(Default)]
struct Silent {
    p: AtomicBool,
    q: AtomicBool,
}

static SILENT: LazyLock<Mutex<HashMap<u32, Arc<Silent>>>> = LazyLock::new(Default::default);

fn silent(tag: u32) -> Arc<Silent> {
    SILENT.lock().unwrap().entry(tag).or_default().clone()
}

#[derive(Debug, Clone, PartialEq, Params)]
struct Conn {
    #[param(default = 0)]
    tag: u32,
}

#[derive(Debug, Clone, PartialEq, Params)]
struct Dev {
    /// Ping period; 0 = no pings.
    #[param(default = 0)]
    ping_ms: u32,
}

#[derive(Debug, Clone, PartialEq, Params)]
struct Point {}

struct Partial;

impl Driver for Partial {
    const NAME: &'static str = "partial";
    const VERSION: &'static str = "0.1.0";
    type Conn = Conn;
    type Dev = Dev;
    type Point = Point;
    type Transport = Arc<Silent>;
    type Plan = Vec<PointId>;

    async fn open(conn: &Conn) -> Result<Arc<Silent>, DriverError> {
        Ok(silent(conn.tag))
    }

    /// Always answers (a probe register that works).
    async fn ping(_t: &mut Arc<Silent>, _dev: &Dev) -> Result<(), DriverError> {
        Ok(())
    }

    fn plan(_dev: &Dev, points: &[(PointId, Point)]) -> Self::Plan {
        points.iter().map(|(id, _)| id.clone()).collect()
    }

    async fn poll(
        t: &mut Arc<Silent>,
        _dev: &Dev,
        plan: &Self::Plan,
    ) -> Vec<(PointId, Result<Value, DriverError>)> {
        plan.iter()
            .map(|id| {
                let off = match id.as_str() {
                    "p" => t.p.load(Ordering::SeqCst),
                    _ => t.q.load(Ordering::SeqCst),
                };
                let r = if off {
                    Err(DriverError::Device("batch timed out".into()))
                } else {
                    Ok(Value::Float(1.0))
                };
                (id.clone(), r)
            })
            .collect()
    }

    async fn write(
        _t: &mut Arc<Silent>,
        _dev: &Dev,
        _id: &str,
        _p: &Point,
        _v: &Value,
    ) -> Result<(), DriverError> {
        Err(DriverError::Point("read only".into()))
    }

    fn point_meta(_p: &Point) -> NodeMeta {
        NodeMeta::number().writable(Writable::Never)
    }

    fn poll_period(_p: &Point) -> Duration {
        Duration::from_millis(50)
    }

    fn ping_period(dev: &Dev) -> Option<Duration> {
        (dev.ping_ms > 0).then(|| Duration::from_millis(dev.ping_ms.into()))
    }

    fn io_timeout(_conn: &Conn) -> Duration {
        Duration::from_millis(500)
    }
}

fn map(kv: &[(&str, Value)]) -> Value {
    Value::Map(
        kv.iter()
            .map(|(k, v)| ((*k).to_owned(), v.clone()))
            .collect(),
    )
}

type H = TestHarness<Framework<Partial>>;

/// `c1` (`tag`) with `d1` (`ping_ms`) and its points `p`, `q`.
async fn start(tag: u32, ping_ms: u32) -> H {
    let points = map(&[("p", map(&[])), ("q", map(&[]))]);
    let dev = map(&[("ping_ms", Value::UInt(ping_ms.into())), ("points", points)]);
    let conn = map(&[
        ("tag", Value::UInt(tag.into())),
        ("devices", map(&[("d1", dev)])),
    ]);
    H::start(Tree(map(&[("connections", map(&[("c1", conn)]))]))).await
}

async fn wait(what: &str, mut f: impl FnMut() -> bool) {
    let deadline = tokio::time::Instant::now() + Duration::from_secs(10);
    while !f() {
        assert!(tokio::time::Instant::now() < deadline, "timeout: {what}");
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
}

fn q(h: &H, s: &str) -> Option<(Value, Quality)> {
    h.ctx().last(s).map(|s| (s.v, s.q))
}

const GOOD: Option<(Value, Quality)> = Some((Value::Float(1.0), Quality::Good));

/// Every quality `path` is published with from now on.
async fn qualities(h: &H, path: &str) -> Arc<Mutex<Vec<Quality>>> {
    let sub = h
        .session()
        .declare_subscriber(h.key(path, "~val"))
        .await
        .unwrap();
    let seen = Arc::new(Mutex::new(Vec::new()));
    let out = seen.clone();
    tokio::spawn(async move {
        while let Ok(s) = sub.recv_async().await {
            if let Ok(v) = wyrm_core::codec::from_slice::<Sample>(&s.payload().to_bytes()) {
                out.lock().unwrap().push(v.q);
            }
        }
    });
    tokio::time::sleep(Duration::from_millis(100)).await;
    seen
}

/// Ruling P30: `q` without an answer goes `uncertain` with its last value,
/// then `bad` after `stale_misses` polls, and `good` again when it answers;
/// `p` and the device are not touched.
#[tokio::test(flavor = "multi_thread")]
async fn unanswered_points_take_the_ladder_alone() {
    let s = silent(1);
    let h = start(1, 0).await;
    wait("first values", || {
        q(&h, "c1/d1/p") == GOOD && q(&h, "c1/d1/q") == GOOD
    })
    .await;

    s.q.store(true, Ordering::SeqCst);
    wait("q stale", || {
        q(&h, "c1/d1/q").map(|(_, x)| x) != Some(Quality::Good)
    })
    .await;
    let first = q(&h, "c1/d1/q").unwrap();
    assert_eq!(
        first,
        (Value::Float(1.0), Quality::Uncertain),
        "last value kept"
    );
    wait("q bad", || {
        q(&h, "c1/d1/q") == Some((Value::Float(1.0), Quality::Bad))
    })
    .await;
    assert_eq!(q(&h, "c1/d1/p"), GOOD, "p untouched");
    let status = h.ctx().last("c1/d1/status").map(|s| s.v);
    assert_eq!(
        status,
        Some(Value::UInt(NodeState::Connected as u64)),
        "the device answered"
    );

    s.q.store(false, Ordering::SeqCst);
    wait("q good again", || q(&h, "c1/d1/q") == GOOD).await;
    h.stop().await;
}

/// M1: the device failed (no point answered, `bad/comm_fail`); then `p`
/// answers again and `q` still does not: `q` stays `bad`, never
/// `uncertain` in between.
#[tokio::test(flavor = "multi_thread")]
async fn a_bad_point_without_an_answer_stays_bad() {
    let s = silent(2);
    let h = start(2, 0).await;
    wait("first values", || q(&h, "c1/d1/q") == GOOD).await;
    s.p.store(true, Ordering::SeqCst);
    s.q.store(true, Ordering::SeqCst);
    wait("device failed", || {
        h.ctx().last("c1/d1/status").map(|s| s.v) == Some(Value::UInt(NodeState::Failed as u64))
            && q(&h, "c1/d1/q").map(|(_, x)| x) == Some(Quality::Bad)
    })
    .await;
    let seen = qualities(&h, "c1/d1/q").await;
    s.p.store(false, Ordering::SeqCst);
    wait("p good again", || q(&h, "c1/d1/p") == GOOD).await;
    // Several polls with `q` silent.
    tokio::time::sleep(Duration::from_millis(500)).await;
    assert_eq!(
        q(&h, "c1/d1/q").map(|(_, x)| x),
        Some(Quality::Bad),
        "still bad"
    );
    let seen = seen.lock().unwrap().clone();
    assert!(
        seen.iter().all(|x| *x == Quality::Bad),
        "q went up without an answer: {seen:?}"
    );
    h.stop().await;
}

/// M2: polls get no answer while pings do (a probe register that answers,
/// a span the device drops): the points reach `bad/comm_fail` and stay
/// there; pings do not lift them to `uncertain`.
#[tokio::test(flavor = "multi_thread")]
async fn answered_pings_do_not_undo_poll_misses() {
    let s = silent(3);
    let h = start(3, 20).await;
    wait("first values", || q(&h, "c1/d1/p") == GOOD).await;
    s.p.store(true, Ordering::SeqCst);
    s.q.store(true, Ordering::SeqCst);
    wait("points bad", || {
        q(&h, "c1/d1/p").map(|(_, x)| x) == Some(Quality::Bad)
    })
    .await;
    let seen = qualities(&h, "c1/d1/p").await;
    tokio::time::sleep(Duration::from_millis(800)).await;
    assert_eq!(
        q(&h, "c1/d1/p").map(|(_, x)| x),
        Some(Quality::Bad),
        "stays bad"
    );
    let seen = seen.lock().unwrap().clone();
    assert!(
        seen.iter().all(|x| *x == Quality::Bad),
        "p left bad without an answer: {seen:?}"
    );
    // The device answers pings: it shows `Connected`, its points stay bad.
    wait("device connected", || {
        h.ctx().last("c1/d1/status").map(|s| s.v) == Some(Value::UInt(NodeState::Connected as u64))
    })
    .await;
    assert_eq!(q(&h, "c1/d1/p").map(|(_, x)| x), Some(Quality::Bad));
    s.p.store(false, Ordering::SeqCst);
    s.q.store(false, Ordering::SeqCst);
    wait("good again", || q(&h, "c1/d1/p") == GOOD).await;
    h.stop().await;
}
