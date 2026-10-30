//! DSA DQL compatibility (ADR 0025): the `filter` test syntax as CEL, and a whole DSA text as a
//! WYRM text (`convert_dsa`).
//!
//! Filter: tests separated by spaces all hold (`and`); `$x` is a meta field, `@x` an attribute,
//! `:name`/`:display` the node's name and display, anything else a column (subscribed first). A
//! test without an operator asks that the thing exists. Operators `= == equals is != < <= > >=
//! ~ like contains in anyContains`, logic `and && or || xor ^ not`, parentheses, lists `[…]`,
//! `#"col"` and a bare name on the right side refer to columns. `like` is SQL's: `%` is any
//! text and the whole value must match (DSA matched anywhere).

use crate::parse::split_top;

#[derive(Debug, Clone, PartialEq)]
enum Tok {
    Word(String),
    Str(String),
    Op(String),
    LParen,
    RParen,
    LBracket,
    RBracket,
    Comma,
    Hash,
}

const OPS: [&str; 12] = [
    "==", "!=", "<=", ">=", "&&", "||", "~", "<", ">", "=", "^", "!",
];

fn word_char(c: char) -> bool {
    c.is_ascii_alphanumeric() || "$@_:./-".contains(c)
}

fn lex(s: &str) -> Result<Vec<Tok>, String> {
    let cs: Vec<char> = s.chars().collect();
    let mut out = Vec::new();
    let mut i = 0;
    while i < cs.len() {
        let c = cs[i];
        if c.is_whitespace() {
            i += 1;
        } else if matches!(c, '"' | '\'' | '`') {
            let mut j = i + 1;
            let mut t = String::new();
            while j < cs.len() && cs[j] != c {
                t.push(cs[j]);
                j += 1;
            }
            if j >= cs.len() {
                return Err("a quote is not closed".into());
            }
            out.push(Tok::Str(t));
            i = j + 1;
        } else if c == '(' {
            out.push(Tok::LParen);
            i += 1;
        } else if c == ')' {
            out.push(Tok::RParen);
            i += 1;
        } else if c == '[' {
            out.push(Tok::LBracket);
            i += 1;
        } else if c == ']' {
            out.push(Tok::RBracket);
            i += 1;
        } else if c == ',' {
            out.push(Tok::Comma);
            i += 1;
        } else if c == '#' {
            out.push(Tok::Hash);
            i += 1;
        } else if word_char(c) {
            let mut j = i;
            while j < cs.len() && word_char(cs[j]) {
                j += 1;
            }
            out.push(Tok::Word(cs[i..j].iter().collect()));
            i = j;
        } else {
            let two: String = cs[i..(i + 2).min(cs.len())].iter().collect();
            let op = OPS
                .iter()
                .find(|o| two.starts_with(*o))
                .ok_or_else(|| format!("{c:?}: not part of a filter"))?;
            out.push(Tok::Op((*op).to_owned()));
            i += op.len();
        }
    }
    Ok(out)
}

struct P {
    toks: Vec<Tok>,
    i: usize,
    cols: Vec<String>,
}

fn cel_str(s: &str) -> String {
    let mut out = String::from("\"");
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            _ => out.push(c),
        }
    }
    out.push('"');
    out
}

const COMPARE: [&str; 6] = ["equals", "is", "like", "contains", "in", "anyContains"];

impl P {
    fn peek(&self) -> Option<&Tok> {
        self.toks.get(self.i)
    }

    fn next(&mut self) -> Option<Tok> {
        let t = self.toks.get(self.i).cloned();
        self.i += 1;
        t
    }

    fn col(&mut self, name: &str) -> String {
        if !self.cols.iter().any(|c| c == name) {
            self.cols.push(name.to_owned());
        }
        format!("({0} in row ? row[{0}] : null)", cel_str(name))
    }

    /// A key on the left side as a CEL value.
    fn key(&mut self, k: &str) -> String {
        if let Some(f) = k.strip_prefix('$') {
            return match f {
                "type" | "unit" | "writable" | "is" | "display" => f.to_owned(),
                "name" => "display".to_owned(),
                _ => "null".to_owned(),
            };
        }
        if let Some(a) = k.strip_prefix('@') {
            return format!("({0} in attr ? attr[{0}] : null)", cel_str(a));
        }
        match k {
            ":name" => "name".into(),
            ":display" | ":displayName" => "display".into(),
            ":path" => "path".into(),
            // other DSA `:` keys were the requester's own attributes: none here
            _ if k.starts_with(':') => "null".into(),
            _ => self.col(k),
        }
    }

    /// The test that a key exists.
    fn exists(&mut self, k: &str) -> String {
        if k.starts_with('$') {
            return format!("{} != null", self.key(k));
        }
        if let Some(a) = k.strip_prefix('@') {
            return format!("{} in attr", cel_str(a));
        }
        if k.starts_with(':') {
            let known = matches!(k, ":name" | ":display" | ":displayName" | ":path");
            return known.to_string();
        }
        format!("{} != null", self.col(k))
    }

    fn value(&mut self) -> Result<String, String> {
        match self.next() {
            Some(Tok::Str(s)) => Ok(cel_str(&s)),
            Some(Tok::Hash) => match self.next() {
                Some(Tok::Str(s)) => Ok(self.col(&s)),
                _ => Err("#: a quoted column name".into()),
            },
            Some(Tok::LBracket) => {
                let mut items = Vec::new();
                loop {
                    if self.peek() == Some(&Tok::RBracket) {
                        self.next();
                        break;
                    }
                    items.push(self.value()?);
                    match self.next() {
                        Some(Tok::Comma) => {}
                        Some(Tok::RBracket) => break,
                        _ => return Err("a list ends with ]".into()),
                    }
                }
                Ok(format!("[{}]", items.join(", ")))
            }
            Some(Tok::Word(w)) => Ok(match w.as_str() {
                "null" | "nil" => "null".into(),
                "true" | "false" => w,
                _ if w.parse::<i64>().is_ok() => w,
                _ if w.parse::<f64>().is_ok() => {
                    let f: f64 = w.parse().unwrap_or(0.0);
                    format!("{f:?}")
                }
                _ if self.peek() == Some(&Tok::LParen) => self.call(&w)?,
                _ => self.key(&w),
            }),
            t => Err(format!("expected a value, found {t:?}")),
        }
    }

    fn call(&mut self, f: &str) -> Result<String, String> {
        self.next();
        let mut args = Vec::new();
        loop {
            if self.peek() == Some(&Tok::RParen) {
                self.next();
                break;
            }
            args.push(self.value()?);
            match self.next() {
                Some(Tok::Comma) => {}
                Some(Tok::RParen) => break,
                _ => return Err(format!("{f}(: arguments end with )")),
            }
        }
        Ok(format!("{f}({})", args.join(", ")))
    }

    fn compare(&mut self) -> Result<String, String> {
        let left = match self.next() {
            Some(Tok::Word(w)) if self.peek() == Some(&Tok::LParen) => self.call(&w)?,
            Some(Tok::Word(w)) => w,
            Some(Tok::Str(s)) => s,
            t => return Err(format!("expected a test, found {t:?}")),
        };
        let op = match self.peek() {
            Some(Tok::Op(o))
                if matches!(
                    o.as_str(),
                    "==" | "!=" | "<=" | ">=" | "<" | ">" | "=" | "~"
                ) =>
            {
                o.clone()
            }
            Some(Tok::Word(w)) if COMPARE.contains(&w.as_str()) => w.clone(),
            _ => return Ok(format!("({})", self.exists(&left))),
        };
        self.next();
        let l = if left.contains('(') {
            left
        } else {
            self.key(&left)
        };
        let r = self.value()?;
        Ok(format!(
            "({})",
            match op.as_str() {
                "=" | "==" | "equals" | "is" => format!("{l} == {r}"),
                "~" => format!("string({l}).matches({r})"),
                "like" => {
                    let pat = r.trim_matches('"');
                    let mut re = String::from("^");
                    for c in pat.chars() {
                        if c == '%' {
                            re.push_str(".*");
                        } else if c.is_ascii_alphanumeric() || c == ' ' {
                            re.push(c);
                        } else {
                            re.push('\\');
                            re.push('\\');
                            re.push(c);
                        }
                    }
                    re.push('$');
                    format!("string({l}).matches(\"{re}\")")
                }
                "contains" => format!("{l}.contains({r})"),
                "in" => format!("{l} in {r}"),
                "anyContains" => format!("{l}.exists(e, e.contains({r}))"),
                o => format!("{l} {o} {r}"),
            }
        ))
    }

    fn unary(&mut self) -> Result<String, String> {
        match self.peek() {
            Some(Tok::Word(w)) if w == "not" => {
                self.next();
                Ok(format!("!({})", self.unary()?))
            }
            Some(Tok::Op(o)) if o == "!" => {
                self.next();
                Ok(format!("!({})", self.unary()?))
            }
            Some(Tok::LParen) => {
                self.next();
                let e = self.expr()?;
                match self.next() {
                    Some(Tok::RParen) => Ok(format!("({e})")),
                    _ => Err("( is not closed".into()),
                }
            }
            _ => self.compare(),
        }
    }

    /// `a [logic b]…`, left to right as DSA's grammar (right-nested, no precedence).
    fn logical(&mut self) -> Result<String, String> {
        let left = self.unary()?;
        let op = match self.peek() {
            Some(Tok::Word(w)) if matches!(w.as_str(), "and" | "or" | "xor") => w.clone(),
            Some(Tok::Op(o)) if matches!(o.as_str(), "&&" | "||" | "^") => o.clone(),
            _ => return Ok(left),
        };
        self.next();
        let right = self.logical()?;
        Ok(match op.as_str() {
            "and" | "&&" => format!("({left} && {right})"),
            "or" | "||" => format!("({left} || {right})"),
            _ => format!("({left} != {right})"),
        })
    }

    /// Tests side by side: all hold.
    fn expr(&mut self) -> Result<String, String> {
        let mut parts = vec![self.logical()?];
        while !matches!(self.peek(), None | Some(Tok::RParen)) {
            parts.push(self.logical()?);
        }
        Ok(parts.join(" && "))
    }
}

/// A DSA filter as CEL, and the columns it reads (to subscribe them first).
pub fn filter_to_cel(text: &str) -> Result<(String, Vec<String>), String> {
    let mut p = P {
        toks: lex(text)?,
        i: 0,
        cols: Vec::new(),
    };
    if p.toks.is_empty() {
        return Err("filter <tests>".into());
    }
    let e = p.expr()?;
    if p.i < p.toks.len() {
        return Err("a ) without its (".into());
    }
    Ok((e, p.cols))
}

/// A DSA path (`/downstream/System/*`, `?`) as a WYRM pattern under `wy/<site>`.
fn dsa_path(path: &str, site: &str) -> Result<String, String> {
    let p = path.trim();
    if p == "*" || p == "/*" || p == "/" {
        return Ok(format!("wy/{site}/downstream/**"));
    }
    let p = p.strip_prefix('/').unwrap_or(p);
    let segs = p
        .split('/')
        .map(|s| match s {
            "?" => Ok("*".to_owned()),
            "*" => Ok("**".to_owned()),
            s if s.contains(['*', '?']) => Err(format!(
                "{s}: a segment with a wildcard inside it has no WYRM form (use where name.matches(…))"
            )),
            s => Ok(s.to_owned()),
        })
        .collect::<Result<Vec<_>, _>>()?;
    Ok(format!("wy/{site}/{}", segs.join("/")))
}

/// A whole DSA DQL text as a WYRM text for site `site`.
pub fn convert(text: &str, site: &str) -> Result<String, String> {
    if site.is_empty() || site.contains('/') {
        return Err("site: one segment".into());
    }
    let mut out = Vec::new();
    for (i, part) in split_top(text, '|')?.iter().enumerate() {
        let part = part.trim();
        let (cmd, arg) = part
            .split_once(char::is_whitespace)
            .map(|(c, a)| (c, a.trim()))
            .unwrap_or((part, ""));
        let err = |e: String| format!("stage {}: {e}", i + 1);
        let stage = match cmd.to_ascii_lowercase().as_str() {
            "list" | "lista" => {
                let mut ps = Vec::new();
                for p in split_top(arg, ',')? {
                    let p = p.trim();
                    ps.push(if p.eq_ignore_ascii_case("brokers") {
                        format!("sites wy/{site}")
                    } else {
                        dsa_path(p, site).map_err(err)?
                    });
                }
                format!("list {}", ps.join(", "))
            }
            "path" => format!("path {}", dsa_path(arg, site).map_err(err)?),
            "sublist" => {
                let rel = dsa_path(arg, site).map_err(err)?;
                let rel = rel
                    .strip_prefix(&format!("wy/{site}/"))
                    .unwrap_or(&rel)
                    .to_owned();
                format!("sublist ./{rel}")
            }
            "invoke" => {
                let open = arg
                    .find('(')
                    .ok_or_else(|| err("invoke <action>(…)".into()))?;
                let (target, params) = arg.split_at(open);
                let target = target.trim();
                let wyrm = match target.rsplit_once('/') {
                    Some((node, action)) if target.starts_with('/') => {
                        let node = dsa_path(node, site).map_err(err)?;
                        format!("{node}/~act/{action}")
                    }
                    Some((node, action)) => format!("{node}/~act/{action}"),
                    None => target.to_owned(),
                };
                format!("invoke {wyrm}{params}")
            }
            "option" => {
                let kept: Vec<String> = arg
                    .split_whitespace()
                    .filter_map(|kv| {
                        let k = kv.split('=').next().unwrap_or("");
                        match k {
                            "traverseBrokers"
                            | "brokersIncludeQuarantine"
                            | "listActions"
                            | "qos" => None,
                            "invokeAllowNull" => Some(kv.replacen(k, "invoke_allow_null", 1)),
                            _ => Some(kv.to_owned()),
                        }
                    })
                    .collect();
                if kept.is_empty() {
                    continue;
                }
                format!("option {}", kept.join(" "))
            }
            _ => part.to_owned(),
        };
        out.push(stage);
    }
    Ok(out.join(" | "))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn filters_become_cel() {
        let (c, cols) = filter_to_cel(r#"$type="number" @unit!="%""#).unwrap();
        assert_eq!(
            c,
            r#"(type == "number") && (("unit" in attr ? attr["unit"] : null) != "%")"#
        );
        assert!(cols.is_empty());
        let (c, cols) = filter_to_cel("$type").unwrap();
        assert_eq!(c, "(type != null)");
        assert!(cols.is_empty());
        let (c, _) = filter_to_cel("@mytag").unwrap();
        assert_eq!(c, r#"("mytag" in attr)"#);
        let (c, cols) = filter_to_cel("value >= 20 and not (:name like 'Temp%')").unwrap();
        assert_eq!(cols, vec!["value"]);
        assert!(c.contains(">= 20") && c.contains("!("), "{c}");
        assert!(c.contains(r#"matches("^Temp.*$")"#), "{c}");
        assert!(filter_to_cel("value >").is_err());
        assert!(filter_to_cel("(a").is_err());
        assert!(filter_to_cel("").is_err());
    }

    #[test]
    fn dsa_texts_convert() {
        assert_eq!(
            convert(
                "list /downstream/System/* | filter $type | subscribe :name value",
                "s"
            )
            .unwrap(),
            "list wy/s/downstream/System/** | filter $type | subscribe :name value"
        );
        assert_eq!(
            convert("list brokers | sublist /downstream/?", "c").unwrap(),
            "list sites wy/c | sublist ./downstream/*"
        );
        assert_eq!(
            convert(
                "list /downstream/System | filter :metric | subscribe | invoke /downstream/MongoDB/local/SystemValues/publish(Path=%path, Value=%value)",
                "s"
            )
            .unwrap(),
            "list wy/s/downstream/System | filter :metric | subscribe | invoke wy/s/downstream/MongoDB/local/SystemValues/~act/publish(Path=%path, Value=%value)"
        );
        assert_eq!(
            convert("option traverseBrokers=true | list *", "s").unwrap(),
            "list wy/s/downstream/**"
        );
        assert!(convert("list /downstream/ahu*", "s").is_err());
    }
}
