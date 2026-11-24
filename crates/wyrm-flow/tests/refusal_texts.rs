//! Audit T7 (docs/rust-rules.md §8): every refusal of a node's config, of a script, of a
//! scope and of a key from a port, as the text an operator reads. The texts are in
//! `refusal_texts.txt`, written by this test while these errors were a `String`
//! (`WYRM_FLOW_REFUSALS_OUT=<file>` writes what the code says now, to compare two builds
//! byte by byte). The typed errors say the same.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    reason = "test code: a failed step fails the test"
)]

use std::collections::BTreeMap;
use std::fmt::Display;
use std::fmt::Write as _;
use std::sync::Arc;
use wyrm_client::WyrmClient;
use wyrm_core::{Quality, Value};
use wyrm_flow::artifacts::Artifacts;
use wyrm_flow::nodes::{self, Io, Mode, Msg, Node, Out, WasmCfg};
use wyrm_flow::scope::Scope;
use wyrm_flow::{def, script};
use wyrm_link_mock::{Mock, MockConfig};
use wyrm_link_sdk::harness::isolated_config;
use wyrm_link_sdk::{LinkConfig, LinkHandle};

type Cfg = BTreeMap<String, Value>;

fn cfg(kv: &[(&str, Value)]) -> Cfg {
    kv.iter()
        .map(|(k, v)| ((*k).to_owned(), v.clone()))
        .collect()
}

fn map(kv: &[(&str, Value)]) -> Value {
    Value::Map(cfg(kv))
}

fn arr(items: &[Value]) -> Value {
    Value::Array(items.to_vec())
}

fn s(x: &str) -> Value {
    Value::Str(x.to_owned())
}

fn names(n: &[&str]) -> Value {
    arr(&n.iter().map(|x| s(x)).collect::<Vec<_>>())
}

fn u(x: u64) -> Value {
    Value::UInt(x)
}

/// What was refused, as text; a call that was not refused fails the test.
fn said<T, E: Display>(what: &str, r: Result<T, E>) -> String {
    match r {
        Err(e) => e.to_string(),
        Ok(_) => panic!("{what}: not refused"),
    }
}

/// The lines of the table: `<what> => <text>`.
#[derive(Default)]
struct Lines(String);

impl Lines {
    fn add(&mut self, what: &str, text: &str) {
        // Zenoh ends its own error with the place in its source, a path of the build host
        let text = match text.find(" at /") {
            Some(i) => format!("{} at <zenoh source>", &text[..i]),
            None => text.to_owned(),
        };
        writeln!(self.0, "{what} => {text}").unwrap();
    }

    fn ports(&mut self, ty: &str, kv: &[(&str, Value)]) {
        let c = cfg(kv);
        let what = format!("ports {ty} {}", show(&c));
        self.add(&what, &said(&what, nodes::ports(ty, &c)));
    }

    fn script(&mut self, ty: &str, kv: &[(&str, Value)]) {
        let c = cfg(kv);
        let what = format!("check_script {ty} {}", show(&c));
        self.add(&what, &said(&what, nodes::check_script(ty, &c)));
    }

    fn build(&mut self, ty: &str, kv: &[(&str, Value)]) {
        let c = cfg(kv);
        let what = format!("build {ty} {}", show(&c));
        self.add(&what, &said(&what, nodes::build(ty, "f", "n", &c)));
    }

    fn compile(&mut self, what: &str, d: &Value) {
        let what = format!("compile {what}");
        self.add(&what, &said(&what, def::compile(d)));
    }
}

/// A config in one line; a long list or text is cut, the line is only a name.
fn show(c: &Cfg) -> String {
    let mut t = format!("{c:?}");
    if t.len() > 120 {
        let mut end = 120;
        while !t.is_char_boundary(end) {
            end -= 1;
        }
        t.truncate(end);
        t.push('…');
    }
    t
}

fn node_configs(l: &mut Lines) {
    // the helpers every type reads its fields with
    l.ports("timer", &[("period_ms", s("x"))]);
    l.ports("timer", &[("period_ms", Value::Float(f64::NAN))]);
    l.ports("publish", &[("node", u(1))]);
    l.ports("filter", &[]);
    l.ports("set", &[("path", s("a")), ("allow_bad", u(1))]);
    l.ports("timer", &[("x", u(1))]);
    // sources
    l.ports("subscribe", &[]);
    l.ports("liveliness", &[("key", u(1))]);
    l.ports("subscribe", &[("key_scope", u(1))]);
    l.ports("timer", &[]);
    l.ports("timer", &[("period_ms", u(5))]);
    l.ports("const", &[]);
    // expression
    l.ports("expression", &[("inputs", names(&["a"]))]);
    l.ports("expression", &[("inputs", names(&["a"])), ("expr", u(1))]);
    l.ports("expression", &[("expr", s("1"))]);
    l.ports("expression", &[("expr", s("1")), ("inputs", arr(&[]))]);
    l.ports(
        "expression",
        &[("expr", s("1")), ("inputs", names(&["a b"]))],
    );
    l.ports("expression", &[("expr", s("1")), ("inputs", arr(&[u(1)]))]);
    l.ports(
        "expression",
        &[
            ("expr", s("1")),
            ("inputs", names(&["a"])),
            ("trigger", s("x")),
        ],
    );
    l.ports(
        "expression",
        &[
            ("expr", s("1")),
            ("inputs", names(&["a"])),
            ("trigger", u(1)),
        ],
    );
    l.ports(
        "expression",
        &[
            ("expr", s("1")),
            ("inputs", names(&["a"])),
            ("quality", s("x")),
        ],
    );
    // operators
    l.ports("scale", &[("k", s("x"))]);
    l.ports("scale", &[("input_min", s("x"))]);
    l.ports("scale", &[("gain", u(1))]);
    l.ports("deadband", &[]);
    l.ports("deadband", &[("abs", s("x"))]);
    l.ports("window", &[("size_s", u(1)), ("kind", s("x"))]);
    l.ports("window", &[("size_s", u(1)), ("fn", s("x"))]);
    l.ports("window", &[("size_s", u(1)), ("max_samples", u(0))]);
    l.ports("window", &[("size_s", u(1)), ("max_samples", s("x"))]);
    l.ports("window", &[]);
    l.ports("window", &[("size_s", u(0))]);
    l.ports("alarm", &[]);
    l.ports("alarm", &[("high", u(1)), ("hysteresis", s("x"))]);
    l.ports("alarm", &[("high", u(1)), ("delay_s", s("x"))]);
    l.ports("alarm", &[("high", u(1)), ("return_delay_s", s("x"))]);
    l.ports("alarm", &[("high", u(1)), ("on_bad", s("x"))]);
    l.ports("latch", &[("reset", s("x"))]);
    l.ports("delay", &[]);
    l.ports("filter", &[("expr", u(1))]);
    // sinks
    l.ports("publish", &[]);
    l.ports("publish", &[("node", s(""))]);
    l.ports("publish", &[("node", s("~x"))]);
    l.ports("publish", &[("node", s("a/b"))]);
    l.ports("publish", &[("node", s("a")), ("meta", u(1))]);
    l.ports("nope", &[]);
    // wasm
    let sha = "0".repeat(64);
    l.ports("wasm", &[]);
    l.ports("wasm", &[("artifact", s("zz"))]);
    l.ports("wasm", &[("artifact", s(&sha)), ("oops", u(1))]);
    l.ports("wasm", &[("artifact", s(&sha)), ("fuel", u(1))]);
    l.ports("wasm", &[("artifact", s(&sha)), ("memory_mb", u(0))]);
    l.ports("wasm", &[("artifact", s(&sha)), ("inputs", arr(&[]))]);
    l.ports("wasm", &[("artifact", s(&sha)), ("inputs", u(1))]);
    l.ports(
        "wasm",
        &[("artifact", s(&sha)), ("inputs", names(&["a", "a"]))],
    );
    l.ports(
        "wasm",
        &[("artifact", s(&sha)), ("outputs", names(&["__a"]))],
    );
    let what = "WasmCfg::parse {}";
    l.add(what, &said(what, WasmCfg::parse(&cfg(&[]))));
    let what = "max_samples 100001";
    l.add(
        what,
        &said(
            what,
            nodes::max_samples(&cfg(&[("max_samples", u(100_001))])),
        ),
    );
}

fn command_configs(l: &mut Lines) {
    for ty in ["invoke", "set"] {
        l.ports(ty, &[]);
        l.ports(ty, &[("path", u(1))]);
        l.ports(ty, &[("path", s("a")), ("auto_run", u(1))]);
        l.ports(ty, &[("path", s("a")), ("enabled", u(1))]);
        l.ports(ty, &[("path", s("a")), ("run_on_start", u(1))]);
        l.ports(ty, &[("path", s("a")), ("interval_ms", u(5))]);
        l.ports(ty, &[("path", s("a")), ("interval_ms", s("x"))]);
        l.ports(ty, &[("path", s("a")), ("oops", u(1))]);
        l.ports(ty, &[("path", s("a")), ("action", s("a")), ("on", s("x"))]);
    }
    fn invoke<'a>(more: &[(&'a str, Value)]) -> Vec<(&'a str, Value)> {
        let mut kv = vec![("path", s("a")), ("action", s("go"))];
        kv.extend(more.iter().map(|(k, v)| (*k, v.clone())));
        kv
    }
    l.ports("invoke", &[("path", s("a"))]);
    l.ports("invoke", &invoke(&[("args", u(1))]));
    l.ports("invoke", &invoke(&[("args", map(&[("__x", Value::Null)]))]));
    l.ports("invoke", &invoke(&[("args", map(&[("", Value::Null)]))]));
    let long = "a".repeat(129);
    l.ports("invoke", &invoke(&[("args", map(&[(&long, Value::Null)]))]));
    let many: Vec<(String, Value)> = (0..65).map(|i| (format!("a{i}"), Value::Null)).collect();
    l.ports(
        "invoke",
        &invoke(&[("args", Value::Map(many.into_iter().collect()))]),
    );
    l.ports("set", &[("path", s("a")), ("deadband", s("x"))]);
}

fn reader_configs(l: &mut Lines) {
    for ty in ["load_value", "list_children", "load_history", "get_node"] {
        l.ports(ty, &[]);
        l.ports(ty, &[("oops", u(1))]);
    }
    let key = ("key", s("downstream/m/p0"));
    l.ports("load_value", &[key.clone(), ("auto_run", u(1))]);
    l.ports("load_value", &[key.clone(), ("enabled", u(1))]);
    l.ports("load_value", &[key.clone(), ("interval_ms", u(5))]);
    l.ports("load_value", &[key.clone(), ("interval_ms", s("x"))]);
    fn history(k: &str, v: Value) -> Vec<(&str, Value)> {
        vec![("key", s("downstream/m/p0")), (k, v)]
    }
    for k in ["time_range", "rollup", "window", "time_zone"] {
        // not a text
        let kv = history(k, u(1));
        l.ports("load_history", &kv);
    }
    l.ports("load_history", &history("rollup", s("median")));
    l.ports("load_history", &history("limit", u(0)));
    l.ports("load_history", &history("limit", u(10_001)));
    l.ports("load_history", &history("limit", Value::Float(2.5)));
    l.ports("load_history", &history("time_zone", s("Nowhere/City")));
    l.ports("load_history", &history("time_range", s("soon")));
    l.ports("load_history", &history("window", s("5x")));
    l.ports("load_history", &history("window", s("0m")));
    l.ports(
        "load_history",
        &history("time_range", s("1960-01-01T00:00:00/1960-01-02T00:00:00")),
    );
}

fn block_configs(l: &mut Lines) {
    l.ports("add", &[("oops", u(1))]);
    l.ports("add", &[("inputs", names(&["a", "a"]))]);
    l.ports("add", &[("inputs", arr(&[]))]);
    l.ports("add", &[("inputs", names(&["a b"]))]);
    l.ports("if", &[("inputs", names(&["then", "b"]))]);
    let many: Vec<String> = (0..65).map(|i| i.to_string()).collect();
    let many: Vec<&str> = many.iter().map(String::as_str).collect();
    l.ports("add", &[("inputs", names(&many))]);
    l.ports("if", &[("op", s("xor"))]);
    l.ports("if", &[("op", u(1))]);
    l.ports("case", &[("op", s("and"))]);
    l.ports("case", &[("op", u(1))]);
    l.ports("router", &[("op", s("and"))]);
    l.ports("add", &[("values", u(1))]);
    l.ports("add", &[("values", map(&[("in.7", u(1))]))]);
    l.ports("round", &[("values", map(&[("in.precision", u(1))]))]);
    l.ports("stopwatch", &[("values", map(&[("reset", u(1))]))]);
    l.ports("number", &[("values", map(&[("in", u(1))]))]);
    l.ports("now", &[("interval_ms", u(5))]);
    l.ports("now", &[("interval_ms", s("x"))]);
    // a block's build runs the same check
    l.build("add", &[("oops", u(1))]);
    l.build("if", &[("op", s("xor"))]);
    l.build("add", &[("values", map(&[("in.7", u(1))]))]);
}

fn table_configs(l: &mut Lines) {
    for ty in ["table_group_by", "table_rollup"] {
        l.script(ty, &[("aggregates", u(1))]);
        let many: Vec<Value> = (0..129).map(|_| map(&[("column", s("a"))])).collect();
        l.script(ty, &[("aggregates", arr(&many))]);
        l.script(ty, &[("aggregates", arr(&[u(1)]))]);
        l.script(ty, &[("aggregates", arr(&[map(&[])]))]);
        l.script(ty, &[("aggregates", arr(&[map(&[("column", s(""))])]))]);
        l.script(
            ty,
            &[(
                "aggregates",
                arr(&[map(&[("column", s("a")), ("method", s("x"))])]),
            )],
        );
    }
    for ty in ["table_filter", "table_remove_rows", "table_edit_rows"] {
        l.script(ty, &[("expr", u(1))]);
        l.script(ty, &[("expr", s("row.a +"))]);
        l.script(ty, &[("expr", s("nope > 1"))]);
        l.build(ty, &[("expr", u(1))]);
        l.build(ty, &[("expr", s("row.a +"))]);
    }
    let ty = "table_map_columns";
    l.script(ty, &[("mapping", u(1))]);
    let many: Vec<Value> = (0..129)
        .map(|_| map(&[("name", s("a")), ("from", s("b"))]))
        .collect();
    l.script(ty, &[("mapping", arr(&many))]);
    l.script(ty, &[("mapping", arr(&[u(1)]))]);
    l.script(ty, &[("mapping", arr(&[map(&[("name", s("a"))])]))]);
    l.script(
        ty,
        &[("mapping", arr(&[map(&[("name", s("")), ("from", s("b"))])]))],
    );
    let long = "a".repeat(257);
    l.script(
        ty,
        &[(
            "mapping",
            arr(&[map(&[("name", s(&long)), ("from", s("b"))])]),
        )],
    );
    let bad = arr(&[map(&[("name", s("c")), ("from", s("= row.a +"))])]);
    l.script(ty, &[("mapping", bad.clone())]);
    l.build(ty, &[("mapping", bad)]);
    l.build(ty, &[("mapping", u(1))]);
}

fn scripts(l: &mut Lines) {
    let ins = ("inputs", names(&["a"]));
    l.script("expression", &[ins.clone(), ("expr", s("a.v +"))]);
    l.script("expression", &[ins.clone(), ("expr", s("b.v + 1"))]);
    l.script("expression", std::slice::from_ref(&ins));
    l.script("expression", &[("expr", s("1"))]);
    l.script("filter", &[("expr", s("v >"))]);
    l.script("filter", &[("expr", s("w > 1"))]);
    l.script("filter", &[]);
    // at build the script's own text, with no field before it
    l.build("expression", &[ins.clone(), ("expr", s("a.v +"))]);
    l.build("expression", std::slice::from_ref(&ins));
    l.build("expression", &[("expr", s("1"))]);
    l.build(
        "expression",
        &[ins.clone(), ("expr", s("1")), ("trigger", s("x"))],
    );
    l.build("expression", &[ins, ("expr", s("1")), ("quality", s("x"))]);
    l.build("filter", &[("expr", s("v >"))]);
    l.build("filter", &[]);
    // the script module itself
    let engine = script::engine();
    for expr in ["1 +", "x +", "y", "let", "\"open"] {
        let what = format!("script::compile {expr:?}");
        l.add(&what, &said(&what, script::compile(&engine, expr, &["x"])));
    }
    for expr in [
        "throw \"stop\"",
        "x.nope()",
        "1 / 0",
        "x + 1",
        "let a = []; a[3]",
        "loop { }",
    ] {
        let ast = script::compile(&engine, expr, &["x"]).unwrap();
        let mut vars = script::Vars::new(&["x"]);
        let what = format!("script::eval {expr:?}");
        l.add(&what, &said(&what, script::eval(&engine, &ast, &mut vars)));
    }
}

fn builds(l: &mut Lines) {
    let sha = "0".repeat(64);
    l.build("nope", &[]);
    l.build("wasm", &[("artifact", s(&sha))]);
    l.build("wasm", &[]);
    l.build("timer", &[("period_ms", s("x"))]);
    l.build("scale", &[("k", s("x"))]);
    l.build("deadband", &[("abs", s("x"))]);
    l.build("window", &[("kind", s("x"))]);
    l.build("window", &[("fn", s("x"))]);
    l.build("window", &[("max_samples", u(0))]);
    l.build("window", &[("size_s", s("x"))]);
    l.build("alarm", &[("on_bad", s("x"))]);
    l.build("alarm", &[("high", s("x"))]);
    l.build("latch", &[("reset", s("x"))]);
    l.build("delay", &[("ms", s("x"))]);
    l.build("publish", &[]);
    l.build("invoke", &[]);
    l.build("set", &[("path", s("a")), ("on", s("x"))]);
    l.build("load_value", &[]);
    l.build("load_history", &[("key", s("a")), ("window", s("5x"))]);
    // a `wasm` node with a store: the artifact is not there, or its name is no hash
    let dir = std::env::temp_dir().join(format!("wyrm-flow-refusals-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    let store = Artifacts::new(&dir);
    let c = cfg(&[("artifact", s(&sha))]);
    let what = "build_with wasm, no such artifact";
    l.add(
        what,
        &said(
            what,
            nodes::build_with("wasm", "f", "n", &c, Some(&store), &Mode::Live),
        ),
    );
    let what = "WasmCfg::check, no such artifact";
    l.add(what, &said(what, WasmCfg::parse(&c).unwrap().check(&store)));
    let _ = std::fs::remove_dir_all(&dir);
}

fn scopes(l: &mut Lines) {
    for written in [
        "sys/**",
        "wy/other/downstream/**",
        "upstream/x",
        "downstreams/x",
        "downstream//x",
        "downstream/a**",
        "downstream/a b#",
        "downstream/x/",
    ] {
        let what = format!("Scope::new {written:?}");
        l.add(&what, &said(&what, Scope::new("s", written)));
    }
    let sc = Scope::new("s", "downstream/modbus/line1/**").unwrap();
    let long = format!("downstream/modbus/line1/{}", "a".repeat(512));
    for v in [
        u(1),
        Value::Null,
        s(""),
        s(&long),
        s("downstream/modbus/line1/~val"),
        s("downstream/modbus/line1//x"),
        s("downstream/modbus/line1/*"),
        s("downstream/modbus/line1/a b"),
        s("sys/audit"),
        s("wy/other/downstream/modbus/line1/x"),
        s("downstream/modbus/line2/x"),
        s("downstream/modbus"),
    ] {
        let what = format!("admit {}", show(&cfg(&[("key", v.clone())])));
        l.add(&what, &said(&what, sc.admit(&v)));
    }
}

fn flow(nodes: &[(&str, Value)], more: &[(&str, Value)]) -> Value {
    let mut kv = vec![
        ("id", s("f")),
        ("version", u(1)),
        ("nodes", map(nodes)),
        ("edges", arr(&[])),
    ];
    kv.extend(more.iter().map(|(k, v)| (*k, v.clone())));
    map(&kv)
}

fn node(ty: &str, kv: &[(&str, Value)]) -> Value {
    let mut kv: Vec<(&str, Value)> = kv.to_vec();
    kv.push(("type", s(ty)));
    map(&kv)
}

fn definitions(l: &mut Lines) {
    // a node's config refusal and a script's, with the place the compiler names
    l.compile(
        "a node config",
        &flow(&[("t", node("timer", &[("period_ms", u(5))]))], &[]),
    );
    l.compile("a node type", &flow(&[("t", node("nope", &[]))], &[]));
    l.compile(
        "a script",
        &flow(
            &[(
                "x",
                node(
                    "expression",
                    &[("inputs", names(&["a"])), ("expr", s("a.v +"))],
                ),
            )],
            &[],
        ),
    );
    l.compile(
        "a table script",
        &flow(
            &[("x", node("table_filter", &[("expr", s("row.a +"))]))],
            &[],
        ),
    );
    // a constant of a custom block's input, into the inner node
    let port = |to: &str| map(&[("name", s("x")), ("to", arr(&[s(to)])), ("default", u(1))]);
    let block = |inner: Value, to: &str| {
        map(&[
            ("nodes", map(&[("f", inner)])),
            ("inputs", arr(&[port(to)])),
        ])
    };
    let with = |b: Value| {
        flow(
            &[("u", node("block:b", &[]))],
            &[("blocks", map(&[("b", b)]))],
        )
    };
    l.compile(
        "a constant an inner input does not take",
        &with(block(node("filter", &[("expr", s("v > 1"))]), "f.in")),
    );
    l.compile(
        "a constant into values that is no map",
        &with(block(node("add", &[("values", u(1))]), "f.in.0")),
    );
    l.compile(
        "a constant into args that is no map",
        &with(block(
            node(
                "invoke",
                &[("path", s("a")), ("action", s("go")), ("args", u(1))],
            ),
            "f.arg.x",
        )),
    );
    // the targets of a definition that does not parse
    let what = "command_targets, no definition";
    l.add(what, &said(what, wyrm_flow::command_targets(&u(1), "s")));
    let what = "command_targets, a node without a type";
    l.add(
        what,
        &said(
            what,
            wyrm_flow::command_targets(&flow(&[("t", map(&[]))], &[]), "s"),
        ),
    );
}

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

fn made(ty: &str, kv: &[(&str, Value)]) -> Box<dyn Node> {
    let c = cfg(kv);
    nodes::ports(ty, &c).unwrap_or_else(|e| panic!("{ty}: {e}"));
    nodes::build(ty, "f", "n", &c).unwrap_or_else(|e| panic!("{ty}: {e}"))
}

/// What a node sends on `error` for `v` on `port`: the whole sample's value.
fn error_of(n: &mut dyn Node, io: &Io, port: &str, v: Value) -> String {
    let mut out = Out::default();
    n.input(port, Msg::new(v, Quality::Good, 1), io, &mut out);
    let e = out
        .0
        .iter()
        .rev()
        .find(|(p, _)| p == "error")
        .map(|(_, m)| m.v.get().clone());
    match e {
        Some(Value::Str(t)) => t,
        // an event `{event, id, code, message}`: the code and the text
        Some(Value::Map(m)) => format!(
            "code {:?}, message {:?}",
            m.get("code").unwrap_or(&Value::Null),
            m.get("message").unwrap_or(&Value::Null)
        ),
        other => panic!("{port}: no error, {other:?}"),
    }
}

fn table(rows: &[&[(&str, Value)]]) -> Value {
    let columns: Vec<Value> = rows
        .first()
        .map(|r| r.iter().map(|(k, _)| s(k)).collect())
        .unwrap_or_default();
    map(&[
        ("columns", Value::Array(columns)),
        ("rows", Value::Array(rows.iter().map(|r| map(r)).collect())),
    ])
}

/// What a running node says on its `error` output.
async fn at_run_time(l: &mut Lines) {
    let e = env().await;
    let io = &e.io;
    let rows = table(&[&[("i", u(0))], &[("i", u(1))], &[("i", u(2))]]);
    // a per-row script that fails at a row
    for (ty, kv) in [
        (
            "table_filter",
            vec![("expr", s("if row.i == 1 { throw \"one\" } true"))],
        ),
        ("table_remove_rows", vec![("expr", s("row.nope.x()"))]),
        (
            "table_edit_rows",
            vec![("expr", s("row.i / 0 > 1")), ("cells", map(&[("a", u(1))]))],
        ),
        (
            "table_map_columns",
            vec![(
                "mapping",
                arr(&[map(&[("name", s("c")), ("from", s("= row.i + nope()"))])]),
            )],
        ),
        // one row's script runs past the engine's own bound
        (
            "table_filter",
            vec![("expr", s("let n = 0; while n < 1000000 { n += 1 } true"))],
        ),
    ] {
        let mut n = made(ty, &kv);
        let what = format!("run {ty} {}", show(&cfg(&kv)));
        l.add(&what, &error_of(n.as_mut(), io, "in", rows.clone()));
    }
    // the scripts of one table take longer than their budget: the check is made before each
    // row, so the table ends at the first row after the budget
    let many: Vec<Value> = (0..10_000).map(|i| map(&[("i", u(i))])).collect();
    let many = map(&[("columns", names(&["i"])), ("rows", Value::Array(many))]);
    let mut n = made(
        "table_filter",
        &[("expr", s("let n = 0; while n < 1000 { n += 1 } true"))],
    );
    l.add(
        "run table_filter, 10000 rows of a slow script",
        &error_of(n.as_mut(), io, "in", many),
    );
    // a key from a port
    for ty in ["subscribe", "liveliness"] {
        // no scope
        let mut n = made(ty, &[("key", s("downstream/m/p0"))]);
        n.start(io);
        let what = format!("run {ty} without a scope, a key on in.key");
        l.add(
            &what,
            &error_of(n.as_mut(), io, "in.key", s("downstream/m/p1")),
        );
        // a scope that is none: checked by the compiler, never by the node's own check
        let mut n = made(ty, &[("key_scope", s("sys/**"))]);
        n.start(io);
        let what = format!("run {ty} with the scope sys/**, a key on in.key");
        l.add(
            &what,
            &error_of(n.as_mut(), io, "in.key", s("downstream/m/p1")),
        );
        for (name, v) in [
            ("a number", u(1)),
            ("an empty text", s("")),
            ("a key outside", s("downstream/x/p0")),
            ("a pattern", s("downstream/m/*")),
            ("another section", s("sys/audit")),
        ] {
            let mut n = made(ty, &[("key_scope", s("downstream/m/*"))]);
            n.start(io);
            let what = format!("run {ty} with the scope downstream/m/*, {name} on in.key");
            l.add(&what, &error_of(n.as_mut(), io, "in.key", v));
        }
    }
    for (ty, field) in [
        ("load_value", "key"),
        ("list_children", "path"),
        ("load_history", "key"),
        ("get_node", "key"),
    ] {
        let scope = format!("{field}_scope");
        let port = format!("in.{field}");
        let mut n = made(
            ty,
            &[(field, s("downstream/m/p0")), ("auto_run", false.into())],
        );
        n.start(io);
        let what = format!("run {ty} without a scope, a key on {port}");
        l.add(
            &what,
            &error_of(n.as_mut(), io, &port, s("downstream/m/p1")),
        );
        let mut n = made(
            ty,
            &[(&scope, s("downstream/m/*")), ("auto_run", false.into())],
        );
        n.start(io);
        let what = format!("run {ty} with the scope downstream/m/*, a key outside on {port}");
        l.add(
            &what,
            &error_of(n.as_mut(), io, &port, s("downstream/x/p0")),
        );
    }
    // `load_history`: a query field from a port that is no good, when the read is asked for
    for (field, v) in [
        ("time_range", s("soon")),
        ("window", s("5x")),
        ("time_zone", s("Nowhere/City")),
    ] {
        let mut n = made(
            "load_history",
            &[("key", s("downstream/m/p0")), ("auto_run", false.into())],
        );
        n.start(io);
        let mut out = Out::default();
        let port = format!("in.{field}");
        n.input(&port, Msg::new(v, Quality::Good, 1), io, &mut out);
        let what = format!("run load_history, a bad {field} from its port, then trigger");
        l.add(&what, &error_of(n.as_mut(), io, "trigger", true.into()));
    }
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn every_refusal_says_what_it_said_as_a_string() {
    let mut l = Lines::default();
    node_configs(&mut l);
    command_configs(&mut l);
    reader_configs(&mut l);
    block_configs(&mut l);
    table_configs(&mut l);
    scripts(&mut l);
    builds(&mut l);
    scopes(&mut l);
    definitions(&mut l);
    at_run_time(&mut l).await;
    if let Ok(path) = std::env::var("WYRM_FLOW_REFUSALS_OUT") {
        std::fs::write(&path, &l.0).unwrap();
    }
    let want = include_str!("refusal_texts.txt");
    for (i, (got, want)) in l.0.lines().zip(want.lines()).enumerate() {
        assert_eq!(got, want, "line {}", i + 1);
    }
    assert_eq!(
        l.0.lines().count(),
        want.lines().count(),
        "the number of lines"
    );
    assert_eq!(l.0, want);
}
