//! The engine: flows as nodes under `wy/<site>/dataflows` (an SDK link rooted
//! there). Root actions `deploy {def}` / `validate {def}`; per flow
//! `start | stop | reload | remove`. `dataflows/<id>/~def` is read-only: a bare
//! `put` carries no verified caller, so deploying goes through the `deploy`
//! action only (ptok, `maxperm` cap, audit). A failed compile leaves the previous version
//! running and shows the error in `dataflows/<id>/~val` (spec 06).
//!
//! Hot swap: the old run stops (drains ≤ 1 s) and the new one starts with
//! the state of every node whose id and config hash did not change.
//! `invoke`/`set` sinks act with a token minted per flow, scoped by the
//! flow's `permissions.maxperm`. Links trust the flow key, so a deployer must
//! prove its own rights on every command target: `deploy {def, proofs}`
//! carries one token per target key, signed by a key the engine trusts
//! (admin or gateway), with the deployer's subject and at least
//! `max(maxperm, write)`; targets must be exact keys under `wy/<site>/downstream/`
//! or `wy/<site>/storage/` (ADR 0008, ADR 0017).
//!
//! WASM nodes (iteration 8): `put_artifact {bytes}` stores a
//! `wyrm:flow/node` component under `<dir>/artifacts/<sha256>.wasm` and
//! returns `{artifact: <sha256>}`; a `~def` uses it as
//! `{type: "wasm", artifact: <sha256>}`. Deploy and validate load the
//! artifact and run its `init`, so a missing or broken component keeps the
//! running version. Hot load = `put_artifact` + `deploy`, no restart.

use crate::artifacts::Artifacts;
use crate::def::{self, FlowDef};
use crate::nodes::{Io, Ports};
use crate::runtime::{self, Running};
use crate::store::{FlowStore, NodeStateRec, Op};
use ed25519_dalek::SigningKey;
use std::collections::BTreeMap;
use std::path::Path;
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tokio::sync::{mpsc, Mutex as AsyncMutex};
use tokio::task::JoinHandle;
use tracing::{info, warn};
use wyrm_client::{SigningTokens, WyrmClient};
use wyrm_core::meta::{ActionResult, ParamMeta, Profile, TextOrCode};
use wyrm_core::ptok::Grant;
use wyrm_core::{ActionMeta, NodeMeta, Perm, Quality, Sample, Status, TypeCode, Value};
use wyrm_link_sdk::auth::Verifier;
use wyrm_link_sdk::{now_us, Caller, Link, LinkCtx, LinkError, ReplySink, VerifyingKey};
use wyrm_state::Store;

/// State older than this is not restored (wiki: `state_ttl` 1 h).
const STATE_TTL_US: u64 = 3_600_000_000;
const STATE_RUNNING: u64 = 0;
const STATE_STOPPED: u64 = 1;
const STATE_ERROR: u64 = 2;

pub type Error = Box<dyn std::error::Error + Send + Sync>;

/// What survives broker reloads: the store and the flow signing key.
pub struct FlowHost {
    site: String,
    store: Mutex<Store<FlowStore>>,
    signer: SigningKey,
    artifacts: Artifacts,
}

impl FlowHost {
    /// Store under `dir/state`, signing key in `dir/flow.key` (0600), WASM
    /// artifacts under `dir/artifacts`.
    pub fn open(dir: &Path, hmac_key: &[u8], site: &str) -> Result<Arc<Self>, Error> {
        Self::open_anchored(dir, hmac_key, site, None)
    }

    /// [`open`](Self::open) with the store's WAL head kept in `anchor`
    /// (another medium; see `wyrm_state::Store::with_anchor`); `init`
    /// creates the anchor from the current head.
    pub fn open_anchored(
        dir: &Path,
        hmac_key: &[u8],
        site: &str,
        anchor: Option<(&Path, bool)>,
    ) -> Result<Arc<Self>, Error> {
        std::fs::create_dir_all(dir)?;
        let mut store = Store::<FlowStore>::open(dir.join("state"), hmac_key)?;
        match anchor {
            Some((a, true)) => store = store.init_anchor(a)?,
            Some((a, false)) => store = store.with_anchor(a)?,
            None => {}
        }
        let key_path = dir.join("flow.key");
        let seed: [u8; 32] = match std::fs::read_to_string(&key_path) {
            Ok(t) => wyrm_core_hex(t.trim())?,
            Err(_) => {
                let mut s = [0u8; 32];
                getrandom_fill(&mut s)?;
                write_private(&key_path, &hex_encode(&s))?;
                s
            }
        };
        Ok(Arc::new(Self {
            site: site.to_owned(),
            store: Mutex::new(store),
            signer: SigningKey::from_bytes(&seed),
            artifacts: Artifacts::new(dir.join("artifacts")),
        }))
    }

    /// Links must trust this key so flow commands pass their `ptok` check.
    pub fn verifying_key(&self) -> VerifyingKey {
        self.signer.verifying_key()
    }

    /// WASM flow-node components by SHA-256.
    pub fn artifacts(&self) -> &Artifacts {
        &self.artifacts
    }

    fn store(&self) -> std::sync::MutexGuard<'_, Store<FlowStore>> {
        self.store.lock().unwrap_or_else(|p| p.into_inner())
    }

    fn apply(&self, op: Op) -> Result<(), LinkError> {
        self.store()
            .apply(op)
            .map(|_| ())
            .map_err(|e| LinkError::internal(e.to_string()))
    }
}

fn hex_encode(b: &[u8]) -> String {
    b.iter().map(|x| format!("{x:02x}")).collect()
}

fn wyrm_core_hex(s: &str) -> Result<[u8; 32], Error> {
    if s.len() != 64 {
        return Err("flow.key: expected 32 bytes hex".into());
    }
    let mut out = [0u8; 32];
    for (i, o) in out.iter_mut().enumerate() {
        *o = u8::from_str_radix(&s[2 * i..2 * i + 2], 16)?;
    }
    Ok(out)
}

fn getrandom_fill(b: &mut [u8]) -> Result<(), Error> {
    getrandom::fill(b).map_err(|e| format!("no randomness: {e}").into())
}

fn write_private(path: &Path, text: &str) -> std::io::Result<()> {
    use std::io::Write;
    let mut opts = std::fs::OpenOptions::new();
    opts.write(true).create_new(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        opts.mode(0o600);
    }
    opts.open(path)?.write_all(text.as_bytes())
}

struct FlowRt {
    def: FlowDef,
    ports: BTreeMap<String, Ports>,
    run: Option<Running>,
    error: Option<String>,
    stopped: bool,
    since: u64,
    supervisor: Option<JoinHandle<()>>,
}

struct State {
    ctx: LinkCtx,
    host: Arc<FlowHost>,
    flows: BTreeMap<String, FlowRt>,
}

type Shared = Arc<AsyncMutex<State>>;

fn type_code(name: &str) -> TypeCode {
    TypeCode::ALL
        .iter()
        .copied()
        .find(|t| t.name() == name)
        .unwrap_or(TypeCode::Dynamic)
}

/// `publish.meta` → node meta (`is`, `type`, `unit`, `attr`).
fn publish_meta(cfg: &def::Map) -> NodeMeta {
    let mut m = NodeMeta::leaf(TypeCode::Dynamic);
    if let Some(Value::Map(meta)) = cfg.get("meta") {
        if let Some(Value::Str(t)) = meta.get("type") {
            m.ty = Some(type_code(t));
        }
        if let Some(Value::Str(is)) = meta.get("is") {
            m.is = Some(Profile::Name(is.clone()));
        }
        if let Some(Value::Str(u)) = meta.get("unit") {
            m.unit = Some(TextOrCode::Text(u.clone()));
        }
        if let Some(Value::Map(attr)) = meta.get("attr") {
            m.attr = Some(attr.clone());
        }
    }
    m
}

impl State {
    /// Tokens of a flow cover only the keys its command sinks declare.
    fn client_for(&self, def: &FlowDef) -> WyrmClient {
        let site = &self.host.site;
        let grants = targets(def, site)
            .into_iter()
            .map(|k| Grant { k, p: def.maxperm })
            .collect();
        let tokens = SigningTokens::new(self.host.signer.clone(), site.clone())
            .subject(format!("flow:{}", def.id))
            .max(def.maxperm)
            .grants(grants);
        WyrmClient::new(self.ctx.client().clone()).with_tokens(Arc::new(tokens))
    }

    async fn publish_val(&self, id: &str) {
        let Some(f) = self.flows.get(id) else { return };
        let state = if f.error.is_some() {
            STATE_ERROR
        } else if f.stopped || !f.def.enabled {
            STATE_STOPPED
        } else {
            STATE_RUNNING
        };
        let mut m = BTreeMap::new();
        m.insert("state".into(), Value::UInt(state));
        if let Some(e) = &f.error {
            m.insert("error".into(), Value::Str(e.clone()));
        }
        m.insert("version".into(), Value::UInt(f.def.version));
        m.insert("since".into(), Value::UInt(f.since));
        if let Some(by) = self.host.store().state().deployers.get(id) {
            m.insert("deployed_by".into(), Value::Str(by.clone()));
        }
        let s = Sample {
            v: Value::Map(m),
            q: Quality::Good,
            t: now_us(),
        };
        if let Ok(p) = wyrm_core::codec::to_vec(&s) {
            let _ = self.ctx.client().put(self.ctx.key(id, "~val"), p).await;
        }
    }

    async fn declare(&self, id: &str) -> Result<(), LinkError> {
        let f = &self.flows[id];
        let mut meta = NodeMeta::folder()
            .is("wy:flow")
            .attr("version", f.def.version);
        if let Some(d) = &f.def.description {
            meta = meta.display(d.clone());
        }
        self.ctx.declare_node(id, meta).await?;
        for a in ["start", "stop", "reload", "remove"] {
            self.ctx
                .declare_action(id, a, ActionMeta::new().level(Perm::Config))
                .await?;
        }
        self.ctx
            .declare_action(
                id,
                "history",
                ActionMeta::new()
                    .result(ActionResult::Type(TypeCode::Array))
                    .level(Perm::Read),
            )
            .await?;
        self.ctx
            .declare_action(
                id,
                "rollback",
                ActionMeta::new()
                    .param("version", ParamMeta::of(TypeCode::Number).required(true))
                    .param("proofs", ParamMeta::of(TypeCode::Map))
                    .level(Perm::Config),
            )
            .await?;
        let nodes = format!("{id}/nodes");
        if self.ctx.meta(&nodes).is_none() {
            self.ctx.declare_node(&nodes, NodeMeta::folder()).await?;
        }
        // Publish nodes: keep the ones still defined, remove the others.
        let wanted: BTreeMap<String, &def::Map> = f
            .def
            .nodes
            .values()
            .filter(|n| n.ty == "publish")
            .filter_map(|n| match n.cfg.get("node") {
                Some(Value::Str(name)) => Some((name.clone(), &n.cfg)),
                _ => None,
            })
            .collect();
        let existing = self
            .ctx
            .meta(&nodes)
            .and_then(|m| m.children)
            .unwrap_or_default();
        for name in existing {
            if !wanted.contains_key(&name) {
                self.ctx.remove_node(&format!("{nodes}/{name}")).await?;
            }
        }
        for (name, cfg) in wanted {
            self.ctx
                .declare_node(&format!("{nodes}/{name}"), publish_meta(cfg))
                .await?;
        }
        let raw = wyrm_core::codec::to_vec(&f.def.raw).unwrap_or_default();
        self.ctx.set_doc(id, "~def", Some(raw))?;
        Ok(())
    }

    fn restored(&self, id: &str) -> BTreeMap<String, (u32, Value)> {
        let now = now_us();
        self.host
            .store()
            .state()
            .states
            .get(id)
            .map(|recs| {
                recs.iter()
                    .filter(|r| now.saturating_sub(r.t) < STATE_TTL_US)
                    .filter_map(|r| {
                        wyrm_core::codec::from_slice::<Value>(&r.cbor)
                            .ok()
                            .map(|v| (r.node.clone(), (r.hash, v)))
                    })
                    .collect()
            })
            .unwrap_or_default()
    }

    fn persist_states(&self, id: &str, states: &BTreeMap<String, (u32, Value)>) {
        let t = now_us();
        let recs = states
            .iter()
            .filter_map(|(node, (hash, v))| {
                wyrm_core::codec::to_vec(v).ok().map(|cbor| NodeStateRec {
                    node: node.clone(),
                    hash: *hash,
                    t,
                    cbor,
                })
            })
            .collect();
        if let Err(e) = self.host.apply(Op::PutStates {
            id: id.to_owned(),
            states: recs,
        }) {
            warn!(flow = %id, "state flush: {e}");
        }
    }

    /// Stop the current run (state saved), if any.
    async fn halt(&mut self, id: &str) -> BTreeMap<String, (u32, Value)> {
        let Some(f) = self.flows.get_mut(id) else {
            return BTreeMap::new();
        };
        if let Some(s) = f.supervisor.take() {
            s.abort();
        }
        let Some(run) = f.run.take() else {
            return BTreeMap::new();
        };
        let states = run.stop().await;
        tokio::time::sleep(Duration::from_millis(20)).await;
        let states = states.lock().unwrap_or_else(|p| p.into_inner()).clone();
        self.persist_states(id, &states);
        states
    }

    /// Start `id` with `restored` states (if enabled and not stopped).
    fn launch(&mut self, id: &str, restored: BTreeMap<String, (u32, Value)>, shared: &Shared) {
        let Some(f) = self.flows.get(id) else { return };
        if f.stopped || !f.def.enabled || f.error.is_some() {
            return;
        }
        let client = self.client_for(&f.def);
        let (ctx, site, flow) = (self.ctx.clone(), self.host.site.clone(), id.to_owned());
        let (ptx, prx) = mpsc::unbounded_channel();
        let run = runtime::start(
            &f.def,
            &f.ports,
            &restored,
            |_node, inject| Io {
                client: client.clone(),
                ctx: ctx.clone(),
                site: site.clone(),
                flow: flow.clone(),
                inject,
            },
            ptx,
            Some(&self.host.artifacts),
        );
        let flush = f.def.policy.state_flush;
        let backoff = f.def.policy.backoff_max.min(Duration::from_secs(5));
        let f = self.flows.get_mut(id).expect("exists");
        match run {
            Ok(r) => {
                f.run = Some(r);
                f.supervisor = Some(tokio::spawn(supervise(
                    shared.clone(),
                    id.to_owned(),
                    prx,
                    flush,
                    backoff,
                )));
            }
            Err(e) => f.error = Some(e),
        }
    }

    /// Compile and (re)deploy. A compile error keeps the running version.
    /// `by`: the deployer's subject (persisted with the definition).
    async fn deploy(
        &mut self,
        raw: Value,
        persist: Option<Option<String>>,
        shared: &Shared,
    ) -> Result<(), LinkError> {
        let by = persist.clone().flatten();
        let persist = persist.is_some();
        let (def, ports) = match compile(&raw, &self.host.artifacts) {
            Ok(x) => x,
            Err(e) => {
                // Show the error on the flow if it exists; old version keeps running.
                if let Some(id) = match &raw {
                    Value::Map(m) => match m.get("id") {
                        Some(Value::Str(s)) => Some(s.clone()),
                        _ => None,
                    },
                    _ => None,
                } {
                    if let Some(f) = self.flows.get_mut(&id) {
                        f.error = Some(e.0.clone());
                        // still running: keep `run`; the error describes the draft
                        self.publish_val(&id).await;
                        if let Some(f) = self.flows.get_mut(&id) {
                            f.error = None;
                        }
                    }
                }
                return Err(LinkError::invalid_parameter(e.0));
            }
        };
        let id = def.id.clone();
        if let Some(old) = self.flows.get(&id) {
            if def.version <= old.def.version && persist {
                return Err(LinkError::invalid_parameter(format!(
                    "version: {} ≤ current {}",
                    def.version, old.def.version
                )));
            }
        }
        if persist {
            let cbor = wyrm_core::codec::to_vec(&def.raw)
                .map_err(|e| LinkError::internal(e.to_string()))?;
            self.host.apply(Op::PutDef {
                id: id.clone(),
                cbor,
                by,
            })?;
        }
        // Hot swap: keep state of unchanged nodes (same id and config hash).
        let mut states = self.halt(&id).await;
        if states.is_empty() {
            states = self.restored(&id);
        }
        states.retain(|node, (hash, _)| def.nodes.get(node).is_some_and(|n| n.hash == *hash));
        let stopped = self
            .host
            .store()
            .state()
            .stopped
            .get(&id)
            .copied()
            .unwrap_or(false);
        self.flows.insert(
            id.clone(),
            FlowRt {
                def,
                ports,
                run: None,
                error: None,
                stopped,
                since: now_us(),
                supervisor: None,
            },
        );
        self.declare(&id).await?;
        self.launch(&id, states, shared);
        self.publish_val(&id).await;
        info!(flow = %id, version = self.flows[&id].def.version, "flow deployed");
        Ok(())
    }
}

/// [`def::compile`] plus the checks that need the host: every `wasm` node's
/// artifact loads and its `init` succeeds.
fn compile(raw: &Value, artifacts: &Artifacts) -> def::Result<(FlowDef, BTreeMap<String, Ports>)> {
    let (d, p) = def::compile(raw)?;
    for (id, n) in d.nodes.iter().filter(|(_, n)| n.ty == "wasm") {
        crate::nodes::WasmCfg::parse(&n.cfg)
            .and_then(|w| w.check(artifacts))
            .map_err(|e| def::DefError(format!("nodes.{id}.{e}")))?;
    }
    Ok((d, p))
}

/// Per run: periodic state flush; on a node panic mark the flow `error`,
/// wait, then restart from the saved state.
async fn supervise(
    shared: Shared,
    id: String,
    mut panics: mpsc::UnboundedReceiver<String>,
    flush: Duration,
    backoff: Duration,
) {
    let mut iv = tokio::time::interval(flush);
    iv.tick().await;
    loop {
        tokio::select! {
            _ = iv.tick() => {
                let st = shared.lock().await;
                if let Some(run) = st.flows.get(&id).and_then(|f| f.run.as_ref()) {
                    run.flush();
                    let states = run.states.clone();
                    drop(st);
                    tokio::time::sleep(Duration::from_millis(50)).await;
                    let snapshot = states.lock().unwrap_or_else(|p| p.into_inner()).clone();
                    shared.lock().await.persist_states(&id, &snapshot);
                }
            }
            why = panics.recv() => {
                let Some(why) = why else { return };
                warn!(flow = %id, "flow error: {why}");
                {
                    let mut st = shared.lock().await;
                    if let Some(f) = st.flows.get_mut(&id) {
                        // This task is the supervisor being replaced: detach first.
                        f.supervisor = None;
                        if let Some(run) = f.run.take() {
                            let states = run.stop().await;
                            let snap = states.lock().unwrap_or_else(|p| p.into_inner()).clone();
                            st.persist_states(&id, &snap);
                        }
                    }
                    if let Some(f) = st.flows.get_mut(&id) {
                        f.error = Some(why);
                    }
                    st.publish_val(&id).await;
                }
                tokio::time::sleep(backoff).await;
                let mut st = shared.lock().await;
                let restored = st.restored(&id);
                if let Some(f) = st.flows.get_mut(&id) {
                    f.error = None;
                    f.since = now_us();
                }
                st.launch(&id, restored, &shared);
                st.publish_val(&id).await;
                return;
            }
        }
    }
}

/// Full keys of every `invoke`/`set` target of `def`.
/// Full keys of a definition's command targets (`…/~act/<a>`, `…/~set`),
/// for which a deployer sends `proofs`.
pub fn command_targets(raw: &Value, site: &str) -> Result<Vec<String>, String> {
    let def = def::parse(raw).map_err(|e| e.0)?;
    Ok(targets(&def, site))
}

fn targets(def: &FlowDef, site: &str) -> Vec<String> {
    def.nodes
        .values()
        .filter_map(|n| crate::nodes::command_target(&n.ty, &n.cfg))
        .map(|k| {
            if k.starts_with("wy/") {
                k
            } else {
                format!("wy/{site}/{}", k.trim_start_matches('/'))
            }
        })
        .collect()
}

fn version_of(v: &Value) -> Option<u64> {
    match v {
        Value::Map(m) => match m.get("version") {
            Some(Value::UInt(u)) => Some(*u),
            Some(Value::Int(i)) => u64::try_from(*i).ok(),
            _ => None,
        },
        _ => None,
    }
}

/// A deploying caller may not give a flow more than it holds: `maxperm` is
/// capped by the caller's effective permission. (Requester tokens are scoped
/// to the request key, so they cannot prove rights on the flow's targets;
/// the flow token itself covers only the declared targets.)
fn caller_covers(raw: &Value, who: &Caller) -> Result<(), LinkError> {
    let Ok(def) = def::parse(raw) else {
        return Ok(()); // the compiler reports it
    };
    if def.maxperm > who.perm {
        return Err(LinkError::new(
            Status::PermissionDenied,
            format!(
                "permissions.maxperm {} exceeds the deployer's {}",
                def.maxperm.name(),
                who.perm.name()
            ),
        ));
    }
    Ok(())
}

/// The deployer's subject: the token-bound `origin`, else the token subject.
fn deployer(who: &Caller) -> Option<String> {
    who.origin
        .clone()
        .or_else(|| who.claims.as_ref().map(|c| c.sub.clone()))
}

/// The deployer proves rights on every command target: the flow key is
/// trusted by links, so without this a `config` right on `dataflows/**` would
/// become a `write` right on every device.
fn proves_targets(
    raw: &Value,
    args: &Value,
    who: &Caller,
    site: &str,
    verifier: &Verifier,
) -> Result<(), LinkError> {
    let Ok(def) = def::parse(raw) else {
        return Ok(()); // the compiler reports it
    };
    let proofs = match args {
        Value::Map(m) => match m.get("proofs") {
            Some(Value::Map(p)) => Some(p),
            None => None,
            Some(_) => return Err(LinkError::invalid_parameter("proofs: map key → token")),
        },
        _ => None,
    };
    let sections = [
        format!("wy/{site}/downstream/"),
        format!("wy/{site}/storage/"),
    ];
    for t in targets(&def, site) {
        if !sections.iter().any(|s| t.starts_with(s)) || t.contains(['*', '$']) {
            return Err(LinkError::invalid_parameter(format!(
                "{t}: command targets must be exact keys under {} or {}",
                sections[0], sections[1]
            )));
        }
        let denied = |why: &str| LinkError::new(Status::PermissionDenied, format!("{t}: {why}"));
        let Some(Value::Bytes(tok)) = proofs.and_then(|p| p.get(&t)) else {
            return Err(denied("no proof of the deployer's rights"));
        };
        let ke = zenoh::key_expr::keyexpr::new(&t).map_err(|_| denied("bad key"))?;
        let (claims, perm) = verifier
            .verify(tok, ke, None, now_us() / 1_000_000)
            .map_err(|_| denied("proof rejected"))?;
        // The flow token for this target carries up to `maxperm`.
        let needed = def.maxperm.max(Perm::Write);
        let same = who.claims.as_ref().is_some_and(|c| c.sub == claims.sub);
        if !same || perm < needed {
            return Err(denied(&format!(
                "proof does not give the deployer {}",
                needed.name()
            )));
        }
    }
    Ok(())
}

pub struct EngineStart {
    pub host: Arc<FlowHost>,
    /// Keys that sign deployers' proofs (the admin keys).
    pub admin_keys: Vec<VerifyingKey>,
}

/// The `wy/<site>/dataflows/**` responder.
pub struct Engine {
    shared: Shared,
    verifier: Verifier,
    site: String,
}

fn def_param() -> ParamMeta {
    ParamMeta::of(TypeCode::Map).required(true)
}

impl Link for Engine {
    const NAME: &'static str = "flow";
    const VERSION: &'static str = env!("CARGO_PKG_VERSION");
    type Config = EngineStart;

    async fn start(cfg: EngineStart, ctx: LinkCtx) -> wyrm_link_sdk::Result<Self> {
        ctx.declare_action(
            "",
            "deploy",
            ActionMeta::new()
                .param("def", def_param())
                // target key → the deployer's token for it
                .param("proofs", ParamMeta::of(TypeCode::Map))
                .level(Perm::Config),
        )
        .await?;
        ctx.declare_action(
            "",
            "put_artifact",
            ActionMeta::new()
                .param("bytes", ParamMeta::of(TypeCode::Binary).required(true))
                .result(ActionResult::Type(TypeCode::Map))
                .level(Perm::Config),
        )
        .await?;
        ctx.declare_action(
            "",
            "validate",
            ActionMeta::new()
                .param("def", def_param())
                .result(ActionResult::Type(TypeCode::Map))
                .level(Perm::Read),
        )
        .await?;
        // the palette of an editor: types, ports, params (crate::catalog)
        ctx.declare_action(
            "",
            "node_types",
            ActionMeta::new()
                .display("Node Types")
                .result(ActionResult::Type(TypeCode::Array))
                .level(Perm::Read),
        )
        .await?;
        let shared: Shared = Arc::new(AsyncMutex::new(State {
            ctx: ctx.clone(),
            host: cfg.host.clone(),
            flows: BTreeMap::new(),
        }));
        let stored: Vec<Vec<u8>> = cfg.host.store().state().defs.values().cloned().collect();
        {
            let mut st = shared.lock().await;
            for cbor in stored {
                match wyrm_core::codec::from_slice::<Value>(&cbor) {
                    Ok(v) => {
                        if let Err(e) = st.deploy(v, None, &shared).await {
                            warn!("stored flow does not compile: {e}");
                        }
                    }
                    Err(e) => warn!("stored flow unreadable: {e}"),
                }
            }
        }
        Ok(Engine {
            shared,
            verifier: Verifier::new(cfg.admin_keys, ctx.site()),
            site: ctx.site().to_owned(),
        })
    }

    async fn on_invoke(
        &mut self,
        path: &str,
        action: &str,
        args: Value,
        who: &Caller,
        out: ReplySink,
    ) -> wyrm_link_sdk::Result<()> {
        let def_arg = || match &args {
            Value::Map(m) => m
                .get("def")
                .cloned()
                .ok_or_else(|| LinkError::invalid_parameter("def: required")),
            _ => Err(LinkError::invalid_parameter("def: required")),
        };
        let shared = self.shared.clone();
        let mut st = self.shared.lock().await;
        match (path, action) {
            ("", "deploy") => {
                let raw = def_arg()?;
                caller_covers(&raw, who)?;
                proves_targets(&raw, &args, who, &self.site, &self.verifier)?;
                st.deploy(raw, Some(deployer(who)), &shared).await?
            }
            ("", "put_artifact") => {
                let Value::Map(m) = &args else {
                    return Err(LinkError::invalid_parameter("bytes: required"));
                };
                let Some(Value::Bytes(b)) = m.get("bytes") else {
                    return Err(LinkError::invalid_parameter("bytes: required binary"));
                };
                let host = st.host.clone();
                drop(st);
                // Compiling a component takes milliseconds to seconds.
                let b = b.clone();
                let sha = tokio::task::spawn_blocking(move || host.artifacts.put(&b))
                    .await
                    .map_err(|e| LinkError::internal(e.to_string()))?
                    .map_err(|e| LinkError::invalid_parameter(format!("bytes: {e}")))?;
                info!(artifact = %sha, "wasm artifact stored");
                let mut r = BTreeMap::new();
                r.insert("artifact".into(), Value::Str(sha));
                return out.reply(Value::Map(r)).await;
            }
            ("", "node_types") => {
                drop(st);
                return out.reply(crate::catalog::value()).await;
            }
            ("", "validate") => {
                let mut m = BTreeMap::new();
                match compile(&def_arg()?, &st.host.artifacts) {
                    Ok(_) => {
                        m.insert("ok".into(), Value::Bool(true));
                    }
                    Err(e) => {
                        m.insert("ok".into(), Value::Bool(false));
                        m.insert("error".into(), Value::Str(e.0));
                    }
                }
                drop(st);
                return out.reply(Value::Map(m)).await;
            }
            (id, "start" | "stop") => {
                let on = action == "start";
                st.host.apply(Op::SetEnabled {
                    id: id.to_owned(),
                    on,
                })?;
                let states = st.halt(id).await;
                if let Some(f) = st.flows.get_mut(id) {
                    f.stopped = !on;
                    f.since = now_us();
                }
                if on {
                    st.launch(id, states, &shared);
                }
                st.publish_val(id).await;
            }
            (id, "reload") => {
                let states = st.halt(id).await;
                st.launch(id, states, &shared);
                st.publish_val(id).await;
            }
            (id, "history") => {
                // Previous definitions (oldest first) and the current one.
                let mut defs: Vec<Value> = {
                    let store = st.host.store();
                    let state = store.state();
                    state
                        .history
                        .get(id)
                        .into_iter()
                        .flatten()
                        .chain(state.defs.get(id))
                        .filter_map(|b| wyrm_core::codec::from_slice::<Value>(b).ok())
                        .collect()
                };
                defs.dedup();
                drop(st);
                return out.reply(Value::Array(defs)).await;
            }
            (id, "rollback") => {
                // Deploy an earlier definition as a new version, with the
                // same checks as `deploy` (ADR 0008).
                let want = match &args {
                    Value::Map(m) => m.get("version").and_then(Value::as_f64),
                    _ => None,
                }
                .ok_or_else(|| LinkError::invalid_parameter("version: required"))?
                    as u64;
                let current = st
                    .flows
                    .get(id)
                    .map(|f| f.def.version)
                    .ok_or_else(|| LinkError::not_found(id.to_owned()))?;
                let old = {
                    let store = st.host.store();
                    store
                        .state()
                        .history
                        .get(id)
                        .into_iter()
                        .flatten()
                        .filter_map(|b| wyrm_core::codec::from_slice::<Value>(b).ok())
                        .find(|v| version_of(v) == Some(want))
                }
                .ok_or_else(|| LinkError::not_found(format!("{id} version {want}")))?;
                let Value::Map(mut m) = old else {
                    return Err(LinkError::internal("stored definition is not a map"));
                };
                m.insert("version".into(), Value::UInt(current + 1));
                let raw = Value::Map(m);
                caller_covers(&raw, who)?;
                proves_targets(&raw, &args, who, &self.site, &self.verifier)?;
                st.deploy(raw, Some(deployer(who)), &shared).await?
            }
            (id, "remove") => {
                st.halt(id).await;
                st.host.apply(Op::RemoveDef(id.to_owned()))?;
                st.flows.remove(id);
                st.ctx.remove_node(id).await?;
                let _ = st.ctx.client().delete(st.ctx.key(id, "~val")).await;
            }
            _ => {
                return Err(LinkError::new(
                    Status::NotSupported,
                    format!("{path}/~act/{action}"),
                ))
            }
        }
        Ok(())
    }

    async fn stop(&mut self) {
        let mut st = self.shared.lock().await;
        let ids: Vec<String> = st.flows.keys().cloned().collect();
        for id in ids {
            st.halt(&id).await;
        }
    }
}
