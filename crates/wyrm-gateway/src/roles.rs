//! Roles → grants (wiki "Користувачі — gateway чи mTLS", "Права"). A user's
//! grants are the grants of their roles, concatenated in role order; the
//! first grant whose key expression intersects a key decides its level.

use std::collections::BTreeMap;
use wyrm_core::ptok::Grant;
use wyrm_core::Perm;
use zenoh::key_expr::keyexpr;

/// Role name → `(key expression, perm)`. `{site}` in a key expression is
/// replaced with the gateway's site.
#[derive(Debug, Clone, PartialEq)]
pub struct RoleTable {
    roles: BTreeMap<String, Vec<(String, Perm)>>,
}

impl Default for RoleTable {
    /// The example roles from the wiki, scoped to the gateway's own site.
    fn default() -> Self {
        let mut t = Self::empty();
        t.insert("viewer", vec![("wy/{site}/down/**".into(), Perm::Read)]);
        t.insert(
            "operator",
            vec![
                ("wy/{site}/down/**".into(), Perm::Write),
                ("wy/{site}/flows/**".into(), Perm::Read),
            ],
        );
        t.insert(
            "engineer",
            vec![
                ("wy/{site}/down/**".into(), Perm::Config),
                ("wy/{site}/flows/**".into(), Perm::Config),
                ("wy/{site}/sys/links/**".into(), Perm::Write),
            ],
        );
        t.insert("admin", vec![("wy/**".into(), Perm::Config)]);
        t
    }
}

impl RoleTable {
    pub fn empty() -> Self {
        Self {
            roles: BTreeMap::new(),
        }
    }

    /// Add or replace a role.
    pub fn insert(&mut self, role: impl Into<String>, grants: Vec<(String, Perm)>) {
        self.roles.insert(role.into(), grants);
    }

    pub fn contains(&self, role: &str) -> bool {
        self.roles.contains_key(role)
    }

    /// Check every key expression once `{site}` is filled in.
    pub fn validate(&self, site: &str) -> Result<(), String> {
        for (role, grants) in &self.roles {
            for (k, _) in grants {
                let k = k.replace("{site}", site);
                keyexpr::new(&k).map_err(|e| format!("role {role}: grant {k}: {e}"))?;
            }
        }
        Ok(())
    }

    /// Grants of `roles` in order; unknown roles add nothing.
    pub fn grants(&self, site: &str, roles: &[String]) -> Grants {
        let list = roles
            .iter()
            .filter_map(|r| self.roles.get(r))
            .flatten()
            .map(|(k, p)| Grant {
                k: k.replace("{site}", site),
                p: *p,
            })
            .collect();
        Grants::new(list)
    }
}

/// Effective grants of one user. `max` = the highest level among them.
#[derive(Debug, Clone, PartialEq)]
pub struct Grants {
    pub list: Vec<Grant>,
    pub max: Perm,
}

impl Grants {
    pub fn new(list: Vec<Grant>) -> Self {
        let max = list.iter().map(|g| g.p).max().unwrap_or(Perm::None);
        Self { list, max }
    }

    /// Level on a concrete key: the first intersecting grant, capped by `max`.
    pub fn perm(&self, key: &str) -> Perm {
        let Ok(target) = keyexpr::new(key) else {
            return Perm::None;
        };
        self.list
            .iter()
            .find(|g| keyexpr::new(&g.k).is_ok_and(|k| k.intersects(target)))
            .map_or(Perm::None, |g| g.p.min(self.max))
    }

    /// Some part of `pattern` is reachable at `need` (subscriptions; each
    /// sample is then filtered with [`Grants::perm`]): a grant at `need`
    /// touches it before a lower grant covers all of it.
    pub fn any(&self, pattern: &str, need: Perm) -> bool {
        let Ok(target) = keyexpr::new(pattern) else {
            return false;
        };
        if self.max < need {
            return false;
        }
        for g in &self.list {
            let Ok(k) = keyexpr::new(&g.k) else { continue };
            if !k.intersects(target) {
                continue;
            }
            if g.p >= need {
                return true;
            }
            if k.includes(target) {
                return false;
            }
        }
        false
    }

    /// All of `pattern` is at `need` or more: the first grant that touches
    /// it must also cover it.
    pub fn covers(&self, pattern: &str, need: Perm) -> bool {
        let Ok(target) = keyexpr::new(pattern) else {
            return false;
        };
        self.list
            .iter()
            .find_map(|g| {
                let k = keyexpr::new(&g.k).ok()?;
                k.intersects(target)
                    .then(|| k.includes(target) && g.p.min(self.max) >= need)
            })
            .unwrap_or(false)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn roles(r: &[&str]) -> Vec<String> {
        r.iter().map(|s| s.to_string()).collect()
    }

    #[test]
    fn default_roles() {
        let t = RoleTable::default();
        t.validate("s").unwrap();
        let v = t.grants("s", &roles(&["viewer"]));
        assert_eq!(v.max, Perm::Read);
        assert_eq!(v.perm("wy/s/down/mock/p0/~val"), Perm::Read);
        assert_eq!(v.perm("wy/s/down/mock/p0/~set"), Perm::Read);
        assert_eq!(v.perm("wy/other/down/mock/p0/~val"), Perm::None);
        assert_eq!(v.perm("wy/s/flows/f/~val"), Perm::None);
        let e = t.grants("s", &roles(&["engineer"]));
        assert!(e.covers("wy/s/sys/links/**", Perm::Write));
        assert!(!e.covers("wy/s/sys/**", Perm::Config), "only a part of sys");
        let a = t.grants("s", &roles(&["admin"]));
        assert!(a.covers("wy/s/sys/**", Perm::Config));
    }

    #[test]
    fn first_match_wins_and_max_caps() {
        let g = Grants::new(vec![
            Grant {
                k: "wy/s/down/mock/g1/**".into(),
                p: Perm::None,
            },
            Grant {
                k: "wy/s/down/**".into(),
                p: Perm::Write,
            },
        ]);
        assert_eq!(g.perm("wy/s/down/mock/g1/p1/~val"), Perm::None);
        assert_eq!(g.perm("wy/s/down/mock/g0/p0/~val"), Perm::Write);
        assert!(g.any("wy/s/down/mock/**/~val", Perm::Read));
        assert!(!g.any("wy/s/down/mock/g1/**/~val", Perm::Read), "shadowed");
        let capped = Grants {
            max: Perm::Read,
            ..g
        };
        assert_eq!(capped.perm("wy/s/down/mock/g0/p0/~set"), Perm::Read);
        // roles concatenate in order
        let mut t = RoleTable::empty();
        t.insert("a", vec![("wy/{site}/down/**".into(), Perm::List)]);
        t.insert("b", vec![("wy/{site}/down/**".into(), Perm::Config)]);
        let ab = t.grants("s", &roles(&["a", "b"]));
        assert_eq!(ab.perm("wy/s/down/x/~meta"), Perm::List);
        assert_eq!(ab.max, Perm::Config);
    }
}
