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

const MAX_REDIRECTS: usize = 3;

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

fn parse(url: &str) -> Result<Target, String> {
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
fn redirect(t: &Target, location: &str) -> String {
    if location.starts_with("https://") || location.starts_with("http://") {
        return location.to_owned();
    }
    let scheme = if t.tls { "https" } else { "http" };
    format!("{scheme}://{}:{}{location}", t.host, t.port)
}

fn tls() -> Result<TlsConnector, String> {
    let mut roots = rustls::RootCertStore::empty();
    roots.extend(webpki_roots::TLS_SERVER_ROOTS.iter().cloned());
    let provider = Arc::new(rustls::crypto::ring::default_provider());
    let mut cfg = rustls::ClientConfig::builder_with_provider(provider)
        .with_safe_default_protocol_versions()
        .map_err(|e| format!("tls: {e}"))?
        .with_root_certificates(roots)
        .with_no_client_auth();
    cfg.alpn_protocols = vec![b"http/1.1".to_vec()];
    Ok(TlsConnector::from(Arc::new(cfg)))
}

enum Answer {
    Body(Vec<u8>),
    Redirect(String),
}

async fn exchange<IO>(io: IO, t: &Target, max: usize) -> Result<Answer, String>
where
    IO: AsyncRead + AsyncWrite + Unpin + Send + 'static,
{
    let (mut sender, conn) = hyper::client::conn::http1::handshake(TokioIo::new(io))
        .await
        .map_err(|e| format!("http: {e}"))?;
    let conn = tokio::spawn(async move {
        let _ = conn.await;
    });
    let req = hyper::Request::get(t.path.as_str())
        .header(hyper::header::HOST, t.host.as_str())
        .header(hyper::header::USER_AGENT, "wyrmd")
        .body(Empty::<Bytes>::new())
        .map_err(|_| "build request".to_owned())?;
    let resp = sender
        .send_request(req)
        .await
        .map_err(|e| format!("http: {e}"))?;
    let status = resp.status();
    if status.is_redirection() {
        conn.abort();
        let loc = resp
            .headers()
            .get(hyper::header::LOCATION)
            .and_then(|v| v.to_str().ok())
            .ok_or_else(|| format!("HTTP {status} without a location"))?;
        return Ok(Answer::Redirect(redirect(t, loc)));
    }
    if !status.is_success() {
        conn.abort();
        return Err(format!("HTTP {}", status.as_u16()));
    }
    let body = Limited::new(resp.into_body(), max)
        .collect()
        .await
        .map_err(|e| format!("body: {e} (limit {} MiB)", max >> 20))?
        .to_bytes();
    conn.abort();
    Ok(Answer::Body(body.to_vec()))
}

async fn get_inner(url: &str, max: usize) -> Result<Vec<u8>, String> {
    let mut url = url.trim().to_owned();
    for _ in 0..=MAX_REDIRECTS {
        let t = parse(&url)?;
        let tcp = TcpStream::connect((t.host.trim_matches(['[', ']']), t.port))
            .await
            .map_err(|e| format!("connect {}: {e}", t.host))?;
        let answer = if t.tls {
            let name = ServerName::try_from(t.host.clone())
                .map_err(|_| format!("bad server name {}", t.host))?;
            let io = tls()?
                .connect(name, tcp)
                .await
                .map_err(|e| format!("tls {}: {e}", t.host))?;
            exchange(io, &t, max).await?
        } else {
            exchange(tcp, &t, max).await?
        };
        match answer {
            Answer::Body(b) => return Ok(b),
            Answer::Redirect(next) => url = next,
        }
    }
    Err(format!("more than {MAX_REDIRECTS} redirects"))
}

/// GET `url` (https, or http to loopback), at most `max` bytes, within
/// `timeout` for the whole exchange (redirects included).
pub async fn get(url: &str, max: usize, timeout: Duration) -> Result<Vec<u8>, String> {
    tokio::time::timeout(timeout, get_inner(url, max))
        .await
        .map_err(|_| format!("{url}: no answer in {} s", timeout.as_secs()))?
}

#[cfg(test)]
mod tests {
    use super::*;

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
        assert!(!err.contains("s3cret"), "{err}");
        assert!(parse("https://h:99999/x").is_err());
        let t = parse("http://127.0.0.1:9/a").unwrap();
        assert_eq!(redirect(&t, "/b"), "http://127.0.0.1:9/b");
        assert_eq!(redirect(&t, "https://o/c"), "https://o/c");
    }
}
