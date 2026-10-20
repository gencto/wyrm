//! `ptok` sources for requests that need one (`~set`, `~act`, restricted
//! `~meta`). Tokens are single-use (`jti`), so a source mints one per request.

use ed25519_dalek::{Signer, SigningKey};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use wyrm_core::ptok::{Grant, PtokClaims, PTOK_VERSION};
use wyrm_core::Perm;
use zenoh::key_expr::keyexpr;

pub trait TokenSource: Send + Sync + 'static {
    /// A fresh token for a request on `key` (full key with suffix), or `None`.
    fn token(&self, key: &str) -> Option<Vec<u8>>;
}

/// `0x01 || cbor(claims) || ed25519(version || claims)`.
pub fn sign(key: &SigningKey, claims: &PtokClaims) -> Vec<u8> {
    let mut tok = vec![PTOK_VERSION];
    tok.extend(wyrm_core::codec::to_vec(claims).expect("claims always encode"));
    let sig = key.sign(&tok);
    tok.extend(sig.to_bytes());
    tok
}

/// Mints tokens locally with an admin signing key. For tools and tests on a
/// trusted host; `wyrm-admin` will issue tokens for users.
pub struct SigningTokens {
    key: SigningKey,
    site: String,
    sub: String,
    grants: Vec<Grant>,
    max: Perm,
    ttl: Duration,
    counter: AtomicU64,
}

impl SigningTokens {
    /// Defaults: `sub = "svc:wyr"`, one grant `wy/<site>/**` at `config`,
    /// `max = config`, 60 s lifetime.
    pub fn new(key: SigningKey, site: impl Into<String>) -> Self {
        let site = site.into();
        Self {
            grants: vec![Grant {
                k: format!("wy/{site}/**"),
                p: Perm::Config,
            }],
            key,
            site,
            sub: "svc:wyr".into(),
            max: Perm::Config,
            ttl: Duration::from_secs(60),
            counter: AtomicU64::new(0),
        }
    }

    pub fn subject(mut self, sub: impl Into<String>) -> Self {
        self.sub = sub.into();
        self
    }

    /// Replace the grants (first intersecting grant wins at the responder).
    pub fn grants(mut self, grants: Vec<Grant>) -> Self {
        self.grants = grants;
        self
    }

    pub fn max(mut self, max: Perm) -> Self {
        self.max = max;
        self
    }

    pub fn ttl(mut self, ttl: Duration) -> Self {
        self.ttl = ttl;
        self
    }

    fn jti(&self) -> [u8; 16] {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_nanos() as u64)
            .unwrap_or(0);
        let mut jti = [0u8; 16];
        jti[..8].copy_from_slice(&nanos.to_be_bytes());
        jti[8..].copy_from_slice(&self.counter.fetch_add(1, Ordering::Relaxed).to_be_bytes());
        jti
    }
}

impl SigningTokens {
    /// The single grant of a token for `key`: exactly that key, at the level
    /// of the first configured grant that covers it. `None` if none covers it.
    fn scoped(&self, key: &str) -> Option<Grant> {
        let target = keyexpr::new(key).ok()?;
        let g = self
            .grants
            .iter()
            .find(|g| keyexpr::new(&g.k).is_ok_and(|k| k.intersects(target)))?;
        Some(Grant {
            k: key.to_owned(),
            p: g.p,
        })
    }
}

impl TokenSource for SigningTokens {
    /// A token valid only for `key`: a captured token cannot be spent on
    /// another node or link (the `jti` replay cache is per responder).
    fn token(&self, key: &str) -> Option<Vec<u8>> {
        let grant = self.scoped(key)?;
        let now = SystemTime::now().duration_since(UNIX_EPOCH).ok()?.as_secs();
        let claims = PtokClaims {
            sub: self.sub.clone(),
            roles: Vec::new(),
            grants: vec![grant],
            max: self.max,
            iat: now,
            exp: now + self.ttl.as_secs().max(1),
            jti: self.jti(),
            site: self.site.clone(),
        };
        Some(sign(&self.key, &claims))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn claims_of(tok: &[u8]) -> PtokClaims {
        let parts = wyrm_core::ptok::split(tok).unwrap();
        wyrm_core::codec::from_slice(parts.claims).unwrap()
    }

    #[test]
    fn tokens_are_scoped_to_the_request_key() {
        let key = SigningKey::from_bytes(&[1; 32]);
        let src = SigningTokens::new(key, "s").grants(vec![
            Grant {
                k: "wy/s/down/plc1/**".into(),
                p: Perm::Write,
            },
            Grant {
                k: "wy/s/down/**".into(),
                p: Perm::Read,
            },
        ]);
        let c = claims_of(&src.token("wy/s/down/plc1/fan/~set").unwrap());
        assert_eq!(
            c.grants,
            [Grant {
                k: "wy/s/down/plc1/fan/~set".into(),
                p: Perm::Write
            }]
        );
        // first covering grant decides the level
        let c = claims_of(&src.token("wy/s/down/mock/p0/~set").unwrap());
        assert_eq!(c.grants[0].p, Perm::Read);
        // nothing covers it: no token at all
        assert!(src.token("wy/other/down/x/~set").is_none());
        // fresh jti per token
        let a = claims_of(&src.token("wy/s/down/plc1/fan/~set").unwrap());
        let b = claims_of(&src.token("wy/s/down/plc1/fan/~set").unwrap());
        assert_ne!(a.jti, b.jti);
    }
}
