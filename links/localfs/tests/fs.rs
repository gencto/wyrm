//! The localfs link on a temporary directory.

use std::path::{Path, PathBuf};
use wyrm_core::{Status, Value};
use wyrm_filestore::testkit::{
    act, bootstrap_with, map, ok, refused, scenario, state, status, wait, Ext, H, SEED,
};
use wyrm_link_localfs::LocalStore;

/// A fresh directory per test, removed when dropped.
struct Dir(PathBuf);

impl Dir {
    fn new(name: &str) -> Self {
        let d = std::env::temp_dir().join(format!("wyrm-localfs-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        Dir(d)
    }

    fn put(&self, path: &str, data: &[u8]) {
        let p = self.0.join(path);
        std::fs::create_dir_all(p.parent().unwrap()).unwrap();
        std::fs::write(p, data).unwrap();
    }
}

impl Drop for Dir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

async fn start(root: &Path, extra: &[(&str, Value)]) -> H<LocalStore> {
    let mut kv = vec![
        ("root", Value::Str(root.to_str().unwrap().into())),
        ("refresh_s", Value::Float(0.0)),
    ];
    kv.extend(extra.iter().cloned());
    H::<LocalStore>::start(bootstrap_with(map(&kv), &allowed())).await
}

/// The temporary directory as the one allowed root.
fn allowed() -> Vec<(&'static str, Value)> {
    vec![(
        "allowed_roots",
        Value::Str(std::env::temp_dir().to_str().unwrap().into()),
    )]
}

#[tokio::test(flavor = "multi_thread")]
async fn directory_tree_folders_uploads() {
    let d = Dir::new("scenario");
    for (k, v) in SEED {
        d.put(k, v.as_bytes());
    }
    // hidden files stay out by default
    d.put(".cache/x", b"x");
    let h = start(&d.0, &[]).await;
    let ext = |e: Ext<'_>| match e {
        Ext::Put(p, v) => d.put(p, v),
        Ext::Delete(p) => std::fs::remove_file(d.0.join(p)).unwrap(),
    };
    scenario(&h, &ext).await;
    assert!(!d.0.join("reports/new dir").exists());
    // no temporary files left by the overwrite
    let left: Vec<_> = walk(&d.0)
        .into_iter()
        .filter(|p| p.contains(".wyrm-"))
        .collect();
    assert!(left.is_empty(), "{left:?}");
    h.stop().await;
}

fn walk(p: &Path) -> Vec<String> {
    let mut out = Vec::new();
    for e in std::fs::read_dir(p).unwrap().flatten() {
        let path = e.path();
        out.push(path.to_string_lossy().into_owned());
        if path.is_dir() {
            out.extend(walk(&path));
        }
    }
    out
}

#[tokio::test(flavor = "multi_thread")]
async fn read_only_refuses_changes() {
    let d = Dir::new("ro");
    d.put("a.txt", b"a");
    let h = start(&d.0, &[("read_only", Value::Bool(true))]).await;
    wait("tree", 10, || h.ctx().has_node("c1/files/a.txt")).await;
    let (a, _) = act(
        &h,
        "c1/files",
        "upload",
        map(&[("name", "b.txt".into()), ("text", "b".into())]),
    )
    .await;
    assert_eq!(status(&a), Status::InvalidParameter);
    let (a, _) = act(&h, "c1/files/a.txt", "delete", map(&[])).await;
    assert_eq!(status(&a), Status::InvalidParameter);
    assert!(d.0.join("a.txt").exists());
    let v = ok(
        &h,
        "c1/files/a.txt",
        "download",
        map(&[("text", Value::Bool(true))]),
    )
    .await;
    assert_eq!(v, Some(Value::Str("a".into())));
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn missing_directory_fails_or_is_created() {
    let d = Dir::new("missing");
    let gone = d.0.join("not-yet");
    let h = start(&gone, &[]).await;
    refused(&h).await;
    h.stop().await;
    let h = start(&gone, &[("create_root", Value::Bool(true))]).await;
    wait("connected", 10, || state(&h, "c1") == Some("connected")).await;
    assert!(gone.is_dir());
    // the directory removed under a running connection: a refresh fails it
    std::fs::remove_dir_all(&gone).unwrap();
    let (a, _) = act(&h, "c1", "refresh", map(&[])).await;
    assert_ne!(status(&a), Status::Ok);
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn windows_unsafe_names_are_refused() {
    let d = Dir::new("names");
    let h = start(&d.0, &[]).await;
    wait("connected", 10, || state(&h, "c1") == Some("connected")).await;
    for name in ["a:b.txt", "CON", "x?"] {
        let (a, _) = act(
            &h,
            "c1/files",
            "upload",
            map(&[("name", name.into()), ("text", "x".into())]),
        )
        .await;
        assert_eq!(status(&a), Status::InvalidParameter, "{name}");
    }
    h.stop().await;
}

#[cfg(unix)]
#[tokio::test(flavor = "multi_thread")]
async fn symlinks_never_lead_out() {
    let outside = Dir::new("outside");
    outside.put("secret.txt", b"secret");
    let d = Dir::new("links");
    d.put("in/real.txt", b"real");
    std::os::unix::fs::symlink(outside.0.join("secret.txt"), d.0.join("leak.txt")).unwrap();
    std::os::unix::fs::symlink(&outside.0, d.0.join("leakdir")).unwrap();
    std::os::unix::fs::symlink(d.0.join("in/real.txt"), d.0.join("alias.txt")).unwrap();
    // not followed by default
    let h = start(&d.0, &[]).await;
    wait("tree", 10, || h.ctx().has_node("c1/files/in/real.txt")).await;
    assert!(!h.ctx().has_node("c1/files/alias.txt"));
    assert!(!h.ctx().has_node("c1/files/leak.txt"));
    h.stop().await;
    // followed: only the link that stays inside
    let h = start(&d.0, &[("follow_symlinks", Value::Bool(true))]).await;
    wait("alias", 10, || h.ctx().has_node("c1/files/alias.txt")).await;
    assert!(!h.ctx().has_node("c1/files/leak.txt"));
    assert!(!h.ctx().has_node("c1/files/leakdir"));
    let v = ok(
        &h,
        "c1/files/alias.txt",
        "download",
        map(&[("text", Value::Bool(true))]),
    )
    .await;
    assert_eq!(v, Some(Value::Str("real".into())));
    // deleting the link leaves its target
    ok(&h, "c1/files/alias.txt", "delete", map(&[])).await;
    assert!(d.0.join("in/real.txt").exists());
    // a folder swapped for a link out of the root after the read is refused
    std::fs::remove_dir_all(d.0.join("in")).unwrap();
    std::os::unix::fs::symlink(&outside.0, d.0.join("in")).unwrap();
    let (a, _) = act(
        &h,
        "c1/files/in",
        "upload",
        map(&[("name", "x.txt".into()), ("text", "x".into())]),
    )
    .await;
    assert_eq!(status(&a), Status::InvalidParameter);
    assert!(!outside.0.join("x.txt").exists());
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn the_brokers_data_directory_is_off_limits() {
    use wyrm_link_sdk::TestHarness;
    let broker = Dir::new("broker");
    let link_data = broker.0.join("links/files/data");
    std::fs::create_dir_all(&link_data).unwrap();
    broker.put("registry.bin", b"x");
    let other = Dir::new("other");
    let tune = |c: &mut wyrm_link_sdk::LinkConfig| c.data_dir = Some(link_data.clone());
    let h = TestHarness::<wyrm_link_localfs::LocalFs>::start_with(
        wyrm_filestore::Bootstrap(map(&allowed())),
        tune,
    )
    .await;
    for root in [broker.0.clone(), link_data.clone(), std::env::temp_dir()] {
        let (a, _) = act(
            &h,
            "",
            "add_connection",
            map(&[
                ("name", "x".into()),
                ("root", Value::Str(root.to_str().unwrap().into())),
            ]),
        )
        .await;
        assert_eq!(status(&a), Status::InvalidParameter, "{}", root.display());
    }
    ok(
        &h,
        "",
        "add_connection",
        map(&[
            ("name", "y".into()),
            ("root", Value::Str(other.0.to_str().unwrap().into())),
        ]),
    )
    .await;
    wait("connected", 10, || state(&h, "y") == Some("connected")).await;
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn only_allowed_directories() {
    use wyrm_link_sdk::TestHarness;
    let d = Dir::new("allowed");
    d.put("a.txt", b"a");
    // no allowed_roots: nothing is allowed
    let conn = map(&[("root", Value::Str(d.0.to_str().unwrap().into()))]);
    let h = H::<LocalStore>::start(wyrm_filestore::testkit::bootstrap(conn.clone())).await;
    wait("failed", 10, || state(&h, "c1") == Some("failed")).await;
    let e = wyrm_filestore::testkit::error(&h, "c1").unwrap();
    assert!(e.contains("allowed_roots"), "{e}");
    h.stop().await;
    // a connection outside the allowed roots is refused; /proc never
    // two lines: a blank one is ignored
    let opts = [(
        "allowed_roots",
        Value::Str(format!("\n{}\n", d.0.join("sub").to_str().unwrap())),
    )];
    let h = TestHarness::<wyrm_link_localfs::LocalFs>::start(wyrm_filestore::Bootstrap(map(&opts)))
        .await;
    std::fs::create_dir_all(d.0.join("sub")).unwrap();
    let (a, _) = act(
        &h,
        "",
        "add_connection",
        map(&[
            ("name", "x".into()),
            ("root", Value::Str(d.0.to_str().unwrap().into())),
        ]),
    )
    .await;
    assert_eq!(
        status(&a),
        Status::InvalidParameter,
        "the parent of the allowed root"
    );
    ok(
        &h,
        "",
        "add_connection",
        map(&[
            ("name", "y".into()),
            ("root", Value::Str(d.0.join("sub").to_str().unwrap().into())),
        ]),
    )
    .await;
    h.stop().await;
    let everything = [("allowed_roots", Value::Str("/".into()))];
    let h = TestHarness::<wyrm_link_localfs::LocalFs>::start(wyrm_filestore::Bootstrap(map(
        &everything,
    )))
    .await;
    for root in ["/proc/self", "/sys", "/dev"] {
        let (a, _) = act(
            &h,
            "",
            "add_connection",
            map(&[("name", "p".into()), ("root", Value::Str(root.into()))]),
        )
        .await;
        assert_eq!(status(&a), Status::InvalidParameter, "{root}");
    }
    h.stop().await;
    // a bad option is refused before the link starts
    let bad = Value::Map([("unknown".to_owned(), Value::Bool(true))].into());
    assert!(wyrm_filestore::store::validate::<LocalStore>(&bad).is_err());
}

#[tokio::test(flavor = "multi_thread")]
async fn hidden_names_are_not_written_unless_shown() {
    let d = Dir::new("hidden");
    let h = start(&d.0, &[]).await;
    wait("connected", 10, || state(&h, "c1") == Some("connected")).await;
    for action in ["upload", "create_folder"] {
        let (a, _) = act(
            &h,
            "c1/files",
            action,
            map(&[("name", ".bashrc".into()), ("text", "x".into())]),
        )
        .await;
        assert_eq!(status(&a), Status::InvalidParameter, "{action}");
    }
    assert!(!d.0.join(".bashrc").exists());
    h.stop().await;
    let h = start(&d.0, &[("show_hidden", Value::Bool(true))]).await;
    wait("connected", 10, || state(&h, "c1") == Some("connected")).await;
    ok(
        &h,
        "c1/files",
        "upload",
        map(&[("name", ".env.example".into()), ("text", "x".into())]),
    )
    .await;
    assert!(d.0.join(".env.example").exists());
    h.stop().await;
}

/// A root that does not exist yet is checked where it would be made: a
/// link inside an allowed root that leads out does not carry a new root
/// (and `create_root`) out with it.
#[cfg(unix)]
#[tokio::test(flavor = "multi_thread")]
async fn a_missing_root_below_a_link_out_is_refused() {
    use wyrm_link_sdk::TestHarness;
    let allowed = Dir::new("allowed-link");
    let outside = Dir::new("outside-link");
    std::os::unix::fs::symlink(&outside.0, allowed.0.join("link")).unwrap();
    let opts = [(
        "allowed_roots",
        Value::Str(allowed.0.to_str().unwrap().into()),
    )];
    let h = TestHarness::<wyrm_link_localfs::LocalFs>::start(wyrm_filestore::Bootstrap(map(&opts)))
        .await;
    let root = allowed.0.join("link").join(".ssh");
    let (a, _) = act(
        &h,
        "",
        "add_connection",
        map(&[
            ("name", "x".into()),
            ("root", Value::Str(root.to_str().unwrap().into())),
            ("create_root", Value::Bool(true)),
        ]),
    )
    .await;
    assert_eq!(status(&a), Status::InvalidParameter, "{:?}", a.err);
    assert!(!outside.0.join(".ssh").exists(), "nothing made outside");
    // a missing root that stays inside is fine
    let inside = allowed.0.join("new").join("deeper");
    ok(
        &h,
        "",
        "add_connection",
        map(&[
            ("name", "y".into()),
            ("root", Value::Str(inside.to_str().unwrap().into())),
            ("create_root", Value::Bool(true)),
        ]),
    )
    .await;
    wait("connected", 10, || state(&h, "y") == Some("connected")).await;
    assert!(inside.is_dir());
    h.stop().await;
}

/// The root swapped for a link out after the probe: changes are refused
/// until the probe checked the place again.
#[cfg(unix)]
#[tokio::test(flavor = "multi_thread")]
async fn a_root_swapped_for_a_link_is_refused() {
    let d = Dir::new("swap");
    let outside = Dir::new("swap-outside");
    let root = d.0.join("root");
    std::fs::create_dir_all(&root).unwrap();
    let h = start(&root, &[]).await;
    wait("connected", 10, || state(&h, "c1") == Some("connected")).await;
    std::fs::rename(&root, d.0.join("moved")).unwrap();
    std::os::unix::fs::symlink(&outside.0, &root).unwrap();
    let (a, _) = act(
        &h,
        "c1/files",
        "upload",
        map(&[("name", "x.txt".into()), ("text", "x".into())]),
    )
    .await;
    assert_ne!(status(&a), Status::Ok, "refused");
    assert!(!outside.0.join("x.txt").exists(), "nothing written outside");
    h.stop().await;
}

/// A file in parts: spooled, then copied into the directory as read.
#[tokio::test(flavor = "multi_thread")]
async fn large_files_in_parts() {
    let d = Dir::new("parts");
    for (k, v) in SEED {
        d.put(k, v.as_bytes());
    }
    let h = start(&d.0, &[]).await;
    wyrm_filestore::testkit::parts_scenario(&h, 9 * 1024 * 1024 + 7).await;
    let left: Vec<_> = walk(&d.0)
        .into_iter()
        .filter(|p| p.contains(".wyrm-"))
        .collect();
    assert!(left.is_empty(), "{left:?}");
    h.stop().await;
}

/// 80 MiB: more than one request may carry (64 MiB), in parts.
#[tokio::test(flavor = "multi_thread")]
async fn beyond_the_single_request_limit() {
    use wyrm_filestore::testkit::{big, download_in_parts, upload_in_parts};
    let d = Dir::new("eighty");
    let h = start(&d.0, &[("max_file_mib", Value::UInt(100))]).await;
    wait("connected", 10, || state(&h, "c1") == Some("connected")).await;
    let data = big(80 * 1024 * 1024);
    let v = upload_in_parts(&h, "c1/files", "eighty.bin", &data, 8 * 1024 * 1024, &[]).await;
    assert!(format!("{v:?}").contains("done"), "{v:?}");
    assert_eq!(
        std::fs::metadata(d.0.join("eighty.bin")).unwrap().len(),
        data.len() as u64
    );
    let back = download_in_parts(&h, "c1/files/eighty.bin", 16 * 1024 * 1024).await;
    assert!(back == data);
    // over max_file_mib: refused at begin
    let (a, _) = act(
        &h,
        "c1/files",
        "upload_begin",
        map(&[
            ("name", "huge.bin".into()),
            ("size", Value::UInt(101 * 1024 * 1024)),
        ]),
    )
    .await;
    assert_eq!(status(&a), Status::OutOfRange);
    h.stop().await;
}

/// A part asked past the end of a file that shrank answers `eof` with the real size, as a 416
/// does for the HTTP stores.
#[tokio::test(flavor = "multi_thread")]
async fn a_part_past_the_end_answers_eof() {
    let d = Dir::new("past-end");
    d.put("reports/readme.txt", b"abcdefghij");
    let h = start(&d.0, &[]).await;
    let node = "c1/files/reports/readme.txt";
    wait("tree", 10, || h.ctx().has_node(node)).await;
    d.put("reports/readme.txt", b"abcd");
    let v = ok(
        &h,
        node,
        "download_part",
        map(&[("offset", Value::UInt(8))]),
    )
    .await;
    let Some(Value::Map(m)) = v else {
        panic!("{v:?}")
    };
    assert_eq!(m["data"], Value::Bytes(Vec::new()));
    assert_eq!(m["eof"], Value::Bool(true));
    assert_eq!(m["size"], Value::UInt(4));
    h.stop().await;
}
