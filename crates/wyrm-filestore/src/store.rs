//! [`FileStore`]: a raw-layer link (ADR 0004 layer 1, its own topology)
//! over a [`Backend`]. Connections are added at runtime and kept sealed in
//! the link's `data_dir`; each running connection probes its store, reads
//! the tree of folders and files below its root and declares it, then reads
//! it again every `refresh_s`.
//!
//! ```text
//! <conn>              Edit, Remove, Stop/Start, Refresh (config / read)
//!   status            enum: Unknown … Connected, Failed, Stopped (wy:df-status)
//!   error             while there is one
//!   entries           files and folders in the tree
//!   total_bytes       sum of the file sizes
//!   last_refresh      when the whole tree was read
//!   files/            the root folder: Refresh, Create Folder, Upload File
//!     <folder>/       … the same, and Delete
//!     <file>          value = size (B), attr modified/etag/content_type;
//!                     Download, Delete
//! ```
//!
//! Node names are the store's names when they are valid key segments;
//! other names get a safe form with a stable hash (`report_2026.pdf_1f…`),
//! and the real name is the node's `display` and `attr.name`. A node
//! keeps its name while its entry exists, so history watches and flows
//! keep working across refreshes.
//!
//! Actions with I/O run on tasks of their own: a slow upload never holds
//! the link's other calls. What a store does not report again on a refresh
//! is removed (principle 3).

use crate::backend::{parent_of, under, Backend, Entry, Error, Limits, Scan};
use crate::persist::Persist;
use crate::util;
use bytes::Bytes;
use std::collections::{BTreeMap, HashMap};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::{Mutex, Notify, Semaphore};
use tokio::task::JoinHandle;
use tracing::{debug, info, warn};
use wyrm_core::meta::{ActionResult, ParamMeta, GROUP_EDIT, GROUP_NEW};
use wyrm_core::{keyspace, ActionMeta, NodeMeta, Perm, Quality, Status, TypeCode, Value};
use wyrm_link_sdk::driver::params::{normalize, ParamSpec};
use wyrm_link_sdk::driver::{backoff, NodeState, Params};
use wyrm_link_sdk::{
    now_us, Caller, FromParams, Link, LinkCtx, LinkError, Params, ReplySink, Result,
};

type Map = BTreeMap<String, Value>;

/// The folder of the tree below a connection.
pub const FILES: &str = "files";
/// Leaves of a connection node (and names a connection may not take).
pub const STATUS: &str = "status";
pub const ERROR: &str = "error";
pub const ENTRIES: &str = "entries";
pub const TOTAL_BYTES: &str = "total_bytes";
pub const LAST_REFRESH: &str = "last_refresh";
/// Stored with the params: `false` after `stop`.
const ENABLED: &str = "enabled";

/// Bound on reading a whole tree (many requests).
pub const SCAN_TIMEOUT: Duration = Duration::from_secs(600);
/// Shortest refresh period (0 = only on Refresh).
pub const MIN_REFRESH_S: f64 = 5.0;
/// Uploads and downloads of one connection at a time (each holds its bytes
/// in memory a few times over).
pub const TRANSFERS: usize = 2;
/// Bound of the `refresh` actions.
const REFRESH_MS: u32 = 300_000;
/// Bound of `upload` and `download`.
const TRANSFER_MS: u32 = 600_000;

/// Params every connection has beside its backend's.
#[derive(Debug, Clone, PartialEq, Params)]
pub struct Common {
    #[param(
        default = 300.0,
        min = 0.0,
        max = 86400.0,
        display = "Refresh (s)",
        desc = "read the whole tree again this often; 0 = only on Refresh"
    )]
    pub refresh_s: f64,
    #[param(
        default = 2000,
        min = 1,
        max = 9000,
        display = "Max Entries",
        desc = "files and folders shown; more are left out (truncated)"
    )]
    pub max_entries: u32,
    #[param(
        default = 8,
        min = 1,
        max = 12,
        display = "Max Depth",
        desc = "folder levels shown"
    )]
    pub max_depth: u32,
    #[param(default = 32, min = 1, max = 64, display = "Max Upload (MiB)")]
    pub max_upload_mib: u32,
    #[param(default = 1024, min = 1, max = 16384, display = "Max Download (KiB)")]
    pub max_download_kib: u32,
}

impl Common {
    fn limits(&self) -> Limits {
        Limits {
            max_entries: self.max_entries as usize,
            max_depth: self.max_depth as usize,
        }
    }
}

/// The link's bootstrap params: `{connections: {<name>: {params}}, …}`;
/// keys beside `connections` are the backend's [`Backend::link_options`]
/// (checked by [`validate`] and on start).
#[derive(Debug, Clone, PartialEq)]
pub struct Bootstrap(pub Value);

impl FromParams for Bootstrap {
    fn from_params(params: &Value) -> Result<Self> {
        match params {
            Value::Null => Ok(Self(Value::Map(Map::new()))),
            Value::Map(m) => match m.get("connections") {
                None | Some(Value::Map(_)) => Ok(Self(params.clone())),
                Some(_) => Err(LinkError::invalid_parameter(
                    "params.connections: expected a map",
                )),
            },
            _ => Err(LinkError::invalid_parameter("params: expected a map")),
        }
    }
}

impl Bootstrap {
    fn map(&self) -> Map {
        match &self.0 {
            Value::Map(m) => m.clone(),
            _ => Map::new(),
        }
    }

    /// `{connections}` alone: what a runtime edit is kept against (a change
    /// of the link options never drops the connections added at runtime).
    fn connections(&self) -> Value {
        let mut m = self.map();
        m.retain(|k, _| k == "connections");
        Value::Map(m)
    }

    /// The link options of `B`, checked, defaults filled in.
    pub fn options<B: Backend>(&self) -> Result<Map> {
        let mut m = self.map();
        m.remove("connections");
        normalize(&B::link_options(), &Value::Map(m))
            .map_err(|e| bad(format!("params.{}", e.message)))
    }
}

/// Check the bootstrap params of a `B` link (`wyrmd` before it installs one).
pub fn validate<B: Backend>(params: &Value) -> Result<()> {
    Bootstrap::from_params(params)?.options::<B>().map(|_| ())
}

/// The form schema of a connection: the backend's params, then [`Common`].
pub fn schema<B: Backend>() -> Vec<ParamSpec> {
    let mut s = B::Params::schema();
    s.extend(Common::schema());
    s
}

fn bad(what: impl std::fmt::Display) -> LinkError {
    LinkError::invalid_parameter(what.to_string())
}

/// Split a stored connection map into its parts, checking every field.
fn parse<B: Backend>(raw: &Map) -> Result<(B::Params, Common, bool)> {
    let enabled = !matches!(raw.get(ENABLED), Some(Value::Bool(false)));
    let own: Vec<&str> = B::Params::schema().iter().map(|s| s.name).collect();
    let common: Vec<&str> = Common::schema().iter().map(|s| s.name).collect();
    if let Some(k) = raw.keys().find(|k| {
        k.as_str() != ENABLED && !own.contains(&k.as_str()) && !common.contains(&k.as_str())
    }) {
        return Err(bad(format!("{k}: unknown parameter")));
    }
    let pick = |names: &[&str]| -> Value {
        Value::Map(
            raw.iter()
                .filter(|(k, _)| names.contains(&k.as_str()))
                .map(|(k, v)| (k.clone(), v.clone()))
                .collect(),
        )
    };
    let p = B::Params::from_value(&pick(&own))?;
    let c = Common::from_value(&pick(&common))?;
    if c.refresh_s > 0.0 && c.refresh_s < MIN_REFRESH_S {
        return Err(bad(format!(
            "refresh_s: 0 (only on Refresh) or at least {MIN_REFRESH_S}"
        )));
    }
    Ok((p, c, enabled))
}

/// `edit` args with the stored secrets kept where the new args leave them
/// out or empty, but only while the destination (the `dest` fields, or
/// every field when none is marked) stays the same, as the driver
/// framework does: `config` must not point a stored key at another host.
fn keep_secrets(schema: &[ParamSpec], old: &Map, new: &Map) -> Map {
    let missing = |m: &Map, n: &str| match m.get(n) {
        None | Some(Value::Null) => true,
        Some(Value::Str(s)) => s.is_empty(),
        _ => false,
    };
    let mut cand = new.clone();
    let mut kept = Vec::new();
    for s in schema.iter().filter(|s| s.secret) {
        if missing(&cand, s.name) {
            cand.remove(s.name);
            if !missing(old, s.name) {
                cand.insert(s.name.to_owned(), old[s.name].clone());
                kept.push(s.name);
            }
        }
    }
    if kept.is_empty() {
        return cand;
    }
    let any_dest = schema.iter().any(|s| s.dest);
    let norm = |m: &Map| {
        let mut m = m.clone();
        m.remove(ENABLED);
        normalize(schema, &Value::Map(m))
    };
    let same = match (norm(old), norm(&cand)) {
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
    cand
}

/// A node name for a store name: the name itself when it is a valid key
/// segment of a sane length, else a safe form with a stable hash.
pub fn segment_for(name: &str, key: &str) -> String {
    if name.len() <= 96 && keyspace::validate_segment(name).is_ok() {
        return name.to_owned();
    }
    let mut s: String = name
        .chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() || matches!(c, '_' | '-' | '.') {
                c
            } else {
                '_'
            }
        })
        .collect();
    while s.contains("__") {
        s = s.replace("__", "_");
    }
    let mut s: String = s.trim_matches('_').chars().take(64).collect();
    if s.is_empty() {
        s.push('_');
    }
    format!("{s}_{:08x}", util::fnv64(key) as u32)
}

fn act(display: &str, level: Perm) -> ActionMeta {
    ActionMeta::new().level(level).display(display)
}

fn text(required: bool) -> ParamMeta {
    ParamMeta::of(TypeCode::String).required(required)
}

fn refresh_action() -> ActionMeta {
    act("Refresh", Perm::Read)
        .timeout_ms(REFRESH_MS)
        .result(ActionResult::Type(TypeCode::Map))
}

fn folder_actions(root: bool) -> BTreeMap<String, ActionMeta> {
    let mut m = BTreeMap::new();
    m.insert("refresh".into(), refresh_action());
    m.insert(
        "create_folder".into(),
        act("Create Folder", Perm::Write)
            .group(GROUP_NEW)
            .param("name", text(true).display("Name"))
            .result(ActionResult::Type(TypeCode::Map)),
    );
    m.insert(
        "upload".into(),
        act("Upload File", Perm::Write)
            .group(GROUP_NEW)
            .timeout_ms(TRANSFER_MS)
            .param("name", text(true).display("Name").placeholder("report.csv"))
            .param(
                "file",
                ParamMeta::of(TypeCode::Binary)
                    .editor(wyrm_core::meta::EDITOR_FILE)
                    .display("File"),
            )
            .param(
                "text",
                ParamMeta::of(TypeCode::String)
                    .editor(wyrm_core::meta::EDITOR_TEXTAREA)
                    .display("Text")
                    .description("the content as text, instead of file"),
            )
            .param(
                "content_type",
                text(false)
                    .display("Content Type")
                    .description("empty: by the name's extension"),
            )
            .param(
                "overwrite",
                ParamMeta::of(TypeCode::Bool)
                    .display("Overwrite")
                    .description("replace a file of that name"),
            )
            .result(ActionResult::Type(TypeCode::Map)),
    );
    if !root {
        m.insert("delete".into(), delete_action(true));
    }
    m
}

fn delete_action(dir: bool) -> ActionMeta {
    let a = act("Delete", Perm::Write)
        .group(GROUP_EDIT)
        .timeout_ms(REFRESH_MS);
    if dir {
        a.param(
            "recursive",
            ParamMeta::of(TypeCode::Bool)
                .display("Recursive")
                .description("required for a folder that is not empty"),
        )
    } else {
        a
    }
}

fn file_actions() -> BTreeMap<String, ActionMeta> {
    let mut m = BTreeMap::new();
    m.insert(
        "download".into(),
        act("Download", Perm::Read)
            .timeout_ms(TRANSFER_MS)
            .param(
                "text",
                ParamMeta::of(TypeCode::Bool)
                    .display("As Text")
                    .description("the content as UTF-8 text instead of bytes"),
            )
            .result(ActionResult::Type(TypeCode::Dynamic)),
    );
    m.insert("delete".into(), delete_action(false));
    m
}

/// `~meta` of an entry's node.
fn entry_meta(e: &Entry) -> NodeMeta {
    let mut m = if e.dir {
        let mut m = NodeMeta::folder();
        m.actions = Some(folder_actions(false));
        m
    } else {
        let mut m = NodeMeta::leaf(TypeCode::Number).unit("B");
        if let Some(t) = e.modified {
            m = m.attr("modified", util::rfc3339(t));
        }
        if let Some(t) = &e.etag {
            m = m.attr("etag", t.as_str());
        }
        if let Some(t) = &e.content_type {
            m = m.attr("content_type", t.as_str());
        }
        m.actions = Some(file_actions());
        m
    };
    m = m
        .display(e.name.as_str())
        .attr("name", e.name.as_str())
        .attr("path", e.path.as_str());
    m
}

fn status_meta() -> NodeMeta {
    NodeMeta::leaf(TypeCode::Enum)
        .is("wy:df-status")
        .enum_values(NodeState::LABELS)
}

/// What a connection shows of its store.
#[derive(Default)]
struct View {
    /// By path (the root is not in it).
    entries: BTreeMap<String, Entry>,
    /// Path → node path (the link-relative key of the node).
    node: HashMap<String, String>,
    /// Node path → path.
    path: HashMap<String, String>,
    truncated: bool,
    /// Counts the changes actions made (create, upload, delete).
    gen: u64,
    /// The paths actions changed, with the `gen` of their last change: a
    /// read that started before it never undoes it.
    touched: HashMap<String, u64>,
}

impl View {
    /// An action changed `path` (and what is below it).
    fn touch(&mut self, path: &str) {
        self.gen += 1;
        self.touched.insert(path.to_owned(), self.gen);
    }

    /// `path` or a folder above it was changed by an action after `since`.
    fn touched_after(&self, path: &str, since: u64) -> bool {
        if self.touched.is_empty() {
            return false;
        }
        let mut at = Some(path);
        while let Some(p) = at {
            if self.touched.get(p).is_some_and(|g| *g > since) {
                return true;
            }
            at = parent_of(p).filter(|q| !q.is_empty());
        }
        false
    }

    /// The child of the folder `parent` whose real name is `name`.
    fn child_named(&self, parent: &str, name: &str) -> Option<&Entry> {
        self.entries
            .values()
            .find(|e| e.name == name && parent_of(&e.path) == Some(parent))
    }
}

/// One running connection.
struct Session<B: Backend> {
    ctx: LinkCtx,
    name: String,
    backend: B,
    common: Common,
    view: Mutex<View>,
    closed: AtomicBool,
    wake: Notify,
    /// Wakes the actions in flight when the connection stops (they are cut).
    stopped: Notify,
    /// One read of the tree at a time: a `refresh` while one runs is busy.
    scanning: Mutex<()>,
    /// Uploads and downloads in flight ([`TRANSFERS`]).
    transfers: Semaphore,
    data_dir: Option<std::path::PathBuf>,
    options: Arc<Map>,
}

fn busy(what: &str) -> LinkError {
    LinkError::new(Status::Busy, format!("{what}: try again when it is done"))
}

/// A name a store sent that the tree must not take (`..`, empty parts,
/// control characters): left out. A `/` in a real name is the store's
/// (Drive allows it); its path part never has one.
fn unsafe_entry(e: &Entry) -> bool {
    let bad = |s: &str| s.is_empty() || s == "." || s == ".." || s.chars().any(char::is_control);
    bad(&e.name) || e.path.split('/').any(bad)
}

impl<B: Backend> Session<B> {
    /// Mark the connection stopped and cut the actions in flight.
    fn close(&self) {
        self.closed.store(true, Ordering::Release);
        self.stopped.notify_waiters();
    }

    /// Returns once the connection stopped.
    async fn until_stopped(&self) {
        loop {
            let n = self.stopped.notified();
            tokio::pin!(n);
            // registered before the check: a close in between is not missed
            n.as_mut().enable();
            if self.closed.load(Ordering::Acquire) {
                return;
            }
            n.await;
        }
    }

    /// A request that shows the connection broke wakes the connection
    /// task: it probes again (and fails the connection if it is down).
    fn seen(&self, e: Error) -> Error {
        if e.breaks() {
            self.wake.notify_one();
        }
        e
    }

    fn files(&self) -> String {
        format!("{}/{FILES}", self.name)
    }

    fn node_of(&self, view: &View, path: &str) -> Option<String> {
        if path.is_empty() {
            Some(self.files())
        } else {
            view.node.get(path).cloned()
        }
    }

    async fn status(&self, state: NodeState, error: Option<&str>) {
        if self.closed.load(Ordering::Acquire) {
            return;
        }
        set_status(&self.ctx, &self.name, state, error).await;
    }

    async fn summary(&self, view: &View, scanned: bool) {
        let n = view.entries.len() as u64;
        let bytes: u64 = view.entries.values().filter_map(|e| e.size).sum();
        let t = now_us();
        let c = &self.ctx;
        let _ = c
            .update(
                &format!("{}/{ENTRIES}", self.name),
                Value::UInt(n),
                Quality::Good,
                t,
            )
            .await;
        let _ = c
            .update(
                &format!("{}/{TOTAL_BYTES}", self.name),
                Value::UInt(bytes),
                Quality::Good,
                t,
            )
            .await;
        if scanned {
            let _ = c
                .update(
                    &format!("{}/{LAST_REFRESH}", self.name),
                    Value::Str(util::rfc3339(t)),
                    Quality::Good,
                    t,
                )
                .await;
        }
    }

    /// The node path of a new entry under `parent_node`: its segment, or
    /// with the hash of its path when another node has that segment.
    fn assign(view: &View, parent_node: &str, e: &Entry) -> String {
        let seg = segment_for(&e.name, &e.path);
        let first = format!("{parent_node}/{seg}");
        if !view.path.contains_key(&first) {
            return first;
        }
        let hashed = format!("{first}_{:08x}", util::fnv64(&e.path) as u32);
        let mut cand = hashed.clone();
        let mut i = 2;
        while view.path.contains_key(&cand) {
            cand = format!("{hashed}_{i}");
            i += 1;
        }
        cand
    }

    /// Declare (or re-declare) one entry whose parent is in the view.
    async fn show(&self, view: &mut View, e: Entry) -> Result<()> {
        let parent = parent_of(&e.path).unwrap_or("");
        let parent_node = self
            .node_of(view, parent)
            .ok_or_else(|| LinkError::not_found(format!("folder {parent}")))?;
        let node = match view.node.get(&e.path) {
            Some(n) => n.clone(),
            None => Self::assign(view, &parent_node, &e),
        };
        self.ctx.declare_node(&node, entry_meta(&e)).await?;
        if !e.dir {
            let size = e.size.unwrap_or(0);
            self.ctx
                .update(
                    &node,
                    Value::UInt(size),
                    Quality::Good,
                    e.modified.unwrap_or_else(now_us),
                )
                .await?;
        }
        view.node.insert(e.path.clone(), node.clone());
        view.path.insert(node, e.path.clone());
        view.entries.insert(e.path.clone(), e);
        Ok(())
    }

    /// Drop the entry at `path` and everything below it.
    async fn hide(&self, view: &mut View, path: &str) {
        if let Some(node) = view.node.get(path).cloned() {
            if self.ctx.has_node(&node) {
                let _ = self.ctx.remove_node(&node).await;
            }
        }
        let gone: Vec<String> = view
            .entries
            .keys()
            .filter(|p| under(p, path))
            .cloned()
            .collect();
        for p in gone {
            view.entries.remove(&p);
            if let Some(n) = view.node.remove(&p) {
                view.path.remove(&n);
            }
        }
    }

    /// Replace what the view holds below `dir` with `scan`.
    async fn apply(&self, view: &mut View, dir: &str, scan: Scan, since: u64) -> Result<()> {
        let mut new: BTreeMap<String, Entry> = BTreeMap::new();
        for e in scan.entries {
            if e.path.is_empty() || !under(&e.path, dir) || e.path == dir {
                continue;
            }
            if unsafe_entry(&e) {
                debug!(conn = %self.name, "a name the tree cannot take is left out");
                continue;
            }
            new.insert(e.path.clone(), e);
        }
        // Folders a store implies (keys `a/b.txt` without `a/`).
        let implied: Vec<String> = new
            .keys()
            .flat_map(|p| {
                let mut out = Vec::new();
                let mut at = parent_of(p);
                while let Some(q) = at {
                    if q.is_empty() || q == dir || !under(q, dir) {
                        break;
                    }
                    out.push(q.to_owned());
                    at = parent_of(q);
                }
                out
            })
            .collect();
        for p in implied {
            new.entry(p.clone()).or_insert_with(|| Entry::dir(p));
        }
        let old: Vec<String> = view
            .entries
            .keys()
            .filter(|p| under(p, dir) && p.as_str() != dir)
            .cloned()
            .collect();
        for p in old {
            let keep = new.get(&p).is_some_and(|n| n.dir == view.entries[&p].dir);
            // made by an action after this read started: the read missed it
            if !keep && view.entries.contains_key(&p) && !view.touched_after(&p, since) {
                self.hide(view, &p).await;
            }
        }
        let max = self.common.max_entries as usize;
        let mut truncated = scan.truncated;
        let mut order: Vec<Entry> = new.into_values().collect();
        order.sort_by(|a, b| {
            let da = a.path.matches('/').count();
            let db = b.path.matches('/').count();
            da.cmp(&db).then_with(|| a.path.cmp(&b.path))
        });
        for e in order {
            if view.entries.get(&e.path) == Some(&e) || view.touched_after(&e.path, since) {
                continue;
            }
            let parent = parent_of(&e.path).unwrap_or("");
            let known = view.entries.contains_key(&e.path);
            if (!known && view.entries.len() >= max)
                || (!parent.is_empty() && !view.entries.contains_key(parent))
            {
                truncated = true;
                continue;
            }
            self.show(view, e).await?;
        }
        if dir.is_empty() {
            view.truncated = truncated;
            // the changes before this read are in it now
            view.touched.retain(|_, g| *g > since);
        } else {
            view.truncated |= truncated;
        }
        Ok(())
    }

    /// The entry of a node (the root for `<conn>/files`).
    fn resolve(&self, view: &View, node: &str) -> Result<Entry> {
        if node == self.files() {
            return Ok(self.backend.root());
        }
        view.path
            .get(node)
            .and_then(|p| view.entries.get(p))
            .cloned()
            .ok_or_else(|| LinkError::not_found(node.to_owned()))
    }

    /// Read the tree below `dir` and show it. The caller holds `scanning`.
    async fn refresh(&self, dir: &Entry) -> std::result::Result<Value, Error> {
        let since = self.view.lock().await.gen;
        let scan = tokio::time::timeout(SCAN_TIMEOUT, self.backend.scan(dir, self.common.limits()))
            .await
            .map_err(|_| Error::Timeout(format!("reading {} took too long", shown(&dir.path))))
            .and_then(|r| r)
            .map_err(|e| self.seen(e))?;
        let mut view = self.view.lock().await;
        if self.closed.load(Ordering::Acquire) {
            return Err(Error::Unreachable("connection stopped".into()));
        }
        self.apply(&mut view, &dir.path, scan, since)
            .await
            .map_err(|e| Error::Refused(e.message))?;
        self.summary(&view, dir.path.is_empty()).await;
        let below = view.entries.keys().filter(|p| under(p, &dir.path)).count();
        Ok(Value::Map(Map::from([
            ("entries".to_owned(), Value::UInt(below as u64)),
            ("truncated".to_owned(), Value::Bool(view.truncated)),
        ])))
    }

    /// A refresh action: busy while another read runs.
    async fn refresh_now(&self, dir: &Entry) -> Result<Value> {
        let Ok(_g) = self.scanning.try_lock() else {
            return Err(busy("a refresh is running"));
        };
        Ok(self.refresh(dir).await?)
    }

    /// Show an entry a request made (mkdir, upload).
    async fn added(&self, mut e: Entry) -> Result<Value> {
        let mut view = self.view.lock().await;
        if self.closed.load(Ordering::Acquire) {
            return Err(LinkError::new(Status::Disconnected, "connection stopped"));
        }
        // a store with two children of one name (Drive): another one's path
        if let (Some(other), Some(id)) = (view.entries.get(&e.path), e.id.as_deref()) {
            if other.id.as_deref().is_some_and(|o| o != id) {
                let short = format!("{} ({})", e.path, &id[..id.len().min(8)]);
                e.path = if view.entries.contains_key(&short) {
                    format!("{} ({id})", e.path)
                } else {
                    short
                };
            }
        }
        view.touch(&e.path);
        let path = e.path.clone();
        let size = e.size;
        self.show(&mut view, e).await?;
        self.summary(&view, false).await;
        let node = view.node.get(&path).cloned().unwrap_or_default();
        let mut m = Map::from([
            ("path".to_owned(), Value::Str(path)),
            ("node".to_owned(), Value::Str(node)),
        ]);
        if let Some(s) = size {
            m.insert("size".to_owned(), Value::UInt(s));
        }
        Ok(Value::Map(m))
    }

    async fn mkdir(&self, node: &str, args: &Map) -> Result<Value> {
        let name = arg_str(args, "name")?.unwrap_or_default();
        util::check_name(&name).map_err(|e| bad(format!("name: {e}")))?;
        let parent = {
            let view = self.view.lock().await;
            let parent = self.resolve(&view, node)?;
            if !parent.dir {
                return Err(bad("not a folder"));
            }
            if view.child_named(&parent.path, &name).is_some() {
                return Err(bad(format!("{name} exists")));
            }
            parent
        };
        let e = self
            .backend
            .mkdir(&parent, &name)
            .await
            .map_err(|e| self.seen(e))?;
        self.added(e).await
    }

    async fn upload(&self, node: &str, mut args: Map) -> Result<Value> {
        let Ok(_slot) = self.transfers.try_acquire() else {
            return Err(busy(&format!(
                "{TRANSFERS} uploads or downloads are running"
            )));
        };
        let name = arg_str(&args, "name")?.unwrap_or_default();
        util::check_name(&name).map_err(|e| bad(format!("name: {e}")))?;
        // taken out of the args, not copied: an upload may be 64 MiB
        let data = match (args.remove("file"), args.remove("text")) {
            (Some(Value::Bytes(b)), None | Some(Value::Null)) => Bytes::from(b),
            (None | Some(Value::Null), Some(Value::Str(s))) => Bytes::from(s.into_bytes()),
            (Some(Value::Bytes(_)), Some(_)) => return Err(bad("give file or text, not both")),
            _ => return Err(bad("file or text: required")),
        };
        let args = &args;
        let max = self.common.max_upload_mib as usize * 1024 * 1024;
        if data.len() > max {
            return Err(LinkError::new(
                Status::OutOfRange,
                format!("{} bytes, at most {max} (max_upload_mib)", data.len()),
            ));
        }
        let ctype = arg_str(args, "content_type")?
            .filter(|c| !c.trim().is_empty())
            .unwrap_or_else(|| util::guess_content_type(&name).to_owned());
        if ctype.len() > 255 || hyper::header::HeaderValue::from_str(&ctype).is_err() {
            return Err(bad("content_type: not a valid content type"));
        }
        let overwrite = matches!(args.get("overwrite"), Some(Value::Bool(true)));
        let (parent, existing) = {
            let view = self.view.lock().await;
            let parent = self.resolve(&view, node)?;
            if !parent.dir {
                return Err(bad("not a folder"));
            }
            // by its real name: two names may share a path form (Drive)
            let existing = view.child_named(&parent.path, &name).cloned();
            match &existing {
                Some(e) if e.dir => return Err(bad(format!("{name} is a folder"))),
                Some(_) if !overwrite => {
                    return Err(bad(format!("{name} exists (set overwrite to replace it)")))
                }
                _ => {}
            }
            (parent, existing)
        };
        let e = self
            .backend
            .put(&parent, &name, data, &ctype, existing.as_ref())
            .await
            .map_err(|e| self.seen(e))?;
        self.added(e).await
    }

    async fn download(&self, node: &str, args: &Map) -> Result<Value> {
        let Ok(_slot) = self.transfers.try_acquire() else {
            return Err(busy(&format!(
                "{TRANSFERS} uploads or downloads are running"
            )));
        };
        let file = {
            let view = self.view.lock().await;
            self.resolve(&view, node)?
        };
        if file.dir {
            return Err(bad("a folder"));
        }
        let max = self.common.max_download_kib as usize * 1024;
        if file.size.is_some_and(|s| s > max as u64) {
            return Err(LinkError::new(
                Status::OutOfRange,
                format!(
                    "{} bytes, at most {max} (max_download_kib)",
                    file.size.unwrap_or(0)
                ),
            ));
        }
        let data = self
            .backend
            .get(&file, max)
            .await
            .map_err(|e| self.seen(e))?;
        if matches!(args.get("text"), Some(Value::Bool(true))) {
            String::from_utf8(data.into())
                .map(Value::Str)
                .map_err(|_| bad("not UTF-8 text: download without text"))
        } else {
            Ok(Value::Bytes(data.into()))
        }
    }

    async fn delete(&self, node: &str, args: &Map) -> Result<Value> {
        let (e, below) = {
            let view = self.view.lock().await;
            let e = self.resolve(&view, node)?;
            if e.path.is_empty() {
                return Err(bad("the root folder"));
            }
            let below: Vec<Entry> = view
                .entries
                .values()
                .filter(|x| x.path != e.path && under(&x.path, &e.path))
                .cloned()
                .collect();
            (e, below)
        };
        let recursive = matches!(args.get("recursive"), Some(Value::Bool(true)));
        if e.dir && !below.is_empty() && !recursive {
            return Err(bad("the folder is not empty: set recursive"));
        }
        // the store checks again: the tree may not show all that is there
        self.backend
            .delete(&e, &below, recursive && e.dir)
            .await
            .map_err(|e| self.seen(e))?;
        let mut view = self.view.lock().await;
        if !self.closed.load(Ordering::Acquire) {
            view.touch(&e.path);
            self.hide(&mut view, &e.path).await;
            self.summary(&view, false).await;
        }
        Ok(Value::Null)
    }
}

fn shown(path: &str) -> &str {
    if path.is_empty() {
        "/"
    } else {
        path
    }
}

fn arg_str(args: &Map, name: &str) -> Result<Option<String>> {
    match args.get(name) {
        None | Some(Value::Null) => Ok(None),
        Some(Value::Str(s)) => Ok(Some(s.clone())),
        Some(_) => Err(bad(format!("{name}: expected text"))),
    }
}

/// Publish the state; the `error` leaf exists while there is an error. The
/// error is written before the state, so whoever sees `Failed` finds why.
async fn set_status(ctx: &LinkCtx, base: &str, state: NodeState, error: Option<&str>) {
    let ep = format!("{base}/{ERROR}");
    if let Some(e) = error {
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
    let _ = ctx
        .update(
            &format!("{base}/{STATUS}"),
            Value::UInt(state as u64),
            Quality::Good,
            now_us(),
        )
        .await;
    if error.is_none() && ctx.has_node(&ep) {
        let _ = ctx.remove_node(&ep).await;
    }
}

/// The connection task: probe, read the tree, read it again every
/// `refresh_s`; on a failure reconnect with backoff.
async fn run<B: Backend>(s: Arc<Session<B>>) {
    let mut attempt = 0u32;
    loop {
        s.status(NodeState::Connecting, None).await;
        let err = match s.backend.check_place(s.data_dir.as_deref(), &s.options) {
            // a mount point moved, or the allowed roots changed
            Err(e) => Some(e.message),
            // a second over the backend's own bound: its error, which says
            // what did not answer, comes first
            Ok(()) => match tokio::time::timeout(
                s.backend.timeout() + Duration::from_secs(1),
                s.backend.check(),
            )
            .await
            {
                Err(_) => Some("no answer in time".to_owned()),
                Ok(Err(e)) => Some(e.to_string()),
                Ok(Ok(())) => None,
            },
        };
        if err.is_none() {
            loop {
                let root = s.backend.root();
                let read = {
                    let _g = s.scanning.lock().await;
                    s.refresh(&root).await
                };
                match read {
                    Ok(_) => {
                        attempt = 0;
                        let warn = s.view.lock().await.truncated.then_some(
                            "truncated: more entries than max_entries or max_depth shows",
                        );
                        s.status(NodeState::Connected, warn).await;
                    }
                    Err(e) => {
                        info!(conn = %s.name, "read failed: {e}");
                        s.status(NodeState::Failed, Some(&e.to_string())).await;
                        break;
                    }
                }
                if s.common.refresh_s > 0.0 {
                    let every = Duration::from_secs_f64(s.common.refresh_s);
                    tokio::select! {
                        _ = tokio::time::sleep(every) => {}
                        _ = s.wake.notified() => {}
                    }
                } else {
                    s.wake.notified().await;
                }
            }
        } else if let Some(e) = err {
            debug!(conn = %s.name, "probe failed: {e}");
            s.status(NodeState::Failed, Some(&e)).await;
        }
        let jitter =
            (util::fnv64(&format!("{}{attempt}{}", s.name, now_us())) % 2001) as f64 / 1000.0 - 1.0;
        tokio::select! {
            _ = tokio::time::sleep(backoff(attempt, jitter)) => {}
            _ = s.wake.notified() => {}
        }
        attempt = attempt.saturating_add(1);
    }
}

struct Slot<B: Backend> {
    /// Params with secrets, and `enabled`.
    raw: Map,
    run: Option<(Arc<Session<B>>, JoinHandle<()>)>,
}

/// The file store link of backend `B`.
pub struct FileStore<B: Backend> {
    ctx: LinkCtx,
    conns: BTreeMap<String, Slot<B>>,
    persist: Option<Persist>,
    /// [`Backend::link_options`] from the bootstrap params.
    options: Arc<Map>,
}

impl<B: Backend> FileStore<B> {
    fn save(&self) {
        if let Some(p) = &self.persist {
            let all: Map = self
                .conns
                .iter()
                .map(|(k, s)| (k.clone(), Value::Map(s.raw.clone())))
                .collect();
            p.save(&all);
        }
    }

    fn add_form(&self) -> ActionMeta {
        let mut a = act(&format!("Add {}", B::DISPLAY), Perm::Config)
            .group(GROUP_NEW)
            .param("name", text(true).display("Name"));
        for s in schema::<B>() {
            a = a.param(s.name, s.param_meta(None));
        }
        a
    }

    fn conn_meta(&self, name: &str, raw: &Map) -> NodeMeta {
        let enabled = !matches!(raw.get(ENABLED), Some(Value::Bool(false)));
        let shown = public_of::<B>(raw);
        let mut edit = act("Edit", Perm::Config).group(GROUP_EDIT);
        for s in schema::<B>() {
            let mut p = s.param_meta(shown.get(s.name));
            if s.secret {
                p.required = Some(false);
                p.description = Some(match p.description.take() {
                    Some(d) => format!("{d} (empty: keep the stored one)"),
                    None => "empty: keep the stored one".into(),
                });
            }
            edit = edit.param(s.name, p);
        }
        let mut actions = BTreeMap::new();
        actions.insert("edit".to_owned(), edit);
        actions.insert(
            "remove".to_owned(),
            act("Remove", Perm::Config).group(GROUP_EDIT),
        );
        if enabled {
            actions.insert("stop".to_owned(), act("Stop", Perm::Config));
            actions.insert("refresh".to_owned(), refresh_action());
        } else {
            actions.insert("start".to_owned(), act("Start", Perm::Config));
        }
        let mut m = NodeMeta::folder().display(name).attr("provider", B::NAME);
        m.cfg = Some(shown);
        m.actions = Some(actions);
        m
    }

    /// Declare a connection's node and leaves, and start it when enabled.
    async fn bring_up(&mut self, name: &str) -> Result<()> {
        let Some(slot) = self.conns.get(name) else {
            return Ok(());
        };
        let raw = slot.raw.clone();
        self.ctx
            .declare_node(name, self.conn_meta(name, &raw))
            .await?;
        self.ctx
            .declare_node(&format!("{name}/{STATUS}"), status_meta())
            .await?;
        for (leaf, meta) in [
            (ENTRIES, NodeMeta::leaf(TypeCode::Number)),
            (TOTAL_BYTES, NodeMeta::leaf(TypeCode::Number).unit("B")),
            (LAST_REFRESH, NodeMeta::leaf(TypeCode::String)),
        ] {
            self.ctx
                .declare_node(&format!("{name}/{leaf}"), meta)
                .await?;
        }
        let parsed = parse::<B>(&raw).and_then(|(p, c, en)| {
            let b = B::new(&p)?;
            b.check_place(self.ctx.data_dir(), &self.options)?;
            Ok((b, c, en))
        });
        let (backend, common, enabled) = match parsed {
            Ok(v) => v,
            Err(e) => {
                set_status(&self.ctx, name, NodeState::Failed, Some(&e.message)).await;
                return Ok(());
            }
        };
        if !enabled {
            set_status(&self.ctx, name, NodeState::Stopped, None).await;
            return Ok(());
        }
        let mut files = NodeMeta::folder().display("Files");
        files.actions = Some(folder_actions(true));
        self.ctx
            .declare_node(&format!("{name}/{FILES}"), files)
            .await?;
        let s = Arc::new(Session {
            ctx: self.ctx.clone(),
            name: name.to_owned(),
            backend,
            common,
            view: Mutex::new(View::default()),
            closed: AtomicBool::new(false),
            wake: Notify::new(),
            stopped: Notify::new(),
            scanning: Mutex::new(()),
            transfers: Semaphore::new(TRANSFERS),
            data_dir: self.ctx.data_dir().map(std::path::Path::to_path_buf),
            options: self.options.clone(),
        });
        let task = tokio::spawn(run(s.clone()));
        if let Some(slot) = self.conns.get_mut(name) {
            slot.run = Some((s, task));
        }
        Ok(())
    }

    /// Stop a connection's task and remove its tree (the node stays).
    async fn tear_down(&mut self, name: &str) {
        let Some((s, task)) = self.conns.get_mut(name).and_then(|c| c.run.take()) else {
            return;
        };
        // cuts the actions in flight at their next await (between two
        // requests: a recursive S3 delete stops at the next key)
        s.close();
        task.abort();
        let _ = task.await;
        // In-flight actions apply under the view lock and see `closed`.
        let _guard = s.view.lock().await;
        let files = format!("{name}/{FILES}");
        if self.ctx.has_node(&files) {
            let _ = self.ctx.remove_node(&files).await;
        }
    }

    async fn add(&mut self, args: Map) -> Result<()> {
        let mut args = args;
        let name = match args.remove("name") {
            Some(Value::Str(s)) => s,
            _ => return Err(bad("name: required")),
        };
        keyspace::validate_segment(&name).map_err(|e| bad(format!("name: {e}")))?;
        if self.conns.contains_key(&name) {
            return Err(bad(format!("{name} exists")));
        }
        let raw = normalized::<B>(&args)?;
        parse::<B>(&raw)
            .and_then(|(p, _, _)| B::new(&p)?.check_place(self.ctx.data_dir(), &self.options))?;
        self.conns.insert(name.clone(), Slot { raw, run: None });
        self.save();
        self.bring_up(&name).await
    }

    async fn edit(&mut self, name: &str, args: Map) -> Result<()> {
        let old = self
            .conns
            .get(name)
            .map(|s| s.raw.clone())
            .ok_or_else(|| LinkError::not_found(name.to_owned()))?;
        let merged = keep_secrets(&schema::<B>(), &old, &args);
        let mut raw = normalized::<B>(&merged)?;
        parse::<B>(&raw)
            .and_then(|(p, _, _)| B::new(&p)?.check_place(self.ctx.data_dir(), &self.options))?;
        if let Some(e) = old.get(ENABLED) {
            raw.insert(ENABLED.to_owned(), e.clone());
        }
        self.tear_down(name).await;
        if let Some(s) = self.conns.get_mut(name) {
            s.raw = raw;
        }
        self.save();
        self.bring_up(name).await
    }

    async fn set_enabled(&mut self, name: &str, on: bool) -> Result<()> {
        if !self.conns.contains_key(name) {
            return Err(LinkError::not_found(name.to_owned()));
        }
        self.tear_down(name).await;
        if let Some(s) = self.conns.get_mut(name) {
            if on {
                s.raw.remove(ENABLED);
            } else {
                s.raw.insert(ENABLED.to_owned(), Value::Bool(false));
            }
        }
        self.save();
        self.bring_up(name).await
    }

    async fn remove(&mut self, name: &str) -> Result<()> {
        if !self.conns.contains_key(name) {
            return Err(LinkError::not_found(name.to_owned()));
        }
        self.tear_down(name).await;
        self.conns.remove(name);
        self.save();
        if self.ctx.has_node(name) {
            self.ctx.remove_node(name).await?;
        }
        Ok(())
    }
}

/// The params of a new or edited connection, checked against the schema,
/// with defaults filled in.
fn normalized<B: Backend>(args: &Map) -> Result<Map> {
    let mut m = args.clone();
    m.remove(ENABLED);
    normalize(&schema::<B>(), &Value::Map(m))
}

fn public_of<B: Backend>(raw: &Map) -> Map {
    let secret: Vec<&str> = schema::<B>()
        .iter()
        .filter(|s| s.secret)
        .map(|s| s.name)
        .collect();
    raw.iter()
        .filter(|(k, _)| k.as_str() != ENABLED && !secret.contains(&k.as_str()))
        .map(|(k, v)| (k.clone(), v.clone()))
        .collect()
}

/// Run `work` on a task of its own and answer through `out`; the work is
/// cut when the connection stops (stop, remove, edit, the link's stop), so
/// nothing of it runs on a connection that is gone. A blocking file system
/// call already under way (`localfs`) still ends in the kernel.
fn spawn_reply<B, F>(out: ReplySink, s: Arc<Session<B>>, work: F)
where
    B: Backend,
    F: std::future::Future<Output = Result<Value>> + Send + 'static,
{
    tokio::spawn(async move {
        let r = tokio::select! {
            r = work => r,
            () = s.until_stopped() => Err(LinkError::new(
                Status::Disconnected,
                "the connection stopped: the action was cut",
            )),
        };
        match r {
            Ok(v) => {
                let _ = out.reply(v).await;
            }
            Err(e) => {
                let _ = out.error(e).await;
            }
        }
    });
}

fn map_args(args: Value) -> Result<Map> {
    match args {
        Value::Map(m) => Ok(m),
        Value::Null => Ok(Map::new()),
        _ => Err(LinkError::new(Status::InvalidMessage, "args must be a map")),
    }
}

impl<B: Backend> Link for FileStore<B> {
    const NAME: &'static str = B::NAME;
    const VERSION: &'static str = B::VERSION;
    type Config = Bootstrap;

    async fn start(cfg: Bootstrap, ctx: LinkCtx) -> Result<Self> {
        let options = Arc::new(cfg.options::<B>()?);
        let persist = Persist::open(&ctx, &cfg.connections());
        let conns: Map = match persist.as_ref().and_then(Persist::load) {
            Some(c) => c,
            None => match &cfg.0 {
                Value::Map(m) => match m.get("connections") {
                    Some(Value::Map(c)) => c.clone(),
                    _ => Map::new(),
                },
                _ => Map::new(),
            },
        };
        let mut fs = FileStore {
            ctx,
            conns: BTreeMap::new(),
            persist,
            options,
        };
        let add = fs.add_form();
        fs.ctx.declare_action("", "add_connection", add).await?;
        for (name, v) in conns {
            // a connection the link cannot show is skipped, never the link
            if let Err(e) = keyspace::validate_segment(&name) {
                warn!("connections.{name}: {e}: left out");
                continue;
            }
            let Value::Map(raw) = v else {
                warn!("connections.{name}: not a map: left out");
                continue;
            };
            // Invalid params keep the connection (Failed, with the error):
            // config is never dropped.
            fs.conns.insert(name, Slot { raw, run: None });
        }
        let names: Vec<String> = fs.conns.keys().cloned().collect();
        for n in names {
            fs.bring_up(&n).await?;
        }
        Ok(fs)
    }

    async fn on_invoke(
        &mut self,
        path: &str,
        action: &str,
        args: Value,
        _who: &Caller,
        out: ReplySink,
    ) -> Result<()> {
        let args = map_args(args)?;
        if path.is_empty() {
            return match action {
                "add_connection" => self.add(args).await,
                _ => Err(LinkError::not_supported(action.to_owned())),
            };
        }
        let (conn, rest) = path.split_once('/').unwrap_or((path, ""));
        if !self.conns.contains_key(conn) {
            return Err(LinkError::not_found(path.to_owned()));
        }
        if rest.is_empty() {
            return match action {
                "edit" => self.edit(conn, args).await,
                "remove" => self.remove(conn).await,
                "stop" => self.set_enabled(conn, false).await,
                "start" => self.set_enabled(conn, true).await,
                "refresh" => {
                    let s = self.session(conn)?;
                    spawn_reply(out, s.clone(), async move {
                        let root = s.backend.root();
                        s.refresh_now(&root).await
                    });
                    Ok(())
                }
                _ => Err(LinkError::not_supported(action.to_owned())),
            };
        }
        if rest != FILES && !rest.starts_with(&format!("{FILES}/")) {
            return Err(LinkError::not_supported(action.to_owned()));
        }
        let s = self.session(conn)?;
        let node = path.to_owned();
        let cut = s.clone();
        match action {
            "refresh" => spawn_reply(out, cut, async move {
                let dir = {
                    let view = s.view.lock().await;
                    s.resolve(&view, &node)?
                };
                if !dir.dir {
                    return Err(bad("not a folder"));
                }
                s.refresh_now(&dir).await
            }),
            "create_folder" => spawn_reply(out, cut, async move { s.mkdir(&node, &args).await }),
            "upload" => spawn_reply(out, cut, async move { s.upload(&node, args).await }),
            "download" => spawn_reply(out, cut, async move { s.download(&node, &args).await }),
            "delete" => spawn_reply(out, cut, async move { s.delete(&node, &args).await }),
            _ => return Err(LinkError::not_supported(action.to_owned())),
        }
        Ok(())
    }

    async fn stop(&mut self) {
        let names: Vec<String> = self.conns.keys().cloned().collect();
        for n in names {
            if let Some((s, task)) = self.conns.get_mut(&n).and_then(|c| c.run.take()) {
                s.close();
                task.abort();
            }
        }
    }
}

impl<B: Backend> FileStore<B> {
    fn session(&self, conn: &str) -> Result<Arc<Session<B>>> {
        self.conns
            .get(conn)
            .and_then(|c| c.run.as_ref())
            .map(|(s, _)| s.clone())
            .ok_or_else(|| LinkError::new(Status::Disconnected, "connection not running"))
    }
}

impl<B: Backend> Drop for FileStore<B> {
    fn drop(&mut self) {
        for c in self.conns.values() {
            if let Some((s, t)) = &c.run {
                s.close();
                t.abort();
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn segments() {
        assert_eq!(segment_for("report.csv", "a/report.csv"), "report.csv");
        let s = segment_for("report 2026 (final).pdf", "x");
        assert!(
            s.starts_with("report_2026_final_.pdf_") || s.starts_with("report_2026_final"),
            "{s}"
        );
        assert!(keyspace::validate_segment(&s).is_ok());
        assert_ne!(segment_for("a b", "1"), segment_for("a b", "2"));
        assert!(keyspace::validate_segment(&segment_for("~meta", "~meta")).is_ok());
        assert!(keyspace::validate_segment(&segment_for("Звіт", "Звіт")).is_ok());
        assert!(keyspace::validate_segment(&segment_for(&"x".repeat(200), "k")).is_ok());
    }

    #[test]
    fn bootstrap() {
        assert!(Bootstrap::from_params(&Value::Null).is_ok());
        // link options are the backend's, checked by `validate`
        let opts = Value::Map(Map::from([("x".to_owned(), Value::Null)]));
        assert!(Bootstrap::from_params(&opts).is_ok());
        let bad = Value::Map(Map::from([("connections".to_owned(), Value::Bool(true))]));
        assert!(Bootstrap::from_params(&bad).is_err());
        assert!(Value::Str("x".into()) != Bootstrap::from_params(&opts).unwrap().connections());
    }
}
