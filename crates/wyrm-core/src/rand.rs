//! The one source of randomness of the workspace (review S3, docs/rust-rules.md §10).
//!
//! Every key, nonce, salt, token id and random name comes from [`fill`] or [`bytes`];
//! a ring API that takes a `SecureRandom` (an RSA or ECDSA signature) gets
//! [`secure_random`]. A failure is an error the caller refuses with: nothing is ever
//! made of zeros, of what the buffer held before, or of a panic. `clippy.toml` bans
//! the direct calls (`getrandom::fill`, `fill_uninit`, `u32`, `u64`,
//! `ring::rand::SystemRandom::new`, `rand_core::OsRng`) everywhere else.
//!
//! Behind the feature `rand` (`ring` adds [`secure_random`]): `wyrm-core` builds for
//! wasm32, where a portable link takes randomness from its host
//! (`Host::random_bytes`), never from here. Each of the three functions carries its
//! own `allow` of the ban, the only ones in the workspace.

/// The OS gave no randomness.
#[derive(Debug, Clone, Copy, PartialEq, Eq, thiserror::Error)]
#[error("no randomness from the OS: {0}")]
pub struct NoRandomness(getrandom::Error);

impl From<getrandom::Error> for NoRandomness {
    fn from(e: getrandom::Error) -> Self {
        Self(e)
    }
}

/// Fill `buf` from the OS, or fail.
#[allow(
    clippy::disallowed_methods,
    reason = "the workspace's one call of getrandom::fill; clippy.toml bans it everywhere else"
)]
pub fn fill(buf: &mut [u8]) -> Result<(), NoRandomness> {
    Ok(getrandom::fill(buf)?)
}

/// `N` random bytes, or fail. The buffer starts uninitialized: no byte of the result
/// is a constant the OS did not write.
#[allow(
    clippy::disallowed_methods,
    reason = "the workspace's one call of getrandom::fill_uninit; clippy.toml bans it everywhere else"
)]
pub fn bytes<const N: usize>() -> Result<[u8; N], NoRandomness> {
    let mut b = [std::mem::MaybeUninit::<u8>::uninit(); N];
    let filled = getrandom::fill_uninit(&mut b)?;
    match <[u8; N]>::try_from(&*filled) {
        Ok(out) => Ok(out),
        // `fill_uninit` hands back the whole buffer it was given
        Err(_) => Err(NoRandomness(getrandom::Error::UNEXPECTED)),
    }
}

/// The OS source as ring's `SecureRandom`, for the ring calls that take one (an
/// RSA PKCS#1 or ECDSA signature, a key pair made by ring). Its own failure is a
/// ring error the caller refuses with.
#[cfg(feature = "ring")]
#[allow(
    clippy::disallowed_methods,
    reason = "the workspace's one SystemRandom; clippy.toml bans SystemRandom::new everywhere else"
)]
pub fn secure_random() -> ring::rand::SystemRandom {
    ring::rand::SystemRandom::new()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fills_and_bytes_are_random() {
        let mut a = [0u8; 32];
        fill(&mut a).unwrap();
        let b: [u8; 32] = bytes().unwrap();
        assert_ne!(a, [0; 32]);
        assert_ne!(a, b);
        assert_eq!(bytes::<0>().unwrap(), [0u8; 0]);
    }
}
