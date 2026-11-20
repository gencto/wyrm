//! `ptok v1` verification in the responder. Spec: 04-attachment.
//!
//! Order (normative, spec 04 0.2.12): version → signature → `exp > now` →
//! `site` → first grant whose key expression intersects the request key →
//! `jti` not replayed → `effective = min(p, max, maxperm)`. A token with no
//! grant for the key is never remembered (review SDK-1). Any failure is
//! `permission_denied` with no detail; the reason goes to `debug` logs only
//! (never the token).
//!
//! A token names no key, so "signature" means: by one of the trusted keys.
//! Which one is found with one verification for a subject seen before
//! ([`Trust`]); what is remembered for that only orders the search and
//! decides nothing.

use ed25519_dalek::{Signature, VerifyingKey};
use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
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
    ///
    /// The person's grants are read as every evaluator reads grants (spec 04,
    /// `wyrm_core::ptok::level_on`): the first grant that touches `key`
    /// decides, so a `none` before a wider grant is a `none` here too. The
    /// signer's scopes are caps, not grants: the widest scope that covers
    /// `key` counts.
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
            Some(auth) => {
                wyrm_core::ptok::level_on(auth.iter().map(|g| (g.k.as_str(), g.p)), ke.as_str())
            }
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

/// Most subjects a verifier remembers the signer of ([`Trust::hints`]).
const HINTS_MAX: usize = 1024;
/// A longer `sub` is never remembered (it is still verified as any other).
const HINT_SUB_MAX: usize = 128;

/// One distinct trusted public key and everything it is trusted as.
#[derive(Debug)]
struct TrustedKey {
    key: VerifyingKey,
    /// It is in the admin list: up to `config` everywhere, whatever `limited` says (the
    /// admin list is read first).
    admin: bool,
    /// Every limited entry with this key, in the order of the trust list. All of them
    /// count together: the widest cap that covers the request, the scopes of each.
    limited: Vec<LimitedKey>,
    /// [`Trust::clock`] at its last good signature: the keys in use are tried first.
    used: AtomicU64,
}

/// The trusted keys, one entry per distinct public key, with what tells the signer of a token
/// before its signature is checked. A token names no key (spec 04), so without that every
/// trusted key is tried in turn, one Ed25519 verification each.
///
/// Nothing here decides anything: `hints` and `used` only set the order in which the keys are
/// tried. The signature is always checked in full against the key that is tried, and a key
/// that fails is followed by every other one, so a wrong hint costs time and never accepts or
/// refuses a token. A refused token is checked against every distinct key exactly once,
/// whatever its `sub` says.
///
/// One signature verifies under one public key only (`verify_strict`: no small-order key or
/// `R`, canonical `S`), so the first key that verifies is the only one, and the search ends
/// there.
#[derive(Debug)]
struct Trust {
    keys: Vec<TrustedKey>,
    /// `sub` → index in `keys` of the key that signed its last accepted token. Written only
    /// with the `sub` of a token that passed every check (signature, times, site, grant,
    /// replay), read with the unverified `sub` of the token at hand. At most [`HINTS_MAX`]
    /// subjects of at most [`HINT_SUB_MAX`] bytes; an arbitrary one goes when it is full.
    /// It lives and dies with this trust list: a new list starts empty.
    hints: Mutex<HashMap<Box<str>, usize>>,
    clock: AtomicU64,
    /// The lists as given, for [`Verifier::with_limited`].
    admin: Vec<VerifyingKey>,
    limited: Vec<LimitedKey>,
}

impl Trust {
    fn new(admin: Vec<VerifyingKey>, limited: Vec<LimitedKey>) -> Self {
        let mut index: HashMap<[u8; 32], usize> = HashMap::new();
        let mut keys: Vec<TrustedKey> = Vec::new();
        let mut entry = |keys: &mut Vec<TrustedKey>, key: &VerifyingKey| -> usize {
            // by the bytes as given: they are what the signature covers
            *index.entry(key.to_bytes()).or_insert_with(|| {
                keys.push(TrustedKey {
                    key: *key,
                    admin: false,
                    limited: Vec::new(),
                    used: AtomicU64::new(0),
                });
                keys.len() - 1
            })
        };
        for k in &admin {
            let i = entry(&mut keys, k);
            if let Some(t) = keys.get_mut(i) {
                t.admin = true;
            }
        }
        for l in &limited {
            let i = entry(&mut keys, &l.key);
            if let Some(t) = keys.get_mut(i) {
                t.limited.push(l.clone());
            }
        }
        Self {
            keys,
            hints: Mutex::new(HashMap::new()),
            clock: AtomicU64::new(0),
            admin,
            limited,
        }
    }

    fn hint(&self, sub: &str) -> Option<usize> {
        self.hints
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .get(sub)
            .copied()
    }

    /// `sub` (of an accepted token) was signed by key `at`.
    fn remember(&self, sub: &str, at: usize) {
        if sub.len() > HINT_SUB_MAX {
            return;
        }
        let mut hints = self.hints.lock().unwrap_or_else(|p| p.into_inner());
        if let Some(i) = hints.get_mut(sub) {
            *i = at;
            return;
        }
        if hints.len() >= HINTS_MAX {
            let Some(old) = hints.keys().next().cloned() else {
                return;
            };
            hints.remove(&old);
        }
        hints.insert(sub.into(), at);
    }

    fn signed_by(&self, at: usize, signed: &[u8], sig: &Signature) -> Option<&TrustedKey> {
        let t = self.keys.get(at)?;
        #[cfg(test)]
        tests::VERIFIES.with(|c| c.set(c.get() + 1));
        t.key.verify_strict(signed, sig).ok()?;
        t.used.store(
            self.clock.fetch_add(1, Ordering::Relaxed) + 1,
            Ordering::Relaxed,
        );
        Some(t)
    }

    /// The trusted key that signed `signed`, and whether `sub_hint` (the token's unverified
    /// `sub`) told it. The key remembered for the `sub` is tried first, then every other one,
    /// the last used first.
    fn signer(
        &self,
        signed: &[u8],
        sig: &Signature,
        sub_hint: Option<&str>,
    ) -> Option<(usize, &TrustedKey, bool)> {
        let hint = sub_hint
            .and_then(|s| self.hint(s))
            .filter(|i| *i < self.keys.len());
        if let Some(i) = hint {
            if let Some(t) = self.signed_by(i, signed, sig) {
                return Some((i, t, true));
            }
        }
        // `used` is read once per key: other requests move it while this one sorts
        let mut order: Vec<(std::cmp::Reverse<u64>, usize)> = self
            .keys
            .iter()
            .enumerate()
            .filter(|(i, _)| Some(*i) != hint)
            .map(|(i, t)| (std::cmp::Reverse(t.used.load(Ordering::Relaxed)), i))
            .collect();
        // keys never used stay in list order, the admin keys first
        order.sort_unstable();
        order
            .into_iter()
            .find_map(|(_, i)| self.signed_by(i, signed, sig).map(|t| (i, t, false)))
    }
}

#[derive(Debug)]
pub struct Verifier {
    /// Admin keys (up to `config`, everywhere) and limited keys; replaced
    /// as a whole by [`set_trust`](Self::set_trust), the replay cache stays.
    /// What is remembered about signers ([`Trust::hints`]) is inside, so it
    /// goes with the list it was learned on.
    trust: std::sync::RwLock<Arc<Trust>>,
    site: String,
    replay: Mutex<Replay>,
}

impl Verifier {
    /// `keys`: the active admin key and optionally the previous one.
    pub fn new(keys: Vec<VerifyingKey>, site: impl Into<String>) -> Self {
        Self {
            trust: std::sync::RwLock::new(Arc::new(Trust::new(keys, Vec::new()))),
            site: site.into(),
            replay: Mutex::new(Replay::default()),
        }
    }

    /// Also trust `keys`, each only up to its cap and within its scopes.
    pub fn with_limited(self, keys: Vec<LimitedKey>) -> Self {
        {
            let mut trust = self.trust.write().unwrap_or_else(|p| p.into_inner());
            let mut limited = trust.limited.clone();
            limited.extend(keys);
            *trust = Arc::new(Trust::new(trust.admin.clone(), limited));
        }
        self
    }

    /// Replace the trusted keys (a new trust list after a broker restart).
    pub fn set_trust(&self, keys: Vec<VerifyingKey>, limited: Vec<LimitedKey>) {
        let new = Arc::new(Trust::new(keys, limited));
        *self.trust.write().unwrap_or_else(|p| p.into_inner()) = new;
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
        // one trust list for the whole check: a list set meanwhile counts from the next token
        let trust = Arc::clone(&self.trust.read().unwrap_or_else(|p| p.into_inner()));
        // Not signed yet: this `sub` only says which key is tried first.
        let (at, signer_key, hinted) = trust
            .signer(parts.signed, &sig, ptok::peek_sub(parts.claims))
            .ok_or(Denied::Signature)?;
        let admin = signer_key.admin;
        let signers: &[LimitedKey] = if admin { &[] } else { &signer_key.limited };
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
        // Accepted: the next token of this subject tries this key first.
        if !hinted {
            trust.remember(&claims.sub, at);
        }
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

    thread_local! {
        /// Ed25519 verifications made on this thread ([`Trust::signed_by`]).
        pub(super) static VERIFIES: std::cell::Cell<usize> = const { std::cell::Cell::new(0) };
    }

    /// Verifications `f` makes.
    fn verifies<T>(f: impl FnOnce() -> T) -> (T, usize) {
        let before = VERIFIES.with(std::cell::Cell::get);
        let out = f();
        (out, VERIFIES.with(std::cell::Cell::get) - before)
    }

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
        // a `none` before a wider grant decides (first match), as at the gateway
        let mut c = claims(Vec::new(), Perm::Config);
        c.auth = Some(vec![
            Grant {
                k: "wy/s/downstream/plc1/**".into(),
                p: Perm::None,
            },
            Grant {
                k: "wy/s/downstream/**".into(),
                p: Perm::Write,
            },
        ]);
        let denied = Caller {
            claims: Some(c),
            signer: None,
            ..Caller::default()
        };
        assert_eq!(denied.perm_on("wy/s/downstream/plc1/p/~val"), Perm::None);
        assert_eq!(denied.perm_on("wy/s/downstream/plc2/p/~val"), Perm::Write);
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

    // ---- the search by `sub` hint against the sequential search it replaced ----

    type Verdict = Result<(PtokClaims, Perm, Option<SignerScopes>), Denied>;

    /// The verifier as it was before the key index (every admin key, then every limited key,
    /// one `verify_strict` each), kept word for word as the oracle: the new one must give the
    /// same answer for every token.
    #[allow(
        clippy::too_many_arguments,
        reason = "the old method's state, spelled out"
    )]
    fn sequential(
        keys: &[VerifyingKey],
        limited: &[LimitedKey],
        site: &str,
        replay: &mut Replay,
        token: &[u8],
        key: &keyexpr,
        maxperm: Option<Perm>,
        now: u64,
    ) -> Verdict {
        let parts = ptok::split(token).ok_or(Denied::Malformed)?;
        let sig = Signature::from_bytes(parts.sig);
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
        if claims.exp <= now {
            return Err(Denied::Expired);
        }
        if claims.exp > now + MAX_TOKEN_TTL_S {
            return Err(Denied::TooLong);
        }
        if claims.site != site {
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
        replay.remember(&claims.sub, claims.jti, claims.exp, now)?;
        Ok((claims, perm, signer))
    }

    /// xorshift64*: the same tokens on every run.
    struct Rng(u64);

    impl Rng {
        fn next(&mut self) -> u64 {
            self.0 ^= self.0 >> 12;
            self.0 ^= self.0 << 25;
            self.0 ^= self.0 >> 27;
            self.0.wrapping_mul(0x2545_f491_4f6c_dd1d)
        }
        fn below(&mut self, n: usize) -> usize {
            (self.next() % n as u64) as usize
        }
        fn one_in(&mut self, n: usize) -> bool {
            self.below(n) == 0
        }
        fn pick<'a, T>(&mut self, of: &'a [T]) -> &'a T {
            &of[self.below(of.len())]
        }
    }

    const PERMS: [Perm; 5] = [
        Perm::None,
        Perm::List,
        Perm::Read,
        Perm::Write,
        Perm::Config,
    ];
    const SCOPES: [&str; 6] = [
        "wy/s",
        "wy/s/downstream",
        "wy/s/downstream/plc",
        "wy/s/storage",
        "wy/s/dataflows",
        "wy/d/downstream",
    ];
    const PATTERNS: [&str; 8] = [
        "wy/s/**",
        "wy/s/downstream/**",
        "wy/s/downstream/plc/**",
        "wy/s/downstream/plc/p/~set",
        "wy/s/storage/**",
        "wy/s/*/f/**",
        "wy/d/**",
        "not a key//",
    ];
    const REQUESTS: [&str; 4] = [
        "wy/s/downstream/plc/p/~set",
        "wy/s/storage/x/~act/rename",
        "wy/s/dataflows/f/~act/deploy",
        "wy/s/sys/~act/get_log",
    ];

    fn subs() -> Vec<String> {
        vec![
            "user:ann".into(),
            "user:bob".into(),
            "link:rec".into(),
            "flow:f".into(),
            // longer than a remembered `sub`
            format!("user:{}", "x".repeat(HINT_SUB_MAX)),
        ]
    }

    fn pool() -> Vec<ed25519_dalek::SigningKey> {
        (10u8..16)
            .map(|i| ed25519_dalek::SigningKey::from_bytes(&[i; 32]))
            .collect()
    }

    /// A trust list with keys named twice and under different limits, and keys that are an
    /// admin key and a limited key at once.
    fn random_trust(
        r: &mut Rng,
        pool: &[ed25519_dalek::SigningKey],
    ) -> (Vec<VerifyingKey>, Vec<LimitedKey>) {
        let subs = subs();
        let admin = (0..r.below(3))
            .map(|_| r.pick(pool).verifying_key())
            .collect();
        let limited = (0..r.below(13))
            .map(|_| LimitedKey {
                key: r.pick(pool).verifying_key(),
                cap: *r.pick(&PERMS),
                scopes: (0..r.below(3))
                    .map(|_| (*r.pick(&SCOPES)).to_owned())
                    .collect(),
                subject: r.one_in(3).then(|| r.pick(&subs).clone()),
            })
            .collect();
        (admin, limited)
    }

    fn random_grants(r: &mut Rng) -> Vec<Grant> {
        (0..r.below(4))
            .map(|_| g(r.pick(&PATTERNS), *r.pick(&PERMS)))
            .collect()
    }

    /// A token of any kind: good, of a signer nobody trusts, expired, too long, for another
    /// site, with and without `auth`, then perhaps damaged.
    fn random_token(
        r: &mut Rng,
        pool: &[ed25519_dalek::SigningKey],
        stranger: &ed25519_dalek::SigningKey,
        now: u64,
    ) -> Vec<u8> {
        use ed25519_dalek::Signer;
        let key = if r.one_in(8) { stranger } else { r.pick(pool) };
        let mut jti = [0u8; 16];
        jti[..8].copy_from_slice(&r.next().to_be_bytes());
        let claims = PtokClaims {
            sub: r.pick(&subs()).clone(),
            roles: Vec::new(),
            grants: if r.one_in(6) {
                random_grants(r)
            } else {
                let mut v = vec![g("wy/s/**", *r.pick(&PERMS))];
                v.extend(random_grants(r));
                v
            },
            max: if r.one_in(3) {
                *r.pick(&PERMS)
            } else {
                Perm::Config
            },
            iat: now,
            exp: match r.below(12) {
                0 => now,
                1 => now.saturating_sub(5),
                2 => now + MAX_TOKEN_TTL_S + 1,
                _ => now + 1 + r.below(MAX_TOKEN_TTL_S as usize) as u64,
            },
            jti,
            site: if r.one_in(12) { "d" } else { "s" }.into(),
            auth: r.one_in(3).then(|| random_grants(r)),
            args: None,
        };
        let mut tok = vec![ptok::PTOK_VERSION];
        if r.one_in(25) {
            // signed by its key, but not claims
            tok.extend([0xff, 0x00, 0x01]);
        } else {
            tok.extend(wyrm_core::codec::to_vec(&claims).unwrap());
        }
        let sig = key.sign(&tok);
        tok.extend(sig.to_bytes());
        match r.below(20) {
            0 => {
                let at = r.below(tok.len());
                tok[at] ^= 1 << r.below(8);
            }
            1 => tok.truncate(r.below(tok.len())),
            2 => tok[0] = 2,
            _ => {}
        }
        tok
    }

    /// For random trust lists (keys named twice, different limits, lists replaced on the way)
    /// and random tokens (good, unknown signer, damaged, expired, replayed), the verifier
    /// answers exactly as the sequential search did: the same claims, level and signer scopes,
    /// or the same refusal.
    #[test]
    fn the_indexed_search_decides_as_the_sequential_one() {
        let pool = pool();
        let stranger = ed25519_dalek::SigningKey::from_bytes(&[99; 32]);
        let mut r = Rng(0x9e37_79b9_7f4a_7c15);
        let mut seen: HashMap<String, usize> = HashMap::new();
        for round in 0..40 {
            let (mut admin, mut limited) = random_trust(&mut r, &pool);
            let v = Verifier::new(admin.clone(), "s").with_limited(limited.clone());
            let mut replay = Replay::default();
            let mut sent: Vec<Vec<u8>> = Vec::new();
            let mut now = 1_000 + r.below(1_000) as u64;
            for step in 0..60 {
                if r.one_in(25) {
                    (admin, limited) = random_trust(&mut r, &pool);
                    v.set_trust(admin.clone(), limited.clone());
                }
                now += r.below(3) as u64;
                let token = if !sent.is_empty() && r.one_in(6) {
                    r.pick(&sent).clone()
                } else {
                    random_token(&mut r, &pool, &stranger, now)
                };
                let key = keyexpr::new(*r.pick(&REQUESTS)).unwrap();
                let maxperm = r.one_in(3).then(|| *r.pick(&PERMS));
                let want = sequential(
                    &admin,
                    &limited,
                    "s",
                    &mut replay,
                    &token,
                    key,
                    maxperm,
                    now,
                );
                let got = v.verify_signed(&token, key, maxperm, now);
                assert_eq!(got, want, "round {round} step {step}, request {key}");
                *seen
                    .entry(match &got {
                        Ok(_) => "ok".to_owned(),
                        Err(e) => format!("{e:?}"),
                    })
                    .or_default() += 1;
                sent.push(token);
            }
            assert_eq!(v.replay.lock().unwrap().total, replay.total);
        }
        // the run met every answer it is about
        for case in [
            "ok",
            "Malformed",
            "Signature",
            "Expired",
            "TooLong",
            "WrongSite",
            "Replayed",
            "NoGrant",
        ] {
            assert!(seen.get(case).is_some_and(|n| *n >= 5), "{case}: {seen:?}");
        }
        assert!(seen["ok"] >= 300, "{seen:?}");
    }

    fn limited(key: &ed25519_dalek::SigningKey, cap: Perm, scope: &str) -> LimitedKey {
        LimitedKey {
            key: key.verifying_key(),
            cap,
            scopes: vec![scope.to_owned()],
            subject: None,
        }
    }

    /// One key trusted more than once: every limited entry of it counts together (the
    /// widest cap that covers the request, the scopes of all, in list order), and a key that
    /// is also in the admin list is an admin key, wherever it stands in the limited list.
    #[test]
    fn a_key_trusted_twice_keeps_what_the_list_order_gave_it() {
        let pool = pool();
        let (a, b) = (&pool[0], &pool[1]);
        let plc = keyexpr::new("wy/s/downstream/plc/p/~set").unwrap();
        let store = keyexpr::new("wy/s/storage/x/~set").unwrap();
        let twice = vec![
            limited(a, Perm::Read, "wy/s/downstream"),
            limited(b, Perm::Config, "wy/s"),
            limited(a, Perm::Write, "wy/s/downstream/plc"),
            limited(a, Perm::Config, "wy/s/storage"),
        ];
        let v = Verifier::new(Vec::new(), "s").with_limited(twice.clone());
        let mut replay = Replay::default();
        let mut jti = 0;
        let mut both = |v: &Verifier, admin: &[VerifyingKey], l: &[LimitedKey], k: &keyexpr| {
            jti += 1;
            let t = signed(a, "user:ann", "wy/s/**", jti, 100);
            let got = v.verify_signed(&t, k, None, 10);
            let want = sequential(admin, l, "s", &mut replay, &t, k, None, 10);
            assert_eq!(got, want);
            got.unwrap()
        };
        // the token's own level is `write`; the request under `plc` meets two entries
        let (_, perm, scopes) = both(&v, &[], &twice, plc);
        assert_eq!(perm, Perm::Write);
        assert_eq!(
            scopes,
            Some(vec![
                ("wy/s/downstream".to_owned(), Perm::Read),
                ("wy/s/downstream/plc".to_owned(), Perm::Write),
                ("wy/s/storage".to_owned(), Perm::Config),
            ]),
            "every entry of the key, in list order; none of the other key"
        );
        let (_, perm, _) = both(&v, &[], &twice, store);
        assert_eq!(perm, Perm::Write, "min(token max, the storage entry)");
        // the same key as an admin key too: admin, whatever its limited entries say
        let admin = vec![a.verifying_key()];
        v.set_trust(admin.clone(), twice.clone());
        let (_, perm, scopes) = both(&v, &admin, &twice, plc);
        assert_eq!((perm, scopes), (Perm::Write, None));
        let sys = keyexpr::new("wy/s/sys/~act/get_log").unwrap();
        let (_, _, scopes) = both(&v, &admin, &twice, sys);
        assert_eq!(
            scopes, None,
            "outside every limited scope: still the admin key"
        );
        // and without the admin entry that request has no scope
        v.set_trust(Vec::new(), twice.clone());
        let t = signed(a, "user:ann", "wy/s/**", 1000, 100);
        assert_eq!(v.verify(&t, sys, None, 10), Err(Denied::NoGrant));
    }

    /// One verification per token once the signer of its subject is known, with any number
    /// of trusted keys; a refused token costs one per distinct key, whatever it claims.
    #[test]
    fn a_known_subject_costs_one_verification() {
        let keys: Vec<ed25519_dalek::SigningKey> = (0..30u8)
            .map(|i| ed25519_dalek::SigningKey::from_bytes(&[100 + i; 32]))
            .collect();
        let admin = ed25519_dalek::SigningKey::from_bytes(&[7; 32]);
        let mut list: Vec<LimitedKey> = keys
            .iter()
            .map(|k| limited(k, Perm::Write, "wy/s/downstream"))
            .collect();
        // named twice: still one key to try
        list.push(limited(&keys[3], Perm::Read, "wy/s/storage"));
        let v = Verifier::new(vec![admin.verifying_key()], "s").with_limited(list);
        let plc = keyexpr::new("wy/s/downstream/plc/p/~set").unwrap();
        let last = &keys[29];
        let mut jti = 0;
        let mut check = |key: &ed25519_dalek::SigningKey, sub: &str| {
            jti += 1;
            let t = signed(key, sub, "wy/s/**", jti, 100);
            verifies(|| v.verify(&t, plc, None, 10))
        };
        // first sight of the subject: the keys in list order, the admin key first
        let (r, n) = check(last, "link:last");
        assert!(r.is_ok());
        assert_eq!(n, 31);
        for _ in 0..5 {
            let (r, n) = check(last, "link:last");
            assert!(r.is_ok());
            assert_eq!(n, 1, "the remembered key");
        }
        // a subject never seen: the key used last is tried first
        let (r, n) = check(last, "user:new");
        assert!(r.is_ok());
        assert_eq!(n, 1);
        let (r, n) = check(&admin, "user:admin");
        assert!(r.is_ok());
        assert_eq!(n, 2, "after the key used last");
        assert_eq!(check(&admin, "user:admin").1, 1);
        assert_eq!(check(last, "link:last").1, 1);
        // refused: every distinct key once, with a remembered subject or a new one
        let stranger = ed25519_dalek::SigningKey::from_bytes(&[99; 32]);
        for sub in ["link:last", "user:nobody"] {
            let (r, n) = check(&stranger, sub);
            assert_eq!(r, Err(Denied::Signature));
            assert_eq!(n, 31);
        }
    }

    /// The remembered signer is a hint only: a token that names a subject of another key is
    /// checked against its real signer and gets that signer's limits, and one that names a
    /// trusted subject without a trusted signature is refused.
    #[test]
    fn a_wrong_hint_never_accepts_and_never_widens() {
        let pool = pool();
        let (wide, narrow) = (&pool[0], &pool[1]);
        let stranger = ed25519_dalek::SigningKey::from_bytes(&[99; 32]);
        let v = Verifier::new(Vec::new(), "s").with_limited(vec![
            limited(wide, Perm::Config, "wy/s"),
            limited(narrow, Perm::Read, "wy/s/downstream/plc"),
        ]);
        let plc = keyexpr::new("wy/s/downstream/plc/p/~set").unwrap();
        let sys = keyexpr::new("wy/s/sys/~act/get_log").unwrap();
        let config = |key, jti, on: &keyexpr| {
            use ed25519_dalek::Signer;
            let claims = PtokClaims {
                sub: "user:ann".into(),
                grants: vec![g("wy/s/**", Perm::Config)],
                max: Perm::Config,
                iat: 1,
                exp: 100,
                jti: [jti; 16],
                site: "s".into(),
                ..Default::default()
            };
            let mut tok = vec![ptok::PTOK_VERSION];
            tok.extend(wyrm_core::codec::to_vec(&claims).unwrap());
            let sig = ed25519_dalek::SigningKey::sign(key, &tok);
            tok.extend(sig.to_bytes());
            v.verify_signed(&tok, on, None, 10)
        };
        // `user:ann` is remembered with the wide key
        assert_eq!(config(wide, 1, sys).unwrap().1, Perm::Config);
        assert_eq!(config(wide, 2, sys).unwrap().1, Perm::Config);
        // the narrow key signs for the same subject: its own cap and scopes, nothing more
        let (_, perm, scopes) = config(narrow, 3, plc).unwrap();
        assert_eq!(perm, Perm::Read);
        assert_eq!(
            scopes,
            Some(vec![("wy/s/downstream/plc".to_owned(), Perm::Read)])
        );
        assert_eq!(config(narrow, 4, sys), Err(Denied::NoGrant));
        // nobody's key under a remembered subject
        assert_eq!(config(&stranger, 5, sys), Err(Denied::Signature));
        assert_eq!(config(wide, 6, sys).unwrap().1, Perm::Config);
    }

    /// A new trust list forgets every remembered signer with the list it was learned on, and
    /// a key that left the list signs nothing from then on.
    #[test]
    fn a_new_trust_list_starts_without_hints() {
        let pool = pool();
        let (a, b) = (&pool[0], &pool[1]);
        let list = |keys: &[&ed25519_dalek::SigningKey]| -> Vec<LimitedKey> {
            keys.iter()
                .map(|k| limited(k, Perm::Write, "wy/s/downstream"))
                .collect()
        };
        let v = Verifier::new(Vec::new(), "s").with_limited(list(&[a, b]));
        let plc = keyexpr::new("wy/s/downstream/plc/p/~set").unwrap();
        let hints = |v: &Verifier| v.trust.read().unwrap().hints.lock().unwrap().len();
        assert!(v
            .verify(&signed(b, "link:b", "wy/s/**", 1, 100), plc, None, 10)
            .is_ok());
        assert_eq!(hints(&v), 1);
        // `b` leaves; `a` now stands where the remembered index of `link:b` pointed
        v.set_trust(Vec::new(), list(&[a]));
        assert_eq!(hints(&v), 0);
        assert_eq!(
            v.verify(&signed(b, "link:b", "wy/s/**", 2, 100), plc, None, 10),
            Err(Denied::Signature)
        );
        assert_eq!(hints(&v), 0, "a refused token is not remembered");
        v.set_trust(Vec::new(), Vec::new());
        assert_eq!(
            v.verify(&signed(a, "link:a", "wy/s/**", 3, 100), plc, None, 10),
            Err(Denied::Signature)
        );
        // the replay cache is the verifier's, not the list's
        v.set_trust(Vec::new(), list(&[a, b]));
        assert_eq!(
            v.verify(&signed(b, "link:b", "wy/s/**", 1, 100), plc, None, 10),
            Err(Denied::Replayed)
        );
    }

    /// What is remembered is bounded and comes from accepted tokens only.
    #[test]
    fn the_hints_are_bounded_and_only_of_accepted_tokens() {
        let key = ed25519_dalek::SigningKey::from_bytes(&[7; 32]);
        let v = Verifier::new(vec![key.verifying_key()], "s");
        let plc = keyexpr::new("wy/s/downstream/plc/p/~set").unwrap();
        let hints = |v: &Verifier| v.trust.read().unwrap().hints.lock().unwrap().len();
        // signed by a trusted key, refused later: no grant here, expired, another site
        let no_grant = signed(&key, "user:a", "wy/s/storage/**", 1, 100);
        assert_eq!(v.verify(&no_grant, plc, None, 10), Err(Denied::NoGrant));
        let expired = signed(&key, "user:b", "wy/s/**", 2, 5);
        assert_eq!(v.verify(&expired, plc, None, 10), Err(Denied::Expired));
        assert_eq!(hints(&v), 0);
        // a subject too long to remember is verified as any other
        let long = format!("user:{}", "x".repeat(HINT_SUB_MAX));
        assert!(v
            .verify(&signed(&key, &long, "wy/s/**", 3, 100), plc, None, 10)
            .is_ok());
        assert_eq!(hints(&v), 0);
        let t = v.trust.read().unwrap().clone();
        for i in 0..HINTS_MAX + 500 {
            t.remember(&format!("user:u{i}"), 0);
        }
        assert_eq!(hints(&v), HINTS_MAX);
        // the newest is there
        assert_eq!(t.hint(&format!("user:u{}", HINTS_MAX + 499)), Some(0));
    }
}
