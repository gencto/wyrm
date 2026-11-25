//! `dataflows/<id>/~def` (spec 06): parsing and the compiler checks, in the
//! spec order — schema, node ids, node types and configs, edges and port
//! types, acyclic except through `delay`, rhai, `maxperm`, memory limits.
//! The first error stops; its text starts with the path (`nodes.sum.expr: …`).
//!
//! Custom blocks (ADR 0040 §3, spec 06 0.2.24): a definition may carry `blocks`, and a node
//! of type `block:<name>` is an instance of one. [`parse`] replaces every instance by the
//! block's nodes under the ids `<instance>/<inner>` and rewires the edges, so the checks, the
//! runtime, `watch` and `preview` only ever see plain nodes.

use crate::nodes::{self, ConfigError, PortType, Ports};
use crate::scope::ScopeError;
use std::collections::{BTreeMap, BTreeSet};
use std::time::Duration;
use wyrm_core::keyspace::KeyError;
use wyrm_core::value::IntError;
use wyrm_core::{Perm, Value};

/// Why a flow definition is refused: the compiler's steps (spec 06) and the host's own checks
/// of it. Every text starts with the place in the definition (`nodes.sum.expr: …`). A
/// variant that carries the refusal of another check (a node's config, a script, a scope, a
/// key segment, a number) holds it as a typed field `error` and prints it after the place;
/// it is not also the `source()`, so a printer of the error chain does not say it twice.
#[derive(Debug, thiserror::Error)]
pub enum DefError {
    // ----- the shape of a value; `at` is its place -----
    #[error("{at}: expected a map")]
    NotMap { at: String },
    #[error("{at}: expected an array")]
    NotArray { at: String },
    #[error("{at}: expected a string")]
    NotText { at: String },
    /// A string that is not there or is something else (`id`, a node's `type`).
    #[error("{at}: required string")]
    RequiredText { at: String },
    #[error("{at}: unknown field")]
    UnknownField { at: String },
    #[error("{at}: expected a non-negative integer ({error})")]
    NotUint { at: String, error: IntError },
    /// A permission's name that is none.
    #[error("{at}: unknown permission {name}")]
    UnknownPerm { at: String, name: String },
    /// A permission's code that is none.
    #[error("{at}: permission out of range")]
    PermRange { at: String },
    /// An edge's end or an inner input that is not `<node>.<port>`; holds the text as written.
    #[error("{at}: expected \"<node>.<port>\", got {got:?}")]
    Endpoint { at: String, got: String },
    /// A node id that is not `[A-Za-z0-9_]+` (in every part, for an inner node).
    #[error("{at}: id must be [A-Za-z0-9_]+")]
    NodeId { at: String },
    /// `at` is the node.
    #[error("{at}.placement: only \"local\" is supported")]
    Placement { at: String },
    #[error("{at}: expected two strings")]
    EdgeNotText { at: String },
    #[error("{at}: expected [from, to]")]
    EdgeNotPair { at: String },

    // ----- `layout` -----
    #[error("{at}: {entries} entries > {MAX_LAYOUT}")]
    LayoutEntries { at: String, entries: usize },
    #[error("{at}: a key of {len} bytes > {MAX_LAYOUT_KEY}")]
    LayoutKey { at: String, len: usize },
    #[error("{at}: expected [x, y]")]
    LayoutPoint { at: String },

    // ----- the limits (spec 06 step 8) -----
    #[error("{at}: {count} nodes > {MAX_NODES}")]
    Nodes { at: String, count: usize },
    #[error("{at}: {count} edges > {MAX_EDGES}")]
    Edges { at: String, count: usize },
    #[error("nodes: more than {MAX_NODES} nodes with the custom blocks expanded")]
    ExpandedNodes,
    #[error("edges: more than {MAX_EDGES} edges with the custom blocks expanded")]
    ExpandedEdges,
    #[error("blocks: at most {MAX_BLOCKS}")]
    Blocks,

    // ----- a custom block (`blocks.<name>`) -----
    #[error("{at}: a block's name must be [A-Za-z0-9_]+")]
    BlockName { at: String },
    #[error("{at}: {count} instances of custom blocks > {MAX_BLOCK_INSTANCES}")]
    Instances { at: String, count: usize },
    /// An edge, an input or an output of the block names a node it does not have.
    #[error("{at}: {block} has no inner node {node}")]
    NoInnerNode {
        at: String,
        block: String,
        node: String,
    },
    /// More inputs, or outputs, than [`MAX_BLOCK_PORTS`].
    #[error("{at}: at most {MAX_BLOCK_PORTS}")]
    BlockPorts { at: String },
    /// `at` is the input or output.
    #[error("{at}.name: required, [A-Za-z0-9_]+")]
    PortName { at: String },
    #[error("{at}.name: {name} twice")]
    PortTwice { at: String, name: String },
    /// An item of an input's `to` that is no string.
    #[error("{at}: expected \"<node>.<port>\"")]
    InnerInput { at: String },
    /// An input's `to` that is none, empty or longer than [`MAX_BLOCK_FANOUT`].
    #[error("{at}: required, 1..={MAX_BLOCK_FANOUT} inner inputs \"<node>.<port>\"")]
    InnerInputs { at: String },
    #[error("{at}.name: {name} is an input (an input is an output of its name already)")]
    OutputIsInput { at: String, name: String },
    #[error("{at}.from: required \"<node>.<port>\"")]
    OutputFrom { at: String },
    /// Holds the block and the loop, from the block back to it.
    #[error("blocks.{block}: a custom block may not contain itself ({})", .lap.join(" → "))]
    InItself { block: String, lap: Vec<String> },

    // ----- an instance of a custom block; `node` is its id (`a1`, `a1/inner`) -----
    #[error("nodes.{node}.type: unknown custom block {block} (define it in blocks)")]
    UnknownBlock { node: String, block: String },
    #[error(
        "nodes.{node}: custom blocks nest at most {MAX_BLOCK_DEPTH} deep \
         (does {block} contain itself?)"
    )]
    TooDeep { node: String, block: String },
    #[error("nodes.{node}.{field}: unknown field (an instance of a custom block takes values)")]
    InstanceField { node: String, field: String },
    #[error("nodes.{node}.values: expected a map {{<input>: <value>}}")]
    InstanceValues { node: String },
    #[error("nodes.{node}.values.{input}: {block} has no input {input}")]
    NoBlockInput {
        node: String,
        block: String,
        input: String,
    },
    /// The constant of the input does not go into an inner input.
    #[error("nodes.{node}.values.{input}: {error}")]
    Constant {
        node: String,
        input: String,
        error: ConstantError,
    },
    /// An edge from an instance's output it does not have; `at` is the edge.
    #[error("{at}: {node} ({block}) has no output {port}")]
    InstanceOutput {
        at: String,
        node: String,
        block: String,
        port: String,
    },
    /// An edge into an instance's input it does not have; `at` is the edge.
    #[error("{at}: {node} ({block}) has no input {port}")]
    InstanceInput {
        at: String,
        node: String,
        block: String,
        port: String,
    },
    /// The walk from an instance's output to a plain one went past its bound.
    #[error("{at}: custom blocks nest too deep")]
    Walk { at: String },

    // ----- the fields of `~def` -----
    #[error("id: {0}")]
    Id(KeyError),
    #[error("enabled: expected true or false")]
    Enabled,
    #[error("{at}: drop_oldest | drop_newest | block")]
    Overflow { at: String },
    #[error("{at}: 1..=65536")]
    Queue { at: String },
    /// `permissions.maxperm` above write (spec 06 step 7: flows never do config operations).
    #[error("permissions.maxperm: at most write")]
    MaxPermConfig,

    // ----- the checks of the expanded definition (steps 2–8) -----
    #[error("nodes.{node}: a node and a custom block share the id")]
    SharedId { node: String },
    /// A node's config is refused (step 3).
    #[error("nodes.{node}: {error}")]
    Node { node: String, error: ConfigError },
    /// `at` is the edge.
    #[error("{at}: unknown node {node}")]
    UnknownNode { at: String, node: String },
    #[error("{at}: {node} has no output {port}")]
    NoOutput {
        at: String,
        node: String,
        port: String,
    },
    #[error("{at}: {node} has no input {port}")]
    NoInput {
        at: String,
        node: String,
        port: String,
    },
    /// The types of an edge's two ends do not fit.
    #[error(
        "{at}: {}.{} ({}) does not fit {}.{} ({})",
        .from.node, .from.port, .from_type.name(), .to.node, .to.port, .to_type.name()
    )]
    NoFit {
        at: String,
        from: Endpoint,
        from_type: PortType,
        to: Endpoint,
        to_type: PortType,
    },
    /// A read field driven by a port without its scope (ADR 0040 §1).
    #[error(
        "nodes.{node}.{scope}: required when in.{field} is wired (the keys it may \
         read, as downstream/<link>/**)"
    )]
    NoScope {
        node: String,
        field: &'static str,
        scope: &'static str,
    },
    /// Holds the loop, from a node back to it (step 5).
    #[error("edges: cycle {} (only a delay node may close a loop)", .cycle.join(" → "))]
    Cycle { cycle: Vec<String> },
    /// A node's script does not compile (step 6); the error names its field.
    #[error("nodes.{node}.{error}")]
    Script { node: String, error: ConfigError },
    /// `maxperm` below what a command sink needs (step 7): the code and the name, as a code
    /// read as a name (2 for write) misleads.
    #[error(
        "permissions.maxperm: {} ({}) < {} ({}) needed by nodes.{node} ({ty}); \
         the codes are 0 none, 1 list, 2 read, 3 write, or give the name",
        .maxperm.code(), .maxperm.name(), .need.code(), .need.name()
    )]
    MaxPerm {
        maxperm: Perm,
        need: Perm,
        node: String,
        ty: String,
    },
    /// A `publish` inside a custom block used more than once (ADR 0040 §3).
    #[error(
        "nodes.{node}.node: {name} is published by {other} too (a custom block \
         with a publish can be used once)"
    )]
    PublishedTwice {
        node: String,
        name: String,
        other: String,
    },
    #[error("nodes: window.max_samples total {total} > {MAX_WINDOW_SAMPLES}")]
    WindowSamples { total: u64 },

    // ----- the host's checks (`engine`) -----
    /// A `wasm` node's config, or its artifact, is refused; the error names its field.
    #[error("nodes.{node}.{error}")]
    Wasm { node: String, error: ConfigError },
    /// A source's scope is none; `param` is the config key (`key_scope`, …).
    #[error("nodes.{node}.{param}: {error}")]
    Scope {
        node: String,
        param: &'static str,
        error: ScopeError,
    },
    /// A source names a key outside this site's sections (security review FLOW-1).
    #[error(
        "nodes.{node}.{param}: a source reads this site's downstream, dataflows or storage only \
         (wy/{site}/downstream/…), not {full}"
    )]
    SourceOutside {
        node: String,
        param: &'static str,
        site: String,
        full: String,
    },
}

pub type Result<T> = core::result::Result<T, DefError>;

impl DefError {
    fn not_map(at: impl Into<String>) -> Self {
        Self::NotMap { at: at.into() }
    }

    fn not_array(at: impl Into<String>) -> Self {
        Self::NotArray { at: at.into() }
    }

    fn not_text(at: impl Into<String>) -> Self {
        Self::NotText { at: at.into() }
    }

    fn required_text(at: impl Into<String>) -> Self {
        Self::RequiredText { at: at.into() }
    }

    fn unknown_field(at: impl Into<String>) -> Self {
        Self::UnknownField { at: at.into() }
    }

    fn node_id(at: impl Into<String>) -> Self {
        Self::NodeId { at: at.into() }
    }

    fn too_many_nodes(at: impl Into<String>, count: usize) -> Self {
        Self::Nodes {
            at: at.into(),
            count,
        }
    }

    fn too_many_edges(at: impl Into<String>, count: usize) -> Self {
        Self::Edges {
            at: at.into(),
            count,
        }
    }
}

pub type Map = BTreeMap<String, Value>;

wyrm_core::name_enum! {
    /// What a full queue does with the next sample (`policy.overflow`).
    pub enum Overflow as "overflow" {
        DropOldest => "drop_oldest",
        DropNewest => "drop_newest",
        Block => "block",
    }
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
    /// The nodes that run: the instances of custom blocks are replaced by their inner nodes
    /// (`<instance>/<inner>`).
    pub nodes: BTreeMap<String, NodeDef>,
    pub edges: Vec<Edge>,
    /// Where each edge of `edges` was written, for the compiler's messages (`edges[3]`,
    /// `blocks.avg.edges[0] in a1`).
    pub edge_at: Vec<String>,
    /// The instances of custom blocks: instance id (`a1`, `a1/inner`) → block name.
    pub instances: BTreeMap<String, String>,
    pub policy: Policy,
    pub maxperm: Perm,
    /// As received (CBOR map), for `~def` and storage.
    pub raw: Value,
}

/// The type prefix of an instance of a custom block: `block:<name>`.
pub const BLOCK_PREFIX: &str = "block:";
/// Custom blocks of one definition at most.
pub const MAX_BLOCKS: usize = 64;
/// Inputs, and outputs, of one custom block at most.
pub const MAX_BLOCK_PORTS: usize = 64;
/// Inner inputs one input of a custom block feeds at most.
pub const MAX_BLOCK_FANOUT: usize = 16;
/// A custom block inside a custom block inside …: this deep at most.
pub const MAX_BLOCK_DEPTH: usize = 4;
/// Instances of other custom blocks inside one custom block at most.
pub const MAX_BLOCK_INSTANCES: usize = 64;
/// Edges of one flow at most, with the custom blocks expanded (spec 06 step 8). A definition
/// is compiled for `validate` and `preview` at level `read`, so the whole expansion is charged
/// against [`MAX_NODES`] and this limit while it is made: a block that multiplies (instances in
/// instances, an input that fans out at every level) is refused after bounded work.
pub const MAX_EDGES: usize = 4 * MAX_NODES;

/// A node as written: its type and its own keys.
type RawNode = (String, Map);

/// One input of a custom block: a field of every instance.
#[derive(Debug, Clone, PartialEq)]
pub struct BlockInput {
    pub name: String,
    /// The inner inputs it feeds.
    pub to: Vec<Endpoint>,
    /// Its constant when an instance gives none.
    pub default: Option<Value>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct BlockOutput {
    pub name: String,
    /// The inner output it repeats.
    pub from: Endpoint,
}

/// A custom block: a sub-flow with named inputs and outputs.
#[derive(Debug, Clone, PartialEq)]
pub struct BlockDef {
    pub description: Option<String>,
    pub inputs: Vec<BlockInput>,
    pub outputs: Vec<BlockOutput>,
    nodes: BTreeMap<String, RawNode>,
    edges: Vec<Edge>,
}

/// Total `window.max_samples` allowed per flow.
pub const MAX_WINDOW_SAMPLES: u64 = 100_000;
/// Nodes of one flow at most (spec 06 step 8): each is a task and an inbox at run time, in a
/// deployed flow and in a preview alike (ADR 0038 §5).
pub const MAX_NODES: usize = 1000;

fn as_map<'a>(v: &'a Value, path: &str) -> Result<&'a Map> {
    match v {
        Value::Map(m) => Ok(m),
        _ => Err(DefError::not_map(path)),
    }
}

fn uint(v: &Value, path: &str) -> Result<u64> {
    match v.to_int() {
        Ok(n) => Ok(n),
        Err(error) => Err(DefError::NotUint {
            at: path.into(),
            error,
        }),
    }
}

fn perm(v: &Value, path: &str) -> Result<Perm> {
    match v {
        Value::Str(s) => Perm::from_name(s).ok_or_else(|| DefError::UnknownPerm {
            at: path.into(),
            name: s.clone(),
        }),
        v => Perm::try_from(u8::try_from(uint(v, path)?).unwrap_or(u8::MAX))
            .map_err(|_| DefError::PermRange { at: path.into() }),
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
        _ => Err(DefError::Endpoint {
            at: path.into(),
            got: s.into(),
        }),
    }
}

/// `nodes`: `{<id>: {type, …config}}`.
fn parse_nodes(v: Option<&Value>, at: &str) -> Result<BTreeMap<String, RawNode>> {
    let mut nodes = BTreeMap::new();
    let Some(v) = v else { return Ok(nodes) };
    for (nid, nv) in as_map(v, at)? {
        let path = format!("{at}.{nid}");
        if nid.contains('/') {
            return Err(DefError::node_id(path));
        }
        let mut cfg = as_map(nv, &path)?.clone();
        let ty = match cfg.remove("type") {
            Some(Value::Str(t)) => t,
            _ => return Err(DefError::required_text(format!("{path}.type"))),
        };
        match cfg.remove("placement") {
            None => {}
            Some(Value::Str(p)) if p == "local" => {}
            Some(_) => return Err(DefError::Placement { at: path }),
        }
        nodes.insert(nid.clone(), (ty, cfg));
    }
    Ok(nodes)
}

/// `edges`: `[[from, to], …]`.
fn parse_edges(v: Option<&Value>, at: &str) -> Result<Vec<Edge>> {
    let mut edges = Vec::new();
    let Some(ev) = v else { return Ok(edges) };
    let Value::Array(items) = ev else {
        return Err(DefError::not_array(at));
    };
    for (i, e) in items.iter().enumerate() {
        let path = format!("{at}[{i}]");
        match e {
            Value::Array(pair) if pair.len() == 2 => match (&pair[0], &pair[1]) {
                (Value::Str(a), Value::Str(b)) => edges.push(Edge {
                    from: endpoint(a, &path)?,
                    to: endpoint(b, &path)?,
                }),
                _ => return Err(DefError::EdgeNotText { at: path }),
            },
            _ => return Err(DefError::EdgeNotPair { at: path }),
        }
    }
    Ok(edges)
}

/// Entries of one `layout` at most (spec 06 0.2.26).
pub const MAX_LAYOUT: usize = 16_384;
/// The longest key of a `layout`, bytes.
pub const MAX_LAYOUT_KEY: usize = 256;

/// `layout`: `{<key>: [a, b]}` (spec 06 0.2.5, 0.2.26). A key is a node id, or an editor's
/// own key `<node>~<name>~<rest>` (`~` cannot be in a node id; the Studio editor keeps a
/// block's pin choices as `<node>~pin~<field>`). The engine reads none of it: a key need not
/// name a node the flow has. It is bounded, as it is stored with every version.
fn check_layout(v: Option<&Value>, at: &str) -> Result<()> {
    let Some(l) = v else { return Ok(()) };
    let l = as_map(l, at)?;
    if l.len() > MAX_LAYOUT {
        return Err(DefError::LayoutEntries {
            at: at.into(),
            entries: l.len(),
        });
    }
    for (n, xy) in l {
        if n.len() > MAX_LAYOUT_KEY {
            return Err(DefError::LayoutKey {
                at: at.into(),
                len: n.len(),
            });
        }
        match xy {
            Value::Array(a)
                if a.len() == 2 && a.iter().all(|v| v.as_f64().is_some_and(f64::is_finite)) => {}
            _ => {
                return Err(DefError::LayoutPoint {
                    at: format!("{at}.{n}"),
                })
            }
        }
    }
    Ok(())
}

fn text(v: Option<&Value>, at: &str) -> Result<Option<String>> {
    match v {
        None => Ok(None),
        Some(Value::Str(s)) => Ok(Some(s.clone())),
        Some(_) => Err(DefError::not_text(at)),
    }
}

/// One custom block of `blocks` (ADR 0040 §3): its shape, and that its inputs, outputs and
/// edges name inner nodes it has. The inner nodes' types and ports are checked where the
/// block is used.
pub fn parse_block(name: &str, v: &Value) -> Result<BlockDef> {
    let at = format!("blocks.{name}");
    if !node_id_ok(name) {
        return Err(DefError::BlockName { at });
    }
    let m = as_map(v, &at)?;
    const KNOWN: &[&str] = &[
        "description",
        "inputs",
        "outputs",
        "nodes",
        "edges",
        "layout",
    ];
    if let Some(k) = m.keys().find(|k| !KNOWN.contains(&k.as_str())) {
        return Err(DefError::unknown_field(format!("{at}.{k}")));
    }
    let nodes = parse_nodes(m.get("nodes"), &format!("{at}.nodes"))?;
    for id in nodes.keys() {
        if !node_id_ok(id) {
            return Err(DefError::node_id(format!("{at}.nodes.{id}")));
        }
    }
    if nodes.len() > MAX_NODES {
        return Err(DefError::too_many_nodes(format!("{at}.nodes"), nodes.len()));
    }
    let uses = nodes
        .values()
        .filter(|(ty, _)| ty.starts_with(BLOCK_PREFIX))
        .count();
    if uses > MAX_BLOCK_INSTANCES {
        return Err(DefError::Instances {
            at: format!("{at}.nodes"),
            count: uses,
        });
    }
    let edges = parse_edges(m.get("edges"), &format!("{at}.edges"))?;
    if edges.len() > MAX_EDGES {
        return Err(DefError::too_many_edges(format!("{at}.edges"), edges.len()));
    }
    check_layout(m.get("layout"), &format!("{at}.layout"))?;
    let block = BlockShape {
        name,
        at: &at,
        m,
        nodes: &nodes,
    };
    for (i, e) in edges.iter().enumerate() {
        block.inner(&e.from, &format!("{at}.edges[{i}]"))?;
        block.inner(&e.to, &format!("{at}.edges[{i}]"))?;
    }
    let inputs = block.block_inputs()?;
    let outputs = block.block_outputs(&inputs)?;
    Ok(BlockDef {
        description: text(m.get("description"), &format!("{at}.description"))?,
        inputs,
        outputs,
        nodes,
        edges,
    })
}

/// A custom block being read: its name, its path in `~def`, its fields and its inner nodes.
struct BlockShape<'a> {
    name: &'a str,
    at: &'a str,
    m: &'a Map,
    nodes: &'a BTreeMap<String, RawNode>,
}

impl<'a> BlockShape<'a> {
    /// That an endpoint names an inner node of the block.
    fn inner(&self, e: &Endpoint, path: &str) -> Result<()> {
        if self.nodes.contains_key(&e.node) {
            Ok(())
        } else {
            Err(DefError::NoInnerNode {
                at: path.into(),
                block: self.name.into(),
                node: e.node.clone(),
            })
        }
    }

    /// `inputs` or `outputs`: lists, so an editor draws them in their order. Each item with
    /// its name, its map and its path.
    fn ports(&self, key: &str) -> Result<Vec<(String, &'a Map, String)>> {
        let at = self.at;
        let list = match self.m.get(key) {
            None => return Ok(Vec::new()),
            Some(Value::Array(a)) => a,
            Some(_) => return Err(DefError::not_array(format!("{at}.{key}"))),
        };
        if list.len() > MAX_BLOCK_PORTS {
            return Err(DefError::BlockPorts {
                at: format!("{at}.{key}"),
            });
        }
        let mut out: Vec<(String, &Map, String)> = Vec::new();
        for (i, item) in list.iter().enumerate() {
            let path = format!("{at}.{key}[{i}]");
            let pm = as_map(item, &path)?;
            let pname = match pm.get("name") {
                Some(Value::Str(n)) if node_id_ok(n) => n.clone(),
                _ => return Err(DefError::PortName { at: path }),
            };
            if out.iter().any(|(n, _, _)| *n == pname) {
                return Err(DefError::PortTwice {
                    at: path,
                    name: pname,
                });
            }
            text(pm.get("description"), &format!("{path}.description"))?;
            out.push((pname, pm, path));
        }
        Ok(out)
    }

    /// `inputs`: each one's name, the inner inputs it feeds and its default.
    fn block_inputs(&self) -> Result<Vec<BlockInput>> {
        let mut inputs = Vec::new();
        for (pname, pm, path) in self.ports("inputs")? {
            if let Some(k) = pm
                .keys()
                .find(|k| !["name", "to", "default", "description"].contains(&k.as_str()))
            {
                return Err(DefError::unknown_field(format!("{path}.{k}")));
            }
            let to_at = format!("{path}.to");
            let to: Vec<Endpoint> = match pm.get("to") {
                Some(Value::Str(one)) => vec![endpoint(one, &to_at)?],
                Some(Value::Array(a)) if !a.is_empty() && a.len() <= MAX_BLOCK_FANOUT => a
                    .iter()
                    .map(|v| match v {
                        Value::Str(x) => endpoint(x, &to_at),
                        _ => Err(DefError::InnerInput { at: to_at.clone() }),
                    })
                    .collect::<Result<_>>()?,
                _ => return Err(DefError::InnerInputs { at: to_at }),
            };
            for t in &to {
                self.inner(t, &to_at)?;
            }
            inputs.push(BlockInput {
                name: pname,
                to,
                default: pm.get("default").filter(|v| **v != Value::Null).cloned(),
            });
        }
        Ok(inputs)
    }

    /// `outputs`: each one's name and the inner output it comes from; no name of an input.
    fn block_outputs(&self, inputs: &[BlockInput]) -> Result<Vec<BlockOutput>> {
        let mut outputs = Vec::new();
        for (pname, pm, path) in self.ports("outputs")? {
            if let Some(k) = pm
                .keys()
                .find(|k| !["name", "from", "description"].contains(&k.as_str()))
            {
                return Err(DefError::unknown_field(format!("{path}.{k}")));
            }
            if inputs.iter().any(|i| i.name == pname) {
                return Err(DefError::OutputIsInput {
                    at: path,
                    name: pname,
                });
            }
            let from = match pm.get("from") {
                Some(Value::Str(x)) => endpoint(x, &format!("{path}.from"))?,
                _ => return Err(DefError::OutputFrom { at: path }),
            };
            self.inner(&from, &format!("{path}.from"))?;
            outputs.push(BlockOutput { name: pname, from });
        }
        Ok(outputs)
    }
}

impl BlockDef {
    /// The names of the custom blocks its inner nodes are instances of.
    pub fn uses(&self) -> BTreeSet<String> {
        self.nodes
            .values()
            .filter_map(|(ty, _)| ty.strip_prefix(BLOCK_PREFIX))
            .map(str::to_owned)
            .collect()
    }
}

/// An instance of a custom block, while the definition is expanded.
struct Instance {
    block: String,
    inputs: BTreeMap<String, Vec<Endpoint>>,
    outputs: BTreeMap<String, Endpoint>,
}

/// Replaces the instances of custom blocks by their inner nodes.
struct Expander<'a> {
    blocks: &'a BTreeMap<String, BlockDef>,
    nodes: BTreeMap<String, RawNode>,
    /// Every edge as written, with full node ids, and where it was written.
    edges: Vec<(Edge, String)>,
    instances: BTreeMap<String, Instance>,
}

/// No custom block holds itself, directly or through others: checked on the definitions,
/// before anything is expanded. The error names the loop.
fn check_no_recursion(blocks: &BTreeMap<String, BlockDef>) -> Result<()> {
    fn visit<'a>(
        name: &'a str,
        blocks: &'a BTreeMap<String, BlockDef>,
        path: &mut Vec<&'a str>,
        done: &mut BTreeSet<&'a str>,
    ) -> Result<()> {
        if done.contains(name) {
            return Ok(());
        }
        if let Some(pos) = path.iter().position(|p| *p == name) {
            let mut lap: Vec<String> = path[pos..].iter().map(|p| (*p).to_owned()).collect();
            lap.push(name.to_owned());
            return Err(DefError::InItself {
                block: name.to_owned(),
                lap,
            });
        }
        let Some(def) = blocks.get(name) else {
            return Ok(()); // an unknown block is reported where it is used
        };
        path.push(name);
        for (ty, _) in def.nodes.values() {
            if let Some(used) = ty.strip_prefix(BLOCK_PREFIX) {
                if let Some((used, _)) = blocks.get_key_value(used) {
                    visit(used, blocks, path, done)?;
                }
            }
        }
        path.pop();
        done.insert(name);
        Ok(())
    }
    let mut done = BTreeSet::new();
    for name in blocks.keys() {
        visit(name, blocks, &mut Vec::new(), &mut done)?;
    }
    Ok(())
}

impl Expander<'_> {
    /// The nodes and edges of one level: the definition itself (`prefix` empty) or the
    /// inside of the instance `prefix` (`a1/`).
    fn graph(
        &mut self,
        prefix: &str,
        nodes: BTreeMap<String, RawNode>,
        edges: &[Edge],
        edges_at: &str,
        depth: usize,
    ) -> Result<()> {
        let within = |e: &Endpoint| Endpoint {
            node: format!("{prefix}{}", e.node),
            port: e.port.clone(),
        };
        for (id, (ty, cfg)) in nodes {
            let path = format!("{prefix}{id}");
            // every node and every instance, at every depth, is charged against the limit
            // while the definition is expanded: a block that multiplies stops here
            if self.nodes.len() + self.instances.len() >= MAX_NODES {
                return Err(DefError::ExpandedNodes);
            }
            let Some(name) = ty.strip_prefix(BLOCK_PREFIX) else {
                self.nodes.insert(path, (ty, cfg));
                continue;
            };
            let blocks = self.blocks;
            let def = blocks.get(name).ok_or_else(|| DefError::UnknownBlock {
                node: path.clone(),
                block: name.to_owned(),
            })?;
            if depth >= MAX_BLOCK_DEPTH {
                return Err(DefError::TooDeep {
                    node: path,
                    block: name.to_owned(),
                });
            }
            if let Some(k) = cfg.keys().find(|k| *k != "values") {
                return Err(DefError::InstanceField {
                    node: path,
                    field: k.clone(),
                });
            }
            let values = match cfg.get("values") {
                None => Map::new(),
                Some(Value::Map(m)) => m.clone(),
                Some(_) => return Err(DefError::InstanceValues { node: path }),
            };
            if let Some(k) = values
                .keys()
                .find(|k| def.inputs.iter().all(|i| i.name != **k))
            {
                return Err(DefError::NoBlockInput {
                    node: path,
                    block: name.to_owned(),
                    input: k.clone(),
                });
            }
            // an input's constant becomes the constant of every inner input it feeds
            let mut inner = def.nodes.clone();
            for input in &def.inputs {
                let constant = values
                    .get(&input.name)
                    .filter(|v| **v != Value::Null)
                    .or(input.default.as_ref());
                let Some(v) = constant else { continue };
                for t in &input.to {
                    constant_into(&mut inner, t, v).map_err(|error| DefError::Constant {
                        node: path.clone(),
                        input: input.name.clone(),
                        error,
                    })?;
                }
            }
            let inside = format!("{path}/");
            let full = |e: &Endpoint| Endpoint {
                node: format!("{inside}{}", e.node),
                port: e.port.clone(),
            };
            self.instances.insert(
                path.clone(),
                Instance {
                    block: name.to_owned(),
                    inputs: def
                        .inputs
                        .iter()
                        .map(|i| (i.name.clone(), i.to.iter().map(full).collect()))
                        .collect(),
                    outputs: def
                        .outputs
                        .iter()
                        .map(|o| (o.name.clone(), full(&o.from)))
                        .collect(),
                },
            );
            self.graph(
                &inside,
                inner,
                &def.edges,
                &format!("blocks.{name}.edges"),
                depth + 1,
            )?;
        }
        if self.edges.len() + edges.len() > MAX_EDGES {
            return Err(DefError::ExpandedEdges);
        }
        for (i, e) in edges.iter().enumerate() {
            let at = if prefix.is_empty() {
                format!("{edges_at}[{i}]")
            } else {
                format!("{edges_at}[{i}] in {}", prefix.trim_end_matches('/'))
            };
            self.edges.push((
                Edge {
                    from: within(&e.from),
                    to: within(&e.to),
                },
                at,
            ));
        }
        Ok(())
    }

    /// The plain output an edge from `e` reads: an instance's output is the inner output
    /// it repeats; an instance's input is the echo of the first inner input it feeds.
    fn source(&self, e: &Endpoint, at: &str) -> Result<Endpoint> {
        let mut e = e.clone();
        // every step goes one level in: the depth bounds the walk
        for _ in 0..=2 * MAX_BLOCK_DEPTH {
            let Some(inst) = self.instances.get(&e.node) else {
                return Ok(e);
            };
            if let Some(o) = inst.outputs.get(&e.port) {
                e = o.clone();
            } else if let Some(t) = inst.inputs.get(&e.port).and_then(|to| to.first()) {
                if self.instances.contains_key(&t.node) {
                    e = t.clone();
                } else {
                    let ty = self.nodes.get(&t.node).map_or("", |(ty, _)| ty.as_str());
                    return Ok(Endpoint {
                        node: t.node.clone(),
                        port: crate::catalog::echo_of(ty, &t.port),
                    });
                }
            } else {
                return Err(DefError::InstanceOutput {
                    at: at.into(),
                    node: e.node,
                    block: inst.block.clone(),
                    port: e.port,
                });
            }
        }
        Err(DefError::Walk { at: at.into() })
    }

    /// The plain inputs an edge into `e` feeds, added to `out`. `room`: how many edges the
    /// flow may still get; an input that fans out at every level stops when it is used up.
    fn targets(&self, e: &Endpoint, at: &str, out: &mut Vec<Endpoint>, room: usize) -> Result<()> {
        let Some(inst) = self.instances.get(&e.node) else {
            if out.len() >= room {
                return Err(DefError::ExpandedEdges);
            }
            out.push(e.clone());
            return Ok(());
        };
        let to = inst
            .inputs
            .get(&e.port)
            .ok_or_else(|| DefError::InstanceInput {
                at: at.into(),
                node: e.node.clone(),
                block: inst.block.clone(),
                port: e.port.clone(),
            })?;
        for t in to {
            self.targets(t, at, out, room)?;
        }
        Ok(())
    }
}

/// Why a constant of a custom block's input does not go into an inner input.
#[derive(Debug, thiserror::Error)]
pub enum ConstantError {
    /// Holds the inner node.
    #[error("no inner node {0}")]
    NoInner(String),
    /// The inner node's `key` (`values`, `args`) is there and is no map.
    #[error("{node}.{key}: expected a map")]
    NotMap { node: String, key: String },
    #[error("{node}.{port} takes no constant: wire the input instead")]
    TakesNone { node: String, port: String },
}

/// Gives the inner input `t` the constant `v`: an instance's own constant (`values`), a
/// parameter's config, an operand's constant (`values`, spec 06 0.2.19), an argument of an
/// `invoke`, a variable's `value`.
fn constant_into(
    inner: &mut BTreeMap<String, RawNode>,
    t: &Endpoint,
    v: &Value,
) -> core::result::Result<(), ConstantError> {
    use crate::catalog::ConstAt;
    let Some((ty, cfg)) = inner.get_mut(&t.node) else {
        return Err(ConstantError::NoInner(t.node.clone()));
    };
    let mut put = |key: &str, name: &str| match cfg
        .entry(key.to_owned())
        .or_insert_with(|| Value::Map(Map::new()))
    {
        Value::Map(m) => {
            m.insert(name.to_owned(), v.clone());
            Ok(())
        }
        _ => Err(ConstantError::NotMap {
            node: t.node.clone(),
            key: key.to_owned(),
        }),
    };
    if ty.starts_with(BLOCK_PREFIX) {
        return put("values", &t.port);
    }
    match crate::catalog::const_at(ty, &t.port) {
        Some(ConstAt::Param(p)) => {
            cfg.insert(p.to_owned(), v.clone());
            Ok(())
        }
        Some(ConstAt::Operand) => put("values", &t.port),
        Some(ConstAt::Arg(a)) => put("args", &a),
        None => Err(ConstantError::TakesNone {
            node: t.node.clone(),
            port: t.port.clone(),
        }),
    }
}

/// Step 1: schema. Returns the typed definition, with its custom blocks expanded.
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
        "layout",
        "blocks",
    ];
    if let Some(k) = m.keys().find(|k| !KNOWN.contains(&k.as_str())) {
        return Err(DefError::unknown_field(k));
    }
    let id = match m.get("id") {
        Some(Value::Str(s)) => s.clone(),
        _ => return Err(DefError::required_text("id")),
    };
    wyrm_core::keyspace::validate_segment(&id).map_err(DefError::Id)?;
    let version = uint(m.get("version").unwrap_or(&Value::UInt(0)), "version")?;
    let enabled = match m.get("enabled") {
        None => true,
        Some(Value::Bool(b)) => *b,
        Some(_) => return Err(DefError::Enabled),
    };
    let description = match m.get("description") {
        None => None,
        Some(Value::Str(s)) => Some(s.clone()),
        Some(_) => return Err(DefError::not_text("description")),
    };
    // Where an editor draws each node (spec 06 0.2.5): `{<node>: [x, y]}`.
    // Not part of a node, so moving one keeps its state on a hot swap.
    check_layout(m.get("layout"), "layout")?;
    let mut blocks = BTreeMap::new();
    if let Some(bv) = m.get("blocks") {
        let bm = as_map(bv, "blocks")?;
        if bm.len() > MAX_BLOCKS {
            return Err(DefError::Blocks);
        }
        for (name, def) in bm {
            blocks.insert(name.clone(), parse_block(name, def)?);
        }
    }
    check_no_recursion(&blocks)?;
    let top = parse_nodes(m.get("nodes"), "nodes")?;
    // step 8's limits, taken here already: nothing is expanded beyond them
    if top.len() > MAX_NODES {
        return Err(DefError::too_many_nodes("nodes", top.len()));
    }
    let top_edges = parse_edges(m.get("edges"), "edges")?;
    if top_edges.len() > MAX_EDGES {
        return Err(DefError::too_many_edges("edges", top_edges.len()));
    }
    let mut x = Expander {
        blocks: &blocks,
        nodes: BTreeMap::new(),
        edges: Vec::new(),
        instances: BTreeMap::new(),
    };
    x.graph("", top, &top_edges, "edges", 0)?;
    let (mut edges, mut edge_at) = (Vec::new(), Vec::new());
    for (e, at) in &x.edges {
        let from = x.source(&e.from, at)?;
        let mut to = Vec::new();
        x.targets(&e.to, at, &mut to, MAX_EDGES - edges.len())?;
        for to in to {
            edges.push(Edge {
                from: from.clone(),
                to,
            });
            edge_at.push(at.clone());
        }
    }
    let instances = x
        .instances
        .iter()
        .map(|(id, i)| (id.clone(), i.block.clone()))
        .collect();
    let nodes = x
        .nodes
        .into_iter()
        .map(|(nid, (ty, cfg))| {
            let mut bytes = ty.as_bytes().to_vec();
            bytes.extend(wyrm_core::codec::value_to_vec(&Value::Map(cfg.clone())));
            let hash = crc32c::crc32c(&bytes);
            (nid, NodeDef { ty, cfg, hash })
        })
        .collect();
    let policy = parse_policy(m)?;
    let maxperm = parse_permissions(m)?;
    Ok(FlowDef {
        id,
        version,
        enabled,
        description,
        nodes,
        edges,
        edge_at,
        instances,
        policy,
        maxperm,
        raw: v.clone(),
    })
}

/// `policy` (spec 06): how a flow queues samples, flushes its state and restarts.
fn parse_policy(m: &Map) -> Result<Policy> {
    let mut policy = Policy::default();
    if let Some(pv) = m.get("policy") {
        let pm = as_map(pv, "policy")?;
        for (k, v) in pm {
            let path = format!("policy.{k}");
            match k.as_str() {
                "overflow" => {
                    policy.overflow = match v {
                        Value::Str(s) => Overflow::from_name(s),
                        _ => None,
                    }
                    .ok_or_else(|| DefError::Overflow { at: path.clone() })?;
                }
                "queue" => {
                    let q = uint(v, &path)?;
                    if !(1..=65_536).contains(&q) {
                        return Err(DefError::Queue { at: path });
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
                _ => return Err(DefError::unknown_field(path)),
            }
        }
    }
    Ok(policy)
}

/// `permissions` (spec 06): the most a flow may do, never more than `write`.
fn parse_permissions(m: &Map) -> Result<Perm> {
    let mut maxperm = Perm::Read;
    if let Some(pv) = m.get("permissions") {
        let pm = as_map(pv, "permissions")?;
        for (k, v) in pm {
            match k.as_str() {
                "maxperm" => {
                    maxperm = perm(v, "permissions.maxperm")?;
                    // spec 06 step 7: flows never do config operations
                    if maxperm > Perm::Write {
                        return Err(DefError::MaxPermConfig);
                    }
                }
                "token" => {}
                _ => return Err(DefError::unknown_field(format!("permissions.{k}"))),
            }
        }
    }
    Ok(maxperm)
}

/// Steps 2–8. Returns the port map of every node.
pub fn check(def: &FlowDef) -> Result<BTreeMap<String, Ports>> {
    // 2. ids
    // an inner node of a custom block has the id `<instance>/<inner>`
    for id in def.nodes.keys().chain(def.instances.keys()) {
        if !id.split('/').all(node_id_ok) {
            return Err(DefError::node_id(format!("nodes.{id}")));
        }
    }
    if let Some(id) = def.instances.keys().find(|i| def.nodes.contains_key(*i)) {
        return Err(DefError::SharedId { node: id.clone() });
    }
    // 3. types and configs
    let mut ports = BTreeMap::new();
    for (id, n) in &def.nodes {
        let p = nodes::ports(&n.ty, &n.cfg).map_err(|error| DefError::Node {
            node: id.clone(),
            error,
        })?;
        ports.insert(id.clone(), p);
    }
    // 4. edges → existing ports, compatible types
    for (i, e) in def.edges.iter().enumerate() {
        let path = def
            .edge_at
            .get(i)
            .cloned()
            .unwrap_or_else(|| format!("edges[{i}]"));
        let from = ports
            .get(&e.from.node)
            .ok_or_else(|| DefError::UnknownNode {
                at: path.clone(),
                node: e.from.node.clone(),
            })?;
        let to = ports.get(&e.to.node).ok_or_else(|| DefError::UnknownNode {
            at: path.clone(),
            node: e.to.node.clone(),
        })?;
        let ft = from
            .output(&e.from.port)
            .ok_or_else(|| DefError::NoOutput {
                at: path.clone(),
                node: e.from.node.clone(),
                port: e.from.port.clone(),
            })?;
        let tt = to.input(&e.to.port).ok_or_else(|| DefError::NoInput {
            at: path.clone(),
            node: e.to.node.clone(),
            port: e.to.port.clone(),
        })?;
        if !ft.fits(tt) {
            return Err(DefError::NoFit {
                at: path,
                from: e.from.clone(),
                from_type: ft,
                to: e.to.clone(),
                to_type: tt,
            });
        }
    }
    // 4a. a read field that a port drives needs its scope (ADR 0040 §1)
    for e in &def.edges {
        let Some(n) = def.nodes.get(&e.to.node) else {
            continue;
        };
        for &(field, scope) in nodes::read_fields(&n.ty) {
            if e.to.port == format!("in.{field}") && !n.cfg.contains_key(scope) {
                return Err(DefError::NoScope {
                    node: e.to.node.clone(),
                    field,
                    scope,
                });
            }
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
            return Err(DefError::Cycle { cycle });
        }
    }
    // 6. rhai compiles (expression, filter)
    for (id, n) in &def.nodes {
        nodes::check_script(&n.ty, &n.cfg).map_err(|error| DefError::Script {
            node: id.clone(),
            error,
        })?;
    }
    // 7. maxperm covers every command sink
    for (id, n) in &def.nodes {
        if let Some(need) = nodes::needs_perm(&n.ty) {
            if def.maxperm < need {
                return Err(DefError::MaxPerm {
                    maxperm: def.maxperm,
                    need,
                    node: id.clone(),
                    ty: n.ty.clone(),
                });
            }
        }
    }
    // 7a. a `publish` inside a custom block has one name in every instance (ADR 0040 §3)
    let mut published: BTreeMap<&str, &str> = BTreeMap::new();
    for (id, n) in def.nodes.iter().filter(|(_, n)| n.ty == "publish") {
        let Some(Value::Str(name)) = n.cfg.get("node") else {
            continue;
        };
        if let Some(other) = published.insert(name, id) {
            if id.contains('/') || other.contains('/') {
                return Err(DefError::PublishedTwice {
                    node: id.clone(),
                    name: name.clone(),
                    other: (*other).to_owned(),
                });
            }
        }
    }
    // 8. memory limits
    if def.nodes.len() > MAX_NODES {
        return Err(DefError::too_many_nodes("nodes", def.nodes.len()));
    }
    let samples: u64 = def
        .nodes
        .values()
        .filter(|n| n.ty == "window")
        .map(|n| nodes::max_samples(&n.cfg).unwrap_or(u64::MAX))
        .fold(0u64, u64::saturating_add);
    if samples > MAX_WINDOW_SAMPLES {
        return Err(DefError::WindowSamples { total: samples });
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

#[cfg(test)]
mod tests {
    use super::*;

    /// A constant for an inner node that is not there (the compiler checks the node first, so
    /// only this function says it). Audit T7: the text it had as a `String`.
    #[test]
    fn a_constant_for_no_inner_node_keeps_its_text() {
        let mut inner = BTreeMap::new();
        let to = Endpoint {
            node: "gone".into(),
            port: "in".into(),
        };
        let e = constant_into(&mut inner, &to, &Value::UInt(1)).map_err(|e| e.to_string());
        assert_eq!(e, Err("no inner node gone".to_owned()));
    }

    /// An edge from an instance's output that leads back to itself: the walk of
    /// [`Expander::source`] stops after its bound. The checks before it (the depth of the
    /// blocks, no block in itself) keep every definition from getting here, so only this test
    /// says it. Audit T7: the text it had as a `String`.
    #[test]
    fn a_walk_past_the_depth_keeps_its_text() {
        let blocks = BTreeMap::new();
        let a = Endpoint {
            node: "a".into(),
            port: "o".into(),
        };
        let x = Expander {
            blocks: &blocks,
            nodes: BTreeMap::new(),
            edges: Vec::new(),
            instances: BTreeMap::from([(
                "a".to_owned(),
                Instance {
                    block: "b".into(),
                    inputs: BTreeMap::new(),
                    outputs: BTreeMap::from([("o".to_owned(), a.clone())]),
                },
            )]),
        };
        let e = x.source(&a, "edges[0]").map_err(|e| e.to_string());
        assert_eq!(e, Err("edges[0]: custom blocks nest too deep".to_owned()));
    }
}
