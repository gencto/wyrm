//! `ptok v1` verification in the responder. Spec: 04-attachment.
//!
//! Order (normative, spec 04 0.2.12): version → signature → `exp > now` →
//! `site` → first grant whose key expression intersects the request key →
//! `jti` not replayed → `effective = min(p, max, maxperm)`. A token with no
//! grant for the key is never remembered (review SDK-1). Any failure is
//! `permission_denied` with no detail; the reason goes to `debug` logs only
//! (never the token).

use ed25519_dalek::{Signature, VerifyingKey};
use std::collections::HashMap;
use std::sync::Mutex;
use wyrm_core::ptok::{self, Grant, PtokClaims};
use wyrm_core::Perm;
use zenoh::key_expr::{keyexpr, OwnedKeyExpr};

/// Upper bound on remembered `jti`s. When full and nothing has expired,
/// new tokens are refused (fail closed).
const REPLAY_CAPACITY: usize = 65_536;
/// Remembered `jti`s of one subject: one caller fills its own share, never
/// the whole cache, so it cannot lock everyone else out (review SDK-1).
const REPLAY_PER_SUBJECT: usize = REPLAY_CAPACITY / 4;

/// `jti` → `exp`, per subject (`sub`).
#[derive(Debug, Default)]
struct Replay {
    by_sub: HashMap<String, HashMap<[u8; 16], u64>>,
    total: usize,
}

impl Replay {
    fn purge(&mut self, now: u64) {
        let mut total = 0;
        self.by_sub.retain(|_, m| {
            m.retain(|_, e| *e > now);
            total += m.len();
            !m.is_empty()
        });
        self.total = total;
    }

    fn remember(&mut self, sub: &str, jti: [u8; 16], exp: u64, now: u64) -> Result<(), Denied> {
        if let Some(m) = self.by_sub.get_mut(sub) {
            if m.contains_key(&jti) {
                return Err(Denied::Replayed);
            }
            if m.len() >= REPLAY_PER_SUBJECT {
                let before = m.len();
                m.retain(|_, e| *e > now);
                self.total -= before - m.len();
                if m.len() >= REPLAY_PER_SUBJECT {
                    return Err(Denied::ReplayCacheFull);
                }
            }
        }
        if self.total >= REPLAY_CAPACITY {
            self.purge(now);
            if self.total >= REPLAY_CAPACITY {
                return Err(Denied::ReplayCacheFull);
            }
        }
        self.by_sub
            .entry(sub.to_owned())
            .or_default()
            .insert(jti, exp);
        self.total += 1;
        Ok(())
    }
}

/// Who is calling, as established by the SDK before the driver runs.
#[derive(Debug, Clone, Default)]
pub struct Caller {
    /// `attachment.origin`, trusted only with a valid `ptok`; `None` otherwise.
    pub origin: Option<String>,
    /// Effective permission for this request.
    pub perm: Perm,
    pub claims: Option<PtokClaims>,
    /// What the key that signed the token is trusted with: `None` for an
    /// admin key (everywhere, up to `config`); for limited keys their scopes
    /// with their caps (ADR 0046). Read only through [`Caller::perm_on`].
    pub signer: Option<SignerScopes>,
}

/// The scopes of the limited keys that signed a token, each with its cap.
pub type SignerScopes = Vec<(String, Perm)>;

impl Caller {
    /// The caller's effective permission on `key`, another key than the
    /// request's (an action that writes outside its own node: a storage
    /// `rename` or `duplicate` makes a sibling under the parent): the token's
    /// `max`, the signer's cap where its scope covers `key`, and, when the
    /// token carries the rights of a person (`auth`, spec 04), their grant
    /// there. The token's own `grants` are left out: a client narrows them to
    /// the request key. No token, nothing.
    pub fn perm_on(&self, key: &str) -> Perm {
        let Some(c) = &self.claims else {
            return Perm::None;
        };
        let Ok(ke) = keyexpr::new(key) else {
            return Perm::None;
        };
        let cap = match &self.signer {
            None => Perm::Config,
            Some(scopes) => scopes
                .iter()
                .filter(|(s, _)| covers(s, key))
                .map(|(_, p)| *p)
                .max()
                .unwrap_or(Perm::None),
        };
        let person = match &c.auth {
            None => Perm::Config,
            Some(auth) => auth
                .iter()
                .filter(|g| keyexpr::new(&g.k).is_ok_and(|g| g.intersects(ke)))
                .map(|g| g.p)
                .max()
                .unwrap_or(Perm::None),
        };
        c.max.min(cap).min(person)
    }
}

/// `key` is `scope` or below it.
fn covers(scope: &str, key: &str) -> bool {
    key == scope || key.strip_prefix(scope).is_some_and(|r| r.starts_with('/'))
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Denied {
    Malformed,
    Signature,
    Expired,
    WrongSite,
    Replayed,
    NoGrant,
    ReplayCacheFull,
    /// `exp` further ahead than [`MAX_TOKEN_TTL_S`].
    TooLong,
}

impl Denied {
    /// Why, in words a refusal can carry (never the token itself).
    pub fn reason(self) -> &'static str {
        match self {
            Denied::Malformed => "the token is malformed",
            Denied::Signature => "the token's signer is not trusted here",
            Denied::Expired => "the token has expired",
            Denied::WrongSite => "the token is for another site",
            Denied::Replayed => "the token was used already",
            Denied::NoGrant => "the token grants nothing on this key",
            Denied::ReplayCacheFull => "too many tokens of this subject at once; try again",
            Denied::TooLong => "the token lives longer than 15 min",
        }
    }
}

/// Longest token lifetime a responder accepts (seconds).
pub const MAX_TOKEN_TTL_S: u64 = 15 * 60;

/// A key trusted only up to `cap` and only for request keys under one of
/// `scopes` (`<prefix>` itself or `<prefix>/...`): the flow engine, the
/// gateway and AI agent keys. A stolen one cannot mint `config` or reach
/// beyond its scopes.
#[derive(Debug, Clone, PartialEq)]
pub struct LimitedKey {
    pub key: VerifyingKey,
    pub cap: Perm,
    pub scopes: Vec<String>,
    /// The only `sub` this key may sign for (a requester link's key:
    /// `link:<id>`), so the audit names who really called. `None` = any.
    pub subject: Option<String>,
}

impl LimitedKey {
    fn covers(&self, key: &str) -> bool {
        self.scopes.iter().any(|s| covers(s, key))
    }
}

#[derive(Debug)]
pub struct Verifier {
    /// Admin keys (up to `config`, everywhere) and limited keys; replaced
    /// as a whole by [`set_trust`](Self::set_trust), the replay cache stays.
    trust: std::sync::RwLock<(Vec<VerifyingKey>, Vec<LimitedKey>)>,
    site: String,
    replay: Mutex<Replay>,
}

impl Verifier {
    /// `keys`: the active admin key and optionally the previous one.
    pub fn new(keys: Vec<VerifyingKey>, site: impl Into<String>) -> Self {
        Self {
            trust: std::sync::RwLock::new((keys, Vec::new())),
            site: site.into(),
            replay: Mutex::new(Replay::default()),
        }
    }

    /// Also trust `keys`, each only up to its cap and within its scopes.
    pub fn with_limited(self, keys: Vec<LimitedKey>) -> Self {
        self.trust
            .write()
            .unwrap_or_else(|p| p.into_inner())
            .1
            .extend(keys);
        self
    }

    /// Replace the trusted keys (a new trust list after a broker restart).
    pub fn set_trust(&self, keys: Vec<VerifyingKey>, limited: Vec<LimitedKey>) {
        *self.trust.write().unwrap_or_else(|p| p.into_inner()) = (keys, limited);
    }

    /// Verify `token` for a request on `key`. `now` is Unix seconds.
    pub fn verify(
        &self,
        token: &[u8],
        key: &keyexpr,
        maxperm: Option<Perm>,
        now: u64,
    ) -> Result<(PtokClaims, Perm), Denied> {
        self.verify_signed(token, key, maxperm, now)
            .map(|(c, p, _)| (c, p))
    }

    /// [`Self::verify`], and what the signer is trusted with (`None` for an
    /// admin key; [`Caller::signer`]).
    pub fn verify_signed(
        &self,
        token: &[u8],
        key: &keyexpr,
        maxperm: Option<Perm>,
        now: u64,
    ) -> Result<(PtokClaims, Perm, Option<SignerScopes>), Denied> {
        let parts = ptok::split(token).ok_or(Denied::Malformed)?;
        let sig = Signature::from_bytes(parts.sig);
        let trust = self.trust.read().unwrap_or_else(|p| p.into_inner());
        let (keys, limited) = &*trust;
        let admin = keys
            .iter()
            .any(|k| k.verify_strict(parts.signed, &sig).is_ok());
        let signers: Vec<&LimitedKey> = if admin {
            Vec::new()
        } else {
            let s: Vec<&LimitedKey> = limited
                .iter()
                .filter(|l| l.key.verify_strict(parts.signed, &sig).is_ok())
                .collect();
            if s.is_empty() {
                return Err(Denied::Signature);
            }
            s
        };
        // Signed: the claims are the signer's, safe to decode now.
        let mut claims: PtokClaims =
            wyrm_core::codec::from_slice(parts.claims).map_err(|_| Denied::Malformed)?;
        let cap = if admin {
            Perm::Config
        } else {
            signers
                .iter()
                .filter(|l| l.covers(key.as_str()))
                .filter(|l| l.subject.as_ref().is_none_or(|s| *s == claims.sub))
                .map(|l| l.cap)
                .max()
                .ok_or(Denied::NoGrant)?
        };
        let signer: Option<SignerScopes> = (!admin).then(|| {
            signers
                .iter()
                .filter(|l| l.subject.as_ref().is_none_or(|s| *s == claims.sub))
                .flat_map(|l| l.scopes.iter().map(|s| (s.clone(), l.cap)))
                .collect()
        });
        // the caller's rights for acting on its behalf: capped as the effective level, and to
        // what each signer is trusted with (a limited key's scopes)
        if let Some(auth) = claims.auth.take() {
            let top = claims.max.min(maxperm.unwrap_or(Perm::Config));
            let trusted: Vec<(Option<&str>, Perm)> = if admin {
                vec![(None, Perm::Config)]
            } else {
                signers
                    .iter()
                    .filter(|l| l.subject.as_ref().is_none_or(|s| *s == claims.sub))
                    .flat_map(|l| l.scopes.iter().map(|s| (Some(s.as_str()), l.cap)))
                    .collect()
            };
            claims.auth = Some(cap_auth(auth, top, &trusted));
        }
        drop(trust);
        if claims.exp <= now {
            return Err(Denied::Expired);
        }
        // The replay cache is in memory: a long-lived token could be replayed
        // after a restart. Bound the window regardless of what the issuer set.
        if claims.exp > now + MAX_TOKEN_TTL_S {
            return Err(Denied::TooLong);
        }
        if claims.site != self.site {
            return Err(Denied::WrongSite);
        }
        let grant = claims
            .grants
            .iter()
            .find(|g| keyexpr::new(&g.k).is_ok_and(|g| g.intersects(key)))
            .ok_or(Denied::NoGrant)?;
        let perm = grant
            .p
            .min(claims.max)
            .min(maxperm.unwrap_or(Perm::Config))
            .min(cap);
        // Only a token that grants something here is remembered.
        self.replay
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .remember(&claims.sub, claims.jti, claims.exp, now)?;
        Ok((claims, perm, signer))
    }
}

/// The `auth` grants a responder may rely on: each at most `top`, and within what a signer is
/// trusted with (`(None, cap)` = everywhere; `(Some(scope), cap)` = `scope` and below). A grant
/// wider than a scope narrows to `<scope>/**`; one that only partly meets a scope is dropped.
pub fn cap_auth(auth: Vec<Grant>, top: Perm, trusted: &[(Option<&str>, Perm)]) -> Vec<Grant> {
    let mut out = Vec::new();
    for g in auth {
        let Ok(gk) = keyexpr::new(&g.k) else { continue };
        for (scope, cap) in trusted {
            let p = g.p.min(top).min(*cap);
            let k = match scope {
                None => g.k.clone(),
                Some(s) => {
                    let Ok(sub) = OwnedKeyExpr::try_from(format!("{s}/**")) else {
                        continue;
                    };
                    let Ok(own) = keyexpr::new(s) else { continue };
                    if sub.includes(gk) {
                        g.k.clone()
                    } else if gk.includes(&sub) && gk.includes(own) {
                        sub.to_string()
                    } else {
                        continue;
                    }
                }
            };
            out.push(Grant { k, p });
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    /// ADR 0046: the caller's level on another key than the request's, as
    /// the verifier would compute it there: grant, max and the signer's scope.
    #[test]
    fn perm_on_another_key() {
        use wyrm_core::ptok::Grant;
        let claims = |grants: Vec<Grant>, max: Perm| PtokClaims {
            sub: "link:rec".into(),
            roles: Vec::new(),
            grants,
            max,
            iat: 0,
            exp: 0,
            jti: [0; 16],
            site: "s".into(),
            auth: None,
            args: None,
        };
        let all = vec![Grant {
            k: "wy/s/**".into(),
            p: Perm::Config,
        }];
        let folder = Caller {
            claims: Some(claims(all.clone(), Perm::Write)),
            signer: Some(vec![("wy/s/storage/dvpsm".into(), Perm::Write)]),
            ..Caller::default()
        };
        assert_eq!(folder.perm_on("wy/s/storage/dvpsm"), Perm::Write);
        assert_eq!(folder.perm_on("wy/s/storage/dvpsm/cmd"), Perm::Write);
        assert_eq!(folder.perm_on("wy/s/storage"), Perm::None, "the parent");
        assert_eq!(folder.perm_on("wy/s/storage/dvpsm2"), Perm::None);
        let admin = Caller {
            claims: Some(claims(all, Perm::Config)),
            signer: None,
            ..Caller::default()
        };
        assert_eq!(admin.perm_on("wy/s/storage"), Perm::Config);
        // a request-scoped token: its grant names only the request key
        let narrow = Caller {
            claims: Some(claims(
                vec![Grant {
                    k: "wy/s/storage/dvpsm/cmd/~act/duplicate".into(),
                    p: Perm::Config,
                }],
                Perm::Config,
            )),
            signer: Some(vec![("wy/s/storage/dvpsm".into(), Perm::Write)]),
            ..Caller::default()
        };
        assert_eq!(narrow.perm_on("wy/s/storage/dvpsm"), Perm::Write);
        assert_eq!(narrow.perm_on("wy/s/storage"), Perm::None);
        // a person's rights (`auth`) through the gateway's key
        let mut c = claims(Vec::new(), Perm::Config);
        c.auth = Some(vec![Grant {
            k: "wy/s/storage/dvpsm/**".into(),
            p: Perm::Write,
        }]);
        let user = Caller {
            claims: Some(c),
            signer: Some(vec![("wy/s/storage".into(), Perm::Config)]),
            ..Caller::default()
        };
        assert_eq!(user.perm_on("wy/s/storage/dvpsm/cmd"), Perm::Write);
        assert_eq!(user.perm_on("wy/s/storage"), Perm::None, "the user's grant");
        assert_eq!(Caller::default().perm_on("wy/s/storage"), Perm::None);
    }

    fn g(k: &str, p: Perm) -> Grant {
        Grant { k: k.into(), p }
    }

    #[test]
    fn auth_is_capped_to_the_signer_and_its_scopes() {
        let auth = vec![
            g("wy/s/**", Perm::Config),
            g("wy/s/downstream/plc1/**", Perm::Write),
            g("wy/s/sys/**", Perm::Config),
        ];
        // an admin key: only `max` caps
        assert_eq!(
            cap_auth(auth.clone(), Perm::Write, &[(None, Perm::Config)]),
            [
                g("wy/s/**", Perm::Write),
                g("wy/s/downstream/plc1/**", Perm::Write),
                g("wy/s/sys/**", Perm::Write)
            ]
        );
        // a limited key trusted at write on downstream: wider grants narrow to the scope,
        // grants outside it go
        assert_eq!(
            cap_auth(
                auth,
                Perm::Config,
                &[(Some("wy/s/downstream"), Perm::Write)]
            ),
            [
                g("wy/s/downstream/**", Perm::Write),
                g("wy/s/downstream/plc1/**", Perm::Write)
            ]
        );
    }

    #[test]
    fn auth_never_authorizes_the_request() {
        use ed25519_dalek::{Signer, SigningKey};
        let key = SigningKey::from_bytes(&[7; 32]);
        let v = Verifier::new(vec![key.verifying_key()], "s");
        let claims = PtokClaims {
            sub: "user:op".into(),
            grants: vec![g("wy/s/downstream/dql/~act/run", Perm::Read)],
            auth: Some(vec![g("wy/s/**", Perm::Config)]),
            max: Perm::Config,
            iat: 1,
            exp: 100,
            jti: [3; 16],
            site: "s".into(),
            ..Default::default()
        };
        let mut tok = vec![ptok::PTOK_VERSION];
        tok.extend(wyrm_core::codec::to_vec(&claims).unwrap());
        let sig = key.sign(&tok);
        tok.extend(sig.to_bytes());
        let k = keyexpr::new("wy/s/downstream/dql/~act/run").unwrap();
        let (c, perm) = v.verify(&tok, k, Some(Perm::Write), 10).unwrap();
        assert_eq!(perm, Perm::Read, "only the scoped grant authorizes");
        // and auth is capped by the request's maxperm
        assert_eq!(c.auth, Some(vec![g("wy/s/**", Perm::Write)]));
    }

    fn signed(
        key: &ed25519_dalek::SigningKey,
        sub: &str,
        grant: &str,
        jti: u32,
        exp: u64,
    ) -> Vec<u8> {
        use ed25519_dalek::Signer;
        let mut id = [0u8; 16];
        id[..4].copy_from_slice(&jti.to_be_bytes());
        let claims = PtokClaims {
            sub: sub.into(),
            grants: vec![g(grant, Perm::Write)],
            max: Perm::Write,
            iat: 1,
            exp,
            jti: id,
            site: "s".into(),
            ..Default::default()
        };
        let mut tok = vec![ptok::PTOK_VERSION];
        tok.extend(wyrm_core::codec::to_vec(&claims).unwrap());
        let sig = key.sign(&tok);
        tok.extend(sig.to_bytes());
        tok
    }

    /// `wyrm_core::ptok::level_on` (used by apps that act for a caller) reads grants exactly
    /// as this verifier and the gateway do with Zenoh's `intersects` (review DQL-2).
    #[test]
    fn level_on_agrees_with_zenoh() {
        let pats = [
            "wy/s/**",
            "wy/s/downstream/**",
            "wy/s/downstream/plc/**",
            "wy/s/downstream/plc",
            "wy/s/*/plc/**",
            "wy/s/downstream/*/t",
            "wy/**/t",
            "wy/s/**/x/**",
            "wy/d/**",
            "**",
        ];
        let keys = [
            "wy/s/downstream/plc",
            "wy/s/downstream/plc/t",
            "wy/s/downstream/ahu/t",
            "wy/s/storage/plc/x/y",
            "wy/s/a/x/b",
            "wy/d/downstream/plc/t",
            "wy/s/downstream/**",
            "wy/s/*/plc/t",
        ];
        for a in pats {
            for b in pats {
                let grants = [(a, Perm::Read), (b, Perm::Write)];
                for k in keys {
                    let target = keyexpr::new(k).unwrap();
                    let zenoh = grants
                        .iter()
                        .find(|(g, _)| keyexpr::new(g).unwrap().intersects(target))
                        .map_or(Perm::None, |(_, p)| *p);
                    assert_eq!(ptok::level_on(grants, k), zenoh, "{grants:?} on {k}");
                }
            }
        }
    }

    /// Review SDK-1: tokens without a grant for the key are never remembered,
    /// and one subject fills only its own share of the replay cache.
    #[test]
    fn one_caller_cannot_fill_the_replay_cache_for_everyone() {
        let key = ed25519_dalek::SigningKey::from_bytes(&[7; 32]);
        let v = Verifier::new(vec![key.verifying_key()], "s");
        let plc = keyexpr::new("wy/s/downstream/plc/~set").unwrap();
        for i in 0..100 {
            let t = signed(&key, "user:mallory", "wy/s/downstream/other/**", i, 100);
            assert_eq!(v.verify(&t, plc, None, 10), Err(Denied::NoGrant));
        }
        assert_eq!(v.replay.lock().unwrap().total, 0, "nothing remembered");
        let t = signed(&key, "user:ann", "wy/s/downstream/**", 1, 100);
        assert!(v.verify(&t, plc, None, 10).is_ok());
        assert_eq!(v.verify(&t, plc, None, 10), Err(Denied::Replayed));

        let mut r = Replay::default();
        let id = |i: usize| {
            let mut j = [0u8; 16];
            j[..8].copy_from_slice(&(i as u64).to_be_bytes());
            j
        };
        for i in 0..REPLAY_PER_SUBJECT {
            r.remember("user:mallory", id(i), 100, 10).unwrap();
        }
        assert_eq!(
            r.remember("user:mallory", id(usize::MAX), 100, 10),
            Err(Denied::ReplayCacheFull),
            "the subject's share is full"
        );
        assert!(
            r.remember("user:ann", id(0), 100, 10).is_ok(),
            "others still pass"
        );
        // expired entries make room again
        assert!(r
            .remember("user:mallory", id(usize::MAX), 1000, 500)
            .is_ok());
        assert_eq!(r.total, 2);
    }
}
