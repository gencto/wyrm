//! `LinkCtx`: the driver's only handle to the tree and the bus.

use crate::error::{LinkError, Result};
use crate::support::{Metrics, SecretStore};
use crate::tree::{Changed, NodeTree};
use std::collections::{BTreeMap, HashMap};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex, RwLock, Weak};
use std::time::{Duration, Instant};
use tracing::Instrument;
pub use wyrm_core::clock::now_us;
use wyrm_core::keyspace::{self, SUFFIX_META, SUFFIX_VAL};
use wyrm_core::meta::ActionMeta;
use wyrm_core::{Attachment, NodeMeta, Quality, Sample, Value};
use zenoh::bytes::ZBytes;
use zenoh::liveliness::LivelinessToken;
use zenoh::pubsub::Publisher;
use zenoh::qos::{CongestionControl, Priority};
use zenoh::Session;

/// The root attribute that says the responder answers `~act/<a>?check` (spec 05 0.2.33).
pub const CHECK_ATTR: &str = "check";

/// After a parent's `~meta` (its `children`) was put, the next put of a
/// parent waits this many times as long as that put took: the lists of a
/// burst of new children cost at most 1/(1 + `HOLD_FACTOR`) of its time.
const HOLD_FACTOR: u32 = 4;

/// The longest a changed child list waits for its put.
const HOLD_MAX: Duration = Duration::from_millis(500);

/// A put of a changed child list that failed is tried again after this.
const RETRY: Duration = Duration::from_millis(250);

/// Parents whose child list changed and whose `~meta` is not put yet.
///
/// A parent's `~meta` lists every child, so one put per new child makes a
/// burst of n children cost n² (docs/backlog.md §14). The first change of a
/// list is put at once, as it always was; while the hold that follows it
/// lasts, a changed parent is only noted here and one task
/// ([`flush_parents`]) puts it when the hold ends, once, with the list as
/// it is then. A set, not a queue: it holds a path once, so it never grows
/// beyond the tree, and nothing is lost when the driver is faster than the
/// puts.
///
/// A parent is noted before its put, also when the put is made at once,
/// and the note goes only when a put that carried that change (or a later
/// one) has succeeded, the node is gone or the link has stopped: a put
/// that failed or was dropped half-way is made again by the task.
#[derive(Default)]
struct Parents {
    state: Mutex<ParentsState>,
    /// Wakes [`flush_parents`]: a parent was noted, or the link has ended.
    wake: tokio::sync::Notify,
    /// Puts of a parent's `~meta` for a changed child list (for tests and
    /// benches: it grows much slower than the children of a burst).
    puts: AtomicU64,
    /// Test hooks: `~meta` puts to fail, and a pause before each put.
    #[cfg(feature = "harness")]
    hooks: Mutex<(u32, Duration)>,
}

#[derive(Default)]
struct ParentsState {
    /// Parent → the number of its last change (`changes`).
    dirty: BTreeMap<String, u64>,
    changes: u64,
    /// Until then a changed parent is noted, not put.
    hold_until: Option<Instant>,
}

/// Until disarmed: the put of a noted parent did not succeed (an error, or
/// its future was dropped). The note stays; the task tries again.
struct Unfinished<'a> {
    parents: &'a Parents,
    armed: bool,
}

impl Drop for Unfinished<'_> {
    fn drop(&mut self) {
        if self.armed {
            let retry = Instant::now() + RETRY;
            let mut st = self.parents.state();
            if st.hold_until.is_none_or(|until| until < retry) {
                st.hold_until = Some(retry);
            }
            drop(st);
            self.parents.wake.notify_one();
        }
    }
}

impl Parents {
    fn state(&self) -> std::sync::MutexGuard<'_, ParentsState> {
        self.state.lock().unwrap_or_else(|p| p.into_inner())
    }

    /// Start the hold that follows parent puts which took `took`.
    fn hold_after(&self, took: Duration) {
        let hold = took.saturating_mul(HOLD_FACTOR).min(HOLD_MAX);
        self.state().hold_until = Some(Instant::now() + hold);
    }

    /// The number of the noted change of `path`, if one waits.
    fn noted(&self, path: &str) -> Option<u64> {
        self.state().dirty.get(path).copied()
    }

    /// Drop the note of `path` unless it changed again after `change`.
    fn done(&self, path: &str, change: u64) {
        let mut st = self.state();
        if st.dirty.get(path) == Some(&change) {
            st.dirty.remove(path);
        }
    }
}

pub(crate) struct Inner {
    pub session: Session,
    pub site: String,
    pub link: String,
    /// `wy/<site>/downstream/<link>`
    pub prefix: String,
    pub tree: RwLock<NodeTree>,
    tokens: Mutex<HashMap<String, LivelinessToken>>,
    /// One `~meta` put at a time, each with the tree as it is when its turn
    /// comes: the last put of a node always carries its newest meta, also
    /// when the driver's tasks and [`flush_parents`] put the same node.
    meta_turn: tokio::sync::Mutex<()>,
    parents: Arc<Parents>,
    #[cfg(feature = "advanced")]
    reliable: Mutex<HashMap<String, Arc<zenoh_ext::AdvancedPublisher<'static>>>>,
    /// Set by `LinkHandle::stop`/drop; every mutation then fails with `closed`.
    closed: AtomicBool,
    pub secrets: SecretStore,
    pub metrics: Metrics,
    pub data_dir: Option<PathBuf>,
    pub grants: Vec<(String, wyrm_core::Perm)>,
    pub driver_timeout: std::time::Duration,
    /// Paths whose `~meta` or `~val` a requester read ([`LinkCtx::reads`]).
    reads: tokio::sync::broadcast::Sender<String>,
}

/// What the host hands to a new [`LinkCtx`] besides its address.
pub(crate) struct HostState {
    pub secrets: SecretStore,
    pub data_dir: Option<PathBuf>,
    pub grants: Vec<(String, wyrm_core::Perm)>,
    pub driver_timeout: std::time::Duration,
}

/// Cheap to clone; all clones share one tree.
#[derive(Clone)]
pub struct LinkCtx(pub(crate) Arc<Inner>);

impl std::fmt::Debug for LinkCtx {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("LinkCtx")
            .field("prefix", &self.0.prefix)
            .finish_non_exhaustive()
    }
}

fn encode<T: minicbor::Encode<()>>(v: &T) -> Result<Vec<u8>> {
    wyrm_core::codec::to_vec(v).map_err(|e| LinkError::internal(e.to_string()))
}

impl LinkCtx {
    pub(crate) fn new(
        session: Session,
        site: &str,
        link: &str,
        prefix: String,
        root: NodeMeta,
        host: HostState,
    ) -> Self {
        let parents = Arc::new(Parents::default());
        let ctx = Self(Arc::new(Inner {
            session,
            site: site.to_owned(),
            link: link.to_owned(),
            prefix,
            tree: RwLock::new(NodeTree::new(root)),
            tokens: Mutex::new(HashMap::new()),
            meta_turn: tokio::sync::Mutex::new(()),
            parents: parents.clone(),
            #[cfg(feature = "advanced")]
            reliable: Mutex::new(HashMap::new()),
            closed: AtomicBool::new(false),
            secrets: host.secrets,
            metrics: Metrics::default(),
            data_dir: host.data_dir,
            grants: host.grants,
            driver_timeout: host.driver_timeout,
            reads: tokio::sync::broadcast::channel(64).0,
        }));
        // in a `link{id}` span of its own, so that the link's log filter takes its lines
        let span = tracing::error_span!("link", id = %link);
        tokio::spawn(flush_parents(Arc::downgrade(&ctx.0), parents).instrument(span));
        ctx
    }

    /// Test hook: the next `n` puts of a `~meta` fail.
    #[cfg(feature = "harness")]
    pub fn fail_meta_puts(&self, n: u32) {
        self.0
            .parents
            .hooks
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .0 = n;
    }

    /// Test hook: every `~meta` put waits this long between reading the
    /// tree and the put.
    #[cfg(feature = "harness")]
    pub fn pause_meta_puts(&self, pause: Duration) {
        self.0
            .parents
            .hooks
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .1 = pause;
    }

    /// How many times a parent's `~meta` was put because its child list
    /// changed (a child declared or removed).
    #[cfg(feature = "harness")]
    pub fn parent_puts(&self) -> u64 {
        self.0.parents.puts.load(Ordering::Relaxed)
    }

    /// Paths of this link whose `~meta` or `~val` a requester read, as they
    /// come (lossy: a slow receiver gets `Lagged`). For a driver that
    /// publishes something at once when it is looked at.
    pub fn reads(&self) -> tokio::sync::broadcast::Receiver<String> {
        self.0.reads.subscribe()
    }

    /// Tell [`LinkCtx::reads`] receivers, if any, that `path` was read.
    pub(crate) fn note_read(&self, path: &str) {
        if self.0.reads.receiver_count() > 0 {
            let _ = self.0.reads.send(path.to_owned());
        }
    }

    pub fn site(&self) -> &str {
        &self.0.site
    }

    pub fn link(&self) -> &str {
        &self.0.link
    }

    /// Full key of `path` with `suffix` (`"~meta"`, `"~val"`, …). Empty
    /// `suffix` gives the node key itself.
    pub fn key(&self, path: &str, suffix: &str) -> String {
        let mut k = self.0.prefix.clone();
        for part in [path, suffix] {
            if !part.is_empty() {
                k.push('/');
                k.push_str(part);
            }
        }
        k
    }

    /// Mark the link stopped and drop per-node liveliness, even while driver
    /// tasks still hold clones of this context.
    pub(crate) fn close(&self) {
        self.0.closed.store(true, Ordering::Release);
        self.0
            .tokens
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .clear();
        #[cfg(feature = "advanced")]
        self.reliable().clear();
        // a stopped link puts nothing more: the flusher ends
        self.0.parents.state().dirty.clear();
        self.0.parents.wake.notify_one();
    }

    /// `true` after the link was stopped; driver tasks should exit.
    pub fn is_closed(&self) -> bool {
        self.0.closed.load(Ordering::Acquire)
    }

    fn ensure_open(&self) -> Result<()> {
        if self.is_closed() {
            Err(LinkError::new(wyrm_core::Status::Closed, "link stopped"))
        } else {
            Ok(())
        }
    }

    pub(crate) fn tree(&self) -> std::sync::RwLockReadGuard<'_, NodeTree> {
        self.0.tree.read().unwrap_or_else(|p| p.into_inner())
    }

    fn tree_mut(&self) -> std::sync::RwLockWriteGuard<'_, NodeTree> {
        self.0.tree.write().unwrap_or_else(|p| p.into_inner())
    }

    /// Snapshot of a node's full `~meta`, if declared.
    pub fn meta(&self, path: &str) -> Option<NodeMeta> {
        self.tree().get(path).map(|n| n.full())
    }

    /// Serve `doc` (CBOR) at `<path>/<suffix>` (`~def`, `~state`); `None` removes it.
    pub fn set_doc(&self, path: &str, suffix: &str, doc: Option<Vec<u8>>) -> Result<()> {
        if !matches!(suffix, "~def" | "~state") {
            return Err(LinkError::invalid_parameter(format!(
                "{suffix} is not a document suffix"
            )));
        }
        self.tree_mut().set_doc(path, suffix, doc)
    }

    /// Last value published for `path`.
    pub fn last(&self, path: &str) -> Option<Sample> {
        self.tree().get(path).and_then(|n| n.last.clone())
    }

    /// Declare or replace a node; the parent must already exist. Publishes the
    /// node's `~meta` and, for a new node, the parent's (new `children`): at
    /// once, or, in a burst of new children, a moment later and once for the
    /// children declared meanwhile (`Parents`).
    pub async fn declare_node(&self, path: &str, meta: NodeMeta) -> Result<()> {
        self.ensure_open()?;
        let meta = if path.is_empty() {
            // spec 05 0.2.33: this responder checks `~act/<a>?check` without acting; a client
            // sends `?check` only where the root says so (an older one would run the action)
            meta.attr(CHECK_ATTR, true)
        } else {
            keyspace::validate_path(path)?;
            meta
        };
        let changed = self.tree_mut().declare(path, meta)?;
        #[cfg(feature = "advanced")]
        self.sync_reliable(path).await?;
        self.publish_changed(path, changed).await
    }

    /// Keep the AdvancedPublisher of `path` in line with its `cfg.qos`.
    #[cfg(feature = "advanced")]
    async fn sync_reliable(&self, path: &str) -> Result<()> {
        use zenoh_ext::{AdvancedPublisherBuilderExt, CacheConfig, MissDetectionConfig};
        let want = self
            .tree()
            .get(path)
            .filter(|n| n.is_leaf())
            .map(|n| (qos_level(&n.meta), cfg_uint(&n.meta, "qos_cache")));
        let has = self.reliable().contains_key(path);
        match want {
            Some((q, cache)) if q >= 2 && !has => {
                let p = self
                    .0
                    .session
                    .declare_publisher(self.key(path, SUFFIX_VAL))
                    .priority(Priority::Data)
                    .congestion_control(CongestionControl::Block)
                    .advanced()
                    .cache(CacheConfig::default().max_samples(cache.unwrap_or(100) as usize))
                    .sample_miss_detection(
                        MissDetectionConfig::default()
                            .heartbeat(std::time::Duration::from_millis(500)),
                    )
                    .publisher_detection()
                    .await?;
                self.reliable().insert(path.to_owned(), Arc::new(p));
            }
            Some((q, _)) if q < 2 && has => {
                self.reliable().remove(path);
            }
            None if has => {
                self.reliable().remove(path);
            }
            _ => {}
        }
        Ok(())
    }

    #[cfg(feature = "advanced")]
    fn reliable(
        &self,
    ) -> std::sync::MutexGuard<'_, HashMap<String, Arc<zenoh_ext::AdvancedPublisher<'static>>>>
    {
        self.0.reliable.lock().unwrap_or_else(|p| p.into_inner())
    }

    /// Add or replace one action on a node and publish its `~meta`.
    pub async fn declare_action(&self, path: &str, name: &str, action: ActionMeta) -> Result<()> {
        self.ensure_open()?;
        keyspace::validate_segment(name)?;
        let changed = self.tree_mut().declare_action(path, name, action)?;
        self.publish_changed(
            path,
            Changed {
                node: changed,
                parent: None,
            },
        )
        .await
    }

    /// Remove one action of a node (and publish its `~meta`); `false` if it
    /// had no such action.
    pub async fn remove_action(&self, path: &str, name: &str) -> Result<bool> {
        self.ensure_open()?;
        let removed = self.tree_mut().remove_action(path, name)?;
        if removed {
            self.publish_changed(
                path,
                Changed {
                    node: true,
                    parent: None,
                },
            )
            .await?;
        }
        Ok(removed)
    }

    /// Whether `path` is a declared node.
    pub fn has_node(&self, path: &str) -> bool {
        self.tree().get(path).is_some()
    }

    /// Remove a node with its subtree: deletes `~meta`/`~val` of every removed
    /// node, drops their liveliness tokens, republishes the parent's `~meta`.
    pub async fn remove_node(&self, path: &str) -> Result<()> {
        self.ensure_open()?;
        let parent = {
            // The removal and its deletes take a turn of the `~meta` puts: a
            // put of a removed node is either out before its delete or finds
            // no node any more, and a node declared again after the removal
            // puts its `~meta` after the delete.
            let _turn = self.0.meta_turn.lock().await;
            let (removed, parent) = self.tree_mut().remove(path)?;
            {
                let mut tokens = self.0.tokens.lock().unwrap_or_else(|p| p.into_inner());
                for p in &removed {
                    tokens.remove(p);
                }
            }
            #[cfg(feature = "advanced")]
            {
                let mut rel = self.reliable();
                for p in &removed {
                    rel.remove(p);
                }
            }
            {
                let mut st = self.0.parents.state();
                for p in &removed {
                    st.dirty.remove(p);
                }
            }
            for p in &removed {
                for suffix in [SUFFIX_META, SUFFIX_VAL] {
                    self.0
                        .session
                        .delete(self.key(p, suffix))
                        .priority(Priority::DataHigh)
                        .congestion_control(CongestionControl::Block)
                        .await?;
                }
            }
            parent
        };
        self.publish_parent(&parent).await
    }

    /// Per-node liveliness at `downstream/<link>/<path>` for nodes that come and go
    /// (devices on a bus). `alive = false` drops the token.
    pub async fn set_dynamic(&self, path: &str, alive: bool) -> Result<()> {
        if self.tree().get(path).is_none() {
            return Err(LinkError::not_found(path.to_owned()));
        }
        if alive {
            self.ensure_open()?;
            let has = self
                .0
                .tokens
                .lock()
                .unwrap_or_else(|p| p.into_inner())
                .contains_key(path);
            if !has {
                let token = self
                    .0
                    .session
                    .liveliness()
                    .declare_token(self.key(path, ""))
                    .await?;
                let mut tokens = self.0.tokens.lock().unwrap_or_else(|p| p.into_inner());
                // `close` may have run while the token was being declared.
                self.ensure_open()?;
                tokens.insert(path.to_owned(), token);
            }
        } else {
            self.0
                .tokens
                .lock()
                .unwrap_or_else(|p| p.into_inner())
                .remove(path);
        }
        Ok(())
    }

    /// Publish a value: `put ~val {v,q,t}`. `t` is the measurement time in µs.
    pub async fn update(&self, path: &str, v: impl Into<Value>, q: Quality, t: u64) -> Result<()> {
        self.update_sample(path, Sample { v: v.into(), q, t }, None)
            .await
    }

    /// Like [`update`](Self::update) with an extended quality code in the
    /// attachment (`bad/comm_fail`, `uncertain/stale`, …).
    pub async fn update_sample(&self, path: &str, s: Sample, qual: Option<&str>) -> Result<()> {
        self.ensure_open()?;
        let payload = encode(&s)?;
        self.tree_mut().set_last(path, s)?;
        #[cfg(feature = "advanced")]
        {
            let rel = self.reliable().get(path).cloned();
            if let Some(p) = rel {
                let mut put = p.put(payload);
                if let Some(qual) = qual {
                    put = put.attachment(qual_attachment(qual)?);
                }
                put.await?;
                Metrics::inc(&self.0.metrics.samples_out);
                return Ok(());
            }
        }
        let mut put = self
            .0
            .session
            .put(self.key(path, SUFFIX_VAL), payload)
            .priority(Priority::Data)
            .congestion_control(CongestionControl::Drop);
        // TODO(zenoh-unstable): Reliability per `cfg.qos` (default BestEffort).
        if let Some(qual) = qual {
            put = put.attachment(qual_attachment(qual)?);
        }
        put.await?;
        Metrics::inc(&self.0.metrics.samples_out);
        Ok(())
    }

    /// A declared publisher for a high-rate point (skips per-put key resolution).
    pub async fn publisher(&self, path: &str) -> Result<PointPublisher> {
        self.ensure_open()?;
        match self.tree().get(path) {
            Some(n) if n.is_leaf() => {}
            Some(_) => {
                return Err(LinkError::invalid_parameter(format!(
                    "{path} is a container"
                )))
            }
            None => return Err(LinkError::not_found(path.to_owned())),
        }
        #[cfg(feature = "advanced")]
        if let Some(p) = self.reliable().get(path).cloned() {
            return Ok(PointPublisher {
                ctx: self.clone(),
                path: path.to_owned(),
                inner: PubInner::Reliable(p),
            });
        }
        let publisher = self
            .0
            .session
            .declare_publisher(self.key(path, SUFFIX_VAL))
            .priority(Priority::Data)
            .congestion_control(CongestionControl::Drop)
            .await?;
        Ok(PointPublisher {
            ctx: self.clone(),
            path: path.to_owned(),
            inner: PubInner::Plain(publisher),
        })
    }

    /// Republish every last value with quality `q` (e.g. `Bad` +
    /// `bad/comm_fail` when the bus is lost). Values are kept; `t` = now.
    pub async fn mark_all(&self, q: Quality, qual: Option<&str>) -> Result<()> {
        let t = now_us();
        let samples: Vec<(String, Sample)> = self
            .tree()
            .iter()
            .filter_map(|(p, n)| {
                n.last.as_ref().map(|s| {
                    (
                        p.clone(),
                        Sample {
                            v: s.v.clone(),
                            q,
                            t,
                        },
                    )
                })
            })
            .collect();
        for (p, s) in samples {
            self.update_sample(&p, s, qual).await?;
        }
        Ok(())
    }

    /// Re-publish every `~meta` and last `~val` (after a router restart the
    /// memory storage is empty and list subscribers missed nothing they need).
    pub async fn republish(&self) -> Result<()> {
        let (paths, samples): (Vec<String>, Vec<(String, Sample)>) = {
            let tree = self.tree();
            (
                tree.iter().map(|(p, _)| p.clone()).collect(),
                tree.iter()
                    .filter_map(|(p, n)| n.last.clone().map(|s| (p.clone(), s)))
                    .collect(),
            )
        };
        for p in paths {
            self.publish_meta(&p).await?;
        }
        for (p, s) in samples {
            self.update_sample(&p, s, None).await?;
        }
        Ok(())
    }

    /// Raw Zenoh session for reading other branches (gateways, aggregators).
    /// Will become `&WyrmClient` once `wyrm-client` exists.
    pub fn client(&self) -> &Session {
        &self.0.session
    }

    pub fn secrets(&self) -> &SecretStore {
        &self.0.secrets
    }

    /// This link's requester key, when the broker gave it grants (secret
    /// [`crate::REQUESTER_KEY`]). Sign each request's `ptok` with it, with
    /// subject `link:<id>` (for example `wyrm_client::SigningTokens`).
    pub fn requester_key(&self) -> Option<ed25519_dalek::SigningKey> {
        let raw = self.0.secrets.get(crate::REQUESTER_KEY)?;
        let seed: [u8; 32] = raw.expose().try_into().ok()?;
        Some(ed25519_dalek::SigningKey::from_bytes(&seed))
    }

    pub fn metrics(&self) -> &Metrics {
        &self.0.metrics
    }

    /// Private directory owned by this link (state the connector keeps across
    /// restarts), or `None` when the host gives it none (tests, external
    /// links): the driver then keeps its state in memory.
    pub fn data_dir(&self) -> Option<&Path> {
        self.0.data_dir.as_deref()
    }

    /// What the broker granted this link as a requester: `(path, permission)`
    /// with the site already in the path. A request outside these cannot
    /// pass the router ACL, so a runtime may refuse it before it leaves.
    pub fn grants(&self) -> &[(String, wyrm_core::Perm)] {
        &self.0.grants
    }

    /// How long the SDK waits for one `on_set`/`on_invoke` before it answers
    /// the caller `timeout` (`LinkConfig::driver_timeout`, raised to
    /// [`Link::call_timeout`](crate::Link::call_timeout)).
    pub fn driver_timeout(&self) -> std::time::Duration {
        self.0.driver_timeout
    }

    /// Lay the broker's overlays over the tree (ADR 0016) and publish the
    /// `~meta` of every node they changed (and of its parent).
    pub(crate) async fn apply_overlays(&self, overlays: crate::tree::Overlays) -> Result<()> {
        let paths = self.tree_mut().set_overlays(overlays);
        for p in paths {
            self.publish_meta(&p).await?;
        }
        Ok(())
    }

    async fn publish_changed(&self, path: &str, changed: Changed) -> Result<()> {
        if changed.node {
            self.publish_meta(path).await?;
        }
        if let Some(parent) = changed.parent {
            self.publish_parent(&parent).await?;
        }
        Ok(())
    }

    /// `put ~meta` of a parent whose child list changed: now, or, while the
    /// hold after an earlier such put lasts, by [`flush_parents`] when it
    /// ends. The change is noted first and the note goes with the put that
    /// carried it.
    async fn publish_parent(&self, parent: &str) -> Result<()> {
        let parents = &self.0.parents;
        {
            let mut st = parents.state();
            st.changes += 1;
            let change = st.changes;
            match st.dirty.get_mut(parent) {
                Some(c) => *c = change,
                None => {
                    st.dirty.insert(parent.to_owned(), change);
                }
            }
            if st.hold_until.is_some_and(|until| Instant::now() < until) {
                drop(st);
                parents.wake.notify_one();
                return Ok(());
            }
        }
        let start = Instant::now();
        // also when this future is dropped while it waits for its turn
        let mut unfinished = Unfinished {
            parents,
            armed: true,
        };
        let done = self.put_meta(parent, false).await;
        // an error has armed the retry inside
        unfinished.armed = false;
        if done.is_ok() {
            parents.hold_after(start.elapsed());
        }
        done
    }

    /// `put ~meta` with the full meta of `path` (DataHigh + Block).
    pub(crate) async fn publish_meta(&self, path: &str) -> Result<()> {
        self.put_meta(path, false).await
    }

    /// [`publish_meta`](Self::publish_meta); with `noted_only`, nothing when
    /// no change of `path`'s child list waits (another put carried it).
    async fn put_meta(&self, path: &str, noted_only: bool) -> Result<()> {
        // One put at a time, the tree read inside the turn: a put never
        // carries an older meta than the put before it, and none follows the
        // delete of a removed node (`remove_node` takes the same turn).
        let _turn = self.0.meta_turn.lock().await;
        // a stopped link puts nothing more (its next start may already declare)
        self.ensure_open()?;
        let parents = &*self.0.parents;
        let noted = parents.noted(path);
        if noted_only && noted.is_none() {
            return Ok(());
        }
        let mut unfinished = Unfinished {
            parents,
            armed: noted.is_some(),
        };
        // Restricted nodes are never broadcast: `~meta` only on an authorized get.
        let meta = {
            let tree = self.tree();
            (!tree.restricted(path))
                .then(|| tree.full(path, false))
                .flatten()
        };
        if let Some(meta) = meta {
            #[cfg(feature = "harness")]
            self.meta_put_hooks().await?;
            self.0
                .session
                .put(self.key(path, SUFFIX_META), encode(&meta)?)
                .priority(Priority::DataHigh)
                .congestion_control(CongestionControl::Block)
                .await?;
            if noted.is_some() {
                parents.puts.fetch_add(1, Ordering::Relaxed);
            }
        }
        // put, or nothing to put (restricted, or the node is gone): this
        // change needs no put any more
        if let Some(change) = noted {
            parents.done(path, change);
        }
        unfinished.armed = false;
        Ok(())
    }

    #[cfg(feature = "harness")]
    async fn meta_put_hooks(&self) -> Result<()> {
        let (fail, pause) = {
            let mut h = self
                .0
                .parents
                .hooks
                .lock()
                .unwrap_or_else(|p| p.into_inner());
            let fail = h.0 > 0;
            h.0 = h.0.saturating_sub(1);
            (fail, h.1)
        };
        if !pause.is_zero() {
            tokio::time::sleep(pause).await;
        }
        if fail {
            return Err(LinkError::internal("test: this ~meta put fails"));
        }
        Ok(())
    }
}

/// The one task that puts the `~meta` of the parents noted in [`Parents`]
/// when their hold ends. It ends with the link (`close`, or its last
/// context dropped).
async fn flush_parents(inner: Weak<Inner>, parents: Arc<Parents>) {
    loop {
        parents.wake.notified().await;
        let until = parents.state().hold_until;
        if let Some(until) = until {
            tokio::time::sleep_until(until.into()).await;
        }
        let Some(ctx) = inner.upgrade().map(LinkCtx) else {
            return;
        };
        let batch: Vec<String> = {
            let mut st = parents.state();
            // children declared while this batch is put wait for the next one
            st.hold_until = Some(Instant::now() + HOLD_MAX);
            st.dirty.keys().cloned().collect()
        };
        let start = Instant::now();
        let mut failed = false;
        for parent in &batch {
            if ctx.is_closed() {
                return;
            }
            // the note stays when the put fails: `Unfinished` wakes this task again
            if let Err(e) = ctx.put_meta(parent, true).await {
                failed = true;
                tracing::debug!(%parent, "put of a changed child list failed: {e}");
            }
        }
        if ctx.is_closed() {
            return;
        }
        if failed {
            parents.state().hold_until = Some(Instant::now() + RETRY);
        } else {
            parents.hold_after(start.elapsed());
        }
    }
}

impl Drop for Inner {
    fn drop(&mut self) {
        // the flusher holds no context: wake it so that it ends
        self.parents.wake.notify_one();
    }
}

fn qual_attachment(qual: &str) -> Result<ZBytes> {
    Ok(ZBytes::from(encode(&Attachment {
        qual: Some(qual.to_owned()),
        ..Default::default()
    })?))
}

/// Publisher bound to one point's `~val`.
pub struct PointPublisher {
    ctx: LinkCtx,
    path: String,
    inner: PubInner,
}

enum PubInner {
    Plain(Publisher<'static>),
    #[cfg(feature = "advanced")]
    Reliable(Arc<zenoh_ext::AdvancedPublisher<'static>>),
}

impl PointPublisher {
    /// Whether any subscriber matches this point's `~val` (a `~val` storage
    /// counts). Advanced publishers always report `true`.
    pub async fn has_subscribers(&self) -> bool {
        match &self.inner {
            PubInner::Plain(p) => p
                .matching_status()
                .await
                .map(|s| s.matching())
                .unwrap_or(true),
            #[cfg(feature = "advanced")]
            PubInner::Reliable(_) => true,
        }
    }

    pub async fn put(&self, v: impl Into<Value>, q: Quality, t: u64) -> Result<()> {
        self.ctx.ensure_open()?;
        let s = Sample { v: v.into(), q, t };
        let payload = encode(&s)?;
        self.ctx.tree_mut().set_last(&self.path, s)?;
        match &self.inner {
            PubInner::Plain(p) => p.put(payload).await?,
            #[cfg(feature = "advanced")]
            PubInner::Reliable(p) => p.put(payload).await?,
        }
        Metrics::inc(&self.ctx.0.metrics.samples_out);
        Ok(())
    }
}

/// `cfg.qos` (DSA QoS 0..=3); absent = 0.
pub fn qos_level(meta: &NodeMeta) -> u64 {
    cfg_uint(meta, "qos").unwrap_or(0)
}

/// A whole number of `cfg` (`Value::to_int`): `qos: 1.5` is no QoS level
/// (absent, 0), not a truncated 1.
fn cfg_uint(meta: &NodeMeta, key: &str) -> Option<u64> {
    meta.cfg_value(key)?.to_int().ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    /// `cfg.qos` is a whole level: `1.5` was read as 1 (an advanced
    /// publisher); now it is no level, so the plain default 0 holds.
    #[test]
    fn qos_level_is_whole() {
        let qos = |v: Value| qos_level(&NodeMeta::number().cfg("qos", v));
        assert_eq!(qos(Value::UInt(2)), 2);
        assert_eq!(qos(Value::Float(2.0)), 2);
        assert_eq!(qos(Value::Float(1.5)), 0);
        assert_eq!(qos(Value::Float(2.9)), 0);
        assert_eq!(qos(Value::Float(f64::INFINITY)), 0);
        assert_eq!(qos_level(&NodeMeta::number()), 0);
    }
}
