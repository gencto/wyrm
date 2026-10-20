//! HTTP(S) server: routes, CBOR bodies, bearer auth, TLS (rustls + ring).

use crate::users::MAX_PASSWORD;
use crate::{AuditEvent, Error, Gateway, LoginError, Principal};
use axum::body::Bytes;
use axum::extract::{ConnectInfo, DefaultBodyLimit, FromRequestParts, Path, State};
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
use wyrm_core::{Status, Value};
use zeroize::Zeroizing;

/// Largest HTTP body.
const MAX_BODY: usize = 64 * 1024;

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
    Router::new()
        .route("/api/login", post(login))
        .route("/api/me", get(me))
        .route("/api/users", get(list_users).post(add_user))
        .route("/api/users/{name}", delete(remove_user))
        .route("/api/users/{name}/password", post(set_password))
        .route("/api/users/{name}/roles", post(set_roles))
        .route("/api/users/{name}/disabled", post(set_disabled))
        .route("/api/ws-ticket", post(ws_ticket))
        .route("/api/ws", get(crate::ws::upgrade))
        .layer(DefaultBodyLimit::max(MAX_BODY))
        .with_state(st)
}

/// Error body: `{status: <spec-04 code>, message}`.
#[derive(Debug)]
pub(crate) struct ApiError {
    http: StatusCode,
    status: Status,
    message: String,
}

impl ApiError {
    fn new(http: StatusCode, status: Status, message: impl Into<String>) -> Self {
        Self {
            http,
            status,
            message: message.into(),
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

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        cbor(
            self.http,
            &map([
                ("status", Value::UInt(self.status.code().into())),
                ("message", Value::Str(self.message)),
            ]),
        )
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
    if user.len() > 64 || password.len() > MAX_PASSWORD {
        return Err(ApiError::bad("user or password too long"));
    }
    let _permit =
        st.gw.hashing.acquire().await.map_err(|_| {
            ApiError::new(StatusCode::SERVICE_UNAVAILABLE, Status::Busy, "stopping")
        })?;
    let gw = st.gw.clone();
    let r = tokio::task::spawn_blocking(move || gw.login(&user, password, peer.ip()))
        .await
        .map_err(|_| Error::Rejected("login task failed".into()))?;
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

async fn me(Auth(p): Auth) -> ApiResult {
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
        ]),
    ))
}

async fn list_users(State(st): State<AppState>, _: Admin) -> ApiResult {
    let users = st
        .gw
        .list_users()
        .into_iter()
        .map(|(name, roles, disabled)| {
            map([
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
    st.gw.remove_user(&name)?;
    changed(&st.gw, &by, &name, "remove");
    Ok(ok())
}
