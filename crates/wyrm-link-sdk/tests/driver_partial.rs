//! A device that answers for some points only (one batch of its poll timed
//! out): the points without an answer take the quality ladder on their own,
//! while the device stays connected.

use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Duration;
use wyrm_core::meta::Writable;
use wyrm_core::{NodeMeta, Quality, Value};
use wyrm_link_sdk::driver::{Driver, DriverError, Framework, NodeState, PointId, Tree};
use wyrm_link_sdk::{Params, TestHarness};

/// While set, point `q` gets no answer.
static Q_SILENT: AtomicBool = AtomicBool::new(false);

#[derive(Debug, Clone, PartialEq, Params)]
struct Conn {}

#[derive(Debug, Clone, PartialEq, Params)]
struct Dev {}

#[derive(Debug, Clone, PartialEq, Params)]
struct Point {}

struct Partial;

impl Driver for Partial {
    const NAME: &'static str = "partial";
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
        plan.iter()
            .map(|id| {
                let r = if id == "q" && Q_SILENT.load(Ordering::SeqCst) {
                    Err(DriverError::Device("batch timed out".into()))
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
        None
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

/// Ruling P30: `q` without an answer goes `uncertain` with its last value,
/// then `bad` after `stale_misses` polls, and `good` again when it answers;
/// `p` and the device are not touched.
#[tokio::test(flavor = "multi_thread")]
async fn unanswered_points_take_the_ladder_alone() {
    let points = map(&[("p", map(&[])), ("q", map(&[]))]);
    let dev = map(&[("points", points)]);
    let conn = map(&[("devices", map(&[("d1", dev)]))]);
    let h = TestHarness::<Framework<Partial>>::start(Tree(map(&[(
        "connections",
        map(&[("c1", conn)]),
    )])))
    .await;
    let q = |h: &TestHarness<Framework<Partial>>, s: &str| h.ctx().last(s).map(|s| (s.v, s.q));
    let good = Some((Value::Float(1.0), Quality::Good));
    wait("first values", || {
        q(&h, "c1/d1/p") == good && q(&h, "c1/d1/q") == good
    })
    .await;

    Q_SILENT.store(true, Ordering::SeqCst);
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
    assert_eq!(q(&h, "c1/d1/p"), good, "p untouched");
    let status = h.ctx().last("c1/d1/status").map(|s| s.v);
    assert_eq!(
        status,
        Some(Value::UInt(NodeState::Connected as u64)),
        "the device answered"
    );

    Q_SILENT.store(false, Ordering::SeqCst);
    wait("q good again", || q(&h, "c1/d1/q") == good).await;
    h.stop().await;
}
