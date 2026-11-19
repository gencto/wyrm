//! How many samples a flow carries (performance audit items 7–10): the engine on an
//! in-memory session, samples put on a source key by the test, the output counted at the
//! `publish` node. Not a check: run it by hand.
//!
//! `cargo test --release -p wyrm-flow --test throughput -- --ignored --nocapture`
//!
//! * `flow/chain/<h>/<keys>/q<queue>/at<rate>`: `subscribe → (scale → add) × … → publish`
//!   with `h` hops after the source; samples put at `rate` per second for 2 s, a ladder of
//!   rates that ends after the first step that lost samples. Samples per second at the
//!   output, `lost` = put − arrived, latency = arrival − the sample's `t`. `<keys>`: `key1`
//!   puts every sample on one key (the source's subscription keeps the latest sample per key,
//!   so a fast key is thinned by design); `keys1000` puts them on 1000 keys in turn under a
//!   `*` source. `q<queue>`: the flow's inbox (`policy.queue`; 64 is the default). The line
//!   without `at<rate>` names the fastest step that lost nothing (`lossless_per_s`).
//! * `flow/per_hop`: allocations and bytes per sample and hop, the difference of the chains
//!   of 9 and 3 hops over 6 at the same rate (the session, the client and the counter cost
//!   the same in both).
//! * `flow/table/<chain>`: a table of 10 000 rows (one number column, under the 512 KiB cap;
//!   each table differs from the one before) through `table_sort` once or three times (the
//!   per-hop figure is their difference), and through `table_filter` (a rhai expression per
//!   row) with `table_aggregate`, as a ladder of 2 … 50 tables per second.
//!
//! One `PERF` line per figure (`tool/perf.sh`).

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::unreachable,
    clippy::print_stdout,
    reason = "test code: a failed step fails the test"
)]

use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use wyrm_bench::{Allocs, Lat, Perf, Usage};
use wyrm_client::{SigningTokens, WyrmClient};
use wyrm_core::{Quality, Sample, Value};
use wyrm_flow::{Engine, EngineStart, FlowHost};
use wyrm_link_sdk::harness::{isolated_config, TEST_KEY_SEED};
use wyrm_link_sdk::{LinkConfig, LinkHandle};

#[global_allocator]
static A: wyrm_bench::Counting = wyrm_bench::Counting;

const SITE: &str = "test";
/// Different tables, put in turn.
const TABLES: u64 = 40;
const ROWS: u64 = 10_000;

fn map(kv: &[(&str, Value)]) -> Value {
    Value::Map(
        kv.iter()
            .map(|(k, v)| ((*k).to_owned(), v.clone()))
            .collect(),
    )
}

fn s(x: &str) -> Value {
    Value::from(x)
}

fn node(ty: &str, kv: &[(&str, Value)]) -> Value {
    let mut all = vec![("type", s(ty))];
    all.extend(kv.iter().cloned());
    map(&all)
}

/// A flow `id` from `source` through `mid` (in order) to a `publish` node `out`.
fn chain(id: &str, source: &str, mid: &[(String, Value)]) -> Value {
    let mut nodes: Vec<(String, Value)> =
        vec![("src".into(), node("subscribe", &[("key", s(source))]))];
    nodes.extend(mid.iter().cloned());
    nodes.push(("out".into(), node("publish", &[("node", s("out"))])));
    let names: Vec<&str> = nodes.iter().map(|(n, _)| n.as_str()).collect();
    let edges: Vec<Value> = names
        .windows(2)
        .map(|w| {
            let to = if nodes.iter().any(|(n, v)| {
                n == w[1] && matches!(v, Value::Map(m) if m.get("type") == Some(&s("add")))
            }) {
                format!("{}.in.0", w[1])
            } else {
                format!("{}.in", w[1])
            };
            Value::Array(vec![s(&format!("{}.out", w[0])), s(&to)])
        })
        .collect();
    let nodes: Vec<(&str, Value)> = nodes.iter().map(|(n, v)| (n.as_str(), v.clone())).collect();
    map(&[
        ("id", s(id)),
        ("version", Value::UInt(1)),
        ("nodes", map(&nodes)),
        ("edges", Value::Array(edges)),
        ("permissions", map(&[("maxperm", s("write"))])),
    ])
}

/// `def` with `policy.queue = queue` (the inbox of every node; default 64, drop_oldest).
fn with_queue(mut def: Value, queue: u64) -> Value {
    if let Value::Map(m) = &mut def {
        m.insert("policy".into(), map(&[("queue", Value::UInt(queue))]));
    }
    def
}

/// `def` with one more `publish` node `err` fed by `from` (an error port).
fn with_error_out(mut def: Value, from: &str) -> Value {
    if let Value::Map(m) = &mut def {
        if let Some(Value::Map(nodes)) = m.get_mut("nodes") {
            nodes.insert("err".into(), node("publish", &[("node", s("err"))]));
        }
        if let Some(Value::Array(edges)) = m.get_mut("edges") {
            edges.push(Value::Array(vec![s(from), s("err.in")]));
        }
    }
    def
}

/// `hops` middle nodes, `scale` and `add` in turn (`add` with a constant second input).
fn numbers(hops: usize) -> Vec<(String, Value)> {
    (0..hops)
        .map(|i| {
            if i % 2 == 0 {
                (
                    format!("m{i}"),
                    node(
                        "scale",
                        &[("k", Value::Float(1.0)), ("b", Value::Float(0.0))],
                    ),
                )
            } else {
                (
                    format!("m{i}"),
                    node("add", &[("values", map(&[("in.1", Value::UInt(0))]))]),
                )
            }
        })
        .collect()
}

struct Env {
    session: zenoh::Session,
    client: WyrmClient,
    engine: Option<LinkHandle<Engine>>,
}

impl Env {
    async fn start() -> Self {
        let dir = std::env::temp_dir().join(format!("wyrm-flow-tput-{}", std::process::id()));
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
        Self {
            session,
            client,
            engine: Some(engine),
        }
    }

    async fn deploy(&self, def: Value) {
        self.client
            .invoke_one(
                &format!("wy/{SITE}/dataflows"),
                "deploy",
                map(&[("def", def), ("proofs", Value::Map(Default::default()))]),
            )
            .await
            .unwrap();
    }

    async fn remove(&self, id: &str) {
        let _ = self
            .client
            .invoke_one(&format!("wy/{SITE}/dataflows/{id}"), "remove", map(&[]))
            .await;
    }

    async fn stop(mut self) {
        if let Some(e) = self.engine.take() {
            e.stop().await;
        }
    }
}

/// What arrived at a flow's `out` node.
#[derive(Default)]
struct Seen {
    n: AtomicU64,
    lat: Mutex<Lat>,
    last: Mutex<Option<Instant>>,
}

struct Run {
    sent: u64,
    got: u64,
    wall: Duration,
    lat: Lat,
    allocs: Allocs,
    cpu_pct: f64,
    rss: Option<u64>,
}

/// A number chain: `(label, hops, queue, key of the i-th sample, source pattern)`.
type Case<'a> = (
    &'a str,
    usize,
    Option<u64>,
    &'a dyn Fn(u64) -> String,
    &'a str,
);

/// One rate step: `per_s` samples a second for `secs`, made by `make(i)` (each differs from
/// the one before: an equal value is not sent on by every block).
struct Step {
    per_s: f64,
    secs: f64,
}

/// Deploy `def`, then for each step put its samples on `source` at its rate and wait until
/// the output stops growing for `quiet`. The ladder ends after the first step that lost
/// samples.
async fn run(
    env: &Env,
    id: &str,
    put_key: &dyn Fn(u64) -> String,
    def: Value,
    make: &dyn Fn(u64) -> Value,
    steps: &[Step],
    quiet: Duration,
) -> Vec<(f64, Run)> {
    env.deploy(def).await;
    let seen = Arc::new(Seen::default());
    let s2 = seen.clone();
    let sub = env
        .session
        .declare_subscriber(format!("wy/{SITE}/dataflows/{id}/nodes/out/~val"))
        .callback(move |smp| {
            let now = wyrm_core::clock::now_us();
            if let Ok(x) = wyrm_core::codec::from_slice::<Sample>(&smp.payload().to_bytes()) {
                s2.lat
                    .lock()
                    .unwrap()
                    .push_us(now.saturating_sub(x.t) as f64);
            }
            s2.n.fetch_add(1, Ordering::Relaxed);
            *s2.last.lock().unwrap() = Some(Instant::now());
        })
        .await
        .unwrap();
    let put = |i: u64, v: Vec<u8>| env.session.put(format!("wy/{SITE}/{}/~val", put_key(i)), v);
    let encode = |v: Value| {
        wyrm_core::codec::to_vec(&Sample {
            v,
            q: Quality::Good,
            t: wyrm_core::clock::now_us(),
        })
        .unwrap()
    };
    // the flow subscribes after its deploy answered: one sample through first
    let mut i = 0u64;
    let deadline = Instant::now() + Duration::from_secs(10);
    while seen.n.load(Ordering::Relaxed) == 0 {
        assert!(Instant::now() < deadline, "{id}: no output");
        put(i, encode(make(i))).await.unwrap();
        i += 1;
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
    tokio::time::sleep(Duration::from_millis(300)).await;
    let mut out = Vec::new();
    for step in steps {
        let count = (step.per_s * step.secs).round() as u64;
        let base = seen.n.load(Ordering::Relaxed);
        *seen.lat.lock().unwrap() = Lat::new();
        let u0 = Usage::read();
        let a0 = Allocs::read();
        let t0 = Instant::now();
        for k in 0..count {
            let due = t0 + Duration::from_secs_f64(k as f64 / step.per_s);
            if due > Instant::now() + Duration::from_millis(1) {
                tokio::time::sleep_until(due.into()).await;
            }
            put(i, encode(make(i))).await.unwrap();
            i += 1;
        }
        let sent_at = Instant::now();
        loop {
            tokio::time::sleep(Duration::from_millis(50)).await;
            let last = seen.last.lock().unwrap().unwrap_or(sent_at).max(sent_at);
            if seen.n.load(Ordering::Relaxed) - base >= count || last.elapsed() > quiet {
                break;
            }
        }
        let end = seen.last.lock().unwrap().unwrap_or(sent_at).max(sent_at);
        let allocs = Allocs::read().since(a0);
        let u1 = Usage::read();
        let got = seen.n.load(Ordering::Relaxed) - base;
        let lat = std::mem::take(&mut *seen.lat.lock().unwrap());
        let lost = got < count;
        out.push((
            step.per_s,
            Run {
                sent: count,
                got,
                wall: end.saturating_duration_since(t0),
                lat,
                allocs,
                cpu_pct: u1.cpu_pct_since(&u0),
                rss: u1.rss_bytes,
            },
        ));
        if lost {
            break;
        }
    }
    drop(sub);
    env.remove(id).await;
    out
}

/// One line per step, and `<name>` for the fastest step that lost nothing.
fn ladder(name: &str, runs: Vec<(f64, Run)>, note: &str) -> Vec<Run> {
    let mut best: Option<String> = None;
    let mut kept = Vec::new();
    for (rate, r) in runs {
        let lossless = r.got >= r.sent;
        let line_name = format!("{name}/at{rate:.0}");
        let r = report(&line_name, r, note);
        if lossless {
            best = Some(format!("{rate:.0}"));
        }
        kept.push(r);
    }
    println!(
        "{}",
        Perf::new(name)
            .field("lossless_per_s", best.as_deref().unwrap_or("none"))
            .note("highest step rate with every sample out")
    );
    kept
}

fn report(name: &str, mut r: Run, note: &str) -> Run {
    let ops = r.got.max(1);
    println!(
        "{}",
        Perf::new(name)
            .lat(&mut r.lat)
            .per_s(r.got as f64 / r.wall.as_secs_f64())
            .cpu_pct(r.cpu_pct)
            .rss(r.rss)
            .allocs(r.allocs, ops)
            .field("sent", r.sent)
            .field("lost", r.sent.saturating_sub(r.got))
            .note(note)
    );
    r
}

fn per_hop(name: &str, short: &Run, long: &Run, hops: u64, note: &str) {
    let per = |r: &Run| {
        let n = r.got.max(1) as f64;
        (r.allocs.calls as f64 / n, r.allocs.bytes as f64 / n)
    };
    let (sc, sb) = per(short);
    let (lc, lb) = per(long);
    println!(
        "{}",
        Perf::new(name)
            .allocs_op((lc - sc) / hops as f64, (lb - sb) / hops as f64)
            .note(note)
    );
}

/// A table of `rows` rows of one column `v`; `shift` makes each table differ.
fn table(rows: u64, shift: u64) -> Value {
    Value::Map(
        [
            ("columns".to_owned(), Value::Array(vec![s("v")])),
            (
                "rows".to_owned(),
                Value::Array(
                    (0..rows)
                        .map(|i| Value::Array(vec![Value::UInt((i * 7919) % rows + shift)]))
                        .collect(),
                ),
            ),
        ]
        .into_iter()
        .collect(),
    )
}

fn sorts(n: usize) -> Vec<(String, Value)> {
    (0..n)
        .map(|i| {
            (
                format!("t{i}"),
                node(
                    "table_sort",
                    &[
                        ("column", s("v")),
                        (
                            "order",
                            s(if i % 2 == 0 {
                                "descending"
                            } else {
                                "ascending"
                            }),
                        ),
                    ],
                ),
            )
        })
        .collect()
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
#[ignore = "a measurement, run by hand"]
async fn throughput() {
    let env = Env::start().await;
    let num = |i: u64| Value::Float(i as f64);
    let steps: Vec<Step> = [2_000.0, 5_000.0, 10_000.0, 20_000.0, 50_000.0, 100_000.0]
        .into_iter()
        .map(|per_s| Step { per_s, secs: 2.0 })
        .collect();
    let mut chains = Vec::new();
    // One key: the source's subscription keeps the latest sample per key (wyrm-client
    // `Policy::Latest`), so a fast key is thinned by design. 1000 keys in turn: what the
    // engine carries, with the default inbox (64, drop_oldest) and a deep one.
    let one = |_: u64| "downstream/src/p0".to_owned();
    let many = |i: u64| format!("downstream/src/k{}", i % 1000);
    let cases: [Case; 4] = [
        ("key1", 3, None, &one, "downstream/src/p0"),
        ("keys1000", 3, None, &many, "downstream/src/*"),
        ("keys1000", 3, Some(65_536), &many, "downstream/src/*"),
        ("keys1000", 9, Some(65_536), &many, "downstream/src/*"),
    ];
    for (keys, hops, queue, put_key, pattern) in cases {
        let q = queue.unwrap_or(64);
        let id = format!("c{hops}{keys}q{q}");
        let mut def = chain(&id, pattern, &numbers(hops));
        if let Some(q) = queue {
            def = with_queue(def, q);
        }
        let runs = run(
            &env,
            &id,
            put_key,
            def,
            &num,
            &steps,
            Duration::from_secs(1),
        )
        .await;
        chains.push(ladder(
            &format!("flow/chain/{hops}/{keys}/q{q}"),
            runs,
            "subscribe->(scale,add)xN->publish, paced",
        ));
    }
    // the first step (same rate) of both chains
    per_hop(
        "flow/per_hop",
        &chains[2][0],
        &chains[3][0],
        6,
        "allocations per sample and hop: chain 9 minus chain 3, over 6, at 2000/s",
    );

    let tables: Vec<Value> = (0..TABLES).map(|i| table(ROWS, i)).collect();
    let tab = |i: u64| tables[(i % TABLES) as usize].clone();
    let tkey = |_: u64| "downstream/src/t".to_owned();
    let tsteps: Vec<Step> = [2.0, 5.0, 10.0, 20.0, 50.0]
        .into_iter()
        .map(|per_s| Step { per_s, secs: 4.0 })
        .collect();
    let mut sorted = Vec::new();
    for n in [1usize, 3] {
        let id = format!("ts{n}");
        let def = chain(&id, "downstream/src/t", &sorts(n));
        let runs = run(&env, &id, &tkey, def, &tab, &tsteps, Duration::from_secs(3)).await;
        sorted.push(ladder(
            &format!("flow/table/sort{n}"),
            runs,
            "10000-row table through table_sort, paced",
        ));
    }
    per_hop(
        "flow/table/per_hop",
        &sorted[0][0],
        &sorted[1][0],
        2,
        "allocations per 10000-row table and table_sort hop: 3 sorts minus 1, over 2, at 2/s",
    );
    let filter = vec![
        (
            "f".to_owned(),
            node("table_filter", &[("expr", s("row.v % 2 == 0"))]),
        ),
        (
            "agg".to_owned(),
            node(
                "table_aggregate",
                &[("column", s("v")), ("method", s("sum"))],
            ),
        ),
    ];
    // a failed script (its 100 ms CPU budget per table, spec 06) leaves by `error`
    let def = with_error_out(chain("tf", "downstream/src/t", &filter), "f.error");
    let errors = Arc::new(AtomicU64::new(0));
    let e2 = errors.clone();
    let err_sub = env
        .session
        .declare_subscriber(format!("wy/{SITE}/dataflows/tf/nodes/err/~val"))
        .callback(move |_| {
            e2.fetch_add(1, Ordering::Relaxed);
        })
        .await
        .unwrap();
    let runs = run(
        &env,
        "tf",
        &tkey,
        def,
        &tab,
        &tsteps,
        Duration::from_secs(3),
    )
    .await;
    ladder(
        "flow/table/filter_sum",
        runs,
        "10000-row table through table_filter (rhai per row) and table_aggregate, paced",
    );
    drop(err_sub);
    println!(
        "{}",
        Perf::new("flow/table/filter_errors")
            .n(errors.load(Ordering::Relaxed))
            .note("table_filter error outputs over the whole ladder (script budget or failure)")
    );
    env.stop().await;
}
