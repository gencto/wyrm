//! Resource limits a supervised link process sets on itself before it
//! connects (it runs our code until then, so this needs no `pre_exec`).
//! Hard and soft limits are the same: the link cannot raise them again.
//!
//! `no_new_privs` is a per-thread attribute that only new threads inherit,
//! so the binary calls [`apply_from_env`] in `main` before it starts the
//! tokio runtime; `process::run` then checks every thread (fail closed).
//!
//! * no core dumps (a dump would hold the link token and secrets);
//! * `WYRM_LIMIT_MEMORY_MB`: Linux only, `RLIMIT_DATA` (heap and private
//!   mappings), 0 = unchanged; macOS refuses a data limit below the large
//!   virtual size of any process, so there it is skipped with a warning;
//! * `WYRM_LIMIT_OPEN_FILES`: file descriptors (`RLIMIT_NOFILE`), 0 = unchanged;
//! * Linux: `no_new_privs` (no privilege gain through set-uid executables).

use crate::error::{LinkError, Result};

pub const MEMORY_ENV: &str = "WYRM_LIMIT_MEMORY_MB";
pub const OPEN_FILES_ENV: &str = "WYRM_LIMIT_OPEN_FILES";

/// Limits for one link process (0 = leave as is).
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct Limits {
    pub memory_mb: u64,
    pub open_files: u64,
}

impl Limits {
    /// The environment variables a supervisor passes to the link.
    pub fn to_env(self) -> Vec<(String, String)> {
        vec![
            (MEMORY_ENV.into(), self.memory_mb.to_string()),
            (OPEN_FILES_ENV.into(), self.open_files.to_string()),
        ]
    }

    pub fn from_env() -> Result<Self> {
        Self::from_vars(|k| std::env::var(k).ok())
    }

    fn from_vars(var: impl Fn(&str) -> Option<String>) -> Result<Self> {
        let num = |k: &str| match var(k) {
            None => Ok(0),
            Some(v) => v
                .trim()
                .parse::<u64>()
                .map_err(|_| LinkError::invalid_parameter(format!("env {k}: not a number"))),
        };
        Ok(Self {
            memory_mb: num(MEMORY_ENV)?,
            open_files: num(OPEN_FILES_ENV)?,
        })
    }

    /// Apply the rlimits and `no_new_privs`. Call it before any other
    /// thread exists. An error means a limit is not in place.
    pub fn apply(self) -> Result<()> {
        self.apply_rlimits()?;
        #[cfg(target_os = "linux")]
        nix::sys::prctl::set_no_new_privs()
            .map_err(|e| LinkError::internal(format!("no_new_privs: {e}")))?;
        Ok(())
    }

    /// The rlimits only (they hold for the whole process).
    pub fn apply_rlimits(self) -> Result<()> {
        #[cfg(unix)]
        {
            use nix::sys::resource::{getrlimit, setrlimit, Resource};
            let fail = |what: &str, e: nix::Error| {
                LinkError::internal(format!("resource limit {what}: {e}"))
            };
            // Never above the current hard limit (lowering needs no privilege).
            let cap = |r: Resource, v: u64, what: &str| -> Result<()> {
                let (_, hard) = getrlimit(r).map_err(|e| fail(what, e))?;
                let v = v.min(hard);
                setrlimit(r, v, v).map_err(|e| fail(what, e))
            };
            cap(Resource::RLIMIT_CORE, 0, "core")?;
            #[cfg(target_os = "linux")]
            if self.memory_mb > 0 {
                cap(
                    Resource::RLIMIT_DATA,
                    self.memory_mb.saturating_mul(1 << 20),
                    "memory",
                )?;
            }
            #[cfg(not(target_os = "linux"))]
            if self.memory_mb > 0 {
                tracing::warn!("memory limit is applied on Linux only");
            }
            if self.open_files > 0 {
                cap(Resource::RLIMIT_NOFILE, self.open_files, "open files")?;
            }
        }
        Ok(())
    }
}

/// `true` when started by the supervisor (it always sets the limits).
pub fn supervised() -> bool {
    std::env::var_os(OPEN_FILES_ENV).is_some()
}

/// For `main`, before the tokio runtime: apply the supervisor's limits.
/// Does nothing outside supervision.
pub fn apply_from_env() -> Result<()> {
    if supervised() {
        Limits::from_env()?.apply()?;
    }
    Ok(())
}

/// Linux: whether every thread of this process has `no_new_privs`.
#[cfg(target_os = "linux")]
pub fn all_threads_no_new_privs() -> std::io::Result<bool> {
    for t in std::fs::read_dir("/proc/self/task")? {
        let status = std::fs::read_to_string(t?.path().join("status"))?;
        let on = status
            .lines()
            .find_map(|l| l.strip_prefix("NoNewPrivs:"))
            .is_some_and(|v| v.trim() == "1");
        if !on {
            return Ok(false);
        }
    }
    Ok(true)
}

#[cfg(all(test, unix))]
mod tests {
    use super::*;
    use nix::sys::resource::{getrlimit, Resource};

    const PROBE: &str = "WYRM_LIMITS_PROBE";

    /// Runs only in the child started by `limits_hold_in_a_child`.
    #[test]
    fn probe() {
        if std::env::var_os(PROBE).is_none() {
            return;
        }
        Limits::from_env().unwrap().apply().unwrap();
        let show = |r| {
            let (s, h) = getrlimit(r).unwrap();
            format!("{s}/{h}")
        };
        #[cfg(target_os = "linux")]
        let nnp = std::fs::read_to_string("/proc/thread-self/status")
            .unwrap()
            .lines()
            .find_map(|l| l.strip_prefix("NoNewPrivs:").map(|v| v.trim().to_owned()))
            .unwrap();
        #[cfg(not(target_os = "linux"))]
        let nnp = "-";
        println!(
            "LIMITS core={} data={} nofile={} nnp={nnp}",
            show(Resource::RLIMIT_CORE),
            show(Resource::RLIMIT_DATA),
            show(Resource::RLIMIT_NOFILE)
        );
    }

    #[test]
    fn limits_hold_in_a_child() {
        let out = std::process::Command::new(std::env::current_exe().unwrap())
            .args([
                "--exact",
                "limits::tests::probe",
                "--nocapture",
                "--test-threads=1",
            ])
            .env(PROBE, "1")
            .envs(
                Limits {
                    memory_mb: 2048,
                    open_files: 256,
                }
                .to_env(),
            )
            .output()
            .unwrap();
        let text = String::from_utf8_lossy(&out.stdout);
        let line = text
            .lines()
            .find_map(|l| l.find("LIMITS ").map(|i| &l[i..]))
            .unwrap_or_else(|| panic!("no probe output: {text}"));
        assert!(line.contains("core=0/0"), "{line}");
        #[cfg(target_os = "linux")]
        {
            let data = 2048u64 << 20;
            assert!(line.contains(&format!("data={data}/{data}")), "{line}");
            assert!(line.contains("nnp=1"), "{line}");
        }
        assert!(line.contains("nofile=256/256"), "{line}");
    }

    #[test]
    fn env_round_trip() {
        let l = Limits {
            memory_mb: 5,
            open_files: 7,
        };
        let env = l.to_env();
        let get = |k: &str| env.iter().find(|(n, _)| n == k).map(|(_, v)| v.clone());
        assert_eq!(Limits::from_vars(get).unwrap(), l);
        assert_eq!(Limits::from_vars(|_| None).unwrap(), Limits::default());
        assert!(Limits::from_vars(|_| Some("x".into())).is_err());
    }
}
