//! Occurrences of one event in civil (local) time, and the mapping of local date-times to
//! instants (ADR 0022 "Model").
//!
//! A rule walks periods of `FREQ × INTERVAL` from the period that holds the event's start. Each
//! period expands or filters `BYMONTH`, `BYMONTHDAY` and `BYDAY` (Ruling R5); a date that does not
//! exist is skipped. A walk never scans from the start: it jumps to the period before the one it
//! is asked about. `COUNT` is walked once, when the event is compiled, and kept as the civil start
//! of the last occurrence.

use jiff::civil::{Date, DateTime, Time, Weekday};
use jiff::tz::{AmbiguousOffset, TimeZone};
use jiff::Timestamp;

use crate::model::{DaySpec, Event, Freq, Micros, Rule, RuleEnd};

const DAY_SECS: i64 = 86_400;
/// How far the walk that resolves `COUNT` looks for its occurrences. Rules whose filters never
/// (or almost never) match end here: the Gregorian calendar repeats every 400 years.
const COUNT_YEARS: i16 = 400;

/// The instant of a local date-time in `tz`. In a gap (spring forward) it is the instant of the
/// transition, the first instant after the gap; in a fold (fall back) the earlier instant.
/// `None` outside the range of instants.
pub(crate) fn to_instant(tz: &TimeZone, dt: DateTime) -> Option<Micros> {
    let ts = match tz.to_ambiguous_timestamp(dt).offset() {
        AmbiguousOffset::Unambiguous { offset } => offset.to_timestamp(dt).ok()?,
        AmbiguousOffset::Fold { before, .. } => before.to_timestamp(dt).ok()?,
        AmbiguousOffset::Gap { after, .. } => {
            // Read with the offset after the gap, the local time is an instant before the
            // transition; the transition that follows it closes the gap.
            let early = after.to_timestamp(dt).ok()?;
            tz.following(early).next()?.timestamp()
        }
    };
    Some(ts.as_microsecond())
}

/// The local date-time of an instant in `tz`; `None` outside the range of instants.
pub(crate) fn to_local(tz: &TimeZone, t: Micros) -> Option<DateTime> {
    Some(tz.to_datetime(Timestamp::from_microsecond(t).ok()?))
}

/// Days since 1970-01-01 (proleptic Gregorian).
pub(crate) fn day_number(d: Date) -> i64 {
    let (y, m, day) = (
        i64::from(d.year()),
        i64::from(d.month()),
        i64::from(d.day()),
    );
    let y = if m <= 2 { y - 1 } else { y };
    let era = y.div_euclid(400);
    let yoe = y - era * 400;
    let mp = (m + 9) % 12;
    let doy = (153 * mp + 2) / 5 + day - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146_097 + doe - 719_468
}

/// The date of a day number; `None` outside jiff's dates.
pub(crate) fn from_day_number(n: i64) -> Option<Date> {
    let z = n.checked_add(719_468)?;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = doy - (153 * mp + 2) / 5 + 1;
    let month = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = yoe + era * 400 + i64::from(month <= 2);
    Date::new(
        i16::try_from(year).ok()?,
        i8::try_from(month).ok()?,
        i8::try_from(day).ok()?,
    )
    .ok()
}

fn time_secs(t: Time) -> i64 {
    i64::from(t.hour()) * 3600 + i64::from(t.minute()) * 60 + i64::from(t.second())
}

/// Seconds since 1970-01-01T00:00 of a civil date-time (no zone), without the fraction.
fn civil_secs(dt: DateTime) -> i64 {
    day_number(dt.date()) * DAY_SECS + time_secs(dt.time())
}

fn from_civil_secs(secs: i64, subsec: i32) -> Option<DateTime> {
    let date = from_day_number(secs.div_euclid(DAY_SECS))?;
    let s = secs.rem_euclid(DAY_SECS);
    let time = Time::new(
        i8::try_from(s / 3600).ok()?,
        i8::try_from(s % 3600 / 60).ok()?,
        i8::try_from(s % 60).ok()?,
        subsec,
    )
    .ok()?;
    Some(date.to_datetime(time))
}

fn month_index(d: Date) -> i64 {
    i64::from(d.year()) * 12 + i64::from(d.month()) - 1
}

fn days_in_month(year: i16, month: i8) -> Option<i8> {
    Some(Date::new(year, month, 1).ok()?.days_in_month())
}

/// Monday 0 … Sunday 6.
fn wd(d: Weekday) -> i8 {
    d.to_monday_zero_offset()
}

/// How an event's occurrences end, once `COUNT` is resolved.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Last {
    Open,
    /// The last kept civil start (`UNTIL`, or the `COUNT`-th start).
    Until(DateTime),
    /// The rule yields nothing.
    Empty,
}

/// One event's recurrence, ready to walk.
#[derive(Debug, Clone)]
pub(crate) struct Recur {
    start: DateTime,
    rule: Option<Rule>,
    last: Last,
}

impl Recur {
    pub(crate) fn new(e: &Event) -> Recur {
        let mut r = Recur {
            start: e.start,
            rule: e.recurrence.clone(),
            last: Last::Open,
        };
        match r.rule.as_ref().map(|rule| rule.end) {
            Some(RuleEnd::Until(u)) => r.last = Last::Until(u),
            Some(RuleEnd::Count(n)) => {
                let years = e.start.year().saturating_add(COUNT_YEARS).min(9998);
                let stop = Date::new(years, 1, 1).unwrap_or(Date::MAX);
                let n = usize::try_from(n).unwrap_or(usize::MAX);
                // A walk from the event's own start begins at the first period.
                let found = r.starts(e.start, stop).take(n).last();
                r.last = found.map_or(Last::Empty, Last::Until);
            }
            Some(RuleEnd::Never) | None => {}
        }
        r
    }

    /// Civil starts in order, from the period before the one that holds `from` (an earlier
    /// window may reach `from`), while the period begins on or before `stop`.
    pub(crate) fn starts(&self, from: DateTime, stop: Date) -> Starts<'_> {
        let mut s = Starts {
            r: self,
            period: 0,
            buf: Vec::new(),
            pos: 0,
            done: self.last == Last::Empty,
            stop,
            one_off: self.rule.is_none(),
        };
        if let Some(rule) = &self.rule {
            s.period = (period_of(rule, self.start, from) - 1).max(0);
        }
        s
    }
}

/// The index of the period that holds the civil date-time `x` (negative before the start).
fn period_of(rule: &Rule, start: DateTime, x: DateTime) -> i64 {
    let n = i64::from(rule.interval);
    match rule.freq {
        Freq::Hourly => (civil_secs(x) - civil_secs(start)).div_euclid(n * 3600),
        Freq::Daily => (day_number(x.date()) - day_number(start.date())).div_euclid(n),
        Freq::Weekly => {
            let monday = day_number(start.date()) - i64::from(wd(start.weekday()));
            (day_number(x.date()) - monday).div_euclid(7 * n)
        }
        Freq::Monthly => (month_index(x.date()) - month_index(start.date())).div_euclid(n),
        Freq::Yearly => (i64::from(x.year()) - i64::from(start.year())).div_euclid(n),
    }
}

/// The lazy walk of one event's civil starts.
pub(crate) struct Starts<'a> {
    r: &'a Recur,
    period: i64,
    /// Candidates of the period last expanded, in order.
    buf: Vec<DateTime>,
    pos: usize,
    done: bool,
    stop: Date,
    one_off: bool,
}

impl Iterator for Starts<'_> {
    type Item = DateTime;

    fn next(&mut self) -> Option<DateTime> {
        if self.one_off {
            self.done = true;
            self.one_off = false;
            return (self.r.start.date() <= self.stop).then_some(self.r.start);
        }
        loop {
            if self.done {
                return None;
            }
            if let Some(&dt) = self.buf.get(self.pos) {
                self.pos += 1;
                if dt < self.r.start {
                    continue;
                }
                if let Last::Until(u) = self.r.last {
                    if dt > u {
                        self.done = true;
                        return None;
                    }
                }
                return Some(dt);
            }
            self.expand();
        }
    }
}

impl Starts<'_> {
    /// Fill `buf` with the next period's candidates, or mark the walk done.
    fn expand(&mut self) {
        self.buf.clear();
        self.pos = 0;
        let Some(rule) = &self.r.rule else {
            self.done = true;
            return;
        };
        let k = self.period;
        let start = self.r.start;
        let n = i64::from(rule.interval);
        let first = match rule.freq {
            Freq::Hourly => {
                let step = n * 3600;
                let Some(dt) = k
                    .checked_mul(step)
                    .and_then(|o| o.checked_add(civil_secs(start)))
                    .and_then(|s| from_civil_secs(s, start.subsec_nanosecond()))
                else {
                    self.done = true;
                    return;
                };
                if date_passes(rule, dt.date(), true) {
                    self.buf.push(dt);
                    self.period = k + 1;
                } else {
                    // Skip the rest of a refused day (or month).
                    let gap = skip_to(rule, dt.date()) * DAY_SECS - civil_secs(start);
                    self.period = (k + 1).max(ceil_div(gap, step));
                }
                Some(dt.date())
            }
            Freq::Daily => {
                let date = k
                    .checked_mul(n)
                    .and_then(|o| from_day_number(day_number(start.date()) + o));
                self.period = k + 1;
                if let Some(d) = date {
                    if date_passes(rule, d, true) {
                        self.buf.push(d.to_datetime(start.time()));
                    } else {
                        let gap = skip_to(rule, d) - day_number(start.date());
                        self.period = self.period.max(ceil_div(gap, n));
                    }
                }
                date
            }
            Freq::Weekly => {
                let monday = day_number(start.date()) - i64::from(wd(start.weekday()));
                let base = k.checked_mul(7 * n).map(|o| monday + o);
                let first = base.and_then(from_day_number);
                if let (Some(base), Some(_)) = (base, first) {
                    let mut days: Vec<i8> = if rule.by_day.is_empty() {
                        vec![wd(start.weekday())]
                    } else {
                        rule.by_day.iter().map(|d| wd(d.day)).collect()
                    };
                    days.sort_unstable();
                    days.dedup();
                    for off in days {
                        if let Some(d) = from_day_number(base + i64::from(off)) {
                            if date_passes(rule, d, false) {
                                self.buf.push(d.to_datetime(start.time()));
                            }
                        }
                    }
                }
                self.period = k + 1;
                first
            }
            Freq::Monthly => {
                let mi = k.checked_mul(n).map(|o| month_index(start.date()) + o);
                let first = mi.and_then(month_date);
                if let Some(d) = first {
                    if rule.by_month.is_empty() || rule.by_month.contains(&month_u8(d)) {
                        self.month(rule, d.year(), d.month());
                    }
                }
                self.period = k + 1;
                first
            }
            Freq::Yearly => {
                let y = k
                    .checked_mul(n)
                    .and_then(|o| i16::try_from(i64::from(start.year()) + o).ok());
                let first = y.and_then(|y| Date::new(y, 1, 1).ok());
                if let Some(y) = first.map(|d| d.year()) {
                    let mut months: Vec<i8> = if rule.by_month.is_empty() {
                        vec![start.month()]
                    } else {
                        rule.by_month
                            .iter()
                            .filter_map(|m| i8::try_from(*m).ok())
                            .collect()
                    };
                    months.sort_unstable();
                    for m in months {
                        self.month(rule, y, m);
                    }
                }
                self.period = k + 1;
                first
            }
        };
        match first {
            Some(d) if d <= self.stop => {}
            _ => {
                self.buf.clear();
                self.done = true;
            }
        }
    }

    /// Append the candidates of one month (MONTHLY, YEARLY): `BYMONTHDAY` and `BYDAY` expand,
    /// their intersection when both are given; neither = the start's day of month.
    fn month(&mut self, rule: &Rule, y: i16, m: i8) {
        let Some(dim) = days_in_month(y, m) else {
            return;
        };
        let by_md: Vec<i8> = rule
            .by_month_day
            .iter()
            .filter_map(|&d| match d {
                -1 => Some(dim),
                d if (1..=dim).contains(&d) => Some(d),
                _ => None,
            })
            .collect();
        let by_wd: Vec<i8> = rule
            .by_day
            .iter()
            .flat_map(|spec| weekdays_in_month(y, m, dim, *spec))
            .collect();
        let mut days: Vec<i8> = match (rule.by_month_day.is_empty(), rule.by_day.is_empty()) {
            (true, true) => {
                let d = self.r.start.day();
                if d <= dim {
                    vec![d]
                } else {
                    Vec::new()
                }
            }
            (false, true) => by_md,
            (true, false) => by_wd,
            (false, false) => by_md.into_iter().filter(|d| by_wd.contains(d)).collect(),
        };
        days.sort_unstable();
        days.dedup();
        let time = self.r.start.time();
        for d in days {
            if let Ok(date) = Date::new(y, m, d) {
                self.buf.push(date.to_datetime(time));
            }
        }
    }
}

fn month_u8(d: Date) -> u8 {
    u8::try_from(d.month()).unwrap_or(0)
}

/// The first day of a month index (`year × 12 + month − 1`).
fn month_date(mi: i64) -> Option<Date> {
    let y = i16::try_from(mi.div_euclid(12)).ok()?;
    let m = i8::try_from(mi.rem_euclid(12) + 1).ok()?;
    Date::new(y, m, 1).ok()
}

/// Days of month `m` that match one `BYDAY` part: every such weekday, or the n-th one
/// (`-1` = the last).
fn weekdays_in_month(y: i16, m: i8, dim: i8, spec: DaySpec) -> Vec<i8> {
    let Ok(first) = Date::new(y, m, 1) else {
        return Vec::new();
    };
    let target = wd(spec.day);
    let first_match = 1 + (target - wd(first.weekday())).rem_euclid(7);
    let all = (0..5)
        .map(|i| first_match + 7 * i)
        .filter(|d| *d <= dim)
        .collect::<Vec<i8>>();
    match spec.ordinal {
        None => all,
        Some(n) if n > 0 => usize::try_from(n - 1)
            .ok()
            .and_then(|i| all.get(i).copied())
            .into_iter()
            .collect(),
        Some(n) => usize::try_from(-i16::from(n))
            .ok()
            .and_then(|back| all.len().checked_sub(back))
            .and_then(|i| all.get(i).copied())
            .into_iter()
            .collect(),
    }
}

/// `a / b` rounded up, for `b > 0`.
fn ceil_div(a: i64, b: i64) -> i64 {
    a.div_euclid(b) + i64::from(a.rem_euclid(b) != 0)
}

/// The day number of the first date after `d` that the filters may pass: the first of the next
/// month when `BYMONTH` refuses `d`'s month or no `BYMONTHDAY` exists in it, else the next day.
/// Keeps the walk of rules that rarely or never match per month, not per period.
fn skip_to(rule: &Rule, d: Date) -> i64 {
    let dim = d.days_in_month();
    let month_refused = (!rule.by_month.is_empty() && !rule.by_month.contains(&month_u8(d)))
        || (!rule.by_month_day.is_empty()
            && !rule.by_month_day.iter().any(|&md| md == -1 || md <= dim));
    if month_refused {
        day_number(d) - i64::from(d.day()) + 1 + i64::from(dim)
    } else {
        day_number(d) + 1
    }
}

/// The filters of HOURLY, DAILY (`with_day`: `BYDAY` too) and WEEKLY: `BYMONTH`, `BYMONTHDAY`.
fn date_passes(rule: &Rule, d: Date, with_day: bool) -> bool {
    if !rule.by_month.is_empty() && !rule.by_month.contains(&month_u8(d)) {
        return false;
    }
    if !rule.by_month_day.is_empty()
        && !rule
            .by_month_day
            .iter()
            .any(|&md| md == d.day() || (md == -1 && d.day() == d.days_in_month()))
    {
        return false;
    }
    !with_day || rule.by_day.is_empty() || rule.by_day.iter().any(|s| s.day == d.weekday())
}

#[cfg(test)]
mod tests {
    use super::*;
    use jiff::civil::{date, datetime};

    #[test]
    fn day_numbers_round_trip() {
        for d in [
            date(1970, 1, 1),
            date(2000, 2, 29),
            date(2026, 10, 29),
            date(1600, 3, 1),
            date(-400, 12, 31),
        ] {
            let n = day_number(d);
            assert_eq!(from_day_number(n), Some(d));
            assert_eq!(n, i64::from(d.since(date(1970, 1, 1)).unwrap().get_days()));
        }
    }

    #[test]
    fn gap_maps_to_the_transition() {
        let kyiv = TimeZone::get("Europe/Kyiv").unwrap();
        let t = to_instant(&kyiv, datetime(2027, 3, 28, 3, 30, 0, 0)).unwrap();
        let want: Timestamp = "2027-03-28T01:00Z".parse().unwrap();
        assert_eq!(t, want.as_microsecond());
        let t = to_instant(&kyiv, datetime(2026, 10, 25, 3, 30, 0, 0)).unwrap();
        let want: Timestamp = "2026-10-25T00:30Z".parse().unwrap();
        assert_eq!(t, want.as_microsecond());
    }

    #[test]
    fn nth_weekday() {
        // November 2026 starts on a Sunday.
        let spec = |o, day| DaySpec { ordinal: o, day };
        assert_eq!(
            weekdays_in_month(2026, 11, 30, spec(Some(1), Weekday::Monday)),
            vec![2]
        );
        assert_eq!(
            weekdays_in_month(2026, 11, 30, spec(Some(-1), Weekday::Friday)),
            vec![27]
        );
        assert_eq!(
            weekdays_in_month(2026, 11, 30, spec(Some(5), Weekday::Monday)),
            vec![30]
        );
        assert!(weekdays_in_month(2026, 11, 30, spec(Some(5), Weekday::Friday)).is_empty());
        assert_eq!(
            weekdays_in_month(2026, 11, 30, spec(None, Weekday::Sunday)),
            vec![1, 8, 15, 22, 29]
        );
    }
}
