//! Time limits on work that runs on one thread (spec 06: a rhai call, the per-row scripts of
//! a table): the CPU time of that thread, not the wall clock. Time the host kept the thread
//! off a core is not the work's, and a sample is never dropped for it.
//!
//! Linux (glibc and musl), Android, macOS/iOS and Free/Open/DragonFly BSD have a thread CPU
//! clock (`CLOCK_THREAD_CPUTIME_ID`); elsewhere (NetBSD, illumos, Windows, wasm32) the wall
//! clock is all there is. The list is the one of `rustix` in `Cargo.toml`.

use std::time::{Duration, Instant};

/// A limit counted from its start on the thread that started it: the wall clock is the cheap
/// check, the thread's CPU time decides. Read it on that thread only.
#[derive(Clone, Copy)]
pub(crate) struct Budget {
    limit: Duration,
    wall: Instant,
    cpu: Option<Duration>,
}

impl Budget {
    /// A budget of `limit` from now, on this thread.
    pub(crate) fn start(limit: Duration) -> Self {
        Self {
            limit,
            wall: Instant::now(),
            cpu: thread_cpu(),
        }
    }

    /// True once the thread used more than the limit since the start. Work cannot use more
    /// CPU time than went by, so the CPU clock (a system call) is read only after the wall
    /// clock is past the limit.
    pub(crate) fn spent(&self) -> bool {
        if self.wall.elapsed() <= self.limit {
            return false;
        }
        match (self.cpu, thread_cpu()) {
            (Some(from), Some(now)) => now.saturating_sub(from) > self.limit,
            // no thread CPU clock on this platform: the wall clock decides
            _ => true,
        }
    }
}

/// CPU time this thread has used so far; `None` where the platform has no such clock.
#[cfg(any(
    target_os = "linux",
    target_os = "android",
    target_vendor = "apple",
    target_os = "freebsd",
    target_os = "openbsd",
    target_os = "dragonfly"
))]
pub(crate) fn thread_cpu() -> Option<Duration> {
    let t = rustix::time::clock_gettime(rustix::time::ClockId::ThreadCPUTime);
    Some(Duration::new(
        u64::try_from(t.tv_sec).ok()?,
        u32::try_from(t.tv_nsec).ok()?,
    ))
}

/// CPU time this thread has used so far; `None` where the platform has no such clock.
#[cfg(not(any(
    target_os = "linux",
    target_os = "android",
    target_vendor = "apple",
    target_os = "freebsd",
    target_os = "openbsd",
    target_os = "dragonfly"
)))]
pub(crate) fn thread_cpu() -> Option<Duration> {
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn time_off_the_core_does_not_spend_a_budget() {
        if thread_cpu().is_none() {
            return; // nothing to tell apart: the wall clock decides
        }
        let b = Budget::start(Duration::from_millis(5));
        std::thread::sleep(Duration::from_millis(20));
        assert!(!b.spent(), "a sleep is no CPU time");
        let from = Instant::now();
        while !b.spent() {
            assert!(from.elapsed() < Duration::from_secs(5), "work spends it");
        }
    }
}
