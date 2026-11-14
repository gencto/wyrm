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

/// The address a limit counts: an IPv6 address by its /64 (one host or link holds a whole
/// /64), an IPv4-mapped one as IPv4 (security review of PR 86, L1).
pub fn bucket(ip: IpAddr) -> IpAddr {
    match ip {
        IpAddr::V4(_) => ip,
        IpAddr::V6(v6) => match v6.to_ipv4_mapped() {
            Some(v4) => IpAddr::V4(v4),
            None => {
                let s = v6.segments();
                IpAddr::V6(std::net::Ipv6Addr::new(s[0], s[1], s[2], s[3], 0, 0, 0, 0))
            }
        },
    }
}

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
        let ip = bucket(ip);
        let now = Instant::now();
        let mut f = self.lock();
        self.recent(&mut f, &(Some(user.to_owned()), ip), now) < self.max
            && self.recent(&mut f, &(None, ip), now) < self.max * IP_FACTOR
    }

    /// `true` for the first refusal of `(user, ip)` in a window: the one to
    /// audit. With the table full, nothing more is audited until records
    /// expire (the refusal itself still holds).
    pub fn note_refusal(&self, user: &str, ip: IpAddr) -> bool {
        let ip = bucket(ip);
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
        let ip = bucket(ip);
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
        self.lock().remove(&(Some(user.to_owned()), bucket(ip)));
    }
}

/// Requests per address in a fixed window, for the public routes that answer without a
/// password (`/api/info`, device challenges): what `LoginLimiter` is for failures.
pub struct RequestLimiter {
    max: u32,
    window: Duration,
    seen: Mutex<HashMap<IpAddr, (Instant, u32)>>,
    cap: usize,
}

impl RequestLimiter {
    pub fn new(max: u32, window: Duration) -> Self {
        Self {
            max: max.max(1),
            window,
            seen: Mutex::new(HashMap::new()),
            cap: MAX_RECORDS,
        }
    }

    #[cfg(test)]
    fn with_cap(mut self, cap: usize) -> Self {
        self.cap = cap;
        self
    }

    /// Count one request of `ip` (by [`bucket`]); `false` past `max` in its window. With
    /// the table full, expired records go first, then the one whose window began first: a
    /// crowd of addresses never locks a new one out.
    pub fn allowed(&self, ip: IpAddr) -> bool {
        let ip = bucket(ip);
        let now = Instant::now();
        let mut m = self.seen.lock().unwrap_or_else(|p| p.into_inner());
        if !m.contains_key(&ip) && m.len() >= self.cap {
            let window = self.window;
            m.retain(|_, (t, _)| now.duration_since(*t) < window);
            if m.len() >= self.cap {
                if let Some(oldest) = m.iter().min_by_key(|(_, (t, _))| *t).map(|(k, _)| *k) {
                    m.remove(&oldest);
                }
            }
        }
        let e = m.entry(ip).or_insert((now, 0));
        if now.duration_since(e.0) >= self.window {
            *e = (now, 0);
        }
        e.1 += 1;
        e.1 <= self.max
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn requests_per_address() {
        let l = RequestLimiter::new(2, Duration::from_millis(50));
        let a: IpAddr = "10.0.0.1".parse().unwrap();
        assert!(l.allowed(a) && l.allowed(a));
        assert!(!l.allowed(a));
        assert!(l.allowed("10.0.0.2".parse().unwrap()));
        std::thread::sleep(Duration::from_millis(60));
        assert!(l.allowed(a), "a new window");
    }

    #[test]
    fn a_full_table_never_locks_a_new_address_out() {
        let l = RequestLimiter::new(5, Duration::from_secs(60)).with_cap(3);
        for i in 1..=3 {
            assert!(l.allowed(format!("10.0.0.{i}").parse().unwrap()));
        }
        assert!(l.allowed("10.0.0.9".parse().unwrap()), "the oldest goes");
    }

    #[test]
    fn ipv6_counts_by_its_64() {
        let l = RequestLimiter::new(2, Duration::from_secs(60));
        assert!(l.allowed("2001:db8:1:2::1".parse().unwrap()));
        assert!(l.allowed("2001:db8:1:2::ffff".parse().unwrap()));
        assert!(
            !l.allowed("2001:db8:1:2:abcd::7".parse().unwrap()),
            "same /64"
        );
        assert!(l.allowed("2001:db8:1:3::1".parse().unwrap()), "another /64");
        let f = LoginLimiter::new(1, Duration::from_secs(60));
        f.failed("u", "2001:db8::1".parse().unwrap());
        assert!(!f.allowed("u", "2001:db8::2".parse().unwrap()));
        assert_eq!(
            bucket("::ffff:10.0.0.1".parse().unwrap()),
            "10.0.0.1".parse::<IpAddr>().unwrap()
        );
    }

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
