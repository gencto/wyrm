//! The MCP server over a user gateway (ADR 0041): Claude (Desktop, Code, any MCP client) works
//! on a broker network as one gateway user. The user's role decides every read and write, as
//! for `wyrm-agent` (ADR 0033) and Studio; the gateway reaches the sites below it.
//!
//! On top of the role, two local switches the person who installs the connector sets:
//! `read_only` refuses every change, and config-level changes (a `~set` on a node with
//! `writable = config`, an action of level `config`, anything under `wy/<site>/sys/**`, a flow
//! deploy) go out only with `allow_config`. Changes are dry-run first by default, and the tools
//! carry MCP annotations (`readOnlyHint`, `destructiveHint`), so a client asks the person
//! before a change runs.
//!
//! The session is opened lazily and opened again when the gateway closes it (expiry, a role
//! change that revokes it, a broker rebuild); the password stays in memory only.

use crate::gw::{self, Step};
use crate::json::{json_to_value, value_to_json};
use crate::spec;
use rmcp::handler::server::router::tool::ToolRouter;
use rmcp::handler::server::wrapper::Parameters;
use rmcp::model::{
    CallToolResult, ContentBlock, Extensions, Implementation, ListResourcesResult,
    PaginatedRequestParams, ReadResourceRequestParams, ReadResourceResponse, ReadResourceResult,
    Resource, ResourceContents, ServerCapabilities, ServerConfig,
};
use rmcp::service::RequestContext;
use rmcp::{tool, tool_handler, tool_router, ErrorData as McpError, RoleServer, ServerHandler};
use schemars::JsonSchema;
use serde::Deserialize;
use serde_json::{json, Map, Value as Json};
use std::future::Future;
use std::pin::Pin;
use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use wyrm_core::{NodeMeta, Perm};
use wyrm_gateway_client::{Conn, Endpoint, Gateway, Me};
use zeroize::Zeroizing;

/// Most keys in one `value_get`.
const GET_MAX: usize = 50;
/// Most nodes one `tree_list` returns.
const TREE_MAX: usize = 1000;
/// Longest `value_watch`.
const WATCH_MAX_S: f64 = 60.0;
/// Most samples one `value_watch` returns.
const WATCH_SAMPLES_MAX: usize = 1000;
/// A session this close to its expiry is replaced before use.
const EXPIRY_MARGIN_S: u64 = 60;

const INSTRUCTIONS: &str = "WYRM broker network (IOT-DSA semantics on Zenoh), reached through a \
user gateway as one gateway user: that user's role decides what may be read and changed. Node keys \
are `wy/<site>/downstream/<link>/<path>`, `wy/<site>/dataflows/<id>`, `wy/<site>/storage/<path>`; a \
path without `wy/` is taken relative to the gateway's own site, and sites below it (downstream \
brokers) are reached by their full keys. Start with whoami, then tree_list / node_meta / value_get. \
Before a change, read the node's ~meta (node_meta), call node_set / action_invoke / flow_deploy with \
dry_run=true (the default), show the person what would be sent, and only then repeat with \
dry_run=false. Several steps that build on each other (add a device, wait for it, set a value, \
expect a reading) go in one plan_run: check it (apply=false), then apply. The `spec` tool holds the \
normative protocol.";

/// How the server reaches its gateway and what it lets through.
pub struct GatewayOptions {
    pub endpoint: Endpoint,
    /// The URL as given, for `whoami`.
    pub url: String,
    pub user: String,
    pub password: Zeroizing<String>,
    /// Refuse every change.
    pub read_only: bool,
    /// Let config-level changes through (the role still decides).
    pub allow_config: bool,
}

/// One working session on a gateway: the socket, who it is, and the switches that narrow it.
#[derive(Clone)]
pub struct Session {
    pub conn: Arc<Conn>,
    pub me: Me,
    /// Refuse every change.
    pub read_only: bool,
    /// Let config-level changes through (the role still decides).
    pub allow_config: bool,
}

pub type BoxFuture<'a, T> = Pin<Box<dyn Future<Output = T> + Send + 'a>>;

/// Where a request's session comes from: a password login of this process (the Claude
/// Desktop extension), or the gateway itself for its own `/mcp` endpoint, which finds the
/// user in the request (`ext` holds the HTTP request parts there).
pub trait Backend: Send + Sync + 'static {
    fn session<'a>(&'a self, ext: &'a Extensions) -> BoxFuture<'a, Result<Session, String>>;
    /// The gateway, for `whoami`.
    fn label(&self) -> String;
}

/// Logs in with a password, keeps the session, and logs in again when it dies.
struct PasswordBackend {
    opts: GatewayOptions,
    live: tokio::sync::Mutex<Option<Session>>,
}

impl PasswordBackend {
    async fn open(&self) -> Result<Session, String> {
        let mut g = self.live.lock().await;
        if let Some(l) = g.as_ref() {
            if !l.conn.is_closed() && l.me.exp > now_s() + EXPIRY_MARGIN_S {
                return Ok(l.clone());
            }
        }
        *g = None;
        let o = &self.opts;
        let gw = Gateway::login_at(o.endpoint.clone(), &o.user, &o.password)
            .await
            .map_err(|e| format!("gateway {}: {e}", o.url))?;
        let me = gw
            .me()
            .await
            .map_err(|e| format!("gateway {}: {e}", o.url))?;
        let conn = Arc::new(
            gw.connect()
                .await
                .map_err(|e| format!("gateway {}: {e}", o.url))?,
        );
        tracing::info!(user = %me.sub, site = %me.site, "gateway session opened");
        let s = Session {
            conn,
            me,
            read_only: o.read_only,
            allow_config: o.allow_config,
        };
        *g = Some(s.clone());
        Ok(s)
    }
}

impl Backend for PasswordBackend {
    fn session<'a>(&'a self, _ext: &'a Extensions) -> BoxFuture<'a, Result<Session, String>> {
        Box::pin(self.open())
    }

    fn label(&self) -> String {
        self.opts.url.clone()
    }
}

#[derive(Clone)]
pub struct GatewayMcp {
    backend: Arc<dyn Backend>,
    tool_router: ToolRouter<Self>,
}

type Out = Result<Json, String>;

fn done(r: Out) -> CallToolResult {
    match r {
        Ok(j) => CallToolResult::success(vec![ContentBlock::text(
            serde_json::to_string_pretty(&j).unwrap_or_else(|_| j.to_string()),
        )]),
        Err(e) => CallToolResult::error(vec![ContentBlock::text(e)]),
    }
}

fn now_s() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

fn yes() -> bool {
    true
}

/// `wy/<site>/sys` and below, on any site.
pub fn is_sys(key: &str) -> bool {
    let mut s = key.split('/');
    s.next() == Some("wy") && s.next().is_some() && s.next() == Some("sys")
}

/// A full key: `wy/…` as given, anything else below `wy/<site>/`. `pattern` lets `*` and
/// `**` segments through (subscriptions); `~…` segments never.
pub fn full_key(site: &str, path: &str, pattern: bool) -> Result<String, String> {
    let p = path.trim().trim_matches('/');
    let key = if p == "wy" || p.starts_with("wy/") {
        p.to_owned()
    } else if p.is_empty() {
        format!("wy/{site}")
    } else {
        format!("wy/{site}/{p}")
    };
    if key.split('/').count() < 2 {
        return Err(format!("{key}: give a key below wy/<site>"));
    }
    for seg in key.split('/') {
        let wild = seg == "*" || seg == "**";
        if seg.is_empty()
            || seg.starts_with('~')
            || seg.contains(['$', '?', '#'])
            || (seg.contains('*') && !(pattern && wild))
        {
            return Err(format!(
                "{key}: give a node key (no empty or `~…` segments{})",
                if pattern {
                    ", wildcards only as whole `*` / `**` segments"
                } else {
                    ", no wildcards"
                }
            ));
        }
    }
    Ok(key)
}

#[derive(Deserialize, JsonSchema)]
pub struct NoParams {}

#[derive(Deserialize, JsonSchema)]
pub struct TreeParams {
    /// Node key, e.g. `downstream` (the links of this site), `wy/edge/downstream/modbus`,
    /// `dataflows`, `storage`, `sys`.
    pub path: String,
    /// Levels below `path` (default 1, at most 4).
    pub depth: Option<usize>,
}

#[derive(Deserialize, JsonSchema)]
pub struct PathParams {
    /// Node key.
    pub path: String,
}

#[derive(Deserialize, JsonSchema)]
pub struct GetParams {
    /// Node keys of points (no wildcards), at most 50.
    pub paths: Vec<String>,
    /// Seconds to wait for each value (default 3, at most 10).
    pub wait_s: Option<f64>,
}

#[derive(Deserialize, JsonSchema)]
pub struct WatchParams {
    /// A key or a pattern with `*` / `**` segments, e.g. `downstream/mock/**`.
    pub pattern: String,
    /// How long to collect (default 5 s, at most 60).
    pub seconds: Option<f64>,
    /// Most samples returned (default 200, at most 1000).
    pub max: Option<usize>,
}

#[derive(Deserialize, JsonSchema)]
pub struct HistoryParams {
    /// Node key of a point that has history (`node_meta` shows `has_history`).
    pub path: String,
    /// Spec 01 `~val?history=` arguments: `from` (RFC 3339 or `-1h`-style), `to`, `agg`
    /// (`avg`, `min`, `max`, `first`, `last`, `sum`, `count`), `window` (e.g. `5m`), `limit`.
    pub args: Map<String, Json>,
}

#[derive(Deserialize, JsonSchema)]
pub struct SetParams {
    /// Node key of the point.
    pub path: String,
    /// The new value as JSON; an enum takes its name or index.
    pub value: Json,
    /// Only check and show what would be sent (default true).
    #[serde(default = "yes")]
    pub dry_run: bool,
}

#[derive(Deserialize, JsonSchema)]
pub struct InvokeParams {
    /// Node key that declares the action.
    pub path: String,
    /// Action name (see `actions` in node_meta).
    pub action: String,
    /// Arguments by parameter name.
    #[serde(default)]
    pub args: Map<String, Json>,
    /// Only check and show what would be sent (default true).
    #[serde(default = "yes")]
    pub dry_run: bool,
}

#[derive(Deserialize, JsonSchema)]
pub struct FlowParams {
    /// The flow definition (spec 06): `{id, nodes, edges, …}`.
    pub def: Json,
    /// The site's flow engine, default `wy/<this site>/dataflows`.
    pub dataflows: Option<String>,
    /// Only validate (default true); a deploy sets the version one above the running one.
    #[serde(default = "yes")]
    pub dry_run: bool,
}

#[derive(Deserialize, JsonSchema)]
pub struct PlanParams {
    /// `{"steps": [...]}` or a list of steps. A step is one of
    /// `{"invoke": key, "action", "args", "unless"?: key, "ok_if_error"?: text}`,
    /// `{"set": key, "value"}`, `{"deploy": "wy/<site>/dataflows", "def"}`,
    /// `{"wait": key, "timeout_s"?}`, `{"expect": key, "equals"? | "min"?/"max"? | "changes"?,
    /// "timeout_s"?}`, `{"sleep_s": n}`. Keys are full (`wy/<site>/…`).
    pub plan: Json,
    /// false (default): check every step against the live tree; true: run them in order and
    /// stop at the first that fails.
    #[serde(default)]
    pub apply: bool,
}

#[derive(Deserialize, JsonSchema)]
pub struct SpecParams {
    /// `01-keyspace`, `02-meta`, `03-val`, `04-attachment`, `05-methods`, `06-flow-def`,
    /// `readme`, `tables`, `changelog`; empty for the list.
    pub section: Option<String>,
}

impl GatewayMcp {
    /// The Claude Desktop extension: log in with a password.
    pub fn new(opts: GatewayOptions) -> Self {
        Self::with_backend(Arc::new(PasswordBackend {
            opts,
            live: tokio::sync::Mutex::new(None),
        }))
    }

    pub fn with_backend(backend: Arc<dyn Backend>) -> Self {
        Self {
            backend,
            tool_router: Self::tool_router(),
        }
    }

    /// Log in now: a wrong password or an unreachable gateway shows at start.
    pub async fn check(&self) -> Result<Me, String> {
        Ok(self.live(&Extensions::default()).await?.me)
    }

    async fn live(&self, ext: &Extensions) -> Result<Session, String> {
        self.backend.session(ext).await
    }

    /// Run a read; once more on a new socket when the old one died under it.
    async fn read<F, Fut>(&self, ext: &Extensions, f: F) -> Out
    where
        F: Fn(Arc<Conn>, Me) -> Fut,
        Fut: Future<Output = Out>,
    {
        let s = self.live(ext).await?;
        let r = f(s.conn.clone(), s.me).await;
        if r.is_err() && s.conn.is_closed() {
            let s = self.live(ext).await?;
            return f(s.conn, s.me).await;
        }
        r
    }

    /// The session's switches, before anything is sent. `level` is what the request needs.
    fn gate(&self, s: &Session, key: &str, level: Perm) -> Result<(), String> {
        if s.read_only {
            return Err(format!(
                "{key}: this connector is read-only (its `read_only` setting); \
                 nothing was sent"
            ));
        }
        if (level >= Perm::Config || is_sys(key)) && !s.allow_config {
            return Err(format!(
                "{key}: a config-level change; this connector lets them through only with its \
                 `allow_config` setting on. Nothing was sent: ask the person to make this change \
                 in Studio, or to turn the setting on."
            ));
        }
        Ok(())
    }

    // ---------- tools ----------

    async fn do_whoami(&self, ext: &Extensions) -> Out {
        let s = self.live(ext).await?;
        let me = &s.me;
        Ok(json!({
            "gateway": self.backend.label(),
            "user": me.sub,
            "roles": me.roles,
            "site": me.site,
            "max": me.max,
            "grants": me.grants.iter().map(|(k, p)| json!({ "key": k, "level": p })).collect::<Vec<_>>(),
            "session_expires_in_s": me.exp.saturating_sub(now_s()),
            "connector": { "read_only": s.read_only, "allow_config": s.allow_config },
        }))
    }

    async fn do_tree(&self, ext: &Extensions, p: TreeParams) -> Out {
        let depth = p.depth.unwrap_or(1).clamp(1, 4);
        self.read(ext, |c, me| {
            let path = p.path.clone();
            async move {
                let key = full_key(&me.site, &path, false)?;
                let mut nodes = gw::tree(&c, &key, depth).await?;
                let truncated = nodes.len() > TREE_MAX;
                nodes.truncate(TREE_MAX);
                Ok(json!({ "key": key, "depth": depth, "nodes": nodes, "truncated": truncated }))
            }
        })
        .await
    }

    async fn do_meta(&self, ext: &Extensions, p: PathParams) -> Out {
        self.read(ext, |c, me| {
            let path = p.path.clone();
            async move {
                let key = full_key(&me.site, &path, false)?;
                let m = c.meta(&key).await.map_err(|e| e.to_string())?;
                if m == NodeMeta::default() {
                    return Err(format!("{key}: no such node (or not visible to this user)"));
                }
                let mut j = crate::json::meta_to_json(&m);
                j["key"] = json!(key);
                Ok(j)
            }
        })
        .await
    }

    async fn do_get(&self, ext: &Extensions, p: GetParams) -> Out {
        if p.paths.len() > GET_MAX {
            return Err(format!("at most {GET_MAX} paths per call"));
        }
        let wait = Duration::from_secs_f64(p.wait_s.unwrap_or(3.0).clamp(0.2, 10.0));
        self.read(ext, |c, me| {
            let paths = p.paths.clone();
            async move {
                let mut set = tokio::task::JoinSet::new();
                for (i, path) in paths.into_iter().enumerate() {
                    let c = c.clone();
                    let site = me.site.clone();
                    set.spawn(async move {
                        let r = match full_key(&site, &path, false) {
                            Ok(key) => gw::get(&c, &key, wait).await,
                            Err(e) => Err(e),
                        };
                        (i, path, r)
                    });
                }
                let mut rows = Vec::new();
                while let Some(r) = set.join_next().await {
                    if let Ok(r) = r {
                        rows.push(r);
                    }
                }
                rows.sort_by_key(|(i, ..)| *i);
                if c.is_closed() {
                    return Err("the gateway connection closed".into());
                }
                let mut out = Map::new();
                for (_, path, r) in rows {
                    let v = match r {
                        Ok(mut j) => {
                            if let Some(o) = j.as_object_mut() {
                                o.remove("key");
                            }
                            j
                        }
                        Err(e) => json!({ "error": e }),
                    };
                    out.insert(path, v);
                }
                Ok(Json::Object(out))
            }
        })
        .await
    }

    async fn do_watch(&self, ext: &Extensions, p: WatchParams) -> Out {
        let seconds = p.seconds.unwrap_or(5.0).clamp(0.1, WATCH_MAX_S);
        let max = p.max.unwrap_or(200).clamp(1, WATCH_SAMPLES_MAX);
        self.read(ext, |c, me| {
            let pattern = p.pattern.clone();
            async move {
                let key = full_key(&me.site, &pattern, true)?;
                let mut s = gw::watch(&c, &key, seconds).await?;
                let total = s.len();
                s.truncate(max);
                Ok(json!({ "pattern": key, "seconds": seconds, "samples": s, "total": total }))
            }
        })
        .await
    }

    async fn do_history(&self, ext: &Extensions, p: HistoryParams) -> Out {
        let args = json_to_value(&Json::Object(p.args))?;
        self.read(ext, |c, me| {
            let path = p.path.clone();
            let args = args.clone();
            async move {
                let key = full_key(&me.site, &path, false)?;
                Ok(json!({ "key": key, "rows": gw::history(&c, &key, args).await? }))
            }
        })
        .await
    }

    async fn do_set(&self, ext: &Extensions, p: SetParams) -> Out {
        let sess = self.live(ext).await?;
        let (c, me) = (sess.conn.clone(), sess.me.clone());
        let key = full_key(&me.site, &p.path, false)?;
        let m = c.meta(&key).await.map_err(|e| e.to_string())?;
        if m == NodeMeta::default() {
            return Err(format!("{key}: no such node (or not visible to this user)"));
        }
        let level = crate::check::set_level(&m)?;
        let v = gw::set_value(&m, &p.value)?;
        let plan = json!({
            "op": "set", "key": key, "value": value_to_json(&v),
            "level": level.name(), "as_user": me.sub,
        });
        if p.dry_run {
            let gate = self.gate(&sess, &key, level).err();
            return Ok(
                json!({ "dry_run": true, "would_send": plan, "refused_by_connector": gate }),
            );
        }
        self.gate(&sess, &key, level)?;
        let r = gw::set(&c, &key, v).await?;
        Ok(json!({ "sent": plan, "result": r }))
    }

    async fn do_invoke(&self, ext: &Extensions, p: InvokeParams) -> Out {
        let sess = self.live(ext).await?;
        let (c, me) = (sess.conn.clone(), sess.me.clone());
        let key = full_key(&me.site, &p.path, false)?;
        let m = c.meta(&key).await.map_err(|e| e.to_string())?;
        if m == NodeMeta::default() {
            return Err(format!("{key}: no such node (or not visible to this user)"));
        }
        let (level_name, args) = gw::invoke_args(&m, &p.action, &Json::Object(p.args))?;
        let level = crate::check::action_level(&m, &p.action)?;
        let plan = json!({
            "op": "invoke", "key": key, "action": p.action, "args": value_to_json(&args),
            "level": level_name, "as_user": me.sub,
        });
        if p.dry_run {
            let gate = self.gate(&sess, &key, level).err();
            return Ok(
                json!({ "dry_run": true, "would_send": plan, "refused_by_connector": gate }),
            );
        }
        self.gate(&sess, &key, level)?;
        let r = gw::invoke(&c, &key, &p.action, args).await?;
        Ok(json!({ "sent": plan, "result": r["result"] }))
    }

    async fn do_flow(&self, ext: &Extensions, p: FlowParams) -> Out {
        let sess = self.live(ext).await?;
        let (c, me) = (sess.conn.clone(), sess.me.clone());
        let dataflows = full_key(
            &me.site,
            p.dataflows.as_deref().unwrap_or("dataflows"),
            false,
        )?;
        let step = Step::Deploy {
            dataflows: dataflows.clone(),
            def: p.def,
        };
        let check = gw::check_step(&c, &step).await;
        if p.dry_run || check["check"] == json!("error") {
            let gate = self.gate(&sess, &dataflows, Perm::Config).err();
            return Ok(json!({ "dry_run": true, "check": check, "refused_by_connector": gate }));
        }
        self.gate(&sess, &dataflows, Perm::Config)?;
        gw::run_step(&c, &step).await
    }

    /// The level a step needs, read from the live `~meta` (`None`: nothing is written).
    async fn step_level(c: &Conn, step: &Step) -> Result<Option<(String, Perm)>, String> {
        let meta = |k: String| async move {
            let m = c.meta(&k).await.map_err(|e| e.to_string())?;
            Ok::<_, String>((k, m))
        };
        Ok(match step {
            Step::Invoke { key, action, .. } => {
                let (k, m) = meta(key.clone()).await?;
                // a node that is not there yet: the strictest level until it is
                let level = crate::check::action_level(&m, action).unwrap_or(Perm::Config);
                Some((k, level))
            }
            Step::Set { key, .. } => {
                let (k, m) = meta(key.clone()).await?;
                Some((k, crate::check::set_level(&m).unwrap_or(Perm::Config)))
            }
            Step::Deploy { dataflows, .. } => Some((dataflows.clone(), Perm::Config)),
            Step::Wait { .. } | Step::Expect { .. } | Step::Sleep(_) => None,
        })
    }

    async fn do_plan(&self, ext: &Extensions, p: PlanParams) -> Out {
        let steps = gw::parse_plan(&p.plan)?;
        let sess = self.live(ext).await?;
        let c = sess.conn.clone();
        if !p.apply {
            let mut out = Vec::new();
            let mut ok = true;
            for s in &steps {
                let mut j = gw::check_step(&c, s).await;
                ok &= j["check"] != json!("error");
                if let Some((k, level)) = Self::step_level(&c, s).await? {
                    if let Err(e) = self.gate(&sess, &k, level) {
                        j["refused_by_connector"] = json!(e);
                        ok = false;
                    }
                }
                out.push(j);
            }
            return Ok(json!({ "steps": out, "checked": ok, "applied": false }));
        }
        let mut out = Vec::new();
        for (i, s) in steps.iter().enumerate() {
            // checked again before each step: an earlier one may have made the node
            let r = match Self::step_level(&c, s).await? {
                Some((k, level)) => match self.gate(&sess, &k, level) {
                    Ok(()) => gw::run_step(&c, s).await,
                    Err(e) => Err(e),
                },
                None => gw::run_step(&c, s).await,
            };
            match r {
                Ok(j) => out.push(j),
                Err(e) => {
                    out.push(json!({ "step": i + 1, "error": e }));
                    return Ok(json!({ "steps": out, "applied": false, "failed_at": i + 1 }));
                }
            }
        }
        Ok(json!({ "steps": out, "applied": true }))
    }
}

#[tool_router]
impl GatewayMcp {
    #[tool(
        description = "Who this connector is on the gateway: user, roles, grants (key patterns and levels), the gateway's own site, the session's expiry, and the connector's read_only / allow_config settings. Call it first.",
        annotations(read_only_hint = true)
    )]
    async fn whoami(
        &self,
        Parameters(_): Parameters<NoParams>,
        ctx: RequestContext<RoleServer>,
    ) -> CallToolResult {
        done(self.do_whoami(&ctx.extensions).await)
    }

    #[tool(
        description = "The nodes below a key, `depth` levels (1–4): key, type, unit, writable. `downstream` lists this site's links, `dataflows` its flows, `storage` the broker storage, `upstream`/`downstream` peer brokers; `wy/<site>/…` reaches other sites.",
        annotations(read_only_hint = true)
    )]
    async fn tree_list(
        &self,
        Parameters(p): Parameters<TreeParams>,
        ctx: RequestContext<RoleServer>,
    ) -> CallToolResult {
        done(self.do_tree(&ctx.extensions, p).await)
    }

    #[tool(
        description = "Full ~meta of a node: type, unit, enum, writable level, cfg (min/max…), attributes, history mark, actions with parameter schemas and levels.",
        annotations(read_only_hint = true)
    )]
    async fn node_meta(
        &self,
        Parameters(p): Parameters<PathParams>,
        ctx: RequestContext<RoleServer>,
    ) -> CallToolResult {
        done(self.do_meta(&ctx.extensions, p).await)
    }

    #[tool(
        description = "Current values of up to 50 points: {path: {v, q, t}} with quality q (good|uncertain|bad) and t in microseconds since the Unix epoch, or {error}.",
        annotations(read_only_hint = true)
    )]
    async fn value_get(
        &self,
        Parameters(p): Parameters<GetParams>,
        ctx: RequestContext<RoleServer>,
    ) -> CallToolResult {
        done(self.do_get(&ctx.extensions, p).await)
    }

    #[tool(
        description = "Samples of a key or a pattern (`downstream/mock/**`) over a few seconds (≤ 60): how values move.",
        annotations(read_only_hint = true)
    )]
    async fn value_watch(
        &self,
        Parameters(p): Parameters<WatchParams>,
        ctx: RequestContext<RoleServer>,
    ) -> CallToolResult {
        done(self.do_watch(&ctx.extensions, p).await)
    }

    #[tool(
        description = "Recorded values of a point from the broker's historian (spec 01 `~val?history=`): raw rows [t, v, q] or rollups [t_start, v] with `agg` and `window`.",
        annotations(read_only_hint = true)
    )]
    async fn history(
        &self,
        Parameters(p): Parameters<HistoryParams>,
        ctx: RequestContext<RoleServer>,
    ) -> CallToolResult {
        done(self.do_history(&ctx.extensions, p).await)
    }

    #[tool(
        description = "Write a value to a point (~set). ALWAYS call with dry_run=true first (the default): it checks the value against ~meta (type, enum, min/max, writable level) and shows what would be sent; show it to the person, then call again with dry_run=false. The gateway user's role decides; the connector's read_only / allow_config settings can refuse first.",
        annotations(
            read_only_hint = false,
            destructive_hint = true,
            idempotent_hint = true
        )
    )]
    async fn node_set(
        &self,
        Parameters(p): Parameters<SetParams>,
        ctx: RequestContext<RoleServer>,
    ) -> CallToolResult {
        done(self.do_set(&ctx.extensions, p).await)
    }

    #[tool(
        description = "Run an action (~act/<action>) of a node: add a connection or device, edit, remove, restart, set up history, … ALWAYS call with dry_run=true first (the default): it checks the arguments against the action's schema and level and shows what would be sent; show it to the person, then call again with dry_run=false.",
        annotations(read_only_hint = false, destructive_hint = true)
    )]
    async fn action_invoke(
        &self,
        Parameters(p): Parameters<InvokeParams>,
        ctx: RequestContext<RoleServer>,
    ) -> CallToolResult {
        done(self.do_invoke(&ctx.extensions, p).await)
    }

    #[tool(
        description = "Validate (dry_run=true, the default) or deploy a flow definition (spec 06) on a site's flow engine; a deploy sets the version one above the running one. A deploy is config-level: the flow then acts on its targets within this user's rights (ADR 0008).",
        annotations(read_only_hint = false, destructive_hint = true)
    )]
    async fn flow_deploy(
        &self,
        Parameters(p): Parameters<FlowParams>,
        ctx: RequestContext<RoleServer>,
    ) -> CallToolResult {
        done(self.do_flow(&ctx.extensions, p).await)
    }

    #[tool(
        description = "A plan of steps that build on each other (invoke, set, deploy, wait for a node, expect a value, sleep). apply=false (the default) checks every step against the live tree; apply=true runs them in order and stops at the first that fails. Check first, show the person, then apply.",
        annotations(read_only_hint = false, destructive_hint = true)
    )]
    async fn plan_run(
        &self,
        Parameters(p): Parameters<PlanParams>,
        ctx: RequestContext<RoleServer>,
    ) -> CallToolResult {
        done(self.do_plan(&ctx.extensions, p).await)
    }

    #[tool(
        description = "The normative WYRM spec: 01 keyspace, 02 meta, 03 val, 04 attachment, 05 methods, 06 flow-def, readme, tables, changelog. Without a section: the list.",
        annotations(read_only_hint = true)
    )]
    async fn spec(&self, Parameters(p): Parameters<SpecParams>) -> CallToolResult {
        let r = match p.section.as_deref().filter(|s| !s.trim().is_empty()) {
            None => Ok(Json::Array(
                spec::FILES
                    .iter()
                    .map(|f| json!({ "section": f.file, "title": f.title, "uri": spec::uri(f) }))
                    .collect(),
            )),
            Some(s) => match spec::find(s) {
                Some(f) => return CallToolResult::success(vec![ContentBlock::text(f.text)]),
                None => Err(format!("no spec section {s:?}")),
            },
        };
        done(r)
    }
}

#[tool_handler(router = self.tool_router)]
impl ServerHandler for GatewayMcp {
    fn get_info(&self) -> ServerConfig {
        ServerConfig::new(
            ServerCapabilities::builder()
                .enable_tools()
                .enable_resources()
                .build(),
        )
        .with_server_info(Implementation::new("wyrm-mcp", env!("CARGO_PKG_VERSION")))
        .with_instructions(INSTRUCTIONS)
    }

    async fn list_resources(
        &self,
        _request: Option<PaginatedRequestParams>,
        _context: RequestContext<RoleServer>,
    ) -> Result<ListResourcesResult, McpError> {
        Ok(ListResourcesResult::with_all_items(
            spec::FILES
                .iter()
                .map(|f| {
                    Resource::new(spec::uri(f), f.file)
                        .with_title(f.title)
                        .with_mime_type(spec::mime(f.file))
                        .with_size(f.text.len() as u64)
                })
                .collect(),
        ))
    }

    async fn read_resource(
        &self,
        request: ReadResourceRequestParams,
        _context: RequestContext<RoleServer>,
    ) -> Result<ReadResourceResponse, McpError> {
        let f = request
            .uri
            .strip_prefix(spec::URI_PREFIX)
            .and_then(|file| spec::FILES.iter().find(|f| f.file == file))
            .ok_or_else(|| McpError::resource_not_found(request.uri.clone(), None))?;
        Ok(ReadResourceResult::new(vec![
            ResourceContents::text(f.text, request.uri).with_mime_type(spec::mime(f.file))
        ])
        .into())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn keys_resolve_against_the_gateway_site() {
        assert_eq!(
            full_key("edge", "downstream/mock", false).unwrap(),
            "wy/edge/downstream/mock"
        );
        assert_eq!(
            full_key("edge", "/wy/plant/sys/", false).unwrap(),
            "wy/plant/sys"
        );
        assert_eq!(full_key("edge", "", false).unwrap(), "wy/edge");
        assert_eq!(
            full_key("edge", "downstream/mock/**", true).unwrap(),
            "wy/edge/downstream/mock/**"
        );
        for bad in ["downstream/m/~val", "downstream/*", "a//b", "x?y", "down*"] {
            assert!(full_key("edge", bad, false).is_err(), "{bad}");
        }
        assert!(full_key("edge", "down*/x", true).is_err());
    }

    #[test]
    fn sys_on_any_site() {
        assert!(is_sys("wy/edge/sys"));
        assert!(is_sys("wy/plant/sys/links/m"));
        assert!(!is_sys("wy/edge/downstream/sys"));
        assert!(!is_sys("wy/edge/system"));
    }
}
