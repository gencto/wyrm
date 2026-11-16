//! Sealing with a 32-byte key: ChaCha20-Poly1305, wire format
//! `nonce [12] | ciphertext | tag [16]`. Used by the framework tree
//! (`driver::persist`) and open to links that keep their own state.

use ring::aead::{Aad, LessSafeKey, Nonce, UnboundKey, CHACHA20_POLY1305, NONCE_LEN};

const AAD: &[u8] = b"wyrm-seal";

/// Sealing failed: the OS gave no randomness for the nonce (a repeated nonce
/// would break the cipher, so nothing is sealed), or the cipher refused.
#[derive(Debug, Clone, Copy, PartialEq, Eq, thiserror::Error)]
#[error("seal: no randomness for the nonce, or the cipher refused")]
pub struct SealError;

impl From<ring::error::Unspecified> for SealError {
    fn from(_: ring::error::Unspecified) -> Self {
        SealError
    }
}

impl From<wyrm_core::rand::NoRandomness> for SealError {
    fn from(_: wyrm_core::rand::NoRandomness) -> Self {
        SealError
    }
}

fn cipher(key: &[u8; 32]) -> Option<LessSafeKey> {
    UnboundKey::new(&CHACHA20_POLY1305, key)
        .ok()
        .map(LessSafeKey::new)
}

/// Seal `plain` under `key` with a fresh random nonce:
/// `nonce | ciphertext | tag`.
pub fn seal(key: &[u8; 32], plain: &[u8]) -> Result<Vec<u8>, SealError> {
    seal_aad(key, AAD, plain)
}

/// Open what [`seal`] made. `None` for another key, a changed byte or a
/// short input.
pub fn open(key: &[u8; 32], sealed: &[u8]) -> Option<Vec<u8>> {
    open_aad(key, AAD, sealed)
}

/// [`seal`] bound to `aad`: it must be the same for [`open_aad`].
pub(crate) fn seal_aad(key: &[u8; 32], aad: &[u8], plain: &[u8]) -> Result<Vec<u8>, SealError> {
    let mut nonce = [0u8; NONCE_LEN];
    wyrm_core::rand::fill(&mut nonce)?;
    let mut out = Vec::with_capacity(NONCE_LEN + plain.len() + 16);
    out.extend_from_slice(&nonce);
    out.extend_from_slice(plain);
    let mut body = out.split_off(NONCE_LEN);
    let c = cipher(key).ok_or(SealError)?;
    c.seal_in_place_append_tag(
        Nonce::assume_unique_for_key(nonce),
        Aad::from(aad),
        &mut body,
    )?;
    out.extend_from_slice(&body);
    Ok(out)
}

pub(crate) fn open_aad(key: &[u8; 32], aad: &[u8], sealed: &[u8]) -> Option<Vec<u8>> {
    if sealed.len() < NONCE_LEN + CHACHA20_POLY1305.tag_len() {
        return None;
    }
    let nonce = Nonce::try_assume_unique_for_key(&sealed[..NONCE_LEN]).ok()?;
    let mut buf = sealed[NONCE_LEN..].to_vec();
    let n = cipher(key)?
        .open_in_place(nonce, Aad::from(aad), &mut buf)
        .ok()?
        .len();
    buf.truncate(n);
    Some(buf)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn seal_roundtrip_and_tamper() {
        let key = [9u8; 32];
        let sealed = seal(&key, b"secret state").unwrap();
        assert_eq!(open(&key, &sealed).as_deref(), Some(&b"secret state"[..]));
        assert_eq!(open(&[8u8; 32], &sealed), None, "other key");
        for i in 0..sealed.len() {
            let mut bad = sealed.clone();
            bad[i] ^= 1;
            assert_eq!(open(&key, &bad), None, "flipped byte {i}");
        }
        assert_eq!(open(&key, &sealed[..5]), None, "too short");
    }
}
