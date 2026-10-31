//! The sample store (ADR 0014): one redb file per UTC day under
//! `<dir>/days/YYYY-MM-DD.redb`, rows keyed `(series, t µs)` with the value
//! as canonical CBOR `[v, q]`; `<dir>/index.redb` maps point keys to series
//! numbers. A day is the unit of retention: deleting old data deletes whole
//! files, so the disk gets the space back at once (redb reuses freed pages
//! but does not shrink a file).
//!
//! Each day file also keeps a change journal (ADR 0026): `seq → (series,
//! t)` for every row written, in the same transaction as the row, so sinks
//! read what was written after their cursor, late rows and rows written
//! again included. `seq` is one counter for the store, reserved in blocks in
//! `index.redb` before use: a crash leaves gaps, never repeats. Writes are
//! serialised and take their numbers in day order, so a reader never sees a
//! number while a lower one is still to commit.
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
/// Day file: change journal, `seq → (series, t)`.
const CHANGES: TableDefinition<u64, (u32, u64)> = TableDefinition::new("changes");
/// Index: `seq` numbers reserved so far (`"seq_end"`, exclusive).
const META: TableDefinition<&str, u64> = TableDefinition::new("meta");
/// Index: the `seq` range of each day file, `day → (first, last)`.
const DAY_SEQ: TableDefinition<i64, (u64, u64)> = TableDefinition::new("day_seq");
/// `seq` numbers reserved per index transaction.
const SEQ_BLOCK: u64 = 4096;
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

/// One journal entry with its row, as a sink reads it (ADR 0026).
#[derive(Debug, Clone, PartialEq)]
pub struct Change {
    pub seq: u64,
    pub series: u32,
    pub row: Row,
}

/// Bounds of one [`Store::changes`] read.
#[derive(Debug, Clone, Copy)]
pub struct ChangeLimit {
    pub rows: usize,
    /// Stored bytes of the rows' values; at least one row is returned.
    pub bytes: usize,
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
    /// Held for a whole [`write`](Self::write): numbers become visible in order.
    journal: Mutex<Journal>,
}

/// The `seq` counter and the range of each day.
#[derive(Default)]
struct Journal {
    /// The next number to hand out.
    next: u64,
    /// Numbers below this are reserved in the index.
    end: u64,
    ranges: BTreeMap<i64, (u64, u64)>,
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
        let mut journal = Journal::default();
        {
            let txn = index.begin_write().map_err(db)?;
            {
                let meta = txn.open_table(META).map_err(db)?;
                let end = meta.get("seq_end").map_err(db)?.map_or(1, |v| v.value());
                // unused numbers of the last block are skipped: gaps, no repeats
                journal.next = end;
                journal.end = end;
                let ranges = txn.open_table(DAY_SEQ).map_err(db)?;
                for item in ranges.iter().map_err(db)? {
                    let (k, v) = item.map_err(db)?;
                    journal.ranges.insert(k.value(), v.value());
                }
            }
            {
                let mut t = txn.open_table(SERIES).map_err(db)?;
                for item in t.iter().map_err(db)? {
                    let (k, v) = item.map_err(db)?;
                    series.insert(k.value().to_owned(), v.value());
                }
                // Series recorded before spec 0.2.0 (`wy/<site>/down/…`) go on
                // under their new names, so watches renamed by the registry
                // find their rows.
                let old: Vec<(String, String, u32)> = series
                    .iter()
                    .filter_map(|(k, id)| {
                        let new = wyrm_core::keyspace::renamed(k);
                        (new != k.as_str() && !series.contains_key(new.as_ref()))
                            .then(|| (k.clone(), new.into_owned(), *id))
                    })
                    .collect();
                for (k, new, id) in old {
                    t.remove(k.as_str()).map_err(db)?;
                    t.insert(new.as_str(), id).map_err(db)?;
                    series.remove(&k);
                    series.insert(new, id);
                }
            }
            txn.commit().map_err(db)?;
        }
        Ok(Self {
            dir: dir.to_owned(),
            index,
            series: Mutex::new(series),
            days: Mutex::default(),
            journal: Mutex::new(journal),
        })
    }

    /// The highest `seq` handed out so far (0: none).
    pub fn last_seq(&self) -> u64 {
        lock(&self.journal).next - 1
    }

    /// The `seq` range `(first, last)` of `day`, if it has a journal.
    pub fn day_seq(&self, day: i64) -> Option<(u64, u64)> {
        lock(&self.journal).ranges.get(&day).copied()
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

    /// Store rows `(series, t, encode_row(..))`; one transaction per day,
    /// each row with its journal entry. A row with the same series and time
    /// replaces the stored one and gets a new `seq`.
    pub fn write(&self, rows: &[NewRow]) -> Result<usize> {
        let mut by_day: BTreeMap<i64, Vec<&NewRow>> = BTreeMap::new();
        for r in rows {
            by_day.entry((r.1 / US_PER_DAY) as i64).or_default().push(r);
        }
        let mut j = lock(&self.journal);
        // Number the rows in day order, then record the numbers and the
        // ranges in the index before any day commits: a crash after this
        // leaves a range wider than its file, never a row outside its range.
        let first = j.next;
        let mut next = first;
        let mut ranges = Vec::with_capacity(by_day.len());
        for (day, rows) in &by_day {
            let n = rows.len() as u64;
            let (lo, hi) = j.ranges.get(day).copied().unwrap_or((next, next));
            ranges.push((*day, (lo.min(next), hi.max(next + n - 1))));
            next += n;
        }
        if !by_day.is_empty() {
            let end = if next > j.end {
                next.div_ceil(SEQ_BLOCK) * SEQ_BLOCK
            } else {
                j.end
            };
            let txn = self.index.begin_write().map_err(db)?;
            {
                let mut meta = txn.open_table(META).map_err(db)?;
                meta.insert("seq_end", end).map_err(db)?;
                let mut t = txn.open_table(DAY_SEQ).map_err(db)?;
                for (day, r) in &ranges {
                    t.insert(*day, *r).map_err(db)?;
                }
            }
            txn.commit().map_err(db)?;
            j.end = end;
            j.next = next;
            j.ranges.extend(ranges);
        }
        let mut seq = first;
        for (day, rows) in by_day {
            let Some(h) = self.day(day, true)? else {
                continue;
            };
            let txn = h.begin_write().map_err(db)?;
            {
                let mut t = txn.open_table(ROWS).map_err(db)?;
                let mut c = txn.open_table(CHANGES).map_err(db)?;
                for (s, ts, v) in rows {
                    t.insert((*s, *ts), v.as_slice()).map_err(db)?;
                    c.insert(seq, (*s, *ts)).map_err(db)?;
                    seq += 1;
                }
            }
            txn.commit().map_err(db)?;
        }
        Ok(rows.len())
    }

    /// Rows written after `after`, lowest `seq` first, of the series `want`
    /// accepts, within `limit`. An entry whose row is gone (purged) is
    /// skipped; a row written twice comes once per write.
    pub fn changes(
        &self,
        after: u64,
        limit: ChangeLimit,
        mut want: impl FnMut(u32) -> bool,
    ) -> Result<Vec<Change>> {
        let days: Vec<i64> = lock(&self.journal)
            .ranges
            .iter()
            .filter(|(_, (_, hi))| *hi > after)
            .map(|(d, _)| *d)
            .collect();
        // each day's first entries above `after`, merged by seq
        let mut all: Vec<(Change, usize)> = Vec::new();
        for day in days {
            let Some(h) = self.day(day, false)? else {
                continue;
            };
            let r = h.begin_read().map_err(db)?;
            let (c, t) = match (r.open_table(CHANGES), r.open_table(ROWS)) {
                (Ok(c), Ok(t)) => (c, t),
                (Err(TableError::TableDoesNotExist(_)), _)
                | (_, Err(TableError::TableDoesNotExist(_))) => continue,
                (Err(e), _) | (_, Err(e)) => return Err(db(e)),
            };
            let mut taken = 0;
            for item in c.range(after + 1..).map_err(db)? {
                let (k, v) = item.map_err(db)?;
                let (series, ts) = v.value();
                if !want(series) {
                    continue;
                }
                let Some(bytes) = t.get((series, ts)).map_err(db)? else {
                    continue;
                };
                let bytes = bytes.value();
                if let Some(row) = decode_row(ts, bytes) {
                    all.push((
                        Change {
                            seq: k.value(),
                            series,
                            row,
                        },
                        bytes.len(),
                    ));
                    taken += 1;
                    if taken >= limit.rows {
                        break;
                    }
                }
            }
        }
        all.sort_by_key(|(c, _)| c.seq);
        let mut out = Vec::new();
        let mut bytes = 0;
        for (c, n) in all {
            if out.len() >= limit.rows || (!out.is_empty() && bytes + n > limit.bytes) {
                break;
            }
            bytes += n;
            out.push(c);
        }
        Ok(out)
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
            Err(e) if e.kind() != std::io::ErrorKind::NotFound => return Err(e.into()),
            _ => {}
        }
        let mut j = lock(&self.journal);
        if j.ranges.remove(&day).is_some() {
            let txn = self.index.begin_write().map_err(db)?;
            txn.open_table(DAY_SEQ)
                .map_err(db)?
                .remove(day)
                .map_err(db)?;
            txn.commit().map_err(db)?;
        }
        Ok(())
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

fn lock<T>(m: &Mutex<T>) -> std::sync::MutexGuard<'_, T> {
    m.lock().unwrap_or_else(|p| p.into_inner())
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
    fn series_before_spec_0_2_are_renamed() {
        let dir = temp("renamed");
        let id = {
            let st = Store::open(&dir).unwrap();
            let id = st.series_id("wy/s/down/m/p0", true).unwrap().unwrap();
            st.series_id("wy/s/sys/x", true).unwrap();
            id
        };
        let st = Store::open(&dir).unwrap();
        assert_eq!(
            st.series_id("wy/s/downstream/m/p0", false).unwrap(),
            Some(id)
        );
        assert_eq!(st.series_id("wy/s/down/m/p0", false).unwrap(), None);
        assert!(st.series_id("wy/s/sys/x", false).unwrap().is_some());
    }

    #[test]
    fn rows_by_series_and_day() {
        let dir = temp("rows");
        let st = Store::open(&dir).unwrap();
        let a = st
            .series_id("wy/s/downstream/mock/a", true)
            .unwrap()
            .unwrap();
        let b = st
            .series_id("wy/s/downstream/mock/b", true)
            .unwrap()
            .unwrap();
        assert_ne!(a, b);
        assert_eq!(
            st.series_id("wy/s/downstream/mock/a", false).unwrap(),
            Some(a)
        );
        assert_eq!(st.series_id("wy/s/downstream/mock/c", false).unwrap(), None);
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
        assert_eq!(
            st.series_id("wy/s/downstream/mock/b", false).unwrap(),
            Some(b)
        );
        assert_eq!(st.read(b, 0, u64::MAX, 10).unwrap().len(), 1);
        assert!(st.size_bytes() > 0);
        let _ = std::fs::remove_dir_all(dir);
    }

    fn seqs(st: &Store, after: u64) -> Vec<(u64, u32, u64)> {
        let all = ChangeLimit {
            rows: 1000,
            bytes: usize::MAX,
        };
        st.changes(after, all, |_| true)
            .unwrap()
            .into_iter()
            .map(|c| (c.seq, c.series, c.row.t))
            .collect()
    }

    #[test]
    fn journal_numbers_every_write_in_order() {
        let dir = temp("journal");
        let st = Store::open(&dir).unwrap();
        assert_eq!(st.last_seq(), 0);
        let (a, b) = (1, 2);
        let d1 = parse_iso("2026-10-21T10:00:00Z").unwrap();
        let d2 = parse_iso("2026-10-22T10:00:00Z").unwrap();
        st.write(&[row(a, d2, 1.0), row(a, d1, 2.0), row(b, d2, 3.0)])
            .unwrap();
        // day order first: the earlier day's row has the lower number
        assert_eq!(seqs(&st, 0), [(1, a, d1), (2, a, d2), (3, b, d2)]);
        assert_eq!(st.last_seq(), 3);
        let day1 = (d1 / US_PER_DAY) as i64;
        assert_eq!(st.day_seq(day1), Some((1, 1)));
        // a cursor at the end sees nothing
        assert!(seqs(&st, 3).is_empty());
        // a late row into the earlier day, and a row written again: both
        // come after the cursor
        st.write(&[row(b, d1, 4.0)]).unwrap();
        st.write(&[row(a, d2, 5.0)]).unwrap();
        assert_eq!(seqs(&st, 3), [(4, b, d1), (5, a, d2)]);
        assert_eq!(st.day_seq(day1), Some((1, 4)));
        // the row written again carries its new value under both numbers
        let v = |after| {
            st.changes(
                after,
                ChangeLimit {
                    rows: 10,
                    bytes: usize::MAX,
                },
                |s| s == a,
            )
            .unwrap()
            .into_iter()
            .map(|c| (c.seq, c.row.v))
            .collect::<Vec<_>>()
        };
        assert_eq!(
            v(0),
            [
                (1, Value::Float(2.0)),
                (2, Value::Float(5.0)),
                (5, Value::Float(5.0))
            ]
        );
        // bounds: rows, and bytes (at least one row)
        let one = ChangeLimit {
            rows: 2,
            bytes: usize::MAX,
        };
        assert_eq!(st.changes(0, one, |_| true).unwrap().len(), 2);
        let tiny = ChangeLimit { rows: 10, bytes: 1 };
        assert_eq!(st.changes(0, tiny, |_| true).unwrap().len(), 1);
        // reopen: numbers go on above the last one, ranges stay
        drop(st);
        let st = Store::open(&dir).unwrap();
        assert!(st.last_seq() >= 5);
        assert_eq!(st.day_seq(day1), Some((1, 4)));
        st.write(&[row(b, d2, 6.0)]).unwrap();
        let after = seqs(&st, 5);
        assert_eq!(after.len(), 1);
        assert!(after[0].0 > 5, "{after:?}");
        // a purged row is skipped; a removed day loses its range
        st.purge(Some(b), d1, d1).unwrap();
        assert_eq!(seqs(&st, 3), [(5, a, d2), (after[0].0, b, d2)]);
        st.purge(
            None,
            day1 as u64 * US_PER_DAY,
            (day1 as u64 + 1) * US_PER_DAY - 1,
        )
        .unwrap();
        assert_eq!(st.day_seq(day1), None);
        assert_eq!(seqs(&st, 0).first().map(|c| c.0), Some(2));
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
