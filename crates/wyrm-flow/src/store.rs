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
        /// Subject of the deployer (`origin` of the deploy request); absent
        /// in records written before it was kept.
        #[n(2)]
        by: Option<String>,
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
    /// A custom block of the site's library (ADR 0040 §3): each put is a new version.
    #[n(4)]
    PutBlock {
        #[n(0)]
        name: String,
        #[n(1)]
        #[cbor(with = "minicbor::bytes")]
        cbor: Vec<u8>,
    },
    #[n(5)]
    RemoveBlock(#[n(0)] String),
}

/// A custom block of the library: its definition (CBOR) and how often it was put.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct BlockRec {
    pub version: u64,
    pub cbor: Vec<u8>,
}

/// Custom blocks of one site's library at most.
pub const MAX_LIBRARY: usize = 256;

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct FlowStore {
    pub defs: BTreeMap<String, Vec<u8>>,
    /// Operator start/stop, separate from `~def.enabled`.
    pub stopped: BTreeMap<String, bool>,
    pub states: BTreeMap<String, Vec<NodeStateRec>>,
    /// Replaced definitions per flow, oldest first, at most [`HISTORY`].
    pub history: BTreeMap<String, Vec<Vec<u8>>>,
    /// Who deployed the current definition. A flow keeps running when its
    /// deployer loses rights (owner decision, ADR 0008); this tells an
    /// operator whose flows to review.
    pub deployers: BTreeMap<String, String>,
    /// The library of custom blocks (ADR 0040 §3). A flow never reads it: an editor copies a
    /// block into the definition it deploys.
    pub blocks: BTreeMap<String, BlockRec>,
}

/// Replaced definitions kept per flow (for `history` and `rollback`).
pub const HISTORY: usize = 10;

impl wyrm_state::State for FlowStore {
    const SCHEMA: u32 = 4;
    type Op = Op;

    fn apply(&mut self, op: &Op) -> Result<(), String> {
        match op {
            Op::PutDef { id, cbor, by } => {
                match by {
                    Some(b) => self.deployers.insert(id.clone(), b.clone()),
                    None => self.deployers.remove(id),
                };
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
                self.deployers.remove(id);
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
            Op::PutBlock { name, cbor } => {
                if !self.blocks.contains_key(name) && self.blocks.len() >= MAX_LIBRARY {
                    return Err(format!("the library holds {MAX_LIBRARY} blocks"));
                }
                let rec = self.blocks.entry(name.clone()).or_default();
                rec.version += 1;
                rec.cbor = cbor.clone();
            }
            Op::RemoveBlock(name) => {
                self.blocks
                    .remove(name)
                    .ok_or_else(|| format!("no block {name}"))?;
            }
        }
        Ok(())
    }
}
