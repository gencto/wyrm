//! `alarm`: watches on points that raise alarm records, acknowledged, noted and kept (ADR 0034),
//! as a portable link (ADR 0023). One source runs embedded in `wyrmd`, as a process
//! (`--features process`) and as a WASM component (`--features wasm`).
//!
//! A class holds watches; a watch subscribes a point (or a subtree) and judges each sample
//! with its algorithm ([`algo`]); a condition that holds (after `to_alarm_s`) makes a record,
//! one that is gone (after `to_normal_s`) returns it to normal; people acknowledge records
//! and add notes; a record is closed when it is normal and acknowledged. Records live in
//! pages of the host store ([`store`]), the open ones also in memory; every change goes to a
//! journal that sinks ([`sinks`]) read in batches for the history sync links.
//!
//! Bounds: every event buffers at most [`limits::COMMANDS_PER_EVENT`] commands and spends at
//! most [`limits::EVENT_TIME_US`] on batched work; loading the classes at start and a burst of
//! due wakes go on in `0` ms timer events. The tree stays within [`limits::NODE_BUDGET`] nodes.
//!
//! The params (a map, validated in `start`): `retention_days` (365) and `max_records`
//! (100 000): closed records older than the retention, or beyond the maximum, are purged
//! daily by whole pages.

mod actions;
pub mod algo;
pub mod limits;
pub mod model;
mod sinks;
mod store;
mod tree;
mod wake;

use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet, VecDeque};

use wyrm_core::{Quality, Sample, Status, Value};
use wyrm_link_api::{App, AppError, Host, Level, Rights, SubId, TimerId, Who};

use actions::{
    AddClass, AddNote, AddSink, AddWatch, AlarmState, ClassArgs, EditSink, EditWatch, GetAlarms,
    Import, Normal, Purge, Raise, RecordArg, ResetSink, SinkFrom, SinkNext, WatchArgs,
};
use algo::{render, Algorithm, AlgorithmName, Judged};
use limits::{
    Counted, CLOCK_STEP_MS, DEFAULT_BATCH_ROWS, DEFAULT_MAX_RECORDS, DEFAULT_RETENTION_DAYS,
    DEFAULT_ROWS, JOURNAL_PAGE, MAX_BATCH_BYTES, MAX_BATCH_ROWS, MAX_CLASSES, MAX_JOURNAL_PAGES,
    MAX_KEYS_PER_WATCH, MAX_MAX_RECORDS, MAX_MESSAGE_LEN, MAX_NOTES, MAX_NOTE_LEN, MAX_OPEN,
    MAX_PAGES_PER_QUERY, MAX_RETENTION_DAYS, MAX_ROWS, MAX_SINKS, MAX_WATCHES,
    MAX_WATCHES_PER_CLASS, NODE_BUDGET, PAGE, PUBLISH_MS, PURGE_INTERVAL_MS, PURGE_PAGES_PER_RUN,
    STATS_NODES, TABLE_ROWS, WATCHDOG_MS,
};
use model::{
    escalation, inhibit, invalid, parse_instant, parse_source, parse_timerange, record_value,
    stored_u64, valid_id, value_from_json, value_to_json, AlarmType, ClassDef, Map, Note, Record,
    WatchDef,
};
use sinks::{Sink, SinkDef};
use store::Meta;
use tree::WatchShown;
use wake::{Fired, Timer, Wake, Wakes};

pub use model::{CLASS_FORMAT, RECORD_FORMAT};

/// Instants: microseconds since the Unix epoch, UTC.
pub type Micros = i64;

const DAY_US: Micros = 86_400_000_000;
/// Commands a raised record costs at most: its page, `open`, the journal page, `meta`, the
/// watch node and its value, a log line.
const RAISE_COST: usize = 8;
const PUBLISH_COST: usize = 5;
const STATS_COST: usize = STATS_NODES;
const PURGE_COST: usize = PURGE_PAGES_PER_RUN + 4;

fn exhausted(msg: impl Into<String>) -> AppError {
    AppError::new(Status::ResourceExhausted, msg)
}

fn denied(msg: impl Into<String>) -> AppError {
    AppError::new(Status::PermissionDenied, msg)
}

fn not_found(what: impl Into<String>) -> AppError {
    AppError::new(Status::NotFound, what)
}

fn now_of(host: &dyn Host) -> Micros {
    i64::try_from(host.now_us()).unwrap_or(Micros::MAX)
}

fn good(host: &dyn Host, v: Value) -> Sample {
    Sample {
        v,
        q: Quality::Good,
        t: host.now_us(),
    }
}

/// What a record knows of a key with no sample (a staleness deadline, a wait that ended
/// without a kept sample): no value and quality `bad`, never `good` (docs/alarm.md §4
/// "No sample").
fn no_sample() -> (Value, Quality) {
    (Value::Null, Quality::Bad)
}

fn secs_us(s: u64) -> Micros {
    i64::try_from(s.saturating_mul(1_000_000)).unwrap_or(Micros::MAX)
}

fn ms_us(ms: u64) -> Micros {
    i64::try_from(ms.saturating_mul(1_000)).unwrap_or(Micros::MAX)
}

/// The caller's rights for a watch it defines; a token without `auth` (spec 04) is refused.
fn author_rights(who: &Who) -> Result<Rights, AppError> {
    Rights::of(who).ok_or_else(|| {
        denied(
            "the caller's rights are unknown (its token carries no auth): a watch reads with \
             its author's rights",
        )
    })
}

/// A caller whose rights are unknown (its token carries no `auth`, spec 04) reads no record.
fn known_rights(who: &Who) -> Result<(), AppError> {
    if who.authority.is_none() {
        return Err(denied(
            "the caller's rights are unknown (its token carries no auth)",
        ));
    }
    Ok(())
}

/// A reader (or an acknowledger) must be able to read the record's source; a caller whose
/// rights are unknown is refused.
fn reader_may(who: &Who, source: &str) -> Result<(), AppError> {
    known_rights(who)?;
    if !who.may_for(source, wyrm_core::Perm::Read) {
        return Err(denied(""));
    }
    Ok(())
}

fn subject(who: &Who) -> String {
    who.subject.clone().unwrap_or_default()
}

/// The link's params.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct Params {
    retention_days: u64,
    max_records: u64,
}

fn params(config: &Value) -> Result<Params, AppError> {
    let m = match config {
        Value::Map(m) => m.clone(),
        Value::Null => Map::new(),
        _ => return Err(invalid("params", "a map")),
    };
    for k in m.keys() {
        if !matches!(k.as_str(), "retention_days" | "max_records") {
            return Err(invalid(&format!("params.{k}"), "unknown"));
        }
    }
    let retention_days = stored_u64(&m, "retention_days")?.unwrap_or(DEFAULT_RETENTION_DAYS);
    if !(1..=MAX_RETENTION_DAYS).contains(&retention_days) {
        return Err(invalid(
            "params.retention_days",
            format!("1 to {MAX_RETENTION_DAYS}"),
        ));
    }
    let max_records = stored_u64(&m, "max_records")?.unwrap_or(DEFAULT_MAX_RECORDS);
    if !(PAGE..=MAX_MAX_RECORDS).contains(&max_records) {
        return Err(invalid(
            "params.max_records",
            format!("{PAGE} to {MAX_MAX_RECORDS}"),
        ));
    }
    Ok(Params {
        retention_days,
        max_records,
    })
}

/// What a key of a watch waits for.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Due {
    ToAlarm,
    ToNormal,
    Stale,
}

/// The state of one key of a watch.
#[derive(Debug, Default, Clone, PartialEq)]
struct PointState {
    /// The condition holds (the deadband applies).
    in_alarm: bool,
    /// The active record of this key.
    record: Option<u64>,
    due: Option<Due>,
    /// The last sample (its value and quality), for a record made when a wait ends.
    last: Option<(Value, Quality)>,
}

/// A watch while it runs.
#[derive(Default)]
struct WatchRun {
    sub: Option<SubId>,
    keys: HashMap<String, PointState>,
    shown: WatchShown,
}

/// A loaded class.
struct Class {
    def: ClassDef,
    run: BTreeMap<String, WatchRun>,
    /// Its open records.
    open: BTreeSet<u64>,
}

impl Class {
    fn watch_at(&self, id: &str) -> Result<usize, AppError> {
        self.def
            .watches
            .iter()
            .position(|w| w.id == id)
            .ok_or_else(|| not_found(format!("{}/watches/{id}", self.def.id)))
    }

    fn nodes(&self) -> usize {
        tree::nodes_of(self.def.watches.len())
    }
}

/// The link's counters since it started.
#[derive(Debug, Default, Clone, Copy)]
struct Stats {
    raised: u64,
    dropped: u64,
}

/// The app.
pub struct Alarm {
    params: Params,
    /// Every class id of the store, in order; loaded, waiting to load, or unreadable.
    index: Vec<String>,
    classes: HashMap<String, Class>,
    /// Ids to load and declare, in batches.
    pending: VecDeque<String>,
    /// Watches (class, index) to subscribe and show, in batches, after their class.
    pending_watches: VecDeque<(String, usize)>,
    /// Nodes of the tree the app declared (the root and its actions not counted).
    nodes: usize,
    /// Subscription → the class and watch it serves.
    subs: HashMap<SubId, (String, String)>,
    /// The open records.
    open: BTreeMap<u64, Record>,
    meta: Meta,
    next_id: u64,
    /// The journal's newest page and its entries; `next_seq = jpage × 256 + jtail.len()`.
    jpage: u64,
    jtail: Vec<u64>,
    sinks: BTreeMap<String, Sink>,
    stats: Stats,
    /// The stats as last published.
    stats_shown: [u64; STATS_NODES - 1],
    wakes: Wakes,
    timer: Timer,
    /// Wall clock when the batched work going on now began; kept across its `0` ms
    /// continuations, cleared when `arm` sets any other timer.
    drain: Option<Micros>,
}

impl Alarm {
    // ---------- bounds and lookups ----------

    fn check_nodes(&self, add: usize, freed: usize) -> Result<(), AppError> {
        if self.nodes - freed + add > NODE_BUDGET {
            return Err(exhausted(format!(
                "at most {NODE_BUDGET} nodes in the alarm link ({} used)",
                self.nodes
            )));
        }
        Ok(())
    }

    fn class(&self, id: &str) -> Result<&Class, AppError> {
        self.classes.get(id).ok_or_else(|| not_found(id.to_owned()))
    }

    fn class_mut(&mut self, id: &str) -> Result<&mut Class, AppError> {
        self.classes
            .get_mut(id)
            .ok_or_else(|| not_found(id.to_owned()))
    }

    fn watches_total(&self) -> usize {
        self.classes.values().map(|c| c.def.watches.len()).sum()
    }

    /// The number the next journal entry gets: entry `i` of page `n` is `256n + i + 1`, so
    /// `0` is "nothing confirmed".
    fn next_seq(&self) -> u64 {
        self.jpage * JOURNAL_PAGE + self.jtail.len() as u64 + 1
    }

    /// Records on disk (the pages kept).
    fn records_on_disk(&self) -> u64 {
        self.next_id.saturating_sub(self.meta.first_page * PAGE)
    }

    /// A record: open (in memory) or on its page.
    fn record(&self, cx: &dyn Host, id: u64) -> Result<Record, AppError> {
        self.open
            .get(&id)
            .cloned()
            .or_else(|| store::load_record(cx, id))
            .ok_or_else(|| not_found(format!("record {id}")))
    }

    // ---------- the journal and records ----------

    /// One journal entry for record `id`; an entry the store refuses is logged (the record
    /// itself is saved already).
    fn journal(&mut self, cx: &mut Counted, id: u64) {
        if self.jtail.len() as u64 >= JOURNAL_PAGE {
            self.jpage += 1;
            self.jtail.clear();
            self.meta.jpage_hint = self.jpage;
            if let Err(e) = self.meta.save(cx) {
                cx.log(Level::Warn, &format!("meta not saved: {}", e.msg));
            }
        }
        self.jtail.push(id);
        if let Err(e) = store::save_journal_page(cx, self.jpage, &self.jtail) {
            self.jtail.pop();
            cx.log(
                Level::Error,
                &format!("journal entry for record {id} not saved: {}", e.msg),
            );
            return;
        }
        // the oldest journal page goes once the journal is full
        if self.jpage - self.meta.first_jpage >= MAX_JOURNAL_PAGES {
            let gone = self.meta.first_jpage;
            let first_seq = gone * JOURNAL_PAGE + 1;
            let last_seq = first_seq + JOURNAL_PAGE - 1;
            for s in self.sinks.values_mut() {
                if s.def.cursor < last_seq {
                    s.dropped_unsent += last_seq - s.def.cursor.max(first_seq - 1);
                }
            }
            cx.store_delete(&store::journal_key(gone));
            self.meta.first_jpage = gone + 1;
            if let Err(e) = self.meta.save(cx) {
                cx.log(Level::Warn, &format!("meta not saved: {}", e.msg));
            }
        }
    }

    /// Saves a changed or new record: its page, the journal, the open set (and `open` on
    /// disk when it changed), the class's table and the stats.
    fn commit(&mut self, cx: &mut Counted, rec: Record) -> Result<(), AppError> {
        store::save_record(cx, &rec)?;
        let id = rec.id;
        self.journal(cx, id);
        let was_open = self.open.contains_key(&id);
        let open = rec.is_open();
        let class = rec.class.clone();
        let acked = rec.is_acked();
        if open {
            self.open.insert(id, rec);
        } else {
            self.open.remove(&id);
        }
        if let Some(c) = self.classes.get_mut(&class) {
            if open {
                c.open.insert(id);
            } else {
                c.open.remove(&id);
            }
        }
        if was_open != open {
            if let Err(e) = store::save_open_ids(cx, self.open.keys().copied()) {
                cx.log(Level::Error, &format!("open set not saved: {}", e.msg));
            }
        }
        if acked || !open {
            self.wakes.set(Wake::Escalate(id), None);
        }
        self.touch_class(cx, &class);
        self.touch_stats(cx);
        Ok(())
    }

    fn touch_class(&mut self, cx: &dyn Host, class: &str) {
        if self.classes.contains_key(class) {
            let at = now_of(cx).saturating_add(ms_us(PUBLISH_MS));
            self.wakes.set_if_none(Wake::Publish(class.to_owned()), at);
        }
    }

    fn touch_stats(&mut self, cx: &dyn Host) {
        let at = now_of(cx).saturating_add(ms_us(PUBLISH_MS));
        self.wakes.set_if_none(Wake::Stats, at);
    }

    /// Makes a record. Over [`MAX_OPEN`] open records, the oldest one that is normal but
    /// unacknowledged is acknowledged by `system:overflow` first.
    #[allow(
        clippy::too_many_arguments,
        reason = "one argument per field of the new record; called from two places"
    )]
    fn raise(
        &mut self,
        cx: &mut Counted,
        class: &str,
        watch: Option<&str>,
        source: &str,
        ty: AlarmType,
        message: String,
        value: Value,
        by: Option<String>,
        now: Micros,
    ) -> Result<u64, AppError> {
        if self.open.len() >= MAX_OPEN {
            let victim = self
                .open
                .values()
                .find(|r| !r.is_active() && !r.is_acked())
                .map(|r| r.id);
            match victim {
                Some(v) => {
                    let mut r = self.open[&v].clone();
                    r.ack = Some(now);
                    r.ack_by = Some("system:overflow".into());
                    self.commit(cx, r)?;
                    cx.log(
                        Level::Warn,
                        &format!("{MAX_OPEN} open records: record {v} acknowledged by overflow"),
                    );
                }
                None => cx.log(
                    Level::Warn,
                    &format!("{MAX_OPEN} open records, all active: record made anyway"),
                ),
            }
        }
        let id = self.next_id;
        let rec = Record {
            id,
            class: class.to_owned(),
            watch: watch.map(str::to_owned),
            source: source.to_owned(),
            ty,
            message,
            value: record_value(&value),
            created: now,
            normal: None,
            ack: None,
            ack_by: None,
            escalation: 0,
            notes: Vec::new(),
            by,
        };
        let page = store::page_of(id);
        if page > self.meta.page_hint || (id == 0 && !store::page_exists(cx, 0)) {
            let mut m = self.meta;
            m.page_hint = page;
            m.save(cx)?;
            self.meta = m;
        }
        let esc = self
            .classes
            .get(class)
            .map(|c| c.def.escalation1_s)
            .unwrap_or(0);
        match self.commit(cx, rec) {
            Ok(()) => {}
            Err(e) => {
                self.stats.dropped += 1;
                self.touch_stats(cx);
                return Err(e);
            }
        }
        self.next_id = id + 1;
        self.stats.raised += 1;
        if esc > 0 {
            self.wakes
                .set(Wake::Escalate(id), Some(now.saturating_add(secs_us(esc))));
        }
        cx.log(
            Level::Info,
            &format!("record {id} raised in {class} ({})", ty.name()),
        );
        Ok(id)
    }

    fn set_normal(&mut self, cx: &mut Counted, id: u64, now: Micros) -> Result<(), AppError> {
        let Some(mut r) = self.open.get(&id).cloned() else {
            return Err(not_found(format!("open record {id}")));
        };
        if !r.is_active() {
            return Err(invalid("id", format!("record {id} is normal already")));
        }
        r.normal = Some(now);
        self.commit(cx, r)?;
        cx.log(Level::Info, &format!("record {id} normal"));
        Ok(())
    }

    fn acknowledge(
        &mut self,
        cx: &mut Counted,
        id: u64,
        by: String,
        note: Option<String>,
        now: Micros,
    ) -> Result<(), AppError> {
        let Some(mut r) = self.open.get(&id).cloned() else {
            return Err(not_found(format!("open record {id}")));
        };
        if r.is_acked() {
            return Err(invalid(
                "id",
                format!("record {id} is acknowledged already"),
            ));
        }
        r.ack = Some(now);
        r.ack_by = Some(by.clone());
        if let Some(text) = note.filter(|n| !n.trim().is_empty()) {
            push_note(&mut r, now, by, text)?;
        }
        self.commit(cx, r)?;
        cx.log(Level::Info, &format!("record {id} acknowledged"));
        Ok(())
    }

    fn escalate(&mut self, cx: &mut Counted, id: u64, now: Micros) {
        let Some(mut r) = self.open.get(&id).cloned() else {
            return;
        };
        if r.is_acked() {
            return;
        }
        let Some(c) = self.classes.get(&r.class) else {
            return;
        };
        let (e1, e2) = (c.def.escalation1_s, c.def.escalation2_s);
        let next = match r.escalation {
            0 if e1 > 0 => 1,
            1 if e2 > 0 => 2,
            _ => return,
        };
        r.escalation = next;
        if let Err(e) = self.commit(cx, r) {
            cx.log(
                Level::Warn,
                &format!("record {id}: escalation not saved: {}", e.msg),
            );
            return;
        }
        if next == 1 && e2 > 0 {
            let at = self.open[&id].created.saturating_add(secs_us(e2));
            self.wakes.set(Wake::Escalate(id), Some(at.max(now)));
        }
        cx.log(Level::Info, &format!("record {id} escalated to {next}"));
    }

    // ---------- watches ----------

    /// The watch node's value and attributes now.
    fn show_watch(&self, cx: &mut Counted, class: &str, wid: &str) {
        let Some(c) = self.classes.get(class) else {
            return;
        };
        let Ok(i) = c.watch_at(wid) else { return };
        let def = &c.def.watches[i];
        let Some(run) = c.run.get(wid) else { return };
        let state = if !def.enabled {
            "disabled"
        } else if run.shown.error.is_some() {
            "error"
        } else if run
            .keys
            .values()
            .any(|p| p.record.is_some() && p.due != Some(Due::ToNormal))
        {
            "alarm"
        } else if run.keys.values().any(|p| p.due == Some(Due::ToNormal)) {
            "to_normal"
        } else if run.keys.values().any(|p| p.due == Some(Due::ToAlarm)) {
            "to_alarm"
        } else {
            "normal"
        };
        let path = tree::watch(class, wid);
        cx.declare_node(&path, tree::watch_meta(def, &run.shown));
        let s = good(cx, Value::from(state));
        cx.update(&path, s);
    }

    /// Subscribes an enabled watch; a refused subscription is the watch's `error`.
    fn subscribe_watch(&mut self, cx: &mut Counted, class: &str, i: usize, now: Micros) {
        let Some(c) = self.classes.get_mut(class) else {
            return;
        };
        let def = c.def.watches[i].clone();
        let run = c.run.entry(def.id.clone()).or_default();
        if !def.enabled {
            return;
        }
        if def.rights.is_none() {
            run.shown.error = Some("no author rights kept: edit the watch".into());
            return;
        }
        match cx.subscribe(&def.sub_key()) {
            Ok(sub) => {
                run.sub = Some(sub);
                run.shown.error = None;
                self.subs.insert(sub, (class.to_owned(), def.id.clone()));
                // a point known from the start counts from now
                if !def.subtree {
                    if let Some(s) = def.algorithm.stale_s() {
                        self.wakes.set(
                            Wake::Point(class.to_owned(), def.id.clone(), def.source.clone()),
                            Some(now.saturating_add(secs_us(s))),
                        );
                        let p = run.keys.entry(def.source.clone()).or_default();
                        p.due = Some(Due::Stale);
                    }
                }
            }
            Err(e) => run.shown.error = Some(e.msg),
        }
    }

    /// Ends a watch's subscription and its waits; its active records return to normal
    /// (nobody watches them any more).
    fn teardown_watch(&mut self, cx: &mut Counted, class: &str, wid: &str, now: Micros) {
        let Some(c) = self.classes.get_mut(class) else {
            return;
        };
        let Some(run) = c.run.get_mut(wid) else {
            return;
        };
        if let Some(sub) = run.sub.take() {
            cx.unsubscribe(sub);
            self.subs.remove(&sub);
        }
        let keys = std::mem::take(&mut run.keys);
        run.shown.keys = 0;
        run.shown.in_alarm = 0;
        for (key, p) in keys {
            self.wakes
                .set(Wake::Point(class.to_owned(), wid.to_owned(), key), None);
            if let Some(id) = p.record {
                if let Err(e) = self.set_normal(cx, id, now) {
                    cx.log(Level::Warn, &format!("record {id}: not normal: {}", e.msg));
                }
            }
        }
    }

    /// A sample of `key` for a watch.
    fn sample(&mut self, cx: &mut Counted, class: &str, wid: &str, key: &str, s: Sample) {
        let now = now_of(cx);
        let Some(c) = self.classes.get_mut(class) else {
            return;
        };
        let Ok(i) = c.watch_at(wid) else { return };
        let def = c.def.watches[i].clone();
        let Some(run) = c.run.get_mut(wid) else {
            return;
        };
        if def.subtree {
            if !def
                .rights
                .as_ref()
                .is_some_and(|r| r.may(key, wyrm_core::Perm::Read))
            {
                return;
            }
            if !run.keys.contains_key(key) && run.keys.len() >= MAX_KEYS_PER_WATCH {
                if run.shown.error.is_none() {
                    run.shown.error = Some(format!("more than {MAX_KEYS_PER_WATCH} keys"));
                    self.show_watch(cx, class, wid);
                }
                return;
            }
        } else if key != def.source {
            return;
        }
        let p = run.keys.entry(key.to_owned()).or_default();
        p.last = Some((record_value(&s.v), s.q));
        let judged = def.algorithm.judge(&s, p.in_alarm);
        let wake = Wake::Point(class.to_owned(), wid.to_owned(), key.to_owned());
        let mut changed = false;
        if let Some(stale) = def.algorithm.stale_s() {
            // a sample ends staleness and starts the next deadline
            if p.in_alarm {
                p.in_alarm = false;
                changed = true;
                if let Some(id) = p.record.take() {
                    if let Err(e) = self.set_normal(cx, id, now) {
                        cx.log(Level::Warn, &format!("record {id}: {}", e.msg));
                    }
                }
            }
            if let Some(p) = self
                .classes
                .get_mut(class)
                .and_then(|c| c.run.get_mut(wid))
                .and_then(|r| r.keys.get_mut(key))
            {
                p.due = Some(Due::Stale);
            }
            self.wakes
                .set(wake, Some(now.saturating_add(secs_us(stale))));
            if changed {
                self.recount(class, wid);
                self.show_watch(cx, class, wid);
            }
            return;
        }
        match judged {
            Judged::Same => return,
            Judged::Alarm => {
                p.in_alarm = true;
                if p.record.is_none() {
                    if p.due == Some(Due::ToAlarm) {
                        return;
                    }
                    if def.to_alarm_s > 0 {
                        p.due = Some(Due::ToAlarm);
                        self.wakes
                            .set(wake, Some(now.saturating_add(secs_us(def.to_alarm_s))));
                        changed = true;
                    } else {
                        p.due = None;
                        self.wakes.set(wake, None);
                        self.make_record(cx, class, wid, key, &def, &s, now);
                        changed = true;
                    }
                } else if p.due == Some(Due::ToNormal) {
                    p.due = None;
                    self.wakes.set(wake, None);
                    changed = true;
                }
            }
            Judged::Normal => {
                p.in_alarm = false;
                if let Some(id) = p.record {
                    if p.due == Some(Due::ToNormal) {
                        return;
                    }
                    if def.to_normal_s > 0 {
                        p.due = Some(Due::ToNormal);
                        self.wakes
                            .set(wake, Some(now.saturating_add(secs_us(def.to_normal_s))));
                    } else {
                        p.record = None;
                        p.due = None;
                        self.wakes.set(wake, None);
                        if let Err(e) = self.set_normal(cx, id, now) {
                            cx.log(Level::Warn, &format!("record {id}: {}", e.msg));
                        }
                    }
                    changed = true;
                } else if p.due == Some(Due::ToAlarm) {
                    p.due = None;
                    self.wakes.set(wake, None);
                    changed = true;
                }
            }
        }
        if changed {
            self.recount(class, wid);
            self.show_watch(cx, class, wid);
        }
    }

    /// A record for `key` of a watch from sample `s`.
    #[allow(
        clippy::too_many_arguments,
        reason = "one argument per field of the new record and its watch"
    )]
    fn make_record(
        &mut self,
        cx: &mut Counted,
        class: &str,
        wid: &str,
        key: &str,
        def: &WatchDef,
        s: &Sample,
        now: Micros,
    ) {
        let message = render(&def.message, key, &s.v, s.q, class, wid, &def.algorithm);
        match self.raise(
            cx,
            class,
            Some(wid),
            key,
            def.ty,
            message,
            s.v.clone(),
            None,
            now,
        ) {
            Ok(id) => {
                if let Some(p) = self
                    .classes
                    .get_mut(class)
                    .and_then(|c| c.run.get_mut(wid))
                    .and_then(|r| r.keys.get_mut(key))
                {
                    p.record = Some(id);
                }
                if let Some(r) = self.classes.get_mut(class).and_then(|c| c.run.get_mut(wid)) {
                    r.shown.last_record = Some(id);
                    r.shown.last_change = Some(now);
                }
            }
            Err(e) => cx.log(
                Level::Error,
                &format!("{class}/{wid}: record not saved: {}", e.msg),
            ),
        }
    }

    /// The counts a watch shows.
    fn recount(&mut self, class: &str, wid: &str) {
        if let Some(r) = self.classes.get_mut(class).and_then(|c| c.run.get_mut(wid)) {
            r.shown.keys = r.keys.len();
            r.shown.in_alarm = r.keys.values().filter(|p| p.record.is_some()).count();
        }
    }

    /// A key's wait ended: the inhibit, or the staleness deadline.
    fn point_due(&mut self, cx: &mut Counted, class: &str, wid: &str, key: &str, now: Micros) {
        let Some(c) = self.classes.get_mut(class) else {
            return;
        };
        let Ok(i) = c.watch_at(wid) else { return };
        let def = c.def.watches[i].clone();
        let Some(run) = c.run.get_mut(wid) else {
            return;
        };
        let Some(p) = run.keys.get_mut(key) else {
            return;
        };
        let Some(due) = p.due.take() else { return };
        match due {
            Due::ToAlarm if p.in_alarm && p.record.is_none() => {
                let (v, q) = p.last.clone().unwrap_or_else(no_sample);
                let s = Sample {
                    v,
                    q,
                    t: cx.now_us(),
                };
                self.make_record(cx, class, wid, key, &def, &s, now);
            }
            Due::ToNormal if !p.in_alarm => {
                if let Some(id) = p.record.take() {
                    if let Err(e) = self.set_normal(cx, id, now) {
                        cx.log(Level::Warn, &format!("record {id}: {}", e.msg));
                    }
                }
            }
            Due::Stale if p.record.is_none() => {
                p.in_alarm = true;
                // the record says that no sample came: nothing fresh is known of the key
                let (v, q) = no_sample();
                let s = Sample {
                    v,
                    q,
                    t: cx.now_us(),
                };
                self.make_record(cx, class, wid, key, &def, &s, now);
            }
            _ => {}
        }
        self.recount(class, wid);
        self.show_watch(cx, class, wid);
    }

    // ---------- classes in the tree ----------

    /// Declares a class's nodes and starts its watches. An open active record of a watch's key
    /// makes that key start as "record open", so its first normal sample closes it.
    fn declare(&mut self, cx: &mut Counted, def: ClassDef, now: Micros) {
        let id = def.id.clone();
        cx.declare_node(&id, tree::class_meta(&def));
        cx.declare_node(
            &tree::open(&id),
            tree::count_meta("Open", "Records active or unacknowledged."),
        );
        cx.declare_node(
            &tree::active(&id),
            tree::count_meta("Active", "Records not yet normal."),
        );
        cx.declare_node(
            &tree::unacked(&id),
            tree::count_meta("Unacknowledged", "Records nobody acknowledged."),
        );
        cx.declare_node(&tree::alarms(&id), tree::alarms_meta());
        cx.declare_node(&tree::watches(&id), tree::watches_meta());
        self.nodes += tree::nodes_of(def.watches.len());
        let open: BTreeSet<u64> = self
            .open
            .values()
            .filter(|r| r.class == id)
            .map(|r| r.id)
            .collect();
        let mut run = BTreeMap::new();
        for w in &def.watches {
            let mut r = WatchRun::default();
            for rec in self.open.values() {
                if rec.class == id && rec.watch.as_deref() == Some(&w.id) && rec.is_active() {
                    let p = r.keys.entry(rec.source.clone()).or_default();
                    p.in_alarm = true;
                    p.record = Some(rec.id);
                    r.shown.last_record = Some(r.shown.last_record.unwrap_or(0).max(rec.id));
                }
            }
            r.shown.keys = r.keys.len();
            r.shown.in_alarm = r.keys.len();
            run.insert(w.id.clone(), r);
        }
        let n = def.watches.len();
        self.classes.insert(id.clone(), Class { def, run, open });
        // the watches follow in batches (a class may hold 500)
        self.pending_watches.extend((0..n).map(|i| (id.clone(), i)));
        self.publish_class(cx, &id);
        let _ = now;
    }

    /// Subscribes and shows the first watch waiting; `false` when the event has no room.
    fn declare_next_watch(&mut self, cx: &mut Counted, now: Micros) -> bool {
        let Some((cid, i)) = self.pending_watches.front().cloned() else {
            return true;
        };
        if !cx.room(tree::WATCH_COST) {
            return false;
        }
        self.pending_watches.pop_front();
        let Some(wid) = self
            .classes
            .get(&cid)
            .and_then(|c| c.def.watches.get(i))
            .map(|w| w.id.clone())
        else {
            return true;
        };
        self.subscribe_watch(cx, &cid, i, now);
        self.show_watch(cx, &cid, &wid);
        true
    }

    /// A class's counts and its table.
    fn publish_class(&mut self, cx: &mut Counted, id: &str) {
        let Some(c) = self.classes.get(id) else {
            return;
        };
        let records: Vec<&Record> = c
            .open
            .iter()
            .rev()
            .filter_map(|i| self.open.get(i))
            .collect();
        let active = records.iter().filter(|r| r.is_active()).count();
        let unacked = records.iter().filter(|r| !r.is_acked()).count();
        let table = Value::Array(
            records
                .iter()
                .take(TABLE_ROWS)
                .map(|r| r.to_row())
                .collect(),
        );
        for (path, n) in [
            (tree::open(id), records.len()),
            (tree::active(id), active),
            (tree::unacked(id), unacked),
        ] {
            let s = good(cx, Value::UInt(n as u64));
            cx.update(&path, s);
        }
        let s = good(cx, table);
        cx.update(&tree::alarms(id), s);
    }

    fn publish_stats(&mut self, cx: &mut Counted) {
        let now = [
            self.open.len() as u64,
            self.open.values().filter(|r| r.is_active()).count() as u64,
            self.open.values().filter(|r| !r.is_acked()).count() as u64,
            self.records_on_disk(),
            self.watches_total() as u64,
            self.stats.raised,
            self.stats.dropped,
        ];
        for (i, name) in tree::stat_names().iter().enumerate() {
            if self.stats_shown[i] != now[i] {
                let s = good(cx, Value::UInt(now[i]));
                cx.update(&tree::stat(name), s);
                self.stats_shown[i] = now[i];
            }
        }
    }

    fn show_sink(&self, cx: &mut Counted, name: &str) {
        if let Some(s) = self.sinks.get(name) {
            let lag = (self.next_seq() - 1).saturating_sub(s.def.cursor);
            let path = tree::sink(name);
            cx.declare_node(&path, tree::sink_meta(s, lag));
            let v = good(cx, Value::UInt(s.def.cursor));
            cx.update(&path, v);
        }
    }

    /// Loads and declares the first class waiting; `false` when the event has no room for it.
    fn load_next(&mut self, cx: &mut Counted, now: Micros) -> bool {
        let Some(id) = self.pending.front().cloned() else {
            return true;
        };
        let def = match store::load_class(cx, &id) {
            Ok(d) => d,
            Err(e) => {
                self.pending.pop_front();
                cx.log(Level::Warn, &format!("class {id}: not loaded: {e}"));
                return true;
            }
        };
        if !cx.room(tree::declare_cost()) {
            return false;
        }
        self.pending.pop_front();
        if let Err(e) = self.check_nodes(tree::nodes_of(def.watches.len()), 0) {
            cx.log(Level::Warn, &format!("class {id}: not loaded: {}", e.msg));
            return true;
        }
        self.declare(cx, def, now);
        if self.pending.is_empty() {
            let n = self.classes.len();
            cx.log(Level::Info, &format!("{n} classes loaded"));
        }
        true
    }

    // ---------- the wake loop ----------

    fn wake_cost(&self, w: &Wake) -> usize {
        match w {
            Wake::Point(..) => RAISE_COST,
            Wake::Escalate(_) => 4,
            Wake::Publish(_) => PUBLISH_COST,
            Wake::Stats => STATS_COST,
            Wake::Purge => PURGE_COST,
        }
    }

    fn fire(&mut self, cx: &mut Counted, wake: Wake, now: Micros) {
        match wake {
            Wake::Point(c, w, k) => self.point_due(cx, &c, &w, &k, now),
            Wake::Escalate(id) => self.escalate(cx, id, now),
            Wake::Publish(c) => self.publish_class(cx, &c),
            Wake::Stats => self.publish_stats(cx),
            Wake::Purge => {
                self.purge_pages(cx, None, now);
                self.wakes.set(
                    Wake::Purge,
                    Some(now.saturating_add(ms_us(PURGE_INTERVAL_MS))),
                );
            }
        }
    }

    /// Batched work, within the event's command and time budget: classes to load, then due
    /// wakes. What is left waits for a `0` ms timer.
    fn run(&mut self, cx: &mut Counted) {
        let now = now_of(cx);
        self.drain.get_or_insert(now);
        loop {
            if !self.pending.is_empty() {
                if !cx.room(tree::declare_cost()) || !self.load_next(cx, now) {
                    return;
                }
                continue;
            }
            if !self.pending_watches.is_empty() {
                if !self.declare_next_watch(cx, now) {
                    return;
                }
                continue;
            }
            match self.wakes.peek_due(now) {
                Some(w) if cx.room(self.wake_cost(&w)) => {}
                _ => return,
            }
            if let Some((_, wake)) = self.wakes.pop_due(now) {
                self.fire(cx, wake, now);
            }
        }
    }

    /// Arms the one host timer: `0` ms while batched work waits, else for the earliest wake
    /// (the daily purge keeps one live, so the watchdog runs).
    fn arm(&mut self, cx: &mut Counted) {
        let now = now_of(cx);
        let next = if !self.pending.is_empty()
            || !self.pending_watches.is_empty()
            || self.wakes.peek_due(now).is_some()
        {
            Some(now)
        } else {
            self.wakes
                .earliest()
                .or_else(|| Some(now.saturating_add(ms_us(WATCHDOG_MS))))
        };
        if next.is_some_and(|t| t <= now) {
            self.drain.get_or_insert(now);
        } else {
            self.drain = None;
        }
        if let Err(e) = self.timer.arm(cx, now, next) {
            cx.log(Level::Error, &format!("{}", wake::no_timer(e)));
        }
    }

    /// An event saw the wall clock step back: the wakes move with it.
    fn check_clock(&mut self, cx: &mut Counted) {
        if let Some(off) = self.timer.observe(now_of(cx)) {
            self.clock_step(cx, off);
        }
    }

    /// The wall clock stepped by `off` (exact from a timer; from another event, measured
    /// against the last event's clock, so late by the time since it, at most the watchdog).
    /// The armed timer is dropped so its firing does not apply the step again.
    fn clock_step(&mut self, cx: &mut Counted, off: Micros) {
        self.wakes.shift(off);
        self.timer.reset(cx);
        self.drain = Some(now_of(cx));
        cx.log(
            Level::Info,
            &format!(
                "wall clock stepped by {} ms: {} wakes moved with it",
                off / 1000,
                self.wakes.len()
            ),
        );
    }

    // ---------- purge ----------

    /// Deletes the oldest pages whose records are all closed while they are older than the
    /// retention (or `before`) or the store holds more than `max_records`; at most
    /// [`PURGE_PAGES_PER_RUN`] pages per run.
    fn purge_pages(&mut self, cx: &mut Counted, before: Option<Micros>, now: Micros) -> usize {
        let cutoff = before.unwrap_or_else(|| {
            now.saturating_sub((self.params.retention_days as Micros).saturating_mul(DAY_US))
        });
        let mut gone = 0;
        while gone < PURGE_PAGES_PER_RUN {
            let n = self.meta.first_page;
            if n * PAGE >= self.next_id {
                break;
            }
            let page = store::load_page(cx, n);
            let old = page.iter().all(|r| r.created < cutoff);
            let over = before.is_none() && self.records_on_disk() > self.params.max_records;
            if !(old || over) || page.iter().any(|r| r.is_open()) {
                break;
            }
            cx.store_delete(&store::page_key(n));
            self.meta.first_page = n + 1;
            if self.meta.page_hint < self.meta.first_page {
                self.meta.page_hint = self.meta.first_page;
            }
            gone += 1;
        }
        if gone > 0 {
            if let Err(e) = self.meta.save(cx) {
                cx.log(Level::Warn, &format!("meta not saved: {}", e.msg));
            }
            self.touch_stats(cx);
            cx.log(Level::Info, &format!("{gone} pages of records purged"));
        }
        gone
    }

    // ---------- actions: classes ----------

    fn add_class(
        &mut self,
        cx: &mut Counted,
        a: AddClass,
        who: &Who,
        now: Micros,
    ) -> Result<Value, AppError> {
        let id = a.id;
        valid_id(&id)?;
        if self.index.contains(&id) {
            return Err(invalid("id", format!("{id} exists")));
        }
        if self.index.len() >= MAX_CLASSES {
            return Err(exhausted(format!("at most {MAX_CLASSES} classes")));
        }
        let def = ClassDef {
            display: a.class.display.unwrap_or_else(|| id.clone()),
            escalation1_s: escalation("escalation1_s", a.class.escalation1_s)?.unwrap_or(0),
            escalation2_s: escalation("escalation2_s", a.class.escalation2_s)?.unwrap_or(0),
            created_by: subject(who),
            id,
            watches: Vec::new(),
            next_watch: 1,
        };
        def.validate()?;
        self.add_new(cx, def, now)?;
        Ok(Value::Null)
    }

    fn add_new(&mut self, cx: &mut Counted, def: ClassDef, now: Micros) -> Result<(), AppError> {
        self.check_nodes(tree::nodes_of(def.watches.len()), 0)?;
        let mut ids = self.index.clone();
        ids.push(def.id.clone());
        store::add_class(cx, &def, &ids)?;
        self.index = ids;
        self.declare(cx, def, now);
        self.run(cx);
        self.touch_stats(cx);
        Ok(())
    }

    fn save_class(&mut self, cx: &mut Counted, def: ClassDef) -> Result<(), AppError> {
        store::replace_class(cx, &def)?;
        if let Some(c) = self.classes.get_mut(&def.id) {
            c.def = def;
        }
        Ok(())
    }

    fn edit_class(&mut self, cx: &mut Counted, cid: &str, a: ClassArgs) -> Result<Value, AppError> {
        let mut def = self.class(cid)?.def.clone();
        if let Some(d) = a.display {
            def.display = d;
        }
        if let Some(e) = escalation("escalation1_s", a.escalation1_s)? {
            def.escalation1_s = e;
        }
        if let Some(e) = escalation("escalation2_s", a.escalation2_s)? {
            def.escalation2_s = e;
        }
        def.validate()?;
        self.save_class(cx, def.clone())?;
        cx.declare_node(cid, tree::class_meta(&def));
        Ok(Value::Null)
    }

    /// Refused while the class has watches (they are configuration) or open records.
    fn remove_class(&mut self, cx: &mut Counted, cid: &str) -> Result<Value, AppError> {
        let c = self.class(cid)?;
        if !c.def.watches.is_empty() {
            return Err(invalid(
                "id",
                format!(
                    "{cid} has {} watches: remove its watches first",
                    c.def.watches.len()
                ),
            ));
        }
        if !c.open.is_empty() {
            return Err(invalid(
                "id",
                format!(
                    "{cid} has {} open records: acknowledge and close them first",
                    c.open.len()
                ),
            ));
        }
        let n = c.nodes();
        let ids: Vec<String> = self.index.iter().filter(|i| *i != cid).cloned().collect();
        store::remove_class(cx, cid, &ids)?;
        self.index = ids;
        self.classes.remove(cid);
        self.nodes -= n;
        self.wakes.set(Wake::Publish(cid.to_owned()), None);
        cx.remove_node(cid);
        self.touch_stats(cx);
        Ok(Value::Null)
    }

    fn export(&self, cid: &str) -> Result<Value, AppError> {
        let c = self.class(cid)?;
        let json = value_to_json(&c.def.to_value(false)).to_string();
        Ok(Value::Map(Map::from([(
            "json".to_owned(),
            Value::Str(json),
        )])))
    }

    /// Every class of the store is loaded and declared: an import waits for it.
    fn loaded(&self) -> Result<(), AppError> {
        if !self.pending.is_empty() || !self.pending_watches.is_empty() {
            return Err(AppError::new(Status::Busy, "classes are still loading"));
        }
        Ok(())
    }

    /// A class's export, with the importer's rights on its watches.
    fn import(
        &mut self,
        cx: &mut Counted,
        a: Import,
        who: &Who,
        now: Micros,
    ) -> Result<Value, AppError> {
        self.loaded()?;
        let overwrite = a.overwrite;
        let parsed: serde_json::Value = serde_json::from_str(&a.json)
            .map_err(|e| invalid("json", format!("not valid JSON: {e}")))?;
        let mut def = ClassDef::from_value(&value_from_json(&parsed))?;
        def.validate()?;
        if def.watches.len() > MAX_WATCHES_PER_CLASS {
            return Err(exhausted(format!(
                "at most {MAX_WATCHES_PER_CLASS} watches per class"
            )));
        }
        let by = subject(who);
        if !def.watches.is_empty() {
            let rights = author_rights(who)?;
            for w in &mut def.watches {
                if !rights.may(&w.sub_key(), wyrm_core::Perm::Read) {
                    return Err(denied(format!(
                        "{}: outside the rights of the importer",
                        w.sub_key()
                    )));
                }
                w.rights = Some(rights.clone());
                w.created_by = by.clone();
            }
        }
        def.created_by = by;
        let id = def.id.clone();
        let replacing = self.index.contains(&id);
        if replacing && !overwrite {
            return Err(invalid(
                "id",
                format!("{id} exists (overwrite: true replaces it)"),
            ));
        }
        let old_nodes = self.classes.get(&id).map_or(0, Class::nodes);
        let old_watches = self.classes.get(&id).map_or(0, |c| c.def.watches.len());
        self.check_nodes(tree::nodes_of(def.watches.len()), old_nodes)?;
        if self.watches_total() - old_watches + def.watches.len() > MAX_WATCHES {
            return Err(exhausted(format!("at most {MAX_WATCHES} watches")));
        }
        if replacing {
            // the old watches go with their waits; the open records stay
            if let Some(c) = self.classes.get(&id) {
                let wids: Vec<String> = c.def.watches.iter().map(|w| w.id.clone()).collect();
                for w in wids {
                    self.teardown_watch(cx, &id, &w, now);
                }
            }
            store::replace_class(cx, &def)?;
            if self.classes.remove(&id).is_some() {
                cx.remove_node(&id);
                self.nodes -= old_nodes;
            }
            self.declare(cx, def, now);
            self.run(cx);
        } else {
            if self.index.len() >= MAX_CLASSES {
                return Err(exhausted(format!("at most {MAX_CLASSES} classes")));
            }
            self.add_new(cx, def, now)?;
        }
        Ok(Value::Map(Map::from([("id".to_owned(), Value::Str(id))])))
    }

    // ---------- actions: watches ----------

    /// A watch from the arguments of `add_watch` (`base` none) or of a watch's `edit` over
    /// `base`: `source` and `algorithm` are there for a new watch, and an edit keeps what it
    /// does not give.
    fn watch_from(
        &self,
        id: String,
        source: Option<String>,
        algorithm: Option<AlgorithmName>,
        a: WatchArgs,
        base: Option<&WatchDef>,
        who: &Who,
    ) -> Result<WatchDef, AppError> {
        let new_source = source.is_some();
        let (source, subtree) = match source {
            Some(s) => parse_source(&s)?,
            None => match base {
                Some(b) => (b.source.clone(), b.subtree),
                None => return Err(invalid("source", "required")),
            },
        };
        let kind = match algorithm {
            Some(k) => k,
            None => match base {
                Some(b) => b.algorithm.kind(),
                None => return Err(invalid("algorithm", "required")),
            },
        };
        let algorithm = Algorithm::build(kind, &a.algorithm, base.map(|b| &b.algorithm))?;
        let message = match a.message {
            Some(t) if t.trim().is_empty() => algorithm.default_message().to_owned(),
            Some(t) => t,
            None => match base {
                Some(b) if b.algorithm.kind() == kind => b.message.clone(),
                _ => algorithm.default_message().to_owned(),
            },
        };
        if message.len() > MAX_MESSAGE_LEN {
            return Err(invalid(
                "message",
                format!("at most {MAX_MESSAGE_LEN} bytes"),
            ));
        }
        let rights = match base {
            // an edit keeps the author's rights unless the source changes
            Some(b) if !new_source && b.rights.is_some() => b.rights.clone(),
            _ => Some(author_rights(who)?),
        };
        // a subtree is checked as its pattern: the author may read some of it (the keys they
        // may not read are dropped sample by sample)
        let pattern = if subtree {
            format!("{source}/**")
        } else {
            source.clone()
        };
        if !rights
            .as_ref()
            .is_some_and(|r| r.may(&pattern, wyrm_core::Perm::Read))
        {
            return Err(denied(format!(
                "{pattern}: outside the rights of the watch's author"
            )));
        }
        Ok(WatchDef {
            id,
            source,
            subtree,
            algorithm,
            ty: a.ty.or(base.map(|b| b.ty)).unwrap_or(AlarmType::Alert),
            message,
            to_alarm_s: inhibit("to_alarm_s", a.to_alarm_s)?
                .unwrap_or(base.map_or(0, |b| b.to_alarm_s)),
            to_normal_s: inhibit("to_normal_s", a.to_normal_s)?
                .unwrap_or(base.map_or(0, |b| b.to_normal_s)),
            enabled: a.enabled.unwrap_or(base.is_none_or(|b| b.enabled)),
            created_by: base.map_or_else(|| subject(who), |b| b.created_by.clone()),
            rights,
        })
    }

    /// The class `cid` is there and one more watch fits: in the class, in the link and in
    /// the tree.
    fn room_for_watch(&self, cid: &str) -> Result<(), AppError> {
        if self.class(cid)?.def.watches.len() >= MAX_WATCHES_PER_CLASS {
            return Err(exhausted(format!(
                "at most {MAX_WATCHES_PER_CLASS} watches per class"
            )));
        }
        if self.watches_total() >= MAX_WATCHES {
            return Err(exhausted(format!("at most {MAX_WATCHES} watches")));
        }
        self.check_nodes(1, 0)
    }

    fn add_watch(
        &mut self,
        cx: &mut Counted,
        cid: &str,
        a: AddWatch,
        who: &Who,
        now: Micros,
    ) -> Result<Value, AppError> {
        self.room_for_watch(cid)?;
        let mut def = self.class(cid)?.def.clone();
        let wid = format!("w{}", def.next_watch);
        let w = self.watch_from(
            wid.clone(),
            Some(a.source),
            Some(a.algorithm),
            a.watch,
            None,
            who,
        )?;
        def.watches.push(w);
        def.next_watch = def.next_watch.saturating_add(1);
        self.save_class(cx, def)?;
        self.nodes += 1;
        let i = self.classes[cid].def.watches.len() - 1;
        self.class_mut(cid)?
            .run
            .insert(wid.clone(), WatchRun::default());
        self.subscribe_watch(cx, cid, i, now);
        self.show_watch(cx, cid, &wid);
        self.touch_stats(cx);
        Ok(Value::Map(Map::from([("id".to_owned(), Value::Str(wid))])))
    }

    fn edit_watch(
        &mut self,
        cx: &mut Counted,
        cid: &str,
        wid: &str,
        a: EditWatch,
        who: &Who,
        now: Micros,
    ) -> Result<Value, AppError> {
        let i = self.class(cid)?.watch_at(wid)?;
        let mut def = self.class(cid)?.def.clone();
        let old = def.watches[i].clone();
        let new = self.watch_from(
            wid.to_owned(),
            a.source,
            a.algorithm,
            a.watch,
            Some(&old),
            who,
        )?;
        let resubscribe =
            new.source != old.source || new.subtree != old.subtree || new.enabled != old.enabled;
        def.watches[i] = new;
        self.save_class(cx, def)?;
        if resubscribe {
            self.teardown_watch(cx, cid, wid, now);
            self.subscribe_watch(cx, cid, i, now);
        } else {
            // a changed algorithm judges the next sample anew; waits start over
            let keys: Vec<String> = self.classes[cid].run[wid].keys.keys().cloned().collect();
            for k in keys {
                self.wakes
                    .set(Wake::Point(cid.to_owned(), wid.to_owned(), k.clone()), None);
                if let Some(p) = self
                    .classes
                    .get_mut(cid)
                    .and_then(|c| c.run.get_mut(wid))
                    .and_then(|r| r.keys.get_mut(&k))
                {
                    p.due = None;
                }
            }
            if let Some(s) = self.classes[cid].def.watches[i].algorithm.stale_s() {
                let keys: Vec<String> = self.classes[cid].run[wid].keys.keys().cloned().collect();
                for k in keys {
                    self.wakes.set(
                        Wake::Point(cid.to_owned(), wid.to_owned(), k),
                        Some(now.saturating_add(secs_us(s))),
                    );
                }
            }
        }
        self.recount(cid, wid);
        self.show_watch(cx, cid, wid);
        Ok(Value::Null)
    }

    fn enable_watch(
        &mut self,
        cx: &mut Counted,
        cid: &str,
        wid: &str,
        on: bool,
        now: Micros,
    ) -> Result<Value, AppError> {
        let i = self.class(cid)?.watch_at(wid)?;
        let mut def = self.class(cid)?.def.clone();
        if def.watches[i].enabled == on {
            return Ok(Value::Null);
        }
        def.watches[i].enabled = on;
        self.save_class(cx, def)?;
        self.teardown_watch(cx, cid, wid, now);
        if on {
            self.subscribe_watch(cx, cid, i, now);
        }
        self.recount(cid, wid);
        self.show_watch(cx, cid, wid);
        Ok(Value::Null)
    }

    fn remove_watch(
        &mut self,
        cx: &mut Counted,
        cid: &str,
        wid: &str,
        now: Micros,
    ) -> Result<Value, AppError> {
        let i = self.class(cid)?.watch_at(wid)?;
        let mut def = self.class(cid)?.def.clone();
        def.watches.remove(i);
        self.save_class(cx, def)?;
        self.teardown_watch(cx, cid, wid, now);
        self.class_mut(cid)?.run.remove(wid);
        cx.remove_node(&tree::watch(cid, wid));
        self.nodes -= 1;
        self.touch_stats(cx);
        Ok(Value::Null)
    }

    // ---------- actions: records ----------

    fn raise_action(
        &mut self,
        cx: &mut Counted,
        a: Raise,
        who: &Who,
        now: Micros,
    ) -> Result<Value, AppError> {
        let class = a.class;
        self.class(&class)?;
        let (source, subtree) = parse_source(&a.source)?;
        if subtree {
            return Err(invalid("source", "one key, not a subtree"));
        }
        let ty = a.ty.unwrap_or(AlarmType::Alert);
        let message = a
            .message
            .unwrap_or_else(|| source.rsplit('/').next().unwrap_or(&source).to_owned());
        if message.len() > MAX_MESSAGE_LEN {
            return Err(invalid(
                "message",
                format!("at most {MAX_MESSAGE_LEN} bytes"),
            ));
        }
        let id = self.raise(
            cx,
            &class,
            None,
            &source,
            ty,
            message,
            Value::Null,
            Some(subject(who)),
            now,
        )?;
        Ok(Value::Map(Map::from([("id".to_owned(), Value::UInt(id))])))
    }

    /// A record's `id` (a `dynamic` argument): a number, or its decimal text (a scenario or
    /// a CLI passes text). A `null` is no id.
    fn record_id(id: &Value) -> Result<u64, AppError> {
        match id {
            Value::Null => Err(invalid("id", "required")),
            Value::Str(s) => s
                .trim()
                .parse()
                .ok()
                .ok_or_else(|| invalid("id", "a record id")),
            number => number
                .to_int()
                .ok()
                .ok_or_else(|| invalid("id", "must be a whole number from 0")),
        }
    }

    fn acknowledge_action(
        &mut self,
        cx: &mut Counted,
        a: actions::Acknowledge,
        who: &Who,
        now: Micros,
    ) -> Result<Value, AppError> {
        let id = Self::record_id(&a.id)?;
        let r = self.record(cx, id)?;
        reader_may(who, &r.source)?;
        self.acknowledge(cx, id, subject(who), a.note, now)?;
        Ok(Value::Null)
    }

    /// Returns a record made with `raise` to normal (a watch's record follows its point).
    fn normal_action(
        &mut self,
        cx: &mut Counted,
        a: Normal,
        who: &Who,
        now: Micros,
    ) -> Result<Value, AppError> {
        let id = Self::record_id(&a.id)?;
        let r = self.record(cx, id)?;
        reader_may(who, &r.source)?;
        if r.watch.is_some() {
            return Err(invalid(
                "id",
                format!("record {id} belongs to a watch: its point decides"),
            ));
        }
        self.set_normal(cx, id, now)?;
        Ok(Value::Null)
    }

    fn add_note_action(
        &mut self,
        cx: &mut Counted,
        a: AddNote,
        who: &Who,
        now: Micros,
    ) -> Result<Value, AppError> {
        let id = Self::record_id(&a.id)?;
        let text = a.note;
        if text.trim().is_empty() {
            return Err(invalid("note", "required"));
        }
        let mut r = self.record(cx, id)?;
        reader_may(who, &r.source)?;
        push_note(&mut r, now, subject(who), text)?;
        self.commit(cx, r)?;
        Ok(Value::Null)
    }

    fn ack_all(
        &mut self,
        cx: &mut Counted,
        class: Option<&str>,
        who: &Who,
        now: Micros,
    ) -> Result<Value, AppError> {
        if let Some(c) = class {
            self.class(c)?;
        }
        known_rights(who)?;
        let ids: Vec<u64> = self
            .open
            .values()
            .filter(|r| !r.is_acked())
            .filter(|r| class.is_none_or(|c| r.class == c))
            .filter(|r| who.may_for(&r.source, wyrm_core::Perm::Read))
            .map(|r| r.id)
            .collect();
        let by = subject(who);
        let mut n = 0u64;
        for id in ids {
            if !cx.room(6) {
                break;
            }
            if self.acknowledge(cx, id, by.clone(), None, now).is_ok() {
                n += 1;
            }
        }
        Ok(Value::Map(Map::from([(
            "acknowledged".to_owned(),
            Value::UInt(n),
        )])))
    }

    fn get_alarm(&self, cx: &dyn Host, a: RecordArg, who: &Who) -> Result<Value, AppError> {
        let r = self.record(cx, Self::record_id(&a.id)?)?;
        reader_may(who, &r.source)?;
        Ok(r.to_value(true))
    }

    fn get_notes(&self, cx: &dyn Host, a: RecordArg, who: &Who) -> Result<Value, AppError> {
        let r = self.record(cx, Self::record_id(&a.id)?)?;
        reader_may(who, &r.source)?;
        let Value::Map(mut v) = r.to_value(true) else {
            return Ok(Value::Array(Vec::new()));
        };
        Ok(v.remove("notes").unwrap_or(Value::Array(Vec::new())))
    }

    /// The first record's creation time of page `n` (a page holds its records by id).
    fn page_first_created(cx: &dyn Host, n: u64) -> Option<Micros> {
        store::load_page(cx, n).first().map(|r| r.created)
    }

    fn get_alarms(&self, cx: &dyn Host, a: GetAlarms, who: &Who) -> Result<Value, AppError> {
        known_rights(who)?;
        let range = a
            .timerange
            .filter(|t| !t.trim().is_empty())
            .map(|t| parse_timerange(&t))
            .transpose()?;
        let class = a.class.filter(|c| !c.is_empty());
        let source = a.source.filter(|s| !s.is_empty());
        let state = a.state.unwrap_or(AlarmState::Open);
        let ty = a.ty;
        let limit = match a.limit {
            None => DEFAULT_ROWS,
            Some(n) if (1..=MAX_ROWS as u64).contains(&n) => n as usize,
            Some(_) => return Err(invalid("limit", format!("must be 1 to {MAX_ROWS}"))),
        };
        let keep = |r: &Record| -> bool {
            class.as_deref().is_none_or(|c| r.class == c)
                && source.as_deref().is_none_or(|s| {
                    if s.ends_with('/') {
                        r.source.starts_with(s)
                    } else {
                        r.source == s
                    }
                })
                && ty.is_none_or(|t| r.ty == t)
                && range.is_none_or(|(from, to)| r.created >= from && r.created < to)
                && match state {
                    AlarmState::Open => r.is_open(),
                    AlarmState::Active => r.is_active(),
                    AlarmState::Unacked => !r.is_acked(),
                    AlarmState::Closed => !r.is_open(),
                    AlarmState::All => true,
                }
                && who.may_for(&r.source, wyrm_core::Perm::Read)
        };
        let mut rows = Vec::new();
        let mut complete = true;
        let mut scanned_to: Option<Micros> = None;
        if matches!(
            state,
            AlarmState::Open | AlarmState::Active | AlarmState::Unacked
        ) {
            for r in self.open.values().rev() {
                if rows.len() >= limit {
                    complete = false;
                    break;
                }
                if keep(r) {
                    rows.push(r.to_row());
                }
            }
        } else if self.next_id > 0 {
            let first = self.meta.first_page;
            let last = store::page_of(self.next_id - 1);
            // the newest page whose first record is not after `to`
            let mut hi = last;
            if let Some((_, to)) = range {
                let (mut lo, mut h) = (first, last + 1);
                while lo < h {
                    let mid = lo + (h - lo) / 2;
                    match Self::page_first_created(cx, mid) {
                        Some(t) if t < to => lo = mid + 1,
                        _ => h = mid,
                    }
                }
                if lo == first {
                    return Ok(answer(rows, true, None));
                }
                hi = lo - 1;
            }
            let mut pages = 0usize;
            let mut n = hi;
            loop {
                if pages >= MAX_PAGES_PER_QUERY {
                    complete = false;
                    break;
                }
                let page = store::load_page(cx, n);
                pages += 1;
                for r in page.iter().rev() {
                    scanned_to = Some(r.created);
                    if range.is_some_and(|(from, _)| r.created < from) {
                        break;
                    }
                    if rows.len() >= limit {
                        complete = false;
                        break;
                    }
                    if keep(r) {
                        rows.push(r.to_row());
                    }
                }
                let below = range.is_some_and(|(from, _)| scanned_to.is_some_and(|t| t < from));
                if !complete || below || n == first {
                    break;
                }
                n -= 1;
            }
        }
        Ok(answer(rows, complete, scanned_to))
    }

    fn purge_action(&mut self, cx: &mut Counted, a: Purge, now: Micros) -> Result<Value, AppError> {
        let before = parse_instant(&a.before)
            .ok_or_else(|| invalid("before", "an RFC 3339 instant or a date"))?;
        let n = self.purge_pages(cx, Some(before), now);
        Ok(Value::Map(Map::from([(
            "pages".to_owned(),
            Value::UInt(n as u64),
        )])))
    }

    // ---------- actions: sinks ----------

    fn save_sinks(&self, cx: &mut Counted) -> Result<(), AppError> {
        sinks::save(cx, self.sinks.values().map(|s| &s.def))
    }

    /// The cursor `from` names: the oldest journal entry kept, or the newest.
    fn cursor_from(&self, from: SinkFrom) -> u64 {
        match from {
            SinkFrom::Start => self.meta.first_jpage * JOURNAL_PAGE,
            SinkFrom::Now => self.next_seq() - 1,
        }
    }

    fn sink(&self, name: &str) -> Result<&Sink, AppError> {
        self.sinks
            .get(name)
            .ok_or_else(|| not_found(format!("sinks/{name}")))
    }

    /// The sink `name` is there and the caller is its link: nobody else moves its cursor (a
    /// person who ran `next` would confirm rows the database never got).
    fn sink_reader(&self, name: &str, who: &Who) -> Result<(), AppError> {
        let s = self.sink(name)?;
        if who.subject.as_deref() != Some(&format!("link:{}", s.def.link)) {
            return Err(denied(""));
        }
        Ok(())
    }

    fn add_sink(&mut self, cx: &mut Counted, a: AddSink) -> Result<Value, AppError> {
        let name = a.name;
        sinks::valid_name("name", &name)?;
        if self.sinks.contains_key(&name) {
            return Err(invalid("name", format!("{name} exists")));
        }
        if self.sinks.len() >= MAX_SINKS {
            return Err(exhausted(format!("at most {MAX_SINKS} sinks")));
        }
        self.check_nodes(1, 0)?;
        let link = a.link;
        sinks::valid_name("link", &link)?;
        let classes = a
            .classes
            .as_deref()
            .map(sinks::class_list)
            .transpose()?
            .unwrap_or_default();
        let cursor = self.cursor_from(a.from.unwrap_or(SinkFrom::Start));
        let def = SinkDef {
            name: name.clone(),
            link,
            classes,
            cursor,
        };
        self.sinks.insert(name.clone(), Sink::new(def));
        if let Err(e) = self.save_sinks(cx) {
            self.sinks.remove(&name);
            return Err(e);
        }
        self.nodes += 1;
        self.show_sink(cx, &name);
        Ok(Value::Null)
    }

    fn edit_sink(&mut self, cx: &mut Counted, name: &str, a: EditSink) -> Result<Value, AppError> {
        let mut def = self.sink(name)?.def.clone();
        if let Some(l) = a.link {
            sinks::valid_name("link", &l)?;
            def.link = l;
        }
        if let Some(c) = a.classes {
            def.classes = sinks::class_list(&c)?;
        }
        let Some(s) = self.sinks.get_mut(name) else {
            return Err(not_found(format!("sinks/{name}")));
        };
        let old = std::mem::replace(&mut s.def, def);
        if let Err(e) = self.save_sinks(cx) {
            if let Some(s) = self.sinks.get_mut(name) {
                s.def = old;
            }
            return Err(e);
        }
        self.show_sink(cx, name);
        Ok(Value::Null)
    }

    fn reset_sink(
        &mut self,
        cx: &mut Counted,
        name: &str,
        a: ResetSink,
    ) -> Result<Value, AppError> {
        self.sink(name)?;
        let cursor = self.cursor_from(a.from);
        let Some(s) = self.sinks.get_mut(name) else {
            return Err(not_found(format!("sinks/{name}")));
        };
        let old = std::mem::replace(&mut s.def.cursor, cursor);
        if let Err(e) = self.save_sinks(cx) {
            if let Some(s) = self.sinks.get_mut(name) {
                s.def.cursor = old;
            }
            return Err(e);
        }
        self.show_sink(cx, name);
        Ok(Value::Null)
    }

    fn remove_sink(&mut self, cx: &mut Counted, name: &str) -> Result<Value, AppError> {
        let Some(s) = self.sinks.remove(name) else {
            return Err(not_found(format!("sinks/{name}")));
        };
        if let Err(e) = self.save_sinks(cx) {
            self.sinks.insert(name.to_owned(), s);
            return Err(e);
        }
        cx.remove_node(&tree::sink(name));
        self.nodes -= 1;
        Ok(Value::Null)
    }

    /// One batch for the sink's link: `{rows: [{seq, key, t, v, q}], next}` (ADR 0026 feed).
    /// `after` (default: the confirmed entry) confirms every entry up to it.
    fn sink_next(
        &mut self,
        cx: &mut Counted,
        name: &str,
        a: SinkNext,
        who: &Who,
        now: Micros,
    ) -> Result<Value, AppError> {
        let next_seq = self.next_seq();
        self.sink_reader(name, who)?;
        let Some(s) = self.sinks.get_mut(name) else {
            return Err(not_found(format!("sinks/{name}")));
        };
        if let Some(after) = a.after {
            if after >= next_seq {
                return Err(invalid(
                    "after",
                    format!("{after}: beyond the last journal entry"),
                ));
            }
            if after != s.def.cursor {
                s.def.cursor = after;
                self.save_sinks(cx)?;
            }
        }
        let max = match a.max {
            None => DEFAULT_BATCH_ROWS,
            Some(n) if n >= 1 => (n as usize).min(MAX_BATCH_ROWS),
            Some(_) => return Err(invalid("max", format!("1 to {MAX_BATCH_ROWS}"))),
        };
        let s = &self.sinks[name];
        let cursor = s.def.cursor;
        let mut seq = (cursor + 1).max(self.meta.first_jpage * JOURNAL_PAGE + 1);
        let mut rows = Vec::new();
        let mut bytes = 0usize;
        let mut seen = HashSet::new();
        let mut pages: HashMap<u64, Vec<Record>> = HashMap::new();
        let mut page: Option<(u64, Vec<u64>)> = None;
        let mut last = cursor;
        'scan: while seq < next_seq {
            let n = store::jpage_of(seq - 1);
            let entries = match &page {
                Some((p, entries)) if *p == n => entries,
                _ => {
                    let entries = if n == self.jpage {
                        self.jtail.clone()
                    } else {
                        store::load_journal_page(cx, n)
                    };
                    &page.insert((n, entries)).1
                }
            };
            let i = (seq - 1 - n * JOURNAL_PAGE) as usize;
            let Some(&id) = entries.get(i) else {
                // a page cut short: on to the next one
                seq = (n + 1) * JOURNAL_PAGE + 1;
                continue;
            };
            if seen.insert(id) {
                let rec = match self.open.get(&id) {
                    Some(r) => Some(r.clone()),
                    None => {
                        let p = store::page_of(id);
                        pages
                            .entry(p)
                            .or_insert_with(|| store::load_page(cx, p))
                            .iter()
                            .find(|r| r.id == id)
                            .cloned()
                    }
                };
                if let Some(r) = rec.filter(|r| s.takes(&r.class)) {
                    let json = r.to_json();
                    if rows.len() >= max || bytes + json.len() > MAX_BATCH_BYTES {
                        break 'scan;
                    }
                    bytes += json.len();
                    rows.push(Value::Map(Map::from([
                        ("seq".to_owned(), Value::UInt(seq)),
                        ("key".to_owned(), Value::Str(r.source.clone())),
                        (
                            "t".to_owned(),
                            Value::UInt(u64::try_from(r.created).unwrap_or(0)),
                        ),
                        ("v".to_owned(), Value::Str(json)),
                        // the row is the record itself, written by this link: not a
                        // reading of the source, so its quality is known to be good
                        ("q".to_owned(), Value::UInt(Quality::Good.code().into())),
                    ])));
                }
            }
            last = seq;
            seq += 1;
        }
        let sent = rows.len() as u64;
        // found at the start; nothing in between removes a sink
        let Some(s) = self.sinks.get_mut(name) else {
            return Err(not_found(format!("sinks/{name}")));
        };
        s.rows_sent += sent;
        s.last_request = Some(now);
        self.show_sink(cx, name);
        Ok(Value::Map(Map::from([
            ("rows".to_owned(), Value::Array(rows)),
            ("next".to_owned(), Value::UInt(last)),
        ])))
    }

    /// The open records (for tests and benchmarks).
    pub fn open_records(&self) -> impl Iterator<Item = &Record> {
        self.open.values()
    }

    /// The next journal entry's number.
    pub fn journal_next(&self) -> u64 {
        self.next_seq()
    }
}

fn push_note(r: &mut Record, now: Micros, by: String, text: String) -> Result<(), AppError> {
    if text.len() > MAX_NOTE_LEN {
        return Err(invalid("note", format!("at most {MAX_NOTE_LEN} bytes")));
    }
    if r.notes.len() >= MAX_NOTES {
        return Err(exhausted(format!("at most {MAX_NOTES} notes per record")));
    }
    r.notes.push(Note { t: now, by, text });
    Ok(())
}

fn answer(rows: Vec<Value>, complete: bool, scanned_to: Option<Micros>) -> Value {
    Value::Map(Map::from([
        ("rows".to_owned(), Value::Array(rows)),
        ("complete".to_owned(), Value::Bool(complete)),
        (
            "scanned_to".to_owned(),
            scanned_to.map_or(Value::Null, model::rfc3339),
        ),
    ]))
}

impl App for Alarm {
    const NAME: &'static str = "alarm";
    const VERSION: &'static str = env!("CARGO_PKG_VERSION");

    fn start(host: &mut dyn Host, config: Value) -> Result<Self, AppError> {
        let params = params(&config)?;
        let mut cx = Counted::new(host);
        for (name, a) in tree::root_actions() {
            cx.declare_action("", name, a);
        }
        cx.declare_node(tree::STATS, tree::stats_meta());
        for n in tree::stat_names() {
            cx.declare_node(&tree::stat(n), tree::stat_meta(n));
        }
        cx.declare_node(tree::SINKS, tree::sinks_meta());
        let index = match store::load_index(&cx) {
            Ok(i) => i,
            Err(e) => {
                cx.log(Level::Error, &format!("store index unreadable: {e}"));
                Vec::new()
            }
        };
        let meta = Meta::load(&cx);
        // after a purge of every page the ids go on after the pages that went
        let next_id = store::next_id(&cx, meta.page_hint).max(meta.first_page * PAGE);
        let (jpage, jtail) = store::last_journal_page(&cx, meta.jpage_hint)
            .unwrap_or((meta.first_jpage.max(meta.jpage_hint), Vec::new()));
        let mut open = BTreeMap::new();
        let mut by_page: BTreeMap<u64, Vec<u64>> = BTreeMap::new();
        for id in store::load_open_ids(&cx) {
            by_page.entry(store::page_of(id)).or_default().push(id);
        }
        for (p, ids) in by_page {
            for r in store::load_page(&cx, p) {
                if ids.contains(&r.id) && r.is_open() {
                    open.insert(r.id, r);
                }
            }
        }
        let sinks: BTreeMap<String, Sink> = sinks::load(&cx)
            .into_iter()
            .map(|d| (d.name.clone(), Sink::new(d)))
            .collect();
        let mut app = Alarm {
            params,
            pending: index.iter().cloned().collect(),
            pending_watches: VecDeque::new(),
            index,
            classes: HashMap::new(),
            nodes: STATS_NODES + 1 + sinks.len(),
            subs: HashMap::new(),
            open,
            meta,
            next_id,
            jpage,
            jtail,
            sinks,
            stats: Stats::default(),
            stats_shown: [u64::MAX; STATS_NODES - 1],
            wakes: Wakes::default(),
            timer: Timer::default(),
            drain: None,
        };
        let now = now_of(&cx);
        app.timer.observe(now);
        let names: Vec<String> = app.sinks.keys().cloned().collect();
        for n in names {
            app.show_sink(&mut cx, &n);
        }
        // open records nobody acknowledged keep escalating
        let esc: Vec<(u64, String, Micros, u8)> = app
            .open
            .values()
            .filter(|r| !r.is_acked())
            .map(|r| (r.id, r.class.clone(), r.created, r.escalation))
            .collect();
        for (id, class, created, level) in esc {
            // the class is not loaded yet: its definition says the delays
            let Ok(c) = store::load_class(&cx, &class) else {
                continue;
            };
            let delay = match level {
                0 if c.escalation1_s > 0 => c.escalation1_s,
                1 if c.escalation2_s > 0 => c.escalation2_s,
                _ => continue,
            };
            app.wakes.set(
                Wake::Escalate(id),
                Some(created.saturating_add(secs_us(delay)).max(now)),
            );
        }
        app.wakes.set(Wake::Stats, Some(now));
        app.wakes
            .set(Wake::Purge, Some(now.saturating_add(ms_us(1_000))));
        app.run(&mut cx);
        app.arm(&mut cx);
        Ok(app)
    }

    fn on_set(
        &mut self,
        _host: &mut dyn Host,
        path: &str,
        _value: Value,
        _who: &Who,
    ) -> Result<(), AppError> {
        Err(not_found(path.to_owned()))
    }

    fn on_invoke(
        &mut self,
        host: &mut dyn Host,
        path: &str,
        action: &str,
        args: Value,
        who: &Who,
    ) -> Result<Value, AppError> {
        let mut cx = Counted::new(host);
        self.check_clock(&mut cx);
        let r = actions::invoke(self, &mut cx, path, action, args, who);
        self.arm(&mut cx);
        r
    }

    fn on_timer(&mut self, host: &mut dyn Host, timer: TimerId) {
        let mut cx = Counted::new(host);
        let now = now_of(&cx);
        let back = self.timer.observe(now);
        let fired = self.timer.fired(timer, now);
        let step = match fired {
            Fired::Step(off) => Some(off),
            _ => back,
        };
        match (step, fired) {
            (Some(off), _) => self.clock_step(&mut cx, off),
            (None, Fired::Stale) => return,
            (None, Fired::Ok { continuation }) => {
                if !continuation {
                    self.drain = None;
                }
            }
            (None, Fired::Step(_)) => {}
        }
        self.run(&mut cx);
        self.arm(&mut cx);
    }

    fn on_value(&mut self, host: &mut dyn Host, sub: SubId, key: &str, sample: Sample) {
        let mut cx = Counted::new(host);
        self.check_clock(&mut cx);
        if let Some((c, w)) = self.subs.get(&sub).cloned() {
            self.sample(&mut cx, &c, &w, key, sample);
        }
        self.arm(&mut cx);
    }
}

/// Lateness tolerance of a wake, for tests.
pub const STEP_MS: u64 = CLOCK_STEP_MS;

// Only on wasm32: natively the exports would be bare global `start`/`stop`… symbols.
#[cfg(all(feature = "wasm", target_arch = "wasm32"))]
wyrm_link_guest::export!(Alarm);
