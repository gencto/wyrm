//! `portable-echo`: the reference portable link (ADR 0023). One source, three modes with the
//! same behaviour:
//! - embedded in a broker: `wyrm_link_portable::Portable<Echo>` (`wyrmd` registers it as the
//!   driver `portable-echo`);
//! - a process link: `cargo build --release --features process` (`src/bin`), packed by
//!   `wyr link pack --kind process`;
//! - a WASM component: `wyr link pack` builds the lib for `wasm32-unknown-unknown` with
//!   `--features wasm` and packs it with its capabilities (`[package.metadata.wyrm-link]`).
//!
//! The tree:
//! - `n`: a writable number kept in the link's store; it comes back after a restart or an
//!   upgrade;
//! - `ticks`: how many timers fired since this start (`ping` arms one);
//! - `starts`: how many times `start` ran, kept in the store;
//! - actions on the root: `ping` arms a 50 ms timer and answers `"pong"`; `echo {value}` answers
//!   `value`.
//!
//! The params (a map, validated in `start`): `faults` (bool, default false) adds the action
//! `crash`, which panics: a trap in WASM, a caught panic natively. The host drops the instance
//! and starts it again after a backoff; the store and `n` stay. The benchmarks of
//! `wyrm-link-portable` use it to time a restart.
//!
//! The app keeps no state the host cannot give back: the host may restart an instance at any
//! time.

use wyrm_core::meta::{ParamMeta, Writable};
use wyrm_core::{ActionMeta, NodeMeta, Perm, Quality, Sample, Status, TypeCode, Value};
use wyrm_link_api::{App, AppError, Host, TimerId, Who};

/// The timer `ping` arms.
pub const PING_TIMER_MS: u64 = 50;

/// The app.
pub struct Echo {
    ticks: u64,
    faults: bool,
}

fn internal(e: impl ToString) -> AppError {
    AppError::new(Status::InternalError, e.to_string())
}

fn good(host: &dyn Host, v: Value) -> Sample {
    Sample {
        v,
        q: Quality::Good,
        t: host.now_us(),
    }
}

/// A number kept in the store (0 when absent).
fn stored(host: &dyn Host, key: &str) -> Result<Option<Value>, AppError> {
    host.store_get(key)
        .map(|b| wyrm_core::codec::from_slice::<Value>(&b).map_err(internal))
        .transpose()
}

/// `faults` from the params; any other key is refused, naming it.
fn faults(config: &Value) -> Result<bool, AppError> {
    let m = match config {
        Value::Map(m) => m,
        Value::Null => return Ok(false),
        _ => return Err(AppError::new(Status::InvalidParameter, "params: a map")),
    };
    let mut on = false;
    for (k, v) in m {
        match (k.as_str(), v) {
            ("faults", Value::Bool(b)) => on = *b,
            ("faults", _) => {
                return Err(AppError::new(
                    Status::InvalidParameter,
                    "params.faults: true or false",
                ))
            }
            (k, _) => {
                return Err(AppError::new(
                    Status::InvalidParameter,
                    format!("params.{k}: unknown"),
                ))
            }
        }
    }
    Ok(on)
}

impl App for Echo {
    const NAME: &'static str = "portable-echo";
    const VERSION: &'static str = env!("CARGO_PKG_VERSION");

    fn start(host: &mut dyn Host, config: Value) -> Result<Self, AppError> {
        let faults = faults(&config)?;
        host.declare_node(
            "n",
            NodeMeta::number().writable(Writable::Write).display("N"),
        );
        host.declare_node("ticks", NodeMeta::number().display("Ticks"));
        host.declare_node("starts", NodeMeta::number().display("Starts"));
        host.declare_action(
            "",
            "ping",
            ActionMeta::new().level(Perm::Write).display("Ping"),
        );
        host.declare_action(
            "",
            "echo",
            ActionMeta::new()
                .level(Perm::Write)
                .display("Echo")
                .param("value", ParamMeta::of(TypeCode::Dynamic)),
        );
        if faults {
            host.declare_action(
                "",
                "crash",
                ActionMeta::new().level(Perm::Config).display("Crash"),
            );
        }
        if let Some(v) = stored(host, "n")? {
            let s = good(host, v);
            host.update("n", s);
        }
        let starts = stored(host, "starts")?
            .and_then(|v| v.as_f64())
            .unwrap_or(0.0)
            + 1.0;
        let v = Value::Float(starts);
        // a store without room (`store_mb = 0`) still starts
        let _ = host.store_put("starts", &wyrm_core::codec::to_vec(&v).map_err(internal)?);
        let s = good(host, v);
        host.update("starts", s);
        Ok(Echo { ticks: 0, faults })
    }

    fn on_set(
        &mut self,
        host: &mut dyn Host,
        path: &str,
        value: Value,
        _who: &Who,
    ) -> Result<(), AppError> {
        if path != "n" {
            return Err(AppError::new(Status::NotFound, path));
        }
        if value.as_f64().is_none() {
            return Err(AppError::new(Status::InvalidParameter, "n: a number"));
        }
        // durable before the reply leaves (the host applies the event's commands first)
        host.store_put("n", &wyrm_core::codec::to_vec(&value).map_err(internal)?)?;
        let s = good(host, value);
        host.update("n", s);
        Ok(())
    }

    fn on_invoke(
        &mut self,
        host: &mut dyn Host,
        path: &str,
        action: &str,
        args: Value,
        _who: &Who,
    ) -> Result<Value, AppError> {
        match (path, action) {
            ("", "ping") => {
                host.set_timer(PING_TIMER_MS)?;
                Ok(Value::Str("pong".into()))
            }
            ("", "echo") => Ok(match args {
                Value::Map(mut m) => m.remove("value").unwrap_or(Value::Null),
                _ => Value::Null,
            }),
            ("", "crash") if self.faults => panic!("asked to crash"),
            _ => Err(AppError::new(Status::NotSupported, action)),
        }
    }

    fn on_timer(&mut self, host: &mut dyn Host, _timer: TimerId) {
        self.ticks += 1;
        let s = good(host, Value::UInt(self.ticks));
        host.update("ticks", s);
    }
}

#[cfg(feature = "wasm")]
wyrm_link_guest::export!(Echo);
