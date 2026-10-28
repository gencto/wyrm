//! The `app` driver (ADR 0023): a WASM component on the portable runtime behaves as the same app
//! compiled into the host, survives traps, fuel, memory and time limits, and takes a hot swap.
//!
//! The test app (`tests/app_fixture/src/echo.rs`) is built here for wasm32-unknown-unknown and
//! turned into a component with `wit-component`; the tests skip when the target is missing.

#[path = "app_fixture/src/echo.rs"]
mod echo;

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::{Arc, Mutex, OnceLock};
use std::time::{Duration, Instant};

use ed25519_dalek::SigningKey;
use wyrm_core::status::StatusCode;
use wyrm_core::{Attachment, NodeMeta, Perm, Quality, Status, Value};
use wyrm_link_portable::{Portable, PortableConfig};
use wyrm_link_sdk::harness::{TestHarness, SITE, TEST_KEY_SEED};
use wyrm_link_sdk::params::FromParams;
use wyrm_link_sdk::runtime::{self, LinkConfig};
use wyrm_link_sdk::{Caller, Link, LinkCtx, Secret};
use wyrm_wasm_host::{component_world, ComponentWorld};

const STORE_KEY: [u8; 32] = [9; 32];

type Native = Portable<echo::Echo>;
type Wasm = wyrm_link_wasm::App;

// ---------- the component ----------

fn wasm32_installed() -> bool {
    Command::new("rustc")
        .args([
            "--print",
            "target-libdir",
            "--target",
            "wasm32-unknown-unknown",
        ])
        .output()
        .ok()
        .filter(|o| o.status.success())
        .map(|o| PathBuf::from(String::from_utf8_lossy(&o.stdout).trim()))
        .is_some_and(|dir| dir.exists())
}

/// Builds the fixture app and makes it a component: `None` without the wasm32 target.
fn build_component() -> Option<Vec<u8>> {
    if !wasm32_installed() {
        return None;
    }
    let crate_dir = Path::new(env!("CARGO_MANIFEST_DIR"));
    let fixture = crate_dir.join("tests/app_fixture");
    // its own workspace: seed the lock file from the main one (same versions)
    std::fs::copy(
        crate_dir.join("../../Cargo.lock"),
        fixture.join("Cargo.lock"),
    )
    .expect("copy Cargo.lock");
    let target = Path::new(env!("CARGO_TARGET_TMPDIR")).join("app-fixture");
    let out = Command::new(env!("CARGO"))
        .args([
            "build",
            "--release",
            "--target",
            "wasm32-unknown-unknown",
            "--manifest-path",
        ])
        .arg(fixture.join("Cargo.toml"))
        .arg("--target-dir")
        .arg(&target)
        .env_remove("RUSTFLAGS")
        .env_remove("CARGO_ENCODED_RUSTFLAGS")
        .output()
        .expect("run cargo");
    assert!(
        out.status.success(),
        "fixture build failed:\n{}",
        String::from_utf8_lossy(&out.stderr)
    );
    let core = std::fs::read(
        target.join("wasm32-unknown-unknown/release/wyrm_link_wasm_app_fixture.wasm"),
    )
    .expect("fixture wasm");
    let component = wit_component::ComponentEncoder::default()
        .module(&core)
        .expect("component type")
        .validate(true)
        .encode()
        .expect("componentize");
    Some(component)
}

/// The component store of this process with the app as packages `echo` and `swap` (the hot swap
/// test replaces `swap` only). `None` (and a SKIP line) without the wasm32 target.
fn component(test: &str) -> Option<&'static [u8]> {
    static BUILT: OnceLock<Option<Vec<u8>>> = OnceLock::new();
    let built = BUILT.get_or_init(|| {
        let c = build_component()?;
        let root = std::env::temp_dir().join(format!("wyrm-wasm-app-{}", std::process::id()));
        std::fs::create_dir_all(&root).unwrap();
        for p in ["echo", "swap"] {
            std::fs::write(root.join(format!("{p}.wasm")), &c).unwrap();
        }
        wyrm_link_wasm::set_component_root(root);
        Some(c)
    });
    if built.is_none() {
        eprintln!(
            "SKIP {test}: target wasm32-unknown-unknown is not installed \
             (rustup target add wasm32-unknown-unknown)"
        );
    }
    built.as_deref()
}

// ---------- harness helpers ----------

fn data_dir(name: &str) -> PathBuf {
    let d = std::env::temp_dir().join(format!(
        "wyrm-wasm-app-{name}-{}-{}",
        std::process::id(),
        wyrm_link_sdk::now_us()
    ));
    let _ = std::fs::remove_dir_all(&d);
    std::fs::create_dir_all(&d).unwrap();
    d
}

/// The link params: the package and whatever the scenario adds. The native engine has no use for
/// `component`; the host keys never reach the app.
fn config(package: &str, params: &[(&str, Value)]) -> PortableConfig {
    let mut m: BTreeMap<String, Value> = params
        .iter()
        .map(|(k, v)| ((*k).to_owned(), v.clone()))
        .collect();
    m.insert("component".into(), Value::Str(package.into()));
    PortableConfig::from_params(&Value::Map(m)).expect("config")
}

async fn start<L: Link<Config = PortableConfig>>(
    cfg: PortableConfig,
    dir: &Path,
    grants: Vec<(String, Perm)>,
) -> TestHarness<L> {
    let dir = dir.to_path_buf();
    TestHarness::<L>::start_with(cfg, move |c| {
        c.data_dir = Some(dir);
        c.secrets
            .insert(".store_key", Secret::new(STORE_KEY.to_vec()));
        c.secrets
            .insert(".requester_key", Secret::new(TEST_KEY_SEED.to_vec()));
        c.grants = grants;
    })
    .await
}

fn status(a: &Attachment) -> Status {
    match a.status.expect("status present") {
        StatusCode::Known(s) => s,
        other => panic!("unexpected status {other:?}"),
    }
}

fn root_attr<L: Link>(h: &TestHarness<L>, name: &str) -> Option<Value> {
    h.ctx().meta("").and_then(|m| m.attr_value(name).cloned())
}

fn last<L: Link>(h: &TestHarness<L>, path: &str) -> Option<Value> {
    h.ctx().last(path).map(|s| s.v)
}

fn num<L: Link>(h: &TestHarness<L>, path: &str) -> Option<f64> {
    last(h, path).and_then(|v| v.as_f64())
}

/// Polls `f` every 20 ms until it holds or `within` passes.
async fn eventually(within: Duration, mut f: impl FnMut() -> bool) -> bool {
    let end = Instant::now() + within;
    while Instant::now() < end {
        if f() {
            return true;
        }
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
    f()
}

fn str_v(s: &str) -> Value {
    Value::Str(s.into())
}

fn empty() -> Value {
    Value::Map(BTreeMap::new())
}

async fn invoke<L: Link>(h: &TestHarness<L>, action: &str, args: Value) -> (Status, Option<Value>) {
    let r = h.invoke("", action, args, Some(h.ptok(Perm::Write))).await;
    assert_eq!(r.len(), 1, "{action}");
    (status(&r[0].att), r[0].value())
}

// ---------- the four scenarios of the native engine (wyrm-link-portable tests/native.rs) ----------

/// What a scenario observed: compared between the engines line by line.
type Transcript = Vec<String>;

async fn tree_set_invoke_timer<L: Link<Config = PortableConfig>>() -> Transcript {
    let mut t = Vec::new();
    let dir = data_dir("tree");
    let h = start::<L>(config("echo", &[]), &dir, Vec::new()).await;

    let (_, root) = h.meta("").await;
    let root = root.expect("root meta");
    let mut children = root.children.clone().unwrap_or_default();
    children.sort();
    t.push(format!("children {children:?}"));
    let mut actions: Vec<_> = root
        .actions
        .clone()
        .unwrap_or_default()
        .into_keys()
        .collect();
    actions.sort();
    t.push(format!("actions {actions:?}"));
    t.push(format!("status {:?}", root_attr(&h, "status")));

    let att = h.set("n", 5i64, Some(h.ptok(Perm::Write))).await;
    t.push(format!("set n=5 {:?}", status(&att)));
    t.push(format!("n {:?}", num(&h, "n")));
    t.push(format!("ping {:?}", invoke(&h, "ping", empty()).await));
    let ticked = eventually(Duration::from_millis(500), || num(&h, "ticks") == Some(1.0)).await;
    t.push(format!("ticks after 500 ms {ticked}"));
    h.stop().await;
    let _ = std::fs::remove_dir_all(&dir);
    t
}

async fn store_survives_restart_and_quota_holds<L: Link<Config = PortableConfig>>() -> Transcript {
    let mut t = Vec::new();
    let dir = data_dir("store");
    let h = start::<L>(config("echo", &[]), &dir, Vec::new()).await;
    let att = h.set("n", 7i64, Some(h.ptok(Perm::Write))).await;
    t.push(format!("set n=7 {:?}", status(&att)));
    h.stop().await;

    let h = start::<L>(config("echo", &[]), &dir, Vec::new()).await;
    t.push(format!("n after restart {:?}", num(&h, "n")));
    t.push(format!("starts {:?}", num(&h, "starts")));
    h.stop().await;

    let full = data_dir("store-full");
    let h = start::<L>(
        config("echo", &[("store_mb", Value::UInt(0))]),
        &full,
        Vec::new(),
    )
    .await;
    let att = h.set("n", 7i64, Some(h.ptok(Perm::Write))).await;
    t.push(format!("set n=7 without room {:?}", status(&att)));
    t.push(format!("status {:?}", root_attr(&h, "status")));
    h.stop().await;
    let _ = std::fs::remove_dir_all(&dir);
    let _ = std::fs::remove_dir_all(&full);
    t
}

async fn fault_restarts_with_backoff_and_sweeps<L: Link<Config = PortableConfig>>() -> Transcript {
    let mut t = Vec::new();
    let dir = data_dir("panic");
    let h = start::<L>(
        config("echo", &[("extra", Value::Bool(true))]),
        &dir,
        Vec::new(),
    )
    .await;
    t.push(format!("extra {}", h.ctx().has_node("extra")));
    let att = h.set("n", 7i64, Some(h.ptok(Perm::Write))).await;
    t.push(format!("set n=7 {:?}", status(&att)));

    let att = h.set("n", -1i64, Some(h.ptok(Perm::Write))).await;
    t.push(format!("set n=-1 {:?}", status(&att)));
    let restarting = eventually(Duration::from_millis(500), || {
        root_attr(&h, "status") == Some(str_v("restarting"))
    })
    .await;
    t.push(format!("restarting {restarting}"));
    t.push(format!(
        "error shown {}",
        matches!(root_attr(&h, "error"), Some(Value::Str(e)) if !e.is_empty())
    ));
    t.push(format!("n quality {:?}", h.ctx().last("n").map(|s| s.q)));
    let running = eventually(Duration::from_secs(3), || {
        root_attr(&h, "status") == Some(str_v("running"))
    })
    .await;
    t.push(format!("running again {running}"));
    let n = h.ctx().last("n");
    t.push(format!("n {:?}", n.map(|s| (s.v.as_f64(), s.q))));
    t.push(format!("extra kept for now {}", h.ctx().has_node("extra")));
    let swept = eventually(Duration::from_secs(12), || !h.ctx().has_node("extra")).await;
    t.push(format!("extra swept {swept}"));
    t.push(format!("n kept {}", h.ctx().has_node("n")));
    h.stop().await;
    let _ = std::fs::remove_dir_all(&dir);
    t
}

/// A link that records what is written to its point `p`, which reads 42.
struct Sink {
    got: Arc<Mutex<Vec<Value>>>,
}

impl Link for Sink {
    const NAME: &'static str = "sink";
    const VERSION: &'static str = "0.1.0";
    type Config = Arc<Mutex<Vec<Value>>>;

    async fn start(got: Self::Config, ctx: LinkCtx) -> wyrm_link_sdk::Result<Self> {
        ctx.declare_node(
            "p",
            NodeMeta::number().writable(wyrm_core::meta::Writable::Write),
        )
        .await?;
        ctx.update("p", 42u64, Quality::Good, wyrm_link_sdk::now_us())
            .await?;
        Ok(Sink { got })
    }

    async fn on_set(
        &mut self,
        _path: &str,
        value: Value,
        _who: &Caller,
    ) -> wyrm_link_sdk::Result<()> {
        self.got.lock().unwrap().push(value);
        Ok(())
    }
}

async fn requests_outside_grants_are_refused<L: Link<Config = PortableConfig>>() -> Transcript {
    let mut t = Vec::new();
    let dir = data_dir("grants");
    let mock = format!("wy/{SITE}/downstream/mock");
    let h = start::<L>(
        config("echo", &[]),
        &dir,
        vec![(format!("{mock}/**"), Perm::Write)],
    )
    .await;

    let got = Arc::new(Mutex::new(Vec::new()));
    let mut lcfg = LinkConfig::new(SITE, "mock");
    lcfg.admin_keys = vec![SigningKey::from_bytes(&TEST_KEY_SEED).verifying_key()];
    lcfg.answer_val = true;
    let sink = runtime::spawn::<Sink>(h.session().clone(), lcfg, got.clone())
        .await
        .expect("sink");

    let call = |op: &str, key: &str| {
        let mut m = BTreeMap::new();
        m.insert("op".to_owned(), str_v(op));
        m.insert("key".to_owned(), str_v(key));
        m.insert("value".to_owned(), Value::UInt(1));
        Value::Map(m)
    };

    let (s, _) = invoke(&h, "call", call("set", &format!("{mock}/p"))).await;
    t.push(format!("set inside {s:?}"));
    let reached = eventually(Duration::from_secs(3), || {
        got.lock().unwrap().iter().any(|v| v.as_f64() == Some(1.0))
    })
    .await;
    t.push(format!("reached the mock {reached}"));
    let replied = eventually(Duration::from_secs(3), || {
        last(&h, "reply") == Some(str_v("ok"))
    })
    .await;
    t.push(format!("reply ok {replied}"));

    let (s, _) = invoke(&h, "call", call("subscribe", &format!("{mock}/p"))).await;
    t.push(format!("subscribe inside {s:?}"));
    let seen = eventually(Duration::from_secs(3), || num(&h, "seen") == Some(42.0)).await;
    t.push(format!("seen 42 {seen}"));

    for (op, key) in [
        ("set", format!("wy/{SITE}/downstream/other/p")),
        ("subscribe", format!("wy/{SITE}/downstream/other/p")),
        ("subscribe", "wy/x/downstream/mock/p".to_owned()),
    ] {
        let (s, _) = invoke(&h, "call", call(op, &key)).await;
        t.push(format!("{op} {key} {s:?}"));
    }
    t.push(format!("sets received {}", got.lock().unwrap().len()));

    sink.stop().await;
    h.stop().await;
    let _ = std::fs::remove_dir_all(&dir);
    t
}

async fn all_scenarios<L: Link<Config = PortableConfig>>() -> Vec<Transcript> {
    let (a, b, c, d) = tokio::join!(
        tree_set_invoke_timer::<L>(),
        store_survives_restart_and_quota_holds::<L>(),
        fault_restarts_with_backoff_and_sweeps::<L>(),
        requests_outside_grants_are_refused::<L>(),
    );
    vec![a, b, c, d]
}

#[tokio::test(flavor = "multi_thread")]
async fn same_scenario_as_native() {
    if component("same_scenario_as_native").is_none() {
        return;
    }
    let (native, wasm) = tokio::join!(all_scenarios::<Native>(), all_scenarios::<Wasm>());
    // the native run is the reference: it must pass the Task 4 checks itself
    let expect: &[&[&str]] = &[
        &[
            r#"children ["n", "reply", "seen", "starts", "ticks"]"#,
            r#"actions ["call", "grow", "ping", "slow", "spin", "trap"]"#,
            r#"status Some(Str("running"))"#,
            "set n=5 Ok",
            "n Some(5.0)",
            r#"ping (Ok, Some(Str("pong")))"#,
            "ticks after 500 ms true",
        ],
        &[
            "set n=7 Ok",
            "n after restart Some(7.0)",
            "starts Some(2.0)",
            "set n=7 without room ResourceExhausted",
            r#"status Some(Str("running"))"#,
        ],
        &[
            "extra true",
            "set n=7 Ok",
            "set n=-1 InternalError",
            "restarting true",
            "error shown true",
            "n quality Some(Bad)",
            "running again true",
            "n Some((Some(7.0), Good))",
            "extra kept for now true",
            "extra swept true",
            "n kept true",
        ],
        &[
            "set inside Ok",
            "reached the mock true",
            "reply ok true",
            "subscribe inside Ok",
            "seen 42 true",
            &format!("set wy/{SITE}/downstream/other/p PermissionDenied"),
            &format!("subscribe wy/{SITE}/downstream/other/p PermissionDenied"),
            "subscribe wy/x/downstream/mock/p PermissionDenied",
            "sets received 1",
        ],
    ];
    for (i, want) in expect.iter().enumerate() {
        assert_eq!(native[i], *want, "native scenario {i}");
    }
    assert_eq!(wasm, native, "the WASM engine differs from the native one");
}

// ---------- faults ----------

/// One fault: the action that causes it and a word the root `error` shows.
async fn fault_and_back(action: &'static str, words: &[&str]) {
    let dir = data_dir(action);
    // a short call: the endless loop ends on time or fuel within 300 ms
    let h = start::<Wasm>(
        config("echo", &[("call_ms", Value::UInt(300))]),
        &dir,
        Vec::new(),
    )
    .await;
    assert_eq!(root_attr(&h, "status"), Some(str_v("running")), "{action}");
    let att = h.set("n", 3i64, Some(h.ptok(Perm::Write))).await;
    assert_eq!(status(&att), Status::Ok, "{action}: {:?}", att.err);

    let t = Instant::now();
    let (s, _) = invoke(&h, action, empty()).await;
    assert_eq!(s, Status::InternalError, "{action}");
    assert!(
        t.elapsed() < Duration::from_secs(2),
        "{action} took {:?}",
        t.elapsed()
    );
    assert!(
        eventually(Duration::from_millis(500), || root_attr(&h, "status")
            == Some(str_v("restarting")))
        .await,
        "{action}: status {:?}",
        root_attr(&h, "status")
    );
    let error = match root_attr(&h, "error") {
        Some(Value::Str(e)) => e,
        other => panic!("{action}: error {other:?}"),
    };
    assert!(
        words.iter().any(|w| error.contains(w)),
        "{action}: error {error:?}, expected one of {words:?}"
    );
    // the broker side answers while the instance is gone
    let (att, meta) = h.meta("").await;
    assert_eq!(status(&att), Status::Ok, "{action}");
    assert!(meta.is_some());
    assert!(
        eventually(Duration::from_secs(3), || root_attr(&h, "status")
            == Some(str_v("running")))
        .await,
        "{action}: status {:?}",
        root_attr(&h, "status")
    );
    // a new instance: it took `n` from the store and answers again
    assert_eq!(num(&h, "n"), Some(3.0), "{action}");
    assert_eq!(num(&h, "starts"), Some(2.0), "{action}");
    let att = h.set("n", 4i64, Some(h.ptok(Perm::Write))).await;
    assert_eq!(status(&att), Status::Ok, "{action}: {:?}", att.err);
    h.stop().await;
    let _ = std::fs::remove_dir_all(&dir);
}

#[tokio::test(flavor = "multi_thread")]
async fn trap_fuel_memory_time_restart() {
    if component("trap_fuel_memory_time_restart").is_none() {
        return;
    }
    tokio::join!(
        fault_and_back("trap", &["trap", "unreachable"]),
        fault_and_back("spin", &["fuel", "time"]),
        fault_and_back("grow", &["memory"]),
    );
}

// ---------- hot swap ----------

#[tokio::test(flavor = "multi_thread")]
async fn hot_swap_keeps_store_and_fails_inflight() {
    if component("hot_swap_keeps_store_and_fails_inflight").is_none() {
        return;
    }
    let dir = data_dir("swap");
    let h = start::<Wasm>(config("swap", &[]), &dir, Vec::new()).await;
    let att = h.set("n", 7i64, Some(h.ptok(Perm::Write))).await;
    assert_eq!(status(&att), Status::Ok, "{:?}", att.err);
    assert_eq!(num(&h, "starts"), Some(1.0));

    let h = Arc::new(h);

    // a `set` cut off by the swap: `busy`, and its store write never lands
    let slow_set = {
        let h = h.clone();
        tokio::spawn(async move { h.set("n", -2i64, Some(h.ptok(Perm::Write))).await })
    };
    tokio::time::sleep(Duration::from_millis(80)).await;
    let swapped = tokio::task::spawn_blocking(|| wyrm_link_wasm::app::reload_component("swap"))
        .await
        .unwrap()
        .expect("reload");
    assert_eq!(swapped, 1);
    let att = slow_set.await.unwrap();
    assert_eq!(status(&att), Status::Busy, "{:?}", att.err);
    assert!(
        eventually(Duration::from_secs(2), || num(&h, "starts") == Some(2.0)).await,
        "starts {:?}",
        num(&h, "starts")
    );
    // the new `start` read `n` from the store: 9 would be the cut-off write
    assert_eq!(num(&h, "n"), Some(7.0));

    // an `invoke` cut off the same way
    let slow = {
        let h = h.clone();
        tokio::spawn(async move { invoke(&h, "slow", empty()).await })
    };
    tokio::time::sleep(Duration::from_millis(80)).await;
    let swapped = tokio::task::spawn_blocking(|| wyrm_link_wasm::app::reload_component("swap"))
        .await
        .unwrap()
        .expect("reload");
    assert_eq!(swapped, 1);
    let (s, v) = slow.await.unwrap();
    assert_eq!(s, Status::Busy, "the cut off invoke answered {v:?}");

    // the new instance started on the same store
    assert!(
        eventually(Duration::from_secs(2), || num(&h, "starts") == Some(3.0)).await,
        "starts {:?}",
        num(&h, "starts")
    );
    assert_eq!(root_attr(&h, "status"), Some(str_v("running")));
    assert_eq!(num(&h, "n"), Some(7.0));
    let att = h.set("n", 8i64, Some(h.ptok(Perm::Write))).await;
    assert_eq!(status(&att), Status::Ok, "{:?}", att.err);
    assert_eq!(num(&h, "n"), Some(8.0));
    let (s, v) = invoke(&h, "slow", empty()).await;
    assert_eq!((s, v), (Status::Ok, Some(str_v("slow"))));

    let Ok(h) = Arc::try_unwrap(h) else {
        panic!("harness still shared")
    };
    h.stop().await;
    let _ = std::fs::remove_dir_all(&dir);
}

// ---------- world detection ----------

#[test]
fn an_app_component_is_told_by_its_exports() {
    let Some(c) = component("an_app_component_is_told_by_its_exports") else {
        return;
    };
    assert_eq!(component_world(c).unwrap(), ComponentWorld::App);
    assert_eq!(
        wyrm_link_wasm::package_world("echo"),
        Some(ComponentWorld::App)
    );
    assert_eq!(wyrm_link_wasm::package_world("missing"), None);
}
