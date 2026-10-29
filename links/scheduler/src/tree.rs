//! Node and action meta of the scheduler's tree (ADR 0022 "Tree and actions", plan ruling 1),
//! paths relative to the link root:
//!
//! ```text
//! ""              add_schedule, import (config)
//! <s>             attrs display, tz, source, next_time, next_value; add_event, get_events,
//!                 export, edit, remove; add_target (config)
//! <s>/current     the schedule's value now (read-only)
//! <s>/default     writable value (saved)
//! <s>/enabled     writable bool (saved)
//! <s>/events/<e>  attrs value, start, end, recurrence, priority, special, display; edit, remove
//! <s>/targets     folder
//! <s>/targets/<t> the target's state; attrs point, confirm, feedback, last_error,
//!                 last_write, attempts, created_by; edit, enable, disable, remove (config)
//! ```
//!
//! A value node cannot have children (spec 02: `type` only on leaves), so the schedule is a
//! container and its value is the leaf `current`.

use std::collections::BTreeMap;

use wyrm_core::meta::{
    ActionResult, ParamMeta, Writable, EDITOR_DATERANGE, EDITOR_TEXTAREA, GROUP_EDIT, GROUP_NEW,
};
use wyrm_core::{ActionMeta, NodeMeta, Perm, TypeCode, Value};
use wyrm_schedule::{format_local, Event, Micros, Schedule, Source, State};

use crate::limits::NODES_PER_SCHEDULE;
use crate::targets::{Confirm, Target, RESUME_COST};

pub fn current(s: &str) -> String {
    format!("{s}/current")
}
pub fn default(s: &str) -> String {
    format!("{s}/default")
}
pub fn enabled(s: &str) -> String {
    format!("{s}/enabled")
}
pub fn events(s: &str) -> String {
    format!("{s}/events")
}
pub fn targets(s: &str) -> String {
    format!("{s}/targets")
}
pub fn event(s: &str, e: &str) -> String {
    format!("{s}/events/{e}")
}
pub fn target(s: &str, t: &str) -> String {
    format!("{s}/targets/{t}")
}

/// Nodes a schedule with `targets` targets takes.
pub fn nodes_of(s: &Schedule, targets: usize) -> usize {
    NODES_PER_SCHEDULE + s.events.len() + targets
}

/// Commands that load and declare a schedule: its nodes, the values of `current`, `default`,
/// `enabled`, a held moment that ended deleted, and what each target does at start.
pub fn declare_cost(s: &Schedule, targets: usize) -> usize {
    NODES_PER_SCHEDULE + s.events.len() + 4 + targets * RESUME_COST
}

/// [`declare_cost`] of a schedule without events.
pub fn declare_cost_min() -> usize {
    NODES_PER_SCHEDULE + 4
}

/// An RFC 3339 instant (`2026-10-29T17:00:00Z`).
pub fn rfc3339(t: Micros) -> Value {
    match jiff::Timestamp::from_microsecond(t) {
        Ok(ts) => Value::Str(ts.to_string()),
        Err(_) => Value::Null,
    }
}

pub fn source_name(s: &Source) -> &str {
    match s {
        Source::Default => "default",
        Source::Event { id, .. } | Source::Moment { id, .. } => id,
    }
}

fn param(ty: TypeCode, display: &str) -> ParamMeta {
    ParamMeta::of(ty).display(display)
}

fn text_param(display: &str) -> ParamMeta {
    param(TypeCode::String, display)
}

const ZONE_ABOUT: &str = "IANA time zone of the event times (Europe/Kyiv); empty: the link's \
     default_tz.";
const LOCAL_ABOUT: &str = "Local time in the schedule's zone, YYYY-MM-DDTHH:MM[:SS], no offset.";
const RRULE_ABOUT: &str = "RRULE subset: FREQ=HOURLY|DAILY|WEEKLY|MONTHLY|YEARLY, INTERVAL, \
     COUNT or UNTIL, BYDAY, BYMONTHDAY, BYMONTH. Empty: once.";
const PRIORITY_ABOUT: &str = "1 (highest) to 9; 0 = none (lowest).";
const SPECIAL_ABOUT: &str = "On a day a special event touches, only special events count.";

/// The fields of `add_event` and an event's `edit`; `required` marks `value`, `start`, `end`.
fn event_params(a: ActionMeta, required: bool) -> ActionMeta {
    a.param("display", text_param("Display"))
        .param(
            "value",
            param(TypeCode::Dynamic, "Value").required(required),
        )
        .param(
            "start",
            text_param("Start")
                .required(required)
                .placeholder("2026-11-02T08:00")
                .description(LOCAL_ABOUT),
        )
        .param(
            "end",
            text_param("End")
                .required(required)
                .placeholder("2026-11-02T17:00")
                .description(LOCAL_ABOUT),
        )
        .param(
            "recurrence",
            text_param("Recurrence")
                .placeholder("FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR")
                .description(RRULE_ABOUT),
        )
        .param(
            "priority",
            param(TypeCode::Number, "Priority").description(PRIORITY_ABOUT),
        )
        .param(
            "special",
            param(TypeCode::Bool, "Special").description(SPECIAL_ABOUT),
        )
}

/// The actions of the link root.
pub fn root_actions() -> [(&'static str, ActionMeta); 2] {
    [
        (
            "add_schedule",
            ActionMeta::new()
                .level(Perm::Write)
                .display("Add Schedule")
                .group(GROUP_NEW)
                .param("id", text_param("Id").required(true).placeholder("lobby"))
                .param("display", text_param("Display"))
                .param("tz", text_param("Time Zone").description(ZONE_ABOUT))
                .param(
                    "default",
                    param(TypeCode::Dynamic, "Default")
                        .required(true)
                        .description("The value when no event is active."),
                )
                .param("enabled", param(TypeCode::Bool, "Enabled")),
        ),
        (
            "import",
            // it carries targets: configuration (ruling 6)
            ActionMeta::new()
                .level(Perm::Config)
                .display("Import Schedule")
                .group(GROUP_NEW)
                .result(ActionResult::Type(TypeCode::Map))
                .param(
                    "json",
                    text_param("JSON")
                        .required(true)
                        .editor(EDITOR_TEXTAREA)
                        .description("This link's export, or a DSA localschedule export."),
                )
                .param(
                    "id",
                    text_param("Id").description(
                        "The schedule's id; default: the id in the export (DSA: its name).",
                    ),
                )
                .param(
                    "overwrite",
                    param(TypeCode::Bool, "Overwrite")
                        .description("Replace a schedule with the same id."),
                ),
        ),
    ]
}

fn schedule_actions() -> BTreeMap<String, ActionMeta> {
    let mut a = BTreeMap::new();
    a.insert(
        "add_event".into(),
        event_params(
            ActionMeta::new()
                .level(Perm::Write)
                .display("Add Event")
                .group(GROUP_NEW)
                .result(ActionResult::Type(TypeCode::Map)),
            true,
        ),
    );
    a.insert(
        "get_events".into(),
        ActionMeta::new()
            .level(Perm::Read)
            .display("Get Events")
            .result(ActionResult::Type(TypeCode::Array))
            .param(
                "timerange",
                text_param("Timerange")
                    .required(true)
                    .placeholder("2026-11-02T00:00:00Z/2026-11-09T00:00:00Z")
                    .editor(EDITOR_DATERANGE)
                    .description("From/to in RFC 3339 (a date is its midnight UTC)."),
            )
            .param(
                "limit",
                param(TypeCode::Number, "Limit").description("Rows at most (1000, at most 5000)."),
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
        ActionMeta::new()
            .level(Perm::Write)
            .display("Edit")
            .group(GROUP_EDIT)
            .param("display", text_param("Display"))
            .param("tz", text_param("Time Zone").description(ZONE_ABOUT))
            .param("default", param(TypeCode::Dynamic, "Default")),
    );
    a.insert(
        "remove".into(),
        ActionMeta::new()
            .level(Perm::Write)
            .display("Remove")
            .group(GROUP_EDIT),
    );
    a.insert(
        "add_target".into(),
        // it points the scheduler at a device: configuration (ruling 6)
        target_params(
            ActionMeta::new()
                .level(Perm::Config)
                .display("Add Target")
                .group(GROUP_NEW)
                .result(ActionResult::Type(TypeCode::Map)),
            true,
        ),
    );
    a
}

const POINT_ABOUT: &str =
    "The point written on each transition: wy/<site>/downstream/<link>/<path>.";
const CONFIRM_ABOUT: &str = "read_back: the point's value shows the write; feedback: another \
     point shows the expected value; ack: an ok reply is enough.";
const MAP_ABOUT: &str = "JSON object, schedule value → value to write ({\"true\": 1, \
     \"false\": 0}).";
const FEEDBACK_MAP_ABOUT: &str = "JSON object, schedule value → value the feedback point shows.";
const TOLERANCE_ABOUT: &str = "Relative tolerance of numbers (absolute at 0); default 1e-6.";

/// The fields of `add_target` and a target's `edit`; `required` marks `point` and `confirm`.
fn target_params(a: ActionMeta, required: bool) -> ActionMeta {
    a.param(
        "point",
        text_param("Point")
            .required(required)
            .placeholder("wy/site/downstream/plc/fan")
            .description(POINT_ABOUT),
    )
    .param(
        "confirm",
        param(TypeCode::Enum, "Confirm")
            .required(required)
            .enum_values(Confirm::ALL.map(Confirm::as_str))
            .description(CONFIRM_ABOUT),
    )
    .param(
        "feedback",
        text_param("Feedback Point").description("With confirm feedback: the point to read."),
    )
    .param("map", text_param("Map").description(MAP_ABOUT))
    .param(
        "feedback_map",
        text_param("Feedback Map").description(FEEDBACK_MAP_ABOUT),
    )
    .param(
        "tolerance",
        param(TypeCode::Number, "Tolerance").description(TOLERANCE_ABOUT),
    )
}

fn target_actions() -> BTreeMap<String, ActionMeta> {
    let config = |display: &str| {
        ActionMeta::new()
            .level(Perm::Config)
            .display(display)
            .group(GROUP_EDIT)
    };
    BTreeMap::from([
        ("edit".to_owned(), target_params(config("Edit"), false)),
        ("enable".to_owned(), config("Enable")),
        ("disable".to_owned(), config("Disable")),
        ("remove".to_owned(), config("Remove")),
    ])
}

/// A target node: its state is the value, the rest attributes.
pub fn target_meta(t: &Target) -> NodeMeta {
    let d = &t.def;
    let mut m = NodeMeta::leaf(TypeCode::String)
        .display(d.id.clone())
        .attr("point", d.point.clone())
        .attr("confirm", d.confirm.as_str())
        .attr(
            "feedback",
            d.feedback.clone().map_or(Value::Null, Value::Str),
        )
        .attr(
            "last_error",
            t.last_error.clone().map_or(Value::Null, Value::Str),
        )
        .attr("last_write", t.last_write.map_or(Value::Null, rfc3339))
        .attr("attempts", Value::UInt(t.attempts))
        .attr("created_by", d.created_by.clone());
    m.actions = Some(target_actions());
    m
}

/// The schedule node: its attributes now, with its actions.
pub fn schedule_meta(s: &Schedule, state: &State, next: Option<&(Micros, State)>) -> NodeMeta {
    let mut m = NodeMeta::folder()
        .display(s.display.clone())
        .attr("tz", s.tz.clone())
        .attr("source", source_name(&state.source))
        .attr("next_time", next.map_or(Value::Null, |(t, _)| rfc3339(*t)))
        .attr(
            "next_value",
            next.map_or(Value::Null, |(_, n)| n.value.clone()),
        );
    m.actions = Some(schedule_actions());
    m
}

pub fn current_meta() -> NodeMeta {
    NodeMeta::leaf(TypeCode::Dynamic)
        .display("Current")
        .attr("description", "The schedule's value now.")
}

pub fn default_meta() -> NodeMeta {
    NodeMeta::leaf(TypeCode::Dynamic)
        .writable(Writable::Write)
        .display("Default")
        .attr("description", "The value when no event is active.")
}

pub fn enabled_meta() -> NodeMeta {
    NodeMeta::leaf(TypeCode::Bool)
        .writable(Writable::Write)
        .display("Enabled")
        .attr(
            "description",
            "Off: the schedule shows its value but wakes and writes nothing.",
        )
}

pub fn events_meta() -> NodeMeta {
    NodeMeta::folder().display("Events")
}

pub fn targets_meta() -> NodeMeta {
    NodeMeta::folder().display("Targets")
}

pub fn event_meta(e: &Event) -> NodeMeta {
    let mut m = NodeMeta::folder()
        .display(if e.display.is_empty() {
            e.id.clone()
        } else {
            e.display.clone()
        })
        .attr("value", e.value.clone())
        .attr("start", format_local(e.start))
        .attr("end", format_local(e.end))
        .attr(
            "recurrence",
            e.recurrence
                .as_ref()
                .map_or(Value::Null, |r| Value::Str(r.to_string())),
        )
        .attr("priority", Value::UInt(u64::from(e.priority)))
        .attr("special", Value::Bool(e.special));
    let mut a = BTreeMap::new();
    a.insert(
        "edit".to_owned(),
        event_params(
            ActionMeta::new()
                .level(Perm::Write)
                .display("Edit")
                .group(GROUP_EDIT),
            false,
        ),
    );
    a.insert(
        "remove".to_owned(),
        ActionMeta::new()
            .level(Perm::Write)
            .display("Remove")
            .group(GROUP_EDIT),
    );
    m.actions = Some(a);
    m
}
