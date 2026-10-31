//! One runtime for portable links (ADR 0023).
//!
//! An [`App`](wyrm_link_api::App) from `wyrm-link-api` runs as a WYRM link through
//! [`Runtime`], which implements the SDK's `trait Link`. The runtime is the same for every engine:
//! [`NativeEngine`] runs Rust code compiled into the host ([`Portable<A>`]); `links/wasm` supplies
//! a WASM engine through [`MakeEngine`].
//!
//! - The engine runs on its own OS thread, one event at a time. The app's effects go into a
//!   command buffer and are applied after the event returns, in order; an event that faults
//!   applies nothing.
//! - Timers are monotonic; subscriptions deliver the current value first; a full queue
//!   coalesces values per subscription and answers `set`/`invoke` with `busy`.
//! - A fault drops the instance, marks its values `bad/comm_fail`, and starts it again after a
//!   backoff (1 s, ×2, cap 60 s, ±20 %). Nodes the new `start` does not declare within 10 s are
//!   removed. The link root carries `status` (`running | restarting | stuck`) and `error`.
//! - The store is the link's own: sealed files in its data directory (see [`store`]).

#![forbid(unsafe_code)]

pub mod engine;
pub mod native;
pub mod runtime;
pub mod services;
pub mod store;

pub use engine::{Engine, Event, Fault, MakeEngine};
pub use native::NativeEngine;
pub use runtime::Runtime;

use wyrm_core::Value;
use wyrm_link_api::net::NetPolicy;
use wyrm_link_sdk::params::FromParams;
use wyrm_link_sdk::LinkError;

/// An [`App`](wyrm_link_api::App) compiled into the host, run as a link.
pub type Portable<A> = Runtime<NativeEngine<A>>;

/// Store size when `store_mb` is not given (MiB).
pub const DEFAULT_STORE_MB: u32 = 1;
/// Largest `store_mb`.
pub const MAX_STORE_MB: u32 = 64;
/// Call time when `call_ms` is not given.
pub const DEFAULT_CALL_MS: u32 = 2000;
/// Largest `call_ms`.
pub const MAX_CALL_MS: u32 = 10_000;
/// Memory of a WASM instance when `memory_mb` is not given (MiB).
pub const DEFAULT_MEMORY_MB: u32 = 64;
/// Largest `memory_mb`.
pub const MAX_MEMORY_MB: u32 = 512;

/// The settings of a portable link, from its params. The keys `net`, `store_mb`, `call_ms`,
/// `memory_mb` and `component` belong to the host; everything else goes to the app's `start` as
/// `params`.
#[derive(Debug, Clone, PartialEq)]
pub struct PortableConfig {
    /// The app's params: a map.
    pub params: Value,
    /// TCP allowlist (ADR 0012 syntax). Empty: no network.
    pub net: NetPolicy,
    /// Store size in MiB; 0 refuses every write.
    pub store_mb: u32,
    /// Time of one call in milliseconds (TCP waits; WASM epoch limit).
    pub call_ms: u32,
    /// Linear memory of a WASM instance in MiB (the native engine has no such bound).
    pub memory_mb: u32,
    /// The `wasm` package whose component runs the app (driver `app`); unused by the native
    /// engine.
    pub component: Option<String>,
}

impl Default for PortableConfig {
    fn default() -> Self {
        Self {
            params: Value::Map(Default::default()),
            net: NetPolicy::default(),
            store_mb: DEFAULT_STORE_MB,
            call_ms: DEFAULT_CALL_MS,
            memory_mb: DEFAULT_MEMORY_MB,
            component: None,
        }
    }
}

fn bounded(
    m: &mut std::collections::BTreeMap<String, Value>,
    key: &str,
    default: u32,
    max: u32,
    min: u32,
) -> Result<u32, LinkError> {
    let Some(v) = m.remove(key) else {
        return Ok(default);
    };
    match v {
        Value::UInt(n) if n >= u64::from(min) && n <= u64::from(max) => Ok(n as u32),
        Value::Int(n) if n >= i64::from(min) && n <= i64::from(max) => Ok(n as u32),
        _ => Err(LinkError::invalid_parameter(format!(
            "params.{key}: a whole number from {min} to {max}"
        ))),
    }
}

impl FromParams for PortableConfig {
    fn from_params(params: &Value) -> Result<Self, LinkError> {
        let mut m = match params {
            Value::Map(m) => m.clone(),
            Value::Null => Default::default(),
            _ => return Err(LinkError::invalid_parameter("params: expected a map")),
        };
        let net = match m.remove("net") {
            None | Some(Value::Null) => NetPolicy::default(),
            Some(Value::Str(s)) => NetPolicy::parse(&s)
                .map_err(|e| LinkError::invalid_parameter(format!("params.net: {e}")))?,
            Some(_) => {
                return Err(LinkError::invalid_parameter(
                    "params.net: a string of <ip>[/<prefix>]:<port> entries",
                ))
            }
        };
        let store_mb = bounded(&mut m, "store_mb", DEFAULT_STORE_MB, MAX_STORE_MB, 0)?;
        let call_ms = bounded(&mut m, "call_ms", DEFAULT_CALL_MS, MAX_CALL_MS, 1)?;
        let memory_mb = bounded(&mut m, "memory_mb", DEFAULT_MEMORY_MB, MAX_MEMORY_MB, 1)?;
        let component = match m.remove("component") {
            None | Some(Value::Null) => None,
            Some(Value::Str(s)) if !s.is_empty() => Some(s),
            Some(_) => {
                return Err(LinkError::invalid_parameter(
                    "params.component: a package name",
                ))
            }
        };
        Ok(Self {
            params: Value::Map(m),
            net,
            store_mb,
            call_ms,
            memory_mb,
            component,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::BTreeMap;

    /// The package manifest checks `capabilities` against the same defaults and bounds
    /// (`wyrm-link-sdk` cannot depend on this crate).
    #[test]
    fn package_capabilities_use_these_limits() {
        use wyrm_link_sdk::package as p;
        assert_eq!(
            (DEFAULT_STORE_MB, MAX_STORE_MB),
            (p::DEFAULT_STORE_MB, p::MAX_STORE_MB)
        );
        assert_eq!(
            (DEFAULT_MEMORY_MB, MAX_MEMORY_MB),
            (p::DEFAULT_MEMORY_MB, p::MAX_MEMORY_MB)
        );
        assert_eq!(
            (DEFAULT_CALL_MS, MAX_CALL_MS),
            (p::DEFAULT_CALL_MS, p::MAX_CALL_MS)
        );
    }

    #[test]
    fn host_keys_are_taken_out_of_params() {
        let mut m = BTreeMap::new();
        m.insert("net".to_owned(), Value::Str("10.0.0.0/8:502".into()));
        m.insert("store_mb".to_owned(), Value::UInt(0));
        m.insert("call_ms".to_owned(), Value::UInt(500));
        m.insert("memory_mb".to_owned(), Value::UInt(128));
        m.insert("component".to_owned(), Value::Str("echo".into()));
        m.insert("rate".to_owned(), Value::UInt(5));
        let c = PortableConfig::from_params(&Value::Map(m)).unwrap();
        assert_eq!(c.store_mb, 0);
        assert_eq!(c.call_ms, 500);
        assert_eq!(c.memory_mb, 128);
        assert_eq!(c.component.as_deref(), Some("echo"));
        assert!(!c.net.is_empty());
        let Value::Map(p) = &c.params else { panic!() };
        assert_eq!(p.keys().collect::<Vec<_>>(), ["rate"]);

        let d = PortableConfig::from_params(&Value::Null).unwrap();
        assert_eq!(d, PortableConfig::default());
        for (k, v) in [
            ("store_mb", Value::UInt(65)),
            ("call_ms", Value::UInt(0)),
            ("call_ms", Value::UInt(10_001)),
            ("memory_mb", Value::UInt(0)),
            ("memory_mb", Value::UInt(513)),
            ("component", Value::Str(String::new())),
            ("component", Value::UInt(1)),
            ("net", Value::Str("example.com".into())),
            ("net", Value::UInt(1)),
        ] {
            let mut m = BTreeMap::new();
            m.insert(k.to_owned(), v);
            assert!(PortableConfig::from_params(&Value::Map(m)).is_err(), "{k}");
        }
    }
}
