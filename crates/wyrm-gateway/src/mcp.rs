//! The remote MCP endpoint `/mcp` (ADR 0041 stage B): streamable HTTP, a bearer from the
//! gateway's own OAuth server ([`crate::oauth`]), and the tools of `wyrm_mcp::gateway` run
//! in process over the WebSocket protocol handler, through a pipe instead of a socket.
//!
//! Every request is authenticated on its own: the bearer is checked (MAC, expiry, the user's
//! generation, enabled) and the user's current grants go with it. One pipe per access token
//! is kept while it lives; it closes with the token's expiry like any session.

use crate::http::{bearer, AppState};
use crate::oauth::{session_claims, Access};
use crate::ws::{serve_frames, WsIn, WsOut};
use crate::Principal;
use axum::extract::{Request, State};
use axum::http::header::WWW_AUTHENTICATE;
use axum::http::{HeaderValue, StatusCode};
use axum::middleware::Next;
use axum::response::{IntoResponse, Response};
use axum::Router;
use futures_util::{SinkExt, StreamExt};
use rmcp::model::Extensions;
use rmcp::transport::streamable_http_server::{
    session::local::LocalSessionManager, StreamableHttpServerConfig, StreamableHttpService,
};
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use tokio_tungstenite::tungstenite::protocol::frame::coding::CloseCode;
use tokio_tungstenite::tungstenite::protocol::{CloseFrame, Role};
use tokio_tungstenite::tungstenite::Message;
use tokio_tungstenite::WebSocketStream;
use wyrm_gateway_client::{Conn, Me};
use wyrm_mcp::gateway::{Backend, BoxFuture, GatewayMcp, Session};

/// Pipes kept at once (one per live access token).
const PIPES_MAX: usize = 256;
const PIPE_BUF: usize = 256 * 1024;

/// The request's verified user and what the person allowed, put into the request by
/// [`authenticate`] and read by the tools.
#[derive(Clone)]
pub(crate) struct McpAuth {
    pub principal: Principal,
    pub access: Access,
}

struct InGateway {
    st: AppState,
    pipes: Mutex<HashMap<[u8; 16], Session>>,
}

impl InGateway {
    fn me(&self, p: &Principal) -> Me {
        Me {
            sub: p.name.clone(),
            roles: p.roles.clone(),
            grants: p
                .grants
                .list
                .iter()
                .map(|g| (g.k.clone(), g.p.name().to_owned()))
                .collect(),
            max: p.grants.max.name().to_owned(),
            exp: p.claims.exp,
            site: self.st.gw.site().to_owned(),
        }
    }

    async fn open(&self, auth: &McpAuth) -> Result<Session, String> {
        let p = &auth.principal;
        if let Some(s) = self.pipes_lock().get(&auth.access.jti) {
            if !s.conn.is_closed() {
                // the grants as now; the pipe re-reads them itself every 15 s
                let mut s = s.clone();
                s.me = self.me(p);
                return Ok(s);
            }
        }
        let slot = self
            .st
            .gw
            .socket_slot(&p.name)
            .ok_or("too many open sockets for this user")?;
        let (client, server) = tokio::io::duplex(PIPE_BUF);
        let ws = WebSocketStream::from_raw_socket(server, Role::Server, None).await;
        let (sink, stream) = ws.split();
        let sink = sink.with(|o: WsOut| {
            futures_util::future::ready(Ok::<_, tokio_tungstenite::tungstenite::Error>(match o {
                WsOut::Binary(b) => Message::Binary(b.into()),
                WsOut::Close(code, reason) => Message::Close(Some(CloseFrame {
                    code: CloseCode::from(code),
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
        let st = self.st.clone();
        let principal = p.clone();
        tokio::spawn(async move {
            serve_frames(st, principal, stream, sink).await;
            drop(slot);
        });
        let s = Session {
            conn: Arc::new(Conn::from_raw(client).await),
            me: self.me(p),
            read_only: !auth.access.consent.write,
            allow_config: auth.access.consent.config,
        };
        let mut m = self.pipes_lock();
        m.retain(|_, s| !s.conn.is_closed());
        if m.len() < PIPES_MAX {
            m.insert(auth.access.jti, s.clone());
        }
        Ok(s)
    }

    fn pipes_lock(&self) -> std::sync::MutexGuard<'_, HashMap<[u8; 16], Session>> {
        self.pipes.lock().unwrap_or_else(|p| p.into_inner())
    }
}

impl Backend for InGateway {
    fn session<'a>(&'a self, ext: &'a Extensions) -> BoxFuture<'a, Result<Session, String>> {
        Box::pin(async move {
            let auth = ext
                .get::<axum::http::request::Parts>()
                .and_then(|p| p.extensions.get::<McpAuth>())
                .ok_or("not signed in")?;
            self.open(auth).await
        })
    }

    fn label(&self) -> String {
        self.st
            .gw
            .oauth
            .as_ref()
            .map(|o| o.issuer().to_owned())
            .unwrap_or_default()
    }
}

fn unauthorized(st: &AppState, error: Option<&str>) -> Response {
    let meta = st
        .gw
        .oauth
        .as_ref()
        .map(|o| o.resource_metadata_url())
        .unwrap_or_default();
    let mut v = format!("Bearer resource_metadata=\"{meta}\"");
    if let Some(e) = error {
        v.push_str(&format!(", error=\"{e}\""));
    }
    let mut r = StatusCode::UNAUTHORIZED.into_response();
    if let Ok(h) = HeaderValue::from_str(&v) {
        r.headers_mut().insert(WWW_AUTHENTICATE, h);
    }
    r
}

/// The bearer of every `/mcp` request: an access token of this gateway for a user as now.
async fn authenticate(State(st): State<AppState>, mut req: Request, next: Next) -> Response {
    let Some(o) = st.gw.oauth.as_ref() else {
        return StatusCode::NOT_FOUND.into_response();
    };
    let Some(token) = bearer(req.headers()) else {
        return unauthorized(&st, None);
    };
    let Some(access) = o.access(&token) else {
        return unauthorized(&st, Some("invalid_token"));
    };
    let Some(principal) = st.gw.resolve(session_claims(&access)) else {
        return unauthorized(&st, Some("invalid_token"));
    };
    req.extensions_mut().insert(McpAuth { principal, access });
    next.run(req).await
}

/// `/mcp` with its bearer check; `None` when the endpoint is off.
pub(crate) fn router(st: AppState) -> Option<Router<AppState>> {
    let o = st.gw.oauth.as_ref()?;
    let backend: Arc<dyn Backend> = Arc::new(InGateway {
        st: st.clone(),
        pipes: Mutex::new(HashMap::new()),
    });
    let config = StreamableHttpServerConfig::default().with_allowed_hosts(o.hosts());
    let mut stop = st.stop.clone();
    let ct = config.cancellation_token.clone();
    tokio::spawn(async move {
        let _ = stop.changed().await;
        ct.cancel();
    });
    let service = StreamableHttpService::new(
        move || Ok(GatewayMcp::with_backend(backend.clone())),
        LocalSessionManager::default().into(),
        config,
    );
    Some(
        Router::<AppState>::new()
            .nest_service("/mcp", service)
            .layer(axum::middleware::from_fn_with_state(st, authenticate)),
    )
}
