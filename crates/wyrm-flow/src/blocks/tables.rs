//! Table blocks of the third set (ADR 0044 §2): parsers and writers, column mapping, sort,
//! filter, group by, join, page, rollup, aggregate, selections and pure row transforms. Every
//! block takes a table (or a list of maps) and gives a table within [`table`]'s bounds; a
//! larger result is `null` with quality `bad`.

use super::table::{Table, MAX_COLUMNS, MAX_NAME, MAX_ROWS};
use super::{bounded_text, num, param, text, truth, Outs, Shape, View, MAX_TEXT, N};
use crate::nodes::PortType::{self, *};
use crate::script;
use std::cmp::Ordering;
use std::collections::BTreeMap;
use std::time::{Duration, Instant};
use wyrm_core::Value;

/// The longest CSV or JSON text a table block reads or writes, bytes.
pub const MAX_TEXT_TABLE: usize = 512 * 1024;
/// The longest field of a CSV text, bytes: a longer one refuses the text.
pub const MAX_FIELD: usize = 64 * 1024;

/// The longest time the per-row scripts of one table may take together.
const SCRIPT_BUDGET: Duration = Duration::from_millis(100);

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum Op {
    FromCsv,
    ToCsv,
    FromJson,
    ToJson,
    MapColumns,
    Sort,
    Filter,
    GroupBy,
    Join,
    Page,
    Rollup,
    Aggregate,
    SelectRows,
    SelectColumns,
    Columns,
    RowCells,
    AddRow,
    RemoveRows,
    EditRows,
    Transpose,
    FromMap,
}

pub(super) const OPS: &[(&str, Op)] = &[
    ("table_from_csv", Op::FromCsv),
    ("table_to_csv", Op::ToCsv),
    ("table_from_json", Op::FromJson),
    ("table_to_json", Op::ToJson),
    ("table_map_columns", Op::MapColumns),
    ("table_sort", Op::Sort),
    ("table_filter", Op::Filter),
    ("table_group_by", Op::GroupBy),
    ("table_join", Op::Join),
    ("table_page", Op::Page),
    ("table_rollup", Op::Rollup),
    ("table_aggregate", Op::Aggregate),
    ("table_select_rows", Op::SelectRows),
    ("table_select_columns", Op::SelectColumns),
    ("table_columns", Op::Columns),
    ("table_row_cells", Op::RowCells),
    ("table_add_row", Op::AddRow),
    ("table_remove_rows", Op::RemoveRows),
    ("table_edit_rows", Op::EditRows),
    ("table_transpose", Op::Transpose),
    ("table_from_map", Op::FromMap),
];

/// The methods of `table_aggregate`, `table_group_by` and `table_rollup`.
pub const METHODS: &[&str] = &[
    "first",
    "last",
    "count",
    "sum",
    "average",
    "min",
    "max",
    "median",
    "mode",
    "std_deviation",
    "variance",
    "concat",
    "concat_unique",
];

pub const JOINS: &[&str] = &["left", "inner", "right", "full", "exclude", "union"];

fn s(v: &str) -> Value {
    Value::Str(v.to_owned())
}

fn shape_of(
    inputs: &'static [&'static str],
    params: Vec<super::Param>,
    outputs: &'static [(&'static str, PortType)],
) -> Shape {
    Shape {
        inputs,
        params,
        items: false,
        outputs,
    }
}

const OUT: &[(&str, PortType)] = &[("out", Any)];

pub(super) fn shape(op: Op) -> Shape {
    let b = |n, d| param(n, Value::Bool(d), true);
    match op {
        Op::FromCsv => shape_of(
            &["in"],
            vec![b("with_header", true), param("delimiter", s(","), true)],
            &[("out", Any), ("parse_error", Bool)],
        ),
        Op::ToCsv => shape_of(
            &["in"],
            vec![b("with_header", true), param("delimiter", s(","), true)],
            OUT,
        ),
        Op::FromJson => shape_of(
            &["in"],
            vec![param("selector", s(""), true)],
            &[("out", Any), ("parse_error", Bool)],
        ),
        Op::ToJson => shape_of(&["in"], vec![b("pretty", false)], OUT),
        Op::MapColumns => shape_of(
            &["in"],
            vec![
                b("retain_columns", false),
                param("mapping", Value::Null, false),
            ],
            &[("out", Any), ("error", Any)],
        ),
        Op::Sort => shape_of(
            &["in"],
            vec![
                param("column", s(""), true),
                param("method", s("number"), true),
                param("order", s("ascending"), true),
            ],
            OUT,
        ),
        Op::Filter | Op::RemoveRows => shape_of(
            &["in"],
            vec![param("expr", s("true"), false)],
            &[("out", Any), ("error", Any)],
        ),
        Op::EditRows => shape_of(
            &["in"],
            vec![
                param("expr", s("true"), false),
                param("cells", Value::Null, true),
            ],
            &[("out", Any), ("error", Any)],
        ),
        Op::GroupBy => shape_of(
            &["in"],
            vec![
                param("column", s(""), true),
                b("include_blank", false),
                b("nested", false),
                param("aggregates", Value::Null, false),
            ],
            OUT,
        ),
        Op::Join => shape_of(
            &["in", "right"],
            vec![
                param("column", s(""), true),
                param("right_column", Value::Null, true),
                param("join", s("left"), true),
            ],
            OUT,
        ),
        Op::Page => shape_of(
            &["in", "next", "previous", "first", "last"],
            vec![
                param("page_size", Value::Int(10), true),
                param("page", Value::Int(0), true),
            ],
            &[
                ("out", Any),
                ("current_page", Number),
                ("total_pages", Number),
            ],
        ),
        Op::Rollup => shape_of(
            &["in"],
            vec![
                param("time_column", s("t"), true),
                param("interval", s("1h"), true),
                b("round_time", true),
                param("method", s("average"), true),
                param("aggregates", Value::Null, false),
                param("week_start", s("monday"), true),
                param("time_zone", s("UTC"), true),
            ],
            OUT,
        ),
        Op::Aggregate => shape_of(
            &["in"],
            vec![
                param("column", s(""), true),
                param("method", s("first"), true),
            ],
            OUT,
        ),
        Op::SelectRows => shape_of(&["in"], vec![param("indexes", s("0"), true)], OUT),
        Op::SelectColumns => shape_of(&["in"], vec![param("columns", s(""), true)], OUT),
        Op::Columns => shape_of(&["in"], vec![], OUT),
        Op::RowCells => shape_of(
            &["in"],
            vec![param("row", Value::Int(0), true)],
            &[("out", Map), ("count", Number)],
        ),
        Op::AddRow => shape_of(&["in"], vec![param("row", Value::Null, true)], OUT),
        Op::Transpose => shape_of(
            &["in"],
            vec![
                param("header_column", s(""), true),
                b("include_headers", false),
                param("header_prefix", s("c"), true),
                param("ignore_columns", s(""), true),
            ],
            OUT,
        ),
        Op::FromMap => shape_of(&["in"], vec![], OUT),
    }
}

/// The compiled per-row scripts of a block: `table_filter`, `table_remove_rows`,
/// `table_edit_rows` (`expr`), `table_map_columns` (each computed mapping).
pub(super) struct Scripts {
    engine: rhai::Engine,
    expr: Option<rhai::AST>,
    columns: Vec<(String, From)>,
}

/// Where a mapped column comes from.
enum From {
    Column(String),
    Expr(rhai::AST, char),
    Nothing,
}

/// The variables a per-row script sees: the row as a map, its index.
const ROW_VARS: &[&str] = &["row", "index"];

/// `mapping` of `table_map_columns`: `[{name, from}, …]`; `from` is a column, or `= expr`
/// (any value), `+ expr` (a number), `& expr` (a bool).
fn mapping(v: Option<&Value>) -> Result<Vec<(String, String)>, String> {
    let Some(v) = v.filter(|v| **v != Value::Null) else {
        return Ok(Vec::new());
    };
    let Value::Array(a) = v else {
        return Err("mapping: a list of {name, from}".into());
    };
    if a.len() > MAX_COLUMNS {
        return Err(format!("mapping: at most {MAX_COLUMNS}"));
    }
    a.iter()
        .map(|m| match m {
            Value::Map(m) => match (m.get("name"), m.get("from")) {
                (Some(Value::Str(n)), Some(Value::Str(f)))
                    if !n.is_empty() && n.len() <= MAX_NAME =>
                {
                    Ok((n.clone(), f.clone()))
                }
                _ => Err("mapping: each item is {name, from} with texts".into()),
            },
            _ => Err("mapping: each item is {name, from}".into()),
        })
        .collect()
}

/// `aggregates` of `table_group_by` and `table_rollup`: `[{column, method, as}, …]`.
fn aggregates(v: Option<&Value>) -> Result<Vec<(String, String, String)>, String> {
    let Some(v) = v.filter(|v| **v != Value::Null) else {
        return Ok(Vec::new());
    };
    let Value::Array(a) = v else {
        return Err("aggregates: a list of {column, method, as}".into());
    };
    if a.len() > MAX_COLUMNS {
        return Err(format!("aggregates: at most {MAX_COLUMNS}"));
    }
    a.iter()
        .map(|m| {
            let Value::Map(m) = m else {
                return Err("aggregates: each item is {column, method, as}".to_owned());
            };
            let t = |k: &str| match m.get(k) {
                Some(Value::Str(x)) => Some(x.clone()),
                _ => None,
            };
            let column = t("column")
                .filter(|c| !c.is_empty())
                .ok_or("aggregates: column required")?;
            let method = t("method").unwrap_or_else(|| "first".into());
            if !METHODS.contains(&method.as_str()) {
                return Err(format!("aggregates: method one of {METHODS:?}"));
            }
            let name = t("as")
                .filter(|a| !a.is_empty())
                .unwrap_or_else(|| column.clone());
            Ok((column, method, name))
        })
        .collect()
}

/// The config check and the scripts of a table block.
pub(super) fn scripts(op: Op, cfg: &crate::def::Map) -> Result<Option<Scripts>, String> {
    match op {
        Op::GroupBy | Op::Rollup => {
            aggregates(cfg.get("aggregates"))?;
            Ok(None)
        }
        Op::Filter | Op::RemoveRows | Op::EditRows => {
            let src = match cfg.get("expr") {
                None => "true",
                Some(Value::Str(x)) => x.as_str(),
                Some(_) => return Err("expr: a rhai expression over row and index".into()),
            };
            let engine = script::engine();
            let ast = script::compile(&engine, src, ROW_VARS).map_err(|e| format!("expr: {e}"))?;
            Ok(Some(Scripts {
                engine,
                expr: Some(ast),
                columns: Vec::new(),
            }))
        }
        Op::MapColumns => {
            let engine = script::engine();
            let mut columns = Vec::new();
            for (name, from) in mapping(cfg.get("mapping"))? {
                let f = from.trim_start();
                let src = match f.chars().next() {
                    Some(c @ ('=' | '+' | '&')) => Some((c, f[1..].to_owned())),
                    _ => None,
                };
                let how = match src {
                    Some((c, e)) => From::Expr(
                        script::compile(&engine, &e, ROW_VARS)
                            .map_err(|e| format!("mapping.{name}: {e}"))?,
                        c,
                    ),
                    None if f.is_empty() => From::Nothing,
                    None => From::Column(from.clone()),
                };
                columns.push((name, how));
            }
            Ok(Some(Scripts {
                engine,
                expr: None,
                columns,
            }))
        }
        _ => Ok(None),
    }
}

/// A table result as outputs: `null` and `bad` past a bound.
fn table_out(t: &Table) -> (Value, bool) {
    match t.to_value() {
        Some(v) => (v, false),
        None => (Value::Null, true),
    }
}

fn input_table(v: &View) -> Option<Table> {
    Table::from_value(v.inv)
}

fn ptext(v: &View, n: &str) -> String {
    match v.p(n) {
        Value::Str(s) => s.clone(),
        Value::Null => String::new(),
        x => text(x),
    }
}

/// A list parameter as names: a list of texts, or one text with commas.
fn name_list(v: &Value) -> Vec<String> {
    // at most a few times the columns a table may have
    const MAX_NAMES: usize = 4 * MAX_COLUMNS;
    match v {
        Value::Array(a) => a.iter().take(MAX_NAMES).map(text).collect(),
        Value::Str(s) if !s.trim().is_empty() => s
            .split(',')
            .take(MAX_NAMES)
            .map(|x| x.trim().to_owned())
            .collect(),
        _ => Vec::new(),
    }
}

/// A cell a script gave, as a value: a float that is not finite is `null`.
fn clean(v: Value) -> Value {
    match v {
        Value::Float(x) if !x.is_finite() => Value::Null,
        v => v,
    }
}

/// Run `ast` on each row; `None` and the reason when a script fails or the table's budget ends.
fn per_row<T>(
    sc: &Scripts,
    ast: &rhai::AST,
    t: &Table,
    mut each: impl FnMut(usize, Value) -> T,
) -> Result<Vec<T>, String> {
    let start = Instant::now();
    let mut state = rhai::Map::new();
    let mut out = Vec::with_capacity(t.rows.len());
    for (i, r) in t.rows.iter().enumerate() {
        if start.elapsed() > SCRIPT_BUDGET {
            return Err(format!(
                "the scripts took longer than {} ms for the table",
                SCRIPT_BUDGET.as_millis()
            ));
        }
        let row = Value::Map(r.clone());
        let vars = vec![
            ("row".to_owned(), script::to_dynamic(&row)),
            ("index".to_owned(), rhai::Dynamic::from_int(i as i64)),
        ];
        let d =
            script::eval(&sc.engine, ast, vars, &mut state).map_err(|e| format!("row {i}: {e}"))?;
        out.push(each(i, clean(script::from_dynamic(&d))));
    }
    Ok(out)
}

pub(super) fn calc(op: Op, v: &View, sc: Option<&Scripts>) -> Outs {
    let one = |(val, bad): (Value, bool)| vec![("out", val, bad)];
    let nul = || vec![("out", Value::Null, false)];
    match op {
        Op::FromCsv => {
            let delim = ptext(v, "delimiter").chars().next().unwrap_or(',');
            match v.inv {
                Value::Str(s) if s.len() <= MAX_TEXT_TABLE => {
                    match parse_csv(s, delim, truth(v.p("with_header"), true)) {
                        Some(t) => {
                            let (val, bad) = table_out(&t);
                            vec![
                                ("out", val, bad),
                                ("parse_error", Value::Bool(false), false),
                            ]
                        }
                        None => vec![
                            ("out", Value::Null, false),
                            ("parse_error", Value::Bool(true), false),
                        ],
                    }
                }
                _ => vec![
                    ("out", Value::Null, false),
                    ("parse_error", Value::Bool(true), false),
                ],
            }
        }
        Op::ToCsv => match input_table(v) {
            None => nul(),
            Some(t) => {
                let delim = ptext(v, "delimiter").chars().next().unwrap_or(',');
                let csv = write_csv(&t, delim, truth(v.p("with_header"), true));
                one(if csv.len() > MAX_TEXT_TABLE {
                    (Value::Null, true)
                } else {
                    (Value::Str(csv), false)
                })
            }
        },
        Op::FromJson => {
            let parsed = match v.inv {
                Value::Str(s) => super::text::parse_json(s).ok(),
                Value::Null => None,
                x => Some(x.clone()),
            };
            let Some(j) = parsed else {
                return vec![
                    ("out", Value::Null, false),
                    ("parse_error", Value::Bool(true), false),
                ];
            };
            let at = select(&j, &ptext(v, "selector"));
            let t = match at {
                Some(Value::Map(m)) if m.contains_key("rows") => {
                    Table::from_value(at.unwrap_or(&Value::Null))
                }
                Some(Value::Array(a)) => Some(flatten(a)),
                Some(m @ Value::Map(_)) => Some(flatten(std::slice::from_ref(m))),
                _ => None,
            };
            match t {
                Some(t) => {
                    let (val, bad) = table_out(&t);
                    vec![
                        ("out", val, bad),
                        ("parse_error", Value::Bool(false), false),
                    ]
                }
                None => vec![
                    ("out", Value::Null, false),
                    ("parse_error", Value::Bool(at.is_none()), false),
                ],
            }
        }
        Op::ToJson => match input_table(v) {
            None => nul(),
            Some(t) => {
                let rows = Value::Array(t.rows.iter().map(|r| Value::Map(r.clone())).collect());
                let s = super::text::stringify(&rows, truth(v.p("pretty"), false));
                one(s
                    .filter(|s| s.len() <= MAX_TEXT_TABLE)
                    .map_or((Value::Null, true), |s| (Value::Str(s), false)))
            }
        },
        Op::MapColumns => {
            let (Some(t), Some(sc)) = (input_table(v), sc) else {
                return vec![("out", Value::Null, false), ("error", Value::Null, false)];
            };
            let mut cols: Vec<String> = if truth(v.p("retain_columns"), false) {
                t.columns.clone()
            } else {
                Vec::new()
            };
            let mut out = Table::new(Vec::new());
            out.rows = if truth(v.p("retain_columns"), false) {
                t.rows.clone()
            } else {
                vec![BTreeMap::new(); t.rows.len()]
            };
            for (name, how) in &sc.columns {
                let cells: Result<Vec<Value>, String> = match how {
                    From::Column(c) => Ok(t
                        .rows
                        .iter()
                        .map(|r| r.get(c).cloned().unwrap_or(Value::Null))
                        .collect()),
                    From::Nothing => Ok(vec![Value::Null; t.rows.len()]),
                    From::Expr(ast, kind) => per_row(sc, ast, &t, |_, x| match kind {
                        '+' => num(&x).map_or(Value::Null, N::value),
                        '&' => Value::Bool(truth(&x, false)),
                        _ => x,
                    }),
                };
                match cells {
                    Ok(cells) => {
                        for (r, c) in out.rows.iter_mut().zip(cells) {
                            r.insert(name.clone(), c);
                        }
                    }
                    Err(e) => {
                        return vec![("out", Value::Null, false), ("error", Value::Str(e), false)]
                    }
                }
                if !cols.contains(name) {
                    cols.push(name.clone());
                }
            }
            out.columns = cols;
            let (val, bad) = table_out(&out);
            vec![("out", val, bad), ("error", Value::Null, false)]
        }
        Op::Sort => {
            let Some(mut t) = input_table(v) else {
                return nul();
            };
            let col = ptext(v, "column");
            if t.columns.contains(&col) {
                let method = ptext(v, "method");
                let desc = ptext(v, "order") == "descending";
                t.rows.sort_by(|a, b| {
                    order(
                        a.get(&col).unwrap_or(&Value::Null),
                        b.get(&col).unwrap_or(&Value::Null),
                        &method,
                        desc,
                    )
                });
            }
            one(table_out(&t))
        }
        Op::Filter | Op::RemoveRows => {
            let (Some(t), Some(sc)) = (input_table(v), sc) else {
                return vec![("out", Value::Null, false), ("error", Value::Null, false)];
            };
            let Some(ast) = sc.expr.as_ref() else {
                return nul();
            };
            match per_row(sc, ast, &t, |_, x| truth(&x, false)) {
                Ok(keep) => {
                    let remove = op == Op::RemoveRows;
                    let rows = t
                        .rows
                        .iter()
                        .zip(keep)
                        .filter(|(_, k)| *k != remove)
                        .map(|(r, _)| r.clone())
                        .collect();
                    let (val, bad) = table_out(&Table {
                        columns: t.columns.clone(),
                        rows,
                    });
                    vec![("out", val, bad), ("error", Value::Null, false)]
                }
                Err(e) => vec![("out", Value::Null, false), ("error", Value::Str(e), false)],
            }
        }
        Op::EditRows => {
            let (Some(mut t), Some(sc)) = (input_table(v), sc) else {
                return vec![("out", Value::Null, false), ("error", Value::Null, false)];
            };
            let Some(ast) = sc.expr.as_ref() else {
                return nul();
            };
            let Value::Map(cells) = v.p("cells") else {
                return vec![
                    ("out", table_out(&t).0, false),
                    ("error", Value::Null, false),
                ];
            };
            match per_row(sc, ast, &t, |_, x| truth(&x, false)) {
                Ok(hit) => {
                    for (r, h) in t.rows.iter_mut().zip(hit) {
                        if h {
                            r.extend(cells.iter().map(|(k, x)| (k.clone(), x.clone())));
                        }
                    }
                    for k in cells.keys() {
                        if !t.columns.contains(k) {
                            t.columns.push(k.clone());
                        }
                    }
                    let (val, bad) = table_out(&t);
                    vec![("out", val, bad), ("error", Value::Null, false)]
                }
                Err(e) => vec![("out", Value::Null, false), ("error", Value::Str(e), false)],
            }
        }
        Op::GroupBy => {
            let Some(t) = input_table(v) else {
                return nul();
            };
            let base = ptext(v, "column");
            if !t.columns.contains(&base) {
                return nul();
            }
            let Ok(aggs) = aggregates(match v.p("aggregates") {
                Value::Null => None,
                x => Some(x),
            }) else {
                return nul();
            };
            let blank = truth(v.p("include_blank"), false);
            let mut keys: Vec<String> = Vec::new();
            let mut groups: BTreeMap<String, Vec<usize>> = BTreeMap::new();
            for (i, r) in t.rows.iter().enumerate() {
                let k = match r.get(&base) {
                    None | Some(Value::Null) => String::new(),
                    Some(x) => bounded_text(x).unwrap_or_default(),
                };
                if k.is_empty() && !blank {
                    continue;
                }
                if !groups.contains_key(&k) {
                    keys.push(k.clone());
                }
                groups.entry(k).or_default().push(i);
            }
            let mut cols = vec![base.clone()];
            cols.extend(aggs.iter().map(|(_, _, a)| a.clone()));
            let nested = truth(v.p("nested"), false);
            if nested {
                cols.push("rows".into());
            }
            let mut out = Table::new(cols);
            for k in keys {
                let idx = &groups[&k];
                let mut row = BTreeMap::from([(base.clone(), Value::Str(k))]);
                for (c, m, a) in &aggs {
                    let cells: Vec<&Value> = idx.iter().map(|i| t.cell(*i, c)).collect();
                    row.insert(a.clone(), aggregate(m, &cells));
                }
                if nested {
                    let sub = Table {
                        columns: t.columns.clone(),
                        rows: idx.iter().map(|i| t.rows[*i].clone()).collect(),
                    };
                    row.insert("rows".into(), sub.to_value().unwrap_or(Value::Null));
                }
                out.rows.push(row);
            }
            one(table_out(&out))
        }
        Op::Join => {
            let (l, r) = (
                input_table(v),
                v.ins.get("right").and_then(Table::from_value),
            );
            let col = ptext(v, "column");
            let rcol = match v.p("right_column") {
                Value::Str(c) if !c.is_empty() => c.clone(),
                _ => col.clone(),
            };
            let kind = ptext(v, "join");
            match join(l, r, &col, &rcol, &kind) {
                Some(t) => one(table_out(&t)),
                None => nul(),
            }
        }
        Op::Page => nul(), // `blocks.rs` pages: it keeps the page
        Op::Rollup => {
            let Some(t) = input_table(v) else {
                return nul();
            };
            match rollup(&t, v) {
                Some(t) => one(table_out(&t)),
                None => nul(),
            }
        }
        Op::Aggregate => {
            let Some(t) = input_table(v) else {
                return nul();
            };
            let col = ptext(v, "column");
            let m = ptext(v, "method");
            if !t.columns.contains(&col) || !METHODS.contains(&m.as_str()) {
                return nul();
            }
            let cells: Vec<&Value> = (0..t.rows.len()).map(|i| t.cell(i, &col)).collect();
            one((aggregate(&m, &cells), false))
        }
        Op::SelectRows => {
            let Some(t) = input_table(v) else {
                return nul();
            };
            let idx: Vec<usize> = match v.p("indexes") {
                Value::Array(a) => a.iter().filter_map(|x| super::whole(x, MAX_ROWS)).collect(),
                Value::Str(s) => s
                    .split(',')
                    .filter_map(|x| x.trim().parse::<usize>().ok())
                    .collect(),
                x => super::whole(x, MAX_ROWS).into_iter().collect(),
            };
            let rows = idx
                .into_iter()
                .take(MAX_ROWS)
                .filter_map(|i| t.rows.get(i).cloned())
                .collect();
            one(table_out(&Table {
                columns: t.columns.clone(),
                rows,
            }))
        }
        Op::SelectColumns => {
            let Some(t) = input_table(v) else {
                return nul();
            };
            let mut cols: Vec<String> = Vec::new();
            for c in name_list(v.p("columns")) {
                if t.columns.contains(&c) && !cols.contains(&c) {
                    cols.push(c);
                }
            }
            let rows = t
                .rows
                .iter()
                .map(|r| {
                    cols.iter()
                        .map(|c| (c.clone(), r.get(c).cloned().unwrap_or(Value::Null)))
                        .collect()
                })
                .collect();
            one(table_out(&Table {
                columns: cols,
                rows,
            }))
        }
        Op::Columns => {
            let Some(t) = input_table(v) else {
                return nul();
            };
            let mut out = Table::new(vec!["name".into(), "type".into()]);
            for c in &t.columns {
                out.rows.push(BTreeMap::from([
                    ("name".to_owned(), Value::Str(c.clone())),
                    ("type".to_owned(), Value::from(column_type(&t, c))),
                ]));
            }
            one(table_out(&out))
        }
        Op::RowCells => {
            let Some(t) = input_table(v) else {
                return vec![("out", Value::Null, false), ("count", Value::Null, false)];
            };
            let row = super::whole(v.p("row"), MAX_ROWS)
                .and_then(|i| t.rows.get(i))
                .map(|r| {
                    Value::Map(
                        t.columns
                            .iter()
                            .map(|c| (c.clone(), r.get(c).cloned().unwrap_or(Value::Null)))
                            .collect(),
                    )
                })
                .unwrap_or(Value::Null);
            vec![
                ("out", row, false),
                ("count", Value::UInt(t.rows.len() as u64), false),
            ]
        }
        Op::AddRow => {
            let Some(mut t) = input_table(v) else {
                return nul();
            };
            if let Value::Map(r) = v.p("row") {
                for k in r.keys() {
                    if !t.columns.contains(k) {
                        t.columns.push(k.clone());
                    }
                }
                t.rows.push(r.clone());
            }
            one(table_out(&t))
        }
        Op::Transpose => {
            let Some(t) = input_table(v) else {
                return nul();
            };
            one(table_out(&transpose(&t, v)))
        }
        Op::FromMap => match v.inv {
            Value::Map(m) if !m.contains_key("rows") => {
                let t = Table {
                    columns: m.keys().cloned().collect(),
                    rows: vec![m.clone()],
                };
                one(table_out(&t))
            }
            x => match Table::from_value(x) {
                Some(t) => one(table_out(&t)),
                None => nul(),
            },
        },
    }
}

/// The reference's CSV reader: a quoted field is the text between its first and last quote
/// (`""` a quote when it had more than two); every line ended by a newline is a row, an empty
/// one too; the last line without a newline only when it has a field. `None`: no rows.
pub(super) fn parse_csv(s: &str, delim: char, header: bool) -> Option<Table> {
    let mut rows: Vec<Vec<String>> = Vec::new();
    let mut row: Vec<String> = Vec::new();
    let mut raw = String::new();
    let mut quotes = 0usize;
    let (mut first_q, mut last_q) = (None::<usize>, None::<usize>);
    let end_field = |raw: &mut String,
                     quotes: &mut usize,
                     fq: &mut Option<usize>,
                     lq: &mut Option<usize>,
                     row: &mut Vec<String>| {
        let f = match (*fq, *lq) {
            (Some(a), Some(b)) if *quotes > 0 && b > a => {
                let inner = &raw[a + 1..b];
                if *quotes > 2 {
                    inner.replace("\"\"", "\"")
                } else {
                    inner.to_owned()
                }
            }
            (Some(a), _) if *quotes > 0 => raw[a + 1..].to_owned(),
            _ => std::mem::take(raw),
        };
        raw.clear();
        *quotes = 0;
        *fq = None;
        *lq = None;
        row.push(f);
    };
    let mut chars = s.chars().peekable();
    while let Some(c) = chars.next() {
        // bounded while it reads: a row of more fields than a table has columns, or a field
        // past 64 KiB, refuses the text (security review 2026-11-11)
        if row.len() > MAX_COLUMNS || raw.len() > MAX_FIELD {
            return None;
        }
        if c == '"' {
            if first_q.is_none() {
                first_q = Some(raw.len());
            }
            last_q = Some(raw.len());
            quotes += 1;
            raw.push(c);
            continue;
        }
        if quotes.is_multiple_of(2) && (c == delim || c == '\n' || c == '\r') {
            end_field(&mut raw, &mut quotes, &mut first_q, &mut last_q, &mut row);
            if c != delim {
                if c == '\r' && chars.peek() == Some(&'\n') {
                    chars.next();
                }
                rows.push(std::mem::take(&mut row));
                if rows.len() > MAX_ROWS + 1 {
                    return None;
                }
            }
            continue;
        }
        raw.push(c);
    }
    if row.len() > MAX_COLUMNS || raw.len() > MAX_FIELD {
        return None;
    }
    if !raw.is_empty() || quotes > 0 || !row.is_empty() {
        end_field(&mut raw, &mut quotes, &mut first_q, &mut last_q, &mut row);
        if row.len() > 1 || row.first().is_some_and(|f| !f.is_empty()) {
            rows.push(row);
        }
    }
    if rows.is_empty() {
        return None;
    }
    let width = rows.iter().map(Vec::len).max().unwrap_or(0);
    if width > MAX_COLUMNS {
        return None;
    }
    let (names, body) = if header {
        let mut names = Names::default();
        for (i, n) in rows[0].iter().enumerate() {
            // a name twice keeps both columns: `a`, `a_2`, …
            names.add(if n.is_empty() {
                format!("v{}", i + 1)
            } else {
                n.clone()
            });
        }
        while names.list.len() < width {
            let n = format!("v{}", names.list.len() + 1);
            names.add(n);
        }
        (names.list, &rows[1..])
    } else {
        ((1..=width).map(|i| format!("v{i}")).collect(), &rows[..])
    };
    let mut t = Table::new(names);
    for r in body {
        t.rows.push(
            t.columns
                .iter()
                .zip(r)
                .map(|(c, x)| (c.clone(), Value::Str(x.clone())))
                .collect(),
        );
    }
    Some(t)
}

/// Column names made unique in one pass: a name seen before gets `_2`, `_3`, … from a counter
/// per name, so each name costs one look-up.
#[derive(Default)]
struct Names {
    list: Vec<String>,
    seen: std::collections::HashSet<String>,
    next: std::collections::HashMap<String, usize>,
}

impl Names {
    fn add(&mut self, base: String) -> String {
        let mut n = base.clone();
        if self.seen.contains(&n) {
            let k = self.next.entry(base.clone()).or_insert(2);
            loop {
                n = format!("{base}_{k}");
                *k += 1;
                if !self.seen.contains(&n) {
                    break;
                }
            }
        }
        self.seen.insert(n.clone());
        self.list.push(n.clone());
        n
    }
}

/// CSV with `delim`; a field with a quote, the delimiter or a line break is quoted.
pub(super) fn write_csv(t: &Table, delim: char, header: bool) -> String {
    let q = |x: &str| {
        if x.contains('"') {
            format!("\"{}\"", x.replace('"', "\"\""))
        } else if x.contains(delim) || x.contains('\n') || x.contains('\r') {
            format!("\"{x}\"")
        } else {
            x.to_owned()
        }
    };
    let mut out = String::new();
    let d = delim.to_string();
    if header {
        out.push_str(&t.columns.iter().map(|c| q(c)).collect::<Vec<_>>().join(&d));
        out.push('\n');
    }
    for r in &t.rows {
        let line: Vec<String> = t
            .columns
            .iter()
            .map(|c| q(&text(r.get(c).unwrap_or(&Value::Null))))
            .collect();
        out.push_str(&line.join(&d));
        out.push('\n');
        if out.len() > MAX_TEXT_TABLE {
            break;
        }
    }
    out
}

/// The value at `a.b[0].c` (empty: the value itself).
fn select<'a>(v: &'a Value, path: &str) -> Option<&'a Value> {
    let mut cur = v;
    for seg in path.split(['.', '[', ']']).filter(|s| !s.is_empty()) {
        cur = match cur {
            Value::Map(m) => m.get(seg)?,
            Value::Array(a) => a.get(seg.parse::<usize>().ok()?)?,
            _ => return None,
        };
    }
    Some(cur)
}

/// A list of objects as rows; a nested map's keys become `a/b`; a scalar item is `{value}`.
fn flatten(items: &[Value]) -> Table {
    fn go(
        prefix: &str,
        v: &Value,
        row: &mut BTreeMap<String, Value>,
        cols: &mut Vec<String>,
        depth: usize,
    ) {
        match v {
            Value::Map(m) if depth < 8 => {
                for (k, x) in m {
                    let name = if prefix.is_empty() {
                        k.clone()
                    } else {
                        format!("{prefix}/{k}")
                    };
                    go(&name, x, row, cols, depth + 1);
                }
            }
            x => {
                let name = if prefix.is_empty() {
                    "value".to_owned()
                } else {
                    prefix.to_owned()
                };
                if cols.len() < MAX_COLUMNS && !cols.contains(&name) {
                    cols.push(name.clone());
                }
                if cols.contains(&name) {
                    row.insert(name, x.clone());
                }
            }
        }
    }
    let mut t = Table::new(Vec::new());
    for it in items.iter().take(MAX_ROWS + 1) {
        let mut row = BTreeMap::new();
        go("", it, &mut row, &mut t.columns, 0);
        t.rows.push(row);
    }
    t
}

/// Natural order: digit runs as numbers, letters without case.
fn natural(a: &str, b: &str) -> Ordering {
    let (mut x, mut y) = (a.chars().peekable(), b.chars().peekable());
    loop {
        match (x.peek().copied(), y.peek().copied()) {
            (None, None) => return Ordering::Equal,
            (None, _) => return Ordering::Less,
            (_, None) => return Ordering::Greater,
            (Some(c), Some(d)) if c.is_ascii_digit() && d.is_ascii_digit() => {
                let take = |it: &mut std::iter::Peekable<std::str::Chars>| {
                    let mut s = String::new();
                    while let Some(c) = it.peek().copied().filter(char::is_ascii_digit) {
                        s.push(c);
                        it.next();
                    }
                    s
                };
                let (m, n) = (take(&mut x), take(&mut y));
                let (m2, n2) = (m.trim_start_matches('0'), n.trim_start_matches('0'));
                let o = m2.len().cmp(&n2.len()).then(m2.cmp(n2));
                if o != Ordering::Equal {
                    return o;
                }
            }
            (Some(c), Some(d)) => {
                let o = c.to_lowercase().cmp(d.to_lowercase());
                if o != Ordering::Equal {
                    return o;
                }
                x.next();
                y.next();
            }
        }
    }
}

/// Sort order of two cells; a cell that is no number (`number`) or `null` (the others) is last
/// in both orders.
fn order(a: &Value, b: &Value, method: &str, desc: bool) -> Ordering {
    let flip = |o: Ordering| if desc { o.reverse() } else { o };
    match method {
        "string" | "natural" => match (a, b) {
            (Value::Null, Value::Null) => Ordering::Equal,
            (Value::Null, _) => Ordering::Greater,
            (_, Value::Null) => Ordering::Less,
            _ => {
                let (x, y) = (text(a), text(b));
                flip(if method == "natural" {
                    natural(&x, &y)
                } else {
                    x.cmp(&y)
                })
            }
        },
        _ => match (num(a), num(b)) {
            (None, None) => Ordering::Equal,
            (None, _) => Ordering::Greater,
            (_, None) => Ordering::Less,
            (Some(x), Some(y)) => flip(x.f().total_cmp(&y.f())),
        },
    }
}

/// One value of a column's cells by `method`.
pub(super) fn aggregate(method: &str, cells: &[&Value]) -> Value {
    let nums: Vec<N> = cells.iter().filter_map(|v| num(v)).collect();
    let present: Vec<&&Value> = cells.iter().filter(|v| ***v != Value::Null).collect();
    match method {
        "first" => cells.first().map_or(Value::Null, |v| (*v).clone()),
        "last" => cells.last().map_or(Value::Null, |v| (*v).clone()),
        "count" => Value::UInt(present.len() as u64),
        "sum" => nums
            .iter()
            .fold(N::I(0), |a, b| a.op(*b, i64::checked_add, |x, y| x + y))
            .value(),
        "min" | "max" => nums
            .iter()
            .copied()
            .reduce(|a, b| {
                if (method == "min") == (b.f() < a.f()) {
                    b
                } else {
                    a
                }
            })
            .map_or(Value::Null, N::value),
        "concat" | "concat_unique" => {
            let mut seen: Vec<String> = Vec::new();
            for v in present {
                let t = text(v);
                if method == "concat" || !seen.contains(&t) {
                    seen.push(t);
                }
            }
            let s = seen.join(",");
            if s.len() > MAX_TEXT {
                Value::Null
            } else {
                Value::Str(s)
            }
        }
        "average" | "median" | "variance" | "std_deviation" | "mode" => {
            let st = match method {
                "average" => super::math::Stat::Average,
                "median" => super::math::Stat::Median,
                "variance" => super::math::Stat::Variance,
                "std_deviation" => super::math::Stat::StdDeviation,
                _ => super::math::Stat::Mode,
            };
            let items: Vec<Value> = cells.iter().map(|v| (*v).clone()).collect();
            super::math::stat(st, &items)
        }
        _ => Value::Null,
    }
}

/// The reference's joins, one to one: the first matching row of the other table counts.
fn join(l: Option<Table>, r: Option<Table>, col: &str, rcol: &str, kind: &str) -> Option<Table> {
    let key = |v: &Value| match v {
        Value::Null => None,
        v => bounded_text(v),
    };
    let (l, r) = match (l, r) {
        (Some(l), Some(r)) => (l, r),
        (Some(l), None) if kind != "right" && kind != "inner" => return Some(l),
        (None, Some(r)) if kind == "right" => return Some(r),
        _ => return None,
    };
    if kind == "union" {
        let mut t = l;
        for c in &r.columns {
            if !t.columns.contains(c) {
                t.columns.push(c.clone());
            }
        }
        t.rows.extend(r.rows);
        return Some(t);
    }
    if !l.columns.iter().any(|c| c == col) || !r.columns.iter().any(|c| c == rcol) {
        return match kind {
            "left" | "full" | "exclude" => Some(l),
            "right" => Some(r),
            _ => None,
        };
    }
    // the right key is the left key's column; other right columns join after the left ones
    let new: Vec<String> = r
        .columns
        .iter()
        .filter(|c| *c != rcol && !l.columns.contains(c))
        .cloned()
        .collect();
    let mut cols = l.columns.clone();
    if kind != "exclude" {
        cols.extend(new.iter().cloned());
    }
    let mut r_index: BTreeMap<String, usize> = BTreeMap::new();
    for (i, row) in r.rows.iter().enumerate() {
        if let Some(k) = row.get(rcol).and_then(key) {
            r_index.entry(k).or_insert(i);
        }
    }
    let fill = |row: &mut BTreeMap<String, Value>, rr: &BTreeMap<String, Value>| {
        for c in &new {
            row.insert(c.clone(), rr.get(c).cloned().unwrap_or(Value::Null));
        }
    };
    let mut rows = Vec::new();
    match kind {
        "inner" | "left" | "exclude" => {
            for row in &l.rows {
                let hit = row
                    .get(col)
                    .and_then(key)
                    .and_then(|k| r_index.get(&k))
                    .copied();
                match (kind, hit) {
                    ("exclude", None) if row.get(col).and_then(key).is_some() => {
                        rows.push(row.clone())
                    }
                    ("exclude", _) => {}
                    ("inner", None) => {}
                    (_, h) => {
                        let mut out = row.clone();
                        if let Some(i) = h {
                            fill(&mut out, &r.rows[i]);
                        }
                        rows.push(out);
                    }
                }
            }
        }
        "right" => {
            let mut l_index: BTreeMap<String, usize> = BTreeMap::new();
            for (i, row) in l.rows.iter().enumerate() {
                if let Some(k) = row.get(col).and_then(key) {
                    l_index.entry(k).or_insert(i);
                }
            }
            for rr in &r.rows {
                let k = rr.get(rcol).and_then(key);
                let mut out = k
                    .as_ref()
                    .and_then(|k| l_index.get(k))
                    .map(|i| l.rows[*i].clone())
                    .unwrap_or_default();
                for (c, x) in rr {
                    let name = if c == rcol { col.to_owned() } else { c.clone() };
                    out.insert(name, x.clone());
                }
                rows.push(out);
            }
        }
        _ => {
            // full: the left rows with a key once each, filled; then the right rows no left row has
            let mut seen: BTreeMap<String, usize> = BTreeMap::new();
            for row in &l.rows {
                let Some(k) = row.get(col).and_then(key) else {
                    continue;
                };
                if seen.contains_key(&k) {
                    continue;
                }
                let mut out = row.clone();
                if let Some(i) = r_index.get(&k) {
                    fill(&mut out, &r.rows[*i]);
                }
                seen.insert(k, rows.len());
                rows.push(out);
            }
            let mut done: Vec<String> = Vec::new();
            for rr in &r.rows {
                let Some(k) = rr.get(rcol).and_then(key) else {
                    continue;
                };
                if seen.contains_key(&k) || done.contains(&k) {
                    continue;
                }
                done.push(k);
                let mut out: BTreeMap<String, Value> = BTreeMap::new();
                for (c, x) in rr {
                    let name = if c == rcol { col.to_owned() } else { c.clone() };
                    out.insert(name, x.clone());
                }
                rows.push(out);
            }
        }
    }
    if rows.len() > MAX_ROWS {
        return None;
    }
    Some(Table {
        columns: cols,
        rows,
    })
}

fn column_type(t: &Table, c: &str) -> &'static str {
    let mut ty: Option<&'static str> = None;
    for r in &t.rows {
        let this = match r.get(c).unwrap_or(&Value::Null) {
            Value::Null => continue,
            Value::Bool(_) => "bool",
            Value::Int(_) | Value::UInt(_) | Value::Float(_) => "number",
            Value::Str(_) => "string",
            Value::Bytes(_) => "bytes",
            Value::Array(_) => "list",
            Value::Map(_) => "map",
        };
        match ty {
            None => ty = Some(this),
            Some(x) if x != this => return "mixed",
            _ => {}
        }
    }
    ty.unwrap_or("null")
}

/// Columns to rows: one output row per input column (the ignored ones and the header column
/// left out), one output column per input row, named by `header_column`'s cell or
/// `<header_prefix><n>`; `include_headers` adds the column `headers` with the input names.
fn transpose(t: &Table, v: &View) -> Table {
    let hc = ptext(v, "header_column");
    let has_h = t.columns.contains(&hc);
    let prefix = ptext(v, "header_prefix");
    let mut ignore = name_list(v.p("ignore_columns"));
    if has_h {
        ignore.push(hc.clone());
    }
    let mut cols = Names::default();
    if truth(v.p("include_headers"), false) {
        cols.add("headers".into());
    }
    let mut names = Vec::new();
    for (n, r) in t.rows.iter().enumerate().take(MAX_COLUMNS) {
        let name = if has_h {
            text(r.get(&hc).unwrap_or(&Value::Null))
        } else {
            format!("{prefix}{n}")
        };
        names.push(cols.add(name));
    }
    let cols = cols.list;
    let mut out = Table::new(cols);
    for c in t.columns.iter().filter(|c| !ignore.contains(c)) {
        let mut row = BTreeMap::new();
        row.insert("headers".to_owned(), Value::Str(c.clone()));
        for (n, name) in names.iter().enumerate() {
            row.insert(name.clone(), t.cell(n, c).clone());
        }
        if !out.columns.contains(&"headers".to_owned()) {
            row.remove("headers");
        }
        out.rows.push(row);
    }
    out
}

/// `<n><unit>`: `s`, `m` (minutes), `h`, `d`, `w`, `M` (months), `y`; and the reference's names.
fn interval(t: &str) -> Option<(i64, char)> {
    let named = [
        ("oneMinute", "1m"),
        ("fiveMinutes", "5m"),
        ("fifteenMinutes", "15m"),
        ("twentyMinutes", "20m"),
        ("thirtyMinutes", "30m"),
        ("oneHour", "1h"),
        ("hour", "1h"),
        ("twoHours", "2h"),
        ("fourHours", "4h"),
        ("sixHours", "6h"),
        ("eightHours", "8h"),
        ("twelveHours", "12h"),
        ("day", "1d"),
        ("twoDays", "2d"),
        ("week", "1w"),
        ("twoWeeks", "2w"),
        ("month", "1M"),
        ("sixMonths", "6M"),
        ("year", "1y"),
    ];
    let t = named.iter().find(|(n, _)| *n == t).map_or(t, |(_, x)| *x);
    let unit = t.chars().last()?;
    let n: i64 = t[..t.len() - unit.len_utf8()]
        .parse()
        .ok()
        .filter(|n| *n >= 1 && *n <= 100_000)?;
    "smhdwMy".contains(unit).then_some((n, unit))
}

/// Rows in time buckets of `interval`, each column of `aggregates` (or every other column by
/// `method`) reduced; the bucket's start (microseconds) in `time_column`.
fn rollup(t: &Table, v: &View) -> Option<Table> {
    use super::date;
    let tcol = ptext(v, "time_column");
    if !t.columns.contains(&tcol) {
        return None;
    }
    let (n, unit) = interval(&ptext(v, "interval"))?;
    let tz = date::zone(v.p("time_zone"))?;
    let ws = date::WEEK_STARTS
        .iter()
        .position(|w| *w == ptext(v, "week_start"))
        .unwrap_or(0);
    let aggs = match aggregates(match v.p("aggregates") {
        Value::Null => None,
        x => Some(x),
    }) {
        Ok(a) if !a.is_empty() => a,
        Ok(_) => {
            let m = ptext(v, "method");
            if !METHODS.contains(&m.as_str()) {
                return None;
            }
            t.columns
                .iter()
                .filter(|c| **c != tcol)
                .map(|c| (c.clone(), m.clone(), c.clone()))
                .collect()
        }
        Err(_) => return None,
    };
    let mut timed: Vec<(i64, usize)> = t
        .rows
        .iter()
        .enumerate()
        .filter_map(|(i, r)| date::date_of(r.get(&tcol)?, &tz).map(|ts| (ts.as_microsecond(), i)))
        .collect();
    timed.sort_by_key(|(ts, i)| (*ts, *i));
    let first = timed.first()?.0;
    let span = |k: i64| -> Option<jiff::Span> {
        let s = jiff::Span::new();
        match unit {
            's' => s.try_seconds(k * n),
            'm' => s.try_minutes(k * n),
            'h' => s.try_hours(k * n),
            'd' => s.try_days(k * n),
            'w' => s.try_weeks(k * n),
            'M' => s.try_months(k * n),
            _ => s.try_years(k * n),
        }
        .ok()
    };
    let zoned = |us: i64| {
        jiff::Timestamp::from_microsecond(us)
            .ok()
            .map(|t| t.to_zoned(tz.clone()))
    };
    let z0 = zoned(first)?;
    // the first bucket: at the first row, or at the round time before it
    let start = if truth(v.p("round_time"), true) {
        let dt = z0.datetime();
        let (y, mo, d, h, mi, s) = (
            dt.year(),
            dt.month(),
            dt.day(),
            dt.hour(),
            dt.minute(),
            dt.second(),
        );
        let fl = |x: i8, n: i64| (i64::from(x) / n * n) as i8;
        let civil = match unit {
            's' => jiff::civil::DateTime::new(y, mo, d, h, mi, fl(s, n), 0),
            'm' => jiff::civil::DateTime::new(y, mo, d, h, fl(mi, n), 0, 0),
            'h' => jiff::civil::DateTime::new(y, mo, d, fl(h, n), 0, 0, 0),
            'd' => jiff::civil::DateTime::new(y, mo, d, 0, 0, 0, 0),
            'w' => {
                let back =
                    (i64::from(dt.weekday().to_monday_zero_offset()) - ws as i64).rem_euclid(7);
                Ok(dt
                    .date()
                    .checked_sub(jiff::Span::new().days(back))
                    .ok()?
                    .to_datetime(jiff::civil::Time::midnight()))
            }
            'M' => jiff::civil::DateTime::new(y, mo, 1, 0, 0, 0, 0),
            _ => jiff::civil::DateTime::new(y, 1, 1, 0, 0, 0, 0),
        }
        .ok()?;
        civil.to_zoned(tz.clone()).ok()?
    } else {
        z0
    };
    let mut cols = vec![tcol.clone()];
    cols.extend(aggs.iter().map(|(_, _, a)| a.clone()));
    let mut out = Table::new(cols);
    let mut k = 0i64;
    let mut idx = 0;
    let mut steps = 0usize;
    while idx < timed.len() {
        let b_start = start
            .checked_add(span(k)?)
            .ok()?
            .timestamp()
            .as_microsecond();
        let b_end = start
            .checked_add(span(k + 1)?)
            .ok()?
            .timestamp()
            .as_microsecond();
        let mut rows = Vec::new();
        while idx < timed.len() && timed[idx].0 < b_end {
            rows.push(timed[idx].1);
            idx += 1;
        }
        if !rows.is_empty() {
            let mut row = BTreeMap::from([(tcol.clone(), Value::Int(b_start))]);
            for (c, m, a) in &aggs {
                let cells: Vec<&Value> = rows.iter().map(|i| t.cell(*i, c)).collect();
                row.insert(a.clone(), aggregate(m, &cells));
            }
            out.rows.push(row);
            k += 1;
        } else {
            // jump over empty buckets in one step
            let gap = timed[idx].0 - b_start;
            let width = (b_end - b_start).max(1);
            k += (gap / width).max(1);
        }
        steps += 1;
        if steps > 2 * MAX_ROWS + 16 {
            return None;
        }
    }
    Some(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn map(kv: &[(&str, Value)]) -> BTreeMap<String, Value> {
        kv.iter()
            .map(|(k, v)| ((*k).to_owned(), v.clone()))
            .collect()
    }

    /// The reference's fixture `t1`: name, kw, zone.
    fn t1() -> Table {
        let r = |n: &str, kw: Value, z: &str| {
            map(&[("name", n.into()), ("kw", kw), ("zone", z.into())])
        };
        Table {
            columns: vec!["name".into(), "kw".into(), "zone".into()],
            rows: vec![
                r("pump", Value::Int(3), "A"),
                r("fan", Value::Int(7), "B"),
                r("chiller", Value::Int(12), "A"),
                r("valve", Value::Null, "B"),
            ],
        }
    }

    fn t2() -> Table {
        Table {
            columns: vec!["zone".into(), "label".into()],
            rows: vec![
                map(&[("zone", "A".into()), ("label", "Alpha".into())]),
                map(&[("zone", "C".into()), ("label", "Gamma".into())]),
            ],
        }
    }

    fn run(
        op: Op,
        inv: Value,
        kv: &[(&str, Value)],
        ins: &[(&str, Value)],
    ) -> Vec<(&'static str, Value, bool)> {
        let mut cfg: BTreeMap<String, Value> = shape(op)
            .params
            .into_iter()
            .map(|p| (p.name.to_owned(), p.default))
            .collect();
        cfg.extend(kv.iter().map(|(k, v)| ((*k).to_owned(), v.clone())));
        let sc = scripts(op, &cfg).unwrap();
        let insm = map(ins);
        calc(
            op,
            &View {
                inv: &inv,
                params: &cfg,
                items: Vec::new(),
                now_us: 0,
                ins: &insm,
            },
            sc.as_ref(),
        )
    }

    fn out_table(r: &[(&'static str, Value, bool)]) -> Table {
        Table::from_value(&r[0].1).unwrap_or_else(|| panic!("no table: {r:?}"))
    }

    fn col(t: &Table, c: &str) -> Vec<Value> {
        (0..t.rows.len()).map(|i| t.cell(i, c).clone()).collect()
    }

    fn v(t: &Table) -> Value {
        t.to_value().unwrap()
    }

    #[test]
    fn csv_both_ways() {
        let t = parse_csv("a,b\n1,2\n3,4", ',', true).unwrap();
        assert_eq!(t.columns, ["a", "b"]);
        assert_eq!(col(&t, "b"), [Value::from("2"), Value::from("4")]);
        let t = parse_csv("x;y\n1;2", ';', false).unwrap();
        assert_eq!(
            (t.columns.clone(), t.rows.len()),
            (vec!["v1".into(), "v2".into()], 2)
        );
        let t = parse_csv("a,b\n1,\"x,y\"\n", ',', true).unwrap();
        assert_eq!(col(&t, "b"), [Value::from("x,y")]);
        // the reference keeps an empty line inside, not a last one
        let t = parse_csv("a\n\nb\n", ',', false).unwrap();
        assert_eq!(
            col(&t, "v1"),
            [Value::from("a"), Value::from(""), Value::from("b")]
        );
        let t = parse_csv("\"say \"\"hi\"\"\",2\r\n", ',', false).unwrap();
        assert_eq!(col(&t, "v1"), [Value::from("say \"hi\"")]);
        assert!(parse_csv("", ',', true).is_none());
        // a name twice keeps both columns
        assert_eq!(
            parse_csv("a,a\n1,2", ',', true).unwrap().columns,
            ["a", "a_2"]
        );
        assert_eq!(
            write_csv(&t1(), ',', true),
            "name,kw,zone\npump,3,A\nfan,7,B\nchiller,12,A\nvalve,,B\n"
        );
        assert_eq!(write_csv(&t2(), ',', false), "A,Alpha\nC,Gamma\n");
        let q = Table {
            columns: vec!["a".into()],
            rows: vec![map(&[("a", "x,\"y\"".into())])],
        };
        assert_eq!(write_csv(&q, ',', false), "\"x,\"\"y\"\"\"\n");
        let r = run(Op::FromCsv, Value::Int(1), &[], &[]);
        assert_eq!(r[1].1, Value::Bool(true));
    }

    #[test]
    fn a_huge_header_is_refused_fast() {
        let started = std::time::Instant::now();
        let empty = format!("{}\n1", ",".repeat(99_999));
        let equal = format!("{}\n1", vec!["a"; 100_000].join(","));
        for text in [empty, equal] {
            let r = run(Op::FromCsv, Value::Str(text), &[], &[]);
            assert_eq!(
                (r[0].1.clone(), r[1].1.clone()),
                (Value::Null, Value::Bool(true))
            );
        }
        let long = "x".repeat(MAX_FIELD + 1);
        assert!(parse_csv(&long, ',', false).is_none());
        // a row map of 100 000 keys is no table either
        let wide = Value::Map(
            (0..100_000)
                .map(|i| (format!("k{i}"), Value::Null))
                .collect(),
        );
        assert!(Table::from_value(&Value::Array(vec![wide])).is_none());
        assert!(
            started.elapsed() < std::time::Duration::from_secs(2),
            "{:?}",
            started.elapsed()
        );
        // equal names keep their columns in one pass
        assert_eq!(
            parse_csv("a,a,a,a_2\n1,2,3,4", ',', true).unwrap().columns,
            ["a", "a_2", "a_3", "a_2_2"]
        );
    }

    #[test]
    fn json_both_ways() {
        let r = run(
            Op::FromJson,
            r#"[{"a":1,"b":"x"},{"a":2,"b":"y"}]"#.into(),
            &[],
            &[],
        );
        let t = out_table(&r);
        assert_eq!(
            (t.columns.clone(), col(&t, "a")),
            (
                vec!["a".into(), "b".into()],
                vec![Value::Int(1), Value::Int(2)]
            )
        );
        let r = run(Op::FromJson, "{".into(), &[], &[]);
        assert_eq!(
            (r[0].1.clone(), r[1].1.clone()),
            (Value::Null, Value::Bool(true))
        );
        let r = run(Op::FromJson, r#"{"r":{"v":[1,2]},"n":5}"#.into(), &[], &[]);
        assert_eq!(
            out_table(&r).columns,
            ["n", "r/v"],
            "a nested map flattens to a/b"
        );
        let r = run(
            Op::FromJson,
            r#"{"data":{"items":[{"k":1}]}}"#.into(),
            &[("selector", "data.items".into())],
            &[],
        );
        assert_eq!(col(&out_table(&r), "k"), [Value::Int(1)]);
        let r = run(Op::ToJson, v(&t2()), &[], &[]);
        assert_eq!(
            r[0].1,
            r#"[{"label":"Alpha","zone":"A"},{"label":"Gamma","zone":"C"}]"#.into()
        );
    }

    #[test]
    fn map_sort_filter_group() {
        let mapping = |pairs: &[(&str, &str)]| {
            Value::Array(
                pairs
                    .iter()
                    .map(|(n, f)| Value::Map(map(&[("name", (*n).into()), ("from", (*f).into())])))
                    .collect(),
            )
        };
        let r = run(
            Op::MapColumns,
            v(&t1()),
            &[("mapping", mapping(&[("power", "kw")]))],
            &[],
        );
        let t = out_table(&r);
        assert_eq!(
            (t.columns.clone(), col(&t, "power")),
            (
                vec!["power".into()],
                vec![Value::Int(3), Value::Int(7), Value::Int(12), Value::Null]
            )
        );
        let r = run(
            Op::MapColumns,
            v(&t1()),
            &[
                ("retain_columns", Value::Bool(true)),
                (
                    "mapping",
                    mapping(&[
                        ("label", r#"= row.name + "/" + row.zone"#),
                        ("big", "& row.kw ?? 0 > 5"),
                    ]),
                ),
            ],
            &[],
        );
        let t = out_table(&r);
        assert_eq!(t.columns, ["name", "kw", "zone", "label", "big"]);
        assert_eq!(t.cell(0, "label"), &Value::from("pump/A"));
        assert_eq!(t.cell(1, "big"), &Value::Bool(true));
        let r = run(
            Op::Sort,
            v(&t1()),
            &[("column", "kw".into()), ("order", "descending".into())],
            &[],
        );
        assert_eq!(
            col(&out_table(&r), "name"),
            ["chiller", "fan", "pump", "valve"].map(Value::from),
            "null last"
        );
        let r = run(
            Op::Sort,
            v(&t1()),
            &[("column", "name".into()), ("method", "string".into())],
            &[],
        );
        assert_eq!(
            col(&out_table(&r), "name"),
            ["chiller", "fan", "pump", "valve"].map(Value::from)
        );
        assert_eq!(natural("a10", "a2"), Ordering::Greater);
        assert_eq!(natural("A1", "a1"), Ordering::Equal);
        let r = run(
            Op::Filter,
            v(&t1()),
            &[("expr", "row.kw != () && row.kw > 5".into())],
            &[],
        );
        assert_eq!(
            col(&out_table(&r), "name"),
            ["fan", "chiller"].map(Value::from)
        );
        let r = run(
            Op::Filter,
            v(&t1()),
            &[("expr", r#"row.zone == "A""#.into())],
            &[],
        );
        assert_eq!(
            col(&out_table(&r), "name"),
            ["pump", "chiller"].map(Value::from)
        );
        let r = run(
            Op::RemoveRows,
            v(&t1()),
            &[("expr", r#"row.zone == "A""#.into())],
            &[],
        );
        assert_eq!(
            col(&out_table(&r), "name"),
            ["fan", "valve"].map(Value::from)
        );
        let r = run(
            Op::Filter,
            v(&t1()),
            &[("expr", r#"if index == 3 { throw "bad row" } true"#.into())],
            &[],
        );
        assert_eq!(r[0].1, Value::Null, "a script error: {r:?}");
        assert!(
            matches!(&r[1].1, Value::Str(e) if e.contains("row 3")),
            "{r:?}"
        );
        let aggs = Value::Array(vec![Value::Map(map(&[
            ("column", "kw".into()),
            ("method", "sum".into()),
            ("as", "total".into()),
        ]))]);
        let r = run(
            Op::GroupBy,
            v(&t1()),
            &[("column", "zone".into()), ("aggregates", aggs)],
            &[],
        );
        let t = out_table(&r);
        assert_eq!(
            (col(&t, "zone"), col(&t, "total")),
            (
                vec!["A".into(), "B".into()],
                vec![Value::Int(15), Value::Int(7)]
            )
        );
        let r = run(
            Op::EditRows,
            v(&t1()),
            &[
                ("expr", "row.name == \"fan\"".into()),
                ("cells", Value::Map(map(&[("zone", "Z".into())]))),
            ],
            &[],
        );
        assert_eq!(
            col(&out_table(&r), "zone"),
            ["A", "Z", "A", "B"].map(Value::from)
        );
    }

    #[test]
    fn joins() {
        let j = |kind: &str| {
            out_table(&run(
                Op::Join,
                v(&t1()),
                &[("column", "zone".into()), ("join", kind.into())],
                &[("right", v(&t2()))],
            ))
        };
        let l = j("left");
        assert_eq!(l.columns, ["name", "kw", "zone", "label"]);
        assert_eq!(
            col(&l, "label"),
            [
                Value::from("Alpha"),
                Value::Null,
                Value::from("Alpha"),
                Value::Null
            ]
        );
        assert_eq!(
            col(&j("inner"), "name"),
            ["pump", "chiller"].map(Value::from)
        );
        assert_eq!(
            col(&j("exclude"), "name"),
            ["fan", "valve"].map(Value::from)
        );
        let r = j("right");
        assert_eq!(
            (col(&r, "name"), col(&r, "zone")),
            (
                vec![Value::from("pump"), Value::Null],
                vec![Value::from("A"), Value::from("C")]
            )
        );
        let f = j("full");
        assert_eq!(
            col(&f, "zone"),
            ["A", "B", "C"].map(Value::from),
            "one left row per key, then the right rows none has"
        );
        assert_eq!(j("union").rows.len(), 6);
        // no right table: the left one passes
        let r = run(Op::Join, v(&t1()), &[("column", "zone".into())], &[]);
        assert_eq!(out_table(&r).rows.len(), 4);
    }

    #[test]
    fn rollups_aggregates_and_shapes() {
        let ts = |s: &str| {
            super::super::date::date_of(&s.into(), &jiff::tz::TimeZone::UTC)
                .unwrap()
                .as_microsecond()
        };
        let t3 = Table {
            columns: vec!["t".into(), "v".into()],
            rows: [
                ("2024-03-15T10:05:00Z", 1),
                ("2024-03-15T10:35:00Z", 3),
                ("2024-03-15T11:10:00Z", 5),
                ("2024-03-15T11:50:00Z", 7),
            ]
            .iter()
            .map(|(t, x)| map(&[("t", (*t).into()), ("v", Value::Int(*x))]))
            .collect(),
        };
        // from the first row's time, as the reference
        let r = run(
            Op::Rollup,
            v(&t3),
            &[("round_time", Value::Bool(false)), ("method", "sum".into())],
            &[],
        );
        let t = out_table(&r);
        assert_eq!(col(&t, "v"), [Value::Int(4), Value::Int(12)]);
        assert_eq!(
            col(&t, "t"),
            [
                Value::Int(ts("2024-03-15T10:05:00Z")),
                Value::Int(ts("2024-03-15T11:05:00Z"))
            ]
        );
        // on the hour
        let aggs = Value::Array(vec![Value::Map(map(&[
            ("column", "v".into()),
            ("method", "max".into()),
            ("as", "vmax".into()),
        ]))]);
        let t = out_table(&run(Op::Rollup, v(&t3), &[("aggregates", aggs)], &[]));
        assert_eq!(
            (col(&t, "t")[0].clone(), col(&t, "vmax")),
            (
                Value::Int(ts("2024-03-15T10:00:00Z")),
                vec![Value::Int(3), Value::Int(7)]
            )
        );
        let t = out_table(&run(Op::Rollup, v(&t3), &[("interval", "1d".into())], &[]));
        assert_eq!(
            col(&t, "v"),
            [Value::Float(4.0)],
            "the average of 1, 3, 5, 7"
        );
        let agg = |m: &str| {
            run(
                Op::Aggregate,
                v(&t1()),
                &[("column", "kw".into()), ("method", m.into())],
                &[],
            )[0]
            .1
            .clone()
        };
        assert_eq!(agg("sum"), Value::Int(22));
        assert_eq!(agg("count"), Value::UInt(3));
        assert_eq!(agg("first"), Value::Int(3));
        assert!((agg("average").as_f64().unwrap() - 22.0 / 3.0).abs() < 1e-12);
        let names = run(
            Op::Aggregate,
            v(&t1()),
            &[("column", "name".into()), ("method", "concat".into())],
            &[],
        )[0]
        .1
        .clone();
        assert_eq!(names, "pump,fan,chiller,valve".into());
        let t = out_table(&run(
            Op::SelectRows,
            v(&t1()),
            &[("indexes", "0, 2".into())],
            &[],
        ));
        assert_eq!(col(&t, "name"), ["pump", "chiller"].map(Value::from));
        let t = out_table(&run(
            Op::SelectColumns,
            v(&t1()),
            &[("columns", "zone,name,nope".into())],
            &[],
        ));
        assert_eq!(t.columns, ["zone", "name"]);
        let t = out_table(&run(Op::Columns, v(&t1()), &[], &[]));
        assert_eq!(
            col(&t, "type"),
            ["string", "number", "string"].map(Value::from)
        );
        let r = run(Op::RowCells, v(&t1()), &[("row", Value::Int(1))], &[]);
        assert_eq!(
            r[0].1,
            Value::Map(map(&[
                ("name", "fan".into()),
                ("kw", Value::Int(7)),
                ("zone", "B".into())
            ]))
        );
        assert_eq!(
            run(Op::RowCells, v(&t1()), &[("row", Value::Int(9))], &[])[0].1,
            Value::Null
        );
        let t = out_table(&run(
            Op::AddRow,
            v(&t2()),
            &[(
                "row",
                Value::Map(map(&[("zone", "D".into()), ("x", Value::Int(1))])),
            )],
            &[],
        ));
        assert_eq!(
            (t.rows.len(), t.columns.clone()),
            (3, vec!["zone".into(), "label".into(), "x".into()])
        );
        let t = out_table(&run(
            Op::Transpose,
            v(&t2()),
            &[
                ("header_column", "zone".into()),
                ("include_headers", Value::Bool(true)),
            ],
            &[],
        ));
        assert_eq!(t.columns, ["headers", "A", "C"]);
        assert_eq!(
            t.rows[0],
            map(&[
                ("headers", "label".into()),
                ("A", "Alpha".into()),
                ("C", "Gamma".into())
            ])
        );
        let t = out_table(&run(
            Op::FromMap,
            Value::Map(map(&[("a", Value::Int(1))])),
            &[],
            &[],
        ));
        assert_eq!((t.columns.clone(), t.rows.len()), (vec!["a".into()], 1));
    }

    #[test]
    fn scripts_are_checked_and_bounded() {
        let bad = map(&[("expr", "row.kw +".into())]);
        assert!(scripts(Op::Filter, &bad).is_err());
        let unknown = map(&[("expr", "kw > 5".into())]);
        assert!(
            scripts(Op::Filter, &unknown).is_err(),
            "a column is row.<name>, not a variable"
        );
        let m = map(&[(
            "mapping",
            Value::Array(vec![Value::Map(map(&[
                ("name", "x".into()),
                ("from", "= nope".into()),
            ]))]),
        )]);
        assert!(scripts(Op::MapColumns, &m).is_err());
        assert!(scripts(
            Op::GroupBy,
            &map(&[(
                "aggregates",
                Value::Array(vec![Value::Map(map(&[
                    ("column", "a".into()),
                    ("method", "pick".into())
                ]))])
            )])
        )
        .is_err());
        // a slow script ends the table, not the flow
        let rows = Table {
            columns: vec!["a".into()],
            rows: vec![map(&[("a", Value::Int(1))]); 2000],
        };
        let r = run(
            Op::Filter,
            v(&rows),
            &[(
                "expr",
                "let n = 0; for i in 0..400 { n += i; } n > 0".into(),
            )],
            &[],
        );
        assert!(r[0].1 == Value::Null || out_table(&r).rows.len() == 2000);
    }
}
