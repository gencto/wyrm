//! `ptok` sources for requests that need one (`~set`, `~act`, restricted
//! `~meta`). Tokens are single-use (`jti`), so a source mints one per request.

use ed25519_dalek::{Signer, SigningKey};
use std::time::Duration;
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
    tok.extend(wyrm_core::codec::encode_to_vec(claims));
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
    args: Option<[u8; 32]>,
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
            args: None,
        }
    }

    /// Bind every token to one request payload: its SHA-256 (claim `args`, spec 04 0.2.14).
    /// For a human approval of exactly the arguments a dry run showed.
    pub fn bound_to(mut self, sha256: [u8; 32]) -> Self {
        self.args = Some(sha256);
        self
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
}

/// A token id (spec 04 `jti`: 16 bytes, single use per responder) from the one random
/// source: nobody can predict the id of a token that is not yet made, and two processes
/// that sign with one key never make the same one. Without randomness there is no id
/// and so no token.
fn new_jti() -> Option<[u8; 16]> {
    wyrm_core::rand::bytes()
        .inspect_err(|e| tracing::error!("no token made: {e}"))
        .ok()
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
        let now = wyrm_core::clock::now_s();
        let claims = PtokClaims {
            sub: self.sub.clone(),
            roles: Vec::new(),
            grants: vec![grant],
            max: self.max,
            iat: now,
            exp: now + self.ttl.as_secs().max(1),
            jti: new_jti()?,
            site: self.site.clone(),
            // an action may act for the caller on keys it names (spec 04 `auth`): only there
            auth: key.contains("/~act/").then(|| self.grants.clone()),
            args: self.args,
        };
        let token = sign(&self.key, &claims);
        // every responder refuses a longer one (spec 04 0.2.36): say so where it is made
        if token.len() > wyrm_core::ptok::MAX_PTOK_LEN {
            tracing::error!(
                sub = %self.sub,
                grants = self.grants.len(),
                "no token made: it is longer than 64 KiB (too many grants)"
            );
            return None;
        }
        Some(token)
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
                k: "wy/s/downstream/plc1/**".into(),
                p: Perm::Write,
            },
            Grant {
                k: "wy/s/downstream/**".into(),
                p: Perm::Read,
            },
        ]);
        let c = claims_of(&src.token("wy/s/downstream/plc1/fan/~set").unwrap());
        assert_eq!(
            c.grants,
            [Grant {
                k: "wy/s/downstream/plc1/fan/~set".into(),
                p: Perm::Write
            }]
        );
        // first covering grant decides the level
        let c = claims_of(&src.token("wy/s/downstream/mock/p0/~set").unwrap());
        assert_eq!(c.grants[0].p, Perm::Read);
        // nothing covers it: no token at all
        assert!(src.token("wy/other/downstream/x/~set").is_none());
        // fresh jti per token
        let a = claims_of(&src.token("wy/s/downstream/plc1/fan/~set").unwrap());
        let b = claims_of(&src.token("wy/s/downstream/plc1/fan/~set").unwrap());
        assert_ne!(a.jti, b.jti);
        // the caller's whole grant set travels on an action token only (spec 04 `auth`)
        assert_eq!(a.auth, None);
        let c = claims_of(&src.token("wy/s/downstream/dql/~act/run").unwrap());
        assert_eq!(c.grants.len(), 1);
        assert_eq!(c.auth.as_deref().map(<[Grant]>::len), Some(2));
    }
}
