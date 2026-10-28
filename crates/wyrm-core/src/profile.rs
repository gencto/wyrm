//! Profiles (spec 02 "Успадкування", key space `pub/<profile>/~meta`): a
//! profile has the structure of `~meta` plus `"extends"` (text key) naming
//! its parent profile. A node field that is absent comes from its profile
//! `is`, recursively through `extends`.

use crate::meta::{NodeMeta, Profile};
use minicbor::data::Type;
use minicbor::decode::{self, Decoder};
use minicbor::encode::{self, Encoder};
use minicbor::{Decode, Encode};
use std::collections::BTreeMap;

/// Longest `extends` chain followed (cycles and runaway chains stop here).
pub const MAX_DEPTH: usize = 8;

/// `pub/<name>/~meta`.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct ProfileDef {
    pub meta: NodeMeta,
    pub extends: Option<String>,
}

impl<C> Encode<C> for ProfileDef {
    fn encode<W: encode::Write>(
        &self,
        e: &mut Encoder<W>,
        _: &mut C,
    ) -> Result<(), encode::Error<W::Error>> {
        // The NodeMeta entries (integer keys) come first in canonical order,
        // then the text key.
        let inner = minicbor::to_vec(&self.meta).map_err(|_| encode::Error::message("meta"))?;
        let mut d = Decoder::new(&inner);
        let n = d
            .map()
            .ok()
            .flatten()
            .ok_or_else(|| encode::Error::message("meta is not a map"))?;
        e.map(n + u64::from(self.extends.is_some()))?;
        e.writer_mut()
            .write_all(&inner[d.position()..])
            .map_err(encode::Error::write)?;
        if let Some(x) = &self.extends {
            e.str("extends")?.str(x)?;
        }
        Ok(())
    }
}

impl<'b, C> Decode<'b, C> for ProfileDef {
    fn decode(d: &mut Decoder<'b>, _: &mut C) -> Result<Self, decode::Error> {
        let input = d.input();
        let n = d
            .map()?
            .ok_or_else(|| decode::Error::message("indefinite map"))?;
        let mut extends = None;
        let mut entries: Vec<&[u8]> = Vec::new();
        for _ in 0..n {
            if matches!(d.datatype()?, Type::String) {
                if d.str()? == "extends" {
                    extends = Some(d.str()?.to_owned());
                } else {
                    d.skip()?;
                }
                continue;
            }
            let start = d.position();
            d.skip()?;
            d.skip()?;
            entries.push(&input[start..d.position()]);
        }
        let mut buf = Encoder::new(Vec::new());
        buf.map(entries.len() as u64)
            .map_err(|_| decode::Error::message("rebuild"))?;
        for e in entries {
            buf.writer_mut().extend_from_slice(e);
        }
        let meta = minicbor::decode(buf.writer())?;
        Ok(Self { meta, extends })
    }
}

fn merge_map<V: Clone>(
    own: &Option<BTreeMap<String, V>>,
    base: &Option<BTreeMap<String, V>>,
) -> Option<BTreeMap<String, V>> {
    match (own, base) {
        (None, b) => b.clone(),
        (o, None) => o.clone(),
        (Some(o), Some(b)) => {
            let mut m = b.clone();
            m.extend(o.iter().map(|(k, v)| (k.clone(), v.clone())));
            Some(m)
        }
    }
}

/// `own` with every absent field taken from `base`; `cfg`, `attr` and
/// `actions` merge key by key (own keys win). Per-node fields (`is`, `rev`,
/// `children`, list/view flags) are never inherited.
pub fn inherit(own: &NodeMeta, base: &NodeMeta) -> NodeMeta {
    NodeMeta {
        is: own.is.clone(),
        ty: own.ty.or(base.ty),
        unit: own.unit.clone().or_else(|| base.unit.clone()),
        enum_values: own.enum_values.clone().or_else(|| base.enum_values.clone()),
        writable: own.writable.or(base.writable),
        invokable: own.invokable.or(base.invokable),
        cfg: merge_map(&own.cfg, &base.cfg),
        attr: merge_map(&own.attr, &base.attr),
        actions: merge_map(&own.actions, &base.actions),
        children: own.children.clone(),
        rev: own.rev,
        has_children: own.has_children,
        display: own.display.clone(),
        has_override: own.has_override,
        children_count: own.children_count,
        q: own.q,
        has_history: own.has_history,
        has_nodes: own.has_nodes,
    }
}

/// `meta` expanded through its profile chain; `lookup` returns a profile by
/// name. Unknown profiles end the chain; at most [`MAX_DEPTH`] steps.
pub fn expand(meta: &NodeMeta, lookup: impl Fn(&str) -> Option<ProfileDef>) -> NodeMeta {
    let mut out = meta.clone();
    let mut next = match &meta.is {
        Some(Profile::Name(n)) => Some(n.clone()),
        _ => None,
    };
    for _ in 0..MAX_DEPTH {
        let Some(name) = next.take() else { break };
        let Some(p) = lookup(&name) else { break };
        out = inherit(&out, &p.meta);
        next = p.extends;
    }
    out
}

/// The full field set of profile `name` (its chain folded in).
pub fn resolved(name: &str, lookup: impl Fn(&str) -> Option<ProfileDef>) -> NodeMeta {
    let start = NodeMeta {
        is: Some(Profile::Name(name.to_owned())),
        ..Default::default()
    };
    let mut m = expand(&start, lookup);
    m.is = None;
    m
}

/// `true` if `own` sets an inheritable field to something other than
/// `base` (spec 02 `has_override`: worth fetching `view=full`).
pub fn overrides(own: &NodeMeta, base: &NodeMeta) -> bool {
    fn map_diff<V: PartialEq>(
        own: &Option<BTreeMap<String, V>>,
        base: &Option<BTreeMap<String, V>>,
    ) -> bool {
        own.as_ref().is_some_and(|o| {
            o.iter()
                .any(|(k, v)| base.as_ref().and_then(|b| b.get(k)) != Some(v))
        })
    }
    fn diff<T: PartialEq>(own: &Option<T>, base: &Option<T>) -> bool {
        own.is_some() && own != base
    }
    diff(&own.ty, &base.ty)
        || diff(&own.unit, &base.unit)
        || diff(&own.enum_values, &base.enum_values)
        || diff(&own.writable, &base.writable)
        || diff(&own.invokable, &base.invokable)
        || map_diff(&own.cfg, &base.cfg)
        || map_diff(&own.attr, &base.attr)
        || map_diff(&own.actions, &base.actions)
}

/// A profile name per spec 01: `<vendor>:<seg>` (`wy:` for the core).
pub fn validate_name(name: &str) -> Result<(), String> {
    let Some((vendor, seg)) = name.split_once(':') else {
        return Err(format!("profile {name:?}: expected <vendor>:<name>"));
    };
    for part in [vendor, seg] {
        crate::keyspace::validate_segment(part).map_err(|e| format!("profile {name:?}: {e}"))?;
    }
    Ok(())
}

/// Core profiles every broker has (wiki "Вузли"); not replaceable.
pub fn builtins() -> Vec<(&'static str, ProfileDef)> {
    use crate::meta::TypeCode;
    let leaf = |ty: TypeCode| ProfileDef {
        meta: NodeMeta {
            ty: Some(ty),
            ..Default::default()
        },
        extends: Some("wy:node".into()),
    };
    let node = |extends: Option<&str>| ProfileDef {
        meta: NodeMeta::default(),
        extends: extends.map(str::to_owned),
    };
    vec![
        ("wy:node", node(None)),
        ("wy:folder", node(Some("wy:node"))),
        ("wy:number", leaf(TypeCode::Number)),
        ("wy:string", leaf(TypeCode::String)),
        ("wy:bool", leaf(TypeCode::Bool)),
        ("wy:enum", leaf(TypeCode::Enum)),
        ("wy:link", node(Some("wy:folder"))),
        ("wy:flow", node(Some("wy:folder"))),
        ("wy:flow-node", node(Some("wy:node"))),
        ("wy:broker", node(Some("wy:folder"))),
    ]
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::meta::{TypeCode, Writable};
    use crate::Value;

    #[test]
    fn roundtrip_with_extends() {
        let p = ProfileDef {
            meta: NodeMeta {
                ty: Some(TypeCode::Number),
                unit: Some(crate::meta::TextOrCode::Text("°C".into())),
                cfg: Some(BTreeMap::from([("min".into(), Value::Float(-40.0))])),
                ..Default::default()
            },
            extends: Some("wy:number".into()),
        };
        let b = crate::codec::to_vec(&p).unwrap();
        assert_eq!(crate::codec::from_slice::<ProfileDef>(&b).unwrap(), p);
        // without extends it is plain ~meta
        let q = ProfileDef {
            extends: None,
            ..p.clone()
        };
        assert_eq!(
            crate::codec::to_vec(&q).unwrap(),
            crate::codec::to_vec(&q.meta).unwrap()
        );
    }

    #[test]
    fn expand_follows_extends() {
        let temp = ProfileDef {
            meta: NodeMeta {
                unit: Some(crate::meta::TextOrCode::Text("°C".into())),
                cfg: Some(BTreeMap::from([
                    ("min".into(), Value::Float(-40.0)),
                    ("max".into(), Value::Float(120.0)),
                ])),
                ..Default::default()
            },
            extends: Some("wy:number".into()),
        };
        let lookup = |n: &str| match n {
            "acme:temp" => Some(temp.clone()),
            other => builtins()
                .into_iter()
                .find(|(b, _)| *b == other)
                .map(|(_, p)| p),
        };
        let node = NodeMeta {
            is: Some(Profile::Name("acme:temp".into())),
            writable: Some(Writable::Write),
            cfg: Some(BTreeMap::from([("max".into(), Value::Float(90.0))])),
            ..Default::default()
        };
        let e = expand(&node, lookup);
        assert_eq!(e.ty, Some(TypeCode::Number), "from wy:number");
        assert_eq!(e.writable, Some(Writable::Write), "own field");
        let cfg = e.cfg.unwrap();
        assert_eq!(cfg["max"], Value::Float(90.0), "own key wins");
        assert_eq!(cfg["min"], Value::Float(-40.0), "inherited key");
        // a cycle stops at MAX_DEPTH
        let cyc = |_: &str| {
            Some(ProfileDef {
                meta: NodeMeta::default(),
                extends: Some("x:a".into()),
            })
        };
        let n = NodeMeta {
            is: Some(Profile::Name("x:a".into())),
            ..Default::default()
        };
        let _ = expand(&n, cyc);
        assert!(validate_name("acme:temp").is_ok());
        assert!(validate_name("temp").is_err() && validate_name("a:b/c").is_err());
    }
}
