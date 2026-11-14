//! rhai sandbox (wiki "Скриптинг rhai"): no I/O, no `eval`/`import`, strict
//! variables (only declared inputs and `state`), 10 000 operations, 8 call
//! levels, 4 KiB strings, 1024-item arrays, 10 ms per call.
//!
//! The 10 ms are time the script itself takes: CPU time of the thread that runs it. Time
//! the host kept that thread off a core is not the script's, and a sample is never dropped
//! for it.

use rhai::{Dynamic, Engine, Scope, AST};
use std::cell::Cell;
use std::collections::BTreeMap;
use std::time::{Duration, Instant};
use wyrm_core::Value;

const TIMEOUT: Duration = Duration::from_millis(10);

thread_local! {
    static STARTED: Cell<Option<Started>> = const { Cell::new(None) };
}

/// The start of one call: the wall clock is the cheap check, the thread's CPU time decides.
#[derive(Clone, Copy)]
struct Started {
    wall: Instant,
    cpu: Option<Duration>,
}

impl Started {
    fn now() -> Self {
        Self {
            wall: Instant::now(),
            cpu: thread_cpu(),
        }
    }

    /// True once the call used more than [`TIMEOUT`]. A call cannot use more CPU time than
    /// went by, so the CPU clock (a system call) is read only after the wall clock is past
    /// the limit.
    fn late(&self) -> bool {
        if self.wall.elapsed() <= TIMEOUT {
            return false;
        }
        match (self.cpu, thread_cpu()) {
            (Some(from), Some(now)) => now.saturating_sub(from) > TIMEOUT,
            // no thread CPU clock on this platform (wasm32, NetBSD, illumos, Windows):
            // the wall clock is all there is
            _ => true,
        }
    }
}

/// CPU time this thread has used so far.
#[cfg(any(
    target_os = "linux",
    target_os = "android",
    target_vendor = "apple",
    target_os = "freebsd",
    target_os = "openbsd",
    target_os = "dragonfly"
))]
fn thread_cpu() -> Option<Duration> {
    let t = rustix::time::clock_gettime(rustix::time::ClockId::ThreadCPUTime);
    Some(Duration::new(
        u64::try_from(t.tv_sec).ok()?,
        u32::try_from(t.tv_nsec).ok()?,
    ))
}

#[cfg(not(any(
    target_os = "linux",
    target_os = "android",
    target_vendor = "apple",
    target_os = "freebsd",
    target_os = "openbsd",
    target_os = "dragonfly"
)))]
fn thread_cpu() -> Option<Duration> {
    None
}

fn now_ms() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
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
        let late = STARTED.with(|s| s.get().is_some_and(|t| t.late()));
        late.then(|| Dynamic::from("timeout"))
    });
    e.on_print(|_| {});
    e.on_debug(|_, _, _| {});
    e.register_fn("now_ms", now_ms);
    e.register_fn("clamp", |x: f64, lo: f64, hi: f64| x.clamp(lo, hi));
    e.register_fn("round", |x: f64, n: i64| {
        let p = 10f64.powi(n.clamp(0, 12) as i32);
        (x * p).round() / p
    });
    e.register_fn("lerp", |a: f64, b: f64, t: f64| a + (b - a) * t);
    e.register_fn("hour", || (now_ms() / 3_600_000) % 24);
    e.register_fn("weekday", || (now_ms() / 86_400_000 + 3) % 7); // 0 = Monday
    e
}

/// Compile `expr` with only `names` (and `state`) defined.
pub fn compile(engine: &Engine, expr: &str, names: &[&str]) -> Result<AST, String> {
    let mut scope = Scope::new();
    for n in names {
        scope.push_dynamic(*n, Dynamic::UNIT);
    }
    scope.push_dynamic("state", Dynamic::from_map(rhai::Map::new()));
    engine
        .compile_with_scope(&scope, expr)
        .map_err(|e| e.to_string())
}

/// Evaluate within [`TIMEOUT`] of the thread's CPU time. `vars` become variables; `state` is
/// read and written back.
pub fn eval(
    engine: &Engine,
    ast: &AST,
    vars: Vec<(String, Dynamic)>,
    state: &mut rhai::Map,
) -> Result<Dynamic, String> {
    let mut scope = Scope::new();
    for (k, v) in vars {
        scope.push_dynamic(k, v);
    }
    scope.push_dynamic("state", Dynamic::from_map(std::mem::take(state)));
    STARTED.with(|s| s.set(Some(Started::now())));
    let r = engine.eval_ast_with_scope::<Dynamic>(&mut scope, ast);
    STARTED.with(|s| s.set(None));
    if let Some(m) = scope.get_value::<rhai::Map>("state") {
        *state = m;
    }
    r.map_err(|e| e.to_string())
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
        Value::Str(s) => Dynamic::from(s.clone()),
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
    if let Some(b) = d.clone().try_cast::<bool>() {
        return Value::Bool(b);
    }
    if let Some(i) = d.clone().try_cast::<i64>() {
        return Value::from(i);
    }
    if let Some(f) = d.clone().try_cast::<f64>() {
        return Value::Float(f);
    }
    if let Some(s) = d.clone().try_cast::<rhai::ImmutableString>() {
        return Value::Str(s.to_string());
    }
    if let Some(b) = d.clone().try_cast::<rhai::Blob>() {
        return Value::Bytes(b);
    }
    if let Some(a) = d.clone().try_cast::<rhai::Array>() {
        return Value::Array(a.iter().map(from_dynamic).collect());
    }
    if let Some(m) = d.clone().try_cast::<rhai::Map>() {
        return Value::Map(
            m.iter()
                .map(|(k, v)| (k.to_string(), from_dynamic(v)))
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
    #[cfg(any(
        target_os = "linux",
        target_os = "android",
        target_vendor = "apple",
        target_os = "freebsd",
        target_os = "openbsd",
        target_os = "dragonfly"
    ))]
    #[test]
    fn time_off_the_core_is_not_the_scripts() {
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
        let from = Instant::now();
        let err = eval(&e, &ast, vec![], &mut st).unwrap_err();
        assert!(err.contains("terminated"), "{err}");
        assert!(from.elapsed() < Duration::from_secs(5));
    }
}
