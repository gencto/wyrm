//! The row engine of one query (ADR 0025): a pure state machine. The host feeds it list
//! changes, samples, sink replies and the time; it answers with [`Effect`]s (lists,
//! subscriptions, sink calls) and keeps the table.
//!
//! - **Rows:** a node is a candidate of a segment when its key matches one of the segment's
//!   patterns; the segment's stages make its columns or drop it. Rows of the last segment are the
//!   table; a row of an earlier segment that passes is the root of a `sublist` below it.
//! - **Lists:** a list is opened on a node when the pattern can reach below it and the node is a
//!   folder (no `type`); at most [`Limits::max_lists`] per query.
//! - **Values:** one subtree subscription per root prefix (`<prefix>/**`); samples of keys no row
//!   needs yet are cached (at most [`Limits::max_cache`]), so a row that appears later has them.
//! - **Sinks** (D3, D5): the first complete arguments of a row are its baseline; a call or a
//!   write goes out only when they change from it, one in flight per row and sink, at most one
//!   per `throttle_ms`; a failed one is counted, not retried.

use std::collections::{BTreeMap, BTreeSet, HashMap};

use ::cel::Context;
use wyrm_core::meta::{Profile, TextOrCode};
use wyrm_core::{NodeMeta, Perm, Quality, Sample, Value};
use wyrm_link_api::{ListChange, Who};

use crate::cel;
use crate::parse::{Arg, Column, Part, Plan, Sink, Source, Stage};
use crate::pattern::{resolve, Pattern};

/// A list or a subscription of the engine; the host maps it to its own handle.
pub type Handle = u64;

/// Rows of one query unless `option max_rows` says less.
pub const DEFAULT_ROWS: usize = 1_000;
/// The most rows a query may ask for.
pub const MAX_ROWS: usize = 5_000;
/// Lists open at once in one query (the host allows 2 000 per link).
pub const MAX_LISTS: usize = 1_000;
/// Samples of keys no row needs yet, kept for rows that may appear.
pub const MAX_CACHE: usize = 20_000;
/// A query is `ready` with an `incomplete` error this long after its start unless
/// `option timeout_s` says otherwise.
pub const DEFAULT_TIMEOUT_S: u64 = 30;
pub const MAX_TIMEOUT_S: u64 = 600;
/// Rows still without a value this long after `ready` (then twice as long, …) open their
/// root's subscription again: its first read of the stored values may have lost replies (a
/// peer hop), and a point that does not change sends nothing more.
pub const REFETCH_AFTER_MS: u64 = 2_000;
/// At most this many refetches per query.
pub const MAX_REFETCHES: u32 = 3;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Limits {
    pub max_rows: usize,
    pub max_lists: usize,
    pub max_cache: usize,
}

impl Default for Limits {
    fn default() -> Self {
        Self {
            max_rows: DEFAULT_ROWS,
            max_lists: MAX_LISTS,
            max_cache: MAX_CACHE,
        }
    }
}

/// What the engine asks the host to do.
#[derive(Debug, Clone, PartialEq)]
pub enum Effect {
    List {
        h: Handle,
        key: String,
        full: bool,
    },
    /// `key` is `<prefix>/**`.
    Subscribe {
        h: Handle,
        key: String,
    },
    /// Ends a list or a subscription.
    Unsubscribe {
        h: Handle,
    },
    Invoke {
        call: u64,
        key: String,
        action: String,
        args: Value,
    },
    Set {
        call: u64,
        key: String,
        value: Value,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Status {
    /// Lists started by the query have not all answered yet.
    Collecting,
    Ready,
}

impl Status {
    pub fn name(self) -> &'static str {
        match self {
            Status::Collecting => "collecting",
            Status::Ready => "ready",
        }
    }
}

/// How the collection goes (D4): shown on the query node.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct Progress {
    pub lists: usize,
    pub lists_pending: usize,
    /// The deepest level reached below a root.
    pub depth: usize,
    /// Sites the lists touched (`wy/<site>`).
    pub sites: BTreeSet<String>,
    /// From the start to `ready`.
    pub collect_ms: Option<u64>,
    /// Expressions that failed on a row, sink calls that failed.
    pub errors: u64,
    pub sink_calls: u64,
    /// Subscriptions opened again for rows without a value ([`REFETCH_AFTER_MS`]).
    pub refetches: u32,
    /// Why the table may be incomplete (`max_rows`, `max_lists`, a refused list, a timeout).
    pub error: Option<String>,
}

struct ListState {
    root: u64,
    key: String,
    refreshed: bool,
    children: BTreeMap<String, NodeMeta>,
}

struct Root {
    seg: usize,
    pattern: Pattern,
    /// key → list handle
    lists: BTreeMap<String, Handle>,
}

struct Cand {
    meta: NodeMeta,
    roots: BTreeSet<u64>,
}

/// A row's columns in order.
type Cols = Vec<(String, Value)>;

/// A sink call a row asks for.
#[derive(Debug, Clone, PartialEq)]
struct SinkReq {
    key: String,
    action: Option<String>,
    payload: Value,
}

#[derive(Default)]
struct SinkState {
    last: Option<Value>,
    inflight: Option<u64>,
    pending: Option<SinkReq>,
    last_fire_us: Option<u64>,
}

/// One running query.
pub struct Engine {
    plan: Plan,
    limits: Limits,
    /// The author's rights and the site the query runs on (ADR 0025 item 4): rows, values and
    /// sink targets outside them are left out. `None`: no bound (`wyr query`, where the user's
    /// own token reads and writes).
    rights: Option<(Who, String)>,
    base: Context<'static, 'static>,
    next: u64,
    started_us: u64,
    timeout_us: u64,
    roots: HashMap<u64, Root>,
    lists: HashMap<Handle, ListState>,
    subs: BTreeMap<String, Handle>,
    /// segment → key → candidate
    cands: Vec<BTreeMap<String, Cand>>,
    /// segment (not the last) → row key → root of the next segment
    parents: Vec<BTreeMap<String, u64>>,
    values: HashMap<String, Sample>,
    /// value key → rows that read it
    deps: HashMap<String, BTreeSet<(usize, String)>>,
    row_keys: HashMap<(usize, String), Vec<String>>,
    table: BTreeMap<String, Vec<(String, Value)>>,
    columns: Vec<String>,
    dirty: bool,
    truncated: bool,
    sinks: HashMap<(String, usize), SinkState>,
    calls: HashMap<u64, (String, usize)>,
    progress: Progress,
    timed_out: bool,
    /// When the query became `ready` (µs).
    ready_us: Option<u64>,
}

fn site_of(key: &str) -> String {
    key.split('/').take(2).collect::<Vec<_>>().join("/")
}

fn meta_map(key: &str, m: &NodeMeta) -> BTreeMap<String, Value> {
    let mut out = BTreeMap::new();
    let s = |v: &str| Value::Str(v.to_owned());
    out.insert("path".into(), s(key));
    out.insert("name".into(), s(key.rsplit('/').next().unwrap_or(key)));
    let attr = m.attr.clone().unwrap_or_default();
    let display = m.display.clone().or_else(|| match attr.get("display") {
        Some(Value::Str(d)) => Some(d.clone()),
        _ => None,
    });
    let opt = |v: Option<Value>| v.unwrap_or(Value::Null);
    out.insert("type".into(), opt(m.ty.map(|t| s(t.name()))));
    out.insert(
        "unit".into(),
        opt(m.unit.as_ref().map(|u| match u {
            TextOrCode::Text(t) => s(t),
            TextOrCode::Code(c) => Value::UInt((*c).into()),
        })),
    );
    out.insert("writable".into(), opt(m.writable.map(|w| s(w.name()))));
    out.insert(
        "is".into(),
        opt(m.is.as_ref().map(|p| match p {
            Profile::Name(n) => s(n),
            Profile::Code(c) => Value::UInt((*c).into()),
        })),
    );
    out.insert("display".into(), opt(display.map(Value::Str)));
    out.insert(
        "actions".into(),
        Value::Array(
            m.actions
                .as_ref()
                .map(|a| a.keys().map(|k| s(k)).collect())
                .unwrap_or_default(),
        ),
    );
    out.insert(
        "quality".into(),
        opt(m
            .q
            .and_then(|q| Quality::try_from(q).ok())
            .map(|q| s(q.name()))),
    );
    out.insert("attr".into(), Value::Map(attr));
    out
}

fn set_col(cols: &mut Vec<(String, Value)>, name: &str, v: Value) {
    match cols.iter_mut().find(|(n, _)| n == name) {
        Some(c) => c.1 = v,
        None => cols.push((name.to_owned(), v)),
    }
}

/// A failed expression counts as an error only when what it reads is there: `value + 1`
/// before the first sample is not an error.
fn reads_nulls(
    e: &crate::cel::Expr,
    meta: &BTreeMap<String, Value>,
    cols: &[(String, Value)],
) -> bool {
    e.variables().iter().any(|v| {
        let found = cols
            .iter()
            .find(|(n, _)| n == v)
            .map(|(_, x)| x)
            .or_else(|| meta.get(v));
        match (v.as_str(), found) {
            ("row", _) => cols.iter().any(|(_, x)| matches!(x, Value::Null)),
            (_, Some(Value::Null)) | (_, None) => true,
            _ => false,
        }
    })
}

fn has_null(v: &Value) -> bool {
    match v {
        Value::Null => true,
        Value::Map(m) => m.values().any(|v| matches!(v, Value::Null)),
        _ => false,
    }
}

impl Engine {
    pub fn new(plan: Plan, mut limits: Limits) -> Self {
        if let Some(m) = plan.options.max_rows {
            limits.max_rows = m.clamp(1, MAX_ROWS);
        }
        let timeout_s = plan
            .options
            .timeout_s
            .unwrap_or(DEFAULT_TIMEOUT_S)
            .clamp(1, MAX_TIMEOUT_S);
        let segs = plan.segments.len();
        Self {
            plan,
            limits,
            rights: None,
            base: cel::base(),
            next: 1,
            started_us: 0,
            timeout_us: timeout_s * 1_000_000,
            roots: HashMap::new(),
            lists: HashMap::new(),
            subs: BTreeMap::new(),
            cands: (0..segs).map(|_| BTreeMap::new()).collect(),
            parents: (0..segs).map(|_| BTreeMap::new()).collect(),
            values: HashMap::new(),
            deps: HashMap::new(),
            row_keys: HashMap::new(),
            table: BTreeMap::new(),
            columns: Vec::new(),
            dirty: true,
            truncated: false,
            sinks: HashMap::new(),
            calls: HashMap::new(),
            progress: Progress::default(),
            timed_out: false,
            ready_us: None,
        }
    }

    pub fn plan(&self) -> &Plan {
        &self.plan
    }

    /// Bound the query to what `who` may do (its `authority`, spec 04 `auth`) on site `site`; a
    /// key of another site is checked with the grants rewritten to it, as the gateway mints them.
    pub fn with_rights(mut self, who: Who, site: &str) -> Self {
        self.rights = Some((who, site.to_owned()));
        self
    }

    /// The author may `need` on `key`.
    fn may(&self, key: &str, need: Perm) -> bool {
        let Some((who, own)) = &self.rights else {
            return true;
        };
        let site = key.strip_prefix("wy/").and_then(|r| r.split('/').next());
        match site {
            Some(site) if site != own => {
                let theirs = Who {
                    authority: who.authority.as_ref().map(|a| {
                        a.iter()
                            .map(|(k, p)| (wyrm_core::ptok::grant_for_site(k, own, site), *p))
                            .collect()
                    }),
                    ..Who::default()
                };
                theirs.may_for(key, need)
            }
            _ => who.may_for(key, need),
        }
    }

    fn id(&mut self) -> u64 {
        let i = self.next;
        self.next += 1;
        i
    }

    /// Opens the first lists and subscriptions.
    pub fn start(&mut self, now_us: u64, out: &mut Vec<Effect>) {
        self.started_us = now_us;
        let Some(Source::Roots(pats)) = self.plan.segments.first().map(|s| s.source.clone()) else {
            return;
        };
        for p in pats {
            if self.plan.uses_values() {
                let prefix = p.top.clone();
                if !self.subs.contains_key(&prefix) {
                    let h = self.id();
                    self.subs.insert(prefix.clone(), h);
                    out.push(Effect::Subscribe {
                        h,
                        key: format!("{prefix}/**"),
                    });
                }
            }
            self.new_root(0, p, out);
        }
        self.check_ready(now_us);
    }

    /// Every handle the engine holds, to end them (the query is removed or edited).
    pub fn stop(&mut self, out: &mut Vec<Effect>) {
        for h in self.lists.keys().chain(self.subs.values()) {
            out.push(Effect::Unsubscribe { h: *h });
        }
        out.sort_by_key(|e| match e {
            Effect::Unsubscribe { h } => *h,
            _ => 0,
        });
        self.lists.clear();
        self.subs.clear();
    }

    fn new_root(&mut self, seg: usize, pattern: Pattern, out: &mut Vec<Effect>) -> u64 {
        let rid = self.id();
        let top = pattern.top.clone();
        self.roots.insert(
            rid,
            Root {
                seg,
                pattern,
                lists: BTreeMap::new(),
            },
        );
        self.open_list(rid, top, out);
        rid
    }

    fn open_list(&mut self, rid: u64, key: String, out: &mut Vec<Effect>) {
        if self
            .roots
            .get(&rid)
            .is_some_and(|r| r.lists.contains_key(&key))
        {
            return;
        }
        if self.lists.len() >= self.limits.max_lists {
            self.progress.error = Some(format!(
                "max_lists: at most {} lists in one query; narrow the pattern",
                self.limits.max_lists
            ));
            return;
        }
        let h = self.id();
        self.progress.sites.insert(site_of(&key));
        self.lists.insert(
            h,
            ListState {
                root: rid,
                key: key.clone(),
                refreshed: false,
                children: BTreeMap::new(),
            },
        );
        if let Some(r) = self.roots.get_mut(&rid) {
            r.lists.insert(key.clone(), h);
        }
        out.push(Effect::List {
            h,
            key,
            full: self.plan.full_meta,
        });
    }

    /// The host refused a list or a subscription it was asked for.
    pub fn failed(&mut self, h: Handle, msg: &str, now_us: u64) {
        if let Some(ls) = self.lists.get_mut(&h) {
            if !ls.refreshed {
                ls.refreshed = true;
            }
            self.progress.error = Some(format!("{}: {msg}", ls.key));
        } else if let Some((k, _)) = self.subs.iter().find(|(_, v)| **v == h) {
            self.progress.error = Some(format!("{k}/**: {msg}"));
        }
        self.check_ready(now_us);
    }

    pub fn on_list(&mut self, h: Handle, change: ListChange, now_us: u64, out: &mut Vec<Effect>) {
        let Some(ls) = self.lists.get_mut(&h) else {
            return;
        };
        match change {
            ListChange::Refreshed(children) => {
                ls.refreshed = true;
                let new: BTreeSet<&String> = children.iter().map(|(n, _)| n).collect();
                let gone: Vec<String> = ls
                    .children
                    .keys()
                    .filter(|n| !new.contains(n))
                    .cloned()
                    .collect();
                for n in gone {
                    self.child_removed(h, &n, now_us, out);
                }
                for (n, m) in children {
                    self.child_upsert(h, n, m, now_us, out);
                }
            }
            ListChange::Added(n, m) | ListChange::Changed(n, m) => {
                self.child_upsert(h, n, m, now_us, out)
            }
            ListChange::Removed(n) => self.child_removed(h, &n, now_us, out),
            ListChange::Disconnected => {
                let names: Vec<String> = ls.children.keys().cloned().collect();
                for n in names {
                    self.child_removed(h, &n, now_us, out);
                }
            }
        }
        self.check_ready(now_us);
    }

    fn child_upsert(
        &mut self,
        h: Handle,
        name: String,
        meta: NodeMeta,
        now: u64,
        out: &mut Vec<Effect>,
    ) {
        let Some(ls) = self.lists.get_mut(&h) else {
            return;
        };
        let full = format!("{}/{name}", ls.key);
        let rid = ls.root;
        ls.children.insert(name, meta.clone());
        let Some(root) = self.roots.get(&rid) else {
            return;
        };
        let seg = root.seg;
        let Some(rel) = root.pattern.rel(&full) else {
            return;
        };
        let (matches, descend) = (root.pattern.matches(&rel), root.pattern.may_descend(&rel));
        self.progress.depth = self.progress.depth.max(rel.len());
        let folder = meta.ty.is_none() && meta.has_children != Some(false);
        if matches {
            let c = self.cands[seg].entry(full.clone()).or_insert_with(|| Cand {
                meta: meta.clone(),
                roots: BTreeSet::new(),
            });
            c.meta = meta;
            c.roots.insert(rid);
            self.eval_row(seg, &full, now, out);
        }
        if descend && folder {
            self.open_list(rid, full, out);
        } else if self
            .roots
            .get(&rid)
            .is_some_and(|r| r.lists.contains_key(&full))
        {
            self.close_below(rid, &full, now, out);
        }
    }

    fn child_removed(&mut self, h: Handle, name: &str, now: u64, out: &mut Vec<Effect>) {
        let Some(ls) = self.lists.get_mut(&h) else {
            return;
        };
        if ls.children.remove(name).is_none() {
            return;
        }
        let full = format!("{}/{name}", ls.key);
        let rid = ls.root;
        self.close_below(rid, &full, now, out);
        self.cand_remove(rid, &full, now, out);
    }

    /// Ends the lists of root `rid` at `key` and below, and their candidates.
    fn close_below(&mut self, rid: u64, key: &str, now: u64, out: &mut Vec<Effect>) {
        let Some(root) = self.roots.get(&rid) else {
            return;
        };
        let below = format!("{key}/");
        let hs: Vec<(String, Handle)> = root
            .lists
            .iter()
            .filter(|(k, _)| *k == key || k.starts_with(&below))
            .map(|(k, h)| (k.clone(), *h))
            .collect();
        for (k, h) in hs {
            if let Some(r) = self.roots.get_mut(&rid) {
                r.lists.remove(&k);
            }
            if let Some(ls) = self.lists.remove(&h) {
                out.push(Effect::Unsubscribe { h });
                for name in ls.children.keys() {
                    self.cand_remove(rid, &format!("{}/{name}", ls.key), now, out);
                }
            }
        }
    }

    fn cand_remove(&mut self, rid: u64, key: &str, now: u64, out: &mut Vec<Effect>) {
        let Some(seg) = self.roots.get(&rid).map(|r| r.seg) else {
            return;
        };
        let gone = match self.cands[seg].get_mut(key) {
            Some(c) => {
                c.roots.remove(&rid);
                c.roots.is_empty()
            }
            None => false,
        };
        if gone {
            self.cands[seg].remove(key);
            self.row_gone(seg, key, now, out);
        }
    }

    fn row_gone(&mut self, seg: usize, key: &str, now: u64, out: &mut Vec<Effect>) {
        if let Some(keys) = self.row_keys.remove(&(seg, key.to_owned())) {
            for k in keys {
                if let Some(d) = self.deps.get_mut(&k) {
                    d.remove(&(seg, key.to_owned()));
                    if d.is_empty() {
                        self.deps.remove(&k);
                    }
                }
            }
        }
        if seg + 1 == self.plan.segments.len() {
            if self.table.remove(key).is_some() {
                self.dirty = true;
                self.refill(now, out);
            }
            self.sinks.retain(|(r, _), _| r != key);
        } else if let Some(child) = self.parents[seg].remove(key) {
            self.drop_root(child, now, out);
        }
    }

    fn drop_root(&mut self, rid: u64, now: u64, out: &mut Vec<Effect>) {
        let Some(top) = self.roots.get(&rid).map(|r| r.pattern.top.clone()) else {
            return;
        };
        self.close_below(rid, &top, now, out);
        self.roots.remove(&rid);
    }

    /// After a row went: candidates the row bound kept out get their turn.
    fn refill(&mut self, now: u64, out: &mut Vec<Effect>) {
        if !self.truncated {
            return;
        }
        self.truncated = false;
        let last = self.plan.segments.len() - 1;
        let waiting: Vec<String> = self.cands[last]
            .keys()
            .filter(|k| !self.table.contains_key(*k))
            .cloned()
            .collect();
        for k in waiting {
            if self.table.len() >= self.limits.max_rows {
                self.truncated = true;
                break;
            }
            self.eval_row(last, &k, now, out);
        }
    }

    pub fn on_value(&mut self, key: &str, sample: Sample, now: u64, out: &mut Vec<Effect>) {
        if !self.may(key, Perm::Read) {
            return;
        }
        let wanted = self.deps.contains_key(key);
        if wanted || self.values.contains_key(key) || self.values.len() < self.limits.max_cache {
            self.values.insert(key.to_owned(), sample);
        }
        if let Some(rows) = self.deps.get(key).cloned() {
            for (seg, row) in rows {
                self.eval_row(seg, &row, now, out);
            }
        }
    }

    /// The value keys a row of `seg` reads.
    fn value_keys(&self, seg: usize, key: &str) -> Vec<String> {
        let mut out = Vec::new();
        for s in &self.plan.segments[seg].stages {
            if let Stage::Subscribe(cols) = s {
                for c in cols {
                    if !matches!(c.key.part, Part::Value | Part::Timestamp | Part::Quality) {
                        continue;
                    }
                    let k = match &c.key.node {
                        None => Some(key.to_owned()),
                        Some(rel) => resolve(key, rel).ok(),
                    };
                    if let Some(k) = k {
                        if !out.contains(&k) {
                            out.push(k);
                        }
                    }
                }
            }
        }
        out
    }

    fn column(&self, key: &str, meta: &BTreeMap<String, Value>, c: &Column) -> Value {
        let sample = |k: &str| self.values.get(k);
        let node = match &c.key.node {
            None => Some(key.to_owned()),
            Some(rel) => resolve(key, rel).ok(),
        };
        match (&c.key.part, node) {
            (Part::Meta(f), _) => meta.get(f).cloned().unwrap_or(Value::Null),
            (Part::Attr(a), _) => match meta.get("attr") {
                Some(Value::Map(m)) => m.get(a).cloned().unwrap_or(Value::Null),
                _ => Value::Null,
            },
            (_, None) => Value::Null,
            (Part::Value, Some(k)) => sample(&k).map(|s| s.v.clone()).unwrap_or(Value::Null),
            (Part::Timestamp, Some(k)) => {
                sample(&k).map(|s| Value::UInt(s.t)).unwrap_or(Value::Null)
            }
            (Part::Quality, Some(k)) => sample(&k)
                .map(|s| Value::Str(s.q.name().to_owned()))
                .unwrap_or(Value::Null),
        }
    }

    /// The row's columns, or `None` when a `where` drops it; and the sink calls it asks for.
    fn evaluate(&mut self, seg: usize, key: &str) -> (Option<Cols>, Vec<(usize, SinkReq)>) {
        let Some(cand) = self.cands[seg].get(key) else {
            return (None, Vec::new());
        };
        // a node its author may not read is no row (as the gateway hides it when browsing)
        if !self.may(key, Perm::Read) {
            return (None, Vec::new());
        }
        let meta = meta_map(key, &cand.meta);
        let mut cols: Vec<(String, Value)> = vec![("path".into(), Value::Str(key.to_owned()))];
        let mut sinks = Vec::new();
        let mut errors = 0u64;
        let stages = &self.plan.segments[seg].stages;
        for (i, st) in stages.iter().enumerate() {
            match st {
                Stage::Subscribe(cs) => {
                    for c in cs {
                        let v = self.column(key, &meta, c);
                        set_col(&mut cols, &c.name, v);
                    }
                }
                Stage::Where(e) => {
                    let row = cel::Row::new(&meta, &cols);
                    match row.eval(&self.base, e) {
                        Ok(Value::Bool(true)) => {}
                        Ok(_) => return (None, Vec::new()),
                        Err(_) => {
                            if !reads_nulls(e, &meta, &cols) {
                                self.progress.errors += 1;
                            }
                            return (None, Vec::new());
                        }
                    }
                }
                Stage::Expression(es) => {
                    for (name, e) in es {
                        let row = cel::Row::new(&meta, &cols);
                        let v = row.eval(&self.base, e).unwrap_or_else(|_| {
                            if !reads_nulls(e, &meta, &cols) {
                                errors += 1;
                            }
                            Value::Null
                        });
                        set_col(&mut cols, name, v);
                    }
                }
                Stage::Rename(r) => {
                    for (a, b) in r {
                        if let Some(c) = cols.iter_mut().find(|(n, _)| n == a) {
                            c.0.clone_from(b);
                        }
                    }
                }
                Stage::Drop(d) => cols.retain(|(n, _)| !d.contains(n)),
                Stage::Sink(s) => {
                    let arg = |a: &Arg, errors: &mut u64| match a {
                        Arg::Col(c) => cols
                            .iter()
                            .find(|(n, _)| n == c)
                            .map(|(_, v)| v.clone())
                            .unwrap_or(Value::Null),
                        Arg::Expr(e) => {
                            let row = cel::Row::new(&meta, &cols);
                            row.eval(&self.base, e).unwrap_or_else(|_| {
                                if !reads_nulls(e, &meta, &cols) {
                                    *errors += 1;
                                }
                                Value::Null
                            })
                        }
                    };
                    let req = match s {
                        Sink::Invoke {
                            node,
                            action,
                            params,
                        } => resolve(key, node).map(|k| SinkReq {
                            key: k,
                            action: Some(action.clone()),
                            payload: Value::Map(
                                params
                                    .iter()
                                    .map(|(p, a)| (p.clone(), arg(a, &mut errors)))
                                    .collect(),
                            ),
                        }),
                        Sink::Set { node, value } => resolve(key, node).map(|k| SinkReq {
                            key: k,
                            action: None,
                            payload: arg(value, &mut errors),
                        }),
                    };
                    match req {
                        Ok(r) => sinks.push((i, r)),
                        Err(_) => errors += 1,
                    }
                }
            }
        }
        self.progress.errors += errors;
        (Some(cols), sinks)
    }

    fn eval_row(&mut self, seg: usize, key: &str, now: u64, out: &mut Vec<Effect>) {
        if !self.cands[seg].contains_key(key) {
            return;
        }
        let rk = (seg, key.to_owned());
        if !self.row_keys.contains_key(&rk) {
            let keys = self.value_keys(seg, key);
            for k in &keys {
                self.deps.entry(k.clone()).or_default().insert(rk.clone());
            }
            self.row_keys.insert(rk, keys);
        }
        let last = seg + 1 == self.plan.segments.len();
        if last && !self.table.contains_key(key) && self.table.len() >= self.limits.max_rows {
            self.truncated = true;
            self.progress.error = Some(format!(
                "max_rows: the table keeps its first {} rows",
                self.limits.max_rows
            ));
            return;
        }
        let (cols, sinks) = self.evaluate(seg, key);
        if last {
            match cols {
                Some(cols) => {
                    for (n, _) in &cols {
                        if !self.columns.contains(n) {
                            self.columns.push(n.clone());
                        }
                    }
                    if self.table.get(key) != Some(&cols) {
                        self.table.insert(key.to_owned(), cols);
                        self.dirty = true;
                    }
                    for (i, r) in sinks {
                        self.sink(key, i, r, now, out);
                    }
                }
                None => {
                    if self.table.remove(key).is_some() {
                        self.dirty = true;
                        self.refill(now, out);
                    }
                    // a row that comes back starts from a new baseline
                    self.sinks.retain(|(r, _), _| r != key);
                }
            }
        } else {
            let passes = cols.is_some();
            let has = self.parents[seg].contains_key(key);
            if passes && !has {
                if let Source::Below(segs) = self.plan.segments[seg + 1].source.clone() {
                    let rid = self.new_root(seg + 1, Pattern::below(key, &segs), out);
                    self.parents[seg].insert(key.to_owned(), rid);
                }
            } else if !passes && has {
                if let Some(rid) = self.parents[seg].remove(key) {
                    self.drop_root(rid, now, out);
                }
            }
        }
    }

    fn sink(&mut self, row: &str, idx: usize, r: SinkReq, now: u64, out: &mut Vec<Effect>) {
        // a target is checked when it fires: `..` may climb out of the root
        if !self.may(&r.key, Perm::Write) {
            self.progress.errors += 1;
            self.progress.error = Some(format!(
                "{}: outside the rights of the query's author",
                r.key
            ));
            return;
        }
        if !self.plan.options.invoke_allow_null && has_null(&r.payload) {
            return;
        }
        let throttle = self.plan.options.throttle_ms * 1000;
        let st = self.sinks.entry((row.to_owned(), idx)).or_default();
        let Some(last) = &st.last else {
            // the first complete arguments: the baseline, nothing is sent (D5)
            st.last = Some(r.payload);
            return;
        };
        if *last == r.payload {
            st.pending = None;
            return;
        }
        let held = st.inflight.is_some()
            || st
                .last_fire_us
                .is_some_and(|t| throttle > 0 && now < t + throttle);
        if held {
            st.pending = Some(r);
            return;
        }
        self.fire(row, idx, r, now, out);
    }

    fn fire(&mut self, row: &str, idx: usize, r: SinkReq, now: u64, out: &mut Vec<Effect>) {
        let call = self.id();
        let st = self.sinks.entry((row.to_owned(), idx)).or_default();
        st.last = Some(r.payload.clone());
        st.inflight = Some(call);
        st.pending = None;
        st.last_fire_us = Some(now);
        self.calls.insert(call, (row.to_owned(), idx));
        self.progress.sink_calls += 1;
        out.push(match r.action {
            Some(action) => Effect::Invoke {
                call,
                key: r.key,
                action,
                args: r.payload,
            },
            None => Effect::Set {
                call,
                key: r.key,
                value: r.payload,
            },
        });
    }

    /// A sink call answered.
    pub fn on_reply(&mut self, call: u64, ok: bool, now: u64, out: &mut Vec<Effect>) {
        let Some(at) = self.calls.remove(&call) else {
            return;
        };
        if !ok {
            self.progress.errors += 1;
        }
        let throttle = self.plan.options.throttle_ms * 1000;
        let Some(st) = self.sinks.get_mut(&at) else {
            return;
        };
        st.inflight = None;
        let due = st
            .last_fire_us
            .is_none_or(|t| throttle == 0 || now >= t + throttle);
        if due {
            if let Some(p) = st.pending.take() {
                if st.last.as_ref() != Some(&p.payload) {
                    self.fire(&at.0, at.1, p, now, out);
                }
            }
        }
    }

    /// Throttled sink calls that are due, and the collection timeout.
    pub fn tick(&mut self, now: u64, out: &mut Vec<Effect>) {
        let throttle = self.plan.options.throttle_ms * 1000;
        let due: Vec<(String, usize)> = self
            .sinks
            .iter()
            .filter(|(_, s)| {
                s.inflight.is_none()
                    && s.pending.is_some()
                    && s.last_fire_us.is_none_or(|t| now >= t + throttle)
            })
            .map(|(k, _)| k.clone())
            .collect();
        for k in due {
            if let Some(p) = self.sinks.get_mut(&k).and_then(|s| s.pending.take()) {
                self.fire(&k.0, k.1, p, now, out);
            }
        }
        self.check_ready(now);
        if self.refetch_at().is_some_and(|t| now >= t) && self.missing_values() {
            self.progress.refetches += 1;
            // the new subscription first, then the old one goes: nothing is missed between
            let subs: Vec<(String, Handle)> =
                self.subs.iter().map(|(k, h)| (k.clone(), *h)).collect();
            for (prefix, old) in subs {
                let h = self.id();
                self.subs.insert(prefix.clone(), h);
                out.push(Effect::Subscribe {
                    h,
                    key: format!("{prefix}/**"),
                });
                out.push(Effect::Unsubscribe { h: old });
            }
        }
    }

    /// When the next refetch is due, while refetches are left.
    fn refetch_at(&self) -> Option<u64> {
        let ready = self.ready_us?;
        if self.subs.is_empty() || self.progress.refetches >= MAX_REFETCHES {
            return None;
        }
        Some(ready + REFETCH_AFTER_MS * 1000 * (1 << self.progress.refetches))
    }

    /// A row of the table reads a value key no sample came for.
    fn missing_values(&self) -> bool {
        let last = self.plan.segments.len() - 1;
        self.row_keys.iter().any(|((seg, row), keys)| {
            *seg == last
                && self.table.contains_key(row)
                && keys.iter().any(|k| !self.values.contains_key(k))
        })
    }

    /// When [`Engine::tick`] has work: a throttled call or the collection timeout.
    pub fn next_wake_us(&self) -> Option<u64> {
        let throttle = self.plan.options.throttle_ms * 1000;
        let sinks = self
            .sinks
            .values()
            .filter(|s| s.inflight.is_none() && s.pending.is_some())
            .filter_map(|s| s.last_fire_us.map(|t| t + throttle))
            .min();
        let timeout =
            (self.status() == Status::Collecting).then_some(self.started_us + self.timeout_us);
        let refetch = self.refetch_at().filter(|_| self.missing_values());
        sinks.into_iter().chain(timeout).chain(refetch).min()
    }

    fn pending(&self) -> usize {
        self.lists.values().filter(|l| !l.refreshed).count()
    }

    fn check_ready(&mut self, now: u64) {
        let pending = self.pending();
        self.progress.lists = self.lists.len();
        self.progress.lists_pending = pending;
        if self.progress.collect_ms.is_some() {
            return;
        }
        if pending == 0 {
            self.progress.collect_ms = Some(now.saturating_sub(self.started_us) / 1000);
            self.ready_us = Some(now);
        } else if now >= self.started_us + self.timeout_us {
            self.ready_us = Some(now);
            self.timed_out = true;
            self.progress.collect_ms = Some(now.saturating_sub(self.started_us) / 1000);
            self.progress.error = Some(format!(
                "incomplete: {pending} lists pending after {} s",
                self.timeout_us / 1_000_000
            ));
        }
    }

    pub fn status(&self) -> Status {
        if self.progress.collect_ms.is_some() {
            Status::Ready
        } else {
            Status::Collecting
        }
    }

    pub fn progress(&self) -> &Progress {
        &self.progress
    }

    pub fn rows(&self) -> usize {
        self.table.len()
    }

    pub fn columns(&self) -> &[String] {
        &self.columns
    }

    /// The table changed since the last call.
    pub fn take_dirty(&mut self) -> bool {
        std::mem::take(&mut self.dirty)
    }

    /// Rows `from..from+limit` in key order, each a map of its columns.
    pub fn table(&self, from: usize, limit: usize) -> Vec<Value> {
        self.table
            .values()
            .skip(from)
            .take(limit)
            .map(|cols| Value::Map(cols.iter().cloned().collect()))
            .collect()
    }
}
