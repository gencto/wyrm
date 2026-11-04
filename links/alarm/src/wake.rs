//! One wake heap behind one host timer, and the clock watchdog (after the scheduler's,
//! ADR 0022 "The link").
//!
//! Every future piece of work (an inhibit's end, a staleness deadline, a record's escalation,
//! a publication, the daily purge) is one [`Wake`] in a min-heap of wall-clock instants. The app
//! holds one host timer, armed for the earliest wake but never longer than [`WATCHDOG_MS`].
//! Host timers run on the monotonic clock, so when a timer fires the wall clock should have
//! moved by the timer's delay; a difference over [`CLOCK_STEP_MS`] is a wall-clock step (NTP, a
//! resume from sleep). The alarm link's wakes are durations from an instant (an inhibit of
//! 10 s stays 10 s), so a step moves every wake by the step ([`Wakes::shift`]).

use std::cmp::Reverse;
use std::collections::{BinaryHeap, HashMap};

use wyrm_core::Status;
use wyrm_link_api::{AppError, Host, TimerId};

use crate::limits::{CLOCK_STEP_MS, WATCHDOG_MS};
use crate::Micros;

/// What a wake is for. One live wake per value: setting it again replaces the older one.
#[derive(Debug, Clone, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub enum Wake {
    /// A key of a watch of a class: its inhibit ends, or its staleness deadline falls.
    Point(String, String, String),
    /// A record's next escalation.
    Escalate(u64),
    /// A class's counts and table.
    Publish(String),
    /// The link's `stats`.
    Stats,
    /// The daily purge.
    Purge,
}

/// The heap. Replaced and cancelled entries stay in the heap until they reach the top; their
/// generation no longer matches the live one there, and they are skipped.
#[derive(Default)]
pub struct Wakes {
    heap: BinaryHeap<Reverse<(Micros, u64, Wake)>>,
    /// The live entry of each wake: its generation and instant.
    live: HashMap<Wake, (u64, Micros)>,
    next_gen: u64,
}

impl Wakes {
    /// `wake` at `at`, replacing its earlier instant; `None` cancels it.
    pub fn set(&mut self, wake: Wake, at: Option<Micros>) {
        let Some(at) = at else {
            self.live.remove(&wake);
            return;
        };
        if self.live.get(&wake).is_some_and(|(_, t)| *t == at) {
            return;
        }
        self.next_gen += 1;
        self.live.insert(wake.clone(), (self.next_gen, at));
        self.heap.push(Reverse((at, self.next_gen, wake)));
        // stale entries are dropped at the top; rebuild when they pile up below it
        if self.heap.len() > 2 * self.live.len() + 64 {
            self.rebuild();
        }
    }

    /// `wake` at `at` unless it is live already (a coalesced publication keeps its first
    /// instant).
    pub fn set_if_none(&mut self, wake: Wake, at: Micros) {
        if !self.live.contains_key(&wake) {
            self.set(wake, Some(at));
        }
    }

    /// Moves every live wake by `off` (a wall-clock step).
    pub fn shift(&mut self, off: Micros) {
        for (_, t) in self.live.values_mut() {
            *t = t.saturating_add(off);
        }
        self.rebuild();
    }

    fn rebuild(&mut self) {
        self.heap = self
            .live
            .iter()
            .map(|(w, (g, t))| Reverse((*t, *g, w.clone())))
            .collect();
    }

    fn drop_stale(&mut self) {
        while let Some(Reverse((_, gen, wake))) = self.heap.peek() {
            if self.live.get(wake).is_some_and(|(g, _)| g == gen) {
                return;
            }
            self.heap.pop();
        }
    }

    /// The earliest live instant.
    pub fn earliest(&mut self) -> Option<Micros> {
        self.drop_stale();
        self.heap.peek().map(|Reverse((t, ..))| *t)
    }

    /// Live wakes.
    pub fn len(&self) -> usize {
        self.live.len()
    }

    /// The earliest live wake due at `now`, without taking it.
    pub fn peek_due(&mut self, now: Micros) -> Option<Wake> {
        self.drop_stale();
        match self.heap.peek() {
            Some(Reverse((t, _, w))) if *t <= now => Some(w.clone()),
            _ => None,
        }
    }

    /// Takes the earliest live wake due at `now` with its instant.
    pub fn pop_due(&mut self, now: Micros) -> Option<(Micros, Wake)> {
        self.peek_due(now)?;
        let Reverse((t, _, w)) = self.heap.pop()?;
        self.live.remove(&w);
        Some((t, w))
    }
}

/// The one host timer, and the latest wall clock the app saw.
#[derive(Default)]
pub struct Timer {
    armed: Option<Armed>,
    /// The latest wall clock seen in any event: the monotonic clock never goes back, so a wall
    /// clock well below it is a backward step, whatever event sees it first.
    seen: Option<Micros>,
}

struct Armed {
    id: TimerId,
    /// Wall clock when it was armed, and its delay (`0`: a continuation of batched work).
    at_wall: Micros,
    ms: u64,
}

impl Armed {
    fn due(&self) -> Micros {
        self.at_wall.saturating_add(ms_to_us(self.ms))
    }
}

fn ms_to_us(ms: u64) -> Micros {
    i64::try_from(ms.saturating_mul(1000)).unwrap_or(i64::MAX)
}

const STEP_US: Micros = (CLOCK_STEP_MS * 1000) as Micros;

/// What a fired timer says about the wall clock.
pub enum Fired {
    /// Not the armed timer (a cancelled one that fired anyway): ignore it.
    Stale,
    /// `continuation`: the `0` ms timer of batched work.
    Ok { continuation: bool },
    /// The wall clock moved by this many microseconds more (or less) than the timer's delay.
    Step(Micros),
}

impl Timer {
    /// Every event calls this first with its wall clock: `Some(offset)` (negative) when the
    /// clock stepped back more than [`CLOCK_STEP_MS`] below the latest wall clock seen.
    pub fn observe(&mut self, now: Micros) -> Option<Micros> {
        let back = self
            .seen
            .filter(|s| now < s.saturating_sub(STEP_US))
            .map(|s| now - s);
        self.seen = Some(match (back, self.seen) {
            (None, Some(s)) => s.max(now),
            _ => now,
        });
        back
    }

    /// The host timer `id` fired at wall clock `now`. A continuation may wait in the host's
    /// queue behind other events, so for it only a backward step or more than [`WATCHDOG_MS`]
    /// beyond its arming counts as a step; the batched work itself is never taken for one.
    pub fn fired(&mut self, id: TimerId, now: Micros) -> Fired {
        match self.armed.take_if(|a| a.id == id) {
            None => Fired::Stale,
            Some(a) if a.ms == 0 => {
                let off = now.saturating_sub(a.at_wall);
                if off < -STEP_US || off > ms_to_us(WATCHDOG_MS) {
                    Fired::Step(off)
                } else {
                    Fired::Ok { continuation: true }
                }
            }
            Some(a) => {
                let off = now.saturating_sub(a.due());
                if off.unsigned_abs() > CLOCK_STEP_MS * 1000 {
                    Fired::Step(off)
                } else {
                    Fired::Ok {
                        continuation: false,
                    }
                }
            }
        }
    }

    /// Forgets the armed timer: when it fires it is stale. After a wall-clock step the app
    /// arms a fresh one, so the step is not measured and applied a second time.
    pub fn reset(&mut self, host: &mut dyn Host) {
        if let Some(a) = self.armed.take() {
            host.cancel_timer(a.id);
        }
    }

    /// Arms the timer for `next` (a wall-clock instant; `None` = nothing to do), at most
    /// [`WATCHDOG_MS`] ahead. A timer already armed to fire no later is kept: an early wake
    /// finds nothing due and arms again.
    pub fn arm(
        &mut self,
        host: &mut dyn Host,
        now: Micros,
        next: Option<Micros>,
    ) -> Result<(), AppError> {
        let Some(next) = next else {
            if let Some(a) = self.armed.take() {
                host.cancel_timer(a.id);
            }
            return Ok(());
        };
        let wait_us = u64::try_from(next.saturating_sub(now)).unwrap_or(0);
        let ms = wait_us.div_ceil(1000).min(WATCHDOG_MS);
        let due = now.saturating_add(ms_to_us(ms));
        if self.armed.as_ref().is_some_and(|a| a.due() <= due) {
            return Ok(());
        }
        if let Some(a) = self.armed.take() {
            host.cancel_timer(a.id);
        }
        let id = host.set_timer(ms)?;
        self.armed = Some(Armed {
            id,
            at_wall: now,
            ms,
        });
        Ok(())
    }
}

/// A timer the host refused: the app cannot wake. The caller logs it at `error`; the event goes
/// on (the next event arms the timer again).
pub fn no_timer(e: AppError) -> AppError {
    AppError::new(Status::ResourceExhausted, format!("no timer: {}", e.msg))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn wakes_replace_cancel_and_shift() {
        let mut w = Wakes::default();
        w.set(Wake::Stats, Some(100));
        w.set(Wake::Purge, Some(50));
        w.set_if_none(Wake::Stats, 10);
        assert_eq!(w.earliest(), Some(50));
        w.set(Wake::Purge, None);
        assert_eq!(w.earliest(), Some(100));
        w.shift(-30);
        assert_eq!(w.earliest(), Some(70));
        assert_eq!(w.pop_due(70), Some((70, Wake::Stats)));
        assert_eq!(w.pop_due(1000), None);
        assert_eq!(w.len(), 0);
    }
}
