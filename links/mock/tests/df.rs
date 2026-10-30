//! Driver framework (ADR 0004) behaviour, through the `mockdev` driver.

use std::collections::BTreeMap;
use std::time::Duration;
use wyrm_core::{Perm, Quality, Status, Value};
use wyrm_link_mock::df::MockDev;
use wyrm_link_sdk::driver::{Framework, Tree};
use wyrm_link_sdk::TestHarness;

type H = TestHarness<Framework<MockDev>>;

fn map(kv: &[(&str, Value)]) -> Value {
    Value::Map(
        kv.iter()
            .map(|(k, v)| ((*k).to_owned(), v.clone()))
            .collect(),
    )
}

/// `poll_unsubscribed: true` is the default and left out; `false` gates
/// polling on subscribers.
fn tree(conn: Value, poll_unsubscribed: bool) -> Tree {
    let mut top = vec![("connections", map(&[("c1", conn)]))];
    if !poll_unsubscribed {
        top.push(("poll_unsubscribed", Value::Bool(false)));
    }
    Tree(map(&top))
}

fn conn(extra: &[(&str, Value)], devices: Value) -> Value {
    let mut kv: Vec<(&str, Value)> = extra.to_vec();
    kv.push(("devices", devices));
    map(&kv)
}

fn dev(extra: &[(&str, Value)], points: Value) -> Value {
    let mut kv: Vec<(&str, Value)> = extra.to_vec();
    kv.push(("points", points));
    map(&kv)
}

/// c1/d1 with a fast counter `n`, a writable constant `w` and an
/// exception point `x`.
fn standard() -> Value {
    conn(
        &[],
        map(&[(
            "d1",
            dev(
                &[("ping_s", Value::Float(0.1))],
                map(&[
                    (
                        "n",
                        map(&[("kind", "counter".into()), ("poll_s", Value::Float(0.05))]),
                    ),
                    (
                        "w",
                        map(&[
                            ("kind", "constant".into()),
                            ("poll_s", Value::Float(0.05)),
                            ("writable", Value::Bool(true)),
                            ("initial", Value::Float(1.0)),
                        ]),
                    ),
                    (
                        "x",
                        map(&[
                            ("fail", "exception".into()),
                            ("poll_s", Value::Float(0.05)),
                            ("writable", Value::Bool(true)),
                        ]),
                    ),
                ]),
            ),
        )]),
    )
}

/// The `status` enum leaf as a state name (`connected`, `failed`, …).
fn state(h: &H, base: &str) -> Option<String> {
    match h.ctx().last(&format!("{base}/status"))?.v {
        Value::UInt(i) => wyrm_link_sdk::driver::NodeState::NAMES
            .get(i as usize)
            .map(|s| (*s).to_owned()),
        _ => None,
    }
}

async fn wait(what: &str, mut f: impl FnMut() -> bool) {
    let deadline = tokio::time::Instant::now() + Duration::from_secs(4);
    while !f() {
        assert!(tokio::time::Instant::now() < deadline, "timeout: {what}");
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
}

fn status(a: &wyrm_core::Attachment) -> Option<Status> {
    match a.status? {
        wyrm_core::status::StatusCode::Known(s) => Some(s),
        _ => None,
    }
}

async fn act(h: &H, path: &str, action: &str, args: Value) -> wyrm_core::Attachment {
    h.invoke(path, action, args, Some(h.ptok(Perm::Config)))
        .await
        .remove(0)
        .att
}

#[tokio::test(flavor = "multi_thread")]
async fn tree_states_and_values() {
    let h = H::start(tree(standard(), true)).await;
    let (_, top) = h.list("c1").await;
    assert_eq!(top.len(), 2, "status + d1");
    wait("connected", || {
        state(&h, "c1").as_deref() == Some("connected")
    })
    .await;
    wait("device connected", || {
        state(&h, "c1/d1").as_deref() == Some("connected")
    })
    .await;
    wait("counter polls", || {
        h.ctx()
            .last("c1/d1/n")
            .is_some_and(|s| s.v.as_f64().unwrap_or(0.0) > 2.0)
    })
    .await;
    // a protocol exception marks one point, not the device
    wait("x bad", || {
        h.ctx().last("c1/d1/x").is_some_and(|s| s.q == Quality::Bad)
    })
    .await;
    assert_eq!(state(&h, "c1/d1").as_deref(), Some("connected"));
    // generated forms: edit pre-filled with the current config
    let (_, m) = h.meta("c1/d1").await;
    let m = m.unwrap();
    let edit = &m.actions.as_ref().unwrap()["edit"];
    assert_eq!(edit.params["ping_s"].default, Some(Value::Float(0.1)));
    assert_eq!(m.cfg.unwrap()["unit"], Value::UInt(1));
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn polls_only_while_subscribed() {
    let h = H::start(tree(standard(), false)).await;
    wait("device connected", || {
        state(&h, "c1/d1").as_deref() == Some("connected")
    })
    .await;
    tokio::time::sleep(Duration::from_millis(300)).await;
    assert!(
        h.ctx().last("c1/d1/n").is_none(),
        "nobody subscribed: no polls"
    );
    let sub = h
        .session()
        .declare_subscriber(h.key("c1/d1/n", "~val"))
        .await
        .unwrap();
    tokio::time::timeout(Duration::from_secs(2), sub.recv_async())
        .await
        .expect("polling starts with a subscriber")
        .unwrap();
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn connection_down_cascades() {
    let h = H::start(tree(
        conn(
            &[("down", Value::Bool(true))],
            map(&[("d1", dev(&[], map(&[])))]),
        ),
        true,
    ))
    .await;
    wait("conn failed", || {
        state(&h, "c1").as_deref() == Some("failed")
    })
    .await;
    wait("device stopped by parent", || {
        state(&h, "c1/d1").as_deref() == Some("stopped_by_parent")
    })
    .await;
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn quality_ladder_on_silent_device() {
    let h = H::start(tree(standard(), true)).await;
    wait("good value", || {
        h.ctx()
            .last("c1/d1/w")
            .is_some_and(|s| s.q == Quality::Good)
    })
    .await;
    let mut args = BTreeMap::new();
    args.insert("silent".to_owned(), Value::Bool(true));
    args.insert("ping_s".to_owned(), Value::Float(0.1));
    assert_eq!(
        status(&act(&h, "c1/d1", "edit", Value::Map(args)).await),
        Some(Status::Ok)
    );
    wait("uncertain/stale then bad/comm_fail", || {
        h.ctx().last("c1/d1/w").is_some_and(|s| s.q == Quality::Bad)
    })
    .await;
    assert_eq!(
        h.ctx().last("c1/d1/w").unwrap().v,
        Value::Float(1.0),
        "value kept"
    );
    wait("device failed", || {
        state(&h, "c1/d1").as_deref() == Some("failed")
    })
    .await;
    assert_eq!(
        state(&h, "c1").as_deref(),
        Some("connected"),
        "connection is fine"
    );
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn writes_read_back_without_optimism() {
    let h = H::start(tree(standard(), true)).await;
    wait("w polled", || h.ctx().last("c1/d1/w").is_some()).await;
    let att = h.set("c1/d1/w", 42.0, Some(h.ptok(Perm::Write))).await;
    assert_eq!(status(&att), Some(Status::Ok));
    assert_eq!(
        h.ctx().last("c1/d1/w").unwrap().v,
        Value::Float(42.0),
        "read back"
    );
    // a refused write leaves the tree alone
    let before = h.ctx().last("c1/d1/x");
    let att = h.set("c1/d1/x", 5.0, Some(h.ptok(Perm::Write))).await;
    assert_eq!(status(&att), Some(Status::InvalidParameter));
    assert_eq!(h.ctx().last("c1/d1/x").map(|s| s.v), before.map(|s| s.v));
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn rejected_edit_changes_nothing() {
    let h = H::start(tree(standard(), true)).await;
    wait("connected", || {
        state(&h, "c1").as_deref() == Some("connected")
    })
    .await;
    let before = h
        .invoke(
            "",
            "export",
            Value::Map(Default::default()),
            Some(h.ptok(Perm::Config)),
        )
        .await
        .remove(0)
        .value();
    let mut args = BTreeMap::new();
    args.insert("latency_ms".to_owned(), Value::UInt(99_999));
    let att = act(&h, "c1", "edit", Value::Map(args)).await;
    assert_eq!(status(&att), Some(Status::InvalidParameter));
    assert_eq!(att.err.as_deref(), Some("latency_ms: 99999 > max 10000"));
    let after = h
        .invoke(
            "",
            "export",
            Value::Map(Default::default()),
            Some(h.ptok(Perm::Config)),
        )
        .await
        .remove(0)
        .value();
    assert_eq!(before, after);
    assert_eq!(state(&h, "c1").as_deref(), Some("connected"));
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn invalid_config_keeps_the_node() {
    let t = tree(
        conn(
            &[],
            map(&[
                ("bad", dev(&[("unit", Value::UInt(0))], map(&[]))),
                (
                    "ok",
                    dev(&[], map(&[("p", map(&[("poll_s", Value::Float(-1.0))]))])),
                ),
            ]),
        ),
        true,
    );
    let h = H::start(t).await;
    wait("bad device failed", || {
        state(&h, "c1/bad").as_deref() == Some("failed")
    })
    .await;
    let (_, m) = h.meta("c1/bad").await;
    assert!(m.is_some(), "node kept");
    let p = h
        .ctx()
        .last("c1/ok/p")
        .expect("point kept with an error value");
    assert_eq!(p.q, Quality::Bad);
    // fixing it through edit brings it up
    let mut args = BTreeMap::new();
    args.insert("unit".to_owned(), Value::UInt(5));
    assert_eq!(
        status(&act(&h, "c1/bad", "edit", Value::Map(args)).await),
        Some(Status::Ok)
    );
    wait("fixed device runs", || {
        state(&h, "c1/bad").as_deref() == Some("connected")
    })
    .await;
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn slow_device_does_not_pile_up() {
    let t = tree(
        conn(
            &[("latency_ms", Value::UInt(300))],
            map(&[(
                "d1",
                dev(
                    &[("ping_s", Value::Float(100.0))],
                    map(&[(
                        "n",
                        map(&[("kind", "counter".into()), ("poll_s", Value::Float(0.02))]),
                    )]),
                ),
            )]),
        ),
        true,
    );
    let h = H::start(t).await;
    tokio::time::sleep(Duration::from_millis(1300)).await;
    let n = h
        .ctx()
        .last("c1/d1/n")
        .map(|s| s.v.as_f64().unwrap())
        .unwrap_or(0.0);
    assert!(
        (2.0..=5.0).contains(&n),
        "{n} polls in 1.3 s at 300 ms each (not ~65)"
    );
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn add_and_remove() {
    let h = H::start(tree(conn(&[], map(&[])), true)).await;
    let mut a = BTreeMap::new();
    a.insert("name".to_owned(), Value::from("d2"));
    assert_eq!(
        status(&act(&h, "c1", "add_device", Value::Map(a)).await),
        Some(Status::Ok)
    );
    let mut a = BTreeMap::new();
    a.insert("name".to_owned(), Value::from("q"));
    a.insert("kind".to_owned(), Value::from("counter"));
    a.insert("poll_s".to_owned(), Value::Float(0.05));
    assert_eq!(
        status(&act(&h, "c1/d2", "add_point", Value::Map(a)).await),
        Some(Status::Ok)
    );
    wait("new point polls", || h.ctx().last("c1/d2/q").is_some()).await;
    // the reserved name is refused
    let mut a = BTreeMap::new();
    a.insert("name".to_owned(), Value::from("status"));
    assert_eq!(
        status(&act(&h, "c1/d2", "add_point", Value::Map(a)).await),
        Some(Status::InvalidParameter)
    );
    assert_eq!(
        status(&act(&h, "c1/d2", "remove", Value::Map(Default::default())).await),
        Some(Status::Ok)
    );
    let (att, _) = h.meta("c1/d2").await;
    assert_eq!(status(&att), Some(Status::NotFound));
    h.stop().await;
}

fn temp_dir(name: &str) -> std::path::PathBuf {
    let d = std::env::temp_dir().join(format!("wyrm-df-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&d);
    std::fs::create_dir_all(&d).unwrap();
    d
}

/// A harness with a `data_dir` and a store key, as `wyrmd` gives every link.
async fn start_stored(tree: Tree, dir: &std::path::Path, key: [u8; 32]) -> H {
    let dir = dir.to_owned();
    H::start_with(tree, move |lc| {
        lc.data_dir = Some(dir);
        lc.secrets.insert(
            wyrm_link_sdk::driver::persist::STORE_KEY,
            wyrm_link_sdk::Secret::new(key.to_vec()),
        );
    })
    .await
}

/// Runtime edits survive a restart, sealed in `data_dir`; secrets never
/// show; an empty secret on `edit` keeps the stored one only while the
/// destination stays; new bootstrap params replace the stored tree.
#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn runtime_edits_and_secrets_are_kept() {
    let dir = temp_dir("persist");
    let key = [7u8; 32];
    let boot = || tree(standard(), true);
    let h = start_stored(boot(), &dir, key).await;
    let a = act(
        &h,
        "",
        "add_connection",
        map(&[
            ("name", "c2".into()),
            ("need_token", Value::Bool(true)),
            ("token", "s3cret-pw".into()),
        ]),
    )
    .await;
    assert_eq!(status(&a), Some(Status::Ok), "{a:?}");
    wait("c2 connected", || {
        state(&h, "c2").as_deref() == Some("connected")
    })
    .await;
    h.stop().await;

    // Sealed: the secret is not readable in the file.
    let raw = std::fs::read(dir.join("framework.tree")).unwrap();
    assert!(!raw.windows(9).any(|w| w == b"s3cret-pw"));
    assert!(!raw.windows(10).any(|w| w == b"need_token"));

    // Restart, same bootstrap: c2 is back and connects with its token.
    let h = start_stored(boot(), &dir, key).await;
    wait("c2 back", || {
        state(&h, "c2").as_deref() == Some("connected")
    })
    .await;
    let ex = h
        .invoke("", "export", map(&[]), Some(h.ptok(Perm::Config)))
        .await
        .remove(0)
        .value()
        .unwrap();
    assert!(
        !format!("{ex:?}").contains("s3cret-pw"),
        "export hides secrets"
    );
    let (_, meta) = h.meta("c2").await;
    assert!(
        !format!("{meta:?}").contains("s3cret-pw"),
        "~meta hides secrets"
    );

    // Edit without the token, same destination: the token is kept.
    let a = act(
        &h,
        "c2",
        "edit",
        map(&[
            ("need_token", Value::Bool(true)),
            ("latency_ms", Value::UInt(1)),
        ]),
    )
    .await;
    assert_eq!(status(&a), Some(Status::Ok), "{a:?}");
    wait("still connected", || {
        state(&h, "c2").as_deref() == Some("connected")
    })
    .await;
    // Another host without the token: the stored token is dropped.
    let a = act(
        &h,
        "c2",
        "edit",
        map(&[("need_token", Value::Bool(true)), ("host", "evil".into())]),
    )
    .await;
    assert_eq!(status(&a), Some(Status::Ok), "{a:?}");
    wait("c2 fails without its token", || {
        state(&h, "c2").as_deref() == Some("failed")
    })
    .await;
    h.stop().await;

    // A wrong store key: the stored tree does not open; bootstrap is used.
    let h = start_stored(boot(), &dir, [8u8; 32]).await;
    wait("c1 up", || state(&h, "c1").as_deref() == Some("connected")).await;
    assert!(state(&h, "c2").is_none(), "sealed with another key");
    h.stop().await;

    // New bootstrap params win over the stored tree.
    let h = start_stored(tree(standard(), false), &dir, key).await;
    wait("c1 up", || state(&h, "c1").as_deref() == Some("connected")).await;
    assert!(
        state(&h, "c2").is_none(),
        "bootstrap changed: stored tree replaced"
    );
    h.stop().await;
    let _ = std::fs::remove_dir_all(dir);
}

/// The DSA shape of a connection: `status` enum leaf, an `error` leaf only
/// while there is an error, `stop` or `start` (whichever applies), actions
/// with names for people and menu groups.
#[tokio::test(flavor = "multi_thread")]
async fn dsa_node_shape() {
    use wyrm_core::meta::{GROUP_EDIT, GROUP_NEW};
    let h = H::start(tree(standard(), true)).await;
    wait("connected", || {
        state(&h, "c1").as_deref() == Some("connected")
    })
    .await;

    let (_, st) = h.meta("c1/status").await;
    let st = st.unwrap();
    assert_eq!(st.ty, Some(wyrm_core::TypeCode::Enum));
    assert_eq!(
        st.enum_values.as_deref().unwrap()[2],
        "Connected",
        "DSA labels"
    );
    assert!(!h.ctx().has_node("c1/error"), "no error, no leaf");

    let actions = |m: &wyrm_core::NodeMeta| m.actions.clone().unwrap_or_default();
    let (_, m) = h.meta("c1").await;
    let a = actions(&m.unwrap());
    assert_eq!(a["add_device"].display.as_deref(), Some("Add Device"));
    assert_eq!(a["add_device"].group.as_deref(), Some(GROUP_NEW));
    assert_eq!(
        a["add_device"].params["name"].display.as_deref(),
        Some("Name")
    );
    assert_eq!(a["edit"].group.as_deref(), Some(GROUP_EDIT));
    assert_eq!(a["remove"].group.as_deref(), Some(GROUP_EDIT));
    assert_eq!(a["restart"].display.as_deref(), Some("Restart"));
    assert!(a.contains_key("stop") && !a.contains_key("start"));
    let (_, root) = h.meta("").await;
    let r = actions(&root.unwrap());
    assert_eq!(
        r["add_connection"].display.as_deref(),
        Some("Add Connection")
    );
    assert_eq!(r["export"].display.as_deref(), Some("Export"));

    // stop: only `start` is offered, the state is Stopped
    assert_eq!(
        status(&act(&h, "c1", "stop", map(&[])).await),
        Some(Status::Ok)
    );
    wait("stopped", || state(&h, "c1").as_deref() == Some("stopped")).await;
    let (_, m) = h.meta("c1").await;
    let a = actions(&m.unwrap());
    assert!(a.contains_key("start") && !a.contains_key("stop"));
    assert_eq!(
        status(&act(&h, "c1", "start", map(&[])).await),
        Some(Status::Ok)
    );
    wait("connected again", || {
        state(&h, "c1").as_deref() == Some("connected")
    })
    .await;

    // a failure shows in `error`; it goes away when the failure clears
    assert_eq!(
        status(&act(&h, "c1", "edit", map(&[("down", Value::Bool(true))])).await),
        Some(Status::Ok)
    );
    wait("error leaf", || {
        h.ctx()
            .last("c1/error")
            .is_some_and(|s| s.v == Value::from("transport: connection refused"))
    })
    .await;
    assert_eq!(state(&h, "c1").as_deref(), Some("failed"));
    assert_eq!(
        status(&act(&h, "c1", "edit", map(&[("down", Value::Bool(false))])).await),
        Some(Status::Ok)
    );
    wait("connected, no error", || {
        state(&h, "c1").as_deref() == Some("connected") && !h.ctx().has_node("c1/error")
    })
    .await;
    h.stop().await;
}

/// Folders are opt-in (`Driver::FOLDERS`, ruling 10): `mockdev` has none, so
/// its devices declare no `add_folder`, an invoke of it is refused, and the
/// export has no `folders` key.
#[tokio::test(flavor = "multi_thread")]
async fn driver_without_folders_has_no_add_folder() {
    let h = H::start(tree(standard(), true)).await;
    let (_, meta) = h.meta("c1/d1").await;
    let actions = meta.expect("c1/d1").actions.unwrap_or_default();
    assert!(actions.contains_key("add_point"));
    assert!(!actions.contains_key("add_folder"), "{:?}", actions.keys());
    let a = act(&h, "c1/d1", "add_folder", map(&[("name", "f1".into())])).await;
    assert_ne!(status(&a), Some(Status::Ok));
    let (_, meta) = h.meta("c1/d1/f1").await;
    assert!(meta.is_none());
    let ex = h
        .invoke("", "export", map(&[]), Some(h.ptok(Perm::Config)))
        .await
        .remove(0)
        .value()
        .unwrap();
    assert!(!format!("{ex:?}").contains("folders"), "{ex:?}");
    h.stop().await;
}
