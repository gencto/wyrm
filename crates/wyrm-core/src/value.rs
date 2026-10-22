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
}

#[cfg(test)]
mod tests {
    use super::*;

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
