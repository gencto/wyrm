//! Targets (ADR 0022 "Targets: writes, confirmation, override"; plan rulings 5–7): the points a
//! schedule writes on each transition.
//!
//! - A transition, and an action that adds, edits or enables a target, marks the target
//!   `pending` and puts it once in one FIFO write queue; [`Scheduler::pump`] sends while fewer
//!   than [`MAX_INFLIGHT`] writes wait for their reply. A newer transition of a queued target
//!   changes what it writes, not how often.
//! - Confirmation: `read_back` (a sample of the point equals what was written), `feedback` (a
//!   sample of another key equals the expected value), `ack` (an `ok` reply). A matching sample
//!   counts while the write waits for its reply or after an `ok`; none [`CONFIRM_TIMEOUT_MS`]
//!   after the `ok` fails the write. Links publish a value only when it changes, so a key whose
//!   last sample already shows the value confirms on the `ok`.
//! - A failed write is tried again with backoff through the one wake heap. Each transition gives
//!   the target a new generation: replies and wakes of an older one are ignored.
//! - Override: a sample that differs from a confirmed value marks the target `override`; it is
//!   not written again until the next transition.
//! - Records `o/<s>/<t>` (on confirm and on override only) name the schedule state they were
//!   for. At start a target with a record for the state now is left as it was; the others wait
//!   [`FIRST_SAMPLE_MS`] for a first sample that already shows the value, else they are written.
//! - Subscriptions: one per key, shared by the targets that confirm on it, held while a target
//!   is enabled, not `override` and not `ack`.
//!
//! Logs name schedule and target ids, states and status names, never values.

use std::collections::{BTreeMap, HashMap, HashSet, VecDeque};

use wyrm_core::{keyspace, Quality, Sample, Status, Value};
use wyrm_link_api::{AppError, Host, Level, ReqId, SubId, Who};
use wyrm_schedule::{value_from_json, Micros, Source, State};

use crate::limits::{
    Counted, CONFIRM_TIMEOUT_MS, DEFAULT_TOLERANCE, FIRST_SAMPLE_MS, MAX_INFLIGHT, MAX_SUBS,
    MAX_TARGETS, RETRY_CAP_MS, RETRY_FIRST_MS, RETRY_JITTER_PCT,
};
use crate::wake::{Wake, Wakes};
use crate::Scheduler;
use crate::{exhausted, good, invalid, now_of, opt_bool, opt_str, req_str, store, tree, Args};

// Command costs are upper bounds: a refused call counts too.
/// Commands one target takes when a transition (or an action) begins its write: its node, its
/// state, its subscription (and a log when refused), a stale record deleted.
pub const BEGIN_COST: usize = 5;
/// Commands one loaded target takes at start: [`BEGIN_COST`], and a confirmation by the last
/// sample of a shared key (record, log, node and state).
pub const RESUME_COST: usize = BEGIN_COST + 4;
/// Commands of one write sent: a subscription tried again (and its log), the set, then the
/// node and state, or a log, the retry's log, the node and state.
pub const WRITE_COST: usize = 7;
/// Commands of one sample, reply or wake of a target: its node and state, the record, a log and
/// an unsubscribe.
pub const TARGET_COST: usize = 5;
/// Bytes of `last_error` at most.
const MAX_TARGET_ERROR: usize = 200;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Confirm {
    ReadBack,
    Feedback,
    Ack,
}

impl Confirm {
    pub fn as_str(self) -> &'static str {
        match self {
            Confirm::ReadBack => "read_back",
            Confirm::Feedback => "feedback",
            Confirm::Ack => "ack",
        }
    }

    fn parse(s: &str) -> Option<Self> {
        match s {
            "read_back" => Some(Confirm::ReadBack),
            "feedback" => Some(Confirm::Feedback),
            "ack" => Some(Confirm::Ack),
            _ => None,
        }
    }
}

/// A target's state, the value of its node.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TState {
    Pending,
    Writing,
    Confirmed,
    Retrying,
    Override,
    Disabled,
}

impl TState {
    pub fn as_str(self) -> &'static str {
        match self {
            TState::Pending => "pending",
            TState::Writing => "writing",
            TState::Confirmed => "confirmed",
            TState::Retrying => "retrying",
            TState::Override => "override",
            TState::Disabled => "disabled",
        }
    }
}

/// A target as saved in its schedule's definition.
#[derive(Debug, Clone, PartialEq)]
pub struct TargetDef {
    pub id: String,
    pub point: String,
    pub confirm: Confirm,
    pub feedback: Option<String>,
    /// Schedule value (its [`value_key`]) → value to write.
    pub map: BTreeMap<String, Value>,
    /// Schedule value → value the feedback key shows.
    pub feedback_map: BTreeMap<String, Value>,
    pub tolerance: Option<f64>,
    pub enabled: bool,
    pub created_by: String,
}

impl TargetDef {
    /// The key whose samples confirm a write (none in `ack` mode).
    pub fn confirm_key(&self) -> Option<&str> {
        match self.confirm {
            Confirm::ReadBack => Some(&self.point),
            Confirm::Feedback => self.feedback.as_deref(),
            Confirm::Ack => None,
        }
    }

    /// What to write for the schedule value `v`, and what the confirm key must show.
    fn plan(&self, v: &Value) -> (Value, Option<Value>) {
        let key = value_key(v);
        let pick = |m: &BTreeMap<String, Value>| key.as_ref().and_then(|k| m.get(k)).cloned();
        let write = pick(&self.map).unwrap_or_else(|| v.clone());
        let expect = match self.confirm {
            Confirm::Ack => None,
            Confirm::ReadBack => Some(write.clone()),
            Confirm::Feedback => Some(pick(&self.feedback_map).unwrap_or_else(|| write.clone())),
        };
        (write, expect)
    }

    fn tolerance(&self) -> f64 {
        self.tolerance.unwrap_or(DEFAULT_TOLERANCE)
    }

    /// The target in a definition (and an export).
    pub fn to_value(&self) -> Value {
        let mut m = BTreeMap::new();
        m.insert("id".to_owned(), Value::Str(self.id.clone()));
        m.insert("point".to_owned(), Value::Str(self.point.clone()));
        m.insert(
            "confirm".to_owned(),
            Value::Str(self.confirm.as_str().into()),
        );
        if let Some(f) = &self.feedback {
            m.insert("feedback".to_owned(), Value::Str(f.clone()));
        }
        if !self.map.is_empty() {
            m.insert("map".to_owned(), Value::Map(self.map.clone()));
        }
        if !self.feedback_map.is_empty() {
            m.insert(
                "feedback_map".to_owned(),
                Value::Map(self.feedback_map.clone()),
            );
        }
        if let Some(t) = self.tolerance {
            m.insert("tolerance".to_owned(), Value::Float(t));
        }
        m.insert("enabled".to_owned(), Value::Bool(self.enabled));
        m.insert("created_by".to_owned(), Value::Str(self.created_by.clone()));
        Value::Map(m)
    }
}

/// The key of a schedule value in `map` and `feedback_map`: `true`/`false`, a number in its
/// shortest decimal (`1`, `0.5`), text as it is; other values have none.
pub fn value_key(v: &Value) -> Option<String> {
    match v {
        Value::Bool(b) => Some(b.to_string()),
        Value::UInt(n) => Some(n.to_string()),
        Value::Int(n) => Some(n.to_string()),
        Value::Float(f) if f.is_finite() => Some(format!("{f}")),
        Value::Str(s) => Some(s.clone()),
        _ => None,
    }
}

fn number(v: &Value) -> Option<f64> {
    match v {
        Value::UInt(n) => Some(*n as f64),
        Value::Int(n) => Some(*n as f64),
        Value::Float(f) => Some(*f),
        _ => None,
    }
}

/// A sample `got` shows `expect`: numbers within `tol` (relative; absolute when `expect` is 0),
/// a bool and the number 1/0, otherwise equal values.
pub fn same(expect: &Value, got: &Value, tol: f64) -> bool {
    let bit = |b: bool| if b { 1.0 } else { 0.0 };
    match (expect, got, number(expect), number(got)) {
        (_, _, Some(0.0), Some(b)) => b.abs() <= tol,
        (_, _, Some(a), Some(b)) => ((a - b) / a).abs() <= tol,
        (Value::Bool(e), _, _, Some(b)) => b == bit(*e),
        (_, Value::Bool(g), Some(a), _) => a == bit(*g),
        _ => expect == got,
    }
}

/// The schedule state a record is for: `default`, or the event and its occurrence.
pub fn source_key(s: &Source) -> String {
    let at = |t: &Micros| match jiff::Timestamp::from_microsecond(*t) {
        Ok(ts) => ts.to_string(),
        Err(_) => t.to_string(),
    };
    match s {
        Source::Default => "default".to_owned(),
        Source::Event { id, at: t } => format!("event:{id}@{}", at(t)),
        Source::Moment { id, at: t } => format!("moment:{id}@{}", at(t)),
    }
}

/// A point or feedback key: `wy/<site>/downstream/<link>/<path>`, each segment a plain key
/// segment (no `*`, `~` or empty one).
fn check_key(field: &str, key: &str) -> Result<(), AppError> {
    let segs: Vec<&str> = key.split('/').collect();
    let ok = segs.len() >= 5
        && segs[0] == keyspace::ROOT
        && segs[2] == "downstream"
        && segs
            .iter()
            .all(|s| keyspace::validate_segment(s).is_ok() && !matches!(*s, "." | ".."));
    if !ok {
        return Err(invalid(
            field,
            format!(
                "{key:?} is not a point key wy/<site>/downstream/<link>/<path> \
                 (no *, ~ or empty segment)"
            ),
        ));
    }
    Ok(())
}

/// A map of schedule values to values: a map, or its JSON text. `None`: absent (an edit keeps
/// it); null, `""` or `{}`: none.
fn value_map(m: &Args, k: &str) -> Result<Option<BTreeMap<String, Value>>, AppError> {
    let bad = || invalid(k, "a map of schedule values to values (a JSON object)");
    match m.get(k) {
        None => Ok(None),
        Some(Value::Null) => Ok(Some(BTreeMap::new())),
        Some(Value::Map(x)) => Ok(Some(x.clone())),
        Some(Value::Str(s)) if s.trim().is_empty() => Ok(Some(BTreeMap::new())),
        Some(Value::Str(s)) => match serde_json::from_str::<serde_json::Value>(s) {
            Ok(j @ serde_json::Value::Object(_)) => match value_from_json(&j) {
                Value::Map(x) => Ok(Some(x)),
                _ => Err(bad()),
            },
            _ => Err(bad()),
        },
        Some(_) => Err(bad()),
    }
}

/// `tolerance`: `None` absent, `Some(None)` null (the default).
fn tolerance(m: &Args) -> Result<Option<Option<f64>>, AppError> {
    match m.get("tolerance") {
        None => Ok(None),
        Some(Value::Null) => Ok(Some(None)),
        Some(v) => match number(v) {
            Some(t) if t.is_finite() && t >= 0.0 => Ok(Some(Some(t))),
            _ => Err(invalid("tolerance", "a number from 0")),
        },
    }
}

/// The fields of `add_target` (`base` = `None`; `point` and `confirm` required) or of a
/// target's `edit` over `base` (absent keeps a field; `feedback` goes when `confirm` is not
/// `feedback`).
pub fn fields(
    id: String,
    m: &Args,
    base: Option<&TargetDef>,
    created_by: String,
) -> Result<TargetDef, AppError> {
    let point = match (opt_str(m, "point")?, base) {
        (Some(p), _) => p,
        (None, Some(b)) => b.point.clone(),
        (None, None) => return Err(invalid("point", "required")),
    };
    check_key("point", &point)?;
    let confirm = match (opt_str(m, "confirm")?, base) {
        (Some(c), _) => Confirm::parse(&c)
            .ok_or_else(|| invalid("confirm", "one of read_back, feedback, ack"))?,
        (None, Some(b)) => b.confirm,
        (None, None) => return Err(invalid("confirm", "required")),
    };
    let given = opt_str(m, "feedback")?;
    let feedback = match confirm {
        Confirm::Feedback => {
            let f = given
                .or_else(|| base.and_then(|b| b.feedback.clone()))
                .filter(|f| !f.is_empty())
                .ok_or_else(|| invalid("feedback", "required with confirm feedback"))?;
            check_key("feedback", &f)?;
            Some(f)
        }
        _ if given.as_ref().is_some_and(|f| !f.is_empty()) => {
            return Err(invalid("feedback", "only with confirm feedback"))
        }
        _ => None,
    };
    let map = match value_map(m, "map")? {
        Some(x) => x,
        None => base.map(|b| b.map.clone()).unwrap_or_default(),
    };
    let feedback_map = match value_map(m, "feedback_map")? {
        Some(x) => x,
        None => base.map(|b| b.feedback_map.clone()).unwrap_or_default(),
    };
    Ok(TargetDef {
        id,
        point,
        confirm,
        feedback,
        map,
        feedback_map,
        tolerance: tolerance(m)?.unwrap_or_else(|| base.and_then(|b| b.tolerance)),
        enabled: base.is_none_or(|b| b.enabled),
        created_by,
    })
}

fn within(at: &str) -> impl Fn(AppError) -> AppError + '_ {
    move |e| AppError::new(e.status, format!("{at}{}", e.msg))
}

/// The `targets` array of a definition or an export (null: none), each checked as by
/// `add_target`; `created_by` (an import): the importer, else as stored.
pub fn defs_from_value(v: &Value, created_by: Option<&str>) -> Result<Vec<TargetDef>, AppError> {
    let items = match v {
        Value::Null => return Ok(Vec::new()),
        Value::Array(a) => a,
        _ => return Err(invalid("targets", "must be an array")),
    };
    if items.len() > MAX_TARGETS {
        return Err(exhausted(format!(
            "at most {MAX_TARGETS} targets per schedule ({} given)",
            items.len()
        )));
    }
    let mut out: Vec<TargetDef> = Vec::new();
    for (i, item) in items.iter().enumerate() {
        let at = format!("targets[{i}].");
        let Value::Map(m) = item else {
            return Err(invalid(&format!("targets[{i}]"), "must be a map"));
        };
        let id = req_str(m, "id").map_err(within(&at))?;
        if keyspace::validate_segment(&id).is_err() || matches!(id.as_str(), "." | "..") {
            return Err(invalid(&format!("{at}id"), format!("{id:?} is not an id")));
        }
        if out.iter().any(|d| d.id == id) {
            return Err(invalid(&format!("{at}id"), format!("{id} twice")));
        }
        let by = match created_by {
            Some(b) => b.to_owned(),
            None => opt_str(m, "created_by")
                .map_err(within(&at))?
                .unwrap_or_default(),
        };
        let mut d = fields(id, m, None, by).map_err(within(&at))?;
        d.enabled = opt_bool(m, "enabled").map_err(within(&at))?.unwrap_or(true);
        out.push(d);
    }
    Ok(out)
}

/// The next target number of a definition: as saved, and past every `t<n>` id.
pub fn next_target(saved: Option<&Value>, defs: &[TargetDef]) -> u32 {
    let saved = match saved {
        Some(Value::UInt(n)) => u32::try_from(*n).unwrap_or(u32::MAX),
        _ => 1,
    };
    let past = defs
        .iter()
        .filter_map(|d| d.id.strip_prefix('t').and_then(|n| n.parse::<u32>().ok()))
        .max()
        .map_or(1, |n| n.saturating_add(1));
    saved.max(past)
}

/// What a target's wake is for.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum DueKind {
    Retry,
    ConfirmTimeout,
    FirstSample,
}

#[derive(Debug, Clone, Copy)]
struct Due {
    kind: DueKind,
    at: Micros,
    delay: Micros,
    gen: u64,
}

/// A target and what it is doing.
pub struct Target {
    pub def: TargetDef,
    pub state: TState,
    pub attempts: u64,
    pub last_error: Option<String>,
    pub last_write: Option<Micros>,
    /// The schedule state the target works for, what it writes and what confirms it.
    for_state: Option<State>,
    /// What its record `o/<s>/<t>` is for (value and source), when it has one.
    recorded: Option<(Value, String)>,
    write: Value,
    expect: Option<Value>,
    /// Each transition is a new generation; older replies and wakes are ignored.
    gen: u64,
    /// A matching sample came while the write waited for its reply.
    matched: bool,
    /// The write in flight had its `ok` reply.
    replied: bool,
    /// At start: waits for the first sample of its confirm key.
    first: bool,
    wake: Option<Due>,
    /// In the write queue.
    queued: bool,
    /// Holds the subscription of its confirm key.
    held: bool,
}

impl Target {
    pub fn new(def: TargetDef) -> Self {
        Target {
            state: if def.enabled {
                TState::Pending
            } else {
                TState::Disabled
            },
            def,
            attempts: 0,
            last_error: None,
            last_write: None,
            for_state: None,
            recorded: None,
            write: Value::Null,
            expect: None,
            gen: 0,
            matched: false,
            replied: false,
            first: false,
            wake: None,
            queued: false,
            held: false,
        }
    }

    /// Holds a subscription now: enabled, confirmed by samples and not overridden.
    fn wants_sub(&self) -> bool {
        self.def.enabled
            && self.def.confirm != Confirm::Ack
            && !matches!(self.state, TState::Override | TState::Disabled)
    }
}

type Holder = (String, String);

struct Sub {
    id: SubId,
    holders: Vec<Holder>,
    last: Option<Value>,
}

/// One subscription per key, shared by its holders.
#[derive(Default)]
pub struct Subs {
    by_key: HashMap<String, Sub>,
    by_id: HashMap<SubId, String>,
}

/// Subscriptions an action made to check keys (ruling 7): kept for the targets that hold them,
/// dropped at the end of the action otherwise, and all dropped when it fails.
pub type Probes = Vec<(String, SubId)>;

impl Subs {
    fn live(&self, key: &str) -> bool {
        self.by_key.contains_key(key)
    }

    /// Subscribes `key` to check that the host lets the link reach it, unless it is live.
    fn probe(&self, cx: &mut dyn Host, key: &str, made: &mut Probes) -> Result<(), AppError> {
        if self.live(key) || made.iter().any(|(k, _)| k == key) {
            return Ok(());
        }
        let id = cx.subscribe(key)?;
        made.push((key.to_owned(), id));
        Ok(())
    }

    pub fn undo(cx: &mut dyn Host, made: &Probes) {
        for (_, id) in made {
            cx.unsubscribe(*id);
        }
    }

    pub fn adopt(&mut self, made: &Probes) {
        for (k, id) in made {
            self.by_id.insert(*id, k.clone());
            self.by_key.insert(
                k.clone(),
                Sub {
                    id: *id,
                    holders: Vec::new(),
                    last: None,
                },
            );
        }
    }

    /// Drops the adopted probes no target holds.
    pub fn sweep(&mut self, cx: &mut dyn Host, made: &Probes) {
        for (k, _) in made {
            if self.by_key.get(k).is_some_and(|s| s.holders.is_empty()) {
                self.drop_key(cx, k);
            }
        }
    }

    fn drop_key(&mut self, cx: &mut dyn Host, key: &str) {
        if let Some(s) = self.by_key.remove(key) {
            self.by_id.remove(&s.id);
            cx.unsubscribe(s.id);
        }
    }

    fn hold(&mut self, cx: &mut dyn Host, key: &str, holder: Holder) -> Result<(), AppError> {
        if let Some(s) = self.by_key.get_mut(key) {
            s.holders.push(holder);
            return Ok(());
        }
        let id = cx.subscribe(key)?;
        self.by_id.insert(id, key.to_owned());
        self.by_key.insert(
            key.to_owned(),
            Sub {
                id,
                holders: vec![holder],
                last: None,
            },
        );
        Ok(())
    }

    fn release(&mut self, cx: &mut dyn Host, key: &str, holder: &Holder) {
        let Some(s) = self.by_key.get_mut(key) else {
            return;
        };
        if let Some(i) = s.holders.iter().position(|h| h == holder) {
            s.holders.swap_remove(i);
        }
        if s.holders.is_empty() {
            self.drop_key(cx, key);
        }
    }

    /// A sample of subscription `sub`: kept as its key's last value; the holders.
    fn sample(&mut self, sub: SubId, v: &Value) -> Option<Vec<Holder>> {
        let key = self.by_id.get(&sub)?;
        let s = self.by_key.get_mut(key)?;
        s.last = Some(v.clone());
        Some(s.holders.clone())
    }

    fn last(&self, key: &str) -> Option<&Value> {
        self.by_key.get(key).and_then(|s| s.last.as_ref())
    }
}

/// The write queue, the writes in flight and the subscriptions.
#[derive(Default)]
pub struct Writer {
    queue: VecDeque<Holder>,
    inflight: HashMap<ReqId, (String, String, u64)>,
    pub subs: Subs,
    /// Samples an event had no room for, handled by the next batches.
    deferred: VecDeque<(String, String, Value)>,
    gen_seq: u64,
}

impl Writer {
    /// Work for a `0` ms timer: deferred samples, or writes waiting with a free slot.
    pub fn has_work(&self) -> bool {
        !self.deferred.is_empty() || (!self.queue.is_empty() && self.inflight.len() < MAX_INFLIGHT)
    }

    fn next_gen(&mut self) -> u64 {
        self.gen_seq += 1;
        self.gen_seq
    }
}

fn ms_us(ms: u64) -> Micros {
    i64::try_from(ms.saturating_mul(1000)).unwrap_or(Micros::MAX)
}

/// FNV-1a 64 of `now` and the target (ruling 4: jitter without `rand`).
fn fnv1a(now: Micros, sid: &str, tid: &str) -> u64 {
    let mut h: u64 = 0xcbf2_9ce4_8422_2325;
    let bytes = now
        .to_le_bytes()
        .into_iter()
        .chain(sid.bytes())
        .chain(*b"/")
        .chain(tid.bytes());
    for b in bytes {
        h ^= u64::from(b);
        h = h.wrapping_mul(0x0000_0100_0000_01b3);
    }
    h
}

/// The wait before the next try after `attempts` tries: 1 s doubled each time up to 60 s, with
/// a jitter of ±20 %.
fn backoff_ms(attempts: u64, now: Micros, sid: &str, tid: &str) -> u64 {
    let n = attempts.saturating_sub(1).min(16);
    let base = RETRY_FIRST_MS.saturating_mul(1 << n).min(RETRY_CAP_MS);
    let span = base * RETRY_JITTER_PCT / 100;
    base - span + fnv1a(now, sid, tid) % (2 * span + 1)
}

fn status_name(e: &AppError) -> &'static str {
    e.status.name()
}

/// Text of an error for `last_error`, bounded.
fn error_text(e: &AppError) -> String {
    let mut s = e.to_string();
    if s.len() > MAX_TARGET_ERROR {
        let mut end = MAX_TARGET_ERROR;
        while !s.is_char_boundary(end) {
            end -= 1;
        }
        s.truncate(end);
    }
    s
}

/// What a target's work needs of the app during one event.
struct Env<'e, 'h> {
    cx: &'e mut Counted<'h>,
    w: &'e mut Writer,
    wakes: &'e mut Wakes,
}

impl Env<'_, '_> {
    fn show(&mut self, sid: &str, t: &Target) {
        let path = tree::target(sid, &t.def.id);
        self.cx.declare_node(&path, tree::target_meta(t));
        let s = good(self.cx, Value::Str(t.state.as_str().into()));
        self.cx.update(&path, s);
    }

    fn log(&mut self, level: Level, sid: &str, t: &Target, what: &str) {
        self.cx
            .log(level, &format!("target {sid}/{} {what}", t.def.id));
    }

    /// Holds or releases the subscription of the confirm key as the target's state wants.
    fn sync_sub(&mut self, sid: &str, t: &mut Target) {
        let Some(key) = t.def.confirm_key().map(str::to_owned) else {
            return;
        };
        let holder = (sid.to_owned(), t.def.id.clone());
        if t.wants_sub() && !t.held {
            match self.w.subs.hold(self.cx, &key, holder) {
                Ok(()) => t.held = true,
                Err(e) => {
                    let what = format!("not subscribed ({})", status_name(&e));
                    t.last_error = Some(error_text(&e));
                    self.log(Level::Warn, sid, t, &what);
                }
            }
        } else if !t.wants_sub() && t.held {
            self.w.subs.release(self.cx, &key, &holder);
            t.held = false;
        }
    }

    fn set_wake(&mut self, sid: &str, t: &mut Target, kind: DueKind, delay_ms: u64) {
        let delay = ms_us(delay_ms);
        let at = now_of(self.cx).saturating_add(delay);
        t.wake = Some(Due {
            kind,
            at,
            delay,
            gen: t.gen,
        });
        self.wakes
            .set(Wake::Target(sid.to_owned(), t.def.id.clone()), Some(at));
    }

    fn cancel_wake(&mut self, sid: &str, t: &mut Target) {
        if t.wake.take().is_some() {
            self.wakes
                .set(Wake::Target(sid.to_owned(), t.def.id.clone()), None);
        }
    }

    fn enqueue(&mut self, sid: &str, t: &mut Target) {
        t.state = TState::Pending;
        if !t.queued {
            t.queued = true;
            self.w.queue.push_back((sid.to_owned(), t.def.id.clone()));
        }
    }

    /// Plans the target for the schedule state `state` (a new generation).
    fn plan(&mut self, sid: &str, t: &mut Target, state: &State) {
        t.gen = self.w.next_gen();
        let (write, expect) = t.def.plan(&state.value);
        t.write = write;
        t.expect = expect;
        t.for_state = Some(state.clone());
        t.attempts = 0;
        t.matched = false;
        t.replied = false;
        t.first = false;
        self.cancel_wake(sid, t);
    }

    /// Deletes the target's record.
    fn forget(&mut self, sid: &str, t: &mut Target) {
        self.cx.store_delete(&store::outcome_key(sid, &t.def.id));
        t.recorded = None;
    }

    /// A transition for an enabled target: it writes `state`, the schedule's state now.
    fn begin(&mut self, sid: &str, t: &mut Target, state: &State) {
        self.plan(sid, t, state);
        // a record for an earlier time of this state (the default has no occurrence) must not
        // pass for this one after a restart
        let key = (state.value.clone(), source_key(&state.source));
        if t.recorded.as_ref() == Some(&key) {
            self.forget(sid, t);
        }
        self.enqueue(sid, t);
        self.sync_sub(sid, t);
        self.show(sid, t);
    }

    /// At start, an enabled target of an enabled schedule in the state `state`: as its record
    /// says when it is for this state, else it waits for a first sample (`ack`: it writes).
    fn resume(&mut self, sid: &str, t: &mut Target, state: &State) {
        self.plan(sid, t, state);
        let record = store::load_outcome(self.cx, sid, &t.def.id);
        t.recorded = record.as_ref().map(|r| (r.value.clone(), r.source.clone()));
        match record {
            Some(r) if r.value == state.value && r.source == source_key(&state.source) => {
                t.state = if r.outcome == store::OVERRIDE {
                    TState::Override
                } else {
                    TState::Confirmed
                };
                self.sync_sub(sid, t);
            }
            _ if t.def.confirm == Confirm::Ack => self.enqueue(sid, t),
            _ => {
                t.state = TState::Pending;
                self.sync_sub(sid, t);
                t.first = true;
                self.set_wake(sid, t, DueKind::FirstSample, FIRST_SAMPLE_MS);
                let last = t
                    .def
                    .confirm_key()
                    .and_then(|k| self.w.subs.last(k))
                    .cloned();
                if let Some(v) = last {
                    self.sample(sid, t, &v);
                }
            }
        }
        self.show(sid, t);
    }

    fn send(&mut self, sid: &str, t: &mut Target) {
        // a subscription the host refused before is tried again
        self.sync_sub(sid, t);
        t.attempts += 1;
        t.replied = false;
        t.last_write = Some(now_of(self.cx));
        match self.cx.set(&t.def.point, t.write.clone()) {
            Ok(req) => {
                self.w
                    .inflight
                    .insert(req, (sid.to_owned(), t.def.id.clone(), t.gen));
                t.state = TState::Writing;
                self.show(sid, t);
            }
            Err(e) => {
                let what = format!("write refused ({})", status_name(&e));
                self.log(Level::Warn, sid, t, &what);
                self.failed(sid, t, e);
            }
        }
    }

    fn failed(&mut self, sid: &str, t: &mut Target, e: AppError) {
        t.state = TState::Retrying;
        t.matched = false;
        t.replied = false;
        t.last_error = Some(error_text(&e));
        let delay = backoff_ms(t.attempts, now_of(self.cx), sid, &t.def.id);
        self.set_wake(sid, t, DueKind::Retry, delay);
        let what = format!("retrying ({})", status_name(&e));
        self.log(Level::Info, sid, t, &what);
        self.show(sid, t);
    }

    fn record(&mut self, sid: &str, t: &mut Target, outcome: &str) {
        let Some(st) = &t.for_state else { return };
        let r = store::Outcome {
            value: st.value.clone(),
            source: source_key(&st.source),
            outcome: outcome.to_owned(),
        };
        let saved = store::encode_outcome(&r)
            .and_then(|b| self.cx.store_put(&store::outcome_key(sid, &t.def.id), &b));
        match saved {
            Ok(()) => t.recorded = Some((r.value, r.source)),
            Err(e) => {
                let what = format!("record not saved ({})", status_name(&e));
                self.log(Level::Warn, sid, t, &what);
            }
        }
    }

    fn confirmed(&mut self, sid: &str, t: &mut Target) {
        t.state = TState::Confirmed;
        t.last_error = None;
        t.matched = false;
        t.replied = false;
        t.first = false;
        self.cancel_wake(sid, t);
        self.record(sid, t, store::CONFIRMED);
        self.log(Level::Info, sid, t, "confirmed");
        self.show(sid, t);
    }

    fn overridden(&mut self, sid: &str, t: &mut Target) {
        t.state = TState::Override;
        self.record(sid, t, store::OVERRIDE);
        self.sync_sub(sid, t);
        self.log(Level::Info, sid, t, "override");
        self.show(sid, t);
    }

    /// A good sample of the target's confirm key.
    fn sample(&mut self, sid: &str, t: &mut Target, v: &Value) {
        let Some(expect) = &t.expect else { return };
        if !t.held {
            return;
        }
        let matches = same(expect, v, t.def.tolerance());
        if t.first {
            t.first = false;
            self.cancel_wake(sid, t);
            if matches {
                self.confirmed(sid, t);
            } else {
                self.enqueue(sid, t);
            }
            return;
        }
        match t.state {
            TState::Writing if matches && t.replied => self.confirmed(sid, t),
            TState::Writing | TState::Pending if matches => t.matched = true,
            TState::Retrying if matches => self.confirmed(sid, t),
            TState::Confirmed if !matches => self.overridden(sid, t),
            _ => {}
        }
    }

    /// The last good sample of the target's confirm key already shows the expected value (a
    /// write of an unchanged value brings no new sample).
    fn shows(&self, t: &Target) -> bool {
        let (Some(expect), Some(key)) = (&t.expect, t.def.confirm_key()) else {
            return false;
        };
        t.held
            && self
                .w
                .subs
                .last(key)
                .is_some_and(|v| same(expect, v, t.def.tolerance()))
    }

    /// The reply to the target's write of generation `gen`.
    fn reply(&mut self, sid: &str, t: &mut Target, gen: u64, result: Result<Value, AppError>) {
        if t.gen != gen || t.state != TState::Writing {
            return;
        }
        match result {
            Ok(_) if t.def.confirm == Confirm::Ack || t.matched || self.shows(t) => {
                self.confirmed(sid, t)
            }
            Ok(_) => {
                t.replied = true;
                self.set_wake(sid, t, DueKind::ConfirmTimeout, CONFIRM_TIMEOUT_MS);
            }
            Err(e) => self.failed(sid, t, e),
        }
    }

    /// The target's wake fell due.
    fn due(&mut self, sid: &str, t: &mut Target) {
        let Some(d) = t.wake.take() else { return };
        if d.gen != t.gen {
            return;
        }
        match d.kind {
            DueKind::Retry if t.state == TState::Retrying => {
                self.enqueue(sid, t);
                self.show(sid, t);
            }
            DueKind::ConfirmTimeout if t.state == TState::Writing && t.replied => {
                let e = AppError::new(
                    Status::Timeout,
                    format!(
                        "no matching value {} s after the write",
                        CONFIRM_TIMEOUT_MS / 1000
                    ),
                );
                self.failed(sid, t, e);
            }
            DueKind::FirstSample if t.first => {
                t.first = false;
                self.enqueue(sid, t);
            }
            _ => {}
        }
    }
}

impl Scheduler {
    fn split<'e, 'h>(
        &'e mut self,
        cx: &'e mut Counted<'h>,
        sid: &str,
        tid: &str,
    ) -> Option<(Env<'e, 'h>, &'e mut Target)> {
        let t = self
            .scheds
            .get_mut(sid)?
            .targets
            .iter_mut()
            .find(|t| t.def.id == tid)?;
        let env = Env {
            cx,
            w: &mut self.w,
            wakes: &mut self.wakes,
        };
        Some((env, t))
    }

    fn target(&self, sid: &str, tid: &str) -> Result<&Target, AppError> {
        self.sched(sid)?
            .targets
            .iter()
            .find(|t| t.def.id == tid)
            .ok_or_else(|| AppError::new(Status::NotFound, format!("{sid}/targets/{tid}")))
    }

    /// Target actions check one writer per point against every schedule, so they wait until
    /// the store is loaded.
    pub(crate) fn loaded(&self) -> Result<(), AppError> {
        if !self.pending.is_empty() {
            return Err(AppError::new(
                Status::Busy,
                format!("{} schedules are still loading", self.pending.len()),
            ));
        }
        Ok(())
    }

    /// The schedule's state changed (or it was turned on): its enabled targets write it.
    pub(crate) fn write_targets(&mut self, cx: &mut Counted, sid: &str) {
        let Some(s) = self.scheds.get_mut(sid) else {
            return;
        };
        if !s.c.schedule().enabled {
            return;
        }
        let state = s.state.clone();
        let mut env = Env {
            cx,
            w: &mut self.w,
            wakes: &mut self.wakes,
        };
        for t in s.targets.iter_mut().filter(|t| t.def.enabled) {
            env.begin(sid, t, &state);
        }
    }

    /// A schedule just declared shows its targets: new ones (`fresh`) write the state now, loaded
    /// ones follow the restart rules.
    pub(crate) fn start_targets(&mut self, cx: &mut Counted, sid: &str, fresh: bool) {
        let ids: Vec<String> = match self.scheds.get(sid) {
            Some(s) => s.targets.iter().map(|t| t.def.id.clone()).collect(),
            None => return,
        };
        for tid in ids {
            self.start_target(cx, sid, &tid, fresh);
        }
    }

    fn start_target(&mut self, cx: &mut Counted, sid: &str, tid: &str, fresh: bool) {
        let Some(s) = self.scheds.get_mut(sid) else {
            return;
        };
        let (state, on) = (s.state.clone(), s.c.schedule().enabled);
        let Some(t) = s.targets.iter_mut().find(|t| t.def.id == tid) else {
            return;
        };
        let mut env = Env {
            cx,
            w: &mut self.w,
            wakes: &mut self.wakes,
        };
        if !t.def.enabled {
            t.state = TState::Disabled;
            env.show(sid, t);
        } else if !on {
            // written when the schedule is turned on (R10)
            t.state = TState::Pending;
            env.show(sid, t);
        } else if fresh {
            env.begin(sid, t, &state);
        } else {
            env.resume(sid, t, &state);
        }
    }

    /// Sends queued writes while fewer than [`MAX_INFLIGHT`] wait for a reply; `false` when the
    /// event has no room for the next one.
    pub(crate) fn pump(&mut self, cx: &mut Counted) -> bool {
        while self.w.inflight.len() < MAX_INFLIGHT {
            let Some((sid, tid)) = self.w.queue.front().cloned() else {
                return true;
            };
            let on = self
                .scheds
                .get(&sid)
                .is_some_and(|s| s.c.schedule().enabled);
            let live = match self.split(cx, &sid, &tid) {
                Some((_, t)) if t.queued => {
                    if on && t.state == TState::Pending {
                        true
                    } else {
                        t.queued = false;
                        false
                    }
                }
                _ => false,
            };
            if live && !cx.room(WRITE_COST) {
                return false;
            }
            self.w.queue.pop_front();
            if !live {
                continue;
            }
            if let Some((mut env, t)) = self.split(cx, &sid, &tid) {
                t.queued = false;
                env.send(&sid, t);
            }
        }
        true
    }

    /// The reply to a write: its slot is free whatever became of the target.
    pub(crate) fn reply(&mut self, cx: &mut Counted, req: ReqId, result: Result<Value, AppError>) {
        let Some((sid, tid, gen)) = self.w.inflight.remove(&req) else {
            return;
        };
        if let Some((mut env, t)) = self.split(cx, &sid, &tid) {
            env.reply(&sid, t, gen, result);
        }
    }

    /// A sample of a subscription: to each target that holds it, within the event's room; the
    /// rest waits for the next batches.
    pub(crate) fn value(&mut self, cx: &mut Counted, sub: SubId, sample: Sample) {
        if sample.q != Quality::Good {
            return;
        }
        let Some(holders) = self.w.subs.sample(sub, &sample.v) else {
            return;
        };
        for (sid, tid) in holders {
            if !self.w.deferred.is_empty() || !cx.room(TARGET_COST) {
                self.w.deferred.push_back((sid, tid, sample.v.clone()));
                continue;
            }
            self.sample_to(cx, &sid, &tid, &sample.v);
        }
    }

    fn sample_to(&mut self, cx: &mut Counted, sid: &str, tid: &str, v: &Value) {
        if let Some((mut env, t)) = self.split(cx, sid, tid) {
            env.sample(sid, t, v);
        }
    }

    /// The deferred samples, within the event's room; `false` when it has no room left.
    pub(crate) fn deferred(&mut self, cx: &mut Counted) -> bool {
        while !self.w.deferred.is_empty() {
            if !cx.room(TARGET_COST) {
                return false;
            }
            if let Some((sid, tid, v)) = self.w.deferred.pop_front() {
                self.sample_to(cx, &sid, &tid, &v);
            }
        }
        true
    }

    pub(crate) fn target_due(&mut self, cx: &mut Counted, sid: &str, tid: &str) {
        if let Some((mut env, t)) = self.split(cx, sid, tid) {
            env.due(sid, t);
        }
    }

    /// After a wall-clock step (the heap was cleared): every target's wake again, moved by the
    /// step and kept within its delay from now.
    pub(crate) fn rewake_targets(&mut self, now: Micros, off: Micros) {
        for (sid, s) in &mut self.scheds {
            for t in &mut s.targets {
                if let Some(d) = &mut t.wake {
                    d.at =
                        d.at.saturating_add(off)
                            .clamp(now, now.saturating_add(d.delay));
                    self.wakes
                        .set(Wake::Target(sid.clone(), t.def.id.clone()), Some(d.at));
                }
            }
        }
    }

    /// A removed schedule's (or a replaced one's) targets: subscriptions, wakes and records go.
    pub(crate) fn drop_targets(&mut self, cx: &mut Counted, sid: &str, targets: Vec<Target>) {
        for t in targets {
            let holder = (sid.to_owned(), t.def.id.clone());
            if t.held {
                if let Some(k) = t.def.confirm_key() {
                    self.w.subs.release(cx, k, &holder);
                }
            }
            self.wakes
                .set(Wake::Target(sid.to_owned(), t.def.id.clone()), None);
            cx.store_delete(&store::outcome_key(sid, &t.def.id));
        }
    }

    /// Refuses `point` when a target other than `skip` writes it (one writer per point), or
    /// any target of schedule `skip_sched` (being replaced).
    fn check_writer(
        &self,
        point: &str,
        skip_sched: Option<&str>,
        skip: Option<(&str, &str)>,
    ) -> Result<(), AppError> {
        for (sid, s) in &self.scheds {
            if Some(sid.as_str()) == skip_sched {
                continue;
            }
            for t in &s.targets {
                if Some((sid.as_str(), t.def.id.as_str())) == skip {
                    continue;
                }
                if t.def.point == point {
                    return Err(invalid(
                        "point",
                        format!("{point} is written by {sid}/{}", t.def.id),
                    ));
                }
            }
        }
        Ok(())
    }

    /// Refuses targets whose confirm keys would take the subscriptions over [`MAX_SUBS`]
    /// (counted for every enabled target that confirms on samples, overridden ones too, so a
    /// transition never finds the bound taken).
    fn check_subs(
        &self,
        new: &[&TargetDef],
        skip_sched: Option<&str>,
        skip: Option<(&str, &str)>,
    ) -> Result<(), AppError> {
        let mut keys: HashSet<&str> = HashSet::new();
        for (sid, s) in &self.scheds {
            if Some(sid.as_str()) == skip_sched {
                continue;
            }
            for t in s.targets.iter().filter(|t| t.def.enabled) {
                if Some((sid.as_str(), t.def.id.as_str())) == skip {
                    continue;
                }
                keys.extend(t.def.confirm_key());
            }
        }
        let before = keys.len();
        keys.extend(new.iter().filter_map(|d| d.confirm_key()));
        if keys.len() > MAX_SUBS && keys.len() > before {
            return Err(exhausted(format!(
                "at most {MAX_SUBS} subscriptions (keys targets confirm on) in the scheduler"
            )));
        }
        Ok(())
    }

    /// Subscribes the keys of `defs` the link does not watch yet: the host refuses a key
    /// outside the site or the link's grants (ruling 7). On a refusal nothing stays subscribed.
    fn probe(&self, cx: &mut Counted, defs: &[&TargetDef]) -> Result<Probes, AppError> {
        let mut made = Probes::new();
        for d in defs {
            let keys = std::iter::once(d.point.as_str()).chain(d.feedback.as_deref());
            for k in keys {
                if let Err(e) = self.w.subs.probe(cx, k, &mut made) {
                    Subs::undo(cx, &made);
                    return Err(e);
                }
            }
        }
        Ok(made)
    }

    /// Checks the targets of an import into `sid` (`replacing`: its own points are free) and
    /// subscribes their keys; the caller saves, adopts and sweeps.
    pub(crate) fn check_import(
        &self,
        cx: &mut Counted,
        sid: &str,
        defs: &[TargetDef],
        replacing: bool,
    ) -> Result<Probes, AppError> {
        let skip = replacing.then_some(sid);
        for (i, d) in defs.iter().enumerate() {
            let at = format!("targets[{i}].");
            self.check_writer(&d.point, skip, None)
                .map_err(within(&at))?;
            if let Some(prev) = defs[..i].iter().find(|p| p.point == d.point) {
                return Err(invalid(
                    &format!("{at}point"),
                    format!("{} is written by {sid}/{}", d.point, prev.id),
                ));
            }
        }
        let refs: Vec<&TargetDef> = defs.iter().collect();
        self.check_subs(&refs, skip, None)?;
        self.probe(cx, &refs)
    }

    /// Saves schedule `sid` with the target definitions `defs`.
    fn save_targets(
        &self,
        cx: &mut Counted,
        sid: &str,
        defs: &[TargetDef],
        next: u32,
    ) -> Result<(), AppError> {
        let s = self.sched(sid)?;
        store::replace(cx, sid, &store::encode(s.def(), defs, next)?)
    }

    pub(crate) fn add_target(
        &mut self,
        cx: &mut Counted,
        sid: &str,
        m: &Args,
        who: &Who,
    ) -> Result<Value, AppError> {
        self.loaded()?;
        let s = self.sched(sid)?;
        if s.targets.len() >= MAX_TARGETS {
            return Err(exhausted(format!(
                "{sid}: at most {MAX_TARGETS} targets per schedule"
            )));
        }
        let next = s.next_target;
        let tid = format!("t{next}");
        let def = fields(
            tid.clone(),
            m,
            None,
            who.subject.clone().unwrap_or_default(),
        )?;
        self.check_writer(&def.point, None, None)?;
        self.check_nodes(1, 0)?;
        self.check_subs(&[&def], None, None)?;
        let made = self.probe(cx, &[&def])?;
        let mut defs = s.defs();
        defs.push(def.clone());
        if let Err(e) = self.save_targets(cx, sid, &defs, next.saturating_add(1)) {
            Subs::undo(cx, &made);
            return Err(e);
        }
        self.w.subs.adopt(&made);
        if let Some(s) = self.scheds.get_mut(sid) {
            s.targets.push(Target::new(def));
            s.next_target = next.saturating_add(1);
        }
        self.nodes += 1;
        self.start_target(cx, sid, &tid, true);
        self.w.subs.sweep(cx, &made);
        Ok(Value::Map(BTreeMap::from([(
            "id".to_owned(),
            Value::Str(tid),
        )])))
    }

    pub(crate) fn edit_target(
        &mut self,
        cx: &mut Counted,
        sid: &str,
        tid: &str,
        m: &Args,
    ) -> Result<Value, AppError> {
        self.loaded()?;
        let base = self.target(sid, tid)?.def.clone();
        let def = fields(tid.to_owned(), m, Some(&base), base.created_by.clone())?;
        self.check_writer(&def.point, None, Some((sid, tid)))?;
        self.check_subs(&[&def], None, Some((sid, tid)))?;
        let made = self.probe(cx, &[&def])?;
        let s = self.sched(sid)?;
        let defs: Vec<TargetDef> = s
            .defs()
            .into_iter()
            .map(|d| if d.id == tid { def.clone() } else { d })
            .collect();
        if let Err(e) = self.save_targets(cx, sid, &defs, s.next_target) {
            Subs::undo(cx, &made);
            return Err(e);
        }
        self.w.subs.adopt(&made);
        // the old key is released after the new one is held, so a kept key stays subscribed
        let mut old = None;
        if let Some((mut env, t)) = self.split(cx, sid, tid) {
            if t.held {
                old = base.confirm_key().map(str::to_owned);
            }
            t.held = false;
            t.def = def;
            // the record was for the old definition
            env.forget(sid, t);
        }
        self.start_target(cx, sid, tid, true);
        if let Some(k) = old {
            self.w
                .subs
                .release(cx, &k, &(sid.to_owned(), tid.to_owned()));
        }
        self.w.subs.sweep(cx, &made);
        Ok(Value::Null)
    }

    /// Saves the target's `enabled`.
    fn save_enabled(
        &mut self,
        cx: &mut Counted,
        sid: &str,
        tid: &str,
        on: bool,
    ) -> Result<(), AppError> {
        let s = self.sched(sid)?;
        let defs: Vec<TargetDef> = s
            .defs()
            .into_iter()
            .map(|mut d| {
                if d.id == tid {
                    d.enabled = on;
                }
                d
            })
            .collect();
        self.save_targets(cx, sid, &defs, s.next_target)?;
        if let Some((_, t)) = self.split(cx, sid, tid) {
            t.def.enabled = on;
        }
        Ok(())
    }

    /// Turned on: a transition for the target (R10).
    pub(crate) fn enable_target(
        &mut self,
        cx: &mut Counted,
        sid: &str,
        tid: &str,
    ) -> Result<Value, AppError> {
        self.target(sid, tid)?;
        self.save_enabled(cx, sid, tid, true)?;
        self.start_target(cx, sid, tid, true);
        Ok(Value::Null)
    }

    pub(crate) fn disable_target(
        &mut self,
        cx: &mut Counted,
        sid: &str,
        tid: &str,
    ) -> Result<Value, AppError> {
        self.target(sid, tid)?;
        self.save_enabled(cx, sid, tid, false)?;
        if let Some((mut env, t)) = self.split(cx, sid, tid) {
            // a reply or wake still due belongs to the old generation
            t.gen = env.w.next_gen();
            env.cancel_wake(sid, t);
            t.first = false;
            t.state = TState::Disabled;
            env.sync_sub(sid, t);
            env.show(sid, t);
            // enabled again, it writes; a record would only mislead a restart
            env.forget(sid, t);
        }
        Ok(Value::Null)
    }

    pub(crate) fn remove_target(
        &mut self,
        cx: &mut Counted,
        sid: &str,
        tid: &str,
    ) -> Result<Value, AppError> {
        self.target(sid, tid)?;
        let s = self.sched(sid)?;
        let defs: Vec<TargetDef> = s.defs().into_iter().filter(|d| d.id != tid).collect();
        self.save_targets(cx, sid, &defs, s.next_target)?;
        let Some(s) = self.scheds.get_mut(sid) else {
            return Ok(Value::Null);
        };
        let Some(i) = s.targets.iter().position(|t| t.def.id == tid) else {
            return Ok(Value::Null);
        };
        let t = s.targets.remove(i);
        self.drop_targets(cx, sid, vec![t]);
        cx.remove_node(&tree::target(sid, tid));
        self.nodes -= 1;
        Ok(Value::Null)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn value_keys() {
        assert_eq!(value_key(&Value::Bool(true)).as_deref(), Some("true"));
        assert_eq!(value_key(&Value::UInt(1)).as_deref(), Some("1"));
        assert_eq!(value_key(&Value::Int(-3)).as_deref(), Some("-3"));
        assert_eq!(value_key(&Value::Float(1.0)).as_deref(), Some("1"));
        assert_eq!(value_key(&Value::Float(0.5)).as_deref(), Some("0.5"));
        assert_eq!(value_key(&Value::Str("eco".into())).as_deref(), Some("eco"));
        assert_eq!(value_key(&Value::Null), None);
        assert_eq!(value_key(&Value::Array(vec![])), None);
    }

    #[test]
    fn sameness() {
        let t = DEFAULT_TOLERANCE;
        assert!(same(&Value::UInt(1), &Value::Float(1.000_000_1), t));
        assert!(!same(&Value::UInt(1), &Value::Float(1.1), t));
        assert!(same(&Value::Float(0.0), &Value::Float(1e-7), t));
        assert!(!same(&Value::Float(0.0), &Value::Float(1e-5), t));
        assert!(same(&Value::Bool(true), &Value::UInt(1), t));
        assert!(same(&Value::UInt(0), &Value::Bool(false), t));
        assert!(!same(&Value::Bool(true), &Value::UInt(0), t));
        assert!(same(&Value::Str("a".into()), &Value::Str("a".into()), t));
        assert!(!same(&Value::Str("a".into()), &Value::Str("b".into()), t));
    }

    #[test]
    fn backoff_doubles_to_the_cap_with_jitter() {
        for (attempts, base) in [
            (1, 1_000),
            (2, 2_000),
            (3, 4_000),
            (7, 60_000),
            (40, 60_000),
        ] {
            for now in 0..50 {
                let d = backoff_ms(attempts, now * 7_919, "s", "t1");
                assert!(d >= base * 4 / 5 && d <= base * 6 / 5, "{attempts}: {d}");
            }
        }
    }

    #[test]
    fn point_keys() {
        assert!(check_key("point", "wy/s/downstream/plc/fan").is_ok());
        assert!(check_key("point", "wy/s/downstream/plc/a/b").is_ok());
        for bad in [
            "wy/s/downstream/plc",
            "wy/s/upstream/plc/fan",
            "wy/s/downstream/plc/*",
            "wy/s/downstream/plc/~val",
            "wy/s/downstream//fan",
            "wy/s/downstream/plc/..",
            "zz/s/downstream/plc/fan",
        ] {
            assert!(check_key("point", bad).is_err(), "{bad}");
        }
    }
}
