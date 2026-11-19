//! One `PERF` line per figure: `PERF name=… n=… p50_us=… p95_us=… p99_us=… per_s=…
//! cpu_pct=… rss_mib=… allocs_op=… bytes_op=…`, then any extra `key=value`. A column that
//! does not apply is `-`; a value has no spaces (they become `_`).

use crate::{Allocs, Lat};
use std::fmt;

/// A figure being written; print it with `println!("{perf}")`.
#[derive(Debug, Clone)]
pub struct Perf {
    name: String,
    /// The fixed columns in their order: `n` … `bytes_op` (see [`Perf::fmt`]).
    cols: [Option<String>; 9],
    extra: Vec<(String, String)>,
}

fn word(s: &str) -> String {
    s.chars()
        .map(|c| {
            if c.is_whitespace() || c == '=' {
                '_'
            } else {
                c
            }
        })
        .collect()
}

fn num(x: f64) -> String {
    if !x.is_finite() {
        return "-".to_owned();
    }
    if x.abs() >= 100.0 {
        format!("{x:.0}")
    } else if x.abs() >= 1.0 {
        format!("{x:.1}")
    } else {
        format!("{x:.3}")
    }
}

impl Perf {
    pub fn new(name: &str) -> Self {
        Self {
            name: word(name),
            cols: Default::default(),
            extra: Vec::new(),
        }
    }

    fn col(mut self, i: usize, v: String) -> Self {
        if let Some(c) = self.cols.get_mut(i) {
            *c = Some(v);
        }
        self
    }

    /// `n`, `p50_us`, `p95_us`, `p99_us` of `lat`.
    pub fn lat(self, lat: &mut Lat) -> Self {
        let n = lat.len().to_string();
        let (p50, p95, p99) = (lat.pct(50.0), lat.pct(95.0), lat.pct(99.0));
        self.col(0, n)
            .col(1, num(p50))
            .col(2, num(p95))
            .col(3, num(p99))
    }

    /// `n` alone (a count with no latencies).
    pub fn n(self, n: u64) -> Self {
        self.col(0, n.to_string())
    }

    pub fn per_s(self, x: f64) -> Self {
        self.col(4, num(x))
    }

    /// Process CPU time over wall time, in % of one core.
    pub fn cpu_pct(self, x: f64) -> Self {
        self.col(5, num(x))
    }

    /// Resident memory in MiB, from bytes.
    pub fn rss(self, bytes: Option<u64>) -> Self {
        match bytes {
            Some(b) => self.col(6, num(b as f64 / 1_048_576.0)),
            None => self,
        }
    }

    /// Allocations and bytes per operation over `ops` operations.
    pub fn allocs(self, a: Allocs, ops: u64) -> Self {
        if !Allocs::active() {
            return self;
        }
        self.col(7, num(a.calls_per(ops)))
            .col(8, num(a.bytes_per(ops)))
    }

    /// Allocations and bytes per operation, worked out by the caller.
    pub fn allocs_op(self, calls: f64, bytes: f64) -> Self {
        self.col(7, num(calls)).col(8, num(bytes))
    }

    /// An extra `key=value` after the columns.
    pub fn field(mut self, key: &str, v: impl fmt::Display) -> Self {
        self.extra.push((word(key), word(&v.to_string())));
        self
    }

    /// An extra number after the columns.
    pub fn num(self, key: &str, x: f64) -> Self {
        self.field(key, num(x))
    }

    /// `note=…`: what the figure is, in a few words.
    pub fn note(self, text: &str) -> Self {
        self.field("note", text)
    }
}

impl fmt::Display for Perf {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let c = |i: usize| self.cols.get(i).and_then(Option::as_deref).unwrap_or("-");
        write!(
            f,
            "PERF name={} n={} p50_us={} p95_us={} p99_us={} per_s={} cpu_pct={} rss_mib={} \
             allocs_op={} bytes_op={}",
            self.name,
            c(0),
            c(1),
            c(2),
            c(3),
            c(4),
            c(5),
            c(6),
            c(7),
            c(8)
        )?;
        for (k, v) in &self.extra {
            write!(f, " {k}={v}")?;
        }
        Ok(())
    }
}
