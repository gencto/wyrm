//! Optional `Driver` hooks with defaults: `poll_timeout` (the poll's
//! whole-operation bound) and `republish` (heartbeat of unchanged values),
//! through a small test driver.

use std::time::Duration;
use wyrm_core::meta::Writable;
use wyrm_core::{NodeMeta, Quality, Value};
use wyrm_link_sdk::driver::{Driver, DriverError, Framework, PointId, Tree};
use wyrm_link_sdk::{Params, TestHarness};

#[derive(Debug, Clone, PartialEq, Params)]
struct Conn {
    /// Time one poll takes.
    #[param(default = 0)]
    poll_ms: u32,
    /// `io_timeout`.
    #[param(default = 100)]
    io_ms: u32,
    /// `poll_timeout`; 0 = the default hook (`io_timeout`).
    #[param(default = 0)]
    poll_bound_ms: u32,
}

#[derive(Debug, Clone, PartialEq, Params)]
struct Dev {
    /// 0 = no heartbeat.
    #[param(default = 0.0)]
    republish_s: f64,
}

#[derive(Debug, Clone, PartialEq, Params)]
struct Point {
    #[param(default = 0.05)]
    poll_s: f64,
}

/// Every point reads the constant 1.0, `poll_ms` late.
struct Hooks;

/// [`Hooks`] without its own hooks: the trait defaults apply.
struct Plain;

struct Transport(Duration);

/// The `Driver` methods both test drivers share.
macro_rules! common {
    () => {
        const VERSION: &'static str = "0.1.0";
        type Conn = Conn;
        type Dev = Dev;
        type Point = Point;
        type Transport = Transport;
        type Plan = Vec<PointId>;

        async fn open(conn: &Conn) -> Result<Transport, DriverError> {
            Ok(Transport(Duration::from_millis(conn.poll_ms.into())))
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
            tokio::time::sleep(t.0).await;
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

        fn io_timeout(conn: &Conn) -> Duration {
            Duration::from_millis(conn.io_ms.into())
        }
    };
}

impl Driver for Hooks {
    const NAME: &'static str = "hooks";
    common!();

    fn poll_timeout(conn: &Conn, plan: &Self::Plan) -> Duration {
        match conn.poll_bound_ms {
            0 => Self::io_timeout(conn),
            ms => Duration::from_millis(u64::from(ms) * plan.len() as u64),
        }
    }

    fn republish(dev: &Dev) -> Option<Duration> {
        (dev.republish_s > 0.0).then(|| Duration::from_secs_f64(dev.republish_s))
    }
}

impl Driver for Plain {
    const NAME: &'static str = "plain";
    common!();
}

fn map(kv: &[(&str, Value)]) -> Value {
    Value::Map(
        kv.iter()
            .map(|(k, v)| ((*k).to_owned(), v.clone()))
            .collect(),
    )
}

/// `c1/d1/p` (and `c1/d1/q`) with these connection and device params.
fn tree(conn: &[(&str, Value)], dev: &[(&str, Value)]) -> Tree {
    let points = map(&[("p", map(&[])), ("q", map(&[]))]);
    let mut d = dev.to_vec();
    d.push(("points", points));
    let mut c = conn.to_vec();
    c.push(("devices", map(&[("d1", map(&d))])));
    Tree(map(&[("connections", map(&[("c1", map(&c))]))]))
}

async fn wait(what: &str, mut f: impl FnMut() -> bool) {
    let deadline = tokio::time::Instant::now() + Duration::from_secs(10);
    while !f() {
        assert!(tokio::time::Instant::now() < deadline, "timeout: {what}");
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
}

/// The source time of the last `c1/d1/p` sample.
fn t_of<D: Driver>(h: &TestHarness<Framework<D>>) -> Option<u64> {
    h.ctx().last("c1/d1/p").map(|s| s.t)
}

/// Ruling 9: an unchanged value is put again once `republish_s` passed
/// since its last sample; 0 (and a driver without the hook) = never.
#[tokio::test(flavor = "multi_thread")]
async fn republish_after_n_seconds() {
    let on =
        TestHarness::<Framework<Hooks>>::start(tree(&[], &[("republish_s", Value::Float(0.3))]))
            .await;
    let off =
        TestHarness::<Framework<Hooks>>::start(tree(&[], &[("republish_s", Value::Float(0.0))]))
            .await;
    let plain =
        TestHarness::<Framework<Plain>>::start(tree(&[], &[("republish_s", Value::Float(0.3))]))
            .await;
    wait("first values", || {
        t_of(&on).is_some() && t_of(&off).is_some() && t_of(&plain).is_some()
    })
    .await;
    let (t_on, t_off, t_plain) = (t_of(&on), t_of(&off), t_of(&plain));
    wait("republished", || t_of(&on) != t_on).await;
    let step = t_of(&on).unwrap() - t_on.unwrap();
    // Not on every 50 ms poll: only once 300 ms passed.
    assert!(step >= 300_000, "republished after {step} µs");
    let s = on.ctx().last("c1/d1/p").unwrap();
    assert_eq!((s.v, s.q), (Value::Float(1.0), Quality::Good));
    tokio::time::sleep(Duration::from_millis(800)).await;
    assert_eq!(t_of(&off), t_off, "republish_s = 0: never");
    assert_eq!(t_of(&plain), t_plain, "default hook: never");
    for h in [on, off] {
        h.stop().await;
    }
    plain.stop().await;
}

/// Ruling 8: the `poll_timeout` hook bounds a poll; the default is
/// `io_timeout`. A 300 ms poll is cut at an `io_timeout` of 100 ms, and
/// passes with a bound of 2 × 400 ms.
#[tokio::test(flavor = "multi_thread")]
async fn poll_timeout_bounds_the_poll() {
    let slow = [("poll_ms", Value::UInt(300)), ("io_ms", Value::UInt(100))];
    let mut bounded = slow.to_vec();
    bounded.push(("poll_bound_ms", Value::UInt(400)));
    let cut = TestHarness::<Framework<Plain>>::start(tree(&slow, &[])).await;
    let hook = TestHarness::<Framework<Hooks>>::start(tree(&bounded, &[])).await;
    wait("polled within the hook's bound", || t_of(&hook).is_some()).await;
    tokio::time::sleep(Duration::from_millis(600)).await;
    assert!(t_of(&cut).is_none(), "cut at io_timeout: no value");
    cut.stop().await;
    hook.stop().await;
}
