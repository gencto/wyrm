//! A WebDAV server for tests and demos (feature `sim`): a tree in memory
//! below [`BASE`], `PROPFIND` (`Depth` 0 and 1), `MKCOL`, `PUT` (with
//! `If-None-Match: *`), `GET`, `DELETE`; basic auth when
//! [`State::basic`] is set. Hrefs are percent-encoded absolute paths, and
//! every other file's href is a full URL, as servers differ.

use bytes::Bytes;
use std::collections::BTreeMap;
use std::net::SocketAddr;
use std::sync::{Arc, Mutex};
use tokio::task::JoinHandle;
use wyrm_filestore::backend::{parent_of, under};
use wyrm_filestore::sim::{serve, SimRequest, SimResponse};
use wyrm_filestore::util::{http_date, now_us, pct_decode, pct_encode};
use wyrm_filestore::xml::escape;

/// The served collection: `http://<addr>/dav/files/alice`.
pub const BASE: &str = "/dav/files/alice";

#[derive(Debug, Clone, Default, PartialEq)]
pub enum Mode {
    #[default]
    Normal,
    Status(u16),
    Silent,
}

#[derive(Debug, Clone)]
pub struct Node {
    pub dir: bool,
    pub data: Bytes,
    pub modified: u64,
    pub content_type: String,
}

#[derive(Debug, Default)]
pub struct State {
    /// By path below [`BASE`] (`""` = the base itself, always a folder).
    pub nodes: BTreeMap<String, Node>,
    /// `Authorization: Basic` required: `user:password`.
    pub basic: Option<(String, String)>,
    pub mode: Mode,
    pub seen: Vec<String>,
    /// An href added to every `Depth: 1` answer (a server that answers
    /// with a path the client cannot map).
    pub odd_href: Option<String>,
    /// Every `Depth: 1` answer is an empty multistatus (no response, not
    /// even the collection itself).
    pub empty_depth1: bool,
}

impl State {
    pub fn new() -> Self {
        let mut s = Self::default();
        s.nodes.insert(String::new(), Self::folder());
        s
    }

    fn folder() -> Node {
        Node {
            dir: true,
            data: Bytes::new(),
            modified: now_us(),
            content_type: String::new(),
        }
    }

    /// Put a file at `path`, making its folders.
    pub fn put(&mut self, path: &str, data: &[u8]) {
        let mut at = parent_of(path);
        while let Some(p) = at {
            if p.is_empty() {
                break;
            }
            self.nodes.entry(p.to_owned()).or_insert_with(Self::folder);
            at = parent_of(p);
        }
        self.nodes.insert(
            path.to_owned(),
            Node {
                dir: false,
                data: Bytes::copy_from_slice(data),
                modified: now_us(),
                content_type: wyrm_filestore::util::guess_content_type(path).into(),
            },
        );
    }

    pub fn remove(&mut self, path: &str) {
        self.nodes
            .retain(|p, _| !(under(p, path) && !path.is_empty()));
    }
}

pub type Shared = Arc<Mutex<State>>;

fn href(path: &str, dir: bool, full: bool, host: &str) -> String {
    let mut h = pct_encode(&format!("{BASE}/{path}"), true).replace("//", "/");
    if path.is_empty() {
        h = pct_encode(BASE, true);
    }
    if dir {
        h.push('/');
    }
    if full {
        format!("http://{host}{h}")
    } else {
        h
    }
}

fn response(path: &str, n: &Node, full: bool, host: &str) -> String {
    let props = if n.dir {
        format!(
            "<d:resourcetype><d:collection/></d:resourcetype><d:getlastmodified>{}</d:getlastmodified>",
            http_date(n.modified)
        )
    } else {
        format!(
            "<d:resourcetype/><d:getcontentlength>{}</d:getcontentlength><d:getlastmodified>{}</d:getlastmodified><d:getetag>&quot;{}&quot;</d:getetag><d:getcontenttype>{}</d:getcontenttype>",
            n.data.len(),
            http_date(n.modified),
            n.modified,
            escape(&n.content_type)
        )
    };
    let missing = if n.dir {
        "<d:propstat><d:prop><d:getcontentlength/><d:getetag/></d:prop><d:status>HTTP/1.1 404 Not Found</d:status></d:propstat>"
    } else {
        ""
    };
    format!(
        "<d:response><d:href>{}</d:href><d:propstat><d:prop>{props}</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>{missing}</d:response>",
        escape(&href(path, n.dir, full, host))
    )
}

fn handle(st: &Shared, r: SimRequest) -> Option<SimResponse> {
    let mut s = st.lock().unwrap_or_else(|e| e.into_inner());
    s.seen.push(format!("{} {}", r.method, r.path));
    match s.mode {
        Mode::Silent => return None,
        Mode::Status(c) => return Some(SimResponse::new(c)),
        Mode::Normal => {}
    }
    if let Some((u, p)) = &s.basic {
        use base64::Engine as _;
        let want = format!(
            "Basic {}",
            base64::engine::general_purpose::STANDARD.encode(format!("{u}:{p}"))
        );
        if r.header("authorization") != Some(want.as_str()) {
            return Some(SimResponse::new(401).header("www-authenticate", "Basic realm=\"sim\""));
        }
    }
    let decoded = pct_decode(&r.path)?;
    let Some(rest) = decoded.strip_prefix(BASE) else {
        return Some(SimResponse::new(404));
    };
    let path = rest.trim_matches('/').to_owned();
    let host = r.header("host").unwrap_or("localhost").to_owned();
    Some(match r.method.as_str() {
        "PROPFIND" => {
            let Some(n) = s.nodes.get(&path).cloned() else {
                return Some(SimResponse::new(404));
            };
            let mut body = String::from(
                "<?xml version=\"1.0\" encoding=\"utf-8\"?><d:multistatus xmlns:d=\"DAV:\">",
            );
            let depth1 = r.header("depth") == Some("1");
            if !(depth1 && s.empty_depth1) {
                body.push_str(&response(&path, &n, false, &host));
            }
            if n.dir && depth1 && !s.empty_depth1 {
                for (i, (p, c)) in s
                    .nodes
                    .iter()
                    .filter(|(p, _)| !p.is_empty() && parent_of(p) == Some(path.as_str()))
                    .enumerate()
                {
                    body.push_str(&response(p, c, i % 2 == 1, &host));
                }
                if let Some(h) = &s.odd_href {
                    body.push_str(&format!(
                        "<d:response><d:href>{}</d:href><d:propstat><d:prop><d:resourcetype/></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>",
                        escape(h)
                    ));
                }
            }
            body.push_str("</d:multistatus>");
            SimResponse::new(207)
                .header("content-type", "application/xml; charset=utf-8")
                .body(body)
        }
        "MKCOL" => {
            if s.nodes.contains_key(&path) {
                return Some(SimResponse::new(405));
            }
            if !parent_of(&path).is_some_and(|p| s.nodes.get(p).is_some_and(|n| n.dir)) {
                return Some(SimResponse::new(409));
            }
            s.nodes.insert(path, State::folder());
            SimResponse::new(201)
        }
        "PUT" => {
            if r.header("if-none-match") == Some("*") && s.nodes.contains_key(&path) {
                return Some(SimResponse::new(412));
            }
            if !parent_of(&path).is_some_and(|p| s.nodes.get(p).is_some_and(|n| n.dir)) {
                return Some(SimResponse::new(409));
            }
            let ctype = r
                .header("content-type")
                .unwrap_or("application/octet-stream")
                .to_owned();
            let m = now_us();
            s.nodes.insert(
                path,
                Node {
                    dir: false,
                    data: r.body.clone(),
                    modified: m,
                    content_type: ctype,
                },
            );
            SimResponse::new(201).header("etag", format!("\"{m}\""))
        }
        "GET" => match s.nodes.get(&path) {
            Some(n) if !n.dir => match r.header("range").and_then(|h| range(h, n.data.len())) {
                Some((a, b)) => SimResponse::new(206)
                    .header("content-type", n.content_type.clone())
                    .body(n.data.slice(a..=b)),
                None => SimResponse::new(200)
                    .header("content-type", n.content_type.clone())
                    .body(n.data.clone()),
            },
            _ => SimResponse::new(404),
        },
        "DELETE" => {
            if path.is_empty() || !s.nodes.contains_key(&path) {
                return Some(SimResponse::new(404));
            }
            s.remove(&path);
            SimResponse::new(204)
        }
        _ => SimResponse::new(405),
    })
}

/// `bytes=a-b` within a body of `len` bytes.
fn range(h: &str, len: usize) -> Option<(usize, usize)> {
    let (a, b) = h.strip_prefix("bytes=")?.split_once('-')?;
    let a: usize = a.parse().ok()?;
    let b: usize = b.parse::<usize>().ok()?.min(len.checked_sub(1)?);
    (a <= b).then_some((a, b))
}

/// Serve on `addr`; the tree is shared with the caller.
pub async fn spawn(addr: &str) -> std::io::Result<(SocketAddr, Shared, JoinHandle<()>)> {
    let st: Shared = Arc::new(Mutex::new(State::new()));
    let h = st.clone();
    let (a, task) = serve(addr, Arc::new(move |r| handle(&h, r))).await?;
    Ok((a, st, task))
}
