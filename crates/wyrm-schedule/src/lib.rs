//! The WYRM schedule model (ADR 0022): schedules, events, an RRULE subset, validation, the
//! link's own export format and the DSA localschedule import.
//!
//! The crate is pure. It does no I/O, reads no clock and no OS zone, and builds for
//! `wasm32-unknown-unknown`: zones come from the bundled tz database. Local date-times are
//! civil (no offset); the evaluator (`state_at`, `next_transition`, `occurrences`) maps them to
//! instants with the zone's rules.

mod convert;
pub mod dsa;
mod eval;
mod model;
mod occur;
mod rrule;

pub use convert::{schedule_from_value, schedule_to_value, value_from_json, value_to_json};
pub use eval::{
    next_transition, occurrences, state_at, Compiled, Occurrence, Source, State, HORIZON_DAYS,
};
pub use model::{
    finite, format_local, parse_local, valid_id, validate, DaySpec, Event, Freq, Invalid, Micros,
    Rule, RuleEnd, Schedule, FORMAT, MAX_COUNT, MAX_EVENTS, MAX_INTERVAL,
};

#[cfg(test)]
mod tests {
    #[test]
    fn bundled_zone() {
        assert!(jiff::tz::TimeZone::get("Europe/Kyiv").is_ok());
    }
}
