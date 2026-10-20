//! WYRM requester SDK. Spec: 05-methods.
//!
//! Node keys are full keys without suffix, e.g. `wy/plant-a/down/mock/g0/p0`.
//!
//! * [`WyrmClient::list`] — subscribes to `node/*/~meta` and liveliness
//!   *before* the snapshot `get`, so no change between the two is lost.
//! * [`WyrmClient::subscribe`] — subscribes to `pattern/~val`, then reads the
//!   stored values; per key, nothing older than what was already emitted.
//! * [`WyrmClient::set`] / [`WyrmClient::invoke`] — `get` on `~set` / `~act`
//!   with `InteractiveHigh + Block + express` (replies inherit the query QoS).

#![forbid(unsafe_code)]

mod streams;
pub mod tokens;

pub use streams::{EventStream, ListEvent, ValEvent};
pub use tokens::{SigningTokens, TokenSource};

use std::sync::Arc;
use std::time::Duration;
use tokio::sync::mpsc;
use wyrm_core::codec::{from_slice, to_vec};
use wyrm_core::keyspace::{self, SUFFIX_META, SUFFIX_SET};
use wyrm_core::status::StatusCode;
use wyrm_core::{Attachment, NodeMeta, SetRequest, Status, StatusGroup, Value};
use zenoh::handlers::FifoChannelHandler;
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
}

/// `wy/<site>/down/<link>` that owns `key`, if any.
pub fn owner_key(key: &str) -> Option<String> {
    let segs: Vec<&str> = key.splitn(5, '/').collect();
    (segs.len() >= 4 && segs[0] == keyspace::ROOT && segs[2] == "down").then(|| segs[..4].join("/"))
}

/// `wy/<site>/down` — its children are links, known from liveliness.
pub(crate) fn is_links_root(key: &str) -> bool {
    let segs: Vec<&str> = key.split('/').collect();
    segs.len() == 3 && segs[0] == keyspace::ROOT && segs[2] == "down"
}

fn suffixed(node: &str, suffix: &str) -> String {
    format!("{node}/{suffix}")
}

impl WyrmClient {
    pub fn new(session: Session) -> Self {
        Self {
            session,
            tokens: None,
            timeout: DEFAULT_TIMEOUT,
        }
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

    fn token_att(&self, key: &str) -> Attachment {
        Attachment {
            ptok: self.tokens.as_ref().and_then(|t| t.token(key)),
            ..Default::default()
        }
    }

    /// Raw `get`. `interactive` selects the `~set/~act` QoS.
    async fn query(
        &self,
        selector: &str,
        payload: Option<Vec<u8>>,
        att: Attachment,
        interactive: bool,
        timeout: Duration,
    ) -> Result<FifoChannelHandler<Reply>> {
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
        Ok(get.await?)
    }

    /// Exactly one reply expected; none → `timeout` or `disconnected`.
    async fn one(
        &self,
        selector: &str,
        payload: Option<Vec<u8>>,
        att: Attachment,
        interactive: bool,
    ) -> Result<Response> {
        let rx = self
            .query(selector, payload, att, interactive, self.timeout)
            .await?;
        match next_response(&rx).await {
            Some(r) => r?.check(),
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

    /// `get node/~meta` (full). Retries once with a `ptok` on `permission_denied`
    /// (restricted nodes) when a token source is set.
    pub async fn meta(&self, node: &str) -> Result<NodeMeta> {
        let r = self.meta_raw(node, "").await?;
        decode(&r.payload)
    }

    async fn meta_raw(&self, node: &str, params: &str) -> Result<Response> {
        let key = suffixed(node, SUFFIX_META);
        let sel = if params.is_empty() {
            key.clone()
        } else {
            format!("{key}?{params}")
        };
        match self.one(&sel, None, Attachment::default(), false).await {
            Err(e) if e.is(Status::PermissionDenied) && self.tokens.is_some() => {
                self.one(&sel, None, self.token_att(&key), false).await
            }
            r => r,
        }
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
    pub async fn children(&self, node: &str) -> Result<Vec<Child>> {
        if is_links_root(node) {
            return self.links(node).await;
        }
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

    /// Links under `wy/<site>/down`: liveliness tokens, then each root `~meta`.
    async fn links(&self, root: &str) -> Result<Vec<Child>> {
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
        let mut out = Vec::with_capacity(names.len());
        for name in names {
            let meta = self
                .meta(&format!("{root}/{name}"))
                .await
                .unwrap_or_default();
            out.push(Child { name, meta });
        }
        Ok(out)
    }

    /// Reactive `list`: first event is `Refreshed` with the snapshot, then
    /// `Added / Changed / Removed / Disconnected / Connected`.
    pub async fn list(&self, node: &str) -> Result<EventStream<ListEvent>> {
        streams::list(self.clone(), node.to_owned()).await
    }

    /// Reactive values for a node pattern (`…/mock/**`): stored values first,
    /// then live samples.
    pub async fn subscribe(&self, pattern: &str) -> Result<EventStream<ValEvent>> {
        streams::subscribe(self.clone(), pattern.to_owned()).await
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
        let payload = to_vec(&SetRequest { v: v.into() })
            .map_err(|e| ClientError::new(Status::InternalError, e.to_string()))?;
        self.one(&key, Some(payload), self.token_att(&key), true)
            .await
            .map(|_| ())
    }

    /// `invoke` returning every reply: one for a plain action, `seq`-ordered
    /// elements for a stream (the final `last = true` reply is not emitted
    /// unless it carries a value). Each reply must arrive within the client
    /// timeout of the previous one.
    pub async fn invoke(
        &self,
        node: &str,
        action: &str,
        args: Value,
    ) -> Result<EventStream<Result<Option<Value>>>> {
        let key = suffixed(node, &format!("~act/{action}"));
        let payload =
            to_vec(&args).map_err(|e| ClientError::new(Status::InternalError, e.to_string()))?;
        // The zenoh query lives long; idleness is bounded per reply below.
        let rx = self
            .query(
                &key,
                Some(payload),
                self.token_att(&key),
                true,
                Duration::from_secs(3600),
            )
            .await?;
        let (tx, out) = mpsc::channel(64);
        let idle = self.timeout;
        let me = self.clone();
        tokio::spawn(async move {
            let mut got_any = false;
            loop {
                let r = match tokio::time::timeout(idle, next_response(&rx)).await {
                    Err(_) => Some(Err(ClientError::new(Status::Timeout, "no reply"))),
                    Ok(None) if !got_any => Some(Err(me.no_reply(&key).await)),
                    Ok(None) => None,
                    Ok(Some(r)) => Some(r.and_then(Response::check)),
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
        Ok(EventStream::new(out))
    }

    /// `invoke` of a plain action: its single result.
    pub async fn invoke_one(&self, node: &str, action: &str, args: Value) -> Result<Option<Value>> {
        let mut s = self.invoke(node, action, args).await?;
        s.next().await.unwrap_or(Ok(None))
    }
}

pub(crate) async fn next_response(rx: &FifoChannelHandler<Reply>) -> Option<Result<Response>> {
    let reply = rx.recv_async().await.ok()?;
    Some(match reply.result() {
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
    })
}

pub(crate) fn decode<T: for<'b> minicbor::Decode<'b, ()>>(b: &[u8]) -> Result<T> {
    from_slice(b).map_err(|e| ClientError::new(Status::InvalidMessage, e.to_string()))
}
