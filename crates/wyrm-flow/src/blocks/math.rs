//! Math, rounding, number formatting, trigonometry, statistics and constants of the third set
//! of blocks (ADR 0044). Pure functions over a [`View`]; `blocks.rs` sends what they give.

use super::{fixed, num, param, Outs, Param, Shape, View, MAX_LIST, N};
use crate::nodes::PortType::{self, *};
use std::collections::BTreeMap;
use wyrm_core::Value;

/// π/180 and 180/π written out, so degrees are `57.29577951308232 * asin(x)` to the last digit.
const DEG: f64 = 0.017_453_292_519_943_295;
const RAD: f64 = 57.295_779_513_082_32;

/// A one-input math block.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum Op {
    Factorial,
    Log,
    Power,
    Root,
    Bound,
    RoundUp,
    RoundDown,
    FormatNumber,
    ParseNumber,
    Sin,
    Cos,
    Tan,
    Cot,
    Asin,
    Acos,
    Atan,
    ToDegrees,
    ToRadians,
}

pub(super) const OPS: &[(&str, Op)] = &[
    ("factorial", Op::Factorial),
    ("log", Op::Log),
    ("power", Op::Power),
    ("root", Op::Root),
    ("bound", Op::Bound),
    ("round_up", Op::RoundUp),
    ("round_down", Op::RoundDown),
    ("format_number", Op::FormatNumber),
    ("parse_number", Op::ParseNumber),
    ("sin", Op::Sin),
    ("cos", Op::Cos),
    ("tan", Op::Tan),
    ("cot", Op::Cot),
    ("asin", Op::Asin),
    ("acos", Op::Acos),
    ("atan", Op::Atan),
    ("to_degrees", Op::ToDegrees),
    ("to_radians", Op::ToRadians),
];

/// A block over its variable inputs: statistics.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum Stat {
    Average,
    Median,
    Mode,
    StdDeviation,
    Variance,
}

pub(super) const STATS: &[(&str, Stat)] = &[
    ("average", Stat::Average),
    ("median", Stat::Median),
    ("mode", Stat::Mode),
    ("std_deviation", Stat::StdDeviation),
    ("variance", Stat::Variance),
];

/// The named numbers of `constant`.
pub const CONSTANTS: &[(&str, f64)] = &[
    ("pi", std::f64::consts::PI),
    ("e", std::f64::consts::E),
    ("sqrt2", std::f64::consts::SQRT_2),
    ("ln2", std::f64::consts::LN_2),
    ("ln10", std::f64::consts::LN_10),
    ("log2e", std::f64::consts::LOG2_E),
    ("log10e", std::f64::consts::LOG10_E),
];

/// The default pattern of `format_number`: grouped, up to three places.
pub const DEFAULT_FORMAT: &str = "#,##0.###";
/// The longest pattern and separator `format_number` takes, bytes.
const MAX_PATTERN: usize = 64;
const MAX_SEPARATOR: usize = 8;

fn one_in(params: Vec<Param>, outputs: &'static [(&'static str, PortType)]) -> Shape {
    Shape {
        inputs: &["in"],
        params,
        items: false,
        outputs,
    }
}

pub(super) fn shape(op: Op) -> Shape {
    let s = |v: &str| Value::Str(v.to_owned());
    match op {
        Op::Log => one_in(
            vec![param("base", Value::Int(10), true)],
            &[("out", Number)],
        ),
        Op::Power => one_in(
            vec![param("exponent", Value::Int(2), true)],
            &[("out", Number)],
        ),
        Op::Root => one_in(
            vec![param("degree", Value::Int(2), true)],
            &[("out", Number)],
        ),
        Op::Bound => one_in(
            vec![
                param("min", Value::Null, true),
                param("max", Value::Null, true),
            ],
            &[("out", Number), ("input_out_of_range", Bool)],
        ),
        Op::RoundUp | Op::RoundDown => one_in(
            vec![param("precision", Value::Int(0), true)],
            &[("out", Number), ("text", Any)],
        ),
        Op::FormatNumber => one_in(
            vec![
                param("format", s(DEFAULT_FORMAT), true),
                param("decimal_separator", s("."), true),
                param("group_separator", s(","), true),
            ],
            &[("out", Any)],
        ),
        Op::Atan => one_in(vec![param("x", Value::Int(1), true)], &[("out", Number)]),
        Op::ParseNumber => one_in(vec![], &[("out", Number)]),
        _ => one_in(vec![], &[("out", Number)]),
    }
}

pub(super) fn stat_shape() -> Shape {
    Shape {
        inputs: &[],
        params: vec![],
        items: true,
        outputs: &[("out", Any)],
    }
}

pub(super) fn constant_shape() -> Shape {
    Shape {
        inputs: &[],
        params: vec![param("name", Value::Str("pi".into()), true)],
        items: false,
        outputs: &[("out", Number)],
    }
}

/// A float as a value: `null` when it is not finite.
fn fl(x: f64) -> Value {
    N::F(x).value()
}

/// A whole float as an integer while it is exact, else as a float.
fn whole_or_float(x: f64) -> Value {
    if x.is_finite() && x.fract() == 0.0 && x.abs() < 9.0e15 {
        Value::Int(x as i64)
    } else {
        fl(x)
    }
}

fn number(v: &Value) -> Option<f64> {
    num(v).map(N::f)
}

/// Places for the rounding blocks: 0 to 20 (not a number or below 0: 0).
fn places(v: &Value) -> i32 {
    number(v).map_or(0, |p| p.clamp(0.0, 20.0) as i32)
}

pub(super) fn constant(name: &Value) -> Value {
    match name {
        Value::Str(n) => CONSTANTS
            .iter()
            .find(|(c, _)| c == n)
            .map_or(Value::Null, |(_, x)| Value::Float(*x)),
        _ => Value::Null,
    }
}

pub(super) fn calc(op: Op, v: &View) -> Outs {
    let x = number(v.inv);
    let out = |val: Value| vec![("out", val, false)];
    match op {
        Op::Factorial => out(x.map_or(Value::Null, factorial)),
        Op::Log => {
            let base = number(v.p("base")).unwrap_or(10.0);
            out(x.map_or(Value::Null, |x| fl(x.ln() / base.ln())))
        }
        Op::Power => {
            let e = number(v.p("exponent"));
            out(match (num(v.inv), e) {
                (Some(N::I(a)), Some(e)) if e.fract() == 0.0 && (0.0..64.0).contains(&e) => a
                    .checked_pow(e as u32)
                    .map_or_else(|| fl((a as f64).powf(e)), Value::Int),
                (Some(a), Some(e)) => fl(a.f().powf(e)),
                _ => Value::Null,
            })
        }
        Op::Root => {
            let d = number(v.p("degree")).unwrap_or(2.0);
            out(x.map_or(Value::Null, |x| root(x, d)))
        }
        Op::Bound => {
            let (lo, hi) = (num(v.p("min")), num(v.p("max")));
            match num(v.inv) {
                None => vec![
                    ("input_out_of_range", Value::Null, false),
                    ("out", Value::Null, false),
                ],
                Some(n) => {
                    let f = n.f();
                    let oor = lo.is_some_and(|l| f < l.f()) || hi.is_some_and(|h| f > h.f());
                    // max applies first, then min: min above max gives min
                    let mut y = n;
                    if let Some(h) = hi.filter(|h| y.f() > h.f()) {
                        y = h;
                    }
                    if let Some(l) = lo.filter(|l| y.f() < l.f()) {
                        y = l;
                    }
                    vec![
                        ("input_out_of_range", Value::Bool(oor), false),
                        ("out", y.value(), false),
                    ]
                }
            }
        }
        Op::RoundUp | Op::RoundDown => {
            let p = places(v.p("precision"));
            let up = op == Op::RoundUp;
            match x {
                None => vec![("out", Value::Null, false), ("text", Value::Null, false)],
                Some(x) => {
                    let f = 10f64.powi(p);
                    let r = if up {
                        (x * f).ceil() / f
                    } else {
                        (x * f).floor() / f
                    };
                    let val = if p == 0 { whole_or_float(r) } else { fl(r) };
                    let text = if r.is_finite() {
                        Value::Str(fixed(r, p, p))
                    } else {
                        Value::Null
                    };
                    vec![("out", val, false), ("text", text, false)]
                }
            }
        }
        Op::FormatNumber => {
            let text = |n: &str, d: &str| match v.p(n) {
                Value::Null => Some(d.to_owned()),
                Value::Str(s) => Some(s.clone()),
                other => Some(super::text(other)),
            };
            let pat = text("format", DEFAULT_FORMAT)
                .filter(|p| !p.is_empty())
                .unwrap_or_else(|| DEFAULT_FORMAT.into());
            let dec = text("decimal_separator", ".").unwrap_or_default();
            let grp = text("group_separator", ",").unwrap_or_default();
            let r = match x {
                Some(x)
                    if pat.len() <= MAX_PATTERN
                        && dec.len() <= MAX_SEPARATOR
                        && grp.len() <= MAX_SEPARATOR =>
                {
                    format_number(x, &pat, &dec, &grp).map_or(Value::Null, Value::Str)
                }
                _ => Value::Null,
            };
            out(r)
        }
        Op::ParseNumber => out(parse_number(v.inv)),
        Op::Sin => out(x.map_or(Value::Null, |x| fl((DEG * x).sin()))),
        Op::Cos => out(x.map_or(Value::Null, |x| fl((DEG * x).cos()))),
        Op::Tan => out(x.map_or(Value::Null, |x| fl((DEG * x).tan()))),
        Op::Cot => out(x.map_or(Value::Null, |x| fl(1.0 / (DEG * x).tan()))),
        Op::Asin => out(x.map_or(Value::Null, |x| fl(RAD * x.asin()))),
        Op::Acos => out(x.map_or(Value::Null, |x| fl(RAD * x.acos()))),
        Op::Atan => {
            let px = number(v.p("x")).unwrap_or(1.0);
            out(x.map_or(Value::Null, |y| fl(RAD * y.atan2(px))))
        }
        Op::ToDegrees => out(x.map_or(Value::Null, |x| fl(RAD * x))),
        Op::ToRadians => out(x.map_or(Value::Null, |x| fl(DEG * x))),
    }
}

/// `n!` of the whole part of `x` (below 1: 1). An integer up to 20!, a float up to 170!, then
/// `null` (not finite).
pub(super) fn factorial(x: f64) -> Value {
    let n = x.trunc();
    if n > 170.0 {
        return Value::Null;
    }
    let mut i: i64 = 1;
    let mut f: f64 = 1.0;
    let mut k = 2.0;
    let mut exact = true;
    while k <= n {
        if exact {
            match i.checked_mul(k as i64) {
                Some(j) => i = j,
                None => exact = false,
            }
        }
        f *= k;
        k += 1.0;
    }
    if exact {
        Value::Int(i)
    } else {
        fl(f)
    }
}

/// The `d`-th root of `x`; a negative `x` has a root for an odd whole `d` (−8, 3: −2).
pub(super) fn root(x: f64, d: f64) -> Value {
    if d == 0.0 {
        return Value::Null;
    }
    if x < 0.0 && d.fract() == 0.0 && (d as i64) % 2 != 0 {
        return fl(-(-x).powf(1.0 / d));
    }
    let r = x.powf(1.0 / d);
    let rounded = r.round();
    // an exact root stays a whole number (27, 3: 3, not 3.0000000000000004)
    if (rounded.powf(d) - x).abs() < f64::EPSILON * x.abs().max(1.0) {
        whole_or_float(rounded)
    } else {
        fl(r)
    }
}

/// `x` by an ICU-like pattern: optional text before and after one number part of `#`, `0`,
/// `,` and `.`; `0` is a digit always shown, `#` one shown when it is not a leading or a
/// trailing zero, `,` sets the group size (digits after the last one), `%` in the text
/// multiplies by 100. `None`: the pattern has no number part.
pub(super) fn format_number(x: f64, pat: &str, dec: &str, grp: &str) -> Option<String> {
    let is_num = |c: char| matches!(c, '#' | '0' | ',' | '.');
    let start = pat.find(is_num)?;
    let len = pat[start..]
        .find(|c: char| !is_num(c))
        .unwrap_or(pat.len() - start);
    let (prefix, body, suffix) = (&pat[..start], &pat[start..start + len], &pat[start + len..]);
    let x = if prefix.contains('%') || suffix.contains('%') {
        x * 100.0
    } else {
        x
    };
    let (int_pat, frac_pat) = match body.find('.') {
        Some(i) => (&body[..i], body[i + 1..].replace([',', '.'], "")),
        None => (body, String::new()),
    };
    let min_int = int_pat.chars().filter(|c| *c == '0').count();
    let group = int_pat.rfind(',').map_or(0, |i| {
        int_pat[i + 1..].chars().filter(|c| *c != ',').count()
    });
    let min_frac = frac_pat.chars().filter(|c| *c == '0').count();
    let max_frac = frac_pat.len().min(20);
    let s = format!("{:.*}", max_frac, x.abs());
    let (int_s, frac_s) = match s.find('.') {
        Some(i) => (s[..i].to_owned(), s[i + 1..].to_owned()),
        None => (s, String::new()),
    };
    let mut frac_s = frac_s;
    while frac_s.len() > min_frac && frac_s.ends_with('0') {
        frac_s.pop();
    }
    let mut digits = int_s.trim_start_matches('0').to_owned();
    while digits.len() < min_int {
        digits.insert(0, '0');
    }
    let mut int_out = String::new();
    for (i, c) in digits.chars().enumerate() {
        let left = digits.len() - i;
        if i > 0 && group > 0 && left % group == 0 {
            int_out.push_str(grp);
        }
        int_out.push(c);
    }
    let negative =
        x < 0.0 && (digits.chars().any(|c| c != '0') || frac_s.chars().any(|c| c != '0'));
    let mut out = String::new();
    out.push_str(prefix);
    if negative {
        out.push('-');
    }
    out.push_str(&int_out);
    if !frac_s.is_empty() {
        out.push_str(dec);
        out.push_str(&frac_s);
    }
    out.push_str(suffix);
    Some(out)
}

/// The first number in a text: `#ff` and `0xff` are hexadecimal, else the first run of digits,
/// points and commas (commas dropped) with an optional exponent. A number is passed as it is.
pub(super) fn parse_number(v: &Value) -> Value {
    let s = match v {
        Value::Str(s) => s.trim(),
        Value::Int(_) | Value::UInt(_) | Value::Float(_) => {
            return num(v).map_or(Value::Null, N::value)
        }
        _ => return Value::Null,
    };
    if s.len() > super::MAX_TEXT {
        return Value::Null;
    }
    let hex = |h: &str, neg: bool| {
        (!h.is_empty() && h.len() <= 15 && h.chars().all(|c| c.is_ascii_hexdigit()))
            .then(|| i64::from_str_radix(h, 16).ok())
            .flatten()
            .map_or(Value::Null, |n| Value::Int(if neg { -n } else { n }))
    };
    if let Some(h) = s.strip_prefix('#') {
        return hex(h, false);
    }
    if let Some(h) = s.strip_prefix("0x").or_else(|| s.strip_prefix("0X")) {
        return hex(h, false);
    }
    if let Some(h) = s.strip_prefix("-0x") {
        return hex(h, true);
    }
    let b = s.as_bytes();
    let numch = |c: u8| c.is_ascii_digit() || c == b'.' || c == b',';
    let Some(start) = (0..b.len())
        .find(|&i| numch(b[i]) || (b[i] == b'-' && b.get(i + 1).is_some_and(|c| numch(*c))))
    else {
        return Value::Null;
    };
    let mut end = start + usize::from(b[start] == b'-');
    while end < b.len() && numch(b[end]) {
        end += 1;
    }
    // an exponent: [Ee]-?[0-9.-]+
    if end < b.len() && (b[end] == b'e' || b[end] == b'E') {
        let mut k = end + 1;
        if k < b.len() && b[k] == b'-' {
            k += 1;
        }
        let digits = k;
        while k < b.len() && (b[k].is_ascii_digit() || b[k] == b'.' || b[k] == b'-') {
            k += 1;
        }
        if k > digits {
            end = k;
        }
    }
    let t: String = s[start..end].chars().filter(|c| *c != ',').collect();
    t.parse::<i64>()
        .map(Value::Int)
        .ok()
        .or_else(|| t.parse::<f64>().ok().map(fl))
        .unwrap_or(Value::Null)
}

/// The numbers of the variable inputs; an input that holds a list gives its numbers (at most
/// [`MAX_LIST`] in all).
fn numbers(items: &[Value]) -> Vec<N> {
    let mut out = Vec::new();
    for v in items {
        match v {
            Value::Array(a) => out.extend(a.iter().filter_map(num)),
            v => out.extend(num(v)),
        }
        if out.len() >= MAX_LIST {
            out.truncate(MAX_LIST);
            break;
        }
    }
    out
}

pub(super) fn stat(s: Stat, items: &[Value]) -> Value {
    if s == Stat::Mode {
        return mode(items);
    }
    let xs: Vec<f64> = numbers(items).into_iter().map(N::f).collect();
    let n = xs.len();
    if n == 0 {
        return Value::Null;
    }
    let mean = xs.iter().sum::<f64>() / n as f64;
    match s {
        Stat::Average => fl(mean),
        Stat::Median => {
            let mut ns = numbers(items);
            ns.sort_by(|a, b| a.f().total_cmp(&b.f()));
            if n % 2 == 1 {
                ns[n / 2].value()
            } else {
                let (a, b) = (ns[n / 2 - 1].f(), ns[n / 2].f());
                whole_or_float(a / 2.0 + b / 2.0)
            }
        }
        Stat::Variance | Stat::StdDeviation => {
            let var = xs.iter().map(|x| (x - mean) * (x - mean)).sum::<f64>() / n as f64;
            fl(if s == Stat::Variance { var } else { var.sqrt() })
        }
        Stat::Mode => unreachable!("handled above"),
    }
}

/// The most frequent scalar (compared as text); `null` and empty text are left out; on a tie,
/// the value that first reached the top count.
fn mode(items: &[Value]) -> Value {
    let mut counts: BTreeMap<String, usize> = BTreeMap::new();
    let (mut best, mut best_n) = (Value::Null, 0);
    let mut seen = 0;
    let flat = items.iter().flat_map(|v| match v {
        Value::Array(a) => a.iter().collect::<Vec<_>>(),
        v => vec![v],
    });
    for v in flat {
        seen += 1;
        if seen > MAX_LIST {
            break;
        }
        let Some(key) = super::bounded_text(v).filter(|k| !k.is_empty()) else {
            continue;
        };
        // scalars only: a list or a map is no value to count (and a deep one no output)
        if matches!(
            v,
            Value::Null | Value::Array(_) | Value::Map(_) | Value::Bytes(_)
        ) {
            continue;
        }
        let c = counts.entry(key).or_insert(0);
        *c += 1;
        if *c > best_n {
            best_n = *c;
            best = v.clone();
        }
    }
    best
}

#[cfg(test)]
mod tests {
    use super::*;

    fn view<'a>(inv: &'a Value, params: &'a BTreeMap<String, Value>) -> View<'a> {
        View {
            inv,
            params,
            items: Vec::new(),
            now_us: 0,
            ins: &super::super::NO_INPUTS,
        }
    }

    fn run(op: Op, x: Value, kv: &[(&str, Value)]) -> Vec<(&'static str, Value)> {
        let params: BTreeMap<String, Value> = shape(op)
            .params
            .into_iter()
            .map(|p| (p.name.to_owned(), p.default))
            .chain(kv.iter().map(|(k, v)| ((*k).to_owned(), v.clone())))
            .collect();
        calc(op, &view(&x, &params))
            .into_iter()
            .map(|(p, v, _)| (p, v))
            .collect()
    }

    fn out(op: Op, x: Value, kv: &[(&str, Value)]) -> Value {
        run(op, x, kv)
            .into_iter()
            .find(|(p, _)| *p == "out")
            .unwrap()
            .1
    }

    fn close(v: Value, want: f64) {
        let got = v.as_f64().unwrap_or_else(|| panic!("{v:?} is no number"));
        assert!((got - want).abs() < 1e-9, "{got} ≠ {want}");
    }

    #[test]
    fn math_cases_of_the_reference() {
        assert_eq!(out(Op::Factorial, Value::Int(5), &[]), Value::Int(120));
        assert_eq!(out(Op::Factorial, Value::Float(4.9), &[]), Value::Int(24));
        assert_eq!(out(Op::Factorial, Value::Int(-3), &[]), Value::Int(1));
        assert_eq!(out(Op::Factorial, Value::Int(0), &[]), Value::Int(1));
        assert!(matches!(
            out(Op::Factorial, Value::Int(25), &[]),
            Value::Float(_)
        ));
        assert_eq!(out(Op::Factorial, Value::Int(171), &[]), Value::Null);
        close(out(Op::Log, Value::Int(100), &[]), 2.0);
        close(out(Op::Log, Value::Int(8), &[("base", Value::Int(2))]), 3.0);
        assert_eq!(
            out(Op::Log, Value::Int(0), &[]),
            Value::Null,
            "-inf is no number"
        );
        assert_eq!(out(Op::Log, Value::Int(-1), &[]), Value::Null);
        assert_eq!(
            out(Op::Power, Value::Int(2), &[("exponent", Value::Int(10))]),
            Value::Int(1024)
        );
        close(
            out(Op::Power, Value::Int(4), &[("exponent", Value::Float(0.5))]),
            2.0,
        );
        assert!(matches!(
            out(Op::Power, Value::Int(10), &[("exponent", Value::Int(30))]),
            Value::Float(_)
        ));
        assert_eq!(
            out(Op::Root, Value::Int(27), &[("degree", Value::Int(3))]),
            Value::Int(3)
        );
        assert_eq!(
            out(Op::Root, Value::Int(-8), &[("degree", Value::Int(3))]),
            Value::Float(-2.0)
        );
        assert_eq!(out(Op::Root, Value::Int(-4), &[]), Value::Null);
        assert_eq!(
            out(Op::Root, Value::Int(4), &[("degree", Value::Int(0))]),
            Value::Null
        );
        close(out(Op::Root, Value::Int(2), &[]), std::f64::consts::SQRT_2);
    }

    #[test]
    fn bound_applies_max_then_min() {
        let r = run(
            Op::Bound,
            Value::Int(15),
            &[("min", Value::Int(0)), ("max", Value::Int(10))],
        );
        assert_eq!(
            r,
            vec![
                ("input_out_of_range", Value::Bool(true)),
                ("out", Value::Int(10))
            ]
        );
        let r = run(
            Op::Bound,
            Value::Int(5),
            &[("min", Value::Int(0)), ("max", Value::Int(10))],
        );
        assert_eq!(r[1].1, Value::Int(5));
        assert_eq!(r[0].1, Value::Bool(false));
        // min above max: min
        let r = run(
            Op::Bound,
            Value::Int(5),
            &[("min", Value::Int(8)), ("max", Value::Int(2))],
        );
        assert_eq!(r[1].1, Value::Int(8));
        // a side without a number does not apply
        let r = run(Op::Bound, Value::Float(-2.5), &[("max", Value::Int(1))]);
        assert_eq!(r[1].1, Value::Float(-2.5));
        let r = run(Op::Bound, Value::Null, &[]);
        assert_eq!(r[1].1, Value::Null);
    }

    #[test]
    fn rounding_up_and_down() {
        let r = run(
            Op::RoundUp,
            Value::Float(1.21),
            &[("precision", Value::Int(1))],
        );
        assert_eq!(r, vec![("out", Value::Float(1.3)), ("text", "1.3".into())]);
        let r = run(
            Op::RoundDown,
            Value::Float(1.29),
            &[("precision", Value::Int(1))],
        );
        assert_eq!(r, vec![("out", Value::Float(1.2)), ("text", "1.2".into())]);
        assert_eq!(out(Op::RoundUp, Value::Float(2.1), &[]), Value::Int(3));
        assert_eq!(out(Op::RoundDown, Value::Float(-2.1), &[]), Value::Int(-3));
        assert_eq!(
            out(
                Op::RoundUp,
                Value::Float(1e300),
                &[("precision", Value::Int(20))]
            ),
            Value::Null
        );
    }

    #[test]
    fn number_formats() {
        let f = |x, p| format_number(x, p, ".", ",").unwrap();
        assert_eq!(f(1234.5, "#,##0.00"), "1,234.50");
        assert_eq!(f(1234.5, DEFAULT_FORMAT), "1,234.5");
        assert_eq!(f(1050.4, "#,###.00"), "1,050.40");
        assert_eq!(f(0.5, "#.##"), ".5");
        assert_eq!(f(0.5, "0.00"), "0.50");
        assert_eq!(f(7.0, "000"), "007");
        assert_eq!(f(-1234567.0, "#,##0"), "-1,234,567");
        assert_eq!(f(-0.001, "0.00"), "0.00", "no minus on a zero");
        assert_eq!(f(0.256, "0.0%"), "25.6%");
        assert_eq!(f(12.0, "€ #,##0.00"), "€ 12.00");
        assert_eq!(
            format_number(1234.5, "#,##0.00", ",", " ").unwrap(),
            "1 234,50"
        );
        assert_eq!(format_number(1234.5, "#,##0", ",", "").unwrap(), "1234");
        assert_eq!(format_number(1.0, "abc", ".", ","), None);
        assert_eq!(f(1e300, "#,##0").len(), 301 + 100);
    }

    #[test]
    fn number_parses() {
        let p = |s: &str| parse_number(&Value::from(s));
        assert_eq!(p("abc12.5kg"), Value::Float(12.5));
        assert_eq!(p("1,234.5"), Value::Float(1234.5));
        assert_eq!(p("1.2.3"), Value::Null);
        assert_eq!(p(""), Value::Null);
        assert_eq!(p("-7 °C"), Value::Int(-7));
        assert_eq!(p("x 2e3 y"), Value::Float(2000.0));
        assert_eq!(p("#ff"), Value::Int(255));
        assert_eq!(p("0x1F"), Value::Int(31));
        assert_eq!(p("#zz"), Value::Null);
        assert_eq!(parse_number(&Value::Int(4)), Value::Int(4));
        assert_eq!(parse_number(&Value::Bool(true)), Value::Null);
        assert_eq!(p("no digits"), Value::Null);
    }

    #[test]
    fn trigonometry_in_degrees() {
        close(out(Op::Sin, Value::Int(90), &[]), 1.0);
        close(out(Op::Cos, Value::Int(0), &[]), 1.0);
        close(out(Op::Tan, Value::Int(45), &[]), 1.0);
        close(out(Op::Cot, Value::Int(45), &[]), 1.0);
        assert_eq!(out(Op::Cot, Value::Int(0), &[]), Value::Null, "infinite");
        close(out(Op::Asin, Value::Int(1), &[]), 90.0);
        close(out(Op::Acos, Value::Int(1), &[]), 0.0);
        close(out(Op::Atan, Value::Int(1), &[]), 45.0);
        close(
            out(Op::Atan, Value::Int(1), &[("x", Value::Int(-1))]),
            135.0,
        );
        assert_eq!(out(Op::Asin, Value::Int(2), &[]), Value::Null);
        close(
            out(Op::ToRadians, Value::Int(180), &[]),
            std::f64::consts::PI,
        );
        close(
            out(Op::ToDegrees, Value::Float(std::f64::consts::PI), &[]),
            180.0,
        );
        // degrees are `57.29577951308232 * asin(x)`, to the last digit
        assert_eq!(
            out(Op::Asin, Value::Float(0.5), &[]),
            Value::Float(57.29577951308232 * 0.5f64.asin())
        );
        assert_eq!(
            out(Op::Cos, Value::Int(90), &[]),
            Value::Float((0.017453292519943295f64 * 90.0).cos())
        );
    }

    #[test]
    fn statistics() {
        let ints = |a: &[i64]| a.iter().map(|i| Value::Int(*i)).collect::<Vec<_>>();
        close(stat(Stat::Average, &ints(&[2, 4, 9])), 5.0);
        assert_eq!(stat(Stat::Median, &ints(&[3, 1, 2])), Value::Int(2));
        assert_eq!(stat(Stat::Median, &ints(&[4, 1, 2, 3])), Value::Float(2.5));
        assert_eq!(stat(Stat::Median, &ints(&[4, 6])), Value::Int(5));
        close(stat(Stat::Variance, &ints(&[2, 4, 4, 4, 5, 5, 7, 9])), 4.0);
        close(
            stat(Stat::StdDeviation, &ints(&[2, 4, 4, 4, 5, 5, 7, 9])),
            2.0,
        );
        assert_eq!(stat(Stat::Mode, &ints(&[1, 2, 2])), Value::Int(2));
        assert_eq!(
            stat(Stat::Mode, &ints(&[1, 2])),
            Value::Int(1),
            "a tie: the first"
        );
        assert_eq!(
            stat(
                Stat::Mode,
                &[Value::Null, "".into(), "a".into(), "a".into()]
            ),
            Value::from("a")
        );
        assert_eq!(stat(Stat::Average, &[Value::Null, "x".into()]), Value::Null);
        // a list on an input gives its numbers
        assert_eq!(
            stat(Stat::Median, &[Value::Array(ints(&[5, 1, 9])), Value::Null]),
            Value::Int(5)
        );
        let big = vec![Value::Float(f64::MAX); 4];
        assert_eq!(
            stat(Stat::Average, &big),
            Value::Null,
            "an overflow is no number"
        );
    }

    #[test]
    fn constants() {
        assert_eq!(constant(&"pi".into()), Value::Float(std::f64::consts::PI));
        assert_eq!(
            constant(&"log10e".into()),
            Value::Float(std::f64::consts::LOG10_E)
        );
        assert_eq!(constant(&"nan".into()), Value::Null);
        assert_eq!(constant(&Value::Int(1)), Value::Null);
    }
}
