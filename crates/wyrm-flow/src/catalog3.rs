//! Catalog entries of the third set of blocks (ADR 0044, `docs/flow-blocks.md`), in the
//! palette's order after the first sets.

use crate::catalog::{
    db, di, dl, dp, ds, ed, p, pick, req, sc, DynPorts, NodeType, Param, ENABLED, INPUTS,
    INTERVAL_MS, ITEMS, KEY, KEY_SCOPE,
};

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
        "The current time in microseconds since the epoch: at the start, every interval_ms, and on each sample of in (in is only a trigger: its value means nothing).",
        &["in", "in.interval_ms"],
        &["out"],
        &[di(
            p(
                "interval_ms",
                "number",
                "Gives the time at the start and every this many milliseconds (default 1000); 0: only on samples of in; else 100 … 86 400 000.",
            ),
            1000,
        )],
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
    // ---------- logic and events ----------
    NodeType {
        ty: "router",
        category: "Logic",
        description: "in goes out on out.<case> of the first case that condition matches by op, else on else.",
        inputs: &["in", "condition", "in.op", "in.single_output"],
        outputs: &["else"],
        dyn_inputs: Some(ITEMS),
        dyn_outputs: Some(DynPorts {
            param: "inputs",
            prefix: "out.",
            default: &["0", "1"],
            keys: false,
        }),
        params: &[
            pick(
                p("op", "string", "How condition is compared with each case: = != > < >= <= (as numbers), contains / starts_with / ends_with / regexp (as text)."),
                crate::blocks::CASE_OPS,
                "=",
            ),
            db(p("single_output", "bool", "When the route changes, the output routed before goes back to null (default false: each output keeps its value)."), false),
            dl(
                p("inputs", "array", "Names of the cases, [A-Za-z0-9_]+, at most 64 (default 0, 1): each is an input in.<name> (its case value, a constant in values) and an output out.<name>."),
                &["0", "1"],
            ),
        ],
    },
    NodeType {
        ty: "event_gate",
        category: "Logic",
        description: "An event once every input changed at least once since the last reset; order says in which order.",
        inputs: &["reset", "in.log_order"],
        outputs: &["on_finish", "order"],
        dyn_inputs: Some(ITEMS),
        dyn_outputs: None,
        params: &[
            pick(
                p("log_order", "string", "What order lists: none, each input at its first change, at its last change, or every change (the last 1000)."),
                &["none", "first_occurrence", "last_occurrence", "all"],
                "none",
            ),
            INPUTS,
        ],
    },
    NodeType {
        ty: "catch_error",
        category: "Logic",
        description: "The errors wired into it (the error events of readers and commands, or texts): the message, its code, which input, and an event.",
        inputs: &[],
        outputs: &["out", "code", "source", "on_error"],
        dyn_inputs: Some(ITEMS),
        dyn_outputs: None,
        params: &[INPUTS],
    },
    // ---------- readers (ADR 0044 §4) ----------
    NodeType {
        ty: "load_history",
        category: "Sources",
        description: "The historian's rows of a point in time_range as a table {t, v, q} (at most limit): at the start and when a field changes (auto_run), on trigger, every interval_ms; in.key names another point inside key_scope.",
        inputs: &[
            "trigger",
            "in.key",
            "in.interval_ms",
            "in.auto_run",
            "in.enabled",
            "in.time_range",
            "in.rollup",
            "in.window",
            "in.limit",
            "in.time_zone",
        ],
        outputs: &["out", "ok", "error", "running", "last_run"],
        dyn_inputs: None,
        dyn_outputs: None,
        params: &[
            KEY,
            KEY_SCOPE,
            INTERVAL_MS,
            db(p("auto_run", "bool", "Read at the start and when the key or a query field changes (default true)."), true),
            ENABLED,
            ds(
                p("time_range", "string", "A range text, as date_range reads it: today, lastWeek, current24hours, 2026-10, <a>/<b> (default today)."),
                "today",
            ),
            pick(
                p("rollup", "string", "With window: how the rows of one window become one (none: the raw rows)."),
                crate::readers::ROLLUPS,
                "none",
            ),
            ds(p("window", "string", "One row per window: 5m, 1h, 1d, 1w (empty: none)."), ""),
            di(p("limit", "number", "Rows at most, 1…10 000 (default 10 000; ok says truncated when the answer reached it)."), 10_000),
            TIME_ZONE,
        ],
    },
    NodeType {
        ty: "get_node",
        category: "Sources",
        description: "A node's summary {name, display, type, unit, enum, writable, is, has_children} and its actions as a table {name, display, group, level, params}: at the start and when the key changes (auto_run), on trigger, every interval_ms.",
        inputs: &["trigger", "in.key", "in.interval_ms", "in.auto_run", "in.enabled"],
        outputs: &["out", "actions", "ok", "error", "running", "last_run"],
        dyn_inputs: None,
        dyn_outputs: None,
        params: &[
            sc(
                req(p("key", "string", "A node of this site: downstream/<link>/…, storage/… (may be absent when in.key brings it).")),
                "key_scope",
            ),
            KEY_SCOPE,
            INTERVAL_MS,
            db(p("auto_run", "bool", "Read at the start and when the key changes (default true)."), true),
            ENABLED,
        ],
    },
    // ---------- tables (ADR 0044 §2: {columns, rows}; a list of maps is a table too) ----------
    NodeType {
        ty: "table",
        category: "Variables",
        description: "A table: sent at start, and again when in brings another.",
        inputs: &["in"],
        outputs: &["out"],
        dyn_inputs: None,
        dyn_outputs: None,
        params: &[ed(p("value", "map", "The table at start, {columns, rows} (default an empty table)."), "textarea")],
    },
    NodeType {
        ty: "table_recorder",
        category: "Tables",
        description: "A row {t, <input>…} for each sample on an input, the last buffer_size rows; reset clears it.",
        inputs: &["reset", "in.enabled", "in.buffer_size", "in.time_window_s", "in.ignore_null"],
        outputs: &["out"],
        dyn_inputs: Some(ITEMS),
        dyn_outputs: None,
        params: &[
            db(p("enabled", "bool", "Recording (default true)."), true),
            di(p("buffer_size", "number", "Rows at most, 1…10 000 (default 1024)."), 1024),
            di(ed(p("time_window_s", "number", "Above 0: only the rows of the last this many seconds (default 0)."), "duration"), 0),
            db(p("ignore_null", "bool", "A null records no row (default false)."), false),
            INPUTS,
        ],
    },
    table1("table_from_csv", "A CSV text as a table of texts; parse_error says it was none.", &["in", "in.with_header", "in.delimiter"], &["out", "parse_error"], &[
        db(p("with_header", "bool", "The first line names the columns (default true; else v1, v2, …)."), true),
        ds(p("delimiter", "string", "Between two fields: its first character (default a comma)."), ","),
    ]),
    table1("table_to_csv", "A table as CSV text, one line per row, every line ending in a line break.", &["in", "in.with_header", "in.delimiter"], &["out"], &[
        db(p("with_header", "bool", "A first line of column names (default true)."), true),
        ds(p("delimiter", "string", "Between two fields (default a comma)."), ","),
    ]),
    table1("table_from_json", "JSON (a text or a value) as a table: a list of objects (nested keys as a/b), one object, or {columns, rows}.", &["in", "in.selector"], &["out", "parse_error"], &[
        ds(p("selector", "string", "Where the data is: data.items or a.b[0] (default: the whole value)."), ""),
    ]),
    table1("table_to_json", "The rows of a table as a JSON text of objects.", &["in", "in.pretty"], &["out"], &[
        db(p("pretty", "bool", "Lines and indents (default false)."), false),
    ]),
    table1("table_map_columns", "A table of new columns: each mapping copies a column or computes one per row.", &["in", "in.retain_columns"], &["out", "error"], &[
        db(p("retain_columns", "bool", "Keep the input's columns first (default false)."), false),
        ed(p("mapping", "dynamic", "[{name, from}]: from is a column, or = expr (a value), + expr (a number), & expr (a bool), rhai over row and index: = row.name + \"/\" + row.zone."), "textarea"),
    ]),
    table1("table_sort", "The rows sorted by one column; a cell with no value sorts last either way.", &["in", "in.column", "in.method", "in.order"], &["out"], &[
        ds(p("column", "string", "The column to sort by (none: the table as it is)."), ""),
        pick(p("method", "string", "number, string (by code), natural (a2 before a10, no case)."), &["number", "string", "natural"], "number"),
        pick(p("order", "string", "ascending or descending."), &["ascending", "descending"], "ascending"),
    ]),
    table1("table_filter", "The rows for which expr is true; error says why a script failed.", &["in"], &["out", "error"], &[ROW_EXPR]),
    table1("table_remove_rows", "The rows for which expr is false: the others removed.", &["in"], &["out", "error"], &[ROW_EXPR]),
    table1("table_edit_rows", "The table with cells set in the rows for which expr is true.", &["in", "in.cells"], &["out", "error"], &[
        ROW_EXPR,
        p("cells", "map", "{<column>: <value>}: what each matching row gets (a new column is added)."),
    ]),
    table1("table_group_by", "One row per value of column, with aggregates of each group.", &["in", "in.column", "in.include_blank", "in.nested"], &["out"], &[
        ds(p("column", "string", "The column to group by."), ""),
        db(p("include_blank", "bool", "Rows with no value form a group with an empty key (default false: left out)."), false),
        db(p("nested", "bool", "A column rows with the group's rows as a table (default false)."), false),
        AGGREGATES,
    ]),
    table1("table_join", "in joined with right on column = right_column, one to one (the first match counts), or appended (union).", &["in", "right", "in.column", "in.right_column", "in.join"], &["out"], &[
        ds(p("column", "string", "The key column of in."), ""),
        p("right_column", "string", "The key column of right (default: column)."),
        pick(p("join", "string", "left, inner, right, full, exclude (in rows right lacks), union (all rows)."), crate::blocks::tables::JOINS, "left"),
    ]),
    table1("table_page", "One page of rows; next, previous, first, last move it.", &["in", "next", "previous", "first", "last", "in.page_size", "in.page"], &["out", "current_page", "total_pages"], &[
        di(p("page_size", "number", "Rows per page (default 10; below 0: one page of all; 0: empty)."), 10),
        di(p("page", "number", "The page, from 0 (default 0)."), 0),
    ]),
    table1("table_rollup", "Rows in time buckets of interval, each value column reduced; the bucket's start in time_column.", &["in", "in.time_column", "in.interval", "in.round_time", "in.method", "in.week_start", "in.time_zone"], &["out"], &[
        ds(p("time_column", "string", "The column of times: microseconds or date text (default t)."), "t"),
        ds(p("interval", "string", "<n> and s, m, h, d, w, M (months) or y: 15m, 1h, 1d (default 1h)."), "1h"),
        db(p("round_time", "bool", "Buckets on round times (default true; false: from the first row)."), true),
        pick(p("method", "string", "Without aggregates: how each other column is reduced."), crate::blocks::tables::METHODS, "average"),
        AGGREGATES,
        pick(p("week_start", "string", "The first day of a w bucket (default monday)."), &["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"], "monday"),
        TIME_ZONE,
    ]),
    table1("table_aggregate", "One value of a column by method.", &["in", "in.column", "in.method"], &["out"], &[
        ds(p("column", "string", "The column."), ""),
        pick(p("method", "string", "first, last, count, sum, average, min, max, median, mode, std_deviation, variance, concat, concat_unique."), crate::blocks::tables::METHODS, "first"),
    ]),
    table1("table_select_rows", "The rows at indexes, in that order.", &["in", "in.indexes"], &["out"], &[
        ds(p("indexes", "string", "0,2,5 or a list or one number (default 0)."), "0"),
    ]),
    table1("table_select_columns", "Only the named columns, in that order.", &["in", "in.columns"], &["out"], &[
        ds(p("columns", "string", "name,zone or a list."), ""),
    ]),
    table1("table_columns", "The columns of a table: a table {name, type}.", &["in"], &["out"], &[]),
    table1("table_row_cells", "One row as a map {<column>: <cell>}; count: the rows of the table.", &["in", "in.row"], &["out", "count"], &[
        di(p("row", "number", "The row, from 0 (default 0)."), 0),
    ]),
    table1("table_add_row", "The table with one more row (a new key adds its column).", &["in", "in.row"], &["out"], &[
        p("row", "map", "The row: {<column>: <cell>} (a make_object gives one)."),
    ]),
    table1("table_transpose", "Columns as rows: one row per column, one column per row.", &["in", "in.header_column", "in.include_headers", "in.header_prefix", "in.ignore_columns"], &["out"], &[
        ds(p("header_column", "string", "A column whose cells name the new columns (default: none)."), ""),
        db(p("include_headers", "bool", "A first column headers with the old column names (default false)."), false),
        ds(p("header_prefix", "string", "Without header_column: the new names are <prefix><n> (default c)."), "c"),
        ds(p("ignore_columns", "string", "Columns to leave out: a,b."), ""),
    ]),
    table1("table_from_map", "A map as a one-row table; a table or a list of maps passes as a table.", &["in"], &["out"], &[]),
];

/// A table block.
const fn table1(
    ty: &'static str,
    description: &'static str,
    inputs: &'static [&'static str],
    outputs: &'static [&'static str],
    params: &'static [Param],
) -> NodeType {
    unary(ty, "Tables", description, inputs, outputs, params)
}

const ROW_EXPR: Param = ds(
    ed(
        p("expr", "string", "rhai over row (the row as a map: row.kw) and index (from 0): row.kw > 5 && row.zone == \"A\" (default true)."),
        "textarea",
    ),
    "true",
);

const AGGREGATES: Param = ed(
    p("aggregates", "dynamic", "[{column, method, as}]: method one of first, last, count, sum, average, min, max, median, mode, std_deviation, variance, concat, concat_unique; as names the result (default: column)."),
    "textarea",
);

const TIME_ZONE: Param = ds(
    p(
        "time_zone",
        "string",
        "The zone of the wall time: Europe/Kyiv, UTC, +02:00 (default UTC).",
    ),
    "UTC",
);
