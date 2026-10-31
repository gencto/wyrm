//! Node and action meta of the DQL link's tree (ADR 0025), paths relative to the link root:
//!
//! ```text
//! ""              add_query, run (write; sinks need config), import (config), explain,
//!                 convert_dsa (read)
//! stats/…         queries, rows, lists, subscriptions, sink_calls (DSA's counters)
//! <q>             attrs display, text, status, error, rows, columns, errors, sink_calls,
//!                 created_by, expires, lists, lists_pending, depth, sites, collect_ms,
//!                 last_publish; get_table, export (read); edit, remove (write)
//! <q>/table       the table: an array of row maps (read-only)
//! <q>/enabled     writable bool; saved
//! ```

use std::collections::BTreeMap;

use wyrm_core::meta::{ActionResult, ParamMeta, Writable, EDITOR_TEXTAREA, GROUP_EDIT, GROUP_NEW};
use wyrm_core::{ActionMeta, NodeMeta, Perm, TypeCode, Value};

pub const STATS: &str = "stats";
/// The counters under `stats/`.
pub const STAT_NAMES: [&str; 5] = ["queries", "rows", "lists", "subscriptions", "sink_calls"];
/// Nodes one query takes: the folder, `table`, `enabled`.
pub const NODES_PER_QUERY: usize = 3;

pub fn table(q: &str) -> String {
    format!("{q}/table")
}

pub fn enabled(q: &str) -> String {
    format!("{q}/enabled")
}

pub fn stat(n: &str) -> String {
    format!("{STATS}/{n}")
}

fn text(display: &str) -> ParamMeta {
    ParamMeta::of(TypeCode::String).display(display)
}

const TEXT_ABOUT: &str = "list <pattern> | where <CEL> | subscribe … | expression … | \
     invoke … | set … (docs/dql.md). Keys are full: wy/<site>/downstream/…; * is one segment, \
     ** any.";
const PUBLISH_ABOUT: &str = "The table is published at most this often, ms (500; 100 to 60000).";
const PUBLISH_TABLE_ABOUT: &str = "Publish the whole table as the value <query>/table, live, for \
     whoever may read that node (needs config). Off: Get Table answers each caller with the rows \
     it may read itself.";

fn query_params(a: ActionMeta, required: bool) -> ActionMeta {
    a.param("display", text("Display"))
        .param(
            "text",
            text("Query")
                .required(required)
                .editor(EDITOR_TEXTAREA)
                .placeholder(
                    "list wy/site/downstream/plc/** | where type == \"number\" | subscribe",
                )
                .description(TEXT_ABOUT),
        )
        .param(
            "publish_ms",
            ParamMeta::of(TypeCode::Number)
                .display("Publish Interval")
                .description(PUBLISH_ABOUT),
        )
        .param(
            "publish",
            ParamMeta::of(TypeCode::Bool)
                .display("Publish Table")
                .description(PUBLISH_TABLE_ABOUT),
        )
}

/// The actions of the link root.
pub fn root_actions() -> [(&'static str, ActionMeta); 5] {
    [
        (
            "add_query",
            query_params(
                ActionMeta::new()
                    .level(Perm::Write)
                    .display("Add Query")
                    .group(GROUP_NEW)
                    .result(ActionResult::Type(TypeCode::Map))
                    .param("id", text("Id").required(true).placeholder("temps")),
                true,
            )
            .param("enabled", ParamMeta::of(TypeCode::Bool).display("Enabled")),
        ),
        (
            "run",
            ActionMeta::new()
                .level(Perm::Write)
                .display("Run Query")
                .result(ActionResult::Type(TypeCode::Map))
                .param(
                    "text",
                    text("Query")
                        .required(true)
                        .editor(EDITOR_TEXTAREA)
                        .description(TEXT_ABOUT),
                )
                .param(
                    "id",
                    text("Id")
                        .description("Name the ad-hoc query (a dataflow subscribes <id>/table)."),
                )
                .param(
                    "ttl_s",
                    ParamMeta::of(TypeCode::Number)
                        .display("Time To Live")
                        .description(
                            "Seconds the ad-hoc query lives unless read again (300; at most 3600).",
                        ),
                ),
        ),
        (
            "explain",
            ActionMeta::new()
                .level(Perm::Read)
                .display("Explain Query")
                .result(ActionResult::Type(TypeCode::Map))
                .param("text", text("Query").required(true).editor(EDITOR_TEXTAREA)),
        ),
        (
            "import",
            // a definition may carry sinks
            ActionMeta::new()
                .level(Perm::Config)
                .display("Import Query")
                .group(GROUP_NEW)
                .result(ActionResult::Type(TypeCode::Map))
                .param(
                    "json",
                    text("JSON")
                        .required(true)
                        .editor(EDITOR_TEXTAREA)
                        .description("This link's export (wyrm-dql/1)."),
                )
                .param(
                    "id",
                    text("Id").description("Default: the id in the export."),
                )
                .param(
                    "overwrite",
                    ParamMeta::of(TypeCode::Bool)
                        .display("Overwrite")
                        .description("Replace a query with the same id."),
                ),
        ),
        (
            "convert_dsa",
            ActionMeta::new()
                .level(Perm::Read)
                .display("Convert DSA Query")
                .result(ActionResult::Type(TypeCode::Map))
                .param(
                    "text",
                    text("DSA Query").required(true).editor(EDITOR_TEXTAREA),
                )
                .param(
                    "site",
                    text("Site")
                        .required(true)
                        .description("The site its /downstream, /upstream, /sys paths belong to."),
                ),
        ),
    ]
}

fn query_actions() -> BTreeMap<String, ActionMeta> {
    let mut a = BTreeMap::new();
    a.insert(
        "get_table".into(),
        ActionMeta::new()
            .level(Perm::Read)
            .display("Get Table")
            .result(ActionResult::Type(TypeCode::Map))
            .param("from", ParamMeta::of(TypeCode::Number).display("From"))
            .param(
                "limit",
                ParamMeta::of(TypeCode::Number)
                    .display("Limit")
                    .description("Rows at most (1000; at most 5000)."),
            ),
    );
    a.insert(
        "export".into(),
        ActionMeta::new()
            .level(Perm::Read)
            .display("Export")
            .result(ActionResult::Type(TypeCode::Map)),
    );
    a.insert(
        "edit".into(),
        query_params(
            ActionMeta::new()
                .level(Perm::Write)
                .display("Edit")
                .group(GROUP_EDIT),
            false,
        ),
    );
    a.insert(
        "remove".into(),
        ActionMeta::new()
            .level(Perm::Write)
            .display("Remove")
            .group(GROUP_EDIT),
    );
    a
}

/// The query node: its attributes, with its actions.
pub fn query_meta(attrs: BTreeMap<String, Value>, display: &str) -> NodeMeta {
    let mut m = NodeMeta::folder().display(display.to_owned());
    m.attr = Some(attrs);
    m.actions = Some(query_actions());
    m
}

pub fn table_meta() -> NodeMeta {
    NodeMeta::leaf(TypeCode::Array).display("Table").attr(
        "description",
        "The rows: one map of columns each, in key order.",
    )
}

pub fn enabled_meta() -> NodeMeta {
    NodeMeta::leaf(TypeCode::Bool)
        .writable(Writable::Write)
        .display("Enabled")
        .attr(
            "description",
            "Off: the query lists, subscribes and writes nothing.",
        )
}

pub fn stats_meta() -> NodeMeta {
    NodeMeta::folder().display("Statistics")
}

pub fn stat_meta(n: &str) -> NodeMeta {
    let d = match n {
        "queries" => "Queries",
        "rows" => "Rows",
        "lists" => "Lists",
        "subscriptions" => "Subscriptions",
        _ => "Sink Calls",
    };
    NodeMeta::leaf(TypeCode::Number).display(d)
}
