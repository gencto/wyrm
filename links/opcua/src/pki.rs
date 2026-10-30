//! The link's OPC UA PKI on disk (`<data_dir>/opcua-pki`). async-opcua
//! reads the application instance certificate and key from files on every
//! connect, and keeps trusted/rejected server certificates in directories.
//!
//! ```text
//! own/app-<uri hash>.der        generated application certificate
//! private/app-<uri hash>.pem    its key (0600)
//! own/user-<pem hash>.der       a certificate given as `cert_pem`
//! private/user-<pem hash>.pem   its key (`key_pem`, 0600)
//! servers/<url hash>-<trust>/   trusted/ and rejected/ for one endpoint
//! ```
//!
//! `<trust>` is `pin-<hash>` (only the pinned certificate is trusted),
//! `tofu` (the first certificate seen is trusted, then only it) or `strict`
//! (nothing is trusted: a secured connection fails until a pin is given).

use opcua::crypto::{CertificateStore, PrivateKey, X509Data, X509};
use sha2::{Digest, Sha256};
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::Mutex;

/// One certificate generation at a time per process (two connections of
/// one link must not write two different certificates).
static GENERATE: Mutex<()> = Mutex::new(());

/// RSA key size of a generated application certificate.
const KEY_BITS: u32 = 2048;
/// Validity of a generated application certificate.
const DAYS: u32 = 3650;

/// What a connection opens with.
#[derive(Debug, Clone)]
pub struct Prepared {
    /// The certificate store's directory (trusted/, rejected/).
    pub store: PathBuf,
    /// The application instance certificate and key (absolute paths).
    pub cert: PathBuf,
    pub key: PathBuf,
    /// SHA-1 thumbprint of the application certificate (hex), as server
    /// trust lists show it.
    pub thumbprint: String,
    /// Trust the server's certificate when it is unknown (first use).
    pub trust_unknown: bool,
}

/// Trust of the server's certificate.
pub enum Trust<'a> {
    Pin(&'a str),
    FirstUse,
    Strict,
}

/// What to prepare for one connection.
pub struct Request<'a> {
    pub url: &'a str,
    pub application_uri: &'a str,
    /// `cert_pem` + `key_pem` (both or neither).
    pub own: Option<(&'a str, &'a str)>,
    pub trust: Trust<'a>,
}

fn hash16(parts: &[&str]) -> String {
    let mut h = Sha256::new();
    for p in parts {
        h.update(p.as_bytes());
        h.update([0u8]);
    }
    hex::encode(&h.finalize()[..8])
}

/// Prepare the files of one connection under `root`. Blocking (file I/O,
/// RSA key generation on first use): run it off the async workers.
pub fn prepare(root: &Path, r: &Request<'_>) -> Result<Prepared, String> {
    let io = |what: &str, e: std::io::Error| format!("{what}: {e}");
    fs::create_dir_all(root).map_err(|e| io("pki directory", e))?;
    let (cert, key) = match r.own {
        Some((cert_pem, key_pem)) => own_from_pem(root, cert_pem, key_pem)?,
        None => generated(root, r.application_uri)?,
    };
    let x509 = CertificateStore::read_cert(&cert)?;
    let thumbprint = x509.thumbprint().as_hex_string();

    let trust = match r.trust {
        Trust::Pin(pem) => format!("pin-{}", hash16(&[pem])),
        Trust::FirstUse => "tofu".to_owned(),
        Trust::Strict => "strict".to_owned(),
    };
    let store = root
        .join("servers")
        .join(format!("{}-{trust}", hash16(&[r.url])));
    let trusted = store.join("trusted");
    let rejected = store.join("rejected");
    fs::create_dir_all(&trusted).map_err(|e| io("trusted directory", e))?;
    fs::create_dir_all(&rejected).map_err(|e| io("rejected directory", e))?;
    let trust_unknown = match r.trust {
        Trust::Pin(pem) => {
            let pin = X509::from_pem(pem.as_bytes())
                .map_err(|_| "server_cert_pem: not a PEM certificate".to_owned())?;
            let name = CertificateStore::cert_file_name(&pin);
            // Only the pin is trusted; the rejected list is checked first,
            // so the pin leaves it.
            clear_dir(&trusted)?;
            let _ = fs::remove_file(rejected.join(&name));
            let der = pin.to_der().map_err(|e| format!("server_cert_pem: {e}"))?;
            write_file(&trusted.join(&name), &der, false)?;
            false
        }
        Trust::FirstUse => dir_is_empty(&trusted)?,
        Trust::Strict => false,
    };
    Ok(Prepared {
        store,
        cert,
        key,
        thumbprint,
        trust_unknown,
    })
}

/// The store of a connection without security and without a `data_dir`: no
/// key or certificate is written, only the empty trust directories the
/// library wants.
pub fn plain_store() -> Result<PathBuf, String> {
    let dir = std::env::temp_dir().join("wyrm-opcua-none");
    for sub in ["trusted", "rejected"] {
        fs::create_dir_all(dir.join(sub)).map_err(|e| format!("pki directory: {e}"))?;
    }
    Ok(dir)
}

/// The most recently written certificate in `<store>/rejected` since
/// `since`: the server's certificate this client just refused.
pub fn rejected_since(store: &Path, since: std::time::SystemTime) -> Option<String> {
    let entries = fs::read_dir(store.join("rejected")).ok()?;
    let mut newest: Option<(std::time::SystemTime, PathBuf)> = None;
    for e in entries.flatten() {
        let Ok(t) = e.metadata().and_then(|m| m.modified()) else {
            continue;
        };
        if t >= since && newest.as_ref().is_none_or(|(n, _)| t > *n) {
            newest = Some((t, e.path()));
        }
    }
    let (_, path) = newest?;
    CertificateStore::read_cert(&path)
        .ok()
        .map(|c| c.thumbprint().as_hex_string())
}

fn clear_dir(dir: &Path) -> Result<(), String> {
    for e in fs::read_dir(dir).map_err(|e| format!("{}: {e}", dir.display()))? {
        let e = e.map_err(|e| format!("{}: {e}", dir.display()))?;
        let _ = fs::remove_file(e.path());
    }
    Ok(())
}

fn dir_is_empty(dir: &Path) -> Result<bool, String> {
    Ok(fs::read_dir(dir)
        .map_err(|e| format!("{}: {e}", dir.display()))?
        .next()
        .is_none())
}

/// Write `bytes` to `path` through a temporary file and a rename; a key is
/// readable by the owner only.
fn write_file(path: &Path, bytes: &[u8], private: bool) -> Result<(), String> {
    let err = |e: std::io::Error| format!("{}: {e}", path.display());
    if let Some(dir) = path.parent() {
        fs::create_dir_all(dir).map_err(err)?;
    }
    let tmp = path.with_extension("tmp");
    let mut opts = fs::OpenOptions::new();
    opts.write(true).create(true).truncate(true);
    #[cfg(unix)]
    if private {
        use std::os::unix::fs::OpenOptionsExt;
        opts.mode(0o600);
    }
    #[cfg(not(unix))]
    let _ = private;
    let mut f = opts.open(&tmp).map_err(err)?;
    f.write_all(bytes).map_err(err)?;
    f.sync_all().map_err(err)?;
    drop(f);
    fs::rename(&tmp, path).map_err(err)
}

/// `cert_pem`/`key_pem` as the files the library reads. The key's content
/// never enters an error.
fn own_from_pem(root: &Path, cert_pem: &str, key_pem: &str) -> Result<(PathBuf, PathBuf), String> {
    let cert = X509::from_pem(cert_pem.as_bytes())
        .map_err(|_| "cert_pem: not a PEM certificate".to_owned())?;
    PrivateKey::from_pem(key_pem.as_bytes())
        .map_err(|_| "key_pem: not a PEM RSA private key".to_owned())?;
    let h = hash16(&[cert_pem]);
    let cert_path = root.join("own").join(format!("user-{h}.der"));
    let key_path = root.join("private").join(format!("user-{h}.pem"));
    let der = cert.to_der().map_err(|e| format!("cert_pem: {e}"))?;
    write_file(&cert_path, &der, false)?;
    write_file(&key_path, key_pem.as_bytes(), true)?;
    Ok((cert_path, key_path))
}

/// The generated application certificate of `application_uri`, made on
/// first use (self-signed, RSA 2048, 10 years).
fn generated(root: &Path, application_uri: &str) -> Result<(PathBuf, PathBuf), String> {
    let h = hash16(&[application_uri]);
    let cert = root.join("own").join(format!("app-{h}.der"));
    let key = root.join("private").join(format!("app-{h}.pem"));
    let _one = GENERATE.lock().unwrap_or_else(|p| p.into_inner());
    if cert.is_file() && key.is_file() {
        return Ok((cert, key));
    }
    // The application URI first, then this host's names (no DNS lookups).
    let alt = X509Data::alt_host_names(
        application_uri,
        Some(X509Data::computer_hostnames()),
        false,
        false,
        false,
    );
    let data = X509Data {
        key_size: KEY_BITS,
        common_name: "WYRM OPC UA Client".to_owned(),
        organization: "WYRM".to_owned(),
        organizational_unit: String::new(),
        country: String::new(),
        state: String::new(),
        alt_host_names: alt,
        certificate_duration_days: DAYS,
    };
    let tmp_cert = cert.with_extension("new");
    let tmp_key = key.with_extension("new");
    CertificateStore::create_certificate_and_key(&data, true, &tmp_cert, &tmp_key)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(&tmp_key, fs::Permissions::from_mode(0o600))
            .map_err(|e| format!("{}: {e}", tmp_key.display()))?;
    }
    fs::rename(&tmp_key, &key).map_err(|e| format!("{}: {e}", key.display()))?;
    fs::rename(&tmp_cert, &cert).map_err(|e| format!("{}: {e}", cert.display()))?;
    let thumb = CertificateStore::read_cert(&cert)
        .map(|c| c.thumbprint().as_hex_string())
        .unwrap_or_default();
    tracing::info!(
        path = %cert.display(),
        thumbprint = %thumb,
        "generated the OPC UA application certificate; trust it on the server"
    );
    Ok((cert, key))
}
