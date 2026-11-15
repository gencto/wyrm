//! HMAC-SHA-256 with a key of any length, made without a fallible call.
//!
//! `Hmac::new_from_slice` returns a `Result` although HMAC takes every key
//! length (RFC 2104 §2); callers then `expect` or `unreachable!`. Here the
//! key is brought to one block the way RFC 2104 does it (hashed when longer
//! than the block, zero-padded when shorter) and handed to the infallible
//! `KeyInit::new`, so the MAC is the same and nothing can fail.

use hmac::digest::{Key, KeyInit};
use hmac::Mac;
use sha2::{Digest, Sha256};

/// HMAC-SHA-256.
pub type HmacSha256 = hmac::Hmac<Sha256>;

/// HMAC-SHA-256 under `key` (any length).
pub fn hmac_sha256(key: &[u8]) -> HmacSha256 {
    let mut block = Key::<HmacSha256>::default();
    let long;
    let key = if key.len() > block.len() {
        long = Sha256::digest(key);
        long.as_slice()
    } else {
        key
    };
    for (b, k) in block.iter_mut().zip(key) {
        *b = *k;
    }
    <HmacSha256 as KeyInit>::new(&block)
}

/// `HMAC-SHA-256(key, data)`.
pub fn hmac_sha256_of(key: &[u8], data: &[u8]) -> [u8; 32] {
    let mut m = hmac_sha256(key);
    m.update(data);
    m.finalize().into_bytes().into()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_same_mac_as_new_from_slice_for_every_key_length() {
        for len in [0usize, 1, 31, 32, 63, 64, 65, 128, 200] {
            let key: Vec<u8> = (0..len).map(|i| (i * 7 + 3) as u8).collect();
            let mut want = <HmacSha256 as Mac>::new_from_slice(&key).unwrap();
            want.update(b"what is signed");
            let mut got = hmac_sha256(&key);
            got.update(b"what is signed");
            assert_eq!(
                got.finalize().into_bytes(),
                want.finalize().into_bytes(),
                "{len}"
            );
        }
    }

    #[test]
    fn rfc_4231_case_6_a_key_longer_than_the_block() {
        let key = [0xaau8; 131];
        let tag = hmac_sha256_of(
            &key,
            b"Test Using Larger Than Block-Size Key - Hash Key First",
        );
        let want = "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54";
        let hex: String = tag.iter().map(|b| format!("{b:02x}")).collect();
        assert_eq!(hex, want);
    }
}
