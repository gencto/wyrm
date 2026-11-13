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
/// `data_dir/update.seen`: the highest sequence of a releases index read.
pub const SEEN_FILE: &str = "update.seen";
/// In a version directory: the signed release document the version came
/// from, and its signature. An archive may not hold files of these names.
pub const RELEASE_DOC: &str = "release.json";
pub const RELEASE_SIG: &str = "release.sig";
/// `<prefix>/bin/trusted.json`: versions put there by hand
/// (`wyrmd install-layout`), each with the SHA-256 of its binary.
pub const TRUSTED: &str = "trusted.json";
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
    format!("{}-{}{musl}", std::env::consts::ARCH, std::env::consts::OS)
}

/// The identity of this build as far as this crate knows it: the stores of
/// other crates (`users`, `flows`) are added by `wyrmd`.
pub fn built() -> Identity {
    use wyrm_state::State;
    Identity {
        version: env!("CARGO_PKG_VERSION").to_owned(),
        target: target(),
        schemas: BTreeMap::from([
            ("registry".to_owned(), crate::registry::Registry::SCHEMA),
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
    /// SHA-256 (hex) of the binary `wyrmd` in the archive: what a host runs
    /// is checked against it before every start, not only at the unpack.
    #[serde(default)]
    pub bin_sha256: String,
}

fn is_sha256(s: &str) -> bool {
    s.len() == 64
        && s.bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
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

/// One entry of `releases.json`: a release document exactly as it was
/// signed, and its own signature. Nothing of an entry is used but what
/// that signature covers.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct IndexEntry {
    /// The text of `wyrmd-<version>.release.json`.
    pub release: String,
    /// The text of its `.sig` file.
    pub signature: String,
}

/// `releases.json` as it is written: signed as a whole, and every entry
/// signed by itself.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct IndexFile {
    /// [`FORMAT`].
    pub wyrmd_releases: u32,
    /// Goes up by one with every index that is published: a host refuses
    /// an index older than one it has read (an old, validly signed index
    /// put back would hide a newer release).
    pub sequence: u64,
    /// When it was made (`YYYY-MM-DD`), for people.
    #[serde(default)]
    pub created: String,
    pub releases: Vec<IndexEntry>,
}

/// What `updates.channel` serves: the index and its signature in one file,
/// so a reader never sees one without the other.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Channel {
    /// [`FORMAT`].
    pub wyrmd_channel: u32,
    /// The text of the index ([`IndexFile`]) exactly as it was signed.
    pub index: String,
    /// Its signature ([`sign_index`]).
    pub signature: String,
}

/// A release whose own signature was checked against the pinned keys, with
/// the signed bytes (they are what is passed on, to a standby for one).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Signed {
    pub release: Release,
    pub document: Vec<u8>,
    pub signature: String,
}

/// A releases index that was checked ([`read_index`]): its own signature
/// and the signature of every entry.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct Index {
    /// 0: an index that was never published (a new one).
    pub sequence: u64,
    pub created: String,
    pub releases: Vec<Signed>,
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
                return Err(format!(
                    "target {t}: file {:?}: a plain *.tar.gz name",
                    a.file
                ));
            }
            if !is_sha256(&a.sha256) {
                return Err(format!("target {t}: sha256: 64 lower-case hex digits"));
            }
            if !is_sha256(&a.bin_sha256) {
                return Err(format!("target {t}: bin_sha256: 64 lower-case hex digits"));
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
        // a store this version does not know could not be put back by its
        // guard: such a release is installed by hand
        if let Some(unknown) = self
            .schemas
            .keys()
            .chain(me.schemas.keys())
            .find(|k| !CONTROL_STORES.iter().any(|(name, _, _)| name == k))
        {
            return Err(format!(
                "wyrmd {} names the store {unknown:?}, which this version cannot restore \
                 after a failed update: update this broker by hand",
                self.version
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
fn verify(
    domain: &[u8],
    bytes: &[u8],
    signature: &str,
    keys: &[VerifyingKey],
) -> Result<(), String> {
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

/// Most releases in an index.
pub const MAX_RELEASES: usize = 256;

/// An index: its own signature first, then the signature and the bounds of
/// every entry. An entry whose own signature does not verify refuses the
/// whole index: no release is trusted because the list around it is signed.
pub fn read_index(bytes: &[u8], signature: &str, keys: &[VerifyingKey]) -> Result<Index, String> {
    if bytes.len() > MAX_RELEASE * 4 {
        return Err(format!("index: more than {} bytes", MAX_RELEASE * 4));
    }
    verify(DOMAIN_INDEX, bytes, signature, keys)?;
    let file: IndexFile = serde_json::from_slice(bytes).map_err(|e| format!("index: {e}"))?;
    if file.wyrmd_releases != FORMAT {
        return Err(format!(
            "index format {}: this broker reads format {FORMAT}",
            file.wyrmd_releases
        ));
    }
    if file.releases.len() > MAX_RELEASES {
        return Err(format!("index: more than {MAX_RELEASES} releases"));
    }
    if file.sequence == 0 || file.created.len() > 32 {
        return Err("index: no sequence, or a created that is not a date".into());
    }
    let mut out = Index {
        sequence: file.sequence,
        created: file.created,
        releases: Vec::new(),
    };
    for e in file.releases {
        let release = read_release(e.release.as_bytes(), &e.signature, keys)
            .map_err(|why| format!("index: an entry is refused: {why}"))?;
        if out.get(&release.version).is_some() {
            return Err(format!("index: wyrmd {} twice", release.version));
        }
        out.releases.push(Signed {
            release,
            document: e.release.into_bytes(),
            signature: e.signature,
        });
    }
    Ok(out)
}

impl Index {
    /// The newest release with a build for `target`.
    pub fn latest(&self, target: &str) -> Option<&Signed> {
        self.releases
            .iter()
            .filter(|s| s.release.targets.contains_key(target))
            .fold(None, |best: Option<&Signed>, s| match best {
                Some(b) if !newer(&s.release.version, &b.release.version) => Some(b),
                _ => Some(s),
            })
    }

    pub fn get(&self, version: &str) -> Option<&Signed> {
        self.releases.iter().find(|s| s.release.version == version)
    }

    /// The index with the release document `document` added (a release of
    /// the same version is replaced): the document must carry its own good
    /// signature. The sequence goes up by one. The result is to be signed
    /// as a whole ([`sign_index`]).
    pub fn with(
        mut self,
        document: &[u8],
        signature: &str,
        keys: &[VerifyingKey],
        created: &str,
    ) -> Result<Self, String> {
        let release = read_release(document, signature, keys)?;
        self.sequence = self
            .sequence
            .checked_add(1)
            .ok_or("index: the sequence is used up")?;
        created.clone_into(&mut self.created);
        self.releases
            .retain(|s| s.release.version != release.version);
        if self.releases.len() >= MAX_RELEASES {
            return Err(format!("index: more than {MAX_RELEASES} releases"));
        }
        self.releases.push(Signed {
            release,
            document: document.to_vec(),
            signature: signature.trim().to_owned(),
        });
        Ok(self)
    }

    /// As it is written to `releases.json`.
    pub fn to_file(&self) -> Result<IndexFile, String> {
        let releases = self
            .releases
            .iter()
            .map(|s| {
                Ok(IndexEntry {
                    release: String::from_utf8(s.document.clone())
                        .map_err(|_| "a release document is not text".to_owned())?,
                    signature: s.signature.clone(),
                })
            })
            .collect::<Result<Vec<_>, String>>()?;
        Ok(IndexFile {
            wyrmd_releases: FORMAT,
            sequence: self.sequence,
            created: self.created.clone(),
            releases,
        })
    }
}

/// The channel file of an index and its signature.
pub fn bundle(index: &[u8], signature: &str) -> Result<Vec<u8>, String> {
    let c = Channel {
        wyrmd_channel: FORMAT,
        index: String::from_utf8(index.to_vec()).map_err(|_| "index: not text".to_owned())?,
        signature: signature.trim().to_owned(),
    };
    serde_json::to_vec(&c).map_err(|e| e.to_string())
}

/// Largest channel file (the index as a JSON string, and its signature).
pub const MAX_CHANNEL: usize = MAX_RELEASE * 10;

/// A channel file: the index in it, checked as [`read_index`] checks it.
pub fn read_channel(bytes: &[u8], keys: &[VerifyingKey]) -> Result<Index, String> {
    if bytes.len() > MAX_CHANNEL {
        return Err(format!("channel: more than {MAX_CHANNEL} bytes"));
    }
    let c: Channel = serde_json::from_slice(bytes).map_err(|e| format!("channel: {e}"))?;
    if c.wyrmd_channel != FORMAT {
        return Err(format!(
            "channel format {}: this broker reads format {FORMAT}",
            c.wyrmd_channel
        ));
    }
    read_index(c.index.as_bytes(), &c.signature, keys)
}

/// The highest index sequence this host has read (`data_dir/update.seen`).
pub fn seen_sequence(data_dir: &Path) -> u64 {
    std::fs::read_to_string(data_dir.join(SEEN_FILE))
        .ok()
        .and_then(|t| t.trim().parse().ok())
        .unwrap_or(0)
}

/// Take the index of sequence `sequence`: refused when this host has read
/// a later one; remembered when it is later than all before.
pub fn note_sequence(data_dir: &Path, sequence: u64) -> Result<(), String> {
    let seen = seen_sequence(data_dir);
    if sequence < seen {
        return Err(format!(
            "the releases index is older than one this broker has read (sequence {sequence}, \
             read {seen}): an old index was put back"
        ));
    }
    if sequence > seen {
        let path = data_dir.join(SEEN_FILE);
        crate::secret::write_private(&path, sequence.to_string().as_bytes())
            .map_err(|e| io(&path, e))?;
    }
    Ok(())
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
        let name_raw: Vec<u8> = header[..100]
            .iter()
            .copied()
            .take_while(|b| *b != 0)
            .collect();
        let name = String::from_utf8(name_raw).map_err(|_| "archive: a name is not UTF-8")?;
        let shown: String = name.chars().take(64).collect();
        // ustar's prefix field: a longer path, never ours
        if header[345] != 0 {
            return Err(format!(
                "archive: entry {shown:?}: a path, not a plain name"
            ));
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
        if name == RELEASE_DOC || name == RELEASE_SIG {
            return Err(format!(
                "archive: entry {name}: the name of a file the broker writes"
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
            return Err(format!("archive: {name} has {size} bytes, more than {max}"));
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
            let n =
                read_full(src, &mut buf[..pad as usize]).map_err(|e| format!("archive: {e}"))?;
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
    let unpacked = unpacked.and_then(|_| {
        // what the signed release says the binary is
        let (bin, _) = sha256_file(&part.join(BIN))?;
        if bin == asset.bin_sha256 {
            Ok(())
        } else {
            Err("the binary in the archive is not the one of the release (SHA-256)".to_owned())
        }
    });
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

/// Keep the signed release document and its signature in the version's
/// directory: what [`Layout::verify`] checks the binary against before
/// every start.
pub fn keep_release(
    versions: &Path,
    version: &str,
    document: &[u8],
    signature: &str,
) -> Result<(), String> {
    check_version(version)?;
    let dir = versions.join(version);
    for (name, bytes) in [
        (RELEASE_DOC, document),
        (RELEASE_SIG, signature.trim().as_bytes()),
    ] {
        let path = dir.join(name);
        if path.symlink_metadata().is_ok() {
            std::fs::remove_file(&path).map_err(|e| io(&path, e))?;
        }
        let mut f = new_file(&path, 0o644).map_err(|e| io(&path, e))?;
        f.write_all(bytes).map_err(|e| io(&path, e))?;
        f.sync_all().map_err(|e| io(&path, e))?;
    }
    sync_dir(&dir);
    Ok(())
}

/// A small file that is a file (no link), read whole.
fn read_plain_file(path: &Path, max: u64) -> Result<Vec<u8>, String> {
    let m = path.symlink_metadata().map_err(|e| io(path, e))?;
    if !m.file_type().is_file() || m.len() > max {
        return Err(format!(
            "{}: not a plain file of at most {max} bytes",
            path.display()
        ));
    }
    std::fs::read(path).map_err(|e| io(path, e))
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

    /// `<prefix>/bin/trusted.json`.
    pub fn trusted(&self) -> PathBuf {
        self.prefix.join("bin").join(TRUSTED)
    }

    fn trusted_list(&self) -> BTreeMap<String, String> {
        read_plain_file(&self.trusted(), 1 << 20)
            .ok()
            .and_then(|b| serde_json::from_slice(&b).ok())
            .unwrap_or_default()
    }

    /// Is `sha256` the binary of `version` as this host may run it? Either
    /// the version was put there by hand (`bin/trusted.json` names it with
    /// this hash), or its directory holds a release document that one of
    /// `keys` signed and that names this hash for this host's target. The
    /// document's own version must be the directory's: a signed release is
    /// good for its own version only.
    pub fn verify_hash(
        &self,
        version: &str,
        sha256: &str,
        keys: &[VerifyingKey],
    ) -> Result<(), String> {
        check_version(version)?;
        if self.trusted_list().get(version).map(String::as_str) == Some(sha256) {
            return Ok(());
        }
        let dir = self.versions().join(version);
        let found = (|| {
            let doc = read_plain_file(&dir.join(RELEASE_DOC), MAX_RELEASE as u64)?;
            let sig = read_plain_file(&dir.join(RELEASE_SIG), 4096)?;
            let sig = String::from_utf8(sig).map_err(|_| "signature: not text".to_owned())?;
            let release = read_release(&doc, &sig, keys)?;
            if release.version != version {
                return Err(format!(
                    "its release document is of wyrmd {}",
                    release.version
                ));
            }
            let asset = release
                .targets
                .get(&target())
                .ok_or("its release has no build for this host")?;
            if asset.bin_sha256 != sha256 {
                return Err("the binary is not the one its signed release names".to_owned());
            }
            Ok(())
        })();
        found.map_err(|e| format!("wyrmd {version} in {} is not verified: {e}", dir.display()))
    }

    /// [`Self::verify_hash`] of the binary of `version` as it is on disk (a
    /// plain file, no link).
    pub fn verify(&self, version: &str, keys: &[VerifyingKey]) -> Result<(), String> {
        check_version(version)?;
        let bin = self.bin_of(version);
        let plain = bin
            .symlink_metadata()
            .is_ok_and(|m| m.file_type().is_file());
        if !plain {
            return Err(format!("{}: not a plain file", bin.display()));
        }
        let (sha, _) = sha256_file(&bin)?;
        self.verify_hash(version, &sha, keys)
    }

    /// Name `version` with the hash of its binary in `bin/trusted.json`: a
    /// version put there by hand has no signed release.
    fn trust(&self, version: &str, sha256: &str) -> Result<(), String> {
        let mut list = self.trusted_list();
        list.insert(version.to_owned(), sha256.to_owned());
        let path = self.trusted();
        let dir = path.parent().unwrap_or(&self.prefix).to_owned();
        std::fs::create_dir_all(&dir).map_err(|e| io(&dir, e))?;
        let tmp = dir.join(format!(".{TRUSTED}.new"));
        if tmp.symlink_metadata().is_ok() {
            std::fs::remove_file(&tmp).map_err(|e| io(&tmp, e))?;
        }
        let bytes = serde_json::to_vec_pretty(&list).map_err(|e| e.to_string())?;
        let mut f = new_file(&tmp, 0o644).map_err(|e| io(&tmp, e))?;
        f.write_all(&bytes).map_err(|e| io(&tmp, e))?;
        f.sync_all().map_err(|e| io(&tmp, e))?;
        std::fs::rename(&tmp, &path).map_err(|e| io(&path, e))
    }

    /// For a guard that runs as root (`ExecStartPre=+… guard-refresh`, the
    /// hardened unit): make the guard the binary of the version that is
    /// current, when that version is verified. The binary is read once,
    /// through no link, and what was hashed is what is written. Returns
    /// whether the guard was replaced.
    pub fn refresh_guard_verified(&self, keys: &[VerifyingKey]) -> Result<bool, String> {
        let version = self
            .current_version()
            .ok_or_else(|| format!("{}: not a link to a version", self.current().display()))?;
        let bytes = read_plain_file(&self.bin_of(&version), MAX_BINARY)?;
        let sha = hex::encode(Sha256::digest(&bytes));
        self.verify_hash(&version, &sha, keys)?;
        let guard = self.guard();
        if sha256_file(&guard).is_ok_and(|(g, _)| g == sha) {
            return Ok(false);
        }
        let dir = guard.parent().unwrap_or(&self.prefix).to_owned();
        let tmp = dir.join(format!(".{GUARD}.new"));
        if tmp.symlink_metadata().is_ok() {
            std::fs::remove_file(&tmp).map_err(|e| io(&tmp, e))?;
        }
        let mut out = new_file(&tmp, 0o755).map_err(|e| io(&tmp, e))?;
        out.write_all(&bytes).map_err(|e| io(&tmp, e))?;
        out.sync_all().map_err(|e| io(&tmp, e))?;
        drop(out);
        std::fs::rename(&tmp, &guard).map_err(|e| io(&guard, e))?;
        sync_dir(&dir);
        Ok(true)
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
        let bin = exe
            .parent()
            .filter(|_| exe.file_name().and_then(|n| n.to_str()) == Some(GUARD));
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
        // put there by hand: trusted by its hash, it has no signed release
        l.trust(version, &sha256_file(&bin)?.0)?;
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
    /// Starts of the new version in its trial, counted by the guard that
    /// lets each one go on (a binary that cannot start is counted too).
    #[serde(default)]
    pub attempts: u32,
    /// Seconds the new version has to prove itself, from its first start.
    #[serde(default)]
    pub trial_s: u64,
    /// Seconds the new version has run in its trial, written by it as it
    /// runs. The trial ends when this reaches `trial_s`: time the host was
    /// off, or the broker was down, is not part of a trial.
    #[serde(default)]
    pub ran_s: u64,
    /// Unix seconds at which the trial ends if the version keeps running:
    /// an estimate for people, set at each start. Nothing is decided by it.
    #[serde(default)]
    pub deadline: u64,
    /// The control-plane stores (names of `schemas`) that existed when the
    /// update began: a store that did not is moved aside by a rollback,
    /// not restored.
    #[serde(default)]
    pub stores: Vec<String>,
    /// After a rollback, or one that could not be done: starts the guard
    /// let through before the version that is current came up once.
    #[serde(default)]
    pub starts: u32,
    /// The version that is current after a rollback came up: the guard
    /// leaves `current` alone from then on.
    #[serde(default)]
    pub settled: bool,
    /// Starts at which the clock was past `keep_until` (see
    /// [`UpdateFile::expire`]).
    #[serde(default)]
    pub expired_starts: u32,
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

    /// Is the old version of a confirmed update no longer kept? Called at
    /// each start of the broker (`at_start`) and then once an hour with
    /// `past_s`, the seconds this process has seen the clock past
    /// `keep_until` without a break. One reading of the clock decides
    /// nothing (a host without a clock battery starts with a wrong time):
    /// the time must be past `keep_until` at two starts, or for a full hour
    /// of one run. A clock that is before `keep_until` again forgets the
    /// starts counted. Never in a trial. `true`: the old version and the
    /// pre-update backup may go.
    pub fn expire(&mut self, now: u64, at_start: bool, past_s: u64) -> bool {
        match self.state.as_str() {
            "rolled_back" => return true,
            "confirmed" => {}
            _ => return false,
        }
        if now <= self.keep_until {
            self.expired_starts = 0;
            return false;
        }
        if at_start {
            self.expired_starts = self.expired_starts.saturating_add(1);
        }
        self.expired_starts >= 2 || past_s >= 3600
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
    // the first start of a broker: the guard runs before it made the directory
    if std::fs::create_dir_all(data_dir).is_err() {
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
    RolledBack {
        from: String,
        to: String,
        restored: bool,
    },
    /// A rollback was due and could not be done as a whole; the text says
    /// which version is current and on what state.
    Stuck(String),
}

fn other_of<'a>(u: &'a UpdateFile, current: &str) -> &'a str {
    if current == u.from {
        &u.to
    } else {
        &u.from
    }
}

/// `wyrmd update-guard`: run before every start of the broker, by the
/// previous version's binary (`<prefix>/bin/wyrmd-guard`).
///
/// It counts each start of a version in its trial. It takes an update back
/// when the new version gave its trial up (exit code 76 and its reason),
/// when [`MAX_ATTEMPTS`] starts did not end the trial, or when a rollback
/// was asked for on purpose: where the update moved a SCHEMA it restores
/// those stores from the pre-update backup, then points `current` back at
/// the old version. The clock decides nothing: a host that was off for a
/// day comes back into the trial it left.
///
/// **It never leaves the broker without a version to start because a
/// restore failed.** When the stores cannot be restored (the backup is
/// gone or changed, a file cannot be written), the old version is made
/// current on the state as it is and the state is `failed` with the reason.
/// If the version that is current after a rollback then does not come up
/// in [`MAX_ATTEMPTS`] starts, the other version is made current. Errors
/// of writing `update.json` are said and passed over.
///
/// With `keys` (a broker in `updates.mode: "self"`) the version that is
/// current is verified before the guard lets it start
/// ([`Layout::verify`]): a binary that is not the one a signed release
/// names (or one put there by hand) is never started. The other version of
/// the update is made current if it verifies; else the guard returns `Err`
/// and nothing starts. That is the one case in which it blocks a start.
pub fn guard(
    layout: &Layout,
    data_dir: &Path,
    version: &str,
    keys: Option<&[VerifyingKey]>,
) -> Result<Guarded, String> {
    stamp_guard(data_dir, version);
    let done = match UpdateFile::load(data_dir) {
        Some(u) => decide(layout, data_dir, u),
        None => Guarded::Nothing,
    };
    if let Some(keys) = keys {
        verified_current(layout, data_dir, keys)?;
    }
    Ok(done)
}

fn save_or_say(u: &UpdateFile, data_dir: &Path) {
    if let Err(e) = u.save(data_dir) {
        eprintln!("update-guard: {STATE_FILE} is not written: {e}");
    }
}

fn decide(layout: &Layout, data_dir: &Path, mut u: UpdateFile) -> Guarded {
    let now = now_s();
    let current = layout.current_version().unwrap_or_default();
    if u.state == "trial" && current == u.from {
        // the old version stopped before `current` moved: nothing ran
        u.state = "rolled_back".into();
        u.reason = format!("the broker stopped before wyrmd {} was made current", u.to);
        u.ended = now;
        u.audited = false;
        u.settled = true;
        save_or_say(&u, data_dir);
        return Guarded::RolledBack {
            from: u.from,
            to: u.to,
            restored: false,
        };
    }
    let why = match u.state.as_str() {
        "trial" if !u.failed.is_empty() => {
            Some(format!("wyrmd {} gave its trial up: {}", u.to, u.failed))
        }
        "trial" if u.attempts >= MAX_ATTEMPTS => Some(format!(
            "wyrmd {} was started {} times and did not end its trial",
            u.to, u.attempts
        )),
        "trial" => {
            // this start of the new version is let through, and counted
            u.attempts += 1;
            save_or_say(&u, data_dir);
            return Guarded::Nothing;
        }
        "confirmed" if !u.rollback.is_empty() => Some(format!("rolled back by {}", u.rollback)),
        "rolled_back" | "failed" if !u.settled => {
            // the version a rollback left current must come up once
            if u.starts < MAX_ATTEMPTS {
                u.starts += 1;
                save_or_say(&u, data_dir);
                return Guarded::Nothing;
            }
            let other = other_of(&u, &current).to_owned();
            let said = format!(
                "wyrmd {current} did not come up in {} starts after the rollback",
                u.starts
            );
            u.starts = 0;
            u.audited = false;
            u.state = "failed".into();
            u.ended = now;
            if check_version(&other).is_ok() && layout.switch(&other).is_ok() {
                u.reason = format!("{}; {said}: wyrmd {other} is current", u.reason);
            } else {
                // nothing else to start: this one goes on being tried
                u.settled = true;
                u.reason = format!("{}; {said}, and wyrmd {other} is gone", u.reason);
            }
            save_or_say(&u, data_dir);
            return Guarded::Stuck(u.reason);
        }
        _ => None,
    };
    let Some(why) = why else {
        return Guarded::Nothing;
    };
    u.ended = now;
    u.audited = false;
    u.rollback.clear();
    u.starts = 0;
    u.settled = false;
    if check_version(&u.from).is_err() || !layout.bin_of(&u.from).is_file() {
        // the old version cannot be started: the new one stays
        u.state = "failed".into();
        u.reason = format!(
            "{why}; not rolled back: {} is gone; wyrmd {} stays",
            layout.bin_of(&u.from).display(),
            u.to
        );
        u.settled = true;
        save_or_say(&u, data_dir);
        return Guarded::Stuck(u.reason);
    }
    let moved = u.moved();
    let restored = if moved.is_empty() || u.role == "standby" {
        Ok(false)
    } else {
        restore_for(data_dir, &u, &moved).map(|()| true)
    };
    if let Err(e) = layout.switch(&u.from) {
        u.state = "failed".into();
        u.reason = format!("{why}; not rolled back: {e}; wyrmd {} stays", u.to);
        u.settled = true;
        save_or_say(&u, data_dir);
        return Guarded::Stuck(u.reason);
    }
    match restored {
        Ok(restored) => {
            u.state = "rolled_back".into();
            u.reason = why;
            u.restored = restored;
            save_or_say(&u, data_dir);
            Guarded::RolledBack {
                from: u.from,
                to: u.to,
                restored,
            }
        }
        Err(e) => {
            // the old version is started all the same, on the state as it is
            u.state = "failed".into();
            u.restored = false;
            u.reason = format!(
                "{why}; the control plane ({}) was not restored: {e}; wyrmd {} runs on the \
                 state wyrmd {} left",
                moved.join(", "),
                u.from,
                u.to
            );
            save_or_say(&u, data_dir);
            Guarded::Stuck(u.reason)
        }
    }
}

/// The pre-update backup of `u`, checked, and the stores `moved` put back.
fn restore_for(data_dir: &Path, u: &UpdateFile, moved: &[String]) -> Result<(), String> {
    if u.backup.is_empty() || !plain_name(&u.backup, 200) {
        return Err("the update has no pre-update backup".into());
    }
    let backup = data_dir.join("backups").join(&u.backup);
    let (sha, _) = sha256_file(&backup).map_err(|e| format!("the pre-update backup: {e}"))?;
    if sha != u.backup_sha256 {
        return Err(format!(
            "the pre-update backup {} is not the file the update made",
            u.backup
        ));
    }
    restore_control(data_dir, &backup, moved, &u.stores)
        .map_err(|e| format!("pre-update backup {}: {e}", u.backup))
}

/// The version `current` names is verified, or another version of the
/// update that is; `Err` when nothing verified can be started.
fn verified_current(layout: &Layout, data_dir: &Path, keys: &[VerifyingKey]) -> Result<(), String> {
    let current = layout
        .current_version()
        .ok_or_else(|| format!("{}: not a link to a version", layout.current().display()))?;
    let Err(why) = layout.verify(&current, keys) else {
        return Ok(());
    };
    let mut u = UpdateFile::load(data_dir);
    let other = u
        .as_ref()
        .map(|u| other_of(u, &current).to_owned())
        .filter(|o| o != &current && layout.verify(o, keys).is_ok());
    let Some(other) = other else {
        return Err(format!(
            "{why}. Nothing is started: a broker in updates.mode \"self\" runs only a binary \
             that a pinned release key signed or that `wyrmd install-layout` put there"
        ));
    };
    layout.switch(&other)?;
    if let Some(u) = u.as_mut() {
        u.state = "failed".into();
        u.reason = format!("{why}; wyrmd {other} is current");
        u.ended = now_s();
        u.audited = false;
        u.settled = true;
        u.rollback.clear();
        save_or_say(u, data_dir);
    }
    eprintln!("update-guard: {why}; wyrmd {other} is current");
    Ok(())
}

/// The control-plane WAL stores: name in `schemas`, directory in a backup's
/// `control` section, directory under `data_dir`.
pub const CONTROL_STORES: [(&str, &str, &str); 4] = [
    ("registry", "state", "state"),
    ("flows", "flows", "flows/state"),
    ("users", "users", "gateway/users"),
    ("audit", "audit", "audit"),
];

/// The control-plane stores (names of `schemas`) that exist in `data_dir`.
pub fn stores_of(data_dir: &Path) -> Vec<String> {
    CONTROL_STORES
        .iter()
        .filter(|(_, _, dir)| data_dir.join(dir).is_dir())
        .map(|(name, _, _)| (*name).to_owned())
        .collect()
}

/// Put the control plane of before an update back, with the broker
/// stopped: the WALs of `stores` (names of `schemas`) from the `control`
/// section of the pre-update backup at `backup`. A store of `existed` is
/// replaced by the backup's; one that did not exist before the update is
/// moved aside and left out, as it was.
///
/// The backup is one this broker sealed (`how: broker`): its manifest is
/// checked with the key of `secrets.key` before a file is read, and every
/// file against the manifest's size and SHA-256. Everything is read into
/// `data_dir/update.restore` first; an error up to there changes nothing.
/// Then each store's directory is moved into `data_dir/update.aside` and
/// replaced; if a move fails, the ones made are undone.
pub fn restore_control(
    data_dir: &Path,
    backup: &Path,
    stores: &[String],
    existed: &[String],
) -> Result<(), String> {
    use crate::backup as format;
    let mut r = format::Reader::open(backup, 8 << 30)?;
    if r.manifest().kind != format::Kind::Broker {
        return Err("not a broker backup".into());
    }
    if r.manifest().sealed.how != "broker" {
        return Err("not sealed for this broker".into());
    }
    let key_path = data_dir.join("secrets.key");
    let secrets_key = zeroize::Zeroizing::new(
        std::fs::read_to_string(&key_path)
            .ok()
            .and_then(|t| hex::decode(t.trim()).ok())
            .ok_or("secrets.key: not readable")?,
    );
    // the manifest is authentic: every path, size and digest in it
    r.manifest()
        .key(None, Some(&secrets_key))
        .map_err(|e| format!("its manifest is not this broker's: {e}"))?;
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
    // (name in the backup, directory under data_dir, has files to put back)
    let mut swaps: Vec<(&str, &str, bool)> = Vec::new();
    for store in stores {
        let (_, name, dir) = CONTROL_STORES
            .iter()
            .find(|(schema, _, _)| schema == store)
            .ok_or_else(|| format!("{store}: not a control-plane store"))?;
        if !existed.contains(store) {
            swaps.push((name, dir, false));
            continue;
        }
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
        swaps.push((name, dir, true));
    }
    let aside = data_dir.join("update.aside");
    if aside.symlink_metadata().is_ok() {
        std::fs::remove_dir_all(&aside).map_err(|e| io(&aside, e))?;
    }
    new_dir(&aside, 0o700).map_err(|e| io(&aside, e))?;
    // (live directory, where it was moved to, the restored one is in place)
    let mut done: Vec<(PathBuf, Option<PathBuf>, bool)> = Vec::new();
    let swapped = (|| {
        for (name, dir, restore) in &swaps {
            let live = data_dir.join(dir);
            let mut moved_to = None;
            if live.symlink_metadata().is_ok() {
                let to = aside.join(name);
                std::fs::rename(&live, &to).map_err(|e| io(&live, e))?;
                moved_to = Some(to);
            }
            done.push((live.clone(), moved_to, false));
            if *restore {
                if let Some(parent) = live.parent() {
                    std::fs::create_dir_all(parent).map_err(|e| io(parent, e))?;
                }
                std::fs::rename(stage.join(name), &live).map_err(|e| io(&live, e))?;
                if let Some(last) = done.last_mut() {
                    last.2 = true;
                }
            }
            if let Some(parent) = live.parent() {
                sync_dir(parent);
            }
        }
        Ok::<(), String>(())
    })();
    if let Err(e) = swapped {
        // back to what was there: the caller starts a version on it
        for (live, moved_to, placed) in done.into_iter().rev() {
            if placed {
                let _ = std::fs::remove_dir_all(&live);
            }
            if let Some(from) = moved_to {
                let _ = std::fs::rename(&from, &live);
            }
        }
        let _ = std::fs::remove_dir_all(&stage);
        return Err(e);
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
        let start = s.char_indices().rev().nth(799).map_or(0, |(i, _)| i);
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

/// The header of one tar entry.
fn tar_header(name: &str, kind: u8, mode: u32, size: u64) -> [u8; 512] {
    let mut h = [0u8; 512];
    h[..name.len().min(100)].copy_from_slice(&name.as_bytes()[..name.len().min(100)]);
    h[100..108].copy_from_slice(format!("{mode:07o}\0").as_bytes());
    h[108..116].copy_from_slice(b"0000000\0");
    h[116..124].copy_from_slice(b"0000000\0");
    h[124..136].copy_from_slice(format!("{size:011o}\0").as_bytes());
    h[136..148].copy_from_slice(b"00000000000\0");
    h[148..156].copy_from_slice(b"        ");
    h[156] = kind;
    h[257..263].copy_from_slice(b"ustar\0");
    h[263..265].copy_from_slice(b"00");
    let sum: u32 = h.iter().map(|b| u32::from(*b)).sum();
    h[148..156].copy_from_slice(format!("{sum:06o}\0 ").as_bytes());
    h
}

/// Write the archive of the binary at `bin` and the small files `extras`
/// to `out` (the release tooling; streamed); its asset (file name, SHA-256,
/// size). No owner, time or mode of the build host goes into it.
pub fn pack(
    bin: &Path,
    extras: &[(&str, &[u8])],
    out: &Path,
    level: flate2::Compression,
) -> Result<Asset, String> {
    let size = std::fs::metadata(bin).map_err(|e| io(bin, e))?.len();
    if size == 0 || size > MAX_BINARY {
        return Err(format!("{}: 1 to {MAX_BINARY} bytes", bin.display()));
    }
    for (name, data) in extras {
        if !plain_name(name, 64) || *name == BIN || data.len() as u64 > MAX_EXTRA {
            return Err(format!("{name}: not a small file with a plain name"));
        }
    }
    let f = std::fs::File::create(out).map_err(|e| io(out, e))?;
    let mut gz = flate2::GzBuilder::new().mtime(0).write(f, level);
    let werr = |e: std::io::Error| io(out, e);
    gz.write_all(&tar_header(BIN, b'0', 0o755, size))
        .map_err(werr)?;
    let mut src = std::fs::File::open(bin).map_err(|e| io(bin, e))?;
    std::io::copy(&mut src, &mut gz).map_err(werr)?;
    gz.write_all(&vec![0u8; ((512 - size % 512) % 512) as usize])
        .map_err(werr)?;
    for (name, data) in extras {
        gz.write_all(&tar_header(name, b'0', 0o644, data.len() as u64))
            .map_err(werr)?;
        gz.write_all(data).map_err(werr)?;
        gz.write_all(&vec![0u8; (512 - data.len() % 512) % 512])
            .map_err(werr)?;
    }
    gz.write_all(&[0u8; 1024]).map_err(werr)?;
    gz.finish().map_err(werr)?.sync_all().map_err(werr)?;
    let (sha256, size) = sha256_file(out)?;
    if size > MAX_ARCHIVE {
        return Err(format!("the archive has more than {MAX_ARCHIVE} bytes"));
    }
    Ok(Asset {
        file: out
            .file_name()
            .map(|n| n.to_string_lossy().into_owned())
            .unwrap_or_default(),
        sha256,
        size,
        url: String::new(),
        bin_sha256: sha256_file(bin)?.0,
    })
}

/// Test helpers: archives of any shape, also for the e2e tests of `wyrmd`.
pub mod testkit {
    use super::*;

    /// One tar entry: a header and the padded data.
    pub fn tar_entry(name: &str, kind: u8, mode: u32, data: &[u8]) -> Vec<u8> {
        let mut out = tar_header(name, kind, mode, data.len() as u64).to_vec();
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

    /// [`pack`] without compression (a debug binary is large).
    pub fn archive_of(bin: &Path, extras: &[(&str, &[u8])], out: &Path) -> Result<Asset, String> {
        pack(bin, extras, out, flate2::Compression::none())
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
                    bin_sha256: "b".repeat(64),
                },
            )]),
        }
    }

    /// Put `bytes` in a file and name it as an asset whose binary is
    /// `b"binary"`.
    fn asset_of(dir: &Path, bytes: &[u8]) -> (PathBuf, Asset) {
        asset_with(dir, bytes, b"binary")
    }

    fn asset_with(dir: &Path, bytes: &[u8], bin: &[u8]) -> (PathBuf, Asset) {
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
                bin_sha256: hex::encode(Sha256::digest(bin)),
            },
        )
    }

    #[test]
    fn a_release_is_read_only_under_a_pinned_key() {
        let bytes = serde_json::to_vec(&release("0.2.0")).unwrap();
        let sig = sign_release(&bytes, &key(1));
        let pinned = [key(1).verifying_key()];
        assert_eq!(
            read_release(&bytes, &sig, &pinned).unwrap().version,
            "0.2.0"
        );
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

    /// The bytes of an index of `releases`, each signed by `signer`.
    fn index_bytes(releases: &[Release], signer: &SigningKey) -> Vec<u8> {
        let file = IndexFile {
            wyrmd_releases: FORMAT,
            sequence: 7,
            created: "2026-11-13".into(),
            releases: releases
                .iter()
                .map(|r| {
                    let doc = serde_json::to_string(r).unwrap();
                    IndexEntry {
                        signature: sign_release(doc.as_bytes(), signer),
                        release: doc,
                    }
                })
                .collect(),
        };
        serde_json::to_vec(&file).unwrap()
    }

    #[test]
    fn an_index_names_the_latest_build_of_a_target() {
        let mut other = release("0.9.0");
        other.targets = BTreeMap::from([(
            "aarch64-linux".to_owned(),
            other.targets["x86_64-linux"].clone(),
        )]);
        let all = [release("0.2.0"), release("0.10.0"), release("0.3.0"), other];
        let bytes = index_bytes(&all, &key(1));
        let pinned = [key(1).verifying_key()];
        let read = read_index(&bytes, &sign_index(&bytes, &key(1)), &pinned).unwrap();
        let version = |t: &str| read.latest(t).map(|s| s.release.version.clone());
        assert_eq!(version("x86_64-linux").as_deref(), Some("0.10.0"));
        assert_eq!(version("aarch64-linux").as_deref(), Some("0.9.0"));
        assert!(read.latest("riscv64-linux").is_none());
        assert!(read_index(&bytes, &sign_release(&bytes, &key(1)), &pinned).is_err());
        // written again it is the same file
        assert_eq!(serde_json::to_vec(&read.to_file().unwrap()).unwrap(), bytes);
    }

    /// A signature of the list does not make its entries trusted: each
    /// entry is a release document under its own signature.
    #[test]
    fn an_index_entry_is_trusted_only_by_its_own_signature() {
        let pinned = [key(1).verifying_key()];
        // the list is signed by the pinned key, one entry by another key:
        // what a signer does who signs an index it did not check
        let mut file: IndexFile =
            serde_json::from_slice(&index_bytes(&[release("0.2.0")], &key(1))).unwrap();
        let planted = serde_json::to_string(&release("9.9.9")).unwrap();
        file.releases.push(IndexEntry {
            signature: sign_release(planted.as_bytes(), &key(2)),
            release: planted.clone(),
        });
        let bytes = serde_json::to_vec(&file).unwrap();
        let err = read_index(&bytes, &sign_index(&bytes, &key(1)), &pinned).unwrap_err();
        assert!(err.contains("an entry is refused"), "{err}");
        // an entry without a signature, and one whose text was changed
        file.releases[1].signature = String::new();
        let bytes = serde_json::to_vec(&file).unwrap();
        assert!(read_index(&bytes, &sign_index(&bytes, &key(1)), &pinned).is_err());
        file.releases.pop();
        file.releases[0].release = file.releases[0].release.replace("0.2.0", "0.2.1");
        let bytes = serde_json::to_vec(&file).unwrap();
        assert!(read_index(&bytes, &sign_index(&bytes, &key(1)), &pinned).is_err());
        // the same version twice
        let bytes = index_bytes(&[release("0.2.0"), release("0.2.0")], &key(1));
        let err = read_index(&bytes, &sign_index(&bytes, &key(1)), &pinned).unwrap_err();
        assert!(err.contains("twice"), "{err}");
        // adding a release needs that release's own signature
        let good = index_bytes(&[release("0.2.0")], &key(1));
        let index = read_index(&good, &sign_index(&good, &key(1)), &pinned).unwrap();
        let doc = serde_json::to_vec(&release("0.3.0")).unwrap();
        let err = index
            .clone()
            .with(&doc, &sign_release(&doc, &key(2)), &pinned, "")
            .unwrap_err();
        assert!(err.contains("pinned release key"), "{err}");
        let more = index
            .with(&doc, &sign_release(&doc, &key(1)), &pinned, "2026-11-14")
            .unwrap();
        assert_eq!(more.releases.len(), 2);
        assert_eq!((more.sequence, more.created.as_str()), (8, "2026-11-14"));
        // a release of the same version replaces the entry
        let again = more
            .with(&doc, &sign_release(&doc, &key(1)), &pinned, "")
            .unwrap();
        assert_eq!(again.releases.len(), 2);
        assert_eq!(again.sequence, 9);
    }

    /// An index carries a sequence: a host refuses one older than it has
    /// read, so an old, validly signed index that is put back hides nothing.
    #[test]
    fn an_older_index_than_one_read_is_refused() {
        let d = scratch("sequence");
        let pinned = [key(1).verifying_key()];
        let bytes = index_bytes(&[release("0.2.0")], &key(1));
        let sig = sign_index(&bytes, &key(1));
        // the channel file holds both; a changed index in it is refused
        let channel = bundle(&bytes, &sig).unwrap();
        let index = read_channel(&channel, &pinned).unwrap();
        assert_eq!(index.sequence, 7);
        let mut c: Channel = serde_json::from_slice(&channel).unwrap();
        c.index = c.index.replace("\"sequence\":7", "\"sequence\":9");
        assert!(read_channel(&serde_json::to_vec(&c).unwrap(), &pinned).is_err());
        assert!(read_channel(b"{}", &pinned).is_err());
        // an index without a sequence is none
        let mut file: IndexFile = serde_json::from_slice(&bytes).unwrap();
        file.sequence = 0;
        let zero = serde_json::to_vec(&file).unwrap();
        assert!(read_index(&zero, &sign_index(&zero, &key(1)), &pinned)
            .unwrap_err()
            .contains("sequence"));
        // what a host has read
        assert_eq!(seen_sequence(&d), 0);
        note_sequence(&d, 7).unwrap();
        note_sequence(&d, 7).unwrap();
        note_sequence(&d, 9).unwrap();
        assert_eq!(seen_sequence(&d), 9);
        let err = note_sequence(&d, 8).unwrap_err();
        assert!(err.contains("older than one this broker has read"), "{err}");
        assert_eq!(seen_sequence(&d), 9);
        let _ = std::fs::remove_dir_all(&d);
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
        assert!(
            bad(&|r| r.targets.get_mut(t).unwrap().file = "../x.tar.gz".into()).contains("file")
        );
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
        // a store this version cannot put back after a failed update
        let mut r = release("0.2.0");
        r.schemas.insert("ledger".into(), 1);
        let err = r.compatible(&me).unwrap_err();
        assert!(
            err.contains("\"ledger\"") && err.contains("by hand"),
            "{err}"
        );
        let mut odd = me.clone();
        odd.schemas.insert("ledger".into(), 1);
        assert!(r.compatible(&odd).is_err());
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
        let (path, asset) = asset_with(&d, &gz, b"#!/bin/sh\nexit 0\n");
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
            assert!(
                !versions.join("0.2.0").exists(),
                "{name}: a version is there"
            );
            assert!(
                !versions.join(".0.2.0.part").exists(),
                "{name}: a part is left"
            );
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
        let mut gz = flate2::write::GzEncoder::new(Vec::new(), flate2::Compression::fast());
        gz.write_all(&[good.clone(), vec![0u8; 1024], b"#!/bin/sh".to_vec()].concat())
            .unwrap();
        let tail = gz.finish().unwrap();
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

    #[test]
    fn a_packed_archive_unpacks_to_the_same_binary() {
        let d = scratch("pack");
        let bin = d.join("built");
        let bytes: Vec<u8> = (0..70_000u32).map(|i| (i % 251) as u8).collect();
        std::fs::write(&bin, &bytes).unwrap();
        let out = d.join("wyrmd-0.2.0-x86_64-linux.tar.gz");
        let level = flate2::Compression::default();
        let asset = pack(&bin, &[("LICENSE", b"Apache-2.0")], &out, level).unwrap();
        assert_eq!(asset.file, "wyrmd-0.2.0-x86_64-linux.tar.gz");
        // the same input gives the same archive (no time, no owner in it)
        let again = pack(
            &bin,
            &[("LICENSE", b"Apache-2.0")],
            &d.join("again.tar.gz"),
            level,
        )
        .unwrap();
        assert_eq!(again.sha256, asset.sha256);
        let unpacked = unpack(&out, &asset, &d.join("versions"), "0.2.0").unwrap();
        assert_eq!(std::fs::read(unpacked).unwrap(), bytes);
        assert!(pack(&bin, &[("../x", b"")], &out, level).is_err());
        assert!(pack(&bin, &[("wyrmd", b"")], &out, level).is_err());
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
        let run = || guard(&l, &data, "0.1.0", None).unwrap();
        // nothing to do without an update
        assert_eq!(run(), Guarded::Nothing);
        assert!(guard_stamp(&data).is_some_and(|t| t + 5 >= now_s()));
        let trial = |f: &dyn Fn(&mut UpdateFile)| {
            l.switch("0.2.0").unwrap();
            let mut u = UpdateFile {
                from: "0.1.0".into(),
                to: "0.2.0".into(),
                state: "trial".into(),
                trial_s: 180,
                ..Default::default()
            };
            f(&mut u);
            u.save(&data).unwrap();
        };
        // a trial that goes on is left alone, and its starts are counted:
        // the new version gets three, also when it cannot even start
        trial(&|_| {});
        for n in 1..=MAX_ATTEMPTS {
            assert_eq!(run(), Guarded::Nothing);
            assert_eq!(UpdateFile::load(&data).unwrap().attempts, n);
            assert_eq!(l.current_version().as_deref(), Some("0.2.0"));
        }
        assert!(matches!(run(), Guarded::RolledBack { .. }));
        assert_eq!(l.current_version().as_deref(), Some("0.1.0"));
        // the two reasons
        for (name, f) in [
            (
                "attempts",
                (&|u: &mut UpdateFile| u.attempts = 3) as &dyn Fn(&mut UpdateFile),
            ),
            ("gave up", &|u: &mut UpdateFile| {
                u.failed = "link plc1 is not back".into()
            }),
        ] {
            trial(f);
            let r = run();
            assert!(
                matches!(&r, Guarded::RolledBack { from, restored: false, .. } if from == "0.1.0"),
                "{name}: {r:?}"
            );
            assert_eq!(l.current_version().as_deref(), Some("0.1.0"), "{name}");
            let u = UpdateFile::load(&data).unwrap();
            assert_eq!(u.state, "rolled_back", "{name}");
            assert!(!u.reason.is_empty() && !u.audited, "{name}");
        }
        // a confirmed update is rolled back only when asked
        trial(&|u| u.state = "confirmed".into());
        assert_eq!(run(), Guarded::Nothing);
        assert_eq!(l.current_version().as_deref(), Some("0.2.0"));
        trial(&|u| {
            u.state = "confirmed".into();
            u.rollback = "user:ann".into();
        });
        assert!(matches!(run(), Guarded::RolledBack { .. }));
        assert_eq!(
            UpdateFile::load(&data).unwrap().reason,
            "rolled back by user:ann"
        );
        // the old version is gone: the new one stays, and that is said
        trial(&|u| u.attempts = 3);
        std::fs::rename(l.versions().join("0.1.0"), d.join("away")).unwrap();
        assert!(matches!(run(), Guarded::Stuck(_)));
        assert_eq!(l.current_version().as_deref(), Some("0.2.0"));
        let u = UpdateFile::load(&data).unwrap();
        assert_eq!(u.state, "failed");
        assert!(u.reason.contains("wyrmd 0.2.0 stays"), "{}", u.reason);
        let _ = std::fs::remove_dir_all(&d);
    }

    /// The clock decides nothing in a trial: a host that was off for longer
    /// than the trial comes back into the trial it left.
    #[cfg(unix)]
    #[test]
    fn downtime_is_not_a_failed_trial() {
        let d = scratch("guard-clock");
        let exe = d.join("built");
        std::fs::write(&exe, b"v1").unwrap();
        let l = Layout::install(&d.join("opt"), &exe, "0.1.0").unwrap();
        std::fs::create_dir_all(l.versions().join("0.2.0")).unwrap();
        std::fs::write(l.bin_of("0.2.0"), b"v2").unwrap();
        l.switch("0.2.0").unwrap();
        let data = d.join("data");
        std::fs::create_dir_all(&data).unwrap();
        // one start, 40 s of 180 run, then the host was off for a week
        // (or its clock jumped a year ahead): the estimate is long past
        for deadline in [now_s() - 7 * 86_400, 1, now_s() + 400 * 86_400] {
            UpdateFile {
                from: "0.1.0".into(),
                to: "0.2.0".into(),
                state: "trial".into(),
                attempts: 1,
                trial_s: 180,
                ran_s: 40,
                deadline,
                started: now_s() - 8 * 86_400,
                from_schemas: BTreeMap::from([("registry".into(), 20)]),
                to_schemas: BTreeMap::from([("registry".into(), 21)]),
                ..Default::default()
            }
            .save(&data)
            .unwrap();
            assert_eq!(guard(&l, &data, "0.1.0", None).unwrap(), Guarded::Nothing);
            let u = UpdateFile::load(&data).unwrap();
            assert_eq!((u.state.as_str(), u.attempts, u.ran_s), ("trial", 2, 40));
            assert_eq!(l.current_version().as_deref(), Some("0.2.0"));
        }
        let _ = std::fs::remove_dir_all(&d);
    }

    /// The old version and the pre-update backup do not go because a clock
    /// without a battery showed a late time once.
    #[test]
    fn one_reading_of_the_clock_removes_nothing() {
        let keep_until = 1_000_000;
        let confirmed = || UpdateFile {
            state: "confirmed".into(),
            keep_until,
            ..Default::default()
        };
        // in time: nothing, however often
        let mut u = confirmed();
        assert!(!u.expire(keep_until, true, 0));
        assert!(!u.expire(keep_until - 5, false, 99_999));
        // one start with the clock years ahead: counted, nothing removed
        let mut u = confirmed();
        assert!(!u.expire(keep_until + 10 * 365 * 86_400, true, 0));
        assert_eq!(u.expired_starts, 1);
        // the clock is right again: forgotten
        assert!(!u.expire(keep_until - 1, true, 0));
        assert_eq!(u.expired_starts, 0);
        // past at two starts
        assert!(!u.expire(keep_until + 1, true, 0));
        assert!(u.expire(keep_until + 2, true, 0));
        // or for a full hour of one run (the hourly look does not count starts)
        let mut u = confirmed();
        assert!(!u.expire(keep_until + 1, true, 0));
        assert!(!u.expire(keep_until + 1800, false, 1800));
        assert_eq!(u.expired_starts, 1);
        assert!(u.expire(keep_until + 3601, false, 3600));
        // never during a trial, whatever the clock says
        let mut u = UpdateFile {
            state: "trial".into(),
            keep_until: 0,
            ..Default::default()
        };
        assert!(!u.expire(u64::MAX, true, u64::MAX));
        assert!(!u.expire(u64::MAX, true, u64::MAX));
        // nor after a rollback that could not be done
        u.state = "failed".into();
        assert!(!u.expire(u64::MAX, true, u64::MAX));
        // a rollback keeps nothing
        u.state = "rolled_back".into();
        assert!(u.expire(0, false, 0));
    }

    /// After a rollback the guard does not leave the broker on a version
    /// that does not come up: three starts, then the other one.
    #[cfg(unix)]
    #[test]
    fn a_version_that_does_not_come_up_after_a_rollback_is_changed() {
        let d = scratch("guard-starts");
        let exe = d.join("built");
        std::fs::write(&exe, b"v1").unwrap();
        let l = Layout::install(&d.join("opt"), &exe, "0.1.0").unwrap();
        std::fs::create_dir_all(l.versions().join("0.2.0")).unwrap();
        std::fs::write(l.bin_of("0.2.0"), b"v2").unwrap();
        l.switch("0.2.0").unwrap();
        let data = d.join("data");
        std::fs::create_dir_all(&data).unwrap();
        // the update moved a SCHEMA and its backup is gone: the old version
        // is started all the same, on the state as it is
        UpdateFile {
            from: "0.1.0".into(),
            to: "0.2.0".into(),
            state: "trial".into(),
            failed: "link plc1 is not back".into(),
            from_schemas: BTreeMap::from([("registry".into(), 20)]),
            to_schemas: BTreeMap::from([("registry".into(), 21)]),
            stores: vec!["registry".into()],
            backup: "site-x.wyrm-backup".into(),
            backup_sha256: "0".repeat(64),
            ..Default::default()
        }
        .save(&data)
        .unwrap();
        let run = || guard(&l, &data, "0.1.0", None).unwrap();
        let r = run();
        assert!(
            matches!(&r, Guarded::Stuck(why) if why.contains("was not restored")),
            "{r:?}"
        );
        assert_eq!(l.current_version().as_deref(), Some("0.1.0"));
        let u = UpdateFile::load(&data).unwrap();
        assert_eq!(u.state, "failed");
        assert!(
            u.reason
                .contains("wyrmd 0.1.0 runs on the state wyrmd 0.2.0 left"),
            "{}",
            u.reason
        );
        assert!(!u.restored && !u.settled);
        // it does not come up (it cannot read that state): three starts
        for n in 1..=MAX_ATTEMPTS {
            assert_eq!(run(), Guarded::Nothing);
            assert_eq!(UpdateFile::load(&data).unwrap().starts, n);
            assert_eq!(l.current_version().as_deref(), Some("0.1.0"));
        }
        // then the version that can read it
        let r = run();
        assert!(
            matches!(&r, Guarded::Stuck(why) if why.contains("wyrmd 0.2.0 is current")),
            "{r:?}"
        );
        assert_eq!(l.current_version().as_deref(), Some("0.2.0"));
        // and so on, three starts each, until one comes up and says so
        for _ in 0..MAX_ATTEMPTS {
            assert_eq!(run(), Guarded::Nothing);
        }
        assert!(matches!(run(), Guarded::Stuck(_)));
        assert_eq!(l.current_version().as_deref(), Some("0.1.0"));
        let mut u = UpdateFile::load(&data).unwrap();
        u.settled = true;
        u.starts = 0;
        u.save(&data).unwrap();
        for _ in 0..10 {
            assert_eq!(run(), Guarded::Nothing);
        }
        assert_eq!(l.current_version().as_deref(), Some("0.1.0"));
        assert_eq!(UpdateFile::load(&data).unwrap().starts, 0);
        let _ = std::fs::remove_dir_all(&d);
    }

    /// A broker that updates itself starts only a binary that a pinned key
    /// signed, or that was put there by hand.
    #[cfg(unix)]
    #[test]
    fn the_guard_starts_only_a_verified_binary() {
        let d = scratch("guard-verify");
        let exe = d.join("built");
        std::fs::write(&exe, b"v1").unwrap();
        let l = Layout::install(&d.join("opt"), &exe, "0.1.0").unwrap();
        let data = d.join("data");
        std::fs::create_dir_all(&data).unwrap();
        let pinned = [key(1).verifying_key()];
        let run = || guard(&l, &data, "0.1.0", Some(&pinned));
        // put there by hand: named with its hash in bin/trusted.json
        assert_eq!(run().unwrap(), Guarded::Nothing);
        l.verify("0.1.0", &pinned).unwrap();
        // a release that was unpacked: its signed document names the hash
        let signed_version = |version: &str, bin: &[u8], signer: &SigningKey, says: &str| {
            let dir = l.versions().join(version);
            let _ = std::fs::remove_dir_all(&dir);
            std::fs::create_dir_all(&dir).unwrap();
            std::fs::write(dir.join(BIN), bin).unwrap();
            let mut r = release(says);
            let asset = r.targets.remove("x86_64-linux").unwrap();
            r.targets.insert(
                target(),
                Asset {
                    bin_sha256: hex::encode(Sha256::digest(bin)),
                    ..asset
                },
            );
            let doc = serde_json::to_vec(&r).unwrap();
            keep_release(&l.versions(), version, &doc, &sign_release(&doc, signer)).unwrap();
        };
        signed_version("0.2.0", b"v2", &key(1), "0.2.0");
        l.verify("0.2.0", &pinned).unwrap();
        l.switch("0.2.0").unwrap();
        assert_eq!(run().unwrap(), Guarded::Nothing);
        assert_eq!(l.current_version().as_deref(), Some("0.2.0"));

        // the binary is replaced: not started; the other version of the
        // update, which verifies, is
        UpdateFile {
            from: "0.1.0".into(),
            to: "0.2.0".into(),
            state: "confirmed".into(),
            ..Default::default()
        }
        .save(&data)
        .unwrap();
        std::fs::write(l.bin_of("0.2.0"), b"evil").unwrap();
        assert!(l
            .verify("0.2.0", &pinned)
            .unwrap_err()
            .contains("not verified"));
        assert_eq!(run().unwrap(), Guarded::Nothing);
        assert_eq!(l.current_version().as_deref(), Some("0.1.0"));
        let u = UpdateFile::load(&data).unwrap();
        assert_eq!(u.state, "failed");
        assert!(
            u.reason.contains("not verified") && u.reason.contains("wyrmd 0.1.0 is current"),
            "{}",
            u.reason
        );
        // both replaced: nothing is started, and the guard says why
        std::fs::write(l.bin_of("0.1.0"), b"evil too").unwrap();
        let err = run().unwrap_err();
        assert!(err.contains("Nothing is started"), "{err}");
        std::fs::write(l.bin_of("0.1.0"), b"v1").unwrap();
        assert!(run().is_ok());

        // what does not make a binary verified
        let refused = |why: &str| {
            let err = l.verify("0.2.0", &pinned).unwrap_err();
            assert!(err.contains(why), "{err}");
        };
        // a release another key signed
        signed_version("0.2.0", b"v2", &key(2), "0.2.0");
        refused("pinned release key");
        // a signed release of another version beside the binary
        signed_version("0.2.0", b"v2", &key(1), "0.3.0");
        refused("of wyrmd 0.3.0");
        // no release document at all
        signed_version("0.2.0", b"v2", &key(1), "0.2.0");
        std::fs::remove_file(l.versions().join("0.2.0").join(RELEASE_DOC)).unwrap();
        refused("not verified");
        // the binary is a link to a file that would verify
        signed_version("0.2.0", b"v2", &key(1), "0.2.0");
        std::fs::rename(l.bin_of("0.2.0"), d.join("real")).unwrap();
        std::os::unix::fs::symlink(d.join("real"), l.bin_of("0.2.0")).unwrap();
        refused("not a plain file");
        // no key pinned: nothing signed is trusted (the hand-put one still is)
        std::fs::remove_file(l.bin_of("0.2.0")).unwrap();
        std::fs::rename(d.join("real"), l.bin_of("0.2.0")).unwrap();
        assert!(l.verify("0.2.0", &[]).is_err());
        l.verify("0.1.0", &[]).unwrap();

        // the guard a root step keeps: the verified binary of the current
        // version, read once
        l.switch("0.2.0").unwrap();
        assert!(l.refresh_guard_verified(&pinned).unwrap());
        assert_eq!(std::fs::read(l.guard()).unwrap(), b"v2");
        assert!(
            !l.refresh_guard_verified(&pinned).unwrap(),
            "already that binary"
        );
        std::fs::write(l.bin_of("0.2.0"), b"evil").unwrap();
        assert!(l.refresh_guard_verified(&pinned).is_err());
        assert_eq!(
            std::fs::read(l.guard()).unwrap(),
            b"v2",
            "the guard is left"
        );
        let _ = std::fs::remove_dir_all(&d);
    }

    /// The archive may not bring the files the broker keeps beside the
    /// binary, and the binary must be the one the signed release names.
    #[test]
    fn the_binary_in_an_archive_is_the_one_the_release_names() {
        let d = scratch("binhash");
        let versions = d.join("versions");
        let good = tar_entry("wyrmd", b'0', 0o755, b"binary");
        // the archive is the one of the release, the binary in it is not
        let (path, mut asset) = asset_of(&d, &tar_gz(std::slice::from_ref(&good)));
        asset.bin_sha256 = "0".repeat(64);
        let err = unpack(&path, &asset, &versions, "0.2.0").unwrap_err();
        assert!(err.contains("binary in the archive"), "{err}");
        assert!(!versions.join("0.2.0").exists() && !versions.join(".0.2.0.part").exists());
        for name in [RELEASE_DOC, RELEASE_SIG] {
            let entries = [good.clone(), tar_entry(name, b'0', 0o644, b"{}")];
            let (path, asset) = asset_of(&d, &tar_gz(&entries));
            let err = unpack(&path, &asset, &versions, "0.2.0").unwrap_err();
            assert!(err.contains("a file the broker writes"), "{err}");
        }
        // a release without the binary's hash is no release
        let mut r = release("0.2.0");
        r.targets.get_mut("x86_64-linux").unwrap().bin_sha256 = String::new();
        assert!(r.check().unwrap_err().contains("bin_sha256"));
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
        let out = run_binary(&script, &["a b; echo x".into()], t)
            .await
            .unwrap();
        assert_eq!(out.trim(), "env:none:a b; echo x");
        let err = run_binary(&script, &["bad".into()], t).await.unwrap_err();
        assert!(err.contains("broken"), "{err}");
        let err = run_binary(
            &script,
            &["slow".into()],
            std::time::Duration::from_millis(300),
        )
        .await
        .unwrap_err();
        assert!(err.contains("no answer"), "{err}");
        let _ = std::fs::remove_dir_all(&d);
    }
}
