//! `~meta` — node metadata. Spec: 02-meta.

use crate::codec::canonical_str_order;
use crate::value::{encode_str_map, Value};
use minicbor::data::Type;
use minicbor::{decode, encode, Decode, Decoder, Encode, Encoder};
use std::collections::BTreeMap;

crate::wire_enum! {
    /// Permission level (spec 04). Ordered: `None < List < … < Config`.
    #[derive(PartialOrd, Ord, Default)]
    pub enum Perm {
        #[default]
        None = 0 => "none",
        List = 1 => "list",
        Read = 2 => "read",
        Write = 3 => "write",
        Config = 4 => "config",
    }
}

crate::wire_enum! {
    /// `~meta.writable` (spec 02, key 4).
    #[derive(Default)]
    pub enum Writable {
        #[default]
        Never = 0 => "never",
        Config = 1 => "config",
        Write = 2 => "write",
    }
}

crate::wire_enum! {
    /// Value type code (spec 02, key 1).
    pub enum TypeCode {
        Null = 0 => "null",
        Number = 1 => "number",
        String = 2 => "string",
        Bool = 3 => "bool",
        Enum = 4 => "enum",
        Map = 5 => "map",
        Array = 6 => "array",
        Binary = 7 => "binary",
        Dynamic = 8 => "dynamic",
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
    /// Field label for people (the key stays the `args` name).
    pub display: Option<String>,
    pub description: Option<String>,
    /// Example value shown in an empty field.
    pub placeholder: Option<String>,
    /// `"password"` (hidden, never echoed) or `"textarea"`; UIs ignore others.
    pub editor: Option<String>,
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
    /// Name for people (`"Add Device"`); the key stays a key segment.
    pub display: Option<String>,
    /// Menu: `"new"` (adds children), `"edit"` (changes or removes the
    /// node), another name = own submenu, `None` = top level.
    pub group: Option<String>,
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
    /// `view=list`: `attr.history` is not empty (spec 02 0.2.1).
    pub has_history: Option<bool>,
    /// A child without `type` (a node, not a value) exists now: a tree UI
    /// draws a triangle (spec 02 0.2.6).
    pub has_nodes: Option<bool>,
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
            self.display.is_some(),
            self.description.is_some(),
            self.placeholder.is_some(),
            self.editor.is_some(),
        ]
        .iter()
        .filter(|b| **b)
        .count() as u64;
        e.map(n)?;
        if let Some(t) = self.ty {
            e.u8(1)?.u8(t.code())?;
        }
        if let Some(u) = &self.unit {
            e.u8(2)?;
            enc_toc(e, u)?;
        }
        if let Some(ev) = &self.enum_values {
            e.u8(3)?;
            enc_str_array(e, ev)?;
        }
        // text keys after int keys, by length then bytes: "editor"(6)
        // "default" "display"(7) "required"(8) "description" "placeholder"(11)
        if let Some(x) = &self.editor {
            e.str("editor")?.str(x)?;
        }
        if let Some(d) = &self.default {
            e.str("default")?;
            d.encode(e, ctx)?;
        }
        if let Some(x) = &self.display {
            e.str("display")?.str(x)?;
        }
        if let Some(r) = self.required {
            e.str("required")?.bool(r)?;
        }
        if let Some(x) = &self.description {
            e.str("description")?.str(x)?;
        }
        if let Some(x) = &self.placeholder {
            e.str("placeholder")?.str(x)?;
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
        // keys by length then bytes: "group" "level"(5) "params" "result"
        // "stream"(6) "display"(7) "timeout_ms"(10)
        let mut n = 1u64;
        n += self.result.is_some() as u64;
        n += self.stream.is_some() as u64;
        n += self.level.is_some() as u64;
        n += self.timeout_ms.is_some() as u64;
        n += self.display.is_some() as u64;
        n += self.group.is_some() as u64;
        e.map(n)?;
        if let Some(g) = &self.group {
            e.str("group")?.str(g)?;
        }
        if let Some(l) = self.level {
            e.str("level")?.u8(l.code())?;
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
                ActionResult::Type(t) => e.u8(t.code())?,
                ActionResult::Stream => e.str("stream")?,
                ActionResult::Void => e.str("void")?,
            };
        }
        if let Some(s) = self.stream {
            e.str("stream")?.bool(s)?;
        }
        if let Some(x) = &self.display {
            e.str("display")?.str(x)?;
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
            self.has_history.is_some(),
            self.has_nodes.is_some(),
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
            e.u8(1)?.u8(v.code())?;
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
            e.u8(4)?.u8(v.code())?;
        }
        if let Some(v) = self.invokable {
            e.u8(5)?.u8(v.code())?;
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
        if let Some(v) = self.has_history {
            e.u8(16)?.bool(v)?;
        }
        if let Some(v) = self.has_nodes {
            e.u8(17)?.bool(v)?;
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
                    "display" => p.display = Some(d.str()?.to_owned()),
                    "description" => p.description = Some(d.str()?.to_owned()),
                    "placeholder" => p.placeholder = Some(d.str()?.to_owned()),
                    "editor" => p.editor = Some(d.str()?.to_owned()),
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
                "display" => a.display = Some(d.str()?.to_owned()),
                "group" => a.group = Some(d.str()?.to_owned()),
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
                16 => m.has_history = Some(d.bool()?),
                17 => m.has_nodes = Some(d.bool()?),
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

/// Interned profile codes (spec `tables.json`, `is_codes`).
pub mod is_code {
    pub const NODE: u32 = 0;
    pub const FOLDER: u32 = 1;
    pub const NUMBER: u32 = 2;
    pub const STRING: u32 = 3;
    pub const BOOL: u32 = 4;
    pub const ENUM: u32 = 5;
    pub const LINK: u32 = 6;
}

// ---------- builders ----------

impl NodeMeta {
    /// Container node (`is = wy:folder`).
    pub fn folder() -> Self {
        Self {
            is: Some(Profile::Code(is_code::FOLDER)),
            ..Default::default()
        }
    }

    /// Leaf node of the given type with the matching base profile.
    pub fn leaf(ty: TypeCode) -> Self {
        let is = match ty {
            TypeCode::Number => is_code::NUMBER,
            TypeCode::String => is_code::STRING,
            TypeCode::Bool => is_code::BOOL,
            TypeCode::Enum => is_code::ENUM,
            _ => is_code::NODE,
        };
        Self {
            is: Some(Profile::Code(is)),
            ty: Some(ty),
            ..Default::default()
        }
    }

    pub fn number() -> Self {
        Self::leaf(TypeCode::Number)
    }

    pub fn is(mut self, profile: impl Into<String>) -> Self {
        self.is = Some(Profile::Name(profile.into()));
        self
    }

    pub fn unit(mut self, unit: impl Into<String>) -> Self {
        self.unit = Some(TextOrCode::Text(unit.into()));
        self
    }

    pub fn enum_values<I: IntoIterator<Item = S>, S: Into<String>>(mut self, values: I) -> Self {
        self.enum_values = Some(values.into_iter().map(Into::into).collect());
        self
    }

    pub fn writable(mut self, w: Writable) -> Self {
        self.writable = Some(w);
        self
    }

    pub fn invokable(mut self, p: Perm) -> Self {
        self.invokable = Some(p);
        self
    }

    pub fn display(mut self, name: impl Into<String>) -> Self {
        self.attr
            .get_or_insert_with(BTreeMap::new)
            .insert("display".into(), Value::Str(name.into()));
        self
    }

    pub fn cfg(mut self, key: impl Into<String>, v: impl Into<Value>) -> Self {
        self.cfg
            .get_or_insert_with(BTreeMap::new)
            .insert(key.into(), v.into());
        self
    }

    pub fn attr(mut self, key: impl Into<String>, v: impl Into<Value>) -> Self {
        self.attr
            .get_or_insert_with(BTreeMap::new)
            .insert(key.into(), v.into());
        self
    }

    pub fn cfg_value(&self, key: &str) -> Option<&Value> {
        self.cfg.as_ref()?.get(key)
    }

    pub fn attr_value(&self, key: &str) -> Option<&Value> {
        self.attr.as_ref()?.get(key)
    }
}

impl ActionMeta {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn param(mut self, name: impl Into<String>, p: ParamMeta) -> Self {
        self.params.insert(name.into(), p);
        self
    }

    pub fn result(mut self, r: ActionResult) -> Self {
        self.result = Some(r);
        self
    }

    pub fn stream(mut self, s: bool) -> Self {
        self.stream = Some(s);
        self
    }

    pub fn level(mut self, p: Perm) -> Self {
        self.level = Some(p);
        self
    }

    pub fn timeout_ms(mut self, ms: u32) -> Self {
        self.timeout_ms = Some(ms);
        self
    }

    pub fn display(mut self, d: impl Into<String>) -> Self {
        self.display = Some(d.into());
        self
    }

    pub fn group(mut self, g: impl Into<String>) -> Self {
        self.group = Some(g.into());
        self
    }
}

/// `group` of actions that add children.
pub const GROUP_NEW: &str = "new";
/// `group` of actions that change or remove the node itself.
pub const GROUP_EDIT: &str = "edit";
/// `editor` of a secret parameter.
pub const EDITOR_PASSWORD: &str = "password";
/// `editor` of a multi-line text parameter.
pub const EDITOR_TEXTAREA: &str = "textarea";
/// `editor` of a binary parameter read from a local file (spec 02 0.1.7).
pub const EDITOR_FILE: &str = "file";
/// `editor` of a text range `<from>/<to>` in RFC 3339 (spec 02 0.2.4): UIs
/// offer ranges (Today, Last 7 Days, …) and date-time pickers.
pub const EDITOR_DATERANGE: &str = "daterange";
/// `editor` of one RFC 3339 instant (spec 02 0.2.4): a date-time picker.
pub const EDITOR_DATE: &str = "date";
/// `editor` of a number of seconds (spec 02 0.2.4): typed in a unit (s,
/// min, h, d) chosen beside it, sent in seconds.
pub const EDITOR_DURATION: &str = "duration";

impl ParamMeta {
    pub fn of(ty: TypeCode) -> Self {
        Self {
            ty: Some(ty),
            ..Default::default()
        }
    }

    pub fn required(mut self, r: bool) -> Self {
        self.required = Some(r);
        self
    }

    pub fn enum_values<I: IntoIterator<Item = S>, S: Into<String>>(mut self, values: I) -> Self {
        self.enum_values = Some(values.into_iter().map(Into::into).collect());
        self
    }

    pub fn display(mut self, d: impl Into<String>) -> Self {
        self.display = Some(d.into());
        self
    }

    pub fn description(mut self, d: impl Into<String>) -> Self {
        self.description = Some(d.into());
        self
    }

    pub fn placeholder(mut self, p: impl Into<String>) -> Self {
        self.placeholder = Some(p.into());
        self
    }

    pub fn editor(mut self, e: impl Into<String>) -> Self {
        self.editor = Some(e.into());
        self
    }
}
