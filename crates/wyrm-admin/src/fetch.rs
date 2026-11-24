//! Downloads of link packages and repository indexes (ADR 0011): an HTTPS
//! GET with the `webpki-roots` store (ring provider, never aws-lc), at most
//! three redirects, a size limit and a time limit. Plain HTTP only to a
//! loopback address (a local mirror, tests).

use bytes::Bytes;
use http_body_util::{BodyExt, Empty, Limited};
use hyper_util::rt::TokioIo;
use rustls_pki_types::ServerName;
use std::sync::Arc;
use std::time::Duration;
use tokio::io::{AsyncRead, AsyncWrite};
use tokio::net::TcpStream;
use tokio_rustls::TlsConnector;
use wyrm_core::weburl::{HttpUrl, SchemeCase, Url, UrlError};

const MAX_REDIRECTS: usize = 3;

/// Why a download gave no bytes. No variant holds the URL, its path or its
/// query (a query may hold a token): the host at most.
#[derive(Debug, thiserror::Error)]
pub enum FetchError {
    /// No scheme, or one that is not `https` (`http` to loopback).
    #[error("url: https:// only")]
    Scheme,
    /// A user or password in the URL; never repeated.
    #[error("url: no credentials in the URL")]
    Credentials,
    /// Anything else the URL parser refuses.
    #[error("url: {0}")]
    Url(#[source] UrlError),
    #[error("{host}: plain http only to a loopback address")]
    PlainHttp { host: String },
    #[error("{host}: no #fragment in the URL")]
    Fragment { host: String },
    /// The TLS client was not built.
    #[error("tls: {0}")]
    TlsConfig(#[source] rustls::Error),
    #[error("connect {host}: {source}")]
    Connect {
        host: String,
        #[source]
        source: std::io::Error,
    },
    #[error("bad server name {host}")]
    ServerName {
        host: String,
        #[source]
        source: rustls_pki_types::InvalidDnsNameError,
    },
    /// The TLS handshake: the certificate, the protocol, the connection.
    #[error("tls {host}: {source}")]
    Tls {
        host: String,
        #[source]
        source: std::io::Error,
    },
    /// The HTTP handshake or the exchange of the request.
    #[error("http: {0}")]
    Http(#[source] hyper::Error),
    #[error("build request")]
    Request(#[source] hyper::http::Error),
    /// A redirect that names no place.
    #[error("HTTP {0} without a location")]
    NoLocation(hyper::StatusCode),
    /// An answer that is neither a success nor a redirect: its code.
    #[error("HTTP {0}")]
    Status(u16),
    /// The body is larger than the caller takes (`max` bytes).
    #[error("body: {source} (limit {} MiB)", .max >> 20)]
    TooLarge {
        max: usize,
        #[source]
        source: Box<http_body_util::LengthLimitError>,
    },
    /// The body did not arrive whole.
    #[error("body: {source} (limit {} MiB)", .max >> 20)]
    Body {
        max: usize,
        #[source]
        source: Box<dyn std::error::Error + Send + Sync>,
    },
    #[error("more than {0} redirects")]
    Redirects(usize),
    /// The whole exchange took longer than the caller waits.
    #[error("{host}: no answer in {secs} s")]
    Timeout { host: String, secs: u64 },
}

#[derive(Debug, PartialEq)]
struct Target {
    tls: bool,
    host: String,
    port: u16,
    /// Path and query, `/` at least.
    path: String,
}

fn loopback(host: &str) -> bool {
    matches!(host, "localhost" | "127.0.0.1" | "[::1]")
}

/// `https://` (or `http://` to loopback) `host[:port][/path][?query]`, read by
/// [`wyrm_core::weburl`]. The message names the host at most, never the URL.
fn parse(url: &str) -> Result<Target, FetchError> {
    let u = HttpUrl::parse(url, SchemeCase::Lower).map_err(|e| match e {
        UrlError::NoScheme | UrlError::Scheme => FetchError::Scheme,
        UrlError::Credentials => FetchError::Credentials,
        e => FetchError::Url(e),
    })?;
    let host = u.url.host.url_form();
    if !u.tls && !loopback(&host) {
        return Err(FetchError::PlainHttp { host });
    }
    if u.url.fragment.is_some() {
        return Err(FetchError::Fragment { host });
    }
    Ok(Target {
        tls: u.tls,
        port: u.port,
        path: u.url.target(),
        host,
    })
}

/// `location` of a redirect, absolute or an absolute path on `t`'s host.
fn redirect(t: &Target, location: &str) -> String {
    if !matches!(Url::parse(location), Err(UrlError::NoScheme)) {
        // a URL (or a malformed one, which `parse` then refuses)
        return location.to_owned();
    }
    let scheme = if t.tls { "https" } else { "http" };
    format!("{scheme}://{}:{}{location}", t.host, t.port)
}

fn tls() -> Result<TlsConnector, FetchError> {
    let mut roots = rustls::RootCertStore::empty();
    roots.extend(webpki_roots::TLS_SERVER_ROOTS.iter().cloned());
    let provider = Arc::new(rustls::crypto::ring::default_provider());
    let mut cfg = rustls::ClientConfig::builder_with_provider(provider)
        .with_safe_default_protocol_versions()
        .map_err(FetchError::TlsConfig)?
        .with_root_certificates(roots)
        .with_no_client_auth();
    cfg.alpn_protocols = vec![b"http/1.1".to_vec()];
    Ok(TlsConnector::from(Arc::new(cfg)))
}

enum Answer {
    Body(Vec<u8>),
    Redirect(String),
}

async fn exchange<IO>(io: IO, t: &Target, max: usize) -> Result<Answer, FetchError>
where
    IO: AsyncRead + AsyncWrite + Unpin + Send + 'static,
{
    let (mut sender, conn) = hyper::client::conn::http1::handshake(TokioIo::new(io))
        .await
        .map_err(FetchError::Http)?;
    let conn = tokio::spawn(async move {
        let _ = conn.await;
    });
    let req = hyper::Request::get(t.path.as_str())
        .header(hyper::header::HOST, t.host.as_str())
        .header(hyper::header::USER_AGENT, "wyrmd")
        .body(Empty::<Bytes>::new())
        .map_err(FetchError::Request)?;
    let resp = sender.send_request(req).await.map_err(FetchError::Http)?;
    let status = resp.status();
    if status.is_redirection() {
        conn.abort();
        let loc = resp
            .headers()
            .get(hyper::header::LOCATION)
            .and_then(|v| v.to_str().ok())
            .ok_or(FetchError::NoLocation(status))?;
        return Ok(Answer::Redirect(redirect(t, loc)));
    }
    if !status.is_success() {
        conn.abort();
        return Err(FetchError::Status(status.as_u16()));
    }
    let body = Limited::new(resp.into_body(), max)
        .collect()
        .await
        .map_err(|e| match e.downcast::<http_body_util::LengthLimitError>() {
            Ok(source) => FetchError::TooLarge { max, source },
            Err(source) => FetchError::Body { max, source },
        })?
        .to_bytes();
    conn.abort();
    Ok(Answer::Body(body.to_vec()))
}

async fn get_inner(url: &str, max: usize) -> Result<Vec<u8>, FetchError> {
    let mut url = url.trim().to_owned();
    for _ in 0..=MAX_REDIRECTS {
        let t = parse(&url)?;
        let host = || t.host.clone();
        let tcp = TcpStream::connect((t.host.trim_matches(['[', ']']), t.port))
            .await
            .map_err(|source| {
                let host = host();
                FetchError::Connect { host, source }
            })?;
        let answer = if t.tls {
            let name = ServerName::try_from(t.host.clone()).map_err(|source| {
                let host = host();
                FetchError::ServerName { host, source }
            })?;
            let io = tls()?.connect(name, tcp).await.map_err(|source| {
                let host = host();
                FetchError::Tls { host, source }
            })?;
            exchange(io, &t, max).await?
        } else {
            exchange(tcp, &t, max).await?
        };
        match answer {
            Answer::Body(b) => return Ok(b),
            Answer::Redirect(next) => url = next,
        }
    }
    Err(FetchError::Redirects(MAX_REDIRECTS))
}

/// GET `url` (https, or http to loopback), at most `max` bytes, within
/// `timeout` for the whole exchange (redirects included).
pub async fn get(url: &str, max: usize, timeout: Duration) -> Result<Vec<u8>, FetchError> {
    // the message names the host, never the URL (a query may hold a token)
    let host = parse(url.trim()).map(|t| t.host).unwrap_or_default();
    match tokio::time::timeout(timeout, get_inner(url, max)).await {
        Ok(got) => got,
        Err(tokio::time::error::Elapsed { .. }) => Err(FetchError::Timeout {
            host,
            secs: timeout.as_secs(),
        }),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The parser before review S4, kept to compare.
    fn old_parse(url: &str) -> Result<Target, String> {
        let (tls, rest) = if let Some(r) = url.strip_prefix("https://") {
            (true, r)
        } else if let Some(r) = url.strip_prefix("http://") {
            (false, r)
        } else {
            return Err("url: https:// only".into());
        };
        let (authority, path) = match rest.find('/') {
            Some(i) => (&rest[..i], &rest[i..]),
            None => (rest, "/"),
        };
        if authority.contains('@') {
            // never echo it: the part before '@' may be a token
            return Err("url: no credentials in the URL".into());
        }
        let (host, port) = match authority.rsplit_once(':') {
            Some((h, p)) if !h.ends_with(']') || authority.starts_with('[') => {
                (h, p.parse::<u16>().map_err(|_| format!("{url}: bad port"))?)
            }
            _ => (authority, if tls { 443 } else { 80 }),
        };
        if host.is_empty() || host.contains([' ', '/', '\\']) {
            return Err(format!("{url}: bad host"));
        }
        if !tls && !loopback(host) {
            return Err(format!("{url}: plain http only to a loopback address"));
        }
        if path.contains(['\r', '\n', ' ']) {
            return Err(format!("{url}: bad path"));
        }
        Ok(Target {
            tls,
            host: host.to_owned(),
            port,
            path: path.to_owned(),
        })
    }

    /// `location` of a redirect, absolute or an absolute path on `t`'s host.
    fn old_redirect(t: &Target, location: &str) -> String {
        if location.starts_with("https://") || location.starts_with("http://") {
            return location.to_owned();
        }
        let scheme = if t.tls { "https" } else { "http" };
        format!("{scheme}://{}:{}{location}", t.host, t.port)
    }

    /// Review S4: every URL the old parser took parses the same, and a redirect goes to
    /// the same place; what it refused stays refused. No message repeats the URL.
    #[test]
    fn urls_parse_as_before() {
        for s in [
            "https://pkg.example:8443/a/b.zip?x=1",
            "https://h",
            "http://127.0.0.1:9/x",
            "http://localhost:8080/index.json",
            "http://[::1]:9/i.json",
            "https://github.com/acme/links/releases/download/v1/index.json",
        ] {
            assert_eq!(parse(s).ok(), old_parse(s).ok(), "{s}");
            let t = parse(s).unwrap();
            for loc in ["/b", "https://o/c", "http://127.0.0.1:1/d"] {
                assert_eq!(redirect(&t, loc), old_redirect(&t, loc), "{s} {loc}");
            }
        }
        for s in [
            "ftp://h/x",
            "https://user:s3cret@h/x",
            "https://h:99999/x",
            "http://pkg.example/x",
            "https://h/a b",
            "https://h/a\r\nx",
            "HTTPS://h/x",
            "https://",
        ] {
            assert!(old_parse(s).is_err(), "old took {s}");
            // neither the text nor the value itself (`Debug`, the source)
            let e = parse(s).unwrap_err();
            let e = format!("{e} {e:?} {:?}", std::error::Error::source(&e));
            assert!(!e.contains("s3cret") && !e.contains("/x"), "{s}: {e}");
        }
        assert!(matches!(parse("ftp://h/x"), Err(FetchError::Scheme)));
        assert!(matches!(parse("HTTPS://h/x"), Err(FetchError::Scheme)));
        assert!(matches!(
            parse("https://user:s3cret@h/x"),
            Err(FetchError::Credentials)
        ));
        assert!(matches!(
            parse("https://h:99999/x"),
            Err(FetchError::Url(UrlError::Port))
        ));
        assert!(matches!(
            parse("http://pkg.example/x"),
            Err(FetchError::PlainHttp { host }) if host == "pkg.example"
        ));
        assert!(matches!(
            parse("https://h/x#f"),
            Err(FetchError::Fragment { host }) if host == "h"
        ));
        // refused now, taken before: a fragment (it went into the request line), port 0,
        // a garbled host
        for s in [
            "https://h/x#f",
            "https://h:0/",
            "https://h%41/",
            "https://a b/",
        ] {
            assert!(parse(s).is_err(), "{s}");
        }
        // a query right after the host was read into the host; now it is a query
        assert_eq!(old_parse("https://h?x=1").unwrap().host, "h?x=1");
        let t = parse("https://h?x=1").unwrap();
        assert_eq!((t.host.as_str(), t.path.as_str()), ("h", "/?x=1"));
    }

    /// Every refusal says what it said as text: these are the answers of
    /// `install_url`, `install_repo` and the broker's own update.
    #[test]
    fn refusals_read_as_before() {
        fn said(e: &FetchError, text: &str) {
            assert_eq!(e.to_string(), text);
        }
        type E = FetchError;
        let io = || std::io::Error::other("no");
        let host = || "h.example".to_owned();
        said(&E::Scheme, "url: https:// only");
        said(&E::Credentials, "url: no credentials in the URL");
        said(&E::Url(UrlError::Port), "url: bad port");
        said(
            &E::PlainHttp { host: host() },
            "h.example: plain http only to a loopback address",
        );
        said(
            &E::Fragment { host: host() },
            "h.example: no #fragment in the URL",
        );
        said(
            &E::TlsConfig(rustls::Error::HandshakeNotComplete),
            "tls: handshake not complete",
        );
        said(
            &E::Connect {
                host: host(),
                source: io(),
            },
            "connect h.example: no",
        );
        let name = ServerName::try_from("a b".to_owned()).unwrap_err();
        said(
            &E::ServerName {
                host: "a b".into(),
                source: name,
            },
            "bad server name a b",
        );
        said(
            &E::Tls {
                host: host(),
                source: io(),
            },
            "tls h.example: no",
        );
        let request = hyper::Request::get("a b").body(()).unwrap_err();
        said(&E::Request(request), "build request");
        said(
            &E::NoLocation(hyper::StatusCode::FOUND),
            "HTTP 302 Found without a location",
        );
        said(&E::Status(404), "HTTP 404");
        // the limit's own error is made only by reading past a limit
        let over = tokio::runtime::Builder::new_current_thread()
            .build()
            .unwrap()
            .block_on(
                Limited::new(http_body_util::Full::new(Bytes::from_static(b"xx")), 1).collect(),
            )
            .unwrap_err()
            .downcast::<http_body_util::LengthLimitError>()
            .unwrap();
        said(
            &E::TooLarge {
                max: 64 << 20,
                source: over,
            },
            "body: length limit exceeded (limit 64 MiB)",
        );
        said(
            &E::Body {
                max: 3 << 20,
                source: "no".into(),
            },
            "body: no (limit 3 MiB)",
        );
        said(&E::Redirects(MAX_REDIRECTS), "more than 3 redirects");
        said(
            &E::Timeout {
                host: host(),
                secs: 15,
            },
            "h.example: no answer in 15 s",
        );
    }

    /// One answer of a server on loopback for every request.
    async fn serve(answer: &'static str) -> String {
        use tokio::io::{AsyncReadExt, AsyncWriteExt};
        let l = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let port = l.local_addr().unwrap().port();
        tokio::spawn(async move {
            while let Ok((mut s, _)) = l.accept().await {
                let mut head = Vec::new();
                while !head.ends_with(b"\r\n\r\n") {
                    let mut b = [0u8; 1];
                    if s.read(&mut b).await.unwrap_or(0) == 0 {
                        break;
                    }
                    head.push(b[0]);
                }
                if answer.is_empty() {
                    // holds the connection and says nothing
                    tokio::time::sleep(Duration::from_secs(30)).await;
                }
                s.write_all(answer.as_bytes()).await.unwrap();
            }
        });
        format!("http://127.0.0.1:{port}/x?token=s3cret")
    }

    /// What a server answers is told apart by type, and no refusal holds
    /// the path or the query of the URL.
    #[tokio::test]
    async fn answers_are_told_apart() {
        let t = Duration::from_secs(5);
        let close = "Content-Length: 5\r\nConnection: close\r\n\r\nhello";
        type Is = fn(&FetchError) -> bool;
        let cases: [(&str, Is); 5] = [
            ("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n", |e| {
                matches!(e, FetchError::Status(404))
            }),
            ("HTTP/1.1 302 Found\r\nContent-Length: 0\r\n\r\n", |e| {
                matches!(e, FetchError::NoLocation(hyper::StatusCode::FOUND))
            }),
            (
                "HTTP/1.1 302 Found\r\nLocation: /x\r\nContent-Length: 0\r\n\r\n",
                |e| matches!(e, FetchError::Redirects(3)),
            ),
            (
                "HTTP/1.1 302 Found\r\nLocation: https://u:s3cret@h/x\r\nContent-Length: 0\r\n\r\n",
                |e| matches!(e, FetchError::Credentials),
            ),
            ("this is no http\r\n\r\n", |e| {
                matches!(e, FetchError::Http(_))
            }),
        ];
        for (answer, is) in cases {
            let e = get(&serve(answer).await, 1 << 20, t).await.unwrap_err();
            assert!(is(&e), "{answer}: {e:?}");
            let shown = format!("{e} {e:?}");
            assert!(
                !shown.contains("s3cret") && !shown.contains("/x"),
                "{shown}"
            );
        }
        let ok = format!("HTTP/1.1 200 OK\r\n{close}");
        let url = serve(Box::leak(ok.into_boxed_str())).await;
        assert_eq!(get(&url, 5, t).await.unwrap(), b"hello");
        // one byte more than the caller takes
        let e = get(&url, 4, t).await.unwrap_err();
        assert!(matches!(e, FetchError::TooLarge { max: 4, .. }), "{e:?}");
        // a server that never answers
        let e = get(&serve("").await, 5, Duration::from_millis(200))
            .await
            .unwrap_err();
        assert!(
            matches!(&e, FetchError::Timeout { host, secs: 0 } if host == "127.0.0.1"),
            "{e:?}"
        );
    }

    #[test]
    fn urls() {
        let t = parse("https://pkg.example:8443/a/b.zip?x=1").unwrap();
        assert_eq!(
            t,
            Target {
                tls: true,
                host: "pkg.example".into(),
                port: 8443,
                path: "/a/b.zip?x=1".into()
            }
        );
        assert_eq!(parse("https://h").unwrap().path, "/");
        assert_eq!(parse("https://h").unwrap().port, 443);
        assert!(parse("http://127.0.0.1:9/x").is_ok());
        assert!(
            parse("http://pkg.example/x").is_err(),
            "plain http off loopback"
        );
        assert!(parse("ftp://h/x").is_err());
        let err = parse("https://user:s3cret@h/x").unwrap_err();
        let err = format!("{err} {err:?}");
        assert!(!err.contains("s3cret"), "{err}");
        assert!(parse("https://h:99999/x").is_err());
        let t = parse("http://127.0.0.1:9/a").unwrap();
        assert_eq!(redirect(&t, "/b"), "http://127.0.0.1:9/b");
        assert_eq!(redirect(&t, "https://o/c"), "https://o/c");
    }
}
