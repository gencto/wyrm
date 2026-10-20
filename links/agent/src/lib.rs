//! AI agent connector (ADR 0005, wiki "AI-агент, MCP і CLI" §2).
//!
//! Tree under `wy/<site>/down/<link>`:
//!
//! | key | what |
//! |---|---|
//! | `~meta.cfg` | `model`, `budget_tokens_day`, `allowed_prefixes`, `require_approval`, … |
//! | `~act/ask {task}` | level `write`, stream: creates `tasks/<id>`, streams progress, ends with `{task, state}` |
//! | `tasks/<id>/~val` | `{state, ask, plan, log, error?, tokens}` |
//! | `tasks/<id>/~act/approve {approvals}` | level `config`: `{<request key>: <base64 ptok>}` |
//! | `tasks/<id>/~act/reject`, `cancel` | level `write` |
//!
//! States: `planning → awaiting_approval → running → done | failed`
//! (`reject` and `cancel` end in `failed` with `error`).
//!
//! Safety does not rest on the model. The model only reads (read-only tools)
//! and proposes; a proposal is checked against `~meta`, `allowed_prefixes`
//! and the level it needs. Execution sends each operation either with the
//! human approval token for exactly its request key (the target link checks
//! the human's rights) or, for write-level operations that need no approval,
//! with the agent's own service token (`ai:<link>`, `max = write`): the agent
//! can never perform a `config` operation by itself.

#![forbid(unsafe_code)]

pub mod llm;
pub mod tools;

use crate::llm::{usage_tokens, AnthropicClient, LlmClient};
use crate::tools::{check_proposal, ApprovalMode, PlanOp, Policy, Reader};
use ed25519_dalek::SigningKey;
use serde_json::{json, Value as Json};
use std::collections::{BTreeMap, VecDeque};
use std::sync::{Arc, Mutex};
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use tracing::{debug, warn};
use wyrm_client::{SigningTokens, TokenSource, WyrmClient};
use wyrm_core::meta::{ActionResult, ParamMeta};
use wyrm_core::ptok::Grant;
use wyrm_core::{ActionMeta, NodeMeta, Perm, Quality, Status, TypeCode, Value};
use wyrm_link_sdk::{
    now_us, Caller, Fields, FromParams, Link, LinkCtx, LinkError, ReplySink, Result,
};
use zeroize::Zeroizing;

/// Kept tasks; the oldest finished ones are removed beyond this.
const MAX_TASKS: usize = 200;
const MAX_LOG: usize = 200;
const MAX_PLAN: usize = 50;
const MAX_ASK_CHARS: usize = 8000;
/// Tool result text sent back to the model.
const MAX_TOOL_RESULT: usize = 16_000;
/// Most results kept from a streaming action during execution.
const MAX_INVOKE_RESULTS: usize = 100;
/// `ask` stream: longest gap between progress items (one LLM call).
const ASK_TIMEOUT_MS: u32 = 300_000;
/// Progress `wait` items while an LLM call runs.
const KEEPALIVE: Duration = Duration::from_secs(1);

const SYSTEM: &str = "You are the WYRM agent: an operator assistant for an IoT broker with \
IOT-DSA semantics. Node keys are `wy/<site>/down/<link>/<path>`; paths may be given relative \
to the site (`down/<link>/<path>`). Explore with tree_list, tree_resolve, node_meta and \
value_get; device models are profiles named `<vendor>:<model>` (profiles tool) whose attr holds \
the model data. You cannot change anything yourself: call `propose` once per change (op=set or \
op=invoke). Every proposal is checked and then shown to a human, who approves or rejects the \
whole plan. Propose only what the task needs; read a node's ~meta before you propose a change \
to it. When you are done, answer with a short summary of the plan, or of what you found if no \
change is needed.";

/// Agent link parameters (`~def.params`).
#[derive(Debug, Clone, PartialEq)]
pub struct AgentParams {
    pub model: String,
    /// LLM tokens per UTC day (input + output + cache); `ask` is refused at the limit.
    pub budget_tokens_day: u64,
    /// Node keys (full or site-relative) under which the agent may propose
    /// changes. Empty: nothing is writable.
    pub allowed_prefixes: Vec<String>,
    pub require_approval: ApprovalMode,
    /// Secret name of the Anthropic API key.
    pub api_key_ref: String,
    /// Secret name of the agent's Ed25519 signing key (32 bytes, raw or hex).
    pub agent_key_ref: String,
    pub api_base: String,
    pub max_turns: u32,
    pub max_tokens: u32,
    /// Server-side refusal fallback (`fallbacks: "default"`).
    pub fallbacks: bool,
    pub llm_timeout_s: u64,
}

impl Default for AgentParams {
    fn default() -> Self {
        Self {
            model: "claude-sonnet-5-5".into(),
            budget_tokens_day: 1_000_000,
            allowed_prefixes: Vec::new(),
            require_approval: ApprovalMode::Write,
            api_key_ref: "anthropic_api_key".into(),
            agent_key_ref: "agent_key".into(),
            api_base: "https://api.anthropic.com".into(),
            max_turns: 16,
            max_tokens: 16_000,
            fallbacks: true,
            llm_timeout_s: 240,
        }
    }
}

const PARAM_NAMES: &[&str] = &[
    "model",
    "budget_tokens_day",
    "allowed_prefixes",
    "require_approval",
    "api_key_ref",
    "agent_key_ref",
    "api_base",
    "max_turns",
    "max_tokens",
    "fallbacks",
    "llm_timeout_s",
];

impl AgentParams {
    pub fn from_value(v: &Value) -> Result<Self> {
        let empty = Value::Map(BTreeMap::new());
        let f = Fields::new(if matches!(v, Value::Null) { &empty } else { v })?;
        f.only(PARAM_NAMES)?;
        let d = Self::default();
        let s = |k: &str, d: &str| -> Result<String> {
            Ok(f.opt_str(k)?
                .map(str::to_owned)
                .unwrap_or_else(|| d.to_owned()))
        };
        let allowed_prefixes = match f.get("allowed_prefixes") {
            None => Vec::new(),
            Some(Value::Array(items)) => items
                .iter()
                .map(|i| match i {
                    Value::Str(s) => Ok(s.clone()),
                    _ => Err(LinkError::invalid_parameter(
                        "params.allowed_prefixes: expected strings",
                    )),
                })
                .collect::<Result<_>>()?,
            Some(_) => {
                return Err(LinkError::invalid_parameter(
                    "params.allowed_prefixes: expected an array of strings",
                ))
            }
        };
        let mode = s("require_approval", d.require_approval.name())?;
        let require_approval = ApprovalMode::from_name(&mode).ok_or_else(|| {
            LinkError::invalid_parameter(format!(
                "params.require_approval: expected one of {:?}",
                ApprovalMode::NAMES
            ))
        })?;
        let p = Self {
            model: s("model", &d.model)?,
            budget_tokens_day: f.u64_or("budget_tokens_day", d.budget_tokens_day)?,
            allowed_prefixes,
            require_approval,
            api_key_ref: s("api_key_ref", &d.api_key_ref)?,
            agent_key_ref: s("agent_key_ref", &d.agent_key_ref)?,
            api_base: s("api_base", &d.api_base)?,
            max_turns: wyrm_link_sdk::params::narrow(
                f.u64_or("max_turns", d.max_turns.into())?.clamp(1, 64),
                "max_turns",
            )?,
            max_tokens: wyrm_link_sdk::params::narrow(
                f.u64_or("max_tokens", d.max_tokens.into())?
                    .clamp(256, 128_000),
                "max_tokens",
            )?,
            fallbacks: f.bool_or("fallbacks", d.fallbacks)?,
            llm_timeout_s: f.u64_or("llm_timeout_s", d.llm_timeout_s)?.clamp(5, 600),
        };
        if p.model.is_empty() {
            return Err(LinkError::invalid_parameter("params.model: empty"));
        }
        llm::parse_base(&p.api_base)
            .map_err(|e| LinkError::invalid_parameter(format!("params.{e}")))?;
        Ok(p)
    }

    /// `~meta.cfg` view (secret names only, never secret values).
    pub fn cfg_map(&self) -> BTreeMap<String, Value> {
        let mut m = BTreeMap::new();
        m.insert("model".into(), Value::from(self.model.as_str()));
        m.insert(
            "budget_tokens_day".into(),
            Value::UInt(self.budget_tokens_day),
        );
        m.insert(
            "allowed_prefixes".into(),
            Value::Array(
                self.allowed_prefixes
                    .iter()
                    .map(|p| Value::from(p.as_str()))
                    .collect(),
            ),
        );
        m.insert(
            "require_approval".into(),
            Value::from(self.require_approval.name()),
        );
        m.insert("api_key_ref".into(), Value::from(self.api_key_ref.as_str()));
        m.insert(
            "agent_key_ref".into(),
            Value::from(self.agent_key_ref.as_str()),
        );
        m.insert("api_base".into(), Value::from(self.api_base.as_str()));
        m.insert("max_turns".into(), Value::UInt(self.max_turns.into()));
        m.insert("max_tokens".into(), Value::UInt(self.max_tokens.into()));
        m.insert("fallbacks".into(), Value::Bool(self.fallbacks));
        m.insert("llm_timeout_s".into(), Value::UInt(self.llm_timeout_s));
        m
    }
}

/// `Link::Config`: the params plus an optional LLM backend. `None` (process
/// mode) builds the Anthropic client from the `api_key_ref` secret.
#[derive(Clone)]
pub struct AgentConfig {
    pub params: AgentParams,
    pub llm: Option<Arc<dyn LlmClient>>,
}

impl FromParams for AgentConfig {
    fn from_params(v: &Value) -> Result<Self> {
        Ok(Self {
            params: AgentParams::from_value(v)?,
            llm: None,
        })
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TaskState {
    Planning,
    AwaitingApproval,
    Running,
    Done,
    Failed,
}

impl TaskState {
    pub fn name(self) -> &'static str {
        match self {
            Self::Planning => "planning",
            Self::AwaitingApproval => "awaiting_approval",
            Self::Running => "running",
            Self::Done => "done",
            Self::Failed => "failed",
        }
    }

    fn finished(self) -> bool {
        matches!(self, Self::Done | Self::Failed)
    }
}

struct Task {
    /// Subject of the `ask` caller; only they (or a `config` caller) may
    /// reject or cancel.
    owner: String,
    ask: String,
    state: TaskState,
    plan: Vec<PlanOp>,
    log: Vec<String>,
    error: Option<String>,
    tokens: u64,
    cancel: bool,
    planner: Option<tokio::task::AbortHandle>,
}

impl Task {
    fn push_log(&mut self, line: impl Into<String>) {
        let mut line: String = line.into();
        if line.len() > 1000 {
            line = truncate(&line, 1000);
        }
        if self.log.len() >= MAX_LOG {
            self.log.remove(0);
        }
        self.log.push(line);
    }

    fn fail(&mut self, e: impl Into<String>) {
        let e = e.into();
        self.push_log(format!("failed: {e}"));
        self.error = Some(e);
        self.state = TaskState::Failed;
    }

    /// Public `~val`: the state only. `~val` is broadcast and answered
    /// without a token, so model output never goes there.
    fn public_value(&self) -> Value {
        map_value(vec![("state", Value::from(self.state.name()))])
    }

    /// The full record, served as the `~state` document of the task node
    /// (restricted: readers need `list` on it). Never holds tokens.
    fn to_value(&self) -> Value {
        let mut m = BTreeMap::new();
        m.insert("state".to_owned(), Value::from(self.state.name()));
        m.insert("owner".to_owned(), Value::from(self.owner.as_str()));
        m.insert("ask".to_owned(), Value::from(self.ask.as_str()));
        m.insert(
            "plan".to_owned(),
            Value::Array(self.plan.iter().map(PlanOp::to_value).collect()),
        );
        m.insert(
            "log".to_owned(),
            Value::Array(self.log.iter().map(|l| Value::from(l.as_str())).collect()),
        );
        if let Some(e) = &self.error {
            m.insert("error".to_owned(), Value::from(e.as_str()));
        }
        m.insert("tokens".to_owned(), Value::UInt(self.tokens));
        Value::Map(m)
    }
}

fn truncate(s: &str, max: usize) -> String {
    if s.len() <= max {
        return s.to_owned();
    }
    let mut end = max;
    while !s.is_char_boundary(end) {
        end -= 1;
    }
    format!("{}…", &s[..end])
}

#[derive(Default)]
struct Budget {
    day: u64,
    used: u64,
}

impl Budget {
    fn today() -> u64 {
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_secs() / 86_400)
            .unwrap_or(0)
    }

    fn roll(&mut self) {
        let d = Self::today();
        if d != self.day {
            self.day = d;
            self.used = 0;
        }
    }

    fn used(&mut self) -> u64 {
        self.roll();
        self.used
    }

    fn add(&mut self, n: u64) {
        self.roll();
        self.used = self.used.saturating_add(n);
    }
}

#[derive(Default)]
struct State {
    tasks: BTreeMap<String, Task>,
    order: VecDeque<String>,
    budget: Budget,
    next: u64,
}

/// Token source with exactly one token for exactly one key (a human approval).
struct OneKey {
    key: String,
    tok: Vec<u8>,
}

impl TokenSource for OneKey {
    fn token(&self, key: &str) -> Option<Vec<u8>> {
        (key == self.key).then(|| self.tok.clone())
    }
}

struct Shared {
    ctx: LinkCtx,
    params: Mutex<AgentParams>,
    llm: Option<Arc<dyn LlmClient>>,
    /// Reads: with the service token when there is one (restricted `~meta`).
    reader: WyrmClient,
    /// `ai:<link>`, `max = write`; `None` without an agent key.
    service: Option<WyrmClient>,
    /// Plain client for sends with a human approval.
    plain: WyrmClient,
    state: Mutex<State>,
}

impl Shared {
    fn lock(&self) -> std::sync::MutexGuard<'_, State> {
        self.state.lock().unwrap_or_else(|p| p.into_inner())
    }

    fn params(&self) -> AgentParams {
        self.params
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .clone()
    }

    fn policy(&self) -> Policy {
        let p = self.params();
        let site = self.ctx.site().to_owned();
        Policy {
            own: self.ctx.key("", ""),
            allowed: full_prefixes(&site, &p.allowed_prefixes),
            mode: p.require_approval,
            site,
        }
    }

    fn task_path(id: &str) -> String {
        format!("tasks/{id}")
    }

    /// Run `f` on task `id` under the lock, then update its `~state`
    /// document and publish its (state-only) `~val`.
    async fn with_task<R>(&self, id: &str, f: impl FnOnce(&mut Task) -> R) -> Option<R> {
        let (r, v, doc) = {
            let mut st = self.lock();
            let t = st.tasks.get_mut(id)?;
            let r = f(t);
            (r, t.public_value(), wyrm_core::codec::to_vec(&t.to_value()))
        };
        match doc {
            Ok(doc) => {
                if let Err(e) = self.ctx.set_doc(&Self::task_path(id), "~state", Some(doc)) {
                    debug!("task {id} document: {e}");
                }
            }
            Err(e) => debug!("encode task {id}: {e}"),
        }
        if let Err(e) = self
            .ctx
            .update(&Self::task_path(id), v, Quality::Good, now_us())
            .await
        {
            debug!("publish task {id}: {e}");
        }
        Some(r)
    }

    fn state_of(&self, id: &str) -> Option<TaskState> {
        self.lock().tasks.get(id).map(|t| t.state)
    }
}

pub struct Agent {
    shared: Arc<Shared>,
}

fn secret_key(ctx: &LinkCtx, name: &str) -> Result<Option<SigningKey>> {
    let Some(s) = ctx.secrets().get(name) else {
        return Ok(None);
    };
    let raw = s.expose();
    let bytes: Zeroizing<Vec<u8>> = if raw.len() == 32 {
        Zeroizing::new(raw.to_vec())
    } else {
        let text = std::str::from_utf8(raw)
            .map_err(|_| LinkError::invalid_parameter(format!("secret {name}: bad key")))?;
        Zeroizing::new(
            hex::decode(text.trim())
                .map_err(|_| LinkError::invalid_parameter(format!("secret {name}: bad key")))?,
        )
    };
    let seed: [u8; 32] = bytes
        .as_slice()
        .try_into()
        .map_err(|_| LinkError::invalid_parameter(format!("secret {name}: need 32 bytes")))?;
    Ok(Some(SigningKey::from_bytes(&seed)))
}

fn task_meta() -> NodeMeta {
    let mut m = NodeMeta::leaf(TypeCode::Map);
    m.actions = Some(BTreeMap::from([
        (
            "approve".to_owned(),
            ActionMeta::new()
                .param("approvals", ParamMeta::of(TypeCode::Map).required(true))
                .level(Perm::Config),
        ),
        (
            "reject".to_owned(),
            ActionMeta::new()
                .param("reason", ParamMeta::of(TypeCode::String))
                .level(Perm::Write),
        ),
        ("cancel".to_owned(), ActionMeta::new().level(Perm::Write)),
    ]));
    m
}

/// `allowed_prefixes` as full node keys (invalid entries are dropped).
fn full_prefixes(site: &str, prefixes: &[String]) -> Vec<String> {
    prefixes
        .iter()
        .filter_map(|a| match tools::node_key(site, a) {
            Ok(k) => Some(k),
            Err(e) => {
                warn!("allowed_prefixes: {e}");
                None
            }
        })
        .collect()
}

/// The agent's own token source: subject `ai:<link>`, `max = write`, and
/// grants scoped to what the agent may touch. First matching grant wins at
/// the responder, so the denials come first:
/// - its own subtree and `sys/**`: `none`;
/// - each allowed prefix (`<prefix>/**`): `write`;
/// - `pub/**` (profiles, device-model catalog): `read`.
///
/// Nothing else gets a token, so the agent cannot be used as a deputy for
/// other links, flows or the control plane.
pub fn service_tokens(
    key: SigningKey,
    site: &str,
    link: &str,
    allowed: &[String],
) -> SigningTokens {
    let g = |k: String, p: Perm| Grant { k, p };
    let mut grants = vec![
        g(format!("wy/{site}/down/{link}/**"), Perm::None),
        g(format!("wy/{site}/sys/**"), Perm::None),
    ];
    grants.extend(allowed.iter().map(|a| g(format!("{a}/**"), Perm::Write)));
    grants.push(g(format!("wy/{site}/pub/**"), Perm::Read));
    SigningTokens::new(key, site)
        .subject(format!("ai:{link}"))
        .grants(grants)
        .max(Perm::Write)
}

fn map_value(kv: Vec<(&str, Value)>) -> Value {
    Value::Map(kv.into_iter().map(|(k, v)| (k.to_owned(), v)).collect())
}

/// The asker of a task, or a caller with `config` on the action.
fn may_manage(t: &Task, who: &Caller) -> bool {
    who.perm >= Perm::Config || (who.claims.is_some() && caller_sub(who) == t.owner)
}

fn not_owner() -> LinkError {
    LinkError::new(
        Status::PermissionDenied,
        "only the asker or a config-level caller may do this",
    )
}

fn caller_sub(who: &Caller) -> String {
    who.claims
        .as_ref()
        .map(|c| c.sub.clone())
        .unwrap_or_else(|| "anonymous".into())
}

impl Link for Agent {
    const NAME: &'static str = "agent";
    const VERSION: &'static str = env!("CARGO_PKG_VERSION");
    type Config = AgentConfig;

    async fn start(cfg: AgentConfig, ctx: LinkCtx) -> Result<Self> {
        let params = cfg.params;
        let site = ctx.site().to_owned();
        let llm: Option<Arc<dyn LlmClient>> = match cfg.llm {
            Some(l) => Some(l),
            None => match ctx
                .secrets()
                .get(&params.api_key_ref)
                .and_then(|s| s.expose_str())
            {
                Some(k) => Some(Arc::new(
                    AnthropicClient::new(
                        Zeroizing::new(k.trim().to_owned()),
                        &params.api_base,
                        Duration::from_secs(params.llm_timeout_s),
                        params.fallbacks,
                    )
                    .map_err(LinkError::invalid_parameter)?,
                )),
                None => {
                    warn!(
                        secret = %params.api_key_ref,
                        "no LLM API key: ask is unavailable"
                    );
                    None
                }
            },
        };
        let plain = WyrmClient::new(ctx.client().clone());
        let allowed = full_prefixes(&site, &params.allowed_prefixes);
        let service = secret_key(&ctx, &params.agent_key_ref)?.map(|key| {
            plain
                .clone()
                .with_tokens(Arc::new(service_tokens(key, &site, ctx.link(), &allowed)))
        });
        if service.is_none() {
            warn!(
                secret = %params.agent_key_ref,
                "no agent key: only approved operations can run"
            );
        }
        let reader = service.clone().unwrap_or_else(|| plain.clone());

        // Task records hold model output: restricted (readers need `list`).
        ctx.declare_node("tasks", NodeMeta::folder().cfg("restricted", true))
            .await?;
        let mut root = ctx.meta("").unwrap_or_else(NodeMeta::folder);
        root.children = None;
        root.children_count = None;
        root.rev = None;
        root.cfg = Some(params.cfg_map());
        ctx.declare_node("", root).await?;
        ctx.declare_action(
            "",
            "ask",
            ActionMeta::new()
                .param("task", ParamMeta::of(TypeCode::String).required(true))
                .result(ActionResult::Stream)
                .stream(true)
                .level(Perm::Write)
                .timeout_ms(ASK_TIMEOUT_MS),
        )
        .await?;
        let shared = Arc::new(Shared {
            ctx,
            params: Mutex::new(params),
            llm,
            reader,
            service,
            plain,
            state: Mutex::new(State::default()),
        });
        Ok(Self { shared })
    }

    async fn reconfigure(&mut self, cfg: AgentConfig) -> Result<()> {
        // The LLM client and keys are fixed at start; a change there restarts.
        let old = self.shared.params();
        let p = cfg.params;
        if p.api_key_ref != old.api_key_ref
            || p.agent_key_ref != old.agent_key_ref
            || p.api_base != old.api_base
            || p.fallbacks != old.fallbacks
            || p.llm_timeout_s != old.llm_timeout_s
            || p.allowed_prefixes != old.allowed_prefixes
            || cfg.llm.is_some()
        {
            // The service token's grants follow allowed_prefixes.
            return Err(LinkError::not_supported(
                "reconfigure of keys, endpoint or allowed_prefixes",
            ));
        }
        let mut root = self.shared.ctx.meta("").unwrap_or_else(NodeMeta::folder);
        root.children = None;
        root.children_count = None;
        root.rev = None;
        root.cfg = Some(p.cfg_map());
        *self.shared.params.lock().unwrap_or_else(|e| e.into_inner()) = p;
        self.shared.ctx.declare_node("", root).await
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
            ("", "ask") => self.ask(args, who, out).await,
            (p, a) => {
                let Some(id) = p.strip_prefix("tasks/").filter(|id| !id.contains('/')) else {
                    return Err(LinkError::not_supported(format!("{p} {a}")));
                };
                let id = id.to_owned();
                let r = match a {
                    "approve" => self.approve(&id, args, who).await?,
                    "reject" => self.reject(&id, args, who).await?,
                    "cancel" => self.cancel(&id, who).await?,
                    other => return Err(LinkError::not_supported(other)),
                };
                out.reply(r).await
            }
        }
    }

    async fn stop(&mut self) {
        let st = self.shared.lock();
        for t in st.tasks.values() {
            if let Some(h) = &t.planner {
                h.abort();
            }
        }
    }
}

fn arg<'a>(args: &'a Value, k: &str) -> Option<&'a Value> {
    match args {
        Value::Map(m) => m.get(k),
        _ => None,
    }
}

impl Agent {
    async fn ask(&mut self, args: Value, who: &Caller, out: ReplySink) -> Result<()> {
        let sh = self.shared.clone();
        let Some(llm) = sh.llm.clone() else {
            return Err(LinkError::new(
                Status::NotAvailable,
                "no LLM configured (missing API key secret)",
            ));
        };
        let text = match arg(&args, "task") {
            Some(Value::Str(s)) if !s.trim().is_empty() => s.trim().to_owned(),
            _ => {
                return Err(LinkError::invalid_parameter(
                    "task: non-empty text required",
                ))
            }
        };
        if text.chars().count() > MAX_ASK_CHARS {
            return Err(LinkError::invalid_parameter(format!(
                "task: at most {MAX_ASK_CHARS} characters"
            )));
        }
        let sub = caller_sub(who);
        let budget = sh.params().budget_tokens_day;
        let (id, evict) = {
            let mut st = sh.lock();
            if st.budget.used() >= budget {
                return Err(LinkError::new(
                    Status::RateLimited,
                    "daily token budget exhausted",
                ));
            }
            st.next += 1;
            let secs = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .map(|d| d.as_secs())
                .unwrap_or(0);
            let id = format!("t{secs:x}-{}", st.next);
            // Make room: drop the oldest finished tasks.
            let mut evict = Vec::new();
            while st.order.len() + 1 > MAX_TASKS {
                let Some(pos) = st
                    .order
                    .iter()
                    .position(|i| st.tasks.get(i).is_none_or(|t| t.state.finished()))
                else {
                    break;
                };
                if let Some(old) = st.order.remove(pos) {
                    st.tasks.remove(&old);
                    evict.push(old);
                }
            }
            if st.order.len() >= MAX_TASKS {
                return Err(LinkError::new(Status::Busy, "too many unfinished tasks"));
            }
            st.order.push_back(id.clone());
            st.tasks.insert(
                id.clone(),
                Task {
                    owner: sub.clone(),
                    ask: text.clone(),
                    state: TaskState::Planning,
                    plan: Vec::new(),
                    log: Vec::new(),
                    error: None,
                    tokens: 0,
                    cancel: false,
                    planner: None,
                },
            );
            (id, evict)
        };
        for old in evict {
            if let Err(e) = sh.ctx.remove_node(&Shared::task_path(&old)).await {
                debug!("remove task {old}: {e}");
            }
        }
        sh.ctx
            .declare_node(&Shared::task_path(&id), task_meta())
            .await?;
        sh.with_task(&id, |t| t.push_log(format!("asked by {sub}")))
            .await;
        // The asker may already be gone; planning goes on regardless.
        let _ = out
            .reply(map_value(vec![
                ("task", Value::from(id.as_str())),
                ("state", Value::from("planning")),
            ]))
            .await;
        let h = tokio::spawn(plan_task(sh.clone(), llm, id.clone(), text, out));
        if let Some(t) = sh.lock().tasks.get_mut(&id) {
            t.planner = Some(h.abort_handle());
        }
        Ok(())
    }

    async fn approve(&mut self, id: &str, args: Value, who: &Caller) -> Result<Value> {
        let sh = self.shared.clone();
        let sub = caller_sub(who);
        if sub.starts_with("ai:") || who.claims.is_none() {
            return Err(LinkError::new(
                Status::PermissionDenied,
                "approve needs a human operator",
            ));
        }
        let Some(Value::Map(given)) = arg(&args, "approvals") else {
            return Err(LinkError::invalid_parameter("approvals: map required"));
        };
        let mut toks: BTreeMap<String, Vec<u8>> = BTreeMap::new();
        for (k, v) in given {
            let tok = match v {
                Value::Bytes(b) => b.clone(),
                Value::Str(s) => wyrm_mcp::check::decode_token(s)
                    .map_err(|e| LinkError::invalid_parameter(format!("approvals[{k}]: {e}")))?,
                _ => {
                    return Err(LinkError::invalid_parameter(format!(
                        "approvals[{k}]: base64 text or bytes required"
                    )))
                }
            };
            toks.insert(k.clone(), tok);
        }
        let site = sh.ctx.site().to_owned();
        let policy = sh.policy();
        // Check everything before anything changes; a failure keeps the task
        // in awaiting_approval and sends nothing.
        let per_op = {
            let st = sh.lock();
            let t = st
                .tasks
                .get(id)
                .ok_or_else(|| LinkError::not_found(format!("task {id}")))?;
            if t.state != TaskState::AwaitingApproval {
                return Err(LinkError::invalid_parameter(format!(
                    "task is {}, not awaiting_approval",
                    t.state.name()
                )));
            }
            if let Some(k) = toks.keys().find(|k| {
                !t.plan
                    .iter()
                    .any(|op| op.requires_approval(&policy) && &op.key == *k)
            }) {
                return Err(LinkError::invalid_parameter(format!(
                    "approval for {k}, which is not a plan step that needs one"
                )));
            }
            let mut per_op = Vec::with_capacity(t.plan.len());
            for op in &t.plan {
                if !op.requires_approval(&policy) {
                    per_op.push(None);
                    continue;
                }
                let tok = toks.remove(&op.key).ok_or_else(|| {
                    LinkError::invalid_parameter(format!("missing approval for {}", op.key))
                })?;
                let info = wyrm_mcp::check::precheck_approval(&tok, &op.key, &site, op.level)
                    .map_err(|e| {
                        LinkError::new(Status::PermissionDenied, format!("{}: {e}", op.key))
                    })?;
                if info.sub != sub {
                    return Err(LinkError::new(
                        Status::PermissionDenied,
                        format!(
                            "approval for {} is from {:?}; it must come from the approver {:?}",
                            op.key, info.sub, sub
                        ),
                    ));
                }
                per_op.push(Some(tok));
            }
            per_op
        };
        // Compare-and-set: only one approve can win.
        let won = sh
            .with_task(id, |t| {
                if t.state != TaskState::AwaitingApproval {
                    return false;
                }
                t.state = TaskState::Running;
                t.push_log(format!("approved by {sub}"));
                true
            })
            .await
            .unwrap_or(false);
        if !won {
            return Err(LinkError::invalid_parameter(
                "task is no longer awaiting_approval",
            ));
        }
        tokio::spawn(execute(sh, id.to_owned(), per_op));
        Ok(map_value(vec![
            ("task", Value::from(id)),
            ("state", Value::from("running")),
        ]))
    }

    async fn reject(&mut self, id: &str, args: Value, who: &Caller) -> Result<Value> {
        let sub = caller_sub(who);
        let reason = match arg(&args, "reason") {
            Some(Value::Str(r)) => format!(": {}", truncate(r, 300)),
            _ => String::new(),
        };
        let r = self
            .shared
            .with_task(id, |t| {
                if !may_manage(t, who) {
                    return Err(not_owner());
                }
                if t.state != TaskState::AwaitingApproval {
                    return Err(LinkError::invalid_parameter(format!(
                        "task is {}, not awaiting_approval",
                        t.state.name()
                    )));
                }
                t.fail(format!("rejected by {sub}{reason}"));
                Ok(())
            })
            .await
            .ok_or_else(|| LinkError::not_found(format!("task {id}")))?;
        r?;
        Ok(map_value(vec![
            ("task", Value::from(id)),
            ("state", Value::from("failed")),
        ]))
    }

    async fn cancel(&mut self, id: &str, who: &Caller) -> Result<Value> {
        let sub = caller_sub(who);
        let r = self
            .shared
            .with_task(id, |t| match t.state {
                _ if !may_manage(t, who) => Err(not_owner()),
                TaskState::Planning => {
                    if let Some(h) = t.planner.take() {
                        h.abort();
                    }
                    t.fail(format!("cancelled by {sub}"));
                    Ok(TaskState::Failed)
                }
                TaskState::AwaitingApproval => {
                    t.fail(format!("cancelled by {sub}"));
                    Ok(TaskState::Failed)
                }
                TaskState::Running => {
                    // Checked between operations; one already sent completes.
                    t.cancel = true;
                    t.push_log(format!("cancel requested by {sub}"));
                    Ok(TaskState::Running)
                }
                s => Err(LinkError::invalid_parameter(format!(
                    "task is already {}",
                    s.name()
                ))),
            })
            .await
            .ok_or_else(|| LinkError::not_found(format!("task {id}")))?;
        let state = r?;
        Ok(map_value(vec![
            ("task", Value::from(id)),
            ("state", Value::from(state.name())),
        ]))
    }
}

/// Best-effort progress on the `ask` stream; planning goes on without it.
async fn progress(sink: &mut Option<ReplySink>, id: &str, event: &str, text: &str) {
    if let Some(s) = sink {
        let v = map_value(vec![
            ("task", Value::from(id)),
            ("event", Value::from(event)),
            ("text", Value::from(text)),
        ]);
        if s.reply(v).await.is_err() {
            *sink = None;
        }
    }
}

/// The planning loop of one task, then the decision what happens next.
async fn plan_task(
    sh: Arc<Shared>,
    llm: Arc<dyn LlmClient>,
    id: String,
    text: String,
    out: ReplySink,
) {
    let mut sink = Some(out);
    let r = plan_loop(&sh, llm.as_ref(), &id, &text, &mut sink).await;
    if let Err(e) = r {
        sh.with_task(&id, |t| {
            if t.state == TaskState::Planning {
                t.fail(e.clone());
            }
        })
        .await;
    } else {
        decide(&sh, &id, &mut sink).await;
    }
    let state = sh.state_of(&id).unwrap_or(TaskState::Failed);
    if let Some(s) = sink {
        let _ = s
            .done(Some(map_value(vec![
                ("task", Value::from(id.as_str())),
                ("state", Value::from(state.name())),
            ])))
            .await;
    }
    if state == TaskState::Running {
        execute(sh, id, Vec::new()).await;
    }
}

async fn plan_loop(
    sh: &Shared,
    llm: &dyn LlmClient,
    id: &str,
    text: &str,
    sink: &mut Option<ReplySink>,
) -> std::result::Result<(), String> {
    let params = sh.params();
    let policy = sh.policy();
    let site = sh.ctx.site().to_owned();
    let reader = Reader {
        client: &sh.reader,
        policy: &policy,
        site: &site,
        timeout: Duration::from_secs(5),
    };
    let system = format!(
        "{SYSTEM}\n\nSite: {site}. You may read and change only under: {:?} (and read wy/{site}/pub/**). Approval rule: {}.",
        policy.allowed,
        policy.mode.name()
    );
    let tools = tools::definitions();
    let mut messages = vec![json!({ "role": "user", "content": text })];
    for turn in 0..params.max_turns {
        if sh.state_of(id) != Some(TaskState::Planning) {
            return Ok(());
        }
        if sh.lock().budget.used() >= params.budget_tokens_day {
            return Err("daily token budget exhausted".into());
        }
        let body = json!({
            "model": params.model,
            "max_tokens": params.max_tokens,
            "system": system,
            "tools": tools,
            "messages": messages,
        });
        // Keep the ask stream alive while the model thinks: requesters drop a
        // stream after their idle timeout (wyrm-client default 10 s).
        let call = llm.messages(body);
        tokio::pin!(call);
        let mut tick = tokio::time::interval(KEEPALIVE);
        tick.tick().await;
        let resp = loop {
            tokio::select! {
                r = &mut call => break r,
                _ = tick.tick() => progress(sink, id, "wait", "").await,
            }
        };
        let resp = resp.map_err(|e| format!("LLM: {e}"))?;
        let used = usage_tokens(&resp);
        sh.lock().budget.add(used);
        sh.with_task(id, |t| t.tokens += used).await;
        let content = resp["content"].clone();
        let blocks = content.as_array().cloned().unwrap_or_default();
        for b in &blocks {
            if b["type"] == "text" {
                let s = b["text"].as_str().unwrap_or("").trim();
                if !s.is_empty() {
                    let line = truncate(s, 600);
                    sh.with_task(id, |t| t.push_log(format!("model: {line}")))
                        .await;
                    progress(sink, id, "text", &line).await;
                }
            }
        }
        // Append-only history: the assistant content goes back verbatim.
        messages.push(json!({ "role": "assistant", "content": content }));
        match resp["stop_reason"].as_str().unwrap_or("") {
            "tool_use" => {}
            "end_turn" | "stop_sequence" => return Ok(()),
            "refusal" => return Err("the model declined the task".into()),
            "max_tokens" => return Err("the model ran out of output tokens".into()),
            other => return Err(format!("unexpected stop_reason {other:?}")),
        }
        let mut results = Vec::new();
        for b in blocks.iter().filter(|b| b["type"] == "tool_use") {
            let name = b["name"].as_str().unwrap_or("");
            let input = &b["input"];
            let tool_id = b["id"].clone();
            let r = if name == "propose" {
                propose(sh, &policy, id, input).await
            } else {
                match reader.call(name, input).await {
                    Some(r) => r,
                    None => Err(format!("unknown tool {name:?}")),
                }
            };
            progress(
                sink,
                id,
                "tool",
                &format!("{name}{}", if r.is_err() { " (error)" } else { "" }),
            )
            .await;
            let (text, is_error) = match r {
                Ok(Json::String(s)) => (s, false),
                Ok(j) => (j.to_string(), false),
                Err(e) => (e, true),
            };
            results.push(json!({
                "type": "tool_result",
                "tool_use_id": tool_id,
                "content": truncate(&text, MAX_TOOL_RESULT),
                "is_error": is_error,
            }));
        }
        if results.is_empty() {
            return Err("stop_reason tool_use without tool calls".into());
        }
        messages.push(json!({ "role": "user", "content": results }));
        debug!(task = %id, turn, "planning turn");
    }
    Err(format!("no final answer after {} turns", params.max_turns))
}

async fn propose(
    sh: &Shared,
    policy: &Policy,
    id: &str,
    input: &Json,
) -> std::result::Result<Json, String> {
    if sh
        .lock()
        .tasks
        .get(id)
        .is_some_and(|t| t.plan.len() >= MAX_PLAN)
    {
        return Err(format!("the plan already has {MAX_PLAN} steps"));
    }
    let op = check_proposal(&sh.reader, policy, input).await?;
    // One approval token per request key, and tokens are single-use.
    if sh
        .lock()
        .tasks
        .get(id)
        .is_some_and(|t| t.plan.iter().any(|o| o.key == op.key))
    {
        return Err(format!(
            "the plan already has a step for {}; use one step per key",
            op.key
        ));
    }
    let summary = json!({
        "added": true,
        "key": op.key,
        "level": op.level.name(),
        "requires_approval": op.needs_approval,
    });
    let line = format!("proposed {} {}", op.op.name(), op.key);
    sh.with_task(id, |t| {
        t.push_log(line);
        t.plan.push(op);
    })
    .await;
    Ok(summary)
}

/// After planning: re-check the plan, then `done` (nothing to do),
/// `awaiting_approval` or `running`.
async fn decide(sh: &Shared, id: &str, sink: &mut Option<ReplySink>) {
    let policy = sh.policy();
    let next = sh
        .with_task(id, |t| {
            if t.state != TaskState::Planning {
                return t.state;
            }
            if let Some(e) = t
                .plan
                .iter()
                .find_map(|op| policy.may_touch(&op.node).err())
            {
                t.fail(e);
            } else if t.plan.is_empty() {
                t.push_log("no changes proposed");
                t.state = TaskState::Done;
            } else if t.plan.iter().any(|op| op.requires_approval(&policy)) {
                t.push_log(format!("plan of {} step(s) awaits approval", t.plan.len()));
                t.state = TaskState::AwaitingApproval;
            } else {
                t.push_log("plan needs no approval");
                t.state = TaskState::Running;
            }
            t.planner = None;
            t.state
        })
        .await;
    if let Some(s) = next {
        progress(sink, id, "state", s.name()).await;
    }
}

/// Run the plan. `approvals[i]` is the human token for step `i` (empty:
/// none). A step that needs approval never goes out without one; a step
/// sent with a token is never retried (tokens are single-use).
async fn execute(sh: Arc<Shared>, id: String, approvals: Vec<Option<Vec<u8>>>) {
    let plan = match sh.lock().tasks.get(&id) {
        Some(t) if t.state == TaskState::Running => t.plan.clone(),
        _ => return,
    };
    let policy = sh.policy();
    for (i, op) in plan.iter().enumerate() {
        let cancelled = sh.lock().tasks.get(&id).is_none_or(|t| t.cancel);
        if cancelled {
            sh.with_task(&id, |t| {
                t.fail(format!("cancelled before step {}", i + 1));
            })
            .await;
            return;
        }
        let r = run_op(&sh, &policy, op, approvals.get(i).cloned().flatten()).await;
        let ok = r.is_ok();
        sh.with_task(&id, |t| match r {
            Ok(line) => t.push_log(format!("step {}: {line}", i + 1)),
            Err(e) => t.fail(format!("step {} ({}): {e}", i + 1, op.key)),
        })
        .await;
        if !ok {
            return;
        }
    }
    sh.with_task(&id, |t| {
        if t.state == TaskState::Running {
            t.state = TaskState::Done;
            t.push_log("done");
        }
    })
    .await;
}

async fn run_op(
    sh: &Shared,
    policy: &Policy,
    op: &PlanOp,
    approval: Option<Vec<u8>>,
) -> std::result::Result<String, String> {
    policy.may_touch(&op.node)?;
    let (client, by) = match approval {
        Some(tok) => {
            // Audited as `<human>/ai:<link>`: approved by a person, sent by
            // the agent.
            let origin = wyrm_mcp::check::token_subject(&tok)
                .map(|sub| format!("{sub}/ai:{}", sh.ctx.link()));
            let mut c = sh.plain.clone().with_tokens(Arc::new(OneKey {
                key: op.key.clone(),
                tok,
            }));
            if let Some(o) = origin {
                c = c.with_origin(o);
            }
            (c, "approval")
        }
        None if op.requires_approval(policy) => return Err("no approval for this step".into()),
        None => match &sh.service {
            Some(c) => (c.clone(), "service token"),
            None => return Err("no agent key: cannot send without approval".into()),
        },
    };
    match op.op {
        tools::OpKind::Set => {
            client
                .set(&op.node, op.payload.clone())
                .await
                .map_err(|e| e.to_string())?;
            Ok(format!("set {} ok ({by})", op.key))
        }
        tools::OpKind::Invoke => {
            let action = op.action.as_deref().unwrap_or_default();
            let mut s = client
                .invoke(&op.node, action, op.payload.clone())
                .await
                .map_err(|e| e.to_string())?;
            let mut n = 0usize;
            while let Some(item) = s.next().await {
                item.map_err(|e| e.to_string())?;
                n += 1;
                if n >= MAX_INVOKE_RESULTS {
                    break;
                }
            }
            Ok(format!("invoke {} ok, {n} result(s) ({by})", op.key))
        }
    }
}
