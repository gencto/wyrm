//! `~meta` — node metadata. Spec: 02-meta.

use crate::codec::canonical_str_order;
use crate::value::{encode_str_map, Value};
use minicbor::data::Type;
use minicbor::{decode, encode, Decode, Decoder, Encode, Encoder};
use std::collections::BTreeMap;

/// Permission level: 0 none, 1 list, 2 read, 3 write, 4 config.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Default)]
#[repr(u8)]
pub enum Perm {
    #[default]
    None = 0,
    List = 1,
    Read = 2,
    Write = 3,
    Config = 4,
}

impl TryFrom<u8> for Perm {
    type Error = u8;
    fn try_from(v: u8) -> Result<Self, u8> {
        Ok(match v {
            0 => Perm::None,
            1 => Perm::List,
            2 => Perm::Read,
            3 => Perm::Write,
            4 => Perm::Config,
            x => return Err(x),
        })
    }
}

/// Writable: 0 never, 1 config, 2 write.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Default)]
#[repr(u8)]
pub enum Writable {
    #[default]
    Never = 0,
    Config = 1,
    Write = 2,
}

impl TryFrom<u8> for Writable {
    type Error = u8;
    fn try_from(v: u8) -> Result<Self, u8> {
        Ok(match v {
            0 => Writable::Never,
            1 => Writable::Config,
            2 => Writable::Write,
            x => return Err(x),
        })
    }
}

/// Value type code (spec 02, key 1).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[repr(u8)]
pub enum TypeCode {
    Null = 0,
    Number = 1,
    String = 2,
    Bool = 3,
    Enum = 4,
    Map = 5,
    Array = 6,
    Binary = 7,
    Dynamic = 8,
}

impl TryFrom<u8> for TypeCode {
    type Error = u8;
    fn try_from(v: u8) -> Result<Self, u8> {
        use TypeCode::*;
        Ok(match v {
            0 => Null,
            1 => Number,
            2 => String,
            3 => Bool,
            4 => Enum,
            5 => Map,
            6 => Array,
            7 => Binary,
            8 => Dynamic,
            x => return Err(x),
        })
    }
}

/// Profile reference: interned code or full name.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum Profile {
    Code(u32),
    Name(String),
}

/// Text or interned code (unit).
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum TextOrCode {
    Text(String),
    Code(u32),
}

/// Parameter metadata inside `actions.*.params` (int keys 1/2/3 + text keys).
#[derive(Debug, Clone, PartialEq, Default)]
pub struct ParamMeta {
    pub ty: Option<TypeCode>,
    pub unit: Option<TextOrCode>,
    pub enum_values: Option<Vec<String>>,
    pub default: Option<Value>,
    pub required: Option<bool>,
}

/// Action result kind.
#[derive(Debug, Clone, PartialEq)]
pub enum ActionResult {
    Type(TypeCode),
    Stream,
    Void,
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct ActionMeta {
    pub params: BTreeMap<String, ParamMeta>,
    pub result: Option<ActionResult>,
    pub stream: Option<bool>,
    pub level: Option<Perm>,
    pub timeout_ms: Option<u32>,
}

/// Full `~meta` (spec 02). Every field optional; absent = inherited from profile.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct NodeMeta {
    pub is: Option<Profile>,
    pub ty: Option<TypeCode>,
    pub unit: Option<TextOrCode>,
    pub enum_values: Option<Vec<String>>,
    pub writable: Option<Writable>,
    pub invokable: Option<Perm>,
    pub cfg: Option<BTreeMap<String, Value>>,
    pub attr: Option<BTreeMap<String, Value>>,
    pub actions: Option<BTreeMap<String, ActionMeta>>,
    pub children: Option<Vec<String>>,
    pub rev: Option<u32>,
    pub has_children: Option<bool>,
    pub display: Option<String>,
    pub has_override: Option<bool>,
    pub children_count: Option<u32>,
    pub q: Option<u8>,
}

/// `~meta` publication: full or `{rev, patch}`.
#[derive(Debug, Clone, PartialEq)]
pub struct MetaPatch {
    pub rev: u32,
    pub patch: BTreeMap<u32, Value>,
}

// ---------- encoding ----------

fn enc_profile<W: encode::Write>(
    e: &mut Encoder<W>,
    p: &Profile,
) -> Result<(), encode::Error<W::Error>> {
    match p {
        Profile::Code(c) => e.u32(*c)?,
        Profile::Name(n) => e.str(n)?,
    };
    Ok(())
}

fn enc_toc<W: encode::Write>(
    e: &mut Encoder<W>,
    t: &TextOrCode,
) -> Result<(), encode::Error<W::Error>> {
    match t {
        TextOrCode::Code(c) => e.u32(*c)?,
        TextOrCode::Text(s) => e.str(s)?,
    };
    Ok(())
}

fn enc_str_array<W: encode::Write>(
    e: &mut Encoder<W>,
    a: &[String],
) -> Result<(), encode::Error<W::Error>> {
    e.array(a.len() as u64)?;
    for s in a {
        e.str(s)?;
    }
    Ok(())
}

impl<C> Encode<C> for ParamMeta {
    fn encode<W: encode::Write>(
        &self,
        e: &mut Encoder<W>,
        ctx: &mut C,
    ) -> Result<(), encode::Error<W::Error>> {
        let n = [
            self.ty.is_some(),
            self.unit.is_some(),
            self.enum_values.is_some(),
            self.default.is_some(),
            self.required.is_some(),
        ]
        .iter()
        .filter(|b| **b)
        .count() as u64;
        e.map(n)?;
        if let Some(t) = self.ty {
            e.u8(1)?.u8(t as u8)?;
        }
        if let Some(u) = &self.unit {
            e.u8(2)?;
            enc_toc(e, u)?;
        }
        if let Some(ev) = &self.enum_values {
            e.u8(3)?;
            enc_str_array(e, ev)?;
        }
        // text keys after int keys (canonical): "default"(7) < "required"(8)
        if let Some(d) = &self.default {
            e.str("default")?;
            d.encode(e, ctx)?;
        }
        if let Some(r) = self.required {
            e.str("required")?.bool(r)?;
        }
        Ok(())
    }
}

impl<C> Encode<C> for ActionMeta {
    fn encode<W: encode::Write>(
        &self,
        e: &mut Encoder<W>,
        ctx: &mut C,
    ) -> Result<(), encode::Error<W::Error>> {
        // keys: "level"(5) "params"(6) "result"(6) "stream"(6) "timeout_ms"(10) → canonical order
        let mut n = 1u64;
        n += self.result.is_some() as u64;
        n += self.stream.is_some() as u64;
        n += self.level.is_some() as u64;
        n += self.timeout_ms.is_some() as u64;
        e.map(n)?;
        if let Some(l) = self.level {
            e.str("level")?.u8(l as u8)?;
        }
        e.str("params")?;
        let mut keys: Vec<&String> = self.params.keys().collect();
        keys.sort_by(|a, b| canonical_str_order(a, b));
        e.map(keys.len() as u64)?;
        for k in keys {
            e.str(k)?;
            self.params[k].encode(e, ctx)?;
        }
        if let Some(r) = &self.result {
            e.str("result")?;
            match r {
                ActionResult::Type(t) => e.u8(*t as u8)?,
                ActionResult::Stream => e.str("stream")?,
                ActionResult::Void => e.str("void")?,
            };
        }
        if let Some(s) = self.stream {
            e.str("stream")?.bool(s)?;
        }
        if let Some(t) = self.timeout_ms {
            e.str("timeout_ms")?.u32(t)?;
        }
        Ok(())
    }
}

impl<C> Encode<C> for NodeMeta {
    fn encode<W: encode::Write>(
        &self,
        e: &mut Encoder<W>,
        ctx: &mut C,
    ) -> Result<(), encode::Error<W::Error>> {
        let n = [
            self.is.is_some(),
            self.ty.is_some(),
            self.unit.is_some(),
            self.enum_values.is_some(),
            self.writable.is_some(),
            self.invokable.is_some(),
            self.cfg.is_some(),
            self.attr.is_some(),
            self.actions.is_some(),
            self.children.is_some(),
            self.rev.is_some(),
            self.has_children.is_some(),
            self.display.is_some(),
            self.has_override.is_some(),
            self.children_count.is_some(),
            self.q.is_some(),
        ]
        .iter()
        .filter(|b| **b)
        .count() as u64;
        e.map(n)?;
        if let Some(v) = &self.is {
            e.u8(0)?;
            enc_profile(e, v)?;
        }
        if let Some(v) = self.ty {
            e.u8(1)?.u8(v as u8)?;
        }
        if let Some(v) = &self.unit {
            e.u8(2)?;
            enc_toc(e, v)?;
        }
        if let Some(v) = &self.enum_values {
            e.u8(3)?;
            enc_str_array(e, v)?;
        }
        if let Some(v) = self.writable {
            e.u8(4)?.u8(v as u8)?;
        }
        if let Some(v) = self.invokable {
            e.u8(5)?.u8(v as u8)?;
        }
        if let Some(v) = &self.cfg {
            e.u8(6)?;
            encode_str_map(e, ctx, v)?;
        }
        if let Some(v) = &self.attr {
            e.u8(7)?;
            encode_str_map(e, ctx, v)?;
        }
        if let Some(v) = &self.actions {
            e.u8(8)?;
            let mut keys: Vec<&String> = v.keys().collect();
            keys.sort_by(|a, b| canonical_str_order(a, b));
            e.map(keys.len() as u64)?;
            for k in keys {
                e.str(k)?;
                v[k].encode(e, ctx)?;
            }
        }
        if let Some(v) = &self.children {
            e.u8(9)?;
            enc_str_array(e, v)?;
        }
        if let Some(v) = self.rev {
            e.u8(10)?.u32(v)?;
        }
        if let Some(v) = self.has_children {
            e.u8(11)?.bool(v)?;
        }
        if let Some(v) = &self.display {
            e.u8(12)?.str(v)?;
        }
        if let Some(v) = self.has_override {
            e.u8(13)?.bool(v)?;
        }
        if let Some(v) = self.children_count {
            e.u8(14)?.u32(v)?;
        }
        if let Some(v) = self.q {
            e.u8(15)?.u8(v)?;
        }
        Ok(())
    }
}

impl<C> Encode<C> for MetaPatch {
    fn encode<W: encode::Write>(
        &self,
        e: &mut Encoder<W>,
        ctx: &mut C,
    ) -> Result<(), encode::Error<W::Error>> {
        e.map(2)?;
        e.u8(10)?.u32(self.rev)?;
        e.str("patch")?;
        e.map(self.patch.len() as u64)?;
        for (k, v) in &self.patch {
            e.u32(*k)?;
            v.encode(e, ctx)?;
        }
        Ok(())
    }
}

// ---------- decoding ----------

fn dec_profile(d: &mut Decoder<'_>) -> Result<Profile, decode::Error> {
    Ok(match d.datatype()? {
        Type::String | Type::StringIndef => Profile::Name(d.str()?.to_owned()),
        _ => Profile::Code(d.u32()?),
    })
}

fn dec_toc(d: &mut Decoder<'_>) -> Result<TextOrCode, decode::Error> {
    Ok(match d.datatype()? {
        Type::String | Type::StringIndef => TextOrCode::Text(d.str()?.to_owned()),
        _ => TextOrCode::Code(d.u32()?),
    })
}

fn dec_str_array(d: &mut Decoder<'_>) -> Result<Vec<String>, decode::Error> {
    let mut out = Vec::new();
    for s in d.array_iter::<&str>()? {
        out.push(s?.to_owned());
    }
    Ok(out)
}

fn dec_str_value_map<'b, C>(
    d: &mut Decoder<'b>,
    ctx: &mut C,
) -> Result<BTreeMap<String, Value>, decode::Error> {
    match Value::decode(d, ctx)? {
        Value::Map(m) => Ok(m),
        _ => Err(decode::Error::message("expected text-keyed map")),
    }
}

fn map_len(d: &mut Decoder<'_>) -> Result<u64, decode::Error> {
    d.map()?
        .ok_or_else(|| decode::Error::message("indefinite map not allowed here"))
}

impl<'b, C> Decode<'b, C> for ParamMeta {
    fn decode(d: &mut Decoder<'b>, ctx: &mut C) -> Result<Self, decode::Error> {
        let mut p = ParamMeta::default();
        for _ in 0..map_len(d)? {
            match d.datatype()? {
                Type::String | Type::StringIndef => match d.str()? {
                    "default" => p.default = Some(Value::decode(d, ctx)?),
                    "required" => p.required = Some(d.bool()?),
                    _ => d.skip()?,
                },
                _ => match d.u32()? {
                    1 => p.ty = Some(TypeCode::try_from(d.u8()?).map_err(bad("type"))?),
                    2 => p.unit = Some(dec_toc(d)?),
                    3 => p.enum_values = Some(dec_str_array(d)?),
                    _ => d.skip()?,
                },
            }
        }
        Ok(p)
    }
}

impl<'b, C> Decode<'b, C> for ActionMeta {
    fn decode(d: &mut Decoder<'b>, ctx: &mut C) -> Result<Self, decode::Error> {
        let mut a = ActionMeta::default();
        for _ in 0..map_len(d)? {
            match d.str()? {
                "params" => {
                    for _ in 0..map_len(d)? {
                        let k = d.str()?.to_owned();
                        a.params.insert(k, ParamMeta::decode(d, ctx)?);
                    }
                }
                "result" => {
                    a.result = Some(match d.datatype()? {
                        Type::String | Type::StringIndef => match d.str()? {
                            "stream" => ActionResult::Stream,
                            "void" => ActionResult::Void,
                            other => {
                                return Err(decode::Error::message(format!(
                                    "bad action result {other}"
                                )))
                            }
                        },
                        _ => ActionResult::Type(TypeCode::try_from(d.u8()?).map_err(bad("type"))?),
                    })
                }
                "stream" => a.stream = Some(d.bool()?),
                "level" => a.level = Some(Perm::try_from(d.u8()?).map_err(bad("level"))?),
                "timeout_ms" => a.timeout_ms = Some(d.u32()?),
                _ => d.skip()?,
            }
        }
        Ok(a)
    }
}

impl<'b, C> Decode<'b, C> for NodeMeta {
    fn decode(d: &mut Decoder<'b>, ctx: &mut C) -> Result<Self, decode::Error> {
        let mut m = NodeMeta::default();
        for _ in 0..map_len(d)? {
            match d.u32()? {
                0 => m.is = Some(dec_profile(d)?),
                1 => m.ty = Some(TypeCode::try_from(d.u8()?).map_err(bad("type"))?),
                2 => m.unit = Some(dec_toc(d)?),
                3 => m.enum_values = Some(dec_str_array(d)?),
                4 => m.writable = Some(Writable::try_from(d.u8()?).map_err(bad("writable"))?),
                5 => m.invokable = Some(Perm::try_from(d.u8()?).map_err(bad("invokable"))?),
                6 => m.cfg = Some(dec_str_value_map(d, ctx)?),
                7 => m.attr = Some(dec_str_value_map(d, ctx)?),
                8 => {
                    let mut acts = BTreeMap::new();
                    for _ in 0..map_len(d)? {
                        let k = d.str()?.to_owned();
                        acts.insert(k, ActionMeta::decode(d, ctx)?);
                    }
                    m.actions = Some(acts);
                }
                9 => m.children = Some(dec_str_array(d)?),
                10 => m.rev = Some(d.u32()?),
                11 => m.has_children = Some(d.bool()?),
                12 => m.display = Some(d.str()?.to_owned()),
                13 => m.has_override = Some(d.bool()?),
                14 => m.children_count = Some(d.u32()?),
                15 => m.q = Some(d.u8()?),
                _ => d.skip()?,
            }
        }
        Ok(m)
    }
}

impl<'b, C> Decode<'b, C> for MetaPatch {
    fn decode(d: &mut Decoder<'b>, ctx: &mut C) -> Result<Self, decode::Error> {
        let mut rev = None;
        let mut patch = BTreeMap::new();
        for _ in 0..map_len(d)? {
            match d.datatype()? {
                Type::String | Type::StringIndef => {
                    if d.str()? == "patch" {
                        for _ in 0..map_len(d)? {
                            let k = d.u32()?;
                            patch.insert(k, Value::decode(d, ctx)?);
                        }
                    } else {
                        d.skip()?;
                    }
                }
                _ => {
                    if d.u32()? == 10 {
                        rev = Some(d.u32()?);
                    } else {
                        d.skip()?;
                    }
                }
            }
        }
        Ok(MetaPatch {
            rev: rev.ok_or_else(|| decode::Error::message("patch without rev"))?,
            patch,
        })
    }
}

fn bad(what: &'static str) -> impl Fn(u8) -> decode::Error {
    move |x| decode::Error::message(format!("bad {what} code {x}"))
}
