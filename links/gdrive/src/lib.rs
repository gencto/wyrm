//! Google Drive link: one folder (My Drive, a folder shared with a service
//! account, or a shared drive) per connection, through the Drive API v3.
//!
//! Credentials, as in DSA, come with the connection and are kept sealed:
//! a service account's JSON key (`auth: service_account`, optionally
//! acting as a Workspace user with `subject`), or an OAuth client and a
//! user's refresh token (`auth: refresh_token`).
//!
//! The tree is read folder by folder (`files.list` on `'<id>' in parents`,
//! pages of 1000), breadth first, within `max_depth` and `max_entries`.
//! Drive allows two files of one name in a folder and `/` in names: the
//! tree path makes them unique (`report.pdf (1a2b3c4d)`, `/` as `_`), the
//! node shows the real name. Google Docs, Sheets and Slides have no bytes
//! to download (export is not supported); they show with size 0 and their
//! type.
//!
//! An upload is one multipart request (a new file) or a media update of
//! the file of that name (overwrite). Delete moves to the trash unless
//! `trash` is off.

#![forbid(unsafe_code)]

pub mod auth;
#[cfg(feature = "sim")]
pub mod sim;

use auth::{Grant, Tokens};
use bytes::Bytes;
use hyper::Method;
use serde_json::{json, Value as Json};
use std::collections::{BTreeSet, VecDeque};
use std::time::Duration;
use wyrm_filestore::backend::{join, not_empty, status_error};
use wyrm_filestore::http::{tls_config, Endpoint, Http, Request, Response};
use wyrm_filestore::util::{parse_rfc3339, pct_encode};
use wyrm_filestore::{Backend, Entry, Error, FileStore, Limits, Scan};
use wyrm_link_sdk::{LinkError, ParamEnum, Params};

/// The `gdrive` link.
pub type GDrive = FileStore<GDriveStore>;

pub const FOLDER_MIME: &str = "application/vnd.google-apps.folder";
/// Fields of a file in every reply.
const FIELDS: &str = "id,name,mimeType,size,modifiedTime,md5Checksum";
const MAX_LISTING: usize = 16 * 1024 * 1024;

#[derive(Debug, Clone, Copy, PartialEq, Eq, ParamEnum)]
pub enum Auth {
    /// A service account's JSON key.
    ServiceAccount,
    /// An OAuth client (id, secret) and a user's refresh token.
    RefreshToken,
}

/// A connection's params. No `Debug`: it holds secrets.
#[derive(Clone, PartialEq, Params)]
pub struct DriveParams {
    #[param(enum, default = "service_account", display = "Authentication", dest)]
    pub auth: Auth,
    #[param(
        default = "",
        secret,
        display = "Service Account Key (JSON)",
        desc = "auth service_account: the whole JSON key file"
    )]
    pub service_account_json: String,
    #[param(
        default = "",
        display = "Act As User",
        placeholder = "operator@example.com",
        desc = "auth service_account: a Workspace user (domain-wide delegation); empty = the account itself",
        dest
    )]
    pub subject: String,
    #[param(default = "", display = "Client ID", desc = "auth refresh_token", dest)]
    pub client_id: String,
    #[param(
        default = "",
        secret,
        display = "Client Secret",
        desc = "auth refresh_token"
    )]
    pub client_secret: String,
    #[param(
        default = "",
        secret,
        display = "Refresh Token",
        desc = "auth refresh_token"
    )]
    pub refresh_token: String,
    #[param(
        default = "root",
        display = "Folder ID",
        desc = "the root of the connection: 'root' (My Drive) or the id from the folder's URL",
        dest
    )]
    pub folder_id: String,
    #[param(
        default = "",
        display = "Shared Drive ID",
        desc = "a shared drive (its id); the folder must be in it ('root' = the drive's top)",
        dest
    )]
    pub shared_drive_id: String,
    #[param(
        default = true,
        display = "Delete to Trash",
        desc = "Delete moves to the trash; off = delete for good"
    )]
    pub trash: bool,
    #[param(default = 15000, min = 1000, max = 120000, display = "Timeout (ms)")]
    pub timeout_ms: u32,
    #[param(
        default = 8192,
        min = 256,
        max = 65536,
        display = "Upload Chunk (KiB)",
        desc = "a file received in parts goes to Drive in chunks of this size (a multiple of 256)"
    )]
    pub upload_chunk_kib: u32,
    #[param(
        default = "https://www.googleapis.com",
        display = "API URL",
        desc = "the Drive API (a test server, a proxy)",
        dest
    )]
    pub api_url: String,
    #[param(
        default = "https://oauth2.googleapis.com/token",
        display = "Token URL",
        dest
    )]
    pub token_url: String,
    #[param(
        default = "",
        editor = "textarea",
        display = "CA Certificates (PEM)",
        desc = "trust these CAs only (a TLS-inspecting proxy); empty = the CA certificates of the host",
        dest
    )]
    pub ca_pem: String,
}

pub struct GDriveStore {
    api: Http,
    tokens: Tokens,
    root_id: String,
    drive: Option<String>,
    trash: bool,
    timeout: Duration,
    /// Chunk of a resumable upload (bytes, a multiple of 256 KiB).
    chunk: u64,
}

fn bad(name: &str, what: impl std::fmt::Display) -> LinkError {
    LinkError::invalid_parameter(format!("{name}: {what}"))
}

/// Drive ids: letters, digits, `-` and `_` (they go into queries).
pub fn valid_id(id: &str) -> bool {
    !id.is_empty()
        && id.len() <= 200
        && id
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'-' | b'_'))
}

fn endpoint(
    name: &str,
    url: &str,
    tls: &Option<std::sync::Arc<wyrm_filestore::http::TlsConfig>>,
) -> Result<(Http, Endpoint), LinkError> {
    let ep = Endpoint::parse(url).map_err(|e| bad(name, e))?;
    if !ep.tls && !ep.is_loopback() {
        return Err(bad(name, "https:// (http:// only to loopback, for tests)"));
    }
    Ok((
        Http::new(
            ep.clone(),
            tls.clone(),
            concat!("wyrm-gdrive/", env!("CARGO_PKG_VERSION")),
        ),
        ep,
    ))
}

/// The path segment of a Drive name (no `/`).
fn segment(name: &str) -> String {
    name.replace('/', "_")
}

/// An entry of a Drive file below `parent`.
fn entry(parent: &str, seg: &str, f: &Json) -> Entry {
    let mime = f["mimeType"].as_str().unwrap_or("");
    let dir = mime == FOLDER_MIME;
    Entry {
        path: join(parent, seg),
        name: f["name"].as_str().unwrap_or("").to_owned(),
        dir,
        size: (!dir).then(|| f["size"].as_str().and_then(|s| s.parse().ok()).unwrap_or(0)),
        modified: f["modifiedTime"].as_str().and_then(parse_rfc3339),
        etag: f["md5Checksum"].as_str().map(str::to_owned),
        content_type: (!dir && !mime.is_empty()).then(|| mime.to_owned()),
        id: f["id"].as_str().map(str::to_owned),
    }
}

impl GDriveStore {
    fn drive_query(&self) -> String {
        match &self.drive {
            Some(d) => format!(
                "&supportsAllDrives=true&includeItemsFromAllDrives=true&corpora=drive&driveId={d}"
            ),
            None => "&supportsAllDrives=true&includeItemsFromAllDrives=true".to_owned(),
        }
    }

    /// An API request with the bearer token; one retry with a new token
    /// when the API refuses the cached one.
    async fn call(
        &self,
        method: Method,
        target: String,
        ctype: Option<&str>,
        body: Bytes,
        max: usize,
    ) -> Result<Response, Error> {
        let mut req = Request::new(method, target).body(body);
        if let Some(c) = ctype {
            req = req.header("content-type", c);
        }
        self.call_req(req, max).await
    }

    /// `base` with the bearer token, bounded by the timeout and the time
    /// its body takes at 512 KiB/s.
    async fn call_req(&self, base: Request, max: usize) -> Result<Response, Error> {
        let t = self.timeout + Duration::from_secs(base.body_len() / (512 * 1024));
        for attempt in 0..2 {
            let token = self.tokens.token().await?;
            let req = base
                .clone()
                .secret_header("authorization", &format!("Bearer {}", token.as_str()))
                .header("accept", "application/json");
            let r = self.api.send(&req, t, max).await?;
            if r.status == 401 && attempt == 0 {
                self.tokens.drop_token().await;
                continue;
            }
            return Ok(r);
        }
        Err(Error::Auth("the API refused a new token".into()))
    }

    fn fail(r: &Response, what: &str) -> Error {
        let j: Json = serde_json::from_slice(&r.body).unwrap_or(Json::Null);
        let msg = j["error"]["message"].as_str().unwrap_or("");
        let reason = j["error"]["errors"][0]["reason"].as_str().unwrap_or("");
        match (r.status, reason) {
            (401, _) => Error::Auth(format!("{what}: HTTP 401 {msg}")),
            (403 | 429, "rateLimitExceeded" | "userRateLimitExceeded") | (429, _) => {
                Error::Refused(format!("{what}: rate limited ({msg})"))
            }
            (s, _) => status_error(s, what, msg),
        }
    }

    fn json(r: &Response, what: &str) -> Result<Json, Error> {
        serde_json::from_slice(&r.body).map_err(|_| Error::Refused(format!("{what}: not JSON")))
    }

    /// One page of a folder's children.
    async fn children(
        &self,
        id: &str,
        page: Option<&str>,
    ) -> Result<(Vec<Json>, Option<String>), Error> {
        if !valid_id(id) {
            return Err(Error::Refused(format!("bad folder id {id:?}")));
        }
        let q = pct_encode(&format!("'{id}' in parents and trashed=false"), false);
        let mut target = format!(
            "{}/drive/v3/files?q={q}&pageSize=1000&orderBy=name%2CcreatedTime&fields={}{}",
            self.api.endpoint.prefix,
            pct_encode(&format!("nextPageToken,files({FIELDS})"), false),
            self.drive_query()
        );
        if let Some(p) = page {
            target.push_str("&pageToken=");
            target.push_str(&pct_encode(p, false));
        }
        let r = self
            .call(Method::GET, target, None, Bytes::new(), MAX_LISTING)
            .await?;
        if !r.ok() {
            return Err(Self::fail(&r, "list"));
        }
        let j = Self::json(&r, "list")?;
        let files = j["files"].as_array().cloned().unwrap_or_default();
        Ok((files, j["nextPageToken"].as_str().map(str::to_owned)))
    }

    fn need_id(e: &Entry) -> Result<&str, Error> {
        e.id.as_deref()
            .filter(|i| valid_id(i))
            .ok_or_else(|| Error::NotFound(format!("{}: no Drive id", e.path)))
    }

    /// The path and query of a session URL Drive gave, which must be on
    /// the API's own origin (the token is never sent elsewhere).
    fn same_origin(&self, url: &str) -> Result<String, Error> {
        let ep = &self.api.endpoint;
        let origin = format!(
            "{}://{}",
            if ep.tls { "https" } else { "http" },
            ep.authority()
        );
        url.strip_prefix(&origin)
            .filter(|rest| rest.starts_with('/'))
            .map(str::to_owned)
            .ok_or_else(|| {
                Error::Refused("upload: the session URL is not on the API's origin".into())
            })
    }

    fn file_target(&self, id: &str, query: &str) -> String {
        format!(
            "{}/drive/v3/files/{id}?supportsAllDrives=true{query}",
            self.api.endpoint.prefix
        )
    }
}

impl Backend for GDriveStore {
    const NAME: &'static str = "gdrive";
    const VERSION: &'static str = env!("CARGO_PKG_VERSION");
    const DISPLAY: &'static str = "Google Drive";
    type Params = DriveParams;

    fn new(p: &DriveParams) -> Result<Self, LinkError> {
        let tls = Some(tls_config(&p.ca_pem, false).map_err(|e| bad("ca_pem", e))?);
        let (api, _) = endpoint("api_url", &p.api_url, &tls)?;
        let (tok_http, tok_ep) = endpoint("token_url", &p.token_url, &tls)?;
        let tok_path = if tok_ep.prefix.is_empty() {
            "/".to_owned()
        } else {
            tok_ep.prefix.clone()
        };
        let folder = p.folder_id.trim();
        if !valid_id(folder) {
            return Err(bad("folder_id", "letters, digits, '-' and '_'"));
        }
        let drive = match p.shared_drive_id.trim() {
            "" => None,
            d if valid_id(d) => Some(d.to_owned()),
            _ => return Err(bad("shared_drive_id", "letters, digits, '-' and '_'")),
        };
        let root_id = match (&drive, folder) {
            (Some(d), "root") => d.clone(),
            _ => folder.to_owned(),
        };
        let grant = match p.auth {
            Auth::ServiceAccount => {
                if p.service_account_json.trim().is_empty() {
                    return Err(bad(
                        "service_account_json",
                        "required with auth service_account",
                    ));
                }
                // Never echo the key file in an error.
                let j: Json = serde_json::from_str(&p.service_account_json)
                    .map_err(|_| bad("service_account_json", "not JSON"))?;
                let email = j["client_email"]
                    .as_str()
                    .filter(|e| e.contains('@'))
                    .ok_or_else(|| bad("service_account_json", "no client_email"))?;
                let pem = j["private_key"]
                    .as_str()
                    .ok_or_else(|| bad("service_account_json", "no private_key"))?;
                let key = auth::rsa_key(pem).map_err(|e| bad("service_account_json", e))?;
                let subject = p.subject.trim();
                Grant::ServiceAccount {
                    email: email.to_owned(),
                    key: Box::new(key),
                    subject: (!subject.is_empty()).then(|| subject.to_owned()),
                }
            }
            Auth::RefreshToken => {
                if p.client_id.trim().is_empty()
                    || p.client_secret.is_empty()
                    || p.refresh_token.is_empty()
                {
                    return Err(bad(
                        "refresh_token",
                        "client_id, client_secret and refresh_token are required with auth refresh_token",
                    ));
                }
                Grant::RefreshToken {
                    client_id: p.client_id.trim().to_owned(),
                    client_secret: zeroize::Zeroizing::new(p.client_secret.clone()),
                    refresh_token: zeroize::Zeroizing::new(p.refresh_token.clone()),
                }
            }
        };
        let timeout = Duration::from_millis(p.timeout_ms.into());
        if !p.upload_chunk_kib.is_multiple_of(256) {
            return Err(bad("upload_chunk_kib", "a multiple of 256 (Drive's rule)"));
        }
        Ok(Self {
            chunk: u64::from(p.upload_chunk_kib) * 1024,
            api,
            tokens: Tokens::new(
                grant,
                tok_http,
                tok_path,
                p.token_url.trim().to_owned(),
                timeout,
            ),
            root_id,
            drive,
            trash: p.trash,
            timeout,
        })
    }

    fn timeout(&self) -> Duration {
        // the probe takes a token first
        self.timeout * 2
    }

    fn root(&self) -> Entry {
        Entry::root(Some(self.root_id.clone()))
    }

    async fn check(&self) -> Result<(), Error> {
        let target = self.file_target(
            &self.root_id,
            &format!("&fields={}", pct_encode(FIELDS, false)),
        );
        let r = self
            .call(Method::GET, target, None, Bytes::new(), MAX_LISTING)
            .await?;
        if !r.ok() {
            let e = Self::fail(&r, &format!("folder {}", self.root_id));
            return Err(match e {
                Error::NotFound(m) | Error::Refused(m) => Error::Auth(m),
                other => other,
            });
        }
        let j = Self::json(&r, "folder")?;
        if j["mimeType"].as_str() != Some(FOLDER_MIME) {
            return Err(Error::Auth(format!("{} is not a folder", self.root_id)));
        }
        Ok(())
    }

    async fn scan(&self, dir: &Entry, limits: Limits) -> Result<Scan, Error> {
        let mut scan = Scan::default();
        let id = Self::need_id(dir)?.to_owned();
        let mut queue = VecDeque::from([(id, dir.path.clone(), 0usize)]);
        let mut seen = BTreeSet::new();
        while let Some((id, path, depth)) = queue.pop_front() {
            if !seen.insert(id.clone()) {
                continue; // a folder with two parents
            }
            let mut page = None;
            let mut names = BTreeSet::new();
            loop {
                let (files, next) = self.children(&id, page.as_deref()).await?;
                for f in &files {
                    if scan.entries.len() >= limits.max_entries {
                        scan.truncated = true;
                        return Ok(scan);
                    }
                    let name = f["name"].as_str().unwrap_or("");
                    let fid = f["id"].as_str().unwrap_or("");
                    if name.is_empty() || !valid_id(fid) {
                        continue;
                    }
                    // a second file of one name (Drive allows it) and a name
                    // that is another's path form get the id in the path
                    let base = segment(name);
                    let mut seg = base.clone();
                    if names.contains(&seg) {
                        seg = format!("{base} ({})", &fid[..fid.len().min(8)]);
                    }
                    if names.contains(&seg) {
                        seg = format!("{base} ({fid})");
                    }
                    if !names.insert(seg.clone()) {
                        continue; // the same id twice in one listing
                    }
                    let e = entry(&path, &seg, f);
                    if e.dir {
                        if depth + 1 < limits.max_depth {
                            queue.push_back((fid.to_owned(), e.path.clone(), depth + 1));
                        } else {
                            scan.truncated = true;
                        }
                    }
                    scan.entries.push(e);
                }
                match next {
                    Some(n) => page = Some(n),
                    None => break,
                }
            }
        }
        Ok(scan)
    }

    async fn mkdir(&self, parent: &Entry, name: &str) -> Result<Entry, Error> {
        let pid = Self::need_id(parent)?;
        let body = json!({"name": name, "mimeType": FOLDER_MIME, "parents": [pid]}).to_string();
        let target = format!(
            "{}/drive/v3/files?supportsAllDrives=true&fields={}",
            self.api.endpoint.prefix,
            pct_encode(FIELDS, false)
        );
        let r = self
            .call(
                Method::POST,
                target,
                Some("application/json; charset=UTF-8"),
                body.into(),
                MAX_LISTING,
            )
            .await?;
        if !r.ok() {
            return Err(Self::fail(&r, &format!("create folder {name}")));
        }
        Ok(entry(
            &parent.path,
            &segment(name),
            &Self::json(&r, "create folder")?,
        ))
    }

    async fn put(
        &self,
        parent: &Entry,
        name: &str,
        data: Bytes,
        content_type: &str,
        existing: Option<&Entry>,
    ) -> Result<Entry, Error> {
        let fields = pct_encode(FIELDS, false);
        let r = match existing {
            Some(e) => {
                let id = Self::need_id(e)?;
                let target = format!(
                    "{}/upload/drive/v3/files/{id}?uploadType=media&supportsAllDrives=true&fields={fields}",
                    self.api.endpoint.prefix
                );
                self.call(Method::PATCH, target, Some(content_type), data, MAX_LISTING)
                    .await?
            }
            None => {
                let pid = Self::need_id(parent)?;
                let meta =
                    json!({"name": name, "parents": [pid], "mimeType": content_type}).to_string();
                let boundary = loop {
                    let mut b = [0u8; 16];
                    ring::rand::SecureRandom::fill(&ring::rand::SystemRandom::new(), &mut b)
                        .map_err(|_| Error::Refused("no randomness".into()))?;
                    let b = format!("wyrm{}", hex::encode(b));
                    if !data.windows(b.len()).any(|w| w == b.as_bytes()) {
                        break b;
                    }
                };
                let mut body = Vec::with_capacity(data.len() + meta.len() + 256);
                body.extend_from_slice(
                    format!(
                        "--{boundary}\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n{meta}\r\n--{boundary}\r\nContent-Type: {content_type}\r\n\r\n"
                    )
                    .as_bytes(),
                );
                body.extend_from_slice(&data);
                body.extend_from_slice(format!("\r\n--{boundary}--\r\n").as_bytes());
                let target = format!(
                    "{}/upload/drive/v3/files?uploadType=multipart&supportsAllDrives=true&fields={fields}",
                    self.api.endpoint.prefix
                );
                let ctype = format!("multipart/related; boundary={boundary}");
                self.call(Method::POST, target, Some(&ctype), body.into(), MAX_LISTING)
                    .await?
            }
        };
        if !r.ok() {
            return Err(Self::fail(&r, &format!("upload {name}")));
        }
        let path_seg = existing
            .and_then(|e| e.path.rsplit('/').next().map(str::to_owned))
            .unwrap_or_else(|| segment(name));
        Ok(entry(&parent.path, &path_seg, &Self::json(&r, "upload")?))
    }

    async fn put_file(
        &self,
        parent: &Entry,
        name: &str,
        src: &std::path::Path,
        size: u64,
        content_type: &str,
        existing: Option<&Entry>,
    ) -> Result<Entry, Error> {
        // a resumable upload: a session, then chunks read from the spool file
        let fields = pct_encode(FIELDS, false);
        let prefix = &self.api.endpoint.prefix;
        let (method, target, meta) = match existing {
            Some(e) => (
                Method::PATCH,
                format!(
                    "{prefix}/upload/drive/v3/files/{}?uploadType=resumable&supportsAllDrives=true&fields={fields}",
                    Self::need_id(e)?
                ),
                json!({}),
            ),
            None => (
                Method::POST,
                format!("{prefix}/upload/drive/v3/files?uploadType=resumable&supportsAllDrives=true&fields={fields}"),
                json!({"name": name, "parents": [Self::need_id(parent)?], "mimeType": content_type}),
            ),
        };
        let start = Request::new(method, target)
            .header("content-type", "application/json; charset=UTF-8")
            .header("x-upload-content-type", content_type)
            .header("x-upload-content-length", &size.to_string())
            .body(meta.to_string());
        let r = self.call_req(start, MAX_LISTING).await?;
        if !r.ok() {
            return Err(Self::fail(&r, &format!("upload {name}")));
        }
        let session = r
            .header("location")
            .ok_or_else(|| Error::Refused(format!("upload {name}: no session URL")))?;
        let session = self.same_origin(session)?;
        let mut offset = 0u64;
        loop {
            let len = self.chunk.min(size - offset);
            let req = Request::new(Method::PUT, session.clone())
                .header(
                    "content-range",
                    &format!("bytes {offset}-{}/{size}", offset + len - 1),
                )
                .file_body(src, offset, len);
            let r = self.call_req(req, MAX_LISTING).await?;
            match r.status {
                200 | 201 => {
                    let path_seg = existing
                        .and_then(|e| e.path.rsplit('/').next().map(str::to_owned))
                        .unwrap_or_else(|| segment(name));
                    return Ok(entry(&parent.path, &path_seg, &Self::json(&r, "upload")?));
                }
                // more to send: from where Drive says it has the bytes
                308 => {
                    let got = r
                        .header("range")
                        .and_then(|h| h.strip_prefix("bytes=0-"))
                        .and_then(|n| n.parse::<u64>().ok())
                        .map_or(0, |n| n + 1);
                    if got <= offset || got > size {
                        return Err(Error::Refused(format!(
                            "upload {name}: Drive took no bytes of the chunk at {offset}"
                        )));
                    }
                    offset = got;
                    if offset >= size {
                        return Err(Error::Refused(format!(
                            "upload {name}: Drive has every byte but did not finish"
                        )));
                    }
                }
                _ => return Err(Self::fail(&r, &format!("upload {name}"))),
            }
        }
    }

    async fn get_range(&self, file: &Entry, offset: u64, len: usize) -> Result<Bytes, Error> {
        if file
            .content_type
            .as_deref()
            .is_some_and(|m| m.starts_with("application/vnd.google-apps."))
        {
            return Err(Error::Refused(format!(
                "{}: a Google Docs file has no bytes to download",
                file.name
            )));
        }
        let id = Self::need_id(file)?;
        let range = format!("bytes={offset}-{}", offset + len as u64 - 1);
        let req =
            Request::new(Method::GET, self.file_target(id, "&alt=media")).header("range", &range);
        let r = self.call_req(req, len + 1024).await?;
        match r.status {
            206 => Ok(r.body),
            200 if offset == 0 && r.body.len() <= len => Ok(r.body),
            200 => Err(Error::Refused(format!(
                "download {}: Drive ignored Range",
                file.path
            ))),
            416 => Ok(Bytes::new()),
            _ => Err(Self::fail(&r, &format!("download {}", file.path))),
        }
    }

    async fn get(&self, file: &Entry, max: usize) -> Result<Bytes, Error> {
        if file
            .content_type
            .as_deref()
            .is_some_and(|m| m.starts_with("application/vnd.google-apps."))
        {
            return Err(Error::Refused(format!(
                "{}: a Google Docs file has no bytes to download (export is not supported)",
                file.name
            )));
        }
        let id = Self::need_id(file)?;
        let r = self
            .call(
                Method::GET,
                self.file_target(id, "&alt=media"),
                None,
                Bytes::new(),
                max,
            )
            .await?;
        if !r.ok() {
            return Err(Self::fail(&r, &format!("download {}", file.path)));
        }
        Ok(r.body)
    }

    async fn delete(&self, e: &Entry, _below: &[Entry], recursive: bool) -> Result<(), Error> {
        let id = Self::need_id(e)?;
        if e.dir && !recursive {
            // trash or delete takes the folder's content: ask Drive first
            let (inside, _) = self.children(id, None).await?;
            if !inside.is_empty() {
                return Err(not_empty(&e.path));
            }
        }
        let r = if self.trash {
            self.call(
                Method::PATCH,
                self.file_target(id, "&fields=id"),
                Some("application/json; charset=UTF-8"),
                Bytes::from_static(br#"{"trashed":true}"#),
                MAX_LISTING,
            )
            .await?
        } else {
            self.call(
                Method::DELETE,
                self.file_target(id, ""),
                None,
                Bytes::new(),
                MAX_LISTING,
            )
            .await?
        };
        if !r.ok() && r.status != 404 {
            return Err(Self::fail(&r, &format!("delete {}", e.path)));
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn entries_and_ids() {
        assert!(valid_id("1AbC-_x"));
        assert!(!valid_id("a' or 1=1"));
        assert!(!valid_id(""));
        let f = json!({"id": "f1", "name": "a/b.txt", "mimeType": "text/plain", "size": "12",
                       "modifiedTime": "2024-01-02T03:04:05.000Z"});
        let e = entry("x", &segment("a/b.txt"), &f);
        assert_eq!(e.path, "x/a_b.txt");
        assert_eq!(e.name, "a/b.txt");
        assert_eq!(e.size, Some(12));
        assert!(!e.dir);
        let d = entry(
            "",
            "d",
            &json!({"id": "d1", "name": "d", "mimeType": FOLDER_MIME}),
        );
        assert!(d.dir);
        assert_eq!(d.size, None);
    }
}
