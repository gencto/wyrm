//! Broker storage (ADR 0017): `wy/<site>/storage/**`, folders and values
//! people create and set, kept across restarts, as a DSA broker's `/data`.
//!
//! [`Storage`] is a link (raw layer of `wyrm-link-sdk`) with the root
//! `wy/<site>/storage`; the host opens the [`Store`] once and hands it to
//! every start, so a router rebuild restarts the link on the same file.

#![forbid(unsafe_code)]

pub mod json;
pub mod store;

use std::collections::BTreeMap;
use std::sync::Arc;
use std::time::Duration;
use tracing::warn;
use wyrm_core::meta::{ActionResult, ParamMeta, GROUP_EDIT, GROUP_NEW};
use wyrm_core::{keyspace, ActionMeta, NodeMeta, Perm, Quality, Status, TypeCode, Value, Writable};
use wyrm_link_sdk::tree::split_parent;
use wyrm_link_sdk::{now_us, Caller, Link, LinkCtx, LinkError, ReplySink, Result};

pub use store::{Rec, Store};

/// Types of `add_value`, in the order a UI offers them.
pub const TYPES: [TypeCode; 7] = [
    TypeCode::String,
    TypeCode::Number,
    TypeCode::Bool,
    TypeCode::Array,
    TypeCode::Map,
    TypeCode::Binary,
    TypeCode::Dynamic,
];

/// Editors of `add_value`; the first means none.
pub const EDITORS: [&str; 3] = ["none", "textarea", "date"];

/// How long values wait in memory before they are written.
const FLUSH_EVERY: Duration = Duration::from_secs(1);

#[derive(Debug, Clone)]
pub struct Limits {
    pub nodes: usize,
    /// Path segments below the root.
    pub depth: usize,
    /// One value, CBOR-encoded.
    pub value_bytes: usize,
    pub import_bytes: usize,
    pub export_bytes: usize,
}

impl Default for Limits {
    fn default() -> Self {
        Self {
            nodes: 10_000,
            depth: 16,
            // Half the gateway's 64 KiB WebSocket frame.
            value_bytes: 32 * 1024,
            import_bytes: 4 * 1024 * 1024,
            export_bytes: 4 * 1024 * 1024,
        }
    }
}

impl Limits {
    pub fn check_depth(&self, path: &str) -> Result<()> {
        if path.split('/').count() > self.depth {
            return Err(LinkError::new(
                Status::OutOfRange,
                format!("more than {} levels", self.depth),
            ));
        }
        Ok(())
    }

    pub fn too_many(&self) -> LinkError {
        LinkError::new(
            Status::OutOfRange,
            format!("the storage holds at most {} nodes", self.nodes),
        )
    }
}

/// `v` fits a value node of type `ty` and the size limit.
pub fn check_value(ty: TypeCode, v: &Value, limits: &Limits) -> Result<()> {
    let ok = match ty {
        TypeCode::Number => v.as_f64().is_some_and(f64::is_finite),
        TypeCode::String => matches!(v, Value::Str(_)),
        TypeCode::Bool => matches!(v, Value::Bool(_)),
        TypeCode::Array => matches!(v, Value::Array(_)),
        TypeCode::Map => matches!(v, Value::Map(_)),
        TypeCode::Binary => matches!(v, Value::Bytes(_)),
        TypeCode::Dynamic => true,
        TypeCode::Null | TypeCode::Enum => false,
    };
    if !ok {
        return Err(LinkError::invalid_parameter(format!(
            "value is not a {}",
            ty.name()
        )));
    }
    let size = wyrm_core::codec::to_vec(v)
        .map_err(|e| LinkError::invalid_parameter(e.to_string()))?
        .len();
    if size > limits.value_bytes {
        return Err(LinkError::new(
            Status::OutOfRange,
            format!("value of {size} bytes, at most {}", limits.value_bytes),
        ));
    }
    Ok(())
}

pub struct StorageStart {
    pub store: Arc<Store>,
    pub limits: Limits,
}

pub struct Storage {
    ctx: LinkCtx,
    store: Arc<Store>,
    limits: Limits,
    flusher: tokio::task::JoinHandle<()>,
}

fn join(parent: &str, name: &str) -> String {
    if parent.is_empty() {
        name.to_owned()
    } else {
        format!("{parent}/{name}")
    }
}

fn act(display: &str) -> ActionMeta {
    ActionMeta::new().level(Perm::Write).display(display)
}

fn name_param() -> ParamMeta {
    ParamMeta::of(TypeCode::String).required(true)
}

fn add_node() -> ActionMeta {
    act("Add Node").group(GROUP_NEW).param("name", name_param())
}

fn add_value() -> ActionMeta {
    act("Add Value")
        .group(GROUP_NEW)
        .param("name", name_param())
        // Choices travel as text, as every action's (the SDK checks the type).
        .param(
            "type",
            ParamMeta::of(TypeCode::String)
                .enum_values(TYPES.iter().map(|t| t.name()))
                .required(true),
        )
        .param(
            "editor",
            ParamMeta::of(TypeCode::String).enum_values(EDITORS),
        )
}

fn export() -> ActionMeta {
    act("Export").result(ActionResult::Type(TypeCode::String))
}

fn import() -> ActionMeta {
    act("Import").param(
        "data",
        ParamMeta::of(TypeCode::String)
            .required(true)
            .editor(wyrm_core::meta::EDITOR_TEXTAREA)
            .description("JSON from Export"),
    )
}

fn edits(m: &mut BTreeMap<String, ActionMeta>) {
    m.insert(
        "delete".into(),
        act("Delete")
            .group(GROUP_EDIT)
            .param("recursive", ParamMeta::of(TypeCode::Bool)),
    );
    m.insert(
        "rename".into(),
        act("Rename").group(GROUP_EDIT).param("name", name_param()),
    );
    m.insert(
        "duplicate".into(),
        act("Duplicate")
            .group(GROUP_EDIT)
            .param("name", name_param()),
    );
}

/// `~meta` of a stored node with its actions.
fn meta(rec: &Rec) -> NodeMeta {
    let mut actions = BTreeMap::new();
    edits(&mut actions);
    let mut m = match rec.ty {
        None => {
            actions.insert("add_node".into(), add_node());
            actions.insert("add_value".into(), add_value());
            actions.insert("export".into(), export());
            actions.insert("import".into(), import());
            NodeMeta::folder()
        }
        Some(ty) => {
            let m = NodeMeta::leaf(ty).writable(Writable::Write);
            match &rec.editor {
                Some(e) => m.attr("editor", e.as_str()),
                None => m,
            }
        }
    };
    m.actions = Some(actions);
    m
}

fn arg<'a>(args: &'a Value, name: &str) -> Option<&'a Value> {
    match args {
        Value::Map(m) => m.get(name),
        _ => None,
    }
}

fn text_arg<'a>(args: &'a Value, name: &str) -> Result<&'a str> {
    match arg(args, name) {
        Some(Value::Str(s)) => Ok(s),
        _ => Err(LinkError::invalid_parameter(format!("{name}: required"))),
    }
}

/// A choice among `options`; `None` when the argument is absent.
fn choice<'a>(args: &Value, name: &str, options: &[&'a str]) -> Result<Option<&'a str>> {
    match arg(args, name) {
        None => Ok(None),
        Some(Value::Str(s)) => options
            .iter()
            .find(|o| **o == s)
            .map(|o| Some(*o))
            .ok_or_else(|| LinkError::invalid_parameter(format!("{name}: one of {options:?}"))),
        Some(_) => Err(LinkError::invalid_parameter(format!("{name}: text"))),
    }
}

fn segment(name: &str) -> Result<()> {
    keyspace::validate_segment(name).map_err(|e| LinkError::invalid_parameter(e.to_string()))
}

impl Storage {
    fn rec(&self, path: &str) -> Result<Rec> {
        self.store
            .get(path)
            .ok_or_else(|| LinkError::not_found(path.to_owned()))
    }

    /// The folder `path` (the root or a stored folder).
    fn folder(&self, path: &str) -> Result<()> {
        if path.is_empty() || self.rec(path)?.is_folder() {
            Ok(())
        } else {
            Err(LinkError::invalid_parameter(format!("{path} is a value")))
        }
    }

    /// A new child `name` of the folder `parent`: free and within limits.
    fn new_child(&self, parent: &str, name: &str, count: usize) -> Result<String> {
        segment(name)?;
        self.folder(parent)?;
        let path = join(parent, name);
        if self.store.get(&path).is_some() {
            return Err(LinkError::invalid_parameter(format!("{path} exists")));
        }
        self.limits.check_depth(&path)?;
        if self.store.len() + count > self.limits.nodes {
            return Err(self.limits.too_many());
        }
        Ok(path)
    }

    /// Declare stored nodes (parents first) and publish their values.
    async fn show(&self, nodes: &[(String, Rec)]) -> Result<()> {
        for (p, r) in nodes {
            self.ctx.declare_node(p, meta(r)).await?;
            if let Some(v) = &r.value {
                self.ctx
                    .update(p, v.clone(), Quality::Good, r.t.unwrap_or_else(now_us))
                    .await?;
            }
        }
        Ok(())
    }

    /// Store and show new nodes, removing `old` first.
    async fn replace(
        &self,
        old: Vec<String>,
        top: &[String],
        new: Vec<(String, Rec)>,
    ) -> Result<()> {
        self.store
            .apply(new.clone(), old)
            .map_err(LinkError::internal)?;
        for p in top {
            if self.ctx.has_node(p) {
                self.ctx.remove_node(p).await?;
            }
        }
        self.show(&new).await
    }

    /// The subtree at `from` moved under `to`, with values.
    fn copy(&self, from: &str, to: &str) -> Vec<(String, Rec)> {
        self.store
            .subtree(from)
            .into_iter()
            .map(|(p, r)| (format!("{to}{}", &p[from.len()..]), r))
            .collect()
    }

    async fn delete(&self, path: &str, args: &Value) -> Result<()> {
        let rec = self.rec(path)?;
        let sub = self.store.subtree(path);
        let recursive = matches!(arg(args, "recursive"), Some(Value::Bool(true)));
        if rec.is_folder() && sub.len() > 1 && !recursive {
            return Err(LinkError::invalid_parameter(
                "the node has children: set recursive",
            ));
        }
        let old = sub.into_iter().map(|(p, _)| p).collect();
        self.replace(old, &[path.to_owned()], Vec::new()).await
    }

    async fn rename(&self, path: &str, args: &Value, keep: bool) -> Result<()> {
        let (parent, _) = split_parent(path).ok_or_else(|| LinkError::invalid_parameter("root"))?;
        self.rec(path)?;
        let n = self.store.subtree(path).len();
        let to = self.new_child(parent, text_arg(args, "name")?, if keep { n } else { 0 })?;
        let new = self.copy(path, &to);
        let (old, top) = if keep {
            (Vec::new(), Vec::new())
        } else {
            let old = self.store.subtree(path).into_iter().map(|(p, _)| p);
            (old.collect(), vec![path.to_owned()])
        };
        self.replace(old, &top, new).await
    }

    async fn add(&self, parent: &str, args: &Value, value: bool) -> Result<()> {
        let path = self.new_child(parent, text_arg(args, "name")?, 1)?;
        let rec = if value {
            let names: Vec<&str> = TYPES.iter().map(|t| t.name()).collect();
            let ty = choice(args, "type", &names)?
                .and_then(|n| TYPES.iter().copied().find(|t| t.name() == n))
                .ok_or_else(|| LinkError::invalid_parameter("type: required"))?;
            let editor = choice(args, "editor", &EDITORS)?
                .filter(|e| *e != EDITORS[0])
                .map(str::to_owned);
            Rec {
                ty: Some(ty),
                editor,
                ..Rec::default()
            }
        } else {
            Rec::folder()
        };
        self.replace(Vec::new(), &[], vec![(path, rec)]).await
    }

    /// Create the folders and the `dynamic` value at `path` that are missing,
    /// then set the value.
    async fn publish(&self, args: &Value) -> Result<()> {
        let path = text_arg(args, "path")?.trim_matches('/');
        keyspace::validate_path(path).map_err(|e| LinkError::invalid_parameter(e.to_string()))?;
        self.limits.check_depth(path)?;
        let value = arg(args, "value")
            .cloned()
            .ok_or_else(|| LinkError::invalid_parameter("value: required"))?;
        let mut missing = Vec::new();
        let mut at = String::new();
        let segs: Vec<&str> = path.split('/').collect();
        for (i, s) in segs.iter().enumerate() {
            at = join(&at, s);
            let last = i + 1 == segs.len();
            match self.store.get(&at) {
                Some(r) if !last && !r.is_folder() => {
                    return Err(LinkError::invalid_parameter(format!("{at} is a value")))
                }
                Some(r) if last && r.is_folder() => {
                    return Err(LinkError::invalid_parameter(format!("{at} is a folder")))
                }
                Some(_) => {}
                None if last => missing.push((
                    at.clone(),
                    Rec {
                        ty: Some(TypeCode::Dynamic),
                        ..Rec::default()
                    },
                )),
                None => missing.push((at.clone(), Rec::folder())),
            }
        }
        let ty = self
            .store
            .get(&at)
            .and_then(|r| r.ty)
            .unwrap_or(TypeCode::Dynamic);
        check_value(ty, &value, &self.limits)?;
        if self.store.len() + missing.len() > self.limits.nodes {
            return Err(self.limits.too_many());
        }
        if !missing.is_empty() {
            self.replace(Vec::new(), &[], missing).await?;
        }
        self.set(&at, value).await
    }

    async fn set(&self, path: &str, v: Value) -> Result<()> {
        let t = now_us();
        if !self.store.set_value(path, v.clone(), t) {
            return Err(LinkError::not_found(path.to_owned()));
        }
        self.ctx.update(path, v, Quality::Good, t).await
    }

    fn export(&self, path: &str) -> Result<Value> {
        self.folder(path)?;
        let text = json::export(path, &self.store.subtree(path));
        if text.len() > self.limits.export_bytes {
            return Err(LinkError::new(
                Status::OutOfRange,
                format!("export: more than {} bytes", self.limits.export_bytes),
            ));
        }
        Ok(Value::Str(text))
    }

    /// Replace the children of the folder `path` with the JSON's.
    async fn import(&self, path: &str, args: &Value) -> Result<()> {
        self.folder(path)?;
        let new = json::import(path, text_arg(args, "data")?, &self.limits)?;
        let old: Vec<String> = self
            .store
            .subtree(path)
            .into_iter()
            .map(|(p, _)| p)
            .filter(|p| p != path)
            .collect();
        if self.store.len() - old.len() + new.len() > self.limits.nodes {
            return Err(self.limits.too_many());
        }
        let top: Vec<String> = old
            .iter()
            .filter(|p| split_parent(p).is_some_and(|(parent, _)| parent == path))
            .cloned()
            .collect();
        self.replace(old, &top, new).await
    }
}

impl Link for Storage {
    const NAME: &'static str = "storage";
    const VERSION: &'static str = env!("CARGO_PKG_VERSION");
    type Config = StorageStart;

    async fn start(cfg: StorageStart, ctx: LinkCtx) -> Result<Self> {
        for (name, a) in [
            ("add_node", add_node()),
            ("add_value", add_value()),
            (
                "publish",
                act("Publish")
                    .param("path", name_param().placeholder("folder/value"))
                    .param("value", ParamMeta::of(TypeCode::Dynamic).required(true)),
            ),
            ("export", export()),
            ("import", import()),
        ] {
            ctx.declare_action("", name, a).await?;
        }
        let store = cfg.store;
        let storage = Storage {
            ctx: ctx.clone(),
            store: store.clone(),
            limits: cfg.limits,
            flusher: tokio::spawn(async move {
                let mut tick = tokio::time::interval(FLUSH_EVERY);
                tick.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
                loop {
                    tick.tick().await;
                    if let Err(e) = store.flush() {
                        warn!("{e}");
                    }
                }
            }),
        };
        let nodes: Vec<(String, Rec)> = storage.store.snapshot().into_iter().collect();
        storage.show(&nodes).await?;
        Ok(storage)
    }

    async fn on_set(&mut self, path: &str, value: Value, _who: &Caller) -> Result<()> {
        let ty = self
            .rec(path)?
            .ty
            .ok_or_else(|| LinkError::invalid_parameter("a folder"))?;
        check_value(ty, &value, &self.limits)?;
        self.set(path, value).await
    }

    async fn on_invoke(
        &mut self,
        path: &str,
        action: &str,
        args: Value,
        _who: &Caller,
        out: ReplySink,
    ) -> Result<()> {
        match (path, action) {
            (_, "add_node") => self.add(path, &args, false).await,
            (_, "add_value") => self.add(path, &args, true).await,
            ("", "publish") => self.publish(&args).await,
            (_, "export") => out.reply(self.export(path)?).await,
            (_, "import") => self.import(path, &args).await,
            (p, "delete") if !p.is_empty() => self.delete(path, &args).await,
            (p, "rename") if !p.is_empty() => self.rename(path, &args, false).await,
            (p, "duplicate") if !p.is_empty() => self.rename(path, &args, true).await,
            _ => Err(LinkError::not_supported(action.to_owned())),
        }
    }

    async fn stop(&mut self) {
        self.flusher.abort();
        // The task holds the store: wait until it has let it go.
        let _ = (&mut self.flusher).await;
        if let Err(e) = self.store.flush() {
            warn!("{e}");
        }
    }
}
