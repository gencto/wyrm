//! WYRM core: wire types and codec shared by broker, SDKs and bindings.
//!
//! Normative reference: `spec/` in the repository root. Every type here is
//! covered by `spec/fixtures` — see `tests/fixtures.rs`.

#![forbid(unsafe_code)]

pub mod args;
pub mod attachment;
pub mod audit;
pub mod clock;
pub mod codec;
pub mod display;
pub mod files;
pub mod hex;
pub mod history;
pub mod keyspace;
pub mod mac;
pub mod meta;
pub mod named;
pub mod profile;
pub mod ptok;
#[cfg(feature = "rand")]
pub mod rand;
pub mod secret;
pub mod setup;
pub mod status;
pub mod time;
pub mod value;
pub mod weburl;
pub mod wire;

pub use attachment::Attachment;
pub use meta::{ActionMeta, NodeMeta, Perm, TypeCode, Writable};
pub use ptok::PtokClaims;
pub use status::{Status, StatusGroup};
pub use value::{HistRow, Quality, Sample, SetRequest, Value};

/// Protocol major version published as `attr.proto` of `wy/<site>/sys/~meta`.
pub const PROTO_VERSION: u8 = 1;
