//! `wyrmd`: Zenoh router runtime + static plugins + `wyrm-admin` + links.
//!
//! [`Daemon`] owns what survives a reload (the admin [`Control`]: registry,
//! CA, supervisor, audit). A [`Broker`] is one router runtime with its
//! plugins and in-process sessions; it is rebuilt when the ACL changes,
//! because Zenoh 1.10 cannot reload `access_control` live (ADR 0004).

#![forbid(unsafe_code)]

use serde::Deserialize;
use std::collections::BTreeMap;
use std::future::Future;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;
use wyrm_admin::{Attached, ConfigLink, Control, ControlConfig, EmbeddedHost, Mode, RunningLink};
use wyrm_core::Value;
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

    fn has_tls(&self) -> bool {
        self.listen
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
        c.insert_json5("listen/endpoints", &json(&self.listen))?;
        c.insert_json5("connect/endpoints", &json(&self.connect))?;
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
}

impl Broker {
    pub async fn start(cfg: &Config, ctl: &Arc<Control>) -> Result<Self, Error> {
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
        runtime.start().await?;
        Ok(Self {
            runtime,
            session,
            admin: Some(admin),
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
        if let Some(a) = self.admin.take() {
            a.stop().await;
        }
        self.session.close().await?;
        self.runtime.close().await?;
        Ok(())
    }
}

pub struct Daemon {
    cfg: Config,
    ctl: Arc<Control>,
    reload: tokio::sync::mpsc::UnboundedReceiver<()>,
}

impl Daemon {
    /// Open state and CA, apply `wyrmd.json5` links. `link_exe` hosts
    /// process links (`<link_exe> link <driver>`), normally this binary.
    pub fn open(cfg: Config, link_exe: PathBuf) -> Result<Self, Error> {
        let ctl_cfg = ControlConfig {
            site: cfg.site.clone(),
            data_dir: cfg.data_dir.clone(),
            admin_keys: cfg.admin_keys()?,
            operators: cfg.operators.clone(),
            dev: cfg.profile == Profile::Dev,
            link_endpoint: cfg.link_endpoint(),
            tls_names: cfg.tls_names.clone(),
            metrics_interval: Duration::from_millis(cfg.metrics_interval_ms.max(100)),
            link_exe,
            max_restarts: cfg.max_restarts,
        };
        let (ctl, reload) = Control::open(ctl_cfg, Arc::new(Drivers))?;
        ctl.bootstrap(&cfg.config_links())?;
        Ok(Self { cfg, ctl, reload })
    }

    pub fn control(&self) -> Arc<Control> {
        self.ctl.clone()
    }

    /// Serve until `shutdown` completes; rebuild the broker on reload requests.
    pub async fn run_until(mut self, shutdown: impl Future<Output = ()>) -> Result<(), Error> {
        tokio::pin!(shutdown);
        loop {
            let broker = Broker::start(&self.cfg, &self.ctl).await?;
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
