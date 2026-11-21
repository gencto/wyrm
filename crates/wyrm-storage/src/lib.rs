//! Broker storage (ADR 0017): `wy/<site>/storage/**`, folders and values
//! people create and set, kept across restarts, as a DSA broker's `/data`.
//!
//! [`Storage`] is a link (raw layer of `wyrm-link-sdk`) with the root
//! `wy/<site>/storage`; the host opens the [`Store`] once and hands it to
//! every start, so a router rebuild restarts the link on the same file.

#![forbid(unsafe_code)]

mod actions;
pub mod json;
pub mod store;

use actions::{AddNode, AddValue, Delete, Duplicate, Import, Publish, Rename};
use std::collections::BTreeMap;
use std::sync::Arc;
use std::time::Duration;
use tracing::warn;
use wyrm_core::{keyspace, NodeMeta, Perm, Quality, Status, TypeCode, Value, Writable};
use wyrm_link_sdk::tree::split_parent;
use wyrm_link_sdk::{now_us, Args, Caller, Link, LinkCtx, LinkError, ReplySink, Result};

pub use actions::{ValueEditor, ValueType};
pub use store::{Changes, Rec, Store};

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
    /// Every record together (CBOR, [`Rec::size`]): bounds the memory the
    /// store holds and every export.
    pub total_bytes: usize,
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
            total_bytes: 64 * 1024 * 1024,
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

    fn too_large(&self) -> LinkError {
        LinkError::new(
            Status::OutOfRange,
            format!("the storage holds at most {} bytes", self.total_bytes),
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

/// `~meta` of a stored node with its actions.
fn meta(rec: &Rec) -> NodeMeta {
    let mut actions = BTreeMap::from([
        ("delete".to_owned(), actions::delete()),
        ("rename".to_owned(), actions::rename()),
        ("duplicate".to_owned(), actions::duplicate()),
    ]);
    let mut m = match rec.ty {
        None => {
            actions.insert("add_node".into(), actions::add_node());
            actions.insert("add_value".into(), actions::add_value());
            actions.insert("export".into(), actions::export());
            actions.insert("import".into(), actions::import());
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
        let removed: usize = old
            .iter()
            .filter_map(|p| self.store.get(p))
            .map(|r| r.size())
            .sum();
        let added: usize = new.iter().map(|(_, r)| r.size()).sum();
        if self.store.bytes().saturating_sub(removed) + added > self.limits.total_bytes {
            return Err(self.limits.too_large());
        }
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

    async fn delete(&self, path: &str, a: Delete) -> Result<()> {
        let rec = self.rec(path)?;
        let sub = self.store.subtree(path);
        let recursive = a.recursive;
        if rec.is_folder() && sub.len() > 1 && !recursive {
            return Err(LinkError::invalid_parameter(
                "the node has children: set recursive",
            ));
        }
        let old = sub.into_iter().map(|(p, _)| p).collect();
        self.replace(old, &[path.to_owned()], Vec::new()).await
    }

    /// `path` under the new `name` beside it; `keep` (a duplicate) leaves it where it is.
    async fn rename(&self, path: &str, name: &str, keep: bool) -> Result<()> {
        let (parent, _) = split_parent(path).ok_or_else(|| LinkError::invalid_parameter("root"))?;
        self.rec(path)?;
        let n = self.store.subtree(path).len();
        let to = self.new_child(parent, name, if keep { n } else { 0 })?;
        let new = self.copy(path, &to);
        let (old, top) = if keep {
            (Vec::new(), Vec::new())
        } else {
            let old = self.store.subtree(path).into_iter().map(|(p, _)| p);
            (old.collect(), vec![path.to_owned()])
        };
        self.replace(old, &top, new).await
    }

    /// The node `rec` as the new child `name` of the folder `parent`.
    async fn add(&self, parent: &str, name: &str, rec: Rec) -> Result<()> {
        let path = self.new_child(parent, name, 1)?;
        self.replace(Vec::new(), &[], vec![(path, rec)]).await
    }

    /// Create the folders and the `dynamic` value at `path` that are missing,
    /// then set the value.
    async fn publish(&self, a: Publish) -> Result<()> {
        let (at, missing) = self.plan_publish(&a)?;
        if !missing.is_empty() {
            self.replace(Vec::new(), &[], missing).await?;
        }
        self.set(&at, a.value).await
    }

    /// What `publish` checks before it writes: the value node it sets and the nodes it makes.
    fn plan_publish(&self, a: &Publish) -> Result<(String, Vec<(String, Rec)>)> {
        let path = a.path.trim_matches('/');
        keyspace::validate_path(path).map_err(|e| LinkError::invalid_parameter(e.to_string()))?;
        self.limits.check_depth(path)?;
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
        check_value(ty, &a.value, &self.limits)?;
        if self.store.len() + missing.len() > self.limits.nodes {
            return Err(self.limits.too_many());
        }
        Ok((at, missing))
    }

    async fn set(&self, path: &str, v: Value) -> Result<()> {
        let t = now_us();
        let old = self.rec(path)?;
        let new = Rec {
            value: Some(v.clone()),
            t: Some(t),
            ..old.clone()
        };
        if self.store.bytes() - old.size() + new.size() > self.limits.total_bytes {
            return Err(self.limits.too_large());
        }
        if !self.store.set_value(path, v.clone(), t) {
            return Err(LinkError::not_found(path.to_owned()));
        }
        self.ctx.update(path, v, Quality::Good, t).await
    }

    fn export(&self, path: &str) -> Result<Value> {
        self.folder(path)?;
        json::export(path, &self.store.subtree(path), self.limits.export_bytes)
            .map(Value::Str)
            .map_err(|e| match e {
                json::ExportError::TooLarge(_) => {
                    LinkError::new(Status::OutOfRange, format!("export: {e}"))
                }
                json::ExportError::FieldName(_) => {
                    LinkError::new(Status::InternalError, format!("export: {e}"))
                }
            })
    }

    /// Replace the children of the folder `path` with the JSON's.
    async fn import(&self, path: &str, a: Import) -> Result<()> {
        self.folder(path)?;
        let text = match (a.data, a.file) {
            (Some(s), None) => s,
            (None, Some(b)) => String::from_utf8(b).map_err(|e| {
                LinkError::invalid_parameter(format!("file: not UTF-8 text ({})", e.utf8_error()))
            })?,
            _ => return Err(LinkError::invalid_parameter("import: data or file")),
        };
        let new = json::import(path, &text, &self.limits)?;
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

impl Storage {
    /// A rename or a duplicate writes a sibling under the parent, outside `path`: the caller
    /// needs write there too, or a grant on a folder could copy it out (ADR 0046). The parent.
    fn may_name_beside<'p>(&self, path: &'p str, action: &str, who: &Caller) -> Result<&'p str> {
        let (parent, _) = split_parent(path).ok_or_else(|| LinkError::invalid_parameter("root"))?;
        let parent_key = self.ctx.key(parent, "");
        let have = who.perm_on(&parent_key);
        if have < Perm::Write {
            return Err(LinkError::new(
                Status::PermissionDenied,
                format!(
                    "{action}: needs write on {parent_key}, where the new name goes (the caller has {})",
                    have.name()
                ),
            ));
        }
        Ok(parent)
    }
}

impl Drop for Storage {
    /// `stop` is skipped when the driver panics: the flusher must not keep
    /// the store for the rest of the process.
    fn drop(&mut self) {
        self.flusher.abort();
    }
}

impl Link for Storage {
    const NAME: &'static str = "storage";
    const VERSION: &'static str = env!("CARGO_PKG_VERSION");
    type Config = StorageStart;

    async fn start(cfg: StorageStart, ctx: LinkCtx) -> Result<Self> {
        for (name, a) in [
            ("add_node", actions::add_node()),
            ("add_value", actions::add_value()),
            ("publish", actions::publish()),
            ("export", actions::export()),
            ("import", actions::import()),
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
        who: &Caller,
        out: ReplySink,
    ) -> Result<()> {
        match (path, action) {
            (_, "add_node") => {
                let a = AddNode::decode(args)?;
                self.add(path, &a.name, Rec::folder()).await
            }
            (_, "add_value") => {
                let a = AddValue::decode(args)?;
                let rec = Rec {
                    ty: Some(a.ty.code()),
                    editor: a.editor.and_then(ValueEditor::stored),
                    ..Rec::default()
                };
                self.add(path, &a.name, rec).await
            }
            ("", "publish") => self.publish(Publish::decode(args)?).await,
            (_, "export") => {
                <()>::decode(args)?;
                out.reply(self.export(path)?).await
            }
            (_, "import") => self.import(path, Import::decode(args)?).await,
            (p, "delete") if !p.is_empty() => {
                self.rec(path)?;
                self.delete(path, Delete::decode(args)?).await
            }
            (p, "rename") if !p.is_empty() => {
                self.may_name_beside(path, action, who)?;
                self.rec(path)?;
                let a = Rename::decode(args)?;
                self.rename(path, &a.name, false).await
            }
            (p, "duplicate") if !p.is_empty() => {
                self.may_name_beside(path, action, who)?;
                self.rec(path)?;
                let a = Duplicate::decode(args)?;
                self.rename(path, &a.name, true).await
            }
            _ => Err(LinkError::not_supported(action.to_owned())),
        }
    }

    /// `~act/<a>?check` (spec 05 0.2.33): the names, places and room a new node needs, and the
    /// parent's rights of a rename or duplicate, as the actions check them; nothing written.
    async fn on_check(
        &mut self,
        path: &str,
        action: &str,
        args: Value,
        who: &Caller,
    ) -> Result<()> {
        match (path, action) {
            (_, "add_node") => {
                let a = AddNode::decode(args)?;
                self.new_child(path, &a.name, 1)?;
            }
            (_, "add_value") => {
                let a = AddValue::decode(args)?;
                self.new_child(path, &a.name, 1)?;
            }
            ("", "publish") => {
                self.plan_publish(&Publish::decode(args)?)?;
            }
            (p, "rename") if !p.is_empty() => {
                let parent = self.may_name_beside(path, action, who)?;
                self.rec(path)?;
                let a = Rename::decode(args)?;
                self.new_child(parent, &a.name, 0)?;
            }
            (p, "duplicate") if !p.is_empty() => {
                let parent = self.may_name_beside(path, action, who)?;
                self.rec(path)?;
                let a = Duplicate::decode(args)?;
                self.new_child(parent, &a.name, self.store.subtree(path).len())?;
            }
            (p, "delete") if !p.is_empty() => {
                self.rec(path)?;
            }
            _ => {}
        }
        Ok(())
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
