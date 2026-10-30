//! The device state under the quality ladder when polls and pings disagree:
//! a device whose polls fail stays `Failed` with its error, whatever its
//! pings do, until a poll answers.

use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Duration;
use wyrm_core::meta::Writable;
use wyrm_core::{NodeMeta, Quality, Value};
use wyrm_link_sdk::driver::{Driver, DriverError, Framework, NodeState, PointId, Tree};
use wyrm_link_sdk::{Params, TestHarness};

/// While set, polls get no answer.
static POLL_DEAD: AtomicBool = AtomicBool::new(false);
/// While set, pings get no answer.
static PING_DEAD: AtomicBool = AtomicBool::new(false);

#[derive(Debug, Clone, PartialEq, Params)]
struct Conn {}

#[derive(Debug, Clone, PartialEq, Params)]
struct Dev {}

#[derive(Debug, Clone, PartialEq, Params)]
struct Point {}

struct Ladder;

impl Driver for Ladder {
    const NAME: &'static str = "ladder";
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
        if PING_DEAD.load(Ordering::SeqCst) {
            Err(DriverError::Device("ping not answered".into()))
        } else {
            Ok(())
        }
    }

    fn plan(_dev: &Dev, points: &[(PointId, Point)]) -> Self::Plan {
        points.iter().map(|(id, _)| id.clone()).collect()
    }

    async fn poll(
        _t: &mut (),
        _dev: &Dev,
        plan: &Self::Plan,
    ) -> Vec<(PointId, Result<Value, DriverError>)> {
        let dead = POLL_DEAD.load(Ordering::SeqCst);
        plan.iter()
            .map(|id| {
                let r = if dead {
                    Err(DriverError::Device("poll not answered".into()))
                } else {
                    Ok(Value::Float(1.0))
                };
                (id.clone(), r)
            })
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

/// Final re-review N1: the device fails on its polls, answers pings for a
/// while, then goes silent. It must stay `Failed` throughout, and come back
/// `Connected` only when a poll answers.
#[tokio::test(flavor = "multi_thread")]
async fn failed_polls_keep_the_device_failed() {
    let points = map(&[("p", map(&[]))]);
    let dev = map(&[("points", points)]);
    let conn = map(&[("devices", map(&[("d1", dev)]))]);
    let h = TestHarness::<Framework<Ladder>>::start(Tree(map(&[(
        "connections",
        map(&[("c1", conn)]),
    )])))
    .await;
    let state = |h: &TestHarness<Framework<Ladder>>| h.ctx().last("c1/d1/status").map(|s| s.v);
    let is = |s: NodeState| Some(Value::UInt(s as u64));
    let q = |h: &TestHarness<Framework<Ladder>>| h.ctx().last("c1/d1/p").map(|s| s.q);
    wait("connected", || state(&h) == is(NodeState::Connected)).await;
    wait("good", || q(&h) == Some(Quality::Good)).await;

    POLL_DEAD.store(true, Ordering::SeqCst);
    wait("failed", || state(&h) == is(NodeState::Failed)).await;
    assert_eq!(q(&h), Some(Quality::Bad));
    // Pings answer: the device stays failed, the point stays bad.
    tokio::time::sleep(Duration::from_millis(400)).await;
    assert_eq!(
        state(&h),
        is(NodeState::Failed),
        "a ping does not hide failed polls"
    );
    assert_eq!(q(&h), Some(Quality::Bad));
    // Everything silent: still failed.
    PING_DEAD.store(true, Ordering::SeqCst);
    tokio::time::sleep(Duration::from_millis(400)).await;
    assert_eq!(
        state(&h),
        is(NodeState::Failed),
        "a dead device stays failed"
    );

    POLL_DEAD.store(false, Ordering::SeqCst);
    PING_DEAD.store(false, Ordering::SeqCst);
    wait("connected again", || state(&h) == is(NodeState::Connected)).await;
    wait("good again", || q(&h) == Some(Quality::Good)).await;
    h.stop().await;
}
