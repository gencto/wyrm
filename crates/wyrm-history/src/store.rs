//! The sample store (ADR 0014): one redb file per UTC day under
//! `<dir>/days/YYYY-MM-DD.redb`, rows keyed `(series, t µs)` with the value
//! as canonical CBOR `[v, q]`; `<dir>/index.redb` maps point keys to series
//! numbers. A day is the unit of retention: deleting old data deletes whole
//! files, so the disk gets the space back at once (redb reuses freed pages
//! but does not shrink a file).
//!
//! All calls block (file I/O and fsync): run them off the async runtime.

use crate::time::{day_name, parse_day, US_PER_DAY};
use redb::{
    Builder, Database, ReadableDatabase, ReadableTable, ReadableTableMetadata, TableDefinition,
    TableError,
};
use std::collections::{BTreeMap, HashMap, VecDeque};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use wyrm_core::{codec, Quality, Value};

const ROWS: TableDefinition<(u32, u64), &[u8]> = TableDefinition::new("rows");
const SERIES: TableDefinition<&str, u32> = TableDefinition::new("series");
/// Page cache of each open file. redb's default (1 GiB) does not fit the
/// 2 GB reference board.
const CACHE_BYTES: usize = 8 << 20;
/// Day files kept open (the current one, plus recent reads).
const MAX_OPEN: usize = 4;

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("history store: {0}")]
    Db(String),
    #[error("history store: {0}")]
    Io(#[from] std::io::Error),
}

fn db<E: std::fmt::Display>(e: E) -> Error {
    Error::Db(e.to_string())
}

pub type Result<T> = std::result::Result<T, Error>;

/// A row to store: `(series, t µs, encode_row(..))`.
pub type NewRow = (u32, u64, Vec<u8>);

/// One stored sample.
#[derive(Debug, Clone, PartialEq)]
pub struct Row {
    pub t: u64,
    pub v: Value,
    pub q: Quality,
}

/// The stored bytes of one sample: canonical CBOR `[v, q]`.
pub fn encode_row(v: &Value, q: Quality) -> Vec<u8> {
    // Encoding a Value into a Vec cannot fail.
    codec::to_vec(&Value::Array(vec![v.clone(), Value::UInt(q.code().into())])).unwrap_or_default()
}

fn decode_row(t: u64, bytes: &[u8]) -> Option<Row> {
    let Value::Array(mut a) = codec::from_slice::<Value>(bytes).ok()? else {
        return None;
    };
    if a.len() != 2 {
        return None;
    }
    let q = match a.pop()? {
        Value::UInt(q) => u8::try_from(q)
            .ok()
            .and_then(|q| Quality::try_from(q).ok())?,
        _ => return None,
    };
    Some(Row { t, v: a.pop()?, q })
}

pub struct Store {
    dir: PathBuf,
    index: Database,
    series: Mutex<HashMap<String, u32>>,
    days: Mutex<OpenDays>,
}

#[derive(Default)]
struct OpenDays {
    open: HashMap<i64, Arc<Database>>,
    order: VecDeque<i64>,
}

fn builder() -> Builder {
    let mut b = Builder::new();
    b.set_cache_size(CACHE_BYTES);
    b
}

impl Store {
    /// Open or create the store in `dir`.
    pub fn open(dir: &Path) -> Result<Self> {
        std::fs::create_dir_all(dir.join("days"))?;
        let index = builder()
            .create(dir.join("index.redb"))
            .map_err(|e| match e {
                // the same wording as wyrm-state's lock: callers retry on it
                redb::DatabaseError::DatabaseAlreadyOpen => {
                    Error::Db(format!("{} is in use by another process", dir.display()))
                }
                e => db(e),
            })?;
        let mut series = HashMap::new();
        {
            let txn = index.begin_write().map_err(db)?;
            {
                let t = txn.open_table(SERIES).map_err(db)?;
                for item in t.iter().map_err(db)? {
                    let (k, v) = item.map_err(db)?;
                    series.insert(k.value().to_owned(), v.value());
                }
            }
            txn.commit().map_err(db)?;
        }
        Ok(Self {
            dir: dir.to_owned(),
            index,
            series: Mutex::new(series),
            days: Mutex::default(),
        })
    }

    pub fn dir(&self) -> &Path {
        &self.dir
    }

    /// The series number of a point key; `create` adds it when missing.
    pub fn series_id(&self, key: &str, create: bool) -> Result<Option<u32>> {
        let mut map = self.series.lock().unwrap_or_else(|p| p.into_inner());
        if let Some(id) = map.get(key) {
            return Ok(Some(*id));
        }
        if !create {
            return Ok(None);
        }
        let id = map.values().max().map_or(1, |m| m + 1);
        let txn = self.index.begin_write().map_err(db)?;
        {
            let mut t = txn.open_table(SERIES).map_err(db)?;
            t.insert(key, id).map_err(db)?;
        }
        txn.commit().map_err(db)?;
        map.insert(key.to_owned(), id);
        Ok(Some(id))
    }

    pub fn series_count(&self) -> usize {
        self.series.lock().unwrap_or_else(|p| p.into_inner()).len()
    }

    fn day_path(&self, day: i64) -> PathBuf {
        self.dir
            .join("days")
            .join(format!("{}.redb", day_name(day)))
    }

    /// Day numbers that have a file, oldest first.
    pub fn days(&self) -> Vec<i64> {
        let mut out: Vec<i64> = std::fs::read_dir(self.dir.join("days"))
            .into_iter()
            .flatten()
            .flatten()
            .filter_map(|e| {
                let name = e.file_name().into_string().ok()?;
                parse_day(name.strip_suffix(".redb")?)
            })
            .collect();
        out.sort_unstable();
        out
    }

    /// The open file of `day`; `create` makes it when missing.
    fn day(&self, day: i64, create: bool) -> Result<Option<Arc<Database>>> {
        let mut d = self.days.lock().unwrap_or_else(|p| p.into_inner());
        if let Some(h) = d.open.get(&day) {
            let h = h.clone();
            d.order.retain(|x| *x != day);
            d.order.push_back(day);
            return Ok(Some(h));
        }
        let path = self.day_path(day);
        if !create && !path.exists() {
            return Ok(None);
        }
        let h = Arc::new(builder().create(&path).map_err(db)?);
        d.open.insert(day, h.clone());
        d.order.push_back(day);
        while d.order.len() > MAX_OPEN {
            if let Some(old) = d.order.pop_front() {
                d.open.remove(&old);
            }
        }
        Ok(Some(h))
    }

    /// Store rows `(series, t, encode_row(..))`; one transaction per day.
    /// A row with the same series and time replaces the stored one.
    pub fn write(&self, rows: &[NewRow]) -> Result<usize> {
        let mut by_day: BTreeMap<i64, Vec<&NewRow>> = BTreeMap::new();
        for r in rows {
            by_day.entry((r.1 / US_PER_DAY) as i64).or_default().push(r);
        }
        for (day, rows) in by_day {
            let Some(h) = self.day(day, true)? else {
                continue;
            };
            let txn = h.begin_write().map_err(db)?;
            {
                let mut t = txn.open_table(ROWS).map_err(db)?;
                for (s, ts, v) in rows {
                    t.insert((*s, *ts), v.as_slice()).map_err(db)?;
                }
            }
            txn.commit().map_err(db)?;
        }
        Ok(rows.len())
    }

    /// Call `f` for each row of `series` in `[from, to]`, oldest first,
    /// until it returns `false`.
    pub fn scan(
        &self,
        series: u32,
        from: u64,
        to: u64,
        mut f: impl FnMut(Row) -> bool,
    ) -> Result<()> {
        let (first, last) = ((from / US_PER_DAY) as i64, (to / US_PER_DAY) as i64);
        for day in self.days() {
            if day < first || day > last {
                continue;
            }
            let Some(h) = self.day(day, false)? else {
                continue;
            };
            let r = h.begin_read().map_err(db)?;
            let t = match r.open_table(ROWS) {
                Ok(t) => t,
                Err(TableError::TableDoesNotExist(_)) => continue,
                Err(e) => return Err(db(e)),
            };
            for item in t.range((series, from)..=(series, to)).map_err(db)? {
                let (k, v) = item.map_err(db)?;
                if let Some(row) = decode_row(k.value().1, v.value()) {
                    if !f(row) {
                        return Ok(());
                    }
                }
            }
        }
        Ok(())
    }

    /// At most `limit` rows of `series` in `[from, to]`, oldest first.
    pub fn read(&self, series: u32, from: u64, to: u64, limit: usize) -> Result<Vec<Row>> {
        let mut out = Vec::new();
        self.scan(series, from, to, |r| {
            out.push(r);
            out.len() < limit
        })?;
        Ok(out)
    }

    /// The first (`newest: false`) or last stored row of `series`.
    pub fn edge(&self, series: u32, newest: bool) -> Result<Option<Row>> {
        let mut days = self.days();
        if newest {
            days.reverse();
        }
        for day in days {
            let Some(h) = self.day(day, false)? else {
                continue;
            };
            let r = h.begin_read().map_err(db)?;
            let t = match r.open_table(ROWS) {
                Ok(t) => t,
                Err(TableError::TableDoesNotExist(_)) => continue,
                Err(e) => return Err(db(e)),
            };
            let mut range = t.range((series, 0)..=(series, u64::MAX)).map_err(db)?;
            let item = if newest {
                range.next_back()
            } else {
                range.next()
            };
            if let Some(item) = item {
                let (k, v) = item.map_err(db)?;
                return Ok(decode_row(k.value().1, v.value()));
            }
        }
        Ok(None)
    }

    /// Delete the rows of `series` (or of every series) in `[from, to]`.
    /// A day the range covers whole goes as a file when every series is
    /// purged; a day left empty goes too. Returns the rows deleted.
    pub fn purge(&self, series: Option<u32>, from: u64, to: u64) -> Result<u64> {
        let mut total = 0;
        for day in self.days() {
            let start = day as u64 * US_PER_DAY;
            let end = start + US_PER_DAY - 1;
            if end < from || start > to {
                continue;
            }
            let Some(h) = self.day(day, false)? else {
                continue;
            };
            if series.is_none() && from <= start && to >= end {
                total += Self::rows_in(&h)?;
                drop(h);
                self.remove_day(day)?;
                continue;
            }
            let mut n = 0u64;
            let left = {
                let txn = h.begin_write().map_err(db)?;
                let left = {
                    let mut t = txn.open_table(ROWS).map_err(db)?;
                    match series {
                        Some(s) => t
                            .retain_in((s, from)..=(s, to), |_, _| {
                                n += 1;
                                false
                            })
                            .map_err(db)?,
                        None => t
                            .retain(|(_, ts), _| {
                                let hit = ts >= from && ts <= to;
                                n += u64::from(hit);
                                !hit
                            })
                            .map_err(db)?,
                    }
                    t.len().map_err(db)?
                };
                txn.commit().map_err(db)?;
                left
            };
            total += n;
            if left == 0 {
                drop(h);
                self.remove_day(day)?;
            }
        }
        Ok(total)
    }

    fn rows_in(h: &Database) -> Result<u64> {
        let r = h.begin_read().map_err(db)?;
        match r.open_table(ROWS) {
            Ok(t) => t.len().map_err(db),
            Err(TableError::TableDoesNotExist(_)) => Ok(0),
            Err(e) => Err(db(e)),
        }
    }

    /// Delete the oldest day file: `(day, rows)`, or `None` if there is none.
    pub fn drop_oldest_day(&self) -> Result<Option<(i64, u64)>> {
        let Some(day) = self.days().first().copied() else {
            return Ok(None);
        };
        let rows = match self.day(day, false)? {
            Some(h) => Self::rows_in(&h)?,
            None => 0,
        };
        self.remove_day(day)?;
        Ok(Some((day, rows)))
    }

    fn remove_day(&self, day: i64) -> Result<()> {
        {
            let mut d = self.days.lock().unwrap_or_else(|p| p.into_inner());
            d.open.remove(&day);
            d.order.retain(|x| *x != day);
        }
        match std::fs::remove_file(self.day_path(day)) {
            Err(e) if e.kind() != std::io::ErrorKind::NotFound => Err(e.into()),
            _ => Ok(()),
        }
    }

    /// Bytes of every store file.
    pub fn size_bytes(&self) -> u64 {
        let len = |p: PathBuf| std::fs::metadata(p).map(|m| m.len()).unwrap_or(0);
        len(self.dir.join("index.redb"))
            + self
                .days()
                .into_iter()
                .map(|d| len(self.day_path(d)))
                .sum::<u64>()
    }

    /// Day files open now.
    pub fn open_files(&self) -> usize {
        self.days
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .open
            .len()
            + 1
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::time::parse_iso;

    pub(crate) fn temp(name: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("wyrm-hist-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        d
    }

    fn row(s: u32, t: u64, v: f64) -> NewRow {
        (s, t, encode_row(&Value::Float(v), Quality::Good))
    }

    #[test]
    fn rows_by_series_and_day() {
        let dir = temp("rows");
        let st = Store::open(&dir).unwrap();
        let a = st.series_id("wy/s/down/mock/a", true).unwrap().unwrap();
        let b = st.series_id("wy/s/down/mock/b", true).unwrap().unwrap();
        assert_ne!(a, b);
        assert_eq!(st.series_id("wy/s/down/mock/a", false).unwrap(), Some(a));
        assert_eq!(st.series_id("wy/s/down/mock/c", false).unwrap(), None);
        let d1 = parse_iso("2026-10-21T23:59:59Z").unwrap();
        let d2 = parse_iso("2026-10-22T00:00:01Z").unwrap();
        st.write(&[row(a, d1, 1.0), row(a, d2, 2.0), row(b, d2, 9.0)])
            .unwrap();
        assert_eq!(st.days().len(), 2);
        let rows = st.read(a, 0, u64::MAX, 100).unwrap();
        assert_eq!(
            rows.iter().map(|r| (r.t, r.v.clone())).collect::<Vec<_>>(),
            [(d1, Value::Float(1.0)), (d2, Value::Float(2.0))]
        );
        assert_eq!(st.read(a, 0, u64::MAX, 1).unwrap().len(), 1);
        assert_eq!(st.read(a, d2, d2, 10).unwrap()[0].v, Value::Float(2.0));
        assert_eq!(st.edge(a, true).unwrap().unwrap().t, d2);
        assert_eq!(st.edge(a, false).unwrap().unwrap().t, d1);
        assert_eq!(st.edge(99, true).unwrap(), None);
        // same time replaces
        st.write(&[row(a, d2, 3.0)]).unwrap();
        assert_eq!(st.edge(a, true).unwrap().unwrap().v, Value::Float(3.0));
        // reopen: series and rows stay
        drop(st);
        let st = Store::open(&dir).unwrap();
        assert_eq!(st.series_id("wy/s/down/mock/b", false).unwrap(), Some(b));
        assert_eq!(st.read(b, 0, u64::MAX, 10).unwrap().len(), 1);
        assert!(st.size_bytes() > 0);
        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn purge_deletes_rows_and_whole_days() {
        let dir = temp("purge");
        let st = Store::open(&dir).unwrap();
        let a = st.series_id("a", true).unwrap().unwrap();
        let b = st.series_id("b", true).unwrap().unwrap();
        let day0 = parse_iso("2026-10-20").unwrap();
        let mut rows = Vec::new();
        for d in 0..3 {
            for h in 0..4 {
                let t = day0 + d * US_PER_DAY + h * 3_600_000_000;
                rows.push(row(a, t, h as f64));
                rows.push(row(b, t, h as f64));
            }
        }
        st.write(&rows).unwrap();
        assert_eq!(st.days().len(), 3);
        // one series, one hour
        assert_eq!(st.purge(Some(a), day0, day0 + 1).unwrap(), 1);
        assert_eq!(st.read(a, 0, u64::MAX, 100).unwrap().len(), 11);
        assert_eq!(st.read(b, 0, u64::MAX, 100).unwrap().len(), 12);
        // every series, the whole first day: the file goes
        assert_eq!(st.purge(None, day0, day0 + US_PER_DAY - 1).unwrap(), 7);
        assert_eq!(st.days().len(), 2);
        // the oldest day
        let (day, n) = st.drop_oldest_day().unwrap().unwrap();
        assert_eq!((day, n), ((day0 / US_PER_DAY) as i64 + 1, 8));
        // a day left empty goes as a file
        let last = day0 + 2 * US_PER_DAY;
        st.purge(Some(a), last, last + US_PER_DAY).unwrap();
        st.purge(Some(b), last, last + US_PER_DAY).unwrap();
        assert!(st.days().is_empty());
        assert_eq!(st.drop_oldest_day().unwrap(), None);
        let _ = std::fs::remove_dir_all(dir);
    }
}
