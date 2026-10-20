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

#[derive(Debug)]
pub struct Verifier {
    /// Trusted keys with the highest permission a token they sign can give
    /// (`config` for admin keys; lower for e.g. the flow or agent key).
    keys: Vec<(VerifyingKey, Perm)>,
    site: String,
    replay: Mutex<HashMap<[u8; 16], u64>>,
}

impl Verifier {
    /// `keys`: the active admin key and optionally the previous one.
    pub fn new(keys: Vec<VerifyingKey>, site: impl Into<String>) -> Self {
        Self {
            keys: keys.into_iter().map(|k| (k, Perm::Config)).collect(),
            site: site.into(),
            replay: Mutex::new(HashMap::new()),
        }
    }

    /// Also trust `keys`, each only up to its permission.
    pub fn with_limited(mut self, keys: Vec<(VerifyingKey, Perm)>) -> Self {
        self.keys.extend(keys);
        self
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
        let cap = self
            .keys
            .iter()
            .filter(|(k, _)| k.verify_strict(parts.signed, &sig).is_ok())
            .map(|(_, cap)| *cap)
            .max()
            .ok_or(Denied::Signature)?;
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
