//! A client of the WYRM user gateway (ADR 0009), as the explorer uses it:
//! `POST /api/login`, `POST /api/ws-ticket`, then the WebSocket CBOR
//! protocol of `wyrm-gateway` (`ws.rs`): one-shot requests (`meta`,
//! `children`, `set`, `invoke`, `history`) and `list`/`subscribe` streams.
//!
//! `https://host[:port]` (TLS by rustls/ring, the roots of `--ca` or the
//! public web roots) reaches a gateway anywhere; plain `http://` only one on
//! loopback, since the password goes in the clear (ADR 0041).

#![forbid(unsafe_code)]

use futures_util::{SinkExt, StreamExt};
use std::collections::{BTreeMap, HashMap};
use std::path::Path;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt};
use tokio::net::TcpStream;
use tokio::sync::{mpsc, oneshot};
use tokio_rustls::rustls;
use tokio_tungstenite::tungstenite::Message;
use tokio_tungstenite::WebSocketStream;
use wyrm_core::codec::{from_slice, to_vec};
use wyrm_core::status::StatusCode;
use wyrm_core::{NodeMeta, Status, Value};

/// How long a one-shot request waits for its reply.
pub const REQUEST_TIMEOUT: Duration = Duration::from_secs(15);

#[cfg(test)]
mod tests {
    use super::Endpoint;

    fn ep(url: &str) -> Result<Endpoint, super::Error> {
        Endpoint::parse(url, None)
    }

    #[test]
    fn plain_http_on_loopback_only() {
        assert_eq!(
            ep("http://127.0.0.1:8445").unwrap().authority(),
            "127.0.0.1:8445"
        );
        assert!(ep("localhost:8445").is_ok());
        assert!(ep("http://[::1]:8445/").is_ok());
        for bad in [
            "http://10.0.0.5:8445",
            "http://evil.example:80",
            "http://127.0.0.1:1/x",
            "ftp://127.0.0.1:1",
            "https://",
            "https://h:notaport",
        ] {
            assert!(ep(bad).is_err(), "{bad}");
        }
    }

    #[test]
    fn https_anywhere() {
        let e = ep("https://broker.example").unwrap();
        assert!(e.is_tls());
        assert_eq!(e.authority(), "broker.example:443");
        let e = ep("https://10.0.0.5:8445/").unwrap();
        assert_eq!(e.authority(), "10.0.0.5:8445");
        assert!(ep("https://[fd00::1]:8445").is_ok());
    }

    #[test]
    fn a_missing_ca_file_is_an_error() {
        let r = Endpoint::parse(
            "https://broker.example",
            Some(std::path::Path::new("/nonexistent/ca.pem")),
        );
        assert!(r.is_err());
    }
}

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("{0}")]
    Transport(String),
    /// An answer of the gateway or the broker: `status` (spec 04) and text.
    #[error("{status:?}: {message}")]
    Refused { status: StatusCode, message: String },
}

impl Error {
    pub fn is(&self, s: Status) -> bool {
        matches!(self, Error::Refused { status, .. } if *status == StatusCode::Known(s))
    }
}

fn transport(e: impl std::fmt::Display) -> Error {
    Error::Transport(e.to_string())
}

pub type Result<T> = std::result::Result<T, Error>;

/// A byte stream to the gateway: TCP or TLS over TCP.
trait Io: AsyncRead + AsyncWrite + Unpin + Send {}
impl<T: AsyncRead + AsyncWrite + Unpin + Send> Io for T {}
type BoxIo = Box<dyn Io>;

/// Where a gateway is and how to talk to it.
#[derive(Clone)]
pub struct Endpoint {
    /// Host as written (`[::1]` keeps its brackets) and port.
    host: String,
    port: u16,
    tls: Option<(
        tokio_rustls::TlsConnector,
        rustls::pki_types::ServerName<'static>,
    )>,
}

impl Endpoint {
    /// `https://host[:port]`, `http://host:port` or `host:port` (plain, both
    /// loopback only). `ca`: PEM roots for the gateway's certificate (a
    /// broker CA, a self-signed one); without it the public web roots.
    pub fn parse(url: &str, ca: Option<&Path>) -> Result<Self> {
        let (tls, rest) = if let Some(r) = url.strip_prefix("https://") {
            (true, r)
        } else if let Some(r) = url.strip_prefix("http://") {
            (false, r)
        } else if url.contains("://") {
            return Err(Error::Transport(format!(
                "gateway url {url}: https://host[:port] or http://127.0.0.1:<port>"
            )));
        } else {
            (false, url)
        };
        let hp = rest.trim_end_matches('/');
        if hp.is_empty() || hp.contains('/') {
            return Err(Error::Transport(format!(
                "gateway url {url}: https://host[:port] (no path)"
            )));
        }
        let (host, port) = match hp.rsplit_once(':') {
            // `[::1]` alone has colons inside the brackets only
            Some((h, p)) if !p.contains(']') => (
                h.to_owned(),
                p.parse::<u16>()
                    .map_err(|_| Error::Transport(format!("gateway url {url}: bad port")))?,
            ),
            _ if tls => (hp.to_owned(), 443),
            _ => {
                return Err(Error::Transport(format!(
                    "gateway url {url}: http://host:port"
                )))
            }
        };
        if host.is_empty() {
            return Err(Error::Transport(format!("gateway url {url}: no host")));
        }
        if !tls {
            // A password goes there in clear: loopback only, never a name
            // that could resolve elsewhere.
            if !matches!(host.as_str(), "127.0.0.1" | "localhost" | "[::1]") {
                return Err(Error::Transport(format!(
                    "gateway url {url}: plain HTTP only on loopback (127.0.0.1, localhost, [::1]); \
                     use https:// for a gateway on another host"
                )));
            }
            return Ok(Self {
                host,
                port,
                tls: None,
            });
        }
        let name = host
            .trim_start_matches('[')
            .trim_end_matches(']')
            .to_owned();
        let server_name = rustls::pki_types::ServerName::try_from(name)
            .map_err(|e| Error::Transport(format!("gateway url {url}: {e}")))?;
        let connector = tokio_rustls::TlsConnector::from(Arc::new(tls_config(ca)?));
        Ok(Self {
            host,
            port,
            tls: Some((connector, server_name)),
        })
    }

    pub fn is_tls(&self) -> bool {
        self.tls.is_some()
    }

    /// `host:port`.
    pub fn authority(&self) -> String {
        format!("{}:{}", self.host, self.port)
    }

    async fn open(&self) -> Result<BoxIo> {
        let addr = self.authority();
        let tcp = tokio::time::timeout(REQUEST_TIMEOUT, TcpStream::connect(&addr))
            .await
            .map_err(|_| Error::Transport(format!("{addr}: connect timed out")))?
            .map_err(|e| Error::Transport(format!("{addr}: {e}")))?;
        let _ = tcp.set_nodelay(true);
        match &self.tls {
            None => Ok(Box::new(tcp)),
            Some((c, name)) => {
                let s = tokio::time::timeout(REQUEST_TIMEOUT, c.connect(name.clone(), tcp))
                    .await
                    .map_err(|_| Error::Transport(format!("{addr}: TLS handshake timed out")))?
                    .map_err(|e| Error::Transport(format!("{addr}: TLS: {e}")))?;
                Ok(Box::new(s))
            }
        }
    }
}

/// rustls on ring, HTTP/1.1 only (WebSockets need it).
fn tls_config(ca: Option<&Path>) -> Result<rustls::ClientConfig> {
    use rustls::pki_types::{pem::PemObject, CertificateDer};
    let mut roots = rustls::RootCertStore::empty();
    match ca {
        Some(path) => {
            let certs = CertificateDer::pem_file_iter(path)
                .map_err(|e| Error::Transport(format!("{}: {e}", path.display())))?
                .collect::<std::result::Result<Vec<_>, _>>()
                .map_err(|e| Error::Transport(format!("{}: {e}", path.display())))?;
            if certs.is_empty() {
                return Err(Error::Transport(format!(
                    "{}: no PEM certificate",
                    path.display()
                )));
            }
            for c in certs {
                roots
                    .add(c)
                    .map_err(|e| Error::Transport(format!("{}: {e}", path.display())))?;
            }
        }
        None => roots.extend(webpki_roots::TLS_SERVER_ROOTS.iter().cloned()),
    }
    let mut cfg = rustls::ClientConfig::builder_with_provider(Arc::new(
        rustls::crypto::ring::default_provider(),
    ))
    .with_safe_default_protocol_versions()
    .map_err(transport)?
    .with_root_certificates(roots)
    .with_no_client_auth();
    cfg.alpn_protocols = vec![b"http/1.1".to_vec()];
    Ok(cfg)
}

/// One HTTP/1.1 request with a CBOR body (head and body in one write, so a
/// refusal before the body is read still reaches us); the status and the
/// CBOR answer. `body: None` sends a `GET`.
async fn http(
    ep: &Endpoint,
    path: &str,
    bearer: Option<&str>,
    body: Option<&Value>,
) -> Result<(u16, Value)> {
    let host = ep.authority();
    let mut msg = match body {
        Some(_) => format!("POST {path} HTTP/1.1\r\nHost: {host}\r\nConnection: close\r\n"),
        None => format!("GET {path} HTTP/1.1\r\nHost: {host}\r\nConnection: close\r\nAccept: application/cbor\r\n"),
    };
    let body = match body {
        Some(b) => {
            let b = to_vec(b).map_err(transport)?;
            msg.push_str(&format!(
                "Content-Type: application/cbor\r\nContent-Length: {}\r\n",
                b.len()
            ));
            b
        }
        None => Vec::new(),
    };
    if let Some(t) = bearer {
        msg.push_str(&format!("Authorization: Bearer {t}\r\n"));
    }
    msg.push_str("\r\n");
    let mut msg = msg.into_bytes();
    msg.extend_from_slice(&body);
    let mut s = ep.open().await?;
    s.write_all(&msg).await.map_err(transport)?;
    s.flush().await.map_err(transport)?;
    let mut resp = Vec::new();
    match tokio::time::timeout(REQUEST_TIMEOUT, s.read_to_end(&mut resp)).await {
        Err(_) => return Err(Error::Transport(format!("{path}: no answer"))),
        Ok(Ok(_)) => {}
        // a TLS peer that closes without close_notify: what came is the answer
        Ok(Err(e)) if e.kind() == std::io::ErrorKind::UnexpectedEof && !resp.is_empty() => {}
        Ok(Err(e)) => return Err(transport(e)),
    }
    let split = resp
        .windows(4)
        .position(|w| w == b"\r\n\r\n")
        .ok_or_else(|| Error::Transport(format!("{path}: not HTTP")))?;
    let head = String::from_utf8_lossy(&resp[..split]);
    let status: u16 = head
        .split(' ')
        .nth(1)
        .and_then(|s| s.parse().ok())
        .ok_or_else(|| Error::Transport(format!("{path}: no status")))?;
    let v = from_slice(&resp[split + 4..]).unwrap_or(Value::Null);
    Ok((status, v))
}

fn text_field(v: &Value, k: &str) -> Option<String> {
    match v {
        Value::Map(m) => match m.get(k) {
            Some(Value::Str(s)) => Some(s.clone()),
            _ => None,
        },
        _ => None,
    }
}

/// A logged-in user of one gateway.
#[derive(Clone)]
pub struct Gateway {
    ep: Endpoint,
    session: String,
}

/// `GET /api/me`: who the session is and what it may do.
#[derive(Debug, Clone, PartialEq)]
pub struct Me {
    pub sub: String,
    pub roles: Vec<String>,
    /// `(key pattern, level)` per grant.
    pub grants: Vec<(String, String)>,
    /// The highest level of any grant (`none`, `list`, `read`, `write`, `config`).
    pub max: String,
    /// Session expiry, seconds since the Unix epoch.
    pub exp: u64,
    /// The site the gateway serves.
    pub site: String,
}

impl Gateway {
    /// Log in at `url` (see [`Endpoint::parse`]), public web roots for TLS.
    pub async fn login(url: &str, user: &str, password: &str) -> Result<Self> {
        Self::login_at(Endpoint::parse(url, None)?, user, password).await
    }

    pub async fn login_at(ep: Endpoint, user: &str, password: &str) -> Result<Self> {
        let body = Value::Map(BTreeMap::from([
            ("user".to_owned(), Value::from(user)),
            ("password".to_owned(), Value::from(password)),
        ]));
        let (st, v) = http(&ep, "/api/login", None, Some(&body)).await?;
        match (st, text_field(&v, "session")) {
            (200, Some(session)) => Ok(Self { ep, session }),
            (401 | 403, _) => Err(Error::Refused {
                status: StatusCode::Known(Status::PermissionDenied),
                message: format!(
                    "login as {user}: wrong user or password, or the user is disabled"
                ),
            }),
            (429, _) => Err(Error::Refused {
                status: StatusCode::Known(Status::RateLimited),
                message: format!("login as {user}: too many failed logins, wait a minute"),
            }),
            _ => Err(Error::Transport(format!("login as {user}: HTTP {st}"))),
        }
    }

    pub async fn me(&self) -> Result<Me> {
        let (st, v) = http(&self.ep, "/api/me", Some(&self.session), None).await?;
        if st != 200 {
            return Err(Error::Transport(format!("/api/me: HTTP {st}")));
        }
        let Value::Map(m) = &v else {
            return Err(Error::Transport("/api/me: not a map".into()));
        };
        let strs = |k: &str| match m.get(k) {
            Some(Value::Array(a)) => a
                .iter()
                .filter_map(|x| match x {
                    Value::Str(s) => Some(s.clone()),
                    _ => None,
                })
                .collect(),
            _ => Vec::new(),
        };
        let grants = match m.get("grants") {
            Some(Value::Array(a)) => a
                .iter()
                .filter_map(|g| Some((text_field(g, "k")?, text_field(g, "p")?)))
                .collect(),
            _ => Vec::new(),
        };
        Ok(Me {
            sub: text_field(&v, "sub").unwrap_or_default(),
            roles: strs("roles"),
            grants,
            max: text_field(&v, "max").unwrap_or_default(),
            exp: match m.get("exp") {
                Some(Value::UInt(e)) => *e,
                _ => 0,
            },
            site: text_field(&v, "site").unwrap_or_default(),
        })
    }

    /// A WebSocket connection (one ticket each).
    pub async fn connect(&self) -> Result<Conn> {
        let (st, v) = http(
            &self.ep,
            "/api/ws-ticket",
            Some(&self.session),
            Some(&Value::Map(BTreeMap::new())),
        )
        .await?;
        let ticket = match (st, text_field(&v, "ticket")) {
            (200, Some(t)) => t,
            _ => return Err(Error::Transport(format!("ws ticket: HTTP {st}"))),
        };
        let scheme = if self.ep.is_tls() { "wss" } else { "ws" };
        let url = format!("{scheme}://{}/api/ws?ticket={ticket}", self.ep.authority());
        let io = self.ep.open().await?;
        let (ws, _) =
            tokio::time::timeout(REQUEST_TIMEOUT, tokio_tungstenite::client_async(url, io))
                .await
                .map_err(|_| Error::Transport("websocket handshake timed out".into()))?
                .map_err(transport)?;
        Ok(Conn::start(ws))
    }
}

enum Pending {
    Once(oneshot::Sender<Value>),
    Stream {
        started: Option<oneshot::Sender<Value>>,
        events: mpsc::UnboundedSender<Event>,
    },
}

type Table = Arc<Mutex<HashMap<u64, Pending>>>;

/// One WebSocket connection: requests and streams by request id.
pub struct Conn {
    out: mpsc::UnboundedSender<Message>,
    pending: Table,
    next: AtomicU64,
    tasks: Vec<tokio::task::JoinHandle<()>>,
}

impl Drop for Conn {
    fn drop(&mut self) {
        for t in &self.tasks {
            t.abort();
        }
    }
}

/// One event of a `list` or `subscribe` stream.
#[derive(Debug, Clone, PartialEq)]
pub enum Event {
    Refreshed(Vec<(String, NodeMeta)>),
    Added(String, NodeMeta),
    Changed(String, NodeMeta),
    Removed(String),
    Connected(String),
    Disconnected(Option<String>),
    Sample {
        key: String,
        v: Value,
        q: String,
        t: u64,
    },
    SampleRemoved(String),
    /// The stream ended on the broker's side, or the connection did.
    Closed,
    Other(Value),
}

fn meta_of(v: Option<&Value>) -> NodeMeta {
    match v {
        Some(Value::Bytes(b)) => from_slice(b).unwrap_or_default(),
        _ => NodeMeta::default(),
    }
}

fn event_of(ev: Value) -> Event {
    let Value::Map(m) = &ev else {
        return Event::Other(ev);
    };
    let s = |k: &str| match m.get(k) {
        Some(Value::Str(s)) => Some(s.clone()),
        _ => None,
    };
    match s("type").as_deref() {
        Some("refreshed") => {
            let kids = match m.get("children") {
                Some(Value::Array(a)) => a
                    .iter()
                    .filter_map(|c| match c {
                        Value::Map(c) => match c.get("name") {
                            Some(Value::Str(n)) => Some((n.clone(), meta_of(c.get("meta")))),
                            _ => None,
                        },
                        _ => None,
                    })
                    .collect(),
                _ => Vec::new(),
            };
            Event::Refreshed(kids)
        }
        Some("added") => Event::Added(s("name").unwrap_or_default(), meta_of(m.get("meta"))),
        Some("changed") => Event::Changed(s("name").unwrap_or_default(), meta_of(m.get("meta"))),
        Some("removed") if m.contains_key("key") => {
            Event::SampleRemoved(s("key").unwrap_or_default())
        }
        Some("removed") => Event::Removed(s("name").unwrap_or_default()),
        Some("connected") => Event::Connected(s("name").unwrap_or_default()),
        Some("disconnected") => Event::Disconnected(s("name")),
        Some("sample") => Event::Sample {
            key: s("key").unwrap_or_default(),
            v: m.get("v").cloned().unwrap_or(Value::Null),
            q: s("q").unwrap_or_default(),
            t: match m.get("t") {
                Some(Value::UInt(t)) => *t,
                _ => 0,
            },
        },
        Some("closed") => Event::Closed,
        _ => Event::Other(ev),
    }
}

/// The final frame of a request: its `result`, or the error it carries.
fn outcome(frame: Value) -> Result<Option<Value>> {
    let Value::Map(mut m) = frame else {
        return Err(Error::Transport("frame is not a map".into()));
    };
    if m.get("ok") == Some(&Value::Bool(true)) {
        return Ok(m.remove("result"));
    }
    let (status, message) = match m.remove("error") {
        Some(Value::Map(e)) => (
            match e.get("status") {
                Some(Value::UInt(c)) => u8::try_from(*c).unwrap_or(u8::MAX),
                _ => u8::MAX,
            },
            match e.get("message") {
                Some(Value::Str(s)) => s.clone(),
                _ => String::new(),
            },
        ),
        _ => (u8::MAX, String::new()),
    };
    Err(Error::Refused {
        status: StatusCode::from(status),
        message,
    })
}

/// A `list` or `subscribe` stream; dropping it does not end it on the
/// gateway (call [`Conn::unsubscribe`]).
pub struct Stream {
    pub id: u64,
    events: mpsc::UnboundedReceiver<Event>,
}

impl Stream {
    pub async fn next(&mut self) -> Option<Event> {
        self.events.recv().await
    }
}

impl Conn {
    /// A connection over a byte stream that already carries the WebSocket
    /// protocol, without an HTTP handshake: the in-process pipe of the
    /// gateway's own MCP endpoint (ADR 0041).
    pub async fn from_raw<S: AsyncRead + AsyncWrite + Unpin + Send + 'static>(io: S) -> Self {
        let ws = WebSocketStream::from_raw_socket(
            io,
            tokio_tungstenite::tungstenite::protocol::Role::Client,
            None,
        )
        .await;
        Self::start(ws)
    }

    fn start<S: AsyncRead + AsyncWrite + Unpin + Send + 'static>(ws: WebSocketStream<S>) -> Self {
        let (mut sink, mut source) = ws.split();
        let (out, mut rx) = mpsc::unbounded_channel::<Message>();
        let pending: Table = Arc::new(Mutex::new(HashMap::new()));
        let writer = tokio::spawn(async move {
            while let Some(m) = rx.recv().await {
                if sink.send(m).await.is_err() {
                    return;
                }
            }
        });
        let table = pending.clone();
        let reader = tokio::spawn(async move {
            while let Some(Ok(m)) = source.next().await {
                let Message::Binary(b) = m else {
                    continue;
                };
                let Ok(Value::Map(f)) = from_slice::<Value>(&b) else {
                    continue;
                };
                let Some(Value::UInt(id)) = f.get("id").cloned() else {
                    continue;
                };
                let mut t = table.lock().unwrap_or_else(|p| p.into_inner());
                if let Some(ev) = f.get("event").cloned() {
                    let ev = event_of(ev);
                    let closed = ev == Event::Closed;
                    if let Some(Pending::Stream { events, .. }) = t.get(&id) {
                        let _ = events.send(ev);
                    }
                    if closed {
                        t.remove(&id);
                    }
                    continue;
                }
                match t.get_mut(&id) {
                    Some(Pending::Once(_)) => {
                        if let Some(Pending::Once(tx)) = t.remove(&id) {
                            let _ = tx.send(Value::Map(f));
                        }
                    }
                    Some(Pending::Stream { started, .. }) => {
                        let ok = f.get("ok") == Some(&Value::Bool(true));
                        if let Some(tx) = started.take() {
                            let _ = tx.send(Value::Map(f));
                        }
                        if !ok {
                            t.remove(&id);
                        }
                    }
                    None => {}
                }
            }
            // the connection is gone: every stream ends, every request fails
            let mut t = table.lock().unwrap_or_else(|p| p.into_inner());
            for (_, p) in t.drain() {
                if let Pending::Stream { events, .. } = p {
                    let _ = events.send(Event::Closed);
                }
            }
        });
        Self {
            out,
            pending,
            next: AtomicU64::new(1),
            tasks: vec![writer, reader],
        }
    }

    fn send(&self, id: u64, op: &str, key: &str, extra: Vec<(&str, Value)>) -> Result<()> {
        let mut m = BTreeMap::from([
            ("id".to_owned(), Value::UInt(id)),
            ("op".to_owned(), Value::from(op)),
        ]);
        if !key.is_empty() {
            m.insert("key".into(), Value::from(key));
        }
        for (k, v) in extra {
            m.insert(k.to_owned(), v);
        }
        let bytes = to_vec(&Value::Map(m)).map_err(transport)?;
        self.out
            .send(Message::Binary(bytes.into()))
            .map_err(|_| Error::Transport("connection closed".into()))
    }

    /// A one-shot request; its `result`.
    pub async fn request(
        &self,
        op: &str,
        key: &str,
        extra: Vec<(&str, Value)>,
    ) -> Result<Option<Value>> {
        let id = self.next.fetch_add(1, Ordering::Relaxed);
        let (tx, rx) = oneshot::channel();
        self.lock().insert(id, Pending::Once(tx));
        self.send(id, op, key, extra)?;
        let frame = tokio::time::timeout(REQUEST_TIMEOUT, rx)
            .await
            .map_err(|_| {
                self.lock().remove(&id);
                Error::Refused {
                    status: StatusCode::Known(Status::Timeout),
                    message: format!("{op} {key}: no answer"),
                }
            })?
            .map_err(|_| Error::Transport("connection closed".into()))?;
        outcome(frame)
    }

    /// Open a `list` or `subscribe` stream (after the gateway's `ok`).
    pub async fn stream(&self, op: &str, key: &str) -> Result<Stream> {
        let id = self.next.fetch_add(1, Ordering::Relaxed);
        let (tx, rx) = oneshot::channel();
        let (etx, erx) = mpsc::unbounded_channel();
        self.lock().insert(
            id,
            Pending::Stream {
                started: Some(tx),
                events: etx,
            },
        );
        self.send(id, op, key, Vec::new())?;
        let frame = tokio::time::timeout(REQUEST_TIMEOUT, rx)
            .await
            .map_err(|_| {
                self.lock().remove(&id);
                Error::Refused {
                    status: StatusCode::Known(Status::Timeout),
                    message: format!("{op} {key}: no answer"),
                }
            })?
            .map_err(|_| Error::Transport("connection closed".into()))?;
        outcome(frame)?;
        Ok(Stream { id, events: erx })
    }

    /// End a stream on the gateway.
    pub async fn unsubscribe(&self, stream: u64) -> Result<()> {
        self.lock().remove(&stream);
        self.request("unsubscribe", "", vec![("sub", Value::UInt(stream))])
            .await
            .map(|_| ())
    }

    /// The socket is gone (closed by the gateway, an expired or revoked
    /// session, the network): open a new one.
    pub fn is_closed(&self) -> bool {
        self.out.is_closed() || self.tasks.iter().any(|t| t.is_finished())
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, HashMap<u64, Pending>> {
        self.pending.lock().unwrap_or_else(|p| p.into_inner())
    }

    pub async fn meta(&self, key: &str) -> Result<NodeMeta> {
        Ok(meta_of(
            self.request("meta", key, Vec::new()).await?.as_ref(),
        ))
    }

    pub async fn children(&self, key: &str) -> Result<Vec<(String, NodeMeta)>> {
        match self.request("children", key, Vec::new()).await? {
            Some(Value::Array(a)) => Ok(a
                .into_iter()
                .filter_map(|c| match c {
                    Value::Map(c) => match c.get("name") {
                        Some(Value::Str(n)) => Some((n.clone(), meta_of(c.get("meta")))),
                        _ => None,
                    },
                    _ => None,
                })
                .collect()),
            _ => Ok(Vec::new()),
        }
    }

    pub async fn set(&self, key: &str, v: Value) -> Result<()> {
        self.request("set", key, vec![("value", v)])
            .await
            .map(|_| ())
    }

    pub async fn invoke(&self, key: &str, action: &str, args: Value) -> Result<Option<Value>> {
        self.request(
            "invoke",
            key,
            vec![("action", Value::from(action)), ("args", args)],
        )
        .await
    }

    /// `check` (spec 05 0.2.33): the responder checks the call as the action would take it and
    /// does nothing; only where its root `~meta` has `attr.check`.
    pub async fn check(&self, key: &str, action: &str, args: Value) -> Result<()> {
        self.request(
            "check",
            key,
            vec![("action", Value::from(action)), ("args", args)],
        )
        .await
        .map(|_| ())
    }

    pub async fn list(&self, key: &str) -> Result<Stream> {
        self.stream("list", key).await
    }

    pub async fn subscribe(&self, pattern: &str) -> Result<Stream> {
        self.stream("subscribe", pattern).await
    }
}
