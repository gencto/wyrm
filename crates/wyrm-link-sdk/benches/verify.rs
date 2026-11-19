//! What one `ptok` check costs a responder (performance audit item 3): the verifier tries
//! the admin keys, then every limited key, with one Ed25519 `verify_strict` each, before it
//! knows who signed. `cargo bench -p wyrm-link-sdk --bench verify`.
//!
//! Per set of limited keys (4, 10, 30; the broker trusts the flow, gateway, scheduler, DQL,
//! agent and requester keys and one per upstream grant, ADR 0013, 0046), two tokens:
//!
//! * `admin`: signed by the admin key, the first key tried (best case, one verify);
//! * `limited_last`: signed by the last limited key, so the admin key and every limited key
//!   are tried (worst case, 1 + n verifies).
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
use wyrm_link_sdk::auth::{LimitedKey, Verifier};
use zenoh::key_expr::keyexpr;

#[global_allocator]
static A: wyrm_bench::Counting = wyrm_bench::Counting;

const SITE: &str = "bench";
const KEY: &str = "wy/bench/downstream/mock/g0/p0/~set";
/// Requests timed per case (after [`WARMUP`]).
const ROUNDS: usize = 4_000;
const WARMUP: usize = 200;

fn sign(key: &SigningKey, jti: u64) -> Vec<u8> {
    let now = wyrm_core::clock::now_s();
    let mut id = [0u8; 16];
    id[..8].copy_from_slice(&jti.to_be_bytes());
    let claims = PtokClaims {
        sub: "user:bench".into(),
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

fn limited(n: usize) -> (Vec<LimitedKey>, Vec<SigningKey>) {
    let signers: Vec<SigningKey> = (0..n)
        .map(|i| {
            let mut seed = [0u8; 32];
            seed[0] = 2;
            seed[1..9].copy_from_slice(&(i as u64).to_be_bytes());
            SigningKey::from_bytes(&seed)
        })
        .collect();
    let keys = signers
        .iter()
        .enumerate()
        .map(|(i, s)| LimitedKey {
            key: s.verifying_key(),
            cap: Perm::Write,
            // only the last one covers the request key
            scopes: vec![if i + 1 == n {
                "wy/bench/downstream".to_owned()
            } else {
                format!("wy/bench/downstream/other{i}")
            }],
            subject: None,
        })
        .collect();
    (keys, signers)
}

fn case(name: &str, verifier: &Verifier, signer: &SigningKey, verifies: usize) {
    let key = keyexpr::new(KEY).unwrap();
    let toks: Vec<Vec<u8>> = (0..ROUNDS + WARMUP)
        .map(|i| sign(signer, i as u64 + 1))
        .collect();
    let (warm, timed) = toks.split_at(WARMUP);
    let now = wyrm_core::clock::now_s();
    for t in warm {
        verifier.verify(t, key, None, now).unwrap();
    }
    let mut lat = Lat::with_capacity(ROUNDS);
    let a0 = Allocs::read();
    let t0 = Instant::now();
    for t in timed {
        let s = Instant::now();
        let (_, perm) = verifier.verify(t, key, None, now).unwrap();
        lat.push(s.elapsed());
        assert_eq!(perm, Perm::Write);
    }
    let wall = t0.elapsed().as_secs_f64();
    let allocs = Allocs::read().since(a0);
    println!(
        "{}",
        Perf::new(name)
            .lat(&mut lat)
            .per_s(ROUNDS as f64 / wall)
            .allocs(allocs, ROUNDS as u64)
            .field("verifies", verifies)
            .note("ptok verify, one request")
    );
}

fn main() {
    let admin = SigningKey::from_bytes(&[1; 32]);
    // one Ed25519 verify alone, for scale
    {
        let tok = sign(&admin, 1);
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
    for n in [4usize, 10, 30] {
        let (keys, signers) = limited(n);
        let fresh = || Verifier::new(vec![admin.verifying_key()], SITE).with_limited(keys.clone());
        case(&format!("verify/admin/l{n}"), &fresh(), &admin, 1);
        let last = signers.last().unwrap();
        case(&format!("verify/limited_last/l{n}"), &fresh(), last, n + 1);
    }
}
