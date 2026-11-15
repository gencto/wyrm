//! WYRM requester SDK. Spec: 05-methods.
//!
//! Node keys are full keys without suffix, e.g. `wy/plant-a/downstream/mock/g0/p0`.
//!
//! * [`WyrmClient::list`] — subscribes to `node/*/~meta` and liveliness
//!   *before* the snapshot `get`, so no change between the two is lost.
//! * [`WyrmClient::subscribe`] — subscribes to `pattern/~val`, then reads the
//!   stored values; per key, nothing older than what was already emitted.
//! * [`WyrmClient::set`] / [`WyrmClient::invoke`] — `get` on `~set` / `~act`
//!   with `InteractiveHigh + Block + express` (replies inherit the query QoS).
//!
//! No stream blocks the Zenoh session when its consumer is slow: each one
//! buffers into state it owns and has its own overflow policy (see
//! [`EventStream::dropped`] and the module docs of `streams`). A one-shot
//! request reads its replies at once.

#![forbid(unsafe_code)]

pub mod endpoint;
mod intake;
mod streams;
pub mod tokens;

pub use streams::{
    EventStream, ListEvent, ValEvent, INVOKE_BUFFER, LIST_BUFFER, MAX_PENDING_KEYS, MAX_RESYNCS,
    MAX_STREAM_KEYS, RELIABLE_BUFFER, VALUE_BUFFER,
};
pub use tokens::{SigningTokens, TokenSource};

use std::collections::VecDeque;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::mpsc;
use wyrm_core::codec::{from_slice, to_vec};
use wyrm_core::keyspace::{self, SUFFIX_META, SUFFIX_SET};
use wyrm_core::status::StatusCode;
use wyrm_core::{Attachment, HistRow, NodeMeta, SetRequest, Status, StatusGroup, Value};
use zenoh::cancellation::CancellationToken;
use zenoh::handlers::{FifoChannel, FifoChannelHandler, IntoHandler};
use zenoh::qos::{CongestionControl, Priority};
use zenoh::query::{ConsolidationMode, Reply};
use zenoh::Session;

/// Default `get` timeout (spec 05).
pub const DEFAULT_TIMEOUT: Duration = Duration::from_secs(10);
const LIST_PAGE: usize = 1000;

/// Request failed: an application status from the responder (`status ≥ 0x20`)
/// or a transport outcome mapped by the SDK (`timeout`, `disconnected`).
#[derive(Debug, Clone, PartialEq, thiserror::Error)]
#[error("{}: {message}", status_name(*status))]
pub struct ClientError {
    pub status: StatusCode,
    pub message: String,
}

fn status_name(s: StatusCode) -> String {
    match s {
        StatusCode::Known(s) => s.name().to_owned(),
        StatusCode::User(c) => format!("user_{c:#04x}"),
        StatusCode::Unknown(c) => format!("unknown_{c:#04x}"),
    }
}

impl ClientError {
    pub fn new(status: Status, message: impl Into<String>) -> Self {
        Self {
            status: status.into(),
            message: message.into(),
        }
    }

    pub fn is(&self, s: Status) -> bool {
        self.status == StatusCode::Known(s)
    }
}

impl From<zenoh::Error> for ClientError {
    fn from(e: zenoh::Error) -> Self {
        Self::new(Status::Disconnected, e.to_string())
    }
}

pub type Result<T, E = ClientError> = core::result::Result<T, E>;

/// One child as returned by `list`: its name and `~meta` (the `view=list`
/// summary in a snapshot, the full meta in later events).
#[derive(Debug, Clone, PartialEq)]
pub struct Child {
    pub name: String,
    pub meta: NodeMeta,
}

/// One reply, decoded.
#[derive(Debug, Clone)]
pub struct Response {
    pub key: String,
    pub att: Attachment,
    pub payload: Vec<u8>,
}

impl Response {
    pub fn value(&self) -> Result<Option<Value>> {
        if self.payload.is_empty() {
            return Ok(None);
        }
        from_slice(&self.payload)
            .map(Some)
            .map_err(|e| ClientError::new(Status::InvalidMessage, e.to_string()))
    }

    /// Responder reply (`~meta`, `~set`, `~act`): `status` is mandatory
    /// (spec 04). Missing → `invalid_message`; `≥ 0x20` → that error.
    fn check(self) -> Result<Self> {
        match self.att.status {
            None => Err(ClientError::new(
                Status::InvalidMessage,
                "reply without status",
            )),
            Some(s) if s.group() == StatusGroup::Error => Err(ClientError {
                status: s,
                message: self.att.err.clone().unwrap_or_default(),
            }),
            Some(_) => Ok(self),
        }
    }
}

#[derive(Clone)]
pub struct WyrmClient {
    session: Session,
    tokens: Option<Arc<dyn TokenSource>>,
    timeout: Duration,
    origin: Option<String>,
}

/// `wy/<site>/downstream/<link>` that owns `key`, if any.
pub fn owner_key(key: &str) -> Option<String> {
    let segs: Vec<&str> = key.splitn(5, '/').collect();
    (segs.len() >= 4 && segs[0] == keyspace::ROOT && segs[2] == "downstream")
        .then(|| segs[..4].join("/"))
}

/// `wy/<site>/downstream` — its children are links, known from liveliness.
pub(crate) fn is_links_root(key: &str) -> bool {
    let segs: Vec<&str> = key.split('/').collect();
    segs.len() == 3 && segs[0] == keyspace::ROOT && segs[2] == "downstream"
}

/// The request body of a `~set` of `v`, byte for byte as [`WyrmClient::set`] sends it: what a
/// token's `args` claim binds (spec 04).
pub fn set_payload(v: Value) -> Result<Vec<u8>> {
    to_vec(&SetRequest { v }).map_err(|e| ClientError::new(Status::InternalError, e.to_string()))
}

/// The request body of an `~act/*` with `args`, byte for byte as [`WyrmClient::invoke`] sends
/// it.
pub fn invoke_payload(args: &Value) -> Result<Vec<u8>> {
    to_vec(args).map_err(|e| ClientError::new(Status::InternalError, e.to_string()))
}

fn suffixed(node: &str, suffix: &str) -> String {
    format!("{node}/{suffix}")
}

/// A history read (spec 01 `~val?history=`): `from`/`to` in RFC 3339 (`to`
/// empty = now), optional `agg` (`avg`, `min`, `max`, `sum`, `count`,
/// `first`, `last`, `delta`, `and`, `or`), `window` (`5m`, `1h`, …) and
/// `limit` (rows; the broker caps it).
#[derive(Debug, Clone, Default, PartialEq)]
pub struct HistoryQuery {
    pub from: String,
    pub to: String,
    pub agg: Option<String>,
    pub window: Option<String>,
    pub limit: Option<usize>,
}

/// History rows as a frame result: `[[t, v, q] | [t_start, v], …]`.
pub fn history_value(rows: Vec<HistRow>) -> Value {
    Value::Array(
        rows.into_iter()
            .map(|r| {
                let mut a = vec![Value::UInt(r.t), r.v];
                a.extend(r.q.map(|q| Value::UInt(q.code().into())));
                Value::Array(a)
            })
            .collect(),
    )
}

impl HistoryQuery {
    /// From `from` to now.
    pub fn since(from: impl Into<String>) -> Self {
        Self {
            from: from.into(),
            ..Default::default()
        }
    }

    /// From the frame args of the gateway and the FFI:
    /// `{from, to?, agg?, window?, limit?}` (texts; `limit` a number).
    pub fn from_args(args: Option<&Value>) -> Self {
        let empty = std::collections::BTreeMap::new();
        let m = match args {
            Some(Value::Map(m)) => m,
            _ => &empty,
        };
        let text = |k: &str| match m.get(k) {
            Some(Value::Str(s)) if !s.trim().is_empty() => Some(s.trim().to_owned()),
            _ => None,
        };
        Self {
            from: text("from").unwrap_or_default(),
            to: text("to").unwrap_or_default(),
            agg: text("agg"),
            window: text("window"),
            limit: m
                .get("limit")
                .and_then(Value::as_f64)
                .filter(|n| n.is_finite() && *n >= 1.0)
                .map(|n| n as usize),
        }
    }

    /// The selector parameters, `&`-separated as spec 01 writes them.
    pub fn params(&self) -> String {
        let mut p = format!("history={}..{}", self.from.trim(), self.to.trim());
        if let Some(a) = self.agg.as_deref().filter(|a| !a.is_empty()) {
            p.push_str(&format!("&agg={a}"));
        }
        if let Some(w) = self.window.as_deref().filter(|w| !w.is_empty()) {
            p.push_str(&format!("&window={w}"));
        }
        if let Some(l) = self.limit {
            p.push_str(&format!("&limit={l}"));
        }
        p
    }
}

impl WyrmClient {
    pub fn new(session: Session) -> Self {
        Self {
            session,
            tokens: None,
            timeout: DEFAULT_TIMEOUT,
            origin: None,
        }
    }

    /// `attachment.origin` on requests that carry a token. Responders keep
    /// it only if it is the token's subject or `<subject>/...` (spec 04), e.g.
    /// `user:alice/ai:claude` for a human-approved call made by an AI.
    pub fn with_origin(mut self, origin: impl Into<String>) -> Self {
        self.origin = Some(origin.into());
        self
    }

    pub fn with_tokens(mut self, tokens: Arc<dyn TokenSource>) -> Self {
        self.tokens = Some(tokens);
        self
    }

    pub fn with_timeout(mut self, timeout: Duration) -> Self {
        self.timeout = timeout;
        self
    }

    pub fn session(&self) -> &Session {
        &self.session
    }

    /// A token for `key` from the configured source, e.g. a proof of rights
    /// on a flow's command target (`dataflows/~act/deploy {proofs}`).
    pub fn proof(&self, key: &str) -> Option<Vec<u8>> {
        self.tokens.as_ref().and_then(|t| t.token(key))
    }

    fn token_att(&self, key: &str) -> Attachment {
        let ptok = self.tokens.as_ref().and_then(|t| t.token(key));
        Attachment {
            origin: ptok.as_ref().and(self.origin.clone()),
            ptok,
            ..Default::default()
        }
    }

    /// Raw `get` into a FIFO. `interactive` selects the `~set/~act` QoS.
    /// Only for replies read at once: a FIFO that fills blocks the session.
    async fn query(
        &self,
        selector: &str,
        payload: Option<Vec<u8>>,
        att: Attachment,
        interactive: bool,
        timeout: Duration,
    ) -> Result<FifoChannelHandler<Reply>> {
        self.query_with(
            selector,
            payload,
            att,
            interactive,
            timeout,
            FifoChannel::default(),
            None,
        )
        .await
    }

    /// Raw `get` into `handler`.
    #[allow(
        clippy::too_many_arguments,
        reason = "private: one argument per builder knob"
    )]
    async fn query_with<H>(
        &self,
        selector: &str,
        payload: Option<Vec<u8>>,
        att: Attachment,
        interactive: bool,
        timeout: Duration,
        handler: H,
        cancel: Option<CancellationToken>,
    ) -> Result<H::Handler>
    where
        H: IntoHandler<Reply> + Send,
        H::Handler: Send,
    {
        let att =
            to_vec(&att).map_err(|e| ClientError::new(Status::InternalError, e.to_string()))?;
        let mut get = self
            .session
            .get(selector)
            .consolidation(ConsolidationMode::None)
            .timeout(timeout)
            .attachment(att);
        get = if interactive {
            get.priority(Priority::InteractiveHigh)
                .congestion_control(CongestionControl::Block)
                .express(true)
        } else {
            get.priority(Priority::DataHigh)
                .congestion_control(CongestionControl::Block)
        };
        if let Some(p) = payload {
            get = get.payload(p);
        }
        if let Some(c) = cancel {
            get = get.cancellation_token(c);
        }
        Ok(get.with(handler).await?)
    }

    /// Exactly one reply expected; none → `timeout` or `disconnected`.
    async fn one(
        &self,
        selector: &str,
        payload: Option<Vec<u8>>,
        att: Attachment,
        interactive: bool,
    ) -> Result<Response> {
        self.one_within(selector, payload, att, interactive, self.timeout)
            .await
    }

    async fn one_within(
        &self,
        selector: &str,
        payload: Option<Vec<u8>>,
        att: Attachment,
        interactive: bool,
        timeout: Duration,
    ) -> Result<Response> {
        let rx = self
            .query(selector, payload, att, interactive, timeout)
            .await?;
        match rx.recv_async().await.ok() {
            // Zenoh ends a query that timed out with its own error reply:
            // that is no reply from the responder (spec 05)
            Some(r) if is_query_timeout(&r) => Err(self.no_reply(selector).await),
            Some(r) => response(&r)?.check(),
            None => Err(self.no_reply(selector).await),
        }
    }

    /// Spec 05: no reply is `disconnected` only if the owner's liveliness is gone.
    async fn no_reply(&self, selector: &str) -> ClientError {
        let key = selector.split('?').next().unwrap_or(selector);
        let Some(owner) = owner_key(key) else {
            return ClientError::new(Status::Timeout, "no reply");
        };
        let alive = match self
            .session
            .liveliness()
            .get(&owner)
            .timeout(Duration::from_secs(1))
            .await
        {
            Ok(rx) => rx.recv_async().await.is_ok_and(|r| r.result().is_ok()),
            Err(_) => false,
        };
        if alive {
            ClientError::new(Status::Timeout, "no reply")
        } else {
            ClientError::new(Status::Disconnected, format!("{owner} is not connected"))
        }
    }

    /// `get node/~val?history=…` (spec 03): the rows in time order, raw
    /// `[t, v, q]` or, with `agg`, `[t_start, v]`. Empty when nobody records
    /// the point. Rights as `subscribe`: the session's ACL on `node/~val`.
    pub async fn history(&self, node: &str, q: &HistoryQuery) -> Result<Vec<HistRow>> {
        let selector = format!("{}?{}", suffixed(node, keyspace::SUFFIX_VAL), q.params());
        let rx = self
            .query(&selector, None, Attachment::default(), false, self.timeout)
            .await?;
        let mut chunks: Vec<Vec<HistRow>> = Vec::new();
        while let Some(r) = next_response(&rx).await {
            let r = r?;
            if let Some(s) = r.att.status {
                if s.group() == StatusGroup::Error {
                    return Err(ClientError {
                        status: s,
                        message: r.att.err.unwrap_or_default(),
                    });
                }
            }
            // The storage answers the same key with the last value (a map).
            if let Ok(rows) = from_slice::<Vec<HistRow>>(&r.payload) {
                chunks.push(rows);
            }
        }
        chunks.sort_by_key(|c| c.first().map_or(0, |r| r.t));
        Ok(chunks.into_iter().flatten().collect())
    }

    /// `get node/~meta` (full). Retries once with a `ptok` on `permission_denied`
    /// (restricted nodes) when a token source is set.
    pub async fn meta(&self, node: &str) -> Result<NodeMeta> {
        let r = self.meta_raw(node, "").await?;
        decode(&r.payload)
    }

    /// A profile from `wy/<site>/pub/<name>/~meta`; `expand` asks for the
    /// profile with its `extends` chain folded in.
    pub async fn profile(
        &self,
        site: &str,
        name: &str,
        expand: bool,
    ) -> Result<wyrm_core::profile::ProfileDef> {
        let key = format!("wy/{site}/pub/{name}/~meta");
        let sel = if expand {
            format!("{key}?expand=true")
        } else {
            key
        };
        let r = self.one(&sel, None, Attachment::default(), false).await?;
        decode(&r.payload)
    }

    /// `~meta` of `node` with every absent field taken from its profile
    /// chain (spec 02 "Успадкування"). Profiles given by code are not
    /// expanded yet.
    pub async fn meta_expanded(&self, node: &str) -> Result<NodeMeta> {
        let meta = self.meta(node).await?;
        let Some(wyrm_core::meta::Profile::Name(name)) = &meta.is else {
            return Ok(meta);
        };
        let site = node
            .strip_prefix("wy/")
            .and_then(|r| r.split('/').next())
            .unwrap_or_default();
        let p = self.profile(site, name, true).await?;
        Ok(wyrm_core::profile::inherit(&meta, &p.meta))
    }

    async fn meta_raw(&self, node: &str, params: &str) -> Result<Response> {
        let key = suffixed(node, SUFFIX_META);
        let sel = if params.is_empty() {
            key.clone()
        } else {
            format!("{key}?{params}")
        };
        // A read is safe to send again: tries of at most half the timeout
        // each, so one lost query (seen once across a peer link, backlog
        // item 6) costs half a timeout, and a missing node no more than one.
        let half = (self.timeout / 2).max(Duration::from_secs(1));
        self.meta_raw_within(&key, &sel, 2 * half, half).await
    }

    /// One `~meta` read of `sel` (on `key`) within `budget`, each try at
    /// most `per_try`.
    async fn meta_raw_within(
        &self,
        key: &str,
        sel: &str,
        budget: Duration,
        per_try: Duration,
    ) -> Result<Response> {
        // Under a link, `timeout` means its token is there (`no_reply`
        // asked): reads go on through the route gap (see `read_through_gap`).
        let owned = owner_key(key).is_some();
        read_through_gap(budget, per_try, owned, |within| async move {
            match self
                .one_within(sel, None, Attachment::default(), false, within)
                .await
            {
                Err(e) if e.is(Status::PermissionDenied) && self.tokens.is_some() => {
                    self.one_within(sel, None, self.token_att(key), false, within)
                        .await
                }
                r => r,
            }
        })
        .await
    }

    /// A link's root `~meta` for a list of the links root: what the read
    /// says about the child its token announced, within
    /// [`LIST_READ_WINDOW`] (a list never waits longer for one child).
    pub(crate) async fn link_meta(&self, node: &str) -> LinkMeta {
        let key = suffixed(node, SUFFIX_META);
        let read = self
            .meta_raw_within(&key, &key, LIST_READ_WINDOW, LIST_READ_WINDOW)
            .await
            .and_then(|r| decode::<NodeMeta>(&r.payload));
        match read {
            Ok(m) => LinkMeta::Read(m),
            // its token is gone (or the session): a `Delete` follows
            Err(e) if e.is(Status::Disconnected) => LinkMeta::Gone,
            // the token is there, but no reply came in the whole budget
            Err(e) if e.is(Status::Timeout) => LinkMeta::Silent,
            // the link answered with a refusal: the name, nothing more
            Err(e) => {
                tracing::debug!(node, "link meta: {e}");
                LinkMeta::Read(NodeMeta::default())
            }
        }
    }

    /// A node's document (`suffix` = `~state` or `~def`, spec 01) as its responder stores it:
    /// canonical CBOR. Like `~meta`, asked again with a `ptok` on `permission_denied` (a
    /// restricted node), so the caller's own rights decide.
    pub async fn doc(&self, node: &str, suffix: &str) -> Result<Vec<u8>> {
        let key = suffixed(node, suffix);
        let r = match self.one(&key, None, Attachment::default(), false).await {
            Err(e) if e.is(Status::PermissionDenied) && self.tokens.is_some() => {
                self.one(&key, None, self.token_att(&key), false).await
            }
            r => r,
        };
        Ok(r?.payload)
    }

    /// `view=keys`: descendant paths relative to `node`.
    pub async fn resolve(
        &self,
        node: &str,
        matcher: Option<&str>,
        depth: Option<usize>,
    ) -> Result<Vec<String>> {
        let mut params = "view=keys".to_owned();
        if let Some(m) = matcher {
            params.push_str("&match=");
            params.push_str(m);
        }
        if let Some(d) = depth {
            params.push_str(&format!("&depth={d}"));
        }
        let r = self.meta_raw(node, &params).await?;
        let compressed: Vec<String> = decode(&r.payload)?;
        Ok(keyspace::expand_keys(compressed))
    }

    /// Snapshot of the children of `node`: names from `view=full`, summaries
    /// from `view=list` (paged), consistent on the parent's `rev`.
    ///
    /// On the links root (`wy/<site>/downstream`) a link whose `~meta` gave
    /// no reply in the whole timeout, while its token is there, is left out:
    /// a child always comes with the meta its link answered (`docs/links.md`
    /// "A link that has just appeared"). A link that refused the read is
    /// listed with an empty meta.
    pub async fn children(&self, node: &str) -> Result<Vec<Child>> {
        Ok(self.snapshot(node).await?.0)
    }

    /// [`children`](Self::children) and, on the links root, the links left
    /// out because their `~meta` gave no reply (a list reads them again).
    pub(crate) async fn snapshot(&self, node: &str) -> Result<(Vec<Child>, Vec<String>)> {
        if is_links_root(node) {
            return self.links(node).await;
        }
        Ok((self.children_of(node).await?, Vec::new()))
    }

    async fn children_of(&self, node: &str) -> Result<Vec<Child>> {
        for _ in 0..3 {
            let full = self.meta_raw(node, "").await?;
            let rev = full.att.rev;
            let names = decode::<NodeMeta>(&full.payload)?
                .children
                .unwrap_or_default();
            let mut summaries: Vec<NodeMeta> = Vec::with_capacity(names.len());
            let mut consistent = true;
            while summaries.len() < names.len() {
                let page = self
                    .meta_raw(
                        node,
                        &format!("view=list&from={}&limit={LIST_PAGE}", summaries.len()),
                    )
                    .await?;
                let items: Vec<NodeMeta> = decode(&page.payload)?;
                if page.att.rev != rev || items.is_empty() {
                    consistent = false;
                    break;
                }
                summaries.extend(items);
            }
            if consistent && summaries.len() == names.len() {
                return Ok(names
                    .into_iter()
                    .zip(summaries)
                    .map(|(name, meta)| Child { name, meta })
                    .collect());
            }
        }
        Err(ClientError::new(Status::Busy, "children kept changing"))
    }

    /// Links under `wy/<site>/downstream`: liveliness tokens, then each root
    /// `~meta`; and the names of those whose `~meta` gave no reply.
    async fn links(&self, root: &str) -> Result<(Vec<Child>, Vec<String>)> {
        let rx = self
            .session
            .liveliness()
            .get(format!("{root}/*"))
            .timeout(self.timeout)
            .await?;
        let mut names = Vec::new();
        while let Ok(r) = rx.recv_async().await {
            if let Ok(s) = r.result() {
                if let Some(name) = s.key_expr().as_str().rsplit('/').next() {
                    names.push(name.to_owned());
                }
            }
        }
        names.sort();
        Ok(read_links(names, self.link_reader(root)).await)
    }

    /// Reads the root `~meta` of the links under `root`, one name at a time
    /// (`link_meta`, bounded by [`LIST_READ_WINDOW`]).
    pub(crate) fn link_reader(&self, root: &str) -> ReadLink {
        let (me, root) = (self.clone(), root.to_owned());
        Arc::new(move |name: String| {
            let (me, node) = (me.clone(), format!("{root}/{name}"));
            Box::pin(async move { me.link_meta(&node).await })
        })
    }

    /// Reactive `list`: first event is `Refreshed` with the snapshot, then
    /// `Added / Changed / Removed / Disconnected / Connected`.
    pub async fn list(&self, node: &str) -> Result<EventStream<ListEvent>> {
        streams::list(self.clone(), node.to_owned()).await
    }

    /// Reactive values for a node pattern (`…/mock/**`): stored values first,
    /// then live samples.
    pub async fn subscribe(&self, pattern: &str) -> Result<EventStream<ValEvent>> {
        self.subscribe_filtered(pattern, |_| true).await
    }

    /// [`subscribe`](Self::subscribe) of only the node keys `keep` accepts:
    /// a refused key never takes room in the stream's buffer (the gateway
    /// passes the user's read grants). `keep` runs on Zenoh's receive path:
    /// keep it short, no I/O.
    pub async fn subscribe_filtered(
        &self,
        pattern: &str,
        keep: impl Fn(&str) -> bool + Send + Sync + 'static,
    ) -> Result<EventStream<ValEvent>> {
        streams::subscribe(self.clone(), pattern.to_owned(), Arc::new(keep)).await
    }

    /// QoS 2/3 values (`cfg.qos >= 2` points): cached history from the
    /// publishers first, then live samples, with gap recovery.
    #[cfg(feature = "advanced")]
    pub async fn subscribe_reliable(&self, pattern: &str) -> Result<EventStream<ValEvent>> {
        streams::subscribe_reliable(self.clone(), pattern.to_owned()).await
    }

    /// Write `v` to `node/~set`.
    pub async fn set(&self, node: &str, v: impl Into<Value>) -> Result<()> {
        let key = suffixed(node, SUFFIX_SET);
        let payload = set_payload(v.into())?;
        self.one(&key, Some(payload), self.token_att(&key), true)
            .await
            .map(|_| ())
    }

    /// `invoke` returning every reply: one for a plain action, `seq`-ordered
    /// elements for a stream (the final `last = true` reply is not emitted
    /// unless it carries a value). Each reply must arrive within the client
    /// timeout of the previous one. A consumer more than [`INVOKE_BUFFER`]
    /// replies behind gets the replies held, then `resource_exhausted`, and
    /// the stream ends (the lost replies count in [`EventStream::dropped`]);
    /// it never holds up the session.
    pub async fn invoke(
        &self,
        node: &str,
        action: &str,
        args: Value,
    ) -> Result<EventStream<Result<Option<Value>>>> {
        let key = suffixed(node, &format!("~act/{action}"));
        let payload = invoke_payload(&args)?;
        let dropped = Arc::new(AtomicU64::new(0));
        #[cfg(test)]
        LIVE_REPLIES.fetch_add(1, Ordering::SeqCst);
        let intake = intake::Intake::new(Replies {
            queue: VecDeque::new(),
            overflow: false,
            done: false,
            dropped: dropped.clone(),
        });
        // The zenoh query lives long; idleness is bounded per reply below.
        // It ends with the stream: the task cancels it on its way out, and
        // the feed holds the buffer weakly, so nothing is kept after that.
        let cancel = CancellationToken::default();
        self.query_with(
            &key,
            Some(payload),
            self.token_att(&key),
            true,
            Duration::from_secs(3600),
            intake.feed(Replies::push, |r| r.done = true),
            Some(cancel.clone()),
        )
        .await?;
        let (tx, out) = mpsc::channel(64);
        let idle = self.timeout;
        let me = self.clone();
        let lost = dropped.clone();
        tokio::spawn(async move {
            let _cancel = CancelOnDrop(cancel);
            let mut got_any = false;
            loop {
                let next = intake.next(Replies::pop);
                let next = tokio::select! {
                    r = tokio::time::timeout(idle, next) => r,
                    _ = tx.closed() => return,
                };
                let r = match next {
                    Err(_) => Some(Err(ClientError::new(Status::Timeout, "no reply"))),
                    Ok(ReplyStep::Overflow) => {
                        let n = lost.load(Ordering::Relaxed);
                        let msg = format!("consumer too slow: {n} replies lost");
                        Some(Err(ClientError::new(Status::ResourceExhausted, msg)))
                    }
                    // Zenoh's own timeout reply: no (more) reply from the responder
                    Ok(ReplyStep::Reply(reply)) if is_query_timeout(&reply) => {
                        Some(Err(me.no_reply(&key).await))
                    }
                    Ok(ReplyStep::Reply(reply)) => Some(response(&reply).and_then(Response::check)),
                    Ok(ReplyStep::Done) if !got_any => Some(Err(me.no_reply(&key).await)),
                    Ok(ReplyStep::Done) => None,
                };
                let Some(r) = r else { return };
                got_any = true;
                let (item, end) = match r {
                    Err(e) => (Some(Err(e)), true),
                    Ok(resp) => {
                        let last = resp.att.last.unwrap_or(resp.att.rid.is_none());
                        match resp.value() {
                            Ok(None) if last && resp.att.rid.is_some() => (None, true),
                            v => (Some(v), last),
                        }
                    }
                };
                if let Some(item) = item {
                    if tx.send(item).await.is_err() {
                        return;
                    }
                }
                if end {
                    return;
                }
            }
        });
        Ok(EventStream::new(out, dropped))
    }

    /// `~act/<action>?check` (spec 05 0.2.33): the responder checks the call as the action
    /// would take it (token, level, arguments, its own parsing) and does nothing. Send it only
    /// where the responder's root `~meta` has `attr.check` (an older one runs the action).
    pub async fn invoke_check(&self, node: &str, action: &str, args: Value) -> Result<()> {
        let key = suffixed(node, &format!("~act/{action}"));
        let payload =
            to_vec(&args).map_err(|e| ClientError::new(Status::InternalError, e.to_string()))?;
        self.one(
            &format!("{key}?check"),
            Some(payload),
            self.token_att(&key),
            true,
        )
        .await
        .map(|_| ())
    }

    /// `invoke` of a plain action: its single result.
    pub async fn invoke_one(&self, node: &str, action: &str, args: Value) -> Result<Option<Value>> {
        let mut s = self.invoke(node, action, args).await?;
        s.next().await.unwrap_or(Ok(None))
    }
}

/// How long a list waits for one link's root `~meta` before it goes on
/// without that link: it covers the route gap with a wide margin. The gap is
/// one routing-tree computation, which Zenoh 1.10.1 runs 100 ms after the
/// last change (`TREES_COMPUTATION_DELAY_MS`), so a read in the gap answers
/// within about 100–200 ms. A link that has given no reply in this window is
/// read again in the background ([`ListEvent::Added`] when it answers); it
/// never holds up its siblings or the first `Refreshed`. A direct
/// [`WyrmClient::meta`] keeps the full timeout (spec 05).
pub const LIST_READ_WINDOW: Duration = Duration::from_millis(1500);

/// Reads one link's root `~meta` by its name (see [`WyrmClient::link_reader`]).
pub(crate) type ReadLink = Arc<
    dyn Fn(String) -> std::pin::Pin<Box<dyn std::future::Future<Output = LinkMeta> + Send>>
        + Send
        + Sync,
>;

/// The children `names` (sorted) read all at once with `read`; the names
/// of those that kept silent come second. One silent link costs the whole
/// snapshot at most one [`LIST_READ_WINDOW`], whatever their number.
pub(crate) async fn read_links(names: Vec<String>, read: ReadLink) -> (Vec<Child>, Vec<String>) {
    let mut reads = tokio::task::JoinSet::new();
    for (i, name) in names.into_iter().enumerate() {
        let read = read.clone();
        reads.spawn(async move { (i, read(name.clone()).await, name) });
    }
    let mut done = Vec::new();
    while let Some(r) = reads.join_next().await {
        match r {
            Ok(x) => done.push(x),
            Err(e) => tracing::debug!("link meta read: {e}"),
        }
    }
    done.sort_by_key(|(i, ..)| *i);
    let (mut out, mut silent) = (Vec::new(), Vec::new());
    for (_, r, name) in done {
        match r {
            LinkMeta::Read(meta) => out.push(Child { name, meta }),
            LinkMeta::Gone => {}
            LinkMeta::Silent => silent.push(name),
        }
    }
    (out, silent)
}

/// The first pause between two reads in the route gap; it doubles up to
/// [`GAP_PAUSE_MAX`].
const GAP_PAUSE_FIRST: Duration = Duration::from_millis(25);
const GAP_PAUSE_MAX: Duration = Duration::from_millis(200);

/// What a list of the links root learns from a link's root `~meta`.
// moved once per link read; boxing would cost an allocation each
#[allow(clippy::large_enum_variant)]
#[derive(Debug, Clone, PartialEq)]
pub(crate) enum LinkMeta {
    /// The link answered: its meta (empty if it refused the read).
    Read(NodeMeta),
    /// Its token is gone.
    Gone,
    /// Its token is there, but no reply came in the whole budget.
    Silent,
}

/// One read, sent again while it ends with `timeout` and `budget` lasts.
///
/// The route gap (backlog item 6, 2026-11-15): when a router connects, its
/// liveliness tokens are routed about one routing-tree computation (Zenoh
/// 1.10.1 debounces it by 100 ms) before queries to it are, and in that gap
/// a query toward it ends at once with no reply. With `owned` (the key is
/// under a link, so `timeout` means `no_reply` found the link's token) the
/// token proves that the responder exists, and the read is sent again after
/// a short pause (25 ms, doubled up to 200 ms) until it has an answer, the
/// token is gone (`disconnected`), or `budget` is spent. Without `owned`,
/// two tries: a key that no queryable serves fails at once. `read` gets the
/// timeout of its try, at most `per_try`.
pub(crate) async fn read_through_gap<T, F, Fut>(
    budget: Duration,
    per_try: Duration,
    owned: bool,
    mut read: F,
) -> Result<T>
where
    F: FnMut(Duration) -> Fut,
    Fut: std::future::Future<Output = Result<T>>,
{
    use tokio::time::Instant;
    let deadline = Instant::now() + budget;
    let mut pause = GAP_PAUSE_FIRST;
    let mut tries = 0u32;
    loop {
        let left = deadline.saturating_duration_since(Instant::now());
        let e = match read(per_try.min(left)).await {
            Err(e) if e.is(Status::Timeout) => e,
            r => return r,
        };
        tries += 1;
        let left = deadline.saturating_duration_since(Instant::now());
        if !owned {
            if tries >= 2 || left.is_zero() {
                return Err(e);
            }
            continue;
        }
        if left <= pause {
            return Err(e);
        }
        tokio::time::sleep(pause).await;
        pause = (pause * 2).min(GAP_PAUSE_MAX);
    }
}

pub(crate) async fn next_response(rx: &FifoChannelHandler<Reply>) -> Option<Result<Response>> {
    let reply = rx.recv_async().await.ok()?;
    Some(response(&reply))
}

/// The error reply Zenoh itself makes when a query times out (the session's
/// own timer, or a router's query cleanup): `"Timeout"`. A responder never
/// answers with a reply error (it sends a status attachment, spec 04).
fn is_query_timeout(reply: &Reply) -> bool {
    reply
        .result()
        .err()
        .is_some_and(|e| e.payload().to_bytes().as_ref() == b"Timeout")
}

fn response(reply: &Reply) -> Result<Response> {
    match reply.result() {
        Ok(s) => {
            // An unreadable attachment is an error, never an empty one.
            let att = match s.attachment() {
                None => Ok(Attachment::default()),
                Some(a) => decode::<Attachment>(&a.to_bytes()),
            };
            att.map(|att| Response {
                key: s.key_expr().as_str().to_owned(),
                att,
                payload: s.payload().to_bytes().to_vec(),
            })
        }
        Err(e) => Err(ClientError::new(
            Status::InternalError,
            String::from_utf8_lossy(&e.payload().to_bytes()).into_owned(),
        )),
    }
}

/// Cancels the Zenoh query of a stream `invoke` when its task ends (the
/// stream is dropped, it ended, or it failed).
struct CancelOnDrop(CancellationToken);

impl Drop for CancelOnDrop {
    fn drop(&mut self) {
        let ct = self.0.clone();
        if let Ok(rt) = tokio::runtime::Handle::try_current() {
            rt.spawn(async move {
                let _ = ct.cancel().await;
            });
        }
    }
}

/// Live `Replies` buffers, for the test that a dropped stream frees its own.
#[cfg(test)]
static LIVE_REPLIES: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);

#[cfg(test)]
impl Drop for Replies {
    fn drop(&mut self) {
        LIVE_REPLIES.fetch_sub(1, Ordering::SeqCst);
    }
}

/// Replies of a stream `invoke`, bounded by [`INVOKE_BUFFER`]. Results are
/// not state: none is dropped silently, an overflow ends the stream.
struct Replies {
    queue: VecDeque<Reply>,
    overflow: bool,
    /// Zenoh dropped the handler: the query is final.
    done: bool,
    dropped: Arc<AtomicU64>,
}

#[allow(
    clippy::large_enum_variant,
    reason = "moved once per reply; boxing would cost an allocation each"
)]
enum ReplyStep {
    Reply(Reply),
    Overflow,
    Done,
}

impl Replies {
    fn push(&mut self, r: Reply) {
        if self.overflow || self.queue.len() >= INVOKE_BUFFER {
            self.overflow = true;
            self.dropped.fetch_add(1, Ordering::Relaxed);
        } else {
            self.queue.push_back(r);
        }
    }

    fn pop(&mut self) -> Option<ReplyStep> {
        if let Some(r) = self.queue.pop_front() {
            Some(ReplyStep::Reply(r))
        } else if self.overflow {
            Some(ReplyStep::Overflow)
        } else {
            self.done.then_some(ReplyStep::Done)
        }
    }
}

pub(crate) fn decode<T: for<'b> minicbor::Decode<'b, ()>>(b: &[u8]) -> Result<T> {
    from_slice(b).map_err(|e| ClientError::new(Status::InvalidMessage, e.to_string()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::AtomicBool;

    fn isolated() -> zenoh::Config {
        let mut c = zenoh::Config::default();
        for (k, v) in [
            ("mode", r#""peer""#),
            ("listen/endpoints", "[]"),
            ("connect/endpoints", "[]"),
            ("scouting/multicast/enabled", "false"),
            ("scouting/gossip/enabled", "false"),
        ] {
            c.insert_json5(k, v).unwrap();
        }
        c
    }

    /// Security review: a stream `invoke` whose reader is gone must not
    /// keep buffering the replies of its hour-long query.
    #[tokio::test(flavor = "multi_thread")]
    async fn a_dropped_invoke_stream_frees_its_buffer() {
        let session = zenoh::open(isolated()).await.unwrap();
        let sent = Arc::new(AtomicU64::new(0));
        let stop = Arc::new(AtomicBool::new(false));
        let (n, halt) = (sent.clone(), stop.clone());
        let _q = session
            .declare_queryable("wy/t/downstream/fake/**")
            .callback(move |q| {
                let (n, halt) = (n.clone(), halt.clone());
                tokio::spawn(async move {
                    // an endless stream action: one element per millisecond
                    let mut att = Attachment::with_status(Status::Ok);
                    att.rid = Some(1);
                    let att = to_vec(&att).unwrap();
                    while !halt.load(Ordering::SeqCst) {
                        let i = n.fetch_add(1, Ordering::SeqCst);
                        let v = to_vec(&Value::UInt(i)).unwrap();
                        let k = q.key_expr().clone();
                        if q.reply(k, v).attachment(att.clone()).await.is_err() {
                            return;
                        }
                        tokio::time::sleep(Duration::from_millis(1)).await;
                    }
                });
            })
            .await
            .unwrap();
        let c = WyrmClient::new(session.clone()).with_timeout(Duration::from_secs(2));
        let before = LIVE_REPLIES.load(Ordering::SeqCst);
        let mut s = c
            .invoke(
                "wy/t/downstream/fake/x",
                "a",
                Value::Map(Default::default()),
            )
            .await
            .unwrap();
        assert!(matches!(s.next().await, Some(Ok(Some(_)))));
        assert_eq!(LIVE_REPLIES.load(Ordering::SeqCst), before + 1);
        drop(s);
        let until = std::time::Instant::now() + Duration::from_secs(2);
        while LIVE_REPLIES.load(Ordering::SeqCst) > before {
            assert!(std::time::Instant::now() < until, "the buffer is kept");
            tokio::time::sleep(Duration::from_millis(20)).await;
        }
        // the responder was still sending when the buffer went
        let at = sent.load(Ordering::SeqCst);
        tokio::time::sleep(Duration::from_millis(200)).await;
        assert!(
            sent.load(Ordering::SeqCst) > at,
            "the responder kept sending"
        );
        stop.store(true, Ordering::SeqCst);
    }
}

/// `read_through_gap` on paused time: a fake read stands for the responder.
#[cfg(test)]
mod gap_tests {
    use super::*;
    use std::cell::Cell;
    use tokio::time::Instant;

    const BUDGET: Duration = Duration::from_secs(10);
    const PER_TRY: Duration = Duration::from_secs(5);

    fn timeout() -> ClientError {
        ClientError::new(Status::Timeout, "no reply")
    }

    /// A read in the route gap ends at once (a few ms) with no reply.
    async fn quick_no_reply() -> Result<u32> {
        tokio::time::sleep(Duration::from_millis(3)).await;
        Err(timeout())
    }

    #[tokio::test(start_paused = true)]
    async fn a_read_in_the_gap_is_sent_again_until_it_answers() {
        let start = Instant::now();
        let calls = Cell::new(0);
        let gap = Duration::from_millis(150);
        let r = read_through_gap(BUDGET, PER_TRY, true, |_| {
            calls.set(calls.get() + 1);
            async move {
                if start.elapsed() < gap {
                    quick_no_reply().await
                } else {
                    Ok(7)
                }
            }
        })
        .await;
        assert_eq!(r, Ok(7), "the answer after the gap, not an error");
        assert!(calls.get() > 2, "more than the two tries of before");
        assert!(start.elapsed() < gap + GAP_PAUSE_MAX + Duration::from_millis(10));
    }

    #[tokio::test(start_paused = true)]
    async fn a_token_that_goes_ends_the_reads() {
        let calls = Cell::new(0);
        let r: Result<u32> = read_through_gap(BUDGET, PER_TRY, true, |_| {
            calls.set(calls.get() + 1);
            async { Err(ClientError::new(Status::Disconnected, "gone")) }
        })
        .await;
        assert!(r.unwrap_err().is(Status::Disconnected));
        assert_eq!(calls.get(), 1);
    }

    #[tokio::test(start_paused = true)]
    async fn an_answer_is_final_also_a_refusal() {
        let calls = Cell::new(0);
        let r: Result<u32> = read_through_gap(BUDGET, PER_TRY, true, |_| {
            calls.set(calls.get() + 1);
            async { Err(ClientError::new(Status::PermissionDenied, "no")) }
        })
        .await;
        assert!(r.unwrap_err().is(Status::PermissionDenied));
        assert_eq!(calls.get(), 1);
    }

    #[tokio::test(start_paused = true)]
    async fn a_gap_that_never_ends_costs_the_budget_only() {
        let start = Instant::now();
        let calls = Cell::new(0);
        let r = read_through_gap(BUDGET, PER_TRY, true, |within| {
            calls.set(calls.get() + 1);
            assert!(within > Duration::ZERO && within <= PER_TRY);
            quick_no_reply()
        })
        .await;
        assert!(r.unwrap_err().is(Status::Timeout));
        assert!(start.elapsed() <= BUDGET, "{:?}", start.elapsed());
        assert!(start.elapsed() >= BUDGET - GAP_PAUSE_MAX - Duration::from_millis(10));
        // 25, 50, 100, then 200 ms pauses: bounded, about 50 reads in 10 s
        assert!(calls.get() < 60, "{}", calls.get());
    }

    /// A responder that is there but never answers: each try waits its
    /// timeout, two of them fill the budget (as before the gap reads).
    #[tokio::test(start_paused = true)]
    async fn a_silent_responder_gets_two_tries() {
        let start = Instant::now();
        let calls = Cell::new(0);
        let r: Result<u32> = read_through_gap(BUDGET, PER_TRY, true, |within| {
            calls.set(calls.get() + 1);
            async move {
                tokio::time::sleep(within).await;
                Err(timeout())
            }
        })
        .await;
        assert!(r.unwrap_err().is(Status::Timeout));
        assert_eq!(calls.get(), 2);
        assert_eq!(start.elapsed(), BUDGET);
    }

    /// Not under a link (no token proves a responder): two tries, so a key
    /// that no queryable serves fails at once.
    #[tokio::test(start_paused = true)]
    async fn without_a_token_two_tries() {
        let start = Instant::now();
        let calls = Cell::new(0);
        let r = read_through_gap(BUDGET, PER_TRY, false, |_| {
            calls.set(calls.get() + 1);
            quick_no_reply()
        })
        .await;
        assert!(r.unwrap_err().is(Status::Timeout));
        assert_eq!(calls.get(), 2);
        assert!(start.elapsed() < Duration::from_millis(10));
    }
}
