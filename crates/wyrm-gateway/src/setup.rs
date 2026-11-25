//! The one-time setup code of a new broker (ADR 0051 §3 "First admin").
//!
//! A board image carries only the hash of a setup code, never the code: the
//! first person who presents the code makes the first admin, and the code is
//! used up. The code is 16 random bytes shown as RFC 4648 base32 without
//! padding (26 characters) in groups of four; its hash is SHA-256 over
//! [`LABEL`] and the 16 bytes. The pending hash is the file [`FILE`] in the
//! gateway's directory (0600), as lowercase hex.
//!
//! Neither the code nor its hash is ever logged.

use crate::{rng, Error};
use data_encoding::BASE32_NOPAD;
use zeroize::Zeroizing;

/// The bytes of a setup code.
pub const CODE_BYTES: usize = 16;
/// The base32 characters of a setup code (RFC 4648, no padding).
pub const CODE_CHARS: usize = 26;
/// What the hash is taken over before the code's bytes.
pub const LABEL: &[u8] = b"wyrm-setup-v1\n";
/// The pending setup in the gateway's directory: the hash as lowercase hex.
pub const FILE: &str = "setup.hash";
/// Longer input is no code, however it is spaced: refused before it is read.
const MAX_INPUT: usize = 128;

/// Why a setup step was refused.
#[derive(Debug, thiserror::Error)]
pub enum SetupError {
    /// No setup is pending: no setup file, or a user exists already.
    #[error("no setup is pending")]
    NoSetup,
    /// The code is not the pending one (or no code at all).
    #[error("wrong setup code")]
    WrongCode,
    /// The user or the setup hash was refused (name, password rules, hex).
    #[error("{0}")]
    Rejected(String),
    /// The user store or the setup file failed.
    #[error(transparent)]
    Store(#[from] Error),
}

impl SetupError {
    /// The wire code of the refusal (`code` of the reply), when it has one of its own;
    /// `Rejected` answers as the gateway's other refusals, `Store` as an internal error.
    pub fn code(&self) -> Option<&'static str> {
        match self {
            SetupError::NoSetup => Some("no_setup"),
            SetupError::WrongCode => Some("setup_code_wrong"),
            SetupError::Rejected(_) | SetupError::Store(_) => None,
        }
    }
}

/// The hash of `code` as a person typed it: upper or lower case, with spaces or `-`
/// between the groups. `None` when it is not 26 base32 characters of 16 bytes.
pub fn code_hash(code: &str) -> Option<[u8; 32]> {
    if code.len() > MAX_INPUT {
        return None;
    }
    // ASCII upper case only: no other letter folds into the alphabet
    let plain: Zeroizing<Vec<u8>> = Zeroizing::new(
        code.bytes()
            .filter(|b| !matches!(b, b' ' | b'-'))
            .map(|b| b.to_ascii_uppercase())
            .collect(),
    );
    if plain.len() != CODE_CHARS || BASE32_NOPAD.decode_len(CODE_CHARS).ok()? != CODE_BYTES {
        return None;
    }
    let mut bytes = Zeroizing::new([0u8; CODE_BYTES]);
    // also refuses a last character whose unused bits are not zero: one code, one text
    BASE32_NOPAD.decode_mut(&plain, bytes.as_mut()).ok()?;
    Some(hash_of(&bytes))
}

/// A new setup code: 16 bytes from the OS, in groups of four characters joined by `-`,
/// and its hash. Fails when the OS gives no randomness.
pub fn new_code() -> Result<(String, [u8; 32]), rng::NoRandomness> {
    let bytes = Zeroizing::new(rng::bytes::<CODE_BYTES>()?);
    let plain = Zeroizing::new(BASE32_NOPAD.encode(bytes.as_ref()));
    let mut code = String::with_capacity(CODE_CHARS + CODE_CHARS / 4);
    for (i, c) in plain.chars().enumerate() {
        if i > 0 && i % 4 == 0 {
            code.push('-');
        }
        code.push(c);
    }
    Ok((code, hash_of(&bytes)))
}

/// SHA-256 over [`LABEL`] and the code's bytes.
fn hash_of(bytes: &[u8; CODE_BYTES]) -> [u8; 32] {
    wyrm_core::hex::sha256_parts(&[LABEL, bytes])
}

/// The pending hash in `text` (the setup file or an import): 64 hex digits of either
/// case, white space around them ignored.
pub(crate) fn read_hash(text: &str) -> Option<[u8; 32]> {
    wyrm_core::hex::decode_array::<32>(text.trim())
}

/// Equal hashes, compared in constant time.
pub(crate) fn same(a: &[u8; 32], b: &[u8; 32]) -> bool {
    use subtle::ConstantTimeEq;
    bool::from(a[..].ct_eq(&b[..]))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{Gateway, GatewayConfig};
    use std::sync::Arc;

    const PASSWORD: &str = "a good long password";

    /// A gateway of its own (no server), its data in a directory of `name`.
    fn gateway(name: &str) -> (Arc<Gateway>, std::path::PathBuf) {
        let dir =
            std::env::temp_dir().join(format!("wyrm-gateway-setup-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let cfg = GatewayConfig::new("s", &dir, "127.0.0.1:0".parse().unwrap());
        (Gateway::open(cfg, b"test state key").unwrap(), dir)
    }

    fn hex(h: &[u8; 32]) -> String {
        wyrm_core::hex::encode(h)
    }

    #[test]
    fn code_is_read_as_typed() {
        let (code, hash) = new_code().unwrap();
        assert_eq!(code_hash(&code), Some(hash));
        // as typed: lower case, spaces between the groups, no dashes, dashes anywhere
        let lower = code.to_lowercase();
        assert_eq!(code_hash(&lower), Some(hash));
        assert_eq!(code_hash(&lower.replace('-', " ")), Some(hash));
        assert_eq!(code_hash(&code.replace('-', "")), Some(hash));
        assert_eq!(
            code_hash(&format!(" {} ", code.replace('-', " - "))),
            Some(hash)
        );

        let plain = code.replace('-', "");
        assert_eq!(plain.len(), CODE_CHARS);
        // one character short or long
        assert_eq!(code_hash(&plain[..CODE_CHARS - 1]), None);
        assert_eq!(code_hash(&format!("{plain}A")), None);
        // a `1` is not in the base32 alphabet
        assert_eq!(code_hash(&format!("1{}", &plain[1..])), None);
        // nothing, padding, other text, a long one, a non-ASCII letter that upper-cases
        // into the alphabet: none is a code, none panics
        for bad in [
            String::new(),
            "-".repeat(40),
            format!("{plain}======"),
            "é".repeat(26),
            "ı".repeat(26),
            "A".repeat(10_000),
            format!("{}\u{301}", &plain[..CODE_CHARS - 1]),
        ] {
            assert_eq!(code_hash(&bad), None, "{bad:?}");
        }
        // the hash of the spec: SHA-256 over the label and the 16 bytes
        let bytes = BASE32_NOPAD.decode(plain.as_bytes()).unwrap();
        assert_eq!(bytes.len(), CODE_BYTES);
        assert_eq!(
            hash,
            wyrm_core::hex::sha256_parts(&[b"wyrm-setup-v1\n", &bytes])
        );
    }

    #[test]
    fn new_code_is_groups_of_four() {
        let (code, _) = new_code().unwrap();
        let groups: Vec<&str> = code.split('-').collect();
        assert_eq!(
            groups.iter().map(|g| g.len()).collect::<Vec<_>>(),
            [4, 4, 4, 4, 4, 4, 2]
        );
        assert!(code
            .bytes()
            .all(|b| b == b'-' || b.is_ascii_uppercase() || (b'2'..=b'7').contains(&b)));
        assert_ne!(new_code().unwrap().0, code);
    }

    #[test]
    fn setup_makes_one_admin() {
        let (gw, dir) = gateway("one-admin");
        let (code, hash) = new_code().unwrap();
        assert!(!gw.setup_pending());
        assert!(gw.import_setup(&hex(&hash)).unwrap());
        assert!(gw.setup_pending());
        let file = dir.join(FILE);
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mode = std::fs::metadata(&file).unwrap().permissions().mode();
            assert_eq!(mode & 0o777, 0o600);
        }

        gw.complete_setup(&code.to_lowercase(), "first", PASSWORD)
            .unwrap();
        let u = gw.user("first").unwrap();
        assert_eq!(u.roles, ["admin"]);
        assert!(!gw.setup_pending());
        assert!(!file.exists());

        // the code is used up
        let again = gw.complete_setup(&code, "second", PASSWORD).unwrap_err();
        assert!(matches!(again, SetupError::NoSetup), "{again:?}");
        assert_eq!(again.code(), Some("no_setup"));
        assert!(gw.user("second").is_none());
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn wrong_code_keeps_the_setup() {
        let (gw, dir) = gateway("wrong-code");
        let (_, hash) = new_code().unwrap();
        let (other, _) = new_code().unwrap();
        assert!(gw.import_setup(&hex(&hash)).unwrap());
        for code in [other.as_str(), "", "not a code", "1111"] {
            let e = gw.complete_setup(code, "first", PASSWORD).unwrap_err();
            assert!(matches!(e, SetupError::WrongCode), "{e:?}");
            assert_eq!(e.code(), Some("setup_code_wrong"));
        }
        assert!(gw.setup_pending());
        assert!(gw.list_users().is_empty());
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn a_refused_user_keeps_the_setup() {
        let (gw, dir) = gateway("refused-user");
        let (code, hash) = new_code().unwrap();
        assert!(gw.import_setup(&hex(&hash)).unwrap());
        for (user, password) in [("first", "short"), (".bad", PASSWORD)] {
            let e = gw.complete_setup(&code, user, password).unwrap_err();
            assert!(matches!(e, SetupError::Rejected(_)), "{e:?}");
            assert_eq!(e.code(), None);
        }
        assert!(gw.setup_pending());
        // the same code still works
        gw.complete_setup(&code, "first", PASSWORD).unwrap();
        assert_eq!(gw.user("first").unwrap().roles, ["admin"]);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn import_is_refused_with_a_user() {
        let (gw, dir) = gateway("import-user");
        gw.add_user("op", PASSWORD, vec!["admin".into()]).unwrap();
        let (code, hash) = new_code().unwrap();
        assert!(!gw.import_setup(&hex(&hash)).unwrap());
        assert!(!dir.join(FILE).exists());
        assert!(!gw.setup_pending());
        let e = gw.complete_setup(&code, "first", PASSWORD).unwrap_err();
        assert!(matches!(e, SetupError::NoSetup), "{e:?}");
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn a_setup_file_beside_a_user_is_void_and_removed() {
        // a restored backup, or a crash between the admin and the removal
        let (gw, dir) = gateway("void-file");
        let (code, hash) = new_code().unwrap();
        assert!(gw.import_setup(&hex(&hash)).unwrap());
        gw.add_user("op", PASSWORD, vec!["admin".into()]).unwrap();
        assert!(!gw.setup_pending());
        let e = gw.complete_setup(&code, "first", PASSWORD).unwrap_err();
        assert!(matches!(e, SetupError::NoSetup), "{e:?}");
        assert!(gw.user("first").is_none());
        assert!(!dir.join(FILE).exists());
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn a_broken_setup_file_beside_a_user_is_void_and_removed() {
        let (gw, dir) = gateway("void-broken");
        let (code, _) = new_code().unwrap();
        std::fs::write(dir.join(FILE), b"not a hash").unwrap();
        gw.add_user("op", PASSWORD, vec!["admin".into()]).unwrap();
        let e = gw.complete_setup(&code, "first", PASSWORD).unwrap_err();
        assert!(matches!(e, SetupError::NoSetup), "{e:?}");
        assert!(!dir.join(FILE).exists());
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn settle_at_start() {
        let (gw, dir) = gateway("settle");
        let file = dir.join(FILE);
        assert!(!gw.settle_setup().unwrap());
        let (_, hash) = new_code().unwrap();
        assert!(gw.import_setup(&hex(&hash)).unwrap());
        assert!(gw.settle_setup().unwrap());
        // damaged, no user: the error names the file, which stays for the operator
        std::fs::write(&file, b"not a hash").unwrap();
        let e = gw.settle_setup().unwrap_err();
        assert!(matches!(e, SetupError::Store(_)), "{e:?}");
        assert!(e.to_string().contains(FILE), "{e}");
        assert!(
            !e.to_string().contains("not a hash"),
            "never the content: {e}"
        );
        assert!(file.exists());
        assert!(!gw.setup_pending());
        // the recovery: a new code's hash replaces the damaged file
        let (code, hash2) = new_code().unwrap();
        assert!(gw.import_setup(&hex(&hash2)).unwrap());
        assert!(gw.settle_setup().unwrap());
        gw.complete_setup(&code, "first", PASSWORD).unwrap();
        assert!(!file.exists());
        // beside a user: void and removed, damaged or not
        std::fs::write(&file, b"not a hash").unwrap();
        assert!(!gw.settle_setup().unwrap());
        assert!(!file.exists());
        assert!(gw.import_setup(&hex(&hash)).is_ok_and(|done| !done));
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn import_takes_hex_of_32_bytes_only() {
        let (gw, dir) = gateway("import-hex");
        let (_, hash) = new_code().unwrap();
        for bad in ["", "zz", &hex(&hash)[..62], &format!("{}00", hex(&hash))] {
            let e = gw.import_setup(bad).unwrap_err();
            assert!(matches!(e, SetupError::Rejected(_)), "{e:?}");
        }
        assert!(!gw.setup_pending());
        // upper case and a newline around it, as a file holds it
        assert!(gw
            .import_setup(&format!("{}\n", hex(&hash).to_uppercase()))
            .unwrap());
        assert!(gw.setup_pending());
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn two_setups_at_once_make_one_admin() {
        let (gw, dir) = gateway("race");
        let (code, hash) = new_code().unwrap();
        assert!(gw.import_setup(&hex(&hash)).unwrap());
        let done: Vec<bool> = std::thread::scope(|s| {
            let runs: Vec<_> = (0..4)
                .map(|i| {
                    let (gw, code) = (&gw, &code);
                    s.spawn(move || gw.complete_setup(code, &format!("u{i}"), PASSWORD).is_ok())
                })
                .collect();
            runs.into_iter().map(|r| r.join().unwrap()).collect()
        });
        assert_eq!(done.iter().filter(|d| **d).count(), 1);
        assert_eq!(gw.list_users().len(), 1);
        let _ = std::fs::remove_dir_all(&dir);
    }
}
