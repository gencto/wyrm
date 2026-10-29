//! One wake heap behind one host timer, and the clock watchdog (ADR 0022 "The link").
//!
//! Every future piece of work (a schedule's next transition; Task 4 adds retries and confirm
//! timeouts) is one [`Wake`] in a min-heap of wall-clock instants. The app holds one host
//! timer, armed for the earliest wake but never longer than [`WATCHDOG_MS`]. Host timers run on
//! the monotonic clock, so when a timer fires the wall clock should have moved by the timer's
//! delay; a difference over [`CLOCK_STEP_MS`] is a wall-clock step (NTP, a resume from sleep),
//! and the app re-evaluates its schedules at the new "now".

use std::cmp::Reverse;
use std::collections::{BinaryHeap, HashMap};

use wyrm_core::Status;
use wyrm_link_api::{AppError, Host, TimerId};
use wyrm_schedule::Micros;

use crate::limits::{CLOCK_STEP_MS, WATCHDOG_MS};

/// What a wake is for. One live wake per value: setting it again replaces the older one.
#[derive(Debug, Clone, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub enum Wake {
    /// The schedule's next transition.
    Transition(String),
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
            self.heap = self
                .live
                .iter()
                .map(|(w, (g, t))| Reverse((*t, *g, w.clone())))
                .collect();
        }
    }

    pub fn clear(&mut self) {
        self.heap.clear();
        self.live.clear();
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

    /// The earliest live instant, without touching the heap.
    pub fn next_live(&self) -> Option<Micros> {
        self.live.values().map(|(_, t)| *t).min()
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

/// The one host timer.
#[derive(Default)]
pub struct Timer {
    armed: Option<Armed>,
}

struct Armed {
    id: TimerId,
    /// Wall clock when it was armed, and its delay.
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

/// What a fired timer says about the wall clock.
pub enum Fired {
    /// Not the armed timer (a cancelled one that fired anyway): ignore it.
    Stale,
    Ok,
    /// The wall clock moved by this many microseconds more (or less) than the timer's delay.
    Step(Micros),
}

impl Timer {
    /// The host timer `id` fired at wall clock `now`.
    pub fn fired(&mut self, id: TimerId, now: Micros) -> Fired {
        match self.armed.take_if(|a| a.id == id) {
            None => Fired::Stale,
            Some(a) => {
                let off = now.saturating_sub(a.due());
                if off.unsigned_abs() > CLOCK_STEP_MS * 1000 {
                    Fired::Step(off)
                } else {
                    Fired::Ok
                }
            }
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

/// A timer the host refused: the app cannot wake, so the event fails loudly.
pub fn no_timer(e: AppError) -> AppError {
    AppError::new(Status::ResourceExhausted, format!("no timer: {}", e.msg))
}
