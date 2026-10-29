//! The app on the native adapter (`Portable<Echo>`) in the SDK's test harness: `ping` and its
//! timer, `echo`, `set`, the store across a restart, bad params and `crash` with `faults`. The
//! same app runs embedded in `wyrmd`, as a process and as a WASM component with the same
//! behaviour (`crates/wyrmd/tests/e2e.rs` `one_app_three_modes`).

use std::collections::BTreeMap;
use std::path::Path;
use std::time::{Duration, Instant};

use wyrm_core::status::StatusCode;
use wyrm_core::{Perm, Status, Value};
use wyrm_link_portable::{Portable, PortableConfig};
use wyrm_link_sdk::harness::TestHarness;
use wyrm_link_sdk::params::FromParams;
use wyrm_link_sdk::Secret;

use wyrm_example_portable::Echo;

type Link = Portable<Echo>;

/// The link with `params` and its store in `dir` (a link's data directory and the key the
/// broker seals the store with).
async fn start(dir: &Path, params: Value) -> TestHarness<Link> {
    let dir = dir.to_path_buf();
    let cfg = PortableConfig::from_params(&params).expect("params");
    TestHarness::<Link>::start_with(cfg, move |c| {
        c.data_dir = Some(dir);
        c.secrets.insert(".store_key", Secret::new(vec![7; 32]));
    })
    .await
}

fn data_dir(name: &str) -> std::path::PathBuf {
    let d = std::env::temp_dir().join(format!(
        "wyrm-example-portable-{name}-{}",
        std::process::id()
    ));
    let _ = std::fs::remove_dir_all(&d);
    std::fs::create_dir_all(&d).unwrap();
    d
}

fn num(h: &TestHarness<Link>, path: &str) -> Option<f64> {
    h.ctx().last(path).and_then(|s| s.v.as_f64())
}

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

fn no_args() -> Value {
    Value::Map(BTreeMap::new())
}

#[tokio::test(flavor = "multi_thread")]
async fn ping_timer_set_and_store() {
    let dir = data_dir("store");
    let h = start(&dir, Value::Null).await;
    assert_eq!(num(&h, "starts"), Some(1.0));
    let r = h
        .invoke("", "ping", no_args(), Some(h.ptok(Perm::Write)))
        .await;
    assert_eq!(
        r[0].value(),
        Some(Value::Str("pong".into())),
        "{:?}",
        r[0].att
    );
    assert!(
        eventually(Duration::from_secs(2), || num(&h, "ticks") == Some(1.0)).await,
        "the ping timer fires once"
    );
    let value = Value::Map(BTreeMap::from([("x".to_owned(), Value::UInt(3))]));
    let args = Value::Map(BTreeMap::from([("value".to_owned(), value.clone())]));
    let r = h.invoke("", "echo", args, Some(h.ptok(Perm::Write))).await;
    assert_eq!(r[0].value(), Some(value));
    let att = h.set("n", 5i64, Some(h.ptok(Perm::Write))).await;
    assert_eq!(
        att.status,
        Some(StatusCode::Known(Status::Ok)),
        "{:?}",
        att.err
    );
    let att = h.set("n", "five", Some(h.ptok(Perm::Write))).await;
    assert_eq!(
        att.status,
        Some(StatusCode::Known(Status::InvalidParameter))
    );
    // without `faults` there is no crash
    let r = h
        .invoke("", "crash", no_args(), Some(h.ptok(Perm::Config)))
        .await;
    assert_ne!(r[0].att.status, Some(StatusCode::Known(Status::Ok)));
    h.stop().await;

    // a new start reads `n` and `starts` back from the store
    let h = start(&dir, Value::Null).await;
    assert_eq!(num(&h, "n"), Some(5.0));
    assert_eq!(num(&h, "starts"), Some(2.0));
    h.stop().await;
    let _ = std::fs::remove_dir_all(&dir);
}

#[tokio::test(flavor = "multi_thread")]
async fn crash_restarts_with_the_store() {
    let dir = data_dir("crash");
    let params = Value::Map(BTreeMap::from([("faults".to_owned(), Value::Bool(true))]));
    let h = start(&dir, params).await;
    let att = h.set("n", 8i64, Some(h.ptok(Perm::Write))).await;
    assert_eq!(
        att.status,
        Some(StatusCode::Known(Status::Ok)),
        "{:?}",
        att.err
    );
    let r = h
        .invoke("", "crash", no_args(), Some(h.ptok(Perm::Config)))
        .await;
    assert_ne!(r[0].att.status, Some(StatusCode::Known(Status::Ok)));
    // the host starts the app again after its backoff (1 s ± 20 %)
    assert!(
        eventually(Duration::from_secs(5), || num(&h, "starts") == Some(2.0)).await,
        "a new instance starts"
    );
    assert_eq!(num(&h, "n"), Some(8.0));
    h.stop().await;
    let _ = std::fs::remove_dir_all(&dir);
}

#[tokio::test(flavor = "multi_thread")]
async fn unknown_params_are_refused() {
    let dir = data_dir("params");
    let params = Value::Map(BTreeMap::from([("rate".to_owned(), Value::UInt(5))]));
    let h = start(&dir, params).await;
    // `start` failed: the app declared nothing, the root says why
    assert!(h.ctx().meta("n").is_none());
    let err = h
        .ctx()
        .meta("")
        .and_then(|m| m.attr_value("error").cloned());
    assert!(
        matches!(&err, Some(Value::Str(e)) if e.contains("params.rate")),
        "{err:?}"
    );
    h.stop().await;
    let _ = std::fs::remove_dir_all(&dir);
}
