//! The one hex and SHA-256 helper of the workspace (review X2, docs/rust-rules.md §11).
//!
//! Hex is lowercase on the way out; on the way in both cases are read, and a text
//! that is not hex is `None`, never a partial or zero result. The digest is
//! SHA-256 of `sha2`. A crate does not write its own `{:02x}` loop or
//! `from_str_radix` pair: twelve of them had three different rules for case and
//! length.

use sha2::{Digest, Sha256};

/// `bytes` as lowercase hex, two characters per byte.
pub fn encode(bytes: impl AsRef<[u8]>) -> String {
    ::hex::encode(bytes)
}

/// `bytes` as uppercase hex, two characters per byte (SNMP engine ids, SQL
/// literals, MAC addresses as devices print them).
pub fn encode_upper(bytes: impl AsRef<[u8]>) -> String {
    ::hex::encode_upper(bytes)
}

/// `bytes` as lowercase hex with `sep` between the bytes (`00:1a:2b`).
pub fn encode_sep(bytes: &[u8], sep: &str) -> String {
    let mut out = String::with_capacity(bytes.len() * (2 + sep.len()));
    for (i, b) in bytes.iter().enumerate() {
        if i > 0 {
            out.push_str(sep);
        }
        out.push_str(&::hex::encode([*b]));
    }
    out
}

/// The bytes of hex text (either case); `None` when it is not hex of whole bytes.
pub fn decode(text: &str) -> Option<Vec<u8>> {
    ::hex::decode(text).ok()
}

/// Exactly `N` bytes of hex text (either case); `None` for any other length or text.
pub fn decode_array<const N: usize>(text: &str) -> Option<[u8; N]> {
    let mut out = [0u8; N];
    ::hex::decode_to_slice(text, &mut out).ok()?;
    Some(out)
}

/// `text` is hex of exactly `bytes` bytes; upper and lower case both pass.
pub fn is_hex(text: &str, bytes: usize) -> bool {
    text.len() == bytes * 2 && text.bytes().all(|b| b.is_ascii_hexdigit())
}

/// `text` is lowercase hex of exactly `bytes` bytes: the one form [`encode`] writes,
/// for a digest that is compared as text.
pub fn is_lower_hex(text: &str, bytes: usize) -> bool {
    text.len() == bytes * 2 && text.bytes().all(|b| matches!(b, b'0'..=b'9' | b'a'..=b'f'))
}

/// SHA-256 of `bytes`.
pub fn sha256(bytes: &[u8]) -> [u8; 32] {
    Sha256::digest(bytes).into()
}

/// SHA-256 of everything `r` gives, read in parts of 1 MiB, and how many bytes that
/// was (a file's digest and length).
pub fn sha256_reader(mut r: impl std::io::Read) -> std::io::Result<([u8; 32], u64)> {
    let mut h = Sha256::new();
    let mut buf = vec![0u8; 1 << 20];
    let mut total = 0u64;
    loop {
        let n = match r.read(&mut buf) {
            Ok(0) => break,
            Ok(n) => n,
            Err(e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
            Err(e) => return Err(e),
        };
        let Some(part) = buf.get(..n) else {
            return Err(std::io::Error::other("a read longer than its buffer"));
        };
        h.update(part);
        total = total.saturating_add(u64::try_from(n).unwrap_or(u64::MAX));
    }
    Ok((h.finalize().into(), total))
}

/// SHA-256 of `bytes` as lowercase hex (64 characters).
pub fn sha256_hex(bytes: &[u8]) -> String {
    encode(sha256(bytes))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trip_and_case() {
        assert_eq!(encode([0x00, 0x1a, 0xff]), "001aff");
        assert_eq!(encode_upper([0x00, 0x1a, 0xff]), "001AFF");
        assert_eq!(encode_sep(&[0x00, 0x1a, 0xff], ":"), "00:1a:ff");
        assert_eq!(encode_sep(&[], ":"), "");
        assert_eq!(decode("001AfF"), Some(vec![0x00, 0x1a, 0xff]));
        assert_eq!(decode_array::<3>("001aff"), Some([0x00, 0x1a, 0xff]));
    }

    #[test]
    fn what_is_not_hex_is_none() {
        assert_eq!(decode("0"), None);
        assert_eq!(decode("zz"), None);
        assert_eq!(decode("+1"), None);
        assert_eq!(decode("é0"), None);
        assert_eq!(decode_array::<2>("001aff"), None);
        assert_eq!(decode_array::<4>("001aff"), None);
        assert_eq!(decode_array::<1>("+1"), None);
        assert!(is_hex("00AAff", 3) && !is_hex("00AAff", 2) && !is_hex("00AAfg", 3));
        assert!(is_lower_hex("00aaff", 3) && !is_lower_hex("00AAff", 3));
    }

    #[test]
    fn sha256_is_the_fips_vector() {
        assert_eq!(
            sha256_hex(b"abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
        assert_eq!(encode(sha256(b"abc")), sha256_hex(b"abc"));
        let big = vec![7u8; (1 << 20) + 5];
        let (sum, len) = sha256_reader(&big[..]).unwrap();
        assert_eq!((sum, len), (sha256(&big), (1 << 20) + 5));
        assert_eq!(sha256_reader(&b""[..]).unwrap(), (sha256(b""), 0));
    }
}
