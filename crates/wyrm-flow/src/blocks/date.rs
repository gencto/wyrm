//! Date and time blocks of the third set (ADR 0044 §3): `now`, `date_time`, `date_format`,
//! `date_parse`, `date_math`, `date_range`.
//!
//! A date value is a number of microseconds since the Unix epoch, as the `t` of every sample;
//! a date input also takes text (RFC 3339, `yyyy-M-d[ H:mm[:ss[.f]]]`, `yyyy/M/d …`,
//! `M/d/yyyy …`, with `am`/`pm`). Wall time is in the zone of `time_zone`: an IANA name,
//! `UTC` (the default) or `±HH:MM`, from `jiff`'s bundled tz data. A wall time in a DST gap
//! moves forward; a repeated one takes the earlier instant. The clock is read once per
//! calculation by the caller and given as `now`.

use super::{num, param, Outs, Shape, View, N};
use crate::nodes::PortType::{self, *};
use jiff::civil::{Date, DateTime};
use jiff::tz::{Offset, TimeZone};
use jiff::{Span, Timestamp};
use std::str::FromStr;
use wyrm_core::Value;

/// The default pattern of `date_format` and `date_range`.
pub const DEFAULT_FORMAT: &str = "yyyy-MM-dd'T'HH:mm:ss";
/// The longest pattern, bytes, and the longest date text an input may be.
const MAX_PATTERN: usize = 128;
const MAX_DATE_TEXT: usize = 64;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum Op {
    Now,
    DateTime,
    Format,
    Parse,
    Math,
    Range,
}

pub(super) const OPS: &[(&str, Op)] = &[
    ("now", Op::Now),
    ("date_time", Op::DateTime),
    ("date_format", Op::Format),
    ("date_parse", Op::Parse),
    ("date_math", Op::Math),
    ("date_range", Op::Range),
];

pub const WEEK_STARTS: &[&str] = &[
    "monday",
    "tuesday",
    "wednesday",
    "thursday",
    "friday",
    "saturday",
    "sunday",
];

fn s(v: &str) -> Value {
    Value::Str(v.to_owned())
}

pub(super) fn shape(op: Op) -> Shape {
    let tz = || param("time_zone", s("UTC"), true);
    let parts = |d: [i64; 7]| -> Vec<super::Param> {
        [
            "year",
            "month",
            "day",
            "hour",
            "minute",
            "second",
            "millisecond",
        ]
        .iter()
        .zip(d)
        .map(|(n, d)| param(n, Value::Int(d), true))
        .collect()
    };
    match op {
        Op::Now => Shape {
            inputs: &["in"],
            params: vec![],
            items: false,
            outputs: &[("out", Number)],
        },
        Op::DateTime => {
            let mut p = parts([1970, 1, 1, 0, 0, 0, 0]);
            p.push(tz());
            Shape {
                inputs: &[],
                params: p,
                items: false,
                outputs: &[("out", Number)],
            }
        }
        Op::Format => Shape {
            inputs: &["in"],
            params: vec![param("format", s(DEFAULT_FORMAT), true), tz()],
            items: false,
            outputs: &[("out", Any)],
        },
        Op::Parse => Shape {
            inputs: &["in"],
            params: vec![tz()],
            items: false,
            outputs: PARSE_OUT,
        },
        Op::Math => {
            let mut p = vec![param("op", s("after"), true)];
            p.extend(parts([0; 7]));
            p.push(tz());
            Shape {
                inputs: &["in"],
                params: p,
                items: false,
                outputs: &[("out", Number)],
            }
        }
        Op::Range => Shape {
            inputs: &["in", "next", "previous"],
            params: vec![
                param("format", s(DEFAULT_FORMAT), true),
                param("range_delimiter", s("/"), true),
                param("keep_special", s("none"), true),
                param("week_start", s("monday"), true),
                tz(),
            ],
            items: false,
            outputs: RANGE_OUT,
        },
    }
}

const PARSE_OUT: &[(&str, PortType)] = &[
    ("time", Number),
    ("year", Number),
    ("month", Number),
    ("day", Number),
    ("hour", Number),
    ("minute", Number),
    ("second", Number),
    ("millisecond", Number),
    ("weekday", Number),
];

const RANGE_OUT: &[(&str, PortType)] = &[
    ("start", Number),
    ("end", Number),
    ("this_range", Any),
    ("next_range", Any),
    ("previous_range", Any),
    ("formatted", Any),
    ("duration", Number),
];

/// The zone a block works in: an IANA name, `UTC` (also `null` and empty), `±HH:MM`.
pub fn zone(v: &Value) -> Option<TimeZone> {
    let name = match v {
        Value::Null => return Some(TimeZone::UTC),
        Value::Str(n) => n.trim(),
        _ => return None,
    };
    // `auto` (`date_format`: the offset the input text has) is UTC for a value without one
    if name.is_empty() || name.eq_ignore_ascii_case("utc") || name == "Z" || name == "auto" {
        return Some(TimeZone::UTC);
    }
    if let Some(off) = offset_of(name) {
        return Some(TimeZone::fixed(off));
    }
    if name.len() > 64 {
        return None;
    }
    TimeZone::get(name).ok()
}

/// `±HH:MM` (or `±HHMM`) as an offset.
fn offset_of(t: &str) -> Option<Offset> {
    let b = t.as_bytes();
    let sign = match b.first()? {
        b'+' => 1,
        b'-' => -1,
        _ => return None,
    };
    let digits: String = t[1..].chars().filter(|c| *c != ':').collect();
    if digits.len() != 4 || !digits.chars().all(|c| c.is_ascii_digit()) {
        return None;
    }
    let h: i32 = digits[..2].parse().ok()?;
    let m: i32 = digits[2..].parse().ok()?;
    if h > 23 || m > 59 {
        return None;
    }
    Offset::from_seconds(sign * (h * 3600 + m * 60)).ok()
}

fn us(ts: Timestamp) -> Value {
    Value::Int(ts.as_microsecond())
}

fn ts_of(us: i64) -> Option<Timestamp> {
    Timestamp::from_microsecond(us).ok()
}

/// A date input: microseconds, or text read in zone `tz` when it has no offset of its own.
pub fn date_of(v: &Value, tz: &TimeZone) -> Option<Timestamp> {
    match v {
        Value::Str(t) => parse_text(t.trim(), tz),
        v => match num(v)? {
            N::I(i) => ts_of(i),
            N::F(x) if x.abs() < 9.0e18 => ts_of(x as i64),
            N::F(_) => None,
        },
    }
}

fn parse_text(t: &str, tz: &TimeZone) -> Option<Timestamp> {
    if t.is_empty() || t.len() > MAX_DATE_TEXT {
        return None;
    }
    if let Ok(ts) = Timestamp::from_str(t) {
        return Some(ts);
    }
    if let Ok(dt) = DateTime::from_str(t) {
        return dt.to_zoned(tz.clone()).ok().map(|z| z.timestamp());
    }
    if let Some(dt) = loose(t) {
        return dt.to_zoned(tz.clone()).ok().map(|z| z.timestamp());
    }
    // a number as text: microseconds
    t.parse::<i64>().ok().and_then(ts_of)
}

/// `yyyy-M-d`, `yyyy/M/d` or `M/d/yyyy`, then optionally `H:mm[:ss[.f]]` and `am`/`pm`.
fn loose(t: &str) -> Option<DateTime> {
    let mut it = t.splitn(2, [' ', 'T']);
    let date = it.next()?;
    let time = it.next().unwrap_or("").trim();
    let parts: Vec<&str> = date.split(['-', '/']).collect();
    if parts.len() != 3
        || parts
            .iter()
            .any(|p| p.is_empty() || !p.chars().all(|c| c.is_ascii_digit()))
    {
        return None;
    }
    let n = |p: &str| p.parse::<i32>().ok();
    let (y, m, d) = if parts[0].len() == 4 {
        (n(parts[0])?, n(parts[1])?, n(parts[2])?)
    } else if parts[2].len() == 4 && date.contains('/') {
        (n(parts[2])?, n(parts[0])?, n(parts[1])?)
    } else {
        return None;
    };
    let (mut h, mut mi, mut sec, mut nanos) = (0i32, 0i32, 0i32, 0i32);
    if !time.is_empty() {
        let low = time.to_ascii_lowercase();
        let (clock, pm, am) = if let Some(c) = low.strip_suffix("pm") {
            (c.trim().to_owned(), true, false)
        } else if let Some(c) = low.strip_suffix("am") {
            (c.trim().to_owned(), false, true)
        } else {
            (low.clone(), false, false)
        };
        let f: Vec<&str> = clock.split(':').collect();
        if f.len() < 2 || f.len() > 3 {
            return None;
        }
        h = f[0].parse().ok()?;
        mi = f[1].parse().ok()?;
        if let Some(s) = f.get(2) {
            let (whole, frac) = s.split_once('.').unwrap_or((s, ""));
            sec = whole.parse().ok()?;
            if !frac.is_empty() {
                if frac.len() > 9 || !frac.chars().all(|c| c.is_ascii_digit()) {
                    return None;
                }
                nanos = format!("{frac:0<9}").parse().ok()?;
            }
        }
        if pm && h < 12 {
            h += 12;
        }
        if am && h == 12 {
            h = 0;
        }
    }
    DateTime::new(
        i16::try_from(y).ok()?,
        i8::try_from(m).ok()?,
        i8::try_from(d).ok()?,
        i8::try_from(h).ok()?,
        i8::try_from(mi).ok()?,
        i8::try_from(sec).ok()?,
        nanos,
    )
    .ok()
}

/// A whole part of a date block (`year`, `day`, …), truncated; `None` when it is no number.
fn part(v: &View, name: &str) -> Option<i64> {
    num(v.p(name)).map(|n| match n {
        N::I(i) => i,
        N::F(x) => x.trunc().clamp(-1e15, 1e15) as i64,
    })
}

pub(super) fn calc(op: Op, v: &View) -> Outs {
    let one = |val: Value| vec![("out", val, false)];
    let Some(tz) = zone(v.p("time_zone")) else {
        return match op {
            Op::Parse => PARSE_OUT
                .iter()
                .map(|(p, _)| (*p, Value::Null, false))
                .collect(),
            Op::Range => RANGE_OUT
                .iter()
                .map(|(p, _)| (*p, Value::Null, false))
                .collect(),
            _ => one(Value::Null),
        };
    };
    match op {
        Op::Now => one(Value::Int(v.now_us as i64)),
        Op::DateTime => one(make(v, &tz).map_or(Value::Null, us)),
        Op::Format => {
            let pat = match v.p("format") {
                Value::Str(p) if p.len() <= MAX_PATTERN => p.clone(),
                Value::Null => DEFAULT_FORMAT.to_owned(),
                _ => return one(Value::Null),
            };
            // `auto`: the offset written in the input text
            let tz = match (v.p("time_zone"), v.inv) {
                (Value::Str(a), Value::Str(t)) if a == "auto" => {
                    written_offset(t).map_or(tz, TimeZone::fixed)
                }
                _ => tz,
            };
            one(date_of(v.inv, &tz)
                .and_then(|ts| format(ts, &tz, &pat))
                .map_or(Value::Null, Value::Str))
        }
        Op::Parse => {
            let parts = date_of(v.inv, &tz).map(|ts| (ts, tz.to_datetime(ts)));
            let Some((ts, dt)) = parts else {
                return PARSE_OUT
                    .iter()
                    .map(|(p, _)| (*p, Value::Null, false))
                    .collect();
            };
            let i = |x: i64| Value::Int(x);
            vec![
                ("time", us(ts), false),
                ("year", i(dt.year().into()), false),
                ("month", i(dt.month().into()), false),
                ("day", i(dt.day().into()), false),
                ("hour", i(dt.hour().into()), false),
                ("minute", i(dt.minute().into()), false),
                ("second", i(dt.second().into()), false),
                ("millisecond", i(dt.millisecond().into()), false),
                (
                    "weekday",
                    i(dt.weekday().to_monday_one_offset().into()),
                    false,
                ),
            ]
        }
        Op::Math => {
            let r = date_of(v.inv, &tz).and_then(|ts| {
                let sign = if matches!(v.p("op"), Value::Str(o) if o == "before") {
                    -1
                } else {
                    1
                };
                let p = |n| part(v, n).unwrap_or(0).checked_mul(sign);
                add(
                    ts,
                    &tz,
                    [
                        p("year")?,
                        p("month")?,
                        p("day")?,
                        p("hour")?,
                        p("minute")?,
                        p("second")?,
                        p("millisecond")?,
                    ],
                )
            });
            one(r.map_or(Value::Null, us))
        }
        Op::Range => {
            // the block gives the text in use (a `next`/`previous` replaces `in`)
            let ws = match v.p("week_start") {
                Value::Str(w) => WEEK_STARTS.iter().position(|x| x == w).unwrap_or(0),
                _ => 0,
            };
            let text = match v.inv {
                Value::Str(t) if t.len() <= 2 * MAX_DATE_TEXT + 8 => t.trim().to_owned(),
                _ => String::new(),
            };
            match range(&text, v.now_us as i64, &tz, ws) {
                None => RANGE_OUT
                    .iter()
                    .map(|(p, _)| (*p, Value::Null, false))
                    .collect(),
                Some(r) => range_outs(&r, v, &tz, &text),
            }
        }
    }
}

fn written_offset(t: &str) -> Option<Offset> {
    let t = t.trim();
    if t.ends_with('Z') {
        return Some(Offset::UTC);
    }
    let tail = t.get(t.len().checked_sub(6)?..)?;
    offset_of(tail)
}

/// `date_time`: the parts in `tz`, normalised as a calendar does (month 13 is January of the
/// next year, day 0 the last day of the month before).
fn make(v: &View, tz: &TimeZone) -> Option<Timestamp> {
    let y = part(v, "year")?;
    let base = DateTime::new(i16::try_from(y).ok()?, 1, 1, 0, 0, 0, 0).ok()?;
    let p = |n: &str, d: i64| part(v, n).unwrap_or(d);
    // one unit at a time: a span holds one sign
    let mut dt = base;
    for (unit, n) in [
        (5, p("month", 1) - 1),
        (3, p("day", 1) - 1),
        (2, p("hour", 0)),
        (1, p("minute", 0)),
        (0, p("second", 0)),
    ] {
        dt = dt.checked_add(span_of(unit, n)?).ok()?;
    }
    dt = dt
        .checked_add(Span::new().try_milliseconds(p("millisecond", 0)).ok()?)
        .ok()?;
    dt.to_zoned(tz.clone()).ok().map(|z| z.timestamp())
}

/// `date_math`: years, months and days on the calendar of `tz` (Jan 31 + 1 month is the last
/// day of February), then hours, minutes, seconds and milliseconds as elapsed time.
fn add(ts: Timestamp, tz: &TimeZone, p: [i64; 7]) -> Option<Timestamp> {
    // one unit at a time: a span holds one sign
    let mut z = ts.to_zoned(tz.clone());
    for (unit, n) in [(6, p[0]), (5, p[1]), (3, p[2])] {
        z = z.checked_add(span_of(unit, n)?).ok()?;
    }
    let mut ts = z.timestamp();
    for (unit, n) in [(2, p[3]), (1, p[4]), (0, p[5])] {
        ts = ts.checked_add(span_of(unit, n)?).ok()?;
    }
    ts.checked_add(Span::new().try_milliseconds(p[6]).ok()?)
        .ok()
}

const MONTHS: [&str; 12] = [
    "January",
    "February",
    "March",
    "April",
    "May",
    "June",
    "July",
    "August",
    "September",
    "October",
    "November",
    "December",
];
const DAYS: [&str; 7] = [
    "Monday",
    "Tuesday",
    "Wednesday",
    "Thursday",
    "Friday",
    "Saturday",
    "Sunday",
];

/// `ts` in `tz` by an ICU-like pattern: `y` (`yy`: two digits), `M` (`MMM` short, `MMMM` full
/// name), `d`, `D` (day of year), `E` (`EEEE` full name), `H`, `h`, `m`, `s`, `S` (fraction
/// digits), `a` (AM/PM), `Z` (`+0200`), `xxx`/`XXX` (`+02:00`), `'text'` (`''` is a quote);
/// other characters as they are. English names. `None`: a pattern longer than 128 bytes.
pub fn format(ts: Timestamp, tz: &TimeZone, pat: &str) -> Option<String> {
    if pat.len() > MAX_PATTERN {
        return None;
    }
    let z = ts.to_zoned(tz.clone());
    let dt = z.datetime();
    let off = z.offset().seconds();
    let mut out = String::new();
    let cs: Vec<char> = pat.chars().collect();
    let mut i = 0;
    while i < cs.len() {
        let c = cs[i];
        if c == '\'' {
            // a quoted text; '' is one quote
            if cs.get(i + 1) == Some(&'\'') {
                out.push('\'');
                i += 2;
                continue;
            }
            i += 1;
            while i < cs.len() {
                if cs[i] == '\'' {
                    if cs.get(i + 1) == Some(&'\'') {
                        out.push('\'');
                        i += 2;
                        continue;
                    }
                    break;
                }
                out.push(cs[i]);
                i += 1;
            }
            i += 1;
            continue;
        }
        let mut n = 1;
        while cs.get(i + n) == Some(&c) {
            n += 1;
        }
        let pad = |x: i64, w: usize| format!("{x:0w$}");
        match c {
            'y' => {
                let y = i64::from(dt.year());
                out.push_str(&if n == 2 {
                    pad(y.rem_euclid(100), 2)
                } else {
                    pad(y, n)
                });
            }
            'M' | 'L' => {
                let m = usize::try_from(dt.month()).unwrap_or(1).clamp(1, 12);
                match n {
                    1 | 2 => out.push_str(&pad(m as i64, n)),
                    3 => out.push_str(&MONTHS[m - 1][..3]),
                    _ => out.push_str(MONTHS[m - 1]),
                }
            }
            'd' => out.push_str(&pad(dt.day().into(), n)),
            'D' => out.push_str(&pad(dt.day_of_year().into(), n)),
            'E' => {
                let w = usize::try_from(dt.weekday().to_monday_zero_offset()).unwrap_or(0) % 7;
                out.push_str(if n >= 4 { DAYS[w] } else { &DAYS[w][..3] });
            }
            'H' => out.push_str(&pad(dt.hour().into(), n)),
            'k' => out.push_str(&pad(if dt.hour() == 0 { 24 } else { dt.hour().into() }, n)),
            'h' => {
                let h = i64::from(dt.hour()) % 12;
                out.push_str(&pad(if h == 0 { 12 } else { h }, n));
            }
            'K' => out.push_str(&pad(i64::from(dt.hour()) % 12, n)),
            'm' => out.push_str(&pad(dt.minute().into(), n)),
            's' => out.push_str(&pad(dt.second().into(), n)),
            'S' => {
                let f = format!("{:09}", dt.subsec_nanosecond());
                out.push_str(&f[..n.min(9)]);
                for _ in 9..n {
                    out.push('0');
                }
            }
            'a' => out.push_str(if dt.hour() < 12 { "AM" } else { "PM" }),
            'Z' | 'x' | 'X' => {
                if c == 'X' && off == 0 {
                    out.push('Z');
                } else {
                    let sign = if off < 0 { '-' } else { '+' };
                    let (h, m) = (off.abs() / 3600, off.abs() % 3600 / 60);
                    if c == 'Z' || n < 3 {
                        out.push_str(&format!("{sign}{h:02}{m:02}"));
                    } else {
                        out.push_str(&format!("{sign}{h:02}:{m:02}"));
                    }
                }
            }
            c if c.is_ascii_alphabetic() => {
                // a letter the pattern does not know: as it is
                for _ in 0..n {
                    out.push(c);
                }
            }
            c => {
                for _ in 0..n {
                    out.push(c);
                }
            }
        }
        i += n;
    }
    Some(out)
}

/// A range of time: `[start, end]` (inclusive, microseconds) and its neighbours as texts.
#[derive(Debug, Clone, PartialEq)]
pub struct Range {
    pub start: i64,
    pub end: i64,
    pub next: String,
    pub previous: String,
    /// The input was a name (`today`) or a relative range (`current3days`).
    pub special: bool,
}

const NAMED: &[(&str, &str, &str)] = &[
    // name, next, previous
    ("today", "today", "yesterday"),
    ("yesterday", "today", "yesterday"),
    ("thisWeek", "thisWeek", "lastWeek"),
    ("lastWeek", "thisWeek", "lastWeek"),
    ("thisMonth", "thisMonth", "lastMonth"),
    ("lastMonth", "thisMonth", "lastMonth"),
    ("thisYear", "thisYear", "lastYear"),
    ("lastYear", "thisYear", "lastYear"),
];

/// A range name in either spelling (`thisWeek`, `this_week`).
fn named(t: &str) -> Option<&'static (&'static str, &'static str, &'static str)> {
    let flat: String = t
        .chars()
        .filter(|c| *c != '_')
        .collect::<String>()
        .to_ascii_lowercase();
    NAMED
        .iter()
        .find(|(n, _, _)| n.to_ascii_lowercase() == flat)
}

/// Whether a range text depends on the clock: a name or a relative range.
pub fn is_relative(t: &str) -> bool {
    named(t).is_some() || relative(t).is_some()
}

const UNITS: &[&str] = &[
    "seconds", "minutes", "hours", "days", "weeks", "months", "years",
];

/// `currentN<unit>` / `previousN<unit>`: (previous, N, unit index).
fn relative(t: &str) -> Option<(bool, i64, usize)> {
    let (prev, rest) = if let Some(r) = t.strip_prefix("current") {
        (false, r)
    } else {
        (true, t.strip_prefix("previous")?)
    };
    let digits = rest.find(|c: char| !c.is_ascii_digit())?;
    let n: i64 = rest[..digits]
        .parse()
        .ok()
        .filter(|n| *n >= 1 && *n <= 100_000)?;
    let unit = UNITS.iter().position(|u| *u == &rest[digits..])?;
    Some((prev, n, unit))
}

fn span_of(unit: usize, n: i64) -> Option<Span> {
    let s = Span::new();
    match unit {
        0 => s.try_seconds(n),
        1 => s.try_minutes(n),
        2 => s.try_hours(n),
        3 => s.try_days(n),
        4 => s.try_weeks(n),
        5 => s.try_months(n),
        _ => s.try_years(n),
    }
    .ok()
}

fn at(d: Date, tz: &TimeZone) -> Option<i64> {
    d.to_datetime(jiff::civil::Time::midnight())
        .to_zoned(tz.clone())
        .ok()
        .map(|z| z.timestamp().as_microsecond())
}

/// `[from, to)` as an inclusive range in microseconds.
fn days(from: Date, to: Date, tz: &TimeZone) -> Option<(i64, i64)> {
    Some((at(from, tz)?, at(to, tz)? - 1))
}

fn iso(us: i64, tz: &TimeZone) -> String {
    ts_of(us)
        .and_then(|ts| format(ts, tz, DEFAULT_FORMAT))
        .unwrap_or_default()
}

/// The range a text names, at `now`, in `tz`, with weeks from `week_start` (0 = Monday).
pub fn range(t: &str, now: i64, tz: &TimeZone, week_start: usize) -> Option<Range> {
    let today = ts_of(now)?.to_zoned(tz.clone()).date();
    if let Some((name, next, previous)) = named(t) {
        let (from, to) = match *name {
            "today" => (today, today.tomorrow().ok()?),
            "yesterday" => (today.yesterday().ok()?, today),
            "thisWeek" | "lastWeek" => {
                let wd = i64::from(today.weekday().to_monday_zero_offset());
                let back = (wd - week_start as i64).rem_euclid(7);
                let start = today.checked_sub(Span::new().days(back)).ok()?;
                let start = if *name == "lastWeek" {
                    start.checked_sub(Span::new().days(7)).ok()?
                } else {
                    start
                };
                (start, start.checked_add(Span::new().days(7)).ok()?)
            }
            "thisMonth" | "lastMonth" => {
                let first = today.first_of_month();
                let first = if *name == "lastMonth" {
                    first.checked_sub(Span::new().months(1)).ok()?
                } else {
                    first
                };
                (first, first.checked_add(Span::new().months(1)).ok()?)
            }
            _ => {
                let first = Date::new(today.year(), 1, 1).ok()?;
                let first = if *name == "lastYear" {
                    first.checked_sub(Span::new().years(1)).ok()?
                } else {
                    first
                };
                (first, first.checked_add(Span::new().years(1)).ok()?)
            }
        };
        let (start, end) = days(from, to, tz)?;
        return Some(Range {
            start,
            end,
            next: (*next).into(),
            previous: (*previous).into(),
            special: true,
        });
    }
    if let Some((prev, n, unit)) = relative(t) {
        // currentN: the last N units up to now; previousN: the N units before those
        let sp = span_of(unit, n)?;
        let nowz = ts_of(now)?.to_zoned(tz.clone());
        let a = nowz.checked_sub(sp).ok()?;
        let (start, end) = if prev {
            (
                a.checked_sub(sp).ok()?.timestamp().as_microsecond(),
                a.timestamp().as_microsecond() - 1,
            )
        } else {
            (a.timestamp().as_microsecond(), now)
        };
        let unit_name = UNITS[unit];
        let (next, previous) = if prev {
            (
                format!("current{n}{unit_name}"),
                format!(
                    "{}/{}",
                    iso_shift(start, end, -1, tz),
                    iso_end(start - 1, tz)
                ),
            )
        } else {
            (
                format!("current{n}{unit_name}"),
                format!("previous{n}{unit_name}"),
            )
        };
        return Some(Range {
            start,
            end,
            next,
            previous,
            special: true,
        });
    }
    let digits = |s: &str| !s.is_empty() && s.chars().all(|c| c.is_ascii_digit());
    let p: Vec<&str> = t.split('-').collect();
    if p.len() == 1 && p[0].len() == 4 && digits(p[0]) {
        let y: i16 = p[0].parse().ok()?;
        let from = Date::new(y, 1, 1).ok()?;
        let (start, end) = days(from, from.checked_add(Span::new().years(1)).ok()?, tz)?;
        return Some(Range {
            start,
            end,
            next: format!("{:04}", y + 1),
            previous: format!("{:04}", y - 1),
            special: false,
        });
    }
    if p.len() == 2 && p[0].len() == 4 && p[1].len() == 2 && digits(p[0]) && digits(p[1]) {
        let from = Date::new(p[0].parse().ok()?, p[1].parse().ok()?, 1).ok()?;
        let to = from.checked_add(Span::new().months(1)).ok()?;
        let before = from.checked_sub(Span::new().months(1)).ok()?;
        let (start, end) = days(from, to, tz)?;
        let ym = |d: Date| format!("{:04}-{:02}", d.year(), d.month());
        return Some(Range {
            start,
            end,
            next: ym(to),
            previous: ym(before),
            special: false,
        });
    }
    if p.len() == 3
        && p[0].len() == 4
        && p[1].len() == 2
        && p[2].len() == 2
        && p.iter().all(|x| digits(x))
    {
        let from = Date::new(p[0].parse().ok()?, p[1].parse().ok()?, p[2].parse().ok()?).ok()?;
        let to = from.tomorrow().ok()?;
        let (start, end) = days(from, to, tz)?;
        let ymd = |d: Date| format!("{:04}-{:02}-{:02}", d.year(), d.month(), d.day());
        return Some(Range {
            start,
            end,
            next: ymd(to),
            previous: ymd(from.yesterday().ok()?),
            special: false,
        });
    }
    // `<date>/<date>`: an end written without a fraction is the whole second
    let (a, b) = t.split_once('/')?;
    let start = date_of(&Value::Str(a.trim().into()), tz)?.as_microsecond();
    let b = b.trim();
    let mut end = date_of(&Value::Str(b.into()), tz)?.as_microsecond();
    if !b.contains('.') && end.rem_euclid(1_000_000) == 0 && b.contains(':') {
        end += 999_999;
    }
    if end < start {
        return None;
    }
    Some(Range {
        start,
        end,
        next: format!(
            "{}/{}",
            iso_shift(start, end, 1, tz),
            iso_end(end + 1 + (end - start), tz)
        ),
        previous: format!(
            "{}/{}",
            iso_shift(start, end, -1, tz),
            iso_end(start - 1, tz)
        ),
        special: false,
    })
}

/// The start of the range `dir` lengths away, as text.
fn iso_shift(start: i64, end: i64, dir: i64, tz: &TimeZone) -> String {
    iso(start + dir * (end - start + 1), tz)
}

/// An end as text: to the second (an end of `.999999` reads as its whole second).
fn iso_end(end: i64, tz: &TimeZone) -> String {
    iso(end, tz)
}

fn range_outs(r: &Range, v: &View, tz: &TimeZone, text: &str) -> Outs {
    let fmt = match v.p("format") {
        Value::Str(f) if f.len() <= MAX_PATTERN => f.clone(),
        Value::Null => DEFAULT_FORMAT.into(),
        _ => String::new(),
    };
    let delim = match v.p("range_delimiter") {
        Value::Str(d) if !d.is_empty() && d.len() <= 16 => d.clone(),
        _ => "/".into(),
    };
    let keep = match v.p("keep_special") {
        Value::Str(k) => k.as_str(),
        _ => "none",
    };
    let f = |us: i64| {
        ts_of(us)
            .and_then(|ts| format(ts, tz, &fmt))
            .unwrap_or_default()
    };
    let formatted = if keep == "raw" && r.special || fmt.is_empty() {
        text.to_owned()
    } else {
        let (a, b) = (f(r.start), f(r.end));
        if keep == "formatted" && a == b {
            a
        } else {
            format!("{a}{delim}{b}")
        }
    };
    vec![
        ("start", Value::Int(r.start), false),
        ("end", Value::Int(r.end), false),
        (
            "this_range",
            Value::Str(format!("{}/{}", iso(r.start, tz), iso(r.end, tz))),
            false,
        ),
        ("next_range", Value::Str(r.next.clone()), false),
        ("previous_range", Value::Str(r.previous.clone()), false),
        ("formatted", Value::Str(formatted), false),
        ("duration", Value::Int(r.end - r.start + 1), false),
    ]
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::BTreeMap;

    /// 2026-10-29T13:00:00Z
    const T: i64 = 1_793_278_800_000_000;

    fn run(op: Op, x: Value, now: i64, kv: &[(&str, Value)]) -> Vec<(&'static str, Value)> {
        let params: BTreeMap<String, Value> = shape(op)
            .params
            .into_iter()
            .map(|p| (p.name.to_owned(), p.default))
            .chain(kv.iter().map(|(k, v)| ((*k).to_owned(), v.clone())))
            .collect();
        calc(
            op,
            &View {
                inv: &x,
                params: &params,
                items: Vec::new(),
                now_us: now as u64,
            },
        )
        .into_iter()
        .map(|(p, v, _)| (p, v))
        .collect()
    }

    fn get(r: &[(&str, Value)], port: &str) -> Value {
        r.iter().find(|(p, _)| *p == port).unwrap().1.clone()
    }

    fn i(x: i64) -> Value {
        Value::Int(x)
    }

    #[test]
    fn parts_and_dates() {
        let dt = run(
            Op::DateTime,
            Value::Null,
            0,
            &[
                ("year", i(2026)),
                ("month", i(10)),
                ("day", i(29)),
                ("hour", i(13)),
            ],
        );
        assert_eq!(get(&dt, "out"), i(T));
        // month 13 is January of the next year; day 0 the last day before
        let dt = run(
            Op::DateTime,
            Value::Null,
            0,
            &[("year", i(2025)), ("month", i(13)), ("day", i(0))],
        );
        assert_eq!(
            get(&dt, "out"),
            date_of(&"2025-12-31T00:00:00Z".into(), &TimeZone::UTC)
                .map(us)
                .unwrap()
        );
        let k = run(
            Op::DateTime,
            Value::Null,
            0,
            &[
                ("year", i(2026)),
                ("month", i(10)),
                ("day", i(29)),
                ("hour", i(15)),
                ("time_zone", "Europe/Kyiv".into()),
            ],
        );
        assert_eq!(
            get(&k, "out"),
            i(T),
            "15:00 in Kyiv (+02:00 after the DST end) is 13:00Z"
        );
        let p = run(Op::Parse, "2026-02-03T04:05:06".into(), 0, &[]);
        assert_eq!(get(&p, "weekday"), i(2), "Tuesday");
        assert_eq!(get(&p, "hour"), i(4));
        let p = run(
            Op::Parse,
            "2024-03-15T13:05:07Z".into(),
            0,
            &[("time_zone", "+02:00".into())],
        );
        assert_eq!(get(&p, "hour"), i(15));
        let p = run(Op::Parse, "3/5/2024 1:02:03 pm".into(), 0, &[]);
        assert_eq!(
            (get(&p, "month"), get(&p, "day"), get(&p, "hour")),
            (i(3), i(5), i(13))
        );
        let p = run(Op::Parse, "2024/3/5 10:00".into(), 0, &[]);
        assert_eq!(get(&p, "hour"), i(10));
        assert_eq!(
            get(&run(Op::Parse, "nope".into(), 0, &[]), "time"),
            Value::Null
        );
        assert_eq!(
            get(
                &run(Op::Parse, i(T), 0, &[("time_zone", "Mars/Base".into())]),
                "year"
            ),
            Value::Null
        );
    }

    #[test]
    fn formats() {
        let ts = ts_of(T).unwrap();
        let f = |p: &str, tz: &str| format(ts, &zone(&tz.into()).unwrap(), p).unwrap();
        assert_eq!(f("yyyy-MM-dd HH:mm", "UTC"), "2026-10-29 13:00");
        assert_eq!(f(DEFAULT_FORMAT, "Europe/Kyiv"), "2026-10-29T15:00:00");
        assert_eq!(f("E, MMM d, yyyy", "UTC"), "Thu, Oct 29, 2026");
        assert_eq!(
            f("EEEE d MMMM yy h:mm a", "UTC"),
            "Thursday 29 October 26 1:00 PM"
        );
        assert_eq!(f("HH:mm:ss.SSS xxx", "-05:30"), "07:30:00.000 -05:30");
        assert_eq!(f("Z", "Europe/Kyiv"), "+0200");
        assert_eq!(
            f("'day' D 'of' yyyy, 'it''s'", "UTC"),
            "day 302 of 2026, it's"
        );
        assert_eq!(format(ts, &TimeZone::UTC, &"y".repeat(200)), None);
        let r = run(
            Op::Format,
            "2024-03-15T10:00:00+05:00".into(),
            0,
            &[("time_zone", "auto".into()), ("format", "HH:mm xxx".into())],
        );
        assert_eq!(get(&r, "out"), "10:00 +05:00".into());
    }

    #[test]
    fn date_math() {
        let r = run(Op::Math, i(T), 0, &[("op", "before".into()), ("day", i(7))]);
        assert_eq!(get(&r, "out"), i(T - 7 * 86_400_000_000));
        // Jan 31 + 1 month: the last day of February
        let r = run(
            Op::Math,
            "2024-01-31T00:00:00Z".into(),
            0,
            &[("month", i(1))],
        );
        assert_eq!(
            get(&r, "out"),
            date_of(&"2024-02-29T00:00:00Z".into(), &TimeZone::UTC)
                .map(us)
                .unwrap()
        );
        // a calendar day over a DST change is 23 hours long
        let r = run(
            Op::Math,
            "2026-03-28T12:00:00+02:00".into(),
            0,
            &[("day", i(1)), ("time_zone", "Europe/Kyiv".into())],
        );
        assert_eq!(
            get(&r, "out"),
            date_of(&"2026-03-29T12:00:00+03:00".into(), &TimeZone::UTC)
                .map(us)
                .unwrap()
        );
        assert_eq!(
            get(&run(Op::Math, i(T), 0, &[("year", i(1_000_000))]), "out"),
            Value::Null
        );
    }

    #[test]
    fn ranges() {
        let tz = TimeZone::UTC;
        let r = run(
            Op::Range,
            "2026-10".into(),
            T,
            &[("format", "yyyy-MM-dd".into())],
        );
        assert_eq!(get(&r, "formatted"), "2026-10-01/2026-10-31".into());
        assert_eq!(get(&r, "next_range"), "2026-11".into());
        assert_eq!(
            get(&r, "this_range"),
            "2026-10-01T00:00:00/2026-10-31T23:59:59".into()
        );
        let today = range("today", T, &tz, 0).unwrap();
        assert_eq!(iso(today.start, &tz), "2026-10-29T00:00:00");
        assert_eq!(today.end - today.start + 1, 86_400_000_000);
        // weeks start on Monday by default, on Sunday when asked
        let w = range("thisWeek", T, &tz, 0).unwrap();
        assert_eq!(iso(w.start, &tz), "2026-10-26T00:00:00");
        let w = range("this_week", T, &tz, 6).unwrap();
        assert_eq!(iso(w.start, &tz), "2026-10-25T00:00:00");
        let lw = range("lastWeek", T, &tz, 0).unwrap();
        assert_eq!(iso(lw.start, &tz), "2026-10-19T00:00:00");
        // previousN is the period before currentN
        let c = range("current3days", T, &tz, 0).unwrap();
        let p = range("previous3days", T, &tz, 0).unwrap();
        assert_eq!(p.end + 1, c.start);
        assert_eq!(c.end, T);
        assert_eq!(p.next, "current3days");
        assert_eq!(c.previous, "previous3days");
        // a range in another zone
        let k = range("today", T, &zone(&"Europe/Kyiv".into()).unwrap(), 0).unwrap();
        assert_eq!(iso(k.start, &tz), "2026-10-28T22:00:00");
        // a/b: the end second is whole; the neighbour starts after it
        let ab = range("2024-03-15T00:00:00/2024-03-16T00:00:00", T, &tz, 0).unwrap();
        assert_eq!(ab.end - ab.start + 1, 86_401_000_000);
        assert!(ab.next.starts_with("2024-03-16T00:00:01"), "{}", ab.next);
        assert!(range("previous0days", T, &tz, 0).is_none());
        assert!(range("2024-13", T, &tz, 0).is_none());
        assert!(is_relative("today") && is_relative("current2hours") && !is_relative("2024"));
        let r = run(
            Op::Range,
            "today".into(),
            T,
            &[("keep_special", "raw".into())],
        );
        assert_eq!(get(&r, "formatted"), "today".into());
        let r = run(
            Op::Range,
            "2026-10-29".into(),
            T,
            &[
                ("keep_special", "formatted".into()),
                ("format", "yyyy-MM-dd".into()),
            ],
        );
        assert_eq!(get(&r, "formatted"), "2026-10-29".into());
    }

    #[test]
    fn now_is_the_given_clock() {
        assert_eq!(get(&run(Op::Now, Value::Null, T, &[]), "out"), i(T));
    }
}
