//! CBOR encode/decode helpers.
//!
//! We emit canonical CBOR (RFC 8949 §4.2.1): integer map keys ascending,
//! text map keys ordered by their encoded bytes (length first, then
//! bytewise), floats in the shortest lossless form. Decoders accept any
//! well-formed CBOR.

use minicbor::{decode, encode, Decode, Decoder, Encode, Encoder};

#[derive(Debug, thiserror::Error)]
pub enum CodecError {
    #[error("cbor decode: {0}")]
    Decode(String),
    #[error("cbor encode: {0}")]
    Encode(String),
}

pub type Result<T> = core::result::Result<T, CodecError>;

pub fn to_vec<T: Encode<()>>(v: &T) -> Result<Vec<u8>> {
    minicbor::to_vec(v).map_err(|e| CodecError::Encode(e.to_string()))
}

pub fn from_slice<'b, T: Decode<'b, ()>>(bytes: &'b [u8]) -> Result<T> {
    minicbor::decode(bytes).map_err(|e| CodecError::Decode(e.to_string()))
}

/// Shortest lossless float: f16 → f32 → f64.
pub fn encode_float<W: encode::Write>(
    e: &mut Encoder<W>,
    v: f64,
) -> core::result::Result<(), encode::Error<W::Error>> {
    let as32 = v as f32;
    if as32 as f64 == v || (v.is_nan() && as32.is_nan()) {
        let as16 = half::f16::from_f32(as32);
        if as16.to_f32() == as32 || (as32.is_nan() && as16.is_nan()) {
            e.f16(as32)?;
        } else {
            e.f32(as32)?;
        }
    } else {
        e.f64(v)?;
    }
    Ok(())
}

/// Canonical order for text keys: by encoded length, then bytewise.
pub fn canonical_str_order(a: &str, b: &str) -> core::cmp::Ordering {
    a.len()
        .cmp(&b.len())
        .then_with(|| a.as_bytes().cmp(b.as_bytes()))
}

/// Skip one CBOR item (used for unknown keys — forward compatibility).
pub fn skip<'b>(d: &mut Decoder<'b>) -> core::result::Result<(), decode::Error> {
    d.skip()
}
