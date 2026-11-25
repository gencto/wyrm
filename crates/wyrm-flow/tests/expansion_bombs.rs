//! Security review 2026-11-09: a definition is compiled for `validate` and `preview` at level
//! `read`, so the expansion of custom blocks is charged against the limits while it is made.
//! A block that multiplies is refused after bounded work, whatever its shape.
//!
//! The work is judged by what it allocates, not by the wall clock: a 50 ms bound failed on a
//! loaded machine though the compiler did the same work. Every node, instance and edge the
//! expansion makes is an allocation or more, so a count of allocations bounds the expansion,
//! and it does not move with the machine's load. The test is alone in its binary: the
//! counters are the whole process's.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::unreachable,
    clippy::print_stdout,
    reason = "test code: a failed step fails the test"
)]

use std::io::Write as _;
use std::time::{Duration, Instant};
use wyrm_bench::{Allocs, Perf};
use wyrm_core::Value;
use wyrm_flow::def;

#[global_allocator]
static A: wyrm_bench::Counting = wyrm_bench::Counting;

fn map(kv: &[(&str, Value)]) -> Value {
    Value::Map(
        kv.iter()
            .map(|(k, v)| ((*k).to_owned(), v.clone()))
            .collect(),
    )
}

fn arr(items: &[Value]) -> Value {
    Value::Array(items.to_vec())
}

fn edge(a: &str, b: &str) -> Value {
    arr(&[Value::from(a), Value::from(b)])
}

fn s(x: &str) -> Value {
    Value::from(x)
}

fn node(ty: &str, kv: &[(&str, Value)]) -> Value {
    let mut all = vec![("type", s(ty))];
    all.extend(kv.iter().cloned());
    map(&all)
}

fn flow(id: &str, nodes: &[(&str, Value)], edges: &[(&str, &str)]) -> Value {
    map(&[
        ("id", s(id)),
        ("version", Value::UInt(1)),
        ("nodes", map(nodes)),
        (
            "edges",
            arr(&edges.iter().map(|(a, b)| edge(a, b)).collect::<Vec<_>>()),
        ),
        ("permissions", map(&[("maxperm", s("write"))])),
    ])
}

fn port(name: &str, key: &str, to: Value, more: &[(&str, Value)]) -> Value {
    let mut kv = vec![("name", s(name)), (key, to)];
    kv.extend(more.iter().cloned());
    map(&kv)
}

fn with_blocks(mut d: Value, blocks: &[(&str, Value)]) -> Value {
    if let Value::Map(m) = &mut d {
        m.insert("blocks".into(), map(blocks));
    }
    d
}

/// The largest definition the limits allow, all of it inside custom blocks: 4 instances of a
/// block of 240 `not` nodes in a chain (960 nodes, 956 edges). What its compile allocates is
/// the unit the refusals are judged by.
fn largest() -> Value {
    let inner: Vec<(String, Value)> = (0..240)
        .map(|k| (format!("n{k}"), node("not", &[])))
        .collect();
    let inner: Vec<(&str, Value)> = inner.iter().map(|(n, v)| (n.as_str(), v.clone())).collect();
    let wires: Vec<Value> = (0..239)
        .map(|k| edge(&format!("n{k}.out"), &format!("n{}.in", k + 1)))
        .collect();
    let uses: Vec<(String, Value)> = (0..4)
        .map(|k| (format!("u{k}"), node("block:big", &[])))
        .collect();
    let uses: Vec<(&str, Value)> = uses.iter().map(|(n, v)| (n.as_str(), v.clone())).collect();
    with_blocks(
        flow("f", &uses, &[]),
        &[(
            "big",
            map(&[("nodes", map(&inner)), ("edges", arr(&wires))]),
        )],
    )
}

/// What a refusal may allocate, in compiles of [`largest`] (measured: 0.01 to 0.31). The bombs below would make 64⁴
/// nodes or 16⁴ edges per wire (17 000 and 16 times the limits); a compiler that expanded
/// them before it counted would allocate thousands of times the unit.
const UNITS: f64 = 1.0;

/// The unbounded case only: no machine under load takes this long for bounded work.
const WALL: Duration = Duration::from_secs(20);

#[test]
fn expansion_bombs_are_refused_after_bounded_work() {
    // the unit: a definition at the limits, compiled once to warm up and once counted
    let big = largest();
    let (d, _) = def::compile(&big).unwrap();
    assert_eq!(d.nodes.len(), 960);
    drop(d);
    let a0 = Allocs::read();
    let compiled = def::compile(&big).unwrap();
    let unit = Allocs::read().since(a0).calls as f64;
    drop(compiled);
    assert!(
        unit > 960.0,
        "the counting allocator is not installed: {unit}"
    );
    let mut err = std::io::stderr().lock();
    let _ = writeln!(
        err,
        "{}",
        Perf::new("flow/expansion/largest")
            .n(1)
            .allocs_op(unit, f64::NAN)
            .note("the unit: compile of a definition at the limits (960 nodes in custom blocks)")
    );
    let mut quick = |what: &str, d: &Value, why: &str| {
        let t = Instant::now();
        let a0 = Allocs::read();
        let e = def::compile(d).unwrap_err();
        let a = Allocs::read().since(a0);
        let took = t.elapsed();
        // written past the harness's capture, so a passing run shows the figures in CI logs
        let _ = writeln!(
            err,
            "{}",
            Perf::new("flow/expansion/refused")
                .n(1)
                .allocs_op(a.calls as f64, a.bytes as f64)
                .num("units", a.calls as f64 / unit)
                .num("ms", took.as_secs_f64() * 1e3)
                .note(what)
        );
        assert!(e.to_string().contains(why), "{what}: {e}");
        assert!(
            (a.calls as f64) < UNITS * unit,
            "{what}: {} allocations to refuse it; a definition at the limits compiles with {unit}",
            a.calls
        );
        assert!(took < WALL, "{what}: {took:?}");
    };
    // a fan-out bomb, 4 deep: each block holds 64 instances of the one below (64⁴ nodes)
    let mut blocks = vec![(
        "b1".to_owned(),
        map(&[("nodes", map(&[("n", node("not", &[]))]))]),
    )];
    for i in 2..=4 {
        let inner: Vec<(String, Value)> = (0..64)
            .map(|k| (format!("i{k}"), node(&format!("block:b{}", i - 1), &[])))
            .collect();
        let inner: Vec<(&str, Value)> =
            inner.iter().map(|(n, v)| (n.as_str(), v.clone())).collect();
        blocks.push((format!("b{i}"), map(&[("nodes", map(&inner))])));
    }
    let blocks: Vec<(&str, Value)> = blocks
        .iter()
        .map(|(n, v)| (n.as_str(), v.clone()))
        .collect();
    let bomb = with_blocks(flow("f", &[("u", node("block:b4", &[]))], &[]), &blocks);
    quick("instances in instances", &bomb, "more than 1000 nodes");
    // instances alone count too: blocks that hold nothing but instances
    let hollow: Vec<(String, Value)> = (2..=4)
        .map(|i| {
            let inner: Vec<(String, Value)> = (0..64)
                .map(|k| (format!("i{k}"), node(&format!("block:h{}", i - 1), &[])))
                .collect();
            let inner: Vec<(&str, Value)> =
                inner.iter().map(|(n, v)| (n.as_str(), v.clone())).collect();
            (format!("h{i}"), map(&[("nodes", map(&inner))]))
        })
        .chain([("h1".to_owned(), map(&[]))])
        .collect();
    let hollow: Vec<(&str, Value)> = hollow
        .iter()
        .map(|(n, v)| (n.as_str(), v.clone()))
        .collect();
    let bomb = with_blocks(flow("f", &[("u", node("block:h4", &[]))], &[]), &hollow);
    quick("hollow instances", &bomb, "more than 1000 nodes");
    // an edge bomb: one input feeds 16 inner inputs at each of 4 levels (16⁴ edges per wire)
    let to16 =
        |target: &dyn Fn(usize) -> String| arr(&(0..16).map(|k| s(&target(k))).collect::<Vec<_>>());
    let mut fan = vec![(
        "e1".to_owned(),
        map(&[
            (
                "nodes",
                map(&[(
                    "h",
                    node(
                        "hub",
                        &[(
                            "inputs",
                            arr(&(0..16).map(|k| s(&format!("p{k}"))).collect::<Vec<_>>()),
                        )],
                    ),
                )]),
            ),
            (
                "inputs",
                arr(&[port("x", "to", to16(&|k| format!("h.in.p{k}")), &[])]),
            ),
        ]),
    )];
    for i in 2..=4 {
        fan.push((
            format!("e{i}"),
            map(&[
                (
                    "nodes",
                    map(&[("i", node(&format!("block:e{}", i - 1), &[]))]),
                ),
                (
                    "inputs",
                    arr(&[port("x", "to", to16(&|_| "i.x".to_owned()), &[])]),
                ),
            ]),
        ));
    }
    let fan: Vec<(&str, Value)> = fan.iter().map(|(n, v)| (n.as_str(), v.clone())).collect();
    let bomb = with_blocks(
        flow(
            "f",
            &[("v", node("number", &[])), ("u", node("block:e4", &[]))],
            &[("v.out", "u.x")],
        ),
        &fan,
    );
    quick(
        "an input that fans out at every level",
        &bomb,
        "more than 4000 edges",
    );
    // more than 64 instances inside one block, and too many plain edges
    let inner: Vec<(String, Value)> = (0..65)
        .map(|k| (format!("i{k}"), node("block:b1", &[])))
        .collect();
    let inner: Vec<(&str, Value)> = inner.iter().map(|(n, v)| (n.as_str(), v.clone())).collect();
    let wide = with_blocks(
        flow("f", &[], &[]),
        &[
            ("b1", map(&[("nodes", map(&[("n", node("not", &[]))]))])),
            ("wide", map(&[("nodes", map(&inner))])),
        ],
    );
    quick(
        "too many instances in a block",
        &wide,
        "65 instances of custom blocks > 64",
    );
}
