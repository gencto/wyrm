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

    /// The variable `state` as the scope holds it.
    fn state_var(&self) -> Option<&Dynamic> {
        let name = STATE;
        self.scope.get(name)
    }

    fn state_var_mut(&mut self) -> Option<&mut Dynamic> {
        let name = STATE;
        self.scope.get_mut(name)
    }

    /// `state` as a value; `None` while it is empty.
    pub fn state(&self) -> Option<Value> {
        let st = self.state_var()?;
        let empty = st.as_map_ref().map_or(true, |m| m.is_empty());
        (!empty).then(|| from_dynamic(st))
    }

    /// Replaces `state`.
    pub fn set_state(&mut self, state: rhai::Map) {
        if let Some(st) = self.state_var_mut() {
            *st = Dynamic::from_map(state);
        }
    }

    /// Empties `state`: for a script whose calls share nothing.
    pub fn clear_state(&mut self) {
        let Some(st) = self.state_var_mut() else {
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
                .state_var()
                .is_some_and(|st| st.is_map() && !st.is_shared() && st.tag() == 0);
        if plain {
            return;
        }
        let state = self.scope.get_value::<rhai::Map>(STATE).unwrap_or_default();
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
            let same =
                m.len() == keys.len() && m.keys().zip(keys.clone()).all(|(a, b)| a.as_str() == b);
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
        Value::Str(s) => Dynamic::from(rhai::ImmutableString::from(s.as_str())),
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
        let mut st = Vars::new(&[]);
        assert!(eval(&e, &ast, &mut st).is_err(), "endless loop stops");
        let ast = compile(&e, "state.n = (state.n ?? 0) + 1; state.n", &[]).unwrap();
        for i in 1..=3 {
            let r = eval(&e, &ast, &mut st).unwrap();
            assert_eq!(r.as_int().unwrap(), i);
        }
        assert_eq!(
            from_dynamic(&to_dynamic(&Value::Float(2.5))),
            Value::Float(2.5)
        );
    }

    fn int(vars: &mut Vars, i: usize, x: i64) {
        *vars.var(i).unwrap() = Dynamic::from_int(x);
    }

    /// The variables are kept between calls, and nothing of one call reaches the next but
    /// `state`: a variable a script declares is gone, also one that hides an input or `state`.
    #[test]
    fn a_variable_of_one_call_is_not_seen_by_the_next() {
        let e = engine();
        let mut vars = Vars::new(&["a"]);
        // `let` in one call; the next call's script cannot even be compiled to read it, and a
        // script that declares it again starts from nothing
        let set = compile(&e, "let leaked = a + 1; leaked", &["a"]).unwrap();
        int(&mut vars, 0, 41);
        assert_eq!(eval(&e, &set, &mut vars).unwrap().as_int().unwrap(), 42);
        assert_eq!(vars.scope.len(), 2, "only a and state stay");
        assert!(!vars.scope.contains("leaked"));
        assert!(compile(&e, "leaked", &["a"]).is_err());
        // a `let` that hides the input: the next call reads the input it was given
        let hide = compile(&e, "let a = 1000; a", &["a"]).unwrap();
        int(&mut vars, 0, 1);
        assert_eq!(eval(&e, &hide, &mut vars).unwrap().as_int().unwrap(), 1000);
        let read = compile(&e, "a", &["a"]).unwrap();
        int(&mut vars, 0, 7);
        assert_eq!(eval(&e, &read, &mut vars).unwrap().as_int().unwrap(), 7);
        // an assignment to the input does not outlive the call either: the caller sets it
        let assign = compile(&e, "a = 99; a", &["a"]).unwrap();
        int(&mut vars, 0, 2);
        assert_eq!(eval(&e, &assign, &mut vars).unwrap().as_int().unwrap(), 99);
        int(&mut vars, 0, 3);
        assert_eq!(eval(&e, &read, &mut vars).unwrap().as_int().unwrap(), 3);
        assert_eq!(vars.state(), None, "no state was written");
    }

    /// A call that fails leaves nothing behind but what it wrote into `state` before it
    /// failed, as before: the variables it declared are gone.
    #[test]
    fn a_call_that_fails_leaves_nothing_behind() {
        let e = engine();
        let mut vars = Vars::new(&["a"]);
        let fail = compile(&e, "let x = 5; let y = [1, 2]; throw \"no\"", &["a"]).unwrap();
        int(&mut vars, 0, 1);
        let err = eval(&e, &fail, &mut vars).unwrap_err();
        assert!(err.contains("no"), "{err}");
        assert_eq!(vars.scope.len(), 2);
        assert!(!vars.scope.contains("x") && !vars.scope.contains("y"));
        assert_eq!(vars.state(), None);
        // an endless loop that declared variables on its way
        let spin = compile(&e, "let z = 1; loop { let w = z; }", &["a"]).unwrap();
        assert!(eval(&e, &spin, &mut vars).is_err());
        assert_eq!(vars.scope.len(), 2);
        // the next call is as the first
        let read = compile(&e, "a * 2", &["a"]).unwrap();
        int(&mut vars, 0, 21);
        assert_eq!(eval(&e, &read, &mut vars).unwrap().as_int().unwrap(), 42);
        // what a failed call wrote into state before it failed stays (as with a scope per
        // call, which read the state back after an error too)
        let half = compile(&e, "state.n = 1; throw \"late\"", &["a"]).unwrap();
        assert!(eval(&e, &half, &mut vars).is_err());
        assert_eq!(
            vars.state(),
            Some(Value::Map([("n".to_owned(), Value::UInt(1))].into()))
        );
    }

    /// `state` after a call is what a scope per call gave: a `let state` that is a map
    /// becomes the state, one that is no map empties it, and the variable itself is gone.
    #[test]
    fn a_script_that_hides_state_keeps_the_old_rules() {
        let e = engine();
        let mut vars = Vars::new(&[]);
        let count = compile(&e, "state.n = (state.n ?? 0) + 1; state.n", &[]).unwrap();
        assert_eq!(eval(&e, &count, &mut vars).unwrap().as_int().unwrap(), 1);
        let map = compile(&e, "let state = #{n: 10}; 0", &[]).unwrap();
        assert!(eval(&e, &map, &mut vars).is_ok());
        assert_eq!(vars.scope.len(), 1);
        assert_eq!(eval(&e, &count, &mut vars).unwrap().as_int().unwrap(), 11);
        let no_map = compile(&e, "let state = 5; 0", &[]).unwrap();
        assert!(eval(&e, &no_map, &mut vars).is_ok());
        assert_eq!(vars.scope.len(), 1);
        assert_eq!(vars.state(), None);
        assert_eq!(eval(&e, &count, &mut vars).unwrap().as_int().unwrap(), 1);
        // state assigned something that is no map: an empty state for the next call
        let assign = compile(&e, "state = 5; 0", &[]).unwrap();
        assert!(eval(&e, &assign, &mut vars).is_ok());
        assert_eq!(vars.state(), None);
        assert_eq!(eval(&e, &count, &mut vars).unwrap().as_int().unwrap(), 1);
        vars.clear_state();
        assert_eq!(vars.state(), None);
    }

    /// `set_map` uses the map of the call before only for the same keys, and replaces every
    /// value: what a script added, removed or changed in it is gone.
    #[test]
    fn a_variable_map_is_whole_again_for_every_call() {
        let e = engine();
        let mut vars = Vars::new(&["row"]);
        let set = |vars: &mut Vars, kv: &[(&str, i64)]| {
            set_map(
                vars.var(0).unwrap(),
                kv.iter().map(|(k, _)| *k),
                kv.iter().map(|(_, v)| Dynamic::from_int(*v)),
            );
        };
        let dirty = compile(
            &e,
            "row.extra = 1; row.a = -1; row.remove(\"b\"); 0",
            &["row"],
        )
        .unwrap();
        let read = compile(&e, "row", &["row"]).unwrap();
        let seen = |vars: &mut Vars| from_dynamic(&eval(&e, &read, vars).unwrap());
        let want = |kv: &[(&str, i64)]| {
            Value::Map(
                kv.iter()
                    .map(|(k, v)| ((*k).to_owned(), Value::from(*v)))
                    .collect(),
            )
        };
        set(&mut vars, &[("a", 1), ("b", 2)]);
        assert!(eval(&e, &dirty, &mut vars).is_ok());
        set(&mut vars, &[("a", 3), ("b", 4)]);
        assert_eq!(seen(&mut vars), want(&[("a", 3), ("b", 4)]));
        // same keys: the values alone are replaced
        set(&mut vars, &[("a", 5), ("b", 6)]);
        assert_eq!(seen(&mut vars), want(&[("a", 5), ("b", 6)]));
        // other keys, fewer keys, more keys
        set(&mut vars, &[("a", 7), ("c", 8)]);
        assert_eq!(seen(&mut vars), want(&[("a", 7), ("c", 8)]));
        set(&mut vars, &[("a", 9)]);
        assert_eq!(seen(&mut vars), want(&[("a", 9)]));
        set(&mut vars, &[("a", 1), ("b", 2), ("c", 3)]);
        assert_eq!(seen(&mut vars), want(&[("a", 1), ("b", 2), ("c", 3)]));
        // a variable a script made something else
        let other = compile(&e, "row = 5; 0", &["row"]).unwrap();
        assert!(eval(&e, &other, &mut vars).is_ok());
        set(&mut vars, &[("a", 1)]);
        assert_eq!(seen(&mut vars), want(&[("a", 1)]));
    }

    /// The conversions read in place and give what they gave: every kind of value there and
    /// back.
    #[test]
    fn values_go_there_and_back() {
        let v = Value::Map(
            [
                ("b".to_owned(), Value::Bool(true)),
                ("f".to_owned(), Value::Float(2.5)),
                ("i".to_owned(), Value::Int(-3)),
                ("n".to_owned(), Value::Null),
                ("s".to_owned(), Value::Str("text".into())),
                ("y".to_owned(), Value::Bytes(vec![1, 2, 3])),
                (
                    "a".to_owned(),
                    Value::Array(vec![Value::UInt(1), Value::Str("x".into())]),
                ),
            ]
            .into(),
        );
        assert_eq!(from_dynamic(&to_dynamic(&v)), v);
        assert_eq!(from_dynamic(&to_dynamic(&Value::Int(7))), Value::UInt(7));
        assert_eq!(
            from_dynamic(&to_dynamic(&Value::UInt(u64::MAX))),
            Value::Float(u64::MAX as f64)
        );
        assert_eq!(from_dynamic(&Dynamic::from('c')), Value::Str("c".into()));
        // a value a closure holds
        let shared = to_dynamic(&v).into_shared();
        assert_eq!(from_dynamic(&shared), v);
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
        let mut st = Vars::new(&[]);
        let r = eval(&e, &ast, &mut st).expect("not a timeout");
        assert_eq!(r.as_int().unwrap(), 3);
        // a script that does use its 10 ms still ends
        let ast = compile(&e, "off_core(); loop { }", &[]).unwrap();
        e.set_max_operations(0);
        let from = std::time::Instant::now();
        let err = eval(&e, &ast, &mut st).unwrap_err();
        assert!(err.contains("terminated"), "{err}");
        assert!(from.elapsed() < Duration::from_secs(5));
    }
}
