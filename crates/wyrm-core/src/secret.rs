//! Secret values: zeroed when dropped, never printed. The three types here are
//! the only secret arguments (`wyrm_core::args::SecretArg` is sealed).

use crate::args::{sealed::Sealed, take, ArgValue, Fault, PastedSecretArg, SecretArg};
use crate::meta::TypeCode;
use crate::value::Value;
use std::fmt;
use zeroize::Zeroizing;

/// A secret value. Zeroed on drop; `Debug` prints `***`.
#[derive(Clone)]
pub struct Secret(Zeroizing<Vec<u8>>);

impl Secret {
    pub fn new(bytes: impl Into<Vec<u8>>) -> Self {
        Self(Zeroizing::new(bytes.into()))
    }

    pub fn expose(&self) -> &[u8] {
        &self.0
    }

    pub fn expose_str(&self) -> Option<&str> {
        std::str::from_utf8(&self.0).ok()
    }
}

impl fmt::Debug for Secret {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("***")
    }
}

/// A secret text argument (a passphrase, a token a program sends): a text
/// parameter, with the password editor under `#[param(secret)]`. Never
/// trimmed: its spaces are part of it.
impl ArgValue for Secret {
    const TYPE: TypeCode = TypeCode::String;
    fn from_value(v: &mut Value) -> Result<Self, Fault> {
        // the text's own buffer becomes the secret: no copy is left behind
        take(v, "text", |v| match v {
            Value::Str(s) => Ok(Secret::new(s.into_bytes())),
            other => Err(other),
        })
    }
}

impl Sealed for Secret {}
impl SecretArg for Secret {}

/// A secret binary argument (a link secret's value, a link's token): a binary
/// parameter, with the password editor under `#[param(secret)]`.
#[derive(Clone, Debug)]
pub struct SecretBytes(pub Secret);

impl ArgValue for SecretBytes {
    const TYPE: TypeCode = TypeCode::Binary;
    fn from_value(v: &mut Value) -> Result<Self, Fault> {
        take(v, "bytes", |v| match v {
            Value::Bytes(b) => Ok(SecretBytes(Secret::new(b))),
            other => Err(other),
        })
    }
}

impl Sealed for SecretBytes {}
impl SecretArg for SecretBytes {}

/// A secret a person pastes as one line: an enrolment token. The white space
/// around it is cut (a pasted token often ends with a newline, and a token
/// holds none), so a text of white space is no token.
///
/// This is the one secret that is trimmed, and a named exception
/// (docs/rust-rules.md §12): a field of this type compiles only with
/// `#[param(secret, trim)]`, and the rules count every use (A4). Never for a
/// passphrase or a key: a passphrase is a [`Secret`], whose spaces are part of
/// it (trimmed, a passphrase of spaces would read as "not given").
#[derive(Clone, Debug)]
pub struct SecretLine(pub Secret);

impl PastedSecretArg for SecretLine {
    const TYPE: TypeCode = TypeCode::String;
    fn pasted(v: &mut Value) -> Result<Self, Fault> {
        take(v, "text", |v| match v {
            Value::Str(s) => {
                // the pasted text is cleared; only the token itself is kept
                let s = Zeroizing::new(s);
                Ok(SecretLine(Secret::new(s.trim().as_bytes())))
            }
            other => Err(other),
        })
    }
}

impl Sealed for SecretLine {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn secrets_take_their_value_and_show_nothing() {
        let mut v = Value::from(" a b ");
        let s = Secret::from_value(&mut v).unwrap();
        assert_eq!((s.expose(), v), (&b" a b "[..], Value::Null));
        assert_eq!(format!("{s:?}"), "***");
        let mut v = Value::Bytes(vec![1, 2]);
        assert_eq!(Secret::from_value(&mut v).err(), Some(Fault::Type("text")));
        assert_eq!(v, Value::Bytes(vec![1, 2]), "left for the reader to clear");
        let b = SecretBytes::from_value(&mut v).unwrap();
        assert_eq!(b.0.expose(), [1, 2]);
        assert!(!format!("{b:?}").contains('1'));
        let mut v = Value::from(" tok.en\n");
        let t = SecretLine::pasted(&mut v).unwrap();
        assert_eq!(t.0.expose(), b"tok.en");
        assert!(!format!("{t:?}").contains("tok"));
        let mut v = Value::UInt(1);
        assert_eq!(SecretLine::pasted(&mut v).err(), Some(Fault::Type("text")));
    }
}
