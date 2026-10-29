//! The RRULE subset: parse and canonical text.

use std::fmt;
use std::str::FromStr;

use jiff::civil::Weekday;

use crate::model::{
    format_local, parse_local, DaySpec, Freq, Invalid, Rule, RuleEnd, MAX_COUNT, MAX_INTERVAL,
};

const DAYS: [(&str, Weekday); 7] = [
    ("MO", Weekday::Monday),
    ("TU", Weekday::Tuesday),
    ("WE", Weekday::Wednesday),
    ("TH", Weekday::Thursday),
    ("FR", Weekday::Friday),
    ("SA", Weekday::Saturday),
    ("SU", Weekday::Sunday),
];

fn day_code(d: Weekday) -> &'static str {
    DAYS.iter().find(|(_, w)| *w == d).map_or("MO", |(c, _)| c)
}

fn freq_name(f: Freq) -> &'static str {
    match f {
        Freq::Hourly => "HOURLY",
        Freq::Daily => "DAILY",
        Freq::Weekly => "WEEKLY",
        Freq::Monthly => "MONTHLY",
        Freq::Yearly => "YEARLY",
    }
}

impl Rule {
    /// The shortest span between two occurrences, in seconds. A window must not be longer.
    pub(crate) fn period_secs(&self) -> i64 {
        const DAY: i64 = 86_400;
        let n = i64::from(self.interval);
        match self.freq {
            Freq::Hourly => n * 3600,
            Freq::Daily => n * DAY,
            Freq::Weekly => {
                let mut days: Vec<i64> = self
                    .by_day
                    .iter()
                    .map(|d| i64::from(d.day.to_monday_zero_offset()))
                    .collect();
                days.sort_unstable();
                days.dedup();
                match (days.first(), days.last()) {
                    (Some(first), Some(last)) if days.len() > 1 => {
                        let wrap = first + 7 - last;
                        let gap = days.windows(2).map(|w| w[1] - w[0]).min().unwrap_or(7);
                        gap.min(wrap) * DAY
                    }
                    _ => 7 * n * DAY,
                }
            }
            Freq::Monthly => 28 * n * DAY,
            Freq::Yearly => 365 * n * DAY,
        }
    }
}

fn num<T: FromStr>(part: &str, v: &str) -> Result<T, Invalid> {
    v.parse()
        .map_err(|_| Invalid::new(part, format!("not a number: {v:?}")))
}

fn list<T>(
    part: &str,
    v: &str,
    one: impl FnMut(&str) -> Result<T, Invalid>,
) -> Result<Vec<T>, Invalid> {
    let out = v.split(',').map(one).collect::<Result<Vec<_>, _>>()?;
    if out.is_empty() {
        return Err(Invalid::new(part, "empty list"));
    }
    Ok(out)
}

fn parse_day(freq: Freq, v: &str) -> Result<DaySpec, Invalid> {
    let bad = || Invalid::new("BYDAY", format!("expected [ordinal]MO..SU, got {v:?}"));
    if v.len() < 2 || !v.is_ascii() {
        return Err(bad());
    }
    let (ord, code) = v.split_at(v.len() - 2);
    let day = DAYS.iter().find(|(c, _)| *c == code).ok_or_else(bad)?.1;
    if ord.is_empty() {
        return Ok(DaySpec { ordinal: None, day });
    }
    // the ordinal counts within the month, also with YEARLY (ruling R5)
    let max = match freq {
        Freq::Monthly | Freq::Yearly => 5i16,
        _ => {
            return Err(Invalid::new(
                "BYDAY",
                "an ordinal (like 1MO, -1FR) is allowed only with MONTHLY or YEARLY",
            ))
        }
    };
    let n: i8 = ord.parse().map_err(|_| bad())?;
    if n == 0 || i16::from(n).abs() > max {
        return Err(Invalid::new(
            "BYDAY",
            format!("ordinal must be 1 to {max} or -1 to -{max}"),
        ));
    }
    Ok(DaySpec {
        ordinal: Some(n),
        day,
    })
}

impl FromStr for Rule {
    type Err = Invalid;

    fn from_str(text: &str) -> Result<Rule, Invalid> {
        let mut freq = None;
        let mut interval = None;
        let mut count = None;
        let mut until = None;
        let mut by_day_text = None;
        let mut by_month_day = None;
        let mut by_month = None;
        let mut seen: Vec<String> = Vec::new();
        for part in text.split(';') {
            let Some((k, v)) = part.split_once('=') else {
                return Err(Invalid::new(
                    part.to_ascii_uppercase(),
                    "expected NAME=VALUE",
                ));
            };
            let k = k.trim().to_ascii_uppercase();
            let v = v.trim();
            if seen.contains(&k) {
                return Err(Invalid::new(k, "given twice"));
            }
            seen.push(k.clone());
            match k.as_str() {
                "FREQ" => {
                    freq = Some(match v.to_ascii_uppercase().as_str() {
                        "HOURLY" => Freq::Hourly,
                        "DAILY" => Freq::Daily,
                        "WEEKLY" => Freq::Weekly,
                        "MONTHLY" => Freq::Monthly,
                        "YEARLY" => Freq::Yearly,
                        _ => {
                            return Err(Invalid::new(
                                "FREQ",
                                format!(
                                    "must be HOURLY, DAILY, WEEKLY, MONTHLY or YEARLY, got {v:?}"
                                ),
                            ))
                        }
                    })
                }
                "INTERVAL" => {
                    let n: u32 = num("INTERVAL", v)?;
                    if !(1..=MAX_INTERVAL).contains(&n) {
                        return Err(Invalid::new(
                            "INTERVAL",
                            format!("must be 1 to {MAX_INTERVAL}"),
                        ));
                    }
                    interval = Some(n);
                }
                "COUNT" => {
                    let n: u32 = num("COUNT", v)?;
                    if !(1..=MAX_COUNT).contains(&n) {
                        return Err(Invalid::new("COUNT", format!("must be 1 to {MAX_COUNT}")));
                    }
                    count = Some(n);
                }
                "UNTIL" => until = Some(parse_local("UNTIL", v)?),
                "BYDAY" => by_day_text = Some(v.to_ascii_uppercase()),
                "BYMONTHDAY" => {
                    by_month_day = Some(list("BYMONTHDAY", v, |s| {
                        let n: i8 = num("BYMONTHDAY", s)?;
                        if n == -1 || (1..=31).contains(&n) {
                            Ok(n)
                        } else {
                            Err(Invalid::new(
                                "BYMONTHDAY",
                                "must be 1 to 31, or -1 for the last day",
                            ))
                        }
                    })?)
                }
                "BYMONTH" => {
                    by_month = Some(list("BYMONTH", v, |s| {
                        let n: u8 = num("BYMONTH", s)?;
                        if (1..=12).contains(&n) {
                            Ok(n)
                        } else {
                            Err(Invalid::new("BYMONTH", "must be 1 to 12"))
                        }
                    })?)
                }
                _ => return Err(Invalid::new(k, "part not supported")),
            }
        }
        let freq = freq.ok_or_else(|| Invalid::new("FREQ", "required"))?;
        let end = match (count, until) {
            (Some(_), Some(_)) => {
                return Err(Invalid::new("COUNT", "COUNT and UNTIL exclude each other"))
            }
            (Some(n), None) => RuleEnd::Count(n),
            (None, Some(u)) => RuleEnd::Until(u),
            (None, None) => RuleEnd::Never,
        };
        let mut by_day = match by_day_text {
            Some(t) => list("BYDAY", &t, |s| parse_day(freq, s))?,
            None => Vec::new(),
        };
        by_day.sort_by_key(|d| (d.day.to_monday_zero_offset(), d.ordinal));
        by_day.dedup();
        let mut by_month_day = by_month_day.unwrap_or_default();
        by_month_day.sort_unstable();
        by_month_day.dedup();
        let mut by_month = by_month.unwrap_or_default();
        by_month.sort_unstable();
        by_month.dedup();
        Ok(Rule {
            freq,
            interval: interval.unwrap_or(1),
            end,
            by_day,
            by_month_day,
            by_month,
        })
    }
}

/// Canonical order, coarse to fine: FREQ, INTERVAL, COUNT|UNTIL, BYMONTH, BYMONTHDAY, BYDAY.
impl fmt::Display for Rule {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "FREQ={};INTERVAL={}",
            freq_name(self.freq),
            self.interval
        )?;
        match self.end {
            RuleEnd::Never => {}
            RuleEnd::Count(n) => write!(f, ";COUNT={n}")?,
            RuleEnd::Until(u) => write!(f, ";UNTIL={}", format_local(u))?,
        }
        if !self.by_month.is_empty() {
            let v: Vec<String> = self.by_month.iter().map(u8::to_string).collect();
            write!(f, ";BYMONTH={}", v.join(","))?;
        }
        if !self.by_month_day.is_empty() {
            let v: Vec<String> = self.by_month_day.iter().map(i8::to_string).collect();
            write!(f, ";BYMONTHDAY={}", v.join(","))?;
        }
        if !self.by_day.is_empty() {
            f.write_str(";BYDAY=")?;
            for (i, d) in self.by_day.iter().enumerate() {
                if i > 0 {
                    f.write_str(",")?;
                }
                if let Some(o) = d.ordinal {
                    write!(f, "{o}")?;
                }
                f.write_str(day_code(d.day))?;
            }
        }
        Ok(())
    }
}
