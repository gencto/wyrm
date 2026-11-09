//! The host store (ADR 0023) of the messenger. The store has no key listing, so each collection
//! keeps an index (a CBOR array of names):
//!
//! ```text
//! bots                      index of bots
//! b/<bot>                   bot definition (CBOR map)
//! secret/<bot>              the bot token (bytes; never shown, never logged)
//! offset/<bot>              the next Telegram update id (u64 LE)
//! ri/<bot>, r/<bot>/<n>     recipients
//! ti/<bot>, t/<bot>/<n>     templates; rights/t/<bot>/<n> their author's rights (ADR 0029)
//! ui/<bot>, u/<bot>/<n>     chat users; rights/u/<bot>/<n> the rights of who invited or edited them
//! ```

use wyrm_core::{codec, Status, Value};
use wyrm_link_api::{AppError, Host, Rights};

pub const BOTS: &str = "bots";

fn store_err(e: impl std::fmt::Display) -> AppError {
    AppError::new(Status::InternalError, e.to_string())
}

pub fn get(host: &dyn Host, key: &str) -> Option<Value> {
    codec::from_slice::<Value>(&host.store_get(key)?).ok()
}

pub fn put(host: &mut dyn Host, key: &str, v: &Value) -> Result<(), AppError> {
    host.store_put(key, &codec::to_vec(v).map_err(store_err)?)
}

pub fn index(host: &dyn Host, key: &str) -> Vec<String> {
    match get(host, key) {
        Some(Value::Array(a)) => a
            .into_iter()
            .filter_map(|v| match v {
                Value::Str(s) => Some(s),
                _ => None,
            })
            .collect(),
        _ => Vec::new(),
    }
}

pub fn put_index<'a>(
    host: &mut dyn Host,
    key: &str,
    names: impl Iterator<Item = &'a String>,
) -> Result<(), AppError> {
    put(
        host,
        key,
        &Value::Array(names.cloned().map(Value::Str).collect()),
    )
}

pub fn bot(name: &str) -> String {
    format!("b/{name}")
}

pub fn secret_key(bot: &str) -> String {
    format!("secret/{bot}")
}

pub fn offset_key(bot: &str) -> String {
    format!("offset/{bot}")
}

/// `(index, item)` keys of a collection: `r`, `t` or `u`.
pub fn coll(c: char, bot: &str) -> String {
    format!("{c}i/{bot}")
}

pub fn item(c: char, bot: &str, name: &str) -> String {
    format!("{c}/{bot}/{name}")
}

pub fn rights_key(c: char, bot: &str, name: &str) -> String {
    format!("rights/{c}/{bot}/{name}")
}

pub fn secret(host: &dyn Host, bot: &str) -> Option<String> {
    host.store_get(&secret_key(bot))
        .and_then(|b| String::from_utf8(b).ok())
        .filter(|s| !s.is_empty())
}

pub fn offset(host: &dyn Host, bot: &str) -> i64 {
    host.store_get(&offset_key(bot))
        .and_then(|b| b.try_into().ok().map(i64::from_le_bytes))
        .unwrap_or(0)
}

pub fn put_offset(host: &mut dyn Host, bot: &str, o: i64) {
    let _ = host.store_put(&offset_key(bot), &o.to_le_bytes());
}

pub fn load_rights(host: &dyn Host, c: char, bot: &str, name: &str) -> Option<Rights> {
    Rights::from_value(&get(host, &rights_key(c, bot, name))?)
}

pub fn put_rights(
    host: &mut dyn Host,
    c: char,
    bot: &str,
    name: &str,
    r: &Rights,
) -> Result<(), AppError> {
    put(host, &rights_key(c, bot, name), &r.to_value())
}

pub fn delete_item(host: &mut dyn Host, c: char, bot: &str, name: &str) {
    host.store_delete(&item(c, bot, name));
    host.store_delete(&rights_key(c, bot, name));
}

/// Everything of a bot.
pub fn delete_bot(host: &mut dyn Host, bot: &str) {
    for c in ['r', 't', 'u'] {
        for n in index(host, &coll(c, bot)) {
            delete_item(host, c, bot, &n);
        }
        host.store_delete(&coll(c, bot));
    }
    host.store_delete(&self::bot(bot));
    host.store_delete(&secret_key(bot));
    host.store_delete(&offset_key(bot));
}
