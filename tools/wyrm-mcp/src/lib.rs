//! `wyrm-mcp`: an MCP server over `wyrm-client` (ADR 0005).
//!
//! Tools: `tree_list`, `tree_resolve`, `node_meta`, `value_get`, `node_set`,
//! `action_invoke`, `profiles`, `flow_get`, `flow_validate`, `flow_apply`,
//! `link_status`, `spec`. Resources: `wy://spec/<file>`.
//!
//! The server signs its requests as `ai:<agent>` with `max = write`.
//! Config-level operations go out only with a human operator's `ptok` for
//! exactly that request key (see [`server`]).
//!
//! With feature `gateway`, [`gateway::GatewayMcp`] serves the same kind of tools through a
//! user gateway as one of its users (ADR 0041): the connector of Claude Desktop.

#![forbid(unsafe_code)]

pub mod check;
#[cfg(feature = "gateway")]
pub mod gateway;
#[cfg(feature = "gateway")]
pub mod gw;
pub mod json;
pub mod server;
pub mod spec;

pub use server::{Options, WyrmMcp};
