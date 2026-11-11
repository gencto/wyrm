//! Catalog entries of the third set of blocks (ADR 0044, `docs/flow-blocks.md`), in the
//! palette's order after the first sets.

use crate::catalog::{db, di, dp, ds, p, pick, NodeType, Param, INPUTS, ITEMS};

/// A block with the input `in`, its parameters and `out`.
const fn unary(
    ty: &'static str,
    category: &'static str,
    description: &'static str,
    inputs: &'static [&'static str],
    outputs: &'static [&'static str],
    params: &'static [Param],
) -> NodeType {
    NodeType {
        ty,
        category,
        description,
        inputs,
        outputs,
        dyn_inputs: None,
        dyn_outputs: None,
        params,
    }
}

/// A one-number function of `in`, in degrees where it is an angle.
const fn trig(ty: &'static str, description: &'static str) -> NodeType {
    unary(ty, "Trigonometry", description, &["in"], &["out"], &[])
}

/// A statistic over the variable inputs.
const fn stat(ty: &'static str, description: &'static str) -> NodeType {
    NodeType {
        ty,
        category: "Statistics",
        description,
        inputs: &[],
        outputs: &["out"],
        dyn_inputs: Some(ITEMS),
        dyn_outputs: None,
        params: &[INPUTS],
    }
}

const PRECISION: Param = di(
    p(
        "precision",
        "number",
        "Places after the point, 0…20 (default 0: an integer).",
    ),
    0,
);

pub const TYPES: &[NodeType] = &[
    // ---------- math, rounding, formatting (ADR 0044 §1) ----------
    NodeType {
        ty: "constant",
        category: "Variables",
        description: "A mathematical constant, sent at start.",
        inputs: &["in.name"],
        outputs: &["out"],
        dyn_inputs: None,
        dyn_outputs: None,
        params: &[pick(
            p("name", "string", "Which constant: π, e, √2, ln 2, ln 10, log₂ e, log₁₀ e."),
            &["pi", "e", "sqrt2", "ln2", "ln10", "log2e", "log10e"],
            "pi",
        )],
    },
    unary("factorial", "Math", "n! of the whole part of in (below 1: 1; above 170: null).", &["in"], &["out"], &[]),
    unary(
        "log",
        "Math",
        "The logarithm of in to base (in at most 0: null).",
        &["in", "in.base"],
        &["out"],
        &[di(p("base", "number", "The base (default 10)."), 10)],
    ),
    unary(
        "power",
        "Math",
        "in to the power exponent.",
        &["in", "in.exponent"],
        &["out"],
        &[di(p("exponent", "number", "The exponent (default 2)."), 2)],
    ),
    unary(
        "root",
        "Math",
        "The degree-th root of in (an odd whole degree takes a negative in).",
        &["in", "in.degree"],
        &["out"],
        &[di(p("degree", "number", "Which root (default 2: the square root)."), 2)],
    ),
    unary(
        "bound",
        "Math",
        "in held inside min…max; input_out_of_range says whether it was outside.",
        &["in", "in.min", "in.max"],
        &["out", "input_out_of_range"],
        &[
            p("min", "number", "The lowest value (none: no lower bound)."),
            p("max", "number", "The highest value (none: no upper bound; min wins when it is above max)."),
        ],
    ),
    unary(
        "round_up",
        "Math",
        "in rounded up to precision places; text: the same with precision places.",
        &["in", "in.precision"],
        &["out", "text"],
        &[PRECISION],
    ),
    unary(
        "round_down",
        "Math",
        "in rounded down to precision places; text: the same with precision places.",
        &["in", "in.precision"],
        &["out", "text"],
        &[PRECISION],
    ),
    unary(
        "format_number",
        "Text",
        "in as text by a pattern: #,##0.00 (0 a digit always shown, # one shown when needed, a comma groups, % multiplies by 100).",
        &["in", "in.format", "in.decimal_separator", "in.group_separator"],
        &["out"],
        &[
            ds(p("format", "string", "The pattern, at most 64 bytes, with text before and after it (default #,##0.###)."), "#,##0.###"),
            ds(p("decimal_separator", "string", "Before the places (default a point)."), "."),
            ds(p("group_separator", "string", "Between the groups (default a comma; empty: none)."), ","),
        ],
    ),
    unary(
        "parse_number",
        "Text",
        "The first number in a text (1,234.5 kg: 1234.5; #ff and 0xff are hexadecimal).",
        &["in"],
        &["out"],
        &[],
    ),
    // ---------- trigonometry, in degrees ----------
    trig("sin", "The sine of in degrees."),
    trig("cos", "The cosine of in degrees."),
    trig("tan", "The tangent of in degrees."),
    trig("cot", "The cotangent of in degrees (at 0: null)."),
    trig("asin", "The angle in degrees whose sine is in (outside −1…1: null)."),
    trig("acos", "The angle in degrees whose cosine is in (outside −1…1: null)."),
    unary(
        "atan",
        "Trigonometry",
        "The angle in degrees of the point (x, in): with x 1, the arc tangent of in.",
        &["in", "in.x"],
        &["out"],
        &[di(dp(p("x", "number", "The point's x (default 1)."), "X"), 1)],
    ),
    trig("to_degrees", "in radians as degrees."),
    trig("to_radians", "in degrees as radians."),
    // ---------- statistics (an input that holds a list gives its numbers) ----------
    stat("average", "The mean of the numbers of the inputs (a list on an input gives its numbers)."),
    stat("median", "The middle of the numbers of the inputs (an even count: the mean of the two middles)."),
    stat("mode", "The value that occurs most often among the inputs (a tie: the first to get there)."),
    stat("std_deviation", "The population standard deviation of the numbers of the inputs."),
    stat("variance", "The population variance of the numbers of the inputs."),
    // ---------- text and codecs ----------
    unary(
        "left",
        "Text",
        "The first length characters of in as text.",
        &["in", "in.length"],
        &["out"],
        &[di(p("length", "number", "How many characters (default 0)."), 0)],
    ),
    unary(
        "right",
        "Text",
        "The last length characters of in as text.",
        &["in", "in.length"],
        &["out"],
        &[di(p("length", "number", "How many characters (default 0)."), 0)],
    ),
    unary("trim", "Text", "in as text without the spaces at its start and end (null: empty text).", &["in"], &["out"], &[]),
    unary("base64_encode", "Codecs", "A text (as UTF-8) or bytes as Base64.", &["in"], &["out"], &[]),
    unary(
        "base64_decode",
        "Codecs",
        "Base64 (standard or URL alphabet, padding optional) as text (UTF-8) and as bytes; not Base64: null.",
        &["in"],
        &["out", "bytes"],
        &[],
    ),
    unary("url_encode", "Codecs", "A text percent-encoded as a URL component (A–Z a–z 0–9 - _ . ! ~ * ' ( ) stay).", &["in"], &["out"], &[]),
    unary("url_decode", "Codecs", "A URL component decoded: + is a space, a bad % stays as it is.", &["in"], &["out"], &[]),
    unary("to_camel_case", "Codecs", "A phrase as camelCase: Hello World-foo → helloWorldFoo.", &["in"], &["out"], &[]),
    unary("from_camel_case", "Codecs", "camelCase as words: each capital X becomes a space and x.", &["in"], &["out"], &[]),
    unary(
        "hash",
        "Codecs",
        "The digest of a text (as UTF-8) or of bytes, in lower-case hex.",
        &["in", "in.algorithm"],
        &["out"],
        &[pick(p("algorithm", "string", "sha256, sha1 or md5 (a check sum, not a secret)."), &["sha256", "sha1", "md5"], "sha256")],
    ),
    unary(
        "json_parse",
        "Codecs",
        "A JSON text as a value (at most 256 KiB, 32 levels); parse_error says it was no JSON. A value that is no text passes.",
        &["in"],
        &["out", "parse_error"],
        &[],
    ),
    unary(
        "json_stringify",
        "Codecs",
        "A value as JSON text (bytes as Base64; at most 256 KiB).",
        &["in", "in.pretty"],
        &["out"],
        &[db(p("pretty", "bool", "Lines and indents (default false)."), false)],
    ),
];
