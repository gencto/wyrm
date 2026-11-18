//! Measurement kit of the WYRM benches and ignored perf tests (`docs/backlog.md` §14,
//! `tool/perf.sh`). Dev only: a crate lists it under `[dev-dependencies]`, never under
//! `[dependencies]`, so no product build has it.
//!
//! * [`Counting`]: a global allocator that counts calls and bytes. A bench or test installs
//!   it itself (`#[global_allocator] static A: wyrm_bench::Counting = wyrm_bench::Counting;`)
//!   and reads [`Allocs::read`] around the work.
//! * [`Lat`]: latencies and their nearest-rank percentiles.
//! * [`Usage`]: process CPU time, resident memory and (Linux) write counters.
//! * [`Perf`]: one machine-readable `PERF` line per figure, the only output `tool/perf.sh`
//!   reads.

mod alloc;
mod line;
mod usage;

pub use alloc::{Allocs, Counting};
pub use line::Perf;
pub use usage::{Io, Usage};

use std::time::Duration;

/// Latency samples in microseconds.
#[derive(Debug, Clone, Default)]
pub struct Lat {
    us: Vec<f64>,
    sorted: bool,
}

impl Lat {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn with_capacity(n: usize) -> Self {
        Self {
            us: Vec::with_capacity(n),
            sorted: false,
        }
    }

    pub fn push(&mut self, d: Duration) {
        self.push_us(d.as_secs_f64() * 1e6);
    }

    pub fn push_us(&mut self, us: f64) {
        self.us.push(us);
        self.sorted = false;
    }

    pub fn len(&self) -> usize {
        self.us.len()
    }

    pub fn is_empty(&self) -> bool {
        self.us.is_empty()
    }

    /// Nearest-rank percentile (`p` in 0..=100); `NaN` without samples.
    pub fn pct(&mut self, p: f64) -> f64 {
        if !self.sorted {
            self.us.sort_by(f64::total_cmp);
            self.sorted = true;
        }
        let n = self.us.len();
        if n == 0 {
            return f64::NAN;
        }
        // the rank is a whole number in 1..=n: `ceil` of a product of two finite numbers
        let rank = (p / 100.0 * n as f64).ceil();
        let i = (1..=n).find(|i| *i as f64 >= rank).unwrap_or(n);
        self.us.get(i - 1).copied().unwrap_or(f64::NAN)
    }

    pub fn mean(&self) -> f64 {
        if self.us.is_empty() {
            return f64::NAN;
        }
        self.us.iter().sum::<f64>() / self.us.len() as f64
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn nearest_rank() {
        let mut l = Lat::new();
        for x in 1..=100 {
            l.push_us(f64::from(x));
        }
        assert_eq!(l.pct(50.0), 50.0);
        assert_eq!(l.pct(99.0), 99.0);
        assert_eq!(l.pct(100.0), 100.0);
        assert_eq!(l.pct(0.0), 1.0);
        let mut one = Lat::new();
        one.push_us(7.0);
        assert_eq!(one.pct(99.0), 7.0);
        assert!(Lat::new().pct(50.0).is_nan());
    }

    #[test]
    fn a_line_has_every_column() {
        let mut l = Lat::new();
        l.push_us(10.0);
        let s = Perf::new("x y")
            .lat(&mut l)
            .per_s(1.5)
            .note("a b")
            .to_string();
        assert!(s.starts_with("PERF name=x_y n=1 p50_us=10.0 p95_us=10.0 p99_us=10.0 per_s=1.5 "));
        assert!(
            s.contains(" cpu_pct=- rss_mib=- allocs_op=- bytes_op=- "),
            "{s}"
        );
        assert!(s.ends_with(" note=a_b"), "{s}");
    }

    #[test]
    fn usage_reads_this_process() {
        let u = Usage::read();
        if cfg!(unix) {
            assert!(u.cpu_s.is_some());
            assert!(u.rss_bytes.is_some_and(|r| r > 0));
        }
    }
}
