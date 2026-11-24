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
//! Errors are types by what failed (audit T7): [`ManifestError`] for what a
//! manifest says alone, [`KeyError`] for the way to the master key (a wrong
//! passphrase, another broker's file and a changed manifest are three
//! variants), [`SealedError`] for a sealed file that does not open,
//! [`ReadError`] and [`WriteError`] for a backup file as a whole, with a file
//! of the host that failed as a variant of its own. A caller that shows one
//! to a person turns it to text; the texts are pinned by a test.
//!
//! `serde_json` is used here because a backup is a user file (principle 5).

use serde::{Deserialize, Serialize};
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

/// What is wrong with the path of an entry ([`check_path`]).
#[derive(Debug, Clone, Copy, PartialEq, Eq, thiserror::Error)]
pub enum PathFault {
    /// Empty, or longer than [`MAX_PATH`].
    #[error("empty or too long")]
    Length,
    /// [`MANIFEST`]: a file may not take the manifest's place.
    #[error("the manifest's name")]
    ManifestName,
    /// A segment that is empty, `.` or `..`: the path would leave its place.
    #[error("empty, `.` or `..` segment")]
    Segment,
    #[error("`\\`, `:` or a control character")]
    Character,
    /// More than [`MAX_DEPTH`] segments.
    #[error("too deep")]
    Depth,
}

/// A path that is no path of an entry ([`check_path`]).
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
#[error("path {path:?}: {fault}")]
pub struct PathError {
    pub path: String,
    pub fault: PathFault,
}

/// A part of a backup with a bound of its own ([`Manifest::caps`]). The
/// order is the order the parts are judged in.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum Part {
    /// The private data of one link: [`MAX_LINK_DATA`].
    LinkData,
    /// One package: [`MAX_PACKAGE`].
    Package,
}

impl Part {
    /// The most stored bytes of one such part.
    pub fn cap(self) -> u64 {
        match self {
            Part::LinkData => MAX_LINK_DATA,
            Part::Package => MAX_PACKAGE,
        }
    }
}

impl std::fmt::Display for Part {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(match self {
            Part::LinkData => "link data",
            Part::Package => "package",
        })
    }
}

/// Why a manifest is refused by what it says alone ([`Manifest::check`],
/// [`Manifest::caps`]): no key and no file content is needed to tell.
#[derive(Debug, thiserror::Error)]
pub enum ManifestError {
    #[error("wyrm_backup {found}: this broker reads version {}", VERSION)]
    Version { found: u32 },
    #[error("manifest: site: {0}")]
    Site(#[source] wyrm_core::keyspace::KeyError),
    /// `sealed.kdf` without `how: passphrase`, or the other way round.
    #[error("manifest: sealed.kdf goes with how: passphrase")]
    KdfAndHow,
    /// A sealed backup without its id, check or MAC: nothing would
    /// authenticate the manifest.
    #[error(
        "manifest: a sealed backup carries sealed.id, sealed.check and sealed.mac; \
         this one is not authenticated"
    )]
    NotAuthenticated,
    /// An unsealed backup that carries an id or a MAC no key stands behind.
    #[error("manifest: sealed.id and sealed.mac go with a sealed backup")]
    AuthenticationWithoutSealing,
    /// `link` without `kind: link`, or the other way round.
    #[error("manifest: link goes with kind: link")]
    LinkAndKind,
    #[error("manifest: no section {section:?} in a {} backup", .kind.name())]
    SectionOfOtherKind { section: SectionName, kind: Kind },
    #[error("manifest: section {0} twice")]
    SectionTwice(SectionName),
    #[error("manifest: more than {} files", MAX_ENTRIES)]
    TooManyFiles,
    #[error(transparent)]
    Path(#[from] PathError),
    /// A file listed in a section whose folder its path is not in.
    #[error("manifest: {path} is not under section {section}")]
    OutsideSection { path: String, section: SectionName },
    /// `sha256` is not 64 hex digits.
    #[error("manifest: {path}: sha256")]
    Digest { path: String },
    #[error("manifest: {path}: {size} bytes (at most {} a file)", MAX_FILE)]
    FileTooLarge { path: String, size: u64 },
    /// The sizes do not fit in a `u64`.
    #[error("manifest: the sizes of its files do not add up")]
    SizesOverflow,
    /// A file the reader holds for secret ([`must_be_sealed`]) is listed as
    /// not sealed.
    #[error("manifest: {path} holds secrets and is not sealed")]
    SecretNotSealed { path: String },
    /// A sealed file in a backup with `how: none`.
    #[error("manifest: {path} is sealed, the backup says none")]
    SealedWithoutSealing { path: String },
    #[error("manifest: {path} twice")]
    PathTwice { path: String },
    /// A flow artifact over [`MAX_ARTIFACT`].
    #[error("{path}: {size} bytes (a flow artifact has at most {})", MAX_ARTIFACT)]
    ArtifactTooLarge { path: String, size: u64 },
    /// One package or one link's data over its bound.
    #[error("the {part} {name} of the backup holds {size} bytes (at most {})", .part.cap())]
    PartTooLarge { part: Part, name: String, size: u64 },
}

/// Why a backup gives no master key ([`Manifest::key`]) or a new one is not
/// sealed ([`Sealing::start`]). No variant holds a byte of a passphrase, a
/// key or sealed content; the hex causes quote the manifest's own fields.
#[derive(Debug, thiserror::Error)]
pub enum KeyError {
    #[error("passphrase: at least {} characters", crate::keys::MIN_PASSPHRASE)]
    PassphraseTooShort,
    /// The manifest asks for another function, or for more work than
    /// [`MAX_KDF_KIB`], [`MAX_KDF_T`], [`MAX_KDF_P`].
    #[error(
        "sealed.kdf: not Argon2id within {} MiB, {} passes, {} lanes",
        MAX_KDF_KIB >> 10,
        MAX_KDF_T,
        MAX_KDF_P
    )]
    KdfBounds,
    #[error("sealed.kdf.salt: hex")]
    SaltHex(#[source] hex::FromHexError),
    /// Argon2 refuses the parameters (it carries no input, only which).
    #[error("sealed.kdf: {0}")]
    KdfParams(argon2::Error),
    #[error("key derivation: {0}")]
    Derivation(argon2::Error),
    #[error("manifest: sealed.id: hex")]
    IdHex(#[source] hex::FromHexError),
    #[error("manifest: sealed.id: 16 bytes")]
    IdLength,
    #[error("passphrase: required, the backup is sealed with one")]
    PassphraseRequired,
    /// `how: broker` and the caller has no `secrets.key` to try.
    #[error("the backup is sealed for the broker that made it")]
    BrokerKeyRequired,
    /// `how: none`: there is no key to give.
    #[error("the backup has no sealed files")]
    NotSealed,
    /// `sealed.check` does not open under the key of this passphrase.
    #[error("wrong passphrase")]
    WrongPassphrase,
    /// `sealed.check` does not open under the key of this `secrets.key`.
    #[error("the backup is sealed for another broker (its secrets.key differs)")]
    AnotherBroker,
    #[error("manifest: sealed.mac: hex")]
    MacHex(#[source] hex::FromHexError),
    /// The key is the right one and the manifest's MAC does not match: a
    /// path, size, digest, flag or `info` was changed.
    #[error("the manifest was changed after the backup was made (its MAC does not match)")]
    ManifestChanged,
    /// The manifest does not serialize for its MAC.
    #[error("{0}")]
    Encode(#[source] serde_json::Error),
    /// No salt or id for a new backup.
    #[error("{0}")]
    NoRandomness(#[source] wyrm_core::rand::NoRandomness),
    /// The check text of a new backup does not seal.
    #[error("{0}")]
    Seal(#[source] wyrm_link_sdk::seal::SealError),
}

/// Why a sealed file does not open ([`open_stream`], [`open_bytes`]). Each
/// names the file; none holds a byte of it.
#[derive(Debug, thiserror::Error)]
pub enum SealedError {
    /// The stream could not be read or the plain bytes not written.
    #[error("{path}: {source}")]
    Io {
        path: String,
        #[source]
        source: std::io::Error,
    },
    #[error("{path}: not a sealed file")]
    NotSealed { path: String },
    /// The stream ends before its last part.
    #[error("{path}: sealed file cut short")]
    CutShort {
        path: String,
        #[source]
        source: std::io::Error,
    },
    /// A part says it is longer than a part may be.
    #[error("{path}: sealed part of {len} bytes")]
    PartTooLarge { path: String, len: usize },
    /// A part is not sealed under this key for this path of this backup, or
    /// was changed.
    #[error("{path}: does not open (wrong key, or changed)")]
    DoesNotOpen { path: String },
    /// An authentic part at another place of its file.
    #[error("{path}: sealed parts out of order")]
    OutOfOrder { path: String },
    #[error("{path}: bytes after the last sealed part")]
    Trailing { path: String },
}

/// Why a backup was not written ([`write`]).
#[derive(Debug, thiserror::Error)]
pub enum WriteError {
    /// A staged file or the backup file itself.
    #[error("{}: {source}", .path.display())]
    Io {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    /// The key's id is not `sealed.id` of the head.
    #[error("the key is of another backup")]
    KeyOfAnotherBackup,
    /// A sealed head without a key, or a key with `how: none`.
    #[error("a sealed backup is written with its key, an unsealed one without")]
    KeyAndSealing,
    /// What was staged makes a manifest no reader would take.
    #[error(transparent)]
    Manifest(#[from] ManifestError),
    #[error("manifest: too large")]
    ManifestTooLarge,
    #[error("{0}")]
    Encode(#[source] serde_json::Error),
    #[error("{0}")]
    Zip(#[source] zip::result::ZipError),
    /// The last bytes did not reach the file.
    #[error("{0}")]
    Flush(#[source] std::io::Error),
    /// A staged file is not the bytes the manifest was made from.
    #[error("{}: changed while it was read", .path.display())]
    SourceChanged { path: PathBuf },
}

/// Why a backup was not opened or a file of it not read ([`Reader`]).
#[derive(Debug, thiserror::Error)]
pub enum ReadError {
    /// The backup file, or the file an entry is written to.
    #[error("{}: {source}", .path.display())]
    File {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("not a backup: {0}")]
    Seek(#[source] std::io::Error),
    #[error("not a backup: {0}")]
    NotZip(#[source] zip::result::ZipError),
    #[error("not a backup: {found} entries (1 to {})", MAX_ENTRIES)]
    EntryCount { found: usize },
    #[error("not a backup: the first entry is not {}", MANIFEST)]
    ManifestNotFirst,
    /// Over [`MAX_MANIFEST`].
    #[error("manifest: too large")]
    ManifestTooLarge,
    #[error("manifest: {0}")]
    ManifestRead(#[source] std::io::Error),
    #[error("manifest: {0}")]
    ManifestJson(#[source] serde_json::Error),
    #[error(transparent)]
    Manifest(#[from] ManifestError),
    /// More stored bytes than the caller takes.
    #[error("the backup holds {size} bytes; at most {max} are taken here")]
    OverLimit { size: u64, max: u64 },
    /// More than [`MAX_RATIO`] times the file's own size, beyond
    /// [`RATIO_SLACK`].
    #[error(
        "the backup is a file of {len} bytes that says it holds {size}: more than \
         {} times its size, it is not opened",
        MAX_RATIO
    )]
    Ratio { len: u64, size: u64 },
    #[error("the backup has {entries} entries, its manifest lists {listed}")]
    EntriesAndManifest { entries: usize, listed: usize },
    #[error("zip: {0}")]
    Zip(#[source] zip::result::ZipError),
    #[error("entry {name:?} is not in the manifest")]
    UnlistedEntry { name: String },
    /// A directory, a symlink or a file of another size.
    #[error("entry {path}: not the file of {size} bytes the manifest lists")]
    EntryNotAsListed { path: String, size: u64 },
    #[error("{path}: not in the backup")]
    NotInBackup { path: String },
    #[error("{path}: {source}")]
    Entry {
        path: String,
        #[source]
        source: zip::result::ZipError,
    },
    /// The stored bytes of an entry could not be read.
    #[error("{path}: {source}")]
    Stored {
        path: String,
        #[source]
        source: std::io::Error,
    },
    /// The bytes read could not be written where they go.
    #[error("{path}: {source}")]
    Output {
        path: String,
        #[source]
        source: std::io::Error,
    },
    #[error("{path}: longer than the manifest lists")]
    Longer { path: String },
    #[error("{path}: size or SHA-256 differs from the manifest")]
    Differs { path: String },
    /// Over [`MAX_IN_MEMORY`].
    #[error("{path}: {size} bytes, too large to read in memory")]
    TooLargeInMemory { path: String, size: u64 },
    /// A sealed file asked for without a key.
    #[error("{path}: sealed, no key")]
    NoKey { path: String },
    #[error(transparent)]
    Sealed(#[from] SealedError),
    /// The last bytes did not reach the extracted file.
    #[error("{0}")]
    Flush(#[source] std::io::Error),
}

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

wyrm_core::name_enum! {
    /// A section of a backup: the top folder of its files in the zip and its entry in
    /// the manifest (ADR 0048 §3.2 for a broker backup, §3.5 for a link backup). Kept by
    /// its name, the text the field held as a `String` (the manifest's bytes and MAC, a
    /// job record and a restore plan are unchanged). A name that is not here refuses
    /// the manifest, the job record or the plan: what is sealed and what is restored
    /// depends on it, so an unknown section is never skipped.
    pub enum SectionName as "backup section" {
        Control => "control",
        Keys => "keys",
        Dataflows => "dataflows",
        Storage => "storage",
        History => "history",
        Links => "links",
        Packages => "packages",
        Config => "config",
        Settings => "settings",
        Data => "data",
        Package => "package",
    }
}

/// `a, b, c`: the names of `sections`, for people (an audit line, an error).
pub fn section_names(sections: &[SectionName]) -> String {
    sections
        .iter()
        .map(|s| s.name())
        .collect::<Vec<_>>()
        .join(", ")
}

/// The sections of a broker backup (ADR 0048 §3.2).
pub const BROKER_SECTIONS: [SectionName; 8] = [
    SectionName::Control,
    SectionName::Keys,
    SectionName::Dataflows,
    SectionName::Storage,
    SectionName::History,
    SectionName::Links,
    SectionName::Packages,
    SectionName::Config,
];
/// The sections of a link backup (ADR 0048 §3.5).
pub const LINK_SECTIONS: [SectionName; 4] = [
    SectionName::Settings,
    SectionName::Data,
    SectionName::Package,
    SectionName::History,
];

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

    pub fn sections(self) -> &'static [SectionName] {
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

wyrm_core::name_enum! {
    /// How the sealed files of a backup are sealed (manifest `sealed.how`, a job's
    /// `sealed`). Kept as its name, as the `String` it was; a manifest with another
    /// name does not decode.
    pub enum How as "backup sealing" {
        /// No sealed file.
        None => "none",
        Passphrase => "passphrase",
        Broker => "broker",
    }
}

/// How the sealed files of a backup are sealed.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Sealed {
    pub how: How,
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
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LinkInfo {
    pub id: String,
    pub driver: String,
    /// Kept by its name (`"process"`), the text the field held when it was a `String`:
    /// the manifest's bytes, and so its MAC, are the same. A name that is no link mode
    /// refuses the manifest.
    #[serde(with = "wyrm_core::named::serde")]
    pub mode: crate::registry::Mode,
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
    pub name: SectionName,
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
    pub fn section(&self, name: SectionName) -> Option<&Section> {
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
    fn mac_text(&self) -> Result<Vec<u8>, serde_json::Error> {
        let mut m = self.clone();
        m.sealed.mac.clear();
        serde_json::to_vec(&m)
    }

    /// The master key of this backup's sealed files: from `passphrase`
    /// (`how: passphrase`) or from this broker's `secrets_key` (`how:
    /// broker`). `Err` for a wrong passphrase ([`KeyError::WrongPassphrase`]),
    /// another broker's file ([`KeyError::AnotherBroker`]), or a manifest
    /// changed since the backup was made (any path, size, digest or flag;
    /// [`KeyError::ManifestChanged`]): the key is handed out only for an
    /// authentic manifest.
    pub fn key(
        &self,
        passphrase: Option<&[u8]>,
        secrets_key: Option<&[u8]>,
    ) -> Result<MasterKey, KeyError> {
        let key = self.sealed.master(passphrase, secrets_key)?;
        let mac = hex::decode(&self.sealed.mac).map_err(KeyError::MacHex)?;
        let text = self.mac_text().map_err(KeyError::Encode)?;
        // ring's error is a unit: it says only that the MAC does not match
        ring::hmac::verify(&key.mac_key(), &text, &mac)
            .map_err(|ring::error::Unspecified| KeyError::ManifestChanged)?;
        Ok(key)
    }

    /// The bounds of what one part of a backup may open into, known before
    /// a byte is extracted (ADR 0048 §3.1): each package, each flow
    /// artifact, each link's private data. A sealed file is a little longer
    /// than its content, so each bound has that much room.
    pub fn caps(&self) -> Result<(), ManifestError> {
        let room = |cap: u64| cap + cap / 1024 + 4096;
        let mut groups: BTreeMap<(Part, &str), u64> = BTreeMap::new();
        for f in self.sections.iter().flat_map(|s| &s.files) {
            let segs: Vec<&str> = f.path.split('/').collect();
            let group = match (self.kind, segs.as_slice()) {
                (Kind::Broker, ["packages", name, ..]) => (Part::Package, *name),
                (Kind::Broker, ["links", id, "files", ..]) => (Part::LinkData, *id),
                (Kind::Link, ["package", ..]) => (Part::Package, ""),
                (Kind::Broker, ["dataflows", "artifacts", ..]) => {
                    if f.size > room(MAX_ARTIFACT) {
                        return Err(ManifestError::ArtifactTooLarge {
                            path: f.path.clone(),
                            size: f.size,
                        });
                    }
                    continue;
                }
                _ => continue,
            };
            let sum = groups.entry(group).or_default();
            *sum = sum.saturating_add(f.size);
        }
        for ((part, name), size) in groups {
            if size > room(part.cap()) {
                return Err(ManifestError::PartTooLarge {
                    part,
                    name: name.to_owned(),
                    size,
                });
            }
        }
        Ok(())
    }

    /// Check what a manifest alone can show: version, section names of its
    /// kind (each once), every path under its section and well formed, no
    /// path twice, digests that are digests, bounded counts.
    pub fn check(&self) -> Result<(), ManifestError> {
        if self.wyrm_backup != VERSION {
            return Err(ManifestError::Version {
                found: self.wyrm_backup,
            });
        }
        wyrm_core::keyspace::validate_segment(&self.site).map_err(ManifestError::Site)?;
        if (self.sealed.how == How::Passphrase) != self.sealed.kdf.is_some() {
            return Err(ManifestError::KdfAndHow);
        }
        let keyed = self.sealed.how != How::None;
        if keyed
            && !(wyrm_core::hex::is_hex(&self.sealed.id, ID_LEN)
                && wyrm_core::hex::is_hex(&self.sealed.mac, 32)
                && !self.sealed.check.is_empty())
        {
            return Err(ManifestError::NotAuthenticated);
        }
        if !keyed && !(self.sealed.id.is_empty() && self.sealed.mac.is_empty()) {
            return Err(ManifestError::AuthenticationWithoutSealing);
        }
        if (self.kind == Kind::Link) != self.link.is_some() {
            return Err(ManifestError::LinkAndKind);
        }
        let mut names = BTreeSet::new();
        let mut paths = BTreeSet::new();
        let mut count = 0usize;
        let mut total = 0u64;
        for s in &self.sections {
            if !self.kind.sections().contains(&s.name) {
                return Err(ManifestError::SectionOfOtherKind {
                    section: s.name,
                    kind: self.kind,
                });
            }
            if !names.insert(s.name.name()) {
                return Err(ManifestError::SectionTwice(s.name));
            }
            count += s.files.len();
            if count >= MAX_ENTRIES {
                return Err(ManifestError::TooManyFiles);
            }
            for f in &s.files {
                check_path(&f.path)?;
                if f.path.split('/').next().and_then(SectionName::from_name) != Some(s.name)
                    || !f.path.contains('/')
                {
                    return Err(ManifestError::OutsideSection {
                        path: f.path.clone(),
                        section: s.name,
                    });
                }
                if f.sha256.len() != 64 || !f.sha256.bytes().all(|b| b.is_ascii_hexdigit()) {
                    return Err(ManifestError::Digest {
                        path: f.path.clone(),
                    });
                }
                if f.size > MAX_FILE {
                    return Err(ManifestError::FileTooLarge {
                        path: f.path.clone(),
                        size: f.size,
                    });
                }
                total = total
                    .checked_add(f.size)
                    .ok_or(ManifestError::SizesOverflow)?;
                if must_be_sealed(self.kind, &f.path) && !f.sealed {
                    return Err(ManifestError::SecretNotSealed {
                        path: f.path.clone(),
                    });
                }
                if f.sealed && self.sealed.how == How::None {
                    return Err(ManifestError::SealedWithoutSealing {
                        path: f.path.clone(),
                    });
                }
                if !paths.insert(f.path.as_str()) {
                    return Err(ManifestError::PathTwice {
                        path: f.path.clone(),
                    });
                }
            }
        }
        Ok(())
    }
}

/// A path of an entry: relative, `/` separators, plain segments (no empty
/// one, no `.` or `..`, no `\`, `:` or control character), bounded.
pub fn check_path(path: &str) -> Result<(), PathError> {
    let bad = |fault: PathFault| {
        Err(PathError {
            path: path.to_owned(),
            fault,
        })
    };
    if path.is_empty() || path.len() > MAX_PATH {
        return bad(PathFault::Length);
    }
    if path == MANIFEST {
        return bad(PathFault::ManifestName);
    }
    let mut depth = 0;
    for seg in path.split('/') {
        depth += 1;
        if seg.is_empty() || seg == "." || seg == ".." {
            return bad(PathFault::Segment);
        }
        if seg.chars().any(|c| c == '\\' || c == ':' || c.is_control()) {
            return bad(PathFault::Character);
        }
    }
    if depth > MAX_DEPTH {
        return bad(PathFault::Depth);
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
        Zeroizing::new(wyrm_core::hex::sha256_parts(&[
            b"wyrm-backup-file\0",
            self.key.as_ref(),
            &self.id,
            b"\0",
            path.as_bytes(),
        ]))
    }

    fn mac_key(&self) -> ring::hmac::Key {
        let k = Zeroizing::new(wyrm_core::hex::sha256_parts(&[
            b"wyrm-backup-mac\0",
            self.key.as_ref(),
            &self.id,
        ]));
        ring::hmac::Key::new(ring::hmac::HMAC_SHA256, k.as_ref())
    }

    /// The MAC of `manifest` (hex) for its `sealed.mac`.
    fn mac_of(&self, manifest: &Manifest) -> Result<String, serde_json::Error> {
        Ok(hex::encode(
            ring::hmac::sign(&self.mac_key(), &manifest.mac_text()?).as_ref(),
        ))
    }

    fn check(&self) -> Result<String, wyrm_link_sdk::seal::SealError> {
        let sealed = wyrm_link_sdk::seal::seal(&self.key, CHECK_TEXT)?;
        Ok(hex::encode(sealed))
    }

    fn opens(&self, check: &str) -> bool {
        hex::decode(check)
            .ok()
            .and_then(|c| wyrm_link_sdk::seal::open(&self.key, &c))
            .is_some_and(|p| p == CHECK_TEXT)
    }
}

fn broker_key(secrets_key: &[u8], id: Vec<u8>) -> MasterKey {
    MasterKey {
        key: Zeroizing::new(wyrm_core::hex::sha256_parts(&[
            b"wyrm-backup-broker\0",
            secrets_key,
        ])),
        id,
    }
}

fn argon2(kdf: &Kdf, passphrase: &[u8], id: Vec<u8>) -> Result<MasterKey, KeyError> {
    if passphrase.len() < crate::keys::MIN_PASSPHRASE {
        return Err(KeyError::PassphraseTooShort);
    }
    // a manifest is not trusted with this host's memory and time
    if kdf.name != "argon2id" || kdf.m_kib > MAX_KDF_KIB || kdf.t > MAX_KDF_T || kdf.p > MAX_KDF_P {
        return Err(KeyError::KdfBounds);
    }
    let salt = hex::decode(&kdf.salt).map_err(KeyError::SaltHex)?;
    let params =
        argon2::Params::new(kdf.m_kib, kdf.t, kdf.p, Some(32)).map_err(KeyError::KdfParams)?;
    let mut key = Zeroizing::new([0u8; 32]);
    argon2::Argon2::new(argon2::Algorithm::Argon2id, argon2::Version::V0x13, params)
        .hash_password_into(passphrase, &salt, key.as_mut())
        .map_err(KeyError::Derivation)?;
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

fn new_id() -> Result<Vec<u8>, KeyError> {
    let mut id = [0u8; ID_LEN];
    wyrm_core::rand::fill(&mut id).map_err(KeyError::NoRandomness)?;
    Ok(id.to_vec())
}

impl Sealing<'_> {
    /// The `sealed` of the manifest (its `mac` is set by [`write`]) and the
    /// master key (none for `None`), with a fresh id of the backup.
    pub fn start(&self) -> Result<(Sealed, Option<MasterKey>), KeyError> {
        match self {
            Sealing::None => Ok((
                Sealed {
                    how: How::None,
                    kdf: None,
                    check: String::new(),
                    id: String::new(),
                    mac: String::new(),
                },
                None,
            )),
            Sealing::Passphrase(p) => {
                let mut salt = [0u8; SALT_LEN];
                wyrm_core::rand::fill(&mut salt).map_err(KeyError::NoRandomness)?;
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
                        how: How::Passphrase,
                        check: key.check().map_err(KeyError::Seal)?,
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
                        how: How::Broker,
                        kdf: None,
                        check: key.check().map_err(KeyError::Seal)?,
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
    ) -> Result<MasterKey, KeyError> {
        let id = hex::decode(&self.id).map_err(KeyError::IdHex)?;
        if id.len() != ID_LEN {
            return Err(KeyError::IdLength);
        }
        let key = match (self.how, &self.kdf) {
            (How::Passphrase, Some(kdf)) => {
                argon2(kdf, passphrase.ok_or(KeyError::PassphraseRequired)?, id)?
            }
            (How::Broker, _) => broker_key(secrets_key.ok_or(KeyError::BrokerKeyRequired)?, id),
            _ => return Err(KeyError::NotSealed),
        };
        if !key.opens(&self.check) {
            return Err(match self.how {
                How::Passphrase => KeyError::WrongPassphrase,
                _ => KeyError::AnotherBroker,
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
    src: impl Read,
    dst: impl Write,
) -> std::io::Result<u64> {
    seal_stream_with(key, path, src, dst, wyrm_link_sdk::seal::seal)
}

/// [`seal_stream`] with the part sealer given: the product code passes
/// [`wyrm_link_sdk::seal::seal`]; a test passes one that fails as a host
/// without randomness does. A sealer error ends the stream with that error.
fn seal_stream_with(
    key: &MasterKey,
    path: &str,
    mut src: impl Read,
    mut dst: impl Write,
    mut seal: impl FnMut(&[u8; 32], &[u8]) -> Result<Vec<u8>, wyrm_link_sdk::seal::SealError>,
) -> std::io::Result<u64> {
    let fk = key.file_key(path);
    dst.write_all(SEAL_MAGIC)?;
    let mut total = 0u64;
    let mut index = 0u64;
    let mut cur = part(&mut src, SEAL_PART)?;
    loop {
        // one part ahead, to mark the last one
        let next = if cur.len() == SEAL_PART {
            part(&mut src, SEAL_PART)?
        } else {
            Vec::new()
        };
        let last = next.is_empty();
        let mut plain = Zeroizing::new(Vec::with_capacity(9 + cur.len()));
        plain.extend_from_slice(&index.to_be_bytes());
        plain.push(u8::from(last));
        plain.extend_from_slice(&cur);
        let sealed = seal(&fk, &plain).map_err(std::io::Error::other)?;
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

/// Up to `max` bytes of `src`: fewer only at its end.
fn part(src: &mut impl Read, max: usize) -> std::io::Result<Vec<u8>> {
    let mut buf = vec![0u8; max];
    let n = wyrm_core::files::read_full(src, &mut buf)?;
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
) -> Result<u64, SealedError> {
    let fk = key.file_key(path);
    let io = |source: std::io::Error| SealedError::Io {
        path: path.to_owned(),
        source,
    };
    let cut = |source: std::io::Error| SealedError::CutShort {
        path: path.to_owned(),
        source,
    };
    let mut magic = [0u8; 5];
    src.read_exact(&mut magic).map_err(io)?;
    if &magic != SEAL_MAGIC {
        return Err(SealedError::NotSealed {
            path: path.to_owned(),
        });
    }
    let mut total = 0u64;
    let mut index = 0u64;
    loop {
        let mut len = [0u8; 4];
        src.read_exact(&mut len).map_err(cut)?;
        let len = u32::from_be_bytes(len) as usize;
        if len > SEAL_PART + 64 {
            return Err(SealedError::PartTooLarge {
                path: path.to_owned(),
                len,
            });
        }
        let mut sealed = vec![0u8; len];
        src.read_exact(&mut sealed).map_err(cut)?;
        let plain = Zeroizing::new(wyrm_link_sdk::seal::open(&fk, &sealed).ok_or_else(|| {
            SealedError::DoesNotOpen {
                path: path.to_owned(),
            }
        })?);
        if plain.len() < 9 || plain[..8] != index.to_be_bytes() {
            return Err(SealedError::OutOfOrder {
                path: path.to_owned(),
            });
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
        return Err(SealedError::Trailing {
            path: path.to_owned(),
        });
    }
    dst.flush().map_err(io)?;
    Ok(total)
}

/// Seal `plain` as the sealed file `path`, in memory. `Err` when a part
/// does not seal (no randomness for its nonce): a caller never gets the
/// magic alone as a sealed file that only fails at restore.
pub fn seal_bytes(key: &MasterKey, path: &str, plain: &[u8]) -> std::io::Result<Vec<u8>> {
    seal_bytes_with(key, path, plain, wyrm_link_sdk::seal::seal)
}

fn seal_bytes_with(
    key: &MasterKey,
    path: &str,
    plain: &[u8],
    seal: impl FnMut(&[u8; 32], &[u8]) -> Result<Vec<u8>, wyrm_link_sdk::seal::SealError>,
) -> std::io::Result<Vec<u8>> {
    let mut out = Vec::with_capacity(plain.len() + 64);
    seal_stream_with(key, path, plain, &mut out, seal)?;
    Ok(out)
}

/// Open what [`seal_bytes`] made.
pub fn open_bytes(
    key: &MasterKey,
    path: &str,
    sealed: &[u8],
) -> Result<Zeroizing<Vec<u8>>, SealedError> {
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
#[derive(Debug, Clone)]
pub struct StagedSection {
    pub name: SectionName,
    pub info: serde_json::Map<String, serde_json::Value>,
    pub files: Vec<Staged>,
}

impl StagedSection {
    /// Section `name`, nothing in it yet.
    pub fn new(name: SectionName) -> Self {
        Self {
            name,
            info: serde_json::Map::new(),
            files: Vec::new(),
        }
    }
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
    let (sum, size) = wyrm_core::hex::sha256_reader(File::open(path)?)?;
    Ok((size, wyrm_core::hex::encode(sum)))
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
) -> Result<Written, WriteError> {
    use zip::write::SimpleFileOptions;
    let io = |what: &Path, source: std::io::Error| WriteError::Io {
        path: what.to_owned(),
        source,
    };
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
            name: s.name,
            info: s.info.clone(),
            files,
        });
    }
    match key {
        Some(k) if manifest.sealed.how != How::None => {
            if hex::encode(&k.id) != manifest.sealed.id {
                return Err(WriteError::KeyOfAnotherBackup);
            }
            manifest.sealed.mac = k.mac_of(&manifest).map_err(WriteError::Encode)?;
        }
        None if manifest.sealed.how == How::None => {}
        _ => return Err(WriteError::KeyAndSealing),
    }
    manifest.check()?;
    let total = manifest.size();
    let text = serde_json::to_vec_pretty(&manifest).map_err(WriteError::Encode)?;
    if text.len() as u64 > MAX_MANIFEST {
        return Err(WriteError::ManifestTooLarge);
    }
    let part = out.with_extension(format!(
        "{}.part",
        out.extension().and_then(|e| e.to_str()).unwrap_or("zip")
    ));
    wyrm_core::files::discard(&part);
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
            .map_err(WriteError::Zip)?;
        w.write_all(&text).map_err(|e| io(&part, e))?;
        let mut done = 0u64;
        let mut buf = vec![0u8; 256 << 10];
        for (s, m) in sections.iter().zip(&manifest.sections) {
            for (f, e) in s.files.iter().zip(&m.files) {
                w.start_file(e.path.as_str(), opt(e.sealed, e.size))
                    .map_err(WriteError::Zip)?;
                let mut src = File::open(&f.source).map_err(|e| io(&f.source, e))?;
                // hashed again as it goes in: a source that changed since the
                // manifest was made fails the backup instead of spoiling it
                let mut h = wyrm_core::hex::Sha256Stream::new();
                let mut left = e.size;
                while left > 0 {
                    let want = buf.len().min(left as usize);
                    let n = src.read(&mut buf[..want]).map_err(|e| io(&f.source, e))?;
                    if n == 0 {
                        return Err(WriteError::SourceChanged {
                            path: f.source.clone(),
                        });
                    }
                    h.update(&buf[..n]);
                    w.write_all(&buf[..n]).map_err(|e| io(&part, e))?;
                    left -= n as u64;
                    done += n as u64;
                    progress(done, total);
                }
                if h.finish_hex() != e.sha256 {
                    return Err(WriteError::SourceChanged {
                        path: f.source.clone(),
                    });
                }
            }
        }
        let inner = w.finish().map_err(WriteError::Zip)?;
        let file = inner
            .into_inner()
            .map_err(|e| WriteError::Flush(e.into_error()))?;
        file.sync_all().map_err(|e| io(&part, e))?;
        Ok(())
    })();
    if let Err(e) = result {
        wyrm_core::files::discard(&part);
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
    pub fn open(path: &Path, max_total: u64) -> Result<Self, ReadError> {
        let f = File::open(path).map_err(|source| ReadError::File {
            path: path.to_owned(),
            source,
        })?;
        Self::new(f, max_total)
    }
}

impl<R: Read + Seek> Reader<R> {
    pub fn new(mut src: R, max_total: u64) -> Result<Self, ReadError> {
        let len = src
            .seek(std::io::SeekFrom::End(0))
            .map_err(ReadError::Seek)?;
        let mut zip = zip::ZipArchive::new(src).map_err(ReadError::NotZip)?;
        if zip.is_empty() || zip.len() > MAX_ENTRIES {
            return Err(ReadError::EntryCount { found: zip.len() });
        }
        let manifest: Manifest = {
            let first = zip.by_index(0).map_err(ReadError::NotZip)?;
            if first.name().ok().as_deref() != Some(MANIFEST) {
                return Err(ReadError::ManifestNotFirst);
            }
            if first.size() > MAX_MANIFEST {
                return Err(ReadError::ManifestTooLarge);
            }
            let mut text = Vec::new();
            first
                .take(MAX_MANIFEST + 1)
                .read_to_end(&mut text)
                .map_err(ReadError::ManifestRead)?;
            if text.len() as u64 > MAX_MANIFEST {
                return Err(ReadError::ManifestTooLarge);
            }
            serde_json::from_slice(&text).map_err(ReadError::ManifestJson)?
        };
        manifest.check()?;
        if manifest.size() > max_total {
            return Err(ReadError::OverLimit {
                size: manifest.size(),
                max: max_total,
            });
        }
        // before anything is extracted: what the file says it opens into
        // is bounded by its own size and by what each part may be
        if manifest.size() > len.saturating_mul(MAX_RATIO).saturating_add(RATIO_SLACK) {
            return Err(ReadError::Ratio {
                len,
                size: manifest.size(),
            });
        }
        manifest.caps()?;
        let files: BTreeMap<String, FileEntry> = manifest
            .sections
            .iter()
            .flat_map(|s| s.files.iter())
            .map(|f| (f.path.clone(), f.clone()))
            .collect();
        if zip.len() != files.len() + 1 {
            return Err(ReadError::EntriesAndManifest {
                entries: zip.len() - 1,
                listed: files.len(),
            });
        }
        for i in 1..zip.len() {
            let e = zip.by_index(i).map_err(ReadError::Zip)?;
            let name = e.name().map_err(ReadError::Zip)?;
            let Some(f) = files.get(name.as_ref()) else {
                return Err(ReadError::UnlistedEntry {
                    name: name.into_owned(),
                });
            };
            if e.is_dir() || e.is_symlink() || e.size() != f.size {
                return Err(ReadError::EntryNotAsListed {
                    path: f.path.clone(),
                    size: f.size,
                });
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

    /// What the manifest lists for `path`.
    fn listed(&self, path: &str) -> Result<&FileEntry, ReadError> {
        self.files.get(path).ok_or_else(|| ReadError::NotInBackup {
            path: path.to_owned(),
        })
    }

    /// Copy the stored bytes of `path` into `dst`, checking size and SHA-256.
    fn copy(&mut self, path: &str, dst: &mut dyn Write) -> Result<u64, ReadError> {
        let f = self.listed(path)?.clone();
        let e = self.zip.by_name(path).map_err(|source| ReadError::Entry {
            path: path.to_owned(),
            source,
        })?;
        // one byte more than listed shows a longer entry (a zip bomb)
        let mut src = e.take(f.size + 1);
        let mut h = wyrm_core::hex::Sha256Stream::new();
        let mut buf = vec![0u8; 256 << 10];
        let mut n = 0u64;
        loop {
            let k = src.read(&mut buf).map_err(|source| ReadError::Stored {
                path: path.to_owned(),
                source,
            })?;
            if k == 0 {
                break;
            }
            n += k as u64;
            if n > f.size {
                return Err(ReadError::Longer {
                    path: path.to_owned(),
                });
            }
            h.update(&buf[..k]);
            dst.write_all(&buf[..k])
                .map_err(|source| ReadError::Output {
                    path: path.to_owned(),
                    source,
                })?;
        }
        if n != f.size || !h.finish_hex().eq_ignore_ascii_case(&f.sha256) {
            return Err(ReadError::Differs {
                path: path.to_owned(),
            });
        }
        Ok(n)
    }

    /// Read every file and check it. `progress(done, total)` in stored bytes.
    pub fn verify(&mut self, mut progress: impl FnMut(u64, u64)) -> Result<(), ReadError> {
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
    pub fn read(&mut self, path: &str) -> Result<Vec<u8>, ReadError> {
        let size = self.listed(path)?.size;
        if size > MAX_IN_MEMORY {
            return Err(ReadError::TooLargeInMemory {
                path: path.to_owned(),
                size,
            });
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
    ) -> Result<Zeroizing<Vec<u8>>, ReadError> {
        // the reader decides what must be sealed, not the file's flag
        // (`Manifest::check` refused a secret file listed as plain)
        let sealed = self.files.get(path).is_some_and(|f| f.sealed)
            || must_be_sealed(self.manifest.kind, path);
        let stored = Zeroizing::new(self.read(path)?);
        if !sealed {
            return Ok(stored);
        }
        let key = key.ok_or_else(|| ReadError::NoKey {
            path: path.to_owned(),
        })?;
        Ok(open_bytes(key, path, &stored)?)
    }

    /// Write the plain content of `path` to the new file `dest` (parents
    /// created; 0600, or 0700 for an `exec` entry; refused when it exists).
    /// A sealed file is opened with `key`. On an error `dest` is removed.
    /// No other path is written: `dest` is the only file this makes.
    pub fn extract(
        &mut self,
        path: &str,
        dest: &Path,
        key: Option<&MasterKey>,
    ) -> Result<u64, ReadError> {
        let f = self.listed(path)?.clone();
        let io = |source: std::io::Error| ReadError::File {
            path: dest.to_owned(),
            source,
        };
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
                let key = key.ok_or_else(|| ReadError::NoKey {
                    path: path.to_owned(),
                })?;
                // sealed files are checked whole first, then opened part by part:
                // the entry is read twice from the backup itself, and its stored
                // bytes are kept in no file (a path beside `dest` can be another
                // entry's, somebody's file or a symlink)
                self.copy(path, &mut std::io::sink())?;
                let src = self.zip.by_name(path).map_err(|source| ReadError::Entry {
                    path: path.to_owned(),
                    source,
                })?;
                open_stream(key, path, src, &mut out)?
            } else {
                self.copy(path, &mut out)?
            };
            let file = out
                .into_inner()
                .map_err(|e| ReadError::Flush(e.into_error()))?;
            file.sync_all().map_err(io)?;
            Ok::<_, ReadError>(n)
        })();
        if r.is_err() {
            // what was written of it: never a whole file
            wyrm_core::files::discard(dest);
        }
        r
    }
}

/// The manifest of the backup at `path` without checking its files' content.
pub fn read_manifest(path: &Path) -> Result<Manifest, ReadError> {
    Reader::open(path, u64::MAX).map(|r| r.manifest)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Cursor;

    /// Review T5: `sealed.how` was a `String` checked against three names. A manifest
    /// written then reads into [`How`] and serializes to the same bytes, so its MAC (over
    /// the canonical JSON) still holds; another name does not decode.
    #[test]
    fn sealed_how_keeps_the_manifest_bytes() {
        #[derive(Serialize)]
        struct OldSealed<'a> {
            how: &'a str,
            #[serde(skip_serializing_if = "str::is_empty")]
            check: &'a str,
            #[serde(skip_serializing_if = "str::is_empty")]
            id: &'a str,
            #[serde(skip_serializing_if = "str::is_empty")]
            mac: &'a str,
        }
        for (how, check, id, mac) in [
            ("none", "", "", ""),
            ("broker", "c0ffee", "00112233445566778899aabbccddeeff", "ab"),
        ] {
            let bytes = serde_json::to_vec(&OldSealed {
                how,
                check,
                id,
                mac,
            })
            .unwrap();
            let new: Sealed = serde_json::from_slice(&bytes).unwrap();
            assert_eq!(new.how.name(), how);
            assert_eq!(serde_json::to_vec(&new).unwrap(), bytes);
        }
        let bad = br#"{"how":"Broker"}"#;
        let e = serde_json::from_slice::<Sealed>(bad)
            .unwrap_err()
            .to_string();
        assert!(e.contains("backup sealing: unknown name"), "{e}");
    }

    /// Review 2026-11-16: `LinkInfo.mode` was a `String` filled from `Mode::name()`. A
    /// manifest written then reads into [`crate::registry::Mode`] and serializes to the
    /// same bytes, so its MAC (over the JSON, `mac_text`) still holds; a name that is no
    /// link mode refuses the manifest instead of reaching a restore as text.
    #[test]
    fn link_mode_keeps_the_manifest_bytes() {
        #[derive(Serialize)]
        struct OldLinkInfo<'a> {
            id: &'a str,
            driver: &'a str,
            mode: &'a str,
            #[serde(skip_serializing_if = "str::is_empty")]
            package: &'a str,
            #[serde(skip_serializing_if = "str::is_empty")]
            version: &'a str,
        }
        for mode in ["embedded", "process", "external"] {
            let bytes = serde_json::to_vec(&OldLinkInfo {
                id: "l1",
                driver: "pkg:x",
                mode,
                package: "x",
                version: "1.0.0",
            })
            .unwrap();
            let new: LinkInfo = serde_json::from_slice(&bytes).unwrap();
            assert_eq!(new.mode.name(), mode);
            assert_eq!(serde_json::to_vec(&new).unwrap(), bytes);
        }
        let bad = br#"{"id":"l1","driver":"mock","mode":"Process"}"#;
        assert!(serde_json::from_slice::<LinkInfo>(bad).is_err());
    }

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
                name: SectionName::Control,
                info: serde_json::Map::from_iter([("lsn".to_owned(), 3.into())]),
                files: vec![Staged {
                    path: "control/state/wal.00000000000000000001.wyw".into(),
                    source: d.join("wal"),
                    sealed: false,
                    exec: false,
                }],
            },
            StagedSection {
                name: SectionName::Keys,
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
        assert!(matches!(
            r.read_plain("keys/pki/ca.key", None),
            Err(ReadError::NoKey { path }) if path == "keys/pki/ca.key"
        ));
        let key = r.manifest().key(Some(PASS), None).unwrap();
        assert_eq!(
            r.read_plain("keys/pki/ca.key", Some(&key)).unwrap().len(),
            SEAL_PART + 10
        );
        assert!(matches!(
            r.manifest().key(Some(b"wrong passphrase!"), None),
            Err(KeyError::WrongPassphrase)
        ));
        assert!(matches!(
            r.manifest().key(Some(b"short"), None),
            Err(KeyError::PassphraseTooShort)
        ));
        assert!(matches!(
            r.manifest().key(None, Some(b"k")),
            Err(KeyError::PassphraseRequired)
        ));
        // extracted: content, owner-only, never over a file
        let dest = d.join("out/pki/ca.key");
        assert_eq!(
            r.extract("keys/pki/ca.key", &dest, Some(&key)).unwrap(),
            (SEAL_PART + 10) as u64
        );
        assert_eq!(std::fs::read(&dest).unwrap(), vec![7u8; SEAL_PART + 10]);
        assert!(matches!(
            r.extract("keys/pki/ca.key", &dest, Some(&key)),
            Err(ReadError::File { path, source })
                if path == dest && source.kind() == std::io::ErrorKind::AlreadyExists
        ));
        assert_eq!(std::fs::read(&dest).unwrap(), vec![7u8; SEAL_PART + 10]);
        // a sealed file without its key leaves nothing behind
        let bare = d.join("out/pki/bare.key");
        assert!(matches!(
            r.extract("keys/pki/ca.key", &bare, None),
            Err(ReadError::NoKey { .. })
        ));
        assert!(!bare.exists());
        assert!(matches!(
            r.read("keys/none"),
            Err(ReadError::NotInBackup { path }) if path == "keys/none"
        ));
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mode = std::fs::metadata(&dest).unwrap().permissions().mode();
            assert_eq!(mode & 0o777, 0o600);
        }
        // the size bound of the reader
        assert!(matches!(
            Reader::open(&path, 100),
            Err(ReadError::OverLimit { max: 100, .. })
        ));
        assert_eq!(read_manifest(&path).unwrap(), w.manifest);
        assert!(matches!(
            Reader::open(&d.join("none.wyrm-backup"), 1 << 30),
            Err(ReadError::File { source, .. }) if source.kind() == std::io::ErrorKind::NotFound
        ));
    }

    /// A backup whose `keys` section holds one sealed file per name in
    /// `names` (all in `keys/pki`); the content of `<name>` is [`secret_of`].
    fn sealed_files(d: &Path, names: &[&str]) -> (PathBuf, MasterKey) {
        let (sealed, key) = Sealing::Passphrase(PASS).start().unwrap();
        let key = key.unwrap();
        let mut files = Vec::new();
        for (i, name) in names.iter().enumerate() {
            let path = format!("keys/pki/{name}");
            let source = d.join(format!("staged-{i}"));
            let mut out = File::create(&source).unwrap();
            seal_stream(&key, &path, secret_of(name).as_slice(), &mut out).unwrap();
            files.push(Staged {
                path,
                source,
                sealed: true,
                exec: false,
            });
        }
        let sections = vec![StagedSection {
            name: SectionName::Keys,
            info: Default::default(),
            files,
        }];
        let out = d.join("b.wyrm-backup");
        write(&out, head(sealed), sections, Some(&key), |_, _| {}).unwrap();
        (out, key)
    }

    /// More than one sealed part, and different for every name.
    fn secret_of(name: &str) -> Vec<u8> {
        let mut v = vec![name.len() as u8; SEAL_PART + 10];
        v.extend_from_slice(name.as_bytes());
        v
    }

    /// Issue #190: the stored bytes of a sealed file were kept in
    /// `dest.with_extension("sealed-part")`. For an entry of that extension
    /// the path was `dest` itself: written over, then removed, with `Ok`.
    #[test]
    fn a_sealed_file_named_as_the_old_temporary_file_is_extracted() {
        let d = dir("extract-own-name");
        let (path, key) = sealed_files(&d, &["a.sealed-part"]);
        let mut r = Reader::open(&path, 1 << 30).unwrap();
        let dest = d.join("out/pki/a.sealed-part");
        let want = secret_of("a.sealed-part");
        assert_eq!(
            r.extract("keys/pki/a.sealed-part", &dest, Some(&key))
                .unwrap(),
            want.len() as u64
        );
        assert!(dest.exists(), "the extracted file is there");
        assert_eq!(std::fs::read(&dest).unwrap(), want);
    }

    /// Issue #190: `x.sealed-part` extracted first was the temporary file of
    /// `x.bin` after it, so it was written over and removed.
    #[test]
    fn two_sealed_files_of_one_folder_are_both_extracted() {
        let d = dir("extract-pair");
        let (path, key) = sealed_files(&d, &["x.sealed-part", "x.bin"]);
        let mut r = Reader::open(&path, 1 << 30).unwrap();
        for name in ["x.sealed-part", "x.bin"] {
            let dest = d.join("out/pki").join(name);
            r.extract(&format!("keys/pki/{name}"), &dest, Some(&key))
                .unwrap();
        }
        for name in ["x.sealed-part", "x.bin"] {
            let dest = d.join("out/pki").join(name);
            assert!(dest.exists(), "{name} is there");
            assert_eq!(std::fs::read(&dest).unwrap(), secret_of(name), "{name}");
        }
        // and nothing else is left in the folder
        let mut left: Vec<_> = std::fs::read_dir(d.join("out/pki"))
            .unwrap()
            .map(|e| e.unwrap().file_name().into_string().unwrap())
            .collect();
        left.sort();
        assert_eq!(left, ["x.bin", "x.sealed-part"]);
    }

    /// Issue #190: the temporary file was opened with `File::create`, which
    /// follows a symlink: the file it named was written over with the stored
    /// bytes and the link removed.
    #[cfg(unix)]
    #[test]
    fn extract_follows_no_symlink_beside_the_destination() {
        let d = dir("extract-symlink");
        let (path, key) = sealed_files(&d, &["x.bin"]);
        let mut r = Reader::open(&path, 1 << 30).unwrap();
        let victim = d.join("victim");
        std::fs::write(&victim, b"not a backup's business").unwrap();
        std::fs::create_dir_all(d.join("out/pki")).unwrap();
        let link = d.join("out/pki/x.sealed-part");
        std::os::unix::fs::symlink(&victim, &link).unwrap();
        let dest = d.join("out/pki/x.bin");
        r.extract("keys/pki/x.bin", &dest, Some(&key)).unwrap();
        assert_eq!(std::fs::read(&dest).unwrap(), secret_of("x.bin"));
        assert_eq!(std::fs::read(&victim).unwrap(), b"not a backup's business");
        assert_eq!(std::fs::read_link(&link).unwrap(), victim);
    }

    /// Issue #190: a file that was there at the temporary path was truncated
    /// and removed.
    #[test]
    fn extract_leaves_the_files_beside_the_destination() {
        let d = dir("extract-neighbour");
        let (path, key) = sealed_files(&d, &["x.bin"]);
        let mut r = Reader::open(&path, 1 << 30).unwrap();
        std::fs::create_dir_all(d.join("out/pki")).unwrap();
        let other = d.join("out/pki/x.sealed-part");
        std::fs::write(&other, b"somebody's file").unwrap();
        let dest = d.join("out/pki/x.bin");
        r.extract("keys/pki/x.bin", &dest, Some(&key)).unwrap();
        assert_eq!(std::fs::read(&dest).unwrap(), secret_of("x.bin"));
        assert_eq!(std::fs::read(&other).unwrap(), b"somebody's file");
        // an extract that fails leaves them too, and no file of its own
        let bare = d.join("out/pki/x.other");
        assert!(matches!(
            r.extract("keys/pki/x.bin", &bare, None),
            Err(ReadError::NoKey { .. })
        ));
        assert!(!bare.exists());
        assert_eq!(std::fs::read(&other).unwrap(), b"somebody's file");
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
            assert!(matches!(e, KeyError::KdfBounds), "{e}");
            assert!(
                started.elapsed() < std::time::Duration::from_millis(200),
                "refused before any work"
            );
        }
    }

    #[test]
    fn broker_sealing_opens_only_with_the_same_key() {
        let (m, key) = signed(Sealing::Broker(b"secrets key"));
        let s = seal_bytes(&key, "data/x", b"").unwrap();
        assert_eq!(
            open_bytes(&key, "data/x", &s).unwrap().len(),
            0,
            "an empty file"
        );
        let k2 = m.key(None, Some(b"secrets key")).unwrap();
        assert!(open_bytes(&k2, "data/x", &s).is_ok());
        assert!(matches!(
            m.key(None, Some(b"another key")),
            Err(KeyError::AnotherBroker)
        ));
        assert!(matches!(
            m.key(Some(PASS), None),
            Err(KeyError::BrokerKeyRequired)
        ));
        let (none, k) = Sealing::None.start().unwrap();
        assert!(k.is_none());
        assert!(matches!(
            none.master(Some(PASS), None),
            Err(KeyError::IdLength)
        ));
        // `how: none` with an id (a manifest `check` refuses) still gives no key
        let mut odd = none.clone();
        odd.id = m.sealed.id.clone();
        assert!(matches!(
            odd.master(Some(PASS), Some(b"secrets key")),
            Err(KeyError::NotSealed)
        ));
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
        let changed = |e: Option<KeyError>| matches!(e, Some(KeyError::ManifestChanged));
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
        assert!(matches!(bare.check(), Err(ManifestError::NotAuthenticated)));
        let mut bare = m.clone();
        bare.sealed.id.clear();
        assert!(matches!(bare.check(), Err(ManifestError::NotAuthenticated)));
        // a MAC or an id that is not hex is told from a changed manifest
        let mut odd = m.clone();
        odd.sealed.mac = "zz".repeat(32);
        assert!(matches!(
            odd.key(None, Some(b"secrets key")),
            Err(KeyError::MacHex(_))
        ));
        odd.sealed.id = "zz".repeat(16);
        assert!(matches!(
            odd.key(None, Some(b"secrets key")),
            Err(KeyError::IdHex(_))
        ));
        // and an unsealed one cannot claim to be authenticated
        let mut plain = manifest_with(&[("control/a", 3, b"abc")]);
        plain.sealed.mac = m.sealed.mac.clone();
        assert!(matches!(
            plain.check(),
            Err(ManifestError::AuthenticationWithoutSealing)
        ));
        // the writer signs only with the key of that backup
        let (_, other) = signed(Sealing::Broker(b"secrets key"));
        let d = dir("wrongkey");
        let head = Head {
            sealed: m.sealed.clone(),
            ..head(m.sealed.clone())
        };
        assert!(matches!(
            write(
                &d.join("x.wyrm-backup"),
                head.clone(),
                vec![],
                Some(&other),
                |_, _| {}
            ),
            Err(WriteError::KeyOfAnotherBackup)
        ));
        assert!(matches!(
            write(&d.join("x.wyrm-backup"), head, vec![], None, |_, _| {}),
            Err(WriteError::KeyAndSealing)
        ));
        assert!(!d.join("x.wyrm-backup").exists());
    }

    #[test]
    fn sizes_that_overflow_are_refused() {
        // two files whose sizes wrap around to a small sum
        let mut m = manifest_with(&[("control/a", 3, b"abc"), ("control/b", 3, b"abc")]);
        m.sections[0].files[0].size = u64::MAX;
        m.sections[0].files[1].size = 2;
        assert_eq!(m.size(), u64::MAX, "never a small number");
        assert_eq!(m.sections[0].size(), u64::MAX);
        assert!(matches!(
            m.check(),
            Err(ManifestError::FileTooLarge { size: u64::MAX, .. })
        ));
        // within one file's bound each, still more than u64 in all
        let mut m = manifest_with(&[("control/a", 3, b"abc")]);
        m.sections[0].files[0].size = MAX_FILE + 1;
        assert!(matches!(
            m.check(),
            Err(ManifestError::FileTooLarge { path, size }) if path == "control/a" && size == MAX_FILE + 1
        ));
        m.sections[0].files[0].size = MAX_FILE;
        m.check().unwrap();
        // the reader's bound holds for the sum
        let zip = zip_of(&serde_json::to_vec(&m).unwrap(), &[("control/a", b"abc")]);
        assert!(matches!(
            Reader::new(Cursor::new(zip), 1 << 30),
            Err(ReadError::OverLimit { size: MAX_FILE, max }) if max == 1 << 30
        ));
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
        f.sha256 = wyrm_core::hex::sha256_hex(b"forged");
        assert!(matches!(
            m.check(),
            Err(ManifestError::SecretNotSealed { path }) if path == "keys/pki/ca.key"
        ));
        let wal = std::fs::read(d.join("wal")).unwrap();
        let zip = zip_of(
            &serde_json::to_vec(&m).unwrap(),
            &[
                ("control/state/wal.00000000000000000001.wyw", &wal),
                ("keys/pki/ca.key", b"forged"),
            ],
        );
        assert!(matches!(
            Reader::new(Cursor::new(zip), 1 << 30),
            Err(ReadError::Manifest(ManifestError::SecretNotSealed { .. }))
        ));
        // with `how: none` there is no sealed file, so no secret file at all
        let mut m = manifest_with(&[("control/a", 3, b"abc")]);
        m.sections[0].name = SectionName::Keys;
        m.sections[0].files[0].path = "keys/state.key".into();
        assert!(matches!(
            m.check(),
            Err(ManifestError::SecretNotSealed { .. })
        ));
        m.sections[0].files[0].sealed = true;
        assert!(matches!(
            m.check(),
            Err(ManifestError::SealedWithoutSealing { path }) if path == "keys/state.key"
        ));
        let _ = path;
    }

    #[test]
    fn a_sealed_part_of_another_backup_does_not_open() {
        // the same passphrase (here: the same broker key), two backups
        let (_, a) = signed(Sealing::Broker(b"secrets key"));
        let (_, b) = signed(Sealing::Broker(b"secrets key"));
        let in_a = seal_bytes(&a, "keys/state.key", b"the key of a").unwrap();
        let in_b = seal_bytes(&b, "keys/state.key", b"the key of b").unwrap();
        assert_eq!(
            &**open_bytes(&a, "keys/state.key", &in_a).unwrap(),
            b"the key of a"
        );
        // the whole file, and one part, moved from b into a
        assert!(matches!(
            open_bytes(&a, "keys/state.key", &in_b),
            Err(SealedError::DoesNotOpen { path }) if path == "keys/state.key"
        ));
        let plain = vec![3u8; SEAL_PART + 1];
        let (long_a, long_b) = (
            seal_bytes(&a, "keys/x", &plain).unwrap(),
            seal_bytes(&b, "keys/x", &plain).unwrap(),
        );
        let part = 4 + SEAL_PART + 9 + 28;
        let mut mixed = long_a[..5 + part].to_vec();
        mixed.extend_from_slice(&long_b[5 + part..]);
        assert!(matches!(
            open_bytes(&a, "keys/x", &mixed),
            Err(SealedError::DoesNotOpen { .. })
        ));
        assert!(open_bytes(&a, "keys/x", &long_a).is_ok());
    }

    #[test]
    fn sealed_parts_are_bound_to_their_file_and_place() {
        let (_, key) = signed(Sealing::Broker(b"k"));
        let plain: Vec<u8> = (0..(2 * SEAL_PART + 5)).map(|i| (i % 251) as u8).collect();
        let sealed = seal_bytes(&key, "data/a", &plain).unwrap();
        assert_eq!(*open_bytes(&key, "data/a", &sealed).unwrap(), plain);
        // another path
        assert!(matches!(
            open_bytes(&key, "data/b", &sealed),
            Err(SealedError::DoesNotOpen { path }) if path == "data/b"
        ));
        // a changed byte
        let mut bad = sealed.clone();
        bad[100] ^= 1;
        assert!(matches!(
            open_bytes(&key, "data/a", &bad),
            Err(SealedError::DoesNotOpen { .. })
        ));
        // the last part cut off, and the first two parts swapped
        let part = 4 + SEAL_PART + 9 + 28;
        assert!(matches!(
            open_bytes(&key, "data/a", &sealed[..5 + 2 * part]),
            Err(SealedError::CutShort { .. })
        ));
        assert!(matches!(
            open_bytes(&key, "data/a", &sealed[..5 + 2 * part + 10]),
            Err(SealedError::CutShort { .. })
        ));
        let mut swapped = sealed[..5].to_vec();
        swapped.extend_from_slice(&sealed[5 + part..5 + 2 * part]);
        swapped.extend_from_slice(&sealed[5..5 + part]);
        swapped.extend_from_slice(&sealed[5 + 2 * part..]);
        assert!(matches!(
            open_bytes(&key, "data/a", &swapped),
            Err(SealedError::OutOfOrder { .. })
        ));
        // bytes after the end
        let mut longer = sealed.clone();
        longer.push(0);
        assert!(matches!(
            open_bytes(&key, "data/a", &longer),
            Err(SealedError::Trailing { .. })
        ));
        // not a sealed file at all, and a part that says it is too long
        assert!(matches!(
            open_bytes(&key, "data/a", b"plain bytes"),
            Err(SealedError::NotSealed { .. })
        ));
        assert!(matches!(
            open_bytes(&key, "data/a", b"WY"),
            Err(SealedError::Io { .. })
        ));
        let mut huge = sealed[..5].to_vec();
        huge.extend_from_slice(&u32::MAX.to_be_bytes());
        assert!(matches!(
            open_bytes(&key, "data/a", &huge),
            Err(SealedError::PartTooLarge { len, .. }) if len == u32::MAX as usize
        ));
        // exactly one part: the next read is empty, the part is the last
        let one = vec![1u8; SEAL_PART];
        let s = seal_bytes(&key, "data/a", &one).unwrap();
        assert_eq!(*open_bytes(&key, "data/a", &s).unwrap(), one);
    }

    /// A host without randomness cannot seal a part: the file is refused, not
    /// written as the magic alone (which only failed at restore).
    #[test]
    fn a_part_that_does_not_seal_fails_the_file() {
        let (_, key) = signed(Sealing::Broker(b"secrets key"));
        let no_rng = |_: &[u8; 32], _: &[u8]| Err(wyrm_link_sdk::seal::SealError);
        assert!(seal_bytes_with(&key, "data/a", b"plain", no_rng).is_err());
        // the second part fails: the first one sealed, the file still fails
        let mut n = 0;
        let second_fails = |k: &[u8; 32], p: &[u8]| {
            n += 1;
            if n == 2 {
                Err(wyrm_link_sdk::seal::SealError)
            } else {
                wyrm_link_sdk::seal::seal(k, p)
            }
        };
        let two = vec![7u8; SEAL_PART + 1];
        assert!(seal_bytes_with(&key, "data/a", &two, second_fails).is_err());
        let mut out = Vec::new();
        assert!(seal_stream_with(&key, "data/a", &b"x"[..], &mut out, no_rng).is_err());
    }

    #[test]
    fn paths_that_leave_the_backup_are_refused() {
        use PathFault as F;
        let deep = format!("control/{}a", "a/".repeat(30));
        let long = "a".repeat(MAX_PATH + 1);
        for (p, fault) in [
            ("", F::Length),
            ("/etc/passwd", F::Segment),
            ("control/../../x", F::Segment),
            ("control/./x", F::Segment),
            ("control//x", F::Segment),
            ("control\\x", F::Character),
            ("c:/x", F::Character),
            ("control/x\n", F::Character),
            ("manifest.json", F::ManifestName),
            ("control/", F::Segment),
            (deep.as_str(), F::Depth),
            (long.as_str(), F::Length),
        ] {
            let e = check_path(p).unwrap_err();
            assert_eq!((e.path.as_str(), e.fault), (p, fault));
        }
        assert!(check_path(&format!("control/{}", "a/".repeat(30))).is_err());
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

    /// Review 2026-11-16: section names were text. A manifest written then (`"name":
    /// "keys"`) reads into [`SectionName`] and writes the same bytes, so its MAC (over the
    /// JSON) still holds; a section this build does not know refuses the manifest, since
    /// what must be sealed and what is restored depends on it.
    #[test]
    fn section_names_keep_the_manifest_bytes_and_an_unknown_one_is_refused() {
        #[derive(Serialize)]
        struct OldSection<'a> {
            name: &'a str,
            files: Vec<FileEntry>,
        }
        for name in SectionName::NAMES {
            let bytes = serde_json::to_vec(&OldSection {
                name,
                files: Vec::new(),
            })
            .unwrap();
            let s: Section = serde_json::from_slice(&bytes).unwrap();
            assert_eq!(s.name.name(), *name);
            assert_eq!(serde_json::to_vec(&s).unwrap(), bytes);
        }
        let m = manifest_with(&[("control/a", 3, b"abc")]);
        let text = String::from_utf8(serde_json::to_vec(&m).unwrap()).unwrap();
        assert!(text.contains(r#""name":"control""#), "{text}");
        let back: Manifest = serde_json::from_str(&text).unwrap();
        assert_eq!(serde_json::to_vec(&back).unwrap(), text.as_bytes());
        for bad in ["secrets", "Control", ""] {
            let other = text.replace(r#""name":"control""#, &format!(r#""name":"{bad}""#));
            let e = serde_json::from_str::<Manifest>(&other).unwrap_err();
            assert!(e.to_string().contains("backup section"), "{bad}: {e}");
        }
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
                how: How::None,
                kdf: None,
                check: String::new(),
                id: String::new(),
                mac: String::new(),
            },
            link: None,
            sections: vec![Section {
                name: SectionName::Control,
                info: Default::default(),
                files: files
                    .iter()
                    .map(|(p, size, data)| FileEntry {
                        path: (*p).to_owned(),
                        size: *size,
                        sha256: wyrm_core::hex::sha256_hex(data),
                        sealed: false,
                        exec: false,
                    })
                    .collect(),
            }],
        }
    }

    fn open(m: &Manifest, entries: &[(&str, &[u8])]) -> Result<Reader<Cursor<Vec<u8>>>, ReadError> {
        let zip = zip_of(&serde_json::to_vec(m).unwrap(), entries);
        Reader::new(Cursor::new(zip), 1 << 20)
    }

    #[test]
    fn the_reader_refuses_what_the_manifest_does_not_list() {
        let good = manifest_with(&[("control/a", 3, b"abc")]);
        let mut r = open(&good, &[("control/a", b"abc")]).unwrap();
        r.verify(|_, _| {}).unwrap();
        // an entry more, an entry less, another name
        assert!(matches!(
            open(&good, &[("control/a", b"abc"), ("control/b", b"x")]),
            Err(ReadError::EntriesAndManifest {
                entries: 2,
                listed: 1
            })
        ));
        assert!(matches!(
            open(&good, &[]),
            Err(ReadError::EntriesAndManifest {
                entries: 0,
                listed: 1
            })
        ));
        assert!(matches!(
            open(&good, &[("control/b", b"abc")]),
            Err(ReadError::UnlistedEntry { name }) if name == "control/b"
        ));
        // another size is seen at open, other content at read
        assert!(matches!(
            open(&good, &[("control/a", b"abcd")]),
            Err(ReadError::EntryNotAsListed { path, size: 3 }) if path == "control/a"
        ));
        let mut r = open(&good, &[("control/a", b"abd")]).unwrap();
        assert!(matches!(
            r.verify(|_, _| {}),
            Err(ReadError::Differs { path }) if path == "control/a"
        ));
        assert!(matches!(
            r.read("control/a"),
            Err(ReadError::Differs { .. })
        ));
        // a manifest that is not first, or is not a manifest
        let zip = zip_of(b"{}", &[]);
        assert!(matches!(
            Reader::new(Cursor::new(zip), 1 << 20),
            Err(ReadError::ManifestJson(_))
        ));
        assert!(matches!(
            Reader::new(Cursor::new(b"not a zip".to_vec()), 1 << 20),
            Err(ReadError::NotZip(_))
        ));
        let mut w = zip::ZipWriter::new(Cursor::new(Vec::new()));
        let opts = zip::write::SimpleFileOptions::default();
        w.start_file("control/a", opts).unwrap();
        w.write_all(b"abc").unwrap();
        w.start_file(MANIFEST, opts).unwrap();
        w.write_all(&serde_json::to_vec(&good).unwrap()).unwrap();
        let zip = w.finish().unwrap().into_inner();
        assert!(matches!(
            Reader::new(Cursor::new(zip), 1 << 20),
            Err(ReadError::ManifestNotFirst)
        ));
        // a manifest the reader refuses is told from a file that is no backup
        let mut bad = good.clone();
        bad.wyrm_backup = 2;
        assert!(matches!(
            open(&bad, &[("control/a", b"abc")]),
            Err(ReadError::Manifest(ManifestError::Version { found: 2 }))
        ));
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
        assert!(
            matches!(e, ReadError::Ratio { size, .. } if size == 96 << 20),
            "{e}"
        );
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
            m.sealed.how = How::Broker;
            m.sections = vec![Section {
                name: SectionName::from_name(name).unwrap(),
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
        assert!(matches!(
            m.caps(),
            Err(ManifestError::PartTooLarge { part: Part::Package, name, .. }) if name == "p"
        ));
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
        assert!(matches!(
            m.caps(),
            Err(ManifestError::ArtifactTooLarge { path, .. }) if path == "dataflows/artifacts/ab/cd"
        ));
        let m = with(
            "links",
            vec![
                entry("links/l1/files/a", MAX_LINK_DATA),
                entry("links/l1/files/b", MAX_LINK_DATA / 512),
            ],
        );
        assert!(matches!(
            m.caps(),
            Err(ManifestError::PartTooLarge { part: Part::LinkData, name, .. }) if name == "l1"
        ));
        let m = with("links", vec![entry("links/l1/files/a", MAX_LINK_DATA)]);
        m.caps().unwrap();
        let mut m = with("package", vec![entry("package/files/bin", MAX_PACKAGE * 2)]);
        m.kind = Kind::Link;
        assert!(matches!(
            m.caps(),
            Err(ManifestError::PartTooLarge { part: Part::Package, name, .. }) if name.is_empty()
        ));
        // a link's data over its bound is named before a package over its own,
        // as it was when the parts were sorted by their names
        let mut m = with(
            "packages",
            vec![
                entry("packages/p/files/a", half),
                entry("packages/p/files/b", half),
            ],
        );
        m.sections.push(Section {
            name: SectionName::Links,
            info: Default::default(),
            files: vec![
                entry("links/l1/files/a", MAX_LINK_DATA),
                entry("links/l1/files/b", MAX_LINK_DATA / 512),
            ],
        });
        assert!(matches!(
            m.caps(),
            Err(ManifestError::PartTooLarge {
                part: Part::LinkData,
                ..
            })
        ));
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
        use ManifestError as E;
        assert!(matches!(
            with(&|m| m.wyrm_backup = 2),
            Err(E::Version { found: 2 })
        ));
        assert!(matches!(with(&|m| m.site = "a/b".into()), Err(E::Site(_))));
        // a section of the other kind of backup
        assert!(matches!(
            with(&|m| m.sections[0].name = SectionName::Settings),
            Err(E::SectionOfOtherKind {
                section: SectionName::Settings,
                kind: Kind::Broker
            })
        ));
        // a file outside the folder of its section
        assert!(matches!(
            with(&|m| m.sections[0].files[0].path = "keys/a".into()),
            Err(E::OutsideSection { path, section: SectionName::Control }) if path == "keys/a"
        ));
        assert!(matches!(
            with(&|m| m.sections[0].files[0].path = "control".into()),
            Err(E::OutsideSection { .. })
        ));
        assert!(matches!(
            with(&|m| m.sections[0].files[0].path = "control/../a".into()),
            Err(E::Path(PathError {
                fault: PathFault::Segment,
                ..
            }))
        ));
        assert!(matches!(
            with(&|m| m.sections[0].files[0].sha256 = "xyz".into()),
            Err(E::Digest { .. })
        ));
        assert!(matches!(
            with(&|m| m.sections[0].files[0].sealed = true),
            Err(E::SealedWithoutSealing { .. })
        ));
        assert!(matches!(
            with(&|m| {
                let f = m.sections[0].files[0].clone();
                m.sections[0].files.push(f)
            }),
            Err(E::PathTwice { path }) if path == "control/a"
        ));
        assert!(matches!(
            with(&|m| {
                let s = m.sections[0].clone();
                m.sections.push(s)
            }),
            Err(E::SectionTwice(SectionName::Control))
        ));
        assert!(
            matches!(with(&|m| m.kind = Kind::Link), Err(E::LinkAndKind)),
            "a link backup names its link"
        );
        assert!(matches!(
            with(&|m| m.sealed.how = How::Passphrase),
            Err(E::KdfAndHow)
        ));
        // a link backup has link sections
        let mut link = ok.clone();
        link.kind = Kind::Link;
        link.link = Some(LinkInfo {
            id: "l1".into(),
            driver: "mock".into(),
            mode: crate::registry::Mode::Embedded,
            package: String::new(),
            version: String::new(),
        });
        assert!(matches!(
            link.check(),
            Err(E::SectionOfOtherKind {
                section: SectionName::Control,
                kind: Kind::Link
            })
        ));
        link.sections[0].name = SectionName::Settings;
        link.sections[0].files[0].path = "settings/link.cbor".into();
        link.check().unwrap();
    }

    /// What was staged is checked as a reader checks it: the writer's error
    /// carries the manifest's, and no file is left.
    #[test]
    fn the_writer_refuses_a_manifest_no_reader_takes() {
        let d = dir("badstage");
        std::fs::write(d.join("a"), b"abc").unwrap();
        let (sealed, _) = Sealing::None.start().unwrap();
        let staged = |path: &str, source: &str| {
            vec![StagedSection {
                name: SectionName::Control,
                info: Default::default(),
                files: vec![Staged {
                    path: path.into(),
                    source: d.join(source),
                    sealed: false,
                    exec: false,
                }],
            }]
        };
        let out = d.join("x.wyrm-backup");
        assert!(matches!(
            write(
                &out,
                head(sealed.clone()),
                staged("keys/a", "a"),
                None,
                |_, _| {}
            ),
            Err(WriteError::Manifest(ManifestError::OutsideSection { .. }))
        ));
        assert!(matches!(
            write(&out, head(sealed), staged("control/a", "none"), None, |_, _| {}),
            Err(WriteError::Io { path, source })
                if path == d.join("none") && source.kind() == std::io::ErrorKind::NotFound
        ));
        assert!(!out.exists() && !d.join("x.wyrm-backup.part").exists());
    }

    /// Audit T7: the errors of this module were text. Each variant says, byte
    /// for byte, what the text said: these lines reach an action's refusal, a
    /// `sys` value, a CLI line and the audit journal.
    #[test]
    fn every_error_says_what_its_text_said() {
        fn said(e: &dyn std::error::Error, want: &str) {
            assert_eq!(e.to_string(), want);
        }
        let io = || std::io::Error::other("no");
        let json = || <serde_json::Error as serde::de::Error>::custom("no");
        let zip = || zip::result::ZipError::FileNotFound;
        let hex = hex::FromHexError::OddLength;
        let p = || "keys/a".to_owned();

        use PathFault as F;
        let path = |fault| PathError {
            path: "a/../b".into(),
            fault,
        };
        said(&path(F::Length), r#"path "a/../b": empty or too long"#);
        said(
            &path(F::ManifestName),
            r#"path "a/../b": the manifest's name"#,
        );
        said(
            &path(F::Segment),
            r#"path "a/../b": empty, `.` or `..` segment"#,
        );
        said(
            &path(F::Character),
            r#"path "a/../b": `\`, `:` or a control character"#,
        );
        said(&path(F::Depth), r#"path "a/../b": too deep"#);

        use ManifestError as M;
        said(
            &M::Version { found: 2 },
            "wyrm_backup 2: this broker reads version 1",
        );
        said(
            &M::Site(wyrm_core::keyspace::KeyError::Empty),
            "manifest: site: empty segment",
        );
        said(
            &M::KdfAndHow,
            "manifest: sealed.kdf goes with how: passphrase",
        );
        said(
            &M::NotAuthenticated,
            "manifest: a sealed backup carries sealed.id, sealed.check and sealed.mac; \
             this one is not authenticated",
        );
        said(
            &M::AuthenticationWithoutSealing,
            "manifest: sealed.id and sealed.mac go with a sealed backup",
        );
        said(&M::LinkAndKind, "manifest: link goes with kind: link");
        said(
            &M::SectionOfOtherKind {
                section: SectionName::Settings,
                kind: Kind::Broker,
            },
            "manifest: no section Settings in a broker backup",
        );
        said(
            &M::SectionTwice(SectionName::Keys),
            "manifest: section keys twice",
        );
        said(&M::TooManyFiles, "manifest: more than 100000 files");
        said(&M::Path(path(F::Depth)), r#"path "a/../b": too deep"#);
        said(
            &M::OutsideSection {
                path: p(),
                section: SectionName::Control,
            },
            "manifest: keys/a is not under section control",
        );
        said(&M::Digest { path: p() }, "manifest: keys/a: sha256");
        said(
            &M::FileTooLarge { path: p(), size: 7 },
            "manifest: keys/a: 7 bytes (at most 1099511627776 a file)",
        );
        said(
            &M::SizesOverflow,
            "manifest: the sizes of its files do not add up",
        );
        said(
            &M::SecretNotSealed { path: p() },
            "manifest: keys/a holds secrets and is not sealed",
        );
        said(
            &M::SealedWithoutSealing { path: p() },
            "manifest: keys/a is sealed, the backup says none",
        );
        said(&M::PathTwice { path: p() }, "manifest: keys/a twice");
        said(
            &M::ArtifactTooLarge { path: p(), size: 7 },
            "keys/a: 7 bytes (a flow artifact has at most 67108864)",
        );
        said(
            &M::PartTooLarge {
                part: Part::Package,
                name: "p".into(),
                size: 7,
            },
            "the package p of the backup holds 7 bytes (at most 268435456)",
        );
        said(
            &M::PartTooLarge {
                part: Part::LinkData,
                name: "l1".into(),
                size: 7,
            },
            "the link data l1 of the backup holds 7 bytes (at most 8589934592)",
        );

        use KeyError as K;
        said(&K::PassphraseTooShort, "passphrase: at least 12 characters");
        said(
            &K::KdfBounds,
            "sealed.kdf: not Argon2id within 128 MiB, 4 passes, 4 lanes",
        );
        said(&K::SaltHex(hex), "sealed.kdf.salt: hex");
        said(
            &K::KdfParams(argon2::Error::MemoryTooLittle),
            "sealed.kdf: memory cost is too small",
        );
        said(
            &K::Derivation(argon2::Error::OutputTooShort),
            "key derivation: output is too short",
        );
        said(&K::IdHex(hex), "manifest: sealed.id: hex");
        said(&K::IdLength, "manifest: sealed.id: 16 bytes");
        said(
            &K::PassphraseRequired,
            "passphrase: required, the backup is sealed with one",
        );
        said(
            &K::BrokerKeyRequired,
            "the backup is sealed for the broker that made it",
        );
        said(&K::NotSealed, "the backup has no sealed files");
        said(&K::WrongPassphrase, "wrong passphrase");
        said(
            &K::AnotherBroker,
            "the backup is sealed for another broker (its secrets.key differs)",
        );
        said(&K::MacHex(hex), "manifest: sealed.mac: hex");
        said(
            &K::ManifestChanged,
            "the manifest was changed after the backup was made (its MAC does not match)",
        );
        said(&K::Encode(json()), "no");
        // `K::NoRandomness` shows its cause alone, as `e.to_string()` did; the
        // cause is made only by `wyrm_core::rand`
        said(
            &K::Seal(wyrm_link_sdk::seal::SealError),
            "seal: no randomness for the nonce, or the cipher refused",
        );

        use SealedError as S;
        said(
            &S::Io {
                path: p(),
                source: io(),
            },
            "keys/a: no",
        );
        said(&S::NotSealed { path: p() }, "keys/a: not a sealed file");
        said(
            &S::CutShort {
                path: p(),
                source: io(),
            },
            "keys/a: sealed file cut short",
        );
        said(
            &S::PartTooLarge { path: p(), len: 7 },
            "keys/a: sealed part of 7 bytes",
        );
        said(
            &S::DoesNotOpen { path: p() },
            "keys/a: does not open (wrong key, or changed)",
        );
        said(
            &S::OutOfOrder { path: p() },
            "keys/a: sealed parts out of order",
        );
        said(
            &S::Trailing { path: p() },
            "keys/a: bytes after the last sealed part",
        );

        use WriteError as W;
        said(
            &W::Io {
                path: "/b/x".into(),
                source: io(),
            },
            "/b/x: no",
        );
        said(&W::KeyOfAnotherBackup, "the key is of another backup");
        said(
            &W::KeyAndSealing,
            "a sealed backup is written with its key, an unsealed one without",
        );
        said(
            &W::Manifest(M::LinkAndKind),
            "manifest: link goes with kind: link",
        );
        said(&W::ManifestTooLarge, "manifest: too large");
        said(&W::Encode(json()), "no");
        said(&W::Zip(zip()), "specified file not found in archive");
        said(&W::Flush(io()), "no");
        said(
            &W::SourceChanged {
                path: "/b/x".into(),
            },
            "/b/x: changed while it was read",
        );

        use ReadError as R;
        said(
            &R::File {
                path: "/b/x".into(),
                source: io(),
            },
            "/b/x: no",
        );
        said(&R::Seek(io()), "not a backup: no");
        said(
            &R::NotZip(zip()),
            "not a backup: specified file not found in archive",
        );
        said(
            &R::EntryCount { found: 0 },
            "not a backup: 0 entries (1 to 100000)",
        );
        said(
            &R::ManifestNotFirst,
            "not a backup: the first entry is not manifest.json",
        );
        said(&R::ManifestTooLarge, "manifest: too large");
        said(&R::ManifestRead(io()), "manifest: no");
        said(&R::ManifestJson(json()), "manifest: no");
        said(
            &R::Manifest(M::LinkAndKind),
            "manifest: link goes with kind: link",
        );
        said(
            &R::OverLimit { size: 9, max: 7 },
            "the backup holds 9 bytes; at most 7 are taken here",
        );
        said(
            &R::Ratio { len: 3, size: 9 },
            "the backup is a file of 3 bytes that says it holds 9: more than \
             200 times its size, it is not opened",
        );
        said(
            &R::EntriesAndManifest {
                entries: 2,
                listed: 1,
            },
            "the backup has 2 entries, its manifest lists 1",
        );
        said(&R::Zip(zip()), "zip: specified file not found in archive");
        said(
            &R::UnlistedEntry {
                name: "a\"b".into(),
            },
            r#"entry "a\"b" is not in the manifest"#,
        );
        said(
            &R::EntryNotAsListed { path: p(), size: 7 },
            "entry keys/a: not the file of 7 bytes the manifest lists",
        );
        said(&R::NotInBackup { path: p() }, "keys/a: not in the backup");
        said(
            &R::Entry {
                path: p(),
                source: zip(),
            },
            "keys/a: specified file not found in archive",
        );
        said(
            &R::Stored {
                path: p(),
                source: io(),
            },
            "keys/a: no",
        );
        said(
            &R::Output {
                path: p(),
                source: io(),
            },
            "keys/a: no",
        );
        said(
            &R::Longer { path: p() },
            "keys/a: longer than the manifest lists",
        );
        said(
            &R::Differs { path: p() },
            "keys/a: size or SHA-256 differs from the manifest",
        );
        said(
            &R::TooLargeInMemory { path: p(), size: 7 },
            "keys/a: 7 bytes, too large to read in memory",
        );
        said(&R::NoKey { path: p() }, "keys/a: sealed, no key");
        said(
            &R::Sealed(S::NotSealed { path: p() }),
            "keys/a: not a sealed file",
        );
        said(&R::Flush(io()), "no");
    }

    /// An error of a key or of a sealed file shows nothing of what was tried:
    /// not the passphrase, not the key, not a byte of the file.
    #[test]
    fn errors_show_no_secret_input() {
        let (m, key) = signed(Sealing::Passphrase(PASS));
        let wrong = b"zebra-zebra-zebra";
        let e = m.key(Some(wrong), None).err().unwrap();
        let shown = format!("{e} {e:?}");
        assert!(!shown.contains("zebra"), "{shown}");
        let e = m.key(Some(b"zebra"), None).err().unwrap();
        let shown = format!("{e} {e:?}");
        assert!(!shown.contains("zebra"), "{shown}");
        let (b, _) = signed(Sealing::Broker(b"zebra-secrets-key"));
        let e = b.key(None, Some(b"zebra-other-key")).err().unwrap();
        let shown = format!("{e} {e:?}");
        assert!(!shown.contains("zebra"), "{shown}");
        // a sealed file that does not open: its bytes are not in the error
        let mut sealed = seal_bytes(&key, "data/a", b"zebra").unwrap();
        let last = sealed.len() - 1;
        sealed[last] ^= 1;
        let e = open_bytes(&key, "data/a", &sealed).unwrap_err();
        assert_eq!(format!("{e:?}"), r#"DoesNotOpen { path: "data/a" }"#);
    }
}
