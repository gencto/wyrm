//! A JSONPath subset (RFC 9535 syntax) that selects values in a JSON reply.
//!
//! ```text
//! $.a.b            member names (letters, digits, `_`, `-`)
//! $['a b']         a quoted member name ('…' or "…", `\` escapes)
//! $.items[0]       an array index (negative: from the end)
//! $.items[*]  $.*  every element or member value
//! $.items[?(@.id=="x")].v     a filter: elements whose relative path
//! $.items[?@.v > 2]           compares (== != < <= > >=) with a literal
//! $.items[?(@.ok)]            (string, number, true, false, null), or
//!                             exists without a comparison
//! ```
//!
//! Not supported: recursive descent (`..`), slices (`[1:3]`), unions
//! (`[0,1]`), functions, and `&&`/`||` in filters. A selector without
//! `[*]`, `.*` or a filter is singular: it selects at most one value.
//!
//! Written in the crate (about 300 lines with tests) rather than taken from
//! `serde_json_path`, which brings `nom`, `inventory` (link-time
//! registration) and a proc-macro crate for features this link does not use.

use serde_json::Value as Json;

/// Longest selector text accepted.
pub const MAX_LEN: usize = 512;
/// Most segments in a selector (and steps in a filter path).
pub const MAX_SEGMENTS: usize = 32;

/// A parsed selector.
#[derive(Debug, Clone, PartialEq)]
pub struct Selector {
    segs: Vec<Seg>,
}

#[derive(Debug, Clone, PartialEq)]
enum Seg {
    Key(String),
    Index(i64),
    Wild,
    Filter(Filter),
}

#[derive(Debug, Clone, PartialEq)]
enum Step {
    Key(String),
    Index(i64),
}

#[derive(Debug, Clone, PartialEq)]
struct Filter {
    path: Vec<Step>,
    cmp: Option<(Op, Json)>,
}

#[derive(Debug, Clone, Copy, PartialEq)]
enum Op {
    Eq,
    Ne,
    Lt,
    Le,
    Gt,
    Ge,
}

struct Parser<'a> {
    s: &'a [u8],
    i: usize,
}

impl Parser<'_> {
    fn peek(&self) -> Option<u8> {
        self.s.get(self.i).copied()
    }

    fn eat(&mut self, c: u8) -> bool {
        if self.peek() == Some(c) {
            self.i += 1;
            true
        } else {
            false
        }
    }

    fn ws(&mut self) {
        while matches!(self.peek(), Some(b' ' | b'\t')) {
            self.i += 1;
        }
    }

    fn err(&self, what: &str) -> String {
        format!("{what} at position {}", self.i)
    }

    fn expect(&mut self, c: u8) -> Result<(), String> {
        if self.eat(c) {
            Ok(())
        } else {
            Err(self.err(&format!("expected '{}'", c as char)))
        }
    }

    fn name(&mut self) -> Result<String, String> {
        let start = self.i;
        while matches!(self.peek(), Some(c) if c.is_ascii_alphanumeric() || c == b'_' || c == b'-')
        {
            self.i += 1;
        }
        if start == self.i {
            return Err(self.err("expected a member name"));
        }
        Ok(String::from_utf8_lossy(&self.s[start..self.i]).into_owned())
    }

    fn quoted(&mut self) -> Result<String, String> {
        let q = self.peek().ok_or_else(|| self.err("expected a quote"))?;
        self.i += 1;
        let mut out = Vec::new();
        loop {
            match self.peek() {
                None => return Err(self.err("unterminated string")),
                Some(c) if c == q => {
                    self.i += 1;
                    break;
                }
                Some(b'\\') => {
                    self.i += 1;
                    let c = self.peek().ok_or_else(|| self.err("unterminated string"))?;
                    out.push(match c {
                        b'n' => b'\n',
                        b't' => b'\t',
                        b'r' => b'\r',
                        c => c,
                    });
                    self.i += 1;
                }
                Some(c) => {
                    out.push(c);
                    self.i += 1;
                }
            }
        }
        String::from_utf8(out).map_err(|_| self.err("string is not UTF-8"))
    }

    fn int(&mut self) -> Result<i64, String> {
        let start = self.i;
        self.eat(b'-');
        while matches!(self.peek(), Some(c) if c.is_ascii_digit()) {
            self.i += 1;
        }
        std::str::from_utf8(&self.s[start..self.i])
            .ok()
            .and_then(|t| t.parse().ok())
            .ok_or_else(|| self.err("expected an index"))
    }

    /// A literal of a filter comparison.
    fn literal(&mut self) -> Result<Json, String> {
        match self.peek() {
            Some(b'"' | b'\'') => self.quoted().map(Json::String),
            Some(c) if c == b'-' || c.is_ascii_digit() => {
                let start = self.i;
                while matches!(self.peek(), Some(c) if c.is_ascii_digit() || matches!(c, b'-' | b'+' | b'.' | b'e' | b'E'))
                {
                    self.i += 1;
                }
                std::str::from_utf8(&self.s[start..self.i])
                    .ok()
                    .and_then(|t| t.parse::<f64>().ok())
                    .and_then(serde_json::Number::from_f64)
                    .map(Json::Number)
                    .ok_or_else(|| self.err("bad number"))
            }
            _ => {
                for (word, v) in [
                    ("true", Json::Bool(true)),
                    ("false", Json::Bool(false)),
                    ("null", Json::Null),
                ] {
                    if self.s[self.i..].starts_with(word.as_bytes()) {
                        self.i += word.len();
                        return Ok(v);
                    }
                }
                Err(self.err("expected a literal (string, number, true, false, null)"))
            }
        }
    }

    fn op(&mut self) -> Option<Op> {
        let two = |p: &Self, a: u8, b: u8| p.s.get(p.i) == Some(&a) && p.s.get(p.i + 1) == Some(&b);
        let (op, n) = if two(self, b'=', b'=') {
            (Op::Eq, 2)
        } else if two(self, b'!', b'=') {
            (Op::Ne, 2)
        } else if two(self, b'<', b'=') {
            (Op::Le, 2)
        } else if two(self, b'>', b'=') {
            (Op::Ge, 2)
        } else if self.peek() == Some(b'<') {
            (Op::Lt, 1)
        } else if self.peek() == Some(b'>') {
            (Op::Gt, 1)
        } else {
            return None;
        };
        self.i += n;
        Some(op)
    }

    /// `@` followed by `.name`, `['name']` or `[n]` steps.
    fn rel_path(&mut self) -> Result<Vec<Step>, String> {
        self.expect(b'@')?;
        let mut steps = Vec::new();
        loop {
            if steps.len() > MAX_SEGMENTS {
                return Err(self.err("filter path too long"));
            }
            if self.eat(b'.') {
                steps.push(Step::Key(self.name()?));
            } else if self.peek() == Some(b'[') {
                self.i += 1;
                self.ws();
                let step = match self.peek() {
                    Some(b'"' | b'\'') => Step::Key(self.quoted()?),
                    _ => Step::Index(self.int()?),
                };
                self.ws();
                self.expect(b']')?;
                steps.push(step);
            } else {
                return Ok(steps);
            }
        }
    }

    fn filter(&mut self) -> Result<Filter, String> {
        self.ws();
        let paren = self.eat(b'(');
        self.ws();
        let path = self.rel_path()?;
        self.ws();
        let cmp = match self.op() {
            None => None,
            Some(op) => {
                self.ws();
                Some((op, self.literal()?))
            }
        };
        self.ws();
        if paren {
            self.expect(b')')?;
            self.ws();
        }
        Ok(Filter { path, cmp })
    }
}

impl Selector {
    pub fn parse(text: &str) -> Result<Self, String> {
        if text.len() > MAX_LEN {
            return Err(format!("longer than {MAX_LEN} characters"));
        }
        let mut p = Parser {
            s: text.as_bytes(),
            i: 0,
        };
        p.ws();
        if !p.eat(b'$') {
            return Err("must start with $".into());
        }
        let mut segs = Vec::new();
        loop {
            if segs.len() > MAX_SEGMENTS {
                return Err(format!("more than {MAX_SEGMENTS} segments"));
            }
            match p.peek() {
                None => break,
                Some(b' ' | b'\t') => {
                    p.ws();
                    if p.peek().is_some() {
                        return Err(p.err("unexpected text"));
                    }
                }
                Some(b'.') => {
                    p.i += 1;
                    if p.eat(b'.') {
                        return Err(p.err("recursive descent (..) is not supported"));
                    }
                    if p.eat(b'*') {
                        segs.push(Seg::Wild);
                    } else {
                        segs.push(Seg::Key(p.name()?));
                    }
                }
                Some(b'[') => {
                    p.i += 1;
                    p.ws();
                    let seg = match p.peek() {
                        Some(b'*') => {
                            p.i += 1;
                            Seg::Wild
                        }
                        Some(b'?') => {
                            p.i += 1;
                            Seg::Filter(p.filter()?)
                        }
                        Some(b'"' | b'\'') => Seg::Key(p.quoted()?),
                        _ => Seg::Index(p.int()?),
                    };
                    p.ws();
                    if matches!(p.peek(), Some(b':' | b',')) {
                        return Err(p.err("slices and unions are not supported"));
                    }
                    p.expect(b']')?;
                    segs.push(seg);
                }
                Some(_) => return Err(p.err("unexpected character")),
            }
        }
        Ok(Selector { segs })
    }

    /// At most one value (no wildcard, no filter).
    pub fn is_singular(&self) -> bool {
        self.segs
            .iter()
            .all(|s| matches!(s, Seg::Key(_) | Seg::Index(_)))
    }

    /// Every value the selector finds in `root`, in document order.
    pub fn select<'a>(&self, root: &'a Json) -> Vec<&'a Json> {
        self.select_masked(root, &|_| false).0
    }

    /// [`Selector::select`], and whether a filter compared (`==`, `<`, …)
    /// a value for which `masked` is true: that answer says nothing true
    /// about the value (a masked secret), so the caller fails the result
    /// instead of showing a count or a match that may be wrong.
    pub fn select_masked<'a>(
        &self,
        root: &'a Json,
        masked: &dyn Fn(&Json) -> bool,
    ) -> (Vec<&'a Json>, bool) {
        let mut hidden = false;
        let mut cur = vec![root];
        for seg in &self.segs {
            let mut next = Vec::new();
            for v in cur {
                match seg {
                    Seg::Key(k) => next.extend(v.get(k.as_str())),
                    Seg::Index(i) => next.extend(index(v, *i)),
                    Seg::Wild => children(v, &mut next),
                    Seg::Filter(f) => {
                        let mut all = Vec::new();
                        children(v, &mut all);
                        for c in all {
                            if f.test(c, masked, &mut hidden) {
                                next.push(c);
                            }
                        }
                    }
                }
            }
            cur = next;
            if cur.is_empty() {
                break;
            }
        }
        (cur, hidden)
    }
}

fn index(v: &Json, i: i64) -> Option<&Json> {
    let a = v.as_array()?;
    let len = i64::try_from(a.len()).ok()?;
    let i = if i < 0 { len + i } else { i };
    usize::try_from(i).ok().and_then(|i| a.get(i))
}

fn children<'a>(v: &'a Json, out: &mut Vec<&'a Json>) {
    match v {
        Json::Array(a) => out.extend(a.iter()),
        Json::Object(o) => out.extend(o.values()),
        _ => {}
    }
}

impl Filter {
    /// Whether `v` passes; `hidden` is set when a comparison met a value
    /// for which `masked` is true.
    fn test(&self, v: &Json, masked: &dyn Fn(&Json) -> bool, hidden: &mut bool) -> bool {
        let mut cur = Some(v);
        for s in &self.path {
            cur = cur.and_then(|c| match s {
                Step::Key(k) => c.get(k.as_str()),
                Step::Index(i) => index(c, *i),
            });
        }
        let Some((op, lit)) = &self.cmp else {
            return cur.is_some();
        };
        let Some(got) = cur else {
            // RFC 9535: an absent value is unequal to every literal.
            return *op == Op::Ne;
        };
        if masked(got) {
            *hidden = true;
        }
        match op {
            Op::Eq => same(got, lit),
            Op::Ne => !same(got, lit),
            _ => {
                let ord = match (got, lit) {
                    (Json::Number(a), Json::Number(b)) => a
                        .as_f64()
                        .zip(b.as_f64())
                        .and_then(|(a, b)| a.partial_cmp(&b)),
                    (Json::String(a), Json::String(b)) => Some(a.cmp(b)),
                    _ => None,
                };
                let Some(ord) = ord else { return false };
                match op {
                    Op::Lt => ord.is_lt(),
                    Op::Le => ord.is_le(),
                    Op::Gt => ord.is_gt(),
                    _ => ord.is_ge(),
                }
            }
        }
    }
}

/// Equality with numbers compared by value (`1` equals `1.0`).
fn same(a: &Json, b: &Json) -> bool {
    match (a, b) {
        (Json::Number(x), Json::Number(y)) => x.as_f64() == y.as_f64(),
        _ => a == b,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn a_filter_on_a_masked_value_is_reported() {
        let d = json!({"items": [{"id": "***", "v": 1}, {"id": 7, "v": 2}], "m": "***"});
        let masked = |j: &Json| j == &json!("***");
        let flag = |s: &str| Selector::parse(s).unwrap().select_masked(&d, &masked).1;
        assert!(flag(r#"$.items[?(@.id == 7)]"#), "compared a masked id");
        assert!(flag(r#"$.items[?(@.id > "a")].v"#));
        assert!(!flag("$.items[?(@.v > 1)]"), "no masked value compared");
        assert!(!flag("$.items[?(@.id)]"), "existence compares nothing");
        assert!(!flag("$.m"), "selected, not compared");
        let (found, hidden) = Selector::parse("$.items[?(@.v > 1)].id")
            .unwrap()
            .select_masked(&d, &masked);
        assert_eq!((found, hidden), (vec![&json!(7)], false));
    }

    fn doc() -> Json {
        json!({
            "a": {"b": 3, "c d": "x"},
            "items": [
                {"id": "x", "v": 1.5, "ok": true},
                {"id": "y", "v": 2.5},
                {"id": "z", "v": 4}
            ],
            "n": [10, 20, 30]
        })
    }

    fn sel(s: &str) -> Vec<Json> {
        let d = doc();
        Selector::parse(s)
            .unwrap_or_else(|e| panic!("{s}: {e}"))
            .select(&d)
            .into_iter()
            .cloned()
            .collect()
    }

    #[test]
    fn the_brief_examples() {
        assert_eq!(sel("$.a.b"), vec![json!(3)]);
        assert_eq!(sel("$.items[0].v"), vec![json!(1.5)]);
        assert_eq!(sel("$.items[?(@.id==\"x\")].v"), vec![json!(1.5)]);
        assert_eq!(sel("$.items[*].v"), vec![json!(1.5), json!(2.5), json!(4)]);
    }

    #[test]
    fn names_indexes_and_wildcards() {
        assert_eq!(sel("$"), vec![doc()]);
        assert_eq!(sel("$['a']['c d']"), vec![json!("x")]);
        assert_eq!(sel("$[\"a\"].b"), vec![json!(3)]);
        assert_eq!(sel("$.n[-1]"), vec![json!(30)]);
        assert_eq!(sel("$.n[3]"), Vec::<Json>::new());
        assert_eq!(sel("$.n[-4]"), Vec::<Json>::new());
        assert_eq!(sel("$.a.*"), vec![json!(3), json!("x")]);
        assert_eq!(sel("$.missing.b"), Vec::<Json>::new());
        assert_eq!(sel("$.a.b.c"), Vec::<Json>::new());
        assert!(Selector::parse("$.a.b").unwrap().is_singular());
        assert!(Selector::parse("$.n[-1]").unwrap().is_singular());
        assert!(!Selector::parse("$.n[*]").unwrap().is_singular());
        assert!(!Selector::parse("$.items[?@.ok]").unwrap().is_singular());
    }

    #[test]
    fn filters() {
        assert_eq!(sel("$.items[?@.id=='y'].v"), vec![json!(2.5)]);
        assert_eq!(
            sel("$.items[?( @.v >= 2.5 )].id"),
            vec![json!("y"), json!("z")]
        );
        assert_eq!(sel("$.items[?(@.v < 2)].id"), vec![json!("x")]);
        assert_eq!(sel("$.items[?(@.v == 4.0)].id"), vec![json!("z")]);
        assert_eq!(sel("$.items[?(@.ok)].id"), vec![json!("x")]);
        assert_eq!(sel("$.items[?(@.ok == true)].id"), vec![json!("x")]);
        // absent: unequal to everything
        assert_eq!(
            sel("$.items[?(@.ok != true)].id"),
            vec![json!("y"), json!("z")]
        );
        assert_eq!(
            sel("$.items[?(@.id > 'x')].id"),
            vec![json!("y"), json!("z")]
        );
        // no match across types
        assert_eq!(sel("$.items[?(@.id > 1)].id"), Vec::<Json>::new());
        assert_eq!(sel("$.n[?(@ > 15)]"), vec![json!(20), json!(30)]);
    }

    #[test]
    fn refusals() {
        for bad in [
            "",
            "a.b",
            "$.",
            "$..a",
            "$.n[1:2]",
            "$.n[0,1]",
            "$.n[x]",
            "$['a",
            "$.items[?(@.id==)]",
            "$.items[?(@.id==\"x\"]",
            "$ .a",
            "$.a b",
            "$.a#",
        ] {
            assert!(Selector::parse(bad).is_err(), "{bad:?}");
        }
        assert!(Selector::parse(&format!("${}", ".a".repeat(40))).is_err());
        assert!(Selector::parse(&format!("$.{}", "a".repeat(600))).is_err());
    }
}
