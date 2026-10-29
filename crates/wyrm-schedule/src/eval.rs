//! Evaluation (ADR 0022 "Model"): the window state of a schedule at an instant, its next
//! transition, and its occurrences for a timeline.
//!
//! Precedence at an instant: on a special day (a local day that some special event's occurrence
//! touches) only special events count. Among the active windows the winner is the minimum of
//! `(rank, later start first, event number)`, where the rank is the priority for 1…9 and 10 for 0.
//! No active window gives the default. Moments are never active; `next_transition` reports one
//! when it beats every window active at its instant.

use std::cmp::Reverse;
use std::collections::{BTreeSet, BinaryHeap};
use std::iter::Peekable;

use jiff::civil::{Date, DateTime, Time};
use jiff::tz::TimeZone;
use jiff::{SignedDuration, Timestamp};
use wyrm_core::Value;

use crate::model::{validate, Invalid, Micros, Schedule};
use crate::occur::{day_number, from_day_number, to_instant, to_local, Recur, Starts};

/// How far ahead `next_transition` looks.
pub const HORIZON_DAYS: i64 = 366;

const DAY_MICROS: i64 = 86_400_000_000;

/// One event, ready to evaluate.
#[derive(Debug, Clone)]
struct Ev {
    /// `n` of the id `e<n>`: the last tie-break, in numeric order.
    num: u32,
    /// Priority 1…9, and 10 for priority 0 (the lowest).
    rank: u8,
    special: bool,
    /// `start == end`: a value written once, never an active window.
    moment: bool,
    /// The window length in civil time (the wall-clock length is kept on DST days).
    span: SignedDuration,
    recur: Recur,
}

/// A validated schedule with its zone and its events' rules resolved.
#[derive(Debug, Clone)]
pub struct Compiled {
    schedule: Schedule,
    tz: TimeZone,
    events: Vec<Ev>,
    has_special: bool,
}

impl Compiled {
    pub fn new(s: &Schedule) -> Result<Compiled, Invalid> {
        validate(s)?;
        let tz = TimeZone::get(&s.tz)
            .map_err(|_| Invalid::new("tz", format!("unknown IANA time zone {:?}", s.tz)))?;
        let events: Vec<Ev> = s
            .events
            .iter()
            .map(|e| Ev {
                num: e.id[1..].parse().unwrap_or(u32::MAX),
                rank: if e.priority == 0 { 10 } else { e.priority },
                special: e.special,
                moment: e.start == e.end,
                span: e.end.duration_since(e.start),
                recur: Recur::new(e),
            })
            .collect();
        Ok(Compiled {
            schedule: s.clone(),
            tz,
            has_special: events.iter().any(|e| e.special),
            events,
        })
    }

    pub fn schedule(&self) -> &Schedule {
        &self.schedule
    }
}

/// Where a state comes from: the default, a window occurrence (by its start), or a moment.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Source {
    Default,
    Event { id: String, at: Micros },
    Moment { id: String, at: Micros },
}

#[derive(Debug, Clone, PartialEq)]
pub struct State {
    pub value: Value,
    pub source: Source,
}

/// One occurrence of an event, for a timeline. A moment has `start == end`.
#[derive(Debug, Clone, PartialEq)]
pub struct Occurrence {
    pub event: String,
    pub start: Micros,
    pub end: Micros,
    pub value: Value,
    pub priority: u8,
    pub special: bool,
}

/// One occurrence as instants.
#[derive(Debug, Clone, Copy)]
struct Occ {
    ev: usize,
    start: Micros,
    end: Micros,
}

/// One event's occurrences as instants, in order of start.
struct Occs<'a> {
    c: &'a Compiled,
    ev: usize,
    starts: Starts<'a>,
}

impl Iterator for Occs<'_> {
    type Item = Occ;

    fn next(&mut self) -> Option<Occ> {
        let s = self.starts.next()?;
        let e = s.checked_add(self.c.events[self.ev].span).ok()?;
        Some(Occ {
            ev: self.ev,
            start: to_instant(&self.c.tz, s)?,
            end: to_instant(&self.c.tz, e)?,
        })
    }
}

/// Event `ev`'s occurrences from the period before the one that holds `from`, up to the
/// periods that begin on `stop`.
fn occs(c: &Compiled, ev: usize, from: DateTime, stop: Date) -> Occs<'_> {
    Occs {
        c,
        ev,
        starts: c.events[ev].recur.starts(from, stop),
    }
}

/// The ordering of precedence: the smallest key wins.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
struct Key {
    rank: u8,
    later: Reverse<Micros>,
    num: u32,
    ev: usize,
    /// Tells apart two windows of one event with the same start (in the sweep's sets).
    seq: u64,
}

impl Key {
    fn of(c: &Compiled, ev: usize, start: Micros, seq: u64) -> Key {
        Key {
            rank: c.events[ev].rank,
            later: Reverse(start),
            num: c.events[ev].num,
            ev,
            seq,
        }
    }

    fn beats(&self, other: &Key) -> bool {
        (self.rank, self.later, self.num) < (other.rank, other.later, other.num)
    }
}

fn add_days(d: Date, n: i64) -> Date {
    from_day_number(day_number(d) + n).unwrap_or(Date::MAX)
}

/// The instants of a local day: `[D 00:00, D+1 00:00)`, both ends mapped with the zone's rules.
fn day_bounds(c: &Compiled, d: Date) -> Option<(Micros, Micros)> {
    let next = from_day_number(day_number(d) + 1)?;
    Some((
        to_instant(&c.tz, d.to_datetime(Time::midnight()))?,
        to_instant(&c.tz, next.to_datetime(Time::midnight()))?,
    ))
}

fn touches(c: &Compiled, o: &Occ, d0: Micros, d1: Micros) -> bool {
    if c.events[o.ev].moment {
        d0 <= o.start && o.start < d1
    } else {
        o.start < d1 && o.end > d0
    }
}

/// Whether some special event has an occurrence (window or moment) that touches local day `d`.
fn special_day(c: &Compiled, d: Date) -> bool {
    let Some((d0, d1)) = day_bounds(c, d) else {
        return false;
    };
    let from = d.to_datetime(Time::midnight());
    let stop = add_days(d, 2);
    (0..c.events.len())
        .filter(|&i| c.events[i].special)
        .any(|i| {
            occs(c, i, from, stop)
                .take_while(|o| o.start < d1)
                .any(|o| touches(c, &o, d0, d1))
        })
}

fn state_of(c: &Compiled, win: Option<Key>) -> State {
    match win {
        None => State {
            value: c.schedule.default.clone(),
            source: Source::Default,
        },
        Some(k) => {
            let e = &c.schedule.events[k.ev];
            State {
                value: e.value.clone(),
                source: Source::Event {
                    id: e.id.clone(),
                    at: k.later.0,
                },
            }
        }
    }
}

/// The window state at `t`: the winning active window, or the default. Never a moment (a
/// missed moment is not replayed).
pub fn state_at(c: &Compiled, t: Micros) -> State {
    let Some(local) = to_local(&c.tz, t) else {
        return state_of(c, None);
    };
    let special = c.has_special && special_day(c, local.date());
    let stop = add_days(local.date(), 2);
    let mut best: Option<Key> = None;
    for (i, ev) in c.events.iter().enumerate() {
        if ev.moment || (special && !ev.special) {
            continue;
        }
        for o in occs(c, i, local, stop).take_while(|o| o.start <= t) {
            if t < o.end {
                let k = Key::of(c, i, o.start, 0);
                if best.is_none_or(|b| k < b) {
                    best = Some(k);
                }
            }
        }
    }
    state_of(c, best)
}

/// What happens at a boundary of the sweep.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
enum Item {
    /// The next occurrence of this event starts.
    Start(usize),
    /// This window ends.
    End(Key),
    /// A local day begins (only with special events).
    Day,
}

/// Special days, marked lazily from the special events' occurrences in order of start.
struct SpecialDays<'a> {
    c: &'a Compiled,
    iters: Vec<Peekable<Occs<'a>>>,
    marked: BTreeSet<Date>,
}

impl<'a> SpecialDays<'a> {
    fn new(c: &'a Compiled, from: Date, stop: Date) -> Self {
        let from = from.to_datetime(Time::midnight());
        SpecialDays {
            c,
            iters: (0..c.events.len())
                .filter(|&i| c.events[i].special)
                .map(|i| occs(c, i, from, stop).peekable())
                .collect(),
            marked: BTreeSet::new(),
        }
    }

    fn is_special(&mut self, d: Date) -> bool {
        let Some((_, d1)) = day_bounds(self.c, d) else {
            return false;
        };
        for it in &mut self.iters {
            while let Some(o) = it.next_if(|o| o.start < d1) {
                mark(self.c, &o, &mut self.marked);
            }
        }
        self.marked.contains(&d)
    }
}

/// Mark the local days an occurrence touches.
fn mark(c: &Compiled, o: &Occ, marked: &mut BTreeSet<Date>) {
    let last = if c.events[o.ev].moment {
        o.start
    } else if o.end > o.start {
        o.end - 1
    } else {
        return;
    };
    let (Some(first), Some(last)) = (to_local(&c.tz, o.start), to_local(&c.tz, last)) else {
        return;
    };
    for n in day_number(first.date())..=day_number(last.date()) {
        if let Some(d) = from_day_number(n) {
            marked.insert(d);
        }
    }
}

/// The first instant after `t`, up to [`HORIZON_DAYS`] ahead, where the state changes: the
/// window state differs from `state_at(t)` (value or source), or a moment fires (it beats every
/// window active at its instant). `None` when nothing changes within the horizon.
pub fn next_transition(c: &Compiled, t: Micros) -> Option<(Micros, State)> {
    let max = Timestamp::MAX.as_microsecond();
    let horizon = t.saturating_add(HORIZON_DAYS * DAY_MICROS).min(max);
    let local = to_local(&c.tz, t)?;
    let stop = add_days(to_local(&c.tz, horizon).map_or(Date::MAX, |d| d.date()), 2);
    let initial = state_at(c, t);

    let mut heap: BinaryHeap<Reverse<(Micros, Item)>> = BinaryHeap::new();
    let mut normal: BTreeSet<Key> = BTreeSet::new();
    let mut special: BTreeSet<Key> = BTreeSet::new();
    let mut seq: u64 = 0;
    let mut iters: Vec<Peekable<Occs<'_>>> = (0..c.events.len())
        .map(|i| occs(c, i, local, stop).peekable())
        .collect();
    let push_next = |heap: &mut BinaryHeap<_>, i: usize, it: &mut Peekable<Occs<'_>>| {
        if let Some(o) = it.peek() {
            if o.start <= horizon {
                heap.push(Reverse((o.start, Item::Start(i))));
            }
        }
    };
    // Open the windows active at `t`.
    for (i, it) in iters.iter_mut().enumerate() {
        while let Some(o) = it.next_if(|o| o.start <= t) {
            if !c.events[i].moment && t < o.end {
                seq += 1;
                let k = Key::of(c, i, o.start, seq);
                set_of(c, i, &mut normal, &mut special).insert(k);
                heap.push(Reverse((o.end, Item::End(k))));
            }
        }
        push_next(&mut heap, i, it);
    }
    let mut days = c
        .has_special
        .then(|| SpecialDays::new(c, local.date(), stop));
    if days.is_some() {
        if let Some((_, d1)) = day_bounds(c, local.date()) {
            heap.push(Reverse((d1, Item::Day)));
        }
    }

    let mut moments: Vec<usize> = Vec::new();
    while let Some(&Reverse((p, _))) = heap.peek() {
        if p > horizon {
            return None;
        }
        moments.clear();
        while heap.peek().is_some_and(|Reverse((q, _))| *q == p) {
            let Some(Reverse((_, item))) = heap.pop() else {
                break;
            };
            match item {
                Item::Start(i) => {
                    if let Some(o) = iters[i].next() {
                        if c.events[i].moment {
                            moments.push(i);
                        } else if o.end > o.start {
                            seq += 1;
                            let k = Key::of(c, i, o.start, seq);
                            set_of(c, i, &mut normal, &mut special).insert(k);
                            heap.push(Reverse((o.end, Item::End(k))));
                        }
                    }
                    push_next(&mut heap, i, &mut iters[i]);
                }
                Item::End(k) => {
                    set_of(c, k.ev, &mut normal, &mut special).remove(&k);
                }
                Item::Day => {
                    let next = to_local(&c.tz, p).and_then(|d| day_bounds(c, d.date()));
                    if let Some((_, d1)) = next.filter(|(_, d1)| *d1 > p) {
                        heap.push(Reverse((d1, Item::Day)));
                    }
                }
            }
        }
        let is_special = match &mut days {
            Some(days) => to_local(&c.tz, p).is_some_and(|d| days.is_special(d.date())),
            None => false,
        };
        let win = if is_special {
            special.first().copied()
        } else {
            match (normal.first(), special.first()) {
                (Some(a), Some(b)) => Some(*a.min(b)),
                (a, b) => a.or(b).copied(),
            }
        };
        let moment = moments
            .iter()
            .filter(|&&i| !is_special || c.events[i].special)
            .map(|&i| Key::of(c, i, p, 0))
            .min();
        if let Some(m) = moment.filter(|m| win.is_none_or(|w| m.beats(&w))) {
            let e = &c.schedule.events[m.ev];
            return Some((
                p,
                State {
                    value: e.value.clone(),
                    source: Source::Moment {
                        id: e.id.clone(),
                        at: p,
                    },
                },
            ));
        }
        let s = state_of(c, win);
        if s != initial {
            return Some((p, s));
        }
    }
    None
}

fn set_of<'s>(
    c: &Compiled,
    ev: usize,
    normal: &'s mut BTreeSet<Key>,
    special: &'s mut BTreeSet<Key>,
) -> &'s mut BTreeSet<Key> {
    if c.events[ev].special {
        special
    } else {
        normal
    }
}

/// Every event's occurrences that touch `[from, to)` (a window with `end > from`, a moment at
/// or after `from`; both with `start < to`), by start then event number, at most `limit`.
/// Precedence is not applied: this is the timeline of all events.
pub fn occurrences(c: &Compiled, from: Micros, to: Micros, limit: usize) -> Vec<Occurrence> {
    let mut out = Vec::new();
    let Some(local) = to_local(&c.tz, from) else {
        return out;
    };
    if limit == 0 || to <= from {
        return out;
    }
    let stop = add_days(to_local(&c.tz, to).map_or(Date::MAX, |d| d.date()), 2);
    let mut iters: Vec<Occs<'_>> = (0..c.events.len())
        .map(|i| occs(c, i, local, stop))
        .collect();
    let mut heap: BinaryHeap<Reverse<(Micros, u32, usize, Micros)>> = BinaryHeap::new();
    for (i, it) in iters.iter_mut().enumerate() {
        if let Some(o) = it.next() {
            heap.push(Reverse((o.start, c.events[i].num, i, o.end)));
        }
    }
    while let Some(Reverse((start, _, i, end))) = heap.pop() {
        if start >= to {
            break;
        }
        let ev = &c.events[i];
        if end > from || (ev.moment && start >= from) {
            let e = &c.schedule.events[i];
            out.push(Occurrence {
                event: e.id.clone(),
                start,
                end,
                value: e.value.clone(),
                priority: e.priority,
                special: e.special,
            });
            if out.len() == limit {
                break;
            }
        }
        if let Some(o) = iters[i].next() {
            heap.push(Reverse((o.start, ev.num, i, o.end)));
        }
    }
    out
}
