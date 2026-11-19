//! What this process uses: CPU time (`getrusage`), resident memory (Linux
//! `/proc/self/status`, elsewhere `ps -o rss=`) and, on Linux only, the write counters of
//! `/proc/self/io`. No OS has a counter of `fsync` calls; a figure that needs one says it is
//! derived from the code or not measured.

use std::time::{Duration, Instant};

/// Linux `/proc/self/io`: write system calls and bytes sent to the storage layer.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct Io {
    pub syscw: u64,
    pub write_bytes: u64,
}

impl Io {
    pub fn since(self, earlier: Self) -> Self {
        Self {
            syscw: self.syscw.saturating_sub(earlier.syscw),
            write_bytes: self.write_bytes.saturating_sub(earlier.write_bytes),
        }
    }
}

/// One reading of the process.
#[derive(Debug, Clone, Copy)]
pub struct Usage {
    pub at: Instant,
    /// User + system CPU seconds since the process started.
    pub cpu_s: Option<f64>,
    /// Resident memory now.
    pub rss_bytes: Option<u64>,
    /// Highest resident memory so far.
    pub peak_rss_bytes: Option<u64>,
    pub io: Option<Io>,
}

impl Usage {
    pub fn read() -> Self {
        let (cpu_s, peak_rss_bytes) = rusage();
        Self {
            at: Instant::now(),
            cpu_s,
            rss_bytes: rss(),
            peak_rss_bytes,
            io: io(),
        }
    }

    /// CPU time over wall time since `earlier`, in % of one core.
    pub fn cpu_pct_since(&self, earlier: &Usage) -> f64 {
        let wall = self.at.duration_since(earlier.at).as_secs_f64();
        match (self.cpu_s, earlier.cpu_s) {
            (Some(a), Some(b)) if wall > 0.0 => (a - b) / wall * 100.0,
            _ => f64::NAN,
        }
    }

    /// Wall time since `earlier`.
    pub fn wall_since(&self, earlier: &Usage) -> Duration {
        self.at.duration_since(earlier.at)
    }

    /// Write counters since `earlier` (Linux only).
    pub fn io_since(&self, earlier: &Usage) -> Option<Io> {
        Some(self.io?.since(earlier.io?))
    }
}

#[cfg(unix)]
fn rusage() -> (Option<f64>, Option<u64>) {
    use nix::sys::resource::{getrusage, UsageWho};
    let Ok(u) = getrusage(UsageWho::RUSAGE_SELF) else {
        return (None, None);
    };
    let secs = |t: nix::sys::time::TimeVal| t.tv_sec() as f64 + t.tv_usec() as f64 / 1e6;
    let cpu = secs(u.user_time()) + secs(u.system_time());
    // `ru_maxrss` is bytes on Apple systems and KiB elsewhere
    let unit: u64 = if cfg!(target_vendor = "apple") {
        1
    } else {
        1024
    };
    let peak = u64::try_from(u.max_rss())
        .ok()
        .map(|r| r.saturating_mul(unit));
    (Some(cpu), peak)
}

#[cfg(not(unix))]
fn rusage() -> (Option<f64>, Option<u64>) {
    (None, None)
}

/// The value of a `<name>: <n> kB` line of `/proc/self/status`, in bytes.
#[cfg(target_os = "linux")]
fn rss() -> Option<u64> {
    let s = std::fs::read_to_string("/proc/self/status").ok()?;
    let line = s.lines().find(|l| l.starts_with("VmRSS:"))?;
    let kib: u64 = line.split_whitespace().nth(1)?.parse().ok()?;
    Some(kib.saturating_mul(1024))
}

#[cfg(all(unix, not(target_os = "linux")))]
fn rss() -> Option<u64> {
    let out = std::process::Command::new("ps")
        .args(["-o", "rss=", "-p", &std::process::id().to_string()])
        .output()
        .ok()?;
    let kib: u64 = String::from_utf8_lossy(&out.stdout).trim().parse().ok()?;
    Some(kib.saturating_mul(1024))
}

#[cfg(not(unix))]
fn rss() -> Option<u64> {
    None
}

#[cfg(target_os = "linux")]
fn io() -> Option<Io> {
    let s = std::fs::read_to_string("/proc/self/io").ok()?;
    let field = |name: &str| -> Option<u64> {
        s.lines()
            .find_map(|l| l.strip_prefix(name))
            .and_then(|r| r.trim().parse().ok())
    };
    Some(Io {
        syscw: field("syscw:")?,
        write_bytes: field("write_bytes:")?,
    })
}

#[cfg(not(target_os = "linux"))]
fn io() -> Option<Io> {
    None
}
