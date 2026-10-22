//! WYRM embedded historian (ADR 0014): watch groups record point values into
//! a day-partitioned redb store; queries return raw rows or rollups.

pub mod engine;
pub mod query;
pub mod rollup;
pub mod store;
pub mod time;

pub use engine::{Counters, GroupCfg, Historian, Logging, WatchCfg};
pub use query::{parse_selector, HistoryQuery, QueryError};
pub use rollup::{Folder, Rollup};
pub use store::{encode_row, Row, Store};
