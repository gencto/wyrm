//! The storage link on the SDK harness: DSA `/data` actions, rights, limits
//! and a restart from the same file.

use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;
use wyrm_core::status::StatusCode;
use wyrm_core::{Perm, Status, TypeCode, Value, Writable};
use wyrm_link_sdk::harness::{Reply, SITE};
use wyrm_link_sdk::TestHarness;
use wyrm_storage::{Limits, Storage, StorageStart, Store};

fn temp(name: &str) -> PathBuf {
    let d = std::env::temp_dir().join(format!("wyrm-storage-it-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&d);
    d
}

fn args(kv: &[(&str, Value)]) -> Value {
    Value::Map(
        kv.iter()
            .map(|(k, v)| ((*k).to_owned(), v.clone()))
            .collect(),
    )
}

fn name(n: &str) -> Value {
    args(&[("name", Value::Str(n.into()))])
}

async fn start(store: Arc<Store>, limits: Limits) -> TestHarness<Storage> {
    TestHarness::start_with(StorageStart { store, limits }, |c| {
        c.root = Some(format!("wy/{SITE}/storage"));
    })
    .await
}

fn status(a: &wyrm_core::Attachment) -> Status {
    match a.status.expect("status present") {
        StatusCode::Known(s) => s,
        other => panic!("unexpected status {other:?}"),
    }
}

fn last(r: &[Reply]) -> Status {
    status(&r.last().expect("a reply").att)
}

async fn run(h: &TestHarness<Storage>, path: &str, action: &str, a: Value) -> Vec<Reply> {
    h.invoke(path, action, a, Some(h.ptok(Perm::Write))).await
}

fn value(h: &TestHarness<Storage>, path: &str) -> Option<Value> {
    h.ctx().last(path).map(|s| s.v)
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn data_actions_rights_and_restart() {
    let dir = temp("actions");
    let store = Arc::new(Store::open(&dir).unwrap());
    let h = start(store.clone(), Limits::default()).await;

    let (_, root) = h.meta("").await;
    let acts = root.unwrap().actions.unwrap();
    for a in ["add_node", "add_value", "publish", "export", "import"] {
        assert_eq!(acts[a].level, Some(Perm::Write), "{a}");
    }

    // every action needs write
    let r = h.invoke("", "add_node", name("plant"), None).await;
    assert_eq!(last(&r), Status::PermissionDenied);
    let r = h
        .invoke("", "add_node", name("plant"), Some(h.ptok(Perm::Read)))
        .await;
    assert_eq!(last(&r), Status::PermissionDenied);
    assert_eq!(
        last(&run(&h, "", "add_node", name("plant")).await),
        Status::Ok
    );
    assert_eq!(
        last(&run(&h, "", "add_node", name("plant")).await),
        Status::InvalidParameter,
        "exists"
    );
    assert_eq!(
        last(&run(&h, "", "add_node", name("bad name")).await),
        Status::InvalidParameter
    );

    // add_value {name, type, editor}: choices as text
    let a = args(&[
        ("name", Value::Str("temp".into())),
        ("type", Value::Str("number".into())),
    ]);
    assert_eq!(last(&run(&h, "plant", "add_value", a).await), Status::Ok);
    let a = args(&[
        ("name", Value::Str("note".into())),
        ("type", Value::Str("string".into())),
        ("editor", Value::Str("textarea".into())),
    ]);
    assert_eq!(last(&run(&h, "plant", "add_value", a).await), Status::Ok);
    let a = args(&[
        ("name", Value::Str("odd".into())),
        ("type", Value::Str("weird".into())),
    ]);
    assert_eq!(
        last(&run(&h, "plant", "add_value", a).await),
        Status::InvalidParameter
    );
    let (_, m) = h.meta("plant/temp").await;
    let m = m.unwrap();
    assert_eq!(
        (m.ty, m.writable),
        (Some(TypeCode::Number), Some(Writable::Write))
    );
    let (_, m) = h.meta("plant/note").await;
    assert_eq!(
        m.unwrap().attr_value("editor"),
        Some(&Value::Str("textarea".into()))
    );

    // ~set needs write and the node's type
    let att = h.set("plant/temp", 21.5, Some(h.ptok(Perm::Read))).await;
    assert_eq!(status(&att), Status::PermissionDenied);
    let att = h.set("plant/temp", 21.5, Some(h.ptok(Perm::Write))).await;
    assert_eq!(status(&att), Status::Ok);
    let att = h.set("plant/temp", "warm", Some(h.ptok(Perm::Write))).await;
    assert_eq!(status(&att), Status::InvalidParameter);
    assert_eq!(value(&h, "plant/temp"), Some(Value::Float(21.5)));

    // publish creates the folders and a dynamic value
    let a = args(&[
        ("path", Value::Str("plant/line1/count".into())),
        ("value", Value::UInt(3)),
    ]);
    assert_eq!(last(&run(&h, "", "publish", a).await), Status::Ok);
    let (_, m) = h.meta("plant/line1/count").await;
    assert_eq!(m.unwrap().ty, Some(TypeCode::Dynamic));
    assert_eq!(value(&h, "plant/line1/count"), Some(Value::UInt(3)));
    let a = args(&[
        ("path", Value::Str("plant/temp/x".into())),
        ("value", Value::UInt(3)),
    ]);
    assert_eq!(
        last(&run(&h, "", "publish", a).await),
        Status::InvalidParameter,
        "through a value"
    );
    let a = args(&[
        ("path", Value::Str("plant/temp".into())),
        ("value", Value::Str("no".into())),
    ]);
    assert_eq!(
        last(&run(&h, "", "publish", a).await),
        Status::InvalidParameter,
        "type of an existing value"
    );

    // duplicate, rename, delete
    assert_eq!(
        last(&run(&h, "plant", "duplicate", name("plant2")).await),
        Status::Ok
    );
    assert_eq!(value(&h, "plant2/temp"), Some(Value::Float(21.5)));
    assert_eq!(
        last(&run(&h, "plant2", "rename", name("plant3")).await),
        Status::Ok
    );
    assert!(!h.ctx().has_node("plant2"));
    assert_eq!(value(&h, "plant3/line1/count"), Some(Value::UInt(3)));
    assert_eq!(
        last(&run(&h, "plant3", "delete", Value::Map(Default::default())).await),
        Status::InvalidParameter,
        "children without recursive"
    );
    let rec = args(&[("recursive", Value::Bool(true))]);
    assert_eq!(last(&run(&h, "plant3", "delete", rec).await), Status::Ok);
    assert!(!h.ctx().has_node("plant3"));
    assert!(store.get("plant3/temp").is_none());

    // export, then import into another folder
    let r = run(&h, "plant", "export", Value::Map(Default::default())).await;
    assert_eq!(last(&r), Status::Ok);
    let Some(Value::Str(text)) = r[0].value() else {
        panic!("export answers text");
    };
    assert_eq!(
        last(&run(&h, "", "add_node", name("copy")).await),
        Status::Ok
    );
    let a = args(&[("data", Value::Str(text))]);
    assert_eq!(last(&run(&h, "copy", "import", a).await), Status::Ok);
    assert_eq!(value(&h, "copy/temp"), Some(Value::Float(21.5)));
    assert_eq!(value(&h, "copy/line1/count"), Some(Value::UInt(3)));
    // a second import replaces the children
    let a = args(&[("data", Value::Str(r#"{"only": {}}"#.into()))]);
    assert_eq!(last(&run(&h, "copy", "import", a).await), Status::Ok);
    assert!(!h.ctx().has_node("copy/temp"));
    assert!(h.ctx().has_node("copy/only"));

    // restart from the file: the tree and the last values come back
    h.stop().await;
    for _ in 0..100 {
        if Arc::strong_count(&store) == 1 {
            break;
        }
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
    drop(store);
    let store = Arc::new(Store::open(&dir).unwrap());
    let h = start(store, Limits::default()).await;
    assert_eq!(value(&h, "plant/temp"), Some(Value::Float(21.5)));
    assert_eq!(value(&h, "plant/line1/count"), Some(Value::UInt(3)));
    assert!(h.ctx().has_node("plant/note"));
    assert!(h.ctx().has_node("copy/only"));
    h.stop().await;
    let _ = std::fs::remove_dir_all(dir);
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn limits_hold() {
    let dir = temp("limits");
    let limits = Limits {
        nodes: 3,
        depth: 2,
        value_bytes: 64,
        ..Limits::default()
    };
    let h = start(Arc::new(Store::open(&dir).unwrap()), limits).await;
    assert_eq!(last(&run(&h, "", "add_node", name("a")).await), Status::Ok);
    assert_eq!(last(&run(&h, "a", "add_node", name("b")).await), Status::Ok);
    assert_eq!(
        last(&run(&h, "a/b", "add_node", name("c")).await),
        Status::OutOfRange,
        "depth"
    );
    let a = args(&[
        ("name", Value::Str("v".into())),
        ("type", Value::Str("dynamic".into())),
    ]);
    assert_eq!(last(&run(&h, "a", "add_value", a).await), Status::Ok);
    assert_eq!(
        last(&run(&h, "", "add_node", name("d")).await),
        Status::OutOfRange,
        "nodes"
    );
    assert_eq!(
        last(&run(&h, "a", "duplicate", name("e")).await),
        Status::OutOfRange,
        "a duplicate counts"
    );
    let att = h
        .set("a/v", "x".repeat(100), Some(h.ptok(Perm::Write)))
        .await;
    assert_eq!(status(&att), Status::OutOfRange, "value size");
    h.stop().await;
    let _ = std::fs::remove_dir_all(dir);
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn total_size_export_and_file_import() {
    let dir = temp("total");
    let limits = Limits {
        total_bytes: 300,
        export_bytes: 150,
        ..Limits::default()
    };
    let h = start(Arc::new(Store::open(&dir).unwrap()), limits).await;
    for n in ["s", "t"] {
        let a = args(&[
            ("name", Value::Str(n.into())),
            ("type", Value::Str("string".into())),
        ]);
        assert_eq!(last(&run(&h, "", "add_value", a).await), Status::Ok);
    }
    let w = || Some(h.ptok(Perm::Write));
    assert_eq!(status(&h.set("s", "x".repeat(100), w()).await), Status::Ok);
    assert_eq!(
        status(&h.set("t", "y".repeat(200), w()).await),
        Status::OutOfRange,
        "total size"
    );
    assert_eq!(
        last(&run(&h, "", "export", Value::Map(Default::default())).await),
        Status::OutOfRange,
        "export size"
    );
    let file = br#"{"f": {"$type": "number", "?value": 2}}"#.to_vec();
    let a = args(&[("file", Value::Bytes(file))]);
    assert_eq!(last(&run(&h, "", "import", a).await), Status::Ok);
    assert_eq!(value(&h, "f"), Some(Value::UInt(2)));
    assert!(!h.ctx().has_node("s"), "import replaces the children");
    assert_eq!(
        last(&run(&h, "", "import", Value::Map(Default::default())).await),
        Status::InvalidParameter,
        "data or file"
    );
    h.stop().await;
    let _ = std::fs::remove_dir_all(dir);
}
