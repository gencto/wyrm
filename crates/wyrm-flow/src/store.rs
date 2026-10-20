//! Flow definitions and node state, persisted with `wyrm-state` (the broker
//! owns flow definitions, ADR 0003). Node state is flushed every
//! `policy.state_flush_s` and on graceful stop.

use minicbor::{Decode, Encode};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Encode, Decode)]
pub struct NodeStateRec {
    #[n(0)]
    pub node: String,
    /// Config hash of the node that wrote it; restored only on a match.
    #[n(1)]
    pub hash: u32,
    /// Microseconds since the Unix epoch.
    #[n(2)]
    pub t: u64,
    #[n(3)]
    #[cbor(with = "minicbor::bytes")]
    pub cbor: Vec<u8>,
}

#[derive(Debug, Encode, Decode)]
pub enum Op {
    #[n(0)]
    PutDef {
        #[n(0)]
        id: String,
        #[n(1)]
        #[cbor(with = "minicbor::bytes")]
        cbor: Vec<u8>,
    },
    #[n(1)]
    RemoveDef(#[n(0)] String),
    #[n(2)]
    SetEnabled {
        #[n(0)]
        id: String,
        #[n(1)]
        on: bool,
    },
    #[n(3)]
    PutStates {
        #[n(0)]
        id: String,
        #[n(1)]
        states: Vec<NodeStateRec>,
    },
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct FlowStore {
    pub defs: BTreeMap<String, Vec<u8>>,
    /// Operator start/stop, separate from `~def.enabled`.
    pub stopped: BTreeMap<String, bool>,
    pub states: BTreeMap<String, Vec<NodeStateRec>>,
    /// Replaced definitions per flow, oldest first, at most [`HISTORY`].
    pub history: BTreeMap<String, Vec<Vec<u8>>>,
}

/// Replaced definitions kept per flow (for `history` and `rollback`).
pub const HISTORY: usize = 10;

impl wyrm_state::State for FlowStore {
    const SCHEMA: u32 = 2;
    type Op = Op;

    fn apply(&mut self, op: &Op) -> Result<(), String> {
        match op {
            Op::PutDef { id, cbor } => {
                if let Some(old) = self.defs.insert(id.clone(), cbor.clone()) {
                    let h = self.history.entry(id.clone()).or_default();
                    h.push(old);
                    if h.len() > HISTORY {
                        h.remove(0);
                    }
                }
            }
            Op::RemoveDef(id) => {
                self.defs
                    .remove(id)
                    .ok_or_else(|| format!("no flow {id}"))?;
                self.states.remove(id);
                self.history.remove(id);
                self.stopped.remove(id);
            }
            Op::SetEnabled { id, on } => {
                if !self.defs.contains_key(id) {
                    return Err(format!("no flow {id}"));
                }
                self.stopped.insert(id.clone(), !on);
            }
            Op::PutStates { id, states } => {
                if self.defs.contains_key(id) {
                    self.states.insert(id.clone(), states.clone());
                }
            }
        }
        Ok(())
    }
}
