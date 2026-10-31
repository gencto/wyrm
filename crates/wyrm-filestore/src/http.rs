//! The HTTP/1.1 client of a store: `hyper` 1 over TCP or `tokio-rustls`
//! (ring provider, never aws-lc), as `links/http`.
//!
//! A few keep-alive connections per endpoint ([`MAX_IDLE`]): a request takes
//! an idle one or opens a new one, and gives it back only when its reply was
//! read whole. A request that is cut (timeout, a body over the limit) drops
//! its connection, so a late reply is never taken for a later request. A
//! reused connection the server closed while idle is retried once on a new
//! one for requests that may go twice (all but `POST`).
//!
//! Errors name the method and the path, never the query (it may carry a
//! signature or a token), headers or bodies.

use crate::backend::Error;
use bytes::Bytes;
use http_body_util::{BodyExt, Full, Limited};
use hyper::client::conn::http1::SendRequest;
use hyper::header::{HeaderMap, HeaderName, HeaderValue};
use hyper::Method;
use hyper_util::rt::TokioIo;
use rustls_pki_types::ServerName;
use std::net::SocketAddr;
use std::sync::{Arc, LazyLock, Mutex};
use std::time::Duration;
use tokio::net::TcpStream;
use tokio::task::JoinHandle;
use tracing::debug;

/// The TLS config type of [`tls_config`].
pub use rustls::ClientConfig as TlsConfig;

/// Idle connections kept per endpoint.
pub const MAX_IDLE: usize = 4;

/// `http[s]://host[:port][/prefix]`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Endpoint {
    pub tls: bool,
    /// Lowercase, without brackets for IPv6.
    pub host: String,
    pub port: u16,
    /// Path prefix without a trailing `/` (may be empty), as sent.
    pub prefix: String,
}

impl Endpoint {
    pub fn parse(url: &str) -> Result<Self, String> {
        let url = url.trim();
        let lower = url.get(..8).unwrap_or(url).to_ascii_lowercase();
        let (tls, rest) = if lower.starts_with("https://") {
            (true, &url[8..])
        } else if lower.starts_with("http://") {
            (false, &url[7..])
        } else {
            return Err("must start with http:// or https://".into());
        };
        let (authority, path) = match rest.find(['/', '?', '#']) {
            Some(i) => (&rest[..i], &rest[i..]),
            None => (rest, ""),
        };
        if authority.contains('@') {
            return Err("no user or password in the URL".into());
        }
        if path.contains(['?', '#']) {
            return Err("no query or fragment in the URL".into());
        }
        let (host, port) = if let Some(v6) = authority.strip_prefix('[') {
            let (h, after) = v6.split_once(']').ok_or("bad IPv6 host")?;
            let port = match after {
                "" => None,
                p => Some(p.strip_prefix(':').ok_or("bad port")?),
            };
            (h, port)
        } else {
            match authority.rsplit_once(':') {
                Some((h, p)) => (h, Some(p)),
                None => (authority, None),
            }
        };
        let port = match port {
            None if tls => 443,
            None => 80,
            Some(p) => p.parse::<u16>().map_err(|_| "bad port".to_owned())?,
        };
        let host_ok = !host.is_empty()
            && host
                .bytes()
                .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'.' | b'-' | b'_' | b':'));
        if !host_ok || port == 0 {
            return Err("bad host".into());
        }
        let prefix = path.trim_end_matches('/').to_owned();
        if let Some(b) = prefix
            .bytes()
            .find(|b| !b.is_ascii_graphic() || b"\\\"<>`{}|^".contains(b))
        {
            return Err(format!(
                "character {:?} in the path (percent-encode it)",
                b as char
            ));
        }
        Ok(Endpoint {
            tls,
            host: host.to_ascii_lowercase(),
            port,
            prefix,
        })
    }

    /// The `Host` header: the port left out when it is the scheme's default.
    pub fn authority(&self) -> String {
        let host = if self.host.contains(':') {
            format!("[{}]", self.host)
        } else {
            self.host.clone()
        };
        if self.port == if self.tls { 443 } else { 80 } {
            host
        } else {
            format!("{host}:{}", self.port)
        }
    }

    pub fn is_loopback(&self) -> bool {
        self.host == "localhost"
            || self
                .host
                .parse::<std::net::IpAddr>()
                .is_ok_and(|ip| ip.is_loopback())
    }

    /// The same endpoint on another host (S3 virtual-hosted buckets).
    pub fn with_host(&self, host: &str) -> Self {
        Self {
            host: host.to_ascii_lowercase(),
            ..self.clone()
        }
    }
}

/// System CA roots, loaded once.
static SYSTEM_ROOTS: LazyLock<Vec<rustls_pki_types::CertificateDer<'static>>> =
    LazyLock::new(|| rustls_native_certs::load_native_certs().certs);

/// The TLS config of a store: `ca_pem` alone when given; else the host's CA
/// certificates, or the Mozilla roots on a host without any.
pub fn tls_config(
    ca_pem: &str,
    insecure_skip_verify: bool,
) -> Result<Arc<rustls::ClientConfig>, String> {
    use rustls_pki_types::pem::PemObject;
    use rustls_pki_types::CertificateDer;
    let provider = Arc::new(rustls::crypto::ring::default_provider());
    let b = rustls::ClientConfig::builder_with_provider(provider.clone())
        .with_safe_default_protocol_versions()
        .map_err(|e| format!("tls: {e}"))?;
    let b = if insecure_skip_verify {
        if !ca_pem.trim().is_empty() {
            return Err("ca_pem: give ca_pem or insecure_skip_verify, not both".into());
        }
        b.dangerous()
            .with_custom_certificate_verifier(Arc::new(NoVerify(provider)))
    } else {
        let mut roots = rustls::RootCertStore::empty();
        if ca_pem.trim().is_empty() {
            roots.add_parsable_certificates(SYSTEM_ROOTS.iter().cloned());
            if roots.is_empty() {
                roots.extend(webpki_roots::TLS_SERVER_ROOTS.iter().cloned());
            }
        } else {
            for cert in CertificateDer::pem_slice_iter(ca_pem.as_bytes()) {
                let cert = cert.map_err(|e| format!("ca_pem: {e}"))?;
                roots.add(cert).map_err(|e| format!("ca_pem: {e}"))?;
            }
            if roots.is_empty() {
                return Err("ca_pem: no certificate".into());
            }
        }
        b.with_root_certificates(roots)
    };
    let mut cfg = b.with_no_client_auth();
    cfg.alpn_protocols = vec![b"http/1.1".to_vec()];
    Ok(Arc::new(cfg))
}

#[derive(Debug)]
struct NoVerify(Arc<rustls::crypto::CryptoProvider>);

impl rustls::client::danger::ServerCertVerifier for NoVerify {
    fn verify_server_cert(
        &self,
        _end_entity: &rustls_pki_types::CertificateDer<'_>,
        _intermediates: &[rustls_pki_types::CertificateDer<'_>],
        _server_name: &rustls_pki_types::ServerName<'_>,
        _ocsp: &[u8],
        _now: rustls_pki_types::UnixTime,
    ) -> Result<rustls::client::danger::ServerCertVerified, rustls::Error> {
        Ok(rustls::client::danger::ServerCertVerified::assertion())
    }

    fn verify_tls12_signature(
        &self,
        message: &[u8],
        cert: &rustls_pki_types::CertificateDer<'_>,
        dss: &rustls::DigitallySignedStruct,
    ) -> Result<rustls::client::danger::HandshakeSignatureValid, rustls::Error> {
        rustls::crypto::verify_tls12_signature(
            message,
            cert,
            dss,
            &self.0.signature_verification_algorithms,
        )
    }

    fn verify_tls13_signature(
        &self,
        message: &[u8],
        cert: &rustls_pki_types::CertificateDer<'_>,
        dss: &rustls::DigitallySignedStruct,
    ) -> Result<rustls::client::danger::HandshakeSignatureValid, rustls::Error> {
        rustls::crypto::verify_tls13_signature(
            message,
            cert,
            dss,
            &self.0.signature_verification_algorithms,
        )
    }

    fn supported_verify_schemes(&self) -> Vec<rustls::SignatureScheme> {
        self.0.signature_verification_algorithms.supported_schemes()
    }
}

/// One request: method, absolute path and query (the endpoint's prefix
/// included), headers beside `Host`, body.
#[derive(Debug, Clone)]
pub struct Request {
    pub method: Method,
    pub target: String,
    pub headers: Vec<(HeaderName, HeaderValue)>,
    pub body: Bytes,
    /// A part of a file sent as the body instead of `body`, read as it
    /// goes out (a large upload is never held in memory).
    pub file: Option<FileBody>,
    /// A header that could not be set (its name): the request is refused
    /// rather than sent without it (an unauthenticated request).
    pub bad_header: Option<String>,
}

impl Request {
    pub fn new(method: Method, target: impl Into<String>) -> Self {
        Self {
            method,
            target: target.into(),
            headers: Vec::new(),
            body: Bytes::new(),
            file: None,
            bad_header: None,
        }
    }

    /// Send `len` bytes of the file `path` from `offset` as the body.
    pub fn file_body(mut self, path: impl Into<std::path::PathBuf>, offset: u64, len: u64) -> Self {
        self.file = Some(FileBody {
            path: path.into(),
            offset,
            len,
        });
        self
    }

    /// Bytes of the body.
    pub fn body_len(&self) -> u64 {
        match &self.file {
            Some(f) => f.len,
            None => self.body.len() as u64,
        }
    }

    fn push(mut self, name: &str, value: &str, sensitive: bool) -> Self {
        match (
            HeaderName::from_bytes(name.as_bytes()),
            HeaderValue::from_str(value),
        ) {
            (Ok(n), Ok(mut v)) => {
                v.set_sensitive(sensitive);
                self.headers.push((n, v));
            }
            _ => self.bad_header = Some(name.to_owned()),
        }
        self
    }

    /// Add a header. A value that is not a valid header value makes
    /// [`Http::send`] refuse the request.
    pub fn header(self, name: &str, value: &str) -> Self {
        self.push(name, value, false)
    }

    /// A credential header, kept out of debug output by hyper.
    pub fn secret_header(self, name: &str, value: &str) -> Self {
        self.push(name, value, true)
    }

    pub fn body(mut self, b: impl Into<Bytes>) -> Self {
        self.body = b.into();
        self
    }

    /// `GET /path` for errors and logs (never the query).
    pub fn what(&self) -> String {
        let path = self.target.split('?').next().unwrap_or("");
        format!("{} {path}", self.method)
    }
}

/// A part of a file as a request body.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FileBody {
    pub path: std::path::PathBuf,
    pub offset: u64,
    pub len: u64,
}

/// Chunks read from a file on the blocking pool while the request goes out.
const FILE_CHUNK: usize = 256 * 1024;

type SendBody = http_body_util::combinators::BoxBody<Bytes, std::io::Error>;

/// A body read from a file as hyper polls it.
struct FileStream {
    rx: tokio::sync::mpsc::Receiver<std::io::Result<Bytes>>,
    len: u64,
}

impl hyper::body::Body for FileStream {
    type Data = Bytes;
    type Error = std::io::Error;

    fn poll_frame(
        mut self: std::pin::Pin<&mut Self>,
        cx: &mut std::task::Context<'_>,
    ) -> std::task::Poll<Option<Result<hyper::body::Frame<Bytes>, std::io::Error>>> {
        self.rx
            .poll_recv(cx)
            .map(|o| o.map(|r| r.map(hyper::body::Frame::data)))
    }

    fn size_hint(&self) -> hyper::body::SizeHint {
        hyper::body::SizeHint::with_exact(self.len)
    }
}

/// The body of `f`: a reader on the blocking pool feeds it in chunks and
/// stops when the request is dropped.
fn file_stream(f: &FileBody) -> SendBody {
    use http_body_util::BodyExt as _;
    use std::io::{Read, Seek, SeekFrom};
    let (tx, rx) = tokio::sync::mpsc::channel(4);
    let f2 = f.clone();
    tokio::task::spawn_blocking(move || {
        let read = || -> std::io::Result<()> {
            let mut file = std::fs::File::open(&f2.path)?;
            file.seek(SeekFrom::Start(f2.offset))?;
            let mut left = f2.len;
            while left > 0 {
                let n = left.min(FILE_CHUNK as u64) as usize;
                let mut buf = vec![0u8; n];
                file.read_exact(&mut buf)?;
                if tx.blocking_send(Ok(Bytes::from(buf))).is_err() {
                    return Ok(()); // the request is gone
                }
                left -= n as u64;
            }
            Ok(())
        };
        if let Err(e) = read() {
            let _ = tx.blocking_send(Err(e));
        }
    });
    FileStream { rx, len: f.len }.boxed()
}

/// A reply (any status).
#[derive(Debug)]
pub struct Response {
    pub status: u16,
    pub headers: HeaderMap,
    pub body: Bytes,
}

impl Response {
    pub fn header(&self, name: &str) -> Option<&str> {
        self.headers.get(name).and_then(|v| v.to_str().ok())
    }

    pub fn ok(&self) -> bool {
        (200..300).contains(&self.status)
    }

    /// The body as text (lossy), for parsers.
    pub fn text(&self) -> String {
        String::from_utf8_lossy(&self.body).into_owned()
    }
}

/// A `Content-Range` header of a reply.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ContentRange {
    /// `bytes <start>-<end>/<size>` (`size` is `None` for `*`).
    Part {
        start: u64,
        end: u64,
        size: Option<u64>,
    },
    /// `bytes */<size>` (with a 416).
    Unsatisfied { size: u64 },
}

fn digits(s: &str) -> Option<u64> {
    let s = s.trim();
    if s.is_empty() || !s.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    s.parse().ok()
}

/// Parse `Content-Range` (RFC 9110 14.4); `None` when it is not one of
/// bytes (a start after its end, an end at or past a known size).
pub fn parse_content_range(h: &str) -> Option<ContentRange> {
    let h = h.trim();
    let (unit, rest) = h.split_once(' ')?;
    if !unit.eq_ignore_ascii_case("bytes") {
        return None;
    }
    let (span, size) = rest.trim().split_once('/')?;
    let size = match size.trim() {
        "*" => None,
        n => Some(digits(n)?),
    };
    if span.trim() == "*" {
        return Some(ContentRange::Unsatisfied { size: size? });
    }
    let (a, b) = span.split_once('-')?;
    let (start, end) = (digits(a)?, digits(b)?);
    if start > end || size.is_some_and(|n| end >= n) {
        return None;
    }
    Some(ContentRange::Part { start, end, size })
}

/// The bytes of a ranged `GET` of `len` bytes from `offset` (S3, Drive,
/// WebDAV), checked:
/// - `206`: its `Content-Range` must start at `offset` and span the body
///   exactly, or the part is refused (never used as if it were that part);
/// - `200`: the whole file, taken only for a range from 0 that holds it
///   (a store that ignores `Range` past 0 is refused rather than read whole);
/// - `416` with `Content-Range: bytes */<size>` and `offset` at or past
///   `size`: [`Error::PastEnd`];
/// - any other reply (a 416 without a usable size too): `other`, the
///   backend's own error for it.
pub fn range_reply(
    r: Response,
    offset: u64,
    len: usize,
    what: &str,
    other: impl FnOnce(&Response) -> Error,
) -> Result<Bytes, Error> {
    let range = r.header("content-range").and_then(parse_content_range);
    match r.status {
        206 => match range {
            Some(ContentRange::Part { start, end, .. })
                if start == offset
                    && (end - start).checked_add(1) == Some(r.body.len() as u64) =>
            {
                Ok(r.body)
            }
            _ => Err(Error::Refused(format!(
                "{what}: the store sent a part that is not bytes {offset}-: Content-Range {:?}, {} bytes",
                r.header("content-range").unwrap_or(""),
                r.body.len()
            ))),
        },
        200 if offset == 0 && r.body.len() <= len => Ok(r.body),
        200 => Err(Error::Refused(format!("{what}: the store ignores Range"))),
        416 => match range {
            Some(ContentRange::Unsatisfied { size }) if offset >= size => Err(Error::PastEnd(
                format!("{what}: offset {offset} is past the end ({size} bytes)"),
                size,
            )),
            _ => Err(other(&r)),
        },
        _ => Err(other(&r)),
    }
}

/// Why a request got no reply.
#[derive(Debug, Clone, PartialEq)]
pub enum HttpError {
    /// No connection (resolve, refused, TLS, I/O).
    Connect(String),
    /// No reply in time.
    Timeout(String),
    /// A body over the limit.
    TooBig(String),
}

impl std::fmt::Display for HttpError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            HttpError::Connect(m) | HttpError::Timeout(m) | HttpError::TooBig(m) => f.write_str(m),
        }
    }
}

struct Live {
    sender: SendRequest<SendBody>,
    task: JoinHandle<()>,
}

impl Drop for Live {
    fn drop(&mut self) {
        // Closes the socket: a late reply goes nowhere.
        self.task.abort();
    }
}

/// The client of one endpoint.
pub struct Http {
    pub endpoint: Endpoint,
    tls: Option<Arc<rustls::ClientConfig>>,
    idle: Mutex<Vec<Live>>,
    user_agent: String,
}

impl Http {
    /// `tls` is required for `https://` and ignored for `http://`.
    pub fn new(endpoint: Endpoint, tls: Option<Arc<rustls::ClientConfig>>, agent: &str) -> Self {
        let tls = if endpoint.tls { tls } else { None };
        Self {
            endpoint,
            tls,
            idle: Mutex::new(Vec::new()),
            user_agent: agent.to_owned(),
        }
    }

    async fn connect(&self) -> Result<Live, String> {
        let e = &self.endpoint;
        let addrs: Vec<SocketAddr> = tokio::net::lookup_host((e.host.as_str(), e.port))
            .await
            .map_err(|err| format!("resolve {}: {err}", e.host))?
            .collect();
        let mut last = format!("resolve {}: no address", e.host);
        let mut tcp = None;
        for a in addrs {
            match TcpStream::connect(a).await {
                Ok(s) => {
                    tcp = Some(s);
                    break;
                }
                Err(err) => last = format!("connect {}: {err}", e.authority()),
            }
        }
        let tcp = tcp.ok_or(last)?;
        let _ = tcp.set_nodelay(true);
        let hs = |err: hyper::Error| format!("http: {err}");
        let (sender, task) = match (&self.tls, e.tls) {
            (_, false) => {
                let (s, c) = hyper::client::conn::http1::handshake(TokioIo::new(tcp))
                    .await
                    .map_err(hs)?;
                (s, tokio::spawn(drive(c)))
            }
            (None, true) => return Err("https without a TLS config".into()),
            (Some(cfg), true) => {
                let name = ServerName::try_from(e.host.clone())
                    .map_err(|_| format!("tls: bad server name {}", e.host))?;
                let tls = tokio_rustls::TlsConnector::from(cfg.clone())
                    .connect(name, tcp)
                    .await
                    .map_err(|err| format!("tls {}: {err}", e.authority()))?;
                let (s, c) = hyper::client::conn::http1::handshake(TokioIo::new(tls))
                    .await
                    .map_err(hs)?;
                (s, tokio::spawn(drive(c)))
            }
        };
        Ok(Live { sender, task })
    }

    fn take_idle(&self) -> Option<Live> {
        let mut idle = self.idle.lock().unwrap_or_else(|e| e.into_inner());
        while let Some(l) = idle.pop() {
            if !l.sender.is_closed() {
                return Some(l);
            }
        }
        None
    }

    fn give_back(&self, l: Live) {
        let mut idle = self.idle.lock().unwrap_or_else(|e| e.into_inner());
        if idle.len() < MAX_IDLE {
            idle.push(l);
        }
    }

    /// Send `req` and read the reply whole (at most `max_body` bytes), all
    /// within `timeout`.
    pub async fn send(
        &self,
        req: &Request,
        timeout: Duration,
        max_body: usize,
    ) -> Result<Response, HttpError> {
        let what = req.what();
        if let Some(h) = &req.bad_header {
            // never the value: it may be a credential
            return Err(HttpError::Connect(format!(
                "{what}: the {h} header has characters a header cannot carry"
            )));
        }
        match tokio::time::timeout(timeout, self.exchange(req, max_body, &what)).await {
            Ok(r) => r,
            Err(_) => Err(HttpError::Timeout(format!(
                "{what}: no reply in {} ms",
                timeout.as_millis()
            ))),
        }
    }

    async fn exchange(
        &self,
        req: &Request,
        max_body: usize,
        what: &str,
    ) -> Result<Response, HttpError> {
        let mut retried = false;
        loop {
            let (mut live, reused) = match self.take_idle() {
                Some(l) => (l, true),
                None => (
                    self.connect()
                        .await
                        .map_err(|e| HttpError::Connect(format!("{what}: {e}")))?,
                    false,
                ),
            };
            if live.sender.ready().await.is_err() {
                if reused {
                    continue;
                }
                return Err(HttpError::Connect(format!("{what}: connection closed")));
            }
            let mut b = hyper::Request::builder()
                .method(req.method.clone())
                .uri(req.target.as_str())
                .header(hyper::header::HOST, self.endpoint.authority())
                .header(hyper::header::USER_AGENT, self.user_agent.as_str())
                .header(hyper::header::ACCEPT_ENCODING, "identity");
            if req.body_len() > 0 || matches!(req.method, Method::PUT | Method::POST) {
                b = b.header(hyper::header::CONTENT_LENGTH, req.body_len());
            }
            let body = match &req.file {
                Some(f) => file_stream(f),
                None => {
                    use http_body_util::BodyExt as _;
                    Full::new(req.body.clone())
                        .map_err(|never| match never {})
                        .boxed()
                }
            };
            let mut hr = b
                .body(body)
                .map_err(|_| HttpError::Connect(format!("{what}: bad request")))?;
            for (k, v) in &req.headers {
                hr.headers_mut().insert(k.clone(), v.clone());
            }
            let resp = match live.sender.send_request(hr).await {
                Ok(r) => r,
                Err(e) => {
                    let again = reused && (e.is_canceled() || req.method != Method::POST);
                    if again && !retried {
                        debug!(%what, "reused connection closed; sending again on a new one");
                        retried = true;
                        continue;
                    }
                    return Err(HttpError::Connect(format!("{what}: {e}")));
                }
            };
            let (parts, body) = resp.into_parts();
            let declared = parts
                .headers
                .get(hyper::header::CONTENT_LENGTH)
                .and_then(|v| v.to_str().ok())
                .and_then(|v| v.parse::<u64>().ok());
            if declared.is_some_and(|n| n > max_body as u64) {
                return Err(HttpError::TooBig(format!(
                    "{what}: reply over {max_body} bytes"
                )));
            }
            let body = match Limited::new(body, max_body).collect().await {
                Ok(b) => b.to_bytes(),
                Err(e)
                    if e.downcast_ref::<http_body_util::LengthLimitError>()
                        .is_some() =>
                {
                    return Err(HttpError::TooBig(format!(
                        "{what}: reply over {max_body} bytes"
                    )))
                }
                Err(e) => return Err(HttpError::Connect(format!("{what}: {e}"))),
            };
            let keep = !parts
                .headers
                .get(hyper::header::CONNECTION)
                .and_then(|v| v.to_str().ok())
                .is_some_and(|v| v.eq_ignore_ascii_case("close"));
            if keep {
                self.give_back(live);
            }
            return Ok(Response {
                status: parts.status.as_u16(),
                headers: parts.headers,
                body,
            });
        }
    }
}

async fn drive<F: std::future::Future<Output = hyper::Result<()>>>(conn: F) {
    if let Err(e) = conn.await {
        debug!("http connection ended: {e}");
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn endpoints() {
        let e = Endpoint::parse("HTTPS://S3.Example.com/base/").unwrap();
        assert_eq!(
            e,
            Endpoint {
                tls: true,
                host: "s3.example.com".into(),
                port: 443,
                prefix: "/base".into()
            }
        );
        assert_eq!(e.authority(), "s3.example.com");
        let e = Endpoint::parse("http://[::1]:9000").unwrap();
        assert_eq!(e.authority(), "[::1]:9000");
        assert!(e.is_loopback());
        for bad in [
            "ftp://x",
            "http://",
            "http://u:p@h",
            "http://h:0",
            "http://h/?q",
            "http://h/a b",
        ] {
            assert!(Endpoint::parse(bad).is_err(), "{bad}");
        }
    }

    fn reply(status: u16, range: Option<&str>, body: &'static [u8]) -> Response {
        let mut headers = HeaderMap::new();
        if let Some(r) = range {
            headers.insert("content-range", HeaderValue::from_str(r).unwrap());
        }
        Response {
            status,
            headers,
            body: Bytes::from_static(body),
        }
    }

    #[test]
    fn content_ranges() {
        use ContentRange::*;
        let p = parse_content_range;
        assert_eq!(
            p("bytes 0-9/100"),
            Some(Part {
                start: 0,
                end: 9,
                size: Some(100)
            })
        );
        assert_eq!(
            p("Bytes 5-5/*"),
            Some(Part {
                start: 5,
                end: 5,
                size: None
            })
        );
        assert_eq!(p("bytes */42"), Some(Unsatisfied { size: 42 }));
        for bad in [
            "",
            "bytes",
            "bytes 9-0/100",
            "bytes 0-100/100",
            "bytes */*",
            "items 0-1/2",
            "bytes +1-2/3",
            "bytes 0-1",
        ] {
            assert_eq!(p(bad), None, "{bad}");
        }
    }

    /// A 206 is used only when its Content-Range starts at the asked
    /// offset and spans the body; a 416 past the end says the size.
    #[test]
    fn range_replies() {
        let other = |r: &Response| Error::Refused(format!("HTTP {}", r.status));
        let ok = range_reply(reply(206, Some("bytes 4-7/10"), b"abcd"), 4, 4, "x", other);
        assert_eq!(ok.unwrap(), Bytes::from_static(b"abcd"));
        // the last part, shorter than asked
        let ok = range_reply(reply(206, Some("bytes 8-9/10"), b"ab"), 8, 4, "x", other);
        assert_eq!(ok.unwrap(), Bytes::from_static(b"ab"));
        for (range, body) in [
            (None, &b"abcd"[..]),
            (Some("bytes 0-3/10"), b"abcd"),
            (Some("bytes 4-8/10"), b"abcd"),
            (Some("bytes 4-7/10"), b"abc"),
            (Some("nonsense"), b"abcd"),
            (Some("bytes 4-18446744073709551615/*"), b"abcd"),
        ] {
            let r = range_reply(reply(206, range, body), 4, 4, "x", other);
            assert!(matches!(r, Err(Error::Refused(_))), "{range:?}: {r:?}");
        }
        assert!(range_reply(reply(200, None, b"ab"), 0, 4, "x", other).is_ok());
        assert!(range_reply(reply(200, None, b"abcdef"), 2, 4, "x", other).is_err());
        let r = range_reply(reply(416, Some("bytes */6"), b""), 8, 4, "x", other);
        assert!(matches!(r, Err(Error::PastEnd(_, 6))), "{r:?}");
        let r = range_reply(reply(416, Some("bytes */6"), b""), 6, 4, "x", other);
        assert!(matches!(r, Err(Error::PastEnd(_, 6))), "at the end: {r:?}");
        // the offset is inside the file it names, or no size: an error
        for range in [Some("bytes */60"), None, Some("bytes 0-1/6")] {
            let r = range_reply(reply(416, range, b""), 8, 4, "x", other);
            assert_eq!(r, Err(Error::Refused("HTTP 416".into())), "{range:?}");
        }
        let r = range_reply(reply(404, None, b""), 0, 4, "x", other);
        assert_eq!(r, Err(Error::Refused("HTTP 404".into())));
    }

    #[test]
    fn tls_configs() {
        assert!(tls_config("", false).is_ok());
        assert!(tls_config("", true).is_ok());
        assert!(tls_config("not pem", false).is_err());
    }
}
