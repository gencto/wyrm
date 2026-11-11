//! Node and action meta of the uplink's tree (ADR 0035), paths relative to the link root:
//!
//! ```text
//! ""                 add_mqtt, add_sparkplug, add_thingsboard, add_azure, add_aws (config)
//! stats/…            upstreams, connected, published, dropped
//! <name>             attrs kind, origin (runtime | config), select
//!   status           connecting | connected | waiting | failed | disabled
//!   error, url, connected_since, published, dropped, queued, last_publish
//!   enabled          writable at config (a runtime upstream)
//!   edit, set_password, test_connection, remove (config)
//! ```

use wyrm_core::meta::{
    ActionResult, ParamMeta, Writable, EDITOR_PASSWORD, EDITOR_TEXTAREA, GROUP_EDIT, GROUP_NEW,
};
use wyrm_core::{ActionMeta, NodeMeta, Perm, TypeCode};

use crate::platform::{fields, Field, Kind, COMMON};

pub const STATS: &str = "stats";
pub const STAT_NAMES: [&str; 4] = ["upstreams", "connected", "published", "dropped"];
/// The leaves of one upstream, in order.
pub const LEAVES: [(&str, TypeCode, &str); 8] = [
    ("status", TypeCode::String, "connecting, connected, waiting (after an error), failed (see error; Edit, Set password or Enable start it again), disabled"),
    ("error", TypeCode::String, "The last error."),
    ("url", TypeCode::String, "Where it connects."),
    ("connected_since", TypeCode::String, "UTC time of the current connection; empty while there is none."),
    ("published", TypeCode::Number, "Values sent since the link started."),
    ("dropped", TypeCode::Number, "Values the queue let go (the platform was slower than the site)."),
    ("queued", TypeCode::Number, "Values waiting to be sent."),
    ("last_publish", TypeCode::String, "UTC time of the last send."),
];
/// Nodes one upstream takes: the folder, the leaves, `enabled`.
pub const NODES_PER_UPSTREAM: usize = 2 + LEAVES.len();

pub fn stat(n: &str) -> String {
    format!("{STATS}/{n}")
}

pub fn leaf(name: &str, l: &str) -> String {
    format!("{name}/{l}")
}

fn param(f: &Field, required: bool) -> ParamMeta {
    let mut p = ParamMeta::of(f.ty).display(f.display);
    if required {
        p = p.required(true);
    }
    if !f.about.is_empty() {
        p = p.description(f.about);
    }
    if !f.placeholder.is_empty() {
        p = p.placeholder(f.placeholder);
    }
    if f.name == "ca_pem" || f.name == "select" {
        p = p.editor(EDITOR_TEXTAREA);
    }
    p
}

/// An Add (with `name`) or Edit (without) form of a kind.
fn form(kind: Kind, add: bool) -> ActionMeta {
    let mut a = ActionMeta::new().level(Perm::Config);
    for f in COMMON.iter().chain(fields(kind)) {
        if f.name == "name" && !add {
            continue;
        }
        a = a.param(f.name, param(f, f.required && add));
    }
    a
}

/// `add_<kind>` of the link root.
pub fn add_action(kind: Kind) -> (String, ActionMeta) {
    (
        format!("add_{}", kind.name()),
        form(kind, true)
            .display(wyrm_core::display::sentence(&format!(
                "Add {} upstream",
                kind.display()
            )))
            .group(GROUP_NEW),
    )
}

/// The actions of one upstream; a config-file one has no Edit, Remove or `enabled` write.
pub fn upstream_actions(kind: Kind, from_config: bool) -> Vec<(&'static str, ActionMeta)> {
    let mut out = vec![
        (
            "set_password",
            ActionMeta::new()
                .display("Set password")
                .group(GROUP_EDIT)
                .level(Perm::Config)
                .param(
                    "password",
                    ParamMeta::of(TypeCode::String)
                        .display("Secret")
                        .editor(EDITOR_PASSWORD)
                        .description(kind.secret_about()),
                ),
        ),
        (
            "test_connection",
            ActionMeta::new()
                .display("Test connection")
                .level(Perm::Config)
                .result(ActionResult::Type(TypeCode::Map)),
        ),
    ];
    if !from_config {
        out.push(("edit", form(kind, false).display("Edit").group(GROUP_EDIT)));
        out.push((
            "remove",
            ActionMeta::new()
                .display("Remove")
                .group(GROUP_EDIT)
                .level(Perm::Config),
        ));
    }
    out
}

pub fn upstream_node(kind: Kind, from_config: bool, select: &[String]) -> NodeMeta {
    NodeMeta::folder()
        .display(format!(
            "{} ({})",
            kind.display(),
            if from_config { "config" } else { "runtime" }
        ))
        .attr("kind", kind.name())
        .attr("origin", if from_config { "config" } else { "runtime" })
        .attr(
            "select",
            wyrm_core::Value::Array(select.iter().cloned().map(wyrm_core::Value::Str).collect()),
        )
}

pub fn status_node() -> NodeMeta {
    NodeMeta::leaf(TypeCode::Enum)
        .enum_values(["connecting", "connected", "waiting", "failed", "disabled"])
        .attr("description", LEAVES[0].2)
}

pub fn enabled_node(from_config: bool) -> NodeMeta {
    let n = NodeMeta::leaf(TypeCode::Bool);
    if from_config {
        n.attr("description", "Set in wyrmd.json5")
    } else {
        n.writable(Writable::Config)
    }
}
