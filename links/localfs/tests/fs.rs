//! The localfs link on a temporary directory.

use std::path::{Path, PathBuf};
use wyrm_core::{Status, Value};
use wyrm_filestore::testkit::{
    act, bootstrap, map, ok, refused, scenario, state, status, wait, Ext, H, SEED,
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
    H::<LocalStore>::start(bootstrap(map(&kv))).await
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
        wyrm_filestore::Bootstrap(Value::Null),
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
