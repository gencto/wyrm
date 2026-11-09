//! Reactive `list` and `subscribe`. Dropping a stream undeclares its
//! subscribers (and ends its task, if it has one).
//!
//! No stream ever blocks the session: Zenoh writes into a buffer the
//! stream owns ([`crate::intake`]), and a full buffer follows the policy of
//! its stream kind instead of waiting for the consumer:
//!
//! * `subscribe`: one pending value per key, the newest wins (values are
//!   state, not events); a replaced value counts in
//!   [`EventStream::dropped`].
//! * `subscribe_reliable` (QoS 2/3, a queue): the oldest sample beyond
//!   [`RELIABLE_BUFFER`] is dropped and counted.
//! * `list`: events are never dropped one by one; beyond [`LIST_BUFFER`]
//!   the buffer is discarded, counted, and the stream reads the children
//!   again and sends `Refreshed`.
//! * `invoke` (`lib.rs`): beyond [`INVOKE_BUFFER`] replies the stream ends
//!   with `resource_exhausted` after the replies it still holds.

use crate::intake::Intake;
use crate::{decode, is_links_root, owner_key, Child, ClientError, Result, WyrmClient};
use std::collections::{HashMap, VecDeque};
use std::pin::Pin;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use std::task::{Context, Poll};
use std::time::Duration;
use tokio::sync::mpsc;
use tracing::debug;
use wyrm_core::keyspace::{SUFFIX_META, SUFFIX_VAL};
use wyrm_core::{Attachment, NodeMeta, Sample};
use zenoh::query::Reply;
use zenoh::sample::{Sample as ZSample, SampleKind};

/// `list` events held for a consumer that is behind; one more discards
/// them and the stream reads the children again (`Refreshed`).
pub const LIST_BUFFER: usize = 1024;
/// `subscribe_reliable` samples held for a consumer that is behind; one
/// more drops the oldest.
pub const RELIABLE_BUFFER: usize = 4096;
/// `invoke` replies held for a consumer that is behind; one more ends the
/// stream with `resource_exhausted`.
pub const INVOKE_BUFFER: usize = 1024;
/// Events a stream task has already turned into `ListEvent`s and holds for
/// its consumer; kept small, so a consumer that wakes up soon meets the
/// fresh snapshot rather than old events.
const TASK_CHANNEL: usize = 16;

/// What a stream reads from: a task's channel or an intake it polls itself.
pub(crate) trait Source<T>: Send {
    fn poll_next(&mut self, cx: &mut Context<'_>) -> Poll<Option<T>>;
}

impl<T: Send> Source<T> for mpsc::Receiver<T> {
    fn poll_next(&mut self, cx: &mut Context<'_>) -> Poll<Option<T>> {
        self.poll_recv(cx)
    }
}

/// A stream of events. Use [`next`](Self::next) or the
/// `futures_core::Stream` impl.
pub struct EventStream<T> {
    src: Box<dyn Source<T>>,
    dropped: Arc<AtomicU64>,
}

impl<T: 'static> EventStream<T> {
    pub(crate) fn new(src: impl Source<T> + 'static, dropped: Arc<AtomicU64>) -> Self {
        Self {
            src: Box::new(src),
            dropped,
        }
    }
}

impl<T> EventStream<T> {
    pub async fn next(&mut self) -> Option<T> {
        std::future::poll_fn(|cx| self.src.poll_next(cx)).await
    }

    /// Items this stream did not deliver because its consumer was behind:
    /// values replaced by a newer one of the same key (`subscribe`), oldest
    /// samples (`subscribe_reliable`), events replaced by a fresh snapshot
    /// (`list`), replies lost before the error (`invoke`). Zero while the
    /// consumer keeps up.
    pub fn dropped(&self) -> u64 {
        self.dropped.load(Ordering::Relaxed)
    }
}

impl<T> futures_core::Stream for EventStream<T> {
    type Item = T;
    fn poll_next(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Option<T>> {
        self.src.poll_next(cx)
    }
}

#[derive(Debug, Clone, PartialEq)]
pub enum ListEvent {
    /// Full snapshot: first event, again after the owner reconnects and
    /// after the consumer fell more than [`LIST_BUFFER`] events behind.
    Refreshed(Vec<Child>),
    Added(Child),
    Changed(Child),
    Removed(String),
    /// `None`: the owning link is gone; `Some(name)`: a dynamic child is gone.
    Disconnected(Option<String>),
    /// A dynamic child is back.
    Connected(String),
}

#[derive(Debug, Clone, PartialEq)]
pub enum ValEvent {
    Sample {
        /// Node key (without `/~val`).
        key: String,
        sample: Sample,
        /// Extended quality from the attachment (`bad/comm_fail`, …).
        qual: Option<String>,
    },
    Removed(String),
}

impl ValEvent {
    fn key(&self) -> &str {
        match self {
            Self::Sample { key, .. } | Self::Removed(key) => key,
        }
    }
}

/// `prefix/<name>/suffix` → `name` (single segment), else `None`.
fn child_name<'a>(key: &'a str, prefix: &str, suffix: &str) -> Option<&'a str> {
    let rest = key.strip_prefix(prefix)?.strip_prefix('/')?;
    let name = if suffix.is_empty() {
        rest
    } else {
        rest.strip_suffix(suffix)?.strip_suffix('/')?
    };
    (!name.is_empty() && !name.contains('/')).then_some(name)
}

// ---------------------------------------------------------------- list

enum Raw {
    Meta(ZSample),
    Child(ZSample),
    Owner(SampleKind),
}

/// Samples of a `list` in arrival order, bounded by [`LIST_BUFFER`].
struct ListIntake {
    queue: VecDeque<Raw>,
    /// Read the children again: the buffer overflowed (or a re-read failed).
    resync: bool,
    closed: bool,
    dropped: Arc<AtomicU64>,
}

impl ListIntake {
    fn push(&mut self, raw: Raw) {
        if self.resync {
            // the snapshot to come covers it
            self.dropped.fetch_add(1, Ordering::Relaxed);
        } else if self.queue.len() >= LIST_BUFFER {
            let lost = self.queue.len() as u64 + 1;
            self.dropped.fetch_add(lost, Ordering::Relaxed);
            self.queue.clear();
            self.resync = true;
        } else {
            self.queue.push_back(raw);
        }
    }
}

// moved once per event; boxing would cost an allocation each
#[allow(clippy::large_enum_variant)]
enum Step {
    Raw(Raw),
    /// Read the children again; everything before this point is covered.
    Resync,
    Closed,
}

fn list_step(s: &mut ListIntake) -> Option<Step> {
    if s.resync {
        s.resync = false;
        s.queue.clear();
        return Some(Step::Resync);
    }
    if let Some(raw) = s.queue.pop_front() {
        return Some(Step::Raw(raw));
    }
    s.closed.then_some(Step::Closed)
}

pub(crate) async fn list(client: WyrmClient, node: String) -> Result<EventStream<ListEvent>> {
    let s = client.session();
    let dropped = Arc::new(AtomicU64::new(0));
    let intake = Intake::new(ListIntake {
        queue: VecDeque::new(),
        resync: false,
        closed: false,
        dropped: dropped.clone(),
    });
    // Subscribe first, snapshot second: nothing between them is lost. The
    // subscribers are not read during the snapshot; the intake holds them.
    let meta_sub = s
        .declare_subscriber(format!("{node}/*/{SUFFIX_META}"))
        .with(intake.feed(
            |st: &mut ListIntake, smp| st.push(Raw::Meta(smp)),
            |st| st.closed = true,
        ))
        .await?;
    let live_sub = s
        .liveliness()
        .declare_subscriber(format!("{node}/*"))
        .with(intake.feed(|st: &mut ListIntake, smp| st.push(Raw::Child(smp)), |_| {}))
        .await?;
    let owner = (!is_links_root(&node)).then(|| owner_key(&node)).flatten();
    let owner_sub = match &owner {
        Some(o) => Some(
            s.liveliness()
                .declare_subscriber(o.clone())
                .with(intake.feed(
                    |st: &mut ListIntake, smp: ZSample| st.push(Raw::Owner(smp.kind())),
                    |_| {},
                ))
                .await?,
        ),
        None => None,
    };
    let snapshot = client.children(&node).await?;

    let (tx, rx) = mpsc::channel(TASK_CHANNEL);
    let mut known = known_of(&snapshot);
    tx.send(ListEvent::Refreshed(snapshot))
        .await
        .map_err(|_| ClientError::new(wyrm_core::Status::Closed, "stream dropped"))?;
    let links_root = is_links_root(&node);

    tokio::spawn(async move {
        let _subs = (meta_sub, live_sub, owner_sub);
        loop {
            let step = tokio::select! {
                step = intake.next(list_step) => step,
                _ = tx.closed() => return,
            };
            let ev = match step {
                Step::Closed => return,
                Step::Raw(Raw::Meta(smp)) => on_meta(&node, &smp, &mut known),
                Step::Raw(Raw::Child(smp)) => {
                    on_child_liveliness(&client, &node, links_root, &smp, &mut known).await
                }
                Step::Raw(Raw::Owner(SampleKind::Delete)) => Some(ListEvent::Disconnected(None)),
                Step::Raw(Raw::Owner(SampleKind::Put)) => match client.children(&node).await {
                    Ok(snap) => {
                        known = known_of(&snap);
                        Some(ListEvent::Refreshed(snap))
                    }
                    Err(e) => {
                        debug!("re-list after reconnect failed: {e}");
                        None
                    }
                },
                Step::Resync => match client.children(&node).await {
                    Ok(snap) => {
                        known = known_of(&snap);
                        Some(ListEvent::Refreshed(snap))
                    }
                    // the owner is gone: its next `Put` lists again
                    Err(e) if e.is(wyrm_core::Status::Disconnected) => {
                        Some(ListEvent::Disconnected(None))
                    }
                    Err(e) => {
                        debug!("re-list after an overflow failed: {e}");
                        tokio::select! {
                            _ = tokio::time::sleep(Duration::from_secs(1)) => {}
                            _ = tx.closed() => return,
                        }
                        intake.update(|st| st.resync = true);
                        None
                    }
                },
            };
            if let Some(ev) = ev {
                if tx.send(ev).await.is_err() {
                    return;
                }
            }
        }
    });
    Ok(EventStream::new(rx, dropped))
}

fn known_of(kids: &[Child]) -> HashMap<String, u32> {
    kids.iter()
        .map(|c| (c.name.clone(), c.meta.rev.unwrap_or(0)))
        .collect()
}

fn on_meta(node: &str, smp: &ZSample, known: &mut HashMap<String, u32>) -> Option<ListEvent> {
    let name = child_name(smp.key_expr().as_str(), node, SUFFIX_META)?.to_owned();
    match smp.kind() {
        SampleKind::Delete => known.remove(&name).map(|_| ListEvent::Removed(name)),
        SampleKind::Put => {
            let meta: NodeMeta = decode(&smp.payload().to_bytes()).ok()?;
            let rev = meta.rev.unwrap_or(0);
            match known.insert(name.clone(), rev) {
                None => Some(ListEvent::Added(Child { name, meta })),
                Some(old) if rev > old => Some(ListEvent::Changed(Child { name, meta })),
                Some(old) => {
                    known.insert(name, old);
                    None
                }
            }
        }
    }
}

async fn on_child_liveliness(
    client: &WyrmClient,
    node: &str,
    links_root: bool,
    smp: &ZSample,
    known: &mut HashMap<String, u32>,
) -> Option<ListEvent> {
    let name = child_name(smp.key_expr().as_str(), node, "")?.to_owned();
    match (smp.kind(), links_root) {
        (SampleKind::Put, true) => {
            if known.contains_key(&name) {
                return None;
            }
            let meta = client
                .meta(&format!("{node}/{name}"))
                .await
                .unwrap_or_default();
            known.insert(name.clone(), meta.rev.unwrap_or(0));
            Some(ListEvent::Added(Child { name, meta }))
        }
        (SampleKind::Delete, true) => known.remove(&name).map(|_| ListEvent::Removed(name)),
        (SampleKind::Put, false) => Some(ListEvent::Connected(name)),
        (SampleKind::Delete, false) => Some(ListEvent::Disconnected(Some(name))),
    }
}

// ----------------------------------------------------------- subscribe

/// What the value buffer does with one more item.
enum Policy {
    /// One pending event per key, the newest wins (`subscribe`).
    Latest {
        pending: HashMap<String, ValEvent>,
        order: VecDeque<String>,
    },
    /// Arrival order, the oldest beyond the bound dropped
    /// (`subscribe_reliable`).
    #[cfg_attr(not(feature = "advanced"), allow(dead_code))]
    Queue(VecDeque<ValEvent>),
}

struct Vals {
    policy: Policy,
    /// Per key, the `t` of the last sample handed to the consumer: an older
    /// one is never handed out after it.
    last_t: HashMap<String, u64>,
    /// The stored values are in; nothing is handed out before.
    stored_done: bool,
    /// The live subscriber is gone (session closed).
    live_closed: bool,
    dropped: Arc<AtomicU64>,
}

impl Vals {
    fn new(policy: Policy, stored_done: bool, dropped: Arc<AtomicU64>) -> Self {
        Self {
            policy,
            last_t: HashMap::new(),
            stored_done,
            live_closed: false,
            dropped,
        }
    }

    fn lose(&self, n: u64) {
        self.dropped.fetch_add(n, Ordering::Relaxed);
    }

    fn push(&mut self, ev: ValEvent) {
        if let ValEvent::Sample { key, sample, .. } = &ev {
            if self.last_t.get(key).is_some_and(|t| *t > sample.t) {
                return;
            }
        }
        let lost =
            match &mut self.policy {
                Policy::Latest { pending, order } => match pending.get_mut(ev.key()) {
                    None => {
                        order.push_back(ev.key().to_owned());
                        pending.insert(ev.key().to_owned(), ev);
                        0
                    }
                    Some(old) => match (&*old, &ev) {
                        // the same sample twice (stored and live): no loss
                        (
                            ValEvent::Sample { sample: a, .. },
                            ValEvent::Sample { sample: b, .. },
                        ) if b.t == a.t => 0,
                        // an older sample after a newer one: the newer stays
                        (
                            ValEvent::Sample { sample: a, .. },
                            ValEvent::Sample { sample: b, .. },
                        ) if b.t < a.t => 1,
                        _ => {
                            *old = ev;
                            1
                        }
                    },
                },
                Policy::Queue(q) => {
                    let lost = if q.len() >= RELIABLE_BUFFER {
                        q.pop_front();
                        1
                    } else {
                        0
                    };
                    q.push_back(ev);
                    lost
                }
            };
        if lost > 0 {
            self.lose(lost);
        }
    }

    /// The next event for the consumer; `Some(None)` = the stream ended.
    fn pop(&mut self) -> Option<Option<ValEvent>> {
        if self.stored_done {
            loop {
                let ev = match &mut self.policy {
                    Policy::Latest { pending, order } => order
                        .pop_front()
                        .map(|k| pending.remove(&k).expect("ordered key is pending")),
                    Policy::Queue(q) => q.pop_front(),
                };
                let Some(ev) = ev else { break };
                match &ev {
                    ValEvent::Sample { key, sample, .. } => {
                        if self.last_t.get(key).is_some_and(|t| *t > sample.t) {
                            continue;
                        }
                        self.last_t.insert(key.clone(), sample.t);
                    }
                    ValEvent::Removed(key) => {
                        self.last_t.remove(key);
                    }
                }
                return Some(Some(ev));
            }
        }
        (self.live_closed && self.stored_done).then_some(None)
    }
}

struct ValReader {
    intake: Arc<Intake<Vals>>,
    /// Keeps the subscriber declared for as long as the stream lives.
    _sub: Box<dyn Send>,
}

impl Source<ValEvent> for ValReader {
    fn poll_next(&mut self, cx: &mut Context<'_>) -> Poll<Option<ValEvent>> {
        self.intake.poll(cx, Vals::pop)
    }
}

fn live_feed(intake: &Arc<Intake<Vals>>) -> crate::intake::Feed<Vals, ZSample> {
    intake.feed(
        |st: &mut Vals, smp: ZSample| {
            if let Some(ev) = to_val(&smp) {
                st.push(ev);
            }
        },
        |st| st.live_closed = true,
    )
}

pub(crate) async fn subscribe(
    client: WyrmClient,
    pattern: String,
) -> Result<EventStream<ValEvent>> {
    let ke = format!("{pattern}/{SUFFIX_VAL}");
    let s = client.session();
    let dropped = Arc::new(AtomicU64::new(0));
    let latest = Policy::Latest {
        pending: HashMap::new(),
        order: VecDeque::new(),
    };
    let intake = Intake::new(Vals::new(latest, false, dropped.clone()));
    // Live first, stored second (no lost update); both into one buffer,
    // newer `t` wins per key, nothing handed out before the stored are in.
    let sub = s.declare_subscriber(&ke).with(live_feed(&intake)).await?;
    s.get(&ke)
        .timeout(client.timeout)
        .with(intake.feed(
            |st: &mut Vals, reply: Reply| {
                if let Some(ev) = reply.result().ok().and_then(to_val) {
                    st.push(ev);
                }
            },
            |st| st.stored_done = true,
        ))
        .await?;
    Ok(EventStream::new(
        ValReader {
            intake,
            _sub: Box::new(sub),
        },
        dropped,
    ))
}

/// QoS 2/3: AdvancedSubscriber with history (cached samples of publishers
/// with `cfg.qos >= 2`, also late-joining ones) and gap recovery.
#[cfg(feature = "advanced")]
pub(crate) async fn subscribe_reliable(
    client: WyrmClient,
    pattern: String,
) -> Result<EventStream<ValEvent>> {
    use zenoh_ext::{AdvancedSubscriberBuilderExt, HistoryConfig, RecoveryConfig};
    let dropped = Arc::new(AtomicU64::new(0));
    let queue = Policy::Queue(VecDeque::new());
    let intake = Intake::new(Vals::new(queue, true, dropped.clone()));
    let sub = client
        .session()
        .declare_subscriber(format!("{pattern}/{SUFFIX_VAL}"))
        .advanced()
        .history(HistoryConfig::default().detect_late_publishers())
        .recovery(RecoveryConfig::default().heartbeat())
        .subscriber_detection()
        .with(live_feed(&intake))
        .await?;
    Ok(EventStream::new(
        ValReader {
            intake,
            _sub: Box::new(sub),
        },
        dropped,
    ))
}

fn to_val(smp: &ZSample) -> Option<ValEvent> {
    let key = smp
        .key_expr()
        .as_str()
        .strip_suffix(SUFFIX_VAL)?
        .strip_suffix('/')?
        .to_owned();
    if smp.kind() == SampleKind::Delete {
        return Some(ValEvent::Removed(key));
    }
    let sample: Sample = decode(&smp.payload().to_bytes()).ok()?;
    let qual = smp
        .attachment()
        .and_then(|a| decode::<Attachment>(&a.to_bytes()).ok())
        .and_then(|a| a.qual);
    Some(ValEvent::Sample { key, sample, qual })
}

#[cfg(test)]
mod tests {
    use super::*;
    use wyrm_core::{Quality, Value};

    #[test]
    fn child_names() {
        assert_eq!(child_name("a/b/x/~meta", "a/b", "~meta"), Some("x"));
        assert_eq!(child_name("a/b/x/y/~meta", "a/b", "~meta"), None);
        assert_eq!(child_name("a/b/x", "a/b", ""), Some("x"));
        assert_eq!(child_name("a/bx/~meta", "a/b", "~meta"), None);
    }

    fn smp(key: &str, t: u64) -> ValEvent {
        ValEvent::Sample {
            key: key.into(),
            sample: Sample {
                v: Value::UInt(t),
                q: Quality::Good,
                t,
            },
            qual: None,
        }
    }

    fn latest() -> Vals {
        let p = Policy::Latest {
            pending: HashMap::new(),
            order: VecDeque::new(),
        };
        Vals::new(p, false, Arc::default())
    }

    fn drain(v: &mut Vals) -> Vec<ValEvent> {
        std::iter::from_fn(|| v.pop().flatten()).collect()
    }

    #[test]
    fn latest_wins_per_key_after_the_stored_values() {
        let mut v = latest();
        v.push(smp("a", 5)); // live during the stored get
        v.push(smp("b", 1));
        v.push(smp("a", 3)); // stored, older: the live one stays
        v.push(smp("b", 1)); // stored, the same: no loss
        assert_eq!(v.pop(), None, "nothing before the stored values");
        v.stored_done = true;
        v.push(smp("a", 6));
        v.push(smp("b", 2));
        assert_eq!(drain(&mut v), [smp("a", 6), smp("b", 2)]);
        assert_eq!(v.dropped.load(Ordering::Relaxed), 3);
        v.push(smp("a", 4)); // older than what was handed out
        v.push(ValEvent::Removed("b".into()));
        assert_eq!(drain(&mut v), [ValEvent::Removed("b".into())]);
        v.live_closed = true;
        assert_eq!(v.pop(), Some(None));
    }

    #[test]
    fn the_reliable_queue_drops_the_oldest() {
        let mut v = Vals::new(Policy::Queue(VecDeque::new()), true, Arc::default());
        for t in 0..RELIABLE_BUFFER as u64 + 2 {
            v.push(smp("a", t));
        }
        let got = drain(&mut v);
        assert_eq!(got.len(), RELIABLE_BUFFER);
        assert_eq!(got[0], smp("a", 2));
        assert_eq!(v.dropped.load(Ordering::Relaxed), 2);
    }

    #[test]
    fn a_full_list_buffer_asks_for_a_snapshot() {
        let mut l = ListIntake {
            queue: VecDeque::new(),
            resync: false,
            closed: false,
            dropped: Arc::default(),
        };
        for _ in 0..=LIST_BUFFER + 4 {
            l.push(Raw::Owner(SampleKind::Put));
        }
        assert!(matches!(list_step(&mut l), Some(Step::Resync)));
        assert!(l.queue.is_empty());
        assert_eq!(l.dropped.load(Ordering::Relaxed), LIST_BUFFER as u64 + 5);
        assert!(list_step(&mut l).is_none());
        l.closed = true;
        assert!(matches!(list_step(&mut l), Some(Step::Closed)));
    }
}
