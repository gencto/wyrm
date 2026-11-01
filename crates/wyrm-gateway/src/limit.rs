//! Failed-login limiter: at most `max` failures per `(user, ip)` and
//! `max * IP_FACTOR` per `ip` over all user names (password spraying) in a
//! sliding `window`; a success clears the `(user, ip)` record. A refusal is
//! audited once per `(user, ip)` and window, not per attempt (review GW-1).

use std::collections::{HashMap, VecDeque};
use std::net::IpAddr;
use std::sync::Mutex;
use std::time::{Duration, Instant};

/// Records kept in memory; when full, expired records go first, then the
/// one with the oldest last failure.
const MAX_RECORDS: usize = 10_000;
/// Failures per address over all user names, as a multiple of `max`.
const IP_FACTOR: usize = 4;

/// `None` user = the address-wide record.
type Key = (Option<String>, IpAddr);

pub struct LoginLimiter {
    max: usize,
    window: Duration,
    fails: Mutex<HashMap<Key, VecDeque<Instant>>>,
    /// When a refusal of `(user, ip)` was last audited.
    noted: Mutex<HashMap<Key, Instant>>,
}

impl LoginLimiter {
    pub fn new(max: usize, window: Duration) -> Self {
        Self {
            max: max.max(1),
            window,
            fails: Mutex::new(HashMap::new()),
            noted: Mutex::new(HashMap::new()),
        }
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, HashMap<Key, VecDeque<Instant>>> {
        self.fails.lock().unwrap_or_else(|p| p.into_inner())
    }

    fn recent(&self, f: &mut HashMap<Key, VecDeque<Instant>>, k: &Key, now: Instant) -> usize {
        let Some(q) = f.get_mut(k) else {
            return 0;
        };
        while q
            .front()
            .is_some_and(|t| now.duration_since(*t) >= self.window)
        {
            q.pop_front();
        }
        q.len()
    }

    /// `false` = too many recent failures; do not even check the password.
    pub fn allowed(&self, user: &str, ip: IpAddr) -> bool {
        let now = Instant::now();
        let mut f = self.lock();
        self.recent(&mut f, &(Some(user.to_owned()), ip), now) < self.max
            && self.recent(&mut f, &(None, ip), now) < self.max * IP_FACTOR
    }

    /// `true` for the first refusal of `(user, ip)` in a window: the one to
    /// audit. With the table full, nothing more is audited until records
    /// expire (the refusal itself still holds).
    pub fn note_refusal(&self, user: &str, ip: IpAddr) -> bool {
        let now = Instant::now();
        let mut n = self.noted.lock().unwrap_or_else(|p| p.into_inner());
        let k = (Some(user.to_owned()), ip);
        if n.get(&k)
            .is_some_and(|t| now.duration_since(*t) < self.window)
        {
            return false;
        }
        if !n.contains_key(&k) && n.len() >= MAX_RECORDS {
            let window = self.window;
            n.retain(|_, t| now.duration_since(*t) < window);
            if n.len() >= MAX_RECORDS {
                return false;
            }
        }
        n.insert(k, now);
        true
    }

    pub fn failed(&self, user: &str, ip: IpAddr) {
        let now = Instant::now();
        let mut f = self.lock();
        for (k, cap) in [
            ((Some(user.to_owned()), ip), self.max),
            ((None, ip), self.max * IP_FACTOR),
        ] {
            if !f.contains_key(&k) && f.len() >= MAX_RECORDS {
                let window = self.window;
                f.retain(|_, q| q.back().is_some_and(|t| now.duration_since(*t) < window));
                if f.len() >= MAX_RECORDS {
                    if let Some(oldest) = f
                        .iter()
                        .min_by_key(|(_, q)| q.back().copied())
                        .map(|(k, _)| k.clone())
                    {
                        f.remove(&oldest);
                    }
                }
            }
            let q = f.entry(k).or_default();
            q.push_back(now);
            if q.len() > cap {
                q.pop_front();
            }
        }
    }

    pub fn succeeded(&self, user: &str, ip: IpAddr) {
        self.lock().remove(&(Some(user.to_owned()), ip));
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

    #[test]
    fn a_refusal_is_noted_once_per_window() {
        let l = LoginLimiter::new(1, Duration::from_millis(50));
        let a: IpAddr = "10.0.0.1".parse().unwrap();
        assert!(l.note_refusal("u", a));
        assert!(!l.note_refusal("u", a));
        assert!(l.note_refusal("v", a), "per user");
        std::thread::sleep(Duration::from_millis(60));
        assert!(l.note_refusal("u", a), "again after the window");
    }

    #[test]
    fn spraying_one_address_is_limited() {
        let l = LoginLimiter::new(2, Duration::from_secs(60));
        let a: IpAddr = "10.0.0.1".parse().unwrap();
        for i in 0..2 * IP_FACTOR {
            l.failed(&format!("user{i}"), a);
        }
        assert!(!l.allowed("someone-else", a), "address-wide limit");
        assert!(l.allowed("someone-else", "10.0.0.9".parse().unwrap()));
    }
}
