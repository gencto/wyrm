//! Node types of the first iteration (wiki "Типи нод"): sources `subscribe`,
//! `timer`, `const`, `liveliness`; operators `expression`, `scale`,
//! `deadband`, `window`, `alarm`, `latch`, `delay`, `filter`; sinks
//! `publish`, `invoke`, `set`; `wasm` (a `wyrm:flow/node` component from
//! the artifact store, iteration 8).
//!
//! Quality: one-input operators pass `q` through; `expression` uses
//! `quality: worst|ignore|custom`. Time: an operator's `t` is the max `t` of
//! the inputs it used. `invoke`/`set` never act on a `bad` input unless
//! `allow_bad: true`.

use crate::artifacts::Artifacts;
use crate::def::Map;
use crate::script;
use std::collections::{BTreeMap, VecDeque};
use std::sync::Arc;
use std::time::Duration;
use tracing::debug;
use wyrm_client::{ValEvent, WyrmClient};
use wyrm_core::{Perm, Quality, Value};
use wyrm_link_sdk::{now_us, LinkCtx};

/// What flows on an edge (spec 06: the `~val` sample plus its source key).
#[derive(Debug, Clone, PartialEq)]
pub struct Msg {
    pub v: Value,
    pub q: Quality,
    pub t: u64,
    pub key: Option<Arc<str>>,
}

impl Msg {
    pub fn new(v: Value, q: Quality, t: u64) -> Self {
        Self { v, q, t, key: None }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PortType {
    Number,
    Bool,
    Map,
    Any,
}

impl PortType {
    pub fn fits(self, to: PortType) -> bool {
        self == to || self == PortType::Any || to == PortType::Any
    }

    pub fn name(self) -> &'static str {
        match self {
            PortType::Number => "number",
            PortType::Bool => "bool",
            PortType::Map => "map",
            PortType::Any => "any",
        }
    }
}

#[derive(Debug, Clone, Default, PartialEq)]
pub struct Ports {
    pub inputs: Vec<(String, PortType)>,
    pub outputs: Vec<(String, PortType)>,
}

impl Ports {
    fn new(inputs: &[(&str, PortType)], outputs: &[(&str, PortType)]) -> Self {
        Self {
            inputs: inputs.iter().map(|(n, t)| ((*n).to_owned(), *t)).collect(),
            outputs: outputs.iter().map(|(n, t)| ((*n).to_owned(), *t)).collect(),
        }
    }

    /// `out`, `event`, or `out.<name>` for a named output.
    pub fn output(&self, port: &str) -> Option<PortType> {
        let p = port.strip_prefix("out.").unwrap_or(port);
        self.outputs
            .iter()
            .find(|(n, _)| n == port || n == p)
            .map(|(_, t)| *t)
    }

    pub fn input(&self, port: &str) -> Option<PortType> {
        self.inputs.iter().find(|(n, _)| n == port).map(|(_, t)| *t)
    }

    /// Canonical output name (`out.event` → `event`).
    pub fn canon_output(&self, port: &str) -> String {
        let p = port.strip_prefix("out.").unwrap_or(port);
        if self.outputs.iter().any(|(n, _)| n == p) {
            p.to_owned()
        } else {
            port.to_owned()
        }
    }
}

// ---------- config helpers ----------

fn f(cfg: &Map, k: &str) -> Result<Option<f64>, String> {
    match cfg.get(k) {
        None => Ok(None),
        Some(v) => v
            .as_f64()
            .filter(|x| x.is_finite())
            .map(Some)
            .ok_or_else(|| format!("{k}: expected a finite number")),
    }
}

fn s<'a>(cfg: &'a Map, k: &str) -> Result<Option<&'a str>, String> {
    match cfg.get(k) {
        None => Ok(None),
        Some(Value::Str(x)) => Ok(Some(x)),
        Some(_) => Err(format!("{k}: expected a string")),
    }
}

fn req_s<'a>(cfg: &'a Map, k: &str) -> Result<&'a str, String> {
    s(cfg, k)?.ok_or_else(|| format!("{k}: required"))
}

fn b(cfg: &Map, k: &str, default: bool) -> Result<bool, String> {
    match cfg.get(k) {
        None => Ok(default),
        Some(Value::Bool(x)) => Ok(*x),
        Some(_) => Err(format!("{k}: expected true or false")),
    }
}

fn only(cfg: &Map, known: &[&str]) -> Result<(), String> {
    match cfg.keys().find(|k| !known.contains(&k.as_str())) {
        Some(k) => Err(format!("{k}: unknown field")),
        None => Ok(()),
    }
}

fn one_of<'a>(
    cfg: &'a Map,
    k: &str,
    allowed: &[&'a str],
    default: &'a str,
) -> Result<&'a str, String> {
    let v = s(cfg, k)?.unwrap_or(default);
    allowed
        .iter()
        .copied()
        .find(|a| *a == v)
        .ok_or_else(|| format!("{k}: one of {allowed:?}"))
}

fn names(cfg: &Map) -> Result<Vec<String>, String> {
    match cfg.get("inputs") {
        Some(Value::Array(a)) if !a.is_empty() => a
            .iter()
            .map(|v| match v {
                Value::Str(n)
                    if !n.is_empty()
                        && n.chars().all(|c| c.is_ascii_alphanumeric() || c == '_') =>
                {
                    Ok(n.clone())
                }
                _ => Err("inputs: names must be [A-Za-z0-9_]+".to_owned()),
            })
            .collect(),
        _ => Err("inputs: required non-empty array".into()),
    }
}

/// `window.max_samples`: an integer 1..=100 000, default 10 000. One parser
/// for the node and for the compiler's memory check.
pub fn max_samples(cfg: &Map) -> Result<u64, String> {
    match cfg.get("max_samples") {
        None => Ok(10_000),
        Some(Value::UInt(u)) if (1..=100_000).contains(u) => Ok(*u),
        Some(Value::Float(x)) if x.fract() == 0.0 && (1.0..=100_000.0).contains(x) => Ok(*x as u64),
        Some(_) => Err("max_samples: integer 1..=100000".into()),
    }
}

/// The key a command sink acts on (`<path>/~act/<action>`, `<path>/~set`),
/// relative or absolute as written; `None` for other node types.
pub fn command_target(ty: &str, cfg: &Map) -> Option<String> {
    let path = match cfg.get("path") {
        Some(Value::Str(p)) => p.trim_end_matches('/'),
        _ => return None,
    };
    match (ty, cfg.get("action")) {
        ("invoke", Some(Value::Str(a))) => Some(format!("{path}/~act/{a}")),
        ("set", _) => Some(format!("{path}/~set")),
        _ => None,
    }
}

/// Ports and config validation of a node type (compiler step 3).
pub fn ports(ty: &str, cfg: &Map) -> Result<Ports, String> {
    use PortType::*;
    Ok(match ty {
        "subscribe" => {
            only(cfg, &["key"])?;
            req_s(cfg, "key")?;
            Ports::new(&[], &[("out", Any)])
        }
        "timer" => {
            only(cfg, &["period_ms"])?;
            let p = f(cfg, "period_ms")?.ok_or("period_ms: required")?;
            if p < 10.0 {
                return Err("period_ms: at least 10".into());
            }
            Ports::new(&[], &[("out", Number)])
        }
        "const" => {
            only(cfg, &["value"])?;
            cfg.get("value").ok_or("value: required")?;
            Ports::new(&[], &[("out", Any)])
        }
        "liveliness" => {
            only(cfg, &["key"])?;
            req_s(cfg, "key")?;
            Ports::new(&[], &[("out", Bool)])
        }
        "expression" => {
            only(cfg, &["inputs", "expr", "trigger", "quality"])?;
            req_s(cfg, "expr")?;
            one_of(cfg, "trigger", &["any", "all"], "any")?;
            one_of(cfg, "quality", &["worst", "ignore", "custom"], "worst")?;
            let ins: Vec<String> = names(cfg)?.into_iter().map(|n| format!("in.{n}")).collect();
            Ports {
                inputs: ins.into_iter().map(|n| (n, Any)).collect(),
                outputs: vec![("out".into(), Any)],
            }
        }
        "scale" => {
            only(cfg, &["k", "b"])?;
            f(cfg, "k")?;
            f(cfg, "b")?;
            Ports::new(&[("in", Number)], &[("out", Number)])
        }
        "deadband" => {
            only(cfg, &["abs", "pct"])?;
            if f(cfg, "abs")?.is_none() && f(cfg, "pct")?.is_none() {
                return Err("abs or pct: required".into());
            }
            Ports::new(&[("in", Number)], &[("out", Number)])
        }
        "window" => {
            only(cfg, &["kind", "size_s", "fn", "max_samples"])?;
            one_of(cfg, "kind", &["tumbling", "sliding"], "tumbling")?;
            one_of(
                cfg,
                "fn",
                &["avg", "min", "max", "sum", "count", "rate"],
                "avg",
            )?;
            max_samples(cfg)?;
            let size = f(cfg, "size_s")?.ok_or("size_s: required")?;
            if size <= 0.0 {
                return Err("size_s: must be > 0".into());
            }
            Ports::new(&[("in", Number)], &[("out", Number)])
        }
        "alarm" => {
            only(
                cfg,
                &[
                    "high",
                    "low",
                    "hysteresis",
                    "delay_s",
                    "return_delay_s",
                    "on_bad",
                ],
            )?;
            if f(cfg, "high")?.is_none() && f(cfg, "low")?.is_none() {
                return Err("high or low: required".into());
            }
            f(cfg, "hysteresis")?;
            f(cfg, "delay_s")?;
            f(cfg, "return_delay_s")?;
            one_of(cfg, "on_bad", &["hold", "clear", "raise"], "hold")?;
            Ports::new(&[("in", Number)], &[("out", Bool), ("event", Map)])
        }
        "latch" => {
            only(cfg, &["reset"])?;
            one_of(cfg, "reset", &["manual", "auto"], "manual")?;
            Ports::new(&[("in", Bool), ("reset", Bool)], &[("out", Bool)])
        }
        "delay" => {
            only(cfg, &["ms"])?;
            f(cfg, "ms")?.ok_or("ms: required")?;
            Ports::new(&[("in", Any)], &[("out", Any)])
        }
        "filter" => {
            only(cfg, &["expr"])?;
            req_s(cfg, "expr")?;
            Ports::new(&[("in", Any)], &[("out", Any)])
        }
        "publish" => {
            only(cfg, &["node", "meta"])?;
            let n = req_s(cfg, "node")?;
            wyrm_core::keyspace::validate_segment(n).map_err(|e| format!("node: {e}"))?;
            if let Some(m) = cfg.get("meta") {
                if !matches!(m, Value::Map(_)) {
                    return Err("meta: expected a map".into());
                }
            }
            Ports::new(&[("in", Any)], &[])
        }
        "invoke" => {
            only(cfg, &["path", "action", "args", "on", "allow_bad"])?;
            req_s(cfg, "path")?;
            req_s(cfg, "action")?;
            one_of(cfg, "on", &["any", "rising", "falling", "change"], "any")?;
            b(cfg, "allow_bad", false)?;
            Ports::new(&[("in", Any)], &[("out", Any)])
        }
        "set" => {
            only(cfg, &["path", "on", "deadband", "allow_bad"])?;
            req_s(cfg, "path")?;
            one_of(cfg, "on", &["any", "change"], "change")?;
            f(cfg, "deadband")?;
            b(cfg, "allow_bad", false)?;
            Ports::new(&[("in", Any)], &[])
        }
        "wasm" => {
            let w = WasmCfg::parse(cfg)?;
            Ports {
                inputs: w.inputs.into_iter().map(|n| (n, Any)).collect(),
                outputs: w.outputs.into_iter().map(|n| (n, Any)).collect(),
            }
        }
        other => return Err(format!("type: unknown node type {other}")),
    })
}

/// Compiler step 6: rhai compiles with only the declared names.
pub fn check_script(ty: &str, cfg: &Map) -> Result<(), String> {
    let e = script::engine();
    match ty {
        "expression" => {
            let n = names(cfg)?;
            let refs: Vec<&str> = n.iter().map(String::as_str).collect();
            script::compile(&e, req_s(cfg, "expr")?, &refs)
                .map(|_| ())
                .map_err(|m| format!("expr: {m}"))
        }
        "filter" => script::compile(&e, req_s(cfg, "expr")?, &["v", "q", "t"])
            .map(|_| ())
            .map_err(|m| format!("expr: {m}")),
        _ => Ok(()),
    }
}

/// Minimum flow permission a node needs (compiler step 7).
pub fn needs_perm(ty: &str) -> Option<Perm> {
    matches!(ty, "invoke" | "set").then_some(Perm::Write)
}

// ---------- runtime interface ----------

/// Emitted samples of one call.
#[derive(Default)]
pub struct Out(pub Vec<(String, Msg)>);

impl Out {
    pub fn emit(&mut self, port: &str, m: Msg) {
        self.0.push((port.to_owned(), m));
    }
}

/// Feeds a sample into a node's own inbox on an internal port.
pub type Inject = Arc<dyn Fn(&str, Msg) + Send + Sync>;

/// Side-effect handle of a node (I/O happens in spawned tasks; results
/// come back through `inject` as inputs on internal ports `__*`).
#[derive(Clone)]
pub struct Io {
    pub client: WyrmClient,
    pub ctx: LinkCtx,
    pub site: String,
    pub flow: String,
    pub inject: Inject,
}

impl Io {
    /// `downstream/x` → `wy/<site>/downstream/x`; absolute `wy/...` kept.
    pub fn full_key(&self, k: &str) -> String {
        if k.starts_with("wy/") {
            k.to_owned()
        } else {
            format!("wy/{}/{}", self.site, k.trim_start_matches('/'))
        }
    }
}

pub trait Node: Send {
    /// Sources start their I/O here.
    fn start(&mut self, _io: &Io) {}
    fn input(&mut self, port: &str, m: Msg, io: &Io, out: &mut Out);
    fn tick_every(&self) -> Option<Duration> {
        None
    }
    fn tick(&mut self, _now: u64, _out: &mut Out) {}
    fn state(&self) -> Option<Value> {
        None
    }
    fn restore(&mut self, _state: &Value) {}
}

fn truthy(v: &Value) -> bool {
    match v {
        Value::Bool(b) => *b,
        v => v.as_f64().is_some_and(|x| x != 0.0),
    }
}

// ---------- sources ----------

struct Subscribe {
    key: String,
    last: Option<Value>,
}

impl Node for Subscribe {
    fn start(&mut self, io: &Io) {
        let pattern = io.full_key(&self.key);
        let (io2, client) = (io.clone(), io.client.clone());
        tokio::spawn(async move {
            let Ok(mut s) = client.subscribe(&pattern).await else {
                return;
            };
            while let Some(ev) = s.next().await {
                if let ValEvent::Sample { key, sample, .. } = ev {
                    (io2.inject)(
                        "__src",
                        Msg {
                            v: sample.v,
                            q: sample.q,
                            t: sample.t,
                            key: Some(key.into()),
                        },
                    );
                }
            }
        });
        // Owner gone → `bad/disconnected` with the previous value.
        let full = io.full_key(&self.key);
        if let Some(owner) = wyrm_client::owner_key(&full).filter(|o| !o.contains('*')) {
            let (io3, session) = (io.clone(), io.client.session().clone());
            tokio::spawn(async move {
                let Ok(sub) = session.liveliness().declare_subscriber(&owner).await else {
                    return;
                };
                while let Ok(s) = sub.recv_async().await {
                    if s.kind() == zenoh::sample::SampleKind::Delete {
                        (io3.inject)("__lost", Msg::new(Value::Null, Quality::Bad, now_us()));
                    }
                }
            });
        }
    }

    fn input(&mut self, port: &str, m: Msg, _io: &Io, out: &mut Out) {
        match port {
            "__src" => {
                self.last = Some(m.v.clone());
                out.emit("out", m);
            }
            "__lost" => {
                if let Some(v) = self.last.clone() {
                    out.emit("out", Msg::new(v, Quality::Bad, m.t));
                }
            }
            _ => {}
        }
    }
}

struct Timer {
    period: Duration,
    n: u64,
}

impl Node for Timer {
    fn input(&mut self, _p: &str, _m: Msg, _io: &Io, _out: &mut Out) {}
    fn tick_every(&self) -> Option<Duration> {
        Some(self.period)
    }
    fn tick(&mut self, now: u64, out: &mut Out) {
        self.n += 1;
        out.emit("out", Msg::new(Value::UInt(self.n), Quality::Good, now));
    }
}

struct Const(Value);

impl Node for Const {
    fn start(&mut self, io: &Io) {
        (io.inject)("__src", Msg::new(self.0.clone(), Quality::Good, now_us()));
    }
    fn input(&mut self, port: &str, m: Msg, _io: &Io, out: &mut Out) {
        if port == "__src" {
            out.emit("out", m);
        }
    }
}

struct Liveliness {
    key: String,
}

impl Node for Liveliness {
    fn start(&mut self, io: &Io) {
        let key = io.full_key(&self.key);
        let (io2, session) = (io.clone(), io.client.session().clone());
        tokio::spawn(async move {
            let Ok(sub) = session
                .liveliness()
                .declare_subscriber(&key)
                .history(true)
                .await
            else {
                return;
            };
            while let Ok(s) = sub.recv_async().await {
                let up = s.kind() == zenoh::sample::SampleKind::Put;
                (io2.inject)("__src", Msg::new(Value::Bool(up), Quality::Good, now_us()));
            }
        });
    }
    fn input(&mut self, port: &str, m: Msg, _io: &Io, out: &mut Out) {
        if port == "__src" {
            out.emit("out", m);
        }
    }
}

// ---------- operators ----------

struct Expression {
    engine: rhai::Engine,
    ast: rhai::AST,
    inputs: Vec<String>,
    last: BTreeMap<String, Msg>,
    fresh: BTreeMap<String, bool>,
    all: bool,
    quality: String,
    state: rhai::Map,
    errors: u64,
}

impl Expression {
    fn worst(&self) -> Quality {
        self.last
            .values()
            .map(|m| m.q)
            .max_by_key(|q| *q as u8)
            .unwrap_or(Quality::Good)
    }
}

impl Node for Expression {
    fn input(&mut self, port: &str, m: Msg, _io: &Io, out: &mut Out) {
        let Some(name) = port.strip_prefix("in.") else {
            return;
        };
        self.last.insert(name.to_owned(), m);
        self.fresh.insert(name.to_owned(), true);
        // Every input must have been seen; `all` also needs a fresh one each.
        if self.inputs.iter().any(|n| !self.last.contains_key(n)) {
            return;
        }
        if self.all
            && self
                .inputs
                .iter()
                .any(|n| !self.fresh.get(n).copied().unwrap_or(false))
        {
            return;
        }
        for v in self.fresh.values_mut() {
            *v = false;
        }
        let now = now_us();
        let vars = self
            .inputs
            .iter()
            .map(|n| {
                let m = &self.last[n];
                let mut map = rhai::Map::new();
                map.insert("v".into(), script::to_dynamic(&m.v));
                map.insert("q".into(), rhai::Dynamic::from_int(m.q as i64));
                map.insert("t".into(), rhai::Dynamic::from_int(m.t as i64));
                map.insert(
                    "age_ms".into(),
                    rhai::Dynamic::from_int((now.saturating_sub(m.t) / 1000) as i64),
                );
                (n.clone(), rhai::Dynamic::from_map(map))
            })
            .collect();
        let t = self.last.values().map(|m| m.t).max().unwrap_or(now);
        let r = match script::eval(&self.engine, &self.ast, vars, &mut self.state) {
            Ok(r) => r,
            Err(e) => {
                self.errors += 1;
                debug!("expression error: {e}");
                return;
            }
        };
        if r.is_unit() {
            return;
        }
        let q = match self.quality.as_str() {
            "ignore" => Quality::Good,
            "custom" => Quality::Good,
            _ => self.worst(),
        };
        let v = script::from_dynamic(&r);
        let (v, q) = match (&v, self.quality.as_str()) {
            (Value::Map(m), "custom") if m.contains_key("v") => {
                let q = match m.get("q").and_then(Value::as_f64) {
                    Some(x) => Quality::try_from(x as u8).unwrap_or(Quality::Bad),
                    None => q,
                };
                (m["v"].clone(), q)
            }
            _ => (v, q),
        };
        out.emit("out", Msg::new(v, q, t));
    }

    fn state(&self) -> Option<Value> {
        (!self.state.is_empty())
            .then(|| script::from_dynamic(&rhai::Dynamic::from_map(self.state.clone())))
    }

    fn restore(&mut self, st: &Value) {
        if let Some(m) = script::to_dynamic(st).try_cast::<rhai::Map>() {
            self.state = m;
        }
    }
}

struct Scale {
    k: f64,
    b: f64,
}

impl Node for Scale {
    fn input(&mut self, _p: &str, m: Msg, _io: &Io, out: &mut Out) {
        if let Some(x) = m.v.as_f64() {
            out.emit("out", Msg::new(Value::Float(x * self.k + self.b), m.q, m.t));
        }
    }
}

struct Deadband {
    abs: Option<f64>,
    pct: Option<f64>,
    last: Option<(f64, Quality)>,
}

impl Node for Deadband {
    fn input(&mut self, _p: &str, m: Msg, _io: &Io, out: &mut Out) {
        let Some(x) = m.v.as_f64() else { return };
        let pass = match self.last {
            None => true,
            Some((l, q)) => {
                q != m.q
                    || self.abs.is_some_and(|a| (x - l).abs() >= a)
                    || self
                        .pct
                        .is_some_and(|p| (x - l).abs() >= l.abs() * p / 100.0)
            }
        };
        if pass {
            self.last = Some((x, m.q));
            out.emit("out", m);
        }
    }
    fn state(&self) -> Option<Value> {
        self.last
            .map(|(x, q)| Value::Array(vec![Value::Float(x), Value::UInt(q as u64)]))
    }
    fn restore(&mut self, st: &Value) {
        if let Value::Array(a) = st {
            if let (Some(x), Some(q)) = (
                a.first().and_then(Value::as_f64),
                a.get(1).and_then(Value::as_f64),
            ) {
                self.last = Some((x, Quality::try_from(q as u8).unwrap_or(Quality::Bad)));
            }
        }
    }
}

struct Window {
    tumbling: bool,
    size_us: u64,
    func: String,
    max: usize,
    buf: VecDeque<(u64, f64, Quality)>,
    start: Option<u64>,
}

impl Window {
    fn compute(&self, end: u64) -> Option<Msg> {
        if self.buf.is_empty() {
            return None;
        }
        let xs: Vec<f64> = self.buf.iter().map(|(_, x, _)| *x).collect();
        let v = match self.func.as_str() {
            "min" => xs.iter().copied().fold(f64::INFINITY, f64::min),
            "max" => xs.iter().copied().fold(f64::NEG_INFINITY, f64::max),
            "sum" => xs.iter().sum(),
            "count" => xs.len() as f64,
            "rate" => {
                let (t0, x0, _) = self.buf.front()?;
                let (t1, x1, _) = self.buf.back()?;
                if t1 <= t0 {
                    return None;
                }
                (x1 - x0) / ((t1 - t0) as f64 / 1e6)
            }
            _ => xs.iter().sum::<f64>() / xs.len() as f64,
        };
        let good = self
            .buf
            .iter()
            .filter(|(_, _, q)| *q == Quality::Good)
            .count();
        let q = if good * 2 < self.buf.len() {
            Quality::Uncertain
        } else {
            Quality::Good
        };
        Some(Msg::new(Value::Float(v), q, end))
    }
}

impl Node for Window {
    fn input(&mut self, _p: &str, m: Msg, _io: &Io, out: &mut Out) {
        let Some(x) = m.v.as_f64() else { return };
        if m.q == Quality::Bad {
            return;
        }
        self.start.get_or_insert(m.t);
        self.buf.push_back((m.t, x, m.q));
        while self.buf.len() > self.max {
            self.buf.pop_front();
        }
        if !self.tumbling {
            let from = m.t.saturating_sub(self.size_us);
            while self.buf.front().is_some_and(|(t, _, _)| *t < from) {
                self.buf.pop_front();
            }
            if let Some(r) = self.compute(m.t) {
                out.emit("out", r);
            }
        }
    }
    fn tick_every(&self) -> Option<Duration> {
        self.tumbling
            .then(|| Duration::from_micros(self.size_us.clamp(10_000, 1_000_000)))
    }
    fn tick(&mut self, now: u64, out: &mut Out) {
        let Some(start) = self.start else { return };
        if now >= start + self.size_us {
            let end = start + self.size_us;
            if let Some(r) = self.compute(end) {
                out.emit("out", r);
            }
            self.buf.clear();
            self.start = Some(end.max(now - (now - end) % self.size_us.max(1)));
        }
    }
    fn state(&self) -> Option<Value> {
        let items = self
            .buf
            .iter()
            .map(|(t, x, q)| {
                Value::Array(vec![
                    Value::UInt(*t),
                    Value::Float(*x),
                    Value::UInt(*q as u64),
                ])
            })
            .collect();
        Some(Value::Map(BTreeMap::from([
            ("buf".into(), Value::Array(items)),
            (
                "start".into(),
                self.start.map(Value::UInt).unwrap_or(Value::Null),
            ),
        ])))
    }
    fn restore(&mut self, st: &Value) {
        let Value::Map(m) = st else { return };
        if let Some(Value::UInt(s)) = m.get("start") {
            self.start = Some(*s);
        }
        if let Some(Value::Array(items)) = m.get("buf") {
            for it in items {
                if let Value::Array(a) = it {
                    if let (Some(Value::UInt(t)), Some(x), Some(q)) = (
                        a.first(),
                        a.get(1).and_then(Value::as_f64),
                        a.get(2).and_then(Value::as_f64),
                    ) {
                        self.buf.push_back((
                            *t,
                            x,
                            Quality::try_from(q as u8).unwrap_or(Quality::Bad),
                        ));
                    }
                }
            }
        }
    }
}

struct Alarm {
    high: Option<f64>,
    low: Option<f64>,
    hyst: f64,
    delay_us: u64,
    ret_us: u64,
    on_bad: String,
    active: bool,
    pending: Option<(bool, u64, f64)>,
}

impl Alarm {
    fn set(&mut self, on: bool, v: f64, t: u64, out: &mut Out) {
        if self.active == on {
            return;
        }
        self.active = on;
        out.emit("out", Msg::new(Value::Bool(on), Quality::Good, t));
        let mut ev = BTreeMap::new();
        ev.insert(
            "edge".into(),
            Value::Str(if on { "rising" } else { "falling" }.into()),
        );
        ev.insert("value".into(), Value::Float(v));
        ev.insert("t".into(), Value::UInt(t));
        out.emit("event", Msg::new(Value::Map(ev), Quality::Good, t));
    }
}

impl Node for Alarm {
    fn input(&mut self, _p: &str, m: Msg, _io: &Io, out: &mut Out) {
        if m.q == Quality::Bad {
            // Lost data must not raise false alarms or clear real ones.
            match self.on_bad.as_str() {
                "clear" => self.set(false, f64::NAN, m.t, out),
                "raise" => self.set(true, f64::NAN, m.t, out),
                _ => {}
            }
            self.pending = None;
            return;
        }
        let Some(x) = m.v.as_f64() else { return };
        let on = self.high.is_some_and(|h| x > h) || self.low.is_some_and(|l| x < l);
        let off = self.high.is_none_or(|h| x < h - self.hyst)
            && self.low.is_none_or(|l| x > l + self.hyst);
        if !self.active && on {
            if self.delay_us == 0 {
                self.set(true, x, m.t, out);
            } else if !matches!(self.pending, Some((true, _, _))) {
                self.pending = Some((true, m.t + self.delay_us, x));
            }
        } else if self.active && off {
            if self.ret_us == 0 {
                self.set(false, x, m.t, out);
            } else if !matches!(self.pending, Some((false, _, _))) {
                self.pending = Some((false, m.t + self.ret_us, x));
            }
        } else if !self.active && !on || self.active && !off {
            self.pending = None;
        }
    }
    fn tick_every(&self) -> Option<Duration> {
        (self.delay_us > 0 || self.ret_us > 0).then(|| Duration::from_millis(50))
    }
    fn tick(&mut self, now: u64, out: &mut Out) {
        if let Some((target, due, x)) = self.pending {
            if now >= due {
                self.pending = None;
                self.set(target, x, now, out);
            }
        }
    }
    fn state(&self) -> Option<Value> {
        Some(Value::Bool(self.active))
    }
    fn restore(&mut self, st: &Value) {
        if let Value::Bool(b) = st {
            self.active = *b;
        }
    }
}

struct Latch {
    auto: bool,
    on: bool,
}

impl Node for Latch {
    fn input(&mut self, port: &str, m: Msg, _io: &Io, out: &mut Out) {
        let v = truthy(&m.v);
        let next = match port {
            "reset" if v => false,
            "in" if v => true,
            "in" if self.auto => false,
            _ => self.on,
        };
        if next != self.on {
            self.on = next;
            out.emit("out", Msg::new(Value::Bool(next), m.q, m.t));
        }
    }
    fn state(&self) -> Option<Value> {
        Some(Value::Bool(self.on))
    }
    fn restore(&mut self, st: &Value) {
        if let Value::Bool(b) = st {
            self.on = *b;
        }
    }
}

struct Delay {
    us: u64,
    queue: VecDeque<(u64, Msg)>,
}

impl Node for Delay {
    fn input(&mut self, _p: &str, m: Msg, _io: &Io, _out: &mut Out) {
        self.queue.push_back((now_us() + self.us, m));
        while self.queue.len() > 10_000 {
            self.queue.pop_front();
        }
    }
    fn tick_every(&self) -> Option<Duration> {
        Some(Duration::from_micros(self.us.clamp(1_000, 100_000)))
    }
    fn tick(&mut self, now: u64, out: &mut Out) {
        while self.queue.front().is_some_and(|(due, _)| *due <= now) {
            if let Some((_, m)) = self.queue.pop_front() {
                out.emit("out", m);
            }
        }
    }
}

struct Filter {
    engine: rhai::Engine,
    ast: rhai::AST,
}

impl Node for Filter {
    fn input(&mut self, _p: &str, m: Msg, _io: &Io, out: &mut Out) {
        let vars = vec![
            ("v".to_owned(), script::to_dynamic(&m.v)),
            ("q".to_owned(), rhai::Dynamic::from_int(m.q as i64)),
            ("t".to_owned(), rhai::Dynamic::from_int(m.t as i64)),
        ];
        let mut st = rhai::Map::new();
        if let Ok(r) = script::eval(&self.engine, &self.ast, vars, &mut st) {
            if r.as_bool().unwrap_or(false) {
                out.emit("out", m);
            }
        }
    }
}

// ---------- sinks ----------

struct Publish {
    path: String,
}

impl Node for Publish {
    fn input(&mut self, _p: &str, m: Msg, io: &Io, _out: &mut Out) {
        let (ctx, path) = (io.ctx.clone(), self.path.clone());
        tokio::spawn(async move {
            let _ = ctx.update(&path, m.v, m.q, m.t).await;
        });
    }
}

/// Edge detection shared by command sinks.
fn should_fire(on: &str, last: &mut Option<Value>, v: &Value) -> bool {
    let prev = last.replace(v.clone());
    match on {
        "rising" => truthy(v) && !prev.as_ref().is_some_and(truthy),
        "falling" => !truthy(v) && prev.as_ref().is_some_and(truthy),
        "change" => prev.as_ref() != Some(v),
        _ => true,
    }
}

struct Invoke {
    path: String,
    action: String,
    args: Map,
    on: String,
    allow_bad: bool,
    last: Option<Value>,
}

impl Node for Invoke {
    fn input(&mut self, port: &str, m: Msg, io: &Io, out: &mut Out) {
        if port == "__result" {
            out.emit("out", m);
            return;
        }
        if m.q == Quality::Bad && !self.allow_bad {
            return; // never act on bad data
        }
        if !should_fire(&self.on, &mut self.last, &m.v) {
            return;
        }
        // `"$in"` in args is replaced by the input value.
        let args: Map = self
            .args
            .iter()
            .map(|(k, v)| {
                let v = match v {
                    Value::Str(s) if s == "$in" => m.v.clone(),
                    v => v.clone(),
                };
                (k.clone(), v)
            })
            .collect();
        let (io2, node, action) = (io.clone(), io.full_key(&self.path), self.action.clone());
        tokio::spawn(async move {
            let r = io2
                .client
                .invoke_one(&node, &action, Value::Map(args))
                .await;
            let msg = match r {
                Ok(v) => Msg::new(v.unwrap_or(Value::Null), Quality::Good, now_us()),
                Err(e) => Msg::new(Value::Str(e.to_string()), Quality::Bad, now_us()),
            };
            (io2.inject)("__result", msg);
        });
    }
}

struct Set {
    path: String,
    on: String,
    deadband: f64,
    allow_bad: bool,
    last: Option<Value>,
}

impl Node for Set {
    fn input(&mut self, _p: &str, m: Msg, io: &Io, _out: &mut Out) {
        if m.q == Quality::Bad && !self.allow_bad {
            return;
        }
        if self.on == "change" {
            let within = match (self.last.as_ref().and_then(Value::as_f64), m.v.as_f64()) {
                (Some(a), Some(b)) => (a - b).abs() <= self.deadband,
                _ => self.last.as_ref() == Some(&m.v),
            };
            if within {
                return;
            }
        }
        self.last = Some(m.v.clone());
        let (client, node) = (io.client.clone(), io.full_key(&self.path));
        tokio::spawn(async move {
            if let Err(e) = client.set(&node, m.v).await {
                debug!("flow set {node}: {e}");
            }
        });
    }
}

/// Build a node (config already checked by [`ports`]).
pub fn build(ty: &str, flow: &str, id: &str, cfg: &Map) -> Result<Box<dyn Node>, String> {
    build_with(ty, flow, id, cfg, None)
}

/// [`build`] with the artifact store that `wasm` nodes load from.
pub fn build_with(
    ty: &str,
    flow: &str,
    id: &str,
    cfg: &Map,
    artifacts: Option<&Artifacts>,
) -> Result<Box<dyn Node>, String> {
    let num = |k: &str, d: f64| f(cfg, k).map(|x| x.unwrap_or(d));
    Ok(match ty {
        "subscribe" => Box::new(Subscribe {
            key: req_s(cfg, "key")?.to_owned(),
            last: None,
        }),
        "timer" => Box::new(Timer {
            period: Duration::from_secs_f64(num("period_ms", 1000.0)? / 1000.0),
            n: 0,
        }),
        "const" => Box::new(Const(cfg.get("value").cloned().unwrap_or(Value::Null))),
        "liveliness" => Box::new(Liveliness {
            key: req_s(cfg, "key")?.to_owned(),
        }),
        "expression" => {
            let inputs = names(cfg)?;
            let engine = script::engine();
            let refs: Vec<&str> = inputs.iter().map(String::as_str).collect();
            let ast = script::compile(&engine, req_s(cfg, "expr")?, &refs)?;
            Box::new(Expression {
                engine,
                ast,
                inputs,
                last: BTreeMap::new(),
                fresh: BTreeMap::new(),
                all: one_of(cfg, "trigger", &["any", "all"], "any")? == "all",
                quality: one_of(cfg, "quality", &["worst", "ignore", "custom"], "worst")?
                    .to_owned(),
                state: rhai::Map::new(),
                errors: 0,
            })
        }
        "scale" => Box::new(Scale {
            k: num("k", 1.0)?,
            b: num("b", 0.0)?,
        }),
        "deadband" => Box::new(Deadband {
            abs: f(cfg, "abs")?,
            pct: f(cfg, "pct")?,
            last: None,
        }),
        "window" => Box::new(Window {
            tumbling: one_of(cfg, "kind", &["tumbling", "sliding"], "tumbling")? == "tumbling",
            size_us: (num("size_s", 60.0)? * 1e6) as u64,
            func: one_of(
                cfg,
                "fn",
                &["avg", "min", "max", "sum", "count", "rate"],
                "avg",
            )?
            .to_owned(),
            max: max_samples(cfg)? as usize,
            buf: VecDeque::new(),
            start: None,
        }),
        "alarm" => Box::new(Alarm {
            high: f(cfg, "high")?,
            low: f(cfg, "low")?,
            hyst: num("hysteresis", 0.0)?,
            delay_us: (num("delay_s", 0.0)? * 1e6) as u64,
            ret_us: (num("return_delay_s", 0.0)? * 1e6) as u64,
            on_bad: one_of(cfg, "on_bad", &["hold", "clear", "raise"], "hold")?.to_owned(),
            active: false,
            pending: None,
        }),
        "latch" => Box::new(Latch {
            auto: one_of(cfg, "reset", &["manual", "auto"], "manual")? == "auto",
            on: false,
        }),
        "delay" => Box::new(Delay {
            us: (num("ms", 0.0)? * 1000.0) as u64,
            queue: VecDeque::new(),
        }),
        "filter" => {
            let engine = script::engine();
            let ast = script::compile(&engine, req_s(cfg, "expr")?, &["v", "q", "t"])?;
            Box::new(Filter { engine, ast })
        }
        "publish" => Box::new(Publish {
            path: format!("{flow}/nodes/{}", req_s(cfg, "node")?),
        }),
        "invoke" => Box::new(Invoke {
            path: req_s(cfg, "path")?.to_owned(),
            action: req_s(cfg, "action")?.to_owned(),
            args: match cfg.get("args") {
                Some(Value::Map(m)) => m.clone(),
                _ => Map::new(),
            },
            on: one_of(cfg, "on", &["any", "rising", "falling", "change"], "any")?.to_owned(),
            allow_bad: b(cfg, "allow_bad", false)?,
            last: None,
        }),
        "set" => Box::new(Set {
            path: req_s(cfg, "path")?.to_owned(),
            on: one_of(cfg, "on", &["any", "change"], "change")?.to_owned(),
            deadband: num("deadband", 0.0)?,
            allow_bad: b(cfg, "allow_bad", false)?,
            last: None,
        }),
        "wasm" => {
            let store = artifacts.ok_or("wasm: no artifact store")?;
            Box::new(Wasm::new(WasmCfg::parse(cfg)?, store)?)
        }
        other => return Err(format!("{id}: unknown node type {other}")),
    })
}

// ---------- wasm ----------

/// `wasm` node config: `artifact` (hex SHA-256 in the artifact store),
/// `inputs`/`outputs` (port names, default `["in"]`/`["out"]`), `config`
/// (any value, given to the guest's `init` as CBOR), `fuel` (per call),
/// `memory_mb`.
#[derive(Clone)]
pub struct WasmCfg {
    pub artifact: String,
    pub inputs: Vec<String>,
    pub outputs: Vec<String>,
    pub config: Value,
    pub limits: wyrm_wasm_host::Limits,
}

fn port_names(cfg: &Map, k: &str, default: &str) -> Result<Vec<String>, String> {
    let ok = |n: &str| {
        !n.is_empty()
            && !n.starts_with("__")
            && n.chars().all(|c| c.is_ascii_alphanumeric() || c == '_')
    };
    match cfg.get(k) {
        None => Ok(vec![default.to_owned()]),
        Some(Value::Array(a)) if !a.is_empty() && a.len() <= 16 => {
            let mut out: Vec<String> = Vec::new();
            for v in a {
                match v {
                    Value::Str(n) if ok(n) && !out.contains(n) => out.push(n.clone()),
                    _ => return Err(format!("{k}: unique names [A-Za-z0-9_]+")),
                }
            }
            Ok(out)
        }
        Some(_) => Err(format!("{k}: 1..=16 port names")),
    }
}

fn uint_in(cfg: &Map, k: &str, lo: u64, hi: u64, default: u64) -> Result<u64, String> {
    match cfg.get(k) {
        None => Ok(default),
        Some(Value::UInt(u)) if (lo..=hi).contains(u) => Ok(*u),
        Some(Value::Float(x)) if x.fract() == 0.0 && (lo as f64..=hi as f64).contains(x) => {
            Ok(*x as u64)
        }
        Some(_) => Err(format!("{k}: integer {lo}..={hi}")),
    }
}

impl WasmCfg {
    pub fn parse(cfg: &Map) -> Result<Self, String> {
        use wyrm_wasm_host::Limits;
        only(
            cfg,
            &[
                "artifact",
                "inputs",
                "outputs",
                "config",
                "fuel",
                "memory_mb",
            ],
        )?;
        let artifact = req_s(cfg, "artifact")?;
        if !wyrm_wasm_host::is_sha256_hex(artifact) {
            return Err("artifact: 64 lowercase hex characters (SHA-256)".into());
        }
        let d = Limits::default();
        let fuel = uint_in(cfg, "fuel", 1_000, Limits::MAX.fuel, d.fuel)?;
        let mb = uint_in(
            cfg,
            "memory_mb",
            1,
            (Limits::MAX.memory_bytes >> 20) as u64,
            (d.memory_bytes >> 20) as u64,
        )?;
        Ok(Self {
            artifact: artifact.to_owned(),
            inputs: port_names(cfg, "inputs", "in")?,
            outputs: port_names(cfg, "outputs", "out")?,
            config: cfg.get("config").cloned().unwrap_or(Value::Null),
            limits: Limits {
                fuel,
                memory_bytes: (mb as usize) << 20,
                ..d
            },
        })
    }

    /// Load the artifact, instantiate and run the guest's `init` (deploy
    /// check).
    pub fn check(&self, artifacts: &Artifacts) -> Result<(), String> {
        Wasm::new(self.clone(), artifacts).map(|_| ())
    }
}

/// Most samples one `process` call may emit.
const WASM_MAX_EMITS: u64 = 256;

struct Wasm {
    node: wyrm_wasm_host::FlowNode,
    outputs: Vec<String>,
    state: Vec<u8>,
    errors: u64,
}

impl Wasm {
    fn new(cfg: WasmCfg, artifacts: &Artifacts) -> Result<Self, String> {
        let art = artifacts.get(&cfg.artifact)?;
        let config = wyrm_core::codec::to_vec(&cfg.config).map_err(|e| format!("config: {e}"))?;
        let mut node =
            wyrm_wasm_host::FlowNode::new(wyrm_wasm_host::Slot::new(art), config, cfg.limits);
        node.start().map_err(|e| format!("artifact: {e}"))?;
        Ok(Self {
            node,
            outputs: cfg.outputs,
            state: Vec::new(),
            errors: 0,
        })
    }
}

/// `[[port, sample], …]` from the guest.
fn decode_emits(b: &[u8]) -> Result<Vec<(String, wyrm_core::Sample)>, String> {
    let mut d = minicbor::Decoder::new(b);
    let n = d
        .array()
        .map_err(|e| e.to_string())?
        .ok_or("emits: indefinite array")?;
    if n > WASM_MAX_EMITS {
        return Err(format!("emits: more than {WASM_MAX_EMITS}"));
    }
    let mut out = Vec::new();
    for _ in 0..n {
        if d.array().map_err(|e| e.to_string())? != Some(2) {
            return Err("emits: expected [port, sample]".into());
        }
        let port = d.str().map_err(|e| e.to_string())?.to_owned();
        let s: wyrm_core::Sample = d.decode().map_err(|e| e.to_string())?;
        out.push((port, s));
    }
    if d.position() != b.len() {
        return Err("emits: trailing bytes".into());
    }
    Ok(out)
}

impl Node for Wasm {
    fn input(&mut self, port: &str, m: Msg, _io: &Io, out: &mut Out) {
        if port.starts_with("__") {
            return;
        }
        let sample = wyrm_core::Sample {
            v: m.v,
            q: m.q,
            t: m.t,
        };
        let Ok(bytes) = wyrm_core::codec::to_vec(&sample) else {
            self.errors += 1;
            return;
        };
        let r = self
            .node
            .process(port, &bytes, &self.state)
            .map_err(|e| e.to_string())
            .and_then(|(emits, state)| Ok((decode_emits(&emits)?, state)));
        match r {
            Ok((emits, state)) => {
                self.state = state;
                for (p, s) in emits {
                    if self.outputs.contains(&p) {
                        out.emit(&p, Msg::new(s.v, s.q, s.t));
                    } else {
                        self.errors += 1;
                        debug!("wasm: emit on undeclared port {p}");
                    }
                }
            }
            Err(e) => {
                // Like `expression`: no sample, no panic, the flow keeps running.
                self.errors += 1;
                debug!(errors = self.errors, "wasm node error: {e}");
            }
        }
    }

    fn state(&self) -> Option<Value> {
        (!self.state.is_empty()).then(|| Value::Bytes(self.state.clone()))
    }

    fn restore(&mut self, state: &Value) {
        if let Value::Bytes(b) = state {
            self.state = b.clone();
        }
    }
}
