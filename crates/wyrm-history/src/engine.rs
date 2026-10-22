//! Watch groups (as DSA's historian): each group follows its watch paths on
//! the broker's in-process session and records them into the [`Store`] by
//! its logging type, buffered and written every `flush` interval.
//!
//! The historian outlives router rebuilds: [`Historian::attach`] binds it to
//! each new session, [`Historian::detach`] flushes and lets go of the old one.

use crate::store::{encode_row, NewRow, Row, Store};
use std::collections::HashMap;
use std::path::Path;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use tokio::sync::{mpsc, watch};
use tokio::task::{JoinHandle, JoinSet};
use tracing::{debug, warn};
use wyrm_client::{ValEvent, WyrmClient};
use wyrm_core::{Quality, Sample};
use zenoh::Session;

/// What a group records (DSA `Logging Type`).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Logging {
    /// Nothing (the group is paused).
    None,
    /// The last value of each point every `interval`, changed or not.
    Interval,
    /// Every update.
    AllData,
    /// Updates whose value or quality differ from the last one recorded.
    PointChange,
}

impl Logging {
    pub const ALL: [Logging; 4] = [
        Logging::None,
        Logging::Interval,
        Logging::AllData,
        Logging::PointChange,
    ];

    pub fn name(self) -> &'static str {
        match self {
            Logging::None => "none",
            Logging::Interval => "interval",
            Logging::AllData => "all_data",
            Logging::PointChange => "point_change",
        }
    }

    /// The DSA names, shown to people.
    pub fn display(self) -> &'static str {
        match self {
            Logging::None => "None",
            Logging::Interval => "Interval",
            Logging::AllData => "All Data",
            Logging::PointChange => "Point Change",
        }
    }

    pub fn code(self) -> u8 {
        match self {
            Logging::None => 0,
            Logging::Interval => 1,
            Logging::AllData => 2,
            Logging::PointChange => 3,
        }
    }

    pub fn from_code(c: u8) -> Option<Self> {
        Self::ALL.into_iter().find(|l| l.code() == c)
    }

    /// By name or display name.
    pub fn parse(s: &str) -> Option<Self> {
        Self::ALL
            .into_iter()
            .find(|l| l.name() == s || l.display() == s)
    }
}

/// One watch group as configured (stored by the admin's registry).
#[derive(Debug, Clone, PartialEq)]
pub struct GroupCfg {
    pub name: String,
    pub logging: Logging,
    /// `Interval` logging: how often (ms).
    pub interval_ms: u64,
    /// How often the buffer goes to disk (ms; DSA `Buffer Flush Time`).
    pub flush_ms: u64,
    pub watches: Vec<WatchCfg>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct WatchCfg {
    /// Node id under the group (`w1`, `w2`, …).
    pub id: String,
    /// Point key, `wy/<site>/down/…`.
    pub key: String,
    pub enabled: bool,
}

/// Shortest flush and logging intervals.
pub const MIN_FLUSH_MS: u64 = 100;
pub const MIN_INTERVAL_MS: u64 = 100;
/// Rows waiting for a flush, all groups together; more are dropped
/// (counted). About 10–20 MiB of memory.
pub const MAX_PENDING: u64 = 200_000;

/// Counters for `sys/history`.
#[derive(Debug, Default)]
pub struct Counters {
    /// Rows written since start.
    pub rows_written: AtomicU64,
    /// Rows dropped: buffer full or a failed write.
    pub dropped: AtomicU64,
    /// Rows waiting for a flush.
    pub pending: AtomicU64,
    /// Duration of the last flush (µs).
    pub last_flush_us: AtomicU64,
    pub write_errors: AtomicU64,
    last_error: Mutex<Option<String>>,
}

impl Counters {
    pub fn last_error(&self) -> Option<String> {
        self.last_error
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .clone()
    }
}

struct Running {
    cfg: GroupCfg,
    stop: watch::Sender<bool>,
    task: JoinHandle<()>,
}

#[derive(Default)]
struct Run {
    session: Option<Session>,
    groups: HashMap<String, Running>,
}

pub struct Historian {
    store: Arc<Store>,
    counters: Arc<Counters>,
    /// Last row written per point key.
    last: Arc<Mutex<HashMap<String, Row>>>,
    run: Mutex<Run>,
}

pub fn now_us() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_micros() as u64)
        .unwrap_or(0)
}

impl Historian {
    pub fn open(dir: &Path) -> crate::store::Result<Arc<Self>> {
        Ok(Arc::new(Self {
            store: Arc::new(Store::open(dir)?),
            counters: Arc::default(),
            last: Arc::default(),
            run: Mutex::default(),
        }))
    }

    pub fn store(&self) -> &Arc<Store> {
        &self.store
    }

    pub fn counters(&self) -> &Counters {
        &self.counters
    }

    /// The last row written for `key` since start.
    pub fn last_written(&self, key: &str) -> Option<Row> {
        self.last
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .get(key)
            .cloned()
    }

    /// Forget what was written for `key` (after a purge).
    pub fn forget(&self, key: &str) {
        self.last
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .remove(key);
    }

    /// Bind to `session` (a new router runtime) and run `groups`.
    pub fn attach(&self, session: Session, groups: Vec<GroupCfg>) {
        self.run.lock().unwrap_or_else(|p| p.into_inner()).session = Some(session);
        self.configure(groups);
    }

    /// Flush and stop every group; the session goes away.
    pub async fn detach(&self) {
        let groups: Vec<Running> = {
            let mut run = self.run.lock().unwrap_or_else(|p| p.into_inner());
            run.session = None;
            run.groups.drain().map(|(_, r)| r).collect()
        };
        for r in groups {
            stop(r).await;
        }
    }

    /// Run `groups` now: a group whose settings changed restarts, a group
    /// gone stops (both after a flush).
    pub fn configure(&self, groups: Vec<GroupCfg>) {
        let mut run = self.run.lock().unwrap_or_else(|p| p.into_inner());
        let Some(session) = run.session.clone() else {
            return;
        };
        let wanted: HashMap<String, GroupCfg> =
            groups.into_iter().map(|g| (g.name.clone(), g)).collect();
        let stale: Vec<String> = run
            .groups
            .iter()
            .filter(|(name, r)| wanted.get(*name) != Some(&r.cfg))
            .map(|(name, _)| name.clone())
            .collect();
        for name in stale {
            if let Some(r) = run.groups.remove(&name) {
                tokio::spawn(stop(r));
            }
        }
        for (name, cfg) in wanted {
            if run.groups.contains_key(&name) {
                continue;
            }
            let (tx, rx) = watch::channel(false);
            let task = tokio::spawn(run_group(
                self.store.clone(),
                self.counters.clone(),
                self.last.clone(),
                session.clone(),
                cfg.clone(),
                rx,
            ));
            run.groups.insert(
                name,
                Running {
                    cfg,
                    stop: tx,
                    task,
                },
            );
        }
    }
}

async fn stop(r: Running) {
    let _ = r.stop.send(true);
    let abort = r.task.abort_handle();
    if tokio::time::timeout(Duration::from_secs(10), r.task)
        .await
        .is_err()
    {
        warn!(group = %r.cfg.name, "history group did not stop in time");
        abort.abort();
    }
}

/// One watch while its group runs.
struct Point {
    key: String,
    series: u32,
    /// Last row in the store (or written since): duplicates and unchanged
    /// values are skipped against it.
    stored: Option<Row>,
    /// Last sample seen (`Interval` logging).
    seen: Option<Sample>,
}

async fn run_group(
    store: Arc<Store>,
    counters: Arc<Counters>,
    last: Arc<Mutex<HashMap<String, Row>>>,
    session: Session,
    cfg: GroupCfg,
    mut stop: watch::Receiver<bool>,
) {
    if cfg.logging == Logging::None {
        return;
    }
    let keys: Vec<String> = cfg
        .watches
        .iter()
        .filter(|w| w.enabled)
        .map(|w| w.key.clone())
        .collect();
    let st = store.clone();
    let points = tokio::task::spawn_blocking(move || {
        keys.into_iter()
            .map(|key| {
                let series = st.series_id(&key, true)?.unwrap_or_default();
                let stored = st.edge(series, true)?;
                Ok(Point {
                    key,
                    series,
                    stored,
                    seen: None,
                })
            })
            .collect::<crate::store::Result<Vec<Point>>>()
    })
    .await;
    let mut points = match points {
        Ok(Ok(p)) => p,
        Ok(Err(e)) => {
            warn!(group = %cfg.name, "history group not started: {e}");
            return;
        }
        Err(_) => return,
    };
    let (tx, mut rx) = mpsc::channel::<(usize, Sample)>(4096);
    let mut subs = JoinSet::new();
    let client = WyrmClient::new(session);
    for (i, p) in points.iter().enumerate() {
        let (client, key, tx) = (client.clone(), p.key.clone(), tx.clone());
        subs.spawn(follow(client, key, i, tx));
    }
    drop(tx);
    let mut buffer: Vec<NewRow> = Vec::new();
    let mut flush = tokio::time::interval(Duration::from_millis(cfg.flush_ms.max(MIN_FLUSH_MS)));
    let mut sample_tick =
        tokio::time::interval(Duration::from_millis(cfg.interval_ms.max(MIN_INTERVAL_MS)));
    sample_tick.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
    let interval = cfg.logging == Logging::Interval;
    debug!(group = %cfg.name, points = points.len(), "history group running");
    loop {
        tokio::select! {
            m = rx.recv() => {
                let Some((i, s)) = m else { break };
                let p = &mut points[i];
                let record = match cfg.logging {
                    Logging::Interval => {
                        p.seen = Some(s);
                        None
                    }
                    Logging::AllData => {
                        let new = p.stored.as_ref().is_none_or(|r| s.t > r.t);
                        new.then_some(s)
                    }
                    Logging::PointChange => {
                        let changed = p
                            .stored
                            .as_ref()
                            .is_none_or(|r| s.t > r.t && (r.v != s.v || r.q != s.q));
                        changed.then_some(s)
                    }
                    Logging::None => None,
                };
                if let Some(s) = record {
                    push(&mut buffer, &counters, p, s.t, s.v, s.q);
                }
            }
            _ = sample_tick.tick(), if interval => {
                let t = now_us();
                for p in points.iter_mut() {
                    if let Some(s) = p.seen.clone() {
                        push(&mut buffer, &counters, p, t, s.v, s.q);
                    }
                }
            }
            _ = flush.tick() => write(&store, &counters, &last, &points, &mut buffer).await,
            _ = stop.changed() => break,
        }
    }
    subs.shutdown().await;
    write(&store, &counters, &last, &points, &mut buffer).await;
    debug!(group = %cfg.name, "history group stopped");
}

/// Follow one point (stored value first, then live), retrying while the
/// router comes up.
async fn follow(client: WyrmClient, key: String, i: usize, tx: mpsc::Sender<(usize, Sample)>) {
    loop {
        match client.subscribe(&key).await {
            Ok(mut events) => {
                while let Some(ev) = events.next().await {
                    if let ValEvent::Sample { sample, .. } = ev {
                        if tx.send((i, sample)).await.is_err() {
                            return;
                        }
                    }
                }
                return;
            }
            Err(e) => {
                debug!(%key, "history subscribe: {e}");
                tokio::time::sleep(Duration::from_secs(2)).await;
            }
        }
    }
}

fn push(
    buffer: &mut Vec<NewRow>,
    counters: &Counters,
    p: &mut Point,
    t: u64,
    v: wyrm_core::Value,
    q: Quality,
) {
    if counters.pending.load(Ordering::Relaxed) >= MAX_PENDING {
        counters.dropped.fetch_add(1, Ordering::Relaxed);
        return;
    }
    buffer.push((p.series, t, encode_row(&v, q)));
    counters.pending.fetch_add(1, Ordering::Relaxed);
    p.stored = Some(Row { t, v, q });
}

async fn write(
    store: &Arc<Store>,
    counters: &Arc<Counters>,
    last: &Arc<Mutex<HashMap<String, Row>>>,
    points: &[Point],
    buffer: &mut Vec<NewRow>,
) {
    if buffer.is_empty() {
        return;
    }
    let rows = std::mem::take(buffer);
    let n = rows.len() as u64;
    let st = store.clone();
    let started = std::time::Instant::now();
    let r = tokio::task::spawn_blocking(move || st.write(&rows)).await;
    counters.pending.fetch_sub(n, Ordering::Relaxed);
    counters
        .last_flush_us
        .store(started.elapsed().as_micros() as u64, Ordering::Relaxed);
    match r {
        Ok(Ok(_)) => {
            counters.rows_written.fetch_add(n, Ordering::Relaxed);
            let mut last = last.lock().unwrap_or_else(|p| p.into_inner());
            for p in points {
                if let Some(r) = &p.stored {
                    last.insert(p.key.clone(), r.clone());
                }
            }
        }
        Ok(Err(e)) => {
            counters.write_errors.fetch_add(1, Ordering::Relaxed);
            counters.dropped.fetch_add(n, Ordering::Relaxed);
            warn!("history write: {e}");
            *counters
                .last_error
                .lock()
                .unwrap_or_else(|p| p.into_inner()) = Some(e.to_string());
        }
        Err(_) => {
            counters.dropped.fetch_add(n, Ordering::Relaxed);
        }
    }
}
