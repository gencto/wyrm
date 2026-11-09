//! The node types an editor offers (`dataflows/~act/node_types`): for
//! each, its category, ports and parameters, as [`crate::nodes::ports`]
//! checks them. A test keeps the two in step.
//!
//! ADR 0038: every field is also an output. A parameter `p` has an echo output `p` (its
//! effective value), an input `x` that is not a parameter's port an echo output `x` (every
//! sample it gets). A declared output keeps its name; an input's echo comes before a
//! parameter's (`latch`: input `reset` and parameter `reset`), so that parameter has none.

use crate::nodes::{Echo, EchoOf, PortType, Ports};
use std::collections::BTreeMap;
use wyrm_core::Value;

/// A parameter's default, typed (ADR 0038 §2): a number stays a number.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Def {
    None,
    Int(i64),
    Float(f64),
    Bool(bool),
    Str(&'static str),
    /// A list of names (`inputs`, `outputs`).
    Names(&'static [&'static str]),
}

impl Def {
    pub fn value(self) -> Option<Value> {
        Some(match self {
            Def::None => return None,
            Def::Int(i) => u64::try_from(i).map_or(Value::Int(i), Value::UInt),
            Def::Float(x) => Value::Float(x),
            Def::Bool(b) => Value::Bool(b),
            Def::Str(s) => Value::from(s),
            Def::Names(n) => texts(n),
        })
    }
}

/// One parameter of a node type.
pub struct Param {
    pub name: &'static str,
    /// `number`, `string`, `bool`, `map`, `array` (of names) or `dynamic`.
    pub ty: &'static str,
    pub required: bool,
    pub choices: &'static [&'static str],
    pub default: Def,
    pub description: &'static str,
    /// UI hint (spec 02 `editor`): `textarea`, `duration`, …
    pub editor: Option<&'static str>,
}

/// Ports named by a parameter (`expression` inputs `in.<name>`, `wasm`
/// ports): the parameter, the prefix of each port, the ports without it.
pub struct DynPorts {
    pub param: &'static str,
    pub prefix: &'static str,
    pub default: &'static [&'static str],
}

pub struct NodeType {
    pub ty: &'static str,
    pub category: &'static str,
    pub description: &'static str,
    pub inputs: &'static [&'static str],
    pub outputs: &'static [&'static str],
    pub dyn_inputs: Option<DynPorts>,
    pub dyn_outputs: Option<DynPorts>,
    pub params: &'static [Param],
}

const fn p(name: &'static str, ty: &'static str, description: &'static str) -> Param {
    Param {
        name,
        ty,
        required: false,
        choices: &[],
        default: Def::None,
        description,
        editor: None,
    }
}

const fn req(mut x: Param) -> Param {
    x.required = true;
    x
}

const fn pick(mut x: Param, choices: &'static [&'static str], default: &'static str) -> Param {
    x.choices = choices;
    x.default = Def::Str(default);
    x
}

const fn ed(mut x: Param, editor: &'static str) -> Param {
    x.editor = Some(editor);
    x
}

const fn di(mut x: Param, d: i64) -> Param {
    x.default = Def::Int(d);
    x
}

const fn df(mut x: Param, d: f64) -> Param {
    x.default = Def::Float(d);
    x
}

const fn db(mut x: Param, d: bool) -> Param {
    x.default = Def::Bool(d);
    x
}

const fn ds(mut x: Param, d: &'static str) -> Param {
    x.default = Def::Str(d);
    x
}

const fn dl(mut x: Param, d: &'static [&'static str]) -> Param {
    x.default = Def::Names(d);
    x
}

const KEY: Param = req(p(
    "key",
    "string",
    "A point of this site: downstream/<link>/…, storage/… or wy/<site>/…",
));

/// Every node type, in the palette's order.
pub const TYPES: &[NodeType] = &[
    NodeType {
        ty: "subscribe",
        category: "Sources",
        description: "Values of a point as they change.",
        inputs: &[],
        outputs: &["out"],
        dyn_inputs: None,
        dyn_outputs: None,
        params: &[KEY],
    },
    NodeType {
        ty: "timer",
        category: "Sources",
        description: "A count every period.",
        inputs: &["in.period_ms"],
        outputs: &["out"],
        dyn_inputs: None,
        dyn_outputs: None,
        params: &[req(p("period_ms", "number", "Milliseconds between two ticks (at least 10)."))],
    },
    NodeType {
        ty: "const",
        category: "Sources",
        description: "One value, once at start.",
        inputs: &[],
        outputs: &["out"],
        dyn_inputs: None,
        dyn_outputs: None,
        params: &[req(p("value", "dynamic", "The value."))],
    },
    NodeType {
        ty: "liveliness",
        category: "Sources",
        description: "Whether a node is alive (its liveliness token).",
        inputs: &[],
        outputs: &["out"],
        dyn_inputs: None,
        dyn_outputs: None,
        params: &[KEY],
    },
    NodeType {
        ty: "expression",
        category: "Logic",
        description: "A rhai expression over named inputs (in.<name>).",
        inputs: &[],
        outputs: &["out"],
        dyn_inputs: Some(DynPorts {
            param: "inputs",
            prefix: "in.",
            default: &[],
        }),
        dyn_outputs: None,
        params: &[
            req(p("inputs", "array", "Input names, [A-Za-z0-9_]+; each is a port in.<name> and a variable.")),
            ed(req(p("expr", "string", "rhai, over the input names: a + b * 2")), "textarea"),
            pick(p("trigger", "string", "Calculate on any input, or once all have a value."), &["any", "all"], "any"),
            pick(
                p("quality", "string", "Quality of the result: the worst input's, good, or set by the script."),
                &["worst", "ignore", "custom"],
                "worst",
            ),
        ],
    },
    NodeType {
        ty: "filter",
        category: "Logic",
        description: "Passes the samples a rhai condition over v, q, t accepts.",
        inputs: &["in"],
        outputs: &["out"],
        dyn_inputs: None,
        dyn_outputs: None,
        params: &[ed(req(p("expr", "string", "rhai over v (value), q (quality), t (time): v > 10")), "textarea")],
    },
    NodeType {
        ty: "latch",
        category: "Logic",
        description: "Holds true after in was true, until reset.",
        inputs: &["in", "reset"],
        outputs: &["out"],
        dyn_inputs: None,
        dyn_outputs: None,
        params: &[pick(p("reset", "string", "manual: only the reset input clears it; auto: also in going false."), &["manual", "auto"], "manual")],
    },
    NodeType {
        ty: "delay",
        category: "Logic",
        description: "Every sample, later (also breaks a cycle).",
        inputs: &["in", "in.ms"],
        outputs: &["out"],
        dyn_inputs: None,
        dyn_outputs: None,
        params: &[req(p("ms", "number", "Milliseconds."))],
    },
    NodeType {
        ty: "scale",
        category: "Math",
        description: "out = k × in + b; with a range, in is first mapped from input_min…input_max to output_min…output_max.",
        inputs: &["in", "in.k", "in.b", "in.input_min", "in.input_max", "in.output_min", "in.output_max"],
        outputs: &["out", "input_out_of_range"],
        dyn_inputs: None,
        dyn_outputs: None,
        params: &[
            di(p("k", "number", "Factor (default 1)."), 1),
            di(p("b", "number", "Offset (default 0)."), 0),
            di(p("input_min", "number", "Range from (default 0 once a range parameter is given)."), 0),
            di(p("input_max", "number", "Range to (default 1)."), 1),
            di(p("output_min", "number", "Mapped from (default 0)."), 0),
            di(p("output_max", "number", "Mapped to (default 100)."), 100),
        ],
    },
    NodeType {
        ty: "deadband",
        category: "Math",
        description: "Passes a value that moved by more than abs or pct.",
        inputs: &["in", "in.abs", "in.pct"],
        outputs: &["out"],
        dyn_inputs: None,
        dyn_outputs: None,
        params: &[
            p("abs", "number", "Absolute change (abs or pct required)."),
            p("pct", "number", "Change in percent of the last value passed."),
        ],
    },
    NodeType {
        ty: "window",
        category: "Math",
        description: "One value per window of time: avg, min, max, sum, count or rate.",
        inputs: &["in", "in.size_s"],
        outputs: &["out"],
        dyn_inputs: None,
        dyn_outputs: None,
        params: &[
            ed(req(p("size_s", "number", "Window length in seconds.")), "duration"),
            pick(p("kind", "string", "tumbling: back to back; sliding: the last size_s at each sample."), &["tumbling", "sliding"], "tumbling"),
            pick(p("fn", "string", "What the window gives."), &["avg", "min", "max", "sum", "count", "rate"], "avg"),
            di(p("max_samples", "number", "Most samples kept, 1..100 000 (default 10 000)."), 10_000),
        ],
    },
    NodeType {
        ty: "alarm",
        category: "Alarms",
        description: "true while in is above high or below low (with hysteresis and delays); an event on each change.",
        inputs: &["in", "in.high", "in.low", "in.hysteresis", "in.delay_s", "in.return_delay_s"],
        outputs: &["out", "event"],
        dyn_inputs: None,
        dyn_outputs: None,
        params: &[
            p("high", "number", "Raised above (high or low required)."),
            p("low", "number", "Raised below."),
            di(p("hysteresis", "number", "Back inside by this much before it clears."), 0),
            di(ed(p("delay_s", "number", "Seconds outside before it is raised."), "duration"), 0),
            di(ed(p("return_delay_s", "number", "Seconds inside before it clears."), "duration"), 0),
            pick(p("on_bad", "string", "What a bad sample does."), &["hold", "clear", "raise"], "hold"),
        ],
    },
    NodeType {
        ty: "publish",
        category: "Outputs",
        description: "Publishes in as a value of this flow: dataflows/<id>/nodes/<node>.",
        inputs: &["in"],
        outputs: &[],
        dyn_inputs: None,
        dyn_outputs: None,
        params: &[
            req(p("node", "string", "Name of the value under the flow's nodes.")),
            p("meta", "map", "Its ~meta fields (unit, …)."),
        ],
    },
    NodeType {
        ty: "set",
        category: "Outputs",
        description: "Writes in to a point (a command: the deployer proves the right, ADR 0008).",
        inputs: &["in"],
        outputs: &[],
        dyn_inputs: None,
        dyn_outputs: None,
        params: &[
            req(p("path", "string", "The point: downstream/<link>/… or storage/…")),
            pick(p("on", "string", "Every sample, or a changed value only."), &["change", "any"], "change"),
            di(p("deadband", "number", "With on change: a smaller change is not written."), 0),
            db(p("allow_bad", "bool", "Write values of bad quality too."), false),
        ],
    },
    NodeType {
        ty: "invoke",
        category: "Outputs",
        description: "Runs an action when in arrives (a command: the deployer proves the right, ADR 0008).",
        inputs: &["in"],
        outputs: &["out"],
        dyn_inputs: None,
        dyn_outputs: None,
        params: &[
            req(p("path", "string", "The node: downstream/<link>/… or storage/…")),
            req(p("action", "string", "The action's name.")),
            p("args", "map", "Its arguments."),
            pick(p("on", "string", "Every sample, a rising or falling bool, or a change."), &["any", "rising", "falling", "change"], "any"),
            db(p("allow_bad", "bool", "Run on samples of bad quality too."), false),
        ],
    },
    NodeType {
        ty: "wasm",
        category: "WASM",
        description: "A WebAssembly component (put_artifact) with named ports.",
        inputs: &[],
        outputs: &[],
        dyn_inputs: Some(DynPorts {
            param: "inputs",
            prefix: "",
            default: &["in"],
        }),
        dyn_outputs: Some(DynPorts {
            param: "outputs",
            prefix: "",
            default: &["out"],
        }),
        params: &[
            req(p("artifact", "string", "SHA-256 of the component (dataflows ▸ put_artifact).")),
            dl(p("inputs", "array", "Input port names (default in)."), &["in"]),
            dl(p("outputs", "array", "Output port names (default out)."), &["out"]),
            p("config", "dynamic", "Given to the component's init."),
            p("fuel", "number", "Instructions per call."),
            p("memory_mb", "number", "Memory limit."),
        ],
    },
    // ---------- logic blocks (crate::blocks, docs/flow-blocks.md) ----------
    NodeType {
        ty: "number",
        category: "Variables",
        description: "A number: sent at start, and again when in brings another.",
        inputs: &["in"],
        outputs: &["out"],
        dyn_inputs: None,
        dyn_outputs: None,
        params: &[di(p("value", "number", "The value at start (default 0)."), 0)],
    },
    NodeType {
        ty: "string",
        category: "Variables",
        description: "A text: sent at start, and again when in brings another.",
        inputs: &["in"],
        outputs: &["out"],
        dyn_inputs: None,
        dyn_outputs: None,
        params: &[ds(ed(p("value", "string", "The text at start (default empty)."), "textarea"), "")],
    },
    NodeType {
        ty: "bool",
        category: "Variables",
        description: "A bool: sent at start, and again when in brings another.",
        inputs: &["in"],
        outputs: &["out"],
        dyn_inputs: None,
        dyn_outputs: None,
        params: &[db(p("value", "bool", "The value at start (default false)."), false)],
    },
    reduce("add", "The sum of the inputs (none: 0)."),
    reduce("subtract", "The first input minus the others."),
    reduce("multiply", "The product of the inputs."),
    reduce("divide", "The first input divided by the others (a float; by 0: null)."),
    reduce("max", "The largest input."),
    reduce("min", "The smallest input."),
    NodeType {
        ty: "abs",
        category: "Math",
        description: "The absolute value of in.",
        inputs: &["in"],
        outputs: &["out"],
        dyn_inputs: None,
        dyn_outputs: None,
        params: &[],
    },
    NodeType {
        ty: "round",
        category: "Math",
        description: "in rounded to precision places (0: an integer); text: the same with at least min_precision places.",
        inputs: &["in", "in.precision", "in.min_precision"],
        outputs: &["out", "text"],
        dyn_inputs: None,
        dyn_outputs: None,
        params: &[
            di(p("precision", "number", "Places after the point, 0…20 (default 0)."), 0),
            p("min_precision", "number", "Fewest places in text: trailing zeros beyond go (default: precision)."),
        ],
    },
    NodeType {
        ty: "modulo",
        category: "Math",
        description: "in divided by modulo: the whole quotient and the remainder (never negative).",
        inputs: &["in", "in.modulo"],
        outputs: &["quotient", "remainder"],
        dyn_inputs: None,
        dyn_outputs: None,
        params: &[p("modulo", "number", "The divisor (0 or none: null).")],
    },
    NodeType {
        ty: "not",
        category: "Logic",
        description: "The opposite of in as a bool.",
        inputs: &["in"],
        outputs: &["out"],
        dyn_inputs: None,
        dyn_outputs: None,
        params: &[],
    },
    NodeType {
        ty: "if",
        category: "Logic",
        description: "then when the inputs pass op, else otherwise.",
        inputs: &["in.op", "in.then", "in.else"],
        outputs: &["out"],
        dyn_inputs: Some(ITEMS),
        dyn_outputs: None,
        params: &[
            pick(
                p("op", "string", "= all equal; != the first equals none of the others; and / or of the inputs; > < >= <= between each input and the next; contains / starts_with / ends_with: the first as text with any of the others."),
                crate::blocks::IF_OPS,
                "=",
            ),
            db(p("then", "dynamic", "Sent when it passes (default true)."), true),
            db(p("else", "dynamic", "Sent when it does not (default false)."), false),
            INPUTS,
        ],
    },
    NodeType {
        ty: "hub",
        category: "Logic",
        description: "The input that changed last: its value, its index and an event.",
        inputs: &["in.ignore_null"],
        outputs: &["out", "index", "on_change"],
        dyn_inputs: Some(ITEMS),
        dyn_outputs: None,
        params: &[db(p("ignore_null", "bool", "A null on an input is not passed (default true)."), true), INPUTS],
    },
    NodeType {
        ty: "stopwatch",
        category: "Logic",
        description: "Counts by step every interval while enabled; an event when it reaches modulo.",
        inputs: &["reset", "in.enabled", "in.interval", "in.step", "in.modulo", "in.loop", "in.reset_value"],
        outputs: &["out", "on_loop"],
        dyn_inputs: None,
        dyn_outputs: None,
        params: &[
            db(p("enabled", "bool", "Counting (default false)."), false),
            df(ed(p("interval", "number", "Seconds between two steps, at least 0.05 (default 0.5)."), "duration"), 0.5),
            di(p("step", "number", "Added each interval (default 1)."), 1),
            di(p("modulo", "number", "Above 0: the count wraps (or stops) there (default 0)."), 0),
            db(p("loop", "bool", "At modulo: start again from the remainder; false: stop there (default true)."), true),
            di(p("reset_value", "number", "The count at start and after reset (default 0)."), 0),
        ],
    },
    NodeType {
        ty: "trace",
        category: "Logic",
        description: "Writes msg and the inputs to the broker log at level trace.",
        inputs: &["in.tracing", "in.msg"],
        outputs: &[],
        dyn_inputs: Some(ITEMS),
        dyn_outputs: None,
        params: &[
            db(p("tracing", "bool", "Writing (default true)."), true),
            ds(p("msg", "string", "The line's text (default trace)."), "trace"),
            INPUTS,
        ],
    },
    NodeType {
        ty: "concat",
        category: "Text",
        description: "The inputs as one text.",
        inputs: &["in.strict"],
        outputs: &["out"],
        dyn_inputs: Some(ITEMS),
        dyn_outputs: None,
        params: &[db(p("strict", "bool", "A missing input gives null (default false: empty text)."), false), INPUTS],
    },
    NodeType {
        ty: "length",
        category: "Text",
        description: "The characters of a text, the items of a list or the entries of a map.",
        inputs: &["in"],
        outputs: &["out"],
        dyn_inputs: None,
        dyn_outputs: None,
        params: &[],
    },
    NodeType {
        ty: "case",
        category: "Logic",
        description: "The then of the first pair whose case in matches by op; else when none does.",
        inputs: &["in", "in.op", "in.else"],
        outputs: &["out"],
        dyn_inputs: Some(ITEMS),
        dyn_outputs: None,
        params: &[
            pick(
                p("op", "string", "How in is compared with each case: = != > < >= <= (as numbers), contains / starts_with / ends_with (as text; an empty case matches nothing)."),
                crate::blocks::CASE_OPS,
                "=",
            ),
            p("else", "dynamic", "Sent when no case matches (default null)."),
            dl(
                p(
                    "inputs",
                    "array",
                    "Names of the variable inputs, in pairs: a case, then what it gives (default 0, 1). Give each its constant in values.",
                ),
                &["0", "1"],
            ),
        ],
    },
];

/// Variable inputs `in.<name>` of a block (default `in.0`, `in.1`).
const ITEMS: DynPorts = DynPorts {
    param: "inputs",
    prefix: "in.",
    default: &["0", "1"],
};

const INPUTS: Param = dl(
    p(
        "inputs",
        "array",
        "Names of the variable inputs, [A-Za-z0-9_]+, at most 64 (default 0, 1): ports in.<name>.",
    ),
    &["0", "1"],
);

/// A block over its variable inputs with one number out.
const fn reduce(ty: &'static str, description: &'static str) -> NodeType {
    NodeType {
        ty,
        category: "Math",
        description,
        inputs: &[],
        outputs: &["out"],
        dyn_inputs: Some(ITEMS),
        dyn_outputs: None,
        params: &[INPUTS],
    }
}

fn texts(a: &[&str]) -> Value {
    Value::Array(a.iter().map(|s| Value::from(*s)).collect())
}

fn dyn_ports(d: &DynPorts) -> Value {
    Value::Map(BTreeMap::from([
        ("param".to_owned(), Value::from(d.param)),
        ("prefix".to_owned(), Value::from(d.prefix)),
        ("default".to_owned(), texts(d.default)),
    ]))
}

/// The catalog as the action answers it: one map per type.
pub fn value() -> Value {
    Value::Array(
        TYPES
            .iter()
            .map(|t| {
                let params = t
                    .params
                    .iter()
                    .map(|x| {
                        let mut m = BTreeMap::from([
                            ("name".to_owned(), Value::from(x.name)),
                            ("type".to_owned(), Value::from(x.ty)),
                            ("required".to_owned(), Value::Bool(x.required)),
                            ("description".to_owned(), Value::from(x.description)),
                        ]);
                        if !x.choices.is_empty() {
                            m.insert("choices".into(), texts(x.choices));
                        }
                        if let Some(d) = x.default.value() {
                            m.insert("default".into(), d);
                        }
                        if let Some(e) = x.editor {
                            m.insert("editor".into(), Value::from(e));
                        }
                        if let Some(port) = t
                            .inputs
                            .iter()
                            .find(|i| param_of_port(t, i).is_some_and(|p| p.name == x.name))
                        {
                            m.insert("port".into(), Value::from(*port));
                        }
                        m.insert("echo".into(), Value::Bool(param_echo(t, x)));
                        Value::Map(m)
                    })
                    .collect();
                let mut m = BTreeMap::from([
                    ("type".to_owned(), Value::from(t.ty)),
                    ("category".to_owned(), Value::from(t.category)),
                    ("description".to_owned(), Value::from(t.description)),
                    ("inputs".to_owned(), texts(t.inputs)),
                    ("outputs".to_owned(), texts(t.outputs)),
                    ("params".to_owned(), Value::Array(params)),
                    ("port_types".to_owned(), port_types(t)),
                ]);
                if let Some(d) = &t.dyn_inputs {
                    m.insert("dyn_inputs".into(), dyn_ports(d));
                }
                if let Some(d) = &t.dyn_outputs {
                    m.insert("dyn_outputs".into(), dyn_ports(d));
                }
                if t.dyn_inputs.is_some() || t.inputs.iter().any(|i| param_of_port(t, i).is_none())
                {
                    m.insert("echo_inputs".into(), Value::Bool(true));
                }
                // spec 06 0.2.19: the operand inputs take a constant in config `values`
                if crate::blocks::takes_values(t.ty) {
                    m.insert("values".into(), Value::Bool(true));
                }
                Value::Map(m)
            })
            .collect(),
    )
}

/// The catalog entry of `ty`.
pub fn find(ty: &str) -> Option<&'static NodeType> {
    TYPES.iter().find(|t| t.ty == ty)
}

/// The port type of a parameter's echo: `number`, `bool` and `map` as they are, any other
/// parameter type (`string`, `dynamic`, `array`) `any`.
pub fn port_type(param_ty: &str) -> PortType {
    match param_ty {
        "number" => PortType::Number,
        "bool" => PortType::Bool,
        "map" => PortType::Map,
        _ => PortType::Any,
    }
}

/// The parameter whose port `port` is (`in.<p>`, listed among the type's fixed inputs).
fn param_of_port<'a>(t: &'a NodeType, port: &str) -> Option<&'a Param> {
    let name = port.strip_prefix("in.")?;
    if !t.inputs.contains(&port) {
        return None;
    }
    t.params.iter().find(|x| x.name == name)
}

/// Whether parameter `x` of `t` has its echo output: not when a fixed output or an input's echo
/// has its name (ADR 0038 §1).
fn param_echo(t: &NodeType, x: &Param) -> bool {
    !(t.outputs.contains(&x.name)
        || t.inputs
            .iter()
            .any(|i| *i == x.name && param_of_port(t, i).is_none()))
}

/// The echo outputs of a node of type `ty` with these ports, in order: inputs, then
/// parameters. A declared output keeps its name; an input's echo comes before a parameter's.
pub(crate) fn echoes(ty: &str, ports: &Ports) -> Vec<Echo> {
    let Some(t) = find(ty) else {
        return Vec::new();
    };
    let mut out: Vec<Echo> = Vec::new();
    let taken = |n: &str, out: &[Echo]| {
        ports.outputs.iter().any(|(o, _)| o == n) || out.iter().any(|e| e.name == n)
    };
    for (name, ty) in &ports.inputs {
        if param_of_port(t, name).is_some() || taken(name, &out) {
            continue;
        }
        out.push(Echo {
            name: name.clone(),
            ty: *ty,
            of: EchoOf::Input,
        });
    }
    for x in t.params {
        if taken(x.name, &out) {
            continue;
        }
        out.push(Echo {
            name: x.name.to_owned(),
            ty: port_type(x.ty),
            of: EchoOf::Param,
        });
    }
    out
}

/// Each parameter's effective value from the config: given, else its default; a parameter with
/// neither is absent.
pub fn effective_params(ty: &str, cfg: &BTreeMap<String, Value>) -> BTreeMap<String, Value> {
    find(ty)
        .map(|t| {
            t.params
                .iter()
                .filter_map(|x| {
                    cfg.get(x.name)
                        .cloned()
                        .or_else(|| x.default.value())
                        .map(|v| (x.name.to_owned(), v))
                })
                .collect()
        })
        .unwrap_or_default()
}

/// A configuration of `t` that the compiler takes: each required parameter with a placeholder.
fn sample_cfg(t: &NodeType) -> BTreeMap<String, Value> {
    let mut cfg = BTreeMap::new();
    for x in t.params.iter().filter(|x| x.required) {
        let v = match (t.ty, x.name) {
            (_, "inputs") => texts(&["a"]),
            ("expression", "expr") => Value::from("a"),
            ("filter", "expr") => Value::from("v > 1"),
            ("publish", "node") => Value::from("x"),
            (_, "artifact") => Value::from("0".repeat(64)),
            _ => match x.ty {
                "number" => Value::UInt(100),
                "map" => Value::Map(BTreeMap::new()),
                _ => Value::from("downstream/x/y"),
            },
        };
        cfg.insert(x.name.to_owned(), v);
    }
    if t.ty == "deadband" {
        cfg.insert("abs".into(), Value::UInt(1));
    }
    if t.ty == "alarm" {
        cfg.insert("high".into(), Value::UInt(10));
    }
    cfg
}

/// `{<port>: <type>}` of the fixed ports, the default dynamic ports and every echo output of
/// them and of the parameters (ADR 0038 §2).
fn port_types(t: &NodeType) -> Value {
    let Ok(ports) = crate::nodes::ports(t.ty, &sample_cfg(t)) else {
        return Value::Map(BTreeMap::new());
    };
    let named = |fixed: &[&str], d: &Option<DynPorts>, n: &str| {
        fixed.contains(&n)
            || d.as_ref()
                .is_some_and(|d| d.default.iter().any(|x| format!("{}{x}", d.prefix) == n))
    };
    let mut m = BTreeMap::new();
    for (n, ty) in &ports.inputs {
        if named(t.inputs, &t.dyn_inputs, n) {
            m.insert(n.clone(), Value::from(ty.name()));
        }
    }
    for (n, ty) in &ports.outputs {
        if named(t.outputs, &t.dyn_outputs, n) {
            m.insert(n.clone(), Value::from(ty.name()));
        }
    }
    for e in &ports.echoes {
        if e.of == EchoOf::Param || named(t.inputs, &t.dyn_inputs, &e.name) {
            m.insert(e.name.clone(), Value::from(e.ty.name()));
        }
    }
    Value::Map(m)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::nodes::ports;

    /// A configuration of `ty` that sets its required params.
    fn sample(t: &NodeType) -> BTreeMap<String, Value> {
        let mut cfg = BTreeMap::new();
        for x in t.params.iter().filter(|x| x.required) {
            let v = match (t.ty, x.name) {
                (_, "inputs") => Value::Array(vec![Value::from("a"), Value::from("b")]),
                ("expression", "expr") => Value::from("a + b"),
                ("filter", "expr") => Value::from("v > 1"),
                ("publish", "node") => Value::from("result"),
                (_, "artifact") => return cfg,
                _ => match x.ty {
                    "number" => Value::UInt(100),
                    "map" => Value::Map(BTreeMap::new()),
                    _ => Value::from("downstream/x/y"),
                },
            };
            cfg.insert(x.name.to_owned(), v);
        }
        if t.ty == "deadband" {
            cfg.insert("abs".into(), Value::UInt(1));
        }
        if t.ty == "alarm" {
            cfg.insert("high".into(), Value::UInt(10));
        }
        cfg
    }

    #[test]
    fn every_type_checks_with_its_params() {
        for t in TYPES.iter().filter(|t| t.ty != "wasm") {
            let cfg = sample(t);
            let got = ports(t.ty, &cfg).unwrap_or_else(|e| panic!("{}: {e}", t.ty));
            let outs: Vec<&str> = got.outputs.iter().map(|(n, _)| n.as_str()).collect();
            assert_eq!(outs, t.outputs, "{} outputs", t.ty);
            let ins: Vec<String> = got.inputs.iter().map(|(n, _)| n.clone()).collect();
            // the fixed ports, then the ones a parameter names (as the editor draws them)
            let mut want: Vec<String> = t.inputs.iter().map(|s| (*s).to_owned()).collect();
            if let Some(d) = &t.dyn_inputs {
                let names: &[&str] = if cfg.contains_key(d.param) {
                    &["a", "b"]
                } else {
                    d.default
                };
                want.extend(names.iter().map(|n| format!("{}{n}", d.prefix)));
            }
            assert_eq!(ins, want, "{} inputs", t.ty);
            // every listed param is one the type takes
            let mut all = cfg.clone();
            for x in t.params {
                all.entry(x.name.to_owned()).or_insert(match x.ty {
                    "number" => Value::UInt(1),
                    "bool" => Value::Bool(false),
                    "map" => Value::Map(BTreeMap::new()),
                    "array" => Value::Array(vec![Value::from("a")]),
                    _ => match x.default {
                        Def::Str(d) => Value::from(d),
                        _ => Value::from("x"),
                    },
                });
            }
            ports(t.ty, &all).unwrap_or_else(|e| panic!("{} with every param: {e}", t.ty));
        }
        assert!(ports("nope", &BTreeMap::new()).is_err());
        assert_eq!(TYPES.len(), 36);
        // every logic block is in the palette
        for b in crate::blocks::TYPES {
            assert!(TYPES.iter().any(|t| t.ty == *b), "{b} in the catalog");
        }
    }

    fn same_number(a: &Value, b: &Value) -> bool {
        a == b || matches!((a.as_f64(), b.as_f64()), (Some(x), Some(y)) if x == y)
    }

    /// ADR 0038 §2: a block's `default` and `port` in the catalog are those of the block.
    #[test]
    fn block_defaults_and_ports_match_the_blocks() {
        for b in crate::blocks::TYPES {
            let t = find(b).unwrap();
            let params = crate::blocks::params_of(b).unwrap();
            for (name, default, port) in params {
                let x = t.params.iter().find(|x| x.name == name).unwrap_or_else(|| {
                    panic!("{b}.{name} in the catalog");
                });
                match x.default.value() {
                    None => assert_eq!(default, Value::Null, "{b}.{name} default"),
                    Some(d) => {
                        assert!(same_number(&d, &default), "{b}.{name}: {d:?} ≠ {default:?}")
                    }
                }
                let listed = t.inputs.contains(&format!("in.{name}").as_str());
                assert_eq!(listed, port, "{b}.{name} port");
            }
        }
    }

    /// ADR 0038 §1–§2: echo flags, typed defaults, port types; the compiler's echo outputs
    /// agree with the catalog.
    #[test]
    fn echo_outputs_and_port_types() {
        let Value::Array(all) = value() else {
            panic!("an array")
        };
        let entry = |ty: &str| -> BTreeMap<String, Value> {
            all.iter()
                .find_map(|v| match v {
                    Value::Map(m) if m.get("type") == Some(&Value::from(ty)) => Some(m.clone()),
                    _ => None,
                })
                .unwrap()
        };
        let param = |ty: &str, name: &str| -> BTreeMap<String, Value> {
            let Some(Value::Array(ps)) = entry(ty).get("params").cloned() else {
                panic!("params")
            };
            ps.into_iter()
                .find_map(|v| match v {
                    Value::Map(m) if m.get("name") == Some(&Value::from(name)) => Some(m),
                    _ => None,
                })
                .unwrap()
        };
        // the one static clash: latch's input `reset` echoes, its parameter `reset` does not
        assert_eq!(
            param("latch", "reset").get("echo"),
            Some(&Value::Bool(false))
        );
        assert_eq!(param("scale", "k").get("echo"), Some(&Value::Bool(true)));
        assert_eq!(param("scale", "k").get("default"), Some(&Value::UInt(1)));
        assert_eq!(
            param("scale", "input_min").get("port"),
            Some(&Value::from("in.input_min"))
        );
        // spec 06 0.2.17: the older types' parameters an editor binds have ports
        for (ty, p) in [
            ("scale", "k"),
            ("scale", "b"),
            ("alarm", "high"),
            ("alarm", "low"),
            ("alarm", "hysteresis"),
            ("alarm", "delay_s"),
            ("alarm", "return_delay_s"),
            ("delay", "ms"),
            ("window", "size_s"),
            ("deadband", "abs"),
            ("deadband", "pct"),
            ("timer", "period_ms"),
        ] {
            assert_eq!(
                param(ty, p).get("port"),
                Some(&Value::from(format!("in.{p}"))),
                "{ty}.{p}"
            );
            assert_eq!(
                param(ty, p).get("echo"),
                Some(&Value::Bool(true)),
                "{ty}.{p}"
            );
        }
        assert_eq!(param("window", "kind").get("port"), None);
        assert_eq!(param("alarm", "on_bad").get("port"), None);
        assert_eq!(
            param("stopwatch", "interval").get("default"),
            Some(&Value::Float(0.5))
        );
        assert_eq!(
            param("window", "fn").get("default"),
            Some(&Value::from("avg"))
        );
        assert_eq!(
            param("add", "inputs").get("default"),
            Some(&Value::Array(vec![Value::from("0"), Value::from("1")]))
        );
        let pt = |ty: &str| match entry(ty).get("port_types") {
            Some(Value::Map(m)) => m.clone(),
            _ => panic!("port_types"),
        };
        let scale = pt("scale");
        assert_eq!(scale.get("in"), Some(&Value::from("number")));
        assert_eq!(scale.get("input_out_of_range"), Some(&Value::from("bool")));
        assert_eq!(scale.get("k"), Some(&Value::from("number")));
        assert_eq!(pt("add").get("in.0"), Some(&Value::from("any")));
        assert_eq!(
            pt("expression").get("in.a"),
            None,
            "a sample port is not listed"
        );
        assert_eq!(entry("add").get("echo_inputs"), Some(&Value::Bool(true)));
        // spec 06 0.2.19: the blocks whose operands take a constant
        for ty in [
            "add", "concat", "if", "hub", "trace", "round", "not", "length",
        ] {
            assert_eq!(entry(ty).get("values"), Some(&Value::Bool(true)), "{ty}");
        }
        for ty in ["number", "stopwatch", "scale", "set"] {
            assert_eq!(entry(ty).get("values"), None, "{ty}");
        }
        assert_eq!(
            entry("timer").get("echo_inputs"),
            None,
            "a timer's only input is its parameter's port"
        );
        assert_eq!(
            pt("timer").get("in.period_ms"),
            Some(&Value::from("number"))
        );
        for t in TYPES {
            let ports = ports(t.ty, &sample_cfg(t)).unwrap_or_else(|e| panic!("{}: {e}", t.ty));
            // a name is one port type, whether input, output or echo
            for e in &ports.echoes {
                if let Some((_, ty)) = ports.inputs.iter().find(|(n, _)| *n == e.name) {
                    assert_eq!(*ty, e.ty, "{}.{}", t.ty, e.name);
                }
                assert!(
                    ports.outputs.iter().all(|(n, _)| *n != e.name),
                    "{}.{}",
                    t.ty,
                    e.name
                );
            }
            for x in t.params {
                let has = ports.echo(x.name).is_some_and(|e| e.of == EchoOf::Param);
                assert_eq!(has, param_echo(t, x), "{}.{} echo", t.ty, x.name);
            }
            // every input that is not a parameter's port echoes
            for (n, _) in &ports.inputs {
                let of_param = param_of_port(t, n).is_some();
                assert_eq!(ports.echo(n).is_some(), !of_param, "{}.{n}", t.ty);
            }
        }
    }

    /// The compiler takes an edge from an echo output, with its type.
    #[test]
    fn edges_from_echo_outputs() {
        let def = |edges: &[(&str, &str)]| {
            let n = |kv: &[(&str, Value)]| {
                Value::Map(
                    kv.iter()
                        .map(|(k, v)| ((*k).to_owned(), v.clone()))
                        .collect(),
                )
            };
            n(&[
                ("id", Value::from("f")),
                (
                    "nodes",
                    n(&[
                        (
                            "r",
                            n(&[
                                ("type", Value::from("round")),
                                ("precision", Value::UInt(2)),
                            ]),
                        ),
                        ("l", n(&[("type", Value::from("latch"))])),
                        ("b", n(&[("type", Value::from("not"))])),
                        ("x", n(&[("type", Value::from("number"))])),
                    ]),
                ),
                (
                    "edges",
                    Value::Array(
                        edges
                            .iter()
                            .map(|(a, b)| Value::Array(vec![Value::from(*a), Value::from(*b)]))
                            .collect(),
                    ),
                ),
            ])
        };
        // a parameter's echo (number) and an input's echo
        crate::def::compile(&def(&[
            ("r.precision", "x.in"),
            ("l.reset", "b.in"),
            ("r.in", "b.in"),
        ]))
        .unwrap();
        // a number echo does not fit a bool input
        let e = crate::def::compile(&def(&[("r.precision", "l.in")])).unwrap_err();
        assert!(e.0.contains("does not fit"), "{e}");
        // a parameter's port has no echo of its own; neither has latch's parameter reset
        let e = crate::def::compile(&def(&[("r.in.precision", "x.in")])).unwrap_err();
        assert!(e.0.contains("has no output"), "{e}");
        // an echo loop is a cycle
        let e = crate::def::compile(&def(&[("b.in", "b.in")])).unwrap_err();
        assert!(e.0.contains("cycle"), "{e}");
    }
}
