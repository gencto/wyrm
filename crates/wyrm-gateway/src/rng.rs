//! The gateway's one source of randomness (audit S3). A failure is an error
//! the caller refuses with: no key, nonce, token id or code is ever made of
//! zeros or of what the buffer held before.

/// The OS gave no randomness.
#[derive(Debug, Clone, Copy, PartialEq, Eq, thiserror::Error)]
#[error("no randomness from the OS")]
pub struct NoRandomness;

/// Fill `buf` from the OS (`wyrm_core::rand`, the workspace's one source), or fail.
pub fn fill(buf: &mut [u8]) -> Result<(), NoRandomness> {
    wyrm_core::rand::fill(buf).map_err(|e| {
        tracing::error!("gateway: {e}");
        NoRandomness
    })
}

/// `N` random bytes (`wyrm_core::rand::bytes`: no byte is a constant the OS did not
/// write), or fail.
pub fn bytes<const N: usize>() -> Result<[u8; N], NoRandomness> {
    wyrm_core::rand::bytes().map_err(|e| {
        tracing::error!("gateway: {e}");
        NoRandomness
    })
}
