//! The site's key bundle for a warm standby (ADR 0036, option 3): the files
//! of `data_dir` that cannot be regenerated and never cross the network in
//! WYRM's own protocol. An operator exports them on the active broker
//! (`wyrmd keys export`), carries the file, and imports it into the
//! standby's empty `data_dir` (`wyrmd keys import`).
//!
//! ```text
//! "WYKB1" | salt [16] | nonce [12] | ChaCha20-Poly1305(cbor {name: bytes}) | tag [16]
//! key = Argon2id(passphrase, salt)
//! ```

use crate::secret::write_private;
use crate::secret::Error;
use argon2::Argon2;
use std::collections::BTreeMap;
use std::path::Path;
use wyrm_core::Value;
use zeroize::Zeroizing;

const MAGIC: &[u8; 5] = b"WYKB1";
const SALT_LEN: usize = 16;
/// Shortest passphrase taken: the bundle is the site.
pub const MIN_PASSPHRASE: usize = 12;

/// What the bundle carries, relative to `data_dir`: the CA and its key,
/// the HMAC keys of the control-plane WALs, the secret store key, the flow
/// and gateway signing keys. The gateway files exist only with a gateway.
pub const FILES: [&str; 7] = [
    "pki/ca.pem",
    "pki/ca.key",
    "state.key",
    "secrets.key",
    "flows.key",
    "gateway/hmac.key",
    "gateway/gateway.key",
];

fn derive(passphrase: &[u8], salt: &[u8]) -> Result<Zeroizing<[u8; 32]>, Error> {
    if passphrase.len() < MIN_PASSPHRASE {
        return Err(format!("passphrase: at least {MIN_PASSPHRASE} characters").into());
    }
    let mut key = Zeroizing::new([0u8; 32]);
    Argon2::default()
        .hash_password_into(passphrase, salt, key.as_mut())
        .map_err(|e| format!("key derivation: {e}"))?;
    Ok(key)
}

/// Seal the key files found under `data_dir` with `passphrase`. The site
/// CA and `state.key` must exist (a broker that never ran has nothing to
/// hand over).
pub fn export(data_dir: &Path, passphrase: &[u8]) -> Result<Vec<u8>, Error> {
    let mut files = BTreeMap::new();
    for name in FILES {
        let path = data_dir.join(name);
        match std::fs::read(&path) {
            Ok(bytes) => {
                files.insert(name.to_owned(), Value::Bytes(bytes));
            }
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
            Err(e) => return Err(format!("{}: {e}", path.display()).into()),
        }
    }
    for must in ["pki/ca.key", "state.key"] {
        if !files.contains_key(must) {
            return Err(format!(
                "{}: not found; run the broker once before exporting its keys",
                data_dir.join(must).display()
            )
            .into());
        }
    }
    let plain =
        Zeroizing::new(wyrm_core::codec::to_vec(&Value::Map(files)).map_err(|e| e.to_string())?);
    let mut salt = [0u8; SALT_LEN];
    getrandom::fill(&mut salt).map_err(|e| format!("no randomness: {e}"))?;
    let key = derive(passphrase, &salt)?;
    let mut out = Vec::with_capacity(MAGIC.len() + SALT_LEN + plain.len() + 28);
    out.extend_from_slice(MAGIC);
    out.extend_from_slice(&salt);
    out.extend(wyrm_link_sdk::seal::seal(&key, &plain));
    Ok(out)
}

/// Open `bundle` with `passphrase` and write its files under `data_dir`
/// (0600, directories created). Refused when any of them already exists:
/// the import is for an empty standby, never over a running site's keys.
/// Returns the names written.
pub fn import(data_dir: &Path, bundle: &[u8], passphrase: &[u8]) -> Result<Vec<String>, Error> {
    if bundle.len() < MAGIC.len() + SALT_LEN || &bundle[..MAGIC.len()] != MAGIC {
        return Err("not a WYRM key bundle".into());
    }
    let salt = &bundle[MAGIC.len()..MAGIC.len() + SALT_LEN];
    let key = derive(passphrase, salt)?;
    let plain = Zeroizing::new(
        wyrm_link_sdk::seal::open(&key, &bundle[MAGIC.len() + SALT_LEN..])
            .ok_or("wrong passphrase, or the bundle was changed")?,
    );
    let Value::Map(files) =
        wyrm_core::codec::from_slice::<Value>(&plain).map_err(|e| e.to_string())?
    else {
        return Err("bundle: not a map".into());
    };
    let mut names = Vec::new();
    for (name, v) in &files {
        if !FILES.contains(&name.as_str()) {
            return Err(format!("bundle: unexpected file {name}").into());
        }
        let Value::Bytes(_) = v else {
            return Err(format!("bundle: {name} is not bytes").into());
        };
        if data_dir.join(name).exists() {
            return Err(format!(
                "{}: exists; the bundle goes into an empty data_dir",
                data_dir.join(name).display()
            )
            .into());
        }
        names.push(name.clone());
    }
    for (name, v) in files {
        let Value::Bytes(bytes) = v else {
            continue;
        };
        let path = data_dir.join(&name);
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
            #[cfg(unix)]
            {
                use std::os::unix::fs::PermissionsExt;
                let _ = std::fs::set_permissions(parent, std::fs::Permissions::from_mode(0o700));
            }
        }
        write_private(&path, &bytes)?;
    }
    Ok(names)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn dir(name: &str) -> std::path::PathBuf {
        let d = std::env::temp_dir().join(format!("wyrm-keys-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        d
    }

    #[test]
    fn bundle_roundtrip_and_refusals() {
        let a = dir("a");
        std::fs::create_dir_all(a.join("pki")).unwrap();
        std::fs::write(a.join("pki/ca.pem"), b"cert").unwrap();
        std::fs::write(a.join("pki/ca.key"), b"ca key").unwrap();
        std::fs::write(a.join("state.key"), b"state key").unwrap();
        std::fs::write(a.join("secrets.key"), b"secrets key").unwrap();
        let pass = b"correct horse battery";
        assert!(export(&a, b"short").is_err(), "a short passphrase");
        let bundle = export(&a, pass).unwrap();
        assert!(import(&dir("b"), &bundle, b"wrong passphrase!").is_err());
        let mut bad = bundle.clone();
        let last = bad.len() - 1;
        bad[last] ^= 1;
        assert!(import(&dir("c"), &bad, pass).is_err(), "a changed byte");
        let b = dir("d");
        let mut names = import(&b, &bundle, pass).unwrap();
        names.sort();
        assert_eq!(
            names,
            ["pki/ca.key", "pki/ca.pem", "secrets.key", "state.key"]
        );
        assert_eq!(std::fs::read(b.join("pki/ca.key")).unwrap(), b"ca key");
        assert!(
            import(&b, &bundle, pass).is_err(),
            "never over existing keys"
        );
        // a broker that never ran
        assert!(export(&dir("e"), pass).is_err());
    }
}
