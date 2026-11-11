//! Node and action meta of the alarm link's tree (ADR 0034 "Tree and actions"), paths relative
//! to the link root:
//!
//! ```text
//! ""                 add_class, raise, acknowledge, normal, add_note, ack_all (write);
//!                    get_alarm, get_notes, get_alarms (read); import, purge, add_sink (config)
//! stats/<n>          counters
//! sinks/<s>          value confirmed_seq; attrs link, classes, lag_entries, rows_sent,
//!                    dropped_unsent, last_request; next (read), edit, reset, remove (config)
//! <c>                folder; attrs display, escalation1_s, escalation2_s, created_by;
//!                    add_watch (config), edit, remove, ack_all (write), export (read)
//! <c>/open|active|unacked   counts
//! <c>/alarms         the open records (a table value)
//! <c>/watches/<w>    the state; attrs source, algorithm, type, message, params, keys,
//!                    in_alarm, last_change, last_record, error, created_by;
//!                    edit, enable, disable, remove (config)
//! ```

use std::collections::BTreeMap;

use wyrm_core::meta::{
    ActionResult, ParamMeta, EDITOR_DATERANGE, EDITOR_TEXTAREA, GROUP_EDIT, GROUP_NEW,
};
use wyrm_core::{ActionMeta, NodeMeta, Perm, TypeCode, Value};

use crate::algo::Algorithm;
use crate::limits::{NODES_PER_CLASS, STAT_NAMES};
use crate::model::{rfc3339, AlarmType, ClassDef, WatchDef};
use crate::sinks::Sink;
use crate::Micros;

pub const STATS: &str = "stats";
pub const SINKS: &str = "sinks";

pub fn stat(n: &str) -> String {
    format!("{STATS}/{n}")
}
pub fn sink(s: &str) -> String {
    format!("{SINKS}/{s}")
}
pub fn open(c: &str) -> String {
    format!("{c}/open")
}
pub fn active(c: &str) -> String {
    format!("{c}/active")
}
pub fn unacked(c: &str) -> String {
    format!("{c}/unacked")
}
pub fn alarms(c: &str) -> String {
    format!("{c}/alarms")
}
pub fn watches(c: &str) -> String {
    format!("{c}/watches")
}
pub fn watch(c: &str, w: &str) -> String {
    format!("{c}/watches/{w}")
}

/// Nodes a class with `watches` watches takes.
pub fn nodes_of(watches: usize) -> usize {
    NODES_PER_CLASS + watches
}

/// Commands that declare a class: its nodes and the four values; its watches follow in
/// batches ([`WATCH_COST`] each: the node, its value, a subscription).
pub fn declare_cost() -> usize {
    NODES_PER_CLASS + 4
}

pub const WATCH_COST: usize = 3;

fn param(ty: TypeCode, display: &str) -> ParamMeta {
    ParamMeta::of(ty).display(display)
}

fn text_param(display: &str) -> ParamMeta {
    param(TypeCode::String, display)
}

/// A record's id: dynamic, so a scenario or a CLI may pass its decimal text too.
fn id_param() -> ParamMeta {
    param(TypeCode::Dynamic, "Record")
        .required(true)
        .description("The record's id (a number).")
}

const SOURCE_ABOUT: &str = "A point key wy/<site>/downstream/<link>/<path>, or a prefix with \
     /** for every value under it.";
const TYPE_ABOUT: &str = "alert, warning or fault.";
const MESSAGE_ABOUT: &str = "Template of the record's message: {name}, {source}, {value}, \
     {quality}, {class}, {watch}, {stale_s}.";
const ALGORITHM_ABOUT: &str = "boolean: the value equals alarm_value; out_of_range: below min \
     or above max (back inside by deadband); staleness: no sample for stale_s; quality: the \
     sample is bad (include_uncertain: or uncertain).";
const ESCALATION_ABOUT: &str = "Seconds an open record stays unacknowledged before this \
     escalation level; 0: off.";

/// The fields of `add_watch` and a watch's `edit`; `required` marks `source` and `algorithm`.
fn watch_params(a: ActionMeta, required: bool) -> ActionMeta {
    a.param(
        "source",
        text_param("Source")
            .required(required)
            .placeholder("wy/site/downstream/plc/temp")
            .description(SOURCE_ABOUT),
    )
    .param(
        "algorithm",
        param(TypeCode::Enum, "Algorithm")
            .required(required)
            .enum_values(Algorithm::NAMES)
            .description(ALGORITHM_ABOUT),
    )
    .param(
        "alarm_value",
        param(TypeCode::Bool, "Alarm value").description("boolean: the value in alarm (true)."),
    )
    .param(
        "min",
        param(TypeCode::Number, "Min").description("out_of_range: below it is an alarm."),
    )
    .param(
        "max",
        param(TypeCode::Number, "Max").description("out_of_range: above it is an alarm."),
    )
    .param(
        "deadband",
        param(TypeCode::Number, "Deadband")
            .description("out_of_range: back to normal only this far inside the limit (0)."),
    )
    .param(
        "stale_s",
        param(TypeCode::Number, "Stale after").description("staleness: seconds without a sample."),
    )
    .param(
        "include_uncertain",
        param(TypeCode::Bool, "Include uncertain")
            .description("quality: an uncertain sample is an alarm too (false)."),
    )
    .param(
        "type",
        param(TypeCode::Enum, "Type")
            .enum_values(AlarmType::ALL.map(AlarmType::as_str))
            .description(TYPE_ABOUT),
    )
    .param("message", text_param("Message").description(MESSAGE_ABOUT))
    .param(
        "to_alarm_s",
        param(TypeCode::Number, "To alarm")
            .description("Seconds the condition must hold before a record is made (0)."),
    )
    .param(
        "to_normal_s",
        param(TypeCode::Number, "To normal")
            .description("Seconds the condition must be gone before the record is normal (0)."),
    )
    .param("enabled", param(TypeCode::Bool, "Enabled"))
}

fn class_params(a: ActionMeta) -> ActionMeta {
    a.param("display", text_param("Display"))
        .param(
            "escalation1_s",
            param(TypeCode::Number, "Escalation 1").description(ESCALATION_ABOUT),
        )
        .param(
            "escalation2_s",
            param(TypeCode::Number, "Escalation 2").description(ESCALATION_ABOUT),
        )
}

/// The actions of the link root.
pub fn root_actions() -> Vec<(&'static str, ActionMeta)> {
    let write = |d: &str| ActionMeta::new().level(Perm::Write).display(d);
    let read = |d: &str| ActionMeta::new().level(Perm::Read).display(d);
    let config = |d: &str| ActionMeta::new().level(Perm::Config).display(d);
    vec![
        (
            "add_class",
            class_params(
                write("Add class")
                    .group(GROUP_NEW)
                    .result(ActionResult::Type(TypeCode::Map))
                    .param("id", text_param("ID").required(true).placeholder("line1")),
            ),
        ),
        (
            "raise",
            write("Raise alarm")
                .result(ActionResult::Type(TypeCode::Map))
                .param("class", text_param("Class").required(true))
                .param(
                    "source",
                    text_param("Source")
                        .required(true)
                        .description("The point the alarm is about (a key of this site)."),
                )
                .param(
                    "type",
                    param(TypeCode::Enum, "Type")
                        .enum_values(AlarmType::ALL.map(AlarmType::as_str))
                        .description(TYPE_ABOUT),
                )
                .param("message", text_param("Message")),
        ),
        (
            "acknowledge",
            write("Acknowledge")
                .param("id", id_param())
                .param("note", text_param("Note")),
        ),
        (
            "normal",
            write("Return to normal").param(
                "id",
                id_param().description("A record made with Raise Alarm."),
            ),
        ),
        (
            "add_note",
            write("Add note").param("id", id_param()).param(
                "note",
                text_param("Note").required(true).editor(EDITOR_TEXTAREA),
            ),
        ),
        (
            "ack_all",
            write("Acknowledge all").param(
                "class",
                text_param("Class").description("Only this class; empty: every class."),
            ),
        ),
        (
            "get_alarm",
            read("Get alarm")
                .result(ActionResult::Type(TypeCode::Map))
                .param("id", id_param()),
        ),
        (
            "get_notes",
            read("Get notes")
                .result(ActionResult::Type(TypeCode::Array))
                .param("id", id_param()),
        ),
        (
            "get_alarms",
            read("Get alarms")
                .result(ActionResult::Type(TypeCode::Map))
                .param(
                    "timerange",
                    text_param("Timerange")
                        .placeholder("2026-11-01T00:00:00Z/2026-11-08T00:00:00Z")
                        .editor(EDITOR_DATERANGE)
                        .description(
                            "From/to in RFC 3339 on the creation time (a date is its midnight \
                             UTC); empty: any time.",
                        ),
                )
                .param("class", text_param("Class"))
                .param(
                    "source",
                    text_param("Source").description("A key, or a prefix ending with /."),
                )
                .param(
                    "state",
                    param(TypeCode::Enum, "State")
                        .enum_values(crate::STATES)
                        .description("open: active or unacknowledged (default)."),
                )
                .param(
                    "type",
                    param(TypeCode::Enum, "Type")
                        .enum_values(AlarmType::ALL.map(AlarmType::as_str)),
                )
                .param(
                    "limit",
                    param(TypeCode::Number, "Limit")
                        .description("Rows at most (500, at most 5000)."),
                ),
        ),
        (
            "import",
            config("Import class")
                .group(GROUP_NEW)
                .result(ActionResult::Type(TypeCode::Map))
                .param(
                    "json",
                    text_param("JSON")
                        .required(true)
                        .editor(EDITOR_TEXTAREA)
                        .description("A class's export."),
                )
                .param(
                    "overwrite",
                    param(TypeCode::Bool, "Overwrite")
                        .description("Replace a class with the same id."),
                ),
        ),
        (
            "purge",
            config("Purge").param(
                "before",
                text_param("Before")
                    .required(true)
                    .description("Closed records created before this instant (RFC 3339) go."),
            ),
        ),
        (
            "add_sink",
            config("Add sink")
                .group(GROUP_NEW)
                .param(
                    "name",
                    text_param("Name").required(true).placeholder("cloud"),
                )
                .param(
                    "link",
                    text_param("Link").required(true).description(
                        "The installed link that reads the batches (a history sync link).",
                    ),
                )
                .param(
                    "classes",
                    text_param("Classes")
                        .description("Class ids it takes, comma separated; empty: all."),
                )
                .param(
                    "from",
                    param(TypeCode::Enum, "From")
                        .enum_values(crate::FROMS)
                        .description(
                            "start: the oldest journal entry kept; now: new changes only.",
                        ),
                ),
        ),
    ]
}

pub fn stats_meta() -> NodeMeta {
    NodeMeta::folder().display("Statistics")
}

pub fn stat_meta(n: &str) -> NodeMeta {
    let (d, about) = match n {
        "open" => ("Open", "Records active or unacknowledged."),
        "active" => ("Active", "Records not yet normal."),
        "unacked" => ("Unacknowledged", "Records nobody acknowledged."),
        "records" => ("Records", "Records kept on disk."),
        "watches" => ("Watches", "Watches of every class."),
        "raised" => ("Raised", "Records made since the link started."),
        _ => (
            "Dropped",
            "Records the store refused since the link started.",
        ),
    };
    NodeMeta::leaf(TypeCode::Number)
        .display(d)
        .attr("description", about)
}

pub fn stat_names() -> [&'static str; STAT_NAMES.len()] {
    STAT_NAMES
}

pub fn sinks_meta() -> NodeMeta {
    NodeMeta::folder().display("Sinks")
}

fn sink_actions() -> BTreeMap<String, ActionMeta> {
    let config = |d: &str| {
        ActionMeta::new()
            .level(Perm::Config)
            .display(d)
            .group(GROUP_EDIT)
    };
    BTreeMap::from([
        (
            "next".to_owned(),
            ActionMeta::new()
                .level(Perm::Read)
                .display("Next batch")
                .result(ActionResult::Type(TypeCode::Map))
                .param(
                    "after",
                    param(TypeCode::Number, "After")
                        .description("Confirms every entry up to it; default: the confirmed one."),
                )
                .param(
                    "max",
                    param(TypeCode::Number, "Max")
                        .description("Rows at most (1000, at most 5000)."),
                ),
        ),
        (
            "edit".to_owned(),
            config("Edit")
                .param("link", text_param("Link"))
                .param("classes", text_param("Classes")),
        ),
        (
            "reset".to_owned(),
            config("Reset cursor").param(
                "from",
                param(TypeCode::Enum, "From")
                    .required(true)
                    .enum_values(crate::FROMS),
            ),
        ),
        ("remove".to_owned(), config("Remove")),
    ])
}

pub fn sink_meta(s: &Sink, lag: u64) -> NodeMeta {
    let mut m = NodeMeta::leaf(TypeCode::Number)
        .display(s.def.name.clone())
        .attr("link", s.def.link.clone())
        .attr("classes", s.def.classes.join(","))
        .attr("lag_entries", Value::UInt(lag))
        .attr("rows_sent", Value::UInt(s.rows_sent))
        .attr("dropped_unsent", Value::UInt(s.dropped_unsent))
        .attr("last_request", s.last_request.map_or(Value::Null, rfc3339));
    m.actions = Some(sink_actions());
    m
}

fn class_actions() -> BTreeMap<String, ActionMeta> {
    let mut a = BTreeMap::new();
    a.insert(
        "add_watch".into(),
        watch_params(
            ActionMeta::new()
                .level(Perm::Config)
                .display("Add watch")
                .group(GROUP_NEW)
                .result(ActionResult::Type(TypeCode::Map)),
            true,
        ),
    );
    a.insert(
        "edit".into(),
        class_params(
            ActionMeta::new()
                .level(Perm::Write)
                .display("Edit")
                .group(GROUP_EDIT),
        ),
    );
    a.insert(
        "remove".into(),
        ActionMeta::new()
            .level(Perm::Write)
            .display("Remove")
            .group(GROUP_EDIT),
    );
    a.insert(
        "ack_all".into(),
        ActionMeta::new()
            .level(Perm::Write)
            .display("Acknowledge all"),
    );
    a.insert(
        "export".into(),
        ActionMeta::new()
            .level(Perm::Read)
            .display("Export")
            .result(ActionResult::Type(TypeCode::Map)),
    );
    a
}

pub fn class_meta(c: &ClassDef) -> NodeMeta {
    let mut m = NodeMeta::folder()
        .display(c.display.clone())
        .attr("escalation1_s", Value::UInt(c.escalation1_s))
        .attr("escalation2_s", Value::UInt(c.escalation2_s))
        .attr("created_by", c.created_by.clone());
    m.actions = Some(class_actions());
    m
}

pub fn count_meta(d: &str, about: &str) -> NodeMeta {
    NodeMeta::leaf(TypeCode::Number)
        .display(d)
        .attr("description", about)
}

pub fn alarms_meta() -> NodeMeta {
    NodeMeta::leaf(TypeCode::Array)
        .display("Alarms")
        .attr(
            "description",
            "The open records, newest first (at most 200), published when they change.",
        )
        .attr(
            "columns",
            Value::Array(
                [
                    "id",
                    "state",
                    "type",
                    "source",
                    "message",
                    "created",
                    "normal",
                    "ack",
                    "ack_by",
                    "escalation",
                    "watch",
                    "value",
                    "notes",
                    "class",
                    "by",
                ]
                .map(Value::from)
                .to_vec(),
            ),
        )
}

pub fn watches_meta() -> NodeMeta {
    NodeMeta::folder().display("Watches")
}

fn watch_actions() -> BTreeMap<String, ActionMeta> {
    let config = |d: &str| {
        ActionMeta::new()
            .level(Perm::Config)
            .display(d)
            .group(GROUP_EDIT)
    };
    BTreeMap::from([
        ("edit".to_owned(), watch_params(config("Edit"), false)),
        ("enable".to_owned(), config("Enable")),
        ("disable".to_owned(), config("Disable")),
        ("remove".to_owned(), config("Remove")),
    ])
}

/// What a watch node shows beside its definition.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct WatchShown {
    pub keys: usize,
    pub in_alarm: usize,
    pub last_change: Option<Micros>,
    pub last_record: Option<u64>,
    pub error: Option<String>,
}

pub fn watch_meta(w: &WatchDef, shown: &WatchShown) -> NodeMeta {
    let mut m = NodeMeta::leaf(TypeCode::String)
        .display(w.id.clone())
        .attr("source", w.sub_key())
        .attr("algorithm", w.algorithm.name())
        .attr("params", Value::Map(w.algorithm.params()))
        .attr("type", w.ty.as_str())
        .attr("message", w.message.clone())
        .attr("to_alarm_s", Value::UInt(w.to_alarm_s))
        .attr("to_normal_s", Value::UInt(w.to_normal_s))
        .attr("keys", Value::UInt(shown.keys as u64))
        .attr("in_alarm", Value::UInt(shown.in_alarm as u64))
        .attr(
            "last_change",
            shown.last_change.map_or(Value::Null, rfc3339),
        )
        .attr(
            "last_record",
            shown.last_record.map_or(Value::Null, Value::UInt),
        )
        .attr("error", shown.error.clone().map_or(Value::Null, Value::Str))
        .attr("created_by", w.created_by.clone());
    m.actions = Some(watch_actions());
    m
}
