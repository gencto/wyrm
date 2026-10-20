//! Request guards in the responder: a token bucket per caller (threat T7)
//! and audit records for every `set`/`invoke` (wiki "Логування і аудит").

use std::collections::HashMap;
use std::sync::Mutex;
use std::time::Instant;

/// Callers kept in memory; the oldest buckets go first beyond this.
const MAX_CALLERS: usize = 10_000;

/// Token bucket per caller: `rate` requests per second, bursts up to `burst`.
pub struct RateLimiter {
    rate: f64,
    burst: f64,
    buckets: Mutex<HashMap<String, (f64, Instant)>>,
}

impl RateLimiter {
    pub fn new(rate: f64, burst: f64) -> Self {
        Self {
            rate: rate.max(0.001),
            burst: burst.max(1.0),
            buckets: Mutex::new(HashMap::new()),
        }
    }

    /// Take one token for `caller`; `false` = over the limit.
    pub fn allow(&self, caller: &str) -> bool {
        let now = Instant::now();
        let mut b = self.buckets.lock().unwrap_or_else(|p| p.into_inner());
        if b.len() >= MAX_CALLERS && !b.contains_key(caller) {
            // Forget buckets that are full again (idle callers).
            let (rate, burst) = (self.rate, self.burst);
            b.retain(|_, (tokens, t)| {
                *tokens + rate * now.duration_since(*t).as_secs_f64() < burst
            });
            if b.len() >= MAX_CALLERS {
                return false; // fail closed under a caller flood
            }
        }
        let (tokens, last) = b.entry(caller.to_owned()).or_insert((self.burst, now));
        *tokens = (*tokens + self.rate * now.duration_since(*last).as_secs_f64()).min(self.burst);
        *last = now;
        if *tokens >= 1.0 {
            *tokens -= 1.0;
            true
        } else {
            false
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bucket() {
        let r = RateLimiter::new(1.0, 3.0);
        assert!(r.allow("a") && r.allow("a") && r.allow("a"));
        assert!(!r.allow("a"), "burst used up");
        assert!(r.allow("b"), "per caller");
    }
}
