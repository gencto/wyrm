//! SecretStore (wiki "Захист даних"): link secrets (device passwords, DLMS
//! keys) encrypted at rest, never in the tree, `~def` or logs.
//!
//! `secrets.bin` = `"WYSS1" || nonce(12) || ChaCha20-Poly1305(cbor)`, key in
//! `secrets.key` (0600). The key file is the root of trust here; binding it
//! to a TPM or OS keyring is a later step.

use crate::secret::{load_or_create_key, write_private, Error};
use ring::aead::{Aad, LessSafeKey, Nonce, UnboundKey, CHACHA20_POLY1305, NONCE_LEN};
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use wyrm_core::Value;
use zeroize::Zeroizing;

const MAGIC: &[u8; 5] = b"WYSS1";

type Db = BTreeMap<String, BTreeMap<String, Zeroizing<Vec<u8>>>>;

pub struct SecretStore {
    path: PathBuf,
    key: LessSafeKey,
    db: Mutex<Db>,
}

fn encode(db: &Db) -> Zeroizing<Vec<u8>> {
    let v = Value::Map(
        db.iter()
            .map(|(link, m)| {
                (
                    link.clone(),
                    Value::Map(
                        m.iter()
                            .map(|(k, s)| (k.clone(), Value::Bytes(s.to_vec())))
                            .collect(),
                    ),
                )
            })
            .collect(),
    );
    Zeroizing::new(wyrm_core::codec::to_vec(&v).unwrap_or_default())
}

fn decode(b: &[u8]) -> Result<Db, Error> {
    let Value::Map(links) = wyrm_core::codec::from_slice::<Value>(b)? else {
        return Err("secrets: bad layout".into());
    };
    let mut db = Db::new();
    for (link, v) in links {
        let Value::Map(m) = v else { continue };
        let entry = db.entry(link).or_default();
        for (k, s) in m {
            if let Value::Bytes(bytes) = s {
                entry.insert(k, Zeroizing::new(bytes));
            }
        }
    }
    Ok(db)
}

impl SecretStore {
    pub fn open(dir: &Path) -> Result<Self, Error> {
        let raw_key = load_or_create_key(&dir.join("secrets.key"))?;
        let key = LessSafeKey::new(
            UnboundKey::new(&CHACHA20_POLY1305, &raw_key).map_err(|_| "secrets: bad key")?,
        );
        let path = dir.join("secrets.bin");
        let db = match std::fs::read(&path) {
            Err(_) => Db::new(),
            Ok(data) => {
                if data.len() < MAGIC.len() + NONCE_LEN || &data[..MAGIC.len()] != MAGIC {
                    return Err("secrets.bin: not a WYRM secret store".into());
                }
                let nonce =
                    Nonce::try_assume_unique_for_key(&data[MAGIC.len()..MAGIC.len() + NONCE_LEN])
                        .map_err(|_| "secrets.bin: bad nonce")?;
                let mut sealed = Zeroizing::new(data[MAGIC.len() + NONCE_LEN..].to_vec());
                let plain = key
                    .open_in_place(nonce, Aad::from(MAGIC), &mut sealed)
                    .map_err(|_| "secrets.bin: cannot decrypt (wrong key or tampered)")?;
                decode(plain)?
            }
        };
        Ok(Self {
            path,
            key,
            db: Mutex::new(db),
        })
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, Db> {
        self.db.lock().unwrap_or_else(|p| p.into_inner())
    }

    fn save(&self, db: &Db) -> Result<(), Error> {
        let mut nonce = [0u8; NONCE_LEN];
        getrandom::fill(&mut nonce).map_err(|e| format!("no randomness: {e}"))?;
        let mut buf = encode(db);
        self.key
            .seal_in_place_append_tag(
                Nonce::assume_unique_for_key(nonce),
                Aad::from(MAGIC),
                &mut *buf,
            )
            .map_err(|_| "secrets: seal failed")?;
        let mut out = MAGIC.to_vec();
        out.extend(nonce);
        out.extend(buf.iter());
        write_private(&self.path, &out)?;
        Ok(())
    }

    pub fn set(&self, link: &str, name: &str, value: &[u8]) -> Result<(), Error> {
        let mut db = self.lock();
        db.entry(link.to_owned())
            .or_default()
            .insert(name.to_owned(), Zeroizing::new(value.to_vec()));
        self.save(&db)
    }

    /// `true` if it existed.
    pub fn remove(&self, link: &str, name: &str) -> Result<bool, Error> {
        let mut db = self.lock();
        let had = db.get_mut(link).and_then(|m| m.remove(name)).is_some();
        if had {
            self.save(&db)?;
        }
        Ok(had)
    }

    pub fn drop_link(&self, link: &str) -> Result<(), Error> {
        let mut db = self.lock();
        if db.remove(link).is_some() {
            self.save(&db)?;
        }
        Ok(())
    }

    /// Names only (shown in the tree).
    pub fn names(&self, link: &str) -> Vec<String> {
        self.lock()
            .get(link)
            .map(|m| m.keys().cloned().collect())
            .unwrap_or_default()
    }

    /// The secrets of one link, for delivery over a protected channel.
    pub fn for_link(&self, link: &str) -> BTreeMap<String, Zeroizing<Vec<u8>>> {
        self.lock().get(link).cloned().unwrap_or_default()
    }
}

/// Lint at install (wiki: "params ... looks like a password/key → move to
/// secrets"): keys named like secrets, or long hex strings.
pub fn lint_params(v: &Value, path: &str) -> Result<(), String> {
    const WORDS: &[&str] = &[
        "password",
        "passwd",
        "secret",
        "token",
        "private_key",
        "api_key",
        "apikey",
        "credential",
        "key_pem",
    ];
    match v {
        Value::Map(m) => {
            for (k, v) in m {
                let lk = k.to_ascii_lowercase();
                let p = format!("{path}.{k}");
                if WORDS.iter().any(|w| lk.contains(w)) || lk == "key" || lk.ends_with("_key") {
                    return Err(format!(
                        "{p}: looks like a secret; use links/<id>/~act/set_secret"
                    ));
                }
                lint_params(v, &p)?;
            }
        }
        Value::Array(a) => {
            for (i, v) in a.iter().enumerate() {
                lint_params(v, &format!("{path}[{i}]"))?;
            }
        }
        Value::Str(s) if s.contains("PRIVATE KEY-----") => {
            return Err(format!(
                "{path}: a PEM private key; enter it in the link's add/edit action or use links/<id>/~act/set_secret"
            ));
        }
        Value::Str(s) if s.len() >= 32 && s.chars().all(|c| c.is_ascii_hexdigit()) => {
            return Err(format!(
                "{path}: looks like a key (long hex); use links/<id>/~act/set_secret"
            ));
        }
        _ => {}
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn dir(name: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("wyrm-secrets-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        d
    }

    #[test]
    fn roundtrip_encrypted_at_rest() {
        let d = dir("rt");
        let s = SecretStore::open(&d).unwrap();
        s.set("dlms", "ek", b"0011223344").unwrap();
        s.set("dlms", "ak", b"secret-ak").unwrap();
        drop(s);
        let raw = std::fs::read(d.join("secrets.bin")).unwrap();
        assert!(
            !raw.windows(9).any(|w| w == b"secret-ak"),
            "not plaintext on disk"
        );
        let s = SecretStore::open(&d).unwrap();
        assert_eq!(s.names("dlms"), ["ak", "ek"]);
        assert_eq!(&**s.for_link("dlms").get("ak").unwrap(), b"secret-ak");
        assert!(s.remove("dlms", "ak").unwrap());
        // tampering is detected
        let mut raw = std::fs::read(d.join("secrets.bin")).unwrap();
        let last = raw.len() - 1;
        raw[last] ^= 1;
        std::fs::write(d.join("secrets.bin"), raw).unwrap();
        assert!(SecretStore::open(&d).is_err());
    }

    #[test]
    fn params_lint() {
        let ok = Value::Map(BTreeMap::from([("host".into(), Value::from("10.0.0.1"))]));
        assert!(lint_params(&ok, "params").is_ok());
        for bad in ["password", "api_key", "dlms_key", "Secret", "key_pem"] {
            let v = Value::Map(BTreeMap::from([(bad.to_owned(), Value::from("x"))]));
            assert!(lint_params(&v, "params").is_err(), "{bad}");
        }
        let hex = Value::Map(BTreeMap::from([(
            "x".into(),
            Value::from("00112233445566778899aabbccddeeff"),
        )]));
        assert!(lint_params(&hex, "params").is_err());
        let pem = Value::Map(BTreeMap::from([(
            "client".into(),
            Value::from("-----BEGIN PRIVATE KEY-----\nMC4\n-----END PRIVATE KEY-----\n"),
        )]));
        assert!(lint_params(&pem, "params").is_err());
        // certificates are public
        let cert = Value::Map(BTreeMap::from([(
            "ca_pem".into(),
            Value::from("-----BEGIN CERTIFICATE-----\nMC4\n-----END CERTIFICATE-----\n"),
        )]));
        assert!(lint_params(&cert, "params").is_ok());
    }
}
