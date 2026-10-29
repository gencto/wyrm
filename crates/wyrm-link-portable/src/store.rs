//! The link's own key-value store (ADR 0023): one sealed file per key in `<data_dir>/store`.
//!
//! ```text
//! <data_dir>/store/<hex(sha256(key))>   nonce [12] | ChaCha20-Poly1305(cbor {"k": key, "v": bytes})
//! ```
//!
//! * Sealed with the link's store key (the secret `.store_key` the admin makes per link).
//! * The record carries its key, and the file name must be the hash of that key, so a file moved
//!   to another name is refused.
//! * A write goes to a temporary file, is synced, renamed over the old file, then the directory
//!   is synced: a crash leaves the old record or the new one.
//! * All records are read at open and kept in memory (the store is at most 64 MiB).
//! * Each entry counts its key and value length rounded up to 4 KiB, at least 4 KiB
//!   ([`store_cost`]); at most [`MAX_STORE_KEYS`] keys of at most [`MAX_STORE_KEY_LEN`] bytes. The
//!   command buffer refuses a write over the quota first; [`Store::put`] checks the key bounds
//!   again.

use std::collections::{BTreeMap, HashMap};
use std::io::Write;
use std::path::{Path, PathBuf};

use sha2::{Digest, Sha256};
use tracing::warn;
use wyrm_core::Value;
use wyrm_link_api::buffer::{store_cost, MAX_STORE_KEYS, MAX_STORE_KEY_LEN};
use wyrm_link_sdk::seal;
use zeroize::Zeroizing;

const DIR: &str = "store";
const TMP: &str = "tmp";

pub struct Store {
    /// `None` without a data directory or a store key: every write fails.
    at: Option<(PathBuf, Zeroizing<[u8; 32]>)>,
    map: HashMap<String, Vec<u8>>,
    used: u64,
    /// Set by the runtime when it gives the engine up (stop): later writes are refused.
    abandoned: bool,
    /// Sequence number of the last job whose writes were applied (set by the runtime).
    committed: u64,
}

fn size(k: &str, v: &[u8]) -> u64 {
    store_cost(k.len(), v.len())
}

fn file_name(key: &str) -> String {
    hex::encode(Sha256::digest(key.as_bytes()))
}

impl Store {
    /// A store that holds nothing and refuses writes.
    pub fn none() -> Self {
        Self {
            at: None,
            map: HashMap::new(),
            used: 0,
            abandoned: false,
            committed: 0,
        }
    }

    /// Open (and create) `<data_dir>/store`. Without a data directory or a 32-byte key the store
    /// is [`none`](Self::none). Records that do not open are skipped with a warning.
    pub fn open(data_dir: Option<&Path>, key: Option<&[u8]>) -> Self {
        let (Some(dir), Some(key)) = (data_dir, key) else {
            return Self::none();
        };
        let Ok(key) = <[u8; 32]>::try_from(key).map(Zeroizing::new) else {
            warn!("store key is not 32 bytes: the link has no store");
            return Self::none();
        };
        let dir = dir.join(DIR);
        if let Err(e) = create_private_dir(&dir) {
            warn!(dir = %dir.display(), "store directory: {e}; the link has no store");
            return Self::none();
        }
        let mut s = Self {
            at: Some((dir.clone(), key)),
            ..Self::none()
        };
        let entries = match std::fs::read_dir(&dir) {
            Ok(e) => e,
            Err(e) => {
                warn!(dir = %dir.display(), "store unreadable: {e}");
                return s;
            }
        };
        for entry in entries.flatten() {
            let name = entry.file_name().to_string_lossy().into_owned();
            if name.len() != 64 || !name.bytes().all(|b| b.is_ascii_hexdigit()) {
                continue; // temporary files and anything else
            }
            match s.read(&entry.path(), &name) {
                Some((k, v)) => {
                    s.used += size(&k, &v);
                    s.map.insert(k, v);
                }
                None => {
                    warn!(file = %entry.path().display(), "store record does not open (other key or changed): skipped")
                }
            }
        }
        s
    }

    fn read(&self, path: &Path, name: &str) -> Option<(String, Vec<u8>)> {
        let (_, key) = self.at.as_ref()?;
        let sealed = std::fs::read(path).ok()?;
        let plain = Zeroizing::new(seal::open(key, &sealed)?);
        let Value::Map(mut m) = wyrm_core::codec::from_slice::<Value>(&plain).ok()? else {
            return None;
        };
        let (Some(Value::Str(k)), Some(Value::Bytes(v))) = (m.remove("k"), m.remove("v")) else {
            return None;
        };
        (file_name(&k) == name).then_some((k, v))
    }

    pub fn is_ready(&self) -> bool {
        self.at.is_some()
    }

    /// Refuse every later write; returns the last committed job (see [`commit`](Self::commit)).
    pub fn abandon(&mut self) -> u64 {
        self.abandoned = true;
        self.committed
    }

    pub fn is_abandoned(&self) -> bool {
        self.abandoned
    }

    /// The writes of job `seq` are applied.
    pub fn commit(&mut self, seq: u64) {
        self.committed = seq;
    }

    pub fn get(&self, key: &str) -> Option<Vec<u8>> {
        self.map.get(key).cloned()
    }

    /// Quota used: the sum of [`store_cost`] of the entries.
    pub fn used(&self) -> u64 {
        self.used
    }

    /// Keys held.
    pub fn len(&self) -> usize {
        self.map.len()
    }

    pub fn is_empty(&self) -> bool {
        self.map.is_empty()
    }

    /// The value length of `key`; `None` when absent.
    pub fn value_len(&self, key: &str) -> Option<usize> {
        self.map.get(key).map(Vec::len)
    }

    pub fn put(&mut self, key: &str, value: &[u8]) -> Result<(), String> {
        if self.abandoned {
            return Err("the link stopped".into());
        }
        let (dir, k) = self.at.as_ref().ok_or("the link has no store")?;
        if key.is_empty() || key.len() > MAX_STORE_KEY_LEN {
            return Err(format!("a store key is 1 to {MAX_STORE_KEY_LEN} bytes"));
        }
        if !self.map.contains_key(key) && self.map.len() >= MAX_STORE_KEYS {
            return Err(format!("at most {MAX_STORE_KEYS} store keys"));
        }
        let mut m = BTreeMap::new();
        m.insert("k".to_owned(), Value::Str(key.to_owned()));
        m.insert("v".to_owned(), Value::Bytes(value.to_vec()));
        let plain =
            Zeroizing::new(wyrm_core::codec::to_vec(&Value::Map(m)).map_err(|e| e.to_string())?);
        let sealed = seal::seal(k, &plain);
        let path = dir.join(file_name(key));
        let tmp = path.with_extension(TMP);
        {
            let mut o = std::fs::OpenOptions::new();
            o.write(true).create(true).truncate(true);
            #[cfg(unix)]
            std::os::unix::fs::OpenOptionsExt::mode(&mut o, 0o600);
            let mut f = o.open(&tmp).map_err(|e| e.to_string())?;
            f.write_all(&sealed).map_err(|e| e.to_string())?;
            f.sync_all().map_err(|e| e.to_string())?;
        }
        std::fs::rename(&tmp, &path).map_err(|e| e.to_string())?;
        sync_dir(dir)?;
        if let Some(old) = self.map.insert(key.to_owned(), value.to_vec()) {
            self.used -= size(key, &old);
        }
        self.used += size(key, value);
        Ok(())
    }

    pub fn delete(&mut self, key: &str) -> Result<(), String> {
        if self.abandoned {
            return Err("the link stopped".into());
        }
        let (dir, _) = self.at.as_ref().ok_or("the link has no store")?;
        match std::fs::remove_file(dir.join(file_name(key))) {
            Ok(()) => sync_dir(dir)?,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
            Err(e) => return Err(e.to_string()),
        }
        if let Some(old) = self.map.remove(key) {
            self.used -= size(key, &old);
        }
        Ok(())
    }
}

fn sync_dir(dir: &Path) -> Result<(), String> {
    std::fs::File::open(dir)
        .and_then(|d| d.sync_all())
        .map_err(|e| format!("sync {}: {e}", dir.display()))
}

fn create_private_dir(dir: &Path) -> std::io::Result<()> {
    let mut b = std::fs::DirBuilder::new();
    b.recursive(true);
    #[cfg(unix)]
    std::os::unix::fs::DirBuilderExt::mode(&mut b, 0o700);
    b.create(dir)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn dir(name: &str) -> PathBuf {
        let d =
            std::env::temp_dir().join(format!("wyrm-portable-store-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        d
    }

    #[test]
    fn put_get_delete_and_reopen() {
        let d = dir("roundtrip");
        let key = [3u8; 32];
        let mut s = Store::open(Some(&d), Some(&key));
        assert!(s.is_ready());
        s.put("a", b"one").unwrap();
        s.put("a", b"two!").unwrap();
        s.put("b", b"x").unwrap();
        // one 4 KiB block per entry however small
        assert_eq!((s.used(), s.len()), (2 * 4096, 2));
        s.delete("b").unwrap();
        s.delete("missing").unwrap();
        let s = Store::open(Some(&d), Some(&key));
        assert_eq!(s.get("a").as_deref(), Some(&b"two!"[..]));
        assert_eq!(s.get("b"), None);
        assert_eq!((s.used(), s.len(), s.value_len("a")), (4096, 1, Some(4)));
        // another key opens nothing
        let s = Store::open(Some(&d), Some(&[4u8; 32]));
        assert_eq!(s.get("a"), None);
        let _ = std::fs::remove_dir_all(&d);
    }

    #[test]
    fn a_record_under_another_name_is_refused() {
        let d = dir("swap");
        let key = [3u8; 32];
        let mut s = Store::open(Some(&d), Some(&key));
        s.put("a", b"1").unwrap();
        let st = d.join(DIR);
        std::fs::rename(st.join(file_name("a")), st.join(file_name("b"))).unwrap();
        let s = Store::open(Some(&d), Some(&key));
        assert_eq!(s.get("a"), None);
        assert_eq!(s.get("b"), None);
        let _ = std::fs::remove_dir_all(&d);
    }

    #[test]
    fn put_checks_the_key_bounds() {
        let d = dir("bounds");
        let mut s = Store::open(Some(&d), Some(&[3u8; 32]));
        assert!(s.put("", b"1").is_err());
        assert!(s.put(&"k".repeat(MAX_STORE_KEY_LEN + 1), b"1").is_err());
        s.put(&"k".repeat(MAX_STORE_KEY_LEN), b"1").unwrap();
        // the key count: the bound is checked on the map, so fill it without files
        for i in s.len()..MAX_STORE_KEYS {
            s.map.insert(format!("f{i}"), Vec::new());
        }
        assert!(s.put("one-more", b"1").unwrap_err().contains("store keys"));
        // an existing key is not a new one
        s.put(&"k".repeat(MAX_STORE_KEY_LEN), b"2").unwrap();
        let _ = std::fs::remove_dir_all(&d);
    }

    #[test]
    fn no_dir_or_key_means_no_store() {
        let mut s = Store::open(None, Some(&[1; 32]));
        assert!(!s.is_ready());
        assert!(s.put("a", b"1").is_err());
        let d = dir("nokey");
        assert!(!Store::open(Some(&d), None).is_ready());
        assert!(!Store::open(Some(&d), Some(&[1; 5])).is_ready());
    }
}
