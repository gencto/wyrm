//! Sinks (ADR 0034 "Sinks"): links that take the records in batches through `next {after,
//! max}`, as the historian's sinks (ADR 0026). The definitions and their cursors are one store
//! key, `sinks`; the counters are kept since the link started.

use wyrm_core::Value;
use wyrm_link_api::{AppError, Host};

use crate::model::{get_str, get_u64, invalid, Map};
use crate::store::{self, SINKS};
use crate::Micros;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SinkDef {
    pub name: String,
    /// The link that reads it: `next` is for the subject `link:<link>` only.
    pub link: String,
    /// The classes it takes; empty: all.
    pub classes: Vec<String>,
    /// The last journal entry its link confirmed.
    pub cursor: u64,
}

/// A sink with its counters.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Sink {
    pub def: SinkDef,
    pub rows_sent: u64,
    pub dropped_unsent: u64,
    pub last_request: Option<Micros>,
}

impl Sink {
    pub fn new(def: SinkDef) -> Self {
        Sink {
            def,
            rows_sent: 0,
            dropped_unsent: 0,
            last_request: None,
        }
    }

    pub fn takes(&self, class: &str) -> bool {
        self.def.classes.is_empty() || self.def.classes.iter().any(|c| c == class)
    }
}

/// A sink name and a link id: key segments.
pub fn valid_name(field: &str, s: &str) -> Result<(), AppError> {
    wyrm_core::keyspace::validate_segment(s).map_err(|e| invalid(field, e))?;
    if s.starts_with('.') || s.starts_with('~') {
        return Err(invalid(field, format!("{s:?} is not a name")));
    }
    Ok(())
}

/// `classes` from an action: a comma separated text or an array; `None` when absent.
pub fn classes_arg(m: &Map, k: &str) -> Result<Option<Vec<String>>, AppError> {
    let list = match m.get(k) {
        None | Some(Value::Null) => return Ok(None),
        Some(Value::Str(s)) => s
            .split(',')
            .map(str::trim)
            .filter(|x| !x.is_empty())
            .map(str::to_owned)
            .collect::<Vec<_>>(),
        Some(Value::Array(a)) => a
            .iter()
            .map(|v| match v {
                Value::Str(s) => Ok(s.trim().to_owned()),
                _ => Err(invalid(k, "class ids")),
            })
            .collect::<Result<Vec<_>, _>>()?,
        Some(_) => return Err(invalid(k, "class ids, comma separated")),
    };
    for c in &list {
        crate::model::valid_id(c).map_err(|e| invalid(k, e.msg))?;
    }
    Ok(Some(list))
}

fn sink_to_value(s: &SinkDef) -> Value {
    Value::Map(Map::from([
        ("name".to_owned(), Value::Str(s.name.clone())),
        ("link".to_owned(), Value::Str(s.link.clone())),
        (
            "classes".to_owned(),
            Value::Array(s.classes.iter().cloned().map(Value::Str).collect()),
        ),
        ("cursor".to_owned(), Value::UInt(s.cursor)),
    ]))
}

fn sink_from_value(v: &Value) -> Option<SinkDef> {
    let Value::Map(m) = v else { return None };
    let classes = match m.get("classes") {
        Some(Value::Array(a)) => a
            .iter()
            .filter_map(|c| match c {
                Value::Str(s) => Some(s.clone()),
                _ => None,
            })
            .collect(),
        _ => Vec::new(),
    };
    Some(SinkDef {
        name: get_str(m, "name").ok()??,
        link: get_str(m, "link").ok()??,
        classes,
        cursor: get_u64(m, "cursor").ok()??,
    })
}

/// The stored sinks, in name order.
pub fn load(host: &dyn Host) -> Vec<SinkDef> {
    match host.store_get(SINKS).and_then(|b| store::decode(&b)) {
        Some(Value::Array(a)) => a.iter().filter_map(sink_from_value).collect(),
        _ => Vec::new(),
    }
}

pub fn save<'a>(
    host: &mut dyn Host,
    sinks: impl Iterator<Item = &'a SinkDef>,
) -> Result<(), AppError> {
    let v = Value::Array(sinks.map(sink_to_value).collect());
    host.store_put(SINKS, &store::encode(&v)?)
}
