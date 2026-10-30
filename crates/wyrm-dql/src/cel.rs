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

    pub fn eval(&self, ctx: &Context<'_, '_>) -> Result<Value, String> {
        let v = self.prog.execute(ctx).map_err(|e| e.to_string())?;
        from_cel(v)
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

/// A row's variables, bound in a child scope of `base` (which holds CEL's functions).
pub fn scope<'a>(
    base: &'a Context<'static, 'static>,
    meta: &BTreeMap<String, Value>,
    cols: &[(String, Value)],
) -> Context<'a, 'static> {
    let mut c = base.new_inner_scope();
    let mut row = HashMap::with_capacity(cols.len());
    for f in META_FIELDS {
        c.add_variable_from_value(f, meta.get(f).map(to_cel).unwrap_or(Cel::Null));
    }
    c.add_variable_from_value("meta", to_cel(&Value::Map(meta.clone())));
    for (k, v) in cols {
        let cv = to_cel(v);
        if is_ident(k) {
            c.add_variable_from_value(k.as_str(), cv.clone());
        }
        row.insert(Key::String(Arc::new(k.clone())), cv);
    }
    c.add_variable_from_value("row", Cel::Map(Map { map: Arc::new(row) }));
    c
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

pub fn to_cel(v: &Value) -> Cel {
    match v {
        Value::Null => Cel::Null,
        Value::Bool(b) => Cel::Bool(*b),
        Value::Int(i) => Cel::Int(*i),
        Value::UInt(u) => Cel::UInt(*u),
        Value::Float(f) => Cel::Float(*f),
        Value::Str(s) => Cel::String(Arc::new(s.clone())),
        Value::Bytes(b) => Cel::Bytes(Arc::new(b.clone())),
        Value::Array(a) => Cel::List(Arc::new(a.iter().map(to_cel).collect())),
        Value::Map(m) => Cel::Map(Map {
            map: Arc::new(
                m.iter()
                    .map(|(k, v)| (Key::String(Arc::new(k.clone())), to_cel(v)))
                    .collect(),
            ),
        }),
    }
}

/// A CEL result as a value; a function, an opaque or a struct value is an error. Map keys
/// become text.
pub fn from_cel(v: Cel) -> Result<Value, String> {
    Ok(match v {
        Cel::Null => Value::Null,
        Cel::Bool(b) => Value::Bool(b),
        Cel::Int(i) => Value::Int(i),
        Cel::UInt(u) => Value::UInt(u),
        Cel::Float(f) if f.is_finite() => Value::Float(f),
        Cel::Float(_) => return Err("not a finite number".into()),
        Cel::String(s) => Value::Str(s.as_ref().clone()),
        Cel::Bytes(b) => Value::Bytes(b.as_ref().clone()),
        Cel::List(l) => Value::Array(l.iter().cloned().map(from_cel).collect::<Result<_, _>>()?),
        Cel::Map(m) => {
            let mut out = BTreeMap::new();
            for (k, v) in m.map.iter() {
                let k = match k {
                    Key::String(s) => s.as_ref().clone(),
                    Key::Int(i) => i.to_string(),
                    Key::Uint(u) => u.to_string(),
                    Key::Bool(b) => b.to_string(),
                };
                out.insert(k, from_cel(v.clone())?);
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
        let c = scope(&b, &m, &cols);
        let t = |src: &str| Expr::compile(src).unwrap().eval(&c);
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
