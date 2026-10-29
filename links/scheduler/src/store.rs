//! The link's store (ADR 0023 host store). Keys:
//! - `index`: CBOR array of the schedule ids (the store has no key listing);
//! - `s/<schedule>`: the definition, CBOR of the export map (`wyrm_schedule::schedule_to_value`)
//!   with its `targets` and `next_target`;
//! - `o/<schedule>/<target>`: a target's last outcome, CBOR `{value, source, outcome}`: the
//!   schedule state it was for (value and source occurrence) and `confirmed` or `override`.

use std::collections::BTreeMap;

use wyrm_core::{Status, Value};
use wyrm_link_api::{AppError, Host};
use wyrm_schedule::{schedule_from_value, schedule_to_value, Schedule};

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

fn internal(e: impl ToString) -> AppError {
    AppError::new(Status::InternalError, e.to_string())
}

/// The definition as saved and exported: the schedule with its targets.
pub fn definition(s: &Schedule, targets: &[TargetDef], next_target: u32) -> Value {
    let mut v = schedule_to_value(s);
    if let Value::Map(m) = &mut v {
        m.insert(
            "targets".to_owned(),
            Value::Array(targets.iter().map(TargetDef::to_value).collect()),
        );
        m.insert(
            "next_target".to_owned(),
            Value::UInt(u64::from(next_target)),
        );
    }
    v
}

pub fn encode(s: &Schedule, targets: &[TargetDef], next_target: u32) -> Result<Vec<u8>, AppError> {
    wyrm_core::codec::to_vec(&definition(s, targets, next_target)).map_err(internal)
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
        next_target: targets::next_target(saved, &defs),
        schedule: s,
        targets: defs,
    })
}

/// A target's last outcome.
pub struct Outcome {
    pub value: Value,
    pub source: String,
    pub outcome: String,
}

pub fn encode_outcome(o: &Outcome) -> Result<Vec<u8>, AppError> {
    let v = Value::Map(BTreeMap::from([
        ("value".to_owned(), o.value.clone()),
        ("source".to_owned(), Value::Str(o.source.clone())),
        ("outcome".to_owned(), Value::Str(o.outcome.clone())),
    ]));
    wyrm_core::codec::to_vec(&v).map_err(internal)
}

/// The record of target `t` of schedule `s`; an absent or unreadable one is none.
pub fn load_outcome(host: &dyn Host, s: &str, t: &str) -> Option<Outcome> {
    let bytes = host.store_get(&outcome_key(s, t))?;
    let Ok(Value::Map(mut m)) = wyrm_core::codec::from_slice::<Value>(&bytes) else {
        return None;
    };
    let text = |v: Option<Value>| match v {
        Some(Value::Str(s)) => Some(s),
        _ => None,
    };
    Some(Outcome {
        value: m.remove("value")?,
        source: text(m.remove("source"))?,
        outcome: text(m.remove("outcome"))?,
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

/// Deletes a schedule and writes the index without it (a smaller index always fits).
pub fn remove(host: &mut dyn Host, id: &str, ids: &[String]) -> Result<(), AppError> {
    let index = encode_index(ids)?;
    host.store_put(INDEX, &index)?;
    host.store_delete(&schedule_key(id));
    Ok(())
}
