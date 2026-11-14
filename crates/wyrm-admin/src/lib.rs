//! WYRM control plane: link registry and tokens, internal CA, generated
//! ACL, process supervisor, quarantine, audit — the `wy/<site>/sys/**` tree.
#![forbid(unsafe_code)]

pub mod acl;
pub mod audit;
pub mod backup;
pub mod control;
pub mod fetch;
pub mod git;
pub mod history;
pub mod keys;
pub mod logs;
pub mod nofollow;
pub mod official;
pub mod packages;
pub mod peers;
pub mod registry;
pub mod release;
pub mod restore_point;
pub mod secret;
pub mod secrets;
pub mod supervisor;

pub use control::backups::{BackupConfig, LinkBackup, SendLink};
pub use control::broker_update::{UpdateConfig, UpdateMode};
pub use control::{
    Attached, ConfigLink, Control, ControlConfig, EmbeddedHost, PeerConfig, RunningLink,
    UpstreamConf,
};
pub use registry::Mode;
