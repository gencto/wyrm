//! The one wall clock of the workspace (review X2, docs/rust-rules.md §11).
//!
//! Every "now" as Unix time comes from here: one read of `SystemTime`, one
//! conversion without `as`. A clock set before 1970 reads as 0 and a time past
//! the range of the integer as its maximum; neither wraps. A portable link
//! takes its time from its host (`Host::now_us`), never from here: on
//! `wasm32-unknown-unknown` there is no system clock.

use std::time::{Duration, SystemTime, UNIX_EPOCH};

/// The time since the Unix epoch; zero for a clock set before it.
pub fn since_epoch() -> Duration {
    unix(SystemTime::now()).unwrap_or(Duration::ZERO)
}

/// `t` as the time since the Unix epoch; `None` for a time before it (a file
/// time, a certificate date).
pub fn unix(t: SystemTime) -> Option<Duration> {
    t.duration_since(UNIX_EPOCH).ok()
}

/// Microseconds since the Unix epoch (the unit of a sample's `t`).
pub fn now_us() -> u64 {
    u64::try_from(since_epoch().as_micros()).unwrap_or(u64::MAX)
}

/// Milliseconds since the Unix epoch.
pub fn now_ms() -> u64 {
    u64::try_from(since_epoch().as_millis()).unwrap_or(u64::MAX)
}

/// Seconds since the Unix epoch.
pub fn now_s() -> u64 {
    since_epoch().as_secs()
}

/// Seconds since the Unix epoch as the signed number X.509 and calendar code count in.
pub fn now_s_signed() -> i64 {
    i64::try_from(now_s()).unwrap_or(i64::MAX)
}

/// Milliseconds since the Unix epoch as a signed number (a script's `now_ms()`).
pub fn now_ms_signed() -> i64 {
    i64::try_from(now_ms()).unwrap_or(i64::MAX)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_units_agree() {
        let (s, ms, us) = (now_s(), now_ms(), now_us());
        // 2020-01-01 as a floor: the clock is read, not a constant
        assert!(s > 1_577_836_800);
        assert!(ms / 1000 >= s && ms / 1000 <= s + 2);
        assert!(us / 1_000_000 >= s && us / 1_000_000 <= s + 2);
        assert_eq!(now_s_signed().unsigned_abs() / 10, now_s() / 10);
    }

    #[test]
    fn a_time_before_the_epoch_is_none() {
        assert_eq!(unix(UNIX_EPOCH), Some(Duration::ZERO));
        assert_eq!(unix(UNIX_EPOCH - Duration::from_secs(1)), None);
        assert_eq!(
            unix(UNIX_EPOCH + Duration::from_secs(5)),
            Some(Duration::from_secs(5))
        );
    }
}
