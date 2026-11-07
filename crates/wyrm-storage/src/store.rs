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

    /// Bytes on disk (CBOR); the storage's total limit counts these.
    pub fn size(&self) -> usize {
        self.encode().len()
    }

    /// The record as stored (CBOR); [`Rec::from_bytes`] reads it back.
    pub fn to_bytes(&self) -> Vec<u8> {
        self.encode()
    }

    /// What [`Rec::to_bytes`] made; `None` for anything else.
    pub fn from_bytes(bytes: &[u8]) -> Option<Self> {
        Self::decode(bytes)
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
    /// [`Rec::size`] of every node.
    bytes: usize,
    /// Change counter of this run (ADR 0036, stage B): every put, delete
    /// and value set is one revision.
    rev: u64,
    /// The last [`JOURNAL`] changes, by revision: the path, and whether
    /// the change was a delete.
    journal: BTreeMap<u64, (String, bool)>,
}

/// Changes kept for a standby's [`Store::changes_since`]; a standby
/// further behind gets the whole tree.
pub const JOURNAL: usize = 20_000;

/// What [`Store::changes_since`] answers.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct Changes {
    /// Identity of this run of the store: another epoch means the counter
    /// started again (a restart), so `since` means nothing.
    pub epoch: u64,
    /// The revision these changes bring the reader to.
    pub rev: u64,
    /// `put` is the whole tree: delete every other path.
    pub full: bool,
    pub put: Vec<(String, Rec)>,
    pub delete: Vec<String>,
}

pub struct Store {
    db: Database,
    inner: Mutex<Inner>,
    /// Microseconds at open: the epoch of the revision counter.
    epoch: u64,
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
        let mut bytes = 0;
        {
            let txn = db_.begin_write().map_err(db)?;
            {
                let t = txn.open_table(NODES).map_err(db)?;
                for item in t.iter().map_err(db)? {
                    let (k, v) = item.map_err(db)?;
                    match Rec::decode(v.value()) {
                        Some(r) => {
                            bytes += r.size();
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
        let epoch = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_micros() as u64)
            .unwrap_or(1)
            .max(1);
        Ok(Self {
            db: db_,
            inner: Mutex::new(Inner {
                nodes,
                dirty: BTreeSet::new(),
                bytes,
                rev: 0,
                journal: BTreeMap::new(),
            }),
            epoch,
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

    /// [`Rec::size`] of every node.
    pub fn bytes(&self) -> usize {
        self.lock().bytes
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
            if let Some(old) = inner.nodes.remove(&p) {
                inner.bytes -= old.size();
            }
            Self::note(&mut inner, p, true);
        }
        for (p, r) in put {
            inner.dirty.remove(&p);
            inner.bytes += r.size();
            if let Some(old) = inner.nodes.insert(p.clone(), r) {
                inner.bytes -= old.size();
            }
            Self::note(&mut inner, p, false);
        }
        Ok(())
    }

    fn note(inner: &mut Inner, path: String, deleted: bool) {
        inner.rev += 1;
        let rev = inner.rev;
        inner.journal.insert(rev, (path, deleted));
        while inner.journal.len() > JOURNAL {
            inner.journal.pop_first();
        }
    }

    /// The revision counter of this run.
    pub fn rev(&self) -> u64 {
        self.lock().rev
    }

    /// The changes after revision `since` (at most `max` paths), for a
    /// standby (ADR 0036): the whole tree when `since` is from another
    /// epoch, ahead of the counter, or older than the journal.
    pub fn changes_since(&self, epoch: u64, since: u64, max: usize) -> Changes {
        let inner = self.lock();
        let max = max.max(1);
        let oldest = inner.journal.keys().next().copied();
        let stale = epoch != self.epoch
            || since > inner.rev
            || oldest.is_some_and(|o| since + 1 < o && since < inner.rev);
        if stale {
            return Changes {
                epoch: self.epoch,
                rev: inner.rev,
                full: true,
                put: inner
                    .nodes
                    .iter()
                    .map(|(p, r)| (p.clone(), r.clone()))
                    .collect(),
                delete: Vec::new(),
            };
        }
        let mut seen = BTreeSet::new();
        let mut put = Vec::new();
        let mut delete = Vec::new();
        let mut rev = since;
        for (r, (path, _)) in inner.journal.range(since + 1..) {
            if seen.len() >= max {
                break;
            }
            rev = *r;
            if !seen.insert(path.clone()) {
                continue;
            }
            match inner.nodes.get(path) {
                Some(rec) => put.push((path.clone(), rec.clone())),
                None => delete.push(path.clone()),
            }
        }
        Changes {
            epoch: self.epoch,
            rev,
            full: false,
            put,
            delete,
        }
    }

    /// A new value of an existing value node: in memory now, on disk at
    /// the next [`flush`](Self::flush).
    pub fn set_value(&self, path: &str, v: Value, t: u64) -> bool {
        let mut inner = self.lock();
        let Some(r) = inner.nodes.get_mut(path) else {
            return false;
        };
        let old = r.size();
        r.value = Some(v);
        r.t = Some(t);
        let new = r.size();
        inner.bytes = inner.bytes - old + new;
        inner.dirty.insert(path.to_owned());
        Self::note(&mut inner, path.to_owned(), false);
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
        let sum: usize = s.snapshot().values().map(Rec::size).sum();
        assert_eq!(s.bytes(), sum);
        let x = s.get("a/x").unwrap();
        assert_eq!(
            (x.ty, x.value, x.t),
            (Some(TypeCode::Number), Some(Value::Float(2.5)), Some(8))
        );
        assert_eq!(s.subtree("a").len(), 2);
        s.apply(vec![], vec!["a/x".into(), "a".into()]).unwrap();
        assert!(s.is_empty());
        assert_eq!(s.bytes(), 0);
        let _ = std::fs::remove_dir_all(dir);
    }
}

#[cfg(test)]
mod replication_tests {
    use super::*;

    fn dir(name: &str) -> std::path::PathBuf {
        let d = std::env::temp_dir().join(format!(
            "wyrm-storage-changes-{name}-{}",
            std::process::id()
        ));
        let _ = std::fs::remove_dir_all(&d);
        d
    }

    fn value(v: f64) -> Rec {
        Rec {
            ty: Some(TypeCode::Number),
            editor: None,
            value: Some(Value::Float(v)),
            t: Some(1),
        }
    }

    #[test]
    fn changes_since_pages_journal_and_falls_back_to_full() {
        let s = Store::open(&dir("a")).unwrap();
        let first = s.changes_since(0, 0, 10);
        assert!(first.full && first.put.is_empty());
        let epoch = first.epoch;
        s.apply(
            vec![
                ("plant".into(), Rec::folder()),
                ("plant/t".into(), value(1.0)),
            ],
            vec![],
        )
        .unwrap();
        assert!(s.set_value("plant/t", Value::Float(2.0), 5));
        s.apply(vec![], vec!["plant/t".into()]).unwrap();
        assert_eq!(s.rev(), 4);
        // from zero in this epoch the journal still starts at 1: the
        // changes fold by path (plant put; plant/t put, set, deleted)
        let all = s.changes_since(epoch, 0, 10);
        assert!(!all.full);
        assert_eq!(all.rev, 4);
        assert_eq!(all.put.len(), 1, "plant alone is left");
        assert_eq!(all.delete, ["plant/t"]);
        // after the first two: the set and the delete of plant/t fold into one delete
        let c = s.changes_since(epoch, 2, 10);
        assert!(!c.full);
        assert_eq!(c.rev, 4);
        assert!(c.put.is_empty());
        assert_eq!(c.delete, ["plant/t"]);
        // a page of one path stops early and says where it got to
        s.apply(
            vec![
                ("plant/u".into(), value(3.0)),
                ("plant/v".into(), value(4.0)),
            ],
            vec![],
        )
        .unwrap();
        let page = s.changes_since(epoch, 4, 1);
        assert_eq!(page.rev, 5);
        assert_eq!(page.put.len(), 1);
        let rest = s.changes_since(epoch, page.rev, 10);
        assert_eq!(rest.rev, 6);
        assert_eq!(rest.put[0].0, "plant/v");
        // another epoch, or a revision ahead of ours: the whole tree
        assert!(s.changes_since(epoch + 1, 6, 10).full);
        assert!(s.changes_since(epoch, 99, 10).full);
        // nothing new
        let none = s.changes_since(epoch, 6, 10);
        assert!(!none.full && none.put.is_empty() && none.delete.is_empty() && none.rev == 6);
    }
}
