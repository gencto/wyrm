//! The MCP server: tools over `WyrmClient`, spec resources.
//!
//! Safety model (ADR 0005): the server signs its own requests as
//! `ai:<agent>` with `max = write`, so it can never perform a `config`
//! operation by itself. Config-level operations (a node with
//! `writable = config`, an action with level `config`, anything under
//! `wy/<site>/sys/**`, a flow deploy) go out only with an `approval`: a `ptok`
//! that a human operator minted for exactly that request key. The server
//! sends it as the request's `ptok` in place of its own, so the responder
//! checks the human's rights, and the audit names the human.

use crate::check::{self, ApprovalInfo};
use crate::json::{
    action_json, json_to_value, meta_to_json, profile_to_json, sample_to_json, value_to_json,
};
use crate::spec;
use ed25519_dalek::SigningKey;
use rmcp::handler::server::router::tool::ToolRouter;
use rmcp::handler::server::wrapper::Parameters;
use rmcp::model::{
    CallToolResult, ContentBlock, Implementation, ListResourcesResult, PaginatedRequestParams,
    ReadResourceRequestParams, ReadResourceResponse, ReadResourceResult, Resource,
    ResourceContents, ServerCapabilities, ServerConfig,
};
use rmcp::service::RequestContext;
use rmcp::{tool, tool_handler, tool_router, ErrorData as McpError, RoleServer, ServerHandler};
use schemars::JsonSchema;
use serde::Deserialize;
use serde_json::{json, Map, Value as Json};
use std::collections::BTreeMap;
use std::sync::Arc;
use std::time::Duration;
use wyrm_client::{SigningTokens, TokenSource, WyrmClient};
use wyrm_core::profile::ProfileDef;
use wyrm_core::{Attachment, Perm, Sample, StatusGroup, Value};
use zenoh::query::ConsolidationMode;

/// Most children returned by one `tree_list` call.
const LIST_LIMIT_MAX: usize = 1000;
const LIST_LIMIT_DEFAULT: usize = 100;
/// Most paths in one `value_get`.
const VALUE_GET_MAX: usize = 200;
/// Most replies collected from a streaming action.
const STREAM_MAX: usize = 1000;

const INSTRUCTIONS: &str = "WYRM broker (IOT-DSA semantics on Zenoh). Node keys are \
`wy/<site>/downstream/<link>/<path>`; paths without `wy/` are taken relative to this server's site. \
Navigate with tree_list / tree_resolve / node_meta, read with value_get. Changes: call node_set or \
action_invoke with dry_run=true first (the default), show the plan, then repeat with \
dry_run=false. This server acts as an AI service account with at most `write` rights. \
Config-level operations (writable=config, action level config, anything under wy/<site>/sys/**, \
flow deploys) need `approval`: a base64 ptok that a human operator minted for exactly that \
request key with an admin signing key. Never invent approvals; ask the operator for one. The `spec` tool and \
wy://spec/* resources hold the normative protocol.";

fn yes() -> bool {
    true
}

#[derive(Deserialize, JsonSchema)]
pub struct TreeListParams {
    /// Node key, e.g. `wy/plant/downstream/mock` (`wy/<site>/downstream` lists links).
    pub path: String,
    /// Index of the first child to return (default 0).
    pub from: Option<usize>,
    /// Most children to return (default 100, at most 1000).
    pub limit: Option<usize>,
}

#[derive(Deserialize, JsonSchema)]
pub struct TreeResolveParams {
    /// Node key under which to search.
    pub path: String,
    /// Filter on `~meta` fields, e.g. `type:1;unit:°C` (spec 05).
    #[serde(rename = "match")]
    pub matcher: Option<String>,
    /// Most levels below `path`.
    pub depth: Option<usize>,
}

#[derive(Deserialize, JsonSchema)]
pub struct NodeMetaParams {
    /// Node key.
    pub path: String,
    /// Fold the profile chain (`is`) into the result.
    #[serde(default)]
    pub expand: bool,
}

#[derive(Deserialize, JsonSchema)]
pub struct ValueGetParams {
    /// Node keys (exact, no wildcards), at most 200.
    pub paths: Vec<String>,
}

/// No `Debug`: carries an approval token.
#[derive(Deserialize, JsonSchema)]
pub struct NodeSetParams {
    /// Node key of the point.
    pub path: String,
    /// New value as JSON. Enums accept the name or the index; binary is
    /// `{"$bytes": "<base64>"}`.
    pub value: Json,
    /// Only validate and show what would be sent (default true).
    #[serde(default = "yes")]
    pub dry_run: bool,
    /// Base64 ptok from a human operator for exactly `<path>/~set`.
    pub approval: Option<String>,
}

/// No `Debug`: carries an approval token.
#[derive(Deserialize, JsonSchema)]
pub struct ActionInvokeParams {
    /// Node key that declares the action.
    pub path: String,
    /// Action name (see `actions` in node_meta).
    pub action: String,
    /// Arguments by parameter name.
    #[serde(default)]
    pub args: Map<String, Json>,
    /// Only validate and show what would be sent (default true).
    #[serde(default = "yes")]
    pub dry_run: bool,
    /// Base64 ptok from a human operator for exactly `<path>/~act/<action>`.
    pub approval: Option<String>,
}

#[derive(Deserialize, JsonSchema)]
pub struct ProfilesParams {
    /// Case-insensitive substring of the profile name.
    pub filter: Option<String>,
}

#[derive(Deserialize, JsonSchema)]
pub struct FlowIdParams {
    /// Flow id.
    pub id: String,
}

#[derive(Deserialize, JsonSchema)]
pub struct FlowDefParams {
    /// Flow definition (spec 06) as a JSON object.
    pub def: Map<String, Json>,
}

/// No `Debug`: carries approval tokens.
#[derive(Deserialize, JsonSchema)]
pub struct FlowApplyParams {
    /// Flow definition (spec 06) as a JSON object.
    pub def: Map<String, Json>,
    /// Only compile and list the command targets (default true).
    #[serde(default = "yes")]
    pub dry_run: bool,
    /// Base64 ptok from a human operator for exactly `wy/<site>/dataflows/~act/deploy`.
    pub approval: Option<String>,
    /// One base64 ptok per command target, `{target_key: token}`, minted by the
    /// same operator as `approval` for exactly that key (level >= write).
    #[serde(default)]
    pub proofs: BTreeMap<String, String>,
}

#[derive(Deserialize, JsonSchema)]
pub struct LinkStatusParams {
    /// Link id (`wy/<site>/downstream/<link>`).
    pub link: String,
}

#[derive(Deserialize, JsonSchema)]
pub struct SpecParams {
    /// `01`…`06`, a name (`keyspace`, `meta`, `val`, `attachment`, `methods`,
    /// `flow-def`), `readme`, `tables` or `changelog`. Empty: the list.
    pub section: Option<String>,
}

/// Server options.
pub struct Options {
    /// Site this server works on (`wy/<site>/…`).
    pub site: String,
    /// Agent name; requests are signed with subject `ai:<name>`.
    pub agent_name: String,
    /// Service signing key; `None` = read-only (no ptok on any request).
    pub key: Option<SigningKey>,
    /// Timeout of direct reads (`~val`, `~def`, profiles, liveliness).
    pub timeout: Duration,
}

struct Inner {
    client: WyrmClient,
    site: String,
    agent_sub: String,
    timeout: Duration,
    can_sign: bool,
}

#[derive(Clone)]
pub struct WyrmMcp {
    inner: Arc<Inner>,
    tool_router: ToolRouter<Self>,
}

/// Token source with exactly one token for exactly one key (a human approval).
struct OneKey {
    key: String,
    tok: Vec<u8>,
}

impl TokenSource for OneKey {
    fn token(&self, key: &str) -> Option<Vec<u8>> {
        (key == self.key).then(|| self.tok.clone())
    }
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

fn err(e: impl std::fmt::Display) -> String {
    e.to_string()
}

impl WyrmMcp {
    /// `client` should have no token source: the server sets its own.
    pub fn new(client: WyrmClient, opts: Options) -> Self {
        let agent_sub = format!("ai:{}", opts.agent_name);
        let can_sign = opts.key.is_some();
        let client = match opts.key {
            Some(key) => client.with_tokens(Arc::new(
                SigningTokens::new(key, opts.site.clone())
                    .subject(agent_sub.clone())
                    .max(Perm::Write),
            )),
            None => client,
        };
        Self {
            inner: Arc::new(Inner {
                client,
                site: opts.site,
                agent_sub,
                timeout: opts.timeout,
                can_sign,
            }),
            tool_router: Self::tool_router(),
        }
    }

    fn site(&self) -> &str {
        &self.inner.site
    }

    fn client(&self) -> &WyrmClient {
        &self.inner.client
    }

    /// Full node key: `wy/<site>/…` (must be this site) or relative to it.
    /// No suffix segments (`~meta`, …), no wildcards.
    fn node_key(&self, path: &str) -> Result<String, String> {
        let p = path.trim().trim_matches('/');
        let root = format!("wy/{}", self.site());
        let key = if p == "wy" || p.starts_with("wy/") {
            if p != root && !p.starts_with(&format!("{root}/")) {
                return Err(format!(
                    "{p}: this server serves site {:?} only",
                    self.site()
                ));
            }
            p.to_owned()
        } else if p.is_empty() {
            root
        } else {
            format!("{root}/{p}")
        };
        for seg in key.split('/') {
            if seg.is_empty() || seg.starts_with('~') || seg.contains(['*', '$', '?', '#']) {
                return Err(format!(
                    "{key}: give a node key (no empty, `~…` or wildcard segments)"
                ));
            }
        }
        Ok(key)
    }

    /// One reply of a plain `get` (no ptok): `(attachment, payload)`.
    async fn get_one(
        &self,
        key: &str,
        ptok: Option<Vec<u8>>,
    ) -> Result<(Attachment, Vec<u8>), String> {
        let att = Attachment {
            ptok,
            ..Default::default()
        };
        let rx = self
            .client()
            .session()
            .get(key)
            .timeout(self.inner.timeout)
            .attachment(wyrm_core::codec::to_vec(&att).map_err(err)?)
            .await
            .map_err(err)?;
        let reply = rx
            .recv_async()
            .await
            .map_err(|_| format!("{key}: no reply"))?;
        let s = reply.result().map_err(|e| {
            format!(
                "{key}: {}",
                String::from_utf8_lossy(&e.payload().to_bytes())
            )
        })?;
        let att: Attachment = match s.attachment() {
            Some(a) => wyrm_core::codec::from_slice(&a.to_bytes()).map_err(err)?,
            None => Attachment::default(),
        };
        if let Some(st) = att.status.filter(|s| s.group() == StatusGroup::Error) {
            return Err(format!(
                "{key}: {st:?} {}",
                att.err.clone().unwrap_or_default()
            ));
        }
        Ok((att, s.payload().to_bytes().to_vec()))
    }

    /// Current `~val` of `node` (storage or the owner).
    async fn read_val(&self, node: &str) -> Result<Sample, String> {
        let (_, p) = self.get_one(&format!("{node}/~val"), None).await?;
        wyrm_core::codec::from_slice(&p).map_err(|e| format!("{node}/~val: {e}"))
    }

    async fn alive(&self, key: &str) -> bool {
        match self
            .client()
            .session()
            .liveliness()
            .get(key)
            .timeout(Duration::from_secs(1))
            .await
        {
            Ok(rx) => rx.recv_async().await.is_ok_and(|r| r.result().is_ok()),
            Err(_) => false,
        }
    }

    /// Decode and pre-check an approval for `key` at `need`, bound to `payload` (a request's
    /// approval) or not (a flow's proof of rights on a target).
    fn approval(
        &self,
        b64: &str,
        key: &str,
        need: Perm,
        payload: Option<&[u8]>,
    ) -> Result<(Vec<u8>, ApprovalInfo), String> {
        let tok = check::decode_token(b64)?;
        let info = check::precheck_approval(&tok, key, self.site(), need, payload)?;
        Ok((tok, info))
    }

    fn approval_json(info: &ApprovalInfo) -> Json {
        json!({ "sub": info.sub, "level": info.perm.name(), "expires_in_s": info.expires_in_s })
    }

    /// The client for a real request: the human's token for exactly `key`, or
    /// the service account.
    fn sender(&self, approval: Option<(Vec<u8>, String)>) -> Result<WyrmClient, String> {
        match approval {
            Some((tok, key)) => {
                // Audited as `<human>/ai:<agent>`: approved by a person,
                // requested by the AI.
                let origin =
                    check::token_subject(&tok).map(|sub| format!("{sub}/{}", self.inner.agent_sub));
                let mut c = self
                    .client()
                    .clone()
                    .with_tokens(Arc::new(OneKey { key, tok }));
                if let Some(o) = origin {
                    c = c.with_origin(o);
                }
                Ok(c)
            }
            None if self.inner.can_sign => Ok(self.client().clone()),
            None => Err("this server has no signing key (--key); it can only read".into()),
        }
    }

    fn ptok_label(&self, approval: Option<&ApprovalInfo>) -> String {
        match approval {
            Some(a) => format!("approval of {}", a.sub),
            None => format!("service account {} (max write)", self.inner.agent_sub),
        }
    }

    // ---------- tools ----------

    async fn do_tree_list(&self, p: TreeListParams) -> Out {
        let node = self.node_key(&p.path)?;
        let kids = self.client().children(&node).await.map_err(err)?;
        let total = kids.len();
        let from = p.from.unwrap_or(0).min(total);
        let limit = p
            .limit
            .unwrap_or(LIST_LIMIT_DEFAULT)
            .clamp(1, LIST_LIMIT_MAX);
        let items: Vec<Json> = kids
            .into_iter()
            .skip(from)
            .take(limit)
            .map(|c| {
                let mut m = meta_to_json(&c.meta);
                if let Json::Object(o) = &mut m {
                    o.insert("name".into(), c.name.clone().into());
                    o.insert("path".into(), format!("{node}/{}", c.name).into());
                }
                m
            })
            .collect();
        let next = (from + items.len() < total).then_some(from + items.len());
        Ok(json!({ "path": node, "total": total, "from": from, "next": next, "children": items }))
    }

    async fn do_tree_resolve(&self, p: TreeResolveParams) -> Out {
        let node = self.node_key(&p.path)?;
        let keys = self
            .client()
            .resolve(&node, p.matcher.as_deref(), p.depth)
            .await
            .map_err(err)?;
        Ok(json!({ "path": node, "count": keys.len(), "keys": keys }))
    }

    async fn do_node_meta(&self, p: NodeMetaParams) -> Out {
        let node = self.node_key(&p.path)?;
        let m = if p.expand {
            self.client().meta_expanded(&node).await
        } else {
            self.client().meta(&node).await
        }
        .map_err(err)?;
        let mut j = meta_to_json(&m);
        if let Json::Object(o) = &mut j {
            o.insert("path".into(), node.into());
        }
        Ok(j)
    }

    async fn do_value_get(&self, p: ValueGetParams) -> Out {
        if p.paths.len() > VALUE_GET_MAX {
            return Err(format!("at most {VALUE_GET_MAX} paths per call"));
        }
        let mut out = Map::new();
        for path in &p.paths {
            let r = match self.node_key(path) {
                Ok(node) => self
                    .read_val(&node)
                    .await
                    .map(|s| sample_to_json(&s))
                    .unwrap_or_else(|e| json!({ "error": e })),
                Err(e) => json!({ "error": e }),
            };
            out.insert(path.clone(), r);
        }
        Ok(Json::Object(out))
    }

    async fn do_node_set(&self, p: NodeSetParams) -> Out {
        let node = self.node_key(&p.path)?;
        let key = format!("{node}/~set");
        let meta = self.client().meta_expanded(&node).await.map_err(err)?;
        let mut level = check::set_level(&meta)?;
        if check::is_control_plane(self.site(), &node) {
            level = Perm::Config;
        }
        let v = check::coerce_enum(
            meta.ty,
            meta.enum_values.as_deref(),
            json_to_value(&p.value)?,
        );
        check::validate_value(&meta, &v)?;
        let needs_approval = level >= Perm::Config;
        tracing::debug!(tool = "node_set", %key, dry_run = p.dry_run, "request");
        // what the client sends for this set (wyrm-client: `SetRequest`), as an approval binds it
        let payload =
            wyrm_core::codec::to_vec(&wyrm_core::SetRequest { v: v.clone() }).map_err(err)?;
        let approval = match &p.approval {
            Some(a) => Some(self.approval(a, &key, level, Some(&payload))?),
            None => None,
        };
        if p.dry_run {
            let current = self.read_val(&node).await.ok().map(|s| sample_to_json(&s));
            return Ok(json!({
                "dry_run": true,
                "valid": true,
                "level": level.name(),
                "requires_approval": needs_approval,
                "approval": approval.as_ref().map(|(_, i)| Self::approval_json(i)),
                "current": current,
                "would_send": {
                    "op": "set",
                    "key": key,
                    "payload": { "v": value_to_json(&v) },
                    "args_sha256": check::payload_sha256(&payload),
                    "ptok": self.ptok_label(approval.as_ref().map(|(_, i)| i)),
                },
            }));
        }
        if needs_approval && approval.is_none() {
            return Err(format!(
                "{key} is config-level: dry_run=false needs `approval`, a ptok a human operator \
                 minted for exactly this key"
            ));
        }
        let by = self.ptok_label(approval.as_ref().map(|(_, i)| i));
        let sender = self.sender(approval.map(|(t, _)| (t, key.clone())))?;
        sender.set(&node, v.clone()).await.map_err(err)?;
        Ok(json!({ "ok": true, "key": key, "value": value_to_json(&v), "sent_as": by }))
    }

    async fn do_action_invoke(&self, p: ActionInvokeParams) -> Out {
        let node = self.node_key(&p.path)?;
        wyrm_core::keyspace::validate_segment(&p.action).map_err(err)?;
        let key = format!("{node}/~act/{}", p.action);
        let meta = self.client().meta_expanded(&node).await.map_err(err)?;
        let mut level = check::action_level(&meta, &p.action)?;
        if check::is_control_plane(self.site(), &node) {
            level = Perm::Config;
        }
        let act = meta
            .actions
            .as_ref()
            .and_then(|a| a.get(&p.action))
            .cloned()
            .unwrap_or_default();
        let given = p
            .args
            .iter()
            .map(|(k, v)| json_to_value(v).map(|v| (k.clone(), v)))
            .collect::<Result<BTreeMap<_, _>, _>>()?;
        let args = check::prepare_args(&act.params, given)?;
        let needs_approval = level >= Perm::Config;
        tracing::debug!(tool = "action_invoke", %key, dry_run = p.dry_run, "request");
        let args = Value::Map(args);
        let payload = wyrm_core::codec::to_vec(&args).map_err(err)?;
        let approval = match &p.approval {
            Some(a) => Some(self.approval(a, &key, level, Some(&payload))?),
            None => None,
        };
        if p.dry_run {
            return Ok(json!({
                "dry_run": true,
                "valid": true,
                "level": level.name(),
                "requires_approval": needs_approval,
                "approval": approval.as_ref().map(|(_, i)| Self::approval_json(i)),
                "action": action_json(&act),
                "would_send": {
                    "op": "invoke",
                    "key": key,
                    "args": value_to_json(&args),
                    "args_sha256": check::payload_sha256(&payload),
                    "ptok": self.ptok_label(approval.as_ref().map(|(_, i)| i)),
                },
            }));
        }
        if needs_approval && approval.is_none() {
            return Err(format!(
                "{key} is config-level: dry_run=false needs `approval`, a ptok a human operator \
                 minted for exactly this key"
            ));
        }
        let by = self.ptok_label(approval.as_ref().map(|(_, i)| i));
        let sender = self.sender(approval.map(|(t, _)| (t, key.clone())))?;
        let stream =
            act.stream == Some(true) || act.result == Some(wyrm_core::meta::ActionResult::Stream);
        let mut s = sender.invoke(&node, &p.action, args).await.map_err(err)?;
        let mut results = Vec::new();
        let mut truncated = false;
        while let Some(item) = s.next().await {
            if let Some(v) = item.map_err(err)? {
                results.push(value_to_json(&v));
            }
            if results.len() >= STREAM_MAX {
                truncated = true;
                break;
            }
        }
        Ok(if stream {
            json!({ "ok": true, "key": key, "results": results, "truncated": truncated, "sent_as": by })
        } else {
            json!({ "ok": true, "key": key, "result": results.into_iter().next(), "sent_as": by })
        })
    }

    async fn do_profiles(&self, p: ProfilesParams) -> Out {
        let prefix = format!("wy/{}/pub/", self.site());
        let rx = self
            .client()
            .session()
            .get(format!("{prefix}*/~meta"))
            .consolidation(ConsolidationMode::None)
            .timeout(self.inner.timeout)
            .await
            .map_err(err)?;
        let filter = p.filter.map(|f| f.to_lowercase());
        let mut found = BTreeMap::new();
        while let Ok(r) = rx.recv_async().await {
            let Ok(s) = r.result() else { continue };
            let Some(name) = s
                .key_expr()
                .as_str()
                .strip_prefix(&prefix)
                .and_then(|r| r.strip_suffix("/~meta"))
            else {
                continue;
            };
            if filter
                .as_ref()
                .is_some_and(|f| !name.to_lowercase().contains(f))
            {
                continue;
            }
            if let Ok(def) = wyrm_core::codec::from_slice::<ProfileDef>(&s.payload().to_bytes()) {
                found.insert(name.to_owned(), profile_to_json(name, &def));
            }
        }
        Ok(json!({ "count": found.len(), "profiles": found.into_values().collect::<Vec<_>>() }))
    }

    fn flows_root(&self) -> String {
        format!("wy/{}/dataflows", self.site())
    }

    async fn flow_state(&self, node: &str) -> Json {
        match self.read_val(node).await {
            Ok(Sample {
                v: Value::Map(m), ..
            }) => {
                let mut o = Map::new();
                let state = match m.get("state") {
                    Some(Value::UInt(0)) => "running".into(),
                    Some(Value::UInt(1)) => "stopped".into(),
                    Some(Value::UInt(2)) => "error".into(),
                    Some(v) => value_to_json(v),
                    None => Json::Null,
                };
                o.insert("state".into(), state);
                for k in ["version", "error"] {
                    if let Some(v) = m.get(k) {
                        o.insert(k.into(), value_to_json(v));
                    }
                }
                Json::Object(o)
            }
            Ok(s) => sample_to_json(&s),
            Err(e) => json!({ "error": e }),
        }
    }

    async fn do_flow_get(&self, p: FlowIdParams) -> Out {
        wyrm_core::keyspace::validate_segment(&p.id).map_err(err)?;
        let node = format!("{}/{}", self.flows_root(), p.id);
        let key = format!("{node}/~def");
        let (_, payload) = self.get_one(&key, self.client().proof(&key)).await?;
        let def: Value = wyrm_core::codec::from_slice(&payload).map_err(err)?;
        Ok(json!({ "id": p.id, "state": self.flow_state(&node).await, "def": value_to_json(&def) }))
    }

    async fn validate_def(&self, def: &Value) -> Out {
        let mut args = BTreeMap::new();
        args.insert("def".to_owned(), def.clone());
        let r = self
            .client()
            .invoke_one(&self.flows_root(), "validate", Value::Map(args))
            .await
            .map_err(err)?;
        Ok(r.map(|v| value_to_json(&v)).unwrap_or(Json::Null))
    }

    async fn do_flow_validate(&self, p: FlowDefParams) -> Out {
        let def = json_to_value(&Json::Object(p.def))?;
        self.validate_def(&def).await
    }

    async fn do_flow_apply(&self, p: FlowApplyParams) -> Out {
        let def = json_to_value(&Json::Object(p.def))?;
        let site = self.site().to_owned();
        let targets =
            wyrm_flow::command_targets(&def, &site).map_err(|e| format!("flow definition: {e}"))?;
        let root = self.flows_root();
        let deploy_key = format!("{root}/~act/deploy");
        tracing::debug!(
            tool = "flow_apply",
            targets = targets.len(),
            dry_run = p.dry_run,
            "request"
        );
        // Proofs: exactly the command targets, each for its key at >= write,
        // all from the deployer (ADR 0008: same subject as the deploy caller).
        if let Some(extra) = p.proofs.keys().find(|k| !targets.contains(k)) {
            return Err(format!(
                "proof for {extra}, which is not a command target of this flow"
            ));
        }
        let mut proofs = BTreeMap::new();
        let mut proof_report = Map::new();
        let mut proof_subs = Vec::new();
        let mut missing = Vec::new();
        for t in &targets {
            match p.proofs.get(t) {
                None => missing.push(t.clone()),
                Some(b64) => {
                    let (tok, info) = self
                        .approval(b64, t, Perm::Write, None)
                        .map_err(|e| format!("proof for {t}: {e}"))?;
                    proof_subs.push((t.clone(), info.sub.clone()));
                    proof_report.insert(t.clone(), Self::approval_json(&info));
                    proofs.insert(t.clone(), Value::Bytes(tok));
                }
            }
        }
        // the deploy request as it will be sent: the approval binds it, proofs included
        let mut args = BTreeMap::new();
        args.insert("def".to_owned(), def.clone());
        args.insert("proofs".to_owned(), Value::Map(proofs));
        let args = Value::Map(args);
        let payload = wyrm_core::codec::to_vec(&args).map_err(err)?;
        let approval = match &p.approval {
            Some(a) => Some(self.approval(a, &deploy_key, Perm::Config, Some(&payload))?),
            None => None,
        };
        if let Some((_, a)) = &approval {
            if let Some((t, sub)) = proof_subs.iter().find(|(_, s)| *s != a.sub) {
                return Err(format!(
                    "proof for {t} is from {sub:?}, the approval from {:?}; both must come from \
                     the same operator",
                    a.sub
                ));
            }
        }
        if p.dry_run {
            let validation = self
                .validate_def(&def)
                .await
                .unwrap_or_else(|e| json!({ "error": e }));
            return Ok(json!({
                "dry_run": true,
                "validation": validation,
                "requires_approval": true,
                "approval_key": deploy_key,
                "args_sha256": check::payload_sha256(&payload),
                "approval": approval.as_ref().map(|(_, i)| Self::approval_json(i)),
                "command_targets": targets,
                "proofs": proof_report,
                "missing_proofs": missing,
            }));
        }
        let Some((tok, info)) = approval else {
            return Err(format!(
                "flow deploy is config-level: dry_run=false needs `approval` (a ptok a human \
                 operator minted for exactly {deploy_key}) and one proof per command target"
            ));
        };
        if !missing.is_empty() {
            return Err(format!("missing proofs for command targets: {missing:?}"));
        }
        let sender = self.sender(Some((tok, deploy_key.clone())))?;
        let r = sender
            .invoke_one(&root, "deploy", args)
            .await
            .map_err(err)?;
        Ok(json!({
            "ok": true,
            "key": deploy_key,
            "result": r.map(|v| value_to_json(&v)),
            "sent_as": format!("approval of {}", info.sub),
        }))
    }

    async fn do_link_status(&self, p: LinkStatusParams) -> Out {
        wyrm_core::keyspace::validate_segment(&p.link).map_err(err)?;
        let site = self.site();
        let down = format!("wy/{site}/downstream/{}", p.link);
        let alive = self.alive(&down).await;
        let root_meta = match self.client().meta(&down).await {
            Ok(m) => meta_to_json(&m),
            Err(e) => json!({ "error": e.to_string() }),
        };
        let sys = format!("wy/{site}/sys/links/{}", p.link);
        let admin = match self.client().meta(&sys).await {
            Ok(m) => {
                let state_node = format!("{sys}/state");
                let state = match self.read_val(&state_node).await {
                    Ok(s) => {
                        let names = self
                            .client()
                            .meta(&state_node)
                            .await
                            .ok()
                            .and_then(|m| m.enum_values);
                        match (&s.v, names) {
                            (Value::UInt(i), Some(n)) if (*i as usize) < n.len() => {
                                Json::String(n[*i as usize].clone())
                            }
                            (v, _) => value_to_json(v),
                        }
                    }
                    Err(e) => json!({ "error": e }),
                };
                json!({
                    "attr": m.attr.as_ref().map(|a| a.iter().map(|(k, v)| (k.clone(), value_to_json(v))).collect::<Map<_, _>>()),
                    "state": state,
                })
            }
            Err(e) => json!({ "error": e.to_string() }),
        };
        Ok(
            json!({ "link": p.link, "key": down, "alive": alive, "meta": root_meta, "admin": admin }),
        )
    }
}

#[tool_router]
impl WyrmMcp {
    #[tool(
        description = "Children of a node with their ~meta summary (type, unit, writable, display, has_children). `wy/<site>/downstream` lists links. Paged with from/limit; `next` is the next `from`."
    )]
    async fn tree_list(&self, Parameters(p): Parameters<TreeListParams>) -> CallToolResult {
        done(self.do_tree_list(p).await)
    }

    #[tool(
        description = "Descendant keys of a node (relative), optionally filtered by ~meta fields (`match`, e.g. `type:1;unit:°C`) and depth. Cheap: keys only."
    )]
    async fn tree_resolve(&self, Parameters(p): Parameters<TreeResolveParams>) -> CallToolResult {
        done(self.do_tree_resolve(p).await)
    }

    #[tool(
        description = "Full ~meta of a node: type, unit, enum, writable level, cfg (min/max…), attr, actions with parameter schemas and levels, children. expand=true folds in the profile chain."
    )]
    async fn node_meta(&self, Parameters(p): Parameters<NodeMetaParams>) -> CallToolResult {
        done(self.do_node_meta(p).await)
    }

    #[tool(
        description = "Current values (~val) of up to 200 nodes: {path: {v, q, t}} with quality good|uncertain|bad and t in microseconds since the Unix epoch, or {error}."
    )]
    async fn value_get(&self, Parameters(p): Parameters<ValueGetParams>) -> CallToolResult {
        done(self.do_value_get(p).await)
    }

    #[tool(
        description = concat!(
            "Write a value to a point (~set). ALWAYS call with dry_run=true first (the default): ",
            "it checks the value against ~meta (type, enum, min/max, writable level) and returns what ",
            "would be sent, without sending. Then call again with dry_run=false. ",
            "Config-level requests (writable=config, action level config, any key under wy/<site>/sys/**) ",
            "are refused unless `approval` is given: a base64 ptok minted by a human operator for exactly ",
            "the request key (`<node>/~set` or `<node>/~act/<action>`), with at least the needed level. ",
            "The server sends it as the request's ptok instead of its own token (ai:<agent>, max write), ",
            "so the responder verifies the human's rights and the audit records the human. ",
            "Tokens are single-use: dry_run never sends or spends an approval."
        )
    )]
    async fn node_set(&self, Parameters(p): Parameters<NodeSetParams>) -> CallToolResult {
        done(self.do_node_set(p).await)
    }

    #[tool(
        description = concat!(
            "Run an action (~act/<action>) of a node. ALWAYS call with dry_run=true first (the default): ",
            "it checks the arguments against the action's parameter schema (names, required, type, enum) ",
            "and level, and returns what would be sent, without sending. Then call again with dry_run=false. ",
            "Streaming actions return all results (at most 1000). ",
            "Config-level requests (writable=config, action level config, any key under wy/<site>/sys/**) ",
            "are refused unless `approval` is given: a base64 ptok minted by a human operator for exactly ",
            "the request key (`<node>/~set` or `<node>/~act/<action>`), with at least the needed level. ",
            "The server sends it as the request's ptok instead of its own token (ai:<agent>, max write), ",
            "so the responder verifies the human's rights and the audit records the human. ",
            "Tokens are single-use: dry_run never sends or spends an approval."
        )
    )]
    async fn action_invoke(&self, Parameters(p): Parameters<ActionInvokeParams>) -> CallToolResult {
        done(self.do_action_invoke(p).await)
    }

    #[tool(
        description = "Node profiles published under wy/<site>/pub/<name>/~meta (shared ~meta for many nodes), optionally filtered by name."
    )]
    async fn profiles(&self, Parameters(p): Parameters<ProfilesParams>) -> CallToolResult {
        done(self.do_profiles(p).await)
    }

    #[tool(description = "Definition (~def) and state (running|stopped|error, version) of a flow.")]
    async fn flow_get(&self, Parameters(p): Parameters<FlowIdParams>) -> CallToolResult {
        done(self.do_flow_get(p).await)
    }

    #[tool(
        description = "Compile a flow definition (spec 06) on the flow engine without deploying it. Returns {ok: true} or {ok: false, error}."
    )]
    async fn flow_validate(&self, Parameters(p): Parameters<FlowDefParams>) -> CallToolResult {
        done(self.do_flow_validate(p).await)
    }

    #[tool(
        description = concat!(
            "Deploy a flow definition (wy/<site>/dataflows/~act/deploy). dry_run=true (the default) validates ",
            "it and lists its command targets (the ~set/~act keys its sinks write to). A deploy is ",
            "config-level, so dry_run=false needs: `approval`, a base64 ptok a human operator minted for ",
            "exactly wy/<site>/dataflows/~act/deploy (level config); and `proofs`, {target_key: base64 ptok} ",
            "with one token per command target, minted by the SAME operator for exactly that key (level >= ",
            "write). The flow then acts on devices only within that operator's rights (ADR 0008). ",
            "dry_run never sends or spends the tokens."
        )
    )]
    async fn flow_apply(&self, Parameters(p): Parameters<FlowApplyParams>) -> CallToolResult {
        done(self.do_flow_apply(p).await)
    }

    #[tool(
        description = "Status of a link: liveliness of wy/<site>/downstream/<link>, its root ~meta (driver, version) and, from the admin (wy/<site>/sys/links/<link>), driver, mode and state."
    )]
    async fn link_status(&self, Parameters(p): Parameters<LinkStatusParams>) -> CallToolResult {
        done(self.do_link_status(p).await)
    }

    #[tool(
        description = "The normative WYRM spec: 01 keyspace, 02 meta, 03 val, 04 attachment (ptok), 05 methods, 06 flow-def, readme, tables, changelog. Without a section: the list."
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
                Some(f) => {
                    return CallToolResult::success(vec![ContentBlock::text(f.text)]);
                }
                None => Err(format!("no spec section {s:?}")),
            },
        };
        done(r)
    }
}

#[tool_handler(router = self.tool_router)]
impl ServerHandler for WyrmMcp {
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
                        .with_mime_type(mime(f.file))
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
            ResourceContents::text(f.text, request.uri).with_mime_type(mime(f.file))
        ])
        .into())
    }
}

fn mime(file: &str) -> &'static str {
    if file.ends_with(".json") {
        "application/json"
    } else {
        "text/markdown"
    }
}
