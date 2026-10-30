//! The pipeline: `<command> <argument> | <command> <argument> …` (DSA DQL syntax, ADR 0025) into
//! a [`Plan`]. Paths are full keys with Zenoh wildcards; predicates and expressions are CEL; a
//! DSA `filter` is turned into CEL ([`crate::dsa`]).

use std::collections::BTreeSet;

use crate::cel::{Expr, META_FIELDS};
use crate::pattern::{check_key, Pattern, Seg};

/// Longest query text, bytes.
pub const MAX_TEXT: usize = 4096;
/// Stages of one query.
pub const MAX_STAGES: usize = 16;

/// What a `subscribe` column reads.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Part {
    Value,
    /// The sample's time, microseconds since the epoch.
    Timestamp,
    /// The sample's quality name.
    Quality,
    /// A field of the row's meta (`type`, `display`, …, see [`META_FIELDS`]).
    Meta(String),
    /// `attr.<name>` of the row's meta.
    Attr(String),
}

/// A `subscribe` key: a part of the row's node (`node: None`) or of a node relative to it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SubKey {
    pub node: Option<String>,
    pub part: Part,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Column {
    pub key: SubKey,
    pub name: String,
}

/// A sink argument: a column (`%col`) or a CEL expression over the row.
#[derive(Debug, Clone, PartialEq)]
pub enum Arg {
    Col(String),
    Expr(Expr),
}

#[derive(Debug, Clone, PartialEq)]
pub enum Sink {
    /// `invoke <node>/~act/<action>(<p>=<arg>, …)`; `node` relative to the row or full.
    Invoke {
        node: String,
        action: String,
        params: Vec<(String, Arg)>,
    },
    /// `set <node> = <arg>`.
    Set { node: String, value: Arg },
}

#[derive(Debug, Clone, PartialEq)]
pub enum Stage {
    Where(Expr),
    Subscribe(Vec<Column>),
    Expression(Vec<(String, Expr)>),
    Rename(Vec<(String, String)>),
    Drop(Vec<String>),
    Sink(Sink),
}

/// Where a segment's rows come from.
#[derive(Debug, Clone, PartialEq)]
pub enum Source {
    /// The first segment: full patterns (`list`, `path`, `list sites`).
    Roots(Vec<Pattern>),
    /// `sublist`: a pattern below each row of the segment before.
    Below(Vec<Seg>),
}

#[derive(Debug, Clone, PartialEq)]
pub struct Segment {
    pub source: Source,
    pub stages: Vec<Stage>,
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct Options {
    pub invoke_allow_null: bool,
    pub throttle_ms: u64,
    pub max_rows: Option<usize>,
    pub timeout_s: Option<u64>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Plan {
    pub text: String,
    pub segments: Vec<Segment>,
    pub options: Options,
    /// Some stage reads `attr`, `actions` or the whole `meta`: list with full `~meta`.
    pub full_meta: bool,
}

/// A refused text: the stage (1-based, 0 = the whole text) and what is wrong.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ParseError {
    pub stage: usize,
    pub msg: String,
}

impl std::fmt::Display for ParseError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        if self.stage == 0 {
            f.write_str(&self.msg)
        } else {
            write!(f, "stage {}: {}", self.stage, self.msg)
        }
    }
}

impl Plan {
    pub fn has_sinks(&self) -> bool {
        self.stages().any(|s| matches!(s, Stage::Sink(_)))
    }

    /// Some column reads values: the query subscribes its roots.
    pub fn uses_values(&self) -> bool {
        self.stages().any(|s| match s {
            Stage::Subscribe(cols) => cols
                .iter()
                .any(|c| matches!(c.key.part, Part::Value | Part::Timestamp | Part::Quality)),
            _ => false,
        })
    }

    fn stages(&self) -> impl Iterator<Item = &Stage> {
        self.segments.iter().flat_map(|s| s.stages.iter())
    }

    /// The fixed keys the query lists first (for `explain` and the rights check of a caller).
    pub fn roots(&self) -> Vec<String> {
        match self.segments.first().map(|s| &s.source) {
            Some(Source::Roots(p)) => p.iter().map(|p| p.top.clone()).collect(),
            _ => Vec::new(),
        }
    }

    /// The targets of the sinks as written (relative or full).
    pub fn sinks(&self) -> Vec<String> {
        self.stages()
            .filter_map(|s| match s {
                Stage::Sink(Sink::Invoke { node, action, .. }) => {
                    Some(format!("{node}/~act/{action}"))
                }
                Stage::Sink(Sink::Set { node, .. }) => Some(format!("{node}/~set")),
                _ => None,
            })
            .collect()
    }

    /// Column names in the order the stages make them.
    pub fn columns(&self) -> Vec<String> {
        let mut out = vec!["path".to_owned()];
        let last = self
            .segments
            .last()
            .map(|s| s.stages.as_slice())
            .unwrap_or(&[]);
        for s in last {
            match s {
                Stage::Subscribe(cols) => out.extend(cols.iter().map(|c| c.name.clone())),
                Stage::Expression(e) => out.extend(e.iter().map(|(n, _)| n.clone())),
                Stage::Rename(r) => {
                    for (a, b) in r {
                        if let Some(c) = out.iter_mut().find(|c| *c == a) {
                            c.clone_from(b);
                        }
                    }
                }
                Stage::Drop(d) => out.retain(|c| !d.contains(c)),
                _ => {}
            }
        }
        let mut seen = BTreeSet::new();
        out.retain(|c| seen.insert(c.clone()));
        out
    }
}

// ---------- lexing helpers ----------

fn is_quote(c: char) -> bool {
    matches!(c, '"' | '\'' | '`')
}

/// Splits at `sep` outside quotes and brackets. With `sep = '|'` a `||` is not a separator.
pub(crate) fn split_top(s: &str, sep: char) -> Result<Vec<String>, String> {
    let mut out = Vec::new();
    let (mut cur, mut depth, mut quote) = (String::new(), 0i32, None::<char>);
    let cs: Vec<char> = s.chars().collect();
    let mut i = 0;
    while i < cs.len() {
        let c = cs[i];
        if let Some(q) = quote {
            cur.push(c);
            if c == '\\' && i + 1 < cs.len() {
                cur.push(cs[i + 1]);
                i += 2;
                continue;
            }
            if c == q {
                quote = None;
            }
        } else if is_quote(c) {
            quote = Some(c);
            cur.push(c);
        } else if matches!(c, '(' | '[' | '{') {
            depth += 1;
            cur.push(c);
        } else if matches!(c, ')' | ']' | '}') {
            depth -= 1;
            cur.push(c);
        } else if c == sep && depth == 0 {
            if sep == '|' && (cs.get(i + 1) == Some(&'|') || cur.ends_with('|')) {
                cur.push(c);
            } else {
                out.push(std::mem::take(&mut cur));
            }
        } else {
            cur.push(c);
        }
        i += 1;
    }
    if quote.is_some() {
        return Err("a quote is not closed".into());
    }
    if depth != 0 {
        return Err("brackets do not match".into());
    }
    out.push(cur);
    Ok(out)
}

/// `"text"` → `text` (a backslash escapes the quote); anything else as it is.
pub(crate) fn unquote(s: &str) -> String {
    let s = s.trim();
    let mut cs = s.chars();
    match (cs.next(), s.chars().last()) {
        (Some(a), Some(b)) if is_quote(a) && a == b && s.len() >= 2 => {
            let inner = &s[1..s.len() - 1];
            let mut out = String::with_capacity(inner.len());
            let mut it = inner.chars().peekable();
            while let Some(c) = it.next() {
                if c == '\\' && it.peek() == Some(&a) {
                    out.push(a);
                    it.next();
                } else {
                    out.push(c);
                }
            }
            out
        }
        _ => s.to_owned(),
    }
}

/// Words separated by whitespace or commas, quotes kept together.
fn words(s: &str) -> Result<Vec<String>, String> {
    let mut out = Vec::new();
    let (mut cur, mut quote) = (String::new(), None::<char>);
    for c in s.chars() {
        match quote {
            Some(q) => {
                cur.push(c);
                if c == q {
                    quote = None;
                }
            }
            None if is_quote(c) => {
                quote = Some(c);
                cur.push(c);
            }
            None if c.is_whitespace() || c == ',' => {
                if !cur.is_empty() {
                    out.push(std::mem::take(&mut cur));
                }
            }
            None => cur.push(c),
        }
    }
    if quote.is_some() {
        return Err("a quote is not closed".into());
    }
    if !cur.is_empty() {
        out.push(cur);
    }
    Ok(out)
}

/// `name=value name2="a b" …` (values quoted or one word).
fn pairs(s: &str) -> Result<Vec<(String, String)>, String> {
    let mut out = Vec::new();
    let cs: Vec<char> = s.chars().collect();
    let mut i = 0;
    let skip = |i: &mut usize| {
        while *i < cs.len() && (cs[*i].is_whitespace() || cs[*i] == ',') {
            *i += 1;
        }
    };
    loop {
        skip(&mut i);
        if i >= cs.len() {
            return Ok(out);
        }
        let start = i;
        while i < cs.len() && cs[i] != '=' && !cs[i].is_whitespace() {
            i += 1;
        }
        let name = unquote(&cs[start..i].iter().collect::<String>());
        while i < cs.len() && cs[i].is_whitespace() {
            i += 1;
        }
        if i >= cs.len() || cs[i] != '=' {
            return Err(format!("{name}: expected name=value"));
        }
        i += 1;
        while i < cs.len() && cs[i].is_whitespace() {
            i += 1;
        }
        let vstart = i;
        if i < cs.len() && is_quote(cs[i]) {
            let q = cs[i];
            i += 1;
            while i < cs.len() && cs[i] != q {
                if cs[i] == '\\' {
                    i += 1;
                }
                i += 1;
            }
            if i >= cs.len() {
                return Err(format!("{name}: a quote is not closed"));
            }
            i += 1;
        } else {
            while i < cs.len() && !cs[i].is_whitespace() && cs[i] != ',' {
                i += 1;
            }
        }
        let value: String = cs[vstart..i].iter().collect();
        if name.is_empty() || value.is_empty() {
            return Err("expected name=value".into());
        }
        out.push((name, value));
    }
}

// ---------- stages ----------

fn sub_key(text: &str) -> Result<SubKey, String> {
    let row = |part| Ok(SubKey { node: None, part });
    match text {
        "value" => return row(Part::Value),
        "value.timestamp" => return row(Part::Timestamp),
        "value.quality" => return row(Part::Quality),
        "$name" | ":displayName" | ":display" => return row(Part::Meta("display".into())),
        ":name" => return row(Part::Meta("name".into())),
        ":path" => return row(Part::Meta("path".into())),
        ":actions" => return row(Part::Meta("actions".into())),
        _ => {}
    }
    if let Some(f) = text.strip_prefix('$') {
        if META_FIELDS.contains(&f) {
            return row(Part::Meta(f.to_owned()));
        }
        return Err(format!("{text}: a meta field ${}", META_FIELDS.join(", $")));
    }
    if let Some(a) = text.strip_prefix('@') {
        if a.is_empty() {
            return Err("@: an attribute name".into());
        }
        return row(Part::Attr(a.to_owned()));
    }
    if text.starts_with(':') {
        return Err(format!(
            "{text}: not a known :key (:name, :display, :path, :actions)"
        ));
    }
    let (node, part) = if let Some(n) = text.strip_suffix(".timestamp") {
        (n, Part::Timestamp)
    } else if let Some(n) = text.strip_suffix(".quality") {
        (n, Part::Quality)
    } else {
        (text, Part::Value)
    };
    let node = node.trim_start_matches("./");
    if node.is_empty() || node.contains('*') || node.contains('~') {
        return Err(format!(
            "{text}: a child key (./a/b) or value, $field, @attr, :name"
        ));
    }
    Ok(SubKey {
        node: Some(node.to_owned()),
        part,
    })
}

fn subscribe(arg: &str) -> Result<Vec<Column>, String> {
    let ws = words(arg)?;
    if ws.is_empty() {
        return Ok(vec![Column {
            key: SubKey {
                node: None,
                part: Part::Value,
            },
            name: "value".into(),
        }]);
    }
    let mut out = Vec::new();
    let mut i = 0;
    while i < ws.len() {
        let text = unquote(&ws[i]);
        let name = if ws.get(i + 1).map(String::as_str) == Some("as") {
            let n = ws
                .get(i + 2)
                .ok_or_else(|| format!("{text} as: a column name"))?;
            i += 2;
            unquote(n)
        } else {
            text.clone()
        };
        out.push(Column {
            key: sub_key(&text)?,
            name,
        });
        i += 1;
    }
    Ok(out)
}

fn arg_of(text: &str) -> Result<Arg, String> {
    let text = text.trim();
    if let Some(c) = text.strip_prefix('%') {
        if !c.is_empty() && !c.contains(char::is_whitespace) {
            return Ok(Arg::Col(c.to_owned()));
        }
    }
    Expr::compile(text).map(Arg::Expr)
}

fn invoke(arg: &str) -> Result<Sink, String> {
    let arg = arg.trim();
    let open = arg
        .find('(')
        .ok_or("expected <node>/~act/<action>(<param>=<value>, …)")?;
    if !arg.ends_with(')') {
        return Err("the parameters end with )".into());
    }
    let target = arg[..open].trim();
    let (node, action) = match target.rsplit_once("/~act/") {
        Some((n, a)) => (n.to_owned(), a.to_owned()),
        None if !target.contains('/') => (".".to_owned(), target.to_owned()),
        None => {
            return Err(format!(
                "{target}: <node>/~act/<action>, or <action> on the row"
            ))
        }
    };
    wyrm_core::keyspace::validate_segment(&action)
        .map_err(|_| format!("{action}: an action name"))?;
    let mut params = Vec::new();
    let inner = &arg[open + 1..arg.len() - 1];
    for p in split_top(inner, ',')? {
        if p.trim().is_empty() {
            continue;
        }
        let (k, v) = p
            .split_once('=')
            .ok_or_else(|| format!("{}: expected <param>=<value>", p.trim()))?;
        params.push((k.trim().to_owned(), arg_of(v)?));
    }
    Ok(Sink::Invoke {
        node,
        action,
        params,
    })
}

fn set(arg: &str) -> Result<Sink, String> {
    let (node, v) = arg.split_once('=').ok_or("expected set <node> = <value>")?;
    let node = node.trim();
    if node.is_empty() || node.contains('*') {
        return Err("set: a node key (relative or full)".into());
    }
    Ok(Sink::Set {
        node: node.to_owned(),
        value: arg_of(v)?,
    })
}

fn parse_options(arg: &str, o: &mut Options) -> Result<(), String> {
    for (k, v) in pairs(arg)? {
        let v = unquote(&v);
        let num = || v.parse::<u64>().map_err(|_| format!("{k}: a whole number"));
        match k.as_str() {
            "invoke_allow_null" | "invokeAllowNull" => {
                o.invoke_allow_null = v.parse().map_err(|_| format!("{k}: true or false"))?;
            }
            "throttle_ms" => o.throttle_ms = num()?.min(3_600_000),
            "max_rows" => o.max_rows = Some(num()? as usize),
            "timeout_s" => o.timeout_s = Some(num()?),
            // DSA options that mean nothing here: QoS belongs to the point (`cfg.qos`), a key
            // says which site it reads, and actions are not nodes
            "qos" | "traverseBrokers" | "brokersIncludeQuarantine" | "listActions" => {}
            _ => return Err(format!("{k}: an unknown option")),
        }
    }
    Ok(())
}

fn sources(arg: &str) -> Result<Vec<Pattern>, String> {
    let mut out = Vec::new();
    for p in split_top(arg, ',')? {
        let p = p.trim();
        if p.is_empty() {
            continue;
        }
        if let Some(site) = p.strip_prefix("sites") {
            let site = site.trim();
            let parts: Vec<&str> = site.split('/').collect();
            if parts.len() != 2 || parts[0] != "wy" || parts[1].is_empty() {
                return Err("list sites wy/<site>".into());
            }
            out.push(Pattern::parse(&format!("{site}/upstream"))?);
            out.push(Pattern::parse(&format!("{site}/downstream"))?);
            continue;
        }
        out.push(Pattern::parse(p)?);
    }
    if out.is_empty() {
        return Err("list <pattern>[, <pattern>…]".into());
    }
    Ok(out)
}

fn path_root(arg: &str) -> Result<Pattern, String> {
    let key = arg.trim();
    check_key(key)?;
    let (parent, name) = key.rsplit_once('/').expect("a full key has segments");
    if parent.split('/').count() < 3 {
        return Err(format!("{key}: a node below a section"));
    }
    Ok(Pattern {
        top: parent.to_owned(),
        segs: vec![Seg::Lit(name.to_owned())],
    })
}

/// A `sites` source keeps only broker nodes under `downstream` (`attr.root`).
fn sites_filter(arg: &str) -> Option<Expr> {
    let site = split_top(arg, ',')
        .ok()?
        .into_iter()
        .find_map(|p| p.trim().strip_prefix("sites").map(|s| s.trim().to_owned()))?;
    Expr::compile(&format!(
        "path.startsWith('{site}/upstream/') || (attr != null && 'root' in attr)"
    ))
    .ok()
}

/// Parse a WYRM DQL text.
pub fn parse(text: &str) -> Result<Plan, ParseError> {
    let whole = |msg: String| ParseError { stage: 0, msg };
    let text = text.trim();
    if text.is_empty() {
        return Err(whole("an empty query".into()));
    }
    if text.len() > MAX_TEXT {
        return Err(whole(format!("a query is at most {MAX_TEXT} bytes")));
    }
    let parts = split_top(text, '|').map_err(whole)?;
    if parts.len() > MAX_STAGES {
        return Err(whole(format!("at most {MAX_STAGES} stages")));
    }
    let mut segments: Vec<Segment> = Vec::new();
    let mut options = Options::default();
    let mut full_meta = false;
    for (i, part) in parts.iter().enumerate() {
        let n = i + 1;
        let err = |msg: String| ParseError { stage: n, msg };
        let part = part.trim();
        let (cmd, arg) = part
            .split_once(char::is_whitespace)
            .map(|(c, a)| (c, a.trim()))
            .unwrap_or((part, ""));
        let cmd = cmd.to_ascii_lowercase();
        let stage = match cmd.as_str() {
            "list" | "lista" | "path" => {
                if !segments.is_empty() {
                    return Err(err(format!("{cmd} begins a query; use sublist below rows")));
                }
                let roots = if cmd == "path" {
                    vec![path_root(arg).map_err(err)?]
                } else {
                    sources(arg).map_err(err)?
                };
                let mut stages = Vec::new();
                if let Some(f) = sites_filter(arg) {
                    full_meta = true;
                    stages.push(Stage::Where(f));
                }
                segments.push(Segment {
                    source: Source::Roots(roots),
                    stages,
                });
                continue;
            }
            "sublist" => {
                if segments.is_empty() {
                    return Err(err("a query begins with list or path".into()));
                }
                let segs = Pattern::relative(arg).map_err(err)?;
                segments.push(Segment {
                    source: Source::Below(segs),
                    stages: Vec::new(),
                });
                continue;
            }
            "option" => {
                parse_options(arg, &mut options).map_err(err)?;
                continue;
            }
            "where" => Stage::Where(Expr::compile(arg).map_err(err)?),
            "filter" => {
                let (cel, cols) = crate::dsa::filter_to_cel(arg).map_err(err)?;
                if !cols.is_empty() {
                    let cols = cols
                        .iter()
                        .map(|c| {
                            Ok(Column {
                                key: sub_key(c)?,
                                name: c.clone(),
                            })
                        })
                        .collect::<Result<Vec<_>, String>>()
                        .map_err(err)?;
                    push_stage(&mut segments, Stage::Subscribe(cols)).map_err(err)?;
                }
                Stage::Where(Expr::compile(&cel).map_err(|e| err(format!("{e} (from {cel})")))?)
            }
            "subscribe" | "child" => Stage::Subscribe(subscribe(arg).map_err(err)?),
            "expression" | "expr" => {
                let mut cols = Vec::new();
                for (k, v) in pairs(arg).map_err(err)? {
                    let e = Expr::compile(&unquote(&v)).map_err(|e| err(format!("{k}: {e}")))?;
                    cols.push((k, e));
                }
                if cols.is_empty() {
                    return Err(err("expression <column>=\"<CEL>\"".into()));
                }
                Stage::Expression(cols)
            }
            "rename" => {
                let ws = words(arg).map_err(err)?;
                let mut out = Vec::new();
                let mut j = 0;
                while j < ws.len() {
                    if let Some((a, b)) = ws[j].split_once('=') {
                        out.push((unquote(a), unquote(b)));
                        j += 1;
                    } else if ws.get(j + 1).map(String::as_str) == Some("as") && j + 2 < ws.len() {
                        out.push((unquote(&ws[j]), unquote(&ws[j + 2])));
                        j += 3;
                    } else {
                        return Err(err(format!("{}: rename <a> as <b> or <a>=<b>", ws[j])));
                    }
                }
                Stage::Rename(out)
            }
            "drop" => Stage::Drop(
                words(arg)
                    .map_err(err)?
                    .iter()
                    .map(|w| unquote(w))
                    .collect(),
            ),
            "invoke" => Stage::Sink(invoke(arg).map_err(err)?),
            "set" => Stage::Sink(set(arg).map_err(err)?),
            _ => {
                return Err(err(format!(
                    "{cmd}: not a command (list, path, sublist, where, filter, subscribe, \
                     expression, rename, drop, option, invoke, set)"
                )))
            }
        };
        auto_subscribe(&mut segments, &stage).map_err(err)?;
        if stage_reads_full_meta(&stage) {
            full_meta = true;
        }
        push_stage(&mut segments, stage).map_err(err)?;
    }
    if segments.is_empty() {
        return Err(whole("a query begins with list or path".into()));
    }
    Ok(Plan {
        text: text.to_owned(),
        segments,
        options,
        full_meta,
    })
}

fn push_stage(segments: &mut [Segment], s: Stage) -> Result<(), String> {
    segments
        .last_mut()
        .ok_or_else(|| "a query begins with list or path".to_owned())?
        .stages
        .push(s);
    Ok(())
}

fn exprs(s: &Stage) -> Vec<&Expr> {
    match s {
        Stage::Where(e) => vec![e],
        Stage::Expression(v) => v.iter().map(|(_, e)| e).collect(),
        Stage::Sink(Sink::Invoke { params, .. }) => params
            .iter()
            .filter_map(|(_, a)| match a {
                Arg::Expr(e) => Some(e),
                Arg::Col(_) => None,
            })
            .collect(),
        Stage::Sink(Sink::Set {
            value: Arg::Expr(e),
            ..
        }) => vec![e],
        _ => Vec::new(),
    }
}

fn stage_reads_full_meta(s: &Stage) -> bool {
    let vars = exprs(s)
        .iter()
        .flat_map(|e| e.variables())
        .collect::<Vec<_>>();
    vars.iter()
        .any(|v| matches!(v.as_str(), "attr" | "actions" | "meta"))
        || match s {
            Stage::Subscribe(cols) => cols.iter().any(|c| {
                matches!(&c.key.part, Part::Attr(_)) || c.key.part == Part::Meta("actions".into())
            }),
            _ => false,
        }
}

/// Columns a CEL stage names that no stage before made: subscribed first, as DSA's filter did
/// (`value` is the row's value, another name a child's).
fn auto_subscribe(segments: &mut [Segment], s: &Stage) -> Result<(), String> {
    let Some(seg) = segments.last() else {
        return Ok(());
    };
    let mut made: BTreeSet<String> = ["path".to_owned()].into();
    for st in &seg.stages {
        match st {
            Stage::Subscribe(c) => made.extend(c.iter().map(|c| c.name.clone())),
            Stage::Expression(e) => made.extend(e.iter().map(|(n, _)| n.clone())),
            Stage::Rename(r) => made.extend(r.iter().map(|(_, b)| b.clone())),
            _ => {}
        }
    }
    let mut want: Vec<String> = exprs(s)
        .iter()
        .flat_map(|e| e.variables())
        .filter(|v| {
            !META_FIELDS.contains(&v.as_str())
                && !matches!(v.as_str(), "row" | "meta")
                && !made.contains(v)
        })
        .collect();
    if let Stage::Sink(Sink::Invoke { params, .. }) = s {
        want.extend(params.iter().filter_map(|(_, a)| match a {
            Arg::Col(c) if !made.contains(c) => Some(c.clone()),
            _ => None,
        }));
    }
    if let Stage::Sink(Sink::Set {
        value: Arg::Col(c), ..
    }) = s
    {
        if !made.contains(c) {
            want.push(c.clone());
        }
    }
    want.sort();
    want.dedup();
    if want.is_empty() {
        return Ok(());
    }
    let cols = want
        .into_iter()
        .map(|w| {
            Ok(Column {
                key: sub_key(&w)?,
                name: w,
            })
        })
        .collect::<Result<Vec<_>, String>>()?;
    push_stage(segments, Stage::Subscribe(cols))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pipelines_split_outside_quotes_and_or() {
        assert_eq!(
            split_top("list a | where x > 1 || y | expression m=\"a | b\"", '|').unwrap(),
            vec!["list a ", " where x > 1 || y ", " expression m=\"a | b\""]
        );
        assert!(split_top("list 'a", '|').is_err());
    }

    #[test]
    fn a_full_query() {
        let p = parse(
            "list wy/s/downstream/plc/** | where type == 'number' | subscribe value value.timestamp as t \
             | expression double=\"value * 2.0\" | rename t as time | drop path",
        )
        .unwrap();
        assert_eq!(p.segments.len(), 1);
        assert_eq!(p.roots(), vec!["wy/s/downstream/plc"]);
        assert!(p.uses_values() && !p.has_sinks() && !p.full_meta);
        assert_eq!(p.columns(), vec!["value", "time", "double"]);
    }

    #[test]
    fn where_subscribes_what_it_names() {
        let p = parse("list wy/s/downstream/m | where value > 20").unwrap();
        let st = &p.segments[0].stages;
        assert!(matches!(&st[0], Stage::Subscribe(c) if c[0].name == "value"));
        assert!(matches!(&st[1], Stage::Where(_)));
        assert!(p.uses_values());
        let p = parse("list wy/s/downstream/m | where attr.unit == '%'").unwrap();
        assert!(p.full_meta && !p.uses_values());
    }

    #[test]
    fn sinks_and_sublists() {
        let p = parse(
            "list sites wy/c | sublist ./downstream/* | subscribe | \
             invoke wy/c/downstream/db/~act/publish(Path=%path, Value=%value, k=\"x\") | set ./out = value + 1",
        )
        .unwrap();
        assert_eq!(p.segments.len(), 2);
        assert!(p.full_meta && p.has_sinks());
        assert_eq!(
            p.sinks(),
            vec!["wy/c/downstream/db/~act/publish", "./out/~set"]
        );
        let p = parse("path wy/s/downstream/plc/p | invoke ack(by=%path)").unwrap();
        assert!(
            matches!(&p.segments[0].stages[0], Stage::Sink(Sink::Invoke { node, action, .. }) if node == "." && action == "ack")
        );
    }

    #[test]
    fn errors_name_the_stage() {
        let e = parse("list wy/s/downstream | nope").unwrap_err();
        assert_eq!(e.stage, 2);
        assert_eq!(parse("where x").unwrap_err().stage, 1);
        assert_eq!(
            parse("list wy/s/downstream | where 1 +").unwrap_err().stage,
            2
        );
        assert_eq!(parse("list x").unwrap_err().stage, 1);
        assert_eq!(
            parse("list wy/s/downstream | list wy/s/x")
                .unwrap_err()
                .stage,
            2
        );
        assert_eq!(
            parse("list wy/s/downstream | option bad=1")
                .unwrap_err()
                .stage,
            2
        );
        assert_eq!(parse("").unwrap_err().stage, 0);
        let p = parse("list wy/s/downstream | option throttle_ms=500 max_rows=10 qos=2").unwrap();
        assert_eq!(p.options.throttle_ms, 500);
        assert_eq!(p.options.max_rows, Some(10));
    }
}
