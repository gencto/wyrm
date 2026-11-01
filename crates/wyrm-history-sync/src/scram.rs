//! SCRAM-SHA-256 (RFC 5802, RFC 7677), shared by the targets that log in with it (PostgreSQL,
//! MongoDB): no channel binding (`n,,`).

use base64::engine::general_purpose::STANDARD as B64;
use base64::Engine as _;
use hmac::{Hmac, Mac};
use sha2::{Digest, Sha256};

type HmacSha256 = Hmac<Sha256>;

fn hmac(key: &[u8], data: &[u8]) -> [u8; 32] {
    // HMAC takes a key of any length
    let mut m = HmacSha256::new_from_slice(key).unwrap_or_else(|_| unreachable!());
    m.update(data);
    m.finalize().into_bytes().into()
}

/// `Hi()` of RFC 5802: PBKDF2-HMAC-SHA-256, one block.
fn hi(password: &[u8], salt: &[u8], iterations: u32) -> [u8; 32] {
    let mut s = salt.to_vec();
    s.extend_from_slice(&1u32.to_be_bytes());
    let mut u = hmac(password, &s);
    let mut out = u;
    for _ in 1..iterations {
        u = hmac(password, &u);
        for (o, x) in out.iter_mut().zip(u) {
            *o ^= x;
        }
    }
    out
}

/// The client's first message (`n,,` + bare) and its bare part.
pub fn client_first(user: &str, nonce: &str) -> (String, String) {
    let bare = format!(
        "n={},r={nonce}",
        user.replace('=', "=3D").replace(',', "=2C")
    );
    (format!("n,,{bare}"), bare)
}

/// Upper bound on the server's iteration count: a hostile server cannot make the link spin.
pub const MAX_ITERATIONS: u32 = 600_000;

/// The client's final message for `server_first`, and the server signature the server's final
/// message must carry.
pub fn client_final(
    password: &str,
    nonce: &str,
    client_first_bare: &str,
    server_first: &str,
) -> Result<(String, String), String> {
    let (mut r, mut s, mut i) = (None, None, None);
    for part in server_first.split(',') {
        match part.split_once('=') {
            Some(("r", v)) => r = Some(v),
            Some(("s", v)) => s = Some(v),
            Some(("i", v)) => i = v.parse::<u32>().ok(),
            Some(("m", _)) => return Err("scram: mandatory extension".into()),
            _ => {}
        }
    }
    let (Some(r), Some(s), Some(i)) = (r, s, i) else {
        return Err("scram: bad server-first message".into());
    };
    if !r.starts_with(nonce) || r.len() == nonce.len() {
        return Err("scram: the server nonce does not extend ours".into());
    }
    if !(1..=MAX_ITERATIONS).contains(&i) {
        return Err(format!("scram: iteration count {i}"));
    }
    let salt = B64.decode(s).map_err(|_| "scram: bad salt")?;
    let salted = hi(password.as_bytes(), &salt, i);
    let client_key = hmac(&salted, b"Client Key");
    let stored_key: [u8; 32] = Sha256::digest(client_key).into();
    let without_proof = format!("c=biws,r={r}");
    let auth = format!("{client_first_bare},{server_first},{without_proof}");
    let signature = hmac(&stored_key, auth.as_bytes());
    let proof: Vec<u8> = client_key
        .iter()
        .zip(signature)
        .map(|(a, b)| a ^ b)
        .collect();
    let server_key = hmac(&salted, b"Server Key");
    let server_signature = B64.encode(hmac(&server_key, auth.as_bytes()));
    Ok((
        format!("{without_proof},p={}", B64.encode(proof)),
        server_signature,
    ))
}

/// Check the server's final message against the signature [`client_final`] expects.
pub fn check_server_final(server_final: &str, expected: &str) -> Result<(), String> {
    if let Some(e) = server_final.strip_prefix("e=") {
        return Err(format!("scram: the server refused: {e}"));
    }
    match server_final.split(',').find_map(|p| p.strip_prefix("v=")) {
        Some(v) if same(v.as_bytes(), expected.as_bytes()) => Ok(()),
        _ => Err("scram: the server's signature does not match (not the server we think)".into()),
    }
}

/// Equal in time that does not depend on where they differ (the length is not secret).
fn same(a: &[u8], b: &[u8]) -> bool {
    a.len() == b.len() && a.iter().zip(b).fold(0u8, |d, (x, y)| d | (x ^ y)) == 0
}

/// A client nonce: 18 bytes from the host's random source (`Host::random_bytes`, ADR 0030: the
/// native and process hosts and a WASM component of `wyrm:app@0.3.0`), as base64 (no `,`, so it
/// fits a SCRAM attribute). A host without one (an older world, a test host) gets
/// [`nonce_from_clock`].
pub fn nonce(host: &mut dyn wyrm_link_api::Host, conn: u32) -> String {
    match host.random_bytes(18) {
        Ok(b) if b.len() == 18 => B64.encode(b),
        _ => nonce_from_clock(host.now_us(), conn),
    }
}

/// The fallback nonce: 18 bytes hashed from the clock, a counter and the connection, never from
/// the secret (the nonce goes to the server: anything derived from the password would let it, or
/// whoever sees the exchange, test guesses offline). It is unique, not unpredictable; it is used
/// only when the host offers no random source (a component of `wyrm:app@0.2.0` or older), and
/// TLS carries the exchange.
pub fn nonce_from_clock(now_us: u64, conn: u32) -> String {
    use std::sync::atomic::{AtomicU64, Ordering};
    static COUNT: AtomicU64 = AtomicU64::new(0);
    let n = COUNT.fetch_add(1, Ordering::Relaxed);
    let mut h = Sha256::new();
    h.update(b"wyrm-scram-nonce");
    h.update(now_us.to_le_bytes());
    h.update(n.to_le_bytes());
    h.update(conn.to_le_bytes());
    B64.encode(&h.finalize()[..18])
}

#[cfg(test)]
mod tests {
    use super::*;

    /// RFC 7677, section 3.
    #[test]
    fn rfc7677_vector() {
        let nonce = "rOprNGfwEbeRWgbNEkqO";
        let (first, bare) = client_first("user", nonce);
        assert_eq!(first, "n,,n=user,r=rOprNGfwEbeRWgbNEkqO");
        let server_first =
            "r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,s=W22ZaJ0SNY7soEsUEjb6gQ==,i=4096";
        let (fin, sig) = client_final("pencil", nonce, &bare, server_first).unwrap();
        assert_eq!(
            fin,
            "c=biws,r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,\
             p=dHzbZapWIk4jUhN+Ute9ytag9zjfMHgsqmmiz7AndVQ="
        );
        check_server_final("v=6rriTRBi23WpRR/wtup+mMhUZUn/dB5nLTJRsjl95G4=", &sig).unwrap();
        assert!(check_server_final("v=AAAA", &sig).is_err());
        assert!(check_server_final("e=invalid-proof", &sig).is_err());
    }

    #[test]
    fn hostile_server_first() {
        let bad = |sf: &str| client_final("pw", "abc", "n=,r=abc", sf).unwrap_err();
        assert!(bad("r=xyz,s=AAAA,i=4096").contains("nonce"));
        assert!(
            bad("r=abc,s=AAAA,i=4096").contains("nonce"),
            "must extend ours"
        );
        assert!(bad("r=abcd,s=AAAA,i=99999999").contains("iteration"));
        assert!(bad("r=abcd,s=!!,i=4096").contains("salt"));
        assert!(bad("m=x,r=abcd,s=AAAA,i=1").contains("extension"));
        assert_ne!(nonce_from_clock(1, 1), nonce_from_clock(1, 1), "unique");
    }

    /// The nonce comes from the host's random source when it has one, else from the clock.
    #[test]
    fn nonce_takes_the_hosts_random_bytes() {
        use crate::testkit::TcpHost;
        let mut h = TcpHost::default();
        let a = nonce(&mut h, 1);
        assert_eq!(B64.decode(&a).unwrap().len(), 18);
        assert_ne!(a, nonce(&mut h, 1), "unique without a random source");
        h.random = Some(0xab);
        assert_eq!(nonce(&mut h, 1), B64.encode([0xab; 18]));
    }
}
