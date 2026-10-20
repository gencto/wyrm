//! `wyrmd`: Zenoh router runtime + static plugins + `wyrm-admin` + links.
//!
//! [`Daemon`] owns what survives a reload (the admin [`Control`]: registry,
//! CA, supervisor, audit; the flow store and signing key). A [`Broker`] is one router runtime with its
//! plugins and in-process sessions; it is rebuilt when the ACL changes,
//! because Zenoh 1.10 cannot reload `access_control` live (ADR 0004).

#![forbid(unsafe_code)]

use serde::Deserialize;
use std::collections::BTreeMap;
use std::future::Future;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::oneshot;
use wyrm_admin::{
    Attached, ConfigLink, Control, ControlConfig, EmbeddedHost, Mode, PeerConfig, RunningLink,
};
use wyrm_core::Value;
use wyrm_flow::{Engine, EngineStart, FlowHost};
use wyrm_gateway::{AuditEvent, Gateway, GatewayConfig};
use wyrm_link_mock::df::MockDev;
use wyrm_link_mock::{Mock, MockConfig};
use wyrm_link_modbus::Modbus;
use wyrm_link_sdk::driver::{Framework, Tree};
use wyrm_link_sdk::{FromParams, Link, LinkConfig, LinkError, LinkHandle, VerifyingKey};
use zenoh::internal::plugins::PluginsManager;
use zenoh::internal::runtime::{Runtime, RuntimeBuilder};
use zenoh::Session;
use zenoh_plugin_rest::RestPlugin;
use zenoh_plugin_storage_manager::StoragesPlugin;

pub type Error = zenoh::Error;

/// `wyrmd.json5`. Unknown fields are rejected.
#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Config {
    pub site: String,
    /// `prod` (default): loopback sessions are requesters only. `dev`:
    /// loopback may do everything (external mock binary, benchmarks).
    #[serde(default)]
    pub profile: Profile,
    #[serde(default = "default_data_dir")]
    pub data_dir: PathBuf,
    #[serde(default = "default_listen")]
    pub listen: Vec<String>,
    #[serde(default)]
    pub connect: Vec<String>,
    /// SANs of the broker certificate (for `tls/` listeners).
    #[serde(default = "default_tls_names")]
    pub tls_names: Vec<String>,
    #[serde(default)]
    pub multicast_scouting: bool,
    /// Allow plaintext `tcp/udp/ws` endpoints off loopback (principle 6:
    /// TLS everywhere except loopback/UDS).
    #[serde(default)]
    pub insecure_plaintext: bool,
    /// Admin `ptok` public keys (32 bytes hex): active, then previous.
    #[serde(default)]
    pub admin_keys: Vec<String>,
    /// Certificate CNs of engineering tools with requester rights.
    #[serde(default)]
    pub operators: Vec<String>,
    /// Links started with the broker, by link id.
    #[serde(default)]
    pub links: BTreeMap<String, LinkSection>,
    /// Zenoh REST plugin listen address (`127.0.0.1:8000`). REST cannot
    /// carry a `ptok`, so `set`/`invoke` through it are denied.
    #[serde(default)]
    pub rest: Option<std::net::SocketAddr>,
    #[serde(default = "default_metrics_ms")]
    pub metrics_interval_ms: u64,
    #[serde(default = "default_restarts")]
    pub max_restarts: u32,
    /// Router-to-router links to other sites (iteration 4), QUIC + mTLS.
    #[serde(default)]
    pub peers: PeersSection,
    /// User gateway (HTTP + WebSocket, iteration 5). Off when absent.
    #[serde(default)]
    pub gateway: Option<GatewaySection>,
}

/// The first admin's password comes from `WYRM_GATEWAY_ADMIN_PASSWORD` at
/// start (only if the user does not exist yet), never from this file.
#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct GatewaySection {
    pub listen: std::net::SocketAddr,
    /// Certificate chain and key (PEM); required off loopback.
    #[serde(default)]
    pub tls_cert: Option<PathBuf>,
    #[serde(default)]
    pub tls_key: Option<PathBuf>,
    #[serde(default)]
    pub session_ttl_s: Option<u64>,
    /// Name of the first admin user.
    #[serde(default = "default_gateway_admin")]
    pub admin_user: String,
}

fn default_gateway_admin() -> String {
    "admin".into()
}

pub const GATEWAY_ADMIN_PASSWORD_ENV: &str = "WYRM_GATEWAY_ADMIN_PASSWORD";

/// Brokers of other sites. Each side trusts the other's CA only on the QUIC
/// broker link; the generated ACL lets an upstream site read our
/// `down/**` and `flows/**` (commands still need a `ptok` from our admin)
/// and lets a downstream site serve its own `wy/<site>/**`.
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PeersSection {
    /// QUIC listener for downstream brokers (`quic/0.0.0.0:7448`).
    #[serde(default)]
    pub listen: Option<String>,
    /// Sites this broker connects to.
    #[serde(default)]
    pub upstream: Vec<UpstreamPeer>,
    /// Sites that connect to this broker.
    #[serde(default)]
    pub downstream: Vec<DownstreamPeer>,
    /// Max rate per key of `~val` samples sent over QUIC (Hz); none = all.
    #[serde(default)]
    pub upstream_val_hz: Option<f64>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct UpstreamPeer {
    pub site: String,
    /// `quic/<host>:<port>`; the host must be a SAN of its broker certificate.
    pub endpoint: String,
    /// CA certificate (PEM) of that site.
    pub ca: PathBuf,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DownstreamPeer {
    pub site: String,
    /// CA certificate (PEM) of that site.
    pub ca: PathBuf,
}

impl PeersSection {
    fn is_empty(&self) -> bool {
        self.upstream.is_empty() && self.downstream.is_empty()
    }

    fn validate(&self, own_site: &str) -> Result<(), Error> {
        let quic = |what: &str, ep: &str| -> Result<(), Error> {
            if !ep.starts_with("quic/") || ep.contains(['#', '?']) {
                return Err(format!("{what} {ep}: expected quic/<host>:<port>").into());
            }
            Ok(())
        };
        let path = |what: &str, p: &std::path::Path| -> Result<(), Error> {
            // Endpoint parameters are `;`-separated.
            if p.to_str().is_none_or(|s| s.contains([';', '#', '?'])) {
                return Err(
                    format!("{what} {}: path must be UTF-8 without ; # ?", p.display()).into(),
                );
            }
            Ok(())
        };
        let mut seen = std::collections::HashSet::new();
        for (site, kind) in self
            .upstream
            .iter()
            .map(|u| (&u.site, "upstream"))
            .chain(self.downstream.iter().map(|d| (&d.site, "downstream")))
        {
            wyrm_core::keyspace::validate_segment(site)
                .map_err(|e| format!("peers.{kind} site: {e}"))?;
            if site == own_site || !seen.insert(site.clone()) {
                return Err(format!("peers.{kind}: site {site} repeated or own").into());
            }
        }
        for u in &self.upstream {
            quic("peers.upstream endpoint", &u.endpoint)?;
            path("peers.upstream ca", &u.ca)?;
        }
        for d in &self.downstream {
            path("peers.downstream ca", &d.ca)?;
        }
        match (&self.listen, self.downstream.is_empty()) {
            (Some(ep), false) => quic("peers.listen", ep)?,
            (Some(_), true) => return Err("peers.listen without peers.downstream".into()),
            (None, false) => return Err("peers.downstream needs peers.listen".into()),
            (None, true) => {}
        }
        if let Some(hz) = self.upstream_val_hz {
            if !(hz.is_finite() && hz > 0.0) {
                return Err("peers.upstream_val_hz: expected > 0".into());
            }
        }
        Ok(())
    }

    fn peer_config(&self) -> PeerConfig {
        PeerConfig {
            peers: wyrm_admin::acl::Peers {
                upstream: self.upstream.iter().map(|u| u.site.clone()).collect(),
                downstream: self.downstream.iter().map(|d| d.site.clone()).collect(),
            },
            trusted_cas: self.downstream.iter().map(|d| d.ca.clone()).collect(),
        }
    }
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Profile {
    #[default]
    Prod,
    Dev,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct LinkSection {
    pub driver: String,
    /// `embedded` (default) | `process` | `external`.
    #[serde(default)]
    pub mode: Option<String>,
    #[serde(default)]
    pub params: serde_json::Value,
}

fn default_listen() -> Vec<String> {
    vec!["tcp/127.0.0.1:7447".into()]
}
fn default_data_dir() -> PathBuf {
    "./data".into()
}
fn default_tls_names() -> Vec<String> {
    vec!["127.0.0.1".into(), "localhost".into()]
}
fn default_metrics_ms() -> u64 {
    10_000
}
fn default_restarts() -> u32 {
    10
}

/// `tcp/`, `udp/` or `ws/` endpoint whose host is not loopback.
pub fn plaintext_off_loopback(endpoint: &str) -> bool {
    let Some((proto, rest)) = endpoint.split_once('/') else {
        return false;
    };
    if !matches!(proto, "tcp" | "udp" | "ws") {
        return false;
    }
    // strip `?metadata` / `#config`, then the port
    let addr = rest.split(['?', '#']).next().unwrap_or(rest);
    let host = match addr.rsplit_once(':') {
        Some((h, _)) => h.trim_start_matches('[').trim_end_matches(']'),
        None => addr,
    };
    let loopback = host.eq_ignore_ascii_case("localhost")
        || host
            .parse::<std::net::IpAddr>()
            .is_ok_and(|ip| ip.is_loopback());
    !loopback
}

/// JSON (from json5) → wire `Value`. Integral numbers stay integers.
pub fn json_to_value(j: &serde_json::Value) -> Value {
    match j {
        serde_json::Value::Null => Value::Null,
        serde_json::Value::Bool(b) => Value::Bool(*b),
        serde_json::Value::Number(n) => {
            if let Some(u) = n.as_u64() {
                Value::UInt(u)
            } else if let Some(i) = n.as_i64() {
                Value::Int(i)
            } else {
                Value::Float(n.as_f64().unwrap_or(f64::NAN))
            }
        }
        serde_json::Value::String(s) => Value::Str(s.clone()),
        serde_json::Value::Array(a) => Value::Array(a.iter().map(json_to_value).collect()),
        serde_json::Value::Object(o) => Value::Map(
            o.iter()
                .map(|(k, v)| (k.clone(), json_to_value(v)))
                .collect(),
        ),
    }
}

fn json<T: serde::Serialize>(v: &T) -> String {
    serde_json::to_string(v).expect("plain data serializes")
}

impl Config {
    pub fn from_json5(text: &str) -> Result<Self, Error> {
        let cfg: Config = json5::from_str(text).map_err(|e| format!("wyrmd.json5: {e}"))?;
        wyrm_core::keyspace::validate_segment(&cfg.site).map_err(|e| format!("site: {e}"))?;
        if let Some(addr) = cfg.rest {
            if !addr.ip().is_loopback() && !cfg.insecure_plaintext {
                return Err(format!(
                    "rest {addr}: HTTP without auth off loopback (set insecure_plaintext: true to allow)"
                )
                .into());
            }
        }
        for ep in cfg.listen.iter().chain(&cfg.connect) {
            if plaintext_off_loopback(ep) {
                if !cfg.insecure_plaintext {
                    return Err(format!(
                        "{ep}: plaintext endpoint off loopback; use tls/quic or a loopback/unixsock endpoint \
                         (or set insecure_plaintext: true)"
                    )
                    .into());
                }
                tracing::warn!(endpoint = %ep, "plaintext endpoint off loopback (insecure_plaintext)");
            }
        }
        cfg.peers.validate(&cfg.site)?;
        if let Some(g) = &cfg.gateway {
            match (&g.tls_cert, &g.tls_key) {
                (Some(_), Some(_)) => {}
                (None, None) if g.listen.ip().is_loopback() => {}
                (None, None) => {
                    return Err(format!(
                        "gateway {}: TLS (tls_cert, tls_key) is required off loopback",
                        g.listen
                    )
                    .into())
                }
                _ => return Err("gateway: set both tls_cert and tls_key".into()),
            }
        }
        for (id, l) in &cfg.links {
            wyrm_core::keyspace::validate_segment(id).map_err(|e| format!("links.{id}: {e}"))?;
            if let Some(m) = &l.mode {
                Mode::parse(m).ok_or_else(|| format!("links.{id}.mode: unknown mode {m}"))?;
            }
        }
        Ok(cfg)
    }

    pub fn admin_keys(&self) -> Result<Vec<VerifyingKey>, Error> {
        self.admin_keys
            .iter()
            .map(|k| {
                let bytes: [u8; 32] = hex::decode(k)?
                    .try_into()
                    .map_err(|_| "admin key must be 32 bytes")?;
                Ok(VerifyingKey::from_bytes(&bytes)?)
            })
            .collect()
    }

    /// Broker certificates are needed for `tls/`/`quic/` listeners and peers.
    fn has_tls(&self) -> bool {
        !self.peers.is_empty()
            || self
                .listen
                .iter()
                .any(|e| e.starts_with("tls/") || e.starts_with("quic/"))
    }

    /// Endpoint for process links: the first `tls/` listener, on loopback.
    pub fn link_endpoint(&self) -> Option<String> {
        let ep = self.listen.iter().find(|e| e.starts_with("tls/"))?;
        Some(
            ep.replace("/0.0.0.0:", "/127.0.0.1:")
                .replace("/[::]:", "/127.0.0.1:"),
        )
    }

    fn config_links(&self) -> Vec<ConfigLink> {
        self.links
            .iter()
            .map(|(id, l)| ConfigLink {
                id: id.clone(),
                driver: l.driver.clone(),
                mode: l
                    .mode
                    .as_deref()
                    .and_then(Mode::parse)
                    .unwrap_or(Mode::Embedded),
                params: match &l.params {
                    serde_json::Value::Null => Value::Map(Default::default()),
                    p => json_to_value(p),
                },
            })
            .collect()
    }

    /// The router config, built in code (never from a user zenoh file).
    fn zenoh_config(&self, ctl: &Control) -> Result<zenoh::Config, Error> {
        let mut c = zenoh::Config::default();
        c.insert_json5("mode", r#""router""#)?;
        // Peer CAs only on the broker links: per-endpoint trust overrides
        // the global root (our own CA) for these endpoints alone.
        let mut listen = self.listen.clone();
        if let Some(ep) = &self.peers.listen {
            listen.push(format!(
                "{ep}#root_ca_certificate_file={}",
                ctl.peer_trust_path().display()
            ));
        }
        let mut connect = self.connect.clone();
        for u in &self.peers.upstream {
            connect.push(format!(
                "{}#root_ca_certificate_file={}",
                u.endpoint,
                u.ca.display()
            ));
        }
        c.insert_json5("listen/endpoints", &json(&listen))?;
        c.insert_json5("connect/endpoints", &json(&connect))?;
        if let Some(hz) = self.peers.upstream_val_hz {
            c.insert_json5(
                "downsampling",
                &serde_json::json!([{
                    "id": "upstream-val",
                    "link_protocols": ["quic"],
                    "flows": ["egress"],
                    "messages": ["put"],
                    "rules": [{ "key_expr": format!("wy/{}/down/**/~val", self.site), "freq": hz }],
                }])
                .to_string(),
            )?;
        }
        c.insert_json5(
            "scouting/multicast/enabled",
            &json(&self.multicast_scouting),
        )?;
        // Storages require timestamps.
        c.insert_json5(
            "timestamping/enabled",
            r#"{ router: true, peer: true, client: true }"#,
        )?;
        // TODO(owner decision): `{flows,pub}/**` persistence — rocksdb
        // volume (dynamic `.so` only) or wyrm-state WAL (ADR 0003).
        c.insert_json5(
            "plugins/storage_manager",
            r#"{ storages: { val: { key_expr: "wy/**/~val", volume: "memory" } } }"#,
        )?;
        if let Some(addr) = self.rest {
            c.insert_json5("plugins/rest", &format!(r#"{{ http_port: "{addr}" }}"#))?;
        }
        ctl.configure_zenoh(&mut c, self.has_tls())?;
        Ok(c)
    }
}

// ---------- drivers compiled into wyrmd ----------

struct Running<L: Link>(LinkHandle<L>);

impl<L: Link> RunningLink for Running<L> {
    fn stop(self: Box<Self>) -> wyrm_admin::control::BoxFut<'static, ()> {
        Box::pin(async move { self.0.stop().await })
    }
}

async fn start_boxed<L: Link>(
    session: Session,
    cfg: LinkConfig,
    params: Value,
) -> Result<Box<dyn RunningLink>, LinkError>
where
    L::Config: FromParams,
{
    let c = L::Config::from_params(&params)?;
    Ok(Box::new(Running(
        wyrm_link_sdk::spawn::<L>(session, cfg, c).await?,
    )))
}

/// `mock`, `mockdev` and `modbus`, embedded or as `wyrmd link <driver>`.
pub struct Drivers;

impl EmbeddedHost for Drivers {
    fn drivers(&self) -> Vec<&'static str> {
        vec![Mock::NAME, Framework::<MockDev>::NAME, Modbus::NAME]
    }

    fn validate(&self, driver: &str, params: &Value) -> Result<(), LinkError> {
        match driver {
            "mock" => MockConfig::from_params(params).map(|_| ()),
            // Framework drivers keep invalid nodes as `Failed`; only the
            // tree shape is checked up front.
            "mockdev" | "modbus" => Tree::from_params(params).map(|_| ()),
            d => Err(LinkError::invalid_parameter(format!("unknown driver {d}"))),
        }
    }

    fn start(
        &self,
        session: Session,
        cfg: LinkConfig,
        driver: String,
        params: Value,
    ) -> wyrm_admin::control::BoxFut<'static, Result<Box<dyn RunningLink>, LinkError>> {
        Box::pin(async move {
            match driver.as_str() {
                "mock" => start_boxed::<Mock>(session, cfg, params).await,
                "mockdev" => start_boxed::<Framework<MockDev>>(session, cfg, params).await,
                "modbus" => start_boxed::<Modbus>(session, cfg, params).await,
                d => Err(LinkError::invalid_parameter(format!("unknown driver {d}"))),
            }
        })
    }
}

/// `wyrmd link <driver>`: host one driver as a supervised process.
pub async fn run_link(driver: &str) -> Result<(), Error> {
    match driver {
        "mock" => wyrm_link_sdk::process::run::<Mock>().await?,
        "mockdev" => wyrm_link_sdk::process::run::<Framework<MockDev>>().await?,
        "modbus" => wyrm_link_sdk::process::run::<Modbus>().await?,
        d => return Err(format!("unknown driver {d}").into()),
    }
    Ok(())
}

// ---------- broker and daemon ----------

/// One router runtime with plugins and in-process sessions.
pub struct Broker {
    runtime: Runtime,
    session: Session,
    admin: Option<Attached>,
    flows: Option<LinkHandle<Engine>>,
    gateway: Option<(oneshot::Sender<()>, tokio::task::JoinHandle<()>)>,
}

impl Broker {
    pub async fn start(
        cfg: &Config,
        ctl: &Arc<Control>,
        flows: &Arc<FlowHost>,
        gateway: Option<&Arc<Gateway>>,
    ) -> Result<Self, Error> {
        let mut plugins = PluginsManager::static_plugins_only();
        plugins.declare_static_plugin::<StoragesPlugin, &str>("storage_manager", true);
        if cfg.rest.is_some() {
            plugins.declare_static_plugin::<RestPlugin, &str>("rest", true);
        }
        let mut runtime = RuntimeBuilder::new(cfg.zenoh_config(ctl)?)
            .plugins_manager(plugins)
            .build()
            .await?;
        // Admin and embedded links come up before the listeners open, so the
        // first remote query already finds their queryables and tokens.
        let session = zenoh::session::init(runtime.clone().into()).await?;
        let admin = ctl.attach(session.clone()).await?;
        // The engine trusts admin keys and the gateway's (user requests),
        // never the flow key: flow tokens do not command flows.
        let mut engine_keys = ctl.config().admin_keys.clone();
        engine_keys.extend(gateway.map(|g| g.verifying_key()));
        let mut lcfg = LinkConfig::new(cfg.site.clone(), wyrm_admin::control::FLOWS_LINK);
        lcfg.root = Some(format!("wy/{}/flows", cfg.site));
        lcfg.admin_keys = engine_keys.clone();
        let flows = match wyrm_link_sdk::spawn::<Engine>(
            session.clone(),
            lcfg,
            EngineStart {
                host: flows.clone(),
                admin_keys: engine_keys,
            },
        )
        .await
        {
            Ok(h) => h,
            Err(e) => {
                admin.stop().await;
                return Err(format!("flow engine: {e}").into());
            }
        };
        runtime.start().await?;
        let gateway = gateway.map(|gw| {
            let (tx, rx) = oneshot::channel::<()>();
            let (gw, s) = (gw.clone(), session.clone());
            let task = tokio::spawn(async move {
                if let Err(e) = gw
                    .serve(s, async {
                        let _ = rx.await;
                    })
                    .await
                {
                    tracing::error!("gateway: {e}");
                }
            });
            (tx, task)
        });
        Ok(Self {
            runtime,
            session,
            admin: Some(admin),
            flows: Some(flows),
            gateway,
        })
    }

    /// In-process session on the router runtime (no ACL, no serialization).
    pub fn session(&self) -> &Session {
        &self.session
    }

    pub fn locators(&self) -> Vec<String> {
        self.runtime
            .get_locators()
            .iter()
            .map(|l| l.to_string())
            .collect()
    }

    /// Stop admin and embedded links, then close sessions before the runtime.
    pub async fn stop(mut self) -> Result<(), Error> {
        if let Some((tx, task)) = self.gateway.take() {
            let _ = tx.send(());
            let _ = task.await;
        }
        if let Some(f) = self.flows.take() {
            f.stop().await;
        }
        if let Some(a) = self.admin.take() {
            a.stop().await;
        }
        self.session.close().await?;
        self.runtime.close().await?;
        Ok(())
    }
}

fn open_gateway(cfg: &Config, g: &GatewaySection) -> Result<Arc<Gateway>, Error> {
    let dir = cfg.data_dir.join("gateway");
    std::fs::create_dir_all(&dir)?;
    let hmac = wyrm_admin::secret::load_or_create_key(&dir.join("hmac.key"))?;
    let mut gc = GatewayConfig::new(cfg.site.clone(), dir, g.listen);
    if let (Some(c), Some(k)) = (&g.tls_cert, &g.tls_key) {
        gc.tls = Some((c.clone(), k.clone()));
    }
    if let Some(s) = g.session_ttl_s {
        gc.session_ttl = Duration::from_secs(s.clamp(60, 7 * 86_400));
    }
    let gw = Gateway::open(gc, &hmac).map_err(|e| format!("gateway: {e}"))?;
    if let Ok(pw) = std::env::var(GATEWAY_ADMIN_PASSWORD_ENV) {
        let pw = zeroize::Zeroizing::new(pw);
        // Child processes get a cleared environment as well (supervisor).
        std::env::remove_var(GATEWAY_ADMIN_PASSWORD_ENV);
        if gw
            .ensure_admin(&g.admin_user, &pw)
            .map_err(|e| format!("gateway admin: {e}"))?
        {
            tracing::info!(user = %g.admin_user, "gateway: first admin created");
        }
    }
    Ok(gw)
}

/// Gateway events into the admin journal (no passwords or tokens in them).
fn gateway_audit(ctl: &Control, e: AuditEvent) {
    use wyrm_core::Status;
    match e {
        AuditEvent::LoginOk { user, ip } => ctl.record(
            &format!("user:{user}"),
            "login",
            "",
            Status::Ok,
            &ip.to_string(),
        ),
        AuditEvent::LoginFailed { user, ip, reason } => ctl.record(
            &format!("user:{user}"),
            "login",
            "",
            Status::PermissionDenied,
            &format!("{ip} {reason}"),
        ),
        AuditEvent::UserChanged { by, user, change } => {
            ctl.record(&by, "user", &user, Status::Ok, change)
        }
        AuditEvent::Denied { user, op, key } => ctl.record(
            &format!("user:{user}"),
            &op,
            &key,
            Status::PermissionDenied,
            "gateway",
        ),
        e => ctl.record("gateway", "event", "", Status::Ok, &format!("{e:?}")),
    }
}

pub struct Daemon {
    cfg: Config,
    ctl: Arc<Control>,
    flows: Arc<FlowHost>,
    gateway: Option<Arc<Gateway>>,
    reload: tokio::sync::mpsc::UnboundedReceiver<()>,
}

impl Daemon {
    /// Open state and CA, apply `wyrmd.json5` links. `link_exe` hosts
    /// process links (`<link_exe> link <driver>`), normally this binary.
    pub fn open(cfg: Config, link_exe: PathBuf) -> Result<Self, Error> {
        std::fs::create_dir_all(&cfg.data_dir)?;
        let hmac = wyrm_admin::secret::load_or_create_key(&cfg.data_dir.join("flows.key"))?;
        let flows = FlowHost::open(&cfg.data_dir.join("flows"), &hmac, &cfg.site)?;
        let gateway = match &cfg.gateway {
            None => None,
            Some(g) => Some(open_gateway(&cfg, g)?),
        };
        // The gateway signs one token per user request with that user's
        // grants. Links (and the flow engine) trust its key; the admin does
        // not, so the control plane stays with operator keys.
        let mut link_keys = vec![flows.verifying_key()];
        link_keys.extend(gateway.as_ref().map(|g| g.verifying_key()));
        let ctl_cfg = ControlConfig {
            site: cfg.site.clone(),
            data_dir: cfg.data_dir.clone(),
            admin_keys: cfg.admin_keys()?,
            link_keys,
            operators: cfg.operators.clone(),
            dev: cfg.profile == Profile::Dev,
            link_endpoint: cfg.link_endpoint(),
            tls_names: cfg.tls_names.clone(),
            metrics_interval: Duration::from_millis(cfg.metrics_interval_ms.max(100)),
            link_exe,
            max_restarts: cfg.max_restarts,
        };
        let (ctl, reload) = Control::open(ctl_cfg, Arc::new(Drivers))?;
        ctl.set_peers(cfg.peers.peer_config());
        if let Some(gw) = &gateway {
            let audit = ctl.clone();
            gw.set_audit(move |e| gateway_audit(&audit, e));
        }
        ctl.bootstrap(&cfg.config_links())?;
        Ok(Self {
            cfg,
            ctl,
            flows,
            gateway,
            reload,
        })
    }

    pub fn control(&self) -> Arc<Control> {
        self.ctl.clone()
    }

    pub fn gateway(&self) -> Option<Arc<Gateway>> {
        self.gateway.clone()
    }

    /// Serve until `shutdown` completes; rebuild the broker on reload requests.
    pub async fn run_until(mut self, shutdown: impl Future<Output = ()>) -> Result<(), Error> {
        tokio::pin!(shutdown);
        loop {
            let broker =
                Broker::start(&self.cfg, &self.ctl, &self.flows, self.gateway.as_ref()).await?;
            tracing::info!(site = %self.cfg.site, locators = ?broker.locators(), "broker up");
            let reload = tokio::select! {
                _ = &mut shutdown => false,
                r = self.reload.recv() => r.is_some(),
            };
            broker.stop().await?;
            if !reload {
                break;
            }
            // Coalesce bursts (several installs in a row).
            while self.reload.try_recv().is_ok() {}
            tracing::info!("ACL changed: rebuilding the router runtime");
        }
        self.ctl.shutdown().await;
        Ok(())
    }
}
