//! [`Framework`]: a [`Link`] that runs any [`Driver`].
//!
//! Tree: `<conn>/<dev>/<point>`, shaped like the DSA driver framework;
//! with [`Driver::FOLDERS`], `<conn>/<dev>/<f1>/…/<point>` (folders at most
//! [`MAX_FOLDER_DEPTH`] deep, names only: `add_folder` and `remove`). A
//! point's id stays unique on its device, so polls, plans and writes go by
//! `(device, id)` and never see folders.
//! Connections and devices have a `status` enum leaf (Unknown, Connecting,
//! Connected, Failed, Stopped, Stopped by Parent; spec 03 gives containers
//! no `~val`) and an `error` leaf that exists only while there is an error.
//! Actions carry a name for people and a menu group (spec 02): `add_*`
//! (group `new`, one per node kind of the level below), `edit` and `remove`
//! (group `edit`), `restart`, and `stop` or `start`, whichever applies.
//!
//! * One owner task per connection holds the transport and serves `Poll`,
//!   `Ping`, `Write` and `Invoke` requests in order, each against the
//!   current plan generation: a request planned before a re-plan is dropped
//!   (a write or action answers `busy`), never run on what replaced it.
//! * One ticker per `(device, poll period)` group; a tick is skipped while
//!   the previous poll of that group is in flight. Points are polled all the
//!   time (owner decision, ADR 0004 amendment); with `poll_unsubscribed:
//!   false` a tick is also skipped while no point of the group has a
//!   subscriber (only reliable for process links: the in-process `~val`
//!   storage of `wyrmd` always counts as one).
//! * Edits validate first (atomic), then rebuild only what depends on them:
//!   a connection edit tears the owner down completely before the new one
//!   starts; device and point edits re-plan without reconnecting.
//! * A config that fails validation at load keeps its node (`Failed`,
//!   error shown) and stays editable; nothing is deleted.
//! * A poll is bounded by [`Driver::poll_timeout`] and a write by
//!   [`Driver::write_timeout`] (both may take many requests), a ping by
//!   [`Driver::io_timeout`]. A value is published on a change, and again
//!   when unchanged once its last sample is [`Driver::republish`] old.
//!   After a write the point is read back; after a failed one only when
//!   [`Driver::read_back_on_error`] says so.
//! * Driver actions ([`Driver::actions`]) are declared on connections and
//!   devices and run on the owner task ([`Driver::invoke`]), between polls;
//!   the link task does not wait for them.
//! * With [`Driver::DIAGNOSTICS`], connections and devices get diagnostics
//!   value leaves (see `diag`), counted from [`Driver::take_outcomes`] after
//!   every operation; an operation cut by its bound counts one timeout.
//! * Branches (ruling 11, format in `branch`): `copy {name}` on connections,
//!   devices, folders and points (beside the source; a copied connection or
//!   device starts stopped; the sealed secrets go with it, as the
//!   destination is the same); `export` of a connection, device or folder;
//!   `import {json, name?, overwrite?}` of a connection at the root, a
//!   device into a connection, a folder into a device or folder. An import
//!   never takes secrets: they are entered again with `edit`.
//! * Root imports ([`Driver::root_imports`]): the driver turns another
//!   system's export into connection branches ([`Driver::convert`]); the
//!   framework checks them all, then imports each like `import` at the root.
//! * Server kinds ([`Driver::is_server`], ADR 0024): no tickers; every
//!   point takes `~set`, written into what the server serves and published
//!   from it ([`Driver::take_changed`]); the owner hands each plan to the
//!   server ([`Driver::serve`], a re-plan wakes it) and applies the remote
//!   side's requests ([`Driver::remote`]) in the same order as the sets.

use super::branch::{self, Node};
use super::diag;
use super::params::{all_secret_names, normalize, Kind, ParamSpec, Params};
use super::persist::Persist;
use super::{
    backoff, jitter, Converted, Driver, DriverError, Level, NodeState, Outcome, PointId, Served,
    Target, REPORT_KEYS,
};
use crate::auth::Caller;
use crate::ctx::{now_us, LinkCtx, PointPublisher};
use crate::error::{LinkError, Result};
use crate::link::{Link, ReplySink};
use crate::params::FromParams;
use std::collections::{BTreeMap, BTreeSet};
use std::sync::atomic::{AtomicBool, AtomicU8, Ordering};
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::{mpsc, oneshot, watch};
use tokio::task::JoinHandle;
use tracing::Instrument;
use tracing::{debug, error, warn};
use wyrm_core::meta::{ActionResult, ParamMeta, Writable, EDITOR_TEXTAREA, GROUP_EDIT, GROUP_NEW};
use wyrm_core::{ActionMeta, NodeMeta, Perm, Quality, Sample, Status, TypeCode, Value};

/// A new run token: a device gets one when it is added, edited, started or
/// restarted, so the owner forgets what it knew of the device before.
fn run_token() -> u64 {
    static NEXT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(1);
    NEXT.fetch_add(1, Ordering::Relaxed)
}

/// How deep folders nest below a device ([`Driver::FOLDERS`]).
pub const MAX_FOLDER_DEPTH: usize = 4;

pub const QUAL_STALE: &str = "uncertain/stale";
pub const QUAL_COMM_FAIL: &str = "bad/comm_fail";
pub const QUAL_DISCONNECTED: &str = "bad/disconnected";
pub const QUAL_DEVICE_ERROR: &str = "bad/device_error";
pub const QUAL_CONFIG_ERROR: &str = "bad/config_error";

/// Name of the status leaf under connections and devices (reserved).
pub const STATUS: &str = "status";
/// Name of the error leaf beside `status`; it exists only while there is
/// an error (reserved).
pub const ERROR: &str = "error";

/// Bootstrap tree (`~def.params`):
/// `{poll_unsubscribed?, connections: {<c>: {..Conn, kind?, enabled?, devices:
/// {<d>: {..Dev, kind?, enabled?, points: {<p>: {..Point, kind?}}, folders?:
/// {<f>: {points, folders?}}}}}}}`.
/// `kind` names the node kind on levels with several (default: the first).
/// `folders` only with [`Driver::FOLDERS`]; a tree is written without the
/// key where a level has no folders (as before folders).
#[derive(Debug, Clone, PartialEq)]
pub struct Tree(pub Value);

impl FromParams for Tree {
    fn from_params(v: &Value) -> Result<Self> {
        match v {
            Value::Map(_) | Value::Null => Ok(Tree(v.clone())),
            _ => Err(LinkError::invalid_parameter("params must be a map")),
        }
    }
}

type Map = BTreeMap<String, Value>;

fn map_of(v: &Value) -> Map {
    match v {
        Value::Map(m) => m.clone(),
        _ => Map::new(),
    }
}

/// A node config: typed when valid, raw (with the error) when not.
#[derive(Debug, Clone)]
struct Slot<P: Params> {
    cfg: Option<P>,
    /// The params as given, without `kind`.
    raw: Value,
    /// The node kind (`""` on a single-kind level).
    kind: String,
    error: Option<String>,
}

/// A level with several node kinds stores and shows `kind`.
fn multi_kind<P: Params>() -> bool {
    P::kinds().len() > 1
}

impl<P: Params> Slot<P> {
    fn parse(raw: Value) -> Self {
        // `kind` is structural only on levels with several kinds (their
        // params may not use that name); elsewhere it is a driver param.
        let mut m = map_of(&raw);
        let given = match multi_kind::<P>().then(|| m.remove("kind")).flatten() {
            Some(Value::Str(k)) => k,
            _ => String::new(),
        };
        let raw = Value::Map(m);
        match P::from_kind_value(&given, &raw) {
            Ok(cfg) => Self {
                kind: cfg.kind().to_owned(),
                cfg: Some(cfg),
                raw,
                error: None,
            },
            Err(e) => Self {
                kind: if given.is_empty() {
                    P::kinds().first().map(|k| k.id).unwrap_or("").to_owned()
                } else {
                    given
                },
                cfg: None,
                raw,
                error: Some(e.message),
            },
        }
    }

    fn valid(cfg: P) -> Self {
        Self {
            raw: cfg.to_value(),
            kind: cfg.kind().to_owned(),
            cfg: Some(cfg),
            error: None,
        }
    }

    /// The parameters of this node's kind.
    fn schema(&self) -> Vec<ParamSpec> {
        P::kind_schema(&self.kind).unwrap_or_default()
    }

    /// Values shown in `~meta.cfg` and pre-filled in `edit`.
    fn shown(&self) -> Map {
        let mut m = match &self.cfg {
            Some(c) => c.public_map(),
            None => {
                // An invalid config (possibly of an unknown kind): leave out
                // the secrets of every kind of the level.
                let secret = super::params::all_secret_names::<P>();
                let mut m = map_of(&self.raw);
                m.retain(|k, _| !secret.contains(&k.as_str()));
                m
            }
        };
        if multi_kind::<P>() {
            m.insert("kind".into(), Value::Str(self.kind.clone()));
        }
        m
    }

    /// The params with secrets and `kind` (the sealed tree only).
    fn stored(&self) -> Map {
        let mut m = map_of(&self.raw);
        if multi_kind::<P>() {
            m.insert("kind".into(), Value::Str(self.kind.clone()));
        }
        m
    }

    /// The params of a branch export: as shown, and each secret that has a
    /// value as [`branch::NOT_EXPORTED`].
    fn exported(&self) -> Map {
        let mut m = self.shown();
        let raw = map_of(&self.raw);
        let secret = match &self.cfg {
            Some(_) => self
                .schema()
                .into_iter()
                .filter(|s| s.secret)
                .map(|s| s.name)
                .collect(),
            None => all_secret_names::<P>(),
        };
        for name in secret {
            if raw.get(name).is_some_and(|v| !blank(v)) {
                m.insert(name.into(), Value::Str(branch::NOT_EXPORTED.into()));
            }
        }
        m
    }

    /// An imported node whose required secret was left out does not load:
    /// say how to fix it.
    fn note_reenter(&mut self, at: &str, reenter: &[String]) {
        let missing = reenter
            .iter()
            .any(|r| r.rsplit_once('.').is_some_and(|(node, _)| node == at));
        if let (Some(e), true) = (&mut self.error, missing) {
            e.push_str(" (secrets are not imported: enter them again with edit)");
        }
    }
}

/// An empty value (no secret given).
fn blank(v: &Value) -> bool {
    match v {
        Value::Null => true,
        Value::Str(s) => s.is_empty(),
        _ => false,
    }
}

/// A folder's path below its device (empty: the device itself).
type Folder = Vec<String>;

/// `folder` with `name` below it.
fn child(folder: &[String], name: &str) -> Folder {
    let mut f = folder.to_vec();
    f.push(name.to_owned());
    f
}

/// The key of `folder` below `base`.
fn below(base: &str, folder: &[String]) -> String {
    if folder.is_empty() {
        base.to_owned()
    } else {
        format!("{base}/{}", folder.join("/"))
    }
}

/// A point and the folder it is in.
#[derive(Clone)]
struct PointEntry<P: Params> {
    slot: Slot<P>,
    folder: Folder,
}

struct DevEntry<D: Driver> {
    slot: Slot<D::Dev>,
    enabled: bool,
    /// See [`run_token`].
    token: u64,
    /// Every point of the device by id (unique across its folders).
    points: BTreeMap<String, PointEntry<D::Point>>,
    /// Every folder (a parent sorts before its children).
    folders: BTreeSet<Folder>,
}

impl<D: Driver> Clone for DevEntry<D> {
    fn clone(&self) -> Self {
        Self {
            slot: self.slot.clone(),
            enabled: self.enabled,
            token: run_token(),
            points: self.points.clone(),
            folders: self.folders.clone(),
        }
    }
}

impl<D: Driver> DevEntry<D> {
    /// The key of point `id` below the device: `<f1>/…/<id>`.
    fn rel(&self, id: &str) -> String {
        match self.points.get(id) {
            Some(p) => child(&p.folder, id).join("/"),
            None => id.to_owned(),
        }
    }

    /// `folder` has a child (point or folder) named `name`.
    fn taken(&self, folder: &[String], name: &str) -> bool {
        self.points.get(name).is_some_and(|p| p.folder == folder)
            || self.folders.contains(&child(folder, name))
    }

    /// `{points, folders?}` of `folder`, each point as `show` gives it;
    /// `folders` only where there are some.
    fn branch(&self, folder: &[String], show: &impl Fn(&Slot<D::Point>) -> Map) -> Map {
        let pts: Map = self
            .points
            .iter()
            .filter(|(_, p)| p.folder == folder)
            .map(|(n, p)| (n.clone(), Value::Map(show(&p.slot))))
            .collect();
        let subs: Map = self
            .folders
            .iter()
            .filter(|f| f.len() == folder.len() + 1 && f.starts_with(folder))
            .map(|f| (f[folder.len()].clone(), Value::Map(self.branch(f, show))))
            .collect();
        let mut m = Map::new();
        m.insert("points".into(), Value::Map(pts));
        if !subs.is_empty() {
            m.insert("folders".into(), Value::Map(subs));
        }
        m
    }

    /// The device, its folders and points.
    fn count(&self) -> usize {
        1 + self.folders.len() + self.points.len()
    }

    /// The device as a branch node.
    fn node(&self, name: &str) -> Node {
        Node {
            level: branch::Level::Device,
            name: name.to_owned(),
            params: self.slot.exported(),
            enabled: self.enabled,
            children: self.children(&[]),
        }
    }

    /// The branch nodes of `folder`'s children: folders, then points.
    fn children(&self, folder: &[String]) -> Vec<Node> {
        let subs = self
            .folders
            .iter()
            .filter(|f| f.len() == folder.len() + 1 && f.starts_with(folder))
            .map(|f| Node {
                level: branch::Level::Folder,
                name: f[folder.len()].clone(),
                params: Map::new(),
                enabled: true,
                children: self.children(f),
            });
        let pts = self
            .points
            .iter()
            .filter(|(_, p)| p.folder == folder)
            .map(|(n, p)| Node {
                level: branch::Level::Point,
                name: n.clone(),
                params: p.slot.exported(),
                enabled: true,
                children: Vec::new(),
            });
        subs.chain(pts).collect()
    }
}

struct ConnEntry<D: Driver> {
    slot: Slot<D::Conn>,
    enabled: bool,
    devices: BTreeMap<String, DevEntry<D>>,
    run: Option<ConnRun<D>>,
}

impl<D: Driver> ConnEntry<D> {
    /// A connection of a server kind ([`Driver::is_server`]); an invalid
    /// config is not one (it does not run).
    fn server(&self) -> bool {
        self.slot.cfg.as_ref().is_some_and(D::is_server)
    }

    /// The connection as a branch node.
    fn node(&self, name: &str) -> Node {
        Node {
            level: branch::Level::Connection,
            name: name.to_owned(),
            params: self.slot.exported(),
            enabled: self.enabled,
            children: self.devices.iter().map(|(n, d)| d.node(n)).collect(),
        }
    }
}

/// One poll group of a device.
struct Group<D: Driver> {
    period: Duration,
    ids: Vec<PointId>,
    plan: Arc<D::Plan>,
    /// Its poll request: [`POLL_IDLE`], [`POLL_QUEUED`] or [`POLL_RUNNING`].
    inflight: Arc<AtomicU8>,
}

/// No poll of the group is queued or running.
const POLL_IDLE: u8 = 0;
/// A poll of the group waits in the owner's queue.
const POLL_QUEUED: u8 = 1;
/// The owner took the poll and runs it.
const POLL_RUNNING: u8 = 2;

/// What the owner task needs about one device.
struct DevRun<D: Driver> {
    cfg: D::Dev,
    /// The device's run token ([`run_token`]).
    token: u64,
    points: BTreeMap<PointId, D::Point>,
    /// The node key of each point (folders included).
    paths: BTreeMap<PointId, String>,
    groups: Vec<Group<D>>,
}

type DevMap<D> = BTreeMap<String, DevRun<D>>;

/// The devices of a running connection as planned, with the generation of
/// that plan (ruling P19). The link task replaces it on every re-plan
/// (under the write lock). The owner reads it before every request and
/// drops a request of an older generation before it starts (a write or
/// action answers `busy`). I/O already started is not interrupted: a poll
/// or ping runs to its end, and a write that passed the check is sent. Its
/// results, the read-back and every device status are published under the
/// read lock, and only while their generation is still current. So once a
/// re-plan returns, nothing of the old plan publishes any more.
struct View<D: Driver> {
    gen: u64,
    devs: Arc<DevMap<D>>,
    /// When this plan began: a server's remote request received before it
    /// was asked of an older plan ([`Driver::apply_remote`]).
    since: tokio::time::Instant,
}

type SharedView<D> = Arc<tokio::sync::RwLock<View<D>>>;

enum Req {
    Poll {
        dev: String,
        group: usize,
        /// The plan generation the ticker was started for.
        gen: u64,
        /// The group's state: [`POLL_RUNNING`] once the owner takes the
        /// poll, [`POLL_IDLE`] once it ran or was dropped.
        inflight: Arc<AtomicU8>,
    },
    Ping {
        dev: String,
        gen: u64,
        /// The device's ping flag: one ping queued or running at a time.
        inflight: Arc<AtomicBool>,
    },
    Write {
        dev: String,
        point: String,
        value: Value,
        /// The plan generation when the set came: after a re-plan the write
        /// is refused (`busy`), never sent with what replaced the point.
        gen: u64,
        /// When the caller stops waiting (the SDK's bound on the set): a
        /// write still queued then is dropped, never sent late (P13).
        deadline: tokio::time::Instant,
        reply: oneshot::Sender<Result<()>>,
    },
    /// A driver action on the connection (`dev: None`) or a device.
    Invoke {
        dev: Option<String>,
        action: String,
        args: Value,
        /// The plan generation when the call came: after a re-plan the
        /// action answers `busy`, never runs on what replaced its node.
        gen: u64,
        /// The action's `timeout_ms`; `None` = [`Driver::io_timeout`].
        bound: Option<Duration>,
        /// When the caller stops waiting: the action never runs past it.
        deadline: tokio::time::Instant,
        reply: ActionReply,
    },
    /// A server connection was re-planned: hand the new plan to the server
    /// ([`Driver::serve`]).
    Serve,
}

/// The connection's action slot ([`ConnRun::acting`]): free.
const SLOT_FREE: u8 = 0;
/// A `read` action holds the slot (one bounded request, ruling P32): a set
/// still queues behind it.
const SLOT_READ: u8 = 1;
/// A `write` or `config` action holds the slot (a scan may take minutes):
/// a set answers `busy`.
const SLOT_HOLD: u8 = 2;

/// The answer to a driver action. It frees the connection's action slot
/// ([`ConnRun::acting`]) just before it answers, or when it is dropped
/// unanswered (the request was dropped, the owner ended): one driver
/// action queued or running per connection (final review I1).
struct ActionReply {
    tx: Option<oneshot::Sender<Result<Value>>>,
    slot: Arc<AtomicU8>,
}

impl ActionReply {
    fn send(mut self, r: Result<Value>) -> std::result::Result<(), Result<Value>> {
        self.slot.store(SLOT_FREE, Ordering::Release);
        match self.tx.take() {
            Some(tx) => tx.send(r),
            None => Err(r),
        }
    }
}

impl Drop for ActionReply {
    fn drop(&mut self) {
        // Only when unanswered: once answered, the slot may already hold
        // the caller's next action.
        if self.tx.is_some() {
            self.slot.store(SLOT_FREE, Ordering::Release);
        }
    }
}

/// A driver action found on a node ([`Framework::find_action`]).
struct FoundAction {
    conn: String,
    dev: Option<String>,
    timeout_ms: Option<u32>,
    /// What it holds the action slot as: [`SLOT_READ`] or [`SLOT_HOLD`].
    slot: u8,
}

/// The shown [`Driver::status_note`] of a running connection, kept for a
/// new declaration of its `status` leaf (`rescan`).
type NoteSlot = Arc<tokio::sync::Mutex<Option<String>>>;

struct ConnRun<D: Driver> {
    tx: mpsc::Sender<Req>,
    /// The action slot: [`SLOT_FREE`], or the level of the driver action
    /// queued or running ([`SLOT_READ`], [`SLOT_HOLD`]). Another action
    /// answers `busy` at once (final review I1); a set does while a
    /// [`SLOT_HOLD`] action holds it (I2, P32).
    acting: Arc<AtomicU8>,
    /// The note its owner shows on the `status` leaf.
    note: NoteSlot,
    /// The plan the owner serves ([`View`]) and its generation.
    view: SharedView<D>,
    gen: u64,
    stop: watch::Sender<bool>,
    owner: JoinHandle<()>,
    tickers: Vec<JoinHandle<()>>,
    tick_stop: watch::Sender<bool>,
    /// Diagnostics of this run (empty at every (re)start).
    book: diag::SharedBook,
    /// The diagnostics flusher and its nudges ([`Driver::DIAGNOSTICS`]).
    flusher: Option<(JoinHandle<()>, diag::Nudge)>,
}

pub struct Framework<D: Driver> {
    ctx: LinkCtx,
    conns: BTreeMap<String, ConnEntry<D>>,
    poll_unsubscribed: bool,
    /// The sealed copy of the tree in `data_dir` (see `persist`).
    persist: Option<Persist>,
}

fn status_path(base: &str) -> String {
    format!("{base}/{STATUS}")
}

fn error_path(base: &str) -> String {
    format!("{base}/{ERROR}")
}

/// The `status` leaf: an enum of [`NodeState::LABELS`].
fn status_meta() -> NodeMeta {
    NodeMeta::leaf(TypeCode::Enum)
        .is("wy:df-status")
        .enum_values(NodeState::LABELS)
}

/// The `status` leaf with a [`Driver::status_note`] as `attr.warning`.
fn status_with(note: Option<&str>) -> NodeMeta {
    match note {
        Some(n) => status_meta().attr("warning", n),
        None => status_meta(),
    }
}

/// Publish the state; declare the `error` leaf while there is an error and
/// remove it when the error clears (DSA shows its `Error` the same way).
async fn set_status(ctx: &LinkCtx, base: &str, state: NodeState, error: Option<&str>) {
    let _ = ctx
        .update(
            &status_path(base),
            Value::UInt(state as u64),
            Quality::Good,
            now_us(),
        )
        .await;
    let ep = error_path(base);
    match error {
        Some(e) => {
            if !ctx.has_node(&ep) {
                let meta = NodeMeta::leaf(TypeCode::String).is("wy:df-error");
                if ctx.declare_node(&ep, meta).await.is_err() {
                    return;
                }
            }
            let _ = ctx
                .update(&ep, Value::Str(e.into()), Quality::Good, now_us())
                .await;
        }
        None => {
            if ctx.has_node(&ep) {
                let _ = ctx.remove_node(&ep).await;
            }
        }
    }
}

/// Publish a point value when it or its quality changed, or (heartbeat,
/// [`Driver::republish`]) when the last sample is at least `republish` old.
async fn put_point(
    ctx: &LinkCtx,
    path: &str,
    v: Value,
    q: Quality,
    qual: Option<&str>,
    republish: Option<Duration>,
) {
    let fresh = |t: u64| {
        republish.is_none_or(|d| {
            now_us().saturating_sub(t) < u64::try_from(d.as_micros()).unwrap_or(u64::MAX)
        })
    };
    if ctx
        .last(path)
        .is_some_and(|s| s.v == v && s.q == q && fresh(s.t))
    {
        return;
    }
    let _ = ctx
        .update_sample(path, Sample { v, q, t: now_us() }, qual)
        .await;
}

/// Re-publish the last values of `paths` with quality `q` (value kept).
async fn mark(ctx: &LinkCtx, paths: impl IntoIterator<Item = String>, q: Quality, qual: &str) {
    for p in paths {
        if let Some(s) = ctx.last(&p) {
            if s.q != q {
                let _ = ctx
                    .update_sample(
                        &p,
                        Sample {
                            v: s.v,
                            q,
                            t: now_us(),
                        },
                        Some(qual),
                    )
                    .await;
            }
        }
    }
}

/// `uncertain/stale` for those of `paths` whose last sample is good (value
/// kept): a point never goes up in quality without an answer (final review
/// M1), so a `bad` point stays `bad`.
async fn mark_stale(ctx: &LinkCtx, paths: impl IntoIterator<Item = String>) {
    for p in paths {
        if let Some(s) = ctx.last(&p) {
            if s.q == Quality::Good {
                let stale = Sample {
                    v: s.v,
                    q: Quality::Uncertain,
                    t: now_us(),
                };
                let _ = ctx.update_sample(&p, stale, Some(QUAL_STALE)).await;
            }
        }
    }
}

/// Actions of the framework; a driver action may not use these names.
const FRAMEWORK_ACTIONS: [&str; 9] = [
    "edit", "remove", "restart", "start", "stop", "export", "rescan", "copy", "import",
];

fn framework_action(name: &str) -> bool {
    name.starts_with("add_") || FRAMEWORK_ACTIONS.contains(&name)
}

/// The names a driver that names imported nodes (a root import) should
/// keep clear of, besides those starting with `add_`: the `status` and
/// `error` leaves, the diagnostics leaves and the framework's action names.
/// The add path refuses fewer (final review M7): `status` and `error`
/// everywhere, the diagnostics leaves for devices, points and folders, and
/// the action names (and `add_*`) for folders only. No key would clash
/// (actions live under `~act/`); the list is the widest set, so a name
/// taken from it fits any level.
pub fn reserved_names<D: Driver>() -> Vec<&'static str> {
    let mut v = vec![STATUS, ERROR];
    if D::DIAGNOSTICS {
        v.extend(diag::names::<D>());
    }
    v.extend(FRAMEWORK_ACTIONS);
    v
}

/// [`Driver::actions`] (of a server connection and its devices:
/// [`Driver::server_actions`]) without names of the framework; level
/// `config` when the driver left it out.
fn driver_actions<D: Driver>(
    server: bool,
    level: Level,
    kind: &str,
) -> Vec<(&'static str, ActionMeta)> {
    let declared = if server {
        D::server_actions(level, kind)
    } else {
        D::actions(level, kind)
    };
    declared
        .into_iter()
        .filter(|(name, _)| {
            let ok = !framework_action(name);
            if !ok {
                warn!("driver action {name:?} has the name of a framework action; not declared");
            }
            ok
        })
        .map(|(name, mut meta)| {
            meta.level.get_or_insert(Perm::Config);
            (name, meta)
        })
        .collect()
}

/// [`Driver::root_imports`] without names of the framework; level `config`
/// and the bound of `import` when the driver left them out.
fn root_imports<D: Driver>() -> Vec<(&'static str, ActionMeta)> {
    D::root_imports()
        .into_iter()
        .filter(|(name, _)| {
            let ok = !framework_action(name);
            if !ok {
                warn!("root import {name:?} has the name of a framework action; not declared");
            }
            ok
        })
        .map(|(name, mut meta)| {
            meta.level.get_or_insert(Perm::Config);
            meta.timeout_ms.get_or_insert(branch::ACTION_MS);
            (name, meta)
        })
        .collect()
}

/// The action that adds a folder ([`Driver::FOLDERS`]).
const ADD_FOLDER: &str = "add_folder";

/// Names a new device, folder or point may not take: the diagnostics leaves.
fn diag_reserved<D: Driver>(name: &str) -> Result<()> {
    if D::DIAGNOSTICS && diag::names::<D>().contains(&name) {
        return Err(LinkError::invalid_parameter(format!(
            "{name:?} is reserved (diagnostics)"
        )));
    }
    Ok(())
}

/// A new folder's name: no diagnostics leaf, no action name of the framework.
fn folder_name<D: Driver>(name: &str) -> Result<()> {
    diag_reserved::<D>(name)?;
    if framework_action(name) {
        return Err(LinkError::invalid_parameter(format!(
            "{name:?} is reserved (action name)"
        )));
    }
    Ok(())
}

fn valid_name(name: &str) -> Result<()> {
    wyrm_core::keyspace::validate_segment(name)?;
    if name == STATUS || name == ERROR {
        return Err(LinkError::invalid_parameter(format!(
            "{name:?} is reserved"
        )));
    }
    Ok(())
}

/// `ip_connection` → `Ip Connection`.
fn title(id: &str) -> String {
    id.split('_')
        .filter(|w| !w.is_empty())
        .map(|w| {
            let mut c = w.chars();
            c.next()
                .map(|f| f.to_uppercase().collect::<String>() + c.as_str())
                .unwrap_or_default()
        })
        .collect::<Vec<_>>()
        .join(" ")
}

/// The add actions of a level: `(action, kind, name for people)`. One kind:
/// `add_<noun>`; several: `add_<kind id>`.
fn adds<P: Params>(noun: &str) -> Vec<(String, Kind)> {
    let kinds = P::kinds();
    if kinds.len() == 1 {
        return kinds
            .into_iter()
            .map(|k| (format!("add_{noun}"), k))
            .collect();
    }
    kinds
        .into_iter()
        .map(|k| (format!("add_{}", k.id), k))
        .collect()
}

/// The name for people of an add action.
fn add_display(noun: &str, k: &Kind) -> String {
    if k.display.is_empty() {
        format!("Add {}", title(if k.id.is_empty() { noun } else { k.id }))
    } else {
        format!("Add {}", k.display)
    }
}

/// A plain action of the framework (no params, `config`).
fn plain(display: &str) -> ActionMeta {
    ActionMeta::new().level(Perm::Config).display(display)
}

fn form<D: Driver>(schema: &[ParamSpec], prefill: Option<&Map>) -> ActionMeta {
    let mut a = ActionMeta::new().level(Perm::Config);
    for s in schema {
        let mut p = s.param_meta(prefill.and_then(|m| m.get(s.name)));
        if prefill.is_some() && s.secret {
            // `edit`: an empty secret keeps the stored one.
            p.required = Some(false);
        }
        let found = D::choices(s.name);
        if let Some(first) = found.first() {
            p.placeholder = Some(first.clone());
            let list = format!("Found: {}", found.join(", "));
            p.description = Some(match p.description.take() {
                Some(d) => format!("{d}. {list}"),
                None => list,
            });
        }
        a = a.param(s.name, p);
    }
    a
}

/// `edit` args with the stored secrets of `old` filled in where `new`
/// leaves them out or empty, but only while the destination (the `dest`
/// fields, or every field when none is marked) stays the same: a caller
/// with `config` must not point a stored password at another host.
fn keep_secrets(schema: &[ParamSpec], old: &Value, new: &Value) -> Value {
    let missing = |m: &Map, n: &str| match m.get(n) {
        None | Some(Value::Null) => true,
        Some(Value::Str(s)) => s.is_empty(),
        _ => false,
    };
    let old_m = map_of(old);
    let mut cand = map_of(new);
    let mut kept = Vec::new();
    for s in schema.iter().filter(|s| s.secret) {
        if missing(&cand, s.name) {
            cand.remove(s.name);
            if !missing(&old_m, s.name) {
                cand.insert(s.name.to_owned(), old_m[s.name].clone());
                kept.push(s.name);
            }
        }
    }
    if kept.is_empty() {
        return Value::Map(cand);
    }
    let any_dest = schema.iter().any(|s| s.dest);
    let same = match (
        normalize(schema, old),
        normalize(schema, &Value::Map(cand.clone())),
    ) {
        (Ok(o), Ok(n)) => schema
            .iter()
            .filter(|s| !s.secret && (s.dest || !any_dest))
            .all(|s| o.get(s.name) == n.get(s.name)),
        _ => false,
    };
    if !same {
        for k in kept {
            cand.remove(k);
        }
    }
    Value::Map(cand)
}

fn add_form<D: Driver>(schema: &[ParamSpec], display: String) -> ActionMeta {
    form::<D>(schema, None)
        .param(
            "name",
            wyrm_core::meta::ParamMeta::of(TypeCode::String)
                .required(true)
                .display("Name"),
        )
        .display(display)
        .group(GROUP_NEW)
}

/// `copy {name}`: the node with everything below it, beside it.
fn copy_form() -> ActionMeta {
    ActionMeta::new()
        .level(Perm::Config)
        .param(
            "name",
            ParamMeta::of(TypeCode::String)
                .required(true)
                .display("Name"),
        )
        .display("Copy")
        .group(GROUP_EDIT)
        .timeout_ms(branch::ACTION_MS)
        .result(ActionResult::Type(TypeCode::Map))
}

/// `export` of a branch: `{json}`.
fn export_form() -> ActionMeta {
    plain("Export").result(ActionResult::Type(TypeCode::Map))
}

/// `import {json, name?, overwrite?}`: `{name, reenter}`.
fn import_form() -> ActionMeta {
    let mut overwrite = ParamMeta::of(TypeCode::Bool)
        .required(false)
        .display("Overwrite")
        .description("Replace a node of that name");
    overwrite.default = Some(Value::Bool(false));
    plain("Import")
        .param(
            "json",
            ParamMeta::of(TypeCode::String)
                .required(true)
                .display("JSON")
                .editor(EDITOR_TEXTAREA)
                .description("A branch from Export (secrets are entered again with Edit)"),
        )
        .param(
            "name",
            ParamMeta::of(TypeCode::String)
                .required(false)
                .display("Name")
                .description("Default: the exported name"),
        )
        .param("overwrite", overwrite)
        .timeout_ms(branch::ACTION_MS)
        .result(ActionResult::Type(TypeCode::Map))
}

/// Split `{name, ..params}` action args.
fn split_name(args: &Value) -> Result<(String, Value)> {
    let mut m = map_of(args);
    let name = match m.remove("name") {
        Some(Value::Str(s)) => s,
        _ => return Err(LinkError::invalid_parameter("name: required")),
    };
    valid_name(&name)?;
    Ok((name, Value::Map(m)))
}

/// Remove structural keys from a node config map.
fn take(m: &mut Map, key: &str) -> Option<Value> {
    m.remove(key)
}

fn is_enabled(m: &mut Map) -> bool {
    !matches!(take(m, "enabled"), Some(Value::Bool(false)))
}

impl<D: Driver> Framework<D> {
    fn point_paths(conn: &str, dev: &str, d: &DevEntry<D>) -> Vec<String> {
        d.points
            .keys()
            .map(|p| format!("{conn}/{dev}/{}", d.rel(p)))
            .collect()
    }

    fn conn_point_paths(name: &str, c: &ConnEntry<D>) -> Vec<String> {
        c.devices
            .iter()
            .flat_map(|(d, e)| Self::point_paths(name, d, e))
            .collect()
    }

    async fn declare_conn(&self, name: &str) -> Result<()> {
        let c = &self.conns[name];
        let shown = c.slot.shown();
        let mut meta = NodeMeta::folder().is("wy:df-connection");
        meta.cfg = Some(shown.clone());
        self.ctx.declare_node(name, meta).await?;
        match &c.run {
            // The note its owner shows stays (final review M4); the lock
            // keeps the owner from changing it meanwhile.
            Some(run) => {
                let note = run.note.lock().await;
                self.ctx
                    .declare_node(&status_path(name), status_with(note.as_deref()))
                    .await?;
            }
            None => {
                self.ctx
                    .declare_node(&status_path(name), status_meta())
                    .await?;
            }
        }
        for (id, k) in adds::<D::Dev>("device") {
            let display = add_display("device", &k);
            self.ctx
                .declare_action(name, &id, add_form::<D>(&k.schema, display))
                .await?;
        }
        self.declare_common(name, &c.slot.schema(), &shown).await?;
        self.ctx
            .declare_action(name, "restart", plain("Restart"))
            .await?;
        self.ctx
            .declare_action(name, "export", export_form())
            .await?;
        self.ctx
            .declare_action(name, "import", import_form())
            .await?;
        for (id, meta) in driver_actions::<D>(c.server(), Level::Connection, &c.slot.kind) {
            self.ctx.declare_action(name, id, meta).await?;
        }
        self.declare_diag(name, |n| c.devices.contains_key(n))
            .await?;
        self.declare_run_toggle(name, c.enabled).await
    }

    /// The diagnostics leaves of a connection or device, except where a
    /// stored child already has the name (it keeps its node).
    async fn declare_diag(&self, base: &str, taken: impl Fn(&str) -> bool) -> Result<()> {
        if !D::DIAGNOSTICS {
            return Ok(());
        }
        for name in diag::names::<D>() {
            if taken(name) {
                warn!(node = %base, "child {name:?} hides the diagnostics leaf of that name");
                continue;
            }
            self.ctx
                .declare_node(&format!("{base}/{name}"), diag::leaf_meta(name))
                .await?;
        }
        Ok(())
    }

    async fn declare_dev(&self, conn: &str, dev: &str) -> Result<()> {
        let server = self.conns[conn].server();
        let d = &self.conns[conn].devices[dev];
        let base = format!("{conn}/{dev}");
        let shown = d.slot.shown();
        let mut meta = NodeMeta::folder().is("wy:df-device");
        meta.cfg = Some(shown.clone());
        self.ctx.declare_node(&base, meta).await?;
        self.ctx
            .declare_node(&status_path(&base), status_meta())
            .await?;
        self.declare_adds_below(&base, &[]).await?;
        self.declare_common(&base, &d.slot.schema(), &shown).await?;
        self.ctx
            .declare_action(&base, "restart", plain("Restart"))
            .await?;
        self.ctx
            .declare_action(&base, "export", export_form())
            .await?;
        if D::FOLDERS {
            self.ctx
                .declare_action(&base, "import", import_form())
                .await?;
        }
        for (id, meta) in driver_actions::<D>(server, Level::Device, &d.slot.kind) {
            self.ctx.declare_action(&base, id, meta).await?;
        }
        self.declare_diag(&base, |n| d.taken(&[], n)).await?;
        self.declare_run_toggle(&base, d.enabled).await
    }

    /// The add actions of a device or folder: one per point kind, and
    /// `add_folder` while folders may nest deeper.
    async fn declare_adds_below(&self, base: &str, folder: &[String]) -> Result<()> {
        for (id, k) in adds::<D::Point>("point") {
            let display = add_display("point", &k);
            self.ctx
                .declare_action(base, &id, add_form::<D>(&k.schema, display))
                .await?;
        }
        if D::FOLDERS && folder.len() < MAX_FOLDER_DEPTH {
            let form = ActionMeta::new()
                .level(Perm::Config)
                .param(
                    "name",
                    wyrm_core::meta::ParamMeta::of(TypeCode::String)
                        .required(true)
                        .display("Name"),
                )
                .display("Add Folder")
                .group(GROUP_NEW);
            self.ctx.declare_action(base, ADD_FOLDER, form).await?;
        }
        Ok(())
    }

    /// A folder: the add actions, `remove` (no `edit`: no rename), `copy`,
    /// `export` and `import`.
    async fn declare_folder(&self, conn: &str, dev: &str, folder: &[String]) -> Result<()> {
        let path = below(&format!("{conn}/{dev}"), folder);
        self.ctx
            .declare_node(&path, NodeMeta::folder().is("wy:df-folder"))
            .await?;
        self.declare_adds_below(&path, folder).await?;
        self.ctx
            .declare_action(&path, "remove", plain("Remove").group(GROUP_EDIT))
            .await?;
        self.ctx.declare_action(&path, "copy", copy_form()).await?;
        self.ctx
            .declare_action(&path, "export", export_form())
            .await?;
        self.ctx
            .declare_action(&path, "import", import_form())
            .await
    }

    /// A connection with its devices.
    async fn declare_conn_tree(&self, name: &str) -> Result<()> {
        self.declare_conn(name).await?;
        for dn in self.conns[name].devices.keys() {
            self.declare_branch(name, dn).await?;
        }
        Ok(())
    }

    /// A device with its folders (parents first) and points.
    async fn declare_branch(&self, conn: &str, dev: &str) -> Result<()> {
        self.declare_dev(conn, dev).await?;
        let d = &self.conns[conn].devices[dev];
        for f in &d.folders {
            self.declare_folder(conn, dev, f).await?;
        }
        for pn in d.points.keys() {
            self.declare_point(conn, dev, pn).await?;
        }
        Ok(())
    }

    async fn declare_point(&self, conn: &str, dev: &str, pt: &str) -> Result<()> {
        let server = self.conns[conn].server();
        let d = &self.conns[conn].devices[dev];
        let p = &d.points[pt].slot;
        let path = format!("{conn}/{dev}/{}", d.rel(pt));
        let mut meta = match &p.cfg {
            Some(cfg) => D::point_meta(cfg),
            None => NodeMeta::leaf(TypeCode::Dynamic),
        };
        if server && p.cfg.is_some() {
            // A server's points take their values from the tree.
            meta.writable = Some(Writable::Write);
        }
        let shown = p.shown();
        let cfg = meta.cfg.get_or_insert_with(Map::new);
        cfg.extend(shown.clone());
        self.ctx.declare_node(&path, meta).await?;
        self.declare_common(&path, &p.schema(), &shown).await?;
        if let Some(e) = &p.error {
            // Keep the node; show why it does not run.
            let _ = self
                .ctx
                .update_sample(
                    &path,
                    Sample {
                        v: Value::Str(e.clone()),
                        q: Quality::Bad,
                        t: now_us(),
                    },
                    Some(QUAL_CONFIG_ERROR),
                )
                .await;
        }
        Ok(())
    }

    /// `edit` (the node's own form, pre-filled), `remove` and `copy`,
    /// group `edit`.
    async fn declare_common(&self, path: &str, schema: &[ParamSpec], shown: &Map) -> Result<()> {
        let edit = form::<D>(schema, Some(shown))
            .display("Edit")
            .group(GROUP_EDIT);
        self.ctx.declare_action(path, "edit", edit).await?;
        self.ctx
            .declare_action(path, "remove", plain("Remove").group(GROUP_EDIT))
            .await?;
        self.ctx.declare_action(path, "copy", copy_form()).await
    }

    /// DSA shows only the action that applies: `stop` while the node runs,
    /// `start` while it is stopped.
    async fn declare_run_toggle(&self, path: &str, enabled: bool) -> Result<()> {
        let (on, off) = if enabled {
            ("stop", "start")
        } else {
            ("start", "stop")
        };
        self.ctx.remove_action(path, off).await?;
        self.ctx.declare_action(path, on, plain(&title(on))).await
    }

    /// Root actions: one `add_*` per connection kind, `export` (the whole
    /// tree), `import` (a connection), and `rescan` when the driver has one.
    async fn declare_root(&self) -> Result<()> {
        for (id, k) in adds::<D::Conn>("connection") {
            let display = add_display("connection", &k);
            self.ctx
                .declare_action("", &id, add_form::<D>(&k.schema, display))
                .await?;
        }
        self.ctx
            .declare_action(
                "",
                "export",
                plain("Export").result(ActionResult::Type(TypeCode::Map)),
            )
            .await?;
        self.ctx.declare_action("", "import", import_form()).await?;
        for (name, meta) in root_imports::<D>() {
            self.ctx.declare_action("", name, meta).await?;
        }
        if let Some(name) = D::RESCAN {
            self.ctx
                .declare_action(
                    "",
                    "rescan",
                    ActionMeta::new()
                        .level(Perm::Config)
                        .display(name)
                        .result(ActionResult::Type(TypeCode::Map)),
                )
                .await?;
        }
        Ok(())
    }

    /// The node kind an add action creates below `at`.
    fn add_kind(at: &At<'_>, action: &str) -> Option<&'static str> {
        let find = |list: Vec<(String, Kind)>| {
            list.into_iter()
                .find(|(id, _)| id == action)
                .map(|(_, k)| k.id)
        };
        match at {
            At::Root => find(adds::<D::Conn>("connection")),
            At::Conn(_) => find(adds::<D::Dev>("device")),
            At::Dev(..) | At::Folder(..) => find(adds::<D::Point>("point")),
            At::Point(..) => None,
        }
    }

    /// The node `parts` names. Below a device: a folder, or a point whose
    /// folder matches (a point at another folder's path is not found).
    fn resolve<'a>(&self, parts: &'a [String]) -> Result<At<'a>> {
        let (conn, dev, rest) = match parts {
            [] => return Ok(At::Root),
            [c] => return Ok(At::Conn(c)),
            [c, d] => return Ok(At::Dev(c, d)),
            [c, d, rest @ ..] => (c, d, rest),
        };
        let entry = self.conns.get(conn).and_then(|c| c.devices.get(dev));
        if entry.is_some_and(|e| e.folders.contains(rest)) {
            return Ok(At::Folder(conn, dev, rest.to_vec()));
        }
        let (id, folder) = rest.split_last().expect("not empty");
        match entry.and_then(|e| e.points.get(id)) {
            Some(p) if p.folder == folder => Ok(At::Point(conn, dev, id)),
            None if folder.is_empty() => Ok(At::Point(conn, dev, id)),
            _ => Err(LinkError::not_found(parts.join("/"))),
        }
    }

    /// `rescan`: forms again with fresh choices; replies `{param: [found]}`.
    async fn rescan(&self) -> Result<Value> {
        self.declare_root().await?;
        for cn in self.conns.keys() {
            self.declare_conn_tree(cn).await?;
        }
        let mut found = Map::new();
        let schemas = D::Conn::kinds()
            .into_iter()
            .chain(D::Dev::kinds())
            .chain(D::Point::kinds())
            .flat_map(|k| k.schema);
        for p in schemas {
            let list = D::choices(p.name);
            if !list.is_empty() {
                found.insert(
                    p.name.to_owned(),
                    Value::Array(list.into_iter().map(Value::Str).collect()),
                );
            }
        }
        Ok(Value::Map(found))
    }

    /// The runtime view of a connection's devices (valid, enabled ones).
    fn dev_map(&self, conn: &str) -> DevMap<D> {
        let mut out = DevMap::new();
        for (name, d) in &self.conns[conn].devices {
            let (Some(cfg), true) = (&d.slot.cfg, d.enabled) else {
                continue;
            };
            let points: BTreeMap<PointId, D::Point> = d
                .points
                .iter()
                .filter_map(|(n, p)| p.slot.cfg.clone().map(|c| (n.clone(), c)))
                .collect();
            let paths = points
                .keys()
                .map(|n| (n.clone(), format!("{conn}/{name}/{}", d.rel(n))))
                .collect();
            let mut by_period: BTreeMap<Duration, Vec<(PointId, D::Point)>> = BTreeMap::new();
            for (n, c) in &points {
                by_period
                    .entry(D::poll_period(c).max(Duration::from_millis(10)))
                    .or_default()
                    .push((n.clone(), c.clone()));
            }
            let groups = by_period
                .into_iter()
                .map(|(period, members)| Group {
                    period,
                    ids: members.iter().map(|(n, _)| n.clone()).collect(),
                    plan: Arc::new(D::plan(cfg, &members)),
                    inflight: Arc::new(AtomicU8::new(POLL_IDLE)),
                })
                .collect();
            out.insert(
                name.clone(),
                DevRun {
                    cfg: cfg.clone(),
                    token: d.token,
                    points,
                    paths,
                    groups,
                },
            );
        }
        out
    }

    /// Start tickers for `devs` (none on a server connection: it is never
    /// polled or pinged).
    async fn start_tickers(
        &self,
        devs: &DevMap<D>,
        tx: &mpsc::Sender<Req>,
        view: &SharedView<D>,
        gen: u64,
        server: bool,
    ) -> (Vec<JoinHandle<()>>, watch::Sender<bool>) {
        let (tick_stop, rx) = watch::channel(false);
        let mut tickers = Vec::new();
        if server {
            return (tickers, tick_stop);
        }
        for (dev, run) in devs {
            for (gi, g) in run.groups.iter().enumerate() {
                let mut pubs = Vec::new();
                if !self.poll_unsubscribed {
                    for path in g.ids.iter().filter_map(|id| run.paths.get(id)) {
                        if let Ok(p) = self.ctx.publisher(path).await {
                            pubs.push(p);
                        }
                    }
                }
                let paths = g
                    .ids
                    .iter()
                    .filter_map(|id| run.paths.get(id).cloned())
                    .collect();
                tickers.push(tokio::spawn(
                    poll_ticker::<D>(
                        Ticker {
                            ctx: self.ctx.clone(),
                            view: view.clone(),
                            tx: tx.clone(),
                            dev: dev.clone(),
                            group: gi,
                            gen,
                            period: g.period,
                            inflight: g.inflight.clone(),
                            paths,
                        },
                        pubs,
                        self.poll_unsubscribed,
                        rx.clone(),
                    )
                    .in_current_span(),
                ));
            }
            if let Some(period) = D::ping_period(&run.cfg) {
                tickers.push(tokio::spawn(
                    ping_ticker(tx.clone(), dev.clone(), gen, period, rx.clone()).in_current_span(),
                ));
            }
        }
        (tickers, tick_stop)
    }

    /// Bring a connection up (if valid and enabled) or show why not.
    async fn bring_up(&mut self, name: &str) {
        let c = &self.conns[name];
        let points = Self::conn_point_paths(name, c);
        match (&c.slot.cfg, c.enabled) {
            (None, _) => {
                set_status(&self.ctx, name, NodeState::Failed, c.slot.error.as_deref()).await;
            }
            (Some(_), false) => {
                set_status(&self.ctx, name, NodeState::Stopped, None).await;
                for d in c.devices.keys() {
                    set_status(
                        &self.ctx,
                        &format!("{name}/{d}"),
                        NodeState::StoppedByParent,
                        None,
                    )
                    .await;
                }
                mark(&self.ctx, points, Quality::Bad, QUAL_DISCONNECTED).await;
            }
            (Some(cfg), true) => {
                let cfg = cfg.clone();
                let server = D::is_server(&cfg);
                let devs = Arc::new(self.dev_map(name));
                for (d, e) in &c.devices {
                    let base = format!("{name}/{d}");
                    match (&e.slot.cfg, e.enabled) {
                        (None, _) => {
                            set_status(&self.ctx, &base, NodeState::Failed, e.slot.error.as_deref())
                                .await
                        }
                        (Some(_), false) => {
                            set_status(&self.ctx, &base, NodeState::Stopped, None).await
                        }
                        (Some(_), true) => set_status(&self.ctx, &base, NodeState::New, None).await,
                    }
                }
                let (tx, rx) = mpsc::channel(256);
                let acting = Arc::new(AtomicU8::new(SLOT_FREE));
                let note = NoteSlot::default();
                let (stop, stop_rx) = watch::channel(false);
                let book = diag::new_book(c.devices.keys());
                let flusher = D::DIAGNOSTICS.then(|| {
                    let (nudge, nudges) = mpsc::channel(16);
                    let task = tokio::spawn(
                        diag::flusher::<D>(
                            self.ctx.clone(),
                            name.to_owned(),
                            book.clone(),
                            nudges,
                            stop_rx.clone(),
                        )
                        .in_current_span(),
                    );
                    (task, nudge)
                });
                let view = Arc::new(tokio::sync::RwLock::new(View {
                    gen: 0,
                    devs: devs.clone(),
                    since: tokio::time::Instant::now(),
                }));
                let owner = tokio::spawn(
                    owner::<D>(
                        self.ctx.clone(),
                        name.to_owned(),
                        cfg,
                        view.clone(),
                        book.clone(),
                        note.clone(),
                        rx,
                        stop_rx,
                    )
                    .in_current_span(),
                );
                let (tickers, tick_stop) = self.start_tickers(&devs, &tx, &view, 0, server).await;
                self.conns.get_mut(name).expect("exists").run = Some(ConnRun {
                    tx,
                    acting,
                    note,
                    view,
                    gen: 0,
                    stop,
                    owner,
                    tickers,
                    tick_stop,
                    book,
                    flusher,
                });
            }
        }
    }

    /// Stop the owner and tickers; returns after they ended (teardown before bring-up).
    async fn tear_down(&mut self, name: &str) {
        let Some(run) = self.conns.get_mut(name).and_then(|c| c.run.take()) else {
            return;
        };
        stop_run(run).await;
    }

    /// A device's diagnostics from zero, published at once.
    fn reset_diag(&self, conn: &str, dev: &str) {
        let Some(run) = self.conns.get(conn).and_then(|c| c.run.as_ref()) else {
            return;
        };
        diag::reset_dev(&run.book, dev);
        if let Some((_, nudge)) = &run.flusher {
            let _ = nudge.try_send(Some(dev.to_owned()));
        }
    }

    /// The driver action `action` on the node at `parts`, if it has one.
    fn find_action(&self, parts: &[String], action: &str) -> Option<FoundAction> {
        let server = self.conns.get(parts.first()?)?.server();
        let (conn, dev, level, kind) = match parts {
            [c] => (c, None, Level::Connection, &self.conns.get(c)?.slot.kind),
            [c, d] => (
                c,
                Some(d.clone()),
                Level::Device,
                &self.conns.get(c)?.devices.get(d)?.slot.kind,
            ),
            _ => return None,
        };
        driver_actions::<D>(server, level, kind)
            .into_iter()
            .find(|(n, _)| *n == action)
            .map(|(_, m)| FoundAction {
                conn: conn.clone(),
                dev,
                timeout_ms: m.timeout_ms,
                slot: if m.level.is_some_and(|l| l > Perm::Read) {
                    SLOT_HOLD
                } else {
                    SLOT_READ
                },
            })
    }

    /// Send a driver action to the owner and answer `out` from a task of
    /// its own: the link task does not wait for the action. One action per
    /// connection is queued or running at a time; another answers `busy`
    /// at once, so actions (of any caller, even at level `read`) delay the
    /// connection's polls by one action at most (final review I1).
    async fn run_action(
        &self,
        found: FoundAction,
        action: &str,
        args: Value,
        out: ReplySink,
    ) -> Result<()> {
        let FoundAction {
            conn,
            dev,
            timeout_ms,
            slot,
        } = found;
        let run = self
            .conns
            .get(&conn)
            .and_then(|c| c.run.as_ref())
            .ok_or_else(|| LinkError::new(Status::Disconnected, "connection not running"))?;
        // A set waiting for the owner runs before the next action: both come
        // through the link task, which waits for the set's answer, so no
        // action can take the slot meanwhile (fairness, P32).
        if run
            .acting
            .compare_exchange(SLOT_FREE, slot, Ordering::AcqRel, Ordering::Acquire)
            .is_err()
        {
            return Err(LinkError::new(
                Status::Busy,
                "an action runs on this connection: try again",
            ));
        }
        let (tx, rx) = oneshot::channel();
        // Frees the slot once answered, or dropped unanswered.
        let reply = ActionReply {
            tx: Some(tx),
            slot: run.acting.clone(),
        };
        let bound = timeout_ms.map(|ms| Duration::from_millis(ms.into()));
        // The SDK's bound on this call, counted from the request.
        let deadline = out.since() + bound.unwrap_or_else(|| self.ctx.driver_timeout());
        // Never wait for room: a full queue answers `busy` and does not
        // stall the link task (P12). A refused request drops its reply,
        // which frees the slot.
        run.tx
            .try_send(Req::Invoke {
                dev,
                action: action.to_owned(),
                args,
                gen: run.gen,
                bound,
                deadline,
                reply,
            })
            .map_err(|e| match e {
                mpsc::error::TrySendError::Full(_) => {
                    LinkError::new(Status::Busy, "connection busy: too many requests queued")
                }
                mpsc::error::TrySendError::Closed(_) => {
                    LinkError::new(Status::Disconnected, "connection stopped")
                }
            })?;
        tokio::spawn(
            async move {
                let _ = match rx.await {
                    Ok(Ok(v)) => out.reply(v).await,
                    Ok(Err(e)) => out.error(e).await,
                    Err(_) => {
                        out.error(LinkError::new(Status::Disconnected, "connection stopped"))
                            .await
                    }
                };
            }
            .in_current_span(),
        );
        Ok(())
    }

    /// Device/point change: new plan for the owner, new tickers, no
    /// reconnect. The next generation of the plan ([`View`]): requests
    /// queued or running under the old one never publish after this
    /// returns. It waits only for a publish in progress (no device I/O).
    async fn replan(&mut self, conn: &str) {
        let devs = Arc::new(self.dev_map(conn));
        let server = self.conns.get(conn).is_some_and(ConnEntry::server);
        let Some(run) = self.conns.get_mut(conn).and_then(|c| c.run.take()) else {
            return;
        };
        let _ = run.tick_stop.send(true);
        for t in run.tickers {
            let _ = tokio::time::timeout(Duration::from_secs(1), t).await;
        }
        let gen = {
            let mut v = run.view.write().await;
            v.gen += 1;
            v.devs = devs.clone();
            v.since = tokio::time::Instant::now();
            v.gen
        };
        let (tickers, tick_stop) = self
            .start_tickers(&devs, &run.tx, &run.view, gen, server)
            .await;
        if server {
            // Nothing else wakes the owner of a server: it hands the new
            // plan to the server at once (a new point is served now). Never
            // wait for room: a full queue wakes it anyway, and it serves
            // the new plan before its next request.
            let _ = run.tx.try_send(Req::Serve);
        }
        self.conns.get_mut(conn).expect("exists").run = Some(ConnRun {
            tickers,
            tick_stop,
            gen,
            ..run
        });
    }

    fn export(&self) -> Value {
        let mut conns = Map::new();
        for (cn, c) in &self.conns {
            let mut cm = c.slot.shown();
            cm.insert("enabled".into(), Value::Bool(c.enabled));
            let mut devs = Map::new();
            for (dn, d) in &c.devices {
                let mut dm = d.slot.shown();
                dm.insert("enabled".into(), Value::Bool(d.enabled));
                dm.extend(d.branch(&[], &Slot::shown));
                devs.insert(dn.clone(), Value::Map(dm));
            }
            cm.insert("devices".into(), Value::Map(devs));
            conns.insert(cn.clone(), Value::Map(cm));
        }
        let mut m = Map::new();
        m.insert(
            "poll_unsubscribed".into(),
            Value::Bool(self.poll_unsubscribed),
        );
        m.insert("connections".into(), Value::Map(conns));
        Value::Map(m)
    }

    /// The whole tree with secrets (for `persist` only, never a reply).
    fn full_tree(&self) -> Value {
        let mut conns = Map::new();
        for (cn, c) in &self.conns {
            let mut cm = c.slot.stored();
            cm.insert("enabled".into(), Value::Bool(c.enabled));
            let mut devs = Map::new();
            for (dn, d) in &c.devices {
                let mut dm = d.slot.stored();
                dm.insert("enabled".into(), Value::Bool(d.enabled));
                dm.extend(d.branch(&[], &Slot::stored));
                devs.insert(dn.clone(), Value::Map(dm));
            }
            cm.insert("devices".into(), Value::Map(devs));
            conns.insert(cn.clone(), Value::Map(cm));
        }
        let mut m = Map::new();
        m.insert(
            "poll_unsubscribed".into(),
            Value::Bool(self.poll_unsubscribed),
        );
        m.insert("connections".into(), Value::Map(conns));
        Value::Map(m)
    }

    fn conn_mut(&mut self, name: &str) -> Result<&mut ConnEntry<D>> {
        self.conns
            .get_mut(name)
            .ok_or_else(|| LinkError::not_found(name.to_owned()))
    }
}

/// Stop a connection's owner and tickers; returns after they ended.
async fn stop_run<D: Driver>(run: ConnRun<D>) {
    let _ = run.tick_stop.send(true);
    let _ = run.stop.send(true);
    for t in run.tickers {
        let _ = tokio::time::timeout(Duration::from_secs(1), t).await;
    }
    let mut owner = run.owner;
    if tokio::time::timeout(Duration::from_secs(3), &mut owner)
        .await
        .is_err()
    {
        owner.abort();
    }
    if let Some((mut task, _)) = run.flusher {
        if tokio::time::timeout(Duration::from_secs(1), &mut task)
            .await
            .is_err()
        {
            task.abort();
        }
    }
}

/// What a poll ticker serves: one poll group of a device.
struct Ticker<D: Driver> {
    ctx: LinkCtx,
    view: SharedView<D>,
    tx: mpsc::Sender<Req>,
    dev: String,
    group: usize,
    /// The plan generation the ticker was started for.
    gen: u64,
    period: Duration,
    inflight: Arc<AtomicU8>,
    /// The node keys of the group's points.
    paths: Vec<String>,
}

impl<D: Driver> Ticker<D> {
    /// One more period in which the group's poll could not run (it waits
    /// in the queue behind an action or a long write series, or the queue
    /// is full): after [`Driver::stale_misses`] in a row the group's good
    /// points go `uncertain/stale` (final review M3). A poll that runs
    /// counts its own outcome instead ([`Owner::dev_miss`]).
    async fn waited(&self, waits: &mut u32) {
        *waits = waits.saturating_add(1);
        if *waits != D::stale_misses().max(1) {
            return;
        }
        // Only while the plan is current: nothing of an old plan publishes
        // after a re-plan (P19).
        let current = self.view.read().await;
        if current.gen == self.gen {
            mark_stale(&self.ctx, self.paths.iter().cloned()).await;
        }
    }
}

async fn poll_ticker<D: Driver>(
    t: Ticker<D>,
    pubs: Vec<PointPublisher>,
    poll_unsubscribed: bool,
    mut stop: watch::Receiver<bool>,
) {
    let mut iv = tokio::time::interval(t.period);
    iv.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
    // Periods in a row in which the group's poll could not run.
    let mut waits = 0u32;
    // The last tick queued a poll.
    let mut queued = false;
    loop {
        tokio::select! {
            _ = iv.tick() => {}
            _ = stop.changed() => return,
        }
        // No pile-up: a slow device skips ticks instead of queueing them.
        match t.inflight.load(Ordering::Acquire) {
            POLL_RUNNING => {
                waits = 0;
                continue;
            }
            POLL_QUEUED => {
                t.waited(&mut waits).await;
                continue;
            }
            _ if queued => waits = 0,
            _ => {}
        }
        if !poll_unsubscribed {
            let mut any = false;
            for p in &pubs {
                if p.has_subscribers().await {
                    any = true;
                    break;
                }
            }
            if !any {
                // Not polled on purpose: no miss.
                (waits, queued) = (0, false);
                continue;
            }
        }
        t.inflight.store(POLL_QUEUED, Ordering::Release);
        queued =
            t.tx.try_send(Req::Poll {
                dev: t.dev.clone(),
                group: t.group,
                gen: t.gen,
                inflight: t.inflight.clone(),
            })
            .is_ok();
        if !queued {
            t.inflight.store(POLL_IDLE, Ordering::Release);
            t.waited(&mut waits).await;
        }
    }
}

async fn ping_ticker(
    tx: mpsc::Sender<Req>,
    dev: String,
    gen: u64,
    period: Duration,
    mut stop: watch::Receiver<bool>,
) {
    let inflight = Arc::new(AtomicBool::new(false));
    let mut iv = tokio::time::interval(period);
    iv.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
    loop {
        tokio::select! {
            _ = iv.tick() => {}
            _ = stop.changed() => return,
        }
        // No pile-up: while the last ping waits for the owner or runs (a
        // long action holds it), ticks are skipped.
        if inflight.swap(true, Ordering::AcqRel) {
            continue;
        }
        let ping = Req::Ping {
            dev: dev.clone(),
            gen,
            inflight: inflight.clone(),
        };
        if tx.try_send(ping).is_err() {
            inflight.store(false, Ordering::Release);
        }
    }
}

/// Per-device bookkeeping inside the owner.
struct DevHealth {
    state: Option<NodeState>,
    /// Misses in a row (polls and pings): the quality ladder.
    misses: u32,
    /// Of those, the polls without an answer since the last poll that
    /// answered: an answered ping forgives only the others (final review
    /// M2), so a device whose polls time out but whose pings answer stays
    /// `bad/comm_fail`.
    poll_misses: u32,
    /// Misses in a row of single points (by path) whose result was
    /// [`DriverError::Device`] while other points of the device answered.
    point_misses: BTreeMap<String, u32>,
    /// The device's run token this entry is about ([`run_token`]).
    token: u64,
}

struct Owner<D: Driver> {
    ctx: LinkCtx,
    conn: String,
    view: SharedView<D>,
    /// The plan of [`Owner::gen`] (refreshed before every request).
    devs: Arc<DevMap<D>>,
    gen: u64,
    health: BTreeMap<String, DevHealth>,
    book: diag::SharedBook,
    /// A server connection ([`Driver::is_server`]).
    server: bool,
    /// The plan the server was last handed ([`Driver::serve`]) and its
    /// generation; `None` on a transport just opened.
    served: Option<(u64, Arc<DevMap<D>>)>,
    /// The [`Driver::status_note`] its `status` leaf shows.
    note: NoteSlot,
}

impl<D: Driver> Owner<D> {
    /// Take the current plan.
    async fn refresh(&mut self) {
        let view = self.view.clone();
        let v = view.read().await;
        self.adopt(&v);
    }

    /// Use plan `v`. On a new generation, forget the state and misses of
    /// devices that left it or got a new run token (added, edited, started,
    /// restarted, replaced), so their next outcome is published afresh.
    fn adopt(&mut self, v: &View<D>) {
        if v.gen != self.gen {
            self.health
                .retain(|d, h| v.devs.get(d).is_some_and(|r| r.token == h.token));
        }
        self.devs = v.devs.clone();
        self.gen = v.gen;
    }

    /// The bookkeeping of `dev` under the current plan.
    fn health(&mut self, dev: &str) -> &mut DevHealth {
        let token = self.devs.get(dev).map_or(0, |r| r.token);
        self.health.entry(dev.to_owned()).or_insert(DevHealth {
            state: None,
            misses: 0,
            poll_misses: 0,
            point_misses: BTreeMap::new(),
            token,
        })
    }

    /// Count the requests of the operation that just ran for `dev` (or the
    /// connection); `cut` = its bound cut it, which counts one timeout (the
    /// request on the wire never got its outcome).
    fn record(&self, t: &mut D::Transport, dev: Option<&str>, cut: bool) {
        if !D::DIAGNOSTICS {
            return;
        }
        let mut out = D::take_outcomes(t);
        if cut {
            out.push(Outcome::Timeout);
        }
        diag::record::<D>(&self.book, dev, &out);
    }

    fn dev_points(&self, dev: &str) -> Vec<String> {
        self.devs
            .get(dev)
            .map(|d| d.paths.values().cloned().collect())
            .unwrap_or_default()
    }

    async fn dev_state(&mut self, dev: &str, s: NodeState, err: Option<&str>) {
        let h = self.health(dev);
        if h.state == Some(s) && err.is_none() {
            return;
        }
        h.state = Some(s);
        set_status(&self.ctx, &format!("{}/{dev}", self.conn), s, err).await;
    }

    /// The device answered a poll (or a server serves it).
    async fn dev_ok(&mut self, dev: &str) {
        let h = self.health(dev);
        (h.misses, h.poll_misses) = (0, 0);
        self.dev_state(dev, NodeState::Connected, None).await;
    }

    /// The device answered a ping: `Connected`, but the misses its polls
    /// earned stay (final review M2). Its points keep their quality until a
    /// poll answers: the ladder neither starts again nor goes back.
    async fn ping_ok(&mut self, dev: &str) {
        let limit = D::stale_misses().max(1);
        let h = self.health(dev);
        h.misses = h.poll_misses;
        // A device whose polls failed stays `Failed` with its error until
        // a poll answers: `Connected` over `bad` points would mislead.
        if h.poll_misses < limit {
            self.dev_state(dev, NodeState::Connected, None).await;
        }
    }

    /// Quality ladder: first miss → `uncertain/stale` (good points only);
    /// `stale_misses` → device `Failed`, points `bad/comm_fail`. `poll`: a
    /// poll's miss, not a ping's.
    async fn dev_miss(&mut self, dev: &str, why: &str, poll: bool) {
        let misses = {
            let h = self.health(dev);
            h.misses += 1;
            if poll {
                h.poll_misses += 1;
            }
            h.misses
        };
        if misses == 1 {
            mark_stale(&self.ctx, self.dev_points(dev)).await;
        }
        // `>=`: a ping that answered in between does not reset the misses
        // polls earned, so the limit can be passed without being met.
        if misses >= D::stale_misses().max(1) {
            if self.health(dev).state != Some(NodeState::Failed) {
                self.dev_state(dev, NodeState::Failed, Some(why)).await;
            }
            mark(
                &self.ctx,
                self.dev_points(dev),
                Quality::Bad,
                QUAL_COMM_FAIL,
            )
            .await;
        }
    }

    /// The device answered, but not for these points (a batch timed out):
    /// the same ladder as [`Owner::dev_miss`], per point, while the device
    /// stays `Connected`.
    async fn points_missed(&mut self, dev: &str, answered: Vec<String>, missed: Vec<String>) {
        let limit = D::stale_misses().max(1);
        let (mut stale, mut failed) = (Vec::new(), Vec::new());
        // A point already `bad` (the device failed, a point error) starts
        // at the limit: no answer never lifts it (M1).
        let missed: Vec<(String, bool)> = missed
            .into_iter()
            .map(|p| {
                let bad = self.ctx.last(&p).is_some_and(|s| s.q == Quality::Bad);
                (p, bad)
            })
            .collect();
        {
            let h = self.health(dev);
            for p in answered {
                h.point_misses.remove(&p);
            }
            for (p, bad) in missed {
                let n = h
                    .point_misses
                    .entry(p.clone())
                    .or_insert(if bad { limit } else { 0 });
                if *n >= limit {
                    continue;
                }
                *n += 1;
                if *n == 1 {
                    stale.push(p.clone());
                }
                if *n == limit {
                    failed.push(p);
                }
            }
        }
        mark_stale(&self.ctx, stale).await;
        mark(&self.ctx, failed, Quality::Bad, QUAL_COMM_FAIL).await;
    }

    /// Connection lost or not open: every device stopped by its parent.
    async fn cascade_down(&mut self) {
        let devs: Vec<String> = self.devs.keys().cloned().collect();
        for d in devs {
            let h = self.health(&d);
            (h.misses, h.poll_misses) = (0, 0);
            self.dev_state(&d, NodeState::StoppedByParent, None).await;
            mark(
                &self.ctx,
                self.dev_points(&d),
                Quality::Bad,
                QUAL_DISCONNECTED,
            )
            .await;
        }
    }

    /// Publish the values a server changed ([`Driver::take_changed`]) of the
    /// points in the current plan. Under the plan's read lock.
    async fn publish_changed(&mut self, t: &mut D::Transport) {
        let devs = self.devs.clone();
        for (dev, id, v) in D::take_changed(t) {
            if let Some(path) = devs.get(&dev).and_then(|d| d.paths.get(&id)) {
                put_point(&self.ctx, path, v, Quality::Good, None, None).await;
            }
        }
    }

    /// The plan was handed to the server.
    fn plan_served(&self) -> bool {
        self.served
            .as_ref()
            .is_some_and(|(gen, _)| *gen == self.gen)
    }

    /// A server connection: hand the current plan to the server, then write
    /// the tree's last value of each point that is new to the server or
    /// whose params or device params changed (after open: every point), and
    /// publish what it serves. So values come from the tree: a reopened
    /// server, a device started again, a point edited to another scale
    /// serve the tree's value, and a point the tree never set has none. A
    /// point that stays as it was keeps what it serves (a master may have
    /// written it). A tree value the server does not take (it does not fit
    /// the point's new data type) is logged at warn and the point marked
    /// `bad/config_error`, its old value kept, until a value is served.
    /// Devices the server refuses show `Failed`, the others `Connected`.
    /// Under the plan's read lock; each write bounded by `bound`.
    async fn serve_plan(&mut self, t: &mut D::Transport, bound: Duration) {
        let devs = self.devs.clone();
        let before = self.served.take().map(|(_, d)| d);
        let served: Vec<Served<'_, D>> = devs
            .iter()
            .map(|(name, d)| Served {
                name,
                dev: &d.cfg,
                points: &d.points,
            })
            .collect();
        let refused: BTreeMap<String, String> = D::serve(t, &served).into_iter().collect();
        self.served = Some((self.gen, devs.clone()));
        let same = |name: &str, d: &DevRun<D>, id: &str, p: &D::Point| {
            before
                .as_ref()
                .and_then(|b| b.get(name))
                .is_some_and(|old| old.cfg == d.cfg && old.points.get(id) == Some(p))
        };
        for (name, d) in devs.iter().filter(|(n, _)| !refused.contains_key(*n)) {
            for (id, p) in &d.points {
                if same(name, d, id, p) {
                    continue;
                }
                let Some(path) = d.paths.get(id) else {
                    continue;
                };
                let Some(last) = self.ctx.last(path) else {
                    continue;
                };
                let w = tokio::time::timeout(bound, D::write(t, &d.cfg, id, p, &last.v));
                let why = match w.await {
                    Ok(Ok(())) => continue,
                    Ok(Err(e)) => e.to_string(),
                    Err(_) => "timed out".to_owned(),
                };
                // The server does not serve the tree's value (it does not fit
                // the point's new params): the broker would keep the old
                // value at good quality. Bad until the tree or the remote
                // side gives one the server takes (the publish of a value it
                // serves follows below and wins). Published even when the
                // point is bad already (`bad/disconnected` while the server
                // was down): the reason changes, not only the quality, so
                // not `mark`, which skips a point of the same quality.
                warn!(point = %path, "the tree's last value is not served: {why}");
                let bad = Sample {
                    v: last.v,
                    q: Quality::Bad,
                    t: now_us(),
                };
                let _ = self
                    .ctx
                    .update_sample(path, bad, Some(QUAL_CONFIG_ERROR))
                    .await;
            }
        }
        self.publish_changed(t).await;
        for d in devs.keys() {
            match refused.get(d) {
                Some(why) => self.dev_state(d, NodeState::Failed, Some(why)).await,
                None => self.dev_ok(d).await,
            }
        }
    }

    /// Show [`Driver::status_note`] of the open connection (`None`: clear a
    /// note shown before) as `attr.warning` of its `status` leaf.
    /// The note is kept in [`NoteSlot`], so a new declaration of the
    /// connection (`rescan`) shows it too (final review M4).
    async fn note(&mut self, note: Option<&str>) {
        let mut shown = self.note.lock().await;
        if note.is_none() && shown.is_none() {
            return;
        }
        let _ = self
            .ctx
            .declare_node(&status_path(&self.conn), status_with(note))
            .await;
        *shown = note.map(str::to_owned);
    }

    async fn publish_results(
        &mut self,
        dev: &str,
        results: Vec<(PointId, Result<Value, DriverError>)>,
    ) -> std::result::Result<(), String> {
        let mut device_err = None;
        let mut any_ok = false;
        let mut missed = Vec::new();
        let mut answered = Vec::new();
        let devs = self.devs.clone();
        let run = devs.get(dev);
        let republish = run.and_then(|d| D::republish(&d.cfg));
        for (id, r) in results {
            let path = match run.and_then(|d| d.paths.get(&id)) {
                Some(p) => p.clone(),
                None => format!("{}/{dev}/{id}", self.conn),
            };
            match r {
                Ok(v) => {
                    any_ok = true;
                    put_point(&self.ctx, &path, v, Quality::Good, None, republish).await;
                    answered.push(path);
                }
                Err(DriverError::Point(e)) => {
                    any_ok = true; // the device answered
                    answered.push(path.clone());
                    debug!(point = %path, "point error: {e}");
                    let v = self.ctx.last(&path).map(|s| s.v).unwrap_or(Value::Null);
                    put_point(
                        &self.ctx,
                        &path,
                        v,
                        Quality::Bad,
                        Some(QUAL_DEVICE_ERROR),
                        republish,
                    )
                    .await;
                }
                Err(DriverError::Device(e)) => {
                    device_err = Some(e);
                    missed.push(path);
                }
                Err(DriverError::Transport(e)) => return Err(e),
            }
        }
        match device_err {
            Some(e) if !any_ok => self.dev_miss(dev, &e, true).await,
            _ => {
                self.dev_ok(dev).await;
                self.points_missed(dev, answered, missed).await;
            }
        }
        Ok(())
    }
}

/// The connection owner: opens the transport, serves requests in order,
/// reconnects with capped, jittered backoff.
#[allow(clippy::too_many_arguments)]
async fn owner<D: Driver>(
    ctx: LinkCtx,
    conn: String,
    cfg: D::Conn,
    view: SharedView<D>,
    book: diag::SharedBook,
    note: NoteSlot,
    mut rx: mpsc::Receiver<Req>,
    mut stop: watch::Receiver<bool>,
) {
    let timeout = D::io_timeout(&cfg);
    let (devs, gen) = {
        let v = view.read().await;
        (v.devs.clone(), v.gen)
    };
    let mut o = Owner::<D> {
        ctx,
        conn,
        view,
        devs,
        gen,
        health: BTreeMap::new(),
        book,
        server: D::is_server(&cfg),
        served: None,
        note,
    };
    let mut attempt = 0u32;
    loop {
        set_status(&o.ctx, &o.conn, NodeState::Connecting, None).await;
        let opened = tokio::select! {
            r = tokio::time::timeout(timeout, guarded(D::open(&cfg))) => r,
            _ = stop.changed() => return,
        };
        let failure = match opened {
            Ok(Err(p)) => p,
            Ok(Ok(Ok(mut t))) => {
                attempt = 0;
                o.record(&mut t, None, false);
                let note = D::status_note(&t);
                if let Some(n) = &note {
                    warn!(conn = %o.conn, "{n}");
                }
                o.note(note.as_deref()).await;
                set_status(&o.ctx, &o.conn, NodeState::Connected, None).await;
                {
                    // Under the plan's read lock: a re-plan (an overwrite)
                    // waits for this loop and never sees it after.
                    let view = o.view.clone();
                    let v = view.read().await;
                    o.adopt(&v);
                    if o.server {
                        // A new server: every value from the tree.
                        o.served = None;
                        o.serve_plan(&mut t, timeout).await;
                    } else {
                        let devs: Vec<String> = o.devs.keys().cloned().collect();
                        for d in devs {
                            o.dev_state(&d, NodeState::Connecting, None).await;
                        }
                    }
                }
                // A panic anywhere in serving (a driver's write, action or serve) is a
                // failure of the connection, as a transport error (security review LNK-2).
                match guarded(serve::<D>(&mut o, &mut t, &mut rx, &mut stop, &cfg)).await {
                    Ok(None) => {
                        o.note(None).await;
                        return;
                    }
                    Ok(Some(e)) | Err(e) => e,
                }
            }
            Ok(Ok(Err(e))) => e.to_string(),
            Err(_) => "open timed out".to_owned(),
        };
        warn!(conn = %o.conn, "connection failed: {failure}");
        o.note(None).await;
        set_status(&o.ctx, &o.conn, NodeState::Failed, Some(&failure)).await;
        {
            let view = o.view.clone();
            let v = view.read().await;
            o.adopt(&v);
            o.cascade_down().await;
        }
        // Backoff; writes meanwhile are answered `disconnected`.
        let sleep = tokio::time::sleep(backoff(attempt, jitter()));
        tokio::pin!(sleep);
        attempt = attempt.saturating_add(1);
        loop {
            tokio::select! {
                _ = &mut sleep => break,
                _ = stop.changed() => return,
                r = rx.recv() => match r {
                    None => return,
                    Some(Req::Write { reply, .. }) => {
                        let _ = reply.send(Err(LinkError::new(Status::Disconnected, failure.clone())));
                    }
                    Some(Req::Invoke { reply, .. }) => {
                        let _ = reply.send(Err(LinkError::new(Status::Disconnected, failure.clone())));
                    }
                    Some(Req::Poll { inflight, .. }) => {
                        inflight.store(POLL_IDLE, Ordering::Release);
                    }
                    Some(Req::Ping { inflight, .. }) => {
                        inflight.store(false, Ordering::Release);
                    }
                    // Served on the next open.
                    Some(Req::Serve) => {}
                },
            }
        }
    }
}

/// Run a driver future; a panic in it is `Err` with its message (security review LNK-2: a
/// panic in the owner task left the connection `Connected` with frozen good values).
async fn guarded<T>(f: impl std::future::Future<Output = T>) -> Result<T, String> {
    use futures_util::FutureExt;
    std::panic::AssertUnwindSafe(f)
        .catch_unwind()
        .await
        .map_err(|p| {
            let what = p
                .downcast_ref::<&str>()
                .map(|s| (*s).to_owned())
                .or_else(|| p.downcast_ref::<String>().cloned())
                .unwrap_or_else(|| "a panic".into());
            error!("driver panicked: {what}");
            format!("driver panicked: {what}")
        })
}

/// The first transport error among poll results.
fn transport_error(results: &[(PointId, Result<Value, DriverError>)]) -> Option<String> {
    results.iter().find_map(|(_, r)| match r {
        Err(DriverError::Transport(e)) => Some(e.clone()),
        _ => None,
    })
}

/// What the owner serves next: one of its requests, or (a server) a
/// request of the remote side that [`Driver::remote`] took and that
/// [`Driver::apply_remote`] answers next.
enum Next {
    Req(Req),
    /// [`Driver::remote`] took a request.
    Remote(std::result::Result<(), DriverError>),
}

/// Serve requests on an open transport. `None` = stopped; `Some(err)` =
/// the transport broke. Pings are bounded by [`Driver::io_timeout`],
/// writes by [`Driver::write_timeout`], polls by [`Driver::poll_timeout`].
/// A server also serves its remote side ([`Driver::remote`]) and gets every
/// new plan before the next request ([`Driver::serve`]).
async fn serve<D: Driver>(
    o: &mut Owner<D>,
    t: &mut D::Transport,
    rx: &mut mpsc::Receiver<Req>,
    stop: &mut watch::Receiver<bool>,
    cfg: &D::Conn,
) -> Option<String> {
    let timeout = D::io_timeout(cfg);
    let server = o.server;
    loop {
        let next = tokio::select! {
            r = rx.recv() => Next::Req(r?),
            r = D::remote(t), if server => Next::Remote(r),
            _ = stop.changed() => return None,
        };
        o.refresh().await;
        // Results are published under the plan's read lock, and only while
        // it is still the plan of the request (P19).
        let view = o.view.clone();
        if server && !o.plan_served() {
            let current = view.read().await;
            if current.gen == o.gen {
                o.serve_plan(t, timeout).await;
            }
            drop(current);
        }
        let req = match next {
            Next::Req(r) => r,
            Next::Remote(Err(DriverError::Transport(e))) => return Some(e),
            Next::Remote(Err(e)) => {
                debug!(conn = %o.conn, "remote request: {e}");
                continue;
            }
            Next::Remote(Ok(())) => {
                // Answered against the plan in force, which the server has:
                // a re-plan cannot come between (the read lock), and one
                // that came while the request waited makes it busy.
                let current = view.read().await;
                o.adopt(&current);
                if !o.plan_served() {
                    o.serve_plan(t, timeout).await;
                }
                let r = D::apply_remote(t, current.since);
                o.record(t, r.dev.as_deref(), false);
                o.publish_changed(t).await;
                drop(current);
                // The remote side gets its answer once the tree shows it.
                if let Some(done) = r.done {
                    done();
                }
                continue;
            }
        };
        match req {
            Req::Serve => {}
            Req::Poll {
                dev,
                group,
                gen,
                inflight,
            } => {
                let devs = o.devs.clone();
                let planned = (gen == o.gen)
                    .then(|| devs.get(&dev))
                    .flatten()
                    .and_then(|d| d.groups.get(group).map(|g| (d, g)));
                let Some((d, g)) = planned else {
                    inflight.store(POLL_IDLE, Ordering::Release);
                    continue;
                };
                inflight.store(POLL_RUNNING, Ordering::Release);
                let bound = D::poll_timeout(cfg, &g.plan);
                let r = tokio::time::timeout(bound, guarded(D::poll(t, &d.cfg, &g.plan))).await;
                inflight.store(POLL_IDLE, Ordering::Release);
                let r = match r {
                    Ok(Err(p)) => return Some(p),
                    Ok(Ok(v)) => Ok(v),
                    Err(e) => Err(e),
                };
                o.record(t, Some(&dev), r.is_err());
                let current = view.read().await;
                if current.gen != gen {
                    debug!(%dev, "poll results dropped: the plan changed");
                    if let Ok(results) = r {
                        if let Some(e) = transport_error(&results) {
                            return Some(e);
                        }
                    }
                    continue;
                }
                match r {
                    Err(_) => o.dev_miss(&dev, "poll timed out", true).await,
                    Ok(results) => {
                        if let Err(e) = o.publish_results(&dev, results).await {
                            return Some(e);
                        }
                    }
                }
                drop(current);
            }
            Req::Ping { dev, gen, inflight } => {
                let devs = o.devs.clone();
                let Some(d) = (gen == o.gen).then(|| devs.get(&dev)).flatten() else {
                    inflight.store(false, Ordering::Release);
                    continue;
                };
                let r = tokio::time::timeout(timeout, guarded(D::ping(t, &d.cfg))).await;
                inflight.store(false, Ordering::Release);
                let r = match r {
                    Ok(Err(p)) => return Some(p),
                    Ok(Ok(v)) => Ok(v),
                    Err(e) => Err(e),
                };
                o.record(t, Some(&dev), r.is_err());
                if let Ok(Err(DriverError::Transport(e))) = r {
                    return Some(e);
                }
                let current = view.read().await;
                if current.gen != gen {
                    continue;
                }
                match r {
                    Err(_) => o.dev_miss(&dev, "ping timed out", false).await,
                    Ok(Ok(())) | Ok(Err(DriverError::Point(_))) => o.ping_ok(&dev).await,
                    Ok(Err(DriverError::Device(e))) => o.dev_miss(&dev, &e, false).await,
                    Ok(Err(DriverError::Transport(_))) => {}
                }
                drop(current);
            }
            Req::Write {
                dev,
                point,
                value,
                gen,
                deadline,
                reply,
            } => {
                if reply.is_closed() || tokio::time::Instant::now() >= deadline {
                    // The caller already got `timeout`: a late write would
                    // change the device behind its back (P13).
                    debug!(%dev, %point, "write dropped: its caller stopped waiting");
                    let _ = reply.send(Err(LinkError::timeout("write not started in time")));
                    continue;
                }
                if gen != o.gen {
                    // The point was re-planned (edited, replaced) after the
                    // set came: never write with what replaced it (P19).
                    debug!(%dev, %point, "write dropped: the plan changed");
                    let _ = reply.send(Err(LinkError::new(
                        Status::Busy,
                        "the connection was reconfigured: not written, try again",
                    )));
                    continue;
                }
                let devs = o.devs.clone();
                let target = devs
                    .get(&dev)
                    .and_then(|d| d.points.get(&point).map(|p| (d, p)));
                let Some((d, p)) = target else {
                    let _ = reply.send(Err(LinkError::not_found(format!("{dev}/{point}"))));
                    continue;
                };
                let bound = D::write_timeout(cfg, p);
                let r = tokio::time::timeout(bound, D::write(t, &d.cfg, &point, p, &value)).await;
                o.record(t, Some(&dev), r.is_err());
                let r = match r {
                    Err(_) => Err(DriverError::Device("write timed out".into())),
                    Ok(r) => r,
                };
                let outcome = match r {
                    Ok(()) => Ok(()),
                    Err(DriverError::Point(e)) => Err(LinkError::invalid_parameter(e)),
                    Err(DriverError::Device(e)) => Err(LinkError::timeout(e)),
                    Err(DriverError::Transport(e)) => {
                        let _ = reply.send(Err(LinkError::new(Status::Disconnected, e.clone())));
                        return Some(e);
                    }
                };
                if server {
                    // The value set is the value served: publish what the
                    // server now serves (no read-back).
                    let current = view.read().await;
                    if current.gen == gen {
                        o.publish_changed(t).await;
                    } else {
                        let _ = D::take_changed(t);
                    }
                    drop(current);
                    let _ = reply.send(outcome);
                    continue;
                }
                // Read back: the tree shows what the device holds (after a
                // failed write too, when the driver asks: a write may have
                // gone through in part).
                if outcome.is_ok() || D::read_back_on_error(&d.cfg) {
                    let plan = D::plan(&d.cfg, &[(point.clone(), p.clone())]);
                    let bound = D::poll_timeout(cfg, &plan);
                    let r = tokio::time::timeout(bound, D::poll(t, &d.cfg, &plan)).await;
                    o.record(t, Some(&dev), r.is_err());
                    if let Ok(results) = r {
                        let current = view.read().await;
                        let published = if current.gen == gen {
                            o.publish_results(&dev, results).await
                        } else {
                            transport_error(&results).map_or(Ok(()), Err)
                        };
                        drop(current);
                        if let Err(e) = published {
                            let _ = reply.send(outcome);
                            return Some(e);
                        }
                    }
                }
                let _ = reply.send(outcome);
            }
            Req::Invoke {
                dev,
                action,
                args,
                gen,
                bound,
                deadline,
                reply,
            } => {
                let left = deadline.saturating_duration_since(tokio::time::Instant::now());
                if left.is_zero() {
                    // The caller gave up while the action waited its turn.
                    let _ = reply.send(Err(LinkError::timeout("action not started in time")));
                    continue;
                }
                if gen != o.gen {
                    // Asked of the plan before a re-plan (an edit, an
                    // overwrite): never run it on what replaced it (P19).
                    debug!(%action, "action dropped: the plan changed");
                    let _ = reply.send(Err(LinkError::new(
                        Status::Busy,
                        "the connection was reconfigured: not run, try again",
                    )));
                    continue;
                }
                let devs = o.devs.clone();
                let target = match &dev {
                    None => Target::Connection,
                    Some(id) => match devs.get(id) {
                        Some(d) => Target::Device { id, dev: &d.cfg },
                        None => {
                            let e = LinkError::new(
                                Status::Disconnected,
                                format!("device {id} is not running"),
                            );
                            let _ = reply.send(Err(e));
                            continue;
                        }
                    },
                };
                let bound = bound.unwrap_or(timeout).min(left);
                let r =
                    tokio::time::timeout(bound, D::invoke(t, cfg, target, &action, &args)).await;
                o.record(t, dev.as_deref(), r.is_err());
                match r {
                    Err(_) => {
                        let _ = reply.send(Err(LinkError::timeout(format!(
                            "action {action} timed out"
                        ))));
                    }
                    // The transport broke: reconnect.
                    Ok(Err(e)) if e.status == Status::Disconnected => {
                        let why = e.message.clone();
                        let _ = reply.send(Err(e));
                        return Some(why);
                    }
                    Ok(r) => {
                        let _ = reply.send(r);
                    }
                }
            }
        }
    }
}

impl<D: Driver> Link for Framework<D> {
    const NAME: &'static str = D::NAME;
    const VERSION: &'static str = D::VERSION;
    type Config = Tree;

    async fn start(tree: Tree, ctx: LinkCtx) -> Result<Self> {
        // Runtime edits kept in `data_dir` win over the bootstrap params
        // they were made on; new bootstrap params win over them.
        let persist = Persist::open(&ctx, &tree.0);
        let source = persist.as_ref().and_then(Persist::load).unwrap_or(tree.0);
        let mut top = map_of(&source);
        // Default: always poll; only an explicit `false` gates on subscribers.
        let poll_unsubscribed = !matches!(
            take(&mut top, "poll_unsubscribed"),
            Some(Value::Bool(false))
        );
        let conns_raw = take(&mut top, "connections")
            .map(|v| map_of(&v))
            .unwrap_or_default();
        if let Some(k) = top.keys().next() {
            return Err(LinkError::invalid_parameter(format!(
                "params.{k}: unknown field"
            )));
        }
        let mut fw = Framework::<D> {
            ctx,
            conns: BTreeMap::new(),
            poll_unsubscribed,
            persist,
        };
        for (cn, cv) in conns_raw {
            let entry = load_conn::<D>(&cn, &cv)?;
            fw.conns.insert(cn, entry);
        }
        fw.declare_root().await?;
        let names: Vec<String> = fw.conns.keys().cloned().collect();
        for cn in &names {
            fw.declare_conn_tree(cn).await?;
        }
        for cn in &names {
            fw.bring_up(cn).await;
        }
        Ok(fw)
    }

    async fn on_set(&mut self, path: &str, value: Value, _who: &Caller) -> Result<()> {
        let parts: Vec<String> = path.split('/').map(str::to_owned).collect();
        let At::Point(conn, dev, point) = self.resolve(&parts)? else {
            return Err(LinkError::not_supported("only points take values"));
        };
        let run = self
            .conns
            .get(conn.as_str())
            .and_then(|c| c.run.as_ref())
            .ok_or_else(|| LinkError::new(Status::Disconnected, "connection not running"))?;
        // The set runs on the link task: it never waits behind a `write` or
        // `config` driver action (up to its `timeout_ms`, minutes for a
        // scan), which would hold every other connection's sets, actions
        // and edits. Nothing is lost: such a write would miss its deadline
        // and be dropped (P13). A `read` action is one bounded request
        // (P32): the set queues behind it, so `read` callers cannot lock
        // writers out.
        if run.acting.load(Ordering::Acquire) == SLOT_HOLD {
            return Err(LinkError::new(
                Status::Busy,
                "an action runs on this connection: not written, try again",
            ));
        }
        // The SDK bounds this call from now (`LinkConfig::driver_timeout`).
        let deadline = tokio::time::Instant::now() + self.ctx.driver_timeout();
        let (reply, rx) = oneshot::channel();
        // Never wait for room in the queue (final review I1).
        run.tx
            .try_send(Req::Write {
                dev: dev.clone(),
                point: point.clone(),
                value,
                gen: run.gen,
                deadline,
                reply,
            })
            .map_err(|e| match e {
                mpsc::error::TrySendError::Full(_) => LinkError::new(
                    Status::Busy,
                    "connection busy: too many requests queued, not written",
                ),
                mpsc::error::TrySendError::Closed(_) => {
                    LinkError::new(Status::Disconnected, "connection stopped")
                }
            })?;
        rx.await
            .map_err(|_| LinkError::new(Status::Disconnected, "connection stopped"))?
    }

    async fn on_invoke(
        &mut self,
        path: &str,
        action: &str,
        args: Value,
        _who: &Caller,
        out: ReplySink,
    ) -> Result<()> {
        let parts: Vec<String> = if path.is_empty() {
            Vec::new()
        } else {
            path.split('/').map(str::to_owned).collect()
        };
        if matches!(action, "copy" | "import") {
            let at = self.resolve(&parts)?;
            // Both save the tree as soon as it changed (before any node is
            // declared), so a call cut later leaves a whole tree on disk.
            let reply = if action == "copy" {
                self.copy(&at, &args).await?
            } else {
                self.import(&at, &args).await?
            };
            return out.reply(reply).await;
        }
        if parts.is_empty() && root_imports::<D>().iter().any(|(n, _)| *n == action) {
            let reply = self.root_import(action, &args).await?;
            return out.reply(reply).await;
        }
        let changes =
            action.starts_with("add_") || matches!(action, "edit" | "remove" | "start" | "stop");
        self.invoke_action(&parts, action, args, out).await?;
        if changes {
            self.save()?;
        }
        Ok(())
    }

    async fn stop(&mut self) {
        let names: Vec<String> = self.conns.keys().cloned().collect();
        for n in names {
            self.tear_down(&n).await;
        }
    }
}

impl<D: Driver> Framework<D> {
    /// Keep the tree for a restart (with a `data_dir`).
    fn save(&self) -> Result<()> {
        if let Some(p) = &self.persist {
            p.save(&self.full_tree()).map_err(|e| {
                LinkError::internal(format!("applied, but not saved for a restart: {e}"))
            })?;
        }
        Ok(())
    }

    /// Save a change made in memory and not yet declared (a copy, an
    /// import); when the save fails, `undo` puts the tree back, so memory
    /// never runs ahead of the disk (final review M5).
    fn save_or_undo(&mut self, undo: impl FnOnce(&mut Self)) -> Result<()> {
        if let Some(p) = &self.persist {
            if let Err(e) = p.save(&self.full_tree()) {
                undo(self);
                return Err(LinkError::internal(format!(
                    "not saved for a restart, nothing changed: {e}"
                )));
            }
        }
        Ok(())
    }
}

/// The node an action or a set names.
enum At<'a> {
    Root,
    Conn(&'a String),
    Dev(&'a String, &'a String),
    Folder(&'a String, &'a String, Folder),
    Point(&'a String, &'a String, &'a String),
}

/// A connection of the tree (`{..Conn, kind?, enabled?, devices?}`).
fn load_conn<D: Driver>(cn: &str, cv: &Value) -> Result<ConnEntry<D>> {
    valid_name(cn)?;
    let mut cm = map_of(cv);
    let enabled = is_enabled(&mut cm);
    let devs_raw = take(&mut cm, "devices")
        .map(|v| map_of(&v))
        .unwrap_or_default();
    let mut devices = BTreeMap::new();
    for (dn, dv) in devs_raw {
        let entry = load_dev::<D>(cn, &dn, &dv)?;
        devices.insert(dn, entry);
    }
    Ok(ConnEntry {
        slot: Slot::parse(Value::Map(cm)),
        enabled,
        devices,
        run: None,
    })
}

/// A device of the tree (`{..Dev, kind?, enabled?, points, folders?}`).
fn load_dev<D: Driver>(cn: &str, dn: &str, dv: &Value) -> Result<DevEntry<D>> {
    valid_name(dn)?;
    let mut dm = map_of(dv);
    let enabled = is_enabled(&mut dm);
    let mut points = BTreeMap::new();
    let mut folders = BTreeSet::new();
    load_branch::<D>(
        &format!("{cn}/{dn}"),
        &[],
        &mut dm,
        &mut points,
        &mut folders,
    )?;
    Ok(DevEntry {
        slot: Slot::parse(Value::Map(dm)),
        enabled,
        token: run_token(),
        points,
        folders,
    })
}

/// Load `{points, folders?}` of `folder` from `m` (the device map, or a
/// folder's), taking those keys out: the points into `points` (an id twice
/// on a device is an error), folders only with [`Driver::FOLDERS`].
fn load_branch<D: Driver>(
    dev: &str,
    folder: &[String],
    m: &mut Map,
    points: &mut BTreeMap<String, PointEntry<D::Point>>,
    folders: &mut BTreeSet<Folder>,
) -> Result<()> {
    let at = below(dev, folder);
    let pts = take(m, "points").map(|v| map_of(&v)).unwrap_or_default();
    for (pn, pv) in pts {
        valid_name(&pn)?;
        if let Some(p) = points.get(&pn) {
            return Err(LinkError::invalid_parameter(format!(
                "{at}: point id {pn:?} is used twice on the device (also at {})",
                below(dev, &p.folder)
            )));
        }
        let entry = PointEntry {
            slot: Slot::parse(pv),
            folder: folder.to_vec(),
        };
        points.insert(pn, entry);
    }
    if !D::FOLDERS {
        return Ok(());
    }
    let subs = take(m, "folders").map(|v| map_of(&v)).unwrap_or_default();
    for (fname, fv) in subs {
        valid_name(&fname)?;
        let f = child(folder, &fname);
        if f.len() > MAX_FOLDER_DEPTH {
            return Err(LinkError::invalid_parameter(format!(
                "{at}/{fname}: folders nest at most {MAX_FOLDER_DEPTH} deep"
            )));
        }
        if points.get(&fname).is_some_and(|p| p.folder == folder) {
            return Err(LinkError::invalid_parameter(format!(
                "{at}/{fname}: a point and a folder of that name"
            )));
        }
        folders.insert(f.clone());
        let mut fm = map_of(&fv);
        load_branch::<D>(dev, &f, &mut fm, points, folders)?;
        if let Some(k) = fm.keys().next() {
            return Err(LinkError::invalid_parameter(format!(
                "{at}/{fname}.{k}: unknown field (a folder has points and folders)"
            )));
        }
    }
    Ok(())
}

impl<D: Driver> Framework<D> {
    /// `add_*`: a connection (below the root), device (below a connection)
    /// or point (below a device or folder) of `kind`.
    async fn add_child(&mut self, at: &At<'_>, kind: &str, args: &Value) -> Result<()> {
        let (name, params) = split_name(args)?;
        match at {
            At::Root => {
                if self.conns.contains_key(&name) {
                    return Err(LinkError::invalid_parameter(format!("{name} exists")));
                }
                let cfg = D::Conn::from_kind_value(kind, &params)?;
                self.conns.insert(
                    name.clone(),
                    ConnEntry {
                        slot: Slot::valid(cfg),
                        enabled: true,
                        devices: BTreeMap::new(),
                        run: None,
                    },
                );
                self.declare_conn(&name).await?;
                self.bring_up(&name).await;
            }
            At::Conn(conn) => {
                diag_reserved::<D>(&name)?;
                let cfg = D::Dev::from_kind_value(kind, &params)?;
                let c = self.conn_mut(conn)?;
                if c.devices.contains_key(&name) {
                    return Err(LinkError::invalid_parameter(format!("{name} exists")));
                }
                c.devices.insert(
                    name.clone(),
                    DevEntry {
                        slot: Slot::valid(cfg),
                        enabled: true,
                        token: run_token(),
                        points: BTreeMap::new(),
                        folders: BTreeSet::new(),
                    },
                );
                self.declare_dev(conn, &name).await?;
                set_status(&self.ctx, &format!("{conn}/{name}"), NodeState::New, None).await;
                self.reset_diag(conn, &name);
                self.replan(conn).await;
            }
            At::Dev(conn, dev) | At::Folder(conn, dev, _) => {
                let folder = match at {
                    At::Folder(_, _, f) => f.clone(),
                    _ => Folder::new(),
                };
                diag_reserved::<D>(&name)?;
                let cfg = D::Point::from_kind_value(kind, &params)?;
                let d = self
                    .conn_mut(conn)?
                    .devices
                    .get_mut(dev.as_str())
                    .ok_or_else(|| LinkError::not_found((*dev).clone()))?;
                if let Some(p) = d.points.get(&name) {
                    // Ids are unique on the device: plans and writes go by id.
                    return Err(LinkError::invalid_parameter(if p.folder == folder {
                        format!("{name} exists")
                    } else {
                        format!("{name} exists on this device (at {})", d.rel(&name))
                    }));
                }
                if d.taken(&folder, &name) {
                    return Err(LinkError::invalid_parameter(format!(
                        "{name} exists (a folder)"
                    )));
                }
                let entry = PointEntry {
                    slot: Slot::valid(cfg),
                    folder,
                };
                d.points.insert(name.clone(), entry);
                self.declare_point(conn, dev, &name).await?;
                self.replan(conn).await;
            }
            At::Point(..) => return Err(LinkError::not_supported("add below a point")),
        }
        Ok(())
    }

    /// `add_folder {name}` below a device or folder.
    async fn add_folder(
        &mut self,
        conn: &str,
        dev: &str,
        folder: Folder,
        args: &Value,
    ) -> Result<()> {
        let (name, rest) = split_name(args)?;
        if let Some(k) = map_of(&rest).keys().next() {
            return Err(LinkError::invalid_parameter(format!(
                "{k}: unknown field (a folder has a name only)"
            )));
        }
        folder_name::<D>(&name)?;
        if folder.len() >= MAX_FOLDER_DEPTH {
            return Err(LinkError::invalid_parameter(format!(
                "folders nest at most {MAX_FOLDER_DEPTH} deep"
            )));
        }
        let d = self
            .conn_mut(conn)?
            .devices
            .get_mut(dev)
            .ok_or_else(|| LinkError::not_found(dev.to_owned()))?;
        if d.taken(&folder, &name) {
            return Err(LinkError::invalid_parameter(format!("{name} exists")));
        }
        let f = child(&folder, &name);
        d.folders.insert(f.clone());
        self.declare_folder(conn, dev, &f).await
    }

    async fn invoke_action(
        &mut self,
        parts: &[String],
        action: &str,
        args: Value,
        out: ReplySink,
    ) -> Result<()> {
        let path = parts.join("/");
        if let Some(found) = self.find_action(parts, action) {
            return self.run_action(found, action, args, out).await;
        }
        let at = self.resolve(parts)?;
        match (&at, action) {
            (At::Root, "export") => return out.reply(self.export()).await,
            (At::Conn(..) | At::Dev(..) | At::Folder(..), "export") => {
                return out.reply(self.export_branch(&at)?).await
            }
            (At::Root, "rescan") if D::RESCAN.is_some() => {
                return out.reply(self.rescan().await?).await
            }
            (At::Dev(conn, dev), ADD_FOLDER) if D::FOLDERS => {
                self.add_folder(conn, dev, Folder::new(), &args).await?;
            }
            (At::Folder(conn, dev, f), ADD_FOLDER) => {
                self.add_folder(conn, dev, f.clone(), &args).await?;
            }
            _ if action.starts_with("add_") => {
                let Some(kind) = Self::add_kind(&at, action) else {
                    return Err(LinkError::not_supported(format!("{path}/~act/{action}")));
                };
                self.add_child(&at, kind, &args).await?;
            }
            (At::Conn(conn), "edit") => {
                // Validate first; a rejected edit changes nothing.
                let slot = &self.conn_mut(conn)?.slot;
                let (old, kind, schema) = (slot.raw.clone(), slot.kind.clone(), slot.schema());
                let cfg = D::Conn::from_kind_value(&kind, &keep_secrets(&schema, &old, &args))?;
                let c = self.conn_mut(conn)?;
                if c.slot.cfg.as_ref() == Some(&cfg) {
                    return Ok(());
                }
                self.tear_down(conn).await;
                self.conn_mut(conn)?.slot = Slot::valid(cfg);
                self.declare_conn(conn).await?;
                self.bring_up(conn).await;
            }
            (At::Dev(conn, dev), "edit") => {
                let (old, kind, schema) = self
                    .conn_mut(conn)?
                    .devices
                    .get(dev.as_str())
                    .map(|d| (d.slot.raw.clone(), d.slot.kind.clone(), d.slot.schema()))
                    .ok_or_else(|| LinkError::not_found((*dev).clone()))?;
                let cfg = D::Dev::from_kind_value(&kind, &keep_secrets(&schema, &old, &args))?;
                let d = self
                    .conn_mut(conn)?
                    .devices
                    .get_mut(dev.as_str())
                    .ok_or_else(|| LinkError::not_found((*dev).clone()))?;
                if d.slot.cfg.as_ref() == Some(&cfg) {
                    return Ok(());
                }
                d.slot = Slot::valid(cfg);
                d.token = run_token();
                self.declare_dev(conn, dev).await?;
                self.replan(conn).await;
            }
            (At::Point(conn, dev, pt), "edit") => {
                let (old, kind, schema) = self
                    .conn_mut(conn)?
                    .devices
                    .get(dev.as_str())
                    .and_then(|d| d.points.get(pt.as_str()))
                    .map(|p| (p.slot.raw.clone(), p.slot.kind.clone(), p.slot.schema()))
                    .ok_or_else(|| LinkError::not_found((*pt).clone()))?;
                let cfg = D::Point::from_kind_value(&kind, &keep_secrets(&schema, &old, &args))?;
                let p = self
                    .conn_mut(conn)?
                    .devices
                    .get_mut(dev.as_str())
                    .and_then(|d| d.points.get_mut(pt.as_str()))
                    .ok_or_else(|| LinkError::not_found((*pt).clone()))?;
                if p.slot.cfg.as_ref() == Some(&cfg) {
                    return Ok(());
                }
                p.slot = Slot::valid(cfg);
                self.declare_point(conn, dev, pt).await?;
                self.replan(conn).await;
            }
            (At::Conn(conn), "remove") => {
                self.conn_mut(conn)?;
                self.tear_down(conn).await;
                self.conns.remove(conn.as_str());
                self.ctx.remove_node(conn).await?;
            }
            (At::Dev(conn, dev), "remove") => {
                self.conn_mut(conn)?
                    .devices
                    .remove(dev.as_str())
                    .ok_or_else(|| LinkError::not_found((*dev).clone()))?;
                self.ctx.remove_node(&format!("{conn}/{dev}")).await?;
                if let Some(run) = self.conns.get(conn.as_str()).and_then(|c| c.run.as_ref()) {
                    diag::remove_dev(&run.book, dev);
                }
                self.replan(conn).await;
            }
            (At::Folder(conn, dev, folder), "remove") => {
                // The folder with everything in it; polling stops with the
                // new plan, the saved tree follows (`on_invoke`).
                let d = self
                    .conn_mut(conn)?
                    .devices
                    .get_mut(dev.as_str())
                    .ok_or_else(|| LinkError::not_found((*dev).clone()))?;
                d.folders.retain(|f| !f.starts_with(folder));
                d.points.retain(|_, p| !p.folder.starts_with(folder));
                self.ctx
                    .remove_node(&below(&format!("{conn}/{dev}"), folder))
                    .await?;
                self.replan(conn).await;
            }
            (At::Point(conn, dev, pt), "remove") => {
                let d = self
                    .conn_mut(conn)?
                    .devices
                    .get_mut(dev.as_str())
                    .ok_or_else(|| LinkError::not_found((*pt).clone()))?;
                let rel = d.rel(pt);
                d.points
                    .remove(pt.as_str())
                    .ok_or_else(|| LinkError::not_found((*pt).clone()))?;
                self.ctx.remove_node(&format!("{conn}/{dev}/{rel}")).await?;
                self.replan(conn).await;
            }
            (At::Conn(conn), "restart") => {
                self.conn_mut(conn)?;
                self.tear_down(conn).await;
                self.bring_up(conn).await;
            }
            (At::Dev(conn, dev), "restart") => {
                self.dev_mut(conn, dev)?.token = run_token();
                self.reset_diag(conn, dev);
                self.replan(conn).await;
            }
            (At::Conn(conn), a @ ("start" | "stop")) => {
                let on = a == "start";
                if self.conn_mut(conn)?.enabled == on {
                    return Ok(());
                }
                self.tear_down(conn).await;
                self.conn_mut(conn)?.enabled = on;
                self.declare_run_toggle(conn, on).await?;
                self.bring_up(conn).await;
            }
            (At::Dev(conn, dev), a @ ("start" | "stop")) => {
                let on = a == "start";
                let d = self
                    .conn_mut(conn)?
                    .devices
                    .get_mut(dev.as_str())
                    .ok_or_else(|| LinkError::not_found((*dev).clone()))?;
                if d.enabled == on {
                    return Ok(());
                }
                d.enabled = on;
                if on {
                    d.token = run_token();
                }
                let base = format!("{conn}/{dev}");
                self.declare_run_toggle(&base, on).await?;
                if on {
                    // `New` first: the owner, on the new plan, starts from
                    // scratch for this device and publishes `Connected`.
                    set_status(&self.ctx, &base, NodeState::New, None).await;
                    self.reset_diag(conn, dev);
                    self.replan(conn).await;
                } else {
                    // The plan first: nothing of it publishes after the mark.
                    self.replan(conn).await;
                    set_status(&self.ctx, &base, NodeState::Stopped, None).await;
                    let paths = Self::point_paths(
                        conn,
                        dev,
                        &self.conns[conn.as_str()].devices[dev.as_str()],
                    );
                    mark(&self.ctx, paths, Quality::Bad, QUAL_DISCONNECTED).await;
                }
            }
            _ => return Err(LinkError::not_supported(format!("{path}/~act/{action}"))),
        }
        Ok(())
    }
}

/// `{name}` and nothing else (a `copy`).
fn copy_name(args: &Value) -> Result<String> {
    let (name, rest) = split_name(args)?;
    if let Some(k) = map_of(&rest).keys().next() {
        return Err(LinkError::invalid_parameter(format!(
            "{k}: unknown field (copy takes a name)"
        )));
    }
    Ok(name)
}

/// `path` with its prefix `from` replaced by `to`.
fn rebase(path: &[String], from: &[String], to: &[String]) -> Folder {
    let mut f = to.to_vec();
    f.extend_from_slice(&path[from.len()..]);
    f
}

/// `<id>_<n>` with the smallest `n` ≥ 2 that `taken` does not refuse.
fn fresh_id(id: &str, taken: impl Fn(&str) -> bool) -> String {
    (2u64..)
        .map(|n| format!("{id}_{n}"))
        .find(|c| !taken(c))
        .expect("a free id")
}

/// A stand-in for a secret left out of an import, so that every other
/// param is still checked like `add_*` would.
fn stand_in(s: &ParamSpec) -> Value {
    match s.ty {
        TypeCode::Number => Value::Float(match (s.min, s.max) {
            (Some(lo), _) => lo,
            (None, Some(hi)) if hi < 0.0 => hi,
            _ => 0.0,
        }),
        TypeCode::Bool => Value::Bool(false),
        TypeCode::Enum => Value::Str(s.enum_values.first().copied().unwrap_or("").into()),
        _ => Value::Str("x".into()),
    }
}

/// An imported node's params at `at`, validated like `add_*`, without
/// secrets: every secret the text names, and every required one, is listed
/// in `reenter` as `<at>.<param>` (it is entered again with `edit`).
fn import_params<P: Params>(at: &str, params: &Map, reenter: &mut Vec<String>) -> Result<Value> {
    let bad = |e: LinkError| LinkError::invalid_parameter(format!("{at}: {}", e.message));
    let mut m = params.clone();
    let kind = match multi_kind::<P>().then(|| m.remove("kind")).flatten() {
        None => String::new(),
        Some(Value::Str(k)) => k,
        Some(_) => {
            return Err(LinkError::invalid_parameter(format!(
                "{at}: kind: expected a name"
            )))
        }
    };
    let resolved = if kind.is_empty() {
        P::kinds().first().map(|k| k.id).unwrap_or("").to_owned()
    } else {
        kind
    };
    let schema = P::kind_schema(&resolved).map_err(bad)?;
    let mut check = m.clone();
    for s in schema.iter().filter(|s| s.secret) {
        let given = m.remove(s.name).is_some();
        check.remove(s.name);
        if given || s.default.is_none() {
            reenter.push(format!("{at}.{}", s.name));
        }
        if s.default.is_none() {
            check.insert(s.name.to_owned(), stand_in(s));
        }
    }
    P::from_kind_value(&resolved, &Value::Map(check)).map_err(bad)?;
    if multi_kind::<P>() {
        m.insert("kind".into(), Value::Str(resolved));
    }
    Ok(Value::Map(m))
}

/// A connection node as a tree map (`load_conn`).
fn conn_tree<D: Driver>(n: &Node, at: &str, reenter: &mut Vec<String>) -> Result<Value> {
    let mut m = map_of(&import_params::<D::Conn>(at, &n.params, reenter)?);
    m.insert("enabled".into(), Value::Bool(n.enabled));
    let mut devs = Map::new();
    for c in &n.children {
        let t = dev_tree::<D>(c, &format!("{at}/{}", c.name), reenter)?;
        if devs.insert(c.name.clone(), t).is_some() {
            return Err(twice(at, &c.name));
        }
    }
    m.insert("devices".into(), Value::Map(devs));
    Ok(Value::Map(m))
}

/// A device node as a tree map (`load_dev`).
fn dev_tree<D: Driver>(n: &Node, at: &str, reenter: &mut Vec<String>) -> Result<Value> {
    let mut m = map_of(&import_params::<D::Dev>(at, &n.params, reenter)?);
    m.insert("enabled".into(), Value::Bool(n.enabled));
    m.extend(folder_tree::<D>(n, at, reenter)?);
    Ok(Value::Map(m))
}

/// The children of a device or folder node as `{points, folders?}`
/// (`load_branch`).
fn folder_tree<D: Driver>(n: &Node, at: &str, reenter: &mut Vec<String>) -> Result<Map> {
    let (mut points, mut folders) = (Map::new(), Map::new());
    for c in &n.children {
        let here = format!("{at}/{}", c.name);
        let (into, t) = match c.level {
            branch::Level::Point => (
                &mut points,
                import_params::<D::Point>(&here, &c.params, reenter)?,
            ),
            _ => (
                &mut folders,
                Value::Map(folder_tree::<D>(c, &here, reenter)?),
            ),
        };
        if into.insert(c.name.clone(), t).is_some() {
            return Err(twice(at, &c.name));
        }
    }
    let mut m = Map::new();
    m.insert("points".into(), Value::Map(points));
    if !folders.is_empty() {
        m.insert("folders".into(), Value::Map(folders));
    }
    Ok(m)
}

/// Ruling P17: an overwritten connection keeps its sealed secrets for the
/// imported one while the destination stays the same (the `keep_secrets`
/// rule of `edit`); the kept ones leave `reenter`.
fn keep_conn_secrets<P: Params>(
    old: &Slot<P>,
    new: &mut Slot<P>,
    at: &str,
    reenter: &mut Vec<String>,
) {
    if old.kind != new.kind {
        return;
    }
    let schema = new.schema();
    let merged = map_of(&keep_secrets(&schema, &old.raw, &new.raw));
    let kept: Vec<String> = schema
        .iter()
        .filter(|s| s.secret && merged.get(s.name).is_some_and(|v| !blank(v)))
        .map(|s| format!("{at}.{}", s.name))
        .collect();
    if kept.is_empty() {
        return;
    }
    reenter.retain(|r| !kept.contains(r));
    let mut m = merged;
    if multi_kind::<P>() {
        m.insert("kind".into(), Value::Str(new.kind.clone()));
    }
    *new = Slot::parse(Value::Map(m));
}

/// An imported connection `node` named `name` as it will load, checked like
/// `add_*` (secrets left out, listed in `reenter`).
fn new_conn<D: Driver>(node: &Node, name: &str, reenter: &mut Vec<String>) -> Result<ConnEntry<D>> {
    let tree = conn_tree::<D>(node, name, reenter)?;
    let entry = load_conn::<D>(name, &tree)?;
    for (dn, d) in &entry.devices {
        diag_reserved::<D>(dn)?;
        check_new::<D>(d.points.keys(), &d.folders)?;
    }
    Ok(entry)
}

/// The keys of `n` (at `at`, its parent's key) and of every node below it.
fn node_keys(n: &Node, at: &str, out: &mut Vec<Value>) {
    let key = if at.is_empty() {
        n.name.clone()
    } else {
        format!("{at}/{}", n.name)
    };
    out.push(Value::Str(key.clone()));
    for c in &n.children {
        node_keys(c, &key, out);
    }
}

fn twice(at: &str, name: &str) -> LinkError {
    LinkError::invalid_parameter(format!("{at}/{name}: twice in the branch"))
}

fn exists_err(name: &str) -> LinkError {
    LinkError::invalid_parameter(format!("{name} exists (overwrite: true replaces it)"))
}

/// The names that `add_*` refuses but loading keeps (a stored tree with
/// them still loads): new points and devices may not take a diagnostics
/// leaf name, new folders no action name either.
fn check_new<'a, D: Driver>(
    points: impl IntoIterator<Item = &'a String>,
    folders: impl IntoIterator<Item = &'a Folder>,
) -> Result<()> {
    for p in points {
        diag_reserved::<D>(p)?;
    }
    for f in folders {
        if let Some(last) = f.last() {
            folder_name::<D>(last)?;
        }
    }
    Ok(())
}

impl<D: Driver> Framework<D> {
    fn dev_mut(&mut self, conn: &str, dev: &str) -> Result<&mut DevEntry<D>> {
        self.conn_mut(conn)?
            .devices
            .get_mut(dev)
            .ok_or_else(|| LinkError::not_found(format!("{conn}/{dev}")))
    }

    /// `export` of a connection, device or folder: `{json}`.
    fn export_branch(&self, at: &At<'_>) -> Result<Value> {
        let not_found = |p: String| LinkError::not_found(p);
        let dev = |c: &str, d: &str| {
            self.conns
                .get(c)
                .and_then(|e| e.devices.get(d))
                .ok_or_else(|| not_found(format!("{c}/{d}")))
        };
        let node = match at {
            At::Conn(c) => self
                .conns
                .get(c.as_str())
                .ok_or_else(|| not_found((*c).clone()))?
                .node(c),
            At::Dev(c, d) => dev(c, d)?.node(d),
            At::Folder(c, d, f) => Node {
                level: branch::Level::Folder,
                name: f.last().cloned().unwrap_or_default(),
                params: Map::new(),
                enabled: true,
                children: dev(c, d)?.children(f),
            },
            At::Root | At::Point(..) => return Err(LinkError::not_supported("export")),
        };
        let mut m = Map::new();
        m.insert("json".into(), Value::Str(branch::to_text(D::NAME, &node)?));
        Ok(Value::Map(m))
    }

    /// `copy {name}`: a deep copy beside the node, under a new id. A copied
    /// connection or device starts stopped (it would poll the same
    /// equipment). The copy keeps the sealed secrets: same link, same
    /// destination (an `edit` of the destination drops them, `keep_secrets`).
    /// A folder's points get fresh ids (`<id>_<n>`: ids are unique on the
    /// device); the reply says which: `{name, renamed?: {old: new}}`.
    async fn copy(&mut self, at: &At<'_>, args: &Value) -> Result<Value> {
        let name = copy_name(args)?;
        let mut reply = Map::new();
        match at {
            At::Root => return Err(LinkError::not_supported("copy of the root")),
            At::Conn(conn) => {
                let src = self
                    .conns
                    .get(conn.as_str())
                    .ok_or_else(|| LinkError::not_found((*conn).clone()))?;
                if self.conns.contains_key(&name) {
                    return Err(LinkError::invalid_parameter(format!("{name} exists")));
                }
                branch::check_copy(1 + src.devices.values().map(DevEntry::count).sum::<usize>())?;
                let entry = ConnEntry {
                    slot: src.slot.clone(),
                    enabled: false,
                    devices: src.devices.clone(),
                    run: None,
                };
                self.conns.insert(name.clone(), entry);
                self.save_or_undo(|fw| {
                    fw.conns.remove(&name);
                })?;
                self.declare_conn_tree(&name).await?;
                self.bring_up(&name).await;
            }
            At::Dev(conn, dev) => {
                diag_reserved::<D>(&name)?;
                let c = self.conn_mut(conn)?;
                let src = c
                    .devices
                    .get(dev.as_str())
                    .ok_or_else(|| LinkError::not_found(format!("{conn}/{dev}")))?;
                if c.devices.contains_key(&name) {
                    return Err(LinkError::invalid_parameter(format!("{name} exists")));
                }
                branch::check_copy(src.count())?;
                let mut entry = src.clone();
                entry.enabled = false;
                c.devices.insert(name.clone(), entry);
                self.save_or_undo(|fw| {
                    if let Some(c) = fw.conns.get_mut(conn.as_str()) {
                        c.devices.remove(&name);
                    }
                })?;
                self.declare_branch(conn, &name).await?;
                set_status(
                    &self.ctx,
                    &format!("{conn}/{name}"),
                    NodeState::Stopped,
                    None,
                )
                .await;
                self.reset_diag(conn, &name);
            }
            At::Folder(conn, dev, folder) => {
                folder_name::<D>(&name)?;
                let parent = &folder[..folder.len() - 1];
                let d = self.dev_mut(conn, dev)?;
                if d.taken(parent, &name) {
                    return Err(LinkError::invalid_parameter(format!("{name} exists")));
                }
                let base = child(parent, &name);
                let inside = d.points.values().filter(|p| p.folder.starts_with(folder));
                branch::check_copy(
                    inside.count() + d.folders.iter().filter(|f| f.starts_with(folder)).count(),
                )?;
                let subs: Vec<Folder> = d
                    .folders
                    .iter()
                    .filter(|f| f.starts_with(folder))
                    .map(|f| rebase(f, folder, &base))
                    .collect();
                let mut renamed = Map::new();
                let mut new_points = Vec::new();
                let mut used: BTreeSet<String> = d.points.keys().cloned().collect();
                for (id, p) in d
                    .points
                    .iter()
                    .filter(|(_, p)| p.folder.starts_with(folder))
                {
                    let f = rebase(&p.folder, folder, &base);
                    let new_id = fresh_id(id, |c| {
                        used.contains(c)
                            || subs.contains(&child(&f, c))
                            || diag_reserved::<D>(c).is_err()
                    });
                    used.insert(new_id.clone());
                    renamed.insert(id.clone(), Value::Str(new_id.clone()));
                    let entry = PointEntry {
                        slot: p.slot.clone(),
                        folder: f,
                    };
                    new_points.push((new_id, entry));
                }
                d.folders.extend(subs.iter().cloned());
                let ids: Vec<String> = new_points.iter().map(|(n, _)| n.clone()).collect();
                d.points.extend(new_points);
                // The folders and ids are new: the undo removes them.
                self.save_or_undo(|fw| {
                    if let Ok(d) = fw.dev_mut(conn, dev) {
                        for f in &subs {
                            d.folders.remove(f);
                        }
                        for id in &ids {
                            d.points.remove(id);
                        }
                    }
                })?;
                for f in &subs {
                    self.declare_folder(conn, dev, f).await?;
                }
                for id in &ids {
                    self.declare_point(conn, dev, id).await?;
                }
                self.replan(conn).await;
                reply.insert("renamed".into(), Value::Map(renamed));
            }
            At::Point(conn, dev, pt) => {
                diag_reserved::<D>(&name)?;
                let d = self.dev_mut(conn, dev)?;
                let src = d
                    .points
                    .get(pt.as_str())
                    .ok_or_else(|| LinkError::not_found(format!("{conn}/{dev}/{pt}")))?;
                let entry = src.clone();
                if d.points.contains_key(&name) {
                    // Ids are unique on the device: plans and writes go by id.
                    return Err(LinkError::invalid_parameter(format!(
                        "{name} exists on this device (at {})",
                        d.rel(&name)
                    )));
                }
                if d.taken(&entry.folder, &name) {
                    return Err(LinkError::invalid_parameter(format!(
                        "{name} exists (a folder)"
                    )));
                }
                d.points.insert(name.clone(), entry);
                self.save_or_undo(|fw| {
                    if let Ok(d) = fw.dev_mut(conn, dev) {
                        d.points.remove(&name);
                    }
                })?;
                self.declare_point(conn, dev, &name).await?;
                self.replan(conn).await;
            }
        }
        reply.insert("name".into(), Value::Str(name));
        Ok(Value::Map(reply))
    }

    /// `import {json, name?, overwrite?}`: a connection at the root, a
    /// device into a connection, a folder into a device or folder.
    async fn import(&mut self, at: &At<'_>, args: &Value) -> Result<Value> {
        let m = map_of(args);
        if let Some(k) = m
            .keys()
            .find(|k| !matches!(k.as_str(), "json" | "name" | "overwrite"))
        {
            return Err(LinkError::invalid_parameter(format!("{k}: unknown field")));
        }
        let Some(Value::Str(text)) = m.get("json") else {
            return Err(LinkError::invalid_parameter("json: required"));
        };
        let name = match m.get("name") {
            None | Some(Value::Null) => None,
            Some(Value::Str(s)) if s.is_empty() => None,
            Some(Value::Str(s)) => Some(s.clone()),
            Some(_) => return Err(LinkError::invalid_parameter("name: expected a string")),
        };
        let overwrite = match m.get("overwrite") {
            None | Some(Value::Null) => false,
            Some(Value::Bool(b)) => *b,
            Some(_) => {
                return Err(LinkError::invalid_parameter(
                    "overwrite: expected true or false",
                ))
            }
        };
        let top = match at {
            At::Root => branch::Level::Connection,
            At::Conn(_) => branch::Level::Device,
            At::Dev(..) | At::Folder(..) if D::FOLDERS => branch::Level::Folder,
            _ => return Err(LinkError::not_supported("import here")),
        };
        let node = branch::parse(text, D::NAME, D::FOLDERS, &[top])?;
        self.import_node(at, node, name, overwrite).await
    }

    /// A root import ([`Driver::convert`]): every connection is checked
    /// before the first is imported, so a refusal changes nothing.
    async fn root_import(&mut self, action: &str, args: &Value) -> Result<Value> {
        let Converted {
            connections,
            mut report,
        } = D::convert(action, args)?;
        if let Some(k) = REPORT_KEYS.iter().find(|k| report.contains_key(**k)) {
            return Err(LinkError::internal(format!(
                "{action}: the driver's report uses {k:?}, a key of the framework"
            )));
        }
        let total: usize = connections.iter().map(Node::count).sum();
        if total > branch::MAX_NODES {
            return Err(LinkError::invalid_parameter(format!(
                "{action}: {total} nodes, more than {}",
                branch::MAX_NODES
            )));
        }
        let mut nodes = Vec::with_capacity(connections.len());
        let mut names = BTreeSet::new();
        for n in connections {
            // The checks of `import` text: levels, nesting and bounds.
            let text = branch::to_text(D::NAME, &n)?;
            let n = branch::parse(&text, D::NAME, D::FOLDERS, &[branch::Level::Connection])?;
            valid_name(&n.name)?;
            if self.conns.contains_key(&n.name) {
                return Err(LinkError::invalid_parameter(format!(
                    "{}: a connection of that name exists",
                    n.name
                )));
            }
            if !names.insert(n.name.clone()) {
                return Err(twice(action, &n.name));
            }
            new_conn::<D>(&n, &n.name, &mut Vec::new())?;
            nodes.push(n);
        }
        let (mut created, mut reenter) = (Vec::new(), Vec::new());
        for n in nodes {
            node_keys(&n, "", &mut created);
            let reply = self.import_node(&At::Root, n, None, false).await?;
            if let Some(Value::Array(r)) = map_of(&reply).remove("reenter") {
                reenter.extend(r);
            }
        }
        report.insert("created".into(), Value::Array(created));
        report.insert("reenter".into(), Value::Array(reenter));
        Ok(Value::Map(report))
    }

    /// Import `node` (its kind already fits `at`) under `name` (default:
    /// its own). Everything is checked before anything changes; an
    /// imported connection or device starts stopped, like a copy. Replies
    /// `{name, reenter: ["<node>.<secret>"]}`.
    async fn import_node(
        &mut self,
        at: &At<'_>,
        mut node: Node,
        name: Option<String>,
        overwrite: bool,
    ) -> Result<Value> {
        if let Some(n) = name {
            node.name = n;
        }
        let name = node.name.clone();
        valid_name(&name)?;
        let mut reenter = Vec::new();
        match at {
            At::Root => {
                let mut entry = new_conn::<D>(&node, &name, &mut reenter)?;
                if let Some(old) = self.conns.get(&name) {
                    if !overwrite {
                        return Err(exists_err(&name));
                    }
                    keep_conn_secrets(&old.slot, &mut entry.slot, &name, &mut reenter);
                }
                entry.enabled = false;
                entry.slot.note_reenter(&name, &reenter);
                for (dn, d) in entry.devices.iter_mut() {
                    d.note_reenter(&format!("{name}/{dn}"), &reenter);
                }
                // The tree changes in one step and is saved; the nodes follow.
                // A failed save puts the old connection back, its run too.
                let mut old = self.conns.insert(name.clone(), entry);
                self.save_or_undo(|fw| match old.take() {
                    Some(o) => {
                        fw.conns.insert(name.clone(), o);
                    }
                    None => {
                        fw.conns.remove(&name);
                    }
                })?;
                if let Some(mut old) = old {
                    if let Some(run) = old.run.take() {
                        stop_run(run).await;
                    }
                    self.ctx.remove_node(&name).await?;
                }
                self.declare_conn_tree(&name).await?;
                self.bring_up(&name).await;
            }
            At::Conn(conn) => {
                self.conn_mut(conn)?;
                let path = format!("{conn}/{name}");
                diag_reserved::<D>(&name)?;
                let tree = dev_tree::<D>(&node, &path, &mut reenter)?;
                let mut entry = load_dev::<D>(conn, &name, &tree)?;
                check_new::<D>(entry.points.keys(), &entry.folders)?;
                let old = self.conn_mut(conn)?.devices.contains_key(&name);
                if old && !overwrite {
                    return Err(exists_err(&name));
                }
                entry.enabled = false;
                entry.note_reenter(&path, &reenter);
                // The tree changes in one step and is saved; the nodes follow.
                let mut prev = self.conn_mut(conn)?.devices.insert(name.clone(), entry);
                self.save_or_undo(|fw| {
                    if let Some(c) = fw.conns.get_mut(conn.as_str()) {
                        match prev.take() {
                            Some(p) => c.devices.insert(name.clone(), p),
                            None => c.devices.remove(&name),
                        };
                    }
                })?;
                if old {
                    if let Some(run) = self.conns.get(conn.as_str()).and_then(|c| c.run.as_ref()) {
                        diag::remove_dev(&run.book, &name);
                    }
                    // The old device's plan ends before its nodes go.
                    self.replan(conn).await;
                    self.ctx.remove_node(&path).await?;
                }
                self.declare_branch(conn, &name).await?;
                set_status(&self.ctx, &path, NodeState::Stopped, None).await;
                self.reset_diag(conn, &name);
                self.replan(conn).await;
            }
            At::Dev(conn, dev) | At::Folder(conn, dev, _) => {
                let parent = match at {
                    At::Folder(_, _, f) => f.clone(),
                    _ => Folder::new(),
                };
                folder_name::<D>(&name)?;
                let base = child(&parent, &name);
                if base.len() > MAX_FOLDER_DEPTH {
                    return Err(LinkError::invalid_parameter(format!(
                        "{name}: folders nest at most {MAX_FOLDER_DEPTH} deep"
                    )));
                }
                let devpath = format!("{conn}/{dev}");
                let d = self.dev_mut(conn, dev)?;
                if d.points.get(&name).is_some_and(|p| p.folder == parent) {
                    return Err(LinkError::invalid_parameter(format!(
                        "{name} exists (a point)"
                    )));
                }
                let old = d.folders.contains(&base);
                if old && !overwrite {
                    return Err(exists_err(&name));
                }
                // The device as it will be: without the folder it replaces,
                // with the imported one (`load_branch` refuses an id twice).
                let mut points: BTreeMap<String, PointEntry<D::Point>> = d
                    .points
                    .iter()
                    .filter(|(_, p)| !p.folder.starts_with(&base))
                    .map(|(n, p)| (n.clone(), p.clone()))
                    .collect();
                let mut folders: BTreeSet<Folder> = d
                    .folders
                    .iter()
                    .filter(|f| !f.starts_with(&base))
                    .cloned()
                    .collect();
                let kept: BTreeSet<String> = points.keys().cloned().collect();
                let at_base = below(&devpath, &base);
                let mut fm = folder_tree::<D>(&node, &at_base, &mut reenter)?;
                folders.insert(base.clone());
                load_branch::<D>(&devpath, &base, &mut fm, &mut points, &mut folders)?;
                let new_ids: Vec<String> = points
                    .keys()
                    .filter(|id| !kept.contains(*id))
                    .cloned()
                    .collect();
                let new_folders: Vec<Folder> = folders
                    .iter()
                    .filter(|f| f.starts_with(&base))
                    .cloned()
                    .collect();
                check_new::<D>(&new_ids, &new_folders)?;
                for id in &new_ids {
                    let p = points.get_mut(id).expect("loaded");
                    let at = format!("{devpath}/{}", child(&p.folder, id).join("/"));
                    p.slot.note_reenter(&at, &reenter);
                }
                // The tree changes in one step and is saved; the nodes follow.
                let d = self.dev_mut(conn, dev)?;
                let mut before = Some((
                    std::mem::replace(&mut d.points, points),
                    std::mem::replace(&mut d.folders, folders),
                ));
                self.save_or_undo(|fw| {
                    if let (Ok(d), Some((p, f))) = (fw.dev_mut(conn, dev), before.take()) {
                        (d.points, d.folders) = (p, f);
                    }
                })?;
                if old {
                    // The old points' plan ends before their nodes go: no
                    // value read with old params lands on a new node.
                    self.replan(conn).await;
                    self.ctx.remove_node(&at_base).await?;
                }
                for f in &new_folders {
                    self.declare_folder(conn, dev, f).await?;
                }
                for id in &new_ids {
                    self.declare_point(conn, dev, id).await?;
                }
                self.replan(conn).await;
            }
            At::Point(..) => return Err(LinkError::not_supported("import into a point")),
        }
        let mut m = Map::new();
        m.insert("name".into(), Value::Str(name));
        m.insert(
            "reenter".into(),
            Value::Array(reenter.into_iter().map(Value::Str).collect()),
        );
        Ok(Value::Map(m))
    }
}

impl<D: Driver> DevEntry<D> {
    /// [`Slot::note_reenter`] for the device and its points (`at`: its key).
    fn note_reenter(&mut self, at: &str, reenter: &[String]) {
        self.slot.note_reenter(at, reenter);
        let rels: Vec<(String, String)> = self
            .points
            .keys()
            .map(|id| (id.clone(), self.rel(id)))
            .collect();
        for (id, rel) in rels {
            if let Some(p) = self.points.get_mut(&id) {
                p.slot.note_reenter(&format!("{at}/{rel}"), reenter);
            }
        }
    }
}
