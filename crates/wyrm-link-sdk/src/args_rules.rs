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
//! Neither does a name that comes a second time through `flatten`, at any
//! depth: the derive asserts it in a `const` (`wyrm_core::args::Names`).
//!
//! ```compile_fail
//! use wyrm_link_sdk::Args;
//!
//! #[derive(Args)]
//! struct Inner {
//!     name: Option<u32>,
//! }
//!
//! #[derive(Args)]
//! struct Twice {
//!     name: String,
//!     #[param(flatten)]
//!     inner: Inner,
//! }
//! ```
//!
//! ```compile_fail
//! use wyrm_link_sdk::Args;
//!
//! #[derive(Args)]
//! struct Inner {
//!     name: Option<u32>,
//! }
//!
//! #[derive(Args)]
//! struct Mid {
//!     #[param(flatten)]
//!     inner: Inner,
//! }
//!
//! #[derive(Debug, wyrm_link_sdk::Args)]
//! struct Twice {
//!     #[param(flatten)]
//!     a: Mid,
//!     #[param(flatten)]
//!     b: Inner,
//! }
//! ```
//!
//! `flatten` stands alone: an attribute beside it would be dropped.
//!
//! ```
//! use wyrm_link_sdk::Args;
//!
//! #[derive(Args)]
//! struct Inner {
//!     n: Option<u32>,
//! }
//!
//! #[derive(Args)]
//! struct Outer {
//!     name: String,
//!     #[param(flatten)]
//!     inner: Inner,
//! }
//! assert_eq!(Outer::params().len(), 2);
//! ```
//!
//! ```compile_fail
//! use wyrm_link_sdk::Args;
//!
//! #[derive(Args)]
//! struct Inner {
//!     n: Option<u32>,
//! }
//!
//! #[derive(Args)]
//! struct Outer {
//!     #[param(flatten, secret)]
//!     inner: Inner,
//! }
//! ```
//!
//! ```compile_fail
//! use wyrm_link_sdk::Args;
//!
//! #[derive(Args)]
//! struct Inner {
//!     n: Option<u32>,
//! }
//!
//! #[derive(Args)]
//! struct Outer {
//!     #[param(flatten, trim)]
//!     inner: Inner,
//! }
//! ```
//!
//! ```compile_fail
//! use wyrm_link_sdk::Args;
//!
//! #[derive(Args)]
//! struct Inner {
//!     n: Option<u32>,
//! }
//!
//! #[derive(Args)]
//! struct Outer {
//!     #[param(flatten, nonempty)]
//!     inner: Inner,
//! }
//! ```
//!
//! ```compile_fail
//! use wyrm_link_sdk::Args;
//!
//! #[derive(Args)]
//! struct Inner {
//!     n: Option<u32>,
//! }
//!
//! #[derive(Args)]
//! struct Outer {
//!     #[param(flatten, min = 1)]
//!     inner: Inner,
//! }
//! ```
//!
//! ```compile_fail
//! use wyrm_link_sdk::Args;
//!
//! #[derive(Args)]
//! struct Inner {
//!     n: Option<u32>,
//! }
//!
//! #[derive(Args)]
//! struct Outer {
//!     #[param(flatten, max = 1)]
//!     inner: Inner,
//! }
//! ```
//!
//! ```compile_fail
//! use wyrm_link_sdk::Args;
//!
//! #[derive(Args)]
//! struct Inner {
//!     n: Option<u32>,
//! }
//!
//! #[derive(Args)]
//! struct Outer {
//!     #[param(flatten, display = "Inner")]
//!     inner: Inner,
//! }
//! ```
//!
//! ```compile_fail
//! use wyrm_link_sdk::Args;
//!
//! #[derive(Args)]
//! struct Inner {
//!     n: Option<u32>,
//! }
//!
//! #[derive(Args)]
//! struct Outer {
//!     #[param(flatten, default = 1)]
//!     inner: Inner,
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
//! A secret is never trimmed, but for a token a person pastes as one line
//! (`SecretLine`):
//!
//! ```
//! use wyrm_link_sdk::{Args, SecretLine};
//!
//! #[derive(Args)]
//! struct Enrol {
//!     #[param(secret, trim, nonempty)]
//!     token: Option<SecretLine>,
//! }
//! assert_eq!(Enrol::params().len(), 1);
//! ```
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
