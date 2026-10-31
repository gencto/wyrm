//! WebDAV link (RFC 4918, class 1): one collection per connection —
//! Nextcloud and ownCloud (`https://<host>/remote.php/dav/files/<user>/`),
//! Synology, QNAP, Apache `mod_dav`, nginx, rclone serve, Box, pCloud,
//! Yandex Disk and others.
//!
//! The tree is read with `PROPFIND` `Depth: 1` folder by folder, breadth
//! first (many servers refuse `Depth: infinity`), within `max_depth` and
//! `max_entries`. Folders are real collections (`MKCOL`); an upload is one
//! `PUT` (with `If-None-Match: *` unless it overwrites); `DELETE` of a
//! collection deletes what is in it. Authentication: none, basic (an app
//! password on Nextcloud) or a bearer token.

#![forbid(unsafe_code)]

#[cfg(feature = "sim")]
pub mod sim;

use base64::Engine as _;
use bytes::Bytes;
use hyper::Method;
use std::collections::VecDeque;
use std::time::Duration;
use wyrm_filestore::backend::{join, last_name, not_empty, status_error};
use wyrm_filestore::http::{range_reply, tls_config, Endpoint, Http, Request, Response};
use wyrm_filestore::util::{parse_http_date, pct_decode, pct_encode};
use wyrm_filestore::{xml, Backend, Entry, Error, FileStore, Limits, Scan};
use wyrm_link_sdk::{LinkError, ParamEnum, Params};

/// The `webdav` link.
pub type WebDav = FileStore<WebDavStore>;

const MAX_LISTING: usize = 16 * 1024 * 1024;

/// The properties a `PROPFIND` asks for.
pub const PROPFIND: &str = r#"<?xml version="1.0" encoding="utf-8"?>
<d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/><d:getcontentlength/><d:getlastmodified/><d:getetag/><d:getcontenttype/></d:prop></d:propfind>"#;

#[derive(Debug, Clone, Copy, PartialEq, Eq, ParamEnum)]
pub enum Auth {
    None,
    Basic,
    Bearer,
}

/// A connection's params. No `Debug`: it holds secrets.
#[derive(Clone, PartialEq, Params)]
pub struct DavParams {
    #[param(
        display = "URL",
        placeholder = "https://cloud.example.com/remote.php/dav/files/alice/plant",
        desc = "the collection that is the connection's root; percent-encode spaces",
        dest
    )]
    pub url: String,
    #[param(enum, default = "basic", display = "Authentication", dest)]
    pub auth: Auth,
    #[param(default = "", display = "Username", desc = "auth basic")]
    pub username: String,
    #[param(
        default = "",
        secret,
        display = "Password",
        desc = "auth basic (Nextcloud: an app password)"
    )]
    pub password: String,
    #[param(default = "", secret, display = "Token", desc = "auth bearer")]
    pub token: String,
    #[param(default = 10000, min = 500, max = 120000, display = "Timeout (ms)")]
    pub timeout_ms: u32,
    #[param(
        default = "",
        editor = "textarea",
        display = "CA Certificates (PEM)",
        desc = "https: trust these CAs only; empty = the CA certificates of the host",
        dest
    )]
    pub ca_pem: String,
    #[param(
        default = false,
        display = "Skip Certificate Check",
        desc = "https: accept any server certificate (insecure)",
        dest
    )]
    pub insecure_skip_verify: bool,
    #[param(
        default = false,
        display = "Allow Credentials over HTTP",
        desc = "send credentials over http:// to a host that is not loopback (insecure)",
        dest
    )]
    pub insecure_plaintext: bool,
}

pub struct WebDavStore {
    http: Http,
    /// The root collection's path, decoded, without a trailing `/`.
    base: String,
    auth: Option<zeroize::Zeroizing<String>>,
    timeout: Duration,
}

fn bad(name: &str, what: impl std::fmt::Display) -> LinkError {
    LinkError::invalid_parameter(format!("{name}: {what}"))
}

/// What one `<response>` of a multistatus says.
#[derive(Debug, Clone, PartialEq)]
pub struct Found {
    /// The decoded path of the href, without a trailing `/`.
    pub href: String,
    pub dir: bool,
    pub size: Option<u64>,
    pub modified: Option<u64>,
    pub etag: Option<String>,
    pub content_type: Option<String>,
}

/// The decoded path of an href (an absolute URL or an absolute path).
pub fn href_path(href: &str) -> Option<String> {
    let path = match href.find("://") {
        Some(i) => {
            let rest = &href[i + 3..];
            rest.find('/').map_or("/", |j| &rest[j..])
        }
        None => href,
    };
    pct_decode(path)
}

/// The responses of a `207 Multi-Status`.
pub fn parse_multistatus(body: &str) -> Result<Vec<Found>, String> {
    let doc = xml::parse(body)?;
    if doc.name != "multistatus" {
        return Err(format!("<{}> is not a multistatus", doc.name));
    }
    let mut out = Vec::new();
    for r in doc.all("response") {
        let Some(href) = r.text_of("href") else {
            continue;
        };
        // an absolute URL or an absolute path
        let path = match href.find("://") {
            Some(i) => {
                let rest = &href[i + 3..];
                rest.find('/').map_or("/", |j| &rest[j..])
            }
            None => href,
        };
        let Some(path) = pct_decode(path) else {
            continue;
        };
        // the properties found (status 200), not those missing (404)
        let mut props = Vec::new();
        for ps in r.all("propstat") {
            let ok = ps
                .text_of("status")
                .is_none_or(|s| s.split_whitespace().nth(1) == Some("200"));
            if let (true, Some(p)) = (ok, ps.child("prop")) {
                props.push(p);
            }
        }
        let prop = |name: &str| {
            props
                .iter()
                .find_map(|p| p.child(name))
                .map(|e| e.text.trim().to_owned())
                .filter(|t| !t.is_empty())
        };
        let dir = props.iter().any(|p| {
            p.child("resourcetype")
                .is_some_and(|t| t.child("collection").is_some())
        });
        out.push(Found {
            href: path.trim_end_matches('/').to_owned(),
            dir,
            size: prop("getcontentlength").and_then(|s| s.parse().ok()),
            modified: prop("getlastmodified").and_then(|s| parse_http_date(&s)),
            etag: prop("getetag").map(|t| t.trim_start_matches("W/").trim_matches('"').to_owned()),
            content_type: prop("getcontenttype"),
        });
    }
    Ok(out)
}

impl WebDavStore {
    /// The request path of `path` below the root (`/` added for folders).
    fn target(&self, path: &str, dir: bool) -> String {
        let mut t = pct_encode(&self.base, true);
        if !path.is_empty() {
            t.push('/');
            t.push_str(&pct_encode(path, true));
        }
        if dir {
            t.push('/');
        }
        t
    }

    async fn send(
        &self,
        method: &str,
        target: String,
        extra: &[(&str, &str)],
        body: Bytes,
        max: usize,
    ) -> Result<Response, Error> {
        let m =
            Method::from_bytes(method.as_bytes()).map_err(|_| Error::Refused(method.to_owned()))?;
        self.send_req(Request::new(m, target).body(body), extra, max)
            .await
    }

    /// Send `req` with `extra` headers and the credentials, bounded by the
    /// timeout and the time its body takes at 512 KiB/s.
    async fn send_req(
        &self,
        mut req: Request,
        extra: &[(&str, &str)],
        max: usize,
    ) -> Result<Response, Error> {
        for (k, v) in extra {
            req = req.header(k, v);
        }
        if let Some(a) = &self.auth {
            req = req.secret_header("authorization", a);
        }
        let t = self.timeout + Duration::from_secs(req.body_len() / (512 * 1024));
        Ok(self.http.send(&req, t, max).await?)
    }

    async fn propfind(&self, path: &str, depth: &str) -> Result<Vec<Found>, Error> {
        let r = self
            .send(
                "PROPFIND",
                self.target(path, true),
                &[
                    ("depth", depth),
                    ("content-type", "application/xml; charset=utf-8"),
                ],
                Bytes::from_static(PROPFIND.as_bytes()),
                MAX_LISTING,
            )
            .await?;
        if r.status != 207 {
            return Err(match r.status {
                401 => Error::Auth(format!("PROPFIND /{path}: HTTP 401")),
                s => status_error(s, &format!("PROPFIND /{path}"), ""),
            });
        }
        parse_multistatus(&r.text()).map_err(|e| Error::Refused(format!("PROPFIND /{path}: {e}")))
    }

    /// The path below the root of a decoded href (`None` outside it).
    fn rel<'a>(&self, href: &'a str) -> Option<&'a str> {
        let rest = href.strip_prefix(self.base.as_str())?;
        if rest.is_empty() {
            Some("")
        } else {
            rest.strip_prefix('/')
        }
    }
}

impl Backend for WebDavStore {
    const NAME: &'static str = "webdav";
    const VERSION: &'static str = env!("CARGO_PKG_VERSION");
    const DISPLAY: &'static str = "WebDAV Folder";
    type Params = DavParams;

    fn new(p: &DavParams) -> Result<Self, LinkError> {
        let ep = Endpoint::parse(&p.url).map_err(|e| bad("url", e))?;
        let base = pct_decode(&ep.prefix).ok_or_else(|| bad("url", "bad percent-encoding"))?;
        let auth = match p.auth {
            Auth::None => None,
            Auth::Basic => {
                if p.username.is_empty() {
                    return Err(bad("username", "required with auth basic"));
                }
                if p.username.contains(':') {
                    return Err(bad("username", "no ':'"));
                }
                let raw = zeroize::Zeroizing::new(format!("{}:{}", p.username, p.password));
                Some(zeroize::Zeroizing::new(format!(
                    "Basic {}",
                    base64::engine::general_purpose::STANDARD.encode(raw.as_bytes())
                )))
            }
            Auth::Bearer => {
                if p.token.is_empty() {
                    return Err(bad("token", "required with auth bearer"));
                }
                // never echo the token
                if !p.token.bytes().all(|b| b.is_ascii_graphic()) {
                    return Err(bad("token", "only visible ASCII characters"));
                }
                Some(zeroize::Zeroizing::new(format!("Bearer {}", p.token)))
            }
        };
        if auth.is_some() && !ep.tls && !ep.is_loopback() && !p.insecure_plaintext {
            return Err(bad(
                "url",
                "credentials are never sent over http:// to a host that is not loopback \
                 (use https://, or set insecure_plaintext)",
            ));
        }
        if !ep.tls && (!p.ca_pem.trim().is_empty() || p.insecure_skip_verify) {
            return Err(bad(
                "ca_pem",
                "ca_pem and insecure_skip_verify only with https://",
            ));
        }
        let tls = if ep.tls {
            Some(tls_config(&p.ca_pem, p.insecure_skip_verify).map_err(|e| bad("tls", e))?)
        } else {
            None
        };
        Ok(Self {
            http: Http::new(ep, tls, concat!("wyrm-webdav/", env!("CARGO_PKG_VERSION"))),
            base,
            auth,
            timeout: Duration::from_millis(p.timeout_ms.into()),
        })
    }

    fn timeout(&self) -> Duration {
        self.timeout
    }

    fn root(&self) -> Entry {
        Entry::root(None)
    }

    async fn check(&self) -> Result<(), Error> {
        let found = self.propfind("", "0").await.map_err(|e| match e {
            Error::NotFound(m) | Error::Refused(m) => Error::Auth(m),
            other => other,
        })?;
        match found.first() {
            Some(f) if f.dir => Ok(()),
            Some(_) => Err(Error::Auth("the URL is a file, not a collection".into())),
            None => Err(Error::Auth("PROPFIND: no response for the URL".into())),
        }
    }

    async fn scan(&self, dir: &Entry, limits: Limits) -> Result<Scan, Error> {
        let mut scan = Scan::default();
        let mut queue = VecDeque::from([(dir.path.clone(), 0usize)]);
        while let Some((path, depth)) = queue.pop_front() {
            for f in self.propfind(&path, "1").await? {
                let Some(rel) = self.rel(&f.href) else {
                    continue;
                };
                if rel == path || rel.split('/').any(str::is_empty) && !rel.is_empty() {
                    continue; // the folder itself
                }
                if wyrm_filestore::backend::parent_of(rel) != Some(path.as_str()) {
                    continue; // a server that answered deeper than asked
                }
                if scan.entries.len() >= limits.max_entries {
                    scan.truncated = true;
                    return Ok(scan);
                }
                let e = Entry {
                    path: rel.to_owned(),
                    name: last_name(rel).to_owned(),
                    dir: f.dir,
                    size: (!f.dir).then(|| f.size.unwrap_or(0)),
                    modified: f.modified,
                    etag: f.etag,
                    content_type: f.content_type.filter(|_| !f.dir),
                    id: None,
                };
                if e.dir {
                    if depth + 1 < limits.max_depth {
                        queue.push_back((e.path.clone(), depth + 1));
                    } else {
                        scan.truncated = true;
                    }
                }
                scan.entries.push(e);
            }
        }
        Ok(scan)
    }

    async fn mkdir(&self, parent: &Entry, name: &str) -> Result<Entry, Error> {
        let path = join(&parent.path, name);
        let r = self
            .send(
                "MKCOL",
                self.target(&path, true),
                &[],
                Bytes::new(),
                MAX_LISTING,
            )
            .await?;
        if !r.ok() {
            return Err(match r.status {
                405 => Error::Exists(format!("create folder {path}: it exists")),
                s => status_error(s, &format!("create folder {path}"), ""),
            });
        }
        Ok(Entry::dir(path))
    }

    async fn put(
        &self,
        parent: &Entry,
        name: &str,
        data: Bytes,
        content_type: &str,
        existing: Option<&Entry>,
    ) -> Result<Entry, Error> {
        let path = join(&parent.path, name);
        let len = data.len() as u64;
        let mut extra = vec![("content-type", content_type)];
        if existing.is_none() {
            extra.push(("if-none-match", "*"));
        }
        let r = self
            .send("PUT", self.target(&path, false), &extra, data, MAX_LISTING)
            .await?;
        if !r.ok() {
            return Err(status_error(r.status, &format!("upload {path}"), ""));
        }
        let mut e = Entry::file(path, len);
        e.modified = Some(wyrm_filestore::util::now_us());
        e.etag = r
            .header("etag")
            .map(|t| t.trim_start_matches("W/").trim_matches('"').to_owned());
        e.content_type = Some(content_type.to_owned());
        Ok(e)
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
        // one PUT, its body read from the spool file as it goes out
        let path = join(&parent.path, name);
        let mut extra = vec![("content-type", content_type)];
        if existing.is_none() {
            extra.push(("if-none-match", "*"));
        }
        let req = Request::new(Method::PUT, self.target(&path, false)).file_body(src, 0, size);
        let r = self.send_req(req, &extra, MAX_LISTING).await?;
        if !r.ok() {
            return Err(status_error(r.status, &format!("upload {path}"), ""));
        }
        let mut e = Entry::file(path, size);
        e.modified = Some(wyrm_filestore::util::now_us());
        e.etag = r
            .header("etag")
            .map(|t| t.trim_start_matches("W/").trim_matches('"').to_owned());
        e.content_type = Some(content_type.to_owned());
        Ok(e)
    }

    async fn get_range(&self, file: &Entry, offset: u64, len: usize) -> Result<Bytes, Error> {
        let range = format!("bytes={offset}-{}", offset + len as u64 - 1);
        let r = self
            .send(
                "GET",
                self.target(&file.path, false),
                &[("range", &range)],
                Bytes::new(),
                len + 1024,
            )
            .await?;
        let what = format!("download {}", file.path);
        range_reply(r, offset, len, &what, |r| status_error(r.status, &what, ""))
    }

    async fn get(&self, file: &Entry, max: usize) -> Result<Bytes, Error> {
        let r = self
            .send(
                "GET",
                self.target(&file.path, false),
                &[],
                Bytes::new(),
                max,
            )
            .await?;
        if !r.ok() {
            return Err(status_error(
                r.status,
                &format!("download {}", file.path),
                "",
            ));
        }
        Ok(r.body)
    }

    async fn delete(&self, e: &Entry, _below: &[Entry], recursive: bool) -> Result<(), Error> {
        if e.dir && !recursive {
            // DELETE of a collection takes all in it: ask the server first.
            // Fail closed: any response but the collection itself (one we
            // cannot map, or whose href does not decode, too) is content.
            let r = self
                .send(
                    "PROPFIND",
                    self.target(&e.path, true),
                    &[
                        ("depth", "1"),
                        ("content-type", "application/xml; charset=utf-8"),
                    ],
                    Bytes::from_static(PROPFIND.as_bytes()),
                    MAX_LISTING,
                )
                .await?;
            if r.status != 207 {
                return Err(status_error(r.status, &format!("PROPFIND /{}", e.path), ""));
            }
            let doc = xml::parse(&r.text())
                .map_err(|x| Error::Refused(format!("PROPFIND /{}: {x}", e.path)))?;
            // exactly one response, and it is the collection (none at all
            // says nothing about the content either)
            let mut seen = 0usize;
            for resp in doc.all("response") {
                let me = resp
                    .text_of("href")
                    .and_then(href_path)
                    .is_some_and(|h| self.rel(h.trim_end_matches('/')) == Some(e.path.as_str()));
                seen += 1;
                if !me || seen > 1 {
                    return Err(not_empty(&e.path));
                }
            }
            if seen != 1 {
                return Err(not_empty(&e.path));
            }
        }
        let r = self
            .send(
                "DELETE",
                self.target(&e.path, e.dir),
                &[],
                Bytes::new(),
                MAX_LISTING,
            )
            .await?;
        if !r.ok() && r.status != 404 {
            return Err(status_error(r.status, &format!("delete {}", e.path), ""));
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A Nextcloud-style reply: prefixes, a full URL href, a 404 propstat.
    #[test]
    fn multistatus() {
        let body = r#"<?xml version="1.0"?>
<d:multistatus xmlns:d="DAV:" xmlns:s="http://sabredav.org/ns" xmlns:oc="http://owncloud.org/ns">
 <d:response><d:href>/remote.php/dav/files/alice/My%20Docs/</d:href>
  <d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype>
   <d:getlastmodified>Tue, 02 Jan 2024 03:04:05 GMT</d:getlastmodified></d:prop>
   <d:status>HTTP/1.1 200 OK</d:status></d:propstat>
  <d:propstat><d:prop><d:getcontentlength/></d:prop><d:status>HTTP/1.1 404 Not Found</d:status></d:propstat>
 </d:response>
 <d:response><d:href>https://cloud.example.com/remote.php/dav/files/alice/My%20Docs/r%C3%A9sum%C3%A9.pdf</d:href>
  <d:propstat><d:prop><d:resourcetype/><d:getcontentlength>1234</d:getcontentlength>
   <d:getetag>&quot;abc&quot;</d:getetag><d:getcontenttype>application/pdf</d:getcontenttype></d:prop>
   <d:status>HTTP/1.1 200 OK</d:status></d:propstat>
 </d:response>
</d:multistatus>"#;
        let f = parse_multistatus(body).unwrap();
        assert_eq!(f.len(), 2);
        assert_eq!(f[0].href, "/remote.php/dav/files/alice/My Docs");
        assert!(f[0].dir);
        assert_eq!(f[0].size, None);
        assert_eq!(f[0].modified, Some(1_704_164_645_000_000));
        assert_eq!(f[1].href, "/remote.php/dav/files/alice/My Docs/résumé.pdf");
        assert!(!f[1].dir);
        assert_eq!(f[1].size, Some(1234));
        assert_eq!(f[1].etag.as_deref(), Some("abc"));
        assert!(parse_multistatus("<a/>").is_err());
    }
}
