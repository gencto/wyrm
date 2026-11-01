//! Security review LNK-2: a panic in a driver call (a bug in a third-party decoder fed by a
//! hostile device) never freezes a connection as `Connected` with its last good values.

use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Duration;
use wyrm_core::meta::Writable;
use wyrm_core::{NodeMeta, Quality, Value};
use wyrm_link_sdk::driver::{Driver, DriverError, Framework, NodeState, PointId, Tree};
use wyrm_link_sdk::{Params, TestHarness};

/// While set, polls and pings panic.
static PANIC: AtomicBool = AtomicBool::new(false);

#[derive(Debug, Clone, PartialEq, Params)]
struct Conn {}

#[derive(Debug, Clone, PartialEq, Params)]
struct Dev {}

#[derive(Debug, Clone, PartialEq, Params)]
struct Point {}

struct Panicky;

impl Driver for Panicky {
    const NAME: &'static str = "panicky";
    const VERSION: &'static str = "0.1.0";
    type Conn = Conn;
    type Dev = Dev;
    type Point = Point;
    type Transport = ();
    type Plan = Vec<PointId>;

    async fn open(_conn: &Conn) -> Result<(), DriverError> {
        Ok(())
    }

    async fn ping(_t: &mut (), _dev: &Dev) -> Result<(), DriverError> {
        if PANIC.load(Ordering::SeqCst) {
            panic!("ping bug");
        }
        Ok(())
    }

    fn plan(_dev: &Dev, points: &[(PointId, Point)]) -> Self::Plan {
        points.iter().map(|(id, _)| id.clone()).collect()
    }

    async fn poll(
        _t: &mut (),
        _dev: &Dev,
        plan: &Self::Plan,
    ) -> Vec<(PointId, Result<Value, DriverError>)> {
        if PANIC.load(Ordering::SeqCst) {
            panic!("poll bug");
        }
        plan.iter()
            .map(|id| (id.clone(), Ok(Value::Float(1.0))))
            .collect()
    }

    async fn write(
        _t: &mut (),
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

    fn ping_period(_dev: &Dev) -> Option<Duration> {
        Some(Duration::from_millis(30))
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

async fn wait(what: &str, mut f: impl FnMut() -> bool) {
    let deadline = tokio::time::Instant::now() + Duration::from_secs(10);
    while !f() {
        assert!(tokio::time::Instant::now() < deadline, "timeout: {what}");
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
}

/// The connection fails with the panic as its error, its points go bad, and it comes back
/// once the driver stops panicking.
#[tokio::test(flavor = "multi_thread")]
async fn a_driver_panic_fails_the_connection() {
    let points = map(&[("p", map(&[]))]);
    let dev = map(&[("points", points)]);
    let conn = map(&[("devices", map(&[("d1", dev)]))]);
    let h = TestHarness::<Framework<Panicky>>::start(Tree(map(&[(
        "connections",
        map(&[("c1", conn)]),
    )])))
    .await;
    type H = TestHarness<Framework<Panicky>>;
    let state = |h: &H| h.ctx().last("c1/status").map(|s| s.v);
    let is = |s: NodeState| Some(Value::UInt(s as u64));
    let q = |h: &H| h.ctx().last("c1/d1/p").map(|s| s.q);
    wait("connected", || state(&h) == is(NodeState::Connected)).await;
    wait("good", || q(&h) == Some(Quality::Good)).await;

    PANIC.store(true, Ordering::SeqCst);
    wait("failed", || state(&h) == is(NodeState::Failed)).await;
    wait("bad", || q(&h) == Some(Quality::Bad)).await;
    let err = h.ctx().last("c1/error").map(|s| s.v);
    assert!(
        matches!(&err, Some(Value::Str(e)) if e.contains("panicked")),
        "{err:?}"
    );

    PANIC.store(false, Ordering::SeqCst);
    wait("connected again", || state(&h) == is(NodeState::Connected)).await;
    wait("good again", || q(&h) == Some(Quality::Good)).await;
    h.stop().await;
}
