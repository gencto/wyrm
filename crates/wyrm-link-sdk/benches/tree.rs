//! What the node tree costs a link (performance audit items 4, 5 and 17).
//! `cargo bench -p wyrm-link-sdk --bench tree`.
//!
//! 1. **Declare** 1 000 / 10 000 / 30 000 points under one folder (`TREE_DECLARE_ONLY=<n>`
//!    runs `tree/declare/<n>` alone, in a process of its own, for an honest `peak_rss_mib`):
//!    * `tree/declare_pure/<n>`: `NodeTree::declare` plus the `~meta` bytes of one put of
//!      the point and one of its parent (which lists every child) per declare, no Zenoh:
//!      what a parent put per child costs. `LinkCtx` puts the parent once per batch;
//!    * `tree/declare/<n>`: `LinkCtx::declare_node` on a link of the `TestHarness`, with a
//!      subscriber on the link's `**/~meta` that counts the puts and their bytes (the
//!      folder's own apart: `parent_puts`, `parent_mib`) and the bytes still held when
//!      every put is delivered (`kept_mib`: the tree and Zenoh's own state).
//! 2. **Fan-in** (`tree/fan_in/10000`): a wildcard `get` that hits one node of 10 000; the
//!    runtime walks the whole tree for it. Beside it `tree/meta_one/10000`, the plain `get` of
//!    the same node.
//! 3. **`view=list`** of 1 000 children, each `is: "wy:number"` (a profile name, so the runtime
//!    resolves the profile per child) and, beside it, the same children without `is`.
//!
//! One `PERF` line per figure (`tool/perf.sh`).

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::print_stdout,
    reason = "a benchmark run by hand: a failed step ends it, figures go to stdout"
)]

use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};
use wyrm_bench::{Allocs, Lat, Perf, Usage};
use wyrm_core::codec::to_vec;
use wyrm_core::{Attachment, NodeMeta};
use wyrm_link_sdk::harness::TestHarness;
use wyrm_link_sdk::tree::NodeTree;
use wyrm_link_sdk::{Link, LinkCtx, Result};

#[global_allocator]
static A: wyrm_bench::Counting = wyrm_bench::Counting;

/// A link that declares nothing itself: the bench declares through its context.
struct Bare;

impl Link for Bare {
    const NAME: &'static str = "bench";
    const VERSION: &'static str = "0";
    type Config = ();

    async fn start(_cfg: (), _ctx: LinkCtx) -> Result<Self> {
        Ok(Bare)
    }
}

async fn harness() -> TestHarness<Bare> {
    TestHarness::<Bare>::start_with((), |c| {
        // the bench reads one key many times: no read budget
        c.read_rate_limit = None;
        c.overlays = false;
    })
    .await
}

fn declare_pure(n: usize) {
    let mut tree = NodeTree::new(NodeMeta::default());
    tree.declare("f", NodeMeta::folder()).unwrap();
    let (mut puts, mut bytes) = (0u64, 0u64);
    let a0 = Allocs::read();
    let t0 = Instant::now();
    for i in 0..n {
        let path = format!("f/p{i}");
        let ch = tree.declare(&path, NodeMeta::number().unit("°C")).unwrap();
        if ch.node {
            bytes += to_vec(&tree.full(&path, false).unwrap()).unwrap().len() as u64;
            puts += 1;
        }
        if let Some(p) = ch.parent {
            bytes += to_vec(&tree.full(&p, false).unwrap()).unwrap().len() as u64;
            puts += 1;
        }
    }
    let wall = t0.elapsed();
    let allocs = Allocs::read().since(a0);
    println!(
        "{}",
        Perf::new(&format!("tree/declare_pure/{n}"))
            .n(n as u64)
            .per_s(n as f64 / wall.as_secs_f64())
            .allocs(allocs, n as u64)
            .num("total_ms", wall.as_secs_f64() * 1e3)
            .field("meta_puts", puts)
            .num("meta_mib", bytes as f64 / 1_048_576.0)
            .num("kept_mib", allocs.live() as f64 / 1_048_576.0)
            .field(
                "node_bytes",
                std::mem::size_of::<wyrm_link_sdk::tree::Node>(),
            )
            .note("NodeTree::declare + encode of point and parent ~meta, no Zenoh")
    );
}

async fn declare(n: usize) {
    let h = harness().await;
    let puts = Arc::new(AtomicU64::new(0));
    let bytes = Arc::new(AtomicU64::new(0));
    let parent_puts = Arc::new(AtomicU64::new(0));
    let parent_bytes = Arc::new(AtomicU64::new(0));
    let (p2, b2) = (puts.clone(), bytes.clone());
    let (pp2, pb2) = (parent_puts.clone(), parent_bytes.clone());
    let sub = h
        .session()
        .declare_subscriber("wy/test/downstream/bench/**/~meta")
        .callback(move |s| {
            let len = s.payload().len() as u64;
            p2.fetch_add(1, Ordering::Relaxed);
            b2.fetch_add(len, Ordering::Relaxed);
            if s.key_expr().as_str() == "wy/test/downstream/bench/f/~meta" {
                pp2.fetch_add(1, Ordering::Relaxed);
                pb2.fetch_add(len, Ordering::Relaxed);
            }
        })
        .await
        .unwrap();
    let ctx = h.ctx().clone();
    ctx.declare_node("f", NodeMeta::folder()).await.unwrap();
    tokio::time::sleep(Duration::from_millis(100)).await;
    let (p0, b0) = (puts.load(Ordering::Relaxed), bytes.load(Ordering::Relaxed));
    let (pp0, pb0) = (
        parent_puts.load(Ordering::Relaxed),
        parent_bytes.load(Ordering::Relaxed),
    );
    let u0 = Usage::read();
    let a0 = Allocs::read();
    let t0 = Instant::now();
    let mut lat = Lat::with_capacity(n);
    for i in 0..n {
        let s = Instant::now();
        ctx.declare_node(&format!("f/p{i}"), NodeMeta::number().unit("°C"))
            .await
            .unwrap();
        lat.push(s.elapsed());
    }
    let wall = t0.elapsed();
    let allocs = Allocs::read().since(a0);
    let u1 = Usage::read();
    // the subscriber runs on Zenoh's threads: wait until it has seen every put
    let mut last = u64::MAX;
    for _ in 0..100 {
        let now = puts.load(Ordering::Relaxed);
        if now == last {
            break;
        }
        last = now;
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
    let (p, b) = (
        puts.load(Ordering::Relaxed) - p0,
        bytes.load(Ordering::Relaxed) - b0,
    );
    let (pp, pb) = (
        parent_puts.load(Ordering::Relaxed) - pp0,
        parent_bytes.load(Ordering::Relaxed) - pb0,
    );
    let kept = Allocs::read().since(a0).live();
    let peak = Usage::read().peak_rss_bytes;
    println!(
        "{}",
        Perf::new(&format!("tree/declare/{n}"))
            .lat(&mut lat)
            .per_s(n as f64 / wall.as_secs_f64())
            .cpu_pct(u1.cpu_pct_since(&u0))
            .rss(u1.rss_bytes)
            .allocs(allocs, n as u64)
            .num("total_ms", wall.as_secs_f64() * 1e3)
            .field("meta_puts", p)
            .num("meta_mib", b as f64 / 1_048_576.0)
            .field("parent_puts", pp)
            .num("parent_mib", pb as f64 / 1_048_576.0)
            .num("kept_mib", kept as f64 / 1_048_576.0)
            .num(
                "peak_rss_mib",
                peak.map_or(f64::NAN, |b| b as f64 / 1_048_576.0),
            )
            .note("LinkCtx::declare_node over in-memory Zenoh, ~meta puts counted")
    );
    drop(sub);
    h.stop().await;
}

/// Replies of one `get` (any number), timed.
async fn get_all(h: &TestHarness<Bare>, sel: &str) -> (Duration, usize) {
    let t = Instant::now();
    let r = h.query(sel, None, Attachment::default()).await;
    (t.elapsed(), r.len())
}

async fn fan_in(n: usize) {
    let h = harness().await;
    let ctx = h.ctx().clone();
    for f in 0..10 {
        ctx.declare_node(&format!("f{f}"), NodeMeta::folder())
            .await
            .unwrap();
    }
    for i in 0..n {
        ctx.declare_node(&format!("f{}/p{i}", i % 10), NodeMeta::number())
            .await
            .unwrap();
    }
    // one node: f7/p17
    for (name, sel) in [
        ("tree/fan_in", "wy/test/downstream/bench/*/p17/~meta"),
        ("tree/meta_one", "wy/test/downstream/bench/f7/p17/~meta"),
    ] {
        for _ in 0..20 {
            get_all(&h, sel).await;
        }
        let rounds = 300;
        let mut lat = Lat::with_capacity(rounds);
        let a0 = Allocs::read();
        let t0 = Instant::now();
        for _ in 0..rounds {
            let (d, got) = get_all(&h, sel).await;
            assert_eq!(got, 1, "{sel}");
            lat.push(d);
        }
        let wall = t0.elapsed();
        let allocs = Allocs::read().since(a0);
        println!(
            "{}",
            Perf::new(&format!("{name}/{n}"))
                .lat(&mut lat)
                .per_s(rounds as f64 / wall.as_secs_f64())
                .allocs(allocs, rounds as u64)
                .note("get that answers one ~meta of a 10k-node tree")
        );
    }
    h.stop().await;
}

async fn list(children: usize, profile: bool) {
    let h = harness().await;
    let ctx = h.ctx().clone();
    ctx.declare_node("f", NodeMeta::folder()).await.unwrap();
    for i in 0..children {
        let m = NodeMeta::number().unit("°C");
        let m = if profile { m.is("wy:number") } else { m };
        ctx.declare_node(&format!("f/p{i}"), m).await.unwrap();
    }
    let sel = "wy/test/downstream/bench/f/~meta?view=list";
    for _ in 0..10 {
        get_all(&h, sel).await;
    }
    let rounds = 200;
    let mut lat = Lat::with_capacity(rounds);
    let a0 = Allocs::read();
    let t0 = Instant::now();
    for _ in 0..rounds {
        let (d, got) = get_all(&h, sel).await;
        assert_eq!(got, 1);
        lat.push(d);
    }
    let wall = t0.elapsed();
    let allocs = Allocs::read().since(a0);
    let name = if profile {
        format!("tree/list_profile/{children}")
    } else {
        format!("tree/list_plain/{children}")
    };
    println!(
        "{}",
        Perf::new(&name)
            .lat(&mut lat)
            .per_s(rounds as f64 / wall.as_secs_f64())
            .allocs(allocs, rounds as u64)
            .note(if profile {
                "view=list, children is:wy:number"
            } else {
                "view=list, children without is"
            })
    );
    h.stop().await;
}

fn main() {
    let rt = tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()
        .unwrap();
    if let Some(n) = std::env::var("TREE_DECLARE_ONLY")
        .ok()
        .and_then(|n| n.parse().ok())
    {
        rt.block_on(declare(n));
        return;
    }
    for n in [1_000, 10_000, 30_000] {
        declare_pure(n);
    }
    rt.block_on(async {
        for n in [1_000, 10_000, 30_000] {
            declare(n).await;
        }
        fan_in(10_000).await;
        list(1_000, false).await;
        list(1_000, true).await;
    });
}
