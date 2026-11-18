//! Link tokens, key files and the internal CA.

use crate::eckey::EcKey;
use argon2::password_hash::{PasswordHash, PasswordHasher, PasswordVerifier, SaltString};
use argon2::Argon2;
use rcgen::{
    BasicConstraints, CertificateParams, CertificateSigningRequestParams, DnType,
    ExtendedKeyUsagePurpose, IsCa, Issuer, KeyUsagePurpose, PublicKeyData,
};
use std::io::Write;
use std::path::{Path, PathBuf};
use zeroize::Zeroizing;

pub type Error = Box<dyn std::error::Error + Send + Sync>;

/// Write a file readable by the owner only (created fresh, 0600 on unix). A
/// directory of `path` that is missing is made 0700; one that exists is left
/// as it is (an operator's output directory). The file is created new (a
/// symlink in its place is not followed) and renamed into place. For a
/// directory that must itself be private, use [`private_dir`].
pub fn write_private(path: &Path, data: &[u8]) -> std::io::Result<()> {
    if let Some(dir) = path.parent() {
        create_missing_private(dir)?;
    }
    let tmp = path.with_extension("tmp");
    wyrm_core::files::discard(&tmp);
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

/// The directories of `dir` that are missing, made 0700 (each of them);
/// existing ones are not changed.
pub fn create_missing_private(dir: &Path) -> std::io::Result<()> {
    let mut b = std::fs::DirBuilder::new();
    b.recursive(true);
    #[cfg(unix)]
    std::os::unix::fs::DirBuilderExt::mode(&mut b, 0o700);
    b.create(dir)
}

/// A directory only its owner enters, held open: what is written into it
/// through [`PrivateDir::write_file`] lands in this very directory, whatever
/// is swapped on its path afterwards.
#[derive(Debug)]
pub struct PrivateDir {
    path: PathBuf,
    #[cfg(unix)]
    fd: std::os::fd::OwnedFd,
}

fn refused(path: &Path, why: impl std::fmt::Display) -> std::io::Error {
    std::io::Error::new(
        std::io::ErrorKind::PermissionDenied,
        format!("{}: not a private directory: {why}", path.display()),
    )
}

/// `root/rel` as a private directory. `root` is the broker's own directory
/// (`data_dir`; it may be a symlink the operator set up) and must exist.
/// Each component of `rel` is made (0700) or opened below the held handle of
/// the one before, never through a symlink: a symlink or a non-directory on
/// the way is refused, not followed (a link's own data, `links/<id>/data/**`,
/// may hold symlinks it planted). The last directory must be owned by the
/// user this process runs as, and is set to 0700 through its open handle.
/// `rel` is plain segments only.
pub fn private_dir(root: &Path, rel: &Path) -> std::io::Result<PrivateDir> {
    let path = root.join(rel);
    for c in rel.components() {
        if !matches!(c, std::path::Component::Normal(_)) {
            return Err(refused(
                &path,
                "the path has a part that is not a plain name",
            ));
        }
    }
    #[cfg(unix)]
    {
        use rustix::fs::{fchmod, fstat, mkdirat, open, openat, Mode, OFlags};
        let dir_flags = OFlags::RDONLY | OFlags::DIRECTORY | OFlags::CLOEXEC;
        let mut fd = open(root, dir_flags, Mode::empty())
            .map_err(|e| std::io::Error::new(e.kind(), format!("{}: {e}", root.display())))?;
        for c in rel.components() {
            let name = c.as_os_str();
            match mkdirat(&fd, name, Mode::RWXU) {
                Ok(()) => {}
                Err(e) if e == rustix::io::Errno::EXIST => {}
                Err(e) => return Err(refused(&path, e)),
            }
            fd = openat(&fd, name, dir_flags | OFlags::NOFOLLOW, Mode::empty()).map_err(|e| {
                refused(
                    &path,
                    format!(
                        "{} is a symlink or not a directory ({e})",
                        name.to_string_lossy()
                    ),
                )
            })?;
        }
        let st = fstat(&fd).map_err(|e| refused(&path, e))?;
        let me = rustix::process::geteuid().as_raw();
        if st.st_uid != me {
            return Err(refused(
                &path,
                format!("owned by uid {}, not by this process's uid {me}", st.st_uid),
            ));
        }
        fchmod(&fd, Mode::RWXU).map_err(|e| refused(&path, e))?;
        Ok(PrivateDir { path, fd })
    }
    #[cfg(not(unix))]
    {
        std::fs::create_dir_all(&path)?;
        Ok(PrivateDir { path })
    }
}

/// Write `rel` (plain segments, a file name last) below `root` as
/// [`private_dir`] reaches its directory: never through a symlink, the
/// directory 0700 and this user's, the file 0600 through its handle.
pub fn write_private_under(root: &Path, rel: &Path, data: &[u8]) -> std::io::Result<()> {
    let (Some(dir), Some(name)) = (rel.parent(), rel.file_name().and_then(|n| n.to_str())) else {
        return Err(refused(&root.join(rel), "not a file name"));
    };
    private_dir(root, dir)?.write_file(name, data, false)
}

/// [`private_dir`] for a directory of the broker's own (backups, restore
/// points, staging): its parent is made if missing (0700) and trusted, the
/// directory itself is checked as [`private_dir`] does.
pub fn private_dir_of(dir: &Path) -> std::io::Result<PrivateDir> {
    let (Some(parent), Some(name)) = (dir.parent(), dir.file_name()) else {
        return Err(refused(dir, "no parent directory"));
    };
    create_missing_private(parent)?;
    private_dir(parent, Path::new(name))
}

impl PrivateDir {
    pub fn path(&self) -> &Path {
        &self.path
    }

    /// Write the file `name` (one plain name) in this directory: created new,
    /// 0600 or 0700 with `exec` (a symlink in its place is not followed),
    /// synced, and renamed into place, all through the held handle.
    pub fn write_file(&self, name: &str, data: &[u8], exec: bool) -> std::io::Result<()> {
        let mut parts = Path::new(name).components();
        let plain = matches!(
            (parts.next(), parts.next()),
            (Some(std::path::Component::Normal(n)), None) if n == std::ffi::OsStr::new(name)
        );
        if !plain {
            return Err(refused(
                &self.path,
                format!("{name:?} is not a plain file name"),
            ));
        }
        let tmp = format!("{name}.tmp");
        #[cfg(unix)]
        {
            use rustix::fs::{openat, renameat, unlinkat, AtFlags, Mode, OFlags};
            match unlinkat(&self.fd, tmp.as_str(), AtFlags::empty()) {
                Ok(()) => {}
                Err(e) if e == rustix::io::Errno::NOENT => {}
                Err(e) => return Err(e.into()),
            }
            let flags =
                OFlags::WRONLY | OFlags::CREATE | OFlags::EXCL | OFlags::NOFOLLOW | OFlags::CLOEXEC;
            let mode = if exec {
                Mode::RWXU
            } else {
                Mode::RUSR | Mode::WUSR
            };
            let fd = openat(&self.fd, tmp.as_str(), flags, mode)?;
            let mut f = std::fs::File::from(fd);
            f.write_all(data)?;
            f.sync_all()?;
            renameat(&self.fd, tmp.as_str(), &self.fd, name)?;
            Ok(())
        }
        #[cfg(not(unix))]
        {
            let _ = exec;
            write_private(&self.path.join(name), data)
        }
    }
}

/// 32 random bytes, hex encoded: the plaintext link token.
pub fn new_token() -> Result<Zeroizing<String>, Error> {
    let mut raw = Zeroizing::new([0u8; 32]);
    wyrm_core::rand::fill(raw.as_mut()).map_err(|e| e.to_string())?;
    Ok(Zeroizing::new(hex::encode(raw.as_ref())))
}

/// argon2id PHC string; the registry stores only this.
pub fn hash_token(token: &str) -> Result<String, Error> {
    // 16 bytes (the recommended salt length) from the one source; no panic when it fails
    let salt = SaltString::encode_b64(&wyrm_core::rand::bytes::<16>().map_err(|e| e.to_string())?)
        .map_err(|e| e.to_string())?;
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
    wyrm_core::rand::fill(&mut k).map_err(|e| e.to_string())?;
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
    issuer: Issuer<'static, EcKey>,
}

impl Pki {
    /// `dir` (`data_dir/pki`) is reached as [`private_dir_of`] does: its parent is
    /// the broker's own, `dir` itself is never a symlink, belongs to this user and
    /// is 0700; a new CA's files are written through its handle.
    pub fn open_or_create(dir: &Path) -> Result<Self, Error> {
        let pd = private_dir_of(dir)?;
        let (cert_p, key_p) = (dir.join("ca.pem"), dir.join("ca.key"));
        let issuer = match (
            std::fs::read_to_string(&cert_p),
            std::fs::read_to_string(&key_p),
        ) {
            (Ok(cert), Ok(key)) => {
                let key = EcKey::from_pem(&key)?;
                Issuer::from_ca_cert_pem(&cert, key)?
            }
            _ => {
                let key = EcKey::generate()?;
                let mut p = CertificateParams::new(Vec::<String>::new())?;
                p.distinguished_name.push(DnType::CommonName, "wyrm-ca");
                p.is_ca = IsCa::Ca(BasicConstraints::Constrained(0));
                p.key_usages = vec![KeyUsagePurpose::KeyCertSign, KeyUsagePurpose::CrlSign];
                p.not_after = rcgen::date_time_ymd(2046, 1, 1);
                let cert = p.self_signed(&key)?;
                pd.write_file("ca.key", key.pem().as_bytes(), false)?;
                pd.write_file("ca.pem", cert.pem().as_bytes(), false)?;
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

    /// Issue a certificate for `cn` into `out/<name>.{pem,key}`, or keep the one there while it
    /// is for `cn` and `sans` and has more than [`RENEW_BEFORE_S`] left (security review D-1: a
    /// certificate issued once and never renewed takes the site down after a year).
    /// `server`: TLS server auth with `sans` (IPs and DNS names).
    pub fn issue(
        &self,
        cn: &str,
        sans: &[String],
        server: bool,
        out: &Path,
        name: &str,
    ) -> Result<CertFiles, Error> {
        self.issue_lasting(cn, sans, server, out, name, LEAF_DAYS)
    }

    pub fn issue_lasting(
        &self,
        cn: &str,
        sans: &[String],
        server: bool,
        out: &Path,
        name: &str,
        days: i64,
    ) -> Result<CertFiles, Error> {
        let files = CertFiles {
            cert: out.join(format!("{name}.pem")),
            key: out.join(format!("{name}.key")),
        };
        if files.key.exists() {
            if let Ok(pem) = std::fs::read_to_string(&files.cert) {
                if still_good(&pem, cn, sans) {
                    return Ok(files);
                }
            }
        }
        let key = EcKey::generate()?;
        let p = leaf_params(cn, sans, server, days)?;
        let cert = p.signed_by(&key, &self.issuer)?;
        // `out` (`pki`, `links/<id>`, `operators`) as a private directory: never
        // through a symlink, the key written through its handle
        let pd = private_dir_of(out)?;
        pd.write_file(&format!("{name}.key"), key.pem().as_bytes(), false)?;
        pd.write_file(&format!("{name}.pem"), cert.pem().as_bytes(), false)?;
        Ok(files)
    }

    /// Sign a downstream broker's request (ADR 0015): a certificate for
    /// `broker:<site>`, client auth, one year, made from fresh parameters
    /// (nothing the request asks for besides its key). Returns the PEM.
    pub fn sign_broker_csr(&self, site: &str, csr_pem: &str) -> Result<String, Error> {
        let csr = broker_csr_params(site, csr_pem)?;
        let p = leaf_params(&format!("broker:{site}"), &[], false, LEAF_DAYS)?;
        Ok(p.signed_by(&csr.public_key, &self.issuer)?.pem())
    }
}

/// Days a leaf certificate lasts.
const LEAF_DAYS: i64 = 365;
/// A certificate with less than this left is issued again (and an enrolled broker asks again).
pub const RENEW_BEFORE_S: i64 = 30 * 86_400;

use wyrm_core::clock::now_s_signed;

/// `not_after` (Unix seconds) of a PEM certificate; `None` if it does not parse.
pub fn cert_not_after(pem: &str) -> Option<i64> {
    let (_, block) = x509_parser::pem::parse_x509_pem(pem.trim().as_bytes()).ok()?;
    let cert = block.parse_x509().ok()?;
    Some(cert.validity().not_after.timestamp())
}

/// It has less than [`RENEW_BEFORE_S`] left, or cannot be read: time to issue it again.
pub fn cert_due(pem: &str) -> bool {
    cert_not_after(pem).is_none_or(|t| t - now_s_signed() < RENEW_BEFORE_S)
}

/// A kept certificate is for `cn`, names every one of `sans` and is not due.
fn still_good(pem: &str, cn: &str, sans: &[String]) -> bool {
    use x509_parser::extensions::GeneralName;
    let Ok((_, block)) = x509_parser::pem::parse_x509_pem(pem.trim().as_bytes()) else {
        return false;
    };
    let Ok(cert) = block.parse_x509() else {
        return false;
    };
    let named = cert
        .subject()
        .iter_common_name()
        .next()
        .and_then(|a| a.as_str().ok());
    if named != Some(cn) || cert_due(pem) {
        return false;
    }
    let have: Vec<String> = cert
        .subject_alternative_name()
        .ok()
        .flatten()
        .map(|e| {
            e.value
                .general_names
                .iter()
                .filter_map(|g| match g {
                    GeneralName::DNSName(d) => Some((*d).to_owned()),
                    GeneralName::IPAddress(b) => match b.len() {
                        4 => <[u8; 4]>::try_from(*b)
                            .ok()
                            .map(|a| std::net::IpAddr::from(a).to_string()),
                        16 => <[u8; 16]>::try_from(*b)
                            .ok()
                            .map(|a| std::net::IpAddr::from(a).to_string()),
                        _ => None,
                    },
                    _ => None,
                })
                .collect()
        })
        .unwrap_or_default();
    sans.iter().all(|s| {
        let s = s
            .parse::<std::net::IpAddr>()
            .map_or(s.clone(), |ip| ip.to_string());
        have.contains(&s)
    })
}

/// Parameters of a leaf certificate for `cn`: `days` from today.
fn leaf_params(
    cn: &str,
    sans: &[String],
    server: bool,
    days: i64,
) -> Result<CertificateParams, Error> {
    let mut p = CertificateParams::new(sans.to_vec())?;
    p.distinguished_name.push(DnType::CommonName, cn);
    p.extended_key_usages = vec![if server {
        ExtendedKeyUsagePurpose::ServerAuth
    } else {
        ExtendedKeyUsagePurpose::ClientAuth
    }];
    p.key_usages = vec![KeyUsagePurpose::DigitalSignature];
    p.not_before = rcgen::date_time_ymd(1975, 1, 1);
    let (y, m, d) = civil_from_days(now_s_signed().div_euclid(86_400) + days);
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
    Ok(wyrm_core::hex::sha256_hex(
        csr.public_key.subject_public_key_info(),
    ))
}

/// A new key for this broker towards an upstream site: `(key PEM, SHA-256
/// of its public key)`. The key stays on this site (ADR 0015).
pub fn new_broker_key() -> Result<(Zeroizing<String>, String), Error> {
    let key = EcKey::generate()?;
    let sha = wyrm_core::hex::sha256_hex(key.subject_public_key_info());
    Ok((key.pem(), sha))
}

/// The certificate request of `broker:<site>` for the key `key_pem`.
pub fn broker_csr(site: &str, key_pem: &str) -> Result<String, Error> {
    let key = EcKey::from_pem(key_pem)?;
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

    /// A directory that others could read is made the owner's only.
    #[cfg(unix)]
    #[test]
    fn a_private_dir_is_the_owners_only() {
        use std::os::unix::fs::PermissionsExt;
        let dir = std::env::temp_dir().join(format!("wyrm-private-dir-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::set_permissions(&dir, std::fs::Permissions::from_mode(0o755)).unwrap();
        std::fs::create_dir_all(dir.join("links/l1")).unwrap();
        std::fs::set_permissions(dir.join("links/l1"), std::fs::Permissions::from_mode(0o755))
            .unwrap();
        let pki = private_dir(&dir, Path::new("pki")).unwrap();
        private_dir(&dir, Path::new("")).unwrap();
        let deep = private_dir(&dir, Path::new("links/l1/data/a")).unwrap();
        for d in [dir.clone(), dir.join("pki"), dir.join("links/l1/data/a")] {
            let mode = std::fs::metadata(&d).unwrap().permissions().mode() & 0o777;
            assert_eq!(mode, 0o700, "{}", d.display());
        }
        // a file written through the handle is the owner's only and lands there
        pki.write_file("ca.key", b"key", false).unwrap();
        deep.write_file("run", b"#!", true).unwrap();
        let m = |p: &Path| std::fs::metadata(p).unwrap().permissions().mode() & 0o777;
        assert_eq!(m(&dir.join("pki/ca.key")), 0o600);
        assert_eq!(m(&dir.join("links/l1/data/a/run")), 0o700);
        assert_eq!(std::fs::read(dir.join("pki/ca.key")).unwrap(), b"key");
        assert!(pki.write_file("../x", b"", false).is_err());
        assert!(private_dir(&dir, Path::new("../x")).is_err());
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// Audit of #125: `pki` (or a directory a link planted under its data) as a
    /// symlink to a directory the broker's own user owns was followed: the target
    /// was made 0700 and the keys landed outside `data_dir`. A symlink anywhere
    /// below the root is refused now, and nothing outside is touched.
    #[cfg(unix)]
    #[test]
    fn a_symlink_to_an_own_directory_is_not_a_private_dir() {
        use std::os::unix::fs::{symlink, PermissionsExt};
        let base = std::env::temp_dir().join(format!("wyrm-private-link-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&base);
        let (data, outside) = (base.join("data"), base.join("outside"));
        std::fs::create_dir_all(data.join("links/l1/data")).unwrap();
        std::fs::create_dir_all(&outside).unwrap();
        std::fs::set_permissions(&outside, std::fs::Permissions::from_mode(0o755)).unwrap();
        symlink(&outside, data.join("pki")).unwrap();
        symlink(&outside, data.join("links/l1/data/sub")).unwrap();
        // as the last part and as a part on the way
        for rel in ["pki", "links/l1/data/sub", "links/l1/data/sub/deeper"] {
            let e = private_dir(&data, Path::new(rel)).unwrap_err();
            assert!(e.to_string().contains("symlink"), "{rel}: {e}");
        }
        // a file in the way is refused too
        std::fs::write(data.join("plain"), b"").unwrap();
        assert!(private_dir(&data, Path::new("plain")).is_err());
        let mode = std::fs::metadata(&outside).unwrap().permissions().mode() & 0o777;
        assert_eq!(mode, 0o755, "the target is not touched");
        assert!(!outside.join("deeper").exists());
        let _ = std::fs::remove_dir_all(&base);
    }

    /// Re-audit of #125: a broker start made its CA through a symlinked `pki` (that `keys
    /// import` refuses), and certificates and peer keys too. The CA's directory, an issued
    /// identity's directory and the peer files are reached without following a symlink.
    #[cfg(unix)]
    #[test]
    fn the_ca_and_issued_keys_follow_no_symlink() {
        use std::os::unix::fs::{symlink, PermissionsExt};
        let base = std::env::temp_dir().join(format!("wyrm-pki-link-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&base);
        let (data, outside) = (base.join("data"), base.join("outside"));
        std::fs::create_dir_all(&data).unwrap();
        std::fs::create_dir_all(&outside).unwrap();
        std::fs::set_permissions(&outside, std::fs::Permissions::from_mode(0o755)).unwrap();
        symlink(&outside, data.join("pki")).unwrap();
        let e = Pki::open_or_create(&data.join("pki"))
            .err()
            .map(|e| e.to_string());
        assert!(
            e.is_some_and(|e| e.contains("symlink")),
            "the CA is not made there"
        );
        assert!(!outside.join("ca.key").exists());
        // a real `pki`: the CA is made, 0700; an identity's directory as a symlink is refused
        std::fs::remove_file(data.join("pki")).unwrap();
        let pki = Pki::open_or_create(&data.join("pki")).unwrap();
        let mode = std::fs::metadata(data.join("pki"))
            .unwrap()
            .permissions()
            .mode()
            & 0o777;
        assert_eq!(mode, 0o700);
        std::fs::create_dir_all(data.join("links")).unwrap();
        symlink(&outside, data.join("links/l1")).unwrap();
        assert!(pki
            .issue("l1", &[], false, &data.join("links/l1"), "link")
            .is_err());
        assert!(!outside.join("link.key").exists());
        // the peer files below `data_dir` the same way
        symlink(&outside, data.join("pki/peers")).unwrap();
        let rel = Path::new("pki/peers/up.key");
        assert!(write_private_under(&data, rel, b"k").is_err());
        assert!(!outside.join("up.key").exists());
        assert_eq!(
            std::fs::metadata(&outside).unwrap().permissions().mode() & 0o777,
            0o755,
            "the target is not touched"
        );
        let _ = std::fs::remove_dir_all(&base);
    }

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
        assert_eq!(wyrm_core::hex::sha256_hex(cert.public_key().raw), sha);
        // a request whose signature does not match is refused
        let mut bad = csr.clone();
        let mid = bad.len() / 2;
        bad.replace_range(mid..mid + 4, "AAAA");
        assert!(pki.sign_broker_csr("edge", &bad).is_err());
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// Review D-1: a certificate close to its end, or for other names, is issued again; a
    /// fresh one for the same names is kept.
    #[test]
    fn certificates_are_renewed_before_they_end() {
        let dir = std::env::temp_dir().join(format!("wyrm-pki-renew-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let pki = Pki::open_or_create(&dir).unwrap();
        let out = dir.join("out");
        let sans = vec!["127.0.0.1".to_owned(), "localhost".to_owned()];
        let read = || std::fs::read_to_string(out.join("srv.pem")).unwrap();
        pki.issue_lasting("broker:s", &sans, true, &out, "srv", 10)
            .unwrap();
        let short = read();
        assert!(cert_due(&short));
        pki.issue("broker:s", &sans, true, &out, "srv").unwrap();
        let renewed = read();
        assert_ne!(renewed, short, "renewed");
        assert!(!cert_due(&renewed));
        assert!(cert_not_after(&renewed).unwrap() - now_s_signed() > 300 * 86_400);
        pki.issue("broker:s", &sans, true, &out, "srv").unwrap();
        assert_eq!(read(), renewed, "kept while fresh");
        // a new name in the SANs, or another CN: issued again
        let more = vec!["127.0.0.1".to_owned(), "edge.example".to_owned()];
        pki.issue("broker:s", &more, true, &out, "srv").unwrap();
        assert_ne!(read(), renewed);
        let again = read();
        pki.issue("broker:t", &more, true, &out, "srv").unwrap();
        assert_ne!(read(), again);
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
