//! `ptok v1` verification in the responder. Spec: 04-attachment.
//!
//! Order (normative): version → signature → `exp > now` → `site` → `jti` not
//! replayed → first grant whose key expression intersects the request key →
//! `effective = min(p, max, maxperm)`. Any failure is `permission_denied`
//! with no detail; the reason goes to `debug` logs only (never the token).

use ed25519_dalek::{Signature, VerifyingKey};
use std::collections::HashMap;
use std::sync::Mutex;
use wyrm_core::ptok::{self, PtokClaims};
use wyrm_core::Perm;
use zenoh::key_expr::keyexpr;

/// Upper bound on remembered `jti`s. When full and nothing has expired,
/// new tokens are refused (fail closed).
const REPLAY_CAPACITY: usize = 65_536;

/// Who is calling, as established by the SDK before the driver runs.
#[derive(Debug, Clone, Default)]
pub struct Caller {
    /// `attachment.origin`, trusted only with a valid `ptok`; `None` otherwise.
    pub origin: Option<String>,
    /// Effective permission for this request.
    pub perm: Perm,
    pub claims: Option<PtokClaims>,
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
}

impl LimitedKey {
    fn covers(&self, key: &str) -> bool {
        self.scopes.iter().any(|s| {
            key == s
                || key
                    .strip_prefix(s.as_str())
                    .is_some_and(|r| r.starts_with('/'))
        })
    }
}

#[derive(Debug)]
pub struct Verifier {
    /// Admin keys (up to `config`, everywhere) and limited keys; replaced
    /// as a whole by [`set_trust`](Self::set_trust), the replay cache stays.
    trust: std::sync::RwLock<(Vec<VerifyingKey>, Vec<LimitedKey>)>,
    site: String,
    replay: Mutex<HashMap<[u8; 16], u64>>,
}

impl Verifier {
    /// `keys`: the active admin key and optionally the previous one.
    pub fn new(keys: Vec<VerifyingKey>, site: impl Into<String>) -> Self {
        Self {
            trust: std::sync::RwLock::new((keys, Vec::new())),
            site: site.into(),
            replay: Mutex::new(HashMap::new()),
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
        let parts = ptok::split(token).ok_or(Denied::Malformed)?;
        let sig = Signature::from_bytes(parts.sig);
        let trust = self.trust.read().unwrap_or_else(|p| p.into_inner());
        let (keys, limited) = &*trust;
        let cap = if keys
            .iter()
            .any(|k| k.verify_strict(parts.signed, &sig).is_ok())
        {
            Perm::Config
        } else {
            let signers: Vec<&LimitedKey> = limited
                .iter()
                .filter(|l| l.key.verify_strict(parts.signed, &sig).is_ok())
                .collect();
            if signers.is_empty() {
                return Err(Denied::Signature);
            }
            signers
                .iter()
                .filter(|l| l.covers(key.as_str()))
                .map(|l| l.cap)
                .max()
                .ok_or(Denied::NoGrant)?
        };
        drop(trust);
        let claims: PtokClaims =
            wyrm_core::codec::from_slice(parts.claims).map_err(|_| Denied::Malformed)?;
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
        self.remember(claims.jti, claims.exp, now)?;
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
        Ok((claims, perm))
    }

    fn remember(&self, jti: [u8; 16], exp: u64, now: u64) -> Result<(), Denied> {
        let mut cache = self.replay.lock().unwrap_or_else(|p| p.into_inner());
        if cache.contains_key(&jti) {
            return Err(Denied::Replayed);
        }
        if cache.len() >= REPLAY_CAPACITY {
            cache.retain(|_, e| *e > now);
            if cache.len() >= REPLAY_CAPACITY {
                return Err(Denied::ReplayCacheFull);
            }
        }
        cache.insert(jti, exp);
        Ok(())
    }
}
