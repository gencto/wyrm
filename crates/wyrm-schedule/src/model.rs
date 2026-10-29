//! Types, limits and validation.

use std::fmt;

use jiff::civil::{DateTime, Weekday};
use wyrm_core::Value;

/// Own export format name and version (`format` key of the export map).
pub const FORMAT: &str = "wyrm-schedule/1";
/// Most events in one schedule.
pub const MAX_EVENTS: usize = 100;
/// Largest `COUNT` of a rule.
pub const MAX_COUNT: u32 = 10_000;
/// Largest `INTERVAL` of a rule (the smallest is 1).
pub const MAX_INTERVAL: u32 = 1_000;

/// Instant: microseconds since the Unix epoch, UTC.
pub type Micros = i64;

#[derive(Debug, Clone, PartialEq)]
pub struct Schedule {
    pub id: String,
    pub display: String,
    /// IANA zone name.
    pub tz: String,
    pub default: Value,
    pub enabled: bool,
    pub events: Vec<Event>,
    /// The next `n` of an event id `e<n>`; never goes down, so an id is never reused.
    pub next_event: u32,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Event {
    pub id: String,
    pub display: String,
    pub value: Value,
    /// 1 (highest) … 9; 0 = none (lowest).
    pub priority: u8,
    pub special: bool,
    /// First occurrence's window, local wall time in the schedule's zone.
    pub start: DateTime,
    pub end: DateTime,
    pub recurrence: Option<Rule>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Freq {
    Hourly,
    Daily,
    Weekly,
    Monthly,
    Yearly,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RuleEnd {
    Never,
    Count(u32),
    Until(DateTime),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct DaySpec {
    /// `1MO` = first Monday, `-1FR` = last Friday; only with MONTHLY and YEARLY.
    pub ordinal: Option<i8>,
    pub day: Weekday,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Rule {
    pub freq: Freq,
    pub interval: u32,
    pub end: RuleEnd,
    pub by_day: Vec<DaySpec>,
    /// 1…31, or -1 = the last day.
    pub by_month_day: Vec<i8>,
    pub by_month: Vec<u8>,
}

/// A refused input: the field (or rule part) and what is wrong with it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Invalid {
    pub field: String,
    pub rule: String,
}

impl Invalid {
    pub fn new(field: impl Into<String>, rule: impl Into<String>) -> Self {
        Invalid {
            field: field.into(),
            rule: rule.into(),
        }
    }

    /// The same error under an outer field: `events[0].recurrence` over `COUNT: …`.
    pub(crate) fn within(self, outer: &str) -> Self {
        Invalid::new(outer, format!("{}: {}", self.field, self.rule))
    }
}

impl fmt::Display for Invalid {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}: {}", self.field, self.rule)
    }
}

impl std::error::Error for Invalid {}

/// A key segment: `[A-Za-z0-9_-]`, 1 to 64 bytes.
pub fn valid_id(id: &str) -> bool {
    (1..=64).contains(&id.len())
        && id
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
}

/// Local date-time text `YYYY-MM-DDTHH:MM[:SS]`. An offset or `Z` is refused.
pub fn parse_local(field: &str, text: &str) -> Result<DateTime, Invalid> {
    let bad = || {
        Invalid::new(
            field,
            format!("expected local time YYYY-MM-DDTHH:MM[:SS] without offset, got {text:?}"),
        )
    };
    let b = text.as_bytes();
    if b.len() != 16 && b.len() != 19 {
        return Err(bad());
    }
    let sep = [(4, b'-'), (7, b'-'), (10, b'T'), (13, b':'), (16, b':')];
    for (i, c) in sep {
        if i < b.len() && b[i] != c {
            return Err(bad());
        }
    }
    let num = |from: usize, to: usize| -> Result<i16, Invalid> {
        let s = &text[from..to];
        if !s.bytes().all(|c| c.is_ascii_digit()) {
            return Err(bad());
        }
        s.parse::<i16>().map_err(|_| bad())
    };
    let sec = if b.len() == 19 { num(17, 19)? } else { 0 };
    let to_i8 = |v: i16| i8::try_from(v).map_err(|_| bad());
    DateTime::new(
        num(0, 4)?,
        to_i8(num(5, 7)?)?,
        to_i8(num(8, 10)?)?,
        to_i8(num(11, 13)?)?,
        to_i8(num(14, 16)?)?,
        to_i8(sec)?,
        0,
    )
    .map_err(|_| bad())
}

/// The canonical text of a local date-time: seconds only when not zero.
pub fn format_local(dt: DateTime) -> String {
    let base = format!(
        "{:04}-{:02}-{:02}T{:02}:{:02}",
        dt.year(),
        dt.month(),
        dt.day(),
        dt.hour(),
        dt.minute()
    );
    if dt.second() == 0 {
        base
    } else {
        format!("{base}:{:02}", dt.second())
    }
}

/// Check a whole schedule. The first error names the field and the rule.
pub fn validate(s: &Schedule) -> Result<(), Invalid> {
    if !valid_id(&s.id) {
        return Err(Invalid::new(
            "id",
            "must be 1 to 64 bytes of A-Z a-z 0-9 _ -",
        ));
    }
    if jiff::tz::TimeZone::get(&s.tz).is_err() {
        return Err(Invalid::new(
            "tz",
            format!("unknown IANA time zone {:?}", s.tz),
        ));
    }
    if s.events.len() > MAX_EVENTS {
        return Err(Invalid::new(
            "events",
            format!("at most {MAX_EVENTS} events per schedule"),
        ));
    }
    for (i, e) in s.events.iter().enumerate() {
        validate_event(s, i, e)?;
    }
    Ok(())
}

fn event_number(id: &str) -> Option<u32> {
    let n = id.strip_prefix('e')?;
    if n.is_empty() || n.starts_with('0') || !n.bytes().all(|c| c.is_ascii_digit()) {
        return None;
    }
    n.parse().ok()
}

fn validate_event(s: &Schedule, i: usize, e: &Event) -> Result<(), Invalid> {
    let f = |name: &str| format!("events[{i}].{name}");
    let Some(n) = event_number(&e.id) else {
        return Err(Invalid::new(f("id"), "must be e<n>, n from 1"));
    };
    if s.events[..i].iter().any(|o| o.id == e.id) {
        return Err(Invalid::new(f("id"), "duplicate event id"));
    }
    if n >= s.next_event {
        return Err(Invalid::new(
            f("id"),
            format!("id not below next_event ({})", s.next_event),
        ));
    }
    if e.priority > 9 {
        return Err(Invalid::new(f("priority"), "must be 0 to 9"));
    }
    if e.end < e.start {
        return Err(Invalid::new(f("end"), "end is before start"));
    }
    if let Some(r) = &e.recurrence {
        if let RuleEnd::Until(u) = r.end {
            if u < e.start {
                return Err(Invalid::new(f("recurrence"), "UNTIL is before start"));
            }
        }
        let window = e.end.duration_since(e.start).as_secs();
        if window > r.period_secs() {
            return Err(Invalid::new(
                f("end"),
                "window longer than its period (shortest gap between occurrences)",
            ));
        }
    }
    Ok(())
}
