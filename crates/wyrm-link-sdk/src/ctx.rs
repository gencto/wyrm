//! `LinkCtx`: the driver's only handle to the tree and the bus.

use crate::error::{LinkError, Result};
use crate::support::{Metrics, SecretStore};
use crate::tree::{Changed, NodeTree};
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, RwLock};
use std::time::{SystemTime, UNIX_EPOCH};
use wyrm_core::keyspace::{self, SUFFIX_META, SUFFIX_VAL};
use wyrm_core::meta::ActionMeta;
use wyrm_core::{Attachment, NodeMeta, Quality, Sample, Value};
use zenoh::bytes::ZBytes;
use zenoh::liveliness::LivelinessToken;
use zenoh::pubsub::Publisher;
use zenoh::qos::{CongestionControl, Priority};
use zenoh::Session;

/// Microseconds since the Unix epoch.
pub fn now_us() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_micros() as u64)
        .unwrap_or(0)
}

pub(crate) struct Inner {
    pub session: Session,
    pub site: String,
    pub link: String,
    /// `wy/<site>/down/<link>`
    pub prefix: String,
    pub tree: RwLock<NodeTree>,
    tokens: Mutex<HashMap<String, LivelinessToken>>,
    #[cfg(feature = "advanced")]
    reliable: Mutex<HashMap<String, Arc<zenoh_ext::AdvancedPublisher<'static>>>>,
    /// Set by `LinkHandle::stop`/drop; every mutation then fails with `closed`.
    closed: AtomicBool,
    pub secrets: SecretStore,
    pub metrics: Metrics,
    pub data_dir: Option<PathBuf>,
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
        secrets: SecretStore,
        data_dir: Option<PathBuf>,
    ) -> Self {
        Self(Arc::new(Inner {
            session,
            site: site.to_owned(),
            link: link.to_owned(),
            prefix,
            tree: RwLock::new(NodeTree::new(root)),
            tokens: Mutex::new(HashMap::new()),
            #[cfg(feature = "advanced")]
            reliable: Mutex::new(HashMap::new()),
            closed: AtomicBool::new(false),
            secrets,
            metrics: Metrics::default(),
            data_dir,
        }))
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
    /// node's `~meta` and, for a new node, the parent's (new `children`).
    pub async fn declare_node(&self, path: &str, meta: NodeMeta) -> Result<()> {
        self.ensure_open()?;
        if !path.is_empty() {
            keyspace::validate_path(path)?;
        }
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

    /// Remove a node with its subtree: deletes `~meta`/`~val` of every removed
    /// node, drops their liveliness tokens, republishes the parent's `~meta`.
    pub async fn remove_node(&self, path: &str) -> Result<()> {
        self.ensure_open()?;
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
        self.publish_meta(&parent).await
    }

    /// Per-node liveliness at `down/<link>/<path>` for nodes that come and go
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

    pub fn metrics(&self) -> &Metrics {
        &self.0.metrics
    }

    /// Private directory owned by this link (state the connector keeps across
    /// restarts), or `None` when the host gives it none (tests, external
    /// links): the driver then keeps its state in memory.
    pub fn data_dir(&self) -> Option<&Path> {
        self.0.data_dir.as_deref()
    }

    async fn publish_changed(&self, path: &str, changed: Changed) -> Result<()> {
        if changed.node {
            self.publish_meta(path).await?;
        }
        if let Some(parent) = changed.parent {
            self.publish_meta(&parent).await?;
        }
        Ok(())
    }

    /// `put ~meta` with the full meta of `path` (DataHigh + Block).
    pub(crate) async fn publish_meta(&self, path: &str) -> Result<()> {
        // Restricted nodes are never broadcast: `~meta` only on an authorized get.
        let Some(meta) = ({
            let tree = self.tree();
            (!tree.restricted(path))
                .then(|| tree.full(path, false))
                .flatten()
        }) else {
            return Ok(());
        };
        self.0
            .session
            .put(self.key(path, SUFFIX_META), encode(&meta)?)
            .priority(Priority::DataHigh)
            .congestion_control(CongestionControl::Block)
            .await?;
        Ok(())
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

fn cfg_uint(meta: &NodeMeta, key: &str) -> Option<u64> {
    match meta.cfg_value(key)? {
        Value::UInt(u) => Some(*u),
        Value::Float(f) if *f >= 0.0 => Some(*f as u64),
        _ => None,
    }
}
