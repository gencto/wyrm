//! Package updates with a way back (ADR 0048 §1).
//!
//! A new version of an installed package is an update, whatever brought it
//! (`sys/packages/<name>/~act/update` from the repository, or `install_zip`
//! / `install_url` / `install_git` / `install_repo` / `install_wasm` with a
//! package that is installed already):
//!
//! 1. the new zip is unpacked and checked beside the old version; nothing
//!    runs it yet;
//! 2. before anything stops, every link of the package gets a restore point
//!    ([`crate::restore`]: its private data and its key list);
//! 3. the old version's directory stays (`PackageDef::previous`, until
//!    `keep_until`), the links start on the new version (an app component by
//!    a hot start), and the action answers;
//! 4. a health check goes on in the background ([`Admin::check_update`]):
//!    every link must answer and declare every key it had. It ends in
//!    `last_update` as `ok`, `rolled_back` or `failed`;
//! 5. `rollback` (by the check, or by hand until `keep_until`) stops the
//!    links, puts the old version and each link's private data back, and
//!    starts them.
//!
//! A rebuild of the router ([`Control::quiesce`]) waits for steps 1–3 as it
//! waits for any install, and for step 5 and the end of step 4 (they hold a
//! [`BusyOwned`]). It does not wait for the polling of step 4: a link may
//! need that very rebuild to come back (a link installed a moment before, a
//! grant the update added), so a check that sees a rebuild waiting steps
//! aside ([`Control::pause_check`]) and goes on with the new router
//! ([`resume`]), with the time it had left.

use super::{
    accepted, arg, arg_str, decode_params, encode_params, install_detail, now_s, outcome, packages,
    rejected, str_param, Admin, BusyOwned, Control, INSTALL_TIMEOUT_MS,
};
use crate::registry::{
    LinkDef, Op, Origin, PackageDef, PackageKind, PreviousDef, UpdateReport, UPDATE_CHECKING,
    UPDATE_FAILED, UPDATE_OK, UPDATE_REPORT_KEYS, UPDATE_ROLLED_BACK,
};
use crate::restore_point as restore;
use std::collections::{BTreeMap, BTreeSet};
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;
use tracing::{debug, warn};
use wyrm_core::meta::{ActionResult, ParamMeta, GROUP_EDIT};
use wyrm_core::{ActionMeta, NodeMeta, Perm, Quality, Status, TypeCode, Value};
use wyrm_link_sdk::package::{Capabilities, RepoEntry};
use wyrm_link_sdk::{now_us, LinkCtx, LinkError};

/// `auto_rollback_s` when the caller names none (ADR 0048 §1.2).
pub const DEFAULT_AUTO_ROLLBACK_S: u32 = 120;
/// The longest health window.
pub const MAX_AUTO_ROLLBACK_S: u32 = 600;
/// With `auto_rollback_s: 0` (keep and report): how long the report waits
/// for every link to answer before it says `failed`.
const REPORT_WAIT_S: u32 = 120;
/// How long the links' keys must stay as they are before the check ends
/// early with a good result.
const SETTLE: Duration = Duration::from_secs(3);
/// The same after a hot start: the nodes the old code declared and the new
/// one did not are swept 10 s after it (`wyrm-link-portable` `SWEEP_AFTER`).
const SETTLE_HOT: Duration = Duration::from_secs(12);
/// One read of a link's key list.
const KEYS_TIMEOUT: Duration = Duration::from_secs(2);
/// How often [`keep`] looks at what is kept.
const KEEP_TICK: Duration = Duration::from_secs(15);
/// The least time a check has after a rebuild of the router: the links say
/// `hello` to the new one first.
const RESUME_MIN: Duration = Duration::from_secs(30);

/// The arguments an update takes beside `accept` (ADR 0048 §1.2); ignored by
/// an install of a package that is not installed yet.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) struct UpdateOpts {
    /// Take a restore point of every link first. Forced when the update
    /// changes the store format: `false` is then refused.
    pub restore_point: bool,
    /// Seconds the links have to come back with every key before the broker
    /// rolls back by itself; 0 keeps the new version and reports.
    pub auto_rollback_s: u32,
}

impl Default for UpdateOpts {
    fn default() -> Self {
        Self {
            restore_point: true,
            auto_rollback_s: DEFAULT_AUTO_ROLLBACK_S,
        }
    }
}

impl UpdateOpts {
    pub fn from_args(args: &Value) -> Result<Self, LinkError> {
        let mut o = Self::default();
        match arg(args, "restore_point") {
            None | Some(Value::Null) => {}
            Some(Value::Bool(b)) => o.restore_point = *b,
            Some(_) => return Err(LinkError::invalid_parameter("restore_point: true or false")),
        }
        match arg(args, "auto_rollback_s") {
            None | Some(Value::Null) => {}
            Some(v) => {
                let n = v.as_f64().filter(|n| {
                    n.fract() == 0.0 && (0.0..=f64::from(MAX_AUTO_ROLLBACK_S)).contains(n)
                });
                o.auto_rollback_s = n.ok_or_else(|| {
                    LinkError::invalid_parameter(format!(
                        "auto_rollback_s: 0 (keep and report) to {MAX_AUTO_ROLLBACK_S}"
                    ))
                })? as u32;
            }
        }
        Ok(o)
    }
}

pub(super) fn restore_point_param() -> ParamMeta {
    ParamMeta::of(TypeCode::Bool)
        .display("Save a restore point")
        .description(
            "An update (the package is installed already): keep each link's private data \
             for a rollback. Default true; false is refused when the new version changes \
             the store format",
        )
}

pub(super) fn auto_rollback_param() -> ParamMeta {
    ParamMeta::of(TypeCode::Number)
        .display("Roll back by itself after (s)")
        .description(format!(
            "An update: the links must come back with every node within this time, else \
             the broker rolls back. Default {DEFAULT_AUTO_ROLLBACK_S}, at most \
             {MAX_AUTO_ROLLBACK_S}; 0 keeps the new version and reports"
        ))
}

fn map(pairs: Vec<(&str, Value)>) -> Value {
    Value::Map(
        pairs
            .into_iter()
            .map(|(k, v)| (k.to_owned(), v))
            .collect::<BTreeMap<_, _>>(),
    )
}

fn strings(v: &[String]) -> Value {
    Value::Array(v.iter().cloned().map(Value::Str).collect())
}

/// `sys/packages/<name>/last_update`.
fn report_value(r: &UpdateReport) -> Value {
    map(vec![
        ("from", Value::Str(r.from.clone())),
        ("to", Value::Str(r.to.clone())),
        ("at", Value::UInt(r.at)),
        ("result", Value::Str(r.result.clone())),
        ("kept", Value::UInt(r.kept.into())),
        ("new", Value::UInt(r.new.into())),
        ("gone", Value::UInt(r.gone.into())),
        ("new_keys", strings(&r.new_keys)),
        ("gone_keys", strings(&r.gone_keys)),
        ("reason", Value::Str(r.reason.clone())),
        ("links", strings(&r.links)),
        ("changes_state", Value::Bool(r.changes_state)),
        ("restore_point", Value::Bool(r.restore_point)),
    ])
}

/// `sys/packages/<name>/previous`: the version kept for a rollback.
fn previous_value(p: &PreviousDef) -> Value {
    map(vec![
        ("version", Value::Str(p.def.version.clone())),
        ("keep_until", Value::UInt(p.keep_until)),
        ("changes_state", Value::Bool(p.changes_state)),
    ])
}

/// The numbers of a version: the part before `-` or `+`, split at `.`.
fn core(v: &str) -> Option<Vec<u64>> {
    let core = v.split(['-', '+']).next().unwrap_or(v);
    core.split('.').map(|s| s.parse::<u64>().ok()).collect()
}

/// Is `latest` a newer version than `installed`? Dotted numbers compare as
/// numbers (`1.10.0` is newer than `1.9.2`); with the same numbers a release
/// is newer than its pre-release (`1.0.0` than `1.0.0-rc1`) and build
/// metadata (`+…`) does not count. Versions that are not dotted numbers are
/// newer when they differ: the repository names one version, and it is the
/// one to offer.
pub(super) fn newer(latest: &str, installed: &str) -> bool {
    if latest == installed {
        return false;
    }
    let (Some(a), Some(b)) = (core(latest), core(installed)) else {
        return true;
    };
    if a != b {
        return a > b;
    }
    let pre = |v: &str| {
        let v = v.split('+').next().unwrap_or(v);
        v.split_once('-').map(|(_, p)| p.to_owned())
    };
    match (pre(latest), pre(installed)) {
        (None, Some(_)) => true,
        (Some(a), Some(b)) => a > b,
        _ => false,
    }
}

/// The repository's entry of package `name` with a build for this host: a
/// package the index does not list is a custom one (no `latest`).
fn index_entry(ctl: &Control, name: &str) -> Option<RepoEntry> {
    let host = packages::platform();
    match &*ctl.repo.lock().unwrap_or_else(|p| p.into_inner()) {
        Some(Ok(list)) => list
            .iter()
            .find(|e| e.name == name && e.asset(&host).is_some())
            .cloned(),
        _ => None,
    }
}

/// `(latest, update_available, changes_state)` of an installed package.
fn update_of(ctl: &Control, p: &PackageDef) -> (String, bool, bool) {
    match index_entry(ctl, &p.name) {
        Some(e) => {
            let available = newer(&e.version, &p.version);
            let changes = available && !e.reads(p.state());
            (e.version, available, changes)
        }
        None => (String::new(), false, false),
    }
}

fn package_driver(name: &str) -> String {
    format!("{}{name}", packages::DRIVER_PREFIX)
}

fn links_of(ctl: &Control, name: &str) -> Vec<LinkDef> {
    let driver = package_driver(name);
    ctl.registry()
        .links
        .values()
        .filter(|l| l.driver == driver)
        .cloned()
        .collect()
}

/// The values of `sys/packages/<name>` (ADR 0048 §1.1).
const PACKAGE_VALUES: [(&str, TypeCode, &str); 7] = [
    ("version", TypeCode::String, "The installed version."),
    (
        "latest",
        TypeCode::String,
        "The version in the repository; empty for a package the repository does not list.",
    ),
    (
        "update_available",
        TypeCode::Bool,
        "The repository has a newer version.",
    ),
    (
        "changes_state",
        TypeCode::Bool,
        "The update to `latest` changes the store format: it takes a restore point.",
    ),
    (
        "state",
        TypeCode::Number,
        "The store format the installed version writes.",
    ),
    (
        "previous",
        TypeCode::Map,
        "The version kept for a rollback: version, keep_until, changes_state.",
    ),
    (
        "last_update",
        TypeCode::Map,
        "The last update or rollback: from, to, at, result, kept, new, gone, new_keys, \
         gone_keys, reason, links.",
    ),
];

/// Publish the values of package `p`, as the registry and the index say now.
async fn publish_package(ctx: &LinkCtx, ctl: &Control, p: &PackageDef) {
    let (latest, available, changes) = update_of(ctl, p);
    let none = || Value::Map(BTreeMap::new());
    let values = [
        ("version", Value::Str(p.version.clone())),
        ("latest", Value::Str(latest)),
        ("update_available", Value::Bool(available)),
        ("changes_state", Value::Bool(changes)),
        ("state", Value::UInt(p.state().into())),
        (
            "previous",
            p.previous.as_deref().map_or_else(none, previous_value),
        ),
        (
            "last_update",
            p.last_update.as_ref().map_or_else(none, report_value),
        ),
    ];
    for (leaf, v) in values {
        let path = format!("packages/{}/{leaf}", p.name);
        if let Err(e) = ctx.update(&path, v, Quality::Good, now_us()).await {
            debug!("{path}: {e}");
        }
    }
}

/// How many links run a package that the repository has a newer version of
/// (`attr.updates_available` of `sys/links`).
pub(super) fn updates_available(ctl: &Control) -> u64 {
    let reg = ctl.registry();
    reg.links
        .values()
        .filter(|l| {
            l.driver
                .strip_prefix(packages::DRIVER_PREFIX)
                .and_then(|name| reg.packages.get(name))
                .is_some_and(|p| update_of(ctl, p).1)
        })
        .count() as u64
}

/// `sys/links` again, with the count as it is now.
pub(super) async fn publish_count(ctx: &LinkCtx, ctl: &Control) {
    if let Err(e) = super::declare_links_node(ctx, ctl).await {
        debug!("sys/links: {e}");
    }
}

/// Every package's values and the count, again (a new index, a change in
/// the registry).
pub(super) async fn publish_all(ctx: &LinkCtx, ctl: &Control) {
    for p in ctl.registry().packages.values() {
        publish_package(ctx, ctl, p).await;
    }
    publish_count(ctx, ctl).await;
}

/// The values of `sys/packages/<name>` and its `update` and `rollback`.
pub(super) async fn declare_values(
    ctx: &LinkCtx,
    ctl: &Control,
    p: &PackageDef,
) -> wyrm_link_sdk::Result<()> {
    let node = format!("packages/{}", p.name);
    for (leaf, ty, what) in PACKAGE_VALUES {
        ctx.declare_node(
            &format!("{node}/{leaf}"),
            NodeMeta::leaf(ty).attr("description", what),
        )
        .await?;
    }
    ctx.declare_action(
        &node,
        "update",
        ActionMeta::new()
            .display("Update")
            .group(GROUP_EDIT)
            .result(ActionResult::Type(TypeCode::Map))
            .timeout_ms(INSTALL_TIMEOUT_MS)
            .level(Perm::Config)
            .param(
                "version",
                str_param()
                    .display("Version")
                    .description("Default: the repository's (`latest`)"),
            )
            .param(
                "accept",
                ParamMeta::of(TypeCode::Bool)
                    .display("Accept requested rights")
                    .description(
                        "Network entries and grants the new version asks for beyond what \
                         the links have: an update without this shows them and changes nothing",
                    ),
            )
            .param("restore_point", restore_point_param())
            .param("auto_rollback_s", auto_rollback_param()),
    )
    .await?;
    ctx.declare_action(
        &node,
        "rollback",
        ActionMeta::new()
            .display("Roll back")
            .group(GROUP_EDIT)
            .result(ActionResult::Type(TypeCode::Map))
            .timeout_ms(INSTALL_TIMEOUT_MS)
            .level(Perm::Config)
            .param(
                "to",
                str_param()
                    .display("Version")
                    .description("Default: the kept version (`previous`)"),
            ),
    )
    .await?;
    publish_package(ctx, ctl, p).await;
    publish_count(ctx, ctl).await;
    Ok(())
}

/// `sys/links/<id>/restore_points`: `[{at, version, size}]`, newest first.
async fn publish_restore_points(ctx: &LinkCtx, ctl: &Control, id: &str) {
    let rows = restore::list(&ctl.restore_root(), id)
        .into_iter()
        .rev()
        .map(|p| {
            map(vec![
                ("at", Value::UInt(p.at)),
                ("version", Value::Str(p.version)),
                ("size", Value::UInt(p.size)),
            ])
        })
        .collect();
    let path = format!("links/{id}/restore_points");
    if let Err(e) = ctx
        .update(&path, Value::Array(rows), Quality::Good, now_us())
        .await
    {
        debug!("{path}: {e}");
    }
}

pub(super) async fn declare_restore_points(
    ctx: &LinkCtx,
    ctl: &Control,
    id: &str,
) -> wyrm_link_sdk::Result<()> {
    ctx.declare_node(
        &format!("links/{id}/restore_points"),
        NodeMeta::leaf(TypeCode::Array).attr(
            "description",
            "Restore points of the link's private data, newest first: at, version, size.",
        ),
    )
    .await?;
    publish_restore_points(ctx, ctl, id).await;
    Ok(())
}

impl Control {
    /// Where restore points are kept: `data_dir/restore/<link>/`.
    pub fn restore_root(&self) -> PathBuf {
        self.cfg.data_dir.join("restore")
    }

    /// Take a restore point of `link` now (ADR 0048 §1.3, §3.5): a link
    /// backup without history and without the package, sealed for this
    /// broker, with the link's key list `keys` beside it. The link keeps
    /// running. Blocking: call it off the async runtime.
    pub(super) fn restore_point_now(
        &self,
        link: &str,
        package: &str,
        version: &str,
        keys: Option<Vec<String>>,
    ) -> Result<restore::Point, String> {
        restore::make(
            &self.restore_root(),
            link,
            package,
            version,
            keys,
            now_s(),
            |path| {
                let made = self.link_restore_point_to(link, path)?;
                Ok((made.size, made.skipped))
            },
        )
    }

    /// Give the stopped link `link` the private data and secrets of its
    /// restore point `id` back. Blocking.
    pub(super) fn restore_point_apply(&self, link: &str, id: &str) -> Result<(), String> {
        let file = restore::file(&self.restore_root(), link, id)?;
        self.link_restore_data(link, &file)
    }

    /// `packages.keep_previous_days` in seconds (1 to 365 days).
    fn keep_previous_s(&self) -> u64 {
        u64::from(self.cfg.keep_previous_days.clamp(1, 365)) * 86_400
    }

    /// Is the update of package `name` being checked now (ADR 0048 §1.5)?
    pub fn package_updating(&self, name: &str) -> bool {
        self.is_updating(name)
    }

    fn is_updating(&self, name: &str) -> bool {
        self.updating
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .contains_key(name)
    }

    /// `busy` while the update of package `name` is being checked.
    pub(super) fn not_updating(&self, name: &str) -> Result<(), LinkError> {
        if self.is_updating(name) {
            return Err(LinkError::new(
                Status::Busy,
                format!(
                    "the update of {name} is being checked (sys/packages/{name}/last_update); \
                     try again when it ends, or stop it with rollback"
                ),
            ));
        }
        Ok(())
    }

    /// The `busy` of a link whose package update is being checked.
    pub(super) fn link_updating(&self, id: &str) -> Option<LinkError> {
        let driver = self.registry().links.get(id)?.driver.clone();
        let name = driver.strip_prefix(packages::DRIVER_PREFIX)?;
        self.not_updating(name).err()
    }

    /// Who asked to stop the check of `name` and roll back.
    fn update_stop_requested(&self, name: &str) -> Option<String> {
        self.updating
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .get(name)
            .cloned()
            .flatten()
    }

    /// Ask the running check of `name` to roll back now; `false`: none runs.
    fn request_update_stop(&self, name: &str, sub: &str) -> bool {
        match self
            .updating
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .get_mut(name)
        {
            Some(slot) => {
                *slot = Some(sub.to_owned());
                true
            }
            None => false,
        }
    }

    /// A long step of a background check (its rollback, its end): `None`
    /// while the broker closes for a rebuild, as [`Control::busy`].
    fn busy_owned(self: &Arc<Self>) -> Option<BusyOwned> {
        use std::sync::atomic::Ordering::SeqCst;
        self.inflight.fetch_add(1, SeqCst);
        let b = BusyOwned(self.clone());
        (!self.closing.load(SeqCst)).then_some(b)
    }

    /// A rebuild of the router is waiting: the check of `plan` steps aside
    /// and goes on with the next router ([`resume`]).
    fn pause_check(&self, plan: UpdatePlan) {
        debug!(package = %plan.name, "health check paused for a rebuild");
        self.paused_checks
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .push(plan);
    }
}

/// One link of a package before its update.
#[derive(Debug, Clone)]
struct LinkBefore {
    id: String,
    /// Its keys; `None`: it did not answer (stopped, or more keys than one
    /// read returns), so the check only waits for it to answer.
    keys: Option<BTreeSet<String>>,
}

/// What the health check of one update needs.
pub(super) struct UpdatePlan {
    name: String,
    report: UpdateReport,
    links: Vec<LinkBefore>,
    auto_rollback_s: u32,
    /// A link took the new code by a hot start.
    hot: bool,
    sub: String,
    /// The time the check has left.
    left: Duration,
}

impl UpdatePlan {
    /// The window the links were given, for the report.
    fn wait_s(&self) -> u32 {
        match self.auto_rollback_s {
            0 => REPORT_WAIT_S,
            s => s,
        }
    }
}

/// The links of a package against what they were before its update.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
struct Health {
    /// Links that do not answer.
    down: Vec<String>,
    kept: u32,
    /// `<link>/<path>` of every key that is new, and of every key that is gone.
    new: Vec<String>,
    gone: Vec<String>,
}

impl Health {
    fn good(&self) -> bool {
        self.down.is_empty() && self.gone.is_empty()
    }

    /// The counts and the first keys into `r`.
    fn fill(&self, r: &mut UpdateReport) {
        r.kept = self.kept;
        r.new = self.new.len() as u32;
        r.gone = self.gone.len() as u32;
        r.new_keys = self.new.iter().take(UPDATE_REPORT_KEYS).cloned().collect();
        r.gone_keys = self.gone.iter().take(UPDATE_REPORT_KEYS).cloned().collect();
    }

    /// Why this is not good, for people.
    fn why(&self, within_s: u32) -> String {
        let mut parts = Vec::new();
        if !self.down.is_empty() {
            parts.push(format!(
                "{} did not come back within {within_s} s",
                self.down.join(", ")
            ));
        }
        if !self.gone.is_empty() {
            let mut by_link: BTreeMap<&str, usize> = BTreeMap::new();
            for k in &self.gone {
                *by_link.entry(k.split('/').next().unwrap_or(k)).or_default() += 1;
            }
            for (link, n) in by_link {
                if !self.down.iter().any(|d| d == link) {
                    parts.push(format!(
                        "{link} did not declare {n} of its nodes again within {within_s} s"
                    ));
                }
            }
        }
        parts.join("; ")
    }
}

/// `health` of `links` given what each answers now (`None`: no answer).
fn compare(links: &[LinkBefore], now: &[Option<BTreeSet<String>>]) -> Health {
    let mut h = Health::default();
    for (l, now) in links.iter().zip(now) {
        let key = |k: &String| format!("{}/{k}", l.id);
        match (&l.keys, now) {
            (before, None) => {
                h.down.push(l.id.clone());
                // what a link that is not there had is gone
                h.gone.extend(before.iter().flatten().map(key));
            }
            (Some(before), Some(now)) => {
                h.kept += before.intersection(now).count() as u32;
                h.gone.extend(before.difference(now).map(key));
                h.new.extend(now.difference(before).map(key));
            }
            // nothing to compare with: it answers, that is all we asked
            (None, Some(_)) => {}
        }
    }
    h
}

/// Grants and network entries the new version asks for that `link` lacks.
fn missing_rights(
    link: &LinkDef,
    new: &PackageDef,
    app: Option<&Capabilities>,
) -> (Vec<(String, u8)>, Vec<String>) {
    let grants = new
        .requester
        .iter()
        .filter(|(path, level)| !link.grants.iter().any(|(p, l)| p == path && l >= level))
        .cloned()
        .collect();
    let has: BTreeSet<String> = match decode_params(&link.params) {
        Value::Map(m) => match m.get("net") {
            Some(Value::Str(net)) => net
                .split(',')
                .map(|s| s.trim().to_owned())
                .filter(|s| !s.is_empty())
                .collect(),
            _ => BTreeSet::new(),
        },
        _ => BTreeSet::new(),
    };
    let net = app
        .map(|c| {
            c.net
                .iter()
                .filter(|e| !has.contains(e.as_str()))
                .cloned()
                .collect()
        })
        .unwrap_or_default();
    (grants, net)
}

impl Admin {
    /// This responder's handles for a task that outlives the request (the
    /// health check): the same tree, control plane and embedded links.
    fn worker(&self) -> Admin {
        Admin {
            ctx: self.ctx.clone(),
            ctl: self.ctl.clone(),
            embedded: self.embedded.clone(),
            _broker: None,
        }
    }

    fn client(&self) -> wyrm_client::WyrmClient {
        wyrm_client::WyrmClient::new(self.ctx.client().clone()).with_timeout(KEYS_TIMEOUT)
    }

    /// The key list of link `id` (`~meta?view=keys` of its root), as any
    /// reader without a token sees it; `None` when it does not answer.
    async fn link_keys(&self, id: &str) -> Option<BTreeSet<String>> {
        let root = format!("wy/{}/downstream/{id}", self.ctl.cfg.site);
        self.client()
            .resolve(&root, None, None)
            .await
            .ok()
            .map(|k| k.into_iter().collect())
    }

    /// Does link `id` answer at all?
    async fn link_answers(&self, id: &str) -> bool {
        let root = format!("wy/{}/downstream/{id}", self.ctl.cfg.site);
        self.client().meta(&root).await.is_ok()
    }

    async fn health(&self, links: &[LinkBefore]) -> Health {
        let mut now = Vec::with_capacity(links.len());
        for l in links {
            now.push(match &l.keys {
                Some(_) => self.link_keys(&l.id).await,
                None => self.link_answers(&l.id).await.then(BTreeSet::new),
            });
        }
        compare(links, &now)
    }

    /// A restore point of `link` (ADR 0048 §1.3, §3.5), audited and shown
    /// in `sys/links/<id>/restore_points`.
    pub(super) async fn take_restore_point(
        &self,
        link: &str,
        package: &str,
        version: &str,
        keys: Option<Vec<String>>,
        sub: &str,
    ) -> Result<restore::Point, String> {
        let ctl = self.ctl.clone();
        let (l, p, v) = (link.to_owned(), package.to_owned(), version.to_owned());
        let made = tokio::task::spawn_blocking(move || ctl.restore_point_now(&l, &p, &v, keys))
            .await
            .map_err(|e| e.to_string())?;
        match &made {
            Ok(p) => self.ctl.record(
                sub,
                "restore_point",
                link,
                Status::Ok,
                &format!(
                    "{} {package} {version} {} B{}",
                    p.id,
                    p.size,
                    match p.skipped {
                        0 => String::new(),
                        n => format!("; {n} entries skipped (not files)"),
                    }
                ),
            ),
            Err(e) => self
                .ctl
                .record(sub, "restore_point", link, Status::InternalError, e),
        }
        publish_restore_points(&self.ctx, &self.ctl, link).await;
        made.map_err(|e| format!("restore point of {link}: {e}"))
    }

    /// Give the links of the package what the new version asks for and they
    /// lack (the caller accepted it): grants as `links/<id>/~act/grant`
    /// does, network entries added to the link's `net` param. `true` when a
    /// link's params changed (it must start again to read them).
    fn apply_rights(
        &self,
        links: &[LinkDef],
        new: &PackageDef,
        app: Option<&Capabilities>,
        sub: &str,
    ) -> Result<bool, String> {
        let (mut granted, mut params_changed) = (false, false);
        for l in links {
            let (grants, net) = missing_rights(l, new, app);
            for (path, code) in grants {
                let level = Perm::try_from(code).map_err(|c| format!("level {c}"))?;
                granted |= self
                    .set_grant(&l.id, &path, level, sub)
                    .map_err(|e| e.to_string())?;
            }
            if net.is_empty() {
                continue;
            }
            if l.origin == Origin::Config {
                warn!(link = %l.id, "net {}: the link is defined in wyrmd.json5; add it there", net.join(","));
                continue;
            }
            let Value::Map(mut params) = decode_params(&l.params) else {
                continue;
            };
            let mut all: Vec<String> = match params.get("net") {
                Some(Value::Str(s)) => s
                    .split(',')
                    .map(|s| s.trim().to_owned())
                    .filter(|s| !s.is_empty())
                    .collect(),
                _ => Vec::new(),
            };
            all.extend(net.iter().cloned());
            params.insert("net".into(), Value::Str(all.join(",")));
            self.ctl
                .apply(Op::Update {
                    id: l.id.clone(),
                    mode: l.mode,
                    params: encode_params(&Value::Map(params)).map_err(|e| e.to_string())?,
                })
                .map_err(|e| e.to_string())?;
            self.ctl.record(
                sub,
                "update",
                &l.id,
                Status::Ok,
                &format!("net +{} ({} {})", net.join(","), new.name, new.version),
            );
            params_changed = true;
        }
        if granted {
            // the router ACL and every link's trust list follow
            self.ctl.schedule_reload();
        }
        Ok(params_changed)
    }

    /// Replace the installed version `old` of a package by the unpacked one
    /// (ADR 0048 §1.2–1.5); returns the message of the install result. The
    /// health check goes on after this returns.
    pub(super) async fn update_package(
        &self,
        old: &PackageDef,
        unpacked: packages::Unpacked,
        app: Option<&Capabilities>,
        opts: UpdateOpts,
        sub: &str,
        accept: bool,
    ) -> Result<String, String> {
        let ctl = &self.ctl;
        let def = unpacked.def.clone();
        let name = def.name.clone();
        let root = ctl.packages_root();
        let changes_state = !unpacked.reads_state.contains(&old.state());
        if changes_state && !opts.restore_point {
            return Err(format!(
                "{name} {} changes the store format (it reads state {:?}, {} {} wrote state \
                 {}): a rollback needs a restore point. Nothing is installed: update with \
                 restore_point: true",
                def.version,
                unpacked.reads_state,
                name,
                old.version,
                old.state()
            ));
        }
        let links = links_of(ctl, &name);
        // new rights only when the installer saw them and said so (as an install)
        let mut asks = BTreeSet::new();
        for l in &links {
            let (grants, net) = missing_rights(l, &def, app);
            for (path, code) in grants {
                let level = Perm::try_from(code).map_or("?", |p| p.name());
                asks.insert(format!("{level} on {path}"));
            }
            asks.extend(net.into_iter().map(|e| format!("network {e}")));
        }
        if !asks.is_empty() && !accept {
            return Err(format!(
                "{name} {} asks for more than its links have: {}. Nothing is installed: read \
                 them, then update again with Accept Requested Rights",
                def.version,
                asks.into_iter().collect::<Vec<_>>().join("; ")
            ));
        }
        // the kept version again (same bytes): its directory is there already
        let reuse = old
            .previous
            .as_deref()
            .is_some_and(|p| p.def.version == def.version && p.def.sha256 == def.sha256);
        if !reuse && packages::dir(&root, &def).exists() {
            return Err(format!(
                "{name} {} is on disk with other content",
                def.version
            ));
        }

        // Before anything stops: each link's keys and its restore point.
        let now = now_s();
        let mut before = Vec::new();
        let mut points = Vec::new();
        for l in &links {
            let keys = self.link_keys(&l.id).await;
            if opts.restore_point {
                let listed = keys.as_ref().map(|k| k.iter().cloned().collect());
                let p = self
                    .take_restore_point(&l.id, &name, &old.version, listed, sub)
                    .await?;
                points.push(format!("{} ({} B)", l.id, p.size));
            }
            before.push(LinkBefore {
                id: l.id.clone(),
                keys,
            });
        }

        // The new files beside the old ones, then the registry.
        if !reuse {
            unpacked.commit(&root)?;
        } else {
            drop(unpacked);
        }
        let report = UpdateReport {
            from: old.version.clone(),
            to: def.version.clone(),
            at: now,
            result: if links.is_empty() {
                UPDATE_OK.into()
            } else {
                UPDATE_CHECKING.into()
            },
            links: links.iter().map(|l| l.id.clone()).collect(),
            changes_state,
            restore_point: opts.restore_point,
            ..UpdateReport::default()
        };
        let mut new = def.clone();
        new.previous = Some(Box::new(PreviousDef {
            def: old.bare(),
            keep_until: now + ctl.keep_previous_s(),
            replaced: now,
            changes_state,
        }));
        new.last_update = Some(report.clone());
        let put = (|| {
            if def.kind == PackageKind::Wasm {
                ctl.publish_component(&def)?;
            }
            ctl.apply(Op::PutPackage(new.clone()))
                .map_err(|e| e.to_string())
        })();
        if let Err(e) = put {
            // as before the update: the old version is the installed one
            if !reuse {
                let _ = std::fs::remove_dir_all(packages::dir(&root, &def));
            }
            if old.kind == PackageKind::Wasm {
                let _ = ctl.publish_component(old);
            }
            return Err(e);
        }
        // one version is kept: the one before `old` goes
        if let Some(pp) = old.previous.as_deref() {
            if pp.def.version != def.version {
                let _ = std::fs::remove_dir_all(packages::dir(&root, &pp.def));
            }
        }
        ctl.record(
            sub,
            "package_install",
            &name,
            Status::Ok,
            &install_detail(&def, app),
        );
        ctl.record(
            sub,
            "package_update",
            &name,
            Status::Ok,
            &format!(
                "{} → {} started; links {}; restore point {}; auto rollback {} s{}",
                old.version,
                def.version,
                report.links.join(","),
                if opts.restore_point { "yes" } else { "no" },
                opts.auto_rollback_s,
                if changes_state {
                    "; changes the store format"
                } else {
                    ""
                }
            ),
        );
        // From here the new version is the installed one: what fails below
        // is told, and the links still start and are checked.
        if let Err(e) = super::declare_package(&self.ctx, ctl, &new).await {
            debug!(package = %name, "values after the update: {e}");
        }
        let mut m = format!("package {name} {} → {}", old.version, def.version);
        let params_changed = match self.apply_rights(&links, &def, app, sub) {
            Ok(changed) => changed,
            Err(e) => {
                m.push_str(&format!("; the accepted rights were not all applied: {e}"));
                true
            }
        };
        // a link whose params changed reads them at a start, not a hot start
        let (failed, hot) = self
            .upgrade_links(&def, app.is_some() && !params_changed, sub)
            .await;
        if !failed.is_empty() {
            m.push_str(&format!("; not restarted: {}", failed.join(", ")));
        }
        if !points.is_empty() {
            m.push_str(&format!("; restore points: {}", points.join(", ")));
        }
        if links.is_empty() {
            return Ok(m);
        }
        // The check goes on by itself.
        ctl.updating
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .insert(name.clone(), None);
        let mut plan = UpdatePlan {
            name: name.clone(),
            report,
            links: before,
            auto_rollback_s: opts.auto_rollback_s,
            hot,
            sub: sub.to_owned(),
            left: Duration::ZERO,
        };
        plan.left = Duration::from_secs(plan.wait_s().into());
        let worker = self.worker();
        tokio::spawn(async move { worker.check_update(plan).await });
        m.push_str(&match opts.auto_rollback_s {
            0 => format!("; the links are being checked: sys/packages/{name}/last_update"),
            s => format!(
                "; the links are being checked (rolled back by itself when they are not \
                 back with every node in {s} s): sys/packages/{name}/last_update"
            ),
        });
        Ok(m)
    }

    /// The health check of one update (ADR 0048 §1.5): polls the links
    /// until they are all back with every key they had and stay so, or the
    /// time is up, or someone stops it; then keeps, rolls back or reports.
    /// A rebuild of the router that waits meanwhile gets its way: the check
    /// steps aside and [`resume`] starts it again on the new router.
    async fn check_update(self, mut plan: UpdatePlan) {
        use std::sync::atomic::Ordering::SeqCst;
        let ctl = self.ctl.clone();
        let name = plan.name.clone();
        let wait_s = plan.wait_s();
        let settle = if plan.hot { SETTLE_HOT } else { SETTLE };
        let deadline = tokio::time::Instant::now() + plan.left;
        let leaf = format!("packages/{name}/last_update");
        let mut seen: Option<(Health, tokio::time::Instant)> = None;
        let (health, stopped) = loop {
            if ctl.closing.load(SeqCst) || self.ctx.is_closed() {
                plan.left = deadline.saturating_duration_since(tokio::time::Instant::now());
                return ctl.pause_check(plan);
            }
            let h = self.health(&plan.links).await;
            if let Some(who) = ctl.update_stop_requested(&name) {
                break (h, Some(who));
            }
            // with auto rollback off a link that answers is all the report waits for
            let enough = h.good() || (plan.auto_rollback_s == 0 && h.down.is_empty());
            let now = tokio::time::Instant::now();
            match &seen {
                Some((prev, since)) if *prev == h => {
                    if enough && now.duration_since(*since) >= settle {
                        break (h, None);
                    }
                }
                _ => {
                    // progress for whoever watches: `n of m` nodes are back
                    let mut r = plan.report.clone();
                    h.fill(&mut r);
                    let _ = self
                        .ctx
                        .update(&leaf, report_value(&r), Quality::Good, now_us())
                        .await;
                    seen = Some((h.clone(), now));
                }
            }
            if now >= deadline {
                break (h, None);
            }
            tokio::time::sleep(Duration::from_secs(1)).await;
        };
        // What follows stops and starts links: a rebuild waits for it, and
        // one that is closing the router already comes first.
        let Some(_busy) = ctl.busy_owned() else {
            plan.left = deadline.saturating_duration_since(tokio::time::Instant::now());
            return ctl.pause_check(plan);
        };

        let mut report = plan.report.clone();
        health.fill(&mut report);
        let rollback = match &stopped {
            Some(who) => Some(format!("stopped by {who}")),
            None if !health.good() && plan.auto_rollback_s > 0 => Some(health.why(wait_s)),
            None => None,
        };
        match rollback {
            Some(reason) => {
                if let Err(e) = self
                    .roll_back(&name, &plan.sub, &reason, report.clone())
                    .await
                {
                    report.result = UPDATE_FAILED.into();
                    report.reason = format!("{reason}; the rollback failed: {e}");
                    self.finish(&name, report, &plan.sub).await;
                }
            }
            None => {
                if health.down.is_empty() {
                    report.result = UPDATE_OK.into();
                    if !health.gone.is_empty() {
                        report.reason = format!("{} (not rolled back)", health.why(wait_s));
                    }
                } else {
                    report.result = UPDATE_FAILED.into();
                    report.reason = format!("{} (not rolled back)", health.why(wait_s));
                }
                self.finish(&name, report, &plan.sub).await;
            }
        }
        ctl.updating
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .remove(&name);
    }

    /// Store the end of an update that kept the new version, and audit it.
    async fn finish(&self, name: &str, report: UpdateReport, sub: &str) {
        let Some(mut def) = self.ctl.registry().packages.get(name).cloned() else {
            return;
        };
        let status = if report.result == UPDATE_OK {
            Status::Ok
        } else {
            Status::InternalError
        };
        self.ctl.record(
            sub,
            "package_update",
            name,
            status,
            &format!(
                "{} → {} {}: kept {}, new {}, gone {}{}",
                report.from,
                report.to,
                report.result,
                report.kept,
                report.new,
                report.gone,
                if report.reason.is_empty() {
                    String::new()
                } else {
                    format!("; {}", report.reason)
                }
            ),
        );
        def.last_update = Some(report);
        if let Err(e) = self.ctl.apply(Op::PutPackage(def.clone())) {
            warn!(package = name, "last_update: {e}");
        }
        publish_package(&self.ctx, &self.ctl, &def).await;
        publish_count(&self.ctx, &self.ctl).await;
    }

    /// Back to the kept version (ADR 0048 §1.6): the links stop, the
    /// registry names the previous version again, each link's private data
    /// comes back from its newest restore point taken at or before the
    /// update, the links start. `report` (of the update that is undone)
    /// becomes `last_update` with `rolled_back` and `reason`. Nothing changes
    /// on `Err`.
    async fn roll_back(
        &self,
        name: &str,
        sub: &str,
        reason: &str,
        mut report: UpdateReport,
    ) -> Result<String, String> {
        let ctl = &self.ctl;
        let cur = ctl
            .registry()
            .packages
            .get(name)
            .cloned()
            .ok_or_else(|| format!("no package {name}"))?;
        let prev = cur
            .previous
            .clone()
            .ok_or_else(|| format!("{name}: no previous version is kept"))?;
        let root = ctl.packages_root();
        if !packages::dir(&root, &prev.def)
            .join(&prev.def.entry)
            .is_file()
        {
            return Err(format!(
                "{name} {}: its kept directory is gone",
                prev.def.version
            ));
        }
        let links = links_of(ctl, name);
        let restore_root = ctl.restore_root();
        let mut points = Vec::new();
        for l in &links {
            let p = restore::newest_before(
                &restore_root,
                &l.id,
                prev.replaced,
                name,
                &prev.def.version,
            );
            if p.is_none() && prev.changes_state {
                return Err(format!(
                    "the update to {} changed the store format and link {} has no restore \
                     point of {}: {} could not read its data. Nothing is rolled back",
                    cur.version, l.id, prev.def.version, prev.def.version
                ));
            }
            points.push((l.id.clone(), p));
        }
        for l in &links {
            if let Err(e) = self.stop_link(&l.id, sub).await {
                debug!(link = %l.id, "stop for rollback: {e}");
            }
        }
        report.result = UPDATE_ROLLED_BACK.into();
        report.reason = reason.to_owned();
        report.at = now_s();
        let mut back = prev.def.clone();
        back.last_update = Some(report);
        let put = (|| {
            if back.kind == PackageKind::Wasm {
                ctl.publish_component(&back)?;
            }
            ctl.apply(Op::PutPackage(back.clone()))
                .map_err(|e| e.to_string())
        })();
        if let Err(e) = put {
            // still on the new version: its links start again
            if cur.kind == PackageKind::Wasm {
                let _ = ctl.publish_component(&cur);
            }
            for l in &links {
                let _ = self.start_link(&l.id, sub).await;
            }
            return Err(e);
        }

        let (mut restored, mut problems) = (Vec::new(), Vec::new());
        for (id, point) in points {
            let Some(point) = point else {
                problems.push(format!("{id}: no restore point, its data stays"));
                continue;
            };
            let (c, l, pid) = (ctl.clone(), id.clone(), point.id.clone());
            let applied = tokio::task::spawn_blocking(move || c.restore_point_apply(&l, &pid))
                .await
                .map_err(|e| e.to_string())
                .and_then(|r| r);
            match applied {
                Ok(()) => restored.push(format!("{id} ({})", point.id)),
                Err(e) => problems.push(format!("{id}: {e}")),
            }
        }
        for l in &links {
            if let Err(e) = self.start_link(&l.id, sub).await {
                problems.push(format!("{}: not started ({})", l.id, e.message));
            }
        }
        if cur.version != back.version {
            let _ = std::fs::remove_dir_all(packages::dir(&root, &cur));
        }
        let mut detail = format!("{} → {}: {reason}", cur.version, back.version);
        if !restored.is_empty() {
            detail.push_str(&format!("; data restored: {}", restored.join(", ")));
        }
        if !problems.is_empty() {
            detail.push_str(&format!("; {}", problems.join("; ")));
        }
        ctl.record(
            sub,
            "update_rollback",
            name,
            if problems.is_empty() {
                Status::Ok
            } else {
                Status::InternalError
            },
            &detail,
        );
        if let Err(e) = super::declare_package(&self.ctx, ctl, &back).await {
            debug!(package = name, "values after rollback: {e}");
        }
        Ok(format!("package {name} {detail}"))
    }

    /// `sys/packages/<name>/~act/update {version?, accept, restore_point,
    /// auto_rollback_s}`: the repository's version, by the same path as
    /// `install_repo` (SHA-256 of the index).
    pub(super) async fn update_action(
        &self,
        name: &str,
        args: &Value,
        sub: &str,
    ) -> wyrm_link_sdk::Result<Option<Value>> {
        let def = self
            .ctl
            .registry()
            .packages
            .get(name)
            .cloned()
            .ok_or_else(|| LinkError::not_found(name.to_owned()))?;
        let opts = UpdateOpts::from_args(args)?;
        let _busy = self.ctl.busy()?;
        self.ctl.not_updating(name)?;
        let wanted = arg_str(args, "version")
            .map(str::trim)
            .filter(|v| !v.is_empty());
        let check = || -> Result<String, String> {
            let e = index_entry(&self.ctl, name).ok_or_else(|| {
                format!(
                    "{name} is not in the repository: update it with Install Link ▸ from \
                     ZIP, URL or Git and a package of the same name"
                )
            })?;
            // an index names one version of a package
            if let Some(v) = wanted.filter(|v| *v != e.version) {
                return Err(format!("the repository has {name} {}, not {v}", e.version));
            }
            if e.version == def.version {
                return Err(format!("{name} {} is installed already", def.version));
            }
            if wanted.is_none() && !newer(&e.version, &def.version) {
                return Err(format!(
                    "{name} {} is installed and the repository has {}: name that version \
                     to install it all the same",
                    def.version, e.version
                ));
            }
            links_of(&self.ctl, name)
                .first()
                .map(|l| l.id.clone())
                .ok_or_else(|| {
                    format!("no link runs {name}: install one with Install Link ▸ from Repository")
                })
        };
        let r = match check() {
            Ok(link) => {
                self.install_from_repo(&link, name, sub, accepted(args), opts)
                    .await
            }
            Err(e) => Err(e),
        };
        Ok(Some(outcome(r)))
    }

    /// `sys/packages/<name>/~act/rollback {to?}`. While the update is being
    /// checked it stops the check, which then rolls back.
    pub(super) async fn rollback_action(
        &self,
        name: &str,
        args: &Value,
        sub: &str,
    ) -> wyrm_link_sdk::Result<Option<Value>> {
        let def = self
            .ctl
            .registry()
            .packages
            .get(name)
            .cloned()
            .ok_or_else(|| LinkError::not_found(name.to_owned()))?;
        let _busy = self.ctl.busy()?;
        let prev = match def.previous.as_deref() {
            Some(p) => p,
            None => {
                return Ok(Some(outcome(Err(format!(
                    "{name}: no previous version is kept"
                )))))
            }
        };
        if let Some(to) = arg_str(args, "to")
            .map(str::trim)
            .filter(|v| !v.is_empty() && *v != prev.def.version)
        {
            return Ok(Some(outcome(Err(format!(
                "{name}: the kept version is {}, not {to}",
                prev.def.version
            )))));
        }
        if self.ctl.request_update_stop(name, sub) {
            return Ok(Some(outcome(Ok(format!(
                "the update of {name} to {} stops and rolls back to {}: \
                 sys/packages/{name}/last_update",
                def.version, prev.def.version
            )))));
        }
        // the report of the update that is undone, when it is the last one
        let report = def
            .last_update
            .clone()
            .filter(|r| r.from == prev.def.version && r.to == def.version)
            .unwrap_or_else(|| UpdateReport {
                from: prev.def.version.clone(),
                to: def.version.clone(),
                links: links_of(&self.ctl, name)
                    .into_iter()
                    .map(|l| l.id)
                    .collect(),
                changes_state: prev.changes_state,
                ..UpdateReport::default()
            });
        let r = self
            .roll_back(name, sub, &format!("rolled back by {sub}"), report)
            .await;
        Ok(Some(outcome(r)))
    }
}

/// Reports left `checking` by a broker that ended during the check: closed
/// as `failed` (the new version stays; a rollback is still there).
fn close_stale(ctl: &Control) {
    for mut p in ctl.registry().packages.into_values() {
        let Some(r) = p.last_update.as_mut() else {
            continue;
        };
        if r.result != UPDATE_CHECKING || ctl.is_updating(&p.name) {
            continue;
        }
        r.result = UPDATE_FAILED.into();
        r.reason =
            "the broker stopped while the links were being checked; the new version stays".into();
        ctl.record(
            "broker",
            "package_update",
            &p.name,
            Status::InternalError,
            &format!("{} → {}: {}", r.from, r.to, r.reason),
        );
        if let Err(e) = ctl.apply(Op::PutPackage(p.clone())).map_err(rejected) {
            warn!(package = %p.name, "last_update: {e}");
        }
    }
}

/// Previous versions past `keep_until` lose their directory and their
/// place in the registry.
fn expire_previous(ctl: &Control, now: u64) {
    let root = ctl.packages_root();
    for mut p in ctl.registry().packages.into_values() {
        let Some(prev) = p.previous.as_deref() else {
            continue;
        };
        if prev.keep_until >= now || ctl.is_updating(&p.name) {
            continue;
        }
        if prev.def.version != p.version {
            let dir = packages::dir(&root, &prev.def);
            if let Err(e) = std::fs::remove_dir_all(&dir) {
                debug!("{}: {e}", dir.display());
            }
        }
        p.previous = None;
        if let Err(e) = ctl.apply(Op::PutPackage(p.clone())).map_err(rejected) {
            warn!(package = %p.name, "previous: {e}");
        }
    }
}

/// [`expire_previous`], and restore points older than
/// `packages.keep_previous_days` go.
async fn expire(ctl: &Arc<Control>, ctx: &LinkCtx) {
    let now = now_s();
    let c = ctl.clone();
    if let Err(e) = tokio::task::spawn_blocking(move || expire_previous(&c, now)).await {
        debug!("previous versions: {e}");
    }
    let (restore_root, keep_s) = (ctl.restore_root(), ctl.keep_previous_s());
    let pruned = tokio::task::spawn_blocking(move || restore::prune(&restore_root, now, keep_s))
        .await
        .unwrap_or_default();
    for link in pruned {
        if ctl.registry().links.contains_key(&link) {
            publish_restore_points(ctx, ctl, &link).await;
        }
    }
}

/// Start again, on this router, the checks that stepped aside for its
/// rebuild; each has the time it had left, at least [`RESUME_MIN`].
pub(super) async fn resume(ctl: Arc<Control>, ctx: LinkCtx, embedded: super::Running) {
    loop {
        if ctx.is_closed() {
            return;
        }
        // `closing` falls when the new router is up ([`Control::reopen`])
        if !ctl.closing.load(std::sync::atomic::Ordering::SeqCst) {
            let paused =
                std::mem::take(&mut *ctl.paused_checks.lock().unwrap_or_else(|p| p.into_inner()));
            for mut plan in paused {
                plan.left = plan.left.max(RESUME_MIN);
                let worker = Admin {
                    ctx: ctx.clone(),
                    ctl: ctl.clone(),
                    embedded: embedded.clone(),
                    _broker: None,
                };
                tokio::spawn(async move { worker.check_update(plan).await });
            }
        }
        tokio::time::sleep(Duration::from_millis(500)).await;
    }
}

/// For as long as the router runs: closes stale reports once, then keeps
/// previous versions and restore points for `packages.keep_previous_days`
/// and shows what the registry holds (a check that ended after its router
/// was rebuilt wrote the registry, not this tree).
pub(super) async fn keep(ctl: Arc<Control>, ctx: LinkCtx) {
    close_stale(&ctl);
    let mut shown = None;
    loop {
        if ctx.is_closed() {
            return;
        }
        expire(&ctl, &ctx).await;
        let packages = ctl.registry().packages;
        if shown.as_ref() != Some(&packages) {
            publish_all(&ctx, &ctl).await;
            shown = Some(packages);
        }
        tokio::time::sleep(KEEP_TICK).await;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn package(version: &str) -> PackageDef {
        PackageDef {
            name: "pkg".into(),
            version: version.into(),
            kind: PackageKind::Process,
            entry: "bin/run".into(),
            args: Vec::new(),
            sha256: "00".into(),
            source: "zip".into(),
            description: String::new(),
            installed: 1,
            requester: Vec::new(),
            state: 1,
            previous: None,
            last_update: None,
        }
    }

    /// `pkg` 1.1.0 over a kept 1.0.0 (both directories on disk), its report
    /// still `checking`.
    fn updated(ctl: &Control, keep_until: u64) -> PackageDef {
        let old = package("1.0.0");
        let mut new = package("1.1.0");
        new.previous = Some(Box::new(PreviousDef {
            def: old.bare(),
            keep_until,
            replaced: 100,
            changes_state: false,
        }));
        new.last_update = Some(UpdateReport {
            from: "1.0.0".into(),
            to: "1.1.0".into(),
            at: 100,
            result: UPDATE_CHECKING.into(),
            links: vec!["l1".into()],
            ..UpdateReport::default()
        });
        for d in [&old, &new] {
            std::fs::create_dir_all(packages::dir(&ctl.packages_root(), d)).unwrap();
        }
        ctl.apply(Op::PutPackage(new.clone())).unwrap();
        new
    }

    /// A broker that ended during a health check: the next start closes the
    /// report; one whose check still runs is left alone.
    #[test]
    fn a_report_left_checking_is_closed_at_the_next_start() {
        let ctl = super::super::tests::control("upd-stale", false, |_| {});
        updated(&ctl, u64::MAX);
        ctl.updating.lock().unwrap().insert("pkg".to_owned(), None);
        close_stale(&ctl);
        let r = ctl.registry().packages["pkg"].last_update.clone().unwrap();
        assert_eq!(r.result, UPDATE_CHECKING, "its check runs");
        assert!(ctl.package_updating("pkg") && ctl.not_updating("pkg").is_err());
        assert_eq!(
            ctl.not_updating("pkg").unwrap_err().status,
            Status::Busy,
            "a refusal is an error (docs/links.md §1)"
        );

        ctl.updating.lock().unwrap().clear();
        close_stale(&ctl);
        let p = ctl.registry().packages["pkg"].clone();
        let r = p.last_update.unwrap();
        assert_eq!(r.result, UPDATE_FAILED);
        assert!(r.reason.contains("the broker stopped"), "{}", r.reason);
        // the new version stays, with its way back
        assert_eq!(p.version, "1.1.0");
        assert_eq!(p.previous.unwrap().def.version, "1.0.0");
        assert!(ctl
            .audit_tail(10)
            .iter()
            .any(|a| a.op == "package_update" && a.key == "pkg"));
    }

    /// The previous version goes after `keep_until`, never during a check.
    #[test]
    fn the_previous_version_is_kept_until_keep_until() {
        let ctl = super::super::tests::control("upd-expire", false, |_| {});
        let p = updated(&ctl, 1_000);
        let root = ctl.packages_root();
        let old_dir = root.join("pkg/1.0.0");
        expire_previous(&ctl, 1_000);
        assert!(old_dir.is_dir() && ctl.registry().packages["pkg"].previous.is_some());
        ctl.updating.lock().unwrap().insert("pkg".to_owned(), None);
        expire_previous(&ctl, 1_001);
        assert!(old_dir.is_dir(), "kept while the update is being checked");
        ctl.updating.lock().unwrap().clear();
        expire_previous(&ctl, 1_001);
        assert!(!old_dir.exists() && root.join("pkg/1.1.0").is_dir());
        let now = ctl.registry().packages["pkg"].clone();
        assert!(now.previous.is_none());
        assert_eq!((now.version, now.last_update), (p.version, p.last_update));
        // 7 days by default, within 1 to 365
        assert_eq!(ctl.keep_previous_s(), 7 * 86_400);
    }

    /// What the new version asks for and a link lacks.
    #[test]
    fn rights_a_link_lacks() {
        let link = |grants: Vec<(String, u8)>, net: &str| LinkDef {
            id: "l1".into(),
            driver: "pkg:pkg".into(),
            mode: crate::registry::Mode::Embedded,
            params: encode_params(&map(vec![("net", Value::Str(net.into()))])).unwrap(),
            token_hash: String::new(),
            rev: 1,
            origin: Origin::Runtime,
            created: 1,
            display: None,
            granted: None,
            log_level: None,
            grants,
        };
        let (read, write) = (Perm::Read.code(), Perm::Write.code());
        let mut new = package("1.1.0");
        new.requester = vec![
            ("wy/{site}/downstream/a".into(), read),
            ("wy/{site}/downstream/b".into(), write),
        ];
        let caps = Capabilities {
            net: vec!["10.0.0.1:502".into(), "10.0.0.2:502".into()],
            ..Capabilities::default()
        };
        // a higher level covers a lower one; a lower one does not
        let l = link(
            vec![
                ("wy/{site}/downstream/a".into(), write),
                ("wy/{site}/downstream/b".into(), read),
            ],
            "10.0.0.1:502, 10.9.9.9:1",
        );
        let (grants, net) = missing_rights(&l, &new, Some(&caps));
        assert_eq!(grants, [("wy/{site}/downstream/b".to_owned(), write)]);
        assert_eq!(net, ["10.0.0.2:502"]);
        // nothing asked beyond what the link has
        let l = link(new.requester.clone(), "10.0.0.2:502,10.0.0.1:502");
        assert_eq!(missing_rights(&l, &new, Some(&caps)), (vec![], vec![]));
        assert_eq!(missing_rights(&l, &new, None).1, Vec::<String>::new());
    }

    #[test]
    fn newer_versions() {
        for (latest, installed, want) in [
            ("1.0.1", "1.0.0", true),
            ("1.10.0", "1.9.2", true),
            ("2.0", "1.9.9", true),
            ("1.0.0", "1.0.0", false),
            ("1.0.0", "1.0.1", false),
            ("1.9.2", "1.10.0", false),
            ("1.0.0", "1.0.0-rc1", true),
            ("1.0.0-rc2", "1.0.0-rc1", true),
            ("1.0.0-rc1", "1.0.0", false),
            ("1.0.0+b2", "1.0.0+b1", false),
            // not dotted numbers: another version is the one to offer
            ("0+abc", "0+abd", false),
            ("release-b", "release-a", true),
        ] {
            assert_eq!(newer(latest, installed), want, "{latest} over {installed}");
        }
    }

    #[test]
    fn options() {
        let args = |pairs: Vec<(&str, Value)>| map(pairs);
        assert_eq!(
            UpdateOpts::from_args(&args(vec![])).unwrap(),
            UpdateOpts {
                restore_point: true,
                auto_rollback_s: 120
            }
        );
        let o = UpdateOpts::from_args(&args(vec![
            ("restore_point", Value::Bool(false)),
            ("auto_rollback_s", Value::UInt(0)),
        ]))
        .unwrap();
        assert_eq!((o.restore_point, o.auto_rollback_s), (false, 0));
        for bad in [
            ("auto_rollback_s", Value::UInt(601)),
            ("auto_rollback_s", Value::Float(1.5)),
            ("auto_rollback_s", Value::Str("soon".into())),
            ("restore_point", Value::Str("yes".into())),
        ] {
            let e = UpdateOpts::from_args(&args(vec![bad.clone()])).unwrap_err();
            assert!(e.status.code() >= 0x20, "{bad:?}: a refusal is an error");
            assert!(e.message.contains(bad.0), "{}", e.message);
        }
    }

    fn set(keys: &[&str]) -> BTreeSet<String> {
        keys.iter().map(|k| (*k).to_owned()).collect()
    }

    #[test]
    fn kept_new_and_gone() {
        let links = vec![
            LinkBefore {
                id: "a".into(),
                keys: Some(set(&["c1", "c1/p1", "c1/p2"])),
            },
            LinkBefore {
                id: "b".into(),
                keys: Some(set(&["x"])),
            },
            LinkBefore {
                id: "c".into(),
                keys: None,
            },
        ];
        // all back, one key more
        let h = compare(
            &links,
            &[
                Some(set(&["c1", "c1/p1", "c1/p2", "c1/p3"])),
                Some(set(&["x"])),
                Some(set(&[])),
            ],
        );
        assert!(h.good());
        assert_eq!(
            (h.kept, h.new.clone(), h.gone.len()),
            (4, vec!["a/c1/p3".to_owned()], 0)
        );
        // a key not declared again, and a link that does not answer
        let h = compare(&links, &[Some(set(&["c1", "c1/p1"])), None, None]);
        assert!(!h.good());
        assert_eq!(h.down, ["b", "c"]);
        assert_eq!(h.gone, ["a/c1/p2", "b/x"]);
        assert_eq!(h.kept, 2);
        let why = h.why(120);
        assert!(why.contains("b, c did not come back within 120 s"), "{why}");
        assert!(
            why.contains("a did not declare 1 of its nodes again"),
            "{why}"
        );
        let mut r = UpdateReport::default();
        h.fill(&mut r);
        assert_eq!((r.kept, r.new, r.gone), (2, 0, 2));
        // the report keeps the counts and the first keys only
        let many: Vec<String> = (0..500).map(|i| format!("p{i:03}")).collect();
        let before = vec![LinkBefore {
            id: "a".into(),
            keys: Some(many.iter().cloned().collect()),
        }];
        let h = compare(&before, &[Some(BTreeSet::new())]);
        h.fill(&mut r);
        assert_eq!((r.gone, r.gone_keys.len()), (500, UPDATE_REPORT_KEYS));
    }
}
