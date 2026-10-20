//! The link registry: control-plane state persisted with `wyrm-state`.

use minicbor::{Decode, Encode};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};
use wyrm_core::keyspace::validate_segment;

/// How a link runs (wiki "Режими розгортання").
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Encode, Decode)]
#[cbor(index_only)]
pub enum Mode {
    /// In-process, started by the broker.
    #[n(0)]
    Embedded,
    /// Child process supervised by the broker (mTLS client, CN = link id).
    #[n(1)]
    Process,
    /// Runs elsewhere (MCU, remote host) with a CA-issued certificate.
    #[n(2)]
    External,
}

impl Mode {
    pub fn parse(s: &str) -> Option<Self> {
        Some(match s {
            "embedded" => Mode::Embedded,
            "process" => Mode::Process,
            "external" => Mode::External,
            _ => return None,
        })
    }

    pub fn name(self) -> &'static str {
        match self {
            Mode::Embedded => "embedded",
            Mode::Process => "process",
            Mode::External => "external",
        }
    }

    /// Connects over the network with its own certificate (gets an ACL rule).
    pub fn is_remote(self) -> bool {
        !matches!(self, Mode::Embedded)
    }
}

/// Where a registry entry came from: `wyrmd.json5` entries follow the file,
/// runtime entries follow `sys/links/~act/*`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Encode, Decode)]
#[cbor(index_only)]
pub enum Origin {
    #[n(0)]
    Config,
    #[n(1)]
    Runtime,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Encode, Decode)]
pub struct LinkDef {
    #[n(0)]
    pub id: String,
    #[n(1)]
    pub driver: String,
    #[n(2)]
    pub mode: Mode,
    /// `~def.params` as canonical CBOR (a `Value` map).
    #[n(3)]
    #[cbor(with = "minicbor::bytes")]
    pub params: Vec<u8>,
    /// argon2id PHC string of the link token; empty for embedded links.
    #[n(4)]
    pub token_hash: String,
    #[n(5)]
    pub rev: u32,
    #[n(6)]
    pub origin: Origin,
    /// Unix seconds.
    #[n(7)]
    pub created: u64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct QuarantineEntry {
    pub first_seen: u64,
    pub last_seen: u64,
    pub attempts: u64,
}

#[derive(Debug, Encode, Decode)]
pub enum Op {
    #[n(0)]
    Install(#[n(0)] LinkDef),
    #[n(1)]
    Remove(#[n(0)] String),
    /// Replace params (and mode) of an existing link; bumps `rev`.
    #[n(2)]
    Update {
        #[n(0)]
        id: String,
        #[n(1)]
        mode: Mode,
        #[n(2)]
        #[cbor(with = "minicbor::bytes")]
        params: Vec<u8>,
    },
    #[n(3)]
    SetTokenHash {
        #[n(0)]
        id: String,
        #[n(1)]
        hash: String,
    },
    /// A session with an unknown CN was seen at `seen`.
    #[n(4)]
    Quarantine {
        #[n(0)]
        cn: String,
        #[n(1)]
        seen: u64,
    },
    /// Leave quarantine (followed by an `Install` of the same id).
    #[n(5)]
    Approve(#[n(0)] String),
    /// Leave quarantine and never record this CN again.
    #[n(6)]
    Reject(#[n(0)] String),
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct Registry {
    pub links: BTreeMap<String, LinkDef>,
    pub quarantine: BTreeMap<String, QuarantineEntry>,
    pub blocklist: BTreeSet<String>,
}

impl wyrm_state::State for Registry {
    const SCHEMA: u32 = 1;
    type Op = Op;

    fn apply(&mut self, op: &Op) -> Result<(), String> {
        match op {
            Op::Install(def) => {
                validate_segment(&def.id).map_err(|e| format!("link id: {e}"))?;
                if self.links.contains_key(&def.id) {
                    return Err(format!("link {} already installed", def.id));
                }
                if def.mode.is_remote() && def.token_hash.is_empty() {
                    return Err(format!("{} link needs a token", def.mode.name()));
                }
                self.quarantine.remove(&def.id);
                self.links.insert(def.id.clone(), def.clone());
            }
            Op::Remove(id) => {
                self.links
                    .remove(id)
                    .ok_or_else(|| format!("no link {id}"))?;
            }
            Op::Update { id, mode, params } => {
                let def = self
                    .links
                    .get_mut(id)
                    .ok_or_else(|| format!("no link {id}"))?;
                if mode.is_remote() && def.token_hash.is_empty() {
                    return Err(format!("{} link needs a token", mode.name()));
                }
                def.mode = *mode;
                def.params = params.clone();
                def.rev += 1;
            }
            Op::SetTokenHash { id, hash } => {
                self.links
                    .get_mut(id)
                    .ok_or_else(|| format!("no link {id}"))?
                    .token_hash = hash.clone();
            }
            Op::Quarantine { cn, seen } => {
                if self.links.contains_key(cn) || self.blocklist.contains(cn) {
                    return Err(format!("{cn} is known"));
                }
                let e = self
                    .quarantine
                    .entry(cn.clone())
                    .or_insert(QuarantineEntry {
                        first_seen: *seen,
                        ..Default::default()
                    });
                e.last_seen = *seen;
                e.attempts += 1;
            }
            Op::Approve(cn) => {
                self.quarantine
                    .remove(cn)
                    .ok_or_else(|| format!("{cn} is not in quarantine"))?;
            }
            Op::Reject(cn) => {
                self.quarantine
                    .remove(cn)
                    .ok_or_else(|| format!("{cn} is not in quarantine"))?;
                self.blocklist.insert(cn.clone());
            }
        }
        Ok(())
    }
}
