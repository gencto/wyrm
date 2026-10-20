//! WYRM core: wire types and codec shared by broker, SDKs and bindings.
//!
//! Normative reference: `spec/` in the repository root. Every type here is
//! covered by `spec/fixtures` — see `tests/fixtures.rs`.

#![forbid(unsafe_code)]

pub mod attachment;
pub mod codec;
pub mod keyspace;
pub mod meta;
pub mod profile;
pub mod ptok;
pub mod status;
pub mod value;
pub mod wire;

pub use attachment::Attachment;
pub use meta::{ActionMeta, NodeMeta, Perm, TypeCode, Writable};
pub use ptok::PtokClaims;
pub use status::{Status, StatusGroup};
pub use value::{Quality, Sample, SetRequest, Value};

/// Protocol major version published at `wy/<site>/sys/broker/~meta.proto`.
pub const PROTO_VERSION: u8 = 1;
