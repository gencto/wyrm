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

use super::tests::control_tweaked;
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
