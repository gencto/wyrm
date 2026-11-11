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
    // ---------- date and time (ADR 0044 §3: microseconds since the epoch) ----------
    unary(
        "now",
        "Date and time",
        "The current time in microseconds since the epoch, on each sample of in.",
        &["in"],
        &["out"],
        &[],
    ),
    unary(
        "date_time",
        "Date and time",
        "A time from its parts in time_zone, as a calendar counts (month 13 is January of the next year).",
        &["in.year", "in.month", "in.day", "in.hour", "in.minute", "in.second", "in.millisecond", "in.time_zone"],
        &["out"],
        &[
            di(p("year", "number", "The year (default 1970)."), 1970),
            di(p("month", "number", "1…12 (default 1)."), 1),
            di(p("day", "number", "1…31 (default 1)."), 1),
            di(p("hour", "number", "0…23 (default 0)."), 0),
            di(p("minute", "number", "Default 0."), 0),
            di(p("second", "number", "Default 0."), 0),
            di(p("millisecond", "number", "Default 0."), 0),
            TIME_ZONE,
        ],
    ),
    unary(
        "date_format",
        "Date and time",
        "A time as text by a pattern: yyyy-MM-dd HH:mm:ss.SSS, MMM/MMMM and E/EEEE names, h and a, xxx the offset, 'text' quoted.",
        &["in", "in.format", "in.time_zone"],
        &["out"],
        &[
            ds(p("format", "string", "The pattern, at most 128 bytes (default yyyy-MM-dd'T'HH:mm:ss)."), "yyyy-MM-dd'T'HH:mm:ss"),
            ds(p("time_zone", "string", "Europe/Kyiv, UTC, +02:00, or auto: the offset the input text has (default UTC)."), "UTC"),
        ],
    ),
    unary(
        "date_parse",
        "Date and time",
        "A time (microseconds or text) in its parts in time_zone; weekday 1 is Monday.",
        &["in", "in.time_zone"],
        &["time", "year", "month", "day", "hour", "minute", "second", "millisecond", "weekday"],
        &[TIME_ZONE],
    ),
    unary(
        "date_math",
        "Date and time",
        "A time after or before in by the parts: years, months and days on the calendar of time_zone, the rest as elapsed time.",
        &["in", "in.op", "in.year", "in.month", "in.day", "in.hour", "in.minute", "in.second", "in.millisecond", "in.time_zone"],
        &["out"],
        &[
            pick(p("op", "string", "after adds, before subtracts."), &["after", "before"], "after"),
            di(p("year", "number", "Years (default 0)."), 0),
            di(p("month", "number", "Months; Jan 31 + 1 is the last day of February (default 0)."), 0),
            di(p("day", "number", "Calendar days (default 0)."), 0),
            di(p("hour", "number", "Hours (default 0)."), 0),
            di(p("minute", "number", "Minutes (default 0)."), 0),
            di(p("second", "number", "Seconds (default 0)."), 0),
            di(p("millisecond", "number", "Milliseconds (default 0)."), 0),
            TIME_ZONE,
        ],
    ),
    unary(
        "date_range",
        "Date and time",
        "The bounds of a range text (today, thisWeek, lastMonth, current3days, previous2hours, 2026, 2026-10, 2026-10-29, <a>/<b>) and its neighbours; next and previous move to them.",
        &["in", "next", "previous", "in.format", "in.range_delimiter", "in.keep_special", "in.week_start", "in.time_zone"],
        &["start", "end", "this_range", "next_range", "previous_range", "formatted", "duration"],
        &[
            ds(p("format", "string", "The pattern of formatted (default yyyy-MM-dd'T'HH:mm:ss; empty: the input text)."), "yyyy-MM-dd'T'HH:mm:ss"),
            ds(p("range_delimiter", "string", "Between the two ends of formatted (default /)."), "/"),
            pick(
                p("keep_special", "string", "raw: formatted is the name of a named or relative range; formatted: one end when both read the same."),
                &["none", "raw", "formatted"],
                "none",
            ),
            pick(
                p("week_start", "string", "The first day of a week (default monday)."),
                &["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"],
                "monday",
            ),
            TIME_ZONE,
        ],
    ),
];

const TIME_ZONE: Param = ds(
    p(
        "time_zone",
        "string",
        "The zone of the wall time: Europe/Kyiv, UTC, +02:00 (default UTC).",
    ),
    "UTC",
);
