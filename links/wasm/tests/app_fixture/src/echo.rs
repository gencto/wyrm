//! The test app of `links/wasm/tests/app.rs`. The same source runs natively (`Portable<Echo>`,
//! included by the test through `#[path]`) and as a WASM component (this fixture crate), so the
//! two engines can be compared event by event. It uses nothing wasm32-unknown-unknown lacks
//! (no threads, no sleep, no clock but the host's).
//!
//! Nodes: `n` (writable, kept in the store), `ticks` (timer count), `reply` (last reply),
//! `seen` (last subscribed value), `starts` (how many times `start` ran, kept in the store),
//! `stopped` (how many times `stop` ran: `stop` counts in the store, `start` shows it).
//! Actions on the root: `ping` (a 50 ms timer, answers `"pong"`), `call` (a request to another
//! point), `slow` (runs 300 ms), and the faults `trap`, `spin` (never ends) and `grow` (asks for
//! 100 MiB). A `set` of -1 panics; a `set` of -2 stores 9 and then runs 300 ms. With
//! `extra: true` it declares `extra` on its first start only. With `gate: <port>` the slow
//! `set` and `slow` do not run a fixed time: each connects to `127.0.0.1:<port>` and returns
//! when one byte arrives there, so a test knows the call is in flight (it accepted) and decides
//! when it ends (it sends).

use wyrm_core::meta::{ParamMeta, Writable};
use wyrm_core::{ActionMeta, NodeMeta, Perm, Quality, Sample, Status, TypeCode, Value};
use wyrm_link_api::{App, AppError, Host, ReqId, SubId, TimerId, Who};

fn sample(v: Value) -> Sample {
    Sample {
        v,
        q: Quality::Good,
        t: 1,
    }
}

fn internal(e: impl ToString) -> AppError {
    AppError::new(Status::InternalError, e.to_string())
}

/// A counter kept in the store (0 when absent).
fn count(host: &dyn Host, key: &str) -> f64 {
    host.store_get(key)
        .and_then(|b| wyrm_core::codec::from_slice::<Value>(&b).ok())
        .and_then(|v| v.as_f64())
        .unwrap_or(0.0)
}

pub struct Echo {
    ticks: u64,
    gate: Option<u16>,
}

impl Echo {
    /// A slow call: 300 ms, or until the gate sends one byte (see the module docs).
    fn slow(&self, host: &mut dyn Host) -> Result<(), AppError> {
        if let Some(port) = self.gate {
            let c = host.tcp_connect("127.0.0.1", port, 1_000)?;
            let r = host.tcp_recv(c, 1, 9_000);
            host.tcp_close(c);
            return r.map(|_| ());
        }
        let end = host.now_us() + 300_000;
        while host.now_us() < end {
            std::hint::black_box(());
        }
        Ok(())
    }
}

impl App for Echo {
    const NAME: &'static str = "echo";
    const VERSION: &'static str = "0.1.0";

    fn start(host: &mut dyn Host, config: Value) -> Result<Self, AppError> {
        host.declare_node("n", NodeMeta::number().writable(Writable::Write));
        host.declare_node("ticks", NodeMeta::number());
        host.declare_node("reply", NodeMeta::leaf(TypeCode::String));
        host.declare_node("seen", NodeMeta::number());
        host.declare_node("starts", NodeMeta::number());
        host.declare_node("stopped", NodeMeta::number());
        for a in ["ping", "slow", "trap", "spin", "grow"] {
            host.declare_action("", a, ActionMeta::new().level(Perm::Write));
        }
        host.declare_action(
            "",
            "call",
            ActionMeta::new()
                .level(Perm::Write)
                .param("op", ParamMeta::of(TypeCode::String))
                .param("key", ParamMeta::of(TypeCode::String))
                .param("value", ParamMeta::of(TypeCode::Number)),
        );
        let extra = matches!(&config, Value::Map(m) if m.get("extra") == Some(&Value::Bool(true)));
        let gate = match &config {
            Value::Map(m) => match m.get("gate") {
                Some(Value::UInt(p)) => u16::try_from(*p).ok(),
                _ => None,
            },
            _ => None,
        };
        if extra && host.store_get("started").is_none() {
            host.declare_node("extra", NodeMeta::number());
            host.store_put("started", &[1])?;
        }
        if let Some(b) = host.store_get("n") {
            let v: Value = wyrm_core::codec::from_slice(&b).map_err(internal)?;
            host.update("n", sample(v));
        }
        let starts = count(host, "starts") + 1.0;
        // a store without room (store_mb = 0) still starts
        if let Ok(b) = wyrm_core::codec::to_vec(&Value::Float(starts)) {
            let _ = host.store_put("starts", &b);
        }
        host.update("starts", sample(Value::Float(starts)));
        host.update("stopped", sample(Value::Float(count(host, "stopped"))));
        Ok(Echo { ticks: 0, gate })
    }

    fn on_set(
        &mut self,
        host: &mut dyn Host,
        path: &str,
        value: Value,
        _who: &Who,
    ) -> Result<(), AppError> {
        if value.as_f64() == Some(-1.0) {
            panic!("asked to fail");
        }
        if path != "n" {
            return Err(AppError::new(Status::NotFound, path));
        }
        if value.as_f64() == Some(-2.0) {
            // a slow set: writes 9, then runs on (the hot swap test cuts it off)
            let nine = Value::UInt(9);
            host.store_put("n", &wyrm_core::codec::to_vec(&nine).map_err(internal)?)?;
            host.update("n", sample(nine));
            return self.slow(host);
        }
        let b = wyrm_core::codec::to_vec(&value).map_err(internal)?;
        host.store_put("n", &b)?;
        host.update("n", sample(value));
        Ok(())
    }

    fn on_invoke(
        &mut self,
        host: &mut dyn Host,
        _path: &str,
        action: &str,
        args: Value,
        _who: &Who,
    ) -> Result<Value, AppError> {
        match action {
            "ping" => {
                host.set_timer(50)?;
                Ok(Value::Str("pong".into()))
            }
            "slow" => {
                self.slow(host)?;
                Ok(Value::Str("slow".into()))
            }
            "trap" => panic!("asked to trap"),
            "spin" => {
                let mut i = 0u64;
                loop {
                    i = std::hint::black_box(i.wrapping_add(1));
                }
            }
            "grow" => {
                let v = std::hint::black_box(vec![1u8; 100 << 20]);
                Ok(Value::UInt(v.iter().map(|b| u64::from(*b)).sum()))
            }
            "call" => {
                let m = match &args {
                    Value::Map(m) => m,
                    _ => return Err(AppError::new(Status::InvalidParameter, "args")),
                };
                let key = match m.get("key") {
                    Some(Value::Str(k)) => k.clone(),
                    _ => return Err(AppError::new(Status::InvalidParameter, "key")),
                };
                match m.get("op") {
                    Some(Value::Str(op)) if op == "set" => {
                        let v = m.get("value").cloned().unwrap_or(Value::Null);
                        host.set(&key, v)?;
                    }
                    Some(Value::Str(op)) if op == "subscribe" => {
                        host.subscribe(&key)?;
                    }
                    _ => return Err(AppError::new(Status::InvalidParameter, "op")),
                }
                Ok(Value::Null)
            }
            _ => Err(AppError::new(Status::NotSupported, action)),
        }
    }

    fn stop(&mut self, host: &mut dyn Host) {
        let stopped = count(host, "stopped") + 1.0;
        if let Ok(b) = wyrm_core::codec::to_vec(&Value::Float(stopped)) {
            let _ = host.store_put("stopped", &b);
        }
    }

    fn on_timer(&mut self, host: &mut dyn Host, _timer: TimerId) {
        self.ticks += 1;
        host.update("ticks", sample(Value::UInt(self.ticks)));
    }

    fn on_value(&mut self, host: &mut dyn Host, _sub: SubId, _key: &str, s: Sample) {
        host.update("seen", sample(s.v));
    }

    fn on_reply(&mut self, host: &mut dyn Host, _req: ReqId, result: Result<Value, AppError>) {
        let text = match result {
            Ok(_) => "ok".to_owned(),
            Err(e) => e.status.name().to_owned(),
        };
        host.update("reply", sample(Value::Str(text)));
    }
}
