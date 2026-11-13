//! `sys/backups/<id>/~act/send {link, connection, path?}` (ADR 0048 §3.4):
//! the broker writes a kept backup into a file store (S3, WebDAV, Google
//! Drive, a local directory) through a file-store link, in parts, with the
//! link's own upload actions (`upload_begin` / `upload_part` /
//! `upload_commit`, ADR 0028).
//!
//! The admin has no signing key links trust, so it gets one for this alone:
//! the **backup sender key**, a secret the broker makes (like a link's
//! requester key; it is in no link backup). Only the links the host names
//! in `backups.send_links` (`wyrmd.json5`, default none) trust it, as one
//! limited key at `write` on their own subtree, bound to the subject
//! [`SENDER_SUBJECT`]. Nothing is kept in the registry.
//!
//! The broker writes here with its own key for whoever has `config` on
//! `sys`, whatever that caller may do on the link. So the **host** decides
//! where a backup may land, not the caller: each entry of `send_links`
//! names one folder, the caller names a connection and a file (or a
//! sub-path) below that folder, and every token the broker signs is good
//! for that folder's keys and the connection's four upload actions only.
//! Nothing is overwritten. The audit names the caller.
//!
//! A backup that holds the `keys` section is never sent: the site's
//! identity does not go to a store by a remote command.

use super::backups::{Job, SendLink};
use super::*;
use ed25519_dalek::SigningKey;

/// The name the sender key is kept under in the secret store (no link id:
/// `:` is in no segment).
const SENDER_STORE: &str = "broker:backup-sender";
const SENDER_KEY: &str = "key";
/// The `sub` of every token the sender key signs; the file-store link's
/// audit and the owner of its uploads.
pub const SENDER_SUBJECT: &str = "broker:backup";
/// Bytes of one part.
const PART: u64 = 1 << 20;
/// One call to the link.
const CALL_TIMEOUT: Duration = Duration::from_secs(60);
/// How often one part is tried.
const PART_TRIES: u32 = 3;
/// How long the store may take to commit the file.
const COMMIT_TIMEOUT: Duration = Duration::from_secs(1800);

impl Control {
    /// The backup sender key, made once.
    fn sender_seed(&self) -> Result<SigningKey, String> {
        let stored = self.secrets.for_link(SENDER_STORE);
        if let Some(seed) = stored
            .get(SENDER_KEY)
            .and_then(|raw| <[u8; 32]>::try_from(&raw[..]).ok())
        {
            return Ok(SigningKey::from_bytes(&seed));
        }
        let mut seed = zeroize::Zeroizing::new([0u8; 32]);
        getrandom::fill(&mut seed[..]).map_err(|e| format!("no randomness: {e}"))?;
        self.secrets
            .set(SENDER_STORE, SENDER_KEY, &seed[..])
            .map_err(|e| e.to_string())?;
        info!("backup sender key created");
        Ok(SigningKey::from_bytes(&seed))
    }

    /// The limited key the link `id` trusts the broker's `send` with:
    /// `None` unless the host named the link in `backups.send_links`.
    pub(super) fn backup_sender_key(&self, id: &str) -> Option<wyrm_link_sdk::LimitedKey> {
        if !self.cfg.backups.send_links.iter().any(|l| l.link == id) {
            return None;
        }
        let key = match self.sender_seed() {
            Ok(k) => k.verifying_key(),
            Err(e) => {
                warn!(link = %id, "backup sender key: {e}");
                return None;
            }
        };
        Some(wyrm_link_sdk::LimitedKey {
            key,
            cap: Perm::Write,
            scopes: vec![format!("wy/{}/downstream/{id}", self.cfg.site)],
            subject: Some(SENDER_SUBJECT.to_owned()),
        })
    }
}

/// What `send` was asked for, checked against the host's list.
#[derive(Debug, Clone, PartialEq)]
struct Target {
    link: String,
    /// The connection: the node of `upload_part` and `upload_commit`.
    conn: String,
    /// The folder node under the link the file goes into:
    /// `<connection>/files/<host's folder>[/<sub-folders of the path>]`.
    folder: String,
    /// The host's folder node (`<connection>/files/<folder>`): the tokens
    /// of this send are good below it and nowhere else.
    root: String,
    /// The file's name in the store.
    name: String,
}

impl Target {
    fn shown(&self) -> String {
        format!("{}/{}/{}", self.link, self.folder, self.name)
    }

    /// The grants of this send's tokens: the host's folder, and the four
    /// upload actions of the connection (they act only on uploads this
    /// subject began, so only on ones begun in that folder).
    fn grants(&self, site: &str) -> Vec<wyrm_core::ptok::Grant> {
        let link = format!("wy/{site}/downstream/{}", self.link);
        let mut out = vec![wyrm_core::ptok::Grant {
            k: format!("{link}/{}/**", self.root),
            p: Perm::Write,
        }];
        for action in UPLOAD_ACTIONS {
            out.push(wyrm_core::ptok::Grant {
                k: format!("{link}/{}/~act/{action}", self.conn),
                p: Perm::Write,
            });
        }
        out
    }
}

/// The actions of a connection a send calls after `upload_begin`.
const UPLOAD_ACTIONS: [&str; 4] = [
    "upload_part",
    "upload_commit",
    "upload_status",
    "upload_abort",
];

/// One segment of a path a caller or the host gave: a plain name.
fn plain(seg: &str) -> bool {
    !seg.is_empty()
        && seg != "."
        && seg != ".."
        && !seg.contains(['\\', ':'])
        && wyrm_core::keyspace::validate_segment(seg).is_ok()
}

/// A `folder` of `backups.send_links`: plain segments, relative.
pub fn check_folder(folder: &str) -> Result<(), String> {
    if folder.split('/').all(plain) {
        Ok(())
    } else {
        Err(format!(
            "folder {folder:?}: a relative path of plain names (no `..`, no empty segment)"
        ))
    }
}

/// Check the arguments of `send` for the job `j` against the host's list.
fn target_of(j: &Job, args: &Value, send_links: &[SendLink]) -> Result<Target, LinkError> {
    let bad = |m: &str| LinkError::invalid_parameter(m.to_owned());
    if j.status != "done" {
        return Err(LinkError::new(
            Status::Busy,
            format!("backup {} is {}", j.id, j.status),
        ));
    }
    if j.sections.iter().any(|s| s == "keys") {
        return Err(bad(
            "a backup that holds the keys section is not sent: download it on the broker's own \
             gateway",
        ));
    }
    let link = arg_str(args, "link")
        .filter(|l| !l.is_empty())
        .ok_or_else(|| bad("link: required"))?;
    crate::registry::validate_link_id(link).map_err(|e| bad(&e))?;
    let Some(entry) = send_links.iter().find(|l| l.link == link) else {
        return Err(bad(&format!(
            "link {link} is not one the broker sends backups through: name it in \
             backups.send_links in wyrmd.json5 (set on the host)"
        )));
    };
    check_folder(&entry.folder).map_err(|e| bad(&format!("backups.send_links: {e}")))?;
    let conn = arg_str(args, "connection")
        .filter(|c| plain(c))
        .ok_or_else(|| bad("connection: required, a connection of the link"))?;
    // the path is below the host's folder: a file name, or sub-folders and
    // a file name. It is never absolute and never climbs.
    let path = match arg_str(args, "path").filter(|p| !p.is_empty()) {
        Some(p) => p,
        None => j.file.as_str(),
    };
    let segs: Vec<&str> = path.split('/').collect();
    if !segs.iter().all(|s| plain(s)) {
        return Err(bad(&format!(
            "path: a file name or a sub-path below the folder {} of plain names (not absolute, \
             no `..`, no empty segment)",
            entry.folder
        )));
    }
    let Some((name, sub)) = segs.split_last() else {
        return Err(bad("path: a file name"));
    };
    if name.len() > 255 {
        return Err(bad("path: a file name of at most 255 bytes"));
    }
    let root = format!("{conn}/files/{}", entry.folder);
    let folder = sub.iter().fold(root.clone(), |f, s| format!("{f}/{s}"));
    Ok(Target {
        link: link.to_owned(),
        conn: conn.to_owned(),
        folder,
        root,
        name: (*name).to_owned(),
    })
}

fn field<'a>(v: &'a Option<Value>, name: &str) -> Option<&'a Value> {
    match v {
        Some(Value::Map(m)) => m.get(name),
        _ => None,
    }
}

fn text(v: &Option<Value>, name: &str) -> String {
    match field(v, name) {
        Some(Value::Str(s)) => s.clone(),
        _ => String::new(),
    }
}

fn args_of<const N: usize>(pairs: [(&str, Value); N]) -> Value {
    Value::Map(pairs.into_iter().map(|(k, v)| (k.to_owned(), v)).collect())
}

/// One send in flight: the client that signs with the sender key and where
/// the file goes.
struct Sending {
    ctl: Arc<Control>,
    client: wyrm_client::WyrmClient,
    id: String,
    to: Target,
    upload: String,
    size: u64,
    by: String,
}

impl Sending {
    fn conn_node(&self) -> String {
        format!(
            "wy/{}/downstream/{}/{}",
            self.ctl.cfg.site, self.to.link, self.to.conn
        )
    }

    async fn call(&self, action: &str, args: Value) -> Result<Option<Value>, String> {
        self.client
            .invoke_one(&self.conn_node(), action, args)
            .await
            .map_err(|e| format!("{action}: {e}"))
    }

    /// Every part, then the commit; `Ok` when the store has the file.
    async fn run(&self) -> Result<(), String> {
        let parts = self.size.div_ceil(PART);
        for index in 0..parts {
            let offset = index * PART;
            let len = PART.min(self.size - offset);
            let (ctl, id) = (self.ctl.clone(), self.id.clone());
            let (data, _) = tokio::task::spawn_blocking(move || ctl.backup_part(&id, offset, len))
                .await
                .map_err(|e| e.to_string())?
                .map_err(|e| e.message)?;
            let mut tries = 0;
            loop {
                tries += 1;
                let args = args_of([
                    ("upload", Value::from(self.upload.clone())),
                    ("index", Value::UInt(index)),
                    ("data", Value::Bytes(data.clone())),
                ]);
                match self.call("upload_part", args).await {
                    Ok(_) => break,
                    Err(e) if tries >= PART_TRIES => return Err(format!("part {index}: {e}")),
                    Err(_) => tokio::time::sleep(Duration::from_secs(1)).await,
                }
            }
            let done = ((index + 1) * 95 / parts.max(1)) as u8;
            self.ctl
                .backups()
                .update(&self.id, |j| j.send_progress = done);
        }
        let upload = || args_of([("upload", Value::from(self.upload.clone()))]);
        self.call("upload_commit", upload()).await?;
        let until = tokio::time::Instant::now() + COMMIT_TIMEOUT;
        loop {
            let st = self.call("upload_status", upload()).await?;
            match text(&st, "state").as_str() {
                "done" => return Ok(()),
                "failed" => return Err(format!("the store refused it: {}", text(&st, "error"))),
                _ if tokio::time::Instant::now() > until => {
                    return Err("the store did not take the file in time".into())
                }
                _ => tokio::time::sleep(Duration::from_millis(500)).await,
            }
        }
    }

    /// Run it to its end and write the end down: the job's values, its
    /// record on disk, the audit.
    async fn finish(self) {
        let r = self.run().await;
        if r.is_err() {
            // nothing half sent stays on the link's disk
            let abort = args_of([("upload", Value::from(self.upload.clone()))]);
            let _ = self.call("upload_abort", abort).await;
        }
        let ctl = &self.ctl;
        ctl.backups().update(&self.id, |j| match &r {
            Ok(()) => {
                j.send_status = "done".into();
                j.send_progress = 100;
                j.send_error.clear();
            }
            Err(e) => {
                j.send_status = "failed".into();
                j.send_error = e.clone();
            }
        });
        if let Some(j) = ctl.backups().get(&self.id) {
            ctl.save_job(&j);
        }
        ctl.backups().sending(false);
        match &r {
            Ok(()) => {
                info!(backup = %self.id, to = %self.to.shown(), "backup sent");
                ctl.record(
                    &self.by,
                    "backup_send",
                    &self.id,
                    Status::Ok,
                    &format!(
                        "sent; link {}; path {}/{}; {} bytes",
                        self.to.link, self.to.folder, self.to.name, self.size
                    ),
                );
            }
            Err(e) => {
                warn!(backup = %self.id, to = %self.to.shown(), "backup not sent: {e}");
                ctl.record(
                    &self.by,
                    "backup_send",
                    &self.id,
                    Status::InternalError,
                    &format!("to {}: {e}", self.to.shown()),
                );
            }
        }
    }
}

/// `sys/backups/<id>/~act/send`: begin the upload on the link and answer;
/// the parts go in the background (`send_status`, `send_progress`).
pub(super) async fn send(
    ctl: &Arc<Control>,
    ctx: &LinkCtx,
    id: &str,
    args: &Value,
    sub: &str,
) -> wyrm_link_sdk::Result<Option<Value>> {
    let job = ctl
        .backups()
        .get(id)
        .ok_or_else(|| LinkError::not_found(format!("backup {id}")))?;
    let to = target_of(&job, args, &ctl.cfg.backups.send_links)?;
    if !ctl.registry().links.contains_key(&to.link) {
        return Err(LinkError::not_found(format!("link {}", to.link)));
    }
    let key = ctl.sender_seed().map_err(LinkError::internal)?;
    let scope = format!("wy/{}/downstream/{}", ctl.cfg.site, to.link);
    // good for the host's folder and the connection's upload actions only
    let tokens = wyrm_client::SigningTokens::new(key, ctl.cfg.site.clone())
        .subject(SENDER_SUBJECT)
        .grants(to.grants(&ctl.cfg.site))
        .max(Perm::Write);
    let client = wyrm_client::WyrmClient::new(ctx.client().clone())
        .with_tokens(Arc::new(tokens))
        .with_timeout(CALL_TIMEOUT);
    if !ctl.backups().sending(true) {
        return Err(LinkError::new(
            Status::Busy,
            "a backup is being sent; one at a time",
        ));
    }
    let begin = args_of([
        ("name", Value::from(to.name.clone())),
        ("size", Value::UInt(job.size)),
        ("part_size", Value::UInt(PART)),
        ("sha256", Value::from(job.sha256.clone())),
        // never: a send replaces no file of the store
        ("overwrite", Value::Bool(false)),
    ]);
    let begun = client
        .invoke_one(&format!("{scope}/{}", to.folder), "upload_begin", begin)
        .await;
    let upload = match begun {
        Ok(v) => text(&v, "upload"),
        Err(e) => {
            ctl.backups().sending(false);
            ctl.record(
                sub,
                "backup_send",
                id,
                Status::InvalidParameter,
                &format!("to {}: {e}", to.shown()),
            );
            return Err(LinkError::invalid_parameter(format!(
                "link {} did not take the file: {e}",
                to.link
            )));
        }
    };
    if upload.is_empty() {
        ctl.backups().sending(false);
        return Err(LinkError::internal(format!(
            "link {}: upload_begin answered no upload",
            to.link
        )));
    }
    ctl.backups().update(id, |j| {
        j.sent_to = to.shown();
        j.send_status = "sending".into();
        j.send_progress = 0;
        j.send_error.clear();
    });
    // who, what, where: the link's own audit names only the broker's
    // subject (the upload actions take no note of the caller)
    ctl.record(
        sub,
        "backup_send",
        id,
        Status::Ok,
        &format!(
            "started; link {}; path {}/{}; {} bytes; sha256 {}",
            to.link, to.folder, to.name, job.size, job.sha256
        ),
    );
    let answer = args_of([
        ("to", Value::from(to.shown())),
        ("upload", Value::from(upload.clone())),
        ("parts", Value::UInt(job.size.div_ceil(PART))),
    ]);
    let sending = Sending {
        ctl: ctl.clone(),
        client,
        id: id.to_owned(),
        to,
        upload,
        size: job.size,
        by: sub.to_owned(),
    };
    tokio::spawn(sending.finish());
    Ok(Some(answer))
}

/// The `send` action of a kept backup.
pub(super) async fn declare(ctx: &LinkCtx, path: &str) -> wyrm_link_sdk::Result<()> {
    ctx.declare_action(
        path,
        "send",
        ActionMeta::new()
            .display("Send to a file store")
            .param(
                "link",
                str_param()
                    .required(true)
                    .display("File store link")
                    .description("One of backups.send_links (attribute send_links of sys/backups)"),
            )
            .param(
                "connection",
                str_param()
                    .required(true)
                    .display("Connection")
                    .description(
                        "A connection of the link; the file goes into the host's folder of it",
                    ),
            )
            .param(
                "path",
                str_param().display("File name").description(
                    "Below the host's folder: a file name, or sub-folders and a file name. \
                         Default: the backup's own name",
                ),
            )
            .result(ActionResult::Type(TypeCode::Map))
            .timeout_ms(INSTALL_TIMEOUT_MS)
            .level(Perm::Config),
    )
    .await
}

#[cfg(test)]
mod tests {
    use super::*;

    fn job(sections: &[&str]) -> Job {
        Job {
            id: "20261113t101502z".into(),
            kind: "full".into(),
            link: String::new(),
            sections: sections.iter().map(|s| (*s).to_owned()).collect(),
            status: "done".into(),
            progress: 100,
            step: String::new(),
            size: 10,
            sha256: "00".repeat(32),
            created: 1,
            expires: 2,
            error: String::new(),
            file: "plant-20261113T101502Z.wyrm-backup".into(),
            sealed: "none".into(),
            by: "user:a".into(),
            pinned: false,
            sent_to: String::new(),
            send_status: String::new(),
            send_progress: 0,
            send_error: String::new(),
        }
    }

    fn args(pairs: &[(&str, &str)]) -> Value {
        Value::Map(
            pairs
                .iter()
                .map(|(k, v)| ((*k).to_owned(), Value::from(*v)))
                .collect(),
        )
    }

    fn host(link: &str, folder: &str) -> Vec<SendLink> {
        vec![SendLink {
            link: link.to_owned(),
            folder: folder.to_owned(),
        }]
    }

    #[test]
    fn send_is_refused_without_the_hosts_list_and_for_keys() {
        let allowed = host("files", "backups");
        let ok = args(&[("link", "files"), ("connection", "c1")]);
        let t = target_of(&job(&["control", "storage"]), &ok, &allowed).unwrap();
        assert_eq!(
            (t.conn.as_str(), t.folder.as_str(), t.name.as_str()),
            (
                "c1",
                "c1/files/backups",
                "plant-20261113T101502Z.wyrm-backup"
            )
        );
        assert_eq!(
            t.shown(),
            "files/c1/files/backups/plant-20261113T101502Z.wyrm-backup"
        );
        // the default: no link is one the broker sends through
        let e = target_of(&job(&["control"]), &ok, &[]).unwrap_err();
        assert!(e.message.contains("backups.send_links"), "{e}");
        assert!(e.status.code() >= 0x20);
        // another link than the host named
        let other = args(&[("link", "s3"), ("connection", "c1")]);
        let e = target_of(&job(&["control"]), &other, &allowed).unwrap_err();
        assert!(e.message.contains("backups.send_links"), "{e}");
        // a backup with the site's keys never goes to a store
        let e = target_of(&job(&["control", "keys"]), &ok, &allowed).unwrap_err();
        assert!(e.message.contains("keys"), "{e}");
        assert!(e.status.code() >= 0x20);
        let mut running = job(&["control"]);
        running.status = "running".into();
        let e = target_of(&running, &ok, &allowed).unwrap_err();
        assert_eq!(e.status, Status::Busy, "{e}");
    }

    /// The confused deputy: the broker writes with its own key, so the
    /// caller never chooses where. The file lands in the host's folder or
    /// below it; a path that climbs out, an absolute one and a connection
    /// that is a path are refused, and the tokens are good for that folder
    /// and the connection's upload actions only.
    #[test]
    fn a_send_stays_in_the_hosts_folder() {
        let allowed = host("files", "site/backups");
        let j = job(&["control"]);
        let with = |path: &str| args(&[("link", "files"), ("connection", "c1"), ("path", path)]);
        let t = target_of(&j, &with("2026/nightly.wyrm-backup"), &allowed).unwrap();
        assert_eq!(t.root, "c1/files/site/backups");
        assert_eq!(t.folder, "c1/files/site/backups/2026");
        assert_eq!(t.name, "nightly.wyrm-backup");
        for path in [
            "../other/x",
            "..",
            "a/../../x",
            "/etc/passwd",
            "/x",
            "a//x",
            "a/",
            "./x",
            "C:\\x",
            "a\\..\\x",
            "c1/files/../x",
            "a b\u{0}",
        ] {
            let e = target_of(&j, &with(path), &allowed).expect_err(path);
            assert!(e.message.contains("path"), "{path}: {e}");
            assert!(e.status.code() >= 0x20);
        }
        // the connection is one name, not a way to another node
        for conn in ["", "c1/files", "..", "c1/../c2", "a:b"] {
            let a = args(&[("link", "files"), ("connection", conn)]);
            assert!(target_of(&j, &a, &allowed).is_err(), "{conn}");
        }
        let none = args(&[("link", "files")]);
        assert!(target_of(&j, &none, &allowed).is_err());
        // a folder of the host that is no plain path is refused, not used
        for folder in ["", "../x", "/abs", "a//b", "a/.."] {
            assert!(check_folder(folder).is_err(), "{folder}");
            let e = target_of(&j, &with("x"), &host("files", folder)).unwrap_err();
            assert!(e.message.contains("send_links"), "{folder}: {e}");
        }
        assert!(check_folder("backups").is_ok() && check_folder("a/b").is_ok());

        // what a token of this send is good for
        let grants: Vec<String> = t.grants("s").into_iter().map(|g| g.k).collect();
        assert_eq!(
            grants,
            [
                "wy/s/downstream/files/c1/files/site/backups/**",
                "wy/s/downstream/files/c1/~act/upload_part",
                "wy/s/downstream/files/c1/~act/upload_commit",
                "wy/s/downstream/files/c1/~act/upload_status",
                "wy/s/downstream/files/c1/~act/upload_abort",
            ]
        );
        assert!(t.grants("s").iter().all(|g| g.p == Perm::Write));
    }

    /// Only the links the host named trust the sender key, at `write` on
    /// their own subtree and for the sender's subject; the key is made once
    /// and is no secret of any link.
    #[test]
    fn only_the_named_links_trust_the_sender_key() {
        let ctl = super::super::tests::control_tweaked("send-trust", |c| {
            c.backups.send_links = vec![SendLink {
                link: "files".to_owned(),
                folder: "backups".to_owned(),
            }];
        });
        let k = ctl.backup_sender_key("files").unwrap();
        assert_eq!(k.cap, Perm::Write);
        assert_eq!(k.scopes, ["wy/s/downstream/files"]);
        assert_eq!(k.subject.as_deref(), Some(SENDER_SUBJECT));
        assert_eq!(ctl.backup_sender_key("files").unwrap().key, k.key, "once");
        assert!(ctl.backup_sender_key("other").is_none());
        let trusts = |id: &str| {
            ctl.embedded_link_config(id, Vec::new())
                .unwrap()
                .limited_keys
                .iter()
                .any(|l| l.key == k.key)
        };
        assert!(trusts("files") && !trusts("other"));
        assert!(ctl.secrets.for_link("files").is_empty());
        // no list: no key is made, nobody trusts one
        let none = super::super::tests::control("send-off", false, |_| {});
        assert!(none.backup_sender_key("files").is_none());
        assert!(none.secrets.for_link(SENDER_STORE).is_empty());
    }
}
