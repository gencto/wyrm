//! Permission token `ptok v1`. Spec: 04-attachment.
//!
//! `ptok = 0x01 || cbor(claims) || ed25519_sig(64)`; the signature covers
//! `version || claims` exactly as received. This module only parses and
//! encodes; signature checks live in the responder SDK.

use crate::meta::Perm;
use minicbor::data::Type;
use minicbor::{decode, encode, Decode, Decoder, Encode, Encoder};

pub const PTOK_VERSION: u8 = 0x01;
pub const SIG_LEN: usize = 64;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Grant {
    /// Zenoh key expression.
    pub k: String,
    pub p: Perm,
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct PtokClaims {
    pub sub: String,
    pub roles: Vec<String>,
    pub grants: Vec<Grant>,
    pub max: Perm,
    pub iat: u64,
    pub exp: u64,
    pub jti: [u8; 16],
    pub site: String,
    /// The caller's full grant set on this site (spec 04 0.2.10), on `~act/*` tokens only. It
    /// never authorizes the request: a responder acting for the caller checks the keys the caller
    /// names against it. `None` = not sent (the caller's rights are unknown).
    pub auth: Option<Vec<Grant>>,
}

/// A grant of site `own` as it reads on site `site` (ADR 0018): `wy/<own>…` becomes
/// `wy/<site>…`, any other pattern (`wy/**`) stays. The gateway mints a user's tokens for a
/// downstream site with it, and a link acting for the user checks that site's keys with it.
pub fn grant_for_site(k: &str, own: &str, site: &str) -> String {
    let own = format!("wy/{own}");
    match k.strip_prefix(&own) {
        Some(rest) if rest.is_empty() || rest.starts_with('/') => format!("wy/{site}{rest}"),
        _ => k.to_owned(),
    }
}

/// Raw parts of a token: `(signed_bytes, claims_bytes, signature)`.
/// `signed_bytes` = `version || claims`.
pub struct PtokParts<'a> {
    pub signed: &'a [u8],
    pub claims: &'a [u8],
    pub sig: &'a [u8; SIG_LEN],
}

/// Split a token into its parts. `None` if too short or wrong version.
pub fn split(ptok: &[u8]) -> Option<PtokParts<'_>> {
    if ptok.len() < 1 + SIG_LEN + 1 || ptok[0] != PTOK_VERSION {
        return None;
    }
    let (signed, sig) = ptok.split_at(ptok.len() - SIG_LEN);
    Some(PtokParts {
        signed,
        claims: &signed[1..],
        sig: sig.try_into().ok()?,
    })
}

impl<C> Encode<C> for Grant {
    fn encode<W: encode::Write>(
        &self,
        e: &mut Encoder<W>,
        _ctx: &mut C,
    ) -> Result<(), encode::Error<W::Error>> {
        e.map(2)?
            .str("k")?
            .str(&self.k)?
            .str("p")?
            .u8(self.p.code())?;
        Ok(())
    }
}

impl<C> Encode<C> for PtokClaims {
    fn encode<W: encode::Write>(
        &self,
        e: &mut Encoder<W>,
        ctx: &mut C,
    ) -> Result<(), encode::Error<W::Error>> {
        // canonical order (length first): exp iat jti max sub auth site roles grants
        e.map(if self.auth.is_some() { 9 } else { 8 })?;
        e.str("exp")?.u64(self.exp)?;
        e.str("iat")?.u64(self.iat)?;
        e.str("jti")?.bytes(&self.jti)?;
        e.str("max")?.u8(self.max.code())?;
        e.str("sub")?.str(&self.sub)?;
        if let Some(auth) = &self.auth {
            e.str("auth")?.array(auth.len() as u64)?;
            for g in auth {
                g.encode(e, ctx)?;
            }
        }
        e.str("site")?.str(&self.site)?;
        e.str("roles")?.array(self.roles.len() as u64)?;
        for r in &self.roles {
            e.str(r)?;
        }
        e.str("grants")?.array(self.grants.len() as u64)?;
        for g in &self.grants {
            g.encode(e, ctx)?;
        }
        Ok(())
    }
}

/// Unknown levels are a decode error: the token is refused, never widened.
fn perm(d: &mut Decoder<'_>) -> Result<Perm, decode::Error> {
    let c = d.u8()?;
    Perm::try_from(c).map_err(|c| decode::Error::message(format!("bad perm {c}")))
}

fn map_len(d: &mut Decoder<'_>) -> Result<u64, decode::Error> {
    d.map()?
        .ok_or_else(|| decode::Error::message("indefinite map not allowed here"))
}

impl<'b, C> Decode<'b, C> for Grant {
    fn decode(d: &mut Decoder<'b>, _ctx: &mut C) -> Result<Self, decode::Error> {
        let (mut k, mut p) = (None, None);
        for _ in 0..map_len(d)? {
            match d.str()? {
                "k" => k = Some(d.str()?.to_owned()),
                "p" => p = Some(perm(d)?),
                _ => d.skip()?,
            }
        }
        Ok(Grant {
            k: k.ok_or_else(|| decode::Error::message("grant without k"))?,
            p: p.ok_or_else(|| decode::Error::message("grant without p"))?,
        })
    }
}

impl<'b, C> Decode<'b, C> for PtokClaims {
    fn decode(d: &mut Decoder<'b>, ctx: &mut C) -> Result<Self, decode::Error> {
        let mut c = PtokClaims::default();
        let mut seen_jti = false;
        for _ in 0..map_len(d)? {
            if !matches!(d.datatype()?, Type::String) {
                d.skip()?;
                d.skip()?;
                continue;
            }
            match d.str()? {
                "sub" => c.sub = d.str()?.to_owned(),
                "roles" => {
                    for r in d.array_iter::<&str>()? {
                        c.roles.push(r?.to_owned());
                    }
                }
                "grants" => {
                    for g in d.array_iter_with::<C, Grant>(ctx)? {
                        c.grants.push(g?);
                    }
                }
                "max" => c.max = perm(d)?,
                "iat" => c.iat = d.u64()?,
                "exp" => c.exp = d.u64()?,
                "jti" => {
                    c.jti = d
                        .bytes()?
                        .try_into()
                        .map_err(|_| decode::Error::message("jti must be 16 bytes"))?;
                    seen_jti = true;
                }
                "site" => c.site = d.str()?.to_owned(),
                "auth" => {
                    let mut auth = Vec::new();
                    for g in d.array_iter_with::<C, Grant>(ctx)? {
                        auth.push(g?);
                    }
                    c.auth = Some(auth);
                }
                _ => d.skip()?,
            }
        }
        if !seen_jti {
            return Err(decode::Error::message("ptok without jti"));
        }
        Ok(c)
    }
}
