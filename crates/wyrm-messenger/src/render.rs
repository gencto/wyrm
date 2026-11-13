//! Templates: `{{name}}` placeholders, filled from a send's variables, a template's live values
//! and built-ins, each escaped for the message's markup so a value can never change it.
//!
//! A placeholder is `{{name}}`, `{{name:.N}}` (a number with N decimals), `{{name.q}}` (the
//! quality of a live value) or `{{name.t}}` (its time, RFC 3339 UTC). Built-ins: `site`, `bot`,
//! `now`.

use wyrm_core::Value;

/// Names a template may use without passing them.
pub const BUILTINS: [&str; 3] = ["site", "bot", "now"];

/// How a filled-in value is escaped.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Escape {
    None,
    /// Telegram HTML: `&`, `<`, `>`.
    Html,
    /// Telegram MarkdownV2: every reserved character gets a backslash.
    MarkdownV2,
    /// Slack mrkdwn: `&`, `<`, `>`.
    Mrkdwn,
    /// JSON string content: the value goes between quotes the template has.
    Json,
    /// Slack Block Kit: mrkdwn first (`&`, `<`, `>`), then JSON string content, so a value
    /// in a text object can be neither a mention (`<!channel>`) nor a link (`<url|text>`).
    JsonMrkdwn,
}

pub fn escape(s: &str, how: Escape) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        match how {
            Escape::None => out.push(c),
            Escape::Html | Escape::Mrkdwn => match c {
                '&' => out.push_str("&amp;"),
                '<' => out.push_str("&lt;"),
                '>' => out.push_str("&gt;"),
                c => out.push(c),
            },
            Escape::MarkdownV2 => {
                if "_*[]()~`>#+-=|{}.!\\".contains(c) {
                    out.push('\\');
                }
                out.push(c);
            }
            Escape::Json => {
                let q = wyrm_history_sync::http::json_string(&c.to_string());
                out.push_str(&q[1..q.len() - 1]);
            }
            Escape::JsonMrkdwn => match c {
                '&' => out.push_str("&amp;"),
                '<' => out.push_str("&lt;"),
                '>' => out.push_str("&gt;"),
                c => {
                    let q = wyrm_history_sync::http::json_string(&c.to_string());
                    out.push_str(&q[1..q.len() - 1]);
                }
            },
        }
    }
    out
}

/// A variable name: `[a-z_][a-z0-9_]*`, at most 32 bytes.
pub fn check_var(n: &str) -> Result<(), String> {
    let ok = !n.is_empty()
        && n.len() <= 32
        && n.bytes()
            .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'_')
        && !n.as_bytes()[0].is_ascii_digit();
    if ok {
        Ok(())
    } else {
        Err(format!("{n:?}: a name of a-z, 0-9 and _"))
    }
}

/// What follows the name of a placeholder.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Modifier {
    None,
    Decimals(u8),
    Quality,
    Time,
}

/// A value map after `|`: `{{state|NORMAL=🟢,UNSTABLE=🟡,*=⚪}}`. The text the placeholder
/// gives without it is looked up; `*` is what any other text becomes (without `*` the text
/// stays). Up to [`MAX_MAP_PAIRS`] pairs in [`MAX_MAP_BYTES`]; a key or a value holds no `,`,
/// `=`, `|` or braces.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct ValueMap {
    pairs: Vec<(String, String)>,
    other: Option<String>,
}

pub const MAX_MAP_PAIRS: usize = 16;
pub const MAX_MAP_BYTES: usize = 256;

impl ValueMap {
    fn parse(spec: &str, whole: &str) -> Result<Self, String> {
        let bad = |why: &str| format!("{{{{{whole}}}}}: {why}");
        if spec.len() > MAX_MAP_BYTES {
            return Err(bad(&format!(
                "a value map is at most {MAX_MAP_BYTES} bytes"
            )));
        }
        let mut m = ValueMap::default();
        for pair in spec.split(',') {
            let (k, v) = pair
                .split_once('=')
                .ok_or_else(|| bad("a value map is key=value pairs, comma separated"))?;
            let (k, v) = (k.trim(), v.trim());
            if k.is_empty() || v.contains(['=', '{', '}']) || k.contains(['{', '}']) {
                return Err(bad("a key and a value without = or braces"));
            }
            if k == "*" {
                if m.other.replace(v.to_owned()).is_some() {
                    return Err(bad("one * in a value map"));
                }
            } else if m.pairs.iter().any(|(x, _)| x == k) {
                return Err(bad(&format!("{k} twice in a value map")));
            } else {
                m.pairs.push((k.to_owned(), v.to_owned()));
            }
        }
        if m.pairs.len() + usize::from(m.other.is_some()) > MAX_MAP_PAIRS {
            return Err(bad(&format!(
                "at most {MAX_MAP_PAIRS} pairs in a value map"
            )));
        }
        Ok(m)
    }

    /// What `text` becomes.
    pub fn apply(&self, text: String) -> String {
        match self.pairs.iter().find(|(k, _)| *k == text.trim()) {
            Some((_, v)) => v.clone(),
            None => self.other.clone().unwrap_or(text),
        }
    }
}

fn parse_full(inner: &str) -> Result<(String, Modifier, Option<ValueMap>), String> {
    let whole = inner.trim();
    let (base, map) = match whole.split_once('|') {
        Some((b, m)) => (b, Some(ValueMap::parse(m, whole)?)),
        None => (whole, None),
    };
    let (name, m) = parse_one(base)?;
    Ok((name, m, map))
}

fn parse_one(inner: &str) -> Result<(String, Modifier), String> {
    let inner = inner.trim();
    let (name, m) = if let Some((n, d)) = inner.split_once(":.") {
        let d: u8 = d
            .parse()
            .ok()
            .filter(|d| *d <= 9)
            .ok_or_else(|| format!("{{{{{inner}}}}}: :.N with N 0…9"))?;
        (n, Modifier::Decimals(d))
    } else if let Some(n) = inner.strip_suffix(".q") {
        (n, Modifier::Quality)
    } else if let Some(n) = inner.strip_suffix(".t") {
        (n, Modifier::Time)
    } else {
        (inner, Modifier::None)
    };
    check_var(name).map_err(|e| format!("placeholder {e}"))?;
    Ok((name.to_owned(), m))
}

/// The placeholders of `text`, in order.
pub fn placeholders(text: &str) -> Result<Vec<(String, Modifier)>, String> {
    let mut out = Vec::new();
    let mut rest = text;
    while let Some(i) = rest.find("{{") {
        let after = &rest[i + 2..];
        let j = after.find("}}").ok_or("a {{ without its }}")?;
        let (name, m, _) = parse_full(&after[..j])?;
        out.push((name, m));
        rest = &after[j + 2..];
    }
    Ok(out)
}

/// `text` with each placeholder replaced by `lookup(name, modifier)` escaped as `how`; a name
/// `lookup` does not know becomes empty.
pub fn render(
    text: &str,
    how: Escape,
    lookup: &dyn Fn(&str, &Modifier) -> Option<String>,
) -> Result<String, String> {
    let mut out = String::with_capacity(text.len());
    let mut rest = text;
    while let Some(i) = rest.find("{{") {
        out.push_str(&rest[..i]);
        let after = &rest[i + 2..];
        let j = after.find("}}").ok_or("a {{ without its }}")?;
        let (name, m, map) = parse_full(&after[..j])?;
        if let Some(v) = lookup(&name, &m) {
            let v = match &map {
                Some(map) => map.apply(v),
                None => v,
            };
            out.push_str(&escape(&v, how));
        }
        rest = &after[j + 2..];
    }
    out.push_str(rest);
    Ok(out)
}

/// A value as text: numbers plain (or with `decimals`), text as it is, others as JSON.
pub fn value_text(v: &Value, decimals: Option<u8>) -> String {
    match (v, decimals) {
        (Value::Null, _) => String::new(),
        (Value::Bool(b), _) => b.to_string(),
        (Value::Int(i), Some(d)) => format!("{:.*}", usize::from(d), *i as f64),
        (Value::UInt(u), Some(d)) => format!("{:.*}", usize::from(d), *u as f64),
        (Value::Float(f), Some(d)) => format!("{:.*}", usize::from(d), f),
        (Value::Int(i), None) => i.to_string(),
        (Value::UInt(u), None) => u.to_string(),
        (Value::Float(f), None) => f.to_string(),
        (Value::Str(s), _) => s.clone(),
        (other, _) => crate::api::json_value(other).to_string(),
    }
}

/// Cut `s` to at most `max` characters, ending with `…` when cut.
pub fn cut(s: &str, max: usize) -> String {
    if s.chars().count() <= max {
        return s.to_owned();
    }
    let mut out: String = s.chars().take(max.saturating_sub(1)).collect();
    out.push('…');
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn look(name: &str, m: &Modifier) -> Option<String> {
        match (name, m) {
            ("who", _) => Some("<script>&".into()),
            ("t", Modifier::Decimals(d)) => Some(value_text(&Value::Float(21.456), Some(*d))),
            ("t", _) => Some(value_text(&Value::Float(21.456), None)),
            ("md", _) => Some("a_b*c.".into()),
            _ => None,
        }
    }

    /// Value maps (DVPSM demo, 2026-11-13: state emojis without an expression in the flow).
    #[test]
    fn value_maps() {
        let look = |n: &str, m: &Modifier| -> Option<String> {
            match (n, m) {
                ("st", Modifier::None) => Some("UNSTABLE".into()),
                ("st", Modifier::Quality) => Some("bad".into()),
                ("x", _) => Some("<b>".into()),
                _ => None,
            }
        };
        let r = |t: &str| render(t, Escape::Html, &look);
        assert_eq!(r("{{st|NORMAL=🟢,UNSTABLE=🟡,*=⚪}}").unwrap(), "🟡");
        assert_eq!(
            r("{{st|NORMAL=🟢}}").unwrap(),
            "UNSTABLE",
            "no *: the text stays"
        );
        assert_eq!(r("{{st|*=⚪}}").unwrap(), "⚪");
        assert_eq!(r("{{st.q|good=ok,bad=❗}}").unwrap(), "❗");
        // what a map gives is escaped as any value
        assert_eq!(r("{{x|y=1}}").unwrap(), "&lt;b&gt;");
        assert_eq!(r("{{st|a=<i>}}").unwrap(), "UNSTABLE");
        assert_eq!(r("{{st|*=<i>}}").unwrap(), "&lt;i&gt;");
        // placeholders still name the variable
        assert_eq!(
            placeholders("{{st|A=1}}").unwrap(),
            vec![("st".into(), Modifier::None)]
        );
        for bad in [
            "{{st|A}}",
            "{{st|=1}}",
            "{{st|A=1,A=2}}",
            "{{st|*=1,*=2}}",
            "{{st|A=b=c}}",
        ] {
            assert!(r(bad).is_err(), "{bad}");
        }
        let many: Vec<String> = (0..17).map(|i| format!("k{i}=v")).collect();
        assert!(r(&format!("{{{{st|{}}}}}", many.join(","))).is_err());
    }

    #[test]
    fn values_are_escaped_for_the_markup() {
        let r = render("<b>{{who}}</b> {{t:.1}}", Escape::Html, &look).unwrap();
        assert_eq!(r, "<b>&lt;script&gt;&amp;</b> 21.5");
        let r = render("*{{md}}*", Escape::MarkdownV2, &look).unwrap();
        assert_eq!(r, r"*a\_b\*c\.*");
        let r = render(r#"{"text":"{{who}} \"{{t}}\""}"#, Escape::Json, &look).unwrap();
        assert_eq!(r, r#"{"text":"<script>& \"21.456\""}"#);
        let r = render(r#"{"x":"{{q}}"}"#, Escape::Json, &|_, _| {
            Some("a\"b\n".into())
        })
        .unwrap();
        assert_eq!(r, r#"{"x":"a\"b\n"}"#);
        assert_eq!(render("{{none}}!", Escape::None, &look).unwrap(), "!");
    }

    #[test]
    fn block_kit_values_are_neither_mentions_nor_links() {
        let tpl = r#"[{"type":"section","text":{"type":"mrkdwn","text":"*{{v}}*"}}]"#;
        let r = render(tpl, Escape::JsonMrkdwn, &|_, _| {
            Some("<!channel> <https://evil.example|click> \"a\" & b".into())
        })
        .unwrap();
        assert_eq!(
            r,
            r#"[{"type":"section","text":{"type":"mrkdwn","text":"*&lt;!channel&gt; &lt;https://evil.example|click&gt; \"a\" &amp; b*"}}]"#
        );
        let j: serde_json::Value = serde_json::from_str(&r).unwrap();
        let text = j[0]["text"]["text"].as_str().unwrap();
        assert!(!text.contains('<') && !text.contains('>'), "{text}");
    }

    #[test]
    fn placeholders_parse_or_fail() {
        let p = placeholders("{{a}} {{ b:.2 }} {{c.q}} {{c.t}}").unwrap();
        assert_eq!(
            p,
            vec![
                ("a".into(), Modifier::None),
                ("b".into(), Modifier::Decimals(2)),
                ("c".into(), Modifier::Quality),
                ("c".into(), Modifier::Time),
            ]
        );
        assert!(placeholders("{{A}}").is_err());
        assert!(placeholders("{{a:.x}}").is_err());
        assert!(placeholders("{{a").is_err());
        assert!(placeholders("plain } { text").unwrap().is_empty());
    }

    #[test]
    fn cut_marks_what_it_cut() {
        assert_eq!(cut("abc", 3), "abc");
        assert_eq!(cut("abcd", 3), "ab…");
        assert_eq!(cut("ґґґґ", 2), "ґ…");
    }
}
