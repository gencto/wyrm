//! `~val` payload and the dynamic `Value` type. Spec: 03-val.

use crate::codec::{canonical_str_order, encode_float};
use minicbor::data::Type;
use minicbor::{decode, encode, Decode, Decoder, Encode, Encoder};
use std::collections::BTreeMap;

crate::wire_enum! {
    /// Value quality (spec 03-val, key 1).
    #[derive(Default)]
    pub enum Quality {
        #[default]
        Good = 0 => "good",
        Uncertain = 1 => "uncertain",
        Bad = 2 => "bad",
    }
}

/// Dynamic value — the CBOR data model restricted to what `~meta.type` allows.
#[derive(Debug, Clone, PartialEq)]
pub enum Value {
    Null,
    Bool(bool),
    Int(i64),
    UInt(u64),
    Float(f64),
    Str(String),
    Bytes(Vec<u8>),
    Array(Vec<Value>),
    /// Text-keyed map (user content: `cfg`, `attr`, action params).
    Map(BTreeMap<String, Value>),
}

impl From<f64> for Value {
    fn from(v: f64) -> Self {
        Value::Float(v)
    }
}
impl From<i64> for Value {
    fn from(v: i64) -> Self {
        if v >= 0 {
            Value::UInt(v as u64)
        } else {
            Value::Int(v)
        }
    }
}
impl From<u64> for Value {
    fn from(v: u64) -> Self {
        Value::UInt(v)
    }
}
impl From<bool> for Value {
    fn from(v: bool) -> Self {
        Value::Bool(v)
    }
}
impl From<&str> for Value {
    fn from(v: &str) -> Self {
        Value::Str(v.to_owned())
    }
}
impl From<String> for Value {
    fn from(v: String) -> Self {
        Value::Str(v)
    }
}
impl From<Vec<u8>> for Value {
    fn from(v: Vec<u8>) -> Self {
        Value::Bytes(v)
    }
}

impl<C> Encode<C> for Value {
    fn encode<W: encode::Write>(
        &self,
        e: &mut Encoder<W>,
        ctx: &mut C,
    ) -> Result<(), encode::Error<W::Error>> {
        match self {
            Value::Null => {
                e.null()?;
            }
            Value::Bool(b) => {
                e.bool(*b)?;
            }
            Value::Int(i) => {
                e.i64(*i)?;
            }
            Value::UInt(u) => {
                e.u64(*u)?;
            }
            Value::Float(f) => encode_float(e, *f)?,
            Value::Str(s) => {
                e.str(s)?;
            }
            Value::Bytes(b) => {
                e.bytes(b)?;
            }
            Value::Array(a) => {
                e.array(a.len() as u64)?;
                for v in a {
                    v.encode(e, ctx)?;
                }
            }
            Value::Map(m) => encode_str_map(e, ctx, m)?,
        }
        Ok(())
    }
}

/// Encode a text-keyed map in canonical key order.
pub fn encode_str_map<W: encode::Write, C>(
    e: &mut Encoder<W>,
    ctx: &mut C,
    m: &BTreeMap<String, Value>,
) -> Result<(), encode::Error<W::Error>> {
    let mut keys: Vec<&String> = m.keys().collect();
    keys.sort_by(|a, b| canonical_str_order(a, b));
    e.map(keys.len() as u64)?;
    for k in keys {
        e.str(k)?;
        m[k].encode(e, ctx)?;
    }
    Ok(())
}

/// Deepest nesting of arrays, maps and tags in one [`Value`] (spec README,
/// rule 6): input from anyone cannot make the decoder recurse past it.
pub const MAX_DEPTH: usize = 32;

impl<'b, C> Decode<'b, C> for Value {
    fn decode(d: &mut Decoder<'b>, _ctx: &mut C) -> Result<Self, decode::Error> {
        decode_value(d, 0)
    }
}

fn decode_value(d: &mut Decoder<'_>, depth: usize) -> Result<Value, decode::Error> {
    if depth > MAX_DEPTH {
        return Err(decode::Error::message(format!(
            "nesting deeper than {MAX_DEPTH}"
        )));
    }
    {
        Ok(match d.datatype()? {
            Type::Null | Type::Undefined => {
                d.skip()?;
                Value::Null
            }
            Type::Bool => Value::Bool(d.bool()?),
            Type::U8 | Type::U16 | Type::U32 | Type::U64 => Value::UInt(d.u64()?),
            Type::I8 | Type::I16 | Type::I32 | Type::I64 | Type::Int => Value::Int(d.i64()?),
            Type::F16 => Value::Float(d.f16()? as f64),
            Type::F32 => Value::Float(d.f32()? as f64),
            Type::F64 => Value::Float(d.f64()?),
            Type::String | Type::StringIndef => Value::Str(decode_str(d)?),
            Type::Bytes | Type::BytesIndef => Value::Bytes(decode_bytes(d)?),
            Type::Array | Type::ArrayIndef => {
                // No capacity from the header: it is the sender's claim.
                let mut out = Vec::new();
                match d.array()? {
                    Some(n) => {
                        for _ in 0..n {
                            out.push(decode_value(d, depth + 1)?);
                        }
                    }
                    None => loop {
                        if d.datatype()? == Type::Break {
                            d.skip()?;
                            break;
                        }
                        out.push(decode_value(d, depth + 1)?);
                    },
                }
                Value::Array(out)
            }
            Type::Map | Type::MapIndef => {
                let mut out = BTreeMap::new();
                let n = d.map()?;
                let mut i = 0u64;
                loop {
                    if let Some(n) = n {
                        if i >= n {
                            break;
                        }
                    } else if d.datatype()? == Type::Break {
                        d.skip()?;
                        break;
                    }
                    let k = decode_str(d)?;
                    let v = decode_value(d, depth + 1)?;
                    out.insert(k, v);
                    i += 1;
                }
                Value::Map(out)
            }
            Type::Tag => {
                d.tag()?;
                decode_value(d, depth + 1)?
            }
            t => return Err(decode::Error::message(format!("unsupported CBOR type {t}"))),
        })
    }
}

fn decode_str(d: &mut Decoder<'_>) -> Result<String, decode::Error> {
    let mut s = String::new();
    for part in d.str_iter()? {
        s.push_str(part?);
    }
    Ok(s)
}

fn decode_bytes(d: &mut Decoder<'_>) -> Result<Vec<u8>, decode::Error> {
    let mut b = Vec::new();
    for part in d.bytes_iter()? {
        b.extend_from_slice(part?);
    }
    Ok(b)
}

/// `~val` payload: `{0: v, 1: q, 2: t}` (spec 03-val).
#[derive(Debug, Clone, PartialEq)]
pub struct Sample {
    pub v: Value,
    pub q: Quality,
    /// Source timestamp, microseconds since Unix epoch (uhlc).
    pub t: u64,
}

impl<C> Encode<C> for Sample {
    fn encode<W: encode::Write>(
        &self,
        e: &mut Encoder<W>,
        ctx: &mut C,
    ) -> Result<(), encode::Error<W::Error>> {
        e.map(3)?;
        e.u8(0)?;
        self.v.encode(e, ctx)?;
        e.u8(1)?.u8(self.q.code())?;
        e.u8(2)?.u64(self.t)?;
        Ok(())
    }
}

impl<'b, C> Decode<'b, C> for Sample {
    fn decode(d: &mut Decoder<'b>, ctx: &mut C) -> Result<Self, decode::Error> {
        let mut v = Value::Null;
        let mut q = Quality::Good;
        let mut t = 0u64;
        for _ in 0..d
            .map()?
            .ok_or_else(|| decode::Error::message("indefinite ~val map"))?
        {
            match d.u32()? {
                0 => v = Value::decode(d, ctx)?,
                1 => {
                    q = Quality::try_from(d.u8()?)
                        .map_err(|x| decode::Error::message(format!("bad quality {x}")))?
                }
                2 => t = d.u64()?,
                _ => d.skip()?,
            }
        }
        Ok(Sample { v, q, t })
    }
}

/// One row of a history answer (`get ~val?history=`, spec 03): a sample
/// `[t, v, q]`, or with `agg` a rollup `[t_start, v]` (no quality).
#[derive(Debug, Clone, PartialEq)]
pub struct HistRow {
    /// Microseconds since the Unix epoch: the sample's time, or the start
    /// of its window.
    pub t: u64,
    pub v: Value,
    /// `None` for a rollup row.
    pub q: Option<Quality>,
}

impl<C> Encode<C> for HistRow {
    fn encode<W: encode::Write>(
        &self,
        e: &mut Encoder<W>,
        ctx: &mut C,
    ) -> Result<(), encode::Error<W::Error>> {
        e.array(if self.q.is_some() { 3 } else { 2 })?;
        e.u64(self.t)?;
        self.v.encode(e, ctx)?;
        if let Some(q) = self.q {
            e.u8(q.code())?;
        }
        Ok(())
    }
}

impl<'b, C> Decode<'b, C> for HistRow {
    fn decode(d: &mut Decoder<'b>, ctx: &mut C) -> Result<Self, decode::Error> {
        let n = d
            .array()?
            .ok_or_else(|| decode::Error::message("indefinite history row"))?;
        if !(2..=3).contains(&n) {
            return Err(decode::Error::message(format!(
                "history row of {n} items (2 or 3)"
            )));
        }
        let t = d.u64()?;
        let v = Value::decode(d, ctx)?;
        let q = if n == 3 {
            Some(
                Quality::try_from(d.u8()?)
                    .map_err(|x| decode::Error::message(format!("bad quality {x}")))?,
            )
        } else {
            None
        };
        Ok(HistRow { t, v, q })
    }
}

/// `~set` request payload: `{0: v}` (spec 05-methods).
#[derive(Debug, Clone, PartialEq)]
pub struct SetRequest {
    pub v: Value,
}

impl<C> Encode<C> for SetRequest {
    fn encode<W: encode::Write>(
        &self,
        e: &mut Encoder<W>,
        ctx: &mut C,
    ) -> Result<(), encode::Error<W::Error>> {
        e.map(1)?.u8(0)?;
        self.v.encode(e, ctx)
    }
}

impl<'b, C> Decode<'b, C> for SetRequest {
    fn decode(d: &mut Decoder<'b>, ctx: &mut C) -> Result<Self, decode::Error> {
        let mut v = None;
        for _ in 0..d
            .map()?
            .ok_or_else(|| decode::Error::message("indefinite ~set map"))?
        {
            match d.u32()? {
                0 => v = Some(Value::decode(d, ctx)?),
                _ => d.skip()?,
            }
        }
        Ok(SetRequest {
            v: v.ok_or_else(|| decode::Error::message("~set without v"))?,
        })
    }
}

impl Value {
    /// Numeric view for range checks; `None` for non-numbers.
    pub fn as_f64(&self) -> Option<f64> {
        match self {
            Value::Int(i) => Some(*i as f64),
            Value::UInt(u) => Some(*u as f64),
            Value::Float(f) => Some(*f),
            _ => None,
        }
    }

    /// The value as a whole number of type `T`: the one integer decoder of the
    /// workspace for action arguments, configuration and wire fields.
    ///
    /// An integer (`UInt`, `Int`) is taken as it is; a float is taken only when
    /// it is a whole number a JSON client may have written as `20.0` (see
    /// [`whole`]). A fraction, NaN, an infinity, a number out of `T`'s range
    /// (a negative one for an unsigned `T`) or a value that is no number is an
    /// error, never a truncated, saturated or zero value: `0.5 as u32` is `0`,
    /// which in a token's count means "no limit".
    pub fn to_int<T: TryFrom<i128>>(&self) -> Result<T, IntError> {
        let n = match *self {
            Value::UInt(u) => i128::from(u),
            Value::Int(i) => i128::from(i),
            Value::Float(f) => i128::from(whole(f)?),
            _ => return Err(IntError::NotANumber),
        };
        match T::try_from(n) {
            Ok(v) => Ok(v),
            Err(_) if n < 0 => Err(IntError::Negative),
            Err(_) => Err(IntError::OutOfRange),
        }
    }
}

/// Why a value is not a whole number of the wanted type ([`Value::to_int`], [`whole`]).
#[derive(Debug, Clone, Copy, PartialEq, Eq, thiserror::Error)]
pub enum IntError {
    #[error("not a number")]
    NotANumber,
    #[error("not a finite number")]
    NotFinite,
    #[error("not a whole number")]
    Fractional,
    #[error("a negative number")]
    Negative,
    #[error("out of range")]
    OutOfRange,
}

/// The largest float magnitude that still holds every integer exactly (2^53).
pub const MAX_EXACT_FLOAT: f64 = 9_007_199_254_740_992.0;

/// A float as the whole number it holds: finite, no fraction and at most
/// [`MAX_EXACT_FLOAT`] in magnitude (above it a float no longer holds every
/// integer, so `2^53 + 1` would read as `2^53`). Anything else is an error.
///
/// For a float that the code itself made from a float input (seconds × 1000
/// rounded), this is the conversion; never `as`, which truncates, saturates
/// and makes NaN a `0`.
pub fn whole(f: f64) -> Result<i64, IntError> {
    if !f.is_finite() {
        return Err(IntError::NotFinite);
    }
    if f.fract() != 0.0 {
        return Err(IntError::Fractional);
    }
    if f.abs() > MAX_EXACT_FLOAT {
        return Err(IntError::OutOfRange);
    }
    // A whole number of at most 54 bits, read from its IEEE 754 fields: the
    // value is `mantissa * 2^(exponent - 1075)`, and the bits shifted out to the
    // right are zero because the number has no fraction.
    let bits = f.to_bits();
    let exponent = (bits >> 52) & 0x7ff;
    if exponent == 0 {
        // ±0 (a subnormal is a fraction and was refused above)
        return Ok(0);
    }
    let mantissa = (bits & ((1 << 52) - 1)) | (1 << 52);
    let magnitude = if exponent >= 1075 {
        mantissa << (exponent - 1075)
    } else {
        mantissa >> (1075 - exponent)
    };
    // below 2^53 it always fits; kept as an error, not a panic
    let magnitude = i64::try_from(magnitude).ok().ok_or(IntError::OutOfRange)?;
    Ok(if bits >> 63 == 1 {
        -magnitude
    } else {
        magnitude
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn whole_numbers_decode_exactly_and_nothing_else_does() {
        use IntError::*;
        let f = |x: f64| Value::Float(x);
        // taken
        assert_eq!(Value::UInt(7).to_int::<u32>(), Ok(7));
        assert_eq!(Value::Int(-7).to_int::<i32>(), Ok(-7));
        assert_eq!(f(20.0).to_int::<u32>(), Ok(20));
        assert_eq!(f(-0.0).to_int::<u8>(), Ok(0));
        assert_eq!(f(-3.0).to_int::<i8>(), Ok(-3));
        assert_eq!(f(MAX_EXACT_FLOAT).to_int::<u64>(), Ok(1 << 53));
        assert_eq!(f(-MAX_EXACT_FLOAT).to_int::<i64>(), Ok(-(1 << 53)));
        assert_eq!(Value::UInt(u64::MAX).to_int::<u64>(), Ok(u64::MAX));
        assert_eq!(Value::Int(i64::MIN).to_int::<i64>(), Ok(i64::MIN));
        // refused: the inputs `as` turned into 0, 1 or a saturated number
        assert_eq!(f(0.5).to_int::<u32>(), Err(Fractional));
        assert_eq!(f(1.7).to_int::<u32>(), Err(Fractional));
        assert_eq!(f(f64::MIN_POSITIVE / 2.0).to_int::<u32>(), Err(Fractional));
        assert_eq!(f(f64::NAN).to_int::<u32>(), Err(NotFinite));
        assert_eq!(f(f64::INFINITY).to_int::<u64>(), Err(NotFinite));
        assert_eq!(f(-1.0).to_int::<u32>(), Err(Negative));
        assert_eq!(Value::Int(-1).to_int::<u64>(), Err(Negative));
        assert_eq!(f(5e9).to_int::<u32>(), Err(OutOfRange));
        assert_eq!(Value::UInt(256).to_int::<u8>(), Err(OutOfRange));
        // above 2^53 a float no longer holds every integer: 2^53 + 2 and 2^64
        // (which `<= u64::MAX as f64` let through and `as` saturated) are refused
        assert_eq!(f(MAX_EXACT_FLOAT + 2.0).to_int::<u64>(), Err(OutOfRange));
        assert_eq!(
            f(18_446_744_073_709_551_616.0).to_int::<u64>(),
            Err(OutOfRange)
        );
        assert_eq!(Value::Str("1".into()).to_int::<u32>(), Err(NotANumber));
        assert_eq!(Value::Bool(true).to_int::<u32>(), Err(NotANumber));
        assert_eq!(Value::Null.to_int::<u32>(), Err(NotANumber));
    }

    #[test]
    fn whole_reads_every_exact_float_as_its_integer() {
        // every power of two and its neighbours up to 2^53, both signs, against
        // the exact integer (test code may use `as` on a known whole number)
        for e in 0..=53u32 {
            let p = 1i64 << e;
            for n in [p - 1, p, p + 1] {
                if n.unsigned_abs() > 1 << 53 {
                    continue;
                }
                for n in [n, -n] {
                    assert_eq!(whole(n as f64), Ok(n), "{n}");
                }
            }
        }
        let mut x = 0x2545_f491_4f6c_dd1du64;
        for _ in 0..100_000 {
            x ^= x << 13;
            x ^= x >> 7;
            x ^= x << 17;
            let n = (x >> 11) as i64 * if x & 1 == 0 { 1 } else { -1 };
            assert_eq!(whole(n as f64), Ok(n), "{n}");
        }
    }

    /// `depth` nested one-element arrays around a null.
    fn nested(depth: usize, head: u8) -> Vec<u8> {
        let mut b = vec![head; depth];
        b.push(0xf6);
        b
    }

    #[test]
    fn nesting_is_bounded() {
        let ok: Value = crate::codec::from_slice(&nested(MAX_DEPTH, 0x81)).unwrap();
        assert!(matches!(ok, Value::Array(_)));
        for head in [0x81, 0x9f, 0xc0] {
            // array, indefinite array, tag
            let mut deep = nested(MAX_DEPTH + 1, head);
            if head == 0x9f {
                deep.extend(std::iter::repeat_n(0xff, MAX_DEPTH + 1));
            }
            assert!(
                crate::codec::from_slice::<Value>(&deep).is_err(),
                "{head:#x}"
            );
        }
        // far past the limit: refused, not a stack overflow
        assert!(crate::codec::from_slice::<Value>(&nested(1_000_000, 0x81)).is_err());
        let mut map = Vec::new();
        for _ in 0..=MAX_DEPTH {
            map.extend([0xa1, 0x61, b'k']);
        }
        map.push(0xf6);
        assert!(crate::codec::from_slice::<Value>(&map).is_err());
    }
}
