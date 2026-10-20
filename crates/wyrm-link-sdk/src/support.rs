//! Secrets and metrics handed to the driver through `LinkCtx`.

use std::collections::HashMap;
use std::fmt;
use std::sync::atomic::{AtomicU64, Ordering};
use zeroize::Zeroizing;

/// A secret value. Zeroed on drop; `Debug` prints `***`.
#[derive(Clone)]
pub struct Secret(Zeroizing<Vec<u8>>);

impl Secret {
    pub fn new(bytes: impl Into<Vec<u8>>) -> Self {
        Self(Zeroizing::new(bytes.into()))
    }

    pub fn expose(&self) -> &[u8] {
        &self.0
    }

    pub fn expose_str(&self) -> Option<&str> {
        std::str::from_utf8(&self.0).ok()
    }
}

impl fmt::Debug for Secret {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("***")
    }
}

/// Secrets of one link (device passwords, keys). Never from `~def`, never in
/// the tree. Filled by the host at start.
#[derive(Debug, Clone, Default)]
pub struct SecretStore {
    items: HashMap<String, Secret>,
}

impl SecretStore {
    pub fn get(&self, name: &str) -> Option<&Secret> {
        self.items.get(name)
    }

    pub fn insert(&mut self, name: impl Into<String>, secret: Secret) {
        self.items.insert(name.into(), secret);
    }
}

impl<K: Into<String>> FromIterator<(K, Secret)> for SecretStore {
    fn from_iter<I: IntoIterator<Item = (K, Secret)>>(iter: I) -> Self {
        Self {
            items: iter.into_iter().map(|(k, v)| (k.into(), v)).collect(),
        }
    }
}

/// Link counters. Exported to `sys/metrics/link/<link>/**` by the host (later).
#[derive(Debug, Default)]
pub struct Metrics {
    pub samples_out: AtomicU64,
    pub sets_in: AtomicU64,
    pub invokes_in: AtomicU64,
    pub denied: AtomicU64,
    pub errors: AtomicU64,
}

impl Metrics {
    pub(crate) fn inc(c: &AtomicU64) {
        c.fetch_add(1, Ordering::Relaxed);
    }

    pub fn get(c: &AtomicU64) -> u64 {
        c.load(Ordering::Relaxed)
    }
}
