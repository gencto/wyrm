//! `sys/history/sinks` (ADR 0026): links that read the history in batches
//! to send it on to another database. A sink names its link and the watch
//! groups it takes; its cursor is in the history store and moves with each
//! `next` (the `after` of a request confirms every row up to it). Only the
//! sink's link may call `next`: it signs as `link:<id>` with its requester
//! key, which the admin trusts at `read` on the sink's node alone.

use super::*;
use crate::registry::SinkDef;
use wyrm_history::ChangeLimit;

pub(super) const SINKS: &str = "sinks";
/// Rows of one batch: by default and at most; bytes of the values at most.
const DEFAULT_BATCH_ROWS: usize = 1_000;
const MAX_BATCH_ROWS: usize = 5_000;
const MAX_BATCH_BYTES: usize = 1 << 20;

/// Values of a sink: key, type, description.
const VALUES: [(&str, TypeCode, &str); 7] = [
    (
        "link",
        TypeCode::String,
        "The link that reads this sink's batches (it signs as link:<id>).",
    ),
    (
        "groups",
        TypeCode::String,
        "Watch groups it takes, comma separated; empty: all.",
    ),
    (
        "confirmed_seq",
        TypeCode::Number,
        "The last journal entry its link confirmed.",
    ),
    (
        "lag_entries",
        TypeCode::Number,
        "Journal entries after the confirmed one (rows of groups it does not take count too).",
    ),
    (
        "rows_sent",
        TypeCode::Number,
        "Rows handed out in batches since the broker started.",
    ),
    (
        "rows_dropped_unsent",
        TypeCode::Number,
        "Rows of its groups deleted (Retention Days, Auto Purge) before its link confirmed them, \
         since the broker started.",
    ),
    (
        "last_request",
        TypeCode::String,
        "Time of its link's last batch request.",
    ),
];

/// The `requester` key scope of sink `name`: its link reaches this node only.
pub fn sink_key(site: &str, name: &str) -> String {
    format!("wy/{site}/sys/{ROOT}/{SINKS}/{name}")
}

const GROUPS_ABOUT: &str = "Watch groups it takes, comma separated; empty: all.";
const LINK_ABOUT: &str = "The installed link that reads the batches and sends them on.";

wyrm_core::name_enum! {
    /// Where a sink's cursor is put.
    enum Cursor as "cursor" without codec {
        /// Everything on disk.
        Start => "start",
        /// Only rows written from now on.
        Now => "now",
    }
}

impl Cursor {
    fn seq(self, st: &wyrm_history::Store) -> u64 {
        match self {
            Cursor::Start => 0,
            Cursor::Now => st.last_seq(),
        }
    }
}

/// `history/sinks ▸ add_sink`.
#[derive(Args)]
struct AddSink {
    #[param(display = "Name", trim, nonempty)]
    name: String,
    #[param(
        display = "Link",
        placeholder = "<link id>",
        desc = LINK_ABOUT,
        trim,
        nonempty
    )]
    link: String,
    #[param(display = "Groups", placeholder = "all", desc = GROUPS_ABOUT)]
    groups: Option<String>,
    #[param(
        choice,
        trim,
        nonempty,
        display = "From",
        desc = "start: everything on disk; now: only rows written from now on."
    )]
    from: Option<Cursor>,
}

/// `history/sinks/<name> ▸ edit`: a field left out stays as it is.
#[derive(Args)]
struct EditSink {
    #[param(
        display = "Link",
        placeholder = "<link id>",
        desc = LINK_ABOUT,
        trim,
        nonempty
    )]
    link: Option<String>,
    /// Given and empty: all groups.
    #[param(display = "Groups", placeholder = "all", desc = GROUPS_ABOUT)]
    groups: Option<String>,
}

/// `history/sinks/<name> ▸ reset_cursor`.
#[derive(Args)]
struct ResetCursor {
    #[param(
        choice,
        trim,
        display = "To",
        desc = "start: send everything on disk again; now: skip what is not sent."
    )]
    to: Cursor,
}

/// `history/sinks/<name> ▸ next`: one batch for the sink's link.
#[derive(Args)]
struct Next {
    /// A journal number is whole: `5.5` would confirm row 5 and send row 6 again.
    #[param(
        display = "After",
        desc = "Confirms every row up to it; empty: the confirmed one."
    )]
    after: Option<u64>,
    #[param(
        display = "Max",
        placeholder = "1000",
        desc = "Rows at most (5000).",
        min = 1
    )]
    max: Option<u64>,
}

/// The names of a `groups` field (`a, b`); empty = all.
fn group_names(text: &str) -> Vec<String> {
    text.split(',')
        .map(str::trim)
        .filter(|g| !g.is_empty())
        .map(str::to_owned)
        .collect()
}

pub(super) async fn declare(ctx: &LinkCtx, ctl: &Control) -> Result<()> {
    let p = format!("{ROOT}/{SINKS}");
    ctx.declare_node(
        &p,
        NodeMeta::folder().attr(
            "description",
            "Links that read the history in batches and send it on to another database (ADR 0026).",
        ),
    )
    .await?;
    ctx.declare_action(
        &p,
        "add_sink",
        AddSink::action()
            .display("Add sink")
            .group(GROUP_NEW)
            .level(Perm::Config),
    )
    .await?;
    for (name, def) in ctl.registry().historian.sinks {
        declare_sink(ctx, ctl, &name, &def).await?;
    }
    Ok(())
}

async fn declare_sink(ctx: &LinkCtx, ctl: &Control, name: &str, def: &SinkDef) -> Result<()> {
    let p = format!("{ROOT}/{SINKS}/{name}");
    ctx.declare_node(&p, NodeMeta::folder()).await?;
    for (key, ty, about) in VALUES {
        ctx.declare_node(
            &format!("{p}/{key}"),
            NodeMeta::leaf(ty).attr("description", about),
        )
        .await?;
    }
    ctx.declare_action(
        &p,
        "edit",
        EditSink::action()
            .display("Edit")
            .group(GROUP_EDIT)
            // what is in force, pre-filled
            .shown("link", |p| p.default(def.link.as_str()))
            .shown("groups", |p| p.default(def.groups.join(", ")))
            .level(Perm::Config),
    )
    .await?;
    ctx.declare_action(
        &p,
        "reset_cursor",
        ResetCursor::action()
            .display("Reset cursor")
            .group(GROUP_EDIT)
            .level(Perm::Config),
    )
    .await?;
    ctx.declare_action(
        &p,
        "remove",
        <()>::action()
            .display("Remove")
            .group(GROUP_EDIT)
            .level(Perm::Config),
    )
    .await?;
    ctx.declare_action(
        &p,
        "next",
        Next::action()
            .display("Next batch")
            // the sink's link only: rows after the cursor, and the cursor to ask after next
            .result(ActionResult::Type(TypeCode::Map))
            .level(Perm::Read),
    )
    .await?;
    refresh_sink(ctx, ctl, name, def).await;
    Ok(())
}

/// The values of every sink.
pub(super) async fn refresh(ctx: &LinkCtx, ctl: &Control) {
    for (name, def) in ctl.registry().historian.sinks {
        refresh_sink(ctx, ctl, &name, &def).await;
    }
}

async fn refresh_sink(ctx: &LinkCtx, ctl: &Control, name: &str, def: &SinkDef) {
    let st = ctl.history.store().clone();
    let n = name.to_owned();
    let Ok(Ok(confirmed)) = tokio::task::spawn_blocking(move || st.sink_seq(&n)).await else {
        return;
    };
    let last = ctl.history.store().last_seq();
    let s = ctl.history.sink_stats(name, |s| s.clone());
    let p = format!("{ROOT}/{SINKS}/{name}");
    let t = now_us();
    let last_request = if s.last_request_us == 0 {
        Value::Null
    } else {
        Value::Str(iso_us(s.last_request_us))
    };
    for (key, v) in [
        ("link", Value::from(def.link.as_str())),
        ("groups", Value::from(def.groups.join(", "))),
        ("confirmed_seq", Value::UInt(confirmed)),
        ("lag_entries", Value::UInt(last.saturating_sub(confirmed))),
        ("rows_sent", Value::UInt(s.rows_sent)),
        ("rows_dropped_unsent", Value::UInt(s.dropped_unsent)),
        ("last_request", last_request),
    ] {
        let _ = ctx.update(&format!("{p}/{key}"), v, Quality::Good, t).await;
    }
}

fn sink_def(ctl: &Control, name: &str) -> Result<SinkDef> {
    ctl.registry()
        .historian
        .sinks
        .get(name)
        .cloned()
        .ok_or_else(|| LinkError::not_found(format!("sink {name}")))
}

/// The point keys a sink takes, by series number (watches of its groups
/// that were ever recorded).
pub(super) fn wanted(ctl: &Control, def: &SinkDef) -> HashMap<u32, String> {
    let reg = ctl.registry();
    let st = ctl.history.store();
    reg.historian
        .groups
        .iter()
        .filter(|(g, _)| def.groups.is_empty() || def.groups.contains(g))
        .flat_map(|(_, g)| g.watches.values())
        .filter_map(|w| Some((st.series_id(&w.key, false).ok()??, w.key.clone())))
        .collect()
}

/// Each sink with its cursor and series, to count what a deleted day held
/// that it had not confirmed.
pub(super) fn cursors(ctl: &Control) -> Vec<(String, u64, HashSet<u32>)> {
    let st = ctl.history.store();
    ctl.registry()
        .historian
        .sinks
        .iter()
        .map(|(name, def)| {
            (
                name.clone(),
                st.sink_seq(name).unwrap_or(0),
                wanted(ctl, def).into_keys().collect(),
            )
        })
        .collect()
}

/// `sinks/**` actions; `rest` follows `sinks`.
pub(super) async fn invoke(
    ctl: &Control,
    ctx: &LinkCtx,
    rest: &[&str],
    action: &str,
    args: Value,
    sub: &str,
) -> Result<Option<Value>> {
    let st = ctl.history.store().clone();
    match (rest, action) {
        ([], "add_sink") => {
            let a = AddSink::decode(args)?;
            let (name, link) = (a.name.as_str(), a.link.as_str());
            if ctl.registry().historian.sinks.contains_key(name) {
                return Err(LinkError::invalid_parameter(format!(
                    "sink {name} exists; use its Edit"
                )));
            }
            let groups = a.groups.as_deref().map(group_names).unwrap_or_default();
            ctl.apply(Op::PutSink {
                name: name.to_owned(),
                link: link.to_owned(),
                groups: groups.clone(),
            })
            .map_err(rejected)?;
            let from = a.from.unwrap_or(Cursor::Start).seq(&st);
            set_cursor(&st, name, Some(from)).await?;
            ctl.record(
                sub,
                "history_sink",
                name,
                Status::Ok,
                &format!("added: link {link}, groups [{}]", groups.join(", ")),
            );
            let def = sink_def(ctl, name)?;
            declare_sink(ctx, ctl, name, &def).await?;
            Ok(None)
        }
        ([name], "edit") => {
            let a = EditSink::decode(args)?;
            let old = sink_def(ctl, name)?;
            let link = a.link.unwrap_or_else(|| old.link.clone());
            let groups = match a.groups.as_deref() {
                None => old.groups.clone(),
                Some(g) => group_names(g),
            };
            ctl.apply(Op::PutSink {
                name: (*name).to_owned(),
                link: link.clone(),
                groups: groups.clone(),
            })
            .map_err(rejected)?;
            ctl.record(
                sub,
                "history_sink",
                name,
                Status::Ok,
                &format!("edited: link {link}, groups [{}]", groups.join(", ")),
            );
            let def = sink_def(ctl, name)?;
            declare_sink(ctx, ctl, name, &def).await?;
            Ok(None)
        }
        ([name], "reset_cursor") => {
            let a = ResetCursor::decode(args)?;
            sink_def(ctl, name)?;
            let to = a.to.seq(&st);
            set_cursor(&st, name, Some(to)).await?;
            ctl.record(
                sub,
                "history_sink",
                name,
                Status::Ok,
                &format!("cursor reset to {to}"),
            );
            refresh_sink(ctx, ctl, name, &sink_def(ctl, name)?).await;
            Ok(None)
        }
        ([name], "remove") => {
            <()>::decode(args)?;
            sink_def(ctl, name)?;
            ctl.apply(Op::RemoveSink((*name).to_owned()))
                .map_err(rejected)?;
            set_cursor(&st, name, None).await?;
            ctl.history.forget_sink(name);
            ctl.record(sub, "history_sink", name, Status::Ok, "removed");
            ctx.remove_node(&format!("{ROOT}/{SINKS}/{name}")).await?;
            Ok(None)
        }
        ([name], "next") => {
            // the caller first: nobody but the sink's link learns anything of
            // this action, not even that its arguments were wrong
            let def = its_link(ctl, name, sub)?;
            next(ctl, ctx, name, &def, Next::decode(args)?)
                .await
                .map(Some)
        }
        _ => Err(LinkError::not_supported(format!(
            "{ROOT}/{SINKS}/{}/~act/{action}",
            rest.join("/")
        ))),
    }
}

async fn set_cursor(st: &Arc<wyrm_history::Store>, name: &str, seq: Option<u64>) -> Result<()> {
    let (st, n) = (st.clone(), name.to_owned());
    tokio::task::spawn_blocking(move || st.set_sink_seq(&n, seq))
        .await
        .map_err(|e| LinkError::internal(e.to_string()))?
        .map_err(|e| LinkError::internal(e.to_string()))
}

/// One batch for the sink's link: `{rows: [{seq, key, t, v, q}], next}`.
/// `after` (default: the confirmed entry) confirms every row up to it.
/// The sink `name` for its own link `sub`. Nobody else moves its cursor: a
/// person who ran `next` would confirm rows the database never got.
fn its_link(ctl: &Control, name: &str, sub: &str) -> Result<SinkDef> {
    let def = sink_def(ctl, name)?;
    if sub != format!("link:{}", def.link) {
        return Err(LinkError::new(Status::PermissionDenied, ""));
    }
    Ok(def)
}

async fn next(ctl: &Control, ctx: &LinkCtx, name: &str, def: &SinkDef, a: Next) -> Result<Value> {
    let st = ctl.history.store().clone();
    let after = a.after;
    let max = match a.max {
        None => DEFAULT_BATCH_ROWS,
        Some(m) => usize::try_from(m).map_or(MAX_BATCH_ROWS, |m| m.min(MAX_BATCH_ROWS)),
    };
    let keys = wanted(ctl, def);
    let n = name.to_owned();
    let batch = tokio::task::spawn_blocking(move || {
        let after = match after {
            Some(a) => {
                if a > st.last_seq() {
                    return Ok(Err(a));
                }
                st.set_sink_seq(&n, Some(a))?;
                a
            }
            None => st.sink_seq(&n)?,
        };
        let limit = ChangeLimit {
            rows: max,
            bytes: MAX_BATCH_BYTES,
        };
        st.changes(after, limit, |s| keys.contains_key(&s))
            .map(|b| Ok((b, keys)))
    })
    .await
    .map_err(|e| LinkError::internal(e.to_string()))?
    .map_err(|e| LinkError::internal(e.to_string()))?;
    let (batch, keys) = batch.map_err(|a| {
        LinkError::invalid_parameter(format!("after {a}: beyond the last journal entry"))
    })?;
    let rows: Vec<Value> = batch
        .rows
        .into_iter()
        .filter_map(|c| {
            let key = keys.get(&c.series)?;
            Some(Value::Map(BTreeMap::from([
                ("seq".to_owned(), Value::UInt(c.seq)),
                ("key".to_owned(), Value::from(key.as_str())),
                ("t".to_owned(), Value::UInt(c.row.t)),
                ("v".to_owned(), c.row.v),
                ("q".to_owned(), Value::UInt(c.row.q.code().into())),
            ])))
        })
        .collect();
    let sent = rows.len() as u64;
    ctl.history.sink_stats(name, |s| {
        s.rows_sent += sent;
        s.last_request_us = now_us();
    });
    refresh_sink(ctx, ctl, name, def).await;
    Ok(Value::Map(BTreeMap::from([
        ("rows".to_owned(), Value::Array(rows)),
        ("next".to_owned(), Value::UInt(batch.next)),
    ])))
}

/// Every `Args` struct of this file with the parameter name it declares twice,
/// if any (audit of #136: a name that comes again through `flatten`). The list
/// is checked against the file: a struct that is not on it fails the test.
#[cfg(test)]
pub(crate) fn arg_structs() -> Vec<(&'static str, Option<&'static str>)> {
    use wyrm_core::args::repeated_param;
    let list = vec![
        (stringify!(AddSink), repeated_param::<AddSink>()),
        (stringify!(EditSink), repeated_param::<EditSink>()),
        (stringify!(ResetCursor), repeated_param::<ResetCursor>()),
        (stringify!(Next), repeated_param::<Next>()),
    ];
    let derives = include_str!("sinks.rs")
        .matches(concat!("#[derive(", "Args"))
        .count();
    assert_eq!(
        list.len(),
        derives,
        "history/sinks.rs: list every Args struct"
    );
    list
}

#[cfg(test)]
mod tests {
    use super::*;

    fn args(kv: &[(&str, Value)]) -> Value {
        Value::Map(
            kv.iter()
                .map(|(k, v)| ((*k).to_owned(), v.clone()))
                .collect(),
        )
    }

    /// A cursor is `start` or `now`, with white space around it as before; a batch
    /// is at least one row and its cursor a whole number.
    #[test]
    fn sink_arguments() {
        let add = |from: Value| {
            AddSink::decode(args(&[
                ("name", " s ".into()),
                ("link", " ext ".into()),
                ("from", from),
            ]))
            .map(|a| (a.name, a.link, a.from))
        };
        assert_eq!(
            add(" now ".into()),
            Ok(("s".to_owned(), "ext".to_owned(), Some(Cursor::Now)))
        );
        assert_eq!(add("".into()).map(|a| a.2), Ok(None));
        assert_eq!(add("later".into()).unwrap_err().field, "from");
        let to = |v: Value| ResetCursor::decode(args(&[("to", v)])).map(|a| a.to);
        assert_eq!(to(" start".into()), Ok(Cursor::Start));
        assert_eq!(to("".into()).unwrap_err().field, "to");
        assert_eq!(
            ResetCursor::decode(args(&[]))
                .map(|_| ())
                .unwrap_err()
                .field,
            "to"
        );
        // an edit: a field left out stays, `groups` given and empty is all groups
        let e = EditSink::decode(args(&[("groups", "".into())])).unwrap();
        assert_eq!(
            (e.link, e.groups.as_deref().map(group_names)),
            (None, Some(vec![]))
        );
        let next = |kv: &[(&str, Value)]| Next::decode(args(kv)).map(|a| (a.after, a.max));
        assert_eq!(next(&[("after", Value::UInt(5))]), Ok((Some(5), None)));
        assert_eq!(
            next(&[("after", Value::Float(5.5))]).unwrap_err().field,
            "after"
        );
        assert_eq!(next(&[("max", Value::UInt(0))]).unwrap_err().field, "max");
    }
}
