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

use super::backups::{io_err, link_prefix, make_private_dir, passphrase_arg, uint_arg, StageDir};
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

/// Secrets of a link that are its identity on one broker, made by that
/// broker: never carried over by a backup.
fn broker_made_secret(name: &str) -> bool {
    name == wyrm_link_sdk::REQUESTER_KEY || name == AGENT_KEY_REF
}

/// What a `.wyrm-link` holds, read and checked, its files opened into a
/// private stage directory (removed with this value).
pub(super) struct LinkRestore {
    pub manifest: Manifest,
    pub def: LinkDef,
    pub package: Option<PackageDef>,
    /// The link's secrets (`data`), without the broker-made ones.
    pub secrets: BTreeMap<String, Zeroizing<Vec<u8>>>,
    pub has_data: bool,
    /// Files of the link's private directory, relative to it.
    pub files: Vec<String>,
    /// History pages in the stage directory.
    pub history: Vec<PathBuf>,
    stage: StageDir,
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
        let def: LinkDef = minicbor::decode(&r.read("settings/link.cbor")?)
            .map_err(|e| format!("settings/link.cbor: {e}"))?;
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
        if let Some(s) = manifest.section("data") {
            out.has_data = true;
            let plain = r.read_plain("data/secrets", key)?;
            let Value::Map(m) =
                wyrm_core::codec::from_slice::<Value>(&plain).map_err(|e| e.to_string())?
            else {
                return Err("data/secrets: not a map".into());
            };
            for (name, v) in m {
                if let (Value::Bytes(b), false) = (v, broker_made_secret(&name)) {
                    out.secrets.insert(name, Zeroizing::new(b));
                }
            }
            for f in &s.files {
                if let Some(rel) = f.path.strip_prefix("data/files/") {
                    r.extract(&f.path, &out.files_dir().join(rel), key)?;
                    out.files.push(rel.to_owned());
                }
            }
        }
        if let Some(s) = manifest.section("package") {
            let def: PackageDef = minicbor::decode(&r.read("package/package.cbor")?)
                .map_err(|e| format!("package/package.cbor: {e}"))?;
            for seg in [&def.name, &def.version] {
                wyrm_core::keyspace::validate_segment(seg)
                    .map_err(|e| format!("package {} {}: {e}", def.name, def.version))?;
            }
            for f in &s.files {
                if let Some(rel) = f.path.strip_prefix("package/files/") {
                    r.extract(&f.path, &out.package_dir().join(rel), None)?;
                }
            }
            if !out.package_dir().join(&def.entry).is_file() {
                return Err(format!(
                    "package {} {}: its entry {} is not in the backup",
                    def.name, def.version, def.entry
                ));
            }
            out.package = Some(def);
        }
        if let Some(s) = manifest.section("history") {
            for (i, f) in s.files.iter().enumerate() {
                let dest = out.stage.0.join("history").join(format!("{i:05}.cbor"));
                r.extract(&f.path, &dest, None)?;
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
        let data = self.link_data_dir(id).map_err(|e| e.message)?;
        std::fs::remove_dir_all(&data).map_err(|e| io_err(&data, e))?;
        self.link_data_dir(id).map_err(|e| e.message)?;
        for rel in &r.files {
            let (from, to) = (r.files_dir().join(rel), data.join(rel));
            if let Some(d) = to.parent() {
                std::fs::create_dir_all(d).map_err(|e| io_err(d, e))?;
            }
            // the stage is on the same disk; a copy when it is not
            if std::fs::rename(&from, &to).is_err() {
                std::fs::copy(&from, &to).map_err(|e| io_err(&to, e))?;
            }
        }
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

    /// `data_dir/restore/<link>/<UTC>.wyrm-link`: where the next restore
    /// point of `link` goes (ADR 0048 §1.3); its directory is made.
    pub fn restore_point_path(&self, link: &str) -> Result<PathBuf, String> {
        crate::registry::validate_link_id(link)?;
        let dir = self.cfg.data_dir.join("restore").join(link);
        make_private_dir(&dir)?;
        let stamp: String = iso_utc(now_s())
            .chars()
            .filter(|c| c.is_ascii_alphanumeric())
            .collect();
        Ok(dir.join(format!("{stamp}.{}", format::EXT_LINK)))
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

/// What a link backup asks for that an installer must have seen: its
/// requester grants and its network allowlist.
fn asks_of(def: &LinkDef) -> Vec<String> {
    let mut asks = Vec::new();
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
        crate::registry::validate_link_id(&id)?;
        let asks = asks_of(&r.def);
        if !asks.is_empty() && !accepted(args) {
            return Err(format!(
                "the link {} of the backup asks for: {}. Nothing is installed: read them, then \
                 install again with Accept Requested Rights",
                r.def.id,
                asks.join("; ")
            ));
        }
        let from = format!("{}@{} of {}", r.def.id, r.manifest.site, r.manifest.created);
        let existing = ctl.registry().links.get(&id).cloned();
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
        let mut message = match self.backup_package(&r, sub).await? {
            Some(m) => format!("{m}; "),
            None => String::new(),
        };
        let params = decode_params(&r.def.params);
        match &existing {
            Some(old) => {
                // a way back first (ADR 0048 §3.5)
                let point = ctl.restore_point_path(&id)?;
                let made = {
                    let (ctl, id, point) = (ctl.clone(), id.clone(), point.clone());
                    tokio::task::spawn_blocking(move || ctl.link_backup_to(&id, &point))
                        .await
                        .map_err(|e| e.to_string())??
                };
                ctl.record(
                    sub,
                    "restore_point",
                    &id,
                    Status::Ok,
                    &format!("{} ({} bytes) before a restore", point.display(), made.size),
                );
                message.push_str(&format!("restore point {}; ", point.display()));
                if old.mode != Mode::External {
                    self.stop_link(&id, sub).await.map_err(|e| e.message)?;
                }
                if old.params != r.def.params {
                    crate::secrets::lint_params(&params, "params")?;
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
    async fn backup_package(&self, r: &LinkRestore, sub: &str) -> Result<Option<String>, String> {
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
        let installed = ctl.registry().packages.get(name).cloned();
        match (installed, &r.package) {
            (Some(i), Some(p)) if i.version == p.version && i.sha256 == p.sha256 => Ok(None),
            (Some(i), Some(p)) => Err(format!(
                "package {name} {} is installed here; the backup holds {} (sha256 {}). One \
                 version per package: update or roll back the package first, or restore the \
                 backup without its package section",
                i.version, p.version, p.sha256
            )),
            (Some(i), None) => Ok(Some(format!(
                "package {name} {} of this broker is used",
                i.version
            ))),
            (None, None) => Err(format!(
                "package {name} is not installed here and the backup does not hold it"
            )),
            (None, Some(p)) => {
                if p.name != name {
                    return Err(format!(
                        "the backup holds package {}, the link runs {name}",
                        p.name
                    ));
                }
                if p.kind == PackageKind::Process && ctl.cfg.link_endpoint.is_none() {
                    return Err("process links need a tls/ listener on the broker".into());
                }
                let mut def = p.clone();
                def.installed = now_s();
                def.source = format!("backup {}@{}", r.def.id, r.manifest.site);
                let root = ctl.packages_root();
                let to = packages::dir(&root, &def);
                if to.exists() {
                    return Err(format!(
                        "{}: exists without its package record",
                        to.display()
                    ));
                }
                let parent = root.join(&def.name);
                std::fs::create_dir_all(&parent).map_err(|e| io_err(&parent, e))?;
                copy_tree(&r.package_dir(), &to)?;
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
                    &install_detail(&def, None),
                );
                declare_package(&self.ctx, &def)
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

/// Copy the files under `from` to the new directory `to`, modes kept.
fn copy_tree(from: &Path, to: &Path) -> Result<(), String> {
    std::fs::create_dir_all(to).map_err(|e| io_err(to, e))?;
    for e in std::fs::read_dir(from).map_err(|e| io_err(from, e))? {
        let e = e.map_err(|e| io_err(from, e))?;
        let (src, dst) = (e.path(), to.join(e.file_name()));
        let meta = e.metadata().map_err(|e| io_err(&src, e))?;
        if meta.is_dir() {
            copy_tree(&src, &dst)?;
        } else if meta.is_file() {
            std::fs::copy(&src, &dst).map_err(|e| io_err(&dst, e))?;
        }
    }
    Ok(())
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

/// The `send` action of a kept backup.
pub(super) async fn declare_send(_ctx: &LinkCtx, _path: &str) -> wyrm_link_sdk::Result<()> {
    Ok(())
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
            asks_of(&def),
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
        assert!(asks_of(&plain).is_empty());
    }
}
