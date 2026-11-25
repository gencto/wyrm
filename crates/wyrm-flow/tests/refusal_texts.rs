//! Audit T7 (docs/rust-rules.md §8): every refusal of a node's config, of a script, of a
//! scope and of a key from a port, as the text an operator reads. The texts are in
//! `refusal_texts.txt`, written by this test while these errors were a `String`
//! (`WYRM_FLOW_REFUSALS_OUT=<file>` writes what the code says now, to compare two builds
//! byte by byte). The typed errors say the same. The compiler's own refusals (`def::DefError`,
//! [`whole_definitions`]) were added to the file while that error was a newtype over a
//! `String`.
//!
//! To compare two commits in one `target`, touch the sources before each build
//! (`touch crates/wyrm-flow/src/*.rs`): after a checkout that only moves the files back to
//! older times, cargo may reuse the test binary of the other commit and both files are then
//! one build's.

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

fn edge(a: &str, b: &str) -> Value {
    arr(&[s(a), s(b)])
}

fn edges(e: &[(&str, &str)]) -> Value {
    arr(&e.iter().map(|(a, b)| edge(a, b)).collect::<Vec<_>>())
}

/// `n` nodes of one type, named `n0`, `n1`, …
fn many(n: usize, ty: &str) -> Value {
    Value::Map((0..n).map(|i| (format!("n{i}"), node(ty, &[]))).collect())
}

/// A definition whose custom blocks are `blocks`.
fn using(nodes: &[(&str, Value)], e: &[(&str, &str)], blocks: &[(&str, Value)]) -> Value {
    flow(nodes, &[("edges", edges(e)), ("blocks", map(blocks))])
}

/// The custom block `b` (`b_def`) alone in a definition, with one instance `u`.
fn block_alone(b_def: Value) -> Value {
    using(&[("u", node("block:b", &[]))], &[], &[("b", b_def)])
}

/// A block of one `not` node `n` and the extra keys `more`.
fn block_of_n(more: &[(&str, Value)]) -> Value {
    let mut kv = vec![("nodes", map(&[("n", node("not", &[]))]))];
    kv.extend(more.iter().cloned());
    map(&kv)
}

/// Every refusal of the compiler itself (`def::parse`, `def::check`, `def::parse_block`), at
/// every place it makes one: the schema of `~def`, of `policy`, `permissions`, `layout`, of a
/// custom block and its instances, the expansion's limits, edges, ports, types, cycles,
/// rights and memory.
fn whole_definitions(l: &mut Lines) {
    // ----- the schema of ~def -----
    l.compile("an unknown field", &flow(&[], &[("colour", u(1))]));
    l.compile("no id", &map(&[("nodes", map(&[]))]));
    l.compile("an id that is no text", &flow(&[], &[("id", u(1))]));
    l.compile("an empty id", &flow(&[], &[("id", s(""))]));
    l.compile("an id with a slash", &flow(&[], &[("id", s("a/b"))]));
    l.compile("a version that is text", &flow(&[], &[("version", s("x"))]));
    l.compile(
        "a negative version",
        &flow(&[], &[("version", Value::Int(-1))]),
    );
    l.compile("enabled that is no bool", &flow(&[], &[("enabled", u(1))]));
    l.compile(
        "a description that is no text",
        &flow(&[], &[("description", u(1))]),
    );
    // layout
    l.compile("a layout that is no map", &flow(&[], &[("layout", u(1))]));
    let xy = || arr(&[u(0), u(0)]);
    let wide: BTreeMap<String, Value> = (0..16_385).map(|i| (format!("k{i}"), xy())).collect();
    l.compile(
        "a layout too large",
        &flow(&[], &[("layout", Value::Map(wide))]),
    );
    let long = BTreeMap::from([("k".repeat(257), xy())]);
    l.compile(
        "a layout key too long",
        &flow(&[], &[("layout", Value::Map(long))]),
    );
    l.compile(
        "a layout point that is text",
        &flow(&[], &[("layout", map(&[("a", s("left"))]))]),
    );
    l.compile(
        "a layout point of one number",
        &flow(&[], &[("layout", map(&[("a", arr(&[u(1)]))]))]),
    );
    l.compile(
        "a layout point that is not finite",
        &flow(
            &[],
            &[(
                "layout",
                map(&[("a", arr(&[u(1), Value::Float(f64::NAN)]))]),
            )],
        ),
    );
    // nodes
    l.compile("nodes that are no map", &flow(&[], &[("nodes", u(1))]));
    l.compile("a node that is no map", &flow(&[("a", u(1))], &[]));
    l.compile(
        "a node id with a slash",
        &flow(&[("a/b", node("not", &[]))], &[]),
    );
    l.compile(
        "a node type that is no text",
        &flow(&[("a", map(&[("type", u(1))]))], &[]),
    );
    l.compile(
        "a placement that is not local",
        &flow(&[("a", node("not", &[("placement", s("remote"))]))], &[]),
    );
    l.compile(
        "a placement that is no text",
        &flow(&[("a", node("not", &[("placement", u(1))]))], &[]),
    );
    l.compile(
        "too many nodes",
        &flow(&[], &[("nodes", many(def::MAX_NODES + 1, "not"))]),
    );
    // edges
    l.compile("edges that are no array", &flow(&[], &[("edges", u(1))]));
    l.compile(
        "an edge that is no pair",
        &flow(&[], &[("edges", arr(&[u(1)]))]),
    );
    l.compile(
        "an edge of three",
        &flow(
            &[],
            &[("edges", arr(&[arr(&[s("a.out"), s("b.in"), s("c.in")])]))],
        ),
    );
    l.compile(
        "an edge of no strings",
        &flow(&[], &[("edges", arr(&[arr(&[u(1), u(2)])]))]),
    );
    l.compile(
        "an edge from no port",
        &flow(&[], &[("edges", edges(&[("a", "b.in")]))]),
    );
    l.compile(
        "an edge into an empty port",
        &flow(&[], &[("edges", edges(&[("a.out", "b.")]))]),
    );
    l.compile(
        "an edge from an empty node",
        &flow(&[], &[("edges", edges(&[(".out", "b.in")]))]),
    );
    let lots: Vec<(&str, &str)> = vec![("a.out", "b.in"); def::MAX_EDGES + 1];
    l.compile("too many edges", &flow(&[], &[("edges", edges(&lots))]));
    // policy
    l.compile("a policy that is no map", &flow(&[], &[("policy", u(1))]));
    for (k, v) in [
        ("overflow", s("drop_all")),
        ("overflow", u(1)),
        ("queue", u(0)),
        ("queue", u(65_537)),
        ("queue", s("x")),
        ("state_flush_s", Value::Float(1.5)),
        ("restart", u(1)),
        ("restart", map(&[("backoff_max_s", s("x"))])),
        ("colour", u(1)),
    ] {
        let what = format!("policy {k} {v:?}");
        l.compile(&what, &flow(&[], &[("policy", map(&[(k, v)]))]));
    }
    // permissions
    l.compile(
        "permissions that are no map",
        &flow(&[], &[("permissions", u(1))]),
    );
    for (k, v) in [
        ("maxperm", s("boss")),
        ("maxperm", u(9)),
        ("maxperm", u(300)),
        ("maxperm", Value::Int(-1)),
        ("maxperm", s("config")),
        ("maxperm", u(4)),
        ("colour", u(1)),
    ] {
        let what = format!("permissions {k} {v:?}");
        l.compile(&what, &flow(&[], &[("permissions", map(&[(k, v)]))]));
    }

    // ----- custom blocks: their own shape (`def::parse_block`) -----
    l.compile("blocks that are no map", &flow(&[], &[("blocks", u(1))]));
    let lots: BTreeMap<String, Value> = (0..=def::MAX_BLOCKS)
        .map(|i| (format!("b{i}"), map(&[])))
        .collect();
    l.compile(
        "too many blocks",
        &flow(&[], &[("blocks", Value::Map(lots))]),
    );
    l.compile("a block's name", &using(&[], &[], &[("a-b", map(&[]))]));
    let what = "parse_block, a block's name";
    l.add(what, &said(what, def::parse_block("a b", &map(&[]))));
    let what = "parse_block, no map";
    l.add(what, &said(what, def::parse_block("b", &u(1))));
    let bad_blocks: Vec<(&str, Value)> = vec![
        ("an unknown field", map(&[("colour", u(1))])),
        ("nodes that are no map", map(&[("nodes", u(1))])),
        (
            "an inner node id",
            map(&[("nodes", map(&[("x-y", node("not", &[]))]))]),
        ),
        (
            "an inner node id with a slash",
            map(&[("nodes", map(&[("x/y", node("not", &[]))]))]),
        ),
        (
            "an inner node that is no map",
            map(&[("nodes", map(&[("n", u(1))]))]),
        ),
        (
            "too many inner nodes",
            map(&[("nodes", many(def::MAX_NODES + 1, "not"))]),
        ),
        (
            "too many instances",
            map(&[("nodes", many(def::MAX_BLOCK_INSTANCES + 1, "block:c"))]),
        ),
        ("edges that are no array", block_of_n(&[("edges", u(1))])),
        (
            "too many edges",
            block_of_n(&[("edges", edges(&vec![("n.out", "n.in"); def::MAX_EDGES + 1]))]),
        ),
        (
            "a bad edge",
            block_of_n(&[("edges", edges(&[("n", "n.in")]))]),
        ),
        ("a layout that is no map", block_of_n(&[("layout", u(1))])),
        (
            "an edge from no inner node",
            block_of_n(&[("edges", edges(&[("m.out", "n.in")]))]),
        ),
        (
            "an edge into no inner node",
            block_of_n(&[("edges", edges(&[("n.out", "m.in")]))]),
        ),
        ("inputs that are no array", block_of_n(&[("inputs", u(1))])),
        (
            "too many inputs",
            block_of_n(&[("inputs", arr(&vec![map(&[]); def::MAX_BLOCK_PORTS + 1]))]),
        ),
        (
            "an input that is no map",
            block_of_n(&[("inputs", arr(&[u(1)]))]),
        ),
        (
            "an input without a name",
            block_of_n(&[("inputs", arr(&[map(&[])]))]),
        ),
        (
            "an input with a bad name",
            block_of_n(&[("inputs", arr(&[map(&[("name", s("a-b"))])]))]),
        ),
        (
            "an input twice",
            block_of_n(&[(
                "inputs",
                arr(&[
                    map(&[("name", s("x")), ("to", s("n.in"))]),
                    map(&[("name", s("x")), ("to", s("n.in"))]),
                ]),
            )]),
        ),
        (
            "an input's description that is no text",
            block_of_n(&[(
                "inputs",
                arr(&[map(&[("name", s("x")), ("description", u(1))])]),
            )]),
        ),
        (
            "an input's unknown field",
            block_of_n(&[("inputs", arr(&[map(&[("name", s("x")), ("colour", u(1))])]))]),
        ),
        (
            "an input without to",
            block_of_n(&[("inputs", arr(&[map(&[("name", s("x"))])]))]),
        ),
        (
            "an input to an empty list",
            block_of_n(&[("inputs", arr(&[map(&[("name", s("x")), ("to", arr(&[]))])]))]),
        ),
        (
            "an input to too many",
            block_of_n(&[(
                "inputs",
                arr(&[map(&[
                    ("name", s("x")),
                    ("to", arr(&vec![s("n.in"); def::MAX_BLOCK_FANOUT + 1])),
                ])]),
            )]),
        ),
        (
            "an input to a number",
            block_of_n(&[(
                "inputs",
                arr(&[map(&[("name", s("x")), ("to", arr(&[u(1)]))])]),
            )]),
        ),
        (
            "an input to no port",
            block_of_n(&[("inputs", arr(&[map(&[("name", s("x")), ("to", s("n"))])]))]),
        ),
        (
            "an input to a list with no port",
            block_of_n(&[(
                "inputs",
                arr(&[map(&[("name", s("x")), ("to", arr(&[s("n")]))])]),
            )]),
        ),
        (
            "an input to no inner node",
            block_of_n(&[(
                "inputs",
                arr(&[map(&[("name", s("x")), ("to", s("m.in"))])]),
            )]),
        ),
        (
            "outputs that are no array",
            block_of_n(&[("outputs", u(1))]),
        ),
        (
            "an output's unknown field",
            block_of_n(&[(
                "outputs",
                arr(&[map(&[
                    ("name", s("y")),
                    ("from", s("n.out")),
                    ("colour", u(1)),
                ])]),
            )]),
        ),
        (
            "an output that is an input",
            block_of_n(&[
                (
                    "inputs",
                    arr(&[map(&[("name", s("x")), ("to", s("n.in"))])]),
                ),
                (
                    "outputs",
                    arr(&[map(&[("name", s("x")), ("from", s("n.out"))])]),
                ),
            ]),
        ),
        (
            "an output without from",
            block_of_n(&[("outputs", arr(&[map(&[("name", s("y"))])]))]),
        ),
        (
            "an output from no port",
            block_of_n(&[(
                "outputs",
                arr(&[map(&[("name", s("y")), ("from", s("n"))])]),
            )]),
        ),
        (
            "an output from no inner node",
            block_of_n(&[(
                "outputs",
                arr(&[map(&[("name", s("y")), ("from", s("m.out"))])]),
            )]),
        ),
        (
            "an output twice",
            block_of_n(&[(
                "outputs",
                arr(&[
                    map(&[("name", s("y")), ("from", s("n.out"))]),
                    map(&[("name", s("y")), ("from", s("n.out"))]),
                ]),
            )]),
        ),
        (
            "a description that is no text",
            block_of_n(&[("description", u(1))]),
        ),
    ];
    for (what, b) in bad_blocks {
        l.compile(&format!("a block, {what}"), &block_alone(b.clone()));
        let what = format!("parse_block, {what}");
        l.add(&what, &said(&what, def::parse_block("b", &b)));
    }
    // a block that holds itself
    l.compile(
        "a block in itself",
        &using(
            &[],
            &[],
            &[("r", map(&[("nodes", map(&[("me", node("block:r", &[]))]))]))],
        ),
    );
    l.compile(
        "a block in itself through another",
        &using(
            &[],
            &[],
            &[
                ("a", map(&[("nodes", map(&[("x", node("block:b", &[]))]))])),
                ("b", map(&[("nodes", map(&[("y", node("block:c", &[]))]))])),
                ("c", map(&[("nodes", map(&[("z", node("block:a", &[]))]))])),
            ],
        ),
    );

    // ----- the instances of custom blocks, while they are expanded -----
    l.compile(
        "an unknown custom block",
        &flow(&[("u", node("block:nope", &[]))], &[]),
    );
    let chain = |depth: usize| -> Vec<(String, Value)> {
        let mut blocks = vec![("b0".to_owned(), block_of_n(&[]))];
        for k in 1..=depth {
            blocks.push((
                format!("b{k}"),
                map(&[(
                    "nodes",
                    map(&[("i", node(&format!("block:b{}", k - 1), &[]))]),
                )]),
            ));
        }
        blocks
    };
    let deep = chain(def::MAX_BLOCK_DEPTH + 1);
    let deep: Vec<(&str, Value)> = deep.iter().map(|(n, v)| (n.as_str(), v.clone())).collect();
    l.compile(
        "custom blocks too deep",
        &using(&[("u", node("block:b5", &[]))], &[], &deep),
    );
    let b = || {
        block_of_n(&[(
            "inputs",
            arr(&[map(&[("name", s("x")), ("to", s("n.in"))])]),
        )])
    };
    l.compile(
        "an instance's unknown field",
        &using(
            &[("u", node("block:b", &[("colour", u(1))]))],
            &[],
            &[("b", b())],
        ),
    );
    l.compile(
        "an instance's values that are no map",
        &using(
            &[("u", node("block:b", &[("values", u(1))]))],
            &[],
            &[("b", b())],
        ),
    );
    l.compile(
        "an instance's value for no input",
        &using(
            &[("u", node("block:b", &[("values", map(&[("z", u(1))]))]))],
            &[],
            &[("b", b())],
        ),
    );
    l.compile(
        "a constant into a block instance's values that are no map",
        &using(
            &[("u", node("block:c", &[]))],
            &[],
            &[
                ("b", b()),
                (
                    "c",
                    map(&[
                        ("nodes", map(&[("i", node("block:b", &[("values", u(1))]))])),
                        (
                            "inputs",
                            arr(&[map(&[
                                ("name", s("x")),
                                ("to", s("i.x")),
                                ("default", u(1)),
                            ])]),
                        ),
                    ]),
                ),
            ],
        ),
    );
    let half = map(&[("nodes", many(def::MAX_NODES / 2 + 1, "not"))]);
    l.compile(
        "too many nodes expanded",
        &using(
            &[("u1", node("block:h", &[])), ("u2", node("block:h", &[]))],
            &[],
            &[("h", half)],
        ),
    );
    let all = block_of_n(&[("edges", edges(&vec![("n.out", "n.in"); def::MAX_EDGES]))]);
    l.compile(
        "too many edges expanded",
        &using(
            &[("u1", node("block:e", &[])), ("u2", node("block:e", &[]))],
            &[],
            &[("e", all)],
        ),
    );
    // one input that feeds 16 inner inputs at each of four levels: 16⁴ edges of one wire
    let mut fan = vec![(
        "f0".to_owned(),
        block_of_n(&[(
            "inputs",
            arr(&[map(&[
                ("name", s("x")),
                ("to", arr(&vec![s("n.in"); def::MAX_BLOCK_FANOUT])),
            ])]),
        )]),
    )];
    for k in 1..4 {
        fan.push((
            format!("f{k}"),
            map(&[
                (
                    "nodes",
                    map(&[("i", node(&format!("block:f{}", k - 1), &[]))]),
                ),
                (
                    "inputs",
                    arr(&[map(&[
                        ("name", s("x")),
                        ("to", arr(&vec![s("i.x"); def::MAX_BLOCK_FANOUT])),
                    ])]),
                ),
            ]),
        ));
    }
    let fan: Vec<(&str, Value)> = fan.iter().map(|(n, v)| (n.as_str(), v.clone())).collect();
    l.compile(
        "an input that fans out past the edges",
        &using(
            &[("v", node("bool", &[])), ("u", node("block:f3", &[]))],
            &[("v.out", "u.x")],
            &fan,
        ),
    );
    let with_out = || {
        block_of_n(&[
            (
                "inputs",
                arr(&[map(&[("name", s("x")), ("to", s("n.in"))])]),
            ),
            (
                "outputs",
                arr(&[map(&[("name", s("y")), ("from", s("n.out"))])]),
            ),
        ])
    };
    l.compile(
        "an edge from an instance's unknown output",
        &using(
            &[("u", node("block:b", &[])), ("o", node("not", &[]))],
            &[("u.nope", "o.in")],
            &[("b", with_out())],
        ),
    );
    l.compile(
        "an edge into an instance's unknown input",
        &using(
            &[("v", node("bool", &[])), ("u", node("block:b", &[]))],
            &[("v.out", "u.nope")],
            &[("b", with_out())],
        ),
    );
    l.compile(
        "an edge inside a block from an instance's unknown output",
        &using(
            &[("u", node("block:c", &[]))],
            &[],
            &[
                ("b", with_out()),
                (
                    "c",
                    map(&[
                        (
                            "nodes",
                            map(&[("i", node("block:b", &[])), ("o", node("not", &[]))]),
                        ),
                        ("edges", edges(&[("i.nope", "o.in")])),
                    ]),
                ),
            ],
        ),
    );
    l.compile(
        "an edge inside a block into a plain node's unknown input",
        &using(
            &[("u", node("block:c", &[]))],
            &[],
            &[(
                "c",
                map(&[
                    (
                        "nodes",
                        map(&[("i", node("not", &[])), ("o", node("not", &[]))]),
                    ),
                    ("edges", edges(&[("i.out", "o.nope")])),
                ]),
            )],
        ),
    );

    // ----- the checks of the expanded definition (`def::check`) -----
    l.compile(
        "a node id that is not a name",
        &flow(&[("a-b", node("not", &[]))], &[]),
    );
    let two = |e: &[(&str, &str)]| {
        flow(
            &[
                ("a", node("not", &[])),
                ("b", node("window", &[("size_s", u(1))])),
            ],
            &[("edges", edges(e))],
        )
    };
    l.compile("an edge from an unknown node", &two(&[("z.out", "a.in")]));
    l.compile("an edge into an unknown node", &two(&[("a.out", "z.in")]));
    l.compile(
        "an edge from an unknown output",
        &two(&[("a.nope", "b.in")]),
    );
    l.compile(
        "an edge into an unknown input",
        &two(&[("a.out", "b.nope")]),
    );
    l.compile("an edge whose types do not fit", &two(&[("a.out", "b.in")]));
    l.compile(
        "a wired read field without its scope",
        &flow(
            &[
                ("k", node("string", &[])),
                (
                    "l",
                    node("list_children", &[("path", s("downstream/mock"))]),
                ),
            ],
            &[("edges", edges(&[("k.out", "l.in.path")]))],
        ),
    );
    l.compile(
        "a cycle",
        &flow(
            &[("x", node("not", &[])), ("y", node("not", &[]))],
            &[("edges", edges(&[("x.out", "y.in"), ("y.out", "x.in")]))],
        ),
    );
    l.compile(
        "a cycle of one",
        &flow(
            &[("x", node("not", &[]))],
            &[("edges", edges(&[("x.out", "x.in")]))],
        ),
    );
    let invoke = || {
        node(
            "invoke",
            &[("path", s("downstream/m/a")), ("action", s("go"))],
        )
    };
    l.compile(
        "a command above maxperm",
        &flow(
            &[("i", invoke())],
            &[("permissions", map(&[("maxperm", s("read"))]))],
        ),
    );
    l.compile("a command with no maxperm", &flow(&[("i", invoke())], &[]));
    let publish = map(&[("nodes", map(&[("p", node("publish", &[("node", s("p"))]))]))]);
    l.compile(
        "a publish in a block used twice",
        &using(
            &[("u1", node("block:pb", &[])), ("u2", node("block:pb", &[]))],
            &[],
            &[("pb", publish)],
        ),
    );
    let window = || node("window", &[("size_s", u(1)), ("max_samples", u(60_000))]);
    l.compile(
        "windows past the samples",
        &flow(&[("w1", window()), ("w2", window())], &[]),
    );
    // a definition made by hand: what `parse` never hands `check`
    let parsed = |d: &Value| def::parse(d).unwrap();
    let mut d = parsed(&flow(&[("a", node("not", &[]))], &[]));
    d.instances.insert("a".into(), "b".into());
    let what = "check, a node and an instance share an id";
    l.add(what, &said(what, def::check(&d)));
    let mut d = parsed(&flow(&[("a", node("not", &[]))], &[]));
    d.instances.insert("a/b-c".into(), "b".into());
    let what = "check, an instance id that is not a name";
    l.add(what, &said(what, def::check(&d)));
    let mut d = parsed(&flow(&[("a", node("not", &[]))], &[]));
    let a = d.nodes["a"].clone();
    d.nodes.insert("a/".into(), a);
    let what = "check, an id with an empty part";
    l.add(what, &said(what, def::check(&d)));
    let mut d = parsed(&two(&[("z.out", "a.in")]));
    d.edge_at.clear();
    let what = "check, an edge without its place";
    l.add(what, &said(what, def::check(&d)));
    let mut d = parsed(&flow(&[], &[("nodes", many(def::MAX_NODES, "not"))]));
    let a = d.nodes["n0"].clone();
    d.nodes.insert("extra".into(), a);
    let what = "check, too many nodes";
    l.add(what, &said(what, def::check(&d)));
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
    whole_definitions(&mut l);
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
