//! Uploads in parts: a file larger than one request (the gateway takes
//! 64 MiB, the reference board has 2 GB of memory) goes to the link part by
//! part, in any order and again after a cut, into a spool file on the
//! link's disk. Once every part is there, a commit sends the spool file to
//! the store as it reads it ([`crate::Backend::put_file`]: S3 multipart,
//! Drive resumable, a streamed WebDAV `PUT`, a local copy) and removes it.
//!
//! An upload belongs to whoever began it (the `ptok` subject): only they
//! add parts, commit, abort or ask its state. An upload idle for
//! [`IDLE`] is dropped with its spool file; so is every upload of a
//! connection that stops, and every spool file left by an earlier start.

use crate::backend::{Entry, Error};
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, HashMap};
use std::io::{Read, Seek, SeekFrom, Write};
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::time::{Duration, Instant};
use wyrm_core::{Status, Value};
use wyrm_link_sdk::LinkError;

/// Part size when the caller names none.
pub const DEFAULT_PART: u64 = 4 * 1024 * 1024;
pub const MIN_PART: u64 = 64 * 1024;
/// Largest part: one request through the gateway, with room.
pub const MAX_PART: u64 = 16 * 1024 * 1024;
/// Uploads in progress per connection at most.
pub const MAX_UPLOADS: usize = 4;
/// An upload no one touched for this long is dropped.
pub const IDLE: Duration = Duration::from_secs(3600);
/// Parts a status answer lists as missing at most.
const MISSING_SHOWN: usize = 1000;

type Map = BTreeMap<String, Value>;

#[derive(Debug, Clone, PartialEq)]
pub enum State {
    Receiving,
    Committing,
    /// The answer of the commit (as Upload File's).
    Done(Value),
    Failed(String),
}

impl State {
    fn name(&self) -> &'static str {
        match self {
            State::Receiving => "receiving",
            State::Committing => "committing",
            State::Done(_) => "done",
            State::Failed(_) => "failed",
        }
    }
}

/// What a commit sends.
#[derive(Debug, Clone)]
pub struct Commit {
    pub id: String,
    pub parent: Entry,
    pub name: String,
    pub content_type: String,
    pub overwrite: bool,
    pub size: u64,
    pub file: PathBuf,
}

#[derive(Debug)]
struct Upload {
    owner: String,
    parent: Entry,
    name: String,
    content_type: String,
    overwrite: bool,
    size: u64,
    part: u64,
    got: Vec<bool>,
    sha256: Option<[u8; 32]>,
    file: PathBuf,
    touched: Instant,
    state: State,
}

impl Upload {
    fn parts(&self) -> u64 {
        self.got.len() as u64
    }

    /// Bytes of part `i`.
    fn part_len(&self, i: u64) -> u64 {
        let start = i * self.part;
        self.part.min(self.size - start)
    }
}

/// What [`Uploads::begin`] takes.
pub struct Begin {
    pub owner: String,
    pub parent: Entry,
    pub name: String,
    pub content_type: String,
    pub overwrite: bool,
    pub size: u64,
    pub part: Option<u64>,
    pub sha256: Option<String>,
}

fn bad(what: impl std::fmt::Display) -> LinkError {
    LinkError::invalid_parameter(what.to_string())
}

fn hex(b: &[u8]) -> String {
    b.iter().map(|x| format!("{x:02x}")).collect()
}

fn unhex(s: &str) -> Option<[u8; 32]> {
    let s = s.trim();
    if s.len() != 64 {
        return None;
    }
    let mut out = [0u8; 32];
    for (i, o) in out.iter_mut().enumerate() {
        *o = u8::from_str_radix(s.get(2 * i..2 * i + 2)?, 16).ok()?;
    }
    Some(out)
}

/// An id nobody can guess (std's per-process random hash keys, time, a
/// counter): it names a spool file and is checked with the owner.
pub(crate) fn new_id() -> String {
    use std::hash::{BuildHasher, Hasher};
    use std::sync::atomic::{AtomicU64, Ordering};
    static N: AtomicU64 = AtomicU64::new(0);
    static KEYS: std::sync::LazyLock<std::collections::hash_map::RandomState> =
        std::sync::LazyLock::new(Default::default);
    let mut out = String::new();
    for salt in 0..2u64 {
        let mut h = KEYS.build_hasher();
        h.write_u64(crate::util::now_us());
        h.write_u64(N.fetch_add(1, Ordering::Relaxed));
        h.write_u64(salt);
        out.push_str(&format!("{:016x}", h.finish()));
    }
    out
}

/// The uploads of one connection.
pub struct Uploads {
    dir: PathBuf,
    map: Mutex<HashMap<String, Upload>>,
}

fn lock<T>(m: &Mutex<T>) -> std::sync::MutexGuard<'_, T> {
    m.lock().unwrap_or_else(|e| e.into_inner())
}

/// Run `f` on the blocking pool.
async fn blocking<T: Send + 'static>(
    f: impl FnOnce() -> std::io::Result<T> + Send + 'static,
) -> Result<T, LinkError> {
    tokio::task::spawn_blocking(f)
        .await
        .map_err(|e| LinkError::internal(e.to_string()))?
        .map_err(|e| LinkError::new(Status::InternalError, format!("spool: {e}")))
}

impl Uploads {
    /// Uploads spooled below `dir` (made 0700; what an earlier start left
    /// there is removed).
    pub fn new(dir: PathBuf) -> Self {
        let _ = std::fs::remove_dir_all(&dir);
        Self {
            dir,
            map: Mutex::new(HashMap::new()),
        }
    }

    fn make_dir(&self) -> std::io::Result<()> {
        let mut b = std::fs::DirBuilder::new();
        b.recursive(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::DirBuilderExt;
            b.mode(0o700);
        }
        b.create(&self.dir)
    }

    /// Drop the uploads idle for [`IDLE`] (and finished ones as old).
    pub fn sweep(&self) {
        let gone: Vec<PathBuf> = {
            let mut m = lock(&self.map);
            let old: Vec<String> = m
                .iter()
                .filter(|(_, u)| u.touched.elapsed() > IDLE && u.state != State::Committing)
                .map(|(k, _)| k.clone())
                .collect();
            old.iter()
                .filter_map(|k| m.remove(k))
                .map(|u| u.file)
                .collect()
        };
        for f in gone {
            let _ = std::fs::remove_file(f);
        }
    }

    /// Drop every upload (the connection stops).
    pub fn clear(&self) {
        lock(&self.map).clear();
        let _ = std::fs::remove_dir_all(&self.dir);
    }

    /// Start an upload: its id, part size and number of parts.
    pub async fn begin(&self, b: Begin, max_size: u64) -> Result<Value, LinkError> {
        self.sweep();
        if b.size == 0 {
            return Err(bad("size: an empty file goes with Upload File"));
        }
        if b.size > max_size {
            return Err(LinkError::new(
                Status::OutOfRange,
                format!("size: {} bytes, at most {max_size} (max_file_mib)", b.size),
            ));
        }
        let part = b.part.unwrap_or(DEFAULT_PART);
        if !(MIN_PART..=MAX_PART).contains(&part) {
            return Err(bad(format!(
                "part_size: {MIN_PART} to {MAX_PART} bytes, not {part}"
            )));
        }
        let sha256 = match b.sha256.as_deref().map(str::trim) {
            None | Some("") => None,
            Some(s) => Some(unhex(s).ok_or_else(|| bad("sha256: 64 hex digits"))?),
        };
        let parts = b.size.div_ceil(part);
        let id = new_id();
        let file = self.dir.join(format!("{id}.part"));
        {
            let m = lock(&self.map);
            if m.values().filter(|u| u.state == State::Receiving).count() >= MAX_UPLOADS {
                return Err(LinkError::new(
                    Status::Busy,
                    format!("{MAX_UPLOADS} uploads are in progress: commit or abort one"),
                ));
            }
        }
        self.make_dir()
            .map_err(|e| LinkError::new(Status::InternalError, format!("spool: {e}")))?;
        let (f2, size) = (file.clone(), b.size);
        // a sparse file of the full size: parts land at their offsets
        blocking(move || {
            let f = std::fs::OpenOptions::new()
                .write(true)
                .create_new(true)
                .open(&f2)?;
            f.set_len(size)
        })
        .await?;
        let up = Upload {
            owner: b.owner,
            parent: b.parent,
            name: b.name,
            content_type: b.content_type,
            overwrite: b.overwrite,
            size: b.size,
            part,
            got: vec![false; parts as usize],
            sha256,
            file,
            touched: Instant::now(),
            state: State::Receiving,
        };
        lock(&self.map).insert(id.clone(), up);
        Ok(Value::Map(Map::from([
            ("upload".to_owned(), Value::Str(id)),
            ("part_size".to_owned(), Value::UInt(part)),
            ("parts".to_owned(), Value::UInt(parts)),
        ])))
    }

    /// The upload `id` of `owner`, touched.
    fn with<T>(
        &self,
        id: &str,
        owner: &str,
        f: impl FnOnce(&mut Upload) -> Result<T, LinkError>,
    ) -> Result<T, LinkError> {
        let mut m = lock(&self.map);
        match m.get_mut(id) {
            // another's upload answers as one that does not exist
            Some(u) if u.owner == owner => {
                u.touched = Instant::now();
                f(u)
            }
            _ => Err(LinkError::not_found(format!("upload {id}"))),
        }
    }

    /// Write part `index` (0-based). Sending a part again is fine.
    pub async fn part(
        &self,
        id: &str,
        owner: &str,
        index: u64,
        data: Vec<u8>,
    ) -> Result<Value, LinkError> {
        let (file, offset) = self.with(id, owner, |u| {
            if u.state != State::Receiving {
                return Err(bad(format!("upload {id} is {}", u.state.name())));
            }
            if index >= u.parts() {
                return Err(bad(format!("index: 0 to {}", u.parts() - 1)));
            }
            let want = u.part_len(index);
            if data.len() as u64 != want {
                return Err(bad(format!(
                    "part {index}: {} bytes, expected {want}",
                    data.len()
                )));
            }
            Ok((u.file.clone(), index * u.part))
        })?;
        blocking(move || {
            let mut f = std::fs::OpenOptions::new().write(true).open(&file)?;
            f.seek(SeekFrom::Start(offset))?;
            f.write_all(&data)
        })
        .await?;
        self.with(id, owner, |u| {
            u.got[index as usize] = true;
            let received = u.got.iter().filter(|g| **g).count() as u64;
            Ok(Value::Map(Map::from([
                ("received".to_owned(), Value::UInt(received)),
                ("parts".to_owned(), Value::UInt(u.parts())),
            ])))
        })
    }

    /// Where the upload stands.
    pub fn status(&self, id: &str, owner: &str) -> Result<Value, LinkError> {
        self.with(id, owner, |u| {
            let missing: Vec<Value> = u
                .got
                .iter()
                .enumerate()
                .filter(|(_, g)| !**g)
                .take(MISSING_SHOWN)
                .map(|(i, _)| Value::UInt(i as u64))
                .collect();
            let mut m = Map::from([
                ("state".to_owned(), Value::Str(u.state.name().into())),
                ("name".to_owned(), Value::Str(u.name.clone())),
                ("size".to_owned(), Value::UInt(u.size)),
                ("part_size".to_owned(), Value::UInt(u.part)),
                ("parts".to_owned(), Value::UInt(u.parts())),
                ("missing".to_owned(), Value::Array(missing)),
            ]);
            match &u.state {
                State::Done(v) => {
                    m.insert("result".to_owned(), v.clone());
                }
                State::Failed(e) => {
                    m.insert("error".to_owned(), Value::Str(e.clone()));
                }
                _ => {}
            }
            Ok(Value::Map(m))
        })
    }

    /// Mark the upload committing when every part is there.
    pub fn commit(&self, id: &str, owner: &str) -> Result<(Commit, Option<[u8; 32]>), LinkError> {
        self.with(id, owner, |u| {
            match &u.state {
                State::Receiving => {}
                State::Failed(_) => {} // a commit may be tried again
                s => return Err(bad(format!("upload {id} is {}", s.name()))),
            }
            if let Some(i) = u.got.iter().position(|g| !*g) {
                return Err(bad(format!("part {i} is missing (see upload_status)")));
            }
            u.state = State::Committing;
            Ok((
                Commit {
                    id: id.to_owned(),
                    parent: u.parent.clone(),
                    name: u.name.clone(),
                    content_type: u.content_type.clone(),
                    overwrite: u.overwrite,
                    size: u.size,
                    file: u.file.clone(),
                },
                u.sha256,
            ))
        })
    }

    /// The end of a commit: the spool file goes when it is done.
    pub fn finish(&self, id: &str, r: Result<Value, LinkError>) {
        let file = {
            let mut m = lock(&self.map);
            let Some(u) = m.get_mut(id) else { return };
            u.touched = Instant::now();
            match r {
                Ok(v) => {
                    u.state = State::Done(v);
                    Some(u.file.clone())
                }
                Err(e) => {
                    u.state = State::Failed(e.message);
                    None
                }
            }
        };
        if let Some(f) = file {
            let _ = std::fs::remove_file(f);
        }
    }

    pub fn abort(&self, id: &str, owner: &str) -> Result<(), LinkError> {
        self.with(id, owner, |u| {
            if u.state == State::Committing {
                return Err(bad(format!("upload {id} is committing")));
            }
            Ok(())
        })?;
        if let Some(u) = lock(&self.map).remove(id) {
            let _ = std::fs::remove_file(u.file);
        }
        Ok(())
    }
}

/// SHA-256 of a file, read in parts (on the blocking pool).
pub async fn file_sha256(path: &Path) -> Result<[u8; 32], Error> {
    let p = path.to_path_buf();
    tokio::task::spawn_blocking(move || -> std::io::Result<[u8; 32]> {
        let mut f = std::fs::File::open(&p)?;
        let mut h = Sha256::new();
        let mut buf = vec![0u8; 1024 * 1024];
        loop {
            let n = f.read(&mut buf)?;
            if n == 0 {
                break;
            }
            h.update(&buf[..n]);
        }
        Ok(h.finalize().into())
    })
    .await
    .map_err(|e| Error::Refused(e.to_string()))?
    .map_err(|e| Error::Refused(format!("spool: {e}")))
}

/// Hex of a digest (for errors and answers).
pub fn digest_hex(d: &[u8; 32]) -> String {
    hex(d)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn begin(size: u64, part: u64) -> Begin {
        Begin {
            owner: "user:a".into(),
            parent: Entry::root(None),
            name: "big.bin".into(),
            content_type: "application/octet-stream".into(),
            overwrite: false,
            size,
            part: Some(part),
            sha256: None,
        }
    }

    fn get(v: &Value, k: &str) -> Value {
        match v {
            Value::Map(m) => m.get(k).cloned().unwrap_or(Value::Null),
            _ => Value::Null,
        }
    }

    #[tokio::test]
    async fn parts_in_any_order_then_commit() {
        let dir = std::env::temp_dir().join(format!("wyrm-parts-{}", std::process::id()));
        let u = Uploads::new(dir.clone());
        let v = u.begin(begin(150_000, 65_536), 1 << 30).await.unwrap();
        let id = match get(&v, "upload") {
            Value::Str(s) => s,
            _ => panic!(),
        };
        assert_eq!(get(&v, "parts"), Value::UInt(3));
        let data: Vec<u8> = (0..150_000u32).map(|i| (i % 251) as u8).collect();
        for i in [2u64, 0, 1, 1] {
            let a = (i * 65_536) as usize;
            let b = (a + 65_536).min(data.len());
            u.part(&id, "user:a", i, data[a..b].to_vec()).await.unwrap();
        }
        // wrong size, out of range, another owner
        assert!(u.part(&id, "user:a", 0, vec![0; 10]).await.is_err());
        assert!(u.part(&id, "user:a", 3, vec![0; 10]).await.is_err());
        assert_eq!(
            u.part(&id, "user:b", 0, vec![0; 65_536])
                .await
                .unwrap_err()
                .status,
            Status::NotFound
        );
        let (c, _) = u.commit(&id, "user:a").unwrap();
        assert_eq!(std::fs::read(&c.file).unwrap(), data);
        assert!(
            u.part(&id, "user:a", 0, vec![0; 65_536]).await.is_err(),
            "committing"
        );
        u.finish(&id, Ok(Value::Null));
        assert!(!c.file.exists(), "spool removed");
        assert_eq!(
            get(&u.status(&id, "user:a").unwrap(), "state"),
            Value::Str("done".into())
        );
        u.clear();
        assert!(!dir.exists());
    }

    #[tokio::test]
    async fn limits() {
        let dir = std::env::temp_dir().join(format!("wyrm-parts-l-{}", std::process::id()));
        let u = Uploads::new(dir);
        assert!(u.begin(begin(100, 65_536), 50).await.is_err(), "over max");
        assert!(
            u.begin(begin(100, 1000), 1 << 20).await.is_err(),
            "part too small"
        );
        assert!(u.begin(begin(0, 65_536), 1 << 20).await.is_err(), "empty");
        let mut ids = Vec::new();
        for _ in 0..MAX_UPLOADS {
            ids.push(u.begin(begin(100, 65_536), 1 << 20).await.unwrap());
        }
        let e = u.begin(begin(100, 65_536), 1 << 20).await.unwrap_err();
        assert_eq!(e.status, Status::Busy);
        let id = match get(&ids[0], "upload") {
            Value::Str(s) => s,
            _ => panic!(),
        };
        assert!(u.commit(&id, "user:a").is_err(), "a part is missing");
        u.abort(&id, "user:a").unwrap();
        assert!(
            u.begin(begin(100, 65_536), 1 << 20).await.is_ok(),
            "room again"
        );
        let mut b = begin(100, 65_536);
        b.sha256 = Some("xyz".into());
        assert!(u.begin(b, 1 << 20).await.is_err());
        u.clear();
    }
}
