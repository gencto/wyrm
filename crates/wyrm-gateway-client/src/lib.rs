//! A client of the WYRM user gateway (ADR 0009), as the explorer uses it:
//! `POST /api/login`, `POST /api/ws-ticket`, then the WebSocket CBOR
//! protocol of `wyrm-gateway` (`ws.rs`): one-shot requests (`meta`,
//! `children`, `set`, `invoke`, `history`) and `list`/`subscribe` streams.
//!
//! Plain `http://` only: the gateway serves plain HTTP on loopback alone,
//! so this client is for tools on the broker's host (tests, the probe link).

#![forbid(unsafe_code)]

use futures_util::{SinkExt, StreamExt};
use std::collections::{BTreeMap, HashMap};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use tokio::sync::{mpsc, oneshot};
use tokio_tungstenite::tungstenite::Message;
use wyrm_core::codec::{from_slice, to_vec};
use wyrm_core::status::StatusCode;
use wyrm_core::{NodeMeta, Status, Value};

/// How long a one-shot request waits for its reply.
pub const REQUEST_TIMEOUT: Duration = Duration::from_secs(15);

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

/// `http://host:port` or `host:port` → `host:port`.
fn host_port(url: &str) -> Result<String> {
    if url.starts_with("https://") {
        return Err(Error::Transport(
            "https is not supported: use the gateway on loopback (http://127.0.0.1:<port>)".into(),
        ));
    }
    let hp = url.trim_start_matches("http://").trim_end_matches('/');
    if hp.is_empty() || hp.contains('/') {
        return Err(Error::Transport(format!(
            "gateway url {url}: http://host:port"
        )));
    }
    Ok(hp.to_owned())
}

/// One HTTP/1.1 request with a CBOR body (head and body in one write, so a
/// refusal before the body is read still reaches us); the status and the
/// CBOR answer.
async fn http(addr: &str, path: &str, bearer: Option<&str>, body: &Value) -> Result<(u16, Value)> {
    let body = to_vec(body).map_err(transport)?;
    let mut msg = format!(
        "POST {path} HTTP/1.1\r\nHost: {addr}\r\nConnection: close\r\nContent-Type: application/cbor\r\nContent-Length: {}\r\n",
        body.len()
    );
    if let Some(t) = bearer {
        msg.push_str(&format!("Authorization: Bearer {t}\r\n"));
    }
    msg.push_str("\r\n");
    let mut msg = msg.into_bytes();
    msg.extend_from_slice(&body);
    let mut s = tokio::time::timeout(REQUEST_TIMEOUT, TcpStream::connect(addr))
        .await
        .map_err(|_| Error::Transport(format!("{addr}: connect timed out")))?
        .map_err(|e| Error::Transport(format!("{addr}: {e}")))?;
    s.write_all(&msg).await.map_err(transport)?;
    let mut resp = Vec::new();
    tokio::time::timeout(REQUEST_TIMEOUT, s.read_to_end(&mut resp))
        .await
        .map_err(|_| Error::Transport(format!("{path}: no answer")))?
        .map_err(transport)?;
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
    addr: String,
    session: String,
}

impl Gateway {
    pub async fn login(url: &str, user: &str, password: &str) -> Result<Self> {
        let addr = host_port(url)?;
        let body = Value::Map(BTreeMap::from([
            ("user".to_owned(), Value::from(user)),
            ("password".to_owned(), Value::from(password)),
        ]));
        let (st, v) = http(&addr, "/api/login", None, &body).await?;
        match (st, text_field(&v, "session")) {
            (200, Some(session)) => Ok(Self { addr, session }),
            _ => Err(Error::Transport(format!("login as {user}: HTTP {st}"))),
        }
    }

    /// A WebSocket connection (one ticket each).
    pub async fn connect(&self) -> Result<Conn> {
        let (st, v) = http(
            &self.addr,
            "/api/ws-ticket",
            Some(&self.session),
            &Value::Map(BTreeMap::new()),
        )
        .await?;
        let ticket = match (st, text_field(&v, "ticket")) {
            (200, Some(t)) => t,
            _ => return Err(Error::Transport(format!("ws ticket: HTTP {st}"))),
        };
        let url = format!("ws://{}/api/ws?ticket={ticket}", self.addr);
        let (ws, _) = tokio_tungstenite::connect_async(url)
            .await
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
    fn start(
        ws: tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<TcpStream>>,
    ) -> Self {
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

    pub async fn list(&self, key: &str) -> Result<Stream> {
        self.stream("list", key).await
    }

    pub async fn subscribe(&self, pattern: &str) -> Result<Stream> {
        self.stream("subscribe", pattern).await
    }
}
