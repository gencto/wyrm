//! The branch format of `export` and `import` (ruling 11): one connection,
//! device or folder with everything below it, as JSON text.
//!
//! ```text
//! {"format": "wyrm-driver-branch/1", "driver": "<Driver::NAME>",
//!  "kind": "connection" | "device" | "folder", "name": "<id>",
//!  "params": {..}, "enabled": true, "children": [<node>, ..]}
//! <node> = {"kind", "name", "params", "enabled"?, "children"?}
//! ```
//!
//! * `kind` is the level; on a level with several node kinds the node kind
//!   is `params.kind`, as in the tree.
//! * `enabled` only on connections and devices; `children` of a connection
//!   are devices, of a device or folder folders and points; a point has none.
//! * Secrets are never exported: a secret with a value is `"<not exported>"`
//!   ([`NOT_EXPORTED`]), and an import never takes a secret from the text.
//! * The text is untrusted: at most [`MAX_BYTES`] and [`MAX_NODES`], every
//!   key known, and the framework validates every node's params like `add_*`.
//!   A copy has the same node bound.

use crate::error::{LinkError, Result};
use serde_json::{Map as JsonMap, Number, Value as Json};
use std::collections::BTreeMap;
use wyrm_core::Value;

/// The `format` of this version.
pub const FORMAT: &str = "wyrm-driver-branch/1";
/// The value of an exported secret.
pub const NOT_EXPORTED: &str = "<not exported>";
/// Largest branch text (export and import).
pub const MAX_BYTES: usize = 4 * 1024 * 1024;
/// Most nodes in one branch (export, import and copy), its top node
/// included. Declaring is quadratic in the children of one parent (each new
/// child publishes its parent's `~meta` with the list of children): 4000
/// points in one folder take about 2 s (release, Apple M4 Max), so a branch
/// of this size stays well inside [`ACTION_MS`] on slower boards.
pub const MAX_NODES: usize = 5_000;
/// The bound on one `copy` or `import` call (its `timeout_ms`).
pub const ACTION_MS: u32 = 60_000;

/// The level of a branch node.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Level {
    Connection,
    Device,
    Folder,
    Point,
}

impl Level {
    pub const fn name(self) -> &'static str {
        match self {
            Level::Connection => "connection",
            Level::Device => "device",
            Level::Folder => "folder",
            Level::Point => "point",
        }
    }

    fn from_name(s: &str) -> Option<Self> {
        [Self::Connection, Self::Device, Self::Folder, Self::Point]
            .into_iter()
            .find(|l| l.name() == s)
    }

    /// The levels a node of this level may hold.
    fn holds(self, folders: bool) -> &'static [Level] {
        match self {
            Level::Connection => &[Level::Device],
            Level::Device | Level::Folder if folders => &[Level::Folder, Level::Point],
            Level::Device | Level::Folder => &[Level::Point],
            Level::Point => &[],
        }
    }

    /// `enabled` belongs to connections and devices.
    fn has_enabled(self) -> bool {
        matches!(self, Level::Connection | Level::Device)
    }
}

fn names(levels: &[Level]) -> String {
    levels
        .iter()
        .map(|l| format!("{:?}", l.name()))
        .collect::<Vec<_>>()
        .join(" or ")
}

/// One node of a branch with everything below it.
#[derive(Debug, Clone, PartialEq)]
pub struct Node {
    pub level: Level,
    pub name: String,
    /// As exported: node kind in `kind` (several kinds), secrets as
    /// [`NOT_EXPORTED`].
    pub params: BTreeMap<String, Value>,
    pub enabled: bool,
    pub children: Vec<Node>,
}

impl Node {
    /// This node and every node below it.
    pub fn count(&self) -> usize {
        1 + self.children.iter().map(Node::count).sum::<usize>()
    }

    fn to_json(&self) -> JsonMap<String, Json> {
        let mut m = JsonMap::new();
        m.insert("kind".into(), Json::String(self.level.name().into()));
        m.insert("name".into(), Json::String(self.name.clone()));
        m.insert(
            "params".into(),
            Json::Object(
                self.params
                    .iter()
                    .map(|(k, v)| (k.clone(), to_json(v)))
                    .collect(),
            ),
        );
        if self.level.has_enabled() {
            m.insert("enabled".into(), Json::Bool(self.enabled));
        }
        if self.level != Level::Point {
            m.insert(
                "children".into(),
                Json::Array(
                    self.children
                        .iter()
                        .map(|c| Json::Object(c.to_json()))
                        .collect(),
                ),
            );
        }
        m
    }
}

fn too_large() -> LinkError {
    LinkError::new(
        wyrm_core::Status::OutOfRange,
        format!("export: the branch is larger than {MAX_BYTES} bytes or {MAX_NODES} nodes"),
    )
}

/// Refuse a copy of more than [`MAX_NODES`] nodes.
pub fn check_copy(nodes: usize) -> Result<()> {
    if nodes > MAX_NODES {
        return Err(LinkError::new(
            wyrm_core::Status::OutOfRange,
            format!("copy: {nodes} nodes, more than {MAX_NODES}"),
        ));
    }
    Ok(())
}

/// `node` of `driver` as branch text; refused when it would not import
/// again ([`MAX_BYTES`], [`MAX_NODES`]).
pub fn to_text(driver: &str, node: &Node) -> Result<String> {
    if node.count() > MAX_NODES {
        return Err(too_large());
    }
    let mut m = JsonMap::new();
    m.insert("format".into(), Json::String(FORMAT.into()));
    m.insert("driver".into(), Json::String(driver.into()));
    m.extend(node.to_json());
    let text = serde_json::to_string(&Json::Object(m))
        .map_err(|e| LinkError::internal(format!("export: {e}")))?;
    if text.len() > MAX_BYTES {
        return Err(too_large());
    }
    Ok(text)
}

/// Parse branch text of `driver` whose top node is one of `top`.
/// `folders`: the driver has folders ([`super::Driver::FOLDERS`]).
pub fn parse(text: &str, driver: &str, folders: bool, top: &[Level]) -> Result<Node> {
    if text.len() > MAX_BYTES {
        return Err(LinkError::invalid_parameter(format!(
            "json: more than {MAX_BYTES} bytes"
        )));
    }
    let j: Json = serde_json::from_str(text)
        .map_err(|e| LinkError::invalid_parameter(format!("json: {e}")))?;
    from_value(&from_json(&j), driver, folders, top)
}

/// A branch already decoded (an import built by a driver, Task 7).
pub fn from_value(v: &Value, driver: &str, folders: bool, top: &[Level]) -> Result<Node> {
    let Value::Map(m) = v else {
        return Err(LinkError::invalid_parameter(
            "json: expected a branch object",
        ));
    };
    match m.get("format") {
        Some(Value::Str(f)) if f == FORMAT => {}
        _ => {
            return Err(LinkError::invalid_parameter(format!(
                "format: expected {FORMAT:?}"
            )))
        }
    }
    match m.get("driver") {
        Some(Value::Str(d)) if d == driver => {}
        Some(Value::Str(d)) => {
            return Err(LinkError::invalid_parameter(format!(
                "driver: {d:?} is not {driver:?}"
            )))
        }
        _ => {
            return Err(LinkError::invalid_parameter(format!(
                "driver: expected {driver:?}"
            )))
        }
    }
    let mut nodes = 0;
    let node = node(m, "", &["format", "driver"], folders, top, &mut nodes)?;
    Ok(node)
}

/// One node map at `at` (the path above it, for errors).
fn node(
    m: &BTreeMap<String, Value>,
    at: &str,
    extra: &[&str],
    folders: bool,
    allowed: &[Level],
    nodes: &mut usize,
) -> Result<Node> {
    *nodes += 1;
    if *nodes > MAX_NODES {
        return Err(LinkError::invalid_parameter(format!(
            "json: more than {MAX_NODES} nodes"
        )));
    }
    let name = match m.get("name") {
        Some(Value::Str(n)) => n.clone(),
        _ if at.is_empty() => return Err(LinkError::invalid_parameter("name: expected a string")),
        _ => {
            return Err(LinkError::invalid_parameter(format!(
                "{at}: name: expected a string"
            )))
        }
    };
    let here = if at.is_empty() {
        name.clone()
    } else {
        format!("{at}/{name}")
    };
    let bad = |what: String| LinkError::invalid_parameter(format!("{here}: {what}"));
    let level = match m.get("kind") {
        Some(Value::Str(k)) => Level::from_name(k)
            .filter(|l| allowed.contains(l))
            .ok_or_else(|| {
                bad(format!(
                    "kind: {k:?} does not fit here (expected {})",
                    names(allowed)
                ))
            })?,
        _ => return Err(bad(format!("kind: expected {}", names(allowed)))),
    };
    let known = ["kind", "name", "params", "enabled", "children"];
    if let Some(k) = m
        .keys()
        .find(|k| !known.contains(&k.as_str()) && !extra.contains(&k.as_str()))
    {
        return Err(bad(format!("{k}: unknown field")));
    }
    let params = match m.get("params") {
        Some(Value::Map(p)) => p.clone(),
        None => BTreeMap::new(),
        Some(_) => return Err(bad("params: expected an object".into())),
    };
    if level == Level::Folder && !params.is_empty() {
        return Err(bad("params: a folder has none".into()));
    }
    let enabled = match (m.get("enabled"), level.has_enabled()) {
        (None, _) => true,
        (Some(Value::Bool(b)), true) => *b,
        (Some(_), true) => return Err(bad("enabled: expected true or false".into())),
        (Some(_), false) => return Err(bad(format!("enabled: not on a {}", level.name()))),
    };
    let holds = level.holds(folders);
    let children = match m.get("children") {
        None => Vec::new(),
        Some(Value::Array(a)) if a.is_empty() || !holds.is_empty() => {
            let mut out = Vec::with_capacity(a.len());
            for c in a {
                let Value::Map(cm) = c else {
                    return Err(bad("children: expected objects".into()));
                };
                out.push(node(cm, &here, &[], folders, holds, nodes)?);
            }
            out
        }
        Some(Value::Array(_)) => return Err(bad(format!("children: a {} has none", level.name()))),
        Some(_) => return Err(bad("children: expected an array".into())),
    };
    Ok(Node {
        level,
        name,
        params,
        enabled,
        children,
    })
}

/// A WYRM value as JSON (params hold numbers, strings and booleans; a
/// non-finite float becomes `null`, bytes an array of numbers).
fn to_json(v: &Value) -> Json {
    match v {
        Value::Null => Json::Null,
        Value::Bool(b) => Json::Bool(*b),
        Value::Int(i) => Json::Number((*i).into()),
        Value::UInt(u) => Json::Number((*u).into()),
        Value::Float(f) => Number::from_f64(*f).map_or(Json::Null, Json::Number),
        Value::Str(s) => Json::String(s.clone()),
        Value::Bytes(b) => Json::Array(b.iter().map(|x| Json::Number((*x).into())).collect()),
        Value::Array(a) => Json::Array(a.iter().map(to_json).collect()),
        Value::Map(m) => Json::Object(m.iter().map(|(k, v)| (k.clone(), to_json(v))).collect()),
    }
}

fn from_json(j: &Json) -> Value {
    match j {
        Json::Null => Value::Null,
        Json::Bool(b) => Value::Bool(*b),
        Json::Number(n) => match (n.as_u64(), n.as_i64(), n.as_f64()) {
            (Some(u), _, _) => Value::UInt(u),
            (_, Some(i), _) => Value::Int(i),
            (_, _, Some(f)) => Value::Float(f),
            _ => Value::Null,
        },
        Json::String(s) => Value::Str(s.clone()),
        Json::Array(a) => Value::Array(a.iter().map(from_json).collect()),
        Json::Object(m) => Value::Map(m.iter().map(|(k, v)| (k.clone(), from_json(v))).collect()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn point(name: &str) -> Node {
        Node {
            level: Level::Point,
            name: name.into(),
            params: BTreeMap::from([("addr".into(), Value::UInt(3))]),
            enabled: true,
            children: vec![],
        }
    }

    #[test]
    fn round_trip() {
        let n = Node {
            level: Level::Device,
            name: "d1".into(),
            params: BTreeMap::from([
                ("unit".into(), Value::UInt(7)),
                ("scale".into(), Value::Float(1.0)),
                ("offset".into(), Value::Int(-2)),
            ]),
            enabled: false,
            children: vec![
                Node {
                    level: Level::Folder,
                    name: "f".into(),
                    params: BTreeMap::new(),
                    enabled: true,
                    children: vec![point("p")],
                },
                point("q"),
            ],
        };
        let text = to_text("x", &n).unwrap();
        assert!(text.contains(FORMAT));
        let back = parse(&text, "x", true, &[Level::Device]).unwrap();
        assert_eq!(back, n);
        // Without folders the folder child does not fit.
        let e = parse(&text, "x", false, &[Level::Device]).unwrap_err();
        assert!(
            e.message.starts_with("d1/f: kind: \"folder\""),
            "{}",
            e.message
        );
    }

    #[test]
    fn refusals_name_the_field() {
        let ok = r#"{"format":"wyrm-driver-branch/1","driver":"x","kind":"folder","name":"f","params":{}}"#;
        assert!(parse(ok, "x", true, &[Level::Folder]).is_ok());
        for (text, top, needle) in [
            (ok.replace("/1", "/2"), Level::Folder, "format"),
            (ok.replace(r#""x""#, r#""y""#), Level::Folder, "driver"),
            (ok.to_owned(), Level::Connection, "kind"),
            (
                ok.replace(r#""name":"f""#, r#""name":1"#),
                Level::Folder,
                "name",
            ),
            (
                ok.replace(r#""params":{}"#, r#""params":{"a":1}"#),
                Level::Folder,
                "params",
            ),
            (
                ok.replace(r#""params":{}"#, r#""enabled":true"#),
                Level::Folder,
                "enabled",
            ),
            (
                ok.replace(r#""params":{}"#, r#""more":1"#),
                Level::Folder,
                "more",
            ),
            (
                ok.replace(
                    r#""params":{}"#,
                    r#""children":[{"kind":"point","name":"p","children":[1]}]"#,
                ),
                Level::Folder,
                "f/p: children",
            ),
            ("[]".to_owned(), Level::Folder, "json"),
            ("{".to_owned(), Level::Folder, "json"),
        ] {
            let e = parse(&text, "x", true, &[top]).unwrap_err();
            assert!(e.message.contains(needle), "{needle}: {}", e.message);
        }
    }
}
