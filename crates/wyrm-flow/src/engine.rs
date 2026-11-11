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
//! Live values (ADR 0038): `<id>/~act/watch` and `<id>/~act/ports` for a deployed flow;
//! `preview {def}` runs a draft in a sandbox whose sinks only report (`crate::preview`).
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
use crate::watch::{self as live, Probe, Watches};
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
    /// Live values for `watch`/`ports` (ADR 0038): one per deployed version, kept across runs.
    probe: Arc<Probe>,
}

struct State {
    ctx: LinkCtx,
    host: Arc<FlowHost>,
    flows: BTreeMap<String, FlowRt>,
    /// The open watches of the site, for their caps.
    watches: Arc<Watches>,
    /// The running previews of drafts (ADR 0038 §5), for their caps.
    previews: Arc<Watches>,
    /// The tasks of previews, watches and `ports` answers: a stop ends and awaits them.
    streams: Vec<JoinHandle<()>>,
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
        // live values of the deployed version (ADR 0038 §3, §4)
        self.ctx
            .declare_action(
                id,
                "watch",
                ActionMeta::new()
                    .display("Watch")
                    .param("nodes", ParamMeta::of(TypeCode::Array))
                    .param("max_hz", ParamMeta::of(TypeCode::Number))
                    .result(ActionResult::Stream)
                    .stream(true)
                    .timeout_ms(live::TIMEOUT_MS)
                    .level(Perm::Read),
            )
            .await?;
        self.ctx
            .declare_action(
                id,
                "ports",
                ActionMeta::new()
                    .display("Ports")
                    .param("nodes", ParamMeta::of(TypeCode::Array))
                    .result(ActionResult::Type(TypeCode::Map))
                    .level(Perm::Read),
            )
            .await?;
        // a run of one command block, asked for by a person or a tool (ADR 0040 §2)
        self.ctx
            .declare_action(
                id,
                "trigger",
                ActionMeta::new()
                    .display("Trigger")
                    .param("node", ParamMeta::of(TypeCode::String).required(true))
                    .level(Perm::Write),
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
            // An aborted task is dropped later by the runtime, and the supervisor holds the
            // engine's state (its store): wait until it is gone. Safe under the state lock:
            // the supervisor waits only on that lock, its clock or its back-off.
            s.abort();
            let _ = s.await;
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
            f.probe.clone(),
            &crate::nodes::Mode::Live,
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
        let (def, ports) = match compile(&raw, &self.host.artifacts, &self.host.site) {
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
        // the watches of the old version end: their nodes and ports may be other ones now
        if let Some(old) = self.flows.get(&id) {
            old.probe.end(live::End::Redeployed(def.version));
        }
        let probe = Probe::new(&def);
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
                probe,
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
/// artifact loads and its `init` succeeds, and every source reads this site's
/// `downstream`, `dataflows` or `storage` only.
fn compile(
    raw: &Value,
    artifacts: &Artifacts,
    site: &str,
) -> def::Result<(FlowDef, BTreeMap<String, Ports>)> {
    let (d, p) = def::compile(raw)?;
    check_sources(&d, site)?;
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
                        // This task stays the flow's supervisor through its back-off: a stop,
                        // start or deploy meanwhile ends it (`halt`), so it never outlives the
                        // engine (holding its store) nor starts a second run. `launch` below
                        // puts the next run's supervisor in its place.
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

/// The engine reads through the broker's own session, which no ACL sees: a `subscribe` or
/// `liveliness` source may name only keys under this site's `downstream/`, `dataflows/` or
/// `storage/`, never `sys/`, `pub/`, `upstream/` or another site (security review FLOW-1: a
/// `config` user on `dataflows/**` read the audit stream and `sys/**` through a flow). Checked
/// at deploy, at validate and when a stored flow starts again.
fn check_sources(def: &FlowDef, site: &str) -> def::Result<()> {
    for r in crate::scope::reads(def) {
        let at = format!("nodes.{}.{}", r.node, r.param);
        if r.scope {
            // a scope is a key expression inside the same sections (ADR 0040 §1)
            crate::scope::Scope::new(site, &r.key)
                .map_err(|e| def::DefError(format!("{at}: {e}")))?;
            continue;
        }
        let full = crate::scope::full_key(site, &r.key);
        if !crate::scope::in_sections(site, &full) {
            return Err(def::DefError(format!(
                "{at}: a source reads this site's downstream, dataflows or storage only \
                 (wy/{site}/downstream/…), not {full}"
            )));
        }
    }
    Ok(())
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

/// The deployer may read every source of the flow: the engine reads through the broker's own
/// session, so a source is checked against the deployer's rights (the token's `auth`, spec 04)
/// when it is deployed. The first grant that touches the key decides, and it must cover all of
/// a pattern: a deny grant on a part is never skipped (security review FLOW-1). A flow keeps
/// running after its deployer loses rights (ADR 0008).
fn reads_sources(raw: &Value, who: &Caller, site: &str) -> Result<(), LinkError> {
    let Ok(def) = def::parse(raw) else {
        return Ok(()); // the compiler reports it
    };
    reads_sources_of(&def, who, site, "the deployer")
}

/// [`reads_sources`] on a parsed definition, for `role` (`the deployer`, `the caller`): the
/// error names the first source `role` may not read. `watch` and `ports` check it too: the
/// values of a flow come from its sources (ADR 0038 §3).
fn reads_sources_of(def: &FlowDef, who: &Caller, site: &str, role: &str) -> Result<(), LinkError> {
    use zenoh::key_expr::keyexpr;
    let denied = |m: String| LinkError::new(Status::PermissionDenied, m);
    for r in crate::scope::reads(def) {
        // a scope is read as a whole: a key from the port may be any key inside it
        let full = crate::scope::full_key(site, &r.key);
        // a key outside the site's sections is refused by the compiler, with its reason
        if !crate::scope::in_sections(site, &full) {
            continue;
        }
        let Some(auth) = who.claims.as_ref().and_then(|c| c.auth.as_ref()) else {
            return Err(denied(format!(
                "a flow with sources needs the rights of {role}: a token with `auth` (spec 04)"
            )));
        };
        if keyexpr::new(&full).is_err() {
            continue; // the compiler reports it
        }
        if !reads_key(auth, &full) {
            return Err(denied(format!("{full}: {role} may not read it")));
        }
        // `list_children` shows a row for every child (its name, type, unit, …): the children
        // are read as a whole, so a child that is denied refuses it (security review
        // 2026-11-10). A reader of the node alone learns nothing about what is below it.
        if r.children {
            let below = crate::scope::children_of(&full);
            if !below.as_deref().is_some_and(|b| reads_key(auth, b)) {
                return Err(denied(format!(
                    "{full}/*: {role} may not read the children it lists"
                )));
            }
        }
    }
    Ok(())
}

/// Whether `auth` gives read on all of `full` (a key, or a scope's key expression). The
/// grants are taken in order, as a responder takes them (the first that matches a key decides
/// for that key): a grant below `read` that touches `full` refuses it, a read grant that
/// covers all of it accepts it, and a read grant that covers a part leaves the rest to the
/// grants after it. So a deny grant on a part is never skipped (security review FLOW-1), and
/// every key inside `full` is one the caller reads. For one concrete key this is the first
/// grant that matches it.
fn reads_key(auth: &[Grant], full: &str) -> bool {
    holds_key(auth, full, Perm::Read)
}

/// [`reads_key`] for any level: `auth` gives `need` on all of `full`.
fn holds_key(auth: &[Grant], full: &str, need: Perm) -> bool {
    use zenoh::key_expr::keyexpr;
    let Ok(target) = keyexpr::new(full) else {
        return false;
    };
    for g in auth {
        let Ok(k) = keyexpr::new(&g.k) else {
            continue;
        };
        if !k.intersects(target) {
            continue;
        }
        if g.p < need {
            return false;
        }
        if k.includes(target) {
            return true;
        }
    }
    false
}

/// `watch` and `ports` (ADR 0038 §3): the caller reads every source and every command target
/// of the flow. A flow's values come from its sources, and an `invoke` node's output carries
/// its target's answer, a `set` node's input what it writes there. The error names the first
/// key the caller may not read (a target as its node key, without `~act/<a>` or `~set`).
fn reads_flow(def: &FlowDef, who: &Caller, site: &str) -> Result<(), LinkError> {
    reads_sources_of(def, who, site, "the caller")?;
    for t in targets(def, site) {
        let node = t
            .rsplit_once("/~act/")
            .map(|(n, _)| n)
            .or_else(|| t.strip_suffix("/~set"))
            .unwrap_or(&t);
        let Some(auth) = who.claims.as_ref().and_then(|c| c.auth.as_ref()) else {
            return Err(LinkError::new(
                Status::PermissionDenied,
                "a flow with command targets needs the rights of the caller: a token with \
                 `auth` (spec 04)",
            ));
        };
        if !reads_key(auth, node) {
            return Err(LinkError::new(
                Status::PermissionDenied,
                format!("{node}: the caller may not read it"),
            ));
        }
    }
    Ok(())
}

/// `trigger` (ADR 0040 §2): the caller itself may do what the block does, on the block's
/// target (`…/~act/<a>`, `…/~set`), by its `auth` (spec 04). The level is the one the deploy
/// asked of the deployer's proof ([`proves_targets`]): the flow's token for the target carries
/// up to `maxperm`, so the caller needs `max(maxperm, write)`. A caller with less could
/// otherwise run through the flow what it may not run itself. The flow's own token only says
/// that its deployer could.
fn triggers(n: &def::NodeDef, maxperm: Perm, who: &Caller, site: &str) -> Result<(), LinkError> {
    let denied = |m: String| LinkError::new(Status::PermissionDenied, m);
    // a reader (ADR 0044 §4): the caller reads what it reads, its key and its scope as a
    // whole (and the children `list_children` lists), as a watcher of the flow must
    if crate::nodes::is_reader(&n.ty) {
        let Some(auth) = who.claims.as_ref().and_then(|c| c.auth.as_ref()) else {
            return Err(denied(
                "trigger needs the rights of the caller: a token with `auth` (spec 04)".into(),
            ));
        };
        for (field, scope) in crate::nodes::read_fields(&n.ty) {
            for param in [*field, *scope] {
                let Some(Value::Str(k)) = n.cfg.get(param) else {
                    continue;
                };
                let full = crate::scope::full_key(site, k);
                if !reads_key(auth, &full) {
                    return Err(denied(format!("{full}: the caller may not read it")));
                }
                if n.ty == "list_children" {
                    let below = crate::scope::children_of(&full);
                    if !below.as_deref().is_some_and(|b| reads_key(auth, b)) {
                        return Err(denied(format!(
                            "{full}/*: the caller may not read the children it lists"
                        )));
                    }
                }
            }
        }
        return Ok(());
    }
    let Some(target) = crate::nodes::command_target(&n.ty, &n.cfg) else {
        return Ok(());
    };
    let full = crate::scope::full_key(site, &target);
    let Some(auth) = who.claims.as_ref().and_then(|c| c.auth.as_ref()) else {
        return Err(denied(
            "trigger needs the rights of the caller: a token with `auth` (spec 04)".into(),
        ));
    };
    let needed = maxperm.max(Perm::Write);
    if !holds_key(auth, &full, needed) {
        return Err(denied(format!(
            "{full}: the caller does not hold {} on it",
            needed.name()
        )));
    }
    Ok(())
}

/// A library block's definition is at most this large (CBOR).
const MAX_BLOCK_BYTES: usize = 256 * 1024;

fn name_arg(args: &Value) -> Result<String, LinkError> {
    match args {
        Value::Map(m) => match m.get("name") {
            Some(Value::Str(n)) => Ok(n.clone()),
            _ => Err(LinkError::invalid_parameter("name: required string")),
        },
        _ => Err(LinkError::invalid_parameter("name: required string")),
    }
}

/// A block of the library: its version and its definition.
fn library_block(host: &FlowHost, name: &str) -> Option<(u64, Value)> {
    let store = host.store();
    let rec = store.state().blocks.get(name)?;
    let v = wyrm_core::codec::from_slice::<Value>(&rec.cbor).ok()?;
    Some((rec.version, v))
}

/// The library blocks that `block` (named `name`) uses, and the ones those use: name →
/// definition. A block it names that the library does not hold is `invalid_parameter`.
fn library_with(
    host: &FlowHost,
    name: &str,
    block: &Value,
) -> Result<BTreeMap<String, Value>, LinkError> {
    let bad = |e: def::DefError| LinkError::invalid_parameter(e.0);
    let mut found: BTreeMap<String, Value> = BTreeMap::new();
    let mut todo: Vec<String> = def::parse_block(name, block)
        .map_err(bad)?
        .uses()
        .into_iter()
        .collect();
    while let Some(dep) = todo.pop() {
        if dep == name || found.contains_key(&dep) {
            continue;
        }
        let (_, v) = library_block(host, &dep).ok_or_else(|| {
            LinkError::invalid_parameter(format!(
                "blocks.{name}: it uses the block {dep}, which the library does not hold"
            ))
        })?;
        todo.extend(def::parse_block(&dep, &v).map_err(bad)?.uses());
        found.insert(dep, v);
    }
    Ok(found)
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
    // one proof per target key: two blocks with one target share it (a token is taken once)
    let unique: std::collections::BTreeSet<String> = targets(&def, site).into_iter().collect();
    for t in unique {
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
    /// Upstream sites' keys, as the links they command trust them (ADR 0018): a deployer at
    /// an upstream site proves its rights on a target here with a token its own site signed.
    pub proof_keys: Vec<wyrm_link_sdk::LimitedKey>,
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
        // live values of a draft in a sandbox whose sinks only report (ADR 0038 §5)
        ctx.declare_action(
            "",
            "preview",
            ActionMeta::new()
                .display("Preview")
                .param("def", def_param())
                .param("nodes", ParamMeta::of(TypeCode::Array))
                .param("max_hz", ParamMeta::of(TypeCode::Number))
                .result(ActionResult::Stream)
                .stream(true)
                .timeout_ms(live::TIMEOUT_MS)
                .level(Perm::Read),
        )
        .await?;
        // the site's library of custom blocks (ADR 0040 §3): an editor copies a block from
        // here into the definition it deploys
        ctx.declare_action(
            "",
            "put_block",
            ActionMeta::new()
                .display("Put Block")
                .param("name", ParamMeta::of(TypeCode::String).required(true))
                .param("def", def_param())
                .result(ActionResult::Type(TypeCode::Map))
                .level(Perm::Config),
        )
        .await?;
        ctx.declare_action(
            "",
            "remove_block",
            ActionMeta::new()
                .display("Remove Block")
                .param("name", ParamMeta::of(TypeCode::String).required(true))
                .level(Perm::Config),
        )
        .await?;
        ctx.declare_action(
            "",
            "get_block",
            ActionMeta::new()
                .display("Get Block")
                .param("name", ParamMeta::of(TypeCode::String).required(true))
                .result(ActionResult::Type(TypeCode::Map))
                .level(Perm::Read),
        )
        .await?;
        ctx.declare_action(
            "",
            "list_blocks",
            ActionMeta::new()
                .display("List Blocks")
                .result(ActionResult::Type(TypeCode::Array))
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
            watches: Arc::new(Watches::default()),
            previews: Arc::new(crate::preview::registry()),
            streams: Vec::new(),
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
            verifier: Verifier::new(cfg.admin_keys, ctx.site()).with_limited(cfg.proof_keys),
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
                reads_sources(&raw, who, &self.site)?;
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
            ("", "preview") => {
                // a draft: compiled as for deploy, run with the caller's rights to read, never
                // stored; no `maxperm` or proofs, as nothing is written
                let (def, ports) = compile(&def_arg()?, &st.host.artifacts, &st.host.site)
                    .map_err(|e| LinkError::invalid_parameter(e.0))?;
                reads_flow(&def, who, &self.site)?;
                let only = live::only(&args, &def)?;
                let period = live::period(&args)?;
                let subject = deployer(who).unwrap_or_default();
                let ticket = st.previews.open(&subject, &subject)?;
                let p = crate::preview::start(
                    &def,
                    &ports,
                    &st.ctx,
                    &st.host.site,
                    &st.host.artifacts,
                )?;
                let task = p.spawn(only, period, ticket, out);
                st.streams.retain(|t| !t.is_finished());
                st.streams.push(task);
                return Ok(());
            }
            ("", "node_types") => {
                drop(st);
                return out.reply(crate::catalog::value()).await;
            }
            ("", "put_block") => {
                let name = name_arg(&args)?;
                let block = def_arg()?;
                let cbor = wyrm_core::codec::to_vec(&block)
                    .map_err(|e| LinkError::invalid_parameter(format!("def: {e}")))?;
                if cbor.len() > MAX_BLOCK_BYTES {
                    return Err(LinkError::invalid_parameter(format!(
                        "def: larger than {MAX_BLOCK_BYTES} bytes"
                    )));
                }
                // it must work as a block: alone in a flow, with the library blocks it uses
                let mut blocks = library_with(&st.host, &name, &block)?;
                blocks.insert(name.clone(), block);
                let probe = Value::Map(BTreeMap::from([
                    ("id".to_owned(), Value::from("block")),
                    ("blocks".to_owned(), Value::Map(blocks)),
                    (
                        "nodes".to_owned(),
                        Value::Map(BTreeMap::from([(
                            "b".to_owned(),
                            Value::Map(BTreeMap::from([(
                                "type".to_owned(),
                                Value::Str(format!("{}{name}", def::BLOCK_PREFIX)),
                            )])),
                        )])),
                    ),
                ]));
                compile(&probe, &st.host.artifacts, &st.host.site)
                    .map_err(|e| LinkError::invalid_parameter(e.0))?;
                st.host.apply(Op::PutBlock {
                    name: name.clone(),
                    cbor,
                })?;
                let version = st
                    .host
                    .store()
                    .state()
                    .blocks
                    .get(&name)
                    .map_or(0, |b| b.version);
                drop(st);
                info!(block = %name, version, "custom block stored");
                return out
                    .reply(Value::Map(BTreeMap::from([
                        ("name".to_owned(), Value::Str(name)),
                        ("version".to_owned(), Value::UInt(version)),
                    ])))
                    .await;
            }
            ("", "remove_block") => {
                let name = name_arg(&args)?;
                if !st.host.store().state().blocks.contains_key(&name) {
                    return Err(LinkError::not_found(format!("block {name}")));
                }
                st.host.apply(Op::RemoveBlock(name))?;
            }
            ("", "get_block") => {
                let name = name_arg(&args)?;
                let (version, block) = library_block(&st.host, &name)
                    .ok_or_else(|| LinkError::not_found(format!("block {name}")))?;
                // with every library block it uses, so the editor copies all of them
                let requires = library_with(&st.host, &name, &block)?;
                drop(st);
                return out
                    .reply(Value::Map(BTreeMap::from([
                        ("name".to_owned(), Value::Str(name)),
                        ("version".to_owned(), Value::UInt(version)),
                        ("def".to_owned(), block),
                        ("requires".to_owned(), Value::Map(requires)),
                    ])))
                    .await;
            }
            ("", "list_blocks") => {
                let names: Vec<String> = st.host.store().state().blocks.keys().cloned().collect();
                let mut rows = Vec::new();
                for name in names {
                    let Some((version, block)) = library_block(&st.host, &name) else {
                        continue;
                    };
                    let mut row = BTreeMap::from([
                        ("name".to_owned(), Value::Str(name.clone())),
                        ("version".to_owned(), Value::UInt(version)),
                    ]);
                    if let Ok(b) = def::parse_block(&name, &block) {
                        let names =
                            |n: Vec<String>| Value::Array(n.into_iter().map(Value::Str).collect());
                        row.insert(
                            "inputs".into(),
                            names(b.inputs.iter().map(|i| i.name.clone()).collect()),
                        );
                        row.insert(
                            "outputs".into(),
                            names(b.outputs.iter().map(|o| o.name.clone()).collect()),
                        );
                        if let Some(d) = b.description {
                            row.insert("description".into(), Value::Str(d));
                        }
                    }
                    rows.push(Value::Map(row));
                }
                drop(st);
                return out.reply(Value::Array(rows)).await;
            }
            ("", "validate") => {
                let mut m = BTreeMap::new();
                match compile(&def_arg()?, &st.host.artifacts, &st.host.site) {
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
                reads_sources(&raw, who, &self.site)?;
                proves_targets(&raw, &args, who, &self.site, &self.verifier)?;
                st.deploy(raw, Some(deployer(who)), &shared).await?
            }
            (id, "watch" | "ports") => {
                let f = st
                    .flows
                    .get(id)
                    .ok_or_else(|| LinkError::not_found(id.to_owned()))?;
                // the values of a flow come from its sources and its command targets
                reads_flow(&f.def, who, &self.site)?;
                let only = live::only(&args, &f.def)?;
                let probe = f.probe.clone();
                st.streams.retain(|t| !t.is_finished());
                if action == "ports" {
                    st.streams.push(tokio::spawn(async move {
                        let row = live::ports(&probe, only.as_ref()).await;
                        let _ = out.reply(row).await;
                    }));
                    return Ok(());
                }
                let period = live::period(&args)?;
                let ticket = st.watches.open(id, &deployer(who).unwrap_or_default())?;
                st.streams.push(tokio::spawn(async move {
                    let rows = out.clone();
                    let cancel = ticket.cancelled();
                    let last = live::run(probe, only, period, live::TTL, cancel, move |v| {
                        let rows = rows.clone();
                        async move { rows.reply(v).await.is_ok() }
                    })
                    .await;
                    let _ = out.done(last).await;
                    drop(ticket);
                }));
                return Ok(());
            }
            (id, "trigger") => {
                // ADR 0040 §2: one run of a command block of a deployed, running flow, with
                // the rights the block's target asks of the caller itself
                let f = st
                    .flows
                    .get(id)
                    .ok_or_else(|| LinkError::not_found(id.to_owned()))?;
                let node = match &args {
                    Value::Map(m) => match m.get("node") {
                        Some(Value::Str(n)) => n.clone(),
                        _ => return Err(LinkError::invalid_parameter("node: required string")),
                    },
                    _ => return Err(LinkError::invalid_parameter("node: required string")),
                };
                let n = f
                    .def
                    .nodes
                    .get(&node)
                    .filter(|n| crate::nodes::triggerable(&n.ty))
                    .ok_or_else(|| {
                        LinkError::invalid_parameter(format!(
                            "node: {node} is not a block that trigger runs (invoke, set, a reader)"
                        ))
                    })?;
                triggers(n, f.def.maxperm, who, &self.site)?;
                let inbox = f
                    .run
                    .as_ref()
                    .and_then(|r| r.inboxes.get(&node))
                    .ok_or_else(|| LinkError::not_supported("the flow is not running"))?;
                inbox.push_now(
                    "__trigger",
                    crate::nodes::Msg::new(Value::Null, Quality::Good, now_us()),
                );
            }
            (id, "remove") => {
                if let Some(f) = st.flows.get(id) {
                    f.probe.end(live::End::Gone);
                }
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

    /// When it returns, nothing the engine started runs any more: previews, watches and
    /// `ports` answers have ended, every flow is halted (its supervisor and node tasks
    /// awaited). The SDK then drops the engine before `LinkHandle::stop` returns, so the
    /// store and its lock are free for the next instance at once (ADR 0038 §6).
    async fn stop(&mut self) {
        let mut st = self.shared.lock().await;
        // streams end first: a preview stops its sandbox, a watch ends without a row
        st.previews.cancel_all();
        for f in st.flows.values() {
            f.probe.end(live::End::Gone);
        }
        let deadline = tokio::time::Instant::now() + Duration::from_secs(2);
        for mut t in std::mem::take(&mut st.streams) {
            // one that does not end in time is cut (a preview's runtime goes with its task)
            // and awaited: an aborted task is dropped only later by the runtime
            if tokio::time::timeout_at(deadline, &mut t).await.is_err() {
                t.abort();
                let _ = t.await;
            }
        }
        let ids: Vec<String> = st.flows.keys().cloned().collect();
        for id in ids {
            st.halt(&id).await;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use wyrm_core::ptok::PtokClaims;

    fn caller(auth: Option<Vec<Grant>>) -> Caller {
        Caller {
            origin: None,
            perm: Perm::Read,
            claims: Some(PtokClaims {
                sub: "user:v".into(),
                roles: Vec::new(),
                grants: Vec::new(),
                max: Perm::Read,
                iat: 0,
                exp: 0,
                jti: [0; 16],
                site: "s".into(),
                auth,
                args: None,
            }),
        }
    }

    /// ADR 0038 §3: `watch` and `ports` name the first source the caller may not read.
    #[test]
    fn a_watcher_reads_every_source() {
        let m = |kv: &[(&str, Value)]| {
            Value::Map(
                kv.iter()
                    .map(|(k, v)| ((*k).to_owned(), v.clone()))
                    .collect(),
            )
        };
        let src = |k: &str| m(&[("type", Value::from("subscribe")), ("key", Value::from(k))]);
        let def = def::parse(&m(&[
            ("id", Value::from("f")),
            (
                "nodes",
                m(&[("a", src("downstream/l/p")), ("b", src("storage/x"))]),
            ),
        ]))
        .unwrap();
        let g = |k: &str| Grant {
            k: k.into(),
            p: Perm::Read,
        };
        let e = reads_sources_of(&def, &caller(None), "s", "the caller").unwrap_err();
        assert_eq!(e.status, Status::PermissionDenied);
        let one = caller(Some(vec![g("wy/s/downstream/**")]));
        let e = reads_sources_of(&def, &one, "s", "the caller").unwrap_err();
        assert!(
            e.message
                .contains("wy/s/storage/x: the caller may not read it"),
            "{e}"
        );
        let both = caller(Some(vec![g("wy/s/downstream/**"), g("wy/s/storage/**")]));
        reads_sources_of(&def, &both, "s", "the caller").unwrap();
        reads_flow(&def, &both, "s").unwrap();
    }

    /// Security review of ADR 0038: an `invoke` node's output carries its target's answer, so
    /// a watcher reads every command target too.
    #[test]
    fn a_watcher_reads_every_command_target() {
        let m = |kv: &[(&str, Value)]| {
            Value::Map(
                kv.iter()
                    .map(|(k, v)| ((*k).to_owned(), v.clone()))
                    .collect(),
            )
        };
        let s = |x: &str| Value::from(x);
        let def = def::parse(&m(&[
            ("id", s("f")),
            (
                "nodes",
                m(&[
                    (
                        "a",
                        m(&[("type", s("subscribe")), ("key", s("downstream/l/p"))]),
                    ),
                    (
                        "cmd",
                        m(&[
                            ("type", s("invoke")),
                            ("path", s("downstream/secret/dev")),
                            ("action", s("read_all")),
                        ]),
                    ),
                    ("w", m(&[("type", s("set")), ("path", s("storage/out"))])),
                ]),
            ),
            ("permissions", m(&[("maxperm", s("write"))])),
        ]))
        .unwrap();
        let g = |k: &str| Grant {
            k: k.into(),
            p: Perm::Read,
        };
        let sources = caller(Some(vec![g("wy/s/downstream/l/**")]));
        let e = reads_flow(&def, &sources, "s").unwrap_err();
        assert_eq!(e.status, Status::PermissionDenied);
        assert!(
            e.message
                .contains("wy/s/downstream/secret/dev: the caller may not read it"),
            "{e}"
        );
        let no_set = caller(Some(vec![
            g("wy/s/downstream/l/**"),
            g("wy/s/downstream/secret/**"),
        ]));
        let e = reads_flow(&def, &no_set, "s").unwrap_err();
        assert!(e.message.contains("wy/s/storage/out:"), "{e}");
        // a deny grant on the target comes first and decides
        let denied = caller(Some(vec![
            Grant {
                k: "wy/s/downstream/secret/**".into(),
                p: Perm::None,
            },
            g("wy/s/**"),
        ]));
        assert!(reads_flow(&def, &denied, "s").is_err());
        let all = caller(Some(vec![g("wy/s/**")]));
        reads_flow(&def, &all, "s").unwrap();
        // no `auth` at all
        assert!(reads_flow(&def, &caller(None), "s").is_err());
    }

    /// ADR 0040 §1: a scope is read whole. A deny grant on a part refuses it wherever it
    /// stands before the grant that covers it; a read grant on a part leaves the rest to the
    /// grants after it.
    #[test]
    fn a_scope_is_read_whole() {
        let g = |k: &str, p: Perm| Grant { k: k.into(), p };
        let scope = "wy/s/downstream/modbus/line1/**";
        assert!(reads_key(&[g("wy/s/downstream/**", Perm::Read)], scope));
        assert!(reads_key(&[g(scope, Perm::Read)], scope));
        // a part only
        assert!(!reads_key(
            &[g("wy/s/downstream/modbus/line1/t1", Perm::Read)],
            scope
        ));
        // a part, then the whole
        assert!(reads_key(
            &[
                g("wy/s/downstream/modbus/line1/t1", Perm::Write),
                g("wy/s/downstream/**", Perm::Read)
            ],
            scope
        ));
        // a deny on a part, before or after another part
        assert!(!reads_key(
            &[
                g("wy/s/downstream/modbus/line1/secret/**", Perm::None),
                g("wy/s/**", Perm::Read)
            ],
            scope
        ));
        assert!(!reads_key(
            &[
                g("wy/s/downstream/modbus/line1/t1", Perm::Read),
                g("wy/s/downstream/modbus/line1/secret", Perm::None),
                g("wy/s/**", Perm::Read)
            ],
            scope
        ));
        // a deny after the grant that covers it never applies
        assert!(reads_key(
            &[
                g("wy/s/**", Perm::Read),
                g("wy/s/downstream/modbus/line1/secret", Perm::None)
            ],
            scope
        ));
        assert!(!reads_key(&[], scope));
        // the deploy check names the scope
        let m = |kv: &[(&str, Value)]| {
            Value::Map(
                kv.iter()
                    .map(|(k, v)| ((*k).to_owned(), v.clone()))
                    .collect(),
            )
        };
        let def = def::parse(&m(&[
            ("id", Value::from("f")),
            (
                "nodes",
                m(&[(
                    "a",
                    m(&[
                        ("type", Value::from("subscribe")),
                        ("key", Value::from("downstream/modbus/line1/t1")),
                        ("key_scope", Value::from("downstream/modbus/line1/**")),
                    ]),
                )]),
            ),
        ]))
        .unwrap();
        let one = caller(Some(vec![g("wy/s/downstream/modbus/line1/t1", Perm::Read)]));
        let e = reads_sources_of(&def, &one, "s", "the deployer").unwrap_err();
        assert!(
            e.message
                .contains("wy/s/downstream/modbus/line1/**: the deployer may not read it"),
            "{e}"
        );
        assert!(reads_flow(&def, &one, "s").is_err());
        let all = caller(Some(vec![g("wy/s/downstream/modbus/**", Perm::Read)]));
        reads_sources_of(&def, &all, "s", "the deployer").unwrap();
        reads_flow(&def, &all, "s").unwrap();
        // the compiler's site check covers a scope
        let bad = def::parse(&m(&[
            ("id", Value::from("f")),
            (
                "nodes",
                m(&[(
                    "a",
                    m(&[
                        ("type", Value::from("subscribe")),
                        ("key_scope", Value::from("wy/*/downstream/**")),
                    ]),
                )]),
            ),
        ]))
        .unwrap();
        let e = check_sources(&bad, "s").unwrap_err();
        assert!(e.0.contains("nodes.a.key_scope"), "{e}");
    }

    /// ADR 0040 §2 (security review): `trigger` asks of the caller what the deploy asked of
    /// the deployer's proof, `max(maxperm, write)` on the block's target. A flow whose token
    /// carried `config` must not be run by a caller that holds only `write` there.
    #[test]
    fn a_reader_runs_on_trigger_for_a_caller_who_reads_it() {
        let m = |kv: &[(&str, Value)]| {
            Value::Map(
                kv.iter()
                    .map(|(k, v)| ((*k).to_owned(), v.clone()))
                    .collect(),
            )
        };
        let s = |x: &str| Value::from(x);
        let def = def::parse(&m(&[
            ("id", s("f")),
            (
                "nodes",
                m(&[
                    (
                        "h",
                        m(&[
                            ("type", s("load_history")),
                            ("key", s("downstream/l/t1")),
                            ("key_scope", s("downstream/l/*")),
                        ]),
                    ),
                    (
                        "c",
                        m(&[("type", s("list_children")), ("path", s("downstream/l"))]),
                    ),
                ]),
            ),
        ]))
        .unwrap();
        let g = |k: &str, p: Perm| Grant { k: k.into(), p };
        let (h, c) = (def.nodes["h"].clone(), def.nodes["c"].clone());
        // read is enough for a reader: it runs no command
        let reader = caller(Some(vec![g("wy/s/**", Perm::Read)]));
        triggers(&h, def.maxperm, &reader, "s").unwrap();
        triggers(&c, def.maxperm, &reader, "s").unwrap();
        // the scope is read as a whole: one denied key inside refuses it
        let holed = caller(Some(vec![
            g("wy/s/downstream/l/secret", Perm::None),
            g("wy/s/**", Perm::Read),
        ]));
        let e = triggers(&h, def.maxperm, &holed, "s").unwrap_err();
        assert_eq!(e.status, Status::PermissionDenied);
        assert!(e.message.contains("downstream/l/*"), "{e}");
        // list_children: the children too
        let e = triggers(&c, def.maxperm, &holed, "s").unwrap_err();
        assert!(e.message.contains("children"), "{e}");
        assert!(triggers(&h, def.maxperm, &caller(None), "s").is_err());
        let other = caller(Some(vec![g("wy/s/storage/**", Perm::Config)]));
        assert!(triggers(&h, def.maxperm, &other, "s").is_err());
    }

    #[test]
    fn trigger_needs_the_level_of_the_flows_token() {
        let m = |kv: &[(&str, Value)]| {
            Value::Map(
                kv.iter()
                    .map(|(k, v)| ((*k).to_owned(), v.clone()))
                    .collect(),
            )
        };
        let s = |x: &str| Value::from(x);
        let mut def = def::parse(&m(&[
            ("id", s("f")),
            (
                "nodes",
                m(&[
                    (
                        "cmd",
                        m(&[
                            ("type", s("invoke")),
                            ("path", s("downstream/l/dev")),
                            ("action", s("edit")),
                        ]),
                    ),
                    ("w", m(&[("type", s("set")), ("path", s("storage/out"))])),
                ]),
            ),
            ("permissions", m(&[("maxperm", s("write"))])),
        ]))
        .unwrap();
        let g = |k: &str, p: Perm| Grant { k: k.into(), p };
        let cmd = def.nodes["cmd"].clone();
        let set = def.nodes["w"].clone();
        let writer = caller(Some(vec![g("wy/s/**", Perm::Write)]));
        let reader = caller(Some(vec![g("wy/s/**", Perm::Read)]));
        let admin = caller(Some(vec![g("wy/s/**", Perm::Config)]));
        // a flow at `write`: write on the target is enough, read is not, no `auth` neither
        triggers(&cmd, def.maxperm, &writer, "s").unwrap();
        triggers(&set, def.maxperm, &writer, "s").unwrap();
        let e = triggers(&cmd, def.maxperm, &reader, "s").unwrap_err();
        assert_eq!(e.status, Status::PermissionDenied);
        assert!(triggers(&cmd, def.maxperm, &caller(None), "s").is_err());
        // write elsewhere is not write on the target; a deny on the target comes first
        let elsewhere = caller(Some(vec![g("wy/s/storage/**", Perm::Write)]));
        assert!(triggers(&cmd, def.maxperm, &elsewhere, "s").is_err());
        let holed = caller(Some(vec![
            g("wy/s/downstream/l/dev/**", Perm::Read),
            g("wy/s/**", Perm::Config),
        ]));
        assert!(triggers(&cmd, def.maxperm, &holed, "s").is_err());
        // a flow whose token carries `config` (the compiler caps `maxperm` at write today;
        // the gate must hold if that cap ever moves): a writer is refused, an admin is not
        def.maxperm = Perm::Config;
        let e = triggers(&cmd, def.maxperm, &writer, "s").unwrap_err();
        assert_eq!(e.status, Status::PermissionDenied);
        assert!(
            e.message
                .contains("wy/s/downstream/l/dev/~act/edit: the caller does not hold config"),
            "{e}"
        );
        assert!(triggers(&set, def.maxperm, &writer, "s").is_err());
        triggers(&cmd, def.maxperm, &admin, "s").unwrap();
        // a flow at `read` still needs write: a trigger is a command
        def.maxperm = Perm::Read;
        assert!(triggers(&cmd, def.maxperm, &reader, "s").is_err());
        triggers(&cmd, def.maxperm, &writer, "s").unwrap();
    }

    /// Security review 2026-11-10: `list_children` shows a row per child, so the deployer and
    /// every watcher read the children as a whole, for the static path and for the scope.
    #[test]
    fn list_children_needs_the_children() {
        let m = |kv: &[(&str, Value)]| {
            Value::Map(
                kv.iter()
                    .map(|(k, v)| ((*k).to_owned(), v.clone()))
                    .collect(),
            )
        };
        let s = |x: &str| Value::from(x);
        let g = |k: &str, p: Perm| Grant { k: k.into(), p };
        let flow = |cfg: &[(&str, Value)]| {
            let mut n = vec![("type", s("list_children"))];
            n.extend(cfg.iter().cloned());
            def::parse(&m(&[("id", s("f")), ("nodes", m(&[("l", m(&n))]))])).unwrap()
        };
        let fixed = flow(&[("path", s("downstream/l/room"))]);
        // the folder alone is not enough
        let folder = caller(Some(vec![g("wy/s/downstream/l/room", Perm::Read)]));
        let e = reads_sources_of(&fixed, &folder, "s", "the deployer").unwrap_err();
        assert_eq!(e.status, Status::PermissionDenied);
        assert!(
            e.message
                .contains("wy/s/downstream/l/room/*: the deployer may not read the children"),
            "{e}"
        );
        assert!(reads_flow(&fixed, &folder, "s").is_err(), "a watcher too");
        // one child denied: its row would show, so it is refused whole
        let holed = caller(Some(vec![
            g("wy/s/downstream/l/room/secret", Perm::None),
            g("wy/s/downstream/**", Perm::Read),
        ]));
        assert!(reads_sources_of(&fixed, &holed, "s", "the deployer").is_err());
        assert!(reads_flow(&fixed, &holed, "s").is_err());
        // a deny deeper than the children does not matter: rows are one level
        let deep = caller(Some(vec![
            g("wy/s/downstream/l/room/a/secret", Perm::None),
            g("wy/s/downstream/**", Perm::Read),
        ]));
        reads_sources_of(&fixed, &deep, "s", "the deployer").unwrap();
        let all = caller(Some(vec![g("wy/s/downstream/l/**", Perm::Read)]));
        reads_sources_of(&fixed, &all, "s", "the deployer").unwrap();
        reads_flow(&fixed, &all, "s").unwrap();
        // a scope: the children of every node it admits
        let scoped = flow(&[("path_scope", s("downstream/l/*"))]);
        let level = caller(Some(vec![g("wy/s/downstream/l/*", Perm::Read)]));
        assert!(reads_sources_of(&scoped, &level, "s", "the deployer").is_err());
        let two = caller(Some(vec![
            g("wy/s/downstream/l/*", Perm::Read),
            g("wy/s/downstream/l/*/*", Perm::Read),
        ]));
        reads_sources_of(&scoped, &two, "s", "the deployer").unwrap();
        // `**` as a scope has its children in canonical form
        assert_eq!(
            crate::scope::children_of("wy/s/downstream/l/**").as_deref(),
            Some("wy/s/downstream/l/*/**")
        );
        let wide = flow(&[("path_scope", s("downstream/l/**"))]);
        reads_sources_of(&wide, &all, "s", "the deployer").unwrap();
        assert!(reads_sources_of(&wide, &holed, "s", "the deployer").is_err());
        // a subscribe of the same key asks for no children
        let sub = def::parse(&m(&[
            ("id", s("f")),
            (
                "nodes",
                m(&[(
                    "a",
                    m(&[("type", s("subscribe")), ("key", s("downstream/l/room"))]),
                )]),
            ),
        ]))
        .unwrap();
        reads_sources_of(&sub, &folder, "s", "the deployer").unwrap();
    }
}
