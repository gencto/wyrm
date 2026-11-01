//! What the author of a stored definition may do (spec 04 `auth`): an app that acts later for its
//! author (a DQL query, a scheduler target) keeps it with the definition and checks the keys it
//! reads or writes against it.

use std::collections::BTreeMap;

use wyrm_core::{Perm, Value};

use crate::Who;

/// The author's rights (`Who::authority`) and the site they were given on.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Rights {
    pub site: String,
    pub grants: Vec<(String, Perm)>,
}

impl Rights {
    /// The caller's rights; `None` when its token carries no `auth` (its rights are unknown).
    /// The site is the request's own, from the grant that let the call in.
    pub fn of(who: &Who) -> Option<Self> {
        let grants = who.authority.clone()?;
        let site = who
            .grants
            .first()
            .and_then(|(k, _)| k.strip_prefix("wy/")?.split('/').next())
            .filter(|s| !s.is_empty() && !s.contains('*'))?;
        Some(Self {
            site: site.to_owned(),
            grants,
        })
    }

    /// They give `need` on `key`; a key of another site is checked with the grants rewritten to
    /// it, as the gateway mints a user's tokens for a downstream site (ADR 0018).
    pub fn may(&self, key: &str, need: Perm) -> bool {
        let site = key.strip_prefix("wy/").and_then(|r| r.split('/').next());
        let grants = match site {
            Some(site) if site != self.site => self
                .grants
                .iter()
                .map(|(k, p)| (wyrm_core::ptok::grant_for_site(k, &self.site, site), *p))
                .collect(),
            _ => self.grants.clone(),
        };
        Who {
            authority: Some(grants),
            ..Who::default()
        }
        .may_for(key, need)
    }

    /// `{site, grants: [[key, level], …]}` for the app's store.
    pub fn to_value(&self) -> Value {
        Value::Map(BTreeMap::from([
            ("site".to_owned(), Value::Str(self.site.clone())),
            (
                "grants".to_owned(),
                Value::Array(
                    self.grants
                        .iter()
                        .map(|(k, p)| {
                            Value::Array(vec![Value::Str(k.clone()), Value::UInt(p.code().into())])
                        })
                        .collect(),
                ),
            ),
        ]))
    }

    /// A grant it cannot read makes the whole thing unreadable: never widened.
    pub fn from_value(v: &Value) -> Option<Self> {
        let Value::Map(m) = v else { return None };
        let Some(Value::Str(site)) = m.get("site") else {
            return None;
        };
        let Some(Value::Array(gs)) = m.get("grants") else {
            return None;
        };
        let grants = gs
            .iter()
            .map(|g| match g {
                Value::Array(a) => match a.as_slice() {
                    [Value::Str(k), Value::UInt(p)] => u8::try_from(*p)
                        .ok()
                        .and_then(|p| Perm::try_from(p).ok())
                        .map(|p| (k.clone(), p)),
                    _ => None,
                },
                _ => None,
            })
            .collect::<Option<Vec<_>>>()?;
        Some(Self {
            site: site.clone(),
            grants,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rights_of_a_caller_round_trip_and_decide() {
        let who = Who {
            subject: Some("user:ann".into()),
            grants: vec![("wy/s/downstream/dql/**".into(), Perm::Config)],
            authority: Some(vec![
                ("wy/s/downstream/plc/secret".into(), Perm::None),
                ("wy/s/downstream/plc/**".into(), Perm::Write),
            ]),
        };
        let r = Rights::of(&who).unwrap();
        assert_eq!(r.site, "s");
        assert_eq!(Rights::from_value(&r.to_value()), Some(r.clone()));
        assert!(r.may("wy/s/downstream/plc/heat", Perm::Write));
        assert!(!r.may("wy/s/downstream/plc/secret", Perm::Read));
        assert!(!r.may("wy/s/downstream/ahu/fan", Perm::Read));
        // review DQL-2: a grant shadowed by an earlier, wider one is dead, as at the gateway
        let shadowed = Rights {
            site: "s".into(),
            grants: vec![
                ("wy/s/**".into(), Perm::Read),
                ("wy/s/downstream/plc/**".into(), Perm::Write),
            ],
        };
        assert!(!shadowed.may("wy/s/downstream/plc/heat", Perm::Write));
        assert!(shadowed.may("wy/s/downstream/plc/heat", Perm::Read));
        // another site: the grants of `s` read as that site's
        assert!(r.may("wy/d/downstream/plc/heat", Perm::Write));
        // no `auth`: unknown rights
        assert_eq!(
            Rights::of(&Who {
                authority: None,
                ..who
            }),
            None
        );
    }
}
