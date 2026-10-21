//! [`Framework`]: a [`Link`] that runs any [`Driver`].
//!
//! Tree: `<conn>/<dev>/<point>`, shaped like the DSA driver framework.
//! Connections and devices have a `status` enum leaf (Unknown, Connecting,
//! Connected, Failed, Stopped, Stopped by Parent; spec 03 gives containers
//! no `~val`) and an `error` leaf that exists only while there is an error.
//! Actions carry a name for people and a menu group (spec 02): `add_*`
//! (group `new`, one per node kind of the level below), `edit` and `remove`
//! (group `edit`), `restart`, and `stop` or `start`, whichever applies.
//!
//! * One owner task per connection holds the transport and serves `Poll`,
//!   `Ping`, `Write` and `Reconfigure` requests in order.
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

use super::params::{normalize, Kind, ParamSpec, Params};
use super::persist::Persist;
use super::{backoff, jitter, Driver, DriverError, NodeState, PointId};
use crate::auth::Caller;
use crate::ctx::{now_us, LinkCtx, PointPublisher};
use crate::error::{LinkError, Result};
use crate::link::{Link, ReplySink};
use crate::params::FromParams;
use std::collections::BTreeMap;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::{mpsc, oneshot, watch};
use tokio::task::JoinHandle;
use tracing::{debug, warn};
use wyrm_core::meta::{ActionResult, GROUP_EDIT, GROUP_NEW};
use wyrm_core::{ActionMeta, NodeMeta, Perm, Quality, Sample, Status, TypeCode, Value};

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
/// {<d>: {..Dev, kind?, enabled?, points: {<p>: {..Point, kind?}}}}}}}`.
/// `kind` names the node kind on levels with several (default: the first).
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
                let schema = self.schema();
                let secret: Vec<&str> =
                    schema.iter().filter(|s| s.secret).map(|s| s.name).collect();
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
}

struct DevEntry<D: Driver> {
    slot: Slot<D::Dev>,
    enabled: bool,
    points: BTreeMap<String, Slot<D::Point>>,
}

struct ConnEntry<D: Driver> {
    slot: Slot<D::Conn>,
    enabled: bool,
    devices: BTreeMap<String, DevEntry<D>>,
    run: Option<ConnRun<D>>,
}

/// One poll group of a device.
struct Group<D: Driver> {
    period: Duration,
    ids: Vec<PointId>,
    plan: Arc<D::Plan>,
    inflight: Arc<AtomicBool>,
}

/// What the owner task needs about one device.
struct DevRun<D: Driver> {
    cfg: D::Dev,
    points: BTreeMap<PointId, D::Point>,
    groups: Vec<Group<D>>,
}

type DevMap<D> = BTreeMap<String, DevRun<D>>;

enum Req<D: Driver> {
    Poll {
        dev: String,
        group: usize,
    },
    Ping {
        dev: String,
    },
    Write {
        dev: String,
        point: String,
        value: Value,
        reply: oneshot::Sender<Result<()>>,
    },
    Reconfigure(Arc<DevMap<D>>),
}

struct ConnRun<D: Driver> {
    tx: mpsc::Sender<Req<D>>,
    stop: watch::Sender<bool>,
    owner: JoinHandle<()>,
    tickers: Vec<JoinHandle<()>>,
    tick_stop: watch::Sender<bool>,
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

/// Publish a point value when it or its quality changed.
async fn put_point(ctx: &LinkCtx, path: &str, v: Value, q: Quality, qual: Option<&str>) {
    if ctx.last(path).is_some_and(|s| s.v == v && s.q == q) {
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
            .map(|p| format!("{conn}/{dev}/{p}"))
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
        self.ctx
            .declare_node(&status_path(name), status_meta())
            .await?;
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
        self.declare_run_toggle(name, c.enabled).await
    }

    async fn declare_dev(&self, conn: &str, dev: &str) -> Result<()> {
        let d = &self.conns[conn].devices[dev];
        let base = format!("{conn}/{dev}");
        let shown = d.slot.shown();
        let mut meta = NodeMeta::folder().is("wy:df-device");
        meta.cfg = Some(shown.clone());
        self.ctx.declare_node(&base, meta).await?;
        self.ctx
            .declare_node(&status_path(&base), status_meta())
            .await?;
        for (id, k) in adds::<D::Point>("point") {
            let display = add_display("point", &k);
            self.ctx
                .declare_action(&base, &id, add_form::<D>(&k.schema, display))
                .await?;
        }
        self.declare_common(&base, &d.slot.schema(), &shown).await?;
        self.ctx
            .declare_action(&base, "restart", plain("Restart"))
            .await?;
        self.declare_run_toggle(&base, d.enabled).await
    }

    async fn declare_point(&self, conn: &str, dev: &str, pt: &str) -> Result<()> {
        let p = &self.conns[conn].devices[dev].points[pt];
        let path = format!("{conn}/{dev}/{pt}");
        let mut meta = match &p.cfg {
            Some(cfg) => D::point_meta(cfg),
            None => NodeMeta::leaf(TypeCode::Dynamic),
        };
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

    /// `edit` (the node's own form, pre-filled) and `remove`, group `edit`.
    async fn declare_common(&self, path: &str, schema: &[ParamSpec], shown: &Map) -> Result<()> {
        let edit = form::<D>(schema, Some(shown))
            .display("Edit")
            .group(GROUP_EDIT);
        self.ctx.declare_action(path, "edit", edit).await?;
        self.ctx
            .declare_action(path, "remove", plain("Remove").group(GROUP_EDIT))
            .await
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

    /// Root actions: one `add_*` per connection kind, `export`, and
    /// `rescan` when the driver has one.
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

    /// The node kind an add action creates on the level below `depth`.
    fn add_kind(depth: usize, action: &str) -> Option<&'static str> {
        let find = |list: Vec<(String, Kind)>| {
            list.into_iter()
                .find(|(id, _)| id == action)
                .map(|(_, k)| k.id)
        };
        match depth {
            0 => find(adds::<D::Conn>("connection")),
            1 => find(adds::<D::Dev>("device")),
            2 => find(adds::<D::Point>("point")),
            _ => None,
        }
    }

    /// `rescan`: forms again with fresh choices; replies `{param: [found]}`.
    async fn rescan(&self) -> Result<Value> {
        self.declare_root().await?;
        for (cn, c) in &self.conns {
            self.declare_conn(cn).await?;
            for (dn, d) in &c.devices {
                self.declare_dev(cn, dn).await?;
                for pn in d.points.keys() {
                    self.declare_point(cn, dn, pn).await?;
                }
            }
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
                .filter_map(|(n, p)| p.cfg.clone().map(|c| (n.clone(), c)))
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
                    inflight: Arc::new(AtomicBool::new(false)),
                })
                .collect();
            out.insert(
                name.clone(),
                DevRun {
                    cfg: cfg.clone(),
                    points,
                    groups,
                },
            );
        }
        out
    }

    /// Start tickers for `devs`.
    async fn start_tickers(
        &self,
        conn: &str,
        devs: &DevMap<D>,
        tx: &mpsc::Sender<Req<D>>,
    ) -> (Vec<JoinHandle<()>>, watch::Sender<bool>) {
        let (tick_stop, rx) = watch::channel(false);
        let mut tickers = Vec::new();
        for (dev, run) in devs {
            for (gi, g) in run.groups.iter().enumerate() {
                let mut pubs = Vec::new();
                if !self.poll_unsubscribed {
                    for id in &g.ids {
                        if let Ok(p) = self.ctx.publisher(&format!("{conn}/{dev}/{id}")).await {
                            pubs.push(p);
                        }
                    }
                }
                tickers.push(tokio::spawn(poll_ticker::<D>(
                    tx.clone(),
                    dev.clone(),
                    gi,
                    g.period,
                    g.inflight.clone(),
                    pubs,
                    self.poll_unsubscribed,
                    rx.clone(),
                )));
            }
            if let Some(period) = D::ping_period(&run.cfg) {
                tickers.push(tokio::spawn(ping_ticker::<D>(
                    tx.clone(),
                    dev.clone(),
                    period,
                    rx.clone(),
                )));
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
                let (stop, stop_rx) = watch::channel(false);
                let owner = tokio::spawn(owner::<D>(
                    self.ctx.clone(),
                    name.to_owned(),
                    cfg,
                    devs.clone(),
                    rx,
                    stop_rx,
                ));
                let (tickers, tick_stop) = self.start_tickers(name, &devs, &tx).await;
                self.conns.get_mut(name).expect("exists").run = Some(ConnRun {
                    tx,
                    stop,
                    owner,
                    tickers,
                    tick_stop,
                });
            }
        }
    }

    /// Stop the owner and tickers; returns after they ended (teardown before bring-up).
    async fn tear_down(&mut self, name: &str) {
        let Some(run) = self.conns.get_mut(name).and_then(|c| c.run.take()) else {
            return;
        };
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
    }

    /// Device/point change: new plan for the owner, new tickers, no reconnect.
    async fn replan(&mut self, conn: &str) {
        let devs = Arc::new(self.dev_map(conn));
        let Some(run) = self.conns.get_mut(conn).and_then(|c| c.run.take()) else {
            return;
        };
        let _ = run.tick_stop.send(true);
        for t in run.tickers {
            let _ = tokio::time::timeout(Duration::from_secs(1), t).await;
        }
        let _ = run.tx.send(Req::Reconfigure(devs.clone())).await;
        let (tickers, tick_stop) = self.start_tickers(conn, &devs, &run.tx).await;
        self.conns.get_mut(conn).expect("exists").run = Some(ConnRun {
            tickers,
            tick_stop,
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
                let pts: Map = d
                    .points
                    .iter()
                    .map(|(pn, p)| (pn.clone(), Value::Map(p.shown())))
                    .collect();
                dm.insert("points".into(), Value::Map(pts));
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
                let pts: Map = d
                    .points
                    .iter()
                    .map(|(pn, p)| (pn.clone(), Value::Map(p.stored())))
                    .collect();
                dm.insert("points".into(), Value::Map(pts));
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

#[allow(clippy::too_many_arguments)]
async fn poll_ticker<D: Driver>(
    tx: mpsc::Sender<Req<D>>,
    dev: String,
    group: usize,
    period: Duration,
    inflight: Arc<AtomicBool>,
    pubs: Vec<PointPublisher>,
    poll_unsubscribed: bool,
    mut stop: watch::Receiver<bool>,
) {
    let mut iv = tokio::time::interval(period);
    iv.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
    loop {
        tokio::select! {
            _ = iv.tick() => {}
            _ = stop.changed() => return,
        }
        // No pile-up: a slow device skips ticks instead of queueing them.
        if inflight.load(Ordering::Acquire) {
            continue;
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
                continue;
            }
        }
        inflight.store(true, Ordering::Release);
        if tx
            .try_send(Req::Poll {
                dev: dev.clone(),
                group,
            })
            .is_err()
        {
            inflight.store(false, Ordering::Release);
        }
    }
}

async fn ping_ticker<D: Driver>(
    tx: mpsc::Sender<Req<D>>,
    dev: String,
    period: Duration,
    mut stop: watch::Receiver<bool>,
) {
    let mut iv = tokio::time::interval(period);
    iv.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
    loop {
        tokio::select! {
            _ = iv.tick() => {}
            _ = stop.changed() => return,
        }
        let _ = tx.try_send(Req::Ping { dev: dev.clone() });
    }
}

/// Per-device bookkeeping inside the owner.
#[derive(Default)]
struct DevHealth {
    state: Option<NodeState>,
    misses: u32,
}

struct Owner<D: Driver> {
    ctx: LinkCtx,
    conn: String,
    devs: Arc<DevMap<D>>,
    health: BTreeMap<String, DevHealth>,
}

impl<D: Driver> Owner<D> {
    fn dev_points(&self, dev: &str) -> Vec<String> {
        self.devs
            .get(dev)
            .map(|d| {
                d.points
                    .keys()
                    .map(|p| format!("{}/{dev}/{p}", self.conn))
                    .collect()
            })
            .unwrap_or_default()
    }

    async fn dev_state(&mut self, dev: &str, s: NodeState, err: Option<&str>) {
        let h = self.health.entry(dev.to_owned()).or_default();
        if h.state == Some(s) && err.is_none() {
            return;
        }
        h.state = Some(s);
        set_status(&self.ctx, &format!("{}/{dev}", self.conn), s, err).await;
    }

    async fn dev_ok(&mut self, dev: &str) {
        self.health.entry(dev.to_owned()).or_default().misses = 0;
        self.dev_state(dev, NodeState::Connected, None).await;
    }

    /// Quality ladder: first miss → `uncertain/stale`; `stale_misses` → device
    /// `Failed`, points `bad/comm_fail`.
    async fn dev_miss(&mut self, dev: &str, why: &str) {
        let misses = {
            let h = self.health.entry(dev.to_owned()).or_default();
            h.misses += 1;
            h.misses
        };
        if misses == 1 {
            mark(
                &self.ctx,
                self.dev_points(dev),
                Quality::Uncertain,
                QUAL_STALE,
            )
            .await;
        }
        if misses == D::stale_misses().max(1) {
            self.dev_state(dev, NodeState::Failed, Some(why)).await;
            mark(
                &self.ctx,
                self.dev_points(dev),
                Quality::Bad,
                QUAL_COMM_FAIL,
            )
            .await;
        }
    }

    /// Connection lost or not open: every device stopped by its parent.
    async fn cascade_down(&mut self) {
        let devs: Vec<String> = self.devs.keys().cloned().collect();
        for d in devs {
            self.health.entry(d.clone()).or_default().misses = 0;
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

    async fn publish_results(
        &mut self,
        dev: &str,
        results: Vec<(PointId, Result<Value, DriverError>)>,
    ) -> std::result::Result<(), String> {
        let mut device_err = None;
        let mut any_ok = false;
        for (id, r) in results {
            let path = format!("{}/{dev}/{id}", self.conn);
            match r {
                Ok(v) => {
                    any_ok = true;
                    put_point(&self.ctx, &path, v, Quality::Good, None).await;
                }
                Err(DriverError::Point(e)) => {
                    any_ok = true; // the device answered
                    debug!(point = %path, "point error: {e}");
                    let v = self.ctx.last(&path).map(|s| s.v).unwrap_or(Value::Null);
                    put_point(&self.ctx, &path, v, Quality::Bad, Some(QUAL_DEVICE_ERROR)).await;
                }
                Err(DriverError::Device(e)) => device_err = Some(e),
                Err(DriverError::Transport(e)) => return Err(e),
            }
        }
        match device_err {
            Some(e) if !any_ok => self.dev_miss(dev, &e).await,
            _ => self.dev_ok(dev).await,
        }
        Ok(())
    }
}

/// The connection owner: opens the transport, serves requests in order,
/// reconnects with capped, jittered backoff.
async fn owner<D: Driver>(
    ctx: LinkCtx,
    conn: String,
    cfg: D::Conn,
    devs: Arc<DevMap<D>>,
    mut rx: mpsc::Receiver<Req<D>>,
    mut stop: watch::Receiver<bool>,
) {
    let timeout = D::io_timeout(&cfg);
    let mut o = Owner::<D> {
        ctx,
        conn,
        devs,
        health: BTreeMap::new(),
    };
    let mut attempt = 0u32;
    loop {
        set_status(&o.ctx, &o.conn, NodeState::Connecting, None).await;
        let opened = tokio::select! {
            r = tokio::time::timeout(timeout, D::open(&cfg)) => r,
            _ = stop.changed() => return,
        };
        let failure = match opened {
            Ok(Ok(mut t)) => {
                attempt = 0;
                set_status(&o.ctx, &o.conn, NodeState::Connected, None).await;
                let devs: Vec<String> = o.devs.keys().cloned().collect();
                for d in devs {
                    o.dev_state(&d, NodeState::Connecting, None).await;
                }
                match serve::<D>(&mut o, &mut t, &mut rx, &mut stop, timeout).await {
                    None => return,
                    Some(e) => e,
                }
            }
            Ok(Err(e)) => e.to_string(),
            Err(_) => "open timed out".to_owned(),
        };
        warn!(conn = %o.conn, "connection failed: {failure}");
        set_status(&o.ctx, &o.conn, NodeState::Failed, Some(&failure)).await;
        o.cascade_down().await;
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
                    Some(Req::Reconfigure(m)) => o.devs = m,
                    Some(Req::Poll { dev, group }) => {
                        if let Some(g) = o.devs.get(&dev).and_then(|d| d.groups.get(group)) {
                            g.inflight.store(false, Ordering::Release);
                        }
                    }
                    Some(Req::Ping { .. }) => {}
                },
            }
        }
    }
}

/// Serve requests on an open transport. `None` = stopped; `Some(err)` =
/// the transport broke.
async fn serve<D: Driver>(
    o: &mut Owner<D>,
    t: &mut D::Transport,
    rx: &mut mpsc::Receiver<Req<D>>,
    stop: &mut watch::Receiver<bool>,
    timeout: Duration,
) -> Option<String> {
    loop {
        let req = tokio::select! {
            r = rx.recv() => r?,
            _ = stop.changed() => return None,
        };
        match req {
            Req::Reconfigure(m) => o.devs = m,
            Req::Poll { dev, group } => {
                let devs = o.devs.clone();
                let Some(d) = devs.get(&dev) else { continue };
                let Some(g) = d.groups.get(group) else {
                    continue;
                };
                let r = tokio::time::timeout(timeout, D::poll(t, &d.cfg, &g.plan)).await;
                g.inflight.store(false, Ordering::Release);
                match r {
                    Err(_) => o.dev_miss(&dev, "poll timed out").await,
                    Ok(results) => {
                        if let Err(e) = o.publish_results(&dev, results).await {
                            return Some(e);
                        }
                    }
                }
            }
            Req::Ping { dev } => {
                let devs = o.devs.clone();
                let Some(d) = devs.get(&dev) else { continue };
                match tokio::time::timeout(timeout, D::ping(t, &d.cfg)).await {
                    Err(_) => o.dev_miss(&dev, "ping timed out").await,
                    Ok(Ok(())) | Ok(Err(DriverError::Point(_))) => o.dev_ok(&dev).await,
                    Ok(Err(DriverError::Device(e))) => o.dev_miss(&dev, &e).await,
                    Ok(Err(DriverError::Transport(e))) => return Some(e),
                }
            }
            Req::Write {
                dev,
                point,
                value,
                reply,
            } => {
                let devs = o.devs.clone();
                let target = devs
                    .get(&dev)
                    .and_then(|d| d.points.get(&point).map(|p| (d, p)));
                let Some((d, p)) = target else {
                    let _ = reply.send(Err(LinkError::not_found(format!("{dev}/{point}"))));
                    continue;
                };
                let r = match tokio::time::timeout(timeout, D::write(t, &d.cfg, &point, p, &value))
                    .await
                {
                    Err(_) => Err(DriverError::Device("write timed out".into())),
                    Ok(r) => r,
                };
                let outcome = match r {
                    Ok(()) => {
                        // Read back: the tree shows what the device holds.
                        let plan = D::plan(&d.cfg, &[(point.clone(), p.clone())]);
                        if let Ok(results) =
                            tokio::time::timeout(timeout, D::poll(t, &d.cfg, &plan)).await
                        {
                            if let Err(e) = o.publish_results(&dev, results).await {
                                let _ = reply.send(Ok(()));
                                return Some(e);
                            }
                        }
                        Ok(())
                    }
                    Err(DriverError::Point(e)) => Err(LinkError::invalid_parameter(e)),
                    Err(DriverError::Device(e)) => Err(LinkError::timeout(e)),
                    Err(DriverError::Transport(e)) => {
                        let _ = reply.send(Err(LinkError::new(Status::Disconnected, e.clone())));
                        return Some(e);
                    }
                };
                let _ = reply.send(outcome);
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
            valid_name(&cn)?;
            let mut cm = map_of(&cv);
            let enabled = is_enabled(&mut cm);
            let devs_raw = take(&mut cm, "devices")
                .map(|v| map_of(&v))
                .unwrap_or_default();
            let mut devices = BTreeMap::new();
            for (dn, dv) in devs_raw {
                valid_name(&dn)?;
                let mut dm = map_of(&dv);
                let denabled = is_enabled(&mut dm);
                let pts_raw = take(&mut dm, "points")
                    .map(|v| map_of(&v))
                    .unwrap_or_default();
                let mut points = BTreeMap::new();
                for (pn, pv) in pts_raw {
                    valid_name(&pn)?;
                    points.insert(pn, Slot::parse(pv));
                }
                devices.insert(
                    dn,
                    DevEntry {
                        slot: Slot::parse(Value::Map(dm)),
                        enabled: denabled,
                        points,
                    },
                );
            }
            fw.conns.insert(
                cn,
                ConnEntry {
                    slot: Slot::parse(Value::Map(cm)),
                    enabled,
                    devices,
                    run: None,
                },
            );
        }
        fw.declare_root().await?;
        let names: Vec<String> = fw.conns.keys().cloned().collect();
        for cn in &names {
            fw.declare_conn(cn).await?;
            let devs: Vec<String> = fw.conns[cn].devices.keys().cloned().collect();
            for dn in &devs {
                fw.declare_dev(cn, dn).await?;
                let pts: Vec<String> = fw.conns[cn].devices[dn].points.keys().cloned().collect();
                for pn in &pts {
                    fw.declare_point(cn, dn, pn).await?;
                }
            }
        }
        for cn in &names {
            fw.bring_up(cn).await;
        }
        Ok(fw)
    }

    async fn on_set(&mut self, path: &str, value: Value, _who: &Caller) -> Result<()> {
        let parts: Vec<&str> = path.split('/').collect();
        let [conn, dev, point] = parts.as_slice() else {
            return Err(LinkError::not_supported("only points take values"));
        };
        let run = self
            .conns
            .get(*conn)
            .and_then(|c| c.run.as_ref())
            .ok_or_else(|| LinkError::new(Status::Disconnected, "connection not running"))?;
        let (reply, rx) = oneshot::channel();
        run.tx
            .send(Req::Write {
                dev: (*dev).to_owned(),
                point: (*point).to_owned(),
                value,
                reply,
            })
            .await
            .map_err(|_| LinkError::new(Status::Disconnected, "connection stopped"))?;
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
        let changes =
            action.starts_with("add_") || matches!(action, "edit" | "remove" | "start" | "stop");
        self.invoke_action(&parts, action, args, out).await?;
        if changes {
            if let Some(p) = &self.persist {
                p.save(&self.full_tree()).map_err(|e| {
                    LinkError::internal(format!("applied, but not saved for a restart: {e}"))
                })?;
            }
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
    /// `add_*`: a connection (depth 0), device (1) or point (2) of `kind`.
    async fn add_child(&mut self, parts: &[String], kind: &str, args: &Value) -> Result<()> {
        let (name, params) = split_name(args)?;
        match parts {
            [] => {
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
            [conn] => {
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
                        points: BTreeMap::new(),
                    },
                );
                self.declare_dev(conn, &name).await?;
                set_status(&self.ctx, &format!("{conn}/{name}"), NodeState::New, None).await;
                self.replan(conn).await;
            }
            [conn, dev] => {
                let cfg = D::Point::from_kind_value(kind, &params)?;
                let d = self
                    .conn_mut(conn)?
                    .devices
                    .get_mut(dev)
                    .ok_or_else(|| LinkError::not_found(dev.clone()))?;
                if d.points.contains_key(&name) {
                    return Err(LinkError::invalid_parameter(format!("{name} exists")));
                }
                d.points.insert(name.clone(), Slot::valid(cfg));
                self.declare_point(conn, dev, &name).await?;
                self.replan(conn).await;
            }
            _ => return Err(LinkError::not_supported("add below a point")),
        }
        Ok(())
    }

    async fn invoke_action(
        &mut self,
        parts: &[String],
        action: &str,
        args: Value,
        out: ReplySink,
    ) -> Result<()> {
        let path = parts.join("/");
        match (parts, action) {
            ([], "export") => return out.reply(self.export()).await,
            ([], "rescan") if D::RESCAN.is_some() => return out.reply(self.rescan().await?).await,
            _ if action.starts_with("add_") => {
                let Some(kind) = Self::add_kind(parts.len(), action) else {
                    return Err(LinkError::not_supported(format!("{path}/~act/{action}")));
                };
                self.add_child(parts, kind, &args).await?;
            }
            ([conn], "edit") => {
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
            ([conn, dev], "edit") => {
                let (old, kind, schema) = self
                    .conn_mut(conn)?
                    .devices
                    .get(dev)
                    .map(|d| (d.slot.raw.clone(), d.slot.kind.clone(), d.slot.schema()))
                    .ok_or_else(|| LinkError::not_found(dev.clone()))?;
                let cfg = D::Dev::from_kind_value(&kind, &keep_secrets(&schema, &old, &args))?;
                let d = self
                    .conn_mut(conn)?
                    .devices
                    .get_mut(dev)
                    .ok_or_else(|| LinkError::not_found(dev.clone()))?;
                if d.slot.cfg.as_ref() == Some(&cfg) {
                    return Ok(());
                }
                d.slot = Slot::valid(cfg);
                self.declare_dev(conn, dev).await?;
                self.replan(conn).await;
            }
            ([conn, dev, pt], "edit") => {
                let (old, kind, schema) = self
                    .conn_mut(conn)?
                    .devices
                    .get(dev)
                    .and_then(|d| d.points.get(pt))
                    .map(|p| (p.raw.clone(), p.kind.clone(), p.schema()))
                    .ok_or_else(|| LinkError::not_found(pt.clone()))?;
                let cfg = D::Point::from_kind_value(&kind, &keep_secrets(&schema, &old, &args))?;
                let p = self
                    .conn_mut(conn)?
                    .devices
                    .get_mut(dev)
                    .and_then(|d| d.points.get_mut(pt))
                    .ok_or_else(|| LinkError::not_found(pt.clone()))?;
                if p.cfg.as_ref() == Some(&cfg) {
                    return Ok(());
                }
                *p = Slot::valid(cfg);
                self.declare_point(conn, dev, pt).await?;
                self.replan(conn).await;
            }
            ([conn], "remove") => {
                self.conn_mut(conn)?;
                self.tear_down(conn).await;
                self.conns.remove(conn);
                self.ctx.remove_node(conn).await?;
            }
            ([conn, dev], "remove") => {
                self.conn_mut(conn)?
                    .devices
                    .remove(dev)
                    .ok_or_else(|| LinkError::not_found(dev.clone()))?;
                self.ctx.remove_node(&format!("{conn}/{dev}")).await?;
                self.replan(conn).await;
            }
            ([conn, dev, pt], "remove") => {
                self.conn_mut(conn)?
                    .devices
                    .get_mut(dev)
                    .and_then(|d| d.points.remove(pt))
                    .ok_or_else(|| LinkError::not_found(pt.clone()))?;
                self.ctx.remove_node(&format!("{conn}/{dev}/{pt}")).await?;
                self.replan(conn).await;
            }
            ([conn], "restart") => {
                self.conn_mut(conn)?;
                self.tear_down(conn).await;
                self.bring_up(conn).await;
            }
            ([conn, _dev], "restart") => {
                self.conn_mut(conn)?;
                self.replan(conn).await;
            }
            ([conn], a @ ("start" | "stop")) => {
                let on = a == "start";
                if self.conn_mut(conn)?.enabled == on {
                    return Ok(());
                }
                self.tear_down(conn).await;
                self.conn_mut(conn)?.enabled = on;
                self.declare_run_toggle(conn, on).await?;
                self.bring_up(conn).await;
            }
            ([conn, dev], a @ ("start" | "stop")) => {
                let on = a == "start";
                let d = self
                    .conn_mut(conn)?
                    .devices
                    .get_mut(dev)
                    .ok_or_else(|| LinkError::not_found(dev.clone()))?;
                if d.enabled == on {
                    return Ok(());
                }
                d.enabled = on;
                let base = format!("{conn}/{dev}");
                self.declare_run_toggle(&base, on).await?;
                if on {
                    set_status(&self.ctx, &base, NodeState::New, None).await;
                } else {
                    set_status(&self.ctx, &base, NodeState::Stopped, None).await;
                    let paths = Self::point_paths(
                        conn,
                        dev,
                        &self.conns[conn.as_str()].devices[dev.as_str()],
                    );
                    mark(&self.ctx, paths, Quality::Bad, QUAL_DISCONNECTED).await;
                }
                self.replan(conn).await;
            }
            _ => return Err(LinkError::not_supported(format!("{path}/~act/{action}"))),
        }
        Ok(())
    }
}
