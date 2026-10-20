//! WYRM connector SDK.
//!
//! A driver implements [`Link`]; the SDK owns everything else for its subtree
//! `wy/<site>/down/<link>/**`: the [`NodeTree`](tree::NodeTree), one queryable
//! routed by suffix (`~meta` / `~set` / `~act/<a>`), `ptok` checks before any
//! driver call, value validation, liveliness, and `~meta`/`~val` publication
//! with the QoS from spec 05.
//!
//! QoS of `~set`/`~act` replies follows the query (Zenoh ≥ 1.10), so the
//! requester (`wyrm-client`) sets `InteractiveHigh + Block`.

#![forbid(unsafe_code)]

pub mod auth;
pub mod ctx;
pub mod driver;
pub mod error;
#[cfg(feature = "harness")]
pub mod harness;
pub mod link;
pub mod params;
#[cfg(feature = "process")]
pub mod process;
pub mod runtime;
pub mod support;
pub mod tree;

pub use auth::Caller;
pub use ctx::{now_us, LinkCtx, PointPublisher};
/// Admin `ptok` public key type (Ed25519).
pub use ed25519_dalek::VerifyingKey;
pub use error::{LinkError, Result};
#[cfg(feature = "harness")]
pub use harness::TestHarness;
pub use link::{Link, ReplySink};
pub use params::{Fields, FromParams};
pub use runtime::{spawn, LinkConfig, LinkHandle};
pub use support::{Metrics, Secret, SecretStore};
/// `#[derive(Params)]` / `#[derive(ParamEnum)]` for driver parameters (ADR 0004).
pub use wyrm_link_sdk_derive::{ParamEnum, Params};
