//! Control-plane state of the broker (ADR 0003): an append-only WAL of
//! operations plus a snapshot cache.
//!
//! ```text
//! <dir>/wal.<first_lsn>.wyw       records: len u32 | crc32c u32 | hmac [32] | cbor(op)
//! <dir>/snapshot.<lsn>.wys        "WYS1" | schema u32 | lsn u64 | chain [32] | len u64 | postcard(state) | crc32c u32 | hmac [32]
//! <dir>/CURRENT                   name of the newest valid snapshot
//! ```
//!
//! * `hmac_n = HMAC-SHA256(key, hmac_{n-1} || lsn_le || cbor(op))`, starting
//!   from 32 zero bytes: removing, reordering or editing a record breaks the chain.
//! * A record cut off at the end of the last segment (power loss) is dropped
//!   and the file truncated. A CRC-valid record with a wrong HMAC is tampering.
//! * Every append is `fsync`ed. The WAL is the source of truth and is never
//!   deleted; the snapshot is only a cache. A snapshot with another
//!   [`State::SCHEMA`] is ignored and the state is rebuilt from the WAL.

#![forbid(unsafe_code)]

use hmac::{Hmac, Mac};
use serde::{de::DeserializeOwned, Serialize};
use sha2::Sha256;
use std::fs::{self, File, OpenOptions};
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use tracing::{info, warn};

const MAGIC: &[u8; 4] = b"WYS1";
const HEADER: usize = 4 + 4 + 32; // len, crc, hmac
/// Snapshot after this many WAL records (wiki: N = 1000).
pub const SNAPSHOT_EVERY: usize = 1000;
/// Upper bound on one record; larger is corruption, not data.
const MAX_RECORD: usize = 16 << 20;

type HmacSha256 = Hmac<Sha256>;

#[derive(Debug, thiserror::Error)]
pub enum StateError {
    #[error("io: {0}")]
    Io(#[from] std::io::Error),
    #[error("WAL record {lsn} in {file}: HMAC chain broken (tampered or wrong key)")]
    Tampered { lsn: u64, file: String },
    #[error("WAL {file} corrupt at offset {offset}: {why}")]
    Corrupt {
        file: String,
        offset: u64,
        why: String,
    },
    #[error("operation rejected: {0}")]
    Rejected(String),
    #[error("codec: {0}")]
    Codec(String),
    #[error("{0} is in use by another process")]
    InUse(String),
    #[error("anchor {anchor}: {why} (WAL truncated or replaced?)")]
    Anchor { anchor: String, why: String },
}

pub type Result<T, E = StateError> = core::result::Result<T, E>;

/// A state machine whose operations go through the WAL.
pub trait State: Clone + Default + Serialize + DeserializeOwned {
    /// Snapshot layout version; a mismatch rebuilds the state from the WAL.
    const SCHEMA: u32;
    type Op: minicbor::Encode<()> + for<'b> minicbor::Decode<'b, ()>;
    /// Validate and apply. `Err` leaves `self` unchanged in the store (the
    /// store applies to a clone first).
    fn apply(&mut self, op: &Self::Op) -> Result<(), String>;
}

pub struct Store<S: State> {
    dir: PathBuf,
    key: Vec<u8>,
    state: S,
    lsn: u64,
    chain: [u8; 32],
    wal: File,
    /// Exclusive lock on `dir/LOCK` for the life of the store: one writer
    /// per WAL (a second process would interleave records).
    _lock: File,
    /// Head record (`<lsn> <hex mac>`) kept outside the store directory.
    anchor: Option<PathBuf>,
    /// The last anchor write failed: no new record until it succeeds.
    anchor_stale: bool,
    since_snapshot: usize,
    snapshot_every: usize,
}

fn mac(key: &[u8], prev: &[u8; 32], lsn: u64, payload: &[u8]) -> [u8; 32] {
    let mut m = HmacSha256::new_from_slice(key).expect("HMAC takes any key length");
    m.update(prev);
    m.update(&lsn.to_le_bytes());
    m.update(payload);
    m.finalize().into_bytes().into()
}

fn segment_name(first_lsn: u64) -> String {
    format!("wal.{first_lsn:020}.wyw")
}

fn snapshot_name(lsn: u64) -> String {
    format!("snapshot.{lsn:020}.wys")
}

/// `fsync` the directory so new or renamed entries survive power loss.
fn hex_of(b: &[u8]) -> String {
    b.iter().map(|x| format!("{x:02x}")).collect()
}

fn sync_dir(dir: &Path) -> Result<()> {
    #[cfg(unix)]
    File::open(dir)?.sync_all()?;
    let _ = dir;
    Ok(())
}

fn segments(dir: &Path) -> Result<Vec<(u64, PathBuf)>> {
    let mut out = Vec::new();
    for e in fs::read_dir(dir)? {
        let p = e?.path();
        let name = p.file_name().and_then(|n| n.to_str()).unwrap_or_default();
        if let Some(n) = name
            .strip_prefix("wal.")
            .and_then(|n| n.strip_suffix(".wyw"))
        {
            if let Ok(first) = n.parse::<u64>() {
                out.push((first, p));
            }
        }
    }
    out.sort();
    Ok(out)
}

impl<S: State> Store<S> {
    /// Open (or create) the store in `dir` with the HMAC `key`.
    pub fn open(dir: impl AsRef<Path>, key: &[u8]) -> Result<Self> {
        let dir = dir.as_ref().to_path_buf();
        fs::create_dir_all(&dir)?;
        let lock = OpenOptions::new()
            .create(true)
            .truncate(false)
            .write(true)
            .open(dir.join("LOCK"))?;
        match lock.try_lock() {
            Ok(()) => {}
            Err(std::fs::TryLockError::WouldBlock) => {
                return Err(StateError::InUse(dir.display().to_string()))
            }
            Err(std::fs::TryLockError::Error(e)) => return Err(e.into()),
        }
        let (mut state, mut lsn, mut chain) = Self::load_snapshot(&dir, key).unwrap_or_default();
        let snap_lsn = lsn;
        let segs = segments(&dir)?;
        let last_idx = segs.len().checked_sub(1);
        let mut replayed = 0usize;
        // All segments are read: the chain is verified from the first record.
        let mut prev = [0u8; 32];
        for (i, (_, path)) in segs.iter().enumerate() {
            let is_last = Some(i) == last_idx;
            Self::replay(
                path,
                key,
                is_last,
                &mut prev,
                &mut |rec_lsn, rec_mac, op| {
                    // Records up to the snapshot are only chain-checked.
                    if rec_lsn <= snap_lsn {
                        if rec_lsn == snap_lsn && rec_mac != chain {
                            return Err(format!("chain at snapshot lsn {snap_lsn} does not match"));
                        }
                        return Ok(());
                    }
                    if rec_lsn != lsn + 1 {
                        return Err(format!("expected lsn {}, found {rec_lsn}", lsn + 1));
                    }
                    state
                        .apply(&op)
                        .map_err(|e| format!("replay of lsn {rec_lsn} rejected: {e}"))?;
                    lsn = rec_lsn;
                    chain = rec_mac;
                    replayed += 1;
                    Ok(())
                },
            )?;
        }
        // Continue the last segment, or start the first one.
        let path = match segs.last() {
            Some((_, p)) => p.clone(),
            None => {
                let p = dir.join(segment_name(1));
                File::create(&p)?;
                sync_dir(&dir)?;
                p
            }
        };
        let wal = OpenOptions::new().append(true).open(&path)?;
        info!(dir = %dir.display(), lsn, replayed, "state opened");
        Ok(Self {
            dir,
            key: key.to_vec(),
            state,
            lsn,
            chain,
            wal,
            _lock: lock,
            anchor: None,
            anchor_stale: false,
            since_snapshot: replayed,
            snapshot_every: SNAPSHOT_EVERY,
        })
    }

    /// Keep the head (LSN and chain MAC) in `path`, on another medium than
    /// the store. The HMAC chain finds edited records but not records cut
    /// from the end; the anchor does. On open: an anchor ahead of the WAL,
    /// or the same LSN with another MAC, is an error; an anchor one record
    /// behind (crash between the WAL write and the anchor write) is accepted.
    pub fn with_anchor(mut self, path: impl Into<PathBuf>) -> Result<Self> {
        let path = path.into();
        let bad = |why: String| StateError::Anchor {
            anchor: path.display().to_string(),
            why,
        };
        match fs::read_to_string(&path) {
            // A store with records and no anchor: the anchor may have been
            // deleted together with a cut. Only `init_anchor` creates one.
            Err(e) if e.kind() == std::io::ErrorKind::NotFound && self.lsn > 0 => {
                return Err(bad(format!(
                    "missing, but the WAL has {} records (create it with init_anchor)",
                    self.lsn
                )));
            }
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
            Err(e) => return Err(e.into()),
            Ok(text) => {
                let mut it = text.split_whitespace();
                let lsn: u64 = it
                    .next()
                    .and_then(|v| v.parse().ok())
                    .ok_or_else(|| bad("unreadable".into()))?;
                let mac_hex = it.next().unwrap_or_default();
                if lsn > self.lsn {
                    return Err(bad(format!(
                        "anchor is at lsn {lsn}, the WAL ends at {}",
                        self.lsn
                    )));
                }
                if lsn == self.lsn && mac_hex != hex_of(&self.chain) {
                    return Err(bad(format!("chain at lsn {lsn} differs")));
                }
                if lsn + 1 < self.lsn {
                    return Err(bad(format!(
                        "anchor is at lsn {lsn}, {} records behind the WAL",
                        self.lsn - lsn
                    )));
                }
            }
        }
        self.anchor = Some(path);
        self.write_anchor()?;
        Ok(self)
    }

    /// Create or replace the anchor with the current head: an explicit
    /// operator step for an existing store (e.g. `wyrmd init-anchors`).
    pub fn init_anchor(mut self, path: impl Into<PathBuf>) -> Result<Self> {
        self.anchor = Some(path.into());
        self.write_anchor()?;
        Ok(self)
    }

    fn write_anchor(&self) -> Result<()> {
        let Some(path) = &self.anchor else {
            return Ok(());
        };
        let tmp = path.with_extension("tmp");
        let mut f = File::create(&tmp)?;
        f.write_all(format!("{} {}\n", self.lsn, hex_of(&self.chain)).as_bytes())?;
        f.sync_all()?;
        fs::rename(&tmp, path)?;
        if let Some(dir) = path.parent() {
            sync_dir(dir)?;
        }
        Ok(())
    }

    /// Test hook: snapshot more often.
    pub fn with_snapshot_every(mut self, n: usize) -> Self {
        self.snapshot_every = n.max(1);
        self
    }

    pub fn state(&self) -> &S {
        &self.state
    }

    /// LSN of the last applied operation (0 = empty).
    pub fn lsn(&self) -> u64 {
        self.lsn
    }

    /// Validate `op` on a copy, append it durably, then make it current.
    pub fn apply(&mut self, op: S::Op) -> Result<u64> {
        if self.anchor_stale {
            // Catch up first; while the anchor cannot be written, refuse.
            self.write_anchor()?;
            self.anchor_stale = false;
        }
        let mut next = self.state.clone();
        next.apply(&op).map_err(StateError::Rejected)?;
        let payload = minicbor::to_vec(&op).map_err(|e| StateError::Codec(e.to_string()))?;
        let lsn = self.lsn + 1;
        let m = mac(&self.key, &self.chain, lsn, &payload);
        let mut rec = Vec::with_capacity(HEADER + payload.len());
        rec.extend((payload.len() as u32).to_le_bytes());
        rec.extend(crc32c::crc32c(&payload).to_le_bytes());
        rec.extend(m);
        rec.extend(&payload);
        self.wal.write_all(&rec)?;
        self.wal.sync_data()?;
        self.state = next;
        self.lsn = lsn;
        self.chain = m;
        if let Err(e) = self.write_anchor() {
            // The record is durable (the anchor is one behind, which open
            // tolerates), but nothing more is written until it catches up.
            self.anchor_stale = true;
            return Err(e);
        }
        self.since_snapshot += 1;
        if self.since_snapshot >= self.snapshot_every {
            if let Err(e) = self.snapshot() {
                warn!("snapshot failed (WAL still holds the truth): {e}");
            }
        }
        Ok(lsn)
    }

    /// Write a snapshot at the current LSN and start a new WAL segment.
    pub fn snapshot(&mut self) -> Result<()> {
        let body =
            postcard::to_stdvec(&self.state).map_err(|e| StateError::Codec(e.to_string()))?;
        let mut buf = Vec::with_capacity(body.len() + 100);
        buf.extend(MAGIC);
        buf.extend(S::SCHEMA.to_le_bytes());
        buf.extend(self.lsn.to_le_bytes());
        buf.extend(self.chain);
        buf.extend((body.len() as u64).to_le_bytes());
        buf.extend(&body);
        let crc = crc32c::crc32c(&buf);
        buf.extend(crc.to_le_bytes());
        let mut m = HmacSha256::new_from_slice(&self.key).expect("any key length");
        m.update(&buf);
        buf.extend(m.finalize().into_bytes());

        let name = snapshot_name(self.lsn);
        let tmp = self.dir.join(format!("{name}.tmp"));
        {
            let mut f = File::create(&tmp)?;
            f.write_all(&buf)?;
            f.sync_all()?;
        }
        fs::rename(&tmp, self.dir.join(&name))?;
        let cur_tmp = self.dir.join("CURRENT.tmp");
        {
            let mut f = File::create(&cur_tmp)?;
            f.write_all(name.as_bytes())?;
            f.sync_all()?;
        }
        fs::rename(&cur_tmp, self.dir.join("CURRENT"))?;
        // New segment: records after this snapshot.
        let seg = self.dir.join(segment_name(self.lsn + 1));
        self.wal = OpenOptions::new().create(true).append(true).open(&seg)?;
        sync_dir(&self.dir)?;
        self.since_snapshot = 0;
        Ok(())
    }

    fn load_snapshot(dir: &Path, key: &[u8]) -> Option<(S, u64, [u8; 32])> {
        let name = fs::read_to_string(dir.join("CURRENT")).ok()?;
        let buf = fs::read(dir.join(name.trim())).ok()?;
        let parsed = (|| {
            if buf.len() < 4 + 4 + 8 + 32 + 8 + 4 + 32 || &buf[..4] != MAGIC {
                return Err("bad header".to_owned());
            }
            let (signed, tag) = buf.split_at(buf.len() - 32);
            let mut m = HmacSha256::new_from_slice(key).expect("any key length");
            m.update(signed);
            m.verify_slice(tag)
                .map_err(|_| "HMAC mismatch".to_owned())?;
            let (data, crc) = signed.split_at(signed.len() - 4);
            if crc32c::crc32c(data).to_le_bytes() != crc {
                return Err("CRC mismatch".to_owned());
            }
            let schema = u32::from_le_bytes(data[4..8].try_into().unwrap());
            if schema != S::SCHEMA {
                return Err(format!("schema {schema} != {}", S::SCHEMA));
            }
            let lsn = u64::from_le_bytes(data[8..16].try_into().unwrap());
            let chain: [u8; 32] = data[16..48].try_into().unwrap();
            let len = u64::from_le_bytes(data[48..56].try_into().unwrap()) as usize;
            let body = data.get(56..56 + len).ok_or("short body")?;
            let state: S = postcard::from_bytes(body).map_err(|e| e.to_string())?;
            Ok((state, lsn, chain))
        })();
        match parsed {
            Ok(s) => Some(s),
            Err(why) => {
                warn!(
                    "snapshot {} ignored ({why}); rebuilding from WAL",
                    name.trim()
                );
                None
            }
        }
    }

    /// Read one segment, check CRC and the HMAC chain (`prev` carries it
    /// across segments), call `f` per record.
    fn replay(
        path: &Path,
        key: &[u8],
        is_last: bool,
        prev: &mut [u8; 32],
        f: &mut dyn FnMut(u64, [u8; 32], S::Op) -> Result<(), String>,
    ) -> Result<()> {
        let file = path.display().to_string();
        let first_lsn: u64 = path
            .file_name()
            .and_then(|n| n.to_str())
            .and_then(|n| n.strip_prefix("wal.")?.strip_suffix(".wyw")?.parse().ok())
            .unwrap_or(1);
        let mut data = Vec::new();
        File::open(path)?.read_to_end(&mut data)?;
        let mut off = 0usize;
        let mut lsn = first_lsn;
        let corrupt = |offset: usize, why: &str| StateError::Corrupt {
            file: file.clone(),
            offset: offset as u64,
            why: why.to_owned(),
        };
        while off < data.len() {
            let tail_cut = |why: &str| -> Result<()> {
                if is_last {
                    warn!(file = %file, offset = off, "dropping incomplete WAL tail: {why}");
                    let f = OpenOptions::new().write(true).open(path)?;
                    f.set_len(off as u64)?;
                    f.sync_all()?;
                    Ok(())
                } else {
                    Err(corrupt(off, why))
                }
            };
            if data.len() - off < HEADER {
                return tail_cut("short header");
            }
            let len = u32::from_le_bytes(data[off..off + 4].try_into().unwrap()) as usize;
            if len > MAX_RECORD {
                return tail_cut("record length out of range");
            }
            if data.len() - off - HEADER < len {
                return tail_cut("short record");
            }
            let crc = u32::from_le_bytes(data[off + 4..off + 8].try_into().unwrap());
            let stored: [u8; 32] = data[off + 8..off + 40].try_into().unwrap();
            let payload = &data[off + HEADER..off + HEADER + len];
            if crc32c::crc32c(payload) != crc {
                // A bad CRC on the very last record is a torn write.
                if off + HEADER + len == data.len() {
                    return tail_cut("CRC mismatch on last record");
                }
                return Err(corrupt(off, "CRC mismatch"));
            }
            if mac(key, prev, lsn, payload) != stored {
                return Err(StateError::Tampered { lsn, file });
            }
            let op: S::Op = minicbor::decode(payload).map_err(|e| corrupt(off, &e.to_string()))?;
            f(lsn, stored, op).map_err(|why| corrupt(off, &why))?;
            *prev = stored;
            off += HEADER + len;
            lsn += 1;
        }
        Ok(())
    }
}

/// Result of [`verify`].
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Report {
    /// Records with a valid CRC and HMAC chain.
    pub records: u64,
    /// LSN of the last valid record (0 = empty).
    pub last_lsn: u64,
    /// The last segment ends in an incomplete record (a torn write; `open`
    /// drops it). Not an attack sign by itself.
    pub torn_tail: bool,
    /// `Some(true)`: the anchor matches the head; `None`: no anchor given.
    pub anchor_ok: Option<bool>,
}

/// Check a store offline without changing it: every record's CRC and the
/// HMAC chain from the first record, and the anchor if given. Fails with
/// `InUse` while a process holds the store.
pub fn verify(dir: &Path, key: &[u8], anchor: Option<&Path>) -> Result<Report> {
    let lock = OpenOptions::new()
        .create(true)
        .truncate(false)
        .write(true)
        .open(dir.join("LOCK"))?;
    match lock.try_lock() {
        Ok(()) => {}
        Err(std::fs::TryLockError::WouldBlock) => {
            return Err(StateError::InUse(dir.display().to_string()))
        }
        Err(std::fs::TryLockError::Error(e)) => return Err(e.into()),
    }
    let segs = segments(dir)?;
    let mut prev = [0u8; 32];
    let mut lsn = 0u64;
    let mut records = 0u64;
    let mut torn_tail = false;
    for (i, (first, path)) in segs.iter().enumerate() {
        let file = path.display().to_string();
        let is_last = i + 1 == segs.len();
        let mut data = Vec::new();
        File::open(path)?.read_to_end(&mut data)?;
        let mut off = 0usize;
        let mut at = *first;
        while off < data.len() {
            let left = data.len() - off;
            let len = if left >= HEADER {
                u32::from_le_bytes(data[off..off + 4].try_into().unwrap_or_default()) as usize
            } else {
                usize::MAX
            };
            if left < HEADER || len > MAX_RECORD || left - HEADER < len {
                if is_last {
                    torn_tail = true;
                    break;
                }
                return Err(StateError::Corrupt {
                    file,
                    offset: off as u64,
                    why: "incomplete record inside the log".into(),
                });
            }
            let crc = u32::from_le_bytes(data[off + 4..off + 8].try_into().unwrap_or_default());
            let stored: [u8; 32] = data[off + 8..off + 40].try_into().unwrap_or([0; 32]);
            let payload = &data[off + HEADER..off + HEADER + len];
            if crc32c::crc32c(payload) != crc {
                if is_last && off + HEADER + len == data.len() {
                    torn_tail = true;
                    break;
                }
                return Err(StateError::Corrupt {
                    file,
                    offset: off as u64,
                    why: "CRC mismatch".into(),
                });
            }
            if mac(key, &prev, at, payload) != stored {
                return Err(StateError::Tampered { lsn: at, file });
            }
            prev = stored;
            lsn = at;
            records += 1;
            off += HEADER + len;
            at += 1;
        }
    }
    let anchor_ok = anchor.map(|a| match fs::read_to_string(a) {
        Ok(t) => {
            let mut it = t.split_whitespace();
            let alsn: Option<u64> = it.next().and_then(|v| v.parse().ok());
            let amac = it.next().unwrap_or_default();
            match alsn {
                Some(n) if n == lsn => amac == hex_of(&prev),
                Some(n) => n + 1 == lsn,
                None => false,
            }
        }
        Err(_) => lsn == 0,
    });
    Ok(Report {
        records,
        last_lsn: lsn,
        torn_tail,
        anchor_ok,
    })
}
