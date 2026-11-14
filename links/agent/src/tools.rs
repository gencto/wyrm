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
    /// `wy/<site>/downstream/<agent link>`: never a target.
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

/// What one step of a plan does. `set` and `invoke` change the site; `wait`, `expect` and
/// `sleep` only read (the plan proves itself) and need no approval. The names are the keys of
/// a step in the `wyrm-agent run` plan format (`wyrm_mcp::gw::Step`, ADR 0033, 0049 §6).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OpKind {
    Set,
    Invoke,
    /// Wait until the node exists.
    Wait,
    /// Wait until the point's value passes a test.
    Expect,
    Sleep,
}

impl OpKind {
    pub const ALL: [Self; 5] = [
        Self::Set,
        Self::Invoke,
        Self::Wait,
        Self::Expect,
        Self::Sleep,
    ];

    pub fn name(self) -> &'static str {
        match self {
            Self::Set => "set",
            Self::Invoke => "invoke",
            Self::Wait => "wait",
            Self::Expect => "expect",
            Self::Sleep => "sleep",
        }
    }

    pub fn from_name(s: &str) -> Option<Self> {
        Self::ALL.into_iter().find(|k| k.name() == s)
    }

    /// Does the step send a `~set` or an `~act`?
    pub fn changes(self) -> bool {
        matches!(self, Self::Set | Self::Invoke)
    }
}

/// How far a proposed step could be checked (ADR 0049 §8).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Check {
    /// Checked against the live tree when it was proposed.
    #[default]
    Now,
    /// Its node does not exist yet (an earlier step makes it): checked when it runs.
    AtRun,
}

impl Check {
    pub fn name(self) -> &'static str {
        match self {
            Self::Now => "now",
            Self::AtRun => "at_run",
        }
    }

    pub fn from_name(s: &str) -> Self {
        if s == "at_run" {
            Self::AtRun
        } else {
            Self::Now
        }
    }
}

/// Longest `wait`/`expect` timeout and `sleep` of a step, seconds (as `wyrm-agent run`).
pub const MAX_STEP_WAIT_S: f64 = 600.0;

/// One validated plan step. Its number `n` is its place in the plan, from 1.
#[derive(Debug, Clone)]
pub struct PlanOp {
    pub op: OpKind,
    /// The node the step is about; empty for `sleep`.
    pub node: String,
    /// The exact request key of a step that changes something (`<node>/~set` or
    /// `<node>/~act/<action>`): what a human approval is for. The node key for `wait` and
    /// `expect`, empty for `sleep`.
    pub key: String,
    pub action: Option<String>,
    /// `set`: the value; `invoke`: the argument map; `expect`: the test, a map with one of
    /// `equals`, `min`/`max`, `changes` (empty: any value); else null.
    pub payload: Value,
    /// `wait`/`expect`: the timeout; `sleep`: its length. Seconds.
    pub seconds: Option<f64>,
    /// The level the request needs; `read` for a step that changes nothing.
    pub level: Perm,
    pub needs_approval: bool,
    pub reason: Option<String>,
    pub check: Check,
    /// What the person must know before approving (a value at a limit).
    pub warn: Option<String>,
    /// The steps (by number) this one needs: skipped when one of them is.
    pub after: Vec<usize>,
    /// What the run did with the step; `None` until it reaches it (a step after a failed one
    /// keeps `None`: it was never sent).
    pub result: Option<StepResult>,
}

/// How one step of a run ended.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StepStatus {
    Ok,
    Failed,
    /// Left out by the approver, or a step that needs one left out: never sent.
    Skipped,
}

impl StepStatus {
    pub fn name(self) -> &'static str {
        match self {
            Self::Ok => "ok",
            Self::Failed => "failed",
            Self::Skipped => "skipped",
        }
    }

    pub fn from_name(s: &str) -> Option<Self> {
        [Self::Ok, Self::Failed, Self::Skipped]
            .into_iter()
            .find(|v| v.name() == s)
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct StepResult {
    pub status: StepStatus,
    /// The responder's answer in short, or its refusal, or why it was skipped.
    pub message: String,
    /// When the step ended, seconds since the Unix epoch (0: a record older than this field).
    pub time: u64,
}

impl StepResult {
    pub fn to_value(&self) -> Value {
        Value::Map(BTreeMap::from([
            ("status".to_owned(), Value::from(self.status.name())),
            ("message".to_owned(), Value::from(self.message.as_str())),
            ("time".to_owned(), Value::UInt(self.time)),
        ]))
    }

    pub fn from_value(v: &Value) -> Option<Self> {
        let Value::Map(m) = v else { return None };
        let s = |k: &str| match m.get(k) {
            Some(Value::Str(s)) => Some(s.clone()),
            _ => None,
        };
        Some(Self {
            status: StepStatus::from_name(&s("status")?)?,
            message: s("message").unwrap_or_default(),
            time: match m.get("time") {
                Some(Value::UInt(t)) => *t,
                _ => 0,
            },
        })
    }
}

/// The keys of a step in `~state` that are not part of what it does: left out of
/// [`plan_hash`].
pub const UNHASHED: [&str; 5] = ["approval", "check", "warn", "reason", "result"];

impl PlanOp {
    /// The stricter of the value recorded at planning time and the current
    /// policy: a policy change during planning never lowers the bar. A step
    /// that changes nothing never needs a human.
    pub fn requires_approval(&self, policy: &Policy) -> bool {
        self.op.changes() && (self.needs_approval || policy.mode.needs_approval(self.level))
    }

    /// The step in the `wyrm-agent run` plan format: `{"set": <node>, "value"}`,
    /// `{"invoke": <node>, "action", "args"}`, `{"wait": <node>, "timeout_s"}`,
    /// `{"expect": <node>, "equals" | "min"/"max" | "changes", "timeout_s"}`, `{"sleep_s"}`.
    fn run_format(&self) -> BTreeMap<String, Value> {
        let mut m = BTreeMap::new();
        let node = Value::from(self.node.as_str());
        let secs = Value::Float(self.seconds.unwrap_or(0.0));
        match self.op {
            OpKind::Set => {
                m.insert("set".to_owned(), node);
                m.insert("value".to_owned(), self.payload.clone());
            }
            OpKind::Invoke => {
                m.insert("invoke".to_owned(), node);
                m.insert(
                    "action".to_owned(),
                    Value::from(self.action.as_deref().unwrap_or_default()),
                );
                m.insert("args".to_owned(), self.payload.clone());
            }
            OpKind::Wait => {
                m.insert("wait".to_owned(), node);
                m.insert("timeout_s".to_owned(), secs);
            }
            OpKind::Expect => {
                m.insert("expect".to_owned(), node);
                if let Value::Map(test) = &self.payload {
                    m.extend(test.clone());
                }
                m.insert("timeout_s".to_owned(), secs);
            }
            OpKind::Sleep => {
                m.insert("sleep_s".to_owned(), secs);
            }
        }
        m
    }

    /// The step as the task's `~state` shows it: the run format, its number `n`, `level`,
    /// `after`, and what is said about it (`approval`: the bar of now, what `approve` will
    /// ask for; `check`; `warn`; `reason`; `result`).
    pub fn to_value(&self, n: usize, policy: &Policy) -> Value {
        let mut m = self.hashed(n);
        m.insert(
            "approval".to_owned(),
            Value::Bool(self.requires_approval(policy)),
        );
        m.insert("check".to_owned(), Value::from(self.check.name()));
        if let Some(w) = &self.warn {
            m.insert("warn".to_owned(), Value::from(w.as_str()));
        }
        if let Some(r) = &self.reason {
            m.insert("reason".to_owned(), Value::from(r.as_str()));
        }
        if let Some(r) = &self.result {
            m.insert("result".to_owned(), r.to_value());
        }
        Value::Map(m)
    }

    /// What the step does, as [`plan_hash`] covers it: [`to_value`](Self::to_value) without
    /// the keys of [`UNHASHED`].
    fn hashed(&self, n: usize) -> BTreeMap<String, Value> {
        let mut m = self.run_format();
        m.insert("n".to_owned(), Value::UInt(n as u64));
        m.insert("level".to_owned(), Value::from(self.level.name()));
        if !self.after.is_empty() {
            m.insert(
                "after".to_owned(),
                Value::Array(self.after.iter().map(|a| Value::UInt(*a as u64)).collect()),
            );
        }
        m
    }

    /// The request body of a step that changes something, byte for byte as the run sends
    /// it: what a human approval may be bound to (claim `args`, spec 04).
    pub fn request_payload(&self) -> Result<Vec<u8>, String> {
        match self.op {
            OpKind::Set => wyrm_client::set_payload(self.payload.clone()),
            OpKind::Invoke => wyrm_client::invoke_payload(&self.payload),
            _ => return Err("the step sends no request".into()),
        }
        .map_err(|e| e.to_string())
    }

    /// One line for the log and the model: `set <node>`, `expect <node>`, `sleep 5 s`.
    pub fn describe(&self) -> String {
        match self.op {
            OpKind::Sleep => format!("sleep {} s", self.seconds.unwrap_or(0.0)),
            OpKind::Invoke => format!("invoke {}", self.key),
            op => format!("{} {}", op.name(), self.node),
        }
    }
}

/// What an approval of a plan is bound to (`~state.plan_hash`, `approve {plan}`): the SHA-256
/// (hex) of the canonical CBOR of the plan as `~state.plan` shows it, each step without the
/// keys of [`UNHASHED`]. Two plans with the same hash send the same requests at the same
/// levels, in the same order, with the same dependencies. The gateway and a client make the
/// same hash from the `~state` they read, so an approval of another plan is refused.
pub fn plan_hash(plan: &[PlanOp]) -> String {
    let steps = plan
        .iter()
        .enumerate()
        .map(|(i, op)| Value::Map(op.hashed(i + 1)))
        .collect();
    check::payload_sha256(&wyrm_core::codec::to_vec(&Value::Array(steps)).unwrap_or_default())
}

/// The steps of `plan` that do not run when the steps in `unapproved` (numbers from 1) get no
/// approval: those, and every step that needs one of them (`after`), with the step each one
/// is skipped for (itself for an unapproved one).
pub fn skipped(plan: &[PlanOp], unapproved: &[usize]) -> BTreeMap<usize, usize> {
    let mut out: BTreeMap<usize, usize> = unapproved.iter().map(|n| (*n, *n)).collect();
    // `after` names earlier steps only, so one pass in order settles every chain
    for (i, op) in plan.iter().enumerate() {
        let n = i + 1;
        if out.contains_key(&n) {
            continue;
        }
        if let Some(dep) = op.after.iter().find(|a| out.contains_key(a)) {
            out.insert(n, *dep);
        }
    }
    out
}

fn str_field<'a>(input: &'a Json, k: &str) -> Result<&'a str, String> {
    input[k]
        .as_str()
        .ok_or_else(|| format!("`{k}` (string) is required"))
}

/// The `after` of a new step: what the model named, else the latest earlier step that
/// changes something on the step's node or on a node above it (it makes or prepares what
/// this step needs). `sleep` depends on the step before it.
fn after_of(input: &Json, plan: &[PlanOp], op: OpKind, node: &str) -> Result<Vec<usize>, String> {
    match input.get("after") {
        None | Some(Json::Null) => {}
        Some(Json::Array(a)) => {
            let mut out = Vec::new();
            for v in a {
                let n = v
                    .as_u64()
                    .map(|n| n as usize)
                    .filter(|n| (1..=plan.len()).contains(n))
                    .ok_or_else(|| {
                        format!(
                            "`after`: numbers of earlier steps (1..{}) are expected",
                            plan.len()
                        )
                    })?;
                if !out.contains(&n) {
                    out.push(n);
                }
            }
            out.sort_unstable();
            return Ok(out);
        }
        Some(_) => return Err("`after` must be an array of step numbers".into()),
    }
    if op == OpKind::Sleep {
        return Ok(if plan.is_empty() {
            Vec::new()
        } else {
            vec![plan.len()]
        });
    }
    Ok(plan
        .iter()
        .enumerate()
        .rev()
        .find(|(_, p)| p.op.changes() && under(node, &p.node))
        .map(|(i, _)| vec![i + 1])
        .unwrap_or_default())
}

fn seconds(input: &Json, k: &str, default: f64) -> Result<f64, String> {
    match input.get(k) {
        None | Some(Json::Null) => Ok(default),
        Some(v) => v
            .as_f64()
            .filter(|s| s.is_finite() && *s >= 0.0)
            .map(|s| s.min(MAX_STEP_WAIT_S))
            .ok_or_else(|| format!("`{k}` must be a number of seconds")),
    }
}

/// The test of an `expect` step as a map: one of `equals`, `min`/`max`, `changes`; empty:
/// any value.
fn expect_test(input: &Json) -> Result<Value, String> {
    let mut m = BTreeMap::new();
    if let Some(v) = input.get("equals").filter(|v| !v.is_null()) {
        m.insert("equals".to_owned(), json_to_value(v)?);
    } else if input["changes"].as_bool() == Some(true) {
        m.insert("changes".to_owned(), Value::Bool(true));
    } else {
        for k in ["min", "max"] {
            if let Some(v) = input.get(k).filter(|v| !v.is_null()) {
                let x = v
                    .as_f64()
                    .filter(|x| x.is_finite())
                    .ok_or_else(|| format!("`{k}` must be a number"))?;
                m.insert(k.to_owned(), Value::Float(x));
            }
        }
    }
    Ok(Value::Map(m))
}

/// A value at a limit of its point: the person should see it before approving.
fn limit_warning(meta: &wyrm_core::NodeMeta, v: &Value) -> Option<String> {
    let x = v.as_f64()?;
    ["min", "max"].into_iter().find_map(|k| {
        let bound = meta.cfg_value(k)?.as_f64()?;
        (x == bound).then(|| format!("the value {x} is at the point's {k} ({bound})"))
    })
}

/// Dry-run check of a proposal (the `wyrm-mcp` rules): node key, policy,
/// `~meta` (type, enum, bounds, action schema), level, approval need. `plan` is the plan so
/// far: a step on a node that does not exist yet is taken when an earlier step may make it
/// (`check: at_run`), and is then checked when it runs.
pub async fn check_proposal(
    reader: &WyrmClient,
    policy: &Policy,
    plan: &[PlanOp],
    input: &Json,
) -> Result<PlanOp, String> {
    let op = match str_field(input, "op")? {
        "flow_apply" => {
            return Err("flow_apply is not supported by this agent yet".into());
        }
        other => OpKind::from_name(other).ok_or_else(|| {
            format!("unknown op {other:?}; use set, invoke, wait, expect or sleep")
        })?,
    };
    let reason = input["reason"]
        .as_str()
        .map(|s| s.chars().take(500).collect());
    let blank = PlanOp {
        op,
        node: String::new(),
        key: String::new(),
        action: None,
        payload: Value::Null,
        seconds: None,
        level: Perm::Read,
        needs_approval: false,
        reason,
        check: Check::Now,
        warn: None,
        after: Vec::new(),
        result: None,
    };
    if op == OpKind::Sleep {
        return Ok(PlanOp {
            seconds: Some(seconds(input, "seconds", 1.0)?),
            after: after_of(input, plan, op, "")?,
            ..blank
        });
    }
    let node = policy.node_key(str_field(input, "path")?)?;
    let after = after_of(input, plan, op, &node)?;
    if !op.changes() {
        // a proof step reads: inside what the model may read, no approval
        policy.may_read(&node)?;
        return Ok(PlanOp {
            key: node.clone(),
            payload: match op {
                OpKind::Expect => expect_test(input)?,
                _ => Value::Null,
            },
            seconds: Some(seconds(input, "timeout_s", 10.0)?),
            node,
            after,
            ..blank
        });
    }
    policy.may_touch(&node)?;
    let action = match op {
        OpKind::Invoke => {
            let a = str_field(input, "action")?.to_owned();
            wyrm_core::keyspace::validate_segment(&a).map_err(|e| e.to_string())?;
            Some(a)
        }
        _ => None,
    };
    let key = match &action {
        Some(a) => format!("{node}/~act/{a}"),
        None => format!("{node}/~set"),
    };
    let meta = match reader.meta_expanded(&node).await {
        Ok(m) => Some(m),
        // made by an earlier step: checked when it runs
        Err(e) if e.is(wyrm_core::Status::NotFound) && !after.is_empty() => None,
        Err(e) => return Err(format!("{node}: {e}")),
    };
    let (payload, mut level, warn) = match (&meta, &action) {
        (Some(meta), None) => {
            let level = check::set_level(meta)?;
            let v = json_to_value(input.get("value").ok_or("`value` is required for set")?)?;
            let v = check::coerce_enum(meta.ty, meta.enum_values.as_deref(), v);
            check::validate_value(meta, &v)?;
            let warn = limit_warning(meta, &v);
            (v, level, warn)
        }
        (Some(meta), Some(action)) => {
            let level = check::action_level(meta, action)?;
            let act = meta
                .actions
                .as_ref()
                .and_then(|a| a.get(action))
                .cloned()
                .unwrap_or_default();
            let args = check::prepare_args(&act.params, given_args(input)?)?;
            (Value::Map(args), level, None)
        }
        // Unknown until the node exists: sent as given, at `write`. A node that then asks
        // for more refuses the step; the token never gives more than was approved.
        (None, None) => (
            json_to_value(input.get("value").ok_or("`value` is required for set")?)?,
            Perm::Write,
            None,
        ),
        (None, Some(_)) => (Value::Map(given_args(input)?), Perm::Write, None),
    };
    if check::is_control_plane(&policy.site, &node) {
        level = Perm::Config;
    }
    Ok(PlanOp {
        node,
        key,
        action,
        payload,
        level,
        needs_approval: policy.mode.needs_approval(level),
        check: if meta.is_some() {
            Check::Now
        } else {
            Check::AtRun
        },
        warn,
        after,
        ..blank
    })
}

fn given_args(input: &Json) -> Result<BTreeMap<String, Value>, String> {
    match input.get("args") {
        None | Some(Json::Null) => Ok(BTreeMap::new()),
        Some(Json::Object(o)) => o
            .iter()
            .map(|(k, v)| json_to_value(v).map(|v| (k.clone(), v)))
            .collect(),
        Some(_) => Err("`args` must be an object".into()),
    }
}

/// Tool definitions for the Messages API (`tools`).
pub fn definitions() -> Json {
    let path = json!({"type": "string", "description": "Node key, `wy/<site>/downstream/<link>/<path>` or relative to the site (`downstream/mock/p0`)."});
    json!([
        {"name": "tree_list", "description": "(Read tools see only allowed_prefixes and pub/**.) Children of a node with their ~meta summary (type, unit, writable, display, has_children). `downstream` lists links. Paged with from/limit; `next` is the next `from`.",
         "input_schema": {"type": "object", "properties": {"path": path, "from": {"type": "integer"}, "limit": {"type": "integer"}}, "required": ["path"]}},
        {"name": "tree_resolve", "description": "Descendant keys of a node, optionally filtered by ~meta fields (`match`, e.g. `type:1;unit:°C`) and depth. Cheap: keys only.",
         "input_schema": {"type": "object", "properties": {"path": path, "match": {"type": "string"}, "depth": {"type": "integer"}}, "required": ["path"]}},
        {"name": "node_meta", "description": "Full ~meta of a node: type, unit, enum, writable level, cfg (min/max), attr, actions with parameter schemas and levels, children. expand=true folds in the profile chain.",
         "input_schema": {"type": "object", "properties": {"path": path, "expand": {"type": "boolean"}}, "required": ["path"]}},
        {"name": "value_get", "description": "Current values (~val) of up to 200 nodes: {path: {v, q, t}} or {error}. An enum value has `v` = its index and `name` = its name; report the name.",
         "input_schema": {"type": "object", "properties": {"paths": {"type": "array", "items": {"type": "string"}}}, "required": ["paths"]}},
        {"name": "profiles", "description": "Node profiles under wy/<site>/pub/<name>/~meta. This is also the device-model catalog: a profile named `<vendor>:<model>` describes one device model, and its `attr` carries the model data (e.g. `registers`, point profiles, typical cfg, documentation links). Filter by a name substring.",
         "input_schema": {"type": "object", "properties": {"filter": {"type": "string"}}}},
        {"name": "flow_get", "description": "Definition (~def) and state of a flow.",
         "input_schema": {"type": "object", "properties": {"id": {"type": "string"}}, "required": ["id"]}},
        {"name": "flow_validate", "description": "Compile a flow definition (spec 06) on the flow engine without deploying it.",
         "input_schema": {"type": "object", "properties": {"def": {"type": "object"}}, "required": ["def"]}},
        {"name": "spec", "description": "The normative WYRM spec: 01 keyspace, 02 meta, 03 val, 04 attachment, 05 methods, 06 flow-def, readme, tables, changelog. Without a section: the list.",
         "input_schema": {"type": "object", "properties": {"section": {"type": "string"}}}},
        {"name": "propose", "description": "Add one step to the task plan. It is NOT executed now: it is checked against ~meta (type, enum, min/max, action schema) and the agent's allowed_prefixes, then shown to a human who approves the steps they want. op=set needs `value`; op=invoke needs `action` and `args`. Prove the plan with steps that only read and need no approval: op=wait (until the node `path` exists), op=expect (until the value of `path` is `equals`, or within `min`/`max`, or `changes`; none of them: any value), op=sleep (`seconds`). The answer is {ok, n, check, warn?}: `check` is `now` (checked against the live tree) or `at_run` (the node does not exist yet; an earlier step makes it); show `warn` to the person. An error result means the step was not added; fix it or explain why it is impossible. Read the node with node_meta first.",
         "input_schema": {"type": "object", "properties": {
            "op": {"type": "string", "enum": ["set", "invoke", "wait", "expect", "sleep"]},
            "path": path,
            "value": {"description": "New value for op=set (enum by name or index; binary as {\"$bytes\": \"<base64>\"})."},
            "action": {"type": "string", "description": "Action name for op=invoke."},
            "args": {"type": "object", "description": "Action arguments for op=invoke."},
            "equals": {"description": "op=expect: the value to wait for."},
            "min": {"type": "number"}, "max": {"type": "number"},
            "changes": {"type": "boolean", "description": "op=expect: two different values are seen."},
            "timeout_s": {"type": "number", "description": "op=wait/expect: seconds to wait (default 10, at most 600)."},
            "seconds": {"type": "number", "description": "op=sleep."},
            "after": {"type": "array", "items": {"type": "integer"}, "description": "Numbers of the earlier steps this step needs: it is skipped when the person leaves one of them out. Default: the latest earlier change on this node or a node above it."},
            "reason": {"type": "string", "description": "One sentence: why this step is needed."}
         }, "required": ["op"]}},
        {"name": "ask_user", "description": "Ask the person one question before you plan, when the task leaves a real choice open. At most 3 questions in one turn. Give up to 6 options; every option must name something you have read in the tree (a node, a value, a profile), never a guess. The task then waits; the answer comes back as this tool's result.",
         "input_schema": {"type": "object", "properties": {
            "question": {"type": "string"},
            "options": {"type": "array", "items": {"type": "object", "properties": {
                "id": {"type": "string"}, "label": {"type": "string"}, "detail": {"type": "string"}
            }, "required": ["id", "label"]}},
            "multiple": {"type": "boolean", "description": "Several options may be picked."},
            "free_text": {"type": "boolean", "description": "The person may answer in their own words."}
         }, "required": ["question"]}}
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
                    Ok(node) => match self.read_val(&node).await {
                        Ok(s) => {
                            let mut j = sample_to_json(&s);
                            // An enum travels as its index: the model gets the
                            // name beside it, so it never reports a bare code.
                            if let Some(i) = enum_index(&s.v) {
                                if let Ok(m) = self.client.meta(&node).await {
                                    if let Some(name) = enum_name(m.enum_values.as_deref(), i) {
                                        j["name"] = name.into();
                                    }
                                }
                            }
                            j
                        }
                        Err(e) => json!({ "error": e }),
                    },
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
        let node = format!("wy/{}/dataflows/{id}", self.site);
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
        self.policy
            .may_read(&format!("wy/{}/dataflows", self.site))?;
        let def = json_to_value(input.get("def").ok_or("`def` is required")?)?;
        let mut args = BTreeMap::new();
        args.insert("def".to_owned(), def);
        let r = self
            .client
            .invoke_one(
                &format!("wy/{}/dataflows", self.site),
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

/// The index an enum value would have: a whole number that is not negative.
fn enum_index(v: &Value) -> Option<usize> {
    match v {
        Value::UInt(u) => usize::try_from(*u).ok(),
        Value::Int(i) => usize::try_from(*i).ok(),
        _ => None,
    }
}

/// The name of index `i` in a node's enum, when the node has one.
fn enum_name(values: Option<&[String]>, i: usize) -> Option<&str> {
    values?.get(i).map(String::as_str)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn an_enum_value_has_a_name() {
        let names = ["new".to_owned(), "connecting".into(), "connected".into()];
        assert_eq!(enum_index(&Value::UInt(2)), Some(2));
        assert_eq!(enum_index(&Value::Int(2)), Some(2));
        assert_eq!(enum_index(&Value::Int(-1)), None);
        assert_eq!(enum_index(&Value::Float(2.0)), None);
        assert_eq!(enum_name(Some(&names), 2), Some("connected"));
        // past the list, or a node with no enum: the number stays alone
        assert_eq!(enum_name(Some(&names), 9), None);
        assert_eq!(enum_name(None, 2), None);
    }

    #[test]
    fn approval_bar_never_drops_after_planning() {
        let op = PlanOp {
            op: OpKind::Set,
            node: "wy/s/downstream/m/p".into(),
            key: "wy/s/downstream/m/p/~set".into(),
            action: None,
            payload: Value::Float(1.0),
            level: Perm::Write,
            needs_approval: false, // planned under mode `config`
            reason: None,
            result: None,
            seconds: None,
            check: Check::Now,
            warn: None,
            after: Vec::new(),
        };
        // the hash covers what is sent, at which level and after what, not the model's words
        // or the run
        let h = plan_hash(std::slice::from_ref(&op));
        // the same vector as dart/wyrm_client/test/plan_hash_test.dart
        assert_eq!(
            h,
            "08900496afc130ee83048251cb224b679cbfd06491270fa67d386c7dcc6cd60d"
        );
        let reworded = PlanOp {
            reason: Some("because".into()),
            warn: Some("at the limit".into()),
            check: Check::AtRun,
            needs_approval: true,
            result: Some(StepResult {
                status: StepStatus::Ok,
                message: "set ok".into(),
                time: 5,
            }),
            ..op.clone()
        };
        assert_eq!(plan_hash(std::slice::from_ref(&reworded)), h);
        for other in [
            PlanOp {
                payload: Value::Float(2.0),
                ..op.clone()
            },
            PlanOp {
                node: "wy/s/downstream/m/q".into(),
                ..op.clone()
            },
            PlanOp {
                level: Perm::Config,
                ..op.clone()
            },
            PlanOp {
                after: vec![1],
                ..op.clone()
            },
        ] {
            assert_ne!(plan_hash(std::slice::from_ref(&other)), h);
        }
        assert_ne!(plan_hash(&[op.clone(), op.clone()]), h);
        // a step left out takes the steps that need it with it, along the whole chain
        let chain = |after: &[usize]| PlanOp {
            after: after.to_vec(),
            ..op.clone()
        };
        let plan = [
            chain(&[]),
            chain(&[1]),
            chain(&[]),
            chain(&[2, 3]),
            chain(&[3]),
        ];
        assert_eq!(
            skipped(&plan, &[1]),
            BTreeMap::from([(1, 1), (2, 1), (4, 2)])
        );
        assert_eq!(
            skipped(&plan, &[3]),
            BTreeMap::from([(3, 3), (4, 3), (5, 3)])
        );
        assert!(skipped(&plan, &[]).is_empty());
        // a step that only reads never needs a human
        let proof = PlanOp {
            op: OpKind::Expect,
            needs_approval: true,
            ..op.clone()
        };
        assert!(!proof.requires_approval(&policy(&[], ApprovalMode::Write)));
        assert!(!op.requires_approval(&policy(&[], ApprovalMode::Config)));
        // the policy became stricter while the task was planning
        assert!(op.requires_approval(&policy(&[], ApprovalMode::Write)));
        // a recorded requirement stays even if the policy relaxes
        let strict = PlanOp {
            needs_approval: true,
            ..op
        };
        assert!(strict.requires_approval(&policy(&[], ApprovalMode::Never)));
    }

    fn policy(allowed: &[&str], mode: ApprovalMode) -> Policy {
        Policy {
            site: "s".into(),
            own: "wy/s/downstream/agent".into(),
            allowed: allowed.iter().map(|s| (*s).to_owned()).collect(),
            mode,
        }
    }

    #[test]
    fn prefixes_on_segment_boundaries() {
        let p = policy(&["wy/s/downstream/mock"], ApprovalMode::Write);
        assert!(p.may_touch("wy/s/downstream/mock").is_ok());
        assert!(p.may_touch("wy/s/downstream/mock/p0").is_ok());
        assert!(p.may_touch("wy/s/downstream/mockery/p0").is_err());
        assert!(p.may_touch("wy/s/downstream/agent/tasks").is_err());
        assert!(policy(&[], ApprovalMode::Write)
            .may_touch("wy/s/downstream/mock/p0")
            .is_err());
        let own = policy(&["wy/s/downstream"], ApprovalMode::Write);
        assert!(own.may_touch("wy/s/downstream/agent/x").is_err());
    }

    #[test]
    fn keys_and_modes() {
        assert_eq!(
            node_key("s", "downstream/mock/p0").unwrap(),
            "wy/s/downstream/mock/p0"
        );
        assert_eq!(
            node_key("s", "wy/s/downstream/m").unwrap(),
            "wy/s/downstream/m"
        );
        assert!(node_key("s", "wy/t/downstream/m").is_err());
        assert!(node_key("s", "downstream/*/p0").is_err());
        assert!(node_key("s", "downstream/m/~set").is_err());
        assert!(ApprovalMode::Write.needs_approval(Perm::Write));
        assert!(!ApprovalMode::Config.needs_approval(Perm::Write));
        assert!(ApprovalMode::Config.needs_approval(Perm::Config));
        assert!(ApprovalMode::Never.needs_approval(Perm::Config));
        assert!(!ApprovalMode::Never.needs_approval(Perm::Write));
    }
}
