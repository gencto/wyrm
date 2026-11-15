//! The gateway's one source of randomness (audit S3). A failure is an error
//! the caller refuses with: no key, nonce, token id or code is ever made of
//! zeros or of what the buffer held before.

/// The OS gave no randomness.
#[derive(Debug, Clone, Copy, PartialEq, Eq, thiserror::Error)]
#[error("no randomness from the OS")]
pub struct NoRandomness;

/// Fill `buf` from the OS, or fail.
pub fn fill(buf: &mut [u8]) -> Result<(), NoRandomness> {
    getrandom::fill(buf).map_err(|e| {
        tracing::error!("gateway: no randomness from the OS ({e})");
        NoRandomness
    })
}

/// `N` random bytes, or fail. The buffer starts uninitialized: no byte of the
/// result is a constant the OS did not write.
pub fn bytes<const N: usize>() -> Result<[u8; N], NoRandomness> {
    let mut b = [std::mem::MaybeUninit::<u8>::uninit(); N];
    let filled = getrandom::fill_uninit(&mut b).map_err(|e| {
        tracing::error!("gateway: no randomness from the OS ({e})");
        NoRandomness
    })?;
    match <[u8; N]>::try_from(&*filled) {
        Ok(out) => Ok(out),
        // `fill_uninit` hands back the whole buffer it was given
        Err(_) => Err(NoRandomness),
    }
}
