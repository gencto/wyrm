//! WYRM data-flow engine (wiki "04 Дата-флоу", spec 06): flows are data
//! under `wy/<site>/flows/<id>/~def`; the engine compiles, runs and hot-swaps
//! them, persists definitions and node state, and exposes every flow as a
//! node with `start/stop/reload/remove`.

#![forbid(unsafe_code)]

pub mod def;
pub mod engine;
pub mod nodes;
pub mod runtime;
pub mod script;
pub mod store;

pub use engine::{Engine, EngineStart, FlowHost};
