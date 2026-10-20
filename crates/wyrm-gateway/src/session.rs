//! Stateless session tokens:
//! `base64url(0x01 || cbor({sub, roles, exp, iat, jti, gen}) || hmac_sha256)`.
//! The MAC key is derived from the gateway's state key, never the key itself.

use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;
use hmac::{Hmac, Mac};
use sha2::Sha256;
use std::collections::BTreeMap;
use std::time::{SystemTime, UNIX_EPOCH};
use wyrm_core::Value;
use zeroize::Zeroizing;

type HmacSha256 = Hmac<Sha256>;

pub const SESSION_VERSION: u8 = 0x01;
const TAG_LEN: usize = 32;
/// Upper bound on an encoded token; anything longer is not ours.
const MAX_TOKEN: usize = 4096;

#[derive(Debug, Clone, PartialEq)]
pub struct SessionClaims {
    /// User name (the ptok subject is `user:<sub>`).
    pub sub: String,
    /// Roles at login; informational, the store decides on every request.
    pub roles: Vec<String>,
    pub exp: u64,
    pub iat: u64,
    pub jti: [u8; 16],
    /// User generation at login (see `users::User::gen`).
    pub gen: u64,
}

pub fn now_s() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

pub struct SessionKey(Zeroizing<Vec<u8>>);

impl SessionKey {
    /// `HMAC(state_key, "wyrm-gateway/session/v1")`.
    pub fn derive(state_key: &[u8]) -> Self {
        let mut m = HmacSha256::new_from_slice(state_key).expect("hmac takes any key length");
        m.update(b"wyrm-gateway/session/v1");
        Self(Zeroizing::new(m.finalize().into_bytes().to_vec()))
    }

    fn mac(&self) -> HmacSha256 {
        HmacSha256::new_from_slice(&self.0).expect("hmac takes any key length")
    }

    pub fn mint(&self, c: &SessionClaims) -> String {
        let mut tok = vec![SESSION_VERSION];
        tok.extend(wyrm_core::codec::to_vec(&encode(c)).expect("claims always encode"));
        let mut m = self.mac();
        m.update(&tok);
        tok.extend(m.finalize().into_bytes());
        URL_SAFE_NO_PAD.encode(tok)
    }

    /// Check the MAC (constant time) and expiry. `None` on any failure.
    pub fn verify(&self, token: &str, now: u64) -> Option<SessionClaims> {
        if token.len() > MAX_TOKEN {
            return None;
        }
        let raw = URL_SAFE_NO_PAD.decode(token.trim()).ok()?;
        if raw.len() < 1 + TAG_LEN + 1 || raw[0] != SESSION_VERSION {
            return None;
        }
        let (signed, tag) = raw.split_at(raw.len() - TAG_LEN);
        let mut m = self.mac();
        m.update(signed);
        m.verify_slice(tag).ok()?;
        let c = decode(&wyrm_core::codec::from_slice(&signed[1..]).ok()?)?;
        (now < c.exp).then_some(c)
    }
}

fn encode(c: &SessionClaims) -> Value {
    Value::Map(BTreeMap::from([
        ("sub".to_owned(), Value::from(c.sub.as_str())),
        (
            "roles".to_owned(),
            Value::Array(c.roles.iter().map(|r| Value::from(r.as_str())).collect()),
        ),
        ("exp".to_owned(), Value::UInt(c.exp)),
        ("iat".to_owned(), Value::UInt(c.iat)),
        ("jti".to_owned(), Value::Bytes(c.jti.to_vec())),
        ("gen".to_owned(), Value::UInt(c.gen)),
    ]))
}

fn decode(v: &Value) -> Option<SessionClaims> {
    let Value::Map(m) = v else { return None };
    let uint = |k: &str| match m.get(k) {
        Some(Value::UInt(u)) => Some(*u),
        _ => None,
    };
    let Some(Value::Str(sub)) = m.get("sub") else {
        return None;
    };
    let Some(Value::Array(roles)) = m.get("roles") else {
        return None;
    };
    let Some(Value::Bytes(jti)) = m.get("jti") else {
        return None;
    };
    Some(SessionClaims {
        sub: sub.clone(),
        roles: roles
            .iter()
            .map(|r| match r {
                Value::Str(s) => Some(s.clone()),
                _ => None,
            })
            .collect::<Option<_>>()?,
        exp: uint("exp")?,
        iat: uint("iat")?,
        jti: jti.as_slice().try_into().ok()?,
        gen: uint("gen")?,
    })
}

pub fn new_jti() -> [u8; 16] {
    let mut j = [0u8; 16];
    // A failing OS RNG leaves zeros; the MAC still binds the token, so this
    // only weakens uniqueness, which nothing relies on for security.
    let _ = getrandom::fill(&mut j);
    j
}

#[cfg(test)]
mod tests {
    use super::*;

    fn claims(exp: u64) -> SessionClaims {
        SessionClaims {
            sub: "olena".into(),
            roles: vec!["operator".into()],
            exp,
            iat: 100,
            jti: [3; 16],
            gen: 1,
        }
    }

    #[test]
    fn round_trip_tamper_expiry() {
        let k = SessionKey::derive(b"state key");
        let t = k.mint(&claims(200));
        assert_eq!(k.verify(&t, 150), Some(claims(200)));
        assert_eq!(k.verify(&t, 200), None, "expired at exp");
        assert_eq!(SessionKey::derive(b"other").verify(&t, 150), None);
        let mut raw = URL_SAFE_NO_PAD.decode(&t).unwrap();
        raw[5] ^= 1;
        assert_eq!(k.verify(&URL_SAFE_NO_PAD.encode(&raw), 150), None);
        assert_eq!(k.verify("not a token", 150), None);
    }
}
