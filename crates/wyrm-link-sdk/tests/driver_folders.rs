//! Folders (`Driver::FOLDERS`, ruling 10): an organisational level between a
//! device and its points, at most four deep, through a small test driver.

use std::collections::HashMap;
use std::sync::{Arc, LazyLock, Mutex};
use std::time::Duration;
use wyrm_core::meta::Writable;
use wyrm_core::status::StatusCode;
use wyrm_core::{NodeMeta, Perm, Quality, Status, Value};
use wyrm_link_sdk::driver::{Driver, DriverError, Framework, PointId, Tree};
use wyrm_link_sdk::{Params, TestHarness};

/// What one test's driver saw (by the connection's `tag`): `poll:<ids>`
/// (the plan, ids joined by `,`) and `write:<id>`, in order.
type Log = Arc<Mutex<Vec<String>>>;

static SEEN: LazyLock<Mutex<HashMap<u32, Log>>> = LazyLock::new(Default::default);

fn seen(tag: u32) -> Log {
    SEEN.lock().unwrap().entry(tag).or_default().clone()
}

fn log(tag: u32) -> Vec<String> {
    seen(tag).lock().unwrap().clone()
}

#[derive(Debug, Clone, PartialEq, Params)]
struct Conn {
    #[param(default = 0)]
    tag: u32,
}

#[derive(Debug, Clone, PartialEq, Params)]
struct Dev {
    #[param(default = 1)]
    unit: u32,
}

#[derive(Debug, Clone, PartialEq, Params)]
struct Point {
    #[param(default = 0.02)]
    poll_s: f64,
}

struct Transport(Log);

/// Every point reads 1.0; writes are logged and accepted.
struct Fold;

impl Driver for Fold {
    const NAME: &'static str = "fold";
    const VERSION: &'static str = "0.1.0";
    type Conn = Conn;
    type Dev = Dev;
    type Point = Point;
    type Transport = Transport;
    type Plan = Vec<PointId>;

    const FOLDERS: bool = true;

    async fn open(conn: &Conn) -> Result<Transport, DriverError> {
        Ok(Transport(seen(conn.tag)))
    }

    async fn ping(_t: &mut Transport, _dev: &Dev) -> Result<(), DriverError> {
        Ok(())
    }

    fn plan(_dev: &Dev, points: &[(PointId, Point)]) -> Self::Plan {
        points.iter().map(|(id, _)| id.clone()).collect()
    }

    async fn poll(
        t: &mut Transport,
        _dev: &Dev,
        plan: &Self::Plan,
    ) -> Vec<(PointId, Result<Value, DriverError>)> {
        t.0.lock().unwrap().push(format!("poll:{}", plan.join(",")));
        plan.iter()
            .map(|id| (id.clone(), Ok(Value::Float(1.0))))
            .collect()
    }

    async fn write(
        t: &mut Transport,
        _dev: &Dev,
        id: &str,
        _p: &Point,
        _v: &Value,
    ) -> Result<(), DriverError> {
        t.0.lock().unwrap().push(format!("write:{id}"));
        Ok(())
    }

    fn point_meta(_p: &Point) -> NodeMeta {
        NodeMeta::number().writable(Writable::Write)
    }

    fn poll_period(p: &Point) -> Duration {
        Duration::from_secs_f64(p.poll_s)
    }

    fn ping_period(_dev: &Dev) -> Option<Duration> {
        None
    }
}

type H = TestHarness<Framework<Fold>>;

fn map(kv: &[(&str, Value)]) -> Value {
    Value::Map(
        kv.iter()
            .map(|(k, v)| ((*k).to_owned(), v.clone()))
            .collect(),
    )
}

/// `c1` (`tag`) with `d1`, whose params beside `unit` are `dev`.
fn tree(tag: u32, dev: &[(&str, Value)]) -> Tree {
    let c1 = map(&[
        ("tag", Value::UInt(tag.into())),
        ("devices", map(&[("d1", map(dev))])),
    ]);
    Tree(map(&[("connections", map(&[("c1", c1)]))]))
}

fn points(names: &[&str]) -> Value {
    map(&names.iter().map(|n| (*n, map(&[]))).collect::<Vec<_>>())
}

async fn wait(what: &str, mut f: impl FnMut() -> bool) {
    let deadline = tokio::time::Instant::now() + Duration::from_secs(10);
    while !f() {
        assert!(tokio::time::Instant::now() < deadline, "timeout: {what}");
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
}

fn code(s: Option<StatusCode>) -> Option<Status> {
    match s? {
        StatusCode::Known(s) => Some(s),
        _ => None,
    }
}

async fn act(h: &H, path: &str, action: &str, args: Value) -> Option<Status> {
    let r = h
        .invoke(path, action, args, Some(h.ptok(Perm::Config)))
        .await;
    code(r.first()?.att.status)
}

fn named(n: &str) -> Value {
    map(&[("name", n.into())])
}

async fn actions(h: &H, path: &str) -> Vec<String> {
    let (_, meta) = h.meta(path).await;
    meta.unwrap_or_else(|| panic!("{path} declared"))
        .actions
        .map(|a| a.keys().cloned().collect())
        .unwrap_or_default()
}

async fn exists(h: &H, path: &str) -> bool {
    h.meta(path).await.1.is_some()
}

/// The ids of the plans polled since `from` (index into the log).
fn plans_since(tag: u32, from: usize) -> Vec<String> {
    log(tag)
        .into_iter()
        .skip(from)
        .filter_map(|l| l.strip_prefix("poll:").map(str::to_owned))
        .collect()
}

/// `<conn>/<dev>/<f1>/<f2>/<point>`: points in folders keep their id (writes
/// get it), their key carries the folder path, and the plan still groups by
/// device. Ids are unique on the device; a folder and a point of one parent
/// do not share a name; a folder has only `add_*` and `remove`.
#[tokio::test(flavor = "multi_thread")]
async fn add_folder_nests_points() {
    let tag = 51;
    let h = H::start(tree(tag, &[("points", points(&["p0"]))])).await;
    assert!(actions(&h, "c1/d1").await.contains(&"add_folder".into()));
    assert_eq!(
        act(&h, "c1/d1", "add_folder", named("f1")).await,
        Some(Status::Ok)
    );
    assert_eq!(
        act(&h, "c1/d1/f1", "add_folder", named("f2")).await,
        Some(Status::Ok)
    );
    assert_eq!(
        act(&h, "c1/d1/f1/f2", "add_point", named("p")).await,
        Some(Status::Ok)
    );
    assert!(exists(&h, "c1/d1/f1/f2/p").await);
    assert!(!exists(&h, "c1/d1/p").await);
    let mut folder = actions(&h, "c1/d1/f1").await;
    folder.sort();
    // Ruling 11 adds `copy`, `export` and `import`; still no `edit`.
    assert_eq!(
        folder,
        [
            "add_folder",
            "add_point",
            "copy",
            "export",
            "import",
            "remove"
        ]
    );

    // One plan per device and period, folders or not.
    let from = log(tag).len();
    wait("one plan with both points", || {
        plans_since(tag, from).iter().any(|p| p == "p,p0")
    })
    .await;
    wait("value at the folder path", || {
        h.ctx()
            .last("c1/d1/f1/f2/p")
            .is_some_and(|s| s.q == Quality::Good)
    })
    .await;

    // Ids are unique on the device, across folders.
    let bad = Some(Status::InvalidParameter);
    assert_eq!(act(&h, "c1/d1/f1", "add_point", named("p0")).await, bad);
    assert_eq!(act(&h, "c1/d1", "add_point", named("p")).await, bad);
    // A folder and a point of one parent never share a key.
    assert_eq!(act(&h, "c1/d1", "add_point", named("f1")).await, bad);
    assert_eq!(act(&h, "c1/d1", "add_folder", named("p0")).await, bad);
    assert_eq!(act(&h, "c1/d1/f1", "add_folder", named("f2")).await, bad);
    // Reserved names: the status leaves and framework action names.
    for n in ["status", "error", "export", "remove", "add_x"] {
        assert_eq!(act(&h, "c1/d1", "add_folder", named(n)).await, bad, "{n}");
    }
    // A folder has no `edit` (no rename, ruling 14).
    assert_ne!(
        act(&h, "c1/d1/f1", "edit", named("g")).await,
        Some(Status::Ok)
    );

    // A write reaches the driver with the point's id only.
    let a = h
        .set(
            "c1/d1/f1/f2/p",
            Value::Float(5.0),
            Some(h.ptok(Perm::Write)),
        )
        .await;
    assert_eq!(code(a.status), Some(Status::Ok), "{a:?}");
    assert!(log(tag).contains(&"write:p".to_owned()));

    // The connection's state reaches points in folders.
    assert_eq!(act(&h, "c1", "stop", map(&[])).await, Some(Status::Ok));
    wait("folder point disconnected", || {
        h.ctx()
            .last("c1/d1/f1/f2/p")
            .is_some_and(|s| s.q == Quality::Bad)
    })
    .await;
    h.stop().await;
}

/// Folders nest at most four deep: the fourth has no `add_folder`, and a
/// tree with a fifth does not load.
#[tokio::test(flavor = "multi_thread")]
async fn depth_limit_is_4() {
    let tag = 52;
    let h = H::start(tree(tag, &[])).await;
    let mut at = "c1/d1".to_owned();
    for f in ["f1", "f2", "f3", "f4"] {
        assert_eq!(
            act(&h, &at, "add_folder", named(f)).await,
            Some(Status::Ok),
            "{f}"
        );
        at = format!("{at}/{f}");
    }
    assert_eq!(at, "c1/d1/f1/f2/f3/f4");
    assert!(!actions(&h, &at).await.contains(&"add_folder".into()));
    assert_ne!(
        act(&h, &at, "add_folder", named("f5")).await,
        Some(Status::Ok)
    );
    assert!(!exists(&h, &format!("{at}/f5")).await);
    assert_eq!(
        act(&h, &at, "add_point", named("deep")).await,
        Some(Status::Ok)
    );
    wait("deep point polled", || {
        h.ctx()
            .last("c1/d1/f1/f2/f3/f4/deep")
            .is_some_and(|s| s.q == Quality::Good)
    })
    .await;
    h.stop().await;

    // Load-time: five deep, and an id used twice on a device, are refused.
    let nest = |depth: usize, leaf: Value| {
        (0..depth).fold(leaf, |inner, i| {
            map(&[("folders", map(&[(["a", "b", "c", "d", "e"][i], inner)]))])
        })
    };
    let five = nest(5, map(&[("points", points(&["x"]))]));
    let four = nest(4, map(&[("points", points(&["x"]))]));
    let mut twice = map_of(nest(1, map(&[("points", points(&["x"]))])));
    twice.insert("points".into(), points(&["x"]));
    let starts = |dev: Value| async move {
        let Value::Map(dev) = dev else { unreachable!() };
        let dev: Vec<(String, Value)> = dev.into_iter().collect();
        let kv: Vec<(&str, Value)> = dev.iter().map(|(k, v)| (k.as_str(), v.clone())).collect();
        let session = zenoh::open(wyrm_link_sdk::harness::isolated_config())
            .await
            .unwrap();
        let cfg = wyrm_link_sdk::LinkConfig::new(wyrm_link_sdk::harness::SITE, "fold");
        let r = wyrm_link_sdk::spawn::<Framework<Fold>>(session.clone(), cfg, tree(tag, &kv)).await;
        let ok = match r {
            Ok(handle) => {
                handle.stop().await;
                Ok(())
            }
            Err(e) => Err(e.message),
        };
        let _ = session.close().await;
        ok
    };
    starts(four).await.expect("four deep loads");
    let e = starts(five).await.expect_err("five deep");
    assert!(e.contains("4 deep"), "{e}");
    let e = starts(Value::Map(twice)).await.expect_err("id twice");
    assert!(e.contains("\"x\""), "{e}");
}

fn map_of(v: Value) -> std::collections::BTreeMap<String, Value> {
    match v {
        Value::Map(m) => m,
        _ => Default::default(),
    }
}

fn temp_dir(name: &str) -> std::path::PathBuf {
    let d = std::env::temp_dir().join(format!("wyrm-fold-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&d);
    std::fs::create_dir_all(&d).unwrap();
    d
}

/// A harness with a `data_dir` and a store key, as `wyrmd` gives every link.
async fn start_stored(tree: Tree, dir: &std::path::Path) -> H {
    let dir = dir.to_owned();
    H::start_with(tree, move |lc| {
        lc.data_dir = Some(dir);
        lc.secrets.insert(
            wyrm_link_sdk::driver::persist::STORE_KEY,
            wyrm_link_sdk::Secret::new(vec![9u8; 32]),
        );
    })
    .await
}

/// Review Focus 5: removing a folder removes its points and sub-folders,
/// stops their polling and is saved: a restart on the same bootstrap (which
/// still has the folder) does not bring them back.
#[tokio::test(flavor = "multi_thread")]
async fn folder_remove_cascades() {
    let tag = 53;
    let dir = temp_dir("remove");
    let f2 = map(&[("points", points(&["q"]))]);
    let f1 = map(&[("points", points(&["p"])), ("folders", map(&[("f2", f2)]))]);
    let boot = || {
        tree(
            tag,
            &[
                ("points", points(&["keep"])),
                ("folders", map(&[("f1", f1.clone())])),
            ],
        )
    };
    let h = start_stored(boot(), &dir).await;
    for p in [
        "c1/d1/keep",
        "c1/d1/f1",
        "c1/d1/f1/p",
        "c1/d1/f1/f2",
        "c1/d1/f1/f2/q",
    ] {
        assert!(exists(&h, p).await, "{p} declared");
    }
    wait("all three polled", || {
        plans_since(tag, 0).iter().any(|p| p == "keep,p,q")
    })
    .await;

    assert_eq!(
        act(&h, "c1/d1/f1", "remove", map(&[])).await,
        Some(Status::Ok)
    );
    for p in ["c1/d1/f1", "c1/d1/f1/p", "c1/d1/f1/f2", "c1/d1/f1/f2/q"] {
        assert!(!exists(&h, p).await, "{p} removed");
    }
    // Polling: only `keep` from here on.
    let from = log(tag).len();
    wait("polled after the remove", || {
        plans_since(tag, from).len() >= 3
    })
    .await;
    assert!(
        plans_since(tag, from).iter().skip(1).all(|p| p == "keep"),
        "{:?}",
        plans_since(tag, from)
    );
    // The ids are free again.
    assert_eq!(
        act(&h, "c1/d1", "add_point", named("q")).await,
        Some(Status::Ok)
    );
    h.stop().await;

    // A restart on the same bootstrap (which still has `f1`): the saved
    // tree wins, the folder stays gone, `q` is a device-level point.
    let h = start_stored(boot(), &dir).await;
    assert!(exists(&h, "c1/d1/keep").await);
    assert!(exists(&h, "c1/d1/q").await);
    for p in ["c1/d1/f1", "c1/d1/f1/p", "c1/d1/f1/f2/q"] {
        assert!(!exists(&h, p).await, "{p} stays removed after a restart");
    }
    let from = log(tag).len();
    wait("polled after the restart", || {
        plans_since(tag, from).len() >= 3
    })
    .await;
    assert!(
        plans_since(tag, from).iter().all(|p| p == "keep,q"),
        "{:?}",
        plans_since(tag, from)
    );
    // The export shows the tree as saved: no `f1`.
    let ex = h
        .invoke("", "export", map(&[]), Some(h.ptok(Perm::Config)))
        .await
        .remove(0)
        .value()
        .unwrap();
    assert!(!format!("{ex:?}").contains("\"f1\""), "{ex:?}");
    h.stop().await;
    let _ = std::fs::remove_dir_all(&dir);
}
