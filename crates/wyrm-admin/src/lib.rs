//! WYRM control plane: link registry and tokens, internal CA, generated
//! ACL, process supervisor, quarantine, audit — the `wy/<site>/sys/**` tree.
#![forbid(unsafe_code)]

pub mod acl;
pub mod audit;
pub mod control;
pub mod registry;
pub mod secret;
pub mod secrets;
pub mod supervisor;

pub use control::{
    Attached, ConfigLink, Control, ControlConfig, EmbeddedHost, PeerConfig, RunningLink,
};
pub use registry::Mode;
