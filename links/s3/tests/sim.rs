//! The s3 link against its simulator.

use wyrm_core::Value;
use wyrm_filestore::testkit::{bootstrap, map, refused, scenario, state, wait, Ext, H, SEED};
use wyrm_link_s3::sim::{self, Mode, Shared};
use wyrm_link_s3::S3Store;

async fn setup(
    secret: &str,
    extra: &[(&str, Value)],
) -> (H<S3Store>, Shared, tokio::task::JoinHandle<()>) {
    setup_with(secret, extra, |_| {}).await
}

/// `prepare` changes the bucket before the link starts (with `refresh_s`
/// 0 the link reads it once).
async fn setup_with(
    secret: &str,
    extra: &[(&str, Value)],
    prepare: impl FnOnce(&mut sim::State),
) -> (H<S3Store>, Shared, tokio::task::JoinHandle<()>) {
    let (addr, st, task) = sim::spawn("127.0.0.1:0").await.unwrap();
    {
        let mut s = st.lock().unwrap();
        for (k, v) in SEED {
            s.put(k, v.as_bytes());
        }
        // a key outside the connection's prefix never shows
        s.put("other/x.txt", b"x");
        prepare(&mut s);
    }
    let mut kv = vec![
        ("endpoint", Value::Str(format!("http://{addr}"))),
        ("bucket", "plant".into()),
        ("access_key_id", "AKIASIM".into()),
        ("secret_access_key", secret.into()),
        ("refresh_s", Value::Float(0.0)),
    ];
    kv.extend(extra.iter().cloned());
    let h = H::<S3Store>::start(bootstrap(map(&kv))).await;
    (h, st, task)
}

#[tokio::test(flavor = "multi_thread")]
async fn bucket_tree_folders_uploads() {
    let (h, st, _task) = setup_with("sim-secret-key", &[], |s| {
        // pages of two keys: continuation tokens
        s.page = 2;
        // the scenario's seed only
        s.objects.remove("other/x.txt");
    })
    .await;
    let ext = |e: Ext<'_>| {
        let mut s = st.lock().unwrap();
        match e {
            Ext::Put(k, v) => s.put(k, v),
            Ext::Delete(k) => {
                s.objects.remove(k);
            }
        }
    };
    scenario(&h, &ext).await;
    // the folder marker of Create Folder, and the deletes
    {
        let s = st.lock().unwrap();
        assert!(!s.objects.keys().any(|k| k.starts_with("reports/new dir")));
        assert!(s.seen.iter().any(|r| r.contains("continuation-token")));
    }
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn prefix_is_the_root() {
    let (h, st, _task) = setup("sim-secret-key", &[("prefix", "reports".into())]).await;
    wait("connected", 10, || state(&h, "c1") == Some("connected")).await;
    wait("tree", 10, || h.ctx().has_node("c1/files/2026/october.csv")).await;
    assert!(!h.ctx().has_node("c1/files/config"));
    let r = wyrm_filestore::testkit::ok(
        &h,
        "c1/files",
        "upload",
        map(&[("name", "n.txt".into()), ("text", "n".into())]),
    )
    .await;
    assert!(r.is_some());
    assert!(st.lock().unwrap().objects.contains_key("reports/n.txt"));
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn wrong_secret_fails() {
    let (h, _st, _task) = setup("wrong", &[]).await;
    refused(&h).await;
    assert!(wyrm_filestore::testkit::error(&h, "c1")
        .unwrap()
        .contains("SignatureDoesNotMatch"));
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn store_down_then_back() {
    use wyrm_core::Status;
    use wyrm_filestore::testkit::{act, status};
    let (h, st, _task) = setup("sim-secret-key", &[]).await;
    wait("connected", 10, || state(&h, "c1") == Some("connected")).await;
    st.lock().unwrap().mode = Mode::Status(503);
    let (a, _) = act(&h, "c1", "refresh", map(&[])).await;
    assert_eq!(status(&a), Status::Disconnected);
    // the failed request wakes the connection: the probe fails it
    wait("failed", 10, || state(&h, "c1") == Some("failed")).await;
    assert!(wyrm_filestore::testkit::error(&h, "c1").is_some());
    st.lock().unwrap().mode = Mode::Normal;
    wait("connected again", 15, || {
        state(&h, "c1") == Some("connected")
    })
    .await;
    assert!(wyrm_filestore::testkit::error(&h, "c1").is_none());
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn silent_store_times_out() {
    let (h, _st, _task) = setup_with("sim-secret-key", &[("timeout_ms", Value::UInt(500))], |s| {
        s.mode = Mode::Silent;
    })
    .await;
    refused(&h).await;
    assert!(wyrm_filestore::testkit::error(&h, "c1")
        .unwrap()
        .contains("no reply"));
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn runtime_connections_are_kept_sealed() {
    use wyrm_filestore::testkit::{act, ok, status};
    use wyrm_link_sdk::{Secret, TestHarness};
    let (addr, st, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    st.lock().unwrap().put("a.txt", b"a");
    let dir = std::env::temp_dir().join(format!("wyrm-s3-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let tune = |c: &mut wyrm_link_sdk::LinkConfig| {
        c.data_dir = Some(dir.clone());
        c.secrets.insert(
            wyrm_link_sdk::driver::persist::STORE_KEY,
            Secret::new(vec![7u8; 32]),
        );
    };
    let h =
        TestHarness::<wyrm_link_s3::S3>::start_with(wyrm_filestore::Bootstrap(Value::Null), tune)
            .await;
    let args = map(&[
        ("name", "added".into()),
        ("endpoint", Value::Str(format!("http://{addr}"))),
        ("bucket", "plant".into()),
        ("access_key_id", "AKIASIM".into()),
        ("secret_access_key", "sim-secret-key".into()),
    ]);
    ok(&h, "", "add_connection", args.clone()).await;
    wait("connected", 10, || state(&h, "added") == Some("connected")).await;
    let (a, _) = act(&h, "", "add_connection", args).await;
    assert_eq!(
        status(&a),
        wyrm_core::Status::InvalidParameter,
        "the name is taken"
    );
    h.stop().await;
    let file = std::fs::read(dir.join("filestore.conns")).unwrap();
    assert!(!file.windows(14).any(|w| w == b"sim-secret-key"), "sealed");
    // a restart reads it back, secret included
    let h =
        TestHarness::<wyrm_link_s3::S3>::start_with(wyrm_filestore::Bootstrap(Value::Null), tune)
            .await;
    wait("connected after restart", 10, || {
        state(&h, "added") == Some("connected")
    })
    .await;
    wait("tree", 10, || h.ctx().has_node("added/files/a.txt")).await;
    ok(&h, "added", "remove", map(&[])).await;
    assert!(!h.ctx().has_node("added"));
    h.stop().await;
    let _ = std::fs::remove_dir_all(&dir);
}

/// Stop cuts an action in flight: a recursive delete stuck on a silent
/// store answers at once and deletes nothing after the stop.
#[tokio::test(flavor = "multi_thread")]
async fn stop_cuts_actions_in_flight() {
    use std::time::{Duration, Instant};
    use wyrm_filestore::testkit::{act, status};
    let (h, st, _task) = setup_with(
        "sim-secret-key",
        &[("timeout_ms", Value::UInt(30_000))],
        |_| {},
    )
    .await;
    wait("tree", 10, || {
        h.ctx().has_node("c1/files/reports/readme.txt")
    })
    .await;
    st.lock().unwrap().mode = Mode::Silent;
    let started = Instant::now();
    let delete = act(
        &h,
        "c1/files/reports",
        "delete",
        map(&[("recursive", Value::Bool(true))]),
    );
    let stop = async {
        tokio::time::sleep(Duration::from_millis(300)).await;
        act(&h, "c1", "stop", map(&[])).await
    };
    let ((a, _), (b, _)) = tokio::join!(delete, stop);
    assert_eq!(status(&b), wyrm_core::Status::Ok);
    assert_eq!(status(&a), wyrm_core::Status::Disconnected, "{:?}", a.err);
    assert!(
        started.elapsed() < Duration::from_secs(10),
        "cut, not timed out"
    );
    {
        let mut s = st.lock().unwrap();
        s.mode = Mode::Normal;
        assert!(
            !s.seen.iter().any(|r| r.starts_with("DELETE")),
            "nothing deleted"
        );
        assert!(s.objects.contains_key("reports/readme.txt"));
    }
    h.stop().await;
}

/// 11 MiB in parts: a multipart upload of 5 MiB parts to the bucket.
#[tokio::test(flavor = "multi_thread")]
async fn large_files_in_parts() {
    let (h, st, _task) = setup_with(
        "sim-secret-key",
        &[("multipart_mib", Value::UInt(5))],
        |s| {
            s.objects.remove("other/x.txt");
        },
    )
    .await;
    wyrm_filestore::testkit::parts_scenario(&h, 11 * 1024 * 1024 + 123).await;
    {
        let s = st.lock().unwrap();
        assert!(
            s.seen.iter().any(|r| r.contains("uploads")),
            "multipart used"
        );
        assert!(s.multipart.is_empty(), "no upload left open");
    }
    h.stop().await;
}
