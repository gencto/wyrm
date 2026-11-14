//! HTTP(S) server: routes, CBOR bodies, bearer auth, TLS (rustls + ring).

use crate::devices::{Purpose, Refused};
use crate::users::MAX_PASSWORD;
use crate::{AuditEvent, Error, Gateway, LoginError, Principal};
use axum::body::Bytes;
use axum::extract::{ConnectInfo, DefaultBodyLimit, FromRequestParts, Path, Query, State};
use axum::http::header::{AUTHORIZATION, CONTENT_TYPE};
use axum::http::request::Parts;
use axum::http::{HeaderMap, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::routing::{delete, get, post};
use axum::Router;
use std::collections::BTreeMap;
use std::future::Future;
use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::watch;
use tracing::{info, warn};
use wyrm_core::{Perm, Status, Value};
use zeroize::Zeroizing;

/// Largest HTTP body.
const MAX_BODY: usize = 64 * 1024;
/// Largest `POST /api/invoke` body: a link package zip or a WASM component
/// (ADR 0011). WebSocket frames stay at 64 KiB.
const MAX_INVOKE_BODY: usize = (64 << 20) + (64 << 10);
/// Longest wait for an invoke over HTTP: install actions fetch and unpack.
const INVOKE_TIMEOUT: Duration = Duration::from_secs(180);
/// Longest upload of a `POST /api/invoke` body: a slow sender cannot hold
/// one of the two slots for long.
const BODY_TIMEOUT: Duration = Duration::from_secs(120);

#[derive(Clone)]
pub(crate) struct AppState {
    pub gw: Arc<Gateway>,
    pub session: zenoh::Session,
    /// Flips to `true` on shutdown; open sockets close themselves.
    pub stop: watch::Receiver<bool>,
}

pub(crate) async fn serve(
    gw: Arc<Gateway>,
    session: zenoh::Session,
    shutdown: impl Future + Send,
) -> crate::Result<()> {
    let tls = match &gw.cfg.tls {
        Some((cert, key)) => Some(tls_config(cert, key)?),
        None => None,
    };
    let listener = std::net::TcpListener::bind(gw.cfg.listen)?;
    listener.set_nonblocking(true)?;
    let addr = listener.local_addr()?;
    let (stop_tx, stop) = watch::channel(false);
    // this session's view of the overlays; a rebuild serves again
    let _follow = AbortOnDrop(tokio::spawn(crate::overlay::follow(
        session.clone(),
        gw.cfg.site.clone(),
        gw.sites.clone(),
    )));
    let app = router(AppState {
        gw: gw.clone(),
        session,
        stop,
    })
    .into_make_service_with_connect_info::<SocketAddr>();
    let handle = axum_server::Handle::new();
    let server = {
        let handle = handle.clone();
        async move {
            match tls {
                Some(cfg) => {
                    let cfg = axum_server::tls_rustls::RustlsConfig::from_config(Arc::new(cfg));
                    axum_server::from_tcp_rustls(listener, cfg)?
                        .handle(handle)
                        .serve(app)
                        .await
                }
                None => {
                    axum_server::from_tcp(listener)?
                        .handle(handle)
                        .serve(app)
                        .await
                }
            }
        }
    };
    gw.addr.send_replace(Some(addr));
    info!(%addr, tls = gw.cfg.tls.is_some(), "gateway: listening");
    let mut server = std::pin::pin!(server);
    tokio::select! {
        r = &mut server => return r.map_err(Into::into),
        _ = shutdown => {}
    }
    let _ = stop_tx.send(true);
    handle.graceful_shutdown(Some(Duration::from_secs(5)));
    server.await.map_err(Into::into)
}

struct AbortOnDrop(tokio::task::JoinHandle<()>);

impl Drop for AbortOnDrop {
    fn drop(&mut self) {
        self.0.abort();
    }
}

fn tls_config(
    cert: &std::path::Path,
    key: &std::path::Path,
) -> crate::Result<rustls::ServerConfig> {
    use rustls_pki_types::pem::PemObject;
    use rustls_pki_types::{CertificateDer, PrivateKeyDer};
    let bad = |what: &str, e: &dyn std::fmt::Display| Error::Config(format!("tls {what}: {e}"));
    let certs = CertificateDer::pem_file_iter(cert)
        .map_err(|e| bad("certificate", &e))?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| bad("certificate", &e))?;
    let key = PrivateKeyDer::from_pem_file(key).map_err(|e| bad("key", &e))?;
    let provider = Arc::new(rustls::crypto::ring::default_provider());
    let mut c = rustls::ServerConfig::builder_with_provider(provider)
        .with_safe_default_protocol_versions()
        .map_err(|e| bad("protocols", &e))?
        .with_no_client_auth()
        .with_single_cert(certs, key)
        .map_err(|e| bad("certificate", &e))?;
    c.alpn_protocols = vec![b"http/1.1".to_vec()];
    Ok(c)
}

fn router(st: AppState) -> Router {
    let r: Router<AppState> = Router::new()
        .route("/api/login", post(login))
        .route("/api/info", get(info))
        .route("/api/me", get(me))
        .route("/api/me/sign-out", post(sign_out))
        .route("/api/confirm", post(confirm_password))
        .route("/api/device/challenge", post(device_challenge))
        .route("/api/device/login", post(device_login))
        .route("/api/device/confirm", post(device_confirm))
        .route("/api/devices", get(my_devices).post(add_device))
        .route("/api/devices/{id}", delete(remove_device))
        .route("/api/users", get(list_users).post(add_user))
        .route("/api/users/{name}", delete(remove_user))
        .route("/api/users/{name}/devices", get(user_devices))
        .route("/api/users/{name}/password", post(set_password))
        .route("/api/users/{name}/roles", post(set_roles))
        .route("/api/users/{name}/disabled", post(set_disabled))
        .route("/api/ws-ticket", post(ws_ticket))
        .route("/api/ws", get(crate::ws::upgrade))
        // The body is read in the handler after the checks, with its own limit.
        .route("/api/invoke", post(invoke))
        // OAuth 2.1 of the remote MCP endpoint (ADR 0041); 404 while it is off
        .route(
            "/.well-known/oauth-protected-resource",
            get(crate::oauth::protected_resource),
        )
        .route(
            "/.well-known/oauth-protected-resource/mcp",
            get(crate::oauth::protected_resource),
        )
        .route(
            "/.well-known/oauth-authorization-server",
            get(crate::oauth::authorization_server),
        )
        .route("/oauth/register", post(crate::oauth::register))
        .route(
            "/oauth/authorize",
            get(crate::oauth::authorize_page).post(crate::oauth::authorize_submit),
        )
        .route("/oauth/token", post(crate::oauth::token))
        .layer(DefaultBodyLimit::max(MAX_BODY));
    #[cfg(feature = "mcp")]
    let r = match crate::mcp::router(st.clone()) {
        Some(m) => r.merge(m),
        None => r,
    };
    r.with_state(st)
}

/// Error body: `{status: <spec-04 code>, message, code?, …}`; `code` names a refusal a
/// client acts on (ADR 0050: `device_removed`, `confirm_required`, …).
#[derive(Debug)]
pub(crate) struct ApiError {
    http: StatusCode,
    status: Status,
    message: String,
    extra: Vec<(&'static str, Value)>,
}

impl ApiError {
    pub(crate) fn new(http: StatusCode, status: Status, message: impl Into<String>) -> Self {
        Self {
            http,
            status,
            message: message.into(),
            extra: Vec::new(),
        }
    }

    pub fn unauthenticated() -> Self {
        Self::new(
            StatusCode::UNAUTHORIZED,
            Status::PermissionDenied,
            "not authenticated",
        )
    }

    fn forbidden() -> Self {
        Self::new(
            StatusCode::FORBIDDEN,
            Status::PermissionDenied,
            "permission denied",
        )
    }

    fn bad(message: impl Into<String>) -> Self {
        Self::new(StatusCode::BAD_REQUEST, Status::InvalidParameter, message)
    }
}

impl From<Error> for ApiError {
    fn from(e: Error) -> Self {
        match e {
            Error::Rejected(m) => Self::bad(m),
            Error::State(wyrm_state::StateError::Rejected(m)) if m.starts_with("no user") => {
                Self::new(StatusCode::NOT_FOUND, Status::NotFound, m)
            }
            Error::State(wyrm_state::StateError::Rejected(m)) => Self::bad(m),
            e => {
                warn!(error = %e, "gateway: request failed");
                Self::new(
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Status::InternalError,
                    "internal error",
                )
            }
        }
    }
}

impl From<Refused> for ApiError {
    fn from(r: Refused) -> Self {
        let coded = |code: &'static str, message: &str| {
            let mut e = Self::new(StatusCode::FORBIDDEN, Status::PermissionDenied, message);
            e.extra.push(("code", Value::from(code)));
            e
        };
        match r {
            Refused::Bare => Self::new(
                StatusCode::UNAUTHORIZED,
                Status::PermissionDenied,
                "device not accepted",
            ),
            Refused::Code(c) => coded(
                c,
                match c {
                    "device_removed" => "this device was removed",
                    "password_changed" => "the password changed: log in with it",
                    "password_due" => "log in with the password: it is due on this device",
                    "devices_off" => "device keys are off on this gateway",
                    "password_required" => "log in with the password first",
                    "too_many_devices" => "this user has as many devices as the gateway allows",
                    "bad_password" => "wrong password",
                    _ => "refused",
                },
            ),
            Refused::ConfirmRequired { nonce, request } => {
                let mut e = coded("confirm_required", "confirm this request");
                if let Some(n) = nonce {
                    e.extra.push(("nonce", Value::Bytes(n.to_vec())));
                }
                e.extra.push(("request", Value::Bytes(request.to_vec())));
                e
            }
            Refused::RateLimited => Self::new(
                StatusCode::TOO_MANY_REQUESTS,
                Status::RateLimited,
                "too many requests",
            ),
            Refused::Busy => Self::new(StatusCode::SERVICE_UNAVAILABLE, Status::Busy, "busy"),
            Refused::Bad(m) => Self::bad(m),
            Refused::NotFound => {
                Self::new(StatusCode::NOT_FOUND, Status::NotFound, "no such device")
            }
        }
    }
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        let mut m = BTreeMap::from([
            ("status".to_owned(), Value::UInt(self.status.code().into())),
            ("message".to_owned(), Value::Str(self.message)),
        ]);
        for (k, v) in self.extra {
            m.insert(k.to_owned(), v);
        }
        cbor(self.http, &Value::Map(m))
    }
}

fn cbor(http: StatusCode, v: &Value) -> Response {
    match wyrm_core::codec::to_vec(v) {
        Ok(b) => (http, [(CONTENT_TYPE, "application/cbor")], b).into_response(),
        Err(_) => StatusCode::INTERNAL_SERVER_ERROR.into_response(),
    }
}

fn map<const N: usize>(fields: [(&str, Value); N]) -> Value {
    Value::Map(fields.into_iter().map(|(k, v)| (k.to_owned(), v)).collect())
}

fn ok() -> Response {
    cbor(StatusCode::OK, &map([("ok", Value::Bool(true))]))
}

type ApiResult = Result<Response, ApiError>;

fn body_map(body: &[u8]) -> Result<BTreeMap<String, Value>, ApiError> {
    match wyrm_core::codec::from_slice::<Value>(body) {
        Ok(Value::Map(m)) => Ok(m),
        Ok(_) => Err(ApiError::bad("body must be a CBOR map")),
        Err(e) => Err(ApiError::new(
            StatusCode::BAD_REQUEST,
            Status::InvalidMessage,
            format!("body: {e}"),
        )),
    }
}

fn text(m: &mut BTreeMap<String, Value>, k: &str) -> Result<String, ApiError> {
    match m.remove(k) {
        Some(Value::Str(s)) => Ok(s),
        _ => Err(ApiError::bad(format!("{k}: text required"))),
    }
}

fn opt_text(m: &mut BTreeMap<String, Value>, k: &str) -> Result<Option<String>, ApiError> {
    match m.remove(k) {
        None | Some(Value::Null) => Ok(None),
        Some(Value::Str(s)) => Ok(Some(s)),
        _ => Err(ApiError::bad(format!("{k}: text required"))),
    }
}

fn bytes(m: &mut BTreeMap<String, Value>, k: &str) -> Result<Vec<u8>, ApiError> {
    match m.remove(k) {
        Some(Value::Bytes(b)) => Ok(b),
        _ => Err(ApiError::bad(format!("{k}: bytes required"))),
    }
}

/// The request a step-up names, for HTTP: `{method, path, body}`.
fn http_request(method: &str, path: &str, body: &[u8]) -> Value {
    map([
        ("method", Value::from(method)),
        ("path", Value::from(path)),
        ("body", Value::Bytes(body.to_vec())),
    ])
}

/// Refuse a `config`-level change of a session that is not confirmed (`step_up: config`).
fn step_up(gw: &Gateway, p: &Principal, request: Value) -> Result<(), ApiError> {
    gw.step_up(p, &request).map_err(|r| {
        gw.audit(AuditEvent::Denied {
            user: p.name.clone(),
            op: "confirm_required".into(),
            key: String::new(),
        });
        ApiError::from(r)
    })
}

fn roles(m: &mut BTreeMap<String, Value>) -> Result<Vec<String>, ApiError> {
    match m.remove("roles") {
        Some(Value::Array(a)) => a
            .into_iter()
            .map(|r| match r {
                Value::Str(s) => Ok(s),
                _ => Err(ApiError::bad("roles: array of text required")),
            })
            .collect(),
        _ => Err(ApiError::bad("roles: array of text required")),
    }
}

pub(crate) fn bearer(h: &HeaderMap) -> Option<String> {
    let v = h.get(AUTHORIZATION)?.to_str().ok()?;
    v.strip_prefix("Bearer ").map(|t| t.trim().to_owned())
}

/// An authenticated request.
pub(crate) struct Auth(Principal);

impl FromRequestParts<AppState> for Auth {
    type Rejection = ApiError;

    async fn from_request_parts(parts: &mut Parts, st: &AppState) -> Result<Self, ApiError> {
        bearer(&parts.headers)
            .and_then(|t| st.gw.authenticate(&t))
            .map(Auth)
            .ok_or_else(ApiError::unauthenticated)
    }
}

/// An authenticated request by a user who may manage users.
pub(crate) struct Admin(Principal);

impl FromRequestParts<AppState> for Admin {
    type Rejection = ApiError;

    async fn from_request_parts(parts: &mut Parts, st: &AppState) -> Result<Self, ApiError> {
        let Auth(p) = Auth::from_request_parts(parts, st).await?;
        if st.gw.is_admin(&p) {
            Ok(Admin(p))
        } else {
            Err(ApiError::forbidden())
        }
    }
}

async fn login(
    State(st): State<AppState>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
    body: Bytes,
) -> ApiResult {
    let mut m = body_map(&body)?;
    let user = text(&mut m, "user")?;
    let password = Zeroizing::new(text(&mut m, "password")?);
    // the device this login is on (ADR 0050): its `password_due` starts again
    let device = opt_text(&mut m, "device")?;
    if user.len() > 64
        || password.len() > MAX_PASSWORD
        || device.as_ref().is_some_and(|d| d.len() > 64)
    {
        return Err(ApiError::bad("user or password too long"));
    }
    // A locked caller never waits for (or holds) a hashing permit.
    let r = match st.gw.check_limit(&user, peer.ip()) {
        Err(e) => Err(e),
        Ok(()) => {
            let _permit = st.gw.hashing.acquire().await.map_err(|_| {
                ApiError::new(StatusCode::SERVICE_UNAVAILABLE, Status::Busy, "stopping")
            })?;
            let gw = st.gw.clone();
            tokio::task::spawn_blocking(move || {
                gw.login(&user, password, device.as_deref(), peer.ip())
            })
            .await
            .map_err(|_| Error::Rejected("login task failed".into()))?
        }
    };
    match r {
        Ok((session, exp)) => Ok(cbor(
            StatusCode::OK,
            &map([("session", Value::Str(session)), ("exp", Value::UInt(exp))]),
        )),
        Err(LoginError::Invalid) => Err(ApiError::new(
            StatusCode::UNAUTHORIZED,
            Status::PermissionDenied,
            "invalid credentials",
        )),
        Err(LoginError::RateLimited) => Err(ApiError::new(
            StatusCode::TOO_MANY_REQUESTS,
            Status::RateLimited,
            "too many failed logins",
        )),
    }
}

async fn ws_ticket(State(st): State<AppState>, headers: HeaderMap) -> ApiResult {
    let session = bearer(&headers).ok_or_else(ApiError::unauthenticated)?;
    let (ticket, exp) = st
        .gw
        .ws_ticket(&session)
        .ok_or_else(ApiError::unauthenticated)?;
    Ok(cbor(
        StatusCode::OK,
        &map([("ticket", Value::Str(ticket)), ("exp", Value::UInt(exp))]),
    ))
}

#[derive(serde::Deserialize)]
pub(crate) struct InvokeQuery {
    key: String,
    action: String,
}

/// Most CBOR data items in a `POST /api/invoke` body: its size is for file
/// contents (one byte string each), not for a tree that decodes to many
/// times its size.
const MAX_ARG_ITEMS: usize = 10_000;

/// Data items of `b`, refused past `max`, without building a value.
fn cbor_items(b: &[u8], max: usize) -> Result<usize, ApiError> {
    let mut d = minicbor::Decoder::new(b);
    let mut n = 0;
    for t in d.tokens() {
        t.map_err(|e| {
            ApiError::new(
                StatusCode::BAD_REQUEST,
                Status::InvalidMessage,
                format!("args: {e}"),
            )
        })?;
        n += 1;
        if n > max {
            return Err(ApiError::bad(format!("args: more than {max} items")));
        }
    }
    Ok(n)
}

fn client_failure(e: wyrm_client::ClientError) -> ApiError {
    let status = match e.status {
        wyrm_core::status::StatusCode::Known(s) => s,
        _ => Status::InternalError,
    };
    ApiError::new(StatusCode::BAD_GATEWAY, status, e.message)
}

/// `POST /api/invoke?key=<node>&action=<a>`, body = the CBOR `args` map: one
/// invoke of an action with an `editor: file` parameter whose arguments are
/// too large for a WebSocket frame (ADR 0011). Before the body is read: the
/// key, the file parameter (from the node's `~meta`) and the user's grant at
/// the action's level ([`check_invoke`]). Then at most [`MAX_ARG_ITEMS`]
/// items are decoded; two such calls run at a time. Replies `{result}` with
/// the last value.
async fn invoke(
    State(st): State<AppState>,
    Auth(p): Auth,
    Query(q): Query<InvokeQuery>,
    body: axum::body::Body,
) -> ApiResult {
    let c = match check_invoke(&st, &p, &q).await {
        Ok(c) => c,
        Err(e) => {
            // Read a small body anyway, so the client gets the answer and not
            // a reset; a big one is cut off.
            let _ = axum::body::to_bytes(body, MAX_BODY).await;
            return Err(e);
        }
    };
    let busy = |why: &str| ApiError::new(StatusCode::SERVICE_UNAVAILABLE, Status::Busy, why);
    // One upload per user, two in all.
    let Some(_slot) = st.gw.upload_slot(&p.name) else {
        let _ = axum::body::to_bytes(body, MAX_BODY).await;
        return Err(busy("an upload of this user is in progress"));
    };
    let Ok(_permit) = st.gw.bulk.try_acquire() else {
        let _ = axum::body::to_bytes(body, MAX_BODY).await;
        return Err(busy("too many uploads at once"));
    };
    let bytes = tokio::time::timeout(BODY_TIMEOUT, axum::body::to_bytes(body, MAX_INVOKE_BODY))
        .await
        .map_err(|_| {
            ApiError::new(
                StatusCode::REQUEST_TIMEOUT,
                Status::Timeout,
                format!("body not received in {} s", BODY_TIMEOUT.as_secs()),
            )
        })?
        .map_err(|_| {
            ApiError::new(
                StatusCode::PAYLOAD_TOO_LARGE,
                Status::InvalidParameter,
                format!("body over {} MiB", MAX_INVOKE_BODY >> 20),
            )
        })?;
    cbor_items(&bytes, MAX_ARG_ITEMS)?;
    let args = match wyrm_core::codec::from_slice::<Value>(&bytes) {
        Ok(v @ Value::Map(_)) => v,
        Ok(_) => return Err(ApiError::bad("args: a CBOR map")),
        Err(e) => {
            return Err(ApiError::new(
                StatusCode::BAD_REQUEST,
                Status::InvalidMessage,
                format!("args: {e}"),
            ))
        }
    };
    let mut s = c
        .invoke(&q.key, &q.action, args)
        .await
        .map_err(client_failure)?;
    let mut last = None;
    while let Some(item) = futures_util::StreamExt::next(&mut s).await {
        match item {
            Ok(Some(v)) => last = Some(v),
            Ok(None) => {}
            Err(e) => return Err(client_failure(e)),
        }
    }
    Ok(cbor(
        StatusCode::OK,
        &map([("result", last.unwrap_or(Value::Null))]),
    ))
}

/// The checks of [`invoke`] before its body is read; returns the client
/// with the user's tokens.
async fn check_invoke(
    st: &AppState,
    p: &Principal,
    q: &InvokeQuery,
) -> Result<wyrm_client::WyrmClient, ApiError> {
    let gw = &st.gw;
    let (key, action) = (&q.key, &q.action);
    // A downstream site is checked as the own site (ADR 0018).
    let own = gw.as_own(key);
    crate::ws::check_key(gw.site(), &own, false).map_err(ApiError::bad)?;
    wyrm_core::keyspace::validate_segment(action)
        .map_err(|_| ApiError::bad("action: valid segment required"))?;
    let deny = || {
        gw.audit(AuditEvent::Denied {
            user: p.name.clone(),
            op: "invoke".into(),
            key: key.clone(),
        });
        ApiError::forbidden()
    };
    let act_key = format!("{own}/~act/{action}");
    if p.grants.perm(&act_key) < Perm::Read {
        return Err(deny());
    }
    let c = wyrm_client::WyrmClient::new(st.session.clone())
        .with_tokens(Arc::new(gw.tokens_for(p)))
        .with_timeout(INVOKE_TIMEOUT);
    let meta = c.meta_expanded(key).await.map_err(client_failure)?;
    let Some(am) = meta.actions.as_ref().and_then(|a| a.get(action)) else {
        return Err(ApiError::bad(format!("no action {action} on {key}")));
    };
    if !am
        .params
        .values()
        .any(|p| p.editor.as_deref() == Some(wyrm_core::meta::EDITOR_FILE))
    {
        return Err(ApiError::bad(format!(
            "{action} takes no file: invoke it over the WebSocket"
        )));
    }
    // The action's own level, before 64 MiB arrive (the link checks again).
    let level = am.level.unwrap_or(Perm::Read).max(Perm::Read);
    if p.grants.perm(&act_key) < level {
        return Err(deny());
    }
    // a config action of a session not confirmed (ADR 0050 §1.3)
    if level >= Perm::Config {
        let req = map([
            ("op", Value::from("invoke")),
            ("key", Value::from(key.as_str())),
            ("action", Value::from(action.as_str())),
        ]);
        step_up(gw, p, req)?;
    }
    Ok(c)
}

async fn me(State(st): State<AppState>, Auth(p): Auth) -> ApiResult {
    let grants = p
        .grants
        .list
        .iter()
        .map(|g| {
            map([
                ("k", Value::Str(g.k.clone())),
                ("p", Value::from(g.p.name())),
            ])
        })
        .collect();
    Ok(cbor(
        StatusCode::OK,
        &map([
            ("sub", Value::Str(p.name)),
            (
                "roles",
                Value::Array(p.roles.into_iter().map(Value::Str).collect()),
            ),
            ("grants", Value::Array(grants)),
            ("max", Value::from(p.grants.max.name())),
            ("exp", Value::UInt(p.claims.exp)),
            // The site the gateway serves (peer sites: its `upstream` and
            // `downstream` sections).
            ("site", Value::Str(st.gw.site().to_owned())),
        ]),
    ))
}

async fn list_users(State(st): State<AppState>, _: Admin) -> ApiResult {
    let users = st
        .gw
        .list_users()
        .into_iter()
        .map(|(name, roles, disabled)| {
            let devices = st.gw.active_devices(&name) as u64;
            map([
                ("devices", Value::UInt(devices)),
                ("name", Value::Str(name)),
                (
                    "roles",
                    Value::Array(roles.into_iter().map(Value::Str).collect()),
                ),
                ("disabled", Value::Bool(disabled)),
            ])
        })
        .collect();
    Ok(cbor(StatusCode::OK, &Value::Array(users)))
}

fn changed(gw: &Gateway, by: &Principal, user: &str, change: &'static str) {
    gw.audit(AuditEvent::UserChanged {
        by: format!("user:{}", by.name),
        user: user.to_owned(),
        change,
    });
}

/// Run argon2 work off the async runtime, bounded like logins.
async fn hashing<T: Send + 'static>(
    gw: &Arc<Gateway>,
    f: impl FnOnce(&Gateway) -> crate::Result<T> + Send + 'static,
) -> Result<T, ApiError> {
    let _permit =
        gw.hashing.acquire().await.map_err(|_| {
            ApiError::new(StatusCode::SERVICE_UNAVAILABLE, Status::Busy, "stopping")
        })?;
    let gw = gw.clone();
    tokio::task::spawn_blocking(move || f(&gw))
        .await
        .map_err(|_| ApiError::from(Error::Rejected("task failed".into())))?
        .map_err(Into::into)
}

async fn add_user(State(st): State<AppState>, Admin(by): Admin, body: Bytes) -> ApiResult {
    step_up(&st.gw, &by, http_request("POST", "/api/users", &body))?;
    let mut m = body_map(&body)?;
    let name = text(&mut m, "name")?;
    let password = Zeroizing::new(text(&mut m, "password")?);
    let roles = roles(&mut m)?;
    let n = name.clone();
    hashing(&st.gw, move |gw| gw.add_user(&n, &password, roles)).await?;
    changed(&st.gw, &by, &name, "add");
    Ok(ok())
}

async fn set_password(
    State(st): State<AppState>,
    Admin(by): Admin,
    Path(name): Path<String>,
    body: Bytes,
) -> ApiResult {
    step_up(
        &st.gw,
        &by,
        http_request("POST", &format!("/api/users/{name}/password"), &body),
    )?;
    let mut m = body_map(&body)?;
    let password = Zeroizing::new(text(&mut m, "password")?);
    let n = name.clone();
    hashing(&st.gw, move |gw| gw.set_password(&n, &password)).await?;
    changed(&st.gw, &by, &name, "password");
    Ok(ok())
}

async fn set_roles(
    State(st): State<AppState>,
    Admin(by): Admin,
    Path(name): Path<String>,
    body: Bytes,
) -> ApiResult {
    step_up(
        &st.gw,
        &by,
        http_request("POST", &format!("/api/users/{name}/roles"), &body),
    )?;
    let roles = roles(&mut body_map(&body)?)?;
    st.gw.set_roles(&name, roles)?;
    changed(&st.gw, &by, &name, "roles");
    Ok(ok())
}

async fn set_disabled(
    State(st): State<AppState>,
    Admin(by): Admin,
    Path(name): Path<String>,
    body: Bytes,
) -> ApiResult {
    step_up(
        &st.gw,
        &by,
        http_request("POST", &format!("/api/users/{name}/disabled"), &body),
    )?;
    let Some(Value::Bool(disabled)) = body_map(&body)?.remove("disabled") else {
        return Err(ApiError::bad("disabled: bool required"));
    };
    st.gw.set_disabled(&name, disabled)?;
    changed(
        &st.gw,
        &by,
        &name,
        if disabled { "disabled" } else { "enabled" },
    );
    Ok(ok())
}

async fn remove_user(
    State(st): State<AppState>,
    Admin(by): Admin,
    Path(name): Path<String>,
) -> ApiResult {
    step_up(
        &st.gw,
        &by,
        http_request("DELETE", &format!("/api/users/{name}"), &[]),
    )?;
    st.gw.remove_user(&name)?;
    changed(&st.gw, &by, &name, "remove");
    Ok(ok())
}

async fn info(State(st): State<AppState>, ConnectInfo(peer): ConnectInfo<SocketAddr>) -> ApiResult {
    if !st.gw.info_limit.allowed(peer.ip()) {
        return Err(Refused::RateLimited.into());
    }
    Ok(cbor(StatusCode::OK, &st.gw.info()))
}

/// `POST /api/me/sign-out`: sign out everywhere (every session, every device key).
async fn sign_out(State(st): State<AppState>, Auth(p): Auth) -> ApiResult {
    st.gw.end_sessions(&p.name)?;
    changed(&st.gw, &p, &p.name, "sign_out");
    Ok(ok())
}

/// `POST /api/device/challenge {device}` → `{nonce, exp}`; with a bearer session
/// `{purpose: "register" | "confirm"}` instead.
async fn device_challenge(
    State(st): State<AppState>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
    headers: HeaderMap,
    body: Bytes,
) -> ApiResult {
    let mut m = body_map(&body)?;
    let purpose = match opt_text(&mut m, "purpose")?.as_deref() {
        None | Some("login") => {
            let device = text(&mut m, "device")?;
            if device.is_empty() || device.len() > 64 {
                return Err(ApiError::bad("device: 1 to 64 bytes"));
            }
            Purpose::Login { device }
        }
        Some(which @ ("register" | "confirm")) => {
            let p = bearer(&headers)
                .and_then(|t| st.gw.authenticate(&t))
                .ok_or_else(ApiError::unauthenticated)?;
            let (user, jti) = (p.name, p.claims.jti);
            if which == "register" {
                Purpose::Register { user, jti }
            } else {
                Purpose::Confirm { user, jti }
            }
        }
        Some(_) => return Err(ApiError::bad("purpose: login, register or confirm")),
    };
    let (nonce, exp) = st.gw.device_challenge(purpose, peer.ip())?;
    Ok(cbor(
        StatusCode::OK,
        &map([
            ("nonce", Value::Bytes(nonce.to_vec())),
            ("exp", Value::UInt(exp)),
        ]),
    ))
}

/// `POST /api/devices {name, platform, alg, public_key, attestation?, origin, nonce,
/// signature}` → `{device}`.
async fn add_device(
    State(st): State<AppState>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
    Auth(p): Auth,
    body: Bytes,
) -> ApiResult {
    let mut m = body_map(&body)?;
    let name = text(&mut m, "name")?;
    let platform = text(&mut m, "platform")?;
    let alg = text(&mut m, "alg")?;
    let public_key = bytes(&mut m, "public_key")?;
    let attestation = match m.remove("attestation") {
        None | Some(Value::Null) => None,
        Some(Value::Bytes(b)) => Some(b),
        _ => return Err(ApiError::bad("attestation: bytes")),
    };
    let origin = text(&mut m, "origin")?;
    let nonce = bytes(&mut m, "nonce")?;
    let signature = bytes(&mut m, "signature")?;
    let id = st.gw.register_device(
        &p,
        &name,
        &platform,
        &alg,
        &public_key,
        attestation,
        &origin,
        &nonce,
        &signature,
        peer.ip(),
    )?;
    Ok(cbor(StatusCode::OK, &map([("device", Value::Str(id))])))
}

/// `POST /api/device/login {device, origin, nonce, signature, session?}` → `{session, exp}`.
async fn device_login(
    State(st): State<AppState>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
    body: Bytes,
) -> ApiResult {
    let mut m = body_map(&body)?;
    let device = text(&mut m, "device")?;
    let origin = text(&mut m, "origin")?;
    let nonce = bytes(&mut m, "nonce")?;
    let signature = bytes(&mut m, "signature")?;
    let keep = opt_text(&mut m, "session")?.map(Zeroizing::new);
    let (session, exp) = st.gw.device_login(
        &device,
        &origin,
        &nonce,
        &signature,
        keep.as_ref().map(|s| s.as_str()),
        peer.ip(),
    )?;
    Ok(cbor(
        StatusCode::OK,
        &map([("session", Value::Str(session)), ("exp", Value::UInt(exp))]),
    ))
}

/// `POST /api/device/confirm {device, origin, nonce, request, signature}`.
async fn device_confirm(
    State(st): State<AppState>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
    Auth(p): Auth,
    body: Bytes,
) -> ApiResult {
    let mut m = body_map(&body)?;
    let device = text(&mut m, "device")?;
    let origin = text(&mut m, "origin")?;
    let nonce = bytes(&mut m, "nonce")?;
    let request = bytes(&mut m, "request")?;
    let signature = bytes(&mut m, "signature")?;
    st.gw.confirm_device(
        &p,
        &device,
        &origin,
        &nonce,
        &request,
        &signature,
        peer.ip(),
    )?;
    Ok(ok())
}

/// `POST /api/confirm {password}`.
async fn confirm_password(
    State(st): State<AppState>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
    Auth(p): Auth,
    body: Bytes,
) -> ApiResult {
    let password = Zeroizing::new(text(&mut body_map(&body)?, "password")?);
    if password.len() > MAX_PASSWORD {
        return Err(ApiError::bad("password too long"));
    }
    let _permit =
        st.gw.hashing.acquire().await.map_err(|_| {
            ApiError::new(StatusCode::SERVICE_UNAVAILABLE, Status::Busy, "stopping")
        })?;
    let gw = st.gw.clone();
    tokio::task::spawn_blocking(move || gw.confirm_password(&p, password, peer.ip()))
        .await
        .map_err(|_| ApiError::from(Error::Rejected("confirm task failed".into())))??;
    Ok(ok())
}

async fn my_devices(State(st): State<AppState>, Auth(p): Auth) -> ApiResult {
    let rows = st.gw.devices_of(&p.name, p.claims.dev.as_deref());
    Ok(cbor(StatusCode::OK, &Value::Array(rows)))
}

async fn user_devices(State(st): State<AppState>, _: Admin, Path(name): Path<String>) -> ApiResult {
    if st.gw.user(&name).is_none() {
        return Err(ApiError::new(
            StatusCode::NOT_FOUND,
            Status::NotFound,
            format!("no user {name}"),
        ));
    }
    Ok(cbor(
        StatusCode::OK,
        &Value::Array(st.gw.devices_of(&name, None)),
    ))
}

/// `DELETE /api/devices/{id}`: its owner turns it off; an admin removes another user's
/// device (a `config` change: the step-up applies).
async fn remove_device(
    State(st): State<AppState>,
    Auth(p): Auth,
    Path(id): Path<String>,
) -> ApiResult {
    let theirs = st
        .gw
        .devices_owner(&id)
        .is_some_and(|owner| owner != p.name);
    if theirs && st.gw.is_admin(&p) {
        step_up(
            &st.gw,
            &p,
            http_request("DELETE", &format!("/api/devices/{id}"), &[]),
        )?;
    }
    st.gw.remove_device(&p, &id)?;
    Ok(ok())
}
