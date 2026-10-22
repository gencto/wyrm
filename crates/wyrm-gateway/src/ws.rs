//! WebSocket protocol: binary frames, each one canonical CBOR map.
//!
//! Client → gateway:
//! `{id: uint, op: tstr, key: tstr, value?, action?: tstr, args?, sub?: uint}`
//! with `op` one of `meta`, `children`, `list`, `subscribe`, `unsubscribe`,
//! `set`, `invoke`, `history`. `key` is a full node key (`wy/<site>/…`, no
//! suffix); `subscribe` takes a pattern (`*`, `**`). `unsubscribe` ends the
//! `list` or `subscribe` stream whose request id is `sub`. `history` takes
//! `args {from, to?, agg?, window?, limit?}` (spec 01 `~val?history=`) and
//! answers `result: [[t, v, q] | [t_start, v], …]`.
//!
//! Gateway → client:
//! * `{id, ok: true, result?}` / `{id, ok: false, error: {status, message}}`
//! * `{id, event: {type, …}}` for streams:
//!   * `list`: `refreshed {children: [{name, meta}]}`, `added|changed {name,
//!     meta}`, `removed|connected {name}`, `disconnected {name?}`;
//!   * `subscribe`: `sample {key, v, q, t, qual?}`, `removed {key}`;
//!   * `invoke`: `value {v}` for every result but the last, which is the
//!     `result` of the final `ok`;
//!   * `closed {}` when a stream ends on the Zenoh side.
//!
//! `meta` is the canonical `~meta` CBOR (spec 02) as a byte string, decoded
//! with the SDK's `NodeMeta` codec. `status` is a spec-04 status code.
//!
//! Every request is checked against the user's grants first (`list`/`meta`/
//! `children` ≥ list, `subscribe` ≥ read on some part of the pattern,
//! `history` ≥ read on the point, `set`
//! ≥ write, `invoke` ≥ read with the action's own level left to the
//! responder), then sent with a fresh `ptok`. Samples and children the user
//! may not see are dropped before they reach the socket.

use crate::http::{bearer, ApiError, AppState};
use crate::{AuditEvent, Gateway, Grants, Principal};
use axum::body::Bytes;
use axum::extract::ws::{CloseFrame, Message, WebSocket, WebSocketUpgrade};
use axum::extract::State;
use axum::http::{HeaderMap, Uri};
use axum::response::{IntoResponse, Response};
use futures_util::{SinkExt, StreamExt};
use std::collections::{BTreeMap, HashMap};
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::{mpsc, watch, Semaphore};
use tokio::task::JoinHandle;
use tracing::debug;
use wyrm_client::{Child, ClientError, ListEvent, ValEvent, WyrmClient};
use wyrm_core::codec::{from_slice, to_vec};
use wyrm_core::{Perm, Status, Value};
use zenoh::key_expr::keyexpr;

/// Largest client frame.
pub const MAX_FRAME: usize = 64 * 1024;
/// Open `list`/`subscribe` streams per connection.
pub const MAX_STREAMS: usize = 64;
/// One-shot requests in flight per connection.
pub const MAX_INFLIGHT: usize = 32;
const OUT_QUEUE: usize = 1024;
/// How often an open socket re-reads the user (revocation, role changes).
const RECHECK: Duration = Duration::from_secs(15);

enum Out {
    Frame(Value),
    Close(u16, &'static str),
}

/// `GET /api/ws?ticket=…` (single-use, from `POST /api/ws-ticket`) or with
/// `Authorization: Bearer <session>`. Sessions are never taken from the URL.
pub(crate) async fn upgrade(
    State(st): State<AppState>,
    uri: Uri,
    headers: HeaderMap,
    ws: WebSocketUpgrade,
) -> Response {
    let p = match query_ticket(&uri) {
        Some(t) => st.gw.redeem_ticket(&t),
        None => bearer(&headers).and_then(|t| st.gw.authenticate(&t)),
    };
    let Some(p) = p else {
        return ApiError::unauthenticated().into_response();
    };
    ws.max_message_size(MAX_FRAME)
        .max_frame_size(MAX_FRAME)
        .on_upgrade(move |sock| run(st, p, sock))
}

fn query_ticket(uri: &Uri) -> Option<String> {
    uri.query()?
        .split('&')
        .find_map(|kv| kv.strip_prefix("ticket="))
        .map(str::to_owned)
}

impl Conn {
    /// A flow deploy through the gateway (ADR 0008): the proofs are the
    /// user's own per-target tokens, signed here with the user's grants, so
    /// the engine checks the user's rights on every command target. Proofs
    /// sent by the client are replaced; a target the user has no grant on
    /// gets no proof and the engine refuses the deploy.
    fn add_flow_proofs(&self, c: &WyrmClient, args: &mut Value) {
        let Value::Map(m) = args else { return };
        let Some(def) = m.get("def") else { return };
        let Ok(targets) = wyrm_flow::command_targets(def, self.gw.site()) else {
            return; // the engine's compiler reports it
        };
        let proofs = targets
            .into_iter()
            .filter_map(|t| c.proof(&t).map(|p| (t, Value::Bytes(p))))
            .collect();
        m.insert("proofs".into(), Value::Map(proofs));
    }
}

struct Conn {
    gw: Arc<Gateway>,
    session: zenoh::Session,
    out: mpsc::Sender<Out>,
    grants: watch::Sender<Arc<Grants>>,
    inflight: Arc<Semaphore>,
}

struct Req {
    id: u64,
    op: String,
    key: String,
    value: Option<Value>,
    action: Option<String>,
    args: Option<Value>,
    sub: Option<u64>,
}

async fn run(st: AppState, p: Principal, socket: WebSocket) {
    let (mut sink, mut stream) = socket.split();
    let (out_tx, mut out_rx) = mpsc::channel::<Out>(OUT_QUEUE);
    let writer = tokio::spawn(async move {
        while let Some(o) = out_rx.recv().await {
            match o {
                Out::Frame(v) => {
                    let Ok(b) = to_vec(&v) else { continue };
                    if sink.send(Message::Binary(Bytes::from(b))).await.is_err() {
                        break;
                    }
                }
                Out::Close(code, reason) => {
                    let frame = CloseFrame {
                        code,
                        reason: reason.into(),
                    };
                    let _ = sink.send(Message::Close(Some(frame))).await;
                    break;
                }
            }
        }
        let _ = sink.close().await;
    });
    let conn = Arc::new(Conn {
        gw: st.gw.clone(),
        session: st.session.clone(),
        out: out_tx.clone(),
        grants: watch::channel(Arc::new(p.grants.clone())).0,
        inflight: Arc::new(Semaphore::new(MAX_INFLIGHT)),
    });
    let claims = p.claims.clone();
    let left = Duration::from_secs(claims.exp.saturating_sub(crate::session::now_s()));
    let expiry = tokio::time::sleep(left);
    tokio::pin!(expiry);
    let mut recheck = tokio::time::interval(RECHECK);
    recheck.tick().await;
    let mut stop = st.stop.clone();
    let mut streams: HashMap<u64, JoinHandle<()>> = HashMap::new();
    let close = loop {
        tokio::select! {
            msg = stream.next() => match msg {
                None | Some(Err(_)) | Some(Ok(Message::Close(_))) => break None,
                Some(Ok(Message::Binary(b))) => {
                    if !conn.handle(&p, &b, &mut streams).await {
                        break Some((4001, "session revoked"));
                    }
                }
                Some(Ok(Message::Text(_))) => {
                    conn.send(err_frame(0, Status::InvalidMessage.code(), "binary CBOR frames only")).await;
                }
                Some(Ok(_)) => {} // ping/pong: answered by the socket
            },
            _ = &mut expiry => break Some((4001, "session expired")),
            _ = recheck.tick() => match conn.gw.resolve(claims.clone()) {
                Some(np) => conn.update_grants(np.grants),
                None => break Some((4001, "session revoked")),
            },
            _ = stop.changed() => break Some((1001, "gateway stopping")),
        }
        streams.retain(|_, h| !h.is_finished());
    };
    for (_, h) in streams {
        h.abort();
    }
    if let Some((code, reason)) = close {
        let _ = out_tx.send(Out::Close(code, reason)).await;
    }
    drop(out_tx);
    drop(conn);
    let abort = writer.abort_handle();
    if tokio::time::timeout(Duration::from_secs(2), writer)
        .await
        .is_err()
    {
        abort.abort();
    }
    debug!(user = %p.name, "gateway: socket closed");
}

impl Conn {
    async fn send(&self, v: Value) {
        let _ = self.out.send(Out::Frame(v)).await;
    }

    fn update_grants(&self, g: Grants) {
        self.grants.send_if_modified(|cur| {
            if **cur == g {
                false
            } else {
                *cur = Arc::new(g);
                true
            }
        });
    }

    fn client(&self, p: &Principal) -> WyrmClient {
        WyrmClient::new(self.session.clone()).with_tokens(Arc::new(self.gw.tokens_for(p)))
    }

    fn deny(&self, p: &Principal, req: &Req) -> Value {
        self.gw.audit(AuditEvent::Denied {
            user: p.name.clone(),
            op: req.op.clone(),
            key: req.key.clone(),
        });
        err_frame(req.id, Status::PermissionDenied.code(), "permission denied")
    }

    /// Handle one frame. `false` = the session is no longer valid.
    async fn handle(
        self: &Arc<Self>,
        login: &Principal,
        bytes: &[u8],
        streams: &mut HashMap<u64, JoinHandle<()>>,
    ) -> bool {
        let req = match parse(bytes) {
            Ok(r) => r,
            Err((id, msg)) => {
                self.send(err_frame(id, Status::InvalidMessage.code(), &msg))
                    .await;
                return true;
            }
        };
        // Current roles and state of the user, not those at login.
        let Some(p) = self.gw.resolve(login.claims.clone()) else {
            self.send(err_frame(
                req.id,
                Status::PermissionDenied.code(),
                "session revoked",
            ))
            .await;
            return false;
        };
        self.update_grants(p.grants.clone());
        if req.op == "unsubscribe" {
            let reply = match req.sub.and_then(|s| streams.remove(&s)) {
                Some(h) => {
                    h.abort();
                    ok_frame(req.id, None)
                }
                None => err_frame(req.id, Status::NotFound.code(), "no such stream"),
            };
            self.send(reply).await;
            return true;
        }
        let pattern = req.op == "subscribe";
        // A downstream site (ADR 0007): read only, checked as the own site.
        if let Some(d) = self.gw.read_site_of(&req.key) {
            if !matches!(
                req.op.as_str(),
                "meta" | "children" | "list" | "subscribe" | "history"
            ) {
                self.send(err_frame(
                    req.id,
                    Status::PermissionDenied.code(),
                    &format!("{d} is a downstream site: read only"),
                ))
                .await;
                return true;
            }
        }
        let own = self.gw.as_own(&req.key);
        if let Err(msg) = check_key(self.gw.site(), &own, pattern) {
            self.send(err_frame(req.id, Status::InvalidParameter.code(), &msg))
                .await;
            return true;
        }
        let allowed = match req.op.as_str() {
            "meta" | "children" | "list" => p.grants.perm(&format!("{own}/~meta")) >= Perm::List,
            "subscribe" => p.grants.any(&format!("{own}/~val"), Perm::Read),
            // as reading the point's value (spec 05 0.1.10)
            "history" => p.grants.perm(&format!("{own}/~val")) >= Perm::Read,
            "set" => p.grants.perm(&format!("{own}/~set")) >= Perm::Write,
            "invoke" => match req.action.as_deref() {
                Some(a) if wyrm_core::keyspace::validate_segment(a).is_ok() => {
                    p.grants.perm(&format!("{own}/~act/{a}")) >= Perm::Read
                }
                _ => {
                    self.send(err_frame(
                        req.id,
                        Status::InvalidParameter.code(),
                        "action: valid segment required",
                    ))
                    .await;
                    return true;
                }
            },
            other => {
                self.send(err_frame(
                    req.id,
                    Status::InvalidParameter.code(),
                    &format!("unknown op {other:?}"),
                ))
                .await;
                return true;
            }
        };
        if !allowed {
            self.send(self.deny(&p, &req)).await;
            return true;
        }
        if matches!(req.op.as_str(), "list" | "subscribe") {
            if streams.contains_key(&req.id) {
                self.send(err_frame(
                    req.id,
                    Status::InvalidParameter.code(),
                    "id of an open stream",
                ))
                .await;
                return true;
            }
            if streams.len() >= MAX_STREAMS {
                self.send(err_frame(req.id, Status::Busy.code(), "too many streams"))
                    .await;
                return true;
            }
            let me = self.clone();
            let id = req.id;
            let h = if pattern {
                tokio::spawn(async move { me.subscribe(p, req).await })
            } else {
                tokio::spawn(async move { me.list(p, req).await })
            };
            streams.insert(id, h);
            return true;
        }
        let Ok(permit) = self.inflight.clone().try_acquire_owned() else {
            self.send(err_frame(req.id, Status::Busy.code(), "too many requests"))
                .await;
            return true;
        };
        let me = self.clone();
        tokio::spawn(async move {
            let _permit = permit;
            me.one_shot(p, req).await;
        });
        true
    }

    async fn one_shot(&self, p: Principal, req: Req) {
        let c = self.client(&p);
        let id = req.id;
        let frame = match req.op.as_str() {
            "meta" => match c.meta(&req.key).await {
                Ok(m) => ok_frame(id, Some(meta_bytes(&m))),
                Err(e) => client_err(id, &e),
            },
            "history" => {
                let q = wyrm_client::HistoryQuery::from_args(req.args.as_ref());
                match c.history(&req.key, &q).await {
                    Ok(rows) => ok_frame(id, Some(wyrm_client::history_value(rows))),
                    Err(e) => client_err(id, &e),
                }
            }
            "children" => match c.children(&req.key).await {
                Ok(kids) => {
                    let g = self.grants.borrow().clone();
                    let kids = kids
                        .iter()
                        .filter(|k| visible_child(&g, &self.gw.as_own(&req.key), &k.name))
                        .map(child_value)
                        .collect();
                    ok_frame(id, Some(Value::Array(kids)))
                }
                Err(e) => client_err(id, &e),
            },
            "set" => match req.value {
                None => err_frame(id, Status::InvalidParameter.code(), "value required"),
                Some(v) => match c.set(&req.key, v).await {
                    Ok(()) => ok_frame(id, None),
                    Err(e) => client_err(id, &e),
                },
            },
            "invoke" => {
                let action = req.action.unwrap_or_default();
                let mut args = req.args.unwrap_or_else(|| Value::Map(BTreeMap::new()));
                // spec 05: the action's `timeout_ms` overrides the default
                // wait (installs fetch and unpack for minutes).
                let c = match action_timeout(&c, &req.key, &action).await {
                    Some(t) => c.with_timeout(t),
                    None => c,
                };
                if action == "deploy" && req.key == format!("wy/{}/flows", self.gw.site()) {
                    self.add_flow_proofs(&c, &mut args);
                }
                match c.invoke(&req.key, &action, args).await {
                    Err(e) => client_err(id, &e),
                    Ok(mut s) => {
                        let mut last: Option<Value> = None;
                        let mut failed = None;
                        while let Some(item) = s.next().await {
                            match item {
                                Ok(None) => {}
                                Ok(Some(v)) => {
                                    if let Some(prev) = last.replace(v) {
                                        self.send(event_frame(id, "value", [("v", prev)])).await;
                                    }
                                }
                                Err(e) => {
                                    failed = Some(e);
                                    break;
                                }
                            }
                        }
                        match failed {
                            Some(e) => client_err(id, &e),
                            None => ok_frame(id, last),
                        }
                    }
                }
            }
            _ => err_frame(id, Status::InvalidParameter.code(), "unknown op"),
        };
        self.send(frame).await;
    }

    async fn list(&self, p: Principal, req: Req) {
        let id = req.id;
        let mut s = match self.client(&p).list(&req.key).await {
            Ok(s) => s,
            Err(e) => return self.send(client_err(id, &e)).await,
        };
        self.send(ok_frame(id, None)).await;
        let grants = self.grants.subscribe();
        while let Some(ev) = s.next().await {
            let g = grants.borrow().clone();
            let parent = self.gw.as_own(&req.key);
            let see = |name: &str| visible_child(&g, &parent, name);
            let ev = match ev {
                ListEvent::Refreshed(kids) => {
                    let kids = kids
                        .iter()
                        .filter(|k| see(&k.name))
                        .map(child_value)
                        .collect();
                    event_frame(id, "refreshed", [("children", Value::Array(kids))])
                }
                ListEvent::Added(c) if see(&c.name) => event_frame(id, "added", child_fields(&c)),
                ListEvent::Changed(c) if see(&c.name) => {
                    event_frame(id, "changed", child_fields(&c))
                }
                ListEvent::Removed(n) if see(&n) => {
                    event_frame(id, "removed", [("name", Value::Str(n))])
                }
                ListEvent::Connected(n) if see(&n) => {
                    event_frame(id, "connected", [("name", Value::Str(n))])
                }
                ListEvent::Disconnected(None) => event_frame(id, "disconnected", []),
                ListEvent::Disconnected(Some(n)) if see(&n) => {
                    event_frame(id, "disconnected", [("name", Value::Str(n))])
                }
                _ => continue,
            };
            // ~meta is DataHigh + Block: wait for room, never drop.
            if self.out.send(Out::Frame(ev)).await.is_err() {
                return;
            }
        }
        self.send(event_frame(id, "closed", [])).await;
    }

    async fn subscribe(&self, p: Principal, req: Req) {
        let id = req.id;
        let mut s = match self.client(&p).subscribe(&req.key).await {
            Ok(s) => s,
            Err(e) => return self.send(client_err(id, &e)).await,
        };
        self.send(ok_frame(id, None)).await;
        let grants = self.grants.subscribe();
        while let Some(ev) = s.next().await {
            let (key, ev) = match ev {
                ValEvent::Sample { key, sample, qual } => {
                    let mut f = vec![
                        ("key", Value::Str(key.clone())),
                        ("v", sample.v),
                        ("q", Value::from(sample.q.name())),
                        ("t", Value::UInt(sample.t)),
                    ];
                    if let Some(q) = qual {
                        f.push(("qual", Value::Str(q)));
                    }
                    let ev = event_frame(id, "sample", f);
                    (key, ev)
                }
                ValEvent::Removed(key) => {
                    let ev = event_frame(id, "removed", [("key", Value::Str(key.clone()))]);
                    (key, ev)
                }
            };
            // Per-point filter: the first grant matching this very key.
            if grants
                .borrow()
                .perm(&format!("{}/~val", self.gw.as_own(&key)))
                < Perm::Read
            {
                continue;
            }
            // ~val is Data + Drop: a slow socket loses samples, not memory.
            if let Err(mpsc::error::TrySendError::Closed(_)) = self.out.try_send(Out::Frame(ev)) {
                return;
            }
        }
        self.send(event_frame(id, "closed", [])).await;
    }
}

fn visible_child(g: &Grants, parent: &str, name: &str) -> bool {
    g.perm(&format!("{parent}/{name}/~meta")) >= Perm::List
}

/// `wy/<site>` or below; a valid key expression; no `~` segments; no
/// wildcards unless `pattern`.
/// Longest wait the gateway gives an action (its `timeout_ms`).
const MAX_ACTION_WAIT: Duration = Duration::from_secs(180);

/// The action's declared `timeout_ms` (plus a margin for the reply), at
/// most [`MAX_ACTION_WAIT`]; `None`: the client default.
async fn action_timeout(c: &WyrmClient, key: &str, action: &str) -> Option<Duration> {
    let m = c.meta_expanded(key).await.ok()?;
    let ms = m.actions.as_ref()?.get(action)?.timeout_ms?;
    Some((Duration::from_millis(ms.into()) + Duration::from_secs(5)).min(MAX_ACTION_WAIT))
}

pub(crate) fn check_key(site: &str, key: &str, pattern: bool) -> Result<(), String> {
    let root = format!("wy/{site}");
    if key != root && !key.starts_with(&format!("{root}/")) {
        return Err(format!("key must be under {root}"));
    }
    keyexpr::new(key).map_err(|e| format!("key: {e}"))?;
    for seg in key.split('/') {
        if seg.starts_with('~') {
            return Err("key must not carry a suffix".into());
        }
        if !pattern && (seg.contains('*') || seg.contains('$')) {
            return Err("wildcards only in subscribe".into());
        }
    }
    Ok(())
}

fn parse(bytes: &[u8]) -> Result<Req, (u64, String)> {
    let v: Value = from_slice(bytes).map_err(|e| (0, format!("frame: {e}")))?;
    let Value::Map(mut m) = v else {
        return Err((0, "frame must be a map".into()));
    };
    let Some(Value::UInt(id)) = m.get("id").cloned() else {
        return Err((0, "id: uint required".into()));
    };
    let text = |m: &mut BTreeMap<String, Value>, k: &str| match m.remove(k) {
        None => Ok(None),
        Some(Value::Str(s)) => Ok(Some(s)),
        Some(_) => Err((id, format!("{k}: text required"))),
    };
    let op = text(&mut m, "op")?.ok_or((id, "op required".to_owned()))?;
    let key = text(&mut m, "key")?.unwrap_or_default();
    if op != "unsubscribe" && key.is_empty() {
        return Err((id, "key required".into()));
    }
    let action = text(&mut m, "action")?;
    let sub = match m.remove("sub") {
        None => None,
        Some(Value::UInt(s)) => Some(s),
        Some(_) => return Err((id, "sub: uint required".into())),
    };
    Ok(Req {
        id,
        op,
        key,
        value: m.remove("value"),
        action,
        args: m.remove("args"),
        sub,
    })
}

fn map<const N: usize>(fields: [(&str, Value); N]) -> Value {
    Value::Map(fields.into_iter().map(|(k, v)| (k.to_owned(), v)).collect())
}

fn ok_frame(id: u64, result: Option<Value>) -> Value {
    let mut m = BTreeMap::from([
        ("id".to_owned(), Value::UInt(id)),
        ("ok".to_owned(), Value::Bool(true)),
    ]);
    if let Some(r) = result {
        m.insert("result".into(), r);
    }
    Value::Map(m)
}

fn err_frame(id: u64, status: u8, message: &str) -> Value {
    map([
        ("id", Value::UInt(id)),
        ("ok", Value::Bool(false)),
        (
            "error",
            map([
                ("status", Value::UInt(status.into())),
                ("message", Value::from(message)),
            ]),
        ),
    ])
}

fn client_err(id: u64, e: &ClientError) -> Value {
    err_frame(id, e.status.code(), &e.message)
}

fn event_frame<'a>(id: u64, ty: &str, fields: impl IntoIterator<Item = (&'a str, Value)>) -> Value {
    let mut ev: BTreeMap<String, Value> =
        fields.into_iter().map(|(k, v)| (k.to_owned(), v)).collect();
    ev.insert("type".into(), Value::from(ty));
    map([("id", Value::UInt(id)), ("event", Value::Map(ev))])
}

fn meta_bytes(m: &wyrm_core::NodeMeta) -> Value {
    Value::Bytes(to_vec(m).unwrap_or_default())
}

fn child_fields(c: &Child) -> [(&'static str, Value); 2] {
    [
        ("name", Value::Str(c.name.clone())),
        ("meta", meta_bytes(&c.meta)),
    ]
}

fn child_value(c: &Child) -> Value {
    map(child_fields(c))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn keys() {
        assert!(check_key("s", "wy/s/down/mock/p0", false).is_ok());
        assert!(check_key("s", "wy/s", false).is_ok());
        assert!(check_key("s", "wy/other/down", false).is_err());
        assert!(check_key("s", "wy/sx/down", false).is_err());
        assert!(check_key("s", "wy/s/down/mock/p0/~set", false).is_err());
        assert!(check_key("s", "wy/s/down/**", false).is_err());
        assert!(check_key("s", "wy/s/down/**", true).is_ok());
        assert!(check_key("s", "wy/s/down//x", false).is_err());
    }

    #[test]
    fn frames_parse() {
        let f = to_vec(&map([
            ("id", Value::UInt(7)),
            ("op", Value::from("set")),
            ("key", Value::from("wy/s/down/m/p0")),
            ("value", Value::Float(1.5)),
        ]))
        .unwrap();
        let r = parse(&f).unwrap();
        assert_eq!((r.id, r.op.as_str()), (7, "set"));
        assert_eq!(r.value, Some(Value::Float(1.5)));
        let bad = to_vec(&map([("id", Value::UInt(3)), ("op", Value::from("meta"))])).unwrap();
        assert_eq!(parse(&bad).err().unwrap().0, 3);
        assert!(parse(b"\xff").is_err());
    }
}
