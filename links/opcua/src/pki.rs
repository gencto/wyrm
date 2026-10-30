//! The link's OPC UA PKI on disk (`<data_dir>/opcua-pki`). async-opcua
//! reads the application instance certificate and key from files on every
//! connect, and keeps trusted/rejected server certificates in directories.
//!
//! ```text
//! own/app-<uri hash>.der        generated application certificate
//! private/app-<uri hash>.pem    its key (0600)
//! own/user-<pem hash>.der       a certificate given as `cert_pem`
//! private/user-<pem hash>.pem   its key (`key_pem`, 0600, plain text)
//! servers/<url hash>-<trust>/   trusted/ and rejected/ for one endpoint
//! ```
//!
//! `<trust>` is `pin-<hash>` (only the pinned certificate is trusted),
//! `tofu` (the first certificate seen is trusted, then only it) or `strict`
//! (nothing is trusted: a secured connection fails until a pin is given).
//! `<url hash>` is of the endpoint as [`crate::session::endpoint_key`]
//! normalises it.
//!
//! The `user-*` files exist only while a connection that names them opens
//! or has a session ([`KeyLease`]); the library reads the key from its file
//! on every secure channel open and renewal, so it cannot stay in memory
//! only. [`sweep`] removes the ones a stopped process left.
//!
//! First use counts only once a session was activated: then the store gets
//! the marker file `tofu-ok`. Until it has it, `prepare` empties `trusted/`
//! (the library stores an unknown certificate there before it checks host
//! name, validity and application URI, and an open can also be cut by its
//! timeout), so a refused first answer never pins the store.

use opcua::crypto::{CertificateStore, PrivateKey, X509Data, X509};
use sha2::{Digest, Sha256};
use std::collections::BTreeMap;
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

/// Supplied key files in use, by key path: how many connections open
/// with them or have a session.
static IN_USE: Mutex<BTreeMap<PathBuf, usize>> = Mutex::new(BTreeMap::new());

/// One connection's use of the `user-*` files of a supplied `cert_pem` /
/// `key_pem`. The files are removed when the last use ends (a session
/// closed, an open failed or cut, an edit that changes the certificate, a
/// removed connection).
#[derive(Debug)]
pub struct KeyLease {
    cert: PathBuf,
    key: PathBuf,
}

impl Drop for KeyLease {
    fn drop(&mut self) {
        let mut used = IN_USE.lock().unwrap_or_else(|p| p.into_inner());
        let n = used.get(&self.key).copied().unwrap_or(1);
        if n > 1 {
            used.insert(self.key.clone(), n - 1);
        } else {
            used.remove(&self.key);
            let _ = fs::remove_file(&self.key);
            let _ = fs::remove_file(&self.cert);
        }
    }
}

/// Remove the `user-*` files under `root` that no connection uses (left by
/// a process that stopped). Run at link start.
pub fn sweep(root: &Path) {
    let used = IN_USE.lock().unwrap_or_else(|p| p.into_inner());
    for dir in ["own", "private"] {
        let Ok(entries) = fs::read_dir(root.join(dir)) else {
            continue;
        };
        for e in entries.flatten() {
            let path = e.path();
            let user = e
                .file_name()
                .to_str()
                .is_some_and(|n| n.starts_with("user-"));
            let key = path.with_extension("pem");
            let key = root
                .join("private")
                .join(key.file_name().unwrap_or_default());
            if user && !used.contains_key(&key) {
                let _ = fs::remove_file(&path);
            }
        }
    }
}

/// What a connection opens with.
#[derive(Debug)]
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
    /// The use of a supplied certificate's files (none for a generated one).
    pub lease: Option<KeyLease>,
}

/// The marker of a trust-on-first-use store whose first use made a session.
const TOFU_OK: &str = "tofu-ok";

impl Prepared {
    /// `cert` (a server certificate) is in this store's `trusted/` and not
    /// in its `rejected/` (the library checks `rejected/` first).
    pub fn trusts(&self, cert: &X509) -> bool {
        let name = CertificateStore::cert_file_name(cert);
        self.store.join("trusted").join(&name).is_file()
            && !self.store.join("rejected").join(&name).is_file()
    }

    /// A session was activated: a first-use store keeps what it trusts.
    pub fn opened(&self) {
        if self.trust_unknown {
            let _ = write_file(&self.store.join(TOFU_OK), b"", false);
        }
    }
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
    let (cert, key, lease) = match r.own {
        Some((cert_pem, key_pem)) => {
            let lease = own_from_pem(root, cert_pem, key_pem)?;
            (lease.cert.clone(), lease.key.clone(), Some(lease))
        }
        None => {
            let (cert, key) = generated(root, r.application_uri)?;
            (cert, key, None)
        }
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
        Trust::FirstUse => {
            let marker = store.join(TOFU_OK);
            if !marker.is_file() {
                // No session yet: what an earlier attempt stored is not
                // trusted (see the module doc).
                clear_dir(&trusted)?;
            }
            let empty = dir_is_empty(&trusted)?;
            if empty {
                let _ = fs::remove_file(&marker);
            }
            empty
        }
        Trust::Strict => false,
    };
    Ok(Prepared {
        store,
        cert,
        key,
        thumbprint,
        trust_unknown,
        lease,
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
        if private {
            private_dir(dir)?;
        } else {
            fs::create_dir_all(dir).map_err(err)?;
        }
    }
    // A new file each time: the mode applies only when the file is created.
    let tmp = path.with_extension("tmp");
    let _ = fs::remove_file(&tmp);
    let mut opts = fs::OpenOptions::new();
    opts.write(true).create_new(true);
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

/// The directory of keys: created with mode 0700 (and set to it when it
/// exists), before any key goes in.
fn private_dir(dir: &Path) -> Result<(), String> {
    let err = |e: std::io::Error| format!("{}: {e}", dir.display());
    #[cfg(unix)]
    {
        use std::os::unix::fs::{DirBuilderExt, PermissionsExt};
        fs::DirBuilder::new()
            .recursive(true)
            .mode(0o700)
            .create(dir)
            .map_err(err)?;
        fs::set_permissions(dir, fs::Permissions::from_mode(0o700)).map_err(err)?;
    }
    #[cfg(not(unix))]
    fs::create_dir_all(dir).map_err(err)?;
    Ok(())
}

/// PEM text of DER bytes.
pub fn pem(label: &str, der: &[u8]) -> String {
    const B64: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut b64 = String::with_capacity(der.len() * 4 / 3 + 4);
    for chunk in der.chunks(3) {
        let n = chunk.len();
        let v = (u32::from(chunk[0]) << 16)
            | (u32::from(*chunk.get(1).unwrap_or(&0)) << 8)
            | u32::from(*chunk.get(2).unwrap_or(&0));
        for i in 0..4 {
            if i <= n {
                b64.push(B64[((v >> (18 - 6 * i)) & 63) as usize] as char);
            } else {
                b64.push('=');
            }
        }
    }
    let mut out = format!("-----BEGIN {label}-----\n");
    for line in b64.as_bytes().chunks(64) {
        out.push_str(std::str::from_utf8(line).unwrap_or(""));
        out.push('\n');
    }
    out.push_str(&format!("-----END {label}-----\n"));
    out
}

/// `cert_pem`/`key_pem` as the files the library reads, for one use. The
/// key's content never enters an error.
fn own_from_pem(root: &Path, cert_pem: &str, key_pem: &str) -> Result<KeyLease, String> {
    let cert = X509::from_pem(cert_pem.as_bytes())
        .map_err(|_| "cert_pem: not a PEM certificate".to_owned())?;
    PrivateKey::from_pem(key_pem.as_bytes())
        .map_err(|_| "key_pem: not a PEM RSA private key".to_owned())?;
    let h = hash16(&[cert_pem]);
    let cert_path = root.join("own").join(format!("user-{h}.der"));
    let key_path = root.join("private").join(format!("user-{h}.pem"));
    let der = cert.to_der().map_err(|e| format!("cert_pem: {e}"))?;
    // Written and counted under the lock: a last use that ends at the same
    // time removes the files before, never after, this write.
    let mut used = IN_USE.lock().unwrap_or_else(|p| p.into_inner());
    write_file(&cert_path, &der, false)?;
    write_file(&key_path, key_pem.as_bytes(), true)?;
    *used.entry(key_path.clone()).or_insert(0) += 1;
    Ok(KeyLease {
        cert: cert_path,
        key: key_path,
    })
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
    // Made in memory; the key file is created 0600 in a 0700 directory, so
    // it is never readable by others, not even for a moment.
    let (x509, pkey) = X509::cert_and_pkey(&data)?;
    let key_der = pkey
        .to_der()
        .map_err(|e| format!("encode the private key: {e}"))?;
    write_file(
        &key,
        pem("PRIVATE KEY", key_der.as_bytes()).as_bytes(),
        true,
    )?;
    let der = x509
        .to_der()
        .map_err(|e| format!("encode the certificate: {e}"))?;
    write_file(&cert, &der, false)?;
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

#[cfg(test)]
mod tests {
    use super::*;

    fn tmp(name: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("wyrm-opcua-pki-{}-{name}", std::process::id()));
        let _ = fs::remove_dir_all(&d);
        d
    }

    #[cfg(unix)]
    fn mode(p: &Path) -> u32 {
        use std::os::unix::fs::PermissionsExt;
        fs::metadata(p).unwrap().permissions().mode() & 0o777
    }

    #[test]
    fn generated_key_is_private_from_the_start() {
        let root = tmp("gen");
        // a wide private/ dir and a stale temp file of another mode
        fs::create_dir_all(root.join("private")).unwrap();
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            fs::set_permissions(root.join("private"), fs::Permissions::from_mode(0o755)).unwrap();
            let h = hash16(&["urn:t"]);
            let stale = root.join("private").join(format!("app-{h}.tmp"));
            fs::write(&stale, b"x").unwrap();
            fs::set_permissions(&stale, fs::Permissions::from_mode(0o644)).unwrap();
        }
        let (cert, key) = generated(&root, "urn:t").unwrap();
        #[cfg(unix)]
        {
            assert_eq!(mode(&root.join("private")), 0o700);
            assert_eq!(mode(&key), 0o600);
        }
        let pem = fs::read_to_string(&key).unwrap();
        assert!(pem.starts_with("-----BEGIN PRIVATE KEY-----\n"));
        assert!(PrivateKey::from_pem(pem.as_bytes()).is_ok());
        assert!(CertificateStore::read_cert(&cert).is_ok());
        // the library reads them as its own
        let (store, c, k) = CertificateStore::new_with_x509_data(
            &root.join("store"),
            false,
            Some(&cert),
            Some(&key),
            None::<X509Data>,
        );
        assert!(c.is_some() && k.is_some());
        drop(store);
        // made once
        let again = generated(&root, "urn:t").unwrap();
        assert_eq!(again, (cert, key));
        let _ = fs::remove_dir_all(&root);
    }

    /// First use counts once a session was made: a certificate an earlier
    /// attempt stored in `trusted/` is dropped until then.
    #[test]
    fn first_use_counts_after_a_session() {
        let root = tmp("tofu");
        let (cert_pem, key_pem) = test_keypair();
        let req = Request {
            url: "opc.tcp://h:4840/",
            application_uri: "urn:t",
            own: Some((&cert_pem, &key_pem)),
            trust: Trust::FirstUse,
        };
        let p = prepare(&root, &req).unwrap();
        assert!(p.trust_unknown);
        // the library stored the server's certificate, then the open failed
        let server = X509::from_pem(cert_pem.as_bytes()).unwrap();
        let name = CertificateStore::cert_file_name(&server);
        fs::write(
            p.store.join("trusted").join(&name),
            server.to_der().unwrap(),
        )
        .unwrap();
        assert!(p.trusts(&server));
        let p = prepare(&root, &req).unwrap();
        assert!(p.trust_unknown, "a failed first use does not pin");
        assert!(!p.trusts(&server));
        // this time a session was made: then only that certificate
        fs::write(
            p.store.join("trusted").join(&name),
            server.to_der().unwrap(),
        )
        .unwrap();
        p.opened();
        let p = prepare(&root, &req).unwrap();
        assert!(!p.trust_unknown);
        assert!(p.trusts(&server));
        let _ = fs::remove_dir_all(&root);
    }

    fn test_keypair() -> (String, String) {
        let (x509, pkey) = X509::cert_and_pkey(&X509Data {
            key_size: 2048,
            common_name: "t".into(),
            organization: String::new(),
            organizational_unit: String::new(),
            country: String::new(),
            state: String::new(),
            alt_host_names: X509Data::alt_host_names("urn:t", None, false, false, false),
            certificate_duration_days: 1,
        })
        .unwrap();
        (
            pem("CERTIFICATE", &x509.to_der().unwrap()),
            pem("PRIVATE KEY", pkey.to_der().unwrap().as_bytes()),
        )
    }

    #[test]
    fn supplied_key_is_written_private() {
        let root = tmp("own");
        let (x509, pkey) = X509::cert_and_pkey(&X509Data {
            key_size: 2048,
            common_name: "t".into(),
            organization: String::new(),
            organizational_unit: String::new(),
            country: String::new(),
            state: String::new(),
            alt_host_names: X509Data::alt_host_names("urn:t", None, false, false, false),
            certificate_duration_days: 1,
        })
        .unwrap();
        let cert_pem = pem("CERTIFICATE", &x509.to_der().unwrap());
        let key_pem = pem("PRIVATE KEY", pkey.to_der().unwrap().as_bytes());
        let lease = own_from_pem(&root, &cert_pem, &key_pem).unwrap();
        let key = lease.key.clone();
        #[cfg(unix)]
        {
            assert_eq!(mode(&root.join("private")), 0o700);
            assert_eq!(mode(&key), 0o600);
        }
        assert_eq!(fs::read_to_string(&key).unwrap(), key_pem);
        // two uses: the files stay until the last one ends
        let second = own_from_pem(&root, &cert_pem, &key_pem).unwrap();
        drop(lease);
        assert!(key.is_file() && second.cert.is_file());
        let cert = second.cert.clone();
        drop(second);
        assert!(!key.exists() && !cert.exists(), "removed with the last use");
        // files a stopped process left are swept; files in use are not
        let kept = own_from_pem(&root, &cert_pem, &key_pem).unwrap();
        fs::write(root.join("private/user-0011223344556677.pem"), "k").unwrap();
        fs::write(root.join("own/user-0011223344556677.der"), "c").unwrap();
        sweep(&root);
        assert!(!root.join("private/user-0011223344556677.pem").exists());
        assert!(!root.join("own/user-0011223344556677.der").exists());
        assert!(kept.key.is_file() && kept.cert.is_file());
        drop(kept);
        // a bad key never shows in the error
        let e = own_from_pem(&root, &cert_pem, "secret-key-text").unwrap_err();
        assert!(!e.contains("secret-key-text"), "{e}");
        let _ = fs::remove_dir_all(&root);
    }
}
