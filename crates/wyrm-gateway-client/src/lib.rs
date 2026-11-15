//! A client of the WYRM user gateway (ADR 0009), as the explorer uses it:
//! `POST /api/login`, `POST /api/ws-ticket`, then the WebSocket CBOR
//! protocol of `wyrm-gateway` (`ws.rs`): one-shot requests (`meta`,
//! `children`, `set`, `invoke`, `history`) and `list`/`subscribe` streams.
//!
//! An invoke whose encoded arguments are over [`MAX_FRAME_ARGS`] (a file or a
//! part of one) goes by `POST /api/invoke` instead, with the session bearer and
//! `Expect: 100-continue`, so a refusal arrives before the body is sent (ADR
//! 0011, ADR 0028 amendment); every other frame over [`MAX_FRAME`] is refused
//! here, before it would close the socket.
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

/// Largest frame the gateway reads (`wyrm-gateway` `ws::MAX_FRAME`).
pub const MAX_FRAME: usize = 64 * 1024;
/// Largest encoded `args` an invoke sends in a frame (the rest of the frame
/// is the request around them); larger ones go by `POST /api/invoke`, as the
/// Dart client's `maxFrameArgs`.
pub const MAX_FRAME_ARGS: usize = 60 * 1024;
/// Largest body of `POST /api/invoke` (`wyrm-gateway` takes this one).
pub const MAX_INVOKE_BODY: usize = (64 << 20) + (64 << 10);
/// How long `POST /api/invoke` waits for `100 Continue` (or a refusal)
/// before it sends the body anyway (RFC 9110 §10.1.1).
const CONTINUE_WAIT: Duration = Duration::from_secs(10);
/// Sending a body: the gateway reads one within 120 s.
const BODY_TIMEOUT: Duration = Duration::from_secs(125);
/// The answer after the body: the gateway waits up to 180 s for the action.
const ANSWER_TIMEOUT: Duration = Duration::from_secs(185);
/// Largest response head read.
const MAX_HEAD: usize = 64 * 1024;

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
    fn query_values_are_escaped() {
        assert_eq!(
            super::query_value("wy/s/downstream/a-b_c.d~e"),
            "wy/s/downstream/a-b_c.d~e"
        );
        assert_eq!(super::query_value("a b+c&d=é"), "a%20b%2Bc%26d%3D%C3%A9");
    }

    #[test]
    fn bulk_answers() {
        use super::{bulk_answer, Error};
        use wyrm_core::codec::to_vec;
        use wyrm_core::{Status, Value};
        let resp = |head: &str, body: Value| {
            let mut b = head.as_bytes().to_vec();
            b.extend(to_vec(&body).unwrap());
            b
        };
        let ok = Value::Map([("result".to_owned(), Value::UInt(5))].into());
        // an interim head is skipped
        let r = resp("HTTP/1.1 100 Continue\r\n\r\nHTTP/1.1 200 OK\r\n\r\n", ok);
        assert_eq!(bulk_answer("put", &r).unwrap(), Some(Value::UInt(5)));
        let none = Value::Map([("result".to_owned(), Value::Null)].into());
        let r = resp("HTTP/1.1 200 OK\r\n\r\n", none);
        assert_eq!(bulk_answer("put", &r).unwrap(), None);
        let refused = Value::Map(
            [
                (
                    "status".to_owned(),
                    Value::UInt(Status::PermissionDenied.code().into()),
                ),
                ("message".to_owned(), Value::from("not authenticated")),
            ]
            .into(),
        );
        let r = resp("HTTP/1.1 401 Unauthorized\r\n\r\n", refused);
        match bulk_answer("put", &r).unwrap_err() {
            e @ Error::Refused {
                http: Some(401), ..
            } => {
                assert!(e.is(Status::PermissionDenied));
                assert!(e.to_string().contains("not authenticated"), "{e}");
                assert!(e.to_string().contains("log in again"), "{e}");
            }
            e => panic!("{e:?}"),
        }
        // no CBOR body: the HTTP status decides
        let r = b"HTTP/1.1 503 Service Unavailable\r\n\r\n".to_vec();
        let e = bulk_answer("put", &r).unwrap_err();
        assert!(e.is(Status::Busy), "{e:?}");
        assert!(bulk_answer("put", b"garbage").is_err());
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
    /// An answer of the gateway or the broker: `status` (spec 04) and text;
    /// `http` is the HTTP status of a refusal of an HTTP request
    /// (`POST /api/invoke`), `None` for one in a WebSocket frame.
    #[error("{status:?}: {message}")]
    Refused {
        status: StatusCode,
        message: String,
        http: Option<u16>,
    },
    /// Nothing was sent: `size` bytes are over `limit`, the most the request
    /// can carry on the route it has; `hint` says what to do.
    #[error("{what}: {size} bytes, over {limit} bytes: {hint}")]
    TooLarge {
        what: String,
        size: usize,
        limit: usize,
        hint: &'static str,
    },
}

impl Error {
    pub fn is(&self, s: Status) -> bool {
        matches!(self, Error::Refused { status, .. } if *status == StatusCode::Known(s))
    }

    /// Refused here as [`Error::TooLarge`], before anything was sent.
    pub fn is_too_large(&self) -> bool {
        matches!(self, Error::TooLarge { .. })
    }

    fn refused(status: Status, message: String) -> Self {
        Error::Refused {
            status: StatusCode::Known(status),
            message,
            http: None,
        }
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
            (401 | 403, _) => Err(Error::refused(
                Status::PermissionDenied,
                format!("login as {user}: wrong user or password, or the user is disabled"),
            )),
            (429, _) => Err(Error::refused(
                Status::RateLimited,
                format!("login as {user}: too many failed logins, wait a minute"),
            )),
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
        let bulk = Bulk {
            ep: self.ep.clone(),
            session: self.session.clone(),
        };
        Ok(Conn::start(ws, Some(bulk)))
    }
}

/// The HTTP route of a [`Conn`] for invokes larger than a frame. No `Debug`:
/// it holds the session bearer.
#[derive(Clone)]
struct Bulk {
    ep: Endpoint,
    session: String,
}

/// `s` for a query value: unreserved characters and `/` as they are, every
/// other byte `%XX` (a `+` would read as a space).
fn query_value(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for b in s.bytes() {
        if b.is_ascii_alphanumeric() || matches!(b, b'-' | b'_' | b'.' | b'~' | b'/') {
            out.push(char::from(b));
        } else {
            out.push_str(&format!("%{b:02X}"));
        }
    }
    out
}

/// The end of the first response head in `buf` (after its blank line).
fn head_end(buf: &[u8]) -> Option<usize> {
    buf.windows(4).position(|w| w == b"\r\n\r\n").map(|i| i + 4)
}

/// The status of a response head.
fn head_status(head: &[u8]) -> Option<u16> {
    String::from_utf8_lossy(head)
        .split(' ')
        .nth(1)
        .and_then(|s| s.parse().ok())
}

/// Read into `buf` until it holds a whole response head; its end.
async fn read_head(s: &mut BoxIo, buf: &mut Vec<u8>) -> std::io::Result<usize> {
    let mut chunk = [0u8; 4096];
    loop {
        if let Some(n) = head_end(buf) {
            return Ok(n);
        }
        if buf.len() > MAX_HEAD {
            return Err(std::io::Error::other("response head too long"));
        }
        let n = s.read(&mut chunk).await?;
        if n == 0 {
            return Err(std::io::ErrorKind::UnexpectedEof.into());
        }
        buf.extend_from_slice(&chunk[..n]);
    }
}

/// Read the rest of the answer into `buf` (to its close, at most
/// [`MAX_INVOKE_BODY`] in all) within `wait`.
async fn read_rest(s: &mut BoxIo, buf: &mut Vec<u8>, wait: Duration) -> Result<()> {
    let cap = (MAX_INVOKE_BODY + MAX_HEAD).saturating_sub(buf.len()) as u64;
    let mut rest = Vec::new();
    let r = tokio::time::timeout(wait, s.take(cap).read_to_end(&mut rest)).await;
    buf.extend_from_slice(&rest);
    match r {
        Err(_) => Err(Error::Transport("POST /api/invoke: no answer".into())),
        Ok(Ok(_)) => Ok(()),
        // a TLS peer that closes without close_notify: what came is the answer
        Ok(Err(e)) if e.kind() == std::io::ErrorKind::UnexpectedEof => Ok(()),
        Ok(Err(e)) => Err(transport(e)),
    }
}

/// A whole response in `buf` (interim `1xx` heads skipped): the invoke's
/// result, or the gateway's refusal.
fn bulk_answer(action: &str, buf: &[u8]) -> Result<Option<Value>> {
    let mut at = 0;
    let (st, body) = loop {
        let n = head_end(&buf[at..])
            .ok_or_else(|| Error::Transport(format!("POST /api/invoke {action}: not HTTP")))?;
        let st = head_status(&buf[at..at + n])
            .ok_or_else(|| Error::Transport(format!("POST /api/invoke {action}: no status")))?;
        if (100..200).contains(&st) {
            at += n;
            continue;
        }
        break (st, &buf[at + n..]);
    };
    let v = from_slice::<Value>(body).unwrap_or(Value::Null);
    if st == 200 {
        return Ok(match v {
            Value::Map(mut m) => m.remove("result").filter(|r| *r != Value::Null),
            _ => None,
        });
    }
    // `{status, message}` of the gateway, or only the HTTP status
    let (code, text) = match &v {
        Value::Map(m) => (
            match m.get("status") {
                Some(Value::UInt(c)) => u8::try_from(*c).ok(),
                _ => None,
            },
            text_field(&v, "message"),
        ),
        _ => (None, None),
    };
    let status = match code {
        Some(c) => StatusCode::from(c),
        None => StatusCode::Known(match st {
            401 | 403 => Status::PermissionDenied,
            408 => Status::Timeout,
            413 => Status::InvalidParameter,
            429 => Status::RateLimited,
            503 => Status::Busy,
            _ => Status::InternalError,
        }),
    };
    let text = text.unwrap_or_else(|| format!("HTTP {st}"));
    let message = if st == 401 {
        format!("POST /api/invoke {action}: {text}: the session ended, log in again")
    } else {
        format!("POST /api/invoke {action}: {text}")
    };
    Err(Error::Refused {
        status,
        message,
        http: Some(st),
    })
}

/// `POST /api/invoke?key=…&action=…` with `body` (the CBOR `args`) and
/// `Expect: 100-continue`: the gateway checks the key, the file parameter, the
/// level and the session before it asks for the body, so a refusal comes back
/// without the body sent. Without an interim answer in [`CONTINUE_WAIT`] the
/// body goes anyway.
async fn bulk_invoke(b: &Bulk, key: &str, action: &str, body: &[u8]) -> Result<Option<Value>> {
    let head = format!(
        "POST /api/invoke?key={}&action={} HTTP/1.1\r\nHost: {}\r\nConnection: close\r\n\
         Content-Type: application/cbor\r\nContent-Length: {}\r\nAccept: application/cbor\r\n\
         Expect: 100-continue\r\nAuthorization: Bearer {}\r\n\r\n",
        query_value(key),
        query_value(action),
        b.ep.authority(),
        body.len(),
        b.session,
    );
    let mut s = b.ep.open().await?;
    let sent = |what: &str, e: &dyn std::fmt::Display| {
        Error::Transport(format!(
            "POST /api/invoke {action}: {what} ({e}); log in again if the session ended, or try again"
        ))
    };
    tokio::time::timeout(REQUEST_TIMEOUT, async {
        s.write_all(head.as_bytes()).await?;
        s.flush().await
    })
    .await
    .map_err(|_| sent("the request head was not taken", &"timed out"))?
    .map_err(|e| sent("the request head was not taken", &e))?;
    let mut buf = Vec::new();
    match tokio::time::timeout(CONTINUE_WAIT, read_head(&mut s, &mut buf)).await {
        // `100 Continue`: the body is wanted
        Ok(Ok(n)) if head_status(&buf[..n]) == Some(100) => {
            buf.drain(..n);
        }
        // the answer before the body: a refusal (or an early result)
        Ok(Ok(_)) => {
            read_rest(&mut s, &mut buf, REQUEST_TIMEOUT).await?;
            return bulk_answer(action, &buf);
        }
        Ok(Err(e)) => return Err(sent("no answer to the request head", &e)),
        // no interim answer: send it anyway
        Err(_) => {}
    }
    let write = tokio::time::timeout(BODY_TIMEOUT, async {
        s.write_all(body).await?;
        s.flush().await
    })
    .await;
    if let Err(why) = match write {
        Err(_) => Err(format!("not sent in {} s", BODY_TIMEOUT.as_secs())),
        Ok(Err(e)) => Err(e.to_string()),
        Ok(Ok(())) => Ok(()),
    } {
        // the gateway may have answered before it closed: that answer is the reason
        if read_rest(&mut s, &mut buf, Duration::from_secs(2))
            .await
            .is_ok()
            && head_end(&buf).is_some()
        {
            return bulk_answer(action, &buf);
        }
        let what = format!(
            "the gateway closed the connection while {} bytes were sent",
            body.len()
        );
        return Err(sent(&what, &why));
    }
    read_rest(&mut s, &mut buf, ANSWER_TIMEOUT).await?;
    bulk_answer(action, &buf)
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
    /// `POST /api/invoke` for arguments over a frame; `None` on a raw pipe.
    bulk: Option<Bulk>,
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
        http: None,
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
    /// gateway's own MCP endpoint (ADR 0041). It has no `POST /api/invoke`:
    /// an invoke whose arguments are over [`MAX_FRAME_ARGS`] is refused here
    /// ([`Error::TooLarge`]).
    pub async fn from_raw<S: AsyncRead + AsyncWrite + Unpin + Send + 'static>(io: S) -> Self {
        let ws = WebSocketStream::from_raw_socket(
            io,
            tokio_tungstenite::tungstenite::protocol::Role::Client,
            None,
        )
        .await;
        Self::start(ws, None)
    }

    fn start<S: AsyncRead + AsyncWrite + Unpin + Send + 'static>(
        ws: WebSocketStream<S>,
        bulk: Option<Bulk>,
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
            bulk,
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
        if bytes.len() > MAX_FRAME {
            // the gateway would close the socket, and every stream on it
            return Err(Error::TooLarge {
                what: format!("{op} {key}"),
                size: bytes.len(),
                limit: MAX_FRAME,
                hint: "a request over the WebSocket fits one frame; only an invoke of an \
                       action with an `editor: file` parameter takes more (POST /api/invoke)",
            });
        }
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
        if let Err(e) = self.send(id, op, key, extra) {
            self.lock().remove(&id);
            return Err(e);
        }
        let frame = tokio::time::timeout(REQUEST_TIMEOUT, rx)
            .await
            .map_err(|_| {
                self.lock().remove(&id);
                Error::refused(Status::Timeout, format!("{op} {key}: no answer"))
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
        if let Err(e) = self.send(id, op, key, Vec::new()) {
            self.lock().remove(&id);
            return Err(e);
        }
        let frame = tokio::time::timeout(REQUEST_TIMEOUT, rx)
            .await
            .map_err(|_| {
                self.lock().remove(&id);
                Error::refused(Status::Timeout, format!("{op} {key}: no answer"))
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

    /// Run `action` on `key`; its result. Arguments over [`MAX_FRAME_ARGS`]
    /// go by `POST /api/invoke` (only an action with an `editor: file`
    /// parameter takes them, the gateway's refusal says so), at most
    /// [`MAX_INVOKE_BODY`]; past that, or on a connection without that route
    /// ([`Conn::from_raw`]), [`Error::TooLarge`] before anything is sent.
    pub async fn invoke(&self, key: &str, action: &str, args: Value) -> Result<Option<Value>> {
        let body = to_vec(&args).map_err(transport)?;
        if body.len() > MAX_FRAME_ARGS {
            let what = format!("invoke {action} on {key}");
            if body.len() > MAX_INVOKE_BODY {
                return Err(Error::TooLarge {
                    what,
                    size: body.len(),
                    limit: MAX_INVOKE_BODY,
                    hint: "the gateway takes at most 64 MiB in one call; send the file in parts \
                           (an action's `upload_part`/`restore_part`)",
                });
            }
            let Some(b) = &self.bulk else {
                return Err(Error::TooLarge {
                    what,
                    size: body.len(),
                    limit: MAX_FRAME_ARGS,
                    hint: "this connection has no POST /api/invoke (the gateway's own MCP \
                           endpoint): send less, or use a client that logs in to the gateway",
                });
            };
            return bulk_invoke(b, key, action, &body).await;
        }
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
