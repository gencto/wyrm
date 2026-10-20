//! The admin service.
//!
//! [`Control`] survives broker reloads: registry and audit stores, the CA,
//! the process supervisor. [`Control::attach`] runs, per broker instance, the
//! `wy/<site>/sys/**` responder (an SDK link rooted at `sys`) and three
//! watchers: link states (liveliness + supervisor), quarantine (link events
//! with an unknown certificate CN) and `acl_denied_total` (router metrics).
//!
//! Zenoh 1.10 cannot reload `access_control` live (ADR 0004), so changes that
//! alter the ACL (install/remove of a process or external link, approve) ask
//! the host to rebuild the router runtime through the reload channel.

use crate::acl;
use crate::audit::{AuditLog, AuditRecord};
use crate::registry::{LinkDef, Mode, Op, Origin, Registry};
use crate::secret::{self, CertFiles, Error, Pki};
use crate::supervisor::{ProcSpec, ProcState, Supervisor};
use std::collections::{BTreeMap, HashMap, HashSet};
use std::future::Future;
use std::path::PathBuf;
use std::pin::Pin;
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tokio::sync::{mpsc, Mutex as AsyncMutex};
use tokio::task::JoinHandle;
use tracing::{debug, info, warn};
use wyrm_core::meta::{is_code, ActionResult, ParamMeta, Profile};
use wyrm_core::{ActionMeta, NodeMeta, Perm, Quality, Status, TypeCode, Value};
use wyrm_link_sdk::{
    now_us, Caller, Link, LinkConfig, LinkCtx, LinkError, LinkHandle, ReplySink, VerifyingKey,
};
use wyrm_state::{StateError, Store};
use zenoh::Session;

pub type BoxFut<'a, T> = Pin<Box<dyn Future<Output = T> + Send + 'a>>;

/// A link running in-process; stopped on remove or broker reload.
pub trait RunningLink: Send {
    fn stop(self: Box<Self>) -> BoxFut<'static, ()>;
}

/// Drivers compiled into the broker binary (implemented by `wyrmd`).
pub trait EmbeddedHost: Send + Sync + 'static {
    fn drivers(&self) -> Vec<&'static str>;
    /// Build the driver config from params without starting it.
    fn validate(&self, driver: &str, params: &Value) -> Result<(), LinkError>;
    fn start(
        &self,
        session: Session,
        cfg: LinkConfig,
        driver: String,
        params: Value,
    ) -> BoxFut<'static, Result<Box<dyn RunningLink>, LinkError>>;
}

#[derive(Debug, Clone)]
pub struct ControlConfig {
    pub site: String,
    pub data_dir: PathBuf,
    pub admin_keys: Vec<VerifyingKey>,
    /// Extra keys trusted by links only, never by the admin itself (the flow
    /// engine signs flow commands with one: a flow may command devices, not
    /// the control plane).
    pub link_keys: Vec<VerifyingKey>,
    /// Certificate CNs with requester rights (engineering tools).
    pub operators: Vec<String>,
    /// `dev` profile: loopback sessions get full rights.
    pub dev: bool,
    /// Where process links connect (`tls/127.0.0.1:7447`); `None` = no
    /// process mode (it needs mTLS for a per-link ACL).
    pub link_endpoint: Option<String>,
    /// SANs of the broker certificate.
    pub tls_names: Vec<String>,
    pub metrics_interval: Duration,
    /// Program that hosts a driver as a process: `<link_exe> link <driver>`.
    pub link_exe: PathBuf,
    pub max_restarts: u32,
}

/// Link id of the flow engine (rooted at `wy/<site>/flows`); reserved.
pub const FLOWS_LINK: &str = "flows";

/// A link declared in `wyrmd.json5`.
#[derive(Debug, Clone)]
pub struct ConfigLink {
    pub id: String,
    pub driver: String,
    pub mode: Mode,
    pub params: Value,
}

const STATES: [&str; 6] = [
    "installed",
    "starting",
    "connected",
    "stopping",
    "stopped",
    "failed",
];

pub struct Control {
    cfg: ControlConfig,
    store: Mutex<Store<Registry>>,
    audit: Mutex<Store<AuditLog>>,
    pki: Pki,
    secrets: crate::secrets::SecretStore,
    supervisor: Arc<Supervisor>,
    host: Arc<dyn EmbeddedHost>,
    reload: mpsc::UnboundedSender<()>,
    peers: Mutex<PeerConfig>,
}

/// Router-to-router setup (iteration 4): peer sites and their CA files.
#[derive(Debug, Clone, Default)]
pub struct PeerConfig {
    pub peers: acl::Peers,
    /// CA certificates of peer sites; trusted only on the QUIC broker listener.
    pub trusted_cas: Vec<PathBuf>,
}

fn now_s() -> u64 {
    now_us() / 1_000_000
}

fn encode_params(v: &Value) -> Result<Vec<u8>, LinkError> {
    wyrm_core::codec::to_vec(v).map_err(|e| LinkError::internal(e.to_string()))
}

fn decode_params(b: &[u8]) -> Value {
    wyrm_core::codec::from_slice(b).unwrap_or(Value::Map(Default::default()))
}

fn rejected(e: StateError) -> LinkError {
    match e {
        StateError::Rejected(why) => LinkError::invalid_parameter(why),
        other => LinkError::internal(other.to_string()),
    }
}

fn sub_of(who: &Caller) -> String {
    who.claims
        .as_ref()
        .map(|c| c.sub.clone())
        .unwrap_or_else(|| "anonymous".into())
}

impl Control {
    /// Open stores and the CA under `data_dir`. The receiver yields reload
    /// requests (ACL changed).
    pub fn open(
        cfg: ControlConfig,
        host: Arc<dyn EmbeddedHost>,
    ) -> Result<(Arc<Self>, mpsc::UnboundedReceiver<()>), Error> {
        std::fs::create_dir_all(&cfg.data_dir)?;
        let key = secret::load_or_create_key(&cfg.data_dir.join("state.key"))?;
        let store = Store::<Registry>::open(cfg.data_dir.join("state"), &key)?;
        let audit = Store::<AuditLog>::open(cfg.data_dir.join("audit"), &key)?;
        let pki = Pki::open_or_create(&cfg.data_dir.join("pki"))?;
        let secrets = crate::secrets::SecretStore::open(&cfg.data_dir)?;
        let (reload, rx) = mpsc::unbounded_channel();
        Ok((
            Arc::new(Self {
                cfg,
                store: Mutex::new(store),
                audit: Mutex::new(audit),
                pki,
                secrets,
                supervisor: Supervisor::new(),
                host,
                reload,
                peers: Mutex::new(PeerConfig::default()),
            }),
            rx,
        ))
    }

    pub fn config(&self) -> &ControlConfig {
        &self.cfg
    }

    pub fn registry(&self) -> Registry {
        self.store
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .state()
            .clone()
    }

    pub fn ca_path(&self) -> PathBuf {
        self.pki.ca_path()
    }

    pub fn audit_tail(&self, n: usize) -> Vec<AuditRecord> {
        let a = self.audit.lock().unwrap_or_else(|p| p.into_inner());
        let r = &a.state().recent;
        r.iter().skip(r.len().saturating_sub(n)).cloned().collect()
    }

    fn apply(&self, op: Op) -> Result<(), StateError> {
        self.store
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .apply(op)
            .map(|_| ())
    }

    fn record(&self, sub: &str, op: &str, key: &str, status: Status, detail: &str) {
        let rec = AuditRecord {
            t: now_us(),
            sub: sub.to_owned(),
            op: op.to_owned(),
            key: key.to_owned(),
            status: status.code(),
            detail: detail.to_owned(),
        };
        if let Err(e) = self
            .audit
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .apply(rec)
        {
            warn!("audit write failed: {e}");
        }
    }

    /// Keys a link verifies `ptok`s with: admin keys plus `link_keys`.
    fn link_trust(&self) -> Vec<VerifyingKey> {
        let mut keys = self.cfg.admin_keys.clone();
        keys.extend(self.cfg.link_keys.iter().copied());
        keys
    }

    /// Secrets of one link for the SDK (embedded start, `hello` reply).
    fn link_secrets(&self, id: &str) -> wyrm_link_sdk::SecretStore {
        self.secrets
            .for_link(id)
            .into_iter()
            .map(|(k, v)| (k, wyrm_link_sdk::Secret::new(v.to_vec())))
            .collect()
    }

    /// `data_dir/links/<id>`; refuses ids that could leave that directory.
    fn link_dir(&self, id: &str) -> Result<PathBuf, LinkError> {
        crate::registry::validate_link_id(id).map_err(LinkError::invalid_parameter)?;
        Ok(self.cfg.data_dir.join("links").join(id))
    }

    /// Certificate for a remote link (CN = id) under `links/<id>/`.
    pub fn link_cert(&self, id: &str) -> Result<CertFiles, Error> {
        self.pki.issue(id, &[], false, &self.link_dir(id)?, "link")
    }

    /// Certificate for an operator tool (CN = `cn`) under `operators/`.
    pub fn operator_cert(&self, cn: &str) -> Result<CertFiles, Error> {
        self.pki
            .issue(cn, &[], false, &self.cfg.data_dir.join("operators"), cn)
    }

    /// Issue the token of a remote link into `links/<id>/token` (0600);
    /// external links also get it back once.
    fn new_token_for(&self, id: &str, mode: Mode) -> Result<(String, Option<String>), LinkError> {
        if !mode.is_remote() {
            return Ok((String::new(), None));
        }
        let token = secret::new_token().map_err(|e| LinkError::internal(e.to_string()))?;
        let hash = secret::hash_token(&token).map_err(|e| LinkError::internal(e.to_string()))?;
        // 0600 file: the supervisor passes it to a process link; for an
        // external link the operator copies it to the device.
        secret::write_private(&self.link_dir(id)?.join("token"), token.as_bytes())
            .map_err(|e| LinkError::internal(e.to_string()))?;
        if mode == Mode::Process {
            return Ok((hash, None));
        }
        Ok((hash, Some(token.to_string())))
    }

    /// Bring the registry in line with `wyrmd.json5` (config-origin links).
    pub fn bootstrap(&self, links: &[ConfigLink]) -> Result<(), Error> {
        let reg = self.registry();
        for l in links {
            let params = encode_params(&l.params)?;
            if l.mode == Mode::Process && self.cfg.link_endpoint.is_none() {
                return Err(format!("{}: process mode needs a tls/ listener", l.id).into());
            }
            if !self.host.drivers().contains(&l.driver.as_str()) && l.mode != Mode::External {
                return Err(format!("{}: driver {} is not compiled in", l.id, l.driver).into());
            }
            crate::secrets::lint_params(&l.params, &format!("links.{}.params", l.id))?;
            if l.mode != Mode::External {
                self.host.validate(&l.driver, &l.params)?;
            }
            match reg.links.get(&l.id) {
                None => {
                    // A new link never inherits secrets of an earlier one.
                    self.secrets.drop_link(&l.id)?;
                    let (token_hash, _) = self.new_token_for(&l.id, l.mode)?;
                    self.apply(Op::Install(LinkDef {
                        id: l.id.clone(),
                        driver: l.driver.clone(),
                        mode: l.mode,
                        params,
                        token_hash,
                        rev: 1,
                        origin: Origin::Config,
                        created: now_s(),
                    }))?;
                    if l.mode.is_remote() {
                        self.link_cert(&l.id)?;
                    }
                    self.record("system", "install", &l.id, Status::Ok, "wyrmd.json5");
                }
                Some(d)
                    if d.origin == Origin::Config && (d.mode != l.mode || d.params != params) =>
                {
                    if l.mode.is_remote() && d.token_hash.is_empty() {
                        let (hash, _) = self.new_token_for(&l.id, l.mode)?;
                        self.apply(Op::SetTokenHash {
                            id: l.id.clone(),
                            hash,
                        })?;
                        self.link_cert(&l.id)?;
                    }
                    self.apply(Op::Update {
                        id: l.id.clone(),
                        mode: l.mode,
                        params,
                    })?;
                    self.record("system", "update", &l.id, Status::Ok, "wyrmd.json5");
                }
                Some(d) if d.origin == Origin::Runtime => {
                    warn!(link = %l.id, "installed at runtime; wyrmd.json5 entry ignored");
                }
                Some(_) => {}
            }
        }
        let wanted: HashSet<&str> = links.iter().map(|l| l.id.as_str()).collect();
        for d in reg.links.values() {
            if d.origin == Origin::Config && !wanted.contains(d.id.as_str()) {
                self.secrets.drop_link(&d.id)?;
                self.apply(Op::Remove(d.id.clone()))?;
                if let Ok(dir) = self.link_dir(&d.id) {
                    let _ = std::fs::remove_dir_all(dir);
                }
                self.record(
                    "system",
                    "remove",
                    &d.id,
                    Status::Ok,
                    "gone from wyrmd.json5",
                );
            }
        }
        Ok(())
    }

    /// TLS (broker certificate, mTLS) when `tls`, admin space (read-only,
    /// in-process only through the ACL) and the generated `access_control`.
    /// CA bundle of peer sites, for the QUIC broker listener's
    /// `#root_ca_certificate_file=` endpoint parameter.
    pub fn peer_trust_path(&self) -> PathBuf {
        self.cfg.data_dir.join("pki").join("peer-trust.pem")
    }

    /// Set peer brokers (takes effect on the next broker build).
    pub fn set_peers(&self, p: PeerConfig) {
        *self.peers.lock().unwrap_or_else(|e| e.into_inner()) = p;
    }

    pub fn configure_zenoh(&self, c: &mut zenoh::Config, tls: bool) -> Result<(), Error> {
        let peers = self.peers.lock().unwrap_or_else(|e| e.into_inner()).clone();
        if tls {
            let pki_dir = self.cfg.data_dir.join("pki");
            let cn = format!("broker:{}", self.cfg.site);
            // Server side (listeners) and client side (outbound to upstreams).
            let server =
                self.pki
                    .issue(&cn, &self.cfg.tls_names, true, &pki_dir, "broker-server")?;
            let client = self.pki.issue(&cn, &[], false, &pki_dir, "broker-client")?;
            // Peer CAs are trusted only on the QUIC broker listener (see
            // `peer_trust_path`); the global root is our own CA alone.
            if !peers.trusted_cas.is_empty() {
                let mut bundle = String::new();
                for ca in &peers.trusted_cas {
                    let pem = std::fs::read_to_string(ca)
                        .map_err(|e| format!("trusted CA {}: {e}", ca.display()))?;
                    if !pem.contains("BEGIN CERTIFICATE") {
                        return Err(
                            format!("trusted CA {}: not a PEM certificate", ca.display()).into(),
                        );
                    }
                    bundle.push_str(&pem);
                    bundle.push('\n');
                }
                std::fs::write(self.peer_trust_path(), bundle)?;
            }
            c.insert_json5(
                "transport/link/tls",
                &serde_json::json!({
                    "root_ca_certificate": self.pki.ca_path(),
                    "listen_certificate": server.cert,
                    "listen_private_key": server.key,
                    "connect_certificate": client.cert,
                    "connect_private_key": client.key,
                    "enable_mtls": true,
                })
                .to_string(),
            )?;
        }
        c.insert_json5(
            "adminspace",
            r#"{ enabled: true, permissions: { read: true, write: false } }"#,
        )?;
        let acl = acl::access_control_with_peers(
            &self.cfg.site,
            &self.registry(),
            &self.cfg.operators,
            self.cfg.dev,
            &peers.peers,
        );
        c.insert_json5("access_control", &acl.to_string())?;
        Ok(())
    }

    fn proc_spec(&self, def: &LinkDef) -> Option<ProcSpec> {
        let endpoint = self.cfg.link_endpoint.clone()?;
        let dir = self.link_dir(&def.id).ok()?;
        let cert = self.link_cert(&def.id).ok()?;
        Some(ProcSpec {
            id: def.id.clone(),
            exe: self.cfg.link_exe.clone(),
            args: vec!["link".into(), def.driver.clone()],
            env: vec![
                ("WYRM_SITE".into(), self.cfg.site.clone()),
                ("WYRM_LINK_ID".into(), def.id.clone()),
                ("WYRM_ENDPOINT".into(), endpoint),
                ("WYRM_CA".into(), self.pki.ca_path().display().to_string()),
                ("WYRM_CERT".into(), cert.cert.display().to_string()),
                ("WYRM_KEY".into(), cert.key.display().to_string()),
                (
                    "WYRM_TOKEN_FILE".into(),
                    dir.join("token").display().to_string(),
                ),
            ],
            max_restarts: self.cfg.max_restarts,
        })
    }

    fn schedule_reload(&self) {
        let tx = self.reload.clone();
        tokio::spawn(async move {
            // Let the current reply leave first.
            tokio::time::sleep(Duration::from_millis(300)).await;
            let _ = tx.send(());
        });
    }

    /// Stop all supervised processes (broker exit).
    pub async fn shutdown(&self) {
        self.supervisor.stop_all().await;
    }

    /// Run the admin responder, embedded links, process links and watchers
    /// on `session` (an in-process session of the router runtime).
    pub async fn attach(self: &Arc<Self>, session: Session) -> Result<Attached, Error> {
        let embedded: Running = Arc::new(AsyncMutex::new(HashMap::new()));
        let mut lcfg = LinkConfig::new(self.cfg.site.clone(), "admin");
        lcfg.root = Some(format!("wy/{}/sys", self.cfg.site));
        lcfg.admin_keys = self.cfg.admin_keys.clone();
        lcfg.open_actions = vec!["hello".into()];
        lcfg.audit = false; // the admin writes its own journal directly
        let admin = wyrm_link_sdk::spawn::<Admin>(
            session.clone(),
            lcfg,
            AdminStart {
                ctl: self.clone(),
                embedded: embedded.clone(),
            },
        )
        .await?;
        let ctx = admin.ctx().clone();
        for def in self.registry().links.values() {
            match def.mode {
                Mode::Embedded => {
                    if let Err(e) = start_embedded(self, &ctx, &embedded, def).await {
                        warn!(link = %def.id, "embedded start failed: {e}");
                    }
                }
                Mode::Process => match self.proc_spec(def) {
                    Some(spec) => self.supervisor.start(spec),
                    None => warn!(link = %def.id, "no tls listener for process mode"),
                },
                Mode::External => {}
            }
        }
        let tasks = vec![
            tokio::spawn(watch_states(self.clone(), ctx.clone(), embedded.clone())),
            tokio::spawn(watch_quarantine(self.clone(), ctx.clone())),
            tokio::spawn(watch_metrics(self.clone(), ctx.clone())),
            tokio::spawn(watch_audit(self.clone(), ctx.clone())),
        ];
        info!(site = %self.cfg.site, "admin attached");
        Ok(Attached {
            admin: Some(admin),
            embedded,
            tasks,
        })
    }
}

type Running = Arc<AsyncMutex<HashMap<String, Box<dyn RunningLink>>>>;

/// Admin state bound to one broker instance.
pub struct Attached {
    admin: Option<LinkHandle<Admin>>,
    embedded: Running,
    tasks: Vec<JoinHandle<()>>,
}

impl Attached {
    pub fn ctx(&self) -> Option<&LinkCtx> {
        self.admin.as_ref().map(|a| a.ctx())
    }

    /// Stop watchers, embedded links and the responder. Processes keep running.
    pub async fn stop(mut self) {
        for t in &self.tasks {
            t.abort();
        }
        let links: Vec<_> = self.embedded.lock().await.drain().collect();
        for (_, l) in links {
            l.stop().await;
        }
        if let Some(a) = self.admin.take() {
            a.stop().await;
        }
    }
}

async fn start_embedded(
    ctl: &Control,
    ctx: &LinkCtx,
    running: &Running,
    def: &LinkDef,
) -> Result<(), LinkError> {
    if running.lock().await.contains_key(&def.id) {
        return Ok(());
    }
    let mut lcfg = LinkConfig::new(ctl.cfg.site.clone(), def.id.clone());
    lcfg.admin_keys = ctl.link_trust();
    lcfg.secrets = ctl.link_secrets(&def.id);
    let link = ctl
        .host
        .start(
            ctx.client().clone(),
            lcfg,
            def.driver.clone(),
            decode_params(&def.params),
        )
        .await?;
    running.lock().await.insert(def.id.clone(), link);
    Ok(())
}

pub struct AdminStart {
    ctl: Arc<Control>,
    embedded: Running,
}

/// The `wy/<site>/sys/**` responder.
pub struct Admin {
    ctx: LinkCtx,
    ctl: Arc<Control>,
    embedded: Running,
}

fn str_param() -> ParamMeta {
    ParamMeta::of(TypeCode::String)
}

fn link_node(def: &LinkDef) -> NodeMeta {
    NodeMeta::folder()
        .is("wy:link-def")
        .attr("driver", def.driver.as_str())
        .attr("mode", def.mode.name())
        .attr("rev", u64::from(def.rev))
        .attr(
            "origin",
            match def.origin {
                Origin::Config => "config",
                Origin::Runtime => "runtime",
            },
        )
}

fn secret_name(args: &Value) -> Result<&str, LinkError> {
    match arg_str(args, "name") {
        Some(n)
            if !n.is_empty()
                && n.len() <= 64
                && n.bytes()
                    .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-') =>
        {
            Ok(n)
        }
        _ => Err(LinkError::invalid_parameter("name: [A-Za-z0-9_-]{1,64}")),
    }
}

async fn declare_link(ctx: &LinkCtx, def: &LinkDef) -> Result<(), LinkError> {
    let p = format!("links/{}", def.id);
    ctx.declare_node(&p, link_node(def)).await?;
    ctx.declare_node(
        &format!("{p}/state"),
        NodeMeta::leaf(TypeCode::Enum).enum_values(STATES),
    )
    .await?;
    for a in ["start", "stop", "remove"] {
        ctx.declare_action(&p, a, ActionMeta::new().level(Perm::Config))
            .await?;
    }
    ctx.declare_action(
        &p,
        "set_secret",
        ActionMeta::new()
            .level(Perm::Config)
            .param("name", ParamMeta::of(TypeCode::String).required(true))
            .param("value", ParamMeta::of(TypeCode::Binary).required(true))
            .result(ActionResult::Type(TypeCode::Array)),
    )
    .await?;
    ctx.declare_action(
        &p,
        "delete_secret",
        ActionMeta::new()
            .level(Perm::Config)
            .param("name", ParamMeta::of(TypeCode::String).required(true))
            .result(ActionResult::Type(TypeCode::Array)),
    )
    .await?;
    ctx.declare_action(
        &p,
        "hello",
        ActionMeta::new()
            .param("token", ParamMeta::of(TypeCode::Binary).required(true))
            .result(ActionResult::Type(TypeCode::Map)),
    )
    .await
}

async fn declare_quarantined(
    ctx: &LinkCtx,
    cn: &str,
    e: &crate::registry::QuarantineEntry,
) -> Result<(), LinkError> {
    let p = format!("quarantine/{cn}");
    ctx.declare_node(
        &p,
        NodeMeta::folder()
            .is("wy:quarantine")
            .attr("first_seen", e.first_seen)
            .attr("last_seen", e.last_seen)
            .attr("attempts", e.attempts),
    )
    .await?;
    ctx.declare_action(
        &p,
        "approve",
        ActionMeta::new()
            .param("driver", str_param())
            .param("params", ParamMeta::of(TypeCode::Map))
            .result(ActionResult::Type(TypeCode::Map))
            .level(Perm::Config),
    )
    .await?;
    ctx.declare_action(&p, "reject", ActionMeta::new().level(Perm::Config))
        .await
}

fn arg<'a>(args: &'a Value, name: &str) -> Option<&'a Value> {
    match args {
        Value::Map(m) => m.get(name),
        _ => None,
    }
}

fn arg_str<'a>(args: &'a Value, name: &str) -> Option<&'a str> {
    match arg(args, name) {
        Some(Value::Str(s)) => Some(s),
        _ => None,
    }
}

impl Link for Admin {
    const NAME: &'static str = "admin";
    const VERSION: &'static str = env!("CARGO_PKG_VERSION");
    type Config = AdminStart;

    async fn start(cfg: AdminStart, ctx: LinkCtx) -> wyrm_link_sdk::Result<Self> {
        ctx.declare_node(
            "broker",
            NodeMeta {
                is: Some(Profile::Code(9)),
                ..Default::default()
            }
            .attr("version", env!("CARGO_PKG_VERSION"))
            .attr("site", cfg.ctl.cfg.site.as_str()),
        )
        .await?;
        ctx.declare_node("links", NodeMeta::folder()).await?;
        ctx.declare_action(
            "links",
            "install",
            ActionMeta::new()
                .param("id", str_param().required(true))
                .param("driver", str_param().required(true))
                .param(
                    "mode",
                    str_param().enum_values(["embedded", "process", "external"]),
                )
                .param("params", ParamMeta::of(TypeCode::Map))
                .result(ActionResult::Type(TypeCode::Map))
                .level(Perm::Config),
        )
        .await?;
        let reg = cfg.ctl.registry();
        for def in reg.links.values() {
            declare_link(&ctx, def).await?;
        }
        ctx.declare_node("quarantine", NodeMeta::folder()).await?;
        for (cn, e) in &reg.quarantine {
            declare_quarantined(&ctx, cn, e).await?;
        }
        ctx.declare_node("metrics", NodeMeta::folder()).await?;
        ctx.declare_node("metrics/broker", NodeMeta::folder())
            .await?;
        ctx.declare_node(
            "metrics/broker/acl_denied_total",
            NodeMeta {
                is: Some(Profile::Code(is_code::NODE + 10)),
                ty: Some(TypeCode::Number),
                ..Default::default()
            }
            .cfg("kind", "counter"),
        )
        .await?;
        ctx.declare_node("audit", NodeMeta::number().is("wy:audit"))
            .await?;
        ctx.declare_action(
            "audit",
            "tail",
            ActionMeta::new()
                .param("n", ParamMeta::of(TypeCode::Number))
                .result(ActionResult::Type(TypeCode::Array))
                .level(Perm::Config),
        )
        .await?;
        // `wy/<site>/sys/broker` liveliness: process links re-publish when it returns.
        ctx.set_dynamic("broker", true).await?;
        Ok(Admin {
            ctx,
            ctl: cfg.ctl,
            embedded: cfg.embedded,
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
        let sub = sub_of(who);
        let segs: Vec<&str> = path.split('/').collect();
        let result = match (segs.as_slice(), action) {
            (["links"], "install") => self.install(&args, &sub).await,
            (["links", id], "hello") => self.hello(id, &args).await,
            (["links", id], "start") => self.start_link(id, &sub).await.map(|_| None),
            (["links", id], "stop") => self.stop_link(id, &sub).await.map(|_| None),
            (["links", id], "remove") => self.remove(id, &sub).await.map(|_| None),
            (["links", id], "set_secret") => self.set_secret(id, &args, &sub),
            (["links", id], "delete_secret") => self.delete_secret(id, &args, &sub),
            (["quarantine", cn], "approve") => self.approve(cn, &args, &sub).await,
            (["quarantine", cn], "reject") => self.reject(cn, &sub).await.map(|_| None),
            (["audit"], "tail") => {
                let n = arg(&args, "n").and_then(Value::as_f64).unwrap_or(50.0) as usize;
                Ok(Some(Value::Array(
                    self.ctl
                        .audit_tail(n.min(1000))
                        .into_iter()
                        .map(|r| {
                            let mut m = BTreeMap::new();
                            m.insert("t".into(), Value::UInt(r.t));
                            m.insert("sub".into(), Value::Str(r.sub));
                            m.insert("op".into(), Value::Str(r.op));
                            m.insert("key".into(), Value::Str(r.key));
                            m.insert("status".into(), Value::UInt(r.status.into()));
                            m.insert("detail".into(), Value::Str(r.detail));
                            Value::Map(m)
                        })
                        .collect(),
                )))
            }
            _ => Err(LinkError::not_supported(format!("{path}/~act/{action}"))),
        };
        match result {
            Ok(Some(v)) => out.reply(v).await,
            Ok(None) => Ok(()),
            Err(e) => Err(e),
        }
    }
}

impl Admin {
    async fn install(&self, args: &Value, sub: &str) -> wyrm_link_sdk::Result<Option<Value>> {
        let ctl = &self.ctl;
        let id = arg_str(args, "id").unwrap_or_default().to_owned();
        let driver = arg_str(args, "driver").unwrap_or_default().to_owned();
        let compiled = ctl.host.drivers().contains(&driver.as_str());
        let mode = match arg_str(args, "mode") {
            Some(m) => Mode::parse(m).ok_or_else(|| LinkError::invalid_parameter("mode"))?,
            None if compiled => Mode::Embedded,
            None => Mode::External,
        };
        let params = arg(args, "params")
            .cloned()
            .unwrap_or(Value::Map(Default::default()));
        crate::registry::validate_link_id(&id).map_err(LinkError::invalid_parameter)?;
        // Before any side effect (token, secret purge) on an existing id.
        if ctl.registry().links.contains_key(&id) {
            return Err(LinkError::invalid_parameter(format!("link {id} exists")));
        }
        crate::secrets::lint_params(&params, "params").map_err(LinkError::invalid_parameter)?;
        if mode != Mode::External {
            if !compiled {
                return Err(LinkError::invalid_parameter(format!(
                    "driver {driver} is not compiled in"
                )));
            }
            ctl.host.validate(&driver, &params)?;
        }
        if mode == Mode::Process && ctl.cfg.link_endpoint.is_none() {
            return Err(LinkError::not_supported(
                "process mode needs a tls/ listener",
            ));
        }
        if ctl.cfg.operators.contains(&id) {
            return Err(LinkError::invalid_parameter("id is an operator CN"));
        }
        let (token_hash, token) = ctl.new_token_for(&id, mode)?;
        let def = LinkDef {
            id: id.clone(),
            driver,
            mode,
            params: encode_params(&params)?,
            token_hash,
            rev: 1,
            origin: Origin::Runtime,
            created: now_s(),
        };
        ctl.secrets
            .drop_link(&id)
            .map_err(|e| LinkError::internal(e.to_string()))?;
        ctl.apply(Op::Install(def.clone())).map_err(rejected)?;
        ctl.record(sub, "install", &id, Status::Ok, mode.name());
        declare_link(&self.ctx, &def).await?;
        let mut reply = BTreeMap::new();
        if mode.is_remote() {
            let cert = ctl
                .link_cert(&id)
                .map_err(|e| LinkError::internal(e.to_string()))?;
            if let Some(t) = token {
                // External links: shown once; the files stay on the broker host.
                reply.insert("token".into(), Value::Str(t));
                reply.insert("cert".into(), Value::Str(cert.cert.display().to_string()));
                reply.insert("key".into(), Value::Str(cert.key.display().to_string()));
                reply.insert("ca".into(), Value::Str(ctl.ca_path().display().to_string()));
            }
            ctl.schedule_reload();
        } else {
            start_embedded(ctl, &self.ctx, &self.embedded, &def).await?;
        }
        Ok(Some(Value::Map(reply)))
    }

    async fn hello(&self, id: &str, args: &Value) -> wyrm_link_sdk::Result<Option<Value>> {
        let token = match arg(args, "token") {
            Some(Value::Bytes(b)) => b.as_slice(),
            _ => &[][..],
        };
        let def = self.ctl.registry().links.get(id).cloned();
        let ok = def
            .as_ref()
            .is_some_and(|d| d.mode.is_remote() && secret::verify_token(token, &d.token_hash));
        let Some(def) = def.filter(|_| ok) else {
            self.ctl.record(
                &format!("link:{id}"),
                "hello",
                id,
                Status::PermissionDenied,
                "",
            );
            return Err(LinkError::new(Status::PermissionDenied, ""));
        };
        self.ctl
            .record(&format!("link:{id}"), "hello", id, Status::Ok, "");
        let mut reply = BTreeMap::new();
        reply.insert("params".into(), decode_params(&def.params));
        // Over the link's own mTLS session only (ACL: CN `<id>` alone may
        // query this key); never logged.
        reply.insert(
            "secrets".into(),
            Value::Map(
                self.ctl
                    .secrets
                    .for_link(id)
                    .into_iter()
                    .map(|(k, v)| (k, Value::Bytes(v.to_vec())))
                    .collect(),
            ),
        );
        reply.insert(
            "admin_keys".into(),
            Value::Array(
                self.ctl
                    .link_trust()
                    .iter()
                    .map(|k| Value::Bytes(k.to_bytes().to_vec()))
                    .collect(),
            ),
        );
        Ok(Some(Value::Map(reply)))
    }

    /// Stores one secret; the link sees it on its next start (`hello`).
    /// Replies with the secret names, never the values.
    fn set_secret(
        &self,
        id: &str,
        args: &Value,
        sub: &str,
    ) -> wyrm_link_sdk::Result<Option<Value>> {
        self.def(id)?;
        let name = secret_name(args)?;
        let value = match arg(args, "value") {
            Some(Value::Bytes(b)) => b.clone(),
            Some(Value::Str(s)) => s.as_bytes().to_vec(),
            _ => return Err(LinkError::invalid_parameter("value")),
        };
        self.ctl
            .secrets
            .set(id, name, &value)
            .map_err(|e| LinkError::internal(e.to_string()))?;
        self.ctl.record(sub, "set_secret", id, Status::Ok, name);
        Ok(Some(self.secret_names(id)))
    }

    fn delete_secret(
        &self,
        id: &str,
        args: &Value,
        sub: &str,
    ) -> wyrm_link_sdk::Result<Option<Value>> {
        self.def(id)?;
        let name = secret_name(args)?;
        let had = self
            .ctl
            .secrets
            .remove(id, name)
            .map_err(|e| LinkError::internal(e.to_string()))?;
        if !had {
            return Err(LinkError::not_found(name.to_owned()));
        }
        self.ctl.record(sub, "delete_secret", id, Status::Ok, name);
        Ok(Some(self.secret_names(id)))
    }

    fn secret_names(&self, id: &str) -> Value {
        Value::Array(
            self.ctl
                .secrets
                .names(id)
                .into_iter()
                .map(Value::Str)
                .collect(),
        )
    }

    fn def(&self, id: &str) -> wyrm_link_sdk::Result<LinkDef> {
        self.ctl
            .registry()
            .links
            .get(id)
            .cloned()
            .ok_or_else(|| LinkError::not_found(id.to_owned()))
    }

    async fn start_link(&self, id: &str, sub: &str) -> wyrm_link_sdk::Result<()> {
        let def = self.def(id)?;
        match def.mode {
            Mode::Embedded => start_embedded(&self.ctl, &self.ctx, &self.embedded, &def).await?,
            Mode::Process => {
                let spec = self
                    .ctl
                    .proc_spec(&def)
                    .ok_or_else(|| LinkError::not_supported("no tls listener"))?;
                self.ctl.supervisor.start(spec);
            }
            Mode::External => return Err(LinkError::not_supported("external links run elsewhere")),
        }
        self.ctl.record(sub, "start", id, Status::Ok, "");
        Ok(())
    }

    async fn stop_link(&self, id: &str, sub: &str) -> wyrm_link_sdk::Result<()> {
        let def = self.def(id)?;
        match def.mode {
            Mode::Embedded => {
                let link = self.embedded.lock().await.remove(id);
                if let Some(l) = link {
                    l.stop().await;
                }
            }
            Mode::Process => self.ctl.supervisor.stop(id).await,
            Mode::External => return Err(LinkError::not_supported("external links run elsewhere")),
        }
        self.ctl.record(sub, "stop", id, Status::Ok, "");
        Ok(())
    }

    async fn remove(&self, id: &str, sub: &str) -> wyrm_link_sdk::Result<()> {
        let def = self.def(id)?;
        if def.origin == Origin::Config {
            return Err(LinkError::not_supported(
                "defined in wyrmd.json5; remove it there",
            ));
        }
        if def.mode != Mode::External {
            self.stop_link(id, sub).await?;
        }
        self.ctl
            .secrets
            .drop_link(id)
            .map_err(|e| LinkError::internal(e.to_string()))?;
        self.ctl
            .apply(Op::Remove(id.to_owned()))
            .map_err(rejected)?;
        if let Ok(dir) = self.ctl.link_dir(id) {
            let _ = std::fs::remove_dir_all(dir);
        }
        self.ctx.remove_node(&format!("links/{id}")).await?;
        self.ctl.record(sub, "remove", id, Status::Ok, "");
        if def.mode.is_remote() {
            self.ctl.schedule_reload();
        }
        Ok(())
    }

    async fn approve(
        &self,
        cn: &str,
        args: &Value,
        sub: &str,
    ) -> wyrm_link_sdk::Result<Option<Value>> {
        if !self.ctl.registry().quarantine.contains_key(cn) {
            return Err(LinkError::not_found(cn.to_owned()));
        }
        let driver = arg_str(args, "driver").unwrap_or("unknown").to_owned();
        let params = arg(args, "params")
            .cloned()
            .unwrap_or(Value::Map(Default::default()));
        if self.ctl.registry().links.contains_key(cn) {
            return Err(LinkError::invalid_parameter(format!("link {cn} exists")));
        }
        crate::secrets::lint_params(&params, "params").map_err(LinkError::invalid_parameter)?;
        let (token_hash, token) = self.ctl.new_token_for(cn, Mode::External)?;
        self.ctl
            .apply(Op::Approve(cn.to_owned()))
            .map_err(rejected)?;
        let def = LinkDef {
            id: cn.to_owned(),
            driver,
            mode: Mode::External,
            params: encode_params(&params)?,
            token_hash,
            rev: 1,
            origin: Origin::Runtime,
            created: now_s(),
        };
        self.ctl
            .secrets
            .drop_link(cn)
            .map_err(|e| LinkError::internal(e.to_string()))?;
        self.ctl.apply(Op::Install(def.clone())).map_err(rejected)?;
        self.ctl.record(sub, "approve", cn, Status::Ok, "");
        self.ctx.remove_node(&format!("quarantine/{cn}")).await?;
        declare_link(&self.ctx, &def).await?;
        self.ctl.schedule_reload();
        let mut reply = BTreeMap::new();
        if let Some(t) = token {
            reply.insert("token".into(), Value::Str(t));
        }
        Ok(Some(Value::Map(reply)))
    }

    async fn reject(&self, cn: &str, sub: &str) -> wyrm_link_sdk::Result<()> {
        self.ctl
            .apply(Op::Reject(cn.to_owned()))
            .map_err(rejected)?;
        self.ctl.record(sub, "reject", cn, Status::Ok, "");
        self.ctx.remove_node(&format!("quarantine/{cn}")).await
    }
}

/// `links/<id>/state` from liveliness (`down/<id>`), the supervisor and the
/// embedded table.
async fn watch_states(ctl: Arc<Control>, ctx: LinkCtx, embedded: Running) {
    let down = format!("wy/{}/down/*", ctl.cfg.site);
    let live = match ctx
        .client()
        .liveliness()
        .declare_subscriber(&down)
        .history(true)
        .await
    {
        Ok(s) => s,
        Err(e) => {
            warn!("cannot watch {down}: {e}");
            return;
        }
    };
    let mut connected: HashSet<String> = HashSet::new();
    let mut shown: HashMap<String, usize> = HashMap::new();
    let mut tick = tokio::time::interval(Duration::from_millis(250));
    loop {
        tokio::select! {
            s = live.recv_async() => {
                let Ok(s) = s else { return };
                if let Some(id) = s.key_expr().as_str().rsplit('/').next() {
                    match s.kind() {
                        zenoh::sample::SampleKind::Put => { connected.insert(id.to_owned()); }
                        zenoh::sample::SampleKind::Delete => { connected.remove(id); }
                    }
                }
            }
            _ = tick.tick() => {}
        }
        let running: HashSet<String> = embedded.lock().await.keys().cloned().collect();
        for def in ctl.registry().links.values() {
            let up = connected.contains(&def.id);
            let state = match def.mode {
                Mode::Embedded if up => "connected",
                Mode::Embedded if running.contains(&def.id) => "starting",
                Mode::Embedded => "stopped",
                Mode::External if up => "connected",
                Mode::External => "stopped",
                Mode::Process => match ctl.supervisor.state(&def.id) {
                    None => "installed",
                    Some(ProcState::Running(_)) if up => "connected",
                    Some(ProcState::Running(_) | ProcState::Starting | ProcState::Backoff) => {
                        "starting"
                    }
                    Some(ProcState::Stopping) => "stopping",
                    Some(ProcState::Stopped) => "stopped",
                    Some(ProcState::Failed) => "failed",
                },
            };
            let idx = STATES.iter().position(|s| *s == state).unwrap_or(0);
            if shown.get(&def.id) != Some(&idx) {
                let path = format!("links/{}/state", def.id);
                if ctx
                    .update(&path, Value::UInt(idx as u64), Quality::Good, now_us())
                    .await
                    .is_ok()
                {
                    shown.insert(def.id.clone(), idx);
                }
            }
        }
        if ctx.is_closed() {
            return;
        }
    }
}

/// Sessions whose certificate CN is not a known link or operator.
async fn watch_quarantine(ctl: Arc<Control>, ctx: LinkCtx) {
    let events = match ctx
        .client()
        .info()
        .link_events_listener()
        .history(true)
        .await
    {
        Ok(e) => e,
        Err(e) => {
            warn!("cannot watch link events: {e}");
            return;
        }
    };
    while let Ok(ev) = events.recv_async().await {
        if ev.kind() != zenoh::sample::SampleKind::Put {
            continue;
        }
        let Some(cn) = ev.link().auth_identifier().map(str::to_owned) else {
            continue;
        };
        let reg = ctl.registry();
        let known = reg.links.contains_key(&cn)
            || reg.blocklist.contains(&cn)
            || reg.retired.contains(&cn)
            || ctl.cfg.operators.contains(&cn)
            || cn == "broker";
        if known || crate::registry::validate_link_id(&cn).is_err() {
            continue;
        }
        if ctl
            .apply(Op::Quarantine {
                cn: cn.clone(),
                seen: now_s(),
            })
            .is_err()
        {
            continue;
        }
        ctl.record(
            &format!("cn:{cn}"),
            "quarantine",
            &cn,
            Status::PermissionDenied,
            &ev.link().src().to_string(),
        );
        info!(cn = %cn, "unknown certificate: quarantined");
        if let Some(e) = ctl.registry().quarantine.get(&cn) {
            if let Err(e) = declare_quarantined(&ctx, &cn, e).await {
                debug!("quarantine node: {e}");
            }
        }
    }
}

/// `set`/`invoke` records put by links on `wy/<site>/sys/audit/<link>`; the
/// ACL lets only CN `<link>` write that key, so the origin is the key.
async fn watch_audit(ctl: Arc<Control>, ctx: LinkCtx) {
    let key = format!("wy/{}/sys/audit/*", ctl.cfg.site);
    let Ok(sub) = ctx.client().declare_subscriber(&key).await else {
        return;
    };
    while let Ok(s) = sub.recv_async().await {
        let Some(link) = s.key_expr().as_str().rsplit('/').next().map(str::to_owned) else {
            continue;
        };
        let Ok(Value::Map(m)) = wyrm_core::codec::from_slice::<Value>(&s.payload().to_bytes())
        else {
            continue;
        };
        let text = |k: &str| match m.get(k) {
            Some(Value::Str(v)) => v.clone(),
            _ => String::new(),
        };
        let status = match m.get("status") {
            Some(Value::UInt(u)) => u8::try_from(*u).unwrap_or(u8::MAX),
            _ => u8::MAX,
        };
        let hash = match m.get("args_hash") {
            Some(Value::Bytes(b)) => hex::encode(b),
            _ => String::new(),
        };
        // The link's own clock and `sub` are claims; the admin's clock is the
        // record time, and a key outside the link's subtree is flagged.
        let key = text("key");
        let root = if link == FLOWS_LINK {
            format!("wy/{}/flows", ctl.cfg.site)
        } else {
            format!("wy/{}/down/{link}", ctl.cfg.site)
        };
        let in_subtree = key == root || key.starts_with(&format!("{root}/"));
        let link_t = match m.get("t") {
            Some(Value::UInt(t)) => t.to_string(),
            _ => "-".into(),
        };
        let suppressed = match m.get("suppressed") {
            Some(Value::UInt(n)) => format!(" suppressed:{n}"),
            _ => String::new(),
        };
        let rec = AuditRecord {
            t: now_us(),
            sub: format!("claimed:{}", text("sub")),
            op: text("op"),
            key,
            status,
            detail: format!(
                "link:{link} link_t:{link_t} args_sha256:{hash}{suppressed}{}",
                if in_subtree { "" } else { " key_outside_link" }
            ),
        };
        if let Err(e) = ctl
            .audit
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .apply(rec)
        {
            warn!("audit write failed: {e}");
        }
    }
}

/// Sum of the router's access-control drop counters (open metrics text).
pub fn acl_denied(metrics: &str) -> u64 {
    metrics
        .lines()
        .filter(|l| {
            (l.starts_with("zenoh_rx_network_message_dropped_payload_bytes_count{")
                || l.starts_with("zenoh_tx_network_message_dropped_payload_bytes_count{"))
                && l.contains(r#"reason="access-control""#)
        })
        .filter_map(|l| l.rsplit(' ').next()?.parse::<f64>().ok())
        .sum::<f64>() as u64
}

async fn watch_metrics(ctl: Arc<Control>, ctx: LinkCtx) {
    let session = ctx.client().clone();
    let key = format!("@/{}/router/metrics", session.zid());
    let mut last = 0u64;
    let mut tick = tokio::time::interval(ctl.cfg.metrics_interval);
    loop {
        tick.tick().await;
        if ctx.is_closed() {
            return;
        }
        let Ok(replies) = session.get(&key).timeout(Duration::from_secs(2)).await else {
            continue;
        };
        let Ok(reply) = replies.recv_async().await else {
            continue;
        };
        let Ok(sample) = reply.result() else { continue };
        let raw = sample.payload().to_bytes();
        let mut text = String::new();
        if raw.starts_with(&[0x1f, 0x8b]) {
            use std::io::Read;
            if flate2::read::GzDecoder::new(&raw[..])
                .read_to_string(&mut text)
                .is_err()
            {
                continue;
            }
        } else {
            text = String::from_utf8_lossy(&raw).into_owned();
        }
        let total = acl_denied(&text);
        let _ = ctx
            .update(
                "metrics/broker/acl_denied_total",
                Value::UInt(total),
                Quality::Good,
                now_us(),
            )
            .await;
        if total > last {
            ctl.record(
                "system",
                "acl_denied",
                "router",
                Status::PermissionDenied,
                &format!("+{}", total - last),
            );
            last = total;
        }
    }
}

#[cfg(test)]
mod tests {
    #[test]
    fn acl_metric_sum() {
        let m = r#"# HELP x
zenoh_rx_network_message_dropped_payload_bytes_count{local_id="a",message="put",reason="access-control"} 2
zenoh_rx_network_message_dropped_payload_bytes_count{local_id="a",message="declare",reason="access-control"} 3
zenoh_rx_network_message_dropped_payload_per_transport_bytes_count{reason="access-control"} 5
zenoh_tx_network_message_dropped_payload_bytes_count{reason="congestion"} 9
"#;
        assert_eq!(super::acl_denied(m), 5);
    }
}
