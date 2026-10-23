//! Link tokens, key files and the internal CA.

use argon2::password_hash::{
    rand_core::OsRng, PasswordHash, PasswordHasher, PasswordVerifier, SaltString,
};
use argon2::Argon2;
use rcgen::{
    BasicConstraints, CertificateParams, CertificateSigningRequestParams, DnType,
    ExtendedKeyUsagePurpose, IsCa, Issuer, KeyPair, KeyUsagePurpose, PublicKeyData,
};
use sha2::{Digest, Sha256};
use std::io::Write;
use std::path::{Path, PathBuf};
use zeroize::Zeroizing;

pub type Error = Box<dyn std::error::Error + Send + Sync>;

/// Write a file readable by the owner only (created fresh, 0600 on unix).
pub fn write_private(path: &Path, data: &[u8]) -> std::io::Result<()> {
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir)?;
    }
    let tmp = path.with_extension("tmp");
    let _ = std::fs::remove_file(&tmp);
    {
        let mut opts = std::fs::OpenOptions::new();
        opts.write(true).create_new(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            opts.mode(0o600);
        }
        let mut f = opts.open(&tmp)?;
        f.write_all(data)?;
        f.sync_all()?;
    }
    std::fs::rename(&tmp, path)
}

/// 32 random bytes, hex encoded: the plaintext link token.
pub fn new_token() -> Result<Zeroizing<String>, Error> {
    let mut raw = Zeroizing::new([0u8; 32]);
    getrandom::fill(raw.as_mut()).map_err(|e| format!("no randomness: {e}"))?;
    Ok(Zeroizing::new(hex::encode(raw.as_ref())))
}

/// argon2id PHC string; the registry stores only this.
pub fn hash_token(token: &str) -> Result<String, Error> {
    let salt = SaltString::generate(&mut OsRng);
    Ok(Argon2::default()
        .hash_password(token.as_bytes(), &salt)
        .map_err(|e| e.to_string())?
        .to_string())
}

pub fn verify_token(token: &[u8], hash: &str) -> bool {
    PasswordHash::new(hash)
        .map(|h| Argon2::default().verify_password(token, &h).is_ok())
        .unwrap_or(false)
}

/// Load a 32-byte key file, or create it.
pub fn load_or_create_key(path: &Path) -> Result<Zeroizing<Vec<u8>>, Error> {
    if let Ok(text) = std::fs::read_to_string(path) {
        let k = Zeroizing::new(hex::decode(text.trim())?);
        if k.len() != 32 {
            return Err(format!("{}: expected 32 bytes", path.display()).into());
        }
        return Ok(k);
    }
    let mut k = Zeroizing::new(vec![0u8; 32]);
    getrandom::fill(&mut k).map_err(|e| format!("no randomness: {e}"))?;
    write_private(path, hex::encode(&*k).as_bytes())?;
    Ok(k)
}

/// Certificate + key files of one identity.
#[derive(Debug, Clone)]
pub struct CertFiles {
    pub cert: PathBuf,
    pub key: PathBuf,
}

/// Internal CA (wiki "Транспорт"): `ca.pem` public, `ca.key` 0600.
pub struct Pki {
    dir: PathBuf,
    issuer: Issuer<'static, KeyPair>,
}

impl Pki {
    pub fn open_or_create(dir: &Path) -> Result<Self, Error> {
        std::fs::create_dir_all(dir)?;
        let (cert_p, key_p) = (dir.join("ca.pem"), dir.join("ca.key"));
        let issuer = match (
            std::fs::read_to_string(&cert_p),
            std::fs::read_to_string(&key_p),
        ) {
            (Ok(cert), Ok(key)) => {
                let key = KeyPair::from_pem(&key)?;
                Issuer::from_ca_cert_pem(&cert, key)?
            }
            _ => {
                let key = KeyPair::generate()?;
                let mut p = CertificateParams::new(Vec::<String>::new())?;
                p.distinguished_name.push(DnType::CommonName, "wyrm-ca");
                p.is_ca = IsCa::Ca(BasicConstraints::Constrained(0));
                p.key_usages = vec![KeyUsagePurpose::KeyCertSign, KeyUsagePurpose::CrlSign];
                p.not_after = rcgen::date_time_ymd(2046, 1, 1);
                let cert = p.self_signed(&key)?;
                write_private(&key_p, key.serialize_pem().as_bytes())?;
                std::fs::write(&cert_p, cert.pem())?;
                Issuer::new(p, key)
            }
        };
        Ok(Self {
            dir: dir.to_path_buf(),
            issuer,
        })
    }

    pub fn ca_path(&self) -> PathBuf {
        self.dir.join("ca.pem")
    }

    /// Issue (or keep, if present) a certificate for `cn` into `out/<name>.{pem,key}`.
    /// `server`: TLS server auth with `sans` (IPs and DNS names).
    pub fn issue(
        &self,
        cn: &str,
        sans: &[String],
        server: bool,
        out: &Path,
        name: &str,
    ) -> Result<CertFiles, Error> {
        let files = CertFiles {
            cert: out.join(format!("{name}.pem")),
            key: out.join(format!("{name}.key")),
        };
        if files.cert.exists() && files.key.exists() {
            return Ok(files);
        }
        let key = KeyPair::generate()?;
        let p = leaf_params(cn, sans, server)?;
        let cert = p.signed_by(&key, &self.issuer)?;
        write_private(&files.key, key.serialize_pem().as_bytes())?;
        std::fs::create_dir_all(out)?;
        std::fs::write(&files.cert, cert.pem())?;
        Ok(files)
    }

    /// Sign a downstream broker's request (ADR 0015): a certificate for
    /// `broker:<site>`, client auth, one year, made from fresh parameters
    /// (nothing the request asks for besides its key). Returns the PEM.
    pub fn sign_broker_csr(&self, site: &str, csr_pem: &str) -> Result<String, Error> {
        let csr = broker_csr_params(site, csr_pem)?;
        let p = leaf_params(&format!("broker:{site}"), &[], false)?;
        Ok(p.signed_by(&csr.public_key, &self.issuer)?.pem())
    }

    /// Remove the files of an identity (link removed).
    pub fn forget(out: &Path, name: &str) {
        let _ = std::fs::remove_file(out.join(format!("{name}.pem")));
        let _ = std::fs::remove_file(out.join(format!("{name}.key")));
    }
}

/// Parameters of a leaf certificate for `cn`: one year from today.
fn leaf_params(cn: &str, sans: &[String], server: bool) -> Result<CertificateParams, Error> {
    let mut p = CertificateParams::new(sans.to_vec())?;
    p.distinguished_name.push(DnType::CommonName, cn);
    p.extended_key_usages = vec![if server {
        ExtendedKeyUsagePurpose::ServerAuth
    } else {
        ExtendedKeyUsagePurpose::ClientAuth
    }];
    p.key_usages = vec![KeyUsagePurpose::DigitalSignature];
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0);
    p.not_before = rcgen::date_time_ymd(1975, 1, 1);
    let (y, m, d) = civil_from_days(now.div_euclid(86_400) + 365);
    p.not_after = rcgen::date_time_ymd(y as i32, m as u8, d as u8);
    Ok(p)
}

/// Largest certificate request accepted.
pub const MAX_CSR: usize = 16 * 1024;

/// A downstream broker's certificate request: one PEM request, signed by
/// its key (checked), for CN `broker:<site>` exactly.
fn broker_csr_params(site: &str, csr_pem: &str) -> Result<CertificateSigningRequestParams, Error> {
    if csr_pem.len() > MAX_CSR {
        return Err("csr: larger than 16 KiB".into());
    }
    let csr = CertificateSigningRequestParams::from_pem(csr_pem.trim())
        .map_err(|e| format!("csr: {e}"))?;
    let want = format!("broker:{site}");
    let cn = csr
        .params
        .distinguished_name
        .get(&DnType::CommonName)
        .map(dn_text);
    if cn.as_deref() != Some(want.as_str()) {
        return Err(format!("csr: for {}, not {want}", cn.unwrap_or_default()).into());
    }
    Ok(csr)
}

fn dn_text(v: &rcgen::DnValue) -> String {
    match v {
        rcgen::DnValue::Utf8String(s) => s.clone(),
        rcgen::DnValue::PrintableString(s) => s.as_str().to_owned(),
        rcgen::DnValue::Ia5String(s) => s.as_str().to_owned(),
        _ => String::new(),
    }
}

/// SHA-256 (hex) of the public key in a broker's certificate request: what
/// both administrators compare before Authorize.
pub fn broker_csr_key(site: &str, csr_pem: &str) -> Result<String, Error> {
    let csr = broker_csr_params(site, csr_pem)?;
    Ok(hex::encode(Sha256::digest(
        csr.public_key.subject_public_key_info(),
    )))
}

/// A new key for this broker towards an upstream site: `(key PEM, SHA-256
/// of its public key)`. The key stays on this site (ADR 0015).
pub fn new_broker_key() -> Result<(Zeroizing<String>, String), Error> {
    let key = KeyPair::generate()?;
    let sha = hex::encode(Sha256::digest(key.subject_public_key_info()));
    Ok((Zeroizing::new(key.serialize_pem()), sha))
}

/// The certificate request of `broker:<site>` for the key `key_pem`.
pub fn broker_csr(site: &str, key_pem: &str) -> Result<String, Error> {
    let key = KeyPair::from_pem(key_pem)?;
    let mut p = CertificateParams::new(Vec::<String>::new())?;
    p.distinguished_name
        .push(DnType::CommonName, format!("broker:{site}"));
    Ok(p.serialize_request(&key)?.pem()?)
}

/// Days since 1970-01-01 → (year, month, day), proleptic Gregorian.
pub(crate) fn civil_from_days(z: i64) -> (i64, u32, u32) {
    let z = z + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = (doy - (153 * mp + 2) / 5 + 1) as u32;
    let m = if mp < 10 { mp + 3 } else { mp - 9 } as u32;
    let y = yoe + era * 400 + i64::from(m <= 2);
    (y, m, d)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// ADR 0015: the downstream's request carries its key; the upstream
    /// signs `broker:<site>` for that key and nothing else.
    #[test]
    fn broker_requests_and_certificates() {
        let dir = std::env::temp_dir().join(format!("wyrm-pki-csr-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let pki = Pki::open_or_create(&dir).unwrap();
        let (key, sha) = new_broker_key().unwrap();
        let csr = broker_csr("edge", &key).unwrap();
        assert_eq!(broker_csr_key("edge", &csr).unwrap(), sha);
        assert!(
            broker_csr_key("plant", &csr).is_err(),
            "another site's name"
        );
        let pem = pki.sign_broker_csr("edge", &csr).unwrap();
        let (_, block) = x509_parser::pem::parse_x509_pem(pem.as_bytes()).unwrap();
        let cert = block.parse_x509().unwrap();
        let cn = cert.subject().iter_common_name().next().unwrap();
        assert_eq!(cn.as_str().unwrap(), "broker:edge");
        assert_eq!(hex::encode(Sha256::digest(cert.public_key().raw)), sha);
        // a request whose signature does not match is refused
        let mut bad = csr.clone();
        let mid = bad.len() / 2;
        bad.replace_range(mid..mid + 4, "AAAA");
        assert!(pki.sign_broker_csr("edge", &bad).is_err());
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn civil_dates() {
        assert_eq!(civil_from_days(0), (1970, 1, 1));
        assert_eq!(civil_from_days(19_723), (2024, 1, 1));
        assert_eq!(civil_from_days(19_782), (2024, 2, 29));
    }

    #[test]
    fn tokens() {
        let t = new_token().unwrap();
        assert_eq!(t.len(), 64);
        let h = hash_token(&t).unwrap();
        assert!(h.starts_with("$argon2id$"));
        assert!(verify_token(t.as_bytes(), &h));
        assert!(!verify_token(b"wrong", &h));
        assert!(!verify_token(t.as_bytes(), "not a hash"));
    }
}
