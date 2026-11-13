//! `wyrmd` releases and the install layout of a broker that updates itself
//! (ADR 0048 §2). Everything here works on files alone, so the running
//! broker, the `update-guard` and the release tooling share it.
//!
//! * A **release** is one JSON document (`wyrmd-<version>.release.json`)
//!   with the version, what it needs and one archive per target, and a
//!   detached Ed25519 signature over its bytes. The **index**
//!   (`releases.json`) is a list of releases, signed the same way under
//!   another domain. A signature is checked against keys pinned in this
//!   binary or in `wyrmd.json5`, never against a key the document names.
//! * An **archive** (`wyrmd-<version>-<target>.tar.gz`) holds the binary
//!   `wyrmd` and at most a few plain files. Its SHA-256 and size come from
//!   the signed release; it is hashed before a byte of it is unpacked.
//! * The **layout** is `<prefix>/versions/<v>/wyrmd`, the symbolic link
//!   `<prefix>/current` → `versions/<v>` and the guard copy
//!   `<prefix>/bin/wyrmd-guard`.
//! * **`update.json`** in `data_dir` is the state of one update: written by
//!   the version that starts it, read by the new version and by the guard.

use ed25519_dalek::{Signature, Signer, SigningKey, VerifyingKey};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::BTreeMap;
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::sync::OnceLock;

/// Version of the release and index documents.
pub const FORMAT: u32 = 1;
/// The binary in an archive and in a version directory.
pub const BIN: &str = "wyrmd";
/// The guard copy in `<prefix>/bin`.
pub const GUARD: &str = "wyrmd-guard";
/// Largest archive taken (a debug build is some hundred MiB).
pub const MAX_ARCHIVE: u64 = 512 << 20;
/// Largest binary unpacked.
pub const MAX_BINARY: u64 = 1 << 30;
/// Largest other file of an archive (a licence, a readme).
pub const MAX_EXTRA: u64 = 1 << 20;
/// Most files in an archive, the binary among them.
pub const MAX_FILES: usize = 9;
/// Largest release document; the index may be four times that.
pub const MAX_RELEASE: usize = 256 << 10;
/// Exit code of a new version that gives its trial up (ADR 0048 §2.5).
pub const TRIAL_EXIT: i32 = 76;
/// Starts of a new version before the guard takes it back.
pub const MAX_ATTEMPTS: u32 = 3;
/// `data_dir/update.json`.
pub const STATE_FILE: &str = "update.json";
/// `data_dir/update.guard`: when the guard ran last.
pub const GUARD_STAMP: &str = "update.guard";
/// The replication protocol between the brokers of a standby pair (ADR
/// 0036): `sys/replication/**` as this version asks and answers it.
pub const REPLICATION_PROTOCOL: u32 = 1;

const DOMAIN_RELEASE: &[u8] = b"wyrmd-release-v1\n";
const DOMAIN_INDEX: &[u8] = b"wyrmd-releases-v1\n";

/// The WYRM release keys built into this binary (Ed25519 public keys, hex).
/// Empty until the project has a release key: a broker then trusts only
/// the keys of `updates.keys` in `wyrmd.json5`
/// (`packaging/wyrmd/README.md` says how the key is made and pinned here).
pub const RELEASE_KEYS: [&str; 0] = [];

/// What a `wyrmd` binary is: told by `wyrmd release-info`, compared with a
/// release before it is installed.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Identity {
    pub version: String,
    /// `<arch>-<os>[-musl]`, the name of its archive's target.
    pub target: String,
    /// `State::SCHEMA` of each control-plane store it writes: `registry`,
    /// `audit`, `users`, `flows`.
    pub schemas: BTreeMap<String, u32>,
    /// [`REPLICATION_PROTOCOL`].
    pub replication: u32,
}

static IDENTITY: OnceLock<Identity> = OnceLock::new();

/// `<arch>-<os>[-musl]` of this build.
pub fn target() -> String {
    let musl = if cfg!(target_env = "musl") {
        "-musl"
    } else {
        ""
    };
    format!(
        "{}-{}{musl}",
        std::env::consts::ARCH,
        std::env::consts::OS
    )
}

/// The identity of this build as far as this crate knows it: the stores of
/// other crates (`users`, `flows`) are added by `wyrmd`.
pub fn built() -> Identity {
    use wyrm_state::State;
    Identity {
        version: env!("CARGO_PKG_VERSION").to_owned(),
        target: target(),
        schemas: BTreeMap::from([
            (
                "registry".to_owned(),
                crate::registry::Registry::SCHEMA,
            ),
            ("audit".to_owned(), crate::audit::AuditLog::SCHEMA),
        ]),
        replication: REPLICATION_PROTOCOL,
    }
}

/// Set what this process is, once, before anything reads it (`wyrmd` at
/// start). Later calls change nothing.
pub fn set_identity(i: Identity) {
    let _ = IDENTITY.set(i);
}

/// What this process is ([`set_identity`], else [`built`]).
pub fn identity() -> &'static Identity {
    IDENTITY.get_or_init(built)
}

/// Is `v` a version name that may be a directory: 1 to 64 of `0-9 A-Z a-z
/// . + -`, starting with a digit.
pub fn check_version(v: &str) -> Result<(), String> {
    let ok = !v.is_empty()
        && v.len() <= 64
        && v.as_bytes()[0].is_ascii_digit()
        && v.bytes()
            .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'.' | b'+' | b'-'))
        && !v.contains("..");
    if ok {
        Ok(())
    } else {
        Err(format!("version {v:?}: not a version name"))
    }
}

fn core(v: &str) -> Option<Vec<u64>> {
    let v = v.split('+').next().unwrap_or(v);
    let core = v.split('-').next().unwrap_or(v);
    core.split('.').map(|s| s.parse::<u64>().ok()).collect()
}

/// Is `a` a newer version than `b`? Dotted numbers compare as numbers; with
/// the same numbers a release is newer than its pre-release; build metadata
/// does not count. Unlike a package's version, a broker's must be dotted
/// numbers: anything else is never newer.
pub fn newer(a: &str, b: &str) -> bool {
    let (Some(x), Some(y)) = (core(a), core(b)) else {
        return false;
    };
    if x != y {
        return x > y;
    }
    let pre = |v: &str| {
        let v = v.split('+').next().unwrap_or(v);
        v.split_once('-').map(|(_, p)| p.to_owned())
    };
    match (pre(a), pre(b)) {
        (None, Some(_)) => true,
        (Some(a), Some(b)) => a > b,
        _ => false,
    }
}

/// One archive of a release.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Asset {
    /// `wyrmd-<version>-<target>.tar.gz`.
    pub file: String,
    /// Hex, lower case.
    pub sha256: String,
    pub size: u64,
    /// Where it is (`https://`); empty: beside the index.
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub url: String,
}

/// One release of `wyrmd`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Release {
    /// [`FORMAT`].
    pub wyrmd_release: u32,
    pub version: String,
    /// `YYYY-MM-DD`.
    #[serde(default)]
    pub date: String,
    /// URL of the release notes.
    #[serde(default)]
    pub notes: String,
    /// The oldest version that may update to this one; empty: any.
    #[serde(default)]
    pub min_from: String,
    /// `State::SCHEMA` of each control-plane store this version writes.
    pub schemas: BTreeMap<String, u32>,
    /// Its [`REPLICATION_PROTOCOL`].
    pub replication: u32,
    /// By target ([`target`]).
    pub targets: BTreeMap<String, Asset>,
}

/// `releases.json`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Index {
    /// [`FORMAT`].
    pub wyrmd_releases: u32,
    pub releases: Vec<Release>,
}

fn plain_name(s: &str, max: usize) -> bool {
    !s.is_empty()
        && s.len() <= max
        && !s.starts_with('.')
        && !s.starts_with('-')
        && s.bytes()
            .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'.' | b'_' | b'-' | b'+'))
        && !s.contains("..")
}

impl Release {
    /// The bounds of a release document.
    pub fn check(&self) -> Result<(), String> {
        if self.wyrmd_release != FORMAT {
            return Err(format!(
                "release format {}: this broker reads format {FORMAT}",
                self.wyrmd_release
            ));
        }
        check_version(&self.version)?;
        if core(&self.version).is_none() {
            return Err(format!("version {:?}: not dotted numbers", self.version));
        }
        if !self.min_from.is_empty() {
            check_version(&self.min_from)?;
        }
        if self.date.len() > 32 || self.notes.len() > 512 {
            return Err("date or notes: too long".into());
        }
        if !self.notes.is_empty() && !self.notes.starts_with("https://") {
            return Err("notes: an https:// URL".into());
        }
        if self.schemas.len() > 16 || self.schemas.keys().any(|k| !plain_name(k, 32)) {
            return Err("schemas: at most 16 plain names".into());
        }
        if self.targets.is_empty() || self.targets.len() > 64 {
            return Err("targets: 1 to 64".into());
        }
        for (t, a) in &self.targets {
            if !plain_name(t, 64) {
                return Err(format!("target {t:?}: not a plain name"));
            }
            if !plain_name(&a.file, 128) || !a.file.ends_with(".tar.gz") {
                return Err(format!("target {t}: file {:?}: a plain *.tar.gz name", a.file));
            }
            if a.sha256.len() != 64
                || !a
                    .sha256
                    .bytes()
                    .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
            {
                return Err(format!("target {t}: sha256: 64 lower-case hex digits"));
            }
            if a.size == 0 || a.size > MAX_ARCHIVE {
                return Err(format!(
                    "target {t}: size {}: 1 to {MAX_ARCHIVE} bytes",
                    a.size
                ));
            }
            if !a.url.is_empty() && (!a.url.starts_with("https://") || a.url.len() > 1024) {
                return Err(format!("target {t}: url: https:// only"));
            }
        }
        Ok(())
    }

    /// May a broker that is `me` update to this release? Its archive for
    /// `me.target`, or why not: no build for the host, a version that is not
    /// newer (an update never goes down), a version too old to start from,
    /// or a release that writes an older SCHEMA than the stores have.
    pub fn compatible(&self, me: &Identity) -> Result<&Asset, String> {
        let asset = self.targets.get(&me.target).ok_or_else(|| {
            format!(
                "wyrmd {} has no build for {} (it has {})",
                self.version,
                me.target,
                self.targets.keys().cloned().collect::<Vec<_>>().join(", ")
            )
        })?;
        if !newer(&self.version, &me.version) {
            return Err(format!(
                "wyrmd {} is not newer than {}: an update never goes down a version",
                self.version, me.version
            ));
        }
        if !self.min_from.is_empty() && newer(&self.min_from, &me.version) {
            return Err(format!(
                "wyrmd {} starts from {} or later; this broker runs {}: update to {} first",
                self.version, self.min_from, me.version, self.min_from
            ));
        }
        for (store, have) in &me.schemas {
            match self.schemas.get(store) {
                Some(n) if n >= have => {}
                Some(n) => {
                    return Err(format!(
                        "wyrmd {} writes SCHEMA {n} of {store}; this data_dir is at {have}: \
                         it cannot be read by an older SCHEMA",
                        self.version
                    ))
                }
                None => {
                    return Err(format!(
                        "wyrmd {} does not name the SCHEMA of {store}",
                        self.version
                    ))
                }
            }
        }
        Ok(asset)
    }

    /// The stores whose SCHEMA this release moves from `me`'s: a rollback
    /// then restores the control plane from the pre-update backup.
    pub fn moves(&self, me: &Identity) -> Vec<String> {
        moved(&me.schemas, &self.schemas)
    }
}

/// The stores whose SCHEMA differs between `from` and `to`.
pub fn moved(from: &BTreeMap<String, u32>, to: &BTreeMap<String, u32>) -> Vec<String> {
    let mut names: Vec<String> = from
        .iter()
        .filter(|(k, v)| to.get(*k) != Some(*v))
        .map(|(k, _)| k.clone())
        .collect();
    names.extend(to.keys().filter(|k| !from.contains_key(*k)).cloned());
    names
}

/// The keys a broker trusts for releases: the built-in ones and `extra`
/// (hex public keys of `updates.keys`).
pub fn pinned_keys(extra: &[String]) -> Result<Vec<VerifyingKey>, String> {
    RELEASE_KEYS
        .iter()
        .map(|k| (*k).to_owned())
        .chain(extra.iter().cloned())
        .map(|k| {
            let raw: [u8; 32] = hex::decode(k.trim())
                .ok()
                .and_then(|b| b.try_into().ok())
                .ok_or("updates.keys: an Ed25519 public key is 64 hex digits")?;
            VerifyingKey::from_bytes(&raw)
                .map_err(|_| "updates.keys: not an Ed25519 public key".to_owned())
        })
        .collect()
}

fn signed_message(domain: &[u8], bytes: &[u8]) -> Vec<u8> {
    let mut m = Vec::with_capacity(domain.len() + bytes.len());
    m.extend_from_slice(domain);
    m.extend_from_slice(bytes);
    m
}

/// Does one line of `signature` (hex Ed25519 signatures, one a line) sign
/// `bytes` under `domain` with one of `keys`?
fn verify(domain: &[u8], bytes: &[u8], signature: &str, keys: &[VerifyingKey]) -> Result<(), String> {
    if keys.is_empty() {
        return Err(
            "no release key is pinned: this build has none and updates.keys is empty".into(),
        );
    }
    let msg = signed_message(domain, bytes);
    let sigs: Vec<Signature> = signature
        .lines()
        .map(str::trim)
        .filter(|l| !l.is_empty())
        .take(8)
        .filter_map(|l| {
            let raw: [u8; 64] = hex::decode(l).ok()?.try_into().ok()?;
            Some(Signature::from_bytes(&raw))
        })
        .collect();
    if sigs.is_empty() {
        return Err("signature: no Ed25519 signature (128 hex digits a line)".into());
    }
    let good = sigs
        .iter()
        .any(|s| keys.iter().any(|k| k.verify_strict(&msg, s).is_ok()));
    if good {
        Ok(())
    } else {
        Err("signature: not made by a pinned release key".into())
    }
}

/// Sign a release document (hex, one line).
pub fn sign_release(bytes: &[u8], key: &SigningKey) -> String {
    hex::encode(key.sign(&signed_message(DOMAIN_RELEASE, bytes)).to_bytes())
}

/// Sign an index (hex, one line).
pub fn sign_index(bytes: &[u8], key: &SigningKey) -> String {
    hex::encode(key.sign(&signed_message(DOMAIN_INDEX, bytes)).to_bytes())
}

/// A release document: the signature first, then its bounds.
pub fn read_release(
    bytes: &[u8],
    signature: &str,
    keys: &[VerifyingKey],
) -> Result<Release, String> {
    if bytes.len() > MAX_RELEASE {
        return Err(format!("release: more than {MAX_RELEASE} bytes"));
    }
    verify(DOMAIN_RELEASE, bytes, signature, keys)?;
    let r: Release = serde_json::from_slice(bytes).map_err(|e| format!("release: {e}"))?;
    r.check()?;
    Ok(r)
}

/// An index: the signature first, then the bounds of every release.
pub fn read_index(bytes: &[u8], signature: &str, keys: &[VerifyingKey]) -> Result<Index, String> {
    if bytes.len() > MAX_RELEASE * 4 {
        return Err(format!("index: more than {} bytes", MAX_RELEASE * 4));
    }
    verify(DOMAIN_INDEX, bytes, signature, keys)?;
    let i: Index = serde_json::from_slice(bytes).map_err(|e| format!("index: {e}"))?;
    if i.wyrmd_releases != FORMAT {
        return Err(format!(
            "index format {}: this broker reads format {FORMAT}",
            i.wyrmd_releases
        ));
    }
    if i.releases.len() > 256 {
        return Err("index: more than 256 releases".into());
    }
    for r in &i.releases {
        r.check()?;
    }
    Ok(i)
}

impl Index {
    /// The newest release with a build for `target`.
    pub fn latest(&self, target: &str) -> Option<&Release> {
        self.releases
            .iter()
            .filter(|r| r.targets.contains_key(target))
            .fold(None, |best: Option<&Release>, r| match best {
                Some(b) if !newer(&r.version, &b.version) => Some(b),
                _ => Some(r),
            })
    }

    pub fn get(&self, version: &str) -> Option<&Release> {
        self.releases.iter().find(|r| r.version == version)
    }
}

fn io(path: &Path, e: std::io::Error) -> String {
    format!("{}: {e}", path.display())
}

/// SHA-256 (hex) and length of a file.
pub fn sha256_file(path: &Path) -> Result<(String, u64), String> {
    let mut f = std::fs::File::open(path).map_err(|e| io(path, e))?;
    let mut h = Sha256::new();
    let mut buf = vec![0u8; 1 << 20];
    let mut total = 0u64;
    loop {
        let n = f.read(&mut buf).map_err(|e| io(path, e))?;
        if n == 0 {
            break;
        }
        h.update(&buf[..n]);
        total += n as u64;
    }
    Ok((hex::encode(h.finalize()), total))
}

fn sync_dir(dir: &Path) {
    // a directory handle syncs on unix; elsewhere it is not needed
    #[cfg(unix)]
    if let Ok(d) = std::fs::File::open(dir) {
        let _ = d.sync_all();
    }
    #[cfg(not(unix))]
    let _ = dir;
}

fn new_file(path: &Path, mode: u32) -> std::io::Result<std::fs::File> {
    let mut o = std::fs::OpenOptions::new();
    o.write(true).create_new(true);
    #[cfg(unix)]
    std::os::unix::fs::OpenOptionsExt::mode(&mut o, mode);
    #[cfg(not(unix))]
    let _ = mode;
    o.open(path)
}

fn new_dir(path: &Path, mode: u32) -> std::io::Result<()> {
    let mut b = std::fs::DirBuilder::new();
    #[cfg(unix)]
    std::os::unix::fs::DirBuilderExt::mode(&mut b, mode);
    #[cfg(not(unix))]
    let _ = mode;
    b.create(path)
}

/// An octal number field of a tar header.
fn octal(field: &[u8]) -> Option<u64> {
    if field.first().is_some_and(|b| b & 0x80 != 0) {
        // base-256: sizes no archive of ours has
        return None;
    }
    let text: Vec<u8> = field
        .iter()
        .copied()
        .skip_while(|b| *b == b' ')
        .take_while(|b| *b != 0 && *b != b' ')
        .collect();
    if text.is_empty() {
        return Some(0);
    }
    let mut n = 0u64;
    for b in text {
        if !(b'0'..=b'7').contains(&b) {
            return None;
        }
        n = n.checked_mul(8)?.checked_add(u64::from(b - b'0'))?;
    }
    Some(n)
}

fn read_full(r: &mut impl Read, buf: &mut [u8]) -> std::io::Result<usize> {
    let mut got = 0;
    while got < buf.len() {
        match r.read(&mut buf[got..])? {
            0 => break,
            n => got += n,
        }
    }
    Ok(got)
}

/// Unpack the tar stream `src` into the new, empty directory `dir`: plain
/// files only, by plain name, the binary [`BIN`] among them. Nothing of a
/// header but the name, the size, the type and the binary's execute bit is
/// used. Returns the names written.
fn untar(src: &mut impl Read, dir: &Path) -> Result<Vec<String>, String> {
    let mut names: Vec<String> = Vec::new();
    let mut header = [0u8; 512];
    loop {
        let got = read_full(src, &mut header).map_err(|e| format!("archive: {e}"))?;
        if got == 0 {
            return Err("archive: it ends without an end mark".into());
        }
        if got != 512 {
            return Err("archive: cut off in a header".into());
        }
        if header.iter().all(|b| *b == 0) {
            break;
        }
        // the checksum: the sum of the header with its own field as spaces
        let want = octal(&header[148..156]).ok_or("archive: bad header checksum")?;
        let sum: u64 = header
            .iter()
            .enumerate()
            .map(|(i, b)| {
                if (148..156).contains(&i) {
                    u64::from(b' ')
                } else {
                    u64::from(*b)
                }
            })
            .sum();
        if sum != want {
            return Err("archive: bad header checksum".into());
        }
        let name_raw: Vec<u8> = header[..100].iter().copied().take_while(|b| *b != 0).collect();
        let name = String::from_utf8(name_raw).map_err(|_| "archive: a name is not UTF-8")?;
        let shown: String = name.chars().take(64).collect();
        // ustar's prefix field: a longer path, never ours
        if header[345] != 0 {
            return Err(format!("archive: entry {shown:?}: a path, not a plain name"));
        }
        match header[156] {
            0 | b'0' => {}
            b'1' => return Err(format!("archive: entry {shown:?} is a hard link")),
            b'2' => return Err(format!("archive: entry {shown:?} is a symbolic link")),
            b'3' | b'4' | b'6' => {
                return Err(format!("archive: entry {shown:?} is a device or a pipe"))
            }
            b'5' => return Err(format!("archive: entry {shown:?} is a directory")),
            t => {
                return Err(format!(
                    "archive: entry {shown:?} has type {:?}: plain files only",
                    t as char
                ))
            }
        }
        let name = name.strip_prefix("./").unwrap_or(&name).to_owned();
        if !plain_name(&name, 64) {
            return Err(format!(
                "archive: entry {shown:?}: not a plain file name (no directories, no `..`)"
            ));
        }
        if names.contains(&name) {
            return Err(format!("archive: entry {name} twice"));
        }
        if names.len() >= MAX_FILES {
            return Err(format!("archive: more than {MAX_FILES} files"));
        }
        let size = octal(&header[124..136]).ok_or("archive: bad size")?;
        let is_bin = name == BIN;
        let max = if is_bin { MAX_BINARY } else { MAX_EXTRA };
        if size > max {
            return Err(format!(
                "archive: {name} has {size} bytes, more than {max}"
            ));
        }
        let mode = octal(&header[100..108]).unwrap_or(0);
        if is_bin && (size == 0 || mode & 0o100 == 0) {
            return Err(format!("archive: {BIN} is not an executable file"));
        }
        // the mode is the broker's: 0755 for the binary, 0644 for the rest
        let path = dir.join(&name);
        let mut out =
            new_file(&path, if is_bin { 0o755 } else { 0o644 }).map_err(|e| io(&path, e))?;
        let mut left = size;
        let mut buf = vec![0u8; 1 << 16];
        while left > 0 {
            let want = left.min(buf.len() as u64) as usize;
            let n = read_full(src, &mut buf[..want]).map_err(|e| format!("archive: {e}"))?;
            if n != want {
                return Err(format!("archive: cut off in {name}"));
            }
            out.write_all(&buf[..n]).map_err(|e| io(&path, e))?;
            left -= n as u64;
        }
        out.sync_all().map_err(|e| io(&path, e))?;
        let pad = (512 - (size % 512)) % 512;
        if pad > 0 {
            let n = read_full(src, &mut buf[..pad as usize]).map_err(|e| format!("archive: {e}"))?;
            if n as u64 != pad {
                return Err(format!("archive: cut off after {name}"));
            }
        }
        names.push(name);
    }
    // after the end mark: zero blocks only
    let mut rest = 0usize;
    let mut buf = vec![0u8; 1 << 14];
    loop {
        let n = src.read(&mut buf).map_err(|e| format!("archive: {e}"))?;
        if n == 0 {
            break;
        }
        rest += n;
        if rest > 1 << 20 || buf[..n].iter().any(|b| *b != 0) {
            return Err("archive: data after its end".into());
        }
    }
    if !names.iter().any(|n| n == BIN) {
        return Err(format!("archive: no {BIN} in it"));
    }
    Ok(names)
}

/// Check `archive` against `asset` (size and SHA-256, before anything is
/// unpacked) and unpack it as `<versions>/<version>`. The files go into a
/// new directory `<versions>/.<version>.part`, each created new, and the
/// directory is renamed into place once all of it is on disk. A directory of
/// that version that exists already is replaced: the caller makes sure it
/// is not the one that runs. Returns the binary's path.
pub fn unpack(
    archive: &Path,
    asset: &Asset,
    versions: &Path,
    version: &str,
) -> Result<PathBuf, String> {
    check_version(version)?;
    let (sha, size) = sha256_file(archive)?;
    if size != asset.size {
        return Err(format!(
            "the archive has {size} bytes, the release says {}",
            asset.size
        ));
    }
    if sha != asset.sha256 {
        return Err("the archive's SHA-256 is not the one of the release".into());
    }
    if size > MAX_ARCHIVE {
        return Err(format!("the archive has more than {MAX_ARCHIVE} bytes"));
    }
    std::fs::create_dir_all(versions).map_err(|e| io(versions, e))?;
    let part = versions.join(format!(".{version}.part"));
    if part.symlink_metadata().is_ok() {
        std::fs::remove_dir_all(&part)
            .or_else(|_| std::fs::remove_file(&part))
            .map_err(|e| io(&part, e))?;
    }
    new_dir(&part, 0o755).map_err(|e| io(&part, e))?;
    let unpacked = (|| {
        let f = std::fs::File::open(archive).map_err(|e| io(archive, e))?;
        // what the archive may unpack to, with room for the headers
        let limit = MAX_BINARY + (MAX_FILES as u64) * (MAX_EXTRA + 1024) + (2 << 20);
        let mut gz = flate2::read::GzDecoder::new(f).take(limit);
        untar(&mut gz, &part)
    })();
    if let Err(e) = unpacked {
        let _ = std::fs::remove_dir_all(&part);
        return Err(e);
    }
    sync_dir(&part);
    let dest = versions.join(version);
    if dest.symlink_metadata().is_ok() {
        std::fs::remove_dir_all(&dest)
            .or_else(|_| std::fs::remove_file(&dest))
            .map_err(|e| io(&dest, e))?;
    }
    std::fs::rename(&part, &dest).map_err(|e| io(&dest, e))?;
    sync_dir(versions);
    Ok(dest.join(BIN))
}

/// The install layout of a broker that updates itself.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Layout {
    pub prefix: PathBuf,
}

const LAYOUT_HELP: &str = "docs/operations.md §2 \"A broker that updates itself\"";

impl Layout {
    pub fn versions(&self) -> PathBuf {
        self.prefix.join("versions")
    }

    pub fn current(&self) -> PathBuf {
        self.prefix.join("current")
    }

    pub fn guard(&self) -> PathBuf {
        self.prefix.join("bin").join(GUARD)
    }

    pub fn bin_of(&self, version: &str) -> PathBuf {
        self.versions().join(version).join(BIN)
    }

    /// The version `current` points at.
    pub fn current_version(&self) -> Option<String> {
        let t = std::fs::read_link(self.current()).ok()?;
        let mut parts = t.components();
        match (parts.next(), parts.next(), parts.next()) {
            (
                Some(std::path::Component::Normal(a)),
                Some(std::path::Component::Normal(v)),
                None,
            ) if a == "versions" => v.to_str().map(str::to_owned),
            _ => None,
        }
    }

    /// The layout a running broker sits in: `exe` (its own binary) must be
    /// `<prefix>/versions/<version>/wyrmd`, `<prefix>/current` the link to
    /// that version and `<prefix>/bin/wyrmd-guard` a file. `Err` says what
    /// is missing.
    pub fn of_broker(exe: &Path, version: &str) -> Result<Self, String> {
        if !cfg!(unix) {
            return Err("updates.mode \"self\" works on Linux and macOS only".into());
        }
        let exe = exe.canonicalize().map_err(|e| io(exe, e))?;
        let wrong = || {
            format!(
                "updates.mode \"self\": this broker runs {}, not \
                 <prefix>/versions/{version}/{BIN} ({LAYOUT_HELP}; `wyrmd install-layout <prefix>` makes it)",
                exe.display()
            )
        };
        if exe.file_name().and_then(|n| n.to_str()) != Some(BIN) {
            return Err(wrong());
        }
        let vdir = exe.parent().ok_or_else(wrong)?;
        if vdir.file_name().and_then(|n| n.to_str()) != Some(version) {
            return Err(wrong());
        }
        let versions = vdir.parent().ok_or_else(wrong)?;
        if versions.file_name().and_then(|n| n.to_str()) != Some("versions") {
            return Err(wrong());
        }
        let l = Self {
            prefix: versions.parent().ok_or_else(wrong)?.to_owned(),
        };
        let is_link = l
            .current()
            .symlink_metadata()
            .is_ok_and(|m| m.file_type().is_symlink());
        if !is_link || l.current_version().as_deref() != Some(version) {
            return Err(format!(
                "updates.mode \"self\": {} is not a symbolic link to versions/{version} ({LAYOUT_HELP})",
                l.current().display()
            ));
        }
        let guard_ok = l
            .guard()
            .symlink_metadata()
            .is_ok_and(|m| m.file_type().is_file());
        if !guard_ok {
            return Err(format!(
                "updates.mode \"self\": no guard at {} ({LAYOUT_HELP})",
                l.guard().display()
            ));
        }
        Ok(l)
    }

    /// The layout of a guard: `exe` is `<prefix>/bin/wyrmd-guard`.
    pub fn of_guard(exe: &Path) -> Result<Self, String> {
        let exe = exe.canonicalize().map_err(|e| io(exe, e))?;
        let bin = exe.parent().filter(|_| {
            exe.file_name().and_then(|n| n.to_str()) == Some(GUARD)
        });
        match bin {
            Some(b) if b.file_name().and_then(|n| n.to_str()) == Some("bin") => Ok(Self {
                prefix: b
                    .parent()
                    .ok_or_else(|| format!("{}: no prefix", exe.display()))?
                    .to_owned(),
            }),
            _ => Err(format!(
                "{}: the guard runs as <prefix>/bin/{GUARD}",
                exe.display()
            )),
        }
    }

    /// Point `current` at `versions/<version>`: a new symbolic link beside
    /// it, renamed over it. A reader sees the old target or the new one.
    pub fn switch(&self, version: &str) -> Result<(), String> {
        check_version(version)?;
        if !self.bin_of(version).is_file() {
            return Err(format!(
                "{}: no such version",
                self.bin_of(version).display()
            ));
        }
        #[cfg(unix)]
        {
            let tmp = self.prefix.join(".current.new");
            if tmp.symlink_metadata().is_ok() {
                std::fs::remove_file(&tmp).map_err(|e| io(&tmp, e))?;
            }
            let target = Path::new("versions").join(version);
            std::os::unix::fs::symlink(&target, &tmp).map_err(|e| io(&tmp, e))?;
            let cur = self.current();
            std::fs::rename(&tmp, &cur).map_err(|e| io(&cur, e))?;
            sync_dir(&self.prefix);
            Ok(())
        }
        #[cfg(not(unix))]
        Err("updates.mode \"self\" works on Linux and macOS only".into())
    }

    /// Make `bin/wyrmd-guard` a copy of `from`: written new beside it, then
    /// renamed over it.
    pub fn refresh_guard(&self, from: &Path) -> Result<(), String> {
        let guard = self.guard();
        let dir = guard.parent().unwrap_or(&self.prefix).to_owned();
        std::fs::create_dir_all(&dir).map_err(|e| io(&dir, e))?;
        let tmp = dir.join(format!(".{GUARD}.new"));
        if tmp.symlink_metadata().is_ok() {
            std::fs::remove_file(&tmp).map_err(|e| io(&tmp, e))?;
        }
        let mut src = std::fs::File::open(from).map_err(|e| io(from, e))?;
        let mut out = new_file(&tmp, 0o755).map_err(|e| io(&tmp, e))?;
        std::io::copy(&mut src, &mut out).map_err(|e| io(&tmp, e))?;
        out.sync_all().map_err(|e| io(&tmp, e))?;
        drop(out);
        std::fs::rename(&tmp, &guard).map_err(|e| io(&guard, e))?;
        sync_dir(&dir);
        Ok(())
    }

    /// Is the guard the same file as `bin`?
    pub fn guard_is(&self, bin: &Path) -> bool {
        match (sha256_file(&self.guard()), sha256_file(bin)) {
            (Ok(a), Ok(b)) => a == b,
            _ => false,
        }
    }

    /// Make the layout in `prefix` from the binary `exe` of `version`
    /// (`wyrmd install-layout`): the version directory, `current`, the
    /// guard. An existing version directory of that name must hold the same
    /// binary.
    pub fn install(prefix: &Path, exe: &Path, version: &str) -> Result<Self, String> {
        check_version(version)?;
        if !cfg!(unix) {
            return Err("the layout of a self-updating broker needs Linux or macOS".into());
        }
        std::fs::create_dir_all(prefix).map_err(|e| io(prefix, e))?;
        let l = Self {
            prefix: prefix.canonicalize().map_err(|e| io(prefix, e))?,
        };
        let vdir = l.versions().join(version);
        let bin = vdir.join(BIN);
        if bin.is_file() {
            if sha256_file(&bin)? != sha256_file(exe)? {
                return Err(format!(
                    "{}: another binary of version {version} is there",
                    bin.display()
                ));
            }
        } else {
            std::fs::create_dir_all(&vdir).map_err(|e| io(&vdir, e))?;
            let mut src = std::fs::File::open(exe).map_err(|e| io(exe, e))?;
            let mut out = new_file(&bin, 0o755).map_err(|e| io(&bin, e))?;
            std::io::copy(&mut src, &mut out).map_err(|e| io(&bin, e))?;
            out.sync_all().map_err(|e| io(&bin, e))?;
        }
        l.switch(version)?;
        l.refresh_guard(&bin)?;
        Ok(l)
    }

    /// Remove every version directory but `keep`, and what an unpack left
    /// half done. Returns the versions removed.
    pub fn prune(&self, keep: &[&str]) -> Vec<String> {
        let mut gone = Vec::new();
        for e in std::fs::read_dir(self.versions())
            .into_iter()
            .flatten()
            .flatten()
        {
            let name = e.file_name().to_string_lossy().into_owned();
            let part = name.starts_with('.') && name.ends_with(".part");
            if part || (check_version(&name).is_ok() && !keep.contains(&name.as_str())) {
                let p = e.path();
                if std::fs::remove_dir_all(&p)
                    .or_else(|_| std::fs::remove_file(&p))
                    .is_ok()
                    && !part
                {
                    gone.push(name);
                }
            }
        }
        gone
    }
}

/// `data_dir/update.json`: one update of the broker, from the moment the old
/// version commits to it.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct UpdateFile {
    pub from: String,
    pub to: String,
    /// `trial`, `confirmed`, `rolled_back`, `failed` (it could not be rolled
    /// back; the new version runs unproven).
    pub state: String,
    /// Starts of the new version in its trial.
    #[serde(default)]
    pub attempts: u32,
    /// Unix seconds: the trial ends; the new version is judged then.
    #[serde(default)]
    pub deadline: u64,
    /// The pre-update backup: its job id, file name in `data_dir/backups`
    /// and SHA-256. Empty on a standby (it follows; it has nothing to
    /// restore).
    #[serde(default)]
    pub backup_id: String,
    #[serde(default)]
    pub backup: String,
    #[serde(default)]
    pub backup_sha256: String,
    #[serde(default)]
    pub from_schemas: BTreeMap<String, u32>,
    #[serde(default)]
    pub to_schemas: BTreeMap<String, u32>,
    /// Links that were connected when the update began: the new version
    /// must have them back.
    #[serde(default)]
    pub links: Vec<String>,
    /// Who asked for it.
    #[serde(default)]
    pub by: String,
    /// Unix seconds: the old version stopped for it.
    #[serde(default)]
    pub started: u64,
    /// Why the new version gave its trial up (it then exits with
    /// [`TRIAL_EXIT`]); empty otherwise.
    #[serde(default)]
    pub failed: String,
    /// Who asked for a rollback of a confirmed update
    /// (`sys/~act/rollback_update`); the guard does it at the next start.
    #[serde(default)]
    pub rollback: String,
    /// Why it was rolled back, or could not be.
    #[serde(default)]
    pub reason: String,
    /// Unix seconds: confirmed or rolled back.
    #[serde(default)]
    pub ended: u64,
    /// Unix seconds: until then a confirmed update can be rolled back (the
    /// old version and the pre-update backup are kept).
    #[serde(default)]
    pub keep_until: u64,
    /// The control plane was restored from the pre-update backup.
    #[serde(default)]
    pub restored: bool,
    /// The version that runs now has written the audit record of `state`.
    #[serde(default)]
    pub audited: bool,
    /// `active`, or `standby` (the broker updated while it follows).
    #[serde(default)]
    pub role: String,
    /// Seconds the site was without its broker (stop to router up).
    #[serde(default)]
    pub without_s: u64,
}

impl UpdateFile {
    pub fn load(data_dir: &Path) -> Option<Self> {
        let bytes = std::fs::read(data_dir.join(STATE_FILE)).ok()?;
        if bytes.len() > 1 << 20 {
            return None;
        }
        serde_json::from_slice(&bytes).ok()
    }

    /// Written beside the file and renamed over it.
    pub fn save(&self, data_dir: &Path) -> Result<(), String> {
        let path = data_dir.join(STATE_FILE);
        let bytes = serde_json::to_vec_pretty(self).map_err(|e| e.to_string())?;
        crate::secret::write_private(&path, &bytes).map_err(|e| io(&path, e))?;
        sync_dir(data_dir);
        Ok(())
    }

    pub fn in_trial(&self) -> bool {
        self.state == "trial"
    }

    /// The stores whose SCHEMA the update moved.
    pub fn moved(&self) -> Vec<String> {
        moved(&self.from_schemas, &self.to_schemas)
    }
}

/// Unix seconds now.
pub fn now_s() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |d| d.as_secs())
}

/// Note that the guard ran (`data_dir/update.guard`): a broker in
/// `updates.mode: "self"` updates only when the guard ran before it started.
pub fn stamp_guard(data_dir: &Path, version: &str) {
    if !data_dir.is_dir() {
        return;
    }
    let v = serde_json::json!({ "at": now_s(), "version": version });
    let _ = crate::secret::write_private(&data_dir.join(GUARD_STAMP), v.to_string().as_bytes());
}

/// When the guard ran last (unix seconds).
pub fn guard_stamp(data_dir: &Path) -> Option<u64> {
    let bytes = std::fs::read(data_dir.join(GUARD_STAMP)).ok()?;
    let v: serde_json::Value = serde_json::from_slice(&bytes).ok()?;
    v.get("at")?.as_u64()
}

/// What the guard did.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Guarded {
    /// No update in its trial, or the trial goes on.
    Nothing,
    /// `current` points at the old version again.
    RolledBack { from: String, to: String, restored: bool },
    /// A rollback was due and cannot be done: the new version stays.
    Stuck(String),
}

/// `wyrmd update-guard`: run before every start of the broker, by the
/// previous version's binary (`<prefix>/bin/wyrmd-guard`). With an update
/// in its trial that failed (the new version said so, started
/// [`MAX_ATTEMPTS`] times, or its time is over), or with a rollback asked
/// for on purpose, it restores the control plane from the pre-update backup
/// where the update moved a SCHEMA, points `current` back at the old
/// version and writes `rolled_back`. `Err`: a step failed and the next run
/// does it again.
pub fn guard(layout: &Layout, data_dir: &Path, version: &str) -> Result<Guarded, String> {
    stamp_guard(data_dir, version);
    let Some(mut u) = UpdateFile::load(data_dir) else {
        return Ok(Guarded::Nothing);
    };
    let now = now_s();
    if u.state == "trial" && layout.current_version().as_deref() == Some(u.from.as_str()) {
        // the old version stopped before `current` moved: nothing ran
        u.state = "rolled_back".into();
        u.reason = format!("the broker stopped before wyrmd {} was made current", u.to);
        u.ended = now;
        u.audited = false;
        u.save(data_dir)?;
        return Ok(Guarded::RolledBack {
            from: u.from,
            to: u.to,
            restored: false,
        });
    }
    let why = if u.state == "trial" {
        if !u.failed.is_empty() {
            Some(format!("wyrmd {} gave its trial up: {}", u.to, u.failed))
        } else if u.attempts >= MAX_ATTEMPTS {
            Some(format!(
                "wyrmd {} started {} times and never ended its trial",
                u.to, u.attempts
            ))
        } else if now > u.deadline {
            Some(format!(
                "wyrmd {} did not end its trial in time (it was not running at the end)",
                u.to
            ))
        } else {
            None
        }
    } else if u.state == "confirmed" && !u.rollback.is_empty() && now <= u.keep_until {
        Some(format!("rolled back by {}", u.rollback))
    } else {
        None
    };
    let Some(why) = why else {
        return Ok(Guarded::Nothing);
    };
    let stuck = |u: &mut UpdateFile, what: String| -> Result<Guarded, String> {
        u.state = "failed".into();
        u.reason = format!("{why}; not rolled back: {what}");
        u.ended = now;
        u.audited = false;
        u.rollback.clear();
        u.save(data_dir)?;
        Ok(Guarded::Stuck(u.reason.clone()))
    };
    if check_version(&u.from).is_err() || !layout.bin_of(&u.from).is_file() {
        let what = format!("{} is gone", layout.bin_of(&u.from).display());
        return stuck(&mut u, what);
    }
    let moved = u.moved();
    let mut restored = false;
    if !moved.is_empty() && u.role != "standby" {
        let backup = data_dir.join("backups").join(&u.backup);
        let usable = !u.backup.is_empty()
            && plain_name(&u.backup, 200)
            && sha256_file(&backup).is_ok_and(|(sha, _)| sha == u.backup_sha256);
        if !usable {
            let what = format!(
                "the update moved the SCHEMA of {} and the pre-update backup {} is gone or changed",
                moved.join(", "),
                u.backup
            );
            return stuck(&mut u, what);
        }
        restore_control(data_dir, &backup, &moved)
            .map_err(|e| format!("pre-update backup {}: {e}", u.backup))?;
        restored = true;
    }
    layout.switch(&u.from)?;
    u.state = "rolled_back".into();
    u.reason = why;
    u.ended = now;
    u.restored = restored;
    u.audited = false;
    u.rollback.clear();
    u.save(data_dir)?;
    Ok(Guarded::RolledBack {
        from: u.from,
        to: u.to,
        restored,
    })
}

/// The control-plane WAL stores: name in `schemas`, directory in a backup's
/// `control` section, directory under `data_dir`.
const CONTROL_STORES: [(&str, &str, &str); 4] = [
    ("registry", "state", "state"),
    ("flows", "flows", "flows/state"),
    ("users", "users", "gateway/users"),
    ("audit", "audit", "audit"),
];

/// Put the WALs of `stores` (names of `schemas`) back from the `control`
/// section of the broker backup at `backup`, with the broker stopped. The
/// files are read whole (size and SHA-256 of the manifest) into
/// `data_dir/update.restore` first; then each store's directory is moved
/// aside into `data_dir/update.aside` and replaced. A run that stopped
/// halfway is done again from the start by the next one.
pub fn restore_control(data_dir: &Path, backup: &Path, stores: &[String]) -> Result<(), String> {
    use crate::backup as format;
    let mut r = format::Reader::open(backup, 8 << 30)?;
    if r.manifest().kind != format::Kind::Broker {
        return Err("not a broker backup".into());
    }
    let listed: Vec<String> = r
        .manifest()
        .section("control")
        .ok_or("the backup has no control section")?
        .files
        .iter()
        .map(|f| f.path.clone())
        .collect();
    let stage = data_dir.join("update.restore");
    if stage.symlink_metadata().is_ok() {
        std::fs::remove_dir_all(&stage).map_err(|e| io(&stage, e))?;
    }
    new_dir(&stage, 0o700).map_err(|e| io(&stage, e))?;
    let mut swaps = Vec::new();
    for store in stores {
        let (_, name, dir) = CONTROL_STORES
            .iter()
            .find(|(schema, _, _)| schema == store)
            .ok_or_else(|| format!("{store}: not a control-plane store"))?;
        let prefix = format!("control/{name}/");
        let mut n = 0;
        for path in listed.iter().filter(|p| p.starts_with(&prefix)) {
            let file = &path[prefix.len()..];
            if !plain_name(file, 128) {
                return Err(format!("{path}: not a file of a WAL store"));
            }
            r.extract(path, &stage.join(name).join(file), None)?;
            n += 1;
        }
        if n == 0 {
            return Err(format!("the backup does not hold the store {store}"));
        }
        swaps.push((*name, *dir));
    }
    let aside = data_dir.join("update.aside");
    if aside.symlink_metadata().is_ok() {
        std::fs::remove_dir_all(&aside).map_err(|e| io(&aside, e))?;
    }
    new_dir(&aside, 0o700).map_err(|e| io(&aside, e))?;
    for (name, dir) in swaps {
        let live = data_dir.join(dir);
        if live.symlink_metadata().is_ok() {
            let to = aside.join(name);
            std::fs::rename(&live, &to).map_err(|e| io(&live, e))?;
        } else if let Some(parent) = live.parent() {
            std::fs::create_dir_all(parent).map_err(|e| io(parent, e))?;
        }
        std::fs::rename(stage.join(name), &live).map_err(|e| io(&live, e))?;
        if let Some(parent) = live.parent() {
            sync_dir(parent);
        }
    }
    let _ = std::fs::remove_dir_all(&stage);
    Ok(())
}

/// Run `bin` with `args` and nothing of this process's environment, and
/// wait at most `timeout`: its standard output when it exits with 0, else
/// the end of what it wrote. No shell is involved.
pub async fn run_binary(
    bin: &Path,
    args: &[std::ffi::OsString],
    timeout: std::time::Duration,
) -> Result<String, String> {
    let mut cmd = tokio::process::Command::new(bin);
    cmd.args(args)
        .env_clear()
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .kill_on_drop(true);
    let child = cmd.spawn().map_err(|e| io(bin, e))?;
    let out = tokio::time::timeout(timeout, child.wait_with_output())
        .await
        .map_err(|_| format!("{}: no answer in {} s", bin.display(), timeout.as_secs()))?
        .map_err(|e| io(bin, e))?;
    let tail = |b: &[u8]| {
        let s = String::from_utf8_lossy(b);
        let s = s.trim();
        let start = s
            .char_indices()
            .rev()
            .nth(799)
            .map_or(0, |(i, _)| i);
        s[start..].to_owned()
    };
    if out.status.success() {
        Ok(String::from_utf8_lossy(&out.stdout).into_owned())
    } else {
        let said = tail(&out.stderr);
        let said = if said.is_empty() {
            tail(&out.stdout)
        } else {
            said
        };
        Err(format!("{} ({}): {said}", bin.display(), out.status))
    }
}

/// Test helpers: archives and keys, also for the e2e tests of `wyrmd`.
pub mod testkit {
    use super::*;

    /// One tar entry: a header and the padded data.
    pub fn tar_entry(name: &str, kind: u8, mode: u32, data: &[u8]) -> Vec<u8> {
        let mut h = [0u8; 512];
        h[..name.len().min(100)].copy_from_slice(&name.as_bytes()[..name.len().min(100)]);
        h[100..108].copy_from_slice(format!("{mode:07o}\0").as_bytes());
        h[108..116].copy_from_slice(b"0000000\0");
        h[116..124].copy_from_slice(b"0000000\0");
        h[124..136].copy_from_slice(format!("{:011o}\0", data.len()).as_bytes());
        h[136..148].copy_from_slice(b"00000000000\0");
        h[148..156].copy_from_slice(b"        ");
        h[156] = kind;
        h[257..263].copy_from_slice(b"ustar\0");
        h[263..265].copy_from_slice(b"00");
        let sum: u32 = h.iter().map(|b| u32::from(*b)).sum();
        h[148..156].copy_from_slice(format!("{sum:06o}\0 ").as_bytes());
        let mut out = h.to_vec();
        out.extend_from_slice(data);
        out.resize(out.len() + (512 - data.len() % 512) % 512, 0);
        out
    }

    /// A `.tar.gz` of `entries` (already made with [`tar_entry`]) with the
    /// end mark.
    pub fn tar_gz(entries: &[Vec<u8>]) -> Vec<u8> {
        let mut tar: Vec<u8> = entries.concat();
        tar.extend_from_slice(&[0u8; 1024]);
        let mut gz = flate2::write::GzEncoder::new(Vec::new(), flate2::Compression::fast());
        gz.write_all(&tar).expect("gzip in memory");
        gz.finish().expect("gzip in memory")
    }

    /// Write the archive of the binary at `bin` to `out`, streamed; its
    /// asset (file name, SHA-256, size).
    pub fn archive_of(bin: &Path, out: &Path) -> Result<Asset, String> {
        let size = std::fs::metadata(bin).map_err(|e| io(bin, e))?.len();
        let header = &tar_entry(BIN, b'0', 0o755, &[])[..512];
        // the header of an empty file, with the real size and a new checksum
        let mut h = header.to_vec();
        h[124..136].copy_from_slice(format!("{size:011o}\0").as_bytes());
        h[148..156].copy_from_slice(b"        ");
        let sum: u32 = h.iter().map(|b| u32::from(*b)).sum();
        h[148..156].copy_from_slice(format!("{sum:06o}\0 ").as_bytes());
        let f = std::fs::File::create(out).map_err(|e| io(out, e))?;
        let mut gz = flate2::write::GzEncoder::new(f, flate2::Compression::fast());
        let werr = |e: std::io::Error| io(out, e);
        gz.write_all(&h).map_err(werr)?;
        let mut src = std::fs::File::open(bin).map_err(|e| io(bin, e))?;
        std::io::copy(&mut src, &mut gz).map_err(werr)?;
        let pad = (512 - size % 512) % 512;
        gz.write_all(&vec![0u8; pad as usize + 1024]).map_err(werr)?;
        gz.finish().map_err(werr)?.sync_all().map_err(werr)?;
        let (sha256, size) = sha256_file(out)?;
        Ok(Asset {
            file: out
                .file_name()
                .map(|n| n.to_string_lossy().into_owned())
                .unwrap_or_default(),
            sha256,
            size,
            url: String::new(),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::testkit::{tar_entry, tar_gz};
    use super::*;

    fn scratch(name: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("wyrm-release-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        d
    }

    fn key(n: u8) -> SigningKey {
        SigningKey::from_bytes(&[n; 32])
    }

    fn me() -> Identity {
        Identity {
            version: "0.1.0".into(),
            target: "x86_64-linux".into(),
            schemas: BTreeMap::from([("registry".into(), 19), ("audit".into(), 1)]),
            replication: 1,
        }
    }

    fn release(version: &str) -> Release {
        Release {
            wyrmd_release: FORMAT,
            version: version.into(),
            date: "2026-11-13".into(),
            notes: String::new(),
            min_from: String::new(),
            schemas: me().schemas,
            replication: 1,
            targets: BTreeMap::from([(
                "x86_64-linux".to_owned(),
                Asset {
                    file: format!("wyrmd-{version}-x86_64-linux.tar.gz"),
                    sha256: "a".repeat(64),
                    size: 10,
                    url: String::new(),
                },
            )]),
        }
    }

    /// Put `bytes` in a file and name it as an asset.
    fn asset_of(dir: &Path, bytes: &[u8]) -> (PathBuf, Asset) {
        let path = dir.join("a.tar.gz");
        std::fs::write(&path, bytes).unwrap();
        let (sha256, size) = sha256_file(&path).unwrap();
        (
            path,
            Asset {
                file: "a.tar.gz".into(),
                sha256,
                size,
                url: String::new(),
            },
        )
    }

    #[test]
    fn a_release_is_read_only_under_a_pinned_key() {
        let bytes = serde_json::to_vec(&release("0.2.0")).unwrap();
        let sig = sign_release(&bytes, &key(1));
        let pinned = [key(1).verifying_key()];
        assert_eq!(read_release(&bytes, &sig, &pinned).unwrap().version, "0.2.0");
        // another key signed it
        let err = read_release(&bytes, &sign_release(&bytes, &key(2)), &pinned).unwrap_err();
        assert!(err.contains("pinned release key"), "{err}");
        // one byte changed after signing
        let mut changed = bytes.clone();
        let at = changed.iter().position(|b| *b == b'2').unwrap();
        changed[at] = b'9';
        assert!(read_release(&changed, &sig, &pinned).is_err());
        // a signature of the index domain does not sign a release
        let err = read_release(&bytes, &sign_index(&bytes, &key(1)), &pinned).unwrap_err();
        assert!(err.contains("pinned release key"), "{err}");
        // no key pinned: nothing is trusted, whatever the document says
        let err = read_release(&bytes, &sig, &[]).unwrap_err();
        assert!(err.contains("no release key is pinned"), "{err}");
        // not a signature
        assert!(read_release(&bytes, "zz", &pinned).is_err());
        assert!(read_release(&bytes, "", &pinned).is_err());
        // several lines: one good one is enough (a key being rotated)
        let two = format!("{}\n{sig}\n", sign_release(&bytes, &key(2)));
        assert!(read_release(&bytes, &two, &pinned).is_ok());
        // too large, before the signature is looked at
        let big = vec![b' '; MAX_RELEASE + 1];
        assert!(read_release(&big, &sig, &pinned)
            .unwrap_err()
            .contains("more than"));
    }

    #[test]
    fn an_index_names_the_latest_build_of_a_target() {
        let mut other = release("0.9.0");
        other.targets = BTreeMap::from([(
            "aarch64-linux".to_owned(),
            other.targets["x86_64-linux"].clone(),
        )]);
        let index = Index {
            wyrmd_releases: FORMAT,
            releases: vec![release("0.2.0"), release("0.10.0"), release("0.3.0"), other],
        };
        let bytes = serde_json::to_vec(&index).unwrap();
        let pinned = [key(1).verifying_key()];
        let read = read_index(&bytes, &sign_index(&bytes, &key(1)), &pinned).unwrap();
        assert_eq!(read.latest("x86_64-linux").unwrap().version, "0.10.0");
        assert_eq!(read.latest("aarch64-linux").unwrap().version, "0.9.0");
        assert!(read.latest("riscv64-linux").is_none());
        assert!(read_index(&bytes, &sign_release(&bytes, &key(1)), &pinned).is_err());
    }

    #[test]
    fn release_documents_are_bounded() {
        let bad = |f: &dyn Fn(&mut Release)| {
            let mut r = release("0.2.0");
            f(&mut r);
            r.check().unwrap_err()
        };
        assert!(bad(&|r| r.wyrmd_release = 2).contains("format"));
        assert!(bad(&|r| r.version = "../0.2.0".into()).contains("version"));
        assert!(bad(&|r| r.version = "0.2/x".into()).contains("version"));
        assert!(bad(&|r| r.version = "1x".into()).contains("dotted"));
        assert!(bad(&|r| r.notes = "http://x".into()).contains("https"));
        assert!(bad(&|r| r.targets.clear()).contains("targets"));
        let t = "x86_64-linux";
        assert!(bad(&|r| r.targets.get_mut(t).unwrap().file = "../x.tar.gz".into()).contains("file"));
        assert!(bad(&|r| r.targets.get_mut(t).unwrap().file = "x.zip".into()).contains("file"));
        assert!(bad(&|r| r.targets.get_mut(t).unwrap().sha256 = "A".repeat(64)).contains("sha256"));
        assert!(bad(&|r| r.targets.get_mut(t).unwrap().size = MAX_ARCHIVE + 1).contains("size"));
        assert!(bad(&|r| r.targets.get_mut(t).unwrap().size = 0).contains("size"));
        assert!(
            bad(&|r| r.targets.get_mut(t).unwrap().url = "http://h/x.tar.gz".into())
                .contains("https")
        );
    }

    #[test]
    fn an_update_never_goes_down_and_never_below_the_schema() {
        let me = me();
        assert!(release("0.2.0").compatible(&me).is_ok());
        // the same and an older version
        let err = release("0.1.0").compatible(&me).unwrap_err();
        assert!(err.contains("never goes down"), "{err}");
        let err = release("0.0.9").compatible(&me).unwrap_err();
        assert!(err.contains("never goes down"), "{err}");
        // a pre-release of what runs is older
        assert!(release("0.1.0-rc1").compatible(&me).is_err());
        // no build for this host
        let mut arm = me.clone();
        arm.target = "aarch64-linux".into();
        assert!(release("0.2.0")
            .compatible(&arm)
            .unwrap_err()
            .contains("no build"));
        // too old to start from
        let mut r = release("0.5.0");
        r.min_from = "0.3.0".into();
        let err = r.compatible(&me).unwrap_err();
        assert!(err.contains("update to 0.3.0 first"), "{err}");
        r.min_from = "0.1.0".into();
        assert!(r.compatible(&me).is_ok());
        // a newer version that writes an older SCHEMA
        let mut r = release("0.2.0");
        r.schemas.insert("registry".into(), 18);
        let err = r.compatible(&me).unwrap_err();
        assert!(err.contains("older SCHEMA"), "{err}");
        // or does not say
        let mut r = release("0.2.0");
        r.schemas.remove("audit");
        assert!(r.compatible(&me).unwrap_err().contains("does not name"));
        // a SCHEMA that moves up is fine and is named
        let mut r = release("0.2.0");
        r.schemas.insert("registry".into(), 20);
        assert!(r.compatible(&me).is_ok());
        assert_eq!(r.moves(&me), ["registry"]);
        assert!(release("0.2.0").moves(&me).is_empty());
    }

    #[test]
    fn versions_compare_as_numbers() {
        assert!(newer("0.10.0", "0.9.2"));
        assert!(!newer("0.9.2", "0.10.0"));
        assert!(newer("1.0.0", "1.0.0-rc1"));
        assert!(!newer("1.0.0-rc1", "1.0.0"));
        assert!(!newer("1.0.0+b2", "1.0.0+b1"));
        assert!(!newer("abc", "0.1.0"), "not dotted numbers: never newer");
        assert!(check_version("0.2.0-rc1+b3").is_ok());
        for bad in ["", ".", "..", "a", "0/1", "0..1", "0 1", "-1"] {
            assert!(check_version(bad).is_err(), "{bad:?}");
        }
    }

    #[test]
    fn an_archive_is_unpacked_into_a_new_version_directory() {
        let d = scratch("unpack");
        let gz = tar_gz(&[
            tar_entry("./wyrmd", b'0', 0o700, b"#!/bin/sh\nexit 0\n"),
            tar_entry("LICENSE", b'0', 0o777, b"Apache-2.0"),
        ]);
        let (path, asset) = asset_of(&d, &gz);
        let versions = d.join("versions");
        let bin = unpack(&path, &asset, &versions, "0.2.0").unwrap();
        assert_eq!(bin, versions.join("0.2.0").join("wyrmd"));
        assert_eq!(std::fs::read(&bin).unwrap(), b"#!/bin/sh\nexit 0\n");
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mode = |p: &Path| std::fs::metadata(p).unwrap().permissions().mode() & 0o7777;
            // the broker's modes, not the archive's
            assert_eq!(mode(&bin) & 0o777 & !0o022, 0o755);
            assert_eq!(mode(&versions.join("0.2.0").join("LICENSE")) & 0o111, 0);
        }
        assert!(!versions.join(".0.2.0.part").exists());
        // again: the directory is replaced
        assert!(unpack(&path, &asset, &versions, "0.2.0").is_ok());
        let _ = std::fs::remove_dir_all(&d);
    }

    #[test]
    fn a_hostile_archive_is_refused_and_leaves_nothing() {
        let d = scratch("hostile");
        let versions = d.join("versions");
        let good = tar_entry("wyrmd", b'0', 0o755, b"binary");
        let refuse = |name: &str, entries: &[Vec<u8>], want: &str| {
            let (path, asset) = asset_of(&d, &tar_gz(entries));
            let err = unpack(&path, &asset, &versions, "0.2.0").unwrap_err();
            assert!(err.contains(want), "{name}: {err}");
            assert!(!versions.join("0.2.0").exists(), "{name}: a version is there");
            assert!(!versions.join(".0.2.0.part").exists(), "{name}: a part is left");
        };
        refuse(
            "traversal",
            &[good.clone(), tar_entry("../evil", b'0', 0o644, b"x")],
            "not a plain file name",
        );
        refuse(
            "absolute",
            &[good.clone(), tar_entry("/etc/cron.d/x", b'0', 0o644, b"x")],
            "not a plain file name",
        );
        refuse(
            "nested",
            &[good.clone(), tar_entry("a/b", b'0', 0o644, b"x")],
            "not a plain file name",
        );
        refuse(
            "hidden",
            &[good.clone(), tar_entry(".profile", b'0', 0o644, b"x")],
            "not a plain file name",
        );
        refuse(
            "symlink",
            &[good.clone(), tar_entry("link", b'2', 0o777, b"")],
            "symbolic link",
        );
        refuse(
            "symlink as the binary",
            &[tar_entry("wyrmd", b'2', 0o777, b"")],
            "symbolic link",
        );
        refuse(
            "hard link",
            &[good.clone(), tar_entry("hard", b'1', 0o644, b"")],
            "hard link",
        );
        refuse(
            "device",
            &[good.clone(), tar_entry("null", b'3', 0o644, b"")],
            "device",
        );
        refuse(
            "fifo",
            &[good.clone(), tar_entry("pipe", b'6', 0o644, b"")],
            "device or a pipe",
        );
        refuse(
            "directory",
            &[tar_entry("dir/", b'5', 0o755, b""), good.clone()],
            "directory",
        );
        refuse(
            "long name header",
            &[tar_entry("././@LongLink", b'L', 0o644, b"x"), good.clone()],
            "plain files only",
        );
        refuse("twice", &[good.clone(), good.clone()], "twice");
        refuse(
            "no binary",
            &[tar_entry("README", b'0', 0o644, b"x")],
            "no wyrmd",
        );
        refuse(
            "not executable",
            &[tar_entry("wyrmd", b'0', 0o644, b"binary")],
            "not an executable",
        );
        refuse(
            "oversized extra",
            &[
                good.clone(),
                tar_entry("big", b'0', 0o644, &vec![0u8; MAX_EXTRA as usize + 1]),
            ],
            "more than",
        );
        let many: Vec<Vec<u8>> = std::iter::once(good.clone())
            .chain((0..MAX_FILES).map(|i| tar_entry(&format!("f{i}"), b'0', 0o644, b"x")))
            .collect();
        refuse("too many", &many, "more than");
        // a header that claims more than is there
        let mut cut = tar_entry("wyrmd", b'0', 0o755, b"binary");
        cut.truncate(512 + 3);
        let (path, asset) = asset_of(&d, &{
            let mut gz = flate2::write::GzEncoder::new(Vec::new(), flate2::Compression::fast());
            gz.write_all(&cut).unwrap();
            gz.finish().unwrap()
        });
        assert!(unpack(&path, &asset, &versions, "0.2.0")
            .unwrap_err()
            .contains("cut off"));
        // a header with a broken checksum
        let mut broken = good.clone();
        broken[0] = b'x';
        refuse("checksum", &[broken], "checksum");
        // data after the end
        let mut tail = tar_gz(&[good.clone()]);
        let mut gz = flate2::write::GzEncoder::new(Vec::new(), flate2::Compression::fast());
        gz.write_all(&[good.clone(), vec![0u8; 1024], b"#!/bin/sh".to_vec()].concat())
            .unwrap();
        tail.clone_from(&gz.finish().unwrap());
        let (path, asset) = asset_of(&d, &tail);
        assert!(unpack(&path, &asset, &versions, "0.2.0")
            .unwrap_err()
            .contains("after its end"));
        let _ = std::fs::remove_dir_all(&d);
    }

    #[test]
    fn the_hash_and_the_size_are_checked_before_the_unpack() {
        let d = scratch("hash");
        let versions = d.join("versions");
        let gz = tar_gz(&[tar_entry("wyrmd", b'0', 0o755, b"binary")]);
        let (path, asset) = asset_of(&d, &gz);
        let mut wrong = asset.clone();
        wrong.sha256 = "0".repeat(64);
        let err = unpack(&path, &wrong, &versions, "0.2.0").unwrap_err();
        assert!(err.contains("SHA-256"), "{err}");
        let mut wrong = asset.clone();
        wrong.size += 1;
        let err = unpack(&path, &wrong, &versions, "0.2.0").unwrap_err();
        assert!(err.contains("bytes"), "{err}");
        // nothing was made: not even the part directory
        assert!(!versions.join(".0.2.0.part").exists());
        assert!(!versions.join("0.2.0").exists());
        // a version name that is a path
        assert!(unpack(&path, &asset, &versions, "../0.2.0").is_err());
        let _ = std::fs::remove_dir_all(&d);
    }

    #[cfg(unix)]
    #[test]
    fn the_layout_is_checked_and_switched_by_one_rename() {
        let d = scratch("layout");
        let exe = d.join("built");
        std::fs::write(&exe, b"v1").unwrap();
        // a binary that sits anywhere else is refused, and the reason says so
        let err = Layout::of_broker(&exe, "0.1.0").unwrap_err();
        assert!(err.contains("install-layout"), "{err}");
        let l = Layout::install(&d.join("opt"), &exe, "0.1.0").unwrap();
        assert_eq!(l.current_version().as_deref(), Some("0.1.0"));
        assert_eq!(std::fs::read(l.guard()).unwrap(), b"v1");
        assert_eq!(Layout::of_broker(&l.bin_of("0.1.0"), "0.1.0").unwrap(), l);
        // through the link too
        assert_eq!(
            Layout::of_broker(&l.current().join(BIN), "0.1.0").unwrap(),
            l
        );
        assert_eq!(Layout::of_guard(&l.guard()).unwrap(), l);
        // the binary says another version than its directory
        assert!(Layout::of_broker(&l.bin_of("0.1.0"), "0.2.0").is_err());
        // without the guard
        let guard = l.guard();
        std::fs::rename(&guard, d.join("guard.away")).unwrap();
        let err = Layout::of_broker(&l.bin_of("0.1.0"), "0.1.0").unwrap_err();
        assert!(err.contains("no guard"), "{err}");
        std::fs::rename(d.join("guard.away"), &guard).unwrap();
        // a version that is not there cannot become current
        assert!(l.switch("0.2.0").is_err());
        std::fs::create_dir_all(l.versions().join("0.2.0")).unwrap();
        std::fs::write(l.bin_of("0.2.0"), b"v2").unwrap();
        l.switch("0.2.0").unwrap();
        assert_eq!(l.current_version().as_deref(), Some("0.2.0"));
        assert_eq!(std::fs::read(l.current().join(BIN)).unwrap(), b"v2");
        assert!(!d.join("opt").join(".current.new").exists());
        // `current` as a directory is not the layout
        let err = Layout::of_broker(&l.bin_of("0.1.0"), "0.1.0").unwrap_err();
        assert!(err.contains("symbolic link"), "{err}");
        // the guard follows a confirmed version
        assert!(!l.guard_is(&l.bin_of("0.2.0")));
        l.refresh_guard(&l.bin_of("0.2.0")).unwrap();
        assert!(l.guard_is(&l.bin_of("0.2.0")));
        // old versions go, the kept ones stay
        std::fs::create_dir_all(l.versions().join(".0.3.0.part")).unwrap();
        assert_eq!(l.prune(&["0.2.0"]), ["0.1.0"]);
        assert!(l.bin_of("0.2.0").is_file());
        assert!(!l.versions().join(".0.3.0.part").exists());
        let _ = std::fs::remove_dir_all(&d);
    }

    #[cfg(unix)]
    #[test]
    fn the_guard_takes_a_failed_trial_back() {
        let d = scratch("guard");
        let exe = d.join("built");
        std::fs::write(&exe, b"v1").unwrap();
        let l = Layout::install(&d.join("opt"), &exe, "0.1.0").unwrap();
        std::fs::create_dir_all(l.versions().join("0.2.0")).unwrap();
        std::fs::write(l.bin_of("0.2.0"), b"v2").unwrap();
        let data = d.join("data");
        std::fs::create_dir_all(&data).unwrap();
        // nothing to do without an update
        assert_eq!(guard(&l, &data, "0.1.0").unwrap(), Guarded::Nothing);
        assert!(guard_stamp(&data).is_some_and(|t| t + 5 >= now_s()));
        let trial = |f: &dyn Fn(&mut UpdateFile)| {
            l.switch("0.2.0").unwrap();
            let mut u = UpdateFile {
                from: "0.1.0".into(),
                to: "0.2.0".into(),
                state: "trial".into(),
                deadline: now_s() + 600,
                ..Default::default()
            };
            f(&mut u);
            u.save(&data).unwrap();
        };
        // a trial that goes on is left alone
        trial(&|u| u.attempts = 2);
        assert_eq!(guard(&l, &data, "0.1.0").unwrap(), Guarded::Nothing);
        assert_eq!(l.current_version().as_deref(), Some("0.2.0"));
        // the three reasons
        for (name, f) in [
            ("attempts", (&|u: &mut UpdateFile| u.attempts = 3) as &dyn Fn(&mut UpdateFile)),
            ("deadline", &|u: &mut UpdateFile| u.deadline = now_s() - 1),
            ("gave up", &|u: &mut UpdateFile| u.failed = "link plc1 is not back".into()),
        ] {
            trial(f);
            let r = guard(&l, &data, "0.1.0").unwrap();
            assert!(
                matches!(&r, Guarded::RolledBack { from, restored: false, .. } if from == "0.1.0"),
                "{name}: {r:?}"
            );
            assert_eq!(l.current_version().as_deref(), Some("0.1.0"), "{name}");
            let u = UpdateFile::load(&data).unwrap();
            assert_eq!(u.state, "rolled_back", "{name}");
            assert!(!u.reason.is_empty() && !u.audited, "{name}");
            // done once
            assert_eq!(guard(&l, &data, "0.1.0").unwrap(), Guarded::Nothing);
        }
        // a confirmed update is rolled back only when asked, and in time
        trial(&|u| {
            u.state = "confirmed".into();
            u.keep_until = now_s() + 600;
        });
        assert_eq!(guard(&l, &data, "0.2.0").unwrap(), Guarded::Nothing);
        trial(&|u| {
            u.state = "confirmed".into();
            u.keep_until = now_s() - 1;
            u.rollback = "user:eve".into();
        });
        assert_eq!(guard(&l, &data, "0.2.0").unwrap(), Guarded::Nothing);
        trial(&|u| {
            u.state = "confirmed".into();
            u.keep_until = now_s() + 600;
            u.rollback = "user:ann".into();
        });
        assert!(matches!(
            guard(&l, &data, "0.2.0").unwrap(),
            Guarded::RolledBack { .. }
        ));
        assert_eq!(
            UpdateFile::load(&data).unwrap().reason,
            "rolled back by user:ann"
        );
        // a SCHEMA moved and the backup is gone: the new version stays
        trial(&|u| {
            u.attempts = 3;
            u.from_schemas = BTreeMap::from([("registry".into(), 19)]);
            u.to_schemas = BTreeMap::from([("registry".into(), 20)]);
            u.backup = "site-x.wyrm-backup".into();
            u.backup_sha256 = "0".repeat(64);
        });
        assert!(matches!(guard(&l, &data, "0.1.0").unwrap(), Guarded::Stuck(_)));
        assert_eq!(l.current_version().as_deref(), Some("0.2.0"));
        assert_eq!(UpdateFile::load(&data).unwrap().state, "failed");
        // the old version is gone: the same
        trial(&|u| u.attempts = 3);
        std::fs::remove_dir_all(l.versions().join("0.1.0")).unwrap();
        assert!(matches!(guard(&l, &data, "0.1.0").unwrap(), Guarded::Stuck(_)));
        assert_eq!(l.current_version().as_deref(), Some("0.2.0"));
        let _ = std::fs::remove_dir_all(&d);
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn a_binary_runs_with_no_environment_and_a_time_limit() {
        let d = scratch("run");
        let script = d.join("tool");
        std::fs::write(
            &script,
            "#!/bin/sh\nif [ \"$1\" = slow ]; then sleep 30; fi\n\
             if [ \"$1\" = bad ]; then echo broken >&2; exit 3; fi\n\
             echo \"env:${WYRM_TEST_LEAK:-none}:$1\"\n",
        )
        .unwrap();
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(&script, std::fs::Permissions::from_mode(0o755)).unwrap();
        std::env::set_var("WYRM_TEST_LEAK", "leaked");
        let t = std::time::Duration::from_secs(10);
        // an argument with shell characters is one argument, not a command
        let out = run_binary(&script, &["a b; echo x".into()], t).await.unwrap();
        assert_eq!(out.trim(), "env:none:a b; echo x");
        let err = run_binary(&script, &["bad".into()], t).await.unwrap_err();
        assert!(err.contains("broken"), "{err}");
        let err = run_binary(&script, &["slow".into()], std::time::Duration::from_millis(300))
            .await
            .unwrap_err();
        assert!(err.contains("no answer"), "{err}");
        let _ = std::fs::remove_dir_all(&d);
    }
}
