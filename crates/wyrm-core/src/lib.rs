//! WYRM core: wire types and codec shared by broker, SDKs and bindings.
//!
//! Normative reference: `spec/` in the repository root. Every type here is
//! covered by `spec/fixtures` — see `tests/fixtures.rs`.

#![forbid(unsafe_code)]

pub mod attachment;
pub mod codec;
pub mod keyspace;
pub mod meta;
pub mod status;
pub mod value;

pub use attachment::Attachment;
pub use meta::{NodeMeta, Perm, Writable};
pub use status::Status;
pub use value::{Quality, Sample, Value};

/// Protocol major version published at `wy/<site>/sys/broker/~meta.proto`.
pub const PROTO_VERSION: u8 = 1;
