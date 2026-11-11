//! The third set of blocks (ADR 0044, `docs/flow-blocks.md`): every block through
//! `nodes::build` and `input`, and a no-panic run of hostile values on every input.

use std::collections::BTreeMap;
use std::sync::Arc;
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

fn cfg(kv: &[(&str, Value)]) -> BTreeMap<String, Value> {
    kv.iter()
        .map(|(k, v)| ((*k).to_owned(), v.clone()))
        .collect()
}

fn build(ty: &str, kv: &[(&str, Value)]) -> Box<dyn Node> {
    let c = cfg(kv);
    nodes::ports(ty, &c).unwrap_or_else(|e| panic!("{ty}: {e}"));
    nodes::build(ty, "f", "n", &c).unwrap()
}

fn good(v: impl Into<Value>) -> Msg {
    Msg::new(v.into(), Quality::Good, 1)
}

fn feed(n: &mut dyn Node, io: &Io, port: &str, msg: Msg) -> Vec<(String, Msg)> {
    let mut out = Out::default();
    n.input(port, msg, io, &mut out);
    out.0
}

fn on(sent: &[(String, Msg)], port: &str) -> Option<Value> {
    sent.iter()
        .rev()
        .find(|(p, _)| p == port)
        .map(|(_, m)| m.v.clone())
}

/// The value a block sends on `port` for `v` on `input`.
fn value_on(
    n: &mut dyn Node,
    io: &Io,
    input: &str,
    v: impl Into<Value>,
    port: &str,
) -> Option<Value> {
    on(&feed(n, io, input, good(v)), port)
}

fn deep(n: usize) -> Value {
    (0..n).fold(Value::Int(1), |v, _| Value::Array(vec![v]))
}

/// Values a block must take on any input without a panic.
fn hostile() -> Vec<Value> {
    vec![
        Value::Null,
        Value::Float(f64::NAN),
        Value::Float(f64::INFINITY),
        Value::Float(f64::NEG_INFINITY),
        Value::Float(-0.0),
        Value::Float(1e308),
        Value::Int(i64::MIN),
        Value::Int(i64::MAX),
        Value::UInt(u64::MAX),
        Value::Bool(true),
        Value::Str(String::new()),
        Value::Str("x".repeat(1 << 20)),
        Value::Str("%E0%A4%A\u{1b}NaN#zz0x-+,.e-".into()),
        Value::Str("2024-02-30T25:61:61Z".into()),
        Value::Str("previous99999999999years".into()),
        Value::Bytes(vec![0xff; 4096]),
        Value::Array(Vec::new()),
        Value::Map(BTreeMap::new()),
        Value::Array((0..5000).map(|i| Value::Float(i as f64 * 1e300)).collect()),
        Value::Map(
            (0..5000)
                .map(|i| (format!("k{i}"), Value::Int(i)))
                .collect(),
        ),
        // as deep as a decoded value may be (spec README rule 6)
        deep(31),
        Value::Map(BTreeMap::from([
            ("columns".to_owned(), Value::Array(vec!["a".into(); 300])),
            (
                "rows".to_owned(),
                Value::Array(vec![Value::Array(vec![Value::Null; 300]); 50]),
            ),
        ])),
    ]
}

/// A configuration a block of `ty` takes, from the catalog: each required parameter set.
fn sample(ty: &str) -> BTreeMap<String, Value> {
    let t = wyrm_flow::catalog::find(ty).unwrap();
    let mut c = BTreeMap::new();
    for x in t.params.iter().filter(|x| x.required) {
        let v = match x.ty {
            "number" => Value::UInt(1),
            "array" => Value::Array(vec!["a".into()]),
            "map" => Value::Map(BTreeMap::new()),
            _ => Value::from("v"),
        };
        c.insert(x.name.to_owned(), v);
    }
    c
}

#[tokio::test(flavor = "multi_thread")]
async fn no_input_makes_a_block_panic() {
    let e = env().await;
    let io = &e.io;
    let pure: Vec<&str> = wyrm_flow::catalog3::TYPES
        .iter()
        .map(|t| t.ty)
        .filter(|t| wyrm_flow::blocks::TYPES.contains(t))
        // the older blocks this set changed
        .chain(["substring", "replace", "case"])
        .collect();
    assert!(!pure.is_empty());
    for ty in pure {
        let c = sample(ty);
        let ports = nodes::ports(ty, &c).unwrap_or_else(|e| panic!("{ty}: {e}"));
        let mut n = nodes::build(ty, "f", "n", &c).unwrap();
        for (port, _) in &ports.inputs {
            for v in hostile() {
                // a value passed through may be as large as the input; a block makes no larger one
                let cap = (600 * 1024).max(wyrm_core::codec::to_vec(&v).map_or(0, |b| b.len()));
                let mut m = good(v);
                m.q = Quality::Uncertain;
                for (out, m) in feed(&mut *n, io, port, m) {
                    let bytes = wyrm_core::codec::to_vec(&m.v)
                        .unwrap_or_else(|e| panic!("{ty}.{out} from {port}: {e}"));
                    assert!(
                        bytes.len() <= cap,
                        "{ty}.{out} from {port}: {} bytes",
                        bytes.len()
                    );
                    let back: Value = wyrm_core::codec::from_slice(&bytes)
                        .unwrap_or_else(|e| panic!("{ty}.{out} from {port} decodes: {e}"));
                    assert_eq!(
                        wyrm_core::codec::to_vec(&back).unwrap(),
                        bytes,
                        "{ty}.{out} round trip"
                    );
                }
            }
            let mut out = Out::default();
            n.tick(1, &mut out);
        }
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn math_blocks_through_the_engine() {
    let e = env().await;
    let io = &e.io;
    // a constant sends at start only: its start goes through the inbox
    let mut c = build("constant", &[("name", "e".into())]);
    assert_eq!(
        on(
            &feed(&mut *c, io, "__start", good(Value::Null).at_start()),
            "out"
        ),
        Some(Value::Float(std::f64::consts::E))
    );
    assert_eq!(
        value_on(&mut *c, io, "in.name", "sqrt2", "out"),
        Some(Value::Float(std::f64::consts::SQRT_2))
    );
    // a parameter's port, change-only
    let mut p = build("power", &[]);
    assert_eq!(
        value_on(&mut *p, io, "in", 3u64, "out"),
        Some(Value::Int(9))
    );
    assert_eq!(
        value_on(&mut *p, io, "in.exponent", 3u64, "out"),
        Some(Value::Int(27))
    );
    assert_eq!(
        value_on(&mut *p, io, "in.exponent", 3u64, "out"),
        None,
        "unchanged"
    );
    // bound: two outputs, the flag first
    let mut b = build("bound", &[("min", Value::Int(0)), ("max", Value::Int(10))]);
    let sent = feed(&mut *b, io, "in", good(12u64));
    assert_eq!(sent[0].0, "input_out_of_range");
    assert_eq!(on(&sent, "out"), Some(Value::Int(10)));
    // statistics over the variable inputs, a list counts as its numbers
    let mut m = build(
        "median",
        &[("inputs", Value::Array(vec!["a".into(), "b".into()]))],
    );
    feed(
        &mut *m,
        io,
        "in.a",
        good(Value::Array(vec![Value::Int(1), Value::Int(9)])),
    );
    assert_eq!(
        value_on(&mut *m, io, "in.b", 4u64, "out"),
        Some(Value::Int(4))
    );
    // the quality of the inputs travels
    let mut s = build("sin", &[]);
    let sent = feed(
        &mut *s,
        io,
        "in",
        Msg::new(Value::Int(30), Quality::Uncertain, 7),
    );
    assert_eq!(sent[0].1.q, Quality::Uncertain);
    assert_eq!(sent[0].1.t, 7);
    // a constant on an operand calculates nothing by itself
    let mut f = build(
        "format_number",
        &[(
            "values",
            Value::Map(BTreeMap::from([("in".to_owned(), Value::Float(1234.5))])),
        )],
    );
    assert_eq!(
        value_on(&mut *f, io, "in.format", "#,##0.00", "out"),
        Some("1,234.50".into())
    );
}

#[tokio::test(flavor = "multi_thread")]
async fn text_blocks_through_the_engine() {
    let e = env().await;
    let io = &e.io;
    // substring: `end`, below 0 from the end; `length` wins over it
    let mut s = build(
        "substring",
        &[("start", Value::UInt(1)), ("end", Value::Int(-1))],
    );
    assert_eq!(
        value_on(&mut *s, io, "in", "[abc]", "out"),
        Some("abc".into())
    );
    assert_eq!(
        value_on(&mut *s, io, "in.end", 3u64, "out"),
        Some("ab".into())
    );
    assert_eq!(
        value_on(&mut *s, io, "in.length", 1u64, "out"),
        Some("a".into())
    );
    // a config without `end` gives what it gave before
    let mut old = build("substring", &[("start", Value::UInt(2))]);
    assert_eq!(
        value_on(&mut *old, io, "in", "hello", "out"),
        Some("llo".into())
    );
    // replace with a pattern; the replacement is taken as it is
    let mut r = build(
        "replace",
        &[
            ("from", "[0-9]+".into()),
            ("to", "#$1".into()),
            ("regexp", Value::Bool(true)),
        ],
    );
    assert_eq!(
        value_on(&mut *r, io, "in", "a1b22c", "out"),
        Some("a#$1b#$1c".into())
    );
    // a pattern that does not compile replaces nothing; plain mode is unchanged
    assert_eq!(
        value_on(&mut *r, io, "in.from", "(", "out"),
        Some("a1b22c".into())
    );
    let mut plain = build("replace", &[("from", "[0-9]+".into()), ("to", "-".into())]);
    assert_eq!(
        value_on(&mut *plain, io, "in", "a[0-9]+b", "out"),
        Some("a-b".into())
    );
    // a long pattern is refused
    assert_eq!(
        value_on(&mut *r, io, "in.from", "a".repeat(300), "out"),
        None,
        "nothing compiled: the text stays and is unchanged"
    );
    // case: regexp
    let mut c = build(
        "case",
        &[
            ("op", "regexp".into()),
            ("inputs", Value::Array(vec!["c1".into(), "v1".into()])),
            (
                "values",
                Value::Map(BTreeMap::from([
                    ("in.c1".to_owned(), Value::from("^AHU-[0-9]+$")),
                    ("in.v1".to_owned(), Value::from("air")),
                ])),
            ),
            ("else", "other".into()),
        ],
    );
    assert_eq!(
        value_on(&mut *c, io, "in", "AHU-12", "out"),
        Some("air".into())
    );
    assert_eq!(
        value_on(&mut *c, io, "in", "AHU-x", "out"),
        Some("other".into())
    );
    // codecs and JSON
    let mut j = build("json_parse", &[]);
    let sent = feed(&mut *j, io, "in", good(r#"{"t": 21.5}"#));
    assert_eq!(
        on(&sent, "out"),
        Some(Value::Map(BTreeMap::from([(
            "t".to_owned(),
            Value::Float(21.5)
        )])))
    );
    assert_eq!(on(&sent, "parse_error"), Some(Value::Bool(false)));
    let mut h = build("hash", &[("algorithm", "md5".into())]);
    assert_eq!(
        value_on(&mut *h, io, "in", "abc", "out"),
        Some("900150983cd24fb0d6963f7d28e17f72".into())
    );
    let mut d = build("url_decode", &[]);
    assert_eq!(
        value_on(&mut *d, io, "in", "a+b%21", "out"),
        Some("a b!".into())
    );
}
