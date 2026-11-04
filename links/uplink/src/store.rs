//! The host store (ADR 0023) of the uplink: `index` (CBOR array of the upstream names; the store
//! has no key listing), `u/<name>` (the definition, CBOR of a map), `secret/<name>` (the one
//! secret of an upstream, bytes), `bdseq/<name>` (the Sparkplug birth/death sequence).

use wyrm_core::{codec, Status, Value};
use wyrm_link_api::{AppError, Host};

use crate::platform::Def;

pub const INDEX: &str = "index";

fn store_err(e: impl std::fmt::Display) -> AppError {
    AppError::new(Status::InternalError, e.to_string())
}

fn def_key(name: &str) -> String {
    format!("u/{name}")
}

pub fn secret_key(name: &str) -> String {
    format!("secret/{name}")
}

fn bdseq_key(name: &str) -> String {
    format!("bdseq/{name}")
}

pub fn load_index(host: &dyn Host) -> Result<Vec<String>, String> {
    let Some(b) = host.store_get(INDEX) else {
        return Ok(Vec::new());
    };
    match codec::from_slice::<Value>(&b).map_err(|e| e.to_string())? {
        Value::Array(a) => Ok(a
            .into_iter()
            .filter_map(|v| match v {
                Value::Str(s) => Some(s),
                _ => None,
            })
            .collect()),
        _ => Err("index: not an array".into()),
    }
}

pub fn put_index(host: &mut dyn Host, names: &[String]) -> Result<(), AppError> {
    let v = Value::Array(names.iter().cloned().map(Value::Str).collect());
    host.store_put(INDEX, &codec::to_vec(&v).map_err(store_err)?)
}

pub fn load_def(host: &dyn Host, name: &str, site: Option<&str>) -> Result<Def, String> {
    let b = host.store_get(&def_key(name)).ok_or("not in the store")?;
    Def::from_value(
        &codec::from_slice::<Value>(&b).map_err(|e| e.to_string())?,
        site,
    )
}

pub fn put_def(host: &mut dyn Host, def: &Def) -> Result<(), AppError> {
    host.store_put(
        &def_key(&def.name),
        &codec::to_vec(&def.to_value()).map_err(store_err)?,
    )
}

pub fn delete(host: &mut dyn Host, name: &str) {
    host.store_delete(&def_key(name));
    host.store_delete(&secret_key(name));
    host.store_delete(&bdseq_key(name));
}

pub fn secret(host: &dyn Host, name: &str) -> Option<String> {
    host.store_get(&secret_key(name))
        .and_then(|b| String::from_utf8(b).ok())
}

/// The next `bdSeq` of an upstream (0 the first time), kept so a new session's NBIRTH never
/// repeats the last one's.
pub fn next_bdseq(host: &mut dyn Host, name: &str) -> u64 {
    let k = bdseq_key(name);
    let last = host
        .store_get(&k)
        .and_then(|b| b.try_into().ok().map(u64::from_le_bytes));
    let next = last.map_or(0, |l| (l + 1) % 256);
    let _ = host.store_put(&k, &next.to_le_bytes());
    next
}
