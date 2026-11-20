//! A burst of new children costs O(1) puts of the parent's `~meta` per
//! child, amortized (docs/backlog.md §14): the parent's child list is put
//! once per batch, and its last put always carries the newest tree.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::unreachable,
    clippy::print_stdout,
    reason = "test code: a failed step fails the test"
)]

use std::sync::{Arc, Mutex};
use std::time::Duration;
use wyrm_core::{ActionMeta, NodeMeta};
use wyrm_link_sdk::{Link, LinkCtx, Result, TestHarness};

struct Bare;

impl Link for Bare {
    const NAME: &'static str = "bare";
    const VERSION: &'static str = "0";
    type Config = ();

    async fn start(_cfg: (), _ctx: LinkCtx) -> Result<Self> {
        Ok(Bare)
    }
}

type Puts = Arc<Mutex<Vec<NodeMeta>>>;

/// Every `~meta` put of `path`, in the order a subscriber gets them.
async fn follow(h: &TestHarness<Bare>, path: &str) -> (Puts, impl Sized) {
    let puts: Puts = Arc::default();
    let p2 = puts.clone();
    let sub = h
        .session()
        .declare_subscriber(h.key(path, "~meta"))
        .callback(move |s| {
            let meta: NodeMeta = wyrm_core::codec::from_slice(&s.payload().to_bytes()).unwrap();
            p2.lock().unwrap().push(meta);
        })
        .await
        .unwrap();
    (puts, sub)
}

/// Wait until the last put of the followed node has the node's `rev`.
async fn settled(h: &TestHarness<Bare>, path: &str, puts: &Puts) -> NodeMeta {
    for _ in 0..600 {
        let now = h.ctx().meta(path).unwrap();
        let last = puts.lock().unwrap().last().cloned();
        if let Some(last) = last.filter(|l| l.rev == now.rev) {
            return last;
        }
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
    panic!(
        "the last ~meta put of {path:?} is behind the tree (rev {:?})",
        h.ctx().meta(path).unwrap().rev
    );
}

fn names(range: std::ops::Range<usize>) -> Vec<String> {
    range.map(|i| format!("p{i}")).collect()
}

/// No put is older than the put before it. (Two tasks that changed one node
/// may each put its newest meta: the same `rev` twice, which a requester
/// ignores.)
fn revs_rise(puts: &Puts) {
    let puts = puts.lock().unwrap();
    assert!(
        puts.windows(2).all(|w| w[0].rev <= w[1].rev),
        "a ~meta put carried an older rev than the put before it"
    );
}

#[tokio::test(flavor = "multi_thread")]
async fn a_burst_of_children_puts_the_parent_once_per_batch() {
    const N: usize = 5_000;
    let h = TestHarness::<Bare>::start(()).await;
    let ctx = h.ctx().clone();
    ctx.declare_node("f", NodeMeta::folder()).await.unwrap();
    let (puts, _sub) = follow(&h, "f").await;
    let puts_before = ctx.parent_puts();

    for i in 0..N {
        ctx.declare_node(&format!("f/p{i}"), NodeMeta::number())
            .await
            .unwrap();
    }
    let last = settled(&h, "f", &puts).await;
    // the whole list, in the order of the declares, with the tree's rev
    assert_eq!(last.children, Some(names(0..N)));
    assert_eq!(last.children_count, Some(N as u32));
    assert_eq!(last.has_nodes, Some(false));
    revs_rise(&puts);
    // one put per child was N puts (and N²/2 names); a batch is hundreds of children
    let n = puts.lock().unwrap().len();
    assert!(
        (1..=N / 10).contains(&n),
        "{n} puts of the parent for {N} children"
    );
    assert_eq!(ctx.parent_puts() - puts_before, n as u64);

    // the same for a burst of removals
    puts.lock().unwrap().clear();
    for i in 0..N / 2 {
        ctx.remove_node(&format!("f/p{i}")).await.unwrap();
    }
    let last = settled(&h, "f", &puts).await;
    assert_eq!(last.children, Some(names(N / 2..N)));
    revs_rise(&puts);
    let n = puts.lock().unwrap().len();
    assert!(
        (1..=N / 20).contains(&n),
        "{n} puts of the parent for {} removals",
        N / 2
    );
    h.stop().await;
}

/// The batch task and the driver put the same node: the last put is the
/// newest meta, whoever made it.
#[tokio::test(flavor = "multi_thread")]
async fn the_last_put_of_a_parent_is_its_newest_meta() {
    let h = TestHarness::<Bare>::start(()).await;
    let ctx = h.ctx().clone();
    ctx.declare_node("f", NodeMeta::folder()).await.unwrap();
    let (puts, _sub) = follow(&h, "f").await;
    for round in 0..20 {
        let base = round * 300;
        let (a, b) = (ctx.clone(), ctx.clone());
        // children from two tasks, and the folder's own meta changed meanwhile
        let one = tokio::spawn(async move {
            for i in base..base + 150 {
                a.declare_node(&format!("f/p{i}"), NodeMeta::number())
                    .await
                    .unwrap();
            }
        });
        let two = tokio::spawn(async move {
            for i in base + 150..base + 300 {
                b.declare_node(&format!("f/q{i}"), NodeMeta::number())
                    .await
                    .unwrap();
                if i % 50 == 0 {
                    b.declare_action("f", &format!("a{i}"), ActionMeta::default())
                        .await
                        .unwrap();
                }
            }
        });
        one.await.unwrap();
        two.await.unwrap();
        let last = settled(&h, "f", &puts).await;
        let tree = ctx.meta("f").unwrap();
        assert_eq!(last.children_count, Some((base + 300) as u32));
        assert_eq!(last.children, tree.children);
        assert_eq!(last.actions, tree.actions);
        revs_rise(&puts);
    }
    h.stop().await;
}

/// One child after a quiet time: the parent's list is put at once, as before.
#[tokio::test(flavor = "multi_thread")]
async fn a_single_child_puts_the_parent_at_once() {
    let h = TestHarness::<Bare>::start(()).await;
    let ctx = h.ctx().clone();
    ctx.declare_node("f", NodeMeta::folder()).await.unwrap();
    let (puts, _sub) = follow(&h, "f").await;
    for i in 0..5 {
        tokio::time::sleep(Duration::from_millis(600)).await;
        let before = ctx.parent_puts();
        ctx.declare_node(&format!("f/p{i}"), NodeMeta::number())
            .await
            .unwrap();
        // put by the declare itself, before it returned
        assert_eq!(ctx.parent_puts(), before + 1);
        let last = settled(&h, "f", &puts).await;
        assert_eq!(last.children, Some(names(0..i + 1)));
    }
    h.stop().await;
}

/// A stopped link puts nothing more, and its batch task ends with it.
#[tokio::test(flavor = "multi_thread")]
async fn a_stopped_link_drops_what_waited() {
    let h = TestHarness::<Bare>::start(()).await;
    let ctx = h.ctx().clone();
    ctx.declare_node("f", NodeMeta::folder()).await.unwrap();
    for i in 0..2_000 {
        ctx.declare_node(&format!("f/p{i}"), NodeMeta::number())
            .await
            .unwrap();
    }
    h.stop().await;
    assert!(ctx.is_closed());
    let after = ctx.parent_puts();
    tokio::time::sleep(Duration::from_millis(700)).await;
    assert_eq!(ctx.parent_puts(), after);
    assert!(ctx
        .declare_node("f/late", NodeMeta::number())
        .await
        .is_err());
}
