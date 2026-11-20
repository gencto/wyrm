//! A refused `ptok` costs the responder no memory worth the name (security audit of PR #150).
//!
//! The verifier reads the `sub` of a token before its signature is checked
//! (`wyrm_core::ptok::peek_sub`), on bytes of anyone who may send a request. A CBOR decoder
//! that passes over nested indefinite-length containers keeps a stack as deep as the nesting:
//! with it, 64 KiB of `0x9f` cost 3 MiB and 16 MiB cost 805 MiB, for a request that is refused.
//! This binary runs on the counting allocator and measures what those inputs allocate now.
//!
//! One test only: the counters are the process's, and a second test thread would add to them.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    reason = "test code: a failed step fails the test"
)]

use ed25519_dalek::{Signer, SigningKey};
use wyrm_bench::Allocs;
use wyrm_core::ptok::{peek_sub, Grant, PtokClaims, MAX_PTOK_LEN, PTOK_VERSION, SIG_LEN};
use wyrm_core::Perm;
use wyrm_link_sdk::auth::{Denied, LimitedKey, Verifier};
use zenoh::key_expr::keyexpr;

#[global_allocator]
static A: wyrm_bench::Counting = wyrm_bench::Counting;

/// What `f` allocated.
fn allocated<T>(f: impl FnOnce() -> T) -> (T, Allocs) {
    let before = Allocs::read();
    let out = f();
    (out, Allocs::read().since(before))
}

/// Claims that are a map with one integer key before `filler`, then a `sub`.
fn claims(filler: &[u8]) -> Vec<u8> {
    let mut c = vec![0xa2, 0x00];
    c.extend(filler);
    c.extend([0x63, b's', b'u', b'b', 0x68]);
    c.extend(b"user:ann");
    c
}

/// A token with these claims and a signature of `key`.
fn token(key: &SigningKey, claims: &[u8]) -> Vec<u8> {
    let mut t = vec![PTOK_VERSION];
    t.extend(claims);
    let sig = key.sign(&t);
    t.extend(sig.to_bytes());
    t
}

#[test]
fn a_refused_token_allocates_next_to_nothing() {
    assert!(Allocs::active(), "the counting allocator is installed");
    let room = MAX_PTOK_LEN - 1 - SIG_LEN - 16;
    // the audit's input: an array of three, then nothing but openings of indefinite arrays
    let mut indefinite = vec![0x83, 0x00];
    indefinite.resize(room, 0x9f);
    // the same depth with definite lengths: one array in another
    let mut definite = vec![0x81; room - 1];
    definite.push(0x00);
    // maps in maps, a tag before every one
    let nested_maps: Vec<u8> = [0xc1, 0xa1, 0x00].repeat(room / 3 - 1);
    // far beyond the longest token
    let huge = vec![0x9f; 16 * 1024 * 1024];

    let attacks: Vec<(&str, Vec<u8>)> = vec![
        ("indefinite nesting", claims(&indefinite)),
        ("definite nesting", claims(&definite)),
        ("tagged maps", claims(&nested_maps)),
        ("16 MiB", claims(&huge)),
        ("empty", Vec::new()),
    ];
    for (name, c) in &attacks {
        let (sub, a) = allocated(|| peek_sub(c));
        assert_eq!(sub, None, "{name}: no hint");
        assert_eq!(
            (a.calls, a.bytes),
            (0, 0),
            "{name}: the peek allocates nothing"
        );
    }
    // and nothing for what it does answer
    let good = claims(&[0x00]);
    let (sub, a) = allocated(|| peek_sub(&good));
    assert_eq!(sub, Some("user:ann"));
    assert_eq!((a.calls, a.bytes), (0, 0));

    // through the verifier, with an admin key and 30 limited keys
    let admin = SigningKey::from_bytes(&[1; 32]);
    let stranger = SigningKey::from_bytes(&[9; 32]);
    let limited: Vec<LimitedKey> = (0..30u8)
        .map(|i| LimitedKey {
            key: SigningKey::from_bytes(&[100 + i; 32]).verifying_key(),
            cap: Perm::Write,
            scopes: vec!["wy/s/downstream".to_owned()],
            subject: None,
        })
        .collect();
    let v = Verifier::new(vec![admin.verifying_key()], "s").with_limited(limited);
    let key = keyexpr::new("wy/s/downstream/plc/p/~set").unwrap();
    for (name, c) in &attacks {
        // signed by nobody the verifier trusts
        let t = token(&stranger, c);
        let (r, a) = allocated(|| v.verify(&t, key, None, 10));
        let want = if t.len() > MAX_PTOK_LEN {
            Denied::TooLarge
        } else if c.is_empty() {
            Denied::Malformed
        } else {
            Denied::Signature
        };
        assert_eq!(r, Err(want), "{name}");
        // the order of the keys and one small buffer per signature check; with the
        // decoder's stack this was 48 bytes per nested container (3 MiB at 64 KiB)
        assert!(a.bytes < 8 * 1024, "{name}: {} bytes allocated", a.bytes);
        if t.len() > MAX_PTOK_LEN {
            assert_eq!(a.calls, 0, "{name}: refused by its length, before any work");
        }
    }

    // the longest real token: one grant, and so many of the caller's grants in `auth` that
    // it ends just below the bound; accepted, with one signature check's worth of memory
    // beside the claims it returns
    let grant = |i: usize| Grant {
        k: format!("wy/s/downstream/link{i:04}/**"),
        p: Perm::Write,
    };
    let mut n = 3000;
    let longest = loop {
        let c = PtokClaims {
            sub: "user:ann".into(),
            roles: vec!["operator".into()],
            grants: vec![Grant {
                k: "wy/s/downstream/**".into(),
                p: Perm::Write,
            }],
            max: Perm::Write,
            iat: 1,
            exp: 100,
            jti: [7; 16],
            site: "s".into(),
            auth: Some((0..n).map(grant).collect()),
            args: None,
        };
        let t = token(&admin, &wyrm_core::codec::to_vec(&c).unwrap());
        if t.len() <= MAX_PTOK_LEN {
            break t;
        }
        n -= 1;
    };
    assert!(n > 1500, "{n} grants of 31 bytes fit");
    assert!(longest.len() > MAX_PTOK_LEN - 64, "just below the bound");
    let (claims, perm) = v.verify(&longest, key, None, 10).unwrap();
    assert_eq!(perm, Perm::Write);
    assert_eq!(claims.auth.map(|a| a.len()), Some(n));
    // one byte more is refused
    let mut over = longest.clone();
    over.resize(MAX_PTOK_LEN + 1, 0);
    assert_eq!(v.verify(&over, key, None, 10), Err(Denied::TooLarge));
}
