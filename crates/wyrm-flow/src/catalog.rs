//! The node types an editor offers (`dataflows/~act/node_types`): for
//! each, its category, ports and parameters, as [`crate::nodes::ports`]
//! checks them. A test keeps the two in step.

use std::collections::BTreeMap;
use wyrm_core::Value;

/// One parameter of a node type.
pub struct Param {
    pub name: &'static str,
    /// `number`, `string`, `bool`, `map`, `array` (of names) or `dynamic`.
    pub ty: &'static str,
    pub required: bool,
    pub choices: &'static [&'static str],
    pub default: Option<&'static str>,
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
        default: None,
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
    x.default = Some(default);
    x
}

const fn ed(mut x: Param, editor: &'static str) -> Param {
    x.editor = Some(editor);
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
        inputs: &[],
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
        inputs: &["in"],
        outputs: &["out"],
        dyn_inputs: None,
        dyn_outputs: None,
        params: &[req(p("ms", "number", "Milliseconds."))],
    },
    NodeType {
        ty: "scale",
        category: "Math",
        description: "out = k × in + b; with a range, in is first mapped from input_min…input_max to output_min…output_max.",
        inputs: &["in", "in.input_min", "in.input_max", "in.output_min", "in.output_max"],
        outputs: &["out", "input_out_of_range"],
        dyn_inputs: None,
        dyn_outputs: None,
        params: &[
            p("k", "number", "Factor (default 1)."),
            p("b", "number", "Offset (default 0)."),
            p("input_min", "number", "Range from (default 0 once a range parameter is given)."),
            p("input_max", "number", "Range to (default 1)."),
            p("output_min", "number", "Mapped from (default 0)."),
            p("output_max", "number", "Mapped to (default 100)."),
        ],
    },
    NodeType {
        ty: "deadband",
        category: "Math",
        description: "Passes a value that moved by more than abs or pct.",
        inputs: &["in"],
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
        inputs: &["in"],
        outputs: &["out"],
        dyn_inputs: None,
        dyn_outputs: None,
        params: &[
            ed(req(p("size_s", "number", "Window length in seconds.")), "duration"),
            pick(p("kind", "string", "tumbling: back to back; sliding: the last size_s at each sample."), &["tumbling", "sliding"], "tumbling"),
            pick(p("fn", "string", "What the window gives."), &["avg", "min", "max", "sum", "count", "rate"], "avg"),
            p("max_samples", "number", "Most samples kept, 1..100 000 (default 10 000)."),
        ],
    },
    NodeType {
        ty: "alarm",
        category: "Alarms",
        description: "true while in is above high or below low (with hysteresis and delays); an event on each change.",
        inputs: &["in"],
        outputs: &["out", "event"],
        dyn_inputs: None,
        dyn_outputs: None,
        params: &[
            p("high", "number", "Raised above (high or low required)."),
            p("low", "number", "Raised below."),
            p("hysteresis", "number", "Back inside by this much before it clears."),
            ed(p("delay_s", "number", "Seconds outside before it is raised."), "duration"),
            ed(p("return_delay_s", "number", "Seconds inside before it clears."), "duration"),
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
            p("deadband", "number", "With on change: a smaller change is not written."),
            p("allow_bad", "bool", "Write values of bad quality too."),
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
            p("allow_bad", "bool", "Run on samples of bad quality too."),
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
            p("inputs", "array", "Input port names (default in)."),
            p("outputs", "array", "Output port names (default out)."),
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
        params: &[p("value", "number", "The value at start (default 0).")],
    },
    NodeType {
        ty: "string",
        category: "Variables",
        description: "A text: sent at start, and again when in brings another.",
        inputs: &["in"],
        outputs: &["out"],
        dyn_inputs: None,
        dyn_outputs: None,
        params: &[ed(p("value", "string", "The text at start (default empty)."), "textarea")],
    },
    NodeType {
        ty: "bool",
        category: "Variables",
        description: "A bool: sent at start, and again when in brings another.",
        inputs: &["in"],
        outputs: &["out"],
        dyn_inputs: None,
        dyn_outputs: None,
        params: &[p("value", "bool", "The value at start (default false).")],
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
        description: "in rounded to precision places (0: an integer).",
        inputs: &["in", "in.precision"],
        outputs: &["out"],
        dyn_inputs: None,
        dyn_outputs: None,
        params: &[p("precision", "number", "Places after the point, 0…20 (default 0).")],
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
        inputs: &["in.then", "in.else"],
        outputs: &["out"],
        dyn_inputs: Some(ITEMS),
        dyn_outputs: None,
        params: &[
            pick(
                p("op", "string", "= all equal; and / or of the inputs; > < >= <= between each input and the next."),
                &["=", "and", "or", ">", "<", ">=", "<="],
                "=",
            ),
            p("then", "dynamic", "Sent when it passes (default true)."),
            p("else", "dynamic", "Sent when it does not (default false)."),
            INPUTS,
        ],
    },
    NodeType {
        ty: "hub",
        category: "Logic",
        description: "The input that changed last: its value, its index and an event.",
        inputs: &[],
        outputs: &["out", "index", "on_change"],
        dyn_inputs: Some(ITEMS),
        dyn_outputs: None,
        params: &[p("ignore_null", "bool", "A null on an input is not passed (default true)."), INPUTS],
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
            p("enabled", "bool", "Counting (default false)."),
            ed(p("interval", "number", "Seconds between two steps, at least 0.05 (default 0.5)."), "duration"),
            p("step", "number", "Added each interval (default 1)."),
            p("modulo", "number", "Above 0: the count wraps (or stops) there (default 0)."),
            p("loop", "bool", "At modulo: start again from the remainder; false: stop there (default true)."),
            p("reset_value", "number", "The count at start and after reset (default 0)."),
        ],
    },
    NodeType {
        ty: "trace",
        category: "Logic",
        description: "Writes msg and the inputs to the broker log at level trace.",
        inputs: &[],
        outputs: &[],
        dyn_inputs: Some(ITEMS),
        dyn_outputs: None,
        params: &[
            p("tracing", "bool", "Writing (default true)."),
            p("msg", "string", "The line's text (default trace)."),
            INPUTS,
        ],
    },
    NodeType {
        ty: "concat",
        category: "Text",
        description: "The inputs as one text.",
        inputs: &[],
        outputs: &["out"],
        dyn_inputs: Some(ITEMS),
        dyn_outputs: None,
        params: &[p("strict", "bool", "A missing input gives null (default false: empty text)."), INPUTS],
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
];

/// Variable inputs `in.<name>` of a block (default `in.0`, `in.1`).
const ITEMS: DynPorts = DynPorts {
    param: "inputs",
    prefix: "in.",
    default: &["0", "1"],
};

const INPUTS: Param = p(
    "inputs",
    "array",
    "Names of the variable inputs, [A-Za-z0-9_]+, at most 64 (default 0, 1): ports in.<name>.",
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
                        if let Some(d) = x.default {
                            m.insert("default".into(), Value::from(d));
                        }
                        if let Some(e) = x.editor {
                            m.insert("editor".into(), Value::from(e));
                        }
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
                ]);
                if let Some(d) = &t.dyn_inputs {
                    m.insert("dyn_inputs".into(), dyn_ports(d));
                }
                if let Some(d) = &t.dyn_outputs {
                    m.insert("dyn_outputs".into(), dyn_ports(d));
                }
                Value::Map(m)
            })
            .collect(),
    )
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
                        Some(d) => Value::from(d),
                        None => Value::from("x"),
                    },
                });
            }
            ports(t.ty, &all).unwrap_or_else(|e| panic!("{} with every param: {e}", t.ty));
        }
        assert!(ports("nope", &BTreeMap::new()).is_err());
        assert_eq!(TYPES.len(), 35);
        // every logic block is in the palette
        for b in crate::blocks::TYPES {
            assert!(TYPES.iter().any(|t| t.ty == *b), "{b} in the catalog");
        }
    }
}
