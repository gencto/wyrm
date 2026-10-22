//! Dates and durations without a calendar crate: UTC days, RFC 3339
//! timestamps (as DSA's `Timerange`) and interval names (`5m`, `1h`).

pub const US_PER_S: u64 = 1_000_000;
pub const US_PER_DAY: u64 = 86_400 * US_PER_S;

/// `(year, month, day)` of a day number (days since 1970-01-01).
pub fn civil_from_days(z: i64) -> (i64, u32, u32) {
    let z = z + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = (doy - (153 * mp + 2) / 5 + 1) as u32;
    let m = if mp < 10 { mp + 3 } else { mp - 9 } as u32;
    let y = yoe + era * 400 + i64::from(m <= 2);
    (y, m, d)
}

/// Day number of a civil date.
pub fn days_from_civil(y: i64, m: u32, d: u32) -> i64 {
    let y = if m <= 2 { y - 1 } else { y };
    let era = y.div_euclid(400);
    let yoe = y.rem_euclid(400);
    let mp = i64::from((m + 9) % 12);
    let doy = (153 * mp + 2) / 5 + i64::from(d) - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146_097 + doe - 719_468
}

/// `YYYY-MM-DD` of a day number.
pub fn day_name(day: i64) -> String {
    let (y, m, d) = civil_from_days(day);
    format!("{y:04}-{m:02}-{d:02}")
}

/// Day number of `YYYY-MM-DD`.
pub fn parse_day(s: &str) -> Option<i64> {
    let b = s.as_bytes();
    if b.len() != 10 || b[4] != b'-' || b[7] != b'-' {
        return None;
    }
    let y: i64 = s[..4].parse().ok()?;
    let m: u32 = s[5..7].parse().ok()?;
    let d: u32 = s[8..10].parse().ok()?;
    if !(1..=12).contains(&m) || !(1..=31).contains(&d) {
        return None;
    }
    let day = days_from_civil(y, m, d);
    (civil_from_days(day) == (y, m, d)).then_some(day)
}

/// RFC 3339 in UTC with milliseconds: `2026-10-22T09:30:00.000Z`.
pub fn iso_us(t: u64) -> String {
    let day = (t / US_PER_DAY) as i64;
    let us = t % US_PER_DAY;
    let s = us / US_PER_S;
    format!(
        "{}T{:02}:{:02}:{:02}.{:03}Z",
        day_name(day),
        s / 3600,
        s % 3600 / 60,
        s % 60,
        us % US_PER_S / 1000
    )
}

/// Microseconds since the epoch of an RFC 3339 timestamp
/// (`2026-10-22T09:30:00Z`, fractions and `±HH:MM` offsets allowed) or of a
/// date (`2026-10-22`, its midnight UTC).
pub fn parse_iso(s: &str) -> Option<u64> {
    let s = s.trim();
    if s.len() == 10 {
        let day = parse_day(s)?;
        return u64::try_from(day).ok()?.checked_mul(US_PER_DAY);
    }
    let (date, rest) = s.split_at_checked(10)?;
    let day = parse_day(date)?;
    let rest = rest.strip_prefix(['T', 't', ' '])?;
    let b = rest.as_bytes();
    if b.len() < 8 || b[2] != b':' || b[5] != b':' {
        return None;
    }
    let h: u64 = rest[..2].parse().ok()?;
    let mi: u64 = rest[3..5].parse().ok()?;
    let sec: u64 = rest[6..8].parse().ok()?;
    if h > 23 || mi > 59 || sec > 60 {
        return None;
    }
    let mut rest = &rest[8..];
    let mut frac_us = 0u64;
    if let Some(f) = rest.strip_prefix('.') {
        let n = f.bytes().take_while(u8::is_ascii_digit).count();
        if n == 0 {
            return None;
        }
        let digits = &f[..n.min(6)];
        frac_us = digits.parse::<u64>().ok()? * 10u64.pow(6 - digits.len() as u32);
        rest = &f[n..];
    }
    let offset_s: i64 = match rest {
        "Z" | "z" => 0,
        o if o.len() == 6 && (o.starts_with('+') || o.starts_with('-')) && &o[3..4] == ":" => {
            let oh: i64 = o[1..3].parse().ok()?;
            let om: i64 = o[4..6].parse().ok()?;
            let v = oh * 3600 + om * 60;
            if o.starts_with('-') {
                -v
            } else {
                v
            }
        }
        _ => return None,
    };
    let local_s = day.checked_mul(86_400)? + (h * 3600 + mi * 60 + sec) as i64;
    let utc_s = u64::try_from(local_s - offset_s).ok()?;
    utc_s.checked_mul(US_PER_S)?.checked_add(frac_us)
}

/// A time range as DSA sends it, `<from>/<to>`, or as spec 01 writes it,
/// `<from>..<to>`; an empty end is now. `None` if a side does not parse or
/// the range is backwards.
pub fn parse_range(s: &str, now: u64) -> Option<(u64, u64)> {
    let (a, b) = s.split_once("..").or_else(|| s.split_once('/'))?;
    let from = parse_iso(a)?;
    let to = if b.trim().is_empty() {
        now
    } else {
        parse_iso(b)?
    };
    (from <= to).then_some((from, to))
}

/// An interval name: `none` (or empty) → `None`; `<n><unit>` with unit
/// `s`, `m`, `h`, `d`, `w` → microseconds. DSA also writes `1M`/`1Y`;
/// months and years are not fixed lengths, so they are refused.
pub fn parse_interval(s: &str) -> Result<Option<u64>, String> {
    let s = s.trim();
    if s.is_empty() || s.eq_ignore_ascii_case("none") {
        return Ok(None);
    }
    let split = s
        .find(|c: char| !c.is_ascii_digit())
        .ok_or_else(|| format!("interval {s:?}: a number and a unit (5m)"))?;
    let (n, unit) = s.split_at(split);
    let n: u64 = n
        .parse()
        .map_err(|_| format!("interval {s:?}: a number and a unit (5m)"))?;
    let unit_s = match unit {
        "s" => 1,
        "m" => 60,
        "h" => 3600,
        "d" => 86_400,
        "w" => 7 * 86_400,
        _ => return Err(format!("interval {s:?}: unit s, m, h, d or w")),
    };
    if n == 0 {
        return Err(format!("interval {s:?}: more than zero"));
    }
    n.checked_mul(unit_s * US_PER_S)
        .map(Some)
        .ok_or_else(|| format!("interval {s:?}: too long"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn days_round_trip() {
        for day in [-1000, 0, 1, 365, 19_000, 20_748, 100_000] {
            let (y, m, d) = civil_from_days(day);
            assert_eq!(days_from_civil(y, m, d), day);
            assert_eq!(parse_day(&day_name(day)), Some(day));
        }
        assert_eq!(day_name(0), "1970-01-01");
        assert_eq!(parse_day("2026-02-30"), None);
    }

    #[test]
    fn timestamps() {
        let t = parse_iso("2026-10-22T09:30:15.250Z").unwrap();
        assert_eq!(iso_us(t), "2026-10-22T09:30:15.250Z");
        assert_eq!(parse_iso("2026-10-22T12:30:15.25+03:00"), Some(t));
        assert_eq!(parse_iso("2026-10-22T05:30:15.250-04:00"), Some(t));
        assert_eq!(
            parse_iso("2026-10-22"),
            Some(parse_iso("2026-10-22T00:00:00Z").unwrap())
        );
        assert_eq!(parse_iso("2026-10-22T25:00:00Z"), None);
        assert_eq!(parse_iso("yesterday"), None);
        let now = t + 10;
        assert_eq!(
            parse_range("2026-10-22T09:30:15.250Z..", now),
            Some((t, now))
        );
        let midnight = parse_iso("2026-10-22").unwrap();
        assert_eq!(
            parse_range("2026-10-22/2026-10-23", now),
            Some((midnight, midnight + US_PER_DAY))
        );
        assert_eq!(parse_range("2026-10-23..2026-10-22", now), None);
    }

    #[test]
    fn intervals() {
        assert_eq!(parse_interval("none"), Ok(None));
        assert_eq!(parse_interval(""), Ok(None));
        assert_eq!(parse_interval("5m"), Ok(Some(300 * US_PER_S)));
        assert_eq!(parse_interval("1d"), Ok(Some(US_PER_DAY)));
        assert!(parse_interval("1M").is_err());
        assert!(parse_interval("0s").is_err());
        assert!(parse_interval("m").is_err());
    }
}
