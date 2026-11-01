//! Logic blocks: small operators with a value per parameter (`docs/flow-blocks.md`).
//!
//! A block keeps the last value of each input. A parameter takes its value from the node's
//! config and, where the block has the port `in.<param>`, from the last sample on that port.
//! Variable inputs are named by the config list `inputs` (default `["0", "1"]`, ports
//! `in.0`, `in.1`, …). Any sample on an input calculates the block; an output is sent only when
//! its value or quality changed (events always). Only the variables (`number`, `string`,
//! `bool`) send at start: an operator waits for its first input, so a deploy or a restart
//! never fires a command by itself.
//!
//! Quality: the worst of the inputs that have a sample. Time: the latest of them.
//!
//! Numbers: an integer stays an integer while it fits (`add`, `subtract`, `multiply`, `abs`,
//! `round` to 0 places, `modulo`'s quotient); `divide` gives a float; a result that is not
//! finite is `null`. Text converts to a number when it parses, a bool to 1 or 0.

use crate::def::Map;
use crate::nodes::{names, Io, Msg, Node, Out, PortType, Ports};
use std::collections::BTreeMap;
use std::time::Duration;
use tracing::trace;
use wyrm_core::{Quality, Value};
use wyrm_link_sdk::now_us;

/// The block types of this module.
pub const TYPES: &[&str] = &[
    "number",
    "string",
    "bool",
    "add",
    "subtract",
    "multiply",
    "divide",
    "max",
    "min",
    "abs",
    "round",
    "modulo",
    "not",
    "if",
    "hub",
    "stopwatch",
    "trace",
    "concat",
    "length",
];

/// Variable inputs of one block at most.
pub const MAX_ITEMS: usize = 64;
/// The stopwatch's clock, and the shortest interval it counts.
const STOPWATCH_TICK: Duration = Duration::from_millis(50);
const MIN_INTERVAL_S: f64 = 0.05;

// ---------- values ----------

/// A number as the blocks use it: an integer while it fits, else a float.
#[derive(Debug, Clone, Copy, PartialEq)]
enum N {
    I(i64),
    F(f64),
}

impl N {
    fn f(self) -> f64 {
        match self {
            N::I(i) => i as f64,
            N::F(x) => x,
        }
    }

    fn value(self) -> Value {
        match self {
            N::I(i) => Value::Int(i),
            N::F(x) if x.is_finite() => Value::Float(x),
            N::F(_) => Value::Null,
        }
    }

    fn op(self, o: N, int: fn(i64, i64) -> Option<i64>, float: fn(f64, f64) -> f64) -> N {
        match (self, o) {
            (N::I(a), N::I(b)) => int(a, b).map_or(N::F(float(a as f64, b as f64)), N::I),
            _ => N::F(float(self.f(), o.f())),
        }
    }
}

/// A value as a number: numbers, bools (1/0) and text that parses.
fn num(v: &Value) -> Option<N> {
    match v {
        Value::Int(i) => Some(N::I(*i)),
        Value::UInt(u) => Some(i64::try_from(*u).map_or(N::F(*u as f64), N::I)),
        Value::Float(x) => Some(N::F(*x)),
        Value::Bool(b) => Some(N::I(i64::from(*b))),
        Value::Str(s) => {
            let s = s.trim();
            s.parse::<i64>()
                .map(N::I)
                .ok()
                .or_else(|| s.parse::<f64>().ok().map(N::F))
        }
        _ => None,
    }
}

/// A value as a bool: numbers other than 0; text `true`, or a number other than 0, or any
/// other text; `false`, empty text and `null` are false (`null` gives `fallback`); a list or
/// a map is true.
fn truth(v: &Value, fallback: bool) -> bool {
    match v {
        Value::Bool(b) => *b,
        Value::Null => fallback,
        Value::Str(s) => {
            let s = s.trim().to_ascii_lowercase();
            match s.as_str() {
                "true" => true,
                "false" | "" => false,
                _ => num(&Value::Str(s)).is_none_or(|n| n.f() != 0.0),
            }
        }
        v => num(v).is_none_or(|n| n.f() != 0.0),
    }
}

/// A value as text, for `concat`: `null` is empty.
fn text(v: &Value) -> String {
    match v {
        Value::Null => String::new(),
        Value::Str(s) => s.clone(),
        Value::Bool(b) => b.to_string(),
        Value::Int(i) => i.to_string(),
        Value::UInt(u) => u.to_string(),
        Value::Float(x) => format!("{x:?}"),
        Value::Bytes(b) => b.iter().map(|x| format!("{x:02x}")).collect(),
        Value::Array(a) => format!("[{}]", a.iter().map(text).collect::<Vec<_>>().join(", ")),
        Value::Map(m) => format!(
            "{{{}}}",
            m.iter()
                .map(|(k, v)| format!("{k}: {}", text(v)))
                .collect::<Vec<_>>()
                .join(", ")
        ),
    }
}

/// Equal as `if`'s `=` compares: the same value, or the same number.
fn same(a: &Value, b: &Value) -> bool {
    a == b || matches!((num(a), num(b)), (Some(x), Some(y)) if x.f() == y.f())
}

// ---------- the block types ----------

#[derive(Debug, Clone, Copy, PartialEq)]
enum Kind {
    Number,
    Text,
    Bool,
    Add,
    Subtract,
    Multiply,
    Divide,
    Max,
    Min,
    Abs,
    Round,
    Modulo,
    Not,
    If,
    Hub,
    Stopwatch,
    Trace,
    Concat,
    Length,
}

/// One parameter: its name, its default, and whether it has the port `in.<name>`.
struct Param {
    name: &'static str,
    default: Value,
    port: bool,
}

const fn param(name: &'static str, default: Value, port: bool) -> Param {
    Param {
        name,
        default,
        port,
    }
}

struct Shape {
    /// The fixed input ports, before the parameter ports.
    inputs: &'static [&'static str],
    params: Vec<Param>,
    /// Variable inputs `in.<name>`.
    items: bool,
    outputs: &'static [(&'static str, PortType)],
}

fn kind(ty: &str) -> Option<Kind> {
    Some(match ty {
        "number" => Kind::Number,
        "string" => Kind::Text,
        "bool" => Kind::Bool,
        "add" => Kind::Add,
        "subtract" => Kind::Subtract,
        "multiply" => Kind::Multiply,
        "divide" => Kind::Divide,
        "max" => Kind::Max,
        "min" => Kind::Min,
        "abs" => Kind::Abs,
        "round" => Kind::Round,
        "modulo" => Kind::Modulo,
        "not" => Kind::Not,
        "if" => Kind::If,
        "hub" => Kind::Hub,
        "stopwatch" => Kind::Stopwatch,
        "trace" => Kind::Trace,
        "concat" => Kind::Concat,
        "length" => Kind::Length,
        _ => return None,
    })
}

fn shape(k: Kind) -> Shape {
    use PortType::*;
    let s = |v: &str| Value::Str(v.to_owned());
    let var = |default: Value, t: PortType| -> (Vec<Param>, PortType) {
        (vec![param("value", default, false)], t)
    };
    match k {
        Kind::Number | Kind::Text | Kind::Bool => {
            let (params, t) = match k {
                Kind::Number => var(Value::Int(0), Number),
                Kind::Bool => var(Value::Bool(false), Bool),
                _ => var(s(""), Any),
            };
            Shape {
                inputs: &["in"],
                params,
                items: false,
                outputs: match t {
                    Number => &[("out", Number)],
                    Bool => &[("out", Bool)],
                    _ => &[("out", Any)],
                },
            }
        }
        Kind::Add | Kind::Subtract | Kind::Multiply | Kind::Divide | Kind::Max | Kind::Min => {
            Shape {
                inputs: &[],
                params: vec![],
                items: true,
                outputs: &[("out", Number)],
            }
        }
        Kind::Abs => Shape {
            inputs: &["in"],
            params: vec![],
            items: false,
            outputs: &[("out", Number)],
        },
        Kind::Round => Shape {
            inputs: &["in"],
            params: vec![param("precision", Value::Int(0), true)],
            items: false,
            outputs: &[("out", Number)],
        },
        Kind::Modulo => Shape {
            inputs: &["in"],
            params: vec![param("modulo", Value::Null, true)],
            items: false,
            outputs: &[("quotient", Number), ("remainder", Number)],
        },
        Kind::Not => Shape {
            inputs: &["in"],
            params: vec![],
            items: false,
            outputs: &[("out", Bool)],
        },
        Kind::If => Shape {
            inputs: &[],
            params: vec![
                param("op", s("="), false),
                param("then", Value::Bool(true), true),
                param("else", Value::Bool(false), true),
            ],
            items: true,
            outputs: &[("out", Any)],
        },
        Kind::Hub => Shape {
            inputs: &[],
            params: vec![param("ignore_null", Value::Bool(true), false)],
            items: true,
            outputs: &[("out", Any), ("index", Number), ("on_change", Map)],
        },
        Kind::Stopwatch => Shape {
            inputs: &["reset"],
            params: vec![
                param("enabled", Value::Bool(false), true),
                param("interval", Value::Float(0.5), true),
                param("step", Value::Int(1), true),
                param("modulo", Value::Int(0), true),
                param("loop", Value::Bool(true), true),
                param("reset_value", Value::Int(0), true),
            ],
            items: false,
            outputs: &[("out", Number), ("on_loop", Map)],
        },
        Kind::Trace => Shape {
            inputs: &[],
            params: vec![
                param("tracing", Value::Bool(true), false),
                param("msg", s("trace"), false),
            ],
            items: true,
            outputs: &[],
        },
        Kind::Concat => Shape {
            inputs: &[],
            params: vec![param("strict", Value::Bool(false), false)],
            items: true,
            outputs: &[("out", Any)],
        },
        Kind::Length => Shape {
            inputs: &["in"],
            params: vec![],
            items: false,
            outputs: &[("out", Number)],
        },
    }
}

/// The variable inputs of a block: `inputs` (default `0`, `1`), each `[A-Za-z0-9_]+`, at most
/// [`MAX_ITEMS`], none named like one of its parameters.
fn items(cfg: &Map, sh: &Shape) -> Result<Vec<String>, String> {
    let list = if cfg.contains_key("inputs") {
        names(cfg)?
    } else {
        vec!["0".into(), "1".into()]
    };
    if list.len() > MAX_ITEMS {
        return Err(format!("inputs: at most {MAX_ITEMS}"));
    }
    for (i, n) in list.iter().enumerate() {
        if list[..i].contains(n) {
            return Err(format!("inputs: {n} twice"));
        }
        if sh.params.iter().any(|p| p.name == n) {
            return Err(format!("inputs: {n} is the name of a parameter"));
        }
    }
    Ok(list)
}

/// Ports and config check of a block type; `None` for a type this module does not have.
pub fn ports(ty: &str, cfg: &Map) -> Option<Result<Ports, String>> {
    let k = kind(ty)?;
    Some(check(k, cfg))
}

fn check(k: Kind, cfg: &Map) -> Result<Ports, String> {
    let sh = shape(k);
    let known: Vec<&str> = sh
        .params
        .iter()
        .map(|p| p.name)
        .chain(sh.items.then_some("inputs"))
        .collect();
    if let Some(x) = cfg.keys().find(|x| !known.contains(&x.as_str())) {
        return Err(format!("{x}: unknown field"));
    }
    if k == Kind::If {
        let op = match cfg.get("op") {
            None => "=",
            Some(Value::Str(o)) => o.as_str(),
            Some(_) => return Err("op: expected a string".into()),
        };
        if !IF_OPS.contains(&op) {
            return Err(format!("op: one of {IF_OPS:?}"));
        }
    }
    let mut inputs: Vec<(String, PortType)> = sh
        .inputs
        .iter()
        .map(|n| ((*n).to_owned(), PortType::Any))
        .collect();
    inputs.extend(
        sh.params
            .iter()
            .filter(|p| p.port)
            .map(|p| (format!("in.{}", p.name), PortType::Any)),
    );
    if sh.items {
        inputs.extend(
            items(cfg, &sh)?
                .into_iter()
                .map(|n| (format!("in.{n}"), PortType::Any)),
        );
    }
    Ok(Ports {
        inputs,
        outputs: sh
            .outputs
            .iter()
            .map(|(n, t)| ((*n).to_owned(), *t))
            .collect(),
    })
}

const IF_OPS: &[&str] = &["=", "and", "or", ">", "<", ">=", "<="];

/// A block of `ty` from `cfg`; `None` for a type this module does not have.
pub fn build(ty: &str, flow: &str, id: &str, cfg: &Map) -> Option<Result<Box<dyn Node>, String>> {
    let k = kind(ty)?;
    Some(check(k, cfg).and_then(|_| {
        let sh = shape(k);
        let items = if sh.items {
            items(cfg, &sh)?
        } else {
            Vec::new()
        };
        let params = sh
            .params
            .iter()
            .map(|p| {
                (
                    p.name.to_owned(),
                    cfg.get(p.name)
                        .cloned()
                        .unwrap_or_else(|| p.default.clone()),
                )
            })
            .collect();
        Ok(Box::new(Block {
            kind: k,
            name: format!("{flow}/{id}"),
            param_ports: sh
                .params
                .iter()
                .filter(|p| p.port)
                .map(|p| p.name)
                .collect(),
            params,
            items,
            values: BTreeMap::new(),
            seen: BTreeMap::new(),
            sent: BTreeMap::new(),
            events: 0,
            count: None,
            elapsed_us: 0,
        }) as Box<dyn Node>)
    }))
}

struct Block {
    kind: Kind,
    /// `<flow>/<node>`, for `trace`.
    name: String,
    /// Each parameter's value: from the config, then from its port.
    params: BTreeMap<String, Value>,
    /// The parameters that have a port `in.<name>`.
    param_ports: Vec<&'static str>,
    /// The variable inputs' names, in order.
    items: Vec<String>,
    /// The last sample of each input port (without `in.`; `in` and `reset` as they are).
    values: BTreeMap<String, Value>,
    /// Quality and time of each input that has a sample.
    seen: BTreeMap<String, (Quality, u64)>,
    /// The last value and quality sent on each output.
    sent: BTreeMap<String, (Value, Quality)>,
    events: u64,
    /// The stopwatch's count; `None` until it was set.
    count: Option<N>,
    /// Time the stopwatch has run since its last step.
    elapsed_us: u64,
}

impl Block {
    fn param(&self, name: &str) -> &Value {
        self.params.get(name).unwrap_or(&Value::Null)
    }

    fn item_values(&self) -> Vec<Value> {
        self.items
            .iter()
            .map(|n| self.values.get(n).cloned().unwrap_or(Value::Null))
            .collect()
    }

    /// The last sample on `in`.
    fn in_value(&self) -> &Value {
        self.values.get("in").unwrap_or(&Value::Null)
    }

    fn quality(&self) -> (Quality, u64) {
        let q = self
            .seen
            .values()
            .map(|(q, _)| *q)
            .max_by_key(|q| q.code())
            .unwrap_or(Quality::Good);
        let t = self
            .seen
            .values()
            .map(|(_, t)| *t)
            .max()
            .unwrap_or_else(now_us);
        (q, t)
    }

    /// Send `v` on `port` when it differs from what was sent there last.
    fn send(&mut self, port: &str, v: Value, q: Quality, t: u64, out: &mut Out) {
        let next = (v, q);
        if self.sent.get(port) == Some(&next) {
            return;
        }
        out.emit(port, Msg::new(next.0.clone(), next.1, t));
        self.sent.insert(port.to_owned(), next);
    }

    /// An event on `port`: always sent.
    fn fire(&mut self, port: &str, t: u64, out: &mut Out) {
        self.events += 1;
        let v = Value::Map(BTreeMap::from([
            ("event".to_owned(), Value::Str(port.to_owned())),
            ("id".to_owned(), Value::UInt(self.events)),
        ]));
        out.emit(port, Msg::new(v, Quality::Good, t));
    }

    fn calculate(&mut self, changed: &str, out: &mut Out) {
        let (q, t) = self.quality();
        let nums = || -> Vec<N> { self.item_values().iter().filter_map(num).collect() };
        match self.kind {
            Kind::Number | Kind::Text | Kind::Bool => {
                let v = self.var_value(self.values.get("in").unwrap_or(self.param("value")));
                self.send("out", v, q, t, out);
            }
            Kind::Add => {
                let v = nums()
                    .into_iter()
                    .fold(N::I(0), |a, b| a.op(b, i64::checked_add, |x, y| x + y));
                self.send("out", v.value(), q, t, out);
            }
            Kind::Subtract | Kind::Multiply | Kind::Divide => {
                let xs = nums();
                let v = xs.split_first().map(|(first, rest)| {
                    rest.iter().fold(*first, |a, b| match self.kind {
                        Kind::Subtract => a.op(*b, i64::checked_sub, |x, y| x - y),
                        Kind::Multiply => a.op(*b, i64::checked_mul, |x, y| x * y),
                        _ => N::F(a.f() / b.f()),
                    })
                });
                // one input alone divides nothing: still a float, as every quotient
                let v = match (self.kind, v) {
                    (Kind::Divide, Some(n)) => N::F(n.f()).value(),
                    (_, v) => v.map_or(Value::Null, N::value),
                };
                self.send("out", v, q, t, out);
            }
            Kind::Max | Kind::Min => {
                let max = self.kind == Kind::Max;
                let v = nums().into_iter().reduce(|a, b| {
                    let better = if max { b.f() > a.f() } else { b.f() < a.f() };
                    if better {
                        b
                    } else {
                        a
                    }
                });
                self.send("out", v.map_or(Value::Null, N::value), q, t, out);
            }
            Kind::Abs => {
                let v = num(self.in_value()).map(|n| match n {
                    N::I(i) => i.checked_abs().map_or(N::F((i as f64).abs()), N::I),
                    N::F(x) => N::F(x.abs()),
                });
                self.send("out", v.map_or(Value::Null, N::value), q, t, out);
            }
            Kind::Round => {
                let places =
                    num(self.param("precision")).map_or(0, |n| n.f().clamp(0.0, 20.0) as i32);
                let v = num(self.in_value()).map(|n| {
                    if places == 0 {
                        let r = n.f().round();
                        if r.abs() < 9.0e15 {
                            N::I(r as i64)
                        } else {
                            N::F(r)
                        }
                    } else {
                        let f = 10f64.powi(places);
                        N::F((n.f() * f).round() / f)
                    }
                });
                self.send("out", v.map_or(Value::Null, N::value), q, t, out);
            }
            Kind::Modulo => {
                let (quot, rem) = match (num(self.in_value()), num(self.param("modulo"))) {
                    (Some(_), Some(m)) if m.f() == 0.0 => (Value::Null, Value::Null),
                    (Some(N::I(a)), Some(N::I(b))) => (
                        a.checked_div(b).map_or(Value::Null, Value::Int),
                        a.checked_rem_euclid(b).map_or(Value::Null, Value::Int),
                    ),
                    (Some(a), Some(b)) => {
                        let qf = (a.f() / b.f()).trunc();
                        let quot = if qf.abs() < 9.0e15 {
                            Value::Int(qf as i64)
                        } else {
                            N::F(qf).value()
                        };
                        (quot, N::F(a.f().rem_euclid(b.f())).value())
                    }
                    _ => (Value::Null, Value::Null),
                };
                self.send("quotient", quot, q, t, out);
                self.send("remainder", rem, q, t, out);
            }
            Kind::Not => {
                let v = !truth(self.in_value(), false);
                self.send("out", Value::Bool(v), q, t, out);
            }
            Kind::If => {
                let vs = self.item_values();
                let op = match self.param("op") {
                    Value::Str(o) => o.clone(),
                    _ => "=".into(),
                };
                let yes = match op.as_str() {
                    "and" => vs.iter().all(|v| truth(v, false)),
                    "or" => vs.iter().any(|v| truth(v, false)),
                    ">" | "<" | ">=" | "<=" => {
                        vs.len() > 1
                            && vs.windows(2).all(|w| match (num(&w[0]), num(&w[1])) {
                                (Some(a), Some(b)) => {
                                    let (a, b) = (a.f(), b.f());
                                    match op.as_str() {
                                        ">" => a > b,
                                        "<" => a < b,
                                        ">=" => a >= b,
                                        _ => a <= b,
                                    }
                                }
                                _ => false,
                            })
                    }
                    _ => vs
                        .first()
                        .is_none_or(|first| vs.iter().all(|v| same(v, first))),
                };
                let v = self.param(if yes { "then" } else { "else" }).clone();
                self.send("out", v, q, t, out);
            }
            Kind::Hub => {
                let Some(index) = self.items.iter().position(|n| n == changed) else {
                    return;
                };
                let v = self.values.get(changed).cloned().unwrap_or(Value::Null);
                if v == Value::Null && truth(self.param("ignore_null"), true) {
                    return;
                }
                self.send("index", Value::UInt(index as u64), q, t, out);
                // the input that changed last, even when it holds the same value as before
                out.emit("out", Msg::new(v.clone(), q, t));
                self.sent.insert("out".into(), (v, q));
                self.fire("on_change", t, out);
            }
            Kind::Stopwatch => {
                if changed == "reset" || self.count.is_none() {
                    self.count = Some(num(self.param("reset_value")).unwrap_or(N::I(0)));
                    self.elapsed_us = 0;
                    if changed == "reset" {
                        let v = self.count.map_or(Value::Null, N::value);
                        self.send("out", v, q, t, out);
                    }
                }
            }
            Kind::Trace => {
                if truth(self.param("tracing"), true) {
                    // values: `trace` only, as every log line that holds them
                    trace!(
                        block = %self.name,
                        msg = %text(self.param("msg")),
                        values = ?self.item_values(),
                        "trace"
                    );
                }
            }
            Kind::Concat => {
                let vs = self.item_values();
                let v = if truth(self.param("strict"), false) && vs.contains(&Value::Null) {
                    Value::Null
                } else {
                    Value::Str(vs.iter().map(text).collect())
                };
                self.send("out", v, q, t, out);
            }
            Kind::Length => {
                let v = match self.in_value() {
                    Value::Str(s) => Value::UInt(s.chars().count() as u64),
                    Value::Array(a) => Value::UInt(a.len() as u64),
                    Value::Map(m) => Value::UInt(m.len() as u64),
                    Value::Bytes(b) => Value::UInt(b.len() as u64),
                    _ => Value::Null,
                };
                self.send("out", v, q, t, out);
            }
        }
    }

    /// A variable's value in its type.
    fn var_value(&self, v: &Value) -> Value {
        match self.kind {
            Kind::Number => num(v).map_or(Value::Null, N::value),
            Kind::Bool => Value::Bool(truth(v, false)),
            _ => match v {
                Value::Str(_) | Value::Null => v.clone(),
                v => Value::Str(text(v)),
            },
        }
    }

    /// One step of the stopwatch.
    fn step(&mut self, now: u64, out: &mut Out) {
        let step = num(self.param("step")).unwrap_or(N::I(0));
        let modulo = num(self.param("modulo")).map_or(0.0, N::f);
        let mut v = self
            .count
            .unwrap_or(N::I(0))
            .op(step, i64::checked_add, |x, y| x + y);
        let mut looped = false;
        if modulo > 0.0 && v.f() >= modulo {
            looped = true;
            if truth(self.param("loop"), true) {
                v = match (v, num(self.param("modulo"))) {
                    (N::I(a), Some(N::I(m))) => N::I(a.rem_euclid(m)),
                    (a, _) => N::F(a.f().rem_euclid(modulo)),
                };
            } else {
                v = num(self.param("modulo")).unwrap_or(N::F(modulo));
                // it stops at the end: switched off until `enabled` comes again
                self.params.insert("enabled".into(), Value::Bool(false));
            }
        }
        self.count = Some(v);
        let (q, _) = self.quality();
        self.send("out", v.value(), q, now, out);
        if looped {
            self.fire("on_loop", now, out);
        }
    }
}

impl Node for Block {
    fn start(&mut self, io: &Io) {
        // only a variable sends at start
        if matches!(self.kind, Kind::Number | Kind::Text | Kind::Bool) {
            (io.inject)("__start", Msg::new(Value::Null, Quality::Good, now_us()));
        }
    }

    fn input(&mut self, port: &str, m: Msg, _io: &Io, out: &mut Out) {
        let name = match port {
            "__start" => {
                self.calculate("", out);
                return;
            }
            "in" | "reset" => port,
            p => match p.strip_prefix("in.") {
                Some(n) => n,
                None => return,
            },
        };
        let name = name.to_owned();
        self.seen.insert(name.clone(), (m.q, m.t));
        if port.starts_with("in.") && self.param_ports.contains(&name.as_str()) {
            self.params.insert(name.clone(), m.v);
        } else {
            self.values.insert(name.clone(), m.v);
        }
        self.calculate(&name, out);
    }

    fn tick_every(&self) -> Option<Duration> {
        (self.kind == Kind::Stopwatch).then_some(STOPWATCH_TICK)
    }

    fn tick(&mut self, now: u64, out: &mut Out) {
        let interval = num(self.param("interval")).map_or(0.0, N::f);
        if !truth(self.param("enabled"), false) || interval <= 0.0 {
            self.elapsed_us = 0;
            return;
        }
        if self.count.is_none() {
            self.count = Some(num(self.param("reset_value")).unwrap_or(N::I(0)));
        }
        let interval_us = (interval.max(MIN_INTERVAL_S) * 1e6) as u64;
        self.elapsed_us += STOPWATCH_TICK.as_micros() as u64;
        while self.elapsed_us >= interval_us && truth(self.param("enabled"), false) {
            self.elapsed_us -= interval_us;
            self.step(now, out);
        }
    }

    fn state(&self) -> Option<Value> {
        (self.kind == Kind::Stopwatch)
            .then(|| self.count.map(N::value))
            .flatten()
    }

    fn restore(&mut self, st: &Value) {
        if self.kind == Kind::Stopwatch {
            self.count = num(st);
        }
    }
}
