//! The webdav link against its simulator.

use wyrm_core::Value;
use wyrm_filestore::testkit::{bootstrap, map, refused, scenario, state, wait, Ext, H, SEED};
use wyrm_link_webdav::sim::{self, Mode, Shared, BASE};
use wyrm_link_webdav::WebDavStore;

async fn setup(
    password: &str,
    url_tail: &str,
) -> (H<WebDavStore>, Shared, tokio::task::JoinHandle<()>) {
    let (addr, st, task) = sim::spawn("127.0.0.1:0").await.unwrap();
    {
        let mut s = st.lock().unwrap();
        s.basic = Some(("alice".into(), "app-pass".into()));
        for (k, v) in SEED {
            s.put(k, v.as_bytes());
        }
    }
    let conn = map(&[
        ("url", Value::Str(format!("http://{addr}{BASE}{url_tail}"))),
        ("username", "alice".into()),
        ("password", password.into()),
        ("refresh_s", Value::Float(0.0)),
    ]);
    (H::<WebDavStore>::start(bootstrap(conn)).await, st, task)
}

#[tokio::test(flavor = "multi_thread")]
async fn collection_tree_folders_uploads() {
    let (h, st, _t) = setup("app-pass", "/").await;
    let ext = |e: Ext<'_>| {
        let mut s = st.lock().unwrap();
        match e {
            Ext::Put(p, v) => s.put(p, v),
            Ext::Delete(p) => s.remove(p),
        }
    };
    scenario(&h, &ext).await;
    {
        let s = st.lock().unwrap();
        assert!(s
            .seen
            .iter()
            .any(|r| r.starts_with("MKCOL ") && r.contains("new%20dir")));
        assert!(!s.nodes.contains_key("reports/new dir"));
    }
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn a_subfolder_as_the_root() {
    let (h, _st, _t) = setup("app-pass", "/reports").await;
    wait("connected", 10, || state(&h, "c1") == Some("connected")).await;
    wait("tree", 10, || h.ctx().has_node("c1/files/2026/october.csv")).await;
    assert!(h.ctx().has_node("c1/files/readme.txt"));
    assert!(!h.ctx().has_node("c1/files/config"));
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn wrong_password_fails() {
    let (h, _st, _t) = setup("nope", "").await;
    refused(&h).await;
    assert!(wyrm_filestore::testkit::error(&h, "c1")
        .unwrap()
        .contains("401"));
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn server_errors_fail_then_recover() {
    let (h, st, _t) = setup("app-pass", "").await;
    wait("connected", 10, || state(&h, "c1") == Some("connected")).await;
    st.lock().unwrap().mode = Mode::Status(500);
    let (a, _) = wyrm_filestore::testkit::act(&h, "c1", "refresh", map(&[])).await;
    assert_eq!(
        wyrm_filestore::testkit::status(&a),
        wyrm_core::Status::Disconnected
    );
    wait("failed", 10, || state(&h, "c1") == Some("failed")).await;
    st.lock().unwrap().mode = Mode::Normal;
    wait("connected again", 15, || {
        state(&h, "c1") == Some("connected")
    })
    .await;
    h.stop().await;
}

/// Delete without `recursive` fails closed: a response the client cannot
/// map is content, and the collection stays.
#[tokio::test(flavor = "multi_thread")]
async fn delete_without_recursive_fails_closed() {
    use wyrm_core::Status;
    use wyrm_filestore::testkit::{act, ok, status};
    let (h, st, _t) = setup("app-pass", "/").await;
    wait("connected", 10, || state(&h, "c1") == Some("connected")).await;
    ok(
        &h,
        "c1/files",
        "create_folder",
        map(&[("name", "box".into())]),
    )
    .await;
    st.lock().unwrap().odd_href = Some("/elsewhere/%zz".into());
    let (a, _) = act(&h, "c1/files/box", "delete", map(&[])).await;
    assert_eq!(status(&a), Status::InvalidParameter, "{:?}", a.err);
    assert!(st.lock().unwrap().nodes.contains_key("box"));
    st.lock().unwrap().odd_href = None;
    // a 207 without any response says nothing about the content
    st.lock().unwrap().empty_depth1 = true;
    let (a, _) = act(&h, "c1/files/box", "delete", map(&[])).await;
    assert_eq!(status(&a), Status::InvalidParameter, "{:?}", a.err);
    assert!(st.lock().unwrap().nodes.contains_key("box"));
    st.lock().unwrap().empty_depth1 = false;
    ok(&h, "c1/files/box", "delete", map(&[])).await;
    assert!(!st.lock().unwrap().nodes.contains_key("box"));
    h.stop().await;
}

/// A file in parts: one streamed PUT of the spool file.
#[tokio::test(flavor = "multi_thread")]
async fn large_files_in_parts() {
    let (h, st, _t) = setup("app-pass", "/").await;
    wyrm_filestore::testkit::parts_scenario(&h, 7 * 1024 * 1024 + 99).await;
    assert_eq!(
        st.lock().unwrap().nodes["reports/big.bin"].data.len(),
        200_000,
        "overwritten last"
    );
    h.stop().await;
}
