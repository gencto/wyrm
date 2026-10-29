//! The link's store (ADR 0023 host store). Keys:
//! - `index`: CBOR array of the schedule ids (the store has no key listing);
//! - `s/<schedule>`: the definition, CBOR of the export map (`wyrm_schedule::schedule_to_value`);
//! - `o/<schedule>/<target>`: a target's last outcome (Task 4).

use wyrm_core::{Status, Value};
use wyrm_link_api::{AppError, Host};
use wyrm_schedule::{schedule_from_value, schedule_to_value, Schedule};

pub const INDEX: &str = "index";

pub fn schedule_key(id: &str) -> String {
    format!("s/{id}")
}

fn internal(e: impl ToString) -> AppError {
    AppError::new(Status::InternalError, e.to_string())
}

pub fn encode_schedule(s: &Schedule) -> Result<Vec<u8>, AppError> {
    wyrm_core::codec::to_vec(&schedule_to_value(s)).map_err(internal)
}

/// A stored definition; `Err` names what is wrong with it.
pub fn load_schedule(host: &dyn Host, id: &str) -> Result<Schedule, String> {
    let bytes = host
        .store_get(&schedule_key(id))
        .ok_or_else(|| "no stored definition".to_owned())?;
    let v = wyrm_core::codec::from_slice::<Value>(&bytes).map_err(|e| e.to_string())?;
    let (s, _targets) = schedule_from_value(&v).map_err(|e| e.to_string())?;
    if s.id != id {
        return Err(format!("stored under {id} but its id is {}", s.id));
    }
    Ok(s)
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

/// Saves a new schedule and the index that names it. When the index does not fit, the
/// definition is deleted again in the same event, so the store is as before.
pub fn add(host: &mut dyn Host, s: &Schedule, ids: &[String]) -> Result<(), AppError> {
    let def = encode_schedule(s)?;
    let index = encode_index(ids)?;
    host.store_put(&schedule_key(&s.id), &def)?;
    if let Err(e) = host.store_put(INDEX, &index) {
        host.store_delete(&schedule_key(&s.id));
        return Err(e);
    }
    Ok(())
}

/// Saves a changed definition of a schedule already in the index.
pub fn replace(host: &mut dyn Host, s: &Schedule) -> Result<(), AppError> {
    host.store_put(&schedule_key(&s.id), &encode_schedule(s)?)
}

/// Deletes a schedule and writes the index without it (a smaller index always fits).
pub fn remove(host: &mut dyn Host, id: &str, ids: &[String]) -> Result<(), AppError> {
    let index = encode_index(ids)?;
    host.store_put(INDEX, &index)?;
    host.store_delete(&schedule_key(id));
    Ok(())
}
