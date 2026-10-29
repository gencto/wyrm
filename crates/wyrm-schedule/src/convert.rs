//! `Value` <-> model (own export map) and `Value` <-> JSON.

use std::collections::BTreeMap;

use wyrm_core::Value;

use crate::model::{format_local, parse_local, validate, Event, Invalid, Rule, Schedule, FORMAT};

fn text(s: &str) -> Value {
    Value::Str(s.to_string())
}

fn map<const N: usize>(entries: [(&str, Value); N]) -> Value {
    Value::Map(
        entries
            .into_iter()
            .map(|(k, v)| (k.to_string(), v))
            .collect(),
    )
}

/// The link's own export map (`format: "wyrm-schedule/1"`). `targets` is an empty array:
/// the link models targets and puts them in.
pub fn schedule_to_value(s: &Schedule) -> Value {
    let events = s
        .events
        .iter()
        .map(|e| {
            let mut m = BTreeMap::new();
            m.insert("id".into(), text(&e.id));
            m.insert("display".into(), text(&e.display));
            m.insert("value".into(), e.value.clone());
            m.insert("priority".into(), Value::UInt(u64::from(e.priority)));
            m.insert("special".into(), Value::Bool(e.special));
            m.insert("start".into(), Value::Str(format_local(e.start)));
            m.insert("end".into(), Value::Str(format_local(e.end)));
            if let Some(r) = &e.recurrence {
                m.insert("recurrence".into(), Value::Str(r.to_string()));
            }
            Value::Map(m)
        })
        .collect();
    map([
        ("format", text(FORMAT)),
        ("id", text(&s.id)),
        ("display", text(&s.display)),
        ("tz", text(&s.tz)),
        ("default", s.default.clone()),
        ("enabled", Value::Bool(s.enabled)),
        ("next_event", Value::UInt(u64::from(s.next_event))),
        ("events", Value::Array(events)),
        ("targets", Value::Array(Vec::new())),
    ])
}

fn get<'a>(m: &'a BTreeMap<String, Value>, field: &str, key: &str) -> Result<&'a Value, Invalid> {
    m.get(key)
        .ok_or_else(|| Invalid::new(field.to_string(), "required"))
}

fn get_str<'a>(m: &'a BTreeMap<String, Value>, field: &str, key: &str) -> Result<&'a str, Invalid> {
    match get(m, field, key)? {
        Value::Str(s) => Ok(s),
        _ => Err(Invalid::new(field.to_string(), "must be text")),
    }
}

fn as_u32(v: &Value) -> Option<u32> {
    match v {
        Value::UInt(n) => u32::try_from(*n).ok(),
        Value::Int(n) => u32::try_from(*n).ok(),
        _ => None,
    }
}

fn get_bool(
    m: &BTreeMap<String, Value>,
    field: &str,
    key: &str,
    default: bool,
) -> Result<bool, Invalid> {
    match m.get(key) {
        None => Ok(default),
        Some(Value::Bool(b)) => Ok(*b),
        Some(_) => Err(Invalid::new(field.to_string(), "must be true or false")),
    }
}

/// Read an export map. Returns the schedule (validated) and its `targets` array
/// (`Value::Null` when absent; the link models targets).
pub fn schedule_from_value(v: &Value) -> Result<(Schedule, Value), Invalid> {
    let Value::Map(m) = v else {
        return Err(Invalid::new("schedule", "must be a map"));
    };
    let format = get_str(m, "format", "format")?;
    if format != FORMAT {
        return Err(Invalid::new(
            "format",
            format!("unsupported {format:?}, expected {FORMAT:?}"),
        ));
    }
    let id = get_str(m, "id", "id")?.to_string();
    let tz = get_str(m, "tz", "tz")?.to_string();
    let display = match m.get("display") {
        None => id.clone(),
        Some(Value::Str(s)) => s.clone(),
        Some(_) => return Err(Invalid::new("display", "must be text")),
    };
    let mut events = Vec::new();
    match m.get("events") {
        None => {}
        Some(Value::Array(items)) => {
            for (i, item) in items.iter().enumerate() {
                events.push(event_from_value(i, item)?);
            }
        }
        Some(_) => return Err(Invalid::new("events", "must be an array")),
    }
    let next_event = match m.get("next_event") {
        Some(n) => as_u32(n).ok_or_else(|| Invalid::new("next_event", "must be a whole number"))?,
        None => events
            .iter()
            .filter_map(|e| e.id.strip_prefix('e').and_then(|n| n.parse::<u32>().ok()))
            .max()
            .map_or(1, |n| n.saturating_add(1)),
    };
    let s = Schedule {
        id,
        display,
        tz,
        default: m.get("default").cloned().unwrap_or(Value::Null),
        enabled: get_bool(m, "enabled", "enabled", true)?,
        events,
        next_event,
    };
    validate(&s)?;
    let targets = match m.get("targets") {
        None => Value::Null,
        Some(t @ Value::Array(_)) => t.clone(),
        Some(_) => return Err(Invalid::new("targets", "must be an array")),
    };
    Ok((s, targets))
}

fn event_from_value(i: usize, v: &Value) -> Result<Event, Invalid> {
    let f = |name: &str| format!("events[{i}].{name}");
    let Value::Map(m) = v else {
        return Err(Invalid::new(format!("events[{i}]"), "must be a map"));
    };
    let priority = match m.get("priority") {
        None => 0,
        Some(p) => as_u32(p)
            .and_then(|n| u8::try_from(n).ok())
            .ok_or_else(|| Invalid::new(f("priority"), "must be 0 to 9"))?,
    };
    let recurrence = match m.get("recurrence") {
        None | Some(Value::Null) => None,
        Some(Value::Str(r)) => Some(r.parse::<Rule>().map_err(|e| e.within(&f("recurrence")))?),
        Some(_) => return Err(Invalid::new(f("recurrence"), "must be RRULE text")),
    };
    Ok(Event {
        id: get_str(m, &f("id"), "id")?.to_string(),
        display: match m.get("display") {
            None => String::new(),
            Some(Value::Str(s)) => s.clone(),
            Some(_) => return Err(Invalid::new(f("display"), "must be text")),
        },
        value: m.get("value").cloned().unwrap_or(Value::Null),
        priority,
        special: get_bool(m, &f("special"), "special", false)?,
        start: parse_local(&f("start"), get_str(m, &f("start"), "start")?)?,
        end: parse_local(&f("end"), get_str(m, &f("end"), "end")?)?,
        recurrence,
    })
}

/// `Value` to JSON. Bytes become an array of numbers; a NaN or infinite float becomes null.
pub fn value_to_json(v: &Value) -> serde_json::Value {
    use serde_json::Value as J;
    match v {
        Value::Null => J::Null,
        Value::Bool(b) => J::Bool(*b),
        Value::Int(n) => J::from(*n),
        Value::UInt(n) => J::from(*n),
        Value::Float(f) => serde_json::Number::from_f64(*f).map_or(J::Null, J::Number),
        Value::Str(s) => J::String(s.clone()),
        Value::Bytes(b) => J::Array(b.iter().map(|x| J::from(*x)).collect()),
        Value::Array(a) => J::Array(a.iter().map(value_to_json).collect()),
        Value::Map(m) => J::Object(
            m.iter()
                .map(|(k, v)| (k.clone(), value_to_json(v)))
                .collect(),
        ),
    }
}

/// JSON to `Value`. Whole non-negative numbers are `UInt`, negative ones `Int`, the rest `Float`.
pub fn value_from_json(j: &serde_json::Value) -> Value {
    use serde_json::Value as J;
    match j {
        J::Null => Value::Null,
        J::Bool(b) => Value::Bool(*b),
        J::Number(n) => {
            if let Some(u) = n.as_u64() {
                Value::UInt(u)
            } else if let Some(i) = n.as_i64() {
                Value::Int(i)
            } else {
                Value::Float(n.as_f64().unwrap_or(f64::NAN))
            }
        }
        J::String(s) => Value::Str(s.clone()),
        J::Array(a) => Value::Array(a.iter().map(value_from_json).collect()),
        J::Object(o) => Value::Map(
            o.iter()
                .map(|(k, v)| (k.clone(), value_from_json(v)))
                .collect(),
        ),
    }
}
