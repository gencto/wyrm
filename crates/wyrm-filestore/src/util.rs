//! Small helpers every backend needs: percent-encoding, civil time and the
//! date formats of the stores (RFC 3339, HTTP dates, SigV4 stamps), and
//! file and folder names people enter.

use std::time::{SystemTime, UNIX_EPOCH};

/// RFC 3986 unreserved characters.
fn unreserved(b: u8) -> bool {
    b.is_ascii_alphanumeric() || matches!(b, b'-' | b'.' | b'_' | b'~')
}

/// Percent-encode everything but the unreserved characters (and `/` when
/// `keep_slash`), as SigV4 and most REST paths want it.
pub fn pct_encode(s: &str, keep_slash: bool) -> String {
    let mut out = String::with_capacity(s.len());
    for b in s.bytes() {
        if unreserved(b) || (keep_slash && b == b'/') {
            out.push(b as char);
        } else {
            out.push_str(&format!("%{b:02X}"));
        }
    }
    out
}

/// Decode `%XX` escapes; `None` for a bad escape or a result that is not
/// UTF-8.
pub fn pct_decode(s: &str) -> Option<String> {
    let b = s.as_bytes();
    let mut out = Vec::with_capacity(b.len());
    let mut i = 0;
    while i < b.len() {
        if b[i] == b'%' {
            let hex = s.get(i + 1..i + 3)?;
            out.push(u8::from_str_radix(hex, 16).ok()?);
            i += 3;
        } else {
            out.push(b[i]);
            i += 1;
        }
    }
    String::from_utf8(out).ok()
}

/// Microseconds since the Unix epoch.
pub fn now_us() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_micros() as u64)
        .unwrap_or(0)
}

/// Days since 1970-01-01 of a proleptic Gregorian date (H. Hinnant).
fn days_from_civil(y: i64, m: u32, d: u32) -> i64 {
    let y = if m <= 2 { y - 1 } else { y };
    let era = if y >= 0 { y } else { y - 399 } / 400;
    let yoe = y - era * 400;
    let mp = (i64::from(m) + 9) % 12;
    let doy = (153 * mp + 2) / 5 + i64::from(d) - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146_097 + doe - 719_468
}

/// The date of a day count since 1970-01-01.
fn civil_from_days(z: i64) -> (i64, u32, u32) {
    let z = z + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = (doy - (153 * mp + 2) / 5 + 1) as u32;
    let m = if mp < 10 { mp + 3 } else { mp - 9 } as u32;
    (if m <= 2 { y + 1 } else { y }, m, d)
}

/// UTC civil time of `secs` since the epoch: `(y, mon, d, h, min, s)`.
pub fn civil(secs: u64) -> (i64, u32, u32, u32, u32, u32) {
    let days = (secs / 86_400) as i64;
    let rem = secs % 86_400;
    let (y, m, d) = civil_from_days(days);
    (
        y,
        m,
        d,
        (rem / 3600) as u32,
        (rem % 3600 / 60) as u32,
        (rem % 60) as u32,
    )
}

/// `2026-10-31T12:00:00Z` (whole seconds).
pub fn rfc3339(us: u64) -> String {
    let (y, mo, d, h, mi, s) = civil(us / 1_000_000);
    format!("{y:04}-{mo:02}-{d:02}T{h:02}:{mi:02}:{s:02}Z")
}

/// SigV4 stamps of `secs`: (`20261031T120000Z`, `20261031`).
pub fn amz_date(secs: u64) -> (String, String) {
    let (y, mo, d, h, mi, s) = civil(secs);
    let day = format!("{y:04}{mo:02}{d:02}");
    (format!("{day}T{h:02}{mi:02}{s:02}Z"), day)
}

fn num<T: std::str::FromStr>(s: &str) -> Option<T> {
    if s.is_empty() || !s.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    s.parse().ok()
}

fn to_us(y: i64, mo: u32, d: u32, h: u32, mi: u32, s: u32) -> Option<u64> {
    if !(1..=12).contains(&mo) || !(1..=31).contains(&d) || h > 23 || mi > 59 || s > 60 {
        return None;
    }
    let days = days_from_civil(y, mo, d);
    let secs = days * 86_400 + i64::from(h) * 3600 + i64::from(mi) * 60 + i64::from(s);
    u64::try_from(secs).ok().map(|s| s * 1_000_000)
}

/// RFC 3339 / ISO 8601 as the stores send it (`2024-01-02T03:04:05.678Z`,
/// `…+02:00`) → microseconds since the epoch.
pub fn parse_rfc3339(s: &str) -> Option<u64> {
    let s = s.trim();
    let (date, time) = s.split_once(['T', 't', ' '])?;
    let mut dp = date.split('-');
    let (y, mo, d) = (
        num::<i64>(dp.next()?)?,
        num::<u32>(dp.next()?)?,
        num::<u32>(dp.next()?)?,
    );
    if dp.next().is_some() {
        return None;
    }
    let (clock, offset_s): (&str, i64) = if let Some(c) = time.strip_suffix(['Z', 'z']) {
        (c, 0)
    } else if let Some(i) = time.rfind(['+', '-']) {
        let (c, off) = time.split_at(i);
        let sign = if off.starts_with('-') { -1 } else { 1 };
        let (oh, om) = off[1..].split_once(':')?;
        (c, sign * (num::<i64>(oh)? * 3600 + num::<i64>(om)? * 60))
    } else {
        (time, 0)
    };
    let (hms, frac) = match clock.split_once('.') {
        Some((a, f)) => (a, f),
        None => (clock, ""),
    };
    let mut tp = hms.split(':');
    let (h, mi, sec) = (
        num::<u32>(tp.next()?)?,
        num::<u32>(tp.next()?)?,
        num::<u32>(tp.next()?)?,
    );
    let mut us = to_us(y, mo, d, h, mi, sec)? as i64;
    if !frac.is_empty() {
        let digits: String = frac.chars().take(6).collect();
        let n = num::<i64>(&digits)?;
        us += n * 10i64.pow(6 - digits.len() as u32);
    }
    u64::try_from(us - offset_s * 1_000_000).ok()
}

const MONTHS: [&str; 12] = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
];

/// An HTTP date (`Sun, 06 Nov 1994 08:49:37 GMT`) → microseconds.
pub fn parse_http_date(s: &str) -> Option<u64> {
    let rest = s.trim().split_once(", ").map(|(_, r)| r)?;
    let mut p = rest.split_whitespace();
    let d = num::<u32>(p.next()?)?;
    let mon = p.next()?;
    let mo = MONTHS.iter().position(|m| m.eq_ignore_ascii_case(mon))? as u32 + 1;
    let y = num::<i64>(p.next()?)?;
    let mut tp = p.next()?.split(':');
    let (h, mi, sec) = (
        num::<u32>(tp.next()?)?,
        num::<u32>(tp.next()?)?,
        num::<u32>(tp.next()?)?,
    );
    to_us(y, mo, d, h, mi, sec)
}

/// An HTTP date of `us`.
pub fn http_date(us: u64) -> String {
    const DAYS: [&str; 7] = ["Thu", "Fri", "Sat", "Sun", "Mon", "Tue", "Wed"];
    let secs = us / 1_000_000;
    let (y, mo, d, h, mi, s) = civil(secs);
    let wd = DAYS[((secs / 86_400) % 7) as usize];
    format!(
        "{wd}, {d:02} {} {y:04} {h:02}:{mi:02}:{s:02} GMT",
        MONTHS[(mo - 1) as usize]
    )
}

/// FNV-1a 64: stable short ids for node names (not for security).
pub fn fnv64(s: &str) -> u64 {
    let mut h: u64 = 0xcbf2_9ce4_8422_2325;
    for b in s.bytes() {
        h ^= u64::from(b);
        h = h.wrapping_mul(0x0100_0000_01b3);
    }
    h
}

/// Longest file or folder name taken from people (bytes).
pub const MAX_NAME: usize = 255;

/// A file or folder name people enter: not empty, not `.` or `..`, no `/`,
/// `\` or control characters, at most [`MAX_NAME`] bytes.
pub fn check_name(name: &str) -> Result<(), String> {
    if name.is_empty() || name.trim().is_empty() {
        return Err("empty name".into());
    }
    if name == "." || name == ".." {
        return Err("not . or ..".into());
    }
    if name.len() > MAX_NAME {
        return Err(format!("longer than {MAX_NAME} bytes"));
    }
    if let Some(c) = name
        .chars()
        .find(|c| matches!(c, '/' | '\\') || c.is_control())
    {
        return Err(format!("character {c:?} is not allowed"));
    }
    Ok(())
}

/// A content type for a file name by its extension (for uploads without
/// one).
pub fn guess_content_type(name: &str) -> &'static str {
    let ext = name
        .rsplit_once('.')
        .map(|(_, e)| e.to_ascii_lowercase())
        .unwrap_or_default();
    match ext.as_str() {
        "txt" | "log" => "text/plain",
        "csv" => "text/csv",
        "json" => "application/json",
        "xml" => "application/xml",
        "html" | "htm" => "text/html",
        "pdf" => "application/pdf",
        "png" => "image/png",
        "jpg" | "jpeg" => "image/jpeg",
        "gif" => "image/gif",
        "svg" => "image/svg+xml",
        "zip" => "application/zip",
        "gz" => "application/gzip",
        "md" => "text/markdown",
        "yaml" | "yml" => "application/yaml",
        _ => "application/octet-stream",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn percent() {
        assert_eq!(pct_encode("a b/c~d+é", true), "a%20b/c~d%2B%C3%A9");
        assert_eq!(pct_encode("a/b", false), "a%2Fb");
        assert_eq!(pct_decode("a%20b/%C3%A9").as_deref(), Some("a b/é"));
        assert_eq!(pct_decode("%zz"), None);
        assert_eq!(pct_decode("%4"), None);
    }

    #[test]
    fn dates() {
        let t = parse_rfc3339("2024-01-02T03:04:05.678Z").unwrap();
        assert_eq!(t, 1_704_164_645_678_000);
        assert_eq!(rfc3339(t), "2024-01-02T03:04:05Z");
        assert_eq!(
            parse_rfc3339("2024-01-02T05:04:05+02:00"),
            Some(1_704_164_645_000_000)
        );
        assert_eq!(parse_rfc3339("2024-13-02T03:04:05Z"), None);
        assert_eq!(parse_rfc3339("garbage"), None);
        let h = parse_http_date("Tue, 02 Jan 2024 03:04:05 GMT").unwrap();
        assert_eq!(h, 1_704_164_645_000_000);
        assert_eq!(http_date(h), "Tue, 02 Jan 2024 03:04:05 GMT");
        assert_eq!(
            amz_date(1_440_938_160),
            ("20150830T123600Z".into(), "20150830".into())
        );
        assert_eq!(civil(0), (1970, 1, 1, 0, 0, 0));
    }

    #[test]
    fn names() {
        assert!(check_name("report 2026.pdf").is_ok());
        for bad in ["", " ", ".", "..", "a/b", "a\\b", "a\nb"] {
            assert!(check_name(bad).is_err(), "{bad:?}");
        }
        assert!(check_name(&"x".repeat(256)).is_err());
        assert_eq!(guess_content_type("A.JSON"), "application/json");
        assert_eq!(guess_content_type("noext"), "application/octet-stream");
    }
}
