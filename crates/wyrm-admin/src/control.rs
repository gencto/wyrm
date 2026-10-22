//! The admin service.
//!
//! [`Control`] survives broker reloads: registry and audit stores, the CA,
//! the process supervisor. [`Control::attach`] runs, per broker instance, the
//! `wy/<site>/sys/**` responder (an SDK link rooted at `sys`) and three
//! watchers: link states (liveliness + supervisor), quarantine (link events
//! with an unknown certificate CN) and router metrics (`acl_denied_total`,
//! traffic rates as values of `sys`, as on a DSA broker).
//!
//! Zenoh 1.10 cannot reload `access_control` live (ADR 0006), so changes that
//! alter the ACL (install/remove of a process or external link, approve) ask
//! the host to rebuild the router runtime through the reload channel.

use crate::acl;
use crate::audit::{AuditLog, AuditRecord};
use crate::packages;
use crate::registry::{
    LinkDef, Mode, Op, Options, Origin, PackageDef, PackageKind, PeerDef, PeerDir, Registry,
    OPTION_NAMES,
};
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
use wyrm_core::meta::Writable;
use wyrm_core::meta::{
    is_code, ActionResult, ParamMeta, Profile, EDITOR_FILE, EDITOR_PASSWORD, EDITOR_TEXTAREA,
    GROUP_EDIT, GROUP_NEW,
};
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
    /// Keys the admin (the control plane, `sys/**`) trusts besides
    /// `admin_keys`: the user gateway's, whose tokens carry each user's
    /// grants, so only roles with `config` on `wy/<site>/sys/**` pass
    /// (owner decision 2026-10-22, ADR 0009).
    pub control_keys: Vec<VerifyingKey>,
    /// Extra keys trusted by links only, never by the admin itself (the flow
    /// engine signs flow commands with one: a flow may command devices, not
    /// the control plane).
    pub link_keys: Vec<wyrm_link_sdk::LimitedKey>,
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
    /// Resource limits of every process link.
    pub link_limits: wyrm_link_sdk::limits::Limits,
    /// The router config has per-link rules (`upstream_val_hz`): any link
    /// install or removal rebuilds the broker, not only remote ones.
    pub per_link_router_rules: bool,
    /// Directory for the WAL head anchors of the registry and the audit
    /// journal (`state.head`, `audit.head`), on another medium than
    /// `data_dir`: detects records cut from the end of a WAL.
    pub anchor_dir: Option<PathBuf>,
    /// Create the anchors from the current heads (operator step).
    pub anchor_init: bool,
    /// Index of link packages for "Install Link ▸ from Repository" (ADR
    /// 0011), as DSA's `linkRepositoryUrl`.
    pub repository: Option<String>,
}

/// Role grants of the user gateway, shown and edited from `sys` (Get and
/// Update Permissions, as on a DSA broker). `wyrmd` wires the gateway in.
pub trait RoleGrants: Send + Sync {
    /// `(role, key expression, level)`, each role's grants in match order.
    fn grants(&self) -> Vec<(String, String, Perm)>;
    /// Add or change (above `none`) or remove (`none`) one grant of `role`.
    fn set_grant(&self, role: &str, key: &str, level: Perm) -> Result<(), String>;
    /// Remove the grants on exactly one of `keys` that widen their role's
    /// access to `probe`; returns `(role, key, level)` of each.
    fn revoke_widening(
        &self,
        keys: &[String],
        probe: &str,
    ) -> Result<Vec<(String, String, Perm)>, String>;
}

/// Driver name of the AI agent link (ADR 0005): its signing key is a link
/// secret and every other link trusts it, capped at `write`.
pub const AGENT_DRIVER: &str = "agent";

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

/// Read-only text values of `wy/<site>/sys` (as the DSA broker's `sys`):
/// key, display name.
const SYS_INFO: [(&str, &str); 4] = [
    ("version", "WYRM Version"),
    ("zenoh_version", "Zenoh Version"),
    ("start_time", "Start Time"),
    ("distribution", "Distribution"),
];

/// Router counters shown as rates: key, display name, unit, counter.
const SYS_RATES: [(&str, &str, &str, &str); 6] = [
    (
        "messages_in_per_second",
        "Messages In Per Second",
        "msg/s",
        "zenoh_rx_network_message_total",
    ),
    (
        "messages_out_per_second",
        "Messages Out Per Second",
        "msg/s",
        "zenoh_tx_network_message_total",
    ),
    (
        "frames_in_per_second",
        "Frames In Per Second",
        "frame/s",
        "zenoh_rx_transport_message_total",
    ),
    (
        "frames_out_per_second",
        "Frames Out Per Second",
        "frame/s",
        "zenoh_tx_transport_message_total",
    ),
    (
        "data_in_per_second",
        "Data In Per Second",
        "B/s",
        "zenoh_rx_bytes_total",
    ),
    (
        "data_out_per_second",
        "Data Out Per Second",
        "B/s",
        "zenoh_tx_bytes_total",
    ),
];

const RATES_NOTE: &str = "Average over the metrics interval of this router's network \
    sessions (TCP, TLS, QUIC); embedded links talk in-process and are not counted.";

/// Messages the router's access control dropped (`sys/acl_denied`).
const ACL_DENIED: &str = "acl_denied";

/// Linux has the current resident size; elsewhere only the peak is known.
const MEMORY_DISPLAY: &str = if cfg!(target_os = "linux") {
    "Memory"
} else {
    "Peak Memory"
};

/// Broker status values of `sys`, measured every metrics interval: key,
/// display name, unit, description.
const SYS_STATUS: [(&str, &str, &str, &str); 14] = [
    (
        "uptime",
        "Uptime",
        "s",
        "Seconds since the broker process started.",
    ),
    ("links_total", "Links", "", "Installed links."),
    (
        "links_connected",
        "Links Connected",
        "",
        "Links whose liveliness token is present (they serve their tree).",
    ),
    (
        "quarantined",
        "Quarantined",
        "",
        "Unknown certificates waiting in quarantine.",
    ),
    ("packages", "Packages", "", "Installed link packages."),
    (
        "sessions",
        "Open Sessions",
        "",
        "Network sessions of the router: links, peer brokers, the gateway's users go \
         through one in-process session and are not counted.",
    ),
    (
        "upstream_connected",
        "Upstream Connected",
        "",
        "Upstream brokers that are connected.",
    ),
    (
        "downstream_connected",
        "Downstream Connected",
        "",
        "Downstream brokers that are connected.",
    ),
    (
        ACL_DENIED,
        "ACL Denied",
        "",
        "Messages the router's access control dropped since the router started.",
    ),
    (
        "cpu",
        "CPU Usage",
        "%",
        "CPU time of the broker process over the metrics interval; 100 = one core.",
    ),
    (
        "memory",
        MEMORY_DISPLAY,
        "MiB",
        "Resident memory of the broker process (peak on systems without /proc).",
    ),
    (
        "disk_free",
        "Disk Free",
        "MiB",
        "Free space on the file system of data_dir.",
    ),
    (
        "data_size",
        "Data Size",
        "MiB",
        "Size of data_dir, measured every minute.",
    ),
    (
        "audit_records",
        "Audit Records",
        "",
        "Records in the audit journal.",
    ),
];

/// Display name and description of the [`Options`] values.
const OPTION_INFO: [(&str, &str); 2] = [
    (
        "Allow All Links",
        "Install every unknown certificate CN signed by this broker's CA as an \
         external link, without quarantine. The link token stays in the broker's \
         data_dir (links/<id>/token) for the operator to copy to the device.",
    ),
    (
        "Enable Quarantine",
        "Record unknown certificate CNs under quarantine for approval; off: ignore them.",
    ),
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
    /// Broker start (unix seconds), `sys/start_time`; survives reloads.
    started: u64,
    role_grants: Mutex<Option<Arc<dyn RoleGrants>>>,
    /// The repository index: `None` until fetched, then the entries or why
    /// it failed. Fetched in the background on every broker build.
    repo: Mutex<Option<Result<Vec<packages::RepoEntry>, String>>>,
    /// Long admin actions in flight (package installs): a rebuild waits for
    /// them ([`Control::idle`]) instead of stopping them halfway.
    inflight: std::sync::atomic::AtomicUsize,
    /// Set while the broker stops for a rebuild: new long actions answer
    /// `busy` instead of starting on a broker that is going away.
    closing: std::sync::atomic::AtomicBool,
}

/// One long admin action in flight; see [`Control::idle`].
struct Busy<'a>(&'a Control);

impl Drop for Busy<'_> {
    fn drop(&mut self) {
        self.0
            .inflight
            .fetch_sub(1, std::sync::atomic::Ordering::SeqCst);
    }
}

/// `(path, peer site)` reference nodes of one peer link.
type PeerNodes = Vec<(String, String)>;

/// Router-to-router setup from `wyrmd.json5` (iteration 4): peer sites and
/// their CA files. Peers added at runtime live in the registry.
#[derive(Debug, Clone, Default)]
pub struct PeerConfig {
    pub peers: acl::Peers,
    /// CA certificates of downstream sites; trusted only on the QUIC broker
    /// listener.
    pub trusted_cas: Vec<PathBuf>,
    /// `(site, quic endpoint, CA file)` of each upstream site.
    pub upstream: Vec<(String, String, PathBuf)>,
    /// `peers.listen` is set: downstream sites can connect.
    pub listen: bool,
}

/// Largest accepted CA certificate (PEM).
const MAX_CA_PEM: usize = 16 * 1024;

/// `peers` without the sites `config` already names (either direction).
fn unshadowed(config: &acl::Peers, peers: impl Iterator<Item = PeerDef>) -> Vec<PeerDef> {
    let named = |s: &str| {
        config
            .upstream
            .iter()
            .chain(&config.downstream)
            .any(|x| x == s)
    };
    peers.filter(|d| !named(&d.site)).collect()
}

/// One CA certificate in PEM: parsed, with the CA basic constraint.
fn check_ca_pem(pem: &str) -> Result<(), String> {
    if pem.len() > MAX_CA_PEM {
        return Err("CA certificate: larger than 16 KiB".into());
    }
    let (rest, block) = x509_parser::pem::parse_x509_pem(pem.trim().as_bytes())
        .map_err(|e| format!("CA certificate: {e}"))?;
    if block.label != "CERTIFICATE" || !rest.iter().all(u8::is_ascii_whitespace) {
        return Err("CA certificate: expected exactly one PEM CERTIFICATE".into());
    }
    let cert = block
        .parse_x509()
        .map_err(|e| format!("CA certificate: {e}"))?;
    if !cert.is_ca() {
        return Err("not a CA certificate (no CA basic constraint)".into());
    }
    Ok(())
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
        let mut store = Store::<Registry>::open(cfg.data_dir.join("state"), &key)?;
        let mut audit = Store::<AuditLog>::open(cfg.data_dir.join("audit"), &key)?;
        if let Some(dir) = &cfg.anchor_dir {
            if cfg.anchor_init {
                store = store.init_anchor(dir.join("state.head"))?;
                audit = audit.init_anchor(dir.join("audit.head"))?;
            } else {
                store = store.with_anchor(dir.join("state.head"))?;
                audit = audit.with_anchor(dir.join("audit.head"))?;
            }
        }
        if store.state().options.allow_all_links {
            warn!(
                "allow_all_links is on: every certificate this CA signs becomes a link \
                 without approval (sys/allow_all_links)"
            );
        }
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
                started: now_s(),
                role_grants: Mutex::new(None),
                repo: Mutex::new(None),
                inflight: Default::default(),
                closing: Default::default(),
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

    /// The user gateway's roles for `sys` Get/Update Permissions; set before
    /// the broker starts.
    pub fn set_role_grants(&self, r: Arc<dyn RoleGrants>) {
        *self.role_grants.lock().unwrap_or_else(|p| p.into_inner()) = Some(r);
    }

    fn role_grants(&self) -> Option<Arc<dyn RoleGrants>> {
        self.role_grants
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .clone()
    }

    /// The router ACL generated from the current registry and every peer.
    fn acl(&self) -> serde_json::Value {
        acl::access_control_with_peers(
            &self.cfg.site,
            &self.registry(),
            &self.cfg.operators,
            self.cfg.dev,
            &self.peers(),
        )
    }

    /// Broker options (`sys/allow_all_links`, `sys/enable_quarantine`).
    pub fn options(&self) -> Options {
        self.store
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .state()
            .options
            .clone()
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

    /// One record in the admin's audit journal (also for in-process
    /// components such as the user gateway). Never pass secret values.
    pub fn record(&self, sub: &str, op: &str, key: &str, status: Status, detail: &str) {
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

    /// Keys a link verifies `ptok`s with: the admin keys, and capped keys
    /// (`link_keys` plus the signing key of every agent link, at `write`).
    fn link_trust(&self) -> (Vec<VerifyingKey>, Vec<wyrm_link_sdk::LimitedKey>) {
        let mut limited = self.cfg.link_keys.clone();
        limited.extend(self.agent_limited_keys());
        limited.extend(self.requester_limited_keys());
        (self.cfg.admin_keys.clone(), limited)
    }

    /// The requester key of a link with grants, one limited key per grant:
    /// trusted up to that grant's level, under that grant's path.
    fn requester_limited_keys(&self) -> Vec<wyrm_link_sdk::LimitedKey> {
        let reg = self.registry();
        let mut out = Vec::new();
        for d in reg.links.values().filter(|d| !d.grants.is_empty()) {
            let Some(key) = self.requester_key_of(&d.id) else {
                continue;
            };
            for (path, code) in &d.grants {
                let Ok(cap) = Perm::try_from(*code) else {
                    continue;
                };
                out.push(wyrm_link_sdk::LimitedKey {
                    key,
                    cap,
                    scopes: vec![path.replace("{site}", &self.cfg.site)],
                    subject: Some(format!("link:{}", d.id)),
                });
            }
        }
        out
    }

    fn requester_key_of(&self, id: &str) -> Option<VerifyingKey> {
        let secrets = self.secrets.for_link(id);
        let raw = secrets.get(wyrm_link_sdk::REQUESTER_KEY)?;
        let seed: [u8; 32] = raw[..].try_into().ok()?;
        Some(ed25519_dalek::SigningKey::from_bytes(&seed).verifying_key())
    }

    /// A link with grants gets its requester key as a link secret, created
    /// once (it goes away with the link's secrets).
    fn ensure_requester_key(&self, def: &LinkDef) -> Result<(), Error> {
        if def.grants.is_empty()
            || self
                .secrets
                .names(&def.id)
                .iter()
                .any(|n| n == wyrm_link_sdk::REQUESTER_KEY)
        {
            return Ok(());
        }
        let mut seed = zeroize::Zeroizing::new([0u8; 32]);
        getrandom::fill(&mut seed[..]).map_err(|e| format!("no randomness: {e}"))?;
        self.secrets
            .set(&def.id, wyrm_link_sdk::REQUESTER_KEY, &seed[..])?;
        info!(link = %def.id, "requester key created");
        Ok(())
    }

    /// Agent keys at `write`, each only under its link's `allowed_prefixes`.
    fn agent_limited_keys(&self) -> Vec<wyrm_link_sdk::LimitedKey> {
        let reg = self.registry();
        reg.links
            .values()
            .filter(|d| d.driver == AGENT_DRIVER)
            .filter_map(|d| {
                let key = self.agent_key_of(d)?;
                let scopes = match decode_params(&d.params) {
                    Value::Map(m) => match m.get("allowed_prefixes") {
                        Some(Value::Array(a)) => a
                            .iter()
                            .filter_map(|v| match v {
                                Value::Str(s) => Some(s.trim_end_matches('/').to_owned()),
                                _ => None,
                            })
                            .collect(),
                        _ => Vec::new(),
                    },
                    _ => Vec::new(),
                };
                Some(wyrm_link_sdk::LimitedKey {
                    key,
                    cap: Perm::Write,
                    scopes,
                    subject: None,
                })
            })
            .collect()
    }

    /// Name of the secret that holds an agent link's signing key.
    fn agent_key_name(def: &LinkDef) -> String {
        match decode_params(&def.params) {
            Value::Map(m) => match m.get("agent_key_ref") {
                Some(Value::Str(s)) if !s.is_empty() => s.clone(),
                _ => "agent_key".into(),
            },
            _ => "agent_key".into(),
        }
    }

    fn agent_key_of(&self, d: &LinkDef) -> Option<VerifyingKey> {
        let secrets = self.secrets.for_link(&d.id);
        let raw = secrets.get(&Self::agent_key_name(d))?;
        let seed: [u8; 32] = match raw.len() {
            32 => raw[..].try_into().ok()?,
            _ => hex::decode(std::str::from_utf8(raw).ok()?.trim())
                .ok()?
                .try_into()
                .ok()?,
        };
        Some(ed25519_dalek::SigningKey::from_bytes(&seed).verifying_key())
    }

    /// Verifying keys of the agent links (driver `agent`) that have one.
    pub fn agent_keys(&self) -> Vec<VerifyingKey> {
        self.registry()
            .links
            .values()
            .filter(|d| d.driver == AGENT_DRIVER)
            .filter_map(|d| self.agent_key_of(d))
            .collect()
    }

    /// An agent link gets its signing key as a link secret (never in params
    /// or the tree); created once, kept across restarts.
    fn ensure_agent_key(&self, def: &LinkDef) -> Result<bool, Error> {
        if def.driver != AGENT_DRIVER {
            return Ok(false);
        }
        let name = Self::agent_key_name(def);
        if self.secrets.names(&def.id).contains(&name) {
            return Ok(false);
        }
        let mut seed = zeroize::Zeroizing::new([0u8; 32]);
        getrandom::fill(&mut seed[..]).map_err(|e| format!("no randomness: {e}"))?;
        self.secrets.set(&def.id, &name, &seed[..])?;
        info!(link = %def.id, "agent signing key created");
        Ok(true)
    }

    /// The link's store key (32 random bytes, secret `.store_key`): it seals
    /// the framework tree the link keeps in its `data_dir`. Created once; it
    /// goes away with the link's secrets.
    fn ensure_store_key(&self, id: &str) -> Result<(), Error> {
        let name = wyrm_link_sdk::driver::persist::STORE_KEY;
        if self.secrets.names(id).iter().any(|n| n == name) {
            return Ok(());
        }
        let mut key = zeroize::Zeroizing::new([0u8; 32]);
        getrandom::fill(&mut key[..]).map_err(|e| format!("no randomness: {e}"))?;
        self.secrets.set(id, name, &key[..])
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

    /// `data_dir/links/<id>/data`: the link's own private directory (mode
    /// 0700), created on demand and removed with the link. Embedded and
    /// process links get it; external links keep their state themselves.
    fn link_data_dir(&self, id: &str) -> Result<PathBuf, LinkError> {
        let dir = self.link_dir(id)?.join("data");
        let mut b = std::fs::DirBuilder::new();
        b.recursive(true);
        #[cfg(unix)]
        std::os::unix::fs::DirBuilderExt::mode(&mut b, 0o700);
        b.create(&dir)
            .map_err(|e| LinkError::internal(format!("{}: {e}", dir.display())))?;
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            std::fs::set_permissions(&dir, std::fs::Permissions::from_mode(0o700))
                .map_err(|e| LinkError::internal(format!("{}: {e}", dir.display())))?;
        }
        Ok(dir)
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
            if l.driver == AGENT_DRIVER && l.mode == Mode::External {
                return Err(format!("{}: agent links cannot be external", l.id).into());
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
                        display: None,
                        granted: None,
                        log_level: None,
                        grants: Vec::new(),
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

    /// Set peer brokers from `wyrmd.json5` (takes effect on the next broker
    /// build).
    pub fn set_peers(&self, p: PeerConfig) {
        *self.peers.lock().unwrap_or_else(|e| e.into_inner()) = p;
    }

    fn config_peers(&self) -> PeerConfig {
        self.peers.lock().unwrap_or_else(|e| e.into_inner()).clone()
    }

    /// Runtime peers whose site `wyrmd.json5` does not also name: the
    /// config wins, as for links (a site twice would repeat ACL rule ids,
    /// and Zenoh refuses such a config).
    fn runtime_peers(&self) -> Vec<PeerDef> {
        unshadowed(
            &self.config_peers().peers,
            self.registry().peers.into_values(),
        )
    }

    /// Remove runtime peers that `wyrmd.json5` now defines (at start, after
    /// [`Control::set_peers`]). Returns their sites.
    pub fn drop_shadowed_peers(&self) -> Vec<String> {
        let keep: HashSet<String> = self.runtime_peers().into_iter().map(|d| d.site).collect();
        let gone: Vec<String> = self
            .registry()
            .peers
            .into_keys()
            .filter(|s| !keep.contains(s))
            .collect();
        for site in &gone {
            if self.apply(Op::RemovePeer(site.clone())).is_ok() {
                let _ = std::fs::remove_file(self.peer_ca_path(site));
                self.record(
                    "system",
                    "peer_remove",
                    site,
                    Status::Ok,
                    "now in wyrmd.json5",
                );
                warn!(site = %site, "peer {site} is in wyrmd.json5: the runtime entry is removed");
            }
        }
        gone
    }

    /// Every peer site in force: `wyrmd.json5` plus runtime ones (enabled
    /// upstream sites only). The ACL, the peer nodes, the router endpoints
    /// and the link-id checks all use this list.
    pub fn peers(&self) -> acl::Peers {
        let mut p = self.config_peers().peers;
        for d in &self.runtime_peers() {
            match d.dir {
                PeerDir::Upstream if d.enabled => p.upstream.push(d.site.clone()),
                PeerDir::Upstream => {}
                PeerDir::Downstream => p.downstream.push(d.site.clone()),
            }
        }
        p
    }

    /// Where link packages are unpacked (ADR 0011).
    pub fn packages_root(&self) -> PathBuf {
        self.cfg.data_dir.join("packages")
    }

    /// The components of `wasm` packages, `<package>.wasm`, as the `wasm`
    /// driver reads them (ADR 0012).
    pub fn component_store(&self) -> PathBuf {
        self.packages_root().join(".wasm")
    }

    /// Put a `wasm` package's entry into the component store, in one rename.
    fn publish_component(&self, def: &PackageDef) -> Result<(), String> {
        let src = packages::dir(&self.packages_root(), def).join(&def.entry);
        let bytes = std::fs::read(&src).map_err(|e| format!("{}: {e}", src.display()))?;
        let store = self.component_store();
        std::fs::create_dir_all(&store).map_err(|e| e.to_string())?;
        let tmp = store.join(format!(".{}.tmp", def.name));
        std::fs::write(&tmp, bytes).map_err(|e| e.to_string())?;
        std::fs::rename(&tmp, store.join(format!("{}.wasm", def.name))).map_err(|e| e.to_string())
    }

    /// CA file of a runtime peer site (written from the registry).
    fn peer_ca_path(&self, site: &str) -> PathBuf {
        self.cfg
            .data_dir
            .join("pki")
            .join("peers")
            .join(format!("{site}.pem"))
    }

    /// `(quic endpoint, CA file)` of every upstream site to connect to.
    pub fn upstream_endpoints(&self) -> Vec<(String, PathBuf)> {
        let mut out: Vec<(String, PathBuf)> = self
            .config_peers()
            .upstream
            .into_iter()
            .map(|(_, ep, ca)| (ep, ca))
            .collect();
        for d in &self.runtime_peers() {
            if d.dir == PeerDir::Upstream && d.enabled {
                out.push((d.endpoint.clone(), self.peer_ca_path(&d.site)));
            }
        }
        out
    }

    /// The router needs broker certificates for peer links.
    pub fn has_peers(&self) -> bool {
        let p = self.peers();
        !p.upstream.is_empty() || !p.downstream.is_empty()
    }

    pub fn configure_zenoh(&self, c: &mut zenoh::Config, tls: bool) -> Result<(), Error> {
        let mut trusted = self.config_peers().trusted_cas;
        for d in &self.runtime_peers() {
            let path = self.peer_ca_path(&d.site);
            std::fs::create_dir_all(path.parent().unwrap_or(&self.cfg.data_dir))?;
            std::fs::write(&path, &d.ca_pem)?;
            if d.dir == PeerDir::Downstream {
                trusted.push(path);
            }
        }
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
            if trusted.is_empty() {
                // no downstream site left: nothing may stay trusted
                let _ = std::fs::remove_file(self.peer_trust_path());
            } else {
                let mut bundle = String::new();
                for ca in &trusted {
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
        c.insert_json5("access_control", &self.acl().to_string())?;
        Ok(())
    }

    fn proc_spec(&self, def: &LinkDef) -> Option<ProcSpec> {
        let endpoint = self.cfg.link_endpoint.clone()?;
        let dir = self.link_dir(&def.id).ok()?;
        let data = match self.link_data_dir(&def.id) {
            Ok(d) => d,
            Err(e) => {
                warn!(link = %def.id, "data dir: {e}");
                return None;
            }
        };
        let cert = self.link_cert(&def.id).ok()?;
        // A package link runs the package's entry with its args (ADR 0011);
        // a built-in driver runs as `<wyrmd> link <driver>`.
        let (exe, args) = match def.driver.strip_prefix(packages::DRIVER_PREFIX) {
            Some(name) => {
                let p = self.registry().packages.get(name).cloned()?;
                let dir = packages::dir(&self.packages_root(), &p);
                (dir.join(&p.entry), p.args.clone())
            }
            None => (
                self.cfg.link_exe.clone(),
                vec!["link".into(), def.driver.clone()],
            ),
        };
        Some(ProcSpec {
            id: def.id.clone(),
            exe,
            args,
            env: vec![
                ("WYRM_SITE".into(), self.cfg.site.clone()),
                // see wyrm_link_sdk::process::PARENT_PID_ENV
                ("WYRM_PARENT_PID".into(), std::process::id().to_string()),
                ("WYRM_LINK_ID".into(), def.id.clone()),
                ("WYRM_ENDPOINT".into(), endpoint),
                ("WYRM_CA".into(), self.pki.ca_path().display().to_string()),
                ("WYRM_CERT".into(), cert.cert.display().to_string()),
                ("WYRM_KEY".into(), cert.key.display().to_string()),
                (
                    "WYRM_TOKEN_FILE".into(),
                    dir.join("token").display().to_string(),
                ),
                ("WYRM_DATA_DIR".into(), data.display().to_string()),
            ]
            .into_iter()
            .chain(
                def.log_level
                    .as_deref()
                    .map(|l| ("RUST_LOG".to_owned(), crate::logs::env_directive(l))),
            )
            .chain(self.cfg.link_limits.to_env())
            .collect(),
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

    /// Count a long admin action; refused while the broker is closing for
    /// a rebuild (the caller tries again on the new one).
    fn busy(&self) -> Result<Busy<'_>, LinkError> {
        use std::sync::atomic::Ordering::SeqCst;
        // Count first, then look: either `quiesce` sees this action and
        // waits for it, or the action sees the flag and backs off.
        self.inflight.fetch_add(1, SeqCst);
        let b = Busy(self);
        if self.closing.load(SeqCst) {
            return Err(LinkError::new(
                Status::Busy,
                "the broker is restarting; try again",
            ));
        }
        Ok(b)
    }

    /// Before the broker stops for a rebuild: refuse new long actions and
    /// wait (at most `max`) for those in flight, so an install finishes on
    /// the broker that started it.
    pub async fn quiesce(&self, max: Duration) {
        use std::sync::atomic::Ordering::SeqCst;
        self.closing.store(true, SeqCst);
        let until = tokio::time::Instant::now() + max;
        while self.inflight.load(SeqCst) > 0 && tokio::time::Instant::now() < until {
            tokio::time::sleep(Duration::from_millis(100)).await;
        }
    }

    /// The new broker is up: long actions run again.
    pub fn reopen(&self) {
        self.closing
            .store(false, std::sync::atomic::Ordering::SeqCst);
    }

    /// Stop all supervised processes (broker exit).
    pub async fn shutdown(&self) {
        self.supervisor.stop_all().await;
    }

    /// Reference nodes of the peer brokers: one link `down/<d>` per
    /// downstream site, one link `up` with a node per upstream site.
    async fn start_peers(&self, session: &Session) -> Vec<LinkHandle<crate::peers::PeerRefs>> {
        use crate::peers::{PeerRefs, PeerRefsConfig};
        let peers = self.peers();
        let site = &self.cfg.site;
        // (link id, root key, reference nodes)
        let mut plan: Vec<(String, String, PeerNodes)> = peers
            .downstream
            .iter()
            .map(|d| {
                (
                    d.clone(),
                    format!("wy/{site}/down/{d}"),
                    vec![(String::new(), d.clone())],
                )
            })
            .collect();
        if !peers.upstream.is_empty() {
            let nodes = peers
                .upstream
                .iter()
                .map(|u| (u.clone(), u.clone()))
                .collect();
            plan.push(("up".into(), format!("wy/{site}/up"), nodes));
        }
        let mut out = Vec::new();
        for (id, root, nodes) in plan {
            let mut lcfg = LinkConfig::new(site.clone(), id.clone());
            lcfg.root = Some(root.clone());
            lcfg.admin_keys = self.cfg.admin_keys.clone();
            lcfg.audit = false;
            match wyrm_link_sdk::spawn::<PeerRefs>(session.clone(), lcfg, PeerRefsConfig { nodes })
                .await
            {
                Ok(h) => out.push(h),
                Err(e) => warn!(%root, "peer nodes: {e}"),
            }
        }
        out
    }

    /// Run the admin responder, embedded links, process links and watchers
    /// on `session` (an in-process session of the router runtime).
    pub async fn attach(self: &Arc<Self>, session: Session) -> Result<Attached, Error> {
        // Agent keys first: every link started below trusts them.
        for def in self.registry().links.values() {
            if let Err(e) = self.ensure_agent_key(def) {
                warn!(link = %def.id, "agent key: {e}");
            }
            if let Err(e) = self.ensure_store_key(&def.id) {
                warn!(link = %def.id, "store key: {e}");
            }
            if let Err(e) = self.ensure_requester_key(def) {
                warn!(link = %def.id, "requester key: {e}");
            }
        }
        // Saved log levels: the broker's and each embedded link's.
        if let Some(lc) = crate::logs::global() {
            let reg = self.registry();
            if let Some(l) = &reg.log_level {
                if let Err(e) = lc.set_level(l) {
                    warn!("log level {l}: {e}");
                }
            }
            for def in reg.links.values().filter(|d| d.mode == Mode::Embedded) {
                if let Err(e) = lc.set_link_level(&def.id, def.log_level.as_deref()) {
                    warn!(link = %def.id, "log level: {e}");
                }
            }
        }
        let embedded: Running = Arc::new(AsyncMutex::new(HashMap::new()));
        let mut lcfg = LinkConfig::new(self.cfg.site.clone(), "admin");
        lcfg.root = Some(format!("wy/{}/sys", self.cfg.site));
        lcfg.admin_keys = self.cfg.admin_keys.clone();
        lcfg.admin_keys
            .extend(self.cfg.control_keys.iter().copied());
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
                    None => {
                        warn!(link = %def.id, "process mode unavailable (no tls listener or link files)")
                    }
                },
                Mode::External => {}
            }
        }
        let tasks = vec![
            tokio::spawn(watch_states(self.clone(), ctx.clone(), embedded.clone())),
            tokio::spawn(watch_quarantine(self.clone(), ctx.clone())),
            tokio::spawn(watch_metrics(self.clone(), ctx.clone())),
            tokio::spawn(watch_audit(self.clone(), ctx.clone())),
            tokio::spawn(serve_profiles(self.clone(), session.clone())),
            tokio::spawn(load_repository(self.clone(), ctx.clone())),
        ];
        info!(site = %self.cfg.site, "admin attached");
        let peers = self.start_peers(&session).await;
        Ok(Attached {
            admin: Some(admin),
            peers,
            embedded,
            tasks,
        })
    }
}

type Running = Arc<AsyncMutex<HashMap<String, Box<dyn RunningLink>>>>;

/// Admin state bound to one broker instance.
pub struct Attached {
    admin: Option<LinkHandle<Admin>>,
    /// `down/<d>` and `up` reference nodes of peer brokers.
    peers: Vec<LinkHandle<crate::peers::PeerRefs>>,
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
        for p in self.peers.drain(..) {
            p.stop().await;
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
    let (admin_keys, limited_keys) = ctl.link_trust();
    lcfg.admin_keys = admin_keys;
    lcfg.limited_keys = limited_keys;
    lcfg.secrets = ctl.link_secrets(&def.id);
    lcfg.data_dir = Some(ctl.link_data_dir(&def.id)?);
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
    /// `wy/<site>/sys/broker` liveliness, undeclared when the admin stops.
    _broker: zenoh::liveliness::LivelinessToken,
}

fn str_param() -> ParamMeta {
    ParamMeta::of(TypeCode::String)
}

fn link_node(def: &LinkDef) -> NodeMeta {
    let mut node = match &def.display {
        Some(d) => NodeMeta::folder().display(d.as_str()),
        None => NodeMeta::folder(),
    };
    if let Some(role) = &def.granted {
        node = node.attr("group", role.as_str());
    }
    node.is("wy:link-def")
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
    // Names for people and menu groups (spec 02 0.1.6).
    for (a, d, g) in [
        ("start", "Start", None),
        ("stop", "Stop", None),
        ("remove", "Remove", Some(GROUP_EDIT)),
    ] {
        let mut m = ActionMeta::new().level(Perm::Config).display(d);
        m.group = g.map(str::to_owned);
        ctx.declare_action(&p, a, m).await?;
    }
    ctx.declare_action(
        &p,
        "update",
        ActionMeta::new()
            .level(Perm::Config)
            .display("Update Params")
            .group(GROUP_EDIT)
            .param("params", ParamMeta::of(TypeCode::Map).required(true))
            .result(ActionResult::Type(TypeCode::Number)),
    )
    .await?;
    ctx.declare_action(
        &p,
        "history",
        ActionMeta::new()
            // params are control-plane config: same level as update/rollback
            .level(Perm::Config)
            .display("History")
            .result(ActionResult::Type(TypeCode::Array)),
    )
    .await?;
    ctx.declare_action(
        &p,
        "rollback",
        ActionMeta::new()
            .level(Perm::Config)
            .display("Rollback")
            .group(GROUP_EDIT)
            .param(
                "rev",
                ParamMeta::of(TypeCode::Number)
                    .required(true)
                    .display("Revision"),
            )
            .result(ActionResult::Type(TypeCode::Number)),
    )
    .await?;
    ctx.declare_action(
        &p,
        "set_secret",
        ActionMeta::new()
            .level(Perm::Config)
            .display("Set Secret")
            .group("secrets")
            .param(
                "name",
                ParamMeta::of(TypeCode::String)
                    .required(true)
                    .display("Name"),
            )
            .param(
                "value",
                ParamMeta::of(TypeCode::Binary)
                    .required(true)
                    .display("Value")
                    .editor(EDITOR_PASSWORD),
            )
            .result(ActionResult::Type(TypeCode::Array)),
    )
    .await?;
    ctx.declare_action(
        &p,
        "delete_secret",
        ActionMeta::new()
            .level(Perm::Config)
            .display("Delete Secret")
            .group("secrets")
            .param(
                "name",
                ParamMeta::of(TypeCode::String)
                    .required(true)
                    .display("Name"),
            )
            .result(ActionResult::Type(TypeCode::Array)),
    )
    .await?;
    ctx.declare_action(
        &p,
        "hello",
        // Link handshake (an open action, see `open_actions`): level none
        // marks it as not for people, and UIs hide it.
        ActionMeta::new()
            .level(Perm::None)
            .param("token", ParamMeta::of(TypeCode::Binary).required(true))
            .result(ActionResult::Type(TypeCode::Map)),
    )
    .await?;
    ctx.declare_action(
        &p,
        "grant",
        ActionMeta::new()
            .display("Grant Access")
            .group("access")
            .param(
                "path",
                str_param()
                    .required(true)
                    .display("Path")
                    .placeholder("wy/{site}/down/<link>")
                    .description("A node of another link (its subtree), or wy/{site}/flows"),
            )
            .param(
                "level",
                str_param()
                    .required(true)
                    .enum_values(["none", "list", "read", "write"])
                    .display("Level")
                    .description("none removes the grant"),
            )
            .level(Perm::Config),
    )
    .await?;
    // External links log on their own host.
    if def.mode == Mode::External {
        return Ok(());
    }
    let level = format!("{p}/log_level");
    ctx.declare_node(
        &level,
        NodeMeta::leaf(TypeCode::Enum)
            .enum_values(link_levels())
            .writable(Writable::Config)
            .display("Log Level")
            .attr(
                "description",
                if def.mode == Mode::Process {
                    "RUST_LOG of the link process; a change restarts it."
                } else {
                    "Level of this link's lines in the broker log."
                },
            ),
    )
    .await?;
    let idx = def
        .log_level
        .as_deref()
        .and_then(|l| crate::logs::LEVELS.iter().position(|x| *x == l))
        .map_or(0, |i| i + 1);
    ctx.update(&level, Value::UInt(idx as u64), Quality::Good, now_us())
        .await?;
    ctx.declare_action(&p, "get_log", log_action(false)).await
}

/// `default` and the level names: a link's `log_level` choices.
fn link_levels() -> Vec<String> {
    std::iter::once("default")
        .chain(crate::logs::LEVELS)
        .map(str::to_owned)
        .collect()
}

/// `get_log {lines, level, filter[, link]}` → a table of log lines.
fn log_action(broker: bool) -> ActionMeta {
    let mut a = ActionMeta::new()
        .display("Get Log")
        .param(
            "lines",
            ParamMeta::of(TypeCode::Number)
                .display("Lines")
                .placeholder("200 (at most 2000)"),
        )
        .param(
            "level",
            str_param()
                .enum_values(crate::logs::LEVELS.iter().rev().map(|l| l.to_string()))
                .display("Level")
                .description("This level and more severe"),
        )
        .param(
            "filter",
            str_param()
                .display("Filter")
                .placeholder("text in the target or message"),
        );
    if broker {
        a = a.param(
            "link",
            str_param()
                .display("Link")
                .placeholder("lines of one embedded link"),
        );
    }
    a.result(ActionResult::Type(TypeCode::Array))
        .level(Perm::Config)
}

/// Log lines as table rows.
fn log_rows(lines: Vec<crate::logs::LogLine>) -> Value {
    Value::Array(
        lines
            .into_iter()
            .map(|l| {
                let mut m = BTreeMap::new();
                m.insert("time".to_owned(), Value::Str(iso_utc_ms(l.t)));
                m.insert(
                    "level".to_owned(),
                    Value::from(crate::logs::level_name(l.level)),
                );
                m.insert("target".to_owned(), Value::Str(l.target));
                if let Some(id) = l.link {
                    m.insert("link".to_owned(), Value::Str(id));
                }
                m.insert("message".to_owned(), Value::Str(l.message));
                Value::Map(m)
            })
            .collect(),
    )
}

/// `(lines, min level, filter)` of a `get_log` call.
fn log_args(args: &Value) -> Result<(usize, tracing::Level, String), LinkError> {
    let n = arg(args, "lines")
        .and_then(Value::as_f64)
        .unwrap_or(200.0)
        .clamp(1.0, 2000.0) as usize;
    let level = match arg_str(args, "level").filter(|l| !l.is_empty()) {
        Some(l) => crate::logs::parse_level(l)
            .ok_or_else(|| LinkError::invalid_parameter(format!("level: {l}?")))?,
        None => tracing::Level::TRACE,
    };
    let filter = arg_str(args, "filter").unwrap_or_default().to_owned();
    Ok((n, level, filter))
}

/// "No role" in the Authorize `group` list (not a valid role name).
const NO_ROLE: &str = "-";

/// Role names of the user gateway, for the Authorize `group` list.
fn role_names(ctl: &Control) -> Vec<String> {
    let mut roles: Vec<String> = ctl
        .role_grants()
        .map(|r| r.grants().into_iter().map(|(role, ..)| role).collect())
        .unwrap_or_default();
    roles.dedup();
    roles
}

/// DSA Authorize: `dsid` (folder action only), `group` (a gateway role that
/// gets `write` on the link), `name` (display name), driver and params.
fn authorize_meta(dsid: Option<ParamMeta>, roles: &[String]) -> ActionMeta {
    let mut a = ActionMeta::new().display("Authorize");
    if let Some(p) = dsid {
        a = a.param("dsid", p);
    }
    let group = if roles.is_empty() {
        str_param().display("Group").placeholder("no user gateway")
    } else {
        str_param()
            .enum_values(std::iter::once(NO_ROLE.to_owned()).chain(roles.iter().cloned()))
            .display("Group")
            .description("Gateway role that gets write on the new link")
    };
    a.param("group", group)
        .param(
            "name",
            str_param().display("Name").placeholder("display name"),
        )
        .param("driver", str_param().display("Driver"))
        .param("params", ParamMeta::of(TypeCode::Map).display("Params"))
        .result(ActionResult::Type(TypeCode::Map))
        .level(Perm::Config)
}

/// `quarantine/~act/authorize` and `deauthorize` (DSA): their CN, link and
/// role lists are enums, so they are declared again after each change
/// (with each quarantined node's own Authorize).
async fn refresh_quarantine(ctx: &LinkCtx, ctl: &Control) -> Result<(), LinkError> {
    let reg = ctl.registry();
    let roles = role_names(ctl);
    let pick = |vals: Vec<String>, display: &str, none: &str| {
        let p = str_param().required(true).display(display);
        if vals.is_empty() {
            p.placeholder(none)
        } else {
            p.enum_values(vals)
        }
    };
    let cns: Vec<String> = reg.quarantine.keys().cloned().collect();
    ctx.declare_action(
        "quarantine",
        "authorize",
        authorize_meta(Some(pick(cns, "DsId", "nothing in quarantine")), &roles),
    )
    .await?;
    let links: Vec<String> = reg
        .links
        .values()
        .filter(|d| d.mode == Mode::External && d.origin == Origin::Runtime)
        .map(|d| d.id.clone())
        .collect();
    ctx.declare_action(
        "quarantine",
        "deauthorize",
        ActionMeta::new()
            .display("Deauthorize")
            .param("link", pick(links, "Link", "no external links"))
            .level(Perm::Config),
    )
    .await?;
    for (cn, e) in &reg.quarantine {
        declare_quarantined(ctx, cn, e, &roles).await?;
    }
    Ok(())
}

async fn declare_quarantined(
    ctx: &LinkCtx,
    cn: &str,
    e: &crate::registry::QuarantineEntry,
    roles: &[String],
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
    ctx.declare_action(&p, "approve", authorize_meta(None, roles))
        .await?;
    ctx.declare_action(
        &p,
        "reject",
        ActionMeta::new().level(Perm::Config).display("Reject"),
    )
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

/// The DSA-style values of `sys`: broker info, traffic rates, options.
async fn declare_sys_values(ctx: &LinkCtx, ctl: &Control) -> wyrm_link_sdk::Result<()> {
    let info = [
        env!("CARGO_PKG_VERSION").to_owned(),
        zenoh::GIT_VERSION.to_owned(),
        iso_utc(ctl.started),
        format!("rust ({})", if ctl.cfg.dev { "dev" } else { "prod" }),
    ];
    for ((key, display), v) in SYS_INFO.iter().zip(info) {
        ctx.declare_node(key, NodeMeta::leaf(TypeCode::String).display(*display))
            .await?;
        ctx.update(key, Value::Str(v), Quality::Good, now_us())
            .await?;
    }
    for (key, display, unit, about) in SYS_STATUS {
        let mut m = NodeMeta::number()
            .display(display)
            .attr("description", about);
        if !unit.is_empty() {
            m = m.unit(unit);
        }
        ctx.declare_node(key, m).await?;
    }
    for (key, display, unit, _) in SYS_RATES {
        ctx.declare_node(
            key,
            NodeMeta::number()
                .display(display)
                .unit(unit)
                .attr("description", RATES_NOTE),
        )
        .await?;
    }
    if let Some(lc) = crate::logs::global() {
        ctx.declare_node(
            "log_level",
            NodeMeta::leaf(TypeCode::Enum)
                .enum_values(crate::logs::LEVELS)
                .writable(Writable::Config)
                .display("Log Level")
                .attr(
                    "description",
                    "Level of the broker log (zenoh stays at warn below trace); replaces RUST_LOG.",
                ),
        )
        .await?;
        let idx = crate::logs::LEVELS
            .iter()
            .position(|l| *l == lc.level())
            .unwrap_or(2);
        ctx.update(
            "log_level",
            Value::UInt(idx as u64),
            Quality::Good,
            now_us(),
        )
        .await?;
        ctx.declare_action("", "get_log", log_action(true)).await?;
    }
    let opts = ctl.options();
    for (name, (display, about)) in OPTION_NAMES.iter().zip(OPTION_INFO) {
        ctx.declare_node(
            name,
            NodeMeta::leaf(TypeCode::Bool)
                .display(display)
                .writable(Writable::Config)
                .attr("description", about),
        )
        .await?;
        let on = opts.get(name).unwrap_or_default();
        ctx.update(name, Value::Bool(on), Quality::Good, now_us())
            .await?;
    }
    Ok(())
}

/// The DSA-style actions of `sys`: Clear Conns, Get/Update Permissions.
async fn declare_sys_actions(ctx: &LinkCtx, ctl: &Control) -> wyrm_link_sdk::Result<()> {
    ctx.declare_action(
        "",
        "clear_conns",
        ActionMeta::new().display("Clear Conns").level(Perm::Config),
    )
    .await?;
    ctx.declare_action(
        "",
        "get_permissions",
        ActionMeta::new()
            .display("Get Permissions")
            .result(ActionResult::Type(TypeCode::Array))
            .level(Perm::Config),
    )
    .await?;
    if ctl.role_grants().is_some() {
        ctx.declare_action(
            "",
            "update_permissions",
            ActionMeta::new()
                .display("Update Permissions")
                .param("role", str_param().required(true).display("Role"))
                .param(
                    "path",
                    str_param()
                        .required(true)
                        .display("Path")
                        .placeholder("wy/{site}/down/**"),
                )
                .param(
                    "level",
                    str_param()
                        .required(true)
                        .enum_values(Perm::ALL.iter().map(|p| p.name()))
                        .display("Level"),
                )
                .level(Perm::Config),
        )
        .await?;
    }
    Ok(())
}

fn site_param() -> ParamMeta {
    str_param()
        .required(true)
        .display("Name")
        .description("Site name of that broker")
}

fn ca_param() -> ParamMeta {
    str_param()
        .required(true)
        .display("CA Certificate")
        .editor(EDITOR_TEXTAREA)
        .description("PEM of that site's CA (its data_dir/pki/ca.pem)")
}

/// `sys/upstream` and `sys/downstream`: peer brokers, as DSA's
/// `/sys/upstream`. Peers from `wyrmd.json5` are shown read-only.
async fn declare_peers(ctx: &LinkCtx, ctl: &Control) -> wyrm_link_sdk::Result<()> {
    ctx.declare_node("upstream", NodeMeta::folder()).await?;
    ctx.declare_action(
        "upstream",
        "add",
        ActionMeta::new()
            .display("Add Upstream Connection")
            .group(GROUP_NEW)
            .param("name", site_param())
            .param(
                "url",
                str_param()
                    .required(true)
                    .display("Url")
                    .placeholder("quic/central.example:7448"),
            )
            .param("ca", ca_param())
            .param("enabled", ParamMeta::of(TypeCode::Bool).display("Enabled"))
            .level(Perm::Config),
    )
    .await?;
    let cfg = ctl.config_peers();
    // Downstream brokers can connect only through `peers.listen`.
    if !cfg.listen {
        for (site, ep, _) in &cfg.upstream {
            declare_upstream(ctx, site, ep, true, false).await?;
        }
        for d in &ctl.runtime_peers() {
            if d.dir == PeerDir::Upstream {
                declare_upstream(ctx, &d.site, &d.endpoint, d.enabled, true).await?;
            }
        }
        return Ok(());
    }
    ctx.declare_node("downstream", NodeMeta::folder()).await?;
    ctx.declare_action(
        "downstream",
        "add",
        ActionMeta::new()
            .display("Add Downstream Broker")
            .group(GROUP_NEW)
            .param("name", site_param())
            .param("ca", ca_param())
            .level(Perm::Config),
    )
    .await?;
    for (site, ep, _) in &cfg.upstream {
        declare_upstream(ctx, site, ep, true, false).await?;
    }
    for site in &cfg.peers.downstream {
        declare_downstream(ctx, site, false).await?;
    }
    for d in &ctl.runtime_peers() {
        match d.dir {
            PeerDir::Upstream => {
                declare_upstream(ctx, &d.site, &d.endpoint, d.enabled, true).await?
            }
            PeerDir::Downstream => declare_downstream(ctx, &d.site, true).await?,
        }
    }
    Ok(())
}

fn origin(runtime: bool) -> &'static str {
    if runtime {
        "runtime"
    } else {
        "config"
    }
}

/// `upstream/<site>`: `url`, `enabled` (writable when added at runtime),
/// `remove`.
async fn declare_upstream(
    ctx: &LinkCtx,
    site: &str,
    endpoint: &str,
    enabled: bool,
    runtime: bool,
) -> wyrm_link_sdk::Result<()> {
    let p = format!("upstream/{site}");
    ctx.declare_node(&p, NodeMeta::folder().attr("origin", origin(runtime)))
        .await?;
    let url = format!("{p}/url");
    ctx.declare_node(&url, NodeMeta::leaf(TypeCode::String).display("Url"))
        .await?;
    ctx.update(
        &url,
        Value::Str(endpoint.to_owned()),
        Quality::Good,
        now_us(),
    )
    .await?;
    let mut on = NodeMeta::leaf(TypeCode::Bool).display("Enabled");
    if runtime {
        on = on.writable(Writable::Config);
    }
    let en = format!("{p}/enabled");
    ctx.declare_node(&en, on).await?;
    ctx.update(&en, Value::Bool(enabled), Quality::Good, now_us())
        .await?;
    if runtime {
        declare_peer_remove(ctx, &p).await?;
    }
    Ok(())
}

async fn declare_downstream(ctx: &LinkCtx, site: &str, runtime: bool) -> wyrm_link_sdk::Result<()> {
    let p = format!("downstream/{site}");
    ctx.declare_node(&p, NodeMeta::folder().attr("origin", origin(runtime)))
        .await?;
    if runtime {
        declare_peer_remove(ctx, &p).await?;
    }
    Ok(())
}

async fn declare_peer_remove(ctx: &LinkCtx, path: &str) -> wyrm_link_sdk::Result<()> {
    ctx.declare_action(
        path,
        "remove",
        ActionMeta::new()
            .display("Remove")
            .group(GROUP_EDIT)
            .level(Perm::Config),
    )
    .await
}

/// Rows of the generated router ACL: one per (subject, rule).
fn acl_rows(acl: &serde_json::Value) -> Vec<Value> {
    let strs = |v: &serde_json::Value| -> Vec<String> {
        v.as_array()
            .into_iter()
            .flatten()
            .filter_map(|x| x.as_str().map(str::to_owned))
            .collect()
    };
    let rules: HashMap<String, &serde_json::Value> = acl["rules"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|r| Some((r["id"].as_str()?.to_owned(), r)))
        .collect();
    let mut rows = Vec::new();
    for policy in acl["policies"].as_array().into_iter().flatten() {
        for subject in strs(&policy["subjects"]) {
            for id in strs(&policy["rules"]) {
                let Some(rule) = rules.get(&id) else { continue };
                rows.push(perm_row(
                    "acl",
                    &subject,
                    &strs(&rule["key_exprs"]).join(" "),
                    &format!(
                        "{} ({})",
                        strs(&rule["messages"]).join(", "),
                        strs(&rule["flows"]).join("/")
                    ),
                ));
            }
        }
    }
    rows
}

fn perm_row(source: &str, subject: &str, path: &str, level: &str) -> Value {
    Value::Map(BTreeMap::from([
        ("source".to_owned(), Value::Str(source.to_owned())),
        ("subject".to_owned(), Value::Str(subject.to_owned())),
        ("path".to_owned(), Value::Str(path.to_owned())),
        ("level".to_owned(), Value::Str(level.to_owned())),
    ]))
}

/// Menu of the link install actions (DSA "Install Link ▸").
const INSTALL_GROUP: &str = "Install Link";

/// Fetch, unpack and start of a package can take a while.
const INSTALL_TIMEOUT_MS: u32 = 120_000;

/// Download of a package (Url, Repository).
const FETCH_TIMEOUT: Duration = Duration::from_secs(90);

/// An "Install Link ▸" action: config level, `{success, message}`, time
/// for a fetch and unpack.
fn install_meta(display: &str) -> ActionMeta {
    ActionMeta::new()
        .display(display)
        .group(INSTALL_GROUP)
        .result(ActionResult::Type(TypeCode::Map))
        .timeout_ms(INSTALL_TIMEOUT_MS)
        .level(Perm::Config)
}

/// "from Repository" (always in the menu, as in DSA): `package` lists the
/// index once it is fetched; until then, when it failed, or without
/// `packages.repository`, the field says why.
async fn declare_repo_action(ctx: &LinkCtx, ctl: &Control) -> wyrm_link_sdk::Result<()> {
    let state = ctl.repo.lock().unwrap_or_else(|p| p.into_inner()).clone();
    let package = match state {
        _ if ctl.cfg.repository.is_none() => str_param()
            .required(true)
            .display("Package")
            .placeholder("set packages.repository in wyrmd.json5"),
        Some(Ok(list)) if !list.is_empty() => str_param()
            .required(true)
            .display("Package")
            .enum_values(list.iter().map(|e| e.name.clone())),
        Some(Ok(_)) => str_param()
            .required(true)
            .display("Package")
            .placeholder("the repository is empty"),
        Some(Err(e)) => str_param()
            .required(true)
            .display("Package")
            .placeholder(format!("repository unreachable: {e}")),
        None => str_param()
            .required(true)
            .display("Package")
            .placeholder("loading the repository index"),
    };
    ctx.declare_action(
        "links",
        "install_repo",
        install_meta("from Repository")
            .param("name", link_name_param())
            .param("package", package),
    )
    .await
}

/// Fetch the repository index in the background, never on the start path;
/// then list its packages in "from Repository".
async fn load_repository(ctl: Arc<Control>, ctx: LinkCtx) {
    let Some(url) = ctl.cfg.repository.clone() else {
        return;
    };
    let r = crate::fetch::get(&url, packages::MAX_INDEX, Duration::from_secs(15))
        .await
        .and_then(|b| packages::parse_index(&b));
    if let Err(e) = &r {
        warn!(%url, "repository index: {e}");
    }
    *ctl.repo.lock().unwrap_or_else(|p| p.into_inner()) = Some(r);
    if let Err(e) = declare_repo_action(&ctx, &ctl).await {
        debug!("install_repo: {e}");
    }
}

fn link_name_param() -> ParamMeta {
    str_param()
        .required(true)
        .display("Name")
        .description("Id of the new link")
}

/// DSA-style install result: two output rows.
fn outcome(r: Result<String, String>) -> Value {
    let (ok, message) = match r {
        Ok(m) => (true, m),
        Err(m) => (false, m),
    };
    Value::Map(BTreeMap::from([
        ("success".to_owned(), Value::Bool(ok)),
        ("message".to_owned(), Value::Str(message)),
    ]))
}

/// `packages/<name>`: version, kind, source, SHA-256; `remove`.
async fn declare_package(ctx: &LinkCtx, p: &PackageDef) -> wyrm_link_sdk::Result<()> {
    let path = format!("packages/{}", p.name);
    let mut node = NodeMeta::folder()
        .is("wy:package")
        .attr("version", p.version.as_str())
        .attr("kind", p.kind.name())
        .attr("source", p.source.as_str())
        .attr("sha256", p.sha256.as_str())
        .attr("installed", p.installed);
    if !p.description.is_empty() {
        node = node.attr("description", p.description.as_str());
    }
    ctx.declare_node(&path, node).await?;
    ctx.declare_action(
        &path,
        "remove",
        ActionMeta::new()
            .display("Remove")
            .group(GROUP_EDIT)
            .level(Perm::Config),
    )
    .await
}

/// Unix milliseconds as ISO 8601 UTC with milliseconds.
fn iso_utc_ms(ms: u64) -> String {
    let s = iso_utc(ms / 1000);
    format!("{}.{:03}Z", s.trim_end_matches('Z'), ms % 1000)
}

/// `secs` since the epoch as ISO 8601 UTC (`2026-10-22T03:43:00Z`).
fn iso_utc(secs: u64) -> String {
    let (y, m, d) = secret::civil_from_days((secs / 86_400) as i64);
    let t = secs % 86_400;
    format!(
        "{y:04}-{m:02}-{d:02}T{:02}:{:02}:{:02}Z",
        t / 3600,
        t % 3600 / 60,
        t % 60
    )
}

impl Link for Admin {
    const NAME: &'static str = "admin";
    const VERSION: &'static str = env!("CARGO_PKG_VERSION");
    type Config = AdminStart;

    async fn start(cfg: AdminStart, ctx: LinkCtx) -> wyrm_link_sdk::Result<Self> {
        // `sys` itself describes the broker (spec README rule 4: `proto`).
        ctx.declare_node(
            "",
            NodeMeta {
                is: Some(Profile::Code(is_code::LINK)),
                ..Default::default()
            }
            .attr("driver", "admin")
            .attr("version", env!("CARGO_PKG_VERSION"))
            .attr("site", cfg.ctl.cfg.site.as_str())
            .attr("proto", u64::from(wyrm_core::PROTO_VERSION)),
        )
        .await?;
        declare_sys_values(&ctx, &cfg.ctl).await?;
        declare_sys_actions(&ctx, &cfg.ctl).await?;
        declare_peers(&ctx, &cfg.ctl).await?;
        ctx.declare_node("links", NodeMeta::folder()).await?;
        ctx.declare_action(
            "links",
            "install",
            ActionMeta::new()
                .display("from Driver")
                .group(INSTALL_GROUP)
                .param("id", str_param().required(true).display("Link ID"))
                .param("driver", str_param().required(true).display("Driver"))
                .param(
                    "mode",
                    str_param()
                        .enum_values(["embedded", "process", "external"])
                        .display("Mode"),
                )
                .param("params", ParamMeta::of(TypeCode::Map).display("Params"))
                .result(ActionResult::Type(TypeCode::Map))
                .level(Perm::Config),
        )
        .await?;
        ctx.declare_action(
            "links",
            "install_zip",
            ActionMeta::new()
                .display("from Zip")
                .group(INSTALL_GROUP)
                .param("name", link_name_param())
                .param(
                    "zip",
                    ParamMeta::of(TypeCode::Binary)
                        .required(true)
                        .display("Zip")
                        .editor(EDITOR_FILE)
                        .description("Link package: a zip with wyrm-link.json"),
                )
                .result(ActionResult::Type(TypeCode::Map))
                .timeout_ms(INSTALL_TIMEOUT_MS)
                .level(Perm::Config),
        )
        .await?;
        ctx.declare_action(
            "links",
            "install_url",
            install_meta("from Url")
                .param("name", link_name_param())
                .param(
                    "url",
                    str_param()
                        .required(true)
                        .display("Url")
                        .placeholder("https://example.com/link.zip"),
                ),
        )
        .await?;
        ctx.declare_action(
            "links",
            "install_git",
            install_meta("from Git")
                .param("name", link_name_param())
                .param(
                    "url",
                    str_param()
                        .required(true)
                        .display("Url")
                        .placeholder("https://git.example.com/link.git"),
                )
                .param(
                    "ref",
                    str_param().display("Ref").placeholder("branch or tag"),
                ),
        )
        .await?;
        ctx.declare_action(
            "links",
            "install_wasm",
            install_meta("from WASM")
                .param("name", link_name_param())
                .param(
                    "wasm",
                    ParamMeta::of(TypeCode::Binary)
                        .required(true)
                        .display("Component")
                        .editor(EDITOR_FILE)
                        .description("A wyrm:link/driver component (.wasm)"),
                ),
        )
        .await?;
        declare_repo_action(&ctx, &cfg.ctl).await?;
        let reg = cfg.ctl.registry();
        for def in reg.links.values() {
            declare_link(&ctx, def).await?;
        }
        ctx.declare_node("packages", NodeMeta::folder()).await?;
        for p in reg.packages.values() {
            declare_package(&ctx, p).await?;
        }
        ctx.declare_node("profiles", NodeMeta::folder()).await?;
        ctx.declare_action(
            "profiles",
            "put",
            ActionMeta::new()
                .display("Put Profile")
                .group(GROUP_NEW)
                .param("name", str_param().required(true).display("Name"))
                .param(
                    "profile",
                    ParamMeta::of(TypeCode::Binary)
                        .required(true)
                        .display("Profile"),
                )
                .level(Perm::Config),
        )
        .await?;
        ctx.declare_action(
            "profiles",
            "remove",
            ActionMeta::new()
                .display("Remove Profile")
                .group(GROUP_EDIT)
                .param("name", str_param().required(true).display("Name"))
                .level(Perm::Config),
        )
        .await?;
        ctx.declare_node("quarantine", NodeMeta::folder()).await?;
        refresh_quarantine(&ctx, &cfg.ctl).await?;
        ctx.declare_node("audit", NodeMeta::number().is("wy:audit"))
            .await?;
        ctx.declare_action(
            "audit",
            "tail",
            ActionMeta::new()
                .display("Tail")
                .param("n", ParamMeta::of(TypeCode::Number).display("Records"))
                .result(ActionResult::Type(TypeCode::Array))
                .level(Perm::Config),
        )
        .await?;
        // `wy/<site>/sys/broker` liveliness (no node): process links
        // re-publish when it returns, peers show `connected` from it.
        let broker = ctx
            .client()
            .liveliness()
            .declare_token(format!("wy/{}/sys/broker", cfg.ctl.cfg.site))
            .await
            .map_err(|e| LinkError::internal(format!("broker token: {e}")))?;
        Ok(Admin {
            ctx,
            ctl: cfg.ctl,
            embedded: cfg.embedded,
            _broker: broker,
        })
    }

    /// `sys/allow_all_links`, `sys/enable_quarantine` (level `config`).
    /// Neither changes the ACL by itself; only links admitted later do.
    async fn on_set(
        &mut self,
        path: &str,
        value: Value,
        who: &Caller,
    ) -> wyrm_link_sdk::Result<()> {
        let level_of = |v: &Value, choices: &[String]| -> Result<Option<String>, LinkError> {
            let name = match v {
                Value::UInt(i) => choices.get(*i as usize).cloned(),
                Value::Str(s) => choices.iter().find(|c| *c == s).cloned(),
                _ => None,
            }
            .ok_or_else(|| LinkError::invalid_parameter("log level: one of the choices"))?;
            Ok((name != "default").then_some(name))
        };
        if path == "log_level" {
            let lc =
                crate::logs::global().ok_or_else(|| LinkError::not_supported("no log control"))?;
            let levels: Vec<String> = crate::logs::LEVELS.iter().map(|l| l.to_string()).collect();
            let level = level_of(&value, &levels)?.unwrap_or_else(|| "info".into());
            lc.set_level(&level).map_err(LinkError::invalid_parameter)?;
            self.ctl
                .apply(Op::SetLogLevel {
                    link: None,
                    level: Some(level.clone()),
                })
                .map_err(rejected)?;
            self.ctl
                .record(&sub_of(who), "log_level", "broker", Status::Ok, &level);
            let idx = crate::logs::LEVELS
                .iter()
                .position(|l| *l == level)
                .unwrap_or(2);
            return self
                .ctx
                .update(path, Value::UInt(idx as u64), Quality::Good, now_us())
                .await;
        }
        if let ["links", id, "log_level"] = path.split('/').collect::<Vec<_>>().as_slice() {
            let level = level_of(&value, &link_levels())?;
            return self.set_link_log_level(id, level, &sub_of(who)).await;
        }
        if let ["upstream", site, "enabled"] = path.split('/').collect::<Vec<_>>().as_slice() {
            let Value::Bool(on) = value else {
                return Err(LinkError::invalid_parameter("enabled: true or false"));
            };
            return self.enable_peer(site, on, &sub_of(who)).await;
        }
        if !OPTION_NAMES.contains(&path) {
            return Err(LinkError::not_supported(format!("{path}/~set")));
        }
        let Value::Bool(on) = value else {
            return Err(LinkError::invalid_parameter(format!(
                "{path}: true or false"
            )));
        };
        self.ctl
            .apply(Op::SetOption {
                name: path.to_owned(),
                on,
            })
            .map_err(rejected)?;
        self.ctl.record(
            &sub_of(who),
            "set_option",
            path,
            Status::Ok,
            &on.to_string(),
        );
        info!(option = path, on, "broker option changed");
        self.ctx
            .update(path, Value::Bool(on), Quality::Good, now_us())
            .await
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
            (["links"], "install_zip") => {
                let _busy = self.ctl.busy()?;
                let name = arg_str(&args, "name").unwrap_or_default().trim().to_owned();
                let r = match arg(&args, "zip") {
                    Some(Value::Bytes(zip)) => {
                        self.install_package(&name, zip.clone(), "zip".into(), &sub)
                            .await
                    }
                    _ => Err("zip: required".into()),
                };
                Ok(Some(outcome(r)))
            }
            (["links"], "install_wasm") => {
                let _busy = self.ctl.busy()?;
                let name = arg_str(&args, "name").unwrap_or_default().trim().to_owned();
                let r = match arg(&args, "wasm") {
                    Some(Value::Bytes(wasm)) => match packages::wrap_component(&name, wasm) {
                        Ok(zip) => self.install_package(&name, zip, "wasm".into(), &sub).await,
                        Err(e) => Err(e),
                    },
                    _ => Err("wasm: required".into()),
                };
                Ok(Some(outcome(r)))
            }
            (["links"], "install_url") => {
                let _busy = self.ctl.busy()?;
                let name = arg_str(&args, "name").unwrap_or_default().trim().to_owned();
                let url = arg_str(&args, "url").unwrap_or_default().trim().to_owned();
                let r = match crate::fetch::get(&url, packages::MAX_ZIP, FETCH_TIMEOUT).await {
                    Ok(zip) => {
                        self.install_package(&name, zip, format!("url {url}"), &sub)
                            .await
                    }
                    Err(e) => Err(e),
                };
                Ok(Some(outcome(r)))
            }
            (["links"], "install_git") => {
                let _busy = self.ctl.busy()?;
                let name = arg_str(&args, "name").unwrap_or_default().trim().to_owned();
                let url = arg_str(&args, "url").unwrap_or_default().trim().to_owned();
                let git_ref = arg_str(&args, "ref").unwrap_or_default().trim().to_owned();
                let root = self.ctl.packages_root();
                // file:// only in the dev profile (tests, a local checkout)
                let r = match crate::git::clone_zip(&url, &git_ref, self.ctl.cfg.dev, &root).await {
                    Ok((zip, commit)) => {
                        let source = format!("git {url} {git_ref} {commit}");
                        self.install_package(&name, zip, source, &sub).await
                    }
                    Err(e) => Err(e),
                };
                Ok(Some(outcome(r)))
            }
            (["links"], "install_repo") => {
                let _busy = self.ctl.busy()?;
                let name = arg_str(&args, "name").unwrap_or_default().trim().to_owned();
                let package = arg_str(&args, "package").unwrap_or_default().to_owned();
                Ok(Some(outcome(
                    self.install_from_repo(&name, &package, &sub).await,
                )))
            }
            (["packages", name], "remove") => self.remove_package(name, &sub).await,
            (["links", id], "hello") => self.hello(id, &args).await,
            (["links", id], "start") => self.start_link(id, &sub).await.map(|_| None),
            (["links", id], "stop") => self.stop_link(id, &sub).await.map(|_| None),
            (["links", id], "remove") => self.remove(id, &sub).await.map(|_| None),
            (["links", id], "update") => {
                let params = arg(&args, "params")
                    .cloned()
                    .ok_or_else(|| LinkError::invalid_parameter("params: required"))?;
                self.update_params(id, params, &sub, "update").await
            }
            (["links", id], "history") => self.params_history(id),
            (["links", id], "grant") => {
                let path = arg_str(&args, "path").unwrap_or_default().trim().to_owned();
                let level = arg_str(&args, "level").unwrap_or_default();
                let level = Perm::ALL
                    .iter()
                    .copied()
                    .find(|p| p.name() == level)
                    .ok_or_else(|| LinkError::invalid_parameter(format!("level: {level}?")))?;
                self.grant(id, &path, level, &sub).map(|_| None)
            }
            (["links", id], "get_log") => {
                let (n, level, filter) = log_args(&args)?;
                let def = self.def(id)?;
                let lines = match def.mode {
                    Mode::Process => self.ctl.supervisor.log_tail(id, n, level, &filter),
                    Mode::Embedded => crate::logs::global()
                        .map(|lc| lc.tail(n, level, &filter, Some(id)))
                        .unwrap_or_default(),
                    Mode::External => {
                        return Err(LinkError::not_supported(
                            "an external link logs on its own host",
                        ))
                    }
                };
                Ok(Some(log_rows(lines)))
            }
            ([""], "get_log") => {
                let (n, level, filter) = log_args(&args)?;
                let lc = crate::logs::global()
                    .ok_or_else(|| LinkError::not_supported("no log control"))?;
                let link = arg_str(&args, "link").filter(|l| !l.is_empty());
                Ok(Some(log_rows(lc.tail(n, level, &filter, link))))
            }
            (["links", id], "rollback") => {
                let rev = arg(&args, "rev")
                    .and_then(Value::as_f64)
                    .ok_or_else(|| LinkError::invalid_parameter("rev: required"))?
                    as u32;
                let old = self
                    .ctl
                    .registry()
                    .history
                    .get(*id)
                    .and_then(|h| h.iter().find(|(r, _)| *r == rev).cloned())
                    .ok_or_else(|| LinkError::not_found(format!("{id} rev {rev}")))?;
                self.update_params(id, decode_params(&old.1), &sub, "rollback")
                    .await
            }
            (["links", id], "set_secret") => self.set_secret(id, &args, &sub),
            (["links", id], "delete_secret") => self.delete_secret(id, &args, &sub),
            (["quarantine", cn], "approve") => self.approve(cn, &args, &sub).await,
            (["quarantine"], "authorize") => match arg_str(&args, "dsid") {
                Some(cn) => self.approve(cn, &args, &sub).await,
                None => Err(LinkError::invalid_parameter("dsid: required")),
            },
            (["quarantine"], "deauthorize") => match arg_str(&args, "link") {
                Some(id) => self.deauthorize(id, &sub).await,
                None => Err(LinkError::invalid_parameter("link: required")),
            },
            (["quarantine", cn], "reject") => self.reject(cn, &sub).await.map(|_| None),
            (["profiles"], "put") => self.put_profile(&args, &sub).await.map(|_| None),
            (["profiles"], "remove") => self.remove_profile(&args, &sub).await.map(|_| None),
            ([""], "clear_conns") => self.clear_conns(&sub).await,
            (["upstream"], "add") => self.add_peer(PeerDir::Upstream, &args, &sub).await,
            (["downstream"], "add") => self.add_peer(PeerDir::Downstream, &args, &sub).await,
            (["upstream" | "downstream", site], "remove") => self.remove_peer(site, &sub).await,
            ([""], "get_permissions") => {
                let mut rows: Vec<Value> = self
                    .ctl
                    .role_grants()
                    .map(|r| r.grants())
                    .unwrap_or_default()
                    .into_iter()
                    .map(|(role, key, p)| perm_row("gateway", &role, &key, p.name()))
                    .collect();
                for d in self.ctl.registry().links.values() {
                    for (path, code) in &d.grants {
                        if let Ok(p) = Perm::try_from(*code) {
                            rows.push(perm_row("link", &d.id, path, p.name()));
                        }
                    }
                }
                rows.extend(acl_rows(&self.ctl.acl()));
                Ok(Some(Value::Array(rows)))
            }
            ([""], "update_permissions") => {
                let roles = self
                    .ctl
                    .role_grants()
                    .ok_or_else(|| LinkError::not_supported("no user gateway"))?;
                let need = |k: &str| {
                    arg_str(&args, k)
                        .filter(|v| !v.is_empty())
                        .ok_or_else(|| LinkError::invalid_parameter(format!("{k}: required")))
                };
                let (role, path) = (need("role")?, need("path")?);
                let level = need("level")?;
                let level = Perm::ALL
                    .iter()
                    .copied()
                    .find(|p| p.name() == level)
                    .ok_or_else(|| LinkError::invalid_parameter(format!("level: {level}?")))?;
                roles
                    .set_grant(role, path, level)
                    .map_err(LinkError::invalid_parameter)?;
                self.ctl.record(
                    &sub,
                    "update_permissions",
                    role,
                    Status::Ok,
                    &format!("{path} {}", level.name()),
                );
                Ok(None)
            }
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
        // the Authorize/Deauthorize lists follow links, quarantine and roles
        if result.is_ok()
            && matches!(
                action,
                "install"
                    | "remove"
                    | "approve"
                    | "reject"
                    | "authorize"
                    | "deauthorize"
                    | "clear_conns"
                    | "update_permissions"
            )
        {
            if let Err(e) = refresh_quarantine(&self.ctx, &self.ctl).await {
                debug!("quarantine actions: {e}");
            }
        }
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
        // `pkg:<name>`: an installed package (ADR 0011); process packages
        // run as process links, never embedded.
        let package =
            match driver.strip_prefix(packages::DRIVER_PREFIX) {
                Some(name) => {
                    Some(ctl.registry().packages.get(name).cloned().ok_or_else(|| {
                        LinkError::invalid_parameter(format!("no package {name}"))
                    })?)
                }
                None => None,
            };
        // process packages run as process links; wasm packages in the
        // broker's space (ADR 0011)
        let package_mode = |p: &PackageDef| match p.kind {
            PackageKind::Process => Mode::Process,
            PackageKind::Wasm => Mode::Embedded,
        };
        let mode = match arg_str(args, "mode") {
            Some(m) => Mode::parse(m).ok_or_else(|| LinkError::invalid_parameter("mode"))?,
            None => match &package {
                Some(p) => package_mode(p),
                None if compiled => Mode::Embedded,
                None => Mode::External,
            },
        };
        if let Some(p) = &package {
            if mode != package_mode(p) {
                return Err(LinkError::invalid_parameter(format!(
                    "package {} runs as {} links",
                    p.name,
                    p.kind.name()
                )));
            }
        }
        let params = arg(args, "params")
            .cloned()
            .unwrap_or(Value::Map(Default::default()));
        crate::registry::validate_link_id(&id).map_err(LinkError::invalid_parameter)?;
        if ctl.peers().downstream.contains(&id) {
            return Err(LinkError::invalid_parameter(format!(
                "link id {id:?} is a downstream site (down/{id} is its broker node)"
            )));
        }
        // Before any side effect (token, secret purge) on an existing id.
        if ctl.registry().links.contains_key(&id) {
            return Err(LinkError::invalid_parameter(format!("link {id} exists")));
        }
        crate::secrets::lint_params(&params, "params").map_err(LinkError::invalid_parameter)?;
        if mode != Mode::External && package.is_none() {
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
        if driver == AGENT_DRIVER && mode == Mode::External {
            return Err(LinkError::invalid_parameter(
                "an agent link runs embedded or as a supervised process: its key is trusted by every link",
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
            display: None,
            granted: None,
            log_level: None,
            grants: Vec::new(),
        };
        ctl.secrets
            .drop_link(&id)
            .map_err(|e| LinkError::internal(e.to_string()))?;
        ctl.apply(Op::Install(def.clone())).map_err(rejected)?;
        ctl.record(sub, "install", &id, Status::Ok, mode.name());
        ctl.ensure_store_key(&id)
            .map_err(|e| LinkError::internal(e.to_string()))?;
        if def.driver == AGENT_DRIVER {
            // New trusted key: running links restart with the new trust list.
            ctl.ensure_agent_key(&def)
                .map_err(|e| LinkError::internal(e.to_string()))?;
            ctl.schedule_reload();
        }
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
            if ctl.cfg.per_link_router_rules {
                ctl.schedule_reload();
            }
        }
        Ok(Some(Value::Map(reply)))
    }

    /// Install a package from `zip` and run it as the link `link`
    /// (ADR 0011). The same version with the same bytes is reused (another
    /// link of the package); a new version replaces the old one and restarts
    /// the links that run it. `Err` is the message of `success: false`.
    async fn install_package(
        &self,
        link: &str,
        zip: Vec<u8>,
        source: String,
        sub: &str,
    ) -> Result<String, String> {
        crate::registry::validate_link_id(link)?;
        let root = self.ctl.packages_root();
        let now = now_s();
        let unpacked = {
            let root = root.clone();
            tokio::task::spawn_blocking(move || packages::unpack(&zip, &root, &source, now))
                .await
                .map_err(|e| e.to_string())??
        };
        let def = unpacked.def.clone();
        if def.kind == PackageKind::Process && self.ctl.cfg.link_endpoint.is_none() {
            return Err("process links need a tls/ listener on the broker".into());
        }
        let reg = self.ctl.registry();
        let driver = format!("{}{}", packages::DRIVER_PREFIX, def.name);
        if let Some(l) = reg.links.get(link) {
            if l.driver != driver {
                return Err(format!("link {link} exists and runs {}", l.driver));
            }
        }
        let mut message = match reg.packages.get(&def.name) {
            Some(old) if old.version == def.version => {
                if old.sha256 != def.sha256 {
                    return Err(format!(
                        "{} {} is installed with other content",
                        def.name, def.version
                    ));
                }
                if def.kind == PackageKind::Wasm {
                    self.ctl.publish_component(&def)?;
                }
                format!("package {} {} is installed", def.name, def.version)
            }
            old => {
                unpacked.commit(&root)?;
                if def.kind == PackageKind::Wasm {
                    self.ctl.publish_component(&def)?;
                }
                self.ctl
                    .apply(Op::PutPackage(def.clone()))
                    .map_err(|e| e.to_string())?;
                self.ctl.record(
                    sub,
                    "package_install",
                    &def.name,
                    Status::Ok,
                    &format!("{} sha256:{} {}", def.version, def.sha256, def.source),
                );
                declare_package(&self.ctx, &def)
                    .await
                    .map_err(|e| e.to_string())?;
                if let Some(old) = old {
                    // Upgrade: the links on it restart from the new files.
                    for l in reg.links.values().filter(|l| l.driver == driver) {
                        let _ = self.stop_link(&l.id, sub).await;
                        self.start_link(&l.id, sub)
                            .await
                            .map_err(|e| e.to_string())?;
                    }
                    let _ = std::fs::remove_dir_all(packages::dir(&root, old));
                    format!("package {} {} → {}", def.name, old.version, def.version)
                } else {
                    format!("package {} {} installed", def.name, def.version)
                }
            }
        };
        if !reg.links.contains_key(link) {
            let mut args = BTreeMap::from([
                ("id".to_owned(), Value::Str(link.to_owned())),
                ("driver".to_owned(), Value::Str(driver)),
            ]);
            match def.kind {
                PackageKind::Process => {
                    args.insert("mode".into(), Value::Str("process".into()));
                }
                PackageKind::Wasm => {
                    // An embedded `wasm` link with one connection on the
                    // package's component; devices and points come from its
                    // own Add actions (ADR 0012).
                    args.insert("mode".into(), Value::Str("embedded".into()));
                    let main =
                        BTreeMap::from([("component".to_owned(), Value::Str(def.name.clone()))]);
                    let conns = BTreeMap::from([("main".to_owned(), Value::Map(main))]);
                    args.insert(
                        "params".into(),
                        Value::Map(BTreeMap::from([(
                            "connections".to_owned(),
                            Value::Map(conns),
                        )])),
                    );
                }
            }
            let args = Value::Map(args);
            self.install(&args, sub).await.map_err(|e| e.to_string())?;
            message.push_str(&format!("; link {link} installed"));
            // the grants the package asks for, shown and audited
            for (path, code) in &def.requester {
                let level = Perm::try_from(*code).map_err(|c| format!("level {c}"))?;
                self.grant(link, path, level, sub)
                    .map_err(|e| e.to_string())?;
                message.push_str(&format!("; grant {path} {}", level.name()));
            }
        }
        Ok(message)
    }

    /// "from Repository": the index entry's zip, which must match its
    /// SHA-256.
    async fn install_from_repo(
        &self,
        link: &str,
        package: &str,
        sub: &str,
    ) -> Result<String, String> {
        let index = self
            .ctl
            .cfg
            .repository
            .clone()
            .ok_or("no packages.repository")?;
        let state = self
            .ctl
            .repo
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .clone();
        let list = match state {
            Some(Ok(list)) => list,
            Some(Err(e)) => return Err(format!("repository unreachable: {e}")),
            None => return Err("the repository index is still loading".into()),
        };
        let e = list
            .into_iter()
            .find(|e| e.name == package)
            .ok_or_else(|| format!("no package {package} in the repository"))?;
        let zip = crate::fetch::get(&e.url, packages::MAX_ZIP, FETCH_TIMEOUT).await?;
        let got = hex::encode(<sha2::Sha256 as sha2::Digest>::digest(&zip));
        if !got.eq_ignore_ascii_case(&e.sha256) {
            return Err(format!("{package}: sha256 {got} does not match the index"));
        }
        self.install_package(link, zip, format!("repository {index}"), sub)
            .await
    }

    async fn remove_package(&self, name: &str, sub: &str) -> wyrm_link_sdk::Result<Option<Value>> {
        let def = self
            .ctl
            .registry()
            .packages
            .get(name)
            .cloned()
            .ok_or_else(|| LinkError::not_found(name.to_owned()))?;
        self.ctl
            .apply(Op::RemovePackage(name.to_owned()))
            .map_err(rejected)?;
        let _ = std::fs::remove_dir_all(self.ctl.packages_root().join(name));
        let _ = std::fs::remove_file(self.ctl.component_store().join(format!("{name}.wasm")));
        self.ctl
            .record(sub, "package_remove", name, Status::Ok, &def.version);
        self.ctx.remove_node(&format!("packages/{name}")).await?;
        Ok(None)
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
        let (admin_keys, limited_keys) = self.ctl.link_trust();
        reply.insert(
            "admin_keys".into(),
            Value::Array(
                admin_keys
                    .iter()
                    .map(|k| Value::Bytes(k.to_bytes().to_vec()))
                    .collect(),
            ),
        );
        // `[key, cap, scopes]`; a key bound to one subject goes in
        // `bound_keys` as `[key, cap, scopes, subject]`: a link built
        // before subjects ignores that field and so never trusts it.
        let entry = |l: &wyrm_link_sdk::LimitedKey| {
            let mut e = vec![
                Value::Bytes(l.key.to_bytes().to_vec()),
                Value::UInt(l.cap.code().into()),
                Value::Array(l.scopes.iter().cloned().map(Value::Str).collect()),
            ];
            e.extend(l.subject.clone().map(Value::Str));
            Value::Array(e)
        };
        let (bound, free): (Vec<_>, Vec<_>) =
            limited_keys.iter().partition(|l| l.subject.is_some());
        reply.insert(
            "limited_keys".into(),
            Value::Array(free.into_iter().map(entry).collect()),
        );
        reply.insert(
            "bound_keys".into(),
            Value::Array(bound.into_iter().map(entry).collect()),
        );
        Ok(Some(Value::Map(reply)))
    }

    /// New params for a runtime-installed link (validated, linted, kept in
    /// the history), then a restart so the link runs them. Replies the new
    /// `rev`. Links from `wyrmd.json5` are edited there.
    async fn update_params(
        &self,
        id: &str,
        params: Value,
        sub: &str,
        op: &str,
    ) -> wyrm_link_sdk::Result<Option<Value>> {
        let def = self.def(id)?;
        if def.origin == Origin::Config {
            return Err(LinkError::not_supported(
                "defined in wyrmd.json5; change it there",
            ));
        }
        crate::secrets::lint_params(&params, "params").map_err(LinkError::invalid_parameter)?;
        if def.mode != Mode::External {
            self.ctl.host.validate(&def.driver, &params)?;
        }
        self.ctl
            .apply(Op::Update {
                id: id.to_owned(),
                mode: def.mode,
                params: encode_params(&params)?,
            })
            .map_err(rejected)?;
        let rev = self.def(id)?.rev;
        self.ctl
            .record(sub, op, id, Status::Ok, &format!("rev {rev}"));
        if def.driver == AGENT_DRIVER {
            // allowed_prefixes scope its key in every link's trust list
            self.ctl.schedule_reload();
        } else if def.mode != Mode::External {
            self.stop_link(id, sub).await?;
            self.start_link(id, sub).await?;
        }
        Ok(Some(Value::UInt(rev.into())))
    }

    /// Previous params (oldest first) and the current one: `[{rev, params}]`.
    fn params_history(&self, id: &str) -> wyrm_link_sdk::Result<Option<Value>> {
        let def = self.def(id)?;
        let reg = self.ctl.registry();
        let entry = |rev: u32, params: &[u8]| {
            let mut m = BTreeMap::new();
            m.insert("rev".to_owned(), Value::UInt(rev.into()));
            m.insert("params".to_owned(), decode_params(params));
            Value::Map(m)
        };
        let mut out: Vec<Value> = reg
            .history
            .get(id)
            .into_iter()
            .flatten()
            .map(|(r, p)| entry(*r, p))
            .collect();
        out.push(entry(def.rev, &def.params));
        Ok(Some(Value::Array(out)))
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
        self.reload_if_agent(id);
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
        self.reload_if_agent(id);
        Ok(Some(self.secret_names(id)))
    }

    /// An agent key changed: links must reload their trust list.
    fn reload_if_agent(&self, id: &str) {
        if self
            .ctl
            .registry()
            .links
            .get(id)
            .is_some_and(|d| d.driver == AGENT_DRIVER)
        {
            self.ctl.schedule_reload();
        }
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

    /// `profiles/~act/put {name, profile: CBOR ProfileDef}`; publishes the
    /// new profile on `pub/<name>/~meta` for subscribers.
    async fn put_profile(&self, args: &Value, sub: &str) -> wyrm_link_sdk::Result<()> {
        let name = arg_str(args, "name").unwrap_or_default().to_owned();
        let Some(Value::Bytes(cbor)) = arg(args, "profile") else {
            return Err(LinkError::invalid_parameter("profile: CBOR bytes required"));
        };
        self.ctl
            .apply(Op::PutProfile {
                name: name.clone(),
                cbor: cbor.clone(),
            })
            .map_err(rejected)?;
        self.ctl.record(sub, "profile_put", &name, Status::Ok, "");
        let key = profile_key(&self.ctl.cfg.site, &name);
        if let Err(e) = self.ctx.client().put(&key, cbor.clone()).await {
            debug!("publish {key}: {e}");
        }
        Ok(())
    }

    async fn remove_profile(&self, args: &Value, sub: &str) -> wyrm_link_sdk::Result<()> {
        let name = arg_str(args, "name").unwrap_or_default().to_owned();
        self.ctl
            .apply(Op::RemoveProfile(name.clone()))
            .map_err(rejected)?;
        self.ctl
            .record(sub, "profile_remove", &name, Status::Ok, "");
        let key = profile_key(&self.ctl.cfg.site, &name);
        if let Err(e) = self.ctx.client().delete(&key).await {
            debug!("delete {key}: {e}");
        }
        Ok(())
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
        if self.unlink(id, sub).await? {
            self.ctl.schedule_reload();
        }
        Ok(())
    }

    /// DSA `clearConns`: forget the runtime-installed external links that
    /// are not connected now. Their ids are retired like any removed remote
    /// link (ADR 0006): a device needs a new id to come back. Replies the
    /// removed ids, nothing when there were none.
    async fn clear_conns(&self, sub: &str) -> wyrm_link_sdk::Result<Option<Value>> {
        let key = format!("wy/{}/down/*", self.ctl.cfg.site);
        let replies = self
            .ctx
            .client()
            .liveliness()
            .get(&key)
            .timeout(Duration::from_secs(2))
            .await
            .map_err(|e| LinkError::internal(format!("link presence: {e}")))?;
        let mut up = HashSet::new();
        while let Ok(r) = replies.recv_async().await {
            if let Ok(s) = r.result() {
                if let Some(id) = s.key_expr().as_str().rsplit('/').next() {
                    up.insert(id.to_owned());
                }
            }
        }
        let gone: Vec<String> = self
            .ctl
            .registry()
            .links
            .values()
            .filter(|d| {
                d.mode == Mode::External && d.origin == Origin::Runtime && !up.contains(&d.id)
            })
            .map(|d| d.id.clone())
            .collect();
        let mut reload = false;
        for id in &gone {
            reload |= self.unlink(id, sub).await?;
        }
        if reload {
            self.ctl.schedule_reload();
        }
        Ok((!gone.is_empty()).then(|| Value::Array(gone.into_iter().map(Value::Str).collect())))
    }

    /// Remove a runtime-installed link; `true` if the ACL must be rebuilt.
    async fn unlink(&self, id: &str, sub: &str) -> wyrm_link_sdk::Result<bool> {
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
        self.ctl.supervisor.forget_log(id);
        if let Some(lc) = crate::logs::global() {
            let _ = lc.set_link_level(id, None);
        }
        self.ctl.record(sub, "remove", id, Status::Ok, "");
        self.revoke_link_grants(id, sub);
        Ok(
            def.mode.is_remote()
                || def.driver == AGENT_DRIVER
                || self.ctl.cfg.per_link_router_rules,
        )
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
        if driver == AGENT_DRIVER {
            return Err(LinkError::invalid_parameter(
                "an approved certificate is an external link; agent links cannot be external",
            ));
        }
        let params = arg(args, "params")
            .cloned()
            .unwrap_or(Value::Map(Default::default()));
        let text = |k: &str| {
            arg_str(args, k)
                .map(str::trim)
                .filter(|v| !v.is_empty() && *v != NO_ROLE)
        };
        let display = text("name").map(str::to_owned);
        if display.as_ref().is_some_and(|d| d.chars().count() > 64) {
            return Err(LinkError::invalid_parameter("name: at most 64 characters"));
        }
        // Group = a gateway role that gets write on the link (owner
        // decision 2026-10-22); checked before anything is installed.
        let grant = match text("group") {
            None => None,
            Some(role) => {
                let roles = self
                    .ctl
                    .role_grants()
                    .ok_or_else(|| LinkError::not_supported("group: no user gateway"))?;
                if !role_names(&self.ctl).iter().any(|r| r == role) {
                    return Err(LinkError::invalid_parameter(format!(
                        "group: no role {role}"
                    )));
                }
                Some((roles, role.to_owned()))
            }
        };
        let how = Admission {
            driver,
            params,
            display,
            granted: grant.as_ref().map(|(_, role)| role.clone()),
        };
        let token = admit(&self.ctl, &self.ctx, cn, how, sub, "approve").await?;
        let mut reply = BTreeMap::new();
        if let Some(t) = token {
            reply.insert("token".into(), Value::Str(t));
        }
        if let Some((roles, role)) = grant {
            let key = format!("wy/{{site}}/down/{cn}/**");
            match roles.set_grant(&role, &key, Perm::Write) {
                Ok(()) => self.ctl.record(
                    sub,
                    "update_permissions",
                    &role,
                    Status::Ok,
                    &format!("{key} write"),
                ),
                Err(e) => {
                    reply.insert("warning".into(), Value::Str(format!("group: {e}")));
                }
            }
        }
        Ok(Some(Value::Map(reply)))
    }

    /// DSA Deauthorize (owner decision 2026-10-22): the external link goes
    /// back to quarantine instead of being retired; its token and secrets
    /// go, and only a manual Authorize admits the CN again.
    async fn deauthorize(&self, id: &str, sub: &str) -> wyrm_link_sdk::Result<Option<Value>> {
        let def = self.def(id)?;
        let seen = now_s();
        self.ctl
            .apply(Op::Deauthorize {
                id: id.to_owned(),
                seen,
            })
            .map_err(rejected)?;
        self.ctl
            .secrets
            .drop_link(id)
            .map_err(|e| LinkError::internal(e.to_string()))?;
        if let Ok(dir) = self.ctl.link_dir(id) {
            let _ = std::fs::remove_dir_all(dir);
        }
        self.ctx.remove_node(&format!("links/{id}")).await?;
        self.ctl.record(sub, "deauthorize", id, Status::Ok, "");
        self.revoke_link_grants(&def.id, sub);
        self.ctl.schedule_reload();
        Ok(None)
    }

    /// When a link goes (Deauthorize, Remove): revoke every gateway grant
    /// on exactly its branch that gives a role more than its other grants
    /// would (the Authorize `group` grant, or a widening one made by hand),
    /// so a CN authorized again starts without them. Restrictive overrides
    /// stay.
    fn revoke_link_grants(&self, id: &str, sub: &str) {
        let Some(roles) = self.ctl.role_grants() else {
            return;
        };
        let site = &self.ctl.cfg.site;
        let keys = [
            format!("wy/{{site}}/down/{id}/**"),
            format!("wy/{site}/down/{id}/**"),
        ];
        match roles.revoke_widening(&keys, &format!("wy/{site}/down/{id}/~val")) {
            Ok(gone) => {
                for (role, key, p) in gone {
                    self.ctl.record(
                        sub,
                        "update_permissions",
                        &role,
                        Status::Ok,
                        &format!("{key} none (was {}; link {id} gone)", p.name()),
                    );
                }
            }
            Err(e) => warn!(link = %id, "grants not revoked: {e}"),
        }
    }

    async fn add_peer(
        &self,
        dir: PeerDir,
        args: &Value,
        sub: &str,
    ) -> wyrm_link_sdk::Result<Option<Value>> {
        let need = |k: &str| {
            arg_str(args, k)
                .map(str::trim)
                .filter(|v| !v.is_empty())
                .ok_or_else(|| LinkError::invalid_parameter(format!("{k}: required")))
        };
        let site = need("name")?;
        let ca_pem = need("ca")?;
        wyrm_core::keyspace::validate_segment(site)
            .map_err(|e| LinkError::invalid_parameter(format!("name: {e}")))?;
        let configured = self.ctl.config_peers();
        if site == self.ctl.cfg.site
            || configured.peers.upstream.iter().any(|u| u == site)
            || configured.peers.downstream.iter().any(|d| d == site)
            || self.ctl.registry().peers.contains_key(site)
        {
            return Err(LinkError::invalid_parameter(format!(
                "site {site} is this broker or already a peer"
            )));
        }
        check_ca_pem(ca_pem).map_err(LinkError::invalid_parameter)?;
        let (endpoint, enabled) = match dir {
            PeerDir::Upstream => {
                let url = need("url")?;
                if !url.starts_with("quic/") || url.contains(['#', '?', ';']) || url.len() > 256 {
                    return Err(LinkError::invalid_parameter(format!(
                        "url {url}: expected quic/<host>:<port>"
                    )));
                }
                let on = !matches!(arg(args, "enabled"), Some(Value::Bool(false)));
                (url.to_owned(), on)
            }
            PeerDir::Downstream => {
                if !configured.listen {
                    return Err(LinkError::not_supported(
                        "no peers.listen in wyrmd.json5: downstream brokers cannot connect",
                    ));
                }
                (String::new(), true)
            }
        };
        self.ctl
            .apply(Op::AddPeer(PeerDef {
                site: site.to_owned(),
                dir,
                endpoint: endpoint.clone(),
                ca_pem: format!("{ca_pem}\n"),
                enabled,
                created: now_s(),
            }))
            .map_err(rejected)?;
        let kind = match dir {
            PeerDir::Upstream => "upstream",
            PeerDir::Downstream => "downstream",
        };
        self.ctl.record(
            sub,
            "peer_add",
            site,
            Status::Ok,
            &format!("{kind} {endpoint}"),
        );
        match dir {
            PeerDir::Upstream => {
                declare_upstream(&self.ctx, site, &endpoint, enabled, true).await?
            }
            PeerDir::Downstream => declare_downstream(&self.ctx, site, true).await?,
        }
        self.ctl.schedule_reload();
        Ok(None)
    }

    async fn remove_peer(&self, site: &str, sub: &str) -> wyrm_link_sdk::Result<Option<Value>> {
        let Some(def) = self.ctl.registry().peers.get(site).cloned() else {
            return Err(LinkError::not_supported(
                "not a runtime peer; peers from wyrmd.json5 are removed there",
            ));
        };
        self.ctl
            .apply(Op::RemovePeer(site.to_owned()))
            .map_err(rejected)?;
        let _ = std::fs::remove_file(self.ctl.peer_ca_path(site));
        self.ctl.record(sub, "peer_remove", site, Status::Ok, "");
        let kind = match def.dir {
            PeerDir::Upstream => "upstream",
            PeerDir::Downstream => "downstream",
        };
        self.ctx.remove_node(&format!("{kind}/{site}")).await?;
        self.ctl.schedule_reload();
        Ok(None)
    }

    async fn enable_peer(&self, site: &str, on: bool, sub: &str) -> wyrm_link_sdk::Result<()> {
        if !self
            .ctl
            .registry()
            .peers
            .get(site)
            .is_some_and(|d| d.dir == PeerDir::Upstream)
        {
            return Err(LinkError::not_supported(
                "not a runtime upstream peer; peers from wyrmd.json5 are changed there",
            ));
        }
        self.ctl
            .apply(Op::SetPeerEnabled {
                site: site.to_owned(),
                on,
            })
            .map_err(rejected)?;
        self.ctl
            .record(sub, "peer_enable", site, Status::Ok, &on.to_string());
        self.ctx
            .update(
                &format!("upstream/{site}/enabled"),
                Value::Bool(on),
                Quality::Good,
                now_us(),
            )
            .await?;
        self.ctl.schedule_reload();
        Ok(())
    }

    /// `links/<id>/~act/grant`: one requester grant of a link. The router
    /// ACL (process and external links) and every link's trust list follow
    /// on the rebuild.
    fn grant(&self, id: &str, path: &str, level: Perm, sub: &str) -> wyrm_link_sdk::Result<()> {
        self.def(id)?;
        if level != Perm::None {
            crate::registry::check_grant(path, level).map_err(LinkError::invalid_parameter)?;
        }
        self.ctl
            .apply(Op::SetLinkGrant {
                id: id.to_owned(),
                path: path.to_owned(),
                level: level.code(),
            })
            .map_err(rejected)?;
        let def = self.def(id)?;
        self.ctl
            .ensure_requester_key(&def)
            .map_err(|e| LinkError::internal(e.to_string()))?;
        self.ctl.record(
            sub,
            "link_grant",
            id,
            Status::Ok,
            &format!("{path} {}", level.name()),
        );
        self.ctl.schedule_reload();
        Ok(())
    }

    /// `links/<id>/log_level`: an embedded link's span directive in the
    /// broker filter; a process link's `RUST_LOG`, applied by a restart.
    async fn set_link_log_level(
        &self,
        id: &str,
        level: Option<String>,
        sub: &str,
    ) -> wyrm_link_sdk::Result<()> {
        let def = self.def(id)?;
        self.ctl
            .apply(Op::SetLogLevel {
                link: Some(id.to_owned()),
                level: level.clone(),
            })
            .map_err(rejected)?;
        match def.mode {
            Mode::Embedded => {
                if let Some(lc) = crate::logs::global() {
                    lc.set_link_level(id, level.as_deref())
                        .map_err(LinkError::invalid_parameter)?;
                }
            }
            Mode::Process => {
                if self.ctl.supervisor.state(id).is_some() {
                    self.stop_link(id, sub).await?;
                    self.start_link(id, sub).await?;
                }
            }
            Mode::External => {}
        }
        let shown = level.as_deref().unwrap_or("default");
        self.ctl.record(sub, "log_level", id, Status::Ok, shown);
        let idx = link_levels().iter().position(|l| l == shown).unwrap_or(0);
        self.ctx
            .update(
                &format!("links/{id}/log_level"),
                Value::UInt(idx as u64),
                Quality::Good,
                now_us(),
            )
            .await
    }

    async fn reject(&self, cn: &str, sub: &str) -> wyrm_link_sdk::Result<()> {
        self.ctl
            .apply(Op::Reject(cn.to_owned()))
            .map_err(rejected)?;
        self.ctl.record(sub, "reject", cn, Status::Ok, "");
        self.ctx.remove_node(&format!("quarantine/{cn}")).await
    }
}

/// What an admitted CN becomes: its driver name, params, display name and
/// the gateway role Authorize grants `write` on it.
struct Admission {
    driver: String,
    params: Value,
    display: Option<String>,
    granted: Option<String>,
}

/// Install `cn`, a certificate CN signed by our CA, as an external link:
/// approved from quarantine, or on first sight with `allow_all_links`.
/// Returns the link token once (also kept in `links/<cn>/token`, 0600).
async fn admit(
    ctl: &Control,
    ctx: &LinkCtx,
    cn: &str,
    how: Admission,
    sub: &str,
    op: &str,
) -> wyrm_link_sdk::Result<Option<String>> {
    let Admission {
        driver,
        params,
        display,
        granted,
    } = how;
    let reg = ctl.registry();
    if reg.links.contains_key(cn) {
        return Err(LinkError::invalid_parameter(format!("link {cn} exists")));
    }
    if ctl.peers().downstream.iter().any(|d| d == cn) {
        return Err(LinkError::invalid_parameter(format!(
            "{cn:?} is a downstream site (down/{cn} is its broker node)"
        )));
    }
    crate::secrets::lint_params(&params, "params").map_err(LinkError::invalid_parameter)?;
    let (token_hash, token) = ctl.new_token_for(cn, Mode::External)?;
    let queued = reg.quarantine.contains_key(cn);
    if queued {
        ctl.apply(Op::Approve(cn.to_owned())).map_err(rejected)?;
    }
    let def = LinkDef {
        id: cn.to_owned(),
        driver,
        mode: Mode::External,
        params: encode_params(&params)?,
        token_hash,
        rev: 1,
        origin: Origin::Runtime,
        created: now_s(),
        display,
        granted,
        log_level: None,
        grants: Vec::new(),
    };
    ctl.secrets
        .drop_link(cn)
        .map_err(|e| LinkError::internal(e.to_string()))?;
    ctl.apply(Op::Install(def.clone())).map_err(rejected)?;
    ctl.record(sub, op, cn, Status::Ok, "");
    if queued {
        ctx.remove_node(&format!("quarantine/{cn}")).await?;
    }
    declare_link(ctx, &def).await?;
    ctl.schedule_reload();
    Ok(token)
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

/// May an unknown certificate CN become a link (quarantine or
/// `allow_all_links`)? Never a known link, a rejected or retired id, an
/// operator, a peer broker, a downstream site's name or an invalid id.
fn admissible(reg: &Registry, operators: &[String], peers: &acl::Peers, cn: &str) -> bool {
    let known = reg.links.contains_key(cn)
        || reg.blocklist.contains(cn)
        || reg.retired.contains(cn)
        || operators.iter().any(|o| o == cn)
        // `down/<d>` is a downstream site's node; never a link.
        || peers.downstream.iter().any(|d| d == cn)
        || cn == "broker";
    !known && crate::registry::validate_link_id(cn).is_ok()
}

/// Sessions whose certificate CN is not a known link or operator: installed
/// with `allow_all_links`, else quarantined with `enable_quarantine`, else
/// ignored. Only TLS sessions count: the link listener trusts our CA alone,
/// while a peer site's CA (QUIC) can sign any CN.
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
        if !admissible(&ctl.registry(), &ctl.cfg.operators, &ctl.peers(), &cn) {
            continue;
        }
        if ev.link().src().protocol().as_str() != "tls" {
            debug!(cn = %cn, "unknown CN outside the TLS link listener: ignored");
            continue;
        }
        let opts = ctl.options();
        // a deauthorized CN stays in quarantine until a manual Authorize
        let held = ctl.registry().held.contains(&cn);
        if opts.allow_all_links && !held {
            let how = Admission {
                driver: "unknown".into(),
                params: Value::Map(Default::default()),
                display: None,
                granted: None,
            };
            match admit(&ctl, &ctx, &cn, how, "system", "auto_install").await {
                Ok(_) => info!(cn = %cn, "unknown certificate: installed (allow_all_links)"),
                Err(e) => warn!(cn = %cn, "allow_all_links install failed: {e}"),
            }
            if let Err(e) = refresh_quarantine(&ctx, &ctl).await {
                debug!("quarantine actions: {e}");
            }
            continue;
        }
        if !opts.enable_quarantine && !held {
            debug!(cn = %cn, "unknown certificate ignored (quarantine off)");
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
        if let Err(e) = refresh_quarantine(&ctx, &ctl).await {
            debug!("quarantine actions: {e}");
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

fn profile_key(site: &str, name: &str) -> String {
    format!("wy/{site}/pub/{name}/~meta")
}

/// `wy/<site>/pub/**` (spec 01/02): `<name>/~meta` answers the CBOR
/// `ProfileDef`; with `?expand=true` the profile with its `extends` chain
/// folded in (no `extends` left). A wildcard `get` answers every match.
async fn serve_profiles(ctl: Arc<Control>, session: Session) {
    let key = format!("wy/{}/pub/**", ctl.cfg.site);
    let q = match session.declare_queryable(&key).complete(true).await {
        Ok(q) => q,
        Err(e) => {
            warn!("profiles queryable: {e}");
            return;
        }
    };
    while let Ok(query) = q.recv_async().await {
        answer_profiles(&ctl, &query).await;
    }
}

async fn answer_profiles(ctl: &Control, q: &zenoh::query::Query) {
    use wyrm_core::profile::{self, ProfileDef};
    let reg = ctl.registry();
    let site = &ctl.cfg.site;
    let expand = q
        .parameters()
        .as_str()
        .split('&')
        .any(|kv| kv == "expand=true");
    let names: Vec<String> = profile::builtins()
        .into_iter()
        .map(|(n, _)| n.to_owned())
        .chain(reg.profiles.keys().cloned())
        .collect();
    let qk = q.key_expr();
    let mut found = false;
    for name in names {
        let k = profile_key(site, &name);
        if !zenoh::key_expr::keyexpr::new(&k).is_ok_and(|k| k.intersects(qk)) {
            continue;
        }
        let Some(p) = reg.profile(&name) else {
            continue;
        };
        let out = if expand {
            let start = NodeMeta {
                is: p.extends.clone().map(Profile::Name),
                ..p.meta.clone()
            };
            let mut meta = profile::expand(&start, |n| reg.profile(n));
            meta.is = None;
            ProfileDef {
                meta,
                extends: None,
            }
        } else {
            p
        };
        let ok = wyrm_core::codec::to_vec(&wyrm_core::Attachment::with_status(Status::Ok));
        if let (Ok(bytes), Ok(ok)) = (wyrm_core::codec::to_vec(&out), ok) {
            if let Err(e) = q.reply(&k, bytes).attachment(ok).await {
                debug!("reply {k}: {e}");
            }
            found = true;
        }
    }
    if !found && !qk.as_str().contains('*') {
        let att = wyrm_core::Attachment::with_status(Status::NotFound);
        if let Ok(a) = wyrm_core::codec::to_vec(&att) {
            let _ = q
                .reply(q.key_expr().clone(), Vec::<u8>::new())
                .attachment(a)
                .await;
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

/// Sum of every series of the counter `name` (exact name, all labels).
pub fn counter(metrics: &str, name: &str) -> f64 {
    metrics
        .lines()
        .filter(|l| {
            l.strip_prefix(name)
                .is_some_and(|rest| rest.starts_with(['{', ' ']))
        })
        .filter_map(|l| l.rsplit(' ').next()?.parse::<f64>().ok())
        .sum()
}

/// Per-second rates from two readings of a counter `elapsed` seconds apart;
/// `None` after a reset (the counter went down).
fn rate(prev: f64, now: f64, elapsed: f64) -> Option<f64> {
    (now >= prev && elapsed > 0.0).then(|| ((now - prev) / elapsed * 10.0).round() / 10.0)
}

async fn fetch_metrics(session: &Session, key: &str) -> Option<String> {
    let replies = session
        .get(key)
        .timeout(Duration::from_secs(2))
        .await
        .ok()?;
    let reply = replies.recv_async().await.ok()?;
    let raw = reply.result().ok()?.payload().to_bytes();
    if raw.starts_with(&[0x1f, 0x8b]) {
        use std::io::Read;
        let mut text = String::new();
        flate2::read::GzDecoder::new(&raw[..])
            .read_to_string(&mut text)
            .ok()?;
        return Some(text);
    }
    Some(String::from_utf8_lossy(&raw).into_owned())
}

/// CPU time (user + system) of this process, in seconds.
fn cpu_seconds() -> Option<f64> {
    #[cfg(unix)]
    {
        use nix::sys::resource::{getrusage, UsageWho};
        let u = getrusage(UsageWho::RUSAGE_SELF).ok()?;
        let s = |t: nix::sys::time::TimeVal| t.tv_sec() as f64 + t.tv_usec() as f64 / 1e6;
        Some(s(u.user_time()) + s(u.system_time()))
    }
    #[cfg(not(unix))]
    None
}

/// Resident memory of this process in MiB: current on Linux, the peak
/// elsewhere (see [`MEMORY_DISPLAY`]).
fn memory_mib() -> Option<f64> {
    #[cfg(target_os = "linux")]
    {
        let s = std::fs::read_to_string("/proc/self/status").ok()?;
        let kb: f64 = s
            .lines()
            .find_map(|l| l.strip_prefix("VmRSS:"))?
            .trim()
            .trim_end_matches("kB")
            .trim()
            .parse()
            .ok()?;
        Some(kb / 1024.0)
    }
    #[cfg(all(unix, not(target_os = "linux")))]
    {
        use nix::sys::resource::{getrusage, UsageWho};
        let max = getrusage(UsageWho::RUSAGE_SELF).ok()?.max_rss() as f64;
        // bytes on macOS, KiB on the BSDs
        Some(if cfg!(target_os = "macos") {
            max / 1048576.0
        } else {
            max / 1024.0
        })
    }
    #[cfg(not(unix))]
    None
}

/// Free space on the file system of `dir`, MiB.
fn disk_free_mib(dir: &std::path::Path) -> Option<f64> {
    #[cfg(unix)]
    {
        let v = nix::sys::statvfs::statvfs(dir).ok()?;
        Some(v.blocks_available() as f64 * v.fragment_size() as f64 / 1048576.0)
    }
    #[cfg(not(unix))]
    {
        let _ = dir;
        None
    }
}

/// Bytes of the regular files under `dir` (symlinks not followed).
fn dir_bytes(dir: &std::path::Path) -> u64 {
    let mut total = 0;
    let mut stack = vec![dir.to_owned()];
    while let Some(d) = stack.pop() {
        let Ok(rd) = std::fs::read_dir(&d) else {
            continue;
        };
        for e in rd.flatten() {
            match e.file_type() {
                Ok(t) if t.is_dir() => stack.push(e.path()),
                Ok(t) if t.is_file() => total += e.metadata().map(|m| m.len()).unwrap_or(0),
                _ => {}
            }
        }
    }
    total
}

/// Sites whose broker liveliness token (`wy/<site>/sys/broker`) is present,
/// and the link ids whose token (`wy/<site>/down/<id>`) is present.
async fn live_tokens(session: &Session, site: &str) -> (HashSet<String>, HashSet<String>) {
    let get = |key: String| async move {
        let mut out = Vec::new();
        if let Ok(r) = session
            .liveliness()
            .get(&key)
            .timeout(Duration::from_secs(2))
            .await
        {
            while let Ok(x) = r.recv_async().await {
                if let Ok(s) = x.result() {
                    out.push(s.key_expr().as_str().to_owned());
                }
            }
        }
        out
    };
    let brokers = get("wy/*/sys/broker".into())
        .await
        .into_iter()
        .filter_map(|k| k.split('/').nth(1).map(str::to_owned))
        .collect();
    let links = get(format!("wy/{site}/down/*"))
        .await
        .into_iter()
        .filter_map(|k| k.rsplit('/').next().map(str::to_owned))
        .collect();
    (brokers, links)
}

/// Router metrics into `sys`. Only `@/<zid>/router/metrics` is read: in
/// Zenoh 1.10.1 the admin-space handlers for `subscriber/**`, `queryable/**`
/// and the like reply while holding the routing tables' read lock, and a
/// declaration waiting for the write lock meanwhile deadlocks the router
/// (seen in `two_brokers_isolation`). The `resources_declared` gauge is never
/// updated in 1.10.1 either, so DSA's "Active Subscriptions" is not shown.
async fn watch_metrics(ctl: Arc<Control>, ctx: LinkCtx) {
    let session = ctx.client().clone();
    let key = format!("@/{}/router/metrics", session.zid());
    let mut last = 0u64;
    let mut prev: Option<(std::time::Instant, Vec<f64>)> = None;
    let mut cpu_prev: Option<(std::time::Instant, f64)> = None;
    let mut data_size_at: Option<std::time::Instant> = None;
    let mut tick = tokio::time::interval(ctl.cfg.metrics_interval);
    loop {
        tick.tick().await;
        if ctx.is_closed() {
            return;
        }
        let set = |key: &'static str, v: f64| {
            let ctx = ctx.clone();
            async move {
                let v = if v.fract() == 0.0 && v >= 0.0 {
                    Value::UInt(v as u64)
                } else {
                    Value::Float((v * 10.0).round() / 10.0)
                };
                let _ = ctx.update(key, v, Quality::Good, now_us()).await;
            }
        };
        let reg = ctl.registry();
        let (brokers, live) = live_tokens(&session, &ctl.cfg.site).await;
        let peers = ctl.peers();
        let count = |sites: &[String]| sites.iter().filter(|s| brokers.contains(*s)).count();
        set("uptime", now_s().saturating_sub(ctl.started) as f64).await;
        set("links_total", reg.links.len() as f64).await;
        set(
            "links_connected",
            reg.links.keys().filter(|id| live.contains(*id)).count() as f64,
        )
        .await;
        set("quarantined", reg.quarantine.len() as f64).await;
        set("packages", reg.packages.len() as f64).await;
        set("upstream_connected", count(&peers.upstream) as f64).await;
        set("downstream_connected", count(&peers.downstream) as f64).await;
        let audit = ctl.audit.lock().unwrap_or_else(|p| p.into_inner()).lsn();
        set("audit_records", audit as f64).await;
        let now = std::time::Instant::now();
        if let Some(c) = cpu_seconds() {
            if let Some((then, before)) = cpu_prev {
                let wall = now.duration_since(then).as_secs_f64();
                if wall > 0.0 {
                    set("cpu", ((c - before) / wall * 100.0).max(0.0)).await;
                }
            }
            cpu_prev = Some((now, c));
        }
        if let Some(m) = memory_mib() {
            set("memory", m).await;
        }
        if let Some(f) = disk_free_mib(&ctl.cfg.data_dir) {
            set("disk_free", f.floor()).await;
        }
        if data_size_at.is_none_or(|t| now.duration_since(t) >= Duration::from_secs(60)) {
            data_size_at = Some(now);
            let dir = ctl.cfg.data_dir.clone();
            if let Ok(b) = tokio::task::spawn_blocking(move || dir_bytes(&dir)).await {
                set("data_size", (b as f64 / 1048576.0 * 10.0).round() / 10.0).await;
            }
        }
        let Some(text) = fetch_metrics(&session, &key).await else {
            continue;
        };
        set("sessions", counter(&text, "zenoh_transports_opened")).await;
        let counters: Vec<f64> = SYS_RATES
            .iter()
            .map(|(_, _, _, name)| counter(&text, name))
            .collect();
        if let Some((then, old)) = &prev {
            let secs = now.duration_since(*then).as_secs_f64();
            for ((path, ..), (o, c)) in SYS_RATES.iter().zip(old.iter().zip(&counters)) {
                if let Some(r) = rate(*o, *c, secs) {
                    let _ = ctx
                        .update(path, Value::Float(r), Quality::Good, now_us())
                        .await;
                }
            }
        }
        prev = Some((now, counters));
        let total = acl_denied(&text);
        let _ = ctx
            .update(ACL_DENIED, Value::UInt(total), Quality::Good, now_us())
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
    use std::collections::HashSet;

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

    #[test]
    fn counters_and_rates() {
        let m = r#"# TYPE zenoh_rx_bytes_total counter
zenoh_rx_bytes_total{protocol="tcp"} 100
zenoh_rx_bytes_total{protocol="tls"} 50
zenoh_rx_per_link_bytes_total{protocol="tcp"} 999
zenoh_rx_bytes_total_extra 7
"#;
        assert_eq!(super::counter(m, "zenoh_rx_bytes_total"), 150.0);
        assert_eq!(super::counter(m, "zenoh_tx_bytes_total"), 0.0);
        assert_eq!(super::rate(100.0, 150.0, 10.0), Some(5.0));
        assert_eq!(super::rate(100.0, 101.0, 3.0), Some(0.3));
        assert_eq!(super::rate(150.0, 20.0, 10.0), None, "reset");
    }

    #[test]
    fn admissible_cns() {
        use crate::registry::{LinkDef, Mode, Op, Origin, Registry};
        use wyrm_state::State;
        let mut reg = Registry::default();
        let def = |id: &str| LinkDef {
            id: id.into(),
            driver: "x".into(),
            mode: Mode::External,
            params: vec![0xa0],
            token_hash: "h".into(),
            rev: 1,
            origin: Origin::Runtime,
            created: 0,
            display: None,
            granted: None,
            log_level: None,
            grants: Vec::new(),
        };
        for op in [
            Op::Install(def("known")),
            Op::Install(def("gone")),
            Op::Remove("gone".into()),
            Op::Quarantine {
                cn: "bad".into(),
                seen: 0,
            },
            Op::Reject("bad".into()),
        ] {
            reg.apply(&op).unwrap();
        }
        let ops = vec!["tool".to_string()];
        let peers = crate::acl::Peers {
            upstream: vec!["cloud".into()],
            downstream: vec!["plant-b".into()],
        };
        let ok = |cn| super::admissible(&reg, &ops, &peers, cn);
        assert!(ok("new-device"));
        for cn in [
            "known",
            "gone",
            "bad",
            "tool",
            "plant-b",
            "broker",
            "broker:cloud",
            "a/b",
            "",
        ] {
            assert!(!ok(cn), "{cn:?} is not admissible");
        }
    }

    #[test]
    fn json5_peers_shadow_runtime_ones() {
        use crate::registry::{PeerDef, PeerDir};
        let def = |site: &str, dir| PeerDef {
            site: site.into(),
            dir,
            endpoint: if dir == PeerDir::Upstream {
                "quic/x:1".into()
            } else {
                String::new()
            },
            ca_pem: String::new(),
            enabled: true,
            created: 0,
        };
        let config = crate::acl::Peers {
            upstream: vec!["cloud".into()],
            downstream: vec!["edge".into()],
        };
        let runtime = vec![
            def("cloud", PeerDir::Upstream),
            def("edge", PeerDir::Upstream),
            def("plant", PeerDir::Downstream),
        ];
        let kept = super::unshadowed(&config, runtime.into_iter());
        assert_eq!(kept.len(), 1);
        assert_eq!(kept[0].site, "plant");
        // the merged list then yields unique ACL ids (Zenoh refuses repeats)
        let merged = crate::acl::Peers {
            upstream: config.upstream.clone(),
            downstream: vec!["edge".into(), "plant".into()],
        };
        let acl = crate::acl::access_control_with_peers(
            "central",
            &crate::registry::Registry::default(),
            &[],
            false,
            &merged,
        );
        for list in ["rules", "subjects", "policies"] {
            let ids: Vec<&str> = acl[list]
                .as_array()
                .unwrap()
                .iter()
                .filter_map(|x| x["id"].as_str())
                .collect();
            let unique: HashSet<&str> = ids.iter().copied().collect();
            assert_eq!(ids.len(), unique.len(), "{list} ids repeat");
        }
    }

    #[test]
    fn iso_dates() {
        assert_eq!(super::iso_utc(0), "1970-01-01T00:00:00Z");
        assert_eq!(super::iso_utc(951_782_400), "2000-02-29T00:00:00Z");
        assert_eq!(super::iso_utc(1_792_640_580), "2026-10-22T03:43:00Z");
    }
}
