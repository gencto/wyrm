//! Every node type of the catalog (`wyrm_flow::catalog::types()`) has at least one case that
//! checks a real output value through `nodes::build` and `Node::input`.
//!
//! The expected values come from the documents, not from the code: `docs/flow-blocks.md`
//! (the logic blocks) and `spec/06-flow-def.md`. The older node types (`expression`, `filter`,
//! `latch`, `delay`, `scale`, `deadband`, `window`, `alarm`, `timer`, `const`) are described
//! there only by name; their cases follow the catalog's descriptions (`src/catalog.rs`).
//!
//! A case is one row of [`cases`]: a type, its config and a list of steps (samples, clock
//! ticks, a paused tokio clock, the start) with what each output must hold. A row where the
//! code and the document disagree keeps the documented value, carries a mismatch id and runs
//! only in its `#[ignore]` test. Types that need zenoh I/O or the engine are listed in
//! [`EXEMPT`] with the test that covers them; the meta test checks both lists against the
//! catalog.

use std::collections::BTreeMap;
use std::fmt::Write as _;
use std::sync::{Arc, Mutex};
use std::time::Duration;
use wyrm_client::WyrmClient;
use wyrm_core::{HistRow, Quality, Sample, Value};
use wyrm_flow::nodes::{self, Io, Msg, Node, Out};
use wyrm_link_mock::{Mock, MockConfig};
use wyrm_link_sdk::harness::isolated_config;
use wyrm_link_sdk::{now_us, LinkConfig, LinkHandle};

// ---------- the environment ----------

struct Env {
    io: Io,
    session: zenoh::Session,
    _h: LinkHandle<Mock>,
}

/// An isolated zenoh session with a mock link at `wy/test/downstream/m`, as `tests/blocks3.rs`.
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
        client: WyrmClient::new(session.clone()),
        ctx: h.ctx().clone(),
        site: "test".into(),
        flow: "f".into(),
        inject: Arc::new(|_, _| {}),
    };
    Env { io, session, _h: h }
}

type Sent = Vec<(String, Msg)>;
type Inbox = Arc<Mutex<Vec<(String, Msg)>>>;

/// The same `Io` with an `inject` that keeps what a node sends to itself.
fn capturing(io: &Io) -> (Io, Inbox) {
    let inbox: Inbox = Arc::default();
    let sink = inbox.clone();
    let io = Io {
        inject: Arc::new(move |p, m| sink.lock().unwrap().push((p.to_owned(), m))),
        ..io.clone()
    };
    (io, inbox)
}

fn config(kv: &[(&'static str, Value)]) -> BTreeMap<String, Value> {
    kv.iter()
        .map(|(k, v)| ((*k).to_owned(), v.clone()))
        .collect()
}

fn build(ty: &str, kv: &[(&'static str, Value)]) -> Result<Box<dyn Node>, String> {
    let c = config(kv);
    nodes::ports(ty, &c).map_err(|e| format!("ports: {e}"))?;
    nodes::build(ty, "f", "n", &c).map_err(|e| format!("build: {e}"))
}

// ---------- values ----------

fn s(x: &str) -> Value {
    Value::Str(x.to_owned())
}

fn n(x: i64) -> Value {
    Value::Int(x)
}

fn fl(x: f64) -> Value {
    Value::Float(x)
}

fn b(x: bool) -> Value {
    Value::Bool(x)
}

fn arr(items: Vec<Value>) -> Value {
    Value::Array(items)
}

fn obj(kv: &[(&str, Value)]) -> Value {
    Value::Map(
        kv.iter()
            .map(|(k, v)| ((*k).to_owned(), v.clone()))
            .collect(),
    )
}

/// A table value (ADR 0044 §2): `columns` and one map per row.
fn tbl(cols: &[&str], rows: Vec<Vec<Value>>) -> Value {
    let rows = rows
        .into_iter()
        .map(|r| {
            Value::Map(
                cols.iter()
                    .zip(r)
                    .map(|(c, v)| ((*c).to_owned(), v))
                    .collect(),
            )
        })
        .collect();
    obj(&[
        ("columns", arr(cols.iter().map(|c| s(c)).collect())),
        ("rows", Value::Array(rows)),
    ])
}

/// Microseconds of an RFC 3339 time.
fn us(t: &str) -> i64 {
    t.parse::<jiff::Timestamp>().unwrap().as_microsecond()
}

/// Microseconds of a wall time in a zone.
fn us_in(y: i16, mo: i8, d: i8, h: i8, mi: i8, tz: &str) -> i64 {
    jiff::civil::date(y, mo, d)
        .at(h, mi, 0, 0)
        .in_tz(tz)
        .unwrap()
        .timestamp()
        .as_microsecond()
}

const DAY: i64 = 86_400_000_000;
/// The degree factors the document writes out (`docs/flow-blocks.md`, Trigonometry).
const RAD: f64 = 0.017453292519943295;
const DEG: f64 = 57.29577951308232;

fn good(v: Value) -> Msg {
    Msg::new(v, Quality::Good, 1)
}

fn msg(v: Value, q: Quality, t: u64) -> Msg {
    Msg::new(v, q, t)
}

// ---------- what an output must hold ----------

#[derive(Clone)]
enum Want {
    /// The value, with integers compared by value (`Int` or `UInt`) and floats exactly.
    V(Value),
    /// An integer (`Int` or `UInt`): the document says the number stays an integer.
    Int(i64),
    /// A float, exactly.
    Float(f64),
    /// Any number within 1e-9 (relative).
    Num(f64),
    /// `null`.
    Null,
    /// An event `{event: <port>, id}`.
    Event,
    /// A table: these columns in this order, and these rows; a cell a row lacks is `null`, and
    /// numbers compare by value.
    Table(Vec<&'static str>, Vec<Vec<Value>>),
    /// A property the document gives.
    Pred(&'static str, fn(&Value) -> bool),
}

fn int(x: i64) -> Want {
    Want::Int(x)
}
fn float(x: f64) -> Want {
    Want::Float(x)
}
fn num(x: f64) -> Want {
    Want::Num(x)
}
fn val(v: Value) -> Want {
    Want::V(v)
}
fn text(x: &str) -> Want {
    Want::V(s(x))
}
fn null() -> Want {
    Want::Null
}
fn table(cols: &[&'static str], rows: Vec<Vec<Value>>) -> Want {
    Want::Table(cols.to_vec(), rows)
}
fn pred(what: &'static str, f: fn(&Value) -> bool) -> Want {
    Want::Pred(what, f)
}

/// Integers as `Int` where they fit, so `Int(5)` and `UInt(5)` are the same.
fn norm(v: &Value) -> Value {
    match v {
        Value::UInt(u) => i64::try_from(*u).map_or(Value::UInt(*u), Value::Int),
        Value::Array(a) => Value::Array(a.iter().map(norm).collect()),
        Value::Map(m) => Value::Map(m.iter().map(|(k, v)| (k.clone(), norm(v))).collect()),
        v => v.clone(),
    }
}

fn as_num(v: &Value) -> Option<f64> {
    match v {
        Value::Int(i) => Some(*i as f64),
        Value::UInt(u) => Some(*u as f64),
        Value::Float(x) => Some(*x),
        _ => None,
    }
}

/// Two cells: numbers by value, the rest structurally.
fn loose(a: &Value, b: &Value) -> bool {
    match (as_num(a), as_num(b)) {
        (Some(x), Some(y)) => x == y || (x - y).abs() <= 1e-9 * y.abs().max(1.0),
        _ => match (a, b) {
            (Value::Array(x), Value::Array(y)) => {
                x.len() == y.len() && x.iter().zip(y).all(|(a, b)| loose(a, b))
            }
            (Value::Map(x), Value::Map(y)) => {
                x.len() == y.len()
                    && x.iter()
                        .zip(y)
                        .all(|((ka, a), (kb, b))| ka == kb && loose(a, b))
            }
            _ => a == b,
        },
    }
}

fn get<'a>(v: &'a Value, k: &str) -> Option<&'a Value> {
    match v {
        Value::Map(m) => m.get(k),
        _ => None,
    }
}

fn rows(v: &Value) -> Vec<Value> {
    match get(v, "rows") {
        Some(Value::Array(a)) => a.clone(),
        _ => Vec::new(),
    }
}

fn columns(v: &Value) -> Vec<String> {
    match get(v, "columns") {
        Some(Value::Array(a)) => a
            .iter()
            .map(|c| match c {
                Value::Str(s) => s.clone(),
                c => format!("{c:?}"),
            })
            .collect(),
        _ => Vec::new(),
    }
}

impl Want {
    fn check(&self, port: &str, v: &Value) -> Result<(), String> {
        let ok = match self {
            Want::V(w) => norm(v) == norm(w),
            Want::Int(w) => matches!(norm(v), Value::Int(i) if i == *w),
            Want::Float(w) => matches!(v, Value::Float(x) if x == w),
            Want::Num(w) => as_num(v).is_some_and(|x| (x - w).abs() <= 1e-9 * w.abs().max(1.0)),
            Want::Null => *v == Value::Null,
            Want::Event => get(v, "event") == Some(&s(port)),
            Want::Table(cols, want) => {
                let have = rows(v);
                columns(v) == *cols
                    && have.len() == want.len()
                    && have.iter().zip(want).all(|(r, w)| {
                        cols.iter()
                            .zip(w)
                            .all(|(c, w)| loose(get(r, c).unwrap_or(&Value::Null), w))
                    })
            }
            Want::Pred(_, f) => f(v),
        };
        if ok {
            Ok(())
        } else {
            Err(format!("{port}: want {}, got {v:?}", self.describe()))
        }
    }

    fn describe(&self) -> String {
        match self {
            Want::V(v) => format!("{v:?}"),
            Want::Int(i) => format!("integer {i}"),
            Want::Float(x) => format!("float {x:?}"),
            Want::Num(x) => format!("number {x}"),
            Want::Null => "null".into(),
            Want::Event => "an event".into(),
            Want::Table(c, r) => format!("table {c:?} {r:?}"),
            Want::Pred(what, _) => (*what).to_owned(),
        }
    }
}

// ---------- a case ----------

#[derive(Clone)]
enum Step {
    /// A sample on a port.
    Feed(&'static str, Msg),
    /// One clock tick at this time (µs).
    Tick(u64),
    /// This many ticks at this time (the stopwatch adds 50 ms per tick).
    Ticks(u32, u64),
    /// One tick at the wall clock plus this many ms (`delay` keeps its due time in wall time).
    TickIn(u64),
    /// The paused tokio clock moves on (ms): `debounce` and `throttle` read it.
    Advance(u64),
    /// The node starts (what it injects into itself is fed back in).
    Start,
    /// The node starts with no edge into it (spec 06 0.2.30: a pure block calculates).
    StartUnwired,
    /// The last value sent on the port, over all steps so far.
    Is(&'static str, Want),
    /// The port's value was sent by the last step.
    Sent(&'static str, Want),
    /// The last step sent nothing on the port.
    Quiet(&'static str),
    /// The quality and the time of the last value on the port.
    Q(&'static str, Quality),
    T(&'static str, u64),
    /// The last value on the port is a time between the start and the end of the last step.
    Now(&'static str),
    /// The last step wrote a log line that holds each text.
    Logged(&'static [&'static str]),
    /// The last step wrote no log line.
    NoLog,
}

use Step::*;

fn feed(port: &'static str, v: Value) -> Step {
    Feed(port, good(v))
}

fn feed_m(port: &'static str, m: Msg) -> Step {
    Feed(port, m)
}

/// An event `{event, id}` on a port, as an event block sends it.
fn event(port: &'static str, id: u64) -> Step {
    Feed(
        port,
        good(obj(&[("event", s("trigger")), ("id", Value::UInt(id))])),
    )
}

#[derive(Clone)]
struct Case {
    ty: &'static str,
    cfg: Vec<(&'static str, Value)>,
    steps: Vec<Step>,
    /// The document and the code disagree: the id of the `#[ignore]` test that runs this row.
    mismatch: Option<&'static str>,
    line: u32,
}

/// Samples on ports, then the last value on `port`.
#[track_caller]
fn c(
    ty: &'static str,
    cfg: Vec<(&'static str, Value)>,
    feeds: Vec<(&'static str, Value)>,
    port: &'static str,
    want: Want,
) -> Case {
    let mut steps: Vec<Step> = feeds.into_iter().map(|(p, v)| feed(p, v)).collect();
    steps.push(Is(port, want));
    sq(ty, cfg, steps)
}

/// A sequence of steps.
#[track_caller]
fn sq(ty: &'static str, cfg: Vec<(&'static str, Value)>, steps: Vec<Step>) -> Case {
    Case {
        ty,
        cfg,
        steps,
        mismatch: None,
        line: std::panic::Location::caller().line(),
    }
}

impl Case {
    /// Marks a row that asserts the document where the code differs (none today: the two
    /// found were settled on 2026-11-12 by fixing the documents). Its id needs an
    /// `#[ignore]` test that calls `run_mismatch`.
    #[allow(dead_code)]
    fn mismatch(mut self, id: &'static str) -> Self {
        self.mismatch = Some(id);
        self
    }
}

// ---------- a log capture for `trace` ----------

#[derive(Clone, Default)]
struct Logs(Arc<Mutex<Vec<String>>>);

struct Fields(String);

impl tracing::field::Visit for Fields {
    fn record_debug(&mut self, f: &tracing::field::Field, v: &dyn std::fmt::Debug) {
        let _ = write!(self.0, "{}={:?} ", f.name(), v);
    }
}

impl tracing::Subscriber for Logs {
    fn register_callsite(
        &self,
        _: &'static tracing::Metadata<'static>,
    ) -> tracing::subscriber::Interest {
        // other tests of this binary may have cached the interest of the callsite
        tracing::subscriber::Interest::sometimes()
    }
    fn enabled(&self, _: &tracing::Metadata<'_>) -> bool {
        true
    }
    fn max_level_hint(&self) -> Option<tracing::level_filters::LevelFilter> {
        Some(tracing::level_filters::LevelFilter::TRACE)
    }
    fn new_span(&self, _: &tracing::span::Attributes<'_>) -> tracing::span::Id {
        tracing::span::Id::from_u64(1)
    }
    fn record(&self, _: &tracing::span::Id, _: &tracing::span::Record<'_>) {}
    fn record_follows_from(&self, _: &tracing::span::Id, _: &tracing::span::Id) {}
    fn event(&self, e: &tracing::Event<'_>) {
        let mut f = Fields(String::new());
        e.record(&mut f);
        self.0.lock().unwrap().push(f.0);
    }
    fn enter(&self, _: &tracing::span::Id) {}
    fn exit(&self, _: &tracing::span::Id) {}
}

// ---------- the runner ----------

/// One case; `Err` names the first step that did not hold.
async fn run(case: &Case, base: &Io) -> Result<(), String> {
    let mut node = build(case.ty, &case.cfg)?;
    let (io, inbox) = capturing(base);
    let logs = Logs::default();
    let mut state: BTreeMap<String, Msg> = BTreeMap::new();
    let mut last: Sent = Vec::new();
    let mut lines: Vec<String> = Vec::new();
    let (mut before, mut after) = (0u64, 0u64);
    for (i, step) in case.steps.iter().enumerate() {
        let fail = |e: String| format!("step {i}: {e}");
        let act = |node: &mut Box<dyn Node>, step: &Step| -> Sent {
            let mut out = Out::default();
            match step {
                Feed(p, m) => node.input(p, m.clone(), &io, &mut out),
                Tick(t) => node.tick(*t, &mut out),
                Ticks(k, t) => {
                    for _ in 0..*k {
                        node.tick(*t, &mut out);
                    }
                }
                TickIn(ms) => node.tick(now_us() + ms * 1000, &mut out),
                Start | StartUnwired => {
                    if matches!(step, StartUnwired) {
                        node.unwired();
                    }
                    node.start(&io);
                    let injected: Vec<_> = inbox.lock().unwrap().drain(..).collect();
                    for (p, m) in injected {
                        node.input(&p, m, &io, &mut out);
                    }
                }
                _ => {}
            }
            out.0
        };
        match step {
            Advance(ms) => tokio::time::advance(Duration::from_millis(*ms)).await,
            Feed(..) | Tick(_) | Ticks(..) | TickIn(_) | Start | StartUnwired => {
                logs.0.lock().unwrap().clear();
                before = now_us();
                last = tracing::subscriber::with_default(logs.clone(), || act(&mut node, step));
                after = now_us();
                lines = logs.0.lock().unwrap().clone();
                for (p, m) in &last {
                    state.insert(p.clone(), m.clone());
                }
            }
            Is(p, w) => match state.get(*p) {
                Some(m) => w.check(p, &m.v).map_err(fail)?,
                None => return Err(fail(format!("{p}: nothing sent, want {}", w.describe()))),
            },
            Sent(p, w) => match last.iter().rev().find(|(q, _)| q == p) {
                Some((_, m)) => w.check(p, &m.v).map_err(fail)?,
                None => {
                    return Err(fail(format!(
                        "{p}: not sent by the last step, want {}",
                        w.describe()
                    )))
                }
            },
            Quiet(p) => {
                if let Some((_, m)) = last.iter().find(|(q, _)| q == p) {
                    return Err(fail(format!("{p}: want nothing, got {:?}", m.v)));
                }
            }
            Q(p, q) => match state.get(*p) {
                Some(m) if m.q == *q => {}
                m => return Err(fail(format!("{p}: want quality {q:?}, got {m:?}"))),
            },
            T(p, t) => match state.get(*p) {
                Some(m) if m.t == *t => {}
                m => return Err(fail(format!("{p}: want time {t}, got {m:?}"))),
            },
            Now(p) => match state.get(*p).and_then(|m| as_num(&m.v)) {
                Some(x) if x >= before as f64 && x <= after as f64 => {}
                x => {
                    return Err(fail(format!(
                        "{p}: want a time in {before}..={after}, got {x:?}"
                    )))
                }
            },
            Logged(texts) => {
                if !lines.iter().any(|l| texts.iter().all(|t| l.contains(t))) {
                    return Err(fail(format!(
                        "want a log line with {texts:?}, got {lines:?}"
                    )));
                }
            }
            NoLog => {
                if !lines.is_empty() {
                    return Err(fail(format!("want no log line, got {lines:?}")));
                }
            }
        }
    }
    Ok(())
}

/// Run the cases that `pick` selects in a paused tokio clock, each with its own node; the
/// failures, one line each.
fn run_cases(pick: impl Fn(&Case) -> bool) -> Vec<String> {
    let rt = tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()
        .unwrap();
    let env = rt.block_on(env());
    let io = env.io.clone();
    let chosen: Vec<Case> = cases().into_iter().filter(|c| pick(c)).collect();
    assert!(!chosen.is_empty(), "no case chosen");
    let failures = std::thread::spawn(move || {
        let paused = tokio::runtime::Builder::new_current_thread()
            .enable_time()
            .start_paused(true)
            .build()
            .unwrap();
        paused.block_on(async {
            let mut failures = Vec::new();
            for case in &chosen {
                if let Err(e) = run(case, &io).await {
                    failures.push(format!(
                        "tests/every_block.rs:{} {}: {e}",
                        case.line, case.ty
                    ));
                }
            }
            failures
        })
    })
    .join()
    .unwrap();
    rt.block_on(async move { drop(env) });
    failures
}

#[test]
fn every_documented_case_holds() {
    let failures = run_cases(|c| c.mismatch.is_none());
    assert!(
        failures.is_empty(),
        "{} case(s) failed:\n{}",
        failures.len(),
        failures.join("\n")
    );
}

/// The rows of one mismatch: they assert the document, so they fail while the code differs.
#[allow(dead_code)]
fn run_mismatch(id: &str) {
    let failures = run_cases(|c| c.mismatch == Some(id));
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}

// ---------- the cases, by catalog category ----------

fn cases() -> Vec<Case> {
    [
        variables(),
        math(),
        trigonometry(),
        statistics(),
        logic(),
        events(),
        text_blocks(),
        codecs(),
        data(),
        dates(),
        tables(),
        older(),
        rules(),
        edges(),
    ]
    .concat()
}

/// Variables: `number`, `string`, `bool`, `constant`, `table` (send their value at start).
fn variables() -> Vec<Case> {
    let long = "x".repeat(4097);
    vec![
        sq(
            "number",
            vec![("value", n(5))],
            vec![Start, Is("out", num(5.0))],
        ),
        sq("number", vec![], vec![Start, Is("out", num(0.0))]),
        // text that parses is a number
        sq(
            "number",
            vec![("value", n(5))],
            vec![Start, feed("in", s(" 7 ")), Is("out", num(7.0))],
        ),
        sq(
            "string",
            vec![("value", s("ahu"))],
            vec![Start, Is("out", text("ahu"))],
        ),
        sq("string", vec![], vec![Start, Is("out", text(""))]),
        // a `string` longer than 4 KiB is null
        sq(
            "string",
            vec![("value", s("a"))],
            vec![Start, feed("in", s(&long)), Is("out", null())],
        ),
        sq("bool", vec![], vec![Start, Is("out", val(b(false)))]),
        sq(
            "bool",
            vec![("value", b(true))],
            vec![Start, Is("out", val(b(true)))],
        ),
        // as a bool: text "false" is false, a number is true unless it is 0
        sq(
            "bool",
            vec![("value", b(true))],
            vec![Start, feed("in", s("false")), Is("out", val(b(false)))],
        ),
        sq(
            "bool",
            vec![],
            vec![Start, feed("in", n(2)), Is("out", val(b(true)))],
        ),
        sq(
            "constant",
            vec![],
            vec![Start, Is("out", float(std::f64::consts::PI))],
        ),
        sq(
            "constant",
            vec![("name", s("e"))],
            vec![Start, Is("out", float(std::f64::consts::E))],
        ),
        sq(
            "constant",
            vec![("name", s("sqrt2"))],
            vec![Start, Is("out", float(std::f64::consts::SQRT_2))],
        ),
        sq(
            "constant",
            vec![("name", s("ln2"))],
            vec![Start, Is("out", float(std::f64::consts::LN_2))],
        ),
        sq(
            "constant",
            vec![("name", s("ln10"))],
            vec![Start, Is("out", float(std::f64::consts::LN_10))],
        ),
        sq(
            "constant",
            vec![("name", s("log2e"))],
            vec![Start, Is("out", float(std::f64::consts::LOG2_E))],
        ),
        sq(
            "constant",
            vec![("name", s("log10e"))],
            vec![Start, Is("out", float(std::f64::consts::LOG10_E))],
        ),
        sq(
            "table",
            vec![("value", tbl(&["a"], vec![vec![n(1)]]))],
            vec![Start, Is("out", table(&["a"], vec![vec![n(1)]]))],
        ),
        // every table input also takes a list of maps
        sq(
            "table",
            vec![("value", tbl(&["a"], vec![vec![n(1)]]))],
            vec![
                Start,
                feed(
                    "in",
                    arr(vec![obj(&[("x", n(1)), ("y", n(2))]), obj(&[("y", n(3))])]),
                ),
                Is(
                    "out",
                    table(&["x", "y"], vec![vec![n(1), n(2)], vec![Value::Null, n(3)]]),
                ),
            ],
        ),
    ]
}

/// Math: arithmetic, rounding, number formatting.
fn math() -> Vec<Case> {
    let two = |a: Value, b: Value| vec![("in.0", a), ("in.1", b)];
    vec![
        // add: the sum stays an integer while it fits; no number gives 0
        c("add", vec![], two(n(2), n(3)), "out", int(5)),
        c("add", vec![], two(s(" 5 "), fl(2.5)), "out", num(7.5)),
        c("add", vec![], two(b(true), n(2)), "out", int(3)),
        c("add", vec![], two(s("abc"), Value::Null), "out", int(0)),
        c(
            "add",
            vec![],
            two(n(i64::MAX), n(1)),
            "out",
            float(i64::MAX as f64 + 1.0),
        ),
        // subtract: the first minus the others; no number gives null
        c("subtract", vec![], two(n(10), n(4)), "out", int(6)),
        c(
            "subtract",
            vec![("inputs", arr(vec![s("a"), s("b"), s("c")]))],
            vec![("in.a", n(10)), ("in.b", n(4)), ("in.c", fl(0.5))],
            "out",
            num(5.5),
        ),
        c("subtract", vec![], two(s("x"), Value::Null), "out", null()),
        // multiply: the product; no number gives null
        c("multiply", vec![], two(n(4), n(3)), "out", int(12)),
        c("multiply", vec![], two(n(4), fl(2.5)), "out", num(10.0)),
        c("multiply", vec![], two(s("x"), s("y")), "out", null()),
        // divide: always a float; a result that is not finite is null
        c("divide", vec![], two(n(7), n(2)), "out", float(3.5)),
        c("divide", vec![], two(n(6), n(3)), "out", float(2.0)),
        c("divide", vec![], two(n(1), n(0)), "out", null()),
        c("max", vec![], two(n(3), n(7)), "out", num(7.0)),
        c("max", vec![], two(n(3), s("x")), "out", num(3.0)),
        c("min", vec![], two(n(3), s("1")), "out", num(1.0)),
        c("abs", vec![], vec![("in", n(-5))], "out", int(5)),
        c("abs", vec![], vec![("in", fl(-2.5))], "out", float(2.5)),
        // an overflow of an integer is a float
        c(
            "abs",
            vec![],
            vec![("in", n(i64::MIN))],
            "out",
            float(-(i64::MIN as f64)),
        ),
        // round: halves away from 0; 0 places is an integer
        c("round", vec![], vec![("in", fl(2.5))], "out", int(3)),
        c("round", vec![], vec![("in", fl(-2.5))], "out", int(-3)),
        c(
            "round",
            vec![("precision", n(2))],
            vec![("in", fl(1.23456))],
            "out",
            num(1.23),
        ),
        // text: `precision` places, trailing zeros trimmed down to `min_precision`
        c(
            "round",
            vec![("precision", n(3))],
            vec![("in", fl(2.5))],
            "text",
            text("2.500"),
        ),
        c(
            "round",
            vec![("precision", n(3)), ("min_precision", n(1))],
            vec![("in", n(2))],
            "text",
            text("2.0"),
        ),
        c(
            "round",
            vec![("precision", n(3)), ("min_precision", n(0))],
            vec![("in", fl(1.2))],
            "text",
            text("1.2"),
        ),
        // modulo: a quotient toward 0, a remainder never negative; by 0 both null
        c(
            "modulo",
            vec![("modulo", n(3))],
            vec![("in", n(-7))],
            "quotient",
            int(-2),
        ),
        c(
            "modulo",
            vec![("modulo", n(3))],
            vec![("in", n(-7))],
            "remainder",
            num(2.0),
        ),
        c(
            "modulo",
            vec![("modulo", n(2))],
            vec![("in", fl(7.5))],
            "remainder",
            num(1.5),
        ),
        c(
            "modulo",
            vec![("modulo", n(0))],
            vec![("in", n(7))],
            "quotient",
            null(),
        ),
        c(
            "modulo",
            vec![("modulo", n(0))],
            vec![("in", n(7))],
            "remainder",
            null(),
        ),
        // stats: the numbers of a list; an empty list gives count 0 and null
        c(
            "stats",
            vec![],
            vec![("in", arr(vec![n(1), n(2), n(3), s("x")]))],
            "sum",
            num(6.0),
        ),
        c(
            "stats",
            vec![],
            vec![("in", arr(vec![n(1), n(2), n(3)]))],
            "avg",
            num(2.0),
        ),
        c(
            "stats",
            vec![],
            vec![("in", arr(vec![n(4), n(1), n(9)]))],
            "min",
            num(1.0),
        ),
        c(
            "stats",
            vec![],
            vec![("in", arr(vec![n(4), n(1), n(9)]))],
            "max",
            num(9.0),
        ),
        c(
            "stats",
            vec![],
            vec![("in", arr(vec![n(4), n(1), n(9)]))],
            "count",
            num(3.0),
        ),
        c(
            "stats",
            vec![],
            vec![("in", arr(vec![]))],
            "count",
            num(0.0),
        ),
        c("stats", vec![], vec![("in", arr(vec![]))], "avg", null()),
        // factorial: of the whole part; below 1: 1; an integer up to 20!, a float to 170!
        c("factorial", vec![], vec![("in", n(5))], "out", int(120)),
        c("factorial", vec![], vec![("in", fl(5.7))], "out", int(120)),
        c("factorial", vec![], vec![("in", n(-3))], "out", num(1.0)),
        c(
            "factorial",
            vec![],
            vec![("in", n(20))],
            "out",
            int(2_432_902_008_176_640_000),
        ),
        c(
            "factorial",
            vec![],
            vec![("in", n(21))],
            "out",
            float((1..=21).map(f64::from).product()),
        ),
        c(
            "factorial",
            vec![],
            vec![("in", n(170))],
            "out",
            num((1..=170).map(f64::from).product()),
        ),
        c("factorial", vec![], vec![("in", n(171))], "out", null()),
        // log: base 10 by default; in at most 0 is null
        c("log", vec![], vec![("in", n(1000))], "out", num(3.0)),
        c(
            "log",
            vec![("base", n(2))],
            vec![("in", n(8))],
            "out",
            num(3.0),
        ),
        c("log", vec![], vec![("in", n(0))], "out", null()),
        c("log", vec![], vec![("in", n(-1))], "out", null()),
        // power: an integer stays an integer while it fits
        c("power", vec![], vec![("in", n(3))], "out", int(9)),
        c(
            "power",
            vec![("exponent", n(10))],
            vec![("in", n(2))],
            "out",
            int(1024),
        ),
        c(
            "power",
            vec![("exponent", fl(0.5))],
            vec![("in", n(16))],
            "out",
            num(4.0),
        ),
        // root: an odd whole degree of a negative; an exact root is a whole number
        c("root", vec![], vec![("in", n(16))], "out", num(4.0)),
        c(
            "root",
            vec![("degree", n(3))],
            vec![("in", n(-8))],
            "out",
            num(-2.0),
        ),
        c(
            "root",
            vec![("degree", n(3))],
            vec![("in", n(27))],
            "out",
            pred("exactly 3", |v| as_num(v) == Some(3.0)),
        ),
        c("root", vec![], vec![("in", n(-8))], "out", null()),
        // bound: max applies first, then min
        c(
            "bound",
            vec![("min", n(0)), ("max", n(10))],
            vec![("in", n(15))],
            "out",
            num(10.0),
        ),
        c(
            "bound",
            vec![("min", n(0)), ("max", n(10))],
            vec![("in", n(15))],
            "input_out_of_range",
            val(b(true)),
        ),
        c(
            "bound",
            vec![("min", n(0)), ("max", n(10))],
            vec![("in", n(5))],
            "input_out_of_range",
            val(b(false)),
        ),
        c(
            "bound",
            vec![("min", n(20)), ("max", n(10))],
            vec![("in", n(15))],
            "out",
            num(20.0),
        ),
        c(
            "bound",
            vec![("min", n(0))],
            vec![("in", n(-5))],
            "out",
            num(0.0),
        ),
        c(
            "bound",
            vec![("min", n(0))],
            vec![("in", n(500))],
            "out",
            num(500.0),
        ),
        // round_up / round_down: text has exactly `precision` places
        c("round_up", vec![], vec![("in", fl(2.1))], "out", num(3.0)),
        c(
            "round_up",
            vec![("precision", n(2))],
            vec![("in", fl(1.234))],
            "out",
            num(1.24),
        ),
        c(
            "round_up",
            vec![("precision", n(2))],
            vec![("in", fl(1.5))],
            "text",
            text("1.50"),
        ),
        c("round_down", vec![], vec![("in", fl(2.9))], "out", num(2.0)),
        c(
            "round_down",
            vec![("precision", n(2))],
            vec![("in", fl(1.239))],
            "out",
            num(1.23),
        ),
        c(
            "round_down",
            vec![("precision", n(1))],
            vec![("in", n(4))],
            "text",
            text("4.0"),
        ),
        // format_number patterns
        c(
            "format_number",
            vec![],
            vec![("in", fl(1234567.891))],
            "out",
            text("1,234,567.891"),
        ),
        c(
            "format_number",
            vec![("format", s("#.##"))],
            vec![("in", fl(0.5))],
            "out",
            text(".5"),
        ),
        c(
            "format_number",
            vec![("format", s("0.00"))],
            vec![("in", fl(0.5))],
            "out",
            text("0.50"),
        ),
        c(
            "format_number",
            vec![("format", s("0.0%"))],
            vec![("in", fl(0.256))],
            "out",
            text("25.6%"),
        ),
        c(
            "format_number",
            vec![("format", s("€ #,##0.00"))],
            vec![("in", fl(1234.5))],
            "out",
            text("€ 1,234.50"),
        ),
        c(
            "format_number",
            vec![
                ("format", s("#,##0.00")),
                ("decimal_separator", s(",")),
                ("group_separator", s(".")),
            ],
            vec![("in", fl(1234.5))],
            "out",
            text("1.234,50"),
        ),
        c(
            "format_number",
            vec![("format", s("#,##0.0")), ("group_separator", s(""))],
            vec![("in", fl(1234.5))],
            "out",
            text("1234.5"),
        ),
        c(
            "format_number",
            vec![("format", s("abc"))],
            vec![("in", n(5))],
            "out",
            null(),
        ),
        // parse_number: the first number in a text
        c(
            "parse_number",
            vec![],
            vec![("in", s("abc12.5kg"))],
            "out",
            num(12.5),
        ),
        c(
            "parse_number",
            vec![],
            vec![("in", s("1,234.5"))],
            "out",
            num(1234.5),
        ),
        c(
            "parse_number",
            vec![],
            vec![("in", s("#ff"))],
            "out",
            num(255.0),
        ),
        c(
            "parse_number",
            vec![],
            vec![("in", s("0xff"))],
            "out",
            num(255.0),
        ),
        c("parse_number", vec![], vec![("in", n(7))], "out", num(7.0)),
    ]
}

/// Trigonometry in degrees, with the factors the document writes out.
fn trigonometry() -> Vec<Case> {
    #[track_caller]
    fn one(ty: &'static str, x: f64, want: Want) -> Case {
        c(ty, vec![], vec![("in", fl(x))], "out", want)
    }
    vec![
        one("sin", 30.0, float((RAD * 30.0).sin())),
        one("cos", 60.0, float((RAD * 60.0).cos())),
        one("tan", 45.0, float((RAD * 45.0).tan())),
        one("cot", 45.0, num(1.0)),
        one("cot", 0.0, null()),
        one("asin", 0.5, float(DEG * 0.5f64.asin())),
        one("asin", 2.0, null()),
        one("acos", 0.5, float(DEG * 0.5f64.acos())),
        one("acos", -1.5, null()),
        one("atan", 1.0, num(45.0)),
        // the angle of the point (x, in)
        c(
            "atan",
            vec![("x", n(-1))],
            vec![("in", n(1))],
            "out",
            num(135.0),
        ),
        one("to_degrees", std::f64::consts::PI, num(180.0)),
        one("to_radians", 180.0, num(std::f64::consts::PI)),
        one("to_degrees", 2.0, float(DEG * 2.0)),
        one("to_radians", 2.0, float(RAD * 2.0)),
    ]
}

/// Statistics over the variable inputs; a list on an input gives its numbers.
fn statistics() -> Vec<Case> {
    let list = |xs: &[i64]| vec![("in.0", arr(xs.iter().map(|x| n(*x)).collect()))];
    vec![
        c(
            "average",
            vec![],
            vec![("in.0", n(2)), ("in.1", n(4))],
            "out",
            num(3.0),
        ),
        c("average", vec![], list(&[1, 2, 3, 4]), "out", num(2.5)),
        c("average", vec![], vec![("in.0", s("x"))], "out", null()),
        c("median", vec![], list(&[3, 1, 2]), "out", num(2.0)),
        c("median", vec![], list(&[4, 1, 3, 2]), "out", num(2.5)),
        c("mode", vec![], list(&[1, 2, 2, 3]), "out", num(2.0)),
        // a tie goes to the value that got there first
        c("mode", vec![], list(&[5, 7]), "out", num(5.0)),
        // null and empty text do not count
        c(
            "mode",
            vec![],
            vec![(
                "in.0",
                arr(vec![Value::Null, s(""), Value::Null, s(""), n(4)]),
            )],
            "out",
            num(4.0),
        ),
        // of the population (÷ n)
        c(
            "variance",
            vec![],
            list(&[2, 4, 4, 4, 5, 5, 7, 9]),
            "out",
            num(4.0),
        ),
        c(
            "std_deviation",
            vec![],
            list(&[2, 4, 4, 4, 5, 5, 7, 9]),
            "out",
            num(2.0),
        ),
        c(
            "variance",
            vec![],
            vec![("in.0", arr(vec![]))],
            "out",
            null(),
        ),
    ]
}

/// Logic: `not`, `if`, `case`, `select`, `hub`, `stopwatch`, `trace`, `router`, `event_gate`,
/// `catch_error`.
fn logic() -> Vec<Case> {
    let pair = |a: Value, b: Value| vec![("in.0", a), ("in.1", b)];
    let case_cfg = || {
        vec![
            ("op", s(">=")),
            ("inputs", arr(vec![s("c1"), s("v1"), s("c2"), s("v2")])),
            (
                "values",
                obj(&[
                    ("in.c1", n(90)),
                    ("in.v1", s("high")),
                    ("in.c2", n(10)),
                    ("in.v2", s("normal")),
                ]),
            ),
            ("else", s("low")),
        ]
    };
    let router_cfg = |single: bool| {
        vec![
            ("inputs", arr(vec![s("high"), s("low")])),
            ("op", s(">=")),
            ("values", obj(&[("in.high", n(90)), ("in.low", n(0))])),
            ("single_output", b(single)),
        ]
    };
    let error_event = obj(&[
        ("event", s("error")),
        ("id", n(1)),
        ("code", n(0x41)),
        ("message", s("boom")),
    ]);
    vec![
        c("not", vec![], vec![("in", b(true))], "out", val(b(false))),
        c("not", vec![], vec![("in", n(0))], "out", val(b(true))),
        c("not", vec![], vec![("in", s("false"))], "out", val(b(true))),
        c(
            "not",
            vec![],
            vec![("in", Value::Null)],
            "out",
            val(b(true)),
        ),
        // if `=`: the same number in another form counts
        c("if", vec![], pair(n(5), s("5")), "out", val(b(true))),
        c("if", vec![], pair(n(5), n(6)), "out", val(b(false))),
        c(
            "if",
            vec![("then", s("yes")), ("else", s("no"))],
            pair(n(5), n(5)),
            "out",
            text("yes"),
        ),
        c(
            "if",
            vec![("op", s(">"))],
            pair(n(3), n(2)),
            "out",
            val(b(true)),
        ),
        c(
            "if",
            vec![
                ("op", s(">")),
                ("inputs", arr(vec![s("a"), s("b"), s("c")])),
            ],
            vec![("in.a", n(3)), ("in.b", n(2)), ("in.c", n(2))],
            "out",
            val(b(false)),
        ),
        // fewer than two inputs do not pass
        c(
            "if",
            vec![("op", s(">")), ("inputs", arr(vec![s("a")]))],
            vec![("in.a", n(3))],
            "out",
            val(b(false)),
        ),
        c(
            "if",
            vec![("op", s("and"))],
            pair(b(true), n(0)),
            "out",
            val(b(false)),
        ),
        c(
            "if",
            vec![("op", s("or"))],
            pair(b(false), n(2)),
            "out",
            val(b(true)),
        ),
        c(
            "if",
            vec![
                ("op", s("!=")),
                ("inputs", arr(vec![s("a"), s("b"), s("c")])),
            ],
            vec![("in.a", n(1)), ("in.b", n(2)), ("in.c", n(3))],
            "out",
            val(b(true)),
        ),
        c(
            "if",
            vec![("op", s("contains"))],
            pair(s("hello"), s("ell")),
            "out",
            val(b(true)),
        ),
        c(
            "if",
            vec![("op", s("starts_with"))],
            pair(s("hello"), s("lo")),
            "out",
            val(b(false)),
        ),
        c(
            "if",
            vec![("op", s("ends_with"))],
            pair(s("hello"), s("lo")),
            "out",
            val(b(true)),
        ),
        // case: the value of the first pair that matches, else `else`
        c("case", case_cfg(), vec![("in", n(95))], "out", text("high")),
        c(
            "case",
            case_cfg(),
            vec![("in", n(50))],
            "out",
            text("normal"),
        ),
        c("case", case_cfg(), vec![("in", n(5))], "out", text("low")),
        c(
            "case",
            vec![("values", obj(&[("in.0", n(5)), ("in.1", s("five"))]))],
            vec![("in", s("5"))],
            "out",
            text("five"),
        ),
        c(
            "case",
            vec![
                ("op", s("contains")),
                ("values", obj(&[("in.0", s("")), ("in.1", s("hit"))])),
            ],
            vec![("in", s("abc"))],
            "out",
            null(),
        ),
        c(
            "case",
            vec![
                ("op", s("regexp")),
                (
                    "values",
                    obj(&[("in.0", s("^t[0-9]+$")), ("in.1", s("temp"))]),
                ),
            ],
            vec![("in", s("t12"))],
            "out",
            text("temp"),
        ),
        c(
            "select",
            vec![("index", n(1))],
            pair(s("a"), s("b")),
            "out",
            text("b"),
        ),
        c("select", vec![], pair(s("a"), s("b")), "out", text("a")),
        c(
            "select",
            vec![("index", n(5))],
            pair(s("a"), s("b")),
            "out",
            null(),
        ),
        // hub: the input that changed last, its index and an event; also the same value again
        sq(
            "hub",
            vec![],
            vec![
                feed("in.0", n(5)),
                Sent("out", num(5.0)),
                Sent("index", num(0.0)),
                Sent("on_change", Want::Event),
                feed("in.1", n(7)),
                Sent("out", num(7.0)),
                Sent("index", num(1.0)),
                feed("in.0", n(7)),
                Sent("out", num(7.0)),
                Sent("index", num(0.0)),
                feed("in.0", n(7)),
                Sent("out", num(7.0)),
                Sent("on_change", Want::Event),
            ],
        ),
        sq(
            "hub",
            vec![],
            vec![
                feed("in.0", n(5)),
                Sent("out", num(5.0)),
                feed("in.1", n(7)),
                Sent("out", num(7.0)),
                Sent("index", num(1.0)),
                Sent("on_change", Want::Event),
                // with ignore_null, a null is not passed
                feed("in.0", Value::Null),
                Quiet("out"),
                Is("out", num(7.0)),
            ],
        ),
        // stopwatch: every interval (its clock ticks every 50 ms) it adds step
        sq(
            "stopwatch",
            vec![("enabled", b(true)), ("interval", fl(0.1)), ("step", n(2))],
            vec![
                Tick(1),
                Quiet("out"),
                Tick(2),
                Sent("out", num(2.0)),
                Ticks(2, 3),
                Sent("out", num(4.0)),
                // a sample on reset sets the count to reset_value at once
                feed("reset", b(true)),
                Sent("out", num(0.0)),
            ],
        ),
        sq(
            "stopwatch",
            vec![
                ("enabled", b(true)),
                ("interval", fl(0.05)),
                ("modulo", n(3)),
            ],
            vec![
                Ticks(3, 1),
                Is("out", num(0.0)),
                Sent("on_loop", Want::Event),
                Tick(2),
                Is("out", num(1.0)),
            ],
        ),
        // with loop false it stops at modulo
        sq(
            "stopwatch",
            vec![
                ("enabled", b(true)),
                ("interval", fl(0.05)),
                ("modulo", n(2)),
                ("loop", b(false)),
            ],
            vec![Ticks(2, 1), Is("out", num(2.0)), Ticks(3, 2), Quiet("out")],
        ),
        sq(
            "stopwatch",
            vec![("interval", fl(0.05))],
            vec![Ticks(3, 1), Quiet("out")],
        ),
        // trace: msg and the inputs' values in the log, at level trace
        sq(
            "trace",
            vec![("msg", s("hello"))],
            vec![feed("in.0", s("abc")), Logged(&["hello", "\"abc\""])],
        ),
        sq(
            "trace",
            vec![],
            vec![feed("in.0", n(1)), Logged(&["trace"])],
        ),
        sq(
            "trace",
            vec![("tracing", b(false))],
            vec![feed("in.0", s("abc")), NoLog],
        ),
        // router: in goes out on out.<name> of the first case condition matches, else on else
        sq(
            "router",
            router_cfg(false),
            vec![
                feed("condition", n(95)),
                feed("in", s("alarm")),
                Is("out.high", text("alarm")),
                feed("condition", n(50)),
                Is("out.low", text("alarm")),
                // without single_output each output keeps its last value
                Is("out.high", text("alarm")),
                feed("condition", n(-5)),
                Is("else", text("alarm")),
            ],
        ),
        sq(
            "router",
            router_cfg(true),
            vec![
                feed("condition", n(95)),
                feed("in", s("alarm")),
                Is("out.high", text("alarm")),
                feed("condition", n(50)),
                Is("out.low", text("alarm")),
                Is("out.high", null()),
            ],
        ),
        // event_gate: an event once every input changed since the last reset
        sq(
            "event_gate",
            vec![
                ("inputs", arr(vec![s("a"), s("b")])),
                ("log_order", s("first_occurrence")),
            ],
            vec![
                feed("in.b", n(1)),
                Quiet("on_finish"),
                feed("in.a", n(1)),
                Sent("on_finish", Want::Event),
                Is("order", text("b,a")),
                // the gate fires once
                feed("in.a", n(2)),
                feed("in.b", n(2)),
                Quiet("on_finish"),
                feed("reset", b(true)),
                feed("in.a", n(3)),
                feed("in.b", n(3)),
                Sent("on_finish", Want::Event),
            ],
        ),
        // a sample born at the start does not count
        sq(
            "event_gate",
            vec![("inputs", arr(vec![s("a"), s("b")]))],
            vec![
                feed_m("in.a", good(n(1)).at_start()),
                feed("in.b", n(1)),
                Quiet("on_finish"),
                feed("in.a", n(2)),
                Sent("on_finish", Want::Event),
            ],
        ),
        // catch_error: the message, the code, the input's name and an event
        sq(
            "catch_error",
            vec![],
            vec![
                feed("in.1", error_event.clone()),
                Is("out", text("boom")),
                Is("code", num(f64::from(0x41))),
                Is("source", text("1")),
                Sent("on_error", Want::Event),
            ],
        ),
        sq(
            "catch_error",
            vec![],
            vec![
                feed("in.0", s("no answer")),
                Is("out", text("no answer")),
                Is("source", text("0")),
                Sent("on_error", Want::Event),
            ],
        ),
    ]
}

/// Events and state: `changed`, the edges, `counter`, `toggle`, `sample_and_hold`, `debounce`,
/// `throttle`.
fn events() -> Vec<Case> {
    vec![
        // the first sample only starts it
        sq(
            "changed",
            vec![],
            vec![
                feed("in", n(1)),
                Quiet("on_change"),
                feed("in", n(1)),
                Quiet("on_change"),
                feed("in", n(2)),
                Sent("on_change", Want::Event),
            ],
        ),
        // nothing before counts as false
        sq(
            "rising_edge",
            vec![],
            vec![
                feed("in", b(true)),
                Sent("on_edge", Want::Event),
                feed("in", b(true)),
                Quiet("on_edge"),
                feed("in", b(false)),
                Quiet("on_edge"),
                feed("in", n(1)),
                Sent("on_edge", Want::Event),
            ],
        ),
        sq(
            "falling_edge",
            vec![],
            vec![
                feed("in", b(false)),
                Quiet("on_edge"),
                feed("in", b(true)),
                Quiet("on_edge"),
                feed("in", b(false)),
                Sent("on_edge", Want::Event),
            ],
        ),
        sq(
            "counter",
            vec![],
            vec![
                feed("in", b(true)),
                Is("out", num(1.0)),
                feed("in", s("x")),
                Is("out", num(2.0)),
                // a true reset goes back to initial
                feed("reset", b(true)),
                Is("out", num(0.0)),
            ],
        ),
        sq(
            "counter",
            vec![("step", n(5)), ("initial", n(10))],
            vec![
                feed("in", n(1)),
                Is("out", num(15.0)),
                feed("in", n(1)),
                Is("out", num(20.0)),
            ],
        ),
        sq(
            "toggle",
            vec![],
            vec![
                feed("in", n(1)),
                Is("out", val(b(true))),
                feed("in", n(1)),
                Is("out", val(b(false))),
                feed("in", n(1)),
                feed("reset", b(true)),
                Is("out", val(b(false))),
            ],
        ),
        sq(
            "toggle",
            vec![("initial", b(true))],
            vec![feed("in", n(1)), Is("out", val(b(false)))],
        ),
        sq(
            "sample_and_hold",
            vec![],
            vec![
                feed("in", n(5)),
                Quiet("out"),
                feed("trigger", b(true)),
                Is("out", num(5.0)),
                feed("in", n(6)),
                Quiet("out"),
                feed("trigger", b(true)),
                Is("out", num(6.0)),
            ],
        ),
        // debounce: the last value, once `ms` passed without another (at most ms/4 late)
        sq(
            "debounce",
            vec![("ms", n(100))],
            vec![
                feed("in", n(1)),
                Quiet("out"),
                Advance(60),
                feed("in", n(2)),
                Advance(60),
                Tick(10),
                Quiet("out"),
                Advance(65),
                Tick(20),
                Sent("out", num(2.0)),
            ],
        ),
        // throttle: the first value at once, then the latest at the end of each period
        sq(
            "throttle",
            vec![("ms", n(100))],
            vec![
                feed("in", n(1)),
                Sent("out", num(1.0)),
                feed("in", n(2)),
                feed("in", n(3)),
                Quiet("out"),
                Advance(50),
                Tick(10),
                Quiet("out"),
                Advance(75),
                Tick(20),
                Sent("out", num(3.0)),
            ],
        ),
    ]
}

/// Text: `concat`, `length`, `substring`, `replace`, `split`, `join`, `left`, `right`, `trim`.
fn text_blocks() -> Vec<Case> {
    #[track_caller]
    fn one(ty: &'static str, cfg: Vec<(&'static str, Value)>, v: Value, want: Want) -> Case {
        c(ty, cfg, vec![("in", v)], "out", want)
    }
    vec![
        c(
            "concat",
            vec![],
            vec![("in.0", s("AHU-")), ("in.1", n(2))],
            "out",
            text("AHU-2"),
        ),
        // a missing input is empty text, or with strict the result is null
        c("concat", vec![], vec![("in.1", s("x"))], "out", text("x")),
        c(
            "concat",
            vec![("strict", b(true))],
            vec![("in.1", s("x"))],
            "out",
            null(),
        ),
        one("length", vec![], s("héllo"), num(5.0)),
        one("length", vec![], arr(vec![n(1), n(2), n(3)]), num(3.0)),
        one("length", vec![], obj(&[("a", n(1)), ("b", n(2))]), num(2.0)),
        one("length", vec![], Value::Bytes(vec![1, 2, 3, 4]), num(4.0)),
        one("length", vec![], n(5), null()),
        one(
            "substring",
            vec![("start", n(1)), ("length", n(3))],
            s("abcdef"),
            text("bcd"),
        ),
        one(
            "substring",
            vec![("start", n(1)), ("end", n(-1))],
            s("[abc]"),
            text("abc"),
        ),
        one(
            "substring",
            vec![("start", n(1)), ("end", n(3))],
            s("abcdef"),
            text("bc"),
        ),
        // an overrun clamps; length wins over end
        one(
            "substring",
            vec![("start", n(4)), ("length", n(100))],
            s("abcdef"),
            text("ef"),
        ),
        one(
            "substring",
            vec![("start", n(0)), ("length", n(2)), ("end", n(5))],
            s("abcdef"),
            text("ab"),
        ),
        one("substring", vec![("start", n(2))], s("añbc"), text("bc")),
        one(
            "replace",
            vec![("from", s("-")), ("to", s("+"))],
            s("a-b-c"),
            text("a+b+c"),
        ),
        // plain text, no pattern
        one(
            "replace",
            vec![("from", s(".")), ("to", s("!"))],
            s("a.b"),
            text("a!b"),
        ),
        one(
            "replace",
            vec![("from", s("")), ("to", s("x"))],
            s("abc"),
            text("abc"),
        ),
        one(
            "replace",
            vec![("from", s("[0-9]+")), ("to", s("#")), ("regexp", b(true))],
            s("a1b22"),
            text("a#b#"),
        ),
        // `to` is taken as it is: `$1` is no group
        one(
            "replace",
            vec![("from", s("(b)")), ("to", s("$1")), ("regexp", b(true))],
            s("abc"),
            text("a$1c"),
        ),
        // a pattern that does not compile replaces nothing
        one(
            "replace",
            vec![("from", s("(")), ("to", s("x")), ("regexp", b(true))],
            s("a(b"),
            text("a(b"),
        ),
        one(
            "split",
            vec![],
            s("a,b,c"),
            val(arr(vec![s("a"), s("b"), s("c")])),
        ),
        one(
            "split",
            vec![("separator", s("; "))],
            s("a; b"),
            val(arr(vec![s("a"), s("b")])),
        ),
        one(
            "split",
            vec![("separator", s(""))],
            s("abc"),
            val(arr(vec![s("abc")])),
        ),
        one("join", vec![], arr(vec![n(1), n(2)]), text("1,2")),
        one(
            "join",
            vec![("separator", s("-"))],
            arr(vec![s("a"), s("b")]),
            text("a-b"),
        ),
        one("left", vec![("length", n(2))], s("abcdef"), text("ab")),
        one("left", vec![("length", n(2))], n(12345), text("12")),
        one("left", vec![], s("abc"), text("")),
        one("right", vec![("length", n(2))], s("abcdef"), text("ef")),
        one("right", vec![("length", n(10))], s("abc"), text("abc")),
        one("trim", vec![], s("  hi there \t"), text("hi there")),
        one("trim", vec![], Value::Null, text("")),
    ]
}

/// Codecs: Base64, URL, camel case, hash, JSON.
fn codecs() -> Vec<Case> {
    #[track_caller]
    fn one(
        ty: &'static str,
        cfg: Vec<(&'static str, Value)>,
        v: Value,
        port: &'static str,
        want: Want,
    ) -> Case {
        c(ty, cfg, vec![("in", v)], port, want)
    }
    vec![
        one("base64_encode", vec![], s("hello"), "out", text("aGVsbG8=")),
        one(
            "base64_encode",
            vec![],
            Value::Bytes(vec![0xff]),
            "out",
            text("/w=="),
        ),
        one("base64_encode", vec![], n(5), "out", null()),
        one("base64_decode", vec![], s("aGVsbG8="), "out", text("hello")),
        one(
            "base64_decode",
            vec![],
            s("aGVsbG8="),
            "bytes",
            val(Value::Bytes(b"hello".to_vec())),
        ),
        // the URL alphabet, padding optional; a bad UTF-8 sequence is U+FFFD
        one(
            "base64_decode",
            vec![],
            s("_w"),
            "bytes",
            val(Value::Bytes(vec![0xff])),
        ),
        one("base64_decode", vec![], s("_w"), "out", text("\u{FFFD}")),
        one("base64_decode", vec![], s("!!!"), "out", null()),
        one("base64_decode", vec![], s("!!!"), "bytes", null()),
        one(
            "url_encode",
            vec![],
            s("a b&c/é"),
            "out",
            text("a%20b%26c%2F%C3%A9"),
        ),
        one(
            "url_encode",
            vec![],
            s("Az09-_.!~*'()"),
            "out",
            text("Az09-_.!~*'()"),
        ),
        one(
            "url_decode",
            vec![],
            s("a+b%20c%C3%A9"),
            "out",
            text("a b cé"),
        ),
        one("url_decode", vec![], s("100%"), "out", text("100%")),
        one("url_decode", vec![], s("%zz%4"), "out", text("%zz%4")),
        one(
            "to_camel_case",
            vec![],
            s("Hello World-foo"),
            "out",
            text("helloWorldFoo"),
        ),
        one("to_camel_case", vec![], s("abc 2nd"), "out", text("abc2Nd")),
        one(
            "from_camel_case",
            vec![],
            s("HelloWorld"),
            "out",
            text(" hello world"),
        ),
        // known digests of "abc"
        one(
            "hash",
            vec![],
            s("abc"),
            "out",
            text("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),
        ),
        one(
            "hash",
            vec![("algorithm", s("sha1"))],
            s("abc"),
            "out",
            text("a9993e364706816aba3e25717850c26c9cd0d89d"),
        ),
        one(
            "hash",
            vec![("algorithm", s("md5"))],
            Value::Bytes(b"abc".to_vec()),
            "out",
            text("900150983cd24fb0d6963f7d28e17f72"),
        ),
        one(
            "json_parse",
            vec![],
            s(r#"{"a": 1, "b": [true, null, "x"]}"#),
            "out",
            val(obj(&[
                ("a", n(1)),
                ("b", arr(vec![b(true), Value::Null, s("x")])),
            ])),
        ),
        // a value that is no text passes as it is; no JSON gives null and parse_error
        one("json_parse", vec![], n(5), "out", num(5.0)),
        one("json_parse", vec![], s("{nope"), "out", null()),
        one(
            "json_parse",
            vec![],
            s("{nope"),
            "parse_error",
            val(b(true)),
        ),
        one(
            "json_stringify",
            vec![],
            obj(&[("a", n(1)), ("b", arr(vec![s("x")]))]),
            "out",
            pred("the JSON of {a: 1, b: [x]}", |v| {
                json_of(v) == Some(serde_json::json!({"a": 1, "b": ["x"]}))
            }),
        ),
        // bytes become Base64 text
        one(
            "json_stringify",
            vec![],
            Value::Bytes(vec![1, 2, 3]),
            "out",
            pred("the JSON text \"AQID\"", |v| {
                json_of(v) == Some(serde_json::json!("AQID"))
            }),
        ),
        one(
            "json_stringify",
            vec![("pretty", b(true))],
            obj(&[("a", n(1))]),
            "out",
            pred("pretty JSON of {a: 1}", |v| {
                matches!(v, Value::Str(t) if t.contains('\n'))
                    && json_of(v) == Some(serde_json::json!({"a": 1}))
            }),
        ),
    ]
}

fn json_of(v: &Value) -> Option<serde_json::Value> {
    match v {
        Value::Str(t) => serde_json::from_str(t).ok(),
        _ => None,
    }
}

/// Data: `make_object`, `make_array`, `get`.
fn data() -> Vec<Case> {
    let ab = || vec![("inputs", arr(vec![s("a"), s("b")]))];
    vec![
        c(
            "make_object",
            ab(),
            vec![("in.a", n(1)), ("in.b", s("x"))],
            "out",
            val(obj(&[("a", n(1)), ("b", s("x"))])),
        ),
        c(
            "make_array",
            ab(),
            vec![("in.b", s("x")), ("in.a", n(1))],
            "out",
            val(arr(vec![n(1), s("x")])),
        ),
        c(
            "get",
            vec![("path", s("a.b.1"))],
            vec![("in", obj(&[("a", obj(&[("b", arr(vec![n(7), n(8)]))]))]))],
            "out",
            num(8.0),
        ),
        c(
            "get",
            vec![("path", s("a.c"))],
            vec![("in", obj(&[("a", obj(&[("b", n(1))]))]))],
            "out",
            null(),
        ),
    ]
}

/// Date and time: µs since the epoch, `time_zone` default UTC.
fn dates() -> Vec<Case> {
    let t0 = s("2026-10-29T13:05:09Z");
    #[track_caller]
    fn fmt(f: &str, tz: &str, want: &str) -> Case {
        c(
            "date_format",
            vec![("format", s(f)), ("time_zone", s(tz))],
            vec![("in", s("2026-10-29T13:05:09Z"))],
            "out",
            text(want),
        )
    }
    #[track_caller]
    fn parse(port: &'static str, want: Want) -> Case {
        c(
            "date_parse",
            vec![],
            vec![("in", s("2026-10-29T13:05:09.250Z"))],
            port,
            want,
        )
    }
    #[track_caller]
    fn math_(cfg: Vec<(&'static str, Value)>, from: &str, want: i64) -> Case {
        c(
            "date_math",
            cfg,
            vec![("in", s(from))],
            "out",
            num(want as f64),
        )
    }
    #[track_caller]
    fn range(r: &str, port: &'static str, want: Want) -> Case {
        c("date_range", vec![], vec![("in", s(r))], port, want)
    }
    vec![
        // now: on each sample of `in`, and at start when interval_ms is above 0
        sq(
            "now",
            vec![("interval_ms", n(0))],
            vec![feed("in", n(1)), Now("out")],
        ),
        sq("now", vec![], vec![Start, Now("out")]),
        sq(
            "now",
            vec![("interval_ms", n(0))],
            vec![Start, Quiet("out")],
        ),
        sq(
            "now",
            vec![("interval_ms", n(200))],
            vec![Tick(5), Now("out")],
        ),
        // date_time: parts overflow as a calendar counts
        c(
            "date_time",
            vec![
                ("month", n(10)),
                ("day", n(29)),
                ("hour", n(13)),
                ("minute", n(5)),
            ],
            vec![("in.year", n(2026))],
            "out",
            num(us("2026-10-29T13:05:00Z") as f64),
        ),
        c(
            "date_time",
            vec![("month", n(13)), ("day", n(1))],
            vec![("in.year", n(2026))],
            "out",
            num(us("2027-01-01T00:00:00Z") as f64),
        ),
        c(
            "date_time",
            vec![("month", n(3)), ("day", n(0))],
            vec![("in.year", n(2026))],
            "out",
            num(us("2026-02-28T00:00:00Z") as f64),
        ),
        c(
            "date_time",
            vec![("hour", fl(1.9)), ("millisecond", n(500))],
            vec![("in.year", n(2026))],
            "out",
            num((us("2026-01-01T01:00:00Z") + 500_000) as f64),
        ),
        c(
            "date_time",
            vec![
                ("month", n(7)),
                ("day", n(1)),
                ("time_zone", s("Europe/Kyiv")),
            ],
            vec![("in.year", n(2026))],
            "out",
            num(us("2026-06-30T21:00:00Z") as f64),
        ),
        // date_format: pattern letters, quoted text, zones
        c(
            "date_format",
            vec![],
            vec![("in", t0.clone())],
            "out",
            text("2026-10-29T13:05:09"),
        ),
        c(
            "date_format",
            vec![],
            vec![("in", n(us("2026-10-29T13:05:09Z")))],
            "out",
            text("2026-10-29T13:05:09"),
        ),
        fmt(
            "EEEE, MMMM d, yyyy 'at' h:mm a",
            "UTC",
            "Thursday, October 29, 2026 at 1:05 PM",
        ),
        fmt("E MMM dd yy", "UTC", "Thu Oct 29 26"),
        fmt("D", "UTC", "302"),
        fmt("HH:mm xxx", "Europe/Kyiv", "15:05 +02:00"),
        fmt("Z", "UTC", "+0000"),
        fmt("XXX", "UTC", "Z"),
        fmt("''yyyy''", "UTC", "'2026'"),
        c(
            "date_format",
            vec![("format", s("HH:mm xxx")), ("time_zone", s("auto"))],
            vec![("in", s("2026-10-29T13:05:00+05:00"))],
            "out",
            text("13:05 +05:00"),
        ),
        // date_parse: the parts; weekday 1 is Monday
        parse("time", num((us("2026-10-29T13:05:09Z") + 250_000) as f64)),
        parse("year", num(2026.0)),
        parse("month", num(10.0)),
        parse("day", num(29.0)),
        parse("hour", num(13.0)),
        parse("minute", num(5.0)),
        parse("second", num(9.0)),
        parse("millisecond", num(250.0)),
        parse("weekday", num(4.0)),
        c(
            "date_parse",
            vec![],
            vec![("in", s("10/29/2026 1:05 pm"))],
            "hour",
            num(13.0),
        ),
        c(
            "date_parse",
            vec![],
            vec![("in", s("2026/1/4"))],
            "weekday",
            num(7.0),
        ),
        c(
            "date_parse",
            vec![("time_zone", s("Europe/Kyiv"))],
            vec![("in", s("2026-10-29T13:05:00"))],
            "time",
            num(us("2026-10-29T11:05:00Z") as f64),
        ),
        c(
            "date_parse",
            vec![],
            vec![("in", s("no date"))],
            "year",
            null(),
        ),
        c(
            "date_parse",
            vec![],
            vec![("in", s("no date"))],
            "time",
            null(),
        ),
        // date_math: calendar parts in the zone, the rest elapsed time
        math_(
            vec![("month", n(1))],
            "2026-01-31T00:00:00Z",
            us("2026-02-28T00:00:00Z"),
        ),
        math_(
            vec![("op", s("before")), ("day", n(1))],
            "2026-01-31T00:00:00Z",
            us("2026-01-30T00:00:00Z"),
        ),
        math_(
            vec![("hour", n(25)), ("millisecond", n(1))],
            "2026-01-31T00:00:00Z",
            us("2026-02-01T01:00:00.001Z"),
        ),
        // a day over a DST change keeps the wall time (Kyiv: 2026-03-29, 23 h)
        math_(
            vec![("day", n(1)), ("time_zone", s("Europe/Kyiv"))],
            "2026-03-28T12:00:00+02:00",
            us_in(2026, 3, 29, 12, 0, "Europe/Kyiv"),
        ),
        // date_range: fixed ranges
        range("2026-10", "start", num(us("2026-10-01T00:00:00Z") as f64)),
        range(
            "2026-10",
            "end",
            num((us("2026-11-01T00:00:00Z") - 1) as f64),
        ),
        range(
            "2026-10",
            "duration",
            num((us("2026-11-01T00:00:00Z") - us("2026-10-01T00:00:00Z")) as f64),
        ),
        range(
            "2026-10",
            "this_range",
            text("2026-10-01T00:00:00/2026-10-31T23:59:59"),
        ),
        range("2026", "start", num(us("2026-01-01T00:00:00Z") as f64)),
        range("2026-10-29", "duration", num(DAY as f64)),
        // an end written to the second takes the whole second
        range(
            "2026-10-29T00:00:00Z/2026-10-29T12:00:00Z",
            "end",
            num((us("2026-10-29T12:00:01Z") - 1) as f64),
        ),
        c(
            "date_range",
            vec![("time_zone", s("Europe/Kyiv"))],
            vec![("in", s("2026-10-29"))],
            "start",
            num(us("2026-10-28T22:00:00Z") as f64),
        ),
        // the neighbours' texts
        range("today", "previous_range", text("yesterday")),
        range("yesterday", "next_range", text("today")),
        range("thisMonth", "previous_range", text("lastMonth")),
        range("current3days", "previous_range", text("previous3days")),
        // relative ranges read the clock
        range(
            "today",
            "start",
            pred("today's midnight (UTC)", |v| {
                as_num(v).is_some_and(|x| {
                    let (x, now) = (x as i64, now_us() as i64);
                    x % DAY == 0 && x <= now && now - x < DAY
                })
            }),
        ),
        range("today", "duration", num(DAY as f64)),
        range("yesterday", "duration", num(DAY as f64)),
        range(
            "this_week",
            "start",
            pred("a Monday at 00:00", |v| {
                // 1970-01-05 was a Monday
                as_num(v).is_some_and(|x| (x as i64) % DAY == 0 && ((x as i64) / DAY) % 7 == 4)
            }),
        ),
        range("thisWeek", "duration", num((7 * DAY) as f64)),
        range(
            "current1hours",
            "end",
            pred("now", |v| {
                as_num(v).is_some_and(|x| (x - now_us() as f64).abs() < 5e6)
            }),
        ),
        // a sample on next or previous moves the block to that neighbour
        sq(
            "date_range",
            vec![],
            vec![
                feed("in", s("2026-10")),
                feed("next", b(true)),
                Is("start", num(us("2026-11-01T00:00:00Z") as f64)),
                event("previous", 2),
                event("previous", 3),
                Is("start", num(us("2026-09-01T00:00:00Z") as f64)),
            ],
        ),
        // ... but not one born at the start
        sq(
            "date_range",
            vec![],
            vec![
                feed("in", s("2026-10")),
                feed_m("next", good(b(true)).at_start()),
                Is("start", num(us("2026-10-01T00:00:00Z") as f64)),
            ],
        ),
    ]
}

/// Tables (ADR 0044 §2).
fn tables() -> Vec<Case> {
    let plant = || {
        tbl(
            &["name", "kw", "zone"],
            vec![
                vec![s("pump"), n(3), s("a")],
                vec![s("fan"), n(7), s("b")],
                vec![s("heater"), n(12), s("a")],
            ],
        )
    };
    let two = || {
        tbl(
            &["name", "kw"],
            vec![vec![s("pump"), n(3)], vec![s("fan"), n(7)]],
        )
    };
    let left = || tbl(&["id", "a"], vec![vec![n(1), s("x")], vec![n(2), s("y")]]);
    let right = || {
        tbl(
            &["id", "b"],
            vec![vec![s("1"), s("p")], vec![s("3"), s("q")]],
        )
    };
    let join = |how: &str| vec![("column", s("id")), ("join", s(how))];
    // `right` is no operand (it takes no constant): its table comes as a sample first
    let lr = || vec![("right", right()), ("in", left())];
    let numbered = || tbl(&["i"], (0..5).map(|i| vec![n(i)]).collect());
    let series = || {
        tbl(
            &["t", "v"],
            vec![
                vec![n(600_000_000), n(1)],
                vec![n(4_000_000_000), n(2)],
                vec![n(4_300_000_000), n(3)],
            ],
        )
    };
    vec![
        // table_from_csv: cells are texts; equal header names get _2
        c(
            "table_from_csv",
            vec![],
            vec![("in", s("name,kw\npump,3\nfan,7\n"))],
            "out",
            table(
                &["name", "kw"],
                vec![vec![s("pump"), s("3")], vec![s("fan"), s("7")]],
            ),
        ),
        c(
            "table_from_csv",
            vec![("delimiter", s(";"))],
            vec![("in", s("x;y\n1;2"))],
            "out",
            table(&["x", "y"], vec![vec![s("1"), s("2")]]),
        ),
        c(
            "table_from_csv",
            vec![],
            vec![("in", s("a,a,\n1,2,3"))],
            "out",
            // an equal name gets `_2`; an empty one is named by its column, `v<n>`
            pred("columns a, a_2 and v3 for the empty name", |v| {
                columns(v) == ["a", "a_2", "v3"]
            }),
        ),
        c(
            "table_from_csv",
            vec![],
            vec![("in", s("a,a\n1,2"))],
            "out",
            table(&["a", "a_2"], vec![vec![s("1"), s("2")]]),
        ),
        c(
            "table_from_csv",
            vec![("with_header", b(false))],
            vec![("in", s("1,2\n3,4"))],
            "out",
            pred("two rows of two cells", |v| {
                rows(v).len() == 2 && columns(v).len() == 2
            }),
        ),
        // a row of more than 128 fields is refused
        c(
            "table_from_csv",
            vec![],
            vec![("in", s(&vec!["h"; 129].join(",")))],
            "parse_error",
            val(b(true)),
        ),
        // table_to_csv
        c(
            "table_to_csv",
            vec![],
            vec![("in", two())],
            "out",
            pred("name,kw / pump,3 / fan,7", |v| {
                csv_lines(v) == ["name,kw", "pump,3", "fan,7"]
            }),
        ),
        c(
            "table_to_csv",
            vec![("with_header", b(false)), ("delimiter", s(";"))],
            vec![("in", two())],
            "out",
            pred("pump;3 / fan;7", |v| csv_lines(v) == ["pump;3", "fan;7"]),
        ),
        // table_from_json: nested keys as a/b, a selector, one object
        c(
            "table_from_json",
            vec![],
            vec![("in", s(r#"[{"a": 1, "b": {"c": 2}}, {"a": 3}]"#))],
            "out",
            table(
                &["a", "b/c"],
                vec![vec![n(1), n(2)], vec![n(3), Value::Null]],
            ),
        ),
        c(
            "table_from_json",
            vec![("selector", s("data.items"))],
            vec![("in", s(r#"{"data": {"items": [{"x": 1}, {"x": 2}]}}"#))],
            "out",
            table(&["x"], vec![vec![n(1)], vec![n(2)]]),
        ),
        c(
            "table_from_json",
            vec![("selector", s("a[0].b"))],
            vec![("in", s(r#"{"a": [{"b": [{"x": 5}]}]}"#))],
            "out",
            table(&["x"], vec![vec![n(5)]]),
        ),
        c(
            "table_from_json",
            vec![],
            vec![("in", s(r#"{"x": 1, "y": "z"}"#))],
            "out",
            table(&["x", "y"], vec![vec![n(1), s("z")]]),
        ),
        c(
            "table_from_json",
            vec![],
            vec![("in", s(r#"{"columns": ["p", "q"], "rows": [[1, 2]]}"#))],
            "out",
            table(&["p", "q"], vec![vec![n(1), n(2)]]),
        ),
        c(
            "table_from_json",
            vec![],
            vec![("in", s("nope"))],
            "parse_error",
            val(b(true)),
        ),
        c(
            "table_from_json",
            vec![],
            vec![("in", s("nope"))],
            "out",
            null(),
        ),
        // table_to_json: the rows as JSON objects
        c(
            "table_to_json",
            vec![],
            vec![("in", two())],
            "out",
            pred("[{name: pump, kw: 3}, {name: fan, kw: 7}]", |v| {
                json_of(v)
                    == Some(
                        serde_json::json!([{"name": "pump", "kw": 3}, {"name": "fan", "kw": 7}]),
                    )
            }),
        ),
        // table_map_columns: a column, `= expr`, `+ expr`, `& expr`
        c(
            "table_map_columns",
            vec![(
                "mapping",
                arr(vec![
                    obj(&[("name", s("n")), ("from", s("name"))]),
                    obj(&[("name", s("w")), ("from", s("+ row.kw * 1000"))]),
                    obj(&[("name", s("big")), ("from", s("& row.kw > 5"))]),
                    obj(&[("name", s("tag")), ("from", s("= \"x\""))]),
                ]),
            )],
            vec![("in", two())],
            "out",
            table(
                &["n", "w", "big", "tag"],
                vec![
                    vec![s("pump"), n(3000), b(false), s("x")],
                    vec![s("fan"), n(7000), b(true), s("x")],
                ],
            ),
        ),
        c(
            "table_map_columns",
            vec![
                ("retain_columns", b(true)),
                (
                    "mapping",
                    arr(vec![obj(&[("name", s("i")), ("from", s("+ index"))])]),
                ),
            ],
            vec![("in", two())],
            "out",
            pred("name, kw kept and i = 0, 1", |v| {
                let cols = columns(v);
                let r = rows(v);
                cols.contains(&"name".to_owned())
                    && cols.contains(&"kw".to_owned())
                    && r.len() == 2
                    && r.iter()
                        .enumerate()
                        .all(|(i, row)| get(row, "i").and_then(as_num) == Some(i as f64))
            }),
        ),
        // table_sort: no value sorts last either way; natural
        c(
            "table_sort",
            vec![("column", s("kw")), ("order", s("descending"))],
            vec![("in", plant())],
            "out",
            pred("heater, fan, pump", |v| {
                names(v) == ["heater", "fan", "pump"]
            }),
        ),
        c(
            "table_sort",
            vec![("column", s("name")), ("method", s("string"))],
            vec![("in", plant())],
            "out",
            pred("fan, heater, pump", |v| {
                names(v) == ["fan", "heater", "pump"]
            }),
        ),
        c(
            "table_sort",
            vec![("column", s("name")), ("method", s("natural"))],
            vec![(
                "in",
                tbl(
                    &["name"],
                    vec![vec![s("a10")], vec![s("a2")], vec![s("a1")]],
                ),
            )],
            "out",
            pred("a1, a2, a10", |v| names(v) == ["a1", "a2", "a10"]),
        ),
        c(
            "table_sort",
            vec![("column", s("kw"))],
            vec![(
                "in",
                tbl(
                    &["name", "kw"],
                    vec![
                        vec![s("x"), Value::Null],
                        vec![s("y"), n(3)],
                        vec![s("z"), n(1)],
                    ],
                ),
            )],
            "out",
            pred("z, y, x", |v| names(v) == ["z", "y", "x"]),
        ),
        c(
            "table_sort",
            vec![("column", s("kw")), ("order", s("descending"))],
            vec![(
                "in",
                tbl(
                    &["name", "kw"],
                    vec![
                        vec![s("x"), Value::Null],
                        vec![s("y"), n(1)],
                        vec![s("z"), n(3)],
                    ],
                ),
            )],
            "out",
            pred("z, y, x", |v| names(v) == ["z", "y", "x"]),
        ),
        // equal keys keep their order
        c(
            "table_sort",
            vec![("column", s("zone")), ("method", s("string"))],
            vec![("in", plant())],
            "out",
            pred("pump, heater, fan", |v| {
                names(v) == ["pump", "heater", "fan"]
            }),
        ),
        // table_filter / table_remove_rows / table_edit_rows: per-row rhai over row and index
        c(
            "table_filter",
            vec![("expr", s("row.kw > 5"))],
            vec![("in", plant())],
            "out",
            pred("fan, heater", |v| names(v) == ["fan", "heater"]),
        ),
        c(
            "table_filter",
            vec![("expr", s("index == 1"))],
            vec![("in", plant())],
            "out",
            pred("fan", |v| names(v) == ["fan"]),
        ),
        c(
            "table_filter",
            vec![("expr", s("row.kw != () && row.kw > 5"))],
            vec![(
                "in",
                arr(vec![
                    obj(&[("name", s("x"))]),
                    obj(&[("name", s("y")), ("kw", n(9))]),
                ]),
            )],
            "out",
            pred("y", |v| names(v) == ["y"]),
        ),
        c(
            "table_remove_rows",
            vec![("expr", s("row.kw > 5"))],
            vec![("in", plant())],
            "out",
            pred("pump", |v| names(v) == ["pump"]),
        ),
        c(
            "table_edit_rows",
            vec![
                ("expr", s("row.kw > 5")),
                ("cells", obj(&[("zone", s("hot"))])),
            ],
            vec![("in", plant())],
            "out",
            table(
                &["name", "kw", "zone"],
                vec![
                    vec![s("pump"), n(3), s("a")],
                    vec![s("fan"), n(7), s("hot")],
                    vec![s("heater"), n(12), s("hot")],
                ],
            ),
        ),
        // table_group_by
        c(
            "table_group_by",
            vec![
                ("column", s("zone")),
                (
                    "aggregates",
                    arr(vec![obj(&[
                        ("column", s("kw")),
                        ("method", s("sum")),
                        ("as", s("total")),
                    ])]),
                ),
            ],
            vec![("in", plant())],
            "out",
            table(
                &["zone", "total"],
                vec![vec![s("a"), n(15)], vec![s("b"), n(7)]],
            ),
        ),
        c(
            "table_group_by",
            vec![
                ("column", s("zone")),
                (
                    "aggregates",
                    arr(vec![obj(&[
                        ("column", s("kw")),
                        ("method", s("count")),
                        ("as", s("n")),
                    ])]),
                ),
            ],
            vec![(
                "in",
                tbl(
                    &["zone", "kw"],
                    vec![
                        vec![s("a"), n(1)],
                        vec![Value::Null, n(2)],
                        vec![s("a"), n(3)],
                    ],
                ),
            )],
            "out",
            table(&["zone", "n"], vec![vec![s("a"), n(2)]]),
        ),
        c(
            "table_group_by",
            vec![("column", s("zone")), ("include_blank", b(true))],
            vec![(
                "in",
                tbl(
                    &["zone", "kw"],
                    vec![
                        vec![s("a"), n(1)],
                        vec![Value::Null, n(2)],
                        vec![s("a"), n(3)],
                    ],
                ),
            )],
            "out",
            pred("two groups", |v| rows(v).len() == 2),
        ),
        c(
            "table_group_by",
            vec![("column", s("zone")), ("nested", b(true))],
            vec![("in", plant())],
            "out",
            pred("a column rows with each group's table", |v| {
                let r = rows(v);
                r.len() == 2
                    && columns(v).contains(&"rows".to_owned())
                    && get(&r[0], "rows").is_some_and(|t| names(t) == ["pump", "heater"])
            }),
        ),
        // table_join: one to one, keys compare as text
        c(
            "table_join",
            join("left"),
            lr(),
            "out",
            table(
                &["id", "a", "b"],
                vec![vec![n(1), s("x"), s("p")], vec![n(2), s("y"), Value::Null]],
            ),
        ),
        c(
            "table_join",
            join("inner"),
            lr(),
            "out",
            table(&["id", "a", "b"], vec![vec![n(1), s("x"), s("p")]]),
        ),
        c(
            "table_join",
            join("right"),
            lr(),
            "out",
            pred("every row of right, its cells winning", |v| {
                let r = rows(v);
                r.len() == 2
                    && get(&r[0], "id") == Some(&s("1"))
                    && get(&r[0], "a") == Some(&s("x"))
                    && get(&r[1], "b") == Some(&s("q"))
            }),
        ),
        c(
            "table_join",
            join("full"),
            lr(),
            "out",
            pred("x, y, then q", |v| {
                let r = rows(v);
                r.len() == 3
                    && get(&r[0], "b") == Some(&s("p"))
                    && get(&r[1], "a") == Some(&s("y"))
                    && get(&r[2], "b") == Some(&s("q"))
            }),
        ),
        c(
            "table_join",
            join("exclude"),
            lr(),
            "out",
            pred("y only", |v| {
                let r = rows(v);
                r.len() == 1 && get(&r[0], "a") == Some(&s("y"))
            }),
        ),
        c(
            "table_join",
            join("union"),
            lr(),
            "out",
            pred("four rows", |v| rows(v).len() == 4),
        ),
        c(
            "table_join",
            vec![("column", s("id")), ("right_column", s("key"))],
            vec![
                ("right", tbl(&["key", "b"], vec![vec![n(2), s("r")]])),
                ("in", left()),
            ],
            "out",
            pred("y joined with r", |v| {
                let r = rows(v);
                r.len() == 2 && get(&r[1], "b") == Some(&s("r"))
            }),
        ),
        // a table with no key column passes in
        c(
            "table_join",
            vec![("column", s("nope"))],
            lr(),
            "out",
            table(&["id", "a"], vec![vec![n(1), s("x")], vec![n(2), s("y")]]),
        ),
        // table_page
        sq(
            "table_page",
            vec![("page_size", n(2))],
            vec![
                feed("in", numbered()),
                Is("out", table(&["i"], vec![vec![n(0)], vec![n(1)]])),
                Is("current_page", num(0.0)),
                Is("total_pages", num(3.0)),
                event("next", 1),
                Is("out", table(&["i"], vec![vec![n(2)], vec![n(3)]])),
                Is("current_page", num(1.0)),
                event("last", 2),
                Is("out", table(&["i"], vec![vec![n(4)]])),
                event("previous", 3),
                Is("current_page", num(1.0)),
                event("first", 4),
                Is("current_page", num(0.0)),
            ],
        ),
        sq(
            "table_page",
            vec![("page_size", n(-1))],
            vec![
                feed("in", numbered()),
                Is("out", pred("all five rows", |v| rows(v).len() == 5)),
                Is("total_pages", num(1.0)),
            ],
        ),
        sq(
            "table_page",
            vec![("page_size", n(2)), ("page", n(2))],
            vec![
                feed("in", numbered()),
                Is("out", table(&["i"], vec![vec![n(4)]])),
            ],
        ),
        // table_rollup: buckets on round times, the bucket's start in µs
        c(
            "table_rollup",
            vec![],
            vec![("in", series())],
            "out",
            table(
                &["t", "v"],
                vec![vec![n(0), n(1)], vec![n(3_600_000_000), fl(2.5)]],
            ),
        ),
        c(
            "table_rollup",
            vec![("round_time", b(false))],
            vec![("in", series())],
            "out",
            table(
                &["t", "v"],
                vec![vec![n(600_000_000), fl(1.5)], vec![n(4_200_000_000), n(3)]],
            ),
        ),
        c(
            "table_rollup",
            vec![(
                "aggregates",
                arr(vec![obj(&[
                    ("column", s("v")),
                    ("method", s("max")),
                    ("as", s("v_max")),
                ])]),
            )],
            vec![("in", series())],
            "out",
            table(
                &["t", "v_max"],
                vec![vec![n(0), n(1)], vec![n(3_600_000_000), n(3)]],
            ),
        ),
        // a bucket without rows gives no row
        c(
            "table_rollup",
            vec![("interval", s("15m")), ("method", s("sum"))],
            vec![("in", series())],
            "out",
            table(
                &["t", "v"],
                vec![vec![n(0), n(1)], vec![n(3_600_000_000), n(5)]],
            ),
        ),
        // table_aggregate: one value
        c(
            "table_aggregate",
            vec![("column", s("kw")), ("method", s("sum"))],
            vec![("in", plant())],
            "out",
            num(22.0),
        ),
        c(
            "table_aggregate",
            vec![("column", s("kw")), ("method", s("average"))],
            vec![("in", plant())],
            "out",
            num(22.0 / 3.0),
        ),
        c(
            "table_aggregate",
            vec![("column", s("kw")), ("method", s("median"))],
            vec![("in", plant())],
            "out",
            num(7.0),
        ),
        c(
            "table_aggregate",
            vec![("column", s("kw"))],
            vec![("in", plant())],
            "out",
            num(3.0),
        ),
        c(
            "table_aggregate",
            vec![("column", s("kw")), ("method", s("last"))],
            vec![("in", plant())],
            "out",
            num(12.0),
        ),
        c(
            "table_aggregate",
            vec![("column", s("kw")), ("method", s("min"))],
            vec![("in", plant())],
            "out",
            num(3.0),
        ),
        c(
            "table_aggregate",
            vec![("column", s("kw")), ("method", s("count"))],
            vec![(
                "in",
                tbl(&["kw"], vec![vec![n(1)], vec![Value::Null], vec![n(2)]]),
            )],
            "out",
            num(2.0),
        ),
        c(
            "table_aggregate",
            vec![("column", s("zone")), ("method", s("concat_unique"))],
            vec![("in", plant())],
            "out",
            text("a,b"),
        ),
        c(
            "table_aggregate",
            vec![("column", s("name")), ("method", s("concat"))],
            vec![("in", plant())],
            "out",
            text("pump,fan,heater"),
        ),
        c(
            "table_aggregate",
            vec![("column", s("kw")), ("method", s("variance"))],
            vec![("in", tbl(&["kw"], vec![vec![n(1)], vec![n(3)]]))],
            "out",
            num(1.0),
        ),
        // table_select_rows / table_select_columns
        c(
            "table_select_rows",
            vec![("indexes", s("0,2"))],
            vec![("in", plant())],
            "out",
            pred("pump, heater", |v| names(v) == ["pump", "heater"]),
        ),
        c(
            "table_select_rows",
            vec![("indexes", n(1))],
            vec![("in", plant())],
            "out",
            pred("fan", |v| names(v) == ["fan"]),
        ),
        c(
            "table_select_rows",
            vec![("indexes", arr(vec![n(2)]))],
            vec![("in", plant())],
            "out",
            pred("heater", |v| names(v) == ["heater"]),
        ),
        c(
            "table_select_columns",
            vec![("columns", s("name,zone"))],
            vec![("in", plant())],
            "out",
            table(
                &["name", "zone"],
                vec![
                    vec![s("pump"), s("a")],
                    vec![s("fan"), s("b")],
                    vec![s("heater"), s("a")],
                ],
            ),
        ),
        c(
            "table_select_columns",
            vec![("columns", arr(vec![s("kw")]))],
            vec![("in", two())],
            "out",
            table(&["kw"], vec![vec![n(3)], vec![n(7)]]),
        ),
        // table_columns: {name, type}
        c(
            "table_columns",
            vec![],
            vec![(
                "in",
                tbl(
                    &["a", "b", "c", "d"],
                    vec![
                        vec![s("x"), n(1), b(true), Value::Null],
                        vec![s("y"), s("2"), b(false), Value::Null],
                    ],
                ),
            )],
            "out",
            table(
                &["name", "type"],
                vec![
                    vec![s("a"), s("string")],
                    vec![s("b"), s("mixed")],
                    vec![s("c"), s("bool")],
                    vec![s("d"), s("null")],
                ],
            ),
        ),
        // table_row_cells: that row as a map; count: the rows
        c(
            "table_row_cells",
            vec![("row", n(1))],
            vec![("in", plant())],
            "out",
            val(obj(&[("name", s("fan")), ("kw", n(7)), ("zone", s("b"))])),
        ),
        c(
            "table_row_cells",
            vec![],
            vec![("in", plant())],
            "count",
            num(3.0),
        ),
        // table_add_row: a new key adds its column
        c(
            "table_add_row",
            vec![("row", obj(&[("name", s("x")), ("extra", n(2))]))],
            vec![("in", two())],
            "out",
            table(
                &["name", "kw", "extra"],
                vec![
                    vec![s("pump"), n(3), Value::Null],
                    vec![s("fan"), n(7), Value::Null],
                    vec![s("x"), Value::Null, n(2)],
                ],
            ),
        ),
        // table_transpose: the columns become rows
        c(
            "table_transpose",
            vec![("header_column", s("name"))],
            vec![("in", two())],
            "out",
            pred("one row (kw) with 3 and 7 under pump and fan", |v| {
                let r = rows(v);
                r.len() == 1
                    && get(&r[0], "pump").and_then(as_num) == Some(3.0)
                    && get(&r[0], "fan").and_then(as_num) == Some(7.0)
            }),
        ),
        c(
            "table_transpose",
            vec![("ignore_columns", s("zone"))],
            vec![("in", plant())],
            "out",
            pred("two rows (name, kw), three cells each", |v| {
                rows(v).len() <= 2 && rows(v).iter().any(|r| {
                    matches!(r, Value::Map(m) if m.values().filter_map(as_num).collect::<Vec<_>>() == [3.0, 7.0, 12.0])
                })
            }),
        ),
        // table_from_map: a map as a one-row table; a table passes
        c(
            "table_from_map",
            vec![],
            vec![("in", obj(&[("a", n(1)), ("b", s("x"))]))],
            "out",
            table(&["a", "b"], vec![vec![n(1), s("x")]]),
        ),
        c(
            "table_from_map",
            vec![],
            vec![("in", two())],
            "out",
            table(
                &["name", "kw"],
                vec![vec![s("pump"), n(3)], vec![s("fan"), n(7)]],
            ),
        ),
        // table_recorder: a row {t, <input>…} for each sample, t the sample's time
        sq(
            "table_recorder",
            vec![("inputs", arr(vec![s("a"), s("b")])), ("buffer_size", n(2))],
            vec![
                feed_m("in.a", msg(n(1), Quality::Good, 10)),
                Is(
                    "out",
                    pred("one row at t 10", |v| {
                        let r = rows(v);
                        r.len() == 1
                            && get(&r[0], "t").and_then(as_num) == Some(10.0)
                            && get(&r[0], "a").and_then(as_num) == Some(1.0)
                    }),
                ),
                feed_m("in.b", msg(n(2), Quality::Good, 20)),
                feed_m("in.b", msg(n(3), Quality::Good, 30)),
                // buffer_size 2: the oldest row goes
                Is(
                    "out",
                    pred("rows at t 20 and 30", |v| {
                        let r = rows(v);
                        r.len() == 2
                            && get(&r[0], "t").and_then(as_num) == Some(20.0)
                            && get(&r[1], "b").and_then(as_num) == Some(3.0)
                    }),
                ),
                feed("reset", b(true)),
                Is("out", pred("no row", |v| rows(v).is_empty())),
            ],
        ),
        sq(
            "table_recorder",
            vec![("ignore_null", b(true))],
            vec![
                feed_m("in.0", msg(n(1), Quality::Good, 10)),
                feed_m("in.0", msg(Value::Null, Quality::Good, 20)),
                Is("out", pred("one row", |v| rows(v).len() == 1)),
            ],
        ),
    ]
}

fn csv_lines(v: &Value) -> Vec<String> {
    match v {
        Value::Str(t) => t
            .lines()
            .map(|l| l.trim_end_matches('\r').to_owned())
            .filter(|l| !l.is_empty())
            .collect(),
        _ => Vec::new(),
    }
}

/// The `name` cells of a table, in order.
fn names(v: &Value) -> Vec<String> {
    rows(v)
        .iter()
        .map(|r| match get(r, "name") {
            Some(Value::Str(n)) => n.clone(),
            x => format!("{x:?}"),
        })
        .collect()
}

/// The older node types, from their catalog descriptions (`src/catalog.rs`).
fn older() -> Vec<Case> {
    vec![
        // timer: a count every period
        sq(
            "timer",
            vec![("period_ms", n(100))],
            vec![
                Tick(1000),
                Is("out", num(1.0)),
                T("out", 1000),
                Tick(2000),
                Is("out", num(2.0)),
            ],
        ),
        // const: one value, once at start
        sq(
            "const",
            vec![("value", s("on"))],
            vec![Start, Is("out", text("on"))],
        ),
        // expression: rhai over named inputs; the worst quality of the inputs by default
        sq(
            "expression",
            vec![
                ("inputs", arr(vec![s("a"), s("b")])),
                ("expr", s("a.v + b.v")),
            ],
            vec![
                feed_m("in.a", msg(n(2), Quality::Good, 5)),
                feed_m("in.b", msg(n(3), Quality::Uncertain, 7)),
                Is("out", num(5.0)),
                Q("out", Quality::Uncertain),
                T("out", 7),
            ],
        ),
        // filter: passes the samples a condition over v, q, t accepts
        sq(
            "filter",
            vec![("expr", s("v > 5"))],
            vec![
                feed("in", n(7)),
                Sent("out", num(7.0)),
                feed("in", n(3)),
                Quiet("out"),
            ],
        ),
        // latch: holds true after in was true, until reset
        sq(
            "latch",
            vec![],
            vec![
                feed("in", b(true)),
                Is("out", val(b(true))),
                feed("in", b(false)),
                Quiet("out"),
                feed("reset", b(true)),
                Is("out", val(b(false))),
            ],
        ),
        // reset auto: also in going false
        sq(
            "latch",
            vec![("reset", s("auto"))],
            vec![
                feed("in", b(true)),
                feed("in", b(false)),
                Is("out", val(b(false))),
            ],
        ),
        // delay: every sample, later, with its own time
        sq(
            "delay",
            vec![("ms", n(200))],
            vec![
                feed_m("in", msg(n(5), Quality::Good, 42)),
                Quiet("out"),
                TickIn(0),
                Quiet("out"),
                TickIn(400),
                Sent("out", num(5.0)),
                T("out", 42),
            ],
        ),
        // scale: k × in + b; with a range, in is first mapped
        c(
            "scale",
            vec![("k", n(2)), ("b", n(1))],
            vec![("in", n(3))],
            "out",
            num(7.0),
        ),
        c(
            "scale",
            vec![("input_max", n(10))],
            vec![("in", n(5))],
            "out",
            num(50.0),
        ),
        c(
            "scale",
            vec![("input_max", n(10))],
            vec![("in", n(15))],
            "input_out_of_range",
            val(b(true)),
        ),
        c(
            "scale",
            vec![
                ("input_min", n(4)),
                ("input_max", n(20)),
                ("output_min", n(0)),
                ("output_max", n(100)),
            ],
            vec![("in", n(12))],
            "out",
            num(50.0),
        ),
        // a range value from its port maps too (docs/flow-blocks.md, scale)
        sq(
            "scale",
            vec![],
            vec![
                feed("in.input_max", n(10)),
                feed("in", n(5)),
                Is("out", num(50.0)),
            ],
        ),
        // deadband: passes a value that moved by abs or pct or more
        sq(
            "deadband",
            vec![("abs", n(1))],
            vec![
                feed("in", n(10)),
                Sent("out", num(10.0)),
                feed("in", fl(10.5)),
                Quiet("out"),
                feed("in", fl(11.5)),
                Sent("out", num(11.5)),
            ],
        ),
        sq(
            "deadband",
            vec![("pct", n(10))],
            vec![
                feed("in", n(100)),
                feed("in", n(105)),
                Quiet("out"),
                feed("in", n(120)),
                Sent("out", num(120.0)),
            ],
        ),
        // "by abs or pct or more": a move of exactly abs passes
        sq(
            "deadband",
            vec![("abs", n(1))],
            vec![feed("in", n(10)), feed("in", n(11)), Sent("out", num(11.0))],
        ),
        // window: one value per window of time
        sq(
            "window",
            vec![("size_s", n(10)), ("kind", s("sliding"))],
            vec![
                feed_m("in", msg(n(2), Quality::Good, 1_000_000)),
                feed_m("in", msg(n(4), Quality::Good, 2_000_000)),
                Is("out", num(3.0)),
            ],
        ),
        sq(
            "window",
            vec![("size_s", n(1)), ("kind", s("sliding")), ("fn", s("max"))],
            vec![
                feed_m("in", msg(n(9), Quality::Good, 1_000_000)),
                feed_m("in", msg(n(4), Quality::Good, 2_500_000)),
                // the 9 is older than the window
                Is("out", num(4.0)),
            ],
        ),
        sq(
            "window",
            vec![("size_s", n(10)), ("kind", s("sliding")), ("fn", s("rate"))],
            vec![
                feed_m("in", msg(n(10), Quality::Good, 1_000_000)),
                feed_m("in", msg(n(20), Quality::Good, 3_000_000)),
                Is("out", num(5.0)),
            ],
        ),
        sq(
            "window",
            vec![("size_s", n(1)), ("fn", s("sum"))],
            vec![
                feed_m("in", msg(n(1), Quality::Good, 1_000_000)),
                feed_m("in", msg(n(2), Quality::Good, 1_500_000)),
                Quiet("out"),
                Tick(2_100_000),
                Sent("out", num(3.0)),
            ],
        ),
        sq(
            "window",
            vec![("size_s", n(1)), ("fn", s("count"))],
            vec![
                feed_m("in", msg(n(1), Quality::Good, 1_000_000)),
                feed_m("in", msg(n(1), Quality::Good, 1_200_000)),
                feed_m("in", msg(n(1), Quality::Good, 1_400_000)),
                Tick(2_000_000),
                Sent("out", num(3.0)),
            ],
        ),
        // alarm: true while above high or below low, with hysteresis and delays; an event
        sq(
            "alarm",
            vec![("high", n(10)), ("hysteresis", n(2))],
            vec![
                feed_m("in", msg(n(11), Quality::Good, 5)),
                Sent("out", val(b(true))),
                Sent(
                    "event",
                    pred("a rising edge at 11", |v| {
                        get(v, "edge") == Some(&s("rising"))
                            && get(v, "value").and_then(as_num) == Some(11.0)
                    }),
                ),
                feed("in", n(9)),
                Quiet("out"),
                feed("in", n(7)),
                Sent("out", val(b(false))),
            ],
        ),
        sq(
            "alarm",
            vec![("low", n(0))],
            vec![feed("in", n(-1)), Sent("out", val(b(true)))],
        ),
        sq(
            "alarm",
            vec![("high", n(10)), ("delay_s", n(1))],
            vec![
                feed_m("in", msg(n(11), Quality::Good, 1_000_000)),
                Quiet("out"),
                Tick(1_500_000),
                Quiet("out"),
                Tick(2_000_000),
                Sent("out", val(b(true))),
            ],
        ),
    ]
}

/// The general rules of `docs/flow-blocks.md` "How a block works" and "What calculates at
/// start", on a few representative types.
fn rules() -> Vec<Case> {
    vec![
        // rule 7: the worst quality among the inputs, the latest time
        sq(
            "add",
            vec![],
            vec![
                feed_m("in.0", msg(n(2), Quality::Good, 1)),
                feed_m("in.1", msg(n(3), Quality::Uncertain, 5)),
                Is("out", int(5)),
                Q("out", Quality::Uncertain),
                T("out", 5),
            ],
        ),
        sq(
            "concat",
            vec![],
            vec![
                feed_m("in.0", msg(s("a"), Quality::Bad, 9)),
                feed_m("in.1", msg(s("b"), Quality::Good, 3)),
                Is("out", text("ab")),
                Q("out", Quality::Bad),
                T("out", 9),
            ],
        ),
        sq(
            "date_format",
            vec![],
            vec![
                feed_m("in", msg(s("2026-10-29T13:05:09Z"), Quality::Uncertain, 77)),
                Q("out", Quality::Uncertain),
                T("out", 77),
            ],
        ),
        sq(
            "table_filter",
            vec![],
            vec![
                feed_m(
                    "in",
                    msg(tbl(&["a"], vec![vec![n(1)]]), Quality::Uncertain, 8),
                ),
                Q("out", Quality::Uncertain),
                T("out", 8),
            ],
        ),
        // rule 6: an output is sent only when its value or its quality changed
        sq(
            "add",
            vec![],
            vec![
                feed("in.0", n(2)),
                Sent("out", int(2)),
                feed("in.0", n(2)),
                Quiet("out"),
                feed_m("in.0", msg(n(2), Quality::Uncertain, 1)),
                Sent("out", int(2)),
            ],
        ),
        // rule 5: an operand's constant is its value until a sample replaces it
        c(
            "subtract",
            vec![("values", obj(&[("in.1", n(4))]))],
            vec![("in.0", n(10))],
            "out",
            int(6),
        ),
        // a parameter's port replaces its value; a number that is not finite is ignored
        sq(
            "round",
            vec![],
            vec![
                feed("in.precision", n(1)),
                feed("in", fl(1.26)),
                Is("out", num(1.3)),
                feed("in.precision", fl(f64::NAN)),
                feed("in", fl(1.24)),
                Is("out", num(1.2)),
            ],
        ),
        // text results longer than 4 KiB are null with quality bad
        sq(
            "concat",
            vec![],
            vec![
                feed("in.0", s(&"x".repeat(3000))),
                feed("in.1", s(&"y".repeat(3000))),
                Is("out", null()),
                Q("out", Quality::Bad),
            ],
        ),
        sq(
            "split",
            vec![],
            vec![
                feed("in", s(&",".repeat(1000))),
                Is("out", null()),
                Q("out", Quality::Bad),
            ],
        ),
        // start: a pure block with no wired input calculates once from its constants
        sq(
            "add",
            vec![("values", obj(&[("in.0", n(2)), ("in.1", n(3))]))],
            vec![StartUnwired, Is("out", int(5))],
        ),
        sq(
            "add",
            vec![("values", obj(&[("in.0", n(2)), ("in.1", n(3))]))],
            vec![Start, Quiet("out")],
        ),
        sq(
            "table_from_csv",
            vec![("values", obj(&[("in", s("a\n1"))]))],
            vec![StartUnwired, Is("out", table(&["a"], vec![vec![s("1")]]))],
        ),
        sq(
            "date_time",
            vec![("year", n(2026)), ("month", n(10)), ("day", n(29))],
            vec![
                StartUnwired,
                Is("out", num(us("2026-10-29T00:00:00Z") as f64)),
            ],
        ),
        // every other block waits for its first sample, wired or not
        sq("counter", vec![], vec![StartUnwired, Quiet("out")]),
        // a value born at the start only gives the block where it starts from
        sq(
            "counter",
            vec![],
            vec![
                feed_m("in", good(n(1)).at_start()),
                feed("in", n(1)),
                // one count: the sample born at the start was not counted
                Is("out", num(1.0)),
            ],
        ),
        sq(
            "changed",
            vec![],
            vec![
                feed_m("in", good(n(1)).at_start()),
                feed("in", n(2)),
                Sent("on_change", Want::Event),
            ],
        ),
        sq(
            "rising_edge",
            vec![],
            vec![feed_m("in", good(b(true)).at_start()), Quiet("on_edge")],
        ),
        sq(
            "sample_and_hold",
            vec![],
            vec![
                feed("in", n(5)),
                feed_m("trigger", good(b(true)).at_start()),
                Quiet("out"),
            ],
        ),
    ]
}

/// Edges and bounds the documents give, one row each.
fn edges() -> Vec<Case> {
    let deep = |levels: usize| s(&format!("{}{}", "[".repeat(levels), "]".repeat(levels)));
    let wide: Vec<&'static str> = (0..128)
        .map(|i| &*Box::leak(format!("c{i}").into_boxed_str()))
        .collect();
    let wide_table = tbl(&wide, vec![wide.iter().map(|_| n(1)).collect()]);
    vec![
        // `if`: `in.op` takes only an operator the block knows (spec 06 0.2.20)
        sq(
            "if",
            vec![],
            vec![
                feed("in.op", s(">")),
                feed("in.op", s("nonsense")),
                feed("in.0", n(3)),
                feed("in.1", n(2)),
                Is("out", val(b(true))),
            ],
        ),
        // `ms` without a number is 500 (spec 06, second set)
        sq(
            "debounce",
            vec![("ms", s("x"))],
            vec![
                feed("in", n(1)),
                Advance(400),
                Tick(1),
                Quiet("out"),
                Advance(230),
                Tick(2),
                Sent("out", num(1.0)),
            ],
        ),
        // the stopwatch's interval is at least 0.05 s
        sq(
            "stopwatch",
            vec![("enabled", b(true)), ("interval", fl(0.01))],
            vec![Tick(1), Is("out", num(1.0)), Tick(2), Is("out", num(2.0))],
        ),
        // a parsed value is at most 32 levels deep
        c(
            "json_parse",
            vec![],
            vec![("in", deep(32))],
            "parse_error",
            val(b(false)),
        ),
        c(
            "json_parse",
            vec![],
            vec![("in", deep(40))],
            "parse_error",
            val(b(true)),
        ),
        // mode: lists and maps do not count
        c(
            "mode",
            vec![("inputs", arr(vec![s("a"), s("b"), s("c")]))],
            vec![
                ("in.a", obj(&[("x", n(1))])),
                ("in.b", obj(&[("x", n(1))])),
                ("in.c", n(9)),
            ],
            "out",
            num(9.0),
        ),
        // as a bool, null is false
        sq(
            "bool",
            vec![("value", b(true))],
            vec![Start, feed("in", Value::Null), Is("out", val(b(false)))],
        ),
        // a table past 128 columns is null with quality bad
        sq(
            "table_add_row",
            vec![("row", obj(&[("extra", n(2))]))],
            vec![
                feed("in", wide_table),
                Is("out", null()),
                Q("out", Quality::Bad),
            ],
        ),
        // date_range: a new value on in drops the move
        sq(
            "date_range",
            vec![],
            vec![
                feed("in", s("2026-10")),
                feed("next", b(true)),
                feed("in", s("2026-03")),
                Is("start", num(us("2026-03-01T00:00:00Z") as f64)),
            ],
        ),
        // event_gate: the order of the last changes
        sq(
            "event_gate",
            vec![
                ("inputs", arr(vec![s("a"), s("b")])),
                ("log_order", s("last_occurrence")),
            ],
            vec![
                feed("in.a", n(1)),
                feed("in.a", n(2)),
                feed("in.b", n(1)),
                Sent("on_finish", Want::Event),
                Is("order", text("a,b")),
            ],
        ),
        // router: a sample on a case routes too
        sq(
            "router",
            vec![
                ("inputs", arr(vec![s("hi")])),
                ("op", s(">=")),
                ("values", obj(&[("in.hi", n(90))])),
            ],
            vec![
                feed("condition", n(50)),
                feed("in", s("x")),
                Is("else", text("x")),
                feed("in.hi", n(10)),
                Is("out.hi", text("x")),
            ],
        ),
        // table_recorder: a table on reset replaces the rows
        sq(
            "table_recorder",
            vec![],
            vec![
                feed("in.0", n(1)),
                feed(
                    "reset",
                    tbl(&["t", "0"], vec![vec![n(5), n(7)], vec![n(6), n(8)]]),
                ),
                Is(
                    "out",
                    pred("the two rows of the reset", |v| {
                        let r = rows(v);
                        r.len() == 2 && get(&r[1], "t").and_then(as_num) == Some(6.0)
                    }),
                ),
            ],
        ),
        // the variables send only when the value differs
        sq(
            "number",
            vec![("value", n(5))],
            vec![
                Start,
                feed("in", n(5)),
                Quiet("out"),
                feed("in", n(6)),
                Sent("out", num(6.0)),
            ],
        ),
        // `now` takes only an interval_ms of 0 or 100 … 86 400 000 on its port
        sq(
            "now",
            vec![("interval_ms", n(0))],
            vec![feed("in.interval_ms", n(50)), Start, Quiet("out")],
        ),
        // power: an integer that no longer fits is a float
        c(
            "power",
            vec![("exponent", n(19))],
            vec![("in", n(10))],
            "out",
            float(1e19),
        ),
        c("factorial", vec![], vec![("in", fl(0.5))], "out", num(1.0)),
        // modulo: the quotient is a whole number toward 0
        c(
            "modulo",
            vec![("modulo", n(2))],
            vec![("in", fl(7.5))],
            "quotient",
            int(3),
        ),
        // format_number: the digits after the last comma set the group size
        c(
            "format_number",
            vec![("format", s("#,#0"))],
            vec![("in", n(12345))],
            "out",
            text("1,23,45"),
        ),
        // date_format: fraction digits, k and K
        c(
            "date_format",
            vec![("format", s("ss.SSS k K"))],
            vec![("in", s("2026-10-29T00:05:09.250Z"))],
            "out",
            text("09.250 24 0"),
        ),
        c(
            "date_format",
            vec![("format", s("hh a"))],
            vec![("in", s("2026-10-29T00:05:09Z"))],
            "out",
            text("12 AM"),
        ),
        // date_range: week_start, last ranges, the next year
        c(
            "date_range",
            vec![("week_start", s("sunday"))],
            vec![("in", s("thisWeek"))],
            "start",
            pred("a Sunday at 00:00", |v| {
                // 1970-01-04 was a Sunday
                as_num(v).is_some_and(|x| (x as i64) % DAY == 0 && ((x as i64) / DAY) % 7 == 3)
            }),
        ),
        c(
            "date_range",
            vec![],
            vec![("in", s("lastWeek"))],
            "duration",
            num((7 * DAY) as f64),
        ),
        sq(
            "date_range",
            vec![],
            vec![
                feed("in", s("2026")),
                feed("next", b(true)),
                Is("start", num(us("2027-01-01T00:00:00Z") as f64)),
                Is("duration", num(365.0 * DAY as f64)),
            ],
        ),
        // table_rollup: the interval names are taken too
        c(
            "table_rollup",
            vec![("interval", s("oneHour"))],
            vec![(
                "in",
                tbl(
                    &["t", "v"],
                    vec![vec![n(0), n(1)], vec![n(1_800_000_000), n(3)]],
                ),
            )],
            "out",
            table(&["t", "v"], vec![vec![n(0), n(2)]]),
        ),
        // 1d starts at midnight in time_zone
        c(
            "table_rollup",
            vec![
                ("interval", s("1d")),
                ("time_zone", s("Europe/Kyiv")),
                ("method", s("sum")),
            ],
            vec![(
                "in",
                tbl(
                    &["t", "v"],
                    vec![
                        vec![n(us("2026-10-28T21:30:00Z")), n(1)],
                        vec![n(us("2026-10-28T22:30:00Z")), n(2)],
                    ],
                ),
            )],
            "out",
            table(
                &["t", "v"],
                vec![
                    vec![n(us("2026-10-27T22:00:00Z")), n(1)],
                    vec![n(us("2026-10-28T22:00:00Z")), n(2)],
                ],
            ),
        ),
        // table_sort by number reads text that parses
        c(
            "table_sort",
            vec![("column", s("name"))],
            vec![(
                "in",
                tbl(&["name"], vec![vec![s("10")], vec![s("9")], vec![s("100")]]),
            )],
            "out",
            pred("9, 10, 100", |v| names(v) == ["9", "10", "100"]),
        ),
        // table_columns: the other types
        c(
            "table_columns",
            vec![],
            vec![(
                "in",
                tbl(
                    &["m", "l", "y"],
                    vec![vec![
                        obj(&[("a", n(1))]),
                        arr(vec![n(1)]),
                        Value::Bytes(vec![1]),
                    ]],
                ),
            )],
            "out",
            table(
                &["name", "type"],
                vec![
                    vec![s("m"), s("map")],
                    vec![s("l"), s("list")],
                    vec![s("y"), s("bytes")],
                ],
            ),
        ),
        // rows given as lists are taken by position
        c(
            "table_select_columns",
            vec![("columns", s("b"))],
            vec![(
                "in",
                obj(&[
                    ("columns", arr(vec![s("a"), s("b")])),
                    (
                        "rows",
                        arr(vec![arr(vec![n(1), n(2)]), arr(vec![n(3), n(4)])]),
                    ),
                ]),
            )],
            "out",
            table(&["b"], vec![vec![n(2)], vec![n(4)]]),
        ),
        // table_from_csv: a field past 64 KiB is refused
        c(
            "table_from_csv",
            vec![],
            vec![("in", s(&format!("a\n{}", "x".repeat(65 * 1024))))],
            "parse_error",
            val(b(true)),
        ),
        // case: an input left without a pair is not used
        c(
            "case",
            vec![
                ("inputs", arr(vec![s("c1"), s("v1"), s("c2")])),
                (
                    "values",
                    obj(&[("in.c1", n(1)), ("in.v1", s("one")), ("in.c2", n(2))]),
                ),
                ("else", s("none")),
            ],
            vec![("in", n(2))],
            "out",
            text("none"),
        ),
        // if contains: a null other never matches
        c(
            "if",
            vec![("op", s("contains"))],
            vec![("in.0", s("null")), ("in.1", Value::Null)],
            "out",
            val(b(false)),
        ),
        // statistics: at most 1000 numbers count
        c(
            "average",
            vec![],
            vec![(
                "in.0",
                arr((0..1010)
                    .map(|i| if i < 1000 { n(0) } else { n(1000) })
                    .collect()),
            )],
            "out",
            num(0.0),
        ),
        // a string variable takes another value converted to text
        sq(
            "string",
            vec![],
            vec![Start, feed("in", n(5)), Is("out", text("5"))],
        ),
        // event_gate `all`: every change, in order
        sq(
            "event_gate",
            vec![
                ("inputs", arr(vec![s("a"), s("b")])),
                ("log_order", s("all")),
            ],
            vec![
                feed("in.a", n(1)),
                feed("in.a", n(2)),
                feed("in.b", n(1)),
                Is("order", text("a,a,b")),
            ],
        ),
        // a wall time in a DST gap moves forward; one that occurs twice takes the earlier
        c(
            "date_time",
            vec![
                ("month", n(3)),
                ("day", n(29)),
                ("hour", n(3)),
                ("minute", n(30)),
                ("time_zone", s("Europe/Kyiv")),
            ],
            vec![("in.year", n(2026))],
            "out",
            num(us("2026-03-29T01:30:00Z") as f64),
        ),
        c(
            "date_time",
            vec![
                ("month", n(10)),
                ("day", n(25)),
                ("hour", n(3)),
                ("minute", n(30)),
                ("time_zone", s("Europe/Kyiv")),
            ],
            vec![("in.year", n(2026))],
            "out",
            num(us("2026-10-25T00:30:00Z") as f64),
        ),
        // an a/b range's neighbour is shifted by its length
        sq(
            "date_range",
            vec![],
            vec![
                feed("in", s("2026-10-29T00:00:00Z/2026-10-29T11:59:59Z")),
                feed("next", b(true)),
                Is("start", num(us("2026-10-29T12:00:00Z") as f64)),
            ],
        ),
        // log of base 1 is not finite: null
        c(
            "log",
            vec![("base", n(1))],
            vec![("in", n(10))],
            "out",
            null(),
        ),
        c(
            "asin",
            vec![],
            vec![("in", n(1))],
            "out",
            float(DEG * 1f64.asin()),
        ),
        // substring: a length is at most 4 KiB
        c(
            "substring",
            vec![("length", n(100_000))],
            vec![("in", s(&"x".repeat(5000)))],
            "out",
            pred("at most 4 KiB", |v| {
                matches!(v, Value::Str(t) if t.len() <= 4096) || *v == Value::Null
            }),
        ),
    ]
}

// ---------- doc/code mismatches: the documented behaviour, ignored until one side changes ----------

// ---------- the types that need zenoh I/O or the engine ----------

/// `(type, "tests/<file>.rs::<test_fn> covers it")`. The meta test checks that the file holds
/// the test and names the type.
const EXEMPT: &[(&str, &str)] = &[
    (
        "subscribe",
        "tests/behaviours.rs::a_subscribe_follows_the_key_on_its_port covers it",
    ),
    (
        "liveliness",
        "tests/every_block.rs::liveliness_is_true_while_a_token_is_there covers it",
    ),
    (
        "load_value",
        "tests/every_block.rs::load_value_reads_a_stored_value covers it",
    ),
    (
        "list_children",
        "tests/behaviours.rs::load_value_and_list_children_read_inside_their_scope covers it",
    ),
    (
        "load_history",
        "tests/every_block.rs::load_history_gives_the_rows_as_a_table covers it",
    ),
    (
        "get_node",
        "tests/blocks3.rs::get_node_reads_a_nodes_summary_and_actions covers it",
    ),
    (
        "set",
        "tests/commands.rs::set_writes_on_in_by_default_and_on_trigger covers it",
    ),
    (
        "invoke",
        "tests/commands.rs::a_trigger_runs_on_a_change_and_never_on_a_start_value covers it",
    ),
    (
        "publish",
        "tests/behaviours.rs::load_value_and_list_children_read_inside_their_scope covers it",
    ),
    ("wasm", "tests/flow.rs::wasm_node_hot_load covers it"),
];

/// The sources of the test files an exemption may name.
fn test_source(file: &str) -> Option<&'static str> {
    Some(match file {
        "tests/behaviours.rs" => include_str!("behaviours.rs"),
        "tests/blocks.rs" => include_str!("blocks.rs"),
        "tests/blocks2.rs" => include_str!("blocks2.rs"),
        "tests/blocks3.rs" => include_str!("blocks3.rs"),
        "tests/commands.rs" => include_str!("commands.rs"),
        "tests/every_block.rs" => include_str!("every_block.rs"),
        "tests/flow.rs" => include_str!("flow.rs"),
        "tests/nodes.rs" => include_str!("nodes.rs"),
        _ => return None,
    })
}

#[test]
fn every_catalog_type_has_a_value_case_or_a_named_test() {
    let catalog: Vec<&str> = wyrm_flow::catalog::types().map(|t| t.ty).collect();
    let all = cases();
    let covered: std::collections::BTreeSet<&str> = all.iter().map(|c| c.ty).collect();
    let mut problems = Vec::new();
    for ty in &catalog {
        let exempt = EXEMPT.iter().any(|(t, _)| t == ty);
        // a type whose only rows are mismatches has no passing check
        let passing = all.iter().any(|c| c.ty == *ty && c.mismatch.is_none());
        match (passing, exempt) {
            (false, false) => problems.push(format!("{ty}: no case and no exemption")),
            (true, true) => problems.push(format!("{ty}: both a case and an exemption")),
            _ => {}
        }
    }
    for ty in &covered {
        if !catalog.contains(ty) {
            problems.push(format!("{ty}: a case for a type the catalog does not have"));
        }
    }
    for (ty, why) in EXEMPT {
        if !catalog.contains(ty) {
            problems.push(format!("{ty}: exempt, but the catalog does not have it"));
        }
        let Some(place) = why.strip_suffix(" covers it") else {
            problems.push(format!(
                "{ty}: the reason must be '<file>::<test> covers it'"
            ));
            continue;
        };
        let Some((file, test)) = place.split_once("::") else {
            problems.push(format!("{ty}: no '::' in {place}"));
            continue;
        };
        match test_source(file) {
            None => problems.push(format!("{ty}: {file} is not a test file of this crate")),
            Some(src) => {
                // this file names every exempt type in EXEMPT itself: search it without that list
                let src = match src.split_once("const EXEMPT") {
                    Some((head, rest)) => {
                        let tail = rest.split_once("\n];").map_or("", |(_, t)| t);
                        format!("{head}{tail}")
                    }
                    None => src.to_owned(),
                };
                if !src.contains(&format!("fn {test}(")) {
                    problems.push(format!("{ty}: {file} has no fn {test}"));
                }
                if !src.contains(&format!("\"{ty}\"")) {
                    problems.push(format!("{ty}: {file} never names the type"));
                }
            }
        }
    }
    // every mismatch id has its ignored test
    let src = include_str!("every_block.rs");
    for id in all.iter().filter_map(|c| c.mismatch) {
        if !src.contains(&format!("run_mismatch(\"{id}\")")) {
            problems.push(format!("mismatch {id}: no #[ignore] test runs it"));
        }
    }
    assert!(problems.is_empty(), "{}", problems.join("\n"));
}

// ---------- reader tests for the exempt types that had none ----------

/// Feed what a node injected into itself back into it until `done` holds (or ~5 s pass).
async fn pump(
    node: &mut dyn Node,
    io: &Io,
    inbox: &Inbox,
    sent: &mut Sent,
    done: impl Fn(&Sent) -> bool,
) {
    for _ in 0..100 {
        let msgs: Vec<_> = inbox.lock().unwrap().drain(..).collect();
        for (p, m) in msgs {
            let mut out = Out::default();
            node.input(&p, m, io, &mut out);
            sent.extend(out.0);
        }
        if done(sent) {
            return;
        }
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
}

fn last_on<'a>(sent: &'a Sent, port: &str) -> Option<&'a Msg> {
    sent.iter().rev().find(|(p, _)| p == port).map(|(_, m)| m)
}

#[tokio::test(flavor = "multi_thread")]
async fn liveliness_is_true_while_a_token_is_there() {
    let e = env().await;
    let (io, inbox) = capturing(&e.io);
    let token = e
        .session
        .liveliness()
        .declare_token("wy/test/downstream/probe/dev")
        .await
        .unwrap();
    let mut node = build("liveliness", &[("key", s("downstream/probe/dev"))]).unwrap();
    node.start(&io);
    let mut sent = Vec::new();
    pump(&mut *node, &io, &inbox, &mut sent, |s| {
        last_on(s, "out").is_some()
    })
    .await;
    assert_eq!(last_on(&sent, "out").map(|m| m.v.clone()), Some(b(true)));
    // the token goes: false
    token.undeclare().await.unwrap();
    pump(&mut *node, &io, &inbox, &mut sent, |s| {
        last_on(s, "out").is_some_and(|m| m.v == b(false))
    })
    .await;
    assert_eq!(last_on(&sent, "out").map(|m| m.v.clone()), Some(b(false)));
}

/// A stand-in for the broker's storage and historian on `wy/test/downstream/probe/**`: `~val`
/// answers with a sample, `~val?history=` with history rows.
async fn fake_store(session: &zenoh::Session) -> tokio::task::JoinHandle<()> {
    let q = session
        .declare_queryable("wy/test/downstream/probe/**")
        .await
        .unwrap();
    tokio::spawn(async move {
        while let Ok(query) = q.recv_async().await {
            let key = query.key_expr().clone();
            if !key.as_str().ends_with("/~val") {
                continue;
            }
            let bytes = if query.parameters().as_str().contains("history=") {
                wyrm_core::codec::to_vec(&vec![
                    HistRow {
                        t: 1_000,
                        v: n(10),
                        q: Some(Quality::Good),
                    },
                    HistRow {
                        t: 2_000,
                        v: fl(11.5),
                        q: Some(Quality::Uncertain),
                    },
                    HistRow {
                        t: 3_000,
                        v: n(12),
                        q: None,
                    },
                ])
                .unwrap()
            } else {
                wyrm_core::codec::to_vec(&Sample {
                    v: fl(21.5),
                    q: Quality::Uncertain,
                    t: 123,
                })
                .unwrap()
            };
            let _ = query.reply(key, bytes).await;
        }
    })
}

#[tokio::test(flavor = "multi_thread")]
async fn load_value_reads_a_stored_value() {
    let e = env().await;
    let store = fake_store(&e.session).await;
    let (io, inbox) = capturing(&e.io);
    let mut node = build("load_value", &[("key", s("downstream/probe/t1"))]).unwrap();
    node.start(&io);
    let mut sent = Vec::new();
    pump(&mut *node, &io, &inbox, &mut sent, |s| {
        last_on(s, "ok").is_some() || last_on(s, "error").is_some()
    })
    .await;
    // `out` carries the stored value with its quality and time
    let out = last_on(&sent, "out").unwrap_or_else(|| panic!("no out: {sent:?}"));
    assert_eq!(
        (out.v.clone(), out.q, out.t),
        (fl(21.5), Quality::Uncertain, 123)
    );
    assert!(Want::Event
        .check("ok", &last_on(&sent, "ok").unwrap().v)
        .is_ok());
    store.abort();
}

#[tokio::test(flavor = "multi_thread")]
async fn load_history_gives_the_rows_as_a_table() {
    let e = env().await;
    let store = fake_store(&e.session).await;
    let (io, inbox) = capturing(&e.io);
    let mut node = build(
        "load_history",
        &[
            ("key", s("downstream/probe/t1")),
            ("time_range", s("2026-10")),
        ],
    )
    .unwrap();
    node.start(&io);
    let mut sent = Vec::new();
    pump(&mut *node, &io, &inbox, &mut sent, |s| {
        last_on(s, "ok").is_some() || last_on(s, "error").is_some()
    })
    .await;
    // a table {t, v, q}: q the quality code, null for a rollup row
    let out = last_on(&sent, "out").unwrap_or_else(|| panic!("no out: {sent:?}"));
    let want = table(
        &["t", "v", "q"],
        vec![
            vec![n(1_000), n(10), n(i64::from(Quality::Good.code()))],
            vec![n(2_000), fl(11.5), n(i64::from(Quality::Uncertain.code()))],
            vec![n(3_000), n(12), Value::Null],
        ],
    );
    want.check("out", &out.v).unwrap();
    assert!(Want::Event
        .check("ok", &last_on(&sent, "ok").unwrap().v)
        .is_ok());
    // an answer that reached the limit: `ok` carries truncated and rows
    let mut node = build(
        "load_history",
        &[
            ("key", s("downstream/probe/t1")),
            ("time_range", s("2026-10")),
            ("limit", n(3)),
        ],
    )
    .unwrap();
    node.start(&io);
    let mut sent = Vec::new();
    pump(&mut *node, &io, &inbox, &mut sent, |s| {
        last_on(s, "ok").is_some()
    })
    .await;
    let ok = &last_on(&sent, "ok")
        .unwrap_or_else(|| panic!("no ok: {sent:?}"))
        .v;
    assert_eq!(get(ok, "truncated"), Some(&b(true)), "{ok:?}");
    assert_eq!(get(ok, "rows").and_then(as_num), Some(3.0), "{ok:?}");
    store.abort();
}
