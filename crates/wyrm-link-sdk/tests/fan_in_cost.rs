//! A wildcard `get` that can meet no key of the link costs the same on a large tree as on
//! a small one (docs/backlog.md §14): the stored read of every pattern subscriber
//! (`…/**/~val`) reaches every link, and a link whose values a storage answers has nothing
//! to say to it. It walked its whole tree for each such read before, two keys per node.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    reason = "test code: a failed step fails the test"
)]

use wyrm_bench::Allocs;
use wyrm_core::{NodeMeta, Quality};
use wyrm_link_sdk::harness::TestHarness;
use wyrm_link_sdk::{Link, LinkCtx, Result};

#[global_allocator]
static A: wyrm_bench::Counting = wyrm_bench::Counting;

struct Bare;

impl Link for Bare {
    const NAME: &'static str = "bench";
    const VERSION: &'static str = "0";
    type Config = ();

    async fn start(_cfg: (), _ctx: LinkCtx) -> Result<Self> {
        Ok(Bare)
    }
}

const ROUNDS: u64 = 40;

/// Allocations of one `get` of `sel` on a link with `points` points that all have a value.
async fn allocs_per_get(points: usize, sel: &str, replies: usize) -> f64 {
    let h = TestHarness::<Bare>::start_with((), |c| {
        c.read_rate_limit = None;
        c.overlays = false;
    })
    .await;
    let ctx = h.ctx().clone();
    ctx.declare_node("f", NodeMeta::folder()).await.unwrap();
    for i in 0..points {
        let p = format!("f/p{i}");
        ctx.declare_node(&p, NodeMeta::number()).await.unwrap();
        ctx.update(&p, i as f64, Quality::Good, 1).await.unwrap();
    }
    for _ in 0..5 {
        h.query(sel, None, Default::default()).await;
    }
    let a0 = Allocs::read();
    for _ in 0..ROUNDS {
        let got = h.query(sel, None, Default::default()).await.len();
        assert_eq!(got, replies, "{sel}");
    }
    let a = Allocs::read().since(a0);
    h.stop().await;
    a.calls_per(ROUNDS)
}

#[tokio::test(flavor = "multi_thread")]
async fn a_fan_in_read_does_not_pay_per_node() {
    for sel in [
        // the stored read of `subscribe("wy/<site>/downstream/**")`
        "wy/test/downstream/**/~val",
        "wy/test/downstream/bench/**/~val",
        // and other reads no node answers
        "wy/test/downstream/bench/**/~set",
    ] {
        let small = allocs_per_get(10, sel, 0).await;
        let large = allocs_per_get(600, sel, 0).await;
        // the walk made two keys per node: 1200 allocations more per read. The slack is for
        // what the session's own tasks allocate meanwhile.
        assert!(
            large < small + 300.0,
            "{sel}: {large:.0} allocations per read on 600 points, {small:.0} on 10"
        );
    }
    // One `~meta` of many: the walk stays (it finds the node), but only the answered key is
    // copied; before, each node cost two keys. (One test: the allocator counts the process.)
    let sel = "wy/test/downstream/bench/*/p7/~meta";
    let small = allocs_per_get(10, sel, 1).await;
    let large = allocs_per_get(600, sel, 1).await;
    assert!(
        large < small + 300.0,
        "{sel}: {large:.0} allocations per read on 600 points, {small:.0} on 10"
    );
}
