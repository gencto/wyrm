//! An HTTP/1.1 JSON server for tests and demos (feature `sim`).
//!
//! Endpoints:
//!
//! * `GET /api/data` → [`State::data`] (nested objects, arrays; `tick`
//!   moves `meter.power` and `meter.energy` on every request);
//! * `POST /api/query` → `{"got": <request body>, "data": <data>}`;
//! * `GET /api/echo` → `{"headers": {…}, "query": "…"}` of the request;
//! * `GET /api/raw` → [`State::raw`] byte for byte;
//! * `GET /api/resource` → [`State::resource`]; `PUT`/`POST`/`PATCH` with
//!   a JSON object merges it in (a writable resource; `400` otherwise);
//! * `GET /redirect/<n>` → `302` to `/redirect/<n-1>`, `/redirect/0` →
//!   `302` to `/api/data`; `GET /offsite` → `302` to another host;
//! * anything else → `404`.
//!
//! [`State::auth`] checks every request (basic, bearer, API key in a
//! header or a query parameter); [`State::mode`] injects failures (a fixed
//! status, silence, invalid JSON, a huge body); `slow_ms` delays replies,
//! `close` closes the connection after each reply. Every request is
//! recorded in [`State::seen`].

use base64::Engine as _;
use bytes::Bytes;
use http_body_util::{BodyExt, Full, Limited};
use hyper::body::Incoming;
use hyper::{Request, Response, StatusCode};
use hyper_util::rt::TokioIo;
use serde_json::{json, Value as Json};
use std::net::SocketAddr;
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tokio::net::TcpListener;
use tokio::task::JoinHandle;

/// What the server checks on every request.
#[derive(Debug, Clone, Default, PartialEq)]
pub enum SimAuth {
    #[default]
    None,
    Basic(String, String),
    Bearer(String),
    Header(String, String),
    Query(String, String),
}

/// Failure modes.
#[derive(Debug, Clone, Default, PartialEq)]
pub enum Mode {
    #[default]
    Normal,
    /// Every request answers with this status and `{"error": …}`.
    Status(u16),
    /// Requests are read and never answered.
    Silent,
    /// `200` with a body that is not JSON.
    InvalidJson,
    /// `200` with a JSON array of this many bytes.
    Huge(usize),
}

/// One request as received.
#[derive(Debug, Clone)]
pub struct Seen {
    pub method: String,
    pub path: String,
    pub query: String,
    pub headers: Vec<(String, String)>,
    pub body: String,
    pub at: tokio::time::Instant,
}

impl Seen {
    pub fn header(&self, name: &str) -> Option<&str> {
        self.headers
            .iter()
            .find(|(k, _)| k.eq_ignore_ascii_case(name))
            .map(|(_, v)| v.as_str())
    }
}

#[derive(Debug)]
pub struct State {
    pub data: Json,
    pub resource: Json,
    /// Move `meter.power` and `meter.energy` on each `GET /api/data`.
    pub tick: bool,
    pub auth: SimAuth,
    pub mode: Mode,
    pub slow_ms: u64,
    pub close: bool,
    pub seen: Vec<Seen>,
    /// TCP connections accepted.
    pub connections: u64,
    /// Served as is by `GET /api/raw` (exact bytes, e.g. JSON escapes).
    pub raw: Option<String>,
}

impl Default for State {
    fn default() -> Self {
        State {
            data: json!({
                "meter": {
                    "power": 1200.5,
                    "energy": 5000,
                    "voltage": "230.1",
                    "on": true,
                    "state": "ON",
                    "name": "sim-1"
                },
                "items": [
                    {"id": "a", "v": 1.5},
                    {"id": "b", "v": 2.5},
                    {"id": "c", "v": 3}
                ],
                "nested": {"deep": {"x": 42}},
                "nothing": null
            }),
            resource: json!({"setpoint": 20.0, "mode": "auto", "enabled": false, "label": "x"}),
            tick: false,
            auth: SimAuth::None,
            mode: Mode::Normal,
            slow_ms: 0,
            close: false,
            seen: Vec::new(),
            connections: 0,
            raw: None,
        }
    }
}

pub type Shared = Arc<Mutex<State>>;

fn lock(s: &Shared) -> std::sync::MutexGuard<'_, State> {
    s.lock().unwrap_or_else(|e| e.into_inner())
}

/// Serve plain HTTP on `addr`.
pub async fn spawn(addr: &str) -> std::io::Result<(SocketAddr, Shared, JoinHandle<()>)> {
    spawn_with(addr, None).await
}

/// Serve HTTPS on `addr` with `tls`.
pub async fn spawn_tls(
    addr: &str,
    tls: Arc<rustls::ServerConfig>,
) -> std::io::Result<(SocketAddr, Shared, JoinHandle<()>)> {
    spawn_with(addr, Some(tokio_rustls::TlsAcceptor::from(tls))).await
}

async fn spawn_with(
    addr: &str,
    tls: Option<tokio_rustls::TlsAcceptor>,
) -> std::io::Result<(SocketAddr, Shared, JoinHandle<()>)> {
    let listener = TcpListener::bind(addr).await?;
    let local = listener.local_addr()?;
    let state: Shared = Arc::new(Mutex::new(State::default()));
    let st = state.clone();
    let task = tokio::spawn(async move {
        let mut conns = tokio::task::JoinSet::new();
        while let Ok((stream, _)) = listener.accept().await {
            lock(&st).connections += 1;
            let st = st.clone();
            let tls = tls.clone();
            conns.spawn(async move {
                let svc = hyper::service::service_fn(move |req| handle(st.clone(), req));
                let builder = hyper::server::conn::http1::Builder::new();
                match tls {
                    None => {
                        let _ = builder.serve_connection(TokioIo::new(stream), svc).await;
                    }
                    Some(acc) => {
                        if let Ok(s) = acc.accept(stream).await {
                            let _ = builder.serve_connection(TokioIo::new(s), svc).await;
                        }
                    }
                }
            });
        }
    });
    Ok((local, state, task))
}

type Resp = Response<Full<Bytes>>;

fn reply(status: u16, body: Json) -> Resp {
    let mut r = Response::new(Full::new(Bytes::from(body.to_string())));
    *r.status_mut() = StatusCode::from_u16(status).unwrap_or(StatusCode::INTERNAL_SERVER_ERROR);
    r.headers_mut().insert(
        hyper::header::CONTENT_TYPE,
        hyper::header::HeaderValue::from_static("application/json"),
    );
    r
}

fn redirect(to: &str) -> Resp {
    let mut r = reply(302, json!({}));
    if let Ok(v) = hyper::header::HeaderValue::from_str(to) {
        r.headers_mut().insert(hyper::header::LOCATION, v);
    }
    r
}

fn authorized(auth: &SimAuth, seen: &Seen) -> bool {
    match auth {
        SimAuth::None => true,
        SimAuth::Basic(u, p) => {
            let want = base64::engine::general_purpose::STANDARD.encode(format!("{u}:{p}"));
            seen.header("authorization") == Some(&format!("Basic {want}"))
        }
        SimAuth::Bearer(t) => seen.header("authorization") == Some(&format!("Bearer {t}")),
        SimAuth::Header(n, v) => seen.header(n) == Some(v.as_str()),
        SimAuth::Query(n, v) => seen.query.split('&').any(|kv| kv == format!("{n}={v}")),
    }
}

/// Merge the members of `patch` (an object) into `into`.
fn merge(into: &mut Json, patch: Json) -> bool {
    match (into, patch) {
        (Json::Object(a), Json::Object(b)) => {
            a.extend(b);
            true
        }
        _ => false,
    }
}

async fn handle(st: Shared, req: Request<Incoming>) -> Result<Resp, std::convert::Infallible> {
    let (parts, body) = req.into_parts();
    let body = Limited::new(body, 1 << 20)
        .collect()
        .await
        .map(|b| b.to_bytes())
        .unwrap_or_default();
    let seen = Seen {
        method: parts.method.to_string(),
        path: parts.uri.path().to_owned(),
        query: parts.uri.query().unwrap_or_default().to_owned(),
        headers: parts
            .headers
            .iter()
            .map(|(k, v)| {
                (
                    k.as_str().to_owned(),
                    String::from_utf8_lossy(v.as_bytes()).into_owned(),
                )
            })
            .collect(),
        body: String::from_utf8_lossy(&body).into_owned(),
        at: tokio::time::Instant::now(),
    };
    let (slow, close, mode) = {
        let mut s = lock(&st);
        s.seen.push(seen.clone());
        (s.slow_ms, s.close, s.mode.clone())
    };
    if slow > 0 {
        tokio::time::sleep(Duration::from_millis(slow)).await;
    }
    let mut r = answer(&st, &seen, mode).await;
    if close {
        r.headers_mut().insert(
            hyper::header::CONNECTION,
            hyper::header::HeaderValue::from_static("close"),
        );
    }
    Ok(r)
}

async fn answer(st: &Shared, seen: &Seen, mode: Mode) -> Resp {
    let auth = lock(st).auth.clone();
    if !authorized(&auth, seen) {
        let mut r = reply(401, json!({"error": "unauthorized"}));
        r.headers_mut().insert(
            hyper::header::WWW_AUTHENTICATE,
            hyper::header::HeaderValue::from_static("Basic realm=\"sim\""),
        );
        r.headers_mut().insert(
            hyper::header::SET_COOKIE,
            hyper::header::HeaderValue::from_static("session=abc123; HttpOnly"),
        );
        return r;
    }
    match mode {
        Mode::Normal => {}
        Mode::Status(code) => return reply(code, json!({"error": "injected"})),
        Mode::Silent => std::future::pending::<()>().await,
        Mode::InvalidJson => {
            let mut r = reply(200, json!({}));
            *r.body_mut() = Full::new(Bytes::from_static(b"<html>not json</html>"));
            return r;
        }
        Mode::Huge(n) => {
            // `[0  …  ]`: exactly `n` bytes of JSON.
            let mut text = String::with_capacity(n.max(3));
            text.push_str("[0");
            text.extend(std::iter::repeat_n(' ', n.saturating_sub(3)));
            text.push(']');
            let mut r = reply(200, json!({}));
            *r.body_mut() = Full::new(Bytes::from(text));
            return r;
        }
    }
    let mut s = lock(st);
    match (seen.method.as_str(), seen.path.as_str()) {
        ("GET", "/api/data") => {
            if s.tick {
                let m = &mut s.data["meter"];
                let p = m["power"].as_f64().unwrap_or(0.0);
                m["power"] = json!(if p >= 1300.0 { 1200.5 } else { p + 10.0 });
                let e = m["energy"].as_u64().unwrap_or(0);
                m["energy"] = json!(e + 1);
            }
            reply(200, s.data.clone())
        }
        ("POST", "/api/query") => {
            let got: Json = serde_json::from_str(&seen.body).unwrap_or(Json::Null);
            reply(200, json!({"got": got, "data": s.data.clone()}))
        }
        ("GET", "/api/echo") => {
            let headers: serde_json::Map<String, Json> = seen
                .headers
                .iter()
                .map(|(k, v)| (k.clone(), Json::String(v.clone())))
                .collect();
            reply(200, json!({"headers": headers, "query": seen.query}))
        }
        ("GET", "/api/raw") => {
            let mut r = reply(200, json!({}));
            *r.body_mut() = Full::new(Bytes::from(s.raw.clone().unwrap_or_default()));
            r
        }
        ("GET", "/api/resource") => reply(200, s.resource.clone()),
        ("PUT" | "POST" | "PATCH", "/api/resource") => {
            let merged = serde_json::from_str::<Json>(&seen.body)
                .is_ok_and(|patch| merge(&mut s.resource, patch));
            if merged {
                reply(200, s.resource.clone())
            } else {
                reply(400, json!({"error": "expected a JSON object"}))
            }
        }
        ("GET", "/offsite") => redirect("http://other.invalid/api/data"),
        ("GET", p) if p.starts_with("/redirect/") => match p["/redirect/".len()..].parse::<u32>() {
            Ok(0) => redirect("/api/data"),
            Ok(n) => redirect(&format!("/redirect/{}", n - 1)),
            Err(_) => reply(404, json!({"error": "not found"})),
        },
        _ => reply(404, json!({"error": "not found"})),
    }
}
