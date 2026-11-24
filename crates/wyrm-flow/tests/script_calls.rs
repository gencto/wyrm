//! What one call of a script block costs (performance slice "flow rhai calls", issue #160,
//! `docs/backlog.md` §14): a node built by [`wyrm_flow::nodes::build`] and its `input` called
//! on the test's thread. No runtime, no inbox and no edge: the figures are the block's alone.
//! Not a check: run it by hand.
//!
//! `cargo test --release -p wyrm-flow --test script_calls -- --ignored --nocapture`
//!
//! * `flow/script/expression`: one `expression` (`x.v * 2.0 + 1.0`), one number per call.
//! * `flow/script/expression3`: one `expression` over three inputs (`a.v + b.v * c.v`); a
//!   call is a sample on one of them.
//! * `flow/script/expression_state`: an `expression` that counts in `state`.
//! * `flow/script/filter`: one `filter` (`v > 10.0`).
//! * `flow/script/table_filter`: a table of [`ROWS`] rows of three cells (a number, a float,
//!   a text) through `table_filter` (`row.v > 600.0`): one script call per row.
//! * `flow/script/table_filter_numbers`: the same with rows of three numbers.
//! * `flow/script/table_map`: the same table through `table_map_columns` with one computed
//!   column (`+ row.v * 2.0`) and the columns kept.
//! * `flow/script/table_sort`: the same table through `table_sort`, a table block with no
//!   script, for scale (what the parse of the input and the output cost).
//! * `flow/script/stage/*` (test `stages`): where the allocations of one call are, measured on
//!   rhai itself with the crate's engine: the variables, the scope, the evaluation on a ready
//!   scope, the state read back, the result.
//!
//! Every case runs [`ROUNDS`] times; the line gives the median round: `ns_op` (wall time per
//! call on one thread; `ms_table` for a table), allocations and bytes per call (the counting
//! allocator; the samples are built before the round), and for a table `allocs_row`.
//! The allocation counts do not move with the machine's load; the times do.
//!
//! One `PERF` line per figure (`tool/perf.sh flow`).

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::unreachable,
    clippy::print_stdout,
    reason = "test code: a failed step fails the test"
)]

use std::collections::BTreeMap;
use std::sync::Arc;
use std::time::Instant;
use wyrm_bench::{Allocs, Perf};
use wyrm_client::WyrmClient;
use wyrm_core::{Quality, Value};
use wyrm_flow::nodes::{self, Io, Msg, Node, Out};
use wyrm_flow::script;
use wyrm_link_mock::{Mock, MockConfig};
use wyrm_link_sdk::harness::isolated_config;
use wyrm_link_sdk::{LinkConfig, LinkHandle};

#[global_allocator]
static A: wyrm_bench::Counting = wyrm_bench::Counting;

const ROUNDS: usize = 7;
/// Rows of the test table: the most a table may have.
const ROWS: u64 = 10_000;

/// The counters are the whole process's: one measurement at a time.
static ONE_AT_A_TIME: tokio::sync::Mutex<()> = tokio::sync::Mutex::const_new(());

fn map(kv: &[(&str, Value)]) -> BTreeMap<String, Value> {
    kv.iter()
        .map(|(k, v)| ((*k).to_owned(), v.clone()))
        .collect()
}

fn s(x: &str) -> Value {
    Value::from(x)
}

struct Env {
    io: Io,
    _h: LinkHandle<Mock>,
}

/// What a node's `input` is given: nothing in these blocks uses it.
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
        io: Io {
            client: WyrmClient::new(session),
            ctx: h.ctx().clone(),
            site: "test".into(),
            flow: "f".into(),
            inject: Arc::new(|_, _| {}),
        },
        _h: h,
    }
}

/// One round: allocations, bytes and nanoseconds per call.
struct Round {
    allocs: f64,
    bytes: f64,
    ns: f64,
}

fn median(rounds: &[Round], f: impl Fn(&Round) -> f64) -> f64 {
    let mut v: Vec<f64> = rounds.iter().map(f).collect();
    v.sort_by(f64::total_cmp);
    v[v.len() / 2]
}

/// `rounds` rounds of `count` calls of `call` (given the call's number, from 1).
fn measure(rounds: usize, count: u64, mut call: impl FnMut(u64)) -> Vec<Round> {
    // the first calls make what a block keeps (its maps, its buffers)
    for i in 0..16 {
        call(i + 1);
    }
    let mut i = 16;
    (0..rounds)
        .map(|_| {
            let a0 = Allocs::read();
            let t0 = Instant::now();
            for _ in 0..count {
                i += 1;
                call(i);
            }
            let wall = t0.elapsed();
            let a = Allocs::read().since(a0);
            Round {
                allocs: a.calls_per(count),
                bytes: a.bytes_per(count),
                ns: wall.as_nanos() as f64 / count as f64,
            }
        })
        .collect()
}

fn line(name: &str, count: u64, rounds: &[Round], note: &str) -> Perf {
    Perf::new(name)
        .n(count)
        .per_s(1e9 / median(rounds, |r| r.ns))
        .allocs_op(median(rounds, |r| r.allocs), median(rounds, |r| r.bytes))
        .num("ns_op", median(rounds, |r| r.ns))
        .field("rounds", rounds.len())
        .note(note)
}

/// A node of type `ty` with config `cfg`.
fn node(ty: &str, cfg: &[(&str, Value)]) -> Box<dyn Node> {
    let cfg = map(cfg);
    nodes::ports(ty, &cfg).unwrap_or_else(|e| panic!("{ty}: {e}"));
    nodes::build(ty, "f", "n", &cfg).unwrap_or_else(|e| panic!("{ty}: {e}"))
}

/// A table of [`ROWS`] rows `{n, v, s}`; `shift` makes each table differ in its third cell
/// alone (a text with `text`, else a number), so a script over `v` keeps the same rows.
fn table(shift: u64, text: bool) -> Value {
    Value::Map(map(&[
        ("columns", Value::Array(vec![s("n"), s("v"), s("s")])),
        (
            "rows",
            Value::Array(
                (0..ROWS)
                    .map(|i| {
                        let n = (i * 7919) % ROWS;
                        Value::Map(map(&[
                            ("n", Value::UInt(n)),
                            ("v", Value::Float(n as f64 / 8.0)),
                            (
                                "s",
                                if text {
                                    s(&format!("row {}", n + shift))
                                } else {
                                    Value::UInt(n * 3 + shift)
                                },
                            ),
                        ]))
                    })
                    .collect(),
            ),
        ),
    ]))
}

/// The value a block sent on `port` in `out`.
fn sent<'a>(out: &'a Out, port: &str) -> Option<&'a Value> {
    out.0
        .iter()
        .rev()
        .find(|(p, _)| p == port)
        .map(|(_, m)| m.v.get())
}

/// One number per call on `port` of `n`; every call must send `out`.
fn numbers(io: &Io, name: &str, mut n: Box<dyn Node>, ports: &[&str], note: &str) {
    let count = 200_000u64;
    let mut out = Out::default();
    let mut sent_out = 0u64;
    let mut calls = 0u64;
    let rounds = measure(ROUNDS, count, |i| {
        let port = ports[(i % ports.len() as u64) as usize];
        out.0.clear();
        n.input(
            port,
            Msg::new(Value::Float(i as f64), Quality::Good, i),
            io,
            &mut out,
        );
        calls += 1;
        sent_out += out.0.len() as u64;
    });
    // an `expression` sends once every input has a value, the `filter` past its bound: all
    // calls but the first few
    assert!(
        sent_out + 32 > calls,
        "{name}: {sent_out} of {calls} calls sent"
    );
    println!("{}", line(name, count, &rounds, note));
}

/// One table per call into `in` of `n`; `rows_out` is how many rows the result must have.
fn tables(io: &Io, name: &str, mut n: Box<dyn Node>, text: bool, rows_out: usize, note: &str) {
    let count = 20u64;
    let mut out = Out::default();
    // the tables of every round, made before any is measured
    let mut made: Vec<Value> = (0..16 + ROUNDS as u64 * count)
        .map(|i| table(i % 8, text))
        .rev()
        .collect();
    let rounds = measure(ROUNDS, count, |i| {
        let t = made.pop().unwrap();
        out.0.clear();
        n.input("in", Msg::new(t, Quality::Good, i), io, &mut out);
        // a table whose scripts ran out of their budget is no figure
        let Some(Value::Map(t)) = sent(&out, "out") else {
            panic!("{name}: no table out: {:?}", sent(&out, "error"));
        };
        let Some(Value::Array(rows)) = t.get("rows") else {
            panic!("{name}: no rows");
        };
        assert_eq!(rows.len(), rows_out, "{name}");
    });
    let allocs = median(&rounds, |r| r.allocs);
    println!(
        "{}",
        line(name, count, &rounds, note)
            .num("ms_table", median(&rounds, |r| r.ns) / 1e6)
            .num("allocs_row", allocs / ROWS as f64)
            .num("ns_row", median(&rounds, |r| r.ns) / ROWS as f64)
    );
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
#[ignore = "a measurement, run by hand"]
async fn script_calls() {
    let _one = ONE_AT_A_TIME.lock().await;
    let env = env().await;
    let io = &env.io;
    // the session's threads settle
    tokio::time::sleep(std::time::Duration::from_millis(200)).await;

    numbers(
        io,
        "flow/script/expression",
        node(
            "expression",
            &[
                ("inputs", Value::Array(vec![s("x")])),
                ("expr", s("x.v * 2.0 + 1.0")),
            ],
        ),
        &["in.x"],
        "one expression block (rhai), one number per call",
    );
    numbers(
        io,
        "flow/script/expression3",
        node(
            "expression",
            &[
                ("inputs", Value::Array(vec![s("a"), s("b"), s("c")])),
                ("expr", s("a.v + b.v * c.v")),
            ],
        ),
        &["in.a", "in.b", "in.c"],
        "one expression block over three inputs, a sample on one of them per call",
    );
    numbers(
        io,
        "flow/script/expression_state",
        node(
            "expression",
            &[
                ("inputs", Value::Array(vec![s("x")])),
                ("expr", s("state.n = (state.n ?? 0) + 1; x.v + state.n")),
            ],
        ),
        &["in.x"],
        "one expression block that counts in state",
    );
    numbers(
        io,
        "flow/script/filter",
        node("filter", &[("expr", s("v > 10.0"))]),
        &["in"],
        "one filter block (rhai over v, q, t)",
    );

    // the rows with v > 600: n runs over 0..10 000, v = n / 8
    let kept = (0..ROWS).filter(|n| *n as f64 / 8.0 > 600.0).count();
    tables(
        io,
        "flow/script/table_filter",
        node("table_filter", &[("expr", s("row.v > 600.0"))]),
        true,
        kept,
        "a 10000-row table of 3 columns (number, float, text) through table_filter, rhai per row",
    );
    tables(
        io,
        "flow/script/table_filter_numbers",
        node("table_filter", &[("expr", s("row.v > 600.0"))]),
        false,
        kept,
        "a 10000-row table of 3 number columns through table_filter, rhai per row",
    );
    tables(
        io,
        "flow/script/table_map",
        node(
            "table_map_columns",
            &[
                ("retain_columns", Value::Bool(true)),
                (
                    "mapping",
                    Value::Array(vec![Value::Map(map(&[
                        ("name", s("w")),
                        ("from", s("+ row.v * 2.0")),
                    ]))]),
                ),
            ],
        ),
        true,
        ROWS as usize,
        "the 10000-row table through table_map_columns, one computed column, rhai per row",
    );
    tables(
        io,
        "flow/script/table_sort",
        node(
            "table_sort",
            &[("column", s("n")), ("order", s("descending"))],
        ),
        true,
        ROWS as usize,
        "the 10000-row table through table_sort: a table block with no script, for scale",
    );
}

/// Where the allocations of one call are: each stage of a call alone, on rhai itself with
/// the crate's engine and a script as `expression` compiles it (`x.v * 2.0 + 1.0`).
#[test]
#[ignore = "a measurement, run by hand"]
fn stages() {
    let _one = ONE_AT_A_TIME.blocking_lock();
    let engine = script::engine();
    let ast = script::compile(&engine, "x.v * 2.0 + 1.0", &["x"]).unwrap();
    let count = 100_000u64;
    let stage = |name: &str, note: &str, f: &mut dyn FnMut(u64)| {
        let rounds = measure(ROUNDS, count, f);
        println!(
            "{}",
            line(&format!("flow/script/stage/{name}"), count, &rounds, note)
        );
    };
    let input = |i: u64| {
        let mut m = rhai::Map::new();
        m.insert("v".into(), script::to_dynamic(&Value::Float(i as f64)));
        m.insert("q".into(), rhai::Dynamic::from_int(0));
        m.insert("t".into(), rhai::Dynamic::from_int(i as i64));
        m.insert("age_ms".into(), rhai::Dynamic::from_int(0));
        m
    };
    stage(
        "input_map",
        "the map {v, q, t, age_ms} of one input",
        &mut |i| {
            drop(std::hint::black_box(input(i)));
        },
    );
    stage(
        "input_dynamic",
        "that map as a rhai value (the map and its box)",
        &mut |i| {
            drop(std::hint::black_box(rhai::Dynamic::from_map(input(i))));
        },
    );
    stage(
        "vars",
        "the variables of a call: a list of (name, value), one input",
        &mut |i| {
            drop(std::hint::black_box(vec![(
                "x".to_owned(),
                rhai::Dynamic::from_map(input(i)),
            )]));
        },
    );
    stage(
        "scope",
        "a new scope with one variable and state (the values made before are not counted: unit)",
        &mut |_| {
            let mut scope = rhai::Scope::new();
            scope.push_dynamic("x", rhai::Dynamic::UNIT);
            scope.push_dynamic("state", rhai::Dynamic::UNIT);
            std::hint::black_box(&scope);
        },
    );
    stage(
        "state_in",
        "an empty state map as a rhai value (its box)",
        &mut |_| {
            drop(std::hint::black_box(rhai::Dynamic::from_map(
                rhai::Map::new(),
            )));
        },
    );
    let mut scope = rhai::Scope::new();
    scope.push_dynamic("x", rhai::Dynamic::from_map(input(1)));
    scope.push_dynamic("state", rhai::Dynamic::from_map(rhai::Map::new()));
    stage(
        "eval",
        "the evaluation alone, on a scope made once",
        &mut |_| {
            let r = engine
                .eval_ast_with_scope::<rhai::Dynamic>(&mut scope, &ast)
                .unwrap();
            drop(std::hint::black_box(r));
        },
    );
    stage(
        "state_out",
        "the state read back from the scope (a copy of the map)",
        &mut |_| {
            drop(std::hint::black_box(scope.get_value::<rhai::Map>("state")));
        },
    );
    let r = rhai::Dynamic::from_float(2.5);
    stage("result", "the result (a float) as a value", &mut |_| {
        drop(std::hint::black_box(script::from_dynamic(&r)));
    });
    // one row of the test table, as `per_row` gives it to a script
    let row = map(&[
        ("n", Value::UInt(7)),
        ("v", Value::Float(0.875)),
        ("s", s("row 7")),
    ]);
    stage(
        "row_copy",
        "a copy of one table row {n, v, s} (number, float, text)",
        &mut |_| {
            drop(std::hint::black_box(Value::Map(row.clone())));
        },
    );
    let as_value = Value::Map(row.clone());
    stage(
        "row_dynamic",
        "that row as a rhai value (from the copy)",
        &mut |_| {
            drop(std::hint::black_box(script::to_dynamic(&as_value)));
        },
    );
}
