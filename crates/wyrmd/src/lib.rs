//! `wyrmd`: Zenoh router runtime + static plugins + `wyrm-admin` + links.
//!
//! [`Daemon`] owns what survives a reload (the admin [`Control`]: registry,
//! CA, supervisor, audit; the flow store and signing key). A [`Broker`] is one router runtime with its
//! plugins and in-process sessions; it is rebuilt when the ACL changes,
//! because Zenoh 1.10 cannot reload `access_control` live (ADR 0006).

#![forbid(unsafe_code)]

use serde::Deserialize;
use std::collections::BTreeMap;
use std::future::Future;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::oneshot;
use wyrm_admin::control::{SCHEDULER_LINK, STORAGE_LINK};
use wyrm_admin::{
    Attached, ConfigLink, Control, ControlConfig, EmbeddedHost, Mode, PeerConfig, RunningLink,
    UpstreamConf,
};
use wyrm_core::Value;
use wyrm_example_portable::Echo;
use wyrm_flow::{Engine, EngineStart, FlowHost};
use wyrm_gateway::{AuditEvent, Gateway, GatewayConfig};
use wyrm_link_agent::{Agent, AgentConfig};
use wyrm_link_mock::df::MockDev;
use wyrm_link_mock::{Mock, MockConfig};
use wyrm_link_modbus::Modbus;
use wyrm_link_mqtt::Mqtt;
use wyrm_link_portable::{Portable, PortableConfig};
use wyrm_link_scheduler::Scheduler;
use wyrm_link_sdk::driver::{Framework, Tree};
use wyrm_link_sdk::{FromParams, Link, LinkConfig, LinkError, LinkHandle, VerifyingKey};
use wyrm_link_wasm::ComponentWorld;
use wyrm_link_wasm::Wasm;
use wyrm_storage::{Storage, StorageStart};
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
    /// Resource limits of process links (see `wyrm_link_sdk::limits`).
    #[serde(default)]
    pub link_limits: LinkLimits,
    /// WAL head anchors of the control-plane state and the audit journal,
    /// on another medium than `data_dir` (e.g. a separate mount): a WAL cut
    /// at the end or rolled back is refused at start.
    #[serde(default)]
    pub state_anchor_dir: Option<PathBuf>,
    /// `wyrmd init-anchors`: create the anchors from the current heads.
    #[serde(skip)]
    pub init_anchors: bool,
    /// Router-to-router links to other sites (iteration 4), QUIC + mTLS.
    #[serde(default)]
    pub peers: PeersSection,
    /// Link packages installed at runtime (ADR 0011).
    #[serde(default)]
    pub packages: PackagesSection,
    /// User gateway (HTTP + WebSocket, iteration 5). Off when absent.
    #[serde(default)]
    pub gateway: Option<GatewaySection>,
    /// The embedded scheduler at `wy/<site>/downstream/scheduler` (ADR 0022).
    #[serde(default)]
    pub scheduler: SchedulerSection,
}

/// `scheduler` in `wyrmd.json5`: on by default.
#[derive(Debug, Clone, Copy, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SchedulerSection {
    #[serde(default = "default_true")]
    pub enabled: bool,
    /// Size of its store (definitions and last outcomes) in MiB.
    #[serde(default = "default_scheduler_store_mb")]
    pub store_mb: u32,
}

impl Default for SchedulerSection {
    fn default() -> Self {
        Self {
            enabled: true,
            store_mb: default_scheduler_store_mb(),
        }
    }
}

fn default_true() -> bool {
    true
}
fn default_scheduler_store_mb() -> u32 {
    64
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
/// `downstream/**` and `dataflows/**` (no `~set`/`~act` queries: the ACL drops them)
/// and lets a downstream site serve its own `wy/<site>/**` (ADR 0007).
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PeersSection {
    /// QUIC listener for downstream brokers (`quic/0.0.0.0:7448`); it
    /// trusts this broker's CA alone (ADR 0015).
    #[serde(default)]
    pub listen: Option<String>,
    /// QUIC listener without client certificates where a downstream broker
    /// asks for its certificate (`quic/0.0.0.0:7450`, ADR 0015); needs
    /// `listen`.
    #[serde(default)]
    pub enroll: Option<String>,
    /// Sites this broker connects to.
    #[serde(default)]
    pub upstream: Vec<UpstreamPeer>,
    /// Sites that connect to this broker.
    #[serde(default)]
    pub downstream: Vec<DownstreamPeer>,
    /// Max rate of `~val` samples sent over QUIC (Hz); none = all. Zenoh
    /// 1.10 keeps one budget per rule and connection, so all points share it.
    #[serde(default)]
    pub upstream_val_hz: Option<f64>,
}

/// Link packages (ADR 0011).
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PackagesSection {
    /// Index for "Install Link ▸ from Repository", JSON
    /// `[{name, version, description, url, sha256}]` (as DSA's
    /// `linkRepositoryUrl`); https, or http to loopback.
    #[serde(default)]
    pub repository: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct UpstreamPeer {
    pub site: String,
    /// `quic/<host>:<port>`; the host must be a SAN of its broker certificate.
    pub endpoint: String,
    /// CA certificate (PEM) of that site.
    pub ca: PathBuf,
    /// The certificate that site issued for this broker (its
    /// `data_dir/peers/<this site>/broker.pem`) and its key (`broker.key`).
    pub cert: PathBuf,
    pub key: PathBuf,
    /// Its users may run `config` actions on our `sys` (ADR 0018); `write`
    /// on devices, flows and storage they always have.
    #[serde(default)]
    pub allow_config: bool,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DownstreamPeer {
    /// Its certificate (`broker:<site>`) is issued into
    /// `data_dir/peers/<site>/` at start (ADR 0015).
    pub site: String,
    /// Sites that broker relays from further down (a chain `plant → edge →
    /// here`: edge has `via: ["plant"]`). It may serve their keys, and this
    /// broker's upstream may read them.
    #[serde(default)]
    pub via: Vec<String>,
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
            path("peers.upstream cert", &u.cert)?;
            path("peers.upstream key", &u.key)?;
        }
        for d in &self.downstream {
            for v in &d.via {
                wyrm_core::keyspace::validate_segment(v)
                    .map_err(|e| format!("peers.downstream {} via: {e}", d.site))?;
                if v == own_site || !seen.insert(v.clone()) {
                    return Err(format!(
                        "peers.downstream {} via: site {v} repeated, own or a peer",
                        d.site
                    )
                    .into());
                }
            }
        }
        if let Some(ep) = &self.enroll {
            quic("peers.enroll", ep)?;
            if self.listen.is_none() {
                return Err("peers.enroll needs peers.listen".into());
            }
        }
        match (&self.listen, self.downstream.is_empty()) {
            (Some(ep), _) => quic("peers.listen", ep)?,
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
                via: self
                    .downstream
                    .iter()
                    .filter(|d| !d.via.is_empty())
                    .map(|d| (d.site.clone(), d.via.clone()))
                    .collect(),
                enroll: self.enroll.is_some(),
                config_from: self
                    .upstream
                    .iter()
                    .filter(|u| u.allow_config)
                    .map(|u| u.site.clone())
                    .collect(),
            },
            upstream: self
                .upstream
                .iter()
                .map(|u| UpstreamConf {
                    site: u.site.clone(),
                    endpoint: u.endpoint.clone(),
                    ca: u.ca.clone(),
                    cert: u.cert.clone(),
                    key: u.key.clone(),
                    allow_config: u.allow_config,
                })
                .collect(),
            listen: self.listen.is_some(),
            listen_port: self
                .listen
                .as_deref()
                .and_then(|ep| ep.rsplit_once(':'))
                .and_then(|(_, p)| p.parse().ok()),
            enroll: self.enroll.is_some(),
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

/// `link_limits` in `wyrmd.json5`; 0 = no limit. Core dumps are always off.
#[derive(Debug, Clone, Copy, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct LinkLimits {
    /// Heap and private mappings per link process (Linux only).
    #[serde(default = "default_link_memory_mb")]
    pub memory_mb: u64,
    #[serde(default = "default_link_open_files")]
    pub open_files: u64,
}

impl Default for LinkLimits {
    fn default() -> Self {
        Self {
            memory_mb: default_link_memory_mb(),
            open_files: default_link_open_files(),
        }
    }
}

fn default_link_memory_mb() -> u64 {
    1024
}
fn default_link_open_files() -> u64 {
    4096
}

pub use wyrm_client::endpoint::plaintext_off_loopback;

/// Egress downsampling of `~val` towards peer brokers (`quic/`): one rule,
/// and so one budget of `hz` samples/s, per link. Zenoh keeps one timer
/// per rule and picks one matching rule per key, so the rules must not
/// overlap; keys of a link not in the registry (`dev` profile only) are not
/// limited. The router is rebuilt when links change (ADR 0006).
pub fn upstream_downsampling(site: &str, links: &[String], hz: f64) -> Option<serde_json::Value> {
    let rules: Vec<serde_json::Value> = links
        .iter()
        .map(|l| serde_json::json!({ "key_expr": format!("wy/{site}/downstream/{l}/**/~val"), "freq": hz }))
        .collect();
    (!rules.is_empty()).then(|| {
        serde_json::json!([{
            "id": "upstream-val",
            "link_protocols": ["quic"],
            "flows": ["egress"],
            "messages": ["put"],
            "rules": rules,
        }])
    })
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
        // `downstream/<d>` is the broker node of downstream site d (ADR 0007).
        for d in &cfg.peers.downstream {
            if cfg.links.contains_key(&d.site) {
                return Err(format!("links.{}: the name of a downstream site", d.site).into());
            }
            // `downstream/scheduler` is the embedded scheduler (ADR 0022)
            if d.site == SCHEDULER_LINK {
                return Err(
                    format!("peers.downstream {}: the id belongs to the broker", d.site).into(),
                );
            }
        }
        let mb = cfg.scheduler.store_mb;
        if !(1..=wyrm_link_portable::MAX_STORE_MB).contains(&mb) {
            return Err(format!(
                "scheduler.store_mb {mb}: expected 1 to {}",
                wyrm_link_portable::MAX_STORE_MB
            )
            .into());
        }
        if let Some(addr) = cfg.rest {
            // The REST plugin runs inside the router: the ACL never sees its
            // requests, so it could put into `downstream/**` and `sys/**`.
            if cfg.profile != Profile::Dev {
                return Err(format!(
                    "rest {addr}: the REST plugin bypasses the ACL; only in profile dev"
                )
                .into());
            }
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
        if let Some(a) = &cfg.state_anchor_dir {
            if a.starts_with(&cfg.data_dir) {
                return Err(format!(
                    "state_anchor_dir {}: must be outside data_dir (another medium)",
                    a.display()
                )
                .into());
            }
        }
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
            // ids of the broker's own links (ADR 0017, 0022)
            if [STORAGE_LINK, SCHEDULER_LINK].contains(&id.as_str()) {
                return Err(format!("links.{id}: the id belongs to the broker").into());
            }
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
        // The QUIC broker listener trusts our own CA, as the others do
        // (ADR 0015): downstream brokers hold certificates from it. It opens
        // whenever it is configured, so an unknown broker reaches quarantine.
        let mut listen = self.listen.clone();
        listen.extend(self.peers.listen.clone());
        // Server-auth TLS only: a downstream broker without a certificate
        // yet asks for one there (the ACL lets it reach one key).
        if let Some(ep) = &self.peers.enroll {
            listen.push(format!("{ep}#enable_mtls=false"));
        }
        // An upstream site's CA and the certificate it issued for us, on
        // its endpoint alone; certificate and key always together, as files
        // (Zenoh logs endpoint strings).
        let mut connect = self.connect.clone();
        for u in ctl.upstream_endpoints() {
            connect.push(format!(
                "{}#root_ca_certificate_file={};connect_certificate_file={};connect_private_key_file={}",
                u.endpoint,
                u.ca.display(),
                u.cert.display(),
                u.key.display()
            ));
        }
        c.insert_json5("listen/endpoints", &json(&listen))?;
        c.insert_json5("connect/endpoints", &json(&connect))?;
        if let Some(hz) = self.peers.upstream_val_hz {
            let links: Vec<String> = ctl.registry().links.into_keys().collect();
            if let Some(d) = upstream_downsampling(&self.site, &links, hz) {
                c.insert_json5("downsampling", &d.to_string())?;
            }
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
        // TODO(owner decision): `{dataflows,pub}/**` persistence — rocksdb
        // volume (dynamic `.so` only) or wyrm-state WAL (ADR 0003).
        c.insert_json5(
            "plugins/storage_manager",
            r#"{ storages: { val: { key_expr: "wy/**/~val", volume: "memory" } } }"#,
        )?;
        if let Some(addr) = self.rest {
            c.insert_json5("plugins/rest", &format!(r#"{{ http_port: "{addr}" }}"#))?;
        }
        ctl.configure_zenoh(&mut c, self.has_tls() || ctl.has_peers())?;
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

/// `mock`, `mockdev`, `modbus`, `mqtt`, `agent` and `portable-echo` (the portable example app,
/// ADR 0023), embedded or as `wyrmd link <driver>`; `wasm` and `app` embedded.
/// `opcua` (OPC UA client, `links/opcua`) embedded or as a process.
pub struct Drivers;

impl EmbeddedHost for Drivers {
    fn drivers(&self) -> Vec<&'static str> {
        vec![
            Mock::NAME,
            Framework::<MockDev>::NAME,
            Modbus::NAME,
            Mqtt::NAME,
            wyrm_link_opcua::Opcua::NAME,
            Agent::NAME,
            Framework::<Wasm>::NAME,
            wyrm_link_wasm::App::NAME,
            Portable::<Echo>::NAME,
        ]
    }

    fn validate(&self, driver: &str, params: &Value) -> Result<(), LinkError> {
        match driver {
            "mock" => MockConfig::from_params(params).map(|_| ()),
            // Framework drivers keep invalid nodes as `Failed`; only the
            // tree shape is checked up front.
            "mockdev" | "modbus" | "mqtt" | "wasm" => Tree::from_params(params).map(|_| ()),
            "opcua" => Tree::from_params(params).map(|_| ()),
            "agent" => AgentConfig::from_params(params).map(|_| ()),
            "app" => <wyrm_link_wasm::App as Link>::Config::from_params(params).map(|_| ()),
            // the app validates its own params in `start`
            "portable-echo" => PortableConfig::from_params(params).map(|_| ()),
            // a `wasm` package link, through the driver it runs on (as `start` picks it); the
            // admin does not ask for a process package, whose params its own binary parses
            d if d.starts_with("pkg:") => {
                let name = &d["pkg:".len()..];
                match wyrm_link_wasm::package_world(name) {
                    Some(ComponentWorld::App) => {
                        <wyrm_link_wasm::App as Link>::Config::from_params(&app_component(
                            name,
                            params.clone(),
                        )?)
                        .map(|_| ())
                    }
                    Some(_) => Tree::from_params(params).map(|_| ()),
                    None => Err(LinkError::invalid_parameter(format!(
                        "package {name}: no WASM component here"
                    ))),
                }
            }
            d => Err(LinkError::invalid_parameter(format!("unknown driver {d}"))),
        }
    }

    fn reload_package(
        &self,
        name: &str,
    ) -> wyrm_admin::control::BoxFut<'static, Result<Vec<String>, LinkError>> {
        let name = name.to_owned();
        Box::pin(async move {
            if wyrm_link_wasm::package_world(&name) != Some(ComponentWorld::App) {
                return Ok(Vec::new());
            }
            // compiles the component: off the async workers
            tokio::task::spawn_blocking(move || wyrm_link_wasm::app::reload_component(&name))
                .await
                .map_err(|e| LinkError::internal(format!("reload: {e}")))?
        })
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
                "mqtt" => start_boxed::<Mqtt>(session, cfg, params).await,
                "opcua" => start_boxed::<wyrm_link_opcua::Opcua>(session, cfg, params).await,
                "agent" => start_boxed::<Agent>(session, cfg, params).await,
                // a portable link on a WASM component (ADR 0023)
                "app" => start_boxed::<wyrm_link_wasm::App>(session, cfg, params).await,
                // the portable example on the native adapter (ADR 0023)
                "portable-echo" => start_boxed::<Portable<Echo>>(session, cfg, params).await,
                // a `wasm` package link runs in the broker (ADR 0011, 0012); its component's
                // exports tell an app from a point driver
                d if d
                    .strip_prefix("pkg:")
                    .and_then(wyrm_link_wasm::package_world)
                    == Some(ComponentWorld::App) =>
                {
                    let params = app_component(&d["pkg:".len()..], params)?;
                    start_boxed::<wyrm_link_wasm::App>(session, cfg, params).await
                }
                d if d == "wasm" || d.starts_with("pkg:") => {
                    start_boxed::<Framework<Wasm>>(session, cfg, params).await
                }
                d => Err(LinkError::invalid_parameter(format!("unknown driver {d}"))),
            }
        })
    }
}

/// The params of a `pkg:<name>` app link: its component is the package's own (the world was
/// told from `<name>.wasm`); another `component` is refused.
fn app_component(name: &str, params: Value) -> Result<Value, LinkError> {
    let mut m = match params {
        Value::Map(m) => m,
        Value::Null => Default::default(),
        _ => return Err(LinkError::invalid_parameter("params: expected a map")),
    };
    match m.get("component") {
        None | Some(Value::Null) => {
            m.insert("component".into(), Value::Str(name.into()));
        }
        Some(Value::Str(c)) if c == name => {}
        Some(other) => {
            return Err(LinkError::invalid_parameter(format!(
                "params.component: {other:?} is not this link's package {name}"
            )))
        }
    }
    Ok(Value::Map(m))
}

/// `wyrmd link <driver>`: host one driver as a supervised process.
pub async fn run_link(driver: &str) -> Result<(), Error> {
    match driver {
        "mock" => wyrm_link_sdk::process::run::<Mock>().await?,
        "mockdev" => wyrm_link_sdk::process::run::<Framework<MockDev>>().await?,
        "modbus" => wyrm_link_sdk::process::run::<Modbus>().await?,
        "mqtt" => wyrm_link_sdk::process::run::<Mqtt>().await?,
        "opcua" => wyrm_link_sdk::process::run::<wyrm_link_opcua::Opcua>().await?,
        "agent" => wyrm_link_sdk::process::run::<Agent>().await?,
        "portable-echo" => wyrm_link_sdk::process::run::<Portable<Echo>>().await?,
        // the scheduler as a process link (ADR 0022 run modes)
        "scheduler" => wyrm_link_sdk::process::run::<Portable<Scheduler>>().await?,
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
    storage: Option<LinkHandle<Storage>>,
    scheduler: Option<LinkHandle<Portable<Scheduler>>>,
    gateway: Option<(oneshot::Sender<()>, tokio::task::JoinHandle<()>)>,
}

/// The zone of schedules added without one (ruling 3): the system's IANA
/// zone when the scheduler knows it, else UTC.
fn system_zone() -> String {
    jiff::tz::TimeZone::system()
        .iana_name()
        .filter(|n| jiff::tz::TimeZone::get(n).is_ok())
        .unwrap_or("UTC")
        .to_owned()
}

impl Broker {
    pub async fn start(
        cfg: &Config,
        ctl: &Arc<Control>,
        flows: &Arc<FlowHost>,
        storage: &Arc<wyrm_storage::Store>,
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
        if let Some(g) = gateway {
            // downstream sites may have changed at runtime (install, quarantine)
            g.set_downstream_sites(ctl.peers().reachable());
        }
        // The engine trusts admin keys and the gateway's (user requests),
        // never the flow key: flow tokens do not command flows.
        let mut engine_keys = ctl.config().admin_keys.clone();
        engine_keys.extend(gateway.map(|g| g.verifying_key()));
        let mut lcfg = LinkConfig::new(cfg.site.clone(), wyrm_admin::control::FLOWS_LINK);
        lcfg.root = Some(format!("wy/{}/dataflows", cfg.site));
        lcfg.admin_keys = engine_keys.clone();
        // upstream sites at write (ADR 0018); deploys need config
        lcfg.limited_keys = ctl.upstream_trust("dataflows");
        let flow_key = flows.verifying_key();
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
        // Storage (ADR 0017): the admin keys, users through the gateway and
        // flows at write, each only under `storage`; upstream sites at
        // write (ADR 0018).
        let root = format!("wy/{}/storage", cfg.site);
        let mut lcfg = LinkConfig::new(cfg.site.clone(), STORAGE_LINK);
        lcfg.root = Some(root.clone());
        lcfg.admin_keys = ctl.config().admin_keys.clone();
        lcfg.limited_keys = std::iter::once((flow_key, wyrm_core::Perm::Write))
            .chain(gateway.map(|g| (g.verifying_key(), wyrm_core::Perm::Config)))
            .map(|(key, cap)| wyrm_link_sdk::LimitedKey {
                key,
                cap,
                scopes: vec![root.clone()],
                subject: None,
            })
            .chain(ctl.upstream_trust("storage"))
            .collect();
        let storage = match wyrm_link_sdk::spawn::<Storage>(
            session.clone(),
            lcfg,
            StorageStart {
                store: storage.clone(),
                limits: Default::default(),
            },
        )
        .await
        {
            Ok(h) => h,
            Err(e) => {
                flows.stop().await;
                admin.stop().await;
                return Err(format!("storage: {e}").into());
            }
        };
        // The scheduler (ADR 0022): trusted as every embedded link; it signs
        // its writes with its own key, which links trust at write on
        // `downstream` (made by the admin at attach; without it the broker
        // runs without the scheduler, R22).
        let scheduler = if ctl.scheduler_runs() {
            let site_down = format!("wy/{}/downstream", cfg.site);
            let started = match ctl
                .embedded_link_config(SCHEDULER_LINK, vec![(site_down, wyrm_core::Perm::Write)])
            {
                Ok(lcfg) => {
                    let mut params = BTreeMap::new();
                    params.insert("default_tz".to_owned(), Value::Str(system_zone()));
                    let pcfg = PortableConfig {
                        params: Value::Map(params),
                        store_mb: cfg.scheduler.store_mb,
                        ..PortableConfig::default()
                    };
                    wyrm_link_sdk::spawn::<Portable<Scheduler>>(session.clone(), lcfg, pcfg).await
                }
                Err(e) => Err(e),
            };
            match started {
                Ok(h) => Some(h),
                Err(e) => {
                    storage.stop().await;
                    flows.stop().await;
                    admin.stop().await;
                    return Err(format!("scheduler: {e}").into());
                }
            }
        } else {
            None
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
            storage: Some(storage),
            scheduler,
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
        // first: it sends requests to the other links
        if let Some(s) = self.scheduler.take() {
            s.stop().await;
        }
        if let Some(f) = self.flows.take() {
            f.stop().await;
        }
        if let Some(s) = self.storage.take() {
            s.stop().await;
        }
        if let Some(a) = self.admin.take() {
            a.stop().await;
        }
        self.session.close().await?;
        self.runtime.close().await?;
        Ok(())
    }
}

/// One store checked by [`verify_state`].
pub struct StoreCheck {
    pub name: String,
    pub result: Result<wyrm_state::Report, String>,
}

impl StoreCheck {
    /// A torn last record counts as a problem here: without an anchor a
    /// crash and an edited last record look the same (open drops it).
    pub fn ok(&self) -> bool {
        matches!(&self.result, Ok(r) if r.anchor_ok != Some(false) && !r.torn_tail)
    }
}

/// Existing hex key file; never creates one.
fn read_key(path: &std::path::Path) -> Result<zeroize::Zeroizing<Vec<u8>>, String> {
    let text = std::fs::read_to_string(path).map_err(|e| format!("{}: {e}", path.display()))?;
    let k = zeroize::Zeroizing::new(
        hex::decode(text.trim()).map_err(|_| format!("{}: not hex", path.display()))?,
    );
    if k.len() != 32 {
        return Err(format!("{}: expected 32 bytes", path.display()));
    }
    Ok(k)
}

/// `wyrmd verify`: every control-plane store (and each agent store) checked
/// offline — CRC, HMAC chain, anchor — without changing anything. wyrmd
/// must be stopped (the stores are locked while it runs).
pub fn verify_state(cfg: &Config) -> Vec<StoreCheck> {
    let d = &cfg.data_dir;
    let anchor = |n: &str| cfg.state_anchor_dir.as_ref().map(|a| a.join(n));
    let mut stores: Vec<(String, PathBuf, PathBuf, Option<PathBuf>)> = vec![
        (
            "registry".into(),
            d.join("state"),
            d.join("state.key"),
            anchor("state.head"),
        ),
        (
            "audit".into(),
            d.join("audit"),
            d.join("state.key"),
            anchor("audit.head"),
        ),
        (
            "flows".into(),
            d.join("flows/state"),
            d.join("flows.key"),
            anchor("flows.head"),
        ),
        (
            "gateway users".into(),
            d.join("gateway/users"),
            d.join("gateway/hmac.key"),
            anchor("users.head"),
        ),
    ];
    if let Ok(links) = std::fs::read_dir(d.join("links")) {
        for e in links.flatten() {
            let data = e.path().join("data");
            if data.join("agent").is_dir() {
                stores.push((
                    format!("agent {}", e.file_name().to_string_lossy()),
                    data.join("agent"),
                    data.join("agent.key"),
                    None,
                ));
            }
        }
    }
    stores
        .into_iter()
        .filter(|(_, dir, _, _)| dir.is_dir())
        .map(|(name, dir, key, anchor)| {
            let result = read_key(&key).and_then(|k| {
                wyrm_state::verify(&dir, &k, anchor.as_deref()).map_err(|e| e.to_string())
            });
            StoreCheck { name, result }
        })
        .collect()
}

/// Gateway user management from the command line (`wyrmd user …`). The
/// stores are locked while wyrmd runs, so this works on a stopped broker;
/// a running one is managed through the gateway's HTTP API.
pub struct UserAdmin {
    gw: Arc<Gateway>,
    audit: std::sync::Mutex<wyrm_state::Store<wyrm_admin::audit::AuditLog>>,
}

impl UserAdmin {
    pub fn open(cfg: &Config) -> Result<Self, Error> {
        let g = cfg
            .gateway
            .as_ref()
            .ok_or("no gateway section in the config")?;
        let in_use = |e: String| -> Error {
            if e.contains("in use") {
                format!("{e} (stop wyrmd, or use the gateway HTTP API)").into()
            } else {
                e.into()
            }
        };
        let gw = open_gateway(cfg, g, false).map_err(|e| in_use(e.to_string()))?;
        let key = wyrm_admin::secret::load_or_create_key(&cfg.data_dir.join("state.key"))?;
        let audit = wyrm_state::Store::open(cfg.data_dir.join("audit"), &key)
            .map_err(|e| in_use(e.to_string()))?;
        Ok(Self {
            gw,
            audit: std::sync::Mutex::new(audit),
        })
    }

    pub fn gateway(&self) -> &Gateway {
        &self.gw
    }

    /// An audit record for a change made here (`sub` = `local:cli`).
    pub fn record(&self, op: &str, user: &str, detail: &str) -> Result<(), Error> {
        let rec = wyrm_admin::audit::AuditRecord {
            t: wyrm_link_sdk::now_us(),
            sub: "local:cli".into(),
            op: op.into(),
            key: user.into(),
            status: wyrm_core::Status::Ok.code(),
            detail: detail.into(),
        };
        self.audit
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .apply(rec)?;
        Ok(())
    }
}

fn open_gateway(cfg: &Config, g: &GatewaySection, bootstrap: bool) -> Result<Arc<Gateway>, Error> {
    let dir = cfg.data_dir.join("gateway");
    std::fs::create_dir_all(&dir)?;
    let hmac = wyrm_admin::secret::load_or_create_key(&dir.join("hmac.key"))?;
    let mut gc = GatewayConfig::new(cfg.site.clone(), dir, g.listen);
    // every site below this one, also through a chain
    gc.downstream_sites = cfg.peers.peer_config().peers.reachable();
    gc.anchor = cfg.state_anchor_dir.as_ref().map(|d| d.join("users.head"));
    gc.anchor_init = cfg.init_anchors;
    if let (Some(c), Some(k)) = (&g.tls_cert, &g.tls_key) {
        gc.tls = Some((c.clone(), k.clone()));
    }
    if let Some(s) = g.session_ttl_s {
        gc.session_ttl = Duration::from_secs(s.clamp(60, 7 * 86_400));
    }
    let gw = Gateway::open(gc, &hmac).map_err(|e| format!("gateway: {e}"))?;
    if !bootstrap {
        return Ok(gw);
    }
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

/// The gateway's roles behind `sys` Get/Update Permissions.
struct GatewayRoles(Arc<Gateway>);

impl wyrm_admin::control::RoleGrants for GatewayRoles {
    fn grants(&self) -> Vec<(String, String, wyrm_core::Perm)> {
        self.0
            .role_table()
            .iter()
            .flat_map(|(role, grants)| {
                grants
                    .iter()
                    .map(move |(k, p)| (role.to_owned(), k.clone(), *p))
            })
            .collect()
    }

    fn set_grant(&self, role: &str, key: &str, level: wyrm_core::Perm) -> Result<(), String> {
        self.0
            .set_grant(role, key, level)
            .map_err(|e| e.to_string())
    }

    fn revoke_widening(
        &self,
        keys: &[String],
        probe: &str,
    ) -> Result<Vec<(String, String, wyrm_core::Perm)>, String> {
        self.0
            .revoke_widening(keys, probe)
            .map_err(|e| e.to_string())
    }
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
    /// Opened once: every broker build restarts the storage link on it.
    storage: Arc<wyrm_storage::Store>,
    gateway: Option<Arc<Gateway>>,
    reload: tokio::sync::mpsc::UnboundedReceiver<()>,
}

impl Daemon {
    /// Open state and CA, apply `wyrmd.json5` links. `link_exe` hosts
    /// process links (`<link_exe> link <driver>`), normally this binary.
    pub fn open(cfg: Config, link_exe: PathBuf) -> Result<Self, Error> {
        std::fs::create_dir_all(&cfg.data_dir)?;
        let hmac = wyrm_admin::secret::load_or_create_key(&cfg.data_dir.join("flows.key"))?;
        let anchor = |name: &str| cfg.state_anchor_dir.as_ref().map(|d| d.join(name));
        if let Some(d) = &cfg.state_anchor_dir {
            // Not created here: it belongs on another medium the operator mounts.
            if !d.is_dir() {
                return Err(format!(
                    "state_anchor_dir {}: not a directory (mount it, then run `wyrmd init-anchors`)",
                    d.display()
                )
                .into());
            }
        }
        let flows_anchor = anchor("flows.head");
        let flows = FlowHost::open_anchored(
            &cfg.data_dir.join("flows"),
            &hmac,
            &cfg.site,
            flows_anchor.as_deref().map(|a| (a, cfg.init_anchors)),
        )?;
        let storage = Arc::new(wyrm_storage::Store::open(&cfg.data_dir.join("storage"))?);
        let gateway = match &cfg.gateway {
            None => None,
            Some(g) => Some(open_gateway(&cfg, g, true)?),
        };
        // The gateway signs one token per user request with that user's
        // grants. Links, the flow engine and the admin trust its key; the
        // grants decide (only the admin role reaches `sys/**`).
        // Caps: flows never get config (spec 06); gateway tokens carry the
        // user's grants, up to config on devices.
        let devices = vec![format!("wy/{}/downstream", cfg.site)];
        let mut link_keys = vec![wyrm_link_sdk::LimitedKey {
            key: flows.verifying_key(),
            cap: wyrm_core::Perm::Write,
            scopes: devices.clone(),
            subject: None,
        }];
        link_keys.extend(gateway.as_ref().map(|g| wyrm_link_sdk::LimitedKey {
            key: g.verifying_key(),
            cap: wyrm_core::Perm::Config,
            scopes: devices.clone(),
            subject: None,
        }));
        let ctl_cfg = ControlConfig {
            site: cfg.site.clone(),
            data_dir: cfg.data_dir.clone(),
            admin_keys: cfg.admin_keys()?,
            control_keys: gateway
                .as_ref()
                .map(|g| g.verifying_key())
                .into_iter()
                .collect(),
            link_keys,
            operators: cfg.operators.clone(),
            dev: cfg.profile == Profile::Dev,
            link_endpoint: cfg.link_endpoint(),
            tls_names: cfg.tls_names.clone(),
            metrics_interval: Duration::from_millis(cfg.metrics_interval_ms.max(100)),
            link_exe,
            max_restarts: cfg.max_restarts,
            per_link_router_rules: cfg.peers.upstream_val_hz.is_some(),
            link_limits: wyrm_link_sdk::limits::Limits {
                memory_mb: cfg.link_limits.memory_mb,
                open_files: cfg.link_limits.open_files,
            },
            anchor_dir: cfg.state_anchor_dir.clone(),
            anchor_init: cfg.init_anchors,
            repository: cfg.packages.repository.clone(),
            scheduler: cfg.scheduler.enabled,
        };
        let (ctl, reload) = Control::open(ctl_cfg, Arc::new(Drivers))?;
        wyrm_link_wasm::set_component_root(ctl.component_store());
        ctl.set_peers(cfg.peers.peer_config());
        // a site now in wyrmd.json5 and still in the registry: json5 wins
        ctl.drop_shadowed_peers();
        // watches stored with a tree route before routes resolved
        ctl.resolve_watch_routes();
        // A link installed at runtime before its name became a downstream
        // site would overlap `downstream/<d>` (ADR 0007): refuse to start.
        if let Some(d) = cfg
            .peers
            .downstream
            .iter()
            .find(|d| ctl.registry().links.contains_key(&d.site))
        {
            return Err(format!(
                "peers.downstream {:?}: a link with that id exists; remove the link first",
                d.site
            )
            .into());
        }
        // The broker storage owns this id since spec 0.2.2 (ADR 0017): a link
        // stored under it would share its audit records, overlays and logs.
        if ctl.registry().links.contains_key(STORAGE_LINK) {
            return Err(format!(
                "a link with id {STORAGE_LINK:?} exists; the id belongs to the broker storage since spec 0.2.2 (ADR 0017): remove the link with the previous wyrmd first"
            )
            .into());
        }
        // The same for the embedded scheduler (ADR 0022): it would also share
        // `downstream/scheduler`.
        if ctl.registry().links.contains_key(SCHEDULER_LINK) {
            return Err(format!(
                "a link with id {SCHEDULER_LINK:?} exists; the id belongs to the embedded scheduler (ADR 0022): remove the link with the previous wyrmd first"
            )
            .into());
        }
        // A name our CA issued `broker:<site>` for keeps a valid certificate:
        // as an upstream site it would match that site's ACL subject.
        if let Some(u) = cfg
            .peers
            .upstream
            .iter()
            .find(|u| ctl.registry().issued_brokers.contains(&u.site))
        {
            return Err(format!(
                "peers.upstream {:?}: was a downstream broker of this site (ADR 0015)",
                u.site
            )
            .into());
        }
        ctl.issue_broker_certs()?;
        if let Some(gw) = &gateway {
            let audit = ctl.clone();
            gw.set_audit(move |e| gateway_audit(&audit, e));
            ctl.set_role_grants(Arc::new(GatewayRoles(gw.clone())));
        }
        ctl.bootstrap(&cfg.config_links())?;
        Ok(Self {
            cfg,
            ctl,
            flows,
            storage,
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
        let r = self.serve(shutdown).await;
        // Also on errors: supervised link processes must not outlive us.
        self.ctl.shutdown().await;
        r
    }

    async fn serve(
        &mut self,
        mut shutdown: std::pin::Pin<&mut impl Future<Output = ()>>,
    ) -> Result<(), Error> {
        loop {
            if let Some(ep) = &self.cfg.peers.listen {
                if !wait_udp_free(ep, QUIC_PORT_WAIT).await {
                    tracing::warn!(
                        endpoint = %ep,
                        "QUIC peer port in use: downstream brokers cannot connect until a restart"
                    );
                }
            }
            let broker = Broker::start(
                &self.cfg,
                &self.ctl,
                &self.flows,
                &self.storage,
                self.gateway.as_ref(),
            )
            .await?;
            self.ctl.reopen();
            tracing::info!(site = %self.cfg.site, locators = ?broker.locators(), "broker up");
            let reload = tokio::select! {
                _ = shutdown.as_mut() => false,
                r = self.reload.recv() => r.is_some(),
            };
            if reload {
                // A package install in flight finishes on this broker; new
                // ones answer `busy` until the next broker is up.
                self.ctl.quiesce(Duration::from_secs(180)).await;
                // Fail closed: an old runtime that did not close may keep
                // sessions under the old ACL, so the daemon ends and its
                // supervisor starts it clean.
                broker.stop().await?;
            } else if let Err(e) = broker.stop().await {
                // At exit a close that times out (a busy peer link) is only
                // reported: nothing runs after it.
                tracing::warn!("closing the broker at exit: {e}");
            }
            if !reload {
                break;
            }
            // Coalesce bursts (several installs in a row).
            while self.reload.try_recv().is_ok() {}
            tracing::info!("ACL changed: rebuilding the router runtime");
        }
        Ok(())
    }
}

/// How long a broker start waits for an old runtime (a rebuild, or a
/// restart in the same process) to let the QUIC peer port go.
const QUIC_PORT_WAIT: Duration = Duration::from_secs(30);

/// Wait until the UDP port of `quic/<host>:<port>` is free. The old
/// runtime's QUIC endpoint keeps it while its connections drain; Zenoh
/// 1.10.1 tries a listener once (`listen/timeout_ms` 0), so a busy port
/// would leave downstream brokers out until the next restart.
async fn wait_udp_free(endpoint: &str, max: Duration) -> bool {
    let Some(addr) = endpoint.strip_prefix("quic/") else {
        return true;
    };
    let deadline = std::time::Instant::now() + max;
    loop {
        if std::net::UdpSocket::bind(addr).is_ok() {
            return true;
        }
        if std::time::Instant::now() >= deadline {
            return false;
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn scheduler_section_and_reserved_ids() {
        let parse = |extra: &str| Config::from_json5(&format!(r#"{{ site: "s", {extra} }}"#));
        let d = parse("").unwrap().scheduler;
        assert!(d.enabled);
        assert_eq!(d.store_mb, 64);
        let off = parse("scheduler: { enabled: false }").unwrap().scheduler;
        assert!(!off.enabled);
        assert_eq!(off.store_mb, 64);
        for bad in [
            "scheduler: { store_mb: 0 }",
            "scheduler: { store_mb: 65 }",
            "scheduler: { other: 1 }",
            r#"links: { scheduler: { driver: "mock" } }"#,
            r#"links: { storage: { driver: "mock" } }"#,
        ] {
            assert!(parse(bad).is_err(), "{bad}");
        }
    }

    #[test]
    fn a_pkg_app_runs_its_own_package() {
        let comp = |v: &Value| match v {
            Value::Map(m) => m.get("component").cloned(),
            _ => None,
        };
        let p = app_component("echo", Value::Null).unwrap();
        assert_eq!(comp(&p), Some(Value::Str("echo".into())));
        let mut m = std::collections::BTreeMap::new();
        m.insert("component".to_owned(), Value::Str("echo".into()));
        m.insert("rate".to_owned(), Value::UInt(1));
        assert!(app_component("echo", Value::Map(m.clone())).is_ok());
        m.insert("component".to_owned(), Value::Str("other".into()));
        assert!(app_component("echo", Value::Map(m)).is_err());
    }
}
