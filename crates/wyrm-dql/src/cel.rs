//! CEL (Common Expression Language, ADR 0025 D1) over a row: the `cel` crate (cel-rust) compiles
//! and runs the text; this module maps `wyrm_core::Value` to CEL values and back and binds a row's
//! variables.
//!
//! Variables of a row: `row` (a map of its columns), `meta` (a map of its node's fields), and
//! each meta field and each column whose name is an identifier on its own (`value`, `type`,
//! `unit`, `name`, …; a column wins over a meta field of the same name).

use std::collections::{BTreeMap, HashMap};
use std::sync::Arc;

use ::cel::objects::{Key, Map};
use ::cel::{Context, Program, Value as Cel};
use wyrm_core::Value;

/// Longest expression text, bytes.
pub const MAX_EXPR: usize = 1024;
/// Macros (`map`, `filter`, `all`, `exists`, `exists_one`) in one expression, chained.
pub const MAX_MACROS: usize = 4;
/// Items in one list literal.
pub const MAX_LIST_LITERAL: usize = 64;
/// Items (all levels) of one value a row binds: a larger one is `null` in CEL.
pub const MAX_VALUE_ITEMS: usize = 1000;
/// Bytes of one text or bytes value a row binds: a longer one is `null` in CEL.
pub const MAX_VALUE_BYTES: usize = 16 << 10;

/// The accumulator a macro's expansion uses; a user cannot write this name.
const ACCU: &str = "@result";

/// Bound the cost of one row before it runs, on the parsed expression (cel-rust cannot stop an
/// evaluation halfway; nested `map`s over a 30-item list took 4.8 s per row at 5 levels). In the
/// standard library only `+`, list and map literals and macros make data grow, so:
/// - no macro inside another macro's body (a chain, `l.filter(…).map(…)`, is allowed: at most
///   [`MAX_MACROS`]);
/// - no `+` and no list or map literal inside a macro's body (besides the macro's own
///   `@result + [x]`): each step of a chain gives at most what it was given;
/// - no `+` in a macro's range (besides inside a macro it chains): a range is a row variable
///   (at most [`MAX_VALUE_ITEMS`]), a literal or a chained macro's result, so one evaluation runs
///   at most `MAX_MACROS × MAX_VALUE_ITEMS` steps;
/// - a list literal holds at most [`MAX_LIST_LITERAL`] items.
///
/// Outside macros, `+` and literals grow the result by what the text (≤ 1 KiB) writes.
fn check_cost(e: &::cel::IdedExpr) -> Result<(), String> {
    let mut macros = 0;
    walk(e, false, &mut macros)
}

fn walk(e: &::cel::IdedExpr, body: bool, macros: &mut usize) -> Result<(), String> {
    use ::cel::common::ast::{EntryExpr, Expr};
    let entries = |es: &[::cel::common::ast::IdedEntryExpr], macros: &mut usize| {
        for en in es {
            match &en.expr {
                EntryExpr::MapEntry(m) => {
                    walk(&m.key, body, macros)?;
                    walk(&m.value, body, macros)?;
                }
                EntryExpr::StructField(f) => walk(&f.value, body, macros)?,
            }
        }
        Ok::<(), String>(())
    };
    match &e.expr {
        Expr::Comprehension(c) => {
            if body {
                return Err("CEL: a macro inside another macro: chain them instead \
                            (list.filter(…).map(…))"
                    .into());
            }
            *macros += 1;
            if *macros > MAX_MACROS {
                return Err(format!("CEL: at most {MAX_MACROS} macros in an expression"));
            }
            // the range may itself be a macro: a chain, outside this one's body
            if grows(&c.iter_range) {
                return Err("CEL: no + in a macro's range (it would run the macro on a \
                            longer list than a value holds)"
                    .into());
            }
            walk(&c.iter_range, false, macros)?;
            walk(&c.loop_cond, true, macros)?;
            walk(&c.loop_step, true, macros)?;
            walk(&c.result, true, macros)
        }
        Expr::Call(call) => {
            if body && call.func_name == "_+_" {
                // the expansion's own step: `@result + [x]` (map, filter) or `@result + 1`
                match call.args.as_slice() {
                    [a, b] if matches!(&a.expr, Expr::Ident(n) if n == ACCU) => match &b.expr {
                        Expr::List(l) if l.elements.len() == 1 => {
                            return walk(&l.elements[0], true, macros)
                        }
                        Expr::Literal(_) => return Ok(()),
                        _ => {}
                    },
                    _ => {}
                }
                return Err("CEL: no + inside a macro (it would grow each item)".into());
            }
            if let Some(t) = &call.target {
                walk(t, body, macros)?;
            }
            call.args.iter().try_for_each(|a| walk(a, body, macros))
        }
        Expr::List(l) => {
            if body {
                return Err("CEL: no list literal inside a macro".into());
            }
            if l.elements.len() > MAX_LIST_LITERAL {
                return Err(format!(
                    "CEL: a list literal of at most {MAX_LIST_LITERAL} items"
                ));
            }
            l.elements.iter().try_for_each(|x| walk(x, body, macros))
        }
        Expr::Map(m) => {
            if body {
                return Err("CEL: no map literal inside a macro".into());
            }
            entries(&m.entries, macros)
        }
        Expr::Struct(st) => {
            if body {
                return Err("CEL: no struct literal inside a macro".into());
            }
            entries(&st.entries, macros)
        }
        Expr::Select(sel) => walk(&sel.operand, body, macros),
        Expr::Ident(_) | Expr::Literal(_) | Expr::Unspecified => Ok(()),
    }
}

/// `e` has a `+` outside the macros it holds (their own ranges are checked when they are walked).
fn grows(e: &::cel::IdedExpr) -> bool {
    use ::cel::common::ast::{EntryExpr, Expr};
    match &e.expr {
        Expr::Comprehension(_) => false,
        Expr::Call(call) => {
            call.func_name == "_+_"
                || call.target.as_deref().is_some_and(grows)
                || call.args.iter().any(grows)
        }
        Expr::List(l) => l.elements.iter().any(grows),
        Expr::Map(m) => m.entries.iter().any(|en| match &en.expr {
            EntryExpr::MapEntry(m) => grows(&m.key) || grows(&m.value),
            EntryExpr::StructField(f) => grows(&f.value),
        }),
        Expr::Struct(st) => st.entries.iter().any(|en| match &en.expr {
            EntryExpr::MapEntry(m) => grows(&m.key) || grows(&m.value),
            EntryExpr::StructField(f) => grows(&f.value),
        }),
        Expr::Select(sel) => grows(&sel.operand),
        Expr::Ident(_) | Expr::Literal(_) | Expr::Unspecified => false,
    }
}

/// Meta fields bound as variables (always, `null` when the node has none).
pub const META_FIELDS: [&str; 10] = [
    "path", "name", "type", "unit", "writable", "is", "display", "attr", "actions", "quality",
];

/// A compiled CEL expression.
#[derive(Debug, Clone)]
pub struct Expr {
    pub src: String,
    prog: Arc<Program>,
}

impl PartialEq for Expr {
    fn eq(&self, other: &Self) -> bool {
        self.src == other.src
    }
}

impl Expr {
    pub fn compile(src: &str) -> Result<Self, String> {
        let src = src.trim();
        if src.is_empty() {
            return Err("an empty expression".into());
        }
        if src.len() > MAX_EXPR {
            return Err(format!("an expression is at most {MAX_EXPR} bytes"));
        }
        // the parser's report spans lines with a caret; its first line says what is wrong
        let prog = Program::compile(src).map_err(|e| {
            let e = e.to_string();
            format!(
                "CEL: {}",
                e.lines().next().unwrap_or(&e).trim_start_matches("ERROR: ")
            )
        })?;
        check_cost(prog.expression())?;
        Ok(Self {
            src: src.to_owned(),
            prog: Arc::new(prog),
        })
    }

    /// The variables the expression names (to subscribe columns it needs, as DSA's filter did).
    /// Names bound by macros (`list.exists(e, …)`) are reported too: the caller ignores names
    /// that are bound here or that it made itself.
    pub fn variables(&self) -> Vec<String> {
        let bound = macro_vars(&self.src);
        self.prog
            .references()
            .variables()
            .into_iter()
            .filter(|v| !bound.iter().any(|b| b == v))
            .map(str::to_owned)
            .collect()
    }
}

/// The names macros bind: `x` in `.all(x, …)`, `.exists(x, …)`, `.exists_one(x, …)`,
/// `.map(x, …)`, `.filter(x, …)`.
fn macro_vars(src: &str) -> Vec<String> {
    let mut out = Vec::new();
    for m in [".all(", ".exists(", ".exists_one(", ".map(", ".filter("] {
        for (i, _) in src.match_indices(m) {
            let rest = &src[i + m.len()..];
            if let Some((v, _)) = rest.split_once(',') {
                let v = v.trim();
                if is_ident(v) {
                    out.push(v.to_owned());
                }
            }
        }
    }
    out
}

/// Lookups of a row's variables one evaluation may make: a macro that reads a row variable in
/// its body pays one per item, so this bounds what the static check cannot see (a long range
/// made with `+`, an outer list compared on every item).
pub const MAX_LOOKUPS: u64 = 10_000;
/// The time one evaluation may take (native builds; a WASM component has its host's fuel).
#[cfg(not(target_arch = "wasm32"))]
pub const ROW_TIME: std::time::Duration = std::time::Duration::from_millis(20);

/// A row's variables, served to an evaluation through a resolver that counts its lookups (and,
/// natively, watches the clock): past the bound every variable is gone, so the evaluation stops
/// at its next lookup with an error, `too costly`. cel-rust has no other way to stop one.
pub struct Row {
    vars: HashMap<String, Cel>,
    lookups: std::sync::atomic::AtomicU64,
    over: std::sync::atomic::AtomicBool,
    #[cfg(not(target_arch = "wasm32"))]
    deadline: std::sync::Mutex<std::time::Instant>,
}

impl Row {
    pub fn new(meta: &BTreeMap<String, Value>, cols: &[(String, Value)]) -> Self {
        let mut vars = HashMap::with_capacity(META_FIELDS.len() + cols.len() + 2);
        let mut row = HashMap::with_capacity(cols.len());
        for f in META_FIELDS {
            vars.insert(f.to_owned(), meta.get(f).map(to_cel).unwrap_or(Cel::Null));
        }
        vars.insert("meta".to_owned(), to_cel(&Value::Map(meta.clone())));
        for (k, v) in cols {
            let cv = to_cel(v);
            if is_ident(k) {
                vars.insert(k.clone(), cv.clone());
            }
            if k.len() <= MAX_VALUE_BYTES {
                row.insert(Key::String(Arc::new(k.clone())), cv);
            }
        }
        vars.insert("row".to_owned(), Cel::Map(Map { map: Arc::new(row) }));
        Row {
            vars,
            lookups: Default::default(),
            over: Default::default(),
            #[cfg(not(target_arch = "wasm32"))]
            deadline: std::sync::Mutex::new(std::time::Instant::now()),
        }
    }

    /// Evaluate `e` over this row; `base` holds CEL's functions.
    pub fn eval(&self, base: &Context<'static, 'static>, e: &Expr) -> Result<Value, String> {
        use std::sync::atomic::Ordering::Relaxed;
        self.lookups.store(0, Relaxed);
        self.over.store(false, Relaxed);
        #[cfg(not(target_arch = "wasm32"))]
        {
            *self.deadline.lock().unwrap_or_else(|p| p.into_inner()) =
                std::time::Instant::now() + ROW_TIME;
        }
        let base: &Context<'static, '_> = base;
        let mut c = base.new_inner_scope();
        c.set_variable_resolver(self);
        let r = e.prog.execute(&c);
        if self.over.load(Relaxed) {
            return Err(format!(
                "CEL: too costly for one row ({MAX_LOOKUPS} variable lookups or the time bound)"
            ));
        }
        from_cel(r.map_err(|e| e.to_string())?)
    }

    fn spent(&self) -> bool {
        use std::sync::atomic::Ordering::Relaxed;
        if self.lookups.fetch_add(1, Relaxed) >= MAX_LOOKUPS {
            return true;
        }
        #[cfg(not(target_arch = "wasm32"))]
        if std::time::Instant::now() > *self.deadline.lock().unwrap_or_else(|p| p.into_inner()) {
            return true;
        }
        false
    }
}

impl ::cel::context::VariableResolver for Row {
    fn resolve<'b>(&'b self, name: &str) -> Option<::cel::common::value::CowVal<'b, 'b>> {
        let v = self.vars.get(name)?;
        if self.spent() {
            self.over.store(true, std::sync::atomic::Ordering::Relaxed);
            return None;
        }
        v.clone()
            .try_into()
            .ok()
            .map(::cel::common::value::CowVal::Owned)
    }
}

/// A CEL identifier, not a reserved word.
pub fn is_ident(s: &str) -> bool {
    let mut cs = s.chars();
    matches!(cs.next(), Some(c) if c.is_ascii_alphabetic() || c == '_')
        && cs.all(|c| c.is_ascii_alphanumeric() || c == '_')
        && !matches!(
            s,
            "true"
                | "false"
                | "null"
                | "in"
                | "as"
                | "break"
                | "const"
                | "continue"
                | "else"
                | "for"
                | "function"
                | "if"
                | "import"
                | "let"
                | "loop"
                | "package"
                | "namespace"
                | "return"
                | "var"
                | "void"
                | "while"
                | "meta"
                | "row"
        )
}

/// A value as CEL; one of more than [`MAX_VALUE_ITEMS`] items (all levels; text, bytes and map
/// keys count one per 16 bytes), or a text or bytes value over [`MAX_VALUE_BYTES`], is `null`.
pub fn to_cel(v: &Value) -> Cel {
    if items(v, MAX_VALUE_ITEMS + 1) > MAX_VALUE_ITEMS {
        return Cel::Null;
    }
    to_cel_all(v)
}

/// Items of `v` at every level, counted up to `stop`; text, bytes and map keys count one item
/// per 16 bytes, so the bytes of a value are bounded with its items.
fn items(v: &Value, stop: usize) -> usize {
    let mut n = 0;
    let mut todo = vec![v];
    while let Some(v) = todo.pop() {
        match v {
            Value::Array(a) => {
                n += a.len();
                todo.extend(a.iter());
            }
            Value::Map(m) => {
                n += m.len() + m.keys().map(|k| k.len() / 16).sum::<usize>();
                todo.extend(m.values());
            }
            Value::Str(s) => n += s.len() / 16,
            Value::Bytes(b) => n += b.len() / 16,
            _ => {}
        }
        if n >= stop {
            break;
        }
    }
    n
}

fn to_cel_all(v: &Value) -> Cel {
    match v {
        Value::Null => Cel::Null,
        Value::Bool(b) => Cel::Bool(*b),
        Value::Int(i) => Cel::Int(*i),
        Value::UInt(u) => Cel::UInt(*u),
        Value::Float(f) => Cel::Float(*f),
        Value::Str(s) if s.len() > MAX_VALUE_BYTES => Cel::Null,
        Value::Bytes(b) if b.len() > MAX_VALUE_BYTES => Cel::Null,
        Value::Str(s) => Cel::String(Arc::new(s.clone())),
        Value::Bytes(b) => Cel::Bytes(Arc::new(b.clone())),
        Value::Array(a) => Cel::List(Arc::new(a.iter().map(to_cel_all).collect())),
        Value::Map(m) => Cel::Map(Map {
            map: Arc::new(
                m.iter()
                    .map(|(k, v)| (Key::String(Arc::new(k.clone())), to_cel_all(v)))
                    .collect(),
            ),
        }),
    }
}

/// A CEL result as a value, within the bounds of a bound value; a function, an opaque or a
/// struct value is an error. Map keys become text.
pub fn from_cel(v: Cel) -> Result<Value, String> {
    let v = from_cel_all(v)?;
    if items(&v, MAX_VALUE_ITEMS + 1) > MAX_VALUE_ITEMS {
        return Err(format!(
            "a result of more than {MAX_VALUE_ITEMS} items (text counts one per 16 bytes)"
        ));
    }
    Ok(v)
}

fn from_cel_all(v: Cel) -> Result<Value, String> {
    Ok(match v {
        Cel::Null => Value::Null,
        Cel::Bool(b) => Value::Bool(b),
        Cel::Int(i) => Value::Int(i),
        Cel::UInt(u) => Value::UInt(u),
        Cel::Float(f) if f.is_finite() => Value::Float(f),
        Cel::Float(_) => return Err("not a finite number".into()),
        Cel::String(s) => Value::Str(s.as_ref().clone()),
        Cel::Bytes(b) => Value::Bytes(b.as_ref().clone()),
        Cel::List(l) => Value::Array(
            l.iter()
                .cloned()
                .map(from_cel_all)
                .collect::<Result<_, _>>()?,
        ),
        Cel::Map(m) => {
            let mut out = BTreeMap::new();
            for (k, v) in m.map.iter() {
                let k = match k {
                    Key::String(s) => s.as_ref().clone(),
                    Key::Int(i) => i.to_string(),
                    Key::Uint(u) => u.to_string(),
                    Key::Bool(b) => b.to_string(),
                };
                out.insert(k, from_cel_all(v.clone())?);
            }
            Value::Map(out)
        }
        Cel::Function(name, _) => return Err(format!("a function ({name}), not a value")),
        Cel::Opaque(_) | Cel::Struct(_) => return Err("not a plain value".into()),
    })
}

/// The base context: CEL's standard functions, no variables.
pub fn base() -> Context<'static, 'static> {
    Context::default()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn meta(pairs: &[(&str, Value)]) -> BTreeMap<String, Value> {
        pairs
            .iter()
            .map(|(k, v)| ((*k).to_owned(), v.clone()))
            .collect()
    }

    #[test]
    fn rows_bind_columns_and_meta() {
        let b = base();
        let m = meta(&[
            ("type", Value::Str("number".into())),
            (
                "attr",
                Value::Map([("unit".to_owned(), Value::Str("%".into()))].into()),
            ),
        ]);
        let cols = vec![
            ("value".to_owned(), Value::Float(21.5)),
            ("value.timestamp".to_owned(), Value::Int(7)),
        ];
        let r = Row::new(&m, &cols);
        let t = |src: &str| r.eval(&b, &Expr::compile(src).unwrap());
        assert_eq!(t("value > 20 && type == 'number'"), Ok(Value::Bool(true)));
        assert_eq!(t("row['value.timestamp']"), Ok(Value::Int(7)));
        assert_eq!(t("attr.unit != '%'"), Ok(Value::Bool(false)));
        assert_eq!(t("unit == null"), Ok(Value::Bool(true)));
        assert_eq!(t("value * 2.0"), Ok(Value::Float(43.0)));
        assert_eq!(t("string(value) + ' C'"), Ok(Value::Str("21.5 C".into())));
        assert!(t("nope > 1").is_err());
        assert!(t("attr.missing").is_err());
        assert!(Expr::compile("1 +").is_err());
        assert!(Expr::compile(&"1+".repeat(600)).is_err());
        let vars = Expr::compile("value > x && row.y").unwrap().variables();
        assert!(vars.contains(&"value".to_owned()) && vars.contains(&"x".to_owned()));
        let vars = Expr::compile("[1, 2].exists(e, e > value)")
            .unwrap()
            .variables();
        assert_eq!(vars, vec!["value".to_owned()]);
        let e = Expr::compile("1 +").unwrap_err();
        assert!(e.starts_with("CEL: ") && !e.contains('\n'), "{e}");
    }

    #[test]
    fn the_cost_of_a_row_is_bounded() {
        let refused = |src: &str, why: &str| {
            let e = Expr::compile(src).unwrap_err();
            assert!(e.contains(why), "{src}: {e}");
        };
        // the reviewer's case: nested maps over a 30-item list, 4.8 s per row at 5 levels
        let list: Vec<String> = (0..30).map(|i| i.to_string()).collect();
        let l = format!("[{}]", list.join(","));
        refused(
            &format!("{l}.map(a, {l}.map(b, a + b))"),
            "inside another macro",
        );
        refused(
            &format!("{l}.exists(a, {l}.all(b, b < a))"),
            "inside another macro",
        );
        // what fooled a scan of the text: spaces, raw strings, comments
        refused(
            &format!("{l}.map (a, {l}. map(b, b))"),
            "inside another macro",
        );
        refused(
            &format!("r'\\' == '' || {l}.map(a, {l}.map(b, b)).size() > 0 || '' == ''"),
            "inside another macro",
        );
        refused(
            &format!("{l}.map(a, // note\n {l}.map(b, b)).size() > 0"),
            "inside another macro",
        );
        // a chain that doubles each item every step: exponential
        refused(
            &format!("{l}.map(a, [a]).map(b, b + b)"),
            "no list literal inside a macro",
        );
        let doubling = format!("{l}.map(a, a){}", ".map(b, b + b)".repeat(40));
        refused(&doubling, "at most 4 macros");
        refused(
            &format!("{l}.map(a, string(a)).map(b, b + b)"),
            "no + inside a macro",
        );
        refused("['x'].map(b, b + b)", "no + inside a macro");
        // a range made longer than a value with `+`: 30 copies of a 1 000-item list
        let range = vec!["l"; 30].join(" + ");
        refused(
            &format!("({range}).map(a, a).size() > 0"),
            "in a macro's range",
        );
        refused(
            "[1].map(a, a).size() > 0 && (l + [1]).exists(a, a > 0)",
            "in a macro's range",
        );
        // a chained macro in a range is fine: its own range is checked
        Expr::compile("l.filter(a, a > 1).map(a, a * 2).size() > 0").unwrap();
        refused(
            &format!("{l}.map(a, {{'k': a}})"),
            "no map literal inside a macro",
        );
        // a chain without growth is linear: allowed, up to 4 macros
        Expr::compile(&format!(
            "{l}.filter(a, a > 3).map(a, a * 2).exists(a, a == 8)"
        ))
        .unwrap();
        refused(
            &format!("{l}{}.size()", ".filter(a, a > 1)".repeat(5)),
            "at most 4 macros",
        );
        // macros over values, exists_one, has: fine
        Expr::compile("attr.history.exists(h, h.startsWith('wy/'))").unwrap();
        Expr::compile("attr.history.exists_one(h, h.endsWith('/w1'))").unwrap();
        Expr::compile("has(attr.unit) && name + ' ' + unit != ''").unwrap();
        // list literals
        let big: Vec<String> = (0..65).map(|i| i.to_string()).collect();
        refused(&format!("[{}].size() > 0", big.join(",")), "list literal");
        Expr::compile(&format!("[{}].size() > 0", big[..64].join(","))).unwrap();
        // a huge value is null in CEL
        let huge = Value::Array((0..2000).map(Value::Int).collect());
        assert_eq!(to_cel(&huge), Cel::Null);
        let ok = Value::Array((0..10).map(Value::Int).collect());
        assert!(matches!(to_cel(&ok), Cel::List(_)));
        assert_eq!(to_cel(&Value::Str("x".repeat(17 << 10))), Cel::Null);
    }

    /// The dearest expression the bounds let through, on the largest values they let in: it
    /// must stay far below a row's share of an event.
    #[test]
    fn the_dearest_allowed_row_is_cheap() {
        // on the stack the portable runtime gives an engine (8 MiB): a debug build recurses deep
        let t = std::thread::Builder::new()
            .stack_size(8 << 20)
            .spawn(dearest_allowed_row)
            .unwrap();
        t.join().unwrap();
    }

    fn dearest_allowed_row() {
        let b = base();
        let list = Value::Array((0..MAX_VALUE_ITEMS as i64).map(Value::Int).collect());
        // the most text a value may hold: one item per 16 bytes, at most MAX_VALUE_ITEMS
        let text = Value::Str("x".repeat(MAX_VALUE_ITEMS * 16 - 16));
        let cols = vec![("l".to_owned(), list), ("s".to_owned(), text)];
        let r = Row::new(&BTreeMap::new(), &cols);
        let chain = "l.filter(a, a % 2 == 0).map(a, a * 3).filter(a, a > 10).exists(a, a == 2994)";
        let concat = vec!["s"; 60].join(" + ");
        let src = format!("{chain} && size({concat}) > 0");
        assert!(src.len() <= MAX_EXPR, "{}", src.len());
        let e = Expr::compile(&src).unwrap();
        let t = std::time::Instant::now();
        for _ in 0..10 {
            assert_eq!(r.eval(&b, &e), Ok(Value::Bool(true)));
        }
        let per_row = t.elapsed() / 10;
        // debug build; a release build is several times faster
        assert!(
            per_row < std::time::Duration::from_millis(50),
            "{per_row:?} per row"
        );
    }

    /// What the static check lets through and only the run can see: a row variable read on every
    /// item of a long range. The lookups stop it, with an error, quickly.
    #[test]
    fn a_costly_row_stops_at_its_lookups() {
        let b = base();
        let list = Value::Array((0..900).map(Value::Int).collect());
        let text = Value::Str("ab".repeat(4000));
        let cols = vec![("l".to_owned(), list), ("s".to_owned(), text)];
        let r = Row::new(&BTreeMap::new(), &cols);
        // `l` compared with itself on every item: never true, so `exists` goes through every
        // item, 13 lookups each
        let pairs = ["l == l"; 6].join(" && ");
        let e = Expr::compile(&format!("l.exists(a, {pairs} && s.matches('c'))")).unwrap();
        let t = std::time::Instant::now();
        let err = r.eval(&b, &e).unwrap_err();
        assert!(err.contains("too costly"), "{err}");
        assert!(
            t.elapsed() < std::time::Duration::from_millis(500),
            "{:?}",
            t.elapsed()
        );
        // the same row answers a cheap expression right after (the bound resets)
        assert_eq!(
            r.eval(&b, &Expr::compile("size(l) == 900").unwrap()),
            Ok(Value::Bool(true))
        );
        // a result past the bound of a value is an error, not a large row
        // (two copies: 1 800 items, cheap enough to stay below the time bound on a slow runner)
        let big = Expr::compile("l + l").unwrap();
        assert!(r.eval(&b, &big).unwrap_err().contains("more than"));
        // map keys and text count toward a value's size
        let wide = Value::Map(
            (0..200)
                .map(|i| (format!("{i}{}", "k".repeat(200)), Value::Null))
                .collect(),
        );
        assert_eq!(to_cel(&wide), Cel::Null);
    }

    #[test]
    fn values_round_trip() {
        let v = Value::Map(
            [
                (
                    "a".to_owned(),
                    Value::Array(vec![Value::Int(1), Value::Null]),
                ),
                ("b".to_owned(), Value::Bytes(vec![1])),
            ]
            .into(),
        );
        assert_eq!(from_cel(to_cel(&v)).unwrap(), v);
        assert!(from_cel(Cel::Float(f64::NAN)).is_err());
    }
}
