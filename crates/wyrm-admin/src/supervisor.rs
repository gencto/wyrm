//! Process supervisor (wiki "Життєвий цикл конектора"). Lives outside the
//! rebuilt broker, so a reload never kills or duplicates children.

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use tokio::process::Command;
use tokio::sync::watch;
use tokio::task::JoinHandle;
use tracing::{info, warn};

const STOP_GRACE: Duration = Duration::from_secs(10);
const BACKOFF_MAX: Duration = Duration::from_secs(60);
/// A run longer than this resets the restart counter.
const HEALTHY_RUN: Duration = Duration::from_secs(60);

#[derive(Debug, Clone)]
pub struct ProcSpec {
    pub id: String,
    pub exe: PathBuf,
    pub args: Vec<String>,
    pub env: Vec<(String, String)>,
    pub max_restarts: u32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ProcState {
    Starting,
    Running(u32),
    Backoff,
    Stopping,
    Stopped,
    Failed,
}

struct Proc {
    stop: watch::Sender<bool>,
    task: JoinHandle<()>,
    state: Arc<Mutex<ProcState>>,
}

#[derive(Default)]
pub struct Supervisor {
    procs: Mutex<HashMap<String, Proc>>,
}

fn set(state: &Mutex<ProcState>, s: ProcState) {
    *state.lock().unwrap_or_else(|p| p.into_inner()) = s;
}

#[cfg(unix)]
fn terminate(pid: u32) {
    use nix::sys::signal::{kill, Signal};
    use nix::unistd::Pid;
    if let Ok(pid) = i32::try_from(pid) {
        let _ = kill(Pid::from_raw(pid), Signal::SIGTERM);
    }
}

impl Supervisor {
    pub fn new() -> Arc<Self> {
        Arc::new(Self::default())
    }

    /// Start `spec` unless it is already supervised and alive.
    pub fn start(&self, spec: ProcSpec) {
        let mut procs = self.procs.lock().unwrap_or_else(|p| p.into_inner());
        if let Some(p) = procs.get(&spec.id) {
            if !p.task.is_finished() {
                return;
            }
        }
        let (stop, rx) = watch::channel(false);
        let state = Arc::new(Mutex::new(ProcState::Starting));
        let id = spec.id.clone();
        let task = tokio::spawn(monitor(spec, rx, state.clone()));
        procs.insert(id, Proc { stop, task, state });
    }

    /// SIGTERM, wait up to 10 s, then kill. No-op if not supervised.
    pub async fn stop(&self, id: &str) {
        let p = self
            .procs
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .remove(id);
        if let Some(p) = p {
            let _ = p.stop.send(true);
            let _ = p.task.await;
        }
    }

    pub async fn stop_all(&self) {
        let ids: Vec<String> = self
            .procs
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .keys()
            .cloned()
            .collect();
        for id in ids {
            self.stop(&id).await;
        }
    }

    pub fn state(&self, id: &str) -> Option<ProcState> {
        self.procs
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .get(id)
            .map(|p| *p.state.lock().unwrap_or_else(|p| p.into_inner()))
    }
}

/// Broker variables a link process may inherit (logging, locale, time zone).
const INHERITED_ENV: &[&str] = &["RUST_LOG", "RUST_BACKTRACE", "TZ", "LANG", "LC_ALL", "PATH"];

async fn monitor(spec: ProcSpec, mut stop: watch::Receiver<bool>, state: Arc<Mutex<ProcState>>) {
    let mut restarts = 0u32;
    let mut backoff = Duration::from_secs(1);
    loop {
        set(&state, ProcState::Starting);
        let mut cmd = Command::new(&spec.exe);
        // A link sees only its own settings, never the broker's environment
        // (bootstrap passwords and other secrets live there).
        cmd.args(&spec.args)
            .env_clear()
            .envs(
                INHERITED_ENV
                    .iter()
                    .filter_map(|k| std::env::var_os(k).map(|v| (k.to_string(), v))),
            )
            .envs(spec.env.iter().cloned())
            .stdin(std::process::Stdio::null())
            .kill_on_drop(false);
        let started = Instant::now();
        let child = cmd.spawn();
        let exited = match child {
            Err(e) => {
                warn!(link = %spec.id, "spawn {}: {e}", spec.exe.display());
                true
            }
            Ok(mut child) => {
                let pid = child.id().unwrap_or(0);
                info!(link = %spec.id, pid, "link process started");
                set(&state, ProcState::Running(pid));
                tokio::select! {
                    status = child.wait() => {
                        warn!(link = %spec.id, ?status, "link process exited");
                        true
                    }
                    _ = stop.changed() => {
                        set(&state, ProcState::Stopping);
                        #[cfg(unix)]
                        terminate(pid);
                        #[cfg(not(unix))]
                        let _ = child.start_kill();
                        if tokio::time::timeout(STOP_GRACE, child.wait()).await.is_err() {
                            warn!(link = %spec.id, "no exit after SIGTERM; killing");
                            let _ = child.kill().await;
                        }
                        false
                    }
                }
            }
        };
        if !exited || *stop.borrow() {
            set(&state, ProcState::Stopped);
            return;
        }
        if started.elapsed() > HEALTHY_RUN {
            restarts = 0;
            backoff = Duration::from_secs(1);
        }
        restarts += 1;
        if restarts > spec.max_restarts {
            warn!(link = %spec.id, restarts, "giving up");
            set(&state, ProcState::Failed);
            return;
        }
        set(&state, ProcState::Backoff);
        tokio::select! {
            _ = tokio::time::sleep(backoff) => {}
            _ = stop.changed() => {
                set(&state, ProcState::Stopped);
                return;
            }
        }
        backoff = (backoff * 2).min(BACKOFF_MAX);
    }
}

#[cfg(all(test, unix))]
mod tests {
    use super::*;

    fn spec(id: &str, script: &str, max: u32) -> ProcSpec {
        ProcSpec {
            id: id.into(),
            exe: "/bin/sh".into(),
            args: vec!["-c".into(), script.into()],
            env: vec![],
            max_restarts: max,
        }
    }

    #[tokio::test(flavor = "multi_thread")]
    async fn stop_sends_sigterm() {
        let s = Supervisor::new();
        s.start(spec(
            "a",
            "trap 'exit 0' TERM; while true; do sleep 0.05; done",
            3,
        ));
        tokio::time::sleep(Duration::from_millis(200)).await;
        assert!(matches!(s.state("a"), Some(ProcState::Running(_))));
        let t = Instant::now();
        s.stop("a").await;
        assert!(
            t.elapsed() < Duration::from_secs(5),
            "graceful, not the 10 s kill"
        );
        assert_eq!(s.state("a"), None);
    }

    #[tokio::test(flavor = "multi_thread")]
    async fn crash_loop_gives_up() {
        let s = Supervisor::new();
        s.start(spec("b", "exit 3", 1));
        // first run, 1 s backoff, second run, then failed
        let deadline = Instant::now() + Duration::from_secs(5);
        while s.state("b") != Some(ProcState::Failed) {
            assert!(Instant::now() < deadline, "state {:?}", s.state("b"));
            tokio::time::sleep(Duration::from_millis(50)).await;
        }
    }
}
