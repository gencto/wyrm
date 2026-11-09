//! The second set of blocks (ADR 0040 §4, `docs/flow-blocks.md`), driven through
//! `input`/`tick`.

use std::collections::BTreeMap;
use std::sync::Arc;
use std::time::Duration;
use wyrm_client::WyrmClient;
use wyrm_core::{Quality, Value};
use wyrm_flow::nodes::{self, Io, Msg, Node, Out};
use wyrm_link_mock::{Mock, MockConfig};
use wyrm_link_sdk::harness::isolated_config;
use wyrm_link_sdk::{LinkConfig, LinkHandle};

struct Env {
    io: Io,
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
    let io = Io {
        client: WyrmClient::new(session),
        ctx: h.ctx().clone(),
        site: "test".into(),
        flow: "f".into(),
        inject: Arc::new(|_, _| {}),
    };
    Env { io, _h: h }
}

fn build(ty: &str, kv: &[(&str, Value)]) -> Box<dyn Node> {
    let c: BTreeMap<String, Value> = kv
        .iter()
        .map(|(k, v)| ((*k).to_owned(), v.clone()))
        .collect();
    nodes::ports(ty, &c).unwrap();
    nodes::build(ty, "f", "n", &c).unwrap()
}

fn good(v: impl Into<Value>) -> Msg {
    Msg::new(v.into(), Quality::Good, 1)
}

fn feed(n: &mut dyn Node, io: &Io, port: &str, msg: Msg) -> Vec<(String, Value)> {
    let mut out = Out::default();
    n.input(port, msg, io, &mut out);
    out.0.into_iter().map(|(p, m)| (p, m.v)).collect()
}

fn tick(n: &mut dyn Node) -> Vec<(String, Value)> {
    let mut out = Out::default();
    n.tick(1, &mut out);
    out.0.into_iter().map(|(p, m)| (p, m.v)).collect()
}

fn on(sent: &[(String, Value)], port: &str) -> Option<Value> {
    sent.iter().find(|(p, _)| p == port).map(|(_, v)| v.clone())
}

fn list(items: &[Value]) -> Value {
    Value::Array(items.to_vec())
}

fn texts(items: &[&str]) -> Value {
    Value::Array(items.iter().map(|s| Value::from(*s)).collect())
}

fn map(kv: &[(&str, Value)]) -> Value {
    Value::Map(
        kv.iter()
            .map(|(k, v)| ((*k).to_owned(), v.clone()))
            .collect(),
    )
}

/// The value a block sends on `out` for `v` on `in`.
fn out_of(n: &mut dyn Node, io: &Io, v: impl Into<Value>) -> Option<Value> {
    on(&feed(n, io, "in", good(v)), "out")
}

#[tokio::test(flavor = "multi_thread")]
async fn text_blocks() {
    let e = env().await;
    let io = &e.io;
    // substring: from `start`, `length` characters (characters, not bytes)
    let mut s = build("substring", &[("start", Value::UInt(2))]);
    assert_eq!(out_of(&mut *s, io, "héllo wörld"), Some("llo wörld".into()));
    assert_eq!(
        on(&feed(&mut *s, io, "in.length", good(3u64)), "out"),
        Some("llo".into())
    );
    assert_eq!(out_of(&mut *s, io, 123456u64), Some("345".into()));
    assert_eq!(out_of(&mut *s, io, "ab"), Some("".into()));
    assert_eq!(out_of(&mut *s, io, Value::Null), Some(Value::Null));
    // replace: every occurrence, plain text
    let mut r = build("replace", &[("from", "a.".into()), ("to", "-".into())]);
    assert_eq!(out_of(&mut *r, io, "a.b a.c aXd"), Some("-b -c aXd".into()));
    assert_eq!(
        on(&feed(&mut *r, io, "in.from", good("")), "out"),
        Some("a.b a.c aXd".into()),
        "an empty text replaces nothing"
    );
    // a result past 4 KiB is null and bad
    let mut r = build(
        "replace",
        &[("from", "a".into()), ("to", "b".repeat(100).into())],
    );
    let mut out = Out::default();
    r.input("in", good("a".repeat(100)), io, &mut out);
    assert_eq!(out.0[0].1.v, Value::Null);
    assert_eq!(out.0[0].1.q, Quality::Bad);
    // split and join
    let mut sp = build("split", &[]);
    assert_eq!(
        out_of(&mut *sp, io, "a,b,,c"),
        Some(texts(&["a", "b", "", "c"]))
    );
    assert_eq!(
        on(&feed(&mut *sp, io, "in.separator", good("")), "out"),
        Some(texts(&["a,b,,c"]))
    );
    let mut sp = build("split", &[("separator", "/".into())]);
    assert_eq!(
        out_of(&mut *sp, io, "downstream/modbus/t1"),
        Some(texts(&["downstream", "modbus", "t1"]))
    );
    let mut out = Out::default();
    sp.input("in", good("/".repeat(2000)), io, &mut out);
    assert_eq!(
        (out.0[0].1.v.clone(), out.0[0].1.q),
        (Value::Null, Quality::Bad)
    );
    let mut j = build("join", &[("separator", "/".into())]);
    assert_eq!(
        out_of(
            &mut *j,
            io,
            list(&["downstream".into(), Value::UInt(7), Value::Null])
        ),
        Some("downstream/7/".into())
    );
    assert_eq!(out_of(&mut *j, io, "alone"), Some("alone".into()));
}

#[tokio::test(flavor = "multi_thread")]
async fn data_blocks() {
    let e = env().await;
    let io = &e.io;
    let names = texts(&["setpoint", "mode"]);
    let mut o = build("make_object", &[("inputs", names.clone())]);
    assert_eq!(
        on(&feed(&mut *o, io, "in.setpoint", good(21.5)), "out"),
        Some(map(&[
            ("setpoint", Value::Float(21.5)),
            ("mode", Value::Null)
        ]))
    );
    assert_eq!(
        on(&feed(&mut *o, io, "in.mode", good("auto")), "out"),
        Some(map(&[
            ("setpoint", Value::Float(21.5)),
            ("mode", "auto".into())
        ]))
    );
    let mut a = build("make_array", &[("inputs", names)]);
    feed(&mut *a, io, "in.mode", good("auto"));
    assert_eq!(
        on(&feed(&mut *a, io, "in.setpoint", good(1u64)), "out"),
        Some(list(&[Value::UInt(1), "auto".into()]))
    );
    // get: keys and indexes
    let doc = map(&[
        (
            "rows",
            list(&[map(&[("name", "t1".into())]), map(&[("name", "t2".into())])]),
        ),
        ("n", Value::UInt(2)),
    ]);
    let mut g = build("get", &[("path", "rows.1.name".into())]);
    assert_eq!(out_of(&mut *g, io, doc.clone()), Some("t2".into()));
    assert_eq!(
        on(&feed(&mut *g, io, "in.path", good("n")), "out"),
        Some(Value::UInt(2))
    );
    for missing in ["rows.5.name", "rows.x", "n.deeper", "nope"] {
        feed(&mut *g, io, "in.path", good("n"));
        assert_eq!(
            on(&feed(&mut *g, io, "in.path", good(missing)), "out"),
            Some(Value::Null),
            "{missing}"
        );
    }
    assert_eq!(
        on(&feed(&mut *g, io, "in.path", good("")), "out"),
        Some(doc)
    );
    // stats: the numbers of a list
    let mut s = build("stats", &[]);
    let sent = feed(
        &mut *s,
        io,
        "in",
        good(list(&[
            Value::UInt(4),
            "x".into(),
            Value::Float(1.0),
            "7".into(),
        ])),
    );
    assert_eq!(on(&sent, "min"), Some(Value::Float(1.0)));
    assert_eq!(on(&sent, "max"), Some(Value::Float(7.0)));
    assert_eq!(on(&sent, "avg"), Some(Value::Float(4.0)));
    assert_eq!(on(&sent, "sum"), Some(Value::Float(12.0)));
    assert_eq!(on(&sent, "count"), Some(Value::UInt(3)));
    let sent = feed(&mut *s, io, "in", good(list(&[])));
    assert_eq!(on(&sent, "avg"), Some(Value::Null));
    assert_eq!(on(&sent, "count"), Some(Value::UInt(0)));
    // select: the input at `index`
    let mut sel = build("select", &[("inputs", texts(&["a", "b", "c"]))]);
    feed(&mut *sel, io, "in.b", good("second"));
    assert_eq!(
        on(&feed(&mut *sel, io, "in.a", good("first")), "out"),
        Some("first".into())
    );
    assert_eq!(
        on(&feed(&mut *sel, io, "in.index", good(1u64)), "out"),
        Some("second".into())
    );
    for none in [Value::UInt(2), Value::UInt(9), Value::Int(-1)] {
        feed(&mut *sel, io, "in.index", good(0u64));
        assert_eq!(
            on(&feed(&mut *sel, io, "in.index", good(none.clone())), "out"),
            Some(Value::Null),
            "{none:?}"
        );
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn event_blocks_never_act_on_a_start_value() {
    let e = env().await;
    let io = &e.io;
    let fired = |sent: &[(String, Value)], port: &str| on(sent, port).is_some();
    // changed: the first sample starts it, a different one is an event, the same one is not
    let mut c = build("changed", &[]);
    assert!(feed(&mut *c, io, "in", good(1u64)).is_empty());
    assert!(feed(&mut *c, io, "in", good(1u64)).is_empty());
    let sent = feed(&mut *c, io, "in", good(2u64));
    assert_eq!(
        on(&sent, "on_change"),
        Some(map(&[
            ("event", "on_change".into()),
            ("id", Value::UInt(1))
        ]))
    );
    // a start value is where it starts from, also after others
    assert!(feed(&mut *c, io, "in", good(9u64).at_start()).is_empty());
    assert!(feed(&mut *c, io, "in", good(9u64)).is_empty());
    // rising_edge: nothing before counts as false, so the first true is an edge
    let mut r = build("rising_edge", &[]);
    assert!(fired(&feed(&mut *r, io, "in", good(true)), "on_edge"));
    assert!(!fired(&feed(&mut *r, io, "in", good(true)), "on_edge"));
    assert!(!fired(&feed(&mut *r, io, "in", good(false)), "on_edge"));
    assert!(fired(&feed(&mut *r, io, "in", good(5u64)), "on_edge"));
    // but not a true that the start brought (a bool variable that is true)
    let mut r = build("rising_edge", &[]);
    assert!(!fired(
        &feed(&mut *r, io, "in", good(true).at_start()),
        "on_edge"
    ));
    assert!(!fired(&feed(&mut *r, io, "in", good(true)), "on_edge"));
    // falling_edge needs a true before
    let mut f = build("falling_edge", &[]);
    assert!(!fired(&feed(&mut *f, io, "in", good(false)), "on_edge"));
    feed(&mut *f, io, "in", good(true).at_start());
    assert!(fired(&feed(&mut *f, io, "in", good(false)), "on_edge"));
    // counter: every sample counts, a start value does not; reset; the count is its state
    let mut n = build(
        "counter",
        &[("step", Value::UInt(2)), ("initial", Value::UInt(10))],
    );
    assert_eq!(
        on(&feed(&mut *n, io, "in", good(true).at_start()), "out"),
        Some(Value::Int(10))
    );
    assert_eq!(
        on(&feed(&mut *n, io, "in", good(true)), "out"),
        Some(Value::Int(12))
    );
    assert_eq!(
        on(&feed(&mut *n, io, "in", good(true)), "out"),
        Some(Value::Int(14))
    );
    assert!(feed(&mut *n, io, "in", good(Value::Null)).is_empty());
    let mut again = build("counter", &[("step", Value::UInt(2))]);
    again.restore(&n.state().unwrap());
    assert_eq!(
        on(&feed(&mut *again, io, "in", good(1u64)), "out"),
        Some(Value::Int(16))
    );
    assert_eq!(
        on(&feed(&mut *n, io, "reset", good(true)), "out"),
        Some(Value::Int(10))
    );
    assert!(feed(&mut *n, io, "reset", good(false)).is_empty());
    // toggle
    let mut t = build("toggle", &[]);
    assert_eq!(
        on(&feed(&mut *t, io, "in", good(1u64)), "out"),
        Some(Value::Bool(true))
    );
    assert_eq!(
        on(&feed(&mut *t, io, "in", good(1u64)), "out"),
        Some(Value::Bool(false))
    );
    assert!(feed(&mut *t, io, "in", good(1u64).at_start()).is_empty());
    feed(&mut *t, io, "in", good(1u64));
    assert_eq!(
        on(&feed(&mut *t, io, "reset", good(true)), "out"),
        Some(Value::Bool(false))
    );
    // sample_and_hold: the value of `in` at the moment of `trigger`
    let mut h = build("sample_and_hold", &[]);
    assert!(feed(&mut *h, io, "in", good(1.5)).is_empty());
    assert_eq!(
        on(&feed(&mut *h, io, "trigger", good(true)), "out"),
        Some(Value::Float(1.5))
    );
    assert!(feed(&mut *h, io, "in", good(2.5)).is_empty());
    assert!(feed(&mut *h, io, "trigger", good(true).at_start()).is_empty());
    assert_eq!(
        on(&feed(&mut *h, io, "trigger", good(1u64)), "out"),
        Some(Value::Float(2.5))
    );
}

#[tokio::test(flavor = "multi_thread")]
async fn debounce_and_throttle() {
    let e = env().await;
    let io = &e.io;
    // debounce: the last value, once `ms` passed without another
    let mut d = build("debounce", &[("ms", Value::UInt(80))]);
    assert_eq!(d.tick_every(), None);
    assert!(feed(&mut *d, io, "in", good(1u64)).is_empty());
    assert_eq!(d.tick_every(), Some(Duration::from_millis(20)));
    tokio::time::sleep(Duration::from_millis(40)).await;
    assert!(tick(&mut *d).is_empty(), "too early");
    assert!(feed(&mut *d, io, "in", good(2u64)).is_empty());
    tokio::time::sleep(Duration::from_millis(50)).await;
    assert!(
        tick(&mut *d).is_empty(),
        "the second sample started the wait again"
    );
    tokio::time::sleep(Duration::from_millis(50)).await;
    assert_eq!(on(&tick(&mut *d), "out"), Some(Value::UInt(2)));
    assert_eq!(d.tick_every(), None, "no clock while nothing waits");
    // throttle: the first at once, then the latest at the end of the period
    let mut t = build("throttle", &[("ms", Value::UInt(80))]);
    assert_eq!(
        on(&feed(&mut *t, io, "in", good(1u64)), "out"),
        Some(Value::UInt(1))
    );
    assert!(feed(&mut *t, io, "in", good(2u64)).is_empty());
    assert!(feed(&mut *t, io, "in", good(3u64)).is_empty());
    assert!(tick(&mut *t).is_empty());
    tokio::time::sleep(Duration::from_millis(100)).await;
    assert_eq!(on(&tick(&mut *t), "out"), Some(Value::UInt(3)));
    // after a quiet period the next one passes at once
    tokio::time::sleep(Duration::from_millis(100)).await;
    assert_eq!(
        on(&feed(&mut *t, io, "in", good(4u64)), "out"),
        Some(Value::UInt(4))
    );
    // `ms` from its port
    feed(&mut *d, io, "in.ms", good(400u64));
    feed(&mut *d, io, "in", good(5u64));
    assert_eq!(d.tick_every(), Some(Duration::from_millis(50)));
}

#[test]
fn the_second_set_is_in_the_catalog_with_ports_for_every_field() {
    let Value::Array(all) = wyrm_flow::catalog::value() else {
        panic!()
    };
    let entry = |ty: &str| {
        all.iter()
            .find_map(|v| match v {
                Value::Map(m) if m.get("type") == Some(&Value::from(ty)) => Some(m.clone()),
                _ => None,
            })
            .unwrap_or_else(|| panic!("{ty} in the catalog"))
    };
    for ty in [
        "substring",
        "replace",
        "split",
        "join",
        "make_object",
        "make_array",
        "get",
        "stats",
        "changed",
        "rising_edge",
        "falling_edge",
        "counter",
        "toggle",
        "sample_and_hold",
        "select",
        "debounce",
        "throttle",
        "load_value",
        "list_children",
    ] {
        let e = entry(ty);
        assert!(matches!(e.get("category"), Some(Value::Str(c)) if !c.is_empty()));
        assert!(matches!(e.get("description"), Some(Value::Str(d)) if d.len() > 10));
        let Some(Value::Map(types)) = e.get("port_types") else {
            panic!("{ty}: port_types")
        };
        let Some(Value::Array(ins)) = e.get("inputs") else {
            panic!()
        };
        let Some(Value::Array(params)) = e.get("params") else {
            panic!()
        };
        for p in params {
            let Value::Map(p) = p else { panic!() };
            let Some(Value::Str(name)) = p.get("name") else {
                panic!()
            };
            // every field has a port, apart from the list of inputs and a scope
            if name != "inputs" && !name.ends_with("_scope") {
                let port = Value::from(format!("in.{name}"));
                assert_eq!(p.get("port"), Some(&port), "{ty}.{name}");
                assert!(ins.contains(&port), "{ty}.{name}");
            }
            assert_eq!(p.get("echo"), Some(&Value::Bool(true)), "{ty}.{name}");
        }
        for i in ins {
            let Value::Str(i) = i else { panic!() };
            assert!(types.contains_key(i), "{ty}: type of {i}");
        }
    }
    // a read field names its scope parameter
    let e = entry("list_children");
    let Some(Value::Array(params)) = e.get("params") else {
        panic!()
    };
    assert!(params.iter().any(|p| matches!(p, Value::Map(p)
        if p.get("name") == Some(&"path".into()) && p.get("scope") == Some(&"path_scope".into()))));
}

/// Security review 2026-11-10: a number from a port or from the config that is not finite, is
/// negative or is huge never panics a block and never becomes a duration, an index or a size.
#[tokio::test(flavor = "multi_thread")]
async fn numbers_from_ports_are_bounded() {
    let e = env().await;
    let io = &e.io;
    let wild = [
        Value::Float(f64::NAN),
        Value::Float(f64::INFINITY),
        Value::Float(f64::NEG_INFINITY),
        Value::Float(-1.0),
        Value::Int(i64::MIN),
        Value::Float(1e300),
        Value::UInt(u64::MAX),
        Value::from("NaN"),
        Value::from("inf"),
        Value::from("-inf"),
        Value::Null,
        Value::from("text"),
    ];
    // debounce and throttle: `ms` from the port, and from the config
    for ty in ["debounce", "throttle"] {
        for w in &wild {
            let mut n = build(ty, &[]);
            feed(&mut *n, io, "in.ms", good(w.clone()));
            feed(&mut *n, io, "in", good(1u64));
            feed(&mut *n, io, "in", good(2u64));
            let every = n.tick_every();
            assert!(
                every.is_none_or(|d| d <= Duration::from_millis(50)),
                "{ty} {w:?}: {every:?}"
            );
            tick(&mut *n);
            let mut n = build(ty, &[("ms", w.clone())]);
            feed(&mut *n, io, "in", good(1u64));
            feed(&mut *n, io, "in", good(2u64));
            let _ = n.tick_every();
            tick(&mut *n);
        }
    }
    // a NaN on the port leaves the last good `ms`; without one, the default of 500 ms holds
    let mut d = build("debounce", &[("ms", Value::UInt(80))]);
    feed(&mut *d, io, "in.ms", good(f64::NAN));
    assert_eq!(
        d.live_params().unwrap().1.get("ms"),
        Some(&Value::UInt(80)),
        "not stored"
    );
    let mut d = build("debounce", &[("ms", Value::Float(f64::NAN))]);
    feed(&mut *d, io, "in", good(1u64));
    assert_eq!(
        d.tick_every(),
        Some(Duration::from_millis(50)),
        "500 / 4, capped"
    );
    // substring, select, counter, get, round, stopwatch: every wild value on every number
    for w in &wild {
        let mut s = build("substring", &[]);
        feed(&mut *s, io, "in.start", good(w.clone()));
        feed(&mut *s, io, "in.length", good(w.clone()));
        let got = out_of(&mut *s, io, "héllo");
        assert!(
            matches!(&got, Some(Value::Str(t)) if t.len() <= 6) || got.is_none(),
            "substring {w:?}: {got:?}"
        );
        let mut sel = build("select", &[]);
        feed(&mut *sel, io, "in.0", good("first"));
        feed(&mut *sel, io, "in.index", good(w.clone()));
        let mut c = build("counter", &[]);
        feed(&mut *c, io, "in.step", good(w.clone()));
        feed(&mut *c, io, "in.initial", good(w.clone()));
        for _ in 0..3 {
            let sent = feed(&mut *c, io, "in", good(true));
            if let Some(v) = on(&sent, "out") {
                assert!(
                    v.as_f64().is_some_and(f64::is_finite),
                    "counter {w:?}: {v:?}"
                );
            }
        }
        let mut r = build("round", &[]);
        feed(&mut *r, io, "in.precision", good(w.clone()));
        feed(&mut *r, io, "in.min_precision", good(w.clone()));
        feed(&mut *r, io, "in", good(1.23456));
        let mut sw = build("stopwatch", &[("enabled", Value::Bool(true))]);
        for p in ["interval", "step", "modulo", "reset_value"] {
            feed(&mut *sw, io, &format!("in.{p}"), good(w.clone()));
        }
        tick(&mut *sw);
        tick(&mut *sw);
        let mut m = build("modulo", &[]);
        feed(&mut *m, io, "in.modulo", good(w.clone()));
        feed(&mut *m, io, "in", good(w.clone()));
        let mut st = build("stats", &[]);
        feed(&mut *st, io, "in", good(list(&[w.clone(), w.clone()])));
    }
    // a huge start and length give an empty text and a bounded one
    let mut s = build("substring", &[("start", Value::UInt(u64::MAX))]);
    assert_eq!(out_of(&mut *s, io, "abc"), Some("".into()));
    let mut s = build("substring", &[("length", Value::Float(1e300))]);
    let got = out_of(&mut *s, io, "x".repeat(10_000));
    assert!(
        matches!(&got, Some(Value::Str(t)) if t.len() == 4096),
        "{got:?}"
    );
    // a counter that would overflow to infinity stays where it is
    let mut c = build(
        "counter",
        &[
            ("step", Value::Float(1e308)),
            ("initial", Value::Float(1e308)),
        ],
    );
    let sent = feed(&mut *c, io, "in", good(true));
    assert_eq!(on(&sent, "out"), Some(Value::Float(1e308)));
    // get: a very long path, a very deep one and an index past the list
    let mut g = build("get", &[]);
    feed(&mut *g, io, "in", good(list(&[Value::UInt(1)])));
    for path in [
        "9".repeat(40),
        "a.".repeat(5000),
        "0.".repeat(2000),
        "-1".to_owned(),
    ] {
        feed(&mut *g, io, "in.path", good("0"));
        assert_eq!(
            on(&feed(&mut *g, io, "in.path", good(path.clone())), "out"),
            Some(Value::Null),
            "{}…",
            &path[..8.min(path.len())]
        );
    }
    // split and join stay within their bounds whatever the separator
    let mut sp = build("split", &[]);
    feed(&mut *sp, io, "in.separator", good("a"));
    let mut out = Out::default();
    sp.input("in", good("a".repeat(5000)), io, &mut out);
    assert_eq!(out.0[0].1.v, Value::Null);
    let mut j = build("join", &[("separator", "x".repeat(3000).into())]);
    let mut out = Out::default();
    j.input("in", good(texts(&["a", "b", "c"])), io, &mut out);
    assert_eq!(
        (out.0[0].1.v.clone(), out.0[0].1.q),
        (Value::Null, Quality::Bad)
    );
}
