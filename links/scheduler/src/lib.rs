//! `scheduler`: schedules of events that give a value at times (ADR 0022), as a portable link
//! (ADR 0023). One source runs embedded in `wyrmd`, as a process (`--features process`) and as a
//! WASM component (`--features wasm`).
//!
//! A schedule has a default value, a zone and events (windows and moments, with an RRULE
//! subset, priorities and special days); `wyrm-schedule` evaluates them. The link shows each
//! schedule's value now in `<s>/current` and keeps one wake heap behind one host timer for the
//! next transitions. Definitions live in the host store: `index` (the ids) and `s/<id>`.
//!
//! Bounds (ruling 5): every event buffers at most [`limits::COMMANDS_PER_EVENT`] commands and
//! spends at most [`limits::EVENT_TIME_US`] on batched work; loading a big store, a burst of
//! transitions and a re-evaluation after a clock step go on in `0` ms timer events. The tree
//! stays within [`limits::NODE_BUDGET`] nodes: an add over it is refused.
//!
//! The params (a map, validated in `start`): `default_tz` (IANA name, default `UTC`), the zone
//! of a schedule added without `tz` and of a DSA import (a WASM app cannot read the host zone).

pub mod limits;
mod store;
mod tree;
mod wake;

use std::collections::{BTreeMap, HashMap, VecDeque};

use wyrm_core::{Quality, Sample, Status, Value};
use wyrm_link_api::{App, AppError, Host, Level, TimerId, Who};
use wyrm_schedule::{
    dsa, next_transition, occurrences, schedule_from_value, schedule_to_value, state_at, valid_id,
    validate, value_from_json, value_to_json, Compiled, Event, Invalid, Micros, Rule, Schedule,
    Source, State, MAX_EVENTS,
};

use limits::{Counted, CLOCK_STEP_MS, DEFAULT_ROWS, MAX_ROWS, NODE_BUDGET, WATCHDOG_MS};
use wake::{Fired, Timer, Wake, Wakes};

/// Commands of one transition: the schedule's attributes and `current`.
const TRANSITION_COST: usize = 2;

type Args = BTreeMap<String, Value>;

fn invalid(field: &str, rule: impl std::fmt::Display) -> AppError {
    AppError::new(Status::InvalidParameter, format!("{field}: {rule}"))
}

fn exhausted(msg: impl Into<String>) -> AppError {
    AppError::new(Status::ResourceExhausted, msg)
}

/// A refused schedule; for the event at `ev` its fields are named without `events[ev].`.
fn refused(e: Invalid, ev: Option<usize>) -> AppError {
    let field = match ev {
        Some(i) => e
            .field
            .strip_prefix(&format!("events[{i}]."))
            .unwrap_or(&e.field),
        None => &e.field,
    };
    invalid(field, &e.rule)
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

fn args_of(args: Value) -> Result<Args, AppError> {
    match args {
        Value::Map(m) => Ok(m),
        Value::Null => Ok(Args::new()),
        _ => Err(invalid("args", "a map")),
    }
}

/// Text, or `None` when absent or null.
fn opt_str(m: &Args, k: &str) -> Result<Option<String>, AppError> {
    match m.get(k) {
        None | Some(Value::Null) => Ok(None),
        Some(Value::Str(s)) => Ok(Some(s.clone())),
        Some(_) => Err(invalid(k, "must be text")),
    }
}

fn req_str(m: &Args, k: &str) -> Result<String, AppError> {
    opt_str(m, k)?.ok_or_else(|| invalid(k, "required"))
}

fn opt_bool(m: &Args, k: &str) -> Result<Option<bool>, AppError> {
    match m.get(k) {
        None | Some(Value::Null) => Ok(None),
        Some(Value::Bool(b)) => Ok(Some(*b)),
        Some(_) => Err(invalid(k, "must be true or false")),
    }
}

/// A whole number, or `None` when absent or null.
fn opt_uint(m: &Args, k: &str) -> Result<Option<u64>, AppError> {
    let bad = || invalid(k, "must be a whole number from 0");
    match m.get(k) {
        None | Some(Value::Null) => Ok(None),
        Some(Value::UInt(n)) => Ok(Some(*n)),
        Some(Value::Int(n)) => u64::try_from(*n).map(Some).map_err(|_| bad()),
        Some(Value::Float(f)) if f.fract() == 0.0 && *f >= 0.0 && *f < 1e15 => Ok(Some(*f as u64)),
        Some(_) => Err(bad()),
    }
}

/// An RFC 3339 instant, or a date (its midnight UTC).
fn parse_instant(s: &str) -> Option<Micros> {
    let s = s.trim();
    if let Ok(t) = s.parse::<jiff::Timestamp>() {
        return Some(t.as_microsecond());
    }
    let d: jiff::civil::Date = s.parse().ok()?;
    d.to_zoned(jiff::tz::TimeZone::UTC)
        .ok()
        .map(|z| z.timestamp().as_microsecond())
}

/// `<from>/<to>` (or `<from>..<to>`), from before to.
fn parse_timerange(s: &str) -> Result<(Micros, Micros), AppError> {
    let bad = || {
        invalid(
            "timerange",
            format!("expected <from>/<to> in RFC 3339, from before to, got {s:?}"),
        )
    };
    let (a, b) = s
        .split_once("..")
        .or_else(|| s.split_once('/'))
        .ok_or_else(bad)?;
    let (from, to) = (
        parse_instant(a).ok_or_else(bad)?,
        parse_instant(b).ok_or_else(bad)?,
    );
    if from >= to {
        return Err(bad());
    }
    Ok((from, to))
}

/// `default_tz` from the params; any other key is refused, naming it.
fn params(config: &Value) -> Result<String, AppError> {
    let m = match config {
        Value::Map(m) => m,
        Value::Null => return Ok("UTC".into()),
        _ => return Err(invalid("params", "a map")),
    };
    let mut tz = "UTC".to_owned();
    for (k, v) in m {
        match (k.as_str(), v) {
            ("default_tz", Value::Str(s)) => {
                if jiff::tz::TimeZone::get(s).is_err() {
                    return Err(invalid(
                        "params.default_tz",
                        format!("unknown IANA time zone {s:?}"),
                    ));
                }
                tz = s.clone();
            }
            ("default_tz", _) => {
                return Err(invalid("params.default_tz", "an IANA time zone name"))
            }
            (k, _) => return Err(invalid(&format!("params.{k}"), "unknown")),
        }
    }
    Ok(tz)
}

/// The fields of `add_event` (`base` = `None`, `value`, `start`, `end` required) or of an
/// event's `edit` over `base` (absent or null keeps a field; an empty `recurrence` clears it).
fn event_from(id: String, m: &Args, base: Option<&Event>) -> Result<Event, AppError> {
    let local = |k: &str| -> Result<Option<_>, AppError> {
        opt_str(m, k)?
            .map(|t| wyrm_schedule::parse_local(k, &t).map_err(|e| refused(e, None)))
            .transpose()
    };
    let required = |k: &str| invalid(k, "required");
    let value = match (m.get("value"), base) {
        (Some(v), None) => v.clone(),
        (None, None) => return Err(required("value")),
        (None | Some(Value::Null), Some(b)) => b.value.clone(),
        (Some(v), Some(_)) => v.clone(),
    };
    let start = match (local("start")?, base) {
        (Some(t), _) => t,
        (None, Some(b)) => b.start,
        (None, None) => return Err(required("start")),
    };
    let end = match (local("end")?, base) {
        (Some(t), _) => t,
        (None, Some(b)) => b.end,
        (None, None) => return Err(required("end")),
    };
    let recurrence = match opt_str(m, "recurrence")? {
        Some(t) if t.trim().is_empty() => None,
        Some(t) => Some(
            t.parse::<Rule>()
                .map_err(|e| invalid("recurrence", format!("{}: {}", e.field, e.rule)))?,
        ),
        None => base.and_then(|b| b.recurrence.clone()),
    };
    let priority = match opt_uint(m, "priority")? {
        Some(p) => u8::try_from(p).map_err(|_| invalid("priority", "must be 0 to 9"))?,
        None => base.map_or(0, |b| b.priority),
    };
    Ok(Event {
        id,
        display: opt_str(m, "display")?
            .or_else(|| base.map(|b| b.display.clone()))
            .unwrap_or_default(),
        value,
        priority,
        special: opt_bool(m, "special")?
            .or(base.map(|b| b.special))
            .unwrap_or(false),
        start,
        end,
        recurrence,
    })
}

/// The window state now, or the moment the schedule holds: a moment that fired is kept until
/// the next transition after it (ruling 8), while its event still gives that value.
fn eval_now(c: &Compiled, now: Micros, held: &State) -> State {
    if let Source::Moment { id, at } = &held.source {
        let still = c
            .schedule()
            .events
            .iter()
            .any(|e| &e.id == id && e.value == held.value);
        if still && *at <= now && next_transition(c, *at).is_none_or(|(t, _)| t > now) {
            return held.clone();
        }
    }
    state_at(c, now)
}

/// One loaded schedule.
struct Sched {
    c: Compiled,
    /// The state the tree shows.
    state: State,
    /// The next transition (none while disabled).
    next: Option<(Micros, State)>,
}

impl Sched {
    fn def(&self) -> &Schedule {
        self.c.schedule()
    }
}

/// The app.
pub struct Scheduler {
    default_tz: String,
    /// Every schedule id of the store, in order; loaded, waiting to load, or unreadable.
    index: Vec<String>,
    scheds: HashMap<String, Sched>,
    /// Ids to load and declare, in batches.
    pending: VecDeque<String>,
    /// Ids to evaluate again after a clock step, in batches.
    reeval: VecDeque<String>,
    /// Nodes of the tree the app declared (the root and its actions not counted).
    nodes: usize,
    wakes: Wakes,
    timer: Timer,
}

impl Scheduler {
    /// The earliest wake of the heap (wall clock, microseconds).
    pub fn next_wake(&self) -> Option<Micros> {
        self.wakes.next_live()
    }

    /// Refuses `add` more nodes (after `freed` go) over the node budget.
    fn check_nodes(&self, add: usize, freed: usize) -> Result<(), AppError> {
        if self.nodes - freed + add > NODE_BUDGET {
            return Err(exhausted(format!(
                "at most {NODE_BUDGET} nodes in the scheduler ({} used)",
                self.nodes
            )));
        }
        Ok(())
    }

    fn sched(&self, id: &str) -> Result<&Sched, AppError> {
        self.scheds
            .get(id)
            .ok_or_else(|| AppError::new(Status::NotFound, id.to_owned()))
    }

    /// Declares a compiled schedule's nodes, shows its state now and sets its next wake.
    fn declare(&mut self, cx: &mut Counted, c: Compiled, now: Micros) {
        let def = c.schedule();
        let id = def.id.clone();
        let state = state_at(&c, now);
        let next = if def.enabled {
            next_transition(&c, now)
        } else {
            None
        };
        cx.declare_node(&id, tree::schedule_meta(def, &state, next.as_ref()));
        cx.declare_node(&tree::current(&id), tree::current_meta());
        cx.declare_node(&tree::default(&id), tree::default_meta());
        let s = good(cx, def.default.clone());
        cx.update(&tree::default(&id), s);
        cx.declare_node(&tree::enabled(&id), tree::enabled_meta());
        let s = good(cx, Value::Bool(def.enabled));
        cx.update(&tree::enabled(&id), s);
        cx.declare_node(&tree::events(&id), tree::events_meta());
        for e in &def.events {
            cx.declare_node(&tree::event(&id, &e.id), tree::event_meta(e));
        }
        cx.declare_node(&tree::targets(&id), tree::targets_meta());
        self.nodes += tree::nodes_of(def);
        self.wakes
            .set(Wake::Transition(id.clone()), next.as_ref().map(|n| n.0));
        self.scheds.insert(id.clone(), Sched { c, state, next });
        self.apply(cx, &id);
    }

    /// The schedule's state changed: `current` shows it (Task 4: and its targets are written).
    fn apply(&mut self, cx: &mut Counted, id: &str) {
        let Some(s) = self.scheds.get(id) else { return };
        let v = good(cx, s.state.value.clone());
        cx.update(&tree::current(id), v);
    }

    /// Re-declares the schedule node with its attributes now.
    fn show(&self, cx: &mut Counted, id: &str) {
        if let Some(s) = self.scheds.get(id) {
            cx.declare_node(id, tree::schedule_meta(s.def(), &s.state, s.next.as_ref()));
        }
    }

    /// Evaluates a schedule at `now` after an edit, a clock step or `enabled` turned on: a
    /// different state is a transition (`force`: one anyway); the attributes are shown again
    /// when anything they show changed (`show`: anyway).
    fn refresh(&mut self, cx: &mut Counted, id: &str, now: Micros, show: bool, force: bool) {
        let Some(s) = self.scheds.get_mut(id) else {
            return;
        };
        let state = eval_now(&s.c, now, &s.state);
        let next = if s.def().enabled {
            next_transition(&s.c, now)
        } else {
            None
        };
        let changed = state != s.state;
        let moved = next != s.next;
        s.state = state;
        s.next = next;
        self.wakes.set(
            Wake::Transition(id.to_owned()),
            s.next.as_ref().map(|n| n.0),
        );
        if changed || moved || show {
            self.show(cx, id);
        }
        if changed || force {
            self.apply(cx, id);
        }
    }

    /// A wake fell due.
    fn fire(&mut self, cx: &mut Counted, wake: Wake, now: Micros) {
        match wake {
            Wake::Transition(id) => self.transition(cx, &id, now),
        }
    }

    /// The schedule's next transition fell due. On time, its state is the precomputed one (a
    /// moment included); late (a wake held back past the step tolerance), the window state now
    /// (a missed moment is not replayed).
    fn transition(&mut self, cx: &mut Counted, id: &str, now: Micros) {
        let Some(s) = self.scheds.get_mut(id) else {
            return;
        };
        let Some((at, next_state)) = s.next.take() else {
            return;
        };
        let late = now.saturating_sub(at) > (CLOCK_STEP_MS * 1000) as Micros;
        let (mut state, from) = if late {
            (state_at(&s.c, now), now)
        } else {
            (next_state, at)
        };
        let mut next = next_transition(&s.c, from);
        if next.as_ref().is_some_and(|(t, _)| *t <= now) {
            state = state_at(&s.c, now);
            next = next_transition(&s.c, now);
        }
        let changed = state != s.state;
        s.state = state;
        s.next = next;
        self.wakes.set(
            Wake::Transition(id.to_owned()),
            s.next.as_ref().map(|n| n.0),
        );
        self.show(cx, id);
        if changed {
            self.apply(cx, id);
        }
    }

    /// Loads and declares the first schedule waiting; `false` when the event has no room for it.
    fn load_next(&mut self, cx: &mut Counted, now: Micros) -> bool {
        let Some(id) = self.pending.front().cloned() else {
            return true;
        };
        let def = match store::load_schedule(cx, &id) {
            Ok(d) => d,
            Err(e) => {
                self.pending.pop_front();
                cx.log(Level::Warn, &format!("schedule {id}: not loaded: {e}"));
                return true;
            }
        };
        let c = match Compiled::new(&def) {
            Ok(c) => c,
            Err(e) => {
                self.pending.pop_front();
                cx.log(Level::Warn, &format!("schedule {id}: not loaded: {e}"));
                return true;
            }
        };
        if !cx.room(tree::declare_cost(&def)) {
            return false;
        }
        self.pending.pop_front();
        if let Err(e) = self.check_nodes(tree::nodes_of(&def), 0) {
            cx.log(
                Level::Warn,
                &format!("schedule {id}: not loaded: {}", e.msg),
            );
            return true;
        }
        self.declare(cx, c, now);
        if self.pending.is_empty() {
            let n = self.scheds.len();
            cx.log(Level::Info, &format!("{n} schedules loaded"));
        }
        true
    }

    /// Batched work, within the event's command and time budget: schedules to load, schedules
    /// to evaluate again, then due wakes. What is left waits for a `0` ms timer.
    fn run(&mut self, cx: &mut Counted) {
        let now = now_of(cx);
        loop {
            if !self.pending.is_empty() {
                if !cx.room(tree::declare_cost_min()) || !self.load_next(cx, now) {
                    return;
                }
                continue;
            }
            if let Some(id) = self.reeval.front().cloned() {
                if !cx.room(TRANSITION_COST) {
                    return;
                }
                self.reeval.pop_front();
                self.refresh(cx, &id, now, false, false);
                continue;
            }
            if self.wakes.peek_due(now).is_none() || !cx.room(TRANSITION_COST) {
                return;
            }
            if let Some((_, wake)) = self.wakes.pop_due(now) {
                self.fire(cx, wake, now);
            }
        }
    }

    /// Arms the one host timer: `0` ms while batched work waits, else for the earliest wake,
    /// and the watchdog while any schedule is enabled.
    fn arm(&mut self, cx: &mut Counted) {
        let now = now_of(cx);
        let next = if !self.pending.is_empty() || !self.reeval.is_empty() {
            Some(now)
        } else {
            self.wakes.earliest().or_else(|| {
                self.scheds
                    .values()
                    .any(|s| s.def().enabled)
                    .then(|| now.saturating_add((WATCHDOG_MS * 1000) as Micros))
            })
        };
        if let Err(e) = self.timer.arm(cx, now, next) {
            cx.log(Level::Error, &format!("{}", wake::no_timer(e)));
        }
    }

    /// The wall clock stepped: evaluate every enabled schedule again and rebuild the heap.
    fn clock_step(&mut self, cx: &mut Counted, off: Micros) {
        self.wakes.clear();
        self.reeval = self
            .index
            .iter()
            .filter(|id| self.scheds.get(*id).is_some_and(|s| s.def().enabled))
            .cloned()
            .collect();
        cx.log(
            Level::Info,
            &format!(
                "wall clock stepped by {} ms: evaluating {} schedules again",
                off / 1000,
                self.reeval.len()
            ),
        );
    }

    fn add_new(&mut self, cx: &mut Counted, def: Schedule, now: Micros) -> Result<(), AppError> {
        let c = Compiled::new(&def).map_err(|e| refused(e, None))?;
        self.check_nodes(tree::nodes_of(&def), 0)?;
        let mut ids = self.index.clone();
        ids.push(def.id.clone());
        store::add(cx, &def, &ids)?;
        self.index = ids;
        self.declare(cx, c, now);
        Ok(())
    }

    /// Replaces a schedule of the index (loaded, waiting or unreadable) as a whole.
    fn replace_whole(
        &mut self,
        cx: &mut Counted,
        def: Schedule,
        now: Micros,
    ) -> Result<(), AppError> {
        let c = Compiled::new(&def).map_err(|e| refused(e, None))?;
        let old = self
            .scheds
            .get(&def.id)
            .map_or(0, |s| tree::nodes_of(s.def()));
        self.check_nodes(tree::nodes_of(&def), old)?;
        store::replace(cx, &def)?;
        self.pending.retain(|p| p != &def.id);
        if self.scheds.remove(&def.id).is_some() {
            cx.remove_node(&def.id);
            self.nodes -= old;
        }
        self.declare(cx, c, now);
        Ok(())
    }

    fn add_schedule(&mut self, cx: &mut Counted, m: &Args, now: Micros) -> Result<Value, AppError> {
        let id = req_str(m, "id")?;
        let def = Schedule {
            display: opt_str(m, "display")?.unwrap_or_else(|| id.clone()),
            tz: opt_str(m, "tz")?
                .filter(|t| !t.is_empty())
                .unwrap_or_else(|| self.default_tz.clone()),
            default: m
                .get("default")
                .cloned()
                .ok_or_else(|| invalid("default", "required"))?,
            enabled: opt_bool(m, "enabled")?.unwrap_or(true),
            events: Vec::new(),
            next_event: 1,
            id,
        };
        validate(&def).map_err(|e| refused(e, None))?;
        if self.index.contains(&def.id) {
            return Err(invalid("id", format!("{} exists", def.id)));
        }
        self.add_new(cx, def, now)?;
        Ok(Value::Null)
    }

    fn import(&mut self, cx: &mut Counted, m: &Args, now: Micros) -> Result<Value, AppError> {
        let json = req_str(m, "json")?;
        let id = opt_str(m, "id")?.filter(|i| !i.is_empty());
        let overwrite = opt_bool(m, "overwrite")?.unwrap_or(false);
        let parsed: serde_json::Value = serde_json::from_str(&json)
            .map_err(|e| invalid("json", format!("not valid JSON: {e}")))?;
        let def = if parsed.get("format").is_some() {
            // Task 4 models the export's targets
            let (mut s, _targets) =
                schedule_from_value(&value_from_json(&parsed)).map_err(|e| refused(e, None))?;
            if let Some(id) = id {
                s.id = id;
                validate(&s).map_err(|e| refused(e, None))?;
            }
            s
        } else {
            let id = match (id, parsed.get("name")) {
                (Some(id), _) => id,
                (None, Some(serde_json::Value::String(n))) if valid_id(n) => n.clone(),
                _ => {
                    return Err(invalid(
                        "id",
                        "required: the DSA export's name is not an id",
                    ))
                }
            };
            dsa::import(&json, &id, &self.default_tz).map_err(|e| refused(e, None))?
        };
        let id = def.id.clone();
        if self.index.contains(&id) {
            if !overwrite {
                return Err(invalid(
                    "id",
                    format!("{id} exists (overwrite: true replaces it)"),
                ));
            }
            self.replace_whole(cx, def, now)?;
        } else {
            self.add_new(cx, def, now)?;
        }
        Ok(Value::Map(BTreeMap::from([(
            "id".to_owned(),
            Value::Str(id),
        )])))
    }

    /// Saves an edited definition of loaded schedule `id` and compiles it in.
    fn save(&mut self, cx: &mut Counted, def: Schedule, ev: Option<usize>) -> Result<(), AppError> {
        let c = Compiled::new(&def).map_err(|e| refused(e, ev))?;
        store::replace(cx, &def)?;
        if let Some(s) = self.scheds.get_mut(&def.id) {
            s.c = c;
        }
        Ok(())
    }

    fn add_event(
        &mut self,
        cx: &mut Counted,
        sid: &str,
        m: &Args,
        now: Micros,
    ) -> Result<Value, AppError> {
        let mut def = self.sched(sid)?.def().clone();
        if def.events.len() >= MAX_EVENTS {
            return Err(exhausted(format!(
                "{sid}: at most {MAX_EVENTS} events per schedule"
            )));
        }
        let eid = format!("e{}", def.next_event);
        def.events.push(event_from(eid.clone(), m, None)?);
        def.next_event = def.next_event.saturating_add(1);
        self.check_nodes(1, 0)?;
        let i = def.events.len() - 1;
        let meta = tree::event_meta(&def.events[i]);
        self.save(cx, def, Some(i))?;
        cx.declare_node(&tree::event(sid, &eid), meta);
        self.nodes += 1;
        self.refresh(cx, sid, now, false, false);
        Ok(Value::Map(BTreeMap::from([(
            "id".to_owned(),
            Value::Str(eid),
        )])))
    }

    fn get_events(&self, sid: &str, m: &Args) -> Result<Value, AppError> {
        let s = self.sched(sid)?;
        let (from, to) = parse_timerange(&req_str(m, "timerange")?)?;
        let limit = match opt_uint(m, "limit")? {
            None => DEFAULT_ROWS,
            Some(n) if (1..=MAX_ROWS as u64).contains(&n) => n as usize,
            Some(_) => return Err(invalid("limit", format!("must be 1 to {MAX_ROWS}"))),
        };
        let rows = occurrences(&s.c, from, to, limit)
            .into_iter()
            .map(|o| {
                Value::Map(BTreeMap::from([
                    ("start".to_owned(), tree::rfc3339(o.start)),
                    ("end".to_owned(), tree::rfc3339(o.end)),
                    ("event".to_owned(), Value::Str(o.event)),
                    ("value".to_owned(), o.value),
                    ("priority".to_owned(), Value::UInt(u64::from(o.priority))),
                    ("special".to_owned(), Value::Bool(o.special)),
                ]))
            })
            .collect();
        Ok(Value::Array(rows))
    }

    fn export(&self, sid: &str) -> Result<Value, AppError> {
        let s = self.sched(sid)?;
        let json = value_to_json(&schedule_to_value(s.def())).to_string();
        Ok(Value::Map(BTreeMap::from([(
            "json".to_owned(),
            Value::Str(json),
        )])))
    }

    fn edit_schedule(
        &mut self,
        cx: &mut Counted,
        sid: &str,
        m: &Args,
        now: Micros,
    ) -> Result<Value, AppError> {
        let old = self.sched(sid)?.def().clone();
        let mut def = old.clone();
        if let Some(d) = opt_str(m, "display")? {
            def.display = d;
        }
        if let Some(t) = opt_str(m, "tz")?.filter(|t| !t.is_empty()) {
            def.tz = t;
        }
        match m.get("default") {
            None | Some(Value::Null) => {}
            Some(v) => def.default = v.clone(),
        }
        self.save(cx, def.clone(), None)?;
        if def.default != old.default {
            let s = good(cx, def.default);
            cx.update(&tree::default(sid), s);
        }
        self.refresh(cx, sid, now, true, false);
        Ok(Value::Null)
    }

    fn remove_schedule(&mut self, cx: &mut Counted, sid: &str) -> Result<Value, AppError> {
        let n = tree::nodes_of(self.sched(sid)?.def());
        let ids: Vec<String> = self.index.iter().filter(|i| *i != sid).cloned().collect();
        store::remove(cx, sid, &ids)?;
        self.index = ids;
        self.scheds.remove(sid);
        self.nodes -= n;
        self.wakes.set(Wake::Transition(sid.to_owned()), None);
        cx.remove_node(sid);
        Ok(Value::Null)
    }

    /// The index of event `eid` in schedule `sid`.
    fn event_at(&self, sid: &str, eid: &str) -> Result<usize, AppError> {
        self.sched(sid)?
            .def()
            .events
            .iter()
            .position(|e| e.id == eid)
            .ok_or_else(|| AppError::new(Status::NotFound, format!("{sid}/events/{eid}")))
    }

    fn edit_event(
        &mut self,
        cx: &mut Counted,
        sid: &str,
        eid: &str,
        m: &Args,
        now: Micros,
    ) -> Result<Value, AppError> {
        let i = self.event_at(sid, eid)?;
        let mut def = self.sched(sid)?.def().clone();
        def.events[i] = event_from(eid.to_owned(), m, Some(&def.events[i]))?;
        let meta = tree::event_meta(&def.events[i]);
        self.save(cx, def, Some(i))?;
        cx.declare_node(&tree::event(sid, eid), meta);
        self.refresh(cx, sid, now, false, false);
        Ok(Value::Null)
    }

    fn remove_event(
        &mut self,
        cx: &mut Counted,
        sid: &str,
        eid: &str,
        now: Micros,
    ) -> Result<Value, AppError> {
        let i = self.event_at(sid, eid)?;
        let mut def = self.sched(sid)?.def().clone();
        def.events.remove(i);
        self.save(cx, def, None)?;
        cx.remove_node(&tree::event(sid, eid));
        self.nodes -= 1;
        self.refresh(cx, sid, now, false, false);
        Ok(Value::Null)
    }

    fn invoke(
        &mut self,
        cx: &mut Counted,
        path: &str,
        action: &str,
        m: &Args,
    ) -> Result<Value, AppError> {
        let now = now_of(cx);
        let unknown = || AppError::new(Status::NotSupported, format!("{path:?}: no {action}"));
        let parts: Vec<&str> = if path.is_empty() {
            Vec::new()
        } else {
            path.split('/').collect()
        };
        match (parts.as_slice(), action) {
            ([], "add_schedule") => self.add_schedule(cx, m, now),
            ([], "import") => self.import(cx, m, now),
            ([s], "add_event") => self.add_event(cx, s, m, now),
            ([s], "get_events") => self.get_events(s, m),
            ([s], "export") => self.export(s),
            ([s], "edit") => self.edit_schedule(cx, s, m, now),
            ([s], "remove") => self.remove_schedule(cx, s),
            ([s, "events", e], "edit") => self.edit_event(cx, s, e, m, now),
            ([s, "events", e], "remove") => self.remove_event(cx, s, e, now),
            _ => Err(unknown()),
        }
    }

    fn set(&mut self, cx: &mut Counted, path: &str, value: Value) -> Result<(), AppError> {
        let now = now_of(cx);
        let Some((sid, leaf)) = path.split_once('/') else {
            return Err(AppError::new(Status::NotFound, path.to_owned()));
        };
        let mut def = self.sched(sid)?.def().clone();
        match leaf {
            "default" => {
                def.default = value.clone();
                self.save(cx, def, None)?;
                let s = good(cx, value);
                cx.update(path, s);
                self.refresh(cx, sid, now, false, false);
            }
            "enabled" => {
                let Value::Bool(on) = value else {
                    return Err(invalid("enabled", "must be true or false"));
                };
                let was = def.enabled;
                def.enabled = on;
                self.save(cx, def, None)?;
                let s = good(cx, Value::Bool(on));
                cx.update(path, s);
                // `enabled` turned on is a transition (ADR 0022)
                self.refresh(cx, sid, now, false, on && !was);
            }
            _ => return Err(AppError::new(Status::NotFound, path.to_owned())),
        }
        Ok(())
    }
}

impl App for Scheduler {
    const NAME: &'static str = "scheduler";
    const VERSION: &'static str = env!("CARGO_PKG_VERSION");

    fn start(host: &mut dyn Host, config: Value) -> Result<Self, AppError> {
        let default_tz = params(&config)?;
        let mut cx = Counted::new(host);
        for (name, a) in tree::root_actions() {
            cx.declare_action("", name, a);
        }
        let index = match store::load_index(&cx) {
            Ok(i) => i,
            Err(e) => {
                cx.log(Level::Error, &format!("store index unreadable: {e}"));
                Vec::new()
            }
        };
        let mut app = Scheduler {
            default_tz,
            pending: index.iter().cloned().collect(),
            index,
            scheds: HashMap::new(),
            reeval: VecDeque::new(),
            nodes: 0,
            wakes: Wakes::default(),
            timer: Timer::default(),
        };
        app.run(&mut cx);
        app.arm(&mut cx);
        Ok(app)
    }

    fn on_set(
        &mut self,
        host: &mut dyn Host,
        path: &str,
        value: Value,
        _who: &Who,
    ) -> Result<(), AppError> {
        let mut cx = Counted::new(host);
        let r = self.set(&mut cx, path, value);
        self.arm(&mut cx);
        r
    }

    fn on_invoke(
        &mut self,
        host: &mut dyn Host,
        path: &str,
        action: &str,
        args: Value,
        _who: &Who,
    ) -> Result<Value, AppError> {
        let m = args_of(args)?;
        let mut cx = Counted::new(host);
        let r = self.invoke(&mut cx, path, action, &m);
        if r.is_ok() {
            self.arm(&mut cx);
        }
        r
    }

    fn on_timer(&mut self, host: &mut dyn Host, timer: TimerId) {
        let mut cx = Counted::new(host);
        let now = now_of(&cx);
        match self.timer.fired(timer, now) {
            Fired::Stale => return,
            Fired::Ok => {}
            Fired::Step(off) => self.clock_step(&mut cx, off),
        }
        self.run(&mut cx);
        self.arm(&mut cx);
    }
}

// Only on wasm32: natively the exports would be bare global `start`/`stop`… symbols.
#[cfg(all(feature = "wasm", target_arch = "wasm32"))]
wyrm_link_guest::export!(Scheduler);
