//! Minimal Anthropic Messages API client (`POST /v1/messages`, tool use).
//!
//! Raw HTTP/1.1 over `tokio-rustls` with the ring provider (never aws-lc),
//! roots from `webpki-roots`. One connection per request: planning makes a
//! handful of calls per task, so pooling buys nothing.
//!
//! The API key comes from the link's `SecretStore`; it is sent only in the
//! `x-api-key` header and never appears in errors, logs or the tree.

use bytes::Bytes;
use http_body_util::{BodyExt, Full, Limited};
use hyper_util::rt::TokioIo;
use rustls_pki_types::ServerName;
use serde_json::Value as Json;
use std::future::Future;
use std::pin::Pin;
use std::sync::Arc;
use std::time::Duration;
use tokio::net::TcpStream;
use tokio_rustls::TlsConnector;
use zeroize::Zeroizing;

/// Boxed future of one Messages API call.
pub type LlmFuture<'a> = Pin<Box<dyn Future<Output = Result<Json, String>> + Send + 'a>>;

/// A Messages API backend. `body` is the request JSON; the result is the
/// response JSON (`content`, `stop_reason`, `usage`). Tests use a scripted
/// fake; production uses [`AnthropicClient`].
pub trait LlmClient: Send + Sync + 'static {
    fn messages(&self, body: Json) -> LlmFuture<'_>;
}

/// Most bytes read from one response body.
const MAX_RESPONSE: usize = 8 << 20;
pub const API_VERSION: &str = "2023-06-01";
/// Beta of the `fallbacks: "default"` form (server-side refusal fallback).
pub const FALLBACK_BETA: &str = "server-side-fallback-2026-07-01";

/// No `Debug`: holds the API key.
pub struct AnthropicClient {
    api_key: Zeroizing<String>,
    host: String,
    port: u16,
    path: String,
    tls: TlsConnector,
    timeout: Duration,
    fallbacks: bool,
}

/// `https://host[:port][/prefix]` → `(host, port, prefix)`. Only https.
pub fn parse_base(base: &str) -> Result<(String, u16, String), String> {
    let rest = base
        .trim()
        .strip_prefix("https://")
        .ok_or("api_base must start with https://")?;
    let (authority, prefix) = match rest.find('/') {
        Some(i) => (&rest[..i], rest[i..].trim_end_matches('/')),
        None => (rest, ""),
    };
    let (host, port) = match authority.rsplit_once(':') {
        Some((h, p)) => (
            h,
            p.parse::<u16>()
                .map_err(|_| "api_base: bad port".to_owned())?,
        ),
        None => (authority, 443),
    };
    if host.is_empty() || host.contains(['@', '[', ']', ' ']) {
        return Err("api_base: bad host".into());
    }
    Ok((host.to_owned(), port, format!("{prefix}/v1/messages")))
}

impl AnthropicClient {
    pub fn new(
        api_key: Zeroizing<String>,
        api_base: &str,
        timeout: Duration,
        fallbacks: bool,
    ) -> Result<Self, String> {
        let (host, port, path) = parse_base(api_base)?;
        let mut roots = rustls::RootCertStore::empty();
        roots.extend(webpki_roots::TLS_SERVER_ROOTS.iter().cloned());
        let provider = Arc::new(rustls::crypto::ring::default_provider());
        let mut cfg = rustls::ClientConfig::builder_with_provider(provider)
            .with_safe_default_protocol_versions()
            .map_err(|e| format!("tls: {e}"))?
            .with_root_certificates(roots)
            .with_no_client_auth();
        cfg.alpn_protocols = vec![b"http/1.1".to_vec()];
        Ok(Self {
            api_key,
            host,
            port,
            path,
            tls: TlsConnector::from(Arc::new(cfg)),
            timeout,
            fallbacks,
        })
    }

    async fn post(&self, mut body: Json) -> Result<Json, String> {
        if self.fallbacks {
            if let Json::Object(o) = &mut body {
                o.insert("fallbacks".into(), "default".into());
            }
        }
        let bytes = serde_json::to_vec(&body).map_err(|e| e.to_string())?;
        let tcp = TcpStream::connect((self.host.as_str(), self.port))
            .await
            .map_err(|e| format!("connect {}: {e}", self.host))?;
        let name = ServerName::try_from(self.host.clone())
            .map_err(|_| format!("bad server name {}", self.host))?;
        let tls = self
            .tls
            .connect(name, tcp)
            .await
            .map_err(|e| format!("tls {}: {e}", self.host))?;
        let (mut sender, conn) = hyper::client::conn::http1::handshake(TokioIo::new(tls))
            .await
            .map_err(|e| format!("http: {e}"))?;
        let conn = tokio::spawn(async move {
            if let Err(e) = conn.await {
                tracing::debug!("llm connection: {e}");
            }
        });
        let mut req = hyper::Request::post(self.path.as_str())
            .header(hyper::header::HOST, self.host.as_str())
            .header(hyper::header::CONTENT_TYPE, "application/json")
            .header("anthropic-version", API_VERSION)
            .header("x-api-key", self.api_key.as_str());
        if self.fallbacks {
            req = req.header("anthropic-beta", FALLBACK_BETA);
        }
        let req = req
            .body(Full::new(Bytes::from(bytes)))
            .map_err(|_| "build request".to_owned())?;
        let resp = sender
            .send_request(req)
            .await
            .map_err(|e| format!("http: {e}"))?;
        let status = resp.status();
        let body = Limited::new(resp.into_body(), MAX_RESPONSE)
            .collect()
            .await
            .map_err(|e| format!("read body: {e}"))?
            .to_bytes();
        conn.abort();
        let json: Json = serde_json::from_slice(&body)
            .map_err(|_| format!("HTTP {status}: response is not JSON"))?;
        if !status.is_success() {
            let e = &json["error"];
            return Err(format!(
                "HTTP {}: {} {}",
                status.as_u16(),
                e["type"].as_str().unwrap_or("error"),
                e["message"].as_str().unwrap_or("")
            ));
        }
        Ok(json)
    }
}

impl LlmClient for AnthropicClient {
    fn messages(&self, body: Json) -> LlmFuture<'_> {
        Box::pin(async move {
            tokio::time::timeout(self.timeout, self.post(body))
                .await
                .map_err(|_| format!("LLM request timed out after {:?}", self.timeout))?
        })
    }
}

/// Tokens billed for one response: input + output + cache reads/writes.
pub fn usage_tokens(resp: &Json) -> u64 {
    let u = &resp["usage"];
    [
        "input_tokens",
        "output_tokens",
        "cache_creation_input_tokens",
        "cache_read_input_tokens",
    ]
    .iter()
    .filter_map(|k| u[*k].as_u64())
    .sum()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn base_urls() {
        assert_eq!(
            parse_base("https://api.anthropic.com").unwrap(),
            ("api.anthropic.com".into(), 443, "/v1/messages".into())
        );
        assert_eq!(
            parse_base("https://proxy.local:8443/llm/").unwrap(),
            ("proxy.local".into(), 8443, "/llm/v1/messages".into())
        );
        assert!(parse_base("http://api.anthropic.com").is_err());
        assert!(parse_base("https://user@host").is_err());
    }

    #[test]
    fn usage_sum() {
        let r = serde_json::json!({"usage": {"input_tokens": 10, "output_tokens": 5, "cache_read_input_tokens": 2}});
        assert_eq!(usage_tokens(&r), 17);
    }
}
