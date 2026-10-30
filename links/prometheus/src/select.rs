//! Series selectors: `name{label="v", label!="v", label=~"re", label!~"re"}`
//! as in PromQL, compiled once when the params are parsed.
//!
//! As in Prometheus, a missing label has the value `""` (so `l=""` matches
//! series without `l`), and a regex matches the whole value (it is anchored
//! as `^(?:re)$`). Regexes use the `regex` crate (linear time, no
//! backreferences) with a bound on the compiled size.

use crate::expo::{is_label_name, is_metric_name, quoted, Series};
use regex::{Regex, RegexBuilder};

/// Bound on one compiled regex.
const REGEX_SIZE: usize = 1 << 20;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Op {
    Eq,
    Ne,
    Re,
    NotRe,
}

#[derive(Debug, Clone)]
pub struct Matcher {
    pub label: String,
    pub op: Op,
    pub value: String,
    re: Option<Regex>,
}

impl PartialEq for Matcher {
    fn eq(&self, o: &Self) -> bool {
        self.label == o.label && self.op == o.op && self.value == o.value
    }
}

impl Matcher {
    pub fn new(label: &str, op: Op, value: &str) -> Result<Self, String> {
        if !is_label_name(label) {
            return Err(format!("bad label name {label:?}"));
        }
        let re = match op {
            Op::Re | Op::NotRe => Some(
                RegexBuilder::new(&format!("^(?:{value})$"))
                    .size_limit(REGEX_SIZE)
                    .build()
                    .map_err(|e| format!("label {label}: bad regex: {e}"))?,
            ),
            _ => None,
        };
        Ok(Self {
            label: label.to_owned(),
            op,
            value: value.to_owned(),
            re,
        })
    }

    pub fn matches(&self, s: &Series) -> bool {
        let v = s.label(&self.label).unwrap_or("");
        match (self.op, &self.re) {
            (Op::Eq, _) => v == self.value,
            (Op::Ne, _) => v != self.value,
            (Op::Re, Some(re)) => re.is_match(v),
            (Op::NotRe, Some(re)) => !re.is_match(v),
            _ => false,
        }
    }
}

/// A metric name (may be empty) and label matchers.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct Selector {
    pub name: String,
    pub matchers: Vec<Matcher>,
}

impl Selector {
    /// `name`, `name{…}` or `{…}`.
    pub fn parse(text: &str) -> Result<Self, String> {
        let t = text.trim();
        let (name, rest) = match t.find('{') {
            Some(i) => (t[..i].trim(), &t[i..]),
            None => (t, ""),
        };
        if !name.is_empty() && !is_metric_name(name) {
            return Err(format!("bad metric name {name:?}"));
        }
        let matchers = if rest.is_empty() {
            Vec::new()
        } else {
            let inner = rest
                .strip_prefix('{')
                .ok_or("expected {")?
                .trim_end()
                .strip_suffix('}')
                .ok_or("expected } at the end")?;
            matchers(inner)?
        };
        Ok(Self {
            name: name.to_owned(),
            matchers,
        })
    }

    /// Label matchers only, with or without braces (a device's filter).
    pub fn parse_matchers(text: &str) -> Result<Vec<Matcher>, String> {
        let t = text.trim();
        if t.starts_with('{') {
            let s = Self::parse(t)?;
            return Ok(s.matchers);
        }
        matchers(t)
    }

    pub fn matches(&self, s: &Series) -> bool {
        (self.name.is_empty() || s.name == self.name) && self.matches_labels(s)
    }

    pub fn matches_labels(&self, s: &Series) -> bool {
        self.matchers.iter().all(|m| m.matches(s))
    }
}

/// `l="v", l2=~"re"` (no braces); a trailing comma is allowed.
fn matchers(mut r: &str) -> Result<Vec<Matcher>, String> {
    let mut out = Vec::new();
    loop {
        r = r.trim_start();
        if r.is_empty() {
            return Ok(out);
        }
        let op_at = r
            .find(['=', '!'])
            .ok_or_else(|| format!("expected a matcher at {:?}", short(r)))?;
        let label = r[..op_at].trim();
        let after = &r[op_at..];
        let (op, after) = if let Some(a) = after.strip_prefix("=~") {
            (Op::Re, a)
        } else if let Some(a) = after.strip_prefix("!~") {
            (Op::NotRe, a)
        } else if let Some(a) = after.strip_prefix("!=") {
            (Op::Ne, a)
        } else if let Some(a) = after.strip_prefix('=') {
            (Op::Eq, a)
        } else {
            return Err(format!("expected =, !=, =~ or !~ after {label:?}"));
        };
        let (value, after) =
            quoted(after.trim_start()).map_err(|e| format!("label {label}: {}", e.0))?;
        out.push(Matcher::new(label, op, &value)?);
        r = after.trim_start();
        if let Some(a) = r.strip_prefix(',') {
            r = a;
        } else if !r.is_empty() {
            return Err(format!("expected , at {:?}", short(r)));
        }
    }
}

fn short(s: &str) -> String {
    s.chars().take(20).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn series(name: &str, labels: &[(&str, &str)]) -> Series {
        let mut labels: Vec<(String, String)> = labels
            .iter()
            .map(|(k, v)| ((*k).to_owned(), (*v).to_owned()))
            .collect();
        labels.sort();
        Series {
            name: name.into(),
            labels,
            value: 1.0,
        }
    }

    #[test]
    fn operators() {
        let s = series("up", &[("job", "node"), ("instance", "a:9100")]);
        let ok = |t: &str| Selector::parse(t).unwrap().matches(&s);
        assert!(ok("up"));
        assert!(!ok("down"));
        assert!(ok("{job=\"node\"}"));
        assert!(ok("up{job=\"node\", instance=~\"a:.*\"}"));
        assert!(!ok("up{instance=~\"a\"}"), "regexes are anchored");
        assert!(ok("up{job!=\"x\"}"));
        assert!(!ok("up{job!~\"no.*\"}"));
        assert!(ok("up{missing=\"\"}"), "a missing label is empty");
        assert!(!ok("up{missing!=\"\"}"));
        assert!(ok("up{job=\"node\",}"));
        assert!(ok("up{job=~\"node|other\"}"));
    }

    #[test]
    fn errors() {
        for bad in [
            "9up",
            "up{job}",
            "up{job=node}",
            "up{job=\"node\"",
            "up{1a=\"x\"}",
            "up{a=~\"(\"}",
            "up{a=\"x\" b=\"y\"}",
            "up{a<\"x\"}",
        ] {
            assert!(Selector::parse(bad).is_err(), "{bad}");
        }
    }

    #[test]
    fn device_filter() {
        let m = Selector::parse_matchers("instance=\"a\", job=~\"n.*\"").unwrap();
        assert_eq!(m.len(), 2);
        assert_eq!(
            Selector::parse_matchers("{instance=\"a\"}").unwrap(),
            m[..1]
        );
        assert!(Selector::parse_matchers("").unwrap().is_empty());
        assert!(
            Selector::parse_matchers("up{a=\"b\"}").is_err(),
            "no metric name in a filter"
        );
    }
}
