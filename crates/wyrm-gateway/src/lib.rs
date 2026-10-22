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
//!   frames, see [`ws`]
//! * user management (`config` on `wy/<site>/sys/**`): `GET|POST /api/users`,
//!   `POST /api/users/{name}/password|roles|disabled`, `DELETE /api/users/{name}`

#![forbid(unsafe_code)]

mod http;
mod limit;
pub mod roles;
pub mod session;
pub mod users;
pub mod ws;

pub use roles::{with_grant, Grants, RoleTable};
pub use session::SessionClaims;

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
    /// Downstream sites (peers, ADR 0007) whose trees users may browse:
    /// read operations only, under the same roles as the own site
    /// (`wy/<d>/x` is checked as `wy/<site>/x`), without a ptok (the
    /// downstream links do not trust this gateway's key).
    pub read_sites: Vec<String>,
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
            read_sites: Vec::new(),
        }
    }
}

/// Per-request tokens for the own site only: requests to a read site go
/// without one (its links would refuse a token they do not trust).
pub struct OwnSiteTokens {
    root: String,
    inner: wyrm_client::SigningTokens,
}

impl wyrm_client::TokenSource for OwnSiteTokens {
    fn token(&self, key: &str) -> Option<Vec<u8>> {
        let own = key == self.root
            || key
                .strip_prefix(self.root.as_str())
                .is_some_and(|r| r.starts_with('/'));
        own.then(|| self.inner.token(key)).flatten()
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
    signing: SigningKey,
    limiter: limit::LoginLimiter,
    /// Bounds concurrent argon2 runs (CPU and ~19 MiB each).
    hashing: Semaphore,
    audit: RwLock<Option<AuditHook>>,
    addr: watch::Sender<Option<SocketAddr>>,
    /// WebSocket tickets: hex(16 random bytes) → ticket.
    tickets: Mutex<std::collections::HashMap<String, Ticket>>,
    /// Downstream sites read through this gateway (starts as
    /// `cfg.read_sites`; peers added at runtime change it).
    read_sites: RwLock<Vec<String>>,
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
        let signing = load_or_create_key(&cfg.dir.join("gateway.key"))?;
        Ok(Arc::new(Self {
            session_key: SessionKey::derive(hmac_key),
            signing,
            users: Mutex::new(users),
            limiter: limit::LoginLimiter::new(LOGIN_FAILURES, LOGIN_WINDOW),
            hashing: Semaphore::new(4),
            audit: RwLock::new(None),
            addr: watch::channel(None).0,
            tickets: Mutex::new(Default::default()),
            read_sites: RwLock::new(cfg.read_sites.clone()),
            cfg,
        }))
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

    /// The downstream site `key` belongs to, if it is one of `read_sites`.
    pub fn read_site_of(&self, key: &str) -> Option<String> {
        let rest = key.strip_prefix("wy/")?;
        let site = rest.split('/').next()?;
        self.read_sites
            .read()
            .unwrap_or_else(|p| p.into_inner())
            .iter()
            .find(|s| s.as_str() == site)
            .cloned()
    }

    /// Downstream sites readable through the gateway (the broker's peers).
    pub fn set_read_sites(&self, sites: Vec<String>) {
        *self.read_sites.write().unwrap_or_else(|p| p.into_inner()) = sites;
    }

    /// `key` with a read site's prefix replaced by the own site's (roles
    /// are written for the own site); other keys unchanged.
    pub fn as_own(&self, key: &str) -> String {
        match self.read_site_of(key) {
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

    fn audit(&self, ev: AuditEvent) {
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

    fn store(&self) -> std::sync::MutexGuard<'_, Store<UserDb>> {
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

    fn resolve(&self, claims: SessionClaims) -> Option<Principal> {
        let u = self.user(&claims.sub)?;
        if u.disabled || u.gen != claims.gen || session::now_s() >= claims.exp {
            return None;
        }
        Some(Principal {
            name: claims.sub.clone(),
            grants: self.grants_of(&u.roles),
            roles: u.roles,
            claims,
        })
    }

    /// Check `user`/`password` (rate limited per user and address) and mint
    /// a session. The caller runs this on a blocking thread.
    fn login(
        &self,
        user: &str,
        password: Zeroizing<String>,
        ip: IpAddr,
    ) -> Result<(String, u64), LoginError> {
        if !self.limiter.allowed(user, ip) {
            self.audit(AuditEvent::LoginFailed {
                user: user.into(),
                ip,
                reason: "rate_limited",
            });
            return Err(LoginError::RateLimited);
        }
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
        let iat = session::now_s();
        let exp = iat + self.cfg.session_ttl.as_secs().max(1);
        let claims = SessionClaims {
            sub: user.into(),
            roles: rec.roles.clone(),
            exp,
            iat,
            jti: session::new_jti(),
            gen: rec.gen,
        };
        self.audit(AuditEvent::LoginOk {
            user: user.into(),
            ip,
        });
        Ok((self.session_key.mint(&claims), exp))
    }

    /// A ptok source for `p`: subject `user:<name>`, the user's grants and
    /// max, 5 min lifetime, one token per request scoped to its key.
    pub fn tokens_for(&self, p: &Principal) -> OwnSiteTokens {
        OwnSiteTokens {
            root: format!("wy/{}", self.cfg.site),
            inner: wyrm_client::SigningTokens::new(self.signing.clone(), &self.cfg.site)
                .subject(format!("user:{}", p.name))
                .grants(p.grants.list.clone())
                .max(p.grants.max)
                .ttl(PTOK_TTL),
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
