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
//! Spool files are removed on the blocking pool, never on a tokio worker.
//!
//! The spool's disk keeps [`SPOOL_RESERVE`] free: an upload whose bytes
//! not received yet do not fit in the rest is refused at begin and at
//! each part (`resource_exhausted`).

use crate::backend::{Entry, Error};
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, HashMap};
use std::io::{Read, Seek, SeekFrom, Write};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
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
/// Free space an upload must leave on the spool's disk.
pub const SPOOL_RESERVE: u64 = 1024 * 1024 * 1024;

/// Bytes free on the file system of a directory; `None` when unknown (the
/// check is then skipped).
pub type FreeSpace = Arc<dyn Fn(&Path) -> Option<u64> + Send + Sync>;

/// Bytes an unprivileged writer may still use on the file system of `dir`
/// (of its nearest existing parent while it does not exist); `None` off
/// Unix or when the system does not say.
pub fn disk_free(dir: &Path) -> Option<u64> {
    #[cfg(unix)]
    {
        let at = dir.ancestors().find(|p| p.exists())?;
        let v = nix::sys::statvfs::statvfs(at).ok()?;
        #[allow(clippy::unnecessary_cast)] // the types differ by platform
        let (blocks, size) = (v.blocks_available() as u64, v.fragment_size() as u64);
        Some(blocks.saturating_mul(size))
    }
    #[cfg(not(unix))]
    {
        let _ = dir;
        None
    }
}

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
    /// Bytes of the parts not received yet.
    missing: u64,
    sha256: Option<[u8; 32]>,
    file: PathBuf,
    touched: Instant,
    state: State,
}

impl Upload {
    fn parts(&self) -> u64 {
        self.got.len() as u64
    }

    /// Its spool file is still on disk (a done upload's is removed).
    fn holds_file(&self) -> bool {
        !matches!(self.state, State::Done(_))
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
    free: FreeSpace,
}

/// The removal of a connection's spool directory, on the blocking pool:
/// await it when what comes next must not find the old spool (or meet
/// the removal: an edit opens the same directory again).
#[must_use = "await it when the spool must be gone first"]
pub struct Cleanup(Option<tokio::task::JoinHandle<()>>);

impl Cleanup {
    pub async fn wait(self) {
        if let Some(h) = self.0 {
            let _ = h.await;
        }
    }
}

/// What goes from the spool.
enum Gone {
    Files(Vec<PathBuf>),
    Dir(PathBuf),
}

#[cfg(test)]
static REMOVED_ON: Mutex<Vec<(PathBuf, std::thread::ThreadId)>> = Mutex::new(Vec::new());

fn remove_now(g: Gone) {
    let paths = match g {
        Gone::Files(f) => f,
        Gone::Dir(d) => {
            let _ = std::fs::remove_dir_all(&d);
            #[cfg(test)]
            lock(&REMOVED_ON).push((d, std::thread::current().id()));
            return;
        }
    };
    for f in paths {
        let _ = std::fs::remove_file(&f);
        #[cfg(test)]
        lock(&REMOVED_ON).push((f, std::thread::current().id()));
    }
}

/// Remove on the blocking pool; here only without a runtime (a link
/// dropped outside one).
fn remove(g: Gone) -> Cleanup {
    if matches!(&g, Gone::Files(f) if f.is_empty()) {
        return Cleanup(None);
    }
    match tokio::runtime::Handle::try_current() {
        Ok(h) => Cleanup(Some(h.spawn_blocking(move || remove_now(g)))),
        Err(_) => {
            remove_now(g);
            Cleanup(None)
        }
    }
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
    /// Uploads spooled below `dir` (made 0700): what an earlier start left
    /// there is removed first, on the blocking pool.
    pub async fn open(dir: PathBuf) -> Self {
        remove(Gone::Dir(dir.clone())).wait().await;
        Self {
            dir,
            map: Mutex::new(HashMap::new()),
            free: Arc::new(disk_free),
        }
    }

    /// Ask `free` for the free space of the spool's disk instead of the
    /// system (tests: a small disk).
    pub fn with_free_space(mut self, free: FreeSpace) -> Self {
        self.free = free;
        self
    }

    /// `need` more bytes fit in the spool's disk with [`SPOOL_RESERVE`]
    /// left free (asked on the blocking pool: a mount may be slow).
    async fn room(&self, need: u64) -> Result<(), LinkError> {
        if need == 0 {
            return Ok(());
        }
        let (free, dir) = (self.free.clone(), self.dir.clone());
        let Ok(Some(have)) = tokio::task::spawn_blocking(move || free(&dir)).await else {
            return Ok(());
        };
        let room = have.saturating_sub(SPOOL_RESERVE);
        if need > room {
            return Err(LinkError::new(
                Status::ResourceExhausted,
                format!(
                    "the link's disk has room for {room} bytes ({} MiB stay free), {need} needed",
                    SPOOL_RESERVE / (1024 * 1024)
                ),
            ));
        }
        Ok(())
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
        // file names are unique: nothing waits for this removal
        drop(remove(Gone::Files(gone)));
    }

    /// Drop every upload (the connection stops); the spool directory is
    /// removed on the blocking pool.
    pub fn clear(&self) -> Cleanup {
        lock(&self.map).clear();
        remove(Gone::Dir(self.dir.clone()))
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
        self.room(b.size).await?;
        let id = new_id();
        let file = self.dir.join(format!("{id}.part"));
        let size = b.size;
        {
            // every upload that still holds a spool file counts (receiving,
            // committing, failed and kept for another commit), and the slot
            // is taken under the same lock: the spool stays within
            // MAX_UPLOADS files of at most max_file_mib each
            let mut m = lock(&self.map);
            if m.values().filter(|u| u.holds_file()).count() >= MAX_UPLOADS {
                return Err(LinkError::new(
                    Status::Busy,
                    format!("{MAX_UPLOADS} uploads are in progress: commit, or abort one"),
                ));
            }
            m.insert(
                id.clone(),
                Upload {
                    owner: b.owner,
                    parent: b.parent,
                    name: b.name,
                    content_type: b.content_type,
                    overwrite: b.overwrite,
                    size,
                    part,
                    got: vec![false; parts as usize],
                    missing: size,
                    sha256,
                    file: file.clone(),
                    touched: Instant::now(),
                    state: State::Receiving,
                },
            );
        }
        let made = match self.make_dir() {
            Ok(()) => {
                // a sparse file of the full size: parts land at their offsets
                let f2 = file.clone();
                blocking(move || {
                    let f = std::fs::OpenOptions::new()
                        .write(true)
                        .create_new(true)
                        .open(&f2)?;
                    // from here the file is ours
                    f.set_len(size).inspect_err(|_| {
                        drop(f);
                        let _ = std::fs::remove_file(&f2);
                    })
                })
                .await
            }
            Err(e) => Err(LinkError::new(Status::InternalError, format!("spool: {e}"))),
        };
        if let Err(e) = made {
            lock(&self.map).remove(&id);
            return Err(e);
        }
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
        let (file, offset, need) = self.with(id, owner, |u| {
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
            Ok((u.file.clone(), index * u.part, u.missing))
        })?;
        // what is still to come must fit (the spool file is sparse: a part
        // takes its space when it is written)
        self.room(need).await?;
        blocking(move || {
            let mut f = std::fs::OpenOptions::new().write(true).open(&file)?;
            f.seek(SeekFrom::Start(offset))?;
            f.write_all(&data)
        })
        .await?;
        self.with(id, owner, |u| {
            if !std::mem::replace(&mut u.got[index as usize], true) {
                u.missing -= u.part_len(index);
            }
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

    /// The end of a commit: the spool file goes when it is done (on the
    /// blocking pool, awaited).
    pub async fn finish(&self, id: &str, r: Result<Value, LinkError>) {
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
        remove(Gone::Files(file.into_iter().collect())).wait().await;
    }

    pub fn abort(&self, id: &str, owner: &str) -> Result<(), LinkError> {
        self.with(id, owner, |u| {
            if u.state == State::Committing {
                return Err(bad(format!("upload {id} is committing")));
            }
            Ok(())
        })?;
        let file = lock(&self.map).remove(id).map(|u| u.file);
        drop(remove(Gone::Files(file.into_iter().collect())));
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
        let u = Uploads::open(dir.clone()).await;
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
        u.finish(&id, Ok(Value::Null)).await;
        assert!(!c.file.exists(), "spool removed");
        assert_eq!(
            get(&u.status(&id, "user:a").unwrap(), "state"),
            Value::Str("done".into())
        );
        u.clear().wait().await;
        assert!(!dir.exists());
    }

    #[tokio::test]
    async fn limits() {
        let dir = std::env::temp_dir().join(format!("wyrm-parts-l-{}", std::process::id()));
        let u = Uploads::open(dir).await;
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
        u.clear().wait().await;
    }

    fn id_of(v: &Value) -> String {
        match get(v, "upload") {
            Value::Str(s) => s,
            _ => panic!("no upload id"),
        }
    }

    /// Every upload that still holds a spool file counts: one committing,
    /// and one whose commit failed (a wrong sha256 makes one at will), so
    /// the spool stays within `MAX_UPLOADS` files of `max_file_mib`.
    #[tokio::test]
    async fn spool_files_are_bounded() {
        let dir = std::env::temp_dir().join(format!("wyrm-parts-b-{}", std::process::id()));
        let u = Uploads::open(dir).await;
        let mut ids = Vec::new();
        for _ in 0..MAX_UPLOADS {
            let id = id_of(&u.begin(begin(100, 65_536), 1 << 20).await.unwrap());
            u.part(&id, "user:a", 0, vec![7; 100]).await.unwrap();
            u.commit(&id, "user:a").unwrap();
            ids.push(id);
        }
        let e = u.begin(begin(100, 65_536), 1 << 20).await.unwrap_err();
        assert_eq!(e.status, Status::Busy, "committing ones hold their files");
        u.finish(&ids[0], Err(LinkError::invalid_parameter("sha256")))
            .await;
        let e = u.begin(begin(100, 65_536), 1 << 20).await.unwrap_err();
        assert_eq!(e.status, Status::Busy, "a failed one keeps its file");
        u.abort(&ids[0], "user:a").unwrap();
        assert!(u.begin(begin(100, 65_536), 1 << 20).await.is_ok());
        u.finish(&ids[1], Ok(Value::Null)).await;
        assert!(
            u.begin(begin(100, 65_536), 1 << 20).await.is_ok(),
            "a done one holds no file"
        );
        u.clear().wait().await;
    }

    /// Begins at once cannot pass the count together.
    #[tokio::test(flavor = "multi_thread", worker_threads = 4)]
    async fn concurrent_begins_are_bounded() {
        let dir = std::env::temp_dir().join(format!("wyrm-parts-c-{}", std::process::id()));
        let u = std::sync::Arc::new(Uploads::open(dir).await);
        let tasks: Vec<_> = (0..4 * MAX_UPLOADS)
            .map(|_| {
                let u = u.clone();
                tokio::spawn(async move { u.begin(begin(100, 65_536), 1 << 20).await.is_ok() })
            })
            .collect();
        let mut ok = 0;
        for t in tasks {
            ok += usize::from(t.await.unwrap());
        }
        assert_eq!(ok, MAX_UPLOADS);
        u.clear().wait().await;
    }

    /// The spool's disk keeps `SPOOL_RESERVE` free: a file whose bytes do
    /// not fit in the rest is refused at begin, and a part when what is
    /// still to come no longer fits (another upload took the space).
    #[tokio::test]
    async fn free_space_bounds_uploads() {
        use std::sync::atomic::{AtomicU64, Ordering};
        let dir = std::env::temp_dir().join(format!("wyrm-parts-f-{}", std::process::id()));
        let free = Arc::new(AtomicU64::new(SPOOL_RESERVE + 300_000));
        let f2 = free.clone();
        let u = Uploads::open(dir)
            .await
            .with_free_space(Arc::new(move |_| Some(f2.load(Ordering::Relaxed))));
        let e = u.begin(begin(400_000, 65_536), 1 << 30).await.unwrap_err();
        assert_eq!(e.status, Status::ResourceExhausted, "{}", e.message);
        let id = id_of(&u.begin(begin(196_608, 65_536), 1 << 30).await.unwrap());
        u.part(&id, "user:a", 0, vec![1; 65_536]).await.unwrap();
        // 131 072 bytes still to come, 100 000 of room
        free.store(SPOOL_RESERVE + 100_000, Ordering::Relaxed);
        let e = u.part(&id, "user:a", 1, vec![1; 65_536]).await.unwrap_err();
        assert_eq!(e.status, Status::ResourceExhausted);
        free.store(SPOOL_RESERVE + 131_072, Ordering::Relaxed);
        u.part(&id, "user:a", 1, vec![1; 65_536]).await.unwrap();
        u.part(&id, "user:a", 2, vec![1; 65_536]).await.unwrap();
        // all in: sending a part again needs no room
        free.store(0, Ordering::Relaxed);
        u.part(&id, "user:a", 0, vec![2; 65_536]).await.unwrap();
        assert!(u.commit(&id, "user:a").is_ok());
        // a disk that does not say: no check
        free.store(0, Ordering::Relaxed);
        let u = u.with_free_space(Arc::new(|_| None));
        assert!(u.begin(begin(400_000, 65_536), 1 << 30).await.is_ok());
        u.clear().wait().await;
    }

    #[test]
    fn disk_free_of_a_missing_dir_is_its_parents() {
        let d = std::env::temp_dir().join("wyrm-no-such-dir").join("below");
        if cfg!(unix) {
            assert!(disk_free(&d).is_some_and(|n| n > 0));
        }
    }

    /// Spool files and directories are removed on the blocking pool, not
    /// on the runtime's thread: on start, at abort, at an idle sweep and
    /// when the connection stops.
    #[tokio::test(flavor = "current_thread")]
    async fn cleanup_runs_on_the_blocking_pool() {
        let dir = std::env::temp_dir().join(format!("wyrm-parts-p-{}", std::process::id()));
        let me = std::thread::current().id();
        let u = Uploads::open(dir.clone()).await;
        let id = id_of(&u.begin(begin(100, 65_536), 1 << 20).await.unwrap());
        let file = dir.join(format!("{id}.part"));
        assert!(file.exists());
        u.abort(&id, "user:a").unwrap();
        wait_removed(&file).await;
        let id = id_of(&u.begin(begin(100, 65_536), 1 << 20).await.unwrap());
        lock(&u.map).get_mut(&id).unwrap().touched = Instant::now() - IDLE - IDLE;
        let idle = dir.join(format!("{id}.part"));
        u.sweep();
        wait_removed(&idle).await;
        u.clear().wait().await;
        assert!(!dir.exists());
        let seen: Vec<_> = lock(&REMOVED_ON)
            .iter()
            .filter(|(p, _)| p.starts_with(&dir))
            .cloned()
            .collect();
        for p in [&dir, &file, &idle] {
            assert!(seen.iter().any(|(q, _)| q == p), "{p:?} removed: {seen:?}");
        }
        assert!(seen.iter().all(|(_, t)| *t != me), "{seen:?}");
    }

    async fn wait_removed(p: &Path) {
        for _ in 0..500 {
            if lock(&REMOVED_ON).iter().any(|(q, _)| q == p) {
                assert!(!p.exists());
                return;
            }
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
        panic!("{p:?} not removed");
    }
}
