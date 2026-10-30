//! A connection held by a driver action (final review I1, I2, M3): one
//! action at a time per connection, a set during it answers `busy` at once
//! and never holds the link task, polls go on between actions, and points
//! whose poll could not run go `uncertain/stale`.

use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, LazyLock, Mutex};
use std::time::{Duration, Instant};
use wyrm_core::meta::{ParamMeta, Writable};
use wyrm_core::status::StatusCode;
use wyrm_core::{ActionMeta, NodeMeta, Perm, Quality, Status, TypeCode, Value};
use wyrm_link_sdk::driver::{Driver, DriverError, Framework, Level, PointId, Target, Tree};
use wyrm_link_sdk::{LinkError, Params, TestHarness};

/// What one test's driver saw (by the connection's `tag`).
#[derive(Default)]
struct Seen {
    polls: AtomicU64,
    writes: AtomicU64,
    /// An action is sleeping now.
    acting: AtomicBool,
    /// Time one poll takes (ms).
    poll_ms: AtomicU64,
    /// A poll is running now.
    polling: AtomicBool,
}

static SEEN: LazyLock<Mutex<HashMap<u32, Arc<Seen>>>> = LazyLock::new(Default::default);

fn seen(tag: u32) -> Arc<Seen> {
    SEEN.lock().unwrap().entry(tag).or_default().clone()
}

#[derive(Debug, Clone, PartialEq, Params)]
struct Conn {
    #[param(default = 0)]
    tag: u32,
}

#[derive(Debug, Clone, PartialEq, Params)]
struct Dev {}

#[derive(Debug, Clone, PartialEq, Params)]
struct Point {}

/// Polls answer after `poll_ms` (at once by default) with a counter (so
/// every poll publishes); writes answer at once; the device action
/// `wait {ms}` sleeps `ms`.
struct Slow;

impl Driver for Slow {
    const NAME: &'static str = "slow";
    const VERSION: &'static str = "0.1.0";
    type Conn = Conn;
    type Dev = Dev;
    type Point = Point;
    type Transport = Arc<Seen>;
    type Plan = Vec<PointId>;

    async fn open(conn: &Conn) -> Result<Arc<Seen>, DriverError> {
        Ok(seen(conn.tag))
    }

    async fn ping(_t: &mut Arc<Seen>, _dev: &Dev) -> Result<(), DriverError> {
        Ok(())
    }

    fn plan(_dev: &Dev, points: &[(PointId, Point)]) -> Self::Plan {
        points.iter().map(|(id, _)| id.clone()).collect()
    }

    async fn poll(
        t: &mut Arc<Seen>,
        _dev: &Dev,
        plan: &Self::Plan,
    ) -> Vec<(PointId, Result<Value, DriverError>)> {
        let ms = t.poll_ms.load(Ordering::SeqCst);
        if ms > 0 {
            t.polling.store(true, Ordering::SeqCst);
            tokio::time::sleep(Duration::from_millis(ms)).await;
            t.polling.store(false, Ordering::SeqCst);
        }
        let n = t.polls.fetch_add(1, Ordering::SeqCst);
        plan.iter()
            .map(|id| (id.clone(), Ok(Value::UInt(n))))
            .collect()
    }

    async fn write(
        t: &mut Arc<Seen>,
        _dev: &Dev,
        _id: &str,
        _p: &Point,
        _v: &Value,
    ) -> Result<(), DriverError> {
        t.writes.fetch_add(1, Ordering::SeqCst);
        Ok(())
    }

    fn point_meta(_p: &Point) -> NodeMeta {
        NodeMeta::number().writable(Writable::Write)
    }

    fn poll_period(_p: &Point) -> Duration {
        Duration::from_millis(50)
    }

    fn ping_period(_dev: &Dev) -> Option<Duration> {
        None
    }

    fn io_timeout(_conn: &Conn) -> Duration {
        Duration::from_secs(1)
    }

    fn actions(level: Level, _kind: &str) -> Vec<(&'static str, ActionMeta)> {
        match level {
            Level::Connection => vec![],
            Level::Device => vec![(
                "wait",
                ActionMeta::new()
                    .level(Perm::Read)
                    .param("ms", ParamMeta::of(TypeCode::Number).required(true))
                    .timeout_ms(10_000),
            )],
        }
    }

    async fn invoke(
        t: &mut Arc<Seen>,
        _conn: &Conn,
        _target: Target<'_, Self>,
        _action: &str,
        args: &Value,
    ) -> Result<Value, LinkError> {
        let ms = match args {
            Value::Map(m) => match m.get("ms") {
                Some(Value::UInt(n)) => *n,
                _ => 0,
            },
            _ => 0,
        };
        t.acting.store(true, Ordering::SeqCst);
        tokio::time::sleep(Duration::from_millis(ms)).await;
        t.acting.store(false, Ordering::SeqCst);
        Ok(Value::Null)
    }
}

fn map(kv: &[(&str, Value)]) -> Value {
    Value::Map(
        kv.iter()
            .map(|(k, v)| ((*k).to_owned(), v.clone()))
            .collect(),
    )
}

/// Connections `c1`, `c2` (tags `tag`, `tag + 1`), each with `d1` and its
/// point `p`.
fn tree(tag: u32) -> Tree {
    let conn = |t: u32| {
        let dev = map(&[("points", map(&[("p", map(&[]))]))]);
        map(&[
            ("tag", Value::UInt(t.into())),
            ("devices", map(&[("d1", dev)])),
        ])
    };
    Tree(map(&[(
        "connections",
        map(&[("c1", conn(tag)), ("c2", conn(tag + 1))]),
    )]))
}

type H = TestHarness<Framework<Slow>>;

async fn wait(what: &str, mut f: impl FnMut() -> bool) {
    let deadline = tokio::time::Instant::now() + Duration::from_secs(10);
    while !f() {
        assert!(tokio::time::Instant::now() < deadline, "timeout: {what}");
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
}

fn status_of(code: Option<StatusCode>) -> Option<Status> {
    match code? {
        StatusCode::Known(s) => Some(s),
        _ => None,
    }
}

async fn act(h: &H, conn: &str, ms: u64) -> Option<Status> {
    let r = h
        .invoke(
            &format!("{conn}/d1"),
            "wait",
            map(&[("ms", Value::UInt(ms))]),
            Some(h.ptok(Perm::Read)),
        )
        .await;
    status_of(r.first()?.att.status)
}

/// A timed set: `(status, how long it took)`.
async fn set(h: &H, path: &str) -> (Option<Status>, Duration) {
    let t = Instant::now();
    let att = h.set(path, 1.0, Some(h.ptok(Perm::Write))).await;
    (status_of(att.status), t.elapsed())
}

async fn started(tag: u32) -> H {
    let h = H::start(tree(tag)).await;
    let s = seen(tag);
    wait("polling", || s.polls.load(Ordering::SeqCst) > 2).await;
    h
}

/// I1: a `read` caller that floods actions at one connection gets `busy`
/// for every action beyond the one queued or running, and the
/// connection's polls go on between actions.
#[tokio::test(flavor = "multi_thread")]
async fn a_flood_of_actions_does_not_stop_polling() {
    let tag = 10;
    let h = Arc::new(started(tag).await);
    let s = seen(tag);
    let end = Instant::now() + Duration::from_secs(3);
    let busy = Arc::new(AtomicU64::new(0));
    let mut flood = Vec::new();
    for _ in 0..16 {
        let (h, busy) = (h.clone(), busy.clone());
        flood.push(tokio::spawn(async move {
            while Instant::now() < end {
                if act(&h, "c1", 300).await == Some(Status::Busy) {
                    busy.fetch_add(1, Ordering::SeqCst);
                }
                tokio::time::sleep(Duration::from_millis(10)).await;
            }
        }));
    }
    tokio::time::sleep(Duration::from_millis(800)).await;
    let (p0, t0) = (s.polls.load(Ordering::SeqCst), Instant::now());
    tokio::time::sleep(Duration::from_millis(2000)).await;
    let polls = s.polls.load(Ordering::SeqCst) - p0;
    let took = t0.elapsed();
    for f in flood {
        f.await.unwrap();
    }
    assert!(
        polls >= 4,
        "{polls} polls in {took:?} of a flood of 300 ms actions"
    );
    assert!(busy.load(Ordering::SeqCst) > 0, "a second action is busy");
    wait("good again", || {
        h.ctx()
            .last("c1/d1/p")
            .is_some_and(|x| x.q == Quality::Good)
    })
    .await;
}

/// I2: a set to a connection while its action runs answers `busy` at
/// once (the write would be dropped by P13 anyway); so does a second
/// action. Once the action ended, both work again.
#[tokio::test(flavor = "multi_thread")]
async fn a_set_during_a_long_action_answers_busy_at_once() {
    let tag = 20;
    let h = started(tag).await;
    let s = seen(tag);
    let (long, (during, second)) = tokio::join!(act(&h, "c1", 3000), async {
        wait("acting", || s.acting.load(Ordering::SeqCst)).await;
        (set(&h, "c1/d1/p").await, act(&h, "c1", 10).await)
    });
    assert_eq!(long, Some(Status::Ok));
    let (st, took) = during;
    assert_eq!(st, Some(Status::Busy), "set during the action");
    assert!(took < Duration::from_secs(1), "answered after {took:?}");
    assert_eq!(second, Some(Status::Busy), "a second action");
    assert_eq!(s.writes.load(Ordering::SeqCst), 0, "never written late");
    assert_eq!(set(&h, "c1/d1/p").await.0, Some(Status::Ok));
    assert_eq!(act(&h, "c1", 10).await, Some(Status::Ok));
    h.stop().await;
}

/// I2: a set to another connection of the link is not delayed by a set to
/// the connection whose action runs.
#[tokio::test(flavor = "multi_thread")]
async fn a_set_to_another_connection_is_not_delayed() {
    let tag = 30;
    let h = started(tag).await;
    let s = seen(tag);
    let (_, _, other) = tokio::join!(
        act(&h, "c1", 3000),
        async {
            wait("acting", || s.acting.load(Ordering::SeqCst)).await;
            set(&h, "c1/d1/p").await
        },
        async {
            wait("acting", || s.acting.load(Ordering::SeqCst)).await;
            tokio::time::sleep(Duration::from_millis(100)).await;
            set(&h, "c2/d1/p").await
        }
    );
    let (st, took) = other;
    assert_eq!(st, Some(Status::Ok));
    assert!(took < Duration::from_secs(1), "c2 answered after {took:?}");
    h.stop().await;
}

/// M3: while an action holds the owner, the points whose poll waits go
/// `uncertain/stale` after `stale_misses` periods (last value kept), and
/// `good` again once polled.
#[tokio::test(flavor = "multi_thread")]
async fn points_whose_poll_waits_go_stale() {
    let tag = 40;
    let h = started(tag).await;
    let s = seen(tag);
    let q = |p: &str| h.ctx().last(p).map(|x| x.q);
    let (long, stale) = tokio::join!(act(&h, "c1", 2000), async {
        wait("acting", || s.acting.load(Ordering::SeqCst)).await;
        let t = Instant::now();
        wait("stale", || q("c1/d1/p") == Some(Quality::Uncertain)).await;
        let took = t.elapsed();
        (took, q("c2/d1/p"), s.acting.load(Ordering::SeqCst))
    });
    assert_eq!(long, Some(Status::Ok));
    let (took, other, acting) = stale;
    assert!(acting, "stale while the action runs ({took:?})");
    assert!(took < Duration::from_secs(1), "stale after {took:?}");
    assert_eq!(other, Some(Quality::Good), "another connection untouched");
    wait("good again", || q("c1/d1/p") == Some(Quality::Good)).await;
    h.stop().await;
}

/// P13 kept: a set queued behind a long poll whose caller already got
/// `timeout` is dropped when the owner reaches it, never written late.
#[tokio::test(flavor = "multi_thread")]
async fn a_write_past_its_deadline_is_never_sent() {
    let tag = 50;
    let s = seen(tag);
    let h = H::start_with(tree(tag), |c| c.driver_timeout = Duration::from_millis(400)).await;
    wait("polling", || s.polls.load(Ordering::SeqCst) > 2).await;
    // One poll of 900 ms (under the 1 s poll bound) holds the owner.
    s.poll_ms.store(900, Ordering::SeqCst);
    wait("slow poll", || s.polling.load(Ordering::SeqCst)).await;
    s.poll_ms.store(0, Ordering::SeqCst);
    let (st, took) = set(&h, "c1/d1/p").await;
    assert_eq!(st, Some(Status::Timeout), "after {took:?}");
    let polls = s.polls.load(Ordering::SeqCst);
    wait("polled after", || {
        s.polls.load(Ordering::SeqCst) > polls + 3
    })
    .await;
    assert_eq!(s.writes.load(Ordering::SeqCst), 0, "written late");
    assert_eq!(set(&h, "c1/d1/p").await.0, Some(Status::Ok));
    assert_eq!(s.writes.load(Ordering::SeqCst), 1);
    h.stop().await;
}
