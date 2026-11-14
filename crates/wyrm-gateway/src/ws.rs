//! WebSocket protocol: binary frames, each one canonical CBOR map.
//!
//! Client → gateway:
//! `{id: uint, op: tstr, key: tstr, value?, action?: tstr, args?, sub?: uint, suffix?: tstr}`
//! with `op` one of `meta`, `children`, `list`, `subscribe`, `unsubscribe`,
//! `set`, `invoke`, `check`, `history`, `doc`. `key` is a full node
//! key (`wy/<site>/…`, no suffix); `subscribe` takes a pattern (`*`, `**`).
//! `unsubscribe` ends the `list` or `subscribe` stream whose request id is
//! `sub`. `history` takes `args {from, to?, agg?, window?, limit?}` (spec 01
//! `~val?history=`) and answers `result: [[t, v, q] | [t_start, v], …]`.
//!
//! `doc` reads a document of the node: `suffix` is `~state` or `~def` (spec
//! 01), `result` is the document's CBOR value, at most
//! [`crate::approve::MAX_DOC`] bytes (`resource_exhausted` beyond). A gateway
//! older than the op answers `invalid_parameter` with `unknown op`.
//!
//! `invoke` of `approve` on an agent task (`…/downstream/<agent>/tasks/<id>`)
//! with `args {steps: [<n>, …], plan: <plan hash>}`: the gateway reads the
//! stored plan and signs one token per named step with the user's rights
//! ([`crate::approve`], ADR 0049); the link gets `{approvals, plan}`. With
//! `approvals` in the arguments the call goes through as it is.
//!
//! Gateway → client:
//! * `{id, ok: true, result?}` / `{id, ok: false, error: {status, message}}`
//! * `{id, event: {type, …}}` for streams:
//!   * `list`: `refreshed {children: [{name, meta}]}`, `added|changed {name,
//!     meta}`, `removed|connected {name}`, `disconnected {name?}`;
//!   * `subscribe`: `sample {key, v, q, t, qual?}`, `removed {key}`;
//!   * `invoke`: `value {v}` for every result but the last, which is the
//!     `result` of the final `ok`;
//!   * `closed {}` when a stream ends on the Zenoh side; a `subscribe` that
//!     hits a client limit (more than `wyrm_client::MAX_STREAM_KEYS` keys, a
//!     socket that does not catch up) ends with `{id, ok: false, error}`
//!     (`resource_exhausted`) instead.
//!
//! `meta` is the canonical `~meta` CBOR (spec 02) as a byte string, decoded
//! with the SDK's `NodeMeta` codec. `status` is a spec-04 status code.
//!
//! Every request is checked against the user's grants first (`list`/`meta`/
//! `children` ≥ list, `subscribe` ≥ read on some part of the pattern,
//! `history` ≥ read on the point, `set`
//! ≥ write, `invoke` ≥ read with the action's own level left to the
//! responder, `doc` ≥ list on the node and on the document's key, with a
//! restricted node left to the responder; an `approve {steps}` also needs
//! the level of every step it signs), then sent with a fresh `ptok`. Samples and children the user
//! may not see are dropped before they reach the socket.

use crate::http::{bearer, ApiError, AppState};
use crate::{AuditEvent, Gateway, Grants, Principal, Refusal};
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
    let Some(slot) = st.gw.socket_slot(&p.name) else {
        return ApiError::new(
            axum::http::StatusCode::TOO_MANY_REQUESTS,
            Status::RateLimited,
            "too many open sockets for this user",
        )
        .into_response();
    };
    ws.max_message_size(MAX_FRAME)
        .max_frame_size(MAX_FRAME)
        .on_upgrade(move |sock| async move {
            run(st, p, sock).await;
            drop(slot);
        })
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
    /// gets no proof and the engine refuses the deploy. `site` is the site the flow is
    /// deployed on (this one or a downstream site, ADR 0018): its targets are that site's.
    fn add_flow_proofs(&self, c: &WyrmClient, site: &str, args: &mut Value) {
        let Value::Map(m) = args else { return };
        let Some(def) = m.get("def") else { return };
        let Ok(targets) = wyrm_flow::command_targets(def, site) else {
            return; // the engine's compiler reports it
        };
        let proofs = targets
            .into_iter()
            .filter_map(|t| c.proof(&t).map(|p| (t, Value::Bytes(p))))
            .collect();
        m.insert("proofs".into(), Value::Map(proofs));
    }
}

impl Conn {
    /// `approve {steps, plan}` of an agent task from a user (ADR 0049 §2, the rule in
    /// [`crate::approve`]): the plan is read from the link with the user's own token, the
    /// user's grants are checked for every step the client named, and only then is one
    /// token signed per step. The arguments the link gets: `{approvals: {"<n>": token},
    /// plan}`. A token made here goes to the link alone, never to the client or a log.
    async fn approval_args(
        &self,
        p: &Principal,
        c: &WyrmClient,
        key: &str,
        args: &Value,
    ) -> Result<Value, ClientError> {
        use crate::approve::{Ask, Plan, MAX_DOC};
        // a step the user may not approve is the gateway's own refusal: audited as one
        let refused = |r: Refusal| {
            if r.status == Status::PermissionDenied {
                self.gw.audit(AuditEvent::Denied {
                    user: p.name.clone(),
                    op: "approve".into(),
                    key: key.to_owned(),
                });
            }
            ClientError::new(r.status, r.message)
        };
        // A person's own session and a task of an agent link of this site, by the broker's
        // registry: an MCP client approves nothing, and no other link that serves a
        // plan-shaped document gets a token of the user.
        crate::approve::gate(self.human, self.gw.agent_task(key).is_some()).map_err(refused)?;
        let ask = Ask::parse(args).map_err(refused)?;
        let site = key.split('/').nth(1).unwrap_or_default();
        let doc = c.doc(key, "~state").await?;
        if doc.len() > MAX_DOC {
            return Err(ClientError::new(
                Status::ResourceExhausted,
                "the task record is larger than the gateway reads",
            ));
        }
        let doc: Value = from_slice(&doc)
            .map_err(|_| ClientError::new(Status::InvalidMessage, "the task record is not CBOR"))?;
        let plan = Plan::parse(&doc, site).map_err(refused)?;
        let sign = plan
            .select(&ask, |k| p.grants.perm(&self.gw.as_own(k)))
            .map_err(refused)?;
        let tokens = self.gw.tokens_for(p);
        let mut approvals = BTreeMap::new();
        for (n, r) in &sign {
            let tok = tokens.approval(&r.key, r.level, r.body).ok_or_else(|| {
                refused(Refusal::new(
                    Status::PermissionDenied,
                    format!("step {n}: you have no right on {}", r.key),
                ))
            })?;
            approvals.insert(n.to_string(), Value::Bytes(tok));
        }
        self.gw.audit(AuditEvent::Approved {
            user: p.name.clone(),
            task: key.to_owned(),
            steps: sign.iter().map(|(_, r)| r.key.clone()).collect(),
            skipped: plan.left_out(&ask.steps),
        });
        Ok(map([
            ("approvals", Value::Map(approvals)),
            ("plan", Value::Str(plan.hash)),
        ]))
    }
}

struct Conn {
    gw: Arc<Gateway>,
    session: zenoh::Session,
    out: mpsc::Sender<Out>,
    grants: watch::Sender<Arc<Grants>>,
    inflight: Arc<Semaphore>,
    /// A person's own login (see [`serve_frames`]).
    human: bool,
}

struct Req {
    id: u64,
    op: String,
    key: String,
    value: Option<Value>,
    action: Option<String>,
    args: Option<Value>,
    sub: Option<u64>,
    /// `doc`: which document (`~state`, `~def`).
    suffix: Option<String>,
}

/// One frame from a client, whatever carries it.
pub(crate) enum WsIn {
    Binary(Vec<u8>),
    Text,
    Close,
    /// Ping, pong: answered by the transport.
    Other,
}

/// One frame to a client.
pub(crate) enum WsOut {
    Binary(Vec<u8>),
    Close(u16, &'static str),
}

async fn run(st: AppState, p: Principal, socket: WebSocket) {
    let (sink, stream) = socket.split();
    let sink = sink.with(|o: WsOut| {
        futures_util::future::ready(Ok::<_, axum::Error>(match o {
            WsOut::Binary(b) => Message::Binary(Bytes::from(b)),
            WsOut::Close(code, reason) => Message::Close(Some(CloseFrame {
                code,
                reason: reason.into(),
            })),
        }))
    });
    let stream = stream.map(|m| match m {
        Ok(Message::Binary(b)) => WsIn::Binary(b.to_vec()),
        Ok(Message::Text(_)) => WsIn::Text,
        Ok(Message::Close(_)) | Err(_) => WsIn::Close,
        Ok(_) => WsIn::Other,
    });
    serve_frames(st, p, true, stream, sink).await;
}

/// The protocol over any frame transport: an axum socket, or the in-process
/// pipe of the MCP endpoint (ADR 0041).
///
/// `human`: the session is a person's own login, not an MCP client's token: only such a
/// session gets approvals of an agent's plan signed (ADR 0049).
pub(crate) async fn serve_frames<St, Si>(
    st: AppState,
    p: Principal,
    human: bool,
    stream: St,
    sink: Si,
) where
    St: futures_util::Stream<Item = WsIn> + Send + Unpin,
    Si: futures_util::Sink<WsOut> + Send + Unpin + 'static,
{
    let mut stream = stream;
    let mut sink = sink;
    let (out_tx, mut out_rx) = mpsc::channel::<Out>(OUT_QUEUE);
    let writer = tokio::spawn(async move {
        while let Some(o) = out_rx.recv().await {
            match o {
                Out::Frame(v) => {
                    let Ok(b) = to_vec(&v) else { continue };
                    if sink.send(WsOut::Binary(b)).await.is_err() {
                        break;
                    }
                }
                Out::Close(code, reason) => {
                    let _ = sink.send(WsOut::Close(code, reason)).await;
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
        human,
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
                None | Some(WsIn::Close) => break None,
                Some(WsIn::Binary(b)) => {
                    if !conn.handle(&p, &b, &mut streams).await {
                        break Some((4001, "session revoked"));
                    }
                }
                Some(WsIn::Text) => {
                    conn.send(err_frame(0, Status::InvalidMessage.code(), "binary CBOR frames only")).await;
                }
                Some(WsIn::Other) => {}
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
        // one budget for all of the user's sockets (review GW-2); closing a stream is free
        if req.op != "unsubscribe" && !self.gw.request_allowed(&p.name) {
            self.send(err_frame(
                req.id,
                Status::RateLimited.code(),
                "too many requests",
            ))
            .await;
            return true;
        }
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
        // A downstream site is checked as the own site (ADR 0007); a write
        // carries a token for it, and it decides too (ADR 0018).
        let own = self.gw.as_own(&req.key);
        if let Err(msg) = check_key(self.gw.site(), &own, pattern) {
            self.send(err_frame(req.id, Status::InvalidParameter.code(), &msg))
                .await;
            return true;
        }
        let allowed = match req.op.as_str() {
            "meta" | "children" | "list" => p.grants.perm(&format!("{own}/~meta")) >= Perm::List,
            "subscribe" => p.grants.any(&format!("{own}/~val"), Perm::Read),
            // as reading the point's value (spec 05 0.1.10); at a watch
            // key, as reading the point it records (ADR 0020, the DSA
            // double check), else as its Get History
            "history"
                if req
                    .key
                    .starts_with(&format!("wy/{}/sys/history/", self.gw.site())) =>
            {
                let sites = self.gw.sites.borrow().clone();
                match crate::overlay::point_of(&sites, &req.key) {
                    Some(point) => {
                        p.grants.perm(&format!("{}/~val", self.gw.as_own(point))) >= Perm::Read
                    }
                    None => p.grants.perm(&format!("{own}/~act/get_history")) >= Perm::Config,
                }
            }
            "history" => p.grants.perm(&format!("{own}/~val")) >= Perm::Read,
            "set" => p.grants.perm(&format!("{own}/~set")) >= Perm::Write,
            // a document of the node: as `list` on it, and the token the responder gets is
            // for the document's own key (a restricted node asks `list` there)
            "doc" => match req.suffix.as_deref() {
                Some(s @ ("~state" | "~def")) => {
                    p.grants.perm(&format!("{own}/~meta")) >= Perm::List
                        && p.grants.perm(&format!("{own}/{s}")) >= Perm::List
                }
                _ => {
                    self.send(err_frame(
                        req.id,
                        Status::InvalidParameter.code(),
                        "suffix: ~state or ~def required",
                    ))
                    .await;
                    return true;
                }
            },
            "invoke" | "check" => match req.action.as_deref() {
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

    /// `step_up: config` (ADR 0050 §1.3): a `set` on a point writable at `config`, or an
    /// `invoke` of an action at `config`, by a session not confirmed in the last 5 minutes
    /// is refused with `confirm_required`. Only for a user who holds `config` there (anyone
    /// else is refused by the responder anyway); a node whose `~meta` cannot be read counts
    /// as `config`.
    async fn needs_step_up(&self, p: &Principal, c: &WyrmClient, req: &Req) -> Option<Value> {
        if !self.gw.step_up_on() || self.gw.confirmed(p) {
            return None;
        }
        let own = self.gw.as_own(&req.key);
        let at_config = match req.op.as_str() {
            "set" if p.grants.perm(&format!("{own}/~set")) >= Perm::Config => {
                match c.meta(&req.key).await {
                    Ok(m) => m.writable == Some(wyrm_core::meta::Writable::Config),
                    Err(_) => true,
                }
            }
            "invoke" => {
                let action = req.action.as_deref().unwrap_or_default();
                if p.grants.perm(&format!("{own}/~act/{action}")) < Perm::Config {
                    return None;
                }
                match c.meta_expanded(&req.key).await {
                    Ok(m) => m
                        .actions
                        .as_ref()
                        .and_then(|a| a.get(action))
                        .is_none_or(|a| a.level.unwrap_or(Perm::Read) >= Perm::Config),
                    Err(_) => true,
                }
            }
            _ => false,
        };
        if !at_config {
            return None;
        }
        let mut what = BTreeMap::from([
            ("op".to_owned(), Value::from(req.op.as_str())),
            ("key".to_owned(), Value::from(req.key.as_str())),
        ]);
        for (k, v) in [
            ("value", req.value.clone()),
            ("action", req.action.clone().map(Value::Str)),
            ("args", req.args.clone()),
        ] {
            if let Some(v) = v {
                what.insert(k.to_owned(), v);
            }
        }
        let refused = self.gw.step_up(p, &Value::Map(what)).err()?;
        self.gw.audit(AuditEvent::Denied {
            user: p.name.clone(),
            op: "confirm_required".into(),
            key: req.key.clone(),
        });
        Some(refused_frame(req.id, refused))
    }

    async fn one_shot(&self, p: Principal, req: Req) {
        let c = self.client(&p);
        let id = req.id;
        if let Some(frame) = self.needs_step_up(&p, &c, &req).await {
            return self.send(frame).await;
        }
        let frame = match req.op.as_str() {
            "meta" => match c.meta(&req.key).await {
                Ok(mut m) => {
                    crate::overlay::lay(&self.gw.sites.borrow(), &req.key, &mut m);
                    ok_frame(id, Some(meta_bytes(&m)))
                }
                Err(e) => client_err(id, &e),
            },
            "history" => {
                let mut q = wyrm_client::HistoryQuery::from_args(req.args.as_ref());
                // the server decides how much one request may ask for (review GW-2)
                q.limit = Some(
                    q.limit
                        .unwrap_or(crate::HISTORY_LIMIT)
                        .min(crate::HISTORY_LIMIT),
                );
                match c.history(&req.key, &q).await {
                    Ok(rows) => ok_frame(id, Some(wyrm_client::history_value(rows))),
                    Err(e) => client_err(id, &e),
                }
            }
            "children" => match c.children(&req.key).await {
                Ok(kids) => {
                    let g = self.grants.borrow().clone();
                    let sites = self.gw.sites.borrow().clone();
                    let kids = kids
                        .into_iter()
                        .filter(|k| visible_child(&g, &self.gw.as_own(&req.key), &k.name))
                        .map(|k| child_value(&laid(&sites, &req.key, k)))
                        .collect();
                    ok_frame(id, Some(Value::Array(kids)))
                }
                Err(e) => client_err(id, &e),
            },
            "doc" => {
                match c
                    .doc(&req.key, req.suffix.as_deref().unwrap_or_default())
                    .await
                {
                    Ok(b) if b.len() > crate::approve::MAX_DOC => err_frame(
                        id,
                        Status::ResourceExhausted.code(),
                        "the document is larger than the gateway returns",
                    ),
                    Ok(b) => match from_slice::<Value>(&b) {
                        Ok(v) => ok_frame(id, Some(v)),
                        Err(_) => err_frame(
                            id,
                            Status::InvalidMessage.code(),
                            "the document is not canonical CBOR",
                        ),
                    },
                    Err(e) => client_err(id, &e),
                }
            }
            "set" => match req.value {
                None => err_frame(id, Status::InvalidParameter.code(), "value required"),
                Some(v) => match c.set(&req.key, v).await {
                    Ok(()) => ok_frame(id, None),
                    Err(e) => client_err(id, &e),
                },
            },
            // spec 05 0.2.33: the responder checks the call and does nothing; the caller
            // sends it only where the responder's root says `attr.check`
            "check" => {
                let action = req.action.unwrap_or_default();
                let args = req.args.unwrap_or_else(|| Value::Map(BTreeMap::new()));
                match c.invoke_check(&req.key, &action, args).await {
                    Ok(()) => ok_frame(id, None),
                    Err(e) => client_err(id, &e),
                }
            }
            "invoke" => {
                let action = req.action.unwrap_or_default();
                let mut args = req.args.unwrap_or_else(|| Value::Map(BTreeMap::new()));
                // spec 05: the action's `timeout_ms` overrides the default
                // wait (installs fetch and unpack for minutes).
                let c = match action_timeout(&c, &req.key, &action).await {
                    Some(t) => c.with_timeout(t),
                    None => c,
                };
                // a deploy here or on a site below (ADR 0033: a downstream deploy got no proofs)
                if action == "deploy"
                    && self.gw.as_own(&req.key) == format!("wy/{}/dataflows", self.gw.site())
                {
                    let site = req.key.split('/').nth(1).unwrap_or_default().to_owned();
                    self.add_flow_proofs(&c, &site, &mut args);
                }
                // a user approves steps of an agent's plan: the gateway signs them (ADR 0049)
                if action == "approve" && crate::approve::asks_for_tokens(&args) {
                    match self.approval_args(&p, &c, &req.key, &args).await {
                        Ok(signed) => args = signed,
                        Err(e) => return self.send(client_err(id, &e)).await,
                    }
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
        // this site's overlays (ADR 0020): laid on each child as sent, and a
        // change sends the children it touches again
        let mut sites_rx = self.gw.sites.subscribe();
        let mut sites = sites_rx.borrow_and_update().clone();
        let mut kids: BTreeMap<String, Child> = BTreeMap::new();
        loop {
            let ev = tokio::select! {
                ev = s.next() => match ev {
                    Some(ev) => ev,
                    None => break,
                },
                Ok(()) = sites_rx.changed() => {
                    let new = sites_rx.borrow_and_update().clone();
                    let g = grants.borrow().clone();
                    let parent = self.gw.as_own(&req.key);
                    for c in kids.values() {
                        let k = format!("{}/{}", req.key, c.name);
                        if sites.get(&k) != new.get(&k) && visible_child(&g, &parent, &c.name) {
                            let ev = event_frame(id, "changed", child_fields(&laid(&new, &req.key, c.clone())));
                            if self.out.send(Out::Frame(ev)).await.is_err() {
                                return;
                            }
                        }
                    }
                    sites = new;
                    continue;
                }
            };
            match &ev {
                ListEvent::Refreshed(all) => {
                    kids = all.iter().map(|c| (c.name.clone(), c.clone())).collect();
                }
                ListEvent::Added(c) | ListEvent::Changed(c) => {
                    kids.insert(c.name.clone(), c.clone());
                }
                ListEvent::Removed(n) => {
                    kids.remove(n);
                }
                _ => {}
            }
            let g = grants.borrow().clone();
            let parent = self.gw.as_own(&req.key);
            let see = |name: &str| visible_child(&g, &parent, name);
            let lay = |c: Child| laid(&sites, &req.key, c);
            let ev = match ev {
                ListEvent::Refreshed(kids) => {
                    let kids = kids
                        .into_iter()
                        .filter(|k| see(&k.name))
                        .map(|k| child_value(&lay(k)))
                        .collect();
                    event_frame(id, "refreshed", [("children", Value::Array(kids))])
                }
                ListEvent::Added(c) if see(&c.name) => {
                    event_frame(id, "added", child_fields(&lay(c)))
                }
                ListEvent::Changed(c) if see(&c.name) => {
                    event_frame(id, "changed", child_fields(&lay(c)))
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
            // ~meta is DataHigh + Block: wait for room, never drop. Only this
            // task waits: the client stream holds `LIST_BUFFER` events and
            // beyond that sends a fresh `refreshed`, never holding up the session.
            if self.out.send(Out::Frame(ev)).await.is_err() {
                return;
            }
        }
        self.send(event_frame(id, "closed", [])).await;
    }

    async fn subscribe(&self, p: Principal, req: Req) {
        let id = req.id;
        // The read filter runs before the client stream buffers anything: a
        // point the user may not read takes no memory (security review). It
        // is checked again below, as grants can change while a value waits.
        let (gw, filter) = (self.gw.clone(), self.grants.subscribe());
        let readable = move |key: &str| {
            filter.borrow().perm(&format!("{}/~val", gw.as_own(key))) >= Perm::Read
        };
        let mut s = match self.client(&p).subscribe_filtered(&req.key, readable).await {
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
            // Wait for room: only this task waits. The client stream keeps
            // one pending value per key meanwhile (newest wins) and never
            // holds up the shared session, so a slow socket gets the latest
            // value of every point instead of losing some at random.
            if self.out.send(Out::Frame(ev)).await.is_err() {
                return;
            }
        }
        // a stream ended by a limit (`resource_exhausted`: too many keys,
        // or a socket that never catches up) ends with that error
        match s.error() {
            Some(e) => self.send(client_err(id, &e)).await,
            None => self.send(event_frame(id, "closed", [])).await,
        }
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
    let suffix = text(&mut m, "suffix")?;
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
        suffix,
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

/// An error frame of a gateway refusal with its `code` (ADR 0050): `confirm_required`
/// carries `nonce` (to sign) and `request` (the hash).
fn refused_frame(id: u64, r: crate::devices::Refused) -> Value {
    use crate::devices::Refused;
    let mut error = BTreeMap::from([
        (
            "status".to_owned(),
            Value::UInt(Status::PermissionDenied.code().into()),
        ),
        ("message".to_owned(), Value::from("confirm this request")),
    ]);
    if let Refused::ConfirmRequired { nonce, request } = r {
        error.insert("code".into(), Value::from("confirm_required"));
        if let Some(n) = nonce {
            error.insert("nonce".into(), Value::Bytes(n.to_vec()));
        }
        error.insert("request".into(), Value::Bytes(request.to_vec()));
    }
    map([
        ("id", Value::UInt(id)),
        ("ok", Value::Bool(false)),
        ("error", Value::Map(error)),
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

/// `c`, a child of `parent`, with this site's overlays laid on (ADR 0020).
fn laid(sites: &crate::overlay::Sites, parent: &str, mut c: Child) -> Child {
    crate::overlay::lay(sites, &format!("{parent}/{}", c.name), &mut c.meta);
    c
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn keys() {
        assert!(check_key("s", "wy/s/downstream/mock/p0", false).is_ok());
        assert!(check_key("s", "wy/s", false).is_ok());
        assert!(check_key("s", "wy/other/downstream", false).is_err());
        assert!(check_key("s", "wy/sx/downstream", false).is_err());
        assert!(check_key("s", "wy/s/downstream/mock/p0/~set", false).is_err());
        assert!(check_key("s", "wy/s/downstream/**", false).is_err());
        assert!(check_key("s", "wy/s/downstream/**", true).is_ok());
        assert!(check_key("s", "wy/s/downstream//x", false).is_err());
    }

    #[test]
    fn frames_parse() {
        let f = to_vec(&map([
            ("id", Value::UInt(7)),
            ("op", Value::from("set")),
            ("key", Value::from("wy/s/downstream/m/p0")),
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
