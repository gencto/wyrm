//! Content-addressed store of WASM flow-node components (iteration 8):
//! `<flow dir>/artifacts/<sha256>.wasm`, written atomically (temp file and
//! rename), re-hashed on every read. A `~def` names a component by its
//! hash (`{type: "wasm", artifact: "<sha256>"}`), so a new version is a new
//! artifact and a new definition: hot load = `put_artifact` + `deploy`.
//!
//! Only components of world `wyrm:flow/node` without imports are stored
//! (`wyrm-wasm-host` checks both). The `wasmtime` host starts on first use.

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::{Mutex, OnceLock};
use wyrm_core::hex::{is_lower_hex, sha256_hex};
use wyrm_wasm_host::{Host, NodeArtifact, NodeWorld};

/// Why a component was not stored or not loaded. The texts are the ones
/// these errors had as a `String`: they reach the refusals of `put_artifact`
/// (`bytes: …`) and of a deploy (`nodes.<id>.…`).
#[derive(Debug, thiserror::Error)]
pub enum ArtifactError {
    /// The `wasmtime` host did not start.
    #[error("wasm host: {0}")]
    Host(#[source] wyrm_wasm_host::Error),
    /// `put`: the bytes are not a component the store takes.
    #[error("{0}")]
    Component(#[source] wyrm_wasm_host::Error),
    /// `put`: the file was not written.
    #[error("store: {0}")]
    Write(#[source] std::io::Error),
    /// `get`: the name is not a SHA-256 in lowercase hex.
    #[error("artifact: expected 64 lowercase hex characters")]
    Name,
    /// `get`: no file of this name could be read.
    #[error("artifact: no artifact {sha}")]
    NotFound {
        sha: String,
        #[source]
        source: std::io::Error,
    },
    /// `get`: the file's bytes are not the ones its name stands for.
    #[error("artifact: {sha}: content does not match its hash")]
    Changed { sha: String },
    /// `get`: the stored bytes no longer load as a component.
    #[error("artifact: {sha}: {source}")]
    Load {
        sha: String,
        #[source]
        source: wyrm_wasm_host::Error,
    },
}

pub struct Artifacts {
    dir: PathBuf,
    host: OnceLock<Result<Host, wyrm_wasm_host::Error>>,
    loaded: Mutex<HashMap<String, NodeArtifact>>,
}

impl Artifacts {
    pub fn new(dir: impl Into<PathBuf>) -> Self {
        Self {
            dir: dir.into(),
            host: OnceLock::new(),
            loaded: Mutex::new(HashMap::new()),
        }
    }

    fn host(&self) -> Result<&Host, ArtifactError> {
        self.host
            .get_or_init(Host::new)
            .as_ref()
            .map_err(|e| ArtifactError::Host(e.clone()))
    }

    fn path(&self, sha: &str) -> PathBuf {
        self.dir.join(format!("{sha}.wasm"))
    }

    fn cache(&self) -> std::sync::MutexGuard<'_, HashMap<String, NodeArtifact>> {
        self.loaded.lock().unwrap_or_else(|p| p.into_inner())
    }

    /// Check and store a component; returns its hex SHA-256.
    pub fn put(&self, bytes: &[u8]) -> Result<String, ArtifactError> {
        let art = self
            .host()?
            .load::<NodeWorld>(bytes)
            .map_err(ArtifactError::Component)?;
        let sha = art.sha256().to_owned();
        let path = self.path(&sha);
        if !path.exists() {
            write_atomic(&self.dir, &path, bytes).map_err(ArtifactError::Write)?;
        }
        self.cache().insert(sha.clone(), art);
        Ok(sha)
    }

    /// A stored component, compiled and checked.
    pub fn get(&self, sha: &str) -> Result<NodeArtifact, ArtifactError> {
        if !is_lower_hex(sha, 32) {
            return Err(ArtifactError::Name);
        }
        if let Some(a) = self.cache().get(sha) {
            return Ok(a.clone());
        }
        let bytes = std::fs::read(self.path(sha)).map_err(|source| ArtifactError::NotFound {
            sha: sha.to_owned(),
            source,
        })?;
        if sha256_hex(&bytes) != sha {
            return Err(ArtifactError::Changed {
                sha: sha.to_owned(),
            });
        }
        let art = self
            .host()?
            .load::<NodeWorld>(&bytes)
            .map_err(|source| ArtifactError::Load {
                sha: sha.to_owned(),
                source,
            })?;
        self.cache().insert(sha.to_owned(), art.clone());
        Ok(art)
    }
}

fn write_atomic(dir: &Path, path: &Path, bytes: &[u8]) -> std::io::Result<()> {
    use std::io::Write;
    std::fs::create_dir_all(dir)?;
    let mut rnd = [0u8; 8];
    wyrm_core::rand::fill(&mut rnd).map_err(|e| std::io::Error::other(e.to_string()))?;
    let tmp = dir.join(format!(".tmp-{}", wyrm_core::hex::encode(rnd)));
    let mut f = std::fs::File::create(&tmp)?;
    f.write_all(bytes)?;
    f.sync_all()?;
    drop(f);
    std::fs::rename(&tmp, path).inspect_err(|_| wyrm_core::files::discard(&tmp))
}
