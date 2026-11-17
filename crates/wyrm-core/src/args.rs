//! Typed action arguments: one struct declares an action's parameters and
//! decodes them (typing audit 2026-11-15, T3).
//!
//! An action's arguments travel as a [`Value`] map (spec 05). `#[derive(Args)]`
//! (crate `wyrm-link-sdk-derive`, re-exported by `wyrm-link-sdk` and
//! `wyrm-link-api`) makes, from one struct with named fields:
//!
//! * [`Args::params`]: the `ParamMeta` of every field, as `~meta` publishes it
//!   (`actions.<a>.params`);
//! * [`Args::decode`]: the struct from the arguments, or an [`ArgError`] that
//!   names the field.
//!
//! So what an action declares and what it reads are the same list. A handler
//! takes the struct; it never looks a name up in the map.
//!
//! Rules of the decoder:
//!
//! * a field of type `T` is required, `Option<T>` is optional; an argument that
//!   is absent or `null` is not there;
//! * a name that is not a field is refused ([`Fault::Unknown`]): a typo must not
//!   pass as "not given";
//! * a whole number goes through [`Value::to_int`], the one integer decoder: a
//!   fraction, a negative number for an unsigned type and a number out of the
//!   type's range are refused, never truncated;
//! * a closed set of names is a [`Named`] type (`name_enum!`, `wire_enum!`):
//!   `#[arg(choice)]` takes its name (a text parameter that lists the names),
//!   `#[arg(enum)]` its index (an `enum` parameter, spec 02).
//!
//! This module has no dependency beyond the wire types, so a portable link
//! (wasm32) decodes its arguments the same way.

use crate::meta::{ActionMeta, ParamMeta, TypeCode};
use crate::named::{Named, UnknownValue};
use crate::value::{IntError, Value};
use std::collections::BTreeMap;
use std::fmt;

/// Why one argument is refused.
#[derive(Debug, Clone, PartialEq, thiserror::Error)]
pub enum Fault {
    /// A required argument is absent, `null` or (for a `nonempty` text) empty.
    #[error("required")]
    Missing,
    /// The name is no parameter of the action.
    #[error("unknown argument")]
    Unknown,
    /// The arguments are not a map.
    #[error("expected a map of arguments")]
    NotAMap,
    /// A value of another type; the text says what is expected (`text`).
    #[error("expected {0}")]
    Type(&'static str),
    /// No whole number of the field's type ([`Value::to_int`]).
    #[error("expected a whole number ({0})")]
    Int(IntError),
    /// NaN or an infinity.
    #[error("expected a finite number")]
    NotFinite,
    /// Below the field's `min`.
    #[error("{0} is below {1}")]
    Below(String, String),
    /// Above the field's `max`.
    #[error("{0} is above {1}")]
    Above(String, String),
    /// A name that is not in the set.
    #[error("{0}")]
    Name(UnknownValue),
    /// An index beyond the list an `enum` parameter declares.
    #[error("index {index} is out of the list of {len}")]
    Index { index: u64, len: usize },
    /// One element of a list.
    #[error("item {index}: {fault}")]
    Item { index: usize, fault: Box<Fault> },
}

impl Fault {
    /// The value is of the right type and outside what the field takes.
    pub fn is_range(&self) -> bool {
        match self {
            Fault::Below(..) | Fault::Above(..) | Fault::Index { .. } => true,
            Fault::Int(e) => matches!(e, IntError::Negative | IntError::OutOfRange),
            Fault::Item { fault, .. } => fault.is_range(),
            _ => false,
        }
    }
}

/// A refused argument: the field's name and why.
#[derive(Debug, Clone, PartialEq)]
pub struct ArgError {
    /// The argument's name as the action declares it (`args` for the whole map).
    pub field: String,
    pub fault: Fault,
}

impl ArgError {
    pub fn new(field: impl Into<String>, fault: Fault) -> Self {
        Self {
            field: field.into(),
            fault,
        }
    }
}

impl fmt::Display for ArgError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}: {}", self.field, self.fault)
    }
}

impl std::error::Error for ArgError {}

/// A type one argument decodes into, with the `type` its parameter declares.
pub trait ArgValue: Sized {
    const TYPE: TypeCode;
    fn from_value(v: &Value) -> Result<Self, Fault>;
}

impl ArgValue for String {
    const TYPE: TypeCode = TypeCode::String;
    fn from_value(v: &Value) -> Result<Self, Fault> {
        match v {
            Value::Str(s) => Ok(s.clone()),
            _ => Err(Fault::Type("text")),
        }
    }
}

impl ArgValue for bool {
    const TYPE: TypeCode = TypeCode::Bool;
    fn from_value(v: &Value) -> Result<Self, Fault> {
        match v {
            Value::Bool(b) => Ok(*b),
            _ => Err(Fault::Type("true or false")),
        }
    }
}

macro_rules! int_arg {
    ($($t:ty),+) => {$(
        impl ArgValue for $t {
            const TYPE: TypeCode = TypeCode::Number;
            fn from_value(v: &Value) -> Result<Self, Fault> {
                v.to_int::<$t>().map_err(|e| match e {
                    IntError::NotANumber => Fault::Type("a number"),
                    e => Fault::Int(e),
                })
            }
        }
    )+};
}
int_arg!(u8, u16, u32, u64, usize, i8, i16, i32, i64, isize);

impl ArgValue for f64 {
    const TYPE: TypeCode = TypeCode::Number;
    fn from_value(v: &Value) -> Result<Self, Fault> {
        let x = match *v {
            Value::Float(f) => f,
            Value::UInt(u) => u as f64,
            Value::Int(i) => i as f64,
            _ => return Err(Fault::Type("a number")),
        };
        if x.is_finite() {
            Ok(x)
        } else {
            Err(Fault::NotFinite)
        }
    }
}

/// A binary argument.
impl ArgValue for Vec<u8> {
    const TYPE: TypeCode = TypeCode::Binary;
    fn from_value(v: &Value) -> Result<Self, Fault> {
        match v {
            Value::Bytes(b) => Ok(b.clone()),
            _ => Err(Fault::Type("bytes")),
        }
    }
}

/// A map argument whose content the action checks itself (a link's `params`).
impl ArgValue for BTreeMap<String, Value> {
    const TYPE: TypeCode = TypeCode::Map;
    fn from_value(v: &Value) -> Result<Self, Fault> {
        match v {
            Value::Map(m) => Ok(m.clone()),
            _ => Err(Fault::Type("a map")),
        }
    }
}

/// A list of texts.
impl ArgValue for Vec<String> {
    const TYPE: TypeCode = TypeCode::Array;
    fn from_value(v: &Value) -> Result<Self, Fault> {
        let Value::Array(items) = v else {
            return Err(Fault::Type("a list"));
        };
        items
            .iter()
            .enumerate()
            .map(|(index, v)| {
                String::from_value(v).map_err(|fault| Fault::Item {
                    index,
                    fault: Box::new(fault),
                })
            })
            .collect()
    }
}

/// A list of names of one set.
pub fn names<T: Named>(v: &Value) -> Result<Vec<T>, Fault> {
    let Value::Array(items) = v else {
        return Err(Fault::Type("a list"));
    };
    items
        .iter()
        .enumerate()
        .map(|(index, v)| {
            by_name::<T>(v).map_err(|fault| Fault::Item {
                index,
                fault: Box::new(fault),
            })
        })
        .collect()
}

/// `#[arg(choice)]`: a value of the set `T` from its name.
pub fn by_name<T: Named>(v: &Value) -> Result<T, Fault> {
    match v {
        Value::Str(s) => crate::named::parse::<T>(s).map_err(Fault::Name),
        _ => Err(Fault::Type("a name")),
    }
}

/// `#[arg(enum)]`: a value of the set `T` from its index in [`Named::NAMES`],
/// the form an `enum` parameter has on the wire (spec 02).
pub fn by_index<T: Named>(v: &Value) -> Result<T, Fault> {
    let index: u64 = v.to_int().map_err(|e| match e {
        IntError::NotANumber => Fault::Type("an index"),
        e => Fault::Int(e),
    })?;
    let out = || Fault::Index {
        index,
        len: T::NAMES.len(),
    };
    let name = usize::try_from(index)
        .ok()
        .and_then(|i| T::NAMES.get(i))
        .ok_or_else(out)?;
    T::from_name(name).ok_or_else(out)
}

/// `#[arg(trim)]`: text without the white space around it.
pub fn trimmed(v: &Value) -> Result<String, Fault> {
    match v {
        Value::Str(s) => Ok(s.trim().to_owned()),
        _ => Err(Fault::Type("text")),
    }
}

/// `#[arg(min = …)]`.
pub fn at_least<T: PartialOrd + fmt::Display>(field: &str, v: &T, min: T) -> Result<(), ArgError> {
    if *v < min {
        return Err(ArgError::new(
            field,
            Fault::Below(v.to_string(), min.to_string()),
        ));
    }
    Ok(())
}

/// `#[arg(max = …)]`.
pub fn at_most<T: PartialOrd + fmt::Display>(field: &str, v: &T, max: T) -> Result<(), ArgError> {
    if *v > max {
        return Err(ArgError::new(
            field,
            Fault::Above(v.to_string(), max.to_string()),
        ));
    }
    Ok(())
}

/// The arguments of one call while a struct takes its fields from them.
pub struct Reader<'a> {
    map: &'a BTreeMap<String, Value>,
    taken: Vec<&'static str>,
}

impl<'a> Reader<'a> {
    pub fn new(args: &'a Value) -> Result<Self, ArgError> {
        match args {
            Value::Map(map) => Ok(Self {
                map,
                taken: Vec::new(),
            }),
            _ => Err(ArgError::new("args", Fault::NotAMap)),
        }
    }

    /// The argument `name`; absent and `null` are the same.
    pub fn take(&mut self, name: &'static str) -> Field<'a> {
        self.taken.push(name);
        Field {
            name,
            value: self.map.get(name).filter(|v| !matches!(v, Value::Null)),
        }
    }

    /// Refuses the first argument no field took.
    pub fn finish(self) -> Result<(), ArgError> {
        match self.map.keys().find(|k| !self.taken.contains(&k.as_str())) {
            Some(k) => Err(ArgError::new(k.clone(), Fault::Unknown)),
            None => Ok(()),
        }
    }
}

/// One argument on its way into a field.
pub struct Field<'a> {
    name: &'static str,
    value: Option<&'a Value>,
}

impl<'a> Field<'a> {
    /// `#[arg(nonempty)]`: a text that is empty or white space is not there
    /// (a form sends an empty field as `""`).
    pub fn nonempty(mut self) -> Self {
        if matches!(self.value, Some(Value::Str(s)) if s.trim().is_empty()) {
            self.value = None;
        }
        self
    }

    pub fn required<T>(self, f: impl FnOnce(&'a Value) -> Result<T, Fault>) -> Result<T, ArgError> {
        match self.value {
            Some(v) => f(v).map_err(|fault| ArgError::new(self.name, fault)),
            None => Err(ArgError::new(self.name, Fault::Missing)),
        }
    }

    pub fn optional<T>(
        self,
        f: impl FnOnce(&'a Value) -> Result<T, Fault>,
    ) -> Result<Option<T>, ArgError> {
        self.value
            .map(f)
            .transpose()
            .map_err(|fault| ArgError::new(self.name, fault))
    }
}

/// The arguments of one action: what it declares and how it reads them.
/// Made by `#[derive(Args)]`; never written by hand.
pub trait Args: Sized {
    /// Every parameter with its declared meta, in field order.
    fn params() -> Vec<(&'static str, ParamMeta)>;

    /// The fields from `r` (a struct inside another one, `#[arg(flatten)]`,
    /// reads from the same arguments).
    fn read(r: &mut Reader<'_>) -> Result<Self, ArgError>;

    /// The struct from an action's arguments.
    fn decode(args: &Value) -> Result<Self, ArgError> {
        let mut r = Reader::new(args)?;
        let v = Self::read(&mut r)?;
        r.finish()?;
        Ok(v)
    }

    /// An action that declares these parameters and nothing else yet.
    fn action() -> ActionMeta {
        let mut a = ActionMeta::new();
        for (name, p) in Self::params() {
            a.params.insert(name.to_owned(), p);
        }
        a
    }
}

/// An action without parameters: any argument is refused.
impl Args for () {
    fn params() -> Vec<(&'static str, ParamMeta)> {
        Vec::new()
    }

    fn read(_: &mut Reader<'_>) -> Result<Self, ArgError> {
        Ok(())
    }
}

/// What a form shows for one declared parameter that depends on the state of
/// the moment: the choices of a list, the value in force. It cannot change the
/// parameter's type or add a parameter: those come from the struct.
pub struct Shown<'a>(&'a mut ParamMeta);

impl Shown<'_> {
    /// The names a text parameter offers now (links, roles, packages).
    pub fn choices<I: IntoIterator<Item = S>, S: Into<String>>(self, values: I) -> Self {
        self.0.enum_values = Some(values.into_iter().map(Into::into).collect());
        self
    }

    pub fn placeholder(self, text: impl Into<String>) -> Self {
        self.0.placeholder = Some(text.into());
        self
    }

    pub fn description(self, text: impl Into<String>) -> Self {
        self.0.description = Some(text.into());
        self
    }

    /// The value in force, pre-filled in an edit form.
    pub fn default(self, v: impl Into<Value>) -> Self {
        self.0.default = Some(v.into());
        self
    }

    /// The form asks for it (the handler still decides: the struct's field is
    /// optional when the need depends on the state).
    pub fn required(self) -> Self {
        self.0.required = Some(true);
        self
    }
}

impl ActionMeta {
    /// Sets what the declared parameter `name` shows now ([`Shown`]). A name
    /// the action does not declare changes nothing.
    pub fn shown(mut self, name: &str, f: impl FnOnce(Shown<'_>) -> Shown<'_>) -> Self {
        if let Some(p) = self.params.get_mut(name) {
            f(Shown(p));
        }
        self
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    crate::name_enum! {
        enum Mode as "mode" {
            Add => "add",
            Replace => "replace",
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
    fn fields_are_taken_once_and_the_rest_is_refused() {
        let args = map(&[
            ("n", Value::Float(20.0)),
            ("name", Value::from("  a ")),
            ("typo", Value::Bool(true)),
            ("gone", Value::Null),
        ]);
        let mut r = Reader::new(&args).unwrap();
        assert_eq!(r.take("n").required(u32::from_value), Ok(20));
        assert_eq!(r.take("name").required(trimmed), Ok("a".to_owned()));
        assert_eq!(r.take("gone").optional(bool::from_value), Ok(None));
        assert_eq!(r.take("absent").optional(bool::from_value), Ok(None));
        assert_eq!(
            r.take("need").required(bool::from_value),
            Err(ArgError::new("need", Fault::Missing))
        );
        assert_eq!(r.finish(), Err(ArgError::new("typo", Fault::Unknown)));
        assert_eq!(
            Reader::new(&Value::UInt(1)).err(),
            Some(ArgError::new("args", Fault::NotAMap))
        );
    }

    #[test]
    fn numbers_are_whole_and_in_range() {
        let int = |v: Value| u8::from_value(&v);
        assert_eq!(int(Value::UInt(7)), Ok(7));
        assert_eq!(int(Value::Float(7.0)), Ok(7));
        assert_eq!(
            int(Value::Float(0.5)),
            Err(Fault::Int(IntError::Fractional))
        );
        assert_eq!(int(Value::Int(-1)), Err(Fault::Int(IntError::Negative)));
        assert_eq!(int(Value::UInt(256)), Err(Fault::Int(IntError::OutOfRange)));
        assert_eq!(int(Value::from("7")), Err(Fault::Type("a number")));
        assert!(Fault::Int(IntError::OutOfRange).is_range());
        assert!(!Fault::Int(IntError::Fractional).is_range());
        assert_eq!(f64::from_value(&Value::UInt(2)), Ok(2.0));
        assert_eq!(
            f64::from_value(&Value::Float(f64::NAN)),
            Err(Fault::NotFinite)
        );
        assert!(at_least("n", &3u32, 5).is_err());
        assert!(at_most("n", &3u32, 5).is_ok());
        assert_eq!(
            at_most("n", &9u32, 5).unwrap_err().to_string(),
            "n: 9 is above 5"
        );
    }

    #[test]
    fn a_set_is_read_by_name_or_by_index_never_both() {
        assert_eq!(Mode::ALL.len(), 2);
        assert_eq!(by_name::<Mode>(&Value::from("replace")), Ok(Mode::Replace));
        assert!(matches!(
            by_name::<Mode>(&Value::from("Replace")),
            Err(Fault::Name(_))
        ));
        assert_eq!(by_name::<Mode>(&Value::UInt(1)), Err(Fault::Type("a name")));
        assert_eq!(by_index::<Mode>(&Value::UInt(1)), Ok(Mode::Replace));
        assert_eq!(
            by_index::<Mode>(&Value::UInt(2)),
            Err(Fault::Index { index: 2, len: 2 })
        );
        assert_eq!(
            by_index::<Mode>(&Value::from("add")),
            Err(Fault::Type("an index"))
        );
        assert_eq!(
            names::<Mode>(&Value::Array(vec!["add".into(), Value::UInt(1)])),
            Err(Fault::Item {
                index: 1,
                fault: Box::new(Fault::Type("a name"))
            })
        );
    }

    #[test]
    fn an_empty_text_of_a_nonempty_field_is_not_there() {
        let args = map(&[("a", Value::from(" ")), ("b", Value::from(""))]);
        let mut r = Reader::new(&args).unwrap();
        assert_eq!(
            r.take("a").nonempty().optional(String::from_value),
            Ok(None)
        );
        assert_eq!(
            r.take("b").nonempty().required(String::from_value),
            Err(ArgError::new("b", Fault::Missing))
        );
        // without `nonempty` an empty text is a value
        assert_eq!(r.take("b").required(String::from_value), Ok(String::new()));
    }

    #[test]
    fn no_parameters_means_no_arguments() {
        assert_eq!(<()>::decode(&map(&[])), Ok(()));
        assert_eq!(
            <()>::decode(&map(&[("x", Value::UInt(1))])),
            Err(ArgError::new("x", Fault::Unknown))
        );
        assert!(<()>::action().params.is_empty());
    }

    #[test]
    fn shown_changes_only_a_declared_parameter() {
        let a = ActionMeta::new()
            .param("link", ParamMeta::of(TypeCode::String))
            .shown("link", |p| p.choices(["a", "b"]).placeholder("none"))
            .shown("other", |p| p.required());
        assert_eq!(a.params.len(), 1);
        let p = &a.params["link"];
        assert_eq!(p.ty, Some(TypeCode::String));
        assert_eq!(p.enum_values, Some(vec!["a".to_owned(), "b".to_owned()]));
        assert_eq!(p.placeholder.as_deref(), Some("none"));
    }
}
