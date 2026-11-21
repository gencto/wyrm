//! Reactive `list` and `subscribe`. Dropping a stream undeclares its
//! subscribers (and ends its task, if it has one).
//!
//! No stream ever blocks the session: Zenoh writes into a buffer the
//! stream owns ([`crate::intake`]), and a full buffer follows the policy of
//! its stream kind instead of waiting for the consumer:
//!
//! * `subscribe`: every sample, in arrival order, while at most
//!   [`VALUE_BUFFER`] wait. Only beyond that (overflow mode, until the
//!   consumer has caught up): one pending value per key, the newest wins
//!   (values are state); a replaced value counts in
//!   [`EventStream::dropped`]. At most [`MAX_PENDING_KEYS`] keys: a sample
//!   of one more is dropped (counted) and the stored values are read again
//!   when the consumer has caught up. A key filter (the gateway's read
//!   grants) runs before anything is buffered.
//! * `subscribe_reliable` (QoS 2/3, a queue): the oldest sample beyond
//!   [`RELIABLE_BUFFER`] is dropped and counted.
//! * `list`: events are never dropped one by one; beyond [`LIST_BUFFER`]
//!   the buffer is discarded, counted, and the stream reads the children
//!   again and sends `Refreshed`.
//! * `invoke` (`lib.rs`): beyond [`INVOKE_BUFFER`] replies the stream ends
//!   with `resource_exhausted` after the replies it still holds.

use crate::intake::Intake;
use crate::{
    decode, is_links_root, owner_key, Child, ClientError, LinkMeta, ReadLink, Result, WyrmClient,
};
use std::collections::{HashMap, VecDeque};
use std::pin::Pin;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use std::task::{Context, Poll};
use std::time::Duration;
use tokio::sync::mpsc;
use tokio::task::{AbortHandle, JoinSet};
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
/// `subscribe` events held in arrival order for a consumer that is behind;
/// every sample is delivered while it fits. One more switches the stream to
/// overflow mode (newest per key, [`MAX_PENDING_KEYS`]) until the consumer
/// has taken what waits.
pub const VALUE_BUFFER: usize = 4096;
/// Keys a `subscribe` stream holds a pending value for in overflow mode
/// (about 1 MiB of small values). A sample of one more key is
/// dropped and counted; once the consumer has taken what is pending, the
/// stream reads the stored values again, so such a key still ends with its
/// newest stored value. A pattern over more keys works as long as the
/// consumer keeps up.
pub const MAX_PENDING_KEYS: usize = 4096;
/// Distinct keys one value stream may hand out (`subscribe`, the gateway's
/// too): it remembers the last `t` of each for the time order per key. One
/// more ends the stream with `resource_exhausted`; subscribe a narrower
/// pattern.
pub const MAX_STREAM_KEYS: usize = 16_384;
/// Reads of the stored values again (after more than [`MAX_PENDING_KEYS`]
/// keys waited) in a row without the consumer catching up; one more ends
/// the stream with `resource_exhausted`.
pub const MAX_RESYNCS: u32 = 3;
/// Events a stream task has already turned into `ListEvent`s and holds for
/// its consumer; kept small, so a consumer that wakes up soon meets the
/// fresh snapshot rather than old events.
const TASK_CHANNEL: usize = 16;

/// What a stream reads from: a task's channel or an intake it polls itself.
pub(crate) trait Source<T>: Send {
    fn poll_next(&mut self, cx: &mut Context<'_>) -> Poll<Option<T>>;

    /// Why the stream ended, when it hit a limit.
    fn error(&self) -> Option<ClientError> {
        None
    }
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

    /// After [`next`](Self::next) returned `None`: the limit that ended the
    /// stream (`resource_exhausted`, see [`MAX_STREAM_KEYS`] and
    /// [`MAX_RESYNCS`]), or `None` for a normal end.
    pub fn error(&self) -> Option<ClientError> {
        self.src.error()
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

#[allow(
    clippy::large_enum_variant,
    reason = "moved once per event; boxing would cost an allocation each"
)]
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
    let (snapshot, unread) = client.snapshot(&node).await?;

    let (tx, rx) = mpsc::channel(TASK_CHANNEL);
    let mut known = known_of(&snapshot);
    tx.send(ListEvent::Refreshed(snapshot))
        .await
        .map_err(|_| ClientError::new(wyrm_core::Status::Closed, "stream dropped"))?;
    let links_root = is_links_root(&node);
    let mut pending = PendingLinks::new(client.link_reader(&node));
    for name in unread {
        pending.start(name, true);
    }

    tokio::spawn(async move {
        let _subs = (meta_sub, live_sub, owner_sub);
        loop {
            let step = tokio::select! {
                step = intake.next(list_step) => step,
                done = pending.next(), if !pending.reads.is_empty() => {
                    let ev = done.and_then(|(name, r)| on_read(&mut known, name, r));
                    if let Some(ev) = ev {
                        if tx.send(ev).await.is_err() {
                            return;
                        }
                    }
                    continue;
                }
                _ = tx.closed() => return,
            };
            let ev = match step {
                Step::Closed => return,
                Step::Raw(Raw::Meta(smp)) => on_meta(&node, &smp, &mut known, &mut pending),
                Step::Raw(Raw::Child(smp)) => {
                    on_child_liveliness(&node, links_root, &smp, &mut known, &mut pending)
                }
                Step::Raw(Raw::Owner(SampleKind::Delete)) => Some(ListEvent::Disconnected(None)),
                Step::Raw(Raw::Owner(SampleKind::Put)) => match client.snapshot(&node).await {
                    Ok((snap, unread)) => {
                        known = known_of(&snap);
                        pending.reset();
                        for name in unread {
                            pending.start(name, true);
                        }
                        Some(ListEvent::Refreshed(snap))
                    }
                    Err(e) => {
                        debug!("re-list after reconnect failed: {e}");
                        None
                    }
                },
                Step::Resync => match client.snapshot(&node).await {
                    Ok((snap, unread)) => {
                        known = known_of(&snap);
                        pending.reset();
                        for name in unread {
                            pending.start(name, true);
                        }
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

/// The first pause before a silent link's `~meta` is read again; it doubles
/// up to [`SILENT_PAUSE_MAX`].
const SILENT_PAUSE_FIRST: Duration = Duration::from_secs(1);
const SILENT_PAUSE_MAX: Duration = Duration::from_secs(30);

/// Links of a links-root list whose token is there but which are not listed
/// yet: each `~meta` read runs on its own task, so the list goes on with
/// every other event meanwhile and no link waits for another. A read is
/// bounded by [`LIST_READ_WINDOW`](crate::LIST_READ_WINDOW); a link that
/// kept silent through it is read again after a pause (1 s, doubled up to
/// [`SILENT_PAUSE_MAX`]) until it answers or its token is gone. A link is
/// listed only once it has answered.
struct PendingLinks {
    read: ReadLink,
    reads: JoinSet<(String, LinkMeta)>,
    ids: HashMap<String, AbortHandle>,
}

impl PendingLinks {
    fn new(read: ReadLink) -> Self {
        Self {
            read,
            reads: JoinSet::new(),
            ids: HashMap::new(),
        }
    }

    /// Read `name` (at once, or after the first pause when it has just kept
    /// silent in a snapshot) and again until it answers.
    fn start(&mut self, name: String, silent_already: bool) {
        if self.ids.contains_key(&name) {
            return;
        }
        let (read, task_name) = (self.read.clone(), name.clone());
        let handle = self.reads.spawn(async move {
            let mut pause = SILENT_PAUSE_FIRST;
            if silent_already {
                tokio::time::sleep(pause).await;
                pause = (pause * 2).min(SILENT_PAUSE_MAX);
            }
            loop {
                match read(task_name.clone()).await {
                    LinkMeta::Silent => {
                        tokio::time::sleep(pause).await;
                        pause = (pause * 2).min(SILENT_PAUSE_MAX);
                    }
                    r => return (task_name, r),
                }
            }
        });
        self.ids.insert(name, handle);
    }

    /// The child is listed, or gone: no more reads of it (the set reports
    /// the aborted task, and it is skipped).
    fn forget(&mut self, name: &str) {
        if let Some(h) = self.ids.remove(name) {
            h.abort();
        }
    }

    /// `true` if the read `id` of `name` is the current one (and ends it).
    fn take(&mut self, name: &str, id: tokio::task::Id) -> bool {
        if self.ids.get(name).is_some_and(|h| h.id() == id) {
            self.ids.remove(name);
            true
        } else {
            false
        }
    }

    /// The next read that ended: `Some((name, what it read))` for a current
    /// one, `None` for an aborted or replaced one.
    async fn next(&mut self) -> Option<(String, LinkMeta)> {
        match self.reads.join_next_with_id().await? {
            Ok((id, (name, r))) if self.take(&name, id) => Some((name, r)),
            _ => None,
        }
    }

    fn reset(&mut self) {
        self.reads.abort_all();
        self.ids.clear();
    }
}

/// A pending link's read has ended: `Added` with the meta it answered.
fn on_read(known: &mut HashMap<String, u32>, name: String, r: LinkMeta) -> Option<ListEvent> {
    match r {
        LinkMeta::Read(meta) if !known.contains_key(&name) => {
            known.insert(name.clone(), meta.rev.unwrap_or(0));
            Some(ListEvent::Added(Child { name, meta }))
        }
        // listed meanwhile (its `~meta` came), or its token is gone
        _ => None,
    }
}

fn on_meta(
    node: &str,
    smp: &ZSample,
    known: &mut HashMap<String, u32>,
    pending: &mut PendingLinks,
) -> Option<ListEvent> {
    let name = child_name(smp.key_expr().as_str(), node, SUFFIX_META)?.to_owned();
    match smp.kind() {
        SampleKind::Delete => known.remove(&name).map(|_| ListEvent::Removed(name)),
        SampleKind::Put => {
            let meta: NodeMeta = decode(&smp.payload().to_bytes()).ok()?;
            // its own meta came: a pending link needs no read any more
            pending.forget(&name);
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

fn on_child_liveliness(
    node: &str,
    links_root: bool,
    smp: &ZSample,
    known: &mut HashMap<String, u32>,
    pending: &mut PendingLinks,
) -> Option<ListEvent> {
    let name = child_name(smp.key_expr().as_str(), node, "")?.to_owned();
    match (smp.kind(), links_root) {
        (SampleKind::Put, true) => {
            // Its token is the proof that it exists; its read (on a task of
            // its own) waits out the route gap (`read_through_gap`) and is
            // `Added` when the link answers, never with an empty default.
            if !known.contains_key(&name) {
                pending.start(name, false);
            }
            None
        }
        (SampleKind::Delete, true) => {
            pending.forget(&name);
            known.remove(&name).map(|_| ListEvent::Removed(name))
        }
        (SampleKind::Put, false) => Some(ListEvent::Connected(name)),
        (SampleKind::Delete, false) => Some(ListEvent::Disconnected(Some(name))),
    }
}

// ----------------------------------------------------------- subscribe

/// A key filter of a value stream: a sample of a key it refuses never
/// enters the buffer (the gateway passes the user's read grants).
pub(crate) type KeyFilter = Arc<dyn Fn(&str) -> bool + Send + Sync>;

/// What the value buffer does with one more item.
enum Policy {
    /// `subscribe`: every event in arrival order while at most
    /// [`VALUE_BUFFER`] wait (`queue`, lossless). One more switches to
    /// overflow mode: one pending event per key, the newest wins, at most
    /// [`MAX_PENDING_KEYS`] keys, handed out after the queue. Once those
    /// are taken, the queue takes new events again.
    Latest {
        queue: VecDeque<ValEvent>,
        pending: HashMap<String, ValEvent>,
        order: VecDeque<String>,
    },
    /// Arrival order, the oldest beyond the bound dropped
    /// (`subscribe_reliable`).
    #[cfg_attr(
        not(feature = "advanced"),
        allow(
            dead_code,
            reason = "made only by `subscribe_reliable` (feature `advanced`)"
        )
    )]
    Queue(VecDeque<ValEvent>),
}

struct Vals {
    policy: Policy,
    /// Per key, the `t` of the last sample handed to the consumer: one as old
    /// or older is never handed out after it. At most [`MAX_STREAM_KEYS`]
    /// keys, never cleared.
    last_t: HashMap<String, u64>,
    /// Stored-value `get`s in flight (the first one and the reads again).
    gets: usize,
    /// A key did not fit into the pending values: read the stored values
    /// again once the consumer has taken what is pending.
    overflowed: bool,
    /// The live subscriber is gone (session closed).
    live_closed: bool,
    /// Reads again since the consumer last caught up.
    resyncs: u32,
    /// A limit ended the stream.
    failed: Option<ClientError>,
    dropped: Arc<AtomicU64>,
}

/// What a value stream hands out next.
enum Pop {
    Event(ValEvent),
    /// Start a stored-value `get` (counted in `gets` already).
    Resync,
    End,
}

impl Vals {
    fn new(policy: Policy, gets: usize, dropped: Arc<AtomicU64>) -> Self {
        Self {
            policy,
            last_t: HashMap::new(),
            gets,
            overflowed: false,
            live_closed: false,
            resyncs: 0,
            failed: None,
            dropped,
        }
    }

    /// End the stream with `resource_exhausted`; what waits is freed.
    fn fail(&mut self, message: String) {
        let waiting = match &mut self.policy {
            Policy::Latest {
                queue,
                pending,
                order,
            } => {
                order.clear();
                std::mem::take(pending).len() + std::mem::take(queue).len()
            }
            Policy::Queue(q) => std::mem::take(q).len(),
        };
        self.dropped.fetch_add(waiting as u64, Ordering::Relaxed);
        self.last_t = HashMap::new();
        self.failed = Some(ClientError::new(
            wyrm_core::Status::ResourceExhausted,
            message,
        ));
    }

    /// One more event of a key the stream's filter accepted (the feed asks
    /// it before the lock, [`to_val`]).
    fn push(&mut self, ev: ValEvent) {
        if self.failed.is_some() {
            return;
        }
        if let ValEvent::Sample { key, sample, .. } = &ev {
            if self.last_t.get(key).is_some_and(|t| *t >= sample.t) {
                return;
            }
        }
        let lost =
            match &mut self.policy {
                // lossless while the queue has room and nothing is coalesced
                Policy::Latest { queue, order, .. }
                    if order.is_empty() && queue.len() < VALUE_BUFFER =>
                {
                    queue.push_back(ev);
                    0
                }
                Policy::Latest { pending, order, .. } => match pending.get_mut(ev.key()) {
                    None if order.len() >= MAX_PENDING_KEYS => {
                        self.overflowed = true;
                        1
                    }
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
            self.dropped.fetch_add(lost, Ordering::Relaxed);
        }
    }

    fn pop(&mut self) -> Option<Pop> {
        if self.failed.is_some() {
            return Some(Pop::End);
        }
        loop {
            let ev = match &mut self.policy {
                // the queue first: what it holds is older than what is coalesced
                Policy::Latest {
                    queue,
                    pending,
                    order,
                } => queue.pop_front().or_else(|| {
                    // every ordered key is pending; a stray one is a bug, said and skipped
                    std::iter::from_fn(|| order.pop_front()).find_map(|k| {
                        let v = pending.remove(&k);
                        if v.is_none() {
                            tracing::error!(key = %k, "stream: an ordered key without a pending value");
                        }
                        v
                    })
                }),
                Policy::Queue(q) => q.pop_front(),
            };
            let Some(ev) = ev else { break };
            match &ev {
                // one lookup for a key the stream knows, and no copy of the key
                ValEvent::Sample { key, sample, .. } => {
                    let room = self.last_t.len() < MAX_STREAM_KEYS;
                    match self.last_t.get_mut(key) {
                        Some(t) if *t >= sample.t => continue,
                        Some(t) => *t = sample.t,
                        None if room => {
                            self.last_t.insert(key.clone(), sample.t);
                        }
                        None => {
                            self.fail(format!(
                                "the pattern matches more than {MAX_STREAM_KEYS} keys"
                            ));
                            return Some(Pop::End);
                        }
                    }
                }
                ValEvent::Removed(key) => {
                    self.last_t.remove(key);
                }
            }
            return Some(Pop::Event(ev));
        }
        if self.gets == 0 {
            if self.overflowed {
                if self.resyncs >= MAX_RESYNCS {
                    self.fail(format!(
                        "consumer too slow: more than {MAX_PENDING_KEYS} keys waited \
                         {} times in a row",
                        MAX_RESYNCS + 1
                    ));
                    return Some(Pop::End);
                }
                self.overflowed = false;
                self.resyncs += 1;
                self.gets += 1;
                return Some(Pop::Resync);
            }
            // nothing waits, nothing is read: the consumer caught up
            self.resyncs = 0;
        }
        (self.live_closed && self.gets == 0).then_some(Pop::End)
    }
}

/// Where a value stream reads its stored values (again).
#[derive(Clone)]
struct Stored {
    session: zenoh::Session,
    ke: String,
    timeout: Duration,
}

struct ValReader {
    intake: Arc<Intake<Vals>>,
    /// The stream's key filter, for the stored values read again.
    keep: KeyFilter,
    /// Keeps the subscriber declared for as long as the stream lives.
    _sub: Box<dyn Send>,
    stored: Option<Stored>,
    /// The first stored read of a bounded client, until it is sent: it
    /// waits for its turn here, polled with the stream.
    first: Option<FirstRead>,
}

type FirstRead = std::pin::Pin<Box<dyn std::future::Future<Output = ()> + Send>>;

impl ValReader {
    fn resync(&self) {
        let rt = tokio::runtime::Handle::try_current();
        let (Some(st), Ok(rt)) = (self.stored.clone(), rt) else {
            self.intake.update(|v| v.gets = v.gets.saturating_sub(1));
            return;
        };
        let feed = stored_feed(&self.intake, &self.keep, Vec::new());
        rt.spawn(async move {
            // on an error the feed is dropped, and that ends this `get`
            if let Err(e) = st.session.get(&st.ke).timeout(st.timeout).with(feed).await {
                debug!("stored values again: {e}");
            }
        });
    }
}

impl Source<ValEvent> for ValReader {
    fn error(&self) -> Option<ClientError> {
        self.intake.with(|v| v.failed.clone())
    }

    fn poll_next(&mut self, cx: &mut Context<'_>) -> Poll<Option<ValEvent>> {
        if let Some(first) = &mut self.first {
            if first.as_mut().poll(cx).is_ready() {
                self.first = None;
            }
        }
        loop {
            match self.intake.poll(cx, Vals::pop) {
                Poll::Pending => return Poll::Pending,
                Poll::Ready(Pop::Event(ev)) => return Poll::Ready(Some(ev)),
                Poll::Ready(Pop::End) => return Poll::Ready(None),
                Poll::Ready(Pop::Resync) => self.resync(),
            }
        }
    }
}

/// The feed of the live subscriber. A sample is filtered and decoded on
/// Zenoh's thread before the buffer's lock is taken: the lock covers the
/// push alone, so the consumer never waits for a decode.
fn live_feed(intake: &Arc<Intake<Vals>>, keep: &KeyFilter) -> crate::intake::Feed<Vals, ZSample> {
    let keep = keep.clone();
    intake.feed_map(
        move |smp: ZSample| to_val(&smp, &keep),
        Vals::push,
        |st| st.live_closed = true,
    )
}

/// The feed of a stored-value read that holds `turns` until Zenoh drops it.
fn stored_feed(
    intake: &Arc<Intake<Vals>>,
    keep: &KeyFilter,
    turns: Vec<tokio::sync::OwnedSemaphorePermit>,
) -> crate::intake::Feed<Vals, Reply> {
    let keep = keep.clone();
    intake.feed_map(
        move |reply: Reply| to_val(reply.result().ok()?, &keep),
        Vals::push,
        move |st| {
            drop(turns);
            st.gets = st.gets.saturating_sub(1);
        },
    )
}

pub(crate) async fn subscribe(
    client: WyrmClient,
    pattern: String,
    keep: KeyFilter,
) -> Result<EventStream<ValEvent>> {
    let ke = format!("{pattern}/{SUFFIX_VAL}");
    let s = client.session();
    let dropped = Arc::new(AtomicU64::new(0));
    let latest = Policy::Latest {
        queue: VecDeque::new(),
        pending: HashMap::new(),
        order: VecDeque::new(),
    };
    let intake = Intake::new(Vals::new(latest, 1, dropped.clone()));
    // Live first, stored second (no lost update); both into one buffer,
    // newer `t` wins per key and nothing older than what was handed out.
    // The subscriber never waits for anything: live values come from now on.
    let sub = s
        .declare_subscriber(&ke)
        .with(live_feed(&intake, &keep))
        .await?;
    let stored = Stored {
        session: s.clone(),
        ke,
        timeout: client.timeout,
    };
    let first = if client.stored_reads.is_empty() {
        s.get(&stored.ke)
            .timeout(client.timeout)
            .with(stored_feed(&intake, &keep, Vec::new()))
            .await?;
        None
    } else {
        // A bounded client reads the stored value when its turn comes. The
        // stream runs the wait itself (no task). The turns go with the
        // read's feed, which Zenoh drops after the last reply (or the
        // timeout).
        let (windows, st) = (client.stored_reads.clone(), stored.clone());
        let (intake, keep) = (intake.clone(), keep.clone());
        let first: FirstRead = Box::pin(async move {
            let mut turns = Vec::with_capacity(windows.len());
            for w in windows {
                match w.acquire_owned().await {
                    Ok(t) => turns.push(t),
                    Err(e) => {
                        debug!("stored reads: {e}");
                        intake.update(|v| v.gets = v.gets.saturating_sub(1));
                        return;
                    }
                }
            }
            // on an error the feed is dropped, and that ends this `get`
            let feed = stored_feed(&intake, &keep, turns);
            if let Err(e) = st.session.get(&st.ke).timeout(st.timeout).with(feed).await {
                debug!("stored value: {e}");
            }
        });
        Some(first)
    };
    Ok(EventStream::new(
        ValReader {
            intake,
            keep,
            _sub: Box::new(sub),
            stored: Some(stored),
            first,
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
    let keep: KeyFilter = Arc::new(|_| true);
    let intake = Intake::new(Vals::new(queue, 0, dropped.clone()));
    let sub = client
        .session()
        .declare_subscriber(format!("{pattern}/{SUFFIX_VAL}"))
        .advanced()
        .history(HistoryConfig::default().detect_late_publishers())
        .recovery(RecoveryConfig::default().heartbeat())
        .subscriber_detection()
        .with(live_feed(&intake, &keep))
        .await?;
    Ok(EventStream::new(
        ValReader {
            intake,
            keep,
            _sub: Box::new(sub),
            stored: None,
            first: None,
        },
        dropped,
    ))
}

/// A `subscribe` stream of the node keys `keep` accepts, fed by hand
/// (`testkit::value_stream`, `testkit::value_stream_filtered`).
#[cfg(feature = "testkit")]
pub(crate) fn fed(keep: KeyFilter) -> (zenoh::handlers::Callback<ZSample>, EventStream<ValEvent>) {
    use zenoh::handlers::IntoHandler;
    let dropped = Arc::new(AtomicU64::new(0));
    let latest = Policy::Latest {
        queue: VecDeque::new(),
        pending: HashMap::new(),
        order: VecDeque::new(),
    };
    let intake = Intake::new(Vals::new(latest, 0, dropped.clone()));
    let (cb, ()) = live_feed(&intake, &keep).into_handler();
    let reader = ValReader {
        intake,
        keep,
        _sub: Box::new(()),
        stored: None,
        first: None,
    };
    (cb, EventStream::new(reader, dropped))
}

/// The event of a `…/~val` sample whose node key `keep` accepts. The filter
/// runs first, on the key as Zenoh holds it: a refused sample is neither
/// copied nor decoded, and never reaches the buffer.
fn to_val(smp: &ZSample, keep: &KeyFilter) -> Option<ValEvent> {
    let key = smp
        .key_expr()
        .as_str()
        .strip_suffix(SUFFIX_VAL)?
        .strip_suffix('/')?;
    if !keep(key) {
        return None;
    }
    let key = key.to_owned();
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
            queue: VecDeque::new(),
            pending: HashMap::new(),
            order: VecDeque::new(),
        };
        Vals::new(p, 1, Arc::default())
    }

    /// The `~val` sample of [`smp`] as Zenoh delivers it.
    fn zsmp(key: &str, t: u64) -> ZSample {
        let s = Sample {
            v: Value::UInt(t),
            q: Quality::Good,
            t,
        };
        let key = zenoh::key_expr::KeyExpr::try_from(format!("{key}/{SUFFIX_VAL}")).unwrap();
        let payload = wyrm_core::codec::to_vec(&s).unwrap();
        zenoh::sample::SampleBuilder::put(key, payload).into()
    }

    fn drain(v: &mut Vals) -> Vec<ValEvent> {
        std::iter::from_fn(|| match v.pop() {
            Some(Pop::Event(ev)) => Some(ev),
            _ => None,
        })
        .collect()
    }

    /// Fill the lossless queue, so the next events go to overflow mode.
    fn fill_queue(v: &mut Vals) {
        for t in 1..=VALUE_BUFFER as u64 {
            v.push(smp("fill", t));
        }
    }

    #[test]
    fn every_sample_in_order_while_it_fits() {
        let mut v = latest();
        v.push(smp("a", 5)); // live during the stored get
        v.push(smp("b", 1));
        v.push(smp("a", 3)); // stored, older than a 5: never after it
        v.push(smp("b", 1)); // stored, the same as b 1: once
        v.push(smp("a", 6));
        v.push(smp("b", 2));
        assert_eq!(
            drain(&mut v),
            [smp("a", 5), smp("b", 1), smp("a", 6), smp("b", 2)]
        );
        assert_eq!(v.dropped.load(Ordering::Relaxed), 0, "nothing lost");
        v.push(smp("a", 4)); // older than what was handed out
        v.push(ValEvent::Removed("b".into()));
        assert_eq!(drain(&mut v), [ValEvent::Removed("b".into())]);
        assert!(v.pop().is_none(), "the stored get is still open");
        v.gets = 0;
        v.live_closed = true;
        assert!(matches!(v.pop(), Some(Pop::End)));
    }

    /// The historian's case: quick samples of one key, fewer than the
    /// queue holds, all arrive in order (All Data, Point Change).
    #[test]
    fn quick_samples_of_one_key_all_arrive() {
        let mut v = latest();
        let n = VALUE_BUFFER as u64;
        for t in 1..=n {
            v.push(smp("p", t));
        }
        let got = drain(&mut v);
        assert_eq!(got.len() as u64, n);
        assert!(got.iter().zip(1..).all(|(e, t)| *e == smp("p", t)));
        assert_eq!(v.dropped.load(Ordering::Relaxed), 0);
    }

    #[test]
    fn beyond_the_queue_the_newest_per_key_wins_then_lossless_again() {
        let mut v = latest();
        fill_queue(&mut v);
        v.push(smp("a", 1)); // overflow mode
        v.push(smp("a", 2)); // replaces a 1
        v.push(smp("a", 1)); // older: a 2 stays
        v.push(smp("b", 7));
        assert_eq!(v.dropped.load(Ordering::Relaxed), 2);
        let got = drain(&mut v);
        assert_eq!(got.len(), VALUE_BUFFER + 2);
        assert_eq!(got[VALUE_BUFFER..], [smp("a", 2), smp("b", 7)]);
        // drained: every sample counts again
        v.push(smp("a", 3));
        v.push(smp("a", 4));
        assert_eq!(drain(&mut v), [smp("a", 3), smp("a", 4)]);
        assert_eq!(v.dropped.load(Ordering::Relaxed), 2);
    }

    #[test]
    fn pending_keys_are_bounded_and_read_again() {
        let mut v = latest();
        fill_queue(&mut v);
        let n = MAX_PENDING_KEYS as u64 + 10;
        for k in 0..n {
            v.push(smp(&format!("k{k}"), 1));
        }
        let Policy::Latest { pending, .. } = &v.policy else {
            panic!()
        };
        assert_eq!(pending.len(), MAX_PENDING_KEYS);
        assert_eq!(v.dropped.load(Ordering::Relaxed), 10);
        assert_eq!(drain(&mut v).len(), VALUE_BUFFER + MAX_PENDING_KEYS);
        // the first stored get is still open: no second one yet
        assert!(v.pop().is_none());
        v.gets = 0; // it ends
        assert!(matches!(v.pop(), Some(Pop::Resync)));
        assert_eq!(v.gets, 1);
        // the stored values again: the keys that did not fit arrive
        for k in 0..n {
            v.push(smp(&format!("k{k}"), 1));
        }
        assert_eq!(drain(&mut v).len(), 10, "only those not handed out yet");
    }

    /// Security review: a pattern over more keys than the buffer, with a
    /// consumer that never catches up (every round brings newer values),
    /// ends after `MAX_RESYNCS` reads again, never loops.
    #[test]
    fn reads_again_are_bounded() {
        let mut v = latest();
        let n = (VALUE_BUFFER + 2 * MAX_PENDING_KEYS) as u64;
        let mut resyncs = 0;
        for round in 1..=20u64 {
            // the stored values of this round, newer than the last ones
            for k in 0..n {
                v.push(smp(&format!("k{k}"), round));
            }
            // this round's get ends; the consumer takes what waits, and
            // then the stream decides
            v.gets = v.gets.saturating_sub(1);
            let next = loop {
                match v.pop() {
                    Some(Pop::Event(_)) => {}
                    other => break other,
                }
            };
            match next {
                Some(Pop::Resync) => resyncs += 1,
                Some(Pop::End) => break,
                _ => panic!("round {round}: neither a read again nor the end"),
            }
        }
        assert_eq!(resyncs, MAX_RESYNCS);
        let e = v.failed.clone().expect("ended by a limit");
        assert!(e.is(wyrm_core::Status::ResourceExhausted), "{e}");
        assert!(matches!(v.pop(), Some(Pop::End)));
    }

    #[test]
    fn a_consumer_that_catches_up_starts_the_count_again() {
        let mut v = latest();
        v.resyncs = MAX_RESYNCS;
        v.gets = 0;
        assert!(v.pop().is_none());
        assert_eq!(v.resyncs, 0);
    }

    #[test]
    fn the_keys_of_one_stream_are_bounded() {
        let mut v = latest();
        v.gets = 0;
        for k in 0..MAX_STREAM_KEYS {
            v.push(smp(&format!("k{k}"), 1));
            assert!(matches!(v.pop(), Some(Pop::Event(_))));
        }
        v.push(smp("one-more", 1));
        assert!(matches!(v.pop(), Some(Pop::End)));
        let e = v.failed.clone().expect("ended by a limit");
        assert!(e.is(wyrm_core::Status::ResourceExhausted), "{e}");
        assert!(v.last_t.is_empty(), "freed");
        v.push(smp("later", 2));
        assert!(matches!(v.pop(), Some(Pop::End)));
    }

    #[test]
    fn a_refused_key_takes_no_memory() {
        use zenoh::handlers::IntoHandler;
        // through the handler Zenoh calls: the filter runs there, before the buffer
        let asked = Arc::new(AtomicU64::new(0));
        let asked2 = asked.clone();
        let keep: KeyFilter = Arc::new(move |k: &str| {
            asked2.fetch_add(1, Ordering::Relaxed);
            !k.starts_with("secret")
        });
        let intake = Intake::new(latest());
        let (cb, ()) = live_feed(&intake, &keep).into_handler();
        let waiting = |v: &Vals| match &v.policy {
            Policy::Latest { queue, pending, .. } => queue.len() + pending.len(),
            Policy::Queue(q) => q.len(),
        };
        for t in 1..=100 {
            cb.call(zsmp("secret/x", t));
        }
        assert_eq!(intake.with(waiting), 0);
        assert_eq!(intake.with(|v| v.last_t.len()), 0);
        cb.call(zsmp("open", 1));
        // once per sample: the filter is the caller's (the gateway's grants), not free
        assert_eq!(asked.load(Ordering::Relaxed), 101);
        let mut got = Vec::new();
        intake.update(|v| got = drain(v));
        assert_eq!(got, [smp("open", 1)]);
        assert_eq!(intake.with(|v| v.dropped.load(Ordering::Relaxed)), 0);
    }

    /// The value buffer as it was before the fan-in work (docs/backlog.md §14), kept as
    /// the model: the filter inside `push`, the key looked up three times and copied in
    /// `pop`. [`the_same_input_gives_the_same_output`] runs both on one input.
    struct Model {
        queue: VecDeque<ValEvent>,
        pending: HashMap<String, ValEvent>,
        order: VecDeque<String>,
        keep: KeyFilter,
        last_t: HashMap<String, u64>,
        gets: usize,
        overflowed: bool,
        live_closed: bool,
        resyncs: u32,
        failed: bool,
        dropped: u64,
    }

    impl Model {
        fn fail(&mut self) {
            self.order.clear();
            let waiting =
                std::mem::take(&mut self.pending).len() + std::mem::take(&mut self.queue).len();
            self.dropped += waiting as u64;
            self.last_t = HashMap::new();
            self.failed = true;
        }

        fn push(&mut self, ev: ValEvent) {
            if self.failed || !(self.keep)(ev.key()) {
                return;
            }
            if let ValEvent::Sample { key, sample, .. } = &ev {
                if self.last_t.get(key).is_some_and(|t| *t >= sample.t) {
                    return;
                }
            }
            if self.order.is_empty() && self.queue.len() < VALUE_BUFFER {
                self.queue.push_back(ev);
                return;
            }
            let lost =
                match self.pending.get_mut(ev.key()) {
                    None if self.order.len() >= MAX_PENDING_KEYS => {
                        self.overflowed = true;
                        1
                    }
                    None => {
                        self.order.push_back(ev.key().to_owned());
                        self.pending.insert(ev.key().to_owned(), ev);
                        0
                    }
                    Some(old) => match (&*old, &ev) {
                        (
                            ValEvent::Sample { sample: a, .. },
                            ValEvent::Sample { sample: b, .. },
                        ) if b.t == a.t => 0,
                        (
                            ValEvent::Sample { sample: a, .. },
                            ValEvent::Sample { sample: b, .. },
                        ) if b.t < a.t => 1,
                        _ => {
                            *old = ev;
                            1
                        }
                    },
                };
            self.dropped += lost;
        }

        fn pop(&mut self) -> Out {
            if self.failed {
                return Out::End;
            }
            loop {
                let ev = self.queue.pop_front().or_else(|| {
                    std::iter::from_fn(|| self.order.pop_front())
                        .find_map(|k| self.pending.remove(&k))
                });
                let Some(ev) = ev else { break };
                match &ev {
                    ValEvent::Sample { key, sample, .. } => {
                        if self.last_t.get(key).is_some_and(|t| *t >= sample.t) {
                            continue;
                        }
                        if self.last_t.len() >= MAX_STREAM_KEYS && !self.last_t.contains_key(key) {
                            self.fail();
                            return Out::End;
                        }
                        self.last_t.insert(key.clone(), sample.t);
                    }
                    ValEvent::Removed(key) => {
                        self.last_t.remove(key);
                    }
                }
                return Out::Event(ev);
            }
            if self.gets == 0 {
                if self.overflowed {
                    if self.resyncs >= MAX_RESYNCS {
                        self.fail();
                        return Out::End;
                    }
                    self.overflowed = false;
                    self.resyncs += 1;
                    self.gets += 1;
                    return Out::Resync;
                }
                self.resyncs = 0;
            }
            if self.live_closed && self.gets == 0 {
                Out::End
            } else {
                Out::Idle
            }
        }
    }

    #[derive(Debug, PartialEq)]
    enum Out {
        Event(ValEvent),
        Resync,
        End,
        Idle,
    }

    fn out(p: Option<Pop>) -> Out {
        match p {
            Some(Pop::Event(ev)) => Out::Event(ev),
            Some(Pop::Resync) => Out::Resync,
            Some(Pop::End) => Out::End,
            None => Out::Idle,
        }
    }

    /// One recorded input (events of `keys` keys in bursts of up to `burst`, times that
    /// go on, repeat and go back, removals, refused keys, reads that end, a session that
    /// closes) through the model and through the buffer: every `pop` gives the same, in
    /// the same order, and both count the same losses.
    fn same_output(seed: u64, keys: u64, burst: u64, steps: usize) {
        let keep: KeyFilter = Arc::new(|k: &str| !k.starts_with("secret"));
        let mut m = Model {
            queue: VecDeque::new(),
            pending: HashMap::new(),
            order: VecDeque::new(),
            keep: keep.clone(),
            last_t: HashMap::new(),
            gets: 1,
            overflowed: false,
            live_closed: false,
            resyncs: 0,
            failed: false,
            dropped: 0,
        };
        let mut v = latest();
        // xorshift64: the same input on every run
        let mut x = seed;
        let mut rnd = move |n: u64| {
            x ^= x << 13;
            x ^= x >> 7;
            x ^= x << 17;
            x % n
        };
        let mut clock: HashMap<u64, u64> = HashMap::new();
        let (mut events, mut ends, mut resyncs) = (0u64, 0u64, 0u64);
        for step in 0..steps {
            for _ in 0..rnd(burst) + 1 {
                let k = rnd(keys);
                let key = match k % 16 {
                    0 => format!("secret/p{k}"),
                    _ => format!("wy/s/downstream/l/p{k}"),
                };
                let ev = if rnd(64) == 0 {
                    ValEvent::Removed(key)
                } else {
                    // mostly forward; sometimes the same time again, or an older one
                    let t = clock.entry(k).or_insert(10);
                    match rnd(8) {
                        0 => {}
                        1 => *t = t.saturating_sub(rnd(3) + 1),
                        _ => *t += rnd(4) + 1,
                    }
                    smp(&key, *t)
                };
                m.push(ev.clone());
                // the buffer's filter runs in its feed (`to_val`)
                if keep(ev.key()) {
                    v.push(ev);
                }
            }
            if rnd(6) == 0 {
                // a stored read ends
                m.gets = m.gets.saturating_sub(1);
                v.gets = v.gets.saturating_sub(1);
            }
            if step + 1 == steps {
                m.live_closed = true;
                v.live_closed = true;
            }
            // the consumer reads some, sometimes all
            let reads = match rnd(4) {
                0 => u64::MAX,
                _ => rnd(burst * 2),
            };
            for _ in 0..reads {
                let (a, b) = (m.pop(), out(v.pop()));
                assert_eq!(a, b, "seed {seed}, step {step}");
                match a {
                    Out::Event(_) => events += 1,
                    Out::Resync => resyncs += 1,
                    Out::End => {
                        ends += 1;
                        break;
                    }
                    Out::Idle => break,
                }
            }
            assert_eq!(m.dropped, v.dropped.load(Ordering::Relaxed), "step {step}");
            assert_eq!(m.failed, v.failed.is_some(), "step {step}");
            assert_eq!(m.last_t, v.last_t, "seed {seed}, step {step}");
        }
        // what still waits comes out the same
        loop {
            let (a, b) = (m.pop(), out(v.pop()));
            assert_eq!(a, b, "seed {seed}, the rest");
            match a {
                Out::Event(_) => events += 1,
                Out::Resync => {
                    resyncs += 1;
                    m.gets = m.gets.saturating_sub(1);
                    v.gets = v.gets.saturating_sub(1);
                }
                Out::End | Out::Idle => break,
            }
        }
        assert_eq!(m.dropped, v.dropped.load(Ordering::Relaxed));
        assert!(events > 0, "seed {seed}: nothing came out");
        // said once, so a run that tests nothing is seen
        println!(
            "seed {seed}: {events} events, {} dropped, {resyncs} reads again, {ends} ends",
            m.dropped
        );
    }

    #[test]
    fn the_same_input_gives_the_same_output() {
        // a consumer that keeps up: the lossless queue alone
        same_output(0x9e37_79b9_7f4a_7c15, 1_000, 600, 400);
        // bursts beyond the queue: overflow mode, newest per key
        same_output(0x2545_f491_4f6c_dd1d, 3_000, 9_000, 120);
        // more keys than may wait: values dropped, stored values read again, the limit
        same_output(0xd1b5_4a32_d192_ed03, 12_000, 30_000, 60);
        // more keys than one stream may hand out: it ends with the limit
        same_output(0x94d0_49bb_1331_11eb, 40_000, 3_000, 200);
    }

    #[test]
    fn the_reliable_queue_drops_the_oldest() {
        let mut v = Vals::new(Policy::Queue(VecDeque::new()), 0, Arc::default());
        for t in 0..RELIABLE_BUFFER as u64 + 2 {
            v.push(smp("a", t));
        }
        let got = drain(&mut v);
        assert_eq!(got.len(), RELIABLE_BUFFER);
        assert_eq!(got[0], smp("a", 2));
        assert_eq!(v.dropped.load(Ordering::Relaxed), 2);
    }

    /// Children `a`, `b`, `c` answer in 300 ms; `silent` gives no reply
    /// (each read waits the whole window) until 5 s after the start.
    fn reader(start: tokio::time::Instant) -> ReadLink {
        Arc::new(move |name: String| {
            Box::pin(async move {
                if name == "silent" && start.elapsed() < Duration::from_secs(5) {
                    tokio::time::sleep(crate::LIST_READ_WINDOW).await;
                    return LinkMeta::Silent;
                }
                tokio::time::sleep(Duration::from_millis(300)).await;
                LinkMeta::Read(NodeMeta::folder().display(name))
            })
        })
    }

    fn names(v: &[&str]) -> Vec<String> {
        v.iter().map(|s| s.to_string()).collect()
    }

    /// One silent link costs a snapshot one window, not one per link, and
    /// the others are in it.
    #[tokio::test(start_paused = true)]
    async fn a_snapshot_reads_all_links_at_once() {
        let start = tokio::time::Instant::now();
        let kids = names(&["a", "b", "c", "silent"]);
        let (out, silent) = crate::read_links(kids, reader(start)).await;
        assert!(
            start.elapsed() <= crate::LIST_READ_WINDOW + Duration::from_millis(5),
            "{:?}",
            start.elapsed()
        );
        let got: Vec<&str> = out.iter().map(|c| c.name.as_str()).collect();
        assert_eq!(got, ["a", "b", "c"]);
        assert_eq!(silent, ["silent"]);
    }

    /// The list's pending reads: the others come within the window, each
    /// at once; the silent one comes later, when it answers.
    #[tokio::test(start_paused = true)]
    async fn a_silent_link_never_holds_up_the_others() {
        let start = tokio::time::Instant::now();
        let mut p = PendingLinks::new(reader(start));
        for n in ["silent", "a", "b", "c"] {
            p.start(n.into(), false);
        }
        let mut got = Vec::new();
        while got.len() < 4 {
            if let Some((name, r)) = p.next().await {
                assert!(matches!(r, LinkMeta::Read(_)), "{name}: {r:?}");
                got.push((name, start.elapsed()));
            }
        }
        for (name, at) in &got[..3] {
            assert_ne!(name, "silent");
            assert!(*at < crate::LIST_READ_WINDOW, "{name} at {at:?}");
        }
        let (name, at) = &got[3];
        assert_eq!(name, "silent");
        assert!(*at >= Duration::from_secs(5), "{at:?}");
        // silent through 1.5 s reads with 1, 2, 4 s pauses between them
        assert!(*at < Duration::from_secs(13), "{at:?}");
        assert!(p.reads.is_empty() && p.ids.is_empty());
    }

    /// A pending link whose token goes is forgotten: its read is aborted
    /// and never reported.
    #[tokio::test(start_paused = true)]
    async fn a_forgotten_link_is_never_reported() {
        let start = tokio::time::Instant::now();
        let mut p = PendingLinks::new(reader(start));
        p.start("silent".into(), false);
        p.start("a".into(), false);
        p.forget("silent");
        let mut got = Vec::new();
        while !p.reads.is_empty() {
            if let Some((name, _)) = p.next().await {
                got.push(name);
            }
        }
        assert_eq!(got, ["a"]);
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
