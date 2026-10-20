//! Failed-login limiter per `(user, ip)`: at most `max` failures in a
//! sliding `window`; a success clears the record.

use std::collections::{HashMap, VecDeque};
use std::net::IpAddr;
use std::sync::Mutex;
use std::time::{Duration, Instant};

/// Records kept in memory; beyond this the stalest go first.
const MAX_RECORDS: usize = 10_000;

pub struct LoginLimiter {
    max: usize,
    window: Duration,
    fails: Mutex<HashMap<(String, IpAddr), VecDeque<Instant>>>,
}

impl LoginLimiter {
    pub fn new(max: usize, window: Duration) -> Self {
        Self {
            max: max.max(1),
            window,
            fails: Mutex::new(HashMap::new()),
        }
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, HashMap<(String, IpAddr), VecDeque<Instant>>> {
        self.fails.lock().unwrap_or_else(|p| p.into_inner())
    }

    /// `false` = too many recent failures; do not even check the password.
    pub fn allowed(&self, user: &str, ip: IpAddr) -> bool {
        let now = Instant::now();
        let mut f = self.lock();
        let Some(q) = f.get_mut(&(user.to_owned(), ip)) else {
            return true;
        };
        while q
            .front()
            .is_some_and(|t| now.duration_since(*t) >= self.window)
        {
            q.pop_front();
        }
        q.len() < self.max
    }

    pub fn failed(&self, user: &str, ip: IpAddr) {
        let now = Instant::now();
        let mut f = self.lock();
        if f.len() >= MAX_RECORDS {
            let window = self.window;
            f.retain(|_, q| q.back().is_some_and(|t| now.duration_since(*t) < window));
        }
        let q = f.entry((user.to_owned(), ip)).or_default();
        q.push_back(now);
        if q.len() > self.max {
            q.pop_front();
        }
    }

    pub fn succeeded(&self, user: &str, ip: IpAddr) {
        self.lock().remove(&(user.to_owned(), ip));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn per_user_and_ip() {
        let l = LoginLimiter::new(2, Duration::from_secs(60));
        let a: IpAddr = "10.0.0.1".parse().unwrap();
        let b: IpAddr = "10.0.0.2".parse().unwrap();
        l.failed("u", a);
        assert!(l.allowed("u", a));
        l.failed("u", a);
        assert!(!l.allowed("u", a));
        assert!(l.allowed("u", b) && l.allowed("v", a));
        l.succeeded("u", a);
        assert!(l.allowed("u", a));
    }
}
