//! Restore from a backup file (ADR 0048 §3.5, §3.6).
//!
//! * A file comes in parts, as ADR 0028: `sys/backups/~act/restore_begin
//!   {size}` → `{upload, part_size}`, `restore_part {upload, offset, data}`
//!   (in order, up to 16 MiB each) → `{received}`, `restore_abort`. It is
//!   kept in `data_dir/backups/.upload-<id>` until it is used or an hour
//!   passed without a part.
//! * `sys/links/~act/install_backup {upload | file, id?, accept,
//!   passphrase?}` installs the link of a `.wyrm-link`: under its own id or
//!   a new one, on this broker or another. An existing link of that id is
//!   replaced in place, after a restore point of it is taken.
//!
//! Nothing of a file is used before the whole of it is checked against its
//! manifest, and nothing sealed without the key that proves the manifest
//! authentic (`wyrm_admin::backup`).

use super::backups::{
    broker_made_secret, io_err, link_prefix, make_private_dir, passphrase_arg, uint_arg, StageDir,
};
use super::*;
use crate::backup::{self as format, Kind, Manifest};
use zeroize::Zeroizing;

/// Largest file taken in parts.
pub const MAX_UPLOAD: u64 = 64 << 30;
/// Largest link backup installed.
pub const MAX_LINK_BACKUP: u64 = 8 << 30;
/// Uploads open at once.
const MAX_UPLOADS: usize = 2;
/// An upload nobody added to for this long is removed.
const UPLOAD_STALE_S: u64 = 3600;

/// A file being uploaded in parts into `data_dir/backups/.upload-<id>`.
pub struct Upload {
    pub size: u64,
    /// Bytes written so far: the offset of the next part.
    pub received: u64,
    /// Unix seconds of the last part.
    pub touched: u64,
    /// Used by a restore that runs now: not removed as stale.
    pub busy: bool,
}

/// What a `.wyrm-link` holds, read and checked, its files opened into a
/// private stage directory (removed with this value).
pub(super) struct LinkRestore {
    pub manifest: Manifest,
    pub def: LinkDef,
    /// The package of the backup, checked and unpacked as any install's.
    pub package: Option<packages::Unpacked>,
    /// The link's secrets (`data`), without the broker-made ones.
    pub secrets: BTreeMap<String, Zeroizing<Vec<u8>>>,
    pub has_data: bool,
    /// Files of the link's private directory, relative to it.
    pub files: Vec<String>,
    /// History pages in the stage directory.
    pub history: Vec<PathBuf>,
    stage: StageDir,
}

/// Where the parts of one link are in a backup.
pub(super) struct LinkLayout {
    /// The `link.cbor`.
    pub settings: String,
    /// `<base>/secrets` and `<base>/files/**`.
    pub data: Option<String>,
    /// `<base>/files/**`, the package's files.
    pub package: Option<String>,
    /// Prefix of the history pages.
    pub history: Option<String>,
}

impl LinkLayout {
    /// A `.wyrm-link`.
    fn link(m: &Manifest) -> Self {
        let has = |s: &str| m.section(s).is_some();
        Self {
            settings: "settings/link.cbor".into(),
            data: has("data").then(|| "data".to_owned()),
            package: has("package").then(|| "package".to_owned()),
            history: has("history").then(|| "history/".to_owned()),
        }
    }

    /// The link `id` of a broker backup, with its package `package` when
    /// the backup holds it.
    pub(super) fn in_broker(m: &Manifest, id: &str, package: Option<&str>) -> Self {
        let listed = |p: String| {
            m.sections
                .iter()
                .any(|s| s.files.iter().any(|f| f.path == p))
        };
        Self {
            settings: format!("links/{id}/link.cbor"),
            data: listed(format!("links/{id}/secrets")).then(|| format!("links/{id}")),
            package: package
                .filter(|n| listed(format!("packages/{n}/files/{}", packages::MANIFEST)))
                .map(|n| format!("packages/{n}")),
            history: None,
        }
    }
}

impl LinkRestore {
    fn files_dir(&self) -> PathBuf {
        self.stage.0.join("files")
    }

    fn package_dir(&self) -> PathBuf {
        self.stage.0.join("package")
    }
}

impl Control {
    fn upload_path(&self, id: &str) -> PathBuf {
        self.backups_dir().join(format!(".upload-{id}"))
    }

    fn uploads(&self) -> std::sync::MutexGuard<'_, BTreeMap<String, Upload>> {
        self.backups()
            .uploads
            .lock()
            .unwrap_or_else(|p| p.into_inner())
    }

    /// Start an upload of `size` bytes; its id.
    fn upload_begin(&self, size: u64) -> Result<String, LinkError> {
        if size == 0 || size > MAX_UPLOAD {
            return Err(LinkError::invalid_parameter(format!(
                "size: 1 to {MAX_UPLOAD} bytes"
            )));
        }
        if let Some(free) = disk_free_mib(&self.cfg.data_dir) {
            // the file, and what is opened out of it
            let want = (size.saturating_mul(2) + (64 << 20)) as f64 / f64::from(1 << 20);
            if free < want {
                return Err(LinkError::new(
                    Status::ResourceExhausted,
                    format!("the file needs about {want:.0} MiB on the disk of data_dir, {free:.0} MiB are free"),
                ));
            }
        }
        make_private_dir(&self.backups_dir()).map_err(LinkError::internal)?;
        let mut r = [0u8; 8];
        getrandom::fill(&mut r).map_err(|e| LinkError::internal(format!("no randomness: {e}")))?;
        let id = hex::encode(r);
        let mut ups = self.uploads();
        if ups.len() >= MAX_UPLOADS {
            return Err(LinkError::new(
                Status::Busy,
                format!("{MAX_UPLOADS} uploads are open; finish or abort one"),
            ));
        }
        let path = self.upload_path(&id);
        secret::write_private(&path, &[]).map_err(|e| LinkError::internal(io_err(&path, e)))?;
        ups.insert(
            id.clone(),
            Upload {
                size,
                received: 0,
                touched: now_s(),
                busy: false,
            },
        );
        Ok(id)
    }

    /// The next part of an upload; the bytes held after it.
    fn upload_part(&self, id: &str, offset: u64, data: &[u8]) -> Result<u64, LinkError> {
        use std::io::Write;
        if data.is_empty() || data.len() as u64 > backups::MAX_PART {
            return Err(LinkError::invalid_parameter(format!(
                "data: 1 to {} bytes",
                backups::MAX_PART
            )));
        }
        let mut ups = self.uploads();
        let up = ups
            .get_mut(id)
            .ok_or_else(|| LinkError::not_found(format!("upload {id}")))?;
        if offset != up.received {
            return Err(LinkError::new(
                Status::OutOfRange,
                format!("offset {offset}: the next part starts at {}", up.received),
            ));
        }
        if up.received + data.len() as u64 > up.size {
            return Err(LinkError::new(
                Status::OutOfRange,
                format!("more than the {} bytes of restore_begin", up.size),
            ));
        }
        let path = self.upload_path(id);
        let internal = |e: std::io::Error| LinkError::internal(io_err(&path, e));
        let mut f = std::fs::OpenOptions::new()
            .append(true)
            .open(&path)
            .map_err(internal)?;
        f.write_all(data).map_err(internal)?;
        f.sync_data().map_err(internal)?;
        up.received += data.len() as u64;
        up.touched = now_s();
        Ok(up.received)
    }

    /// The file of a complete upload, marked in use.
    pub(super) fn upload_take(&self, id: &str) -> Result<PathBuf, LinkError> {
        let mut ups = self.uploads();
        let up = ups
            .get_mut(id)
            .ok_or_else(|| LinkError::not_found(format!("upload {id}")))?;
        if up.received != up.size {
            return Err(LinkError::invalid_parameter(format!(
                "upload {id}: {} of {} bytes received",
                up.received, up.size
            )));
        }
        if up.busy {
            return Err(LinkError::new(Status::Busy, "the upload is in use"));
        }
        up.busy = true;
        up.touched = now_s();
        Ok(self.upload_path(id))
    }

    /// Let an upload go: `remove` deletes it, else it may be used again.
    pub(super) fn upload_release(&self, id: &str, remove: bool) {
        let mut ups = self.uploads();
        if remove {
            ups.remove(id);
            let _ = std::fs::remove_file(self.upload_path(id));
        } else if let Some(up) = ups.get_mut(id) {
            up.busy = false;
            up.touched = now_s();
        }
    }

    /// Remove uploads nobody touched for an hour.
    pub(super) fn drop_stale_uploads(&self) {
        let now = now_s();
        let mut ups = self.uploads();
        let stale: Vec<String> = ups
            .iter()
            .filter(|(_, u)| !u.busy && u.touched + UPLOAD_STALE_S < now)
            .map(|(id, _)| id.clone())
            .collect();
        for id in stale {
            ups.remove(&id);
            let _ = std::fs::remove_file(self.upload_path(&id));
        }
    }

    /// The key of a backup read here: `None` for one without sealed files.
    pub(super) fn backup_key(
        &self,
        manifest: &Manifest,
        passphrase: Option<&[u8]>,
    ) -> Result<Option<format::MasterKey>, String> {
        if manifest.sealed.how == "none" {
            return Ok(None);
        }
        let secrets_key = secret::load_or_create_key(&self.cfg.data_dir.join("secrets.key"))
            .map_err(|e| format!("secrets.key: {e}"))?;
        manifest.key(passphrase, Some(&secrets_key)).map(Some)
    }

    /// Read the link backup at `path`: every file checked, the manifest
    /// proved authentic with the key (`passphrase`, or this broker's for a
    /// restore point), its files opened into a stage directory. Blocking.
    pub(super) fn read_link_backup(
        &self,
        path: &Path,
        passphrase: Option<&[u8]>,
    ) -> Result<LinkRestore, String> {
        let mut r = format::Reader::open(path, MAX_LINK_BACKUP)?;
        let manifest = r.manifest().clone();
        if manifest.kind != Kind::Link {
            return Err("a broker backup: restore it from System, not as a link".into());
        }
        r.verify(|_, _| {})?;
        let key = self.backup_key(&manifest, passphrase)?;
        let key = key.as_ref();
        self.read_link_parts(&mut r, key, &LinkLayout::link(&manifest))
    }

    /// The link whose files are laid out as `lay` says in the backup `r`
    /// (already verified), opened into a stage directory.
    pub(super) fn read_link_parts<R: std::io::Read + std::io::Seek>(
        &self,
        r: &mut format::Reader<R>,
        key: Option<&format::MasterKey>,
        lay: &LinkLayout,
    ) -> Result<LinkRestore, String> {
        let manifest = r.manifest().clone();
        let paths: Vec<String> = manifest
            .sections
            .iter()
            .flat_map(|s| s.files.iter().map(|f| f.path.clone()))
            .collect();
        let def: LinkDef = minicbor::decode(&r.read(&lay.settings)?)
            .map_err(|e| format!("{}: {e}", lay.settings))?;
        crate::registry::validate_link_id(&def.id)?;
        let backups = self.backups_dir();
        make_private_dir(&backups)?;
        let stage = StageDir::new(&backups)?;
        let mut out = LinkRestore {
            manifest: manifest.clone(),
            def,
            package: None,
            secrets: BTreeMap::new(),
            has_data: false,
            files: Vec::new(),
            history: Vec::new(),
            stage,
        };
        if let Some(base) = &lay.data {
            out.has_data = true;
            let secrets = format!("{base}/secrets");
            let plain = r.read_plain(&secrets, key)?;
            let Value::Map(m) =
                wyrm_core::codec::from_slice::<Value>(&plain).map_err(|e| e.to_string())?
            else {
                return Err(format!("{secrets}: not a map"));
            };
            for (name, v) in m {
                if let (Value::Bytes(b), false) = (v, broker_made_secret(&name)) {
                    out.secrets.insert(name, Zeroizing::new(b));
                }
            }
            let prefix = format!("{base}/files/");
            for path in &paths {
                if let Some(rel) = path.strip_prefix(&prefix) {
                    r.extract(path, &out.files_dir().join(rel), key)?;
                    out.files.push(rel.to_owned());
                }
            }
        }
        if let Some(base) = &lay.package {
            let prefix = format!("{base}/files/");
            for path in &paths {
                if let Some(rel) = path.strip_prefix(&prefix) {
                    r.extract(path, &out.package_dir().join(rel), None)?;
                }
            }
            // Nothing of the backup says what the package is: its files go
            // through the validator of every install (entry inside the
            // package, requester grants, world and capabilities), which
            // builds the record.
            let source = format!("backup {}@{}", out.def.id, manifest.site);
            out.package = Some(checked_package(
                &out.package_dir(),
                &self.packages_root(),
                &source,
            )?);
        }
        if let Some(prefix) = &lay.history {
            for (i, path) in paths.iter().filter(|p| p.starts_with(prefix)).enumerate() {
                let dest = out.stage.0.join("history").join(format!("{i:05}.cbor"));
                r.extract(path, &dest, None)?;
                out.history.push(dest);
            }
        }
        Ok(out)
    }

    /// Put the secrets and the private files of a link backup in place for
    /// the link `id`, which must be stopped: its secrets are set (the
    /// broker-made ones stay as they are), its `data` directory is replaced.
    fn place_link_data(&self, id: &str, r: &LinkRestore) -> Result<(), String> {
        if !r.has_data {
            return Ok(());
        }
        for (name, v) in &r.secrets {
            self.secrets
                .set(id, name, v)
                .map_err(|e| format!("secret {name}: {e}"))?;
        }
        // The new directory is built beside the old one and swapped in with
        // two renames: on a failure the link's data stays as it was. Every
        // directory and file is made new and no symlink is followed
        // (`crate::nofollow`): what the link left under these names is
        // removed as what it is, never written through.
        let data = self.link_data_dir(id).map_err(|e| e.message)?;
        let parent = data
            .parent()
            .ok_or_else(|| format!("{}: no parent", data.display()))?;
        let (fresh, old) = (parent.join("data.restoring"), parent.join("data.replaced"));
        crate::nofollow::remove_any(&fresh);
        crate::nofollow::remove_any(&old);
        crate::nofollow::new_private_dir(&fresh)?;
        let filled = (|| {
            for rel in &r.files {
                let rel_path = Path::new(rel);
                let name = rel_path
                    .file_name()
                    .ok_or_else(|| format!("unsafe path {rel}"))?;
                let dir =
                    crate::nofollow::make_dirs(&fresh, rel_path.parent().unwrap_or(Path::new("")))?;
                let (from, to) = (r.files_dir().join(rel), dir.join(name));
                // the stage is on the same disk; a copy when it is not
                if std::fs::rename(&from, &to).is_err() {
                    let mut src = std::fs::File::open(&from).map_err(|e| io_err(&from, e))?;
                    let mut dst =
                        crate::nofollow::create_new(&to, None).map_err(|e| io_err(&to, e))?;
                    std::io::copy(&mut src, &mut dst).map_err(|e| io_err(&to, e))?;
                    dst.sync_all().map_err(|e| io_err(&to, e))?;
                }
            }
            Ok::<(), String>(())
        })();
        if let Err(e) = filled {
            let _ = std::fs::remove_dir_all(&fresh);
            return Err(e);
        }
        std::fs::rename(&data, &old).map_err(|e| io_err(&data, e))?;
        if let Err(e) = std::fs::rename(&fresh, &data) {
            let _ = std::fs::rename(&old, &data);
            let _ = std::fs::remove_dir_all(&fresh);
            return Err(io_err(&data, e));
        }
        let _ = std::fs::remove_dir_all(&old);
        // the framework tree is bound to its link's id: under a new id it
        // is sealed again for it, with the store key that came with it
        let tree = data.join(wyrm_link_sdk::driver::persist::TREE_FILE);
        if id != r.def.id && tree.is_file() {
            let key = r
                .secrets
                .get(wyrm_link_sdk::driver::persist::STORE_KEY)
                .and_then(|k| <[u8; 32]>::try_from(&k[..]).ok())
                .map(Zeroizing::new)
                .ok_or("the backup holds a framework tree without its store key")?;
            let sealed = std::fs::read(&tree).map_err(|e| io_err(&tree, e))?;
            let bound = wyrm_link_sdk::driver::persist::rebind(&sealed, &key, &r.def.id, id)
                .ok_or("the framework tree of the backup does not open with its store key")?;
            secret::write_private(&tree, &bound).map_err(|e| io_err(&tree, e))?;
        }
        Ok(())
    }

    /// Give the stopped link `id` the private data and secrets of the link
    /// backup at `path` (a restore point this broker made, or any backup
    /// sealed for it): what a package rollback needs (ADR 0048 §1.6). The
    /// link's definition, grants and package are not touched. Blocking; the
    /// caller stops the link before and starts it after.
    pub fn link_restore_data(&self, id: &str, path: &Path) -> Result<(), String> {
        if !self.registry().links.contains_key(id) {
            return Err(format!("no link {id}"));
        }
        let r = self.read_link_backup(path, None)?;
        if !r.has_data {
            return Err(format!("{}: no private data in it", path.display()));
        }
        self.place_link_data(id, &r)
    }

    /// Write the history rows of a link backup under the link `id`. Returns
    /// the rows written.
    fn place_link_history(&self, id: &str, r: &LinkRestore) -> Result<u64, String> {
        let store = self.history.store();
        let prefix = link_prefix(&self.cfg.site, id);
        let mut total = 0u64;
        for page in &r.history {
            let bytes = std::fs::read(page).map_err(|e| io_err(page, e))?;
            let Value::Array(rows) =
                wyrm_core::codec::from_slice::<Value>(&bytes).map_err(|e| e.to_string())?
            else {
                return Err("history: a page is not a list".into());
            };
            let mut batch = Vec::with_capacity(rows.len());
            for row in rows {
                let Value::Array(mut f) = row else {
                    return Err("history: a row is not a list".into());
                };
                if f.len() != 4 {
                    return Err("history: a row of 4 fields".into());
                }
                let (Some(Value::UInt(q)), Some(v), Some(Value::UInt(t)), Some(Value::Str(rel))) =
                    (f.pop(), f.pop(), f.pop(), f.pop())
                else {
                    return Err("history: a row is [key, t, v, q]".into());
                };
                wyrm_core::keyspace::validate_path(&rel)
                    .map_err(|e| format!("history: key {rel:?}: {e}"))?;
                let q = u8::try_from(q)
                    .ok()
                    .and_then(|q| Quality::try_from(q).ok())
                    .ok_or("history: quality")?;
                let series = store
                    .series_id(&format!("{prefix}{rel}"), true)
                    .map_err(|e| e.to_string())?
                    .ok_or("history: no series")?;
                batch.push((series, t, wyrm_history::encode_row(&v, q)));
            }
            total += store.write(&batch).map_err(|e| e.to_string())? as u64;
        }
        Ok(total)
    }
}

/// The files of a package that came in a backup, through the validator of
/// every install ([`packages::unpack`]): packed again as a zip, then checked
/// and unpacked beside the installed packages of `root`.
fn checked_package(dir: &Path, root: &Path, source: &str) -> Result<packages::Unpacked, String> {
    let zip = packages::repack(dir)?;
    packages::unpack(&zip, root, source, now_s())
        .map_err(|e| format!("the package of the backup: {e}"))
}

/// What a package of a backup asks for, as `install_*` shows it: the
/// network of its capabilities and its requester grants. One list for
/// `install_backup` and for the broker restore.
pub(super) fn package_asks(p: &packages::Unpacked) -> Vec<String> {
    let mut asks = Vec::new();
    if let Some(c) = p.app.as_ref().filter(|c| !c.net.is_empty()) {
        asks.push(format!(
            "package {}: network {}",
            p.def.name,
            c.net.join(", ")
        ));
    }
    for (path, code) in &p.def.requester {
        let level = Perm::try_from(*code).map_or("?", |p| p.name());
        asks.push(format!("package {}: {level} on {path}", p.def.name));
    }
    asks
}

/// What a link backup asks for that an installer must have seen: the
/// link's requester grants and network allowlist and, for a package this
/// install brings (`package`), the grants and the network its manifest
/// asks for, as `install_*` shows them.
fn asks_of(def: &LinkDef, package: Option<&packages::Unpacked>) -> Vec<String> {
    let mut asks = package.map(package_asks).unwrap_or_default();
    if let Value::Map(m) = decode_params(&def.params) {
        if let Some(Value::Str(net)) = m
            .get("net")
            .filter(|v| matches!(v, Value::Str(s) if !s.is_empty()))
        {
            asks.push(format!("network {net}"));
        }
    }
    for (path, code) in &def.grants {
        let level = Perm::try_from(*code).map_or("?", |p| p.name());
        asks.push(format!("{level} on {path}"));
    }
    asks
}

impl Admin {
    /// `sys/links/~act/install_backup`: `Err` is the message of `success: false`.
    pub(super) async fn install_backup(&self, args: &Value, sub: &str) -> Result<String, String> {
        let ctl = &self.ctl;
        let passphrase = passphrase_arg(args).map_err(|e| e.message)?;
        let upload = arg_str(args, "upload").filter(|u| !u.is_empty());
        // the file: an upload in parts, or the bytes themselves
        let (path, _tmp) = match (upload, arg(args, "file")) {
            (Some(id), _) => (ctl.upload_take(id).map_err(|e| e.message)?, None),
            (None, Some(Value::Bytes(b))) => {
                make_private_dir(&ctl.backups_dir())?;
                let tmp = StageDir::new(&ctl.backups_dir())?;
                let p = tmp.0.join("file");
                std::fs::write(&p, b).map_err(|e| io_err(&p, e))?;
                (p, Some(tmp))
            }
            _ => return Err("file or upload: required".into()),
        };
        let r = self.install_backup_from(&path, args, passphrase, sub).await;
        if let Some(id) = upload {
            // a refused file can be tried again (another passphrase, accept)
            ctl.upload_release(id, r.is_ok());
        }
        r
    }

    async fn install_backup_from(
        &self,
        path: &Path,
        args: &Value,
        passphrase: Option<Zeroizing<Vec<u8>>>,
        sub: &str,
    ) -> Result<String, String> {
        let ctl = &self.ctl;
        let r = {
            let (ctl, path) = (ctl.clone(), path.to_owned());
            tokio::task::spawn_blocking(move || {
                ctl.read_link_backup(&path, passphrase.as_deref().map(|p| &p[..]))
            })
            .await
            .map_err(|e| e.to_string())??
        };
        let id = match arg_str(args, "id").map(str::trim).filter(|i| !i.is_empty()) {
            Some(i) => i.to_owned(),
            None => r.def.id.clone(),
        };
        self.install_restored(r, id, accepted(args), sub).await
    }

    /// Install the link read from a backup as `id` (see the module
    /// documentation): a new link, or an existing one replaced in place.
    pub(super) async fn install_restored(
        &self,
        mut r: LinkRestore,
        id: String,
        accept: bool,
        sub: &str,
    ) -> Result<String, String> {
        let ctl = &self.ctl;
        crate::registry::validate_link_id(&id)?;
        let existing = ctl.registry().links.get(&id).cloned();
        if existing.is_none() {
            // a new link: the ids a broker keeps for itself are refused
            crate::registry::validate_new_link_id(&id)?;
        }
        // what the package asks for counts when this install brings it, or
        // makes a new link of it
        let brings = r
            .package
            .as_ref()
            .filter(|p| existing.is_none() || !ctl.registry().packages.contains_key(&p.def.name));
        let asks = asks_of(&r.def, brings);
        if !asks.is_empty() && !accept {
            return Err(format!(
                "the link {} of the backup asks for: {}. Nothing is installed: read them, then \
                 install again with Accept Requested Rights",
                r.def.id,
                asks.join("; ")
            ));
        }
        let from = format!("{}@{} of {}", r.def.id, r.manifest.site, r.manifest.created);
        if let Some(old) = &existing {
            if old.origin == Origin::Config {
                return Err(format!("link {id} is defined in wyrmd.json5: not replaced"));
            }
            if old.driver != r.def.driver || old.mode != r.def.mode {
                return Err(format!(
                    "link {id} exists and runs {} ({}); the backup is of {} ({})",
                    old.driver,
                    old.mode.name(),
                    r.def.driver,
                    r.def.mode.name()
                ));
            }
        }
        // The definition of the backup is checked as a new link's is, before
        // anything is stopped or written: params (no secret in them, the
        // driver takes them), every grant (`check_grant`), the id.
        let params = decode_params(&r.def.params);
        crate::secrets::lint_params(&params, "params")?;
        if r.def.driver == AGENT_DRIVER {
            check_agent_refs(&params).map_err(|e| e.message)?;
        }
        let packaged = r.def.driver.starts_with(packages::DRIVER_PREFIX);
        if r.def.mode != Mode::External && !packaged {
            if !ctl.host.drivers().contains(&r.def.driver.as_str()) {
                return Err(format!(
                    "driver {} is not built into this broker",
                    r.def.driver
                ));
            }
            ctl.host
                .validate(&r.def.driver, &params)
                .map_err(|e| e.message)?;
        }
        for (path, code) in &r.def.grants {
            let level = Perm::try_from(*code).map_err(|c| format!("grant level {c}"))?;
            crate::registry::check_grant(path, level).map_err(|e| format!("grant: {e}"))?;
        }
        if ctl.peers().downstream.contains(&id) || ctl.cfg.operators.contains(&id) {
            return Err(format!(
                "link id {id:?} is a downstream site or an operator of this broker"
            ));
        }
        let mut message = match self.backup_package(&mut r, sub).await? {
            Some(m) => format!("{m}; "),
            None => String::new(),
        };
        match &existing {
            Some(old) => {
                // a way back first (ADR 0048 §3.5): a restore point like the
                // one of a package update, listed and pruned with them. The
                // link was not asked for its keys: a restore has no health
                // check.
                let (package, version) = match old.driver.strip_prefix(packages::DRIVER_PREFIX) {
                    Some(name) => (
                        name.to_owned(),
                        ctl.registry()
                            .packages
                            .get(name)
                            .map(|p| p.version.clone())
                            .unwrap_or_default(),
                    ),
                    None => (String::new(), String::new()),
                };
                let point = self
                    .take_restore_point(&id, &package, &version, None, sub)
                    .await?;
                message.push_str(&format!("restore point {}; ", point.id));
                if old.mode != Mode::External {
                    self.stop_link(&id, sub).await.map_err(|e| e.message)?;
                }
                if old.params != r.def.params {
                    ctl.apply(Op::Update {
                        id: id.clone(),
                        mode: old.mode,
                        params: r.def.params.clone(),
                    })
                    .map_err(|e| e.to_string())?;
                }
            }
            None => {
                let install = Value::Map(BTreeMap::from([
                    ("id".to_owned(), Value::Str(id.clone())),
                    ("driver".to_owned(), Value::Str(r.def.driver.clone())),
                    ("mode".to_owned(), Value::Str(r.def.mode.name().to_owned())),
                    ("params".to_owned(), params),
                ]));
                let reply = self.install(&install, sub).await.map_err(|e| e.message)?;
                if let Some(Value::Map(m)) = reply {
                    // an external link: its token is shown once, here
                    if let Some(Value::Str(t)) = m.get("token") {
                        message.push_str(&format!("token {t}; "));
                    }
                }
                if r.def.mode != Mode::External && r.has_data {
                    self.stop_link(&id, sub).await.map_err(|e| e.message)?;
                }
            }
        }
        // the private data and secrets while the link is stopped
        let (placed, rows) = {
            let (ctl, id2) = (ctl.clone(), id.clone());
            tokio::task::spawn_blocking(move || {
                let placed = ctl.place_link_data(&id2, &r);
                let rows = match &placed {
                    Ok(()) => ctl.place_link_history(&id2, &r),
                    Err(_) => Ok(0),
                };
                (placed.map(|()| r), rows)
            })
            .await
            .map_err(|e| e.to_string())?
        };
        let r = placed?;
        let mut grants = false;
        for (path, code) in &r.def.grants {
            let level = Perm::try_from(*code).map_err(|c| format!("level {c}"))?;
            grants |= self
                .set_grant(&id, path, level, sub)
                .map_err(|e| e.message)?;
        }
        if r.def.mode != Mode::External && (existing.is_some() || r.has_data) {
            self.start_link(&id, sub).await.map_err(|e| e.message)?;
        }
        if grants {
            ctl.schedule_reload();
        }
        let sections: Vec<&str> = r
            .manifest
            .sections
            .iter()
            .map(|s| s.name.as_str())
            .collect();
        ctl.record(
            sub,
            "link_restore",
            &id,
            Status::Ok,
            &format!("from {from}; sections {}", sections.join(", ")),
        );
        message.push_str(&format!(
            "link {id} {} from the backup of {from}",
            if existing.is_some() {
                "replaced"
            } else {
                "installed"
            }
        ));
        match rows {
            Ok(0) => {}
            Ok(n) => message.push_str(&format!("; {n} history rows")),
            Err(e) => message.push_str(&format!("; history not restored: {e}")),
        }
        Ok(message)
    }

    /// The package of a link backup on this broker: the installed one when
    /// it is the same, installed from the backup when there is none.
    async fn backup_package(
        &self,
        r: &mut LinkRestore,
        sub: &str,
    ) -> Result<Option<String>, String> {
        let ctl = &self.ctl;
        let Some(name) = r.def.driver.strip_prefix(packages::DRIVER_PREFIX) else {
            if r.def.mode != Mode::External && !ctl.host.drivers().contains(&r.def.driver.as_str())
            {
                return Err(format!(
                    "driver {} is not built into this broker",
                    r.def.driver
                ));
            }
            return Ok(None);
        };
        let name = name.to_owned();
        let installed = ctl.registry().packages.get(&name).cloned();
        let root = ctl.packages_root();
        match (installed, r.package.take()) {
            (Some(i), Some(p)) if i.version == p.def.version => {
                // the same files as the installed ones, or it is another package
                let here = packages::repack(&packages::dir(&root, &i))?;
                if wyrm_link_sdk::package::sha256_hex(&here) != p.def.sha256 {
                    return Err(format!(
                        "package {name} {} is installed here with other content than the \
                         backup holds",
                        i.version
                    ));
                }
                Ok(None)
            }
            (Some(i), Some(p)) => Err(format!(
                "package {name} {} is installed here; the backup holds {}. One version per \
                 package: update or roll back the package first, or restore the backup \
                 without its package section",
                i.version, p.def.version
            )),
            (Some(i), None) => Ok(Some(format!(
                "package {name} {} of this broker is used",
                i.version
            ))),
            (None, None) => Err(format!(
                "package {name} is not installed here and the backup does not hold it"
            )),
            (None, Some(p)) => {
                // as `install_package` does with a package that came as a
                // zip: the record is the validator's, never the backup's
                let (def, app) = (p.def.clone(), p.app.clone());
                if def.name != name {
                    return Err(format!(
                        "the backup holds package {}, the link runs {name}",
                        def.name
                    ));
                }
                if def.kind == PackageKind::Process && ctl.cfg.link_endpoint.is_none() {
                    return Err("process links need a tls/ listener on the broker".into());
                }
                p.commit(&root)?;
                if def.kind == PackageKind::Wasm {
                    ctl.publish_component(&def)?;
                }
                ctl.apply(Op::PutPackage(def.clone()))
                    .map_err(|e| e.to_string())?;
                ctl.record(
                    sub,
                    "package_install",
                    &def.name,
                    Status::Ok,
                    &install_detail(&def, app.as_ref()),
                );
                declare_package(&self.ctx, ctl, &def)
                    .await
                    .map_err(|e| e.to_string())?;
                Ok(Some(format!(
                    "package {} {} installed from the backup",
                    def.name, def.version
                )))
            }
        }
    }
}

/// The upload actions of `sys/backups` and `install_backup` of `sys/links`.
pub(super) async fn declare(ctx: &LinkCtx) -> wyrm_link_sdk::Result<()> {
    let upload = || {
        str_param()
            .required(true)
            .display("Upload")
            .description("The id restore_begin gave")
    };
    ctx.declare_action(
        "backups",
        "restore_begin",
        ActionMeta::new()
            .display("Upload a backup")
            .param(
                "size",
                ParamMeta::of(TypeCode::Number)
                    .required(true)
                    .display("Size (bytes)"),
            )
            .result(ActionResult::Type(TypeCode::Map))
            .level(Perm::Config),
    )
    .await?;
    ctx.declare_action(
        "backups",
        "restore_part",
        ActionMeta::new()
            .display("Upload part")
            .param("upload", upload())
            .param(
                "offset",
                ParamMeta::of(TypeCode::Number)
                    .required(true)
                    .display("Offset (bytes)"),
            )
            .param(
                "data",
                ParamMeta::of(TypeCode::Binary)
                    .required(true)
                    .display("Data")
                    .description("The next part, at most 16 MiB"),
            )
            .result(ActionResult::Type(TypeCode::Map))
            .timeout_ms(60_000)
            .level(Perm::Config),
    )
    .await?;
    ctx.declare_action(
        "backups",
        "restore_abort",
        ActionMeta::new()
            .display("Abort upload")
            .param("upload", upload())
            .level(Perm::Config),
    )
    .await?;
    ctx.declare_action(
        "links",
        "install_backup",
        install_meta("From backup")
            .param(
                "file",
                ParamMeta::of(TypeCode::Binary)
                    .display("Backup file")
                    .editor(EDITOR_FILE)
                    .description("A .wyrm-link file; or upload it in parts and give Upload"),
            )
            .param(
                "upload",
                str_param()
                    .display("Upload")
                    .description("The id of a file uploaded with sys/backups restore_begin"),
            )
            .param(
                "id",
                str_param()
                    .display("Link ID")
                    .description("Empty: the id in the backup. An existing link is replaced"),
            )
            .param(
                "passphrase",
                str_param()
                    .display("Passphrase")
                    .editor(EDITOR_PASSWORD)
                    .description("Of a backup that holds private data"),
            ),
    )
    .await
}

/// The restore actions of a broker backup.
pub(super) async fn declare_broker(ctx: &LinkCtx) -> wyrm_link_sdk::Result<()> {
    super::restore_broker::declare(ctx).await
}

pub(super) async fn invoke(
    ctl: &Arc<Control>,
    rest: &[&str],
    action: &str,
    args: &Value,
    _sub: &str,
) -> wyrm_link_sdk::Result<Option<Value>> {
    let upload = || {
        arg_str(args, "upload")
            .filter(|u| !u.is_empty())
            .ok_or_else(|| LinkError::invalid_parameter("upload: required"))
    };
    match (rest, action) {
        ([], "restore_begin") => {
            let size = uint_arg(args, "size")?
                .ok_or_else(|| LinkError::invalid_parameter("size: required"))?;
            let id = ctl.upload_begin(size)?;
            Ok(Some(Value::Map(BTreeMap::from([
                ("upload".to_owned(), Value::Str(id)),
                ("part_size".to_owned(), Value::UInt(backups::DEFAULT_PART)),
                ("max_part".to_owned(), Value::UInt(backups::MAX_PART)),
            ]))))
        }
        ([], "restore_part") => {
            let id = upload()?.to_owned();
            let offset = uint_arg(args, "offset")?
                .ok_or_else(|| LinkError::invalid_parameter("offset: required"))?;
            let Some(Value::Bytes(data)) = arg(args, "data") else {
                return Err(LinkError::invalid_parameter("data: required"));
            };
            let (ctl2, data) = (ctl.clone(), data.clone());
            let received =
                tokio::task::spawn_blocking(move || ctl2.upload_part(&id, offset, &data))
                    .await
                    .map_err(|e| LinkError::internal(e.to_string()))??;
            Ok(Some(Value::Map(BTreeMap::from([(
                "received".to_owned(),
                Value::UInt(received),
            )]))))
        }
        ([], "restore_abort") => {
            let id = upload()?;
            if ctl.uploads().get(id).is_some_and(|u| u.busy) {
                return Err(LinkError::new(Status::Busy, "the upload is in use"));
            }
            ctl.upload_release(id, true);
            Ok(None)
        }
        _ => Err(LinkError::not_supported(format!(
            "backups/{}/~act/{action}",
            rest.join("/")
        ))),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// ADR 0048 §1.3 with the security review of the restore point (commit
    /// 0784257): a restore point is a link backup made while the link runs.
    /// A symlink the link planted in its data is never followed (no file of
    /// the broker's goes into the point), it needs no `export_secrets`, and
    /// applying it replaces the data as a whole without writing through a
    /// symlink.
    #[cfg(unix)]
    #[test]
    fn a_restore_point_is_a_link_backup_that_follows_no_symlink() {
        use std::os::unix::fs::symlink;
        let ctl = super::super::tests::control("point-nofollow", false, |_| {});
        assert!(!ctl.cfg.backups.export_secrets);
        let d = ctl.cfg.data_dir.clone();
        ctl.apply(Op::Install(LinkDef {
            id: "l1".into(),
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
        ctl.secrets.set("l1", "password", b"pw-123456").unwrap();
        let data = d.join("links/l1/data");
        let put = |rel: &str, bytes: &[u8]| {
            let p = data.join(rel);
            std::fs::create_dir_all(p.parent().unwrap()).unwrap();
            std::fs::write(p, bytes).unwrap();
        };
        put("framework.tree", b"TREE-v1");
        put("store/p/0", b"page0");
        put("uploads/c1/spool", b"scratch");
        let outside = d.join("outside");
        std::fs::create_dir_all(&outside).unwrap();
        std::fs::write(outside.join("secret"), b"BROKER-SECRET-0123456789").unwrap();
        symlink(outside.join("secret"), data.join("leak")).unwrap();
        symlink(&outside, data.join("leakdir")).unwrap();
        symlink(d.join("state.key"), data.join("store/leak2")).unwrap();

        let keys = vec!["a".to_owned()];
        let p = ctl
            .restore_point_now("l1", "", "", Some(keys.clone()))
            .unwrap();
        assert_eq!(p.skipped, 3, "the symlinks are counted, not copied");
        assert_eq!(p.keys, keys);
        let file = crate::restore_point::file(&ctl.restore_root(), "l1", &p.id).unwrap();
        assert_eq!(p.size, std::fs::metadata(&file).unwrap().len());
        let m = format::read_manifest(&file).unwrap();
        assert_eq!((m.kind, m.sealed.how.as_str()), (Kind::Link, "broker"));
        let mut names: Vec<&str> = m
            .section("data")
            .unwrap()
            .files
            .iter()
            .map(|f| f.path.as_str())
            .collect();
        names.sort_unstable();
        assert_eq!(
            names,
            [
                "data/files/framework.tree",
                "data/files/store/p/0",
                "data/secrets"
            ]
        );
        let bytes = std::fs::read(&file).unwrap();
        assert!(!bytes.windows(13).any(|w| w == b"BROKER-SECRET"));
        assert!(!bytes.windows(9).any(|w| w == b"pw-123456"), "sealed");

        // the new version wrote over the data and left symlinks under the
        // names the swap uses; the point puts everything back as it was
        std::fs::write(data.join("framework.tree"), b"TREE-v2").unwrap();
        std::fs::remove_dir_all(data.join("store")).unwrap();
        put("v2-only", b"x");
        ctl.secrets.set("l1", "password", b"changed").unwrap();
        symlink(&outside, d.join("links/l1/data.restoring")).unwrap();
        symlink(&outside, d.join("links/l1/data.replaced")).unwrap();
        ctl.restore_point_apply("l1", &p.id).unwrap();
        assert_eq!(
            std::fs::read(data.join("framework.tree")).unwrap(),
            b"TREE-v1"
        );
        assert_eq!(std::fs::read(data.join("store/p/0")).unwrap(), b"page0");
        assert!(!data.join("v2-only").exists(), "replaced as a whole");
        assert!(!data.join("leak").exists() && !data.join("uploads").exists());
        assert_eq!(&ctl.secrets.for_link("l1")["password"][..], b"pw-123456");
        assert!(!d.join("links/l1/data.restoring").exists());
        assert!(!d.join("links/l1/data.replaced").exists());
        let left: Vec<_> = std::fs::read_dir(&outside)
            .unwrap()
            .flatten()
            .map(|e| e.file_name())
            .collect();
        assert_eq!(left, ["secret"], "nothing was written outside");
        assert_eq!(
            std::fs::read(outside.join("secret")).unwrap(),
            b"BROKER-SECRET-0123456789"
        );
        // a data directory that is itself a symlink: no point is made
        std::fs::remove_dir_all(&data).unwrap();
        symlink(&outside, &data).unwrap();
        assert!(ctl.restore_point_now("l1", "", "", None).is_err());
        assert_eq!(
            crate::restore_point::list(&ctl.restore_root(), "l1").len(),
            1
        );
        // a point of another link or a name that leaves the directory
        assert!(ctl.restore_point_apply("l1", "../x").is_err());
        assert!(ctl.restore_point_apply("nolink", &p.id).is_err());
    }

    #[test]
    fn identity_secrets_stay_with_their_broker() {
        assert!(broker_made_secret(wyrm_link_sdk::REQUESTER_KEY));
        assert!(broker_made_secret("agent_key"));
        assert!(!broker_made_secret(
            wyrm_link_sdk::driver::persist::STORE_KEY
        ));
        assert!(!broker_made_secret("password"));
    }

    #[test]
    fn a_backup_says_what_its_link_asks_for() {
        let params = Value::Map(BTreeMap::from([(
            "net".to_owned(),
            Value::from("plc.example:502"),
        )]));
        let def = LinkDef {
            id: "a".into(),
            driver: "pkg:demo".into(),
            mode: Mode::Embedded,
            params: encode_params(&params).unwrap(),
            token_hash: String::new(),
            rev: 1,
            origin: Origin::Runtime,
            created: 0,
            display: None,
            granted: None,
            log_level: None,
            grants: vec![("wy/{site}/downstream/plc".into(), Perm::Write.code())],
        };
        assert_eq!(
            asks_of(&def, None),
            [
                "network plc.example:502",
                "write on wy/{site}/downstream/plc"
            ]
        );
        let plain = LinkDef {
            params: encode_params(&Value::Map(BTreeMap::new())).unwrap(),
            grants: Vec::new(),
            ..def
        };
        assert!(asks_of(&plain, None).is_empty());
    }

    /// A package directory as a backup carries it: its manifest and files.
    fn package_dir(name: &str, manifest: serde_json::Value, files: &[(&str, &[u8])]) -> PathBuf {
        let d = std::env::temp_dir().join(format!("wyrm-restore-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(d.join("pkg")).unwrap();
        std::fs::write(d.join("pkg").join(packages::MANIFEST), manifest.to_string()).unwrap();
        for (path, data) in files {
            let p = d.join("pkg").join(path);
            std::fs::create_dir_all(p.parent().unwrap()).unwrap();
            std::fs::write(p, data).unwrap();
        }
        d
    }

    fn manifest(entry: &str, requester: serde_json::Value) -> serde_json::Value {
        serde_json::json!({
            "name": "demo",
            "version": "1.0.0",
            "description": "d",
            "wyrm_link": wyrm_link_sdk::LINK_PROTOCOL,
            "kind": "process",
            "entries": { packages::platform(): entry },
            "requester": requester,
        })
    }

    #[test]
    fn a_package_of_a_backup_passes_the_validator_of_an_install() {
        let none = serde_json::json!([]);
        // a good one: the record comes from the manifest, and what it asks
        // for is shown
        let grants = serde_json::json!([{ "path": "wy/{site}/downstream/plc", "level": "write" }]);
        let d = package_dir(
            "ok",
            manifest("bin/run", grants),
            &[("bin/run", b"#!/bin/sh\n")],
        );
        let p = checked_package(&d.join("pkg"), &d.join("root"), "backup x@s").unwrap();
        assert_eq!(
            (p.def.name.as_str(), p.def.version.as_str()),
            ("demo", "1.0.0")
        );
        assert_eq!(p.def.entry, "bin/run");
        assert_eq!(p.def.source, "backup x@s");
        let def = LinkDef {
            id: "a".into(),
            driver: "pkg:demo".into(),
            mode: Mode::Process,
            params: encode_params(&Value::Null).unwrap(),
            token_hash: String::new(),
            rev: 1,
            origin: Origin::Runtime,
            created: 0,
            display: None,
            granted: None,
            log_level: None,
            grants: Vec::new(),
        };
        assert_eq!(
            asks_of(&def, Some(&p)),
            ["package demo: write on wy/{site}/downstream/plc"]
        );
        // the same files give the same SHA-256, other files another
        let again = packages::repack(&d.join("pkg")).unwrap();
        assert_eq!(wyrm_link_sdk::package::sha256_hex(&again), p.def.sha256);
        std::fs::write(d.join("pkg/bin/run"), b"#!/bin/sh\nrm -rf /\n").unwrap();
        let other = packages::repack(&d.join("pkg")).unwrap();
        assert_ne!(wyrm_link_sdk::package::sha256_hex(&other), p.def.sha256);

        // an entry outside the package, with a file there to find
        let d = package_dir(
            "escape",
            manifest("../evil", none.clone()),
            &[("bin/run", b"x")],
        );
        std::fs::write(d.join("evil"), b"x").unwrap();
        let e = checked_package(&d.join("pkg"), &d.join("root"), "s")
            .err()
            .unwrap();
        assert!(e.contains("not a file of the package"), "{e}");
        // an entry that is not among the files
        let d = package_dir(
            "missing",
            manifest("bin/run", none.clone()),
            &[("bin/other", b"x")],
        );
        assert!(checked_package(&d.join("pkg"), &d.join("root"), "s").is_err());
        // a whole root, and a level that is no level
        for bad in [
            serde_json::json!([{ "path": "wy/{site}/downstream", "level": "write" }]),
            serde_json::json!([{ "path": "wy/{site}/downstream/plc", "level": "config" }]),
            serde_json::json!([{ "path": "wy/{site}/sys", "level": "read" }]),
        ] {
            let d = package_dir(
                "grant",
                manifest("bin/run", bad.clone()),
                &[("bin/run", b"x")],
            );
            let e = checked_package(&d.join("pkg"), &d.join("root"), "s")
                .err()
                .unwrap();
            assert!(e.contains("requester"), "{bad}: {e}");
        }
        // no manifest at all: files alone are no package
        let d = package_dir("bare", none, &[("bin/run", b"x")]);
        std::fs::remove_file(d.join("pkg").join(packages::MANIFEST)).unwrap();
        assert!(checked_package(&d.join("pkg"), &d.join("root"), "s").is_err());
    }
}
