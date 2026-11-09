//! What a flow may read (ADR 0040 §1, spec 06 0.2.22).
//!
//! The engine reads through the broker's own session, which no ACL sees. So every key a flow
//! reads is approved when it is deployed: a static key as before (security review FLOW-1), and
//! a key that arrives on a port (`subscribe.in.key`) through a **scope**, a key expression in
//! the node's config (`key_scope`). The deployer must read all of the scope; `watch` and
//! `preview` ask the same of their caller. At run time [`Scope::admit`] refuses every value
//! that is not one concrete key inside the scope and inside this site's `downstream`,
//! `dataflows` or `storage`.

use crate::def::FlowDef;
use std::time::Duration;
use wyrm_core::Value;
use zenoh::key_expr::{keyexpr, OwnedKeyExpr};

/// The site sections a flow reads.
pub const SECTIONS: [&str; 3] = ["downstream", "dataflows", "storage"];
/// Longest key a port may bring, bytes.
pub const MAX_KEY: usize = 512;
/// Two changes of a dynamic key are at least this far apart; the latest value wins.
pub const RESUBSCRIBE: Duration = Duration::from_millis(100);

/// `downstream/x` → `wy/<site>/downstream/x`; an absolute `wy/…` key is kept.
pub fn full_key(site: &str, k: &str) -> String {
    if k.starts_with("wy/") {
        k.to_owned()
    } else {
        format!("wy/{site}/{}", k.trim_start_matches('/'))
    }
}

/// Whether `full` is one of this site's sections or a key below one.
pub fn in_sections(site: &str, full: &str) -> bool {
    SECTIONS.iter().any(|s| {
        full.strip_prefix(&format!("wy/{site}/{s}"))
            .is_some_and(|r| r.is_empty() || r.starts_with('/'))
    })
}

/// The keys a dynamic field may name.
#[derive(Debug, Clone)]
pub struct Scope {
    site: String,
    written: String,
    pattern: OwnedKeyExpr,
}

impl Scope {
    /// `written`: a key expression as in the config, relative to `wy/<site>/` or absolute. It
    /// must lie inside one of this site's sections: the section is literal, so no wildcard
    /// of the scope can reach `sys`, `pub`, `upstream` or another site.
    pub fn new(site: &str, written: &str) -> Result<Self, String> {
        let full = full_key(site, written);
        if !in_sections(site, &full) {
            return Err(format!(
                "a scope lies in this site's downstream, dataflows or storage \
                 (wy/{site}/downstream/…), not {full}"
            ));
        }
        let pattern =
            OwnedKeyExpr::new(full.as_str()).map_err(|e| format!("not a key expression: {e}"))?;
        Ok(Self {
            site: site.to_owned(),
            written: written.to_owned(),
            pattern,
        })
    }

    /// The scope as a full key expression: what the deployer must read.
    pub fn full(&self) -> &str {
        self.pattern.as_str()
    }

    /// The full key that `v` names, or why it is refused. A dynamic key is a text, one
    /// concrete node key (every segment `[A-Za-z0-9_.-]+`, so no wildcard, no `~` suffix,
    /// no empty segment), inside this site's sections and inside the scope.
    pub fn admit(&self, v: &Value) -> Result<String, String> {
        let Value::Str(k) = v else {
            return Err("the key is not a text".into());
        };
        if k.is_empty() {
            return Err("the key is empty".into());
        }
        if k.len() > MAX_KEY {
            return Err(format!("the key is longer than {MAX_KEY} bytes"));
        }
        let full = full_key(&self.site, k);
        wyrm_core::keyspace::validate_path(&full)
            .map_err(|e| format!("not a concrete key: {e}"))?;
        if !in_sections(&self.site, &full) {
            return Err("the key is outside this site's downstream, dataflows and storage".into());
        }
        let ke = keyexpr::new(full.as_str()).map_err(|e| format!("not a key: {e}"))?;
        if !self.pattern.includes(ke) {
            return Err(format!("the key is outside the scope {}", self.written));
        }
        Ok(full)
    }
}

/// One thing a definition reads.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Read {
    pub node: String,
    /// The config key that names it (`key`, `key_scope`, …).
    pub param: &'static str,
    /// As written in the config.
    pub key: String,
    /// A scope (a key expression for a dynamic field), not a static key.
    pub scope: bool,
    /// The node lists the children of what it names (`list_children`): whoever may read the
    /// flow must read `<key>/*` too, as the rows show each child's name, type and unit.
    pub children: bool,
}

/// The children of `full` (a key or a scope) as a key expression in canonical form
/// (`a/**` → `a/*/**`).
pub fn children_of(full: &str) -> Option<String> {
    OwnedKeyExpr::autocanonize(format!("{full}/*"))
        .ok()
        .map(|k| k.as_str().to_owned())
}

/// Every static key and every scope the nodes of `def` read.
pub fn reads(def: &FlowDef) -> Vec<Read> {
    let mut out = Vec::new();
    for (id, n) in &def.nodes {
        for (field, scope) in crate::nodes::read_fields(&n.ty) {
            for (param, is_scope) in [(*field, false), (*scope, true)] {
                if let Some(Value::Str(k)) = n.cfg.get(param) {
                    out.push(Read {
                        node: id.clone(),
                        param,
                        key: k.clone(),
                        scope: is_scope,
                        children: n.ty == "list_children",
                    });
                }
            }
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_scope_lies_in_the_sites_sections() {
        assert!(Scope::new("s", "downstream/modbus/line1/**").is_ok());
        assert!(Scope::new("s", "wy/s/storage/**").is_ok());
        assert!(Scope::new("s", "dataflows/*/nodes/*").is_ok());
        for bad in [
            "sys/**",
            "**",
            "wy/other/downstream/**",
            "wy/*/downstream/**",
            "wy/s/down*/**",
            "upstream/x/**",
            "downstreamx/**",
            "pub/**",
        ] {
            assert!(Scope::new("s", bad).is_err(), "{bad}");
        }
        // not a key expression
        assert!(Scope::new("s", "downstream//x").is_err());
        assert!(Scope::new("s", "downstream/a**").is_err());
    }

    #[test]
    fn a_dynamic_key_is_one_concrete_key_inside_the_scope() {
        let sc = Scope::new("s", "downstream/modbus/line1/**").unwrap();
        let ok = |k: &str| sc.admit(&Value::from(k));
        assert_eq!(
            ok("downstream/modbus/line1/t1").unwrap(),
            "wy/s/downstream/modbus/line1/t1"
        );
        assert_eq!(
            ok("wy/s/downstream/modbus/line1/a/b").unwrap(),
            "wy/s/downstream/modbus/line1/a/b"
        );
        for (bad, why) in [
            ("downstream/modbus/line2/t1", "outside the scope"),
            ("downstream/modbus/line1/*", "not a concrete key"),
            ("downstream/modbus/line1/**", "not a concrete key"),
            ("downstream/modbus/line1/$*", "not a concrete key"),
            ("downstream/modbus/line1/t1/~meta", "not a concrete key"),
            ("downstream/modbus/line1//t1", "not a concrete key"),
            ("downstream/modbus/line1/t 1", "not a concrete key"),
            ("downstream/modbus/line1/t1?x=1", "not a concrete key"),
            ("sys/audit/x", "outside this site"),
            ("wy/other/downstream/modbus/line1/t1", "outside this site"),
            ("", "empty"),
        ] {
            let e = ok(bad).unwrap_err();
            assert!(e.contains(why), "{bad}: {e}");
        }
        assert!(sc.admit(&Value::UInt(1)).is_err());
        assert!(sc.admit(&Value::Null).is_err());
        assert!(ok(&format!("downstream/modbus/line1/{}", "a".repeat(600))).is_err());
        // a scope of one level admits that level only
        let one = Scope::new("s", "storage/rooms/*").unwrap();
        assert!(one.admit(&Value::from("storage/rooms/a")).is_ok());
        assert!(one.admit(&Value::from("storage/rooms/a/b")).is_err());
        assert!(one.admit(&Value::from("storage/rooms")).is_err());
    }
}
