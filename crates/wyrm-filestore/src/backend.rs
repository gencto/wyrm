//! What a store does: the [`Backend`] contract each link implements, the
//! [`Entry`] of a file or folder, and the [`Error`] classes that decide
//! whether the connection fails.

use bytes::Bytes;
use std::future::Future;
use std::time::Duration;
use wyrm_core::Status;
use wyrm_link_sdk::driver::Params;
use wyrm_link_sdk::LinkError;

/// A file or folder of a store.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct Entry {
    /// Below the connection's root: `/`-joined names, no leading or
    /// trailing `/`; `""` is the root. Unique in a scan: a backend whose
    /// store allows two children of one name (Google Drive) makes them
    /// unique here, and keeps the real name in [`Entry::name`].
    pub path: String,
    /// The name people see.
    pub name: String,
    pub dir: bool,
    /// Bytes (files).
    pub size: Option<u64>,
    /// Last change, microseconds since the epoch.
    pub modified: Option<u64>,
    pub etag: Option<String>,
    pub content_type: Option<String>,
    /// The store's own id where paths do not address (Google Drive).
    pub id: Option<String>,
}

impl Entry {
    /// The root folder, with the store's id of it.
    pub fn root(id: Option<String>) -> Self {
        Self {
            dir: true,
            id,
            ..Self::default()
        }
    }

    pub fn dir(path: impl Into<String>) -> Self {
        let path = path.into();
        Self {
            name: last_name(&path).to_owned(),
            path,
            dir: true,
            ..Self::default()
        }
    }

    pub fn file(path: impl Into<String>, size: u64) -> Self {
        let path = path.into();
        Self {
            name: last_name(&path).to_owned(),
            path,
            size: Some(size),
            ..Self::default()
        }
    }

    /// The parent's path (`None` for the root).
    pub fn parent(&self) -> Option<&str> {
        parent_of(&self.path)
    }
}

/// The last name of a path.
pub fn last_name(path: &str) -> &str {
    path.rsplit_once('/').map_or(path, |(_, n)| n)
}

/// The parent of `path` (`""` for a top-level one, `None` for the root).
pub fn parent_of(path: &str) -> Option<&str> {
    if path.is_empty() {
        None
    } else {
        Some(path.rsplit_once('/').map_or("", |(p, _)| p))
    }
}

/// `parent/name` (`name` at the root).
pub fn join(parent: &str, name: &str) -> String {
    if parent.is_empty() {
        name.to_owned()
    } else {
        format!("{parent}/{name}")
    }
}

/// `true` when `path` is `dir` or below it.
pub fn under(path: &str, dir: &str) -> bool {
    dir.is_empty()
        || path == dir
        || (path.len() > dir.len() && path.starts_with(dir) && path.as_bytes()[dir.len()] == b'/')
}

/// Bounds of one scan.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Limits {
    /// Entries in all, folders included.
    pub max_entries: usize,
    /// Folder levels below the scanned folder.
    pub max_depth: usize,
}

impl Limits {
    /// `true` when `path` (below `dir`) is deeper than allowed.
    pub fn too_deep(&self, dir: &str, path: &str) -> bool {
        let rel = if dir.is_empty() {
            path
        } else {
            path.get(dir.len() + 1..).unwrap_or("")
        };
        rel.split('/').count() > self.max_depth
    }
}

/// The entries below a folder.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Scan {
    /// Every file and folder below the scanned folder (not itself), at
    /// most [`Limits::max_entries`], within [`Limits::max_depth`].
    pub entries: Vec<Entry>,
    /// Some were left out (a limit was reached).
    pub truncated: bool,
}

/// Why a store request failed.
#[derive(Debug, Clone, PartialEq)]
pub enum Error {
    /// The store cannot be reached (connect, TLS, 5xx on the probe): the
    /// connection fails and reconnects.
    Unreachable(String),
    /// Credentials refused (401/403 on the probe, token refused): the
    /// connection fails.
    Auth(String),
    /// No reply in time: the connection fails when it was the probe.
    Timeout(String),
    NotFound(String),
    /// A name already taken.
    Exists(String),
    /// The store refused the request (permission on one object, a bad
    /// name, quota).
    Refused(String),
    TooLarge(String),
}

impl Error {
    /// The connection is not usable (as opposed to one request failing).
    pub fn breaks(&self) -> bool {
        matches!(
            self,
            Error::Unreachable(_) | Error::Auth(_) | Error::Timeout(_)
        )
    }

    pub fn message(&self) -> &str {
        match self {
            Error::Unreachable(m)
            | Error::Auth(m)
            | Error::Timeout(m)
            | Error::NotFound(m)
            | Error::Exists(m)
            | Error::Refused(m)
            | Error::TooLarge(m) => m,
        }
    }
}

impl std::fmt::Display for Error {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.message())
    }
}

impl From<Error> for LinkError {
    fn from(e: Error) -> Self {
        let status = match &e {
            Error::Unreachable(_) => Status::Disconnected,
            Error::Auth(_) => Status::PermissionDenied,
            Error::Timeout(_) => Status::Timeout,
            Error::NotFound(_) => Status::NotFound,
            Error::Exists(_) => Status::InvalidParameter,
            Error::Refused(_) => Status::InvalidParameter,
            Error::TooLarge(_) => Status::OutOfRange,
        };
        LinkError::new(status, e.message().to_owned())
    }
}

impl From<crate::http::HttpError> for Error {
    fn from(e: crate::http::HttpError) -> Self {
        use crate::http::HttpError;
        match e {
            HttpError::Connect(m) => Error::Unreachable(m),
            HttpError::Timeout(m) => Error::Timeout(m),
            HttpError::TooBig(m) => Error::TooLarge(m),
        }
    }
}

/// The class of an HTTP error status on a request that is not the probe:
/// 401 and 403 are refusals of this object, not of the credentials (the
/// probe tells those apart).
pub fn status_error(status: u16, what: &str, detail: &str) -> Error {
    let msg = if detail.is_empty() {
        format!("{what}: HTTP {status}")
    } else {
        format!("{what}: HTTP {status} {detail}")
    };
    match status {
        404 => Error::NotFound(msg),
        409 | 412 => Error::Exists(msg),
        413 => Error::TooLarge(msg),
        500..=599 => Error::Unreachable(msg),
        _ => Error::Refused(msg),
    }
}

/// A store. One value per running connection, shared by its tasks: every
/// method takes `&self`, and requests of one connection may run at once.
pub trait Backend: Sized + Send + Sync + 'static {
    /// The link's driver name (`s3`): a key segment.
    const NAME: &'static str;
    const VERSION: &'static str;
    /// A connection for people (`"S3 Bucket"`): `Add <DISPLAY>`.
    const DISPLAY: &'static str;
    /// The connection params (destination, credentials as `secret`).
    type Params: Params;

    /// Build the client from checked params (no I/O). An error refuses
    /// the params (cross-field rules).
    fn new(p: &Self::Params) -> Result<Self, LinkError>;

    /// Bound on one request (and on the probe).
    fn timeout(&self) -> Duration;

    /// The connection's root folder.
    fn root(&self) -> Entry;

    /// Probe: the store answers and takes the credentials (the bucket,
    /// drive or folder exists). Its errors are those of the connection.
    fn check(&self) -> impl Future<Output = Result<(), Error>> + Send;

    /// Every entry below `dir` (a folder from a scan, or [`Backend::root`]).
    fn scan(&self, dir: &Entry, limits: Limits)
        -> impl Future<Output = Result<Scan, Error>> + Send;

    /// Create the folder `name` in `parent`; the new entry.
    fn mkdir(
        &self,
        parent: &Entry,
        name: &str,
    ) -> impl Future<Output = Result<Entry, Error>> + Send;

    /// Store `data` as the file `name` in `parent`, replacing `existing`
    /// (the file of that name the tree knows, if any); the new entry.
    fn put(
        &self,
        parent: &Entry,
        name: &str,
        data: Bytes,
        content_type: &str,
        existing: Option<&Entry>,
    ) -> impl Future<Output = Result<Entry, Error>> + Send;

    /// The content of the file `file`, at most `max` bytes (more is
    /// [`Error::TooLarge`]).
    fn get(&self, file: &Entry, max: usize) -> impl Future<Output = Result<Bytes, Error>> + Send;

    /// Delete `e`. A folder with `recursive` goes with everything in it
    /// (`below` are the entries the tree knows under it; a store without
    /// folders lists its keys again, the tree may miss some). Without
    /// `recursive` the backend asks the store itself whether the folder
    /// is empty (the tree misses hidden names, levels below `max_depth`,
    /// entries over `max_entries`, files added since the last read) and
    /// answers [`not_empty`] when it is not.
    fn delete(
        &self,
        e: &Entry,
        below: &[Entry],
        recursive: bool,
    ) -> impl Future<Output = Result<(), Error>> + Send;

    /// Bootstrap params of the link beside `connections` (set by the
    /// broker's admin in `sys/links`, never by `add_connection`), checked
    /// as these params; `localfs`: `allowed_roots`.
    fn link_options() -> Vec<wyrm_link_sdk::driver::ParamSpec> {
        Vec::new()
    }

    /// Refuse a connection that would reach what it must not: called with
    /// the link's `data_dir` and its [`Backend::link_options`] when a
    /// connection is added, edited or started, and before every probe
    /// (a local directory must not overlap the broker's data, and must be
    /// below an allowed root). It may touch the store (resolve paths): a
    /// backend bounds it as its other calls.
    fn check_place(
        &self,
        _data_dir: Option<&std::path::Path>,
        _options: &std::collections::BTreeMap<String, wyrm_core::Value>,
    ) -> impl Future<Output = Result<(), LinkError>> + Send {
        async { Ok(()) }
    }
}

/// The answer to a delete of a folder that is not empty without
/// `recursive`.
pub fn not_empty(path: &str) -> Error {
    Error::Refused(format!("{path}: the folder is not empty: set recursive"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn paths() {
        assert_eq!(parent_of(""), None);
        assert_eq!(parent_of("a"), Some(""));
        assert_eq!(parent_of("a/b/c"), Some("a/b"));
        assert_eq!(last_name("a/b/c"), "c");
        assert_eq!(join("", "a"), "a");
        assert_eq!(join("a", "b"), "a/b");
        assert!(under("a/b", "a"));
        assert!(under("a", "a"));
        assert!(under("x", ""));
        assert!(!under("ab", "a"));
        let l = Limits {
            max_entries: 10,
            max_depth: 2,
        };
        assert!(!l.too_deep("", "a/b"));
        assert!(l.too_deep("", "a/b/c"));
        assert!(!l.too_deep("a", "a/b/c"));
    }
}
