//! AI agent connector (ADR 0005, wiki "AI-агент, MCP і CLI" §2).
//!
//! Tree under `wy/<site>/downstream/<link>`:
//!
//! | key | what |
//! |---|---|
//! | `~meta.cfg` | `model`, `budget_tokens_day`, `allowed_prefixes`, `require_approval`, … |
//! | `budget_used_today` | LLM tokens used this UTC day |
//! | `~act/ask {task, parent?, context?}` | level `write`, stream: creates `tasks/<id>`, streams progress, ends with `{task, state}`; `parent` = a task this one follows (one that waits for a person is replaced by it), `context` = keys the asker attached |
//! | `tasks/<id>/~val` | `{state, step, of, last?: {n, ok, result}, suggestions?, reviewing?, replaced_by?}` (public: numbers, fixed words and task ids only) |
//! | `tasks/<id>/~state` | `{state, owner, ask, plan[], plan_hash, questions[]?, suggestions[]?, parent?, replaced_by?, context[]?, step, log[], error?, review?, reviewing?, tokens}` (restricted: `list`); a suggestion is `{id, label, detail, changes, step?, rows?: [{key, label, detail}]}`; a step is the `wyrm-agent run` step (`{set, value}`, `{invoke, action, args}`, `{wait, timeout_s}`, `{expect, equals \| min/max \| changes, timeout_s}`, `{sleep_s}`) with `n, level, after?, approval, check, warn? (the link's finding), model_warn? (the model's words), reason?, result?: {status: ok \| failed \| skipped, message, time}` |
//! | `tasks/<id>/~act/approve {approvals, plan?}` | level `write`: `approvals` = `{<step number> \| <request key>: <ptok, bytes or base64>}`, one human token per step at the step's level; a step that needs one and gets none is skipped, with the steps that need it; `plan` = the `plan_hash` the approver read |
//! | `tasks/<id>/~act/answer {answers?, text?}` | level `write`, stream like `ask`: `answers` = `{<question id>: [<option id>] \| text}` |
//! | `tasks/<id>/~act/reject`, `cancel` | level `write`; `cancel` also ends the review turn after a stopped run |
//!
//! States: `planning (⇄ awaiting_answer) → awaiting_approval → running → done | failed`
//! (`reject`, `cancel` and a follow-up that replaces the task end in `failed` with `error`).
//!
//! What the model offers to ask next (tool `suggest`) is in `~state.suggestions`: fixes
//! for a step's warning, the same change for more nodes, and, after a run stopped at a
//! step, the ways out the model found in one more read-only turn (`review_turns`).
//! Nothing runs because of a suggestion: the person who picks one sends a follow-up `ask`.
//!
//! Safety does not rest on the model. The model only reads (read-only tools)
//! and proposes; a proposal is checked against `~meta`, `allowed_prefixes`
//! and the level it needs. Execution sends each operation either with the
//! human approval token for exactly its request key (the target link checks
//! the human's rights) or, for write-level operations that need no approval,
//! with the agent's own service token (`ai:<link>`, `max = write`): the agent
//! can never perform a `config` operation by itself.
//!
//! With a `data_dir` (embedded and process links under `wyrmd`), tasks and
//! the daily budget survive a restart (see [`store`]). A task that was
//! `planning` or `running` when the link stopped comes back `failed`
//! ("interrupted by restart") and is never resumed; `awaiting_approval`
//! stays approvable. Without a `data_dir` everything is in memory.

#![forbid(unsafe_code)]

#[cfg(feature = "cli")]
pub mod cli;
pub mod llm;
pub mod store;
pub mod tools;

use crate::llm::{usage_tokens, AnthropicClient, LlmClient};
use crate::store::{AgentStore, TaskRec};
use crate::tools::{
    check_proposal, ApprovalMode, PlanOp, Policy, Reader, StepResult, StepStatus, Suggestion,
};
use ed25519_dalek::SigningKey;
use serde_json::{json, Value as Json};
use std::collections::{BTreeMap, VecDeque};
use std::path::{Path, PathBuf};
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
use wyrm_mcp::json::{meta_to_json, sample_to_json};
use zeroize::Zeroizing;

/// Kept tasks; the oldest finished ones are removed beyond this.
const MAX_TASKS: usize = 200;
/// Finished tasks older than this are removed.
const MAX_TASK_AGE_S: u64 = 30 * 86_400;
/// Error of a task that was planning or running when the link stopped.
pub const INTERRUPTED: &str = "interrupted by restart";
const MAX_LOG: usize = 200;
/// The value under the link's root with the LLM tokens used this UTC day.
const BUDGET_NODE: &str = "budget_used_today";
const MAX_PLAN: usize = 50;
const MAX_ASK_CHARS: usize = 8000;
/// Keys one `ask` may attach (`context`).
const MAX_CONTEXT: usize = 16;
/// Questions the model may ask in one turn, options of one question, questions of a task.
const MAX_QUESTIONS_TURN: usize = 3;
const MAX_OPTIONS: usize = 6;
const MAX_QUESTIONS: usize = 30;
/// Bytes of an answer in the person's own words.
const MAX_ANSWER: usize = 2000;
/// Bytes kept of what the model found after a run stopped (`~state.review`).
const MAX_REVIEW: usize = 600;
/// Tool result text sent back to the model.
const MAX_TOOL_RESULT: usize = 16_000;
/// Most results kept from a streaming action during execution.
const MAX_INVOKE_RESULTS: usize = 100;
/// `ask` stream: longest gap between progress items (one LLM call).
const ASK_TIMEOUT_MS: u32 = 300_000;
/// Progress `wait` items while an LLM call runs.
const KEEPALIVE: Duration = Duration::from_secs(1);

const SYSTEM: &str = "You are the WYRM agent: an operator assistant for an IoT broker with \
IOT-DSA semantics. Node keys are `wy/<site>/downstream/<link>/<path>`; paths may be given relative \
to the site (`downstream/<link>/<path>`). Explore with tree_list, tree_resolve, node_meta and \
value_get; device models are profiles named `<vendor>:<model>` (profiles tool) whose attr holds \
the model data. You cannot change anything yourself: call `propose` once per step. A step that \
changes something is op=set or op=invoke; it is checked and then shown to a human, who approves \
the steps they want. A step left out is skipped, and so is every step that needs it (`after`). \
Prove the plan with steps that only read: op=wait (a node exists), op=expect (a value), \
op=sleep. When the task leaves a real choice open, ask the person with `ask_user` before you \
plan; offer only options you have read in the tree. Propose only what the task needs; read a \
node's ~meta before you propose a change to it. When a step carries a risk you read in the \
tree, say it in the step's `warn` and offer its fixes with `suggest` (`step` = its number). \
When the same change fits more nodes you read, offer them with `suggest` and `rows`. A \
suggestion runs nothing: the person who picks it asks you again. When you are done, answer \
with a short summary of the plan, or of what you found if no change is needed.";

/// The turn after a run stopped at a step: the model reads and offers ways out.
const REVIEW_SYSTEM: &str = "You are the WYRM agent: an operator assistant for an IoT broker \
with IOT-DSA semantics. A plan you wrote was run and stopped at a step. You cannot change \
anything and you cannot plan now. Read what tells why the step failed (tree_list, node_meta, \
value_get), then offer the person at most 3 ways out with `suggest`: `label` as on a button, \
`detail` in one or two sentences, `changes` = how many changes it would take (0: it changes \
nothing, for example leave it as it is or only look further). Offer only what you read in the \
tree. A way out runs nothing: the person who picks it asks you again and approves that plan. \
End with one or two sentences on what you found.";

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
    /// LLM calls of the turn after a run stopped at a step, in which the model reads why
    /// and offers ways out (`suggest`). 0: no such turn.
    pub review_turns: u32,
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
            review_turns: 4,
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
    "review_turns",
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
            review_turns: wyrm_link_sdk::params::narrow(
                f.u64_or("review_turns", d.review_turns.into())?.min(16),
                "review_turns",
            )?,
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
        m.insert("review_turns".into(), Value::UInt(self.review_turns.into()));
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

wyrm_core::wire_enum! {
    /// The states of a task (`tasks/<id>` `~val.state`, by name).
    pub enum TaskState {
        Planning = 0 => "planning",
        AwaitingApproval = 1 => "awaiting_approval",
        Running = 2 => "running",
        Done = 3 => "done",
        Failed = 4 => "failed",
        /// The model asked the person (`ask_user`); `answer` resumes it (ADR 0049 §5).
        AwaitingAnswer = 5 => "awaiting_answer",
    }
}

impl TaskState {
    fn finished(self) -> bool {
        matches!(self, Self::Done | Self::Failed)
    }
}

/// One option of a [`Question`].
#[derive(Debug, Clone, PartialEq)]
pub struct Choice {
    pub id: String,
    pub label: String,
    pub detail: String,
}

/// What the model asked the person (`ask_user`).
#[derive(Debug, Clone, PartialEq)]
pub struct Question {
    /// `q1`, `q2`, …: unique in the task.
    pub id: String,
    pub text: String,
    pub options: Vec<Choice>,
    pub multiple: bool,
    pub free_text: bool,
    /// The picked option ids (an array) or the person's own words (text).
    pub answer: Option<Value>,
}

impl Question {
    pub fn to_value(&self) -> Value {
        let mut m = BTreeMap::new();
        m.insert("id".to_owned(), Value::from(self.id.as_str()));
        m.insert("text".to_owned(), Value::from(self.text.as_str()));
        m.insert(
            "options".to_owned(),
            Value::Array(
                self.options
                    .iter()
                    .map(|o| {
                        map_value(vec![
                            ("id", Value::from(o.id.as_str())),
                            ("label", Value::from(o.label.as_str())),
                            ("detail", Value::from(o.detail.as_str())),
                        ])
                    })
                    .collect(),
            ),
        );
        m.insert("multiple".to_owned(), Value::Bool(self.multiple));
        m.insert("free_text".to_owned(), Value::Bool(self.free_text));
        if let Some(a) = &self.answer {
            m.insert("answer".to_owned(), a.clone());
        }
        Value::Map(m)
    }

    pub fn from_value(v: &Value) -> Option<Self> {
        let Value::Map(m) = v else { return None };
        let s = |m: &BTreeMap<String, Value>, k: &str| match m.get(k) {
            Some(Value::Str(s)) => s.clone(),
            _ => String::new(),
        };
        let options = match m.get("options") {
            Some(Value::Array(a)) => a
                .iter()
                .filter_map(|o| match o {
                    Value::Map(o) => Some(Choice {
                        id: s(o, "id"),
                        label: s(o, "label"),
                        detail: s(o, "detail"),
                    }),
                    _ => None,
                })
                .collect(),
            _ => Vec::new(),
        };
        Some(Self {
            id: s(m, "id"),
            text: s(m, "text"),
            options,
            multiple: matches!(m.get("multiple"), Some(Value::Bool(true))),
            free_text: matches!(m.get("free_text"), Some(Value::Bool(true))),
            answer: m.get("answer").cloned(),
        })
    }
}

/// An answer on its way to the planner: the answers by question id (already in the task's
/// record) and the stream of the `answer` call, which carries the progress from here on.
type Answered = ReplySink;

fn now_s() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
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
    /// Seconds since the Unix epoch.
    created: u64,
    /// Sequence number in the task id.
    seq: u64,
    cancel: bool,
    /// The planning or executing task; aborted by `cancel` (while planning)
    /// and by `stop`.
    worker: Option<tokio::task::AbortHandle>,
    /// What the model asked, in order; the last ones wait while the task is
    /// `awaiting_answer`.
    questions: Vec<Question>,
    /// The task this one follows (`ask {parent}`).
    parent: Option<String>,
    /// Keys the person attached (`ask {context}`).
    context: Vec<String>,
    /// The step that runs or ran last, from 1 (0: none yet).
    step: usize,
    /// The latest finished step: its number and how it ended.
    last: Option<(usize, StepStatus)>,
    /// The planner waits here for `answer`; not persisted (a restart ends the wait).
    answer: Option<tokio::sync::oneshot::Sender<Answered>>,
    /// What the model offers to ask next (`suggest`); bounded, cleared when the task fails.
    suggestions: Vec<Suggestion>,
    /// The follow-up task that took this one's place while it waited for a person.
    replaced_by: Option<String>,
    /// What the model found after the run stopped (its last words of that turn).
    review: Option<String>,
    /// The turn after a stopped run is on; not persisted (a restart ends it).
    reviewing: bool,
    /// The asker's rights (spec 04 `auth`) as their latest call on the task carried them
    /// (`ask`, then their own `answer` or `approve`): what they may read bounds the rows of
    /// a suggestion, and only until that token's `exp` ([`asker_rights`]). `None`: not
    /// known (a token without `auth`, or a restart: not persisted).
    rights: Option<Caller>,
}

impl Task {
    fn to_rec(&self) -> TaskRec {
        TaskRec {
            state: self.state.name().to_owned(),
            owner: self.owner.clone(),
            ask: self.ask.clone(),
            plan: store::encode_plan(
                &self.plan,
                &store::Extras {
                    questions: self.questions.clone(),
                    parent: self.parent.clone(),
                    context: self.context.clone(),
                    suggestions: self.suggestions.clone(),
                    replaced_by: self.replaced_by.clone(),
                    review: self.review.clone(),
                },
            ),
            log: self.log.clone(),
            error: self.error.clone(),
            tokens: self.tokens,
            created: self.created,
            seq: self.seq,
        }
    }

    /// A reloaded record. A task that was `planning` or `running` is not
    /// resumed: it becomes `failed` ([`INTERRUPTED`]). `Err`: unreadable.
    fn from_rec(r: &TaskRec) -> std::result::Result<Self, String> {
        let state = store::state_from_name(&r.state).ok_or("unknown state")?;
        let (plan, extras) = store::decode_plan(&r.plan)?;
        let mut t = Self {
            owner: r.owner.clone(),
            ask: r.ask.clone(),
            state,
            plan,
            questions: extras.questions,
            parent: extras.parent,
            context: extras.context,
            suggestions: extras.suggestions,
            replaced_by: extras.replaced_by,
            review: extras.review,
            reviewing: false,
            rights: None,
            step: 0,
            last: None,
            answer: None,
            log: r.log.clone(),
            error: r.error.clone(),
            tokens: r.tokens,
            created: r.created,
            seq: r.seq,
            cancel: false,
            worker: None,
        };
        // a waiting question cannot be resumed either: the model's turns were in memory
        if matches!(
            state,
            TaskState::Planning | TaskState::Running | TaskState::AwaitingAnswer
        ) {
            t.fail(INTERRUPTED);
        }
        // where the run stood, from the results it left
        if let Some((i, r)) = t
            .plan
            .iter()
            .enumerate()
            .rev()
            .find_map(|(i, op)| op.result.as_ref().map(|r| (i, r)))
        {
            t.step = i + 1;
            t.last = Some((i + 1, r.status));
        }
        Ok(t)
    }

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

    /// The task ends as `failed`. What the model offered while it planned goes with the
    /// plan: fixes and more rows of a plan that did not run through are not offered again
    /// (after a run that stopped at a step, the review offers ways out).
    fn fail(&mut self, e: impl Into<String>) {
        let e = e.into();
        self.push_log(format!("failed: {e}"));
        self.error = Some(e);
        self.state = TaskState::Failed;
        self.suggestions.clear();
    }

    /// Public `~val`: `{state, step, of, last?, suggestions?, reviewing?, replaced_by?}`
    /// (ADR 0049 §7, amendment of 2026-11-14). `suggestions` is their count, `replaced_by`
    /// a task id the link made: a reader learns that the record changed, not what it says. `~val` is broadcast and
    /// answered without a token, to anyone who may read the link, while the record is
    /// restricted. So it holds numbers and the link's own fixed words only: `last` is
    /// `{n, ok, result}` of the latest finished step, `result` one of `ok`, `failed`,
    /// `skipped`. No text of a result, no value read, no node key, no ask, no owner: those
    /// are in `~state`.
    fn public_value(&self) -> Value {
        let mut kv = vec![
            ("state", Value::from(self.state.name())),
            ("step", Value::UInt(self.step as u64)),
            ("of", Value::UInt(self.plan.len() as u64)),
        ];
        if !self.suggestions.is_empty() {
            kv.push(("suggestions", Value::UInt(self.suggestions.len() as u64)));
        }
        if self.reviewing {
            kv.push(("reviewing", Value::Bool(true)));
        }
        if let Some(by) = &self.replaced_by {
            kv.push(("replaced_by", Value::from(by.as_str())));
        }
        if let Some((n, status)) = &self.last {
            kv.push((
                "last",
                map_value(vec![
                    ("n", Value::UInt(*n as u64)),
                    ("ok", Value::Bool(*status != StepStatus::Failed)),
                    ("result", Value::from(status.name())),
                ]),
            ));
        }
        map_value(kv)
    }

    /// The full record, served as the `~state` document of the task node
    /// (restricted: readers need `list` on it). Never holds tokens.
    fn to_value(&self, policy: &Policy) -> Value {
        let mut m = BTreeMap::new();
        m.insert("state".to_owned(), Value::from(self.state.name()));
        m.insert("owner".to_owned(), Value::from(self.owner.as_str()));
        m.insert("ask".to_owned(), Value::from(self.ask.as_str()));
        m.insert(
            "plan".to_owned(),
            Value::Array(
                self.plan
                    .iter()
                    .enumerate()
                    .map(|(i, op)| op.to_value(i + 1, policy))
                    .collect(),
            ),
        );
        if !self.questions.is_empty() {
            m.insert(
                "questions".to_owned(),
                Value::Array(self.questions.iter().map(Question::to_value).collect()),
            );
        }
        if !self.suggestions.is_empty() {
            m.insert(
                "suggestions".to_owned(),
                Value::Array(self.suggestions.iter().map(Suggestion::to_value).collect()),
            );
        }
        if let Some(p) = &self.parent {
            m.insert("parent".to_owned(), Value::from(p.as_str()));
        }
        if let Some(by) = &self.replaced_by {
            m.insert("replaced_by".to_owned(), Value::from(by.as_str()));
        }
        if let Some(r) = &self.review {
            m.insert("review".to_owned(), Value::from(r.as_str()));
        }
        if self.reviewing {
            m.insert("reviewing".to_owned(), Value::Bool(true));
        }
        if !self.context.is_empty() {
            m.insert(
                "context".to_owned(),
                Value::Array(
                    self.context
                        .iter()
                        .map(|k| Value::from(k.as_str()))
                        .collect(),
                ),
            );
        }
        m.insert("step".to_owned(), Value::UInt(self.step as u64));
        // what an approval names (`approve {plan}`): the reader approves this very plan
        m.insert(
            "plan_hash".to_owned(),
            Value::from(tools::plan_hash(&self.plan)),
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
    /// Held by LLM calls in flight ([`Reserved`]); not persisted.
    reserved: u64,
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

    /// Check and reserve in one step: refused at the limit (used plus calls
    /// in flight); otherwise up to `max` tokens (the output cap of one call)
    /// are held until the call is settled. Before the call the hold is
    /// re-sized to its input and output with [`fit`](Self::fit).
    fn reserve(&mut self, limit: u64, max: u64) -> Option<u64> {
        self.roll();
        let committed = self.used.saturating_add(self.reserved);
        if committed >= limit {
            return None;
        }
        let n = max.min(limit - committed).max(1);
        self.reserved += n;
        Some(n)
    }

    /// Re-size a hold of `held` tokens for a call with `input` tokens: all
    /// of the input plus up to `max` output tokens. Returns the output
    /// tokens held; `None` (and nothing held) when the input does not fit.
    fn fit(&mut self, limit: u64, held: u64, input: u64, max: u64) -> Option<u64> {
        self.roll();
        self.reserved = self.reserved.saturating_sub(held);
        let free = limit.saturating_sub(self.used.saturating_add(self.reserved));
        if input >= free {
            return None;
        }
        let out = max.min(free - input);
        self.reserved += input + out;
        Some(out)
    }
}

/// Upper estimate of the input tokens of a request body: one token per
/// three bytes of JSON (tokenizers average about four characters per token).
fn input_estimate(body: &Json) -> u64 {
    (body.to_string().len() as u64).div_ceil(3)
}

#[derive(Default)]
struct State {
    tasks: BTreeMap<String, Task>,
    order: VecDeque<String>,
    budget: Budget,
    next: u64,
    /// Durable copy (with a `data_dir`); taken by `stop`, after which late
    /// updates of leftover tasks stay in memory.
    db: Option<AgentStore>,
    /// The `data_dir` of `db` (for compaction).
    db_dir: Option<PathBuf>,
}

impl State {
    fn persist(&mut self, op: store::Op) {
        let Some(db) = self.db.as_mut() else { return };
        if let Err(e) = db.apply(op) {
            warn!("agent store: {e}");
        }
        if db.lsn() > store::COMPACT_AT {
            self.compact();
        }
    }

    /// Rewrite the store from the current state (the WAL is append-only).
    /// After a failed rewrite the store is opened again as it is on disk.
    fn compact(&mut self) {
        let (Some(db), Some(dir)) = (self.db.take(), self.db_dir.clone()) else {
            return;
        };
        self.db = match store::compact(&dir, db) {
            Ok(db) => Some(db),
            Err(e) => {
                warn!("agent store compaction: {e}");
                store::open(&dir, u64::MAX)
                    .inspect_err(|e| warn!("agent store lost, tasks kept in memory only: {e}"))
                    .ok()
            }
        };
    }

    fn save_task(&mut self, id: &str) {
        if self.db.is_none() {
            return;
        }
        if let Some(rec) = self.tasks.get(id).map(Task::to_rec) {
            self.persist(store::Op::Put(id.to_owned(), rec));
        }
    }

    fn save_budget(&mut self) {
        let (day, used) = (self.budget.day, self.budget.used);
        self.persist(store::Op::Budget { day, used });
    }

    /// Remove finished tasks older than [`MAX_TASK_AGE_S`], then the oldest
    /// finished ones until `room` more fit under [`MAX_TASKS`]. Returns the
    /// removed ids (their nodes are still to be removed).
    fn evict(&mut self, room: usize) -> Vec<String> {
        let cutoff = now_s().saturating_sub(MAX_TASK_AGE_S);
        let mut evict: Vec<String> = self
            .order
            .iter()
            .filter(|i| {
                self.tasks
                    .get(*i)
                    .is_none_or(|t| t.state.finished() && t.created < cutoff)
            })
            .cloned()
            .collect();
        self.order.retain(|i| !evict.contains(i));
        while self.order.len() + room > MAX_TASKS {
            let Some(pos) = self
                .order
                .iter()
                .position(|i| self.tasks.get(i).is_none_or(|t| t.state.finished()))
            else {
                break;
            };
            if let Some(old) = self.order.remove(pos) {
                evict.push(old);
            }
        }
        for old in &evict {
            // a finished task's worker may still run its review: it ends with the task
            if let Some(h) = self.tasks.remove(old).and_then(|t| t.worker) {
                h.abort();
            }
            self.persist(store::Op::Remove(old.clone()));
        }
        evict
    }
}

/// Tokens held for one LLM call; released on drop (an aborted planner),
/// replaced by the real usage on [`settle`](Self::settle).
struct Reserved {
    sh: Arc<Shared>,
    n: u64,
}

impl Reserved {
    /// Hold the input of the call and up to `max` output tokens (see
    /// [`Budget::fit`]); returns the output tokens the call may ask for.
    fn fit(&mut self, limit: u64, input: u64, max: u64) -> Option<u64> {
        let out = self.sh.lock().budget.fit(limit, self.n, input, max);
        self.n = out.map_or(0, |o| input + o);
        out
    }

    fn settle(mut self, used: u64) {
        let mut st = self.sh.lock();
        st.budget.reserved = st.budget.reserved.saturating_sub(self.n);
        self.n = 0;
        st.budget.add(used);
        st.save_budget();
    }
}

impl Drop for Reserved {
    fn drop(&mut self) {
        if self.n > 0 {
            let mut st = self.sh.lock();
            st.budget.reserved = st.budget.reserved.saturating_sub(self.n);
        }
    }
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
    /// document and publish its (state-only) `~val`. The record is persisted
    /// when its state, plan, error or tokens changed (not for every log line).
    async fn with_task<R>(&self, id: &str, f: impl FnOnce(&mut Task) -> R) -> Option<R> {
        self.update_task(id, false, f).await
    }

    /// Like [`with_task`](Self::with_task), and always persisted.
    async fn with_task_saved<R>(&self, id: &str, f: impl FnOnce(&mut Task) -> R) -> Option<R> {
        self.update_task(id, true, f).await
    }

    async fn update_task<R>(
        &self,
        id: &str,
        force: bool,
        f: impl FnOnce(&mut Task) -> R,
    ) -> Option<R> {
        let policy = self.policy();
        let (r, v, doc) = {
            let mut st = self.lock();
            let t = st.tasks.get_mut(id)?;
            let mark = |t: &Task| {
                (
                    t.state,
                    t.plan.len(),
                    t.error.is_some(),
                    t.tokens,
                    t.questions.len(),
                    t.suggestions.len(),
                    t.replaced_by.is_some(),
                    t.review.is_some(),
                )
            };
            let before = mark(t);
            let r = f(t);
            let changed = before != mark(t);
            let out = (
                r,
                t.public_value(),
                wyrm_core::codec::to_vec(&t.to_value(&policy)),
            );
            // Under the lock: records reach the WAL in the order they change.
            if force || changed {
                st.save_task(id);
            }
            out
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

    /// Was `cancel` asked for the running task `id` (or is the task gone)?
    fn cancelled(&self, id: &str) -> bool {
        self.lock().tasks.get(id).is_none_or(|t| t.cancel)
    }

    /// The tokens used today as the value `budget_used_today` (ADR 0049 §10).
    async fn publish_budget(&self) {
        let used = self.lock().budget.used();
        if let Err(e) = self
            .ctx
            .update(BUDGET_NODE, Value::UInt(used), Quality::Good, now_us())
            .await
        {
            debug!("publish {BUDGET_NODE}: {e}");
        }
    }

    fn state_of(&self, id: &str) -> Option<TaskState> {
        self.lock().tasks.get(id).map(|t| t.state)
    }

    /// Reserve budget for the next LLM call (see [`Budget::reserve`]).
    fn reserve(self: &Arc<Self>) -> Option<Reserved> {
        let p = self.params();
        let n = self
            .lock()
            .budget
            .reserve(p.budget_tokens_day, p.max_tokens.into())?;
        Some(Reserved {
            sh: self.clone(),
            n,
        })
    }
}

/// Load the persisted tasks and budget. Tasks that were planning or running
/// become failed (and are saved so); ids keep counting from the highest
/// loaded sequence number.
fn reload(db: AgentStore, dir: &Path) -> State {
    let saved = db.state().clone();
    let mut st = State {
        db: Some(db),
        db_dir: Some(dir.to_owned()),
        ..State::default()
    };
    st.budget.day = saved.day;
    st.budget.used = saved.used;
    let mut loaded: Vec<(String, Task)> = Vec::new();
    for (id, rec) in &saved.tasks {
        match Task::from_rec(rec) {
            Ok(t) => loaded.push((id.clone(), t)),
            Err(e) => {
                warn!(task = %id, "unreadable task record dropped: {e}");
                st.persist(store::Op::Remove(id.clone()));
            }
        }
    }
    loaded.sort_by_key(|(_, t)| (t.created, t.seq));
    for (id, t) in loaded {
        st.next = st.next.max(t.seq);
        let interrupted = store::state_from_name(&saved.tasks[&id].state) != Some(t.state);
        st.order.push_back(id.clone());
        st.tasks.insert(id.clone(), t);
        if interrupted {
            st.save_task(&id);
        }
    }
    st.evict(0);
    st
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
            // `write` on the task: what a person may approve is decided by the tokens, one
            // per step at the level the step needs (ADR 0049 §3)
            ActionMeta::new()
                // Two forms: `approvals` from a caller with its own key, or `steps` from a
                // user of the gateway, which signs them and sends `approvals` (ADR 0049 §2)
                .param("approvals", ParamMeta::of(TypeCode::Map))
                .param("steps", ParamMeta::of(TypeCode::Array))
                .param("plan", ParamMeta::of(TypeCode::String))
                .level(Perm::Write),
        ),
        (
            "answer".to_owned(),
            ActionMeta::new()
                .param("answers", ParamMeta::of(TypeCode::Map))
                .param("text", ParamMeta::of(TypeCode::String))
                .result(ActionResult::Stream)
                .stream(true)
                .level(Perm::Write)
                .timeout_ms(ASK_TIMEOUT_MS),
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
        g(format!("wy/{site}/downstream/{link}/**"), Perm::None),
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

/// The rights of a person a call carries: the caller, when its token has `auth` (spec 04:
/// a token without it means the caller's rights are unknown, and a responder that needs
/// them refuses).
fn asker_rights(who: &Caller) -> Option<Caller> {
    who.claims
        .as_ref()
        .is_some_and(|c| c.auth.is_some())
        .then(|| who.clone())
}

/// Keep the newer rights of the asker of `t` from a call of theirs on the task.
fn renew_rights(t: &mut Task, who: &Caller) {
    if who.claims.is_some() && caller_sub(who) == t.owner {
        if let Some(r) = asker_rights(who) {
            t.rights = Some(r);
        }
    }
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
        // Fail closed: with a data_dir, a store that does not open is an
        // error, not a silent reset of tasks and budget.
        let state = match ctx.data_dir() {
            Some(dir) => reload(
                store::open(dir, store::COMPACT_AT)
                    .map_err(|e| LinkError::internal(format!("agent store: {e}")))?,
                dir,
            ),
            None => State::default(),
        };

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
                .param("parent", ParamMeta::of(TypeCode::String))
                .param("context", ParamMeta::of(TypeCode::Array))
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
            state: Mutex::new(state),
        });
        shared
            .ctx
            .declare_node(BUDGET_NODE, NodeMeta::number().unit("tokens"))
            .await?;
        shared.publish_budget().await;
        let ids: Vec<String> = shared.lock().order.iter().cloned().collect();
        for id in ids {
            shared
                .ctx
                .declare_node(&Shared::task_path(&id), task_meta())
                .await?;
            shared.with_task(&id, |_| ()).await;
        }
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
                if a == "answer" {
                    // a stream, like `ask`: the planner goes on writing to it
                    return self.answer(&id, args, who, out).await;
                }
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
        self.shut();
    }
}

impl Agent {
    /// Abort planning and execution, and release the store (and its lock
    /// file) now: leftover clones of `Shared` must not keep a restarted link
    /// from opening it.
    fn shut(&self) {
        let mut st = self.shared.lock();
        for t in st.tasks.values() {
            if let Some(h) = &t.worker {
                h.abort();
            }
        }
        st.db = None;
    }
}

/// Also when the host aborts the link without `stop` (handle dropped).
impl Drop for Agent {
    fn drop(&mut self) {
        self.shut();
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
                Status::NotSupported,
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
        let params = sh.params();
        let policy = sh.policy();
        // Keys the person attached (ADR 0049 §9): inside what the agent may read, and inside
        // what the asker may read: the model must not read for them what they may not.
        let mut context: Vec<String> = Vec::new();
        match arg(&args, "context") {
            None | Some(Value::Null) => {}
            Some(Value::Array(items)) if !items.is_empty() && asker_rights(who).is_none() => {
                return Err(LinkError::new(
                    Status::PermissionDenied,
                    "context: needs the rights of the asker, a token with `auth` (spec 04)",
                ));
            }
            Some(Value::Array(items)) if items.len() <= MAX_CONTEXT => {
                for i in items {
                    let Value::Str(k) = i else {
                        return Err(LinkError::invalid_parameter("context: node keys"));
                    };
                    let node = policy
                        .node_key(k)
                        .and_then(|n| policy.may_read(&n).map(|()| n))
                        .map_err(|e| LinkError::invalid_parameter(format!("context: {e}")))?;
                    if who.perm_on(&format!("{node}/~val")) < Perm::Read {
                        return Err(LinkError::new(
                            Status::PermissionDenied,
                            format!("context: you may not read {node}"),
                        ));
                    }
                    if !context.contains(&node) {
                        context.push(node);
                    }
                }
            }
            Some(_) => {
                return Err(LinkError::invalid_parameter(format!(
                    "context: an array of at most {MAX_CONTEXT} node keys"
                )))
            }
        }
        let parent = match arg(&args, "parent") {
            None | Some(Value::Null) => None,
            Some(Value::Str(p)) => Some(p.clone()),
            Some(_) => return Err(LinkError::invalid_parameter("parent: a task id")),
        };
        let (id, evict, first, earlier) = {
            let mut st = sh.lock();
            // The task this one follows: the asker of it, or a config caller (as for cancel).
            let earlier = match &parent {
                None => None,
                Some(p) => {
                    let t = st
                        .tasks
                        .get(p)
                        .ok_or_else(|| LinkError::not_found(format!("parent: task {p}")))?;
                    if !may_manage(t, who) {
                        return Err(not_owner());
                    }
                    Some(brief(p, t, &policy))
                }
            };
            // The check and the reservation for the first LLM call are one
            // step: two concurrent asks cannot both pass on the last tokens.
            let committed = st.budget.used().saturating_add(st.budget.reserved);
            if committed >= params.budget_tokens_day {
                return Err(LinkError::new(
                    Status::RateLimited,
                    "daily token budget exhausted",
                ));
            }
            // Make room: drop expired and the oldest finished tasks.
            let evict = st.evict(1);
            if st.order.len() >= MAX_TASKS {
                return Err(LinkError::new(Status::Busy, "too many unfinished tasks"));
            }
            let first = st
                .budget
                .reserve(params.budget_tokens_day, params.max_tokens.into())
                .unwrap_or(0);
            st.next += 1;
            let seq = st.next;
            let created = now_s();
            let id = format!("t{created:x}-{seq}");
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
                    created,
                    seq,
                    cancel: false,
                    worker: None,
                    questions: Vec::new(),
                    parent: parent.clone(),
                    context: context.clone(),
                    step: 0,
                    last: None,
                    answer: None,
                    suggestions: Vec::new(),
                    replaced_by: None,
                    review: None,
                    reviewing: false,
                    rights: asker_rights(who),
                },
            );
            st.save_task(&id);
            // A task that waits for a person is replaced by its follow-up (the asker asked
            // for another plan): it ends here, under the same lock, so the old plan cannot
            // be approved beside the new one. A parent that runs or has ended stays as it
            // is: a follow-up of it replaces nothing.
            let replaced = parent.as_ref().is_some_and(|p| {
                let Some(t) = st.tasks.get_mut(p) else {
                    return false;
                };
                if !matches!(
                    t.state,
                    TaskState::AwaitingApproval | TaskState::AwaitingAnswer
                ) {
                    return false;
                }
                // the planner of a task that waits for an answer waits with it
                if let Some(h) = t.worker.take() {
                    h.abort();
                }
                t.answer = None;
                t.fail(format!("replaced by {id}"));
                t.replaced_by = Some(id.clone());
                true
            });
            if let Some(p) = parent.as_ref().filter(|_| replaced) {
                st.save_task(p);
            }
            (id, evict, first, earlier)
        };
        // the replaced task's record and `~val` say so
        if let Some(p) = &parent {
            sh.with_task(p, |_| ()).await;
        }
        let first = Reserved {
            sh: sh.clone(),
            n: first,
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
        let brief = Brief {
            text,
            earlier,
            context,
        };
        let h = tokio::spawn(plan_task(sh.clone(), llm, id.clone(), brief, out, first));
        if let Some(t) = sh.lock().tasks.get_mut(&id) {
            t.worker = Some(h.abort_handle());
        }
        Ok(())
    }

    /// `answer {answers?, text?}` (ADR 0049 §5): the answers to the questions that wait, by
    /// question id (`[<option id>, …]` or the person's own words), or `text` alone: their
    /// own words for the whole card. The planner goes on, and its progress comes on this
    /// call's stream, as it does on `ask`.
    async fn answer(&mut self, id: &str, args: Value, who: &Caller, out: ReplySink) -> Result<()> {
        let sh = self.shared.clone();
        let sub = caller_sub(who);
        let given = match arg(&args, "answers") {
            None | Some(Value::Null) => BTreeMap::new(),
            Some(Value::Map(m)) => m.clone(),
            Some(_) => return Err(LinkError::invalid_parameter("answers: map required")),
        };
        let words = match arg(&args, "text") {
            None | Some(Value::Null) => None,
            Some(Value::Str(s)) if !s.trim().is_empty() => Some(truncate(s.trim(), MAX_ANSWER)),
            Some(_) => return Err(LinkError::invalid_parameter("text: non-empty text")),
        };
        if given.is_empty() && words.is_none() {
            return Err(LinkError::invalid_parameter("answers or text required"));
        }
        let tx = sh
            .with_task_saved(id, |t| {
                if !may_manage(t, who) {
                    return Err(not_owner());
                }
                if t.state != TaskState::AwaitingAnswer {
                    return Err(LinkError::invalid_parameter(format!(
                        "task is {}, not awaiting_answer",
                        t.state.name()
                    )));
                }
                // Checked whole before anything is kept.
                let mut checked: Vec<(usize, Value)> = Vec::new();
                for (qid, a) in &given {
                    let Some(i) = t
                        .questions
                        .iter()
                        .position(|q| &q.id == qid && q.answer.is_none())
                    else {
                        return Err(LinkError::invalid_parameter(format!(
                            "answers: {qid} is not a question that waits"
                        )));
                    };
                    checked.push((i, check_answer(&t.questions[i], a)?));
                }
                let Some(tx) = t.answer.take() else {
                    return Err(LinkError::internal(
                        "the task does not wait for an answer any more",
                    ));
                };
                for (i, a) in checked {
                    t.questions[i].answer = Some(a);
                }
                // a question left open gets the person's own words, or no answer
                for q in t.questions.iter_mut().filter(|q| q.answer.is_none()) {
                    q.answer = Some(match &words {
                        Some(w) => Value::from(w.as_str()),
                        None => Value::Array(Vec::new()),
                    });
                }
                t.state = TaskState::Planning;
                renew_rights(t, who);
                t.push_log(format!("answered by {sub}"));
                Ok(tx)
            })
            .await
            .ok_or_else(|| LinkError::not_found(format!("task {id}")))??;
        let _ = out
            .reply(map_value(vec![
                ("task", Value::from(id)),
                ("state", Value::from("planning")),
            ]))
            .await;
        if tx.send(out).is_err() {
            // the planner is gone (the link is stopping)
            sh.with_task(id, |t| t.fail(INTERRUPTED)).await;
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
            // `steps` alone is the form of a gateway user: the gateway makes `approvals`
            // of it. Here it came from a caller no gateway signs for.
            return Err(LinkError::invalid_parameter(
                if arg(&args, "steps").is_some() {
                    "steps: only a gateway signs the steps of its user; a caller with its \
                     own key sends approvals {<step>: <ptok>}"
                } else {
                    "approvals: map required"
                },
            ));
        };
        let mut toks: Vec<(String, Vec<u8>)> = Vec::new();
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
            toks.push((k.clone(), tok));
        }
        if toks.is_empty() {
            return Err(LinkError::invalid_parameter(
                "approvals: no step is approved (reject the plan instead)",
            ));
        }
        // The plan the approver read (`~state.plan_hash`); checked under the lock below.
        let seen = match arg(&args, "plan") {
            None | Some(Value::Null) => None,
            Some(Value::Str(h)) => Some(h.clone()),
            Some(_) => return Err(LinkError::invalid_parameter("plan: text required")),
        };
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
            if let Some(by) = &t.replaced_by {
                return Err(LinkError::invalid_parameter(format!(
                    "task was replaced by {by}: its plan is no longer approved; approve that task"
                )));
            }
            if t.state != TaskState::AwaitingApproval {
                return Err(LinkError::invalid_parameter(format!(
                    "task is {}, not awaiting_approval",
                    t.state.name()
                )));
            }
            if seen
                .as_ref()
                .is_some_and(|h| *h != tools::plan_hash(&t.plan))
            {
                return Err(LinkError::invalid_parameter(
                    "plan: the plan is not the one this approval was made for; read it again",
                ));
            }
            // `approve` is `write` on the task (ADR 0049 §3), so the caller may be a stranger
            // to it. The asker, or a caller with `config` on the link, decides for the task:
            // steps that need no human run with the agent's key, as they would have without
            // an approval. Anybody else decides only for what they sign: every step that
            // changes something needs their own token, and one without it is skipped, never
            // run with the agent's key on their word.
            let manages = may_manage(t, who);
            let needs_token =
                |op: &PlanOp| op.op.changes() && (!manages || op.requires_approval(&policy));
            // An approval names its step by number (ADR 0049 §4), or by request key when
            // one step alone has that key.
            let mut by_step: BTreeMap<usize, Vec<u8>> = BTreeMap::new();
            for (k, tok) in toks {
                let n = step_named(&t.plan, &k).map_err(LinkError::invalid_parameter)?;
                // a token for a step that needs none is taken: the step then runs with it
                if !t.plan[n - 1].op.changes() {
                    return Err(LinkError::invalid_parameter(format!(
                        "step {n} ({k}) sends nothing: it takes no approval"
                    )));
                }
                if by_step.insert(n, tok).is_some() {
                    return Err(LinkError::invalid_parameter(format!(
                        "step {n} is approved twice"
                    )));
                }
            }
            // The steps left out, and those that need one of them, do not run.
            let unapproved: Vec<usize> = (1..=t.plan.len())
                .filter(|n| needs_token(&t.plan[n - 1]) && !by_step.contains_key(n))
                .collect();
            let skip = tools::skipped(&t.plan, &unapproved);
            let mut per_op = Vec::with_capacity(t.plan.len());
            for (i, op) in t.plan.iter().enumerate() {
                let n = i + 1;
                let tok = by_step.remove(&n);
                if let Some(dep) = skip.get(&n) {
                    if tok.is_some() {
                        return Err(LinkError::invalid_parameter(format!(
                            "step {n} needs step {dep}, which is not approved"
                        )));
                    }
                    per_op.push(Approval::Skip(if *dep == n {
                        format!("skipped by {sub}")
                    } else {
                        format!("skipped: needs step {dep}")
                    }));
                    continue;
                }
                let Some(tok) = tok else {
                    per_op.push(Approval::NotNeeded);
                    continue;
                };
                // The plan's arguments were stored at `propose` and run from there. An
                // approval bound to arguments (claim `args`) must be bound to these: found
                // here, before anything runs, not at the step.
                let payload = match token_binds_args(&tok) {
                    true => Some(op.request_payload().map_err(LinkError::internal)?),
                    false => None,
                };
                let info = wyrm_mcp::check::precheck_approval(
                    &tok,
                    &op.key,
                    &site,
                    op.level,
                    payload.as_deref(),
                )
                .map_err(|e| {
                    LinkError::new(
                        Status::PermissionDenied,
                        format!("step {n} ({}): {e}", op.key),
                    )
                })?;
                if info.sub != sub {
                    return Err(LinkError::new(
                        Status::PermissionDenied,
                        format!(
                            "approval for step {n} is from {:?}; it must come from the approver {:?}",
                            info.sub, sub
                        ),
                    ));
                }
                // The token was made now and the step is sent after the waits before it:
                // one that cannot live that long is refused here, while the person can
                // still leave the step for a follow-up.
                let waits = tools::waits_before(&t.plan, n, |k| skip.contains_key(&k));
                if waits > 0.0 && waits + tools::APPROVAL_MARGIN_S > info.expires_in_s as f64 {
                    return Err(LinkError::invalid_parameter(format!(
                        "step {n} may be sent {waits} s after this approval (the waits before \
                         it), and its approval is good for {} s: leave it out and ask for it \
                         as a follow-up when this plan is done",
                        info.expires_in_s
                    )));
                }
                per_op.push(Approval::Token(tok));
            }
            per_op
        };
        let skipped = per_op
            .iter()
            .filter(|a| matches!(a, Approval::Skip(_)))
            .count();
        // Compare-and-set: only one approve can win.
        let won = sh
            .with_task(id, |t| {
                if t.state != TaskState::AwaitingApproval {
                    return false;
                }
                t.state = TaskState::Running;
                renew_rights(t, who);
                t.push_log(match skipped {
                    0 => format!("approved by {sub}"),
                    n => format!("approved by {sub}, {n} step(s) left out"),
                });
                true
            })
            .await
            .unwrap_or(false);
        if !won {
            return Err(LinkError::invalid_parameter(
                "task is no longer awaiting_approval",
            ));
        }
        let h = tokio::spawn(execute(sh.clone(), id.to_owned(), per_op));
        if let Some(t) = sh.lock().tasks.get_mut(id) {
            t.worker = Some(h.abort_handle());
        }
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
                TaskState::Planning | TaskState::AwaitingAnswer => {
                    if let Some(h) = t.worker.take() {
                        h.abort();
                    }
                    t.answer = None;
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
                // the turn after a stopped run: it ends, the task stays failed
                TaskState::Failed if t.reviewing => {
                    if let Some(h) = t.worker.take() {
                        h.abort();
                    }
                    t.reviewing = false;
                    t.push_log(format!("review cancelled by {sub}"));
                    Ok(TaskState::Failed)
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

/// What a task starts from: the ask, the task it follows, and the keys the person attached.
struct Brief {
    text: String,
    /// The parent task in short ([`brief`]).
    earlier: Option<String>,
    context: Vec<String>,
}

/// A task for the model of a follow-up ask (ADR 0049 §9): its ask, state, plan with the
/// results, and error. Bounded; the plan is the model's own earlier output and tree text.
fn brief(id: &str, t: &Task, policy: &Policy) -> String {
    let plan: Vec<Json> = t
        .plan
        .iter()
        .enumerate()
        .map(|(i, op)| wyrm_mcp::json::value_to_json(&op.to_value(i + 1, policy)))
        .collect();
    // what the model offered there: the person may have picked one of them
    let offered: Vec<Json> = t
        .suggestions
        .iter()
        .map(|s| wyrm_mcp::json::value_to_json(&s.to_value()))
        .collect();
    let j = json!({
        "task": id,
        "ask": t.ask,
        "state": t.state.name(),
        "plan": plan,
        "error": t.error,
        "suggestions": offered,
    });
    truncate(&j.to_string(), MAX_TOOL_RESULT)
}

/// The step an approval names: its number (`"3"`), or its request key when one step alone
/// has that key.
fn step_named(plan: &[PlanOp], k: &str) -> std::result::Result<usize, String> {
    if let Ok(n) = k.parse::<usize>() {
        return if (1..=plan.len()).contains(&n) {
            Ok(n)
        } else {
            Err(format!("approvals: the plan has no step {n}"))
        };
    }
    let mut hits = plan
        .iter()
        .enumerate()
        .filter(|(_, op)| op.op.changes() && op.key == k)
        .map(|(i, _)| i + 1);
    match (hits.next(), hits.next()) {
        (Some(n), None) => Ok(n),
        (Some(_), Some(_)) => Err(format!(
            "approvals: {k} is the key of several steps; name them by number"
        )),
        _ => Err(format!("approvals: {k} is not a plan step")),
    }
}

/// An answer to `q` as it is kept: the picked option ids, or the person's own words.
fn check_answer(q: &Question, a: &Value) -> Result<Value> {
    match a {
        Value::Str(s) if q.free_text && !s.trim().is_empty() => {
            Ok(Value::from(truncate(s.trim(), MAX_ANSWER)))
        }
        Value::Str(_) => Err(LinkError::invalid_parameter(format!(
            "answers.{}: pick one of its options",
            q.id
        ))),
        Value::Array(ids) => {
            let mut picked: Vec<Value> = Vec::new();
            for i in ids {
                match i {
                    Value::Str(o) if q.options.iter().any(|c| &c.id == o) => {
                        if !picked.contains(i) {
                            picked.push(i.clone());
                        }
                    }
                    _ => {
                        return Err(LinkError::invalid_parameter(format!(
                            "answers.{}: not one of its options",
                            q.id
                        )))
                    }
                }
            }
            if picked.is_empty() || (picked.len() > 1 && !q.multiple) {
                return Err(LinkError::invalid_parameter(format!(
                    "answers.{}: {} expected",
                    q.id,
                    if q.multiple {
                        "one option or more"
                    } else {
                        "one option"
                    }
                )));
            }
            Ok(Value::Array(picked))
        }
        _ => Err(LinkError::invalid_parameter(format!(
            "answers.{}: option ids or text",
            q.id
        ))),
    }
}

/// The answer to `q` as the model gets it: the labels of the picked options, or the words.
fn answer_text(q: &Question) -> String {
    match &q.answer {
        Some(Value::Str(s)) => s.clone(),
        Some(Value::Array(ids)) if !ids.is_empty() => ids
            .iter()
            .filter_map(|i| match i {
                Value::Str(i) => q.options.iter().find(|o| &o.id == i),
                _ => None,
            })
            .map(|o| format!("{} ({})", o.label, o.id))
            .collect::<Vec<_>>()
            .join("; "),
        _ => "(no answer)".to_owned(),
    }
}

/// A question of the model (`ask_user`) as a [`Question`] without its id.
fn question_of(input: &Json) -> std::result::Result<Question, String> {
    let text = input["question"].as_str().unwrap_or("").trim();
    if text.is_empty() {
        return Err("`question` (text) is required".into());
    }
    let mut options: Vec<Choice> = Vec::new();
    for o in input["options"]
        .as_array()
        .map(Vec::as_slice)
        .unwrap_or(&[])
    {
        let id = o["id"].as_str().unwrap_or("").trim();
        let label = o["label"].as_str().unwrap_or("").trim();
        if id.is_empty() || label.is_empty() {
            return Err("every option needs `id` and `label`".into());
        }
        if options.iter().any(|c| c.id == id) {
            return Err(format!("option id {id:?} is used twice"));
        }
        options.push(Choice {
            id: truncate(id, 64),
            label: truncate(label, 200),
            detail: truncate(o["detail"].as_str().unwrap_or("").trim(), 300),
        });
    }
    if options.len() > MAX_OPTIONS {
        return Err(format!("at most {MAX_OPTIONS} options"));
    }
    Ok(Question {
        id: String::new(),
        text: truncate(text, 500),
        // with nothing to pick, the person can only write
        free_text: input["free_text"].as_bool().unwrap_or(false) || options.is_empty(),
        multiple: input["multiple"].as_bool().unwrap_or(false),
        options,
        answer: None,
    })
}

/// The planning loop of one task, then the decision what happens next.
async fn plan_task(
    sh: Arc<Shared>,
    llm: Arc<dyn LlmClient>,
    id: String,
    brief: Brief,
    out: ReplySink,
    first: Reserved,
) {
    let mut sink = Some(out);
    let r = plan_loop(&sh, llm.as_ref(), &id, brief, &mut sink, first).await;
    if let Err(e) = r {
        sh.with_task(&id, |t| {
            if matches!(t.state, TaskState::Planning | TaskState::AwaitingAnswer) {
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

/// The first message of a task: the ask, then the task it follows and what the person
/// attached, each read now (`context` keys were checked against the asker's rights).
async fn first_message(reader: &Reader<'_>, brief: &Brief) -> String {
    let mut m = brief.text.clone();
    if let Some(e) = &brief.earlier {
        m.push_str("\n\nThis follows an earlier task (its ask, plan with results, error):\n");
        m.push_str(e);
    }
    if !brief.context.is_empty() {
        m.push_str("\n\nThe person attached these nodes (read them first):");
        for k in &brief.context {
            let meta = match reader.client.meta(k).await {
                Ok(meta) => meta_to_json(&meta).to_string(),
                Err(e) => format!("{{\"error\": {:?}}}", e.to_string()),
            };
            let val = match reader.read_val(k).await {
                Ok(s) => sample_to_json(&s).to_string(),
                Err(_) => "null".to_owned(),
            };
            m.push_str(&format!(
                "\n- {k}: meta {} value {}",
                truncate(&meta, 2000),
                truncate(&val, 500)
            ));
        }
    }
    m
}

/// One call of the model for task `id`: the tokens of the call are held and then charged,
/// the stream (when there is one) is kept alive while the model thinks, and the model's
/// words go to the task's log and the stream.
async fn model_turn(
    sh: &Arc<Shared>,
    llm: &dyn LlmClient,
    id: &str,
    params: &AgentParams,
    mut body: Json,
    mut reserved: Reserved,
    sink: &mut Option<ReplySink>,
) -> std::result::Result<Json, String> {
    // The input is held as well, and the call asks for no more output
    // than is left: it overruns the budget only by the estimate's error.
    let Some(out) = reserved.fit(
        params.budget_tokens_day,
        input_estimate(&body),
        params.max_tokens.into(),
    ) else {
        return Err("daily token budget exhausted (the next request does not fit)".into());
    };
    body["max_tokens"] = out.into();
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
    let resp = match resp {
        Ok(r) => r,
        Err(e) => {
            // No usage reported: nothing is charged.
            reserved.settle(0);
            return Err(format!("LLM: {e}"));
        }
    };
    let used = usage_tokens(&resp);
    reserved.settle(used);
    sh.publish_budget().await;
    sh.with_task(id, |t| t.tokens += used).await;
    for b in resp["content"].as_array().map(Vec::as_slice).unwrap_or(&[]) {
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
    Ok(resp)
}

async fn plan_loop(
    sh: &Arc<Shared>,
    llm: &dyn LlmClient,
    id: &str,
    brief: Brief,
    sink: &mut Option<ReplySink>,
    first: Reserved,
) -> std::result::Result<(), String> {
    let mut first = Some(first).filter(|r| r.n > 0);
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
    let mut messages =
        vec![json!({ "role": "user", "content": first_message(&reader, &brief).await })];
    for turn in 0..params.max_turns {
        if sh.state_of(id) != Some(TaskState::Planning) {
            return Ok(());
        }
        let Some(reserved) = first.take().or_else(|| sh.reserve()) else {
            return Err("daily token budget exhausted".into());
        };
        let body = json!({
            "model": params.model,
            "system": system,
            "tools": tools,
            "messages": messages,
        });
        let resp = model_turn(sh, llm, id, &params, body, reserved, sink).await?;
        let content = resp["content"].clone();
        let blocks = content.as_array().cloned().unwrap_or_default();
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
        // the questions of this turn: (tool call, question id)
        let mut asked: Vec<(Json, String)> = Vec::new();
        for b in blocks.iter().filter(|b| b["type"] == "tool_use") {
            let name = b["name"].as_str().unwrap_or("");
            let input = &b["input"];
            let tool_id = b["id"].clone();
            let r = if name == "propose" {
                propose(sh, &policy, id, input).await
            } else if name == "suggest" {
                suggest(sh, &policy, id, input).await
            } else if name == "ask_user" {
                match ask_user(sh, id, input, asked.len()).await {
                    Ok(q) => {
                        progress(sink, id, "question", &q.text).await;
                        asked.push((tool_id, q.id));
                        // its result is the person's answer, below
                        continue;
                    }
                    Err(e) => Err(e),
                }
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
        if !asked.is_empty() {
            // The task waits for the person. The stream that brought the ask ends here;
            // the stream of `answer` carries the progress from then on.
            let (tx, rx) = tokio::sync::oneshot::channel();
            let n = asked.len();
            let waits = sh
                .with_task_saved(id, |t| {
                    if t.state != TaskState::Planning {
                        return false;
                    }
                    t.state = TaskState::AwaitingAnswer;
                    t.answer = Some(tx);
                    t.push_log(format!("asked {n} question(s)"));
                    true
                })
                .await
                .unwrap_or(false);
            if !waits {
                return Ok(());
            }
            progress(sink, id, "state", TaskState::AwaitingAnswer.name()).await;
            if let Some(s) = sink.take() {
                let _ = s
                    .done(Some(map_value(vec![
                        ("task", Value::from(id)),
                        ("state", Value::from(TaskState::AwaitingAnswer.name())),
                    ])))
                    .await;
            }
            // cancelled, or the link stops: the sender is dropped
            let Ok(answered) = rx.await else {
                return Ok(());
            };
            *sink = Some(answered);
            for (tool_id, qid) in asked {
                let text = sh
                    .lock()
                    .tasks
                    .get(id)
                    .and_then(|t| t.questions.iter().find(|q| q.id == qid).map(answer_text))
                    .unwrap_or_else(|| "(no answer)".to_owned());
                results.push(json!({
                    "type": "tool_result",
                    "tool_use_id": tool_id,
                    "content": truncate(&text, MAX_TOOL_RESULT),
                    "is_error": false,
                }));
            }
        }
        if results.is_empty() {
            return Err("stop_reason tool_use without tool calls".into());
        }
        messages.push(json!({ "role": "user", "content": results }));
        debug!(task = %id, turn, "planning turn");
    }
    Err(format!("no final answer after {} turns", params.max_turns))
}

/// `ask_user`: one more question of this turn (`so_far` asked before it).
async fn ask_user(
    sh: &Shared,
    id: &str,
    input: &Json,
    so_far: usize,
) -> std::result::Result<Question, String> {
    if so_far >= MAX_QUESTIONS_TURN {
        return Err(format!(
            "at most {MAX_QUESTIONS_TURN} questions in one turn"
        ));
    }
    let mut q = question_of(input)?;
    sh.with_task_saved(id, |t| {
        if t.questions.len() >= MAX_QUESTIONS {
            return Err(format!("this task already asked {MAX_QUESTIONS} questions"));
        }
        q.id = format!("q{}", t.questions.len() + 1);
        t.questions.push(q.clone());
        Ok(q)
    })
    .await
    .unwrap_or_else(|| Err("the task is gone".to_owned()))
}

async fn propose(
    sh: &Shared,
    policy: &Policy,
    id: &str,
    input: &Json,
) -> std::result::Result<Json, String> {
    let plan = match sh.lock().tasks.get(id) {
        Some(t) if t.plan.len() >= MAX_PLAN => {
            return Err(format!("the plan already has {MAX_PLAN} steps"))
        }
        Some(t) => t.plan.clone(),
        None => return Err("the task is gone".into()),
    };
    let op = check_proposal(&sh.reader, policy, &plan, input).await?;
    let n = plan.len() + 1;
    // ADR 0049 §8: how far the step was checked, and what the person must see
    let mut answer = json!({
        "ok": true,
        "n": n,
        "check": op.check.name(),
        "level": op.level.name(),
        "requires_approval": op.requires_approval(policy),
        "after": op.after,
    });
    if let Some(w) = &op.warn {
        answer["warn"] = w.as_str().into();
    }
    let line = format!("proposed {}", op.describe());
    sh.with_task(id, |t| {
        t.push_log(line);
        t.plan.push(op);
    })
    .await;
    Ok(answer)
}

/// `suggest`: one more thing the person may ask next (see [`Suggestion`]). Bounded, and its
/// rows are nodes the asker of the task may read.
async fn suggest(
    sh: &Shared,
    policy: &Policy,
    id: &str,
    input: &Json,
) -> std::result::Result<Json, String> {
    let (steps, rights) = match sh.lock().tasks.get(id) {
        Some(t) => (t.plan.len(), t.rights.clone()),
        None => return Err("the task is gone".into()),
    };
    // The asker's rights while their token lives: a row is never checked against rights
    // that are unknown (no `auth`, a restart) or past their `exp` (fail closed).
    let now = now_s();
    let live = rights.filter(|who| who.claims.as_ref().is_some_and(|c| now < c.exp));
    let has_rows = matches!(input.get("rows"), Some(Json::Array(a)) if !a.is_empty());
    if has_rows && live.is_none() {
        return Err(
            "`rows` need the rights of the task's asker, and they are not known now \
                    (their token had no `auth`, has expired, or the link restarted): offer it \
                    without rows"
                .into(),
        );
    }
    let mut s = tools::suggestion_of(input, policy, steps, |node| {
        live.as_ref()
            .is_some_and(|who| who.perm_on(&format!("{node}/~val")) >= Perm::Read)
    })?;
    sh.with_task_saved(id, |t| {
        if t.suggestions.len() >= tools::MAX_SUGGESTIONS {
            return Err(format!(
                "this task already holds {} suggestions",
                tools::MAX_SUGGESTIONS
            ));
        }
        s.id = format!("s{}", t.suggestions.len() + 1);
        t.push_log(format!("suggested {}", s.id));
        t.suggestions.push(s.clone());
        Ok(json!({"ok": true, "id": s.id}))
    })
    .await
    .unwrap_or_else(|| Err("the task is gone".to_owned()))
}

/// After a run stopped at a step: one bounded turn in which the model reads why and offers
/// ways out (`suggest`). It plans nothing and asks nobody; the task stays `failed`, and
/// what the model found is `~state.review`. Skipped without a model, with `review_turns`
/// 0, and after a cancel. A failure of the turn itself is a log line: the run's own error
/// stays the task's error.
async fn review(sh: &Arc<Shared>, id: &str) {
    let params = sh.params();
    let Some(llm) = sh.llm.clone().filter(|_| params.review_turns > 0) else {
        return;
    };
    let started = sh
        .with_task(id, |t| {
            if t.state != TaskState::Failed || t.cancel {
                return false;
            }
            t.reviewing = true;
            true
        })
        .await
        .unwrap_or(false);
    if !started {
        return;
    }
    let r = review_loop(sh, llm.as_ref(), id, &params).await;
    sh.with_task_saved(id, |t| {
        t.reviewing = false;
        match r {
            Ok(found) => t.review = found.map(|f| truncate(&f, MAX_REVIEW)),
            Err(e) => t.push_log(format!("review: {e}")),
        }
    })
    .await;
}

async fn review_loop(
    sh: &Arc<Shared>,
    llm: &dyn LlmClient,
    id: &str,
    params: &AgentParams,
) -> std::result::Result<Option<String>, String> {
    let policy = sh.policy();
    let site = sh.ctx.site().to_owned();
    let reader = Reader {
        client: &sh.reader,
        policy: &policy,
        site: &site,
        timeout: Duration::from_secs(5),
    };
    let about = match sh.lock().tasks.get(id) {
        Some(t) => brief(id, t, &policy),
        None => return Ok(None),
    };
    let system = format!(
        "{REVIEW_SYSTEM}\n\nSite: {site}. You may read only under: {:?} (and wy/{site}/pub/**).",
        policy.allowed
    );
    let tools = tools::review_definitions();
    let mut messages = vec![json!({
        "role": "user",
        "content": format!("The run of this task stopped (its ask, plan with results, error):\n{about}"),
    })];
    let mut found: Option<String> = None;
    let mut sink = None;
    for _ in 0..params.review_turns {
        let Some(reserved) = sh.reserve() else {
            return Err("daily token budget exhausted".into());
        };
        let body = json!({
            "model": params.model,
            "system": system,
            "tools": tools,
            "messages": messages,
        });
        let resp = model_turn(sh, llm, id, params, body, reserved, &mut sink).await?;
        let content = resp["content"].clone();
        let blocks = content.as_array().cloned().unwrap_or_default();
        let said: Vec<&str> = blocks
            .iter()
            .filter(|b| b["type"] == "text")
            .filter_map(|b| b["text"].as_str())
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .collect();
        if !said.is_empty() {
            found = Some(said.join(" "));
        }
        messages.push(json!({ "role": "assistant", "content": content }));
        match resp["stop_reason"].as_str().unwrap_or("") {
            "tool_use" => {}
            "end_turn" | "stop_sequence" => return Ok(found),
            other => return Err(format!("the model stopped with {other:?}")),
        }
        let mut results = Vec::new();
        for b in blocks.iter().filter(|b| b["type"] == "tool_use") {
            let name = b["name"].as_str().unwrap_or("");
            let r = if name == "suggest" {
                suggest(sh, &policy, id, &b["input"]).await
            } else if name == "propose" || name == "ask_user" {
                Err(format!("{name} is not available after a run"))
            } else {
                match reader.call(name, &b["input"]).await {
                    Some(r) => r,
                    None => Err(format!("unknown tool {name:?}")),
                }
            };
            let (text, is_error) = match r {
                Ok(Json::String(s)) => (s, false),
                Ok(j) => (j.to_string(), false),
                Err(e) => (e, true),
            };
            results.push(json!({
                "type": "tool_result",
                "tool_use_id": b["id"],
                "content": truncate(&text, MAX_TOOL_RESULT),
                "is_error": is_error,
            }));
        }
        if results.is_empty() {
            return Err("stop_reason tool_use without tool calls".into());
        }
        messages.push(json!({ "role": "user", "content": results }));
    }
    // out of turns: what was offered so far stays
    Ok(found)
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
                .filter(|op| op.op.changes())
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
            t.state
        })
        .await;
    if let Some(s) = next {
        progress(sink, id, "state", s.name()).await;
    }
}

/// What `approve` decided for one step of the plan.
enum Approval {
    /// The step runs without a human token: with the agent's own key, or it only reads.
    NotNeeded,
    /// The human token for exactly this step.
    Token(Vec<u8>),
    /// The step is never sent, and why: the approver left it out, or it needs a step that
    /// was left out.
    Skip(String),
}

/// Does an approval carry the `args` claim (spec 04: good for one request body only)?
fn token_binds_args(tok: &[u8]) -> bool {
    wyrm_core::ptok::split(tok)
        .and_then(|p| wyrm_core::codec::from_slice::<wyrm_core::ptok::PtokClaims>(p.claims).ok())
        .is_some_and(|c| c.args.is_some())
}

fn step_result(status: StepStatus, message: impl Into<String>) -> Option<StepResult> {
    Some(StepResult {
        status,
        message: truncate(&message.into(), 500),
        time: now_s(),
    })
}

/// Run the plan. `approvals[i]` is what `approve` decided for step `i`
/// (empty: no step needs a human). A step that needs approval never goes out
/// without a token; one that was left out, or needs one that was, is recorded
/// as skipped and the run goes on; a step sent with a token is never retried
/// (tokens are single-use). Every step the run reaches gets its `result`, and
/// the task's `~val` says where the run is (`step`, `of`, `last`).
async fn execute(sh: Arc<Shared>, id: String, approvals: Vec<Approval>) {
    let mut approvals = approvals.into_iter();
    let plan = match sh.lock().tasks.get(&id) {
        Some(t) if t.state == TaskState::Running => t.plan.clone(),
        _ => return,
    };
    let policy = sh.policy();
    for (i, op) in plan.iter().enumerate() {
        let n = i + 1;
        if sh.cancelled(&id) {
            sh.with_task(&id, |t| {
                t.fail(format!("cancelled before step {n}"));
            })
            .await;
            return;
        }
        let token = match approvals.next().unwrap_or(Approval::NotNeeded) {
            Approval::Skip(why) => {
                sh.with_task_saved(&id, |t| {
                    t.push_log(format!("step {n}: {why}"));
                    t.step = n;
                    t.last = Some((n, StepStatus::Skipped));
                    if let Some(s) = t.plan.get_mut(i) {
                        s.result = step_result(StepStatus::Skipped, why);
                    }
                })
                .await;
                continue;
            }
            Approval::Token(tok) => Some(tok),
            Approval::NotNeeded => None,
        };
        sh.with_task(&id, |t| t.step = n).await;
        let r = run_op(&sh, &policy, &id, op, token).await;
        let ok = r.is_ok();
        // Saved: a reader after a restart sees which steps went out.
        sh.with_task_saved(&id, |t| {
            let (status, text) = match &r {
                Ok(line) => (StepStatus::Ok, line.as_str()),
                Err(e) => (StepStatus::Failed, e.as_str()),
            };
            t.last = Some((n, status));
            if let Some(s) = t.plan.get_mut(i) {
                s.result = step_result(status, text);
            }
            match r {
                Ok(line) => t.push_log(format!("step {n}: {line}")),
                Err(e) => t.fail(format!("step {n} ({}): {e}", op.describe())),
            }
        })
        .await;
        if !ok {
            // the run stopped at this step: the model reads why and offers ways out
            review(&sh, &id).await;
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

/// A step proposed before its node existed (`check: at_run`), checked now against the live
/// `~meta` as `propose` checks: the request is the one that was approved, so a node that
/// asks for a higher level, or for other arguments, stops the step before it is sent.
async fn check_at_run(
    sh: &Shared,
    policy: &Policy,
    op: &PlanOp,
) -> std::result::Result<(), String> {
    let meta = sh
        .reader
        .meta_expanded(&op.node)
        .await
        .map_err(|e| format!("{}: {e}", op.node))?;
    let check = wyrm_mcp::check::is_control_plane(&policy.site, &op.node);
    let need = match &op.action {
        None => {
            wyrm_mcp::check::validate_value(&meta, &op.payload)?;
            wyrm_mcp::check::set_level(&meta)?
        }
        Some(a) => {
            let params = meta
                .actions
                .as_ref()
                .and_then(|acts| acts.get(a))
                .map(|act| act.params.clone())
                .unwrap_or_default();
            let given = match &op.payload {
                Value::Map(m) => m.clone(),
                _ => BTreeMap::new(),
            };
            if Value::Map(wyrm_mcp::check::prepare_args(&params, given)?) != op.payload {
                return Err(
                    "the action takes these arguments in another form; plan it again".into(),
                );
            }
            wyrm_mcp::check::action_level(&meta, a)?
        }
    };
    let need = if check { Perm::Config } else { need };
    if need > op.level {
        return Err(format!(
            "the node asks {} for this; the step was planned at {}",
            need.name(),
            op.level.name()
        ));
    }
    Ok(())
}

/// Does `v` pass the test of an `expect` step? `first` is the first value seen (`changes`).
fn passes(test: &Value, v: &Value, first: &Value) -> bool {
    let Value::Map(t) = test else { return true };
    if let Some(want) = t.get("equals") {
        return v == want || (v.as_f64().is_some() && v.as_f64() == want.as_f64());
    }
    if t.contains_key("changes") {
        return v != first;
    }
    if t.contains_key("min") || t.contains_key("max") {
        let bound = |k: &str| t.get(k).and_then(Value::as_f64);
        return v.as_f64().is_some_and(|x| {
            bound("min").is_none_or(|lo| x >= lo) && bound("max").is_none_or(|hi| x <= hi)
        });
    }
    true
}

/// A proof step (`wait`, `expect`, `sleep`): reads only, with the agent's reader, inside
/// what the model may read. Polled, so `cancel` ends it within a moment.
async fn run_proof(
    sh: &Shared,
    policy: &Policy,
    id: &str,
    op: &PlanOp,
) -> std::result::Result<String, String> {
    const POLL: Duration = Duration::from_millis(250);
    let secs = op.seconds.unwrap_or(0.0).clamp(0.0, tools::MAX_STEP_WAIT_S);
    let end = tokio::time::Instant::now() + Duration::from_secs_f64(secs);
    let left = || tokio::time::Instant::now() < end;
    if op.op == tools::OpKind::Sleep {
        while left() {
            if sh.cancelled(id) {
                return Err("cancelled".into());
            }
            tokio::time::sleep(POLL.min(end - tokio::time::Instant::now())).await;
        }
        return Ok(format!("slept {secs} s"));
    }
    policy.may_read(&op.node)?;
    let site = sh.ctx.site().to_owned();
    let reader = Reader {
        client: &sh.reader,
        policy,
        site: &site,
        timeout: Duration::from_secs(2),
    };
    let mut first: Option<Value> = None;
    let mut last = "nothing".to_owned();
    loop {
        if sh.cancelled(id) {
            return Err("cancelled".into());
        }
        match op.op {
            tools::OpKind::Wait => {
                if sh
                    .reader
                    .meta(&op.node)
                    .await
                    .is_ok_and(|m| m != NodeMeta::default())
                {
                    return Ok(format!("{} is there", op.node));
                }
            }
            _ => {
                if let Ok(s) = reader.read_val(&op.node).await {
                    let seen = first.get_or_insert_with(|| s.v.clone());
                    last = truncate(&wyrm_mcp::json::value_to_json(&s.v).to_string(), 120);
                    if passes(&op.payload, &s.v, seen) {
                        return Ok(format!("{} is {last}", op.node));
                    }
                }
            }
        }
        if !left() {
            return Err(match op.op {
                tools::OpKind::Wait => format!("{}: not there after {secs} s", op.node),
                _ => format!("{}: not as expected after {secs} s (last {last})", op.node),
            });
        }
        tokio::time::sleep(POLL).await;
    }
}

async fn run_op(
    sh: &Shared,
    policy: &Policy,
    id: &str,
    op: &PlanOp,
    approval: Option<Vec<u8>>,
) -> std::result::Result<String, String> {
    if !op.op.changes() {
        return run_proof(sh, policy, id, op).await;
    }
    policy.may_touch(&op.node)?;
    if op.check == tools::Check::AtRun {
        check_at_run(sh, policy, op).await?;
    }
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
        _ => {
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

#[cfg(test)]
mod tests {
    use super::*;

    fn rec(state: TaskState) -> TaskRec {
        TaskRec {
            state: state.name().to_owned(),
            owner: "user:op".into(),
            ask: "x".into(),
            plan: Vec::new(),
            log: Vec::new(),
            error: None,
            tokens: 3,
            created: 1,
            seq: 4,
        }
    }

    /// What `approve` says of itself is what its callers send: a client that checks
    /// arguments against `~meta` takes the form of a gateway user and the form of a caller
    /// with its own key (review of ADR 0049: `approvals` was required, `steps` unknown).
    #[test]
    fn the_meta_of_approve_takes_both_forms() {
        let meta = task_meta();
        let approve = &meta.actions.as_ref().unwrap()["approve"];
        assert_eq!(approve.level, Some(Perm::Write));
        let args = |kv: Vec<(&str, Value)>| -> BTreeMap<String, Value> {
            kv.into_iter().map(|(k, v)| (k.to_owned(), v)).collect()
        };
        for form in [
            args(vec![
                ("steps", Value::Array(vec![Value::UInt(1)])),
                ("plan", Value::from("h")),
            ]),
            args(vec![("approvals", Value::Map(BTreeMap::new()))]),
        ] {
            let r = wyrm_mcp::check::prepare_args(&approve.params, form.clone());
            assert_eq!(r, Ok(form));
        }
    }

    #[test]
    fn interrupted_tasks_fail_and_others_keep_their_state() {
        for s in [TaskState::Planning, TaskState::Running] {
            let t = Task::from_rec(&rec(s)).unwrap();
            assert_eq!(t.state, TaskState::Failed);
            assert_eq!(t.error.as_deref(), Some(INTERRUPTED));
        }
        for s in [
            TaskState::AwaitingApproval,
            TaskState::Done,
            TaskState::Failed,
        ] {
            let t = Task::from_rec(&rec(s)).unwrap();
            assert_eq!(t.state, s);
            assert_eq!(t.error, None);
        }
    }

    #[test]
    fn reservation_is_checked_and_held_in_one_step() {
        let mut b = Budget::default();
        assert_eq!(b.reserve(100, 16_000), Some(100));
        assert_eq!(b.reserve(100, 16_000), None, "in-flight calls count");
        b.reserved = 0;
        b.add(60);
        assert_eq!(b.reserve(100, 16_000), Some(40));
        // Re-sized to input plus output; nothing held when the input does
        // not fit.
        assert_eq!(b.fit(100, 40, 30, 16_000), Some(10));
        assert_eq!(b.reserved, 40);
        assert_eq!(b.fit(100, 40, 40, 16_000), None);
        assert_eq!(b.reserved, 0);
        assert_eq!(b.fit(100, 0, 5, 20), Some(20));
        assert!(input_estimate(&json!({"a": "x".repeat(300)})) >= 100);
    }

    #[test]
    fn eviction_drops_expired_and_oldest_finished() {
        let mut st = State::default();
        let add = |id: &str, state: TaskState, created: u64, st: &mut State| {
            let mut t = Task::from_rec(&rec(state)).unwrap();
            t.created = created;
            st.order.push_back(id.to_owned());
            st.tasks.insert(id.to_owned(), t);
        };
        add("old-done", TaskState::Done, 1, &mut st);
        add("old-waiting", TaskState::AwaitingApproval, 1, &mut st);
        add("new-done", TaskState::Done, now_s(), &mut st);
        assert_eq!(st.evict(0), vec!["old-done".to_owned()]);
        for i in 0..MAX_TASKS {
            add(
                &format!("w{i}"),
                TaskState::AwaitingApproval,
                now_s(),
                &mut st,
            );
        }
        assert_eq!(st.evict(0), vec!["new-done".to_owned()]);
        assert!(st.tasks.contains_key("old-waiting"));
    }

    /// An evicted task's worker (a review still running after its run stopped) ends with it.
    #[tokio::test]
    async fn eviction_ends_a_review_that_still_runs() {
        let mut st = State::default();
        let mut t = Task::from_rec(&rec(TaskState::Failed)).unwrap();
        t.created = 1;
        t.reviewing = true;
        let review = tokio::spawn(std::future::pending::<()>());
        t.worker = Some(review.abort_handle());
        st.order.push_back("old-failed".to_owned());
        st.tasks.insert("old-failed".to_owned(), t);
        assert_eq!(st.evict(0), vec!["old-failed".to_owned()]);
        let e = tokio::time::timeout(Duration::from_secs(5), review)
            .await
            .expect("the review still runs")
            .unwrap_err();
        assert!(e.is_cancelled(), "{e}");
    }
}
