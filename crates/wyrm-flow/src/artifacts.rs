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
use wyrm_wasm_host::{is_sha256_hex, sha256_hex, Host, NodeArtifact, NodeWorld};

pub struct Artifacts {
    dir: PathBuf,
    host: OnceLock<Result<Host, String>>,
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

    fn host(&self) -> Result<&Host, String> {
        self.host
            .get_or_init(|| Host::new().map_err(|e| e.to_string()))
            .as_ref()
            .map_err(|e| format!("wasm host: {e}"))
    }

    fn path(&self, sha: &str) -> PathBuf {
        self.dir.join(format!("{sha}.wasm"))
    }

    fn cache(&self) -> std::sync::MutexGuard<'_, HashMap<String, NodeArtifact>> {
        self.loaded.lock().unwrap_or_else(|p| p.into_inner())
    }

    /// Check and store a component; returns its hex SHA-256.
    pub fn put(&self, bytes: &[u8]) -> Result<String, String> {
        let art = self
            .host()?
            .load::<NodeWorld>(bytes)
            .map_err(|e| e.to_string())?;
        let sha = art.sha256().to_owned();
        let path = self.path(&sha);
        if !path.exists() {
            write_atomic(&self.dir, &path, bytes).map_err(|e| format!("store: {e}"))?;
        }
        self.cache().insert(sha.clone(), art);
        Ok(sha)
    }

    /// A stored component, compiled and checked.
    pub fn get(&self, sha: &str) -> Result<NodeArtifact, String> {
        if !is_sha256_hex(sha) {
            return Err("artifact: expected 64 lowercase hex characters".into());
        }
        if let Some(a) = self.cache().get(sha) {
            return Ok(a.clone());
        }
        let bytes =
            std::fs::read(self.path(sha)).map_err(|_| format!("artifact: no artifact {sha}"))?;
        if sha256_hex(&bytes) != sha {
            return Err(format!("artifact: {sha}: content does not match its hash"));
        }
        let art = self
            .host()?
            .load::<NodeWorld>(&bytes)
            .map_err(|e| format!("artifact: {sha}: {e}"))?;
        self.cache().insert(sha.to_owned(), art.clone());
        Ok(art)
    }
}

fn write_atomic(dir: &Path, path: &Path, bytes: &[u8]) -> std::io::Result<()> {
    use std::io::Write;
    std::fs::create_dir_all(dir)?;
    let mut rnd = [0u8; 8];
    getrandom::fill(&mut rnd).map_err(|e| std::io::Error::other(e.to_string()))?;
    let tmp = dir.join(format!(
        ".tmp-{}",
        rnd.iter().map(|b| format!("{b:02x}")).collect::<String>()
    ));
    let mut f = std::fs::File::create(&tmp)?;
    f.write_all(bytes)?;
    f.sync_all()?;
    drop(f);
    std::fs::rename(&tmp, path).inspect_err(|_| {
        let _ = std::fs::remove_file(&tmp);
    })
}
