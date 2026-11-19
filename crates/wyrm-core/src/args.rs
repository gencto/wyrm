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
//! * the arguments are taken by value: a field takes its value out of the map,
//!   so a large binary argument (a package, a part of a file) is moved into the
//!   struct, never copied;
//! * a field of type `T` is required, `Option<T>` is optional; an argument that
//!   is absent or `null` is not there;
//! * a name that is not a field is refused ([`Fault::Unknown`]): a typo must not
//!   pass as "not given";
//! * a name is one field: a struct that names a parameter twice, by two of its
//!   fields or through `#[param(flatten)]`, does not compile ([`Names`]);
//! * a refused call clears the text and bytes this decoder still holds: what no
//!   field took, a value of the wrong type, arguments that are no map. (Not
//!   cleared here: the transport's buffer the arguments were decoded from, and
//!   a value a field already took, which is the field type's own to clear.)
//! * a whole number goes through [`Value::to_int`], the one integer decoder: a
//!   fraction, a negative number for an unsigned type and a number out of the
//!   type's range are refused, never truncated;
//! * a closed set of names is a [`Named`] type (`name_enum!`, `wire_enum!`):
//!   `#[param(choice)]` takes its name (a text parameter that lists the names),
//!   `#[param(enum)]` its index (an `enum` parameter, spec 02);
//! * `#[param(nonempty)]`: the empty text `""` is not there (a form sends an
//!   empty field so). Only with `#[param(trim)]` is a text of white space empty
//!   too: a secret is never trimmed, so a passphrase of spaces is a passphrase.
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
    /// A reader took this name twice: a fault of the action's code, not of the
    /// caller (the derive does not compile such a struct, see [`Names`]).
    #[error("declared twice by the action")]
    Repeated,
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

/// A refused argument: the field's name and why.
#[derive(Debug, Clone, PartialEq)]
pub struct ArgError {
    /// The argument's name as the action declares it (`args` for the whole
    /// map); a name the caller made up is cut at 64 bytes.
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
/// The value is taken out of `v` (left `Null`), not copied: bytes and
/// text move into the field. On a refusal `v` is left as it was, and the
/// reader clears it.
pub trait ArgValue: Sized {
    const TYPE: TypeCode;
    fn from_value(v: &mut Value) -> Result<Self, Fault>;
}

/// `v` taken as the variant `pick` wants, or left in place and refused.
pub(crate) fn take<T>(
    v: &mut Value,
    what: &'static str,
    pick: impl FnOnce(Value) -> Result<T, Value>,
) -> Result<T, Fault> {
    match pick(std::mem::replace(v, Value::Null)) {
        Ok(t) => Ok(t),
        Err(back) => {
            *v = back;
            Err(Fault::Type(what))
        }
    }
}

pub(crate) mod sealed {
    /// Only the secret types of `wyrm_core::secret` are secret arguments: no
    /// other crate can add one.
    pub trait Sealed {}
}

/// A type that keeps a secret argument: its memory is cleared when it is
/// dropped and its `Debug` prints no part of the value. `#[param(secret)]`
/// compiles only on such a type: [`Secret`](crate::secret::Secret) and
/// [`SecretBytes`](crate::secret::SecretBytes). Sealed.
pub trait SecretArg: ArgValue + sealed::Sealed {}

/// The one secret that is trimmed: a token a person pastes as one line,
/// [`SecretLine`](crate::secret::SecretLine). A token holds no white space,
/// and a pasted one often ends with a newline. Sealed, and no [`ArgValue`]:
/// a field of this type compiles only with `#[param(secret, trim)]`, so the
/// exception is always written out. A passphrase is never one (its spaces are
/// part of it).
pub trait PastedSecretArg: Sized + sealed::Sealed {
    const TYPE: TypeCode;
    /// The token without the white space around it; the pasted text is cleared.
    fn pasted(v: &mut Value) -> Result<Self, Fault>;
}

/// The parameter names of an `Args` struct: its own fields and the structs it
/// flattens. The derive checks them when the struct is compiled.
pub struct Names {
    pub own: &'static [&'static str],
    pub flat: &'static [&'static Names],
}

const fn same(a: &str, b: &str) -> bool {
    let (a, b) = (a.as_bytes(), b.as_bytes());
    if a.len() != b.len() {
        return false;
    }
    let mut i = 0;
    while i < a.len() {
        if a[i] != b[i] {
            return false;
        }
        i += 1;
    }
    true
}

impl Names {
    /// How many fields of this struct and of those it flattens are `name`.
    pub const fn count(&self, name: &str) -> usize {
        let (mut n, mut i) = (0, 0);
        while i < self.own.len() {
            if same(self.own[i], name) {
                n += 1;
            }
            i += 1;
        }
        let mut i = 0;
        while i < self.flat.len() {
            n += self.flat[i].count(name);
            i += 1;
        }
        n
    }

    /// A name below `self` is declared twice in `root`. The derive asserts
    /// `!NAMES.repeats_in(&NAMES)` in a `const`, so a struct that gets a name a
    /// second time through `flatten` is a compile error.
    pub const fn repeats_in(&self, root: &Names) -> bool {
        let mut i = 0;
        while i < self.own.len() {
            if root.count(self.own[i]) > 1 {
                return true;
            }
            i += 1;
        }
        let mut i = 0;
        while i < self.flat.len() {
            if self.flat[i].repeats_in(root) {
                return true;
            }
            i += 1;
        }
        false
    }
}

impl ArgValue for String {
    const TYPE: TypeCode = TypeCode::String;
    fn from_value(v: &mut Value) -> Result<Self, Fault> {
        take(v, "text", |v| match v {
            Value::Str(s) => Ok(s),
            other => Err(other),
        })
    }
}

impl ArgValue for bool {
    const TYPE: TypeCode = TypeCode::Bool;
    fn from_value(v: &mut Value) -> Result<Self, Fault> {
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
            fn from_value(v: &mut Value) -> Result<Self, Fault> {
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
    fn from_value(v: &mut Value) -> Result<Self, Fault> {
        match v.as_f64() {
            Some(x) if x.is_finite() => Ok(x),
            Some(_) => Err(Fault::NotFinite),
            None => Err(Fault::Type("a number")),
        }
    }
}

/// A binary argument.
impl ArgValue for Vec<u8> {
    const TYPE: TypeCode = TypeCode::Binary;
    fn from_value(v: &mut Value) -> Result<Self, Fault> {
        take(v, "bytes", |v| match v {
            Value::Bytes(b) => Ok(b),
            other => Err(other),
        })
    }
}

/// A map argument whose content the action checks itself (a link's `params`).
impl ArgValue for BTreeMap<String, Value> {
    const TYPE: TypeCode = TypeCode::Map;
    fn from_value(v: &mut Value) -> Result<Self, Fault> {
        take(v, "a map", |v| match v {
            Value::Map(m) => Ok(m),
            other => Err(other),
        })
    }
}

/// Each element of a list through `f`; a refusal says which element.
fn list<T>(v: &mut Value, f: impl Fn(&mut Value) -> Result<T, Fault>) -> Result<Vec<T>, Fault> {
    let Value::Array(items) = v else {
        return Err(Fault::Type("a list"));
    };
    items
        .iter_mut()
        .enumerate()
        .map(|(index, v)| {
            f(v).map_err(|fault| Fault::Item {
                index,
                fault: Box::new(fault),
            })
        })
        .collect()
}

/// A list of texts.
impl ArgValue for Vec<String> {
    const TYPE: TypeCode = TypeCode::Array;
    fn from_value(v: &mut Value) -> Result<Self, Fault> {
        list(v, String::from_value)
    }
}

/// `#[param(choice)]` on a `Vec<T>`: a list of names of one set.
pub fn names<T: Named>(v: &mut Value) -> Result<Vec<T>, Fault> {
    list(v, by_name::<T>)
}

/// `#[param(choice)]`: a value of the set `T` from its name.
pub fn by_name<T: Named>(v: &mut Value) -> Result<T, Fault> {
    match v {
        Value::Str(s) => crate::named::parse::<T>(s).map_err(Fault::Name),
        _ => Err(Fault::Type("a name")),
    }
}

/// `#[param(choice, trim)]`: [`by_name`] of the text without the white space
/// around it.
pub fn by_name_trimmed<T: Named>(v: &mut Value) -> Result<T, Fault> {
    match v {
        Value::Str(s) => crate::named::parse::<T>(s.trim()).map_err(Fault::Name),
        _ => Err(Fault::Type("a name")),
    }
}

/// `#[param(enum)]`: a value of the set `T` from its index in [`Named::NAMES`],
/// the form an `enum` parameter has on the wire (spec 02).
pub fn by_index<T: Named>(v: &mut Value) -> Result<T, Fault> {
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

/// `#[param(trim)]`: text without the white space around it.
pub fn trimmed(v: &mut Value) -> Result<String, Fault> {
    match v {
        Value::Str(s) => Ok(s.trim().to_owned()),
        _ => Err(Fault::Type("text")),
    }
}

/// `#[param(min = …)]`.
pub fn at_least<T: PartialOrd + fmt::Display>(field: &str, v: &T, min: T) -> Result<(), ArgError> {
    if *v < min {
        return Err(ArgError::new(
            field,
            Fault::Below(v.to_string(), min.to_string()),
        ));
    }
    Ok(())
}

/// `#[param(max = …)]`.
pub fn at_most<T: PartialOrd + fmt::Display>(field: &str, v: &T, max: T) -> Result<(), ArgError> {
    if *v > max {
        return Err(ArgError::new(
            field,
            Fault::Above(v.to_string(), max.to_string()),
        ));
    }
    Ok(())
}

/// The arguments of one call while a struct takes its fields out of them.
pub struct Reader {
    map: BTreeMap<String, Value>,
    taken: Vec<&'static str>,
}

impl Reader {
    pub fn new(args: Value) -> Result<Self, ArgError> {
        match args {
            Value::Map(map) => Ok(Self {
                map,
                taken: Vec::new(),
            }),
            mut other => {
                // no map: whatever it is, it is cleared before it is freed
                wipe(&mut other);
                Err(ArgError::new("args", Fault::NotAMap))
            }
        }
    }

    /// The argument `name`, taken out of the map; absent and `null` are the
    /// same. A name is taken once: a second take is the action's fault
    /// ([`Fault::Repeated`]), whatever the caller sent.
    pub fn take(&mut self, name: &'static str) -> Field {
        let repeated = self.taken.contains(&name);
        self.taken.push(name);
        Field {
            name,
            value: self.map.remove(name).filter(|v| !matches!(v, Value::Null)),
            repeated,
        }
    }

    /// Refuses the first argument no field took. Its name is the caller's
    /// text: at most 64 bytes of it are repeated.
    pub fn finish(&mut self) -> Result<(), ArgError> {
        match self.map.keys().next() {
            Some(k) => Err(ArgError::new(
                crate::named::shown(k).to_owned(),
                Fault::Unknown,
            )),
            None => Ok(()),
        }
    }
}

/// Text and bytes of `v`, and of what it holds, overwritten with zeros.
pub(crate) fn wipe(v: &mut Value) {
    use zeroize::Zeroize;
    match v {
        Value::Str(s) => s.zeroize(),
        Value::Bytes(b) => b.zeroize(),
        Value::Array(items) => items.iter_mut().for_each(wipe),
        Value::Map(m) => m.values_mut().for_each(wipe),
        _ => {}
    }
}

/// What no field took is cleared: when a call is refused on one field, a
/// passphrase or a token that was still in the map does not stay in freed
/// memory. A value that a field refused is cleared by [`Field::optional`], and
/// arguments that are no map by [`Reader::new`]. Not cleared here: a value a
/// field took (a secret type clears itself; plain text and bytes are the
/// handler's), and the buffer the transport decoded the arguments from.
impl Drop for Reader {
    fn drop(&mut self) {
        self.map.values_mut().for_each(wipe);
    }
}

/// One argument on its way into a field.
pub struct Field {
    name: &'static str,
    value: Option<Value>,
    repeated: bool,
}

impl Field {
    /// `#[param(nonempty)]`: the empty text is not there (a form sends an
    /// empty field as `""`). A text of white space is a value: a secret is
    /// never trimmed.
    pub fn nonempty(mut self) -> Self {
        if matches!(&self.value, Some(Value::Str(s)) if s.is_empty()) {
            self.value = None;
        }
        self
    }

    /// `#[param(trim, nonempty)]`: a text that is empty or white space is not
    /// there.
    pub fn nonblank(mut self) -> Self {
        if matches!(&self.value, Some(Value::Str(s)) if s.trim().is_empty()) {
            self.value = None;
        }
        self
    }

    pub fn required<T>(
        self,
        f: impl FnOnce(&mut Value) -> Result<T, Fault>,
    ) -> Result<T, ArgError> {
        let name = self.name;
        match self.optional(f) {
            Ok(Some(v)) => Ok(v),
            Ok(None) => Err(ArgError::new(name, Fault::Missing)),
            Err(e) => Err(e),
        }
    }

    pub fn optional<T>(
        self,
        f: impl FnOnce(&mut Value) -> Result<T, Fault>,
    ) -> Result<Option<T>, ArgError> {
        let Some(mut v) = self.value else {
            return match self.repeated {
                true => Err(ArgError::new(self.name, Fault::Repeated)),
                false => Ok(None),
            };
        };
        let r = match self.repeated {
            true => Err(Fault::Repeated),
            false => f(&mut v),
        };
        match r {
            Ok(t) => Ok(Some(t)),
            Err(fault) => {
                // a refused value may be a secret of the wrong type (a
                // passphrase sent as bytes): cleared before it is freed
                wipe(&mut v);
                Err(ArgError::new(self.name, fault))
            }
        }
    }
}

/// The arguments of one action: what it declares and how it reads them.
/// Made by `#[derive(Args)]`; never written by hand.
pub trait Args: Sized {
    /// The parameter names, checked when the struct is compiled.
    const NAMES: Names;

    /// Every parameter with its declared meta, in field order.
    fn params() -> Vec<(&'static str, ParamMeta)>;

    /// The fields from `r` (a struct inside another one, `#[param(flatten)]`,
    /// reads from the same arguments).
    fn read(r: &mut Reader) -> Result<Self, ArgError>;

    /// The struct from an action's arguments, which it takes.
    fn decode(args: Value) -> Result<Self, ArgError> {
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
    const NAMES: Names = Names {
        own: &[],
        flat: &[],
    };

    fn params() -> Vec<(&'static str, ParamMeta)> {
        Vec::new()
    }

    fn read(_: &mut Reader) -> Result<Self, ArgError> {
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
        let mut r = Reader::new(args).unwrap();
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
            Reader::new(Value::UInt(1)).err(),
            Some(ArgError::new("args", Fault::NotAMap))
        );
    }

    /// One name is one field: a second take is refused, given or not, so a struct
    /// that names a parameter twice cannot read it as two types.
    #[test]
    fn a_name_is_taken_once() {
        for args in [map(&[("name", Value::from("x"))]), map(&[])] {
            let mut r = Reader::new(args).unwrap();
            assert!(r.take("name").optional(String::from_value).is_ok());
            assert_eq!(
                r.take("name").optional(u32::from_value),
                Err(ArgError::new("name", Fault::Repeated))
            );
            assert_eq!(
                r.take("name").required(String::from_value),
                Err(ArgError::new("name", Fault::Repeated))
            );
        }
    }

    /// The name of an unknown argument is the caller's text: an error repeats at
    /// most 64 bytes of it, on a character boundary.
    #[test]
    fn an_unknown_name_is_cut() {
        let long = "k".repeat(50_000);
        let e = Reader::new(map(&[(&long, Value::UInt(1))]))
            .unwrap()
            .finish()
            .unwrap_err();
        assert_eq!(e.field, "k".repeat(64));
        assert!(e.to_string().len() < 100);
        let wide = "é".repeat(100);
        let e = Reader::new(map(&[(&wide, Value::UInt(1))]))
            .unwrap()
            .finish()
            .unwrap_err();
        assert_eq!(e.field, "é".repeat(32));
        // an unknown name with a null is unknown too
        let e = Reader::new(map(&[("zzz", Value::Null)])).unwrap().finish();
        assert_eq!(e, Err(ArgError::new("zzz", Fault::Unknown)));
    }

    #[test]
    fn numbers_are_whole_and_in_range() {
        let int = |v: &mut Value| u8::from_value(v);
        assert_eq!(int(&mut Value::UInt(7)), Ok(7));
        assert_eq!(int(&mut Value::Float(7.0)), Ok(7));
        assert_eq!(
            int(&mut Value::Float(0.5)),
            Err(Fault::Int(IntError::Fractional))
        );
        assert_eq!(
            int(&mut Value::Int(-1)),
            Err(Fault::Int(IntError::Negative))
        );
        assert_eq!(
            int(&mut Value::UInt(256)),
            Err(Fault::Int(IntError::OutOfRange))
        );
        assert_eq!(int(&mut Value::from("7")), Err(Fault::Type("a number")));
        assert_eq!(f64::from_value(&mut Value::UInt(2)), Ok(2.0));
        assert_eq!(f64::from_value(&mut Value::Int(-2)), Ok(-2.0));
        assert_eq!(
            f64::from_value(&mut Value::Float(f64::NAN)),
            Err(Fault::NotFinite)
        );
        assert_eq!(
            f64::from_value(&mut Value::from("2")),
            Err(Fault::Type("a number"))
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
        assert_eq!(
            by_name::<Mode>(&mut Value::from("replace")),
            Ok(Mode::Replace)
        );
        assert!(matches!(
            by_name::<Mode>(&mut Value::from("Replace")),
            Err(Fault::Name(_))
        ));
        assert!(matches!(
            by_name::<Mode>(&mut Value::from(" replace ")),
            Err(Fault::Name(_))
        ));
        assert_eq!(
            by_name_trimmed::<Mode>(&mut Value::from(" replace ")),
            Ok(Mode::Replace)
        );
        assert_eq!(
            by_name::<Mode>(&mut Value::UInt(1)),
            Err(Fault::Type("a name"))
        );
        assert_eq!(by_index::<Mode>(&mut Value::UInt(1)), Ok(Mode::Replace));
        assert_eq!(
            by_index::<Mode>(&mut Value::UInt(2)),
            Err(Fault::Index { index: 2, len: 2 })
        );
        assert_eq!(
            by_index::<Mode>(&mut Value::from("add")),
            Err(Fault::Type("an index"))
        );
        assert_eq!(
            names::<Mode>(&mut Value::Array(vec!["add".into(), Value::UInt(1)])),
            Err(Fault::Item {
                index: 1,
                fault: Box::new(Fault::Type("a name"))
            })
        );
    }

    /// `nonempty` is the empty text only; white space is empty only for a field
    /// that is trimmed (`nonblank`). A secret of spaces stays a secret.
    #[test]
    fn an_empty_text_of_a_nonempty_field_is_not_there() {
        let args = || map(&[("a", Value::from(" ")), ("b", Value::from(""))]);
        let mut r = Reader::new(args()).unwrap();
        assert_eq!(
            r.take("a").nonempty().optional(String::from_value),
            Ok(Some(" ".to_owned()))
        );
        assert_eq!(
            r.take("b").nonempty().required(String::from_value),
            Err(ArgError::new("b", Fault::Missing))
        );
        let mut r = Reader::new(args()).unwrap();
        assert_eq!(r.take("a").nonblank().optional(trimmed), Ok(None));
        assert_eq!(r.take("b").nonblank().optional(trimmed), Ok(None));
        // without `nonempty` an empty text is a value
        let mut r = Reader::new(args()).unwrap();
        assert_eq!(r.take("b").required(String::from_value), Ok(String::new()));
    }

    #[test]
    fn no_parameters_means_no_arguments() {
        assert_eq!(<()>::decode(map(&[])), Ok(()));
        assert_eq!(
            <()>::decode(map(&[("x", Value::UInt(1))])),
            Err(ArgError::new("x", Fault::Unknown))
        );
        assert!(<()>::action().params.is_empty());
    }

    /// The check the derive asserts at compile time: a name declared twice, by
    /// two fields or through a flattened struct at any depth.
    #[test]
    fn names_find_a_repeat_at_any_depth() {
        const INNER: Names = Names {
            own: &["name", "n"],
            flat: &[],
        };
        const MID: Names = Names {
            own: &["mid"],
            flat: &[&INNER],
        };
        const GOOD: Names = Names {
            own: &["a", "nam"],
            flat: &[&MID],
        };
        const BAD: Names = Names {
            own: &["a", "name"],
            flat: &[&MID],
        };
        const TWICE: Names = Names {
            own: &[],
            flat: &[&INNER, &MID],
        };
        const OWN: Names = Names {
            own: &["x", "x"],
            flat: &[],
        };
        assert!(!GOOD.repeats_in(&GOOD) && !INNER.repeats_in(&INNER));
        assert!(BAD.repeats_in(&BAD) && TWICE.repeats_in(&TWICE) && OWN.repeats_in(&OWN));
        assert_eq!(
            (BAD.count("name"), GOOD.count("name"), GOOD.count("zz")),
            (2, 1, 0)
        );
    }

    /// A value its field refuses is left where it was (so it can be cleared), and
    /// a value its field takes is moved out.
    #[test]
    fn a_refused_value_stays_and_a_taken_one_moves() {
        let mut v = Value::Bytes(vec![1, 2, 3]);
        assert_eq!(String::from_value(&mut v), Err(Fault::Type("text")));
        assert_eq!(v, Value::Bytes(vec![1, 2, 3]));
        assert_eq!(Vec::<u8>::from_value(&mut v), Ok(vec![1, 2, 3]));
        assert_eq!(v, Value::Null);
        // the reader clears what the field refused: a secret of the wrong type
        let mut seen = Vec::new();
        let args = map(&[("passphrase", Value::Bytes(b"hunter2".to_vec()))]);
        let mut r = Reader::new(args).unwrap();
        let e = r.take("passphrase").optional(|v: &mut Value| {
            let r = String::from_value(v);
            seen.push(v.clone());
            r
        });
        assert_eq!(e, Err(ArgError::new("passphrase", Fault::Type("text"))));
        assert_eq!(
            seen,
            [Value::Bytes(b"hunter2".to_vec())],
            "left for the wipe"
        );
    }

    /// What a refused call leaves in the map is zeroed when the reader goes.
    #[test]
    fn what_no_field_took_is_cleared() {
        let mut v = map(&[
            ("passphrase", Value::from("hunter2")),
            ("nested", map(&[("k", Value::Bytes(vec![7; 4]))])),
            ("list", Value::Array(vec![Value::from("s")])),
            ("n", Value::UInt(1)),
        ]);
        wipe(&mut v);
        let Value::Map(m) = v else { return };
        assert_eq!(m["passphrase"], Value::Str(String::new()));
        assert_eq!(m["nested"], map(&[("k", Value::Bytes(Vec::new()))]));
        assert_eq!(m["list"], Value::Array(vec![Value::Str(String::new())]));
        assert_eq!(m["n"], Value::UInt(1));
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
