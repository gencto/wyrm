//! The link's store (ADR 0023 host store). Keys:
//! - `index`: CBOR array of the schedule ids (the store has no key listing);
//! - `s/<schedule>`: the definition, CBOR of the export map (`wyrm_schedule::schedule_to_value`)
//!   with its `targets` and `next_target`;
//! - `o/<schedule>/<target>`: a target's last outcome, CBOR `{value, source, outcome,
//!   valid_until}`: the schedule state it was for (value and source occurrence), `confirmed` or
//!   `override`, and the instant of the next transition after that state (R19; absent in an
//!   older store: the record is stale);
//! - `h/<schedule>`: the moment the schedule holds, CBOR `{event, at, value}` (R17): put when a
//!   moment fires, deleted when the next transition replaces it.
//!
//! Keys at most: `1 + 2 × schedules + targets` (at most 8 031 within the node budget), below
//! the host's 10 000.

use std::collections::BTreeMap;

use wyrm_core::{Status, Value};
use wyrm_link_api::{AppError, Host};
use wyrm_schedule::{schedule_from_value, schedule_to_value, Micros, Schedule, Source, State};

use crate::targets::{self, TargetDef};

pub const INDEX: &str = "index";
pub const CONFIRMED: &str = "confirmed";
pub const OVERRIDE: &str = "override";

pub fn schedule_key(id: &str) -> String {
    format!("s/{id}")
}

pub fn outcome_key(schedule: &str, target: &str) -> String {
    format!("o/{schedule}/{target}")
}

pub fn held_key(schedule: &str) -> String {
    format!("h/{schedule}")
}

/// An instant: CBOR gives back a positive integer as unsigned.
fn instant(v: Option<Value>) -> Option<Micros> {
    match v? {
        Value::Int(n) => Some(n),
        Value::UInt(n) => Micros::try_from(n).ok(),
        _ => None,
    }
}

fn text(v: Option<Value>) -> Option<String> {
    match v? {
        Value::Str(s) => Some(s),
        _ => None,
    }
}

fn internal(e: impl ToString) -> AppError {
    AppError::new(Status::InternalError, e.to_string())
}

/// The definition as saved (`stored`: with each target's author rights) and exported: the
/// schedule with its targets.
pub fn definition(s: &Schedule, targets: &[TargetDef], next_target: u32, stored: bool) -> Value {
    let mut v = schedule_to_value(s);
    if let Value::Map(m) = &mut v {
        m.insert(
            "targets".to_owned(),
            Value::Array(
                targets
                    .iter()
                    .map(|t| if stored { t.to_stored() } else { t.to_value() })
                    .collect(),
            ),
        );
        m.insert(
            "next_target".to_owned(),
            Value::UInt(u64::from(next_target)),
        );
    }
    v
}

pub fn encode(s: &Schedule, targets: &[TargetDef], next_target: u32) -> Result<Vec<u8>, AppError> {
    wyrm_core::codec::to_vec(&definition(s, targets, next_target, true)).map_err(internal)
}

/// A stored definition.
pub struct Loaded {
    pub schedule: Schedule,
    pub targets: Vec<TargetDef>,
    pub next_target: u32,
}

/// A stored definition; `Err` names what is wrong with it.
pub fn load_schedule(host: &dyn Host, id: &str) -> Result<Loaded, String> {
    let bytes = host
        .store_get(&schedule_key(id))
        .ok_or_else(|| "no stored definition".to_owned())?;
    let v = wyrm_core::codec::from_slice::<Value>(&bytes).map_err(|e| e.to_string())?;
    let (s, t) = schedule_from_value(&v).map_err(|e| e.to_string())?;
    if s.id != id {
        return Err(format!("stored under {id} but its id is {}", s.id));
    }
    let defs = targets::defs_from_value(&t, None).map_err(|e| e.msg)?;
    let saved = match &v {
        Value::Map(m) => m.get("next_target"),
        _ => None,
    };
    Ok(Loaded {
        next_target: targets::next_target(saved, &defs).map_err(|e| e.msg)?,
        schedule: s,
        targets: defs,
    })
}

/// A target's last outcome.
#[derive(Debug, Clone, PartialEq)]
pub struct Outcome {
    pub value: Value,
    pub source: String,
    pub outcome: String,
    /// The next transition after the state (R19); `None` (an older store): stale.
    pub valid_until: Option<Micros>,
}

impl Outcome {
    /// For the state now at `now`: the same state, and no transition since.
    pub fn holds(&self, value: &Value, source: &str, now: Micros) -> bool {
        &self.value == value && self.source == source && self.valid_until.is_some_and(|u| now < u)
    }
}

pub fn encode_outcome(o: &Outcome) -> Result<Vec<u8>, AppError> {
    let mut m = BTreeMap::from([
        ("value".to_owned(), o.value.clone()),
        ("source".to_owned(), Value::Str(o.source.clone())),
        ("outcome".to_owned(), Value::Str(o.outcome.clone())),
    ]);
    if let Some(u) = o.valid_until {
        m.insert("valid_until".to_owned(), Value::from(u));
    }
    wyrm_core::codec::to_vec(&Value::Map(m)).map_err(internal)
}

/// The record of target `t` of schedule `s`; an absent or unreadable one is none.
pub fn load_outcome(host: &dyn Host, s: &str, t: &str) -> Option<Outcome> {
    let bytes = host.store_get(&outcome_key(s, t))?;
    let Ok(Value::Map(mut m)) = wyrm_core::codec::from_slice::<Value>(&bytes) else {
        return None;
    };
    Some(Outcome {
        value: m.remove("value")?,
        source: text(m.remove("source"))?,
        outcome: text(m.remove("outcome"))?,
        valid_until: instant(m.remove("valid_until")),
    })
}

/// The held moment of a state (none for a window state or the default).
pub fn encode_held(s: &State) -> Option<Result<Vec<u8>, AppError>> {
    let Source::Moment { id, at } = &s.source else {
        return None;
    };
    let v = Value::Map(BTreeMap::from([
        ("event".to_owned(), Value::Str(id.clone())),
        ("at".to_owned(), Value::from(*at)),
        ("value".to_owned(), s.value.clone()),
    ]));
    Some(wyrm_core::codec::to_vec(&v).map_err(internal))
}

/// The moment schedule `s` held when it was saved; an absent or unreadable one is none.
pub fn load_held(host: &dyn Host, s: &str) -> Option<State> {
    let bytes = host.store_get(&held_key(s))?;
    let Ok(Value::Map(mut m)) = wyrm_core::codec::from_slice::<Value>(&bytes) else {
        return None;
    };
    Some(State {
        source: Source::Moment {
            id: text(m.remove("event"))?,
            at: instant(m.remove("at"))?,
        },
        value: m.remove("value")?,
    })
}

/// The ids in the index; an unreadable index is empty (logged by the caller).
pub fn load_index(host: &dyn Host) -> Result<Vec<String>, String> {
    let Some(bytes) = host.store_get(INDEX) else {
        return Ok(Vec::new());
    };
    match wyrm_core::codec::from_slice::<Value>(&bytes) {
        Ok(Value::Array(items)) => Ok(items
            .into_iter()
            .filter_map(|v| match v {
                Value::Str(s) => Some(s),
                _ => None,
            })
            .collect()),
        Ok(_) => Err("the index is not an array".into()),
        Err(e) => Err(e.to_string()),
    }
}

pub fn encode_index(ids: &[String]) -> Result<Vec<u8>, AppError> {
    let v = Value::Array(ids.iter().cloned().map(Value::Str).collect());
    wyrm_core::codec::to_vec(&v).map_err(internal)
}

/// Saves a new schedule's definition `def` and the index that names it. When the index does
/// not fit, the definition is deleted again in the same event, so the store is as before.
pub fn add(host: &mut dyn Host, id: &str, def: &[u8], ids: &[String]) -> Result<(), AppError> {
    let index = encode_index(ids)?;
    host.store_put(&schedule_key(id), def)?;
    if let Err(e) = host.store_put(INDEX, &index) {
        host.store_delete(&schedule_key(id));
        return Err(e);
    }
    Ok(())
}

/// Saves a changed definition of a schedule already in the index.
pub fn replace(host: &mut dyn Host, id: &str, def: &[u8]) -> Result<(), AppError> {
    host.store_put(&schedule_key(id), def)
}

/// Deletes a schedule (and its held moment) and writes the index without it (a smaller index
/// always fits).
pub fn remove(host: &mut dyn Host, id: &str, ids: &[String]) -> Result<(), AppError> {
    let index = encode_index(ids)?;
    host.store_put(INDEX, &index)?;
    host.store_delete(&schedule_key(id));
    host.store_delete(&held_key(id));
    Ok(())
}
