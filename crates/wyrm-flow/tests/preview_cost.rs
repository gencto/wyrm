//! What one preview costs (ADR 0038 §5): live heap bytes per node and the time to the first
//! row, for a draft of `n` nodes in a chain. Not a check: run it by hand and copy the figures
//! into the ADR.
//!
//! `cargo test -p wyrm-flow --release --test preview_cost -- --ignored --nocapture`

use std::alloc::{GlobalAlloc, Layout, System};
use std::sync::atomic::{AtomicIsize, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};
use wyrm_client::{SigningTokens, WyrmClient};
use wyrm_core::Value;
use wyrm_flow::{Engine, EngineStart, FlowHost};
use wyrm_link_sdk::harness::{isolated_config, TEST_KEY_SEED};
use wyrm_link_sdk::LinkConfig;

/// Bytes allocated and not freed yet.
struct Counting;

static LIVE: AtomicIsize = AtomicIsize::new(0);

unsafe impl GlobalAlloc for Counting {
    unsafe fn alloc(&self, l: Layout) -> *mut u8 {
        LIVE.fetch_add(l.size() as isize, Ordering::Relaxed);
        unsafe { System.alloc(l) }
    }
    unsafe fn dealloc(&self, p: *mut u8, l: Layout) {
        LIVE.fetch_sub(l.size() as isize, Ordering::Relaxed);
        unsafe { System.dealloc(p, l) }
    }
}

#[global_allocator]
static A: Counting = Counting;

const SITE: &str = "test";

fn map(kv: Vec<(String, Value)>) -> Value {
    Value::Map(kv.into_iter().collect())
}

/// A `bool` variable and `n - 1` `not` blocks in a chain: the start value runs through all.
fn chain(n: usize) -> Value {
    let node = |ty: &str| map(vec![("type".into(), Value::from(ty))]);
    let mut nodes = vec![("n0".to_owned(), node("bool"))];
    let mut edges = Vec::new();
    for i in 1..n {
        nodes.push((format!("n{i}"), node("not")));
        edges.push(Value::Array(vec![
            Value::from(format!("n{}.out", i - 1)),
            Value::from(format!("n{i}.in")),
        ]));
    }
    map(vec![
        ("id".into(), Value::from("cost")),
        ("nodes".into(), map(nodes)),
        ("edges".into(), Value::Array(edges)),
    ])
}

#[tokio::test(flavor = "multi_thread")]
#[ignore = "a measurement, run by hand"]
async fn preview_cost() {
    let dir = std::env::temp_dir().join(format!("wyrm-flow-cost-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    let session = zenoh::open(isolated_config()).await.unwrap();
    let key = ed25519_dalek::SigningKey::from_bytes(&TEST_KEY_SEED);
    let host = FlowHost::open(&dir, b"flow-test-hmac-key", SITE).unwrap();
    let mut lcfg = LinkConfig::new(SITE, "dataflows");
    lcfg.root = Some(format!("wy/{SITE}/dataflows"));
    lcfg.admin_keys = vec![key.verifying_key()];
    let engine = wyrm_link_sdk::spawn::<Engine>(
        session.clone(),
        lcfg,
        EngineStart {
            host,
            admin_keys: vec![key.verifying_key()],
            proof_keys: Vec::new(),
        },
    )
    .await
    .unwrap();
    let client = WyrmClient::new(session.clone())
        .with_tokens(Arc::new(SigningTokens::new(key, SITE)))
        .with_timeout(Duration::from_secs(30));
    let root = format!("wy/{SITE}/dataflows");
    for n in [10usize, 100, 1000] {
        let def = chain(n);
        tokio::time::sleep(Duration::from_millis(300)).await;
        let before = LIVE.load(Ordering::Relaxed);
        let t0 = Instant::now();
        let mut st = client
            .invoke(&root, "preview", map(vec![("def".into(), def)]))
            .await
            .unwrap();
        let first = st.next().await.unwrap().unwrap().unwrap();
        let to_first = t0.elapsed();
        let live = LIVE.load(Ordering::Relaxed) - before;
        let last = match &first {
            Value::Map(m) => match m.get("nodes") {
                Some(Value::Map(nodes)) => {
                    nodes.get(&format!("n{}", n - 1)).and_then(|x| match x {
                        Value::Map(x) => x.get("out").cloned(),
                        _ => None,
                    })
                }
                _ => None,
            },
            _ => None,
        };
        println!(
            "nodes {n:5}: first row {:7.1} ms, live heap {:8} B ({:6} B/node), last out {last:?}",
            to_first.as_secs_f64() * 1e3,
            live,
            live / n as isize,
        );
        drop(st);
        // a newer preview of the same subject ends this one: open the next one
    }
    engine.stop().await;
}
