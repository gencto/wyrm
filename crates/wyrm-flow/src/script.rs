//! rhai sandbox (wiki "Скриптинг rhai"): no I/O, no `eval`/`import`, strict
//! variables (only declared inputs and `state`), 10 000 operations, 8 call
//! levels, 4 KiB strings, 1024-item arrays, 10 ms per call.
//!
//! The 10 ms are time the script itself takes: CPU time of the thread that runs it. Time
//! the host kept that thread off a core is not the script's, and a sample is never dropped
//! for it.

use crate::cpu_clock::Budget;
use rhai::{Dynamic, Engine, Scope, AST};
use std::cell::Cell;
use std::collections::BTreeMap;
use std::time::Duration;
use wyrm_core::clock::now_ms_signed;
use wyrm_core::Value;

const TIMEOUT: Duration = Duration::from_millis(10);

thread_local! {
    static STARTED: Cell<Option<Budget>> = const { Cell::new(None) };
}

/// A locked-down engine.
pub fn engine() -> Engine {
    let mut e = Engine::new();
    e.set_max_operations(10_000);
    e.set_max_call_levels(8);
    e.set_max_string_size(4096);
    e.set_max_array_size(1024);
    e.set_max_map_size(1024);
    e.set_max_expr_depths(64, 32);
    e.set_max_modules(0);
    e.set_strict_variables(true);
    e.disable_symbol("eval");
    e.disable_symbol("import");
    e.on_progress(|_ops| {
        let late = STARTED.with(|s| s.get().is_some_and(|t| t.spent()));
        late.then(|| Dynamic::from("timeout"))
    });
    e.on_print(|_| {});
    e.on_debug(|_, _, _| {});
    e.register_fn("now_ms", now_ms_signed);
    e.register_fn("clamp", |x: f64, lo: f64, hi: f64| x.clamp(lo, hi));
    e.register_fn("round", |x: f64, n: i64| {
        let p = 10f64.powi(n.clamp(0, 12) as i32);
        (x * p).round() / p
    });
    e.register_fn("lerp", |a: f64, b: f64, t: f64| a + (b - a) * t);
    e.register_fn("hour", || (now_ms_signed() / 3_600_000) % 24);
    e.register_fn("weekday", || (now_ms_signed() / 86_400_000 + 3) % 7); // 0 = Monday
    e
}

/// The variable a script keeps its own values in between its calls.
const STATE: &str = "state";

/// The variables of a script, kept between its calls: the declared names in their order, then
/// `state`, as [`compile`] declares them. A scope made anew for every call cost eight
/// allocations (its lists, a name each, the state's box in and out); this one is made once.
///
/// Nothing of one call reaches the next but `state`: the caller gives every variable its
/// value before a call ([`Vars::var`]), and [`eval`] takes away what the script declared and
/// brings `state` back to a plain map.
pub struct Vars {
    scope: Scope<'static>,
    /// The declared names in their order; `None` for one that a later name or `state` hides
    /// (a script can never read it).
    names: Vec<Option<String>>,
}

impl Vars {
    /// The variables `names` (and `state`), each `()` until it is set.
    pub fn new(names: &[&str]) -> Self {
        let mut scope = Scope::new();
        for n in names {
            scope.push_dynamic(*n, Dynamic::UNIT);
        }
        scope.push_dynamic(STATE, Dynamic::from_map(rhai::Map::new()));
        let names = names
            .iter()
            .enumerate()
            .map(|(i, n)| {
                let hidden = *n == STATE || names.iter().skip(i + 1).any(|later| later == n);
                (!hidden).then(|| (*n).to_owned())
            })
            .collect();
        Self { scope, names }
    }

    /// The variable declared at place `i`, to be given its value for the next call; `None`
    /// for a name that another hides.
    pub fn var(&mut self, i: usize) -> Option<&mut Dynamic> {
        let name = self.names.get(i)?.as_deref()?;
        self.scope.get_mut(name)
    }

    /// `state` as a value; `None` while it is empty.
    pub fn state(&self) -> Option<Value> {
        let st = self.scope.get(STATE)?;
        let empty = st.as_map_ref().map_or(true, |m| m.is_empty());
        (!empty).then(|| from_dynamic(st))
    }

    /// Replaces `state`.
    pub fn set_state(&mut self, state: rhai::Map) {
        if let Some(st) = self.scope.get_mut(STATE) {
            *st = Dynamic::from_map(state);
        }
    }

    /// Empties `state`: for a script whose calls share nothing.
    pub fn clear_state(&mut self) {
        let Some(st) = self.scope.get_mut(STATE) else {
            return;
        };
        if let Ok(mut m) = st.as_map_mut() {
            if !m.is_empty() {
                m.clear();
            }
        }
    }

    /// How many variables every call starts with.
    fn base(&self) -> usize {
        self.names.len() + 1
    }

    /// After a call: the variables the script declared go, and `state` is a plain map again.
    /// What the script left under the name `state` is the state when it is a map (also one
    /// that a `let state` or a closure holds), and an empty map otherwise, as it was when
    /// every call had a scope of its own.
    fn settle(&mut self) {
        let base = self.base();
        let plain = self.scope.len() == base
            && self
                .scope
                .get(STATE)
                .is_some_and(|st| st.is_map() && !st.is_shared() && st.tag() == 0);
        if plain {
            return;
        }
        let state = self
            .scope
            .get_value::<rhai::Map>(STATE)
            .unwrap_or_default();
        self.scope.rewind(base);
        self.set_state(state);
    }
}

/// Compile `expr` with only `names` (and `state`) defined.
pub fn compile(engine: &Engine, expr: &str, names: &[&str]) -> Result<AST, String> {
    engine
        .compile_with_scope(&Vars::new(names).scope, expr)
        .map_err(|e| e.to_string())
}

/// Evaluate within [`TIMEOUT`] of the thread's CPU time, over `vars` (made by [`Vars::new`]
/// with the names `ast` was compiled with). `state` is read and written in place; a variable
/// the script declares is gone after the call, also when the call fails.
pub fn eval(engine: &Engine, ast: &AST, vars: &mut Vars) -> Result<Dynamic, String> {
    STARTED.with(|s| s.set(Some(Budget::start(TIMEOUT))));
    let r = engine.eval_ast_with_scope::<Dynamic>(&mut vars.scope, ast);
    STARTED.with(|s| s.set(None));
    vars.settle();
    r.map_err(|e| e.to_string())
}

/// Makes `slot` the map of `keys` and `values` (as many, in the same order). When `slot`
/// already is a plain map of exactly these keys in this order (the order of a map's keys),
/// only its values are replaced: the map of the call before is used again and nothing is
/// allocated for it. Every value is replaced either way, so nothing a script did to the map
/// stays.
pub fn set_map<'a>(
    slot: &mut Dynamic,
    keys: impl ExactSizeIterator<Item = &'a str> + Clone,
    values: impl Iterator<Item = Dynamic>,
) {
    // a map that a closure holds, or one with a tag, is not ours alone: a new one
    if !slot.is_shared() && slot.tag() == 0 {
        if let Ok(mut m) = slot.as_map_mut() {
            let same = m.len() == keys.len() && m.keys().zip(keys.clone()).all(|(a, b)| a == b);
            if same {
                for (cell, v) in m.values_mut().zip(values) {
                    *cell = v;
                }
                return;
            }
        }
    }
    *slot = Dynamic::from_map(keys.zip(values).map(|(k, v)| (k.into(), v)).collect());
}

pub fn to_dynamic(v: &Value) -> Dynamic {
    match v {
        Value::Null => Dynamic::UNIT,
        Value::Bool(b) => Dynamic::from_bool(*b),
        Value::Int(i) => Dynamic::from_int(*i),
        Value::UInt(u) => match i64::try_from(*u) {
            Ok(i) => Dynamic::from_int(i),
            Err(_) => Dynamic::from_float(*u as f64),
        },
        Value::Float(f) => Dynamic::from_float(*f),
        // from the text itself: no copy of the `String` on the way
        Value::Str(s) => Dynamic::from(s.as_str()),
        Value::Bytes(b) => Dynamic::from_blob(b.clone()),
        Value::Array(a) => Dynamic::from_array(a.iter().map(to_dynamic).collect()),
        Value::Map(m) => Dynamic::from_map(
            m.iter()
                .map(|(k, v)| (k.as_str().into(), to_dynamic(v)))
                .collect(),
        ),
    }
}

pub fn from_dynamic(d: &Dynamic) -> Value {
    if d.is_unit() {
        return Value::Null;
    }
    // a value a closure holds is read as a copy, so no lock is held while its items are read
    if d.is_shared() {
        return from_dynamic(&d.flatten_clone());
    }
    // read in place: no copy of a list or a map before its items are converted
    if let Some(b) = d.read_lock::<bool>() {
        return Value::Bool(*b);
    }
    if let Some(i) = d.read_lock::<i64>() {
        return Value::from(*i);
    }
    if let Some(f) = d.read_lock::<f64>() {
        return Value::Float(*f);
    }
    if let Some(s) = d.read_lock::<rhai::ImmutableString>() {
        return Value::Str(s.as_str().to_owned());
    }
    if let Some(b) = d.read_lock::<rhai::Blob>() {
        return Value::Bytes(b.clone());
    }
    if let Some(a) = d.read_lock::<rhai::Array>() {
        return Value::Array(a.iter().map(from_dynamic).collect());
    }
    if let Some(m) = d.read_lock::<rhai::Map>() {
        return Value::Map(
            m.iter()
                .map(|(k, v)| (k.as_str().to_owned(), from_dynamic(v)))
                .collect::<BTreeMap<_, _>>(),
        );
    }
    Value::Str(d.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn strict_names_and_limits() {
        let e = engine();
        assert!(compile(&e, "a + b", &["a", "b"]).is_ok());
        let err = compile(&e, "a + c", &["a"]).unwrap_err();
        assert!(err.contains('c'), "{err}");
        assert!(compile(&e, "eval(\"1\")", &[]).is_err());
        let ast = compile(&e, "loop { }", &[]).unwrap();
        let mut st = rhai::Map::new();
        assert!(
            eval(&e, &ast, vec![], &mut st).is_err(),
            "endless loop stops"
        );
        let ast = compile(&e, "state.n = (state.n ?? 0) + 1; state.n", &[]).unwrap();
        for i in 1..=3 {
            let r = eval(&e, &ast, vec![], &mut st).unwrap();
            assert_eq!(r.as_int().unwrap(), i);
        }
        assert_eq!(
            from_dynamic(&to_dynamic(&Value::Float(2.5))),
            Value::Float(2.5)
        );
    }

    /// A thread that the host keeps off its core is not a slow script: the limit counts
    /// the thread's CPU time. (On a loaded CI runner the wall clock ended a three-operation
    /// expression and its sample was dropped.)
    #[test]
    fn time_off_the_core_is_not_the_scripts() {
        if crate::cpu_clock::thread_cpu().is_none() {
            return; // no thread CPU clock here: the wall clock decides
        }
        let mut e = engine();
        // stands for a preemption: wall time goes by, the thread uses no CPU
        e.register_fn("off_core", || std::thread::sleep(TIMEOUT * 3));
        let ast = compile(&e, "off_core(); 1 + 2", &[]).unwrap();
        let mut st = rhai::Map::new();
        let r = eval(&e, &ast, vec![], &mut st).expect("not a timeout");
        assert_eq!(r.as_int().unwrap(), 3);
        // a script that does use its 10 ms still ends
        let ast = compile(&e, "off_core(); loop { }", &[]).unwrap();
        e.set_max_operations(0);
        let from = std::time::Instant::now();
        let err = eval(&e, &ast, vec![], &mut st).unwrap_err();
        assert!(err.contains("terminated"), "{err}");
        assert!(from.elapsed() < Duration::from_secs(5));
    }
}
