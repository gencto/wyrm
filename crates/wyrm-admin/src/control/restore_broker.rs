//! Restore of a broker backup (ADR 0048 §3.6), from an upload of
//! `sys/backups/~act/restore_begin` / `restore_part`:
//!
//! * `restore_check {upload, passphrase?}` reads the whole file and says
//!   what it is and what stands in the way: site, keys, versions, links.
//! * `restore_apply {upload, sections, mode, passphrase?, accept?,
//!   replace_keys?}`:
//!   - `mode: add` works live: links that do not exist yet (as
//!     `install_backup` does) and storage nodes that do not exist yet.
//!     Nothing is replaced, nothing restarts.
//!   - `mode: replace` makes a backup of what it replaces (`pre-restore`),
//!     stages the chosen sections in `data_dir/restore.pending` and stops
//!     the broker. [`apply_pending`] puts them in place at the next start,
//!     before any store opens, and removes the folder.
//!
//! A backup of another site name is never restored with `replace`, and a
//! caller from an upstream never runs `replace`. Every restore of the
//! `keys` section needs `backups.export_secrets`, a caller of this site and
//! the passphrase; keys that differ from this broker's in any file also
//! need `replace_keys: true` ([`replace_gates`]). A file of the backup goes
//! only where its section defines a place ([`place_of`]).

use super::backups::{
    broker_made_secret, key_files, make_private_dir, wal_stores, BackupError, BackupRequest,
    FileError, NowError, SealWith, StartError,
};
use super::restore::{LinkLayout, RestoreError, MAX_UPLOAD};
use super::*;
use crate::backup::{self as format, Kind, Manifest, MasterKey, SectionName};
use serde::{Deserialize, Serialize};
use zeroize::Zeroizing;

/// `data_dir/restore.pending`: a staged restore, applied at the next start.
pub const PENDING: &str = "restore.pending";
const PENDING_TMP: &str = "restore.pending.tmp";
const PLAN: &str = "plan.json";
const STORAGE_TREE: &str = "storage.tree.cbor";
const LINK_SECRETS: &str = "link-secrets.cbor";
/// `data_dir/restore.failed`: a restore that was not applied, with its
/// plan and the reason (`error.txt`); the state before it is in place.
pub const FAILED: &str = "restore.failed";
/// A restore that was applied and committed, being removed.
const DONE: &str = "restore.done";
/// What was there before the first change, written before it.
const BEFORE: &str = "before.json";
/// What the restore replaced, kept until it is committed: `old/<path>`.
const OLD: &str = "old";
/// The restore is being undone (with the reason): a start goes on with it.
const UNDO: &str = "undo";
const ERROR: &str = "error.txt";
/// The failure was audited.
const REPORTED: &str = "reported";
const SECRETS_BIN: &str = "secrets.bin";

/// The sections `mode: replace` puts in place (`config` is never restored).
const REPLACEABLE: [SectionName; 7] = [
    SectionName::Control,
    SectionName::Keys,
    SectionName::Dataflows,
    SectionName::Storage,
    SectionName::History,
    SectionName::Links,
    SectionName::Packages,
];
/// The sections `mode: add` takes.
const ADDABLE: [SectionName; 3] = [
    SectionName::Links,
    SectionName::Storage,
    SectionName::Dataflows,
];

wyrm_core::name_enum! {
    /// How `restore_apply` restores (module doc): `add` live, what does not exist yet;
    /// `replace` staged for the next start, the sections in place of this broker's.
    pub enum RestoreMode as "restore mode" {
        Add => "add",
        Replace => "replace",
    }
}

impl RestoreMode {
    /// The sections this mode restores.
    fn sections(self) -> &'static [SectionName] {
        match self {
            RestoreMode::Add => &ADDABLE,
            RestoreMode::Replace => &REPLACEABLE,
        }
    }
}

/// What [`apply_pending`] does, written by `restore_apply`.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct Plan {
    pub by: String,
    /// `<site> <created>` of the backup.
    pub backup: String,
    pub sections: Vec<SectionName>,
    /// Paths under `data_dir` removed first (stale certificates of
    /// replaced keys).
    #[serde(default)]
    pub remove: Vec<String>,
    /// Remove every `links/<id>/*.pem` and `*.key`: issued by the CA that
    /// is replaced.
    #[serde(default)]
    pub strip_link_certs: bool,
    /// Directories under `data_dir` replaced by `data/<dir>` of the folder.
    #[serde(default)]
    pub dirs: Vec<String>,
    /// Files under `data_dir` replaced by `data/<file>` of the folder.
    #[serde(default)]
    pub files: Vec<String>,
    /// `(package, entry path under data_dir)`: published to the component
    /// store again.
    #[serde(default)]
    pub components: Vec<(String, String)>,
}

/// What a start applied.
#[derive(Debug, Clone, PartialEq)]
pub struct Applied {
    pub by: String,
    pub backup: String,
    pub sections: Vec<SectionName>,
}

/// A file of a broker backup that no section defines ([`place_of`]): the
/// whole backup is refused.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
#[error(
    "the backup lists {path:?}, a file no section defines: nothing of this backup is \
     restored"
)]
pub struct NoPlace {
    pub path: String,
}

/// A name that is no plain file name, or a path without one
/// ([`plain_segment`], [`plain_rel`]).
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
enum NotPlain {
    #[error("{0:?} is no file name")]
    Segment(String),
    #[error("a path without a file name")]
    NoName,
}

/// A gate of `mode: replace` that is closed ([`replace_gates`]), in the order
/// they are judged. `KeysDiffer` names key files, never their content.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum GateError {
    /// The caller's authority comes from an upstream.
    #[error(
        "mode replace is not run through an upstream: it replaces this site's state. Do it \
         on the broker's own gateway (mode add works from above)"
    )]
    Remote,
    /// `backups.export_secrets` is false and the `keys` section was chosen.
    #[error(
        "restoring the keys section needs backups.export_secrets: true in wyrmd.json5 (set \
         on the host)"
    )]
    ExportOff,
    /// The `keys` section without the passphrase.
    #[error("passphrase: required to restore the keys section")]
    NoPassphrase,
    /// Key files that are not byte for byte this broker's, without
    /// `replace_keys`.
    #[error(
        "the keys of the backup differ from this broker's ({}): they are put in place only \
         with replace_keys: true{}",
        .differ.join(", "),
        if .differ.iter().any(|f| f == CA_FILE) {
            " (another CA: links, operators and peer brokers enrol again)"
        } else {
            ""
        }
    )]
    KeysDiffer { differ: Vec<String> },
}

/// A `control` section that no broker makes ([`Control::stage_control`]: for
/// each store one WAL segment with every record, and the number of the last
/// one in the section's `info`). Restored, the store would open without the
/// records the backup claims: an emptied control plane (issue #198).
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum ControlError {
    /// A file a store does not read its records from.
    #[error(
        "{path} is no segment of a WAL (wal.<first lsn>.wyw): a store is restored from its \
         segments alone. Nothing of this backup is restored"
    )]
    NotSegment { path: String },
    /// The section without the registry.
    #[error(
        "the control section of the backup holds no segment of the registry (control/state). \
         Nothing of this backup is restored"
    )]
    NoRegistry,
    /// The manifest does not say where the store ends.
    #[error(
        "the backup does not say how many records its {store} store holds. Nothing of this \
         backup is restored"
    )]
    NoHead { store: &'static str },
    /// The store opens with other records than the backup says it holds.
    #[error(
        "the {store} store of the backup opens with {found} records, the backup says it holds \
         {said}. Nothing of this backup is restored"
    )]
    Head {
        store: &'static str,
        said: u64,
        found: u64,
    },
}

/// The head of the store `store` as the `control` section of `manifest` says
/// it, checked against the head `found` that the store opens with. A store
/// without records is a real one (a broker backed up before anything was
/// installed): it says 0 and opens with 0.
fn head_as_said(manifest: &Manifest, store: &'static str, found: u64) -> Result<(), ControlError> {
    let said = manifest
        .section(SectionName::Control)
        .and_then(|s| s.info.get(store))
        .and_then(|said| said.as_u64())
        .ok_or(ControlError::NoHead { store })?;
    if said != found {
        return Err(ControlError::Head { store, said, found });
    }
    Ok(())
}

/// What stands in the way of every `replace` of a backup, as `restore_check`
/// lists it (`problems`) and `restore_apply` refuses it.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum Problem {
    #[error(
        "the backup is of site {backup}, this broker is {here}: a site is restored under its own \
         name (set `site` in wyrmd.json5)"
    )]
    OtherSite { backup: String, here: String },
    #[error(
        "the {store} store of the backup has schema {backup}, this broker reads up to {here}: \
         update the broker first"
    )]
    NewerSchema {
        store: String,
        backup: u32,
        here: u32,
    },
}

/// Why the plan of a staged restore is not taken ([`read_plan`]).
#[derive(Debug, thiserror::Error)]
pub enum PlanError {
    #[error(transparent)]
    File(#[from] FileError),
    /// Not a plan, or one with a section this build does not know.
    #[error("plan.json: {0}")]
    Json(#[source] serde_json::Error),
    /// A path that would leave the `data_dir`.
    #[error("restore.pending: {0}")]
    Path(#[source] format::PathError),
    /// A package name of `components` that is no name.
    #[error("{0}")]
    Component(#[source] wyrm_core::keyspace::KeyError),
}

/// Why the link secrets a restore staged do not read ([`parse_link_secrets`]).
/// No variant holds a secret: a link's id and a secret's name only.
#[derive(Debug, thiserror::Error)]
pub enum LinkSecretsError {
    #[error("link secrets: {0}")]
    Decode(#[source] wyrm_core::codec::CodecError),
    #[error("link secrets: not a map")]
    NotMap,
    /// A link id that is none (`registry::validate_link_id`, as it says it).
    #[error("{0}")]
    LinkId(#[source] crate::registry::LinkIdError),
    #[error("link secrets: {link}: not a map")]
    LinkNotMap { link: String },
    #[error("link secrets: {link}/{name}: not bytes")]
    NotBytes { link: String, name: String },
}

/// Why the storage of a backup was not built from its tree ([`build_storage`]).
#[derive(Debug, thiserror::Error)]
pub enum StorageError {
    #[error(transparent)]
    File(#[from] FileError),
    /// The tree is no CBOR.
    #[error("storage tree: unreadable")]
    TreeDecode(#[source] wyrm_core::codec::CodecError),
    /// The tree is CBOR and no list of storage nodes.
    #[error("storage tree: unreadable")]
    TreeShape,
    /// The new store did not open or did not take the nodes.
    #[error("{0}")]
    Store(#[source] wyrm_storage::Error),
}

/// Why a staged restore was not put in place and the state before it could
/// not be put back either ([`apply_pending`], [`undo_pending`]); also every
/// failure of the plan itself, whose text is the `error.txt` of
/// `restore.failed` when the state before it is back.
#[derive(Debug, thiserror::Error)]
pub enum PendingError {
    #[error(transparent)]
    Plan(#[from] PlanError),
    /// The plan does not read and the restore had begun: nothing says what
    /// to put back.
    #[error("{0}; the restore had begun: see restore.pending")]
    Begun(#[source] PlanError),
    #[error(transparent)]
    File(#[from] FileError),
    /// `before.json` (what was there before the first change) does not read.
    #[error("before.json: {0}")]
    Before(#[source] serde_json::Error),
    #[error("{0}")]
    BeforeEncode(#[source] serde_json::Error),
    #[error(transparent)]
    Storage(#[from] StorageError),
    #[error(transparent)]
    LinkSecrets(#[from] LinkSecretsError),
    /// The secret store in place did not open or did not take a link's secret.
    #[error("{0}")]
    SecretStore(#[source] secret::Error),
}

/// Why `restore_check` or `restore_apply` is refused. To a caller:
/// [`BrokerRestoreError::status`]. No variant holds a passphrase, a key, a
/// secret or a byte of a file of the backup.
#[derive(Debug, thiserror::Error)]
pub enum BrokerRestoreError {
    /// The file does not read as a backup, its key is not given, the disk has
    /// no room: what a link backup is refused for too.
    #[error(transparent)]
    Restore(#[from] RestoreError),
    #[error("a link backup: install it with Add a link, From backup")]
    LinkBackup,
    #[error(transparent)]
    Place(#[from] NoPlace),
    /// A `keys` section without the CA certificate.
    #[error("the keys section holds no pki/ca.pem")]
    NoCa,
    /// A key file of this broker (`state.key`, the key of a WAL store) does
    /// not load.
    #[error("{0}")]
    KeyLoad(#[source] secret::Error),
    /// A section the mode does not restore.
    #[error(
        "sections: {section} is not restored with mode {mode} (of {})",
        format::section_names(.mode.sections())
    )]
    Section {
        section: SectionName,
        mode: RestoreMode,
    },
    #[error("sections: none chosen")]
    NoSections,
    #[error(transparent)]
    Problem(#[from] Problem),
    /// A chosen section that the backup does not have.
    #[error("sections: the backup has no section {0}")]
    MissingSection(SectionName),
    /// `control` with `state_anchor_dir` set.
    #[error(
        "state_anchor_dir is set: restore the control plane offline, then run \
         `wyrmd init-anchors` (docs/operations.md §3)"
    )]
    Anchored,
    #[error(transparent)]
    Gate(#[from] GateError),
    /// A `control` section that is not what a broker makes.
    #[error(transparent)]
    Control(#[from] ControlError),
    /// `control` under other keys than this broker's, without new keys.
    #[error(
        "the control plane of the backup is under other keys than this broker's: \
         restore it together with the keys section (replace_keys: true)"
    )]
    ControlKeys,
    /// Another replace is staged, or an operation holds a package or a link
    /// (`Control::replacing`).
    #[error("{}", .0.message)]
    Busy(LinkError),
    /// No backup of what the restore replaces.
    #[error(transparent)]
    PreBackup(#[from] NowError),
    /// The task that read or staged the backup ended without an answer.
    #[error("{0}")]
    Task(#[source] tokio::task::JoinError),
    /// A WAL store of the backup does not open with the key that will be in
    /// place.
    #[error(
        "{store}: the store of the backup does not open with the keys that will \
         be in place ({source}): restore it together with the keys section"
    )]
    WalKeys {
        store: &'static str,
        #[source]
        source: StateError,
    },
    #[error("the history of the backup does not open: {0}")]
    History(#[source] wyrm_history::store::Error),
    #[error(transparent)]
    Storage(#[from] StorageError),
    #[error(transparent)]
    LinkSecrets(#[from] LinkSecretsError),
    /// The link secrets were not encoded for the start that applies them.
    #[error("{0}")]
    SecretsEncode(#[source] wyrm_core::codec::CodecError),
    /// A package of the backup does not pass the validator of an install
    /// (`packages::unpack`, as it says it).
    #[error("package {name} of the backup: {why}")]
    PackageInvalid { name: String, why: String },
    /// The folder `packages/<dir>` holds a package of another name.
    #[error("packages/{dir} holds package {holds}")]
    PackageName { dir: String, holds: String },
    /// A package version that is no path segment.
    #[error("{0}")]
    PackageVersion(#[source] wyrm_core::keyspace::KeyError),
    /// What the packages of the backup ask for was not accepted.
    #[error(
        "the packages of the backup ask for: {}. Nothing is restored: read them, then \
         restore again with Accept Requested Rights",
        .asks.join("; ")
    )]
    Asks { asks: Vec<String> },
    /// The secret store of the backup does not open with the key that comes
    /// with it.
    #[error("the secret store of the backup: {0}")]
    SecretStore(#[source] secret::Error),
    #[error("{0}")]
    PlanEncode(#[source] serde_json::Error),
    /// The plan just written does not read as the start will read it.
    #[error(transparent)]
    Plan(#[from] PlanError),
    /// The staging failed (`error`) and the half-staged folder `path`, which
    /// may hold opened secrets, could not be removed.
    #[error("{error}; {} stays: {source}", .path.display())]
    Stays {
        error: Box<BrokerRestoreError>,
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    /// `mode: add` of `storage` on a broker without its storage.
    #[error("storage: not open")]
    StorageClosed,
    #[error("the backup has no storage tree")]
    NoStorageTree,
    /// The storage did not take the new nodes.
    #[error("{0}")]
    StorageApply(#[source] wyrm_storage::Error),
}

impl BrokerRestoreError {
    /// The status of the refusal. `busy` is a reason to try again: another
    /// restore, backup, update or install runs. A gate closed by the caller's
    /// rights is `permission_denied` (owner decision 2026-11-24, issue #198
    /// item 3): the caller comes from an upstream, or the host keeps secrets
    /// on the site, as `sys/backups ▸ create` and `download_part` answer the
    /// same rule.
    ///
    /// A restore that has no `pre-restore` backup is refused, never run
    /// without it (owner decision 2026-11-27), and the refusal says why:
    /// - the disk of `data_dir` has not the room the backup needs
    ///   (`StartError::DiskFull`, the check before the job) or filled up
    ///   while it was written (an I/O error of kind `StorageFull` or
    ///   `QuotaExceeded`): `resource_exhausted`, as `sys/backups ▸ create`
    ///   answers the first;
    /// - any other I/O error of the job (a file or a directory of the
    ///   broker, the zip, a store read: [`BackupError::io_cause`] finds it in
    ///   the chain of the typed error): `internal_error`;
    /// - the job's record is gone when it ends (`NowError::Gone`): the
    ///   broker lost it, not the caller: `internal_error`;
    /// - the request of the backup is refused, or the job fails without an
    ///   I/O error (`storage: not open`, a key file that does not load, a
    ///   cause held as text only): `invalid_parameter`, as before.
    ///
    /// Everything else is `invalid_parameter`, as the handler answered before
    /// the refusals had types (it told `busy` by the words of the message).
    pub fn status(&self) -> Status {
        match self {
            BrokerRestoreError::Gate(GateError::Remote | GateError::ExportOff) => {
                Status::PermissionDenied
            }
            BrokerRestoreError::Busy(_) => Status::Busy,
            BrokerRestoreError::PreBackup(NowError::Refused(
                StartError::Running | StartError::LinkBusy(_),
            )) => Status::Busy,
            BrokerRestoreError::PreBackup(NowError::Refused(StartError::DiskFull { .. })) => {
                Status::ResourceExhausted
            }
            BrokerRestoreError::PreBackup(NowError::Failed(e)) => pre_backup_failed(e),
            BrokerRestoreError::PreBackup(NowError::Gone) => Status::InternalError,
            BrokerRestoreError::Stays { error, .. } => error.status(),
            BrokerRestoreError::PreBackup(NowError::Refused(StartError::Request(_)))
            | BrokerRestoreError::Restore(_)
            | BrokerRestoreError::LinkBackup
            | BrokerRestoreError::Place(_)
            | BrokerRestoreError::NoCa
            | BrokerRestoreError::KeyLoad(_)
            | BrokerRestoreError::Section { .. }
            | BrokerRestoreError::NoSections
            | BrokerRestoreError::Problem(_)
            | BrokerRestoreError::MissingSection(_)
            | BrokerRestoreError::Anchored
            | BrokerRestoreError::Gate(GateError::NoPassphrase | GateError::KeysDiffer { .. })
            | BrokerRestoreError::Control(_)
            | BrokerRestoreError::ControlKeys
            | BrokerRestoreError::Task(_)
            | BrokerRestoreError::WalKeys { .. }
            | BrokerRestoreError::History(_)
            | BrokerRestoreError::Storage(_)
            | BrokerRestoreError::LinkSecrets(_)
            | BrokerRestoreError::SecretsEncode(_)
            | BrokerRestoreError::PackageInvalid { .. }
            | BrokerRestoreError::PackageName { .. }
            | BrokerRestoreError::PackageVersion(_)
            | BrokerRestoreError::Asks { .. }
            | BrokerRestoreError::SecretStore(_)
            | BrokerRestoreError::PlanEncode(_)
            | BrokerRestoreError::Plan(_)
            | BrokerRestoreError::StorageClosed
            | BrokerRestoreError::NoStorageTree
            | BrokerRestoreError::StorageApply(_) => Status::InvalidParameter,
        }
    }
}

/// The status of a `pre-restore` backup that failed while it was written
/// ([`BrokerRestoreError::status`]).
fn pre_backup_failed(e: &BackupError) -> Status {
    use std::io::ErrorKind;
    match e.io_cause().map(std::io::Error::kind) {
        Some(ErrorKind::StorageFull | ErrorKind::QuotaExceeded) => Status::ResourceExhausted,
        Some(_) => Status::InternalError,
        None => Status::InvalidParameter,
    }
}

impl From<BrokerRestoreError> for LinkError {
    fn from(e: BrokerRestoreError) -> Self {
        LinkError::new(e.status(), e.to_string())
    }
}

impl From<format::ReadError> for BrokerRestoreError {
    fn from(e: format::ReadError) -> Self {
        Self::Restore(e.into())
    }
}

impl From<FileError> for BrokerRestoreError {
    fn from(e: FileError) -> Self {
        Self::Restore(e.into())
    }
}

/// A path of a plan: relative, plain segments.
fn plan_path(p: &str) -> Result<(), PlanError> {
    format::check_path(p).map_err(PlanError::Path)
}

/// What one file of a broker backup is, and so where a restore may put it.
/// A restore never joins a path of the archive to a directory: every
/// destination is built here, from segments that were checked, and a path
/// no section defines refuses the whole backup ([`place_of`]).
#[derive(Debug, Clone, PartialEq)]
enum Place {
    /// A key file, `secrets.bin` or a link's token: its path under
    /// `data_dir`, one of a closed list.
    Key(String),
    /// A file of the WAL store `name`, kept in `dir` under `data_dir`.
    Wal {
        name: &'static str,
        dir: &'static str,
        file: String,
    },
    /// Under `flows/artifacts`.
    Artifact(PathBuf),
    StorageTree,
    /// For people; never restored.
    StorageExport,
    HistoryIndex,
    /// `<day>.redb` under `history/days`.
    HistoryDay(String),
    LinkSettings(String),
    LinkSecrets(String),
    /// A file of the link's private data.
    LinkFile(String, PathBuf),
    /// A file of the package, before the install validator.
    PackageFile(String, PathBuf),
    /// Never restored.
    Config,
}

/// One segment of a destination: a plain file name.
fn plain_segment(s: &str) -> Result<&str, NotPlain> {
    let bad = s.is_empty()
        || s == "."
        || s == ".."
        || s.chars()
            .any(|c| matches!(c, '/' | '\\' | ':') || c.is_control());
    if bad {
        return Err(NotPlain::Segment(s.to_owned()));
    }
    Ok(s)
}

/// A relative path built from checked segments (at least one).
fn plain_rel(segs: &[&str]) -> Result<PathBuf, NotPlain> {
    if segs.is_empty() {
        return Err(NotPlain::NoName);
    }
    let mut out = PathBuf::new();
    for s in segs {
        out.push(plain_segment(s)?);
    }
    Ok(out)
}

/// The place of the file `path` of a broker backup: `Err` for a path that
/// no section defines (ADR 0048 §3.6, the allowlist of a restore).
fn place_of(path: &str) -> Result<Place, NoPlace> {
    let refuse = || NoPlace {
        path: path.to_owned(),
    };
    let link = |id: &str| -> Result<String, NoPlace> {
        crate::registry::validate_link_id(id).map_err(|_| refuse())?;
        Ok(id.to_owned())
    };
    let segs: Vec<&str> = path.split('/').collect();
    let place = match segs.as_slice() {
        ["keys", "links", id, "token"] => Place::Key(format!("links/{}/token", link(id)?)),
        ["keys", rest @ ..] => {
            let rel = rest.join("/");
            if rel != "secrets.bin" && !key_files().contains(&rel.as_str()) {
                return Err(refuse());
            }
            Place::Key(rel)
        }
        ["control", store, file] => {
            let (name, dir, _, _) = wal_stores()
                .into_iter()
                .find(|(name, ..)| name == store)
                .ok_or_else(refuse)?;
            Place::Wal {
                name,
                dir,
                file: plain_segment(file).map_err(|_| refuse())?.to_owned(),
            }
        }
        ["dataflows", "artifacts", rest @ ..] => {
            Place::Artifact(plain_rel(rest).map_err(|_| refuse())?)
        }
        ["storage", "tree.cbor"] => Place::StorageTree,
        ["storage", "export.json"] => Place::StorageExport,
        ["history", "index.redb"] => Place::HistoryIndex,
        ["history", "days", day] if day.ends_with(".redb") => {
            Place::HistoryDay(plain_segment(day).map_err(|_| refuse())?.to_owned())
        }
        ["links", id, "link.cbor"] => Place::LinkSettings(link(id)?),
        ["links", id, "secrets"] => Place::LinkSecrets(link(id)?),
        ["links", id, "files", rest @ ..] => {
            Place::LinkFile(link(id)?, plain_rel(rest).map_err(|_| refuse())?)
        }
        ["packages", name, "files", rest @ ..] => {
            wyrm_core::keyspace::validate_segment(name).map_err(|_| refuse())?;
            if name.starts_with('.') {
                return Err(refuse());
            }
            Place::PackageFile((*name).to_owned(), plain_rel(rest).map_err(|_| refuse())?)
        }
        ["config", "wyrmd.json"] => Place::Config,
        _ => return Err(refuse()),
    };
    Ok(place)
}

/// What decides whether `mode: replace` may go on (ADR 0048 §3.6).
struct Gates<'a> {
    /// The caller's authority comes from an upstream site.
    remote: bool,
    /// The `keys` section is among the chosen ones.
    keys: bool,
    /// Key files of the backup that are not byte for byte this broker's.
    differ: &'a [String],
    /// `backups.export_secrets` of the host.
    export_secrets: bool,
    passphrase: bool,
    replace_keys: bool,
}

/// The gates of `mode: replace`. A caller from an upstream never replaces
/// anything of this site. Every restore of `keys` needs the host's
/// `backups.export_secrets` and the passphrase, whatever the keys are; keys
/// that differ from this broker's in any file also need `replace_keys`.
fn replace_gates(g: &Gates) -> Result<(), GateError> {
    if g.remote {
        return Err(GateError::Remote);
    }
    if !g.keys {
        return Ok(());
    }
    if !g.export_secrets {
        return Err(GateError::ExportOff);
    }
    if !g.passphrase {
        return Err(GateError::NoPassphrase);
    }
    if !g.differ.is_empty() && !g.replace_keys {
        return Err(GateError::KeysDiffer {
            differ: g.differ.to_vec(),
        });
    }
    Ok(())
}

/// The CA certificate among the key files: another one is another identity.
const CA_FILE: &str = "pki/ca.pem";

/// What was under `data_dir` before a staged restore changed anything.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
struct Before {
    /// Paths the plan replaces that were there.
    existed: Vec<String>,
    /// Paths the plan removes that were there (set aside, never deleted).
    moved: Vec<String>,
    /// Every path the plan puts something at, in the order it does.
    placed: Vec<String>,
}

/// A restore that was not applied ([`take_failure`]).
#[derive(Debug, Clone, PartialEq)]
pub struct Failure {
    pub by: String,
    pub backup: String,
    pub sections: Vec<SectionName>,
    pub error: String,
}

fn is_there(p: &Path) -> bool {
    std::fs::symlink_metadata(p).is_ok()
}

fn move_to(from: &Path, to: &Path) -> Result<(), FileError> {
    if let Some(d) = to.parent() {
        std::fs::create_dir_all(d).map_err(|e| FileError::new(d, e))?;
    }
    std::fs::rename(from, to).map_err(|e| FileError::new(to, e))
}

fn component_target(name: &str) -> String {
    format!("packages/.wasm/{name}.wasm")
}

/// The plan of the folder, checked: every path relative and plain.
fn read_plan(pending: &Path) -> Result<Plan, PlanError> {
    let text =
        std::fs::read(pending.join(PLAN)).map_err(|e| FileError::new(&pending.join(PLAN), e))?;
    let plan: Plan = serde_json::from_slice(&text).map_err(PlanError::Json)?;
    for p in plan.remove.iter().chain(&plan.dirs).chain(&plan.files) {
        plan_path(p)?;
    }
    for (name, entry) in &plan.components {
        plan_path(entry)?;
        wyrm_core::keyspace::validate_segment(name).map_err(PlanError::Component)?;
    }
    Ok(plan)
}

/// What is there now, before anything of `plan` is done.
fn look_before(data_dir: &Path, pending: &Path, plan: &Plan) -> Before {
    let mut moved: Vec<String> = plan
        .remove
        .iter()
        .filter(|p| is_there(&data_dir.join(p)))
        .cloned()
        .collect();
    if plan.strip_link_certs {
        for link in std::fs::read_dir(data_dir.join("links"))
            .into_iter()
            .flatten()
            .flatten()
        {
            for f in std::fs::read_dir(link.path())
                .into_iter()
                .flatten()
                .flatten()
            {
                let name = f.file_name().to_string_lossy().into_owned();
                if f.path().is_file() && (name.ends_with(".pem") || name.ends_with(".key")) {
                    moved.push(format!(
                        "links/{}/{name}",
                        link.file_name().to_string_lossy()
                    ));
                }
            }
        }
    }
    moved.sort();
    let mut placed: Vec<String> = plan.dirs.iter().chain(&plan.files).cloned().collect();
    placed.extend(plan.components.iter().map(|(n, _)| component_target(n)));
    for extra in [(STORAGE_TREE, "storage"), (LINK_SECRETS, SECRETS_BIN)] {
        if pending.join(extra.0).is_file() && !placed.iter().any(|p| p == extra.1) {
            placed.push(extra.1.to_owned());
        }
    }
    // what a removal takes away is not there for what is placed after it
    let gone = |p: &String| {
        moved
            .iter()
            .any(|m| p == m || p.starts_with(&format!("{m}/")))
    };
    let existed = placed
        .iter()
        .filter(|p| is_there(&data_dir.join(p)) && !gone(p))
        .cloned()
        .collect();
    Before {
        existed,
        moved,
        placed,
    }
}

/// Do the plan. Every step may run again after a start that stopped in it.
/// What a step replaces or removes goes to `old/` first, never away.
fn forward(
    data_dir: &Path,
    pending: &Path,
    plan: &Plan,
    before: &Before,
) -> Result<(), PendingError> {
    let (staged, old) = (pending.join("data"), pending.join(OLD));
    let existed = |p: &str| before.existed.iter().any(|e| e == p);
    // what is at `p` goes aside, once; a leftover of an earlier try goes
    let aside = |p: &str| -> Result<(), FileError> {
        let (to, keep) = (data_dir.join(p), old.join(p));
        if !is_there(&to) {
            return Ok(());
        }
        if existed(p) && !is_there(&keep) {
            move_to(&to, &keep)
        } else {
            crate::nofollow::remove_any(&to).map_err(|e| FileError::new(&to, e))
        }
    };
    for m in &before.moved {
        let (at, keep) = (data_dir.join(m), old.join(m));
        if is_there(&at) && !is_there(&keep) {
            move_to(&at, &keep)?;
        }
    }
    // a staging of an earlier build left the storage as its tree: built
    // here, in the folder, before it is moved like any directory
    let tree = pending.join(STORAGE_TREE);
    let mut dirs = plan.dirs.clone();
    if tree.is_file() {
        let built = staged.join("storage");
        crate::nofollow::remove_any(&built).map_err(|e| FileError::new(&built, e))?;
        build_storage(&tree, &built)?;
        if !dirs.iter().any(|d| d == "storage") {
            dirs.push("storage".into());
        }
    }
    for p in dirs.iter().chain(&plan.files) {
        let from = staged.join(p);
        // moved already by a start that stopped after it
        if !is_there(&from) {
            continue;
        }
        aside(p)?;
        move_to(&from, &data_dir.join(p))?;
    }
    for (name, entry) in &plan.components {
        let target = component_target(name);
        aside(&target)?;
        let to = data_dir.join(&target);
        if let Some(d) = to.parent() {
            std::fs::create_dir_all(d).map_err(|e| FileError::new(d, e))?;
        }
        std::fs::copy(data_dir.join(entry), &to).map_err(|e| FileError::new(&to, e))?;
    }
    // link secrets go into the store that is in place now; the store as it
    // was is kept first
    let secrets = pending.join(LINK_SECRETS);
    if secrets.is_file() {
        let (at, keep) = (data_dir.join(SECRETS_BIN), old.join(SECRETS_BIN));
        if existed(SECRETS_BIN) && !is_there(&keep) {
            let bytes = Zeroizing::new(std::fs::read(&at).map_err(|e| FileError::new(&at, e))?);
            secret::write_private(&keep, &bytes).map_err(|e| FileError::new(&keep, e))?;
        }
        let bytes =
            Zeroizing::new(std::fs::read(&secrets).map_err(|e| FileError::new(&secrets, e))?);
        let links = parse_link_secrets(&bytes)?;
        let store =
            crate::secrets::SecretStore::open(data_dir).map_err(PendingError::SecretStore)?;
        for (link, m) in links {
            for (name, b) in m {
                store
                    .set(&link, &name, &b)
                    .map_err(PendingError::SecretStore)?;
            }
        }
    }
    Ok(())
}

/// `{link: {name: bytes}}`.
type LinkSecrets = BTreeMap<String, BTreeMap<String, Zeroizing<Vec<u8>>>>;

/// The link secrets a restore staged: `{link: {name: bytes}}`, without the
/// ones a broker makes for a link's identity (never taken from a backup).
fn parse_link_secrets(bytes: &[u8]) -> Result<LinkSecrets, LinkSecretsError> {
    let Value::Map(links) =
        wyrm_core::codec::from_slice::<Value>(bytes).map_err(LinkSecretsError::Decode)?
    else {
        return Err(LinkSecretsError::NotMap);
    };
    let mut out = BTreeMap::new();
    for (link, v) in links {
        crate::registry::validate_link_id(&link).map_err(LinkSecretsError::LinkId)?;
        let Value::Map(m) = v else {
            return Err(LinkSecretsError::LinkNotMap { link });
        };
        let mut of_link = BTreeMap::new();
        for (name, v) in m {
            if broker_made_secret(&name) {
                continue;
            }
            let Value::Bytes(b) = v else {
                return Err(LinkSecretsError::NotBytes { link, name });
            };
            of_link.insert(name, Zeroizing::new(b));
        }
        out.insert(link, of_link);
    }
    Ok(out)
}

/// The storage of a backup (`storage/tree.cbor`) as a new store at `dir`.
fn build_storage(tree: &Path, dir: &Path) -> Result<(), StorageError> {
    let bytes = std::fs::read(tree).map_err(|e| FileError::new(tree, e))?;
    let value = wyrm_core::codec::from_slice(&bytes).map_err(StorageError::TreeDecode)?;
    let changes = replication::parse_changes(value).ok_or(StorageError::TreeShape)?;
    let store = wyrm_storage::Store::open(dir).map_err(StorageError::Store)?;
    store
        .apply(changes.put, Vec::new())
        .map_err(StorageError::Store)?;
    Ok(())
}

/// Put back what [`forward`] replaced or removed, then keep the folder as
/// `restore.failed` with `why`. Every step may run again. `Err`: something
/// could not be put back (the state is then neither the old nor the new).
fn undo(data_dir: &Path, pending: &Path, before: &Before, why: &str) -> Result<(), FileError> {
    let old = pending.join(OLD);
    if !pending.join(UNDO).exists() {
        secret::write_private(&pending.join(UNDO), why.as_bytes())
            .map_err(|e| FileError::new(pending, e))?;
    }
    for p in before.placed.iter().rev() {
        let (to, keep) = (data_dir.join(p), old.join(p));
        if before.existed.contains(p) {
            // not set aside: never touched, or back already
            if is_there(&keep) {
                crate::nofollow::remove_any(&to).map_err(|e| FileError::new(&to, e))?;
                move_to(&keep, &to)?;
            }
        } else {
            // placed by the restore: what it put there goes, or the undo is not done
            crate::nofollow::remove_any(&to).map_err(|e| FileError::new(&to, e))?;
        }
    }
    for m in before.moved.iter().rev() {
        let (at, keep) = (data_dir.join(m), old.join(m));
        if is_there(&keep) {
            crate::nofollow::remove_any(&at).map_err(|e| FileError::new(&at, e))?;
            move_to(&keep, &at)?;
        }
    }
    set_failed(data_dir, pending, why)
}

/// The folder becomes `restore.failed`: its plan and the reason stay,
/// everything else (opened keys and secrets among it) goes.
fn set_failed(data_dir: &Path, pending: &Path, why: &str) -> Result<(), FileError> {
    // The state is the old one here; what is left of the folder is the broker's own
    // private directory (0700). A part that does not go (opened keys and secrets among
    // them) is named in the log, as in `apply_pending`, and never stops the start that
    // runs on the old state: the next restore removes `restore.failed` first.
    let left = |p: &Path, r: std::io::Result<()>| {
        if let Err(e) = r {
            tracing::error!("{} stays: {e}", p.display());
        }
    };
    for name in ["data", OLD, LINK_SECRETS, STORAGE_TREE, BEFORE] {
        let p = pending.join(name);
        left(&p, crate::nofollow::remove_any(&p));
    }
    secret::write_private(&pending.join(ERROR), why.as_bytes())
        .map_err(|e| FileError::new(pending, e))?;
    // moved with the folder when it stays; a folder that is not moved is undone again
    // at the next start, which is safe (every step may run again)
    let undo_mark = pending.join(UNDO);
    left(
        &undo_mark,
        std::fs::remove_file(&undo_mark).or_else(wyrm_core::files::gone_ok),
    );
    let failed = data_dir.join(FAILED);
    left(&failed, crate::nofollow::remove_any(&failed));
    std::fs::rename(pending, &failed).map_err(|e| FileError::new(&failed, e))
}

/// Put a restore staged in `data_dir/restore.pending` in place. Call it
/// before any store of `data_dir` opens, then [`commit_pending`] once the
/// stores opened, or [`undo_pending`] when they did not.
///
/// All or nothing (ADR 0048 §3.6): what the plan replaces or removes is
/// set aside in the folder, never deleted, until the commit. `Ok(Some)`:
/// the plan is in place. `Ok(None)`: nothing was staged, or the plan could
/// not be applied: then everything is as it was before, the folder is
/// `restore.failed` and [`take_failure`] says why, and the broker starts
/// with the state it had. `Err`: the state before could not be put back
/// either. A start that stopped halfway is taken up again by the next one.
pub fn apply_pending(data_dir: &Path) -> Result<Option<Applied>, PendingError> {
    // a staging that never finished; a restore that was committed. Both may hold
    // opened secrets; one that stays is named, and the next start tries again
    for left in [PENDING_TMP, DONE] {
        let p = data_dir.join(left);
        if let Err(e) = crate::nofollow::remove_any(&p) {
            tracing::error!("{} stays: {e}", p.display());
        }
    }
    let pending = data_dir.join(PENDING);
    if !pending.is_dir() {
        return Ok(None);
    }
    let started = pending.join(BEFORE).exists();
    let plan = match read_plan(&pending) {
        Ok(plan) => plan,
        // nothing was changed yet: the folder is set aside
        Err(e) if !started => {
            set_failed(data_dir, &pending, &e.to_string())?;
            return Ok(None);
        }
        Err(e) => return Err(PendingError::Begun(e)),
    };
    let before: Before = if started {
        let text = std::fs::read(pending.join(BEFORE))
            .map_err(|e| FileError::new(&pending.join(BEFORE), e))?;
        serde_json::from_slice(&text).map_err(PendingError::Before)?
    } else {
        let b = look_before(data_dir, &pending, &plan);
        let text = serde_json::to_vec(&b).map_err(PendingError::BeforeEncode)?;
        secret::write_private(&pending.join(BEFORE), &text)
            .map_err(|e| FileError::new(&pending, e))?;
        b
    };
    // an undo that a start stopped in goes on
    if pending.join(UNDO).exists() {
        let why = std::fs::read_to_string(pending.join(UNDO)).unwrap_or_default();
        undo(data_dir, &pending, &before, &why)?;
        return Ok(None);
    }
    match forward(data_dir, &pending, &plan, &before) {
        Ok(()) => Ok(Some(Applied {
            by: plan.by,
            backup: plan.backup,
            sections: plan.sections,
        })),
        Err(e) => {
            undo(data_dir, &pending, &before, &e.to_string())?;
            Ok(None)
        }
    }
}

/// The stores opened on what [`apply_pending`] put in place: the restore
/// is committed and what it replaced goes. The plan is removed last (the
/// folder is renamed first, then removed).
pub fn commit_pending(data_dir: &Path) {
    let pending = data_dir.join(PENDING);
    if !pending.is_dir() {
        return;
    }
    let done = data_dir.join(DONE);
    let remove_done = || {
        // what the restore replaced; the next start tries again (`apply_pending`)
        if let Err(e) = crate::nofollow::remove_any(&done) {
            tracing::error!("{} stays: {e}", done.display());
        }
    };
    remove_done();
    match std::fs::rename(&pending, &done) {
        Ok(()) => remove_done(),
        Err(e) => warn!("{}: {e}", pending.display()),
    }
}

/// The stores did not open on what [`apply_pending`] put in place (`why`):
/// everything goes back as it was before the restore, and the folder is
/// kept as `restore.failed`. The next start runs on the old state.
pub fn undo_pending(data_dir: &Path, why: &str) -> Result<(), PendingError> {
    let pending = data_dir.join(PENDING);
    if !pending.is_dir() {
        return Ok(());
    }
    let text = std::fs::read(pending.join(BEFORE))
        .map_err(|e| FileError::new(&pending.join(BEFORE), e))?;
    let before: Before = serde_json::from_slice(&text).map_err(PendingError::Before)?;
    Ok(undo(data_dir, &pending, &before, why)?)
}

/// A restore that was not applied and was not reported yet: reported once
/// (the caller audits it). The folder `restore.failed` stays for people.
pub fn take_failure(data_dir: &Path) -> Option<Failure> {
    let failed = data_dir.join(FAILED);
    if !failed.is_dir() || failed.join(REPORTED).exists() {
        return None;
    }
    let error = std::fs::read_to_string(failed.join(ERROR)).unwrap_or_default();
    let plan = read_plan(&failed).unwrap_or_default();
    // without the mark the failure is reported again at the next start
    if let Err(e) = std::fs::write(failed.join(REPORTED), b"") {
        tracing::warn!(dir = %failed.display(), "restore failure not marked as reported: {e}");
    }
    Some(Failure {
        by: plan.by,
        backup: plan.backup,
        sections: plan.sections,
        error,
    })
}

/// A broker backup read and checked.
struct Checked {
    manifest: Manifest,
    key: Option<MasterKey>,
    /// The backup's keys are of another CA than this broker's.
    keys_other: bool,
    /// Files of the `keys` section (paths under `data_dir`) that are not
    /// byte for byte this broker's.
    keys_differ: Vec<String>,
    /// Every file of the backup with its place.
    places: Vec<(String, Place)>,
    /// The registry WAL of the backup opens with this broker's `state.key`.
    wal_opens_here: bool,
    /// What stands in the way of a `replace`.
    problems: Vec<Problem>,
    notes: Vec<String>,
}

fn strs(v: &[String]) -> Value {
    Value::Array(v.iter().map(|s| Value::from(s.clone())).collect())
}

/// Section names as a list of their names.
fn section_values(v: &[SectionName]) -> Value {
    Value::Array(v.iter().map(|s| Value::from(s.name())).collect())
}

impl Control {
    /// Read the broker backup at `path` whole and compare it with this
    /// broker. Blocking.
    fn check_broker_backup(
        &self,
        r: &mut format::Reader,
        passphrase: Option<&[u8]>,
    ) -> Result<Checked, BrokerRestoreError> {
        let manifest = r.manifest().clone();
        if manifest.kind != Kind::Broker {
            return Err(BrokerRestoreError::LinkBackup);
        }
        // every file has a place a section defines, or nothing is restored
        let mut places = Vec::new();
        for f in manifest.sections.iter().flat_map(|s| &s.files) {
            places.push((f.path.clone(), place_of(&f.path)?));
        }
        r.verify(|_, _| {})?;
        let key = self.backup_key(&manifest, passphrase)?;
        let mut problems = Vec::new();
        let mut notes = Vec::new();
        if manifest.site != self.cfg.site {
            problems.push(Problem::OtherSite {
                backup: manifest.site.clone(),
                here: self.cfg.site.clone(),
            });
        }
        let here = self.schemas();
        for (name, v) in &manifest.schemas {
            if let Some(h) = here.get(name).filter(|h| v > *h) {
                problems.push(Problem::NewerSchema {
                    store: name.clone(),
                    backup: *v,
                    here: *h,
                });
            }
        }
        let d = &self.cfg.data_dir;
        let mut keys_other = false;
        let mut keys_differ = Vec::new();
        if manifest.section(SectionName::Keys).is_some() {
            if !places.iter().any(|(_, p)| *p == Place::Key(CA_FILE.into())) {
                return Err(BrokerRestoreError::NoCa);
            }
            for (path, place) in &places {
                let Place::Key(rel) = place else { continue };
                let theirs = r.read_plain(path, key.as_ref())?;
                let own = Zeroizing::new(std::fs::read(d.join(rel)).unwrap_or_default());
                if theirs.as_slice() != own.as_slice() {
                    keys_differ.push(rel.clone());
                }
            }
            keys_other = keys_differ.iter().any(|f| f == CA_FILE);
            if keys_other {
                notes.push(
                    "the keys of the backup are of another CA: with replace_keys every link \
                     process, operator and peer broker enrols again"
                        .into(),
                );
            } else if !keys_differ.is_empty() {
                notes.push(format!(
                    "keys of the backup differ from this broker's: {}; they are put in place \
                     only with replace_keys",
                    keys_differ.join(", ")
                ));
            }
        }
        // A control section is what a broker makes of its stores: segments
        // alone, the registry among them. A file a store does not read (a
        // segment under another name) would be put in place and the store
        // would open without a record.
        if manifest.section(SectionName::Control).is_some() {
            let mut registry = false;
            for (path, place) in &places {
                let Place::Wal { name, file, .. } = place else {
                    continue;
                };
                if wyrm_state::segment_first_lsn(file).is_none() {
                    return Err(ControlError::NotSegment { path: path.clone() }.into());
                }
                registry |= *name == "state";
            }
            if !registry {
                return Err(ControlError::NoRegistry.into());
            }
        }
        // does the registry of the backup open with the key in place here?
        let scratch =
            super::backups::StageDir::new(&self.backups_dir()).map_err(RestoreError::from)?;
        let mut wal_opens_here = true;
        let mut any = false;
        for f in &manifest
            .section(SectionName::Control)
            .map(|s| s.files.clone())
            .unwrap_or_default()
        {
            if let Some(file) = f.path.strip_prefix("control/state/") {
                r.extract(&f.path, &scratch.0.join("state").join(file), None)?;
                any = true;
            }
        }
        if any {
            let state_key = secret::load_or_create_key(&d.join("state.key"))
                .map_err(BrokerRestoreError::KeyLoad)?;
            let opened = wyrm_state::replicate::copy_to(
                &scratch.0.join("state"),
                &state_key,
                &scratch.0.join("verify"),
            );
            // Under this broker's key the records can be counted now. Under
            // other keys they are counted when the restore is staged, with
            // the key that will be in place (`stage_replace`).
            if let Ok(head) = &opened {
                head_as_said(&manifest, "state", head.lsn)?;
            }
            wal_opens_here = opened.is_ok();
        }
        if !wal_opens_here {
            notes.push(
                "the control plane of the backup is under other keys than this broker's: it is \
                 restored only together with the keys section"
                    .into(),
            );
        }
        if self.cfg.anchor_dir.is_some() {
            notes.push(
                "state_anchor_dir is set: the control plane is restored offline, then `wyrmd \
                 init-anchors` (docs/operations.md §3)"
                    .into(),
            );
        }
        Ok(Checked {
            manifest,
            key,
            keys_other,
            keys_differ,
            places,
            wal_opens_here,
            problems,
            notes,
        })
    }

    /// The answer of `restore_check`.
    fn check_report(&self, c: &Checked, size: u64) -> Value {
        let m = &c.manifest;
        let reg = self.registry();
        let here = self.schemas();
        let links: BTreeMap<String, Value> = m
            .section(SectionName::Links)
            .map(|s| {
                s.info
                    .keys()
                    .map(|id| {
                        let state = if reg.links.contains_key(id) {
                            "exists"
                        } else {
                            "new"
                        };
                        (id.clone(), Value::from(state))
                    })
                    .collect()
            })
            .unwrap_or_default();
        Value::Map(BTreeMap::from([
            ("size".to_owned(), Value::UInt(size)),
            ("site".to_owned(), Value::from(m.site.clone())),
            ("same_site".to_owned(), Value::Bool(m.site == self.cfg.site)),
            ("created".to_owned(), Value::from(m.created.clone())),
            ("broker".to_owned(), Value::from(m.broker.clone())),
            ("sealed".to_owned(), Value::from(m.sealed.how.name())),
            (
                "schemas".to_owned(),
                Value::Map(
                    m.schemas
                        .iter()
                        .map(|(k, v)| {
                            let pair = BTreeMap::from([
                                ("backup".to_owned(), Value::UInt((*v).into())),
                                (
                                    "here".to_owned(),
                                    Value::UInt(here.get(k).copied().unwrap_or(0).into()),
                                ),
                            ]);
                            (k.clone(), Value::Map(pair))
                        })
                        .collect(),
                ),
            ),
            (
                "sections".to_owned(),
                Value::Map(
                    m.sections
                        .iter()
                        .map(|s| (s.name.name().to_owned(), Value::UInt(s.size())))
                        .collect(),
                ),
            ),
            (
                "keys".to_owned(),
                // `other`: another CA; `differ`: this CA, other key files
                Value::from(
                    match (
                        m.section(SectionName::Keys).is_some(),
                        c.keys_other,
                        c.keys_differ.is_empty(),
                    ) {
                        (false, ..) => "none",
                        (true, true, _) => "other",
                        (true, false, true) => "same",
                        (true, false, false) => "differ",
                    },
                ),
            ),
            ("keys_differ".to_owned(), strs(&c.keys_differ)),
            (
                "control_opens_here".to_owned(),
                Value::Bool(c.wal_opens_here),
            ),
            ("links".to_owned(), Value::Map(links)),
            (
                "problems".to_owned(),
                Value::Array(
                    c.problems
                        .iter()
                        .map(|p| Value::from(p.to_string()))
                        .collect(),
                ),
            ),
            ("notes".to_owned(), strs(&c.notes)),
            ("restart".to_owned(), Value::from("replace")),
        ]))
    }

    /// Stage the sections `chosen` of a checked backup for `mode: replace`
    /// into `restore.pending` (blocking). The folder appears whole or not
    /// at all. Every destination comes from the file's [`Place`], never
    /// from its path in the archive. `accept`: the caller has seen what the
    /// packages of the backup ask for.
    fn stage_replace(
        &self,
        r: &mut format::Reader,
        c: &Checked,
        chosen: &[SectionName],
        accept: bool,
        by: &str,
    ) -> Result<Plan, BrokerRestoreError> {
        let d = &self.cfg.data_dir;
        let tmp = d.join(PENDING_TMP);
        // an earlier staging (it may hold opened secrets) goes before this one
        crate::nofollow::remove_any(&tmp).map_err(|e| FileError::new(&tmp, e))?;
        // what the chosen sections open into must fit, before any of it is
        self.room_for(super::restore::extract_need(
            c.manifest
                .sections
                .iter()
                .filter(|s| chosen.contains(&s.name) || s.name == SectionName::Control)
                .flat_map(|s| &s.files),
        ))?;
        make_private_dir(&tmp)?;
        let staged = self.stage_sections(r, c, chosen, accept, by, &tmp);
        let plan = match staged {
            Ok(plan) => plan,
            Err(e) => {
                // nothing half staged stays (it may hold opened secrets)
                if let Err(r) = crate::nofollow::remove_any(&tmp) {
                    tracing::error!("{} stays: {r}", tmp.display());
                    return Err(BrokerRestoreError::Stays {
                        error: Box::new(e),
                        path: tmp,
                        source: r,
                    });
                }
                return Err(e);
            }
        };
        let pending = d.join(PENDING);
        crate::nofollow::remove_any(&pending).map_err(|e| FileError::new(&pending, e))?;
        // an earlier restore that was not applied is forgotten
        let failed = d.join(FAILED);
        crate::nofollow::remove_any(&failed).map_err(|e| FileError::new(&failed, e))?;
        std::fs::rename(&tmp, &pending).map_err(|e| FileError::new(&pending, e))?;
        Ok(plan)
    }

    /// The body of [`Self::stage_replace`]: everything into `tmp`.
    fn stage_sections(
        &self,
        r: &mut format::Reader,
        c: &Checked,
        chosen: &[SectionName],
        accept: bool,
        by: &str,
        tmp: &Path,
    ) -> Result<Plan, BrokerRestoreError> {
        let d = &self.cfg.data_dir;
        let mut st = Staging {
            r,
            c,
            chosen,
            tmp,
            data: tmp.join("data"),
            plan: Plan {
                by: by.to_owned(),
                backup: format!("{} {}", c.manifest.site, c.manifest.created),
                sections: chosen.to_vec(),
                ..Default::default()
            },
        };
        let keys = st.has(SectionName::Keys) && c.manifest.section(SectionName::Keys).is_some();
        if keys {
            st.key_files()?;
        }
        st.wals(d, keys)?;
        if st.has(SectionName::Dataflows) {
            st.artifacts()?;
        }
        if st.has(SectionName::Storage) && c.manifest.section(SectionName::Storage).is_some() {
            st.storage()?;
        }
        if st.has(SectionName::History) && c.manifest.section(SectionName::History).is_some() {
            st.history()?;
        }
        if st.has(SectionName::Links) {
            // with `control` every link of the backup is in the registry
            // that will be in place; without it, the links this broker has
            st.links(&self.registry(), keys)?;
        }
        if st.has(SectionName::Packages) {
            st.packages(&self.registry(), d, accept)?;
        }
        let Staging { data, plan, .. } = st;
        // the secret store of the backup opens with the key that comes with it
        if keys && data.join(SECRETS_BIN).is_file() && data.join("secrets.key").is_file() {
            crate::secrets::SecretStore::open(&data)
                .map(drop)
                .map_err(BrokerRestoreError::SecretStore)?;
        }
        let text = serde_json::to_vec_pretty(&plan).map_err(BrokerRestoreError::PlanEncode)?;
        secret::write_private(&tmp.join(PLAN), &text).map_err(|e| FileError::new(tmp, e))?;
        // as the start that applies it will read it
        read_plan(tmp)?;
        Ok(plan)
    }
}

/// A `replace` being staged ([`Control::stage_sections`]): the reader of the
/// backup and what its check found, the sections chosen, the directory it
/// stages into (`data` under it holds what goes to `data_dir`) and the plan
/// that the start which applies it follows. One method per section, called
/// in the order of the format.
struct Staging<'a> {
    r: &'a mut format::Reader,
    c: &'a Checked,
    chosen: &'a [SectionName],
    tmp: &'a Path,
    data: PathBuf,
    plan: Plan,
}

impl Staging<'_> {
    fn has(&self, s: SectionName) -> bool {
        self.chosen.contains(&s)
    }

    /// `keys`: every key file of the backup; when they are of another CA,
    /// everything the replaced CA issued goes.
    fn key_files(&mut self) -> Result<(), BrokerRestoreError> {
        let c = self.c;
        let key = c.key.as_ref();
        for (p, place) in &c.places {
            let Place::Key(rel) = place else { continue };
            self.r.extract(p, &self.data.join(rel), key)?;
            self.plan.files.push(rel.clone());
        }
        if c.keys_other {
            // everything the replaced CA issued: also the gateway's certificate of
            // `gateway.tls: "site_ca"` (never the rest of `gateway`: users, keys, setup)
            self.plan.remove = vec![
                "pki".into(),
                "operators".into(),
                "peers".into(),
                "gateway/tls.pem".into(),
                "gateway/tls.key".into(),
            ];
            self.plan.strip_link_certs = true;
        }
        Ok(())
    }

    /// The WALs: the registry, users (and the audit when its key is
    /// replaced) with `control`; the flow store with `control` or
    /// `dataflows`. Each is read through with the key that will be in place
    /// and must hold every record the backup says it holds.
    fn wals(&mut self, d: &Path, keys: bool) -> Result<(), BrokerRestoreError> {
        let c = self.c;
        let (data, tmp) = (&self.data, self.tmp);
        let state_key_replaced = keys && c.keys_differ.iter().any(|f| f == "state.key");
        for (name, dir, key_file, _) in wal_stores() {
            let wanted = match name {
                "flows" => self.has(SectionName::Control) || self.has(SectionName::Dataflows),
                "audit" => self.has(SectionName::Control) && state_key_replaced,
                _ => self.has(SectionName::Control),
            };
            let files: Vec<(&String, &String)> = c
                .places
                .iter()
                .filter_map(|(p, place)| match place {
                    Place::Wal { name: n, file, .. } if *n == name => Some((p, file)),
                    _ => None,
                })
                .collect();
            if !wanted || files.is_empty() {
                continue;
            }
            for (p, file) in files {
                self.r.extract(p, &data.join(dir).join(file), None)?;
            }
            // with the key that will be in place
            let staged_key = data.join(key_file);
            let key_path = if staged_key.is_file() {
                staged_key
            } else {
                d.join(key_file)
            };
            let wal_key =
                secret::load_or_create_key(&key_path).map_err(BrokerRestoreError::KeyLoad)?;
            let head = wyrm_state::replicate::copy_to(
                &data.join(dir),
                &wal_key,
                &tmp.join("verify").join(name),
            )
            .map_err(|source| BrokerRestoreError::WalKeys {
                store: name,
                source,
            })?;
            // every record the backup says it holds, or nothing is staged
            head_as_said(&c.manifest, name, head.lsn)?;
            self.plan.dirs.push(dir.to_owned());
        }
        wyrm_core::files::discard_dir(&tmp.join("verify"));
        Ok(())
    }

    /// `dataflows`: the artifacts of the flows.
    fn artifacts(&mut self) -> Result<(), BrokerRestoreError> {
        let dir = self.data.join("flows").join("artifacts");
        std::fs::create_dir_all(&dir).map_err(|e| FileError::new(&dir, e))?;
        for (p, place) in &self.c.places {
            if let Place::Artifact(rel) = place {
                self.r.extract(p, &dir.join(rel), None)?;
            }
        }
        self.plan.dirs.push("flows/artifacts".into());
        Ok(())
    }

    /// `storage`: the store is built here, from the tree: a tree that does
    /// not read refuses the restore now, not the start that applies it.
    fn storage(&mut self) -> Result<(), BrokerRestoreError> {
        let tree = self.tmp.join(STORAGE_TREE);
        self.r.extract("storage/tree.cbor", &tree, None)?;
        build_storage(&tree, &self.data.join("storage"))?;
        std::fs::remove_file(&tree).map_err(|e| FileError::new(&tree, e))?;
        self.plan.dirs.push("storage".into());
        Ok(())
    }

    /// `history`: its index and day files, which must open.
    fn history(&mut self) -> Result<(), BrokerRestoreError> {
        let dir = self.data.join("history");
        std::fs::create_dir_all(dir.join("days")).map_err(|e| FileError::new(&dir, e))?;
        for (p, place) in &self.c.places {
            match place {
                Place::HistoryIndex => self.r.extract(p, &dir.join("index.redb"), None)?,
                Place::HistoryDay(day) => self.r.extract(p, &dir.join("days").join(day), None)?,
                _ => continue,
            };
        }
        // files that do not open would stop every start after the restore
        wyrm_history::Store::open(&dir)
            .map(drop)
            .map_err(BrokerRestoreError::History)?;
        self.plan.dirs.push("history".into());
        Ok(())
    }

    /// `links`: the private data of each link of the backup that will be in
    /// the registry (`reg` when `control` is not restored) and, without
    /// `keys`, its secrets.
    fn links(&mut self, reg: &Registry, keys: bool) -> Result<(), BrokerRestoreError> {
        let c = self.c;
        let key = c.key.as_ref();
        let mut secrets: BTreeMap<String, Value> = BTreeMap::new();
        let ids: BTreeSet<&String> = c
            .places
            .iter()
            .filter_map(|(_, place)| match place {
                Place::LinkSecrets(id) => Some(id),
                _ => None,
            })
            .collect();
        for id in ids {
            if !self.has(SectionName::Control) && !reg.links.contains_key(id) {
                continue;
            }
            let dir = self.data.join("links").join(id).join("data");
            std::fs::create_dir_all(&dir).map_err(|e| FileError::new(&dir, e))?;
            for (p, place) in &c.places {
                match place {
                    Place::LinkFile(l, rel) if l == id => {
                        self.r.extract(p, &dir.join(rel), key)?;
                    }
                    _ => {}
                }
            }
            self.plan.dirs.push(format!("links/{id}/data"));
            // With `keys`, the `secrets.bin` of the backup holds them
            // already: the store comes back whole, the secrets the
            // broker made for its links among them (they are that
            // site's own, restored under the gates of the keys).
            // Without `keys`, a link's secrets go into this broker's
            // store, and a broker-made one is never taken from a file.
            if !keys {
                let plain = self.r.read_plain(&format!("links/{id}/secrets"), key)?;
                let Value::Map(m) = wyrm_core::codec::from_slice::<Value>(&plain)
                    .map_err(RestoreError::SecretsDecode)?
                else {
                    return Err(RestoreError::SecretsNotMap {
                        path: format!("links/{id}/secrets"),
                    }
                    .into());
                };
                let kept: BTreeMap<String, Value> = m
                    .into_iter()
                    .filter(|(name, _)| !broker_made_secret(name))
                    .collect();
                secrets.insert(id.clone(), Value::Map(kept));
            }
        }
        if !secrets.is_empty() {
            let bytes = Zeroizing::new(
                wyrm_core::codec::to_vec(&Value::Map(secrets))
                    .map_err(BrokerRestoreError::SecretsEncode)?,
            );
            // as the start that applies it will read it
            parse_link_secrets(&bytes)?;
            secret::write_private(&self.tmp.join(LINK_SECRETS), &bytes)
                .map_err(|e| FileError::new(self.tmp, e))?;
        }
        Ok(())
    }

    /// `packages`: each package of the backup, through the validator of
    /// every install; what one asks for counts (refused without `accept`)
    /// unless this broker (`reg`, `d`) has the same version with the same
    /// files.
    fn packages(
        &mut self,
        reg: &Registry,
        d: &Path,
        accept: bool,
    ) -> Result<(), BrokerRestoreError> {
        let c = self.c;
        let (data, tmp) = (&self.data, self.tmp);
        let names: BTreeSet<&String> = c
            .places
            .iter()
            .filter_map(|(_, place)| match place {
                Place::PackageFile(name, _) => Some(name),
                _ => None,
            })
            .collect();
        let mut asks = Vec::new();
        for name in names {
            let scratch = tmp.join("package").join(name);
            for (p, place) in &c.places {
                match place {
                    Place::PackageFile(n, rel) if n == name => {
                        self.r.extract(p, &scratch.join(rel), None)?;
                    }
                    _ => {}
                }
            }
            // through the validator of every install; its record names
            // the version and the entry
            let source = format!("backup {}", c.manifest.site);
            let zip =
                packages::repack(&scratch).map_err(|e| RestoreError::Repack(e.to_string()))?;
            let checked =
                packages::unpack(&zip, &tmp.join("unpacked"), &source, now_s()).map_err(|why| {
                    BrokerRestoreError::PackageInvalid {
                        name: name.clone(),
                        why: why.to_string(),
                    }
                })?;
            let def = checked.def.clone();
            if def.name != *name {
                return Err(BrokerRestoreError::PackageName {
                    dir: name.clone(),
                    holds: def.name,
                });
            }
            wyrm_core::keyspace::validate_segment(&def.version)
                .map_err(BrokerRestoreError::PackageVersion)?;
            let rel = format!("packages/{}/{}", def.name, def.version);
            // what it asks for was accepted here only if this broker
            // has the same version with the same files
            let here = reg.packages.get(&def.name).is_some_and(|p| {
                p.version == def.version && packages::repack(&d.join(&rel)).is_ok_and(|z| z == zip)
            });
            if !here {
                asks.extend(super::restore::package_asks(&checked));
            }
            let to = data.join(&rel);
            if let Some(parent) = to.parent() {
                std::fs::create_dir_all(parent).map_err(|e| FileError::new(parent, e))?;
            }
            std::fs::rename(&scratch, &to).map_err(|e| FileError::new(&to, e))?;
            if def.kind == PackageKind::Wasm {
                self.plan
                    .components
                    .push((def.name.clone(), format!("{rel}/{}", def.entry)));
            }
            self.plan.dirs.push(rel);
        }
        wyrm_core::files::discard_dir(&tmp.join("package"));
        wyrm_core::files::discard_dir(&tmp.join("unpacked"));
        if !asks.is_empty() && !accept {
            return Err(BrokerRestoreError::Asks { asks });
        }
        Ok(())
    }
}

/// `sys/backups ▸ restore_check`: the uploaded backup and what opens it.
#[derive(Args)]
pub(super) struct RestoreCheck {
    #[param(display = "Upload", desc = "The id restore_begin gave", nonempty)]
    pub upload: String,
    #[param(
        display = "Passphrase",
        secret,
        nonempty,
        desc = "Of a backup sealed with one"
    )]
    pub passphrase: Option<Secret>,
}

/// How `restore_apply` restores.
#[derive(Args)]
pub(super) struct ApplyHow {
    #[param(choice, display = "Sections")]
    pub sections: Vec<SectionName>,
    #[param(
        choice,
        display = "Mode",
        desc = "add: what does not exist yet, live. replace: the broker stops and \
                applies it at the next start"
    )]
    pub mode: RestoreMode,
    #[param(
        display = "Accept requested rights",
        desc = "Of the links mode add installs and of the packages mode replace \
                brings",
        absent = false
    )]
    pub accept: bool,
    #[param(
        display = "Replace the site's keys",
        desc = "Keys that differ from this broker's (restore_check lists them). \
                Another CA: links, operators and peer brokers enrol again",
        absent = false
    )]
    pub replace_keys: bool,
}

/// `sys/backups ▸ restore_apply`.
#[derive(Args)]
pub(super) struct RestoreApply {
    #[param(flatten)]
    pub file: RestoreCheck,
    #[param(flatten)]
    pub how: ApplyHow,
}

impl Admin {
    /// `sys/backups/~act/restore_check` and `restore_apply`. The caller holds
    /// `Control::busy` (taken before the arguments are read).
    pub(super) async fn restore_broker(
        &self,
        file: RestoreCheck,
        apply: Option<ApplyHow>,
        sub: &str,
        remote: bool,
    ) -> wyrm_link_sdk::Result<Option<Value>> {
        let ctl = &self.ctl;
        let upload = file.upload;
        let passphrase = super::backups::passphrase_bytes(file.passphrase);
        let path = ctl.upload_take(&upload)?;
        let r = match apply {
            None => self.restore_check(&path, passphrase).await,
            Some(how) => {
                self.restore_apply(&path, how, passphrase, sub, remote)
                    .await
            }
        };
        // the file stays for the next call (a check, then an apply) until a
        // replace took it
        let used = matches!(&r, Ok((_, true)));
        ctl.upload_release(&upload, used);
        // a restore, a backup, an update or an install in flight is a reason to
        // try again: `BrokerRestoreError::status`
        r.map(|(v, _)| Some(v)).map_err(LinkError::from)
    }

    async fn restore_check(
        &self,
        path: &Path,
        passphrase: Option<Zeroizing<Vec<u8>>>,
    ) -> Result<(Value, bool), BrokerRestoreError> {
        let (ctl, path) = (self.ctl.clone(), path.to_owned());
        tokio::task::spawn_blocking(move || -> Result<(Value, bool), BrokerRestoreError> {
            let size = std::fs::metadata(&path).map_or(0, |m| m.len());
            let mut r = format::Reader::open(&path, MAX_UPLOAD)?;
            let c = ctl.check_broker_backup(&mut r, passphrase.as_deref().map(|p| &p[..]))?;
            Ok((ctl.check_report(&c, size), false))
        })
        .await
        .map_err(BrokerRestoreError::Task)?
    }

    async fn restore_apply(
        &self,
        path: &Path,
        how: ApplyHow,
        passphrase: Option<Zeroizing<Vec<u8>>>,
        sub: &str,
        remote: bool,
    ) -> Result<(Value, bool), BrokerRestoreError> {
        let ctl = &self.ctl;
        let (chosen, mode) = (how.sections, how.mode);
        let allowed = mode.sections();
        if let Some(s) = chosen.iter().find(|s| !allowed.contains(s)) {
            return Err(BrokerRestoreError::Section { section: *s, mode });
        }
        if chosen.is_empty() {
            return Err(BrokerRestoreError::NoSections);
        }
        if mode == RestoreMode::Add {
            return self
                .restore_add(path, &chosen, passphrase, how.accept, sub)
                .await
                .map(|v| (v, false));
        }
        let (replace_keys, accept) = (how.replace_keys, how.accept);
        // a caller from above is refused before the file is opened
        if remote {
            replace_gates(&Gates {
                remote,
                keys: false,
                differ: &[],
                export_secrets: false,
                passphrase: false,
                replace_keys: false,
            })?;
        }
        // nothing else changes a package or a link while this is staged
        // (ADR 0048 §1.9); the flag stays until the broker stops
        ctl.replacing(true).map_err(BrokerRestoreError::Busy)?;
        let (ctl2, path2, sub2, chosen2) =
            (ctl.clone(), path.to_owned(), sub.to_owned(), chosen.clone());
        let staged = tokio::task::spawn_blocking(move || -> Result<Plan, BrokerRestoreError> {
            let ctl = ctl2;
            let has = |s: SectionName| chosen2.contains(&s);
            let pass = passphrase.as_deref().map(|p| &p[..]);
            let mut r = format::Reader::open(&path2, MAX_UPLOAD)?;
            let c = ctl.check_broker_backup(&mut r, pass)?;
            if let Some(p) = c.problems.first() {
                return Err(p.clone().into());
            }
            if let Some(s) = chosen2.iter().find(|s| c.manifest.section(**s).is_none()) {
                return Err(BrokerRestoreError::MissingSection(*s));
            }
            if has(SectionName::Control) && ctl.cfg.anchor_dir.is_some() {
                return Err(BrokerRestoreError::Anchored);
            }
            // Every restore of `keys` passes the gates, whatever the CA: the
            // host allowed secrets to move, the caller is of this site and
            // gave the passphrase; keys that differ in any file also need
            // `replace_keys`.
            replace_gates(&Gates {
                remote,
                keys: has(SectionName::Keys),
                differ: &c.keys_differ,
                export_secrets: ctl.cfg.backups.export_secrets,
                passphrase: pass.is_some(),
                replace_keys,
            })?;
            // keys of the backup that replace other ones
            let new_keys = has(SectionName::Keys) && !c.keys_differ.is_empty();
            if has(SectionName::Control) && !c.wal_opens_here && !new_keys {
                return Err(BrokerRestoreError::ControlKeys);
            }
            // a backup of what is replaced, first. Keys go into it only
            // when they are replaced, under the passphrase of this restore
            // (the key of a broker-sealed file would be replaced with them).
            let mut before: Vec<SectionName> = chosen2
                .iter()
                .copied()
                .filter(|s| new_keys || *s != SectionName::Keys)
                .collect();
            if before.contains(&SectionName::History) && ctl.history.store().days().is_empty() {
                before.retain(|s| *s != SectionName::History);
            }
            let job = ctl.backup_now(
                BackupRequest {
                    kind: Kind::Broker,
                    sections: before,
                    links: None,
                    link: None,
                    history_days: None,
                    seal: match (new_keys, pass) {
                        (true, Some(p)) => SealWith::Passphrase(Zeroizing::new(p.to_vec())),
                        _ => SealWith::None,
                    },
                    label: super::backups::JobKind::PreRestore,
                    pinned: false,
                    remote: false,
                },
                &sub2,
            )?;
            info!(backup = %job.id, "what the restore replaces is backed up");
            ctl.stage_replace(&mut r, &c, &chosen2, accept, &sub2)
        })
        .await
        .map_err(BrokerRestoreError::Task)
        .and_then(|r| r);
        let plan = match staged {
            Ok(plan) => plan,
            Err(e) => {
                let _ = ctl.replacing(false);
                return Err(e);
            }
        };
        ctl.record(
            sub,
            AuditOp::RestoreApply,
            &plan.backup,
            Status::Ok,
            &format!(
                "replace; sections {}; keys replaced: {}; applied at the next start",
                format::section_names(&chosen),
                plan.strip_link_certs
            ),
        );
        warn!(by = sub, sections = %format::section_names(&chosen), "restore staged: the broker stops and applies it at the next start");
        // answer first, then stop: the supervisor starts the broker again
        let stop = ctl.clone();
        tokio::spawn(async move {
            tokio::time::sleep(Duration::from_millis(500)).await;
            stop.request_stop();
        });
        Ok((
            Value::Map(BTreeMap::from([
                ("mode".to_owned(), Value::from("replace")),
                ("sections".to_owned(), section_values(&chosen)),
                ("restart".to_owned(), Value::Bool(true)),
            ])),
            true,
        ))
    }

    /// `mode: add`: what does not exist yet, live.
    async fn restore_add(
        &self,
        path: &Path,
        chosen: &[SectionName],
        passphrase: Option<Zeroizing<Vec<u8>>>,
        accept: bool,
        sub: &str,
    ) -> Result<Value, BrokerRestoreError> {
        let ctl = &self.ctl;
        let has = |s: SectionName| chosen.contains(&s);
        let mut done: Vec<String> = Vec::new();
        let mut skipped: Vec<String> = Vec::new();
        // the whole file is checked once; the key goes on to the parts
        let (ctl2, path2, pass2) = (ctl.clone(), path.to_owned(), passphrase);
        // the key is derived once (Argon2id for a passphrase) and goes on
        // to every link of the file
        let (manifest, tree, key) = tokio::task::spawn_blocking(move || {
            let mut r = format::Reader::open(&path2, MAX_UPLOAD)?;
            let c = ctl2.check_broker_backup(&mut r, pass2.as_deref().map(|p| &p[..]))?;
            let tree = match c.manifest.section(SectionName::Storage) {
                Some(_) => Some(r.read("storage/tree.cbor")?),
                None => None,
            };
            Ok::<_, BrokerRestoreError>((c.manifest, tree, c.key))
        })
        .await
        .map_err(BrokerRestoreError::Task)??;
        if has(SectionName::Dataflows) {
            skipped.push(
                "dataflows: a flow is deployed with proofs of its deployer; restore them with \
                 mode replace"
                    .into(),
            );
        }
        if has(SectionName::Storage) {
            let store = ctl.storage().ok_or(BrokerRestoreError::StorageClosed)?;
            let changes = tree
                .and_then(|b| wyrm_core::codec::from_slice(&b).ok())
                .and_then(replication::parse_changes)
                .ok_or(BrokerRestoreError::NoStorageTree)?;
            let put: Vec<_> = changes
                .put
                .into_iter()
                .filter(|(p, _)| store.get(p).is_none())
                .collect();
            let n = put.len();
            if n > 0 {
                tokio::task::spawn_blocking(move || store.apply(put, Vec::new()))
                    .await
                    .map_err(BrokerRestoreError::Task)?
                    .map_err(BrokerRestoreError::StorageApply)?;
                // the storage link reads its store again
                ctl.schedule_reload();
            }
            done.push(format!("storage: {n} nodes added"));
        }
        if has(SectionName::Links) {
            let ids: Vec<String> = manifest
                .section(SectionName::Links)
                .map(|s| s.info.keys().cloned().collect())
                .unwrap_or_default();
            for id in ids {
                if ctl.registry().links.contains_key(&id) {
                    skipped.push(format!("link {id}: exists"));
                    continue;
                }
                let (ctl2, path2, key, id2) =
                    (ctl.clone(), path.to_owned(), key.clone(), id.clone());
                let read = tokio::task::spawn_blocking(move || {
                    let mut r = format::Reader::open(&path2, MAX_UPLOAD)?;
                    let m = r.manifest().clone();
                    // the package the link names, if the backup holds it
                    let settings = format!("links/{id2}/link.cbor");
                    let def: LinkDef = minicbor::decode(&r.read(&settings)?).map_err(|source| {
                        RestoreError::Settings {
                            path: settings,
                            source,
                        }
                    })?;
                    let package = def.driver.strip_prefix(packages::DRIVER_PREFIX);
                    let lay = LinkLayout::in_broker(&m, &id2, package);
                    ctl2.read_link_parts(&mut r, key.as_ref(), &lay)
                })
                .await
                .map_err(BrokerRestoreError::Task)?;
                let r = match read {
                    Ok(r) => r,
                    Err(e) => {
                        skipped.push(format!("link {id}: {e}"));
                        continue;
                    }
                };
                match self.install_restored(r, id.clone(), accept, sub).await {
                    Ok(m) => done.push(m),
                    Err(e) => skipped.push(format!("link {id}: {e}")),
                }
            }
        }
        ctl.record(
            sub,
            AuditOp::RestoreApply,
            &format!("{} {}", manifest.site, manifest.created),
            Status::Ok,
            &format!(
                "add; sections {}; {} done, {} skipped",
                format::section_names(chosen),
                done.len(),
                skipped.len()
            ),
        );
        Ok(Value::Map(BTreeMap::from([
            ("mode".to_owned(), Value::from("add")),
            ("done".to_owned(), strs(&done)),
            ("skipped".to_owned(), strs(&skipped)),
            ("restart".to_owned(), Value::Bool(false)),
        ])))
    }
}

/// `restore_check` and `restore_apply` of `sys/backups`.
pub(super) async fn declare(ctx: &LinkCtx) -> wyrm_link_sdk::Result<()> {
    ctx.declare_action(
        "backups",
        "restore_check",
        RestoreCheck::action()
            .display("Check a backup")
            .result(ActionResult::Type(TypeCode::Map))
            .timeout_ms(INSTALL_TIMEOUT_MS)
            .level(Perm::Config),
    )
    .await?;
    ctx.declare_action(
        "backups",
        "restore_apply",
        RestoreApply::action()
            .display("Restore")
            .result(ActionResult::Type(TypeCode::Map))
            .timeout_ms(INSTALL_TIMEOUT_MS)
            .level(Perm::Config),
    )
    .await
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Audit of #136: what `restore_apply` takes. A wrong `mode` or `sections` is
    /// refused when the arguments are decoded, before the upload is taken: the
    /// uploaded file stays as it is for the next call (it was taken, refused and
    /// given back before; the caller sees `invalid_parameter` in both cases).
    #[test]
    fn restore_apply_arguments() {
        let args = |kv: &[(&str, Value)]| {
            Value::Map(
                kv.iter()
                    .map(|(k, v)| ((*k).to_owned(), v.clone()))
                    .collect::<BTreeMap<_, _>>(),
            )
        };
        let sections = Value::Array(vec!["storage".into()]);
        let a = RestoreApply::decode(args(&[
            ("upload", "u1".into()),
            ("passphrase", "   ".into()),
            ("sections", sections.clone()),
            ("mode", "add".into()),
        ]))
        .unwrap();
        assert_eq!(a.file.upload, "u1");
        // a passphrase is never trimmed
        assert_eq!(
            a.file.passphrase.map(|p| p.expose().to_vec()),
            Some(b"   ".to_vec())
        );
        assert!(a.how.mode == RestoreMode::Add && !a.how.accept && !a.how.replace_keys);
        assert_eq!(a.how.sections, [SectionName::Storage]);
        let field = |kv: &[(&str, Value)]| {
            RestoreApply::decode(args(kv))
                .map(|_| ())
                .unwrap_err()
                .field
        };
        let up = ("upload", Value::from("u1"));
        assert_eq!(
            field(&[
                up.clone(),
                ("sections", sections.clone()),
                ("mode", "merge".into())
            ]),
            "mode"
        );
        assert_eq!(field(&[up.clone(), ("sections", sections.clone())]), "mode");
        assert_eq!(field(&[up.clone(), ("mode", "add".into())]), "sections");
        assert_eq!(
            field(&[
                up.clone(),
                ("sections", Value::Array(vec!["nope".into()])),
                ("mode", "add".into())
            ]),
            "sections"
        );
        assert_eq!(
            field(&[
                ("upload", "".into()),
                ("sections", sections),
                ("mode", "add".into())
            ]),
            "upload"
        );
        let c = RestoreCheck::decode(args(&[up, ("passphrase", "".into())])).unwrap();
        assert!(c.passphrase.is_none(), "an empty passphrase is none");
    }

    fn dir(name: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("wyrm-pending-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        d
    }

    fn put(root: &Path, rel: &str, data: &[u8]) {
        let p = root.join(rel);
        std::fs::create_dir_all(p.parent().unwrap()).unwrap();
        std::fs::write(p, data).unwrap();
    }

    /// What is there, and a staged restore of the registry and the keys.
    fn staged(name: &str) -> (PathBuf, PathBuf) {
        let d = dir(name);
        // what is there: a store, a key, certificates of the old CA
        put(&d, "state/wal.1", b"old");
        put(&d, "state/snapshot", b"old");
        put(&d, "state.key", b"old key");
        put(&d, "pki/ca.pem", b"old ca");
        put(&d, "pki/broker.pem", b"old leaf");
        put(&d, "links/a/a.pem", b"old cert");
        put(&d, "links/a/a.key", b"old key");
        put(&d, "links/a/token", b"tok");
        put(&d, "links/a/data/framework.tree", b"old tree");
        put(&d, "history/days/x.redb", b"untouched");
        let p = d.join(PENDING);
        put(&p, "data/state/wal.1", b"new");
        put(&p, "data/state.key", b"new key");
        put(&p, "data/pki/ca.pem", b"new ca");
        put(&p, "data/links/a/data/framework.tree", b"new tree");
        put(&p, "data/links/b/data/framework.tree", b"tree of b");
        let plan = Plan {
            by: "user:eve".into(),
            backup: "plant 2026-11-13T10:00:00Z".into(),
            sections: vec![SectionName::Control, SectionName::Keys],
            remove: vec!["pki".into(), "operators".into()],
            strip_link_certs: true,
            dirs: vec!["state".into(), "links/a/data".into(), "links/b/data".into()],
            files: vec!["state.key".into(), "pki/ca.pem".into()],
            components: Vec::new(),
        };
        std::fs::write(p.join(PLAN), serde_json::to_vec(&plan).unwrap()).unwrap();
        (d, p)
    }

    /// Every file under `d` with its content, the restore folders left out.
    fn tree_of(d: &Path) -> BTreeMap<String, Vec<u8>> {
        fn walk(root: &Path, dir: &Path, out: &mut BTreeMap<String, Vec<u8>>) {
            for e in std::fs::read_dir(dir).into_iter().flatten().flatten() {
                let rel = e.path().strip_prefix(root).unwrap().to_owned();
                let top = rel
                    .components()
                    .next()
                    .unwrap()
                    .as_os_str()
                    .to_string_lossy();
                if top.starts_with("restore.") {
                    continue;
                }
                if e.path().is_dir() {
                    walk(root, &e.path(), out);
                } else {
                    out.insert(
                        rel.to_string_lossy().into_owned(),
                        std::fs::read(e.path()).unwrap(),
                    );
                }
            }
        }
        let mut out = BTreeMap::new();
        walk(d, d, &mut out);
        out
    }

    #[test]
    fn a_pending_restore_is_applied_once_and_taken_up_again() {
        let (d, p) = staged("apply");
        // a staging that never finished is dropped
        put(&d, "restore.pending.tmp/data/state/wal.1", b"half");
        // a start that stopped after it set the old store aside and before
        // it moved the new one in
        let before = look_before(&d, &p, &read_plan(&p).unwrap());
        assert_eq!(
            before.moved,
            ["links/a/a.key", "links/a/a.pem", "pki"],
            "what is there of the removals"
        );
        assert_eq!(
            before.existed,
            ["state", "links/a/data", "state.key"],
            "pki/ca.pem goes with pki; links/b is new"
        );
        std::fs::write(p.join(BEFORE), serde_json::to_vec(&before).unwrap()).unwrap();
        move_to(&d.join("state"), &p.join("old/state")).unwrap();

        let applied = apply_pending(&d).unwrap().unwrap();
        assert_eq!(applied.by, "user:eve");
        assert_eq!(applied.sections, [SectionName::Control, SectionName::Keys]);
        let read = |rel: &str| std::fs::read(d.join(rel)).ok();
        assert_eq!(read("state/wal.1").as_deref(), Some(&b"new"[..]));
        assert_eq!(
            read("state/snapshot"),
            None,
            "the old snapshot went with its store"
        );
        assert_eq!(read("state.key").as_deref(), Some(&b"new key"[..]));
        assert_eq!(read("pki/ca.pem").as_deref(), Some(&b"new ca"[..]));
        assert_eq!(read("pki/broker.pem"), None, "a leaf of the old CA");
        assert_eq!(read("links/a/a.pem"), None, "a certificate of the old CA");
        assert_eq!(
            read("links/a/data/framework.tree").as_deref(),
            Some(&b"new tree"[..])
        );
        assert_eq!(read("links/a/token").as_deref(), Some(&b"tok"[..]));
        assert_eq!(
            read("history/days/x.redb").as_deref(),
            Some(&b"untouched"[..])
        );
        assert!(!d.join(PENDING_TMP).exists());
        // until the stores opened, what was replaced is kept; a start that
        // stopped before the commit applies again and changes nothing
        assert_eq!(std::fs::read(p.join("old/state/snapshot")).unwrap(), b"old");
        let now = tree_of(&d);
        assert!(apply_pending(&d).unwrap().is_some());
        assert_eq!(tree_of(&d), now);
        commit_pending(&d);
        assert!(!p.exists() && !d.join(DONE).exists());
        assert_eq!(tree_of(&d), now);
        assert_eq!(apply_pending(&d).unwrap(), None);
        assert_eq!(take_failure(&d), None);
    }

    /// Review of PR 72, item 6: a staged restore that cannot be applied, or
    /// whose stores do not open, never keeps the broker from starting. The
    /// state before it comes back whole, the folder is set aside with the
    /// reason, and the failure is reported once.
    #[test]
    fn a_restore_that_fails_leaves_the_state_before_it() {
        // 1. the stores do not open on what was put in place
        let (d, p) = staged("undo");
        let was = tree_of(&d);
        assert!(apply_pending(&d).unwrap().is_some());
        assert_ne!(tree_of(&d), was);
        undo_pending(&d, "registry: schema 99").unwrap();
        assert_eq!(tree_of(&d), was, "everything is as it was");
        assert!(!p.exists());
        let failed = d.join(FAILED);
        assert!(failed.join(PLAN).is_file());
        assert!(
            !failed.join("data").exists() && !failed.join(OLD).exists(),
            "no opened key stays in the folder"
        );
        // the next start runs on the old state and says what happened, once
        assert_eq!(apply_pending(&d).unwrap(), None);
        let f = take_failure(&d).unwrap();
        assert_eq!(
            (f.by.as_str(), f.error.as_str()),
            ("user:eve", "registry: schema 99")
        );
        assert_eq!(f.sections, [SectionName::Control, SectionName::Keys]);
        assert_eq!(take_failure(&d), None);

        // 2. a step of the plan fails in the middle (a staged store that is
        // not there to copy from): undone by the same start
        let (d, p) = staged("midway");
        let was = tree_of(&d);
        let mut plan = read_plan(&p).unwrap();
        plan.components = vec![("pkg".into(), "packages/pkg/1.0.0/app.wasm".into())];
        std::fs::write(p.join(PLAN), serde_json::to_vec(&plan).unwrap()).unwrap();
        assert_eq!(apply_pending(&d).unwrap(), None, "the broker starts");
        assert_eq!(tree_of(&d), was);
        let f = take_failure(&d).unwrap();
        assert!(f.error.contains("pkg.wasm"), "{}", f.error);

        // 3. an undo that a start stopped in goes on at the next start
        let (d, p) = staged("undo-again");
        let was = tree_of(&d);
        assert!(apply_pending(&d).unwrap().is_some());
        std::fs::write(p.join(UNDO), b"power").unwrap();
        // half undone: one store is back already
        crate::nofollow::remove_any(&d.join("state")).unwrap();
        move_to(&p.join("old/state"), &d.join("state")).unwrap();
        assert_eq!(apply_pending(&d).unwrap(), None);
        assert_eq!(tree_of(&d), was);
        assert_eq!(take_failure(&d).unwrap().error, "power");

        // 4. a plan that does not read: nothing was changed, the folder is
        // set aside and the broker starts
        let (d, p) = staged("bad-plan");
        let was = tree_of(&d);
        std::fs::write(p.join(PLAN), b"{ not json").unwrap();
        assert_eq!(apply_pending(&d).unwrap(), None);
        assert_eq!(tree_of(&d), was);
        assert!(!p.exists() && d.join(FAILED).is_dir());
        assert!(take_failure(&d).unwrap().error.contains(PLAN));
        // a plan that names a path outside the data directory
        let (d, p) = staged("bad-path");
        let was = tree_of(&d);
        let mut plan = read_plan(&p).unwrap();
        plan.dirs.push("../outside".into());
        std::fs::write(p.join(PLAN), serde_json::to_vec(&plan).unwrap()).unwrap();
        assert_eq!(apply_pending(&d).unwrap(), None);
        assert_eq!(tree_of(&d), was);

        // 5. link secrets that do not read
        let (d, p) = staged("bad-secrets");
        let was = tree_of(&d);
        std::fs::write(p.join(LINK_SECRETS), b"\xff\xff").unwrap();
        assert_eq!(apply_pending(&d).unwrap(), None);
        let mut now = tree_of(&d);
        // the secret key a first open of the store makes is no state
        now.remove("secrets.key");
        assert_eq!(now, was);
        assert!(take_failure(&d).unwrap().error.contains("link secrets"));
    }

    #[test]
    fn only_defined_paths_have_a_place() {
        for ok in [
            "keys/pki/ca.pem",
            "keys/pki/ca.key",
            "keys/state.key",
            "keys/secrets.key",
            "keys/gateway/gateway.key",
            "keys/flows/flow.key",
            "keys/secrets.bin",
            "keys/links/plc1/token",
            "control/state/wal.00000000000000000001.wyw",
            "control/audit/snapshot",
            "dataflows/artifacts/ab/cdef.wasm",
            "storage/tree.cbor",
            "storage/export.json",
            "history/index.redb",
            "history/days/2026-11-13.redb",
            "links/plc1/link.cbor",
            "links/plc1/secrets",
            "links/plc1/files/framework.tree",
            "links/plc1/files/a/b/c",
            "packages/mockpkg/files/wyrm-link.json",
            "packages/mockpkg/files/bin/run",
            "config/wyrmd.json",
        ] {
            assert!(place_of(ok).is_ok(), "{ok}");
        }
        assert_eq!(
            place_of("keys/links/plc1/token"),
            Ok(Place::Key("links/plc1/token".into()))
        );
        for bad in [
            // anything under keys/ that is no key file
            "keys/wyrmd.json5",
            "keys/restore.pending/plan.json",
            "keys/packages/mockpkg/1.0.0/bin/run",
            "keys/links/plc1/data/framework.tree",
            "keys/links/plc1/token/x",
            "keys/links/../token",
            "keys/links/.hidden/token",
            "keys/links/admin/token",
            "keys/pki/broker.key",
            "keys/pki/ca.pem/x",
            // other sections: only what they define
            "control/state/sub/wal",
            "control/nostore/wal",
            "control/../state.key",
            "dataflows/flow.key",
            "dataflows/artifacts",
            "dataflows/artifacts/../../state.key",
            "storage/storage.redb",
            "history/days/../../state.key",
            "history/days/2026-11-13.txt",
            "history/days/a/b.redb",
            "links/plc1/token",
            "links/plc1/data/x",
            "links/../files/x",
            "links/plc1/files",
            "links/plc1/files/a/../../../x",
            "packages/.wasm/files/x.wasm",
            "packages/mockpkg/1.0.0/bin/run",
            "config/wyrmd.json5",
            "other/x",
        ] {
            let e = place_of(bad).expect_err(bad);
            assert_eq!(e.path, bad);
            assert!(e.to_string().contains("no section defines"), "{bad}: {e}");
        }
    }

    /// Findings 1 and 4: the gates of `mode: replace`.
    #[test]
    fn replace_gates_hold_for_every_keys_restore() {
        let differ = vec!["secrets.bin".to_owned()];
        let ca = vec![CA_FILE.to_owned(), "state.key".to_owned()];
        let g = |remote, keys, differ: &[String], export_secrets, passphrase, replace_keys| {
            replace_gates(&Gates {
                remote,
                keys,
                differ,
                export_secrets,
                passphrase,
                replace_keys,
            })
        };
        // a caller from an upstream: never, with or without keys
        let e = g(true, false, &[], true, true, true).unwrap_err();
        assert_eq!(e, GateError::Remote);
        assert!(e.to_string().contains("upstream"), "{e}");
        assert_eq!(g(true, true, &[], true, true, true), Err(GateError::Remote));
        // without keys: no gate for a caller of this site
        assert!(g(false, false, &[], false, false, false).is_ok());
        // keys byte for byte this broker's: still the host's switch and the
        // passphrase, no replace_keys
        let e = g(false, true, &[], false, true, true).unwrap_err();
        assert_eq!(e, GateError::ExportOff);
        assert!(e.to_string().contains("export_secrets"), "{e}");
        let e = g(false, true, &[], true, false, true).unwrap_err();
        assert_eq!(e, GateError::NoPassphrase);
        assert!(e.to_string().contains("passphrase"), "{e}");
        assert!(g(false, true, &[], true, true, false).is_ok());
        // the same CA, another key file: replace_keys, and it is named
        let e = g(false, true, &differ, true, true, false).unwrap_err();
        assert!(matches!(&e, GateError::KeysDiffer { differ: d } if *d == differ));
        let e = e.to_string();
        assert!(
            e.contains("replace_keys") && e.contains("secrets.bin"),
            "{e}"
        );
        assert!(g(false, true, &differ, false, true, true).is_err());
        assert!(g(false, true, &differ, true, false, true).is_err());
        assert!(g(false, true, &differ, true, true, true).is_ok());
        // another CA
        let e = g(false, true, &ca, true, true, false)
            .unwrap_err()
            .to_string();
        assert!(e.contains("another CA"), "{e}");
        assert!(g(false, true, &ca, true, true, true).is_ok());
    }

    const PASS: &[u8] = b"correct horse battery";

    fn exporting(name: &str) -> Arc<Control> {
        super::super::tests::control_tweaked(name, |c| c.backups.export_secrets = true)
    }

    /// A broker backup of site `s` under [`PASS`] made of `files`
    /// (`path`, content, sealed), each in the section its path names.
    fn crafted(dir: &Path, files: &[(&str, &[u8], bool)]) -> PathBuf {
        crafted_saying(dir, files, &[])
    }

    /// [`crafted`] whose `control` section says the heads `heads` (store,
    /// last LSN) in its `info`, as a broker's backup does.
    fn crafted_saying(dir: &Path, files: &[(&str, &[u8], bool)], heads: &[(&str, u64)]) -> PathBuf {
        let (sealed, key) = format::Sealing::Passphrase(PASS).start().unwrap();
        let key = key.unwrap();
        let src = dir.join("crafted-src");
        std::fs::create_dir_all(&src).unwrap();
        let mut sections: Vec<format::StagedSection> = Vec::new();
        for (i, (path, data, seal)) in files.iter().enumerate() {
            let source = src.join(i.to_string());
            let stored = if *seal {
                format::seal_bytes(&key, path, data).unwrap()
            } else {
                data.to_vec()
            };
            std::fs::write(&source, stored).unwrap();
            let name = SectionName::from_name(path.split('/').next().unwrap()).unwrap();
            let staged = format::Staged {
                path: (*path).to_owned(),
                source,
                sealed: *seal,
                exec: false,
            };
            match sections.iter_mut().find(|s| s.name == name) {
                Some(s) => s.files.push(staged),
                None => sections.push(format::StagedSection {
                    name,
                    info: Default::default(),
                    files: vec![staged],
                }),
            }
        }
        if let Some(s) = sections.iter_mut().find(|s| s.name == SectionName::Control) {
            for (store, lsn) in heads {
                s.info.insert((*store).to_owned(), (*lsn).into());
            }
        }
        let head = format::Head {
            kind: Kind::Broker,
            site: "s".into(),
            broker: "0.1.0".into(),
            created: "2026-11-13T10:00:00Z".into(),
            schemas: BTreeMap::new(),
            sealed,
            link: None,
        };
        let out = dir.join("crafted.wyrm-backup");
        format::write(&out, head, sections, Some(&key), |_, _| {}).unwrap();
        out
    }

    /// Finding 2, end to end in the reader: a backup that lists a file
    /// under `keys/` that is no key is refused whole, by the check and so by
    /// every mode; nothing of it reaches the `data_dir`.
    #[test]
    fn a_backup_with_a_stray_file_under_keys_is_refused_whole() {
        let ctl = exporting("restore-stray");
        let d = ctl.cfg.data_dir.clone();
        let ca = std::fs::read(d.join("pki/ca.pem")).unwrap();
        for stray in [
            "keys/links/a/data/framework.tree",
            "keys/restore.pending/plan.json",
            "keys/wyrmd.json5",
        ] {
            let path = crafted(
                &d,
                &[("keys/pki/ca.pem", &ca, true), (stray, b"planted", true)],
            );
            let mut r = format::Reader::open(&path, MAX_UPLOAD).unwrap();
            let e = ctl
                .check_broker_backup(&mut r, Some(PASS))
                .err()
                .expect(stray);
            assert!(
                matches!(&e, BrokerRestoreError::Place(p) if p.path == stray),
                "{e:?}"
            );
            assert!(e.to_string().contains("no section defines"), "{stray}: {e}");
        }
        assert!(!d.join("links/a").exists() && !d.join(PENDING).exists());
        assert!(!d.join(PENDING_TMP).exists() && !d.join("wyrmd.json5").exists());
    }

    /// A broker backup of `sections`, not sealed, as the broker makes it.
    fn made(ctl: &Control, name: &str, sections: &[SectionName]) -> PathBuf {
        let out = ctl.cfg.data_dir.join(name);
        let req = BackupRequest {
            kind: Kind::Broker,
            sections: sections.to_vec(),
            links: None,
            link: None,
            history_days: None,
            seal: SealWith::None,
            label: super::super::backups::JobKind::PreRestore,
            pinned: false,
            remote: false,
        };
        ctl.write_backup(&req, &out, &|_, _| {}).unwrap();
        out
    }

    /// Issue #198 item 2: a `control` section whose files are no WAL segments
    /// (`control/state/wal.1`) passed the check and the staging, no segment
    /// was seen, and `replace` put an EMPTY control state in place at the next
    /// start. It is refused whole now, by the check and so by every mode, and
    /// so is a store that opens with other records than the backup says.
    #[test]
    fn a_control_section_that_would_empty_the_control_plane_is_refused() {
        let ctl = exporting("restore-empty-control");
        let d = ctl.cfg.data_dir.clone();
        let segment = "control/state/wal.00000000000000000001.wyw";
        let check = |path: &Path| {
            let mut r = format::Reader::open(path, MAX_UPLOAD).unwrap();
            ctl.check_broker_backup(&mut r, Some(PASS)).map(|_| ())
        };
        let refused = |path: &Path, want: ControlError| {
            let e = check(path).unwrap_err();
            assert!(
                matches!(&e, BrokerRestoreError::Control(c) if *c == want),
                "{e:?}"
            );
            assert_eq!(e.status(), Status::InvalidParameter);
            assert!(!d.join(PENDING).exists() && !d.join(PENDING_TMP).exists());
        };
        // files that are no segments: the store would open without a record
        for stray in [
            "control/state/wal.1",
            "control/state/wal.00000000000000000001",
            "control/state/snapshot.00000000000000000001.wys",
            "control/users/CURRENT",
        ] {
            let path = crafted_saying(
                &d,
                &[(segment, b"", false), (stray, b"x", false)],
                &[("state", 0)],
            );
            refused(&path, ControlError::NotSegment { path: stray.into() });
        }
        // the example of the issue: nothing but a file that is no segment
        let path = crafted(&d, &[("control/state/wal.1", b"records", false)]);
        refused(
            &path,
            ControlError::NotSegment {
                path: "control/state/wal.1".into(),
            },
        );
        // a control section without the registry
        let path = crafted_saying(
            &d,
            &[("control/users/wal.00000000000000000001.wyw", b"", false)],
            &[("users", 0)],
        );
        refused(&path, ControlError::NoRegistry);
        // an empty segment where the backup says the registry has records,
        // and one that does not say
        let path = crafted_saying(&d, &[(segment, b"", false)], &[("state", 7)]);
        refused(
            &path,
            ControlError::Head {
                store: "state",
                said: 7,
                found: 0,
            },
        );
        let path = crafted(&d, &[(segment, b"", false)]);
        refused(&path, ControlError::NoHead { store: "state" });

        // The staging holds the same for every store it puts in place, with
        // the key that will be there: the registry is as it says, the users
        // store is short of the records the backup says it holds.
        let path = crafted_saying(
            &d,
            &[
                (segment, b"", false),
                ("control/users/wal.00000000000000000001.wyw", b"", false),
            ],
            &[("state", 0), ("users", 3)],
        );
        let mut r = format::Reader::open(&path, MAX_UPLOAD).unwrap();
        let c = ctl.check_broker_backup(&mut r, Some(PASS)).unwrap();
        let e = ctl
            .stage_replace(&mut r, &c, &[SectionName::Control], false, "user:a")
            .unwrap_err();
        let want = ControlError::Head {
            store: "users",
            said: 3,
            found: 0,
        };
        assert!(
            matches!(&e, BrokerRestoreError::Control(c) if *c == want),
            "{e:?}"
        );
    }

    /// What a broker makes still restores, also when its control plane is
    /// empty. A broker backed up before anything was installed has a
    /// registry without a record: `Control::stage_control` writes one segment
    /// of 0 bytes for it and says head 0. (A store never comes as a snapshot
    /// alone: the WAL is never deleted and a backup copies records, not the
    /// snapshot, `wyrm_state::replicate::copy_to`.) So "head 0" is no reason
    /// to refuse; "other than the backup says" is.
    #[test]
    fn a_backup_of_an_empty_control_plane_is_restored() {
        let ctl = exporting("restore-fresh-control");
        let d = ctl.cfg.data_dir.clone();
        let staged = |name: &str, lsn: u64| {
            let path = made(&ctl, name, &[SectionName::Control]);
            let mut r = format::Reader::open(&path, MAX_UPLOAD).unwrap();
            let section = r.manifest().section(SectionName::Control).unwrap().clone();
            assert_eq!(section.info.get("state"), Some(&lsn.into()), "{name}");
            let files: Vec<&str> = section.files.iter().map(|f| f.path.as_str()).collect();
            assert!(
                files.contains(&"control/state/wal.00000000000000000001.wyw"),
                "{files:?}"
            );
            assert!(
                files.iter().all(
                    |f| wyrm_state::segment_first_lsn(f.rsplit('/').next().unwrap()).is_some()
                ),
                "segments alone: {files:?}"
            );
            let c = ctl.check_broker_backup(&mut r, None).unwrap();
            assert!(c.wal_opens_here && c.problems.is_empty(), "{name}");
            let plan = ctl
                .stage_replace(&mut r, &c, &[SectionName::Control], false, "user:a")
                .unwrap();
            assert!(plan.dirs.contains(&"state".to_owned()), "{name}");
            std::fs::remove_dir_all(d.join(PENDING)).unwrap();
        };
        // right after the first start: no record in the registry
        assert_eq!(ctl.registry().links.len(), 0);
        staged("fresh.wyrm-backup", 0);
        // and with records
        ctl.apply(Op::Install(LinkDef {
            id: "a".into(),
            driver: "mockdev".into(),
            mode: Mode::Embedded,
            params: Vec::new(),
            token_hash: String::new(),
            rev: 1,
            origin: Origin::Runtime,
            created: 1,
            display: None,
            granted: None,
            log_level: None,
            grants: Vec::new(),
        }))
        .unwrap();
        staged("one.wyrm-backup", 1);
    }

    /// Finding 1: keys of the same CA that differ in another file are told
    /// apart from this broker's, named by the check, and staged only from
    /// the closed list of key files.
    #[test]
    fn keys_of_the_same_ca_that_differ_are_named() {
        let ctl = exporting("restore-differ");
        let d = ctl.cfg.data_dir.clone();
        let read = |rel: &str| std::fs::read(d.join(rel)).unwrap();
        let own = [
            ("keys/pki/ca.pem", read("pki/ca.pem"), true),
            ("keys/state.key", read("state.key"), true),
        ];
        let same: Vec<(&str, &[u8], bool)> = own.iter().map(|(p, b, s)| (*p, &b[..], *s)).collect();
        let path = crafted(&d, &same);
        let mut r = format::Reader::open(&path, MAX_UPLOAD).unwrap();
        let c = ctl.check_broker_backup(&mut r, Some(PASS)).unwrap();
        assert!(!c.keys_other && c.keys_differ.is_empty());
        let Value::Map(report) = ctl.check_report(&c, 0) else {
            panic!("a map")
        };
        assert_eq!(report.get("keys"), Some(&Value::from("same")));

        // the same CA, another gateway key and another store of secrets
        let mut other = same.clone();
        other.push(("keys/gateway/gateway.key", b"another gateway key", true));
        other.push(("keys/secrets.bin", b"another store", true));
        let path = crafted(&d, &other);
        let mut r = format::Reader::open(&path, MAX_UPLOAD).unwrap();
        let c = ctl.check_broker_backup(&mut r, Some(PASS)).unwrap();
        assert!(!c.keys_other, "the CA is this broker's");
        assert_eq!(c.keys_differ, ["gateway/gateway.key", "secrets.bin"]);
        let Value::Map(report) = ctl.check_report(&c, 0) else {
            panic!("a map")
        };
        assert_eq!(report.get("keys"), Some(&Value::from("differ")));
        assert_eq!(report.get("keys_differ"), Some(&strs(&c.keys_differ)));
        // what restore_apply asks the gates with
        let gates = |export_secrets, passphrase, replace_keys| {
            replace_gates(&Gates {
                remote: false,
                keys: true,
                differ: &c.keys_differ,
                export_secrets,
                passphrase,
                replace_keys,
            })
        };
        assert!(gates(true, true, false).is_err(), "needs replace_keys");
        assert!(gates(false, true, true).is_err(), "needs export_secrets");
        assert!(gates(true, false, true).is_err(), "needs the passphrase");
        assert!(gates(true, true, true).is_ok());
        // staged: exactly the key files, where the list says
        let plan = ctl
            .stage_replace(&mut r, &c, &[SectionName::Keys], false, "user:a")
            .unwrap();
        assert_eq!(
            plan.files,
            [
                "pki/ca.pem",
                "state.key",
                "gateway/gateway.key",
                "secrets.bin"
            ]
        );
        assert!(plan.remove.is_empty() && !plan.strip_link_certs);
        assert_eq!(
            std::fs::read(d.join(PENDING).join("data/gateway/gateway.key")).unwrap(),
            b"another gateway key"
        );
    }

    /// Finding 3: a secret a broker makes for a link's identity is not
    /// taken from a backup by `replace`, neither at staging nor at the start
    /// that applies it.
    #[test]
    fn broker_made_secrets_are_not_restored_by_replace() {
        let ctl = exporting("restore-made");
        let d = ctl.cfg.data_dir.clone();
        let def = LinkDef {
            id: "a".into(),
            driver: "mockdev".into(),
            mode: Mode::Embedded,
            params: Vec::new(),
            token_hash: String::new(),
            rev: 1,
            origin: Origin::Runtime,
            created: 1,
            display: None,
            granted: None,
            log_level: None,
            grants: Vec::new(),
        };
        ctl.apply(Op::Install(def.clone())).unwrap();
        let secrets = Value::Map(BTreeMap::from([
            (
                wyrm_link_sdk::REQUESTER_KEY.to_owned(),
                Value::Bytes(b"a key of another broker".to_vec()),
            ),
            ("agent_key".to_owned(), Value::Bytes(b"its agent".to_vec())),
            ("password".to_owned(), Value::Bytes(b"pw-123456".to_vec())),
        ]));
        let secrets = wyrm_core::codec::to_vec(&secrets).unwrap();
        let path = crafted(
            &d,
            &[
                ("links/a/link.cbor", &minicbor::to_vec(&def).unwrap(), false),
                ("links/a/secrets", &secrets, true),
                ("links/a/files/framework.tree", b"tree", true),
            ],
        );
        let mut r = format::Reader::open(&path, MAX_UPLOAD).unwrap();
        let c = ctl.check_broker_backup(&mut r, Some(PASS)).unwrap();
        ctl.stage_replace(&mut r, &c, &[SectionName::Links], false, "user:a")
            .unwrap();
        let staged = std::fs::read(d.join(PENDING).join(LINK_SECRETS)).unwrap();
        let Value::Map(links) = wyrm_core::codec::from_slice::<Value>(&staged).unwrap() else {
            panic!("a map")
        };
        let Some(Value::Map(a)) = links.get("a") else {
            panic!("link a")
        };
        assert_eq!(a.keys().collect::<Vec<_>>(), ["password"]);

        // the start: a plan file that names one all the same is filtered
        let all = Value::Map(BTreeMap::from([(
            "a".to_owned(),
            wyrm_core::codec::from_slice::<Value>(&secrets).unwrap(),
        )]));
        std::fs::write(
            d.join(PENDING).join(LINK_SECRETS),
            wyrm_core::codec::to_vec(&all).unwrap(),
        )
        .unwrap();
        drop(ctl);
        apply_pending(&d).unwrap().unwrap();
        let store = crate::secrets::SecretStore::open(&d).unwrap();
        assert_eq!(store.names("a"), ["password"]);
        assert_eq!(&store.for_link("a")["password"][..], b"pw-123456");
        assert_eq!(
            std::fs::read(d.join("links/a/data/framework.tree")).unwrap(),
            b"tree"
        );
    }

    /// Finding 4: a package that `replace` brings passes the install
    /// validator, and what it asks for needs `accept`, as `install_backup`.
    #[test]
    fn packages_of_a_replace_need_accept_and_pass_the_validator() {
        let ctl = exporting("restore-pkg");
        let d = ctl.cfg.data_dir.clone();
        let manifest = |entry: &str| {
            format!(
                r#"{{ "name": "demo", "version": "1.0.0", "wyrm_link": {}, "kind": "process",
                     "entries": {{ "{}": "{entry}" }},
                     "requester": [{{"path": "wy/{{site}}/downstream/plc1", "level": "write"}}] }}"#,
                wyrm_link_sdk::LINK_PROTOCOL,
                packages::platform()
            )
            .into_bytes()
        };
        let stage = |m: &[u8], accept: bool| {
            let path = crafted(
                &d,
                &[
                    ("packages/demo/files/wyrm-link.json", m, false),
                    ("packages/demo/files/bin/run", b"#!/bin/sh\n", false),
                ],
            );
            let mut r = format::Reader::open(&path, MAX_UPLOAD).unwrap();
            let c = ctl.check_broker_backup(&mut r, Some(PASS)).unwrap();
            ctl.stage_replace(&mut r, &c, &[SectionName::Packages], accept, "user:a")
        };
        // an entry outside the package: the validator of every install
        let e = stage(&manifest("../../../../bin/sh"), true).unwrap_err();
        assert!(
            matches!(e, BrokerRestoreError::PackageInvalid { .. }),
            "{e:?}"
        );
        assert!(e.to_string().contains("package demo of the backup"), "{e}");
        // its grant is shown and nothing is staged without accept
        let e = stage(&manifest("bin/run"), false).unwrap_err();
        assert!(matches!(e, BrokerRestoreError::Asks { .. }), "{e:?}");
        let e = e.to_string();
        assert!(
            e.contains("write on wy/{site}/downstream/plc1") && e.contains("Accept"),
            "{e}"
        );
        assert!(!d.join(PENDING).exists() && !d.join(PENDING_TMP).exists());
        let plan = stage(&manifest("bin/run"), true).unwrap();
        assert_eq!(plan.dirs, ["packages/demo/1.0.0"]);
        assert!(d
            .join(PENDING)
            .join("data/packages/demo/1.0.0/bin/run")
            .is_file());
    }

    /// Review 2026-11-16: a plan's sections are typed. One written as text then reads the
    /// same; a section this build does not know refuses the plan before anything is
    /// touched (what it restores would be read wrong), and the broker starts as it was.
    #[test]
    fn a_plan_with_an_unknown_section_is_not_applied() {
        let mut v = serde_json::to_value(Plan {
            sections: vec![SectionName::Control, SectionName::Keys],
            ..Default::default()
        })
        .unwrap();
        assert_eq!(v["sections"], serde_json::json!(["control", "keys"]));
        v["sections"] = serde_json::json!(["control", "secrets"]);
        let d = dir("unknown-section");
        let p = d.join(PENDING);
        put(&p, "data/x", b"x");
        std::fs::write(p.join(PLAN), serde_json::to_vec(&v).unwrap()).unwrap();
        let e = read_plan(&p).unwrap_err();
        assert!(matches!(e, PlanError::Json(_)), "{e:?}");
        assert!(e.to_string().contains("backup section"));
        assert_eq!(apply_pending(&d).unwrap(), None);
        assert!(!p.exists() && d.join(FAILED).is_dir());
        assert!(!d.join("x").exists());
    }

    #[test]
    fn a_plan_cannot_reach_outside_the_data_dir() {
        for bad in ["../outside", "/etc/passwd", "state/../../x"] {
            for remove in [false, true] {
                let d = dir("escape");
                let p = d.join(PENDING);
                put(&p, "data/x", b"x");
                let plan = match remove {
                    false => Plan {
                        dirs: vec![bad.into()],
                        ..Default::default()
                    },
                    true => Plan {
                        remove: vec![bad.into()],
                        ..Default::default()
                    },
                };
                std::fs::write(p.join(PLAN), serde_json::to_vec(&plan).unwrap()).unwrap();
                // refused before anything is touched; the broker starts
                assert_eq!(apply_pending(&d).unwrap(), None, "{bad}");
                assert!(!p.exists() && d.join(FAILED).is_dir(), "{bad}");
                assert!(!d.join("x").exists(), "{bad}");
            }
        }
    }

    fn said(e: &dyn std::fmt::Display, text: &str) {
        assert_eq!(e.to_string(), text);
    }

    fn cancelled() -> tokio::task::JoinError {
        tokio::runtime::Builder::new_current_thread()
            .build()
            .unwrap()
            .block_on(async {
                let task = tokio::spawn(std::future::pending::<()>());
                task.abort();
                task.await.unwrap_err()
            })
    }

    /// One of every variant of [`BrokerRestoreError`], with the status it has
    /// to a caller.
    fn every_refusal() -> Vec<(BrokerRestoreError, Status)> {
        use BrokerRestoreError as B;
        use Status::{
            Busy, InternalError as Internal, InvalidParameter as Invalid,
            PermissionDenied as Denied, ResourceExhausted as Exhausted,
        };
        let io = || std::io::Error::other("no");
        let file = |kind: std::io::ErrorKind| {
            BackupError::File(FileError::new(
                Path::new("/d/backups/s.wyrm-backup"),
                std::io::Error::new(kind, "no"),
            ))
        };
        let boxed = || -> secret::Error { "no".into() };
        let codec = || wyrm_core::codec::CodecError::Encode("no".into());
        let json = || serde_json::from_str::<u8>("x").unwrap_err();
        let segment = || wyrm_core::keyspace::validate_segment("").unwrap_err();
        let busy = |m: &str| LinkError::new(Status::Busy, m);
        vec![
            (B::Restore(RestoreError::BrokerBackup), Invalid),
            (
                B::Restore(RestoreError::Key(format::KeyError::WrongPassphrase)),
                Invalid,
            ),
            (B::LinkBackup, Invalid),
            (
                B::Place(NoPlace {
                    path: "keys/x".into(),
                }),
                Invalid,
            ),
            (B::NoCa, Invalid),
            (B::KeyLoad(boxed()), Invalid),
            (
                B::Section {
                    section: SectionName::Keys,
                    mode: RestoreMode::Add,
                },
                Invalid,
            ),
            (B::NoSections, Invalid),
            (
                B::Problem(Problem::OtherSite {
                    backup: "plant".into(),
                    here: "s".into(),
                }),
                Invalid,
            ),
            (
                B::Problem(Problem::NewerSchema {
                    store: "registry".into(),
                    backup: 99,
                    here: 20,
                }),
                Invalid,
            ),
            (B::MissingSection(SectionName::History), Invalid),
            (B::Anchored, Invalid),
            // refused by the caller's rights, not by an argument
            (B::Gate(GateError::Remote), Denied),
            (B::Gate(GateError::ExportOff), Denied),
            (B::Gate(GateError::NoPassphrase), Invalid),
            (
                B::Gate(GateError::KeysDiffer {
                    differ: vec!["state.key".into()],
                }),
                Invalid,
            ),
            (
                B::Control(ControlError::NotSegment {
                    path: "control/state/wal.1".into(),
                }),
                Invalid,
            ),
            (B::Control(ControlError::NoRegistry), Invalid),
            (B::Control(ControlError::NoHead { store: "state" }), Invalid),
            (
                B::Control(ControlError::Head {
                    store: "state",
                    said: 7,
                    found: 0,
                }),
                Invalid,
            ),
            (B::ControlKeys, Invalid),
            // the two refusals of `Control::replacing`
            (
                B::Busy(busy("a restore is being staged; one at a time")),
                Busy,
            ),
            (
                B::Busy(busy(
                    "a package or a link is being installed, updated, rolled back or restored; \
                     try again when it ends",
                )),
                Busy,
            ),
            (B::PreBackup(NowError::Refused(StartError::Running)), Busy),
            (
                B::PreBackup(NowError::Refused(StartError::LinkBusy(busy(
                    "link plc is being restored; try again when it ends",
                )))),
                Busy,
            ),
            (
                B::PreBackup(NowError::Refused(StartError::Request(
                    super::super::backups::RequestError::NoConfig,
                ))),
                Invalid,
            ),
            (
                B::PreBackup(NowError::Refused(StartError::DiskFull {
                    want: 2.0,
                    free: 1.0,
                })),
                Exhausted,
            ),
            // the disk filled up while the backup was written
            (
                B::PreBackup(NowError::Failed(file(std::io::ErrorKind::StorageFull))),
                Exhausted,
            ),
            (
                B::PreBackup(NowError::Failed(file(std::io::ErrorKind::QuotaExceeded))),
                Exhausted,
            ),
            // any other I/O error of the backup
            (
                B::PreBackup(NowError::Failed(file(std::io::ErrorKind::PermissionDenied))),
                Internal,
            ),
            (B::PreBackup(NowError::Failed(file(io().kind()))), Internal),
            // a job that failed without an I/O error
            (
                B::PreBackup(NowError::Failed(BackupError::StorageClosed)),
                Invalid,
            ),
            (B::PreBackup(NowError::Gone), Internal),
            (B::Task(cancelled()), Invalid),
            (
                B::WalKeys {
                    store: "state",
                    source: StateError::Rejected("no".into()),
                },
                Invalid,
            ),
            (
                B::History(wyrm_history::store::Error::Db("no".into())),
                Invalid,
            ),
            (B::Storage(StorageError::TreeShape), Invalid),
            (B::LinkSecrets(LinkSecretsError::NotMap), Invalid),
            (B::SecretsEncode(codec()), Invalid),
            (
                B::PackageInvalid {
                    name: "demo".into(),
                    why: "no".into(),
                },
                Invalid,
            ),
            (
                B::PackageName {
                    dir: "demo".into(),
                    holds: "other".into(),
                },
                Invalid,
            ),
            (B::PackageVersion(segment()), Invalid),
            (
                B::Asks {
                    asks: vec!["package demo: network a:1".into()],
                },
                Invalid,
            ),
            (B::SecretStore(boxed()), Invalid),
            (B::PlanEncode(json()), Invalid),
            (B::Plan(PlanError::Json(json())), Invalid),
            (
                B::Stays {
                    error: Box::new(B::NoCa),
                    path: PathBuf::from("/d/restore.pending.tmp"),
                    source: io(),
                },
                Invalid,
            ),
            (B::StorageClosed, Invalid),
            (B::NoStorageTree, Invalid),
            (B::StorageApply(wyrm_storage::Error::Io(io())), Invalid),
        ]
    }

    /// The status of every refusal of `restore_check` and `restore_apply` is the
    /// one the handler gave before the refusals had a type. It told `busy` by
    /// the words of the message then (`by_words`, the rule as it was); the type
    /// tells it now, with the same answer for every refusal the broker makes,
    /// but for two kinds. The two gates closed by the caller's rights differ
    /// from the old rule on purpose (owner decision 2026-11-24, issue #198
    /// item 3): `permission_denied` where the old rule said
    /// `invalid_parameter`. A `pre-restore` backup that the disk had no room
    /// for or that failed on an I/O error (owner decision 2026-11-27) is
    /// `resource_exhausted` or `internal_error`; so is a job whose record is
    /// gone.
    #[test]
    fn a_broker_restore_is_refused_with_its_status() {
        let by_words = |m: &str| {
            if m.contains("try again") || m.contains("one at a time") {
                Status::Busy
            } else {
                Status::InvalidParameter
            }
        };
        let by_rights = |e: &BrokerRestoreError| {
            matches!(
                e,
                BrokerRestoreError::Gate(GateError::Remote | GateError::ExportOff)
            )
        };
        let no_pre_backup =
            |s: Status| matches!(s, Status::ResourceExhausted | Status::InternalError);
        let (mut denied, mut not_backed_up) = (0, 0);
        for (e, status) in every_refusal() {
            let text = e.to_string();
            assert_eq!(e.status(), status, "{text}");
            // a refusal is never answered below 0x20 (docs/links.md §1)
            assert!(status.is_error(), "{text}");
            if by_rights(&e) {
                denied += 1;
                assert_eq!(status, Status::PermissionDenied, "{text}");
                assert_eq!(by_words(&text), Status::InvalidParameter, "{text}");
            } else if no_pre_backup(status) {
                not_backed_up += 1;
                assert!(matches!(e, BrokerRestoreError::PreBackup(_)), "{text}");
                assert_eq!(by_words(&text), Status::InvalidParameter, "{text}");
            } else {
                assert_ne!(status, Status::PermissionDenied, "{text}");
                assert_eq!(by_words(&text), status, "{text}");
            }
            let l = LinkError::from(e);
            assert_eq!((l.status, l.message.as_str()), (status, text.as_str()));
        }
        assert_eq!(denied, 2, "exactly the two gates of rights");
        assert_eq!(not_backed_up, 6, "disk full, I/O, gone");
        // a missing passphrase and keys that differ are wrong arguments
        for e in [
            GateError::NoPassphrase,
            GateError::KeysDiffer {
                differ: vec!["state.key".into()],
            },
        ] {
            assert_eq!(
                BrokerRestoreError::Gate(e).status(),
                Status::InvalidParameter
            );
        }
        // What a backup says cannot make a refusal `busy` any more: a path, a
        // package's manifest or a job's error with those words in it.
        for e in [
            BrokerRestoreError::Place(NoPlace {
                path: "keys/try again".into(),
            }),
            BrokerRestoreError::Asks {
                asks: vec!["package demo: network one at a time".into()],
            },
            BrokerRestoreError::PreBackup(NowError::Failed(BackupError::LinkData {
                link: "l1".into(),
                why: "try again".into(),
            })),
        ] {
            assert_eq!(by_words(&e.to_string()), Status::Busy);
            assert_eq!(e.status(), Status::InvalidParameter, "{e}");
        }
        // nor `internal_error` busy: its type tells it, not its words
        let e = BrokerRestoreError::PreBackup(NowError::Failed(BackupError::File(FileError::new(
            Path::new("/d/try again"),
            std::io::Error::other("no"),
        ))));
        assert_eq!(by_words(&e.to_string()), Status::Busy);
        assert_eq!(e.status(), Status::InternalError, "{e}");
        // a staging that failed and left its folder keeps the status of the failure
        let stays = |error: BrokerRestoreError| BrokerRestoreError::Stays {
            error: Box::new(error),
            path: PathBuf::from("/d/t"),
            source: std::io::Error::other("no"),
        };
        assert_eq!(
            stays(BrokerRestoreError::NoCa).status(),
            Status::InvalidParameter
        );
        assert_eq!(
            stays(BrokerRestoreError::Busy(LinkError::new(Status::Busy, "x"))).status(),
            Status::Busy
        );
    }

    /// Rule 8 (audit T7): every refusal says, byte for byte, what it said when
    /// it was a `String`. The texts reach the answers of `restore_check` and
    /// `restore_apply`, `error.txt` of `restore.failed` (and so the audit
    /// journal) and the start-up output of `wyrmd`.
    #[test]
    fn every_error_says_what_its_text_said() {
        let io = || std::io::Error::other("no");
        let file = || FileError::new(Path::new("/d/f"), io());
        let boxed = || -> secret::Error { "no".into() };
        let codec = || wyrm_core::codec::CodecError::Decode("no".into());
        let json = || serde_json::from_str::<u8>("x").unwrap_err();
        let json_text = "expected value at line 1 column 1";
        let segment = || wyrm_core::keyspace::validate_segment("").unwrap_err();

        said(
            &NoPlace {
                path: "keys/x y".into(),
            },
            "the backup lists \"keys/x y\", a file no section defines: nothing of this backup \
             is restored",
        );
        said(&NotPlain::Segment("a/b".into()), "\"a/b\" is no file name");
        said(&NotPlain::NoName, "a path without a file name");

        use ControlError as C;
        said(
            &C::NotSegment {
                path: "control/state/wal.1".into(),
            },
            "control/state/wal.1 is no segment of a WAL (wal.<first lsn>.wyw): a store is \
             restored from its segments alone. Nothing of this backup is restored",
        );
        said(
            &C::NoRegistry,
            "the control section of the backup holds no segment of the registry \
             (control/state). Nothing of this backup is restored",
        );
        said(
            &C::NoHead { store: "users" },
            "the backup does not say how many records its users store holds. Nothing of this \
             backup is restored",
        );
        said(
            &C::Head {
                store: "state",
                said: 7,
                found: 0,
            },
            "the state store of the backup opens with 0 records, the backup says it holds 7. \
             Nothing of this backup is restored",
        );
        use GateError as G;
        said(
            &G::Remote,
            "mode replace is not run through an upstream: it replaces this site's state. Do it \
             on the broker's own gateway (mode add works from above)",
        );
        said(
            &G::ExportOff,
            "restoring the keys section needs backups.export_secrets: true in wyrmd.json5 (set \
             on the host)",
        );
        said(
            &G::NoPassphrase,
            "passphrase: required to restore the keys section",
        );
        said(
            &G::KeysDiffer {
                differ: vec!["state.key".into(), "secrets.bin".into()],
            },
            "the keys of the backup differ from this broker's (state.key, secrets.bin): they \
             are put in place only with replace_keys: true",
        );
        said(
            &G::KeysDiffer {
                differ: vec!["pki/ca.pem".into()],
            },
            "the keys of the backup differ from this broker's (pki/ca.pem): they are put in \
             place only with replace_keys: true (another CA: links, operators and peer brokers \
             enrol again)",
        );

        said(
            &Problem::OtherSite {
                backup: "plant".into(),
                here: "s".into(),
            },
            "the backup is of site plant, this broker is s: a site is restored under its own \
             name (set `site` in wyrmd.json5)",
        );
        said(
            &Problem::NewerSchema {
                store: "registry".into(),
                backup: 99,
                here: 20,
            },
            "the registry store of the backup has schema 99, this broker reads up to 20: \
             update the broker first",
        );

        use PlanError as P;
        said(&P::File(file()), "/d/f: no");
        said(&P::Json(json()), &format!("plan.json: {json_text}"));
        said(
            &P::Path(format::check_path("../x").unwrap_err()),
            "restore.pending: path \"../x\": empty, `.` or `..` segment",
        );
        said(&P::Component(segment()), "empty segment");

        use LinkSecretsError as L;
        said(&L::Decode(codec()), "link secrets: cbor decode: no");
        said(&L::NotMap, "link secrets: not a map");
        said(
            &L::LinkId(crate::registry::LinkIdError::Dot(".x".into())),
            "link id \".x\" may not start with '.'",
        );
        said(
            &L::LinkNotMap { link: "plc".into() },
            "link secrets: plc: not a map",
        );
        said(
            &L::NotBytes {
                link: "plc".into(),
                name: "password".into(),
            },
            "link secrets: plc/password: not bytes",
        );

        use StorageError as S;
        said(&S::File(file()), "/d/f: no");
        said(&S::TreeDecode(codec()), "storage tree: unreadable");
        said(&S::TreeShape, "storage tree: unreadable");
        said(&S::Store(wyrm_storage::Error::Io(io())), "storage: no");

        use PendingError as N;
        said(
            &N::Plan(P::Json(json())),
            &format!("plan.json: {json_text}"),
        );
        said(
            &N::Begun(P::Json(json())),
            &format!("plan.json: {json_text}; the restore had begun: see restore.pending"),
        );
        said(&N::File(file()), "/d/f: no");
        said(&N::Before(json()), &format!("before.json: {json_text}"));
        said(&N::BeforeEncode(json()), json_text);
        said(&N::Storage(S::TreeShape), "storage tree: unreadable");
        said(&N::LinkSecrets(L::NotMap), "link secrets: not a map");
        said(&N::SecretStore(boxed()), "no");
        // the names of the files in the texts are the constants the code uses
        assert_eq!(
            (PLAN, BEFORE, PENDING),
            ("plan.json", "before.json", "restore.pending")
        );
        assert_eq!(CA_FILE, "pki/ca.pem");

        use BrokerRestoreError as B;
        said(
            &B::Restore(RestoreError::BrokerBackup),
            "a broker backup: restore it from System, not as a link",
        );
        said(
            &B::from(format::ReadError::ManifestTooLarge),
            "manifest: too large",
        );
        said(&B::from(file()), "/d/f: no");
        said(
            &B::LinkBackup,
            "a link backup: install it with Add a link, From backup",
        );
        said(
            &B::Place(NoPlace { path: "x".into() }),
            "the backup lists \"x\", a file no section defines: nothing of this backup is \
             restored",
        );
        said(&B::NoCa, "the keys section holds no pki/ca.pem");
        said(&B::KeyLoad(boxed()), "no");
        said(
            &B::Section {
                section: SectionName::Keys,
                mode: RestoreMode::Add,
            },
            "sections: keys is not restored with mode add (of links, storage, dataflows)",
        );
        said(
            &B::Section {
                section: SectionName::Config,
                mode: RestoreMode::Replace,
            },
            "sections: config is not restored with mode replace (of control, keys, dataflows, \
             storage, history, links, packages)",
        );
        said(&B::NoSections, "sections: none chosen");
        said(
            &B::Problem(Problem::OtherSite {
                backup: "plant".into(),
                here: "s".into(),
            }),
            "the backup is of site plant, this broker is s: a site is restored under its own \
             name (set `site` in wyrmd.json5)",
        );
        said(
            &B::MissingSection(SectionName::History),
            "sections: the backup has no section history",
        );
        said(
            &B::Anchored,
            "state_anchor_dir is set: restore the control plane offline, then run `wyrmd \
             init-anchors` (docs/operations.md §3)",
        );
        said(
            &B::Gate(G::NoPassphrase),
            "passphrase: required to restore the keys section",
        );
        said(
            &B::ControlKeys,
            "the control plane of the backup is under other keys than this broker's: restore \
             it together with the keys section (replace_keys: true)",
        );
        said(
            &B::Busy(LinkError::new(
                Status::Busy,
                "a restore is being staged; one at a time",
            )),
            "a restore is being staged; one at a time",
        );
        said(
            &B::PreBackup(NowError::Refused(StartError::Running)),
            "a backup is being made; one at a time",
        );
        said(
            &B::PreBackup(NowError::Failed(BackupError::StorageClosed)),
            "storage: not open",
        );
        said(&B::PreBackup(NowError::Gone), "the backup is gone");
        let join = cancelled();
        let text = join.to_string();
        said(&B::Task(join), &text);
        said(
            &B::WalKeys {
                store: "state",
                source: StateError::Rejected("no".into()),
            },
            "state: the store of the backup does not open with the keys that will be in place \
             (operation rejected: no): restore it together with the keys section",
        );
        said(
            &B::History(wyrm_history::store::Error::Db("no".into())),
            "the history of the backup does not open: history store: no",
        );
        said(&B::Storage(S::TreeShape), "storage tree: unreadable");
        said(&B::LinkSecrets(L::NotMap), "link secrets: not a map");
        said(&B::SecretsEncode(codec()), "cbor decode: no");
        said(
            &B::PackageInvalid {
                name: "demo".into(),
                why: "no".into(),
            },
            "package demo of the backup: no",
        );
        said(
            &B::PackageName {
                dir: "demo".into(),
                holds: "other".into(),
            },
            "packages/demo holds package other",
        );
        said(&B::PackageVersion(segment()), "empty segment");
        said(
            &B::Asks {
                asks: vec![
                    "package demo: network a:1".into(),
                    "package demo: write on wy/{site}/downstream/plc1".into(),
                ],
            },
            "the packages of the backup ask for: package demo: network a:1; package demo: \
             write on wy/{site}/downstream/plc1. Nothing is restored: read them, then restore \
             again with Accept Requested Rights",
        );
        said(
            &B::SecretStore(boxed()),
            "the secret store of the backup: no",
        );
        said(&B::PlanEncode(json()), json_text);
        said(
            &B::Plan(P::Json(json())),
            &format!("plan.json: {json_text}"),
        );
        said(
            &B::Stays {
                error: Box::new(B::NoCa),
                path: PathBuf::from("/d/restore.pending.tmp"),
                source: io(),
            },
            "the keys section holds no pki/ca.pem; /d/restore.pending.tmp stays: no",
        );
        said(&B::StorageClosed, "storage: not open");
        said(&B::NoStorageTree, "the backup has no storage tree");
        said(
            &B::StorageApply(wyrm_storage::Error::Io(io())),
            "storage: no",
        );
    }

    /// The start-up side keeps its outcomes: a plan that does not read before
    /// anything changed is set aside with its text; one that does not read
    /// after the restore began stops the start, and nothing is touched.
    #[test]
    fn a_pending_restore_fails_by_its_type() {
        let (d, p) = staged("pending-types");
        std::fs::write(p.join(PLAN), b"{ nope").unwrap();
        assert_eq!(apply_pending(&d).unwrap(), None);
        let f = take_failure(&d).unwrap();
        assert!(f.error.starts_with("plan.json: "), "{}", f.error);
        assert!(!p.exists() && d.join(FAILED).is_dir());

        let (d, p) = staged("pending-types-begun");
        assert!(apply_pending(&d).unwrap().is_some());
        let before = tree_of(&d);
        std::fs::write(p.join(PLAN), b"{ nope").unwrap();
        let e = apply_pending(&d).unwrap_err();
        assert!(
            matches!(e, PendingError::Begun(PlanError::Json(_))),
            "{e:?}"
        );
        assert!(e
            .to_string()
            .ends_with("; the restore had begun: see restore.pending"));
        assert_eq!(tree_of(&d), before, "nothing is touched");
        assert!(p.is_dir() && !d.join(FAILED).exists());

        let (d, p) = staged("pending-types-before");
        std::fs::write(p.join(BEFORE), b"{ nope").unwrap();
        assert!(matches!(apply_pending(&d), Err(PendingError::Before(_))));
        assert!(matches!(
            undo_pending(&d, "why"),
            Err(PendingError::Before(_))
        ));
        assert!(p.is_dir() && !d.join(FAILED).exists());
    }

    /// Owner decision 2026-11-27: a `replace` whose `pre-restore` backup
    /// fails on an I/O error is refused with `internal_error`, never run
    /// without that backup. Nothing is staged (`restore.pending` and its
    /// `.tmp` are not there) and the broker takes the next restore.
    #[cfg(unix)]
    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn a_replace_without_its_pre_restore_backup_is_refused_as_internal() {
        use std::os::unix::fs::PermissionsExt;
        use wyrm_link_sdk::TestHarness;
        let ctl = exporting("restore-pre-backup-io");
        let d = ctl.cfg.data_dir.clone();
        // an artifact of the flow engine, in the backup to restore
        let artifacts = d.join("flows/artifacts");
        std::fs::create_dir_all(&artifacts).unwrap();
        let artifact = artifacts.join("a.wasm");
        std::fs::write(&artifact, b"artifact").unwrap();
        let path = made(&ctl, "upload.wyrm-backup", &[SectionName::Dataflows]);
        let bytes = std::fs::read(&path).unwrap();
        // the pre-restore backup copies the artifact again, and cannot read it
        std::fs::set_permissions(&artifact, std::fs::Permissions::from_mode(0o000)).unwrap();
        if std::fs::read(&artifact).is_ok() {
            // root reads any file: no I/O error to be made here
            return;
        }

        let h = TestHarness::<Admin>::start_with(
            super::super::AdminStart {
                ctl: ctl.clone(),
                embedded: Arc::new(tokio::sync::Mutex::new(Default::default())),
            },
            |c| {
                c.root = Some("wy/s/sys".into());
                c.open_actions = vec!["hello".into(), "enroll".into()];
                c.overlays = false;
                c.audit = false;
            },
        )
        .await;
        let args = |kv: Vec<(&str, Value)>| {
            Value::Map(
                kv.into_iter()
                    .map(|(k, v)| (k.to_owned(), v))
                    .collect::<BTreeMap<_, _>>(),
            )
        };
        let call = |action: &'static str, a: Value| {
            let h = &h;
            async move {
                let r = h
                    .invoke("backups", action, a, Some(h.ptok(Perm::Config)))
                    .await;
                r.into_iter().next().expect("an answer")
            }
        };
        let begun = call(
            "restore_begin",
            args(vec![("size", Value::UInt(bytes.len() as u64))]),
        )
        .await;
        let Some(Value::Map(m)) = begun.value() else {
            panic!("restore_begin: {begun:?}");
        };
        let Some(Value::Str(upload)) = m.get("upload").cloned() else {
            panic!("restore_begin: {m:?}");
        };
        let part = call(
            "restore_part",
            args(vec![
                ("upload", Value::Str(upload.clone())),
                ("offset", Value::UInt(0)),
                ("data", Value::Bytes(bytes)),
            ]),
        )
        .await;
        assert!(part.att.status.is_none_or(|s| !s.is_error()), "{part:?}");
        let refused = call(
            "restore_apply",
            args(vec![
                ("upload", Value::Str(upload)),
                ("sections", Value::Array(vec![Value::from("dataflows")])),
                ("mode", Value::from("replace")),
            ]),
        )
        .await;
        let status = refused.att.status.map(|s| s.code());
        assert_eq!(
            status,
            Some(Status::InternalError.code()),
            "{refused:?} {:?}",
            refused.value()
        );
        // nothing staged, and the restore is no longer held
        assert!(!d.join(PENDING).exists() && !d.join(PENDING_TMP).exists());
        ctl.replacing(true).unwrap();
        ctl.replacing(false).unwrap();
        // the failed job is kept as failed, with the cause in its text
        let job = ctl
            .backups()
            .list()
            .into_iter()
            .find(|j| j.kind == super::super::backups::JobKind::PreRestore)
            .expect("the pre-restore job");
        assert_eq!(job.status, super::super::backups::JobStatus::Failed);
        assert!(job.error.contains("a.wasm"), "{}", job.error);
        std::fs::set_permissions(&artifact, std::fs::Permissions::from_mode(0o600)).unwrap();
        h.stop().await;
    }
}
