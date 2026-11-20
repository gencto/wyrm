//! What one `ptok` check costs a responder (performance audit item 3). Before the fix the
//! verifier tried the admin keys, then every limited key, with one Ed25519 `verify_strict`
//! each, before it knew who signed; now it tries the key that last signed for the token's
//! `sub` first (`auth.rs`). `cargo bench -p wyrm-link-sdk --bench verify`.
//!
//! Per set of limited keys (1, 4, 10, 30; the broker trusts the flow, gateway, scheduler, DQL,
//! agent and requester keys and one per upstream grant, ADR 0013, 0046):
//!
//! * `admin`: signed by the admin key;
//! * `limited_first` / `limited_last`: signed by the first / the last limited key;
//! * `refused`: signed by a key nobody trusts (every trusted key is tried, then refused);
//! * `new_sub_last`: the last limited key, a `sub` never seen before in every token (a
//!   gateway's users);
//! * `mixed`: the limited keys take turns, each with its own `sub` (links and flows);
//! * `mixed_new_sub`: the limited keys take turns and every token has a new `sub`: nothing
//!   tells the signer beforehand (the worst case of the fix).
//!
//! Tokens are signed before the timed loop. A fresh verifier per case keeps the replay cache
//! (16 384 `jti` per subject) from refusing them. One `PERF` line per case (`tool/perf.sh`).

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::print_stdout,
    reason = "a benchmark run by hand: a failed step ends it, figures go to stdout"
)]

use ed25519_dalek::{Signer, SigningKey};
use std::time::Instant;
use wyrm_bench::{Allocs, Lat, Perf};
use wyrm_core::ptok::{Grant, PtokClaims, PTOK_VERSION};
use wyrm_core::Perm;
use wyrm_link_sdk::auth::{Denied, LimitedKey, Verifier};
use zenoh::key_expr::keyexpr;

#[global_allocator]
static A: wyrm_bench::Counting = wyrm_bench::Counting;

const SITE: &str = "bench";
const KEY: &str = "wy/bench/downstream/mock/g0/p0/~set";
/// Requests timed per case (after [`WARMUP`]).
const ROUNDS: usize = 4_000;
const WARMUP: usize = 200;

fn sign(key: &SigningKey, sub: &str, jti: u64) -> Vec<u8> {
    let now = wyrm_core::clock::now_s();
    let mut id = [0u8; 16];
    id[..8].copy_from_slice(&jti.to_be_bytes());
    let claims = PtokClaims {
        sub: sub.into(),
        roles: vec!["operator".into()],
        grants: vec![Grant {
            k: "wy/bench/downstream/**".into(),
            p: Perm::Write,
        }],
        max: Perm::Write,
        auth: None,
        args: None,
        iat: now,
        exp: now + 600,
        jti: id,
        site: SITE.into(),
    };
    let mut tok = vec![PTOK_VERSION];
    tok.extend(wyrm_core::codec::to_vec(&claims).unwrap());
    let sig = key.sign(&tok);
    tok.extend(sig.to_bytes());
    tok
}

fn signer(kind: u8, i: usize) -> SigningKey {
    let mut seed = [0u8; 32];
    seed[0] = kind;
    seed[1..9].copy_from_slice(&(i as u64).to_be_bytes());
    SigningKey::from_bytes(&seed)
}

fn limited(n: usize) -> (Vec<LimitedKey>, Vec<SigningKey>) {
    let signers: Vec<SigningKey> = (0..n).map(|i| signer(2, i)).collect();
    let keys = signers
        .iter()
        .map(|s| LimitedKey {
            key: s.verifying_key(),
            cap: Perm::Write,
            scopes: vec!["wy/bench/downstream".to_owned()],
            subject: None,
        })
        .collect();
    (keys, signers)
}

/// Times `verifier` on the tokens `token(i)` makes; `accepted` = what every one must get.
fn case(name: &str, verifier: &Verifier, accepted: bool, token: impl Fn(usize) -> Vec<u8>) {
    let key = keyexpr::new(KEY).unwrap();
    let toks: Vec<Vec<u8>> = (0..ROUNDS + WARMUP).map(token).collect();
    let (warm, timed) = toks.split_at(WARMUP);
    let now = wyrm_core::clock::now_s();
    let check = |t: &[u8]| match verifier.verify(t, key, None, now) {
        Ok((_, perm)) => {
            assert!(accepted, "{name}: accepted");
            assert_eq!(perm, Perm::Write);
        }
        Err(e) => {
            assert!(!accepted, "{name}: {e:?}");
            assert_eq!(e, Denied::Signature);
        }
    };
    for t in warm {
        check(t);
    }
    let mut lat = Lat::with_capacity(ROUNDS);
    let a0 = Allocs::read();
    let t0 = Instant::now();
    for t in timed {
        let s = Instant::now();
        check(t);
        lat.push(s.elapsed());
    }
    let wall = t0.elapsed().as_secs_f64();
    let allocs = Allocs::read().since(a0);
    println!(
        "{}",
        Perf::new(name)
            .lat(&mut lat)
            .per_s(ROUNDS as f64 / wall)
            .allocs(allocs, ROUNDS as u64)
            .note("ptok verify, one request")
    );
}

fn main() {
    let admin = SigningKey::from_bytes(&[1; 32]);
    // one Ed25519 verify alone, for scale
    {
        let tok = sign(&admin, "user:bench", 1);
        let parts = wyrm_core::ptok::split(&tok).unwrap();
        let sig = ed25519_dalek::Signature::from_bytes(parts.sig);
        let vk = admin.verifying_key();
        let mut lat = Lat::with_capacity(ROUNDS);
        let t0 = Instant::now();
        for _ in 0..ROUNDS {
            let s = Instant::now();
            vk.verify_strict(parts.signed, &sig).unwrap();
            lat.push(s.elapsed());
        }
        let wall = t0.elapsed().as_secs_f64();
        println!(
            "{}",
            Perf::new("verify/ed25519_one")
                .lat(&mut lat)
                .per_s(ROUNDS as f64 / wall)
                .note("one verify_strict")
        );
    }
    let stranger = signer(3, 0);
    for n in [1usize, 4, 10, 30] {
        let (keys, signers) = limited(n);
        let fresh = || Verifier::new(vec![admin.verifying_key()], SITE).with_limited(keys.clone());
        let (first, last) = (&signers[0], &signers[n - 1]);
        let jti = |i: usize| i as u64 + 1;
        case(&format!("verify/admin/l{n}"), &fresh(), true, |i| {
            sign(&admin, "user:bench", jti(i))
        });
        case(&format!("verify/limited_first/l{n}"), &fresh(), true, |i| {
            sign(first, "user:bench", jti(i))
        });
        case(&format!("verify/limited_last/l{n}"), &fresh(), true, |i| {
            sign(last, "user:bench", jti(i))
        });
        case(&format!("verify/refused/l{n}"), &fresh(), false, |i| {
            sign(&stranger, "user:bench", jti(i))
        });
        case(&format!("verify/new_sub_last/l{n}"), &fresh(), true, |i| {
            sign(last, &format!("user:u{i}"), jti(i))
        });
        case(&format!("verify/mixed/l{n}"), &fresh(), true, |i| {
            sign(&signers[i % n], &format!("link:l{}", i % n), jti(i))
        });
        case(&format!("verify/mixed_new_sub/l{n}"), &fresh(), true, |i| {
            sign(&signers[i % n], &format!("user:u{i}"), jti(i))
        });
    }
}
