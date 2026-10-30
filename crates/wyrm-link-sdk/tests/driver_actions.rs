//! Driver actions (`Driver::actions` / `Driver::invoke`, ruling 13) and
//! diagnostics counters (`Driver::DIAGNOSTICS`, ruling 12), through a small
//! test driver.

use std::collections::{BTreeMap, HashMap};
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::{Arc, LazyLock, Mutex};
use std::time::{Duration, Instant};
use wyrm_core::meta::{ActionResult, ParamMeta, Writable};
use wyrm_core::status::StatusCode;
use wyrm_core::{ActionMeta, NodeMeta, Perm, Status, TypeCode, Value};
use wyrm_link_sdk::driver::{
    Driver, DriverError, Framework, Level, Outcome, PointId, Target, Tree,
};
use wyrm_link_sdk::{LinkError, Params, TestHarness};

/// What one test's driver instances saw (by the connection's `tag`).
#[derive(Default)]
struct Seen {
    busy: AtomicBool,
    /// An operation started while another was running.
    overlaps: AtomicU32,
    opens: AtomicU32,
    /// `poll` and `invoke:<action>`, in order.
    log: Mutex<Vec<String>>,
}

static SEEN: LazyLock<Mutex<HashMap<u32, Arc<Seen>>>> = LazyLock::new(Default::default);

fn seen(tag: u32) -> Arc<Seen> {
    SEEN.lock().unwrap().entry(tag).or_default().clone()
}

#[derive(Debug, Clone, PartialEq, Params)]
struct Conn {
    #[param(default = 0)]
    tag: u32,
    /// Time one poll takes.
    #[param(default = 20)]
    poll_ms: u32,
}

#[derive(Debug, Clone, PartialEq, Params)]
struct Dev {
    #[param(default = 1)]
    unit: u32,
}

#[derive(Debug, Clone, PartialEq, Params)]
struct Point {
    #[param(default = 0.02)]
    poll_s: f64,
}

struct Transport {
    seen: Arc<Seen>,
    poll: Duration,
    /// Requests sent so far.
    n: u64,
    outcomes: Vec<Outcome>,
}

impl Transport {
    fn enter(&self) {
        if self.seen.busy.swap(true, Ordering::AcqRel) {
            self.seen.overlaps.fetch_add(1, Ordering::Relaxed);
        }
    }

    fn leave(&self, what: String) {
        self.seen.log.lock().unwrap().push(what);
        self.seen.busy.store(false, Ordering::Release);
    }
}

/// One request per poll, in a cycle of five: answered after 10 ms, after
/// 30 ms, an exception after 20 ms, a timeout, an I/O error; and one
/// driver event `retries` per poll.
struct Diag;

const MS: fn(u64) -> Duration = Duration::from_millis;

impl Driver for Diag {
    const NAME: &'static str = "diag";
    const VERSION: &'static str = "0.1.0";
    type Conn = Conn;
    type Dev = Dev;
    type Point = Point;
    type Transport = Transport;
    type Plan = Vec<PointId>;

    const DIAGNOSTICS: bool = true;
    const DIAG_EXTRA: &'static [&'static str] = &["retries"];

    fn take_outcomes(t: &mut Transport) -> Vec<Outcome> {
        std::mem::take(&mut t.outcomes)
    }

    async fn open(conn: &Conn) -> Result<Transport, DriverError> {
        let seen = seen(conn.tag);
        seen.opens.fetch_add(1, Ordering::Relaxed);
        Ok(Transport {
            seen,
            poll: MS(conn.poll_ms.into()),
            n: 0,
            outcomes: Vec::new(),
        })
    }

    async fn ping(_t: &mut Transport, _dev: &Dev) -> Result<(), DriverError> {
        Ok(())
    }

    fn plan(_dev: &Dev, points: &[(PointId, Point)]) -> Self::Plan {
        points.iter().map(|(id, _)| id.clone()).collect()
    }

    async fn poll(
        t: &mut Transport,
        _dev: &Dev,
        plan: &Self::Plan,
    ) -> Vec<(PointId, Result<Value, DriverError>)> {
        t.enter();
        tokio::time::sleep(t.poll).await;
        let o = match t.n % 5 {
            0 => Outcome::Reply(MS(10)),
            1 => Outcome::Reply(MS(30)),
            2 => Outcome::Exception(MS(20)),
            3 => Outcome::Timeout,
            _ => Outcome::Error,
        };
        t.n += 1;
        t.outcomes.extend([o, Outcome::Count("retries")]);
        t.leave("poll".into());
        plan.iter()
            .map(|id| (id.clone(), Ok(Value::Float(1.0))))
            .collect()
    }

    async fn write(
        _t: &mut Transport,
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

    fn poll_period(p: &Point) -> Duration {
        Duration::from_secs_f64(p.poll_s)
    }

    fn ping_period(_dev: &Dev) -> Option<Duration> {
        None
    }

    fn actions(level: Level, _kind: &str) -> Vec<(&'static str, ActionMeta)> {
        let read = || ActionMeta::new().level(Perm::Read);
        match level {
            Level::Connection => vec![(
                "scan",
                ActionMeta::new()
                    .level(Perm::Config)
                    .display("Scan")
                    .result(ActionResult::Type(TypeCode::Map)),
            )],
            Level::Device => vec![
                (
                    "echo",
                    read().param("x", ParamMeta::of(TypeCode::Number).required(true)),
                ),
                ("fail", read()),
                ("break", read()),
                // Framework names: never declared.
                ("edit", read()),
                ("add_thing", read()),
            ],
        }
    }

    async fn invoke(
        t: &mut Transport,
        conn: &Conn,
        target: Target<'_, Self>,
        action: &str,
        args: &Value,
    ) -> Result<Value, LinkError> {
        t.enter();
        tokio::time::sleep(MS(30)).await;
        let r = match (target, action) {
            (Target::Connection, "scan") => Ok(map(&[("tag", Value::UInt(conn.tag.into()))])),
            (Target::Device { id, dev }, "echo") => {
                t.outcomes.push(Outcome::Reply(MS(5)));
                let x = match args {
                    Value::Map(m) => m.get("x").cloned().unwrap_or(Value::Null),
                    _ => Value::Null,
                };
                Ok(map(&[
                    ("id", id.into()),
                    ("unit", Value::UInt(dev.unit.into())),
                    ("x", x),
                ]))
            }
            (Target::Device { .. }, "fail") => {
                t.outcomes.push(Outcome::Exception(MS(5)));
                Err(LinkError::invalid_parameter("illegal address"))
            }
            (Target::Device { .. }, "break") => {
                Err(LinkError::new(Status::Disconnected, "transport lost"))
            }
            (_, a) => Err(LinkError::not_supported(a.to_owned())),
        };
        t.leave(format!("invoke:{action}"));
        r
    }
}

fn map(kv: &[(&str, Value)]) -> Value {
    Value::Map(
        kv.iter()
            .map(|(k, v)| ((*k).to_owned(), v.clone()))
            .collect(),
    )
}

/// `c1` (`tag`) with `d1` (points `p`, `q`) and `d2` (no points).
fn tree(tag: u32, d1_points: Value) -> Tree {
    let devs = map(&[
        ("d1", map(&[("points", d1_points)])),
        ("d2", map(&[("unit", Value::UInt(2)), ("points", map(&[]))])),
    ]);
    let c1 = map(&[("tag", Value::UInt(tag.into())), ("devices", devs)]);
    Tree(map(&[("connections", map(&[("c1", c1)]))]))
}

fn two_points() -> Value {
    map(&[("p", map(&[])), ("q", map(&[]))])
}

type H = TestHarness<Framework<Diag>>;

async fn wait(what: &str, within: Duration, mut f: impl FnMut() -> bool) {
    let deadline = tokio::time::Instant::now() + within;
    while !f() {
        assert!(tokio::time::Instant::now() < deadline, "timeout: {what}");
        tokio::time::sleep(MS(20)).await;
    }
}

fn status(r: &[wyrm_link_sdk::harness::Reply]) -> Option<Status> {
    match r.first()?.att.status? {
        StatusCode::Known(s) => Some(s),
        _ => None,
    }
}

fn actions(h: &H, path: &str) -> BTreeMap<String, ActionMeta> {
    h.ctx()
        .meta(path)
        .and_then(|m| m.actions)
        .unwrap_or_default()
}

/// Ruling 13 (hook): driver actions appear on their nodes with their
/// level; they run on the owner task between polls, never during one; the
/// driver's error status reaches the caller; `disconnected` reconnects.
#[tokio::test(flavor = "multi_thread")]
async fn driver_actions_are_declared_and_run_on_the_owner_task() {
    let s = seen(1);
    let h = H::start(tree(1, two_points())).await;
    wait("polling", Duration::from_secs(5), || {
        s.log.lock().unwrap().len() > 3
    })
    .await;

    let conn = actions(&h, "c1");
    assert_eq!(conn["scan"].level, Some(Perm::Config));
    assert_eq!(conn["scan"].display.as_deref(), Some("Scan"));
    let dev = actions(&h, "c1/d1");
    assert_eq!(dev["echo"].level, Some(Perm::Read));
    assert_eq!(dev["fail"].level, Some(Perm::Read));
    assert!(!dev.contains_key("add_thing"), "framework name refused");
    assert_eq!(dev["edit"].level, Some(Perm::Config), "framework edit kept");
    assert_eq!(dev["edit"].display.as_deref(), Some("Edit"));
    assert!(
        !actions(&h, "c1/d1/p").contains_key("echo"),
        "not on points"
    );

    // Ten actions while the device is polled every 20 ms.
    for i in 0..10u64 {
        let r = h
            .invoke(
                "c1/d1",
                "echo",
                map(&[("x", Value::UInt(i))]),
                Some(h.ptok(Perm::Read)),
            )
            .await;
        assert_eq!(status(&r), Some(Status::Ok));
        assert_eq!(
            r[0].value(),
            Some(map(&[
                ("id", "d1".into()),
                ("unit", Value::UInt(1)),
                ("x", Value::UInt(i)),
            ]))
        );
    }
    assert_eq!(s.overlaps.load(Ordering::Relaxed), 0, "never during a poll");
    let log = s.log.lock().unwrap().clone();
    let first = log.iter().position(|e| e == "invoke:echo").unwrap();
    let last = log.iter().rposition(|e| e == "invoke:echo").unwrap();
    let between = log[first..last].iter().filter(|e| *e == "poll").count();
    assert!(between > 0, "polls go on between actions: {log:?}");

    // The device's own params; the connection's on a connection action.
    let r = h
        .invoke(
            "c1/d2",
            "echo",
            map(&[("x", Value::UInt(7))]),
            Some(h.ptok(Perm::Read)),
        )
        .await;
    assert_eq!(
        r[0].value(),
        Some(map(&[
            ("id", "d2".into()),
            ("unit", Value::UInt(2)),
            ("x", Value::UInt(7))
        ]))
    );
    let r = h
        .invoke("c1", "scan", map(&[]), Some(h.ptok(Perm::Config)))
        .await;
    assert_eq!(r[0].value(), Some(map(&[("tag", Value::UInt(1))])));
    // The declared level is enforced.
    let r = h
        .invoke("c1", "scan", map(&[]), Some(h.ptok(Perm::Read)))
        .await;
    assert_eq!(status(&r), Some(Status::PermissionDenied));

    // The driver's error status reaches the caller.
    let r = h
        .invoke("c1/d1", "fail", map(&[]), Some(h.ptok(Perm::Read)))
        .await;
    assert_eq!(status(&r), Some(Status::InvalidParameter));
    // `disconnected` = the transport broke: the framework reconnects.
    let r = h
        .invoke("c1/d1", "break", map(&[]), Some(h.ptok(Perm::Read)))
        .await;
    assert_eq!(status(&r), Some(Status::Disconnected));
    wait("reconnected", Duration::from_secs(5), || {
        s.opens.load(Ordering::Relaxed) == 2
    })
    .await;

    // A stopped device takes no action.
    let r = h
        .invoke("c1/d1", "stop", map(&[]), Some(h.ptok(Perm::Config)))
        .await;
    assert_eq!(status(&r), Some(Status::Ok));
    let r = h
        .invoke(
            "c1/d1",
            "echo",
            map(&[("x", Value::UInt(1))]),
            Some(h.ptok(Perm::Read)),
        )
        .await;
    assert_eq!(status(&r), Some(Status::Disconnected));
    assert_eq!(s.overlaps.load(Ordering::Relaxed), 0);
    h.stop().await;
}

fn val(h: &H, path: &str) -> Option<Value> {
    h.ctx().last(path).map(|s| s.v)
}

fn t_of(h: &H, path: &str) -> Option<u64> {
    h.ctx().last(path).map(|s| s.t)
}

fn uint(h: &H, path: &str) -> u64 {
    match val(h, path) {
        Some(Value::UInt(n)) => n,
        v => panic!("{path}: {v:?}"),
    }
}

fn float(h: &H, path: &str) -> f64 {
    match val(h, path) {
        Some(Value::Float(n)) => n,
        v => panic!("{path}: {v:?}"),
    }
}

/// Ruling 12: counters grow with requests; RTT values move; a changed
/// value is published at most once every 10 s, at once on a read of the
/// node, never when unchanged; counters reset on a restart.
#[tokio::test(flavor = "multi_thread")]
async fn diagnostics_are_published_on_change_at_most_every_10_s() {
    let h = H::start(tree(2, two_points())).await;
    let started = Instant::now();
    let leaves = [
        "requests",
        "errors",
        "timeouts",
        "exceptions",
        "retries",
        "last_rtt_ms",
        "avg_rtt_ms",
    ];
    // Leaves on the connection and every device, published at the start.
    wait("first values", Duration::from_secs(5), || {
        ["c1", "c1/d1", "c1/d2"].iter().all(|n| {
            leaves
                .iter()
                .all(|l| val(&h, &format!("{n}/{l}")).is_some())
        })
    })
    .await;
    let meta = h.ctx().meta("c1/d1/avg_rtt_ms").unwrap();
    assert_eq!(meta.ty, Some(TypeCode::Number));
    assert!(h.ctx().meta("c1/d1/p/requests").is_none(), "not on points");
    let conn_t0 = t_of(&h, "c1/requests").unwrap();
    let d1_t0 = t_of(&h, "c1/d1/requests").unwrap();
    // A flush publishes the leaves in order; `avg_rtt_ms` comes last.
    let d1_last_t0 = t_of(&h, "c1/d1/avg_rtt_ms");
    let d2_t0 = t_of(&h, "c1/d2/requests").unwrap();

    // Polls every 20 ms change the counters, but nothing is published.
    tokio::time::sleep(Duration::from_millis(1500)).await;
    assert_eq!(
        t_of(&h, "c1/d1/requests"),
        Some(d1_t0),
        "not on every change"
    );

    // A read of the device publishes its counters at once.
    h.meta("c1/d1").await;
    wait("published on a read", Duration::from_secs(1), || {
        t_of(&h, "c1/d1/avg_rtt_ms") != d1_last_t0
    })
    .await;
    assert_ne!(t_of(&h, "c1/d1/requests"), Some(d1_t0));
    let requests = uint(&h, "c1/d1/requests");
    assert!(requests >= 20, "{requests} requests in 1.5 s");
    let failed: u64 = ["errors", "timeouts", "exceptions"]
        .iter()
        .map(|l| uint(&h, &format!("c1/d1/{l}")))
        .sum();
    for l in ["errors", "timeouts", "exceptions", "retries"] {
        assert!(uint(&h, &format!("c1/d1/{l}")) > 0, "{l}");
    }
    assert!(requests >= failed, "{requests} ≥ {failed}");
    let last = float(&h, "c1/d1/last_rtt_ms");
    assert!([10.0, 20.0, 30.0].contains(&last), "last_rtt_ms {last}");
    let avg = float(&h, "c1/d1/avg_rtt_ms");
    assert!(avg > 10.0 && avg < 30.0, "avg_rtt_ms {avg}");
    // The connection (not read) still shows its first values.
    assert_eq!(t_of(&h, "c1/requests"), Some(conn_t0));

    // Unchanged (no requests): a read publishes nothing.
    h.meta("c1/d2").await;
    tokio::time::sleep(Duration::from_millis(300)).await;
    assert_eq!(t_of(&h, "c1/d2/requests"), Some(d2_t0), "unchanged");

    // RTT values move with new requests; a read of a leaf is a read too.
    tokio::time::sleep(Duration::from_millis(300)).await;
    let t1 = t_of(&h, "c1/d1/avg_rtt_ms");
    h.meta("c1/d1/avg_rtt_ms").await;
    wait("published on a leaf read", Duration::from_secs(1), || {
        t_of(&h, "c1/d1/avg_rtt_ms") != t1
    })
    .await;
    assert_ne!(float(&h, "c1/d1/avg_rtt_ms"), avg, "avg_rtt_ms moves");

    // The connection's changed counters come with the 10 s period.
    wait("the 10 s publish", Duration::from_secs(12), || {
        t_of(&h, "c1/requests") != Some(conn_t0)
    })
    .await;
    let gap = t_of(&h, "c1/requests").unwrap() - conn_t0;
    assert!(gap >= 9_500_000, "published again after {gap} µs");
    assert!(started.elapsed() >= Duration::from_millis(9_500));
    assert!(uint(&h, "c1/requests") >= uint(&h, "c1/d1/requests"));
    assert_eq!(t_of(&h, "c1/d2/requests"), Some(d2_t0), "d2 never changed");

    // A device restart resets its counters (published at once).
    h.meta("c1/d1").await;
    tokio::time::sleep(Duration::from_millis(200)).await;
    let before = uint(&h, "c1/d1/requests");
    let conn_before = uint(&h, "c1/requests");
    let r = h
        .invoke("c1/d1", "restart", map(&[]), Some(h.ptok(Perm::Config)))
        .await;
    assert_eq!(status(&r), Some(Status::Ok));
    wait("device reset", Duration::from_secs(2), || {
        uint(&h, "c1/d1/requests") < before.min(10)
    })
    .await;
    // A connection restart resets the connection's.
    h.meta("c1").await;
    tokio::time::sleep(Duration::from_millis(200)).await;
    let conn_now = uint(&h, "c1/requests");
    assert!(
        conn_now >= conn_before,
        "a device restart keeps the connection's"
    );
    let r = h
        .invoke("c1", "restart", map(&[]), Some(h.ptok(Perm::Config)))
        .await;
    assert_eq!(status(&r), Some(Status::Ok));
    wait("connection reset", Duration::from_secs(2), || {
        uint(&h, "c1/requests") < conn_now.min(10)
    })
    .await;
    h.stop().await;
}

/// A stored device or point named like a diagnostics leaf keeps its node
/// (the leaf is left out); a new one may not take the name.
#[tokio::test(flavor = "multi_thread")]
async fn a_child_named_like_a_diagnostics_leaf_keeps_its_node() {
    let points = map(&[("errors", map(&[])), ("p", map(&[]))]);
    let h = H::start(tree(3, points)).await;
    wait("polled", Duration::from_secs(5), || {
        val(&h, "c1/d1/errors") == Some(Value::Float(1.0))
    })
    .await;
    wait("other leaves", Duration::from_secs(5), || {
        val(&h, "c1/d1/requests").is_some()
    })
    .await;
    // Still the point (a value of its own, not a counter), after a read.
    h.meta("c1/d1").await;
    tokio::time::sleep(Duration::from_millis(300)).await;
    assert_eq!(val(&h, "c1/d1/errors"), Some(Value::Float(1.0)));
    for (path, action) in [("c1/d1", "add_point"), ("c1", "add_device")] {
        let r = h
            .invoke(
                path,
                action,
                map(&[("name", "timeouts".into())]),
                Some(h.ptok(Perm::Config)),
            )
            .await;
        assert_eq!(status(&r), Some(Status::InvalidParameter), "{action}");
    }
    h.stop().await;
}
