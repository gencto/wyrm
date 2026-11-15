//! The route gap (backlog item 6, 2026-11-15): a link's liveliness token is
//! routed before queries to it are, so for a moment its `~meta` read ends at
//! once with no reply. A list of the links root must wait that out and list
//! the link only with the meta it answered, never with an empty default.
//!
//! The fake link here counts queries instead of time: it drops the first
//! `drop_first` (a dropped query ends at once with no reply, as in the gap),
//! holds the next `hold_first` without a reply until the client gives up on
//! them (a link that keeps silent), and answers the rest. No timing decides
//! a result.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::unreachable,
    clippy::print_stdout,
    reason = "test code: a failed step fails the test"
)]

use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;
use wyrm_client::{Child, EventStream, ListEvent, WyrmClient};
use wyrm_core::codec::to_vec;
use wyrm_core::{Attachment, NodeMeta};
use wyrm_link_sdk::harness::{isolated_config, SITE};
use zenoh::query::Query;
use zenoh::Wait;

fn links_root() -> String {
    format!("wy/{SITE}/downstream")
}

fn meta() -> NodeMeta {
    meta_of("Fake link")
}

fn meta_of(display: &str) -> NodeMeta {
    NodeMeta {
        rev: Some(1),
        ..NodeMeta::folder().display(display)
    }
}

struct FakeLink {
    asked: Arc<AtomicUsize>,
    held: Arc<Mutex<Vec<Query>>>,
    _queryable: zenoh::query::Queryable<()>,
    token: Option<zenoh::liveliness::LivelinessToken>,
}

impl FakeLink {
    async fn start(session: &zenoh::Session, drop_first: usize, hold_first: usize) -> Self {
        Self::named(session, "fake", "Fake link", drop_first, hold_first).await
    }

    async fn named(
        session: &zenoh::Session,
        name: &str,
        display: &str,
        drop_first: usize,
        hold_first: usize,
    ) -> Self {
        let root = format!("{}/{name}", links_root());
        let asked = Arc::new(AtomicUsize::new(0));
        let held = Arc::new(Mutex::new(Vec::new()));
        let (a, h) = (asked.clone(), held.clone());
        let payload = to_vec(&meta_of(display)).unwrap();
        let att = to_vec(&Attachment::ok()).unwrap();
        let queryable = session
            .declare_queryable(format!("{root}/**"))
            .callback(move |q: Query| {
                let n = a.fetch_add(1, Ordering::SeqCst);
                if n < drop_first {
                    return; // dropped: the query ends at once, no reply
                }
                if n < drop_first + hold_first {
                    h.lock().unwrap().push(q); // no reply until the client gives up
                    return;
                }
                let key = q.key_expr().clone();
                q.reply(key, payload.clone())
                    .attachment(att.clone())
                    .wait()
                    .unwrap();
            })
            .await
            .unwrap();
        let token = session.liveliness().declare_token(&root).await.unwrap();
        Self {
            asked,
            held,
            _queryable: queryable,
            token: Some(token),
        }
    }

    fn asked(&self) -> usize {
        self.asked.load(Ordering::SeqCst)
    }
}

async fn next(s: &mut EventStream<ListEvent>, within: Duration) -> ListEvent {
    tokio::time::timeout(within, s.next())
        .await
        .expect("event in time")
        .expect("stream open")
}

fn assert_read(c: &Child) {
    assert_eq!(c.name, "fake");
    assert_eq!(c.meta, meta(), "the meta the link answered, not a default");
}

async fn client() -> (zenoh::Session, WyrmClient) {
    let s = zenoh::open(isolated_config()).await.unwrap();
    let c = WyrmClient::new(s.clone()).with_timeout(Duration::from_secs(2));
    (s, c)
}

/// The token appears while the list runs; the first three reads have no
/// reply (more than the two tries a read had before), the fourth answers.
#[tokio::test(flavor = "multi_thread")]
async fn a_link_added_in_the_gap_comes_with_its_meta() {
    let (s, c) = client().await;
    let mut list = c.list(&links_root()).await.unwrap();
    assert_eq!(
        next(&mut list, Duration::from_secs(3)).await,
        ListEvent::Refreshed(vec![])
    );
    let fake = FakeLink::start(&s, 3, 0).await;
    match next(&mut list, Duration::from_secs(5)).await {
        ListEvent::Added(child) => assert_read(&child),
        e => panic!("expected Added, got {e:?}"),
    }
    assert_eq!(fake.asked(), 4, "three reads in the gap, one answered");
}

/// The token is there before the list starts: the snapshot waits out the
/// gap too.
#[tokio::test(flavor = "multi_thread")]
async fn the_snapshot_waits_out_the_gap() {
    let (s, c) = client().await;
    let _fake = FakeLink::start(&s, 3, 0).await;
    let kids = c.children(&links_root()).await.unwrap();
    assert_eq!(kids.len(), 1);
    assert_read(&kids[0]);
}

/// A link that keeps silent through a whole read (`LIST_READ_WINDOW`) is
/// not listed then; it is read again and listed once it answers.
#[tokio::test(flavor = "multi_thread")]
async fn a_silent_link_is_listed_once_it_answers() {
    let (s, c) = client().await;
    let mut list = c.list(&links_root()).await.unwrap();
    assert_eq!(
        next(&mut list, Duration::from_secs(3)).await,
        ListEvent::Refreshed(vec![])
    );
    let fake = FakeLink::start(&s, 0, 2).await;
    // a read of 1.5 s, a pause of 1 s, a read of 1.5 s, a pause of 2 s, then
    // the read that answers
    match next(&mut list, Duration::from_secs(8)).await {
        ListEvent::Added(child) => assert_read(&child),
        e => panic!("expected Added, got {e:?}"),
    }
    assert_eq!(fake.asked(), 3);
    assert_eq!(fake.held.lock().unwrap().len(), 2);
}

/// A silent link whose token goes is never listed.
#[tokio::test(flavor = "multi_thread")]
async fn a_silent_link_that_goes_is_never_listed() {
    let (s, c) = client().await;
    let mut list = c.list(&links_root()).await.unwrap();
    assert_eq!(
        next(&mut list, Duration::from_secs(3)).await,
        ListEvent::Refreshed(vec![])
    );
    let mut fake = FakeLink::start(&s, 0, usize::MAX / 2).await;
    // two reads end without a reply
    tokio::time::timeout(Duration::from_secs(6), async {
        while fake.asked() < 2 {
            tokio::time::sleep(Duration::from_millis(20)).await;
        }
    })
    .await
    .expect("two reads");
    drop(fake.token.take());
    // the reads again stop, and nothing is listed
    let r = tokio::time::timeout(Duration::from_secs(4), list.next()).await;
    assert!(r.is_err(), "no event for a link that never answered: {r:?}");
}

/// A silent link never holds up its siblings: the snapshot comes within one
/// `LIST_READ_WINDOW` with the links that answered, a link added later is
/// listed at once even while a silent one is being read, and the silent one
/// is listed when it answers.
#[tokio::test(flavor = "multi_thread")]
async fn a_silent_link_never_holds_up_its_siblings() {
    use std::time::Instant;
    // the default timeout (10 s, spec 05): the list must not wait that long
    let s = zenoh::open(isolated_config()).await.unwrap();
    let c = WyrmClient::new(s.clone());
    let _a = FakeLink::named(&s, "a", "A", 0, 0).await;
    let _b = FakeLink::named(&s, "b", "B", 0, 0).await;
    let silent = FakeLink::named(&s, "silent", "Silent", 0, 2).await;
    let started = Instant::now();
    let mut list = c.list(&links_root()).await.unwrap();
    let ListEvent::Refreshed(kids) = next(&mut list, Duration::from_secs(3)).await else {
        panic!("Refreshed first")
    };
    let first = started.elapsed();
    let names: Vec<&str> = kids.iter().map(|k| k.name.as_str()).collect();
    assert_eq!(names, ["a", "b"], "the silent one is not in the snapshot");
    assert!(
        first < wyrm_client::LIST_READ_WINDOW + Duration::from_millis(700),
        "the snapshot waited {first:?}"
    );
    // a link that comes while the silent one is read again: listed at once
    let added = Instant::now();
    let _d = FakeLink::named(&s, "d", "D", 0, 0).await;
    match next(&mut list, Duration::from_secs(3)).await {
        ListEvent::Added(ch) => {
            assert_eq!(ch.name, "d");
            assert_eq!(ch.meta, meta_of("D"));
        }
        e => panic!("expected Added(d), got {e:?}"),
    }
    assert!(
        added.elapsed() < Duration::from_millis(700),
        "{:?}",
        added.elapsed()
    );
    // the silent one, once it answers
    match next(&mut list, Duration::from_secs(8)).await {
        ListEvent::Added(ch) => {
            assert_eq!(ch.name, "silent");
            assert_eq!(ch.meta, meta_of("Silent"));
        }
        e => panic!("expected Added(silent), got {e:?}"),
    }
    assert_eq!(silent.asked(), 3);
}
