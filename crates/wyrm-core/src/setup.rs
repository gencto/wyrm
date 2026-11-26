//! The one-time setup code of a new broker (ADR 0051 §3 "First admin"): the pure part,
//! shared by the gateway (which takes the code), `wyr image build` (which makes one for an
//! image) and a client (which checks the proof before it sends the code).
//!
//! The code is 16 random bytes shown as RFC 4648 base32 without padding (26 characters) in
//! groups of four; its hash is SHA-256 over [`LABEL`] and the 16 bytes. A board image
//! carries only the hash, never the code.
//!
//! The code also proves the server to the client: [`setup_proof`] is HMAC-SHA-256 keyed
//! with the hash over [`PROOF_LABEL`] and the DER of the CA the gateway presents, and a
//! client checks it from the typed code ([`verify_setup_proof`]) before it sends the code.
//! Only who holds the hash can make a proof for a CA, so the hash is kept like a secret of
//! the image.
//!
//! Nothing here reads a clock or a file. [`code_of`] takes the bytes from its caller, so it
//! builds for wasm32; [`new_code`] (feature `rand`) takes them from the OS. Neither the code
//! nor its hash is ever logged.

use data_encoding::BASE32_NOPAD;
use zeroize::Zeroizing;

/// The bytes of a setup code.
pub const CODE_BYTES: usize = 16;
/// The base32 characters of a setup code (RFC 4648, no padding).
pub const CODE_CHARS: usize = 26;
/// What the hash is taken over before the code's bytes.
pub const LABEL: &[u8] = b"wyrm-setup-v1\n";
/// What the setup proof is taken over before the CA's DER.
pub const PROOF_LABEL: &[u8] = b"wyrm-setup-proof-v1\n";
/// Longer input is no code, however it is spaced: refused before it is read.
const MAX_INPUT: usize = 128;

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

/// The text of the code made of `bytes` (groups of four characters joined by `-`) and its
/// hash. The bytes are the caller's randomness: 16 bytes from the OS, or from the host of a
/// build that has no OS source.
pub fn code_of(bytes: &[u8; CODE_BYTES]) -> (String, [u8; 32]) {
    let plain = Zeroizing::new(BASE32_NOPAD.encode(bytes));
    let mut code = String::with_capacity(CODE_CHARS + CODE_CHARS / 4);
    for (i, c) in plain.chars().enumerate() {
        if i > 0 && i % 4 == 0 {
            code.push('-');
        }
        code.push(c);
    }
    (code, hash_of(bytes))
}

/// A new setup code: 16 bytes from the OS, as [`code_of`] writes them, and its hash. Fails
/// when the OS gives no randomness.
#[cfg(feature = "rand")]
pub fn new_code() -> Result<(String, [u8; 32]), crate::rand::NoRandomness> {
    let bytes = Zeroizing::new(crate::rand::bytes::<CODE_BYTES>()?);
    Ok(code_of(&bytes))
}

/// SHA-256 over [`LABEL`] and the code's bytes.
fn hash_of(bytes: &[u8; CODE_BYTES]) -> [u8; 32] {
    crate::hex::sha256_parts(&[LABEL, bytes])
}

/// The proof `/api/info` carries while a setup is pending: HMAC-SHA-256 keyed with the
/// setup `hash` over [`PROOF_LABEL`] and `ca_der`, the DER of the CA the gateway presents
/// (the bytes of `info.ca`).
pub fn setup_proof(hash: &[u8; 32], ca_der: &[u8]) -> [u8; 32] {
    use hmac::Mac;
    let mut m = crate::mac::hmac_sha256(hash);
    m.update(PROOF_LABEL);
    m.update(ca_der);
    m.finalize().into_bytes().into()
}

/// For a client before it sends the code: `proof` (`info.setup_proof`) was made for the CA
/// in `ca_der` (`info.ca`) by who holds the hash of `code` (typed as [`code_hash`] reads
/// it). `false` for a code that is not one, or a proof of another length. Constant time in
/// the proof.
pub fn verify_setup_proof(code: &str, ca_der: &[u8], proof: &[u8]) -> bool {
    use subtle::ConstantTimeEq;
    let Some(hash) = code_hash(code).map(Zeroizing::new) else {
        return false;
    };
    let want = setup_proof(&hash, ca_der);
    bool::from(want[..].ct_eq(proof))
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A code made of fixed bytes: these tests need no OS randomness.
    fn new_code() -> Result<(String, [u8; 32]), std::convert::Infallible> {
        Ok(code_of(&[
            0x3f, 0x0a, 0x9c, 0x1e, 0x5b, 0x7d, 0x24, 0x68, 0xac, 0xe0, 0x13, 0x57, 0x9b, 0xdf,
            0x02, 0x46,
        ]))
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
            crate::hex::sha256_parts(&[b"wyrm-setup-v1\n", &bytes])
        );
    }

    /// The proof of the spec: HMAC-SHA-256 keyed with the hash over the label and the CA's
    /// DER; a client verifies it from the code alone.
    #[test]
    fn setup_proof_is_the_spec() {
        use hmac::Mac;
        let (code, hash) = new_code().unwrap();
        let ca = b"the DER of a CA".as_slice();
        let mut m = <hmac::Hmac<sha2::Sha256> as Mac>::new_from_slice(&hash).unwrap();
        m.update(b"wyrm-setup-proof-v1\n");
        m.update(ca);
        let want: [u8; 32] = m.finalize().into_bytes().into();
        assert_eq!(setup_proof(&hash, ca), want);
        assert!(verify_setup_proof(&code, ca, &want));
        assert!(!verify_setup_proof(&code, b"another CA", &want));
        let mut flipped = want;
        flipped[0] ^= 1;
        assert!(!verify_setup_proof(&code, ca, &flipped));
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
        assert_ne!(code_of(&[7; CODE_BYTES]).0, code);
    }
}
