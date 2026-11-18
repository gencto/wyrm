//! The broker's certificate keys: ECDSA P-256, made and used with the one random
//! source (docs/rust-rules.md §10).
//!
//! `rcgen::KeyPair` opens a random source of its own to make a key, to read one and
//! for every signature. rcgen signs with any [`rcgen::SigningKey`], so the CA, the
//! leaf keys and the broker keys are an [`EcKey`] instead: ring makes the key pair
//! and each signature with `wyrm_core::rand::secure_random()`. The formats are the
//! ones `rcgen::KeyPair::generate()` wrote: the same curve and algorithm
//! (`PKCS_ECDSA_P256_SHA256`, signatures in ASN.1 DER), the key as PKCS#8 in a
//! `PRIVATE KEY` PEM block of 64-column lines. A key file written before this type
//! reads as before, and rcgen reads a file this type writes.

use base64::Engine;
use ring::signature::{EcdsaKeyPair, ECDSA_P256_SHA256_ASN1_SIGNING};
use rustls_pki_types::pem::PemObject;
use rustls_pki_types::PrivatePkcs8KeyDer;
use zeroize::Zeroizing;

/// Why a key could not be made, read or used. Never carries key bytes.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum EcKeyError {
    #[error("no key made: the random source failed")]
    Generate,
    #[error("not a PKCS#8 private key in PEM: {0}")]
    Pem(String),
    #[error("not an ECDSA P-256 key: {0}")]
    Rejected(String),
    #[error("no signature made: the random source failed")]
    Sign,
}

/// An ECDSA P-256 key pair for certificates.
pub struct EcKey {
    pair: EcdsaKeyPair,
    pkcs8: Zeroizing<Vec<u8>>,
}

impl EcKey {
    /// A new key from the one random source.
    pub fn generate() -> Result<Self, EcKeyError> {
        let rng = wyrm_core::rand::secure_random();
        let doc = EcdsaKeyPair::generate_pkcs8(&ECDSA_P256_SHA256_ASN1_SIGNING, &rng)
            .map_err(|ring::error::Unspecified| EcKeyError::Generate)?;
        Self::from_pkcs8(doc.as_ref())
    }

    /// The key of a `PRIVATE KEY` PEM block (what [`Self::pem`] and rcgen write).
    pub fn from_pem(pem: &str) -> Result<Self, EcKeyError> {
        let der = PrivatePkcs8KeyDer::from_pem_slice(pem.as_bytes())
            .map_err(|e| EcKeyError::Pem(e.to_string()))?;
        Self::from_pkcs8(der.secret_pkcs8_der())
    }

    fn from_pkcs8(der: &[u8]) -> Result<Self, EcKeyError> {
        let rng = wyrm_core::rand::secure_random();
        let pair = EcdsaKeyPair::from_pkcs8(&ECDSA_P256_SHA256_ASN1_SIGNING, der, &rng)
            .map_err(|e| EcKeyError::Rejected(e.to_string()))?;
        Ok(Self {
            pair,
            pkcs8: Zeroizing::new(der.to_vec()),
        })
    }

    /// The private key as a `PRIVATE KEY` PEM block: base64 in lines of 64, `\n` ends.
    pub fn pem(&self) -> Zeroizing<String> {
        let b64 = Zeroizing::new(base64::engine::general_purpose::STANDARD.encode(&*self.pkcs8));
        let mut out = Zeroizing::new(String::with_capacity(b64.len() + 80));
        out.push_str("-----BEGIN PRIVATE KEY-----\n");
        let mut rest = b64.as_str();
        while !rest.is_empty() {
            // base64 is ASCII: every byte index is a character boundary
            let (line, tail) = rest.split_at(rest.len().min(64));
            out.push_str(line);
            out.push('\n');
            rest = tail;
        }
        out.push_str("-----END PRIVATE KEY-----\n");
        out
    }
}

impl rcgen::PublicKeyData for EcKey {
    fn der_bytes(&self) -> &[u8] {
        // ring's trait method, by its path: the type is not rcgen's `KeyPair`
        ring::signature::KeyPair::public_key(&self.pair).as_ref()
    }

    fn algorithm(&self) -> &'static rcgen::SignatureAlgorithm {
        &rcgen::PKCS_ECDSA_P256_SHA256
    }
}

impl rcgen::SigningKey for EcKey {
    fn sign(&self, msg: &[u8]) -> Result<Vec<u8>, rcgen::Error> {
        let rng = wyrm_core::rand::secure_random();
        self.pair
            .sign(&rng, msg)
            .map(|s| s.as_ref().to_vec())
            .map_err(|ring::error::Unspecified| rcgen::Error::RingUnspecified)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use rcgen::{PublicKeyData, SigningKey};
    use ring::signature::{UnparsedPublicKey, ECDSA_P256_SHA256_ASN1};

    #[test]
    fn a_key_rcgen_made_reads_and_writes_back_the_same_pem() {
        // what `ca.key`, `<name>.key` and a broker key held before this type
        let old = rcgen::KeyPair::generate().unwrap();
        let pem = old.serialize_pem();
        let key = EcKey::from_pem(&pem).unwrap();
        assert_eq!(*key.pem(), pem);
        assert_eq!(key.subject_public_key_info(), old.subject_public_key_info());
        assert_eq!(key.algorithm(), old.algorithm());
    }

    #[test]
    fn rcgen_reads_a_key_made_here_as_the_same_key() {
        let key = EcKey::generate().unwrap();
        let theirs = rcgen::KeyPair::from_pem(&key.pem()).unwrap();
        assert_eq!(theirs.serialize_pem(), *key.pem());
        assert_eq!(
            theirs.subject_public_key_info(),
            key.subject_public_key_info()
        );
        assert!(theirs.is_compatible(&rcgen::PKCS_ECDSA_P256_SHA256));
        // two keys differ: the source is read
        assert_ne!(*EcKey::generate().unwrap().pem(), *key.pem());
    }

    #[test]
    fn a_signature_verifies_under_the_public_key() {
        let key = EcKey::generate().unwrap();
        let sig = key.sign(b"to be signed").unwrap();
        let public = UnparsedPublicKey::new(&ECDSA_P256_SHA256_ASN1, key.der_bytes());
        public.verify(b"to be signed", &sig).unwrap();
        assert!(public.verify(b"another text", &sig).is_err());
    }

    #[test]
    fn what_is_not_a_p256_pkcs8_key_is_refused() {
        assert!(matches!(EcKey::from_pem(""), Err(EcKeyError::Pem(_))));
        assert!(matches!(
            EcKey::from_pem("-----BEGIN CERTIFICATE-----\nAAAA\n-----END CERTIFICATE-----\n"),
            Err(EcKeyError::Pem(_))
        ));
        let ed = rcgen::KeyPair::generate_for(&rcgen::PKCS_ED25519).unwrap();
        assert!(matches!(
            EcKey::from_pem(&ed.serialize_pem()),
            Err(EcKeyError::Rejected(_))
        ));
    }
}
