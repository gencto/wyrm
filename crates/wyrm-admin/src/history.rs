//! `sys/history`: the embedded historian's nodes (ADR 0014), as DSA's etsdb
//! link: database values and purge settings, watch groups with their logging
//! type, and watches with Get History, Purge and Unsubscribe.
//!
//! The settings live in the registry (`Registry::historian`); the rows in
//! `data_dir/history` ([`wyrm_history::Store`]).

use crate::control::{disk_free_mib, rejected, Control};
use crate::registry::{check_watch_key, Op, Registry, WatchDef, WatchGroupDef, FLUSH_MS};
use std::collections::{BTreeMap, HashMap};
use std::sync::atomic::Ordering;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tracing::{info, warn};
use wyrm_core::meta::{ActionResult, ParamMeta, Writable, GROUP_EDIT, GROUP_NEW};
use wyrm_core::{ActionMeta, NodeMeta, Perm, Quality, Status, TypeCode, Value};
use wyrm_history::time::{iso_us, parse_interval, parse_range, US_PER_DAY};
use wyrm_history::{GroupCfg, HistoryQuery, Logging, Rollup, WatchCfg};
use wyrm_link_sdk::{now_us, LinkCtx, LinkError};

type Result<T> = wyrm_link_sdk::Result<T>;

const ROOT: &str = "history";
/// Rows of one Get History: by default and at most.
const DEFAULT_ROWS: usize = 1000;
const MAX_ROWS: usize = 10_000;
/// How often retention and free space are checked.
const PURGE_EVERY: Duration = Duration::from_secs(60);

/// Database values: key, display name, unit, description.
const DB_VALUES: [(&str, &str, &str, &str); 9] = [
    (
        "rows_written",
        "Rows Written",
        "",
        "Rows written since the broker started.",
    ),
    (
        "writes_per_second",
        "Writes Per Second",
        "rows/s",
        "Rows written per second over the metrics interval.",
    ),
    (
        "rows_pending",
        "Rows Pending",
        "",
        "Rows in memory waiting for the next flush.",
    ),
    (
        "rows_dropped",
        "Rows Dropped",
        "",
        "Rows lost since the broker started: a full buffer or a failed write.",
    ),
    (
        "last_flush",
        "Last Flush Duration",
        "ms",
        "Time of the last write to disk.",
    ),
    (
        "database_size",
        "Database Size",
        "MiB",
        "Size of data_dir/history: one file per day (UTC) and the index.",
    ),
    (
        "space_available",
        "Space Available",
        "MiB",
        "Free space on the file system of data_dir/history.",
    ),
    ("series", "Series", "", "Points that were ever recorded."),
    (
        "day_files",
        "Day Files",
        "",
        "Day files on disk (one per UTC day).",
    ),
];

/// Writable settings: key, display name, type, unit, description.
const OPTIONS: [(&str, &str, TypeCode, &str, &str); 3] = [
    (
        "auto_purge",
        "Auto Purge",
        TypeCode::Bool,
        "",
        "Delete the oldest day while the disk has less free space than \
         Disk Space Remaining (never the current day).",
    ),
    (
        "disk_space_remaining",
        "Disk Space Remaining",
        TypeCode::Number,
        "MiB",
        "Free space Auto Purge keeps on the disk of data_dir/history.",
    ),
    (
        "retention_days",
        "Retention Days",
        TypeCode::Number,
        "d",
        "Delete days older than this; 0 keeps every day.",
    ),
];

/// Node names under `history` that a group cannot take.
fn reserved(name: &str) -> bool {
    DB_VALUES.iter().any(|v| v.0 == name)
        || OPTIONS.iter().any(|o| o.0 == name)
        || name == "oldest_day"
}

/// The engine settings of the registry's watch groups.
pub fn groups(reg: &Registry) -> Vec<GroupCfg> {
    reg.historian
        .groups
        .iter()
        .map(|(name, g)| GroupCfg {
            name: name.clone(),
            logging: Logging::from_code(g.logging).unwrap_or(Logging::None),
            interval_ms: g.interval_ms,
            flush_ms: g.flush_ms,
            watches: g
                .watches
                .iter()
                .map(|(id, w)| WatchCfg {
                    id: id.clone(),
                    key: w.key.clone(),
                    enabled: w.enabled,
                })
                .collect(),
        })
        .collect()
}

fn arg<'a>(args: &'a Value, name: &str) -> Option<&'a Value> {
    match args {
        Value::Map(m) => m.get(name),
        _ => None,
    }
}

fn arg_str<'a>(args: &'a Value, name: &str) -> Option<&'a str> {
    match arg(args, name) {
        Some(Value::Str(s)) => Some(s.trim()).filter(|s| !s.is_empty()),
        _ => None,
    }
}

fn arg_num(args: &Value, name: &str) -> Option<f64> {
    arg(args, name).and_then(Value::as_f64)
}

/// A logging type from its display name, name or index.
fn arg_logging(args: &Value) -> Result<Option<Logging>> {
    match arg(args, "logging_type") {
        None | Some(Value::Null) => Ok(None),
        Some(Value::UInt(i)) => Logging::ALL
            .get(*i as usize)
            .copied()
            .map(Some)
            .ok_or_else(|| LinkError::invalid_parameter("logging_type?")),
        Some(Value::Str(s)) if s.trim().is_empty() => Ok(None),
        Some(Value::Str(s)) => Logging::parse(s.trim())
            .map(Some)
            .ok_or_else(|| LinkError::invalid_parameter(format!("logging type {s:?}?"))),
        Some(_) => Err(LinkError::invalid_parameter("logging_type: a name")),
    }
}

/// Seconds → ms; `None` keeps `current`.
fn arg_ms(args: &Value, name: &str, current: u64) -> Result<u64> {
    match arg_num(args, name) {
        None => Ok(current),
        Some(s) if s.is_finite() && s >= 0.0 => Ok((s * 1000.0).round() as u64),
        Some(_) => Err(LinkError::invalid_parameter(format!("{name}: seconds"))),
    }
}

fn str_param() -> ParamMeta {
    ParamMeta::of(TypeCode::String)
}

fn logging_param(current: Option<Logging>) -> ParamMeta {
    let mut p = str_param()
        .enum_values(Logging::ALL.iter().map(|l| l.display()))
        .display("Logging Type")
        .description(
            "None: record nothing. Interval: the last value every Interval. \
             All Data: every update. Point Change: updates whose value or quality changed.",
        );
    if let Some(l) = current {
        p = p.placeholder(l.display());
    }
    p
}

fn seconds_param(display: &str, about: &str, current: Option<u64>) -> ParamMeta {
    let mut p = ParamMeta::of(TypeCode::Number)
        .display(display)
        .description(about);
    if let Some(ms) = current {
        p = p.placeholder(format!("{}", ms as f64 / 1000.0));
    }
    p
}

const INTERVAL_ABOUT: &str = "Seconds between two rows of Interval logging (0.1 s to 1 day).";
const FLUSH_ABOUT: &str = "Seconds between writes to disk (0 = 0.1 s, at most 10 min); \
     rows wait in memory until then.";

fn timerange_param() -> ParamMeta {
    str_param()
        .required(true)
        .display("Timerange")
        .placeholder("2026-10-22T00:00:00Z/2026-10-23T00:00:00Z")
        .description("From/to in RFC 3339 (a date is its midnight UTC); an empty end is now.")
}

/// `sys/history` and everything under it.
pub(crate) async fn declare(ctx: &LinkCtx, ctl: &Control) -> Result<()> {
    ctx.declare_node(
        ROOT,
        NodeMeta::folder().display("History").attr(
            "description",
            "The embedded historian: watch groups record points into data_dir/history.",
        ),
    )
    .await?;
    for (key, display, unit, about) in DB_VALUES {
        let mut m = NodeMeta::number()
            .display(display)
            .attr("description", about);
        if !unit.is_empty() {
            m = m.unit(unit);
        }
        ctx.declare_node(&format!("{ROOT}/{key}"), m).await?;
    }
    ctx.declare_node(
        &format!("{ROOT}/oldest_day"),
        NodeMeta::leaf(TypeCode::String)
            .display("Oldest Day")
            .attr("description", "The oldest day on disk (UTC)."),
    )
    .await?;
    let h = ctl.registry().historian;
    let current = [
        Value::Bool(h.auto_purge),
        Value::UInt(h.keep_free_mib),
        Value::UInt(h.retention_days.into()),
    ];
    for ((key, display, ty, unit, about), v) in OPTIONS.into_iter().zip(current) {
        let mut m = NodeMeta::leaf(ty)
            .display(display)
            .writable(Writable::Config)
            .attr("description", about);
        if !unit.is_empty() {
            m = m.unit(unit);
        }
        let path = format!("{ROOT}/{key}");
        ctx.declare_node(&path, m).await?;
        ctx.update(&path, v, Quality::Good, now_us()).await?;
    }
    ctx.declare_action(
        ROOT,
        "add_watch_group",
        ActionMeta::new()
            .display("Add Watch Group")
            .group(GROUP_NEW)
            .param("name", str_param().required(true).display("Name"))
            .param("logging_type", logging_param(None))
            .param(
                "interval",
                seconds_param("Interval", INTERVAL_ABOUT, None).placeholder("60"),
            )
            .param(
                "buffer_flush_time",
                seconds_param("Buffer Flush Time", FLUSH_ABOUT, None).placeholder("5"),
            )
            .level(Perm::Config),
    )
    .await?;
    ctx.declare_action(
        ROOT,
        "purge",
        ActionMeta::new()
            .display("Purge")
            .group(GROUP_EDIT)
            .param("timerange", timerange_param())
            .result(ActionResult::Type(TypeCode::Map))
            .level(Perm::Config),
    )
    .await?;
    for (name, g) in &h.groups {
        declare_group(ctx, name, g).await?;
    }
    Ok(())
}

async fn declare_group(ctx: &LinkCtx, name: &str, g: &WatchGroupDef) -> Result<()> {
    let p = format!("{ROOT}/{name}");
    ctx.declare_node(&p, NodeMeta::folder().display(name))
        .await?;
    group_values(ctx, name, g).await?;
    ctx.declare_action(
        &p,
        "add_watch_path",
        ActionMeta::new()
            .display("Add Watch Path")
            .group(GROUP_NEW)
            .param(
                "path",
                str_param()
                    .required(true)
                    .display("Path")
                    .placeholder("down/<link>/<point>")
                    .description(
                        "A point of this site (down/… or flows/…, or the full wy/<site>/… key) \
                         or of a downstream site (wy/<site>/…).",
                    ),
            )
            .level(Perm::Config),
    )
    .await?;
    ctx.declare_action(
        &p,
        "remove",
        ActionMeta::new()
            .display("Delete")
            .group(GROUP_EDIT)
            .param(
                "purge",
                ParamMeta::of(TypeCode::Bool)
                    .display("Purge")
                    .description("Also delete the recorded rows of its watches."),
            )
            .level(Perm::Config),
    )
    .await?;
    for (id, w) in &g.watches {
        declare_watch(ctx, name, id, w).await?;
    }
    Ok(())
}

/// A group's setting values, and its Edit action showing them.
async fn group_values(ctx: &LinkCtx, name: &str, g: &WatchGroupDef) -> Result<()> {
    let p = format!("{ROOT}/{name}");
    let logging = Logging::from_code(g.logging).unwrap_or(Logging::None);
    let t = now_us();
    ctx.declare_node(
        &format!("{p}/logging_type"),
        NodeMeta::leaf(TypeCode::String).display("Logging Type"),
    )
    .await?;
    ctx.update(
        &format!("{p}/logging_type"),
        Value::from(logging.display()),
        Quality::Good,
        t,
    )
    .await?;
    for (key, display, ms) in [
        ("interval", "Interval", g.interval_ms),
        ("buffer_flush_time", "Buffer Flush Time", g.flush_ms),
    ] {
        let k = format!("{p}/{key}");
        ctx.declare_node(&k, NodeMeta::number().display(display).unit("s"))
            .await?;
        ctx.update(&k, Value::Float(ms as f64 / 1000.0), Quality::Good, t)
            .await?;
    }
    ctx.declare_action(
        &p,
        "edit",
        ActionMeta::new()
            .display("Edit")
            .group(GROUP_EDIT)
            .param("logging_type", logging_param(Some(logging)))
            .param(
                "interval",
                seconds_param("Interval", INTERVAL_ABOUT, Some(g.interval_ms)),
            )
            .param(
                "buffer_flush_time",
                seconds_param("Buffer Flush Time", FLUSH_ABOUT, Some(g.flush_ms)),
            )
            .level(Perm::Config),
    )
    .await
}

async fn declare_watch(ctx: &LinkCtx, group: &str, id: &str, w: &WatchDef) -> Result<()> {
    let p = format!("{ROOT}/{group}/{id}");
    ctx.declare_node(
        &p,
        NodeMeta::folder()
            .display(w.key.as_str())
            .attr("path", w.key.as_str()),
    )
    .await?;
    ctx.declare_node(
        &format!("{p}/enabled"),
        NodeMeta::leaf(TypeCode::Bool)
            .display("Enabled")
            .writable(Writable::Config),
    )
    .await?;
    ctx.update(
        &format!("{p}/enabled"),
        Value::Bool(w.enabled),
        Quality::Good,
        now_us(),
    )
    .await?;
    for (key, display) in [("start_date", "Start Date"), ("end_date", "End Date")] {
        ctx.declare_node(
            &format!("{p}/{key}"),
            NodeMeta::leaf(TypeCode::String).display(display),
        )
        .await?;
    }
    // No "Last Written Value" (DSA has one): sys would publish point values
    // to everyone who may read sys, not only to who may read the point.
    ctx.declare_action(
        &p,
        "get_history",
        ActionMeta::new()
            .display("Get History")
            .param("timerange", timerange_param())
            .param(
                "interval",
                str_param()
                    .display("Interval")
                    .placeholder("none")
                    .description(
                        "none, or a number and s, m, h, d or w (5m): one row per interval.",
                    ),
            )
            .param(
                "rollup",
                str_param()
                    .enum_values(Rollup::ALL.iter().map(|r| r.name()))
                    .display("Rollup")
                    .description(
                        "How the samples of one interval become one value (none: the first).",
                    ),
            )
            .param(
                "limit",
                ParamMeta::of(TypeCode::Number)
                    .display("Rows")
                    .placeholder(format!("{DEFAULT_ROWS} (at most {MAX_ROWS})")),
            )
            .result(ActionResult::Type(TypeCode::Array))
            // Config, as all of sys/history: the rows are point values, and
            // a role with read on sys has no read on the points (ADR 0014).
            .level(Perm::Config),
    )
    .await?;
    ctx.declare_action(
        &p,
        "purge",
        ActionMeta::new()
            .display("Purge")
            .group(GROUP_EDIT)
            .param("timerange", timerange_param())
            .result(ActionResult::Type(TypeCode::Map))
            .level(Perm::Config),
    )
    .await?;
    ctx.declare_action(
        &p,
        "unsubscribe",
        ActionMeta::new()
            .display("Unsubscribe")
            .group(GROUP_EDIT)
            .level(Perm::Config),
    )
    .await?;
    ctx.declare_action(
        &p,
        "unsubscribe_purge",
        ActionMeta::new()
            .display("Unsubscribe and Purge")
            .group(GROUP_EDIT)
            .result(ActionResult::Type(TypeCode::Map))
            .level(Perm::Config),
    )
    .await
}

/// Start and end date of a watch from the store (first and last row).
async fn refresh_dates(ctl: &Control, ctx: &LinkCtx, group: &str, id: &str, key: &str) {
    let st = ctl.history.store().clone();
    let k = key.to_owned();
    let edges = tokio::task::spawn_blocking(move || {
        let Some(s) = st.series_id(&k, false)? else {
            return Ok((None, None));
        };
        Ok::<_, wyrm_history::store::Error>((st.edge(s, false)?, st.edge(s, true)?))
    })
    .await;
    let (first, last) = match edges {
        Ok(Ok(e)) => e,
        Ok(Err(e)) => {
            warn!(%key, "history dates: {e}");
            return;
        }
        Err(_) => return,
    };
    let p = format!("{ROOT}/{group}/{id}");
    let t = now_us();
    let date = |r: &Option<wyrm_history::Row>| match r {
        Some(r) => Value::Str(iso_us(r.t)),
        None => Value::Null,
    };
    let _ = ctx
        .update(&format!("{p}/start_date"), date(&first), Quality::Good, t)
        .await;
    let _ = ctx
        .update(&format!("{p}/end_date"), date(&last), Quality::Good, t)
        .await;
}

async fn refresh_all(ctl: &Control, ctx: &LinkCtx) {
    for (g, def) in ctl.registry().historian.groups {
        for (id, w) in def.watches {
            refresh_dates(ctl, ctx, &g, &id, &w.key).await;
        }
    }
}

/// The new settings go to the running historian.
fn apply_groups(ctl: &Control) {
    ctl.history.configure(groups(&ctl.registry()));
}

/// A watch path as typed (`down/…`, `/down/…`, `wy/<site>/…`) → its full
/// key; only this site and downstream sites.
fn watch_key(ctl: &Control, path: &str) -> Result<String> {
    let path = path.trim().trim_matches('/');
    let site = &ctl.config().site;
    let key = if path.starts_with("down/") || path.starts_with("flows/") {
        format!("wy/{site}/{path}")
    } else {
        path.to_owned()
    };
    check_watch_key(&key).map_err(LinkError::invalid_parameter)?;
    let s = key.split('/').nth(1).unwrap_or_default();
    if s != site && !ctl.peers().downstream.iter().any(|d| d == s) {
        return Err(LinkError::invalid_parameter(format!(
            "{key}: site {s} is neither this site nor a downstream one"
        )));
    }
    Ok(key)
}

fn watch_def(ctl: &Control, group: &str, id: &str) -> Result<WatchDef> {
    ctl.registry()
        .historian
        .groups
        .get(group)
        .and_then(|g| g.watches.get(id))
        .cloned()
        .ok_or_else(|| LinkError::not_found(format!("watch {group}/{id}")))
}

/// Delete rows of `key` (or of every series) in a range; refresh the dates.
async fn purge(ctl: &Control, key: Option<&str>, from: u64, to: u64) -> Result<u64> {
    let st = ctl.history.store().clone();
    let k = key.map(str::to_owned);
    let n = tokio::task::spawn_blocking(move || {
        let series = match &k {
            Some(k) => match st.series_id(k, false)? {
                Some(s) => Some(s),
                None => return Ok(0),
            },
            None => None,
        };
        st.purge(series, from, to)
    })
    .await
    .map_err(|e| LinkError::internal(e.to_string()))?
    .map_err(|e| LinkError::internal(e.to_string()))?;
    match key {
        Some(k) => ctl.history.forget(k),
        None => {
            for g in groups(&ctl.registry()) {
                for w in g.watches {
                    ctl.history.forget(&w.key);
                }
            }
        }
    }
    Ok(n)
}

fn deleted(n: u64) -> Value {
    Value::Map(BTreeMap::from([("deleted".to_owned(), Value::UInt(n))]))
}

fn range_arg(args: &Value) -> Result<(u64, u64)> {
    let r = arg_str(args, "timerange").ok_or_else(|| LinkError::invalid_parameter("timerange"))?;
    parse_range(r, now_us()).ok_or_else(|| {
        LinkError::invalid_parameter(format!(
            "timerange {r:?}: <from>/<to> in RFC 3339, from before to"
        ))
    })
}

/// `history/**` writes: the purge settings and a watch's `enabled`.
pub(crate) async fn set(
    ctl: &Control,
    ctx: &LinkCtx,
    rest: &[&str],
    value: Value,
    sub: &str,
) -> Result<()> {
    let h = ctl.registry().historian;
    let (mut auto, mut keep, mut days) = (h.auto_purge, h.keep_free_mib, h.retention_days);
    match rest {
        ["auto_purge"] => {
            auto = match value {
                Value::Bool(b) => b,
                _ => return Err(LinkError::invalid_parameter("auto_purge: true or false")),
            }
        }
        ["disk_space_remaining"] => {
            keep = value
                .as_f64()
                .filter(|v| v.is_finite() && *v >= 0.0)
                .ok_or_else(|| LinkError::invalid_parameter("disk_space_remaining: MiB"))?
                as u64
        }
        ["retention_days"] => {
            days = value
                .as_f64()
                .filter(|v| v.is_finite() && (0.0..=36_500.0).contains(v))
                .ok_or_else(|| LinkError::invalid_parameter("retention_days: 0 to 36500"))?
                as u32
        }
        [group, id, "enabled"] => {
            let Value::Bool(on) = value else {
                return Err(LinkError::invalid_parameter("enabled: true or false"));
            };
            ctl.apply(Op::SetWatchEnabled {
                group: (*group).to_owned(),
                id: (*id).to_owned(),
                on,
            })
            .map_err(rejected)?;
            ctl.record(
                sub,
                "history_watch",
                &format!("{group}/{id}"),
                Status::Ok,
                if on { "enabled" } else { "disabled" },
            );
            apply_groups(ctl);
            let path = format!("{ROOT}/{group}/{id}/enabled");
            return ctx
                .update(&path, Value::Bool(on), Quality::Good, now_us())
                .await;
        }
        _ => {
            return Err(LinkError::not_supported(format!(
                "{ROOT}/{}/~set",
                rest.join("/")
            )))
        }
    }
    ctl.apply(Op::SetHistoryOptions {
        auto_purge: auto,
        keep_free_mib: keep,
        retention_days: days,
    })
    .map_err(rejected)?;
    ctl.record(
        sub,
        "history_options",
        ROOT,
        Status::Ok,
        &format!("auto_purge {auto}, disk_space_remaining {keep} MiB, retention_days {days}"),
    );
    let t = now_us();
    for (key, v) in [
        ("auto_purge", Value::Bool(auto)),
        ("disk_space_remaining", Value::UInt(keep)),
        ("retention_days", Value::UInt(days.into())),
    ] {
        ctx.update(&format!("{ROOT}/{key}"), v, Quality::Good, t)
            .await?;
    }
    Ok(())
}

/// `history/**` actions.
pub(crate) async fn invoke(
    ctl: &Control,
    ctx: &LinkCtx,
    rest: &[&str],
    action: &str,
    args: &Value,
    sub: &str,
) -> Result<Option<Value>> {
    match (rest, action) {
        ([], "add_watch_group") => {
            let name = arg_str(args, "name").ok_or_else(|| LinkError::invalid_parameter("name"))?;
            if reserved(name) {
                return Err(LinkError::invalid_parameter(format!(
                    "{name}: a value of history has that name"
                )));
            }
            if ctl.registry().historian.groups.contains_key(name) {
                return Err(LinkError::invalid_parameter(format!(
                    "watch group {name} exists; use its Edit"
                )));
            }
            let logging = arg_logging(args)?.unwrap_or(Logging::AllData);
            ctl.apply(Op::PutWatchGroup {
                name: name.to_owned(),
                logging: logging.code(),
                interval_ms: arg_ms(args, "interval", 60_000)?,
                // 0 = as soon as possible (DSA): the shortest flush
                flush_ms: arg_ms(args, "buffer_flush_time", 5_000)?.max(*FLUSH_MS.start()),
            })
            .map_err(rejected)?;
            ctl.record(sub, "history_group", name, Status::Ok, logging.name());
            let g = ctl.registry().historian.groups[name].clone();
            declare_group(ctx, name, &g).await?;
            apply_groups(ctl);
            Ok(None)
        }
        ([], "purge") => {
            let (from, to) = range_arg(args)?;
            let n = purge(ctl, None, from, to).await?;
            ctl.record(
                sub,
                "history_purge",
                ROOT,
                Status::Ok,
                &format!("{} {}: {n} rows", iso_us(from), iso_us(to)),
            );
            refresh_all(ctl, ctx).await;
            Ok(Some(deleted(n)))
        }
        ([group], "edit") => {
            let g = ctl
                .registry()
                .historian
                .groups
                .get(*group)
                .cloned()
                .ok_or_else(|| LinkError::not_found(format!("watch group {group}")))?;
            let logging = arg_logging(args)?
                .or(Logging::from_code(g.logging))
                .unwrap_or(Logging::None);
            ctl.apply(Op::PutWatchGroup {
                name: (*group).to_owned(),
                logging: logging.code(),
                interval_ms: arg_ms(args, "interval", g.interval_ms)?,
                flush_ms: arg_ms(args, "buffer_flush_time", g.flush_ms)?.max(*FLUSH_MS.start()),
            })
            .map_err(rejected)?;
            ctl.record(sub, "history_group", group, Status::Ok, logging.name());
            let g = ctl.registry().historian.groups[*group].clone();
            group_values(ctx, group, &g).await?;
            apply_groups(ctl);
            Ok(None)
        }
        ([group], "add_watch_path") => {
            let path = arg_str(args, "path").ok_or_else(|| LinkError::invalid_parameter("path"))?;
            let key = watch_key(ctl, path)?;
            let before: Vec<String> = ctl
                .registry()
                .historian
                .groups
                .get(*group)
                .map(|g| g.watches.keys().cloned().collect())
                .unwrap_or_default();
            ctl.apply(Op::AddWatch {
                group: (*group).to_owned(),
                key: key.clone(),
            })
            .map_err(rejected)?;
            ctl.record(
                sub,
                "history_watch",
                group,
                Status::Ok,
                &format!("add {key}"),
            );
            let reg = ctl.registry();
            if let Some((id, w)) = reg.historian.groups[*group]
                .watches
                .iter()
                .find(|(id, _)| !before.contains(id))
            {
                declare_watch(ctx, group, id, w).await?;
                refresh_dates(ctl, ctx, group, id, &w.key).await;
            }
            apply_groups(ctl);
            Ok(None)
        }
        ([group], "remove") => {
            let g = ctl
                .registry()
                .historian
                .groups
                .get(*group)
                .cloned()
                .ok_or_else(|| LinkError::not_found(format!("watch group {group}")))?;
            ctl.apply(Op::RemoveWatchGroup((*group).to_owned()))
                .map_err(rejected)?;
            apply_groups(ctl);
            let mut n = 0;
            if matches!(arg(args, "purge"), Some(Value::Bool(true))) {
                for w in g.watches.values() {
                    n += purge(ctl, Some(&w.key), 0, u64::MAX).await?;
                }
            }
            ctl.record(
                sub,
                "history_group",
                group,
                Status::Ok,
                &format!("removed; {n} rows purged"),
            );
            ctx.remove_node(&format!("{ROOT}/{group}")).await?;
            Ok(None)
        }
        ([group, id], "get_history") => {
            let w = watch_def(ctl, group, id)?;
            let (from, to) = range_arg(args)?;
            let interval = parse_interval(arg_str(args, "interval").unwrap_or("none"))
                .map_err(LinkError::invalid_parameter)?;
            let rollup = match arg(args, "rollup") {
                Some(Value::UInt(i)) => Rollup::ALL.get(*i as usize).copied(),
                _ => Rollup::parse(arg_str(args, "rollup").unwrap_or("none")),
            }
            .ok_or_else(|| LinkError::invalid_parameter("rollup?"))?;
            let limit = arg_num(args, "limit")
                .filter(|n| n.is_finite() && *n >= 1.0)
                .map_or(DEFAULT_ROWS, |n| (n as usize).min(MAX_ROWS));
            let rows = query(ctl, &w.key, from, to, interval, rollup, limit).await?;
            Ok(Some(Value::Array(rows)))
        }
        ([group, id], "purge") => {
            let w = watch_def(ctl, group, id)?;
            let (from, to) = range_arg(args)?;
            let n = purge(ctl, Some(&w.key), from, to).await?;
            ctl.record(
                sub,
                "history_purge",
                &w.key,
                Status::Ok,
                &format!("{} {}: {n} rows", iso_us(from), iso_us(to)),
            );
            refresh_dates(ctl, ctx, group, id, &w.key).await;
            Ok(Some(deleted(n)))
        }
        ([group, id], "unsubscribe" | "unsubscribe_purge") => {
            let w = watch_def(ctl, group, id)?;
            ctl.apply(Op::RemoveWatch {
                group: (*group).to_owned(),
                id: (*id).to_owned(),
            })
            .map_err(rejected)?;
            apply_groups(ctl);
            let n = if action == "unsubscribe_purge" {
                purge(ctl, Some(&w.key), 0, u64::MAX).await?
            } else {
                0
            };
            ctl.record(
                sub,
                "history_watch",
                group,
                Status::Ok,
                &format!("remove {}; {n} rows purged", w.key),
            );
            ctx.remove_node(&format!("{ROOT}/{group}/{id}")).await?;
            Ok((action == "unsubscribe_purge").then(|| deleted(n)))
        }
        _ => Err(LinkError::not_supported(format!(
            "{ROOT}/{}/~act/{action}",
            rest.join("/")
        ))),
    }
}

/// Rows of `key` in `[from, to]` as table records: `time`, `value` and,
/// for raw rows, `quality`.
pub(crate) async fn query(
    ctl: &Control,
    key: &str,
    from: u64,
    to: u64,
    interval: Option<u64>,
    rollup: Rollup,
    limit: usize,
) -> Result<Vec<Value>> {
    let q = HistoryQuery {
        from,
        to,
        interval,
        rollup,
        limit,
    };
    let out = ctl
        .history
        .query(key, &q)
        .await
        .map_err(|e| LinkError::new(e.status(), e.to_string()))?
        .unwrap_or_default();
    let raw = q.raw();
    Ok(out
        .into_iter()
        .map(|(t, v, q)| {
            let mut m = BTreeMap::new();
            m.insert("time".to_owned(), Value::Str(iso_us(t)));
            m.insert("value".to_owned(), v);
            if raw {
                m.insert("quality".to_owned(), Value::from(q.name()));
            }
            Value::Map(m)
        })
        .collect())
}

/// Every metrics interval: the database values and each watch's last row;
/// every minute: retention and Auto Purge.
pub(crate) async fn watch(ctl: Arc<Control>, ctx: LinkCtx) {
    refresh_all(&ctl, &ctx).await;
    let every = ctl.config().metrics_interval;
    let mut tick = tokio::time::interval(every);
    tick.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
    let c = |n: &std::sync::atomic::AtomicU64| n.load(Ordering::Relaxed);
    let mut prev = (Instant::now(), c(&ctl.history.counters().rows_written));
    let mut last_purge = Instant::now();
    let mut shown: HashMap<String, u64> = HashMap::new();
    loop {
        tick.tick().await;
        let counters = ctl.history.counters();
        let written = c(&counters.rows_written);
        let elapsed = prev.0.elapsed().as_secs_f64().max(0.001);
        let wps = written.saturating_sub(prev.1) as f64 / elapsed;
        prev = (Instant::now(), written);
        let st = ctl.history.store().clone();
        let dir = st.dir().to_owned();
        let Ok((size, days)) =
            tokio::task::spawn_blocking(move || (st.size_bytes(), st.days())).await
        else {
            continue;
        };
        let values = [
            ("rows_written", written as f64),
            ("writes_per_second", (wps * 10.0).round() / 10.0),
            ("rows_pending", c(&counters.pending) as f64),
            ("rows_dropped", c(&counters.dropped) as f64),
            ("last_flush", c(&counters.last_flush_us) as f64 / 1000.0),
            (
                "database_size",
                (size as f64 / 1_048_576.0 * 100.0).round() / 100.0,
            ),
            ("series", ctl.history.store().series_count() as f64),
            ("day_files", days.len() as f64),
        ];
        let t = now_us();
        for (key, v) in values {
            let _ = ctx
                .update(&format!("{ROOT}/{key}"), Value::Float(v), Quality::Good, t)
                .await;
        }
        if let Some(free) = disk_free_mib(&dir) {
            let _ = ctx
                .update(
                    &format!("{ROOT}/space_available"),
                    Value::Float(free.round()),
                    Quality::Good,
                    t,
                )
                .await;
        }
        let oldest = days.first().map_or(Value::Null, |d| {
            Value::Str(wyrm_history::time::day_name(*d))
        });
        let _ = ctx
            .update(&format!("{ROOT}/oldest_day"), oldest, Quality::Good, t)
            .await;
        // each watch: the time of its last row, when it changed
        for (g, def) in ctl.registry().historian.groups {
            for (id, w) in def.watches {
                let Some(r) = ctl.history.last_written(&w.key) else {
                    continue;
                };
                if shown.get(&w.key) == Some(&r.t) {
                    continue;
                }
                shown.insert(w.key.clone(), r.t);
                let p = format!("{ROOT}/{g}/{id}");
                let _ = ctx
                    .update(
                        &format!("{p}/end_date"),
                        Value::Str(iso_us(r.t)),
                        Quality::Good,
                        t,
                    )
                    .await;
            }
        }
        if last_purge.elapsed() >= PURGE_EVERY {
            last_purge = Instant::now();
            if auto_purge(&ctl).await {
                shown.clear();
                refresh_all(&ctl, &ctx).await;
            }
        }
    }
}

/// Retention, then free space: delete the oldest days (never the current
/// one). `true` if a day went.
async fn auto_purge(ctl: &Control) -> bool {
    let h = ctl.registry().historian;
    let st = ctl.history.store().clone();
    let today = (now_us() / US_PER_DAY) as i64;
    let keep_free = h.keep_free_mib as f64;
    let (auto, retention) = (h.auto_purge, i64::from(h.retention_days));
    let dropped = tokio::task::spawn_blocking(move || {
        let mut dropped = Vec::new();
        loop {
            let Some(oldest) = st.days().first().copied() else {
                break;
            };
            if oldest >= today {
                break;
            }
            let old = retention > 0 && oldest < today - retention;
            let full = auto && disk_free_mib(st.dir()).is_some_and(|f| f < keep_free);
            if !old && !full {
                break;
            }
            match st.drop_oldest_day() {
                Ok(Some((day, rows))) => dropped.push((day, rows, old)),
                Ok(None) => break,
                Err(e) => {
                    warn!("history purge: {e}");
                    break;
                }
            }
        }
        dropped
    })
    .await
    .unwrap_or_default();
    for (day, rows, old) in &dropped {
        let why = if *old {
            "older than retention_days"
        } else {
            "disk free below disk_space_remaining"
        };
        info!(
            day = %wyrm_history::time::day_name(*day),
            rows, "history: day deleted ({why})"
        );
        ctl.record(
            "broker",
            "history_purge",
            ROOT,
            Status::Ok,
            &format!(
                "day {} ({rows} rows): {why}",
                wyrm_history::time::day_name(*day)
            ),
        );
    }
    if !dropped.is_empty() {
        for g in groups(&ctl.registry()) {
            for w in g.watches {
                ctl.history.forget(&w.key);
            }
        }
    }
    !dropped.is_empty()
}
