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
    TokenDef, OPTION_NAMES,
};
use crate::secret::{self, CertFiles, Error, Pki};
use crate::supervisor::{ProcSpec, ProcState, Supervisor};
use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};
use std::future::Future;
use std::path::{Path, PathBuf};
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

mod signers;

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
    /// Hot start (ADR 0023): swap the new component of `wasm` package `name`
    /// (already in the component store) into its running app links without
    /// a stop and start; returns the ids of the links it swapped. A host
    /// without app links, or a package that is not an app, swaps none.
    fn reload_package(&self, _name: &str) -> BoxFut<'static, Result<Vec<String>, LinkError>> {
        Box::pin(async { Ok(Vec::new()) })
    }
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
    /// The embedded scheduler runs ([`SCHEDULER_LINK`], ADR 0022): its keys
    /// are made at attach and every link trusts its requester key.
    pub scheduler: bool,
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

/// Link id of the flow engine (rooted at `wy/<site>/dataflows`); reserved.
pub const FLOWS_LINK: &str = "dataflows";
/// Link id of the broker storage (rooted at `wy/<site>/storage`, ADR 0017).
pub const STORAGE_LINK: &str = "storage";
/// Link id of the embedded scheduler (`wy/<site>/downstream/scheduler`, ADR 0022): not a
/// registry link; it signs its writes with its own requester key, trusted by every link.
pub const SCHEDULER_LINK: &str = "scheduler";
/// `sys/overlays/.sites`: overlays of downstream sites' points this site
/// records, by full key, laid on by the gateway (ADR 0020). Never a link
/// id: those may not start with `.`.
pub const SITES_OVERLAY: &str = ".sites";

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
const SYS_INFO: [&str; 4] = ["version", "zenoh_version", "start_time", "distribution"];

/// Router counters shown as rates: key, display name, unit, counter.
const SYS_RATES: [(&str, &str, &str); 6] = [
    (
        "messages_in_per_second",
        "msg/s",
        "zenoh_rx_network_message_total",
    ),
    (
        "messages_out_per_second",
        "msg/s",
        "zenoh_tx_network_message_total",
    ),
    (
        "frames_in_per_second",
        "frame/s",
        "zenoh_rx_transport_message_total",
    ),
    (
        "frames_out_per_second",
        "frame/s",
        "zenoh_tx_transport_message_total",
    ),
    ("data_in_per_second", "B/s", "zenoh_rx_bytes_total"),
    ("data_out_per_second", "B/s", "zenoh_tx_bytes_total"),
];

const RATES_NOTE: &str = "Average over the metrics interval of this router's network \
    sessions (TCP, TLS, QUIC); embedded links talk in-process and are not counted.";

/// Messages the router's access control dropped (`sys/acl_denied`).
const ACL_DENIED: &str = "acl_denied";

/// Broker status values of `sys`, measured every metrics interval: key,
/// display name, unit, description.
const SYS_STATUS: [(&str, &str, &str); 14] = [
    ("uptime", "s", "Seconds since the broker process started."),
    ("links_total", "", "Installed links."),
    (
        "links_connected",
        "",
        "Links whose liveliness token is present (they serve their tree).",
    ),
    (
        "quarantined",
        "",
        "Unknown certificates waiting in quarantine.",
    ),
    ("packages_total", "", "Installed link packages."),
    (
        "sessions",
        "",
        "Network sessions of the router: links, peer brokers, the gateway's users go \
         through one in-process session and are not counted.",
    ),
    (
        "upstream_connected",
        "",
        "Upstream brokers that are connected.",
    ),
    (
        "downstream_connected",
        "",
        "Downstream brokers that are connected.",
    ),
    (
        ACL_DENIED,
        "",
        "Messages the router's access control dropped since the router started.",
    ),
    (
        "cpu",
        "%",
        "CPU time of the broker process over the metrics interval; 100 = one core.",
    ),
    (
        "memory",
        "MiB",
        "Resident memory of the broker process (peak on systems without /proc).",
    ),
    (
        "disk_free",
        "MiB",
        "Free space on the file system of data_dir.",
    ),
    (
        "data_size",
        "MiB",
        "Size of data_dir, measured every minute.",
    ),
    ("audit_records", "", "Records in the audit journal."),
];

/// Display name and description of the [`Options`] values.
const OPTION_INFO: [&str; 2] = [
    "Install every unknown certificate CN signed by this broker's CA as an \
         external link, without quarantine. The link token stays in the broker's \
         data_dir (links/<id>/token) for the operator to copy to the device.",
    "Record unknown certificate CNs under quarantine for approval; off: ignore them.",
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
    /// The embedded historian (`sys/history`, ADR 0014); outlives rebuilds.
    pub(crate) history: Arc<wyrm_history::Historian>,
    /// Wakes [`enroll_upstreams`] for a new or re-enabled upstream site.
    enroll_wake: tokio::sync::Notify,
    /// Polls of waiting enrollment requests, by site (not persisted).
    enroll_seen: Mutex<HashMap<String, EnrollSeen>>,
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

/// Router-to-router setup from `wyrmd.json5` (iteration 4, ADR 0015): peer
/// sites and how to reach each upstream site. Peers added at runtime live in
/// the registry.
#[derive(Debug, Clone, Default)]
pub struct PeerConfig {
    pub peers: acl::Peers,
    pub upstream: Vec<UpstreamConf>,
    /// `peers.listen` is set: downstream sites can connect.
    pub listen: bool,
    /// Its port: a link whose local end has it came in on that listener.
    pub listen_port: Option<u16>,
    /// `peers.enroll` is set: the enrollment listener without client
    /// certificates is open (ADR 0015).
    pub enroll: bool,
}

/// How to reach one upstream site: its QUIC endpoint, its CA, and the
/// certificate it issued for this broker (`broker:<site>`) with its key.
#[derive(Debug, Clone)]
pub struct UpstreamConf {
    pub site: String,
    pub endpoint: String,
    pub ca: PathBuf,
    pub cert: PathBuf,
    pub key: PathBuf,
    /// Its users may run `config` actions on our `sys` (ADR 0018).
    pub allow_config: bool,
}

/// Largest accepted CA certificate (PEM).
const MAX_CA_PEM: usize = 16 * 1024;

/// The certificate `pki` issues for downstream site `site` (ADR 0015):
/// `<data_dir>/peers/<site>/broker.{pem,key}`, kept once issued.
pub fn broker_cert_in(pki: &Pki, data_dir: &Path, site: &str) -> Result<CertFiles, Error> {
    let dir = data_dir.join("peers").join(site);
    pki.issue(
        &crate::registry::broker_cn(site),
        &[],
        false,
        &dir,
        "broker",
    )
}

/// The secret-store entry of a runtime upstream site: our private key for
/// the certificate it issued (never a link id: those have no `:`).
fn peer_secret(site: &str) -> String {
    format!("peer:{site}")
}

const PEER_KEY: &str = "key";
/// The token for an upstream site's enrollment, until it is used.
const PEER_TOKEN: &str = "token";

/// While an enrollment waits for Authorize, ask again this often.
const ENROLL_RETRY: Duration = Duration::from_secs(10);
/// After a refusal, this often; an unreachable endpoint doubles from 2 s
/// up to this.
const ENROLL_BACKOFF: Duration = Duration::from_secs(60);

/// A waiting request leaves quarantine when its broker has not asked again
/// for this long (it asks every 10 s): junk names cannot fill the 64 places.
const ENROLL_STALE_S: u64 = 600;

/// What polls of a waiting enrollment request look like, kept in memory so
/// that a broker asking every 10 s writes nothing: `(last seen, attempts,
/// requests with another key)`.
#[derive(Debug, Clone, Copy, Default)]
struct EnrollSeen {
    last: u64,
    attempts: u64,
    conflicts: u64,
}

/// One poll at `now`: the waiting key's poll keeps the request alive; one
/// with another key only counts.
fn touch_seen(
    seen: &mut HashMap<String, EnrollSeen>,
    site: &str,
    now: u64,
    conflict: bool,
) -> EnrollSeen {
    let s = seen.entry(site.to_owned()).or_insert(EnrollSeen {
        last: now,
        ..Default::default()
    });
    if conflict {
        s.conflicts += 1;
    } else {
        s.last = now;
        s.attempts += 1;
    }
    *s
}

/// Sites whose request waits (not held) and was not asked again for `ttl`
/// seconds; a site without a record since this broker started counts from
/// `now` (it gets the whole time).
fn stale_enrollments(
    reg: &Registry,
    seen: &mut HashMap<String, EnrollSeen>,
    now: u64,
    ttl: u64,
) -> Vec<String> {
    reg.enrollments
        .keys()
        .filter(|site| !reg.held.contains(&crate::registry::broker_cn(site)))
        .filter(|site| {
            let s = seen.entry((*site).clone()).or_insert(EnrollSeen {
                last: now,
                ..Default::default()
            });
            now.saturating_sub(s.last) > ttl
        })
        .cloned()
        .collect()
}

/// What an upstream site answered an enrollment request.
enum Answer {
    Issued { cert: String, port: u16 },
    Pending,
    Refused(String),
}

/// SHA-256 (hex) of an admission token; the registry keeps only this.
fn token_sha256(token: &str) -> String {
    use sha2::{Digest, Sha256};
    hex::encode(Sha256::digest(token.as_bytes()))
}

/// `via` given as a list or as `a, b` text.
fn via_list(v: Option<&Value>) -> Vec<String> {
    let mut out: Vec<String> = match v {
        Some(Value::Array(a)) => a
            .iter()
            .filter_map(|x| match x {
                Value::Str(s) => Some(s.trim().to_owned()),
                _ => None,
            })
            .collect(),
        Some(Value::Str(s)) => s.split([',', ' ']).map(|x| x.trim().to_owned()).collect(),
        _ => Vec::new(),
    };
    out.retain(|s| !s.is_empty());
    out
}

/// The host of `quic/<host>:<port>` (`[v6]` kept).
fn host_of(endpoint: &str) -> Option<&str> {
    let addr = endpoint.strip_prefix("quic/")?;
    Some(addr.rsplit_once(':')?.0)
}

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

/// The certificate an upstream site sent: for `broker:<own site>` and for
/// our key (SHA-256 of its public key).
fn check_issued_cert(pem: &str, own: &str, key_sha256: &str) -> Result<(), String> {
    use sha2::{Digest, Sha256};
    let (_, block) = x509_parser::pem::parse_x509_pem(pem.trim().as_bytes())
        .map_err(|e| format!("bad answer: certificate: {e}"))?;
    let cert = block
        .parse_x509()
        .map_err(|e| format!("bad answer: certificate: {e}"))?;
    let want = crate::registry::broker_cn(own);
    let cn = cert
        .subject()
        .iter_common_name()
        .next()
        .and_then(|a| a.as_str().ok());
    if cn != Some(want.as_str()) {
        return Err(format!("bad answer: certificate for {}", cn.unwrap_or("?")));
    }
    if hex::encode(Sha256::digest(cert.public_key().raw)) != key_sha256 {
        return Err("bad answer: certificate for another key".into());
    }
    Ok(())
}

/// `<CN>, valid until <date>` of a PEM certificate, for people.
fn cert_summary(pem: &str) -> String {
    let parsed = x509_parser::pem::parse_x509_pem(pem.trim().as_bytes()).ok();
    let Some(cert) = parsed.as_ref().and_then(|(_, b)| b.parse_x509().ok()) else {
        return "unreadable".into();
    };
    let cn = cert
        .subject()
        .iter_common_name()
        .next()
        .and_then(|a| a.as_str().ok())
        .unwrap_or("?");
    format!(
        "{cn}, valid until {}",
        cert.validity().not_after.to_datetime().date()
    )
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

pub(crate) fn rejected(e: StateError) -> LinkError {
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
        let history = wyrm_history::Historian::open(&cfg.data_dir.join("history"))
            .map_err(|e| e.to_string())?;
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
                history,
                enroll_wake: tokio::sync::Notify::new(),
                enroll_seen: Mutex::default(),
            }),
            rx,
        ))
    }

    /// One more poll of the waiting request of `site` (in memory; only for
    /// a name that waits). A request with another key counts as a conflict
    /// and keeps nothing alive: it does not touch `last`.
    fn enroll_touch(&self, site: &str, conflict: bool) -> EnrollSeen {
        let mut seen = self.enroll_seen.lock().unwrap_or_else(|p| p.into_inner());
        touch_seen(&mut seen, site, now_s(), conflict)
    }

    /// Forget the polls of `site` (admitted, rejected, expired).
    fn enroll_forget(&self, site: &str) {
        self.enroll_seen
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .remove(site);
    }

    fn enroll_seen_of(&self, site: &str) -> Option<EnrollSeen> {
        self.enroll_seen
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .get(site)
            .copied()
    }

    /// The id of a valid admission token (known, not used up, not expired):
    /// `<id>.<secret>`, compared by SHA-256.
    fn token_id(&self, token: &str) -> Option<String> {
        let (id, _) = token.split_once('.')?;
        let reg = self.registry();
        let def = reg.tokens.get(id)?;
        let fresh = def.expires == 0 || now_s() < def.expires;
        (fresh && def.sha256 == token_sha256(token)).then(|| id.to_owned())
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

    pub(crate) fn apply(&self, op: Op) -> Result<(), StateError> {
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
        limited.extend(self.scheduler_limited_key());
        limited.extend(self.upstream_trust("downstream"));
        (self.cfg.admin_keys.clone(), limited)
    }

    /// The embedded scheduler's requester key: `write` on this site's
    /// `downstream` only, bound to the subject `link:scheduler` (ADR 0022).
    fn scheduler_limited_key(&self) -> Option<wyrm_link_sdk::LimitedKey> {
        if !self.cfg.scheduler {
            return None;
        }
        Some(wyrm_link_sdk::LimitedKey {
            key: self.requester_key_of(SCHEDULER_LINK)?,
            cap: Perm::Write,
            scopes: vec![format!("wy/{}/downstream", self.cfg.site)],
            subject: Some(format!("link:{SCHEDULER_LINK}")),
        })
    }

    /// The link config of a link the broker runs in-process (an embedded
    /// registry link or a built-in one): the links' trust, its secrets,
    /// its private `data_dir` and `grants`.
    pub fn embedded_link_config(
        &self,
        id: &str,
        grants: Vec<(String, Perm)>,
    ) -> Result<LinkConfig, LinkError> {
        let mut lcfg = LinkConfig::new(self.cfg.site.clone(), id);
        let (admin_keys, limited_keys) = self.link_trust();
        lcfg.admin_keys = admin_keys;
        lcfg.limited_keys = limited_keys;
        lcfg.secrets = self.link_secrets(id);
        lcfg.data_dir = Some(self.link_data_dir(id)?);
        lcfg.grants = grants;
        Ok(lcfg)
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

    /// The grants of a link for the link itself: `(path, permission)`, the
    /// `{site}` placeholder expanded. Grants with an unknown code are left
    /// out, as in the router ACL.
    pub fn link_grants(&self, def: &LinkDef) -> Vec<(String, Perm)> {
        def.grants
            .iter()
            .filter_map(|(path, code)| {
                Some((
                    path.replace("{site}", &self.cfg.site),
                    Perm::try_from(*code).ok()?,
                ))
            })
            .collect()
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
        if def.grants.is_empty() {
            return Ok(());
        }
        self.ensure_requester_seed(&def.id)
    }

    /// The requester key secret of `id`, created once.
    fn ensure_requester_seed(&self, id: &str) -> Result<(), Error> {
        let name = wyrm_link_sdk::REQUESTER_KEY;
        if self.secrets.names(id).iter().any(|n| n == name) {
            return Ok(());
        }
        let mut seed = zeroize::Zeroizing::new([0u8; 32]);
        getrandom::fill(&mut seed[..]).map_err(|e| format!("no randomness: {e}"))?;
        self.secrets.set(id, name, &seed[..])?;
        info!(link = %id, "requester key created");
        Ok(())
    }

    /// A built-in link (not in the registry, [`SCHEDULER_LINK`]) gets its
    /// requester key and store key as link secrets, each created once.
    fn ensure_builtin_keys(&self, id: &str) -> Result<(), Error> {
        self.ensure_requester_seed(id)?;
        self.ensure_store_key(id)
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

    /// History watches stored with a tree route (`wy/central/downstream/edge/
    /// downstream/…`, pasted before routes resolved) get the key of the site
    /// the route ends in. At start, after the peers are known. Returns how
    /// many changed.
    pub fn resolve_watch_routes(&self) -> usize {
        let below = self.peers().reachable();
        let reg = self.registry();
        let mut n = 0;
        for (group, g) in &reg.historian.groups {
            for (id, w) in &g.watches {
                let key = wyrm_core::keyspace::route_key(&w.key, |s| below.iter().any(|d| d == s));
                if key == w.key {
                    continue;
                }
                match self.apply(Op::SetWatchKey {
                    group: group.clone(),
                    id: id.clone(),
                    key: key.clone(),
                }) {
                    Ok(()) => {
                        self.record(
                            "system",
                            "watch_key",
                            &format!("{group}/{id}"),
                            Status::Ok,
                            &key,
                        );
                        info!(watch = %format!("{group}/{id}"), %key, "a watched route is now its key");
                        n += 1;
                    }
                    Err(e) => warn!(watch = %format!("{group}/{id}"), "route {}: {e}", w.key),
                }
            }
        }
        n
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
        let cfg = self.config_peers();
        let mut p = cfg.peers;
        p.enroll = cfg.enroll;
        for d in &self.runtime_peers() {
            match d.dir {
                PeerDir::Upstream if d.enabled => {
                    p.upstream.push(d.site.clone());
                    if d.allow_config {
                        p.config_from.push(d.site.clone());
                    }
                }
                PeerDir::Upstream => {}
                PeerDir::Downstream => {
                    p.downstream.push(d.site.clone());
                    if !d.via.is_empty() {
                        p.via.insert(d.site.clone(), d.via.clone());
                    }
                }
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

    /// Files of a runtime upstream site (written from the registry and the
    /// secret store at each broker build): `<site>.pem` its CA,
    /// `<site>.cert.pem` and `<site>.key` our certificate from it.
    fn peer_file(&self, site: &str, ext: &str) -> PathBuf {
        self.cfg
            .data_dir
            .join("pki")
            .join("peers")
            .join(format!("{site}.{ext}"))
    }

    fn peer_ca_path(&self, site: &str) -> PathBuf {
        self.peer_file(site, "pem")
    }

    /// The certificate this broker issued for downstream site `site`
    /// (`broker:<site>`, ADR 0015), issued on first use, under
    /// `data_dir/peers/<site>/broker.{pem,key}` for the operator to copy.
    pub fn broker_cert(&self, site: &str) -> Result<CertFiles, Error> {
        broker_cert_in(&self.pki, &self.cfg.data_dir, site)
    }

    /// Issue `broker:<d>` for every downstream site (kept once issued) and
    /// record the names (ADR 0015): at open, so the files exist before the
    /// downstream starts, and at each broker build.
    pub fn issue_broker_certs(&self) -> Result<(), Error> {
        for site in &self.peers().downstream {
            if !self.registry().issued_brokers.contains(site) {
                self.apply(Op::IssueBroker(site.clone()))
                    .map_err(|e| e.to_string())?;
            }
            self.broker_cert(site)?;
        }
        Ok(())
    }

    /// Every upstream site to connect to: `wyrmd.json5` and enabled runtime
    /// ones.
    pub fn upstream_endpoints(&self) -> Vec<UpstreamConf> {
        let mut out = self.config_peers().upstream;
        for d in &self.runtime_peers() {
            if d.dir == PeerDir::Upstream && d.enabled {
                // added before ADR 0015: no certificate from that site
                if d.cert_pem.is_empty()
                    || !self
                        .secrets
                        .names(&peer_secret(&d.site))
                        .iter()
                        .any(|n| n == PEER_KEY)
                {
                    warn!(site = %d.site, "upstream without our certificate from it: not connected; add it again");
                    continue;
                }
                out.push(UpstreamConf {
                    site: d.site.clone(),
                    endpoint: d.endpoint.clone(),
                    ca: self.peer_ca_path(&d.site),
                    cert: self.peer_file(&d.site, "cert.pem"),
                    key: self.peer_file(&d.site, "key"),
                    allow_config: d.allow_config,
                });
            }
        }
        out
    }

    /// The router needs broker certificates for peer links (and for the
    /// QUIC listener, open whenever `peers.listen` is set).
    pub fn has_peers(&self) -> bool {
        let p = self.peers();
        !p.upstream.is_empty() || !p.downstream.is_empty() || self.config_peers().listen
    }

    pub fn configure_zenoh(&self, c: &mut zenoh::Config, tls: bool) -> Result<(), Error> {
        for d in &self.runtime_peers() {
            if d.dir != PeerDir::Upstream {
                continue;
            }
            let path = self.peer_ca_path(&d.site);
            std::fs::create_dir_all(path.parent().unwrap_or(&self.cfg.data_dir))?;
            std::fs::write(&path, &d.ca_pem)?;
            std::fs::write(self.peer_file(&d.site, "cert.pem"), &d.cert_pem)?;
            let key = self.secrets.for_link(&peer_secret(&d.site));
            if let Some(k) = key.get(PEER_KEY) {
                secret::write_private(&self.peer_file(&d.site, "key"), k)?;
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
            // Every listener, the QUIC broker listener too, trusts our own CA
            // alone (ADR 0015): downstream brokers hold certificates from it.
            let _ = std::fs::remove_file(pki_dir.join("peer-trust.pem"));
            self.issue_broker_certs()?;
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

    /// Reference nodes of the peer brokers: one link `downstream/<d>` per
    /// downstream site, one link `upstream` with a node per upstream site.
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
                    format!("wy/{site}/downstream/{d}"),
                    vec![(String::new(), d.clone())],
                )
            })
            .collect();
        // `upstream` always, empty without upstream sites: a client opening a
        // site finds its four sections (down, flows, sys, up).
        let nodes = peers
            .upstream
            .iter()
            .map(|u| (u.clone(), u.clone()))
            .collect();
        plan.push(("upstream".into(), format!("wy/{site}/upstream"), nodes));
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
        // The scheduler's key before the admin answers any `hello`: a process
        // link trusts only the keys its `hello` reply carried.
        if self.cfg.scheduler {
            self.ensure_builtin_keys(SCHEDULER_LINK)?;
        }
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
        // upstream sites with `allow_config` (ADR 0018)
        lcfg.limited_keys = self.upstream_trust("sys");
        lcfg.open_actions = vec!["hello".into(), "enroll".into()];
        // the admin publishes overlays; it lays none over itself
        lcfg.overlays = false;
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
        // `~val?history=` of this site's points; a downstream site's broker
        // answers for its own.
        let site = &self.cfg.site;
        self.history.attach(
            session.clone(),
            crate::history::groups(&self.registry()),
            vec![
                format!("wy/{site}/downstream/**/~val"),
                format!("wy/{site}/dataflows/**/~val"),
                format!("wy/{site}/storage/**/~val"),
            ],
            // a downstream site's point is read at its watch (ADR 0020)
            Some(format!("wy/{site}/sys/history")),
        );
        let tasks = vec![
            tokio::spawn(crate::history::watch(self.clone(), ctx.clone())),
            tokio::spawn(watch_states(self.clone(), ctx.clone(), embedded.clone())),
            tokio::spawn(watch_quarantine(self.clone(), ctx.clone())),
            tokio::spawn(watch_metrics(self.clone(), ctx.clone())),
            tokio::spawn(watch_audit(self.clone(), ctx.clone())),
            tokio::spawn(serve_profiles(self.clone(), session.clone())),
            tokio::spawn(load_repository(self.clone(), ctx.clone())),
            tokio::spawn(enroll_upstreams(self.clone(), ctx.clone())),
            tokio::spawn(expire_enrollments(self.clone(), ctx.clone())),
            tokio::spawn(signers::follow_signers(self.clone(), ctx.clone())),
            tokio::spawn(signers::serve_signing_keys(self.clone(), session.clone())),
        ];
        info!(site = %self.cfg.site, "admin attached");
        let peers = self.start_peers(&session).await;
        Ok(Attached {
            admin: Some(admin),
            peers,
            embedded,
            tasks,
            history: self.history.clone(),
        })
    }
}

type Running = Arc<AsyncMutex<HashMap<String, Box<dyn RunningLink>>>>;

/// Admin state bound to one broker instance.
pub struct Attached {
    admin: Option<LinkHandle<Admin>>,
    /// `downstream/<d>` and `upstream` reference nodes of peer brokers.
    peers: Vec<LinkHandle<crate::peers::PeerRefs>>,
    embedded: Running,
    tasks: Vec<JoinHandle<()>>,
    history: Arc<wyrm_history::Historian>,
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
        // Buffered history rows go to disk before the session closes.
        self.history.detach().await;
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
    let lcfg = ctl.embedded_link_config(&def.id, ctl.link_grants(def))?;
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
                    .placeholder("wy/{site}/downstream/<link>")
                    .description("A node of another link (its subtree), or wy/{site}/dataflows"),
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
        .param("via", via_param())
        .param(
            "key",
            str_param()
                .display("Key")
                .description("Downstream brokers: the SHA-256 of its key you compared"),
        )
        .result(ActionResult::Type(TypeCode::Map))
        .level(Perm::Config)
}

/// `quarantine/~act/authorize` and `deauthorize` (DSA): their CN, link and
/// role lists are enums, so they are declared again after each change
/// (with each quarantined node's own Authorize).
async fn refresh_quarantine(ctx: &LinkCtx, ctl: &Control) -> Result<(), LinkError> {
    let reg = ctl.registry();
    let roles = role_names(ctl);
    // Always a list, also an empty one (the UI shows `none` in it).
    let pick = |vals: Vec<String>, display: &str, none: &str| {
        str_param()
            .required(true)
            .display(display)
            .placeholder(none)
            .enum_values(vals)
    };
    let cns: Vec<String> = reg.quarantine.keys().cloned().collect();
    ctx.declare_action(
        "quarantine",
        "authorize",
        authorize_meta(Some(pick(cns, "DsId", "nothing in quarantine")), &roles),
    )
    .await?;
    // everything connected downstream that can go back: runtime external
    // links and runtime downstream brokers (as DSA's Deauthorize)
    let mut links: Vec<String> = reg
        .links
        .values()
        .filter(|d| d.mode == Mode::External && d.origin == Origin::Runtime)
        .map(|d| d.id.clone())
        .collect();
    links.extend(
        reg.peers
            .values()
            .filter(|p| p.dir == PeerDir::Downstream)
            .map(|p| p.site.clone()),
    );
    links.sort();
    ctx.declare_action(
        "quarantine",
        "deauthorize",
        ActionMeta::new()
            .display("Deauthorize")
            .param("link", pick(links, "Link", "nothing connected downstream"))
            .level(Perm::Config),
    )
    .await?;
    for (cn, e) in &reg.quarantine {
        let site = crate::registry::broker_site(cn);
        let asked = site.and_then(|s| reg.enrollments.get(s));
        // polls since this broker started (kept in memory, not written)
        let mut e = e.clone();
        let mut asked = asked.cloned();
        if let Some(seen) = site.and_then(|s| ctl.enroll_seen_of(s)) {
            e.last_seen = e.last_seen.max(seen.last);
            e.attempts = e.attempts.max(seen.attempts);
            if let Some(a) = asked.as_mut() {
                a.conflicts = a.conflicts.max(seen.conflicts);
            }
        }
        declare_quarantined(ctx, cn, &e, asked.as_ref(), &roles).await?;
    }
    Ok(())
}

/// The node of a quarantined CN: a downstream broker (`broker:<site>`) by
/// its site, a link by its CN.
fn quarantine_node(cn: &str) -> &str {
    crate::registry::broker_site(cn).unwrap_or(cn)
}

async fn declare_quarantined(
    ctx: &LinkCtx,
    cn: &str,
    e: &crate::registry::QuarantineEntry,
    asked: Option<&crate::registry::Enrollment>,
    roles: &[String],
) -> Result<(), LinkError> {
    let p = format!("quarantine/{}", quarantine_node(cn));
    let kind = if crate::registry::broker_site(cn).is_some() {
        "broker"
    } else {
        "link"
    };
    let mut m = NodeMeta::folder()
        .is("wy:quarantine")
        .attr("kind", kind)
        .attr("first_seen", e.first_seen)
        .attr("last_seen", e.last_seen)
        .attr("attempts", e.attempts);
    // what the administrators compare on both sides before Authorize
    if let Some(a) = asked {
        m = m
            .attr("key", a.key_sha256.as_str())
            .attr("via", a.via.join(", "))
            .attr("conflicts", a.conflicts);
    }
    ctx.declare_node(&p, m).await?;
    // a downstream broker needs only the sites it relays, and the key it
    // was reviewed with (one choice: a changed request needs a new look)
    let approve = if kind == "broker" {
        let mut key = str_param()
            .display("Key")
            .description("SHA-256 of its key: the same as its sys/upstream/<this site>/key");
        if let Some(k) = asked
            .map(|a| a.key_sha256.as_str())
            .filter(|k| !k.is_empty())
        {
            key = key.required(true).enum_values([k.to_owned()]);
        }
        ActionMeta::new()
            .display("Authorize")
            .param("key", key)
            .param("via", via_param())
            .level(Perm::Config)
    } else {
        authorize_meta(None, roles)
    };
    ctx.declare_action(&p, "approve", approve).await?;
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
    for (key, v) in SYS_INFO.iter().zip(info) {
        ctx.declare_node(key, NodeMeta::leaf(TypeCode::String))
            .await?;
        ctx.update(key, Value::Str(v), Quality::Good, now_us())
            .await?;
    }
    for (key, unit, about) in SYS_STATUS {
        let mut m = NodeMeta::number().attr("description", about);
        if !unit.is_empty() {
            m = m.unit(unit);
        }
        ctx.declare_node(key, m).await?;
    }
    for (key, unit, _) in SYS_RATES {
        ctx.declare_node(
            key,
            NodeMeta::number()
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
    for (name, about) in OPTION_NAMES.iter().zip(OPTION_INFO) {
        ctx.declare_node(
            name,
            NodeMeta::leaf(TypeCode::Bool)
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
                        .placeholder("wy/{site}/downstream/**"),
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

fn via_param() -> ParamMeta {
    str_param()
        .display("Via")
        .placeholder("plant, cell")
        .description(
            "Downstream brokers: sites that broker relays from further down (a chain); \
             it may serve their keys, and our upstream may read them.",
        )
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

/// `sys/upstream`: the brokers this one connects to, as DSA's
/// `/sys/upstream` (ADR 0015). Downstream brokers have no section here: they
/// add us themselves and come in through a token, `allow_all_links` or
/// quarantine. Peers from `wyrmd.json5` are shown read-only.
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
                    .placeholder("quic/central.example:7450")
                    .description("Its enrollment endpoint (peers.enroll there)"),
            )
            .param("ca", ca_param())
            .param(
                "token",
                str_param()
                    .display("Token")
                    .editor(EDITOR_PASSWORD)
                    .description("From its sys/tokens, if it gave one: admitted at once"),
            )
            .param("enabled", ParamMeta::of(TypeCode::Bool).display("Enabled"))
            .param("allow_config", allow_config_param())
            .level(Perm::Config),
    )
    .await?;
    for u in &ctl.config_peers().upstream {
        let pem = |p: &PathBuf| std::fs::read_to_string(p).unwrap_or_default();
        let shown = Upstream {
            site: &u.site,
            url: &u.endpoint,
            ca_pem: &pem(&u.ca),
            cert_pem: &pem(&u.cert),
            key_sha256: "",
            enabled: true,
            allow_config: u.allow_config,
        };
        declare_upstream(ctx, &shown, false).await?;
    }
    for d in &ctl.runtime_peers() {
        if d.dir == PeerDir::Upstream {
            declare_upstream(ctx, &Upstream::of(d), true).await?;
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

/// What `sys/upstream/<site>` shows of one upstream site.
struct Upstream<'a> {
    site: &'a str,
    /// Its enrollment endpoint (added at runtime) or its peer endpoint.
    url: &'a str,
    ca_pem: &'a str,
    cert_pem: &'a str,
    key_sha256: &'a str,
    enabled: bool,
    allow_config: bool,
}

/// `allow_config` of an upstream site (ADR 0018).
fn allow_config_param() -> ParamMeta {
    ParamMeta::of(TypeCode::Bool)
        .display("Allow Config")
        .description("Its users may run config actions here (sys), as far as their own grants go")
}

impl<'a> Upstream<'a> {
    fn of(d: &'a PeerDef) -> Self {
        Self {
            site: &d.site,
            url: if d.enroll.is_empty() {
                &d.endpoint
            } else {
                &d.enroll
            },
            ca_pem: &d.ca_pem,
            cert_pem: &d.cert_pem,
            key_sha256: &d.key_sha256,
            enabled: d.enabled,
            allow_config: d.allow_config,
        }
    }
}

/// `upstream/<site>`: the parameters it was added with (`url`, `enabled`,
/// writable when added at runtime; `ca` and `certificate` as subject and
/// expiry; `key` as the SHA-256 of our public key, never the key; never the
/// token), the enrollment `status`, and `remove`.
async fn declare_upstream(
    ctx: &LinkCtx,
    u: &Upstream<'_>,
    runtime: bool,
) -> wyrm_link_sdk::Result<()> {
    let p = format!("upstream/{}", u.site);
    ctx.declare_node(&p, NodeMeta::folder().attr("origin", origin(runtime)))
        .await?;
    let t = now_us();
    let status = match (runtime, u.cert_pem.is_empty()) {
        (false, _) => "configured in wyrmd.json5",
        (true, true) => "waiting",
        (true, false) => "issued",
    };
    let certificate = if u.cert_pem.is_empty() {
        String::new()
    } else {
        cert_summary(u.cert_pem)
    };
    for (key, v) in [
        ("url", u.url.to_owned()),
        ("ca", cert_summary(u.ca_pem)),
        ("certificate", certificate),
        ("key", u.key_sha256.to_owned()),
        ("status", status.to_owned()),
    ] {
        let k = format!("{p}/{key}");
        ctx.declare_node(&k, NodeMeta::leaf(TypeCode::String))
            .await?;
        ctx.update(&k, Value::Str(v), Quality::Good, t).await?;
    }
    let mut on = NodeMeta::leaf(TypeCode::Bool);
    if runtime {
        on = on.writable(Writable::Config);
    }
    let en = format!("{p}/enabled");
    ctx.declare_node(&en, on.clone()).await?;
    ctx.update(&en, Value::Bool(u.enabled), Quality::Good, t)
        .await?;
    // what its requests may do here (ADR 0018)
    let ac = format!("{p}/allow_config");
    ctx.declare_node(
        &ac,
        on.attr(
            "description",
            "Its users may run config actions here (sys); write on devices, flows and storage they always have",
        ),
    )
    .await?;
    ctx.update(&ac, Value::Bool(u.allow_config), Quality::Good, t)
        .await?;
    if runtime {
        declare_remove(ctx, &p).await?;
    }
    Ok(())
}

/// The broker's attributes for link nodes (ADR 0016), today only
/// `history`: for each recorded point of this site, the keys of the watch
/// nodes that record it, by link: `{<path>: {"history": [<watch key>…]}}`.
/// Derived from the registry's watches, so nothing more is stored.
pub(crate) fn overlay_maps(
    reg: &Registry,
    site: &str,
) -> BTreeMap<String, BTreeMap<String, Value>> {
    let down = format!("wy/{site}/downstream/");
    let flows = format!("wy/{site}/dataflows/");
    let storage = format!("wy/{site}/storage/");
    let own = format!("wy/{site}/");
    let mut by_link: BTreeMap<String, BTreeMap<String, Vec<Value>>> = BTreeMap::new();
    for (group, g) in &reg.historian.groups {
        for (id, w) in &g.watches {
            let (link, path) = if let Some(rest) = w.key.strip_prefix(&down) {
                match rest.split_once('/') {
                    Some((l, p)) => (l.to_owned(), p.to_owned()),
                    None => continue,
                }
            } else if let Some(rest) = w.key.strip_prefix(&flows) {
                (FLOWS_LINK.to_owned(), rest.to_owned())
            } else if let Some(rest) = w.key.strip_prefix(&storage) {
                (STORAGE_LINK.to_owned(), rest.to_owned())
            } else if !w.key.starts_with(&own) {
                // a downstream site's point: its link is another broker's,
                // so the overlay is ours, by full key (ADR 0020)
                (SITES_OVERLAY.to_owned(), w.key.clone())
            } else {
                continue;
            };
            by_link
                .entry(link)
                .or_default()
                .entry(path)
                .or_default()
                .push(Value::Str(format!("wy/{site}/sys/history/{group}/{id}")));
        }
    }
    by_link
        .into_iter()
        .map(|(link, paths)| {
            let attrs = paths
                .into_iter()
                .map(|(p, keys)| {
                    let a = BTreeMap::from([("history".to_owned(), Value::Array(keys))]);
                    (p, Value::Map(a))
                })
                .collect();
            (link, attrs)
        })
        .collect()
}

/// Publish every link's overlay map at `sys/overlays/<link>` (ADR 0016):
/// after each broker build (the memory storage starts empty) and after each
/// watch change. Links without overlays get an empty map, which clears any
/// they had.
pub(crate) async fn publish_overlays(ctx: &LinkCtx, ctl: &Control) -> wyrm_link_sdk::Result<()> {
    let reg = ctl.registry();
    let mut maps = overlay_maps(&reg, &ctl.cfg.site);
    let mut links: BTreeSet<String> = reg.links.keys().cloned().collect();
    links.insert(FLOWS_LINK.to_owned());
    links.insert(STORAGE_LINK.to_owned());
    if ctl.cfg.scheduler {
        links.insert(SCHEDULER_LINK.to_owned());
    }
    links.insert(SITES_OVERLAY.to_owned());
    links.extend(maps.keys().cloned());
    ctx.declare_node(
        "overlays",
        NodeMeta::folder().attr(
            "description",
            "Attributes the broker lays over link nodes (ADR 0016): attr.history of recorded points.",
        ),
    )
    .await?;
    let t = now_us();
    for link in links {
        let m = maps.remove(&link).unwrap_or_default();
        let k = format!("overlays/{link}");
        ctx.declare_node(&k, NodeMeta::leaf(TypeCode::Map)).await?;
        ctx.update(&k, Value::Map(m), Quality::Good, t).await?;
    }
    Ok(())
}

/// `sys/tokens` (as DSA's `/sys/tokens`, ADR 0015): Add Token, and one node
/// per token with `uses` left and `expires`; never the token itself.
async fn declare_tokens(ctx: &LinkCtx, ctl: &Control) -> wyrm_link_sdk::Result<()> {
    ctx.declare_node(
        "tokens",
        NodeMeta::folder().attr(
            "description",
            "Tokens that admit a downstream broker at once (its Add Upstream Connection).",
        ),
    )
    .await?;
    ctx.declare_action(
        "tokens",
        "add",
        ActionMeta::new()
            .display("Add Token")
            .group(GROUP_NEW)
            .param(
                "count",
                ParamMeta::of(TypeCode::Number)
                    .display("Count")
                    .placeholder("1")
                    .description("Admissions it allows; 0: no limit"),
            )
            .param(
                "hours",
                ParamMeta::of(TypeCode::Number)
                    .display("Hours")
                    .placeholder("24")
                    .description("Valid for this long; 0: never expires"),
            )
            .result(ActionResult::Type(TypeCode::Map))
            .level(Perm::Config),
    )
    .await?;
    let t = now_us();
    for (id, def) in &ctl.registry().tokens {
        let p = format!("tokens/{id}");
        ctx.declare_node(
            &p,
            NodeMeta::folder()
                .attr("created", def.created)
                .attr("by", def.by.as_str()),
        )
        .await?;
        let expires = if def.expires == 0 {
            "never".to_owned()
        } else {
            iso_utc(def.expires)
        };
        for (key, v) in [
            ("uses", Value::UInt(def.uses.into())),
            ("expires", Value::Str(expires)),
        ] {
            let k = format!("{p}/{key}");
            let m = match key {
                "uses" => NodeMeta::number().attr("description", "Admissions left; 0: no limit"),
                _ => NodeMeta::leaf(TypeCode::String),
            };
            ctx.declare_node(&k, m).await?;
            ctx.update(&k, v, Quality::Good, t).await?;
        }
        declare_remove(ctx, &p).await?;
    }
    Ok(())
}

/// Runtime upstream sites without our certificate ask for it (ADR 0015):
/// at once for a new or re-enabled one, every 10 s while it waits for
/// Authorize, every 60 s after a refusal. The status shows in
/// `sys/upstream/<site>/status`.
async fn enroll_upstreams(ctl: Arc<Control>, ctx: LinkCtx) {
    let mut next: HashMap<String, std::time::Instant> = HashMap::new();
    let mut failures: HashMap<String, u32> = HashMap::new();
    loop {
        let waiting: Vec<PeerDef> = ctl
            .registry()
            .peers
            .into_values()
            .filter(|p| {
                p.dir == PeerDir::Upstream
                    && p.enabled
                    && p.cert_pem.is_empty()
                    && !p.enroll.is_empty()
            })
            .collect();
        next.retain(|site, _| waiting.iter().any(|p| &p.site == site));
        failures.retain(|site, _| waiting.iter().any(|p| &p.site == site));
        for def in waiting {
            let now = std::time::Instant::now();
            if next.get(&def.site).is_some_and(|t| *t > now) {
                continue;
            }
            let answer = ask_certificate(&ctl, &def).await;
            if answer.is_ok() {
                failures.remove(&def.site);
            }
            let (status, wait) = match answer {
                Ok(Answer::Issued { cert, port }) => {
                    let endpoint = match host_of(&def.enroll) {
                        Some(h) => format!("quic/{h}:{port}"),
                        None => continue,
                    };
                    let applied = ctl.apply(Op::SetPeerCert {
                        site: def.site.clone(),
                        endpoint,
                        cert_pem: cert.clone(),
                    });
                    if applied.is_err() {
                        continue;
                    }
                    let _ = ctl.secrets.remove(&peer_secret(&def.site), PEER_TOKEN);
                    ctl.record("system", "peer_cert", &def.site, Status::Ok, "issued");
                    info!(site = %def.site, "certificate from the upstream site: connecting");
                    let k = format!("upstream/{}/certificate", def.site);
                    let _ = ctx
                        .update(&k, Value::Str(cert_summary(&cert)), Quality::Good, now_us())
                        .await;
                    ctl.schedule_reload();
                    ("issued".to_owned(), None)
                }
                Ok(Answer::Pending) => (
                    format!("pending authorization on {}", def.site),
                    Some(ENROLL_RETRY),
                ),
                Ok(Answer::Refused(why)) => (format!("refused: {why}"), Some(ENROLL_BACKOFF)),
                Err(e) => {
                    debug!(site = %def.site, "enrollment: {e}");
                    let n = failures.entry(def.site.clone()).or_default();
                    *n = n.saturating_add(1);
                    let wait = Duration::from_secs(1 << (*n).min(6)).min(ENROLL_BACKOFF);
                    (e, Some(wait))
                }
            };
            let k = format!("upstream/{}/status", def.site);
            let _ = ctx
                .update(&k, Value::Str(status), Quality::Good, now_us())
                .await;
            match wait {
                Some(w) => next.insert(def.site.clone(), now + w),
                None => next.remove(&def.site),
            };
        }
        tokio::select! {
            _ = ctl.enroll_wake.notified() => next.clear(),
            _ = tokio::time::sleep(Duration::from_secs(1)) => {}
        }
    }
}

/// Requests whose broker stopped asking leave quarantine after 10 minutes
/// (as a DSA link that disconnects); held brokers stay.
async fn expire_enrollments(ctl: Arc<Control>, ctx: LinkCtx) {
    loop {
        tokio::time::sleep(Duration::from_secs(60)).await;
        let reg = ctl.registry();
        if reg.enrollments.is_empty() {
            ctl.enroll_seen
                .lock()
                .unwrap_or_else(|p| p.into_inner())
                .clear();
            continue;
        }
        let stale = {
            let mut seen = ctl.enroll_seen.lock().unwrap_or_else(|p| p.into_inner());
            // nothing kept for a name that does not wait
            seen.retain(|site, _| reg.enrollments.contains_key(site));
            stale_enrollments(&reg, &mut seen, now_s(), ENROLL_STALE_S)
        };
        for site in stale {
            if ctl.apply(Op::DropEnrollment(site.clone())).is_ok() {
                ctl.enroll_seen
                    .lock()
                    .unwrap_or_else(|p| p.into_inner())
                    .remove(&site);
                debug!(site = %site, "enrollment request expired");
                let _ = ctx.remove_node(&format!("quarantine/{site}")).await;
            }
        }
        // also shows the polls counted in memory since the last change
        let _ = refresh_quarantine(&ctx, &ctl).await;
    }
}

/// One enrollment request to an upstream site over its enrollment
/// endpoint (server-auth TLS with that site's CA, no client certificate):
/// its answer, or why there is none (unreachable, a bad answer).
async fn ask_certificate(ctl: &Control, def: &PeerDef) -> Result<Answer, String> {
    let sealed = ctl.secrets.for_link(&peer_secret(&def.site));
    let key = sealed
        .get(PEER_KEY)
        .and_then(|k| std::str::from_utf8(k).ok())
        .ok_or("no key for this upstream site: add it again")?;
    let csr = secret::broker_csr(&ctl.cfg.site, key).map_err(|e| e.to_string())?;
    let ca = ctl.peer_ca_path(&def.site);
    if let Some(dir) = ca.parent() {
        std::fs::create_dir_all(dir).map_err(|e| e.to_string())?;
    }
    std::fs::write(&ca, &def.ca_pem).map_err(|e| e.to_string())?;
    let mut zc = zenoh::Config::default();
    let tls = serde_json::json!({ "root_ca_certificate": ca, "enable_mtls": false });
    for (k, v) in [
        ("mode", r#""client""#.to_owned()),
        (
            "connect/endpoints",
            serde_json::json!([def.enroll]).to_string(),
        ),
        ("scouting/multicast/enabled", "false".to_owned()),
        ("connect/timeout_ms", "5000".to_owned()),
        ("transport/link/tls", tls.to_string()),
    ] {
        zc.insert_json5(k, &v).map_err(|e| e.to_string())?;
    }
    let session = zenoh::open(zc)
        .await
        .map_err(|e| format!("unreachable: {}: {e}", def.enroll))?;
    let mut args = BTreeMap::from([
        ("site".to_owned(), Value::Str(ctl.cfg.site.clone())),
        ("csr".to_owned(), Value::Str(csr)),
        (
            "via".to_owned(),
            Value::Array(
                ctl.peers()
                    .reachable()
                    .into_iter()
                    .map(Value::Str)
                    .collect(),
            ),
        ),
    ]);
    if let Some(t) = sealed
        .get(PEER_TOKEN)
        .and_then(|t| std::str::from_utf8(t).ok())
    {
        args.insert("token".to_owned(), Value::Str(t.to_owned()));
    }
    let client = wyrm_client::WyrmClient::new(session.clone()).with_timeout(Duration::from_secs(5));
    let answer = client
        .invoke_one(&format!("wy/{}/sys", def.site), "enroll", Value::Map(args))
        .await;
    let _ = session.close().await;
    let m = match answer {
        Ok(Some(Value::Map(m))) => m,
        Ok(_) => return Err("no answer".into()),
        Err(e) => return Err(format!("unreachable: {e}")),
    };
    match m.get("status") {
        Some(Value::Str(s)) if s == "pending" => Ok(Answer::Pending),
        Some(Value::Str(s)) if s == "refused" => Ok(Answer::Refused(match m.get("reason") {
            Some(Value::Str(r)) => r.clone(),
            _ => String::new(),
        })),
        Some(Value::Str(s)) if s == "issued" => {
            let cert = match m.get("certificate") {
                Some(Value::Str(c)) => c.clone(),
                _ => return Err("bad answer: no certificate".into()),
            };
            check_issued_cert(&cert, &ctl.cfg.site, &def.key_sha256)?;
            let port = m
                .get("port")
                .and_then(Value::as_f64)
                .filter(|p| (1.0..=65535.0).contains(p))
                .ok_or("bad answer: no port")? as u16;
            Ok(Answer::Issued { cert, port })
        }
        _ => Err("bad answer".into()),
    }
}

async fn declare_remove(ctx: &LinkCtx, path: &str) -> wyrm_link_sdk::Result<()> {
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
        // only what this host can install (a build for it, ADR 0021)
        Some(Ok(list))
            if list
                .iter()
                .any(|e| e.asset(&packages::platform()).is_some()) =>
        {
            str_param().required(true).display("Package").enum_values(
                list.iter()
                    .filter(|e| e.asset(&packages::platform()).is_some())
                    .map(|e| e.name.clone()),
            )
        }
        Some(Ok(list)) if !list.is_empty() => str_param()
            .required(true)
            .display("Package")
            .placeholder(format!(
                "no package built for this host ({})",
                packages::platform()
            )),
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
/// The `package_install` audit detail (install and upgrade): version,
/// SHA-256 and source, then what the package's links may use: its
/// capabilities and the requester grants it asks for.
fn install_detail(def: &PackageDef, caps: Option<&wyrm_link_sdk::package::Capabilities>) -> String {
    let mut d = format!("{} sha256:{} {}", def.version, def.sha256, def.source);
    if let Some(c) = caps {
        d.push_str(&format!("; capabilities {}", c.describe()));
    }
    for (path, code) in &def.requester {
        let level = Perm::try_from(*code).map_or("?", |p| p.name());
        d.push_str(&format!("; requester {path} {level}"));
    }
    d
}

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
        publish_overlays(&ctx, &cfg.ctl).await?;
        signers::publish_signing_keys(&ctx, &cfg.ctl).await?;
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
        // Downstream brokers ask for a certificate and come in as DSA links
        // do: token, allow_all_links or quarantine (ADR 0015).
        if cfg.ctl.config_peers().enroll {
            ctx.declare_action(
                "",
                "enroll",
                // open (see `open_actions`); level none hides it from people
                ActionMeta::new()
                    .level(Perm::None)
                    .param("site", str_param().required(true))
                    .param("csr", str_param().required(true))
                    .param("token", str_param())
                    .param("via", ParamMeta::of(TypeCode::Array))
                    .result(ActionResult::Type(TypeCode::Map)),
            )
            .await?;
            declare_tokens(&ctx, &cfg.ctl).await?;
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
        crate::history::declare(&ctx, &cfg.ctl).await?;
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
        if let ["history", rest @ ..] = path.split('/').collect::<Vec<_>>().as_slice() {
            return crate::history::set(&self.ctl, &self.ctx, rest, value, &sub_of(who)).await;
        }
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
        if let ["upstream", site, "allow_config"] = path.split('/').collect::<Vec<_>>().as_slice() {
            let Value::Bool(on) = value else {
                return Err(LinkError::invalid_parameter("allow_config: true or false"));
            };
            return self.allow_config(site, on, &sub_of(who)).await;
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
            ([""], "enroll") => self.enroll(&args).await,
            (["tokens"], "add") => self.add_token(&args, &sub).await,
            (["tokens", id], "remove") => self.remove_token(id, &sub).await,
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
            (["quarantine", node], "approve") => {
                let cn = self.quarantine_key(node);
                self.approve(&cn, &args, &sub).await
            }
            (["quarantine"], "authorize") => match arg_str(&args, "dsid") {
                Some(cn) => self.approve(cn, &args, &sub).await,
                None => Err(LinkError::invalid_parameter("dsid: required")),
            },
            (["quarantine"], "deauthorize") => match arg_str(&args, "link") {
                Some(id) => self.deauthorize(id, &sub).await,
                None => Err(LinkError::invalid_parameter("link: required")),
            },
            (["quarantine", node], "reject") => {
                let cn = self.quarantine_key(node);
                self.reject(&cn, &sub).await.map(|_| None)
            }
            (["profiles"], "put") => self.put_profile(&args, &sub).await.map(|_| None),
            (["profiles"], "remove") => self.remove_profile(&args, &sub).await.map(|_| None),
            ([""], "clear_conns") => self.clear_conns(&sub).await,
            (["upstream"], "add") => self.add_upstream(&args, &sub).await,
            (["upstream", site], "remove") => self.remove_upstream(site, &sub).await,
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
            (["history", rest @ ..], _) => {
                crate::history::invoke(&self.ctl, &self.ctx, rest, action, &args, &sub).await
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
        crate::registry::validate_new_link_id(&id).map_err(LinkError::invalid_parameter)?;
        if ctl.peers().downstream.contains(&id) {
            return Err(LinkError::invalid_parameter(format!(
                "link id {id:?} is a downstream site (downstream/{id} is its broker node)"
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
        let app = unpacked.app.clone();
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
                    &install_detail(&def, app.as_ref()),
                );
                declare_package(&self.ctx, &def)
                    .await
                    .map_err(|e| e.to_string())?;
                if let Some(old) = old {
                    let failed = self.upgrade_links(&def, app.is_some(), sub).await;
                    let _ = std::fs::remove_dir_all(packages::dir(&root, old));
                    let mut m = format!("package {} {} → {}", def.name, old.version, def.version);
                    if !failed.is_empty() {
                        m.push_str(&format!("; not restarted: {}", failed.join(", ")));
                    }
                    m
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
                    // a portable app as a process: its capabilities as params, as
                    // for its WASM twin (ADR 0023)
                    if app.is_some() {
                        args.insert(
                            "params".into(),
                            packages::link_params(&def.name, def.kind, app.as_ref()),
                        );
                    }
                }
                PackageKind::Wasm => {
                    // Embedded: an app component (ADR 0023) runs as driver
                    // `app` with its capabilities as params; a driver or
                    // point component gets one connection on it, devices and
                    // points come from its own Add actions (ADR 0012).
                    args.insert("mode".into(), Value::Str("embedded".into()));
                    args.insert(
                        "params".into(),
                        packages::link_params(&def.name, def.kind, app.as_ref()),
                    );
                }
            }
            let args = Value::Map(args);
            self.install(&args, sub).await.map_err(|e| e.to_string())?;
            message.push_str(&format!("; link {link} installed"));
            // what the app link may use, shown (ADR 0023)
            if let Some(c) = &app {
                message.push_str(&format!("; capabilities {}", c.describe()));
            }
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

    /// After an upgrade, the links of package `def` run the new version:
    /// an app component's running links swap code in place (hot start, ADR
    /// 0023: the tree stays, the store carries over); every other link of the
    /// package stops and starts from the new files. One link that fails does
    /// not stop the others; returns `<id> (<error>)` of each that failed, each
    /// also audited.
    async fn upgrade_links(&self, def: &PackageDef, app: bool, sub: &str) -> Vec<String> {
        let driver = format!("{}{}", packages::DRIVER_PREFIX, def.name);
        let mut failed = Vec::new();
        let swapped = if def.kind == PackageKind::Wasm && app {
            match self.ctl.host.reload_package(&def.name).await {
                Ok(ids) => ids,
                Err(e) => {
                    warn!(package = %def.name, "hot start: {e}; the links restart instead");
                    Vec::new()
                }
            }
        } else {
            Vec::new()
        };
        let reg = self.ctl.registry();
        for l in reg.links.values().filter(|l| l.driver == driver) {
            if swapped.contains(&l.id) {
                self.ctl
                    .record(sub, "hot_start", &l.id, Status::Ok, &def.version);
                continue;
            }
            let _ = self.stop_link(&l.id, sub).await;
            if let Err(e) = self.start_link(&l.id, sub).await {
                self.ctl.record(
                    sub,
                    "start",
                    &l.id,
                    e.status,
                    &format!("after upgrade to {}: {}", def.version, e.message),
                );
                failed.push(format!("{} ({})", l.id, e.message));
            }
        }
        failed
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
        // this host's file (ADR 0021); a relative url is in the repository
        let host = packages::platform();
        let a = e
            .asset(&host)
            .ok_or_else(|| format!("{package}: no build for this host ({host})"))?;
        let url = wyrm_link_sdk::package::resolve(&index, &a.url)?;
        let zip = crate::fetch::get(&url, packages::MAX_ZIP, FETCH_TIMEOUT).await?;
        let got = hex::encode(<sha2::Sha256 as sha2::Digest>::digest(&zip));
        if !got.eq_ignore_ascii_case(&a.sha256) {
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
        reply.insert(
            "grants".into(),
            Value::Array(
                self.ctl
                    .link_grants(&def)
                    .into_iter()
                    .map(|(path, perm)| {
                        Value::Array(vec![Value::Str(path), Value::UInt(perm.code().into())])
                    })
                    .collect(),
            ),
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
        // A process package's params are its binary's to parse (at `hello`):
        // the broker cannot know their type, so they are not checked here, as
        // at install. Every other link is checked by the driver it runs on (a
        // `wasm` package by its component's world).
        let process_package = def
            .driver
            .strip_prefix(packages::DRIVER_PREFIX)
            .and_then(|n| self.ctl.registry().packages.get(n).map(|p| p.kind))
            == Some(PackageKind::Process);
        if def.mode != Mode::External && !process_package {
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
        let key = format!("wy/{}/downstream/*", self.ctl.cfg.site);
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
        if let Some(site) = crate::registry::broker_site(cn) {
            return self.authorize_broker(site, args, sub).await;
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
            let key = format!("wy/{{site}}/downstream/{cn}/**");
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
        // a downstream broker is a link to DSA too: held in quarantine,
        // its key and certificate kept for Authorize (ADR 0015)
        if self
            .ctl
            .registry()
            .peers
            .get(id)
            .is_some_and(|p| p.dir == PeerDir::Downstream)
        {
            self.ctl
                .apply(Op::HoldBroker {
                    site: id.to_owned(),
                    seen: now_s(),
                })
                .map_err(rejected)?;
            self.ctl.record(
                sub,
                "deauthorize",
                &crate::registry::broker_cn(id),
                Status::Ok,
                "",
            );
            refresh_quarantine(&self.ctx, &self.ctl).await?;
            self.ctl.schedule_reload();
            return Ok(None);
        }
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
            format!("wy/{{site}}/downstream/{id}/**"),
            format!("wy/{site}/downstream/{id}/**"),
        ];
        match roles.revoke_widening(&keys, &format!("wy/{site}/downstream/{id}/~val")) {
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

    /// `sys/upstream ▸ Add Upstream Connection` (ADR 0015, as DSA's): that
    /// site's enrollment endpoint, its CA and an optional token. This broker
    /// makes its own key (sealed, it never leaves the site) and asks for its
    /// certificate in the background ([`enroll_upstreams`]).
    async fn add_upstream(&self, args: &Value, sub: &str) -> wyrm_link_sdk::Result<Option<Value>> {
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
        self.check_new_site(site)?;
        if self.ctl.registry().issued_brokers.contains(site) {
            return Err(LinkError::invalid_parameter(format!(
                "site {site} was a downstream broker of ours: its certificate stays valid"
            )));
        }
        check_ca_pem(ca_pem).map_err(LinkError::invalid_parameter)?;
        let url = need("url")?;
        if !url.starts_with("quic/") || url.contains(['#', '?', ';']) || url.len() > 256 {
            return Err(LinkError::invalid_parameter(format!(
                "url {url}: expected quic/<host>:<port> (its peers.enroll)"
            )));
        }
        let token = arg_str(args, "token")
            .map(str::trim)
            .filter(|t| !t.is_empty());
        let enabled = !matches!(arg(args, "enabled"), Some(Value::Bool(false)));
        let allow_config = matches!(arg(args, "allow_config"), Some(Value::Bool(true)));
        let (key, key_sha256) =
            secret::new_broker_key().map_err(|e| LinkError::internal(e.to_string()))?;
        let store = peer_secret(site);
        let sealed = self
            .ctl
            .secrets
            .set(&store, PEER_KEY, key.as_bytes())
            .and_then(|_| match token {
                Some(t) => self.ctl.secrets.set(&store, PEER_TOKEN, t.as_bytes()),
                None => Ok(()),
            });
        if let Err(e) = sealed {
            let _ = self.ctl.secrets.drop_link(&store);
            return Err(LinkError::internal(e.to_string()));
        }
        let def = PeerDef {
            site: site.to_owned(),
            dir: PeerDir::Upstream,
            endpoint: String::new(),
            ca_pem: format!("{ca_pem}\n"),
            enabled,
            created: now_s(),
            via: Vec::new(),
            cert_pem: String::new(),
            enroll: url.to_owned(),
            key_sha256,
            allow_config,
        };
        if let Err(e) = self.ctl.apply(Op::AddPeer(def.clone())) {
            let _ = self.ctl.secrets.drop_link(&store);
            return Err(rejected(e));
        }
        self.ctl.record(
            sub,
            "peer_add",
            site,
            Status::Ok,
            &format!("upstream {url}"),
        );
        declare_upstream(&self.ctx, &Upstream::of(&def), true).await?;
        self.ctl.enroll_wake.notify_one();
        Ok(None)
    }

    /// A new peer site: not this broker, not a peer (either direction, from
    /// `wyrmd.json5` or the registry), not a site a peer relays.
    fn check_new_site(&self, site: &str) -> wyrm_link_sdk::Result<()> {
        let all = self.ctl.peers();
        if site == self.ctl.cfg.site
            || self.ctl.registry().peers.contains_key(site)
            || all.upstream.iter().any(|u| u == site)
            || all.downstream.iter().any(|d| d == site)
            || all.reachable().iter().any(|r| r == site)
        {
            return Err(LinkError::invalid_parameter(format!(
                "site {site} is this broker, a peer or a site a peer relays"
            )));
        }
        Ok(())
    }

    async fn remove_upstream(&self, site: &str, sub: &str) -> wyrm_link_sdk::Result<Option<Value>> {
        if !self
            .ctl
            .registry()
            .peers
            .get(site)
            .is_some_and(|d| d.dir == PeerDir::Upstream)
        {
            return Err(LinkError::not_supported(
                "not a runtime upstream peer; peers from wyrmd.json5 are removed there",
            ));
        }
        self.ctl
            .apply(Op::RemovePeer(site.to_owned()))
            .map_err(rejected)?;
        let _ = self.ctl.secrets.drop_link(&peer_secret(site));
        for ext in ["pem", "cert.pem", "key"] {
            let _ = std::fs::remove_file(self.ctl.peer_file(site, ext));
        }
        self.ctl
            .record(sub, "peer_remove", site, Status::Ok, "upstream");
        self.ctx.remove_node(&format!("upstream/{site}")).await?;
        self.ctl.schedule_reload();
        Ok(None)
    }

    /// The sites a downstream broker relays (`via`) are free here: none is
    /// this site, the broker itself, a peer or a site a peer relays.
    fn via_free(&self, site: &str, via: &[String]) -> Result<(), String> {
        let all = self.ctl.peers();
        for v in via {
            wyrm_core::keyspace::validate_segment(v).map_err(|e| format!("via: {e}"))?;
            if *v == self.ctl.cfg.site
                || *v == site
                || all.upstream.contains(v)
                || all.downstream.contains(v)
                || all.reachable().contains(v)
                || via.iter().filter(|x| *x == v).count() > 1
            {
                return Err(format!("via {v}: this broker, a peer or already relayed"));
            }
        }
        Ok(())
    }

    /// Admit a downstream broker (ADR 0015): out of quarantine, a runtime
    /// downstream peer with the key and certificate it was given (empty:
    /// admitted by name, its certificate came another way).
    async fn admit_broker(
        &self,
        site: &str,
        via: Vec<String>,
        key_sha256: String,
        cert_pem: String,
        sub: &str,
        how: &str,
    ) -> wyrm_link_sdk::Result<()> {
        // also on Authorize: peers may have changed since it was quarantined
        self.check_new_site(site)?;
        self.via_free(site, &via)
            .map_err(LinkError::invalid_parameter)?;
        self.ctl
            .apply(Op::AdmitBroker {
                site: site.to_owned(),
                via: via.clone(),
                key_sha256,
                cert_pem,
                seen: now_s(),
            })
            .map_err(rejected)?;
        self.ctl.enroll_forget(site);
        self.ctl.record(
            sub,
            how,
            &crate::registry::broker_cn(site),
            Status::Ok,
            &format!("via [{}]", via.join(", ")),
        );
        let _ = self.ctx.remove_node(&format!("quarantine/{site}")).await;
        refresh_quarantine(&self.ctx, &self.ctl).await?;
        self.ctl.schedule_reload();
        Ok(())
    }

    /// Sign the waiting request of `site` (or give back the certificate it
    /// held when Deauthorized) and admit it: Authorize of a broker.
    async fn authorize_broker(
        &self,
        site: &str,
        args: &Value,
        sub: &str,
    ) -> wyrm_link_sdk::Result<Option<Value>> {
        let reg = self.ctl.registry();
        // Bound to the request the administrator looked at: its key's
        // SHA-256 must come with Authorize (the request may have expired
        // and come back with another key in between).
        let given = arg_str(args, "key").map(str::trim).unwrap_or_default();
        let e = match reg.enrollments.get(site) {
            Some(e) if e.key_sha256.is_empty() || e.key_sha256 == given => e.clone(),
            Some(_) => {
                return Err(LinkError::invalid_parameter(
                    "key: not the key of the waiting request; look at it again",
                ))
            }
            // a broker seen only by its certificate (no request): by name
            None if reg
                .quarantine
                .contains_key(&crate::registry::broker_cn(site))
                && given.is_empty() =>
            {
                Default::default()
            }
            None => return Err(LinkError::not_found(format!("no request of {site}"))),
        };
        // the Via field, else what the broker asked for
        let via = match arg(args, "via") {
            Some(v) if !via_list(Some(v)).is_empty() => via_list(Some(v)),
            _ => e.via.clone(),
        };
        let cert = if !e.csr_pem.is_empty() {
            self.ctl
                .pki
                .sign_broker_csr(site, &e.csr_pem)
                .map_err(|e| LinkError::invalid_parameter(e.to_string()))?
        } else {
            e.cert_pem.clone()
        };
        self.admit_broker(site, via, e.key_sha256, cert, sub, "approve")
            .await?;
        Ok(None)
    }

    /// `sys/~act/enroll` (ADR 0015, an open action: no ptok, the
    /// unverified-caller rate limit): a downstream broker asks for its
    /// certificate with `{site, csr, token, via}`. Answers `{status: issued,
    /// certificate, port}` or `{status: pending}`; a refusal is an error.
    async fn enroll(&self, args: &Value) -> wyrm_link_sdk::Result<Option<Value>> {
        let site = arg_str(args, "site").unwrap_or_default().trim().to_owned();
        let csr = arg_str(args, "csr").unwrap_or_default().to_owned();
        let via = via_list(arg(args, "via"));
        wyrm_core::keyspace::validate_segment(&site)
            .map_err(|e| LinkError::invalid_parameter(format!("site: {e}")))?;
        // a refusal is an answer, with its reason, for the asking broker
        let refused = |why: &str| -> wyrm_link_sdk::Result<Option<Value>> {
            Ok(Some(Value::Map(BTreeMap::from([
                ("status".to_owned(), Value::from("refused")),
                ("reason".to_owned(), Value::from(why)),
            ]))))
        };
        let cfg = self.ctl.config_peers();
        let port = cfg
            .listen_port
            .ok_or_else(|| LinkError::not_supported("no peers.listen"))?;
        let key = secret::broker_csr_key(&site, &csr)
            .map_err(|e| LinkError::invalid_parameter(e.to_string()))?;
        let issued = |cert: String| {
            Ok(Some(Value::Map(BTreeMap::from([
                ("status".to_owned(), Value::from("issued")),
                ("certificate".to_owned(), Value::Str(cert)),
                ("port".to_owned(), Value::UInt(port.into())),
            ]))))
        };
        let reg = self.ctl.registry();
        let cn = crate::registry::broker_cn(&site);
        // one reason for every name it cannot have: the endpoint is open,
        // so it does not tell peers, links or relayed sites apart
        const NOT_HERE: &str = "this name cannot be admitted here";
        if let Some(p) = reg.peers.get(&site) {
            // asked again (it lost the answer): the same key, the same answer
            if p.dir == PeerDir::Downstream && p.key_sha256 == key && !p.cert_pem.is_empty() {
                return issued(p.cert_pem.clone());
            }
            return refused(NOT_HERE);
        }
        if cfg.peers.downstream.contains(&site)
            || self.check_new_site(&site).is_err()
            || reg.links.contains_key(&site)
            // `downstream/scheduler` is the embedded scheduler (ADR 0022)
            || site == SCHEDULER_LINK
            || reg.blocklist.contains(&cn)
        {
            return refused(NOT_HERE);
        }
        let pending = || {
            Ok(Some(Value::Map(BTreeMap::from([(
                "status".to_owned(),
                Value::from("pending"),
            )]))))
        };
        let wait = |ctl: &Control| -> wyrm_link_sdk::Result<()> {
            ctl.apply(Op::EnrollRequest {
                site: site.clone(),
                csr_pem: csr.clone(),
                key_sha256: key.clone(),
                via: via.clone(),
                seen: now_s(),
            })
            .map_err(rejected)
        };
        if reg
            .enrollments
            .get(&site)
            .is_some_and(|e| !e.key_sha256.is_empty() && e.key_sha256 != key)
        {
            // counted (in memory), shown; the waiting request stays
            let seen = self.ctl.enroll_touch(&site, true);
            if seen.conflicts == 1 {
                self.ctl.record(
                    &format!("broker:{site}"),
                    "enroll",
                    &cn,
                    Status::PermissionDenied,
                    "another key waits for this name",
                );
            }
            refresh_quarantine(&self.ctx, &self.ctl).await?;
            return refused(NOT_HERE);
        }
        let opts = self.ctl.options();
        if !reg.held.contains(&cn) && self.via_free(&site, &via).is_ok() {
            let token = arg_str(args, "token").and_then(|t| self.ctl.token_id(t));
            if token.is_some() || opts.allow_all_links {
                let cert = self
                    .ctl
                    .pki
                    .sign_broker_csr(&site, &csr)
                    .map_err(|e| LinkError::invalid_parameter(e.to_string()))?;
                let how = match &token {
                    Some(id) => {
                        self.ctl.apply(Op::UseToken(id.clone())).map_err(rejected)?;
                        let _ = self.ctx.remove_node(&format!("tokens/{id}")).await;
                        declare_tokens(&self.ctx, &self.ctl).await?;
                        "enroll_token"
                    }
                    None => "auto_install",
                };
                self.admit_broker(
                    &site,
                    via,
                    key,
                    cert.clone(),
                    &format!("broker:{site}"),
                    how,
                )
                .await?;
                return issued(cert);
            }
        }
        if !opts.enable_quarantine && !reg.held.contains(&cn) {
            return refused("not admitted (quarantine is off)");
        }
        // Written only when it changes (a new name, key or via, or the
        // first request of a held broker); a poll every 10 s writes nothing.
        let changed = reg
            .enrollments
            .get(&site)
            .is_none_or(|e| e.key_sha256 != key || e.via != via || e.csr_pem.is_empty());
        if changed {
            wait(&self.ctl)?;
            // counted once it waits (a refused name leaves no trace)
            self.ctl.enroll_touch(&site, false);
            self.ctl.record(
                &format!("broker:{site}"),
                "quarantine",
                &cn,
                Status::PermissionDenied,
                "enrollment",
            );
            info!(site = %site, "downstream broker waits in quarantine");
            refresh_quarantine(&self.ctx, &self.ctl).await?;
        } else {
            self.ctl.enroll_touch(&site, false);
        }
        pending()
    }

    /// `sys/tokens ▸ Add Token {count, hours}` (as DSA's `/sys/tokens`): a
    /// token that admits a downstream broker at once; returned once, kept
    /// as its SHA-256.
    async fn add_token(&self, args: &Value, sub: &str) -> wyrm_link_sdk::Result<Option<Value>> {
        let num = |k: &str, d: f64| arg(args, k).and_then(Value::as_f64).unwrap_or(d);
        let (count, hours) = (num("count", 1.0), num("hours", 24.0));
        if !(0.0..=1e6).contains(&count) || !(0.0..=87_600.0).contains(&hours) {
            return Err(LinkError::invalid_parameter(
                "count 0..1000000 (0: no limit), hours 0..87600 (0: never)",
            ));
        }
        let id =
            secret::new_token().map_err(|e| LinkError::internal(e.to_string()))?[..12].to_owned();
        let secret_part = secret::new_token().map_err(|e| LinkError::internal(e.to_string()))?;
        let token = zeroize::Zeroizing::new(format!("{id}.{}", secret_part.as_str()));
        let now = now_s();
        let def = TokenDef {
            sha256: token_sha256(&token),
            uses: count as u32,
            expires: if hours == 0.0 {
                0
            } else {
                now + (hours * 3600.0) as u64
            },
            created: now,
            by: sub.to_owned(),
        };
        self.ctl
            .apply(Op::AddToken {
                id: id.clone(),
                def,
            })
            .map_err(rejected)?;
        self.ctl.record(sub, "token_add", &id, Status::Ok, "");
        declare_tokens(&self.ctx, &self.ctl).await?;
        Ok(Some(Value::Map(BTreeMap::from([(
            "token".to_owned(),
            Value::Str(token.to_string()),
        )]))))
    }

    async fn remove_token(&self, id: &str, sub: &str) -> wyrm_link_sdk::Result<Option<Value>> {
        self.ctl
            .apply(Op::RemoveToken(id.to_owned()))
            .map_err(rejected)?;
        self.ctl.record(sub, "token_remove", id, Status::Ok, "");
        self.ctx.remove_node(&format!("tokens/{id}")).await?;
        Ok(None)
    }

    /// The registry key of a quarantine node: `broker:<site>` for a
    /// downstream broker, else the link CN.
    fn quarantine_key(&self, node: &str) -> String {
        let cn = crate::registry::broker_cn(node);
        if self.ctl.registry().quarantine.contains_key(&cn) {
            cn
        } else {
            node.to_owned()
        }
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
        self.ctl.enroll_wake.notify_one();
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

    /// `upstream/<site>/allow_config` of a runtime upstream site: the ACL
    /// and the admin's trust follow on the rebuild (ADR 0018).
    async fn allow_config(&self, site: &str, on: bool, sub: &str) -> wyrm_link_sdk::Result<()> {
        self.ctl
            .apply(Op::SetPeerAllowConfig {
                site: site.to_owned(),
                on,
            })
            .map_err(|_| {
                LinkError::not_supported(
                    "not a runtime upstream peer; peers from wyrmd.json5 are changed there",
                )
            })?;
        self.ctl
            .record(sub, "peer_allow_config", site, Status::Ok, &on.to_string());
        self.ctx
            .update(
                &format!("upstream/{site}/allow_config"),
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
        if let Some(site) = crate::registry::broker_site(cn) {
            self.ctl.enroll_forget(site);
        }
        self.ctl.record(sub, "reject", cn, Status::Ok, "");
        self.ctx
            .remove_node(&format!("quarantine/{}", quarantine_node(cn)))
            .await
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
            "{cn:?} is a downstream site (downstream/{cn} is its broker node)"
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

/// `links/<id>/state` from liveliness (`downstream/<id>`), the supervisor and the
/// embedded table.
async fn watch_states(ctl: Arc<Control>, ctx: LinkCtx, embedded: Running) {
    let down = format!("wy/{}/downstream/*", ctl.cfg.site);
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
        // `downstream/<d>` is a downstream site's node; never a link.
        || peers.downstream.iter().any(|d| d == cn)
        // a broker of that name waits in quarantine: one node each
        || reg.quarantine.contains_key(&crate::registry::broker_cn(cn))
        || cn == "broker";
    !known && crate::registry::validate_new_link_id(cn).is_ok()
}

/// The port of `<host>:<port>` (`[v6]:<port>` too).
fn port_of(address: &str) -> Option<u16> {
    address.rsplit_once(':')?.1.parse().ok()
}

/// May a `broker:<site>` session over QUIC go to quarantine (ADR 0015)?
/// Never this broker, a peer site (an upstream's own certificate on our
/// outbound link included), a site a peer relays, a rejected broker or a
/// name a link has (or waits for in quarantine).
fn broker_admissible(reg: &Registry, peers: &acl::Peers, own: &str, site: &str) -> bool {
    let known = site == own
        || peers.upstream.iter().any(|u| u == site)
        || peers.downstream.iter().any(|d| d == site)
        || peers.reachable().iter().any(|r| r == site)
        || reg.peers.contains_key(site)
        || reg.links.contains_key(site)
        || site == SCHEDULER_LINK
        || reg.quarantine.contains_key(site)
        || reg.blocklist.contains(&crate::registry::broker_cn(site));
    !known
}

/// Sessions whose certificate CN is not a known link or operator: installed
/// with `allow_all_links`, else quarantined with `enable_quarantine`, else
/// ignored. Links count over `tls`, downstream brokers (`broker:<site>`)
/// over `quic`; both listeners trust our CA alone (ADR 0015). Brokers are
/// never installed automatically: Authorize sets the sites they relay.
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
        let proto = ev.link().src().protocol().as_str().to_owned();
        let broker = crate::registry::broker_site(&cn).is_some();
        let ok = match crate::registry::broker_site(&cn) {
            // only sessions that came in on our QUIC peer listener: on our own
            // link to an upstream site the CN is that site's server's
            Some(site) => {
                proto == "quic"
                    && port_of(ev.link().src().address().as_ref()) == ctl.config_peers().listen_port
                    && broker_admissible(&ctl.registry(), &ctl.peers(), &ctl.cfg.site, site)
            }
            None => {
                proto == "tls" && admissible(&ctl.registry(), &ctl.cfg.operators, &ctl.peers(), &cn)
            }
        };
        if !ok {
            debug!(cn = %cn, proto = %proto, "known CN or wrong listener: not quarantined");
            continue;
        }
        let opts = ctl.options();
        // a deauthorized CN stays in quarantine until a manual Authorize
        let held = ctl.registry().held.contains(&cn);
        if opts.allow_all_links && !held && !broker {
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
            format!("wy/{}/dataflows", ctl.cfg.site)
        } else if link == STORAGE_LINK {
            format!("wy/{}/storage", ctl.cfg.site)
        } else {
            format!("wy/{}/downstream/{link}", ctl.cfg.site)
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
pub(crate) fn disk_free_mib(dir: &std::path::Path) -> Option<f64> {
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
/// and the link ids whose token (`wy/<site>/downstream/<id>`) is present.
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
    let links = get(format!("wy/{site}/downstream/*"))
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
        set("packages_total", reg.packages.len() as f64).await;
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
            .map(|(_, _, name)| counter(&text, name))
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
    fn overlays_of_other_sites_go_to_sites() {
        use crate::registry::{Registry, WatchDef, WatchGroupDef};
        use wyrm_core::Value;
        let mut reg = Registry::default();
        let watch = |key: &str| WatchDef {
            key: key.into(),
            enabled: true,
        };
        reg.historian.groups.insert(
            "g".into(),
            WatchGroupDef {
                logging: 1,
                interval_ms: 1000,
                flush_ms: 1000,
                watches: [
                    ("w1".into(), watch("wy/c/downstream/hq/p0")),
                    ("w2".into(), watch("wy/edge/downstream/lab/wave")),
                    ("w3".into(), watch("wy/c/sys/cpu")),
                ]
                .into(),
            },
        );
        let maps = super::overlay_maps(&reg, "c");
        let hist = |k: &str| {
            Value::Map(
                [(
                    "history".to_owned(),
                    Value::Array(vec![Value::from(format!("wy/c/sys/history/g/{k}"))]),
                )]
                .into(),
            )
        };
        assert_eq!(maps["hq"]["p0"], hist("w1"));
        // a downstream site's point: under its full key, in `.sites`
        assert_eq!(
            maps[super::SITES_OVERLAY]["wy/edge/downstream/lab/wave"],
            hist("w2")
        );
        // the own sys has no link to lay it on
        assert_eq!(maps.len(), 2, "{maps:?}");
    }

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

    /// Junk requests cannot hold the 64 places: a request not asked again
    /// for 10 minutes goes, a held broker stays, a fresh one stays.
    #[test]
    fn stale_enrollment_requests() {
        use crate::registry::{Op, Registry};
        use wyrm_state::State;
        let mut reg = Registry::default();
        for site in ["old", "fresh", "unseen"] {
            reg.apply(&Op::EnrollRequest {
                site: site.into(),
                csr_pem: "csr".into(),
                key_sha256: "k".into(),
                via: Vec::new(),
                seen: 0,
            })
            .unwrap();
        }
        reg.held.insert("broker:old-held".into());
        reg.enrollments
            .insert("old-held".into(), Default::default());
        let seen_at = |last| super::EnrollSeen {
            last,
            ..Default::default()
        };
        let mut seen = std::collections::HashMap::from([
            ("old".to_owned(), seen_at(100)),
            ("fresh".to_owned(), seen_at(1000)),
            ("old-held".to_owned(), seen_at(0)),
        ]);
        // another key's polls do not keep a request alive
        super::touch_seen(&mut seen, "old", 1000, true);
        assert_eq!(seen["old"].conflicts, 1);
        let stale = super::stale_enrollments(&reg, &mut seen, 1000, 600);
        assert_eq!(stale, ["old"]);
        // an unseen one counts from now
        assert_eq!(seen["unseen"].last, 1000);
        reg.apply(&Op::DropEnrollment("old".into())).unwrap();
        assert!(!reg.quarantine.contains_key("broker:old"));
        assert!(reg.apply(&Op::DropEnrollment("old-held".into())).is_err());
    }

    #[test]
    fn ports_of_link_addresses() {
        assert_eq!(super::port_of("127.0.0.1:7449"), Some(7449));
        assert_eq!(super::port_of("[::1]:7449"), Some(7449));
        assert_eq!(super::port_of("host"), None);
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
            ..Default::default()
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
            via: Vec::new(),
            cert_pem: String::new(),
            enroll: String::new(),
            key_sha256: String::new(),
            allow_config: false,
        };
        let config = crate::acl::Peers {
            upstream: vec!["cloud".into()],
            downstream: vec!["edge".into()],
            ..Default::default()
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
            ..Default::default()
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
