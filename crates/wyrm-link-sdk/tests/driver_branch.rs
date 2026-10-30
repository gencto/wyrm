//! Copy, export and import of branches (ruling 11): framework actions of
//! every driver, through a small test driver with two connection kinds, a
//! secret and folders.

use serde_json::{json, Value as Json};
use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, LazyLock, Mutex};
use std::time::Duration;
use wyrm_core::meta::{ParamMeta, Writable};
use wyrm_core::status::StatusCode;
use wyrm_core::{ActionMeta, NodeMeta, Perm, Quality, Status, TypeCode, Value};
use wyrm_link_sdk::driver::branch::{self, Level as BranchLevel};
use wyrm_link_sdk::driver::branch::{FORMAT, MAX_BYTES, MAX_NODES, NOT_EXPORTED};
use wyrm_link_sdk::driver::{
    Converted, Driver, DriverError, Framework, Level, NodeState, PointId, Target, Tree,
};
use wyrm_link_sdk::{LinkError, Params, TestHarness};

/// What one test's driver saw (by the connection's `tag`): `open` and
/// `poll:<ids>`, in order.
type Log = Arc<Mutex<Vec<String>>>;

static SEEN: LazyLock<Mutex<HashMap<u32, Log>>> = LazyLock::new(Default::default);

fn seen(tag: u32) -> Log {
    SEEN.lock().unwrap().entry(tag).or_default().clone()
}

fn log(tag: u32) -> Vec<String> {
    seen(tag).lock().unwrap().clone()
}

#[derive(Debug, Clone, PartialEq, Params)]
struct Ip {
    #[param(default = 0)]
    tag: u32,
    #[param(default = "h", dest)]
    host: String,
    /// Required: a connection without it does not load.
    #[param(secret)]
    password: String,
}

#[derive(Debug, Clone, PartialEq, Params)]
struct Serial {
    #[param(default = 0)]
    tag: u32,
    #[param(default = "", secret)]
    pin: String,
}

#[derive(Debug, Clone, PartialEq, Params)]
enum Conn {
    #[param(name = "ip", display = "IP Connection")]
    Ip(Ip),
    #[param(name = "serial", display = "Serial Connection")]
    Serial(Serial),
}

#[derive(Debug, Clone, PartialEq, Params)]
struct Dev {
    #[param(default = 1)]
    unit: u32,
    /// Ping period; 0 = no pings.
    #[param(default = 0)]
    ping_ms: u32,
}

#[derive(Debug, Clone, PartialEq, Params)]
struct Point {
    #[param(default = 0.02)]
    poll_s: f64,
    #[param(default = 0, max = 1000)]
    addr: u32,
}

struct Transport(Log);

/// Armed by a test: the next declaration of a point with `addr` 666 panics
/// (a call cut half-way through).
static BOOM: AtomicBool = AtomicBool::new(false);

/// Armed by a test: the next poll of a point with `addr` 13 breaks the
/// transport; `FAILED` says it happened.
static FAIL: AtomicBool = AtomicBool::new(false);
static FAILED: AtomicBool = AtomicBool::new(false);

/// Every point reads its `addr`; a poll with `addr` 5 takes 300 ms. An IP
/// connection opens only with a password.
struct Br;

impl Driver for Br {
    const NAME: &'static str = "br";
    const VERSION: &'static str = "0.1.0";
    type Conn = Conn;
    type Dev = Dev;
    type Point = Point;
    type Transport = Transport;
    type Plan = Vec<(PointId, u32)>;

    const FOLDERS: bool = true;

    async fn open(conn: &Conn) -> Result<Transport, DriverError> {
        let tag = match conn {
            Conn::Ip(c) if c.password.is_empty() => {
                return Err(DriverError::Transport("no password".into()))
            }
            Conn::Ip(c) => c.tag,
            Conn::Serial(c) => c.tag,
        };
        seen(tag).lock().unwrap().push("open".into());
        Ok(Transport(seen(tag)))
    }

    async fn ping(t: &mut Transport, _dev: &Dev) -> Result<(), DriverError> {
        t.0.lock().unwrap().push("ping".into());
        Ok(())
    }

    fn plan(_dev: &Dev, points: &[(PointId, Point)]) -> Self::Plan {
        points.iter().map(|(id, p)| (id.clone(), p.addr)).collect()
    }

    async fn poll(
        t: &mut Transport,
        _dev: &Dev,
        plan: &Self::Plan,
    ) -> Vec<(PointId, Result<Value, DriverError>)> {
        if plan.iter().any(|(_, a)| *a == 13) && FAIL.swap(false, Ordering::SeqCst) {
            FAILED.store(true, Ordering::SeqCst);
            return plan
                .iter()
                .map(|(id, _)| (id.clone(), Err(DriverError::Transport("cut".into()))))
                .collect();
        }
        let ids: Vec<&str> = plan.iter().map(|(id, _)| id.as_str()).collect();
        t.0.lock().unwrap().push(format!("poll:{}", ids.join(",")));
        if plan.iter().any(|(_, a)| *a == 5) {
            tokio::time::sleep(Duration::from_millis(300)).await;
        }
        plan.iter()
            .map(|(id, a)| (id.clone(), Ok(Value::Float((*a).into()))))
            .collect()
    }

    async fn write(
        _t: &mut Transport,
        _dev: &Dev,
        _id: &str,
        _p: &Point,
        _v: &Value,
    ) -> Result<(), DriverError> {
        Ok(())
    }

    fn point_meta(p: &Point) -> NodeMeta {
        if p.addr == 666 && BOOM.swap(false, Ordering::SeqCst) {
            panic!("cut while declaring");
        }
        NodeMeta::number().writable(Writable::Write)
    }

    fn poll_period(p: &Point) -> Duration {
        Duration::from_secs_f64(p.poll_s)
    }

    fn ping_period(dev: &Dev) -> Option<Duration> {
        (dev.ping_ms > 0).then(|| Duration::from_millis(dev.ping_ms.into()))
    }

    /// `hold {ms}` on a device: keeps the owner task busy that long;
    /// `touch`: logs `touch:<unit>` (it reached the device).
    fn actions(level: Level, _kind: &str) -> Vec<(&'static str, ActionMeta)> {
        match level {
            Level::Device => vec![
                (
                    "hold",
                    ActionMeta::new()
                        .level(Perm::Config)
                        .timeout_ms(5000)
                        .param("ms", ParamMeta::of(TypeCode::Number).required(true)),
                ),
                (
                    "touch",
                    ActionMeta::new().level(Perm::Config).timeout_ms(5000),
                ),
            ],
            Level::Connection => Vec::new(),
        }
    }

    /// `import_list {names}`: one IP connection per comma-separated name,
    /// each with `d1/f1/p1`; the report says `{"names": <count>}`.
    fn root_imports() -> Vec<(&'static str, ActionMeta)> {
        vec![(
            "import_list",
            ActionMeta::new().param("names", ParamMeta::of(TypeCode::String).required(true)),
        )]
    }

    fn convert(_action: &str, args: &Value) -> Result<Converted, LinkError> {
        let names = match args {
            Value::Map(m) => match m.get("names") {
                Some(Value::Str(s)) => s.clone(),
                _ => String::new(),
            },
            _ => String::new(),
        };
        let node = |level, name: &str, params: Vec<(&str, Value)>, children| branch::Node {
            level,
            name: name.into(),
            params: params.into_iter().map(|(k, v)| (k.into(), v)).collect(),
            enabled: true,
            children,
        };
        let connections: Vec<branch::Node> = names
            .split(',')
            .map(|n| {
                let p1 = node(
                    BranchLevel::Point,
                    "p1",
                    vec![("addr", Value::UInt(4))],
                    vec![],
                );
                let f1 = node(BranchLevel::Folder, "f1", vec![], vec![p1]);
                let d1 = node(BranchLevel::Device, "d1", vec![], vec![f1]);
                node(
                    BranchLevel::Connection,
                    n,
                    vec![("kind", "ip".into()), ("host", "h9".into())],
                    vec![d1],
                )
            })
            .collect();
        let report = [("names".to_owned(), Value::UInt(connections.len() as u64))].into();
        Ok(Converted {
            connections,
            report,
        })
    }

    async fn invoke(
        t: &mut Transport,
        _conn: &Conn,
        target: Target<'_, Self>,
        action: &str,
        args: &Value,
    ) -> Result<Value, LinkError> {
        if action == "touch" {
            if let Target::Device { dev, .. } = target {
                t.0.lock().unwrap().push(format!("touch:{}", dev.unit));
            }
            return Ok(Value::Null);
        }
        let ms = match args {
            Value::Map(m) => m.get("ms").and_then(Value::as_f64).unwrap_or(0.0),
            _ => 0.0,
        };
        tokio::time::sleep(Duration::from_secs_f64(ms / 1000.0)).await;
        Ok(Value::Null)
    }
}

type H = TestHarness<Framework<Br>>;

fn map(kv: &[(&str, Value)]) -> Value {
    Value::Map(
        kv.iter()
            .map(|(k, v)| ((*k).to_owned(), v.clone()))
            .collect(),
    )
}

fn pt(addr: u64) -> Value {
    map(&[("addr", Value::UInt(addr))])
}

/// `c1` (IP, `tag`, password `pw-secret`) with `d1` (unit 7): `p0` at the
/// device, `f1/p1` and `f1/f2/p2` in folders.
fn tree(tag: u32) -> Tree {
    let f2 = map(&[("points", map(&[("p2", pt(3))]))]);
    let f1 = map(&[
        ("points", map(&[("p1", pt(2))])),
        ("folders", map(&[("f2", f2)])),
    ]);
    let d1 = map(&[
        ("unit", Value::UInt(7)),
        ("points", map(&[("p0", pt(1))])),
        ("folders", map(&[("f1", f1)])),
    ]);
    let c1 = map(&[
        ("kind", "ip".into()),
        ("tag", Value::UInt(tag.into())),
        ("host", "h1".into()),
        ("password", "pw-secret".into()),
        ("devices", map(&[("d1", d1)])),
    ]);
    Tree(map(&[("connections", map(&[("c1", c1)]))]))
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

/// An action's status, error text and value.
struct Out {
    status: Option<Status>,
    err: String,
    value: Option<Value>,
}

async fn run(h: &H, path: &str, action: &str, args: Value) -> Out {
    let mut r = h
        .invoke(path, action, args, Some(h.ptok(Perm::Config)))
        .await;
    assert!(!r.is_empty(), "{path}/~act/{action}: no reply");
    let r = r.remove(0);
    Out {
        status: code(r.att.status),
        err: r.att.err.clone().unwrap_or_default(),
        value: r.value(),
    }
}

async fn ok(h: &H, path: &str, action: &str, args: Value) -> Option<Value> {
    let o = run(h, path, action, args).await;
    assert_eq!(
        o.status,
        Some(Status::Ok),
        "{path}/~act/{action}: {}",
        o.err
    );
    o.value
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

fn state(h: &H, path: &str) -> Option<Value> {
    h.ctx().last(&format!("{path}/status")).map(|s| s.v)
}

fn is_state(s: NodeState) -> Option<Value> {
    Some(Value::UInt(s as u64))
}

/// `export` of `path` as JSON.
async fn export(h: &H, path: &str) -> Json {
    let v = ok(h, path, "export", map(&[])).await.expect("a reply");
    let Value::Map(m) = v else { panic!("{v:?}") };
    let Some(Value::Str(text)) = m.get("json") else {
        panic!("{m:?}")
    };
    serde_json::from_str(text).expect("JSON")
}

/// The whole tree (root `export`).
async fn root_export(h: &H) -> Value {
    ok(h, "", "export", map(&[])).await.expect("a reply")
}

fn import_args(j: &Json, name: Option<&str>, overwrite: bool) -> Value {
    let mut kv = vec![
        ("json", Value::Str(j.to_string())),
        ("overwrite", Value::Bool(overwrite)),
    ];
    if let Some(n) = name {
        kv.push(("name", n.into()));
    }
    map(&kv)
}

/// The names of a branch node's children.
fn children(j: &Json) -> Vec<String> {
    j["children"]
        .as_array()
        .map(|a| {
            a.iter()
                .map(|c| c["name"].as_str().unwrap().to_owned())
                .collect()
        })
        .unwrap_or_default()
}

/// A branch without its own `name` (to compare two of them).
fn unnamed(mut j: Json) -> Json {
    j.as_object_mut().unwrap().remove("name");
    j
}

fn temp_dir(name: &str) -> std::path::PathBuf {
    let d = std::env::temp_dir().join(format!("wyrm-br-{name}-{}", std::process::id()));
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

/// Every node kind offers the actions of ruling 11, all at `config`.
#[tokio::test(flavor = "multi_thread")]
async fn actions_are_offered_at_config() {
    let h = H::start(tree(60)).await;
    let want: [(&str, &[&str]); 5] = [
        ("", &["import", "export"]),
        ("c1", &["copy", "export", "import"]),
        ("c1/d1", &["copy", "export", "import"]),
        ("c1/d1/f1", &["copy", "export", "import"]),
        ("c1/d1/f1/p1", &["copy"]),
    ];
    for (path, names) in want {
        let (_, meta) = h.meta(path).await;
        let acts = meta.unwrap().actions.unwrap_or_default();
        for n in names {
            let a = acts
                .get(*n)
                .unwrap_or_else(|| panic!("{path}: no {n} in {:?}", acts.keys()));
            assert_eq!(a.level, Some(Perm::Config), "{path}/~act/{n}");
        }
    }
    let point = actions(&h, "c1/d1/f1/p1").await;
    assert!(!point.contains(&"export".to_owned()) && !point.contains(&"import".to_owned()));
    // A caller with `write` gets none of them.
    for (path, a) in [("c1", "copy"), ("c1", "export"), ("", "import")] {
        let r = h
            .invoke(path, a, named("x"), Some(h.ptok(Perm::Write)))
            .await;
        assert_ne!(code(r[0].att.status), Some(Status::Ok), "{path}/~act/{a}");
    }
    assert!(!exists(&h, "x").await);
    h.stop().await;
}

/// A copied device has every folder and point of the source under a new id,
/// starts disabled (not polled) and can be started.
#[tokio::test(flavor = "multi_thread")]
async fn copy_device_is_deep_and_disabled() {
    let tag = 61;
    let h = H::start(tree(tag)).await;
    wait("d1 polled", || {
        h.ctx()
            .last("c1/d1/f1/f2/p2")
            .is_some_and(|s| s.q == Quality::Good)
    })
    .await;
    ok(&h, "c1/d1", "copy", named("d2")).await;
    for p in [
        "c1/d2",
        "c1/d2/p0",
        "c1/d2/f1",
        "c1/d2/f1/p1",
        "c1/d2/f1/f2",
        "c1/d2/f1/f2/p2",
    ] {
        assert!(exists(&h, p).await, "{p} copied");
    }
    assert_eq!(state(&h, "c1/d2"), is_state(NodeState::Stopped));
    let acts = actions(&h, "c1/d2").await;
    assert!(acts.contains(&"start".to_owned()) && !acts.contains(&"stop".to_owned()));
    // The same params and children, the copy disabled.
    let (src, dst) = (export(&h, "c1/d1").await, export(&h, "c1/d2").await);
    assert_eq!(dst["name"], "d2");
    assert_eq!(dst["enabled"], false);
    assert_eq!(src["enabled"], true);
    assert_eq!(dst["params"], src["params"]);
    assert_eq!(dst["children"], src["children"]);
    // Not polled while disabled: no values, no diagnostics or runtime state.
    let from = log(tag).len();
    wait("polls after the copy", || log(tag).len() >= from + 5).await;
    for p in ["c1/d2/p0", "c1/d2/f1/p1", "c1/d2/f1/f2/p2"] {
        assert!(h.ctx().last(p).is_none(), "{p} has no value");
    }
    ok(&h, "c1/d2", "start", map(&[])).await;
    wait("the copy polled once started", || {
        h.ctx()
            .last("c1/d2/f1/f2/p2")
            .is_some_and(|s| s.q == Quality::Good)
    })
    .await;

    // A connection copy: disabled, with its devices; the sealed password
    // goes with it (same link, same destination), so it starts.
    ok(&h, "c1", "copy", named("c9")).await;
    assert!(exists(&h, "c9/d1/f1/f2/p2").await);
    assert!(exists(&h, "c9/d2/f1/p1").await);
    assert_eq!(state(&h, "c9"), is_state(NodeState::Stopped));
    let opens = log(tag).iter().filter(|l| *l == "open").count();
    ok(&h, "c9", "start", map(&[])).await;
    wait("c9 connected", || {
        state(&h, "c9") == is_state(NodeState::Connected)
    })
    .await;
    assert_eq!(log(tag).iter().filter(|l| *l == "open").count(), opens + 1);

    // New ids only: an existing one, a reserved one, a bad key segment.
    let bad = Some(Status::InvalidParameter);
    assert_eq!(run(&h, "c1/d1", "copy", named("d2")).await.status, bad);
    assert_eq!(run(&h, "c1", "copy", named("c9")).await.status, bad);
    assert_eq!(run(&h, "c1/d1", "copy", named("status")).await.status, bad);
    assert_eq!(run(&h, "c1/d1", "copy", named("a/b")).await.status, bad);
    assert_eq!(run(&h, "c1/d1", "copy", map(&[])).await.status, bad);
    assert_eq!(
        run(&h, "c1/nope", "copy", named("d3")).await.status,
        Some(Status::NotFound)
    );
    h.stop().await;
}

/// A point copy goes beside its source, under a new id that is free on the
/// whole device; a folder copy renames its points (ids are unique on the
/// device) and says how.
#[tokio::test(flavor = "multi_thread")]
async fn copy_point_under_same_parent() {
    let h = H::start(tree(62)).await;
    ok(&h, "c1/d1/f1/p1", "copy", named("p9")).await;
    assert!(exists(&h, "c1/d1/f1/p9").await);
    assert!(!exists(&h, "c1/d1/p9").await);
    wait("the copy polled", || {
        h.ctx()
            .last("c1/d1/f1/p9")
            .is_some_and(|s| s.q == Quality::Good)
    })
    .await;
    let f1 = export(&h, "c1/d1/f1").await;
    let params = |name: &str| {
        f1["children"]
            .as_array()
            .unwrap()
            .iter()
            .find(|c| c["name"] == name)
            .unwrap()["params"]
            .clone()
    };
    assert_eq!(params("p9"), params("p1"));
    assert_eq!(params("p9")["addr"], 2);

    let bad = Some(Status::InvalidParameter);
    // `p0` is on the device, `p2` in `f1/f2`, `f2` is a folder of `f1`.
    for n in ["p0", "p2", "f2", "p1"] {
        let o = run(&h, "c1/d1/f1/p1", "copy", named(n)).await;
        assert_eq!(o.status, bad, "{n}: {}", o.err);
    }
    assert!(!exists(&h, "c1/d1/f1/p0").await);

    // A folder copy: beside the source, its points under fresh ids.
    let r = ok(&h, "c1/d1/f1", "copy", named("g1")).await.unwrap();
    let Value::Map(r) = r else { panic!("{r:?}") };
    let Some(Value::Map(renamed)) = r.get("renamed") else {
        panic!("{r:?}")
    };
    assert_eq!(renamed.get("p1"), Some(&Value::Str("p1_2".into())));
    assert_eq!(renamed.get("p2"), Some(&Value::Str("p2_2".into())));
    for p in ["c1/d1/g1", "c1/d1/g1/p1_2", "c1/d1/g1/f2/p2_2"] {
        assert!(exists(&h, p).await, "{p}");
    }
    assert_eq!(run(&h, "c1/d1/f1", "copy", named("p0")).await.status, bad);
    h.stop().await;
}

/// `export` leaves secrets out (marked), shows the node kind and the whole
/// branch; root `export` keeps its shape.
#[tokio::test(flavor = "multi_thread")]
async fn export_leaves_secrets_out() {
    let h = H::start(tree(63)).await;
    let v = ok(&h, "c1", "export", map(&[])).await.unwrap();
    assert!(!format!("{v:?}").contains("pw-secret"), "{v:?}");
    let c = export(&h, "c1").await;
    assert_eq!(c["format"], FORMAT);
    assert_eq!(c["driver"], "br");
    assert_eq!(c["kind"], "connection");
    assert_eq!(c["name"], "c1");
    assert_eq!(c["enabled"], true);
    assert_eq!(
        c["params"],
        json!({"kind": "ip", "tag": 63, "host": "h1", "password": NOT_EXPORTED})
    );
    assert_eq!(children(&c), ["d1"]);
    let d = &c["children"][0];
    assert_eq!(d["kind"], "device");
    assert_eq!(d["params"], json!({"unit": 7, "ping_ms": 0}));
    assert_eq!(children(d), ["f1", "p0"]);
    let f1 = &d["children"][0];
    assert_eq!(f1["kind"], "folder");
    assert_eq!(f1["params"], json!({}));
    assert_eq!(children(f1), ["f2", "p1"]);
    assert_eq!(f1["children"][1]["kind"], "point");
    assert_eq!(
        f1["children"][1]["params"],
        json!({"addr": 2, "poll_s": 0.02})
    );
    assert_eq!(f1["children"][0]["children"][0]["name"], "p2");

    // A device and a folder export the same subtrees.
    let dj = export(&h, "c1/d1").await;
    assert_eq!(dj["format"], FORMAT);
    assert_eq!(unnamed(dj.clone())["children"], d["children"]);
    assert_eq!(dj["params"], d["params"]);
    let fj = export(&h, "c1/d1/f1").await;
    assert_eq!(fj["kind"], "folder");
    assert_eq!(fj["children"], f1["children"]);
    // A point has no export; the root's is the whole tree as before.
    assert_ne!(
        run(&h, "c1/d1/p0", "export", map(&[])).await.status,
        Some(Status::Ok)
    );
    let Value::Map(root) = root_export(&h).await else {
        panic!()
    };
    assert!(root.contains_key("connections") && root.contains_key("poll_unsubscribed"));
    h.stop().await;
}

/// Export a connection, import it under a new name: the same params and
/// children; the secrets are not carried and the import names them; the
/// node loads (Failed, with the reason) and `edit` brings it up.
#[tokio::test(flavor = "multi_thread")]
async fn import_round_trip() {
    let tag = 64;
    let h = H::start(tree(tag)).await;
    let c1 = export(&h, "c1").await;
    let r = ok(&h, "", "import", import_args(&c1, Some("c2"), false))
        .await
        .unwrap();
    let Value::Map(r) = r else { panic!("{r:?}") };
    assert_eq!(r.get("name"), Some(&Value::Str("c2".into())));
    assert_eq!(
        r.get("reenter"),
        Some(&Value::Array(vec![Value::Str("c2.password".into())])),
        "{r:?}"
    );
    for p in ["c2", "c2/d1", "c2/d1/p0", "c2/d1/f1/p1", "c2/d1/f1/f2/p2"] {
        assert!(exists(&h, p).await, "{p} imported");
    }
    // Loaded, not dropped: Failed with the missing secret named.
    assert_eq!(state(&h, "c2"), is_state(NodeState::Failed));
    let err = h.ctx().last("c2/error").map(|s| s.v);
    let Some(Value::Str(err)) = err else {
        panic!("{err:?}")
    };
    assert!(err.contains("password") && err.contains("edit"), "{err}");
    let c2 = export(&h, "c2").await;
    assert_eq!(c2["children"], c1["children"]);
    let mut want = c1["params"].clone();
    want.as_object_mut().unwrap().remove("password");
    assert_eq!(c2["params"], want, "no password stored");

    // `edit` with the password; the import started disabled.
    ok(
        &h,
        "c2",
        "edit",
        map(&[
            ("tag", Value::UInt(tag.into())),
            ("host", "h1".into()),
            ("password", "again".into()),
        ]),
    )
    .await;
    assert_eq!(state(&h, "c2"), is_state(NodeState::Stopped));
    ok(&h, "c2", "start", map(&[])).await;
    wait("c2 connected", || {
        state(&h, "c2") == is_state(NodeState::Connected)
    })
    .await;
    wait("c2 polled", || {
        h.ctx()
            .last("c2/d1/f1/f2/p2")
            .is_some_and(|s| s.q == Quality::Good)
    })
    .await;

    // A secret written into the text is not taken either.
    let mut real = c1.clone();
    real["params"]["password"] = json!("real");
    let r = ok(&h, "", "import", import_args(&real, Some("c4"), false))
        .await
        .unwrap();
    let Value::Map(r) = r else { panic!() };
    assert_eq!(
        r.get("reenter"),
        Some(&Value::Array(vec![Value::Str("c4.password".into())]))
    );
    assert_eq!(state(&h, "c4"), is_state(NodeState::Failed));
    assert!(export(&h, "c4").await["params"].get("password").is_none());

    // A device into a connection; a folder (default name: the exported
    // one) into a device and into a folder.
    let d1 = export(&h, "c1/d1").await;
    ok(&h, "c2", "import", import_args(&d1, Some("d5"), false)).await;
    assert!(exists(&h, "c2/d5/f1/f2/p2").await);
    assert_eq!(state(&h, "c2/d5"), is_state(NodeState::Stopped));
    assert_eq!(unnamed(export(&h, "c2/d5").await)["params"], d1["params"]);

    let mut f = export(&h, "c1/d1/f1/f2").await;
    f["children"][0]["name"] = json!("p7");
    let r = ok(&h, "c1/d1", "import", import_args(&f, None, false))
        .await
        .unwrap();
    let Value::Map(r) = r else { panic!() };
    assert_eq!(r.get("name"), Some(&Value::Str("f2".into())));
    assert_eq!(r.get("reenter"), Some(&Value::Array(vec![])));
    assert!(exists(&h, "c1/d1/f2/p7").await);
    f["children"][0]["name"] = json!("p8");
    ok(&h, "c1/d1/f1", "import", import_args(&f, Some("f3"), false)).await;
    assert!(exists(&h, "c1/d1/f1/f3/p8").await);
    wait("imported points polled", || {
        ["c1/d1/f2/p7", "c1/d1/f1/f3/p8"]
            .iter()
            .all(|p| h.ctx().last(p).is_some_and(|s| s.q == Quality::Good))
    })
    .await;
    h.stop().await;
}

/// A branch of the wrong format, driver or kind, bad params, a point id
/// that the device already has, too deep, too large or with too many
/// nodes: refused with the field or bound named, nothing changed.
#[tokio::test(flavor = "multi_thread")]
async fn import_refuses_wrong_kind_or_driver_or_format() {
    let h = H::start(tree(65)).await;
    let before = root_export(&h).await;
    let c1 = export(&h, "c1").await;
    let d1 = export(&h, "c1/d1").await;
    let f1 = export(&h, "c1/d1/f1").await;
    let edit = |j: &Json, f: &dyn Fn(&mut Json)| {
        let mut j = j.clone();
        f(&mut j);
        j
    };
    // Below `c1/d1/f1/f2`: `f8` is the third level, `y` would be the fifth.
    let deep = json!({"format": FORMAT, "driver": "br", "kind": "folder", "name": "f8",
        "params": {}, "children": [{"kind": "folder", "name": "x", "params": {},
            "children": [{"kind": "folder", "name": "y", "params": {}, "children": []}]}]});
    let many = {
        let pts: Vec<Json> = (0..=MAX_NODES)
            .map(|i| json!({"kind": "point", "name": format!("n{i}"), "params": {}}))
            .collect();
        json!({"format": FORMAT, "driver": "br", "kind": "folder", "name": "big",
            "params": {}, "children": pts})
    };
    let (nodes, bytes) = (MAX_NODES.to_string(), MAX_BYTES.to_string());
    let cases: Vec<(&str, Json, Option<&str>, &str)> = vec![
        (
            "",
            edit(&c1, &|j| j["format"] = json!("wyrm-driver-branch/9")),
            Some("c3"),
            "format",
        ),
        (
            "",
            edit(&c1, &|j| j["driver"] = json!("modbus")),
            Some("c3"),
            "driver",
        ),
        ("", d1.clone(), Some("c3"), "kind"),
        ("c1", c1.clone(), Some("d3"), "kind"),
        ("c1/d1", d1.clone(), Some("f9"), "kind"),
        ("c1/d1/f1", c1.clone(), Some("f9"), "kind"),
        (
            "",
            edit(&c1, &|j| {
                j["children"][0]["params"]["unit"] = json!("seven")
            }),
            Some("c3"),
            "c3/d1: unit",
        ),
        (
            "",
            edit(&c1, &|j| j["params"]["kind"] = json!("bus")),
            Some("c3"),
            "kind",
        ),
        (
            "",
            edit(&c1, &|j| {
                j["children"][0]["children"][1]["params"]["addr"] = json!(5000)
            }),
            Some("c3"),
            "addr",
        ),
        (
            "",
            edit(&c1, &|j| j["children"][0]["params"]["port"] = json!(1)),
            Some("c3"),
            "port",
        ),
        (
            "",
            edit(&c1, &|j| j["extra"] = json!(1)),
            Some("c3"),
            "extra",
        ),
        // `p1` is already in `c1/d1/f1`.
        (
            "c1/d1",
            edit(&f1, &|j| j["children"][0]["children"] = json!([])),
            Some("f8"),
            "p1",
        ),
        ("c1/d1/f1/f2", deep, Some("f8"), "4 deep"),
        ("c1/d1", many, None, &nodes),
        (
            "",
            json!({"format": FORMAT, "pad": "x".repeat(MAX_BYTES)}),
            Some("c3"),
            &bytes,
        ),
        ("", json!([1, 2]), Some("c3"), "json"),
    ];
    for (at, j, name, needle) in &cases {
        let o = run(&h, at, "import", import_args(j, *name, false)).await;
        assert_eq!(
            o.status,
            Some(Status::InvalidParameter),
            "{at} {needle}: {}",
            o.err
        );
        assert!(
            o.err.contains(needle),
            "{at}: {needle:?} not in {:?}",
            o.err
        );
    }
    let o = run(&h, "", "import", map(&[("json", "{not json".into())])).await;
    assert_eq!(o.status, Some(Status::InvalidParameter), "{}", o.err);
    assert!(o.err.contains("json"), "{}", o.err);
    assert_eq!(root_export(&h).await, before, "nothing changed");
    h.stop().await;
}

/// An id that exists is refused unless `overwrite`, which replaces the
/// branch (a connection, a device, a folder) with the imported one.
#[tokio::test(flavor = "multi_thread")]
async fn import_overwrite() {
    let h = H::start(tree(66)).await;
    let mut c1 = export(&h, "c1").await;
    let o = run(&h, "", "import", import_args(&c1, None, false)).await;
    assert_eq!(o.status, Some(Status::InvalidParameter));
    assert!(
        o.err.contains("c1") && o.err.contains("overwrite"),
        "{}",
        o.err
    );

    // Replace `c1` with a branch whose device has only `p0`.
    c1["params"]["host"] = json!("h2");
    c1["children"][0]["children"] = json!([c1["children"][0]["children"][1].clone()]);
    ok(&h, "", "import", import_args(&c1, None, true)).await;
    assert!(exists(&h, "c1/d1/p0").await);
    assert!(!exists(&h, "c1/d1/f1").await);
    assert!(!exists(&h, "c1/d1/f1/p1").await);
    let now = export(&h, "c1").await;
    assert_eq!(now["params"]["host"], "h2");
    assert_eq!(children(&now["children"][0]), ["p0"]);

    // A device, then a folder.
    let mut d = export(&h, "c1/d1").await;
    d["params"]["unit"] = json!(9);
    let o = run(&h, "c1", "import", import_args(&d, None, false)).await;
    assert_eq!(o.status, Some(Status::InvalidParameter), "{}", o.err);
    ok(&h, "c1", "import", import_args(&d, None, true)).await;
    assert_eq!(export(&h, "c1/d1").await["params"]["unit"], 9);

    let folder = |pts: &[&str]| {
        let pts: Vec<Json> = pts
            .iter()
            .map(|n| json!({"kind": "point", "name": n, "params": {}}))
            .collect();
        json!({"format": FORMAT, "driver": "br", "kind": "folder", "name": "g",
            "params": {}, "children": pts})
    };
    ok(
        &h,
        "c1/d1",
        "import",
        import_args(&folder(&["a", "b"]), None, false),
    )
    .await;
    let o = run(
        &h,
        "c1/d1",
        "import",
        import_args(&folder(&["c"]), None, false),
    )
    .await;
    assert_eq!(o.status, Some(Status::InvalidParameter));
    // Overwrite: `a` and `b` go, so `b` may come back in the new branch.
    ok(
        &h,
        "c1/d1",
        "import",
        import_args(&folder(&["b", "c"]), None, true),
    )
    .await;
    assert!(!exists(&h, "c1/d1/g/a").await);
    assert!(exists(&h, "c1/d1/g/b").await && exists(&h, "c1/d1/g/c").await);
    // A point is not replaced by a folder of its name.
    let mut p0 = folder(&["z"]);
    p0["name"] = json!("p0");
    let o = run(&h, "c1/d1", "import", import_args(&p0, None, true)).await;
    assert_eq!(o.status, Some(Status::InvalidParameter), "{}", o.err);
    assert!(exists(&h, "c1/d1/p0").await);
    h.stop().await;
}

/// Task 5 carry-over: a folder tree made at runtime (`add_folder`,
/// `add_point`), a copy and an import are saved in the sealed `data_dir`
/// tree and read back after a restart; the copied password too.
#[tokio::test(flavor = "multi_thread")]
async fn runtime_changes_survive_a_restart() {
    let tag = 67;
    let dir = temp_dir("restart");
    let h = start_stored(tree(tag), &dir).await;
    ok(&h, "c1/d1", "add_folder", named("r1")).await;
    ok(&h, "c1/d1/r1", "add_folder", named("r2")).await;
    ok(
        &h,
        "c1/d1/r1/r2",
        "add_point",
        map(&[("name", "rp".into()), ("addr", Value::UInt(9))]),
    )
    .await;
    ok(&h, "c1/d1/r1/r2/rp", "copy", named("rq")).await;
    ok(&h, "c1", "copy", named("c9")).await;
    let f = export(&h, "c1/d1/r1").await;
    // The imported points need ids of their own on the device.
    let o = run(&h, "c1/d1/f1", "import", import_args(&f, Some("i1"), false)).await;
    assert_eq!(o.status, Some(Status::InvalidParameter), "{}", o.err);
    assert!(o.err.contains("rp"), "{}", o.err);
    let with = |id: &str| {
        let mut j = f.clone();
        j["children"][0]["children"] = json!([
            {"kind": "point", "name": id, "params": {"addr": 4}}
        ]);
        j
    };
    ok(
        &h,
        "c1/d1/f1",
        "import",
        import_args(&with("ip0"), Some("i1"), false),
    )
    .await;
    ok(
        &h,
        "c1/d1/f1",
        "import",
        import_args(&with("ip1"), Some("i2"), false),
    )
    .await;
    let before = root_export(&h).await;
    h.stop().await;

    let h = start_stored(tree(tag), &dir).await;
    for p in [
        "c1/d1/r1",
        "c1/d1/r1/r2",
        "c1/d1/r1/r2/rp",
        "c1/d1/r1/r2/rq",
        "c1/d1/f1/i1/r2/ip0",
        "c1/d1/f1/i2/r2/ip1",
        "c9/d1/f1/f2/p2",
    ] {
        assert!(exists(&h, p).await, "{p} after a restart");
    }
    assert_eq!(root_export(&h).await, before);
    let rq = export(&h, "c1/d1/r1/r2").await;
    assert_eq!(rq["children"][1]["name"], "rq");
    assert_eq!(rq["children"][1]["params"]["addr"], 9);
    wait("runtime points polled", || {
        ["c1/d1/r1/r2/rp", "c1/d1/r1/r2/rq", "c1/d1/f1/i2/r2/ip1"]
            .iter()
            .all(|p| h.ctx().last(p).is_some_and(|s| s.q == Quality::Good))
    })
    .await;
    // The copy kept the sealed password: it stays disabled, and starts.
    assert_eq!(state(&h, "c9"), is_state(NodeState::Stopped));
    ok(&h, "c9", "start", map(&[])).await;
    wait("c9 connected", || {
        state(&h, "c9") == is_state(NodeState::Connected)
    })
    .await;
    h.stop().await;
    let _ = std::fs::remove_dir_all(&dir);
}

/// The largest import (`MAX_NODES`: a folder of 49 folders of 101 points)
/// and a copy of it finish inside the call (`timeout_ms`, and the harness
/// waits 10 s); a copy of more than `MAX_NODES` is refused.
#[tokio::test(flavor = "multi_thread")]
async fn largest_import_fits_the_call_bound() {
    let h = H::start(tree(68)).await;
    let subs: Vec<Json> = (0..49)
        .map(|f| {
            let pts: Vec<Json> = (0..101)
                .map(|i| {
                    json!({"kind": "point", "name": format!("n{f}_{i}"),
                        "params": {"poll_s": 60.0}})
                })
                .collect();
            json!({"kind": "folder", "name": format!("g{f}"), "params": {}, "children": pts})
        })
        .collect();
    let big = json!({"format": FORMAT, "driver": "br", "kind": "folder", "name": "big",
        "params": {}, "children": subs});
    assert_eq!(1 + 49 + 49 * 101, MAX_NODES - 1);
    let t = std::time::Instant::now();
    ok(&h, "c1/d1", "import", import_args(&big, None, false)).await;
    let took = t.elapsed();
    assert!(exists(&h, "c1/d1/big/g48/n48_100").await);
    let t = std::time::Instant::now();
    ok(&h, "c1/d1/big", "copy", named("big2")).await;
    let copied = t.elapsed();
    assert!(exists(&h, "c1/d1/big2/g48/n48_100_2").await);
    eprintln!(
        "import of {} nodes: {took:?}; copy: {copied:?}",
        MAX_NODES - 1
    );
    // The device now holds twice that: no copy of it.
    let o = run(&h, "c1/d1", "copy", named("d2")).await;
    assert_eq!(o.status, Some(Status::OutOfRange), "{}", o.err);
    assert!(o.err.contains(&MAX_NODES.to_string()), "{}", o.err);
    assert!(!exists(&h, "c1/d2").await);
    // Both actions carry their bound.
    let (_, meta) = h.meta("c1/d1").await;
    let acts = meta.unwrap().actions.unwrap();
    for a in ["copy", "import"] {
        assert_eq!(
            acts[a].timeout_ms,
            Some(wyrm_link_sdk::driver::branch::ACTION_MS)
        );
    }
    h.stop().await;
}

/// Fix round 1: a copy or an import cut half-way through (here: a panic
/// while its nodes are declared) has already changed the tree as a whole
/// and saved it, so a restart shows the new tree in full (never the old
/// connection lost, never half of the new one).
#[tokio::test(flavor = "multi_thread")]
async fn cut_apply_keeps_a_whole_tree() {
    let tag = 69;
    let dir = temp_dir("cut");
    let h = start_stored(tree(tag), &dir).await;
    let mut c1 = export(&h, "c1").await;
    c1["params"]["host"] = json!("h9");
    c1["children"][0]["children"] = json!([
        {"kind": "point", "name": "boom", "params": {"addr": 666}},
        {"kind": "point", "name": "p0", "params": {"addr": 1}}
    ]);
    BOOM.store(true, Ordering::SeqCst);
    let o = run(&h, "", "import", import_args(&c1, None, true)).await;
    assert_ne!(o.status, Some(Status::Ok), "the cut call fails");
    h.stop().await;

    let h = start_stored(tree(tag), &dir).await;
    let now = export(&h, "c1").await;
    assert_eq!(now["params"]["host"], "h9", "the new connection in full");
    assert_eq!(children(&now["children"][0]), ["boom", "p0"]);
    assert!(exists(&h, "c1/d1/boom").await && exists(&h, "c1/d1/p0").await);
    assert!(!exists(&h, "c1/d1/f1").await);

    BOOM.store(true, Ordering::SeqCst);
    let o = run(&h, "c1/d1", "copy", named("d2")).await;
    assert_ne!(o.status, Some(Status::Ok), "the cut call fails");
    h.stop().await;

    let h = start_stored(tree(tag), &dir).await;
    let (d1, d2) = (export(&h, "c1/d1").await, export(&h, "c1/d2").await);
    assert_eq!(d2["children"], d1["children"], "the copy in full");
    assert_eq!(d2["enabled"], false);
    assert!(exists(&h, "c1/d2/boom").await && exists(&h, "c1/d2/p0").await);
    h.stop().await;
    let _ = std::fs::remove_dir_all(&dir);
}

/// Fix round 1: an overwrite never shows a value read with the old params
/// on the new node of the same key (the old plan is gone before the new
/// nodes are declared). `b` at `addr` 5 polls slowly, so a poll of it is
/// in flight when the import comes.
#[tokio::test(flavor = "multi_thread")]
async fn overwrite_does_not_take_old_values() {
    let h = H::start(tree(70)).await;
    let folder = |addr: u64| {
        json!({"format": FORMAT, "driver": "br", "kind": "folder", "name": "g", "params": {},
            "children": [{"kind": "point", "name": "b", "params": {"addr": addr, "poll_s": 0.01}}]})
    };
    ok(&h, "c1/d1", "import", import_args(&folder(5), None, false)).await;
    let b = |h: &H| h.ctx().last("c1/d1/g/b").map(|s| s.v);
    wait("b reads 5", || b(&h) == Some(Value::Float(5.0))).await;
    tokio::time::sleep(Duration::from_millis(100)).await;
    ok(&h, "c1/d1", "import", import_args(&folder(9), None, true)).await;
    let until = tokio::time::Instant::now() + Duration::from_millis(700);
    while tokio::time::Instant::now() < until {
        assert_ne!(
            b(&h),
            Some(Value::Float(5.0)),
            "an old value on the new node"
        );
        tokio::time::sleep(Duration::from_millis(5)).await;
    }
    assert_eq!(b(&h), Some(Value::Float(9.0)));
    h.stop().await;
}

/// Ruling P17: an overwrite of a connection keeps its sealed secrets while
/// the destination (`dest` fields) stays the same; another destination
/// drops them and the import lists them.
#[tokio::test(flavor = "multi_thread")]
async fn overwrite_keeps_secrets_for_the_same_destination() {
    let h = H::start(tree(71)).await;
    let c1 = export(&h, "c1").await;
    let r = ok(&h, "", "import", import_args(&c1, None, true))
        .await
        .unwrap();
    let Value::Map(r) = r else { panic!() };
    assert_eq!(r.get("reenter"), Some(&Value::Array(vec![])), "kept");
    assert_eq!(state(&h, "c1"), is_state(NodeState::Stopped));
    ok(&h, "c1", "start", map(&[])).await;
    wait("c1 connected with the kept password", || {
        state(&h, "c1") == is_state(NodeState::Connected)
    })
    .await;

    let mut moved = c1.clone();
    moved["params"]["host"] = json!("h2");
    let r = ok(&h, "", "import", import_args(&moved, None, true))
        .await
        .unwrap();
    let Value::Map(r) = r else { panic!() };
    assert_eq!(
        r.get("reenter"),
        Some(&Value::Array(vec![Value::Str("c1.password".into())]))
    );
    assert_eq!(state(&h, "c1"), is_state(NodeState::Failed));
    h.stop().await;
}

/// Fix round 2 (ruling P19): requests planned before a change never run
/// on what replaced it. The owner is held (a driver action) longer than
/// the call bound while a poll of `p0` waits in its queue; the device is
/// overwritten meanwhile (it comes back stopped). Once released, the old
/// poll must not publish onto the new `p0` nor mark the device connected.
#[tokio::test(flavor = "multi_thread")]
async fn stale_requests_never_reach_new_nodes() {
    let h = H::start_with(tree(72), |lc| {
        lc.driver_timeout = Duration::from_millis(300)
    })
    .await;
    wait("p0 polled", || {
        h.ctx().last("c1/d1/p0").map(|s| s.v) == Some(Value::Float(1.0))
    })
    .await;
    let d1 = json!({"format": FORMAT, "driver": "br", "kind": "device", "name": "d1",
        "params": {"unit": 7}, "children": [
            {"kind": "point", "name": "p0", "params": {"addr": 7, "poll_s": 0.02}}]});
    let hold = h.invoke(
        "c1/d1",
        "hold",
        map(&[("ms", Value::UInt(1500))]),
        Some(h.ptok(Perm::Config)),
    );
    let overwrite = async {
        tokio::time::sleep(Duration::from_millis(200)).await;
        ok(&h, "c1", "import", import_args(&d1, None, true)).await
    };
    let (held, _) = tokio::join!(hold, overwrite);
    assert_eq!(
        code(held[0].att.status),
        Some(Status::Ok),
        "{:?}",
        held[0].att.err
    );
    let until = tokio::time::Instant::now() + Duration::from_millis(500);
    while tokio::time::Instant::now() < until {
        assert!(
            h.ctx().last("c1/d1/p0").is_none(),
            "an old value on the new node"
        );
        assert_eq!(state(&h, "c1/d1"), is_state(NodeState::Stopped));
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
    h.stop().await;
}

/// Fix round 2: a device pings again only once its last ping ran, so an
/// owner held for a second does not queue a ping per tick.
#[tokio::test(flavor = "multi_thread")]
async fn pings_do_not_pile_up() {
    let tag = 73;
    let mut t = tree(tag);
    if let Value::Map(top) = &mut t.0 {
        let Some(Value::Map(conns)) = top.get_mut("connections") else {
            panic!()
        };
        let Some(Value::Map(c1)) = conns.get_mut("c1") else {
            panic!()
        };
        let Some(Value::Map(devs)) = c1.get_mut("devices") else {
            panic!()
        };
        let Some(Value::Map(d1)) = devs.get_mut("d1") else {
            panic!()
        };
        d1.insert("ping_ms".into(), Value::UInt(10));
    }
    let h = H::start(t).await;
    let pings = |from: usize| log(tag).iter().skip(from).filter(|l| *l == "ping").count();
    wait("pinging", || pings(0) > 3).await;
    let hold = h.invoke(
        "c1/d1",
        "hold",
        map(&[("ms", Value::UInt(1000))]),
        Some(h.ptok(Perm::Config)),
    );
    let mark = async {
        tokio::time::sleep(Duration::from_millis(300)).await;
        log(tag).len()
    };
    let (held, from) = tokio::join!(hold, mark);
    assert_eq!(
        code(held[0].att.status),
        Some(Status::Ok),
        "{:?}",
        held[0].att.err
    );
    tokio::time::sleep(Duration::from_millis(100)).await;
    // About 100 ticks passed while held; at most one ping waited for the
    // owner, then one per 10 ms.
    let n = pings(from);
    assert!(n < 30, "{n} pings after the hold");
    h.stop().await;
}

/// Fix round 2: a driver action queued before a re-plan answers `busy` and
/// never reaches the device that replaced its target. `touch` waits behind
/// `hold`; meanwhile `d1` is overwritten (unit 9) and started.
#[tokio::test(flavor = "multi_thread")]
async fn stale_actions_answer_busy() {
    let tag = 74;
    let h = H::start(tree(tag)).await;
    wait("p0 polled", || h.ctx().last("c1/d1/p0").is_some()).await;
    let d1 = json!({"format": FORMAT, "driver": "br", "kind": "device", "name": "d1",
        "params": {"unit": 9}, "children": []});
    let cfg = || Some(h.ptok(Perm::Config));
    let hold = h.invoke("c1/d1", "hold", map(&[("ms", Value::UInt(1500))]), cfg());
    let touch = async {
        tokio::time::sleep(Duration::from_millis(100)).await;
        h.invoke("c1/d1", "touch", map(&[]), cfg()).await
    };
    let change = async {
        tokio::time::sleep(Duration::from_millis(300)).await;
        ok(&h, "c1", "import", import_args(&d1, None, true)).await;
        ok(&h, "c1/d1", "start", map(&[])).await;
    };
    let (held, touched, _) = tokio::join!(hold, touch, change);
    assert_eq!(
        code(held[0].att.status),
        Some(Status::Ok),
        "{:?}",
        held[0].att.err
    );
    assert_eq!(
        code(touched[0].att.status),
        Some(Status::Busy),
        "{:?}",
        touched[0].att.err
    );
    assert!(
        !log(tag).iter().any(|l| l.starts_with("touch")),
        "{:?}",
        log(tag)
    );
    h.stop().await;
}

/// Fix round 3 (ruling P21): a device stopped and started again shows
/// `Stopped`, then `New`, then `Connected` once polled (the owner does not
/// keep its cached state across the re-plans).
#[tokio::test(flavor = "multi_thread")]
async fn stop_start_shows_connected_again() {
    let h = H::start(tree(75)).await;
    wait("connected", || {
        state(&h, "c1/d1") == is_state(NodeState::Connected)
    })
    .await;
    ok(&h, "c1/d1", "stop", map(&[])).await;
    assert_eq!(state(&h, "c1/d1"), is_state(NodeState::Stopped));
    ok(&h, "c1/d1", "start", map(&[])).await;
    assert_eq!(state(&h, "c1/d1"), is_state(NodeState::New));
    wait("connected again", || {
        state(&h, "c1/d1") == is_state(NodeState::Connected)
    })
    .await;
    h.stop().await;
}

/// Fix round 3: the owner's status loops run under the plan's read lock. A
/// transport failure while a device is overwritten (the new one comes
/// back stopped) never marks the new device stopped by its parent.
/// Hundreds of devices make the failure's loop long enough to overlap.
#[tokio::test(flavor = "multi_thread")]
async fn overwrite_during_failure_stays_stopped() {
    let mut t = tree(76);
    if let Value::Map(top) = &mut t.0 {
        let Some(Value::Map(conns)) = top.get_mut("connections") else {
            panic!()
        };
        let Some(Value::Map(c1)) = conns.get_mut("c1") else {
            panic!()
        };
        let Some(Value::Map(devs)) = c1.get_mut("devices") else {
            panic!()
        };
        devs.insert(
            "a".into(),
            map(&[("points", map(&[("x", map(&[("addr", Value::UInt(13))]))]))]),
        );
        for i in 0..400 {
            devs.insert(format!("m{i:03}"), map(&[]));
        }
        devs.insert("zz".into(), map(&[]));
    }
    let h = H::start(t).await;
    wait("a polled", || h.ctx().last("c1/a/x").is_some()).await;
    let zz = json!({"format": FORMAT, "driver": "br", "kind": "device", "name": "zz",
        "params": {"unit": 3}, "children": []});
    FAILED.store(false, Ordering::SeqCst);
    FAIL.store(true, Ordering::SeqCst);
    wait("transport cut", || FAILED.load(Ordering::SeqCst)).await;
    ok(&h, "c1", "import", import_args(&zz, None, true)).await;
    let until = tokio::time::Instant::now() + Duration::from_millis(400);
    while tokio::time::Instant::now() < until {
        tokio::time::sleep(Duration::from_millis(10)).await;
        assert_eq!(state(&h, "c1/zz"), is_state(NodeState::Stopped));
    }
    h.stop().await;
}

/// Fix round 3: `stop` cuts the plan off first, then marks the points bad:
/// no good value of the stopped device follows. 300 points polled every
/// 10 ms keep a poll's results coming while `stop` marks them.
#[tokio::test(flavor = "multi_thread")]
async fn stop_marks_bad_and_stays_bad() {
    let mut t = tree(77);
    if let Value::Map(top) = &mut t.0 {
        let Some(Value::Map(conns)) = top.get_mut("connections") else {
            panic!()
        };
        let Some(Value::Map(c1)) = conns.get_mut("c1") else {
            panic!()
        };
        let Some(Value::Map(devs)) = c1.get_mut("devices") else {
            panic!()
        };
        let pts: Vec<(String, Value)> = (0..300)
            .map(|i| (format!("q{i:03}"), map(&[("poll_s", Value::Float(0.01))])))
            .collect();
        let kv: Vec<(&str, Value)> = pts.iter().map(|(k, v)| (k.as_str(), v.clone())).collect();
        devs.insert("big".into(), map(&[("points", map(&kv))]));
    }
    let h = H::start(t).await;
    let all = |q: Quality| {
        (0..300).all(|i| {
            h.ctx()
                .last(&format!("c1/big/q{i:03}"))
                .is_some_and(|s| s.q == q)
        })
    };
    for round in 0..20 {
        wait("all good", || all(Quality::Good)).await;
        ok(&h, "c1/big", "stop", map(&[])).await;
        tokio::time::sleep(Duration::from_millis(60)).await;
        assert!(all(Quality::Bad), "round {round}: a good value after stop");
        ok(&h, "c1/big", "start", map(&[])).await;
    }
    h.stop().await;
}

/// A root import (Task 7 entry): every connection is checked before the
/// first is imported; each is imported like `import` (stopped, secrets in
/// `reenter`), and the reply lists every new node beside the driver's report.
#[tokio::test(flavor = "multi_thread")]
async fn root_import_checks_all_then_imports_each() {
    let h = H::start(tree(61)).await;
    let (_, root) = h.meta("").await;
    let acts = root.unwrap().actions.unwrap();
    assert_eq!(acts["import_list"].level, Some(Perm::Config));
    assert_eq!(acts["import_list"].timeout_ms, Some(branch::ACTION_MS));
    let names = |n: &str| map(&[("names", n.into())]);
    let r = h
        .invoke("", "import_list", names("n1"), Some(h.ptok(Perm::Write)))
        .await;
    assert_eq!(code(r[0].att.status), Some(Status::PermissionDenied));
    assert!(!exists(&h, "n1").await);

    let v = ok(&h, "", "import_list", names("n1,n2")).await.unwrap();
    let Value::Map(m) = v else { panic!("{v:?}") };
    assert_eq!(m["names"], Value::UInt(2), "the driver's report");
    let keys = |ks: &[&str]| Value::Array(ks.iter().map(|k| Value::from(*k)).collect());
    assert_eq!(
        m["created"],
        keys(&[
            "n1",
            "n1/d1",
            "n1/d1/f1",
            "n1/d1/f1/p1",
            "n2",
            "n2/d1",
            "n2/d1/f1",
            "n2/d1/f1/p1"
        ])
    );
    assert_eq!(m["reenter"], keys(&["n1.password", "n2.password"]));
    // Loaded without the secret: Failed with it named, and not running.
    for c in ["n1", "n2"] {
        assert!(exists(&h, &format!("{c}/d1/f1/p1")).await);
        assert_eq!(state(&h, c), is_state(NodeState::Failed), "{c}");
        assert!(actions(&h, c).await.contains(&"start".to_owned()), "{c}");
    }

    // One name taken (or twice, or invalid): refused, nothing imported.
    for (list, needle) in [
        ("n3,c1", "c1: a connection of that name exists"),
        ("n3,n3", "twice"),
        ("n3,bad name", "bad name"),
    ] {
        let o = run(&h, "", "import_list", names(list)).await;
        assert_eq!(o.status, Some(Status::InvalidParameter), "{list}");
        assert!(o.err.contains(needle), "{list}: {}", o.err);
        assert!(!exists(&h, "n3").await, "{list}");
    }
    h.stop().await;
}
