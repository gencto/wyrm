//! The value a sample carries between blocks ([`crate::nodes::Msg::v`], issue #160).
//!
//! A list or a map (a table, an object, an array) is shared: the edges of one output, the
//! probe's last sample of each port (`watch`, spec 06 0.2.18), a block's last input and its
//! last output all hold the one value. It is copied only where a holder changes it
//! ([`Payload::make_mut`]) or takes it apart ([`Payload::into_value`]) while another holder
//! keeps it, so a block that changes its input never changes what a sibling edge got.
//!
//! A scalar (a number, a text, bytes) is held in place: sharing it would cost an allocation
//! per sample that copying it does not, and the pure blocks send one new number per sample.

use std::fmt;
use std::ops::Deref;
use std::sync::Arc;
use wyrm_core::Value;

/// A sample's value: a list or a map shared, any other value in place. Reads go through
/// [`Deref`] to [`Value`]; equality is the values' (two payloads that hold equal values are
/// equal, shared or not).
pub struct Payload(Repr);

enum Repr {
    Here(Value),
    Shared(Arc<Value>),
}

impl Payload {
    /// `v` as a payload: shared when it is a list or a map.
    pub fn new(v: Value) -> Self {
        match v {
            Value::Array(_) | Value::Map(_) => Self(Repr::Shared(Arc::new(v))),
            v => Self(Repr::Here(v)),
        }
    }

    pub fn get(&self) -> &Value {
        match &self.0 {
            Repr::Here(v) => v,
            Repr::Shared(v) => v,
        }
    }

    /// The value itself: moved out when no one else holds it, else a copy.
    pub fn into_value(self) -> Value {
        match self.0 {
            Repr::Here(v) => v,
            Repr::Shared(v) => Arc::unwrap_or_clone(v),
        }
    }

    /// The value to change in place: copied first when another holder shares it.
    pub fn make_mut(&mut self) -> &mut Value {
        match &mut self.0 {
            Repr::Here(v) => v,
            Repr::Shared(v) => Arc::make_mut(v),
        }
    }

    /// Whether `self` and `other` are one value in memory (not only equal ones).
    pub fn shares(&self, other: &Payload) -> bool {
        match (&self.0, &other.0) {
            (Repr::Shared(a), Repr::Shared(b)) => Arc::ptr_eq(a, b),
            _ => false,
        }
    }
}

impl Clone for Payload {
    /// A shared value is not copied; a scalar is.
    fn clone(&self) -> Self {
        Self(match &self.0 {
            Repr::Here(v) => Repr::Here(v.clone()),
            Repr::Shared(v) => Repr::Shared(Arc::clone(v)),
        })
    }

    /// A text or bytes in place reuses its buffer, as [`Value::clone_from`] does.
    fn clone_from(&mut self, source: &Self) {
        match (&mut self.0, &source.0) {
            (Repr::Here(a), Repr::Here(b)) => a.clone_from(b),
            _ => *self = source.clone(),
        }
    }
}

impl Default for Payload {
    fn default() -> Self {
        Self(Repr::Here(Value::Null))
    }
}

impl Deref for Payload {
    type Target = Value;

    fn deref(&self) -> &Value {
        self.get()
    }
}

impl AsRef<Value> for Payload {
    fn as_ref(&self) -> &Value {
        self.get()
    }
}

impl From<Value> for Payload {
    fn from(v: Value) -> Self {
        Self::new(v)
    }
}

impl From<Payload> for Value {
    fn from(p: Payload) -> Self {
        p.into_value()
    }
}

impl PartialEq for Payload {
    fn eq(&self, other: &Self) -> bool {
        self.get() == other.get()
    }
}

impl PartialEq<Value> for Payload {
    fn eq(&self, other: &Value) -> bool {
        self.get() == other
    }
}

impl fmt::Debug for Payload {
    /// As the value: a payload prints as the [`Value`] it holds.
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        self.get().fmt(f)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::BTreeMap;

    fn table() -> Value {
        Value::Map(BTreeMap::from([(
            "rows".to_owned(),
            Value::Array(vec![Value::UInt(1), Value::UInt(2)]),
        )]))
    }

    #[test]
    fn a_list_or_a_map_is_shared_a_scalar_is_not() {
        let a = Payload::new(table());
        let b = a.clone();
        assert!(a.shares(&b));
        assert_eq!(a, b);
        let n = Payload::new(Value::Float(1.0));
        assert!(!n.shares(&n.clone()));
        assert_eq!(n, Value::Float(1.0));
    }

    #[test]
    fn a_change_copies_only_a_shared_value() {
        let a = Payload::new(table());
        let mut b = a.clone();
        if let Value::Map(m) = b.make_mut() {
            m.insert("x".to_owned(), Value::Null);
        }
        assert!(!a.shares(&b));
        assert_eq!(a, table());
        assert_ne!(a, b);
        // the only holder changes it in place
        let mut c = Payload::new(table());
        let before = c.get() as *const Value;
        c.make_mut();
        assert_eq!(before, c.get() as *const Value);
    }

    #[test]
    fn into_value_moves_the_only_holder_and_copies_a_shared_one() {
        let a = Payload::new(table());
        let b = a.clone();
        assert_eq!(b.into_value(), table());
        assert_eq!(a.into_value(), table());
    }

    #[test]
    fn equality_is_the_values_and_debug_prints_the_value() {
        let nan = Payload::new(Value::Array(vec![Value::Float(f64::NAN)]));
        // one value in memory, but NaN is no equal of itself: as the values compare
        assert_ne!(nan, nan.clone());
        assert_eq!(
            format!("{:?}", Payload::new(table())),
            format!("{:?}", table())
        );
    }
}
