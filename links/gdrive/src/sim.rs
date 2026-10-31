//! A Google Drive API v3 and OAuth token server for tests and demos
//! (feature `sim`): files in memory, `POST /token` (JWT bearer grant with
//! the signature checked against [`State::public_key`], or a refresh
//! token), `files.get` (`alt=media` too), `files.list` on `'<id>' in
//! parents` with pages, `files.create`, multipart and media uploads,
//! `files.update` (trash) and `files.delete`.
//!
//! The root folder has id `root`. [`State::mode`] injects failures.

use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine as _;
use bytes::Bytes;
use serde_json::{json, Value as Json};
use std::collections::BTreeMap;
use std::net::SocketAddr;
use std::sync::{Arc, Mutex};
use tokio::task::JoinHandle;
use wyrm_filestore::sim::{serve, SimRequest, SimResponse};
use wyrm_filestore::util::{now_us, rfc3339};

pub const ROOT: &str = "root";

#[derive(Debug, Clone, Default, PartialEq)]
pub enum Mode {
    #[default]
    Normal,
    Status(u16),
    Silent,
}

#[derive(Debug, Clone)]
pub struct File {
    pub name: String,
    pub mime: String,
    pub parent: String,
    pub data: Bytes,
    pub modified: u64,
    pub trashed: bool,
}

#[derive(Debug)]
pub struct State {
    pub files: BTreeMap<String, File>,
    /// The service account accepted: its email and its public key (DER,
    /// PKCS#1 `RSAPublicKey`).
    pub email: String,
    pub public_key: Vec<u8>,
    /// A refresh token grant accepted: (client id, client secret, token).
    pub refresh: Option<(String, String, String)>,
    pub tokens: Vec<String>,
    pub mode: Mode,
    /// Files per list page at most.
    pub page: usize,
    next_id: u64,
    pub seen: Vec<String>,
    /// Resumable upload sessions by id.
    pub sessions: BTreeMap<String, Session>,
}

/// A resumable upload: the file it makes (or replaces) and what came.
#[derive(Debug, Clone)]
pub struct Session {
    pub parent: String,
    pub name: String,
    pub mime: String,
    pub replace: Option<String>,
    pub size: u64,
    pub data: Vec<u8>,
}

impl Default for State {
    fn default() -> Self {
        let mut files = BTreeMap::new();
        files.insert(
            ROOT.to_owned(),
            File {
                name: "My Drive".into(),
                mime: crate::FOLDER_MIME.into(),
                parent: String::new(),
                data: Bytes::new(),
                modified: now_us(),
                trashed: false,
            },
        );
        Self {
            files,
            email: "sim@wyrm.iam.gserviceaccount.com".into(),
            public_key: Vec::new(),
            refresh: None,
            tokens: Vec::new(),
            mode: Mode::Normal,
            page: 1000,
            next_id: 1,
            seen: Vec::new(),
            sessions: BTreeMap::new(),
        }
    }
}

impl State {
    fn new_id(&mut self) -> String {
        self.next_id += 1;
        format!("id{:06}", self.next_id)
    }

    fn child(&self, parent: &str, name: &str) -> Option<String> {
        self.files
            .iter()
            .find(|(_, f)| f.parent == parent && f.name == name && !f.trashed)
            .map(|(id, _)| id.clone())
    }

    pub fn add(&mut self, parent: &str, name: &str, mime: &str, data: &[u8]) -> String {
        let id = self.new_id();
        self.files.insert(
            id.clone(),
            File {
                name: name.into(),
                mime: mime.into(),
                parent: parent.into(),
                data: Bytes::copy_from_slice(data),
                modified: now_us(),
                trashed: false,
            },
        );
        id
    }

    /// Put a file at `path` below the root, making its folders.
    pub fn put_path(&mut self, path: &str, data: &[u8]) -> String {
        let mut parent = ROOT.to_owned();
        let parts: Vec<&str> = path.split('/').collect();
        for p in &parts[..parts.len() - 1] {
            parent = match self.child(&parent, p) {
                Some(id) => id,
                None => self.add(&parent, p, crate::FOLDER_MIME, b""),
            };
        }
        let name = parts[parts.len() - 1];
        if let Some(id) = self.child(&parent, name) {
            self.files.remove(&id);
        }
        self.add(&parent, name, "text/plain", data)
    }

    /// The id of `path` below the root.
    pub fn find(&self, path: &str) -> Option<String> {
        let mut at = ROOT.to_owned();
        for p in path.split('/') {
            at = self.child(&at, p)?;
        }
        Some(at)
    }

    fn remove_tree(&mut self, id: &str) {
        let kids: Vec<String> = self
            .files
            .iter()
            .filter(|(_, f)| f.parent == id)
            .map(|(k, _)| k.clone())
            .collect();
        for k in kids {
            self.remove_tree(&k);
        }
        self.files.remove(id);
    }

    fn trash_tree(&mut self, id: &str) {
        let kids: Vec<String> = self
            .files
            .iter()
            .filter(|(_, f)| f.parent == id)
            .map(|(k, _)| k.clone())
            .collect();
        for k in kids {
            self.trash_tree(&k);
        }
        if let Some(f) = self.files.get_mut(id) {
            f.trashed = true;
        }
    }
}

pub type Shared = Arc<Mutex<State>>;

fn err(status: u16, msg: &str) -> SimResponse {
    jsonr(
        status,
        json!({"error": {"code": status, "message": msg, "errors": [{"reason": "sim"}]}}),
    )
}

fn jsonr(status: u16, j: Json) -> SimResponse {
    SimResponse::new(status)
        .header("content-type", "application/json")
        .body(j.to_string())
}

fn meta(id: &str, f: &File) -> Json {
    let mut j =
        json!({"id": id, "name": f.name, "mimeType": f.mime, "modifiedTime": rfc3339(f.modified)});
    if f.mime != crate::FOLDER_MIME {
        j["size"] = Json::String(f.data.len().to_string());
    }
    j
}

fn form(body: &[u8]) -> BTreeMap<String, String> {
    String::from_utf8_lossy(body)
        .split('&')
        .filter_map(|kv| kv.split_once('='))
        .map(|(k, v)| {
            (
                k.to_owned(),
                wyrm_filestore::util::pct_decode(v).unwrap_or_default(),
            )
        })
        .collect()
}

fn token(s: &mut State, r: &SimRequest) -> SimResponse {
    let f = form(&r.body);
    let ok = match f.get("grant_type").map(String::as_str) {
        Some("urn:ietf:params:oauth:grant-type:jwt-bearer") => {
            let jwt = f.get("assertion").cloned().unwrap_or_default();
            let parts: Vec<&str> = jwt.split('.').collect();
            if parts.len() != 3 {
                return jsonr(
                    400,
                    json!({"error": "invalid_grant", "error_description": "bad JWT"}),
                );
            }
            let sig = URL_SAFE_NO_PAD.decode(parts[2]).unwrap_or_default();
            let key = ring::signature::UnparsedPublicKey::new(
                &ring::signature::RSA_PKCS1_2048_8192_SHA256,
                &s.public_key,
            );
            let signed = format!("{}.{}", parts[0], parts[1]);
            let claims: Json = URL_SAFE_NO_PAD
                .decode(parts[1])
                .ok()
                .and_then(|b| serde_json::from_slice(&b).ok())
                .unwrap_or(Json::Null);
            key.verify(signed.as_bytes(), &sig).is_ok()
                && claims["iss"].as_str() == Some(s.email.as_str())
                && claims["scope"].as_str() == Some(crate::auth::SCOPE)
                && claims["aud"]
                    .as_str()
                    .is_some_and(|a| a.ends_with("/token"))
        }
        Some("refresh_token") => s.refresh.as_ref().is_some_and(|(id, secret, rt)| {
            f.get("client_id") == Some(id)
                && f.get("client_secret") == Some(secret)
                && f.get("refresh_token") == Some(rt)
        }),
        _ => false,
    };
    if !ok {
        return jsonr(
            400,
            json!({"error": "invalid_grant", "error_description": "refused"}),
        );
    }
    let t = format!("tok-{}", s.tokens.len() + 1);
    s.tokens.push(t.clone());
    jsonr(
        200,
        json!({"access_token": t, "expires_in": 3599, "token_type": "Bearer"}),
    )
}

/// Parent id of a `'<id>' in parents and trashed=false` query.
fn parent_of_query(q: &str) -> Option<String> {
    let rest = q.strip_prefix('\'')?;
    let (id, tail) = rest.split_once('\'')?;
    tail.starts_with(" in parents").then(|| id.to_owned())
}

fn multipart(r: &SimRequest) -> Option<(Json, Bytes, String)> {
    let ct = r.header("content-type")?;
    let boundary = ct.split("boundary=").nth(1)?.trim();
    let body = &r.body[..];
    let sep = format!("--{boundary}");
    let text = body;
    let mut parts = Vec::new();
    let mut at = 0;
    let find = |from: usize| {
        text[from..]
            .windows(sep.len())
            .position(|w| w == sep.as_bytes())
            .map(|p| p + from)
    };
    let mut start = find(0)? + sep.len();
    while let Some(next) = find(start) {
        parts.push(&text[start..next]);
        start = next + sep.len();
        at += 1;
        if at > 4 {
            break;
        }
    }
    let split = |p: &[u8]| -> Option<(String, Bytes)> {
        let p = p.strip_prefix(b"\r\n")?;
        let i = p.windows(4).position(|w| w == b"\r\n\r\n")?;
        let head = String::from_utf8_lossy(&p[..i]).to_string();
        let data = p[i + 4..].strip_suffix(b"\r\n")?;
        Some((head, Bytes::copy_from_slice(data)))
    };
    let (_, m) = split(parts.first()?)?;
    let (head, data) = split(parts.get(1)?)?;
    let ctype = head
        .lines()
        .find_map(|l| l.strip_prefix("Content-Type: "))
        .unwrap_or("application/octet-stream")
        .to_owned();
    Some((serde_json::from_slice(&m).ok()?, data, ctype))
}

fn handle(st: &Shared, r: SimRequest) -> Option<SimResponse> {
    let mut s = st.lock().unwrap_or_else(|e| e.into_inner());
    s.seen.push(format!("{} {}", r.method, r.path));
    match s.mode {
        Mode::Silent => return None,
        Mode::Status(c) => return Some(err(c, "injected")),
        Mode::Normal => {}
    }
    if r.path == "/token" && r.method == "POST" {
        return Some(token(&mut s, &r));
    }
    let authed = r
        .header("authorization")
        .and_then(|a| a.strip_prefix("Bearer "))
        .is_some_and(|t| s.tokens.iter().any(|x| x == t));
    if !authed {
        return Some(err(401, "Request had invalid authentication credentials."));
    }
    let path = r.path.clone();
    if let Some(resp) = resumable(&mut s, &r) {
        return Some(resp);
    }
    Some(match (r.method.as_str(), path.as_str()) {
        ("GET", "/drive/v3/files") => {
            let q = r.param("q").unwrap_or_default();
            let Some(parent) = parent_of_query(&q) else {
                return Some(err(400, "unsupported query"));
            };
            let size = r
                .param("pageSize")
                .and_then(|p| p.parse::<usize>().ok())
                .unwrap_or(100)
                .min(s.page);
            let from = r
                .param("pageToken")
                .and_then(|p| p.parse::<usize>().ok())
                .unwrap_or(0);
            let all: Vec<Json> = s
                .files
                .iter()
                .filter(|(_, f)| f.parent == parent && !f.trashed)
                .map(|(id, f)| meta(id, f))
                .collect();
            let page: Vec<Json> = all.iter().skip(from).take(size).cloned().collect();
            let mut j = json!({"files": page});
            if from + size < all.len() {
                j["nextPageToken"] = Json::String((from + size).to_string());
            }
            jsonr(200, j)
        }
        ("POST", "/drive/v3/files") => {
            let j: Json = serde_json::from_slice(&r.body).unwrap_or(Json::Null);
            let parent = j["parents"][0].as_str().unwrap_or(ROOT).to_owned();
            let name = j["name"].as_str().unwrap_or("").to_owned();
            let mime = j["mimeType"]
                .as_str()
                .unwrap_or("application/octet-stream")
                .to_owned();
            if !s.files.contains_key(&parent) {
                return Some(err(404, "parent not found"));
            }
            let id = s.add(&parent, &name, &mime, b"");
            let f = s.files[&id].clone();
            jsonr(200, meta(&id, &f))
        }
        ("POST", "/upload/drive/v3/files") => {
            let Some((m, data, ctype)) = multipart(&r) else {
                return Some(err(400, "bad multipart body"));
            };
            let parent = m["parents"][0].as_str().unwrap_or(ROOT).to_owned();
            let name = m["name"].as_str().unwrap_or("").to_owned();
            if !s.files.contains_key(&parent) {
                return Some(err(404, "parent not found"));
            }
            let id = s.add(&parent, &name, &ctype, &data);
            let f = s.files[&id].clone();
            jsonr(200, meta(&id, &f))
        }
        (m, p) => {
            let (upload, id) = if let Some(id) = p.strip_prefix("/upload/drive/v3/files/") {
                (true, id.to_owned())
            } else if let Some(id) = p.strip_prefix("/drive/v3/files/") {
                (false, id.to_owned())
            } else {
                return Some(err(404, "no such API"));
            };
            let Some(f) = s.files.get(&id).cloned().filter(|f| !f.trashed) else {
                return Some(err(404, &format!("File not found: {id}.")));
            };
            match (m, upload) {
                ("GET", false)
                    if r.param("alt").as_deref() == Some("media")
                        && r.header("range").is_some() =>
                {
                    let h = r.header("range").unwrap_or("");
                    match h
                        .strip_prefix("bytes=")
                        .and_then(|x| x.split_once('-'))
                        .and_then(|(a, b)| {
                            Some((a.parse::<usize>().ok()?, b.parse::<usize>().ok()?))
                        }) {
                        Some((a, b)) if a < f.data.len() => {
                            SimResponse::new(206).body(f.data.slice(a..=b.min(f.data.len() - 1)))
                        }
                        _ => SimResponse::new(416),
                    }
                }
                ("GET", false) if r.param("alt").as_deref() == Some("media") => {
                    SimResponse::new(200)
                        .header("content-type", f.mime.clone())
                        .body(f.data.clone())
                }
                ("GET", false) => jsonr(200, meta(&id, &f)),
                ("PATCH", true) => {
                    let ctype = r
                        .header("content-type")
                        .unwrap_or("application/octet-stream")
                        .to_owned();
                    let e = s.files.get_mut(&id)?;
                    e.data = r.body.clone();
                    e.mime = ctype;
                    e.modified = now_us();
                    let f = e.clone();
                    jsonr(200, meta(&id, &f))
                }
                ("PATCH", false) => {
                    let j: Json = serde_json::from_slice(&r.body).unwrap_or(Json::Null);
                    if j["trashed"].as_bool() == Some(true) {
                        s.trash_tree(&id);
                    }
                    jsonr(200, json!({"id": id}))
                }
                ("DELETE", false) => {
                    s.remove_tree(&id);
                    SimResponse::new(204)
                }
                _ => err(400, "unsupported"),
            }
        }
    })
}

/// Resumable uploads: a session (`uploadType=resumable` on POST or PATCH)
/// and its chunks (`PUT ?upload_id=` with `Content-Range`); `None` for
/// other requests.
fn resumable(s: &mut State, r: &SimRequest) -> Option<SimResponse> {
    let host = r.header("host").unwrap_or("localhost").to_owned();
    if r.param("uploadType").as_deref() == Some("resumable") && r.param("upload_id").is_none() {
        let j: Json = serde_json::from_slice(&r.body).unwrap_or(Json::Null);
        let size = r.header("x-upload-content-length")?.parse().ok()?;
        let mime = r
            .header("x-upload-content-type")
            .unwrap_or("application/octet-stream")
            .to_owned();
        let session = match (
            r.method.as_str(),
            r.path.strip_prefix("/upload/drive/v3/files/"),
        ) {
            ("POST", None) => Session {
                parent: j["parents"][0].as_str().unwrap_or(ROOT).to_owned(),
                name: j["name"].as_str().unwrap_or("").to_owned(),
                mime,
                replace: None,
                size,
                data: Vec::new(),
            },
            ("PATCH", Some(id)) => {
                let f = s.files.get(id)?.clone();
                Session {
                    parent: f.parent,
                    name: f.name,
                    mime,
                    replace: Some(id.to_owned()),
                    size,
                    data: Vec::new(),
                }
            }
            _ => return Some(err(400, "bad resumable start")),
        };
        let sid = format!("s{}", s.sessions.len() + 1);
        s.sessions.insert(sid.clone(), session);
        return Some(SimResponse::new(200).header(
            "location",
            format!("http://{host}/upload/drive/v3/files?uploadType=resumable&upload_id={sid}"),
        ));
    }
    let sid = r.param("upload_id")?;
    if r.method != "PUT" {
        return None;
    }
    let range = r
        .header("content-range")?
        .strip_prefix("bytes ")?
        .to_owned();
    let (span, total) = range.split_once('/')?;
    let (a, b) = span.split_once('-')?;
    let (a, b, total): (usize, usize, u64) =
        (a.parse().ok()?, b.parse().ok()?, total.parse().ok()?);
    let Some(sess) = s.sessions.get_mut(&sid) else {
        return Some(err(404, "no such session"));
    };
    if a != sess.data.len() || b + 1 - a != r.body.len() || total != sess.size {
        return Some(err(400, "chunk out of place"));
    }
    // Drive's rule: every chunk but the last a multiple of 256 KiB
    if (b + 1) as u64 != total && !r.body.len().is_multiple_of(256 * 1024) {
        return Some(err(400, "chunk not a multiple of 256 KiB"));
    }
    sess.data.extend_from_slice(&r.body);
    if (sess.data.len() as u64) < sess.size {
        let end = sess.data.len() - 1;
        return Some(SimResponse::new(308).header("range", format!("bytes=0-{end}")));
    }
    let sess = s.sessions.remove(&sid)?;
    let id = match sess.replace {
        Some(id) => {
            let f = s.files.get_mut(&id)?;
            f.data = Bytes::from(sess.data);
            f.mime = sess.mime;
            f.modified = now_us();
            id
        }
        None => s.add(&sess.parent, &sess.name, &sess.mime, &sess.data),
    };
    let f = s.files[&id].clone();
    Some(jsonr(200, meta(&id, &f)))
}

/// Serve on `addr`; the drive's state is shared with the caller.
pub async fn spawn(addr: &str) -> std::io::Result<(SocketAddr, Shared, JoinHandle<()>)> {
    let st: Shared = Arc::new(Mutex::new(State::default()));
    let h = st.clone();
    let (a, task) = serve(addr, Arc::new(move |r| handle(&h, r))).await?;
    Ok((a, st, task))
}
