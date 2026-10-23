//! The storage tree on disk (ADR 0017): `<dir>/storage.redb`, one record
//! per node, keyed by its path under `wy/<site>/storage`. Structure changes
//! are written at once; values wait in memory for [`Store::flush`] (once a
//! second), so a crash loses at most the last second of values.

use redb::{Database, ReadableDatabase, ReadableTable, TableDefinition};
use std::collections::{BTreeMap, BTreeSet};
use std::path::Path;
use std::sync::{Mutex, MutexGuard};
use wyrm_core::{codec, TypeCode, Value};

const NODES: TableDefinition<&str, &[u8]> = TableDefinition::new("nodes");

/// One node: a folder (`ty` none) or a value of a type, with the editor a
/// UI should use, the last value and its time (µs since the epoch).
#[derive(Debug, Clone, PartialEq, Default)]
pub struct Rec {
    pub ty: Option<TypeCode>,
    pub editor: Option<String>,
    pub value: Option<Value>,
    pub t: Option<u64>,
}

impl Rec {
    pub fn folder() -> Self {
        Self::default()
    }

    pub fn is_folder(&self) -> bool {
        self.ty.is_none()
    }

    fn encode(&self) -> Vec<u8> {
        let mut m = BTreeMap::new();
        if let Some(t) = self.ty {
            m.insert("ty".to_owned(), Value::UInt(t.code().into()));
        }
        if let Some(e) = &self.editor {
            m.insert("editor".to_owned(), Value::Str(e.clone()));
        }
        if let Some(v) = &self.value {
            m.insert("v".to_owned(), v.clone());
        }
        if let Some(t) = self.t {
            m.insert("t".to_owned(), Value::UInt(t));
        }
        codec::to_vec(&Value::Map(m)).expect("a value encodes")
    }

    fn decode(bytes: &[u8]) -> Option<Self> {
        let Value::Map(mut m) = codec::from_slice::<Value>(bytes).ok()? else {
            return None;
        };
        let ty = match m.remove("ty") {
            Some(Value::UInt(c)) => Some(TypeCode::try_from(u8::try_from(c).ok()?).ok()?),
            _ => None,
        };
        let editor = match m.remove("editor") {
            Some(Value::Str(e)) => Some(e),
            _ => None,
        };
        let t = match m.remove("t") {
            Some(Value::UInt(t)) => Some(t),
            _ => None,
        };
        Some(Self {
            ty,
            editor,
            value: m.remove("v"),
            t,
        })
    }
}

struct Inner {
    nodes: BTreeMap<String, Rec>,
    /// Values set since the last flush.
    dirty: BTreeSet<String>,
}

pub struct Store {
    db: Database,
    inner: Mutex<Inner>,
}

fn db<E: std::fmt::Display>(e: E) -> String {
    format!("storage: {e}")
}

impl Store {
    /// Open or create the store in `dir`; every node is loaded.
    pub fn open(dir: &Path) -> Result<Self, String> {
        std::fs::create_dir_all(dir).map_err(db)?;
        let db_ = Database::create(dir.join("storage.redb")).map_err(db)?;
        let mut nodes = BTreeMap::new();
        {
            let txn = db_.begin_write().map_err(db)?;
            {
                let t = txn.open_table(NODES).map_err(db)?;
                for item in t.iter().map_err(db)? {
                    let (k, v) = item.map_err(db)?;
                    match Rec::decode(v.value()) {
                        Some(r) => {
                            nodes.insert(k.value().to_owned(), r);
                        }
                        None => {
                            tracing::warn!(path = %k.value(), "storage: unreadable record skipped")
                        }
                    }
                }
            }
            txn.commit().map_err(db)?;
        }
        Ok(Self {
            db: db_,
            inner: Mutex::new(Inner {
                nodes,
                dirty: BTreeSet::new(),
            }),
        })
    }

    fn lock(&self) -> MutexGuard<'_, Inner> {
        self.inner.lock().unwrap_or_else(|p| p.into_inner())
    }

    /// Every node, parents before their children.
    pub fn snapshot(&self) -> BTreeMap<String, Rec> {
        self.lock().nodes.clone()
    }

    pub fn get(&self, path: &str) -> Option<Rec> {
        self.lock().nodes.get(path).cloned()
    }

    pub fn len(&self) -> usize {
        self.lock().nodes.len()
    }

    pub fn is_empty(&self) -> bool {
        self.lock().nodes.is_empty()
    }

    /// `path` and every node below it.
    pub fn subtree(&self, path: &str) -> Vec<(String, Rec)> {
        let prefix = format!("{path}/");
        self.lock()
            .nodes
            .iter()
            .filter(|(k, _)| path.is_empty() || *k == path || k.starts_with(&prefix))
            .map(|(k, r)| (k.clone(), r.clone()))
            .collect()
    }

    /// A structure change in one transaction: `delete` these paths, then
    /// `put` these records (with their values).
    pub fn apply(&self, put: Vec<(String, Rec)>, delete: Vec<String>) -> Result<(), String> {
        let mut inner = self.lock();
        let txn = self.db.begin_write().map_err(db)?;
        {
            let mut t = txn.open_table(NODES).map_err(db)?;
            for p in &delete {
                t.remove(p.as_str()).map_err(db)?;
            }
            for (p, r) in &put {
                t.insert(p.as_str(), r.encode().as_slice()).map_err(db)?;
            }
        }
        txn.commit().map_err(db)?;
        for p in delete {
            inner.dirty.remove(&p);
            inner.nodes.remove(&p);
        }
        for (p, r) in put {
            inner.dirty.remove(&p);
            inner.nodes.insert(p, r);
        }
        Ok(())
    }

    /// A new value of an existing value node: in memory now, on disk at
    /// the next [`flush`](Self::flush).
    pub fn set_value(&self, path: &str, v: Value, t: u64) -> bool {
        let mut inner = self.lock();
        let Some(r) = inner.nodes.get_mut(path) else {
            return false;
        };
        r.value = Some(v);
        r.t = Some(t);
        inner.dirty.insert(path.to_owned());
        true
    }

    /// Write the values set since the last flush (one transaction).
    pub fn flush(&self) -> Result<usize, String> {
        let mut inner = self.lock();
        if inner.dirty.is_empty() {
            return Ok(0);
        }
        let txn = self.db.begin_write().map_err(db)?;
        let mut n = 0;
        {
            let mut t = txn.open_table(NODES).map_err(db)?;
            for p in &inner.dirty {
                if let Some(r) = inner.nodes.get(p) {
                    t.insert(p.as_str(), r.encode().as_slice()).map_err(db)?;
                    n += 1;
                }
            }
        }
        txn.commit().map_err(db)?;
        inner.dirty.clear();
        Ok(n)
    }

    /// Values on disk: what a restart would load.
    pub fn stored_value(&self, path: &str) -> Option<Value> {
        let txn = self.db.begin_read().ok()?;
        let t = txn.open_table(NODES).ok()?;
        let v = t.get(path).ok()??;
        Rec::decode(v.value())?.value
    }
}

impl Drop for Store {
    fn drop(&mut self) {
        if let Err(e) = self.flush() {
            tracing::warn!("{e}");
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp(name: &str) -> std::path::PathBuf {
        let d = std::env::temp_dir().join(format!("wyrm-storage-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        d
    }

    #[test]
    fn structure_now_values_on_flush() {
        let dir = temp("store");
        {
            let s = Store::open(&dir).unwrap();
            let value = Rec {
                ty: Some(TypeCode::Number),
                ..Rec::default()
            };
            s.apply(
                vec![("a".into(), Rec::folder()), ("a/x".into(), value)],
                vec![],
            )
            .unwrap();
            assert!(s.set_value("a/x", Value::Float(1.5), 7));
            assert_eq!(s.stored_value("a/x"), None, "not before a flush");
            assert_eq!(s.flush().unwrap(), 1);
            assert_eq!(s.stored_value("a/x"), Some(Value::Float(1.5)));
            assert!(!s.set_value("nope", Value::Null, 7));
            assert!(s.set_value("a/x", Value::Float(2.5), 8));
            // dropped: the last value is flushed
        }
        let s = Store::open(&dir).unwrap();
        assert_eq!(s.len(), 2);
        let x = s.get("a/x").unwrap();
        assert_eq!(
            (x.ty, x.value, x.t),
            (Some(TypeCode::Number), Some(Value::Float(2.5)), Some(8))
        );
        assert_eq!(s.subtree("a").len(), 2);
        s.apply(vec![], vec!["a/x".into(), "a".into()]).unwrap();
        assert!(s.is_empty());
        let _ = std::fs::remove_dir_all(dir);
    }
}
