//! A tiny HTTP/1.1 server for the stores' simulators (feature `sim`): every
//! request, its body read whole, goes to a handler; `None` from the handler
//! never answers (a silent store).

use bytes::Bytes;
use http_body_util::{BodyExt, Full, Limited};
use hyper::body::Incoming;
use hyper_util::rt::TokioIo;
use std::net::SocketAddr;
use std::sync::Arc;
use tokio::net::TcpListener;
use tokio::task::JoinHandle;

/// Largest request body taken.
pub const MAX_BODY: usize = 80 * 1024 * 1024;

#[derive(Debug, Clone)]
pub struct SimRequest {
    pub method: String,
    /// As sent (percent-encoded).
    pub path: String,
    pub query: String,
    pub headers: Vec<(String, String)>,
    pub body: Bytes,
}

impl SimRequest {
    pub fn header(&self, name: &str) -> Option<&str> {
        self.headers
            .iter()
            .find(|(k, _)| k.eq_ignore_ascii_case(name))
            .map(|(_, v)| v.as_str())
    }

    /// A query parameter, percent-decoded (`+` is a space).
    pub fn param(&self, name: &str) -> Option<String> {
        self.query.split('&').find_map(|kv| {
            let (k, v) = kv.split_once('=').unwrap_or((kv, ""));
            (k == name).then(|| crate::util::pct_decode(&v.replace('+', " ")).unwrap_or_default())
        })
    }
}

#[derive(Debug, Clone, Default)]
pub struct SimResponse {
    pub status: u16,
    pub headers: Vec<(String, String)>,
    pub body: Bytes,
}

impl SimResponse {
    pub fn new(status: u16) -> Self {
        Self {
            status,
            ..Self::default()
        }
    }

    pub fn header(mut self, k: &str, v: impl Into<String>) -> Self {
        self.headers.push((k.to_owned(), v.into()));
        self
    }

    pub fn body(mut self, b: impl Into<Bytes>) -> Self {
        self.body = b.into();
        self
    }
}

pub type Handler = Arc<dyn Fn(SimRequest) -> Option<SimResponse> + Send + Sync>;

/// Listen on `addr` (`127.0.0.1:0` for any port) and answer with `h`.
pub async fn serve(addr: &str, h: Handler) -> std::io::Result<(SocketAddr, JoinHandle<()>)> {
    let l = TcpListener::bind(addr).await?;
    let local = l.local_addr()?;
    let task = tokio::spawn(async move {
        loop {
            let Ok((sock, _)) = l.accept().await else {
                continue;
            };
            let h = h.clone();
            tokio::spawn(async move {
                let svc = hyper::service::service_fn(move |req: hyper::Request<Incoming>| {
                    let h = h.clone();
                    async move {
                        let (parts, body) = req.into_parts();
                        let body = Limited::new(body, MAX_BODY)
                            .collect()
                            .await
                            .map(|b| b.to_bytes())
                            .unwrap_or_default();
                        let r = SimRequest {
                            method: parts.method.to_string(),
                            path: parts.uri.path().to_owned(),
                            query: parts.uri.query().unwrap_or("").to_owned(),
                            headers: parts
                                .headers
                                .iter()
                                .map(|(k, v)| {
                                    (k.as_str().to_owned(), v.to_str().unwrap_or("").to_owned())
                                })
                                .collect(),
                            body,
                        };
                        let Some(resp) = h(r) else {
                            std::future::pending::<()>().await;
                            unreachable!()
                        };
                        let mut b = hyper::Response::builder().status(resp.status);
                        for (k, v) in &resp.headers {
                            b = b.header(k, v);
                        }
                        Ok::<_, std::convert::Infallible>(
                            b.body(Full::new(resp.body))
                                .unwrap_or_else(|_| hyper::Response::new(Full::new(Bytes::new()))),
                        )
                    }
                });
                let _ = hyper::server::conn::http1::Builder::new()
                    .serve_connection(TokioIo::new(sock), svc)
                    .await;
            });
        }
    });
    Ok((local, task))
}
