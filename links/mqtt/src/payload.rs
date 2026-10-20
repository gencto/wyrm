//! Plain-topic payloads: raw text or JSON (RFC 6901 pointer), to and from
//! tree values. `serde_json` is used here only, at the MQTT payload edge;
//! the WYRM wire stays CBOR.

use wyrm_core::Value;
use wyrm_link_sdk::driver::ParamEnum;
use wyrm_link_sdk::ParamEnum;

#[derive(Debug, Clone, Copy, PartialEq, Eq, ParamEnum)]
pub enum Format {
    /// UTF-8 text: `21.5`, `true`, `on`, `hello`.
    Raw,
    /// A JSON document; `pointer` selects the value.
    Json,
}

/// Value type of a point.
#[derive(Debug, Clone, Copy, PartialEq, Eq, ParamEnum)]
pub enum Kind {
    Number,
    String,
    Bool,
}

fn number_text(s: &str) -> Option<Value> {
    let s = s.trim();
    if let Ok(i) = s.parse::<i64>() {
        return Some(Value::from(i));
    }
    if let Ok(u) = s.parse::<u64>() {
        return Some(Value::UInt(u));
    }
    s.parse::<f64>()
        .ok()
        .filter(|f| f.is_finite())
        .map(Value::Float)
}

fn bool_text(s: &str) -> Option<bool> {
    match s.trim().to_ascii_lowercase().as_str() {
        "true" | "1" | "on" | "yes" => Some(true),
        "false" | "0" | "off" | "no" => Some(false),
        _ => None,
    }
}

/// Convert a decoded value to the point's kind.
pub fn coerce(v: Value, kind: Kind) -> Result<Value, String> {
    match (kind, v) {
        (_, Value::Null) => Ok(Value::Null),
        (Kind::Number, v @ (Value::Int(_) | Value::UInt(_))) => Ok(v),
        (Kind::Number, Value::Float(f)) if f.is_finite() => Ok(Value::Float(f)),
        (Kind::Number, Value::Str(s)) => {
            number_text(&s).ok_or_else(|| "payload is not a number".to_owned())
        }
        (Kind::Number, Value::Bool(b)) => Ok(Value::UInt(u64::from(b))),
        (Kind::Bool, Value::Bool(b)) => Ok(Value::Bool(b)),
        (Kind::Bool, Value::Int(i)) => Ok(Value::Bool(i != 0)),
        (Kind::Bool, Value::UInt(u)) => Ok(Value::Bool(u != 0)),
        (Kind::Bool, Value::Str(s)) => bool_text(&s)
            .map(Value::Bool)
            .ok_or_else(|| "payload is not a boolean".to_owned()),
        (Kind::String, Value::Str(s)) => Ok(Value::Str(s)),
        (Kind::String, Value::Bool(b)) => Ok(Value::Str(b.to_string())),
        (Kind::String, Value::Int(i)) => Ok(Value::Str(i.to_string())),
        (Kind::String, Value::UInt(u)) => Ok(Value::Str(u.to_string())),
        (Kind::String, Value::Float(f)) => Ok(Value::Str(f.to_string())),
        (k, _) => Err(format!("payload does not convert to {}", k.name())),
    }
}

fn from_json(j: &serde_json::Value, kind: Kind) -> Result<Value, String> {
    use serde_json::Value as J;
    let v = match j {
        J::Null => Value::Null,
        J::Bool(b) => Value::Bool(*b),
        J::Number(n) => match (n.as_i64(), n.as_u64(), n.as_f64()) {
            (Some(i), _, _) => Value::from(i),
            (None, Some(u), _) => Value::UInt(u),
            (None, None, Some(f)) => Value::Float(f),
            _ => return Err("unsupported JSON number".into()),
        },
        J::String(s) => Value::Str(s.clone()),
        // A string point can carry a JSON sub-document as text.
        J::Array(_) | J::Object(_) if kind == Kind::String => Value::Str(j.to_string()),
        J::Array(_) | J::Object(_) => return Err("pointer selects an object or array".into()),
    };
    coerce(v, kind)
}

/// Decode one message payload for a point.
pub fn decode(payload: &[u8], format: Format, pointer: &str, kind: Kind) -> Result<Value, String> {
    match format {
        Format::Raw => {
            let text = std::str::from_utf8(payload).map_err(|_| "payload is not UTF-8")?;
            coerce(Value::Str(text.to_owned()), kind)
        }
        Format::Json => {
            let doc: serde_json::Value =
                serde_json::from_slice(payload).map_err(|e| format!("payload is not JSON: {e}"))?;
            let j = doc
                .pointer(pointer)
                .ok_or_else(|| format!("JSON pointer {pointer:?} not found"))?;
            from_json(j, kind)
        }
    }
}

fn to_json(v: &Value) -> Result<serde_json::Value, String> {
    use serde_json::Value as J;
    Ok(match v {
        Value::Null => J::Null,
        Value::Bool(b) => J::Bool(*b),
        Value::Int(i) => J::from(*i),
        Value::UInt(u) => J::from(*u),
        Value::Float(f) => serde_json::Number::from_f64(*f)
            .map(J::Number)
            .ok_or("value is not finite")?,
        Value::Str(s) => J::String(s.clone()),
        _ => return Err("only scalar values can be written".into()),
    })
}

/// Unescape one RFC 6901 reference token.
fn token(t: &str) -> String {
    t.replace("~1", "/").replace("~0", "~")
}

/// Encode a written value. For JSON with a pointer `/a/b` the payload is
/// `{"a":{"b":<v>}}` (tokens are object keys).
pub fn encode(v: &Value, format: Format, pointer: &str) -> Result<Vec<u8>, String> {
    match format {
        Format::Raw => Ok(match v {
            Value::Str(s) => s.clone().into_bytes(),
            Value::Bool(b) => b.to_string().into_bytes(),
            Value::Int(i) => i.to_string().into_bytes(),
            Value::UInt(u) => u.to_string().into_bytes(),
            Value::Float(f) if f.is_finite() => f.to_string().into_bytes(),
            Value::Float(_) => return Err("value is not finite".into()),
            _ => return Err("only scalar values can be written".into()),
        }),
        Format::Json => {
            let mut doc = to_json(v)?;
            if !pointer.is_empty() {
                for t in pointer[1..].rsplit('/') {
                    let mut m = serde_json::Map::new();
                    m.insert(token(t), doc);
                    doc = serde_json::Value::Object(m);
                }
            }
            serde_json::to_vec(&doc).map_err(|e| e.to_string())
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn raw_text() {
        let d = |p: &[u8], k| decode(p, Format::Raw, "", k);
        assert_eq!(d(b"21.5", Kind::Number), Ok(Value::Float(21.5)));
        assert_eq!(d(b" 42\n", Kind::Number), Ok(Value::UInt(42)));
        assert_eq!(d(b"-7", Kind::Number), Ok(Value::Int(-7)));
        assert_eq!(d(b"ON", Kind::Bool), Ok(Value::Bool(true)));
        assert_eq!(d(b"0", Kind::Bool), Ok(Value::Bool(false)));
        assert_eq!(d(b"hello", Kind::String), Ok(Value::from("hello")));
        assert!(d(b"abc", Kind::Number).is_err());
        assert!(d(b"NaN", Kind::Number).is_err());
        assert!(d(&[0xff, 0xfe], Kind::String).is_err());
    }

    #[test]
    fn json_pointer() {
        let doc = br#"{"a":{"b":[1,{"c":true,"t":"21.5"}]},"x/y":3,"s":{"k":1}}"#;
        let d = |p: &str, k| decode(doc, Format::Json, p, k);
        assert_eq!(d("/a/b/0", Kind::Number), Ok(Value::UInt(1)));
        assert_eq!(d("/a/b/1/c", Kind::Bool), Ok(Value::Bool(true)));
        assert_eq!(d("/a/b/1/t", Kind::Number), Ok(Value::Float(21.5)));
        assert_eq!(d("/x~1y", Kind::Number), Ok(Value::UInt(3)));
        assert_eq!(d("/s", Kind::String), Ok(Value::from(r#"{"k":1}"#)));
        assert!(d("/s", Kind::Number).is_err());
        assert!(d("/missing", Kind::Number).is_err());
        assert_eq!(
            decode(b"12", Format::Json, "", Kind::Number),
            Ok(Value::UInt(12))
        );
        assert!(decode(b"{", Format::Json, "", Kind::Number).is_err());
    }

    #[test]
    fn encode_values() {
        assert_eq!(encode(&Value::Float(42.0), Format::Raw, "").unwrap(), b"42");
        assert_eq!(
            encode(&Value::Bool(true), Format::Raw, "").unwrap(),
            b"true"
        );
        assert_eq!(
            encode(&Value::Float(1.5), Format::Json, "/set/sp").unwrap(),
            br#"{"set":{"sp":1.5}}"#
        );
        assert_eq!(
            encode(&Value::from("a"), Format::Json, "").unwrap(),
            br#""a""#
        );
        assert!(encode(&Value::Float(f64::NAN), Format::Json, "").is_err());
    }
}
