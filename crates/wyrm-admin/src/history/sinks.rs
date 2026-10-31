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

fn groups_param() -> ParamMeta {
    str_param()
        .display("Groups")
        .placeholder("all")
        .description("Watch groups it takes, comma separated; empty: all.")
}

fn link_param() -> ParamMeta {
    str_param()
        .display("Link")
        .placeholder("<link id>")
        .description("The installed link that reads the batches and sends them on.")
}

fn with_default(mut p: ParamMeta, v: &str) -> ParamMeta {
    p.default = Some(Value::from(v));
    p
}

/// `groups` as a list; empty or absent = all.
fn arg_groups(args: &Value) -> Vec<String> {
    arg_str(args, "groups")
        .map(|s| {
            s.split(',')
                .map(str::trim)
                .filter(|g| !g.is_empty())
                .map(str::to_owned)
                .collect()
        })
        .unwrap_or_default()
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
        ActionMeta::new()
            .display("Add Sink")
            .group(GROUP_NEW)
            .param("name", str_param().required(true).display("Name"))
            .param("link", link_param().required(true))
            .param("groups", groups_param())
            .param(
                "from",
                str_param()
                    .display("From")
                    .enum_values(["start", "now"])
                    .description("start: everything on disk; now: only rows written from now on."),
            )
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
        ActionMeta::new()
            .display("Edit")
            .group(GROUP_EDIT)
            .param("link", with_default(link_param(), def.link.as_str()))
            .param(
                "groups",
                with_default(groups_param(), &def.groups.join(", ")),
            )
            .level(Perm::Config),
    )
    .await?;
    ctx.declare_action(
        &p,
        "reset_cursor",
        ActionMeta::new()
            .display("Reset Cursor")
            .group(GROUP_EDIT)
            .param(
                "to",
                str_param()
                    .required(true)
                    .display("To")
                    .enum_values(["start", "now"])
                    .description(
                        "start: send everything on disk again; now: skip what is not sent.",
                    ),
            )
            .level(Perm::Config),
    )
    .await?;
    ctx.declare_action(
        &p,
        "remove",
        ActionMeta::new()
            .display("Remove")
            .group(GROUP_EDIT)
            .level(Perm::Config),
    )
    .await?;
    ctx.declare_action(
        &p,
        "next",
        ActionMeta::new()
            .display("Next Batch")
            .param(
                "after",
                ParamMeta::of(TypeCode::Number)
                    .display("After")
                    .description("Confirms every row up to it; empty: the confirmed one."),
            )
            .param(
                "max",
                ParamMeta::of(TypeCode::Number)
                    .display("Max")
                    .placeholder("1000")
                    .description("Rows at most (5000)."),
            )
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
    args: &Value,
    sub: &str,
) -> Result<Option<Value>> {
    let st = ctl.history.store().clone();
    match (rest, action) {
        ([], "add_sink") => {
            let name = arg_str(args, "name").ok_or_else(|| LinkError::invalid_parameter("name"))?;
            let link = arg_str(args, "link").ok_or_else(|| LinkError::invalid_parameter("link"))?;
            if ctl.registry().historian.sinks.contains_key(name) {
                return Err(LinkError::invalid_parameter(format!(
                    "sink {name} exists; use its Edit"
                )));
            }
            let groups = arg_groups(args);
            ctl.apply(Op::PutSink {
                name: name.to_owned(),
                link: link.to_owned(),
                groups: groups.clone(),
            })
            .map_err(rejected)?;
            let from = match arg_str(args, "from") {
                None | Some("start") => 0,
                Some("now") => st.last_seq(),
                Some(f) => {
                    return Err(LinkError::invalid_parameter(format!(
                        "from {f:?}: start or now"
                    )))
                }
            };
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
            let old = sink_def(ctl, name)?;
            let link = arg_str(args, "link").unwrap_or(&old.link).to_owned();
            let groups = match arg(args, "groups") {
                None => old.groups.clone(),
                Some(_) => arg_groups(args),
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
            sink_def(ctl, name)?;
            let to = match arg_str(args, "to") {
                Some("start") => 0,
                Some("now") => st.last_seq(),
                _ => return Err(LinkError::invalid_parameter("to: start or now")),
            };
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
            sink_def(ctl, name)?;
            ctl.apply(Op::RemoveSink((*name).to_owned()))
                .map_err(rejected)?;
            set_cursor(&st, name, None).await?;
            ctl.history.forget_sink(name);
            ctl.record(sub, "history_sink", name, Status::Ok, "removed");
            ctx.remove_node(&format!("{ROOT}/{SINKS}/{name}")).await?;
            Ok(None)
        }
        ([name], "next") => next(ctl, ctx, name, args, sub).await.map(Some),
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
async fn next(ctl: &Control, ctx: &LinkCtx, name: &str, args: &Value, sub: &str) -> Result<Value> {
    let def = sink_def(ctl, name)?;
    // Nobody else moves its cursor: a person who ran it would confirm rows
    // the database never got.
    if sub != format!("link:{}", def.link) {
        return Err(LinkError::new(Status::PermissionDenied, ""));
    }
    let st = ctl.history.store().clone();
    let after = match arg(args, "after") {
        None | Some(Value::Null) => None,
        Some(v) => Some(
            v.as_f64()
                .filter(|a| a.is_finite() && *a >= 0.0)
                .ok_or_else(|| LinkError::invalid_parameter("after: a journal number"))?
                as u64,
        ),
    };
    let max = match arg_num(args, "max") {
        None => DEFAULT_BATCH_ROWS,
        Some(m) if m.is_finite() && m >= 1.0 => (m as usize).min(MAX_BATCH_ROWS),
        Some(_) => return Err(LinkError::invalid_parameter("max: 1 to 5000")),
    };
    let keys = wanted(ctl, &def);
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
    refresh_sink(ctx, ctl, name, &def).await;
    Ok(Value::Map(BTreeMap::from([
        ("rows".to_owned(), Value::Array(rows)),
        ("next".to_owned(), Value::UInt(batch.next)),
    ])))
}
