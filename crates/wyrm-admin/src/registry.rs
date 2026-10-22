//! The link registry: control-plane state persisted with `wyrm-state`.

use minicbor::{Decode, Encode};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};
use wyrm_core::keyspace::validate_segment;
use wyrm_core::profile::{self, ProfileDef};

/// A link id is a key segment, a certificate CN and a directory name under
/// `data_dir/links`: no leading `.` (rejects `.` and `..`), no reserved names.
pub fn validate_link_id(id: &str) -> Result<(), String> {
    validate_segment(id).map_err(|e| format!("link id: {e}"))?;
    if id.starts_with('.') {
        return Err(format!("link id {id:?} may not start with '.'"));
    }
    if matches!(id, "admin" | "broker" | "flows") {
        return Err(format!("link id {id:?} is reserved"));
    }
    Ok(())
}

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
    /// Add or replace a profile (`pub/<name>/~meta`, CBOR `ProfileDef`).
    #[n(7)]
    PutProfile {
        #[n(0)]
        name: String,
        #[n(1)]
        #[cbor(with = "minicbor::bytes")]
        cbor: Vec<u8>,
    },
    #[n(8)]
    RemoveProfile(#[n(0)] String),
    /// A broker option (`sys/<name>`, see [`Options`]).
    #[n(9)]
    SetOption {
        #[n(0)]
        name: String,
        #[n(1)]
        on: bool,
    },
    /// Add a peer broker (`sys/upstream`, `sys/downstream`).
    #[n(10)]
    AddPeer(#[n(0)] PeerDef),
    #[n(11)]
    RemovePeer(#[n(0)] String),
    /// Connect to an upstream site or not (it stays configured).
    #[n(12)]
    SetPeerEnabled {
        #[n(0)]
        site: String,
        #[n(1)]
        on: bool,
    },
}

/// Which side a peer broker is on (ADR 0007).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Encode, Decode)]
#[cbor(index_only)]
pub enum PeerDir {
    /// We connect to it and it reads our `down/**`, `flows/**`.
    #[n(0)]
    Upstream,
    /// It connects to us and serves its own `wy/<site>/**`.
    #[n(1)]
    Downstream,
}

/// A peer broker added at runtime, as DSA's `/sys/upstream` (peers from
/// `wyrmd.json5` are not stored here).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Encode, Decode)]
pub struct PeerDef {
    #[n(0)]
    pub site: String,
    #[n(1)]
    pub dir: PeerDir,
    /// `quic/<host>:<port>` of an upstream site; empty for downstream.
    #[n(2)]
    pub endpoint: String,
    /// That site's CA certificate (PEM): trusted only on the QUIC broker link.
    #[n(3)]
    pub ca_pem: String,
    /// Upstream only: connect to it.
    #[n(4)]
    pub enabled: bool,
    #[n(5)]
    pub created: u64,
}

/// Broker options changed at runtime, as DSA's `allowAllLinks` and
/// `quarantine` (`wy/<site>/sys/allow_all_links`, `.../enable_quarantine`).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Options {
    /// Install every unknown certificate CN signed by our CA as an
    /// external link, without quarantine. Off by default.
    pub allow_all_links: bool,
    /// Record unknown CNs in `sys/quarantine` (off: drop them unrecorded).
    pub enable_quarantine: bool,
}

impl Default for Options {
    fn default() -> Self {
        Self {
            allow_all_links: false,
            enable_quarantine: true,
        }
    }
}

impl Options {
    /// The option `name` (one of [`OPTION_NAMES`]).
    pub fn get(&self, name: &str) -> Option<bool> {
        match name {
            "allow_all_links" => Some(self.allow_all_links),
            "enable_quarantine" => Some(self.enable_quarantine),
            _ => None,
        }
    }
}

/// Names of the [`Options`] fields, as `SetOption` takes them.
pub const OPTION_NAMES: [&str; 2] = ["allow_all_links", "enable_quarantine"];

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct Registry {
    pub links: BTreeMap<String, LinkDef>,
    pub quarantine: BTreeMap<String, QuarantineEntry>,
    pub blocklist: BTreeSet<String>,
    /// Ids of removed links. Their certificates stay valid until expiry (no
    /// CRL yet), so an id is never handed out again.
    #[serde(default)]
    pub retired: BTreeSet<String>,
    /// Profiles beside the built-in ones: name → CBOR `ProfileDef`.
    #[serde(default)]
    pub profiles: BTreeMap<String, Vec<u8>>,
    /// Replaced params per link, oldest first: `(rev, params CBOR)`, at most
    /// [`LINK_HISTORY`] (T11: version history and rollback).
    #[serde(default)]
    pub history: BTreeMap<String, Vec<(u32, Vec<u8>)>>,
    #[serde(default)]
    pub options: Options,
    /// Peer brokers added at runtime, by site.
    #[serde(default)]
    pub peers: BTreeMap<String, PeerDef>,
}

/// Replaced params kept per link.
pub const LINK_HISTORY: usize = 10;

impl Registry {
    /// A profile by name: built-in or stored.
    pub fn profile(&self, name: &str) -> Option<ProfileDef> {
        if let Some((_, p)) = profile::builtins().into_iter().find(|(n, _)| *n == name) {
            return Some(p);
        }
        self.profiles
            .get(name)
            .and_then(|b| wyrm_core::codec::from_slice(b).ok())
    }

    fn check_profile(&self, name: &str, def: &ProfileDef) -> Result<(), String> {
        profile::validate_name(name)?;
        if profile::builtins().iter().any(|(n, _)| *n == name) {
            return Err(format!("profile {name} is built in"));
        }
        // the parent exists and the chain does not come back to `name`
        let mut next = def.extends.clone();
        for _ in 0..profile::MAX_DEPTH {
            let Some(p) = next.take() else {
                return Ok(());
            };
            if p == name {
                return Err(format!("profile {name}: extends cycle"));
            }
            next = self
                .profile(&p)
                .ok_or_else(|| format!("profile {name}: extends unknown {p}"))?
                .extends;
        }
        Err(format!(
            "profile {name}: extends chain longer than {}",
            profile::MAX_DEPTH
        ))
    }
}

impl wyrm_state::State for Registry {
    const SCHEMA: u32 = 6;
    type Op = Op;

    fn apply(&mut self, op: &Op) -> Result<(), String> {
        match op {
            Op::Install(def) => {
                validate_link_id(&def.id)?;
                if self
                    .peers
                    .get(&def.id)
                    .is_some_and(|p| p.dir == PeerDir::Downstream)
                {
                    return Err(format!("{} is a downstream site", def.id));
                }
                if self.retired.contains(&def.id) {
                    return Err(format!(
                        "link id {} was removed before; its certificate may still be valid, choose a new id",
                        def.id
                    ));
                }
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
                self.history.remove(id);
                let def = self
                    .links
                    .remove(id)
                    .ok_or_else(|| format!("no link {id}"))?;
                // A token hash exists iff the link was ever remote, i.e. a
                // certificate was issued (Update to embedded keeps it).
                if def.mode.is_remote() || !def.token_hash.is_empty() {
                    self.retired.insert(id.clone());
                }
            }
            Op::Update { id, mode, params } => {
                let def = self
                    .links
                    .get_mut(id)
                    .ok_or_else(|| format!("no link {id}"))?;
                if mode.is_remote() && def.token_hash.is_empty() {
                    return Err(format!("{} link needs a token", mode.name()));
                }
                let h = self.history.entry(id.clone()).or_default();
                h.push((def.rev, def.params.clone()));
                if h.len() > LINK_HISTORY {
                    h.remove(0);
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
                validate_link_id(cn)?;
                if self.links.contains_key(cn)
                    || self.blocklist.contains(cn)
                    || self.retired.contains(cn)
                {
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
            Op::PutProfile { name, cbor } => {
                let def: ProfileDef = wyrm_core::codec::from_slice(cbor)
                    .map_err(|e| format!("profile {name}: {e}"))?;
                self.check_profile(name, &def)?;
                self.profiles.insert(name.clone(), cbor.clone());
            }
            Op::RemoveProfile(name) => {
                if !self.profiles.contains_key(name) {
                    return Err(format!("no profile {name}"));
                }
                let child = self.profiles.iter().find(|(n, b)| {
                    *n != name
                        && wyrm_core::codec::from_slice::<ProfileDef>(b)
                            .is_ok_and(|p| p.extends.as_deref() == Some(name.as_str()))
                });
                if let Some((c, _)) = child {
                    return Err(format!("profile {c} extends {name}"));
                }
                self.profiles.remove(name);
            }
            Op::AddPeer(def) => {
                validate_segment(&def.site).map_err(|e| format!("site: {e}"))?;
                if self.peers.contains_key(&def.site) {
                    return Err(format!("peer {} exists", def.site));
                }
                if def.dir == PeerDir::Downstream && self.links.contains_key(&def.site) {
                    return Err(format!(
                        "{} is a link id (down/{} would be both)",
                        def.site, def.site
                    ));
                }
                if (def.dir == PeerDir::Upstream) == def.endpoint.is_empty() {
                    return Err("an upstream peer needs an endpoint, a downstream one none".into());
                }
                self.peers.insert(def.site.clone(), def.clone());
            }
            Op::RemovePeer(site) => {
                self.peers
                    .remove(site)
                    .ok_or_else(|| format!("no peer {site}"))?;
            }
            Op::SetPeerEnabled { site, on } => {
                self.peers
                    .get_mut(site)
                    .ok_or_else(|| format!("no peer {site}"))?
                    .enabled = *on;
            }
            Op::SetOption { name, on } => match name.as_str() {
                "allow_all_links" => self.options.allow_all_links = *on,
                "enable_quarantine" => self.options.enable_quarantine = *on,
                other => return Err(format!("no option {other}")),
            },
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use wyrm_state::State;

    fn def(id: &str, mode: Mode) -> LinkDef {
        LinkDef {
            id: id.into(),
            driver: "d".into(),
            mode,
            params: vec![0xa0],
            token_hash: "h".into(),
            rev: 1,
            origin: Origin::Runtime,
            created: 0,
        }
    }

    #[test]
    fn link_ids() {
        assert!(validate_link_id("plc1").is_ok());
        for bad in [".", "..", ".hidden", "a/b", "admin", "broker", "~x", ""] {
            assert!(validate_link_id(bad).is_err(), "{bad:?}");
        }
    }

    #[test]
    fn peers_and_link_ids_do_not_overlap() {
        let mut r = Registry::default();
        let peer = |site: &str, dir, endpoint: &str| PeerDef {
            site: site.into(),
            dir,
            endpoint: endpoint.into(),
            ca_pem: "pem".into(),
            enabled: true,
            created: 0,
        };
        r.apply(&Op::AddPeer(peer("edge", PeerDir::Downstream, "")))
            .unwrap();
        r.apply(&Op::AddPeer(peer(
            "cloud",
            PeerDir::Upstream,
            "quic/c:7448",
        )))
        .unwrap();
        assert!(r
            .apply(&Op::AddPeer(peer("x", PeerDir::Upstream, "")))
            .is_err());
        assert!(r
            .apply(&Op::AddPeer(peer("edge", PeerDir::Downstream, "")))
            .is_err());
        let mut d = def("edge", Mode::External);
        assert!(r.apply(&Op::Install(d.clone())).is_err(), "downstream name");
        d.id = "plc".into();
        r.apply(&Op::Install(d)).unwrap();
        assert!(r
            .apply(&Op::AddPeer(peer("plc", PeerDir::Downstream, "")))
            .is_err());
        r.apply(&Op::SetPeerEnabled {
            site: "cloud".into(),
            on: false,
        })
        .unwrap();
        assert!(!r.peers["cloud"].enabled);
        r.apply(&Op::RemovePeer("edge".into())).unwrap();
        assert!(r.apply(&Op::RemovePeer("edge".into())).is_err());
    }

    #[test]
    fn removed_remote_ids_are_retired() {
        let mut r = Registry::default();
        r.apply(&Op::Install(def("plc1", Mode::Process))).unwrap();
        r.apply(&Op::Remove("plc1".into())).unwrap();
        assert!(r.apply(&Op::Install(def("plc1", Mode::Process))).is_err());
        assert!(r
            .apply(&Op::Quarantine {
                cn: "plc1".into(),
                seen: 1
            })
            .is_err());
        // embedded links have no certificate: the id may come back
        let mut e = def("emb", Mode::Embedded);
        e.token_hash.clear();
        r.apply(&Op::Install(e.clone())).unwrap();
        r.apply(&Op::Remove("emb".into())).unwrap();
        r.apply(&Op::Install(e)).unwrap();
        assert!(r.apply(&Op::Install(def("..", Mode::External))).is_err());
        // remote, then switched to embedded: the certificate still exists
        r.apply(&Op::Install(def("sw", Mode::Process))).unwrap();
        r.apply(&Op::Update {
            id: "sw".into(),
            mode: Mode::Embedded,
            params: vec![0xa0],
        })
        .unwrap();
        r.apply(&Op::Remove("sw".into())).unwrap();
        assert!(r.retired.contains("sw"));
    }
}
