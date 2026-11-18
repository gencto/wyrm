//! What `#[derive(Args)]` refuses at compile time (audit of #136). Each block
//! below is a doc test: the first compiles, the others must not.
//!
//! A struct of an action's arguments:
//!
//! ```
//! use wyrm_link_sdk::{Args, Secret};
//!
//! #[derive(Args)]
//! struct Seal {
//!     name: String,
//!     #[param(secret, nonempty)]
//!     passphrase: Option<Secret>,
//! }
//! assert_eq!(Seal::params().len(), 2);
//! ```
//!
//! A name is one field: two fields with one parameter name do not compile
//! (`decode` would read the key twice, with two types, and `~meta` would
//! declare the last one).
//!
//! ```compile_fail
//! use wyrm_link_sdk::Args;
//!
//! #[derive(Args)]
//! struct Twice {
//!     name: String,
//!     #[param(name = "name")]
//!     other: Option<u32>,
//! }
//! ```
//!
//! A secret is kept in a secret type: `secret` on a `String` does not compile
//! (a derived `Debug` would print it, and nothing would clear it).
//!
//! ```compile_fail
//! use wyrm_link_sdk::Args;
//!
//! #[derive(Args)]
//! struct Seal {
//!     #[param(secret)]
//!     passphrase: Option<String>,
//! }
//! ```
//!
//! ```compile_fail
//! use wyrm_link_sdk::Args;
//!
//! #[derive(Args)]
//! struct Key {
//!     #[param(secret)]
//!     value: Vec<u8>,
//! }
//! ```
//!
//! A secret is never trimmed.
//!
//! ```compile_fail
//! use wyrm_link_sdk::{Args, Secret};
//!
//! #[derive(Args)]
//! struct Seal {
//!     #[param(secret, trim)]
//!     passphrase: Option<Secret>,
//! }
//! ```
