//! The framework tree of a link, kept in its private `data_dir` (principle
//! 3: the connector owns its configuration). Runtime edits (`add_*`,
//! `edit`, `remove`, `enable`) survive a restart.
//!
//! ```text
//! <data_dir>/framework.tree   "WYT1" | nonce [12] | ChaCha20-Poly1305(cbor {0: boot, 1: tree})
//! ```
//!
//! * The whole tree is sealed, secret fields included, with the link's
//!   store key: the secret [`STORE_KEY`] that the admin creates per link and
//!   delivers with the other link secrets. The file alone is useless.
//! * `boot` is SHA-256 of the bootstrap params (`~def.params`). When they
//!   change (a `wyrmd.json5` edit, admin `update` or `rollback`), the
//!   bootstrap wins and the stored tree is replaced on the next edit.
//! * Without a `data_dir` or a store key, the tree lives in memory only.

use ring::aead::{Aad, LessSafeKey, Nonce, UnboundKey, CHACHA20_POLY1305, NONCE_LEN};
use ring::rand::{SecureRandom, SystemRandom};
use sha2::{Digest, Sha256};
use std::io::Write;
use std::path::PathBuf;
use tracing::{info, warn};
use wyrm_core::Value;

/// Name of the link secret that seals the stored tree (not a valid name for
/// `set_secret`, so operators cannot overwrite it by accident).
pub const STORE_KEY: &str = ".store_key";
const MAGIC: &[u8; 4] = b"WYT1";
const FILE: &str = "framework.tree";

pub(crate) struct Persist {
    path: PathBuf,
    key: LessSafeKey,
    aad: String,
    boot: [u8; 32],
}

impl Persist {
    /// `None` without a `data_dir` or a usable store key.
    pub(crate) fn open(ctx: &crate::LinkCtx, bootstrap: &Value) -> Option<Self> {
        let dir = ctx.data_dir()?;
        let Some(secret) = ctx.secrets().get(STORE_KEY) else {
            warn!(
                link = ctx.link(),
                "no store key: runtime edits are not kept"
            );
            return None;
        };
        let Some(key) = UnboundKey::new(&CHACHA20_POLY1305, secret.expose())
            .ok()
            .map(LessSafeKey::new)
        else {
            warn!(
                link = ctx.link(),
                "store key is not 32 bytes: runtime edits are not kept"
            );
            return None;
        };
        let boot = Sha256::digest(wyrm_core::codec::to_vec(bootstrap).unwrap_or_default()).into();
        Some(Self {
            path: dir.join(FILE),
            key,
            aad: format!("wyrm-tree:{}", ctx.link()),
            boot,
        })
    }

    /// The stored tree, if it was saved for the same bootstrap params.
    pub(crate) fn load(&self) -> Option<Value> {
        let mut buf = match std::fs::read(&self.path) {
            Ok(b) => b,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => return None,
            Err(e) => {
                warn!(file = %self.path.display(), "stored tree unreadable ({e}): bootstrap params used");
                return None;
            }
        };
        let opened = (|| {
            if buf.len() < 4 + NONCE_LEN || &buf[..4] != MAGIC {
                return None;
            }
            let nonce = Nonce::try_assume_unique_for_key(&buf[4..4 + NONCE_LEN]).ok()?;
            let plain = self
                .key
                .open_in_place(
                    nonce,
                    Aad::from(self.aad.as_bytes()),
                    &mut buf[4 + NONCE_LEN..],
                )
                .ok()?;
            let Value::Map(mut m) = wyrm_core::codec::from_slice::<Value>(plain).ok()? else {
                return None;
            };
            Some((m.remove("boot")?, m.remove("tree")?))
        })();
        zeroize::Zeroize::zeroize(&mut buf);
        match opened {
            None => {
                warn!(file = %self.path.display(), "stored tree does not open (other key or tampered): bootstrap params used");
                None
            }
            Some((Value::Bytes(b), tree)) if b == self.boot => Some(tree),
            Some(_) => {
                info!(file = %self.path.display(), "bootstrap params changed: stored tree replaced");
                None
            }
        }
    }

    /// Seal and write `tree` (temp file, fsync, rename).
    pub(crate) fn save(&self, tree: &Value) -> Result<(), String> {
        let mut m = std::collections::BTreeMap::new();
        m.insert("boot".to_owned(), Value::Bytes(self.boot.to_vec()));
        m.insert("tree".to_owned(), tree.clone());
        let mut buf = zeroize::Zeroizing::new(
            wyrm_core::codec::to_vec(&Value::Map(m)).map_err(|e| e.to_string())?,
        );
        let mut nonce = [0u8; NONCE_LEN];
        SystemRandom::new()
            .fill(&mut nonce)
            .map_err(|_| "no randomness")?;
        self.key
            .seal_in_place_append_tag(
                Nonce::assume_unique_for_key(nonce),
                Aad::from(self.aad.as_bytes()),
                &mut *buf,
            )
            .map_err(|_| "seal failed")?;
        let tmp = self.path.with_extension("tmp");
        {
            let mut o = std::fs::OpenOptions::new();
            o.write(true).create(true).truncate(true);
            #[cfg(unix)]
            std::os::unix::fs::OpenOptionsExt::mode(&mut o, 0o600);
            let mut f = o.open(&tmp).map_err(|e| e.to_string())?;
            f.write_all(MAGIC).map_err(|e| e.to_string())?;
            f.write_all(&nonce).map_err(|e| e.to_string())?;
            f.write_all(&buf).map_err(|e| e.to_string())?;
            f.sync_all().map_err(|e| e.to_string())?;
        }
        std::fs::rename(&tmp, &self.path).map_err(|e| e.to_string())?;
        if let Some(dir) = self.path.parent() {
            if let Ok(d) = std::fs::File::open(dir) {
                let _ = d.sync_all();
            }
        }
        Ok(())
    }
}
