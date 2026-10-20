//! `flows/<id>/~def` (spec 06): parsing and the compiler checks, in the
//! spec order — schema, node ids, node types and configs, edges and port
//! types, acyclic except through `delay`, rhai, `maxperm`, memory limits.
//! The first error stops; its text starts with the path (`nodes.sum.expr: …`).

use crate::nodes::{self, PortType, Ports};
use std::collections::{BTreeMap, BTreeSet};
use std::time::Duration;
use wyrm_core::{Perm, Value};

#[derive(Debug, Clone, PartialEq, thiserror::Error)]
#[error("{0}")]
pub struct DefError(pub String);

pub type Result<T> = core::result::Result<T, DefError>;

fn err<T>(msg: impl Into<String>) -> Result<T> {
    Err(DefError(msg.into()))
}

pub type Map = BTreeMap<String, Value>;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Overflow {
    DropOldest,
    DropNewest,
    Block,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Policy {
    pub overflow: Overflow,
    pub queue: usize,
    pub state_flush: Duration,
    pub backoff_max: Duration,
}

impl Default for Policy {
    fn default() -> Self {
        Self {
            overflow: Overflow::DropOldest,
            queue: 64,
            state_flush: Duration::from_secs(30),
            backoff_max: Duration::from_secs(60),
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct NodeDef {
    pub ty: String,
    /// The node's own keys (without `type`/`placement`).
    pub cfg: Map,
    /// CRC32C of `type` + canonical CBOR of `cfg`: unchanged nodes keep state.
    pub hash: u32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Endpoint {
    pub node: String,
    pub port: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Edge {
    pub from: Endpoint,
    pub to: Endpoint,
}

#[derive(Debug, Clone, PartialEq)]
pub struct FlowDef {
    pub id: String,
    pub version: u64,
    pub enabled: bool,
    pub description: Option<String>,
    pub nodes: BTreeMap<String, NodeDef>,
    pub edges: Vec<Edge>,
    pub policy: Policy,
    pub maxperm: Perm,
    /// As received (CBOR map), for `~def` and storage.
    pub raw: Value,
}

/// Total `window.max_samples` allowed per flow.
pub const MAX_WINDOW_SAMPLES: u64 = 100_000;

fn as_map<'a>(v: &'a Value, path: &str) -> Result<&'a Map> {
    match v {
        Value::Map(m) => Ok(m),
        _ => err(format!("{path}: expected a map")),
    }
}

fn uint(v: &Value, path: &str) -> Result<u64> {
    match v {
        Value::UInt(u) => Ok(*u),
        Value::Float(f) if f.fract() == 0.0 && *f >= 0.0 => Ok(*f as u64),
        _ => err(format!("{path}: expected a non-negative integer")),
    }
}

fn perm(v: &Value, path: &str) -> Result<Perm> {
    match v {
        Value::Str(s) => Perm::ALL
            .iter()
            .copied()
            .find(|p| p.name() == s)
            .ok_or_else(|| DefError(format!("{path}: unknown permission {s}"))),
        v => Perm::try_from(u8::try_from(uint(v, path)?).unwrap_or(u8::MAX))
            .map_err(|_| DefError(format!("{path}: permission out of range"))),
    }
}

fn node_id_ok(id: &str) -> bool {
    !id.is_empty() && id.chars().all(|c| c.is_ascii_alphanumeric() || c == '_')
}

fn endpoint(s: &str, path: &str) -> Result<Endpoint> {
    match s.split_once('.') {
        Some((node, port)) if !node.is_empty() && !port.is_empty() => Ok(Endpoint {
            node: node.to_owned(),
            port: port.to_owned(),
        }),
        _ => err(format!("{path}: expected \"<node>.<port>\", got {s:?}")),
    }
}

/// Step 1: schema. Returns the typed definition.
pub fn parse(v: &Value) -> Result<FlowDef> {
    let m = as_map(v, "~def")?;
    const KNOWN: &[&str] = &[
        "id",
        "version",
        "enabled",
        "description",
        "nodes",
        "edges",
        "policy",
        "permissions",
    ];
    if let Some(k) = m.keys().find(|k| !KNOWN.contains(&k.as_str())) {
        return err(format!("{k}: unknown field"));
    }
    let id = match m.get("id") {
        Some(Value::Str(s)) => s.clone(),
        _ => return err("id: required string"),
    };
    wyrm_core::keyspace::validate_segment(&id).map_err(|e| DefError(format!("id: {e}")))?;
    let version = uint(m.get("version").unwrap_or(&Value::UInt(0)), "version")?;
    let enabled = match m.get("enabled") {
        None => true,
        Some(Value::Bool(b)) => *b,
        Some(_) => return err("enabled: expected true or false"),
    };
    let description = match m.get("description") {
        None => None,
        Some(Value::Str(s)) => Some(s.clone()),
        Some(_) => return err("description: expected a string"),
    };
    let mut nodes = BTreeMap::new();
    for (nid, nv) in as_map(m.get("nodes").unwrap_or(&Value::Map(Map::new())), "nodes")? {
        let path = format!("nodes.{nid}");
        let mut cfg = as_map(nv, &path)?.clone();
        let ty = match cfg.remove("type") {
            Some(Value::Str(t)) => t,
            _ => return err(format!("{path}.type: required string")),
        };
        match cfg.remove("placement") {
            None => {}
            Some(Value::Str(p)) if p == "local" => {}
            Some(_) => return err(format!("{path}.placement: only \"local\" is supported")),
        }
        let mut bytes = ty.as_bytes().to_vec();
        bytes.extend(wyrm_core::codec::to_vec(&Value::Map(cfg.clone())).unwrap_or_default());
        nodes.insert(
            nid.clone(),
            NodeDef {
                ty,
                cfg,
                hash: crc32c::crc32c(&bytes),
            },
        );
    }
    let mut edges = Vec::new();
    if let Some(ev) = m.get("edges") {
        let Value::Array(items) = ev else {
            return err("edges: expected an array");
        };
        for (i, e) in items.iter().enumerate() {
            let path = format!("edges[{i}]");
            match e {
                Value::Array(pair) if pair.len() == 2 => match (&pair[0], &pair[1]) {
                    (Value::Str(a), Value::Str(b)) => edges.push(Edge {
                        from: endpoint(a, &path)?,
                        to: endpoint(b, &path)?,
                    }),
                    _ => return err(format!("{path}: expected two strings")),
                },
                _ => return err(format!("{path}: expected [from, to]")),
            }
        }
    }
    let mut policy = Policy::default();
    if let Some(pv) = m.get("policy") {
        let pm = as_map(pv, "policy")?;
        for (k, v) in pm {
            let path = format!("policy.{k}");
            match k.as_str() {
                "overflow" => {
                    policy.overflow = match v {
                        Value::Str(s) if s == "drop_oldest" => Overflow::DropOldest,
                        Value::Str(s) if s == "drop_newest" => Overflow::DropNewest,
                        Value::Str(s) if s == "block" => Overflow::Block,
                        _ => return err(format!("{path}: drop_oldest | drop_newest | block")),
                    }
                }
                "queue" => {
                    let q = uint(v, &path)?;
                    if !(1..=65_536).contains(&q) {
                        return err(format!("{path}: 1..=65536"));
                    }
                    policy.queue = q as usize;
                }
                "state_flush_s" => policy.state_flush = Duration::from_secs(uint(v, &path)?.max(1)),
                "restart" => {
                    let rm = as_map(v, &path)?;
                    if let Some(b) = rm.get("backoff_max_s") {
                        policy.backoff_max =
                            Duration::from_secs(uint(b, &format!("{path}.backoff_max_s"))?.max(1));
                    }
                }
                _ => return err(format!("{path}: unknown field")),
            }
        }
    }
    let mut maxperm = Perm::Read;
    if let Some(pv) = m.get("permissions") {
        let pm = as_map(pv, "permissions")?;
        for (k, v) in pm {
            match k.as_str() {
                "maxperm" => maxperm = perm(v, "permissions.maxperm")?,
                "token" => {}
                _ => return err(format!("permissions.{k}: unknown field")),
            }
        }
    }
    Ok(FlowDef {
        id,
        version,
        enabled,
        description,
        nodes,
        edges,
        policy,
        maxperm,
        raw: v.clone(),
    })
}

/// Steps 2–8. Returns the port map of every node.
pub fn check(def: &FlowDef) -> Result<BTreeMap<String, Ports>> {
    // 2. ids
    for id in def.nodes.keys() {
        if !node_id_ok(id) {
            return err(format!("nodes.{id}: id must be [A-Za-z0-9_]+"));
        }
    }
    // 3. types and configs
    let mut ports = BTreeMap::new();
    for (id, n) in &def.nodes {
        let p = nodes::ports(&n.ty, &n.cfg).map_err(|e| DefError(format!("nodes.{id}: {e}")))?;
        ports.insert(id.clone(), p);
    }
    // 4. edges → existing ports, compatible types
    for (i, e) in def.edges.iter().enumerate() {
        let path = format!("edges[{i}]");
        let from = ports
            .get(&e.from.node)
            .ok_or_else(|| DefError(format!("{path}: unknown node {}", e.from.node)))?;
        let to = ports
            .get(&e.to.node)
            .ok_or_else(|| DefError(format!("{path}: unknown node {}", e.to.node)))?;
        let ft = from.output(&e.from.port).ok_or_else(|| {
            DefError(format!(
                "{path}: {} has no output {}",
                e.from.node, e.from.port
            ))
        })?;
        let tt = to
            .input(&e.to.port)
            .ok_or_else(|| DefError(format!("{path}: {} has no input {}", e.to.node, e.to.port)))?;
        if !ft.fits(tt) {
            return err(format!(
                "{path}: {}.{} ({}) does not fit {}.{} ({})",
                e.from.node,
                e.from.port,
                ft.name(),
                e.to.node,
                e.to.port,
                tt.name()
            ));
        }
    }
    // 5. acyclic, except through `delay`
    let mut adj: BTreeMap<&str, Vec<&str>> = BTreeMap::new();
    for e in &def.edges {
        if def.nodes.get(&e.to.node).is_some_and(|n| n.ty == "delay") {
            continue;
        }
        adj.entry(e.from.node.as_str())
            .or_default()
            .push(e.to.node.as_str());
    }
    let mut done = BTreeSet::new();
    for start in def.nodes.keys() {
        let mut path = Vec::new();
        if let Some(cycle) = find_cycle(start, &adj, &mut path, &mut done) {
            return err(format!(
                "edges: cycle {} (only a delay node may close a loop)",
                cycle.join(" → ")
            ));
        }
    }
    // 6. rhai compiles (expression, filter)
    for (id, n) in &def.nodes {
        nodes::check_script(&n.ty, &n.cfg).map_err(|e| DefError(format!("nodes.{id}.{e}")))?;
    }
    // 7. maxperm covers every command sink
    for (id, n) in &def.nodes {
        if let Some(need) = nodes::needs_perm(&n.ty) {
            if def.maxperm < need {
                return err(format!(
                    "permissions.maxperm: {} < {} needed by nodes.{id} ({})",
                    def.maxperm.name(),
                    need.name(),
                    n.ty
                ));
            }
        }
    }
    // 8. memory limits
    let samples: u64 = def
        .nodes
        .values()
        .filter(|n| n.ty == "window")
        .map(|n| nodes::max_samples(&n.cfg).unwrap_or(u64::MAX))
        .fold(0u64, u64::saturating_add);
    if samples > MAX_WINDOW_SAMPLES {
        return err(format!(
            "nodes: window.max_samples total {samples} > {MAX_WINDOW_SAMPLES}"
        ));
    }
    let _ = PortType::Any;
    Ok(ports)
}

fn find_cycle<'a>(
    n: &'a str,
    adj: &BTreeMap<&'a str, Vec<&'a str>>,
    path: &mut Vec<&'a str>,
    done: &mut BTreeSet<&'a str>,
) -> Option<Vec<String>> {
    if done.contains(n) {
        return None;
    }
    if let Some(pos) = path.iter().position(|p| *p == n) {
        let mut c: Vec<String> = path[pos..].iter().map(|s| (*s).to_owned()).collect();
        c.push(n.to_owned());
        return Some(c);
    }
    path.push(n);
    for next in adj.get(n).map(Vec::as_slice).unwrap_or_default() {
        if let Some(c) = find_cycle(next, adj, path, done) {
            return Some(c);
        }
    }
    path.pop();
    done.insert(n);
    None
}

/// Parse and check in one step.
pub fn compile(v: &Value) -> Result<(FlowDef, BTreeMap<String, Ports>)> {
    let def = parse(v)?;
    let ports = check(&def)?;
    Ok((def, ports))
}
