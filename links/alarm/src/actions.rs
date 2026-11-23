//! The arguments of the alarm link's actions: one struct per action declares its parameters
//! (`~meta`, [`crate::tree`]) and decodes them (`wyrm_core::args`, typing audit 2026-11-15
//! T3). A handler takes its struct; no handler reads a name from the arguments map.
//!
//! [`invoke`] is the one place that decodes: it checks what an action is about first (the
//! class, the watch or the sink that must exist, the caller a sink serves), then the
//! arguments, so what does not exist is `not_found` whatever the arguments are.
//!
//! A set of names (`algorithm`, `type`, `state`, `from`) is an `enum` parameter: through an
//! action it is the index into the list `~meta` declares (spec 02), which is what the SDK
//! lets through. A stored class and an import carry the name ([`crate::model`]).

use wyrm_core::{Status, Value};
use wyrm_link_api::{AppError, Args, Who};

use crate::algo::{AlgorithmArgs, AlgorithmName};
use crate::limits::Counted;
use crate::model::AlarmType;
use crate::{now_of, Alarm};

wyrm_core::name_enum! {
    /// `get_alarms` `state`: which records it answers.
    pub enum AlarmState as "alarm state" without codec {
        /// Active or unacknowledged.
        Open => "open",
        Active => "active",
        Unacked => "unacked",
        Closed => "closed",
        All => "all",
    }
}

wyrm_core::name_enum! {
    /// Where a sink's cursor starts: the oldest journal entry kept, or the newest.
    pub enum SinkFrom as "sink start" without codec {
        Start => "start",
        Now => "now",
    }
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
/// A record's id is `dynamic`, so a scenario or a CLI may pass its decimal text too.
const RECORD_ABOUT: &str = "The record's id (a number).";

// ---------- classes ----------

/// What `add_class` and a class's `edit` set.
#[derive(Args)]
pub(crate) struct ClassArgs {
    #[param(display = "Display")]
    pub display: Option<String>,
    #[param(display = "Escalation 1", desc = ESCALATION_ABOUT)]
    pub escalation1_s: Option<u64>,
    #[param(display = "Escalation 2", desc = ESCALATION_ABOUT)]
    pub escalation2_s: Option<u64>,
}

/// `add_class`.
#[derive(Args)]
pub(crate) struct AddClass {
    #[param(display = "ID", placeholder = "line1")]
    pub id: String,
    #[param(flatten)]
    pub class: ClassArgs,
}

/// `import`: a class's export.
#[derive(Args)]
pub(crate) struct Import {
    #[param(display = "JSON", editor = "textarea", desc = "A class's export.")]
    pub json: String,
    #[param(
        display = "Overwrite",
        desc = "Replace a class with the same id.",
        absent = false
    )]
    pub overwrite: bool,
}

// ---------- watches ----------

/// What `add_watch` and a watch's `edit` set beside the source and the algorithm.
#[derive(Args)]
pub(crate) struct WatchArgs {
    #[param(flatten)]
    pub algorithm: AlgorithmArgs,
    #[param(name = "type", display = "Type", enum, desc = TYPE_ABOUT)]
    pub ty: Option<AlarmType>,
    #[param(display = "Message", desc = MESSAGE_ABOUT)]
    pub message: Option<String>,
    #[param(
        display = "To alarm",
        desc = "Seconds the condition must hold before a record is made (0)."
    )]
    pub to_alarm_s: Option<u64>,
    #[param(
        display = "To normal",
        desc = "Seconds the condition must be gone before the record is normal (0)."
    )]
    pub to_normal_s: Option<u64>,
    #[param(display = "Enabled")]
    pub enabled: Option<bool>,
}

/// `<class> ▸ add_watch`.
#[derive(Args)]
pub(crate) struct AddWatch {
    #[param(
        display = "Source",
        placeholder = "wy/site/downstream/plc/temp",
        desc = SOURCE_ABOUT
    )]
    pub source: String,
    #[param(display = "Algorithm", enum, desc = ALGORITHM_ABOUT)]
    pub algorithm: AlgorithmName,
    #[param(flatten)]
    pub watch: WatchArgs,
}

/// `<watch> ▸ edit`: what is not given stays.
#[derive(Args)]
pub(crate) struct EditWatch {
    #[param(
        display = "Source",
        placeholder = "wy/site/downstream/plc/temp",
        desc = SOURCE_ABOUT
    )]
    pub source: Option<String>,
    #[param(display = "Algorithm", enum, desc = ALGORITHM_ABOUT)]
    pub algorithm: Option<AlgorithmName>,
    #[param(flatten)]
    pub watch: WatchArgs,
}

// ---------- records ----------

/// `raise`.
#[derive(Args)]
pub(crate) struct Raise {
    #[param(display = "Class")]
    pub class: String,
    #[param(
        display = "Source",
        desc = "The point the alarm is about (a key of this site)."
    )]
    pub source: String,
    #[param(name = "type", display = "Type", enum, desc = TYPE_ABOUT)]
    pub ty: Option<AlarmType>,
    #[param(display = "Message")]
    pub message: Option<String>,
}

/// `get_alarm`, `get_notes`: one record by its id (a number, or its decimal text).
#[derive(Args)]
pub(crate) struct RecordArg {
    #[param(display = "Record", desc = RECORD_ABOUT)]
    pub id: Value,
}

/// `acknowledge`.
#[derive(Args)]
pub(crate) struct Acknowledge {
    #[param(display = "Record", desc = RECORD_ABOUT)]
    pub id: Value,
    #[param(display = "Note")]
    pub note: Option<String>,
}

/// `normal`.
#[derive(Args)]
pub(crate) struct Normal {
    #[param(display = "Record", desc = "A record made with Raise Alarm.")]
    pub id: Value,
}

/// `add_note`.
#[derive(Args)]
pub(crate) struct AddNote {
    #[param(display = "Record", desc = RECORD_ABOUT)]
    pub id: Value,
    #[param(display = "Note", editor = "textarea")]
    pub note: String,
}

/// The root's `ack_all`.
#[derive(Args)]
pub(crate) struct AckAll {
    #[param(display = "Class", desc = "Only this class; empty: every class.")]
    pub class: Option<String>,
}

/// `get_alarms`.
#[derive(Args)]
pub(crate) struct GetAlarms {
    #[param(
        display = "Timerange",
        placeholder = "2026-11-01T00:00:00Z/2026-11-08T00:00:00Z",
        editor = "daterange",
        desc = "From/to in RFC 3339 on the creation time (a date is its midnight \
                UTC); empty: any time."
    )]
    pub timerange: Option<String>,
    #[param(display = "Class")]
    pub class: Option<String>,
    #[param(display = "Source", desc = "A key, or a prefix ending with /.")]
    pub source: Option<String>,
    #[param(
        display = "State",
        enum,
        desc = "open: active or unacknowledged (default)."
    )]
    pub state: Option<AlarmState>,
    #[param(name = "type", display = "Type", enum)]
    pub ty: Option<AlarmType>,
    #[param(display = "Limit", desc = "Rows at most (500, at most 5000).")]
    pub limit: Option<u64>,
}

/// `purge`.
#[derive(Args)]
pub(crate) struct Purge {
    #[param(
        display = "Before",
        desc = "Closed records created before this instant (RFC 3339) go."
    )]
    pub before: String,
}

// ---------- sinks ----------

/// `add_sink`.
#[derive(Args)]
pub(crate) struct AddSink {
    #[param(display = "Name", placeholder = "cloud")]
    pub name: String,
    #[param(
        display = "Link",
        desc = "The installed link that reads the batches (a history sync link)."
    )]
    pub link: String,
    #[param(
        display = "Classes",
        desc = "Class ids it takes, comma separated; empty: all."
    )]
    pub classes: Option<String>,
    #[param(
        display = "From",
        enum,
        desc = "start: the oldest journal entry kept; now: new changes only."
    )]
    pub from: Option<SinkFrom>,
}

/// `<sink> ▸ next`.
#[derive(Args)]
pub(crate) struct SinkNext {
    #[param(
        display = "After",
        desc = "Confirms every entry up to it; default: the confirmed one."
    )]
    pub after: Option<u64>,
    #[param(display = "Max", desc = "Rows at most (1000, at most 5000).")]
    pub max: Option<u64>,
}

/// `<sink> ▸ edit`.
#[derive(Args)]
pub(crate) struct EditSink {
    #[param(display = "Link")]
    pub link: Option<String>,
    #[param(display = "Classes")]
    pub classes: Option<String>,
}

/// `<sink> ▸ reset`.
#[derive(Args)]
pub(crate) struct ResetSink {
    #[param(display = "From", enum)]
    pub from: SinkFrom,
}

// ---------- dispatch ----------

/// One action on the node at `path` (relative to the link root). What the action is about is
/// looked up before its arguments are decoded.
pub(crate) fn invoke(
    app: &mut Alarm,
    cx: &mut Counted,
    path: &str,
    action: &str,
    args: Value,
    who: &Who,
) -> Result<Value, AppError> {
    let now = now_of(cx);
    let parts: Vec<&str> = if path.is_empty() {
        Vec::new()
    } else {
        path.split('/').collect()
    };
    match (parts.as_slice(), action) {
        ([], "add_class") => app.add_class(cx, AddClass::decode(args)?, who, now),
        ([], "raise") => app.raise_action(cx, Raise::decode(args)?, who, now),
        ([], "acknowledge") => app.acknowledge_action(cx, Acknowledge::decode(args)?, who, now),
        ([], "normal") => app.normal_action(cx, Normal::decode(args)?, who, now),
        ([], "add_note") => app.add_note_action(cx, AddNote::decode(args)?, who, now),
        ([], "ack_all") => {
            let a = AckAll::decode(args)?;
            let class = a.class.filter(|c| !c.is_empty());
            app.ack_all(cx, class.as_deref(), who, now)
        }
        ([], "get_alarm") => app.get_alarm(cx, RecordArg::decode(args)?, who),
        ([], "get_notes") => app.get_notes(cx, RecordArg::decode(args)?, who),
        ([], "get_alarms") => {
            crate::known_rights(who)?;
            app.get_alarms(cx, GetAlarms::decode(args)?, who)
        }
        ([], "import") => {
            app.loaded()?;
            app.import(cx, Import::decode(args)?, who, now)
        }
        ([], "purge") => app.purge_action(cx, Purge::decode(args)?, now),
        ([], "add_sink") => app.add_sink(cx, AddSink::decode(args)?),
        (["sinks", s], "next") => {
            app.sink_reader(s, who)?;
            app.sink_next(cx, s, SinkNext::decode(args)?, who, now)
        }
        (["sinks", s], "edit") => {
            app.sink(s)?;
            app.edit_sink(cx, s, EditSink::decode(args)?)
        }
        (["sinks", s], "reset") => {
            app.sink(s)?;
            app.reset_sink(cx, s, ResetSink::decode(args)?)
        }
        (["sinks", s], "remove") => {
            app.sink(s)?;
            <()>::decode(args)?;
            app.remove_sink(cx, s)
        }
        ([c], "add_watch") => {
            app.room_for_watch(c)?;
            app.add_watch(cx, c, AddWatch::decode(args)?, who, now)
        }
        ([c], "edit") => {
            app.class(c)?;
            app.edit_class(cx, c, ClassArgs::decode(args)?)
        }
        ([c], "remove") => {
            app.class(c)?;
            <()>::decode(args)?;
            app.remove_class(cx, c)
        }
        ([c], "ack_all") => {
            app.class(c)?;
            <()>::decode(args)?;
            app.ack_all(cx, Some(c), who, now)
        }
        ([c], "export") => {
            app.class(c)?;
            <()>::decode(args)?;
            app.export(c)
        }
        ([c, "watches", w], "edit") => {
            app.class(c)?.watch_at(w)?;
            app.edit_watch(cx, c, w, EditWatch::decode(args)?, who, now)
        }
        ([c, "watches", w], "enable" | "disable" | "remove") => {
            app.class(c)?.watch_at(w)?;
            <()>::decode(args)?;
            match action {
                "enable" => app.enable_watch(cx, c, w, true, now),
                "disable" => app.enable_watch(cx, c, w, false, now),
                _ => app.remove_watch(cx, c, w, now),
            }
        }
        _ => Err(AppError::new(
            Status::NotSupported,
            format!("{path:?}: no {action}"),
        )),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn args<const N: usize>(entries: [(&str, Value); N]) -> Value {
        Value::Map(
            entries
                .into_iter()
                .map(|(k, v)| (k.to_owned(), v))
                .collect(),
        )
    }

    fn refused<T: Args>(v: Value) -> String {
        match T::decode(v) {
            Ok(_) => panic!("the arguments are refused"),
            Err(e) => AppError::from(e).msg,
        }
    }

    /// A required argument that is absent or `null` is refused with its name; a `dynamic`
    /// one (`id`) takes a `null` that is there, and the handler refuses it.
    #[test]
    fn missing_and_null() {
        assert_eq!(refused::<AddClass>(args([])), "id: required");
        assert_eq!(
            refused::<AddClass>(args([("id", Value::Null)])),
            "id: required"
        );
        assert_eq!(
            refused::<Raise>(args([("class", Value::from("c"))])),
            "source: required"
        );
        assert_eq!(
            refused::<AddNote>(args([("id", Value::UInt(1))])),
            "note: required"
        );
        assert_eq!(
            refused::<AddNote>(args([("id", Value::UInt(1)), ("note", Value::Null)])),
            "note: required"
        );
        assert_eq!(refused::<Acknowledge>(args([])), "id: required");
        let a = Acknowledge::decode(args([("id", Value::Null)])).unwrap();
        assert_eq!(a.id, Value::Null);
        assert_eq!(Alarm::record_id(&a.id).unwrap_err().msg, "id: required");
        assert_eq!(refused::<ResetSink>(args([])), "from: required");
        assert_eq!(refused::<Purge>(args([])), "before: required");
        // an optional argument that is null is not there
        let r = Raise::decode(args([
            ("class", Value::from("c")),
            ("source", Value::from("wy/s/downstream/plc/t")),
            ("type", Value::Null),
            ("message", Value::Null),
        ]))
        .unwrap();
        assert!(r.ty.is_none() && r.message.is_none());
        let e = EditWatch::decode(args([("min", Value::Null), ("source", Value::Null)])).unwrap();
        assert!(e.watch.algorithm.min.is_none() && e.source.is_none());
    }

    #[test]
    fn wrong_types_and_numbers() {
        assert_eq!(
            refused::<AddClass>(args([("id", Value::UInt(1))])),
            "id: expected text"
        );
        assert_eq!(
            refused::<Import>(args([
                ("json", Value::from("{}")),
                ("overwrite", Value::from("yes"))
            ])),
            "overwrite: expected true or false"
        );
        assert_eq!(
            refused::<AddNote>(args([("id", Value::UInt(1)), ("note", Value::UInt(2))])),
            "note: expected text"
        );
        // a whole number: an integer, or a float without a fraction
        let g = GetAlarms::decode(args([("limit", Value::Float(7.0))])).unwrap();
        assert_eq!(g.limit, Some(7));
        let g = GetAlarms::decode(args([("limit", Value::Int(7))])).unwrap();
        assert_eq!(g.limit, Some(7));
        assert!(refused::<GetAlarms>(args([("limit", Value::Float(7.5))]))
            .starts_with("limit: expected a whole number"));
        assert!(refused::<GetAlarms>(args([("limit", Value::Int(-1))]))
            .starts_with("limit: expected a whole number"));
        assert_eq!(
            refused::<GetAlarms>(args([("limit", Value::from("7"))])),
            "limit: expected a number"
        );
        // a number of the algorithm: an integer is a float too
        let w =
            EditWatch::decode(args([("max", Value::UInt(5)), ("min", Value::Int(-2))])).unwrap();
        assert_eq!(w.watch.algorithm.max, Some(5.0));
        assert_eq!(w.watch.algorithm.min, Some(-2.0));
        assert_eq!(
            refused::<EditWatch>(args([("max", Value::Float(f64::NAN))])),
            "max: expected a finite number"
        );
        // a record id: a number or its decimal text
        for (v, id) in [
            (Value::UInt(9), 9),
            (Value::Float(9.0), 9),
            (Value::from(" 9 "), 9),
        ] {
            let a = RecordArg::decode(args([("id", v)])).unwrap();
            assert_eq!(Alarm::record_id(&a.id).unwrap(), id);
        }
        for (v, msg) in [
            (Value::from("nine"), "id: a record id"),
            (Value::Int(-1), "id: must be a whole number from 0"),
            (Value::Float(1.5), "id: must be a whole number from 0"),
            (Value::Bool(true), "id: must be a whole number from 0"),
        ] {
            let a = RecordArg::decode(args([("id", v)])).unwrap();
            assert_eq!(Alarm::record_id(&a.id).unwrap_err().msg, msg);
        }
    }

    /// An `enum` parameter is the index into the list `~meta` declares.
    #[test]
    fn enums_by_index() {
        let w = AddWatch::decode(args([
            ("source", Value::from("wy/s/downstream/plc/t")),
            ("algorithm", Value::UInt(1)),
            ("type", Value::UInt(2)),
        ]))
        .unwrap();
        assert_eq!(w.algorithm, AlgorithmName::OutOfRange);
        assert_eq!(w.watch.ty, Some(AlarmType::Fault));
        let g = GetAlarms::decode(args([("state", Value::UInt(4))])).unwrap();
        assert_eq!(g.state, Some(AlarmState::All));
        let r = ResetSink::decode(args([("from", Value::UInt(1))])).unwrap();
        assert_eq!(r.from, SinkFrom::Now);
        assert_eq!(
            refused::<GetAlarms>(args([("state", Value::UInt(5))])),
            "state: index 5 is out of the list of 5"
        );
        assert_eq!(
            refused::<GetAlarms>(args([("state", Value::from("open"))])),
            "state: expected an index"
        );
    }

    #[test]
    fn unknown_names_and_no_map() {
        assert_eq!(
            refused::<AckAll>(args([("clas", Value::from("c"))])),
            "clas: unknown argument"
        );
        assert_eq!(
            refused::<()>(args([("x", Value::UInt(1))])),
            "x: unknown argument"
        );
        assert_eq!(
            refused::<AckAll>(Value::Null),
            "args: expected a map of arguments"
        );
        assert!(<()>::decode(args([])).is_ok());
    }
}
