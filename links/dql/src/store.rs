//! The host store (ADR 0023) of the DQL link: `index` (CBOR array of the stored query ids; the
//! store has no key listing) and `q/<id>` (the definition, CBOR of a map). Ad-hoc queries are
//! not stored. The export is JSON `wyrm-dql/1`.

use std::collections::BTreeMap;

use wyrm_core::{codec, Perm, Status, Value};
use wyrm_link_api::{AppError, Host};

pub const INDEX: &str = "index";
pub const FORMAT: &str = "wyrm-dql/1";

fn key(id: &str) -> String {
    format!("q/{id}")
}

/// A query definition.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Def {
    pub id: String,
    pub display: String,
    pub text: String,
    pub enabled: bool,
    pub publish_ms: u64,
    /// The whole table is the value `<id>/table` (set with `config`); otherwise `get_table`
    /// answers each caller with the rows it may read (ADR 0025 item 4, owner decision).
    pub publish: bool,
    pub created_by: String,
    /// What its author may do, kept from the call that defined it (ADR 0025 item 4). `None`: a
    /// definition from before it was kept; it does not run.
    pub rights: Option<Rights>,
}

/// The author's rights (`Who::authority`) and the site they were given on.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Rights {
    pub site: String,
    pub grants: Vec<(String, Perm)>,
}

impl Rights {
    fn to_value(&self) -> Value {
        Value::Map(BTreeMap::from([
            ("site".to_owned(), Value::Str(self.site.clone())),
            (
                "grants".to_owned(),
                Value::Array(
                    self.grants
                        .iter()
                        .map(|(k, p)| {
                            Value::Array(vec![Value::Str(k.clone()), Value::UInt(p.code().into())])
                        })
                        .collect(),
                ),
            ),
        ]))
    }

    /// A grant it cannot read makes the whole thing unreadable: never widened.
    fn from_value(v: &Value) -> Option<Self> {
        let Value::Map(m) = v else { return None };
        let Some(Value::Str(site)) = m.get("site") else {
            return None;
        };
        let Some(Value::Array(gs)) = m.get("grants") else {
            return None;
        };
        let grants = gs
            .iter()
            .map(|g| match g {
                Value::Array(a) => match a.as_slice() {
                    [Value::Str(k), Value::UInt(p)] => u8::try_from(*p)
                        .ok()
                        .and_then(|p| Perm::try_from(p).ok())
                        .map(|p| (k.clone(), p)),
                    _ => None,
                },
                _ => None,
            })
            .collect::<Option<Vec<_>>>()?;
        Some(Self {
            site: site.clone(),
            grants,
        })
    }
}

impl Def {
    fn to_value(&self) -> Value {
        let s = |v: &str| Value::Str(v.to_owned());
        let mut m = BTreeMap::from([
            ("id".to_owned(), s(&self.id)),
            ("display".to_owned(), s(&self.display)),
            ("text".to_owned(), s(&self.text)),
            ("enabled".to_owned(), Value::Bool(self.enabled)),
            ("publish_ms".to_owned(), Value::UInt(self.publish_ms)),
            ("publish".to_owned(), Value::Bool(self.publish)),
            ("created_by".to_owned(), s(&self.created_by)),
        ]);
        if let Some(r) = &self.rights {
            m.insert("rights".to_owned(), r.to_value());
        }
        Value::Map(m)
    }

    fn from_value(v: &Value) -> Result<Self, String> {
        let Value::Map(m) = v else {
            return Err("not a map".into());
        };
        let text = |k: &str| match m.get(k) {
            Some(Value::Str(s)) => Ok(s.clone()),
            _ => Err(format!("{k}: text expected")),
        };
        Ok(Self {
            id: text("id")?,
            display: text("display").unwrap_or_default(),
            text: text("text")?,
            enabled: !matches!(m.get("enabled"), Some(Value::Bool(false))),
            publish_ms: match m.get("publish_ms") {
                Some(Value::UInt(n)) => *n,
                Some(Value::Int(n)) if *n > 0 => *n as u64,
                _ => crate::DEFAULT_PUBLISH_MS,
            },
            publish: matches!(m.get("publish"), Some(Value::Bool(true))),
            created_by: text("created_by").unwrap_or_default(),
            rights: m.get("rights").and_then(Rights::from_value),
        })
    }
}

fn store_err(e: impl std::fmt::Display) -> AppError {
    AppError::new(Status::InternalError, e.to_string())
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

pub fn put_index(host: &mut dyn Host, ids: &[String]) -> Result<(), AppError> {
    let v = Value::Array(ids.iter().cloned().map(Value::Str).collect());
    host.store_put(INDEX, &codec::to_vec(&v).map_err(store_err)?)
}

pub fn load_def(host: &dyn Host, id: &str) -> Result<Def, String> {
    let b = host.store_get(&key(id)).ok_or("not in the store")?;
    Def::from_value(&codec::from_slice::<Value>(&b).map_err(|e| e.to_string())?)
}

pub fn put_def(host: &mut dyn Host, def: &Def) -> Result<(), AppError> {
    host.store_put(
        &key(&def.id),
        &codec::to_vec(&def.to_value()).map_err(store_err)?,
    )
}

pub fn delete_def(host: &mut dyn Host, id: &str) {
    host.store_delete(&key(id));
}

pub fn to_json(def: &Def) -> String {
    serde_json::json!({
        "format": FORMAT,
        "id": def.id,
        "display": def.display,
        "text": def.text,
        "enabled": def.enabled,
        "publish_ms": def.publish_ms,
        "publish": def.publish,
    })
    .to_string()
}

pub fn from_json(s: &str) -> Result<Def, String> {
    let v: serde_json::Value = serde_json::from_str(s).map_err(|e| e.to_string())?;
    if v.get("format").and_then(|f| f.as_str()) != Some(FORMAT) {
        return Err(format!("format: {FORMAT} expected"));
    }
    let text = |k: &str| v.get(k).and_then(|x| x.as_str()).map(str::to_owned);
    Ok(Def {
        id: text("id").ok_or("id: text expected")?,
        display: text("display").unwrap_or_default(),
        text: text("text").ok_or("text: text expected")?,
        enabled: v.get("enabled").and_then(|x| x.as_bool()).unwrap_or(true),
        publish_ms: v
            .get("publish_ms")
            .and_then(|x| x.as_u64())
            .unwrap_or(crate::DEFAULT_PUBLISH_MS),
        publish: v.get("publish").and_then(|x| x.as_bool()).unwrap_or(false),
        created_by: String::new(),
        rights: None,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn defs_round_trip() {
        let d = Def {
            id: "q".into(),
            display: "Q".into(),
            text: "list wy/s/downstream".into(),
            enabled: false,
            publish_ms: 250,
            publish: true,
            created_by: "user:ann".into(),
            rights: Some(Rights {
                site: "s".into(),
                grants: vec![("wy/s/downstream/**".into(), Perm::Read)],
            }),
        };
        assert_eq!(Def::from_value(&d.to_value()).unwrap(), d);
        // the export carries neither the author nor their rights: an import takes the importer's
        let j = from_json(&to_json(&d)).unwrap();
        assert_eq!(
            j,
            Def {
                created_by: String::new(),
                rights: None,
                ..d
            }
        );
        assert!(from_json("{}").is_err());
    }
}
