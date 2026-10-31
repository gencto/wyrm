//! File store links (S3 buckets, Google Drive, WebDAV): one raw-layer link
//! ([`FileStore`]) over a [`Backend`] that each store's crate implements.
//!
//! A connection points at one bucket, drive folder or WebDAV collection.
//! The link reads the tree of folders and files below it, declares it as
//! nodes, keeps it fresh, and lets people create folders, upload,
//! download and delete files. See [`store`] for the tree and the actions.

#![forbid(unsafe_code)]

pub mod backend;
pub mod http;
pub mod parts;
pub mod persist;
#[cfg(feature = "sim")]
pub mod sim;
pub mod store;
#[cfg(feature = "testkit")]
pub mod testkit;
pub mod util;
pub mod xml;

pub use backend::{Backend, Entry, Error, Limits, Scan};
pub use store::{Bootstrap, Common, FileStore};
