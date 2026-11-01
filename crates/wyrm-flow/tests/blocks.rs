//! The logic blocks (`wyrm_flow::blocks`, `docs/flow-blocks.md`), driven through `input`/`tick`.

use std::collections::BTreeMap;
use std::sync::{Arc, Mutex};
use wyrm_client::WyrmClient;
use wyrm_core::{Quality, Value};
use wyrm_flow::nodes::{self, Io, Msg, Node, Out};
use wyrm_link_mock::{Mock, MockConfig};
use wyrm_link_sdk::harness::isolated_config;
use wyrm_link_sdk::{LinkConfig, LinkHandle};

struct Env {
    io: Io,
    injected: Arc<Mutex<Vec<String>>>,
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
    let injected = Arc::new(Mutex::new(Vec::new()));
    let seen = injected.clone();
    let io = Io {
        client: WyrmClient::new(session),
        ctx: h.ctx().clone(),
        site: "test".into(),
        flow: "f".into(),
        inject: Arc::new(move |port, _| seen.lock().unwrap().push(port.to_owned())),
    };
    Env {
        io,
        injected,
        _h: h,
    }
}

fn cfg(kv: &[(&str, Value)]) -> BTreeMap<String, Value> {
    kv.iter()
        .map(|(k, v)| ((*k).to_owned(), v.clone()))
        .collect()
}

fn build(ty: &str, kv: &[(&str, Value)]) -> Box<dyn Node> {
    let c = cfg(kv);
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

/// The value sent on `port`, if any.
fn on(sent: &[(String, Value)], port: &str) -> Option<Value> {
    sent.iter().find(|(p, _)| p == port).map(|(_, v)| v.clone())
}

fn names(n: &[&str]) -> Value {
    Value::Array(n.iter().map(|x| Value::from(*x)).collect())
}

#[tokio::test(flavor = "multi_thread")]
async fn math_keeps_integers_and_gives_null_when_not_finite() {
    let e = env().await;
    let io = &e.io;
    let mut add = build("add", &[]);
    assert_eq!(
        on(&feed(&mut *add, io, "in.0", good(2i64)), "out"),
        Some(Value::Int(2))
    );
    assert_eq!(
        on(&feed(&mut *add, io, "in.1", good(3i64)), "out"),
        Some(Value::Int(5))
    );
    // text that parses is a number; a float makes a float
    assert_eq!(
        on(&feed(&mut *add, io, "in.1", good("2.5")), "out"),
        Some(Value::Float(4.5))
    );
    // an integer overflow goes to a float
    let mut add = build("add", &[]);
    feed(&mut *add, io, "in.0", good(i64::MAX));
    let v = on(&feed(&mut *add, io, "in.1", good(1i64)), "out").unwrap();
    assert!(matches!(v, Value::Float(_)), "{v:?}");
    // nothing that is a number: add gives 0, subtract null
    let mut add = build("add", &[]);
    assert_eq!(
        on(&feed(&mut *add, io, "in.0", good("x")), "out"),
        Some(Value::Int(0))
    );
    let mut sub = build("subtract", &[("inputs", names(&["a", "b", "c"]))]);
    assert_eq!(
        on(&feed(&mut *sub, io, "in.a", good("x")), "out"),
        Some(Value::Null)
    );
    feed(&mut *sub, io, "in.a", good(10i64));
    feed(&mut *sub, io, "in.b", good(3i64));
    assert_eq!(
        on(&feed(&mut *sub, io, "in.c", good(2i64)), "out"),
        Some(Value::Int(5))
    );
    let mut mul = build("multiply", &[]);
    assert_eq!(
        on(&feed(&mut *mul, io, "in.0", good(4i64)), "out"),
        Some(Value::Int(4))
    );
    // true is 1: 4 × 1 is still 4, so nothing new goes out
    assert_eq!(on(&feed(&mut *mul, io, "in.1", good(true)), "out"), None);
    assert_eq!(
        on(&feed(&mut *mul, io, "in.1", good(3i64)), "out"),
        Some(Value::Int(12))
    );
    let mut div = build("divide", &[]);
    assert_eq!(
        on(&feed(&mut *div, io, "in.0", good(6i64)), "out"),
        Some(Value::Float(6.0))
    );
    assert_eq!(
        on(&feed(&mut *div, io, "in.1", good(4i64)), "out"),
        Some(Value::Float(1.5))
    );
    assert_eq!(
        on(&feed(&mut *div, io, "in.1", good(0i64)), "out"),
        Some(Value::Null),
        "÷0"
    );
    let mut max = build("max", &[]);
    feed(&mut *max, io, "in.0", good(3i64));
    assert_eq!(
        on(&feed(&mut *max, io, "in.1", good(7.5)), "out"),
        Some(Value::Float(7.5))
    );
    let mut min = build("min", &[]);
    assert_eq!(
        on(&feed(&mut *min, io, "in.0", good(3i64)), "out"),
        Some(Value::Int(3))
    );
    assert_eq!(
        on(&feed(&mut *min, io, "in.1", good(7.5)), "out"),
        None,
        "still 3"
    );
    assert_eq!(
        on(&feed(&mut *min, io, "in.1", good(-1.5)), "out"),
        Some(Value::Float(-1.5))
    );
    let mut abs = build("abs", &[]);
    assert_eq!(
        on(&feed(&mut *abs, io, "in", good(-4i64)), "out"),
        Some(Value::Int(4))
    );
}

#[tokio::test(flavor = "multi_thread")]
async fn outputs_change_only_with_quality() {
    let e = env().await;
    let io = &e.io;
    let mut add = build("add", &[]);
    assert!(on(&feed(&mut *add, io, "in.0", good(1i64)), "out").is_some());
    assert!(
        feed(&mut *add, io, "in.0", good(1i64)).is_empty(),
        "same value"
    );
    // the same value of another quality goes on (honest quality)
    let mut out = Out::default();
    add.input(
        "in.0",
        Msg::new(Value::Int(1), Quality::Bad, 2),
        io,
        &mut out,
    );
    assert_eq!(out.0.len(), 1);
    assert_eq!(out.0[0].1.q, Quality::Bad);
}

#[tokio::test(flavor = "multi_thread")]
async fn round_modulo_and_scale() {
    let e = env().await;
    let io = &e.io;
    let mut r = build("round", &[]);
    assert_eq!(
        on(&feed(&mut *r, io, "in", good(2.5)), "out"),
        Some(Value::Int(3))
    );
    assert_eq!(
        on(&feed(&mut *r, io, "in", good(-2.5)), "out"),
        Some(Value::Int(-3))
    );
    assert_eq!(
        on(&feed(&mut *r, io, "in.precision", good(2i64)), "out"),
        Some(Value::Float(-2.5)),
        "the port sets the parameter"
    );
    let mut r = build("round", &[("precision", Value::Int(2))]);
    assert_eq!(
        on(&feed(&mut *r, io, "in", good(21.4567)), "out"),
        Some(Value::Float(21.46))
    );

    let mut md = build("modulo", &[("modulo", Value::Int(3))]);
    let s = feed(&mut *md, io, "in", good(-7i64));
    assert_eq!(on(&s, "quotient"), Some(Value::Int(-2)), "toward zero");
    assert_eq!(on(&s, "remainder"), Some(Value::Int(2)), "never negative");
    let s = feed(&mut *md, io, "in", good(7.5));
    assert_eq!(
        (on(&s, "quotient"), on(&s, "remainder")),
        (Some(Value::Int(2)), Some(Value::Float(1.5)))
    );
    let s = feed(&mut *md, io, "in.modulo", good(0i64));
    assert_eq!(
        (on(&s, "quotient"), on(&s, "remainder")),
        (Some(Value::Null), Some(Value::Null))
    );

    // scale with a range: 0..1 → 0..100 by default once one range parameter is given
    let mut sc = build("scale", &[("input_max", Value::Int(10))]);
    let s = feed(&mut *sc, io, "in", good(5i64));
    assert_eq!(on(&s, "out"), Some(Value::Float(50.0)));
    assert_eq!(on(&s, "input_out_of_range"), Some(Value::Bool(false)));
    let s = feed(&mut *sc, io, "in", good(12i64));
    assert_eq!(on(&s, "input_out_of_range"), Some(Value::Bool(true)));
    // without one, scale stays k × in + b (identity by default)
    let mut sc = build("scale", &[]);
    let s = feed(&mut *sc, io, "in", good(5i64));
    assert_eq!(on(&s, "out"), Some(Value::Float(5.0)));
    assert_eq!(on(&s, "input_out_of_range"), None);
    // a range port turns the range on
    feed(&mut *sc, io, "in.output_max", good(1000i64));
    assert_eq!(
        on(&feed(&mut *sc, io, "in", good(0.5)), "out"),
        Some(Value::Float(500.0))
    );
}

#[tokio::test(flavor = "multi_thread")]
async fn not_and_if() {
    let e = env().await;
    let io = &e.io;
    let mut not = build("not", &[]);
    for (v, want) in [
        (Value::from("false"), true),
        (Value::from(""), true),
        (Value::from("0"), true),
        (Value::from("abc"), false),
        (Value::Int(2), false),
        (Value::Null, true),
    ] {
        let mut n = build("not", &[]);
        assert_eq!(
            on(&feed(&mut *n, io, "in", good(v.clone())), "out"),
            Some(Value::Bool(want)),
            "{v:?}"
        );
    }
    assert_eq!(
        on(&feed(&mut *not, io, "in", good(true)), "out"),
        Some(Value::Bool(false))
    );

    let mut eq = build("if", &[]);
    feed(&mut *eq, io, "in.0", good("5"));
    assert_eq!(
        on(&feed(&mut *eq, io, "in.1", good(5i64)), "out"),
        Some(Value::Bool(true)),
        "the same number"
    );
    assert_eq!(
        on(&feed(&mut *eq, io, "in.1", good(6i64)), "out"),
        Some(Value::Bool(false))
    );
    // then / else from their ports
    assert_eq!(
        on(&feed(&mut *eq, io, "in.else", good("no")), "out"),
        Some(Value::from("no"))
    );
    let mut gt = build(
        "if",
        &[
            ("op", Value::from(">")),
            ("inputs", names(&["a", "b", "c"])),
            ("then", Value::from("down")),
        ],
    );
    feed(&mut *gt, io, "in.a", good(3i64));
    feed(&mut *gt, io, "in.b", good(2i64));
    assert_eq!(
        on(&feed(&mut *gt, io, "in.c", good(1i64)), "out"),
        Some(Value::from("down")),
        "3 > 2 > 1"
    );
    assert_eq!(
        on(&feed(&mut *gt, io, "in.c", good(2i64)), "out"),
        Some(Value::Bool(false))
    );
    let mut and = build("if", &[("op", Value::from("and"))]);
    feed(&mut *and, io, "in.0", good(true));
    assert_eq!(
        on(&feed(&mut *and, io, "in.1", good(1i64)), "out"),
        Some(Value::Bool(true))
    );
    let mut or = build("if", &[("op", Value::from("or"))]);
    assert_eq!(
        on(&feed(&mut *or, io, "in.0", good(0i64)), "out"),
        Some(Value::Bool(false))
    );
}

#[tokio::test(flavor = "multi_thread")]
async fn hub_sends_the_input_that_changed() {
    let e = env().await;
    let io = &e.io;
    let mut hub = build("hub", &[("inputs", names(&["a", "b", "c"]))]);
    let s = feed(&mut *hub, io, "in.b", good(7i64));
    assert_eq!(on(&s, "index"), Some(Value::UInt(1)));
    assert_eq!(
        on(&s, "out"),
        Some(Value::from(7i64)),
        "the input's value as it came"
    );
    assert!(matches!(on(&s, "on_change"), Some(Value::Map(_))));
    // the same value again still goes out, with a new event
    let s = feed(&mut *hub, io, "in.b", good(7i64));
    assert_eq!(on(&s, "out"), Some(Value::from(7i64)));
    assert!(on(&s, "on_change").is_some());
    // a null is not passed by default
    assert!(feed(&mut *hub, io, "in.a", good(Value::Null)).is_empty());
    let mut keep = build("hub", &[("ignore_null", Value::Bool(false))]);
    assert_eq!(
        on(&feed(&mut *keep, io, "in.0", good(Value::Null)), "out"),
        Some(Value::Null)
    );
}

#[tokio::test(flavor = "multi_thread")]
async fn stopwatch_counts_loops_resets_and_keeps_its_count() {
    let e = env().await;
    let io = &e.io;
    let mut sw = build(
        "stopwatch",
        &[
            ("enabled", Value::Bool(true)),
            ("interval", Value::Float(0.1)),
            ("modulo", Value::Int(3)),
        ],
    );
    assert_eq!(sw.tick_every(), Some(std::time::Duration::from_millis(50)));
    let mut sent = Vec::new();
    for i in 0..8 {
        let mut out = Out::default();
        sw.tick(i, &mut out);
        sent.extend(out.0.into_iter().map(|(p, m)| (p, m.v)));
    }
    // 8 × 50 ms = 4 steps of 100 ms: 1, 2, 0 (looped, with an event), 1
    let counts: Vec<Value> = sent
        .iter()
        .filter(|(p, _)| p == "out")
        .map(|(_, v)| v.clone())
        .collect();
    assert_eq!(
        counts,
        [Value::Int(1), Value::Int(2), Value::Int(0), Value::Int(1)]
    );
    assert_eq!(sent.iter().filter(|(p, _)| p == "on_loop").count(), 1);
    // a hot swap keeps the count
    let st = sw.state().unwrap();
    let mut again = build(
        "stopwatch",
        &[
            ("enabled", Value::Bool(true)),
            ("interval", Value::Float(0.05)),
        ],
    );
    again.restore(&st);
    let mut out = Out::default();
    again.tick(0, &mut out);
    assert_eq!(out.0[0].1.v, Value::Int(2));
    // reset: the reset value at once
    let s = feed(&mut *again, io, "reset", good(true));
    assert_eq!(on(&s, "out"), Some(Value::Int(0)));
    // switched off from its port: no more steps
    feed(&mut *again, io, "in.enabled", good(false));
    let mut out = Out::default();
    again.tick(0, &mut out);
    assert!(out.0.is_empty());
    // loop false: it stops at modulo
    let mut once = build(
        "stopwatch",
        &[
            ("enabled", Value::Bool(true)),
            ("interval", Value::Float(0.05)),
            ("modulo", Value::Int(2)),
            ("loop", Value::Bool(false)),
        ],
    );
    let mut last = Vec::new();
    for i in 0..5 {
        let mut out = Out::default();
        once.tick(i, &mut out);
        last.extend(
            out.0
                .into_iter()
                .filter(|(p, _)| p == "out")
                .map(|(_, m)| m.v),
        );
    }
    assert_eq!(last, [Value::Int(1), Value::Int(2)]);
}

#[tokio::test(flavor = "multi_thread")]
async fn text_blocks_and_variables() {
    let e = env().await;
    let io = &e.io;
    let mut c = build("concat", &[("inputs", names(&["a", "b", "c"]))]);
    feed(&mut *c, io, "in.a", good("t="));
    assert_eq!(
        on(&feed(&mut *c, io, "in.b", good(21.5)), "out"),
        Some(Value::from("t=21.5"))
    );
    let mut strict = build("concat", &[("strict", Value::Bool(true))]);
    assert_eq!(
        on(&feed(&mut *strict, io, "in.0", good("x")), "out"),
        Some(Value::Null)
    );
    let mut len = build("length", &[]);
    assert_eq!(
        on(&feed(&mut *len, io, "in", good("héllo")), "out"),
        Some(Value::UInt(5))
    );
    assert_eq!(
        on(&feed(&mut *len, io, "in", good(3i64)), "out"),
        Some(Value::Null)
    );

    // only a variable sends at start: an operator never does (a deploy fires no command)
    let mut n = build("number", &[("value", Value::from("7"))]);
    n.start(io);
    let mut add = build("add", &[]);
    add.start(io);
    assert_eq!(*e.injected.lock().unwrap(), ["__start"]);
    assert_eq!(
        on(&feed(&mut *n, io, "__start", good(Value::Null)), "out"),
        Some(Value::Int(7))
    );
    assert_eq!(
        on(&feed(&mut *n, io, "in", good("8.5")), "out"),
        Some(Value::Float(8.5))
    );
    let mut b = build("bool", &[]);
    assert_eq!(
        on(&feed(&mut *b, io, "__start", good(Value::Null)), "out"),
        Some(Value::Bool(false))
    );
    let mut s = build("string", &[("value", Value::from("hi"))]);
    assert_eq!(
        on(&feed(&mut *s, io, "in", good(5i64)), "out"),
        Some(Value::from("5"))
    );
}

#[test]
fn config_is_checked() {
    let bad = |ty: &str, kv: &[(&str, Value)]| nodes::ports(ty, &cfg(kv)).unwrap_err();
    assert!(bad("add", &[("oops", Value::Int(1))]).contains("oops"));
    assert!(bad("add", &[("inputs", names(&["a", "a"]))]).contains("twice"));
    assert!(bad("if", &[("inputs", names(&["then", "b"]))]).contains("parameter"));
    assert!(bad("if", &[("op", Value::from("xor"))]).contains("op"));
    let many: Vec<String> = (0..65).map(|i| i.to_string()).collect();
    let many: Vec<&str> = many.iter().map(String::as_str).collect();
    assert!(bad("concat", &[("inputs", names(&many))]).contains("64"));
    // the ports: fixed ones, the parameters' ports, then the variable inputs
    let p = nodes::ports("if", &cfg(&[])).unwrap();
    let ins: Vec<&str> = p.inputs.iter().map(|(n, _)| n.as_str()).collect();
    assert_eq!(ins, ["in.then", "in.else", "in.0", "in.1"]);
}
