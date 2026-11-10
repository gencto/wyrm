//! `dataflows/<id>/~def` (spec 06): parsing and the compiler checks, in the
//! spec order — schema, node ids, node types and configs, edges and port
//! types, acyclic except through `delay`, rhai, `maxperm`, memory limits.
//! The first error stops; its text starts with the path (`nodes.sum.expr: …`).
//!
//! Custom blocks (ADR 0040 §3, spec 06 0.2.24): a definition may carry `blocks`, and a node
//! of type `block:<name>` is an instance of one. [`parse`] replaces every instance by the
//! block's nodes under the ids `<instance>/<inner>` and rewires the edges, so the checks, the
//! runtime, `watch` and `preview` only ever see plain nodes.

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

/// `nodes`: `{<id>: {type, …config}}`.
fn parse_nodes(v: Option<&Value>, at: &str) -> Result<BTreeMap<String, RawNode>> {
    let mut nodes = BTreeMap::new();
    let Some(v) = v else { return Ok(nodes) };
    for (nid, nv) in as_map(v, at)? {
        let path = format!("{at}.{nid}");
        if nid.contains('/') {
            return err(format!("{path}: id must be [A-Za-z0-9_]+"));
        }
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
        nodes.insert(nid.clone(), (ty, cfg));
    }
    Ok(nodes)
}

/// `edges`: `[[from, to], …]`.
fn parse_edges(v: Option<&Value>, at: &str) -> Result<Vec<Edge>> {
    let mut edges = Vec::new();
    let Some(ev) = v else { return Ok(edges) };
    let Value::Array(items) = ev else {
        return err(format!("{at}: expected an array"));
    };
    for (i, e) in items.iter().enumerate() {
        let path = format!("{at}[{i}]");
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
        return err(format!("{at}: {} entries > {MAX_LAYOUT}", l.len()));
    }
    for (n, xy) in l {
        if n.len() > MAX_LAYOUT_KEY {
            return err(format!(
                "{at}: a key of {} bytes > {MAX_LAYOUT_KEY}",
                n.len()
            ));
        }
        match xy {
            Value::Array(a)
                if a.len() == 2 && a.iter().all(|v| v.as_f64().is_some_and(f64::is_finite)) => {}
            _ => return err(format!("{at}.{n}: expected [x, y]")),
        }
    }
    Ok(())
}

fn text(v: Option<&Value>, at: &str) -> Result<Option<String>> {
    match v {
        None => Ok(None),
        Some(Value::Str(s)) => Ok(Some(s.clone())),
        Some(_) => err(format!("{at}: expected a string")),
    }
}

/// One custom block of `blocks` (ADR 0040 §3): its shape, and that its inputs, outputs and
/// edges name inner nodes it has. The inner nodes' types and ports are checked where the
/// block is used.
pub fn parse_block(name: &str, v: &Value) -> Result<BlockDef> {
    let at = format!("blocks.{name}");
    if !node_id_ok(name) {
        return err(format!("{at}: a block's name must be [A-Za-z0-9_]+"));
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
        return err(format!("{at}.{k}: unknown field"));
    }
    let nodes = parse_nodes(m.get("nodes"), &format!("{at}.nodes"))?;
    for id in nodes.keys() {
        if !node_id_ok(id) {
            return err(format!("{at}.nodes.{id}: id must be [A-Za-z0-9_]+"));
        }
    }
    if nodes.len() > MAX_NODES {
        return err(format!("{at}.nodes: {} nodes > {MAX_NODES}", nodes.len()));
    }
    let uses = nodes
        .values()
        .filter(|(ty, _)| ty.starts_with(BLOCK_PREFIX))
        .count();
    if uses > MAX_BLOCK_INSTANCES {
        return err(format!(
            "{at}.nodes: {uses} instances of custom blocks > {MAX_BLOCK_INSTANCES}"
        ));
    }
    let edges = parse_edges(m.get("edges"), &format!("{at}.edges"))?;
    if edges.len() > MAX_EDGES {
        return err(format!("{at}.edges: {} edges > {MAX_EDGES}", edges.len()));
    }
    check_layout(m.get("layout"), &format!("{at}.layout"))?;
    let inner = |e: &Endpoint, path: &str| -> Result<()> {
        if nodes.contains_key(&e.node) {
            Ok(())
        } else {
            err(format!("{path}: {name} has no inner node {}", e.node))
        }
    };
    for (i, e) in edges.iter().enumerate() {
        inner(&e.from, &format!("{at}.edges[{i}]"))?;
        inner(&e.to, &format!("{at}.edges[{i}]"))?;
    }
    // inputs and outputs: lists, so an editor draws them in their order
    let ports = |key: &str| -> Result<Vec<(String, &Map, String)>> {
        let list = match m.get(key) {
            None => return Ok(Vec::new()),
            Some(Value::Array(a)) => a,
            Some(_) => return err(format!("{at}.{key}: expected an array")),
        };
        if list.len() > MAX_BLOCK_PORTS {
            return err(format!("{at}.{key}: at most {MAX_BLOCK_PORTS}"));
        }
        let mut out: Vec<(String, &Map, String)> = Vec::new();
        for (i, item) in list.iter().enumerate() {
            let path = format!("{at}.{key}[{i}]");
            let pm = as_map(item, &path)?;
            let pname = match pm.get("name") {
                Some(Value::Str(n)) if node_id_ok(n) => n.clone(),
                _ => return err(format!("{path}.name: required, [A-Za-z0-9_]+")),
            };
            if out.iter().any(|(n, _, _)| *n == pname) {
                return err(format!("{path}.name: {pname} twice"));
            }
            text(pm.get("description"), &format!("{path}.description"))?;
            out.push((pname, pm, path));
        }
        Ok(out)
    };
    let mut inputs = Vec::new();
    for (pname, pm, path) in ports("inputs")? {
        if let Some(k) = pm
            .keys()
            .find(|k| !["name", "to", "default", "description"].contains(&k.as_str()))
        {
            return err(format!("{path}.{k}: unknown field"));
        }
        let to_at = format!("{path}.to");
        let to: Vec<Endpoint> = match pm.get("to") {
            Some(Value::Str(one)) => vec![endpoint(one, &to_at)?],
            Some(Value::Array(a)) if !a.is_empty() && a.len() <= MAX_BLOCK_FANOUT => a
                .iter()
                .map(|v| match v {
                    Value::Str(x) => endpoint(x, &to_at),
                    _ => err(format!("{to_at}: expected \"<node>.<port>\"")),
                })
                .collect::<Result<_>>()?,
            _ => {
                return err(format!(
                    "{to_at}: required, 1..={MAX_BLOCK_FANOUT} inner inputs \"<node>.<port>\""
                ))
            }
        };
        for t in &to {
            inner(t, &to_at)?;
        }
        inputs.push(BlockInput {
            name: pname,
            to,
            default: pm.get("default").filter(|v| **v != Value::Null).cloned(),
        });
    }
    let mut outputs = Vec::new();
    for (pname, pm, path) in ports("outputs")? {
        if let Some(k) = pm
            .keys()
            .find(|k| !["name", "from", "description"].contains(&k.as_str()))
        {
            return err(format!("{path}.{k}: unknown field"));
        }
        if inputs.iter().any(|i| i.name == pname) {
            return err(format!(
                "{path}.name: {pname} is an input (an input is an output of its name already)"
            ));
        }
        let from = match pm.get("from") {
            Some(Value::Str(x)) => endpoint(x, &format!("{path}.from"))?,
            _ => return err(format!("{path}.from: required \"<node>.<port>\"")),
        };
        inner(&from, &format!("{path}.from"))?;
        outputs.push(BlockOutput { name: pname, from });
    }
    Ok(BlockDef {
        description: text(m.get("description"), &format!("{at}.description"))?,
        inputs,
        outputs,
        nodes,
        edges,
    })
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

fn too_many_nodes<T>() -> Result<T> {
    err(format!(
        "nodes: more than {MAX_NODES} nodes with the custom blocks expanded"
    ))
}

fn too_many_edges<T>() -> Result<T> {
    err(format!(
        "edges: more than {MAX_EDGES} edges with the custom blocks expanded"
    ))
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
            let mut lap: Vec<&str> = path[pos..].to_vec();
            lap.push(name);
            return err(format!(
                "blocks.{name}: a custom block may not contain itself ({})",
                lap.join(" → ")
            ));
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
                return too_many_nodes();
            }
            let Some(name) = ty.strip_prefix(BLOCK_PREFIX) else {
                self.nodes.insert(path, (ty, cfg));
                continue;
            };
            let blocks = self.blocks;
            let def = blocks.get(name).ok_or_else(|| {
                DefError(format!(
                    "nodes.{path}.type: unknown custom block {name} (define it in blocks)"
                ))
            })?;
            if depth >= MAX_BLOCK_DEPTH {
                return err(format!(
                    "nodes.{path}: custom blocks nest at most {MAX_BLOCK_DEPTH} deep \
                     (does {name} contain itself?)"
                ));
            }
            if let Some(k) = cfg.keys().find(|k| *k != "values") {
                return err(format!(
                    "nodes.{path}.{k}: unknown field (an instance of a custom block takes values)"
                ));
            }
            let values = match cfg.get("values") {
                None => Map::new(),
                Some(Value::Map(m)) => m.clone(),
                Some(_) => {
                    return err(format!(
                        "nodes.{path}.values: expected a map {{<input>: <value>}}"
                    ))
                }
            };
            if let Some(k) = values
                .keys()
                .find(|k| def.inputs.iter().all(|i| i.name != **k))
            {
                return err(format!("nodes.{path}.values.{k}: {name} has no input {k}"));
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
                    constant_into(&mut inner, t, v).map_err(|e| {
                        DefError(format!("nodes.{path}.values.{}: {e}", input.name))
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
            return too_many_edges();
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
                return err(format!(
                    "{at}: {} ({}) has no output {}",
                    e.node, inst.block, e.port
                ));
            }
        }
        err(format!("{at}: custom blocks nest too deep"))
    }

    /// The plain inputs an edge into `e` feeds, added to `out`. `room`: how many edges the
    /// flow may still get; an input that fans out at every level stops when it is used up.
    fn targets(&self, e: &Endpoint, at: &str, out: &mut Vec<Endpoint>, room: usize) -> Result<()> {
        let Some(inst) = self.instances.get(&e.node) else {
            if out.len() >= room {
                return too_many_edges();
            }
            out.push(e.clone());
            return Ok(());
        };
        let to = inst.inputs.get(&e.port).ok_or_else(|| {
            DefError(format!(
                "{at}: {} ({}) has no input {}",
                e.node, inst.block, e.port
            ))
        })?;
        for t in to {
            self.targets(t, at, out, room)?;
        }
        Ok(())
    }
}

/// Gives the inner input `t` the constant `v`: an instance's own constant (`values`), a
/// parameter's config, an operand's constant (`values`, spec 06 0.2.19), an argument of an
/// `invoke`, a variable's `value`.
fn constant_into(
    inner: &mut BTreeMap<String, RawNode>,
    t: &Endpoint,
    v: &Value,
) -> core::result::Result<(), String> {
    use crate::catalog::ConstAt;
    let Some((ty, cfg)) = inner.get_mut(&t.node) else {
        return Err(format!("no inner node {}", t.node));
    };
    let mut put = |key: &str, name: &str| match cfg
        .entry(key.to_owned())
        .or_insert_with(|| Value::Map(Map::new()))
    {
        Value::Map(m) => {
            m.insert(name.to_owned(), v.clone());
            Ok(())
        }
        _ => Err(format!("{}.{key}: expected a map", t.node)),
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
        None => Err(format!(
            "{}.{} takes no constant: wire the input instead",
            t.node, t.port
        )),
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
    // Where an editor draws each node (spec 06 0.2.5): `{<node>: [x, y]}`.
    // Not part of a node, so moving one keeps its state on a hot swap.
    check_layout(m.get("layout"), "layout")?;
    let mut blocks = BTreeMap::new();
    if let Some(bv) = m.get("blocks") {
        let bm = as_map(bv, "blocks")?;
        if bm.len() > MAX_BLOCKS {
            return err(format!("blocks: at most {MAX_BLOCKS}"));
        }
        for (name, def) in bm {
            blocks.insert(name.clone(), parse_block(name, def)?);
        }
    }
    check_no_recursion(&blocks)?;
    let top = parse_nodes(m.get("nodes"), "nodes")?;
    // step 8's limits, taken here already: nothing is expanded beyond them
    if top.len() > MAX_NODES {
        return err(format!("nodes: {} nodes > {MAX_NODES}", top.len()));
    }
    let top_edges = parse_edges(m.get("edges"), "edges")?;
    if top_edges.len() > MAX_EDGES {
        return err(format!("edges: {} edges > {MAX_EDGES}", top_edges.len()));
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
            bytes.extend(wyrm_core::codec::to_vec(&Value::Map(cfg.clone())).unwrap_or_default());
            let hash = crc32c::crc32c(&bytes);
            (nid, NodeDef { ty, cfg, hash })
        })
        .collect();
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
                "maxperm" => {
                    maxperm = perm(v, "permissions.maxperm")?;
                    // spec 06 step 7: flows never do config operations
                    if maxperm > Perm::Write {
                        return err("permissions.maxperm: at most write");
                    }
                }
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
        edge_at,
        instances,
        policy,
        maxperm,
        raw: v.clone(),
    })
}

/// Steps 2–8. Returns the port map of every node.
pub fn check(def: &FlowDef) -> Result<BTreeMap<String, Ports>> {
    // 2. ids
    // an inner node of a custom block has the id `<instance>/<inner>`
    for id in def.nodes.keys().chain(def.instances.keys()) {
        if !id.split('/').all(node_id_ok) {
            return err(format!("nodes.{id}: id must be [A-Za-z0-9_]+"));
        }
    }
    if let Some(id) = def.instances.keys().find(|i| def.nodes.contains_key(*i)) {
        return err(format!(
            "nodes.{id}: a node and a custom block share the id"
        ));
    }
    // 3. types and configs
    let mut ports = BTreeMap::new();
    for (id, n) in &def.nodes {
        let p = nodes::ports(&n.ty, &n.cfg).map_err(|e| DefError(format!("nodes.{id}: {e}")))?;
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
    // 4a. a read field that a port drives needs its scope (ADR 0040 §1)
    for e in &def.edges {
        let Some(n) = def.nodes.get(&e.to.node) else {
            continue;
        };
        for (field, scope) in nodes::read_fields(&n.ty) {
            if e.to.port == format!("in.{field}") && !n.cfg.contains_key(*scope) {
                return err(format!(
                    "nodes.{}.{scope}: required when in.{field} is wired (the keys it may \
                     read, as downstream/<link>/**)",
                    e.to.node
                ));
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
    // 7a. a `publish` inside a custom block has one name in every instance (ADR 0040 §3)
    let mut published: BTreeMap<&str, &str> = BTreeMap::new();
    for (id, n) in def.nodes.iter().filter(|(_, n)| n.ty == "publish") {
        let Some(Value::Str(name)) = n.cfg.get("node") else {
            continue;
        };
        if let Some(other) = published.insert(name, id) {
            if id.contains('/') || other.contains('/') {
                return err(format!(
                    "nodes.{id}.node: {name} is published by {other} too (a custom block \
                     with a publish can be used once)"
                ));
            }
        }
    }
    // 8. memory limits
    if def.nodes.len() > MAX_NODES {
        return err(format!("nodes: {} nodes > {MAX_NODES}", def.nodes.len()));
    }
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
