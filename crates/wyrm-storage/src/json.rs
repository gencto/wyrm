//! Export and import of a storage subtree as JSON, the shape a DSA broker
//! uses for `/data` (ADR 0017): `$type` is a value node's type, `@editor`
//! its editor, `?value` its value, any other key whose value is an object
//! is a child. Binary values are `{"$hex": "…"}`; other `$`/`@` keys
//! (a DSA export's `$is`, `$name`, …) are ignored on import.

use crate::store::Rec;
use crate::{check_value, Limits, EDITORS, TYPES};
use serde_json::{Map, Number, Value as Json};
use std::collections::BTreeMap;
use wyrm_core::keyspace::validate_segment;
use wyrm_core::Value;
use wyrm_link_sdk::{LinkError, Result};

const HEX: &str = "$hex";

/// A WYRM value as JSON. Non-finite floats become `null` (JSON has none).
pub fn to_json(v: &Value) -> Json {
    match v {
        Value::Null => Json::Null,
        Value::Bool(b) => Json::Bool(*b),
        Value::Int(i) => Json::Number((*i).into()),
        Value::UInt(u) => Json::Number((*u).into()),
        Value::Float(f) => Number::from_f64(*f).map_or(Json::Null, Json::Number),
        Value::Str(s) => Json::String(s.clone()),
        Value::Bytes(b) => {
            let mut m = Map::new();
            m.insert(HEX.into(), Json::String(hex::encode(b)));
            Json::Object(m)
        }
        Value::Array(a) => Json::Array(a.iter().map(to_json).collect()),
        Value::Map(m) => Json::Object(m.iter().map(|(k, v)| (k.clone(), to_json(v))).collect()),
    }
}

/// JSON as a WYRM value; `{"$hex": "…"}` alone is binary.
pub fn from_json(j: &Json) -> Result<Value> {
    Ok(match j {
        Json::Null => Value::Null,
        Json::Bool(b) => Value::Bool(*b),
        Json::Number(n) => match (n.as_u64(), n.as_i64(), n.as_f64()) {
            (Some(u), _, _) => Value::UInt(u),
            (_, Some(i), _) => Value::Int(i),
            (_, _, Some(f)) => Value::Float(f),
            _ => return Err(LinkError::invalid_parameter("number out of range")),
        },
        Json::String(s) => Value::Str(s.clone()),
        Json::Array(a) => Value::Array(a.iter().map(from_json).collect::<Result<_>>()?),
        Json::Object(m) => match (m.len(), m.get(HEX)) {
            (1, Some(Json::String(h))) => Value::Bytes(
                hex::decode(h).map_err(|_| LinkError::invalid_parameter("$hex: not hex"))?,
            ),
            _ => Value::Map(
                m.iter()
                    .map(|(k, v)| Ok((k.clone(), from_json(v)?)))
                    .collect::<Result<_>>()?,
            ),
        },
    })
}

/// The subtree at `path` (`nodes` holds it, `path` itself included) as
/// JSON text: the node's own fields and its children, nested.
pub fn export(path: &str, nodes: &[(String, Rec)]) -> String {
    fn node(rec: Option<&Rec>) -> Map<String, Json> {
        let mut m = Map::new();
        if let Some(r) = rec {
            if let Some(t) = r.ty {
                m.insert("$type".into(), Json::String(t.name().into()));
            }
            if let Some(e) = &r.editor {
                m.insert("@editor".into(), Json::String(e.clone()));
            }
            if let Some(v) = &r.value {
                m.insert("?value".into(), to_json(v));
            }
        }
        m
    }
    // Paths sort parents first, so every parent object exists when a
    // child is placed; a stack keeps the open objects down to the child.
    let base = |p: &str| -> Vec<String> {
        let rel = if path.is_empty() {
            p
        } else {
            p.strip_prefix(path).unwrap_or(p).trim_start_matches('/')
        };
        if rel.is_empty() {
            Vec::new()
        } else {
            rel.split('/').map(str::to_owned).collect()
        }
    };
    let own = nodes.iter().find(|(p, _)| p == path).map(|(_, r)| r);
    let mut root = node(own);
    for (p, r) in nodes {
        let segs = base(p);
        let Some((last, parents)) = segs.split_last() else {
            continue;
        };
        let mut at = &mut root;
        for s in parents {
            at = match at
                .entry(s.clone())
                .or_insert_with(|| Json::Object(Map::new()))
            {
                Json::Object(m) => m,
                _ => unreachable!("children are objects"),
            };
        }
        at.insert(last.clone(), Json::Object(node(Some(r))));
    }
    Json::Object(root).to_string()
}

/// Nodes of an import into the folder `path`, parents first, checked
/// against the limits: names, types, editors, values, depth.
pub fn import(path: &str, text: &str, limits: &Limits) -> Result<Vec<(String, Rec)>> {
    if text.len() > limits.import_bytes {
        return Err(LinkError::new(
            wyrm_core::Status::OutOfRange,
            format!("import: more than {} bytes", limits.import_bytes),
        ));
    }
    let j: Json = serde_json::from_str(text)
        .map_err(|e| LinkError::invalid_parameter(format!("import: {e}")))?;
    let Json::Object(top) = j else {
        return Err(LinkError::invalid_parameter("import: not a JSON object"));
    };
    let mut out = Vec::new();
    children(path, &top, limits, &mut out)?;
    Ok(out)
}

fn children(
    parent: &str,
    m: &Map<String, Json>,
    limits: &Limits,
    out: &mut Vec<(String, Rec)>,
) -> Result<()> {
    let sorted: BTreeMap<&String, &Json> = m.iter().collect();
    for (name, j) in sorted {
        if name.starts_with(['$', '@', '?']) {
            continue;
        }
        let Json::Object(child) = j else {
            continue;
        };
        validate_segment(name).map_err(|e| LinkError::invalid_parameter(e.to_string()))?;
        let path = if parent.is_empty() {
            name.clone()
        } else {
            format!("{parent}/{name}")
        };
        limits.check_depth(&path)?;
        if out.len() >= limits.nodes {
            return Err(limits.too_many());
        }
        let rec = record(&path, child, limits)?;
        let folder = rec.is_folder();
        out.push((path.clone(), rec));
        if folder {
            children(&path, child, limits, out)?;
        } else if child
            .iter()
            .any(|(k, v)| !k.starts_with(['$', '@', '?']) && v.is_object())
        {
            return Err(LinkError::invalid_parameter(format!(
                "import: value {path} has children"
            )));
        }
    }
    Ok(())
}

fn record(path: &str, m: &Map<String, Json>, limits: &Limits) -> Result<Rec> {
    let bad = |what: &str| LinkError::invalid_parameter(format!("import: {path}: {what}"));
    let ty = match m.get("$type") {
        None => None,
        Some(Json::String(t)) => Some(
            TYPES
                .iter()
                .copied()
                .find(|c| c.name() == t)
                .ok_or_else(|| bad("unknown $type"))?,
        ),
        Some(_) => return Err(bad("$type is not text")),
    };
    let editor = match m.get("@editor") {
        None => None,
        Some(Json::String(e)) if EDITORS.contains(&e.as_str()) => {
            (e != EDITORS[0]).then(|| e.clone())
        }
        Some(_) => return Err(bad("unknown @editor")),
    };
    let value = match m.get("?value") {
        None | Some(Json::Null) => None,
        Some(v) => Some(from_json(v)?),
    };
    let Some(ty) = ty else {
        // A DSA export gives every node a value slot; a folder has none.
        if value.is_some() || editor.is_some() {
            return Err(bad("a value needs $type"));
        }
        return Ok(Rec::folder());
    };
    if let Some(v) = &value {
        check_value(ty, v, limits).map_err(|e| bad(&e.message))?;
    }
    Ok(Rec {
        ty: Some(ty),
        editor,
        value,
        t: None,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use wyrm_core::TypeCode;

    #[test]
    fn values_round_trip() {
        let mut m = BTreeMap::new();
        m.insert("b".to_owned(), Value::Bytes(vec![1, 2, 255]));
        m.insert("n".to_owned(), Value::Int(-3));
        let v = Value::Array(vec![
            Value::Map(m),
            Value::Float(1.5),
            Value::UInt(7),
            Value::Str("x".into()),
            Value::Bool(true),
            Value::Null,
        ]);
        assert_eq!(from_json(&to_json(&v)).unwrap(), v);
        assert_eq!(to_json(&Value::Float(f64::NAN)), Json::Null);
    }

    #[test]
    fn export_then_import() {
        let num = Rec {
            ty: Some(TypeCode::Number),
            editor: None,
            value: Some(Value::Float(21.5)),
            t: Some(5),
        };
        let note = Rec {
            ty: Some(TypeCode::String),
            editor: Some("textarea".into()),
            value: None,
            t: None,
        };
        let nodes = vec![
            ("a".to_owned(), Rec::folder()),
            ("a/b".to_owned(), Rec::folder()),
            ("a/b/t".to_owned(), num.clone()),
            ("a/note".to_owned(), note.clone()),
        ];
        let text = export("a", &nodes);
        let j: Json = serde_json::from_str(&text).unwrap();
        assert_eq!(j["b"]["t"]["$type"], "number");
        assert_eq!(j["b"]["t"]["?value"], 21.5);
        assert_eq!(j["note"]["@editor"], "textarea");

        let got = import("c", &text, &Limits::default()).unwrap();
        let want = vec![
            ("c/b".to_owned(), Rec::folder()),
            ("c/b/t".to_owned(), Rec { t: None, ..num }),
            ("c/note".to_owned(), note),
        ];
        assert_eq!(got, want);
    }

    #[test]
    fn import_refuses_bad_input() {
        let l = Limits::default();
        assert!(import("", "[1]", &l).is_err());
        assert!(import("", r#"{"a b": {}}"#, &l).is_err());
        assert!(import("", r#"{"x": {"$type": "weird"}}"#, &l).is_err());
        assert!(import("", r#"{"x": {"$type": "number", "?value": "no"}}"#, &l).is_err());
        assert!(import("", r#"{"x": {"?value": 1}}"#, &l).is_err());
        assert!(import("", r#"{"x": {"$type": "bool", "y": {}}}"#, &l).is_err());
        // DSA leftovers are ignored.
        let ok = import(
            "",
            r#"{"$is": "node", "x": {"$is": "broker/dataNode"}}"#,
            &l,
        )
        .unwrap();
        assert_eq!(ok, vec![("x".to_owned(), Rec::folder())]);
        let deep = (0..=l.depth).fold(String::from("{}"), |acc, _| format!(r#"{{"d": {acc}}}"#));
        assert!(import("", &deep, &l).is_err());
        let small = Limits {
            nodes: 1,
            ..Limits::default()
        };
        assert!(import("", r#"{"a": {}, "b": {}}"#, &small).is_err());
    }
}
