//! The native engine on the portable runtime (ADR 0023): tree, `set`, `invoke`, timers, the store,
//! faults with restarts and the re-declare sweep, and requests within grants.

use std::collections::BTreeMap;
use std::path::PathBuf;
use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use ed25519_dalek::SigningKey;
use wyrm_core::meta::ParamMeta;
use wyrm_core::status::StatusCode;
use wyrm_core::{ActionMeta, Attachment, NodeMeta, Perm, Quality, Sample, Status, TypeCode, Value};
use wyrm_link_api::{App, AppError, Host, ReqId, SubId, TimerId, Who};
use wyrm_link_portable::{Portable, PortableConfig};
use wyrm_link_sdk::harness::{TestHarness, SITE, TEST_KEY_SEED};
use wyrm_link_sdk::params::FromParams;
use wyrm_link_sdk::runtime::{self, LinkConfig};
use wyrm_link_sdk::{Caller, Link, LinkCtx, Secret};

const STORE_KEY: [u8; 32] = [9; 32];

fn sample(v: Value) -> Sample {
    Sample {
        v,
        q: Quality::Good,
        t: 1,
    }
}

/// The test app: `n` (writable, kept in the store), `ticks` (timer count), `reply` (last reply),
/// actions `ping` (a 50 ms timer, answers `"pong"`) and `call` (a request to another point).
/// A value of -1 makes it panic. With `extra: true` it declares `extra` on its first start only.
/// `seen` shows the last subscribed value. `arm` sets a 100 ms timer that `slow_cancel` cancels
/// after 400 ms; `late` sets a timer whose `on_timer` takes 3 s and then writes `late` to the store.
/// `sleep` takes 600 ms, `nap` 2 s; `actions {n}` declares `n` more actions on the root.
struct Echo {
    ticks: u64,
    armed: Option<TimerId>,
    late: bool,
}

impl App for Echo {
    const NAME: &'static str = "echo";
    const VERSION: &'static str = "0.1.0";

    fn start(host: &mut dyn Host, config: Value) -> Result<Self, AppError> {
        host.declare_node(
            "n",
            NodeMeta::number().writable(wyrm_core::meta::Writable::Write),
        );
        host.declare_node("ticks", NodeMeta::number());
        host.declare_node("reply", NodeMeta::leaf(TypeCode::String));
        host.declare_node("seen", NodeMeta::number());
        for a in ["ping", "arm", "slow_cancel", "late", "sleep", "nap"] {
            host.declare_action("", a, ActionMeta::new().level(Perm::Write));
        }
        // `actions {n}` declares `n` more actions on the root
        host.declare_action(
            "",
            "actions",
            ActionMeta::new()
                .level(Perm::Write)
                .param("n", ParamMeta::of(TypeCode::Number)),
        );
        host.declare_action(
            "",
            "call",
            ActionMeta::new()
                .level(Perm::Write)
                .param("op", ParamMeta::of(TypeCode::String))
                .param("key", ParamMeta::of(TypeCode::String))
                .param("value", ParamMeta::of(TypeCode::Number)),
        );
        let extra = matches!(&config, Value::Map(m) if m.get("extra") == Some(&Value::Bool(true)));
        if extra && host.store_get("started").is_none() {
            host.declare_node("extra", NodeMeta::number());
            host.store_put("started", &[1])?;
        }
        if let Some(b) = host.store_get("n") {
            let v: Value = wyrm_core::codec::from_slice(&b)
                .map_err(|e| AppError::new(Status::InternalError, e.to_string()))?;
            host.update("n", sample(v));
        }
        Ok(Echo {
            ticks: 0,
            armed: None,
            late: false,
        })
    }

    fn on_set(
        &mut self,
        host: &mut dyn Host,
        path: &str,
        value: Value,
        _who: &Who,
    ) -> Result<(), AppError> {
        if value.as_f64() == Some(-1.0) {
            panic!("asked to fail");
        }
        if path != "n" {
            return Err(AppError::new(Status::NotFound, path));
        }
        let b = wyrm_core::codec::to_vec(&value)
            .map_err(|e| AppError::new(Status::InternalError, e.to_string()))?;
        host.store_put("n", &b)?;
        host.update("n", sample(value));
        Ok(())
    }

    fn on_invoke(
        &mut self,
        host: &mut dyn Host,
        _path: &str,
        action: &str,
        args: Value,
        _who: &Who,
    ) -> Result<Value, AppError> {
        match action {
            "ping" => {
                host.set_timer(50)?;
                Ok(Value::Str("pong".into()))
            }
            "arm" => {
                self.armed = Some(host.set_timer(100)?);
                Ok(Value::Null)
            }
            "slow_cancel" => {
                std::thread::sleep(Duration::from_millis(400));
                if let Some(t) = self.armed.take() {
                    host.cancel_timer(t);
                }
                Ok(Value::Null)
            }
            "late" => {
                self.late = true;
                host.set_timer(0)?;
                Ok(Value::Null)
            }
            "sleep" => {
                std::thread::sleep(Duration::from_millis(600));
                Ok(Value::Str("awake".into()))
            }
            "nap" => {
                std::thread::sleep(Duration::from_secs(2));
                Ok(Value::Null)
            }
            "actions" => {
                let n = match &args {
                    Value::Map(m) => m.get("n").and_then(Value::as_f64).unwrap_or(0.0),
                    _ => 0.0,
                };
                for i in 0..n as u32 {
                    host.declare_action("", &format!("x{i}"), ActionMeta::new());
                }
                Ok(Value::Null)
            }
            "call" => {
                let m = match &args {
                    Value::Map(m) => m,
                    _ => return Err(AppError::new(Status::InvalidParameter, "args")),
                };
                let key = match m.get("key") {
                    Some(Value::Str(k)) => k.clone(),
                    _ => return Err(AppError::new(Status::InvalidParameter, "key")),
                };
                match m.get("op") {
                    Some(Value::Str(op)) if op == "set" => {
                        let v = m.get("value").cloned().unwrap_or(Value::Null);
                        host.set(&key, v)?;
                    }
                    Some(Value::Str(op)) if op == "subscribe" => {
                        host.subscribe(&key)?;
                    }
                    _ => return Err(AppError::new(Status::InvalidParameter, "op")),
                }
                Ok(Value::Null)
            }
            _ => Err(AppError::new(Status::NotSupported, action)),
        }
    }

    fn on_timer(&mut self, host: &mut dyn Host, _timer: TimerId) {
        if std::mem::take(&mut self.late) {
            std::thread::sleep(Duration::from_secs(3));
            let _ = host.store_put("late", &[1]);
            return;
        }
        self.ticks += 1;
        host.update("ticks", sample(Value::UInt(self.ticks)));
    }

    fn on_value(&mut self, host: &mut dyn Host, _sub: SubId, _key: &str, s: Sample) {
        host.update("seen", sample(s.v));
    }

    fn on_reply(&mut self, host: &mut dyn Host, _req: ReqId, result: Result<Value, AppError>) {
        let text = match result {
            Ok(_) => "ok".to_owned(),
            Err(e) => e.status.name().to_owned(),
        };
        host.update("reply", sample(Value::Str(text)));
    }
}

static DOOMED_STARTS: AtomicU32 = AtomicU32::new(0);

/// An app that panics in every `start`.
struct Doomed;

impl App for Doomed {
    const NAME: &'static str = "doomed";
    const VERSION: &'static str = "0.1.0";

    fn start(_host: &mut dyn Host, _config: Value) -> Result<Self, AppError> {
        DOOMED_STARTS.fetch_add(1, Ordering::SeqCst);
        panic!("never starts");
    }

    fn on_set(&mut self, _: &mut dyn Host, _: &str, _: Value, _: &Who) -> Result<(), AppError> {
        Ok(())
    }

    fn on_invoke(
        &mut self,
        _: &mut dyn Host,
        _: &str,
        _: &str,
        _: Value,
        _: &Who,
    ) -> Result<Value, AppError> {
        Ok(Value::Null)
    }
}

fn data_dir(name: &str) -> PathBuf {
    let d = std::env::temp_dir().join(format!(
        "wyrm-portable-{name}-{}-{}",
        std::process::id(),
        wyrm_link_sdk::now_us()
    ));
    let _ = std::fs::remove_dir_all(&d);
    std::fs::create_dir_all(&d).unwrap();
    d
}

fn config(params: &[(&str, Value)]) -> PortableConfig {
    let m: BTreeMap<String, Value> = params
        .iter()
        .map(|(k, v)| ((*k).to_owned(), v.clone()))
        .collect();
    PortableConfig::from_params(&Value::Map(m)).expect("config")
}

async fn start<A: App + Send + 'static>(
    cfg: PortableConfig,
    dir: &std::path::Path,
    grants: Vec<(String, Perm)>,
) -> TestHarness<Portable<A>> {
    let dir = dir.to_path_buf();
    TestHarness::<Portable<A>>::start_with(cfg, move |c| {
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

fn root_attr<A: App + Send + 'static>(h: &TestHarness<Portable<A>>, name: &str) -> Option<Value> {
    h.ctx().meta("").and_then(|m| m.attr_value(name).cloned())
}

fn last<A: App + Send + 'static>(h: &TestHarness<Portable<A>>, path: &str) -> Option<Value> {
    h.ctx().last(path).map(|s| s.v)
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

#[tokio::test(flavor = "multi_thread")]
async fn tree_set_invoke_timer() {
    let dir = data_dir("tree");
    let h = start::<Echo>(config(&[]), &dir, Vec::new()).await;

    let (_, root) = h.meta("").await;
    let root = root.expect("root meta");
    let children = root.children.clone().unwrap_or_default();
    assert!(children.contains(&"n".to_owned()), "{children:?}");
    assert!(children.contains(&"ticks".to_owned()), "{children:?}");
    assert!(root
        .actions
        .as_ref()
        .is_some_and(|a| a.contains_key("ping")));
    assert_eq!(root_attr(&h, "status"), Some(str_v("running")));

    let att = h.set("n", 5i64, Some(h.ptok(Perm::Write))).await;
    assert_eq!(status(&att), Status::Ok, "{:?}", att.err);
    assert_eq!(last(&h, "n").and_then(|v| v.as_f64()), Some(5.0));

    let r = h
        .invoke(
            "",
            "ping",
            Value::Map(BTreeMap::new()),
            Some(h.ptok(Perm::Write)),
        )
        .await;
    assert_eq!(r.len(), 1);
    assert_eq!(r[0].value(), Some(str_v("pong")), "{:?}", r[0].att);
    assert!(
        eventually(Duration::from_millis(500), || last(&h, "ticks")
            .and_then(|v| v.as_f64())
            == Some(1.0))
        .await,
        "ticks: {:?}",
        last(&h, "ticks")
    );
    h.stop().await;
    let _ = std::fs::remove_dir_all(&dir);
}

#[tokio::test(flavor = "multi_thread")]
async fn store_survives_restart_and_quota_holds() {
    let dir = data_dir("store");
    let h = start::<Echo>(config(&[]), &dir, Vec::new()).await;
    let att = h.set("n", 7i64, Some(h.ptok(Perm::Write))).await;
    assert_eq!(status(&att), Status::Ok, "{:?}", att.err);
    h.stop().await;

    let h = start::<Echo>(config(&[]), &dir, Vec::new()).await;
    assert_eq!(last(&h, "n").and_then(|v| v.as_f64()), Some(7.0));
    h.stop().await;

    let full = data_dir("store-full");
    let h = start::<Echo>(config(&[("store_mb", Value::UInt(0))]), &full, Vec::new()).await;
    let att = h.set("n", 7i64, Some(h.ptok(Perm::Write))).await;
    assert_eq!(status(&att), Status::ResourceExhausted, "{:?}", att.err);
    // a refused `store_put` is an app error, not a fault: the link keeps running
    assert_eq!(root_attr(&h, "status"), Some(str_v("running")));
    h.stop().await;
    let _ = std::fs::remove_dir_all(&dir);
    let _ = std::fs::remove_dir_all(&full);
}

#[tokio::test(flavor = "multi_thread")]
async fn panic_restarts_with_backoff_and_sweeps() {
    let dir = data_dir("panic");
    let h = start::<Echo>(config(&[("extra", Value::Bool(true))]), &dir, Vec::new()).await;
    assert!(h.ctx().has_node("extra"));
    let att = h.set("n", 7i64, Some(h.ptok(Perm::Write))).await;
    assert_eq!(status(&att), Status::Ok, "{:?}", att.err);

    let att = h.set("n", -1i64, Some(h.ptok(Perm::Write))).await;
    assert!(status(&att).is_error(), "{att:?}");
    assert!(
        eventually(Duration::from_millis(500), || root_attr(&h, "status")
            == Some(str_v("restarting")))
        .await
    );
    assert!(matches!(root_attr(&h, "error"), Some(Value::Str(e)) if e.contains("asked to fail")));
    // marked before the status changed
    assert_eq!(h.ctx().last("n").expect("n").q, Quality::Bad);
    // the old values stay, marked bad, until the new instance publishes again
    assert!(
        eventually(Duration::from_secs(3), || root_attr(&h, "status")
            == Some(str_v("running")))
        .await,
        "status: {:?}",
        root_attr(&h, "status")
    );
    let n = h.ctx().last("n").expect("n");
    assert_eq!(n.v.as_f64(), Some(7.0));
    assert_eq!(n.q, Quality::Good);
    // `extra` was not declared again: it goes after the 10 s window
    assert!(h.ctx().has_node("extra"));
    assert!(
        eventually(Duration::from_secs(12), || !h.ctx().has_node("extra")).await,
        "extra was not swept"
    );
    assert!(h.ctx().has_node("n"));
    h.stop().await;
    let _ = std::fs::remove_dir_all(&dir);
}

#[tokio::test(flavor = "multi_thread")]
async fn panic_in_start_backs_off() {
    let dir = data_dir("doomed");
    let h = start::<Doomed>(config(&[]), &dir, Vec::new()).await;
    tokio::time::sleep(Duration::from_secs(4)).await;
    let n = DOOMED_STARTS.load(Ordering::SeqCst);
    assert!((2..=3).contains(&n), "{n} starts in 4 s");
    assert_eq!(root_attr(&h, "status"), Some(str_v("restarting")));
    // the broker side answers
    let (att, meta) = h.meta("").await;
    assert_eq!(status(&att), Status::Ok);
    assert!(meta.is_some());
    assert!(matches!(root_attr(&h, "error"), Some(Value::Str(e)) if e.contains("never starts")));
    h.stop().await;
    let _ = std::fs::remove_dir_all(&dir);
}

/// A link that records what is written to its point `p`.
struct Sink {
    got: Arc<Mutex<Vec<Value>>>,
}

static SINK_GOT: Mutex<Option<Arc<Mutex<Vec<Value>>>>> = Mutex::new(None);

impl Link for Sink {
    const NAME: &'static str = "sink";
    const VERSION: &'static str = "0.1.0";
    type Config = ();

    async fn start(_cfg: (), ctx: LinkCtx) -> wyrm_link_sdk::Result<Self> {
        ctx.declare_node(
            "p",
            NodeMeta::number().writable(wyrm_core::meta::Writable::Write),
        )
        .await?;
        ctx.update("p", 42u64, Quality::Good, wyrm_link_sdk::now_us())
            .await?;
        let got = SINK_GOT.lock().unwrap().clone().expect("sink recorder set");
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

#[tokio::test(flavor = "multi_thread")]
async fn requests_outside_grants_are_refused() {
    let dir = data_dir("grants");
    let mock = format!("wy/{SITE}/downstream/mock");
    let h = start::<Echo>(config(&[]), &dir, vec![(format!("{mock}/**"), Perm::Write)]).await;

    let got = Arc::new(Mutex::new(Vec::new()));
    *SINK_GOT.lock().unwrap() = Some(got.clone());
    let mut lcfg = LinkConfig::new(SITE, "mock");
    lcfg.admin_keys = vec![SigningKey::from_bytes(&TEST_KEY_SEED).verifying_key()];
    // `get ~val` answers the current value (no storage in the harness)
    lcfg.answer_val = true;
    let sink = runtime::spawn::<Sink>(h.session().clone(), lcfg, ())
        .await
        .expect("sink");

    let call = |op: &str, key: &str| {
        let mut m = BTreeMap::new();
        m.insert("op".to_owned(), str_v(op));
        m.insert("key".to_owned(), str_v(key));
        m.insert("value".to_owned(), Value::UInt(1));
        Value::Map(m)
    };

    let r = h
        .invoke(
            "",
            "call",
            call("set", &format!("{mock}/p")),
            Some(h.ptok(Perm::Write)),
        )
        .await;
    assert_eq!(r.len(), 1);
    assert_eq!(status(&r[0].att), Status::Ok, "{:?}", r[0].att.err);
    assert!(
        eventually(Duration::from_secs(3), || got
            .lock()
            .unwrap()
            .iter()
            .any(|v| v.as_f64() == Some(1.0)))
        .await,
        "the set did not reach the mock link"
    );
    assert!(
        eventually(Duration::from_secs(3), || last(&h, "reply")
            == Some(str_v("ok")))
        .await,
        "reply: {:?}",
        last(&h, "reply")
    );

    // inside the grant: the first value is the point's current one
    let r = h
        .invoke(
            "",
            "call",
            call("subscribe", &format!("{mock}/p")),
            Some(h.ptok(Perm::Write)),
        )
        .await;
    assert_eq!(status(&r[0].att), Status::Ok, "{:?}", r[0].att.err);
    assert!(
        eventually(Duration::from_secs(3), || last(&h, "seen")
            .and_then(|v| v.as_f64())
            == Some(42.0))
        .await,
        "seen: {:?}",
        last(&h, "seen")
    );

    // outside the grant (same site), and in another site
    for (op, key) in [
        ("set", format!("wy/{SITE}/downstream/other/p")),
        ("subscribe", format!("wy/{SITE}/downstream/other/p")),
        ("subscribe", "wy/x/downstream/mock/p".to_owned()),
    ] {
        let r = h
            .invoke("", "call", call(op, &key), Some(h.ptok(Perm::Write)))
            .await;
        assert_eq!(r.len(), 1);
        assert_eq!(status(&r[0].att), Status::PermissionDenied, "{op} {key}");
    }
    assert_eq!(got.lock().unwrap().len(), 1);

    sink.stop().await;
    h.stop().await;
    let _ = std::fs::remove_dir_all(&dir);
}

fn empty() -> Value {
    Value::Map(BTreeMap::new())
}

#[tokio::test(flavor = "multi_thread")]
async fn a_cancelled_timer_is_not_delivered() {
    let dir = data_dir("cancel");
    let h = start::<Echo>(config(&[]), &dir, Vec::new()).await;
    let r = h
        .invoke("", "arm", empty(), Some(h.ptok(Perm::Write)))
        .await;
    assert_eq!(status(&r[0].att), Status::Ok, "{:?}", r[0].att.err);
    // the timer fires (and is queued) while this event runs; the event then cancels it
    let r = h
        .invoke("", "slow_cancel", empty(), Some(h.ptok(Perm::Write)))
        .await;
    assert_eq!(status(&r[0].att), Status::Ok, "{:?}", r[0].att.err);
    tokio::time::sleep(Duration::from_millis(500)).await;
    assert_eq!(last(&h, "ticks"), None);
    h.stop().await;
    let _ = std::fs::remove_dir_all(&dir);
}

#[tokio::test(flavor = "multi_thread")]
async fn a_store_write_after_stop_gave_up_is_refused() {
    let dir = data_dir("late");
    let h = start::<Echo>(config(&[]), &dir, Vec::new()).await;
    let r = h
        .invoke("", "late", empty(), Some(h.ptok(Perm::Write)))
        .await;
    assert_eq!(status(&r[0].att), Status::Ok, "{:?}", r[0].att.err);
    // `on_timer` now runs for 3 s; stop waits 2 s for it, then gives the call up
    tokio::time::sleep(Duration::from_millis(200)).await;
    let t = Instant::now();
    h.stop().await;
    assert!(
        t.elapsed() < Duration::from_millis(2900),
        "{:?}",
        t.elapsed()
    );
    tokio::time::sleep(Duration::from_secs(2)).await;
    let store = wyrm_link_portable::store::Store::open(Some(&dir), Some(&STORE_KEY));
    assert_eq!(store.get("late"), None);
    let _ = std::fs::remove_dir_all(&dir);
}

/// I2: the SDK's bound on a call is raised to `call_ms` + 1 s, so a call shorter than `call_ms`
/// is not answered `timeout` (here the host's own bound is 300 ms).
#[tokio::test(flavor = "multi_thread")]
async fn the_call_bound_covers_call_ms() {
    let dir = data_dir("callbound");
    let cfg = config(&[("call_ms", Value::UInt(1000))]);
    let d = dir.clone();
    let h = TestHarness::<Portable<Echo>>::start_with(cfg, move |c| {
        c.data_dir = Some(d);
        c.secrets
            .insert(".store_key", Secret::new(STORE_KEY.to_vec()));
        c.driver_timeout = Duration::from_millis(300);
    })
    .await;
    let r = h
        .invoke("", "sleep", empty(), Some(h.ptok(Perm::Write)))
        .await;
    assert_eq!(status(&r[0].att), Status::Ok, "{:?}", r[0].att.err);
    assert_eq!(r[0].value(), Some(str_v("awake")));
    h.stop().await;
    let _ = std::fs::remove_dir_all(&dir);
}

/// I2: a request that waits in the queue until its caller got `timeout` is dropped, not run
/// later (a retry would run it twice).
#[tokio::test(flavor = "multi_thread")]
async fn a_request_that_timed_out_in_the_queue_is_not_run() {
    let dir = data_dir("dropped");
    // the SDK's bound: max(200 ms, call_ms 1 + 1 s) = about 1 s
    let cfg = config(&[("call_ms", Value::UInt(1))]);
    let d = dir.clone();
    let h = TestHarness::<Portable<Echo>>::start_with(cfg, move |c| {
        c.data_dir = Some(d);
        c.secrets
            .insert(".store_key", Secret::new(STORE_KEY.to_vec()));
        c.driver_timeout = Duration::from_millis(200);
    })
    .await;
    let r = h
        .invoke("", "late", empty(), Some(h.ptok(Perm::Write)))
        .await;
    assert_eq!(status(&r[0].att), Status::Ok, "{:?}", r[0].att.err);
    // `on_timer` now holds the engine for 3 s; this set waits behind it and times out
    tokio::time::sleep(Duration::from_millis(100)).await;
    let t = Instant::now();
    let att = h.set("n", 5i64, Some(h.ptok(Perm::Write))).await;
    assert_eq!(status(&att), Status::Timeout, "{:?}", att.err);
    assert!(
        t.elapsed() < Duration::from_millis(2500),
        "{:?}",
        t.elapsed()
    );
    // the timer event ends; the set is not run after it
    tokio::time::sleep(Duration::from_millis(3000)).await;
    assert_eq!(last(&h, "n"), None);
    // the link still answers
    let att = h.set("n", 6i64, Some(h.ptok(Perm::Write))).await;
    assert_eq!(status(&att), Status::Ok, "{:?}", att.err);
    h.stop().await;
    let store = wyrm_link_portable::store::Store::open(Some(&dir), Some(&STORE_KEY));
    let n: Value = wyrm_core::codec::from_slice(&store.get("n").expect("n stored")).unwrap();
    assert_eq!(n.as_f64(), Some(6.0));
    let _ = std::fs::remove_dir_all(&dir);
}

/// I2 (round 2): a request that waited in the queue longer than the margin could run past the
/// SDK's bound; it is answered `timeout` by the link and not run, even when the SDK itself
/// would wait longer.
#[tokio::test(flavor = "multi_thread")]
async fn a_request_that_waited_past_the_margin_is_answered_timeout() {
    let dir = data_dir("late-dequeue");
    let cfg = config(&[("call_ms", Value::UInt(1))]);
    let d = dir.clone();
    let h = TestHarness::<Portable<Echo>>::start_with(cfg, move |c| {
        c.data_dir = Some(d);
        c.secrets
            .insert(".store_key", Secret::new(STORE_KEY.to_vec()));
        // the SDK waits 10 s: only the link's own rule can answer earlier
        c.driver_timeout = Duration::from_secs(10);
    })
    .await;
    let r = h
        .invoke("", "late", empty(), Some(h.ptok(Perm::Write)))
        .await;
    assert_eq!(status(&r[0].att), Status::Ok, "{:?}", r[0].att.err);
    tokio::time::sleep(Duration::from_millis(100)).await;
    let t = Instant::now();
    let att = h.set("n", 5i64, Some(h.ptok(Perm::Write))).await;
    assert_eq!(status(&att), Status::Timeout, "{:?}", att.err);
    // answered when the 3 s timer event ended, by the link (the SDK would wait 10 s)
    let waited = t.elapsed();
    assert!(
        waited > Duration::from_millis(2000) && waited < Duration::from_secs(5),
        "{waited:?}"
    );
    tokio::time::sleep(Duration::from_millis(300)).await;
    assert_eq!(last(&h, "n"), None);
    h.stop().await;
    let store = wyrm_link_portable::store::Store::open(Some(&dir), Some(&STORE_KEY));
    assert_eq!(store.get("n"), None);
    let _ = std::fs::remove_dir_all(&dir);
}

/// I2 (round 2): an `invoke` that the SDK answered `timeout` while it waited in the SDK's own
/// queue (behind a 2 s call) is not run by the link.
#[tokio::test(flavor = "multi_thread")]
async fn an_invoke_that_timed_out_in_the_sdk_queue_is_not_run() {
    let dir = data_dir("sdk-queue");
    // the SDK's bound: max(200 ms, call_ms 1 + 1 s) = about 1 s
    let cfg = config(&[("call_ms", Value::UInt(1))]);
    let d = dir.clone();
    let h = TestHarness::<Portable<Echo>>::start_with(cfg, move |c| {
        c.data_dir = Some(d);
        c.secrets
            .insert(".store_key", Secret::new(STORE_KEY.to_vec()));
        c.driver_timeout = Duration::from_millis(200);
    })
    .await;
    let (nap, ping) = tokio::join!(
        h.invoke("", "nap", empty(), Some(h.ptok(Perm::Write))),
        async {
            // behind `nap` in the SDK's queue
            tokio::time::sleep(Duration::from_millis(100)).await;
            h.invoke("", "ping", empty(), Some(h.ptok(Perm::Write)))
                .await
        }
    );
    assert_eq!(status(&nap[0].att), Status::Timeout, "{:?}", nap[0].att.err);
    assert_eq!(
        status(&ping[0].att),
        Status::Timeout,
        "{:?}",
        ping[0].att.err
    );
    // `nap` ends at 2 s; `ping` (a 50 ms timer, then `ticks`) never ran
    tokio::time::sleep(Duration::from_millis(2500)).await;
    assert_eq!(last(&h, "ticks"), None);
    // the link answers again
    let r = h
        .invoke("", "ping", empty(), Some(h.ptok(Perm::Write)))
        .await;
    assert_eq!(r[0].value(), Some(str_v("pong")), "{:?}", r[0].att);
    assert!(
        eventually(Duration::from_millis(500), || last(&h, "ticks").is_some()).await,
        "ticks after the last ping"
    );
    h.stop().await;
    let _ = std::fs::remove_dir_all(&dir);
}

/// M5: at most 64 actions on one node; the event that declares more fails as a whole.
#[tokio::test(flavor = "multi_thread")]
async fn actions_per_node_are_bounded() {
    let dir = data_dir("actions");
    let h = start::<Echo>(config(&[]), &dir, Vec::new()).await;
    let n = |n: u64| Value::Map(BTreeMap::from([("n".to_owned(), Value::UInt(n))]));
    let own = h
        .ctx()
        .meta("")
        .and_then(|m| m.actions)
        .map_or(0, |a| a.len());
    let room = (wyrm_link_api::buffer::MAX_ACTIONS - own) as u64;
    let r = h
        .invoke("", "actions", n(room), Some(h.ptok(Perm::Write)))
        .await;
    assert_eq!(status(&r[0].att), Status::Ok, "{:?}", r[0].att.err);
    // re-declares add nothing
    let r = h
        .invoke("", "actions", n(room), Some(h.ptok(Perm::Write)))
        .await;
    assert_eq!(status(&r[0].att), Status::Ok, "{:?}", r[0].att.err);
    let r = h
        .invoke("", "actions", n(room + 1), Some(h.ptok(Perm::Write)))
        .await;
    assert_eq!(
        status(&r[0].att),
        Status::ResourceExhausted,
        "{:?}",
        r[0].att.err
    );
    let actions = h
        .ctx()
        .meta("")
        .and_then(|m| m.actions)
        .map_or(0, |a| a.len());
    assert_eq!(actions, wyrm_link_api::buffer::MAX_ACTIONS);
    h.stop().await;
    let _ = std::fs::remove_dir_all(&dir);
}
