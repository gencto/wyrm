//! WYRM data-flow engine (wiki "04 Дата-флоу", spec 06): flows are data
//! under `wy/<site>/dataflows/<id>/~def`; the engine compiles, runs and hot-swaps
//! them, persists definitions and node state, and exposes every flow as a
//! node with `start/stop/reload/remove`.

#![forbid(unsafe_code)]

pub mod artifacts;
pub mod blocks;
pub mod catalog;
mod commands;
pub mod def;
pub mod engine;
pub mod nodes;
pub mod preview;
pub mod runtime;
pub mod scope;
pub mod script;
mod sources;
pub mod store;
pub mod watch;

pub use engine::{command_targets, Engine, EngineStart, FlowHost};
