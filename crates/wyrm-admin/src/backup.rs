//! The backup file format (ADR 0048 §3.1): `.wyrm-backup` for a broker,
//! `.wyrm-link` for one link. A zip whose first entry is `manifest.json`:
//!
//! ```text
//! manifest.json            wyrm_backup 1, kind, site, broker, created, schemas,
//!                          sealed, link?, sections[{name, info, files[{path, size, sha256, sealed, exec}]}]
//! <section>/<path>         every file a section lists, and no other entry
//! ```
//!
//! * `size` and `sha256` are of the bytes as stored in the zip (the sealed
//!   form of a sealed file), so a file is checked without any key.
//! * A sealed file never holds its content in clear. It is a stream of
//!   parts of at most 1 MiB, each ChaCha20-Poly1305 under a key of its own
//!   file: `"WYBS1" | (len u32 BE | seal(index u64 BE | last u8 | data))*`,
//!   `key = SHA-256("wyrm-backup-file" | 0 | master | path)`. A part moved
//!   to another place or file, or a stream cut short, does not open.
//! * The master key is `Argon2id(passphrase, salt)` with the parameters in
//!   `sealed` (`how: "passphrase"`), or derived from the broker's
//!   `secrets.key` (`how: "broker"`: restore points and pre-update backups,
//!   which only the same broker opens). `sealed.check` tells a wrong
//!   passphrase before anything is read.
//!
//! * A sealed backup (`passphrase` or `broker`) has a random `sealed.id`,
//!   mixed into every file key (a sealed part of another backup under the
//!   same passphrase does not open here), and `sealed.mac`: HMAC-SHA-256
//!   over the whole manifest (every path, size, SHA-256, `sealed` and
//!   `exec` flag, every `info`) under a key from the master key and the id.
//!   The only way to a [`MasterKey`] for reading is [`Manifest::key`], which
//!   checks that MAC: who holds the key holds an authentic manifest.
//! * The reader, not the file, says what must be sealed ([`must_be_sealed`]):
//!   every file of `keys`, a link's `secrets`, `token` and `files/**` in
//!   `links`, and every file of a link backup's `data`. A manifest that
//!   lists one of them as not sealed is refused.
//!
//! The reader takes nothing on trust: the entry count, every path, every
//! size and the sum of sizes are bounded and checked against the manifest
//! before a byte is written anywhere, and each file is hashed as it is read.
//!
//! `serde_json` is used here because a backup is a user file (principle 5).

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, BTreeSet};
use std::fs::File;
use std::io::{Read, Seek, Write};
use std::path::{Path, PathBuf};
use zeroize::Zeroizing;

/// `wyrm_backup` of the manifests this code writes and reads.
pub const VERSION: u32 = 1;
/// Name of the first entry.
pub const MANIFEST: &str = "manifest.json";
/// File extension of a broker backup.
pub const EXT_BROKER: &str = "wyrm-backup";
/// File extension of a link backup.
pub const EXT_LINK: &str = "wyrm-link";
/// Most entries in one file.
pub const MAX_ENTRIES: usize = 100_000;
/// Largest `manifest.json`.
pub const MAX_MANIFEST: u64 = 16 << 20;
/// Longest path of an entry, and the most segments in it.
pub const MAX_PATH: usize = 512;
pub const MAX_DEPTH: usize = 24;
/// Largest file [`Reader::read`] returns in memory.
pub const MAX_IN_MEMORY: u64 = 64 << 20;
/// Largest single file of a backup (a history day file is the largest kind).
pub const MAX_FILE: u64 = 1 << 40;
/// Plain bytes in one part of a sealed file.
pub const SEAL_PART: usize = 1 << 20;

const SEAL_MAGIC: &[u8; 5] = b"WYBS1";
const CHECK_TEXT: &[u8] = b"wyrm-backup-check";
const SALT_LEN: usize = 16;
const ID_LEN: usize = 16;
/// Stored bytes a backup may declare for each byte of its own file, and what
/// it may declare beyond that: a small upload cannot open into tens of GiB
/// (deflate reaches 1000:1 on zeros; real stores stay far below this).
pub const MAX_RATIO: u64 = 200;
pub const RATIO_SLACK: u64 = 64 << 20;
/// Most bytes of one package in a backup: what an install unpacks.
pub const MAX_PACKAGE: u64 = crate::packages::MAX_UNPACKED;
/// Most bytes of one flow artifact (an upload of `put_artifact`).
pub const MAX_ARTIFACT: u64 = 64 << 20;
/// Most bytes of one link's private data: what a link backup takes.
pub const MAX_LINK_DATA: u64 = 8 << 30;

/// The most Argon2id work a manifest may ask of this host: the key is
/// derived before the manifest's MAC can be checked, so the parameters are
/// an unauthenticated input. A broker writes the crate's defaults (19 MiB,
/// 2 passes, 1 lane); the reference board has 2 GB.
pub const MAX_KDF_KIB: u32 = 128 << 10;
pub const MAX_KDF_T: u32 = 4;
pub const MAX_KDF_P: u32 = 4;

/// `true` for a path whose file holds secrets and so must be sealed in a
/// backup of `kind`, whatever its manifest says: all of `keys`; in `links`
/// each link's `secrets`, `token` and `files/**` (its private data); all of
/// a link backup's `data`. Everything else holds no secret by construction
/// (`link.cbor` carries no token hash, params are linted at install).
pub fn must_be_sealed(kind: Kind, path: &str) -> bool {
    let segs: Vec<&str> = path.split('/').collect();
    matches!(
        (kind, segs.as_slice()),
        (Kind::Broker, ["keys", ..])
            | (Kind::Broker, ["links", _, "secrets" | "token"])
            | (Kind::Broker, ["links", _, "files", ..])
            | (Kind::Link, ["data", ..])
    )
}

/// The sections of a broker backup (ADR 0048 §3.2).
pub const BROKER_SECTIONS: [&str; 8] = [
    "control",
    "keys",
    "dataflows",
    "storage",
    "history",
    "links",
    "packages",
    "config",
];
/// The sections of a link backup (ADR 0048 §3.5).
pub const LINK_SECTIONS: [&str; 4] = ["settings", "data", "package", "history"];

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Kind {
    Broker,
    Link,
}

impl Kind {
    pub fn name(self) -> &'static str {
        match self {
            Kind::Broker => "broker",
            Kind::Link => "link",
        }
    }

    pub fn extension(self) -> &'static str {
        match self {
            Kind::Broker => EXT_BROKER,
            Kind::Link => EXT_LINK,
        }
    }

    pub fn sections(self) -> &'static [&'static str] {
        match self {
            Kind::Broker => &BROKER_SECTIONS,
            Kind::Link => &LINK_SECTIONS,
        }
    }
}

/// Argon2id parameters of a passphrase-sealed file.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Kdf {
    /// `argon2id`.
    pub name: String,
    /// Hex, 16 bytes.
    pub salt: String,
    pub m_kib: u32,
    pub t: u32,
    pub p: u32,
}

/// How the sealed files of a backup are sealed.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Sealed {
    /// `none` (no sealed file), `passphrase` or `broker`.
    pub how: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub kdf: Option<Kdf>,
    /// Hex of a constant sealed under the master key: opens only with it.
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub check: String,
    /// Hex, 16 random bytes of this backup: part of every file key and of
    /// the MAC key. Empty only with `how: none`.
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub id: String,
    /// Hex HMAC-SHA-256 of the manifest (this field empty) under the
    /// master key and `id`. Empty only with `how: none`.
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub mac: String,
}

/// The link of a link backup.
#[derive(Debug, Clone, PartialEq, Eq, Default, Serialize, Deserialize)]
pub struct LinkInfo {
    pub id: String,
    pub driver: String,
    pub mode: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub package: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub version: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct FileEntry {
    /// Path in the zip: `<section>/…`.
    pub path: String,
    /// Bytes as stored.
    pub size: u64,
    /// SHA-256 (hex) of the bytes as stored.
    pub sha256: String,
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub sealed: bool,
    /// The owner may execute it (a package's entry).
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub exec: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Section {
    pub name: String,
    /// What the section holds, for people and for the restore check (the
    /// LSN of a WAL, the revision of the storage, the days of history, …).
    #[serde(default, skip_serializing_if = "serde_json::Map::is_empty")]
    pub info: serde_json::Map<String, serde_json::Value>,
    pub files: Vec<FileEntry>,
}

impl Section {
    /// Stored bytes of the section's files.
    /// `u64::MAX` when the sum does not fit (no bound then admits it;
    /// [`Manifest::check`] refuses such a manifest).
    pub fn size(&self) -> u64 {
        self.files
            .iter()
            .try_fold(0u64, |a, f| a.checked_add(f.size))
            .unwrap_or(u64::MAX)
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Manifest {
    pub wyrm_backup: u32,
    pub kind: Kind,
    pub site: String,
    /// Version of the broker that made it.
    pub broker: String,
    /// RFC 3339, UTC.
    pub created: String,
    /// `State::SCHEMA` of the control-plane stores: registry, users, flows, audit.
    pub schemas: BTreeMap<String, u32>,
    pub sealed: Sealed,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub link: Option<LinkInfo>,
    pub sections: Vec<Section>,
}

impl Manifest {
    pub fn section(&self, name: &str) -> Option<&Section> {
        self.sections.iter().find(|s| s.name == name)
    }

    /// Stored bytes of every file.
    /// `u64::MAX` when the sum does not fit, as [`Section::size`].
    pub fn size(&self) -> u64 {
        self.sections
            .iter()
            .flat_map(|s| s.files.iter())
            .try_fold(0u64, |a, f| a.checked_add(f.size))
            .unwrap_or(u64::MAX)
    }

    /// The bytes the MAC covers: this manifest with `sealed.mac` empty.
    fn mac_text(&self) -> Result<Vec<u8>, String> {
        let mut m = self.clone();
        m.sealed.mac.clear();
        serde_json::to_vec(&m).map_err(|e| e.to_string())
    }

    /// The master key of this backup's sealed files: from `passphrase`
    /// (`how: passphrase`) or from this broker's `secrets_key` (`how:
    /// broker`). `Err` for a wrong passphrase, another broker's file, or a
    /// manifest changed since the backup was made (any path, size, digest
    /// or flag): the key is handed out only for an authentic manifest.
    pub fn key(
        &self,
        passphrase: Option<&[u8]>,
        secrets_key: Option<&[u8]>,
    ) -> Result<MasterKey, String> {
        let key = self.sealed.master(passphrase, secrets_key)?;
        let mac = hex::decode(&self.sealed.mac).map_err(|_| "manifest: sealed.mac: hex")?;
        ring::hmac::verify(&key.mac_key(), &self.mac_text()?, &mac).map_err(|_| {
            "the manifest was changed after the backup was made (its MAC does not match)".to_owned()
        })?;
        Ok(key)
    }

    /// The bounds of what one part of a backup may open into, known before
    /// a byte is extracted (ADR 0048 §3.1): each package, each flow
    /// artifact, each link's private data. A sealed file is a little longer
    /// than its content, so each bound has that much room.
    pub fn caps(&self) -> Result<(), String> {
        let room = |cap: u64| cap + cap / 1024 + 4096;
        let mut groups: BTreeMap<(&str, &str), u64> = BTreeMap::new();
        for f in self.sections.iter().flat_map(|s| &s.files) {
            let segs: Vec<&str> = f.path.split('/').collect();
            let group = match (self.kind, segs.as_slice()) {
                (Kind::Broker, ["packages", name, ..]) => ("package", *name),
                (Kind::Broker, ["links", id, "files", ..]) => ("link data", *id),
                (Kind::Link, ["package", ..]) => ("package", ""),
                (Kind::Broker, ["dataflows", "artifacts", ..]) => {
                    if f.size > room(MAX_ARTIFACT) {
                        return Err(format!(
                            "{}: {} bytes (a flow artifact has at most {MAX_ARTIFACT})",
                            f.path, f.size
                        ));
                    }
                    continue;
                }
                _ => continue,
            };
            let sum = groups.entry(group).or_default();
            *sum = sum.saturating_add(f.size);
        }
        for ((what, name), size) in groups {
            let cap = match what {
                "package" => MAX_PACKAGE,
                _ => MAX_LINK_DATA,
            };
            if size > room(cap) {
                return Err(format!(
                    "the {what} {name} of the backup holds {size} bytes (at most {cap})"
                ));
            }
        }
        Ok(())
    }

    /// Check what a manifest alone can show: version, section names of its
    /// kind (each once), every path under its section and well formed, no
    /// path twice, digests that are digests, bounded counts.
    pub fn check(&self) -> Result<(), String> {
        if self.wyrm_backup != VERSION {
            return Err(format!(
                "wyrm_backup {}: this broker reads version {VERSION}",
                self.wyrm_backup
            ));
        }
        wyrm_core::keyspace::validate_segment(&self.site)
            .map_err(|e| format!("manifest: site: {e}"))?;
        if !matches!(self.sealed.how.as_str(), "none" | "passphrase" | "broker") {
            return Err(format!("manifest: sealed.how {:?}", self.sealed.how));
        }
        if (self.sealed.how == "passphrase") != self.sealed.kdf.is_some() {
            return Err("manifest: sealed.kdf goes with how: passphrase".into());
        }
        let keyed = self.sealed.how != "none";
        let hex_of =
            |s: &str, len: usize| s.len() == 2 * len && s.bytes().all(|b| b.is_ascii_hexdigit());
        if keyed
            && !(hex_of(&self.sealed.id, ID_LEN)
                && hex_of(&self.sealed.mac, 32)
                && !self.sealed.check.is_empty())
        {
            return Err(
                "manifest: a sealed backup carries sealed.id, sealed.check and sealed.mac; \
                 this one is not authenticated"
                    .into(),
            );
        }
        if !keyed && !(self.sealed.id.is_empty() && self.sealed.mac.is_empty()) {
            return Err("manifest: sealed.id and sealed.mac go with a sealed backup".into());
        }
        if (self.kind == Kind::Link) != self.link.is_some() {
            return Err("manifest: link goes with kind: link".into());
        }
        let mut names = BTreeSet::new();
        let mut paths = BTreeSet::new();
        let mut count = 0usize;
        let mut total = 0u64;
        for s in &self.sections {
            if !self.kind.sections().contains(&s.name.as_str()) {
                return Err(format!(
                    "manifest: no section {:?} in a {} backup",
                    s.name,
                    self.kind.name()
                ));
            }
            if !names.insert(s.name.as_str()) {
                return Err(format!("manifest: section {} twice", s.name));
            }
            count += s.files.len();
            if count >= MAX_ENTRIES {
                return Err(format!("manifest: more than {MAX_ENTRIES} files"));
            }
            for f in &s.files {
                check_path(&f.path)?;
                if f.path.split('/').next() != Some(s.name.as_str()) || !f.path.contains('/') {
                    return Err(format!(
                        "manifest: {} is not under section {}",
                        f.path, s.name
                    ));
                }
                if f.sha256.len() != 64 || !f.sha256.bytes().all(|b| b.is_ascii_hexdigit()) {
                    return Err(format!("manifest: {}: sha256", f.path));
                }
                if f.size > MAX_FILE {
                    return Err(format!(
                        "manifest: {}: {} bytes (at most {MAX_FILE} a file)",
                        f.path, f.size
                    ));
                }
                total = total
                    .checked_add(f.size)
                    .ok_or("manifest: the sizes of its files do not add up")?;
                if must_be_sealed(self.kind, &f.path) && !f.sealed {
                    return Err(format!(
                        "manifest: {} holds secrets and is not sealed",
                        f.path
                    ));
                }
                if f.sealed && self.sealed.how == "none" {
                    return Err(format!(
                        "manifest: {} is sealed, the backup says none",
                        f.path
                    ));
                }
                if !paths.insert(f.path.as_str()) {
                    return Err(format!("manifest: {} twice", f.path));
                }
            }
        }
        Ok(())
    }
}

/// A path of an entry: relative, `/` separators, plain segments (no empty
/// one, no `.` or `..`, no `\`, `:` or control character), bounded.
pub fn check_path(path: &str) -> Result<(), String> {
    let bad = |why: &str| Err(format!("path {path:?}: {why}"));
    if path.is_empty() || path.len() > MAX_PATH {
        return bad("empty or too long");
    }
    if path == MANIFEST {
        return bad("the manifest's name");
    }
    let mut depth = 0;
    for seg in path.split('/') {
        depth += 1;
        if seg.is_empty() || seg == "." || seg == ".." {
            return bad("empty, `.` or `..` segment");
        }
        if seg.chars().any(|c| c == '\\' || c == ':' || c.is_control()) {
            return bad("`\\`, `:` or a control character");
        }
    }
    if depth > MAX_DEPTH {
        return bad("too deep");
    }
    Ok(())
}

/// The master key of a backup's sealed files.
#[derive(Clone)]
pub struct MasterKey {
    key: Zeroizing<[u8; 32]>,
    /// `sealed.id` of the backup it belongs to.
    id: Vec<u8>,
}

impl MasterKey {
    fn file_key(&self, path: &str) -> Zeroizing<[u8; 32]> {
        let mut h = Sha256::new();
        h.update(b"wyrm-backup-file\0");
        h.update(self.key.as_ref());
        h.update(&self.id);
        h.update(b"\0");
        h.update(path.as_bytes());
        Zeroizing::new(h.finalize().into())
    }

    fn mac_key(&self) -> ring::hmac::Key {
        let mut h = Sha256::new();
        h.update(b"wyrm-backup-mac\0");
        h.update(self.key.as_ref());
        h.update(&self.id);
        let k: Zeroizing<[u8; 32]> = Zeroizing::new(h.finalize().into());
        ring::hmac::Key::new(ring::hmac::HMAC_SHA256, k.as_ref())
    }

    /// The MAC of `manifest` (hex) for its `sealed.mac`.
    fn mac_of(&self, manifest: &Manifest) -> Result<String, String> {
        Ok(hex::encode(
            ring::hmac::sign(&self.mac_key(), &manifest.mac_text()?).as_ref(),
        ))
    }

    fn check(&self) -> String {
        hex::encode(wyrm_link_sdk::seal::seal(&self.key, CHECK_TEXT))
    }

    fn opens(&self, check: &str) -> bool {
        hex::decode(check)
            .ok()
            .and_then(|c| wyrm_link_sdk::seal::open(&self.key, &c))
            .is_some_and(|p| p == CHECK_TEXT)
    }
}

fn broker_key(secrets_key: &[u8], id: Vec<u8>) -> MasterKey {
    let mut h = Sha256::new();
    h.update(b"wyrm-backup-broker\0");
    h.update(secrets_key);
    MasterKey {
        key: Zeroizing::new(h.finalize().into()),
        id,
    }
}

fn argon2(kdf: &Kdf, passphrase: &[u8], id: Vec<u8>) -> Result<MasterKey, String> {
    if passphrase.len() < crate::keys::MIN_PASSPHRASE {
        return Err(format!(
            "passphrase: at least {} characters",
            crate::keys::MIN_PASSPHRASE
        ));
    }
    // a manifest is not trusted with this host's memory and time
    if kdf.name != "argon2id" || kdf.m_kib > MAX_KDF_KIB || kdf.t > MAX_KDF_T || kdf.p > MAX_KDF_P {
        return Err(format!(
            "sealed.kdf: not Argon2id within {} MiB, {MAX_KDF_T} passes, {MAX_KDF_P} lanes",
            MAX_KDF_KIB >> 10
        ));
    }
    let salt = hex::decode(&kdf.salt).map_err(|_| "sealed.kdf.salt: hex")?;
    let params = argon2::Params::new(kdf.m_kib, kdf.t, kdf.p, Some(32))
        .map_err(|e| format!("sealed.kdf: {e}"))?;
    let mut key = Zeroizing::new([0u8; 32]);
    argon2::Argon2::new(argon2::Algorithm::Argon2id, argon2::Version::V0x13, params)
        .hash_password_into(passphrase, &salt, key.as_mut())
        .map_err(|e| format!("key derivation: {e}"))?;
    Ok(MasterKey { key, id })
}

/// What seals a new backup.
pub enum Sealing<'a> {
    /// No sealed file may be added.
    None,
    /// At least [`crate::keys::MIN_PASSPHRASE`] characters.
    Passphrase(&'a [u8]),
    /// The content of the broker's `secrets.key`.
    Broker(&'a [u8]),
}

fn new_id() -> Result<Vec<u8>, String> {
    let mut id = [0u8; ID_LEN];
    getrandom::fill(&mut id).map_err(|e| format!("no randomness: {e}"))?;
    Ok(id.to_vec())
}

impl Sealing<'_> {
    /// The `sealed` of the manifest (its `mac` is set by [`write`]) and the
    /// master key (none for `None`), with a fresh id of the backup.
    pub fn start(&self) -> Result<(Sealed, Option<MasterKey>), String> {
        match self {
            Sealing::None => Ok((
                Sealed {
                    how: "none".into(),
                    kdf: None,
                    check: String::new(),
                    id: String::new(),
                    mac: String::new(),
                },
                None,
            )),
            Sealing::Passphrase(p) => {
                let mut salt = [0u8; SALT_LEN];
                getrandom::fill(&mut salt).map_err(|e| format!("no randomness: {e}"))?;
                let d = argon2::Params::default();
                let kdf = Kdf {
                    name: "argon2id".into(),
                    salt: hex::encode(salt),
                    m_kib: d.m_cost(),
                    t: d.t_cost(),
                    p: d.p_cost(),
                };
                let key = argon2(&kdf, p, new_id()?)?;
                Ok((
                    Sealed {
                        how: "passphrase".into(),
                        check: key.check(),
                        kdf: Some(kdf),
                        id: hex::encode(&key.id),
                        mac: String::new(),
                    },
                    Some(key),
                ))
            }
            Sealing::Broker(k) => {
                let key = broker_key(k, new_id()?);
                Ok((
                    Sealed {
                        how: "broker".into(),
                        kdf: None,
                        check: key.check(),
                        id: hex::encode(&key.id),
                        mac: String::new(),
                    },
                    Some(key),
                ))
            }
        }
    }
}

impl Sealed {
    /// The master key, before the manifest's MAC is checked: see
    /// [`Manifest::key`], the only way out of this module.
    fn master(
        &self,
        passphrase: Option<&[u8]>,
        secrets_key: Option<&[u8]>,
    ) -> Result<MasterKey, String> {
        let id = hex::decode(&self.id).map_err(|_| "manifest: sealed.id: hex")?;
        if id.len() != ID_LEN {
            return Err("manifest: sealed.id: 16 bytes".into());
        }
        let key = match (self.how.as_str(), &self.kdf) {
            ("passphrase", Some(kdf)) => argon2(
                kdf,
                passphrase.ok_or("passphrase: required, the backup is sealed with one")?,
                id,
            )?,
            ("broker", _) => broker_key(
                secrets_key.ok_or("the backup is sealed for the broker that made it")?,
                id,
            ),
            _ => return Err("the backup has no sealed files".into()),
        };
        if !key.opens(&self.check) {
            return Err(match self.how.as_str() {
                "passphrase" => "wrong passphrase".into(),
                _ => "the backup is sealed for another broker (its secrets.key differs)".into(),
            });
        }
        Ok(key)
    }
}

/// Seal `src` into `dst` as the sealed file `path` of a backup. Returns the
/// plain bytes read.
pub fn seal_stream(
    key: &MasterKey,
    path: &str,
    mut src: impl Read,
    mut dst: impl Write,
) -> std::io::Result<u64> {
    let fk = key.file_key(path);
    dst.write_all(SEAL_MAGIC)?;
    let mut total = 0u64;
    let mut index = 0u64;
    let mut cur = read_full(&mut src, SEAL_PART)?;
    loop {
        // one part ahead, to mark the last one
        let next = if cur.len() == SEAL_PART {
            read_full(&mut src, SEAL_PART)?
        } else {
            Vec::new()
        };
        let last = next.is_empty();
        let mut plain = Zeroizing::new(Vec::with_capacity(9 + cur.len()));
        plain.extend_from_slice(&index.to_be_bytes());
        plain.push(u8::from(last));
        plain.extend_from_slice(&cur);
        let sealed = wyrm_link_sdk::seal::seal(&fk, &plain);
        dst.write_all(&(sealed.len() as u32).to_be_bytes())?;
        dst.write_all(&sealed)?;
        total += cur.len() as u64;
        index += 1;
        if last {
            break;
        }
        cur = next;
    }
    dst.flush()?;
    Ok(total)
}

fn read_full(src: &mut impl Read, max: usize) -> std::io::Result<Vec<u8>> {
    let mut buf = vec![0u8; max];
    let mut n = 0;
    while n < max {
        match src.read(&mut buf[n..])? {
            0 => break,
            k => n += k,
        }
    }
    buf.truncate(n);
    Ok(buf)
}

/// Open the sealed file `path` from `src` into `dst`. Returns the plain
/// bytes written. `Err` for another key or path, a changed or moved part,
/// or a stream cut short; `dst` then holds parts that did open.
pub fn open_stream(
    key: &MasterKey,
    path: &str,
    mut src: impl Read,
    mut dst: impl Write,
) -> Result<u64, String> {
    let fk = key.file_key(path);
    let io = |e: std::io::Error| format!("{path}: {e}");
    let mut magic = [0u8; 5];
    src.read_exact(&mut magic).map_err(io)?;
    if &magic != SEAL_MAGIC {
        return Err(format!("{path}: not a sealed file"));
    }
    let mut total = 0u64;
    let mut index = 0u64;
    loop {
        let mut len = [0u8; 4];
        src.read_exact(&mut len)
            .map_err(|_| format!("{path}: sealed file cut short"))?;
        let len = u32::from_be_bytes(len) as usize;
        if len > SEAL_PART + 64 {
            return Err(format!("{path}: sealed part of {len} bytes"));
        }
        let mut sealed = vec![0u8; len];
        src.read_exact(&mut sealed)
            .map_err(|_| format!("{path}: sealed file cut short"))?;
        let plain = Zeroizing::new(
            wyrm_link_sdk::seal::open(&fk, &sealed)
                .ok_or_else(|| format!("{path}: does not open (wrong key, or changed)"))?,
        );
        if plain.len() < 9 || plain[..8] != index.to_be_bytes() {
            return Err(format!("{path}: sealed parts out of order"));
        }
        dst.write_all(&plain[9..]).map_err(io)?;
        total += (plain.len() - 9) as u64;
        index += 1;
        if plain[8] == 1 {
            break;
        }
    }
    let mut rest = [0u8; 1];
    if src.read(&mut rest).map_err(io)? != 0 {
        return Err(format!("{path}: bytes after the last sealed part"));
    }
    dst.flush().map_err(io)?;
    Ok(total)
}

/// Seal `plain` as the sealed file `path`, in memory.
pub fn seal_bytes(key: &MasterKey, path: &str, plain: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(plain.len() + 64);
    // writing into a Vec cannot fail
    let _ = seal_stream(key, path, plain, &mut out);
    out
}

/// Open what [`seal_bytes`] made.
pub fn open_bytes(
    key: &MasterKey,
    path: &str,
    sealed: &[u8],
) -> Result<Zeroizing<Vec<u8>>, String> {
    let mut out = Zeroizing::new(Vec::new());
    open_stream(key, path, sealed, &mut *out)?;
    Ok(out)
}

/// The head of a new backup: everything of the manifest but its sections.
#[derive(Debug, Clone)]
pub struct Head {
    pub kind: Kind,
    pub site: String,
    pub broker: String,
    pub created: String,
    pub schemas: BTreeMap<String, u32>,
    pub sealed: Sealed,
    pub link: Option<LinkInfo>,
}

/// One file staged for a backup, already in its stored form (sealed files
/// are staged sealed, with [`seal_stream`] under their `path`).
#[derive(Debug, Clone)]
pub struct Staged {
    /// Path in the zip: `<section>/…`.
    pub path: String,
    pub source: PathBuf,
    pub sealed: bool,
    pub exec: bool,
}

/// One section staged: its name, what it holds, its files.
#[derive(Debug, Clone, Default)]
pub struct StagedSection {
    pub name: String,
    pub info: serde_json::Map<String, serde_json::Value>,
    pub files: Vec<Staged>,
}

/// What [`write`] made.
#[derive(Debug, Clone)]
pub struct Written {
    pub manifest: Manifest,
    /// Bytes of the backup file.
    pub size: u64,
    /// SHA-256 (hex) of the backup file.
    pub sha256: String,
}

fn hash_file(path: &Path) -> std::io::Result<(u64, String)> {
    let mut f = File::open(path)?;
    let mut h = Sha256::new();
    let mut buf = vec![0u8; 256 << 10];
    let mut size = 0u64;
    loop {
        let n = f.read(&mut buf)?;
        if n == 0 {
            break;
        }
        h.update(&buf[..n]);
        size += n as u64;
    }
    Ok((size, hex::encode(h.finalize())))
}

/// Write the backup `out` from staged files: the manifest first, then
/// every file in manifest order. `progress(done, total)` in stored bytes.
/// The file appears under its name only when complete (`<out>.part` until
/// then) and is readable by the owner alone. `key` is the master key of
/// `head.sealed` (from [`Sealing::start`]; `None` with `how: none`): it
/// signs the manifest.
pub fn write(
    out: &Path,
    head: Head,
    sections: Vec<StagedSection>,
    key: Option<&MasterKey>,
    mut progress: impl FnMut(u64, u64),
) -> Result<Written, String> {
    use zip::write::SimpleFileOptions;
    let io = |what: &Path, e: std::io::Error| format!("{}: {e}", what.display());
    let mut manifest = Manifest {
        wyrm_backup: VERSION,
        kind: head.kind,
        site: head.site,
        broker: head.broker,
        created: head.created,
        schemas: head.schemas,
        sealed: head.sealed,
        link: head.link,
        sections: Vec::with_capacity(sections.len()),
    };
    for s in &sections {
        let mut files = Vec::with_capacity(s.files.len());
        for f in &s.files {
            let (size, sha256) = hash_file(&f.source).map_err(|e| io(&f.source, e))?;
            files.push(FileEntry {
                path: f.path.clone(),
                size,
                sha256,
                sealed: f.sealed,
                exec: f.exec,
            });
        }
        manifest.sections.push(Section {
            name: s.name.clone(),
            info: s.info.clone(),
            files,
        });
    }
    match key {
        Some(k) if manifest.sealed.how != "none" => {
            if hex::encode(&k.id) != manifest.sealed.id {
                return Err("the key is of another backup".into());
            }
            manifest.sealed.mac = k.mac_of(&manifest)?;
        }
        None if manifest.sealed.how == "none" => {}
        _ => return Err("a sealed backup is written with its key, an unsealed one without".into()),
    }
    manifest.check()?;
    let total = manifest.size();
    let text = serde_json::to_vec_pretty(&manifest).map_err(|e| e.to_string())?;
    if text.len() as u64 > MAX_MANIFEST {
        return Err("manifest: too large".into());
    }
    let part = out.with_extension(format!(
        "{}.part",
        out.extension().and_then(|e| e.to_str()).unwrap_or("zip")
    ));
    let _ = std::fs::remove_file(&part);
    let result = (|| {
        let mut opts = std::fs::OpenOptions::new();
        opts.write(true).create_new(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            opts.mode(0o600);
        }
        let file = opts.open(&part).map_err(|e| io(&part, e))?;
        let mut w = zip::ZipWriter::new(std::io::BufWriter::new(file));
        let opt = |sealed: bool, size: u64| {
            SimpleFileOptions::default()
                .compression_method(if sealed {
                    zip::CompressionMethod::Stored
                } else {
                    zip::CompressionMethod::Deflated
                })
                .last_modified_time(zip::DateTime::default())
                .large_file(size >= u32::MAX as u64)
        };
        w.start_file(MANIFEST, opt(false, text.len() as u64))
            .map_err(|e| e.to_string())?;
        w.write_all(&text).map_err(|e| io(&part, e))?;
        let mut done = 0u64;
        let mut buf = vec![0u8; 256 << 10];
        for (s, m) in sections.iter().zip(&manifest.sections) {
            for (f, e) in s.files.iter().zip(&m.files) {
                w.start_file(e.path.as_str(), opt(e.sealed, e.size))
                    .map_err(|e| e.to_string())?;
                let mut src = File::open(&f.source).map_err(|e| io(&f.source, e))?;
                // hashed again as it goes in: a source that changed since the
                // manifest was made fails the backup instead of spoiling it
                let mut h = Sha256::new();
                let mut left = e.size;
                while left > 0 {
                    let want = buf.len().min(left as usize);
                    let n = src.read(&mut buf[..want]).map_err(|e| io(&f.source, e))?;
                    if n == 0 {
                        return Err(format!("{}: changed while it was read", f.source.display()));
                    }
                    h.update(&buf[..n]);
                    w.write_all(&buf[..n]).map_err(|e| io(&part, e))?;
                    left -= n as u64;
                    done += n as u64;
                    progress(done, total);
                }
                if hex::encode(h.finalize()) != e.sha256 {
                    return Err(format!("{}: changed while it was read", f.source.display()));
                }
            }
        }
        let inner = w.finish().map_err(|e| e.to_string())?;
        let file = inner.into_inner().map_err(|e| e.to_string())?;
        file.sync_all().map_err(|e| io(&part, e))?;
        Ok(())
    })();
    if let Err(e) = result {
        let _ = std::fs::remove_file(&part);
        return Err(e);
    }
    let (size, sha256) = hash_file(&part).map_err(|e| io(&part, e))?;
    std::fs::rename(&part, out).map_err(|e| io(out, e))?;
    Ok(Written {
        manifest,
        size,
        sha256,
    })
}

/// A backup file opened and checked against its manifest (see the module
/// documentation): every entry is listed, every listed file is there with
/// its size. File contents are hashed when they are read.
pub struct Reader<R: Read + Seek = File> {
    zip: zip::ZipArchive<R>,
    manifest: Manifest,
    files: BTreeMap<String, FileEntry>,
}

impl Reader<File> {
    /// Open the backup at `path`; its files may hold `max_total` stored
    /// bytes in all.
    pub fn open(path: &Path, max_total: u64) -> Result<Self, String> {
        let f = File::open(path).map_err(|e| format!("{}: {e}", path.display()))?;
        Self::new(f, max_total)
    }
}

impl<R: Read + Seek> Reader<R> {
    pub fn new(mut src: R, max_total: u64) -> Result<Self, String> {
        let len = src
            .seek(std::io::SeekFrom::End(0))
            .map_err(|e| format!("not a backup: {e}"))?;
        let mut zip = zip::ZipArchive::new(src).map_err(|e| format!("not a backup: {e}"))?;
        if zip.is_empty() || zip.len() > MAX_ENTRIES {
            return Err(format!(
                "not a backup: {} entries (1 to {MAX_ENTRIES})",
                zip.len()
            ));
        }
        let manifest: Manifest = {
            let first = zip.by_index(0).map_err(|e| format!("not a backup: {e}"))?;
            if first.name().ok().as_deref() != Some(MANIFEST) {
                return Err(format!("not a backup: the first entry is not {MANIFEST}"));
            }
            if first.size() > MAX_MANIFEST {
                return Err("manifest: too large".into());
            }
            let mut text = Vec::new();
            first
                .take(MAX_MANIFEST + 1)
                .read_to_end(&mut text)
                .map_err(|e| format!("manifest: {e}"))?;
            if text.len() as u64 > MAX_MANIFEST {
                return Err("manifest: too large".into());
            }
            serde_json::from_slice(&text).map_err(|e| format!("manifest: {e}"))?
        };
        manifest.check()?;
        if manifest.size() > max_total {
            return Err(format!(
                "the backup holds {} bytes; at most {max_total} are taken here",
                manifest.size()
            ));
        }
        // before anything is extracted: what the file says it opens into
        // is bounded by its own size and by what each part may be
        if manifest.size() > len.saturating_mul(MAX_RATIO).saturating_add(RATIO_SLACK) {
            return Err(format!(
                "the backup is a file of {len} bytes that says it holds {}: more than \
                 {MAX_RATIO} times its size, it is not opened",
                manifest.size()
            ));
        }
        manifest.caps()?;
        let files: BTreeMap<String, FileEntry> = manifest
            .sections
            .iter()
            .flat_map(|s| s.files.iter())
            .map(|f| (f.path.clone(), f.clone()))
            .collect();
        if zip.len() != files.len() + 1 {
            return Err(format!(
                "the backup has {} entries, its manifest lists {}",
                zip.len() - 1,
                files.len()
            ));
        }
        for i in 1..zip.len() {
            let e = zip.by_index(i).map_err(|e| format!("zip: {e}"))?;
            let name = e.name().map_err(|e| format!("zip: {e}"))?;
            let Some(f) = files.get(name.as_ref()) else {
                return Err(format!("entry {name:?} is not in the manifest"));
            };
            if e.is_dir() || e.is_symlink() || e.size() != f.size {
                return Err(format!(
                    "entry {}: not the file of {} bytes the manifest lists",
                    f.path, f.size
                ));
            }
        }
        Ok(Self {
            zip,
            manifest,
            files,
        })
    }

    pub fn manifest(&self) -> &Manifest {
        &self.manifest
    }

    /// Copy the stored bytes of `path` into `dst`, checking size and SHA-256.
    fn copy(&mut self, path: &str, dst: &mut dyn Write) -> Result<u64, String> {
        let f = self
            .files
            .get(path)
            .ok_or_else(|| format!("{path}: not in the backup"))?
            .clone();
        let e = self.zip.by_name(path).map_err(|e| format!("{path}: {e}"))?;
        // one byte more than listed shows a longer entry (a zip bomb)
        let mut src = e.take(f.size + 1);
        let mut h = Sha256::new();
        let mut buf = vec![0u8; 256 << 10];
        let mut n = 0u64;
        loop {
            let k = src.read(&mut buf).map_err(|e| format!("{path}: {e}"))?;
            if k == 0 {
                break;
            }
            n += k as u64;
            if n > f.size {
                return Err(format!("{path}: longer than the manifest lists"));
            }
            h.update(&buf[..k]);
            dst.write_all(&buf[..k])
                .map_err(|e| format!("{path}: {e}"))?;
        }
        if n != f.size || !hex::encode(h.finalize()).eq_ignore_ascii_case(&f.sha256) {
            return Err(format!("{path}: size or SHA-256 differs from the manifest"));
        }
        Ok(n)
    }

    /// Read every file and check it. `progress(done, total)` in stored bytes.
    pub fn verify(&mut self, mut progress: impl FnMut(u64, u64)) -> Result<(), String> {
        let total = self.manifest.size();
        let mut done = 0;
        let paths: Vec<String> = self.files.keys().cloned().collect();
        for p in paths {
            done += self.copy(&p, &mut std::io::sink())?;
            progress(done, total);
        }
        Ok(())
    }

    /// The stored bytes of `path` (at most [`MAX_IN_MEMORY`]), checked.
    pub fn read(&mut self, path: &str) -> Result<Vec<u8>, String> {
        let size = self
            .files
            .get(path)
            .ok_or_else(|| format!("{path}: not in the backup"))?
            .size;
        if size > MAX_IN_MEMORY {
            return Err(format!("{path}: {size} bytes, too large to read in memory"));
        }
        let mut out = Vec::with_capacity(size as usize);
        self.copy(path, &mut out)?;
        Ok(out)
    }

    /// The plain bytes of `path`: opened with `key` when it is sealed.
    pub fn read_plain(
        &mut self,
        path: &str,
        key: Option<&MasterKey>,
    ) -> Result<Zeroizing<Vec<u8>>, String> {
        // the reader decides what must be sealed, not the file's flag
        // (`Manifest::check` refused a secret file listed as plain)
        let sealed = self.files.get(path).is_some_and(|f| f.sealed)
            || must_be_sealed(self.manifest.kind, path);
        let stored = Zeroizing::new(self.read(path)?);
        if !sealed {
            return Ok(stored);
        }
        let key = key.ok_or_else(|| format!("{path}: sealed, no key"))?;
        open_bytes(key, path, &stored)
    }

    /// Write the plain content of `path` to the new file `dest` (parents
    /// created; 0600, or 0700 for an `exec` entry; refused when it exists).
    /// A sealed file is opened with `key`. On an error `dest` is removed.
    pub fn extract(
        &mut self,
        path: &str,
        dest: &Path,
        key: Option<&MasterKey>,
    ) -> Result<u64, String> {
        let f = self
            .files
            .get(path)
            .ok_or_else(|| format!("{path}: not in the backup"))?
            .clone();
        let io = |e: std::io::Error| format!("{}: {e}", dest.display());
        if let Some(dir) = dest.parent() {
            std::fs::create_dir_all(dir).map_err(io)?;
        }
        let mut opts = std::fs::OpenOptions::new();
        opts.write(true).create_new(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            opts.mode(if f.exec { 0o700 } else { 0o600 });
        }
        let out = opts.open(dest).map_err(io)?;
        let r = (|| {
            let mut out = std::io::BufWriter::new(out);
            let n = if f.sealed || must_be_sealed(self.manifest.kind, path) {
                let key = key.ok_or_else(|| format!("{path}: sealed, no key"))?;
                // sealed files are checked whole first, then opened part by part
                let stored = dest.with_extension("sealed-part");
                let r = (|| {
                    let mut tmp = File::create(&stored).map_err(io)?;
                    self.copy(path, &mut tmp)?;
                    drop(tmp);
                    let src = std::io::BufReader::new(File::open(&stored).map_err(io)?);
                    open_stream(key, path, src, &mut out)
                })();
                let _ = std::fs::remove_file(&stored);
                r?
            } else {
                self.copy(path, &mut out)?
            };
            let file = out.into_inner().map_err(|e| e.to_string())?;
            file.sync_all().map_err(io)?;
            Ok(n)
        })();
        if r.is_err() {
            let _ = std::fs::remove_file(dest);
        }
        r
    }
}

/// The manifest of the backup at `path` without checking its files' content.
pub fn read_manifest(path: &Path) -> Result<Manifest, String> {
    Reader::open(path, u64::MAX).map(|r| r.manifest)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Cursor;

    fn dir(name: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("wyrm-backup-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        d
    }

    fn head(sealed: Sealed) -> Head {
        Head {
            kind: Kind::Broker,
            site: "plant".into(),
            broker: "0.1.0".into(),
            created: "2026-11-13T10:00:00Z".into(),
            schemas: BTreeMap::from([("registry".to_owned(), 19)]),
            sealed,
            link: None,
        }
    }

    const PASS: &[u8] = b"correct horse battery";

    /// A backup with a plain and a sealed file; returns its path and key.
    fn sample(d: &Path) -> (PathBuf, MasterKey, Written) {
        let (sealed, key) = Sealing::Passphrase(PASS).start().unwrap();
        let key = key.unwrap();
        std::fs::write(d.join("wal"), b"records records records").unwrap();
        let secret = vec![7u8; SEAL_PART + 10];
        let mut out = File::create(d.join("ca.sealed")).unwrap();
        seal_stream(&key, "keys/pki/ca.key", secret.as_slice(), &mut out).unwrap();
        let sections = vec![
            StagedSection {
                name: "control".into(),
                info: serde_json::Map::from_iter([("lsn".to_owned(), 3.into())]),
                files: vec![Staged {
                    path: "control/state/wal.00000000000000000001.wyw".into(),
                    source: d.join("wal"),
                    sealed: false,
                    exec: false,
                }],
            },
            StagedSection {
                name: "keys".into(),
                info: Default::default(),
                files: vec![Staged {
                    path: "keys/pki/ca.key".into(),
                    source: d.join("ca.sealed"),
                    sealed: true,
                    exec: false,
                }],
            },
        ];
        let out = d.join("b.wyrm-backup");
        let mut last = (0, 0);
        let w = write(&out, head(sealed), sections, Some(&key), |a, b| {
            last = (a, b)
        })
        .unwrap();
        assert_eq!(last.0, last.1, "progress reaches the total");
        assert_eq!(w.size, std::fs::metadata(&out).unwrap().len());
        assert!(!d.join("b.wyrm-backup.part").exists());
        (out, key, w)
    }

    #[test]
    fn a_backup_is_written_read_and_checked() {
        let d = dir("roundtrip");
        let (path, _, w) = sample(&d);
        let mut r = Reader::open(&path, 1 << 30).unwrap();
        assert_eq!(r.manifest(), &w.manifest);
        assert_eq!(r.manifest().sections.len(), 2);
        r.verify(|_, _| {}).unwrap();
        assert_eq!(
            r.read("control/state/wal.00000000000000000001.wyw")
                .unwrap(),
            b"records records records"
        );
        // the sealed file is not its content, and opens only with the passphrase
        let stored = r.read("keys/pki/ca.key").unwrap();
        assert!(!stored.windows(16).any(|w| w == [7u8; 16]));
        assert!(r.read_plain("keys/pki/ca.key", None).is_err());
        let key = r.manifest().key(Some(PASS), None).unwrap();
        assert_eq!(
            r.read_plain("keys/pki/ca.key", Some(&key)).unwrap().len(),
            SEAL_PART + 10
        );
        assert_eq!(
            r.manifest()
                .key(Some(b"wrong passphrase!"), None)
                .err()
                .as_deref(),
            Some("wrong passphrase")
        );
        assert!(r.manifest().key(Some(b"short"), None).is_err());
        assert!(r.manifest().key(None, Some(b"k")).is_err());
        // extracted: content, owner-only, never over a file
        let dest = d.join("out/pki/ca.key");
        assert_eq!(
            r.extract("keys/pki/ca.key", &dest, Some(&key)).unwrap(),
            (SEAL_PART + 10) as u64
        );
        assert_eq!(std::fs::read(&dest).unwrap(), vec![7u8; SEAL_PART + 10]);
        assert!(r.extract("keys/pki/ca.key", &dest, Some(&key)).is_err());
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mode = std::fs::metadata(&dest).unwrap().permissions().mode();
            assert_eq!(mode & 0o777, 0o600);
        }
        // the size bound of the reader
        assert!(Reader::open(&path, 100).is_err());
        assert_eq!(read_manifest(&path).unwrap(), w.manifest);
    }

    /// A manifest of one plain file, sealed as `sealing` says and signed.
    fn signed(sealing: Sealing) -> (Manifest, MasterKey) {
        let (sealed, key) = sealing.start().unwrap();
        let key = key.unwrap();
        let mut m = manifest_with(&[("control/a", 3, b"abc")]);
        m.sealed = sealed;
        m.sealed.mac = key.mac_of(&m).unwrap();
        m.check().unwrap();
        (m, key)
    }

    /// Review of PR 72, item 8: the Argon2id parameters of a manifest run
    /// before its MAC is checked, so they are bounded by what a small host
    /// can afford, and what this broker writes is far inside the bound.
    #[test]
    fn a_manifest_cannot_ask_for_more_key_derivation_than_a_small_host_has() {
        let pass = b"correct horse battery";
        let (sealed, _) = Sealing::Passphrase(pass).start().unwrap();
        let kdf = sealed.kdf.clone().unwrap();
        assert!(kdf.m_kib <= MAX_KDF_KIB / 4 && kdf.t <= MAX_KDF_T && kdf.p <= MAX_KDF_P);
        assert!(sealed.master(Some(pass), None).is_ok());
        for (m_kib, t, p) in [
            (MAX_KDF_KIB + 1, kdf.t, kdf.p),
            (1 << 20, kdf.t, kdf.p),
            (kdf.m_kib, MAX_KDF_T + 1, kdf.p),
            (kdf.m_kib, kdf.t, MAX_KDF_P + 1),
        ] {
            let mut s = sealed.clone();
            s.kdf = Some(Kdf {
                m_kib,
                t,
                p,
                ..kdf.clone()
            });
            let started = std::time::Instant::now();
            let e = s.master(Some(pass), None).err().unwrap();
            assert!(e.contains("sealed.kdf"), "{e}");
            assert!(
                started.elapsed() < std::time::Duration::from_millis(200),
                "refused before any work"
            );
        }
    }

    #[test]
    fn broker_sealing_opens_only_with_the_same_key() {
        let (m, key) = signed(Sealing::Broker(b"secrets key"));
        let s = seal_bytes(&key, "data/x", b"");
        assert_eq!(
            open_bytes(&key, "data/x", &s).unwrap().len(),
            0,
            "an empty file"
        );
        let k2 = m.key(None, Some(b"secrets key")).unwrap();
        assert!(open_bytes(&k2, "data/x", &s).is_ok());
        assert!(m.key(None, Some(b"another key")).is_err());
        assert!(m.key(Some(PASS), None).is_err());
        let (none, k) = Sealing::None.start().unwrap();
        assert!(k.is_none() && none.master(Some(PASS), None).is_err());
    }

    #[test]
    fn an_edited_manifest_gives_no_key() {
        let (m, _) = signed(Sealing::Broker(b"secrets key"));
        m.key(None, Some(b"secrets key")).unwrap();
        let edited = |f: &dyn Fn(&mut Manifest)| {
            let mut e = m.clone();
            f(&mut e);
            e.key(None, Some(b"secrets key")).err()
        };
        let changed = |e: Option<String>| e.is_some_and(|e| e.contains("changed"));
        // a digest, a size, a path, a flag, what a section says, the site
        assert!(changed(edited(
            &|m| m.sections[0].files[0].sha256 = "0".repeat(64)
        )));
        assert!(changed(edited(&|m| m.sections[0].files[0].size = 4)));
        assert!(changed(edited(
            &|m| m.sections[0].files[0].path = "control/b".into()
        )));
        assert!(changed(edited(&|m| m.sections[0].files[0].exec = true)));
        assert!(changed(edited(&|m| m.sections[0].files[0].sealed = true)));
        assert!(changed(edited(&|m| {
            m.sections[0].info.insert("lsn".into(), 9.into());
        })));
        assert!(changed(edited(&|m| m.site = "other".into())));
        assert!(changed(edited(&|m| m.sections[0].files.clear())));
        // a sealed backup without its MAC or id is not read at all
        let mut bare = m.clone();
        bare.sealed.mac.clear();
        assert!(bare.check().unwrap_err().contains("not authenticated"));
        let mut bare = m.clone();
        bare.sealed.id.clear();
        assert!(bare.check().is_err());
        // and an unsealed one cannot claim to be authenticated
        let mut plain = manifest_with(&[("control/a", 3, b"abc")]);
        plain.sealed.mac = m.sealed.mac.clone();
        assert!(plain.check().is_err());
        // the writer signs only with the key of that backup
        let (_, other) = signed(Sealing::Broker(b"secrets key"));
        let d = dir("wrongkey");
        let head = Head {
            sealed: m.sealed.clone(),
            ..head(m.sealed.clone())
        };
        assert!(write(
            &d.join("x.wyrm-backup"),
            head.clone(),
            vec![],
            Some(&other),
            |_, _| {}
        )
        .is_err());
        assert!(write(&d.join("x.wyrm-backup"), head, vec![], None, |_, _| {}).is_err());
    }

    #[test]
    fn sizes_that_overflow_are_refused() {
        // two files whose sizes wrap around to a small sum
        let mut m = manifest_with(&[("control/a", 3, b"abc"), ("control/b", 3, b"abc")]);
        m.sections[0].files[0].size = u64::MAX;
        m.sections[0].files[1].size = 2;
        assert_eq!(m.size(), u64::MAX, "never a small number");
        assert_eq!(m.sections[0].size(), u64::MAX);
        assert!(m.check().is_err());
        // within one file's bound each, still more than u64 in all
        let mut m = manifest_with(&[("control/a", 3, b"abc")]);
        m.sections[0].files[0].size = MAX_FILE + 1;
        assert!(m.check().unwrap_err().contains("at most"));
        m.sections[0].files[0].size = MAX_FILE;
        m.check().unwrap();
        // the reader's bound holds for the sum
        let zip = zip_of(&serde_json::to_vec(&m).unwrap(), &[("control/a", b"abc")]);
        assert!(Reader::new(Cursor::new(zip), 1 << 30).is_err());
    }

    #[test]
    fn a_secret_file_listed_as_plain_is_refused() {
        // keys, a link's secrets, token and private files; a link backup's data
        for (kind, path, secret) in [
            (Kind::Broker, "keys/pki/ca.key", true),
            (Kind::Broker, "keys/secrets.bin", true),
            (Kind::Broker, "links/plc1/secrets", true),
            (Kind::Broker, "links/plc1/token", true),
            (Kind::Broker, "links/plc1/files/framework.tree", true),
            (Kind::Broker, "links/plc1/link.cbor", false),
            (
                Kind::Broker,
                "control/state/wal.00000000000000000001.wyw",
                false,
            ),
            (Kind::Broker, "packages/demo/files/bin/run", false),
            (Kind::Link, "data/secrets", true),
            (Kind::Link, "data/files/store/00ff", true),
            (Kind::Link, "settings/link.cbor", false),
            (Kind::Link, "package/files/bin/run", false),
        ] {
            assert_eq!(must_be_sealed(kind, path), secret, "{path}");
        }
        // the flag of a sealed file flipped to false, with the plain bytes
        // of an attacker in its place: refused before anything is read
        let d = dir("downgrade");
        let (path, _, w) = sample(&d);
        let mut m = w.manifest.clone();
        let f = &mut m.sections[1].files[0];
        assert!(f.sealed);
        f.sealed = false;
        f.size = 6;
        f.sha256 = hex::encode(Sha256::digest(b"forged"));
        assert!(m.check().unwrap_err().contains("not sealed"));
        let wal = std::fs::read(d.join("wal")).unwrap();
        let zip = zip_of(
            &serde_json::to_vec(&m).unwrap(),
            &[
                ("control/state/wal.00000000000000000001.wyw", &wal),
                ("keys/pki/ca.key", b"forged"),
            ],
        );
        assert!(Reader::new(Cursor::new(zip), 1 << 30).is_err());
        // with `how: none` there is no sealed file, so no secret file at all
        let mut m = manifest_with(&[("control/a", 3, b"abc")]);
        m.sections[0].name = "keys".into();
        m.sections[0].files[0].path = "keys/state.key".into();
        assert!(m.check().is_err());
        m.sections[0].files[0].sealed = true;
        assert!(m.check().is_err());
        let _ = path;
    }

    #[test]
    fn a_sealed_part_of_another_backup_does_not_open() {
        // the same passphrase (here: the same broker key), two backups
        let (_, a) = signed(Sealing::Broker(b"secrets key"));
        let (_, b) = signed(Sealing::Broker(b"secrets key"));
        let in_a = seal_bytes(&a, "keys/state.key", b"the key of a");
        let in_b = seal_bytes(&b, "keys/state.key", b"the key of b");
        assert_eq!(
            &**open_bytes(&a, "keys/state.key", &in_a).unwrap(),
            b"the key of a"
        );
        // the whole file, and one part, moved from b into a
        assert!(open_bytes(&a, "keys/state.key", &in_b).is_err());
        let plain = vec![3u8; SEAL_PART + 1];
        let (long_a, long_b) = (
            seal_bytes(&a, "keys/x", &plain),
            seal_bytes(&b, "keys/x", &plain),
        );
        let part = 4 + SEAL_PART + 9 + 28;
        let mut mixed = long_a[..5 + part].to_vec();
        mixed.extend_from_slice(&long_b[5 + part..]);
        assert!(open_bytes(&a, "keys/x", &mixed).is_err());
        assert!(open_bytes(&a, "keys/x", &long_a).is_ok());
    }

    #[test]
    fn sealed_parts_are_bound_to_their_file_and_place() {
        let (_, key) = signed(Sealing::Broker(b"k"));
        let plain: Vec<u8> = (0..(2 * SEAL_PART + 5)).map(|i| (i % 251) as u8).collect();
        let sealed = seal_bytes(&key, "data/a", &plain);
        assert_eq!(*open_bytes(&key, "data/a", &sealed).unwrap(), plain);
        // another path
        assert!(open_bytes(&key, "data/b", &sealed).is_err());
        // a changed byte
        let mut bad = sealed.clone();
        bad[100] ^= 1;
        assert!(open_bytes(&key, "data/a", &bad).is_err());
        // the last part cut off, and the first two parts swapped
        let part = 4 + SEAL_PART + 9 + 28;
        assert!(open_bytes(&key, "data/a", &sealed[..5 + 2 * part]).is_err());
        let mut swapped = sealed[..5].to_vec();
        swapped.extend_from_slice(&sealed[5 + part..5 + 2 * part]);
        swapped.extend_from_slice(&sealed[5..5 + part]);
        swapped.extend_from_slice(&sealed[5 + 2 * part..]);
        assert!(open_bytes(&key, "data/a", &swapped).is_err());
        // bytes after the end
        let mut longer = sealed.clone();
        longer.push(0);
        assert!(open_bytes(&key, "data/a", &longer).is_err());
        // exactly one part: the next read is empty, the part is the last
        let one = vec![1u8; SEAL_PART];
        let s = seal_bytes(&key, "data/a", &one);
        assert_eq!(*open_bytes(&key, "data/a", &s).unwrap(), one);
    }

    #[test]
    fn paths_that_leave_the_backup_are_refused() {
        for p in [
            "",
            "/etc/passwd",
            "control/../../x",
            "control/./x",
            "control//x",
            "control\\x",
            "c:/x",
            "control/x\n",
            "manifest.json",
            "control/",
        ] {
            assert!(check_path(p).is_err(), "{p:?}");
        }
        assert!(check_path(&format!("control/{}", "a/".repeat(30))).is_err());
        assert!(check_path(&"a".repeat(MAX_PATH + 1)).is_err());
        assert!(check_path("links/plc1/data/store/00ff").is_ok());
    }

    fn zip_of(manifest: &[u8], entries: &[(&str, &[u8])]) -> Vec<u8> {
        use zip::write::SimpleFileOptions;
        let mut w = zip::ZipWriter::new(Cursor::new(Vec::new()));
        w.start_file(MANIFEST, SimpleFileOptions::default())
            .unwrap();
        w.write_all(manifest).unwrap();
        for (name, data) in entries {
            w.start_file(*name, SimpleFileOptions::default()).unwrap();
            w.write_all(data).unwrap();
        }
        w.finish().unwrap().into_inner()
    }

    fn manifest_with(files: &[(&str, u64, &[u8])]) -> Manifest {
        Manifest {
            wyrm_backup: VERSION,
            kind: Kind::Broker,
            site: "plant".into(),
            broker: "0.1.0".into(),
            created: "2026-11-13T10:00:00Z".into(),
            schemas: BTreeMap::new(),
            sealed: Sealed {
                how: "none".into(),
                kdf: None,
                check: String::new(),
                id: String::new(),
                mac: String::new(),
            },
            link: None,
            sections: vec![Section {
                name: "control".into(),
                info: Default::default(),
                files: files
                    .iter()
                    .map(|(p, size, data)| FileEntry {
                        path: (*p).to_owned(),
                        size: *size,
                        sha256: hex::encode(Sha256::digest(data)),
                        sealed: false,
                        exec: false,
                    })
                    .collect(),
            }],
        }
    }

    fn open(m: &Manifest, entries: &[(&str, &[u8])]) -> Result<Reader<Cursor<Vec<u8>>>, String> {
        let zip = zip_of(&serde_json::to_vec(m).unwrap(), entries);
        Reader::new(Cursor::new(zip), 1 << 20)
    }

    #[test]
    fn the_reader_refuses_what_the_manifest_does_not_list() {
        let good = manifest_with(&[("control/a", 3, b"abc")]);
        let mut r = open(&good, &[("control/a", b"abc")]).unwrap();
        r.verify(|_, _| {}).unwrap();
        // an entry more, an entry less, another name
        assert!(open(&good, &[("control/a", b"abc"), ("control/b", b"x")]).is_err());
        assert!(open(&good, &[]).is_err());
        assert!(open(&good, &[("control/b", b"abc")]).is_err());
        // another size is seen at open, other content at read
        assert!(open(&good, &[("control/a", b"abcd")]).is_err());
        let mut r = open(&good, &[("control/a", b"abd")]).unwrap();
        assert!(r.verify(|_, _| {}).is_err());
        assert!(r.read("control/a").is_err());
        // a manifest that is not first, or is not a manifest
        let zip = zip_of(b"{}", &[]);
        assert!(Reader::new(Cursor::new(zip), 1 << 20).is_err());
        assert!(Reader::new(Cursor::new(b"not a zip".to_vec()), 1 << 20).is_err());
    }

    /// Review of PR 72, item 5: what a backup opens into is bounded before
    /// a byte is extracted, by the size of the file itself and by what each
    /// part may be; an entry longer than listed stops at the listed size.
    #[test]
    fn a_small_file_does_not_open_into_a_large_one() {
        // 96 MiB of zeros deflate into a file of about 100 KiB
        let zeros = vec![0u8; 96 << 20];
        let m = manifest_with(&[("control/a", zeros.len() as u64, &zeros)]);
        let zip = zip_of(&serde_json::to_vec(&m).unwrap(), &[("control/a", &zeros)]);
        assert!(zip.len() < 1 << 20, "{} bytes", zip.len());
        let e = Reader::new(Cursor::new(zip), 1 << 40).err().unwrap();
        assert!(e.contains("times its size"), "{e}");
        // within the slack a compressible file is taken (a fresh redb file)
        let small = vec![0u8; 8 << 20];
        let m = manifest_with(&[("control/a", small.len() as u64, &small)]);
        let zip = zip_of(&serde_json::to_vec(&m).unwrap(), &[("control/a", &small)]);
        Reader::new(Cursor::new(zip), 1 << 40).unwrap();

        // each part has its own bound, whatever the whole is
        let entry = |path: &str, size: u64| FileEntry {
            path: path.into(),
            size,
            sha256: "0".repeat(64),
            sealed: must_be_sealed(Kind::Broker, path),
            exec: false,
        };
        let with = |name: &str, files: Vec<FileEntry>| {
            let mut m = manifest_with(&[]);
            m.sealed.how = "broker".into();
            m.sections = vec![Section {
                name: name.into(),
                info: Default::default(),
                files,
            }];
            m
        };
        let half = MAX_PACKAGE / 2 + (1 << 20);
        let m = with(
            "packages",
            vec![
                entry("packages/p/files/a", half),
                entry("packages/p/files/b", half),
            ],
        );
        assert!(m.caps().unwrap_err().contains("package p"));
        let m = with(
            "packages",
            vec![
                entry("packages/p/files/a", half),
                entry("packages/q/files/b", half),
            ],
        );
        m.caps().unwrap();
        let m = with(
            "dataflows",
            vec![entry("dataflows/artifacts/ab/cd", MAX_ARTIFACT + (1 << 20))],
        );
        assert!(m.caps().unwrap_err().contains("flow artifact"));
        let m = with(
            "links",
            vec![
                entry("links/l1/files/a", MAX_LINK_DATA),
                entry("links/l1/files/b", MAX_LINK_DATA / 512),
            ],
        );
        assert!(m.caps().unwrap_err().contains("link data l1"));
        let m = with("links", vec![entry("links/l1/files/a", MAX_LINK_DATA)]);
        m.caps().unwrap();
        let mut m = with("package", vec![entry("package/files/bin", MAX_PACKAGE * 2)]);
        m.kind = Kind::Link;
        assert!(m.caps().unwrap_err().contains("package"));
    }

    #[test]
    fn the_manifest_is_checked() {
        let ok = manifest_with(&[("control/a", 3, b"abc")]);
        ok.check().unwrap();
        let with = |f: &dyn Fn(&mut Manifest)| {
            let mut m = ok.clone();
            f(&mut m);
            m.check()
        };
        assert!(with(&|m| m.wyrm_backup = 2).is_err());
        assert!(with(&|m| m.site = "a/b".into()).is_err());
        assert!(with(&|m| m.sections[0].name = "nope".into()).is_err());
        assert!(with(&|m| m.sections[0].files[0].path = "keys/a".into()).is_err());
        assert!(with(&|m| m.sections[0].files[0].path = "control".into()).is_err());
        assert!(with(&|m| m.sections[0].files[0].path = "control/../a".into()).is_err());
        assert!(with(&|m| m.sections[0].files[0].sha256 = "xyz".into()).is_err());
        assert!(with(&|m| m.sections[0].files[0].sealed = true).is_err());
        assert!(with(&|m| {
            let f = m.sections[0].files[0].clone();
            m.sections[0].files.push(f)
        })
        .is_err());
        assert!(with(&|m| {
            let s = m.sections[0].clone();
            m.sections.push(s)
        })
        .is_err());
        assert!(
            with(&|m| m.kind = Kind::Link).is_err(),
            "a link backup names its link"
        );
        assert!(with(&|m| m.sealed.how = "passphrase".into()).is_err());
        // a link backup has link sections
        let mut link = ok.clone();
        link.kind = Kind::Link;
        link.link = Some(LinkInfo::default());
        assert!(link.check().is_err());
        link.sections[0].name = "settings".into();
        link.sections[0].files[0].path = "settings/link.cbor".into();
        link.check().unwrap();
    }
}
