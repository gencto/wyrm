//! [`Runtime`]: one portable link.
//!
//! ```text
//!  SDK (on_set / on_invoke / stop) ──Input──▶ actor task ──Job (one at a time)──▶ engine thread
//!  timer, subscription, request tasks ──Internal──▶  │ ◀──────────Outcome─────────── (app call,
//!                                                    │                                store writes)
//!                                     applies commands through LinkCtx, answers the caller
//! ```
//!
//! - The engine runs on its own OS thread and owns the app and the [`BufferHost`]; the actor
//!   gives it one job at a time and applies the commands of a job before it sends the next, so
//!   every event sees the effects of the one before it.
//! - The event queue (at most [`QUEUE`] entries) lives in the actor, where it can coalesce: when
//!   it is full a value replaces the queued value of its subscription, `set`/`invoke` get `busy`;
//!   timers and replies are always queued (their number is bounded by the limits).
//! - Store writes are applied on the engine thread right after the call, before the event's other
//!   commands, so the next event reads them and they are durable before the reply leaves.

use std::collections::{BTreeSet, HashMap, VecDeque};
use std::hash::{BuildHasher, Hasher};
use std::marker::PhantomData;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use tokio::sync::{mpsc, oneshot};
use tokio::task::AbortHandle;
use tokio::time::Instant;
use tracing::{debug, error, info, warn, Instrument};
use wyrm_client::{ClientError, SigningTokens, ValEvent, WyrmClient};
use wyrm_core::ptok::Grant;
use wyrm_core::status::StatusCode;
use wyrm_core::{keyspace, Quality, Status, Value};
use wyrm_link_api::buffer::{BufferHost, Command, Counts, Limits};
use wyrm_link_api::{AppError, Level, ReqId, SubId, TimerId, Who};
use wyrm_link_sdk::driver::persist::STORE_KEY;
use wyrm_link_sdk::{Caller, Link, LinkCtx, LinkError, ReplySink};

use crate::engine::{Engine, Event, Fault, MakeEngine};
use crate::services::{lock, CallState, RuntimeServices, SharedCall, SharedStore};
use crate::store::Store;
use crate::PortableConfig;

/// Events waiting for the engine (values of one subscription coalesce beyond this).
pub const QUEUE: usize = 256;
/// Nodes of a dead instance that the new `start` does not declare again go after this.
pub const SWEEP_AFTER: Duration = Duration::from_secs(10);
/// No event completed for this long: the link is `stuck`.
pub const STUCK_AFTER: Duration = Duration::from_secs(30);
const BACKOFF_FIRST: Duration = Duration::from_secs(1);
const BACKOFF_CAP: Duration = Duration::from_secs(60);
/// Bound on the app's `stop` (and on the call in flight before it).
const STOP_WAIT: Duration = Duration::from_secs(2);
/// `Link::start` waits this long for the app's first `start`, then returns anyway.
const FIRST_START_WAIT: Duration = Duration::from_secs(10);
const INPUTS: usize = 64;
const MIB: u64 = 1024 * 1024;

const RUNNING: &str = "running";
const RESTARTING: &str = "restarting";
const STUCK: &str = "stuck";

type Answer = oneshot::Sender<Result<Option<Value>, AppError>>;

enum Input {
    Request(Event, Answer),
    Stop(oneshot::Sender<()>),
}

/// From the tasks of the current instance; ids that are no longer known are ignored.
enum Internal {
    Timer(u64),
    Value(u64, String, wyrm_core::Sample),
    Reply(u64, Result<Value, AppError>),
}

/// `Start` and `Event` carry a sequence number: the store remembers the last one whose writes it
/// applied (see [`Actor::stop`]).
enum Job {
    Start(u64, Value, Counts),
    Event(u64, Event, Counts),
    Reset,
    Exit,
}

enum Failure {
    Fault(String),
    /// The engine's code was replaced: start the new code at once.
    Replaced,
    /// A bound the app could not see, or a store write that failed.
    Apply(AppError),
}

struct Outcome {
    result: Result<Result<Option<Value>, AppError>, Failure>,
    cmds: Vec<Command>,
}

fn busy(msg: &str) -> AppError {
    AppError::new(Status::Busy, msg)
}

const REPLACED: &str = "the link's code was replaced";

fn from_link(e: LinkError) -> AppError {
    AppError::new(e.status, e.message)
}

fn from_client(e: ClientError) -> AppError {
    let status = match e.status {
        StatusCode::Known(s) => s,
        _ => Status::InternalError,
    };
    AppError::new(status, e.message)
}

fn answer(to: Option<Answer>, r: Result<Option<Value>, AppError>) {
    if let Some(tx) = to {
        let _ = tx.send(r);
    }
}

// ---------- engine thread ----------

fn engine_thread<E: Engine>(
    mut engine: E,
    mut host: BufferHost,
    store: SharedStore,
    call: SharedCall,
    call_time: Duration,
    jobs: std::sync::mpsc::Receiver<Job>,
    out: mpsc::UnboundedSender<Outcome>,
) {
    while let Ok(job) = jobs.recv() {
        let begin = |counts: Counts, host: &mut BufferHost| {
            host.set_counts(counts);
            lock(&call).deadline = Some(std::time::Instant::now() + call_time);
        };
        let (start, seq, r) = match job {
            Job::Exit => return,
            Job::Reset => {
                engine.reset();
                lock(&call).reset = true;
                continue;
            }
            Job::Start(seq, config, counts) => {
                begin(counts, &mut host);
                (
                    true,
                    seq,
                    engine.start(&mut host, &config).map(|r| r.map(|()| None)),
                )
            }
            Job::Event(seq, ev, counts) => {
                begin(counts, &mut host);
                (false, seq, engine.event(&mut host, ev))
            }
        };
        lock(&call).deadline = None;
        if out
            .send(conclude(start, seq, r, &mut host, &store))
            .is_err()
        {
            return;
        }
    }
}

/// The event's commands, with the store writes applied; nothing when the call faulted, the app's
/// `start` failed, a path belongs to the host or the runtime gave the event up (stop): the store
/// changes only for an event whose other commands are going to be applied.
fn conclude(
    start: bool,
    seq: u64,
    r: Result<Result<Option<Value>, AppError>, Fault>,
    host: &mut BufferHost,
    store: &SharedStore,
) -> Outcome {
    let cmds = host.finish();
    let fail = |f| Outcome {
        result: Err(f),
        cmds: Vec::new(),
    };
    let r = match r {
        Err(Fault::Crash(m)) => return fail(Failure::Fault(m)),
        Err(Fault::Replaced) => return fail(Failure::Replaced),
        Ok(Err(e)) if start => {
            return Outcome {
                result: Ok(Err(e)),
                cmds: Vec::new(),
            }
        }
        Ok(r) => r,
    };
    let cmds = match cmds {
        Ok(c) => c,
        Err(e) => return fail(Failure::Apply(e)),
    };
    if let Err(e) = check_paths(&cmds) {
        return fail(Failure::Apply(e));
    }
    let mut rest = Vec::with_capacity(cmds.len());
    let mut st = lock(store);
    if st.is_abandoned() {
        return fail(Failure::Apply(busy("the link stopped")));
    }
    for c in cmds {
        let w = match c {
            Command::StorePut(k, v) => st.put(&k, &v),
            Command::StoreDelete(k) => st.delete(&k),
            other => {
                rest.push(other);
                continue;
            }
        };
        if let Err(e) = w {
            return fail(Failure::Apply(AppError::new(
                Status::InternalError,
                format!("store: {e}"),
            )));
        }
    }
    st.commit(seq);
    Outcome {
        result: Ok(r),
        cmds: rest,
    }
}

/// What a stopped link answers for an outcome it did not apply.
fn result_of(o: Outcome) -> Result<Option<Value>, AppError> {
    match o.result {
        Ok(r) => r,
        Err(Failure::Fault(m)) => Err(AppError::new(
            Status::InternalError,
            format!("the link crashed: {m}"),
        )),
        Err(Failure::Replaced) => Err(busy(REPLACED)),
        Err(Failure::Apply(e)) => Err(e),
    }
}

// ---------- actor ----------

enum State {
    /// A `start` is in flight.
    Starting,
    Running,
    /// Waiting to start again.
    Backoff(Instant),
}

struct InFlight {
    seq: u64,
    since: Instant,
    answer: Option<Answer>,
    start: bool,
}

struct Pending {
    ev: Event,
    answer: Option<Answer>,
}

struct Actor {
    ctx: LinkCtx,
    params: Value,
    jobs: std::sync::mpsc::SyncSender<Job>,
    internal: mpsc::UnboundedSender<Internal>,
    client: WyrmClient,
    state: State,
    queue: VecDeque<Pending>,
    inflight: Option<InFlight>,
    timers: HashMap<u64, AbortHandle>,
    subs: HashMap<u64, AbortHandle>,
    reqs: HashMap<u64, AbortHandle>,
    paths: Paths,
    max_nodes: usize,
    /// When the nodes of dead instances that were not declared again go.
    sweep_at: Option<Instant>,
    store: SharedStore,
    seq: u64,
    backoff: Duration,
    started_at: Option<Instant>,
    stuck: bool,
    /// What the root shows now.
    status: Option<(&'static str, Option<String>)>,
}

/// ±20 % around `d`.
fn jitter(d: Duration) -> Duration {
    let mut h = std::collections::hash_map::RandomState::new().build_hasher();
    h.write_u128(std::time::UNIX_EPOCH.elapsed().map_or(0, |t| t.as_nanos()));
    let frac = (h.finish() % 10_001) as f64 / 10_000.0;
    d.mul_f64(0.8 + 0.4 * frac)
}

/// The app's nodes in the tree: those the current instance declared and those of dead instances
/// that wait for the sweep. The two sets never share a path, so the tree holds `len()` app nodes.
#[derive(Debug, Default)]
struct Paths {
    declared: BTreeSet<String>,
    sweep: BTreeSet<String>,
}

impl Paths {
    fn len(&self) -> usize {
        self.declared.len() + self.sweep.len()
    }

    /// Room for `declare_node(p)`: a path already in the tree adds nothing; a new one needs room
    /// under `max`.
    fn admit(&self, p: &str, max: usize) -> Result<(), AppError> {
        if self.declared.contains(p) || self.sweep.contains(p) || self.len() < max {
            Ok(())
        } else {
            Err(AppError::new(
                Status::ResourceExhausted,
                format!("too many nodes (at most {max})"),
            ))
        }
    }

    fn declared(&mut self, p: String) {
        self.sweep.remove(&p);
        self.declared.insert(p);
    }

    fn removed(&mut self, p: &str) {
        self.declared.retain(|d| d != p && !under(p, d));
        self.sweep.retain(|d| d != p && !under(p, d));
    }

    /// The instance is gone: what it declared waits for the sweep.
    fn fault(&mut self) {
        self.sweep.append(&mut self.declared);
    }

    /// The paths to remove now, parents first; a path with a declared node below it stays.
    fn take_sweep(&mut self) -> Vec<String> {
        let mut gone: Vec<String> = std::mem::take(&mut self.sweep)
            .into_iter()
            .filter(|p| !self.declared.iter().any(|d| under(p, d)))
            .collect();
        gone.sort_by_key(|p| p.len());
        gone
    }
}

/// Checks done before anything of an event is applied, the store included.
fn check_paths(cmds: &[Command]) -> Result<(), AppError> {
    for c in cmds {
        match c {
            Command::DeclareNode(p, _) | Command::RemoveNode(p) | Command::Update(p, _) => {
                check_path(p, false)?
            }
            Command::DeclareAction(p, ..) => check_path(p, true)?,
            _ => {}
        }
    }
    Ok(())
}

/// App paths are under the root and never hidden: `""` and any segment starting with `.`
/// belong to the host.
fn check_path(p: &str, root_ok: bool) -> Result<(), AppError> {
    if (p.is_empty() && !root_ok) || p.split('/').any(|s| s.starts_with('.')) {
        return Err(AppError::new(
            Status::InvalidParameter,
            format!("{p:?}: the link root and paths starting with '.' belong to the host"),
        ));
    }
    Ok(())
}

fn under(p: &str, d: &str) -> bool {
    d.strip_prefix(p).is_some_and(|r| r.starts_with('/'))
}

impl Actor {
    fn counts(&self) -> Counts {
        Counts {
            timers: self.timers.len(),
            subs: self.subs.len(),
            inflight: self.reqs.len(),
        }
    }

    async fn run(
        mut self,
        mut inputs: mpsc::Receiver<Input>,
        mut internal: mpsc::UnboundedReceiver<Internal>,
        mut outcomes: mpsc::UnboundedReceiver<Outcome>,
        first: oneshot::Sender<()>,
    ) {
        let mut first = Some(first);
        self.begin_start().await;
        let mut tick = tokio::time::interval(Duration::from_secs(1));
        let far = || Instant::now() + Duration::from_secs(86_400);
        loop {
            self.pump();
            let backoff_at = match self.state {
                State::Backoff(at) => Some(at),
                _ => None,
            };
            let sweep_at = self.sweep_at;
            tokio::select! {
                inp = inputs.recv() => match inp {
                    Some(Input::Request(ev, tx)) => self.on_request(ev, tx),
                    Some(Input::Stop(tx)) => {
                        self.stop(&mut outcomes).await;
                        let _ = tx.send(());
                        return;
                    }
                    None => {
                        self.stop(&mut outcomes).await;
                        return;
                    }
                },
                Some(i) = internal.recv() => self.on_internal(i),
                o = outcomes.recv() => {
                    let Some(o) = o else {
                        error!("the engine thread is gone");
                        return;
                    };
                    if self.on_outcome(o).await {
                        if let Some(f) = first.take() {
                            let _ = f.send(());
                        }
                    }
                }
                _ = tokio::time::sleep_until(backoff_at.unwrap_or_else(far)), if backoff_at.is_some() => {
                    self.begin_start().await;
                }
                _ = tokio::time::sleep_until(sweep_at.unwrap_or_else(far)), if sweep_at.is_some() => {
                    self.sweep_now().await;
                }
                _ = tick.tick() => self.check_stuck().await,
            }
        }
    }

    fn on_request(&mut self, ev: Event, tx: Answer) {
        if !matches!(self.state, State::Running) {
            let _ = tx.send(Err(busy("the link is restarting")));
        } else if self.queue.len() >= QUEUE {
            let _ = tx.send(Err(busy("the link's event queue is full")));
        } else {
            self.queue.push_back(Pending {
                ev,
                answer: Some(tx),
            });
        }
    }

    fn push(&mut self, ev: Event) {
        self.queue.push_back(Pending { ev, answer: None });
    }

    fn on_internal(&mut self, i: Internal) {
        match i {
            Internal::Timer(id) => {
                if self.timers.remove(&id).is_some() {
                    self.push(Event::Timer(TimerId(id)));
                }
            }
            Internal::Reply(id, r) => {
                if self.reqs.remove(&id).is_some() {
                    self.push(Event::Reply(ReqId(id), r));
                }
            }
            Internal::Value(id, key, sample) => {
                if !self.subs.contains_key(&id) {
                    return;
                }
                if self.queue.len() >= QUEUE {
                    let queued = self
                        .queue
                        .iter_mut()
                        .rev()
                        .find(|p| matches!(&p.ev, Event::Value(SubId(s), ..) if *s == id));
                    if let Some(p) = queued {
                        p.ev = Event::Value(SubId(id), key, sample);
                        return;
                    }
                }
                self.push(Event::Value(SubId(id), key, sample));
            }
        }
    }

    /// Hand the next event to the engine when it is idle.
    fn pump(&mut self) {
        if self.inflight.is_some() || !matches!(self.state, State::Running) {
            return;
        }
        let Some(p) = self.queue.pop_front() else {
            return;
        };
        self.seq += 1;
        if self
            .jobs
            .try_send(Job::Event(self.seq, p.ev, self.counts()))
            .is_err()
        {
            error!("the engine thread is gone");
            answer(
                p.answer,
                Err(AppError::new(
                    Status::InternalError,
                    "the link's engine is gone",
                )),
            );
            return;
        }
        self.inflight = Some(InFlight {
            seq: self.seq,
            since: Instant::now(),
            answer: p.answer,
            start: false,
        });
    }

    async fn begin_start(&mut self) {
        // A crash loop keeps the first deadline: nodes of dead instances go at the latest 10 s
        // after the first restart began, however often it fails since.
        match self.sweep_at {
            Some(at) if at <= Instant::now() => self.sweep_now().await,
            None if !self.paths.sweep.is_empty() => {
                self.sweep_at = Some(Instant::now() + SWEEP_AFTER);
            }
            _ => {}
        }
        self.state = State::Starting;
        self.seq += 1;
        let job = Job::Start(self.seq, self.params.clone(), self.counts());
        if self.jobs.try_send(job).is_err() {
            error!("the engine thread is gone");
            return;
        }
        self.inflight = Some(InFlight {
            seq: self.seq,
            since: Instant::now(),
            answer: None,
            start: true,
        });
    }

    /// Returns `true` when this was the outcome of a `start`.
    async fn on_outcome(&mut self, o: Outcome) -> bool {
        let Some(f) = self.inflight.take() else {
            return false;
        };
        let was_stuck = std::mem::take(&mut self.stuck);
        match o.result {
            Err(Failure::Fault(msg)) => {
                answer(
                    f.answer,
                    Err(AppError::new(
                        Status::InternalError,
                        format!("the link crashed: {msg}"),
                    )),
                );
                self.fault(msg).await;
            }
            Err(Failure::Replaced) => {
                answer(f.answer, Err(busy(REPLACED)));
                self.replaced().await;
            }
            Err(Failure::Apply(e)) => {
                let msg = e.to_string();
                answer(f.answer, Err(e));
                self.fault(msg).await;
            }
            Ok(Err(e)) if f.start => self.fault(format!("start: {e}")).await,
            Ok(r) => match self.apply(o.cmds).await {
                Ok(()) => {
                    answer(f.answer, r);
                    if f.start {
                        self.on_started().await;
                    } else if was_stuck {
                        self.set_status(RUNNING, None).await;
                    }
                }
                Err(e) => {
                    let msg = e.to_string();
                    answer(f.answer, Err(e));
                    self.fault(msg).await;
                }
            },
        }
        f.start
    }

    async fn on_started(&mut self) {
        self.state = State::Running;
        self.started_at = Some(Instant::now());
        self.backoff = self.backoff.max(BACKOFF_FIRST);
        self.set_status(RUNNING, None).await;
        info!("app running");
    }

    fn drop_tasks(&mut self) {
        for (_, h) in self
            .timers
            .drain()
            .chain(self.subs.drain())
            .chain(self.reqs.drain())
        {
            h.abort();
        }
    }

    /// The instance is gone: drop its timers, subscriptions and requests, mark its values, wait.
    async fn fault(&mut self, msg: String) {
        warn!(error = %msg, "app failed; starting again after a backoff");
        self.drop_tasks();
        for p in self.queue.drain(..) {
            answer(p.answer, Err(busy("the link is restarting")));
        }
        // `sweep_at` stays: see `begin_start`.
        self.paths.fault();
        if let Err(e) = self.ctx.mark_all(Quality::Bad, Some("bad/comm_fail")).await {
            debug!("mark values bad: {e}");
        }
        let _ = self.jobs.try_send(Job::Reset);
        if self
            .started_at
            .take()
            .is_some_and(|t| t.elapsed() >= BACKOFF_CAP)
        {
            self.backoff = BACKOFF_FIRST;
        }
        let wait = jitter(self.backoff);
        self.backoff = (self.backoff * 2).min(BACKOFF_CAP);
        self.state = State::Backoff(Instant::now() + wait);
        self.set_status(RESTARTING, Some(msg)).await;
    }

    /// A hot swap: the old instance's timers, subscriptions, requests and queued events go (their
    /// ids are its own), queued callers get `busy`, and the new code starts at once on the same
    /// store. Its nodes wait for the sweep as after a fault; values are not marked, the new
    /// `start` publishes its own.
    async fn replaced(&mut self) {
        info!("{REPLACED}; starting the new code");
        self.drop_tasks();
        for p in self.queue.drain(..) {
            answer(p.answer, Err(busy(REPLACED)));
        }
        self.paths.fault();
        let _ = self.jobs.try_send(Job::Reset);
        self.begin_start().await;
    }

    async fn sweep_now(&mut self) {
        self.sweep_at = None;
        for p in self.paths.take_sweep() {
            if self.ctx.has_node(&p) {
                if let Err(e) = self.ctx.remove_node(&p).await {
                    debug!(path = %p, "sweep: {e}");
                }
            }
        }
    }

    async fn check_stuck(&mut self) {
        let long = self
            .inflight
            .as_ref()
            .is_some_and(|f| f.since.elapsed() >= STUCK_AFTER);
        if long && !self.stuck {
            self.stuck = true;
            warn!("no event completed for 30 s: the link is stuck");
            self.set_status(STUCK, Some("no event completed for 30 s".into()))
                .await;
        }
    }

    /// Root attributes `status` and `error`.
    async fn set_status(&mut self, status: &'static str, error: Option<String>) {
        let want = (status, error);
        if self.status.as_ref() == Some(&want) {
            return;
        }
        let Some(mut m) = self.ctx.meta("") else {
            return;
        };
        let attr = m.attr.get_or_insert_with(Default::default);
        attr.insert("status".into(), Value::Str(want.0.into()));
        match &want.1 {
            Some(e) => attr.insert("error".into(), Value::Str(e.clone())),
            None => attr.remove("error"),
        };
        if let Err(e) = self.ctx.declare_node("", m).await {
            debug!("root status: {e}");
            return;
        }
        self.status = Some(want);
    }

    /// Apply one event's commands in order (paths were checked by `conclude`). A new node over
    /// `max_nodes` fails the event.
    async fn apply(&mut self, cmds: Vec<Command>) -> Result<(), AppError> {
        for c in cmds {
            match c {
                Command::DeclareNode(p, m) => {
                    self.paths.admit(&p, self.max_nodes)?;
                    self.ctx.declare_node(&p, m).await.map_err(from_link)?;
                    self.paths.declared(p);
                }
                Command::DeclareAction(p, name, a) => {
                    self.ctx
                        .declare_action(&p, &name, a)
                        .await
                        .map_err(from_link)?;
                }
                Command::RemoveNode(p) => {
                    self.ctx.remove_node(&p).await.map_err(from_link)?;
                    self.paths.removed(&p);
                }
                Command::Update(p, s) => {
                    self.ctx
                        .update_sample(&p, s, None)
                        .await
                        .map_err(from_link)?;
                }
                Command::SetTimer(TimerId(id), ms) => {
                    let tx = self.internal.clone();
                    let t = tokio::spawn(async move {
                        tokio::time::sleep(Duration::from_millis(ms)).await;
                        let _ = tx.send(Internal::Timer(id));
                    });
                    self.timers.insert(id, t.abort_handle());
                }
                Command::CancelTimer(TimerId(id)) => {
                    if let Some(h) = self.timers.remove(&id) {
                        h.abort();
                    }
                    // fired while this event ran: not delivered any more
                    self.queue
                        .retain(|q| !matches!(q.ev, Event::Timer(TimerId(t)) if t == id));
                }
                // applied by the engine thread
                Command::StorePut(..) | Command::StoreDelete(_) => {}
                Command::Subscribe(SubId(id), key) => {
                    let (client, tx) = (self.client.clone(), self.internal.clone());
                    let t = tokio::spawn(async move {
                        let mut s = match client.subscribe(&key).await {
                            Ok(s) => s,
                            Err(e) => {
                                warn!(%key, "subscribe: {e}");
                                return;
                            }
                        };
                        while let Some(ev) = s.next().await {
                            if let ValEvent::Sample { key, sample, .. } = ev {
                                if tx.send(Internal::Value(id, key, sample)).is_err() {
                                    return;
                                }
                            }
                        }
                    });
                    self.subs.insert(id, t.abort_handle());
                }
                Command::Unsubscribe(SubId(id)) => {
                    if let Some(h) = self.subs.remove(&id) {
                        h.abort();
                    }
                    self.queue
                        .retain(|q| !matches!(q.ev, Event::Value(SubId(s), ..) if s == id));
                }
                Command::Set(ReqId(id), key, v) => {
                    let (client, tx) = (self.client.clone(), self.internal.clone());
                    let t = tokio::spawn(async move {
                        let r = client
                            .set(&key, v)
                            .await
                            .map(|()| Value::Null)
                            .map_err(from_client);
                        let _ = tx.send(Internal::Reply(id, r));
                    });
                    self.reqs.insert(id, t.abort_handle());
                }
                Command::Invoke(ReqId(id), key, action, args) => {
                    let (client, tx) = (self.client.clone(), self.internal.clone());
                    let t = tokio::spawn(async move {
                        let r = client
                            .invoke_one(&key, &action, args)
                            .await
                            .map(|v| v.unwrap_or(Value::Null))
                            .map_err(from_client);
                        let _ = tx.send(Internal::Reply(id, r));
                    });
                    self.reqs.insert(id, t.abort_handle());
                }
                Command::Log(level, msg) => match level {
                    Level::Error => error!(app = true, "{msg}"),
                    Level::Warn => warn!(app = true, "{msg}"),
                    Level::Info => info!(app = true, "{msg}"),
                    Level::Debug => debug!(app = true, "{msg}"),
                },
            }
        }
        Ok(())
    }

    /// Answer what waits, let the call in flight end, run the app's `stop` (each bounded), and
    /// end the engine thread. An engine that does not return is left behind (native: `stuck`),
    /// and the store refuses its late writes: a new instance on the same data directory may have
    /// read the store already.
    async fn stop(&mut self, outcomes: &mut mpsc::UnboundedReceiver<Outcome>) {
        for p in self.queue.drain(..) {
            answer(p.answer, Err(busy("the link is stopping")));
        }
        self.drop_tasks();
        let end = Instant::now() + STOP_WAIT;
        if let Some(f) = self.inflight.take() {
            match tokio::time::timeout_at(end, outcomes.recv()).await {
                // done: its store writes (if any) are in, its tree commands no longer apply
                Ok(Some(o)) => answer(f.answer, result_of(o)),
                _ => {
                    self.give_up(f, outcomes).await;
                    return;
                }
            }
            if f.start {
                self.state = State::Running;
            }
        }
        if matches!(self.state, State::Running) {
            self.seq += 1;
            let job = Job::Event(self.seq, Event::Stop, self.counts());
            if self.jobs.try_send(job).is_ok() {
                let seq = self.seq;
                if !matches!(
                    tokio::time::timeout_at(end, outcomes.recv()).await,
                    Ok(Some(_))
                ) {
                    let f = InFlight {
                        seq,
                        since: Instant::now(),
                        answer: None,
                        start: false,
                    };
                    self.give_up(f, outcomes).await;
                    return;
                }
            }
        }
        let _ = self.jobs.try_send(Job::Exit);
    }

    /// The call in flight did not end in time: the store refuses its writes from now on. When
    /// they were applied just before, its outcome is on the way and answers the caller;
    /// otherwise the caller gets `busy`.
    async fn give_up(&mut self, f: InFlight, outcomes: &mut mpsc::UnboundedReceiver<Outcome>) {
        let committed = lock(&self.store).abandon();
        if committed >= f.seq {
            match tokio::time::timeout(Duration::from_millis(500), outcomes.recv()).await {
                Ok(Some(o)) => answer(f.answer, result_of(o)),
                _ => answer(
                    f.answer,
                    Err(AppError::new(
                        Status::InternalError,
                        "the link stopped after the call's store writes",
                    )),
                ),
            }
        } else {
            warn!("the call in flight did not end in time; its store writes are refused");
            answer(f.answer, Err(busy("the link is stopping")));
        }
        let _ = self.jobs.try_send(Job::Exit);
    }
}

impl Drop for Actor {
    /// A runtime dropped without `stop` (its task aborted): nothing the engine thread finishes
    /// later reaches the store.
    fn drop(&mut self) {
        lock(&self.store).abandon();
    }
}

// ---------- the link ----------

/// A portable link on engine `E`. See the crate docs.
///
/// `E` is both the engine and its maker ([`MakeEngine`] with `E = Self`), which gives the link
/// its `NAME` and `VERSION` at compile time.
pub struct Runtime<E> {
    tx: mpsc::Sender<Input>,
    actor: tokio::task::JoinHandle<()>,
    _engine: PhantomData<fn() -> E>,
}

impl<E> Drop for Runtime<E> {
    fn drop(&mut self) {
        self.actor.abort();
    }
}

/// The verified caller as the app sees it.
fn who_of(c: &Caller) -> Who {
    Who {
        subject: c
            .origin
            .clone()
            .or_else(|| c.claims.as_ref().map(|cl| cl.sub.clone())),
        grants: c
            .claims
            .as_ref()
            .map(|cl| cl.grants.iter().map(|g| (g.k.clone(), g.p)).collect())
            .unwrap_or_default(),
    }
}

/// Requests leave signed with the link's requester key (ADR 0013), each `ptok` scoped to the
/// link's grants. Without a key they leave unsigned and the responder and the router decide.
fn client_of(ctx: &LinkCtx) -> WyrmClient {
    let client = WyrmClient::new(ctx.client().clone());
    match ctx.requester_key() {
        Some(key) => {
            let grants = ctx
                .grants()
                .iter()
                .map(|(p, perm)| Grant {
                    k: format!("{}/**", p.strip_suffix("/**").unwrap_or(p)),
                    p: *perm,
                })
                .collect();
            client.with_tokens(Arc::new(
                SigningTokens::new(key, ctx.site())
                    .subject(format!("link:{}", ctx.link()))
                    .grants(grants),
            ))
        }
        None => client,
    }
}

impl<E> Runtime<E> {
    async fn ask(&self, ev: Event) -> wyrm_link_sdk::Result<Option<Value>> {
        let (tx, rx) = oneshot::channel();
        if self.tx.try_send(Input::Request(ev, tx)).is_err() {
            return Err(LinkError::new(Status::Busy, "the link is busy"));
        }
        match rx.await {
            Ok(Ok(v)) => Ok(v),
            Ok(Err(e)) => Err(LinkError::new(e.status, e.msg)),
            Err(_) => Err(LinkError::new(Status::Busy, "the link is restarting")),
        }
    }
}

impl<E> Link for Runtime<E>
where
    E: Engine + MakeEngine<E = E>,
{
    const NAME: &'static str = <E as MakeEngine>::NAME;
    const VERSION: &'static str = <E as MakeEngine>::VERSION;
    type Config = PortableConfig;

    async fn start(cfg: PortableConfig, ctx: LinkCtx) -> wyrm_link_sdk::Result<Self> {
        let engine = E::make(&cfg, &ctx)?;
        let store: SharedStore = Arc::new(Mutex::new(Store::open(
            ctx.data_dir(),
            ctx.secrets().get(STORE_KEY).map(|s| s.expose()),
        )));
        let call: SharedCall = Arc::new(Mutex::new(CallState::default()));
        let services = RuntimeServices::new(
            store.clone(),
            ctx.grants().to_vec(),
            cfg.net.clone(),
            call.clone(),
        );
        let limits = Limits {
            store_bytes: u64::from(cfg.store_mb) * MIB,
            ..Limits::default()
        };
        let host = BufferHost::new(
            Box::new(services),
            limits.clone(),
            Counts::default(),
            1,
            format!("{}/{}", keyspace::ROOT, ctx.site()),
        );
        let actor_store = store.clone();
        let (jobs_tx, jobs_rx) = std::sync::mpsc::sync_channel(4);
        let (out_tx, out_rx) = mpsc::unbounded_channel();
        let call_time = Duration::from_millis(cfg.call_ms.into());
        std::thread::Builder::new()
            .name(format!("wyrm-link-{}", ctx.link()))
            .spawn(move || engine_thread(engine, host, store, call, call_time, jobs_rx, out_tx))
            .map_err(|e| LinkError::internal(format!("engine thread: {e}")))?;

        let (internal_tx, internal_rx) = mpsc::unbounded_channel();
        let actor = Actor {
            client: client_of(&ctx),
            ctx,
            params: cfg.params,
            jobs: jobs_tx,
            internal: internal_tx,
            state: State::Starting,
            queue: VecDeque::new(),
            inflight: None,
            timers: HashMap::new(),
            subs: HashMap::new(),
            reqs: HashMap::new(),
            paths: Paths::default(),
            max_nodes: limits.max_nodes,
            sweep_at: None,
            store: actor_store,
            seq: 0,
            backoff: BACKOFF_FIRST,
            started_at: None,
            stuck: false,
            status: None,
        };
        let (tx, inputs) = mpsc::channel(INPUTS);
        let (first_tx, first_rx) = oneshot::channel();
        let actor = tokio::spawn(
            actor
                .run(inputs, internal_rx, out_rx, first_tx)
                .instrument(tracing::Span::current()),
        );
        // The first `start` declares the tree before the link goes live. A failed one is not an
        // error here: the link is up, shows `restarting` and tries again.
        let _ = tokio::time::timeout(FIRST_START_WAIT, first_rx).await;
        Ok(Self {
            tx,
            actor,
            _engine: PhantomData,
        })
    }

    async fn on_set(
        &mut self,
        path: &str,
        value: Value,
        who: &Caller,
    ) -> wyrm_link_sdk::Result<()> {
        let ev = Event::Set {
            path: path.to_owned(),
            value,
            who: who_of(who),
        };
        self.ask(ev).await.map(|_| ())
    }

    async fn on_invoke(
        &mut self,
        path: &str,
        action: &str,
        args: Value,
        who: &Caller,
        out: ReplySink,
    ) -> wyrm_link_sdk::Result<()> {
        let ev = Event::Invoke {
            path: path.to_owned(),
            action: action.to_owned(),
            args,
            who: who_of(who),
        };
        let v = self.ask(ev).await?;
        out.reply(v.unwrap_or(Value::Null)).await
    }

    async fn stop(&mut self) {
        let (tx, rx) = oneshot::channel();
        if self.tx.send(Input::Stop(tx)).await.is_ok() {
            let _ = rx.await;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn jitter_stays_within_twenty_percent() {
        for _ in 0..200 {
            let d = jitter(Duration::from_secs(10));
            assert!(
                d >= Duration::from_secs(8) && d <= Duration::from_secs(12),
                "{d:?}"
            );
        }
    }

    #[test]
    fn node_cap_counts_new_paths_only_and_holds_across_a_restart() {
        let mut p = Paths::default();
        for n in ["a", "b"] {
            p.admit(n, 3).unwrap();
            p.declared(n.into());
        }
        // re-declares add nothing
        p.admit("a", 2).unwrap();
        p.declared("a".into());
        assert_eq!(p.len(), 2);
        assert_eq!(
            p.admit("c", 2).unwrap_err().status,
            Status::ResourceExhausted
        );
        // the instance dies: its nodes stay in the tree until the sweep
        p.fault();
        assert_eq!(p.len(), 2);
        // the new instance declares `a` again (no room needed) but no new path fits
        p.admit("a", 2).unwrap();
        p.declared("a".into());
        assert_eq!(p.len(), 2);
        assert!(p.admit("c", 2).is_err());
        // a second fault before the sweep: still two nodes, still no room
        p.fault();
        assert!(p.admit("c", 2).is_err());
        // the sweep frees what was not declared again
        p.declared("a".into());
        assert_eq!(p.take_sweep(), ["b"]);
        assert_eq!(p.len(), 1);
        p.admit("c", 2).unwrap();
    }

    #[test]
    fn sweep_keeps_parents_of_declared_nodes() {
        let mut p = Paths::default();
        for n in ["d", "d/x", "e"] {
            p.declared(n.into());
        }
        p.fault();
        p.declared("d/x".into());
        assert_eq!(p.take_sweep(), ["e"]);
        p.removed("d");
        assert_eq!(p.len(), 0);
    }

    fn buffer(dir: &std::path::Path) -> (BufferHost, SharedStore) {
        let store: SharedStore = Arc::new(Mutex::new(Store::open(Some(dir), Some(&[5; 32]))));
        let services = RuntimeServices::new(
            store.clone(),
            Vec::new(),
            Default::default(),
            Arc::new(Mutex::new(CallState::default())),
        );
        let host = BufferHost::new(
            Box::new(services),
            Limits::default(),
            Counts::default(),
            1,
            "wy/s".into(),
        );
        (host, store)
    }

    fn tmp(name: &str) -> std::path::PathBuf {
        let d =
            std::env::temp_dir().join(format!("wyrm-portable-rt-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        d
    }

    #[test]
    fn a_host_path_fails_the_event_before_the_store_changes() {
        use wyrm_link_api::Host;
        let d = tmp("paths");
        let (mut host, store) = buffer(&d);
        host.store_put("n", &[7]).unwrap();
        host.declare_node(".x", Default::default());
        let o = conclude(false, 1, Ok(Ok(None)), &mut host, &store);
        assert!(
            matches!(&o.result, Err(Failure::Apply(e)) if e.status == Status::InvalidParameter)
        );
        assert_eq!(lock(&store).get("n"), None);
        assert_eq!(Store::open(Some(&d), Some(&[5; 32])).get("n"), None);
        let _ = std::fs::remove_dir_all(&d);
    }

    #[test]
    fn an_abandoned_event_does_not_write_the_store() {
        use wyrm_link_api::Host;
        let d = tmp("abandoned");
        let (mut host, store) = buffer(&d);
        host.store_put("n", &[1]).unwrap();
        let o = conclude(false, 1, Ok(Ok(None)), &mut host, &store);
        assert!(o.result.is_ok());
        assert_eq!(lock(&store).abandon(), 1);
        host.store_put("n", &[2]).unwrap();
        let o = conclude(false, 2, Ok(Ok(None)), &mut host, &store);
        assert!(matches!(&o.result, Err(Failure::Apply(e)) if e.status == Status::Busy));
        assert_eq!(
            Store::open(Some(&d), Some(&[5; 32])).get("n").as_deref(),
            Some(&[1u8][..])
        );
        let _ = std::fs::remove_dir_all(&d);
    }

    #[test]
    fn host_paths_are_refused() {
        assert!(check_path("", false).is_err());
        assert!(check_path("", true).is_ok());
        assert!(check_path(".x", true).is_err());
        assert!(check_path("a/.b", false).is_err());
        assert!(check_path("a/b", false).is_ok());
    }
}
