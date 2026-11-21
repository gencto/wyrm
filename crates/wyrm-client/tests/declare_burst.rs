//! A client that lists while a link declares a burst of children gets every
//! child, although the parent's `~meta` (its `children`) is put once per
//! batch and not once per child (docs/backlog.md §14).

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::unreachable,
    clippy::print_stdout,
    reason = "test code: a failed step fails the test"
)]

use std::collections::BTreeSet;
use std::sync::Arc;
use std::time::Duration;
use wyrm_client::{EventStream, ListEvent, SigningTokens, WyrmClient};
use wyrm_core::NodeMeta;
use wyrm_link_sdk::harness::{SITE, TEST_KEY_SEED};
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

/// Follow a `list` stream until it holds `want` children. Every child comes
/// once (`Refreshed` replaces what is known); none is removed.
async fn collect_children(mut s: EventStream<ListEvent>, want: usize) -> BTreeSet<String> {
    let mut names = BTreeSet::new();
    let all = async {
        while names.len() < want {
            match s.next().await.expect("stream open") {
                ListEvent::Refreshed(snap) => {
                    names = snap.into_iter().map(|c| c.name).collect();
                }
                ListEvent::Added(c) => {
                    assert!(names.insert(c.name.clone()), "{} added twice", c.name);
                }
                ListEvent::Changed(_) => {}
                e => panic!("unexpected {e:?}"),
            }
        }
    };
    if tokio::time::timeout(Duration::from_secs(120), all)
        .await
        .is_err()
    {
        panic!("the list holds {} of {want} children", names.len());
    }
    names
}

/// Open a list. While children are declared faster than a snapshot is read,
/// the client answers `busy` ("children kept changing", as it always did):
/// the caller asks again.
async fn open_list(c: &WyrmClient, node: &str) -> EventStream<ListEvent> {
    for _ in 0..10_000 {
        match c.list(node).await {
            Ok(s) => return s,
            Err(e) if e.is(wyrm_core::Status::Busy) => {
                tokio::time::sleep(Duration::from_millis(1)).await;
            }
            Err(e) => panic!("list: {e}"),
        }
    }
    panic!("the list stayed busy");
}

/// Each child's own `~meta` is put when it is declared, and a snapshot is
/// answered from the tree: lists opened before the burst and at moments of
/// it all end with the 10 000 children. The folder's parent sees the folder
/// change until its last put carries the whole list.
#[tokio::test(flavor = "multi_thread")]
async fn list_during_a_declare_burst_gets_every_child() {
    const N: usize = 10_000;
    let h = TestHarness::<Bare>::start_with((), |c| {
        // the lists read the same keys many times: no read budget
        c.read_rate_limit = None;
    })
    .await;
    let key = ed25519_dalek::SigningKey::from_bytes(&TEST_KEY_SEED);
    let c = WyrmClient::new(h.session().clone())
        .with_tokens(Arc::new(SigningTokens::new(key, SITE)))
        .with_timeout(Duration::from_secs(10));
    let root = h.key("", "");
    h.ctx()
        .declare_node("burst", NodeMeta::folder())
        .await
        .unwrap();
    let node = format!("{root}/burst");
    // lists from before the burst: of the folder and of its parent
    let before = c.list(&node).await.unwrap();
    let mut above = c.list(&root).await.unwrap();
    assert!(matches!(
        above.next().await.expect("stream open"),
        ListEvent::Refreshed(_)
    ));

    let ctx = h.ctx().clone();
    let declare = tokio::spawn(async move {
        for i in 0..N {
            ctx.declare_node(&format!("burst/p{i}"), NodeMeta::number())
                .await
                .unwrap();
            if i % 500 == 499 {
                // the lists opened meanwhile meet a half-made folder
                tokio::time::sleep(Duration::from_millis(10)).await;
            }
        }
    });
    let mut during = Vec::new();
    let mut half_made = 0;
    for _ in 0..6 {
        tokio::time::sleep(Duration::from_millis(5)).await;
        let s = open_list(&c, &node).await;
        half_made += usize::from(!declare.is_finished());
        during.push(s);
    }
    assert!(half_made > 0, "no list was opened during the burst");
    let want: BTreeSet<String> = (0..N).map(|i| format!("p{i}")).collect();
    assert_eq!(collect_children(before, N).await, want);
    for s in during {
        assert_eq!(collect_children(s, N).await, want);
    }
    declare.await.unwrap();

    // the parent's own list is whole and in the order of the declares
    let m = c.meta(&node).await.unwrap();
    let names: Vec<String> = (0..N).map(|i| format!("p{i}")).collect();
    assert_eq!(m.children.as_deref(), Some(names.as_slice()));
    assert_eq!(m.children_count, Some(N as u32));
    // and the folder's last `~meta` put, as its parent's list sees it,
    // carries all of it: nobody needs a `get` to converge
    let whole = async {
        loop {
            if let ListEvent::Changed(ch) = above.next().await.expect("stream open") {
                if ch.name == "burst" && ch.meta.children_count == Some(N as u32) {
                    assert_eq!(ch.meta.children.as_deref(), Some(names.as_slice()));
                    assert_eq!(ch.meta.rev, m.rev);
                    return;
                }
            }
        }
    };
    tokio::time::timeout(Duration::from_secs(30), whole)
        .await
        .expect("the folder's last ~meta put lists every child");
    h.stop().await;
}
