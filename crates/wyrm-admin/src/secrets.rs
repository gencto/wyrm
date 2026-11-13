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
            // Only a missing file is an empty store: any other error would
            // drop every secret at the next save.
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Db::new(),
            Err(e) => return Err(format!("secrets.bin: {e}").into()),
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

    /// Saves one secret; when the store cannot be saved it is as before (no secret only in
    /// memory: a key lost at the next start would leave sealed data unreadable).
    pub fn set(&self, link: &str, name: &str, value: &[u8]) -> Result<(), Error> {
        let mut db = self.lock();
        let entry = db.entry(link.to_owned()).or_default();
        let old = entry.insert(name.to_owned(), Zeroizing::new(value.to_vec()));
        let saved = self.save(&db);
        if saved.is_err() {
            let entry = db.entry(link.to_owned()).or_default();
            match old {
                Some(v) => {
                    entry.insert(name.to_owned(), v);
                }
                None => {
                    entry.remove(name);
                    if entry.is_empty() {
                        db.remove(link);
                    }
                }
            }
        }
        saved
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

    /// Where the secrets a restore replaces are kept until it is committed.
    /// No link has this name (an id never starts with `.`).
    fn stash_name(link: &str) -> String {
        format!(".restoring/{link}")
    }

    /// Set the secrets `new` of `link` and keep what the link had before
    /// beside them, in one save: a restore that does not reach its end
    /// takes them back with [`Self::unstash`] (ADR 0048 §3.5). The store is
    /// as before when it cannot be saved.
    pub fn replace_stashed(
        &self,
        link: &str,
        new: &BTreeMap<String, Zeroizing<Vec<u8>>>,
    ) -> Result<(), Error> {
        let mut db = self.lock();
        let before = db.clone();
        let old = db.get(link).cloned().unwrap_or_default();
        db.insert(Self::stash_name(link), old);
        let entry = db.entry(link.to_owned()).or_default();
        for (name, v) in new {
            entry.insert(name.clone(), v.clone());
        }
        if entry.is_empty() {
            db.remove(link);
        }
        let saved = self.save(&db);
        if saved.is_err() {
            *db = before;
        }
        saved
    }

    /// End a [`Self::replace_stashed`] of `link`: `restore` puts the
    /// secrets it had before back, else they are forgotten. `false`: nothing
    /// was kept.
    pub fn unstash(&self, link: &str, restore: bool) -> Result<bool, Error> {
        let mut db = self.lock();
        let before = db.clone();
        let Some(old) = db.remove(&Self::stash_name(link)) else {
            return Ok(false);
        };
        if restore {
            if old.is_empty() {
                db.remove(link);
            } else {
                db.insert(link.to_owned(), old);
            }
        }
        match self.save(&db) {
            Ok(()) => Ok(true),
            Err(e) => {
                *db = before;
                Err(e)
            }
        }
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

/// Names that say a value is a secret.
const WORDS: &[&str] = &[
    "password",
    "passwd",
    "passphrase",
    "secret",
    "token",
    "private_key",
    "api_key",
    "apikey",
    "credential",
    "key_pem",
];

/// `true` for a field name that says its value is a secret.
pub fn secret_name(name: &str) -> bool {
    let lk = name.to_ascii_lowercase();
    WORDS.iter().any(|w| lk.contains(w)) || lk == "key" || lk.ends_with("_key")
}

/// What stands for a masked secret.
pub const MASK: &str = "***";

/// A configuration as JSON with every secret masked, for the `config`
/// section of a backup (ADR 0048 §3.2): the value of a field named like a
/// secret ([`secret_name`]; whatever its type), a PEM private key, and a
/// long hex string wherever it is, except under `admin_keys` (public keys).
pub fn mask_config(v: &mut serde_json::Value) {
    fn walk(v: &mut serde_json::Value, public: bool) {
        match v {
            serde_json::Value::Object(m) => {
                for (k, v) in m.iter_mut() {
                    if secret_name(k) {
                        *v = serde_json::Value::String(MASK.into());
                    } else {
                        walk(v, k == "admin_keys");
                    }
                }
            }
            serde_json::Value::Array(a) => a.iter_mut().for_each(|v| walk(v, public)),
            serde_json::Value::String(s) => {
                let hex = s.len() >= 32 && s.chars().all(|c| c.is_ascii_hexdigit());
                if s.contains("PRIVATE KEY-----") || (hex && !public) {
                    *s = MASK.into();
                }
            }
            _ => {}
        }
    }
    walk(v, false);
}

/// Lint at install (wiki: "params ... looks like a password/key → move to
/// secrets"): keys named like secrets, or long hex strings.
pub fn lint_params(v: &Value, path: &str) -> Result<(), String> {
    match v {
        Value::Map(m) => {
            for (k, v) in m {
                let p = format!("{path}.{k}");
                if secret_name(k) {
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
    fn a_config_copy_has_no_secret_in_clear() {
        let mut v = serde_json::json!({
            "site": "plant",
            "admin_keys": ["aa".repeat(32)],
            "gateway": { "tls_key": "/etc/wyrm/gw.key", "listen": "0.0.0.0:8445" },
            "uplink": { "upstreams": [{ "name": "x", "password": "hunter2", "url": "mqtts://b" }] },
            "links": { "plc": { "params": { "api_token": { "v": "t0k" }, "psk": "bb".repeat(16) } } },
            "peers": { "upstream": [{ "site": "c", "key": "-----BEGIN PRIVATE KEY-----x" }] },
            "note": "-----BEGIN EC PRIVATE KEY-----\nabc",
        });
        mask_config(&mut v);
        let text = v.to_string();
        for secret in [
            "hunter2",
            "t0k",
            "/etc/wyrm/gw.key",
            "PRIVATE KEY",
            &"bb".repeat(16),
        ] {
            assert!(!text.contains(secret), "{secret} in {text}");
        }
        // what is not a secret stays: the site, the listener, the public keys
        assert_eq!(v["site"], "plant");
        assert_eq!(v["gateway"]["listen"], "0.0.0.0:8445");
        assert_eq!(v["admin_keys"][0], "aa".repeat(32));
        assert_eq!(v["uplink"]["upstreams"][0]["password"], MASK);
        assert!(secret_name("Passphrase") && secret_name("state_key") && !secret_name("keep_days"));
    }

    /// Review ADM-7: only a missing file is an empty store.
    #[test]
    fn an_unreadable_store_fails_the_open() {
        let d = dir("unreadable");
        assert!(SecretStore::open(&d).is_ok(), "missing = empty");
        std::fs::create_dir_all(d.join("secrets.bin")).unwrap();
        assert!(SecretStore::open(&d).is_err());
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
