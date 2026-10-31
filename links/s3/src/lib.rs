//! S3 link: one bucket (or a prefix in it) per connection, through the S3
//! REST API with Signature V4 — AWS S3, MinIO, Ceph RGW, Cloudflare R2,
//! Wasabi, Backblaze B2, DigitalOcean Spaces, Google Cloud Storage with
//! HMAC keys (`https://storage.googleapis.com`, region `auto`).
//!
//! S3 has keys, not folders: the tree is read with ListObjectsV2 (no
//! delimiter, pages of 1000) and every `/` in a key is a folder level.
//! `Create Folder` stores the empty marker object `<folder>/`, as the S3
//! consoles do; a folder with files and no marker shows too. An upload is
//! one PutObject (with `If-None-Match: *` unless it overwrites, so a file
//! created meanwhile is not replaced); deleting a folder deletes every key
//! below it. Without an access key the requests are not signed (a public
//! bucket).
//!
//! The probe is a ListObjectsV2 of one key: it needs the list permission
//! the tree needs anyway. A 301 (the bucket is in another region) names
//! the region in the error.

#![forbid(unsafe_code)]

pub mod sigv4;
#[cfg(feature = "sim")]
pub mod sim;

use bytes::Bytes;
use hyper::Method;
use std::time::Duration;
use wyrm_filestore::backend::{join, not_empty, status_error};
use wyrm_filestore::http::{tls_config, Endpoint, Http, Request, Response};
use wyrm_filestore::util::{amz_date, parse_rfc3339, pct_encode};
use wyrm_filestore::{xml, Backend, Entry, Error, FileStore, Limits, Scan};
use wyrm_link_sdk::{LinkError, ParamEnum, Params};

/// The `s3` link.
pub type S3 = FileStore<S3Store>;

/// Largest listing or error reply read.
const MAX_LISTING: usize = 8 * 1024 * 1024;
/// ListObjectsV2 pages read in one scan at most (1000 keys each).
const MAX_PAGES: usize = 500;
/// Keys deleted with a folder at most.
const MAX_DELETE: usize = 10_000;

#[derive(Debug, Clone, Copy, PartialEq, Eq, ParamEnum)]
pub enum Addressing {
    /// Virtual-hosted on `*.amazonaws.com` (a DNS-safe bucket), path-style
    /// elsewhere.
    Auto,
    /// `https://host/bucket/key` (MinIO, Ceph, most S3-compatible stores).
    Path,
    /// `https://bucket.host/key`.
    Virtual,
}

/// A connection's params. No `Debug`: it holds secrets.
#[derive(Clone, PartialEq, Params)]
pub struct S3Params {
    #[param(
        default = "https://s3.amazonaws.com",
        display = "Endpoint",
        placeholder = "https://minio.local:9000",
        desc = "AWS: https://s3.<region>.amazonaws.com; R2: https://<account>.r2.cloudflarestorage.com; GCS: https://storage.googleapis.com",
        dest
    )]
    pub endpoint: String,
    #[param(
        default = "us-east-1",
        display = "Region",
        desc = "MinIO and most stores: us-east-1; R2 and GCS: auto",
        dest
    )]
    pub region: String,
    #[param(display = "Bucket", placeholder = "plant-reports", dest)]
    pub bucket: String,
    #[param(enum, default = "auto", display = "Addressing", dest)]
    pub addressing: Addressing,
    #[param(
        default = "",
        display = "Prefix",
        placeholder = "site1/reports",
        desc = "the connection's root folder inside the bucket; empty = the whole bucket"
    )]
    pub prefix: String,
    #[param(
        default = "",
        display = "Access Key ID",
        desc = "empty: unsigned requests (a public bucket)"
    )]
    pub access_key_id: String,
    #[param(default = "", secret, display = "Secret Access Key")]
    pub secret_access_key: String,
    #[param(
        default = "",
        secret,
        display = "Session Token",
        desc = "temporary credentials (STS) only"
    )]
    pub session_token: String,
    #[param(default = 10000, min = 500, max = 120000, display = "Timeout (ms)")]
    pub timeout_ms: u32,
    #[param(
        default = 16,
        min = 5,
        max = 512,
        display = "Multipart Part (MiB)",
        desc = "a file received in parts goes to the bucket in parts of this size (S3: at least 5 MiB)"
    )]
    pub multipart_mib: u32,
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
        desc = "sign requests over http:// to a host that is not loopback (insecure)",
        dest
    )]
    pub insecure_plaintext: bool,
}

/// A running S3 connection.
pub struct S3Store {
    http: Http,
    region: String,
    bucket: String,
    virtual_host: bool,
    /// Without leading or trailing `/`.
    prefix: String,
    access: String,
    secret: zeroize::Zeroizing<String>,
    token: zeroize::Zeroizing<String>,
    timeout: Duration,
    /// Part size of a multipart upload (bytes).
    multipart: u64,
}

fn bad(name: &str, what: impl std::fmt::Display) -> LinkError {
    LinkError::invalid_parameter(format!("{name}: {what}"))
}

/// S3 bucket naming rules (the strict ones; legacy names with uppercase
/// or `_` only path-style).
fn dns_bucket(b: &str) -> bool {
    (3..=63).contains(&b.len())
        && b.bytes()
            .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == b'-')
        && !b.starts_with('-')
        && !b.ends_with('-')
}

impl S3Store {
    /// The key of `path` below the connection's prefix.
    fn key(&self, path: &str) -> String {
        if path.is_empty() {
            self.prefix.clone()
        } else {
            join(&self.prefix, path)
        }
    }

    /// The path below the prefix of `key` (`None` outside it).
    fn rel<'a>(&self, key: &'a str) -> Option<&'a str> {
        if self.prefix.is_empty() {
            Some(key)
        } else {
            key.strip_prefix(self.prefix.as_str())?.strip_prefix('/')
        }
    }

    /// The request path of `key` (encoded); `""` = the bucket.
    fn target(&self, key: &str) -> String {
        let p = &self.http.endpoint.prefix;
        let k = pct_encode(key, true);
        if self.virtual_host {
            format!("{p}/{k}")
        } else if key.is_empty() {
            format!("{p}/{}", self.bucket)
        } else {
            format!("{p}/{}/{k}", self.bucket)
        }
    }

    async fn send(
        &self,
        method: Method,
        key: &str,
        query: &[(String, String)],
        extra: &[(&str, &str)],
        body: Bytes,
        max: usize,
    ) -> Result<Response, Error> {
        let path = self.target(key);
        let mut target = path.clone();
        if !query.is_empty() {
            target.push('?');
            target.push_str(&sigv4::canonical_query(query));
        }
        let mut req = Request::new(method.clone(), target).body(body.clone());
        for (k, v) in extra {
            req = req.header(k, v);
        }
        if !self.access.is_empty() {
            let secs = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_secs())
                .unwrap_or(0);
            let (stamp, _) = amz_date(secs);
            let hash = if body.is_empty() {
                sigv4::EMPTY_SHA256.to_owned()
            } else {
                sigv4::sha256_hex(&body)
            };
            let mut signed = vec![
                ("host".to_owned(), self.http.endpoint.authority()),
                ("x-amz-content-sha256".to_owned(), hash.clone()),
                ("x-amz-date".to_owned(), stamp.clone()),
            ];
            if !self.token.is_empty() {
                signed.push(("x-amz-security-token".to_owned(), self.token.to_string()));
            }
            let auth = sigv4::authorization(&sigv4::Signing {
                method: method.as_str(),
                path: &path,
                query,
                headers: &signed,
                payload_sha256: &hash,
                access_key: &self.access,
                secret_key: &self.secret,
                region: &self.region,
                service: "s3",
                amz_date: &stamp,
            });
            req = req
                .header("x-amz-content-sha256", &hash)
                .header("x-amz-date", &stamp)
                .secret_header("authorization", &auth);
            if !self.token.is_empty() {
                req = req.secret_header("x-amz-security-token", &self.token);
            }
        }
        // Large bodies: time to send them too (at 512 KiB/s at least).
        let t = self.timeout + Duration::from_secs(body.len() as u64 / (512 * 1024));
        Ok(self.http.send(&req, t, max).await?)
    }

    /// `Code: Message` of an S3 error body.
    fn detail(r: &Response) -> String {
        let Ok(doc) = xml::parse(&r.text()) else {
            return String::new();
        };
        match (doc.text_of("Code"), doc.text_of("Message")) {
            (Some(c), Some(m)) => format!("{c}: {m}"),
            (Some(c), None) => c.to_owned(),
            _ => String::new(),
        }
    }

    fn fail(r: &Response, what: &str) -> Error {
        status_error(r.status, what, &Self::detail(r))
    }

    /// One ListObjectsV2 page below `prefix`.
    async fn list_page(
        &self,
        prefix: &str,
        token: Option<&str>,
        max_keys: usize,
    ) -> Result<(Vec<xml::Element>, Option<String>), Error> {
        let mut q = vec![
            ("list-type".to_owned(), "2".to_owned()),
            ("max-keys".to_owned(), max_keys.to_string()),
        ];
        if !prefix.is_empty() {
            q.push(("prefix".to_owned(), prefix.to_owned()));
        }
        if let Some(t) = token {
            q.push(("continuation-token".to_owned(), t.to_owned()));
        }
        let r = self
            .send(Method::GET, "", &q, &[], Bytes::new(), MAX_LISTING)
            .await?;
        if !r.ok() {
            return Err(Self::fail(&r, "list"));
        }
        let doc = xml::parse(&r.text()).map_err(|e| Error::Refused(format!("list: {e}")))?;
        let next = (doc.text_of("IsTruncated") == Some("true"))
            .then(|| doc.text_of("NextContinuationToken").map(str::to_owned))
            .flatten();
        let contents = doc.all("Contents").cloned().collect();
        Ok((contents, next))
    }

    /// Every key below `prefix` (at most `cap`).
    async fn keys_below(&self, prefix: &str, cap: usize) -> Result<Vec<String>, Error> {
        let mut out = Vec::new();
        let mut token = None;
        loop {
            let (page, next) = self.list_page(prefix, token.as_deref(), 1000).await?;
            out.extend(
                page.iter()
                    .filter_map(|c| c.text_of("Key").map(str::to_owned)),
            );
            if out.len() >= cap {
                return Err(Error::TooLarge(format!(
                    "more than {cap} keys below {prefix}"
                )));
            }
            match next {
                Some(t) => token = Some(t),
                None => return Ok(out),
            }
        }
    }
}

/// `len` bytes of `src` from `offset`, read on the blocking pool.
async fn read_part(src: &std::path::Path, offset: u64, len: u64) -> Result<Bytes, Error> {
    use std::io::{Read, Seek, SeekFrom};
    let p = src.to_path_buf();
    tokio::task::spawn_blocking(move || -> std::io::Result<Vec<u8>> {
        let mut f = std::fs::File::open(&p)?;
        f.seek(SeekFrom::Start(offset))?;
        let mut buf = vec![0u8; len as usize];
        f.read_exact(&mut buf)?;
        Ok(buf)
    })
    .await
    .map_err(|e| Error::Refused(e.to_string()))?
    .map(Bytes::from)
    .map_err(|e| Error::Refused(format!("the received parts: {e}")))
}

impl S3Store {
    /// CreateMultipartUpload: the upload id.
    async fn multipart_begin(&self, key: &str, content_type: &str) -> Result<String, Error> {
        let q = [("uploads".to_owned(), String::new())];
        let r = self
            .send(
                Method::POST,
                key,
                &q,
                &[("content-type", content_type)],
                Bytes::new(),
                MAX_LISTING,
            )
            .await?;
        if !r.ok() {
            return Err(Self::fail(&r, &format!("upload {key}")));
        }
        let doc = xml::parse(&r.text()).map_err(|e| Error::Refused(format!("upload: {e}")))?;
        doc.text_of("UploadId")
            .filter(|u| !u.is_empty())
            .map(str::to_owned)
            .ok_or_else(|| Error::Refused("upload: no UploadId in the answer".into()))
    }

    /// UploadPart for each part (one in memory at a time), then
    /// CompleteMultipartUpload; the object's ETag.
    async fn multipart_send(
        &self,
        key: &str,
        upload: &str,
        src: &std::path::Path,
        size: u64,
        part: u64,
        new_only: bool,
    ) -> Result<Option<String>, Error> {
        let mut done = String::from("<CompleteMultipartUpload>");
        let mut offset = 0u64;
        let mut n = 1u32;
        while offset < size {
            let len = part.min(size - offset);
            let data = read_part(src, offset, len).await?;
            let q = [
                ("partNumber".to_owned(), n.to_string()),
                ("uploadId".to_owned(), upload.to_owned()),
            ];
            let r = self
                .send(Method::PUT, key, &q, &[], data, MAX_LISTING)
                .await?;
            if !r.ok() {
                return Err(Self::fail(&r, &format!("upload {key} part {n}")));
            }
            let etag = r
                .header("etag")
                .ok_or_else(|| Error::Refused(format!("upload {key} part {n}: no ETag")))?;
            done.push_str(&format!(
                "<Part><PartNumber>{n}</PartNumber><ETag>{}</ETag></Part>",
                xml::escape(etag)
            ));
            offset += len;
            n += 1;
        }
        done.push_str("</CompleteMultipartUpload>");
        let q = [("uploadId".to_owned(), upload.to_owned())];
        let mut extra = vec![("content-type", "application/xml")];
        if new_only {
            extra.push(("if-none-match", "*"));
        }
        let r = self
            .send(
                Method::POST,
                key,
                &q,
                &extra,
                Bytes::from(done),
                MAX_LISTING,
            )
            .await?;
        // a 200 may carry an error (S3 reports late failures so)
        let doc = xml::parse(&r.text()).ok();
        if !r.ok() || doc.as_ref().is_some_and(|d| d.name == "Error") {
            return Err(Self::fail(&r, &format!("upload {key}")));
        }
        Ok(doc
            .as_ref()
            .and_then(|d| d.text_of("ETag"))
            .map(|t| t.trim_matches('"').to_owned()))
    }
}

impl Backend for S3Store {
    const NAME: &'static str = "s3";
    const VERSION: &'static str = env!("CARGO_PKG_VERSION");
    const DISPLAY: &'static str = "S3 Bucket";
    type Params = S3Params;

    fn new(p: &S3Params) -> Result<Self, LinkError> {
        let ep = Endpoint::parse(&p.endpoint).map_err(|e| bad("endpoint", e))?;
        let bucket = p.bucket.trim();
        if bucket.is_empty()
            || bucket.len() > 255
            || !bucket
                .bytes()
                .all(|c| c.is_ascii_alphanumeric() || matches!(c, b'-' | b'.' | b'_'))
        {
            return Err(bad("bucket", "letters, digits, '-', '.' and '_' only"));
        }
        let region = p.region.trim();
        if region.is_empty()
            || !region
                .bytes()
                .all(|c| c.is_ascii_alphanumeric() || c == b'-')
        {
            return Err(bad("region", "letters, digits and '-' only"));
        }
        let virtual_host = match p.addressing {
            Addressing::Path => false,
            Addressing::Virtual => true,
            Addressing::Auto => ep.host.ends_with("amazonaws.com") && dns_bucket(bucket),
        };
        if virtual_host && bucket.contains(['.', '_']) {
            return Err(bad(
                "addressing",
                "virtual needs a bucket without '.' or '_'",
            ));
        }
        let prefix = p.prefix.trim().trim_matches('/').to_owned();
        if prefix
            .split('/')
            .any(|s| s.is_empty() || s == "." || s == "..")
            && !prefix.is_empty()
        {
            return Err(bad("prefix", "no empty, '.' or '..' folders"));
        }
        let access = p.access_key_id.trim().to_owned();
        if access.is_empty() != p.secret_access_key.is_empty() {
            return Err(bad(
                "secret_access_key",
                "give access_key_id and secret_access_key together, or neither",
            ));
        }
        if !access.is_empty() && !ep.tls && !ep.is_loopback() && !p.insecure_plaintext {
            return Err(bad(
                "endpoint",
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
        let ep = if virtual_host {
            ep.with_host(&format!("{bucket}.{}", ep.host))
        } else {
            ep
        };
        Ok(Self {
            http: Http::new(ep, tls, concat!("wyrm-s3/", env!("CARGO_PKG_VERSION"))),
            region: region.to_owned(),
            bucket: bucket.to_owned(),
            virtual_host,
            prefix,
            access,
            secret: zeroize::Zeroizing::new(p.secret_access_key.clone()),
            token: zeroize::Zeroizing::new(p.session_token.clone()),
            timeout: Duration::from_millis(p.timeout_ms.into()),
            multipart: u64::from(p.multipart_mib) * 1024 * 1024,
        })
    }

    fn timeout(&self) -> Duration {
        self.timeout
    }

    fn root(&self) -> Entry {
        Entry::root(None)
    }

    async fn check(&self) -> Result<(), Error> {
        let prefix = if self.prefix.is_empty() {
            String::new()
        } else {
            format!("{}/", self.prefix)
        };
        let mut q = vec![
            ("list-type".to_owned(), "2".to_owned()),
            ("max-keys".to_owned(), "1".to_owned()),
        ];
        if !prefix.is_empty() {
            q.push(("prefix".to_owned(), prefix));
        }
        let r = self
            .send(Method::GET, "", &q, &[], Bytes::new(), MAX_LISTING)
            .await?;
        if r.ok() {
            return Ok(());
        }
        let detail = Self::detail(&r);
        let msg = format!("bucket {}: HTTP {} {detail}", self.bucket, r.status);
        Err(match r.status {
            401 | 403 => Error::Auth(msg),
            301 | 307 => match r.header("x-amz-bucket-region") {
                Some(reg) => Error::Unreachable(format!("{msg} (the bucket is in region {reg})")),
                None => Error::Unreachable(msg),
            },
            _ => Error::Unreachable(msg),
        })
    }

    async fn scan(&self, dir: &Entry, limits: Limits) -> Result<Scan, Error> {
        let base = self.key(&dir.path);
        let prefix = if base.is_empty() {
            String::new()
        } else {
            format!("{base}/")
        };
        let mut scan = Scan::default();
        let mut dirs = std::collections::BTreeSet::new();
        let mut token: Option<String> = None;
        for _ in 0..MAX_PAGES {
            let (page, next) = self.list_page(&prefix, token.as_deref(), 1000).await?;
            for c in &page {
                let Some(key) = c.text_of("Key") else {
                    continue;
                };
                let Some(path) = self.rel(key) else { continue };
                let is_dir = path.ends_with('/');
                let path = path.trim_end_matches('/');
                if path.is_empty() || path == dir.path || path.split('/').any(str::is_empty) {
                    // the folder's own marker, or a key with `//` (no tree path)
                    continue;
                }
                if limits.too_deep(&dir.path, path) {
                    // keep the folder at the deepest shown level
                    let rel_start = if dir.path.is_empty() {
                        0
                    } else {
                        dir.path.len() + 1
                    };
                    let shown: Vec<&str> = path[rel_start..]
                        .split('/')
                        .take(limits.max_depth)
                        .collect();
                    dirs.insert(join(&dir.path, &shown.join("/")));
                    scan.truncated = true;
                    continue;
                }
                if is_dir {
                    dirs.insert(path.to_owned());
                    continue;
                }
                if scan.entries.len() + dirs.len() >= limits.max_entries {
                    scan.truncated = true;
                    break;
                }
                let mut e = Entry::file(
                    path,
                    c.text_of("Size").and_then(|s| s.parse().ok()).unwrap_or(0),
                );
                e.modified = c.text_of("LastModified").and_then(parse_rfc3339);
                e.etag = c.text_of("ETag").map(|t| t.trim_matches('"').to_owned());
                scan.entries.push(e);
            }
            if scan.truncated && scan.entries.len() + dirs.len() >= limits.max_entries {
                break;
            }
            match next {
                Some(t) => token = Some(t),
                None => {
                    token = None;
                    break;
                }
            }
        }
        if token.is_some() {
            scan.truncated = true;
        }
        scan.entries.extend(dirs.into_iter().map(Entry::dir));
        Ok(scan)
    }

    async fn mkdir(&self, parent: &Entry, name: &str) -> Result<Entry, Error> {
        let path = join(&parent.path, name);
        let key = format!("{}/", self.key(&path));
        let r = self
            .send(
                Method::PUT,
                &key,
                &[],
                &[("if-none-match", "*")],
                Bytes::new(),
                MAX_LISTING,
            )
            .await?;
        if !r.ok() {
            return Err(Self::fail(&r, &format!("create folder {path}")));
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
            .send(
                Method::PUT,
                &self.key(&path),
                &[],
                &extra,
                data,
                MAX_LISTING,
            )
            .await?;
        if !r.ok() {
            return Err(Self::fail(&r, &format!("upload {path}")));
        }
        let mut e = Entry::file(path, len);
        e.modified = Some(wyrm_filestore::util::now_us());
        e.etag = r.header("etag").map(|t| t.trim_matches('"').to_owned());
        e.content_type = Some(content_type.to_owned());
        Ok(e)
    }

    async fn get_range(&self, file: &Entry, offset: u64, len: usize) -> Result<Bytes, Error> {
        let range = format!("bytes={offset}-{}", offset + len as u64 - 1);
        let r = self
            .send(
                Method::GET,
                &self.key(&file.path),
                &[],
                &[("range", &range)],
                Bytes::new(),
                len + 1024,
            )
            .await?;
        match r.status {
            206 => Ok(r.body),
            // a store that sends the whole file for a range: only when it is
            // that range
            200 if offset == 0 && r.body.len() <= len => Ok(r.body),
            200 => Err(Error::Refused(format!(
                "download {}: the store ignores Range",
                file.path
            ))),
            416 => Ok(Bytes::new()),
            _ => Err(Self::fail(&r, &format!("download {}", file.path))),
        }
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
        if size <= self.multipart {
            let data = read_part(src, 0, size).await?;
            return self.put(parent, name, data, content_type, existing).await;
        }
        let path = join(&parent.path, name);
        let key = self.key(&path);
        // at most 10 000 parts: a larger file takes larger parts
        let part = self
            .multipart
            .max(size.div_ceil(10_000).next_multiple_of(1024 * 1024));
        let upload = self.multipart_begin(&key, content_type).await?;
        match self
            .multipart_send(&key, &upload, src, size, part, existing.is_none())
            .await
        {
            Ok(etag) => {
                let mut e = Entry::file(path, size);
                e.modified = Some(wyrm_filestore::util::now_us());
                e.etag = etag;
                e.content_type = Some(content_type.to_owned());
                Ok(e)
            }
            Err(err) => {
                // the parts sent must not stay (they cost storage)
                let q = [("uploadId".to_owned(), upload)];
                let _ = self
                    .send(Method::DELETE, &key, &q, &[], Bytes::new(), MAX_LISTING)
                    .await;
                Err(err)
            }
        }
    }

    async fn get(&self, file: &Entry, max: usize) -> Result<Bytes, Error> {
        let r = self
            .send(
                Method::GET,
                &self.key(&file.path),
                &[],
                &[],
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
        let mut keys = if e.dir && !recursive {
            // the bucket says what is below, not the tree: two keys tell
            let base = format!("{}/", self.key(&e.path));
            let (page, _) = self.list_page(&base, None, 2).await?;
            if page.iter().any(|c| c.text_of("Key") != Some(base.as_str())) {
                return Err(not_empty(&e.path));
            }
            vec![base]
        } else if e.dir {
            let base = format!("{}/", self.key(&e.path));
            let mut k = self.keys_below(&base, MAX_DELETE).await?;
            if !k.contains(&base) {
                k.push(base);
            }
            k
        } else {
            vec![self.key(&e.path)]
        };
        // deepest first: a folder marker goes last
        keys.sort_by_key(|k| std::cmp::Reverse(k.len()));
        for k in keys {
            let r = self
                .send(Method::DELETE, &k, &[], &[], Bytes::new(), MAX_LISTING)
                .await?;
            if !r.ok() && r.status != 404 {
                return Err(Self::fail(&r, &format!("delete {k}")));
            }
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use wyrm_core::Value;
    use wyrm_link_sdk::driver::Params;

    fn params(kv: &[(&str, &str)]) -> Result<S3Store, LinkError> {
        let m = kv
            .iter()
            .map(|(k, v)| ((*k).to_owned(), Value::Str((*v).to_owned())))
            .collect();
        S3Store::new(&S3Params::from_value(&Value::Map(m))?)
    }

    #[test]
    fn addressing_and_rules() {
        let s = params(&[("bucket", "my-bucket")]).unwrap();
        assert!(s.virtual_host);
        assert_eq!(s.http.endpoint.host, "my-bucket.s3.amazonaws.com");
        assert_eq!(s.target("a b/c.txt"), "/a%20b/c.txt");
        let s = params(&[
            ("bucket", "b"),
            ("endpoint", "http://127.0.0.1:9000"),
            ("prefix", "/x/y/"),
        ])
        .unwrap();
        assert!(!s.virtual_host);
        assert_eq!(s.target(&s.key("f")), "/b/x/y/f");
        assert_eq!(s.rel("x/y/f"), Some("f"));
        assert_eq!(s.rel("x/yz"), None);
        assert!(params(&[("bucket", "")]).is_err());
        assert!(params(&[("bucket", "b"), ("prefix", "a//b")]).is_err());
        assert!(params(&[("bucket", "b"), ("access_key_id", "AK")]).is_err());
        assert!(params(&[
            ("bucket", "b"),
            ("endpoint", "http://10.0.0.5:9000"),
            ("access_key_id", "AK"),
            ("secret_access_key", "SK")
        ])
        .is_err());
        assert!(
            params(&[
                ("bucket", "b"),
                ("endpoint", "http://10.0.0.5:9000"),
                ("access_key_id", "AK"),
                ("secret_access_key", "SK"),
                ("insecure_plaintext", "x")
            ])
            .is_err(),
            "a bool param given as text is refused"
        );
    }
}
