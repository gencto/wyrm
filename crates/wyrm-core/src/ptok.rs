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
    // a `$*` in the key: which grants it touches is not decided here, so nothing is given
    // (a deny grant it touches could be skipped otherwise; automated review of f8a5d6c)
    if key.contains('$') {
        return Perm::None;
    }
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

/// Longest `ptok` a responder reads (spec 04 0.2.36): version, claims and signature. A longer
/// one is refused before any other work. A real token is far below it: one grant for the
/// request key and, on actions, the caller's grants in `auth` (about 550 grants of 100-byte
/// keys fit).
pub const MAX_PTOK_LEN: usize = 64 * 1024;

/// Most CBOR items [`peek_sub`] passes over before it gives up.
const PEEK_ITEMS: usize = 4096;

/// One CBOR head at `at`: `(major type, argument, where the next byte is)`. `None` at the end
/// of the bytes, for a reserved length and for an indefinite length (canonical CBOR, the only
/// form spec 04 writes, has none).
fn head(b: &[u8], at: usize) -> Option<(u8, u64, usize)> {
    let first = *b.get(at)?;
    let at = at.checked_add(1)?;
    let n: usize = match first & 0x1f {
        v @ 0..=23 => return Some((first >> 5, u64::from(v), at)),
        24 => 1,
        25 => 2,
        26 => 4,
        27 => 8,
        _ => return None,
    };
    let end = at.checked_add(n)?;
    let arg = b
        .get(at..end)?
        .iter()
        .fold(0u64, |v, x| (v << 8) | u64::from(*x));
    Some((first >> 5, arg, end))
}

/// The bytes of a text or byte string whose head said `len`, and where the next item is.
fn body(b: &[u8], at: usize, len: u64) -> Option<(&[u8], usize)> {
    let end = at.checked_add(usize::try_from(len).ok()?)?;
    Some((b.get(at..end)?, end))
}

/// Where the item after the one at `at` begins. It keeps one number (the items still to pass)
/// and no stack, so nesting of any depth costs no memory; `budget` bounds the items it reads.
fn pass(b: &[u8], mut at: usize, budget: &mut usize) -> Option<usize> {
    let mut todo: u64 = 1;
    while todo > 0 {
        *budget = budget.checked_sub(1)?;
        todo -= 1;
        let (major, arg, next) = head(b, at)?;
        at = next;
        match major {
            // a byte or text string: its bytes follow
            2 | 3 => at = body(b, at, arg)?.1,
            // an array of `arg` items, a map of `arg` pairs, a tag before one item
            4 => todo = todo.checked_add(arg)?,
            5 => todo = todo.checked_add(arg.checked_mul(2)?)?,
            6 => todo = todo.checked_add(1)?,
            // an integer, a simple value or a float: the head is all of it
            _ => {}
        }
    }
    Some(at)
}

/// The `sub` of encoded claims, read without decoding anything else. For claims whose
/// signature is NOT checked yet: the answer is the sender's word and may only pick which
/// trusted key a verifier tries first, never what it decides. `None` when the bytes are not a
/// claims map with a text `sub`, and for anything a canonical encoder does not write or
/// that is too long to walk (an indefinite length, more than 4096 items before `sub`).
///
/// It runs on bytes of anyone who may send a request, so it allocates nothing, whatever
/// they are: it is a walk over the heads with a counter (no decoder, no stack), at most one
/// pass over the bytes.
pub fn peek_sub(claims: &[u8]) -> Option<&str> {
    let mut budget = PEEK_ITEMS;
    let (major, pairs, mut at) = head(claims, 0)?;
    if major != 5 {
        return None;
    }
    for _ in 0..pairs {
        budget = budget.checked_sub(1)?;
        let (major, len, next) = head(claims, at)?;
        if major != 3 {
            // not a text key: over it and its value
            at = pass(claims, at, &mut budget)?;
            at = pass(claims, at, &mut budget)?;
            continue;
        }
        let (name, next) = body(claims, next, len)?;
        if name != b"sub" {
            at = pass(claims, next, &mut budget)?;
            continue;
        }
        let (major, len, next) = head(claims, next)?;
        if major != 3 {
            return None;
        }
        return std::str::from_utf8(body(claims, next, len)?.0).ok();
    }
    None
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
    fn peek_sub_reads_only_the_subject() {
        let claims = PtokClaims {
            sub: "user:ann".into(),
            roles: vec!["operator".into()],
            grants: vec![Grant {
                k: "wy/s/**".into(),
                p: Perm::Write,
            }],
            auth: Some(Vec::new()),
            args: Some([9; 32]),
            ..Default::default()
        };
        let bytes = crate::codec::encode_to_vec(&claims);
        assert_eq!(peek_sub(&bytes), Some("user:ann"));
        // not claims: nothing, and never a panic
        assert_eq!(peek_sub(&[]), None);
        assert_eq!(peek_sub(&[0xff; 40]), None);
        assert_eq!(
            peek_sub(&[0xbf, 0x63, b's', b'u', b'b', 0x61, b'x', 0xff]),
            None
        );
        for cut in 0..bytes.len() {
            let _ = peek_sub(&bytes[..cut]);
        }
        // a map without `sub`, and one whose `sub` is not text
        assert_eq!(peek_sub(&[0xa1, 0x63, b'e', b'x', b'p', 0x01]), None);
        assert_eq!(peek_sub(&[0xa1, 0x63, b's', b'u', b'b', 0x01]), None);
        // an indefinite-length map, array or string anywhere: no answer (never written by a
        // canonical encoder), also before a `sub` that is there
        let sub = [0x63, b's', b'u', b'b', 0x61, b'x'];
        for bad in [
            &[0x9f, 0xff][..],
            &[0xbf, 0xff],
            &[0x5f, 0xff],
            &[0x7f, 0xff],
        ] {
            let mut c = vec![0xa2, 0x00];
            c.extend(bad);
            c.extend(sub);
            assert_eq!(peek_sub(&c), None, "{bad:02x?}");
        }
        // nested containers and a tag before it are passed over
        let mut c = vec![0xa2, 0x00, 0x82, 0xa1, 0x01, 0x81, 0xc1, 0x02, 0x41, 0x00];
        c.extend(sub);
        assert_eq!(peek_sub(&c), Some("x"));
        // lengths that point beyond the bytes or overflow
        assert_eq!(
            peek_sub(&[0xa1, 0x7b, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff]),
            None
        );
        assert_eq!(
            peek_sub(&[0xbb, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff]),
            None
        );
        assert_eq!(
            peek_sub(&[0xa2, 0x00, 0x9b, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff]),
            None
        );
        assert_eq!(
            peek_sub(&[0xa2, 0x00, 0xbb, 0x80, 0, 0, 0, 0, 0, 0, 0]),
            None,
            "pairs × 2 overflows"
        );
        // not UTF-8
        assert_eq!(peek_sub(&[0xa1, 0x63, b's', b'u', b'b', 0x61, 0xff]), None);
        // more items before `sub` than the walk reads: no answer
        let mut c = vec![0xa2, 0x00, 0x99, 0x20, 0x00];
        c.extend(std::iter::repeat_n(0x00, 0x2000));
        c.extend(sub);
        assert_eq!(peek_sub(&c), None);
        // deep definite nesting: one array in another, 60 000 times
        let mut c = vec![0xa2, 0x00];
        c.extend(std::iter::repeat_n(0x81, 60_000));
        c.push(0x00);
        c.extend(sub);
        assert_eq!(peek_sub(&c), None, "beyond the item budget");
        let mut c = vec![0xa2, 0x00];
        c.extend(std::iter::repeat_n(0x81, 1000));
        c.push(0x00);
        c.extend(sub);
        assert_eq!(peek_sub(&c), Some("x"), "depth alone costs nothing");
        // the peek agrees with the decoder on what an encoder writes
        for n in [0usize, 1, 50, 400] {
            let claims = PtokClaims {
                sub: format!("user:{n}"),
                grants: (0..n)
                    .map(|i| Grant {
                        k: format!("wy/s/downstream/l{i}/**"),
                        p: Perm::Read,
                    })
                    .collect(),
                auth: Some(Vec::new()),
                ..Default::default()
            };
            let bytes = crate::codec::encode_to_vec(&claims);
            assert_eq!(peek_sub(&bytes), Some(claims.sub.as_str()));
        }
        // integer keys are passed over
        assert_eq!(
            peek_sub(&[0xa2, 0x01, 0x02, 0x63, b's', b'u', b'b', 0x61, b'x']),
            Some("x")
        );
    }

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
        // a `$*` key gets nothing: `plc1` (none) touches `plc$*`, Zenoh says
        let g = [("wy/s/plc1", Perm::None), ("wy/s/**", Perm::Write)];
        assert_eq!(level_on(g, "wy/s/plc$*"), Perm::None);
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
