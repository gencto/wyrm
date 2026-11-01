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
    /// SHA-256 of the request's payload as sent (spec 04 0.2.14): the token is good only for
    /// those exact arguments (a human approval of one dry-run payload). `None` = any payload.
    pub args: Option<[u8; 32]>,
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

/// The level `grants` give on `key` (spec 04): the first grant whose key expression intersects
/// `key` decides; none → `Perm::None`. Every evaluator of grants uses this one rule (the SDK, the
/// gateway and apps that act for a caller, review DQL-2), so a grant shadowed by an earlier one is
/// dead everywhere. `key` may be a pattern. Grants with a `$*` sub-segment wildcard are not
/// evaluated here: one that may touch `key` makes the answer `Perm::None` (never wider).
pub fn level_on<'a>(grants: impl IntoIterator<Item = (&'a str, Perm)>, key: &str) -> Perm {
    let key: Vec<&str> = key.split('/').collect();
    for (k, p) in grants {
        let g: Vec<&str> = k.split('/').collect();
        if k.contains('$') {
            if intersects(&g, &key, true) {
                return Perm::None;
            }
        } else if intersects(&g, &key, false) {
            return p;
        }
    }
    Perm::None
}

/// Most chunks a key expression may have here; longer ones intersect nothing.
const MAX_CHUNKS: usize = 64;

/// Zenoh key-expression intersection over chunks: `*` is one chunk, `**` zero or more. `loose`
/// reads any chunk with `$` as `*` (an over-estimate). A table over the chunk pairs, so many `**`
/// cost `len(a) × len(b)` steps, never more.
fn intersects(a: &[&str], b: &[&str], loose: bool) -> bool {
    if a.len() > MAX_CHUNKS || b.len() > MAX_CHUNKS {
        return false;
    }
    let chunk = |x: &str, y: &str| {
        x == y || x == "*" || y == "*" || (loose && (x.contains('$') || y.contains('$')))
    };
    let (n, m) = (a.len(), b.len());
    // t[i][j]: a[i..] intersects b[j..]
    let mut t = vec![vec![false; m + 1]; n + 1];
    t[n][m] = true;
    for i in (0..=n).rev() {
        for j in (0..=m).rev() {
            if i == n && j == m {
                continue;
            }
            t[i][j] = if i < n && a[i] == "**" {
                t[i + 1][j] || (j < m && t[i][j + 1])
            } else if j < m && b[j] == "**" {
                t[i][j + 1] || (i < n && t[i + 1][j])
            } else {
                i < n && j < m && chunk(a[i], b[j]) && t[i + 1][j + 1]
            };
        }
    }
    t[0][0]
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
        e.map(8 + u64::from(self.auth.is_some()) + u64::from(self.args.is_some()))?;
        e.str("exp")?.u64(self.exp)?;
        e.str("iat")?.u64(self.iat)?;
        e.str("jti")?.bytes(&self.jti)?;
        e.str("max")?.u8(self.max.code())?;
        e.str("sub")?.str(&self.sub)?;
        // canonical order: length first, then bytes ("args" < "auth" < "site")
        if let Some(h) = &self.args {
            e.str("args")?.bytes(h)?;
        }
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
                "args" => {
                    c.args = Some(
                        d.bytes()?
                            .try_into()
                            .map_err(|_| decode::Error::message("args must be 32 bytes"))?,
                    );
                }
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

#[cfg(test)]
mod level_tests {
    use super::*;

    #[test]
    fn the_first_intersecting_grant_decides() {
        let g = [
            ("wy/s/**", Perm::Read),
            ("wy/s/downstream/plc1/**", Perm::Write),
        ];
        // shadowed: the wider read grant comes first (review DQL-2)
        assert_eq!(level_on(g, "wy/s/downstream/plc1/t"), Perm::Read);
        let g = [
            ("wy/s/downstream/plc1/secret", Perm::None),
            ("wy/s/downstream/plc1/**", Perm::Write),
            ("wy/s/*/ahu/**", Perm::List),
        ];
        assert_eq!(level_on(g, "wy/s/downstream/plc1/secret"), Perm::None);
        assert_eq!(
            level_on(g, "wy/s/downstream/plc1"),
            Perm::Write,
            "`**` is zero chunks too"
        );
        assert_eq!(level_on(g, "wy/s/storage/ahu/fan"), Perm::List);
        assert_eq!(level_on(g, "wy/s/storage/x/ahu"), Perm::None);
        // patterns intersect too, as for a subscription
        assert_eq!(
            level_on(g, "wy/s/downstream/**"),
            Perm::None,
            "first: the secret"
        );
        assert_eq!(
            level_on([("wy/s/a/**", Perm::Read)], "wy/s/*/b"),
            Perm::Read
        );
        // `$*` grants never widen
        let g = [("wy/s/plc$*", Perm::None), ("wy/s/**", Perm::Write)];
        assert_eq!(level_on(g, "wy/s/plc1"), Perm::None);
        assert_eq!(level_on([("wy/s/p$*", Perm::Write)], "wy/s/p1"), Perm::None);
        assert_eq!(
            level_on(
                [("wy/s/p$*", Perm::Write), ("wy/s/**", Perm::Read)],
                "wy/s/q/r"
            ),
            Perm::Read
        );
        // many `**` stay cheap
        let deep = vec!["**"; 60].join("/");
        assert_eq!(
            level_on([(deep.as_str(), Perm::Read)], &format!("{deep}/x")),
            Perm::Read
        );
        assert_eq!(
            level_on([("a/**/b/**/c", Perm::Read)], "a/x/**/y/c"),
            Perm::Read
        );
        assert_eq!(level_on([("a/*/c", Perm::Read)], "a/c"), Perm::None);
    }
}
