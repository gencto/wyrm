//! In-memory node tree of one link. The SDK answers `~meta` from here.
//!
//! Paths are relative to `wy/<site>/down/<link>`; the root is `""`.
//! `children`, `rev`, `children_count` and the `view=list` summary fields are
//! owned by the tree — whatever the driver puts there is replaced.

use crate::error::{LinkError, Result};
use std::collections::HashMap;
use wyrm_core::meta::{ActionMeta, Profile, TextOrCode, TypeCode};
use wyrm_core::{NodeMeta, Sample, Value};

#[derive(Debug, Clone)]
pub struct Node {
    /// Fields declared by the driver (no tree-owned fields).
    pub meta: NodeMeta,
    pub children: Vec<String>,
    pub rev: u32,
    pub last: Option<Sample>,
}

impl Node {
    fn new(meta: NodeMeta) -> Self {
        Self {
            meta,
            children: Vec::new(),
            rev: 1,
            last: None,
        }
    }

    pub fn is_leaf(&self) -> bool {
        self.meta.ty.is_some()
    }

    /// `cfg.restricted == true`: reading `~meta` needs a `ptok` with `list`.
    pub fn is_restricted(&self) -> bool {
        matches!(self.meta.cfg_value("restricted"), Some(Value::Bool(true)))
    }

    /// Full `~meta` (`view=full`).
    pub fn full(&self) -> NodeMeta {
        let mut m = self.meta.clone();
        m.rev = Some(self.rev);
        if !self.is_leaf() || !self.children.is_empty() {
            m.children = Some(self.children.clone());
            m.children_count = Some(self.children.len() as u32);
        }
        m
    }

    /// Child summary for `view=list`: keys `{0,1,4,10,11,12?,15?}`.
    pub fn summary(&self) -> NodeMeta {
        NodeMeta {
            is: self.meta.is.clone(),
            ty: self.meta.ty,
            writable: self.meta.writable,
            rev: Some(self.rev),
            has_children: Some(!self.children.is_empty()),
            display: match self.meta.attr_value("display") {
                Some(Value::Str(s)) => Some(s.clone()),
                _ => None,
            },
            q: self.last.as_ref().map(|s| s.q.code()),
            ..Default::default()
        }
    }
}

/// Outcome of a mutation: which nodes need a fresh `~meta` publication.
#[derive(Debug, Default)]
pub struct Changed {
    pub node: bool,
    pub parent: Option<String>,
}

#[derive(Debug)]
pub struct NodeTree {
    nodes: HashMap<String, Node>,
}

/// Parent path and last segment. `None` for the root.
pub fn split_parent(path: &str) -> Option<(&str, &str)> {
    if path.is_empty() {
        return None;
    }
    Some(match path.rfind('/') {
        Some(i) => (&path[..i], &path[i + 1..]),
        None => ("", path),
    })
}

fn join(base: &str, name: &str) -> String {
    if base.is_empty() {
        name.to_owned()
    } else {
        format!("{base}/{name}")
    }
}

/// Drop tree-owned fields from a driver-supplied meta.
fn sanitize(mut m: NodeMeta) -> NodeMeta {
    m.children = None;
    m.rev = None;
    m.has_children = None;
    m.display = None;
    m.has_override = None;
    m.children_count = None;
    m.q = None;
    m
}

impl NodeTree {
    pub fn new(root: NodeMeta) -> Self {
        let mut nodes = HashMap::new();
        nodes.insert(String::new(), Node::new(sanitize(root)));
        Self { nodes }
    }

    pub fn get(&self, path: &str) -> Option<&Node> {
        self.nodes.get(path)
    }

    pub fn len(&self) -> usize {
        self.nodes.len()
    }

    pub fn is_empty(&self) -> bool {
        self.nodes.is_empty()
    }

    pub fn iter(&self) -> impl Iterator<Item = (&String, &Node)> {
        self.nodes.iter()
    }

    /// Create or replace a node. The parent must exist. Re-declaring with an
    /// identical meta is a no-op (no `rev` bump). Actions added with
    /// [`declare_action`](Self::declare_action) survive a re-declare that has none.
    pub fn declare(&mut self, path: &str, meta: NodeMeta) -> Result<Changed> {
        let mut meta = sanitize(meta);
        if let Some(node) = self.nodes.get_mut(path) {
            if meta.actions.is_none() {
                meta.actions = node.meta.actions.clone();
            }
            if node.meta == meta {
                return Ok(Changed::default());
            }
            node.meta = meta;
            node.rev = node.rev.wrapping_add(1);
            return Ok(Changed {
                node: true,
                parent: None,
            });
        }
        let (parent, name) = split_parent(path).expect("root always exists");
        let p = self
            .nodes
            .get_mut(parent)
            .ok_or_else(|| LinkError::not_found(format!("parent of {path} not declared")))?;
        if p.is_leaf() {
            return Err(LinkError::invalid_parameter(format!(
                "parent of {path} is a leaf"
            )));
        }
        p.children.push(name.to_owned());
        p.rev = p.rev.wrapping_add(1);
        self.nodes.insert(path.to_owned(), Node::new(meta));
        Ok(Changed {
            node: true,
            parent: Some(parent.to_owned()),
        })
    }

    pub fn declare_action(&mut self, path: &str, name: &str, action: ActionMeta) -> Result<bool> {
        let node = self
            .nodes
            .get_mut(path)
            .ok_or_else(|| LinkError::not_found(path.to_owned()))?;
        let actions = node.meta.actions.get_or_insert_with(Default::default);
        if actions.get(name) == Some(&action) {
            return Ok(false);
        }
        actions.insert(name.to_owned(), action);
        node.rev = node.rev.wrapping_add(1);
        Ok(true)
    }

    /// Remove a node with its subtree. Returns removed paths (parent first)
    /// and the parent path.
    pub fn remove(&mut self, path: &str) -> Result<(Vec<String>, String)> {
        let (parent, name) = split_parent(path)
            .ok_or_else(|| LinkError::invalid_parameter("cannot remove the link root"))?;
        if !self.nodes.contains_key(path) {
            return Err(LinkError::not_found(path.to_owned()));
        }
        let mut removed = Vec::new();
        let mut stack = vec![path.to_owned()];
        while let Some(p) = stack.pop() {
            if let Some(n) = self.nodes.remove(&p) {
                stack.extend(n.children.iter().map(|c| join(&p, c)));
                removed.push(p);
            }
        }
        if let Some(pn) = self.nodes.get_mut(parent) {
            pn.children.retain(|c| c != name);
            pn.rev = pn.rev.wrapping_add(1);
        }
        Ok((removed, parent.to_owned()))
    }

    /// Store the last value of a leaf.
    pub fn set_last(&mut self, path: &str, sample: Sample) -> Result<()> {
        let node = self
            .nodes
            .get_mut(path)
            .ok_or_else(|| LinkError::not_found(path.to_owned()))?;
        if !node.is_leaf() {
            return Err(LinkError::invalid_parameter(format!(
                "{path} is a container: containers have no ~val"
            )));
        }
        node.last = Some(sample);
        Ok(())
    }

    /// `view=list`: child summaries in `children` order, paginated.
    pub fn list(&self, path: &str, from: usize, limit: usize) -> Option<Vec<NodeMeta>> {
        let node = self.nodes.get(path)?;
        Some(
            node.children
                .iter()
                .skip(from)
                .take(limit)
                .filter_map(|c| self.nodes.get(&join(path, c)).map(Node::summary))
                .collect(),
        )
    }

    /// `view=keys`: descendant paths relative to `path`, depth-first in
    /// `children` order, filtered by `filter`, not deeper than `depth`.
    pub fn keys(&self, path: &str, filter: &KeyFilter, depth: usize) -> Option<Vec<String>> {
        let root = self.nodes.get(path)?;
        let mut out = Vec::new();
        // (relative path, absolute path, depth), pushed in reverse to keep order
        let mut stack: Vec<(String, String, usize)> = root
            .children
            .iter()
            .rev()
            .map(|c| (c.clone(), join(path, c), 1))
            .collect();
        while let Some((rel, abs, d)) = stack.pop() {
            let Some(n) = self.nodes.get(&abs) else {
                continue;
            };
            if filter.matches(&n.meta) {
                out.push(rel.clone());
            }
            if d < depth {
                for c in n.children.iter().rev() {
                    stack.push((join(&rel, c), join(&abs, c), d + 1));
                }
            }
        }
        Some(out)
    }
}

/// `match=is:<code>;type:<code>;unit:<str>;tag:<str>` (AND). `tag` tests
/// membership in `attr.tag` (array of strings) or equality with a string.
#[derive(Debug, Default, Clone, PartialEq)]
pub struct KeyFilter {
    pub is: Option<String>,
    pub ty: Option<TypeCode>,
    pub unit: Option<String>,
    pub tag: Option<String>,
}

impl KeyFilter {
    pub fn parse(s: &str) -> Result<Self> {
        let mut f = KeyFilter::default();
        for part in s.split(';').filter(|p| !p.is_empty()) {
            let (k, v) = part
                .split_once(':')
                .ok_or_else(|| LinkError::invalid_parameter(format!("bad match term {part}")))?;
            match k {
                "is" => f.is = Some(v.to_owned()),
                "type" => {
                    let ty = v
                        .parse::<u8>()
                        .ok()
                        .and_then(|c| TypeCode::try_from(c).ok());
                    f.ty = Some(ty.ok_or_else(|| {
                        LinkError::invalid_parameter(format!("bad type code {v}"))
                    })?)
                }
                "unit" => f.unit = Some(v.to_owned()),
                "tag" => f.tag = Some(v.to_owned()),
                _ => {
                    return Err(LinkError::invalid_parameter(format!(
                        "unknown match key {k}"
                    )))
                }
            }
        }
        Ok(f)
    }

    pub fn matches(&self, m: &NodeMeta) -> bool {
        if let Some(is) = &self.is {
            let ok = match &m.is {
                Some(Profile::Code(c)) => is.parse::<u32>().is_ok_and(|x| x == *c),
                Some(Profile::Name(n)) => n == is,
                None => false,
            };
            if !ok {
                return false;
            }
        }
        if let Some(ty) = self.ty {
            if m.ty != Some(ty) {
                return false;
            }
        }
        if let Some(unit) = &self.unit {
            let ok = match &m.unit {
                Some(TextOrCode::Text(t)) => t == unit,
                Some(TextOrCode::Code(c)) => unit.parse::<u32>().is_ok_and(|x| x == *c),
                None => false,
            };
            if !ok {
                return false;
            }
        }
        if let Some(tag) = &self.tag {
            let ok = match m.attr_value("tag") {
                Some(Value::Array(a)) => a.iter().any(|v| matches!(v, Value::Str(s) if s == tag)),
                Some(Value::Str(s)) => s == tag,
                _ => false,
            };
            if !ok {
                return false;
            }
        }
        true
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use wyrm_core::meta::Writable;

    fn tree() -> NodeTree {
        let mut t = NodeTree::new(NodeMeta::folder());
        t.declare("ahu1", NodeMeta::folder()).unwrap();
        t.declare(
            "ahu1/supply_temp",
            NodeMeta::number()
                .unit("°C")
                .attr("tag", Value::Array(vec!["hvac".into()])),
        )
        .unwrap();
        t.declare("ahu1/fan", NodeMeta::leaf(wyrm_core::TypeCode::Bool))
            .unwrap();
        t.declare("ahu2", NodeMeta::folder()).unwrap();
        t.declare("ahu2/supply_temp", NodeMeta::number().unit("°C"))
            .unwrap();
        t
    }

    #[test]
    fn declare_tracks_children_and_rev() {
        let mut t = tree();
        assert_eq!(t.get("").unwrap().children, ["ahu1", "ahu2"]);
        assert_eq!(t.get("ahu1").unwrap().children, ["supply_temp", "fan"]);
        let rev = t.get("ahu1/fan").unwrap().rev;
        // identical re-declare: no change
        let c = t
            .declare("ahu1/fan", NodeMeta::leaf(wyrm_core::TypeCode::Bool))
            .unwrap();
        assert!(!c.node);
        assert_eq!(t.get("ahu1/fan").unwrap().rev, rev);
        let c = t
            .declare(
                "ahu1/fan",
                NodeMeta::leaf(wyrm_core::TypeCode::Bool).writable(Writable::Write),
            )
            .unwrap();
        assert!(c.node && c.parent.is_none());
        assert_eq!(t.get("ahu1/fan").unwrap().rev, rev + 1);
    }

    #[test]
    fn declare_requires_parent() {
        let mut t = tree();
        assert_eq!(
            t.declare("nope/x", NodeMeta::number()).unwrap_err().status,
            wyrm_core::Status::NotFound
        );
        assert!(t.declare("ahu1/fan/x", NodeMeta::number()).is_err());
    }

    #[test]
    fn remove_subtree() {
        let mut t = tree();
        let parent_rev = t.get("").unwrap().rev;
        let (removed, parent) = t.remove("ahu1").unwrap();
        assert_eq!(parent, "");
        assert_eq!(removed.len(), 3);
        assert!(t.get("ahu1/fan").is_none());
        assert_eq!(t.get("").unwrap().children, ["ahu2"]);
        assert_eq!(t.get("").unwrap().rev, parent_rev + 1);
        assert!(t.remove("").is_err());
    }

    #[test]
    fn keys_with_filter_and_depth() {
        let t = tree();
        let all = t.keys("", &KeyFilter::default(), usize::MAX).unwrap();
        assert_eq!(
            all,
            [
                "ahu1",
                "ahu1/supply_temp",
                "ahu1/fan",
                "ahu2",
                "ahu2/supply_temp"
            ]
        );
        let top = t.keys("", &KeyFilter::default(), 1).unwrap();
        assert_eq!(top, ["ahu1", "ahu2"]);
        let f = KeyFilter::parse("type:1;unit:°C").unwrap();
        assert_eq!(
            t.keys("", &f, usize::MAX).unwrap(),
            ["ahu1/supply_temp", "ahu2/supply_temp"]
        );
        let f = KeyFilter::parse("tag:hvac").unwrap();
        assert_eq!(t.keys("", &f, usize::MAX).unwrap(), ["ahu1/supply_temp"]);
        let f = KeyFilter::parse("is:1").unwrap();
        assert_eq!(t.keys("", &f, usize::MAX).unwrap(), ["ahu1", "ahu2"]);
        assert!(KeyFilter::parse("bogus:1").is_err());
    }

    #[test]
    fn list_pagination() {
        let t = tree();
        let l = t.list("ahu1", 0, 1000).unwrap();
        assert_eq!(l.len(), 2);
        assert_eq!(l[0].ty, Some(wyrm_core::TypeCode::Number));
        assert_eq!(l[0].has_children, Some(false));
        assert_eq!(t.list("ahu1", 1, 1).unwrap().len(), 1);
    }
}
