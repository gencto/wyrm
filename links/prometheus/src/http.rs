//! One scrape: `GET <url>` over HTTP/1.1 (`hyper` 1), optionally TLS
//! (`tokio-rustls`, ring provider; never aws-lc or native-tls).
//!
//! Every scrape opens its own connection and drops it after the body: a
//! reply that comes after a timeout dies with its connection and can never
//! be taken for a later scrape. The whole scrape (connect, TLS, headers,
//! body) is bounded by the connection's timeout; the body by `max_body`
//! bytes on the wire and again after gzip decoding ([`Fetched::decode`],
//! which the caller runs on a blocking thread).

use bytes::Bytes;
use http_body_util::{BodyExt, Empty};
use hyper::header::{HeaderName, HeaderValue};
use hyper_util::rt::TokioIo;
use rustls::client::danger::{HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier};
use rustls::crypto::CryptoProvider;
use rustls::pki_types::{CertificateDer, PrivateKeyDer, ServerName, UnixTime};
use rustls::{DigitallySignedStruct, SignatureScheme};
use std::io::Read;
use std::net::IpAddr;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, OnceLock};
use std::time::{Duration, Instant};
use tokio::io::{AsyncRead, AsyncWrite};
use tokio::net::TcpStream;
use tokio::task::JoinHandle;
use tokio_rustls::TlsConnector;
use wyrm_link_sdk::Secret;

/// What the scrape asks for: OpenMetrics first, the text format next.
pub const ACCEPT: &str = "application/openmetrics-text;version=1.0.0;q=0.75,\
                          text/plain;version=0.0.4;q=0.5,*/*;q=0.1";

/// Headers the `headers` param may not set: credentials go in secret
/// params, the rest belongs to the client.
pub const RESERVED: [&str; 9] = [
    "authorization",
    "proxy-authorization",
    "cookie",
    "host",
    "content-length",
    "transfer-encoding",
    "connection",
    "accept-encoding",
    "te",
];

/// A parsed `http(s)://host[:port][/path][?query]`.
#[derive(Debug, Clone, PartialEq)]
pub struct Url {
    pub tls: bool,
    /// Without brackets for IPv6.
    pub host: String,
    pub port: u16,
    /// `host[:port]` as given (the `Host` header).
    pub authority: String,
    /// `/path?query` (at least `/`).
    pub target: String,
}

impl Url {
    pub fn parse(s: &str) -> Result<Self, String> {
        let s = s.trim();
        let (tls, rest) = if let Some(r) = s.strip_prefix("https://") {
            (true, r)
        } else if let Some(r) = s.strip_prefix("http://") {
            (false, r)
        } else {
            return Err("must start with http:// or https://".into());
        };
        let end = rest.find(['/', '?', '#']).unwrap_or(rest.len());
        let authority = &rest[..end];
        let mut target = rest[end..].to_owned();
        if let Some(i) = target.find('#') {
            target.truncate(i);
        }
        if !target.starts_with('/') {
            target.insert(0, '/');
        }
        if authority.contains('@') {
            return Err("no user info in the url: use username/password".into());
        }
        let (host, port) = if let Some(r) = authority.strip_prefix('[') {
            let close = r.find(']').ok_or("unclosed [ in the host")?;
            let host = &r[..close];
            host.parse::<std::net::Ipv6Addr>()
                .map_err(|_| "bad IPv6 address")?;
            let port = match &r[close + 1..] {
                "" => None,
                p => Some(p.strip_prefix(':').ok_or("bad port")?),
            };
            (host, port)
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
            Some(p) => p.parse::<u16>().ok().filter(|p| *p > 0).ok_or("bad port")?,
        };
        if host.is_empty()
            || !host
                .bytes()
                .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'.' | b'-' | b'_' | b':'))
        {
            return Err("bad host".into());
        }
        if target.bytes().any(|b| b <= b' ' || b == 0x7f) {
            return Err("spaces or control characters in the path".into());
        }
        Ok(Self {
            tls,
            host: host.to_owned(),
            port,
            authority: authority.to_owned(),
            target,
        })
    }

    pub fn is_loopback(&self) -> bool {
        self.host.eq_ignore_ascii_case("localhost")
            || self.host.parse::<IpAddr>().is_ok_and(|a| a.is_loopback())
    }
}

/// `Name: value` per line → validated headers.
pub fn parse_headers(text: &str) -> Result<Vec<(HeaderName, HeaderValue)>, String> {
    let mut out = Vec::new();
    for line in text.lines() {
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        let (n, v) = line
            .split_once(':')
            .ok_or_else(|| "one `Name: value` per line".to_owned())?;
        let name = HeaderName::from_bytes(n.trim().as_bytes())
            .map_err(|_| format!("bad header name {:?}", n.trim()))?;
        if RESERVED.contains(&name.as_str()) {
            return Err(format!(
                "header {name} is not allowed here (credentials go in username/password or \
                 bearer_token)"
            ));
        }
        let value =
            HeaderValue::from_str(v.trim()).map_err(|_| format!("header {name}: bad value"))?;
        out.push((name, value));
    }
    if out.len() > 32 {
        return Err("at most 32 headers".into());
    }
    Ok(out)
}

/// Client TLS: roots from `ca_pem` (else the system's), optional client
/// certificate, optional no-verify mode. Errors never show key material.
pub fn tls_config(
    ca_pem: &str,
    cert_pem: &str,
    key_pem: &Secret,
    insecure_skip_verify: bool,
) -> Result<rustls::ClientConfig, String> {
    use rustls::pki_types::pem::PemObject;
    let provider = Arc::new(rustls::crypto::ring::default_provider());
    let b = rustls::ClientConfig::builder_with_provider(provider.clone())
        .with_safe_default_protocol_versions()
        .map_err(|e| format!("tls: {e}"))?;
    let b = if insecure_skip_verify {
        b.dangerous()
            .with_custom_certificate_verifier(Arc::new(AnyCert(provider)))
    } else {
        let roots = if ca_pem.trim().is_empty() {
            system_roots()?
        } else {
            let mut roots = rustls::RootCertStore::empty();
            for cert in CertificateDer::pem_slice_iter(ca_pem.as_bytes()) {
                let cert = cert.map_err(|e| format!("ca_pem: {e}"))?;
                roots.add(cert).map_err(|e| format!("ca_pem: {e}"))?;
            }
            if roots.is_empty() {
                return Err("ca_pem: no CA certificates".into());
            }
            Arc::new(roots)
        };
        b.with_root_certificates(roots)
    };
    let mut cfg = if cert_pem.trim().is_empty() {
        b.with_no_client_auth()
    } else {
        let chain = CertificateDer::pem_slice_iter(cert_pem.as_bytes())
            .collect::<Result<Vec<_>, _>>()
            .map_err(|e| format!("cert_pem: {e}"))?;
        if chain.is_empty() {
            return Err("cert_pem: no certificate".into());
        }
        let key = PrivateKeyDer::from_pem_slice(key_pem.expose())
            .map_err(|_| "key_pem: not a PEM private key".to_owned())?;
        b.with_client_auth_cert(chain, key)
            .map_err(|e| format!("cert_pem/key_pem: {e}"))?
    };
    cfg.alpn_protocols = vec![b"http/1.1".to_vec()];
    Ok(cfg)
}

/// The system's root certificates, loaded once per process (blocking file
/// I/O, or Security.framework calls on macOS): not again on every
/// reconnect. A failure is not kept, so a later call tries again.
fn system_roots() -> Result<Arc<rustls::RootCertStore>, String> {
    static ROOTS: OnceLock<Arc<rustls::RootCertStore>> = OnceLock::new();
    if let Some(r) = ROOTS.get() {
        return Ok(r.clone());
    }
    let found = rustls_native_certs::load_native_certs();
    let errors: Vec<String> = found.errors.iter().map(|e| e.to_string()).collect();
    let roots = roots_from(found.certs, &errors)?;
    Ok(ROOTS.get_or_init(|| Arc::new(roots)).clone())
}

/// The root store of the certificates found, or why there is none.
fn roots_from(
    certs: Vec<CertificateDer<'static>>,
    errors: &[String],
) -> Result<rustls::RootCertStore, String> {
    let mut roots = rustls::RootCertStore::empty();
    roots.add_parsable_certificates(certs);
    if roots.is_empty() {
        let why = if errors.is_empty() {
            String::new()
        } else {
            format!(" ({})", errors.join("; "))
        };
        return Err(format!(
            "no system root certificates found{why}: set ca_pem"
        ));
    }
    Ok(roots)
}

/// `insecure_skip_verify`: any server certificate, signatures still checked.
#[derive(Debug)]
struct AnyCert(Arc<CryptoProvider>);

impl ServerCertVerifier for AnyCert {
    fn verify_server_cert(
        &self,
        _end_entity: &CertificateDer<'_>,
        _intermediates: &[CertificateDer<'_>],
        _server_name: &ServerName<'_>,
        _ocsp_response: &[u8],
        _now: UnixTime,
    ) -> Result<ServerCertVerified, rustls::Error> {
        Ok(ServerCertVerified::assertion())
    }

    fn verify_tls12_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, rustls::Error> {
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
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, rustls::Error> {
        rustls::crypto::verify_tls13_signature(
            message,
            cert,
            dss,
            &self.0.signature_verification_algorithms,
        )
    }

    fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
        self.0.signature_verification_algorithms.supported_schemes()
    }
}

/// Why a scrape failed.
#[derive(Debug, Clone, PartialEq)]
pub enum FetchError {
    /// Connect, TLS or I/O failure, or a broken response.
    Io(String),
    /// No complete response within the timeout.
    Timeout,
    /// A response with a non-2xx status.
    Status(u16, String),
    /// The body is over `max_body` (on the wire or decoded).
    TooLarge(String),
}

/// A scrape's body as it came on the wire (at most `max_body` bytes).
pub struct Fetched {
    pub body: Vec<u8>,
    /// `Content-Encoding: gzip` (decode with [`Fetched::decode`]).
    pub gzip: bool,
    pub content_type: String,
    /// From the request to the end of the body.
    pub rtt: Duration,
}

impl Fetched {
    /// The decoded body, at most `max_body` bytes. Blocking work in
    /// proportion to the body: run it off the async runtime. It reads 1 MiB
    /// at a time and stops once `cancel` is set. The error text names the
    /// param.
    pub fn decode(self, max_body: usize, cancel: &AtomicBool) -> Result<Vec<u8>, String> {
        if !self.gzip {
            return Ok(self.body);
        }
        let mut out = Vec::new();
        let limit = max_body as u64 + 1;
        let mut gz = flate2::read::GzDecoder::new(&self.body[..]).take(limit);
        loop {
            if cancel.load(Ordering::Relaxed) {
                return Err("the scrape was cancelled".into());
            }
            let n = (&mut gz)
                .take(1 << 20)
                .read_to_end(&mut out)
                .map_err(|e| format!("gzip body: {e}"))?;
            if n == 0 {
                break;
            }
        }
        if out.len() > max_body {
            return Err(too_large(max_body));
        }
        // `read_to_end` may leave up to twice the bytes allocated.
        out.shrink_to_fit();
        Ok(out)
    }
}

fn too_large(max_body: usize) -> String {
    format!("the response body is over {max_body} bytes (max_body_mib)")
}

/// The scrape client of one connection. No `Debug`: holds credentials.
pub struct Client {
    pub url: Url,
    tls: Option<(TlsConnector, ServerName<'static>)>,
    headers: Vec<(HeaderName, HeaderValue)>,
    /// `Authorization` value (sensitive); built from secret params.
    auth: Option<HeaderValue>,
    gzip: bool,
    max_body: usize,
    timeout: Duration,
}

/// Aborts the HTTP connection task when the scrape ends (or is dropped).
struct AbortOnDrop(JoinHandle<()>);

impl Drop for AbortOnDrop {
    fn drop(&mut self) {
        self.0.abort();
    }
}

impl Client {
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        url: Url,
        tls: Option<rustls::ClientConfig>,
        headers: Vec<(HeaderName, HeaderValue)>,
        auth: Option<HeaderValue>,
        gzip: bool,
        max_body: usize,
        timeout: Duration,
    ) -> Result<Self, String> {
        let tls = match tls {
            None => None,
            Some(cfg) => {
                let name = ServerName::try_from(url.host.clone())
                    .map_err(|_| format!("bad server name {}", url.host))?;
                Some((TlsConnector::from(Arc::new(cfg)), name))
            }
        };
        Ok(Self {
            url,
            tls,
            headers,
            auth,
            gzip,
            max_body,
            timeout,
        })
    }

    pub fn timeout(&self) -> Duration {
        self.timeout
    }

    pub fn max_body(&self) -> usize {
        self.max_body
    }

    pub async fn fetch(&self) -> Result<Fetched, FetchError> {
        let started = Instant::now();
        let mut f = tokio::time::timeout(self.timeout, self.connect_and_get())
            .await
            .map_err(|_| FetchError::Timeout)??;
        f.rtt = started.elapsed();
        Ok(f)
    }

    async fn connect_and_get(&self) -> Result<Fetched, FetchError> {
        let a = &self.url.authority;
        // never link-local or metadata addresses, whatever the name resolves to (review LNK-1)
        let addrs = wyrm_link_sdk::outbound::resolve(&self.url.host, self.url.port)
            .await
            .map_err(FetchError::Io)?;
        let tcp = TcpStream::connect(&addrs[..])
            .await
            .map_err(|e| FetchError::Io(format!("connect {a}: {e}")))?;
        let _ = tcp.set_nodelay(true);
        match &self.tls {
            None => self.get(tcp).await,
            Some((connector, name)) => {
                let s = connector
                    .connect(name.clone(), tcp)
                    .await
                    .map_err(|e| FetchError::Io(format!("tls {a}: {e}")))?;
                self.get(s).await
            }
        }
    }

    async fn get<S>(&self, io: S) -> Result<Fetched, FetchError>
    where
        S: AsyncRead + AsyncWrite + Unpin + Send + 'static,
    {
        let io_err = |e: hyper::Error| FetchError::Io(format!("http: {e}"));
        let (mut sender, conn) = hyper::client::conn::http1::handshake(TokioIo::new(io))
            .await
            .map_err(io_err)?;
        let _conn = AbortOnDrop(tokio::spawn(async move {
            if let Err(e) = conn.await {
                tracing::trace!("scrape connection: {e}");
            }
        }));
        let mut req = hyper::Request::get(self.url.target.as_str())
            .header(hyper::header::HOST, self.url.authority.as_str())
            .header(hyper::header::ACCEPT, ACCEPT)
            .header(
                hyper::header::USER_AGENT,
                concat!("wyrm-prometheus/", env!("CARGO_PKG_VERSION")),
            );
        if self.gzip {
            req = req.header(hyper::header::ACCEPT_ENCODING, "gzip");
        }
        if let Some(a) = &self.auth {
            req = req.header(hyper::header::AUTHORIZATION, a.clone());
        }
        for (n, v) in &self.headers {
            req = req.header(n, v);
        }
        let req = req
            .body(Empty::<Bytes>::new())
            .map_err(|_| FetchError::Io("bad request".into()))?;
        let resp = sender.send_request(req).await.map_err(io_err)?;
        let status = resp.status();
        if !status.is_success() {
            return Err(FetchError::Status(
                status.as_u16(),
                status.canonical_reason().unwrap_or("").to_owned(),
            ));
        }
        let header = |n: hyper::header::HeaderName| {
            resp.headers()
                .get(n)
                .and_then(|v| v.to_str().ok())
                .unwrap_or("")
                .to_ascii_lowercase()
        };
        let content_type = header(hyper::header::CONTENT_TYPE);
        let encoding = header(hyper::header::CONTENT_ENCODING);
        let gzip = match encoding.as_str() {
            "" | "identity" => false,
            "gzip" | "x-gzip" => true,
            other => {
                return Err(FetchError::Io(format!(
                    "unsupported content-encoding {other:?}"
                )))
            }
        };
        let too_large = || FetchError::TooLarge(too_large(self.max_body));
        let declared = header(hyper::header::CONTENT_LENGTH)
            .parse::<u64>()
            .unwrap_or(0);
        if declared > self.max_body as u64 {
            return Err(too_large());
        }
        let mut body = resp.into_body();
        let mut buf = Vec::new();
        while let Some(frame) = body.frame().await {
            let frame = frame.map_err(io_err)?;
            if let Ok(d) = frame.into_data() {
                if buf.len() + d.len() > self.max_body {
                    return Err(too_large());
                }
                buf.extend_from_slice(&d);
            }
        }
        Ok(Fetched {
            body: buf,
            gzip,
            content_type,
            rtt: Duration::ZERO,
        })
    }
}

/// `Basic base64(user:password)` or `Bearer token`, marked sensitive.
pub fn auth_header(username: &str, password: &Secret, bearer: &Secret) -> Option<HeaderValue> {
    use base64::Engine;
    let text = if !bearer.expose().is_empty() {
        let mut t = b"Bearer ".to_vec();
        t.extend_from_slice(bearer.expose());
        t
    } else if !username.is_empty() {
        let mut raw = username.as_bytes().to_vec();
        raw.push(b':');
        raw.extend_from_slice(password.expose());
        let mut t = b"Basic ".to_vec();
        t.extend_from_slice(
            base64::engine::general_purpose::STANDARD
                .encode(&raw)
                .as_bytes(),
        );
        raw.iter_mut().for_each(|b| *b = 0);
        t
    } else {
        return None;
    };
    let mut v = HeaderValue::from_bytes(&text).ok()?;
    v.set_sensitive(true);
    Some(v)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn urls() {
        let u = Url::parse("http://host:9100/metrics").unwrap();
        assert_eq!(
            (u.tls, u.host.as_str(), u.port, u.target.as_str()),
            (false, "host", 9100, "/metrics")
        );
        let u = Url::parse("https://example.org").unwrap();
        assert_eq!((u.tls, u.port, u.target.as_str()), (true, 443, "/"));
        let u = Url::parse("http://[::1]:8080/m?x=1#frag").unwrap();
        assert_eq!(
            (u.host.as_str(), u.port, u.target.as_str(), u.is_loopback()),
            ("::1", 8080, "/m?x=1", true)
        );
        assert_eq!(Url::parse("http://h?a=b").unwrap().target, "/?a=b");
        assert!(Url::parse("http://localhost/").unwrap().is_loopback());
        assert!(!Url::parse("http://10.0.0.1/").unwrap().is_loopback());
        for bad in [
            "ftp://h/",
            "h:9100",
            "http://user:pw@h/",
            "http://:80/",
            "http://h:0/",
            "http://h:99999/",
            "http://[::1/",
            "http://h/a b",
            "http://h p/",
        ] {
            assert!(Url::parse(bad).is_err(), "{bad}");
        }
    }

    #[test]
    fn headers() {
        let h = parse_headers("X-Scope-OrgID: plant\n\n  X-Other:  a b \n").unwrap();
        assert_eq!(h.len(), 2);
        assert_eq!(h[1].1, "a b");
        assert!(parse_headers("Authorization: Bearer x").is_err());
        assert!(parse_headers("cookie: a=b").is_err());
        assert!(parse_headers("no colon").is_err());
        assert!(parse_headers("bad name: x").is_err());
    }

    #[test]
    fn no_system_roots() {
        let e = roots_from(Vec::new(), &["open /etc/ssl/certs: not found".into()])
            .err()
            .unwrap();
        assert!(e.starts_with("no system root certificates found"), "{e}");
        assert!(e.contains("not found") && e.ends_with("set ca_pem"), "{e}");
        assert!(!e.starts_with("ca_pem"), "{e}");
        let e = roots_from(Vec::new(), &[]).err().unwrap();
        assert_eq!(e, "no system root certificates found: set ca_pem");
    }

    #[test]
    fn authorization() {
        let none = Secret::new(Vec::new());
        assert!(auth_header("", &none, &none).is_none());
        let v = auth_header("user", &Secret::new("pass"), &none).unwrap();
        assert_eq!(v, "Basic dXNlcjpwYXNz");
        assert!(v.is_sensitive());
        let v = auth_header("", &none, &Secret::new("tok")).unwrap();
        assert_eq!(v, "Bearer tok");
    }
}
