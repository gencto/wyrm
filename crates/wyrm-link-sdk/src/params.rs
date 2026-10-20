//! Driver config from `~def.params` (a CBOR map, spec 02 user content).
//! No serde on this path: drivers read fields with these helpers.

use crate::error::{LinkError, Result};
use std::collections::BTreeMap;
use wyrm_core::Value;

/// A driver config that can be built from `~def.params`.
pub trait FromParams: Sized {
    fn from_params(params: &Value) -> Result<Self>;
}

/// Field access on a params map with path-aware errors.
pub struct Fields<'a> {
    map: &'a BTreeMap<String, Value>,
    at: String,
}

fn bad(at: &str, key: &str, what: &str) -> LinkError {
    let path = if at.is_empty() {
        key.to_owned()
    } else {
        format!("{at}.{key}")
    };
    LinkError::invalid_parameter(format!("params.{path}: {what}"))
}

impl<'a> Fields<'a> {
    pub fn new(v: &'a Value) -> Result<Self> {
        Self::at(v, "")
    }

    fn at(v: &'a Value, at: &str) -> Result<Self> {
        match v {
            Value::Map(map) => Ok(Self {
                map,
                at: at.to_owned(),
            }),
            _ => Err(LinkError::invalid_parameter(format!(
                "params{}{at}: expected a map",
                if at.is_empty() { "" } else { "." }
            ))),
        }
    }

    /// Reject keys not in `known` (typos must not pass silently).
    pub fn only(&self, known: &[&str]) -> Result<()> {
        match self.map.keys().find(|k| !known.contains(&k.as_str())) {
            Some(k) => Err(bad(&self.at, k, "unknown field")),
            None => Ok(()),
        }
    }

    pub fn get(&self, key: &str) -> Option<&'a Value> {
        self.map.get(key)
    }

    pub fn str(&self, key: &str) -> Result<&'a str> {
        match self.get(key) {
            Some(Value::Str(s)) => Ok(s),
            Some(_) => Err(bad(&self.at, key, "expected a string")),
            None => Err(bad(&self.at, key, "missing")),
        }
    }

    pub fn opt_str(&self, key: &str) -> Result<Option<&'a str>> {
        self.get(key).map(|_| self.str(key)).transpose()
    }

    pub fn f64_or(&self, key: &str, default: f64) -> Result<f64> {
        match self.get(key) {
            None => Ok(default),
            Some(v) => v
                .as_f64()
                .filter(|x| x.is_finite())
                .ok_or_else(|| bad(&self.at, key, "expected a finite number")),
        }
    }

    pub fn u64_or(&self, key: &str, default: u64) -> Result<u64> {
        match self.get(key) {
            None => Ok(default),
            Some(Value::UInt(u)) => Ok(*u),
            Some(Value::Float(f)) if f.fract() == 0.0 && *f >= 0.0 && *f <= u64::MAX as f64 => {
                Ok(*f as u64)
            }
            Some(_) => Err(bad(&self.at, key, "expected a non-negative integer")),
        }
    }

    pub fn bool_or(&self, key: &str, default: bool) -> Result<bool> {
        match self.get(key) {
            None => Ok(default),
            Some(Value::Bool(b)) => Ok(*b),
            Some(_) => Err(bad(&self.at, key, "expected true or false")),
        }
    }

    /// Each element of the array `key` as a nested map.
    pub fn list(&self, key: &str) -> Result<Vec<Fields<'a>>> {
        match self.get(key) {
            None => Ok(Vec::new()),
            Some(Value::Array(items)) => items
                .iter()
                .enumerate()
                .map(|(i, v)| {
                    let at = if self.at.is_empty() {
                        format!("{key}[{i}]")
                    } else {
                        format!("{}.{key}[{i}]", self.at)
                    };
                    Fields::at(v, &at)
                })
                .collect(),
            Some(_) => Err(bad(&self.at, key, "expected an array")),
        }
    }
}

/// `u64` that must fit the target integer type.
pub fn narrow<T: TryFrom<u64>>(v: u64, what: &str) -> Result<T> {
    T::try_from(v).map_err(|_| LinkError::invalid_parameter(format!("params.{what}: out of range")))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn map(kv: &[(&str, Value)]) -> Value {
        Value::Map(
            kv.iter()
                .map(|(k, v)| ((*k).to_owned(), v.clone()))
                .collect(),
        )
    }

    #[test]
    fn fields() {
        let v = map(&[
            ("host", Value::from("h")),
            ("port", Value::UInt(502)),
            (
                "points",
                Value::Array(vec![map(&[("x", Value::Bool(true))])]),
            ),
        ]);
        let f = Fields::new(&v).unwrap();
        assert_eq!(f.str("host").unwrap(), "h");
        assert_eq!(f.u64_or("port", 1).unwrap(), 502);
        assert_eq!(f.u64_or("unit", 1).unwrap(), 1);
        assert!(f.list("points").unwrap()[0].bool_or("x", false).unwrap());
        let e = f.str("missing").unwrap_err();
        assert_eq!(e.message, "params.missing: missing");
        let e = f.list("points").unwrap()[0].str("x").unwrap_err();
        assert_eq!(e.message, "params.points[0].x: expected a string");
        assert!(f.only(&["host", "port"]).is_err());
        assert!(f.only(&["host", "port", "points"]).is_ok());
        assert!(narrow::<u8>(300, "unit").is_err());
    }
}
