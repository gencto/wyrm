//! `sys/history`: the embedded historian's nodes (ADR 0014), as DSA's etsdb
//! link: database values and purge settings, watch groups with their logging
//! type, and watches with Get History, Purge and Unsubscribe.
//!
//! The settings live in the registry (`Registry::historian`); the rows in
//! `data_dir/history` ([`wyrm_history::Store`]).

use crate::control::{disk_free_mib, rejected, Control};
use crate::registry::{check_watch_key, Op, Registry, WatchDef, WatchGroupDef, FLUSH_MS};
use std::collections::{BTreeMap, HashMap, HashSet};
use std::sync::atomic::Ordering;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tracing::{info, warn};
use wyrm_core::meta::{ActionResult, Writable, GROUP_EDIT, GROUP_NEW};
use wyrm_core::{ActionMeta, NodeMeta, Perm, Quality, Status, TypeCode, Value};
use wyrm_history::time::{iso_us, parse_interval, parse_range, US_PER_DAY};
use wyrm_history::{GroupCfg, HistoryRead, Logging, Rollup, WatchCfg};
use wyrm_link_sdk::{now_us, Args, LinkCtx, LinkError};

mod sinks;
pub use sinks::sink_key;
use sinks::SINKS;

type Result<T> = wyrm_link_sdk::Result<T>;

const ROOT: &str = "history";
/// Rows of one Get History: by default and at most.
const DEFAULT_ROWS: usize = 1000;
const MAX_ROWS: usize = 10_000;
/// How often retention and free space are checked.
const PURGE_EVERY: Duration = Duration::from_secs(60);

/// Database values: key, unit, description.
const DB_VALUES: [(&str, &str, &str); 9] = [
    ("rows_written", "", "Rows written since the broker started."),
    (
        "writes_per_second",
        "rows/s",
        "Rows written per second over the metrics interval.",
    ),
    (
        "rows_pending",
        "",
        "Rows in memory waiting for the next flush.",
    ),
    (
        "rows_dropped",
        "",
        "Rows lost since the broker started: a full buffer or a failed write.",
    ),
    ("last_flush", "ms", "Time of the last write to disk."),
    (
        "database_size",
        "MiB",
        "Size of data_dir/history: one file per day (UTC) and the index.",
    ),
    (
        "space_available",
        "MiB",
        "Free space on the file system of data_dir/history.",
    ),
    ("series", "", "Points that were ever recorded."),
    ("day_files", "", "Day files on disk (one per UTC day)."),
];

/// Writable settings: key, type, unit, description.
const OPTIONS: [(&str, TypeCode, &str, &str); 3] = [
    (
        "auto_purge",
        TypeCode::Bool,
        "",
        "Delete the oldest day while the disk has less free space than \
         Disk Space Remaining (never the current day).",
    ),
    (
        "disk_space_remaining",
        TypeCode::Number,
        "MiB",
        "Free space Auto Purge keeps on the disk of data_dir/history.",
    ),
    (
        "retention_days",
        TypeCode::Number,
        "d",
        "Delete days older than this; 0 keeps every day.",
    ),
];

const KEEP_AFTER_SYNC: &str = "keep_after_sync_days";

/// Node names under `history` that a group cannot take.
fn reserved(name: &str) -> bool {
    DB_VALUES.iter().any(|v| v.0 == name)
        || OPTIONS.iter().any(|o| o.0 == name)
        || ["oldest_day", KEEP_AFTER_SYNC, SINKS].contains(&name)
}

fn keep_after_sync_value(days: Option<u32>) -> Value {
    days.map_or(Value::Null, |d| Value::UInt(d.into()))
}

/// The engine settings of the registry's watch groups.
pub fn groups(reg: &Registry) -> Vec<GroupCfg> {
    reg.historian
        .groups
        .iter()
        .map(|(name, g)| GroupCfg {
            name: name.clone(),
            logging: Logging::try_from(g.logging).ok().unwrap_or(Logging::None),
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

/// Choices of Get History's interval (any `<n>s|m|h|d|w` is accepted).
const GET_HISTORY_INTERVALS: [&str; 19] = [
    "none", "1s", "5s", "10s", "15s", "30s", "1m", "5m", "10m", "15m", "30m", "1h", "2h", "3h",
    "4h", "6h", "12h", "1d", "1w",
];

const LOGGING_ABOUT: &str = "None: record nothing. Interval: the last value every Interval. \
     All Data: every update. Point Change: updates whose value or quality changed.";
const INTERVAL_ABOUT: &str = "Seconds between two rows of Interval logging (0.1 s to 1 day).";
const FLUSH_ABOUT: &str = "Seconds between writes to disk (0 = 0.1 s, at most 10 min); \
     rows wait in memory until then.";

/// How a watch group records: `add_watch_group` and a group's `edit`.
#[derive(Args, Debug)]
struct GroupSettings {
    /// By the name the parameter lists (`All Data`).
    #[param(choice, trim, nonempty, display = "Logging type", desc = LOGGING_ABOUT)]
    logging_type: Option<Logging>,
    #[param(
        display = "Interval",
        desc = INTERVAL_ABOUT,
        editor = "duration",
        min = 0.0
    )]
    interval: Option<f64>,
    #[param(
        display = "Buffer flush time",
        desc = FLUSH_ABOUT,
        editor = "duration",
        min = 0.0
    )]
    buffer_flush_time: Option<f64>,
}

/// `history ▸ add_watch_group`.
#[derive(Args)]
struct AddWatchGroup {
    #[param(display = "Name", trim, nonempty)]
    name: String,
    #[param(flatten)]
    settings: GroupSettings,
}

/// A span of time: `purge`, and `get_history` with what it returns.
#[derive(Args, Debug)]
struct TimeRange {
    #[param(
        display = "Timerange",
        placeholder = "2026-10-22T00:00:00Z/2026-10-23T00:00:00Z",
        editor = "daterange",
        desc = "From/to in RFC 3339 (a date is its midnight UTC); an empty end is now.",
        trim,
        nonempty
    )]
    timerange: String,
}

impl TimeRange {
    /// `(from, to)` in µs.
    fn us(&self) -> Result<(u64, u64)> {
        let r = self.timerange.as_str();
        parse_range(r, now_us()).ok_or_else(|| {
            LinkError::invalid_parameter(format!(
                "timerange {:?}: <from>/<to> in RFC 3339, from before to",
                wyrm_core::named::shown(r)
            ))
        })
    }
}

/// `history/<group> ▸ add_watch_path`.
#[derive(Args)]
struct AddWatchPath {
    #[param(
        display = "Path",
        placeholder = "downstream/<link>/<point>",
        desc = "A point of this site (downstream/…, dataflows/… or storage/…, or the full wy/<site>/… key) \
                or of a site below (wy/<site>/…, or its path in the tree as Copy Path gives it).",
        trim,
        nonempty
    )]
    path: String,
}

/// `history/<group> ▸ remove`.
#[derive(Args)]
struct RemoveGroup {
    #[param(
        display = "Purge",
        desc = "Also delete the recorded rows of its watches.",
        absent = false
    )]
    purge: bool,
}

/// `history/<group>/<watch> ▸ get_history`.
#[derive(Args, Debug)]
struct GetHistory {
    #[param(flatten)]
    range: TimeRange,
    /// The intervals a DSA client offers, in this API's units; any
    /// `<n>s|m|h|d|w` is taken.
    #[param(
        suggest = GET_HISTORY_INTERVALS,
        display = "Interval",
        desc = "none: every row; else one row per interval.",
        trim,
        nonempty
    )]
    interval: Option<String>,
    #[param(
        choice,
        trim,
        nonempty,
        display = "Rollup",
        desc = "How the samples of one interval become one value (none: the first)."
    )]
    rollup: Option<Rollup>,
    #[param(
        display = "Rows",
        placeholder = format!("{DEFAULT_ROWS} (at most {MAX_ROWS})")
    )]
    limit: Option<u64>,
}

impl GetHistory {
    /// Rows asked for: at least 1 (0 or absent is the default), at most [`MAX_ROWS`].
    fn rows(&self) -> usize {
        match self.limit {
            None | Some(0) => DEFAULT_ROWS,
            Some(n) => usize::try_from(n).map_or(MAX_ROWS, |n| n.min(MAX_ROWS)),
        }
    }
}

/// Seconds → ms; `None` keeps `current`.
fn ms_of(name: &str, seconds: Option<f64>, current: u64) -> Result<u64> {
    match seconds {
        None => Ok(current),
        Some(s) => wyrm_core::value::whole((s * 1000.0).round())
            .ok()
            .and_then(|ms| u64::try_from(ms).ok())
            .ok_or_else(|| LinkError::invalid_parameter(format!("{name}: seconds"))),
    }
}

/// The settings form of a group: `current` shows what is in force.
fn group_settings(a: ActionMeta, current: Option<(Logging, u64, u64)>) -> ActionMeta {
    let seconds = |ms: u64| format!("{}", ms as f64 / 1000.0);
    match current {
        None => a
            .shown("interval", |p| p.placeholder("60"))
            .shown("buffer_flush_time", |p| p.placeholder("5")),
        Some((logging, interval_ms, flush_ms)) => a
            .shown("logging_type", |p| p.placeholder(logging.name()))
            .shown("interval", |p| p.placeholder(seconds(interval_ms)))
            .shown("buffer_flush_time", |p| p.placeholder(seconds(flush_ms))),
    }
}

/// `sys/history` and everything under it.
pub(crate) async fn declare(ctx: &LinkCtx, ctl: &Control) -> Result<()> {
    ctx.declare_node(
        ROOT,
        // the key, lowercase, as the other folders of sys
        NodeMeta::folder().attr(
            "description",
            "The embedded historian: watch groups record points into data_dir/history.",
        ),
    )
    .await?;
    for (key, unit, about) in DB_VALUES {
        let mut m = NodeMeta::number().attr("description", about);
        if !unit.is_empty() {
            m = m.unit(unit);
        }
        ctx.declare_node(&format!("{ROOT}/{key}"), m).await?;
    }
    ctx.declare_node(
        &format!("{ROOT}/oldest_day"),
        NodeMeta::leaf(TypeCode::String).attr("description", "The oldest day on disk (UTC)."),
    )
    .await?;
    let h = ctl.registry().historian;
    let current = [
        Value::Bool(h.auto_purge),
        Value::UInt(h.keep_free_mib),
        Value::UInt(h.retention_days.into()),
    ];
    for ((key, ty, unit, about), v) in OPTIONS.into_iter().zip(current) {
        let mut m = NodeMeta::leaf(ty)
            .writable(Writable::Config)
            .attr("description", about);
        if !unit.is_empty() {
            m = m.unit(unit);
        }
        let path = format!("{ROOT}/{key}");
        ctx.declare_node(&path, m).await?;
        ctx.update(&path, v, Quality::Good, now_us()).await?;
    }
    let path = format!("{ROOT}/{KEEP_AFTER_SYNC}");
    ctx.declare_node(
        &path,
        NodeMeta::number()
            .writable(Writable::Config)
            .unit("d")
            .attr(
                "description",
                "With sinks: delete a day once every sink confirmed it and it is older than this; \
                 0 keeps only what is not sent; empty: no such rule (ADR 0026).",
            ),
    )
    .await?;
    ctx.update(
        &path,
        keep_after_sync_value(h.keep_after_sync_days),
        Quality::Good,
        now_us(),
    )
    .await?;
    ctx.declare_action(
        ROOT,
        "add_watch_group",
        group_settings(AddWatchGroup::action(), None)
            .display("Add watch group")
            .group(GROUP_NEW)
            .level(Perm::Config),
    )
    .await?;
    ctx.declare_action(
        ROOT,
        "purge",
        TimeRange::action()
            .display("Purge")
            .group(GROUP_EDIT)
            .result(ActionResult::Type(TypeCode::Map))
            .level(Perm::Config),
    )
    .await?;
    for (name, g) in &h.groups {
        declare_group(ctx, name, g).await?;
    }
    sinks::declare(ctx, ctl).await
}

async fn declare_group(ctx: &LinkCtx, name: &str, g: &WatchGroupDef) -> Result<()> {
    let p = format!("{ROOT}/{name}");
    ctx.declare_node(&p, NodeMeta::folder()).await?;
    group_values(ctx, name, g).await?;
    ctx.declare_action(
        &p,
        "add_watch_path",
        AddWatchPath::action()
            .display("Add watch path")
            .group(GROUP_NEW)
            .level(Perm::Config),
    )
    .await?;
    ctx.declare_action(
        &p,
        "remove",
        RemoveGroup::action()
            .display("Delete")
            .group(GROUP_EDIT)
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
    let logging = Logging::try_from(g.logging).ok().unwrap_or(Logging::None);
    let t = now_us();
    ctx.declare_node(
        &format!("{p}/logging_type"),
        NodeMeta::leaf(TypeCode::String),
    )
    .await?;
    ctx.update(
        &format!("{p}/logging_type"),
        Value::from(logging.name()),
        Quality::Good,
        t,
    )
    .await?;
    for (key, ms) in [
        ("interval", g.interval_ms),
        ("buffer_flush_time", g.flush_ms),
    ] {
        let k = format!("{p}/{key}");
        ctx.declare_node(&k, NodeMeta::number().unit("s")).await?;
        ctx.update(&k, Value::Float(ms as f64 / 1000.0), Quality::Good, t)
            .await?;
    }
    ctx.declare_action(
        &p,
        "edit",
        group_settings(
            GroupSettings::action(),
            Some((logging, g.interval_ms, g.flush_ms)),
        )
        .display("Edit")
        .group(GROUP_EDIT)
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
        NodeMeta::leaf(TypeCode::Bool).writable(Writable::Config),
    )
    .await?;
    ctx.update(
        &format!("{p}/enabled"),
        Value::Bool(w.enabled),
        Quality::Good,
        now_us(),
    )
    .await?;
    for key in ["start_date", "end_date"] {
        ctx.declare_node(&format!("{p}/{key}"), NodeMeta::leaf(TypeCode::String))
            .await?;
    }
    // No "Last Written Value" (DSA has one): sys would publish point values
    // to everyone who may read sys, not only to who may read the point.
    ctx.declare_action(
        &p,
        "get_history",
        GetHistory::action()
            .display("Get history")
            .result(ActionResult::Type(TypeCode::Array))
            // Config, as all of sys/history: the rows are point values, and
            // a role with read on sys has no read on the points (ADR 0014).
            .level(Perm::Config),
    )
    .await?;
    ctx.declare_action(
        &p,
        "purge",
        TimeRange::action()
            .display("Purge")
            .group(GROUP_EDIT)
            .result(ActionResult::Type(TypeCode::Map))
            .level(Perm::Config),
    )
    .await?;
    ctx.declare_action(
        &p,
        "unsubscribe",
        <()>::action()
            .display("Unsubscribe")
            .group(GROUP_EDIT)
            .level(Perm::Config),
    )
    .await?;
    ctx.declare_action(
        &p,
        "unsubscribe_purge",
        <()>::action()
            .display("Unsubscribe and purge")
            .group(GROUP_EDIT)
            .result(ActionResult::Type(TypeCode::Map))
            .level(Perm::Config),
    )
    .await
}

/// Start and end date of a watch from the store (first and last row).
/// `true` when the store holds a first row (`start_date` is known).
async fn refresh_dates(ctl: &Control, ctx: &LinkCtx, group: &str, id: &str, key: &str) -> bool {
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
            return false;
        }
        Err(_) => return false,
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
    first.is_some()
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

/// A watch path as typed (`downstream/…`, `/downstream/…`, `wy/<site>/…`) → its full
/// key; only this site and downstream sites.
fn watch_key(ctl: &Control, path: &str) -> Result<String> {
    let path = path.trim().trim_matches('/');
    let site = &ctl.config().site;
    let key = if ["downstream/", "dataflows/", "storage/"]
        .iter()
        .any(|s| path.starts_with(s))
    {
        format!("wy/{site}/{path}")
    } else {
        path.to_owned()
    };
    // a route copied from an explorer's tree (through peer brokers) is the
    // key of the site it ends in
    let below = ctl.peers().reachable();
    let key = wyrm_core::keyspace::route_key(&key, |s| below.iter().any(|d| d == s));
    check_watch_key(&key).map_err(LinkError::invalid_parameter)?;
    let s = key.split('/').nth(1).unwrap_or_default();
    if s != site && !below.iter().any(|d| d == s) {
        return Err(LinkError::invalid_parameter(format!(
            "{key}: site {s} is neither this site nor one below it"
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
            keep = value.to_int::<u64>().map_err(|e| {
                LinkError::invalid_parameter(format!("disk_space_remaining: {e}, whole MiB"))
            })?
        }
        ["retention_days"] => {
            days = value
                .to_int::<u32>()
                .ok()
                .filter(|d| *d <= 36_500)
                .ok_or_else(|| LinkError::invalid_parameter("retention_days: 0 to 36500"))?
        }
        [KEEP_AFTER_SYNC] => {
            let days =
                match value {
                    Value::Null => None,
                    Value::Str(s) if s.trim().is_empty() => None,
                    v => Some(v.to_int::<u32>().ok().filter(|d| *d <= 36_500).ok_or_else(
                        || {
                            LinkError::invalid_parameter(
                                "keep_after_sync_days: 0 to 36500, or empty",
                            )
                        },
                    )?),
                };
            ctl.apply(Op::SetKeepAfterSync(days)).map_err(rejected)?;
            ctl.record(
                sub,
                "history_options",
                ROOT,
                Status::Ok,
                &format!("keep_after_sync_days {days:?}"),
            );
            return ctx
                .update(
                    &format!("{ROOT}/{KEEP_AFTER_SYNC}"),
                    keep_after_sync_value(days),
                    Quality::Good,
                    now_us(),
                )
                .await;
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
    args: Value,
    sub: &str,
) -> Result<Option<Value>> {
    match (rest, action) {
        ([SINKS, rest @ ..], _) => sinks::invoke(ctl, ctx, rest, action, args, sub).await,
        ([], "add_watch_group") => {
            let a = AddWatchGroup::decode(args)?;
            let (name, set) = (a.name.as_str(), a.settings);
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
            let logging = set.logging_type.unwrap_or(Logging::AllData);
            ctl.apply(Op::PutWatchGroup {
                name: name.to_owned(),
                logging: logging.code(),
                interval_ms: ms_of("interval", set.interval, 60_000)?,
                // 0 = as soon as possible (DSA): the shortest flush
                flush_ms: ms_of("buffer_flush_time", set.buffer_flush_time, 5_000)?
                    .max(*FLUSH_MS.start()),
            })
            .map_err(rejected)?;
            ctl.record(sub, "history_group", name, Status::Ok, logging.name());
            let g = ctl.registry().historian.groups[name].clone();
            declare_group(ctx, name, &g).await?;
            apply_groups(ctl);
            Ok(None)
        }
        ([], "purge") => {
            let (from, to) = TimeRange::decode(args)?.us()?;
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
            // the group must exist before its arguments are read
            let g = ctl
                .registry()
                .historian
                .groups
                .get(*group)
                .cloned()
                .ok_or_else(|| LinkError::not_found(format!("watch group {group}")))?;
            let set = GroupSettings::decode(args)?;
            let logging = set
                .logging_type
                .or(Logging::try_from(g.logging).ok())
                .unwrap_or(Logging::None);
            ctl.apply(Op::PutWatchGroup {
                name: (*group).to_owned(),
                logging: logging.code(),
                interval_ms: ms_of("interval", set.interval, g.interval_ms)?,
                flush_ms: ms_of("buffer_flush_time", set.buffer_flush_time, g.flush_ms)?
                    .max(*FLUSH_MS.start()),
            })
            .map_err(rejected)?;
            ctl.record(sub, "history_group", group, Status::Ok, logging.name());
            let g = ctl.registry().historian.groups[*group].clone();
            group_values(ctx, group, &g).await?;
            apply_groups(ctl);
            Ok(None)
        }
        ([group], "add_watch_path") => {
            // the group first, whatever the arguments are
            if !ctl.registry().historian.groups.contains_key(*group) {
                return Err(LinkError::not_found(format!("watch group {group}")));
            }
            let a = AddWatchPath::decode(args)?;
            let key = watch_key(ctl, &a.path)?;
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
            crate::control::publish_overlays(ctx, ctl).await?;
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
            let a = RemoveGroup::decode(args)?;
            ctl.apply(Op::RemoveWatchGroup((*group).to_owned()))
                .map_err(rejected)?;
            apply_groups(ctl);
            crate::control::publish_overlays(ctx, ctl).await?;
            let mut n = 0;
            if a.purge {
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
            // the watch must exist before its arguments are read
            let w = watch_def(ctl, group, id)?;
            let a = GetHistory::decode(args)?;
            let (from, to) = a.range.us()?;
            let interval = parse_interval(a.interval.as_deref().unwrap_or("none"))
                .map_err(LinkError::invalid_parameter)?;
            let rollup = a.rollup.unwrap_or(Rollup::None);
            let limit = a.rows();
            let rows = query(ctl, &w.key, from, to, interval, rollup, limit).await?;
            Ok(Some(Value::Array(rows)))
        }
        ([group, id], "purge") => {
            let w = watch_def(ctl, group, id)?;
            let range = TimeRange::decode(args)?;
            let (from, to) = range.us()?;
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
            <()>::decode(args)?;
            ctl.apply(Op::RemoveWatch {
                group: (*group).to_owned(),
                id: (*id).to_owned(),
            })
            .map_err(rejected)?;
            apply_groups(ctl);
            crate::control::publish_overlays(ctx, ctl).await?;
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
    let q = HistoryRead {
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
    // watches whose first row is shown; a new one has none until the store
    // gets its first flush
    let mut dated: HashSet<String> = HashSet::new();
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
                if !dated.contains(&w.key) && refresh_dates(&ctl, &ctx, &g, &id, &w.key).await {
                    dated.insert(w.key.clone());
                }
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
        sinks::refresh(&ctx, &ctl).await;
        if last_purge.elapsed() >= PURGE_EVERY {
            last_purge = Instant::now();
            if auto_purge(&ctl).await {
                shown.clear();
                refresh_all(&ctl, &ctx).await;
            }
        }
    }
}

/// Why [`auto_purge`] deleted a day.
#[derive(Debug, Clone, Copy, PartialEq)]
enum Why {
    Retention,
    Disk,
    Synced,
}

/// What the purge rules say of the oldest day, `oldest`: retention first,
/// then free space, then the synced rule (`keep_synced` days, a day whose
/// whole journal `day_seq` every sink confirmed: `synced_upto` is the
/// slowest sink's cursor). Never the current day; a day with no journal
/// (written before ADR 0026) is never synced.
fn purge_reason(
    oldest: i64,
    today: i64,
    retention: i64,
    disk_low: bool,
    keep_synced: Option<u32>,
    day_seq: Option<(u64, u64)>,
    synced_upto: Option<u64>,
) -> Option<Why> {
    if oldest >= today {
        None
    } else if retention > 0 && oldest < today - retention {
        Some(Why::Retention)
    } else if disk_low {
        Some(Why::Disk)
    } else if keep_synced.is_some_and(|k| oldest < today - i64::from(k))
        && day_seq
            .zip(synced_upto)
            .is_some_and(|((_, hi), upto)| hi <= upto)
    {
        Some(Why::Synced)
    } else {
        None
    }
}

/// Retention, then free space, then days every sink confirmed (ADR 0026):
/// delete the oldest days (never the current one). Retention and free
/// space never wait for a sink (owner decision 1): the rows of a sink's
/// groups it had not confirmed are counted as dropped. `true` if a day went.
async fn auto_purge(ctl: &Control) -> bool {
    let h = ctl.registry().historian;
    let st = ctl.history.store().clone();
    let today = (now_us() / US_PER_DAY) as i64;
    let keep_free = h.keep_free_mib as f64;
    let (auto, retention) = (h.auto_purge, i64::from(h.retention_days));
    let cursors = sinks::cursors(ctl);
    // the synced rule needs a sink, and counts the slowest one
    let synced_upto = cursors.iter().map(|c| c.1).min();
    let keep_synced = h.keep_after_sync_days.filter(|_| synced_upto.is_some());
    let (dropped, unsent) = tokio::task::spawn_blocking(move || {
        let mut dropped = Vec::new();
        let mut unsent: HashMap<String, u64> = HashMap::new();
        while let Some(oldest) = st.days().first().copied() {
            let disk_low = auto && disk_free_mib(st.dir()).is_some_and(|f| f < keep_free);
            let Some(why) = purge_reason(
                oldest,
                today,
                retention,
                disk_low,
                keep_synced,
                st.day_seq(oldest),
                synced_upto,
            ) else {
                break;
            };
            if !matches!(why, Why::Synced) {
                for (name, after, series) in &cursors {
                    match st.count_changes(oldest, *after, |s| series.contains(&s)) {
                        Ok(0) => {}
                        Ok(n) => *unsent.entry(name.clone()).or_default() += n,
                        Err(e) => warn!(sink = %name, "history purge: {e}"),
                    }
                }
            }
            match st.drop_oldest_day() {
                Ok(Some((day, rows))) => dropped.push((day, rows, why)),
                Ok(None) => break,
                Err(e) => {
                    warn!("history purge: {e}");
                    break;
                }
            }
        }
        (dropped, unsent)
    })
    .await
    .unwrap_or_default();
    for (name, n) in unsent {
        warn!(sink = %name, rows = n, "history: rows deleted before the sink confirmed them");
        ctl.history.sink_stats(&name, |s| s.dropped_unsent += n);
    }
    for (day, rows, why) in &dropped {
        let why = match why {
            Why::Retention => "older than retention_days",
            Why::Disk => "disk free below disk_space_remaining",
            Why::Synced => "every sink confirmed it, older than keep_after_sync_days",
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

#[cfg(test)]
mod tests {
    use super::*;

    /// Typing audit T6 and T3: the logging type was taken by its internal name, its
    /// display name or its index. The parameter is a text that lists the names
    /// (`All Data`): that name is the one form taken.
    #[test]
    fn a_logging_type_is_taken_by_the_one_name_it_lists() {
        let logging = |v: Value| {
            GroupSettings::decode(Value::Map(BTreeMap::from([("logging_type".to_owned(), v)])))
                .map(|s| s.logging_type)
        };
        for l in Logging::ALL {
            assert_eq!(logging(Value::from(l.name())), Ok(Some(*l)));
        }
        assert_eq!(logging(Value::from("")), Ok(None), "an empty field");
        assert_eq!(
            logging(Value::from(" All Data ")),
            Ok(Some(Logging::AllData)),
            "white space around the name is cut, as before"
        );
        assert_eq!(
            GroupSettings::action().params["logging_type"]
                .enum_values
                .as_deref()
                .map(<[String]>::len),
            Some(4)
        );
        for other in ["all_data", "point_change", "none", "ALL DATA", "Every"] {
            let e = logging(Value::from(other)).unwrap_err();
            assert_eq!(e.field, "logging_type", "{other}");
        }
        // the declared type is text: an index is not a name
        assert_eq!(logging(Value::UInt(2)).unwrap_err().field, "logging_type");
    }

    fn args(kv: &[(&str, Value)]) -> Value {
        Value::Map(
            kv.iter()
                .map(|(k, v)| ((*k).to_owned(), v.clone()))
                .collect(),
        )
    }

    /// Typing audit T3: a group's times are numbers of seconds. A text was read as
    /// "not given" (the value in force stayed, silently), and a negative one refused
    /// only after the group's name was checked.
    #[test]
    fn group_times_are_seconds_or_refused() {
        let set = |kv: &[(&str, Value)]| GroupSettings::decode(args(kv));
        let s = set(&[
            ("interval", Value::Float(0.5)),
            ("buffer_flush_time", Value::UInt(2)),
        ])
        .unwrap();
        assert_eq!(ms_of("interval", s.interval, 60_000), Ok(500));
        assert_eq!(
            ms_of("buffer_flush_time", s.buffer_flush_time, 5_000),
            Ok(2_000)
        );
        assert_eq!(ms_of("interval", None, 60_000), Ok(60_000));
        for (field, bad) in [
            ("interval", Value::from("60")),
            ("interval", Value::Float(-1.0)),
            ("interval", Value::Float(f64::NAN)),
            ("buffer_flush_time", Value::Bool(true)),
            ("flush", Value::UInt(1)),
        ] {
            assert_eq!(
                set(&[(field, bad.clone())]).unwrap_err().field,
                field,
                "{bad:?}"
            );
        }
    }

    /// Typing audit T3: `get_history` reads what it declares. A rollup is a name of
    /// the list (an index was taken too, a form the declared text type never had).
    #[test]
    fn get_history_reads_what_it_declares() {
        let range = ("timerange", Value::from("2026-10-22/2026-10-23"));
        let get = |kv: &[(&str, Value)]| {
            let mut all = vec![range.clone()];
            all.extend(kv.iter().cloned());
            GetHistory::decode(args(&all))
        };
        let a = get(&[]).unwrap();
        assert_eq!((a.rollup, a.rows()), (None, DEFAULT_ROWS));
        assert!(a.range.us().is_ok());
        let a = get(&[
            ("rollup", Value::from("avg")),
            ("interval", Value::from(" 7m ")),
            ("limit", Value::UInt(u64::MAX)),
        ])
        .unwrap();
        assert_eq!(a.rollup, Some(Rollup::Avg));
        assert_eq!(
            a.interval.as_deref(),
            Some("7m"),
            "any interval, not only the listed"
        );
        assert_eq!(a.rows(), MAX_ROWS);
        assert_eq!(
            get(&[("limit", Value::UInt(0))]).unwrap().rows(),
            DEFAULT_ROWS
        );
        assert_eq!(get(&[("rollup", Value::from(""))]).unwrap().rollup, None);
        // white space around a name is cut, as before (audit of #136)
        assert_eq!(
            get(&[("rollup", Value::from(" max "))]).unwrap().rollup,
            Some(Rollup::Max)
        );
        assert_eq!(get(&[("rollup", Value::from("  "))]).unwrap().rollup, None);
        for (field, bad) in [
            ("rollup", Value::UInt(3)),
            ("rollup", Value::from("mean")),
            ("limit", Value::Float(1.5)),
            ("limit", Value::Int(-1)),
            ("interval", Value::UInt(60)),
        ] {
            assert_eq!(
                get(&[(field, bad.clone())]).unwrap_err().field,
                field,
                "{bad:?}"
            );
        }
        assert_eq!(
            GetHistory::decode(args(&[])).unwrap_err().field,
            "timerange"
        );
        assert_eq!(
            TimeRange::decode(args(&[("timerange", Value::from("  "))]))
                .unwrap_err()
                .field,
            "timerange"
        );
    }

    #[test]
    fn purge_rules_in_order() {
        let r = |oldest, retention, disk_low, keep, seq, upto| {
            purge_reason(oldest, 1000, retention, disk_low, keep, seq, upto)
        };
        let synced = Some((10, 20));
        // never the current day
        assert_eq!(r(1000, 1, true, Some(0), synced, Some(99)), None);
        // retention first, sent or not
        assert_eq!(
            r(800, 100, false, None, synced, Some(0)),
            Some(Why::Retention)
        );
        assert_eq!(r(950, 100, false, None, synced, None), None);
        // free space, sent or not (owner decision 1)
        assert_eq!(r(950, 0, true, None, synced, Some(0)), Some(Why::Disk));
        // synced: older than keep, every sink past the day's last entry
        assert_eq!(
            r(900, 0, false, Some(90), synced, Some(20)),
            Some(Why::Synced)
        );
        assert_eq!(
            r(900, 0, false, Some(90), synced, Some(19)),
            None,
            "one entry not confirmed"
        );
        assert_eq!(
            r(950, 0, false, Some(90), synced, Some(99)),
            None,
            "younger than keep"
        );
        assert_eq!(
            r(999, 0, false, Some(0), synced, Some(20)),
            Some(Why::Synced),
            "0 keeps only unsent"
        );
        // no sink, no rule, or a day with no journal: kept
        assert_eq!(r(900, 0, false, Some(90), synced, None), None);
        assert_eq!(r(900, 0, false, None, synced, Some(99)), None);
        assert_eq!(r(900, 0, false, Some(90), None, Some(99)), None);
    }
}
