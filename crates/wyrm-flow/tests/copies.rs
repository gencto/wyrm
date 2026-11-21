//! What one sample costs inside the flow runtime (performance slice "flow copies",
//! `docs/backlog.md` §14): the runtime started directly ([`wyrm_flow::runtime::start`]),
//! samples pushed into the first node's inbox, the end read from the flow's own counters.
//! No session carries a sample and no `publish` node encodes one, so the figures are the
//! runtime's and the blocks' alone. Not a check: run it by hand.
//!
//! `cargo test --release -p wyrm-flow --test copies -- --ignored --nocapture`
//!
//! * `flow/copies/chain10`: 10 pure blocks in a chain (`add` with a constant and `multiply`
//!   in turn), a new number in every sample.
//! * `flow/copies/fanout16`: one `add` whose output has 16 edges, each into an `abs`.
//! * `flow/copies/rhai`: one `expression` (`x.v * 2.0 + 1.0`).
//! * `flow/copies/table3`: a table of 1000 rows of three cells (a number, a float, a text)
//!   through three `table_sort` blocks; each table differs from the one before.
//! * `flow/copies/hub3`: the same tables through three `hub` blocks, which pass a value on as
//!   it is.
//! * `flow/copies/table_fanout4`: the same tables through one `table_sort` whose output has 4
//!   edges, each into a `hub`.
//! * `flow/copies/table_copy`: what one `Value::clone` of such a table allocates; the table
//!   cases give `copies`, their allocations per table over it (about how many times a table was
//!   copied on its way, the copy a block parses included).
//!
//! Every case runs [`ROUNDS`] times; the line gives the median round: samples per second
//! (the first node's samples from the first push to the last node's last input), CPU time
//! of the whole process per sample (`cpu_us`), allocations and bytes per sample (the
//! counting allocator; the samples are built before the round). `per_s_min`/`per_s_max`
//! are the slowest and the fastest round. The allocation counts do not move with the
//! machine's load; the rates do.
//!
//! One `PERF` line per figure (`tool/perf.sh`).
//!
//! One check runs with the other tests: `a_number_through_ten_blocks_allocates_next_to_nothing`.
//! It writes its `PERF` line (`flow/copies/check`) to stderr past the harness's capture, so a
//! passing run shows it in the CI log.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::unreachable,
    clippy::print_stdout,
    reason = "test code: a failed step fails the test"
)]

use std::collections::BTreeMap;
use std::io::Write as _;
use std::sync::atomic::Ordering;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::mpsc;
use wyrm_bench::{Allocs, Perf, Usage};
use wyrm_client::WyrmClient;
use wyrm_core::{Quality, Value};
use wyrm_flow::nodes::{Io, Mode, Msg};
use wyrm_flow::runtime::{self, FlowStats};
use wyrm_flow::watch::Probe;
use wyrm_link_mock::{Mock, MockConfig};
use wyrm_link_sdk::harness::isolated_config;
use wyrm_link_sdk::{LinkConfig, LinkCtx, LinkHandle};

#[global_allocator]
static A: wyrm_bench::Counting = wyrm_bench::Counting;

const ROUNDS: usize = 7;
const ROWS: u64 = 1000;

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

fn edge(from: &str, to: &str) -> Value {
    Value::Array(vec![s(from), s(to)])
}

/// A flow of `nodes` and `edges` whose inboxes hold `queue` samples.
fn flow(id: &str, nodes: Vec<(String, Value)>, edges: Vec<Value>, queue: u64) -> Value {
    let nodes: Vec<(&str, Value)> = nodes.iter().map(|(n, v)| (n.as_str(), v.clone())).collect();
    map(&[
        ("id", s(id)),
        ("version", Value::UInt(1)),
        ("nodes", map(&nodes)),
        ("edges", Value::Array(edges)),
        ("policy", map(&[("queue", Value::UInt(queue))])),
    ])
}

fn add_one() -> Value {
    node("add", &[("values", map(&[("in.1", Value::UInt(1))]))])
}

struct Env {
    ctx: LinkCtx,
    client: WyrmClient,
    _h: LinkHandle<Mock>,
}

async fn env() -> Env {
    let session = zenoh::open(isolated_config()).await.unwrap();
    let h = wyrm_link_sdk::spawn::<Mock>(
        session.clone(),
        LinkConfig::new("test", "m"),
        MockConfig {
            points: 1,
            rate_hz: 0.0,
            depth: 0,
            fanout: 1,
            writable: false,
        },
    )
    .await
    .unwrap();
    Env {
        ctx: h.ctx().clone(),
        client: WyrmClient::new(session),
        _h: h,
    }
}

struct Round {
    per_s: f64,
    cpu_us: f64,
    allocs: f64,
    bytes: f64,
}

/// One case: `def` started once, then [`ROUNDS`] rounds of `count` samples made by `make`
/// and pushed on port `port` of node `first`; a round ends when the nodes took in
/// `count × inputs_per_sample` more samples.
struct Case<'a> {
    name: &'a str,
    def: &'a Value,
    first: &'a str,
    port: &'a str,
    inputs_per_sample: u64,
    count: u64,
    make: &'a dyn Fn(u64) -> Value,
    note: &'a str,
    /// Allocations of one copy of the sample's value: the line then gives `copies`, the
    /// allocations per sample over it (about how many times the value was copied).
    copy_allocs: Option<f64>,
}

/// The rounds of `c`, each measured.
async fn measure(env: &Env, c: &Case<'_>, rounds: usize) -> Vec<Round> {
    let Case {
        name,
        def,
        first,
        port,
        inputs_per_sample,
        count,
        make,
        ..
    } = *c;
    let (def, ports) = wyrm_flow::def::compile(def).unwrap();
    let stats = Arc::new(FlowStats::default());
    let (ptx, mut prx) = mpsc::unbounded_channel();
    let run = runtime::start(
        &def,
        &ports,
        &BTreeMap::new(),
        |_node, inject| Io {
            client: env.client.clone(),
            ctx: env.ctx.clone(),
            site: "test".into(),
            flow: def.id.clone(),
            inject,
        },
        ptx,
        None,
        Probe::new(&def),
        &Mode::Live,
        stats.clone(),
    )
    .unwrap();
    let inbox = run.inboxes[first].clone();
    let taken = || stats.samples_in.load(Ordering::Relaxed);
    let settle = |want: u64, since: Instant| {
        let stats = stats.clone();
        async move {
            while stats.samples_in.load(Ordering::Relaxed) < want {
                assert!(
                    since.elapsed() < Duration::from_secs(120),
                    "the flow did not take every sample"
                );
                tokio::time::sleep(Duration::from_micros(200)).await;
            }
        }
    };
    // the start values and one sample through, so every block holds its maps
    tokio::time::sleep(Duration::from_millis(100)).await;
    let base = taken();
    inbox.push_now(port, Msg::new(make(0), Quality::Good, 1));
    settle(base + inputs_per_sample, Instant::now()).await;
    let mut i = 1u64;
    let mut out = Vec::new();
    for _ in 0..rounds {
        let msgs: Vec<Msg> = (0..count)
            .map(|k| Msg::new(make(i + k), Quality::Good, i + k))
            .collect();
        i += count;
        let base = taken();
        let u0 = Usage::read();
        let a0 = Allocs::read();
        let t0 = Instant::now();
        for m in msgs {
            inbox.push_now(port, m);
        }
        settle(base + count * inputs_per_sample, t0).await;
        let wall = t0.elapsed();
        let a = Allocs::read().since(a0);
        let cpu_s = match (Usage::read().cpu_s, u0.cpu_s) {
            (Some(a), Some(b)) => a - b,
            _ => f64::NAN,
        };
        out.push(Round {
            per_s: count as f64 / wall.as_secs_f64(),
            cpu_us: cpu_s * 1e6 / count as f64,
            allocs: a.calls_per(count),
            bytes: a.bytes_per(count),
        });
    }
    assert_eq!(stats.dropped.load(Ordering::Relaxed), 0, "{name}: dropped");
    assert!(prx.try_recv().is_err(), "{name}: a node panicked");
    run.stop().await;
    out
}

async fn case(env: &Env, c: Case<'_>) {
    let rounds = measure(env, &c, ROUNDS).await;
    let Case {
        name,
        count,
        note,
        copy_allocs,
        ..
    } = c;
    let med = |f: &dyn Fn(&Round) -> f64| {
        let mut v: Vec<f64> = rounds.iter().map(f).collect();
        v.sort_by(f64::total_cmp);
        (v[0], v[v.len() / 2], v[v.len() - 1])
    };
    let (lo, per_s, hi) = med(&|r| r.per_s);
    let allocs = med(&|r| r.allocs).1;
    let mut line = Perf::new(name)
        .n(count)
        .per_s(per_s)
        .allocs_op(allocs, med(&|r| r.bytes).1)
        .num("cpu_us", med(&|r| r.cpu_us).1)
        .num("per_s_min", lo)
        .num("per_s_max", hi)
        .field("rounds", ROUNDS);
    if let Some(unit) = copy_allocs {
        line = line.num("copies", allocs / unit);
    }
    println!("{}", line.note(note));
}

/// Allocations and bytes of one copy of `v` (a `Value::clone`).
fn copy_cost(v: &Value) -> (f64, f64) {
    let a0 = Allocs::read();
    let c = v.clone();
    let a = Allocs::read().since(a0);
    drop(c);
    (a.calls_per(1), a.bytes_per(1))
}

/// A table of [`ROWS`] rows `{n, v, s}`; `shift` makes each table differ.
fn table(shift: u64) -> Value {
    map(&[
        ("columns", Value::Array(vec![s("n"), s("v"), s("s")])),
        (
            "rows",
            Value::Array(
                (0..ROWS)
                    .map(|i| {
                        let n = (i * 7919) % ROWS + shift;
                        map(&[
                            ("n", Value::UInt(n)),
                            ("v", Value::Float(n as f64 / 8.0)),
                            ("s", s(&format!("row {n}"))),
                        ])
                    })
                    .collect(),
            ),
        ),
    ])
}

/// The counters are the whole process's: the measurement and the check never run together.
static ONE_AT_A_TIME: tokio::sync::Mutex<()> = tokio::sync::Mutex::const_new(());

/// 10 pure blocks in a chain: `add` with a constant and `multiply` in turn.
fn chain10() -> Value {
    let mut nodes = Vec::new();
    let mut edges = Vec::new();
    for i in 0..10 {
        let add = i % 2 == 0;
        nodes.push((
            format!("n{i}"),
            if add {
                add_one()
            } else {
                node("multiply", &[("values", map(&[("in.1", Value::UInt(1))]))])
            },
        ));
        if i > 0 {
            edges.push(edge(&format!("n{}.out", i - 1), &format!("n{i}.in.0")));
        }
    }
    flow("chain10", nodes, edges, 65_536)
}

/// A sample that goes from block to block costs no allocation per block: the port names
/// are shared with the edges, the blocks' slots are found by their names, and a number
/// holds no heap. (Before this slice: 9 allocations per block and sample.) One allocation
/// per sample is the test's own push into the first inbox; the bound leaves room for what
/// the idle session's threads allocate meanwhile.
#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn a_number_through_ten_blocks_allocates_next_to_nothing() {
    let _one = ONE_AT_A_TIME.lock().await;
    let env = env().await;
    let c = Case {
        name: "check",
        def: &chain10(),
        first: "n0",
        port: "in.0",
        inputs_per_sample: 10,
        count: 20_000,
        make: &|i| Value::Float(i as f64),
        note: "",
        copy_allocs: None,
    };
    let r = measure(&env, &c, 1).await;
    // written past the test harness's capture, so a passing run shows the figure in CI logs
    let line = Perf::new("flow/copies/check")
        .n(c.count)
        .per_s(r[0].per_s)
        .allocs_op(r[0].allocs, r[0].bytes)
        .note("the check: 10 pure blocks, one number per sample, in the build the tests run in");
    let _ = writeln!(std::io::stderr().lock(), "{line}");
    assert!(
        r[0].allocs < 3.0,
        "{} allocations per sample through 10 blocks",
        r[0].allocs
    );
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
#[ignore = "a measurement, run by hand"]
async fn copies() {
    let _one = ONE_AT_A_TIME.lock().await;
    let env = env().await;
    let num = |i: u64| Value::Float(i as f64);

    // a round is one burst: it must fit the deepest inbox a flow may have (65 536)
    let count = 50_000u64;
    case(
        &env,
        Case {
            name: "flow/copies/chain10",
            def: &chain10(),
            first: "n0",
            port: "in.0",
            inputs_per_sample: 10,
            count,
            make: &num,
            note: "10 pure blocks in a chain, one number per sample",
            copy_allocs: None,
        },
    )
    .await;

    let mut nodes = vec![("n0".to_owned(), add_one())];
    let mut edges = Vec::new();
    for i in 0..16 {
        nodes.push((format!("a{i}"), node("abs", &[])));
        edges.push(edge("n0.out", &format!("a{i}.in")));
    }
    case(
        &env,
        Case {
            name: "flow/copies/fanout16",
            def: &flow("fanout16", nodes, edges, 65_536),
            first: "n0",
            port: "in.0",
            inputs_per_sample: 17,
            count,
            make: &num,
            note: "one add whose output has 16 edges, each into an abs",
            copy_allocs: None,
        },
    )
    .await;

    let nodes = vec![(
        "e".to_owned(),
        node(
            "expression",
            &[
                ("inputs", Value::Array(vec![s("x")])),
                ("expr", s("x.v * 2.0 + 1.0")),
            ],
        ),
    )];
    case(
        &env,
        Case {
            name: "flow/copies/rhai",
            def: &flow("rhai", nodes, Vec::new(), 65_536),
            first: "e",
            port: "in.x",
            inputs_per_sample: 1,
            count,
            make: &num,
            note: "one expression block (rhai), one number per sample",
            copy_allocs: None,
        },
    )
    .await;

    let tables = 200u64;
    // what one copy of the test table costs: the unit of `copies`
    let (unit, unit_bytes) = copy_cost(&table(0));
    println!(
        "{}",
        Perf::new("flow/copies/table_copy")
            .n(1)
            .allocs_op(unit, unit_bytes)
            .note("one Value::clone of the 1000-row table of 3 columns")
    );
    let mut nodes = Vec::new();
    let mut edges = Vec::new();
    for i in 0..3 {
        let order = if i % 2 == 0 {
            "descending"
        } else {
            "ascending"
        };
        nodes.push((
            format!("t{i}"),
            node("table_sort", &[("column", s("n")), ("order", s(order))]),
        ));
        if i > 0 {
            edges.push(edge(&format!("t{}.out", i - 1), &format!("t{i}.in")));
        }
    }
    case(
        &env,
        Case {
            name: "flow/copies/table3",
            def: &flow("table3", nodes, edges, 65_536),
            first: "t0",
            port: "in",
            inputs_per_sample: 3,
            count: tables,
            make: &table,
            note: "a 1000-row table of 3 columns through 3 table_sort blocks",
            copy_allocs: Some(unit),
        },
    )
    .await;

    // a table through blocks that pass it on as it is: 3 hubs in a chain
    let mut nodes = Vec::new();
    let mut edges = Vec::new();
    for i in 0..3 {
        nodes.push((format!("h{i}"), node("hub", &[])));
        if i > 0 {
            edges.push(edge(&format!("h{}.out", i - 1), &format!("h{i}.in.0")));
        }
    }
    case(
        &env,
        Case {
            name: "flow/copies/hub3",
            def: &flow("hub3", nodes, edges, 65_536),
            first: "h0",
            port: "in.0",
            inputs_per_sample: 3,
            count: tables,
            make: &table,
            note: "a 1000-row table of 3 columns through 3 hub blocks (passed on as it is)",
            copy_allocs: Some(unit),
        },
    )
    .await;

    // a table sorted once and sent on 4 edges, each into a hub
    let mut nodes = vec![(
        "t".to_owned(),
        node("table_sort", &[("column", s("n")), ("order", s("descending"))]),
    )];
    let mut edges = Vec::new();
    for i in 0..4 {
        nodes.push((format!("h{i}"), node("hub", &[])));
        edges.push(edge("t.out", &format!("h{i}.in.0")));
    }
    case(
        &env,
        Case {
            name: "flow/copies/table_fanout4",
            def: &flow("table_fanout4", nodes, edges, 65_536),
            first: "t",
            port: "in",
            inputs_per_sample: 5,
            count: tables,
            make: &table,
            note: "a 1000-row table through one table_sort whose output has 4 edges, each into a hub",
            copy_allocs: Some(unit),
        },
    )
    .await;
}
