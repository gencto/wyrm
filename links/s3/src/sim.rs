//! An S3 server for tests and demos (feature `sim`): one bucket in memory,
//! path-style and virtual-hosted addressing, Signature V4 checked against
//! one key pair, ListObjectsV2 (prefix, pages, continuation tokens),
//! PutObject (`If-None-Match: *`), GetObject, DeleteObject.
//!
//! [`State::mode`] injects failures (a fixed status, silence);
//! [`State::page`] makes pages short to test continuation.

use crate::sigv4;
use bytes::Bytes;
use std::collections::BTreeMap;
use std::net::SocketAddr;
use std::sync::{Arc, Mutex};
use tokio::task::JoinHandle;
use wyrm_filestore::sim::{serve, SimRequest, SimResponse};
use wyrm_filestore::util::{now_us, pct_decode, rfc3339};
use wyrm_filestore::xml::escape;

#[derive(Debug, Clone, Default, PartialEq)]
pub enum Mode {
    #[default]
    Normal,
    /// Every request answers this status.
    Status(u16),
    /// Requests are never answered.
    Silent,
}

#[derive(Debug, Clone)]
pub struct Obj {
    pub data: Bytes,
    pub content_type: String,
    pub modified: u64,
    pub etag: String,
}

#[derive(Debug)]
pub struct State {
    pub bucket: String,
    pub region: String,
    /// Empty: requests need no signature.
    pub access: String,
    pub secret: String,
    pub objects: BTreeMap<String, Obj>,
    pub mode: Mode,
    /// Keys per ListObjectsV2 page at most.
    pub page: usize,
    /// `METHOD path?query` of each request.
    pub seen: Vec<String>,
}

impl Default for State {
    fn default() -> Self {
        Self {
            bucket: "plant".into(),
            region: "us-east-1".into(),
            access: "AKIASIM".into(),
            secret: "sim-secret-key".into(),
            objects: BTreeMap::new(),
            mode: Mode::Normal,
            page: 1000,
            seen: Vec::new(),
        }
    }
}

impl State {
    pub fn put(&mut self, key: &str, data: &[u8]) {
        let etag = sigv4::sha256_hex(data)[..32].to_owned();
        self.objects.insert(
            key.to_owned(),
            Obj {
                data: Bytes::copy_from_slice(data),
                content_type: "application/octet-stream".into(),
                modified: now_us(),
                etag,
            },
        );
    }
}

pub type Shared = Arc<Mutex<State>>;

fn error(status: u16, code: &str, msg: &str) -> SimResponse {
    SimResponse::new(status)
        .header("content-type", "application/xml")
        .body(format!(
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<Error><Code>{code}</Code><Message>{}</Message></Error>",
            escape(msg)
        ))
}

fn query_pairs(q: &str) -> Vec<(String, String)> {
    q.split('&')
        .filter(|kv| !kv.is_empty())
        .map(|kv| {
            let (k, v) = kv.split_once('=').unwrap_or((kv, ""));
            (
                pct_decode(k).unwrap_or_default(),
                pct_decode(v).unwrap_or_default(),
            )
        })
        .collect()
}

/// `None` when the signature is good (or none is needed).
fn check_sig(s: &State, r: &SimRequest) -> Option<SimResponse> {
    if s.access.is_empty() {
        return None;
    }
    let Some(auth) = r.header("authorization") else {
        return Some(error(403, "AccessDenied", "Anonymous access denied"));
    };
    let field = |name: &str| {
        auth.split([' ', ','])
            .find_map(|p| p.trim().strip_prefix(name))
            .unwrap_or("")
            .to_owned()
    };
    let cred = field("Credential=");
    let signed = field("SignedHeaders=");
    let mut parts = cred.split('/');
    if parts.next() != Some(s.access.as_str()) {
        return Some(error(403, "InvalidAccessKeyId", "unknown access key"));
    }
    let _date = parts.next();
    if parts.next() != Some(s.region.as_str()) {
        return Some(error(400, "AuthorizationHeaderMalformed", "wrong region"));
    }
    let hash = r.header("x-amz-content-sha256").unwrap_or("").to_owned();
    if hash != sigv4::sha256_hex(&r.body) {
        return Some(error(400, "XAmzContentSHA256Mismatch", "payload hash"));
    }
    let headers: Vec<(String, String)> = signed
        .split(';')
        .map(|h| (h.to_owned(), r.header(h).unwrap_or("").to_owned()))
        .collect();
    let amz_date = r.header("x-amz-date").unwrap_or("").to_owned();
    let expect = sigv4::authorization(&sigv4::Signing {
        method: &r.method,
        path: &r.path,
        query: &query_pairs(&r.query),
        headers: &headers,
        payload_sha256: &hash,
        access_key: &s.access,
        secret_key: &s.secret,
        region: &s.region,
        service: "s3",
        amz_date: &amz_date,
    });
    (expect != auth).then(|| error(403, "SignatureDoesNotMatch", "signature"))
}

fn list(s: &State, r: &SimRequest) -> SimResponse {
    let q: BTreeMap<String, String> = query_pairs(&r.query).into_iter().collect();
    let prefix = q.get("prefix").cloned().unwrap_or_default();
    let max = q
        .get("max-keys")
        .and_then(|m| m.parse::<usize>().ok())
        .unwrap_or(1000)
        .min(s.page);
    let after = q.get("continuation-token").cloned();
    let keys: Vec<(&String, &Obj)> = s
        .objects
        .iter()
        .filter(|(k, _)| k.starts_with(&prefix))
        .filter(|(k, _)| after.as_ref().is_none_or(|a| k.as_str() > a.as_str()))
        .collect();
    let page = &keys[..keys.len().min(max)];
    let truncated = keys.len() > page.len();
    let mut body = format!(
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<ListBucketResult xmlns=\"http://s3.amazonaws.com/doc/2006-03-01/\"><Name>{}</Name><Prefix>{}</Prefix><KeyCount>{}</KeyCount><IsTruncated>{truncated}</IsTruncated>",
        escape(&s.bucket),
        escape(&prefix),
        page.len()
    );
    if truncated {
        if let Some((k, _)) = page.last() {
            body.push_str(&format!(
                "<NextContinuationToken>{}</NextContinuationToken>",
                escape(k)
            ));
        }
    }
    for (k, o) in page {
        body.push_str(&format!(
            "<Contents><Key>{}</Key><LastModified>{}</LastModified><ETag>&quot;{}&quot;</ETag><Size>{}</Size><StorageClass>STANDARD</StorageClass></Contents>",
            escape(k),
            rfc3339(o.modified).replace('Z', ".000Z"),
            o.etag,
            o.data.len()
        ));
    }
    body.push_str("</ListBucketResult>");
    SimResponse::new(200)
        .header("content-type", "application/xml")
        .body(body)
}

fn handle(st: &Shared, r: SimRequest) -> Option<SimResponse> {
    let mut s = st.lock().unwrap_or_else(|e| e.into_inner());
    s.seen.push(format!("{} {}?{}", r.method, r.path, r.query));
    match s.mode {
        Mode::Silent => return None,
        Mode::Status(code) => return Some(error(code, "Injected", "injected failure")),
        Mode::Normal => {}
    }
    if let Some(e) = check_sig(&s, &r) {
        return Some(e);
    }
    let host = r.header("host").unwrap_or("").to_owned();
    let path = pct_decode(&r.path).unwrap_or_default();
    let path = path.trim_start_matches('/');
    let virtual_bucket = host
        .split(':')
        .next()
        .and_then(|h| h.strip_suffix(".localhost"))
        .map(str::to_owned);
    let (bucket, key) = match virtual_bucket {
        Some(b) => (b, path.to_owned()),
        None => match path.split_once('/') {
            Some((b, k)) => (b.to_owned(), k.to_owned()),
            None => (path.to_owned(), String::new()),
        },
    };
    if bucket != s.bucket {
        return Some(error(
            404,
            "NoSuchBucket",
            "The specified bucket does not exist",
        ));
    }
    Some(match (r.method.as_str(), key.is_empty()) {
        ("GET", true) if r.param("list-type").as_deref() == Some("2") => list(&s, &r),
        ("GET", false) => match s.objects.get(&key) {
            Some(o) => SimResponse::new(200)
                .header("content-type", o.content_type.clone())
                .header("etag", format!("\"{}\"", o.etag))
                .body(o.data.clone()),
            None => error(404, "NoSuchKey", "The specified key does not exist."),
        },
        ("PUT", false) => {
            if r.header("if-none-match") == Some("*") && s.objects.contains_key(&key) {
                return Some(error(412, "PreconditionFailed", "the object exists"));
            }
            let etag = sigv4::sha256_hex(&r.body)[..32].to_owned();
            let ctype = r
                .header("content-type")
                .unwrap_or("application/octet-stream")
                .to_owned();
            s.objects.insert(
                key,
                Obj {
                    data: r.body.clone(),
                    content_type: ctype,
                    modified: now_us(),
                    etag: etag.clone(),
                },
            );
            SimResponse::new(200).header("etag", format!("\"{etag}\""))
        }
        ("DELETE", false) => {
            s.objects.remove(&key);
            SimResponse::new(204)
        }
        _ => error(400, "InvalidRequest", "not supported by the simulator"),
    })
}

/// Serve on `addr`; the bucket's state is shared with the caller.
pub async fn spawn(addr: &str) -> std::io::Result<(SocketAddr, Shared, JoinHandle<()>)> {
    let st: Shared = Arc::new(Mutex::new(State::default()));
    let h = st.clone();
    let (a, task) = serve(addr, Arc::new(move |r| handle(&h, r))).await?;
    Ok((a, st, task))
}
