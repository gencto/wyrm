//! JSON on the MCP side ↔ WYRM wire types.
//!
//! Numbers map like `wyrmd`/`wyr`: non-negative integers → `UInt`, negative →
//! `Int`, everything else → `Float`. JSON has no byte strings, so binary values
//! travel as `{"$bytes": "<base64>"}` in both directions. Non-finite floats
//! become `null`.

use base64::Engine as _;
use serde_json::{json, Map, Value as Json};
use wyrm_core::meta::{ActionResult, ParamMeta, Profile, TextOrCode};
use wyrm_core::profile::ProfileDef;
use wyrm_core::{ActionMeta, NodeMeta, Sample, Value};

/// Key of the one-field object that carries a byte string.
pub const BYTES_KEY: &str = "$bytes";

const B64: base64::engine::GeneralPurpose = base64::engine::general_purpose::STANDARD;

/// JSON value → wire value. `{"$bytes": "<base64>"}` → `Bytes`.
pub fn json_to_value(j: &Json) -> Result<Value, String> {
    Ok(match j {
        Json::Null => Value::Null,
        Json::Bool(b) => Value::Bool(*b),
        Json::Number(n) => {
            if let Some(u) = n.as_u64() {
                Value::UInt(u)
            } else if let Some(i) = n.as_i64() {
                Value::Int(i)
            } else {
                Value::Float(n.as_f64().unwrap_or(f64::NAN))
            }
        }
        Json::String(s) => Value::Str(s.clone()),
        Json::Array(a) => Value::Array(a.iter().map(json_to_value).collect::<Result<_, _>>()?),
        Json::Object(o) => {
            if let (1, Some(b)) = (o.len(), o.get(BYTES_KEY)) {
                let Json::String(s) = b else {
                    return Err(format!("{BYTES_KEY} must be a base64 string"));
                };
                return B64
                    .decode(s)
                    .map(Value::Bytes)
                    .map_err(|e| format!("{BYTES_KEY}: {e}"));
            }
            Value::Map(
                o.iter()
                    .map(|(k, v)| json_to_value(v).map(|v| (k.clone(), v)))
                    .collect::<Result<_, _>>()?,
            )
        }
    })
}

/// Wire value → JSON value (inverse of [`json_to_value`]).
pub fn value_to_json(v: &Value) -> Json {
    match v {
        Value::Null => Json::Null,
        Value::Bool(b) => Json::Bool(*b),
        Value::Int(i) => json!(i),
        Value::UInt(u) => json!(u),
        Value::Float(f) => serde_json::Number::from_f64(*f)
            .map(Json::Number)
            .unwrap_or(Json::Null),
        Value::Str(s) => Json::String(s.clone()),
        Value::Bytes(b) => json!({ BYTES_KEY: B64.encode(b) }),
        Value::Array(a) => Json::Array(a.iter().map(value_to_json).collect()),
        Value::Map(m) => Json::Object(
            m.iter()
                .map(|(k, v)| (k.clone(), value_to_json(v)))
                .collect(),
        ),
    }
}

/// `~val` sample → `{v, q, t}` (`t` in microseconds since the Unix epoch).
pub fn sample_to_json(s: &Sample) -> Json {
    json!({ "v": value_to_json(&s.v), "q": s.q.name(), "t": s.t })
}

fn profile_json(p: &Profile) -> Json {
    match p {
        Profile::Name(n) => Json::String(n.clone()),
        Profile::Code(c) => json!({ "code": c }),
    }
}

fn toc_json(t: &TextOrCode) -> Json {
    match t {
        TextOrCode::Text(s) => Json::String(s.clone()),
        TextOrCode::Code(c) => json!({ "code": c }),
    }
}

fn str_map(m: &std::collections::BTreeMap<String, Value>) -> Json {
    Json::Object(
        m.iter()
            .map(|(k, v)| (k.clone(), value_to_json(v)))
            .collect(),
    )
}

fn param_json(p: &ParamMeta) -> Json {
    let mut o = Map::new();
    if let Some(t) = p.ty {
        o.insert("type".into(), t.name().into());
    }
    if let Some(u) = &p.unit {
        o.insert("unit".into(), toc_json(u));
    }
    if let Some(e) = &p.enum_values {
        o.insert("enum".into(), json!(e));
    }
    if let Some(d) = &p.default {
        o.insert("default".into(), value_to_json(d));
    }
    if let Some(r) = p.required {
        o.insert("required".into(), r.into());
    }
    Json::Object(o)
}

/// One action's metadata with readable names.
pub fn action_json(a: &ActionMeta) -> Json {
    let mut o = Map::new();
    o.insert(
        "params".into(),
        Json::Object(
            a.params
                .iter()
                .map(|(k, p)| (k.clone(), param_json(p)))
                .collect(),
        ),
    );
    if let Some(r) = &a.result {
        o.insert(
            "result".into(),
            match r {
                ActionResult::Type(t) => t.name().into(),
                ActionResult::Stream => "stream".into(),
                ActionResult::Void => "void".into(),
            },
        );
    }
    if let Some(s) = a.stream {
        o.insert("stream".into(), s.into());
    }
    if let Some(l) = a.level {
        o.insert("level".into(), l.name().into());
    }
    if let Some(t) = a.timeout_ms {
        o.insert("timeout_ms".into(), t.into());
    }
    Json::Object(o)
}

/// `~meta` with field names instead of integer keys (spec 02). Absent fields
/// are left out.
pub fn meta_to_json(m: &NodeMeta) -> Json {
    let mut o = Map::new();
    if let Some(p) = &m.is {
        o.insert("is".into(), profile_json(p));
    }
    if let Some(t) = m.ty {
        o.insert("type".into(), t.name().into());
    }
    if let Some(u) = &m.unit {
        o.insert("unit".into(), toc_json(u));
    }
    if let Some(e) = &m.enum_values {
        o.insert("enum".into(), json!(e));
    }
    if let Some(w) = m.writable {
        o.insert("writable".into(), w.name().into());
    }
    if let Some(i) = m.invokable {
        o.insert("invokable".into(), i.name().into());
    }
    if let Some(c) = &m.cfg {
        o.insert("cfg".into(), str_map(c));
    }
    if let Some(a) = &m.attr {
        o.insert("attr".into(), str_map(a));
    }
    if let Some(acts) = &m.actions {
        o.insert(
            "actions".into(),
            Json::Object(
                acts.iter()
                    .map(|(k, a)| (k.clone(), action_json(a)))
                    .collect(),
            ),
        );
    }
    if let Some(c) = &m.children {
        o.insert("children".into(), json!(c));
    }
    if let Some(r) = m.rev {
        o.insert("rev".into(), r.into());
    }
    if let Some(h) = m.has_children {
        o.insert("has_children".into(), h.into());
    }
    if let Some(d) = &m.display {
        o.insert("display".into(), d.clone().into());
    }
    if let Some(h) = m.has_override {
        o.insert("has_override".into(), h.into());
    }
    if let Some(c) = m.children_count {
        o.insert("children_count".into(), c.into());
    }
    if let Some(q) = m.q {
        o.insert("qos".into(), q.into());
    }
    if let Some(h) = m.has_nodes {
        o.insert("has_nodes".into(), h.into());
    }
    Json::Object(o)
}

/// Profile document (`pub/<name>/~meta`).
pub fn profile_to_json(name: &str, p: &ProfileDef) -> Json {
    let mut o = Map::new();
    o.insert("name".into(), name.into());
    if let Some(e) = &p.extends {
        o.insert("extends".into(), e.clone().into());
    }
    o.insert("meta".into(), meta_to_json(&p.meta));
    Json::Object(o)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::BTreeMap;

    #[test]
    fn round_trip() {
        let j = json!({
            "a": 3, "b": -3, "c": 21.5, "d": "x", "e": null, "f": [true],
            "g": { "$bytes": "AQID" }
        });
        let v = json_to_value(&j).unwrap();
        let Value::Map(m) = &v else { panic!() };
        assert_eq!(m["a"], Value::UInt(3));
        assert_eq!(m["b"], Value::Int(-3));
        assert_eq!(m["c"], Value::Float(21.5));
        assert_eq!(m["g"], Value::Bytes(vec![1, 2, 3]));
        assert_eq!(value_to_json(&v), j);
    }

    #[test]
    fn edge_cases() {
        assert!(json_to_value(&json!({ "$bytes": 1 })).is_err());
        assert!(json_to_value(&json!({ "$bytes": "!!" })).is_err());
        // a second key makes it an ordinary map
        let v = json_to_value(&json!({ "$bytes": "AQID", "x": 1 })).unwrap();
        assert!(matches!(v, Value::Map(_)));
        assert_eq!(value_to_json(&Value::Float(f64::NAN)), Json::Null);
        assert_eq!(
            value_to_json(&Value::Map(BTreeMap::new())),
            Json::Object(Map::new())
        );
    }

    #[test]
    fn meta_names() {
        let m = NodeMeta::number()
            .unit("°C")
            .writable(wyrm_core::Writable::Config);
        let j = meta_to_json(&m);
        assert_eq!(j["type"], "number");
        assert_eq!(j["unit"], "°C");
        assert_eq!(j["writable"], "config");
    }
}
