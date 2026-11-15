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
    match s.as_bytes() {
        [y @ .., b'-', m1, m2, b'-', d1, d2] if y.len() == 4 => day_of(y, &[*m1, *m2], &[*d1, *d2]),
        _ => None,
    }
}

/// The value of 1 to 6 ASCII digits; `None` for anything else. Input text is read as bytes
/// and never sliced as `str`, so no offset can fall inside a character (review S1).
fn digits(b: &[u8]) -> Option<u64> {
    if b.is_empty() || b.len() > 6 {
        return None;
    }
    b.iter().try_fold(0u64, |n, c| {
        c.is_ascii_digit().then(|| n * 10 + u64::from(c - b'0'))
    })
}

fn day_of(y: &[u8], m: &[u8], d: &[u8]) -> Option<i64> {
    let y = i64::try_from(digits(y)?).ok()?;
    let m = u32::try_from(digits(m)?).ok()?;
    let d = u32::try_from(digits(d)?).ok()?;
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

/// RFC 3339 in UTC with microseconds, `2026-10-22T09:30:00.000001Z`: what
/// [`parse_iso`] reads back to the same `t`.
pub fn iso_us_exact(t: u64) -> String {
    let day = (t / US_PER_DAY) as i64;
    let us = t % US_PER_DAY;
    let s = us / US_PER_S;
    format!(
        "{}T{:02}:{:02}:{:02}.{:06}Z",
        day_name(day),
        s / 3600,
        s % 3600 / 60,
        s % 60,
        us % US_PER_S
    )
}

/// Microseconds since the epoch of an RFC 3339 timestamp
/// (`2026-10-22T09:30:00Z`, fractions and `±HH:MM` offsets allowed) or of a
/// date (`2026-10-22`, its midnight UTC). Any other text, ASCII or not, is
/// `None`; the parser never panics.
pub fn parse_iso(s: &str) -> Option<u64> {
    let b = s.trim().as_bytes();
    let (day, rest) = match b {
        [y1, y2, y3, y4, b'-', m1, m2, b'-', d1, d2, rest @ ..] => (
            day_of(&[*y1, *y2, *y3, *y4], &[*m1, *m2], &[*d1, *d2])?,
            rest,
        ),
        _ => return None,
    };
    if rest.is_empty() {
        return u64::try_from(day).ok()?.checked_mul(US_PER_DAY);
    }
    let (h, mi, sec, mut rest) = match rest {
        [b'T' | b't' | b' ', h1, h2, b':', m1, m2, b':', s1, s2, rest @ ..] => (
            digits(&[*h1, *h2])?,
            digits(&[*m1, *m2])?,
            digits(&[*s1, *s2])?,
            rest,
        ),
        _ => return None,
    };
    if h > 23 || mi > 59 || sec > 60 {
        return None;
    }
    let mut frac_us = 0u64;
    if let [b'.', f @ ..] = rest {
        let n = f.iter().take_while(|c| c.is_ascii_digit()).count();
        let (all, tail) = f.split_at_checked(n)?;
        let kept = all.get(..n.min(6))?;
        let scale = 10u64.pow(6 - u32::try_from(kept.len()).ok()?);
        frac_us = digits(kept)?.checked_mul(scale)?;
        rest = tail;
    }
    let offset_s: i64 = match rest {
        [b'Z' | b'z'] => 0,
        [sign @ (b'+' | b'-'), h1, h2, b':', m1, m2] => {
            let v = i64::try_from(digits(&[*h1, *h2])? * 3600 + digits(&[*m1, *m2])? * 60).ok()?;
            if *sign == b'-' {
                -v
            } else {
                v
            }
        }
        _ => return None,
    };
    let clock = i64::try_from(h * 3600 + mi * 60 + sec).ok()?;
    let local_s = day.checked_mul(86_400)?.checked_add(clock)?;
    let utc_s = u64::try_from(local_s.checked_sub(offset_s)?).ok()?;
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
        for t in [0, 1, t + 7, u64::from(u32::MAX) * 1_000_003] {
            assert_eq!(parse_iso(&iso_us_exact(t)), Some(t), "{t}");
        }
        assert_eq!(parse_iso("2026-10-22T12:30:15.25+03:00"), Some(t));
        assert_eq!(parse_iso("2026-10-22T05:30:15.250-04:00"), Some(t));
        assert_eq!(
            parse_iso("2026-10-22"),
            Some(parse_iso("2026-10-22T00:00:00Z").unwrap())
        );
        assert_eq!(parse_iso("2026-10-22T25:00:00Z"), None);
        assert_eq!(parse_iso("yesterday"), None);
        assert_eq!(
            parse_iso("2026-10-22T09:30:15.1234567Z"),
            parse_iso("2026-10-22T09:30:15.123456Z")
        );
        assert_eq!(parse_iso("2026-10-22T09:30:15.Z"), None);
        assert_eq!(parse_iso("2026-10-22T09:30:15"), None);
        assert_eq!(parse_iso("+026-10-22"), None);
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

    /// Review S1: a fixed byte offset inside a character panicked the history answer task.
    #[test]
    fn non_ascii_text_is_refused_not_a_panic() {
        for s in [
            "2026-10-22T00:00:0\u{e9}",
            "2026-10-22T00:00:00+0\u{e9}00",
            "2026-10-2\u{e9}",
            "2026-10-22T\u{e9}0:00:00Z",
            "2026-10-22T00:00:00.\u{e9}Z",
            "2026-10-22T00:00:00.5\u{e9}",
            "\u{1f600}026-10-22",
            "2026-10-22T00:00:00+00:0\u{e9}",
        ] {
            assert_eq!(parse_iso(s), None, "{s}");
            assert_eq!(parse_range(&format!("{s}.."), 0), None, "{s}");
        }
        assert_eq!(parse_day("20\u{e9}6-1-22"), None);
    }

    /// No text makes the parsers panic: valid stamps cut at every byte, with every byte
    /// replaced by a hard character, and random text from a small alphabet of ASCII and
    /// multibyte characters (a fixed-seed fuzz table; the workspace has no `proptest`).
    #[test]
    fn arbitrary_text_never_panics() {
        const HARD: [char; 12] = [
            '0',
            '9',
            ':',
            '-',
            '.',
            '+',
            'T',
            'Z',
            ' ',
            '\u{e9}',
            '\u{20ac}',
            '\u{1f600}',
        ];
        let check = |s: &str| {
            let _ = parse_iso(s);
            let _ = parse_day(s);
            let _ = parse_range(s, 1);
            let _ = parse_interval(s);
        };
        let valid = [
            "2026-10-22T09:30:15.250Z",
            "2026-10-22T12:30:15.123456789+03:00",
            "2026-10-22 05:30:15-04:00",
            "2026-10-22",
            "2026-10-22T00:00:00Z..2026-10-23",
        ];
        for v in valid {
            let chars: Vec<char> = v.chars().collect();
            for i in 0..=chars.len() {
                check(&chars[..i].iter().collect::<String>());
                for h in HARD {
                    let mut c = chars.clone();
                    if i < c.len() {
                        c[i] = h;
                    } else {
                        c.push(h);
                    }
                    check(&c.iter().collect::<String>());
                    let mut c = chars.clone();
                    c.insert(i, h);
                    check(&c.iter().collect::<String>());
                }
            }
        }
        let mut x: u64 = 0x9e37_79b9_7f4a_7c15;
        let mut next = || {
            x ^= x << 13;
            x ^= x >> 7;
            x ^= x << 17;
            x
        };
        for _ in 0..200_000 {
            let len = (next() % 40) as usize;
            let s: String = (0..len)
                .map(|_| HARD[(next() % HARD.len() as u64) as usize])
                .collect();
            check(&s);
        }
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
