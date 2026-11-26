//! The one-time setup code of a new broker (ADR 0051 §3 "First admin").
//!
//! A board image carries only the hash of a setup code, never the code: the
//! first person who presents the code makes the first admin, and the code is
//! used up. The code is 16 random bytes shown as RFC 4648 base32 without
//! padding (26 characters) in groups of four; its hash is SHA-256 over
//! [`LABEL`] and the 16 bytes. The pending hash is the file [`FILE`] in the
//! gateway's directory (0600), as lowercase hex.
//!
//! The code also proves the server to the client (ADR 0051, answer 3 of the owner:
//! the first trust goes through the code). While a setup is pending, `GET /api/info`
//! carries [`setup_proof`]: HMAC-SHA-256 keyed with the hash over [`PROOF_LABEL`] and
//! the DER of the CA it presents as `ca`. A client computes the hash from the typed code
//! and checks the proof against that CA ([`verify_setup_proof`]) before it sends the
//! code, then pins the CA. Only who holds the hash (the device, and the image it came
//! from) can make a proof for a CA, so the hash is kept like a secret of the image.
//!
//! The code, its hash and the proof are `wyrm_core::setup` (pure, shared with
//! `wyr image build` and the clients) and are re-exported here; this module keeps what
//! belongs to the gateway: the pending file, the refusals and the OS randomness.
//!
//! Neither the code nor its hash is ever logged.

use crate::{rng, Error};
use zeroize::Zeroizing;

pub use wyrm_core::setup::{
    code_hash, setup_proof, verify_setup_proof, CODE_BYTES, CODE_CHARS, LABEL, PROOF_LABEL,
};

/// The pending setup in the gateway's directory: the hash as lowercase hex.
pub const FILE: &str = "setup.hash";

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

/// A new setup code: 16 bytes from the OS, in groups of four characters joined by `-`,
/// and its hash. Fails when the OS gives no randomness.
pub fn new_code() -> Result<(String, [u8; 32]), rng::NoRandomness> {
    let bytes = Zeroizing::new(rng::bytes::<CODE_BYTES>()?);
    Ok(wyrm_core::setup::code_of(&bytes))
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

    /// The gateway's `new_code` draws from the OS: two codes differ, in the documented form.
    #[test]
    fn new_codes_differ() {
        let (a, hash_a) = new_code().unwrap();
        let (b, hash_b) = new_code().unwrap();
        assert_ne!(a, b);
        assert_ne!(hash_a, hash_b);
        assert_eq!(a.len(), CODE_CHARS + 6);
        assert_eq!(code_hash(&a), Some(hash_a));
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

    /// A setup file that cannot be read is no setup, and is told once (not at every
    /// `/api/info`) until it is read again.
    #[test]
    fn an_unreadable_setup_file_is_told_once() {
        use std::sync::atomic::Ordering;
        let (gw, dir) = gateway("unreadable");
        let file = dir.join(FILE);
        // a directory where the file should be: every read fails, not as "not found"
        std::fs::create_dir_all(&file).unwrap();
        assert!(!gw.setup_pending());
        assert!(gw.setup_unreadable.load(Ordering::Relaxed), "told");
        assert!(!gw.setup_pending());
        assert!(
            gw.setup_unreadable.load(Ordering::Relaxed),
            "not told again"
        );
        std::fs::remove_dir(&file).unwrap();
        assert!(!gw.setup_pending());
        assert!(
            !gw.setup_unreadable.load(Ordering::Relaxed),
            "read again: a later failure is told again"
        );
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
