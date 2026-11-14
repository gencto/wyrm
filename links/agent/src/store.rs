//! Durable state of the agent link (principle 3: the connector owns it):
//! task records and the daily token budget in a `wyrm-state` store under the
//! link's private `data_dir`.
//!
//! ```text
//! <data_dir>/agent.key     32-byte HMAC key of the WAL chain (hex, 0600), created once
//! <data_dir>/agent/        the store (WAL + snapshot)
//! <data_dir>/agent.next/   compaction in progress (see `open`)
//! ```
//!
//! Records hold what a task shows (`state, owner, ask, plan, log, error,
//! tokens`), never approval tokens. The WAL is append-only, so `open`
//! rewrites the store from its current state once it holds more than
//! [`COMPACT_AT`] records (at start and while running, see [`compact`]):
//! removed tasks then also leave the disk.

use crate::tools::{Check, OpKind, PlanOp, StepResult, Suggestion};
use crate::{Question, TaskState};
use minicbor::{Decode, Encode};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use wyrm_core::{Perm, Value};
use wyrm_state::Store;
use zeroize::Zeroizing;

/// Rewrite the store once its WAL holds more records than this.
pub const COMPACT_AT: u64 = 10_000;

pub type Error = Box<dyn std::error::Error + Send + Sync>;

/// One task as persisted.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Encode, Decode)]
pub struct TaskRec {
    /// [`TaskState::name`].
    #[n(0)]
    pub state: String,
    #[n(1)]
    pub owner: String,
    #[n(2)]
    pub ask: String,
    /// Canonical CBOR of the plan (see [`encode_plan`]).
    #[n(3)]
    #[cbor(with = "minicbor::bytes")]
    pub plan: Vec<u8>,
    #[n(4)]
    pub log: Vec<String>,
    #[n(5)]
    pub error: Option<String>,
    #[n(6)]
    pub tokens: u64,
    /// Seconds since the Unix epoch.
    #[n(7)]
    pub created: u64,
    /// Sequence number of the task id (`t<secs>-<seq>`).
    #[n(8)]
    pub seq: u64,
}

/// The persisted state. Values are `Arc`s: the store clones the state on
/// every operation.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct Saved {
    pub tasks: BTreeMap<String, Arc<TaskRec>>,
    /// UTC day (days since the epoch) of `used`.
    pub day: u64,
    pub used: u64,
}

#[derive(Debug, Encode, Decode)]
pub enum Op {
    #[n(0)]
    Put(#[n(0)] String, #[n(1)] TaskRec),
    /// Removal of an unknown id is not an error (idempotent replay).
    #[n(1)]
    Remove(#[n(0)] String),
    /// Absolute budget usage of `day`.
    #[n(2)]
    Budget {
        #[n(0)]
        day: u64,
        #[n(1)]
        used: u64,
    },
}

impl wyrm_state::State for Saved {
    const SCHEMA: u32 = 1;
    type Op = Op;

    fn apply(&mut self, op: &Op) -> Result<(), String> {
        match op {
            Op::Put(id, rec) => {
                self.tasks.insert(id.clone(), Arc::new(rec.clone()));
            }
            Op::Remove(id) => {
                self.tasks.remove(id);
            }
            Op::Budget { day, used } => {
                self.day = *day;
                self.used = *used;
            }
        }
        Ok(())
    }
}

pub type AgentStore = Store<Saved>;

/// Load the 32-byte key file, or create it (random, 0600).
pub fn load_or_create_key(path: &Path) -> Result<Zeroizing<Vec<u8>>, Error> {
    if let Ok(text) = std::fs::read_to_string(path) {
        let text = Zeroizing::new(text);
        let k = Zeroizing::new(hex::decode(text.trim())?);
        if k.len() != 32 {
            return Err(format!("{}: expected 32 bytes", path.display()).into());
        }
        return Ok(k);
    }
    let mut k = Zeroizing::new(vec![0u8; 32]);
    getrandom::fill(&mut k).map_err(|e| format!("no randomness: {e}"))?;
    let tmp = path.with_extension("tmp");
    let _ = std::fs::remove_file(&tmp);
    {
        let mut opts = std::fs::OpenOptions::new();
        opts.write(true).create_new(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            opts.mode(0o600);
        }
        let mut f = opts.open(&tmp)?;
        f.write_all(Zeroizing::new(hex::encode(&*k)).as_bytes())?;
        f.sync_all()?;
    }
    std::fs::rename(&tmp, path)?;
    Ok(k)
}

fn sibling(dir: &Path, ext: &str) -> PathBuf {
    let mut s = dir.as_os_str().to_owned();
    s.push(ext);
    PathBuf::from(s)
}

/// Open the store in `data_dir/agent` (key `data_dir/agent.key`) and compact
/// it when its WAL is longer than `compact_at` records.
pub fn open(data_dir: &Path, compact_at: u64) -> Result<AgentStore, Error> {
    std::fs::create_dir_all(data_dir)?;
    let key = load_or_create_key(&data_dir.join("agent.key"))?;
    let dir = data_dir.join("agent");
    let next = sibling(&dir, ".next");
    let old = sibling(&dir, ".old");
    // An interrupted swap: `agent.next` is complete once `agent` was moved.
    if !dir.exists() && next.exists() {
        std::fs::rename(&next, &dir)?;
    }
    for d in [&next, &old] {
        if d.exists() {
            std::fs::remove_dir_all(d)?;
        }
    }
    let store = Store::<Saved>::open(&dir, &key)?;
    if store.lsn() <= compact_at {
        return Ok(store);
    }
    compact(data_dir, store)
}

/// Rewrite `store` (the one in `data_dir/agent`) from its current state and
/// reopen it: the history of removed tasks leaves the disk. On an error the
/// store is closed; [`open`] then finds the old or the complete new copy.
pub fn compact(data_dir: &Path, store: AgentStore) -> Result<AgentStore, Error> {
    let key = load_or_create_key(&data_dir.join("agent.key"))?;
    let dir = data_dir.join("agent");
    let next = sibling(&dir, ".next");
    let old = sibling(&dir, ".old");
    if next.exists() {
        std::fs::remove_dir_all(&next)?;
    }
    let state = store.state().clone();
    {
        let mut fresh = Store::<Saved>::open(&next, &key)?;
        for (id, rec) in &state.tasks {
            fresh.apply(Op::Put(id.clone(), (**rec).clone()))?;
        }
        if state.used > 0 {
            fresh.apply(Op::Budget {
                day: state.day,
                used: state.used,
            })?;
        }
    }
    drop(store);
    std::fs::rename(&dir, &old)?;
    std::fs::rename(&next, &dir)?;
    std::fs::remove_dir_all(&old)?;
    tracing::info!(dir = %dir.display(), tasks = state.tasks.len(), "agent store compacted");
    Ok(Store::<Saved>::open(&dir, &key)?)
}

fn plan_op_value(op: &PlanOp) -> Value {
    let mut m = BTreeMap::new();
    m.insert("op".to_owned(), Value::from(op.op.name()));
    m.insert("node".to_owned(), Value::from(op.node.as_str()));
    m.insert("key".to_owned(), Value::from(op.key.as_str()));
    if let Some(a) = &op.action {
        m.insert("action".to_owned(), Value::from(a.as_str()));
    }
    m.insert("payload".to_owned(), op.payload.clone());
    m.insert("level".to_owned(), Value::UInt(op.level.code().into()));
    m.insert("approval".to_owned(), Value::Bool(op.needs_approval));
    if let Some(r) = &op.reason {
        m.insert("reason".to_owned(), Value::from(r.as_str()));
    }
    // The keys below are absent in records written before ADR 0049: read with defaults.
    if let Some(r) = &op.result {
        m.insert("result".to_owned(), r.to_value());
    }
    if let Some(s) = op.seconds {
        m.insert("seconds".to_owned(), Value::Float(s));
    }
    if op.check != Check::Now {
        m.insert("check".to_owned(), Value::from(op.check.name()));
    }
    if let Some(w) = &op.warn {
        m.insert("warn".to_owned(), Value::from(w.as_str()));
    }
    if !op.after.is_empty() {
        m.insert(
            "after".to_owned(),
            Value::Array(op.after.iter().map(|a| Value::UInt(*a as u64)).collect()),
        );
    }
    Value::Map(m)
}

/// What a task holds beside its plan (ADR 0049). It is kept inside the record's `plan`
/// bytes, so the record itself keeps the shape older snapshots were written with.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Extras {
    pub questions: Vec<Question>,
    pub parent: Option<String>,
    pub context: Vec<String>,
    /// What the model offers to ask next (absent in records written before 2026-11-14).
    pub suggestions: Vec<Suggestion>,
    /// The follow-up task that took this one's place.
    pub replaced_by: Option<String>,
    /// What the model found after the run stopped.
    pub review: Option<String>,
}

impl Extras {
    fn is_empty(&self) -> bool {
        self.questions.is_empty()
            && self.parent.is_none()
            && self.context.is_empty()
            && self.suggestions.is_empty()
            && self.replaced_by.is_none()
            && self.review.is_none()
    }
}

/// The plan as persisted: the array of its steps, or, with [`Extras`], a map
/// `{steps, questions?, parent?, context?, suggestions?, replaced_by?, review?}`.
pub fn encode_plan(plan: &[PlanOp], extras: &Extras) -> Vec<u8> {
    let steps = Value::Array(plan.iter().map(plan_op_value).collect());
    let v = if extras.is_empty() {
        steps
    } else {
        let mut m = BTreeMap::from([("steps".to_owned(), steps)]);
        if !extras.questions.is_empty() {
            m.insert(
                "questions".to_owned(),
                Value::Array(extras.questions.iter().map(Question::to_value).collect()),
            );
        }
        if let Some(p) = &extras.parent {
            m.insert("parent".to_owned(), Value::from(p.as_str()));
        }
        if !extras.context.is_empty() {
            m.insert(
                "context".to_owned(),
                Value::Array(
                    extras
                        .context
                        .iter()
                        .map(|k| Value::from(k.as_str()))
                        .collect(),
                ),
            );
        }
        if !extras.suggestions.is_empty() {
            m.insert(
                "suggestions".to_owned(),
                Value::Array(
                    extras
                        .suggestions
                        .iter()
                        .map(Suggestion::to_value)
                        .collect(),
                ),
            );
        }
        if let Some(by) = &extras.replaced_by {
            m.insert("replaced_by".to_owned(), Value::from(by.as_str()));
        }
        if let Some(r) = &extras.review {
            m.insert("review".to_owned(), Value::from(r.as_str()));
        }
        Value::Map(m)
    };
    wyrm_core::codec::to_vec(&v).unwrap_or_default()
}

pub fn decode_plan(b: &[u8]) -> Result<(Vec<PlanOp>, Extras), String> {
    if b.is_empty() {
        return Ok((Vec::new(), Extras::default()));
    }
    let v: Value = wyrm_core::codec::from_slice(b).map_err(|e| format!("plan: {e}"))?;
    let steps = |items: &[Value]| {
        items
            .iter()
            .map(plan_op_from)
            .collect::<Result<Vec<_>, _>>()
    };
    match v {
        // a record written before ADR 0049
        Value::Array(items) => Ok((steps(&items)?, Extras::default())),
        Value::Map(m) => {
            let plan = match m.get("steps") {
                Some(Value::Array(items)) => steps(items)?,
                _ => return Err("plan: no steps".into()),
            };
            let texts = |k: &str| match m.get(k) {
                Some(Value::Array(a)) => a
                    .iter()
                    .filter_map(|v| match v {
                        Value::Str(s) => Some(s.clone()),
                        _ => None,
                    })
                    .collect(),
                _ => Vec::new(),
            };
            let text = |k: &str| match m.get(k) {
                Some(Value::Str(p)) => Some(p.clone()),
                _ => None,
            };
            let extras = Extras {
                questions: match m.get("questions") {
                    Some(Value::Array(a)) => a.iter().filter_map(Question::from_value).collect(),
                    _ => Vec::new(),
                },
                parent: text("parent"),
                context: texts("context"),
                suggestions: match m.get("suggestions") {
                    Some(Value::Array(a)) => a.iter().filter_map(Suggestion::from_value).collect(),
                    _ => Vec::new(),
                },
                replaced_by: text("replaced_by"),
                review: text("review"),
            };
            Ok((plan, extras))
        }
        _ => Err("plan: not an array".into()),
    }
}

fn plan_op_from(v: &Value) -> Result<PlanOp, String> {
    let Value::Map(m) = v else {
        return Err("plan step: not a map".into());
    };
    let s = |k: &str| match m.get(k) {
        Some(Value::Str(s)) => Ok(s.clone()),
        _ => Err(format!("plan step: {k} missing")),
    };
    let op = s("op")?;
    let op = OpKind::from_name(&op).ok_or_else(|| format!("plan step: op {op:?}"))?;
    let level = match m.get("level") {
        Some(Value::UInt(c)) => u8::try_from(*c)
            .ok()
            .and_then(|c| Perm::try_from(c).ok())
            .ok_or("plan step: bad level")?,
        _ => return Err("plan step: level missing".into()),
    };
    Ok(PlanOp {
        op,
        node: s("node")?,
        key: s("key")?,
        action: s("action").ok(),
        payload: m.get("payload").cloned().unwrap_or(Value::Null),
        level,
        needs_approval: matches!(m.get("approval"), Some(Value::Bool(true))),
        reason: s("reason").ok(),
        result: m.get("result").and_then(StepResult::from_value),
        seconds: m.get("seconds").and_then(Value::as_f64),
        check: Check::from_name(&s("check").unwrap_or_default()),
        warn: s("warn").ok(),
        after: match m.get("after") {
            Some(Value::Array(a)) => a
                .iter()
                .filter_map(|n| match n {
                    Value::UInt(n) => usize::try_from(*n).ok(),
                    _ => None,
                })
                .collect(),
            _ => Vec::new(),
        },
    })
}

pub fn state_from_name(n: &str) -> Option<TaskState> {
    TaskState::ALL.iter().copied().find(|s| s.name() == n)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tmp(name: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!(
            "wyrm-agent-store-{name}-{}-{:?}",
            std::process::id(),
            std::time::SystemTime::now()
        ));
        let _ = std::fs::remove_dir_all(&d);
        d
    }

    fn rec(seq: u64) -> TaskRec {
        TaskRec {
            state: "done".into(),
            owner: "user:op".into(),
            ask: "x".into(),
            plan: encode_plan(
                &[PlanOp {
                    op: OpKind::Invoke,
                    node: "wy/s/downstream/m/p".into(),
                    key: "wy/s/downstream/m/p/~act/go".into(),
                    action: Some("go".into()),
                    payload: Value::Map(BTreeMap::from([("a".to_owned(), Value::UInt(1))])),
                    level: Perm::Config,
                    needs_approval: true,
                    reason: Some("why".into()),
                    result: Some(StepResult {
                        status: crate::tools::StepStatus::Skipped,
                        message: "not approved".into(),
                        time: 7,
                    }),
                    seconds: None,
                    check: Check::AtRun,
                    warn: Some("at the limit".into()),
                    after: vec![1],
                }],
                &Extras::default(),
            ),
            log: vec!["l".into()],
            error: None,
            tokens: 5,
            created: 1,
            seq,
        }
    }

    #[test]
    fn plan_round_trip() {
        let r = rec(1);
        let (p, extras) = decode_plan(&r.plan).unwrap();
        assert_eq!(extras, Extras::default());
        assert_eq!(p.len(), 1);
        assert_eq!(p[0].op, OpKind::Invoke);
        assert_eq!(p[0].action.as_deref(), Some("go"));
        assert_eq!(p[0].level, Perm::Config);
        assert!(p[0].needs_approval);
        assert_eq!(
            p[0].result.as_ref().map(|r| r.status),
            Some(crate::tools::StepStatus::Skipped)
        );
        assert_eq!(
            (p[0].check, p[0].after.as_slice()),
            (Check::AtRun, &[1][..])
        );
        assert_eq!(encode_plan(&p, &extras), r.plan);
        // questions, the parent and the context travel inside the plan bytes
        let more = Extras {
            questions: vec![Question {
                id: "q1".into(),
                text: "which unit?".into(),
                options: vec![crate::Choice {
                    id: "a".into(),
                    label: "unit 3".into(),
                    detail: "behind tcp-line2".into(),
                }],
                multiple: false,
                free_text: true,
                answer: Some(Value::Array(vec![Value::from("a")])),
            }],
            parent: Some("t1-1".into()),
            context: vec!["wy/s/downstream/m".into()],
            suggestions: vec![Suggestion {
                id: "s1".into(),
                label: "Try slave id 4".into(),
                detail: "3 is used by ahu-old".into(),
                changes: 1,
                step: Some(1),
                rows: vec![crate::tools::Row {
                    key: "wy/s/downstream/m/u4".into(),
                    label: "unit 4".into(),
                    detail: String::new(),
                }],
            }],
            replaced_by: Some("t1-3".into()),
            review: Some("the device does not answer".into()),
        };
        let (q, back) = decode_plan(&encode_plan(&p, &more)).unwrap();
        assert_eq!((q.len(), back), (1, more.clone()));
        // a record written before the suggestions (questions, parent, context only) reads
        // with none, not replaced, no review
        let before = Extras {
            suggestions: Vec::new(),
            replaced_by: None,
            review: None,
            ..more
        };
        let (_, back) = decode_plan(&encode_plan(&p, &before)).unwrap();
        assert_eq!(back, before);
        // a record written before ADR 0049 (no result, check, warn, after, seconds) still reads
        let old = Value::Array(vec![Value::Map(BTreeMap::from([
            ("op".to_owned(), Value::from("set")),
            ("node".to_owned(), Value::from("wy/s/downstream/m/p")),
            ("key".to_owned(), Value::from("wy/s/downstream/m/p/~set")),
            ("payload".to_owned(), Value::Float(1.0)),
            ("level".to_owned(), Value::UInt(Perm::Write.code().into())),
            ("approval".to_owned(), Value::Bool(true)),
        ]))]);
        let (p, _) = decode_plan(&wyrm_core::codec::to_vec(&old).unwrap()).unwrap();
        assert_eq!(p[0].op, OpKind::Set);
        assert_eq!((p[0].check, p[0].result.clone()), (Check::Now, None));
        assert!(p[0].after.is_empty() && p[0].warn.is_none() && p[0].seconds.is_none());
    }

    /// A WAL record of a task written before the suggestions (2026-11-14): `Op::Put` with
    /// the plan as a map `{steps, parent, context}` and nothing else. The bytes are fixed,
    /// so a later change of the encoder cannot hide a record it no longer reads. The store
    /// schema stays 1: the record's shape did not change, only what its plan bytes may hold.
    #[test]
    fn a_task_written_before_the_suggestions_still_loads() {
        let plan = Value::Map(BTreeMap::from([
            (
                "steps".to_owned(),
                Value::Array(vec![Value::Map(BTreeMap::from([
                    ("op".to_owned(), Value::from("set")),
                    ("node".to_owned(), Value::from("wy/s/downstream/m/p")),
                    ("key".to_owned(), Value::from("wy/s/downstream/m/p/~set")),
                    ("payload".to_owned(), Value::Float(1.0)),
                    ("level".to_owned(), Value::UInt(Perm::Write.code().into())),
                    ("approval".to_owned(), Value::Bool(true)),
                ]))]),
            ),
            ("parent".to_owned(), Value::from("t1-1")),
            (
                "context".to_owned(),
                Value::Array(vec![Value::from("wy/s/downstream/m")]),
            ),
        ]));
        let put = Op::Put(
            "t1-2".into(),
            TaskRec {
                state: "awaiting_approval".into(),
                owner: "user:op".into(),
                ask: "set p".into(),
                plan: wyrm_core::codec::to_vec(&plan).unwrap(),
                log: vec!["asked by user:op".into()],
                error: None,
                tokens: 20,
                created: 1,
                seq: 2,
            },
        );
        const OLD: &str = "8200826474312d3289716177616974696e675f617070726f76616c67757365723a6f70\
            657365742070588aa365737465707381a6626f7063736574636b6579781877792f732f646f776e7374\
            7265616d2f6d2f702f7e736574646e6f64657377792f732f646f776e73747265616d2f6d2f70656c65\
            76656c03677061796c6f6164f93c0068617070726f76616cf566706172656e746474312d3167636f6e\
            74657874817177792f732f646f776e73747265616d2f6d817061736b656420627920757365723a6f70\
            f6140102";
        let old: String = OLD.split_whitespace().collect();
        let bytes = hex::decode(old).unwrap();
        // the fixed bytes are what the task above encodes to (the record did not change)
        assert_eq!(minicbor::to_vec(&put).unwrap(), bytes);
        let Op::Put(id, rec) = minicbor::decode::<Op>(&bytes).unwrap() else {
            panic!("not a put")
        };
        assert_eq!(
            (id.as_str(), rec.state.as_str()),
            ("t1-2", "awaiting_approval")
        );
        let (steps, extras) = decode_plan(&rec.plan).unwrap();
        assert_eq!(steps.len(), 1);
        assert_eq!(steps[0].key, "wy/s/downstream/m/p/~set");
        assert_eq!(
            extras,
            Extras {
                parent: Some("t1-1".into()),
                context: vec!["wy/s/downstream/m".into()],
                ..Extras::default()
            },
            "no suggestions, not replaced, no review"
        );
    }

    #[test]
    fn key_is_created_once_and_private() {
        let d = tmp("key");
        std::fs::create_dir_all(&d).unwrap();
        let p = d.join("agent.key");
        let a = load_or_create_key(&p).unwrap();
        let b = load_or_create_key(&p).unwrap();
        assert_eq!(*a, *b);
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mode = std::fs::metadata(&p).unwrap().permissions().mode();
            assert_eq!(mode & 0o777, 0o600);
        }
        let _ = std::fs::remove_dir_all(d);
    }

    #[test]
    fn compaction_keeps_state_and_drops_history() {
        let d = tmp("compact");
        {
            let mut s = open(&d, COMPACT_AT).unwrap();
            for i in 0..30 {
                s.apply(Op::Put(format!("t-{i}"), rec(i))).unwrap();
                if i % 2 == 0 {
                    s.apply(Op::Remove(format!("t-{i}"))).unwrap();
                }
            }
            s.apply(Op::Budget { day: 7, used: 99 }).unwrap();
            assert_eq!(s.lsn(), 46);
        }
        let s = open(&d, 10).unwrap();
        assert_eq!(s.lsn(), 16, "15 tasks + budget");
        assert_eq!(s.state().tasks.len(), 15);
        assert_eq!((s.state().day, s.state().used), (7, 99));
        assert_eq!(*s.state().tasks["t-1"], rec(1));
        drop(s);
        // An interrupted swap (agent moved away, agent.next complete) recovers.
        std::fs::rename(d.join("agent"), d.join("agent.next")).unwrap();
        let s = open(&d, COMPACT_AT).unwrap();
        assert_eq!(s.state().tasks.len(), 15);
        assert!(!d.join("agent.next").exists());
        // While running: compact an open store in place.
        let mut s = s;
        for i in 0..20 {
            s.apply(Op::Remove(format!("t-{i}"))).unwrap();
        }
        let s = compact(&d, s).unwrap();
        assert_eq!(s.lsn(), 6, "5 tasks + budget");
        assert_eq!(*s.state().tasks["t-21"], rec(21));
        drop(s);
        let _ = std::fs::remove_dir_all(d);
    }
}
