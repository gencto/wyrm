//! Declarative node parameters (ADR 0004). One schema per node kind drives
//! validation, defaults, the generated `add_*`/`edit` action forms and
//! `~meta.cfg`. Parameters are typed structs parsed once, never read by
//! string key on the hot path.

use crate::error::{LinkError, Result};
use std::collections::BTreeMap;
use wyrm_core::meta::ParamMeta;
use wyrm_core::{TypeCode, Value};

/// One parameter of a node kind.
#[derive(Debug, Clone, PartialEq)]
pub struct ParamSpec {
    pub name: &'static str,
    /// `Number`, `String`, `Bool` or `Enum` (enum values travel as names).
    pub ty: TypeCode,
    /// `None` = required.
    pub default: Option<Value>,
    pub enum_values: &'static [&'static str],
    /// Inclusive bounds for numbers (enforced here; spec 02 `ParamMeta`
    /// cannot carry them yet).
    pub min: Option<f64>,
    pub max: Option<f64>,
    /// Never echoed in `~meta.cfg` or replies.
    pub secret: bool,
    /// Where a secret goes (host, port, TLS, CA): an `edit` that changes a
    /// destination field drops the stored secrets unless it supplies them
    /// again. Without any `dest` field, every field counts as one.
    pub dest: bool,
    /// Hint shown with the field (`description` in the form).
    pub desc: &'static str,
    /// Field label for people (`"Slave ID"`); empty = the name.
    pub display: &'static str,
    /// Example value shown in an empty field.
    pub placeholder: &'static str,
    /// Form editor (`"textarea"`); a secret is always `"password"`.
    pub editor: &'static str,
}

impl ParamSpec {
    pub const fn new(name: &'static str, ty: TypeCode) -> Self {
        Self {
            name,
            ty,
            default: None,
            enum_values: &[],
            min: None,
            max: None,
            secret: false,
            dest: false,
            desc: "",
            display: "",
            placeholder: "",
            editor: "",
        }
    }

    pub fn default(mut self, v: impl Into<Value>) -> Self {
        self.default = Some(v.into());
        self
    }

    pub const fn bounds(mut self, min: f64, max: f64) -> Self {
        self.min = Some(min);
        self.max = Some(max);
        self
    }

    pub const fn one_of(mut self, values: &'static [&'static str]) -> Self {
        self.ty = TypeCode::Enum;
        self.enum_values = values;
        self
    }

    pub const fn secret(mut self) -> Self {
        self.secret = true;
        self
    }

    pub const fn dest(mut self) -> Self {
        self.dest = true;
        self
    }

    pub const fn desc(mut self, d: &'static str) -> Self {
        self.desc = d;
        self
    }

    pub const fn display(mut self, d: &'static str) -> Self {
        self.display = d;
        self
    }

    pub const fn placeholder(mut self, p: &'static str) -> Self {
        self.placeholder = p;
        self
    }

    pub const fn editor(mut self, e: &'static str) -> Self {
        self.editor = e;
        self
    }

    /// Spec 02 `param-meta` for action forms (enum as names, string-typed).
    pub fn param_meta(&self, prefill: Option<&Value>) -> ParamMeta {
        let mut p = ParamMeta::of(match self.ty {
            TypeCode::Enum => TypeCode::String,
            t => t,
        });
        if !self.enum_values.is_empty() {
            p.enum_values = Some(self.enum_values.iter().map(|s| (*s).to_owned()).collect());
        }
        p.default = if self.secret {
            None
        } else {
            prefill.cloned().or_else(|| self.default.clone())
        };
        p.required = Some(self.default.is_none() && prefill.is_none());
        let text = |s: &str| (!s.is_empty()).then(|| s.to_owned());
        p.display = text(self.display);
        p.description = text(self.desc);
        p.placeholder = text(self.placeholder);
        p.editor = if self.secret {
            Some(wyrm_core::meta::EDITOR_PASSWORD.to_owned())
        } else {
            text(self.editor)
        };
        p
    }
}

/// One kind of node on a level, like DSA's "Add IP Connection" next to
/// "Add Serial Connection": its own add action and parameters.
#[derive(Debug, Clone)]
pub struct Kind {
    /// Key segment (`ip_connection`); empty for a type with one kind.
    pub id: &'static str,
    /// Name for people (`"IP Connection"`); empty = the level's noun.
    pub display: &'static str,
    pub schema: Vec<ParamSpec>,
}

/// Typed parameters of the nodes of one level. A struct is one kind; an
/// enum of structs (`#[derive(Params)]` on newtype variants) is one kind
/// per variant. The tree stores a node's kind as `"kind"` beside its params,
/// so the kinds of a multi-kind level must not have a param named `kind`.
pub trait Params: Sized + Clone + PartialEq + Send + Sync + 'static {
    /// The parameters of a single-kind type (of the first kind otherwise).
    fn schema() -> Vec<ParamSpec>;
    /// From a normalized map (see [`normalize`]): every field present.
    fn from_map(m: &BTreeMap<String, Value>) -> Result<Self>;
    fn to_map(&self) -> BTreeMap<String, Value>;

    /// Validate `v` against the schema, fill defaults, build `Self`.
    fn from_value(v: &Value) -> Result<Self> {
        Self::from_map(&normalize(&Self::schema(), v)?)
    }

    fn to_value(&self) -> Value {
        Value::Map(self.to_map())
    }

    /// The kinds of this level; one unnamed kind by default.
    fn kinds() -> Vec<Kind> {
        vec![Kind {
            id: "",
            display: "",
            schema: Self::schema(),
        }]
    }

    /// This value's kind (`""` for a single-kind type).
    fn kind(&self) -> &'static str {
        ""
    }

    /// Build a value of `kind` from its normalized map.
    fn from_kind_map(kind: &str, m: &BTreeMap<String, Value>) -> Result<Self> {
        if kind.is_empty() {
            Self::from_map(m)
        } else {
            Err(LinkError::invalid_parameter(format!(
                "kind: unknown {kind:?}"
            )))
        }
    }

    /// The parameters of `kind` (`""` = the first kind).
    fn kind_schema(kind: &str) -> Result<Vec<ParamSpec>> {
        let kinds = Self::kinds();
        if kind.is_empty() {
            return Ok(kinds
                .into_iter()
                .next()
                .map(|k| k.schema)
                .unwrap_or_default());
        }
        kinds
            .into_iter()
            .find(|k| k.id == kind)
            .map(|k| k.schema)
            .ok_or_else(|| LinkError::invalid_parameter(format!("kind: unknown {kind:?}")))
    }

    /// Validate `v` against the schema of `kind` and build the value.
    fn from_kind_value(kind: &str, v: &Value) -> Result<Self> {
        let kind = if kind.is_empty() {
            Self::kinds().first().map(|k| k.id).unwrap_or("")
        } else {
            kind
        };
        Self::from_kind_map(kind, &normalize(&Self::kind_schema(kind)?, v)?)
    }

    /// `~meta.cfg` view: secrets left out (those of every kind when the
    /// kind cannot be resolved: fail closed).
    fn public_map(&self) -> BTreeMap<String, Value> {
        let secret: Vec<&str> = match Self::kind_schema(self.kind()) {
            Ok(schema) => schema.iter().filter(|s| s.secret).map(|s| s.name).collect(),
            Err(_) => all_secret_names::<Self>(),
        };
        let mut m = self.to_map();
        m.retain(|k, _| !secret.contains(&k.as_str()));
        m
    }
}

/// The secret params of every kind of `P` (redaction when the kind of a
/// stored config is unknown).
pub fn all_secret_names<P: Params>() -> Vec<&'static str> {
    let mut names: Vec<&'static str> = P::kinds()
        .into_iter()
        .flat_map(|k| k.schema)
        .filter(|s| s.secret)
        .map(|s| s.name)
        .collect();
    names.sort_unstable();
    names.dedup();
    names
}

fn bad(name: &str, what: impl std::fmt::Display) -> LinkError {
    LinkError::invalid_parameter(format!("{name}: {what}"))
}

/// Check `v` (a map) against `schema`: no unknown keys, required present,
/// types, enum names, finite numbers within bounds. Returns the map with
/// defaults filled in. Atomic: an error means nothing was accepted.
pub fn normalize(schema: &[ParamSpec], v: &Value) -> Result<BTreeMap<String, Value>> {
    let empty = BTreeMap::new();
    let given = match v {
        Value::Map(m) => m,
        Value::Null => &empty,
        _ => return Err(LinkError::invalid_parameter("parameters must be a map")),
    };
    if let Some(k) = given
        .keys()
        .find(|k| !schema.iter().any(|s| s.name == k.as_str()))
    {
        return Err(bad(k, "unknown parameter"));
    }
    let mut out = BTreeMap::new();
    for s in schema {
        let v = match (given.get(s.name), &s.default) {
            (Some(v), _) => v.clone(),
            (None, Some(d)) => d.clone(),
            (None, None) => return Err(bad(s.name, "required")),
        };
        let v = match s.ty {
            TypeCode::Number => {
                let x = v.as_f64().ok_or_else(|| bad(s.name, "expected a number"))?;
                if !x.is_finite() {
                    return Err(bad(s.name, "must be finite"));
                }
                if let Some(min) = s.min {
                    if x < min {
                        return Err(bad(s.name, format!("{x} < min {min}")));
                    }
                }
                if let Some(max) = s.max {
                    if x > max {
                        return Err(bad(s.name, format!("{x} > max {max}")));
                    }
                }
                v
            }
            TypeCode::Bool => match v {
                Value::Bool(_) => v,
                _ => return Err(bad(s.name, "expected true or false")),
            },
            TypeCode::String => match v {
                Value::Str(_) => v,
                _ => return Err(bad(s.name, "expected a string")),
            },
            TypeCode::Enum => match &v {
                Value::Str(name) if s.enum_values.contains(&name.as_str()) => v,
                _ => return Err(bad(s.name, format!("expected one of {:?}", s.enum_values))),
            },
            t => {
                return Err(bad(
                    s.name,
                    format!("unsupported parameter type {}", t.name()),
                ))
            }
        };
        out.insert(s.name.to_owned(), v);
    }
    Ok(out)
}

/// Field readers for `Params::from_map` on a normalized map.
pub mod field {
    use super::*;

    fn get<'a>(m: &'a BTreeMap<String, Value>, k: &str) -> Result<&'a Value> {
        m.get(k)
            .ok_or_else(|| LinkError::internal(format!("{k}: missing after normalize")))
    }

    pub fn f64(m: &BTreeMap<String, Value>, k: &str) -> Result<f64> {
        get(m, k)?
            .as_f64()
            .ok_or_else(|| bad(k, "expected a number"))
    }

    /// Integer that fits `T` (bounds should already guarantee it).
    pub fn int<T: TryFrom<i64>>(m: &BTreeMap<String, Value>, k: &str) -> Result<T> {
        let x = f64(m, k)?;
        if x.fract() != 0.0 {
            return Err(bad(k, "expected an integer"));
        }
        T::try_from(x as i64).map_err(|_| bad(k, "out of range"))
    }

    pub fn bool(m: &BTreeMap<String, Value>, k: &str) -> Result<bool> {
        match get(m, k)? {
            Value::Bool(b) => Ok(*b),
            _ => Err(bad(k, "expected true or false")),
        }
    }

    pub fn string(m: &BTreeMap<String, Value>, k: &str) -> Result<String> {
        match get(m, k)? {
            Value::Str(s) => Ok(s.clone()),
            _ => Err(bad(k, "expected a string")),
        }
    }

    pub fn enumv<E: ParamEnum>(m: &BTreeMap<String, Value>, k: &str) -> Result<E> {
        match get(m, k)? {
            Value::Str(s) => {
                E::from_name(s).ok_or_else(|| bad(k, format!("expected one of {:?}", E::NAMES)))
            }
            _ => Err(bad(k, "expected a name")),
        }
    }
}

/// Enum parameter type: names on the wire, a Rust enum in code.
pub trait ParamEnum: Sized + Copy {
    const NAMES: &'static [&'static str];
    fn from_name(s: &str) -> Option<Self>;
    fn name(self) -> &'static str;
}

#[cfg(test)]
mod tests {
    use super::*;

    #[derive(Debug, Clone, PartialEq)]
    struct Conn {
        host: String,
        port: u16,
        timeout_ms: u32,
        secret: String,
    }

    impl Params for Conn {
        fn schema() -> Vec<ParamSpec> {
            vec![
                ParamSpec::new("host", TypeCode::String),
                ParamSpec::new("port", TypeCode::Number)
                    .default(502u64)
                    .bounds(1.0, 65535.0),
                ParamSpec::new("timeout_ms", TypeCode::Number)
                    .default(500u64)
                    .bounds(100.0, 10_000.0),
                ParamSpec::new("secret", TypeCode::String)
                    .default("")
                    .secret(),
            ]
        }
        fn from_map(m: &BTreeMap<String, Value>) -> Result<Self> {
            Ok(Self {
                host: field::string(m, "host")?,
                port: field::int(m, "port")?,
                timeout_ms: field::int(m, "timeout_ms")?,
                secret: field::string(m, "secret")?,
            })
        }
        fn to_map(&self) -> BTreeMap<String, Value> {
            BTreeMap::from([
                ("host".into(), Value::Str(self.host.clone())),
                ("port".into(), Value::UInt(self.port.into())),
                ("timeout_ms".into(), Value::UInt(self.timeout_ms.into())),
                ("secret".into(), Value::Str(self.secret.clone())),
            ])
        }
    }

    fn map(kv: &[(&str, Value)]) -> Value {
        Value::Map(
            kv.iter()
                .map(|(k, v)| ((*k).to_owned(), v.clone()))
                .collect(),
        )
    }

    #[test]
    fn defaults_bounds_unknown() {
        let c = Conn::from_value(&map(&[("host", "h".into())])).unwrap();
        assert_eq!(c.port, 502);
        assert_eq!(Conn::from_value(&c.to_value()).unwrap(), c);
        let e = Conn::from_value(&map(&[
            ("host", "h".into()),
            ("timeout_ms", Value::UInt(5)),
        ]))
        .unwrap_err();
        assert_eq!(e.message, "timeout_ms: 5 < min 100");
        assert!(Conn::from_value(&map(&[])).is_err(), "host is required");
        assert!(Conn::from_value(&map(&[("host", "h".into()), ("prot", Value::UInt(1))])).is_err());
        assert!(Conn::from_value(&map(&[
            ("host", "h".into()),
            ("port", Value::Float(f64::NAN))
        ]))
        .is_err());
        assert!(!c.public_map().contains_key("secret"));
    }

    #[test]
    fn action_form() {
        let s = &Conn::schema()[1];
        let p = s.param_meta(None);
        assert_eq!(p.default, Some(Value::UInt(502)));
        assert_eq!(p.required, Some(false));
        let p = s.param_meta(Some(&Value::UInt(1502)));
        assert_eq!(
            p.default,
            Some(Value::UInt(1502)),
            "edit form is pre-filled"
        );
        assert_eq!(
            Conn::schema()[3].param_meta(Some(&"x".into())).default,
            None,
            "secret never echoed"
        );
        assert_eq!(Conn::schema()[0].param_meta(None).required, Some(true));
    }
}
