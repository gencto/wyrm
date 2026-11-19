//! The declared schema of every `sys` action, as it is on the wire.
//!
//! The admin runs as a link in a test session with one of each kind of node
//! (links, a package, a token, quarantined CNs, an upstream site, a watch
//! group with a watch, a sink, a backup). Every action of every node is
//! written as `[state] <path> ▸ <action> <canonical CBOR of its ActionMeta, hex>`
//! and compared with `sys_actions.snapshot`: a change of a parameter's name,
//! type, `required`, list, text or editor is a change of that file, seen in
//! review. `WYRM_SNAPSHOT=write cargo test -p wyrm-admin sys_action_schemas`
//! writes the file again.

use super::tests::{control, control_tweaked};
use super::*;
use crate::registry::{Op, PackageDef, PackageKind, PeerDef, TokenDef};
use wyrm_link_sdk::TestHarness;

const SNAPSHOT: &str = concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/src/control/sys_actions.snapshot"
);

struct Roles;

impl RoleGrants for Roles {
    fn grants(&self) -> Vec<(String, String, Perm)> {
        vec![("operator".into(), "wy/s/downstream/**".into(), Perm::Write)]
    }
    fn set_grant(&self, _: &str, _: &str, _: Perm) -> Result<(), String> {
        Ok(())
    }
    fn revoke_widening(
        &self,
        _: &[String],
        _: &str,
    ) -> Result<Vec<(String, String, Perm)>, String> {
        Ok(Vec::new())
    }
}

fn link(id: &str, mode: Mode) -> LinkDef {
    LinkDef {
        id: id.into(),
        driver: "x".into(),
        mode,
        params: wyrm_core::codec::to_vec(&Value::Map(Default::default())).unwrap(),
        token_hash: "x".into(),
        rev: 1,
        origin: Origin::Runtime,
        created: 1,
        display: None,
        granted: None,
        log_level: None,
        grants: Vec::new(),
    }
}

fn package(name: &str) -> PackageDef {
    PackageDef {
        name: name.into(),
        version: "1.0.0".into(),
        kind: PackageKind::Process,
        entry: "bin".into(),
        args: Vec::new(),
        sha256: "00".into(),
        source: "zip".into(),
        description: String::new(),
        installed: 1,
        requester: Vec::new(),
        state: 1,
        previous: None,
        last_update: None,
    }
}

/// One of each kind of node that has actions of its own.
fn state(ctl: &Control) {
    for op in [
        Op::Install(link("ext", Mode::External)),
        Op::Install(link("proc", Mode::Process)),
        Op::PutPackage(package("pack")),
        Op::AddToken {
            id: "tok".into(),
            def: TokenDef {
                sha256: "00".into(),
                uses: 1,
                expires: 0,
                created: 1,
                by: "test".into(),
            },
        },
        Op::Quarantine {
            cn: "stray".into(),
            seen: 1,
        },
        Op::EnrollRequest {
            site: "plant".into(),
            csr_pem: "csr".into(),
            key_sha256: "ab".repeat(32),
            via: Vec::new(),
            seen: 1,
        },
        Op::AddPeer(PeerDef {
            site: "central".into(),
            dir: PeerDir::Upstream,
            endpoint: "quic/central.example:7450".into(),
            ca_pem: String::new(),
            enabled: true,
            created: 1,
            via: Vec::new(),
            cert_pem: String::new(),
            enroll: "quic/central.example:7451".into(),
            key_sha256: String::new(),
            allow_config: false,
        }),
        // a downstream broker admitted by name, then held: no key to compare
        Op::AddPeer(PeerDef {
            site: "edge".into(),
            dir: PeerDir::Downstream,
            endpoint: String::new(),
            ca_pem: String::new(),
            enabled: true,
            created: 1,
            via: Vec::new(),
            cert_pem: String::new(),
            enroll: String::new(),
            key_sha256: String::new(),
            allow_config: false,
        }),
        Op::HoldBroker {
            site: "edge".into(),
            seen: 1,
        },
        Op::PutWatchGroup {
            name: "g".into(),
            logging: 2,
            interval_ms: 60_000,
            flush_ms: 5_000,
        },
        Op::AddWatch {
            group: "g".into(),
            key: "wy/s/downstream/ext/p".into(),
        },
    ] {
        ctl.apply(op).unwrap();
    }
}

async fn harness(ctl: Arc<Control>) -> TestHarness<Admin> {
    let start = AdminStart {
        ctl,
        embedded: Arc::new(AsyncMutex::new(HashMap::new())),
    };
    TestHarness::<Admin>::start_with(start, |c| {
        c.root = Some("wy/s/sys".into());
        c.open_actions = vec!["hello".into(), "enroll".into()];
        c.overlays = false;
        c.audit = false;
    })
    .await
}

fn args(kv: &[(&str, Value)]) -> Value {
    Value::Map(
        kv.iter()
            .map(|(k, v)| ((*k).to_owned(), v.clone()))
            .collect(),
    )
}

async fn invoke(h: &TestHarness<Admin>, path: &str, action: &str, a: Value) {
    let r = h.invoke(path, action, a, Some(h.ptok(Perm::Config))).await;
    assert!(!r.is_empty(), "{path} ▸ {action}: no answer");
    for r in r {
        assert!(
            r.att.status.is_none_or(|s| s.code() == 0),
            "{path} ▸ {action}: {:?} {:?}",
            r.att.status,
            r.att.err
        );
    }
}

/// Every action of every node, the id of a backup written as `<id>`.
async fn dump(h: &TestHarness<Admin>, label: &str, out: &mut Vec<String>) {
    let (_, mut paths) = h.keys("", "").await;
    paths.push(String::new());
    paths.sort();
    paths.dedup();
    for path in paths {
        let Some(meta) = h.ctx().meta(&path) else {
            continue;
        };
        let shown = match path.strip_prefix("backups/") {
            Some(rest) => match rest.split_once('/') {
                Some((_, tail)) => format!("backups/<id>/{tail}"),
                None => "backups/<id>".to_owned(),
            },
            None => path.clone(),
        };
        for (name, a) in meta.actions.unwrap_or_default() {
            let hex = hex::encode(wyrm_core::codec::to_vec(&a).unwrap());
            out.push(format!("[{label}] {shown} ▸ {name} {hex}"));
        }
    }
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn sys_action_schemas_are_the_snapshot() {
    crate::logs::install_quiet();
    let mut out = Vec::new();

    // a broker with one of everything
    let ctl = control_tweaked("schema-full", |_| {});
    ctl.set_role_grants(Arc::new(Roles));
    ctl.set_peers(PeerConfig {
        enroll: true,
        listen: true,
        ..Default::default()
    });
    state(&ctl);
    let h = harness(ctl.clone()).await;
    invoke(
        &h,
        "history/sinks",
        "add_sink",
        args(&[("name", "sink".into()), ("link", "ext".into())]),
    )
    .await;
    invoke(&h, "backups", "create", args(&[])).await;
    dump(&h, "full", &mut out).await;
    h.stop().await;
    assert!(
        out.iter()
            .any(|l| l.contains("backups/<id> ▸ download_part")),
        "the backup's node"
    );

    // a broker with nothing: no gateway, no enrollment, empty lists
    let h = harness(control_tweaked("schema-bare", |_| {})).await;
    dump(&h, "bare", &mut out).await;
    h.stop().await;

    // "from Repository" in each state of the index
    let entry: packages::RepoEntry = serde_json::from_str(
        r#"{"name": "alarm", "version": "1.0.0", "url": "https://x.example/a.zip", "sha256": "00"}"#,
    )
    .unwrap();
    for (label, repo) in [
        ("repo-loading", None),
        ("repo-failed", Some(Err("no route".to_owned()))),
        ("repo-empty", Some(Ok(Vec::new()))),
        ("repo-list", Some(Ok(vec![entry]))),
    ] {
        let ctl = control_tweaked(&format!("schema-{label}"), |c| {
            c.repository = Some("https://x.example/index.json".into())
        });
        *ctl.repo.lock().unwrap() = repo;
        let h = harness(ctl).await;
        let mut all = Vec::new();
        dump(&h, label, &mut all).await;
        h.stop().await;
        out.extend(all.into_iter().filter(|l| l.contains("▸ install_repo ")));
    }

    let text = out.join("\n") + "\n";
    if std::env::var("WYRM_SNAPSHOT").as_deref() == Ok("write") {
        std::fs::write(SNAPSHOT, &text).unwrap();
        return;
    }
    let want = std::fs::read_to_string(SNAPSHOT).unwrap_or_default();
    let (want, got): (Vec<&str>, Vec<&str>) = (want.lines().collect(), text.lines().collect());
    let gone: Vec<&&str> = want.iter().filter(|l| !got.contains(l)).collect();
    let new: Vec<&&str> = got.iter().filter(|l| !want.contains(l)).collect();
    assert!(
        gone.is_empty() && new.is_empty(),
        "the declared schema of a sys action changed (WYRM_SNAPSHOT=write to accept):\n\
         not declared any more: {gone:#?}\nnew: {new:#?}"
    );
}

/// Audit of #136: `history/sinks/<n> ▸ next` is for the sink's link alone. Another
/// caller is told `permission_denied` whatever it sent: the caller is checked
/// before its arguments are decoded (a bad argument answered `invalid_parameter`,
/// which told a stranger that the arguments were looked at).
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn a_strangers_next_is_denied_before_its_arguments_are_read() {
    let ctl = control_tweaked("order-next", |_| {});
    state(&ctl);
    let h = harness(ctl).await;
    invoke(
        &h,
        "history/sinks",
        "add_sink",
        args(&[("name", "sink".into()), ("link", "ext".into())]),
    )
    .await;
    // `after: 0.5` passes the SDK's type check (a number) and is refused by the
    // action's struct (a whole number); `max: 0` is below its bound
    for bad in [
        args(&[("after", Value::Float(0.5))]),
        args(&[("max", Value::UInt(0))]),
        args(&[]),
    ] {
        let r = h
            .invoke(
                "history/sinks/sink",
                "next",
                bad.clone(),
                Some(h.ptok(Perm::Config)),
            )
            .await;
        assert!(!r.is_empty(), "no answer");
        for r in r {
            assert_eq!(
                r.att.status.map(|s| s.code()),
                Some(Status::PermissionDenied.code()),
                "{bad:?}"
            );
        }
    }
    h.stop().await;
}

/// The admin with `key` as an upstream site's key: trusted on `sys` up to
/// `config`, as `allow_config` gives it (a limited key, so `Caller::signer` is set).
async fn harness_with_upstream(
    ctl: Arc<Control>,
    key: &ed25519_dalek::SigningKey,
) -> TestHarness<Admin> {
    let start = AdminStart {
        ctl,
        embedded: Arc::new(AsyncMutex::new(HashMap::new())),
    };
    let limited = wyrm_link_sdk::LimitedKey {
        key: key.verifying_key(),
        cap: Perm::Config,
        scopes: vec!["wy/s/sys".into()],
        subject: None,
    };
    TestHarness::<Admin>::start_with(start, |c| {
        c.root = Some("wy/s/sys".into());
        c.open_actions = vec!["hello".into(), "enroll".into()];
        c.overlays = false;
        c.audit = false;
        c.limited_keys = vec![limited];
    })
    .await
}

/// A `config` token on all of the admin signed by `key`.
fn token_of(h: &TestHarness<Admin>, key: &ed25519_dalek::SigningKey) -> Vec<u8> {
    use ed25519_dalek::Signer;
    let all = h.key("**", "");
    let claims = h.claims(&[(&all, Perm::Config)]);
    let mut tok = vec![wyrm_core::ptok::PTOK_VERSION];
    tok.extend(wyrm_core::codec::to_vec(&claims).unwrap());
    let sig = key.sign(&tok);
    tok.extend(sig.to_bytes());
    tok
}

/// A kept backup `id` that holds the site's keys, as the broker finds it at a start.
fn kept_keys_backup(dir: &std::path::Path, id: &str) {
    use super::backups::{Job, JobKind, JobStatus};
    let backups = dir.join("backups");
    std::fs::create_dir_all(&backups).unwrap();
    let file = format!("s-{id}.wyrm-backup");
    std::fs::write(backups.join(&file), b"not read by this test").unwrap();
    let job = Job {
        id: id.to_owned(),
        kind: JobKind::Full,
        link: String::new(),
        sections: vec![
            crate::backup::SectionName::Control,
            crate::backup::SectionName::Keys,
        ],
        status: JobStatus::Done,
        progress: 100,
        step: String::new(),
        size: 21,
        sha256: "00".repeat(32),
        created: 1,
        expires: u64::MAX / 2,
        error: String::new(),
        file: file.clone(),
        sealed: Some(crate::backup::How::Passphrase),
        by: "user:a".into(),
        pinned: true,
        sent_to: String::new(),
        send_status: None,
        send_progress: 0,
        send_error: String::new(),
    };
    std::fs::write(
        backups.join(format!("{file}.json")),
        serde_json::to_vec(&job).unwrap(),
    )
    .unwrap();
}

/// Second audit of #136: a backup that holds the site's keys never travels to
/// another site. A caller from an upstream is told `permission_denied` whatever
/// its arguments are: `offset: 0.5` passes the SDK's type check and is refused by
/// the action's struct, so it shows which check runs first. The site's own
/// administrator, with the same argument, is told what is wrong with it.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn an_upstream_callers_download_is_denied_before_its_arguments_are_read() {
    const ID: &str = "20261113t101502z";
    let ctl = control("order-download", false, |dir| kept_keys_backup(dir, ID));
    assert!(ctl.backups().get(ID).is_some(), "the kept backup is listed");
    let upstream = ed25519_dalek::SigningKey::from_bytes(&[9; 32]);
    let h = harness_with_upstream(ctl.clone(), &upstream).await;
    super::backups::show_job(h.ctx(), &ctl, ID).await;
    let path = format!("backups/{ID}");
    let status = |r: Vec<wyrm_link_sdk::harness::Reply>| -> Vec<Option<u8>> {
        assert!(!r.is_empty(), "no answer");
        r.iter().map(|r| r.att.status.map(|s| s.code())).collect()
    };
    for bad in [
        args(&[("offset", Value::Float(0.5))]),
        args(&[("offset", Value::UInt(0)), ("len", Value::Float(1.5))]),
        args(&[("offset", Value::UInt(0))]),
    ] {
        let r = h
            .invoke(
                &path,
                "download_part",
                bad.clone(),
                Some(token_of(&h, &upstream)),
            )
            .await;
        assert_eq!(
            status(r),
            [Some(Status::PermissionDenied.code())],
            "from an upstream: {bad:?}"
        );
    }
    // the site's own key: the argument is what is wrong
    let r = h
        .invoke(
            &path,
            "download_part",
            args(&[("offset", Value::Float(0.5))]),
            Some(h.ptok(Perm::Config)),
        )
        .await;
    assert_eq!(status(r), [Some(Status::InvalidParameter.code())]);
    h.stop().await;
}

/// Second audit of #136: `rollback_update` is done on the broker's own gateway.
/// A caller whose authority comes from an upstream is refused before its
/// arguments are read. Over the wire the SDK refuses an empty map first (the
/// confirmation is required), so the handler is called itself: with an empty
/// map and with an argument that is no parameter.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn an_upstream_callers_rollback_is_denied_before_its_arguments_are_read() {
    let ctl = control_tweaked("order-rollback", |_| {});
    let h = harness(ctl.clone()).await;
    let mut admin = Admin {
        ctx: h.ctx().clone(),
        ctl,
        embedded: Arc::new(AsyncMutex::new(HashMap::new())),
        _broker: None,
    };
    let from = |signer: Option<wyrm_link_sdk::auth::SignerScopes>| Caller {
        origin: None,
        perm: Perm::Config,
        claims: None,
        signer,
    };
    let upstream = || from(Some(vec![("wy/s/sys".to_owned(), Perm::Config)]));
    for bad in [args(&[]), args(&[("nope", Value::UInt(1))])] {
        let e = admin
            .on_invoke(
                "",
                "rollback_update",
                bad.clone(),
                &upstream(),
                wyrm_link_sdk::harness::unread_sink(),
            )
            .await
            .unwrap_err();
        assert_eq!(e.status, Status::PermissionDenied, "{bad:?}: {}", e.message);
    }
    // the site's own administrator: the arguments are read, and refused
    let e = admin
        .on_invoke(
            "",
            "rollback_update",
            args(&[]),
            &from(None),
            wyrm_link_sdk::harness::unread_sink(),
        )
        .await
        .unwrap_err();
    assert_eq!(e.status, Status::InvalidParameter);
    assert_eq!(e.message, "confirm_site: required");
    h.stop().await;
}

/// Second and third audits of #136: every action on a node says what is wrong
/// with the node before it reads the arguments. Each action of the snapshot whose
/// path names a node (a link, a package, a token, an upstream, a quarantined CN,
/// a backup, a watch group or watch, a sink) is called on a node that does not
/// exist, once with no arguments and once with an argument that is no parameter.
/// Both answers are the same refusal (the node's), and neither is about the
/// argument.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn what_does_not_exist_is_said_before_the_arguments_are_read() {
    let ctl = control_tweaked("order-state", |_| {});
    state(&ctl);
    let h = harness(ctl.clone()).await;
    let mut admin = Admin {
        ctx: h.ctx().clone(),
        ctl,
        embedded: Arc::new(AsyncMutex::new(HashMap::new())),
        _broker: None,
    };
    let who = Caller {
        origin: None,
        perm: Perm::Config,
        claims: None,
        signer: None,
    };
    // the node of each path of the full broker, as a node that does not exist
    let gone = |path: &str| -> Option<String> {
        let segs: Vec<&str> = path.split('/').collect();
        Some(match segs.as_slice() {
            ["links", _] => "links/gone".into(),
            ["packages", _] => "packages/gone".into(),
            ["tokens", _] => "tokens/gone".into(),
            ["upstream", _] => "upstream/gone".into(),
            ["quarantine", _] => "quarantine/gone".into(),
            ["backups", "<id>"] => "backups/gone".into(),
            ["history", "sinks"] => return None,
            ["history", "sinks", _] => "history/sinks/gone".into(),
            ["history", g, _] => format!("history/{g}/gone"),
            ["history", _] => "history/gone".into(),
            _ => return None,
        })
    };
    let snapshot = std::fs::read_to_string(SNAPSHOT).unwrap();
    let mut calls = std::collections::BTreeSet::new();
    for line in snapshot.lines().filter_map(|l| l.strip_prefix("[full] ")) {
        let Some((path, rest)) = line.split_once(" ▸ ") else {
            continue;
        };
        let action = rest.split(' ').next().unwrap_or_default();
        if action == "hello" {
            // a handshake answers for itself: an unknown id is a refused token
            continue;
        }
        if let Some(p) = gone(path) {
            calls.insert((p, action.to_owned()));
        }
    }
    // every node action of the snapshot but `hello`: a new one is one more call
    assert_eq!(calls.len(), 33, "{calls:?}");
    for (path, action) in &calls {
        let mut answers = Vec::new();
        for a in [args(&[]), args(&[("zz", Value::UInt(1))])] {
            let e = admin
                .on_invoke(path, action, a, &who, wyrm_link_sdk::harness::unread_sink())
                .await
                .map(|_| ())
                .unwrap_err();
            assert!(
                !e.message.contains("zz"),
                "{path} ▸ {action}: {}",
                e.message
            );
            answers.push((e.status, e.message));
        }
        assert_eq!(answers[0], answers[1], "{path} ▸ {action}");
    }
    h.stop().await;
}
