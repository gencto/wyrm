//! WAL replication (ADR 0036, option 3): the leader hands out its records
//! after an LSN, a follower appends them to its own WAL after checking the
//! HMAC chain with the shared key.
//!
//! * [`records_after`] reads the leader's segment files as they are (no
//!   lock: the writer appends and syncs one record at a time, so a torn
//!   tail is at most the record being written, and it is left out).
//! * A [`Follower`] holds the store directory like a [`Store`](crate::Store)
//!   does (the `LOCK`), appends records with the MAC the leader stored and
//!   refuses one whose MAC does not follow its own chain: a tampered feed,
//!   or a leader with another history. The follower never writes a
//!   snapshot; a `Store::open` on its directory replays the WAL.
//! * A follower whose chain at `after` is not the leader's has a history the
//!   leader does not (the records of a former active that never reached its
//!   standby): [`Follower::reset`] moves the directory aside as
//!   `<dir>.stale.<n>` and starts again from LSN 0.

use crate::{mac, segment_name, segments, sync_dir, Result, StateError, HEADER, MAX_RECORD};
use std::fs::{self, File, OpenOptions};
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use tracing::{info, warn};

/// One WAL record as stored: its LSN, the chain MAC the writer computed,
/// and the CBOR of the operation.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RawRecord {
    pub lsn: u64,
    pub mac: [u8; 32],
    pub payload: Vec<u8>,
}

/// What the leader answers to "records after `after`".
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Page {
    /// The chain MAC at `after` (32 zero bytes at 0): a follower whose own
    /// chain differs there has forked.
    pub chain: [u8; 32],
    /// The leader's last LSN.
    pub last: u64,
    /// Records `after + 1 ..`, at most the `max` asked for.
    pub records: Vec<RawRecord>,
}

/// Walk every record of the WAL in `dir` without checking MACs (the files
/// are the caller's own; a follower checks). `f(lsn, mac, payload)` per
/// record; a torn tail in the last segment is ignored, one inside the log
/// is corruption.
fn walk(dir: &Path, mut f: impl FnMut(u64, [u8; 32], &[u8])) -> Result<()> {
    let segs = segments(dir)?;
    for (i, (first, path)) in segs.iter().enumerate() {
        let is_last = i + 1 == segs.len();
        let mut data = Vec::new();
        File::open(path)?.read_to_end(&mut data)?;
        let mut off = 0usize;
        let mut lsn = *first;
        while off < data.len() {
            let left = data.len() - off;
            let len = if left >= HEADER {
                u32::from_le_bytes(data[off..off + 4].try_into().unwrap_or_default()) as usize
            } else {
                usize::MAX
            };
            if left < HEADER || len > MAX_RECORD || left - HEADER < len {
                if is_last {
                    break;
                }
                return Err(StateError::Corrupt {
                    file: path.display().to_string(),
                    offset: off as u64,
                    why: "incomplete record inside the log".into(),
                });
            }
            let crc = u32::from_le_bytes(data[off + 4..off + 8].try_into().unwrap_or_default());
            let stored: [u8; 32] = data[off + 8..off + 40].try_into().unwrap_or([0; 32]);
            let payload = &data[off + HEADER..off + HEADER + len];
            if crc32c::crc32c(payload) != crc {
                if is_last && off + HEADER + len == data.len() {
                    break;
                }
                return Err(StateError::Corrupt {
                    file: path.display().to_string(),
                    offset: off as u64,
                    why: "CRC mismatch".into(),
                });
            }
            f(lsn, stored, payload);
            off += HEADER + len;
            lsn += 1;
        }
    }
    Ok(())
}

/// The leader side: the records after `after` (at most `max`), the chain
/// MAC at `after` and the last LSN of the WAL in `dir`.
pub fn records_after(dir: &Path, after: u64, max: usize) -> Result<Page> {
    let mut page = Page {
        chain: [0; 32],
        last: 0,
        records: Vec::new(),
    };
    if !dir.is_dir() {
        return Ok(page);
    }
    walk(dir, |lsn, mac, payload| {
        page.last = lsn;
        if lsn == after {
            page.chain = mac;
        } else if lsn > after && page.records.len() < max {
            page.records.push(RawRecord {
                lsn,
                mac,
                payload: payload.to_vec(),
            });
        }
    })?;
    Ok(page)
}

/// The follower side of one WAL: appends the leader's records in order
/// after checking each against its own chain.
pub struct Follower {
    dir: PathBuf,
    key: Vec<u8>,
    lsn: u64,
    chain: [u8; 32],
    wal: File,
    _lock: File,
    /// Head record kept outside the store, as `Store::with_anchor` does.
    anchor: Option<PathBuf>,
}

impl Follower {
    /// Open (or create) the WAL in `dir`, check it from the first record
    /// with `key` (as `Store::open` does; a torn tail is cut), hold its lock.
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
        let mut lsn = 0u64;
        let mut chain = [0u8; 32];
        let mut bad: Option<u64> = None;
        walk(&dir, |at, stored, payload| {
            if bad.is_some() {
                return;
            }
            if at != lsn + 1 || mac(key, &chain, at, payload) != stored {
                bad = Some(at);
                return;
            }
            lsn = at;
            chain = stored;
        })?;
        if let Some(at) = bad {
            return Err(StateError::Tampered {
                lsn: at,
                file: dir.display().to_string(),
            });
        }
        let segs = segments(&dir)?;
        let path = match segs.last() {
            Some((_, p)) => p.clone(),
            None => {
                let p = dir.join(segment_name(1));
                File::create(&p)?;
                sync_dir(&dir)?;
                p
            }
        };
        // Cut a torn tail the walk skipped, so the next record follows the
        // last complete one.
        {
            let mut data = Vec::new();
            File::open(&path)?.read_to_end(&mut data)?;
            let mut off = 0usize;
            while data.len() - off >= HEADER {
                let len =
                    u32::from_le_bytes(data[off..off + 4].try_into().unwrap_or_default()) as usize;
                if len > MAX_RECORD || data.len() - off - HEADER < len {
                    break;
                }
                off += HEADER + len;
            }
            if off < data.len() {
                warn!(file = %path.display(), offset = off, "dropping incomplete WAL tail");
                let f = OpenOptions::new().write(true).open(&path)?;
                f.set_len(off as u64)?;
                f.sync_all()?;
            }
        }
        let wal = OpenOptions::new().append(true).open(&path)?;
        info!(dir = %dir.display(), lsn, "follower opened");
        Ok(Self {
            dir,
            key: key.to_vec(),
            lsn,
            chain,
            wal,
            _lock: lock,
            anchor: None,
        })
    }

    /// Keep the head in `path` after every record (`state_anchor_dir`), so
    /// a promotion with anchors finds the anchor at the WAL's head.
    pub fn with_anchor(mut self, path: impl Into<PathBuf>) -> Result<Self> {
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
        f.write_all(format!("{} {}\n", self.lsn, crate::hex_of(&self.chain)).as_bytes())?;
        f.sync_all()?;
        fs::rename(&tmp, path)?;
        if let Some(dir) = path.parent() {
            sync_dir(dir)?;
        }
        Ok(())
    }

    /// LSN of the last record held.
    pub fn lsn(&self) -> u64 {
        self.lsn
    }

    /// Chain MAC at the last record (zeros when empty).
    pub fn chain(&self) -> [u8; 32] {
        self.chain
    }

    /// Append the leader's next record: its LSN must be ours plus one and
    /// its MAC must be the one our chain and key give for its payload.
    pub fn append(&mut self, rec: &RawRecord) -> Result<()> {
        if rec.lsn != self.lsn + 1 {
            return Err(StateError::Rejected(format!(
                "record {} does not follow {}",
                rec.lsn, self.lsn
            )));
        }
        if rec.payload.len() > MAX_RECORD {
            return Err(StateError::Rejected(format!(
                "record {}: {} bytes",
                rec.lsn,
                rec.payload.len()
            )));
        }
        if mac(&self.key, &self.chain, rec.lsn, &rec.payload) != rec.mac {
            return Err(StateError::Tampered {
                lsn: rec.lsn,
                file: self.dir.display().to_string(),
            });
        }
        let mut out = Vec::with_capacity(HEADER + rec.payload.len());
        out.extend((rec.payload.len() as u32).to_le_bytes());
        out.extend(crc32c::crc32c(&rec.payload).to_le_bytes());
        out.extend(rec.mac);
        out.extend(&rec.payload);
        self.wal.write_all(&out)?;
        self.wal.sync_data()?;
        self.lsn = rec.lsn;
        self.chain = rec.mac;
        self.write_anchor()
    }

    /// Our history is not the leader's: move the directory aside as
    /// `<dir>.stale.<n>` (the lowest free `n`) and start again empty. The
    /// path of the old directory is returned.
    pub fn reset(&mut self) -> Result<PathBuf> {
        let parent = self.dir.parent().map(Path::to_path_buf).unwrap_or_default();
        let name = self
            .dir
            .file_name()
            .map(|n| n.to_string_lossy().into_owned())
            .unwrap_or_else(|| "wal".into());
        let mut n = 1u32;
        let stale = loop {
            let p = parent.join(format!("{name}.stale.{n}"));
            if !p.exists() {
                break p;
            }
            n += 1;
        };
        // The lock file moves with the old directory and is let go with
        // the old `self`; the fresh directory gets its own.
        let key = std::mem::take(&mut self.key);
        let dir = self.dir.clone();
        let anchor = self.anchor.take();
        fs::rename(&dir, &stale)?;
        sync_dir(&parent)?;
        warn!(from = %dir.display(), to = %stale.display(), "follower history differs from the leader's: moved aside");
        let mut fresh = Self::open(&dir, &key)?;
        if let Some(a) = anchor {
            fresh = fresh.with_anchor(a)?;
        }
        *self = fresh;
        Ok(stale)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{State, Store};
    use minicbor::{Decode, Encode};
    use serde::{Deserialize, Serialize};

    #[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
    struct Count(u32);

    #[derive(Debug, Encode, Decode)]
    struct Add(#[n(0)] u32);

    impl State for Count {
        const SCHEMA: u32 = 1;
        type Op = Add;
        fn apply(&mut self, op: &Add) -> Result<(), String> {
            self.0 += op.0;
            Ok(())
        }
    }

    fn dir(name: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("wyrm-state-repl-{name}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&d);
        let _ = fs::remove_dir_all(d.with_extension("x"));
        d
    }

    #[test]
    fn follower_copies_the_leader_and_the_copy_opens() {
        let key = [3u8; 32];
        let base = dir("copy");
        let (lead, foll) = (base.join("lead"), base.join("foll"));
        let mut store: Store<Count> = Store::open(&lead, &key).unwrap();
        for i in 1..=5 {
            store.apply(Add(i)).unwrap();
        }
        let mut f = Follower::open(&foll, &key).unwrap();
        // pages of two
        loop {
            let page = records_after(&lead, f.lsn(), 2).unwrap();
            assert_eq!(page.chain, f.chain(), "chains agree at {}", f.lsn());
            if page.records.is_empty() {
                assert_eq!(page.last, f.lsn());
                break;
            }
            for r in &page.records {
                f.append(r).unwrap();
            }
        }
        assert_eq!(f.lsn(), 5);
        drop(f);
        let copy: Store<Count> = Store::open(&foll, &key).unwrap();
        assert_eq!(copy.state(), &Count(15));
        assert_eq!(copy.lsn(), 5);
        // more on the leader after a snapshot (a new segment) still follows
        store.snapshot().unwrap();
        store.apply(Add(100)).unwrap();
        drop(copy);
        let mut f = Follower::open(&foll, &key).unwrap();
        let page = records_after(&lead, f.lsn(), 10).unwrap();
        assert_eq!(page.records.len(), 1);
        f.append(&page.records[0]).unwrap();
        assert_eq!(f.lsn(), 6);
    }

    #[test]
    fn follower_refuses_a_tampered_or_foreign_feed() {
        let key = [4u8; 32];
        let base = dir("tamper");
        let mut store: Store<Count> = Store::open(base.join("lead"), &key).unwrap();
        store.apply(Add(1)).unwrap();
        store.apply(Add(2)).unwrap();
        let page = records_after(&base.join("lead"), 0, 10).unwrap();
        let mut f = Follower::open(base.join("foll"), &key).unwrap();
        // a changed payload
        let mut bad = page.records[0].clone();
        bad.payload[0] ^= 1;
        assert!(matches!(f.append(&bad), Err(StateError::Tampered { .. })));
        // a record out of order
        assert!(matches!(
            f.append(&page.records[1]),
            Err(StateError::Rejected(_))
        ));
        // the same records under another key: another site's feed
        let mut other = Follower::open(base.join("other"), &[5u8; 32]).unwrap();
        assert!(matches!(
            other.append(&page.records[0]),
            Err(StateError::Tampered { .. })
        ));
        f.append(&page.records[0]).unwrap();
        f.append(&page.records[1]).unwrap();
        assert_eq!(f.lsn(), 2);
    }

    #[test]
    fn a_forked_follower_moves_its_history_aside() {
        let key = [6u8; 32];
        let base = dir("fork");
        // two histories from one key: the former active wrote a record the
        // new one never saw
        let mut a: Store<Count> = Store::open(base.join("a"), &key).unwrap();
        a.apply(Add(1)).unwrap();
        a.apply(Add(7)).unwrap();
        let mut b: Store<Count> = Store::open(base.join("b"), &key).unwrap();
        b.apply(Add(1)).unwrap();
        b.apply(Add(9)).unwrap();
        drop(a);
        let mut f = Follower::open(base.join("a"), &key).unwrap();
        assert_eq!(f.lsn(), 2);
        let page = records_after(&base.join("b"), f.lsn(), 10).unwrap();
        assert_ne!(page.chain, f.chain(), "the chains differ at 2");
        let stale = f.reset().unwrap();
        assert!(stale.ends_with("a.stale.1"));
        assert_eq!(f.lsn(), 0);
        let page = records_after(&base.join("b"), 0, 10).unwrap();
        for r in &page.records {
            f.append(r).unwrap();
        }
        drop(f);
        let copy: Store<Count> = Store::open(base.join("a"), &key).unwrap();
        assert_eq!(copy.state(), &Count(10));
        assert!(base.join("a.stale.1").join("LOCK").exists());
    }
}
