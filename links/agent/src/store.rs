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
//! [`COMPACT_AT`] records: removed tasks then also leave the disk.

use crate::tools::{OpKind, PlanOp};
use crate::TaskState;
use minicbor::{Decode, Encode};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use wyrm_core::{Perm, Value};
use wyrm_state::Store;
use zeroize::Zeroizing;

/// Rewrite the store at start once its WAL holds more records than this.
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
    Value::Map(m)
}

pub fn encode_plan(plan: &[PlanOp]) -> Vec<u8> {
    wyrm_core::codec::to_vec(&Value::Array(plan.iter().map(plan_op_value).collect()))
        .unwrap_or_default()
}

pub fn decode_plan(b: &[u8]) -> Result<Vec<PlanOp>, String> {
    if b.is_empty() {
        return Ok(Vec::new());
    }
    let v: Value = wyrm_core::codec::from_slice(b).map_err(|e| format!("plan: {e}"))?;
    let Value::Array(items) = v else {
        return Err("plan: not an array".into());
    };
    items.iter().map(plan_op_from).collect()
}

fn plan_op_from(v: &Value) -> Result<PlanOp, String> {
    let Value::Map(m) = v else {
        return Err("plan step: not a map".into());
    };
    let s = |k: &str| match m.get(k) {
        Some(Value::Str(s)) => Ok(s.clone()),
        _ => Err(format!("plan step: {k} missing")),
    };
    let op = match s("op")?.as_str() {
        "set" => OpKind::Set,
        "invoke" => OpKind::Invoke,
        other => return Err(format!("plan step: op {other:?}")),
    };
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
    })
}

pub fn state_from_name(n: &str) -> Option<TaskState> {
    [
        TaskState::Planning,
        TaskState::AwaitingApproval,
        TaskState::Running,
        TaskState::Done,
        TaskState::Failed,
    ]
    .into_iter()
    .find(|s| s.name() == n)
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
            plan: encode_plan(&[PlanOp {
                op: OpKind::Invoke,
                node: "wy/s/down/m/p".into(),
                key: "wy/s/down/m/p/~act/go".into(),
                action: Some("go".into()),
                payload: Value::Map(BTreeMap::from([("a".to_owned(), Value::UInt(1))])),
                level: Perm::Config,
                needs_approval: true,
                reason: Some("why".into()),
            }]),
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
        let p = decode_plan(&r.plan).unwrap();
        assert_eq!(p.len(), 1);
        assert_eq!(p[0].op, OpKind::Invoke);
        assert_eq!(p[0].action.as_deref(), Some("go"));
        assert_eq!(p[0].level, Perm::Config);
        assert!(p[0].needs_approval);
        assert_eq!(encode_plan(&p), r.plan);
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
        drop(s);
        let _ = std::fs::remove_dir_all(d);
    }
}
