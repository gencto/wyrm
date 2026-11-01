//! The HTTP/1.1 client of one connection: `hyper` 1 over a TCP socket or
//! `tokio-rustls` (ring provider, never aws-lc).
//!
//! One keep-alive connection per link connection, one request on it at a
//! time (no pipelining). A request that is cut (its timeout, or the
//! framework's bound on the poll) leaves the connection dirty; the next
//! request opens a new one first, so a late reply arrives on a closed
//! socket and is never taken for a later request. A connection the server
//! closed while idle is reopened without a failure.
//!
//! Errors never carry the query string (an API key may be in it), headers
//! or bodies: they name the method and the path only.

use bytes::Bytes;
use http_body_util::{BodyExt, Full, Limited};
use hyper::client::conn::http1::SendRequest;
use hyper::header::{HeaderMap, HeaderName, HeaderValue};
use hyper::{Method, StatusCode};
use hyper_util::rt::TokioIo;
use rustls_pki_types::ServerName;
use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Duration;
use tokio::net::TcpStream;
use tokio::task::JoinHandle;
use tokio::time::Instant;
use tracing::debug;
use wyrm_link_sdk::driver::Outcome;

/// Redirects followed per request (to the same scheme, host and port only).
pub const MAX_REDIRECTS: usize = 3;
/// Diagnostics counter: connections opened again (idle close, dirty).
pub const RECONNECTS: &str = "reconnects";
/// Diagnostics counter: redirects followed.
pub const REDIRECTS: &str = "redirects";

/// `http[s]://host[:port][/prefix]`.
#[derive(Debug, Clone, PartialEq)]
pub struct Origin {
    pub tls: bool,
    /// Without brackets for IPv6.
    pub host: String,
    pub port: u16,
    /// Path prefix without a trailing `/` (may be empty).
    pub prefix: String,
}

impl Origin {
    pub fn parse(url: &str) -> Result<Self, String> {
        let url = url.trim();
        let (tls, rest) = if let Some(r) = strip_ci(url, "https://") {
            (true, r)
        } else if let Some(r) = strip_ci(url, "http://") {
            (false, r)
        } else {
            return Err("must start with http:// or https://".into());
        };
        let (authority, path) = match rest.find(['/', '?', '#']) {
            Some(i) => (&rest[..i], &rest[i..]),
            None => (rest, ""),
        };
        if authority.contains('@') {
            return Err("no user or password in the URL: use auth".into());
        }
        if path.contains(['?', '#']) {
            return Err("no query or fragment in the base URL".into());
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
            None => {
                if tls {
                    443
                } else {
                    80
                }
            }
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
        check_path(&prefix)?;
        Ok(Origin {
            tls,
            host: host.to_ascii_lowercase(),
            port,
            prefix,
        })
    }

    /// The `Host` header: `host[:port]`, the port left out when it is the
    /// scheme's default.
    pub fn authority(&self) -> String {
        let host = if self.host.contains(':') {
            format!("[{}]", self.host)
        } else {
            self.host.clone()
        };
        let default = if self.tls { 443 } else { 80 };
        if self.port == default {
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
}

/// `s` without an ASCII `prefix` (any case). Compares bytes, so a
/// multi-byte character where the prefix ends never panics.
fn strip_ci<'a>(s: &'a str, prefix: &str) -> Option<&'a str> {
    let p = prefix.as_bytes();
    if s.as_bytes().get(..p.len())?.eq_ignore_ascii_case(p) {
        // On a char boundary: the matched prefix is ASCII.
        s.get(p.len()..)
    } else {
        None
    }
}

/// A path (or path and query) as sent: visible ASCII without `#`, `\`,
/// spaces or quotes; empty or starting with `/`.
pub fn check_path(p: &str) -> Result<(), String> {
    if !p.is_empty() && !p.starts_with('/') {
        return Err("must start with /".into());
    }
    check_chars(p)
}

/// Visible ASCII without `#`, `\`, `"`, `<`, `>`, `` ` ``, `{`, `}`, `|`, `^`.
pub fn check_chars(p: &str) -> Result<(), String> {
    match p
        .bytes()
        .find(|b| !b.is_ascii_graphic() || b"#\\\"<>`{}|^".contains(b))
    {
        Some(b) => Err(format!(
            "character {:?} is not allowed (percent-encode it)",
            b as char
        )),
        None => Ok(()),
    }
}

/// The path part of a path and query, for errors (never the query).
pub fn path_only(pq: &str) -> &str {
    pq.split('?').next().unwrap_or(pq)
}

/// Percent-encode a query component (RFC 3986 unreserved left as is).
pub fn encode_query(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for b in s.bytes() {
        if b.is_ascii_alphanumeric() || matches!(b, b'-' | b'.' | b'_' | b'~') {
            out.push(b as char);
        } else {
            out.push_str(&format!("%{b:02X}"));
        }
    }
    out
}

/// What every request of a connection carries (built when its params are
/// parsed).
pub struct Prepared {
    pub origin: Origin,
    pub tls: Option<Arc<rustls::ClientConfig>>,
    /// Default headers, then the auth header (marked sensitive).
    pub headers: Vec<(HeaderName, HeaderValue)>,
    /// `name=value` of an API key in the query (percent-encoded).
    pub query_key: Option<(String, String)>,
    pub timeout: Duration,
    /// Least time between two requests (the rate limit).
    pub interval: Duration,
    pub max_body: usize,
    /// Secret texts (and their encodings), longest first: masked in what a
    /// user is shown of a reply (point values, action replies).
    pub masks: Vec<String>,
    /// The masks that are plain decimal numbers: a reading equal to one is
    /// hidden.
    pub numbers: Vec<f64>,
    /// Shown as the connection's warning while it runs.
    pub note: Option<String>,
}

/// One request: method, the path and query below the base URL's prefix,
/// and an optional JSON body.
#[derive(Debug, Clone, PartialEq)]
pub struct Req {
    pub method: Method,
    /// Path and query, starting with `/` (the prefix not included).
    pub target: String,
    pub body: Option<Bytes>,
}

impl Req {
    /// Identity of the request (the last reply to it is kept for
    /// `test_selector`).
    pub fn key(&self) -> String {
        let body = self.body.as_deref().unwrap_or_default();
        format!(
            "{} {}\n{}",
            self.method,
            self.target,
            String::from_utf8_lossy(body)
        )
    }
}

/// A reply (any status).
pub struct Reply {
    pub status: StatusCode,
    pub headers: HeaderMap,
    pub body: Bytes,
}

/// Why a request failed.
#[derive(Debug, Clone, PartialEq)]
pub enum Fail {
    /// No connection (refused, TLS, I/O): reconnect.
    Transport(String),
    /// No reply in time.
    Timeout(String),
    /// A reply that cannot be used (too big, a redirect refused).
    Bad(String),
}

struct Live {
    sender: SendRequest<Full<Bytes>>,
    task: JoinHandle<()>,
}

impl Drop for Live {
    fn drop(&mut self) {
        // Closes the socket: a late reply goes nowhere.
        self.task.abort();
    }
}

/// The transport of one connection.
pub struct Client {
    pub prep: Arc<Prepared>,
    live: Option<Live>,
    /// A request went out and its reply was not fully read.
    dirty: bool,
    next_slot: Option<Instant>,
    pub outcomes: Vec<Outcome>,
}

async fn connect(prep: &Prepared) -> Result<Live, String> {
    let o = &prep.origin;
    let target = (o.host.as_str(), o.port);
    // never link-local or metadata addresses, whatever the name resolves to (review LNK-1)
    let addrs: Vec<SocketAddr> = wyrm_link_sdk::outbound::resolve(target.0, target.1).await?;
    let mut last = format!("resolve {}: no address", o.host);
    let mut tcp = None;
    for a in addrs {
        match TcpStream::connect(a).await {
            Ok(s) => {
                tcp = Some(s);
                break;
            }
            Err(e) => last = format!("connect {}: {e}", o.authority()),
        }
    }
    let tcp = tcp.ok_or(last)?;
    let _ = tcp.set_nodelay(true);
    let handshake = |e: hyper::Error| format!("http: {e}");
    let (sender, task) = match &prep.tls {
        None => {
            let (sender, conn) = hyper::client::conn::http1::handshake(TokioIo::new(tcp))
                .await
                .map_err(handshake)?;
            (sender, tokio::spawn(drive(conn)))
        }
        Some(cfg) => {
            let name = ServerName::try_from(o.host.clone())
                .map_err(|_| format!("tls: bad server name {}", o.host))?;
            let tls = tokio_rustls::TlsConnector::from(cfg.clone())
                .connect(name, tcp)
                .await
                .map_err(|e| format!("tls {}: {e}", o.authority()))?;
            let (sender, conn) = hyper::client::conn::http1::handshake(TokioIo::new(tls))
                .await
                .map_err(handshake)?;
            (sender, tokio::spawn(drive(conn)))
        }
    };
    Ok(Live { sender, task })
}

async fn drive<F: std::future::Future<Output = hyper::Result<()>>>(conn: F) {
    if let Err(e) = conn.await {
        debug!("http connection ended: {e}");
    }
}

enum Sent {
    Reply(Reply),
    /// The connection failed; `retry`: the request may go again on a new
    /// connection (it was not sent, or it is a GET on a reused one).
    Failed {
        err: String,
        retry: bool,
    },
    TooBig,
}

impl Client {
    /// Open the connection (TCP and TLS) within the connection's timeout.
    pub async fn open(prep: Arc<Prepared>) -> Result<Self, Fail> {
        let live = tokio::time::timeout(prep.timeout, connect(&prep))
            .await
            .map_err(|_| Fail::Transport(format!("connect {}: timeout", prep.origin.authority())))?
            .map_err(Fail::Transport)?;
        Ok(Client {
            prep,
            live: Some(live),
            dirty: false,
            next_slot: None,
            outcomes: Vec::new(),
        })
    }

    /// Wait for the rate limit's next slot.
    async fn pace(&mut self) {
        let now = Instant::now();
        let at = self.next_slot.map_or(now, |s| s.max(now));
        if at > now {
            tokio::time::sleep_until(at).await;
        }
        self.next_slot = Some(at + self.prep.interval);
    }

    /// A usable connection: the current one, or a new one when there is
    /// none, it is dirty or the server closed it. `true` = reused.
    async fn ensure(&mut self) -> Result<bool, Fail> {
        if self.dirty {
            self.live = None;
            self.dirty = false;
        }
        if let Some(l) = &mut self.live {
            if !l.sender.is_closed() && l.sender.ready().await.is_ok() {
                return Ok(true);
            }
            self.live = None;
        }
        let prep = self.prep.clone();
        let live = match tokio::time::timeout(prep.timeout, connect(&prep)).await {
            Ok(Ok(live)) => live,
            Ok(Err(e)) => {
                self.outcomes.push(Outcome::Error);
                return Err(Fail::Transport(e));
            }
            Err(_) => {
                self.outcomes.push(Outcome::Timeout);
                return Err(Fail::Transport(format!(
                    "connect {}: timeout",
                    prep.origin.authority()
                )));
            }
        };
        self.outcomes.push(Outcome::Count(RECONNECTS));
        self.live = Some(live);
        Ok(false)
    }

    fn build(
        &self,
        method: &Method,
        pq: &str,
        body: Option<&Bytes>,
    ) -> Result<hyper::Request<Full<Bytes>>, Fail> {
        let p = &self.prep;
        let mut uri = pq.to_owned();
        // A redirect's `Location` may carry the key already.
        let carried = p.query_key.as_ref().is_some_and(|(name, value)| {
            uri.split_once('?').is_some_and(|(_, q)| {
                q.split('&')
                    .any(|kv| kv.split_once('=') == Some((name.as_str(), value.as_str())))
            })
        });
        if let Some((name, value)) = p.query_key.as_ref().filter(|_| !carried) {
            uri.push(if uri.contains('?') { '&' } else { '?' });
            uri.push_str(name);
            uri.push('=');
            uri.push_str(value);
        }
        let mut b = hyper::Request::builder()
            .method(method.clone())
            .uri(uri)
            .header(hyper::header::HOST, p.origin.authority())
            .header(hyper::header::ACCEPT, "application/json")
            // never a compressed body: the masker could not see into it
            .header(hyper::header::ACCEPT_ENCODING, "identity")
            .header(
                hyper::header::USER_AGENT,
                concat!("wyrm-http/", env!("CARGO_PKG_VERSION")),
            );
        if body.is_some() {
            b = b.header(hyper::header::CONTENT_TYPE, "application/json");
        }
        let mut req = b
            .body(Full::new(body.cloned().unwrap_or_default()))
            .map_err(|_| Fail::Bad(format!("{method} {}: bad request", path_only(pq))))?;
        for (k, v) in &p.headers {
            req.headers_mut().insert(k.clone(), v.clone());
        }
        Ok(req)
    }

    /// One request on the wire (no redirects) to `pq` (absolute path and
    /// query): paced, on a usable connection, its reply read whole within
    /// the timeout.
    async fn once(
        &mut self,
        method: &Method,
        pq: &str,
        body: Option<&Bytes>,
    ) -> Result<Reply, Fail> {
        let what = format!("{method} {}", path_only(pq));
        let mut retried = false;
        loop {
            self.pace().await;
            let reused = self.ensure().await?;
            let req = self.build(method, pq, body)?;
            let max = self.prep.max_body;
            let Some(live) = self.live.as_mut() else {
                return Err(Fail::Transport(format!("{what}: no connection")));
            };
            self.dirty = true;
            let sent = Instant::now();
            let idempotent = *method == Method::GET;
            let exchange = async {
                let resp = match live.sender.send_request(req).await {
                    Ok(r) => r,
                    Err(e) => {
                        let retry = reused && (e.is_canceled() || idempotent);
                        return Sent::Failed {
                            err: e.to_string(),
                            retry,
                        };
                    }
                };
                let (parts, body) = resp.into_parts();
                let declared = parts
                    .headers
                    .get(hyper::header::CONTENT_LENGTH)
                    .and_then(|v| v.to_str().ok())
                    .and_then(|v| v.parse::<u64>().ok());
                if declared.is_some_and(|n| n > max as u64) {
                    return Sent::TooBig;
                }
                match Limited::new(body, max).collect().await {
                    Ok(b) => Sent::Reply(Reply {
                        status: parts.status,
                        headers: parts.headers,
                        body: b.to_bytes(),
                    }),
                    Err(e)
                        if e.downcast_ref::<http_body_util::LengthLimitError>()
                            .is_some() =>
                    {
                        Sent::TooBig
                    }
                    Err(e) => Sent::Failed {
                        err: e.to_string(),
                        retry: false,
                    },
                }
            };
            let r = tokio::time::timeout(self.prep.timeout, exchange).await;
            let rtt = sent.elapsed();
            match r {
                Err(_) => {
                    self.outcomes.push(Outcome::Timeout);
                    self.live = None;
                    self.dirty = false;
                    return Err(Fail::Timeout(format!(
                        "{what}: no reply in {} ms",
                        self.prep.timeout.as_millis()
                    )));
                }
                Ok(Sent::TooBig) => {
                    self.outcomes.push(Outcome::Error);
                    self.live = None;
                    self.dirty = false;
                    return Err(Fail::Bad(format!("{what}: body over {max} bytes")));
                }
                Ok(Sent::Failed { err, retry }) => {
                    self.live = None;
                    self.dirty = false;
                    // A request sent again is a request of its own.
                    self.outcomes.push(Outcome::Error);
                    if retry && !retried {
                        debug!(%what, "reused connection closed; sending again on a new one");
                        retried = true;
                        continue;
                    }
                    return Err(Fail::Transport(format!("{what}: {err}")));
                }
                Ok(Sent::Reply(reply)) => {
                    self.dirty = false;
                    self.outcomes.push(if reply.status.as_u16() >= 400 {
                        Outcome::Exception(rtt)
                    } else {
                        Outcome::Reply(rtt)
                    });
                    return Ok(reply);
                }
            }
        }
    }

    /// `GET /prefix/path` of `r`, for errors and logs (never the query).
    pub fn what(&self, r: &Req) -> String {
        format!(
            "{} {}{}",
            r.method,
            self.prep.origin.prefix,
            path_only(&r.target)
        )
    }

    /// A request with up to [`MAX_REDIRECTS`] redirects to the same
    /// origin. Any final status is a reply.
    pub async fn request(&mut self, r: &Req) -> Result<Reply, Fail> {
        self.send(r, false).await
    }

    /// A write: as [`Client::request`], but a 301 or 302 fails (a client
    /// may send it on as a GET without the body: the write would not be
    /// applied), a 303 is the reply (applied; see the result, not
    /// followed), and 307/308 are followed with the method and the body.
    pub async fn write(&mut self, r: &Req) -> Result<Reply, Fail> {
        self.send(r, true).await
    }

    async fn send(&mut self, r: &Req, write: bool) -> Result<Reply, Fail> {
        let mut method = r.method.clone();
        let mut target = format!("{}{}", self.prep.origin.prefix, r.target);
        if target.is_empty() {
            target.push('/');
        }
        let mut body = r.body.clone();
        for hop in 0..=MAX_REDIRECTS {
            let reply = self.once(&method, &target, body.as_ref()).await?;
            let s = reply.status.as_u16();
            if !matches!(s, 301 | 302 | 303 | 307 | 308) {
                return Ok(reply);
            }
            let what = format!("{method} {}", path_only(&target));
            if write {
                match s {
                    303 => return Ok(reply),
                    301 | 302 => {
                        return Err(Fail::Bad(format!(
                            "{what}: redirected (HTTP {s}); write not applied \
                             (set write_path to the target)"
                        )))
                    }
                    _ => {}
                }
            }
            let Some(loc) = reply
                .headers
                .get(hyper::header::LOCATION)
                .and_then(|v| v.to_str().ok())
            else {
                return Ok(reply);
            };
            if hop == MAX_REDIRECTS {
                return Err(Fail::Bad(format!(
                    "{what}: more than {MAX_REDIRECTS} redirects"
                )));
            }
            target = self
                .resolve(&target, loc)
                .map_err(|e| Fail::Bad(format!("{what}: redirect refused: {e}")))?;
            self.outcomes.push(Outcome::Count(REDIRECTS));
            if s == 303 || (matches!(s, 301 | 302) && method == Method::POST) {
                method = Method::GET;
                body = None;
            }
        }
        Err(Fail::Bad("redirect loop".into()))
    }

    /// A redirect's `Location` as an absolute path and query; only to the
    /// same scheme, host and port.
    fn resolve(&self, current: &str, loc: &str) -> Result<String, String> {
        let o = &self.prep.origin;
        let absolute = strip_ci(loc, "http://").is_some() || strip_ci(loc, "https://").is_some();
        let path = if absolute || loc.starts_with("//") {
            let full = if loc.starts_with("//") {
                format!("{}:{loc}", if o.tls { "https" } else { "http" })
            } else {
                loc.to_owned()
            };
            let (scheme_tls, rest) = match strip_ci(&full, "https://") {
                Some(r) => (true, r),
                None => (false, strip_ci(&full, "http://").unwrap_or(&full)),
            };
            let (auth, path) = match rest.find(['/', '?']) {
                Some(i) => (&rest[..i], &rest[i..]),
                None => (rest, "/"),
            };
            let there = Origin::parse(&format!(
                "{}://{auth}",
                if scheme_tls { "https" } else { "http" }
            ))
            .map_err(|_| "another host".to_owned())?;
            if there.tls != o.tls || there.host != o.host || there.port != o.port {
                return Err("another host".into());
            }
            path.to_owned()
        } else if loc.starts_with('/') {
            loc.to_owned()
        } else {
            // Relative to the current path's directory.
            let dir = path_only(current).rsplit_once('/').map_or("", |(d, _)| d);
            format!("{dir}/{loc}")
        };
        let path = path.split('#').next().unwrap_or_default().to_owned();
        check_chars(&path)?;
        Ok(path)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn origins() {
        let o = Origin::parse("https://Meter.local:8443/api/").unwrap();
        assert_eq!(
            (o.tls, o.host.as_str(), o.port, o.prefix.as_str()),
            (true, "meter.local", 8443, "/api")
        );
        assert_eq!(o.authority(), "meter.local:8443");
        let o = Origin::parse("http://10.0.0.5").unwrap();
        assert_eq!(
            (o.port, o.prefix.as_str(), o.authority()),
            (80, "", "10.0.0.5".into())
        );
        let o = Origin::parse("http://[::1]:8080/x").unwrap();
        assert_eq!((o.host.as_str(), o.port), ("::1", 8080));
        assert_eq!(o.authority(), "[::1]:8080");
        assert!(o.is_loopback());
        assert!(Origin::parse("http://localhost").unwrap().is_loopback());
        assert!(!Origin::parse("http://192.0.2.1").unwrap().is_loopback());
        for bad in [
            "ftp://x",
            "http://",
            "http://u:p@host/",
            "http://host:99999/",
            "http://host:0/",
            "http://host/a?b=1",
            "http://host/a#f",
            "http://ho st/",
            "http://host/a b",
            "http://[::1/",
            // a multi-byte character where the scheme ends: refused, no panic
            "http://über.local/api",
            "https://ü.local",
            "httpü://x",
        ] {
            assert!(Origin::parse(bad).is_err(), "{bad}");
        }
    }

    #[test]
    fn paths_and_queries() {
        assert!(check_path("").is_ok());
        assert!(check_path("/v1/status?x=1&y=%20").is_ok());
        assert!(check_path("v1").is_err());
        assert!(check_path("/a b").is_err());
        assert!(check_path("/a#b").is_err());
        assert!(check_path("/a\u{e9}").is_err());
        assert_eq!(path_only("/a/b?key=secret"), "/a/b");
        assert_eq!(encode_query("a b&c=d~"), "a%20b%26c%3Dd~");
    }

    fn client(prefix: &str) -> Client {
        Client {
            prep: Arc::new(Prepared {
                origin: Origin::parse(&format!("http://host:8080{prefix}")).unwrap(),
                tls: None,
                headers: Vec::new(),
                query_key: None,
                timeout: Duration::from_secs(1),
                interval: Duration::ZERO,
                max_body: 1024,
                masks: Vec::new(),
                numbers: Vec::new(),
                note: None,
            }),
            live: None,
            dirty: false,
            next_slot: None,
            outcomes: Vec::new(),
        }
    }

    #[test]
    fn redirects_stay_on_the_origin() {
        let c = client("/api");
        assert_eq!(c.resolve("/api/a/b", "/api/c?x=1").unwrap(), "/api/c?x=1");
        assert_eq!(c.resolve("/api/a/b?k=1", "c").unwrap(), "/api/a/c");
        assert_eq!(
            c.resolve("/api/a", "http://host:8080/api/z").unwrap(),
            "/api/z"
        );
        assert_eq!(c.resolve("/api/a", "//HOST:8080").unwrap(), "/");
        assert_eq!(c.resolve("/api/a", "/other#frag").unwrap(), "/other");
        assert!(c.resolve("/a", "http://other:8080/api/z").is_err());
        assert!(c.resolve("/a", "https://host:8080/api/z").is_err());
        assert!(c.resolve("/a", "http://host:8081/api/z").is_err());
        assert!(c.resolve("/a", "http://host/api/z").is_err());
        assert!(c.resolve("/a", "/a b").is_err());
        // the scheme in any case: still the origin check, not a relative path
        assert_eq!(c.resolve("/api/a", "HTTP://host:8080/z").unwrap(), "/z");
        assert!(c.resolve("/api/a", "HTTP://other:8080/z").is_err());
    }
}
