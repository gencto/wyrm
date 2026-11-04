//! The link's store (ADR 0034 "Store", the host store of ADR 0023). Keys:
//! - `index`: CBOR array of the class ids (the store has no key listing);
//! - `c/<class>`: a class with its watches and their authors' rights;
//! - `p/<n>`: page `n` of records, ids `64n … 64n+63`, a CBOR array of record maps;
//! - `open`: the ids of the open records, a CBOR array;
//! - `j/<n>`: journal page `n`, a CBOR array of record ids: entry `seq = 256n + i` says that
//!   record `ids[i]` was made or changed;
//! - `sinks`: the sinks with their cursors (`sinks.rs`);
//! - `meta`: `first_page` (the oldest page kept), `page_hint` (the newest page made so far:
//!   the last page is found from it), `first_jpage`, `jpage_hint`.
//!
//! A record's id grows with its creation time, so a page is found by its ids, and the page
//! that holds the first record of a time range by a binary search on the pages' first records.

use wyrm_core::{Status, Value};
use wyrm_link_api::{AppError, Host};

use crate::limits::{JOURNAL_PAGE, PAGE};
use crate::model::{get_u64, ClassDef, Map, Record};

pub const INDEX: &str = "index";
pub const OPEN: &str = "open";
pub const META: &str = "meta";
pub const SINKS: &str = "sinks";

pub fn class_key(id: &str) -> String {
    format!("c/{id}")
}

pub fn page_key(n: u64) -> String {
    format!("p/{n}")
}

pub fn journal_key(n: u64) -> String {
    format!("j/{n}")
}

pub fn page_of(id: u64) -> u64 {
    id / PAGE
}

/// The journal page of entry index `i` (a number from 0: `seq - 1`).
pub fn jpage_of(i: u64) -> u64 {
    i / JOURNAL_PAGE
}

fn internal(e: impl ToString) -> AppError {
    AppError::new(Status::InternalError, e.to_string())
}

pub fn encode(v: &Value) -> Result<Vec<u8>, AppError> {
    wyrm_core::codec::to_vec(v).map_err(internal)
}

pub fn decode(bytes: &[u8]) -> Option<Value> {
    wyrm_core::codec::from_slice::<Value>(bytes).ok()
}

fn ids_of(v: Option<Value>) -> Vec<u64> {
    match v {
        Some(Value::Array(a)) => a
            .into_iter()
            .filter_map(|x| match x {
                Value::UInt(n) => Some(n),
                _ => None,
            })
            .collect(),
        _ => Vec::new(),
    }
}

fn encode_ids(ids: impl Iterator<Item = u64>) -> Result<Vec<u8>, AppError> {
    encode(&Value::Array(ids.map(Value::UInt).collect()))
}

// ---------- the index and the classes ----------

/// The ids in the index; an unreadable index is an error (logged by the caller).
pub fn load_index(host: &dyn Host) -> Result<Vec<String>, String> {
    let Some(bytes) = host.store_get(INDEX) else {
        return Ok(Vec::new());
    };
    match decode(&bytes) {
        Some(Value::Array(items)) => Ok(items
            .into_iter()
            .filter_map(|v| match v {
                Value::Str(s) => Some(s),
                _ => None,
            })
            .collect()),
        Some(_) => Err("the index is not an array".into()),
        None => Err("the index does not decode".into()),
    }
}

pub fn encode_index(ids: &[String]) -> Result<Vec<u8>, AppError> {
    encode(&Value::Array(ids.iter().cloned().map(Value::Str).collect()))
}

pub fn load_class(host: &dyn Host, id: &str) -> Result<ClassDef, String> {
    let bytes = host
        .store_get(&class_key(id))
        .ok_or_else(|| "no stored definition".to_owned())?;
    let v = decode(&bytes).ok_or_else(|| "does not decode".to_owned())?;
    let c = ClassDef::from_value(&v).map_err(|e| e.msg)?;
    if c.id != id {
        return Err(format!("stored under {id} but its id is {}", c.id));
    }
    Ok(c)
}

pub fn encode_class(c: &ClassDef) -> Result<Vec<u8>, AppError> {
    encode(&c.to_value(true))
}

/// Saves a new class's definition and the index that names it. When the index does not fit,
/// the definition is deleted again in the same event, so the store is as before.
pub fn add_class(host: &mut dyn Host, c: &ClassDef, ids: &[String]) -> Result<(), AppError> {
    let index = encode_index(ids)?;
    host.store_put(&class_key(&c.id), &encode_class(c)?)?;
    if let Err(e) = host.store_put(INDEX, &index) {
        host.store_delete(&class_key(&c.id));
        return Err(e);
    }
    Ok(())
}

pub fn replace_class(host: &mut dyn Host, c: &ClassDef) -> Result<(), AppError> {
    host.store_put(&class_key(&c.id), &encode_class(c)?)
}

/// Deletes a class and writes the index without it (a smaller index always fits).
pub fn remove_class(host: &mut dyn Host, id: &str, ids: &[String]) -> Result<(), AppError> {
    host.store_put(INDEX, &encode_index(ids)?)?;
    host.store_delete(&class_key(id));
    Ok(())
}

// ---------- meta ----------

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct Meta {
    pub first_page: u64,
    pub page_hint: u64,
    pub first_jpage: u64,
    pub jpage_hint: u64,
}

impl Meta {
    pub fn load(host: &dyn Host) -> Self {
        let Some(Value::Map(m)) = host.store_get(META).and_then(|b| decode(&b)) else {
            return Meta::default();
        };
        let n = |k: &str| get_u64(&m, k).ok().flatten().unwrap_or(0);
        Meta {
            first_page: n("first_page"),
            page_hint: n("page_hint"),
            first_jpage: n("first_jpage"),
            jpage_hint: n("jpage_hint"),
        }
    }

    pub fn save(&self, host: &mut dyn Host) -> Result<(), AppError> {
        let v = Value::Map(Map::from([
            ("first_page".to_owned(), Value::UInt(self.first_page)),
            ("page_hint".to_owned(), Value::UInt(self.page_hint)),
            ("first_jpage".to_owned(), Value::UInt(self.first_jpage)),
            ("jpage_hint".to_owned(), Value::UInt(self.jpage_hint)),
        ]));
        host.store_put(META, &encode(&v)?)
    }
}

// ---------- record pages ----------

/// The records of page `n` (empty when absent); unreadable records are dropped.
pub fn load_page(host: &dyn Host, n: u64) -> Vec<Record> {
    match host.store_get(&page_key(n)).and_then(|b| decode(&b)) {
        Some(Value::Array(a)) => a.iter().filter_map(Record::from_value).collect(),
        _ => Vec::new(),
    }
}

pub fn page_exists(host: &dyn Host, n: u64) -> bool {
    host.store_get(&page_key(n)).is_some()
}

pub fn save_page(host: &mut dyn Host, n: u64, records: &[Record]) -> Result<(), AppError> {
    let v = Value::Array(records.iter().map(|r| r.to_value(false)).collect());
    host.store_put(&page_key(n), &encode(&v)?)
}

/// Puts `r` on its page (replacing the record with its id).
pub fn save_record(host: &mut dyn Host, r: &Record) -> Result<(), AppError> {
    let n = page_of(r.id);
    let mut page = load_page(host, n);
    match page.iter().position(|x| x.id == r.id) {
        Some(i) => page[i] = r.clone(),
        None => {
            page.push(r.clone());
            page.sort_by_key(|x| x.id);
        }
    }
    save_page(host, n, &page)
}

/// Record `id` from its page.
pub fn load_record(host: &dyn Host, id: u64) -> Option<Record> {
    load_page(host, page_of(id))
        .into_iter()
        .find(|r| r.id == id)
}

/// The newest page from `hint` on: pages are made in order, so the first missing page after
/// the hint ends them. `None`: no page at all (the hint's page is missing too).
pub fn last_page(host: &dyn Host, hint: u64) -> Option<u64> {
    if !page_exists(host, hint) {
        return None;
    }
    let mut n = hint;
    while page_exists(host, n + 1) {
        n += 1;
    }
    Some(n)
}

/// The next record id: after the last record of the last page.
pub fn next_id(host: &dyn Host, hint: u64) -> u64 {
    match last_page(host, hint) {
        Some(n) => load_page(host, n)
            .iter()
            .map(|r| r.id + 1)
            .max()
            .unwrap_or(n * PAGE),
        None => 0,
    }
}

// ---------- open records ----------

pub fn load_open_ids(host: &dyn Host) -> Vec<u64> {
    ids_of(host.store_get(OPEN).and_then(|b| decode(&b)))
}

pub fn save_open_ids(host: &mut dyn Host, ids: impl Iterator<Item = u64>) -> Result<(), AppError> {
    let bytes = encode_ids(ids)?;
    host.store_put(OPEN, &bytes)
}

// ---------- the journal ----------

pub fn load_journal_page(host: &dyn Host, n: u64) -> Vec<u64> {
    ids_of(host.store_get(&journal_key(n)).and_then(|b| decode(&b)))
}

pub fn save_journal_page(host: &mut dyn Host, n: u64, ids: &[u64]) -> Result<(), AppError> {
    let bytes = encode_ids(ids.iter().copied())?;
    host.store_put(&journal_key(n), &bytes)
}

pub fn journal_page_exists(host: &dyn Host, n: u64) -> bool {
    host.store_get(&journal_key(n)).is_some()
}

/// The newest journal page from `hint` on, and its entries.
pub fn last_journal_page(host: &dyn Host, hint: u64) -> Option<(u64, Vec<u64>)> {
    if !journal_page_exists(host, hint) {
        return None;
    }
    let mut n = hint;
    while journal_page_exists(host, n + 1) {
        n += 1;
    }
    Some((n, load_journal_page(host, n)))
}
