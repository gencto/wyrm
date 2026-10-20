//! Responder: one queryable on `wy/<site>/down/<link>/**`, routed by suffix.
//!
//! * `~meta` is answered from the shared tree on the query task — it never
//!   waits for the driver.
//! * `~set` / `~act/<a>` are authorized and validated here, then sent to the
//!   driver task (`&mut self`, one call at a time) on a bounded queue.
//! * `~val` is answered only with `answer_val` (peer mode without storage);
//!   with a router, storage owns last values.
//!
//! Every `~meta`, `~set` and `~act` reply carries `attachment.status`; errors
//! are normal replies with `status ≥ 0x20`, never `reply_err`.

use crate::auth::{Caller, Verifier};
use crate::ctx::LinkCtx;
use crate::error::{LinkError, Result};
use crate::link::{Link, ReplySink, SinkItem};
use crate::support::{Metrics, SecretStore};
use ed25519_dalek::VerifyingKey;
use std::cmp::Ordering;
use std::collections::HashMap;
use std::sync::atomic::{self, AtomicU32};
use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use tokio::sync::{mpsc, oneshot};
use tokio::task::JoinHandle;
use tracing::{debug, warn};
use wyrm_core::codec::{from_slice, to_vec};
use wyrm_core::keyspace::{self, SUFFIX_META, SUFFIX_SET, SUFFIX_VAL};
use wyrm_core::meta::{is_code, ActionResult, ParamMeta, Profile, TypeCode, Writable};
use wyrm_core::profile::{self, ProfileDef};
use wyrm_core::{Attachment, NodeMeta, Perm, SetRequest, Status, Value};
use zenoh::handlers::FifoChannelHandler;
use zenoh::key_expr::keyexpr;
use zenoh::liveliness::LivelinessToken;
use zenoh::query::{Query, Queryable};
use zenoh::Session;

const QUEUE_DEPTH: usize = 256;
const STOP_TIMEOUT: Duration = Duration::from_secs(10);
const LIST_LIMIT_MAX: usize = 1000;

/// Host-side settings of one link instance.
#[derive(Debug, Clone)]
pub struct LinkConfig {
    pub site: String,
    /// Link id = last key segment = certificate CN.
    pub link: String,
    /// Admin `ptok` keys: the active one and optionally the previous one.
    /// Empty → every `set`/`invoke` is denied.
    pub admin_keys: Vec<VerifyingKey>,
    /// More trusted keys, each capped at a permission (the flow engine and
    /// agent keys at `write`): a stolen one cannot mint `config`.
    pub limited_keys: Vec<(VerifyingKey, Perm)>,
    /// Bound on each driver call (overridden by `actions.*.timeout_ms`).
    /// Keep below the requester's 10 s `get` timeout.
    pub driver_timeout: Duration,
    /// Answer `get ~val` from the last published value (peer mode only).
    pub answer_val: bool,
    pub secrets: SecretStore,
    /// Key prefix override (`wy/<site>/sys` for the admin). Default:
    /// `wy/<site>/down/<link>`.
    pub root: Option<String>,
    /// Actions that skip the `ptok` check because the driver authenticates
    /// the caller itself (the admin's `hello` checks a link token). Host
    /// config only: a driver cannot open an action through its declarations.
    pub open_actions: Vec<String>,
    /// Liveliness key of the broker (`wy/<site>/sys/broker`): when it comes
    /// back (router restart), re-publish all `~meta` and last values.
    pub republish_on: Option<String>,
    /// `set`/`invoke` per caller: `(requests per second, burst)`; `None` = off.
    pub rate_limit: Option<(f64, f64)>,
    /// Put an audit record for every `set`/`invoke` on `wy/<site>/sys/audit/<link>`.
    pub audit: bool,
    /// Reads (`~meta`, documents, `~val`, wildcard fan-in) for the whole
    /// link: `(per second, burst)`; `None` = off. Reads carry no verified
    /// identity, so the budget protects the link's CPU, not fairness.
    pub read_rate_limit: Option<(f64, f64)>,
}

/// Most replies to one wildcard `get` or `view=keys`.
pub const MAX_READ_ITEMS: usize = 10_000;
const READS: &str = "reads";
/// Reads are first charged to one of these shards by the target path, so a
/// flood on one key fills its own shard before it can drain the link-wide
/// budget; hashing keeps the table bounded however large the tree is.
const READ_SHARDS: u64 = 1024;
/// Per-shard budget as a fraction of the link-wide one.
const SHARD_SHARE: f64 = 0.05;

impl LinkConfig {
    pub fn new(site: impl Into<String>, link: impl Into<String>) -> Self {
        Self {
            site: site.into(),
            link: link.into(),
            admin_keys: Vec::new(),
            limited_keys: Vec::new(),
            driver_timeout: Duration::from_secs(5),
            answer_val: false,
            secrets: SecretStore::default(),
            root: None,
            open_actions: Vec::new(),
            republish_on: None,
            rate_limit: Some((50.0, 100.0)),
            audit: true,
            read_rate_limit: Some((5000.0, 10_000.0)),
        }
    }
}

enum Cmd<C> {
    Set {
        path: String,
        value: Value,
        caller: Caller,
        timeout: Duration,
        tx: oneshot::Sender<Result<()>>,
    },
    Invoke {
        path: String,
        action: String,
        args: Value,
        caller: Caller,
        timeout: Duration,
        sink: ReplySink,
    },
    Reconfigure {
        cfg: C,
        tx: oneshot::Sender<Result<()>>,
    },
    Stop {
        tx: oneshot::Sender<()>,
    },
}

/// A running link. Dropping it aborts the tasks; prefer [`stop`](Self::stop).
pub struct LinkHandle<L: Link> {
    ctx: LinkCtx,
    cmd: mpsc::Sender<Cmd<L::Config>>,
    query_task: JoinHandle<()>,
    actor: JoinHandle<()>,
    watcher: Option<JoinHandle<()>>,
    token: Option<LivelinessToken>,
}

impl<L: Link> LinkHandle<L> {
    pub fn ctx(&self) -> &LinkCtx {
        &self.ctx
    }

    pub async fn reconfigure(&self, cfg: L::Config) -> Result<()> {
        let (tx, rx) = oneshot::channel();
        self.cmd
            .send(Cmd::Reconfigure { cfg, tx })
            .await
            .map_err(|_| LinkError::new(Status::Closed, "link stopped"))?;
        rx.await
            .map_err(|_| LinkError::new(Status::Closed, "link stopped"))?
    }

    /// Stop taking requests, run `Link::stop` (≤ 10 s), drop liveliness.
    pub async fn stop(mut self) {
        self.query_task.abort();
        self.ctx.close();
        let (tx, rx) = oneshot::channel();
        if self.cmd.send(Cmd::Stop { tx }).await.is_ok() {
            let _ = rx.await;
        }
        self.token.take();
    }
}

impl<L: Link> Drop for LinkHandle<L> {
    fn drop(&mut self) {
        self.ctx.close();
        self.query_task.abort();
        self.actor.abort();
        if let Some(w) = &self.watcher {
            w.abort();
        }
    }
}

/// Start a link on `session`: tree + queryable, then `L::start`, then the
/// driver task and the liveliness token `wy/<site>/down/<link>`.
pub async fn spawn<L: Link>(
    session: Session,
    cfg: LinkConfig,
    link_cfg: L::Config,
) -> Result<LinkHandle<L>> {
    keyspace::validate_segment(&cfg.site)?;
    keyspace::validate_segment(&cfg.link)?;
    let root = NodeMeta {
        is: Some(Profile::Code(is_code::LINK)),
        ..Default::default()
    }
    .attr("driver", L::NAME)
    .attr("version", L::VERSION);
    let prefix = match &cfg.root {
        Some(r) => r.clone(),
        None => format!("{}/{}/down/{}", keyspace::ROOT, cfg.site, cfg.link),
    };
    let ctx = LinkCtx::new(
        session.clone(),
        &cfg.site,
        &cfg.link,
        prefix,
        root,
        cfg.secrets,
    );
    let queryable = session
        .declare_queryable(format!("{}/**", ctx.0.prefix))
        .await?;
    ctx.publish_meta("").await?;

    let (tx, rx) = mpsc::channel(QUEUE_DEPTH);
    let shared = Arc::new(Shared {
        ctx: ctx.clone(),
        verifier: Verifier::new(cfg.admin_keys, cfg.site.clone()).with_limited(cfg.limited_keys),
        cmd: tx.clone(),
        driver_timeout: cfg.driver_timeout,
        answer_val: cfg.answer_val,
        open_actions: cfg.open_actions,
        limiter: cfg
            .rate_limit
            .map(|(r, b)| crate::guard::RateLimiter::new(r, b)),
        anon_limiter: cfg
            .rate_limit
            .map(|(r, b)| crate::guard::RateLimiter::new(r, b)),
        profiles: Default::default(),
        read_limiter: cfg
            .read_rate_limit
            .map(|(r, b)| crate::guard::RateLimiter::new(r, b)),
        shard_limiter: cfg.read_rate_limit.map(|(r, b)| {
            crate::guard::RateLimiter::new(r * SHARD_SHARE, (b * SHARD_SHARE).max(2.0))
        }),
        shard_seed: Default::default(),
        audit_key: cfg
            .audit
            .then(|| format!("{}/{}/sys/audit/{}", keyspace::ROOT, cfg.site, cfg.link)),
        audit_suppressed: Default::default(),
        next_rid: AtomicU32::new(1),
    });
    let profiles = shared.profiles.clone();
    let (psession, psite) = (session.clone(), cfg.site.clone());
    // One task: aborting it stops the queryable and the profile follower.
    let query_task = tokio::spawn(async move {
        tokio::join!(
            serve(shared, queryable),
            follow_profiles(psession, psite, profiles)
        );
    });
    let link = match guarded(L::start(link_cfg, ctx.clone())).await {
        Ok(Ok(l)) => l,
        Ok(Err(e)) => {
            query_task.abort();
            return Err(e);
        }
        Err(()) => {
            query_task.abort();
            ctx.close();
            tracing::error!(link = %ctx.link(), "driver panicked in start");
            return Err(LinkError::internal("driver panicked in start"));
        }
    };
    let actor = tokio::spawn(run_driver(ctx.clone(), link, rx));
    let token = session
        .liveliness()
        .declare_token(ctx.0.prefix.clone())
        .await?;
    let watcher = cfg
        .republish_on
        .map(|key| tokio::spawn(republish_on(ctx.clone(), key)));
    Ok(LinkHandle {
        ctx,
        cmd: tx,
        query_task,
        actor,
        watcher,
        token: Some(token),
    })
}

/// Re-publish whenever the broker's liveliness token re-appears.
async fn republish_on(ctx: LinkCtx, key: String) {
    let sub = match ctx.client().liveliness().declare_subscriber(&key).await {
        Ok(s) => s,
        Err(e) => {
            warn!("cannot watch {key}: {e}");
            return;
        }
    };
    while let Ok(s) = sub.recv_async().await {
        if s.kind() == zenoh::sample::SampleKind::Put {
            debug!("broker back: re-publishing");
            if ctx.republish().await.is_err() {
                return; // link stopped
            }
        }
    }
}

/// A driver call that may panic: `Err(())` if it did.
async fn guarded<F: std::future::Future>(f: F) -> std::result::Result<F::Output, ()> {
    use futures_util::FutureExt;
    std::panic::AssertUnwindSafe(f)
        .catch_unwind()
        .await
        .map_err(|_| ())
}

fn panicked() -> LinkError {
    LinkError::internal("driver panicked; the link stopped")
}

async fn run_driver<L: Link>(ctx: LinkCtx, mut link: L, mut rx: mpsc::Receiver<Cmd<L::Config>>) {
    // A panic leaves the driver in an unknown state: answer, mark every
    // value bad, close the link (no new requests) and stop the actor.
    let fail = |what: &str| {
        tracing::error!(link = %ctx.link(), "driver panicked in {what}; link stopped");
        let ctx = ctx.clone();
        async move {
            let _ = ctx
                .mark_all(wyrm_core::Quality::Bad, Some("bad/driver_panic"))
                .await;
            ctx.close();
        }
    };
    while let Some(cmd) = rx.recv().await {
        match cmd {
            Cmd::Set {
                path,
                value,
                caller,
                timeout,
                tx,
            } => {
                let r = guarded(tokio::time::timeout(
                    timeout,
                    link.on_set(&path, value, &caller),
                ))
                .await;
                let Ok(r) = r else {
                    let _ = tx.send(Err(panicked()));
                    fail("on_set").await;
                    return;
                };
                let _ =
                    tx.send(r.unwrap_or_else(|_| Err(LinkError::timeout("driver did not answer"))));
            }
            Cmd::Invoke {
                path,
                action,
                args,
                caller,
                timeout,
                sink,
            } => {
                let errs = sink.clone();
                let r = guarded(tokio::time::timeout(
                    timeout,
                    link.on_invoke(&path, &action, args, &caller, sink),
                ))
                .await;
                let Ok(r) = r else {
                    let _ = errs.error(panicked()).await;
                    fail("on_invoke").await;
                    return;
                };
                if let Err(e) =
                    r.unwrap_or_else(|_| Err(LinkError::timeout("driver did not answer")))
                {
                    let _ = errs.error(e).await;
                }
            }
            Cmd::Reconfigure { cfg, tx } => match guarded(link.reconfigure(cfg)).await {
                Ok(r) => {
                    let _ = tx.send(r);
                }
                Err(()) => {
                    let _ = tx.send(Err(panicked()));
                    fail("reconfigure").await;
                    return;
                }
            },
            Cmd::Stop { tx } => {
                match guarded(tokio::time::timeout(STOP_TIMEOUT, link.stop())).await {
                    Ok(Ok(())) => {}
                    Ok(Err(_)) => warn!("link stop timed out"),
                    Err(()) => warn!("link stop panicked"),
                }
                let _ = tx.send(());
                return;
            }
        }
    }
}

struct Shared<C> {
    ctx: LinkCtx,
    verifier: Verifier,
    cmd: mpsc::Sender<Cmd<C>>,
    driver_timeout: Duration,
    answer_val: bool,
    open_actions: Vec<String>,
    /// Verified subjects, and separately everyone else: unverified traffic
    /// can never use up the table or buckets of verified callers.
    limiter: Option<crate::guard::RateLimiter>,
    anon_limiter: Option<crate::guard::RateLimiter>,
    read_limiter: Option<crate::guard::RateLimiter>,
    /// `pub/**` profiles of the site, followed live (spec 02 inheritance).
    profiles: Profiles,
    shard_limiter: Option<crate::guard::RateLimiter>,
    /// Random per link: a caller cannot pick keys that share a shard.
    shard_seed: std::collections::hash_map::RandomState,
    audit_key: Option<String>,
    audit_suppressed: std::sync::atomic::AtomicU64,
    next_rid: AtomicU32,
}

async fn serve<C: Send + 'static>(
    sh: Arc<Shared<C>>,
    queryable: Queryable<FifoChannelHandler<Query>>,
) {
    while let Ok(q) = queryable.recv_async().await {
        sh.route(q).await;
    }
}

type Profiles = Arc<std::sync::RwLock<HashMap<String, ProfileDef>>>;

/// Keep `cache` equal to `wy/<site>/pub/*/~meta`: subscribe first, then
/// read everything once (no lost-update window).
async fn follow_profiles(session: Session, site: String, cache: Profiles) {
    let prefix = format!("{}/{site}/pub/", keyspace::ROOT);
    let name_of = |k: &str| {
        k.strip_prefix(prefix.as_str())
            .and_then(|r| r.strip_suffix("/~meta"))
            .map(str::to_owned)
    };
    let Ok(sub) = session.declare_subscriber(format!("{prefix}*/~meta")).await else {
        return;
    };
    if let Ok(replies) = session
        .get(format!("{prefix}*/~meta"))
        .timeout(Duration::from_secs(5))
        .await
    {
        while let Ok(r) = replies.recv_async().await {
            let Ok(s) = r.result() else { continue };
            if let (Some(n), Ok(p)) = (
                name_of(s.key_expr().as_str()),
                from_slice::<ProfileDef>(&s.payload().to_bytes()),
            ) {
                cache
                    .write()
                    .unwrap_or_else(|p| p.into_inner())
                    .insert(n, p);
            }
        }
    }
    while let Ok(s) = sub.recv_async().await {
        let Some(n) = name_of(s.key_expr().as_str()) else {
            continue;
        };
        let mut c = cache.write().unwrap_or_else(|p| p.into_inner());
        match s.kind() {
            zenoh::sample::SampleKind::Delete => {
                c.remove(&n);
            }
            zenoh::sample::SampleKind::Put => {
                if let Ok(p) = from_slice::<ProfileDef>(&s.payload().to_bytes()) {
                    c.insert(n, p);
                }
            }
        }
    }
}

/// Spec 04: `origin` is trusted only with a valid token. It must be the
/// token's subject or a sub-identity of it (`<sub>/...`, e.g. a gateway
/// session acting for `user:x`); anything else is replaced by the subject.
fn bound_origin(claimed: Option<&str>, sub: &str) -> String {
    match claimed {
        Some(o) if o == sub || o.strip_prefix(sub).is_some_and(|r| r.starts_with('/')) => {
            o.to_owned()
        }
        _ => sub.to_owned(),
    }
}

fn now_s() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

fn is_wild(key: &str) -> bool {
    key.contains('*')
}

/// Selector parameter per spec 01 (`key?a=1&b=2`). Parsed from the raw
/// string because Zenoh 1.x `Parameters` split on `;`, which spec 01 uses
/// inside `match=`. A bare `name` yields `""`.
fn param<'a>(q: &'a Query, name: &str) -> Option<&'a str> {
    q.parameters()
        .as_str()
        .split('&')
        .find_map(|kv| match kv.split_once('=') {
            Some((k, v)) if k == name => Some(v),
            None if kv == name => Some(""),
            _ => None,
        })
}

fn denied() -> LinkError {
    LinkError::new(Status::PermissionDenied, "")
}

fn status_att(status: Status) -> Attachment {
    Attachment::with_status(status)
}

fn err_att(e: &LinkError) -> Attachment {
    let mut a = status_att(e.status);
    if !e.message.is_empty() && e.status != Status::PermissionDenied {
        a.err = Some(e.message.clone());
    }
    a
}

fn encode<T: minicbor::Encode<()>>(v: &T) -> Result<Vec<u8>> {
    to_vec(v).map_err(|e| LinkError::internal(e.to_string()))
}

async fn reply(q: &Query, key: &str, payload: Vec<u8>, att: Option<Attachment>, express: bool) {
    let mut b = q.reply(key, payload).express(express);
    if let Some(att) = att {
        match to_vec(&att) {
            Ok(a) => b = b.attachment(a),
            Err(e) => warn!("attachment encode: {e}"),
        }
    }
    if let Err(e) = b.await {
        debug!("reply on {key} failed: {e}");
    }
}

async fn reply_here(q: &Query, payload: Vec<u8>, att: Attachment, express: bool) {
    let key = q.key_expr().as_str().to_owned();
    reply(q, &key, payload, Some(att), express).await;
}

impl<C: Send + 'static> Shared<C> {
    /// `target`: the node path, or the wildcard key of a fan-in.
    /// A profile from the followed cache, else a built-in one.
    fn profile(&self, name: &str) -> Option<ProfileDef> {
        if let Some(p) = self
            .profiles
            .read()
            .unwrap_or_else(|p| p.into_inner())
            .get(name)
        {
            return Some(p.clone());
        }
        profile::builtins()
            .into_iter()
            .find(|(n, _)| *n == name)
            .map(|(_, p)| p)
    }

    fn read_allowed(&self, target: &str) -> bool {
        use std::hash::BuildHasher;
        let shard_ok = self.shard_limiter.as_ref().is_none_or(|l| {
            let shard = self.shard_seed.hash_one(target) % READ_SHARDS;
            l.allow(&format!("s{shard}"))
        });
        shard_ok && self.read_limiter.as_ref().is_none_or(|l| l.allow(READS))
    }

    async fn route(self: &Arc<Self>, q: Query) {
        let key = q.key_expr().as_str();
        if is_wild(key) {
            if self.read_allowed(key) {
                self.fan_in(&q).await;
            }
            return;
        }
        let Some(rest) = key
            .strip_prefix(self.ctx.0.prefix.as_str())
            .and_then(|r| r.strip_prefix('/'))
        else {
            return;
        };
        let (path, suffix) = if rest.starts_with('~') {
            ("", rest)
        } else {
            match keyspace::split_suffix(rest) {
                Some(x) => x,
                None => return,
            }
        };
        let (path, suffix) = (path.to_owned(), suffix.to_owned());
        let is_read = suffix != SUFFIX_SET && !suffix.starts_with("~act/");
        if is_read && !self.read_allowed(&path) {
            if suffix != SUFFIX_VAL {
                let e = LinkError::new(Status::RateLimited, "too many reads");
                reply_here(&q, Vec::new(), err_att(&e), false).await;
            }
            return;
        }
        match suffix.as_str() {
            SUFFIX_META => {
                let (payload, att) = match self.meta(&q, &path) {
                    Ok(x) => x,
                    Err(e) => (Vec::new(), err_att(&e)),
                };
                reply_here(&q, payload, att, false).await;
            }
            SUFFIX_VAL => {
                if self.answer_val {
                    let last = self.ctx.last(&path);
                    if let Some(Ok(p)) = last.as_ref().map(encode) {
                        let key = q.key_expr().as_str().to_owned();
                        reply(&q, &key, p, None, false).await;
                    }
                }
            }
            SUFFIX_SET => {
                let sh = self.clone();
                tokio::spawn(async move {
                    let att = match sh.set(&q, &path).await {
                        Ok(()) => status_att(Status::Ok),
                        Err(e) => sh.fail(e),
                    };
                    reply_here(&q, Vec::new(), att, true).await;
                });
            }
            s => match s.strip_prefix("~act/") {
                Some(action) => {
                    let sh = self.clone();
                    let action = action.to_owned();
                    tokio::spawn(async move {
                        if let Err(e) = sh.invoke(&q, &path, &action).await {
                            let att = sh.fail(e);
                            reply_here(&q, Vec::new(), att, true).await;
                        }
                    });
                }
                None => {
                    let (payload, att) = match self.doc(&q, &path, s) {
                        Ok(d) => (d, status_att(Status::Ok)),
                        Err(e) => (Vec::new(), err_att(&e)),
                    };
                    reply_here(&q, payload, att, false).await;
                }
            },
        }
    }

    fn fail(&self, e: LinkError) -> Attachment {
        if e.status == Status::PermissionDenied {
            Metrics::inc(&self.ctx.0.metrics.denied);
        } else {
            Metrics::inc(&self.ctx.0.metrics.errors);
        }
        err_att(&e)
    }

    /// Wildcard `get` (fan-in): full `~meta` of every non-restricted node
    /// whose key intersects, plus `~val` with `answer_val`. Selector
    /// parameters are ignored here.
    async fn fan_in(&self, q: &Query) {
        let qk = q.key_expr();
        let hits = |k: &str| keyexpr::new(k).is_ok_and(|k| k.intersects(qk));
        let mut out: Vec<(String, Vec<u8>, Option<Attachment>)> = Vec::new();
        {
            let tree = self.ctx.tree();
            for (path, node) in tree.iter() {
                let k = self.ctx.key(path, SUFFIX_META);
                if !tree.restricted(path) && hits(&k) {
                    if let Ok(p) = encode(&tree.full(path, false).unwrap_or_default()) {
                        let mut att = status_att(Status::Ok);
                        att.rev = Some(node.rev);
                        out.push((k, p, Some(att)));
                    }
                }
                if self.answer_val {
                    if let Some(last) = &node.last {
                        let k = self.ctx.key(path, SUFFIX_VAL);
                        if hits(&k) {
                            if let Ok(p) = encode(last) {
                                out.push((k, p, None));
                            }
                        }
                    }
                }
            }
        }
        if out.len() > MAX_READ_ITEMS {
            debug!(key = %qk, n = out.len(), "fan-in truncated");
            out.truncate(MAX_READ_ITEMS);
        }
        for (k, p, att) in out {
            reply(q, &k, p, att, false).await;
        }
    }

    fn attachment(&self, q: &Query) -> Result<Attachment> {
        match q.attachment() {
            None => Ok(Attachment::default()),
            Some(z) => from_slice(&z.to_bytes())
                .map_err(|_| LinkError::new(Status::InvalidMessage, "bad attachment")),
        }
    }

    /// No token → anonymous caller (`perm = none`). Invalid token → denied.
    /// With a token, `origin` is bound to its subject (see [`bound_origin`]).
    fn authorize(&self, q: &Query, att: &Attachment) -> Result<Caller> {
        let Some(tok) = att.ptok.as_deref() else {
            return Ok(Caller::default());
        };
        match self
            .verifier
            .verify(tok, q.key_expr(), att.maxperm, now_s())
        {
            Ok((claims, perm)) => Ok(Caller {
                origin: Some(bound_origin(att.origin.as_deref(), &claims.sub)),
                perm,
                claims: Some(claims),
            }),
            Err(reason) => {
                debug!(?reason, key = %q.key_expr(), "ptok rejected");
                Err(denied())
            }
        }
    }

    /// A document set with `LinkCtx::set_doc` (`~def`, `~state`); restricted
    /// nodes need `list` like `~meta`.
    fn doc(&self, q: &Query, path: &str, suffix: &str) -> Result<Vec<u8>> {
        let (doc, restricted) = {
            let tree = self.ctx.tree();
            let node = tree
                .get(path)
                .ok_or_else(|| LinkError::not_found(path.to_owned()))?;
            (node.docs.get(suffix).cloned(), tree.restricted(path))
        };
        let doc = doc.ok_or_else(|| LinkError::not_supported(format!("suffix {suffix}")))?;
        if restricted {
            let att = self.attachment(q)?;
            if self.authorize(q, &att)?.perm < Perm::List {
                return Err(denied());
            }
        }
        Ok(doc)
    }

    fn meta(&self, q: &Query, path: &str) -> Result<(Vec<u8>, Attachment)> {
        let parse = |name: &str| -> Result<Option<usize>> {
            param(q, name)
                .map(|v| {
                    v.parse()
                        .map_err(|_| LinkError::invalid_parameter(format!("bad {name}")))
                })
                .transpose()
        };
        let restricted = {
            let tree = self.ctx.tree();
            tree.get(path)
                .ok_or_else(|| LinkError::not_found(path.to_owned()))?;
            tree.restricted(path)
        };
        // Restricted nodes (inherited) need `list`; for open nodes a valid
        // token only reveals restricted children.
        let att = self.attachment(q)?;
        let authorized = if restricted || att.ptok.is_some() {
            let ok = self.authorize(q, &att)?.perm >= Perm::List;
            if restricted && !ok {
                return Err(denied());
            }
            ok
        } else {
            false
        };
        let tree = self.ctx.tree();
        let node = tree
            .get(path)
            .ok_or_else(|| LinkError::not_found(path.to_owned()))?;
        let mut att = status_att(Status::Ok);
        att.rev = Some(node.rev);
        if parse("rev")? == Some(node.rev as usize) {
            return Ok((Vec::new(), att));
        }
        let payload = match param(q, "view").unwrap_or("full") {
            "full" => {
                let m = tree.full(path, authorized).unwrap_or_default();
                if param(q, "expand") == Some("true") {
                    encode(&profile::expand(&m, |n| self.profile(n)))?
                } else {
                    encode(&m)?
                }
            }
            "list" => {
                let from = parse("from")?.unwrap_or(0);
                let limit = parse("limit")?
                    .unwrap_or(LIST_LIMIT_MAX)
                    .min(LIST_LIMIT_MAX);
                let overrides = |m: &NodeMeta| match &m.is {
                    Some(Profile::Name(n)) => {
                        profile::overrides(m, &profile::resolved(n, |x| self.profile(x)))
                    }
                    _ => false,
                };
                encode(
                    &tree
                        .list_with(path, from, limit, authorized, overrides)
                        .unwrap_or_default(),
                )?
            }
            "keys" => {
                let filter = crate::tree::KeyFilter::parse(param(q, "match").unwrap_or(""))?;
                let depth = parse("depth")?.unwrap_or(usize::MAX);
                let keys = tree
                    .keys(path, &filter, depth, authorized)
                    .unwrap_or_default();
                if keys.len() > MAX_READ_ITEMS {
                    return Err(LinkError::new(
                        Status::Busy,
                        format!("more than {MAX_READ_ITEMS} keys; narrow match or depth"),
                    ));
                }
                encode(&keyspace::compress_keys(keys))?
            }
            v => return Err(LinkError::invalid_parameter(format!("bad view {v}"))),
        };
        Ok((payload, att))
    }

    /// Over the budget → `rate_limited`. A verified token is its own bucket.
    /// Anonymous and unauthenticated callers have no verified identity in
    /// the SDK; they use a separate limiter, one bucket per *declared* path
    /// (the router ACL binds paths to transport identities, e.g.
    /// `links/<id>/~act/hello` only for CN `<id>`) and one shared bucket for
    /// any other path, so made-up paths cannot grow the table.
    fn limit(&self, caller: Option<&Caller>, path: &str) -> Result<()> {
        let allowed = match caller {
            Some(Caller {
                claims: Some(c), ..
            }) => self.limiter.as_ref().is_none_or(|l| l.allow(&c.sub)),
            _ => self.anon_limiter.as_ref().is_none_or(|l| {
                let declared = self.ctx.tree().get(path).is_some();
                let tag = if caller.is_some() { "anon" } else { "unauth" };
                l.allow(&format!("{tag}:{}", if declared { path } else { "*" }))
            }),
        };
        if allowed {
            Ok(())
        } else {
            Err(LinkError::new(Status::RateLimited, "too many requests"))
        }
    }

    /// Audit record of one `set`/`invoke` (args as SHA-256, never the values).
    async fn audit(&self, q: &Query, op: &str, sub: &str, args: &[u8], r: &Result<()>) {
        let Some(key) = &self.audit_key else {
            return;
        };
        use sha2::Digest;
        let status = match r {
            Ok(()) => Status::Ok,
            Err(e) => e.status,
        };
        // A flood must not become an audit flood: rejected-by-limit requests
        // are counted and reported in the next record.
        if status == Status::RateLimited {
            self.audit_suppressed
                .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
            return;
        }
        let mut m = std::collections::BTreeMap::new();
        let suppressed = self
            .audit_suppressed
            .swap(0, std::sync::atomic::Ordering::Relaxed);
        if suppressed > 0 {
            m.insert("suppressed".to_owned(), Value::UInt(suppressed));
        }
        m.insert("t".to_owned(), Value::UInt(crate::ctx::now_us()));
        m.insert("sub".to_owned(), Value::Str(sub.to_owned()));
        m.insert("op".to_owned(), Value::Str(op.to_owned()));
        m.insert(
            "key".to_owned(),
            Value::Str(q.key_expr().as_str().to_owned()),
        );
        m.insert(
            "args_hash".to_owned(),
            Value::Bytes(sha2::Sha256::digest(args).to_vec()),
        );
        m.insert("status".to_owned(), Value::UInt(status.code().into()));
        if let Ok(p) = encode(&Value::Map(m)) {
            let _ = self
                .ctx
                .client()
                .put(key, p)
                .priority(zenoh::qos::Priority::Background)
                .congestion_control(zenoh::qos::CongestionControl::Block)
                .await;
        }
    }

    async fn set(&self, q: &Query, path: &str) -> Result<()> {
        Metrics::inc(&self.ctx.0.metrics.sets_in);
        let args = q
            .payload()
            .map(|p| p.to_bytes().to_vec())
            .unwrap_or_default();
        let (sub, r) = match self.attachment(q).and_then(|att| self.authorize(q, &att)) {
            Err(e) => (
                "unauthenticated".to_owned(),
                self.limit(None, path).and(Err(e)),
            ),
            Ok(caller) => {
                let sub = caller
                    .claims
                    .as_ref()
                    .map(|c| c.sub.clone())
                    .unwrap_or_else(|| "anonymous".into());
                let r = match self.limit(Some(&caller), path) {
                    Ok(()) => self.set_authorized(q, path, caller).await,
                    Err(e) => Err(e),
                };
                (sub, r)
            }
        };
        self.audit(q, "set", &sub, &args, &r).await;
        r
    }

    async fn set_authorized(&self, q: &Query, path: &str, caller: Caller) -> Result<()> {
        let meta = self
            .ctx
            .tree()
            .get(path)
            .map(|n| n.meta.clone())
            .ok_or_else(|| LinkError::not_found(path.to_owned()))?;
        if param(q, "field").is_some() {
            if caller.perm < Perm::Config {
                return Err(denied());
            }
            // TODO: cfg/attr overrides need broker-owned persistence (ADR 0003).
            return Err(LinkError::not_supported("field writes"));
        }
        if meta.ty.is_none() {
            return Err(LinkError::not_supported("containers have no value"));
        }
        let required = match meta.writable.unwrap_or_default() {
            Writable::Never => return Err(LinkError::not_supported("not writable")),
            Writable::Config => Perm::Config,
            Writable::Write => Perm::Write,
        };
        if caller.perm < required {
            return Err(denied());
        }
        let bytes = q.payload().map(|p| p.to_bytes()).unwrap_or_default();
        let req: SetRequest = from_slice(&bytes)
            .map_err(|_| LinkError::new(Status::InvalidMessage, "expected {0: v}"))?;
        validate_value(&meta, &req.v)?;
        let (tx, rx) = oneshot::channel();
        self.submit(Cmd::Set {
            path: path.to_owned(),
            value: req.v,
            caller,
            timeout: self.driver_timeout,
            tx,
        })?;
        rx.await
            .map_err(|_| LinkError::new(Status::Disconnected, "driver stopped"))?
    }

    /// Replies itself on success; `Err` → the caller sends one error reply.
    async fn invoke(&self, q: &Query, path: &str, action: &str) -> Result<()> {
        Metrics::inc(&self.ctx.0.metrics.invokes_in);
        let args = q
            .payload()
            .map(|p| p.to_bytes().to_vec())
            .unwrap_or_default();
        let (sub, r) = match self
            .attachment(q)
            .and_then(|att| self.authorize(q, &att).map(|c| (att, c)))
        {
            Err(e) => (
                "unauthenticated".to_owned(),
                self.limit(None, path).and(Err(e)),
            ),
            Ok((att, caller)) => {
                let sub = caller
                    .claims
                    .as_ref()
                    .map(|c| c.sub.clone())
                    .unwrap_or_else(|| "anonymous".into());
                let r = match self.limit(Some(&caller), path) {
                    Ok(()) => self.invoke_authorized(q, path, action, att, caller).await,
                    Err(e) => Err(e),
                };
                (sub, r)
            }
        };
        self.audit(q, "invoke", &sub, &args, &r).await;
        r
    }

    async fn invoke_authorized(
        &self,
        q: &Query,
        path: &str,
        action: &str,
        att: Attachment,
        caller: Caller,
    ) -> Result<()> {
        let (act, invokable) = {
            let tree = self.ctx.tree();
            let node = tree
                .get(path)
                .ok_or_else(|| LinkError::not_found(path.to_owned()))?;
            let act = node
                .meta
                .actions
                .as_ref()
                .and_then(|a| a.get(action))
                .cloned()
                .ok_or_else(|| LinkError::not_found(format!("action {action}")))?;
            (act, node.meta.invokable)
        };
        if param(q, "close").is_some() {
            return Err(LinkError::not_supported("close"));
        }
        // Open actions (host config) authenticate in the driver.
        if !self.open_actions.iter().any(|a| a == action) {
            let required = act
                .level
                .or(invokable)
                .filter(|p| *p != Perm::None)
                .ok_or_else(|| LinkError::not_supported("not invokable"))?;
            if caller.perm < required {
                return Err(denied());
            }
        }
        let args = match q.payload().map(|p| p.to_bytes()) {
            Some(b) if !b.is_empty() => from_slice::<Value>(&b)
                .map_err(|_| LinkError::new(Status::InvalidMessage, "bad args"))?,
            _ => Value::Map(Default::default()),
        };
        let Value::Map(given) = &args else {
            return Err(LinkError::new(Status::InvalidMessage, "args must be a map"));
        };
        validate_args(&act.params, given)?;
        let stream = act.stream == Some(true) || act.result == Some(ActionResult::Stream);
        let timeout = act
            .timeout_ms
            .map(|ms| Duration::from_millis(ms.into()))
            .unwrap_or(self.driver_timeout);
        let rid = att
            .rid
            .unwrap_or_else(|| self.next_rid.fetch_add(1, atomic::Ordering::Relaxed));
        let (sink, rx) = ReplySink::new(16);
        self.submit(Cmd::Invoke {
            path: path.to_owned(),
            action: action.to_owned(),
            args,
            caller,
            timeout,
            sink,
        })?;
        drain(q, rx, stream, rid, timeout).await;
        Ok(())
    }

    fn submit(&self, cmd: Cmd<C>) -> Result<()> {
        self.cmd.try_send(cmd).map_err(|e| match e {
            mpsc::error::TrySendError::Full(_) => LinkError::new(Status::Busy, "driver queue full"),
            mpsc::error::TrySendError::Closed(_) => {
                LinkError::new(Status::Disconnected, "driver stopped")
            }
        })
    }
}

/// Forward driver replies to the query. Plain action: first item ends it.
/// Stream: `rid` fixed, `seq` from 0, `last = true` on the final reply.
async fn drain(
    q: &Query,
    mut rx: mpsc::Receiver<SinkItem>,
    stream: bool,
    rid: u32,
    timeout: Duration,
) {
    let mut seq = 0u32;
    let att = |status: Status, seq: u32, last: bool| {
        let mut a = status_att(status);
        if stream {
            a.rid = Some(rid);
            a.seq = Some(seq);
            a.last = Some(last);
        }
        a
    };
    loop {
        let item = match tokio::time::timeout(timeout, rx.recv()).await {
            Err(_) => SinkItem::Error(LinkError::timeout("driver did not answer")),
            Ok(None) => SinkItem::Done(None),
            Ok(Some(i)) => i,
        };
        let (payload, a, end) = match item {
            SinkItem::Value(v) => (encode(&v), att(Status::Ok, seq, !stream), !stream),
            SinkItem::Done(v) => (
                v.as_ref().map(encode).unwrap_or(Ok(Vec::new())),
                att(Status::Ok, seq, true),
                true,
            ),
            SinkItem::Error(e) => {
                let mut a = att(e.status, seq, true);
                a.err = err_att(&e).err;
                (Ok(Vec::new()), a, true)
            }
        };
        match payload {
            Ok(p) => reply_here(q, p, a, true).await,
            Err(e) => {
                reply_here(q, Vec::new(), err_att(&e), true).await;
                return;
            }
        }
        if end {
            return;
        }
        seq += 1;
    }
}

/// Numeric order: exact for integer pairs, `f64` otherwise; `None` for NaN.
fn num_cmp(a: &Value, b: &Value) -> Option<Ordering> {
    let int = |v: &Value| match v {
        Value::Int(i) => Some(*i as i128),
        Value::UInt(u) => Some(*u as i128),
        _ => None,
    };
    match (int(a), int(b)) {
        (Some(x), Some(y)) => Some(x.cmp(&y)),
        _ => a.as_f64()?.partial_cmp(&b.as_f64()?),
    }
}

fn num_str(v: &Value) -> String {
    match v {
        Value::Int(i) => i.to_string(),
        Value::UInt(u) => u.to_string(),
        other => other.as_f64().map(|f| f.to_string()).unwrap_or_default(),
    }
}

/// Action arguments: no unknown names, every `required` present, each value
/// checked like a `~set` value against its `ParamMeta` (type, `enum`, finite).
fn validate_args(
    params: &std::collections::BTreeMap<String, ParamMeta>,
    given: &std::collections::BTreeMap<String, Value>,
) -> Result<()> {
    for (name, v) in given {
        let p = params
            .get(name)
            .ok_or_else(|| LinkError::invalid_parameter(format!("unknown param {name}")))?;
        let as_meta = NodeMeta {
            ty: p.ty,
            enum_values: p.enum_values.clone(),
            ..Default::default()
        };
        validate_value(&as_meta, v)
            .map_err(|e| LinkError::new(e.status, format!("{name}: {}", e.message)))?;
    }
    for (name, p) in params {
        if p.required == Some(true) && !given.contains_key(name) {
            return Err(LinkError::invalid_parameter(format!("missing {name}")));
        }
    }
    Ok(())
}

/// Type, `enum` and `cfg.min/max` checks before the driver sees a value.
fn validate_value(meta: &NodeMeta, v: &Value) -> Result<()> {
    let ok = match meta.ty {
        Some(TypeCode::Number) => {
            let x = v
                .as_f64()
                .ok_or_else(|| LinkError::invalid_parameter("expected number"))?;
            // NaN compares false both ways: reject non-finite values outright.
            if !x.is_finite() {
                return Err(LinkError::new(Status::OutOfRange, "value must be finite"));
            }
            if let Some(min) = meta.cfg_value("min").filter(|m| m.as_f64().is_some()) {
                // `None` (incomparable) fails closed.
                if num_cmp(v, min).is_none_or(|o| o == Ordering::Less) {
                    return Err(LinkError::new(
                        Status::OutOfRange,
                        format!("value {} < min {}", num_str(v), num_str(min)),
                    ));
                }
            }
            if let Some(max) = meta.cfg_value("max").filter(|m| m.as_f64().is_some()) {
                if num_cmp(v, max).is_none_or(|o| o == Ordering::Greater) {
                    return Err(LinkError::new(
                        Status::OutOfRange,
                        format!("value {} > max {}", num_str(v), num_str(max)),
                    ));
                }
            }
            true
        }
        Some(TypeCode::Enum) => {
            let Value::UInt(i) = v else {
                return Err(LinkError::invalid_parameter("expected enum index"));
            };
            if let Some(values) = &meta.enum_values {
                if *i as usize >= values.len() {
                    return Err(LinkError::new(
                        Status::OutOfRange,
                        "enum index out of range",
                    ));
                }
            }
            true
        }
        Some(TypeCode::String) => matches!(v, Value::Str(_)),
        Some(TypeCode::Bool) => matches!(v, Value::Bool(_)),
        Some(TypeCode::Binary) => matches!(v, Value::Bytes(_)),
        Some(TypeCode::Map) => matches!(v, Value::Map(_)),
        Some(TypeCode::Array) => matches!(v, Value::Array(_)),
        Some(TypeCode::Null) => matches!(v, Value::Null),
        Some(TypeCode::Dynamic) | None => true,
    };
    if ok {
        Ok(())
    } else {
        Err(LinkError::invalid_parameter(
            "value type does not match ~meta.type",
        ))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn number_range() {
        let m = NodeMeta::number().cfg("min", -40.0).cfg("max", 120.0);
        assert!(validate_value(&m, &Value::Float(21.0)).is_ok());
        assert!(validate_value(&m, &Value::UInt(21)).is_ok());
        let e = validate_value(&m, &Value::UInt(150)).unwrap_err();
        assert_eq!(e.status, Status::OutOfRange);
        assert_eq!(e.message, "value 150 > max 120");
        assert_eq!(
            validate_value(&m, &Value::Str("x".into()))
                .unwrap_err()
                .status,
            Status::InvalidParameter
        );
    }

    #[test]
    fn non_finite_and_exact_integer_bounds() {
        let m = NodeMeta::number().cfg("min", -40.0).cfg("max", 120.0);
        for x in [f64::NAN, f64::INFINITY, f64::NEG_INFINITY] {
            assert_eq!(
                validate_value(&m, &Value::Float(x)).unwrap_err().status,
                Status::OutOfRange
            );
        }
        // NaN bound fails closed
        let m = NodeMeta::number().cfg("max", f64::NAN);
        assert!(validate_value(&m, &Value::Float(1.0)).is_err());
        // 2^53 + 1 is not representable in f64; integer compare stays exact
        let m = NodeMeta::number().cfg("max", Value::UInt(1 << 53));
        assert!(validate_value(&m, &Value::UInt(1 << 53)).is_ok());
        assert_eq!(
            validate_value(&m, &Value::UInt((1 << 53) + 1))
                .unwrap_err()
                .status,
            Status::OutOfRange
        );
    }

    #[test]
    fn action_args() {
        let params: std::collections::BTreeMap<_, _> = [
            (
                "mode".to_owned(),
                ParamMeta::of(TypeCode::Enum)
                    .enum_values(["soft", "hard"])
                    .required(true),
            ),
            ("delay".to_owned(), ParamMeta::of(TypeCode::Number)),
        ]
        .into();
        let args = |kv: &[(&str, Value)]| -> std::collections::BTreeMap<String, Value> {
            kv.iter()
                .map(|(k, v)| ((*k).to_owned(), v.clone()))
                .collect()
        };
        assert!(validate_args(&params, &args(&[("mode", Value::UInt(1))])).is_ok());
        let err = |kv: &[(&str, Value)]| validate_args(&params, &args(kv)).unwrap_err().status;
        assert_eq!(err(&[]), Status::InvalidParameter); // missing required
        assert_eq!(err(&[("mode", Value::UInt(2))]), Status::OutOfRange);
        assert_eq!(
            err(&[("mode", Value::from("soft"))]),
            Status::InvalidParameter
        );
        assert_eq!(
            err(&[("mode", Value::UInt(0)), ("delay", Value::Float(f64::NAN))]),
            Status::OutOfRange
        );
        assert_eq!(
            err(&[("mode", Value::UInt(0)), ("extra", Value::Null)]),
            Status::InvalidParameter
        );
    }

    #[test]
    fn enum_index() {
        let m = NodeMeta::leaf(TypeCode::Enum).enum_values(["a", "b"]);
        assert!(validate_value(&m, &Value::UInt(1)).is_ok());
        assert_eq!(
            validate_value(&m, &Value::UInt(2)).unwrap_err().status,
            Status::OutOfRange
        );
    }
}
