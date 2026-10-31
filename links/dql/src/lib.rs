//! `dql`: DSA DQL in WYRM (ADR 0025) as a portable link (ADR 0023), as the scheduler is. One
//! source runs embedded in `wyrmd`, as a process (`--features process`) and as a WASM component
//! (`--features wasm`).
//!
//! A query is a stored definition (`add_query`) or an ad-hoc one (`run`, with a time to live);
//! `wyrm-dql` parses it and runs it as an [`Engine`]. The link performs the engine's effects
//! through the [`Host`] (lists, subtree subscriptions, sink calls), and shows each query as a
//! node whose `table` value is the result, published at most every `publish_ms`.
//!
//! Bounds: every event spends at most [`BUDGET`] commands (the host fails an event over 1 000);
//! what is left waits in a backlog drained by `0` ms timer events. At most [`MAX_QUERIES`]
//! queries and [`SINKS_IN_FLIGHT`] sink calls at once; more wait in a FIFO.
//!
//! Rights (D2): defining a query is `write`; a query with a sink (`set`, `invoke`) needs the
//! caller's effective `config` on the action, checked here from [`Who`].

mod store;
pub mod tree;

use std::collections::{BTreeMap, HashMap, VecDeque};

use wyrm_core::{Perm, Quality, Sample, Status, Value};
use wyrm_dql::{parse, Effect, Engine, Handle, Limits};
use wyrm_link_api::{App, AppError, Host, Level, ListChange, ReqId, SubId, TimerId, Who};

pub use store::{Def, Rights};

/// Queries at once, stored and ad-hoc.
pub const MAX_QUERIES: usize = 200;
/// Commands one event spends (the host allows 1 000).
pub const BUDGET: usize = 700;
/// Sink calls in flight for the whole link (the host allows 100 requests).
pub const SINKS_IN_FLIGHT: usize = 50;
pub const DEFAULT_PUBLISH_MS: u64 = 500;
pub const MIN_PUBLISH_MS: u64 = 100;
pub const MAX_PUBLISH_MS: u64 = 60_000;
pub const DEFAULT_TTL_S: u64 = 300;
pub const MAX_TTL_S: u64 = 3_600;
/// Rows of one `get_table` reply unless `limit` says less.
pub const TABLE_PAGE: usize = 1_000;
pub const MAX_TABLE_PAGE: usize = 5_000;

type Args = BTreeMap<String, Value>;

fn invalid(field: &str, rule: impl std::fmt::Display) -> AppError {
    AppError::new(Status::InvalidParameter, format!("{field}: {rule}"))
}

fn args_of(args: Value) -> Result<Args, AppError> {
    match args {
        Value::Map(m) => Ok(m),
        Value::Null => Ok(Args::new()),
        _ => Err(invalid("args", "a map")),
    }
}

fn opt_str(m: &Args, k: &str) -> Result<Option<String>, AppError> {
    match m.get(k) {
        None | Some(Value::Null) => Ok(None),
        Some(Value::Str(s)) if s.is_empty() => Ok(None),
        Some(Value::Str(s)) => Ok(Some(s.clone())),
        Some(_) => Err(invalid(k, "must be text")),
    }
}

fn req_str(m: &Args, k: &str) -> Result<String, AppError> {
    opt_str(m, k)?.ok_or_else(|| invalid(k, "required"))
}

fn opt_uint(m: &Args, k: &str) -> Result<Option<u64>, AppError> {
    let bad = || invalid(k, "must be a whole number from 0");
    match m.get(k) {
        None | Some(Value::Null) => Ok(None),
        Some(Value::UInt(n)) => Ok(Some(*n)),
        Some(Value::Int(n)) => u64::try_from(*n).map(Some).map_err(|_| bad()),
        Some(Value::Float(f)) if f.fract() == 0.0 && *f >= 0.0 && *f < 1e15 => Ok(Some(*f as u64)),
        Some(_) => Err(bad()),
    }
}

fn opt_bool(m: &Args, k: &str) -> Result<Option<bool>, AppError> {
    match m.get(k) {
        None | Some(Value::Null) => Ok(None),
        Some(Value::Bool(b)) => Ok(Some(*b)),
        Some(_) => Err(invalid(k, "must be true or false")),
    }
}

/// A query id: one key segment, not a reserved name.
fn check_id(id: &str) -> Result<(), AppError> {
    if id == tree::STATS || id.starts_with('.') {
        return Err(invalid("id", format!("{id:?} is reserved")));
    }
    wyrm_core::keyspace::validate_segment(id)
        .map_err(|_| invalid("id", "one key segment: letters, digits, _ . -"))
}

fn publish_ms(m: &Args) -> Result<Option<u64>, AppError> {
    match opt_uint(m, "publish_ms")? {
        Some(v) if !(MIN_PUBLISH_MS..=MAX_PUBLISH_MS).contains(&v) => Err(invalid(
            "publish_ms",
            format!("{MIN_PUBLISH_MS} to {MAX_PUBLISH_MS}"),
        )),
        v => Ok(v),
    }
}

/// The caller holds `config` on the action it called (the token's one grant, capped at the
/// request's effective level by the host).
fn may_config(who: &Who) -> bool {
    who.grants.iter().any(|(_, p)| *p >= Perm::Config)
}

/// Changing a sink query (switching it on, editing, replacing or removing it) needs `config`, as
/// making it did: an operator may stop its writes (switch it off), never start them again, change
/// them or drop an engineer's query.
fn guard_sink_query(text: &str, who: &Who, what: &str) -> Result<(), AppError> {
    let sinks = parse(text).map(|p| p.has_sinks()).unwrap_or(false);
    if sinks && !may_config(who) {
        return Err(AppError::new(
            Status::PermissionDenied,
            format!("to {what} a query with set or invoke needs config on the DQL link"),
        ));
    }
    Ok(())
}

/// The caller's rights, kept with what it defines (ADR 0025 item 4): a query reads and writes
/// only what its author may. A token without `auth` (spec 04) is refused: its rights are unknown.
/// The site is the request's own, from the grant that let the call in.
fn rights_of(who: &Who) -> Result<Rights, AppError> {
    let refuse = || {
        AppError::new(
            Status::PermissionDenied,
            "the caller's rights are unknown (its token carries no auth): a query runs with its \
             author's rights",
        )
    };
    let grants = who.authority.clone().ok_or_else(refuse)?;
    let site = who
        .grants
        .first()
        .and_then(|(k, _)| k.strip_prefix("wy/")?.split('/').next())
        .filter(|s| !s.is_empty() && !s.contains('*'))
        .ok_or_else(refuse)?;
    Ok(Rights {
        site: site.to_owned(),
        grants,
    })
}

fn refuse_sinks(text: &str, who: &Who) -> Result<(), AppError> {
    let plan = parse(text).map_err(|e| invalid("text", e))?;
    if plan.has_sinks() && !may_config(who) {
        return Err(AppError::new(
            Status::PermissionDenied,
            "a query with set or invoke needs config on the DQL link",
        ));
    }
    Ok(())
}

fn rfc3339(us: u64) -> Value {
    i64::try_from(us)
        .ok()
        .and_then(|us| jiff::Timestamp::from_microsecond(us).ok())
        .map_or(Value::Null, |t| Value::Str(t.to_string()))
}

/// Counts the commands of one event, so the app stays within [`BUDGET`].
struct Cx<'h> {
    host: &'h mut dyn Host,
    used: usize,
}

impl Cx<'_> {
    fn room(&self) -> bool {
        self.used < BUDGET
    }
    fn now(&self) -> u64 {
        self.host.now_us()
    }
}

struct Query {
    def: Def,
    engine: Option<Engine>,
    /// Why the query does not run (its text no longer parses).
    error: Option<String>,
    /// `Some`: ad-hoc, not stored; removed at this instant unless read again.
    expires_us: Option<u64>,
    ttl_s: u64,
    /// engine handle → host subscription or list
    handles: HashMap<Handle, u64>,
    last_publish_us: Option<u64>,
    /// The table changed and is not published yet.
    dirty: bool,
    /// The attributes last declared, to declare again only on a change.
    shown: Option<BTreeMap<String, Value>>,
    rows_shown: usize,
}

impl Query {
    fn new(def: Def) -> Self {
        Self {
            def,
            engine: None,
            error: None,
            expires_us: None,
            ttl_s: 0,
            handles: HashMap::new(),
            last_publish_us: None,
            dirty: true,
            shown: None,
            rows_shown: 0,
        }
    }

    fn status(&self) -> &'static str {
        if !self.def.enabled {
            "disabled"
        } else if self.error.is_some() {
            "error"
        } else {
            self.engine.as_ref().map_or("error", |e| e.status().name())
        }
    }

    fn attrs(&self) -> BTreeMap<String, Value> {
        let mut a = BTreeMap::new();
        let s = |v: &str| Value::Str(v.to_owned());
        a.insert("text".into(), s(&self.def.text));
        a.insert("status".into(), s(self.status()));
        a.insert("created_by".into(), s(&self.def.created_by));
        a.insert(
            "expires".into(),
            self.expires_us.map_or(Value::Null, rfc3339),
        );
        let (error, rows, cols, p) = match &self.engine {
            Some(e) => (
                self.error.clone().or_else(|| e.progress().error.clone()),
                e.rows(),
                e.columns().to_vec(),
                Some(e.progress()),
            ),
            None => (self.error.clone(), 0, Vec::new(), None),
        };
        a.insert("error".into(), error.map_or(Value::Null, Value::Str));
        a.insert("rows".into(), Value::UInt(rows as u64));
        a.insert(
            "columns".into(),
            Value::Array(cols.into_iter().map(Value::Str).collect()),
        );
        let n = |v: usize| Value::UInt(v as u64);
        if let Some(p) = p {
            a.insert("errors".into(), Value::UInt(p.errors));
            a.insert("sink_calls".into(), Value::UInt(p.sink_calls));
            a.insert("refetches".into(), Value::UInt(p.refetches.into()));
            a.insert("lists".into(), n(p.lists));
            a.insert("lists_pending".into(), n(p.lists_pending));
            a.insert("depth".into(), n(p.depth));
            a.insert(
                "sites".into(),
                Value::Array(p.sites.iter().cloned().map(Value::Str).collect()),
            );
            a.insert(
                "collect_ms".into(),
                p.collect_ms.map_or(Value::Null, Value::UInt),
            );
        }
        a
    }
}

/// The DQL link.
pub struct Dql {
    queries: BTreeMap<String, Query>,
    /// Stored query ids, in the store's `index`.
    index: Vec<String>,
    /// host subscription or list → (query, engine handle)
    subs: HashMap<u64, (String, Handle)>,
    /// host request → (query, engine call)
    reqs: HashMap<u64, (String, u64)>,
    backlog: VecDeque<(String, Effect)>,
    /// Host subscriptions and lists of stopped queries, ended within the budget.
    closing: VecDeque<u64>,
    /// Sink calls beyond [`SINKS_IN_FLIGHT`].
    waiting: VecDeque<(String, Effect)>,
    timer: Option<(TimerId, u64)>,
    stats: [u64; 5],
    next_run: u64,
}

impl Dql {
    fn effects(&mut self, q: &str, out: Vec<Effect>) {
        self.backlog
            .extend(out.into_iter().map(|e| (q.to_owned(), e)));
    }

    /// Start (or restart) the engine of query `id` from its definition.
    fn start_query(&mut self, cx: &mut Cx<'_>, id: &str) {
        self.stop_query(cx, id);
        let Some(q) = self.queries.get_mut(id) else {
            return;
        };
        q.error = None;
        q.engine = None;
        q.dirty = true;
        q.last_publish_us = None;
        if !q.def.enabled {
            return;
        }
        let Some(r) = &q.def.rights else {
            q.error = Some(
                "defined before its author's rights were kept: edit its text or add it again"
                    .into(),
            );
            return;
        };
        let author = Who {
            authority: Some(r.grants.clone()),
            ..Who::default()
        };
        match parse(&q.def.text) {
            Ok(plan) => {
                let mut e = Engine::new(plan, Limits::default()).with_rights(author, &r.site);
                let mut out = Vec::new();
                e.start(cx.now(), &mut out);
                q.engine = Some(e);
                self.effects(id, out);
            }
            Err(e) => q.error = Some(e.to_string()),
        }
    }

    /// End everything query `id` holds in the host.
    fn stop_query(&mut self, cx: &mut Cx<'_>, id: &str) {
        self.backlog.retain(|(q, _)| q != id);
        self.waiting.retain(|(q, _)| q != id);
        let Some(q) = self.queries.get_mut(id) else {
            return;
        };
        for (_, sid) in q.handles.drain() {
            self.subs.remove(&sid);
            self.closing.push_back(sid);
        }
        let _ = cx;
        self.reqs.retain(|_, (qid, _)| qid != id);
        q.engine = None;
    }

    fn declare_query(&mut self, cx: &mut Cx<'_>, id: &str) {
        let Some(q) = self.queries.get_mut(id) else {
            return;
        };
        let attrs = q.attrs();
        cx.host
            .declare_node(id, tree::query_meta(attrs.clone(), &q.def.display));
        cx.host.declare_node(&tree::table(id), tree::table_meta());
        cx.host
            .declare_node(&tree::enabled(id), tree::enabled_meta());
        cx.host.update(
            &tree::enabled(id),
            Sample {
                v: Value::Bool(q.def.enabled),
                q: Quality::Good,
                t: cx.host.now_us(),
            },
        );
        cx.used += 4;
        q.shown = Some(attrs);
    }

    fn remove_query(&mut self, cx: &mut Cx<'_>, id: &str) {
        self.stop_query(cx, id);
        if self.queries.remove(id).is_some() {
            cx.host.remove_node(id);
            cx.used += 1;
        }
    }

    /// Apply the backlog within the event's budget.
    fn drain(&mut self, cx: &mut Cx<'_>) {
        while cx.room() {
            let Some(sid) = self.closing.pop_front() else {
                break;
            };
            cx.host.unsubscribe(SubId(sid));
            cx.used += 1;
        }
        while cx.room() {
            let Some((qid, eff)) = self.backlog.pop_front() else {
                break;
            };
            self.apply(cx, &qid, eff);
        }
        while cx.room() && self.reqs.len() < SINKS_IN_FLIGHT {
            let Some((qid, eff)) = self.waiting.pop_front() else {
                break;
            };
            self.apply(cx, &qid, eff);
        }
    }

    fn apply(&mut self, cx: &mut Cx<'_>, qid: &str, eff: Effect) {
        let now = cx.now();
        let Some(q) = self.queries.get_mut(qid) else {
            return;
        };
        let mut out = Vec::new();
        match eff {
            Effect::List { h, key, full } => {
                cx.used += 1;
                match cx.host.list(&key, full) {
                    Ok(s) => {
                        q.handles.insert(h, s.0);
                        self.subs.insert(s.0, (qid.to_owned(), h));
                    }
                    Err(e) => {
                        if let Some(en) = q.engine.as_mut() {
                            en.failed(h, &e.to_string(), now);
                        }
                    }
                }
            }
            Effect::Subscribe { h, key } => {
                cx.used += 1;
                match cx.host.subscribe(&key) {
                    Ok(s) => {
                        q.handles.insert(h, s.0);
                        self.subs.insert(s.0, (qid.to_owned(), h));
                    }
                    Err(e) => {
                        if let Some(en) = q.engine.as_mut() {
                            en.failed(h, &e.to_string(), now);
                        }
                    }
                }
            }
            Effect::Unsubscribe { h } => {
                if let Some(s) = q.handles.remove(&h) {
                    self.subs.remove(&s);
                    cx.host.unsubscribe(SubId(s));
                    cx.used += 1;
                }
            }
            sink @ (Effect::Invoke { .. } | Effect::Set { .. }) => {
                if self.reqs.len() >= SINKS_IN_FLIGHT {
                    self.waiting.push_back((qid.to_owned(), sink));
                    return;
                }
                cx.used += 1;
                let (call, r) = match sink {
                    Effect::Invoke {
                        call,
                        key,
                        action,
                        args,
                    } => (call, cx.host.invoke(&key, &action, args)),
                    Effect::Set { call, key, value } => (call, cx.host.set(&key, value)),
                    _ => unreachable!("a sink"),
                };
                match r {
                    Ok(ReqId(id)) => {
                        self.reqs.insert(id, (qid.to_owned(), call));
                    }
                    Err(e) => {
                        cx.host.log(
                            Level::Info,
                            &format!("query {qid}: sink call refused: {}", e.status.name()),
                        );
                        cx.used += 1;
                        if let Some(en) = q.engine.as_mut() {
                            en.on_reply(call, false, now, &mut out);
                        }
                    }
                }
            }
        }
        if !out.is_empty() {
            self.effects(qid, out);
        }
    }

    /// Publish tables that are due, show changed attributes, renew counters, and arm the timer.
    fn settle(&mut self, cx: &mut Cx<'_>) {
        let now = cx.now();
        // ad-hoc queries whose time is up
        let expired: Vec<String> = self
            .queries
            .iter()
            .filter(|(_, q)| q.expires_us.is_some_and(|t| t <= now))
            .map(|(id, _)| id.clone())
            .collect();
        for id in expired {
            self.remove_query(cx, &id);
        }
        // throttled sinks, collection timeouts
        let ids: Vec<String> = self.queries.keys().cloned().collect();
        for id in &ids {
            let mut out = Vec::new();
            if let Some(e) = self.queries.get_mut(id).and_then(|q| q.engine.as_mut()) {
                if e.next_wake_us().is_some_and(|t| t <= now) {
                    e.tick(now, &mut out);
                }
            }
            self.effects(id, out);
        }
        self.drain(cx);
        for id in &ids {
            if !cx.room() {
                break;
            }
            let Some(q) = self.queries.get_mut(id) else {
                continue;
            };
            if let Some(e) = q.engine.as_mut() {
                if e.take_dirty() {
                    q.dirty = true;
                }
            }
            let every = q.def.publish_ms * 1000;
            let due = q.last_publish_us.is_none_or(|t| now >= t + every);
            if q.dirty && due {
                let rows = q
                    .engine
                    .as_ref()
                    .map(|e| e.table(0, wyrm_dql::engine::MAX_ROWS))
                    .unwrap_or_default();
                q.rows_shown = rows.len();
                cx.host.update(
                    &tree::table(id),
                    Sample {
                        v: Value::Array(rows),
                        q: Quality::Good,
                        t: now,
                    },
                );
                cx.used += 1;
                q.dirty = false;
                q.last_publish_us = Some(now);
            }
            let mut attrs = q.attrs();
            attrs.insert(
                "last_publish".into(),
                q.last_publish_us.map_or(Value::Null, rfc3339),
            );
            if q.shown.as_ref() != Some(&attrs) {
                cx.host
                    .declare_node(id, tree::query_meta(attrs.clone(), &q.def.display));
                cx.used += 1;
                q.shown = Some(attrs);
            }
        }
        self.show_stats(cx);
        self.arm(cx);
    }

    fn show_stats(&mut self, cx: &mut Cx<'_>) {
        let mut now = [0u64; 5];
        now[0] = self.queries.len() as u64;
        for q in self.queries.values() {
            if let Some(e) = &q.engine {
                now[1] += e.rows() as u64;
                now[2] += e.progress().lists as u64;
                now[4] += e.progress().sink_calls;
            }
            now[3] += q.handles.len() as u64;
        }
        now[3] = now[3].saturating_sub(now[2]);
        let t = cx.now();
        for (i, n) in tree::STAT_NAMES.iter().enumerate() {
            if self.stats[i] != now[i] && cx.room() {
                cx.host.update(
                    &tree::stat(n),
                    Sample {
                        v: Value::UInt(now[i]),
                        q: Quality::Good,
                        t,
                    },
                );
                cx.used += 1;
                self.stats[i] = now[i];
            }
        }
    }

    /// One timer for everything: the backlog, publications, engine wakes, expiries.
    fn arm(&mut self, cx: &mut Cx<'_>) {
        let now = cx.now();
        let mut due: Option<u64> = None;
        let mut at = |t: u64| due = Some(due.map_or(t, |d| d.min(t)));
        if !self.backlog.is_empty()
            || !self.closing.is_empty()
            || (!self.waiting.is_empty() && self.reqs.len() < SINKS_IN_FLIGHT)
        {
            at(now);
        }
        for q in self.queries.values() {
            if q.dirty || q.engine.as_ref().is_some_and(|e| e.rows() != q.rows_shown) {
                at(q.last_publish_us
                    .map_or(now, |t| t + q.def.publish_ms * 1000));
            }
            if let Some(t) = q.engine.as_ref().and_then(Engine::next_wake_us) {
                at(t);
            }
            if let Some(t) = q.expires_us {
                at(t);
            }
        }
        let Some(due) = due else {
            if let Some((t, _)) = self.timer.take() {
                cx.host.cancel_timer(t);
            }
            return;
        };
        let due = due.max(now);
        if self.timer.is_some_and(|(_, d)| d == due) {
            return;
        }
        if let Some((t, _)) = self.timer.take() {
            cx.host.cancel_timer(t);
        }
        if let Ok(t) = cx.host.set_timer((due - now).div_ceil(1000)) {
            self.timer = Some((t, due));
        }
    }

    fn add(&mut self, cx: &mut Cx<'_>, m: &Args, who: &Who) -> Result<Value, AppError> {
        let id = req_str(m, "id")?;
        check_id(&id)?;
        if self.queries.contains_key(&id) {
            return Err(invalid("id", format!("{id} exists")));
        }
        if self.queries.len() >= MAX_QUERIES {
            return Err(AppError::new(
                Status::ResourceExhausted,
                format!("at most {MAX_QUERIES} queries"),
            ));
        }
        let text = req_str(m, "text")?;
        refuse_sinks(&text, who)?;
        let rights = rights_of(who)?;
        let def = Def {
            id: id.clone(),
            display: opt_str(m, "display")?.unwrap_or_else(|| id.clone()),
            text,
            enabled: opt_bool(m, "enabled")?.unwrap_or(true),
            publish_ms: publish_ms(m)?.unwrap_or(DEFAULT_PUBLISH_MS),
            created_by: who.subject.clone().unwrap_or_default(),
            rights: Some(rights),
        };
        self.save(cx, &def, true)?;
        self.queries.insert(id.clone(), Query::new(def));
        self.declare_query(cx, &id);
        self.start_query(cx, &id);
        Ok(Value::Map([("id".to_owned(), Value::Str(id))].into()))
    }

    fn save(&mut self, cx: &mut Cx<'_>, def: &Def, new: bool) -> Result<(), AppError> {
        cx.used += 1;
        store::put_def(cx.host, def)?;
        if new && !self.index.contains(&def.id) {
            let mut index = self.index.clone();
            index.push(def.id.clone());
            cx.used += 1;
            store::put_index(cx.host, &index)?;
            self.index = index;
        }
        Ok(())
    }

    fn run(&mut self, cx: &mut Cx<'_>, m: &Args, who: &Who) -> Result<Value, AppError> {
        let text = req_str(m, "text")?;
        let ttl_s = opt_uint(m, "ttl_s")?
            .unwrap_or(DEFAULT_TTL_S)
            .clamp(1, MAX_TTL_S);
        refuse_sinks(&text, who)?;
        let rights = rights_of(who)?;
        let now = cx.now();
        // identical text with the same author rights shares one ad-hoc query (DSA's
        // QueryManager): a table made with one user's rights is never handed to another
        let id = match opt_str(m, "id")? {
            Some(id) => {
                check_id(&id)?;
                id
            }
            None => self
                .queries
                .iter()
                .find(|(_, q)| {
                    q.expires_us.is_some()
                        && q.def.text == text.trim()
                        && q.def.rights.as_ref() == Some(&rights)
                })
                .map(|(id, _)| id.clone())
                .unwrap_or_else(|| {
                    self.next_run += 1;
                    format!("run-{}", self.next_run)
                }),
        };
        if let Some(q) = self.queries.get(&id) {
            if q.def.text != text.trim() || q.def.rights.as_ref() != Some(&rights) {
                guard_sink_query(&q.def.text, who, "replace")?;
            }
        }
        match self.queries.get_mut(&id) {
            Some(q) if q.expires_us.is_none() => {
                return Err(invalid("id", format!("{id} is a stored query")));
            }
            Some(q) if q.def.text == text.trim() && q.def.rights.as_ref() == Some(&rights) => {
                q.ttl_s = ttl_s;
                q.expires_us = Some(now + ttl_s * 1_000_000);
            }
            existing => {
                if existing.is_none() && self.queries.len() >= MAX_QUERIES {
                    return Err(AppError::new(
                        Status::ResourceExhausted,
                        format!("at most {MAX_QUERIES} queries"),
                    ));
                }
                let def = Def {
                    id: id.clone(),
                    display: id.clone(),
                    text: text.trim().to_owned(),
                    enabled: true,
                    publish_ms: publish_ms(m)?.unwrap_or(DEFAULT_PUBLISH_MS),
                    created_by: who.subject.clone().unwrap_or_default(),
                    rights: Some(rights),
                };
                let mut q = Query::new(def);
                q.ttl_s = ttl_s;
                q.expires_us = Some(now + ttl_s * 1_000_000);
                if self.queries.contains_key(&id) {
                    self.stop_query(cx, &id);
                }
                self.queries.insert(id.clone(), q);
                self.declare_query(cx, &id);
                self.start_query(cx, &id);
            }
        }
        Ok(Value::Map(
            [
                ("id".to_owned(), Value::Str(id.clone())),
                ("table".to_owned(), Value::Str(tree::table(&id))),
            ]
            .into(),
        ))
    }

    fn edit(&mut self, cx: &mut Cx<'_>, id: &str, m: &Args, who: &Who) -> Result<Value, AppError> {
        let q = self.queries.get(id).ok_or_else(|| not_found(id))?;
        guard_sink_query(&q.def.text, who, "edit")?;
        let mut def = q.def.clone();
        if let Some(d) = opt_str(m, "display")? {
            def.display = d;
        }
        let text = opt_str(m, "text")?;
        if let Some(t) = &text {
            refuse_sinks(t, who)?;
            def.text = t.trim().to_owned();
            // a new text runs with its editor's rights
            def.rights = Some(rights_of(who)?);
            def.created_by = who.subject.clone().unwrap_or_default();
        }
        if let Some(p) = publish_ms(m)? {
            def.publish_ms = p;
        }
        let restart = def.text != q.def.text || def.rights != q.def.rights;
        if q.expires_us.is_none() {
            self.save(cx, &def, false)?;
        }
        if let Some(q) = self.queries.get_mut(id) {
            q.def = def;
            q.shown = None;
        }
        self.declare_query(cx, id);
        if restart {
            self.start_query(cx, id);
        }
        Ok(Value::Null)
    }

    fn remove(&mut self, cx: &mut Cx<'_>, id: &str) -> Result<Value, AppError> {
        let stored = self
            .queries
            .get(id)
            .ok_or_else(|| not_found(id))?
            .expires_us
            .is_none();
        if stored {
            let index: Vec<String> = self.index.iter().filter(|i| *i != id).cloned().collect();
            store::put_index(cx.host, &index)?;
            store::delete_def(cx.host, id);
            cx.used += 2;
            self.index = index;
        }
        self.remove_query(cx, id);
        Ok(Value::Null)
    }

    fn get_table(&mut self, cx: &mut Cx<'_>, id: &str, m: &Args) -> Result<Value, AppError> {
        let now = cx.now();
        let q = self.queries.get_mut(id).ok_or_else(|| not_found(id))?;
        if q.expires_us.is_some() {
            q.expires_us = Some(now + q.ttl_s * 1_000_000);
        }
        let from = opt_uint(m, "from")?.unwrap_or(0) as usize;
        let limit =
            (opt_uint(m, "limit")?.unwrap_or(TABLE_PAGE as u64) as usize).clamp(1, MAX_TABLE_PAGE);
        let (rows, total, cols) = match &q.engine {
            Some(e) => (e.table(from, limit), e.rows(), e.columns().to_vec()),
            None => (Vec::new(), 0, Vec::new()),
        };
        let mut out = BTreeMap::new();
        out.insert("rows".into(), Value::Array(rows));
        out.insert("total".into(), Value::UInt(total as u64));
        out.insert(
            "columns".into(),
            Value::Array(cols.into_iter().map(Value::Str).collect()),
        );
        out.insert("status".into(), Value::Str(q.status().into()));
        Ok(Value::Map(out))
    }

    fn import(&mut self, cx: &mut Cx<'_>, m: &Args, who: &Who) -> Result<Value, AppError> {
        let json = req_str(m, "json")?;
        let mut def = store::from_json(&json).map_err(|e| invalid("json", e))?;
        if let Some(id) = opt_str(m, "id")? {
            def.id = id;
        }
        check_id(&def.id)?;
        let overwrite = opt_bool(m, "overwrite")?.unwrap_or(false);
        if let Some(q) = self.queries.get(&def.id) {
            if !overwrite || q.expires_us.is_some() {
                return Err(invalid("id", format!("{} exists", def.id)));
            }
        } else if self.queries.len() >= MAX_QUERIES {
            return Err(AppError::new(
                Status::ResourceExhausted,
                format!("at most {MAX_QUERIES} queries"),
            ));
        }
        parse(&def.text).map_err(|e| invalid("text", e))?;
        if !(MIN_PUBLISH_MS..=MAX_PUBLISH_MS).contains(&def.publish_ms) {
            return Err(invalid(
                "publish_ms",
                format!("{MIN_PUBLISH_MS} to {MAX_PUBLISH_MS}"),
            ));
        }
        def.created_by = who.subject.clone().unwrap_or_default();
        def.rights = Some(rights_of(who)?);
        let id = def.id.clone();
        self.save(cx, &def, true)?;
        if self.queries.contains_key(&id) {
            self.stop_query(cx, &id);
        }
        self.queries.insert(id.clone(), Query::new(def));
        self.declare_query(cx, &id);
        self.start_query(cx, &id);
        Ok(Value::Map([("id".to_owned(), Value::Str(id))].into()))
    }

    fn invoke(
        &mut self,
        cx: &mut Cx<'_>,
        path: &str,
        action: &str,
        m: &Args,
        who: &Who,
    ) -> Result<Value, AppError> {
        match (path, action) {
            ("", "add_query") => self.add(cx, m, who),
            ("", "run") => self.run(cx, m, who),
            ("", "import") => self.import(cx, m, who),
            ("", "explain") => Ok(wyrm_dql::explain(&req_str(m, "text")?)),
            ("", "convert_dsa") => {
                let site = req_str(m, "site")?;
                let text = wyrm_dql::dsa::convert(&req_str(m, "text")?, &site)
                    .map_err(|e| invalid("text", e))?;
                Ok(Value::Map([("text".to_owned(), Value::Str(text))].into()))
            }
            (id, "get_table") => self.get_table(cx, id, m),
            (id, "export") => {
                let q = self.queries.get(id).ok_or_else(|| not_found(id))?;
                Ok(Value::Map(
                    [("json".to_owned(), Value::Str(store::to_json(&q.def)))].into(),
                ))
            }
            (id, "edit") => self.edit(cx, id, m, who),
            (id, "remove") => {
                if let Some(q) = self.queries.get(id) {
                    guard_sink_query(&q.def.text, who, "remove")?;
                }
                self.remove(cx, id)
            }
            _ => Err(AppError::new(
                Status::NotFound,
                format!("no action {action} on {path:?}"),
            )),
        }
    }

    fn set(
        &mut self,
        cx: &mut Cx<'_>,
        path: &str,
        value: Value,
        who: &Who,
    ) -> Result<(), AppError> {
        let id = path
            .strip_suffix("/enabled")
            .filter(|id| self.queries.contains_key(*id))
            .ok_or_else(|| AppError::new(Status::NotFound, format!("{path} is not writable")))?
            .to_owned();
        let Value::Bool(on) = value else {
            return Err(invalid("value", "true or false"));
        };
        let q = self.queries.get(&id).ok_or_else(|| not_found(&id))?;
        if q.def.enabled == on {
            return Ok(());
        }
        if on {
            guard_sink_query(&q.def.text, who, "switch on")?;
        }
        let mut def = q.def.clone();
        def.enabled = on;
        if q.expires_us.is_none() {
            self.save(cx, &def, false)?;
        }
        if let Some(q) = self.queries.get_mut(&id) {
            q.def = def;
        }
        self.declare_query(cx, &id);
        if on {
            self.start_query(cx, &id);
        } else {
            self.stop_query(cx, &id);
            if let Some(q) = self.queries.get_mut(&id) {
                q.dirty = true;
            }
        }
        Ok(())
    }
}

fn not_found(id: &str) -> AppError {
    AppError::new(Status::NotFound, format!("no query {id}"))
}

impl App for Dql {
    const NAME: &'static str = "dql";
    const VERSION: &'static str = env!("CARGO_PKG_VERSION");

    fn start(host: &mut dyn Host, config: Value) -> Result<Self, AppError> {
        match config {
            Value::Null | Value::Map(_) => {}
            _ => return Err(invalid("params", "a map")),
        }
        let mut cx = Cx { host, used: 0 };
        for (name, a) in tree::root_actions() {
            cx.host.declare_action("", name, a);
            cx.used += 1;
        }
        cx.host.declare_node(tree::STATS, tree::stats_meta());
        for n in tree::STAT_NAMES {
            cx.host.declare_node(&tree::stat(n), tree::stat_meta(n));
        }
        cx.used += 1 + tree::STAT_NAMES.len();
        let index = match store::load_index(cx.host) {
            Ok(i) => i,
            Err(e) => {
                cx.host
                    .log(Level::Error, &format!("store index unreadable: {e}"));
                Vec::new()
            }
        };
        let mut app = Dql {
            queries: BTreeMap::new(),
            index: index.clone(),
            subs: HashMap::new(),
            reqs: HashMap::new(),
            backlog: VecDeque::new(),
            closing: VecDeque::new(),
            waiting: VecDeque::new(),
            timer: None,
            stats: [u64::MAX; 5],
            next_run: 0,
        };
        for id in index {
            match store::load_def(cx.host, &id) {
                Ok(def) => {
                    app.queries.insert(id.clone(), Query::new(def));
                    app.declare_query(&mut cx, &id);
                    app.start_query(&mut cx, &id);
                }
                Err(e) => cx.host.log(Level::Error, &format!("query {id}: {e}")),
            }
        }
        app.settle(&mut cx);
        Ok(app)
    }

    fn on_set(
        &mut self,
        host: &mut dyn Host,
        path: &str,
        value: Value,
        who: &Who,
    ) -> Result<(), AppError> {
        let mut cx = Cx { host, used: 0 };
        let r = self.set(&mut cx, path, value, who);
        self.settle(&mut cx);
        r
    }

    fn on_invoke(
        &mut self,
        host: &mut dyn Host,
        path: &str,
        action: &str,
        args: Value,
        who: &Who,
    ) -> Result<Value, AppError> {
        let m = args_of(args)?;
        let mut cx = Cx { host, used: 0 };
        let r = self.invoke(&mut cx, path, action, &m, who);
        self.settle(&mut cx);
        r
    }

    fn on_timer(&mut self, host: &mut dyn Host, timer: TimerId) {
        if self.timer.is_some_and(|(t, _)| t == timer) {
            self.timer = None;
        }
        let mut cx = Cx { host, used: 0 };
        self.settle(&mut cx);
    }

    fn on_value(&mut self, host: &mut dyn Host, sub: SubId, key: &str, sample: Sample) {
        let mut cx = Cx { host, used: 0 };
        if let Some((qid, _)) = self.subs.get(&sub.0).cloned() {
            let now = cx.now();
            let mut out = Vec::new();
            if let Some(e) = self.queries.get_mut(&qid).and_then(|q| q.engine.as_mut()) {
                e.on_value(key, sample, now, &mut out);
            }
            self.effects(&qid, out);
        }
        self.settle(&mut cx);
    }

    fn on_list(&mut self, host: &mut dyn Host, sub: SubId, _key: &str, change: ListChange) {
        let mut cx = Cx { host, used: 0 };
        if let Some((qid, h)) = self.subs.get(&sub.0).cloned() {
            let now = cx.now();
            let mut out = Vec::new();
            if let Some(e) = self.queries.get_mut(&qid).and_then(|q| q.engine.as_mut()) {
                e.on_list(h, change, now, &mut out);
            }
            self.effects(&qid, out);
        }
        self.settle(&mut cx);
    }

    fn on_reply(&mut self, host: &mut dyn Host, req: ReqId, result: Result<Value, AppError>) {
        let mut cx = Cx { host, used: 0 };
        if let Some((qid, call)) = self.reqs.remove(&req.0) {
            let now = cx.now();
            if let Err(e) = &result {
                cx.host.log(
                    Level::Info,
                    &format!("query {qid}: sink call failed: {}", e.status.name()),
                );
                cx.used += 1;
            }
            let mut out = Vec::new();
            if let Some(e) = self.queries.get_mut(&qid).and_then(|q| q.engine.as_mut()) {
                e.on_reply(call, result.is_ok(), now, &mut out);
            }
            self.effects(&qid, out);
        }
        self.settle(&mut cx);
    }
}

// Only on wasm32: natively the exports would be bare global `start`/`stop`… symbols.
#[cfg(all(feature = "wasm", target_arch = "wasm32"))]
wyrm_link_guest::export!(Dql);
