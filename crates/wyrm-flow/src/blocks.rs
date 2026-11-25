//! Logic blocks: small operators with a value per parameter (`docs/flow-blocks.md`).
//!
//! A block keeps the last value of each input. A parameter takes its value from the node's
//! config and, where the block has the port `in.<param>`, from the last sample on that port.
//! Variable inputs are named by the config list `inputs` (default `["0", "1"]`, ports
//! `in.0`, `in.1`, …). Any sample on an input calculates the block; an output is sent only when
//! its value or quality changed (events always). The variables (`number`, `string`, `bool`,
//! `table`) and `constant` send at start. A pure block ([`pure`]) with no wired input
//! calculates once at start from its constants and parameters (spec 06 0.2.30); what it sends
//! is made of typed constants ([`Msg::constant`]), so it runs no command, not even through
//! `in` of a `set` or an `invoke`. Any other block waits for its first input.
//!
//! Quality: the worst of the inputs that have a sample. Time: the latest of them.
//!
//! Numbers: an integer stays an integer while it fits (`add`, `subtract`, `multiply`, `abs`,
//! `round` to 0 places, `modulo`'s quotient); `divide` gives a float; a result that is not
//! finite is `null`. Text converts to a number when it parses, a bool to 1 or 0.

use crate::commands::{MAX_INTERVAL_MS, MIN_INTERVAL_MS};
use crate::def::Map;
use crate::nodes::{
    names, put, ConfigError, Io, Msg, Node, Out, Payload, PortName, PortType, Ports,
};
use std::collections::BTreeMap;
use std::time::Duration;
use tracing::trace;
use wyrm_core::{Quality, Value};
use wyrm_link_sdk::now_us;

pub(crate) mod date;
mod math;
pub(crate) mod table;
pub(crate) mod tables;
mod text;

pub use tables::TableConfigError;

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
    "case",
    // the second set (ADR 0040 §4)
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
    // the third set (ADR 0044): math, rounding, formatting, trigonometry
    "constant",
    "factorial",
    "log",
    "power",
    "root",
    "bound",
    "round_up",
    "round_down",
    "format_number",
    "parse_number",
    "sin",
    "cos",
    "tan",
    "cot",
    "asin",
    "acos",
    "atan",
    "to_degrees",
    "to_radians",
    "average",
    "median",
    "mode",
    "std_deviation",
    "variance",
    // text and codecs
    "left",
    "right",
    "trim",
    "base64_encode",
    "base64_decode",
    "url_encode",
    "url_decode",
    "to_camel_case",
    "from_camel_case",
    "hash",
    "json_parse",
    "json_stringify",
    // date and time
    "now",
    "date_time",
    "date_format",
    "date_parse",
    "date_math",
    "date_range",
    // logic and events
    "router",
    "event_gate",
    "catch_error",
    // tables (ADR 0044 §2)
    "table",
    "table_recorder",
    "table_from_csv",
    "table_to_csv",
    "table_from_json",
    "table_to_json",
    "table_map_columns",
    "table_sort",
    "table_filter",
    "table_group_by",
    "table_join",
    "table_page",
    "table_rollup",
    "table_aggregate",
    "table_select_rows",
    "table_select_columns",
    "table_columns",
    "table_row_cells",
    "table_add_row",
    "table_remove_rows",
    "table_edit_rows",
    "table_transpose",
    "table_from_map",
];

/// Variable inputs of one block at most.
pub const MAX_ITEMS: usize = 64;
/// Longest text a block makes (`concat`, a `string` variable), bytes: as the expression
/// engine's strings. A longer one is `null` with quality `bad` (a `concat` in a loop through
/// a `delay` would grow without end; automated review of e89b1d4).
pub const MAX_TEXT: usize = 4096;
/// Most items a block puts in a list (`split`); more is `null` with quality `bad`.
pub const MAX_LIST: usize = 1000;
/// The longest `ms` of `debounce` and `throttle`: one hour.
const MAX_HOLD_MS: f64 = 3_600_000.0;
/// `ms` of `debounce` and `throttle` when the parameter is no finite number.
const DEFAULT_HOLD_MS: f64 = 500.0;
/// The stopwatch's clock, and the shortest interval it counts.
const STOPWATCH_TICK: Duration = Duration::from_millis(50);
const MIN_INTERVAL_S: f64 = 0.05;
/// How often a relative `date_range` (`today`, `current3days`) is calculated again.
const RANGE_TICK: Duration = Duration::from_secs(1);
/// `now`'s default `interval_ms`.
pub const NOW_INTERVAL_MS: i64 = 1000;

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

/// A value as a number: numbers, bools (1/0) and text that parses. A float that is not
/// finite (NaN, ±inf, also as the texts `NaN` and `inf`) is no number: a value from a port or
/// from the config never becomes a duration, an index, a length or a count as one (security
/// review 2026-11-10: `Duration::from_secs_f64(NaN)` panics).
fn num(v: &Value) -> Option<N> {
    match v {
        Value::Int(i) => Some(N::I(*i)),
        Value::UInt(u) => Some(i64::try_from(*u).map_or(N::F(*u as f64), N::I)),
        Value::Float(x) => x.is_finite().then_some(N::F(*x)),
        Value::Bool(b) => Some(N::I(i64::from(*b))),
        Value::Str(s) => {
            let s = s.trim();
            s.parse::<i64>()
                .map(N::I)
                .ok()
                .or_else(|| s.parse::<f64>().ok().filter(|x| x.is_finite()).map(N::F))
        }
        _ => None,
    }
}

/// A parameter as a whole number of at most `max`: a count of characters, an index. What is
/// not a finite number, or is below 0, is `None`.
fn whole(v: &Value, max: usize) -> Option<usize> {
    let x = num(v)?.f();
    (x >= 0.0).then_some(if x >= max as f64 { max } else { x as usize })
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

/// A value as text within [`MAX_TEXT`]; `None` when it is longer.
fn bounded_text(v: &Value) -> Option<String> {
    let mut out = String::new();
    push_text(&mut out, v).then_some(out)
}

/// Appends `v` as text; `false` once `out` is past [`MAX_TEXT`] (it stops there).
fn push_text(out: &mut String, v: &Value) -> bool {
    let ok = |out: &String| out.len() <= MAX_TEXT;
    match v {
        Value::Array(a) => {
            out.push('[');
            for (i, x) in a.iter().enumerate() {
                if i > 0 {
                    out.push_str(", ");
                }
                if !push_text(out, x) {
                    return false;
                }
            }
            out.push(']');
        }
        Value::Map(m) => {
            out.push('{');
            for (i, (k, x)) in m.iter().enumerate() {
                if i > 0 {
                    out.push_str(", ");
                }
                out.push_str(k);
                out.push_str(": ");
                if !ok(out) || !push_text(out, x) {
                    return false;
                }
            }
            out.push('}');
        }
        Value::Bytes(b) => {
            if out.len() + b.len() * 2 > MAX_TEXT {
                return false;
            }
            out.push_str(&wyrm_core::hex::encode(b));
        }
        v => out.push_str(&text(v)),
    }
    ok(out)
}

/// `x` with `places` places after the point, its trailing zeros trimmed until `min` places
/// remain (and the point, at none): `round`'s `text`.
fn fixed(x: f64, places: i32, min: i32) -> String {
    let mut s = format!("{x:.*}", usize::try_from(places).unwrap_or(0));
    if let Some(dot) = s.find('.') {
        let keep = dot + 1 + usize::try_from(min).unwrap_or(0);
        while s.len() > keep && s.ends_with('0') {
            s.pop();
        }
        if s.ends_with('.') {
            s.pop();
        }
    }
    s
}

/// A scalar as text, for `concat`: `null` is empty.
fn text(v: &Value) -> String {
    match v {
        Value::Null => String::new(),
        Value::Str(s) => s.clone(),
        Value::Bool(b) => b.to_string(),
        Value::Int(i) => i.to_string(),
        Value::UInt(u) => u.to_string(),
        Value::Float(x) => format!("{x:?}"),
        // lists, maps and bytes go through `push_text`, within the bound
        Value::Bytes(_) | Value::Array(_) | Value::Map(_) => bounded_text(v).unwrap_or_default(),
    }
}

/// Equal as `if`'s `=` compares: the same value, or the same number.
fn same(a: &Value, b: &Value) -> bool {
    a == b || matches!((num(a), num(b)), (Some(x), Some(y)) if x.f() == y.f())
}

/// What a pure calculation of the third set sees: `in`, the parameters, the variable inputs
/// and the time of the calculation (from the runtime's clock, so tests give it).
pub(crate) struct View<'a> {
    inv: &'a Value,
    params: &'a BTreeMap<String, Value>,
    now_us: u64,
    /// Every input's last sample (`table_join`'s `right`).
    ins: &'a BTreeMap<String, Payload>,
}

/// No inputs, for a view in a test.
#[cfg(test)]
pub(crate) static NO_INPUTS: BTreeMap<String, Payload> = BTreeMap::new();

impl View<'_> {
    fn p(&self, name: &str) -> &Value {
        self.params.get(name).unwrap_or(&Value::Null)
    }
}

/// What a pure calculation gives: each output's value, and whether it is `bad` (an input
/// that was valid but gave a result past a bound).
type Outs = Vec<(&'static str, Value, bool)>;

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
    Case,
    Substring,
    Replace,
    Split,
    Join,
    MakeObject,
    MakeArray,
    Get,
    Stats,
    Changed,
    RisingEdge,
    FallingEdge,
    Counter,
    Toggle,
    SampleAndHold,
    Select,
    Debounce,
    Throttle,
    Constant,
    Math(math::Op),
    Stat(math::Stat),
    Str(text::Op),
    Date(date::Op),
    Router,
    EventGate,
    CatchError,
    TableVar,
    Recorder,
    Table(tables::Op),
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
        "case" => Kind::Case,
        "substring" => Kind::Substring,
        "replace" => Kind::Replace,
        "split" => Kind::Split,
        "join" => Kind::Join,
        "make_object" => Kind::MakeObject,
        "make_array" => Kind::MakeArray,
        "get" => Kind::Get,
        "stats" => Kind::Stats,
        "changed" => Kind::Changed,
        "rising_edge" => Kind::RisingEdge,
        "falling_edge" => Kind::FallingEdge,
        "counter" => Kind::Counter,
        "toggle" => Kind::Toggle,
        "sample_and_hold" => Kind::SampleAndHold,
        "select" => Kind::Select,
        "debounce" => Kind::Debounce,
        "throttle" => Kind::Throttle,
        "constant" => Kind::Constant,
        "router" => Kind::Router,
        "event_gate" => Kind::EventGate,
        "catch_error" => Kind::CatchError,
        "table" => Kind::TableVar,
        "table_recorder" => Kind::Recorder,
        t => {
            if let Some((_, op)) = math::OPS.iter().find(|(n, _)| *n == t) {
                Kind::Math(*op)
            } else if let Some((_, st)) = math::STATS.iter().find(|(n, _)| *n == t) {
                Kind::Stat(*st)
            } else if let Some((_, op)) = text::OPS.iter().find(|(n, _)| *n == t) {
                Kind::Str(*op)
            } else if let Some((_, op)) = date::OPS.iter().find(|(n, _)| *n == t) {
                Kind::Date(*op)
            } else if let Some((_, op)) = tables::OPS.iter().find(|(n, _)| *n == t) {
                Kind::Table(*op)
            } else {
                return None;
            }
        }
    })
}

impl Shape {
    /// The shape of a block on `in` alone.
    fn one_in(params: Vec<Param>, outputs: &'static [(&'static str, PortType)]) -> Self {
        Self {
            inputs: &["in"],
            params,
            items: false,
            outputs,
        }
    }

    /// The shape of a block on its variable inputs alone.
    fn on_items(params: Vec<Param>, outputs: &'static [(&'static str, PortType)]) -> Self {
        Self {
            inputs: &[],
            params,
            items: true,
            outputs,
        }
    }

    /// The shape of a variable (`number`, `string`, `bool`): `value` and its type on `out`.
    fn variable(default: Value, outputs: &'static [(&'static str, PortType)]) -> Self {
        Self::one_in(vec![param("value", default, false)], outputs)
    }
}

/// The blocks with inputs of their own beside `in` and the variable inputs, or both.
impl Shape {
    /// `stopwatch`: counts on its clock; `reset` starts it again.
    fn stopwatch() -> Self {
        use PortType::*;
        Shape {
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
        }
    }

    /// `case`: `in` against the case values of its variable inputs.
    fn case() -> Self {
        use PortType::*;
        let s = |v: &str| Value::Str(v.to_owned());
        Shape {
            inputs: &["in"],
            params: vec![param("op", s("="), true), param("else", Value::Null, true)],
            items: true,
            outputs: &[("out", Any)],
        }
    }

    /// `counter`: counts the samples on `in`; `reset` sets it back.
    fn counter() -> Self {
        use PortType::*;
        Shape {
            inputs: &["in", "reset"],
            params: vec![
                param("step", Value::Int(1), true),
                param("initial", Value::Int(0), true),
            ],
            items: false,
            outputs: &[("out", Number)],
        }
    }

    /// `toggle`: flips on each sample on `in`; `reset` sets it back.
    fn toggle() -> Self {
        use PortType::*;
        Shape {
            inputs: &["in", "reset"],
            params: vec![param("initial", Value::Bool(false), true)],
            items: false,
            outputs: &[("out", Bool)],
        }
    }

    /// `sample_and_hold`: sends `in` on each sample on `trigger`.
    fn sample_and_hold() -> Self {
        use PortType::*;
        Shape {
            inputs: &["in", "trigger"],
            params: vec![],
            items: false,
            outputs: &[("out", Any)],
        }
    }

    /// `router`: sends `in` to the output of the case value `condition` matches.
    fn router() -> Self {
        use PortType::*;
        let s = |v: &str| Value::Str(v.to_owned());
        Shape {
            inputs: &["in", "condition"],
            params: vec![
                param("op", s("="), true),
                param("single_output", Value::Bool(false), true),
            ],
            items: true,
            outputs: &[("else", Any)],
        }
    }

    /// `event_gate`: fires once every variable input changed; `reset` opens it again.
    fn event_gate() -> Self {
        use PortType::*;
        let s = |v: &str| Value::Str(v.to_owned());
        Shape {
            inputs: &["reset"],
            params: vec![param("log_order", s("none"), true)],
            items: true,
            outputs: &[("on_finish", Map), ("order", Any)],
        }
    }

    /// `table_recorder`: records its variable inputs as rows; `reset` replaces them.
    fn recorder() -> Self {
        use PortType::*;
        Shape {
            inputs: &["reset"],
            params: vec![
                param("enabled", Value::Bool(true), true),
                param("buffer_size", Value::Int(1024), true),
                param("time_window_s", Value::Int(0), true),
                param("ignore_null", Value::Bool(false), true),
            ],
            items: true,
            outputs: &[("out", Any)],
        }
    }
}

fn shape(k: Kind) -> Shape {
    use PortType::*;
    let s = |v: &str| Value::Str(v.to_owned());
    match k {
        Kind::Number => Shape::variable(Value::Int(0), &[("out", Number)]),
        Kind::Bool => Shape::variable(Value::Bool(false), &[("out", Bool)]),
        Kind::Text => Shape::variable(s(""), &[("out", Any)]),
        Kind::Add | Kind::Subtract | Kind::Multiply | Kind::Divide | Kind::Max | Kind::Min => {
            Shape::on_items(vec![], &[("out", Number)])
        }
        Kind::Abs => Shape::one_in(vec![], &[("out", Number)]),
        Kind::Round => Shape::one_in(
            vec![
                param("precision", Value::Int(0), true),
                // fewest places in `text`: trailing zeros beyond it go (default: precision)
                param("min_precision", Value::Null, true),
            ],
            &[("out", Number), ("text", Any)],
        ),
        Kind::Modulo => Shape::one_in(
            vec![param("modulo", Value::Null, true)],
            &[("quotient", Number), ("remainder", Number)],
        ),
        Kind::Not => Shape::one_in(vec![], &[("out", Bool)]),
        Kind::If => Shape::on_items(
            vec![
                param("op", s("="), true),
                param("then", Value::Bool(true), true),
                param("else", Value::Bool(false), true),
            ],
            &[("out", Any)],
        ),
        Kind::Hub => Shape::on_items(
            vec![param("ignore_null", Value::Bool(true), true)],
            &[("out", Any), ("index", Number), ("on_change", Map)],
        ),
        Kind::Stopwatch => Shape::stopwatch(),
        Kind::Trace => Shape::on_items(
            vec![
                param("tracing", Value::Bool(true), true),
                param("msg", s("trace"), true),
            ],
            &[],
        ),
        Kind::Concat => Shape::on_items(
            vec![param("strict", Value::Bool(false), true)],
            &[("out", Any)],
        ),
        Kind::Length => Shape::one_in(vec![], &[("out", Number)]),
        // the variable inputs are pairs: in.<1st> a case value, in.<2nd> what it gives, …
        Kind::Case => Shape::case(),
        Kind::Substring => Shape::one_in(
            vec![
                param("start", Value::Int(0), true),
                param("length", Value::Null, true),
                // ADR 0044: where it ends (exclusive); below 0 counts from the end
                param("end", Value::Null, true),
            ],
            &[("out", Any)],
        ),
        Kind::Replace => Shape::one_in(
            vec![
                param("from", s(""), true),
                param("to", s(""), true),
                // ADR 0044 §6: `from` is a bounded pattern
                param("regexp", Value::Bool(false), true),
            ],
            &[("out", Any)],
        ),
        Kind::Split | Kind::Join => {
            Shape::one_in(vec![param("separator", s(","), true)], &[("out", Any)])
        }
        Kind::MakeObject => Shape::on_items(vec![], &[("out", Map)]),
        Kind::MakeArray => Shape::on_items(vec![], &[("out", Any)]),
        Kind::Get => Shape::one_in(vec![param("path", s(""), true)], &[("out", Any)]),
        Kind::Stats => Shape::one_in(
            vec![],
            &[
                ("min", Number),
                ("max", Number),
                ("avg", Number),
                ("sum", Number),
                ("count", Number),
            ],
        ),
        Kind::Changed => Shape::one_in(vec![], &[("on_change", Map)]),
        Kind::RisingEdge | Kind::FallingEdge => Shape::one_in(vec![], &[("on_edge", Map)]),
        Kind::Counter => Shape::counter(),
        Kind::Toggle => Shape::toggle(),
        Kind::SampleAndHold => Shape::sample_and_hold(),
        Kind::Select => Shape::on_items(vec![param("index", Value::Int(0), true)], &[("out", Any)]),
        Kind::Debounce | Kind::Throttle => {
            Shape::one_in(vec![param("ms", Value::Int(500), true)], &[("out", Any)])
        }
        Kind::Constant => math::constant_shape(),
        Kind::Math(op) => math::shape(op),
        Kind::Stat(_) => math::stat_shape(),
        Kind::Str(op) => text::shape(op),
        Kind::Date(op) => date::shape(op),
        // the case values are the variable inputs; each has the output `out.<name>`
        Kind::Router => Shape::router(),
        Kind::EventGate => Shape::event_gate(),
        Kind::TableVar => Shape::one_in(vec![param("value", Value::Null, false)], &[("out", Any)]),
        Kind::Recorder => Shape::recorder(),
        Kind::Table(op) => tables::shape(op),
        Kind::CatchError => Shape::on_items(
            vec![],
            &[
                ("out", Any),
                ("code", Number),
                ("source", Any),
                ("on_error", Map),
            ],
        ),
    }
}

/// Each parameter of block type `ty`: its name, its default and whether it has the port
/// `in.<name>` (the catalog's `default` and `port` are checked against it).
pub fn params_of(ty: &str) -> Option<Vec<(&'static str, Value, bool)>> {
    let sh = shape(kind(ty)?);
    Some(
        sh.params
            .into_iter()
            .map(|p| (p.name, p.default, p.port))
            .collect(),
    )
}

/// The variable inputs of a block: `inputs` (default `0`, `1`), each `[A-Za-z0-9_]+`, at most
/// [`MAX_ITEMS`], none named like one of its parameters.
fn items(cfg: &Map, sh: &Shape) -> Result<Vec<String>, ConfigError> {
    let list = if cfg.contains_key("inputs") {
        names(cfg)?
    } else {
        vec!["0".into(), "1".into()]
    };
    if list.len() > MAX_ITEMS {
        return Err(ConfigError::ManyInputs);
    }
    for (i, n) in list.iter().enumerate() {
        if list[..i].contains(n) {
            return Err(ConfigError::InputTwice(n.clone()));
        }
        if sh.params.iter().any(|p| p.name == n) {
            return Err(ConfigError::InputIsParam(n.clone()));
        }
    }
    Ok(list)
}

/// Ports and config check of a block type; `None` for a type this module does not have.
pub fn ports(ty: &str, cfg: &Map) -> Option<Result<Ports, ConfigError>> {
    let k = kind(ty)?;
    Some(check(k, cfg))
}

/// The compile check of a table block's per-row scripts (`expr`, `mapping`) and its
/// `aggregates`; other types have none.
pub fn check_scripts(ty: &str, cfg: &Map) -> Result<(), ConfigError> {
    match kind(ty) {
        Some(Kind::Table(op)) => tables::scripts(op, cfg)
            .map(|_| ())
            .map_err(ConfigError::Table),
        _ => Ok(()),
    }
}

/// Whether block type `ty` has operand inputs that take a constant in config `values`
/// (spec 06 0.2.19): `in` and the variable inputs, never a parameter's port, never `reset`,
/// and not the variables (their `value` is the constant).
pub fn takes_values(ty: &str) -> bool {
    kind(ty).is_some_and(|k| has_operands(k, &shape(k)))
}

fn has_operands(k: Kind, sh: &Shape) -> bool {
    // `now`'s `in` is a trigger: its value means nothing (spec 06 0.2.30)
    !matches!(
        k,
        Kind::Number | Kind::Text | Kind::Bool | Kind::TableVar | Kind::Date(date::Op::Now)
    ) && (sh.items || sh.inputs.contains(&"in"))
}

/// Whether a block of kind `k` is a pure function of its inputs and parameters: no state, no
/// events, no clock of its own. Such a block with no wired input calculates once at the start
/// from its constants (spec 06 0.2.30, `docs/flow-blocks.md`). `date_range` reads the clock
/// for a relative range, as it does on its own tick.
fn pure(k: Kind) -> bool {
    match k {
        Kind::Add
        | Kind::Subtract
        | Kind::Multiply
        | Kind::Divide
        | Kind::Max
        | Kind::Min
        | Kind::Abs
        | Kind::Round
        | Kind::Modulo
        | Kind::Not
        | Kind::If
        | Kind::Concat
        | Kind::Length
        | Kind::Case
        | Kind::Substring
        | Kind::Replace
        | Kind::Split
        | Kind::Join
        | Kind::MakeObject
        | Kind::MakeArray
        | Kind::Get
        | Kind::Stats
        | Kind::Select
        | Kind::Math(_)
        | Kind::Stat(_)
        | Kind::Str(_) => true,
        Kind::Date(op) => op != date::Op::Now,
        Kind::Table(op) => op != tables::Op::Page,
        // variables and `constant` send at start anyway; the others keep state, fire events,
        // keep time or route: they wait for a real sample
        Kind::Number
        | Kind::Text
        | Kind::Bool
        | Kind::Constant
        | Kind::TableVar
        | Kind::Hub
        | Kind::Stopwatch
        | Kind::Trace
        | Kind::Changed
        | Kind::RisingEdge
        | Kind::FallingEdge
        | Kind::Counter
        | Kind::Toggle
        | Kind::SampleAndHold
        | Kind::Debounce
        | Kind::Throttle
        | Kind::Router
        | Kind::EventGate
        | Kind::CatchError
        | Kind::Recorder => false,
    }
}

/// Whether block type `ty` calculates at start when no edge leads into it (spec 06 0.2.30).
pub fn computes_at_start(ty: &str) -> bool {
    kind(ty).is_some_and(pure)
}

/// `now`'s `interval_ms`: 0 (no clock) or [`MIN_INTERVAL_MS`]…[`MAX_INTERVAL_MS`], as a
/// command's.
fn now_interval_ok(v: &Value) -> bool {
    num(v).is_some_and(|n| {
        let x = n.f();
        x == 0.0 || (MIN_INTERVAL_MS..=MAX_INTERVAL_MS).contains(&x)
    })
}

/// The operand constants of config `values`: `{<port>: <value>}`, each port an operand input
/// of the block (`in`, `in.<name>` of `inputs`); keyed by the input's name (`in`, `<name>`).
fn constants(k: Kind, sh: &Shape, cfg: &Map) -> Result<BTreeMap<String, Value>, ConfigError> {
    let Some(v) = cfg.get("values") else {
        return Ok(BTreeMap::new());
    };
    let Value::Map(m) = v else {
        return Err(ConfigError::ValuesNotMap);
    };
    let items = if sh.items {
        items(cfg, sh)?
    } else {
        Vec::new()
    };
    let mut out = BTreeMap::new();
    for (port, v) in m {
        let name = match port.as_str() {
            "in" if sh.inputs.contains(&"in") => "in",
            p => match p.strip_prefix("in.") {
                Some(n) if items.iter().any(|i| i == n) => n,
                _ => {
                    return Err(ConfigError::NotOperand {
                        port: port.clone(),
                        block: kind_name(k),
                    })
                }
            },
        };
        out.insert(name.to_owned(), v.clone());
    }
    Ok(out)
}

fn kind_name(k: Kind) -> &'static str {
    TYPES
        .iter()
        .copied()
        .find(|t| kind(t) == Some(k))
        .unwrap_or("block")
}

fn check(k: Kind, cfg: &Map) -> Result<Ports, ConfigError> {
    let sh = shape(k);
    let known: Vec<&str> = sh
        .params
        .iter()
        .map(|p| p.name)
        .chain(sh.items.then_some("inputs"))
        // `now` takes no constant; one saved before spec 06 0.2.30 is read and ignored
        .chain((has_operands(k, &sh) || k == Kind::Date(date::Op::Now)).then_some("values"))
        .collect();
    if let Some(x) = cfg.keys().find(|x| !known.contains(&x.as_str())) {
        return Err(ConfigError::UnknownField(x.clone()));
    }
    if k == Kind::Date(date::Op::Now) {
        if let Some(v) = cfg.get("interval_ms") {
            if !now_interval_ok(v) {
                return Err(ConfigError::NowInterval);
            }
        }
    } else {
        constants(k, &sh, cfg)?;
    }
    Ops::of_config(k, cfg)?;
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
    let mut outputs: Vec<(String, PortType)> = Vec::new();
    if k == Kind::Router {
        outputs.extend(
            items(cfg, &sh)?
                .into_iter()
                .map(|n| (format!("out.{n}"), PortType::Any)),
        );
    }
    outputs.extend(sh.outputs.iter().map(|(n, t)| ((*n).to_owned(), *t)));
    Ok(Ports {
        inputs,
        outputs,
        echoes: Vec::new(),
    })
}

wyrm_core::name_enum! {
    /// `if`'s operators (spec 06 0.2.21 adds `!=`, `contains`, `starts_with`, `ends_with`).
    /// The config's `op` and a sample on `in.op` become one of these where they are read;
    /// a config is checked at compile, so the name is in `~def` as written.
    #[derive(Default)]
    pub enum IfOp as "if operator" without codec {
        #[default]
        Eq => "=",
        Ne => "!=",
        And => "and",
        Or => "or",
        Gt => ">",
        Lt => "<",
        Ge => ">=",
        Le => "<=",
        Contains => "contains",
        StartsWith => "starts_with",
        EndsWith => "ends_with",
    }
}

wyrm_core::name_enum! {
    /// `case`'s and `router`'s operators: each compares `in` with a pair's case value.
    #[derive(Default)]
    pub enum CaseOp as "case operator" without codec {
        #[default]
        Eq => "=",
        Ne => "!=",
        Gt => ">",
        Lt => "<",
        Ge => ">=",
        Le => "<=",
        Contains => "contains",
        StartsWith => "starts_with",
        EndsWith => "ends_with",
        /// ADR 0044 §6: `in` as text contains a match of the case as a bounded pattern.
        Regexp => "regexp",
    }
}

/// A comparison of two numbers.
#[derive(Clone, Copy)]
enum NumCmp {
    Gt,
    Lt,
    Ge,
    Le,
}

/// A test of one text against another.
#[derive(Clone, Copy)]
enum TextCmp {
    Contains,
    StartsWith,
    EndsWith,
}

/// The operator a block runs with, decoded where it comes in: from the config when the
/// block is built, from a sample on `in.op` when it arrives. `if` reads `if_op`, `case`
/// and `router` read `case_op`; a block of another kind has no `op` and reads neither.
/// A block whose config has no `op` runs with the spec's default, `=`.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
struct Ops {
    if_op: IfOp,
    case_op: CaseOp,
}

impl Ops {
    /// The operators of the config of a block of kind `k`. A name that is not an operator
    /// of the kind is an error that lists them: the flow does not compile.
    fn of_config(k: Kind, cfg: &Map) -> Result<Self, ConfigError> {
        let mut ops = Self::default();
        match cfg.get("op") {
            None => Ok(ops),
            Some(Value::Str(name)) => {
                ops.set(k, name)?;
                Ok(ops)
            }
            Some(_) if Self::has(k) => Err(ConfigError::OpNotText),
            Some(_) => Ok(ops),
        }
    }

    /// A block of kind `k` has the parameter `op`.
    fn has(k: Kind) -> bool {
        matches!(k, Kind::If | Kind::Case | Kind::Router)
    }

    /// Take the operator `name` for a block of kind `k`. `Err` (the operators of the
    /// kind) when it is not one; the operator in use stays. A kind without `op` takes
    /// nothing and refuses nothing.
    fn set(&mut self, k: Kind, name: &str) -> Result<(), NotAnOp> {
        match k {
            Kind::If => {
                self.if_op = IfOp::from_name(name).ok_or(NotAnOp(IfOp::NAMES))?;
            }
            Kind::Case | Kind::Router => {
                self.case_op = CaseOp::from_name(name).ok_or(NotAnOp(CaseOp::NAMES))?;
            }
            _ => {}
        }
        Ok(())
    }
}

/// `op` is not an operator of the block's kind; holds the operators of the kind.
#[derive(Debug, thiserror::Error)]
#[error("op: one of {0:?}")]
pub struct NotAnOp(&'static [&'static str]);

/// `x op p` for the text operators, both as text; a `null` never matches. (`case` skips an
/// empty case text first: it matches nothing; in `if` an empty text is contained in every text.)
fn text_op(op: TextCmp, x: &Value, p: &Value) -> bool {
    if *x == Value::Null || *p == Value::Null {
        return false;
    }
    let (x, p) = (text(x), text(p));
    match op {
        TextCmp::Contains => x.contains(&p),
        TextCmp::StartsWith => x.starts_with(&p),
        TextCmp::EndsWith => x.ends_with(&p),
    }
}

/// `x op p` for the comparisons: as numbers (one that is not a number never matches).
fn num_op(op: NumCmp, x: &Value, p: &Value) -> bool {
    match (num(x), num(p)) {
        (Some(a), Some(b)) => {
            let (a, b) = (a.f(), b.f());
            match op {
                NumCmp::Gt => a > b,
                NumCmp::Lt => a < b,
                NumCmp::Ge => a >= b,
                NumCmp::Le => a <= b,
            }
        }
        _ => false,
    }
}

/// Whether `x` matches the case value `p` by `op` (`case`, `router`).
fn case_match(
    op: CaseOp,
    x: &Value,
    p: &Value,
    cache: &mut Option<(String, Option<regex::Regex>)>,
) -> bool {
    // an empty case text matches nothing
    let as_text = |t: TextCmp| !text(p).is_empty() && text_op(t, x, p);
    match op {
        CaseOp::Regexp => {
            *x != Value::Null
                && !text(p).is_empty()
                && cached(cache, &text(p)).is_some_and(|re| re.is_match(&text(x)))
        }
        CaseOp::Eq => same(x, p),
        CaseOp::Ne => !same(x, p),
        CaseOp::Gt => num_op(NumCmp::Gt, x, p),
        CaseOp::Lt => num_op(NumCmp::Lt, x, p),
        CaseOp::Ge => num_op(NumCmp::Ge, x, p),
        CaseOp::Le => num_op(NumCmp::Le, x, p),
        CaseOp::Contains => as_text(TextCmp::Contains),
        CaseOp::StartsWith => as_text(TextCmp::StartsWith),
        CaseOp::EndsWith => as_text(TextCmp::EndsWith),
    }
}

/// The longest pattern of `replace` and `case`, bytes, and the most its compiled form may take.
pub const MAX_PATTERN: usize = 256;
const MAX_PATTERN_SIZE: usize = 64 * 1024;

/// A pattern (ADR 0044 §6): linear time, no backreferences, at most [`MAX_PATTERN`] bytes and
/// 64 KiB compiled; `None` when it does not compile. The last one is kept in `cache`.
fn cached<'a>(
    cache: &'a mut Option<(String, Option<regex::Regex>)>,
    pattern: &str,
) -> Option<&'a regex::Regex> {
    if cache.as_ref().is_none_or(|(p, _)| p != pattern) {
        let re = (pattern.len() <= MAX_PATTERN)
            .then(|| {
                regex::RegexBuilder::new(pattern)
                    .size_limit(MAX_PATTERN_SIZE)
                    .dfa_size_limit(MAX_PATTERN_SIZE)
                    .nest_limit(32)
                    .build()
                    .ok()
            })
            .flatten();
        *cache = Some((pattern.to_owned(), re));
    }
    cache.as_ref().and_then(|(_, re)| re.as_ref())
}

/// A block of `ty` from `cfg`; `None` for a type this module does not have.
pub fn build(
    ty: &str,
    flow: &str,
    id: &str,
    cfg: &Map,
) -> Option<Result<Box<dyn Node>, ConfigError>> {
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
        // an operand's constant is its value until a sample replaces it (spec 06 0.2.19); a
        // pure block with no wired input calculates from it at start (0.2.30). `now` has none.
        let consts = if k == Kind::Date(date::Op::Now) {
            BTreeMap::new()
        } else {
            constants(k, &sh, cfg)?
        };
        Ok(Box::new(Block {
            ops: Ops::of_config(k, cfg)?,
            values: consts
                .iter()
                .map(|(k, v)| (k.clone(), Payload::new(v.clone())))
                .collect(),
            consts,
            kind: k,
            name: format!("{flow}/{id}"),
            param_ports: sh
                .params
                .iter()
                .filter(|p| p.port)
                .map(|p| p.name)
                .collect(),
            params,
            params_rev: 0,
            items,
            seen: BTreeMap::new(),
            sent: BTreeMap::new(),
            events: 0,
            count: None,
            elapsed_us: 0,
            born: false,
            unwired: false,
            prev: None,
            held: None,
            due: None,
            passed: None,
            re: None,
            range: None,
            gate: Vec::new(),
            order: Vec::new(),
            finished: false,
            route: None,
            scripts: match k {
                Kind::Table(op) => tables::scripts(op, cfg)?,
                _ => None,
            },
            rows: std::collections::VecDeque::new(),
        }) as Box<dyn Node>)
    }))
}

struct Block {
    /// The operator in use (`if`, `case`, `router`), typed.
    ops: Ops,
    kind: Kind,
    /// `<flow>/<node>`, for `trace`.
    name: String,
    /// Each parameter's value: from the config, then from its port.
    params: BTreeMap<String, Value>,
    /// Grows on every change of `params` (ADR 0038: their echo outputs and `watch`).
    params_rev: u64,
    /// The parameters that have a port `in.<name>`.
    param_ports: Vec<&'static str>,
    /// The variable inputs' names, in order.
    items: Vec<String>,
    /// The last sample of each input port (without `in.`; `in` and `reset` as they are),
    /// seeded with the operands' constants. Held as it came: a table is shared with the edge
    /// and the probe, not copied.
    values: BTreeMap<String, Payload>,
    /// The operands' constants from config `values`, for `watch` (`Node::seeds`).
    consts: BTreeMap<String, Value>,
    /// Quality and time of each input that has a sample.
    seen: BTreeMap<String, (Quality, u64)>,
    /// The last value and quality sent on each output (shared with the sample sent).
    sent: BTreeMap<String, (Payload, Quality)>,
    events: u64,
    /// The stopwatch's count; `None` until it was set.
    count: Option<N>,
    /// Time the stopwatch has run since its last step.
    elapsed_us: u64,
    /// The sample in hand was born at the start (ADR 0040 §2): the event blocks, `counter`,
    /// `toggle` and `sample_and_hold` take its value and do not act on it.
    born: bool,
    /// No edge leads into the block: a pure one calculates at start (spec 06 0.2.30).
    unwired: bool,
    /// `changed` and the edge blocks: the sample before.
    prev: Option<Payload>,
    /// `debounce` and `throttle`: the value that waits, and when it goes out.
    held: Option<Payload>,
    due: Option<tokio::time::Instant>,
    /// `throttle`: when a value last went out.
    passed: Option<tokio::time::Instant>,
    /// The last pattern `replace` or `case` compiled (ADR 0044 §6).
    re: Option<(String, Option<regex::Regex>)>,
    /// `date_range`: the range text a `next` or `previous` moved to.
    range: Option<String>,
    /// `event_gate`: the inputs that changed since the reset, the order it logs, and whether it
    /// fired; `router`: the output it routed to last.
    gate: Vec<String>,
    order: Vec<String>,
    finished: bool,
    route: Option<String>,
    /// The per-row scripts of a table block, compiled at build.
    scripts: Option<tables::Scripts>,
    /// `table_recorder`: the rows it holds.
    rows: std::collections::VecDeque<BTreeMap<String, Value>>,
}

impl Block {
    fn param(&self, name: &str) -> &Value {
        self.params.get(name).unwrap_or(&Value::Null)
    }

    fn item_values(&self) -> Vec<Value> {
        self.items
            .iter()
            .map(|n| self.values.get(n).map_or(Value::Null, |v| v.get().clone()))
            .collect()
    }

    /// The last sample on `in`.
    fn in_value(&self) -> &Value {
        self.in_sample().map_or(&Value::Null, Payload::get)
    }

    /// The last sample on `in` as it came: a table stays shared.
    fn in_sample(&self) -> Option<&Payload> {
        self.values.get("in")
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
    fn send(
        &mut self,
        port: impl Into<PortName>,
        v: impl Into<Payload>,
        q: Quality,
        t: u64,
        out: &mut Out,
    ) {
        let port = port.into();
        let v = v.into();
        // the slot is found once and its key is made only for a port's first value
        match self.sent.get_mut(port.as_ref()) {
            Some(last) if last.0 == v && last.1 == q => return,
            Some(last) => {
                last.0.clone_from(&v);
                last.1 = q;
            }
            None => {
                self.sent.insert(port.to_string(), (v.clone(), q));
            }
        }
        out.emit(port, Msg::new(v, q, t));
    }

    /// An event on `port`: always sent.
    fn fire(&mut self, port: &'static str, t: u64, out: &mut Out) {
        self.events += 1;
        let v = Value::Map(BTreeMap::from([
            ("event".to_owned(), Value::Str(port.to_owned())),
            ("id".to_owned(), Value::UInt(self.events)),
        ]));
        out.emit(port, Msg::new(v, Quality::Good, t));
    }

    /// The numbers of the variable inputs. An input with no value yet is `null`, which is no
    /// number: the same as leaving it out.
    fn nums(&self) -> impl Iterator<Item = N> + '_ {
        self.items
            .iter()
            .filter_map(|n| self.values.get(n).and_then(|v| num(v)))
    }

    fn calculate(&mut self, changed: &str, out: &mut Out) {
        let (q, t) = self.quality();
        match self.kind {
            Kind::Number | Kind::Text | Kind::Bool => self.variable(q, t, out),
            Kind::TableVar => self.table_var(q, t, out),
            Kind::Recorder => self.record(changed, q, t, out),
            Kind::Table(tables::Op::Page) => self.page(changed, q, t, out),
            Kind::Table(op) => self.table_op(op, q, t, out),
            Kind::Add => {
                let v = self
                    .nums()
                    .fold(N::I(0), |a, b| a.op(b, i64::checked_add, |x, y| x + y));
                self.send("out", v.value(), q, t, out);
            }
            Kind::Subtract | Kind::Multiply | Kind::Divide => self.arithmetic(q, t, out),
            Kind::Max | Kind::Min => self.max_min(q, t, out),
            Kind::Abs => self.abs(q, t, out),
            Kind::Round => self.round(q, t, out),
            Kind::Modulo => self.modulo(q, t, out),
            Kind::Not => {
                let v = !truth(self.in_value(), false);
                self.send("out", Value::Bool(v), q, t, out);
            }
            Kind::If => self.if_then(q, t, out),
            Kind::Case => self.case(q, t, out),
            Kind::Hub => self.hub(changed, q, t, out),
            Kind::Stopwatch => self.stopwatch(changed, q, t, out),
            Kind::Trace => self.trace(),
            Kind::Concat => self.concat(q, t, out),
            Kind::Substring => self.substring(q, t, out),
            Kind::Replace => self.replace(q, t, out),
            Kind::Split => self.split(q, t, out),
            Kind::Join => self.join(q, t, out),
            Kind::MakeObject => self.make_object(q, t, out),
            Kind::MakeArray => {
                let v = Value::Array(self.item_values());
                self.send("out", v, q, t, out);
            }
            Kind::Get => self.get_path(q, t, out),
            Kind::Stats => self.stats(q, t, out),
            Kind::Changed | Kind::RisingEdge | Kind::FallingEdge => self.edge(changed, t, out),
            Kind::Counter | Kind::Toggle => self.counter_toggle(changed, q, t, out),
            Kind::SampleAndHold => self.sample_and_hold(changed, q, t, out),
            Kind::Select => self.select(q, t, out),
            Kind::Debounce | Kind::Throttle => self.debounce_throttle(changed, q, t, out),
            Kind::Constant => {
                let v = math::constant(self.param("name"));
                self.send("out", v, q, t, out);
            }
            Kind::Math(op) => {
                let outs = math::calc(op, &self.view());
                self.send_all(outs, q, t, out);
            }
            Kind::Stat(st) => {
                let v = math::stat(st, &self.item_values());
                self.send("out", v, q, t, out);
            }
            Kind::Str(op) => {
                let outs = text::calc(op, &self.view());
                self.send_all(outs, q, t, out);
            }
            Kind::Date(date::Op::Range) => self.date_range(changed, q, t, out),
            // the time at start, on its clock and on each sample of `in`; never on a change of
            // `interval_ms`
            Kind::Date(date::Op::Now) => {
                if matches!(changed, "" | "in" | "__tick") {
                    let now = now_us();
                    self.send("out", Value::Int(now as i64), q, now, out);
                }
            }
            Kind::Router => self.router(q, t, out),
            Kind::EventGate => self.event_gate(changed, q, t, out),
            Kind::CatchError => self.catch_error(changed, q, t, out),
            Kind::Date(op) => {
                let outs = date::calc(op, &self.view());
                self.send_all(outs, q, t, out);
            }
            Kind::Length => self.length(q, t, out),
        }
    }

    /// A variable: `in`, else its `value`, as its type.
    fn variable(&mut self, q: Quality, t: u64, out: &mut Out) {
        let v = self.var_value(
            self.values
                .get("in")
                .map_or(self.param("value"), Payload::get),
        );
        self.send("out", v, q, t, out);
    }

    /// `table`: `in`, else its `value`, as a table; an empty one for `null`.
    fn table_var(&mut self, q: Quality, t: u64, out: &mut Out) {
        let v = self
            .values
            .get("in")
            .map_or(self.param("value"), Payload::get);
        let (v, q) = match v {
            Value::Null => (table::Table::default().to_value().unwrap_or(Value::Null), q),
            v => match table::Table::from_value(v).and_then(table::Table::into_value) {
                Some(t) => (t, q),
                None => (Value::Null, Quality::Bad),
            },
        };
        self.send("out", v, q, t, out);
    }

    /// A table block other than `table_page`, with its per-row scripts.
    fn table_op(&mut self, op: tables::Op, q: Quality, t: u64, out: &mut Out) {
        // the scripts keep their variables between calls: out of the block for the
        // call, which reads the rest of it
        let mut scripts = self.scripts.take();
        let outs = tables::calc(op, &self.view(), scripts.as_mut());
        self.scripts = scripts;
        self.send_all(outs, q, t, out);
    }

    /// `subtract`, `multiply`, `divide`: the first number by each of the others in turn.
    fn arithmetic(&mut self, q: Quality, t: u64, out: &mut Out) {
        let mut xs = self.nums();
        let v = xs.next().map(|first| {
            xs.fold(first, |a, b| match self.kind {
                Kind::Subtract => a.op(b, i64::checked_sub, |x, y| x - y),
                Kind::Multiply => a.op(b, i64::checked_mul, |x, y| x * y),
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

    /// `max`, `min`: the largest or the smallest number.
    fn max_min(&mut self, q: Quality, t: u64, out: &mut Out) {
        let max = self.kind == Kind::Max;
        let v = self.nums().reduce(|a, b| {
            let better = if max { b.f() > a.f() } else { b.f() < a.f() };
            if better {
                b
            } else {
                a
            }
        });
        self.send("out", v.map_or(Value::Null, N::value), q, t, out);
    }

    /// `abs`: the absolute value of `in`.
    fn abs(&mut self, q: Quality, t: u64, out: &mut Out) {
        let v = num(self.in_value()).map(|n| match n {
            N::I(i) => i.checked_abs().map_or(N::F((i as f64).abs()), N::I),
            N::F(x) => N::F(x.abs()),
        });
        self.send("out", v.map_or(Value::Null, N::value), q, t, out);
    }

    /// `round`: `in` to `precision` places, as a number and as text.
    fn round(&mut self, q: Quality, t: u64, out: &mut Out) {
        let places = num(self.param("precision")).map_or(0, |n| n.f().clamp(0.0, 20.0) as i32);
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
        let text = v.map_or(Value::Null, |n| {
            // `places` places, trailing zeros trimmed down to `min_precision`
            let min = num(self.param("min_precision"))
                .map_or(places, |m| m.f().clamp(0.0, f64::from(places)) as i32);
            Value::Str(fixed(n.f(), places, min))
        });
        self.send("out", v.map_or(Value::Null, N::value), q, t, out);
        self.send("text", text, q, t, out);
    }

    /// `modulo`: the quotient and the remainder of `in` by `modulo`.
    fn modulo(&mut self, q: Quality, t: u64, out: &mut Out) {
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

    /// `if`: `then` when the inputs pass `op`, else `else`.
    fn if_then(&mut self, q: Quality, t: u64, out: &mut Out) {
        let vs = self.item_values();
        let op = self.ops.if_op;
        // each input against the next, as numbers
        let chain = |c: NumCmp| {
            vs.len() > 1
                && vs.windows(2).all(|w| match w {
                    [a, b] => num_op(c, a, b),
                    _ => false,
                })
        };
        // the first input as text against any of the others
        let any_text = |c: TextCmp| {
            vs.split_first().is_some_and(|(x, rest)| {
                let x = if *x == Value::Null {
                    Value::Str(String::new())
                } else {
                    x.clone()
                };
                rest.iter().any(|p| text_op(c, &x, p))
            })
        };
        let yes = match op {
            IfOp::And => vs.iter().all(|v| truth(v, false)),
            IfOp::Or => vs.iter().any(|v| truth(v, false)),
            IfOp::Gt => chain(NumCmp::Gt),
            IfOp::Lt => chain(NumCmp::Lt),
            IfOp::Ge => chain(NumCmp::Ge),
            IfOp::Le => chain(NumCmp::Le),
            // the first input against the others: none equal
            IfOp::Ne => vs
                .split_first()
                .is_none_or(|(x, rest)| !rest.iter().any(|v| same(x, v))),
            IfOp::Contains => any_text(TextCmp::Contains),
            IfOp::StartsWith => any_text(TextCmp::StartsWith),
            IfOp::EndsWith => any_text(TextCmp::EndsWith),
            IfOp::Eq => vs
                .first()
                .is_none_or(|first| vs.iter().all(|v| same(v, first))),
        };
        let v = self.param(if yes { "then" } else { "else" }).clone();
        self.send("out", v, q, t, out);
    }

    /// `case`: what the first case value that `in` matches gives, else `else`.
    fn case(&mut self, q: Quality, t: u64, out: &mut Out) {
        let x = self.in_value().clone();
        let op = self.ops.case_op;
        let vs = self.item_values();
        let mut cache = self.re.take();
        let hit = vs
            .as_chunks::<2>()
            .0
            .iter()
            .find(|[p, _]| case_match(op, &x, p, &mut cache));
        let v = match hit {
            Some(pair) => pair[1].clone(),
            None => self.param("else").clone(),
        };
        self.re = cache;
        self.send("out", v, q, t, out);
    }

    /// `hub`: the input that changed, its index and an event.
    fn hub(&mut self, changed: &str, q: Quality, t: u64, out: &mut Out) {
        let Some(index) = self.items.iter().position(|n| n == changed) else {
            return;
        };
        let v = self.values.get(changed).cloned().unwrap_or_default();
        if v == Value::Null && truth(self.param("ignore_null"), true) {
            return;
        }
        self.send("index", Value::UInt(index as u64), q, t, out);
        // the input that changed last, even when it holds the same value as before
        out.emit("out", Msg::new(v.clone(), q, t));
        self.sent.insert("out".into(), (v, q));
        self.fire("on_change", t, out);
    }

    /// `stopwatch`: `reset`, or a sample before the first count, sets the count to
    /// `reset_value` (its clock steps it, in `step`).
    fn stopwatch(&mut self, changed: &str, q: Quality, t: u64, out: &mut Out) {
        if changed == "reset" || self.count.is_none() {
            self.count = Some(num(self.param("reset_value")).unwrap_or(N::I(0)));
            self.elapsed_us = 0;
            if changed == "reset" {
                let v = self.count.map_or(Value::Null, N::value);
                self.send("out", v, q, t, out);
            }
        }
    }

    /// `trace`: the inputs in the log.
    fn trace(&self) {
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

    /// `concat`: the inputs as one text.
    fn concat(&mut self, q: Quality, t: u64, out: &mut Out) {
        let vs = self.item_values();
        let (v, q) = if truth(self.param("strict"), false) && vs.contains(&Value::Null) {
            (Value::Null, q)
        } else {
            let mut s = String::new();
            if vs.iter().all(|v| push_text(&mut s, v)) {
                (Value::Str(s), q)
            } else {
                (Value::Null, Quality::Bad)
            }
        };
        self.send("out", v, q, t, out);
    }

    /// `substring`: a part of `in` as text.
    fn substring(&mut self, q: Quality, t: u64, out: &mut Out) {
        let v = match self.in_value() {
            Value::Null => Value::Null,
            v => {
                // a start below 0 or not a number is 0; a length never passes 4 KiB
                let start = whole(self.param("start"), usize::MAX).unwrap_or(0);
                let src = text(v);
                // `length` wins over `end`
                let len = match (
                    whole(self.param("length"), MAX_TEXT),
                    num(self.param("end")),
                ) {
                    (Some(l), _) => l,
                    (None, Some(e)) => {
                        let n = src.chars().count() as f64;
                        let e = e.f();
                        let end = if e < 0.0 { (n + e).max(0.0) } else { e.min(n) };
                        (end as usize).saturating_sub(start)
                    }
                    (None, None) => MAX_TEXT,
                };
                let part: String = src.chars().skip(start).take(len).collect();
                if part.len() > MAX_TEXT {
                    Value::Null
                } else {
                    Value::Str(part)
                }
            }
        };
        let q = if v == Value::Null && *self.in_value() != Value::Null {
            Quality::Bad
        } else {
            q
        };
        self.send("out", v, q, t, out);
    }

    /// `replace`: `in` as text with `from` replaced by `to`.
    fn replace(&mut self, q: Quality, t: u64, out: &mut Out) {
        let (v, q) = match self.in_value() {
            Value::Null => (Value::Null, q),
            v => {
                let (from, to) = (text(self.param("from")), text(self.param("to")));
                let src = text(v);
                if truth(self.param("regexp"), false) {
                    let r = self.pattern(&from).map(|re| {
                        let hits = re.find_iter(&src).count();
                        if src.len().saturating_add(hits.saturating_mul(to.len())) > MAX_TEXT {
                            None
                        } else {
                            Some(re.replace_all(&src, regex::NoExpand(&to)).into_owned())
                        }
                    });
                    let (v, q) = match r {
                        Some(Some(s)) => (Value::Str(s), q),
                        Some(None) => (Value::Null, Quality::Bad),
                        // a pattern that does not compile replaces nothing
                        None => (Value::Str(src), q),
                    };
                    self.send("out", v, q, t, out);
                    return;
                }
                // the result is bounded before it is built
                let grows = to.len().saturating_sub(from.len());
                let hits = if from.is_empty() {
                    0
                } else {
                    src.matches(&from).count()
                };
                if src.len().saturating_add(hits.saturating_mul(grows)) > MAX_TEXT {
                    (Value::Null, Quality::Bad)
                } else if hits == 0 {
                    (Value::Str(src), q)
                } else {
                    (Value::Str(src.replace(&from, &to)), q)
                }
            }
        };
        self.send("out", v, q, t, out);
    }

    /// `split`: `in` as text split at `separator`.
    fn split(&mut self, q: Quality, t: u64, out: &mut Out) {
        let (v, q) = match self.in_value() {
            Value::Null => (Value::Null, q),
            v => {
                let (src, sep) = (text(v), text(self.param("separator")));
                if sep.is_empty() {
                    (Value::Array(vec![Value::Str(src)]), q)
                } else if src.matches(&sep).count() >= MAX_LIST {
                    (Value::Null, Quality::Bad)
                } else {
                    let parts = src.split(&sep).map(|p| Value::Str(p.to_owned()));
                    (Value::Array(parts.collect()), q)
                }
            }
        };
        self.send("out", v, q, t, out);
    }

    /// `join`: the items of `in` as one text with `separator` between them.
    fn join(&mut self, q: Quality, t: u64, out: &mut Out) {
        let (v, q) = match self.in_value() {
            Value::Null => (Value::Null, q),
            Value::Array(a) => {
                let sep = text(self.param("separator"));
                let mut s = String::new();
                let ok = a.iter().enumerate().all(|(i, x)| {
                    if i > 0 {
                        s.push_str(&sep);
                    }
                    push_text(&mut s, x)
                });
                if ok {
                    (Value::Str(s), q)
                } else {
                    (Value::Null, Quality::Bad)
                }
            }
            v => (bounded_text(v).map_or(Value::Null, Value::Str), q),
        };
        self.send("out", v, q, t, out);
    }

    /// `make_object`: the inputs as a map by their names.
    fn make_object(&mut self, q: Quality, t: u64, out: &mut Out) {
        let m = self
            .items
            .iter()
            .cloned()
            .zip(self.item_values())
            .collect::<BTreeMap<_, _>>();
        self.send("out", Value::Map(m), q, t, out);
    }

    /// `get`: the value at `path` in `in`.
    fn get_path(&mut self, q: Quality, t: u64, out: &mut Out) {
        // a path longer than a text a block makes names nothing
        let path = Some(text(self.param("path")))
            .filter(|p| p.len() <= MAX_TEXT)
            .unwrap_or_else(|| "\u{0}".to_owned());
        let mut v = self.in_value();
        for seg in path.split('.').filter(|s| !s.is_empty()) {
            v = match v {
                Value::Map(m) => m.get(seg).unwrap_or(&Value::Null),
                Value::Array(a) => seg
                    .parse::<usize>()
                    .ok()
                    .and_then(|i| a.get(i))
                    .unwrap_or(&Value::Null),
                _ => &Value::Null,
            };
        }
        let v = v.clone();
        self.send("out", v, q, t, out);
    }

    /// `stats`: the minimum, maximum, average, sum and count of the numbers of `in`.
    fn stats(&mut self, q: Quality, t: u64, out: &mut Out) {
        let xs: Vec<f64> = match self.in_value() {
            Value::Array(a) => a.iter().filter_map(num).map(N::f).collect(),
            _ => Vec::new(),
        };
        let n = xs.len();
        let sum: f64 = xs.iter().sum();
        let of = |x: Option<f64>| x.map_or(Value::Null, |x| N::F(x).value());
        let min = xs.iter().copied().reduce(f64::min);
        let max = xs.iter().copied().reduce(f64::max);
        self.send("min", of(min), q, t, out);
        self.send("max", of(max), q, t, out);
        self.send("avg", of((n > 0).then(|| sum / n as f64)), q, t, out);
        self.send("sum", of((n > 0).then_some(sum)), q, t, out);
        self.send("count", Value::UInt(n as u64), q, t, out);
    }

    /// The edge blocks (`rising_edge` and `falling_edge`) and the block `changed`: an event
    /// when `in` turned or changed.
    fn edge(&mut self, changed: &str, t: u64, out: &mut Out) {
        if changed != "in" {
            return;
        }
        let v = self.in_sample().cloned().unwrap_or_default();
        let prev = self.prev.replace(v.clone());
        // a value born at the start is where the block starts from, not an event
        if self.born {
            return;
        }
        let was = prev.as_ref().is_some_and(|p| truth(p, false));
        let is = truth(&v, false);
        let (port, hit) = match self.kind {
            Kind::Changed => ("on_change", prev.is_some_and(|p| p != v)),
            // nothing before counts as false: the first true is an edge
            Kind::RisingEdge => ("on_edge", is && !was),
            _ => ("on_edge", !is && was),
        };
        if hit {
            self.fire(port, t, out);
        }
    }

    /// `counter`, `toggle`: a step on each sample on `in`, back to `initial` on `reset`.
    fn counter_toggle(&mut self, changed: &str, q: Quality, t: u64, out: &mut Out) {
        let initial = match self.kind {
            Kind::Counter => num(self.param("initial")).unwrap_or(N::I(0)),
            _ => N::I(i64::from(truth(self.param("initial"), false))),
        };
        let fresh = self.count.is_none();
        let mut n = self.count.unwrap_or(initial);
        let hit = changed == "in" && !self.born && *self.in_value() != Value::Null;
        if changed == "reset"
            && !self.born
            && truth(
                self.values.get("reset").map_or(&Value::Null, Payload::get),
                false,
            )
        {
            n = initial;
        } else if hit && self.kind == Kind::Counter {
            let step = num(self.param("step")).unwrap_or(N::I(1));
            let next = n.op(step, i64::checked_add, |x, y| x + y);
            // a count that would leave the finite numbers stays where it is
            if next.f().is_finite() {
                n = next;
            }
        } else if hit {
            n = N::I(i64::from(n.f() == 0.0));
        } else if !fresh {
            return;
        }
        self.count = Some(n);
        let v = match self.kind {
            Kind::Counter => n.value(),
            _ => Value::Bool(n.f() != 0.0),
        };
        self.send("out", v, q, t, out);
    }

    /// `sample_and_hold`: `in` on each sample on `trigger`.
    fn sample_and_hold(&mut self, changed: &str, q: Quality, t: u64, out: &mut Out) {
        let fired = self
            .values
            .get("trigger")
            .is_some_and(|v| *v != Value::Null);
        if changed == "trigger" && !self.born && fired {
            let v = self.in_sample().cloned().unwrap_or_default();
            self.send("out", v, q, t, out);
        }
    }

    /// `select`: the input at `index`.
    fn select(&mut self, q: Quality, t: u64, out: &mut Out) {
        let v = whole(self.param("index"), MAX_ITEMS)
            .and_then(|i| self.items.get(i))
            .and_then(|name| self.values.get(name))
            .cloned()
            .unwrap_or_default();
        self.send("out", v, q, t, out);
    }

    /// `debounce`, `throttle`: `in` held back for `ms`.
    fn debounce_throttle(&mut self, changed: &str, q: Quality, t: u64, out: &mut Out) {
        if changed != "in" {
            return;
        }
        let v = self.in_sample().cloned().unwrap_or_default();
        let now = tokio::time::Instant::now();
        let ms = self.hold();
        if self.kind == Kind::Debounce {
            // the value goes out once `ms` passed without another
            self.held = Some(v);
            self.due = Some(now + ms);
        } else if self.passed.is_none_or(|p| now >= p + ms) {
            self.passed = Some(now);
            self.held = None;
            self.send("out", v, q, t, out);
        } else {
            // the latest value waits for the end of the period
            self.held = Some(v);
            self.due = self.passed.map(|p| p + ms);
        }
    }

    /// `router`: `in` to the output of the first case value `condition` matches.
    fn router(&mut self, q: Quality, t: u64, out: &mut Out) {
        let x = self.values.get("condition").cloned().unwrap_or_default();
        let op = self.ops.case_op;
        let mut cache = self.re.take();
        let names = self.items.clone();
        let hit = names.iter().find(|name| {
            let p = self.values.get(*name).cloned().unwrap_or_default();
            case_match(op, &x, &p, &mut cache)
        });
        self.re = cache;
        let port = hit.map_or_else(|| "else".to_owned(), |n| format!("out.{n}"));
        let v = self.in_sample().cloned().unwrap_or_default();
        if truth(self.param("single_output"), false) {
            if let Some(last) = self.route.take().filter(|l| *l != port) {
                self.send(last, Value::Null, q, t, out);
            }
        }
        self.route = Some(port.clone());
        self.send(port, v, q, t, out);
    }

    /// `event_gate`: an event once every input changed since the reset, and their order.
    fn event_gate(&mut self, changed: &str, q: Quality, t: u64, out: &mut Out) {
        if changed == "reset" {
            let v = self.values.get("reset").map_or(&Value::Null, Payload::get);
            if !self.born && *v != Value::Null {
                self.gate.clear();
                self.order.clear();
                self.finished = false;
            }
            return;
        }
        if self.born || self.finished || !self.items.iter().any(|n| n == changed) {
            return;
        }
        let first = !self.gate.iter().any(|n| n == changed);
        if first {
            self.gate.push(changed.to_owned());
        }
        match self.param("log_order") {
            Value::Str(m) if m == "first_occurrence" && first => {
                self.order.push(changed.to_owned())
            }
            Value::Str(m) if m == "last_occurrence" => {
                self.order.retain(|n| n != changed);
                self.order.push(changed.to_owned());
            }
            Value::Str(m) if m == "all" => {
                if self.order.len() >= MAX_LIST {
                    self.order.remove(0);
                }
                self.order.push(changed.to_owned());
            }
            _ => {}
        }
        if self.gate.len() == self.items.len() {
            self.finished = true;
            let order =
                bounded_text(&Value::Str(self.order.join(","))).map_or(Value::Null, Value::Str);
            self.send("order", order, q, t, out);
            self.fire("on_finish", t, out);
        }
    }

    /// `catch_error`: the message, code and source of an error on an input, and an event.
    fn catch_error(&mut self, changed: &str, q: Quality, t: u64, out: &mut Out) {
        if self.born || !self.items.iter().any(|n| n == changed) {
            return;
        }
        let v = self.values.get(changed).cloned().unwrap_or_default();
        if v == Value::Null {
            return;
        }
        let (message, code) = match &*v {
            Value::Map(m) => (
                m.get("message").map_or_else(|| text(&v), text),
                m.get("code").and_then(num).map_or(Value::Null, N::value),
            ),
            v => (text(v), Value::Null),
        };
        let message = Some(message)
            .filter(|m| m.len() <= MAX_TEXT)
            .map_or(Value::Null, Value::Str);
        // the same text twice is two errors: `on_error` fires every time
        self.send("out", message, q, t, out);
        self.send("code", code, q, t, out);
        self.send("source", Value::Str(changed.to_owned()), q, t, out);
        self.fire("on_error", t, out);
    }

    /// `length`: the length of `in`.
    fn length(&mut self, q: Quality, t: u64, out: &mut Out) {
        let v = match self.in_value() {
            Value::Str(s) => Value::UInt(s.chars().count() as u64),
            Value::Array(a) => Value::UInt(a.len() as u64),
            Value::Map(m) => Value::UInt(m.len() as u64),
            Value::Bytes(b) => Value::UInt(b.len() as u64),
            _ => Value::Null,
        };
        self.send("out", v, q, t, out);
    }

    /// `pattern` compiled, from the cache when it was the last one.
    fn pattern(&mut self, pattern: &str) -> Option<regex::Regex> {
        let mut c = self.re.take();
        let r = cached(&mut c, pattern).cloned();
        self.re = c;
        r
    }

    /// `date_range`: the text in use is `in`, or the neighbour a `next` or `previous` moved to.
    fn date_range(&mut self, changed: &str, q: Quality, t: u64, out: &mut Out) {
        let now = now_us();
        let tz = date::zone(self.param("time_zone")).unwrap_or(jiff::tz::TimeZone::UTC);
        let ws = match self.param("week_start") {
            Value::Str(w) => date::WEEK_STARTS.iter().position(|x| x == w).unwrap_or(0),
            _ => 0,
        };
        if changed == "in" {
            self.range = None;
        }
        let fired = |s: &Self, port: &str| {
            changed == port && !s.born && s.values.get(port).is_some_and(|v| *v != Value::Null)
        };
        if fired(self, "next") || fired(self, "previous") {
            if let Some(r) = date::range(&self.range_text(), now as i64, &tz, ws) {
                self.range = Some(if changed == "next" {
                    r.next
                } else {
                    r.previous
                });
            }
        } else if changed == "next" || changed == "previous" {
            return;
        }
        let text = Value::Str(self.range_text());
        let outs = date::calc(
            date::Op::Range,
            &View {
                inv: &text,
                params: &self.params,
                now_us: now,
                ins: &self.values,
            },
        );
        self.send_all(outs, q, t, out);
    }

    /// `table_recorder`: a row `{t, <input>…}` for each sample on an input (one born at the
    /// start too: it records, it runs nothing); `buffer_size` rows at most (1 … 10 000), and with
    /// `time_window_s` only the rows that recent.
    fn record(&mut self, changed: &str, q: Quality, t: u64, out: &mut Out) {
        if changed == "reset" {
            let v = self.values.get("reset").cloned().unwrap_or_default();
            if self.born || v == Value::Null {
                return;
            }
            // a table of the recorder's columns replaces the rows
            self.rows = table::Table::from_value(&v)
                .map(|tb| tb.rows.into_iter().collect())
                .unwrap_or_default();
        } else if self.items.iter().any(|n| n == changed) {
            let v = self.values.get(changed).cloned().unwrap_or_default();
            if !truth(self.param("enabled"), true)
                || (v == Value::Null && truth(self.param("ignore_null"), false))
            {
                return;
            }
            let mut row: BTreeMap<String, Value> = self
                .items
                .iter()
                .map(|n| {
                    (
                        n.clone(),
                        self.values.get(n).map_or(Value::Null, |v| v.get().clone()),
                    )
                })
                .collect();
            row.insert("t".into(), Value::UInt(t));
            self.rows.push_back(row);
        } else if !matches!(
            changed,
            "enabled" | "buffer_size" | "time_window_s" | "ignore_null"
        ) {
            return;
        }
        let cap = whole(self.param("buffer_size"), table::MAX_ROWS)
            .filter(|n| *n > 0)
            .unwrap_or(1024);
        while self.rows.len() > cap {
            self.rows.pop_front();
        }
        if let Some(w) = num(self.param("time_window_s"))
            .map(N::f)
            .filter(|w| *w > 0.0)
        {
            let newest = self
                .rows
                .back()
                .and_then(|r| r.get("t"))
                .and_then(Value::as_f64)
                .unwrap_or(0.0);
            let cut = newest - w * 1e6;
            while self
                .rows
                .front()
                .and_then(|r| r.get("t"))
                .and_then(Value::as_f64)
                .is_some_and(|x| x < cut)
            {
                self.rows.pop_front();
            }
        }
        let mut cols = vec!["t".to_owned()];
        cols.extend(self.items.iter().cloned());
        let tb = table::Table {
            columns: cols,
            rows: self.rows.iter().cloned().collect(),
        };
        // a buffer past 512 KiB drops its oldest rows until it fits
        let mut tb = tb;
        while !tb.fits() && !tb.rows.is_empty() {
            tb.rows.remove(0);
            self.rows.pop_front();
        }
        let v = tb.to_value().unwrap_or(Value::Null);
        self.send("out", v, q, t, out);
    }

    /// `table_page`: the page in `count`; `next`, `previous`, `first`, `last` move it (not a
    /// sample born at the start), `page` sets it.
    fn page(&mut self, changed: &str, q: Quality, t: u64, out: &mut Out) {
        let tb = table::Table::from_value(self.in_value());
        let n = tb.as_ref().map_or(0, |tb| tb.rows.len());
        let size = num(self.param("page_size")).map(N::f);
        // no size or below 0: one page of all; 0: an empty page
        let size = match size {
            Some(s) if s >= 0.0 => s.min(table::MAX_ROWS as f64) as usize,
            _ => n.max(1),
        };
        let pages = if size == 0 {
            1
        } else {
            n.div_ceil(size).max(1)
        };
        let mut page = match self.count {
            Some(p) if changed != "page" => p.f() as i64,
            _ => num(self.param("page")).map_or(0, |p| p.f().clamp(0.0, 1e9) as i64),
        };
        let fired = |s: &Self, p: &str| {
            changed == p && !s.born && s.values.get(p).is_some_and(|v| *v != Value::Null)
        };
        if fired(self, "next") {
            page += 1;
        } else if fired(self, "previous") {
            page -= 1;
        } else if fired(self, "first") {
            page = 0;
        } else if fired(self, "last") {
            page = pages as i64 - 1;
        } else if matches!(changed, "next" | "previous" | "first" | "last") {
            return;
        }
        let page = page.clamp(0, pages as i64 - 1);
        self.count = Some(N::I(page));
        let v = match tb {
            None => Value::Null,
            Some(tb) => {
                let from = (page as usize).saturating_mul(size).min(n);
                let rows = tb.rows[from..(from + size).min(n)].to_vec();
                table::Table {
                    columns: tb.columns,
                    rows,
                }
                .to_value()
                .unwrap_or(Value::Null)
            }
        };
        self.send("out", v, q, t, out);
        self.send("current_page", Value::Int(page), q, t, out);
        self.send("total_pages", Value::UInt(pages as u64), q, t, out);
    }

    /// `date_range`'s text in use.
    fn range_text(&self) -> String {
        match &self.range {
            Some(r) => r.clone(),
            None => match self.in_value() {
                Value::Str(s) => s.trim().to_owned(),
                _ => String::new(),
            },
        }
    }

    /// Whether `date_range` reads the clock: its text is a name or a relative range.
    fn range_is_relative(&self) -> bool {
        let t = match (&self.range, self.in_value()) {
            (Some(r), _) => r.as_str(),
            (None, Value::Str(s)) => s.as_str(),
            _ => return false,
        };
        date::is_relative(t.trim())
    }

    /// The view a pure calculation of the third set reads.
    fn view(&self) -> View<'_> {
        View {
            inv: self.in_value(),
            params: &self.params,
            now_us: now_us(),
            ins: &self.values,
        }
    }

    /// Send what a pure calculation gave, in its order; a `bad` result has quality `bad`.
    fn send_all(&mut self, outs: Outs, q: Quality, t: u64, out: &mut Out) {
        for (port, v, bad) in outs {
            self.send(port, v, if bad { Quality::Bad } else { q }, t, out);
        }
    }

    /// `now`'s clock: `interval_ms`, none when it is 0 (only on samples of `in`).
    fn now_every(&self) -> Option<Duration> {
        let ms = num(self.param("interval_ms")).map_or(NOW_INTERVAL_MS as f64, N::f);
        (ms >= MIN_INTERVAL_MS).then(|| Duration::from_millis(ms.min(MAX_INTERVAL_MS) as u64))
    }

    /// `ms` of `debounce` and `throttle`.
    fn hold(&self) -> Duration {
        // not a finite number: the default; `num` gives no NaN, so the clamp is total
        let ms = num(self.param("ms")).map_or(DEFAULT_HOLD_MS, N::f);
        Duration::from_millis(ms.clamp(0.0, MAX_HOLD_MS) as u64)
    }

    /// A variable's value in its type.
    fn var_value(&self, v: &Value) -> Value {
        match self.kind {
            Kind::Number => num(v).map_or(Value::Null, N::value),
            Kind::Bool => Value::Bool(truth(v, false)),
            _ => match v {
                Value::Null => Value::Null,
                Value::Str(s) if s.len() <= MAX_TEXT => v.clone(),
                Value::Str(_) => Value::Null,
                v => bounded_text(v).map_or(Value::Null, Value::Str),
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
                self.params_rev += 1;
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
    fn unwired(&mut self) {
        self.unwired = true;
    }

    fn start(&mut self, io: &Io) {
        // a variable (and a constant) sends at start
        if matches!(
            self.kind,
            Kind::Number | Kind::Text | Kind::Bool | Kind::Constant | Kind::TableVar
        ) {
            (io.inject)(
                "__start",
                Msg::new(Value::Null, Quality::Good, now_us()).at_start(),
            );
        // a pure block with no wired input calculates once from its constants, and `now`
        // with a clock gives the time at once: made of constants, so they run no command
        // (spec 06 0.2.30)
        } else if (pure(self.kind) && self.unwired)
            || (self.kind == Kind::Date(date::Op::Now) && self.now_every().is_some())
        {
            (io.inject)(
                "__start",
                Msg::new(Value::Null, Quality::Good, now_us()).of_constants(),
            );
        }
    }

    fn input(&mut self, port: &str, m: Msg, _io: &Io, out: &mut Out) {
        let name = match port {
            "__start" => {
                self.born = true;
                self.calculate("", out);
                return;
            }
            "in" | "reset" | "trigger" | "next" | "previous" | "condition" | "right" | "first"
            | "last" => port,
            p => match p.strip_prefix("in.") {
                Some(n) => n,
                None => return,
            },
        };
        // `op` takes only an operator the block knows: another text is ignored (spec 06 0.2.20)
        if name == "op" && Ops::has(self.kind) {
            match &*m.v {
                Value::Str(o) if self.ops.set(self.kind, o).is_ok() => {}
                _ => return,
            }
        }
        // a number that is not finite never becomes a parameter: the last good value stays
        let is_param = port.starts_with("in.") && self.param_ports.contains(&name);
        if is_param && matches!(&*m.v, Value::Float(x) if !x.is_finite()) {
            return;
        }
        // `now` takes only an `interval_ms` it can keep: another value is ignored
        if is_param && self.kind == Kind::Date(date::Op::Now) && !now_interval_ok(&m.v) {
            return;
        }
        put(&mut self.seen, name, (m.q, m.t));
        self.born = m.start;
        if is_param {
            // a parameter keeps a value of its own: a list the probe shares is copied once
            put(&mut self.params, name, m.v.into_value());
            self.params_rev += 1;
        } else {
            put(&mut self.values, name, m.v);
        }
        self.calculate(name, out);
    }

    fn tick_every(&self) -> Option<Duration> {
        match self.kind {
            Kind::Stopwatch => Some(STOPWATCH_TICK),
            // a clock only while a value waits: a quarter of `ms`, 5 to 50 ms
            Kind::Debounce | Kind::Throttle if self.held.is_some() => {
                Some((self.hold() / 4).clamp(Duration::from_millis(5), Duration::from_millis(50)))
            }
            // a relative range rolls over with the clock (ADR 0044 §3)
            Kind::Date(date::Op::Range) if self.range_is_relative() => Some(RANGE_TICK),
            Kind::Date(date::Op::Now) => self.now_every(),
            _ => None,
        }
    }

    /// `now` gave its time at start already (made of constants): its clock ticks first one
    /// period later, and those ticks are ordinary samples, as a `timer`'s.
    fn first_tick_now(&self) -> bool {
        self.kind != Kind::Date(date::Op::Now)
    }

    fn tick(&mut self, now: u64, out: &mut Out) {
        if self.kind == Kind::Date(date::Op::Now) {
            self.born = false;
            self.calculate("__tick", out);
            return;
        }
        if self.kind == Kind::Date(date::Op::Range) {
            let (q, _) = self.quality();
            self.date_range("__tick", q, now, out);
            return;
        }
        if matches!(self.kind, Kind::Debounce | Kind::Throttle) {
            if self.due.is_some_and(|d| tokio::time::Instant::now() >= d) {
                self.due = None;
                if let Some(v) = self.held.take() {
                    self.passed = Some(tokio::time::Instant::now());
                    let (q, _) = self.quality();
                    self.send("out", v, q, now, out);
                }
            }
            return;
        }
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
        matches!(self.kind, Kind::Stopwatch | Kind::Counter | Kind::Toggle)
            .then(|| self.count.map(N::value))
            .flatten()
    }

    fn restore(&mut self, st: &Value) {
        if matches!(self.kind, Kind::Stopwatch | Kind::Counter | Kind::Toggle) {
            self.count = num(st);
        }
    }

    fn live_params(&self) -> Option<(u64, &BTreeMap<String, Value>)> {
        Some((self.params_rev, &self.params))
    }

    fn seeds(&self) -> Vec<(String, Value)> {
        self.consts
            .iter()
            .map(|(n, v)| {
                let port = if n == "in" {
                    n.clone()
                } else {
                    format!("in.{n}")
                };
                (port, v.clone())
            })
            .collect()
    }
}

#[cfg(test)]
mod ops_tests {
    use super::*;

    #[test]
    fn an_operator_is_decoded_once_and_an_unknown_one_is_refused() {
        let cfg = |op: Value| Map::from([("op".to_owned(), op)]);
        // no `op`: the spec's default
        let ops = Ops::of_config(Kind::If, &Map::new()).unwrap();
        assert_eq!((ops.if_op, ops.case_op), (IfOp::Eq, CaseOp::Eq));
        assert_eq!(
            Ops::of_config(Kind::If, &cfg("and".into())).unwrap().if_op,
            IfOp::And
        );
        assert_eq!(
            Ops::of_config(Kind::Router, &cfg("regexp".into()))
                .unwrap()
                .case_op,
            CaseOp::Regexp
        );
        // an operator of the other block, a wrong case and a wrong type do not compile
        for (k, bad) in [
            (Kind::If, Value::from("regexp")),
            (Kind::Case, "and".into()),
            (Kind::Case, "Contains".into()),
            (Kind::If, "".into()),
            (Kind::If, Value::UInt(1)),
        ] {
            let e = Ops::of_config(k, &cfg(bad.clone())).unwrap_err();
            assert!(
                matches!(e, ConfigError::Op(_) | ConfigError::OpNotText),
                "{bad:?}: {e:?}"
            );
            assert!(e.to_string().starts_with("op: "), "{bad:?}: {e}");
        }
        // a sample with an unknown operator changes nothing; a known one is taken
        let mut ops = Ops::of_config(Kind::Case, &cfg(">".into())).unwrap();
        assert!(ops.set(Kind::Case, "and").is_err());
        assert_eq!(ops.case_op, CaseOp::Gt);
        ops.set(Kind::Case, "<=").unwrap();
        assert_eq!(ops.case_op, CaseOp::Le);
    }
}
