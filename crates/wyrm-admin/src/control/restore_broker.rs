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
    broker_made_secret, io_err, key_files, make_private_dir, passphrase_arg, wal_stores,
    BackupRequest, SealWith,
};
use super::restore::{LinkLayout, MAX_UPLOAD};
use super::*;
use crate::backup::{self as format, Kind, Manifest, MasterKey};
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
const REPLACEABLE: [&str; 7] = [
    "control",
    "keys",
    "dataflows",
    "storage",
    "history",
    "links",
    "packages",
];
/// The sections `mode: add` takes.
const ADDABLE: [&str; 3] = ["links", "storage", "dataflows"];

/// What [`apply_pending`] does, written by `restore_apply`.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct Plan {
    pub by: String,
    /// `<site> <created>` of the backup.
    pub backup: String,
    pub sections: Vec<String>,
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
    pub sections: Vec<String>,
}

/// A path of a plan: relative, plain segments.
fn plan_path(p: &str) -> Result<(), String> {
    format::check_path(p).map_err(|e| format!("restore.pending: {e}"))
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
fn plain_segment(s: &str) -> Result<&str, String> {
    let bad = s.is_empty()
        || s == "."
        || s == ".."
        || s.chars()
            .any(|c| matches!(c, '/' | '\\' | ':') || c.is_control());
    if bad {
        return Err(format!("{s:?} is no file name"));
    }
    Ok(s)
}

/// A relative path built from checked segments (at least one).
fn plain_rel(segs: &[&str]) -> Result<PathBuf, String> {
    if segs.is_empty() {
        return Err("a path without a file name".into());
    }
    let mut out = PathBuf::new();
    for s in segs {
        out.push(plain_segment(s)?);
    }
    Ok(out)
}

/// The place of the file `path` of a broker backup: `Err` for a path that
/// no section defines (ADR 0048 §3.6, the allowlist of a restore).
fn place_of(path: &str) -> Result<Place, String> {
    let refuse = || {
        format!(
            "the backup lists {path:?}, a file no section defines: nothing of this backup is \
             restored"
        )
    };
    let link = |id: &str| -> Result<String, String> {
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
fn replace_gates(g: &Gates) -> Result<(), String> {
    if g.remote {
        return Err(
            "mode replace is not run through an upstream: it replaces this site's state. Do it \
             on the broker's own gateway (mode add works from above)"
                .into(),
        );
    }
    if !g.keys {
        return Ok(());
    }
    if !g.export_secrets {
        return Err(
            "restoring the keys section needs backups.export_secrets: true in wyrmd.json5 (set \
             on the host)"
                .into(),
        );
    }
    if !g.passphrase {
        return Err("passphrase: required to restore the keys section".into());
    }
    if !g.differ.is_empty() && !g.replace_keys {
        let ca = g.differ.iter().any(|f| f == CA_FILE);
        return Err(format!(
            "the keys of the backup differ from this broker's ({}): they are put in place only \
             with replace_keys: true{}",
            g.differ.join(", "),
            if ca {
                " (another CA: links, operators and peer brokers enrol again)"
            } else {
                ""
            }
        ));
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
    pub sections: Vec<String>,
    pub error: String,
}

fn is_there(p: &Path) -> bool {
    std::fs::symlink_metadata(p).is_ok()
}

fn move_to(from: &Path, to: &Path) -> Result<(), String> {
    if let Some(d) = to.parent() {
        std::fs::create_dir_all(d).map_err(|e| io_err(d, e))?;
    }
    std::fs::rename(from, to).map_err(|e| io_err(to, e))
}

fn component_target(name: &str) -> String {
    format!("packages/.wasm/{name}.wasm")
}

/// The plan of the folder, checked: every path relative and plain.
fn read_plan(pending: &Path) -> Result<Plan, String> {
    let text = std::fs::read(pending.join(PLAN)).map_err(|e| io_err(&pending.join(PLAN), e))?;
    let plan: Plan = serde_json::from_slice(&text).map_err(|e| format!("{PLAN}: {e}"))?;
    for p in plan.remove.iter().chain(&plan.dirs).chain(&plan.files) {
        plan_path(p)?;
    }
    for (name, entry) in &plan.components {
        plan_path(entry)?;
        wyrm_core::keyspace::validate_segment(name).map_err(|e| e.to_string())?;
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
fn forward(data_dir: &Path, pending: &Path, plan: &Plan, before: &Before) -> Result<(), String> {
    let (staged, old) = (pending.join("data"), pending.join(OLD));
    let existed = |p: &str| before.existed.iter().any(|e| e == p);
    // what is at `p` goes aside, once; a leftover of an earlier try goes
    let aside = |p: &str| -> Result<(), String> {
        let (to, keep) = (data_dir.join(p), old.join(p));
        if !is_there(&to) {
            return Ok(());
        }
        if existed(p) && !is_there(&keep) {
            move_to(&to, &keep)
        } else {
            crate::nofollow::remove_any(&to);
            Ok(())
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
        crate::nofollow::remove_any(&built);
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
            std::fs::create_dir_all(d).map_err(|e| io_err(d, e))?;
        }
        std::fs::copy(data_dir.join(entry), &to).map_err(|e| io_err(&to, e))?;
    }
    // link secrets go into the store that is in place now; the store as it
    // was is kept first
    let secrets = pending.join(LINK_SECRETS);
    if secrets.is_file() {
        let (at, keep) = (data_dir.join(SECRETS_BIN), old.join(SECRETS_BIN));
        if existed(SECRETS_BIN) && !is_there(&keep) {
            let bytes = Zeroizing::new(std::fs::read(&at).map_err(|e| io_err(&at, e))?);
            secret::write_private(&keep, &bytes).map_err(|e| io_err(&keep, e))?;
        }
        let bytes = Zeroizing::new(std::fs::read(&secrets).map_err(|e| io_err(&secrets, e))?);
        let links = parse_link_secrets(&bytes)?;
        let store = crate::secrets::SecretStore::open(data_dir).map_err(|e| e.to_string())?;
        for (link, m) in links {
            for (name, b) in m {
                store.set(&link, &name, &b).map_err(|e| e.to_string())?;
            }
        }
    }
    Ok(())
}

/// `{link: {name: bytes}}`.
type LinkSecrets = BTreeMap<String, BTreeMap<String, Zeroizing<Vec<u8>>>>;

/// The link secrets a restore staged: `{link: {name: bytes}}`, without the
/// ones a broker makes for a link's identity (never taken from a backup).
fn parse_link_secrets(bytes: &[u8]) -> Result<LinkSecrets, String> {
    let Value::Map(links) =
        wyrm_core::codec::from_slice::<Value>(bytes).map_err(|e| format!("link secrets: {e}"))?
    else {
        return Err("link secrets: not a map".into());
    };
    let mut out = BTreeMap::new();
    for (link, v) in links {
        crate::registry::validate_link_id(&link)?;
        let Value::Map(m) = v else {
            return Err(format!("link secrets: {link}: not a map"));
        };
        let mut of_link = BTreeMap::new();
        for (name, v) in m {
            if broker_made_secret(&name) {
                continue;
            }
            let Value::Bytes(b) = v else {
                return Err(format!("link secrets: {link}/{name}: not bytes"));
            };
            of_link.insert(name, Zeroizing::new(b));
        }
        out.insert(link, of_link);
    }
    Ok(out)
}

/// The storage of a backup (`storage/tree.cbor`) as a new store at `dir`.
fn build_storage(tree: &Path, dir: &Path) -> Result<(), String> {
    let bytes = std::fs::read(tree).map_err(|e| io_err(tree, e))?;
    let changes = wyrm_core::codec::from_slice(&bytes)
        .ok()
        .and_then(replication::parse_changes)
        .ok_or("storage tree: unreadable")?;
    let store = wyrm_storage::Store::open(dir)?;
    store.apply(changes.put, Vec::new())?;
    Ok(())
}

/// Put back what [`forward`] replaced or removed, then keep the folder as
/// `restore.failed` with `why`. Every step may run again. `Err`: something
/// could not be put back (the state is then neither the old nor the new).
fn undo(data_dir: &Path, pending: &Path, before: &Before, why: &str) -> Result<(), String> {
    let old = pending.join(OLD);
    if !pending.join(UNDO).exists() {
        secret::write_private(&pending.join(UNDO), why.as_bytes())
            .map_err(|e| io_err(pending, e))?;
    }
    for p in before.placed.iter().rev() {
        let (to, keep) = (data_dir.join(p), old.join(p));
        if before.existed.contains(p) {
            // not set aside: never touched, or back already
            if is_there(&keep) {
                crate::nofollow::remove_any(&to);
                move_to(&keep, &to)?;
            }
        } else {
            crate::nofollow::remove_any(&to);
        }
    }
    for m in before.moved.iter().rev() {
        let (at, keep) = (data_dir.join(m), old.join(m));
        if is_there(&keep) {
            crate::nofollow::remove_any(&at);
            move_to(&keep, &at)?;
        }
    }
    set_failed(data_dir, pending, why)
}

/// The folder becomes `restore.failed`: its plan and the reason stay,
/// everything else (opened keys and secrets among it) goes.
fn set_failed(data_dir: &Path, pending: &Path, why: &str) -> Result<(), String> {
    for name in ["data", OLD, LINK_SECRETS, STORAGE_TREE, BEFORE] {
        crate::nofollow::remove_any(&pending.join(name));
    }
    secret::write_private(&pending.join(ERROR), why.as_bytes()).map_err(|e| io_err(pending, e))?;
    let _ = std::fs::remove_file(pending.join(UNDO));
    let failed = data_dir.join(FAILED);
    crate::nofollow::remove_any(&failed);
    std::fs::rename(pending, &failed).map_err(|e| io_err(&failed, e))
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
pub fn apply_pending(data_dir: &Path) -> Result<Option<Applied>, String> {
    // a staging that never finished; a restore that was committed
    let _ = std::fs::remove_dir_all(data_dir.join(PENDING_TMP));
    let _ = std::fs::remove_dir_all(data_dir.join(DONE));
    let pending = data_dir.join(PENDING);
    if !pending.is_dir() {
        return Ok(None);
    }
    let started = pending.join(BEFORE).exists();
    let plan = match read_plan(&pending) {
        Ok(plan) => plan,
        // nothing was changed yet: the folder is set aside
        Err(e) if !started => return set_failed(data_dir, &pending, &e).map(|()| None),
        Err(e) => return Err(format!("{e}; the restore had begun: see {PENDING}")),
    };
    let before: Before = if started {
        let text =
            std::fs::read(pending.join(BEFORE)).map_err(|e| io_err(&pending.join(BEFORE), e))?;
        serde_json::from_slice(&text).map_err(|e| format!("{BEFORE}: {e}"))?
    } else {
        let b = look_before(data_dir, &pending, &plan);
        let text = serde_json::to_vec(&b).map_err(|e| e.to_string())?;
        secret::write_private(&pending.join(BEFORE), &text).map_err(|e| io_err(&pending, e))?;
        b
    };
    // an undo that a start stopped in goes on
    if pending.join(UNDO).exists() {
        let why = std::fs::read_to_string(pending.join(UNDO)).unwrap_or_default();
        return undo(data_dir, &pending, &before, &why).map(|()| None);
    }
    match forward(data_dir, &pending, &plan, &before) {
        Ok(()) => Ok(Some(Applied {
            by: plan.by,
            backup: plan.backup,
            sections: plan.sections,
        })),
        Err(e) => undo(data_dir, &pending, &before, &e).map(|()| None),
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
    let _ = std::fs::remove_dir_all(&done);
    match std::fs::rename(&pending, &done) {
        Ok(()) => {
            let _ = std::fs::remove_dir_all(&done);
        }
        Err(e) => warn!("{}: {e}", pending.display()),
    }
}

/// The stores did not open on what [`apply_pending`] put in place (`why`):
/// everything goes back as it was before the restore, and the folder is
/// kept as `restore.failed`. The next start runs on the old state.
pub fn undo_pending(data_dir: &Path, why: &str) -> Result<(), String> {
    let pending = data_dir.join(PENDING);
    if !pending.is_dir() {
        return Ok(());
    }
    let text = std::fs::read(pending.join(BEFORE)).map_err(|e| io_err(&pending.join(BEFORE), e))?;
    let before: Before = serde_json::from_slice(&text).map_err(|e| format!("{BEFORE}: {e}"))?;
    undo(data_dir, &pending, &before, why)
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
    let _ = std::fs::write(failed.join(REPORTED), b"");
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
    problems: Vec<String>,
    notes: Vec<String>,
}

fn strs(v: &[String]) -> Value {
    Value::Array(v.iter().map(|s| Value::from(s.clone())).collect())
}

impl Control {
    /// Read the broker backup at `path` whole and compare it with this
    /// broker. Blocking.
    fn check_broker_backup(
        &self,
        r: &mut format::Reader,
        passphrase: Option<&[u8]>,
    ) -> Result<Checked, String> {
        let manifest = r.manifest().clone();
        if manifest.kind != Kind::Broker {
            return Err("a link backup: install it with Add a link, From backup".into());
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
            problems.push(format!(
                "the backup is of site {}, this broker is {}: a site is restored under its own \
                 name (set `site` in wyrmd.json5)",
                manifest.site, self.cfg.site
            ));
        }
        let here = self.schemas();
        for (name, v) in &manifest.schemas {
            if here.get(name).is_some_and(|h| v > h) {
                problems.push(format!(
                    "the {name} store of the backup has schema {v}, this broker reads up to {}: \
                     update the broker first",
                    here[name]
                ));
            }
        }
        let d = &self.cfg.data_dir;
        let mut keys_other = false;
        let mut keys_differ = Vec::new();
        if manifest.section("keys").is_some() {
            if !places.iter().any(|(_, p)| *p == Place::Key(CA_FILE.into())) {
                return Err(format!("the keys section holds no {CA_FILE}"));
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
        // does the registry of the backup open with the key in place here?
        let scratch = super::backups::StageDir::new(&self.backups_dir())?;
        let mut wal_opens_here = true;
        let mut any = false;
        for f in &manifest
            .section("control")
            .map(|s| s.files.clone())
            .unwrap_or_default()
        {
            if let Some(file) = f.path.strip_prefix("control/state/") {
                r.extract(&f.path, &scratch.0.join("state").join(file), None)?;
                any = true;
            }
        }
        if any {
            let state_key =
                secret::load_or_create_key(&d.join("state.key")).map_err(|e| e.to_string())?;
            wal_opens_here = wyrm_state::replicate::copy_to(
                &scratch.0.join("state"),
                &state_key,
                &scratch.0.join("verify"),
            )
            .is_ok();
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
            .section("links")
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
            ("sealed".to_owned(), Value::from(m.sealed.how.clone())),
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
                        .map(|s| (s.name.clone(), Value::UInt(s.size())))
                        .collect(),
                ),
            ),
            (
                "keys".to_owned(),
                // `other`: another CA; `differ`: this CA, other key files
                Value::from(
                    match (
                        m.section("keys").is_some(),
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
            ("problems".to_owned(), strs(&c.problems)),
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
        chosen: &[String],
        accept: bool,
        by: &str,
    ) -> Result<Plan, String> {
        let d = &self.cfg.data_dir;
        let tmp = d.join(PENDING_TMP);
        let _ = std::fs::remove_dir_all(&tmp);
        // what the chosen sections open into must fit, before any of it is
        self.room_for(super::restore::extract_need(
            c.manifest
                .sections
                .iter()
                .filter(|s| chosen.contains(&s.name) || s.name == "control")
                .flat_map(|s| &s.files),
        ))?;
        make_private_dir(&tmp)?;
        let staged = self.stage_sections(r, c, chosen, accept, by, &tmp);
        let plan = match staged {
            Ok(plan) => plan,
            Err(e) => {
                // nothing half staged stays (it may hold opened secrets)
                let _ = std::fs::remove_dir_all(&tmp);
                return Err(e);
            }
        };
        let pending = d.join(PENDING);
        let _ = std::fs::remove_dir_all(&pending);
        // an earlier restore that was not applied is forgotten
        let _ = std::fs::remove_dir_all(d.join(FAILED));
        std::fs::rename(&tmp, &pending).map_err(|e| io_err(&pending, e))?;
        Ok(plan)
    }

    /// The body of [`Self::stage_replace`]: everything into `tmp`.
    fn stage_sections(
        &self,
        r: &mut format::Reader,
        c: &Checked,
        chosen: &[String],
        accept: bool,
        by: &str,
        tmp: &Path,
    ) -> Result<Plan, String> {
        let d = &self.cfg.data_dir;
        let data = tmp.join("data");
        let key = c.key.as_ref();
        let has = |s: &str| chosen.iter().any(|x| x == s);
        let mut plan = Plan {
            by: by.to_owned(),
            backup: format!("{} {}", c.manifest.site, c.manifest.created),
            sections: chosen.to_vec(),
            ..Default::default()
        };
        let keys = has("keys") && c.manifest.section("keys").is_some();
        if keys {
            for (p, place) in &c.places {
                let Place::Key(rel) = place else { continue };
                r.extract(p, &data.join(rel), key)?;
                plan.files.push(rel.clone());
            }
            if c.keys_other {
                // everything the replaced CA issued
                plan.remove = vec!["pki".into(), "operators".into(), "peers".into()];
                plan.strip_link_certs = true;
            }
        }
        // WALs: the registry, users (and the audit when its key is replaced)
        // with `control`; the flow store with `control` or `dataflows`
        let state_key_replaced = keys && c.keys_differ.iter().any(|f| f == "state.key");
        for (name, dir, key_file, _) in wal_stores() {
            let wanted = match name {
                "flows" => has("control") || has("dataflows"),
                "audit" => has("control") && state_key_replaced,
                _ => has("control"),
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
                r.extract(p, &data.join(dir).join(file), None)?;
            }
            // with the key that will be in place
            let staged_key = data.join(key_file);
            let key_path = if staged_key.is_file() {
                staged_key
            } else {
                d.join(key_file)
            };
            let wal_key = secret::load_or_create_key(&key_path).map_err(|e| e.to_string())?;
            wyrm_state::replicate::copy_to(
                &data.join(dir),
                &wal_key,
                &tmp.join("verify").join(name),
            )
            .map_err(|e| {
                format!(
                    "{name}: the store of the backup does not open with the keys that will \
                         be in place ({e}): restore it together with the keys section"
                )
            })?;
            plan.dirs.push(dir.to_owned());
        }
        let _ = std::fs::remove_dir_all(tmp.join("verify"));
        if has("dataflows") {
            let dir = data.join("flows").join("artifacts");
            std::fs::create_dir_all(&dir).map_err(|e| io_err(&dir, e))?;
            for (p, place) in &c.places {
                if let Place::Artifact(rel) = place {
                    r.extract(p, &dir.join(rel), None)?;
                }
            }
            plan.dirs.push("flows/artifacts".into());
        }
        if has("storage") && c.manifest.section("storage").is_some() {
            // the store is built here, from the tree: a tree that does not
            // read refuses the restore now, not the start that applies it
            let tree = tmp.join(STORAGE_TREE);
            r.extract("storage/tree.cbor", &tree, None)?;
            build_storage(&tree, &data.join("storage"))?;
            std::fs::remove_file(&tree).map_err(|e| io_err(&tree, e))?;
            plan.dirs.push("storage".into());
        }
        if has("history") && c.manifest.section("history").is_some() {
            let dir = data.join("history");
            std::fs::create_dir_all(dir.join("days")).map_err(|e| io_err(&dir, e))?;
            for (p, place) in &c.places {
                match place {
                    Place::HistoryIndex => r.extract(p, &dir.join("index.redb"), None)?,
                    Place::HistoryDay(day) => r.extract(p, &dir.join("days").join(day), None)?,
                    _ => continue,
                };
            }
            // files that do not open would stop every start after the restore
            wyrm_history::Store::open(&dir)
                .map(drop)
                .map_err(|e| format!("the history of the backup does not open: {e}"))?;
            plan.dirs.push("history".into());
        }
        if has("links") {
            // with `control` every link of the backup is in the registry
            // that will be in place; without it, the links this broker has
            let reg = self.registry();
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
                if !has("control") && !reg.links.contains_key(id) {
                    continue;
                }
                let dir = data.join("links").join(id).join("data");
                std::fs::create_dir_all(&dir).map_err(|e| io_err(&dir, e))?;
                for (p, place) in &c.places {
                    match place {
                        Place::LinkFile(l, rel) if l == id => {
                            r.extract(p, &dir.join(rel), key)?;
                        }
                        _ => {}
                    }
                }
                plan.dirs.push(format!("links/{id}/data"));
                // With `keys`, the `secrets.bin` of the backup holds them
                // already: the store comes back whole, the secrets the
                // broker made for its links among them (they are that
                // site's own, restored under the gates of the keys).
                // Without `keys`, a link's secrets go into this broker's
                // store, and a broker-made one is never taken from a file.
                if !keys {
                    let plain = r.read_plain(&format!("links/{id}/secrets"), key)?;
                    let Value::Map(m) =
                        wyrm_core::codec::from_slice::<Value>(&plain).map_err(|e| e.to_string())?
                    else {
                        return Err(format!("links/{id}/secrets: not a map"));
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
                    wyrm_core::codec::to_vec(&Value::Map(secrets)).map_err(|e| e.to_string())?,
                );
                // as the start that applies it will read it
                parse_link_secrets(&bytes)?;
                secret::write_private(&tmp.join(LINK_SECRETS), &bytes)
                    .map_err(|e| io_err(tmp, e))?;
            }
        }
        if has("packages") {
            let names: BTreeSet<&String> = c
                .places
                .iter()
                .filter_map(|(_, place)| match place {
                    Place::PackageFile(name, _) => Some(name),
                    _ => None,
                })
                .collect();
            let reg = self.registry();
            let mut asks = Vec::new();
            for name in names {
                let scratch = tmp.join("package").join(name);
                for (p, place) in &c.places {
                    match place {
                        Place::PackageFile(n, rel) if n == name => {
                            r.extract(p, &scratch.join(rel), None)?;
                        }
                        _ => {}
                    }
                }
                // through the validator of every install; its record names
                // the version and the entry
                let source = format!("backup {}", c.manifest.site);
                let zip = packages::repack(&scratch)?;
                let checked = packages::unpack(&zip, &tmp.join("unpacked"), &source, now_s())
                    .map_err(|e| format!("package {name} of the backup: {e}"))?;
                let def = checked.def.clone();
                if def.name != *name {
                    return Err(format!("packages/{name} holds package {}", def.name));
                }
                wyrm_core::keyspace::validate_segment(&def.version).map_err(|e| e.to_string())?;
                let rel = format!("packages/{}/{}", def.name, def.version);
                // what it asks for was accepted here only if this broker
                // has the same version with the same files
                let here = reg.packages.get(&def.name).is_some_and(|p| {
                    p.version == def.version
                        && packages::repack(&d.join(&rel)).is_ok_and(|z| z == zip)
                });
                if !here {
                    asks.extend(super::restore::package_asks(&checked));
                }
                let to = data.join(&rel);
                if let Some(parent) = to.parent() {
                    std::fs::create_dir_all(parent).map_err(|e| io_err(parent, e))?;
                }
                std::fs::rename(&scratch, &to).map_err(|e| io_err(&to, e))?;
                if def.kind == PackageKind::Wasm {
                    plan.components
                        .push((def.name.clone(), format!("{rel}/{}", def.entry)));
                }
                plan.dirs.push(rel);
            }
            let _ = std::fs::remove_dir_all(tmp.join("package"));
            let _ = std::fs::remove_dir_all(tmp.join("unpacked"));
            if !asks.is_empty() && !accept {
                return Err(format!(
                    "the packages of the backup ask for: {}. Nothing is restored: read them, \
                     then restore again with Accept Requested Rights",
                    asks.join("; ")
                ));
            }
        }
        // the secret store of the backup opens with the key that comes with it
        if keys && data.join(SECRETS_BIN).is_file() && data.join("secrets.key").is_file() {
            crate::secrets::SecretStore::open(&data)
                .map(drop)
                .map_err(|e| format!("the secret store of the backup: {e}"))?;
        }
        let text = serde_json::to_vec_pretty(&plan).map_err(|e| e.to_string())?;
        secret::write_private(&tmp.join(PLAN), &text).map_err(|e| io_err(tmp, e))?;
        // as the start that applies it will read it
        read_plan(tmp)?;
        Ok(plan)
    }
}

fn sections_arg(args: &Value) -> Result<Vec<String>, LinkError> {
    match arg(args, "sections") {
        Some(Value::Array(a)) => a
            .iter()
            .map(|v| match v {
                Value::Str(s) => Ok(s.clone()),
                _ => Err(LinkError::invalid_parameter("sections: a list of names")),
            })
            .collect(),
        Some(Value::Str(s)) => Ok(s
            .split([',', ' '])
            .filter(|p| !p.is_empty())
            .map(str::to_owned)
            .collect()),
        _ => Err(LinkError::invalid_parameter("sections: required")),
    }
}

impl Admin {
    /// `sys/backups/~act/restore_check` and `restore_apply`.
    pub(super) async fn restore_broker(
        &self,
        action: &str,
        args: &Value,
        sub: &str,
        remote: bool,
    ) -> wyrm_link_sdk::Result<Option<Value>> {
        let ctl = &self.ctl;
        // A check reads the whole file and `add` installs links: a rebuild
        // of the router waits for both, as for `replace` and any install,
        // and neither starts on a broker that is closing for one.
        let _busy = ctl.busy()?;
        let upload = arg_str(args, "upload")
            .filter(|u| !u.is_empty())
            .ok_or_else(|| LinkError::invalid_parameter("upload: required"))?
            .to_owned();
        let passphrase = passphrase_arg(args)?;
        let path = ctl.upload_take(&upload)?;
        let r = match action {
            "restore_check" => self.restore_check(&path, passphrase).await,
            _ => {
                self.restore_apply(&path, args, passphrase, sub, remote)
                    .await
            }
        };
        // the file stays for the next call (a check, then an apply) until a
        // replace took it
        let used = matches!(&r, Ok((_, true)));
        ctl.upload_release(&upload, used);
        r.map(|(v, _)| Some(v)).map_err(|m| {
            // a rebuild or a backup in flight is a reason to try again
            if m.contains("try again") || m.contains("one at a time") {
                LinkError::new(Status::Busy, m)
            } else {
                LinkError::invalid_parameter(m)
            }
        })
    }

    async fn restore_check(
        &self,
        path: &Path,
        passphrase: Option<Zeroizing<Vec<u8>>>,
    ) -> Result<(Value, bool), String> {
        let (ctl, path) = (self.ctl.clone(), path.to_owned());
        tokio::task::spawn_blocking(move || {
            let size = std::fs::metadata(&path).map_or(0, |m| m.len());
            let mut r = format::Reader::open(&path, MAX_UPLOAD)?;
            let c = ctl.check_broker_backup(&mut r, passphrase.as_deref().map(|p| &p[..]))?;
            Ok((ctl.check_report(&c, size), false))
        })
        .await
        .map_err(|e| e.to_string())?
    }

    async fn restore_apply(
        &self,
        path: &Path,
        args: &Value,
        passphrase: Option<Zeroizing<Vec<u8>>>,
        sub: &str,
        remote: bool,
    ) -> Result<(Value, bool), String> {
        let ctl = &self.ctl;
        let chosen = sections_arg(args).map_err(|e| e.message)?;
        let mode = arg_str(args, "mode").unwrap_or_default().to_owned();
        let allowed: &[&str] = match mode.as_str() {
            "add" => &ADDABLE,
            "replace" => &REPLACEABLE,
            _ => return Err("mode: add or replace".into()),
        };
        if let Some(s) = chosen.iter().find(|s| !allowed.contains(&s.as_str())) {
            return Err(format!(
                "sections: {s} is not restored with mode {mode} (of {})",
                allowed.join(", ")
            ));
        }
        if chosen.is_empty() {
            return Err("sections: none chosen".into());
        }
        if mode == "add" {
            return self
                .restore_add(path, &chosen, passphrase, accepted(args), sub)
                .await
                .map(|v| (v, false));
        }
        let replace_keys = matches!(arg(args, "replace_keys"), Some(Value::Bool(true)));
        let accept = accepted(args);
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
        ctl.replacing(true).map_err(|e| e.message)?;
        let (ctl2, path2, sub2, chosen2) =
            (ctl.clone(), path.to_owned(), sub.to_owned(), chosen.clone());
        let staged = tokio::task::spawn_blocking(move || -> Result<Plan, String> {
            let ctl = ctl2;
            let has = |s: &str| chosen2.iter().any(|x| x == s);
            let pass = passphrase.as_deref().map(|p| &p[..]);
            let mut r = format::Reader::open(&path2, MAX_UPLOAD)?;
            let c = ctl.check_broker_backup(&mut r, pass)?;
            if let Some(p) = c.problems.first() {
                return Err(p.clone());
            }
            if let Some(s) = chosen2.iter().find(|s| c.manifest.section(s).is_none()) {
                return Err(format!("sections: the backup has no section {s}"));
            }
            if has("control") && ctl.cfg.anchor_dir.is_some() {
                return Err(
                    "state_anchor_dir is set: restore the control plane offline, then run \
                     `wyrmd init-anchors` (docs/operations.md §3)"
                        .into(),
                );
            }
            // Every restore of `keys` passes the gates, whatever the CA: the
            // host allowed secrets to move, the caller is of this site and
            // gave the passphrase; keys that differ in any file also need
            // `replace_keys`.
            replace_gates(&Gates {
                remote,
                keys: has("keys"),
                differ: &c.keys_differ,
                export_secrets: ctl.cfg.backups.export_secrets,
                passphrase: pass.is_some(),
                replace_keys,
            })?;
            // keys of the backup that replace other ones
            let new_keys = has("keys") && !c.keys_differ.is_empty();
            if has("control") && !c.wal_opens_here && !new_keys {
                return Err(
                    "the control plane of the backup is under other keys than this broker's: \
                     restore it together with the keys section (replace_keys: true)"
                        .into(),
                );
            }
            // a backup of what is replaced, first. Keys go into it only
            // when they are replaced, under the passphrase of this restore
            // (the key of a broker-sealed file would be replaced with them).
            let mut before: Vec<String> = chosen2
                .iter()
                .filter(|s| new_keys || *s != "keys")
                .cloned()
                .collect();
            if before.iter().any(|s| s == "history") && ctl.history.store().days().is_empty() {
                before.retain(|s| s != "history");
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
                    label: "pre-restore".into(),
                    pinned: false,
                    remote: false,
                    estimate: false,
                },
                &sub2,
            )?;
            info!(backup = %job.id, "what the restore replaces is backed up");
            ctl.stage_replace(&mut r, &c, &chosen2, accept, &sub2)
        })
        .await
        .map_err(|e| e.to_string())
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
            "restore_apply",
            &plan.backup,
            Status::Ok,
            &format!(
                "replace; sections {}; keys replaced: {}; applied at the next start",
                chosen.join(", "),
                plan.strip_link_certs
            ),
        );
        warn!(by = sub, sections = %chosen.join(", "), "restore staged: the broker stops and applies it at the next start");
        // answer first, then stop: the supervisor starts the broker again
        let stop = ctl.clone();
        tokio::spawn(async move {
            tokio::time::sleep(Duration::from_millis(500)).await;
            stop.request_stop();
        });
        Ok((
            Value::Map(BTreeMap::from([
                ("mode".to_owned(), Value::from("replace")),
                ("sections".to_owned(), strs(&chosen)),
                ("restart".to_owned(), Value::Bool(true)),
            ])),
            true,
        ))
    }

    /// `mode: add`: what does not exist yet, live.
    async fn restore_add(
        &self,
        path: &Path,
        chosen: &[String],
        passphrase: Option<Zeroizing<Vec<u8>>>,
        accept: bool,
        sub: &str,
    ) -> Result<Value, String> {
        let ctl = &self.ctl;
        let has = |s: &str| chosen.iter().any(|x| x == s);
        let mut done: Vec<String> = Vec::new();
        let mut skipped: Vec<String> = Vec::new();
        // the whole file is checked once; the key goes on to the parts
        let (ctl2, path2, pass2) = (ctl.clone(), path.to_owned(), passphrase);
        // the key is derived once (Argon2id for a passphrase) and goes on
        // to every link of the file
        let (manifest, tree, key) = tokio::task::spawn_blocking(move || {
            let mut r = format::Reader::open(&path2, MAX_UPLOAD)?;
            let c = ctl2.check_broker_backup(&mut r, pass2.as_deref().map(|p| &p[..]))?;
            let tree = match c.manifest.section("storage") {
                Some(_) => Some(r.read("storage/tree.cbor")?),
                None => None,
            };
            Ok::<_, String>((c.manifest, tree, c.key))
        })
        .await
        .map_err(|e| e.to_string())??;
        if has("dataflows") {
            skipped.push(
                "dataflows: a flow is deployed with proofs of its deployer; restore them with \
                 mode replace"
                    .into(),
            );
        }
        if has("storage") {
            let store = ctl.storage().ok_or("storage: not open")?;
            let changes = tree
                .and_then(|b| wyrm_core::codec::from_slice(&b).ok())
                .and_then(replication::parse_changes)
                .ok_or("the backup has no storage tree")?;
            let put: Vec<_> = changes
                .put
                .into_iter()
                .filter(|(p, _)| store.get(p).is_none())
                .collect();
            let n = put.len();
            if n > 0 {
                tokio::task::spawn_blocking(move || store.apply(put, Vec::new()))
                    .await
                    .map_err(|e| e.to_string())??;
                // the storage link reads its store again
                ctl.schedule_reload();
            }
            done.push(format!("storage: {n} nodes added"));
        }
        if has("links") {
            let ids: Vec<String> = manifest
                .section("links")
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
                    let def: LinkDef =
                        minicbor::decode(&r.read(&format!("links/{id2}/link.cbor"))?)
                            .map_err(|e| format!("links/{id2}/link.cbor: {e}"))?;
                    let package = def.driver.strip_prefix(packages::DRIVER_PREFIX);
                    let lay = LinkLayout::in_broker(&m, &id2, package);
                    ctl2.read_link_parts(&mut r, key.as_ref(), &lay)
                })
                .await
                .map_err(|e| e.to_string())?;
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
            "restore_apply",
            &format!("{} {}", manifest.site, manifest.created),
            Status::Ok,
            &format!(
                "add; sections {}; {} done, {} skipped",
                chosen.join(", "),
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
    let base = |display: &str| {
        ActionMeta::new()
            .display(display)
            .param(
                "upload",
                str_param()
                    .required(true)
                    .display("Upload")
                    .description("The id restore_begin gave"),
            )
            .param(
                "passphrase",
                str_param()
                    .display("Passphrase")
                    .editor(EDITOR_PASSWORD)
                    .description("Of a backup sealed with one"),
            )
            .result(ActionResult::Type(TypeCode::Map))
            .timeout_ms(INSTALL_TIMEOUT_MS)
            .level(Perm::Config)
    };
    ctx.declare_action("backups", "restore_check", base("Check a backup"))
        .await?;
    ctx.declare_action(
        "backups",
        "restore_apply",
        base("Restore")
            .param(
                "sections",
                ParamMeta::of(TypeCode::Array)
                    .required(true)
                    .display("Sections"),
            )
            .param(
                "mode",
                str_param()
                    .required(true)
                    .display("Mode")
                    .enum_values(["add", "replace"])
                    .description(
                        "add: what does not exist yet, live. replace: the broker stops and \
                         applies it at the next start",
                    ),
            )
            .param(
                "accept",
                ParamMeta::of(TypeCode::Bool)
                    .display("Accept requested rights")
                    .description(
                        "Of the links mode add installs and of the packages mode replace \
                         brings",
                    ),
            )
            .param(
                "replace_keys",
                ParamMeta::of(TypeCode::Bool)
                    .display("Replace the site's keys")
                    .description(
                        "Keys that differ from this broker's (restore_check lists them). \
                         Another CA: links, operators and peer brokers enrol again",
                    ),
            ),
    )
    .await
}

#[cfg(test)]
mod tests {
    use super::*;

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
            sections: vec!["control".into(), "keys".into()],
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
        assert_eq!(applied.sections, ["control", "keys"]);
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
        assert_eq!(f.sections, ["control", "keys"]);
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
        crate::nofollow::remove_any(&d.join("state"));
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
            assert!(e.contains("no section defines"), "{bad}: {e}");
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
        assert!(e.contains("upstream"), "{e}");
        assert!(g(true, true, &[], true, true, true).is_err());
        // without keys: no gate for a caller of this site
        assert!(g(false, false, &[], false, false, false).is_ok());
        // keys byte for byte this broker's: still the host's switch and the
        // passphrase, no replace_keys
        let e = g(false, true, &[], false, true, true).unwrap_err();
        assert!(e.contains("export_secrets"), "{e}");
        let e = g(false, true, &[], true, false, true).unwrap_err();
        assert!(e.contains("passphrase"), "{e}");
        assert!(g(false, true, &[], true, true, false).is_ok());
        // the same CA, another key file: replace_keys, and it is named
        let e = g(false, true, &differ, true, true, false).unwrap_err();
        assert!(
            e.contains("replace_keys") && e.contains("secrets.bin"),
            "{e}"
        );
        assert!(g(false, true, &differ, false, true, true).is_err());
        assert!(g(false, true, &differ, true, false, true).is_err());
        assert!(g(false, true, &differ, true, true, true).is_ok());
        // another CA
        let e = g(false, true, &ca, true, true, false).unwrap_err();
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
        let (sealed, key) = format::Sealing::Passphrase(PASS).start().unwrap();
        let key = key.unwrap();
        let src = dir.join("crafted-src");
        std::fs::create_dir_all(&src).unwrap();
        let mut sections: Vec<format::StagedSection> = Vec::new();
        for (i, (path, data, seal)) in files.iter().enumerate() {
            let source = src.join(i.to_string());
            let stored = if *seal {
                format::seal_bytes(&key, path, data)
            } else {
                data.to_vec()
            };
            std::fs::write(&source, stored).unwrap();
            let name = path.split('/').next().unwrap();
            let staged = format::Staged {
                path: (*path).to_owned(),
                source,
                sealed: *seal,
                exec: false,
            };
            match sections.iter_mut().find(|s| s.name == name) {
                Some(s) => s.files.push(staged),
                None => sections.push(format::StagedSection {
                    name: name.to_owned(),
                    info: Default::default(),
                    files: vec![staged],
                }),
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
            assert!(e.contains("no section defines"), "{stray}: {e}");
        }
        assert!(!d.join("links/a").exists() && !d.join(PENDING).exists());
        assert!(!d.join(PENDING_TMP).exists() && !d.join("wyrmd.json5").exists());
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
            .stage_replace(&mut r, &c, &["keys".to_owned()], false, "user:a")
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
        ctl.stage_replace(&mut r, &c, &["links".to_owned()], false, "user:a")
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
            ctl.stage_replace(&mut r, &c, &["packages".to_owned()], accept, "user:a")
        };
        // an entry outside the package: the validator of every install
        let e = stage(&manifest("../../../../bin/sh"), true).unwrap_err();
        assert!(e.contains("package demo of the backup"), "{e}");
        // its grant is shown and nothing is staged without accept
        let e = stage(&manifest("bin/run"), false).unwrap_err();
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
}
