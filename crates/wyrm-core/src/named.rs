//! `name_enum!`: one declaration per closed set of names that has no wire code.
//!
//! A field, argument or state whose values are a fixed list of names is an enum
//! (docs/rust-rules.md §6), not a `String`. `wire_enum!` declares the sets with a
//! wire code; `name_enum!` declares the others. Each variant lists its name, and
//! the macro generates the enum and:
//!
//! * `name(self) -> &'static str`, `ALL` and `NAMES` (the names in declaration
//!   order: the list a catalog shows and an error names);
//! * `from_name(&str) -> Option<Self>` and `FromStr` (`Err` is [`UnknownValue`]);
//! * `Display` (the name);
//! * [`Named`], so the by-name codecs below take it;
//! * minicbor `Encode`/`Decode` and serde `Serialize`/`Deserialize` as the name:
//!   a CBOR text string, a postcard string, a JSON string. That is the form a
//!   `String` field had, so a store or a file written with the `String` reads
//!   into the enum and writes back the same bytes. A name that is not in the
//!   set is a decode error naming the set (fail closed): an old build never
//!   reads a newer name as some other variant.
//!
//! `pub enum X as "set" without codec { … }` leaves the codecs out, for a type
//! that keeps another form (a registry type encoded by its index derives its own).
//!
//! A `wire_enum!` type keeps its code on the wire. Where a store keeps one by
//! its name instead (an agent task's state, a package grant's level), the field
//! says so with `#[cbor(with = "wyrm_core::named::cbor")]` and
//! `#[serde(with = "wyrm_core::named::serde")]`: a by-name form is never chosen
//! silently for a type that has a code.
//!
//! ```
//! wyrm_core::name_enum! {
//!     /// Example set.
//!     #[derive(Default)]
//!     pub enum Mode as "mode" {
//!         #[default]
//!         Hold => "hold",
//!         Clear => "clear",
//!     }
//! }
//! assert_eq!(Mode::Clear.name(), "clear");
//! assert_eq!(Mode::NAMES, &["hold", "clear"]);
//! assert_eq!(Mode::from_name("hold"), Some(Mode::Hold));
//! assert_eq!("clear".parse::<Mode>(), Ok(Mode::Clear));
//! assert!("Clear".parse::<Mode>().is_err());
//! ```

use core::fmt;

/// A closed set of names: a `name_enum!` type, or a `wire_enum!` type read by name.
pub trait Named: Copy + Sized + 'static {
    /// What the set is, for errors (`backup status`).
    const SET: &'static str;
    /// Every name of the set, for errors.
    const NAMES: &'static [&'static str];
    fn name(self) -> &'static str;
    fn from_name(name: &str) -> Option<Self>;
}

/// Longest part of an unknown name an error repeats.
const SHOWN: usize = 64;

/// A name that is not in its set: from the wire, a store or a file.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UnknownValue {
    /// [`Named::SET`].
    pub set: &'static str,
    /// The text, cut at 64 bytes (on a character boundary).
    pub name: String,
    /// [`Named::NAMES`].
    pub known: &'static [&'static str],
}

impl UnknownValue {
    pub fn new(set: &'static str, known: &'static [&'static str], name: &str) -> Self {
        let mut end = name.len().min(SHOWN);
        while !name.is_char_boundary(end) {
            end -= 1;
        }
        Self {
            set,
            name: name.get(..end).unwrap_or_default().to_owned(),
            known,
        }
    }
}

impl fmt::Display for UnknownValue {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "{}: unknown name {:?} (one of {})",
            self.set,
            self.name,
            self.known.join(", ")
        )
    }
}

impl std::error::Error for UnknownValue {}

/// `name` as a value of `T`, or the typed error.
pub fn parse<T: Named>(name: &str) -> Result<T, UnknownValue> {
    T::from_name(name).ok_or_else(|| UnknownValue::new(T::SET, T::NAMES, name))
}

/// `#[cbor(with = "wyrm_core::named::cbor")]`: a [`Named`] value as its name (a
/// CBOR text string); an unknown name is a decode error.
pub mod cbor {
    use super::Named;
    use minicbor::{decode as dec, encode as enc, Decoder, Encoder};

    pub fn encode<T: Named, C, W: enc::Write>(
        v: &T,
        e: &mut Encoder<W>,
        _ctx: &mut C,
    ) -> Result<(), enc::Error<W::Error>> {
        e.str(v.name())?;
        Ok(())
    }

    pub fn decode<T: Named, C>(d: &mut Decoder<'_>, _ctx: &mut C) -> Result<T, dec::Error> {
        let s = d.str()?;
        super::parse::<T>(s).map_err(dec::Error::message)
    }
}

/// `#[serde(with = "wyrm_core::named::serde")]`: a [`Named`] value as its name (a
/// string in JSON and in postcard); an unknown name is a decode error.
pub mod serde {
    use super::Named;
    use ::serde::{de, Deserialize, Deserializer, Serializer};

    pub fn serialize<T: Named, S: Serializer>(v: &T, s: S) -> Result<S::Ok, S::Error> {
        s.serialize_str(v.name())
    }

    pub fn deserialize<'de, T: Named, D: Deserializer<'de>>(d: D) -> Result<T, D::Error> {
        let s = String::deserialize(d)?;
        super::parse::<T>(&s).map_err(<D::Error as de::Error>::custom)
    }
}

/// `#[serde(default, with = "wyrm_core::named::serde_or_empty")]`: an
/// `Option<T>` kept as a name, `None` as the empty string. For a field that
/// was a `String` whose empty value meant "not set": the same text reads back,
/// and anything else than a name of the set or `""` is a decode error.
pub mod serde_or_empty {
    use super::Named;
    use ::serde::{de, Deserialize, Deserializer, Serializer};

    pub fn serialize<T: Named, S: Serializer>(v: &Option<T>, s: S) -> Result<S::Ok, S::Error> {
        s.serialize_str(v.map_or("", |v| v.name()))
    }

    pub fn deserialize<'de, T: Named, D: Deserializer<'de>>(d: D) -> Result<Option<T>, D::Error> {
        let s = String::deserialize(d)?;
        if s.is_empty() {
            return Ok(None);
        }
        super::parse::<T>(&s)
            .map(Some)
            .map_err(<D::Error as de::Error>::custom)
    }
}

/// `#[serde(default, with = "wyrm_core::named::serde_opt")]`: an `Option<T>` kept as a
/// name when it is there (a config field that may be left out).
pub mod serde_opt {
    use super::Named;
    use ::serde::{de, Deserialize, Deserializer, Serializer};

    pub fn serialize<T: Named, S: Serializer>(v: &Option<T>, s: S) -> Result<S::Ok, S::Error> {
        match v {
            Some(v) => s.serialize_some(v.name()),
            None => s.serialize_none(),
        }
    }

    pub fn deserialize<'de, T: Named, D: Deserializer<'de>>(d: D) -> Result<Option<T>, D::Error> {
        match Option::<String>::deserialize(d)? {
            None => Ok(None),
            Some(s) => super::parse::<T>(&s)
                .map(Some)
                .map_err(<D::Error as de::Error>::custom),
        }
    }
}

#[doc(hidden)]
pub mod __private {
    pub use minicbor;
    pub use serde;
}

#[macro_export]
macro_rules! name_enum {
    (
        $(#[$meta:meta])*
        $vis:vis enum $ty:ident as $set:literal without codec {
            $(
                $(#[$vmeta:meta])*
                $variant:ident => $name:literal
            ),+ $(,)?
        }
    ) => {
        $crate::name_enum! {
            @core
            $(#[$meta])*
            $vis enum $ty as $set {
                $( $(#[$vmeta])* $variant => $name, )+
            }
        }
    };
    (
        $(#[$meta:meta])*
        $vis:vis enum $ty:ident as $set:literal {
            $(
                $(#[$vmeta:meta])*
                $variant:ident => $name:literal
            ),+ $(,)?
        }
    ) => {
        $crate::name_enum! {
            @core
            $(#[$meta])*
            $vis enum $ty as $set {
                $( $(#[$vmeta])* $variant => $name, )+
            }
        }

        impl<C> $crate::named::__private::minicbor::Encode<C> for $ty {
            fn encode<W: $crate::named::__private::minicbor::encode::Write>(
                &self,
                e: &mut $crate::named::__private::minicbor::Encoder<W>,
                ctx: &mut C,
            ) -> ::core::result::Result<
                (),
                $crate::named::__private::minicbor::encode::Error<W::Error>,
            > {
                $crate::named::cbor::encode(self, e, ctx)
            }
        }

        impl<'b, C> $crate::named::__private::minicbor::Decode<'b, C> for $ty {
            fn decode(
                d: &mut $crate::named::__private::minicbor::Decoder<'b>,
                ctx: &mut C,
            ) -> ::core::result::Result<Self, $crate::named::__private::minicbor::decode::Error>
            {
                $crate::named::cbor::decode(d, ctx)
            }
        }

        impl $crate::named::__private::serde::Serialize for $ty {
            fn serialize<S: $crate::named::__private::serde::Serializer>(
                &self,
                s: S,
            ) -> ::core::result::Result<S::Ok, S::Error> {
                $crate::named::serde::serialize(self, s)
            }
        }

        impl<'de> $crate::named::__private::serde::Deserialize<'de> for $ty {
            fn deserialize<D: $crate::named::__private::serde::Deserializer<'de>>(
                d: D,
            ) -> ::core::result::Result<Self, D::Error> {
                $crate::named::serde::deserialize(d)
            }
        }
    };
    (
        @core
        $(#[$meta:meta])*
        $vis:vis enum $ty:ident as $set:literal {
            $(
                $(#[$vmeta:meta])*
                $variant:ident => $name:literal
            ),+ $(,)?
        }
    ) => {
        $(#[$meta])*
        #[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
        $vis enum $ty {
            $( $(#[$vmeta])* $variant, )+
        }

        impl $ty {
            /// Every variant, in declaration order.
            pub const ALL: &'static [Self] = &[$(Self::$variant),+];

            /// Every name, in declaration order.
            pub const NAMES: &'static [&'static str] = &[$($name),+];

            /// The name.
            pub const fn name(self) -> &'static str {
                match self {
                    $(Self::$variant => $name,)+
                }
            }

            /// The variant with this name; `None` for any other text.
            pub fn from_name(name: &str) -> ::core::option::Option<Self> {
                match name {
                    $($name => ::core::option::Option::Some(Self::$variant),)+
                    _ => ::core::option::Option::None,
                }
            }
        }

        impl $crate::named::Named for $ty {
            const SET: &'static str = $set;
            const NAMES: &'static [&'static str] = $ty::NAMES;
            fn name(self) -> &'static str {
                $ty::name(self)
            }
            fn from_name(name: &str) -> ::core::option::Option<Self> {
                $ty::from_name(name)
            }
        }

        impl ::core::str::FromStr for $ty {
            type Err = $crate::named::UnknownValue;
            fn from_str(s: &str) -> ::core::result::Result<Self, Self::Err> {
                $crate::named::parse::<Self>(s)
            }
        }

        impl ::core::fmt::Display for $ty {
            fn fmt(&self, f: &mut ::core::fmt::Formatter<'_>) -> ::core::fmt::Result {
                f.write_str(self.name())
            }
        }
    };
}

#[cfg(test)]
mod tests {
    use super::*;

    crate::name_enum! {
        /// A test set.
        #[derive(Default, PartialOrd, Ord)]
        enum Job as "job status" {
            #[default]
            Running => "running",
            Done => "done",
            Failed => "failed",
        }
    }

    #[derive(Debug, PartialEq, ::serde::Serialize, ::serde::Deserialize)]
    struct Old {
        status: String,
        sent: String,
    }

    #[derive(Debug, PartialEq, ::serde::Serialize, ::serde::Deserialize)]
    struct New {
        status: Job,
        #[serde(default, with = "serde_or_empty")]
        sent: Option<Job>,
    }

    #[derive(Debug, PartialEq, minicbor::Encode, minicbor::Decode)]
    struct OldCbor {
        #[n(0)]
        status: String,
        #[n(1)]
        state: String,
    }

    #[derive(Debug, PartialEq, minicbor::Encode, minicbor::Decode)]
    struct NewCbor {
        #[n(0)]
        status: Job,
        #[n(1)]
        #[cbor(with = "crate::named::cbor")]
        state: crate::Perm,
    }

    #[test]
    fn names_and_lookup() {
        assert_eq!(Job::NAMES, &["running", "done", "failed"]);
        assert_eq!(Job::ALL.len(), Job::NAMES.len());
        for (v, n) in Job::ALL.iter().zip(Job::NAMES) {
            assert_eq!(v.name(), *n);
            assert_eq!(Job::from_name(n), Some(*v));
            assert_eq!(v.to_string(), *n);
        }
        assert_eq!(Job::default(), Job::Running);
        let e = "Done".parse::<Job>().unwrap_err();
        assert_eq!(
            e.to_string(),
            "job status: unknown name \"Done\" (one of running, done, failed)"
        );
        assert!(Job::from_name("").is_none());
        // a long unknown name is cut, on a character boundary
        let long = "é".repeat(100);
        assert_eq!(UnknownValue::new("x", &[], &long).name.len(), 64);
    }

    /// The enum writes the bytes the `String` wrote, in each codec, and an
    /// unknown name is a decode error.
    #[test]
    fn same_bytes_as_the_string_it_replaces() {
        for (status, sent) in [("done", ""), ("failed", "running"), ("running", "done")] {
            let old = Old {
                status: status.into(),
                sent: sent.into(),
            };
            let json = serde_json::to_vec(&old).unwrap();
            let new: New = serde_json::from_slice(&json).unwrap();
            assert_eq!(new.status.name(), status);
            assert_eq!(new.sent.map_or("", |s| s.name()), sent);
            assert_eq!(serde_json::to_vec(&new).unwrap(), json);
            // postcard is not self-describing: a derived enum would write an index
            let pc = postcard::to_stdvec(&old).unwrap();
            let new: New = postcard::from_bytes(&pc).unwrap();
            assert_eq!(new.status.name(), status);
            assert_eq!(postcard::to_stdvec(&new).unwrap(), pc);

            let cbor = minicbor::to_vec(OldCbor {
                status: status.into(),
                state: "write".into(),
            })
            .unwrap();
            let new: NewCbor = minicbor::decode(&cbor).unwrap();
            assert_eq!(new.state, crate::Perm::Write);
            assert_eq!(minicbor::to_vec(&new).unwrap(), cbor);
        }
        assert!(serde_json::from_str::<New>(r#"{"status":"paused","sent":""}"#).is_err());
        assert!(serde_json::from_str::<New>(r#"{"status":"done","sent":"x"}"#).is_err());
        let new: New = serde_json::from_str(r#"{"status":"done"}"#).unwrap();
        assert_eq!(new.sent, None);
        let bad = minicbor::to_vec(OldCbor {
            status: "paused".into(),
            state: "read".into(),
        })
        .unwrap();
        let e = minicbor::decode::<NewCbor>(&bad).unwrap_err().to_string();
        assert!(e.contains("job status: unknown name \"paused\""), "{e}");
        let bad = minicbor::to_vec(OldCbor {
            status: "done".into(),
            state: "everything".into(),
        })
        .unwrap();
        assert!(minicbor::decode::<NewCbor>(&bad).is_err());
    }
}
