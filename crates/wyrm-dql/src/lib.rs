//! WYRM DQL (ADR 0025): the query language of the DQL link, after DSA's `dslink-dart-dql`.
//!
//! ```text
//! list wy/plant/downstream/plc1/** | where type == "number" | subscribe value :name
//!     | expression f="value * 1.8 + 32.0" | set ./display_f = f
//! ```
//!
//! - [`parse`]: the pipeline into a [`Plan`] (full keys with Zenoh wildcards, CEL predicates and
//!   expressions; DSA `filter` syntax kept and turned into CEL by [`dsa`]).
//! - [`Engine`]: one running query as a pure state machine; the host (the link, `wyr query`)
//!   performs its [`Effect`]s and feeds back list changes, samples and replies.
//! - [`dsa::convert`]: a DSA DQL text for one site as a WYRM text.
//!
//! No I/O, no clock, no async; builds for `wasm32-unknown-unknown`.

pub mod cel;
pub mod dsa;
pub mod engine;
pub mod parse;
pub mod pattern;

pub use engine::{Effect, Engine, Handle, Limits, Progress, Status};
pub use parse::{parse, ParseError, Plan};

use std::collections::BTreeMap;
use wyrm_core::Value;

/// What `explain` answers: the plan of a text, or why it is refused.
pub fn explain(text: &str) -> Value {
    let mut m = BTreeMap::new();
    let strs = |v: Vec<String>| Value::Array(v.into_iter().map(Value::Str).collect());
    match parse(text) {
        Ok(p) => {
            let stages: Vec<String> = parse::split_top(&p.text, '|')
                .unwrap_or_default()
                .into_iter()
                .map(|s| s.trim().to_owned())
                .collect();
            m.insert("stages".into(), strs(stages));
            m.insert("columns".into(), strs(p.columns()));
            m.insert("roots".into(), strs(p.roots()));
            m.insert("sinks".into(), strs(p.sinks()));
            m.insert("full_meta".into(), Value::Bool(p.full_meta));
            m.insert("errors".into(), Value::Array(Vec::new()));
        }
        Err(e) => {
            m.insert("errors".into(), strs(vec![e.to_string()]));
        }
    }
    Value::Map(m)
}
