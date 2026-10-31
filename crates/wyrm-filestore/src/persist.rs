//! The connections of a file store link, kept in its private `data_dir`
//! (principle 3: the connector owns its configuration), as the driver
//! framework keeps its tree:
//!
//! ```text
//! <data_dir>/filestore.conns   "WYF1" | seal(store key, cbor {boot, conns})
//! ```
//!
//! Sealed whole, secrets included, with the link's store key (secret
//! [`STORE_KEY`]). `boot` is SHA-256 of the bootstrap params: when they
//! change, the bootstrap wins. Without a `data_dir` or a store key the
//! connections live in memory only.

use sha2::{Digest, Sha256};
use std::collections::BTreeMap;
use std::io::Write;
use std::path::PathBuf;
use tracing::{info, warn};
use wyrm_core::Value;
use wyrm_link_sdk::driver::persist::STORE_KEY;
use wyrm_link_sdk::seal;

const MAGIC: &[u8; 4] = b"WYF1";
const FILE: &str = "filestore.conns";

pub struct Persist {
    path: PathBuf,
    key: zeroize::Zeroizing<[u8; 32]>,
    boot: Vec<u8>,
}

impl Persist {
    pub fn open(ctx: &wyrm_link_sdk::LinkCtx, bootstrap: &Value) -> Option<Self> {
        let dir = ctx.data_dir()?;
        let Some(secret) = ctx.secrets().get(STORE_KEY) else {
            warn!(
                link = ctx.link(),
                "no store key: runtime edits are not kept"
            );
            return None;
        };
        let Ok(key) = <[u8; 32]>::try_from(secret.expose()) else {
            warn!(
                link = ctx.link(),
                "store key is not 32 bytes: runtime edits are not kept"
            );
            return None;
        };
        let boot = Sha256::digest(wyrm_core::codec::to_vec(bootstrap).unwrap_or_default()).to_vec();
        Some(Self {
            path: dir.join(FILE),
            key: zeroize::Zeroizing::new(key),
            boot,
        })
    }

    /// The stored connections, if saved for the same bootstrap params.
    pub fn load(&self) -> Option<BTreeMap<String, Value>> {
        let buf = match std::fs::read(&self.path) {
            Ok(b) => b,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => return None,
            Err(e) => {
                warn!(file = %self.path.display(), "stored connections unreadable ({e})");
                return None;
            }
        };
        let body = buf.strip_prefix(MAGIC.as_slice())?;
        let Some(plain) = seal::open(&self.key, body).map(zeroize::Zeroizing::new) else {
            warn!(file = %self.path.display(), "stored connections do not open: bootstrap used");
            return None;
        };
        let Ok(Value::Map(mut m)) = wyrm_core::codec::from_slice::<Value>(&plain) else {
            return None;
        };
        if m.get("boot") != Some(&Value::Bytes(self.boot.clone())) {
            info!("bootstrap params changed: stored connections replaced");
            return None;
        }
        match m.remove("conns") {
            Some(Value::Map(c)) => Some(c),
            _ => None,
        }
    }

    /// Save atomically (temp file, then rename), mode 0600.
    pub fn save(&self, conns: &BTreeMap<String, Value>) {
        let mut doc = BTreeMap::new();
        doc.insert("boot".to_owned(), Value::Bytes(self.boot.clone()));
        doc.insert("conns".to_owned(), Value::Map(conns.clone()));
        let Ok(plain) = wyrm_core::codec::to_vec(&Value::Map(doc)) else {
            return;
        };
        let plain = zeroize::Zeroizing::new(plain);
        let mut out = MAGIC.to_vec();
        out.extend(seal::seal(&self.key, &plain));
        let tmp = self.path.with_extension("tmp");
        let write = || -> std::io::Result<()> {
            let mut o = std::fs::OpenOptions::new();
            o.write(true).create(true).truncate(true);
            #[cfg(unix)]
            {
                use std::os::unix::fs::OpenOptionsExt;
                o.mode(0o600);
            }
            let mut f = o.open(&tmp)?;
            f.write_all(&out)?;
            f.sync_all()?;
            std::fs::rename(&tmp, &self.path)
        };
        if let Err(e) = write() {
            warn!(file = %self.path.display(), "connections not saved: {e}");
        }
    }
}
