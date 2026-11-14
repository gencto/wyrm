//! WYRM user gateway (wiki "Користувачі — gateway чи mTLS"): HTTP(S) + WS
//! server that holds user sessions, mints a fresh `ptok` per request from
//! the user's roles, proxies list/subscribe/set/invoke into Zenoh and
//! filters every sample and child by the user's grants.
//!
//! Bodies and frames are canonical CBOR (`wyrm_core::Value`), never JSON.
//!
//! * `POST /api/login` `{user, password}` → `{session, exp}`
//! * `GET /api/me` → `{sub, roles, grants}`
//! * `POST /api/ws-ticket` (bearer session) → `{ticket, exp}`: single use,
//!   30 s, so the long-lived session never appears in a URL
//! * `GET /api/ws?ticket=…` (or `Authorization: Bearer`) — binary CBOR
//!   frames (64 KiB each), see [`ws`]
//! * `POST /api/invoke?key=…&action=…` (bearer session), body = CBOR `args`
//!   → `{result}`: one invoke of an action with an `editor: file` parameter
//!   whose arguments do not fit a frame (64 MiB, ADR 0011); key, grant and
//!   the file parameter are checked before the body is read
//! * user management (`config` on `wy/<site>/sys/**`): `GET|POST /api/users`,
//!   `POST /api/users/{name}/password|roles|disabled`, `DELETE /api/users/{name}`
//! * `GET /api/info` (public): what a log-in page needs before a login (ADR 0050 §2.2)
//! * device keys and the step-up (ADR 0050 §1): see [`devices`]

#![forbid(unsafe_code)]

pub mod approve;
pub mod devices;
mod http;
mod limit;
#[cfg(feature = "mcp")]
mod mcp;
pub mod oauth;
mod overlay;
pub mod roles;
pub mod session;
pub mod users;
pub mod ws;

pub use devices::{DevicePolicy, StepUp};
pub use oauth::McpConfig;
pub use roles::{with_grant, Grants, RoleTable};
pub use session::{Amr, SessionClaims};

use ed25519_dalek::{SigningKey, VerifyingKey};
use session::SessionKey;
use std::future::Future;
use std::net::{IpAddr, SocketAddr};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, RwLock};
use std::time::Duration;
use tokio::sync::{watch, Semaphore};
use tracing::info;
use users::{Op, User, UserDb};
use wyrm_core::Perm;
use wyrm_state::Store;
use zeroize::Zeroizing;

/// Lifetime of a minted `ptok` (wiki: 5 min).
pub const PTOK_TTL: Duration = Duration::from_secs(300);
/// Default session lifetime.
pub const SESSION_TTL: Duration = Duration::from_secs(8 * 3600);
/// Failed logins per user and address in [`LOGIN_WINDOW`].
pub const LOGIN_FAILURES: usize = 5;
pub const LOGIN_WINDOW: Duration = Duration::from_secs(60);
/// `GET /api/info` requests per address and minute.
pub const INFO_PER_MIN: u32 = 60;
/// `POST /api/device/challenge` requests per address and minute.
pub const CHALLENGES_PER_MIN: u32 = 30;
/// The oldest Studio this gateway serves (`min_studio` of `/api/info`).
pub const MIN_STUDIO: &str = "1.0.0";

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("state: {0}")]
    State(#[from] wyrm_state::StateError),
    #[error("io: {0}")]
    Io(#[from] std::io::Error),
    #[error("config: {0}")]
    Config(String),
    #[error("{0}")]
    Rejected(String),
}

pub type Result<T, E = Error> = core::result::Result<T, E>;

#[derive(Debug, Clone)]
pub struct GatewayConfig {
    pub site: String,
    /// Holds `users/` (WAL + snapshot) and `gateway.key`.
    pub dir: PathBuf,
    pub listen: SocketAddr,
    /// `(certificate chain PEM, private key PEM)`. Required unless `listen`
    /// is a loopback address.
    pub tls: Option<(PathBuf, PathBuf)>,
    pub session_ttl: Duration,
    pub roles: RoleTable,
    /// WAL head anchor of the user store (another medium; see
    /// `wyrm_state::Store::with_anchor`).
    pub anchor: Option<PathBuf>,
    /// Create the anchor from the current head (operator step).
    pub anchor_init: bool,
    /// Downstream sites (peers, ADR 0007) users may reach through this
    /// gateway, under the same roles as the own site (`wy/<d>/x` is checked
    /// as `wy/<site>/x`). Writes carry a token for that site, which it
    /// trusts through its upstream as far as it allows (ADR 0018).
    pub downstream_sites: Vec<String>,
    /// The remote MCP endpoint `/mcp` with its OAuth 2.1 server (ADR 0041
    /// stage B); `None` = off.
    pub mcp: Option<McpConfig>,
    /// Device keys and the step-up (ADR 0050 §1.6).
    pub devices: DevicePolicy,
    /// What `GET /api/info` tells beyond the site (ADR 0050 §2.2).
    pub info: InfoConfig,
}

/// The parts of `GET /api/info` the broker knows (ADR 0050 §2).
#[derive(Debug, Clone, Default, PartialEq)]
pub struct InfoConfig {
    /// DER of the CA the gateway's certificate chains to: `ca` and `ca_fp` (for a client
    /// that pins it after a person compared the code).
    pub ca: Option<Vec<u8>>,
    /// The other broker of a standby pair, `host:port` of its gateway.
    pub pair: Option<String>,
    /// The upstream sites of this broker.
    pub up: Vec<String>,
}

impl GatewayConfig {
    /// Defaults: no TLS, 8 h sessions, the wiki's example roles.
    pub fn new(site: impl Into<String>, dir: impl Into<PathBuf>, listen: SocketAddr) -> Self {
        Self {
            site: site.into(),
            dir: dir.into(),
            listen,
            tls: None,
            session_ttl: SESSION_TTL,
            roles: RoleTable::default(),
            anchor: None,
            anchor_init: false,
            downstream_sites: Vec::new(),
            mcp: None,
            devices: DevicePolicy::default(),
            info: InfoConfig::default(),
        }
    }
}

/// Per-request tokens of one user: for the own site, and for a downstream
/// site with the own-site grants rewritten to it (`wy/<site>/…` →
/// `wy/<d>/…`, `wy/**` as it is) and the subject `user:<name>@<site>`
/// (ADR 0018). No token for other sites.
pub struct UserTokens {
    site: String,
    signing: SigningKey,
    sub: String,
    grants: Vec<wyrm_core::ptok::Grant>,
    max: Perm,
    downstream: Vec<String>,
}

impl UserTokens {
    fn for_site(&self, site: &str) -> wyrm_client::SigningTokens {
        let tokens = wyrm_client::SigningTokens::new(self.signing.clone(), site)
            .max(self.max)
            .ttl(PTOK_TTL);
        if site == self.site {
            return tokens.subject(&self.sub).grants(self.grants.clone());
        }
        let grants = self
            .grants
            .iter()
            .map(|g| wyrm_core::ptok::Grant {
                k: wyrm_core::ptok::grant_for_site(&g.k, &self.site, site),
                p: g.p,
            })
            .collect();
        tokens
            .subject(format!("{}@{}", self.sub, self.site))
            .grants(grants)
    }
}

impl UserTokens {
    /// A human approval of one step of an agent's plan (ADR 0049): a token for exactly the
    /// request `key`, capped at the `level` the step needs, good only for the request body
    /// that hashes to `body` (claim `args`, spec 04) and for [`approve::APPROVAL_TTL`].
    /// `None`: the site is out of reach or no grant of the user covers the key. The caller
    /// has checked that the user's level on `key` reaches `level`; a grant below it makes a
    /// token the responder refuses, never one that gives more.
    pub fn approval(&self, key: &str, level: Perm, body: [u8; 32]) -> Option<Vec<u8>> {
        use wyrm_client::TokenSource as _;
        let site = key.strip_prefix("wy/")?.split('/').next()?;
        if site != self.site && !self.downstream.iter().any(|d| d == site) {
            return None;
        }
        self.for_site(site)
            .max(level.min(self.max))
            .ttl(approve::APPROVAL_TTL)
            .bound_to(body)
            .token(key)
    }
}

/// A request the gateway refuses itself: a spec-04 status (≥ `0x20`) and a message.
#[derive(Debug, Clone, PartialEq)]
pub(crate) struct Refusal {
    pub status: wyrm_core::Status,
    pub message: String,
}

impl Refusal {
    pub(crate) fn new(status: wyrm_core::Status, message: impl Into<String>) -> Self {
        Self {
            status,
            message: message.into(),
        }
    }
}

impl wyrm_client::TokenSource for UserTokens {
    fn token(&self, key: &str) -> Option<Vec<u8>> {
        let site = key.strip_prefix("wy/")?.split('/').next()?;
        (site == self.site || self.downstream.iter().any(|d| d == site))
            .then(|| self.for_site(site).token(key))
            .flatten()
    }
}

/// Security events for the audit trail. Never carries passwords or tokens.
#[derive(Debug, Clone, PartialEq)]
#[non_exhaustive]
pub enum AuditEvent {
    LoginOk {
        user: String,
        ip: IpAddr,
    },
    /// `reason`: `bad_credentials`, `disabled` or `rate_limited`.
    LoginFailed {
        user: String,
        ip: IpAddr,
        reason: &'static str,
    },
    /// `change`: `add`, `password`, `roles`, `disabled`, `enabled`, `remove`.
    UserChanged {
        by: String,
        user: String,
        change: &'static str,
    },
    /// Refused by the gateway's own grant check (before Zenoh).
    Denied {
        user: String,
        op: String,
        key: String,
    },
    /// The user signed an MCP client in (ADR 0041): its name as it registered
    /// and what the person allowed.
    McpGranted {
        user: String,
        client: String,
        write: bool,
        config: bool,
    },
    /// The gateway signed approvals of an agent's plan for the user (ADR 0049): the task
    /// and the request keys of the steps, `skipped` those left out.
    Approved {
        user: String,
        task: String,
        steps: Vec<String>,
        skipped: usize,
    },
    /// A device key was registered (ADR 0050): its id, name and platform, never the key.
    DeviceAdded {
        user: String,
        device: String,
        name: String,
        platform: String,
        ip: IpAddr,
    },
    DeviceLogin {
        user: String,
        device: String,
        ip: IpAddr,
    },
    /// A device request refused: `code` is the refusal code, or for a bare refusal what was
    /// wrong (`unknown_device`, `bad_signature`, `bad_nonce`, `bad_registration`,
    /// `rate_limited`). `user` when the device is known.
    DeviceRefused {
        user: Option<String>,
        device: String,
        ip: IpAddr,
        code: &'static str,
    },
    /// A session confirmed with `method` `device` or `password`; `request` the hex hash the
    /// device signed (empty for the password).
    StepUp {
        user: String,
        method: &'static str,
        request: String,
    },
    DeviceRemoved {
        user: String,
        device: String,
        by: String,
    },
}

type AuditHook = Arc<dyn Fn(AuditEvent) + Send + Sync>;

/// An authenticated user, resolved against the store on every request.
#[derive(Debug, Clone)]
pub struct Principal {
    pub name: String,
    pub roles: Vec<String>,
    pub grants: Grants,
    pub claims: SessionClaims,
}

pub struct Gateway {
    cfg: GatewayConfig,
    users: Mutex<Store<UserDb>>,
    session_key: SessionKey,
    pub(crate) oauth: Option<oauth::OAuth>,
    signing: SigningKey,
    limiter: limit::LoginLimiter,
    /// Bounds concurrent argon2 runs (CPU and ~19 MiB each).
    pub(crate) hashing: Semaphore,
    /// Bounds concurrent `POST /api/invoke` bodies (up to 64 MiB each).
    bulk: Semaphore,
    /// Users with a `POST /api/invoke` in progress: one each (see
    /// [`Gateway::upload_slot`]).
    uploading: Mutex<std::collections::HashSet<String>>,
    audit: RwLock<Option<AuditHook>>,
    addr: watch::Sender<Option<SocketAddr>>,
    /// WebSocket tickets: hex(16 random bytes) → ticket.
    tickets: Mutex<std::collections::HashMap<String, Ticket>>,
    /// Downstream sites reached through this gateway (starts as
    /// `cfg.downstream_sites`; peers added at runtime change it).
    downstream_sites: RwLock<Vec<String>>,
    /// Other sites' points this site records (ADR 0020), followed while
    /// the gateway serves.
    sites: Arc<watch::Sender<Arc<overlay::Sites>>>,
    /// The ids of this site's agent links (driver `agent`), told by the broker
    /// ([`Gateway::set_agent_links`]): the only links whose tasks the gateway signs
    /// approvals for.
    agent_links: RwLock<Vec<String>>,
    /// Open WebSockets and the request bucket of each user (review GW-2).
    per_user: Mutex<std::collections::HashMap<String, UserUse>>,
    /// Live device challenges (ADR 0050).
    pub(crate) challenges: devices::Challenges,
    /// Step-ups and password checks of sessions after their login.
    pub(crate) fresh: devices::Fresh,
    pub(crate) challenge_limit: limit::RequestLimiter,
    pub(crate) info_limit: limit::RequestLimiter,
    /// The DNS and IP names of the gateway's certificate (default device origins).
    pub(crate) cert_names: Vec<String>,
    /// Upstream sites for `/api/info` (starts as `cfg.info.up`).
    up_sites: RwLock<Vec<String>>,
}

/// What one user holds over all their sockets.
struct UserUse {
    sockets: usize,
    tokens: f64,
    at: std::time::Instant,
}

/// WebSockets one user may hold open (review GW-2: tickets bounded only the live ones).
pub const SOCKETS_PER_USER: usize = 8;
/// Requests (one-shots and stream opens) per second over all of a user's sockets, and the
/// burst.
pub const REQUESTS_PER_S: f64 = 100.0;
pub const REQUEST_BURST: f64 = 200.0;
/// Rows one `history` request through the gateway may ask for.
pub const HISTORY_LIMIT: usize = 10_000;

/// One of a user's open WebSockets; dropping it frees the place.
pub(crate) struct SocketSlot {
    gw: Arc<Gateway>,
    user: String,
}

impl Drop for SocketSlot {
    fn drop(&mut self) {
        // the request bucket stays: a new socket must not start with a full burst (automated
        // review of aa55e96); idle entries go once their bucket would be full again
        let mut m = self.gw.per_user.lock().unwrap_or_else(|p| p.into_inner());
        if let Some(u) = m.get_mut(&self.user) {
            u.sockets = u.sockets.saturating_sub(1);
        }
    }
}

/// Seconds an empty bucket takes to fill.
const REFILL_S: f64 = REQUEST_BURST / REQUESTS_PER_S;

pub(crate) struct UploadSlot<'a> {
    gw: &'a Gateway,
    user: String,
}

impl Drop for UploadSlot<'_> {
    fn drop(&mut self) {
        self.gw
            .uploading
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .remove(&self.user);
    }
}

struct Ticket {
    session: Zeroizing<String>,
    user: String,
    exp: u64,
}

const TICKET_TTL_S: u64 = 30;
/// Live tickets per user; a new one replaces that user's oldest.
const TICKETS_PER_USER: usize = 8;

impl Gateway {
    /// Open the user store and the signing key (`<dir>/gateway.key`, 0600,
    /// created on first start). `hmac_key` keys the WAL chain; the session
    /// MAC key is derived from it.
    pub fn open(cfg: GatewayConfig, hmac_key: &[u8]) -> Result<Arc<Self>> {
        wyrm_core::keyspace::validate_segment(&cfg.site)
            .map_err(|e| Error::Config(format!("site: {e}")))?;
        cfg.roles.validate(&cfg.site).map_err(Error::Config)?;
        if cfg.tls.is_none() && !cfg.listen.ip().is_loopback() {
            return Err(Error::Config(format!(
                "gateway on {} needs TLS (plain HTTP only on loopback)",
                cfg.listen
            )));
        }
        let mut users = Store::<UserDb>::open(cfg.dir.join("users"), hmac_key)?;
        if let Some(a) = &cfg.anchor {
            users = if cfg.anchor_init {
                users.init_anchor(a)?
            } else {
                users.with_anchor(a)?
            };
        }
        if cfg.mcp.is_some() && !cfg!(feature = "mcp") {
            return Err(Error::Config(
                "gateway.mcp: this build has no MCP endpoint (feature `mcp`)".into(),
            ));
        }
        let signing = load_or_create_key(&cfg.dir.join("gateway.key"))?;
        let cert_names = match &cfg.tls {
            Some((cert, _)) => devices::cert_names(&std::fs::read(cert)?),
            None => Vec::new(),
        };
        Ok(Arc::new(Self {
            session_key: SessionKey::derive(hmac_key),
            oauth: match &cfg.mcp {
                Some(m) => Some(oauth::OAuth::new(m.clone(), hmac_key).map_err(Error::Config)?),
                None => None,
            },
            signing,
            users: Mutex::new(users),
            limiter: limit::LoginLimiter::new(LOGIN_FAILURES, LOGIN_WINDOW),
            hashing: Semaphore::new(4),
            bulk: Semaphore::new(2),
            uploading: Mutex::new(Default::default()),
            audit: RwLock::new(None),
            addr: watch::channel(None).0,
            tickets: Mutex::new(Default::default()),
            downstream_sites: RwLock::new(cfg.downstream_sites.clone()),
            sites: Arc::new(watch::channel(Arc::default()).0),
            agent_links: RwLock::new(Vec::new()),
            per_user: Mutex::new(Default::default()),
            challenges: Default::default(),
            fresh: Default::default(),
            challenge_limit: limit::RequestLimiter::new(CHALLENGES_PER_MIN, LOGIN_WINDOW),
            info_limit: limit::RequestLimiter::new(INFO_PER_MIN, LOGIN_WINDOW),
            cert_names,
            up_sites: RwLock::new(cfg.info.up.clone()),
            cfg,
        }))
    }

    /// A place for one more WebSocket of `user`; `None` at [`SOCKETS_PER_USER`].
    pub(crate) fn socket_slot(self: &Arc<Self>, user: &str) -> Option<SocketSlot> {
        let mut m = self.per_user.lock().unwrap_or_else(|p| p.into_inner());
        if m.len() >= 1024 {
            m.retain(|_, u| u.sockets > 0 || u.at.elapsed().as_secs_f64() < REFILL_S);
        }
        let u = m.entry(user.to_owned()).or_insert(UserUse {
            sockets: 0,
            tokens: REQUEST_BURST,
            at: std::time::Instant::now(),
        });
        if u.sockets >= SOCKETS_PER_USER {
            return None;
        }
        u.sockets += 1;
        Some(SocketSlot {
            gw: self.clone(),
            user: user.to_owned(),
        })
    }

    /// One request of `user` (over all their sockets): `false` past [`REQUESTS_PER_S`].
    pub(crate) fn request_allowed(&self, user: &str) -> bool {
        let mut m = self.per_user.lock().unwrap_or_else(|p| p.into_inner());
        let Some(u) = m.get_mut(user) else {
            return true; // no socket: not a WebSocket request
        };
        if u.sockets == 0 {
            return true;
        }
        let now = std::time::Instant::now();
        u.tokens =
            (u.tokens + now.duration_since(u.at).as_secs_f64() * REQUESTS_PER_S).min(REQUEST_BURST);
        u.at = now;
        if u.tokens < 1.0 {
            return false;
        }
        u.tokens -= 1.0;
        true
    }

    /// A single-use WebSocket ticket for a valid `session` token.
    pub fn ws_ticket(&self, session: &str) -> Option<(String, u64)> {
        let p = self.authenticate(session)?;
        let now = session::now_s();
        let mut raw = [0u8; 16];
        getrandom::fill(&mut raw).ok()?;
        let ticket: String = raw.iter().map(|b| format!("{b:02x}")).collect();
        let exp = now + TICKET_TTL_S;
        let mut t = self.tickets.lock().unwrap_or_else(|p| p.into_inner());
        // Live tickets are bounded by users × TICKETS_PER_USER: one user
        // cannot crowd out the others.
        t.retain(|_, k| k.exp > now);
        let mut mine: Vec<(u64, String)> = t
            .iter()
            .filter(|(_, k)| k.user == p.name)
            .map(|(id, k)| (k.exp, id.clone()))
            .collect();
        if mine.len() >= TICKETS_PER_USER {
            mine.sort();
            for (_, id) in &mine[..=mine.len() - TICKETS_PER_USER] {
                t.remove(id);
            }
        }
        t.insert(
            ticket.clone(),
            Ticket {
                session: Zeroizing::new(session.to_owned()),
                user: p.name,
                exp,
            },
        );
        Some((ticket, exp))
    }

    /// Spend a ticket: the principal of its session, checked again now.
    pub fn redeem_ticket(&self, ticket: &str) -> Option<Principal> {
        let k = self
            .tickets
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .remove(ticket)?;
        if session::now_s() >= k.exp {
            return None;
        }
        self.authenticate(&k.session)
    }

    pub fn site(&self) -> &str {
        &self.cfg.site
    }

    /// The downstream site `key` belongs to, if it is one of `downstream_sites`.
    pub fn downstream_site_of(&self, key: &str) -> Option<String> {
        let rest = key.strip_prefix("wy/")?;
        let site = rest.split('/').next()?;
        self.downstream_sites
            .read()
            .unwrap_or_else(|p| p.into_inner())
            .iter()
            .find(|s| s.as_str() == site)
            .cloned()
    }

    /// The one `POST /api/invoke` slot of `user`; `None` while another of
    /// theirs runs. Freed when the guard drops.
    pub(crate) fn upload_slot(&self, user: &str) -> Option<UploadSlot<'_>> {
        let mut u = self.uploading.lock().unwrap_or_else(|p| p.into_inner());
        u.insert(user.to_owned()).then(|| UploadSlot {
            gw: self,
            user: user.to_owned(),
        })
    }

    /// The upstream sites `/api/info` names (the broker's peers above).
    pub fn set_upstream_sites(&self, sites: Vec<String>) {
        *self.up_sites.write().unwrap_or_else(|p| p.into_inner()) = sites;
    }

    /// `GET /api/info` (ADR 0050 §2.2): no user, no key, nothing a session would tell.
    pub fn info(&self) -> wyrm_core::Value {
        use wyrm_core::Value;
        let mut m = std::collections::BTreeMap::from([
            ("site".to_owned(), Value::from(self.cfg.site.as_str())),
            ("version".to_owned(), Value::from(env!("CARGO_PKG_VERSION"))),
            ("tls".to_owned(), Value::Bool(self.cfg.tls.is_some())),
            ("role".to_owned(), Value::from("active")),
            ("devices".to_owned(), self.cfg.devices.to_value()),
            ("min_studio".to_owned(), Value::from(MIN_STUDIO)),
            (
                "up".to_owned(),
                Value::Array(
                    self.up_sites
                        .read()
                        .unwrap_or_else(|p| p.into_inner())
                        .iter()
                        .map(|s| Value::from(s.as_str()))
                        .collect(),
                ),
            ),
        ]);
        if let Some(ca) = self.cfg.info.ca.as_ref().filter(|_| self.cfg.tls.is_some()) {
            m.insert("ca_fp".into(), Value::Str(devices::ca_fingerprint(ca)));
            m.insert("ca".into(), Value::Bytes(ca.clone()));
        }
        if let Some(p) = &self.cfg.info.pair {
            m.insert("pair".into(), Value::from(p.as_str()));
        }
        Value::Map(m)
    }

    /// Downstream sites reached through the gateway (the broker's peers).
    pub fn set_downstream_sites(&self, sites: Vec<String>) {
        *self
            .downstream_sites
            .write()
            .unwrap_or_else(|p| p.into_inner()) = sites;
    }

    /// The agent links of this site (their link ids), from the broker's registry. The
    /// gateway signs approvals only for tasks of these links (ADR 0049): a link cannot make
    /// itself one, whatever it serves under its own subtree.
    pub fn set_agent_links(&self, links: Vec<String>) {
        *self.agent_links.write().unwrap_or_else(|p| p.into_inner()) = links;
    }

    /// The task id when `key` is `wy/<this site>/downstream/<agent link>/tasks/<id>`.
    pub(crate) fn agent_task(&self, key: &str) -> Option<String> {
        let rest = key.strip_prefix(&format!("wy/{}/downstream/", self.cfg.site))?;
        let mut parts = rest.split('/');
        let (link, tasks, id) = (parts.next()?, parts.next()?, parts.next()?);
        let known = self
            .agent_links
            .read()
            .unwrap_or_else(|p| p.into_inner())
            .iter()
            .any(|l| l == link);
        (known && tasks == "tasks" && parts.next().is_none()).then(|| id.to_owned())
    }

    /// `key` with a downstream site's prefix replaced by the own site's (roles
    /// are written for the own site); other keys unchanged.
    pub fn as_own(&self, key: &str) -> String {
        match self.downstream_site_of(key) {
            Some(d) => format!("wy/{}{}", self.cfg.site, &key[3 + d.len()..]),
            None => key.to_owned(),
        }
    }

    /// Key that links must trust (`LinkConfig::admin_keys`) for gateway ptoks.
    pub fn verifying_key(&self) -> VerifyingKey {
        self.signing.verifying_key()
    }

    pub fn set_audit(&self, hook: impl Fn(AuditEvent) + Send + Sync + 'static) {
        *self.audit.write().unwrap_or_else(|p| p.into_inner()) = Some(Arc::new(hook));
    }

    pub(crate) fn audit(&self, ev: AuditEvent) {
        let hook = self.audit.read().unwrap_or_else(|p| p.into_inner()).clone();
        if let Some(h) = hook {
            h(ev);
        }
    }

    /// Address the server is bound to, once [`Gateway::serve`] has bound it.
    pub fn bound_addr(&self) -> Option<SocketAddr> {
        *self.addr.borrow()
    }

    /// Wait until [`Gateway::serve`] has bound its listener.
    pub async fn local_addr(&self) -> SocketAddr {
        let mut rx = self.addr.subscribe();
        loop {
            if let Some(a) = *rx.borrow_and_update() {
                return a;
            }
            if rx.changed().await.is_err() {
                std::future::pending::<()>().await;
            }
        }
    }

    pub(crate) fn store(&self) -> std::sync::MutexGuard<'_, Store<UserDb>> {
        self.users.lock().unwrap_or_else(|p| p.into_inner())
    }

    pub fn user(&self, name: &str) -> Option<User> {
        self.store().state().users.get(name).cloned()
    }

    /// `(name, roles, disabled)` of every user.
    pub fn list_users(&self) -> Vec<(String, Vec<String>, bool)> {
        self.store()
            .state()
            .users
            .iter()
            .map(|(n, u)| (n.clone(), u.roles.clone(), u.disabled))
            .collect()
    }

    /// Bootstrap: create `name` with the `admin` role if no such user exists.
    /// Returns `true` if it was created. Blocking (argon2).
    pub fn ensure_admin(&self, name: &str, password: &str) -> Result<bool> {
        if self.user(name).is_some() {
            return Ok(false);
        }
        if !self.role_table().contains("admin") {
            return Err(Error::Config("no `admin` role in the role table".into()));
        }
        self.add_user(name, password, vec!["admin".into()])?;
        info!(user = name, "gateway: bootstrap admin created");
        Ok(true)
    }

    fn check_roles(&self, roles: &[String]) -> Result<()> {
        let table = self.role_table();
        match roles.iter().find(|r| !table.contains(r)) {
            Some(r) => Err(Error::Rejected(format!("unknown role {r}"))),
            None => Ok(()),
        }
    }

    /// Blocking (argon2).
    pub fn add_user(&self, name: &str, password: &str, roles: Vec<String>) -> Result<()> {
        if !users::valid_name(name) {
            return Err(Error::Rejected(format!("invalid user name {name:?}")));
        }
        users::check_password(password).map_err(Error::Rejected)?;
        self.check_roles(&roles)?;
        let hash = users::hash_password(password).map_err(Error::Rejected)?;
        self.store().apply(Op::AddUser {
            name: name.into(),
            hash,
            roles,
        })?;
        Ok(())
    }

    /// Blocking (argon2). Ends the user's sessions.
    pub fn set_password(&self, name: &str, password: &str) -> Result<()> {
        users::check_password(password).map_err(Error::Rejected)?;
        let hash = users::hash_password(password).map_err(Error::Rejected)?;
        self.store().apply(Op::SetPassword {
            name: name.into(),
            hash,
        })?;
        Ok(())
    }

    pub fn set_roles(&self, name: &str, roles: Vec<String>) -> Result<()> {
        self.check_roles(&roles)?;
        self.store().apply(Op::SetRoles {
            name: name.into(),
            roles,
        })?;
        Ok(())
    }

    /// Disabling ends the user's sessions.
    pub fn set_disabled(&self, name: &str, disabled: bool) -> Result<()> {
        self.store().apply(Op::Disable {
            name: name.into(),
            disabled,
        })?;
        Ok(())
    }

    pub fn remove_user(&self, name: &str) -> Result<()> {
        self.store().apply(Op::RemoveUser(name.into()))?;
        Ok(())
    }

    pub fn grants_of(&self, roles: &[String]) -> Grants {
        self.role_table().grants(&self.cfg.site, roles)
    }

    /// The configured roles with the runtime changes from the store on top.
    pub fn role_table(&self) -> RoleTable {
        self.table_of(self.store().state())
    }

    fn table_of(&self, db: &UserDb) -> RoleTable {
        let mut t = self.cfg.roles.clone();
        for (role, grants) in &db.roles {
            let grants = grants
                .iter()
                .filter_map(|(k, c)| Some((k.clone(), Perm::try_from(*c).ok()?)))
                .collect();
            t.insert(role.clone(), grants);
        }
        t
    }

    /// Remove each grant on exactly one of `keys` that gives its role more
    /// on `probe` than the role's other grants would (it widens access);
    /// restrictive and neutral grants stay. Returns `(role, key, level)` of
    /// each removed grant. Used when a link goes away (ADR 0006).
    pub fn revoke_widening(
        &self,
        keys: &[String],
        probe: &str,
    ) -> Result<Vec<(String, String, Perm)>> {
        let mut out = Vec::new();
        for (role, grants) in self.role_table().iter() {
            for (k, p) in grants.iter().filter(|(k, _)| keys.contains(k)) {
                let rest: Vec<(String, Perm)> =
                    grants.iter().filter(|(k2, _)| k2 != k).cloned().collect();
                let mut alone = RoleTable::empty();
                alone.insert(role, rest);
                let without = alone.grants(&self.cfg.site, &[role.to_owned()]).perm(probe);
                if *p > without {
                    out.push((role.to_owned(), k.clone(), *p));
                }
            }
        }
        for (role, k, _) in &out {
            self.set_grant(role, k, Perm::None)?;
        }
        Ok(out)
    }

    /// Add, change or (at `none`) remove the grant on `key` of `role`; a new
    /// role starts empty. Refused when no enabled user would keep `config`
    /// on `wy/<site>/sys/**` (user management needs one). Sessions see the
    /// change on their next request.
    pub fn set_grant(&self, role: &str, key: &str, level: Perm) -> Result<()> {
        if !users::valid_name(role) {
            return Err(Error::Rejected(format!("invalid role name {role:?}")));
        }
        let concrete = key.replace("{site}", &self.cfg.site);
        if !concrete.starts_with("wy/") {
            return Err(Error::Rejected(format!("{key}: grants are on wy/**")));
        }
        zenoh::key_expr::keyexpr::new(&concrete)
            .map_err(|e| Error::Rejected(format!("{key}: {e}")))?;
        let mut store = self.store();
        let mut table = self.table_of(store.state());
        let grants = roles::with_grant(table.get(role).unwrap_or_default(), key, level)
            .map_err(Error::Rejected)?;
        table.insert(role, grants.clone());
        let sys = format!("wy/{}/sys/**", self.cfg.site);
        let admin_left = store.state().users.values().any(|u| {
            !u.disabled
                && table
                    .grants(&self.cfg.site, &u.roles)
                    .covers(&sys, Perm::Config)
        });
        if !admin_left {
            return Err(Error::Rejected(
                "no enabled user would keep config on sys/** (user management)".into(),
            ));
        }
        store.apply(Op::SetRole {
            role: role.into(),
            grants: grants.iter().map(|(k, p)| (k.clone(), p.code())).collect(),
        })?;
        Ok(())
    }

    /// Verify a session token and resolve it against the store: the user
    /// must exist, be enabled and have the same generation as at login.
    /// Grants come from the roles in the store now, not from the token.
    pub fn authenticate(&self, token: &str) -> Option<Principal> {
        let claims = self.session_key.verify(token, session::now_s())?;
        self.resolve(claims)
    }

    pub(crate) fn resolve(&self, claims: SessionClaims) -> Option<Principal> {
        let u = self.user(&claims.sub)?;
        if u.disabled || u.gen != claims.gen || session::now_s() >= claims.exp {
            return None;
        }
        // a device login ends with its device (removed, forgotten, signed out)
        if let Some(id) = &claims.dev {
            let store = self.store();
            let db = store.state();
            let d = db.devices.get(id)?;
            if d.user != claims.sub || !db.device_active(d) {
                return None;
            }
        }
        Some(Principal {
            name: claims.sub.clone(),
            grants: self.grants_of(&u.roles),
            roles: u.roles,
            claims,
        })
    }

    /// Refuse a locked `(user, ip)` before any hashing: callers check it
    /// before they wait for a hashing permit (review GW-7). The refusal is
    /// audited once per window, not per attempt (GW-1).
    pub(crate) fn check_limit(&self, user: &str, ip: IpAddr) -> Result<(), LoginError> {
        if self.limiter.allowed(user, ip) {
            return Ok(());
        }
        if self.limiter.note_refusal(user, ip) {
            self.audit(AuditEvent::LoginFailed {
                user: user.into(),
                ip,
                reason: "rate_limited",
            });
        }
        Err(LoginError::RateLimited)
    }

    /// Check `user`/`password` (rate limited per user and address) and mint
    /// a session. The caller runs this on a blocking thread.
    fn login(
        &self,
        user: &str,
        password: Zeroizing<String>,
        device: Option<&str>,
        ip: IpAddr,
    ) -> Result<(String, u64), LoginError> {
        let (roles, gen) = self.verify_login(user, password, ip)?;
        // the device saw the password: its `password_due` starts again (ADR 0050)
        if let Some(d) = device {
            self.password_seen(user, d);
        }
        let iat = session::now_s();
        let exp = iat + self.cfg.session_ttl.as_secs().max(1);
        let claims = SessionClaims {
            sub: user.into(),
            roles,
            exp,
            iat,
            jti: session::new_jti(),
            gen,
            amr: session::Amr::Password,
            auth_at: iat,
            dev: None,
        };
        Ok((self.session_key.mint(&claims), exp))
    }

    /// Check `user`/`password` (rate limited per user and address, audited);
    /// the user's roles and generation. On a blocking thread.
    pub(crate) fn verify_login(
        &self,
        user: &str,
        password: Zeroizing<String>,
        ip: IpAddr,
    ) -> Result<(Vec<String>, u64), LoginError> {
        self.check_limit(user, ip)?;
        let rec = self.user(user);
        let ok = users::verify_password(&password, rec.as_ref().map(|u| u.hash.as_str()));
        let rec = match rec {
            Some(u) if ok && !u.disabled => u,
            other => {
                self.limiter.failed(user, ip);
                let reason = match other {
                    Some(u) if ok && u.disabled => "disabled",
                    _ => "bad_credentials",
                };
                self.audit(AuditEvent::LoginFailed {
                    user: user.into(),
                    ip,
                    reason,
                });
                return Err(LoginError::Invalid);
            }
        };
        self.limiter.succeeded(user, ip);
        self.audit(AuditEvent::LoginOk {
            user: user.into(),
            ip,
        });
        Ok((rec.roles.clone(), rec.gen))
    }

    /// A ptok source for `p`: subject `user:<name>`, the user's grants and
    /// max, 5 min lifetime, one token per request scoped to its key.
    pub fn tokens_for(&self, p: &Principal) -> UserTokens {
        UserTokens {
            site: self.cfg.site.clone(),
            signing: self.signing.clone(),
            sub: format!("user:{}", p.name),
            grants: p.grants.list.clone(),
            max: p.grants.max,
            downstream: self
                .downstream_sites
                .read()
                .unwrap_or_else(|p| p.into_inner())
                .clone(),
        }
    }

    /// May `p` manage users: `config` on all of `wy/<site>/sys/**`.
    pub fn is_admin(&self, p: &Principal) -> bool {
        p.grants
            .covers(&format!("wy/{}/sys/**", self.cfg.site), Perm::Config)
    }

    /// Serve until `shutdown` resolves. Binds `cfg.listen` (see
    /// [`Gateway::local_addr`]); TLS uses rustls with the ring provider.
    pub async fn serve(
        self: Arc<Self>,
        session: zenoh::Session,
        shutdown: impl Future + Send,
    ) -> Result<()> {
        http::serve(self, session, shutdown).await
    }
}

#[derive(Debug)]
enum LoginError {
    Invalid,
    RateLimited,
}

/// Read the 32-byte Ed25519 seed, or create it (0600) if the file is absent.
/// An unreadable or malformed file is an error: a silent new key would break
/// trust with every link.
fn load_or_create_key(path: &Path) -> Result<SigningKey> {
    match std::fs::read(path) {
        Ok(raw) => {
            let raw = Zeroizing::new(raw);
            let seed: [u8; 32] = raw
                .as_slice()
                .try_into()
                .map_err(|_| Error::Config(format!("{}: expected 32 bytes", path.display())))?;
            Ok(SigningKey::from_bytes(&seed))
        }
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
            let mut seed = Zeroizing::new([0u8; 32]);
            getrandom::fill(seed.as_mut())
                .map_err(|e| Error::Config(format!("no randomness: {e}")))?;
            write_private(path, seed.as_ref())?;
            info!(path = %path.display(), "gateway: new signing key");
            Ok(SigningKey::from_bytes(&seed))
        }
        Err(e) => Err(e.into()),
    }
}

/// Write a file readable by the owner only (created fresh, 0600 on unix).
fn write_private(path: &Path, data: &[u8]) -> std::io::Result<()> {
    use std::io::Write;
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir)?;
    }
    let tmp = path.with_extension("tmp");
    let _ = std::fs::remove_file(&tmp);
    {
        let mut opts = std::fs::OpenOptions::new();
        opts.write(true).create_new(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            opts.mode(0o600);
        }
        let mut f = opts.open(&tmp)?;
        f.write_all(data)?;
        f.sync_all()?;
    }
    std::fs::rename(&tmp, path)
}
