//! Tools offered to the model: read-only WYRM tools (the same surface as
//! `wyrm-mcp`, run in-process over `wyrm-client`) and `propose`, which only
//! validates an operation and appends it to the task plan. Nothing here
//! sends a `~set` or `~act`.

use serde_json::{json, Map, Value as Json};
use std::collections::BTreeMap;
use std::time::Duration;
use wyrm_client::WyrmClient;
use wyrm_core::profile::ProfileDef;
use wyrm_core::{Attachment, Perm, Sample, StatusGroup, Value};
use wyrm_mcp::check;
use wyrm_mcp::json::{json_to_value, meta_to_json, profile_to_json, sample_to_json};
use zenoh::query::ConsolidationMode;

const LIST_LIMIT_MAX: usize = 1000;
const LIST_LIMIT_DEFAULT: usize = 100;
const VALUE_GET_MAX: usize = 200;

/// When a write-level operation needs a human approval (`config` always does).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum ApprovalMode {
    /// Only config-level operations need approval.
    Config,
    /// Every operation needs approval (the default).
    #[default]
    Write,
    /// Like `Config`: config-level operations always need approval.
    Never,
}

impl ApprovalMode {
    pub const NAMES: &'static [&'static str] = &["config", "write", "never"];

    pub fn from_name(s: &str) -> Option<Self> {
        match s {
            "config" => Some(Self::Config),
            "write" => Some(Self::Write),
            "never" => Some(Self::Never),
            _ => None,
        }
    }

    pub fn name(self) -> &'static str {
        match self {
            Self::Config => "config",
            Self::Write => "write",
            Self::Never => "never",
        }
    }

    /// Strict: `config` (and anything above `write`) always needs approval.
    pub fn needs_approval(self, level: Perm) -> bool {
        level >= Perm::Config || (self == Self::Write && level >= Perm::Write)
    }
}

/// What the agent may touch.
#[derive(Debug, Clone)]
pub struct Policy {
    pub site: String,
    /// `wy/<site>/down/<agent link>`: never a target.
    pub own: String,
    /// Full node keys; empty = nothing is writable.
    pub allowed: Vec<String>,
    pub mode: ApprovalMode,
}

fn under(key: &str, prefix: &str) -> bool {
    key == prefix
        || key
            .strip_prefix(prefix)
            .is_some_and(|rest| rest.starts_with('/'))
}

impl Policy {
    /// Full node key: `wy/<site>/…` (this site only) or relative to it. No
    /// suffix (`~…`) or wildcard segments.
    pub fn node_key(&self, path: &str) -> Result<String, String> {
        node_key(&self.site, path)
    }

    /// May the agent change `node`? Own subtree never; otherwise the node
    /// must lie under one of `allowed` (on a segment boundary).
    pub fn may_touch(&self, node: &str) -> Result<(), String> {
        if under(node, &self.own) {
            return Err(format!("{node}: the agent may not change its own subtree"));
        }
        if self.allowed.is_empty() {
            return Err("allowed_prefixes is empty: this agent may not change anything".to_owned());
        }
        if self.allowed.iter().any(|p| under(node, p)) {
            Ok(())
        } else {
            Err(format!(
                "{node} is outside allowed_prefixes {:?}",
                self.allowed
            ))
        }
    }
}

impl Policy {
    /// May the model read `node`? Only under `allowed_prefixes` or
    /// `wy/<site>/pub/**`, never the agent's own subtree. Checked in every
    /// read tool, whatever the token would allow (defence in depth).
    pub fn may_read(&self, node: &str) -> Result<(), String> {
        if under(node, &self.own) {
            return Err(format!("{node}: the agent may not read its own subtree"));
        }
        let public = format!("wy/{}/pub", self.site);
        if under(node, &public) || self.allowed.iter().any(|p| under(node, p)) {
            Ok(())
        } else {
            Err(format!(
                "{node} is outside allowed_prefixes {:?} and {public}/**: the agent may not read it",
                self.allowed
            ))
        }
    }
}

pub fn node_key(site: &str, path: &str) -> Result<String, String> {
    let p = path.trim().trim_matches('/');
    let root = format!("wy/{site}");
    let key = if p == "wy" || p.starts_with("wy/") {
        if p != root && !p.starts_with(&format!("{root}/")) {
            return Err(format!("{p}: this agent serves site {site:?} only"));
        }
        p.to_owned()
    } else if p.is_empty() {
        root
    } else {
        format!("{root}/{p}")
    };
    for seg in key.split('/') {
        if seg.is_empty() || seg.starts_with('~') || seg.contains(['*', '$', '?', '#']) {
            return Err(format!(
                "{key}: give a node key (no empty, `~…` or wildcard segments)"
            ));
        }
    }
    Ok(key)
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OpKind {
    Set,
    Invoke,
}

impl OpKind {
    pub fn name(self) -> &'static str {
        match self {
            Self::Set => "set",
            Self::Invoke => "invoke",
        }
    }
}

/// One validated plan step. `key` is the exact request key
/// (`<node>/~set` or `<node>/~act/<action>`); approvals are keyed by it.
#[derive(Debug, Clone)]
pub struct PlanOp {
    pub op: OpKind,
    pub node: String,
    pub key: String,
    pub action: Option<String>,
    /// `~set` value, or the action's argument map.
    pub payload: Value,
    pub level: Perm,
    pub needs_approval: bool,
    pub reason: Option<String>,
}

impl PlanOp {
    pub fn to_value(&self) -> Value {
        let mut m = BTreeMap::new();
        m.insert("op".to_owned(), Value::from(self.op.name()));
        m.insert("key".to_owned(), Value::from(self.key.as_str()));
        m.insert("args".to_owned(), self.payload.clone());
        m.insert("level".to_owned(), Value::from(self.level.name()));
        m.insert("approval".to_owned(), Value::Bool(self.needs_approval));
        if let Some(r) = &self.reason {
            m.insert("reason".to_owned(), Value::from(r.as_str()));
        }
        Value::Map(m)
    }
}

fn str_field<'a>(input: &'a Json, k: &str) -> Result<&'a str, String> {
    input[k]
        .as_str()
        .ok_or_else(|| format!("`{k}` (string) is required"))
}

/// Dry-run check of a proposal (the `wyrm-mcp` rules): node key, policy,
/// `~meta` (type, enum, bounds, action schema), level, approval need.
pub async fn check_proposal(
    reader: &WyrmClient,
    policy: &Policy,
    input: &Json,
) -> Result<PlanOp, String> {
    let op = match str_field(input, "op")? {
        "set" => OpKind::Set,
        "invoke" => OpKind::Invoke,
        "flow_apply" => {
            return Err("flow_apply is not supported by this agent yet".into());
        }
        other => return Err(format!("unknown op {other:?}; use set or invoke")),
    };
    let node = policy.node_key(str_field(input, "path")?)?;
    policy.may_touch(&node)?;
    let reason = input["reason"]
        .as_str()
        .map(|s| s.chars().take(500).collect());
    let meta = reader
        .meta_expanded(&node)
        .await
        .map_err(|e| format!("{node}: {e}"))?;
    let (key, action, payload, mut level) = match op {
        OpKind::Set => {
            let level = check::set_level(&meta)?;
            let v = json_to_value(input.get("value").ok_or("`value` is required for set")?)?;
            let v = check::coerce_enum(meta.ty, meta.enum_values.as_deref(), v);
            check::validate_value(&meta, &v)?;
            (format!("{node}/~set"), None, v, level)
        }
        OpKind::Invoke => {
            let action = str_field(input, "action")?.to_owned();
            wyrm_core::keyspace::validate_segment(&action).map_err(|e| e.to_string())?;
            let level = check::action_level(&meta, &action)?;
            let act = meta
                .actions
                .as_ref()
                .and_then(|a| a.get(&action))
                .cloned()
                .unwrap_or_default();
            let given = match input.get("args") {
                None | Some(Json::Null) => BTreeMap::new(),
                Some(Json::Object(o)) => o
                    .iter()
                    .map(|(k, v)| json_to_value(v).map(|v| (k.clone(), v)))
                    .collect::<Result<_, _>>()?,
                Some(_) => return Err("`args` must be an object".into()),
            };
            let args = check::prepare_args(&act.params, given)?;
            (
                format!("{node}/~act/{action}"),
                Some(action),
                Value::Map(args),
                level,
            )
        }
    };
    if check::is_control_plane(&policy.site, &node) {
        level = Perm::Config;
    }
    Ok(PlanOp {
        op,
        node,
        key,
        action,
        payload,
        level,
        needs_approval: policy.mode.needs_approval(level),
        reason,
    })
}

/// Tool definitions for the Messages API (`tools`).
pub fn definitions() -> Json {
    let path = json!({"type": "string", "description": "Node key, `wy/<site>/down/<link>/<path>` or relative to the site (`down/mock/p0`)."});
    json!([
        {"name": "tree_list", "description": "(Read tools see only allowed_prefixes and pub/**.) Children of a node with their ~meta summary (type, unit, writable, display, has_children). `down` lists links. Paged with from/limit; `next` is the next `from`.",
         "input_schema": {"type": "object", "properties": {"path": path, "from": {"type": "integer"}, "limit": {"type": "integer"}}, "required": ["path"]}},
        {"name": "tree_resolve", "description": "Descendant keys of a node, optionally filtered by ~meta fields (`match`, e.g. `type:1;unit:°C`) and depth. Cheap: keys only.",
         "input_schema": {"type": "object", "properties": {"path": path, "match": {"type": "string"}, "depth": {"type": "integer"}}, "required": ["path"]}},
        {"name": "node_meta", "description": "Full ~meta of a node: type, unit, enum, writable level, cfg (min/max), attr, actions with parameter schemas and levels, children. expand=true folds in the profile chain.",
         "input_schema": {"type": "object", "properties": {"path": path, "expand": {"type": "boolean"}}, "required": ["path"]}},
        {"name": "value_get", "description": "Current values (~val) of up to 200 nodes: {path: {v, q, t}} or {error}.",
         "input_schema": {"type": "object", "properties": {"paths": {"type": "array", "items": {"type": "string"}}}, "required": ["paths"]}},
        {"name": "profiles", "description": "Node profiles under wy/<site>/pub/<name>/~meta. This is also the device-model catalog: a profile named `<vendor>:<model>` describes one device model, and its `attr` carries the model data (e.g. `registers`, point profiles, typical cfg, documentation links). Filter by a name substring.",
         "input_schema": {"type": "object", "properties": {"filter": {"type": "string"}}}},
        {"name": "flow_get", "description": "Definition (~def) and state of a flow.",
         "input_schema": {"type": "object", "properties": {"id": {"type": "string"}}, "required": ["id"]}},
        {"name": "flow_validate", "description": "Compile a flow definition (spec 06) on the flow engine without deploying it.",
         "input_schema": {"type": "object", "properties": {"def": {"type": "object"}}, "required": ["def"]}},
        {"name": "spec", "description": "The normative WYRM spec: 01 keyspace, 02 meta, 03 val, 04 attachment, 05 methods, 06 flow-def, readme, tables, changelog. Without a section: the list.",
         "input_schema": {"type": "object", "properties": {"section": {"type": "string"}}}},
        {"name": "propose", "description": "Add one change to the task plan. It is NOT executed now: it is checked against ~meta (type, enum, min/max, action schema) and the agent's allowed_prefixes, then shown to a human who approves or rejects the whole plan. op=set needs `value`; op=invoke needs `action` and `args`. An error result means the step was not added; fix it or explain why it is impossible. Read the node with node_meta first.",
         "input_schema": {"type": "object", "properties": {
            "op": {"type": "string", "enum": ["set", "invoke"]},
            "path": path,
            "value": {"description": "New value for op=set (enum by name or index; binary as {\"$bytes\": \"<base64>\"})."},
            "action": {"type": "string", "description": "Action name for op=invoke."},
            "args": {"type": "object", "description": "Action arguments for op=invoke."},
            "reason": {"type": "string", "description": "One sentence: why this step is needed."}
         }, "required": ["op", "path"]}}
    ])
}

/// Read-only tools over a `WyrmClient`.
pub struct Reader<'a> {
    pub client: &'a WyrmClient,
    pub policy: &'a Policy,
    pub site: &'a str,
    pub timeout: Duration,
}

type Out = Result<Json, String>;

fn err(e: impl std::fmt::Display) -> String {
    e.to_string()
}

impl Reader<'_> {
    /// Run tool `name`; `None` if it is not a read-only tool.
    pub async fn call(&self, name: &str, input: &Json) -> Option<Out> {
        Some(match name {
            "tree_list" => self.tree_list(input).await,
            "tree_resolve" => self.tree_resolve(input).await,
            "node_meta" => self.node_meta(input).await,
            "value_get" => self.value_get(input).await,
            "profiles" => self.profiles(input).await,
            "flow_get" => self.flow_get(input).await,
            "flow_validate" => self.flow_validate(input).await,
            "spec" => Ok(spec(input)),
            _ => return None,
        })
    }

    /// The `path` argument as a node key the model may read.
    fn node(&self, input: &Json) -> Result<String, String> {
        let node = node_key(self.site, str_field(input, "path")?)?;
        self.policy.may_read(&node)?;
        Ok(node)
    }

    async fn tree_list(&self, input: &Json) -> Out {
        let node = self.node(input)?;
        let kids = self.client.children(&node).await.map_err(err)?;
        let total = kids.len();
        let from = (input["from"].as_u64().unwrap_or(0) as usize).min(total);
        let limit = (input["limit"].as_u64().unwrap_or(LIST_LIMIT_DEFAULT as u64) as usize)
            .clamp(1, LIST_LIMIT_MAX);
        let items: Vec<Json> = kids
            .into_iter()
            .skip(from)
            .take(limit)
            .map(|c| {
                let mut m = meta_to_json(&c.meta);
                if let Json::Object(o) = &mut m {
                    o.insert("name".into(), c.name.clone().into());
                    o.insert("path".into(), format!("{node}/{}", c.name).into());
                }
                m
            })
            .collect();
        let next = (from + items.len() < total).then_some(from + items.len());
        Ok(json!({ "path": node, "total": total, "from": from, "next": next, "children": items }))
    }

    async fn tree_resolve(&self, input: &Json) -> Out {
        let node = self.node(input)?;
        let keys = self
            .client
            .resolve(
                &node,
                input["match"].as_str(),
                input["depth"].as_u64().map(|d| d as usize),
            )
            .await
            .map_err(err)?;
        Ok(json!({ "path": node, "count": keys.len(), "keys": keys }))
    }

    async fn node_meta(&self, input: &Json) -> Out {
        let node = self.node(input)?;
        let m = if input["expand"].as_bool().unwrap_or(false) {
            self.client.meta_expanded(&node).await
        } else {
            self.client.meta(&node).await
        }
        .map_err(err)?;
        let mut j = meta_to_json(&m);
        if let Json::Object(o) = &mut j {
            o.insert("path".into(), node.into());
        }
        Ok(j)
    }

    async fn get_one(&self, key: &str, ptok: Option<Vec<u8>>) -> Result<Vec<u8>, String> {
        let att = Attachment {
            ptok,
            ..Default::default()
        };
        let rx = self
            .client
            .session()
            .get(key)
            .timeout(self.timeout)
            .attachment(wyrm_core::codec::to_vec(&att).map_err(err)?)
            .await
            .map_err(err)?;
        let reply = rx
            .recv_async()
            .await
            .map_err(|_| format!("{key}: no reply"))?;
        let s = reply.result().map_err(|e| {
            format!(
                "{key}: {}",
                String::from_utf8_lossy(&e.payload().to_bytes())
            )
        })?;
        let att: Attachment = match s.attachment() {
            Some(a) => wyrm_core::codec::from_slice(&a.to_bytes()).map_err(err)?,
            None => Attachment::default(),
        };
        if let Some(st) = att.status.filter(|s| s.group() == StatusGroup::Error) {
            return Err(format!("{key}: {st:?} {}", att.err.unwrap_or_default()));
        }
        Ok(s.payload().to_bytes().to_vec())
    }

    pub async fn read_val(&self, node: &str) -> Result<Sample, String> {
        let p = self.get_one(&format!("{node}/~val"), None).await?;
        wyrm_core::codec::from_slice(&p).map_err(|e| format!("{node}/~val: {e}"))
    }

    async fn value_get(&self, input: &Json) -> Out {
        let paths = input["paths"]
            .as_array()
            .ok_or("`paths` (array of strings) is required")?;
        if paths.len() > VALUE_GET_MAX {
            return Err(format!("at most {VALUE_GET_MAX} paths per call"));
        }
        let mut out = Map::new();
        for p in paths {
            let Some(path) = p.as_str() else { continue };
            let r =
                match node_key(self.site, path).and_then(|n| self.policy.may_read(&n).map(|_| n)) {
                    Ok(node) => self
                        .read_val(&node)
                        .await
                        .map(|s| sample_to_json(&s))
                        .unwrap_or_else(|e| json!({ "error": e })),
                    Err(e) => json!({ "error": e }),
                };
            out.insert(path.to_owned(), r);
        }
        Ok(Json::Object(out))
    }

    async fn profiles(&self, input: &Json) -> Out {
        let prefix = format!("wy/{}/pub/", self.site);
        let rx = self
            .client
            .session()
            .get(format!("{prefix}*/~meta"))
            .consolidation(ConsolidationMode::None)
            .timeout(self.timeout)
            .await
            .map_err(err)?;
        let filter = input["filter"].as_str().map(str::to_lowercase);
        let mut found = BTreeMap::new();
        while let Ok(r) = rx.recv_async().await {
            let Ok(s) = r.result() else { continue };
            let Some(name) = s
                .key_expr()
                .as_str()
                .strip_prefix(&prefix)
                .and_then(|r| r.strip_suffix("/~meta"))
            else {
                continue;
            };
            if filter
                .as_ref()
                .is_some_and(|f| !name.to_lowercase().contains(f))
            {
                continue;
            }
            if let Ok(def) = wyrm_core::codec::from_slice::<ProfileDef>(&s.payload().to_bytes()) {
                found.insert(name.to_owned(), profile_to_json(name, &def));
            }
        }
        Ok(json!({ "count": found.len(), "profiles": found.into_values().collect::<Vec<_>>() }))
    }

    async fn flow_get(&self, input: &Json) -> Out {
        let id = str_field(input, "id")?;
        wyrm_core::keyspace::validate_segment(id).map_err(err)?;
        let node = format!("wy/{}/flows/{id}", self.site);
        // Before any proof is minted or a definition is read.
        self.policy.may_read(&node)?;
        let key = format!("{node}/~def");
        let payload = self.get_one(&key, self.client.proof(&key)).await?;
        let def: Value = wyrm_core::codec::from_slice(&payload).map_err(err)?;
        let state = self
            .read_val(&node)
            .await
            .map(|s| sample_to_json(&s))
            .unwrap_or_else(|e| json!({ "error": e }));
        Ok(json!({ "id": id, "state": state, "def": wyrm_mcp::json::value_to_json(&def) }))
    }

    async fn flow_validate(&self, input: &Json) -> Out {
        self.policy.may_read(&format!("wy/{}/flows", self.site))?;
        let def = json_to_value(input.get("def").ok_or("`def` is required")?)?;
        let mut args = BTreeMap::new();
        args.insert("def".to_owned(), def);
        let r = self
            .client
            .invoke_one(
                &format!("wy/{}/flows", self.site),
                "validate",
                Value::Map(args),
            )
            .await
            .map_err(err)?;
        Ok(r.map(|v| wyrm_mcp::json::value_to_json(&v))
            .unwrap_or(Json::Null))
    }
}

fn spec(input: &Json) -> Json {
    use wyrm_mcp::spec;
    match input["section"].as_str().filter(|s| !s.trim().is_empty()) {
        None => Json::Array(
            spec::FILES
                .iter()
                .map(|f| json!({ "section": f.file, "title": f.title }))
                .collect(),
        ),
        Some(s) => match spec::find(s) {
            Some(f) => Json::String(f.text.to_owned()),
            None => json!({ "error": format!("no spec section {s:?}") }),
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn policy(allowed: &[&str], mode: ApprovalMode) -> Policy {
        Policy {
            site: "s".into(),
            own: "wy/s/down/agent".into(),
            allowed: allowed.iter().map(|s| (*s).to_owned()).collect(),
            mode,
        }
    }

    #[test]
    fn prefixes_on_segment_boundaries() {
        let p = policy(&["wy/s/down/mock"], ApprovalMode::Write);
        assert!(p.may_touch("wy/s/down/mock").is_ok());
        assert!(p.may_touch("wy/s/down/mock/p0").is_ok());
        assert!(p.may_touch("wy/s/down/mockery/p0").is_err());
        assert!(p.may_touch("wy/s/down/agent/tasks").is_err());
        assert!(policy(&[], ApprovalMode::Write)
            .may_touch("wy/s/down/mock/p0")
            .is_err());
        let own = policy(&["wy/s/down"], ApprovalMode::Write);
        assert!(own.may_touch("wy/s/down/agent/x").is_err());
    }

    #[test]
    fn keys_and_modes() {
        assert_eq!(node_key("s", "down/mock/p0").unwrap(), "wy/s/down/mock/p0");
        assert_eq!(node_key("s", "wy/s/down/m").unwrap(), "wy/s/down/m");
        assert!(node_key("s", "wy/t/down/m").is_err());
        assert!(node_key("s", "down/*/p0").is_err());
        assert!(node_key("s", "down/m/~set").is_err());
        assert!(ApprovalMode::Write.needs_approval(Perm::Write));
        assert!(!ApprovalMode::Config.needs_approval(Perm::Write));
        assert!(ApprovalMode::Config.needs_approval(Perm::Config));
        assert!(ApprovalMode::Never.needs_approval(Perm::Config));
        assert!(!ApprovalMode::Never.needs_approval(Perm::Write));
    }
}
