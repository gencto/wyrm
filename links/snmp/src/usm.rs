//! The User-based Security Model (RFC 3414): password to localized key,
//! HMAC-SHA-96 (`usmHMACSHAAuthProtocol`), HMAC-192-SHA-256 (RFC 7860)
//! and AES-128 in CFB mode (RFC 3826).

use aes::cipher::{AsyncStreamCipher, KeyIvInit};
use hmac::{Hmac, Mac};
use sha1::Sha1;
use sha2::{Digest, Sha256};
use zeroize::Zeroizing;

use crate::ber::Oid;

/// RFC 3414: a passphrase has at least 8 characters.
pub const MIN_PASSPHRASE: usize = 8;

/// Octets hashed by the password-to-key algorithm.
const EXPANDED: usize = 1_048_576;

/// `usmStats` (1.3.6.1.6.3.15.1.1): the counters a Report PDU names.
pub const USM_STATS: [u32; 9] = [1, 3, 6, 1, 6, 3, 15, 1, 1];

/// `snmpUnknownContexts.0` (SNMP-TARGET-MIB, RFC 3413).
pub const UNKNOWN_CONTEXTS: [u32; 10] = [1, 3, 6, 1, 6, 3, 12, 1, 5, 0];

/// Report reasons (`usmStats.<n>.0`, `snmpUnknownContexts.0`).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ReportKind {
    UnsupportedSecLevel,
    NotInTimeWindow,
    UnknownUserName,
    UnknownEngineId,
    WrongDigest,
    DecryptionError,
    /// `snmpUnknownContexts` (SNMP-TARGET-MIB): the request's context name is
    /// not one the agent has.
    UnknownContext,
    /// Another report: its OID is in the message.
    Other,
}

impl ReportKind {
    pub fn of(oid: &Oid) -> ReportKind {
        if oid.0 == UNKNOWN_CONTEXTS {
            return ReportKind::UnknownContext;
        }
        match oid.suffix(&Oid(USM_STATS.to_vec())) {
            Some([1, 0]) => ReportKind::UnsupportedSecLevel,
            Some([2, 0]) => ReportKind::NotInTimeWindow,
            Some([3, 0]) => ReportKind::UnknownUserName,
            Some([4, 0]) => ReportKind::UnknownEngineId,
            Some([5, 0]) => ReportKind::WrongDigest,
            Some([6, 0]) => ReportKind::DecryptionError,
            _ => ReportKind::Other,
        }
    }

    /// The `usmStats` OID of this reason (the agent's side).
    pub fn oid(self) -> Oid {
        let n = match self {
            ReportKind::UnsupportedSecLevel => 1,
            ReportKind::NotInTimeWindow => 2,
            ReportKind::UnknownUserName => 3,
            ReportKind::UnknownEngineId => 4,
            ReportKind::WrongDigest => 5,
            ReportKind::DecryptionError | ReportKind::Other => 6,
            ReportKind::UnknownContext => return Oid(UNKNOWN_CONTEXTS.to_vec()),
        };
        Oid(USM_STATS.to_vec()).join(&[n, 0])
    }

    /// What people read when a request is refused this way.
    pub fn message(self) -> &'static str {
        match self {
            ReportKind::UnsupportedSecLevel => {
                "the agent refused the security level (usmStatsUnsupportedSecLevels): check \
                 auth_protocol and priv_protocol for this user"
            }
            ReportKind::NotInTimeWindow => {
                "the agent's clock moved out of the time window (usmStatsNotInTimeWindows)"
            }
            ReportKind::UnknownUserName => {
                "the agent does not know this user (usmStatsUnknownUserNames)"
            }
            ReportKind::UnknownEngineId => {
                "the agent's engine id changed (usmStatsUnknownEngineIDs)"
            }
            ReportKind::WrongDigest => {
                "the agent refused the authentication digest (usmStatsWrongDigests): check \
                 auth_protocol and auth_passphrase"
            }
            ReportKind::DecryptionError => {
                "the agent could not decrypt the request (usmStatsDecryptionErrors): check \
                 priv_protocol and priv_passphrase"
            }
            ReportKind::UnknownContext => {
                "the agent does not know this context (snmpUnknownContexts): check the device's \
                 context"
            }
            ReportKind::Other => "the agent answered with a report",
        }
    }
}

/// Authentication protocols.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Auth {
    /// usmHMACSHAAuthProtocol: HMAC-SHA-1, MAC of 12 octets.
    Sha1,
    /// usmHMAC192SHA256AuthProtocol: HMAC-SHA-256, MAC of 24 octets.
    Sha256,
}

impl Auth {
    /// Octets of `msgAuthenticationParameters`.
    pub fn mac_len(self) -> usize {
        match self {
            Auth::Sha1 => 12,
            Auth::Sha256 => 24,
        }
    }

    /// RFC 3414 A.2: the localized key of `passphrase` for `engine_id`.
    pub fn localized_key(self, passphrase: &[u8], engine_id: &[u8]) -> Zeroizing<Vec<u8>> {
        match self {
            Auth::Sha1 => localize::<Sha1>(passphrase, engine_id),
            Auth::Sha256 => localize::<Sha256>(passphrase, engine_id),
        }
    }

    /// The MAC of `msg` (its auth parameters zeroed), truncated.
    pub fn sign(self, key: &[u8], msg: &[u8]) -> Vec<u8> {
        let full = match self {
            Auth::Sha1 => mac::<Hmac<Sha1>>(key, msg),
            Auth::Sha256 => mac::<Hmac<Sha256>>(key, msg),
        };
        full[..self.mac_len()].to_vec()
    }

    /// Check `tag` against the MAC of `msg` (constant time).
    pub fn verify(self, key: &[u8], msg: &[u8], tag: &[u8]) -> bool {
        if tag.len() != self.mac_len() {
            return false;
        }
        match self {
            Auth::Sha1 => verify::<Hmac<Sha1>>(key, msg, tag),
            Auth::Sha256 => verify::<Hmac<Sha256>>(key, msg, tag),
        }
    }
}

fn password_to_key<D: Digest>(passphrase: &[u8]) -> Zeroizing<Vec<u8>> {
    let mut h = D::new();
    if passphrase.is_empty() {
        return Zeroizing::new(h.finalize().to_vec());
    }
    let mut block = Zeroizing::new([0u8; 64]);
    let mut i = 0usize;
    for _ in 0..EXPANDED / block.len() {
        for b in block.iter_mut() {
            *b = passphrase[i % passphrase.len()];
            i += 1;
        }
        h.update(&block[..]);
    }
    Zeroizing::new(h.finalize().to_vec())
}

fn localize<D: Digest>(passphrase: &[u8], engine_id: &[u8]) -> Zeroizing<Vec<u8>> {
    let ku = password_to_key::<D>(passphrase);
    let mut h = D::new();
    h.update(&ku[..]);
    h.update(engine_id);
    h.update(&ku[..]);
    Zeroizing::new(h.finalize().to_vec())
}

fn mac<M: Mac + hmac::digest::KeyInit>(key: &[u8], msg: &[u8]) -> Vec<u8> {
    // HMAC takes a key of any length.
    let mut m = <M as hmac::digest::KeyInit>::new_from_slice(key)
        .unwrap_or_else(|_| <M as hmac::digest::KeyInit>::new(&Default::default()));
    m.update(msg);
    m.finalize().into_bytes().to_vec()
}

fn verify<M: Mac + hmac::digest::KeyInit>(key: &[u8], msg: &[u8], tag: &[u8]) -> bool {
    let Ok(mut m) = <M as hmac::digest::KeyInit>::new_from_slice(key) else {
        return false;
    };
    m.update(msg);
    m.verify_truncated_left(tag).is_ok()
}

/// The AES-128 key: the first 16 octets of the localized privacy key.
pub fn aes_key(localized: &[u8]) -> Option<Zeroizing<[u8; 16]>> {
    let k: [u8; 16] = localized.get(..16)?.try_into().ok()?;
    Some(Zeroizing::new(k))
}

fn iv(boots: u32, time: u32, salt: &[u8; 8]) -> [u8; 16] {
    let mut iv = [0u8; 16];
    iv[..4].copy_from_slice(&boots.to_be_bytes());
    iv[4..8].copy_from_slice(&time.to_be_bytes());
    iv[8..].copy_from_slice(salt);
    iv
}

type Enc = cfb_mode::Encryptor<aes::Aes128>;
type Dec = cfb_mode::Decryptor<aes::Aes128>;

/// RFC 3826: encrypt `data` in place with IV `boots‖time‖salt`.
pub fn encrypt(key: &[u8; 16], boots: u32, time: u32, salt: &[u8; 8], data: &mut [u8]) {
    Enc::new(key.into(), &iv(boots, time, salt).into()).encrypt(data);
}

/// RFC 3826: decrypt `data` in place.
pub fn decrypt(key: &[u8; 16], boots: u32, time: u32, salt: &[u8; 8], data: &mut [u8]) {
    Dec::new(key.into(), &iv(boots, time, salt).into()).decrypt(data);
}

#[cfg(test)]
mod tests {
    use super::*;

    fn hex(s: &str) -> Vec<u8> {
        let s: String = s.chars().filter(|c| !c.is_whitespace()).collect();
        (0..s.len())
            .step_by(2)
            .map(|i| u8::from_str_radix(&s[i..i + 2], 16).unwrap())
            .collect()
    }

    /// RFC 3414 A.3.2: "maplesyrup" with SHA.
    #[test]
    fn rfc3414_sha_key_localization() {
        let ku = password_to_key::<Sha1>(b"maplesyrup");
        assert_eq!(*ku, hex("9fb5cc0381497b3793528939ff788d5d79145211"));
        let engine = hex("000000000000000000000002");
        let kul = Auth::Sha1.localized_key(b"maplesyrup", &engine);
        assert_eq!(*kul, hex("6695febc9288e36282235fc7151f128497b38f3f"));
    }

    /// The same algorithm with SHA-256 (RFC 7860 §4.2.1; the RFC has no
    /// sample). The value was computed with Python's `hashlib`, an
    /// implementation independent of this one.
    #[test]
    fn sha256_key_localization() {
        let engine = hex("000000000000000000000002");
        let kul = Auth::Sha256.localized_key(b"maplesyrup", &engine);
        assert_eq!(kul.len(), 32);
        assert_eq!(
            *kul,
            hex("8982e0e549e866db361a6b625d84cccc11162d453ee8ce3a6445c2d6776f0f8b")
        );
    }

    #[test]
    fn macs_are_truncated_and_verified() {
        let key = Auth::Sha1.localized_key(b"maplesyrup", b"engine");
        let tag = Auth::Sha1.sign(&key, b"message");
        assert_eq!(tag.len(), 12);
        assert!(Auth::Sha1.verify(&key, b"message", &tag));
        assert!(!Auth::Sha1.verify(&key, b"messagf", &tag));
        assert!(!Auth::Sha1.verify(&key, b"message", &tag[..11]));
        let key = Auth::Sha256.localized_key(b"maplesyrup", b"engine");
        let tag = Auth::Sha256.sign(&key, b"message");
        assert_eq!(tag.len(), 24);
        assert!(Auth::Sha256.verify(&key, b"message", &tag));
        assert!(!Auth::Sha256.verify(&key[1..], b"message", &tag));
    }

    /// NIST SP 800-38A F.3.13 (CFB128-AES128.Encrypt), first two blocks.
    #[test]
    fn aes_cfb128_nist_vector() {
        let key: [u8; 16] = hex("2b7e151628aed2a6abf7158809cf4f3c").try_into().unwrap();
        let ivb = hex("000102030405060708090a0b0c0d0e0f");
        let boots = u32::from_be_bytes(ivb[..4].try_into().unwrap());
        let time = u32::from_be_bytes(ivb[4..8].try_into().unwrap());
        let salt: [u8; 8] = ivb[8..].try_into().unwrap();
        let plain = hex("6bc1bee22e409f96e93d7e117393172aae2d8a571e03ac9c9eb76fac45af8e51");
        let mut data = plain.clone();
        encrypt(&key, boots, time, &salt, &mut data);
        assert_eq!(
            data,
            hex("3b3fd92eb72dad20333449f8e83cfb4ac8a64537a0b3a93fcde3cdad9f1ce58b")
        );
        decrypt(&key, boots, time, &salt, &mut data);
        assert_eq!(data, plain);
        // a partial last block (CFB needs no padding)
        let mut odd = plain[..21].to_vec();
        encrypt(&key, boots, time, &salt, &mut odd);
        decrypt(&key, boots, time, &salt, &mut odd);
        assert_eq!(odd, plain[..21]);
    }

    #[test]
    fn report_kinds() {
        for k in [
            ReportKind::UnsupportedSecLevel,
            ReportKind::NotInTimeWindow,
            ReportKind::UnknownUserName,
            ReportKind::UnknownEngineId,
            ReportKind::WrongDigest,
            ReportKind::DecryptionError,
            ReportKind::UnknownContext,
        ] {
            assert_eq!(ReportKind::of(&k.oid()), k);
        }
        assert_eq!(
            ReportKind::of(&Oid::parse("1.3.6.1.6.3.12.1.5.0").unwrap()),
            ReportKind::UnknownContext
        );
        assert_eq!(
            ReportKind::of(&Oid::parse("1.3.6.1.6.3.11.2.1.3.0").unwrap()),
            ReportKind::Other
        );
    }
}
