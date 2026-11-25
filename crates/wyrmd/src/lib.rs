//! `wyrmd`: Zenoh router runtime + static plugins + `wyrm-admin` + links.
//!
//! [`Daemon`] owns what survives a reload (the admin [`Control`]: registry,
//! CA, supervisor, audit; the flow store and signing key). A [`Broker`] is one router runtime with its
//! plugins and in-process sessions; it is rebuilt when the ACL changes,
//! because Zenoh 1.10 cannot reload `access_control` live (ADR 0006).

#![forbid(unsafe_code)]

pub mod announce;
pub mod arbiter;
pub mod cli;
pub mod gateway_tls;
pub mod standby;
pub mod update;

use serde::Deserialize;
use std::collections::BTreeMap;
use std::future::Future;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::oneshot;
use wyrm_admin::audit::AuditOp;
use wyrm_admin::control::{ALARM_LINK, DQL_LINK, SCHEDULER_LINK, STORAGE_LINK, UPLINK_LINK};
use wyrm_admin::{
    Attached, ConfigLink, Control, ControlConfig, EmbeddedHost, Mode, PeerConfig, RunningLink,
    UpstreamConf,
};
use wyrm_core::Value;
use wyrm_example_portable::Echo;
use wyrm_flow::{Engine, EngineStart, FlowHost};
use wyrm_gateway::{AuditEvent, Gateway, GatewayConfig};
use wyrm_link_agent::{Agent, AgentConfig};
use wyrm_link_alarm::Alarm;
use wyrm_link_dql::Dql;
use wyrm_link_gdrive::GDrive;
use wyrm_link_http::Http;
use wyrm_link_localfs::LocalFs;
use wyrm_link_mock::df::MockDev;
use wyrm_link_mock::{Mock, MockConfig};
use wyrm_link_modbus::Modbus;
use wyrm_link_mqtt::Mqtt;
use wyrm_link_portable::{Portable, PortableConfig};
use wyrm_link_prometheus::Prometheus;
use wyrm_link_s3::S3;
use wyrm_link_s7::S7;
use wyrm_link_scheduler::Scheduler;
use wyrm_link_sdk::driver::{Framework, Tree};
use wyrm_link_sdk::{FromParams, Link, LinkConfig, LinkError, LinkHandle, VerifyingKey};
use wyrm_link_snmp::Snmp;
use wyrm_link_uplink::Uplink;
use wyrm_link_wasm::ComponentWorld;
use wyrm_link_wasm::Wasm;
use wyrm_link_webdav::WebDav;
use wyrm_storage::{Storage, StorageStart};
use zenoh::internal::plugins::PluginsManager;
use zenoh::internal::runtime::{Runtime, RuntimeBuilder};
use zenoh::Session;
use zenoh_plugin_rest::RestPlugin;
use zenoh_plugin_storage_manager::StoragesPlugin;

pub type Error = zenoh::Error;

/// `Debug` of an error that `main` may return: its text in quotes, as the
/// `String` it replaces printed (`Error: "updates.trial_s 5: 10 to 3600"`),
/// not the name of its variant. See [`OpenError`].
macro_rules! debug_as_text {
    ($($t:ty),+ $(,)?) => {$(
        impl std::fmt::Debug for $t {
            fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                std::fmt::Debug::fmt(&self.to_string(), f)
            }
        }
    )+};
}
pub(crate) use debug_as_text;

/// A store that did not open. Its text is the line `wyrmd` printed for it
/// when these errors were strings: the name of what the store belongs to
/// (`gateway: …`) and the cause's text, or the cause's text alone when that
/// names the store itself (`storage: …`, `history store: …`).
///
/// `Debug` is the same text in quotes, not the fields: `main` returns its
/// error, the runtime prints it with `{:?}`, and operators read
/// `Error: "storage: File exists (os error 17)"`. The cause stays the
/// [`source`](std::error::Error::source), so [`store_held`] still sees it.
#[derive(thiserror::Error)]
pub struct OpenError {
    what: Option<&'static str>,
    #[source]
    source: Error,
}

impl OpenError {
    /// `<what>: <the cause's text>`.
    pub fn new(what: &'static str, source: impl Into<Error>) -> Self {
        Self {
            what: Some(what),
            source: source.into(),
        }
    }

    /// The cause's text as it is: it names the store already.
    pub fn named(source: impl Into<Error>) -> Self {
        Self {
            what: None,
            source: source.into(),
        }
    }
}

impl std::fmt::Display for OpenError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self.what {
            Some(what) => write!(f, "{what}: {}", self.source),
            None => write!(f, "{}", self.source),
        }
    }
}

impl std::fmt::Debug for OpenError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        // as the `String` error it replaces prints
        std::fmt::Debug::fmt(&self.to_string(), f)
    }
}

/// The error of [`Control::open`] for the start line: a history store that
/// did not open prints its text (`history store: …`), as it did when
/// `Control::open` made a string of it. Every other error is as it was.
fn control_open_error(e: Error) -> Error {
    match e.downcast::<wyrm_history::store::Error>() {
        Ok(history) => OpenError::named(*history).into(),
        Err(e) => e,
    }
}

/// `e`, or one of its causes, says that a store is held: a `wyrm-state` WAL
/// (its `LOCK`), the flows store, the broker storage or the history index is open in another
/// process, or in a daemon of this one that is still closing. Opening it
/// again a moment later may succeed.
pub fn store_held(e: &(dyn std::error::Error + 'static)) -> bool {
    let mut at = Some(e);
    while let Some(e) = at {
        if matches!(e.downcast_ref(), Some(wyrm_state::StateError::InUse(_)))
            || matches!(e.downcast_ref(), Some(wyrm_flow::HostError::InUse(_)))
            || matches!(e.downcast_ref(), Some(wyrm_storage::Error::InUse(_)))
            || matches!(e.downcast_ref(), Some(wyrm_history::store::Error::InUse(_)))
        {
            return true;
        }
        at = e.source();
    }
    false
}

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
    /// The embedded DQL link at `wy/<site>/downstream/dql` (ADR 0025).
    #[serde(default)]
    pub dql: DqlSection,
    /// The embedded alarm link at `wy/<site>/downstream/alarm` (ADR 0034).
    #[serde(default)]
    pub alarm: AlarmSection,
    /// The embedded uplink at `wy/<site>/downstream/uplink` (ADR 0035): platform upstreams.
    #[serde(default)]
    pub uplink: UplinkSection,
    /// A warm standby pair (ADR 0036): the other broker of this site. With
    /// it, `wyrmd` follows the other broker until it is away, then opens
    /// the daemon on the followed `data_dir`.
    #[serde(default)]
    pub standby: Option<standby::StandbySection>,
    /// Backups made from `sys/backups` and kept in `data_dir/backups`
    /// (ADR 0048).
    #[serde(default)]
    pub backups: BackupsSection,
    /// The broker's own update (ADR 0048 §2): off by default.
    #[serde(default)]
    pub updates: update::UpdatesSection,
    /// The file this configuration was read from (set by `wyrmd`): the
    /// `config` section of a backup copies it.
    #[serde(skip)]
    pub config_file: Option<PathBuf>,
}

/// The text fields of `wyrmd.json5` that the `config` section of a backup
/// shows (ADR 0048 §3.2), by key path (`*`: any one key): the ones known to
/// hold no secret. Every other text of the file is masked
/// (`wyrm_admin::secrets::mask_config`), so a field that is not here, or a
/// section this list does not know, is never in a backup in clear. A new
/// text field of [`Config`] goes here or into [`CONFIG_MASKED`]: the test
/// `every_text_field_of_the_config_is_shown_or_masked_on_purpose` fails
/// until it is in one of them.
const CONFIG_SHOWN: &[&str] = &[
    "site",
    "profile",
    "data_dir",
    "listen",
    "connect",
    "tls_names",
    // public keys
    "admin_keys",
    "operators",
    "rest",
    "state_anchor_dir",
    "links.*.driver",
    "links.*.mode",
    "peers.listen",
    "peers.enroll",
    "peers.upstream.site",
    "peers.upstream.endpoint",
    "peers.upstream.ca",
    "peers.upstream.cert",
    "peers.downstream.site",
    "peers.downstream.via",
    "packages.repository",
    "packages.seed_dir",
    "gateway.listen",
    "gateway.tls",
    "gateway.tls_cert",
    "gateway.admin_user",
    "gateway.setup_file",
    "gateway.mcp.public_url",
    "gateway.mcp.redirect_uris",
    "gateway.tls_ca",
    "gateway.devices.step_up",
    "gateway.devices.origins",
    "gateway.announce.interfaces",
    "gateway.announce.pair",
    "uplink.net",
    "standby.peer",
    "standby.witness",
    "standby.arbiter",
    // the release keys are public keys
    "updates.mode",
    "updates.channel",
    "updates.keys",
    "backups.send_links",
    "backups.send_links.link",
    "backups.send_links.folder",
];

/// The text fields of `wyrmd.json5` that are masked on purpose: where a
/// private key is (a path, and a name that says secret), and what a link
/// or a platform upstream is given (free maps: any text may be a secret).
/// Masked is the default; this list is what the test checks a choice by.
#[cfg(test)]
const CONFIG_MASKED: &[&str] = &[
    "gateway.tls_key",
    "peers.upstream.key",
    "links.*.params",
    "uplink.upstreams",
];

/// The configuration file `path` as JSON, for the `config` section of a
/// backup: masked by default, [`CONFIG_SHOWN`] in clear. `None` when it
/// cannot be read.
fn masked_config(path: &std::path::Path) -> Option<String> {
    let text = std::fs::read_to_string(path).ok()?;
    let mut v: serde_json::Value = json5::from_str(&text).ok()?;
    wyrm_admin::secrets::mask_config(&mut v, CONFIG_SHOWN);
    serde_json::to_string_pretty(&v).ok()
}

/// `backups` in `wyrmd.json5`.
#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct BackupsSection {
    /// Days a backup stays on the broker (1 to 3650).
    #[serde(default = "default_backup_days")]
    pub keep_days: u32,
    /// Most MiB of backups kept; the oldest are removed first, the newest
    /// one never.
    #[serde(default = "default_backup_mb")]
    pub max_mb: u64,
    /// Secrets may leave this broker in a backup sealed with a passphrase
    /// the caller picks: the `keys` section (the site CA, `state.key`,
    /// `secrets.key`, the gateway keys, `secrets.bin`, link tokens) and link
    /// secrets that open on any broker. Off by default: whoever has
    /// `config` on `sys` would else turn a session into the site's
    /// identity. Set it on the host, for the time it is needed.
    #[serde(default)]
    pub export_secrets: bool,
    /// The file-store links (S3, WebDAV, Google Drive, a local directory)
    /// the broker may send a kept backup through (`sys/backups/<id>` ▸
    /// `send`), each with the folder backups land in: `{link, folder}`, or
    /// a link id alone for the folder `backups`. Empty (the default):
    /// `send` is refused. Only these links trust the broker's backup sender
    /// key, and a send writes below that folder only.
    #[serde(default)]
    pub send_links: Vec<SendLinkEntry>,
}

/// One entry of `backups.send_links`.
#[derive(Debug, Clone, Deserialize)]
#[serde(untagged)]
pub enum SendLinkEntry {
    /// A link id: the folder is `backups`.
    Link(String),
    Folder {
        link: String,
        #[serde(default = "default_send_folder")]
        folder: String,
    },
}

fn default_send_folder() -> String {
    "backups".to_owned()
}

/// Why `backups.send_links` is refused when the configuration is read.
#[derive(thiserror::Error)]
pub enum SendLinksError {
    /// An entry's link is no link id.
    #[error("backups.send_links: {0}")]
    Link(#[source] wyrm_admin::registry::LinkIdError),
    /// The folder of `link` is no plain relative path.
    #[error("backups.send_links: link {link}: {source}")]
    Folder {
        link: String,
        #[source]
        source: wyrm_admin::control::send::FolderError,
    },
    /// The link is listed twice.
    #[error("backups.send_links: link {0} twice (one folder a link)")]
    Twice(String),
}

debug_as_text!(SendLinksError);

impl SendLinkEntry {
    fn checked(&self) -> Result<wyrm_admin::SendLink, SendLinksError> {
        let (link, folder) = match self {
            Self::Link(link) => (link.clone(), default_send_folder()),
            Self::Folder { link, folder } => (link.clone(), folder.trim_matches('/').to_owned()),
        };
        wyrm_admin::registry::validate_link_id(&link).map_err(SendLinksError::Link)?;
        if let Err(source) = wyrm_admin::control::send::check_folder(&folder) {
            return Err(SendLinksError::Folder { link, source });
        }
        Ok(wyrm_admin::SendLink { link, folder })
    }
}

fn default_backup_days() -> u32 {
    7
}

fn default_backup_mb() -> u64 {
    2048
}

impl BackupsSection {
    /// `send_links` checked: link ids, plain relative folders, one folder
    /// a link.
    pub fn checked_send_links(&self) -> Result<Vec<wyrm_admin::SendLink>, SendLinksError> {
        let mut out: Vec<wyrm_admin::SendLink> = Vec::new();
        for e in &self.send_links {
            let entry = e.checked()?;
            if out.iter().any(|o| o.link == entry.link) {
                return Err(SendLinksError::Twice(entry.link));
            }
            out.push(entry);
        }
        Ok(out)
    }
}

impl Default for BackupsSection {
    fn default() -> Self {
        Self {
            keep_days: default_backup_days(),
            max_mb: default_backup_mb(),
            export_secrets: false,
            send_links: Vec::new(),
        }
    }
}

/// `alarm` in `wyrmd.json5`: on by default.
#[derive(Debug, Clone, Copy, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct AlarmSection {
    #[serde(default = "default_true")]
    pub enabled: bool,
    /// Size of its store (classes, records, the journal) in MiB.
    #[serde(default = "default_alarm_store_mb")]
    pub store_mb: u32,
    /// Closed records older than this are purged (by whole pages).
    #[serde(default = "default_alarm_retention_days")]
    pub retention_days: u64,
    /// Records kept at most; the oldest closed ones go beyond it.
    #[serde(default = "default_alarm_max_records")]
    pub max_records: u64,
}

impl Default for AlarmSection {
    fn default() -> Self {
        Self {
            enabled: true,
            store_mb: default_alarm_store_mb(),
            retention_days: default_alarm_retention_days(),
            max_records: default_alarm_max_records(),
        }
    }
}

/// `uplink` in `wyrmd.json5`: on by default. `net` is the link's allowlist (ADR 0012 syntax,
/// host names allowed: `broker.example:8883, *.azure-devices.net:8883, 10.0.0.5:1883`); without
/// it no platform is reachable. `upstreams` are definitions as the Add actions take them, with
/// `kind` and `name` (shown as `origin: config`, read-only; the secret still goes in with Set
/// Password).
#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct UplinkSection {
    #[serde(default = "default_true")]
    pub enabled: bool,
    /// Size of its store (definitions and secrets) in MiB.
    #[serde(default = "default_uplink_store_mb")]
    pub store_mb: u32,
    #[serde(default)]
    pub net: String,
    #[serde(default)]
    pub upstreams: Vec<serde_json::Value>,
}

impl Default for UplinkSection {
    fn default() -> Self {
        Self {
            enabled: true,
            store_mb: default_uplink_store_mb(),
            net: String::new(),
            upstreams: Vec::new(),
        }
    }
}

fn default_alarm_store_mb() -> u32 {
    64
}
fn default_alarm_retention_days() -> u64 {
    wyrm_link_alarm::limits::DEFAULT_RETENTION_DAYS
}
fn default_alarm_max_records() -> u64 {
    wyrm_link_alarm::limits::DEFAULT_MAX_RECORDS
}
fn default_uplink_store_mb() -> u32 {
    2
}

/// `dql` in `wyrmd.json5`: on by default.
#[derive(Debug, Clone, Copy, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DqlSection {
    #[serde(default = "default_true")]
    pub enabled: bool,
    /// Size of its store (the query definitions) in MiB.
    #[serde(default = "default_dql_store_mb")]
    pub store_mb: u32,
}

impl Default for DqlSection {
    fn default() -> Self {
        Self {
            enabled: true,
            store_mb: default_dql_store_mb(),
        }
    }
}

fn default_dql_store_mb() -> u32 {
    16
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
/// start (only if the user does not exist yet), never from this file; or the
/// first admin comes from a setup code whose hash `setup_file` holds (ADR 0051 §3).
#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct GatewaySection {
    pub listen: std::net::SocketAddr,
    /// `"site_ca"`: the broker issues the gateway's certificate from its own site CA into
    /// `data_dir/gateway/tls.{pem,key}` (ADR 0051 §3); excludes `tls_cert` and `tls_key`.
    #[serde(default)]
    pub tls: Option<GatewayTls>,
    /// Certificate chain and key (PEM); required off loopback unless `tls` is set.
    #[serde(default)]
    pub tls_cert: Option<PathBuf>,
    #[serde(default)]
    pub tls_key: Option<PathBuf>,
    #[serde(default)]
    pub session_ttl_s: Option<u64>,
    /// Name of the first admin user.
    #[serde(default = "default_gateway_admin")]
    pub admin_user: String,
    /// A file with the hash of a one-time setup code (64 hex digits, `wyrmd setup-code`;
    /// ADR 0051 §3). Read at start while no user exists: the hash becomes the pending
    /// setup and the file is removed. Absent or missing: no setup from a file.
    #[serde(default)]
    pub setup_file: Option<PathBuf>,
    /// The remote MCP endpoint `/mcp` for Claude's connectors, with its
    /// OAuth 2.1 server (ADR 0041 stage B). Absent = off.
    #[serde(default)]
    pub mcp: Option<GatewayMcpSection>,
    /// The CA certificate (PEM) the gateway's certificate chains to, whose code the Trust
    /// screen compares (ADR 0050 §2). Default: the last certificate of `tls_cert` when it
    /// holds a chain, else the site CA when it issued the gateway's certificate.
    #[serde(default)]
    pub tls_ca: Option<PathBuf>,
    /// Device keys and the step-up (ADR 0050 §1.6). Absent: the defaults.
    #[serde(default)]
    pub devices: Option<GatewayDevicesSection>,
    /// The DNS-SD announce (ADR 0050 §2.1). Absent: on when the gateway listens off
    /// loopback.
    #[serde(default)]
    pub announce: Option<GatewayAnnounceSection>,
}

/// `gateway.tls`: where the gateway's certificate comes from when no files are named.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum GatewayTls {
    /// Issued by the broker from its own site CA (ADR 0051 §3).
    SiteCa,
}

impl GatewaySection {
    /// The certificate chain and key the gateway serves (PEM): `tls_cert` and `tls_key`
    /// when both are set, `data_dir/gateway/tls.{pem,key}` for `tls: "site_ca"`, else
    /// `None` (plain HTTP on loopback). The one place every reader takes them from.
    pub fn tls_files(&self, data_dir: &std::path::Path) -> Option<(PathBuf, PathBuf)> {
        match (&self.tls_cert, &self.tls_key, self.tls) {
            (Some(c), Some(k), _) => Some((c.clone(), k.clone())),
            (_, _, Some(GatewayTls::SiteCa)) => Some(gateway_tls::files(data_dir)),
            _ => None,
        }
    }
}

/// `gateway.devices` (ADR 0050 §1.6).
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct GatewayDevicesSection {
    /// `false` refuses device logins and keeps the records (default true).
    #[serde(default)]
    pub enabled: Option<bool>,
    /// Devices that can log in, per user, 1 … 20 (default 5).
    #[serde(default)]
    pub max_per_user: Option<u32>,
    /// A device sees the password at least this often, 1 … 365 days (default 30).
    #[serde(default)]
    pub password_every_days: Option<u32>,
    /// Studio's idle lock may be set up to this, 1 … 1440 minutes (default 30).
    #[serde(default)]
    pub idle_lock_max_min: Option<u32>,
    /// `"config"`: every request at `config` level needs a session confirmed in the last
    /// 5 minutes; `"none"` (default).
    #[serde(default)]
    pub step_up: Option<String>,
    /// A screen PIN or a computer's login password may stand in for biometrics (default
    /// false).
    #[serde(default)]
    pub allow_device_credential: Option<bool>,
    /// Origins a device key may sign for (`https://host[:port]`); default the names of
    /// the gateway's certificate on its port. List the standby's too when it has its own.
    #[serde(default)]
    pub origins: Vec<String>,
}

/// `gateway.announce` (ADR 0050 §2.1).
#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct GatewayAnnounceSection {
    /// Default true; hardened sites turn it off.
    #[serde(default = "default_true")]
    pub enabled: bool,
    /// Interface names to announce on (default: those the gateway listens on).
    #[serde(default)]
    pub interfaces: Vec<String>,
    /// The other gateway of a standby pair, `host:port` (default: the host of
    /// `standby.peer` with this gateway's port).
    #[serde(default)]
    pub pair: Option<String>,
}

impl GatewayDevicesSection {
    /// The policy the gateway runs with, bounds checked.
    pub fn policy(&self) -> Result<wyrm_gateway::DevicePolicy, Error> {
        let d = wyrm_gateway::DevicePolicy::default();
        let within = |what: &str, v: Option<u32>, lo: u32, hi: u32, def: u64| match v {
            None => Ok(def),
            Some(v) if (lo..=hi).contains(&v) => Ok(v.into()),
            Some(v) => Err(format!("gateway.devices.{what}: {v} is not in {lo} … {hi}")),
        };
        let step_up = match self.step_up.as_deref() {
            None | Some("none") => wyrm_gateway::StepUp::None,
            Some("config") => wyrm_gateway::StepUp::Config,
            Some(o) => {
                return Err(format!("gateway.devices.step_up: {o:?} is not config or none").into())
            }
        };
        for o in &self.origins {
            if wyrm_gateway::devices::parse_origin(o).is_none() {
                return Err(
                    format!("gateway.devices.origins: {o:?} is not scheme://host[:port]").into(),
                );
            }
        }
        Ok(wyrm_gateway::DevicePolicy {
            enabled: self.enabled.unwrap_or(d.enabled),
            max_per_user: within(
                "max_per_user",
                self.max_per_user,
                1,
                20,
                d.max_per_user as u64,
            )? as usize,
            password_every_days: within(
                "password_every_days",
                self.password_every_days,
                1,
                365,
                d.password_every_days,
            )?,
            idle_lock_max_min: within(
                "idle_lock_max_min",
                self.idle_lock_max_min,
                1,
                1440,
                d.idle_lock_max_min,
            )?,
            step_up,
            allow_device_credential: self.allow_device_credential.unwrap_or(false),
            origins: self.origins.clone(),
            ..d
        })
    }
}

/// The DER of the CA the gateway's certificate chains to (ADR 0050 §2): `tls_ca`, else the
/// last certificate of `tls_cert` when it holds a chain, else the site CA when it issued the
/// gateway's certificate. `None` without TLS or when none of these is known. Never creates
/// a CA. The one source of `ca_fp` (`/api/info`), the `fp` TXT key and `wyrmd ca
/// fingerprint`.
pub fn gateway_ca(cfg: &Config) -> Option<Vec<u8>> {
    use rustls_pki_types::pem::PemObject;
    use rustls_pki_types::CertificateDer;
    let g = cfg.gateway.as_ref()?;
    let certs = |path: &std::path::Path| -> Vec<Vec<u8>> {
        CertificateDer::pem_file_iter(path)
            .map(|it| it.filter_map(Result::ok).map(|c| c.to_vec()).collect())
            .unwrap_or_default()
    };
    if let Some(ca) = &g.tls_ca {
        return certs(ca).into_iter().next();
    }
    let (cert, _) = g.tls_files(&cfg.data_dir)?;
    let chain = certs(&cert);
    if chain.len() > 1 {
        return chain.last().cloned();
    }
    let leaf = chain.first()?;
    let site = certs(&cfg.data_dir.join("pki").join("ca.pem"))
        .into_iter()
        .next()?;
    let (_, l) = x509_parser::parse_x509_certificate(leaf).ok()?;
    let (_, c) = x509_parser::parse_x509_certificate(&site).ok()?;
    (l.issuer().as_raw() == c.subject().as_raw()
        && l.verify_signature(Some(c.public_key())).is_ok())
    .then_some(site)
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct GatewayMcpSection {
    /// The gateway as Claude reaches it: `https://broker.example[:port]`.
    pub public_url: String,
    /// Redirect URIs a client may register; default Claude's callbacks and
    /// `"loopback"` (MCP clients on the person's computer).
    #[serde(default)]
    pub redirect_uris: Option<Vec<String>>,
    /// Access token lifetime, 60 … 3600 s (default 3600).
    #[serde(default)]
    pub access_ttl_s: Option<u64>,
    /// Refresh token lifetime in days, 1 … 365 (default 30).
    #[serde(default)]
    pub refresh_days: Option<u64>,
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
#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PackagesSection {
    /// Index for "Install Link ▸ from Repository", JSON
    /// `[{name, version, description, url, sha256}]` (as DSA's
    /// `linkRepositoryUrl`); https, or http to loopback. `"official"`: the
    /// index of this project's link releases (ADR 0043). Unset: none, the
    /// broker never fetches one.
    #[serde(default)]
    pub repository: Option<String>,
    /// Days a replaced package version and the restore points of its links
    /// are kept for a rollback (ADR 0048); 1 to 365.
    #[serde(default = "default_keep_previous_days")]
    pub keep_previous_days: u32,
    /// A read-only directory with `seed.json` and link packages (ADR 0051
    /// §1): on its first start the broker installs each listed package as
    /// `install_zip` does and writes `data_dir/seed.done`. Unset: no seed.
    #[serde(default)]
    pub seed_dir: Option<PathBuf>,
}

fn default_keep_previous_days() -> u32 {
    7
}

impl Default for PackagesSection {
    fn default() -> Self {
        Self {
            repository: None,
            keep_previous_days: default_keep_previous_days(),
            seed_dir: None,
        }
    }
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
    /// Its users may run `config` actions on our site: `sys`, links, flows
    /// and storage (ADR 0018); `write` on links, flows and storage they
    /// always have.
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
                standby: self.listen.is_some(),
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
    /// By name; `None`: embedded. Another name refuses the file.
    #[serde(default, with = "wyrm_core::named::serde_opt")]
    pub mode: Option<Mode>,
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

fn json<T: serde::Serialize>(v: &T) -> Result<String, serde_json::Error> {
    serde_json::to_string(v)
}

impl Config {
    pub fn from_json5(text: &str) -> Result<Self, Error> {
        let cfg: Config = json5::from_str(text).map_err(|e| format!("wyrmd.json5: {e}"))?;
        wyrm_core::keyspace::validate_segment(&cfg.site).map_err(|e| format!("site: {e}"))?;
        cfg.backups.checked_send_links()?;
        cfg.updates.validate()?;
        // `downstream/<d>` is the broker node of downstream site d (ADR 0007).
        for d in &cfg.peers.downstream {
            if cfg.links.contains_key(&d.site) {
                return Err(format!("links.{}: the name of a downstream site", d.site).into());
            }
            // `downstream/scheduler`, `downstream/dql`, `downstream/alarm` and `downstream/uplink`
            // are built-in links (ADR 0022, 0025, 0034, 0035)
            if [SCHEDULER_LINK, DQL_LINK, ALARM_LINK, UPLINK_LINK].contains(&d.site.as_str()) {
                return Err(
                    format!("peers.downstream {}: the id belongs to the broker", d.site).into(),
                );
            }
        }
        for (name, mb) in [
            ("scheduler", cfg.scheduler.store_mb),
            ("dql", cfg.dql.store_mb),
            ("alarm", cfg.alarm.store_mb),
            ("uplink", cfg.uplink.store_mb),
        ] {
            if !(1..=wyrm_link_portable::MAX_STORE_MB).contains(&mb) {
                return Err(format!(
                    "{name}.store_mb {mb}: expected 1 to {}",
                    wyrm_link_portable::MAX_STORE_MB
                )
                .into());
            }
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
        if let Some(s) = &cfg.standby {
            s.validate(cfg.peers.listen.is_some())?;
        }
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
            match (&g.tls_cert, &g.tls_key, g.tls) {
                (None, None, Some(GatewayTls::SiteCa)) => {}
                (_, _, Some(GatewayTls::SiteCa)) => {
                    return Err(r#"gateway: tls "site_ca" excludes tls_cert and tls_key"#.into())
                }
                (Some(_), Some(_), None) => {}
                (None, None, None) if g.listen.ip().is_loopback() => {}
                (None, None, None) => {
                    return Err(format!(
                        "gateway {}: TLS (tls_cert, tls_key) is required off loopback",
                        g.listen
                    )
                    .into())
                }
                _ => return Err("gateway: set both tls_cert and tls_key".into()),
            }
            if let Some(d) = &g.devices {
                d.policy()?;
            }
        }
        for id in cfg.links.keys() {
            wyrm_core::keyspace::validate_segment(id).map_err(|e| format!("links.{id}: {e}"))?;
            // ids of the broker's own links (ADR 0017, 0022, 0025, 0034)
            if [
                STORAGE_LINK,
                SCHEDULER_LINK,
                DQL_LINK,
                ALARM_LINK,
                UPLINK_LINK,
            ]
            .contains(&id.as_str())
            {
                return Err(format!("links.{id}: the id belongs to the broker").into());
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
                mode: l.mode.unwrap_or(Mode::Embedded),
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
        let listen: Vec<String> = listen.iter().map(|e| single_stream(e)).collect();
        let connect: Vec<String> = connect.iter().map(|e| single_stream(e)).collect();
        c.insert_json5("listen/endpoints", &json(&listen)?)?;
        c.insert_json5("connect/endpoints", &json(&connect)?)?;
        if let Some(hz) = self.peers.upstream_val_hz {
            let links: Vec<String> = ctl.registry().links.into_keys().collect();
            if let Some(d) = upstream_downsampling(&self.site, &links, hz) {
                c.insert_json5("downsampling", &d.to_string())?;
            }
        }
        c.insert_json5(
            "scouting/multicast/enabled",
            &json(&self.multicast_scouting)?,
        )?;
        // Storages require timestamps.
        c.insert_json5(
            "timestamping/enabled",
            r#"{ router: true, peer: true, client: true }"#,
        )?;
        // `~val` only, in memory: the broker keeps its own state with
        // wyrm-state (ADR 0029, decision 4); rocksdb is a dynamic `.so`.
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

/// A `quic/` endpoint on one QUIC stream (`?multistream=0`). With Zenoh 1.10's default
/// (`auto`) each priority has a stream of its own, and the order between them is lost: a
/// request (`DataHigh`) can reach the peer before the declaration (`Control`) of the key
/// expression it names, sent just before it (a `list` across a peer: the subscriber's key
/// first, then the query on its prefix). The peer cannot resolve that scope and drops the
/// request (its ACL interceptor does), and the query ends with no reply. One stream keeps the order, as TCP does; the
/// transmit queues still send by priority, so what is given up is only that a lost packet
/// holds up every priority, as on TCP. Either end that offers only one stream decides it
/// (ALPN), so a peer of an older broker agrees. Other endpoints, and one with metadata of its
/// own, are left as they are.
pub fn single_stream(endpoint: &str) -> String {
    let (addr, conf) = match endpoint.split_once('#') {
        Some((a, c)) => (a, Some(c)),
        None => (endpoint, None),
    };
    if !addr.starts_with("quic/") || addr.contains('?') {
        return endpoint.to_owned();
    }
    match conf {
        Some(c) => format!("{addr}?multistream=0#{c}"),
        None => format!("{addr}?multistream=0"),
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
/// `http` (`links/http`), embedded or as `wyrmd link http`.
/// `snmp` (SNMP v2c/v3), embedded or as `wyrmd link snmp`.
/// `s7` embedded or as `wyrmd link s7`.
/// `bacnet` (BACnet/IP client, `links/bacnet`) embedded or as `wyrmd link bacnet`.
/// `opcua` (OPC UA client, `links/opcua`) embedded or as a process.
/// `prometheus` (scrape connector), embedded or as `wyrmd link prometheus`.
/// `s3`, `gdrive`, `webdav` and `localfs` (file stores, `wyrm-filestore`), embedded or as
/// processes.
pub struct Drivers;

impl EmbeddedHost for Drivers {
    fn drivers(&self) -> Vec<&'static str> {
        vec![
            Mock::NAME,
            Framework::<MockDev>::NAME,
            Modbus::NAME,
            Mqtt::NAME,
            Http::NAME,
            Snmp::NAME,
            S7::NAME,
            wyrm_link_bacnet::Bacnet::NAME,
            wyrm_link_opcua::Opcua::NAME,
            Prometheus::NAME,
            S3::NAME,
            GDrive::NAME,
            WebDav::NAME,
            LocalFs::NAME,
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
            "http" => Tree::from_params(params).map(|_| ()),
            "snmp" => Tree::from_params(params).map(|_| ()),
            "s7" => Tree::from_params(params).map(|_| ()),
            "bacnet" => Tree::from_params(params).map(|_| ()),
            "opcua" => Tree::from_params(params).map(|_| ()),
            "prometheus" => Tree::from_params(params).map(|_| ()),
            "s3" => wyrm_filestore::store::validate::<wyrm_link_s3::S3Store>(params),
            "gdrive" => wyrm_filestore::store::validate::<wyrm_link_gdrive::GDriveStore>(params),
            "webdav" => wyrm_filestore::store::validate::<wyrm_link_webdav::WebDavStore>(params),
            "localfs" => wyrm_filestore::store::validate::<wyrm_link_localfs::LocalStore>(params),
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
                "http" => start_boxed::<Http>(session, cfg, params).await,
                "snmp" => start_boxed::<Snmp>(session, cfg, params).await,
                "s7" => start_boxed::<S7>(session, cfg, params).await,
                "bacnet" => start_boxed::<wyrm_link_bacnet::Bacnet>(session, cfg, params).await,
                "opcua" => start_boxed::<wyrm_link_opcua::Opcua>(session, cfg, params).await,
                "prometheus" => start_boxed::<Prometheus>(session, cfg, params).await,
                "s3" => start_boxed::<S3>(session, cfg, params).await,
                "gdrive" => start_boxed::<GDrive>(session, cfg, params).await,
                "webdav" => start_boxed::<WebDav>(session, cfg, params).await,
                "localfs" => start_boxed::<LocalFs>(session, cfg, params).await,
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
        "http" => wyrm_link_sdk::process::run::<Http>().await?,
        "snmp" => wyrm_link_sdk::process::run::<Snmp>().await?,
        "s7" => wyrm_link_sdk::process::run::<S7>().await?,
        "bacnet" => wyrm_link_sdk::process::run::<wyrm_link_bacnet::Bacnet>().await?,
        "opcua" => wyrm_link_sdk::process::run::<wyrm_link_opcua::Opcua>().await?,
        "prometheus" => wyrm_link_sdk::process::run::<Prometheus>().await?,
        "s3" => wyrm_link_sdk::process::run::<S3>().await?,
        "gdrive" => wyrm_link_sdk::process::run::<GDrive>().await?,
        "webdav" => wyrm_link_sdk::process::run::<WebDav>().await?,
        "localfs" => wyrm_link_sdk::process::run::<LocalFs>().await?,
        "agent" => wyrm_link_sdk::process::run::<Agent>().await?,
        "portable-echo" => wyrm_link_sdk::process::run::<Portable<Echo>>().await?,
        // the scheduler as a process link (ADR 0022 run modes)
        "scheduler" => wyrm_link_sdk::process::run::<Portable<Scheduler>>().await?,
        // the DQL link as a process link (ADR 0025 run modes)
        "dql" => wyrm_link_sdk::process::run::<Portable<Dql>>().await?,
        // the alarm link as a process link (ADR 0034 run modes)
        "alarm" => wyrm_link_sdk::process::run::<Portable<Alarm>>().await?,
        // the uplink as a process link (ADR 0035)
        "uplink" => wyrm_link_sdk::process::run::<Portable<Uplink>>().await?,
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
    dql: Option<LinkHandle<Portable<Dql>>>,
    alarm: Option<LinkHandle<Portable<Alarm>>>,
    uplink: Option<LinkHandle<Portable<Uplink>>>,
    gateway: Option<(oneshot::Sender<()>, tokio::task::JoinHandle<()>)>,
}

/// What the embedded alarm link may reach (ADR 0034): `read` on this site's `downstream`,
/// `dataflows` and `storage`. It writes nothing. Never `sys`, never other sites (D4 of ADR
/// 0025 left for later).
fn alarm_grants(site: &str) -> Vec<(String, wyrm_core::Perm)> {
    ["downstream", "dataflows", "storage"]
        .iter()
        .map(|s| (format!("wy/{site}/{s}"), wyrm_core::Perm::Read))
        .collect()
}

/// What the embedded uplink may reach (ADR 0035): `read` on this site's `downstream`,
/// `dataflows` and `storage` and on the sections of every downstream site this one reads (as
/// the DQL link). Never `sys`, never a write.
fn uplink_grants(site: &str, peers: &wyrm_admin::acl::Peers) -> Vec<(String, wyrm_core::Perm)> {
    dql_grants(site, peers)
        .into_iter()
        .map(|(k, _)| (k, wyrm_core::Perm::Read))
        .collect()
}

/// The embedded uplink's params: the site and its own key (never sent), the allowlist as text
/// (an Add refuses a host it does not cover) and the definitions from `wyrmd.json5`.
fn uplink_params(site: &str, section: &UplinkSection) -> Value {
    let mut m = BTreeMap::new();
    m.insert("site".to_owned(), Value::Str(site.to_owned()));
    m.insert(
        "own".to_owned(),
        Value::Str(format!("wy/{site}/downstream/{UPLINK_LINK}")),
    );
    m.insert("net".to_owned(), Value::Str(section.net.clone()));
    if !section.upstreams.is_empty() {
        m.insert(
            "upstreams".to_owned(),
            Value::Array(section.upstreams.iter().map(json_to_value).collect()),
        );
    }
    Value::Map(m)
}

/// What the embedded DQL link may reach (ADR 0025): `read` on this site's `downstream`,
/// `dataflows`, `storage` and `upstream` and on the sections of every downstream site this one
/// reads (ADR 0007, 0018; D4), `write` on this site's `downstream` for its sinks. Never `sys`.
fn dql_grants(site: &str, peers: &wyrm_admin::acl::Peers) -> Vec<(String, wyrm_core::Perm)> {
    use wyrm_core::Perm;
    // write first: a request token carries the first grant that covers its key
    let mut g = vec![(format!("wy/{site}/downstream"), Perm::Write)];
    g.extend(
        ["dataflows", "storage", "upstream"]
            .iter()
            .map(|s| (format!("wy/{site}/{s}"), Perm::Read)),
    );
    let mut others: Vec<String> = peers.reachable();
    others.sort();
    others.dedup();
    for o in others.iter().filter(|o| *o != site) {
        for s in ["downstream", "dataflows", "storage"] {
            g.push((format!("wy/{o}/{s}"), Perm::Read));
        }
    }
    g
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

/// What every embedded link of one router build starts from: the in-process session, the
/// config, the control plane and the gateway.
struct Embed<'a> {
    session: &'a Session,
    cfg: &'a Config,
    ctl: &'a Arc<Control>,
    gateway: Option<&'a Arc<Gateway>>,
}

/// The embedded portable links of one router build, each one only where its section
/// switches it on.
struct Portables {
    scheduler: Option<LinkHandle<Portable<Scheduler>>>,
    dql: Option<LinkHandle<Portable<Dql>>>,
    alarm: Option<LinkHandle<Portable<Alarm>>>,
    uplink: Option<LinkHandle<Portable<Uplink>>>,
}

impl Embed<'_> {
    /// The flow engine at `dataflows`.
    async fn engine(&self, host: &Arc<FlowHost>) -> Result<LinkHandle<Engine>, LinkError> {
        let (cfg, ctl) = (self.cfg, self.ctl);
        // The engine trusts admin keys and the gateway's (user requests),
        // never the flow key: flow tokens do not command flows.
        let mut engine_keys = ctl.config().admin_keys.clone();
        engine_keys.extend(self.gateway.map(|g| g.verifying_key()));
        let mut lcfg = LinkConfig::new(cfg.site.clone(), wyrm_admin::control::FLOWS_LINK);
        lcfg.root = Some(format!("wy/{}/dataflows", cfg.site));
        lcfg.admin_keys = engine_keys.clone();
        // upstream sites at write (ADR 0018); deploys need config. Their keys are also known
        // with the scopes the links and storage give them: a request here is still only
        // within `dataflows`, but a deployer's rights (`auth`) on the flow's sources and
        // targets are kept as far as those sections trust the key (ADR 0033).
        lcfg.limited_keys = [
            ctl.upstream_trust("dataflows"),
            ctl.upstream_trust("downstream"),
            ctl.upstream_trust("storage"),
        ]
        .concat();
        wyrm_link_sdk::spawn::<Engine>(
            self.session.clone(),
            lcfg,
            EngineStart {
                host: host.clone(),
                admin_keys: engine_keys,
                // a target is a link's or storage's: trusted as they trust upstream keys
                proof_keys: [
                    ctl.upstream_trust("downstream"),
                    ctl.upstream_trust("storage"),
                ]
                .concat(),
            },
        )
        .await
    }

    /// The broker storage at `storage` (ADR 0017), on `store`.
    async fn storage(
        &self,
        store: &Arc<wyrm_storage::Store>,
        flow_key: VerifyingKey,
    ) -> Result<LinkHandle<Storage>, LinkError> {
        let (cfg, ctl) = (self.cfg, self.ctl);
        // Storage (ADR 0017): the admin keys, users through the gateway and
        // flows at write, each only under `storage`; upstream sites at
        // write (ADR 0018); a link with a grant under `storage` within it
        // (ADR 0046; a grant change rebuilds the router, and this with it).
        let root = format!("wy/{}/storage", cfg.site);
        let mut lcfg = LinkConfig::new(cfg.site.clone(), STORAGE_LINK);
        lcfg.root = Some(root.clone());
        lcfg.admin_keys = ctl.config().admin_keys.clone();
        lcfg.limited_keys = std::iter::once((flow_key, wyrm_core::Perm::Write))
            .chain(
                self.gateway
                    .map(|g| (g.verifying_key(), wyrm_core::Perm::Config)),
            )
            .map(|(key, cap)| wyrm_link_sdk::LimitedKey {
                key,
                cap,
                scopes: vec![root.clone()],
                subject: None,
            })
            .chain(ctl.upstream_trust("storage"))
            .chain(ctl.requester_keys_under(&root))
            .collect();
        wyrm_link_sdk::spawn::<Storage>(
            self.session.clone(),
            lcfg,
            StorageStart {
                store: store.clone(),
                limits: Default::default(),
            },
        )
        .await
    }

    /// The scheduler (ADR 0022): trusted as every embedded link; it signs
    /// its writes with its own key, which links trust at write on
    /// `downstream` (made by the admin at attach; without it the broker
    /// runs without the scheduler, R22).
    async fn scheduler(&self) -> Result<LinkHandle<Portable<Scheduler>>, LinkError> {
        let cfg = self.cfg;
        let site_down = format!("wy/{}/downstream", cfg.site);
        match self
            .ctl
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
                wyrm_link_sdk::spawn::<Portable<Scheduler>>(self.session.clone(), lcfg, pcfg).await
            }
            Err(e) => Err(e),
        }
    }

    /// The DQL link (ADR 0025): as the scheduler. It reads this site's sections and the
    /// sections other sites let this one read (ADR 0018, D4), and writes only its sinks,
    /// signed with its own key, which links trust at write on `downstream`.
    async fn dql(&self) -> Result<LinkHandle<Portable<Dql>>, LinkError> {
        let (cfg, ctl) = (self.cfg, self.ctl);
        match ctl.embedded_link_config(DQL_LINK, dql_grants(&cfg.site, &ctl.peers())) {
            Ok(lcfg) => {
                let pcfg = PortableConfig {
                    store_mb: cfg.dql.store_mb,
                    ..PortableConfig::default()
                };
                wyrm_link_sdk::spawn::<Portable<Dql>>(self.session.clone(), lcfg, pcfg).await
            }
            Err(e) => Err(e),
        }
    }

    /// The alarm link (ADR 0034): as the scheduler; it only reads, so its key is trusted
    /// by nobody.
    async fn alarm(&self) -> Result<LinkHandle<Portable<Alarm>>, LinkError> {
        let cfg = self.cfg;
        match self
            .ctl
            .embedded_link_config(ALARM_LINK, alarm_grants(&cfg.site))
        {
            Ok(lcfg) => {
                let mut params = BTreeMap::new();
                params.insert(
                    "retention_days".to_owned(),
                    Value::UInt(cfg.alarm.retention_days),
                );
                params.insert("max_records".to_owned(), Value::UInt(cfg.alarm.max_records));
                let pcfg = PortableConfig {
                    params: Value::Map(params),
                    store_mb: cfg.alarm.store_mb,
                    ..PortableConfig::default()
                };
                wyrm_link_sdk::spawn::<Portable<Alarm>>(self.session.clone(), lcfg, pcfg).await
            }
            Err(e) => Err(e),
        }
    }

    /// The uplink (ADR 0035): as the DQL link, reads only; its network is `uplink.net`.
    async fn uplink(&self) -> Result<LinkHandle<Portable<Uplink>>, LinkError> {
        let (cfg, ctl) = (self.cfg, self.ctl);
        match ctl.embedded_link_config(UPLINK_LINK, uplink_grants(&cfg.site, &ctl.peers())) {
            Ok(lcfg) => {
                let net = wyrm_link_api::net::NetPolicy::parse(&cfg.uplink.net)
                    .map_err(|e| format!("uplink.net: {e}"));
                match net {
                    Ok(net) => {
                        let pcfg = PortableConfig {
                            params: uplink_params(&cfg.site, &cfg.uplink),
                            net,
                            store_mb: cfg.uplink.store_mb,
                            call_ms: 5_000,
                            ..PortableConfig::default()
                        };
                        wyrm_link_sdk::spawn::<Portable<Uplink>>(self.session.clone(), lcfg, pcfg)
                            .await
                    }
                    Err(e) => Err(LinkError::invalid_parameter(e)),
                }
            }
            Err(e) => Err(e),
        }
    }

    /// The scheduler, the DQL link, the alarm link and the uplink, in this order, each one
    /// where its section switches it on. When one does not start, the ones started before it
    /// are stopped, last first, and its error is returned.
    async fn portables(&self) -> Result<Portables, Error> {
        let ctl = self.ctl;
        let scheduler = if ctl.scheduler_runs() {
            match self.scheduler().await {
                Ok(h) => Some(h),
                Err(e) => return Err(format!("scheduler: {e}").into()),
            }
        } else {
            None
        };
        let dql = if ctl.dql_runs() {
            match self.dql().await {
                Ok(h) => Some(h),
                Err(e) => {
                    if let Some(s) = scheduler {
                        s.stop().await;
                    }
                    return Err(format!("dql: {e}").into());
                }
            }
        } else {
            None
        };
        let alarm = if ctl.alarm_runs() {
            match self.alarm().await {
                Ok(h) => Some(h),
                Err(e) => {
                    if let Some(d) = dql {
                        d.stop().await;
                    }
                    if let Some(s) = scheduler {
                        s.stop().await;
                    }
                    return Err(format!("alarm: {e}").into());
                }
            }
        } else {
            None
        };
        let uplink = if ctl.uplink_runs() {
            match self.uplink().await {
                Ok(h) => Some(h),
                Err(e) => {
                    if let Some(a) = alarm {
                        a.stop().await;
                    }
                    if let Some(d) = dql {
                        d.stop().await;
                    }
                    if let Some(s) = scheduler {
                        s.stop().await;
                    }
                    return Err(format!("uplink: {e}").into());
                }
            }
        } else {
            None
        };
        Ok(Portables {
            scheduler,
            dql,
            alarm,
            uplink,
        })
    }
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
        let mut admin = ctl.attach(session.clone()).await?;
        if let Some(g) = gateway {
            // downstream sites may have changed at runtime (install, quarantine)
            g.set_downstream_sites(ctl.peers().reachable());
            g.set_upstream_sites(ctl.peers().upstream.clone());
            // which links are agents is the registry's word, never a link's own (ADR 0049)
            g.set_agent_links(
                ctl.registry()
                    .links
                    .values()
                    .filter(|l| l.driver == "agent")
                    .map(|l| l.id.clone())
                    .collect(),
            );
        }
        let embed = Embed {
            session: &session,
            cfg,
            ctl,
            gateway,
        };
        let flow_key = flows.verifying_key();
        let flows = match embed.engine(flows).await {
            Ok(h) => h,
            Err(e) => {
                admin.stop().await;
                return Err(format!("flow engine: {e}").into());
            }
        };
        let storage = match embed.storage(storage, flow_key).await {
            Ok(h) => h,
            Err(e) => {
                flows.stop().await;
                admin.stop().await;
                return Err(format!("storage: {e}").into());
            }
        };
        let portables = match embed.portables().await {
            Ok(p) => p,
            Err(e) => {
                storage.stop().await;
                flows.stop().await;
                admin.stop().await;
                return Err(e);
            }
        };
        runtime.start().await?;
        // seed packages on the first start (ADR 0051 §1), once the link
        // endpoint listens
        admin.start_seed();
        // a site-CA certificate follows the host's addresses while the gateway serves
        let site_ca = cfg
            .gateway
            .as_ref()
            .filter(|g| g.tls == Some(GatewayTls::SiteCa))
            .map(|_| Arc::new(cfg.clone()));
        let gateway = gateway.map(|gw| {
            let (tx, rx) = oneshot::channel::<()>();
            let (gw, s) = (gw.clone(), session.clone());
            let task = tokio::spawn(async move {
                let serve = gw.clone().serve(s, async {
                    let _ = rx.await;
                });
                let follow = async {
                    if let Some(cfg) = site_ca {
                        gateway_tls::watch(cfg, gw.clone(), gateway_tls::WATCH_EVERY).await;
                    }
                    std::future::pending::<()>().await;
                };
                // the watch ends with the serve (dropped), never the other way round
                let r = tokio::select! {
                    r = serve => r,
                    () = follow => Ok(()),
                };
                if let Err(e) = r {
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
            scheduler: portables.scheduler,
            dql: portables.dql,
            alarm: portables.alarm,
            uplink: portables.uplink,
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
        // first: they send requests to the other links
        if let Some(a) = self.alarm.take() {
            a.stop().await;
        }
        if let Some(u) = self.uplink.take() {
            u.stop().await;
        }
        if let Some(d) = self.dql.take() {
            d.stop().await;
        }
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
    pub result: Result<wyrm_state::Report, VerifyError>,
}

impl StoreCheck {
    /// A torn last record counts as a problem here: without an anchor a
    /// crash and an edited last record look the same (open drops it).
    pub fn ok(&self) -> bool {
        matches!(&self.result, Ok(r) if r.anchor_ok != Some(false) && !r.torn_tail)
    }
}

/// Existing hex key file; never creates one.
fn read_key(path: &std::path::Path) -> Result<zeroize::Zeroizing<Vec<u8>>, KeyFileError> {
    let text = std::fs::read_to_string(path).map_err(|source| KeyFileError::Read {
        path: path.to_path_buf(),
        source,
    })?;
    let k = zeroize::Zeroizing::new(
        hex::decode(text.trim()).map_err(|_| KeyFileError::NotHex(path.to_path_buf()))?,
    );
    if k.len() != 32 {
        return Err(KeyFileError::Length(path.to_path_buf()));
    }
    Ok(k)
}

/// A key file of a control-plane store that gives no key.
#[derive(thiserror::Error)]
pub enum KeyFileError {
    #[error("{}: {source}", .path.display())]
    Read {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    /// The decoder's own error is not kept: it names a character of the
    /// file, and the file holds a key.
    #[error("{}: not hex", .0.display())]
    NotHex(PathBuf),
    #[error("{}: expected 32 bytes", .0.display())]
    Length(PathBuf),
}

/// Why a store did not pass [`verify_state`]: its text is the line `wyrmd
/// verify` prints after `FAILED: `.
#[derive(thiserror::Error)]
pub enum VerifyError {
    #[error(transparent)]
    Key(#[from] KeyFileError),
    #[error(transparent)]
    Store(#[from] wyrm_state::StateError),
}

debug_as_text!(KeyFileError, VerifyError);

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
            let result = read_key(&key).map_err(VerifyError::Key).and_then(|k| {
                wyrm_state::verify(&dir, &k, anchor.as_deref()).map_err(VerifyError::Store)
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
        // the stores of a running broker: say what to do instead
        let in_use = |e: Error| -> Error {
            if store_held(&*e) {
                format!("{e} (stop wyrmd, or use the gateway HTTP API)").into()
            } else {
                // text, as before the typed errors: `wyrmd user` prints the
                // Debug of what it returns, and nobody reads the type further
                e.to_string().into()
            }
        };
        let gw = open_gateway(cfg, g, false).map_err(in_use)?;
        let key = wyrm_admin::secret::load_or_create_key(&cfg.data_dir.join("state.key"))?;
        let audit = wyrm_state::Store::open(cfg.data_dir.join("audit"), &key)
            .map_err(|e| in_use(OpenError::named(e).into()))?;
        Ok(Self {
            gw,
            audit: std::sync::Mutex::new(audit),
        })
    }

    pub fn gateway(&self) -> &Gateway {
        &self.gw
    }

    /// An audit record for a change made here (`sub` = `local:cli`).
    pub fn record(&self, op: AuditOp, user: &str, detail: &str) -> Result<(), Error> {
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

/// The certificate or key of `gateway.tls: "site_ca"` is not there yet.
fn site_ca_files_missing(cfg: &Config) -> bool {
    let (cert, key) = gateway_tls::files(&cfg.data_dir);
    !(cert.is_file() && key.is_file())
}

fn open_gateway(cfg: &Config, g: &GatewaySection, bootstrap: bool) -> Result<Arc<Gateway>, Error> {
    let dir = cfg.data_dir.join("gateway");
    std::fs::create_dir_all(&dir)?;
    let hmac = wyrm_admin::secret::load_or_create_key(&dir.join("hmac.key"))?;
    if g.tls == Some(GatewayTls::SiteCa) && (bootstrap || site_ca_files_missing(cfg)) {
        // before `gateway_ca` and `Gateway::open` read the files; the CA is the one
        // `Control::open` opens later (made here on a first start). `wyrmd user …`
        // (no bootstrap) issues only when there is nothing to read: a running broker's
        // watch owns the files, and the lock of one issue holds in one process only
        let names = gateway_tls::names_now(cfg, g.listen);
        gateway_tls::issue(cfg, &names)?;
        tracing::info!(?names, "gateway: certificate from the site CA");
    }
    let mut gc = GatewayConfig::new(cfg.site.clone(), dir, g.listen);
    // every site below this one, also through a chain
    gc.downstream_sites = cfg.peers.peer_config().peers.reachable();
    gc.anchor = cfg.state_anchor_dir.as_ref().map(|d| d.join("users.head"));
    gc.anchor_init = cfg.init_anchors;
    gc.tls = g.tls_files(&cfg.data_dir);
    if let Some(s) = g.session_ttl_s {
        gc.session_ttl = Duration::from_secs(s.clamp(60, 7 * 86_400));
    }
    if let Some(m) = &g.mcp {
        let mut mc = wyrm_gateway::McpConfig::new(m.public_url.clone());
        if let Some(r) = &m.redirect_uris {
            mc.redirect_uris = r.clone();
        }
        if let Some(s) = m.access_ttl_s {
            mc.access_ttl = Duration::from_secs(s.clamp(60, 3600));
        }
        if let Some(d) = m.refresh_days {
            mc.refresh_ttl = Duration::from_secs(d.clamp(1, 365) * 86_400);
        }
        gc.mcp = Some(mc);
    }
    if let Some(d) = &g.devices {
        gc.devices = d.policy()?;
    }
    gc.info = wyrm_gateway::InfoConfig {
        ca: gateway_ca(cfg),
        pair: announce::pair_of(cfg),
        up: cfg.peers.upstream.iter().map(|u| u.site.clone()).collect(),
    };
    let gw = Gateway::open(gc, &hmac).map_err(|e| OpenError::new("gateway", e))?;
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
    if let Some(f) = &g.setup_file {
        import_setup_file(&gw, f);
    }
    // a setup file beside a user is void (a restored backup, a crash before its
    // removal); a damaged one is told here, once, as `/api/info` shows no `setup`
    match gw.settle_setup() {
        Ok(true) => tracing::info!("gateway: waiting for the first admin from the setup code"),
        Ok(false) => {}
        Err(e) => tracing::error!(
            path = %pending_setup_path(cfg).display(),
            error = %e,
            "gateway: the pending setup cannot be read, so no setup code is taken; \
             start again with a good gateway.setup_file (docs/operations.md)"
        ),
    }
    Ok(gw)
}

/// The gateway's pending setup (`data_dir/gateway/setup.hash`).
fn pending_setup_path(cfg: &Config) -> PathBuf {
    cfg.data_dir.join("gateway").join(wyrm_gateway::setup::FILE)
}

/// `gateway.setup_file` at start (ADR 0051 §3): its hash becomes the pending setup and
/// the file goes. A file that is not 64 hex digits (white space around them aside) stays
/// and is logged with its path; so does one the gateway could not store, for the next
/// start. Never logs the content.
fn import_setup_file(gw: &Gateway, path: &std::path::Path) {
    let text = match std::fs::read_to_string(path) {
        Ok(t) => zeroize::Zeroizing::new(t),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return,
        Err(e) => {
            tracing::warn!(path = %path.display(), error = %e, "gateway: setup file not read");
            return;
        }
    };
    let hex = text.trim();
    if hex.len() != 64 || !hex.bytes().all(|b| b.is_ascii_hexdigit()) {
        tracing::warn!(
            path = %path.display(),
            "gateway: setup file is not 64 hex digits (wyrmd setup-code): not taken"
        );
        return;
    }
    match gw.import_setup(hex) {
        Ok(true) => tracing::info!(path = %path.display(), "gateway: setup code taken in"),
        Ok(false) => tracing::info!(
            path = %path.display(),
            "gateway: setup file ignored: a user exists"
        ),
        Err(e) => {
            tracing::error!(path = %path.display(), error = %e, "gateway: setup file not taken");
            return;
        }
    }
    if let Err(e) = std::fs::remove_file(path) {
        tracing::warn!(
            path = %path.display(),
            error = %e,
            "gateway: setup file not removed (void once a user exists)"
        );
    }
}

/// The gateway's roles behind `sys` Get/Update Permissions.
/// Weak: the gateway's audit hook holds the control plane, which holds this; a strong
/// handle here would keep both, and the gateway's users store locked, after the daemon
/// ends, so a second daemon in the same process could not open it.
struct GatewayRoles(std::sync::Weak<Gateway>);

/// A role change asked of a gateway that has already closed (only while the broker stops).
#[derive(Debug, thiserror::Error)]
#[error("the gateway has closed")]
struct GatewayClosed;

impl GatewayRoles {
    fn gateway(&self) -> Result<Arc<Gateway>, wyrm_admin::control::RoleGrantsError> {
        self.0
            .upgrade()
            .ok_or_else(|| wyrm_admin::control::RoleGrantsError(Box::new(GatewayClosed)))
    }
}

impl wyrm_admin::control::RoleGrants for GatewayRoles {
    fn grants(&self) -> Vec<(String, String, wyrm_core::Perm)> {
        let Some(gw) = self.0.upgrade() else {
            return Vec::new();
        };
        gw.role_table()
            .iter()
            .flat_map(|(role, grants)| {
                grants
                    .iter()
                    .map(move |(k, p)| (role.to_owned(), k.clone(), *p))
            })
            .collect()
    }

    fn set_grant(
        &self,
        role: &str,
        key: &str,
        level: wyrm_core::Perm,
    ) -> Result<(), wyrm_admin::control::RoleGrantsError> {
        self.gateway()?
            .set_grant(role, key, level)
            .map_err(|e| wyrm_admin::control::RoleGrantsError(Box::new(e)))
    }

    fn revoke_widening(
        &self,
        keys: &[String],
        probe: &str,
    ) -> Result<Vec<(String, String, wyrm_core::Perm)>, wyrm_admin::control::RoleGrantsError> {
        self.gateway()?
            .revoke_widening(keys, probe)
            .map_err(|e| wyrm_admin::control::RoleGrantsError(Box::new(e)))
    }
}

/// The audit op of a request the gateway refused: the same name, in the journal's set.
fn denied_op(op: wyrm_gateway::DeniedFor) -> AuditOp {
    use wyrm_gateway::DeniedFor as D;
    match op {
        D::Meta => AuditOp::Meta,
        D::Children => AuditOp::Children,
        D::List => AuditOp::List,
        D::Subscribe => AuditOp::Subscribe,
        D::Unsubscribe => AuditOp::Unsubscribe,
        D::Set => AuditOp::Set,
        D::Invoke => AuditOp::Invoke,
        D::Check => AuditOp::Check,
        D::History => AuditOp::History,
        D::Doc => AuditOp::Doc,
        D::Approve => AuditOp::Approve,
        D::ConfirmRequired => AuditOp::ConfirmRequired,
    }
}

/// Gateway events into the admin journal (no passwords or tokens in them).
fn gateway_audit(ctl: &Control, e: AuditEvent) {
    use wyrm_core::Status;
    match e {
        AuditEvent::LoginOk { user, ip } => ctl.record(
            &format!("user:{user}"),
            AuditOp::Login,
            "",
            Status::Ok,
            &ip.to_string(),
        ),
        AuditEvent::LoginFailed { user, ip, reason } => ctl.record(
            &format!("user:{user}"),
            AuditOp::Login,
            "",
            Status::PermissionDenied,
            &format!("{ip} {reason}"),
        ),
        AuditEvent::UserChanged { by, user, change } => {
            ctl.record(&by, AuditOp::User, &user, Status::Ok, change)
        }
        AuditEvent::Denied { user, op, key } => ctl.record(
            &format!("user:{user}"),
            denied_op(op),
            &key,
            Status::PermissionDenied,
            "gateway",
        ),
        AuditEvent::McpGranted {
            user,
            client,
            write,
            config,
        } => ctl.record(
            &format!("user:{user}"),
            AuditOp::McpSignIn,
            &client,
            Status::Ok,
            &format!("write={write} config={config}"),
        ),
        AuditEvent::Approved {
            user,
            task,
            steps,
            skipped,
        } => ctl.record(
            &format!("user:{user}"),
            AuditOp::Approve,
            &task,
            Status::Ok,
            &format!("signed={} skipped={skipped}", steps.join(",")),
        ),
        // device keys (ADR 0050): ids, names and codes, never a key, nonce or signature
        AuditEvent::DeviceAdded {
            user,
            device,
            name,
            platform,
            ip,
        } => ctl.record(
            &format!("user:{user}"),
            AuditOp::DeviceAdded,
            &device,
            Status::Ok,
            &format!("{ip} {platform} {name}"),
        ),
        AuditEvent::DeviceLogin { user, device, ip } => ctl.record(
            &format!("user:{user}"),
            AuditOp::DeviceLogin,
            &device,
            Status::Ok,
            &ip.to_string(),
        ),
        AuditEvent::DeviceRefused {
            user,
            device,
            ip,
            code,
        } => ctl.record(
            &user.map_or_else(|| "gateway".to_owned(), |u| format!("user:{u}")),
            AuditOp::DeviceRefused,
            &device,
            Status::PermissionDenied,
            &format!("{ip} {code}"),
        ),
        AuditEvent::StepUp {
            user,
            method,
            request,
        } => ctl.record(
            &format!("user:{user}"),
            AuditOp::StepUp,
            &request,
            Status::Ok,
            method,
        ),
        AuditEvent::DeviceRemoved { user, device, by } => ctl.record(
            &by,
            AuditOp::DeviceRemoved,
            &device,
            Status::Ok,
            &format!("user:{user}"),
        ),
        e => ctl.record("gateway", AuditOp::Event, "", Status::Ok, &format!("{e:?}")),
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

/// The control plane's config: its keys (the flow key and the gateway's, at their caps),
/// its places and the sections of `wyrmd.json5` it runs by.
fn control_config(
    cfg: &Config,
    flows: &FlowHost,
    gateway: Option<&Arc<Gateway>>,
    link_exe: PathBuf,
) -> Result<ControlConfig, Error> {
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
    link_keys.extend(gateway.map(|g| wyrm_link_sdk::LimitedKey {
        key: g.verifying_key(),
        cap: wyrm_core::Perm::Config,
        scopes: devices.clone(),
        subject: None,
    }));
    Ok(ControlConfig {
        site: cfg.site.clone(),
        data_dir: cfg.data_dir.clone(),
        admin_keys: cfg.admin_keys()?,
        control_keys: gateway.map(|g| g.verifying_key()).into_iter().collect(),
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
        repository: wyrm_admin::official::repository_url(cfg.packages.repository.as_deref()),
        scheduler: cfg.scheduler.enabled,
        dql: cfg.dql.enabled,
        alarm: cfg.alarm.enabled,
        uplink: cfg.uplink.enabled,
        backups: wyrm_admin::BackupConfig {
            keep_days: cfg.backups.keep_days.clamp(1, 3650),
            max_mb: cfg.backups.max_mb,
            export_secrets: cfg.backups.export_secrets,
            send_links: cfg.backups.checked_send_links()?,
            config: cfg.config_file.as_deref().and_then(masked_config),
            schemas: BTreeMap::from([
                (
                    "users".to_owned(),
                    <wyrm_gateway::users::UserDb as wyrm_state::State>::SCHEMA,
                ),
                (
                    "flows".to_owned(),
                    <wyrm_flow::store::FlowStore as wyrm_state::State>::SCHEMA,
                ),
            ]),
        },
        keep_previous_days: cfg.packages.keep_previous_days,
        seed_dir: cfg.packages.seed_dir.clone(),
        updates: update::update_config(cfg)?,
    })
}

/// What a start refuses in the registry: a link under the name of a downstream site, a link
/// under the id of the storage or of an embedded link, an upstream site that was a
/// downstream broker of this one.
fn refuse_taken_names(cfg: &Config, ctl: &Control) -> Result<(), Error> {
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
    // And for the embedded DQL link (ADR 0025): `downstream/dql`.
    if ctl.registry().links.contains_key(DQL_LINK) {
        return Err(format!(
            "a link with id {DQL_LINK:?} exists; the id belongs to the embedded DQL link (ADR 0025): remove the link with the previous wyrmd first"
        )
        .into());
    }
    // And for the embedded alarm link (ADR 0034): `downstream/alarm`.
    if ctl.registry().links.contains_key(ALARM_LINK) {
        return Err(format!(
            "a link with id {ALARM_LINK:?} exists; the id belongs to the embedded alarm link (ADR 0034): remove the link with the previous wyrmd first"
        )
        .into());
    }
    // And for the embedded uplink (ADR 0035): `downstream/uplink`.
    if ctl.registry().links.contains_key(UPLINK_LINK) {
        return Err(format!(
            "a link with id {UPLINK_LINK:?} exists; the id belongs to the embedded uplink (ADR 0035): remove the link with the previous wyrmd first"
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
    Ok(())
}

/// A restore applied at this start (`restored`), or one that was not applied: in the log
/// and in the audit.
fn record_restore(
    ctl: &Control,
    data_dir: &std::path::Path,
    restored: Option<wyrm_admin::control::restore_broker::Applied>,
) {
    if let Some(r) = restored {
        tracing::info!(sections = %wyrm_admin::backup::section_names(&r.sections), "restore applied");
        ctl.record(
            &r.by,
            AuditOp::RestoreApplied,
            &r.backup,
            wyrm_core::Status::Ok,
            &format!(
                "sections {}",
                wyrm_admin::backup::section_names(&r.sections)
            ),
        );
    }
    // a restore that was not applied: said once, where people look
    if let Some(f) = wyrm_admin::control::restore_broker::take_failure(data_dir) {
        tracing::error!(
            by = %f.by, backup = %f.backup,
            "the restore was not applied, the state before it is in place: {}", f.error
        );
        ctl.record(
            &f.by,
            AuditOp::RestoreFailed,
            &f.backup,
            wyrm_core::Status::InternalError,
            &format!(
                "sections {}; not applied, the state before it is in place: {}",
                wyrm_admin::backup::section_names(&f.sections),
                f.error
            ),
        );
    }
}

impl Daemon {
    /// Open state and CA, apply `wyrmd.json5` links. `link_exe` hosts
    /// process links (`<link_exe> link <driver>`), normally this binary.
    pub fn open(cfg: Config, link_exe: PathBuf) -> Result<Self, Error> {
        use wyrm_admin::control::restore_broker as restore;
        std::fs::create_dir_all(&cfg.data_dir)?;
        // A restore staged by `sys/backups/~act/restore_apply {mode: replace}`
        // (ADR 0048 §3.6): put in place before any store opens, all of it or
        // nothing. A plan that cannot be applied leaves the state as it was
        // (`Ok(None)`) and this start goes on with it.
        let data_dir = cfg.data_dir.clone();
        let restored = restore::apply_pending(&data_dir).map_err(|e| {
            format!("restore.pending: {e}. The state before the restore could not be put back")
        })?;
        let applied = restored.is_some();
        match Self::open_stores(cfg, link_exe, restored) {
            Ok(d) => {
                // the stores opened on it: what the restore replaced goes
                if applied {
                    restore::commit_pending(&data_dir);
                }
                Ok(d)
            }
            // The stores did not open on what the restore put in place:
            // everything goes back, and the next start (the supervisor's)
            // runs on the state before it and reports the failure.
            //
            // The error is text and `e` is not its source, on purpose: `e` is
            // about the restored state, which `undo_pending` has just taken
            // away, so it is no longer true of this `data_dir`. A caller that
            // opens again while `store_held` says so would start on the state
            // before the restore and never show this report; with a text it
            // gives the report to the operator, who starts again.
            Err(e) if applied => match restore::undo_pending(&data_dir, &e.to_string()) {
                Ok(()) => Err(format!(
                    "the restore was not applied ({e}): the state before it is back in place, \
                     start again"
                )
                .into()),
                Err(u) => Err(format!(
                    "the restore was not applied ({e}) and the state before it could not be \
                     put back ({u}): see restore.pending"
                )
                .into()),
            },
            Err(e) => Err(e),
        }
    }

    fn open_stores(
        cfg: Config,
        link_exe: PathBuf,
        restored: Option<wyrm_admin::control::restore_broker::Applied>,
    ) -> Result<Self, Error> {
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
        )
        .map_err(OpenError::named)?;
        // flow counters in `~val.stats` at the pace of `sys` metrics, never faster than
        // every 5 s: gateway and historian watchers of `dataflows/**` see each one (ADR 0045)
        flows.set_stats_every(Duration::from_millis(cfg.metrics_interval_ms.max(5_000)));
        let storage = Arc::new(
            wyrm_storage::Store::open(&cfg.data_dir.join("storage")).map_err(OpenError::named)?,
        );
        let gateway = match &cfg.gateway {
            None => None,
            Some(g) => Some(open_gateway(&cfg, g, true)?),
        };
        let ctl_cfg = control_config(&cfg, &flows, gateway.as_ref(), link_exe)?;
        let (ctl, reload) =
            Control::open(ctl_cfg, Arc::new(Drivers)).map_err(control_open_error)?;
        wyrm_link_wasm::set_component_root(ctl.component_store());
        ctl.set_storage(&storage);
        ctl.set_peers(cfg.peers.peer_config());
        // a site now in wyrmd.json5 and still in the registry: json5 wins
        ctl.drop_shadowed_peers();
        // watches stored with a tree route before routes resolved
        ctl.resolve_watch_routes();
        refuse_taken_names(&cfg, &ctl)?;
        ctl.issue_broker_certs()?;
        if let Some(gw) = &gateway {
            let audit = ctl.clone();
            gw.set_audit(move |e| gateway_audit(&audit, e));
            ctl.set_role_grants(Arc::new(GatewayRoles(Arc::downgrade(gw))));
        }
        ctl.bootstrap(&cfg.config_links())?;
        record_restore(&ctl, &cfg.data_dir, restored);
        // an update the guard took back is recorded by the version it
        // went back to (ADR 0048 §2.6)
        ctl.update_started();
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
        // Long actions are closed by this loop alone, before a rebuild, and
        // opened again by it once the next broker is up. A first start opens
        // nothing: the listeners answer before `Broker::start` returns (by
        // Zenoh's `scouting/delay`, 500 ms), so an unasked `reopen` there
        // would undo a `quiesce` taken meanwhile.
        let mut closed = false;
        loop {
            // Both QUIC listeners under one deadline: `STANDBY_HOLD` counts
            // on a single wait.
            let peers = &self.cfg.peers;
            let ports = [peers.listen.as_deref(), peers.enroll.as_deref()];
            let busy = wait_udp_free(
                &ports.into_iter().flatten().collect::<Vec<_>>(),
                QUIC_PORT_WAIT,
            )
            .await;
            if let Some(ep) = peers.listen.as_deref().filter(|ep| busy.contains(ep)) {
                tracing::warn!(
                    endpoint = %ep,
                    "QUIC peer port in use: downstream brokers cannot connect until a restart"
                );
            }
            if let Some(ep) = peers.enroll.as_deref().filter(|ep| busy.contains(ep)) {
                tracing::warn!(
                    endpoint = %ep,
                    "QUIC enrollment port in use: downstream brokers cannot enroll until a restart"
                );
            }
            let broker = Broker::start(
                &self.cfg,
                &self.ctl,
                &self.flows,
                &self.storage,
                self.gateway.as_ref(),
            )
            .await?;
            if std::mem::take(&mut closed) {
                self.ctl.reopen();
            }
            self.ctl.release_standby();
            tracing::info!(site = %self.cfg.site, locators = ?broker.locators(), "broker up");
            let reload = tokio::select! {
                _ = shutdown.as_mut() => false,
                // a restore staged in `restore.pending` (ADR 0048 §3.6):
                // stop cleanly, the supervisor starts the broker again
                _ = self.ctl.stop_requested() => {
                    tracing::info!("stop requested from sys: stopping for a restart");
                    false
                }
                r = self.reload.recv() => r.is_some(),
            };
            if reload {
                // A standby (ADR 0036) must not take the closed listeners
                // for an absence: it waits until the router is back (or the
                // hold runs out). It reads the hold with its next poll.
                self.ctl.hold_standby(STANDBY_HOLD);
                if self.ctl.standby_recent(Duration::from_secs(5)) {
                    tokio::time::sleep(STANDBY_HOLD_READ).await;
                }
                // A package install in flight finishes on this broker; new
                // ones answer `busy` until the next broker is up.
                closed = true;
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
/// restart in the same process) to let the QUIC peer ports go: one
/// deadline for all of them.
const QUIC_PORT_WAIT: Duration = Duration::from_secs(30);

/// How long a standby waits for a rebuild (ADR 0036): the QUIC port wait
/// and the router build, with room to spare. Released as soon as the
/// router is up.
const STANDBY_HOLD: Duration = Duration::from_secs(60);
/// How long the rebuild waits for a connected standby to read the hold (it
/// polls once a second).
const STANDBY_HOLD_READ: Duration = Duration::from_millis(2500);

/// Wait until the UDP ports of the `quic/<host>:<port>` endpoints are free,
/// all under one deadline `max` from now (each address once); returns the
/// endpoints whose port is still in use. The old runtime's QUIC endpoint
/// keeps a port while its connections drain; Zenoh 1.10.1 tries a listener
/// once (`listen/timeout_ms` 0), so a busy port would leave downstream
/// brokers out until the next restart.
async fn wait_udp_free<'a>(endpoints: &[&'a str], max: Duration) -> Vec<&'a str> {
    let deadline = std::time::Instant::now() + max;
    let mut done: Vec<(&str, bool)> = Vec::new();
    let mut busy = Vec::new();
    for &ep in endpoints {
        let Some(addr) = ep.strip_prefix("quic/") else {
            continue;
        };
        let free = match done.iter().find(|(a, _)| *a == addr) {
            Some(&(_, free)) => free,
            None => {
                let free = wait_addr_free(addr, deadline).await;
                done.push((addr, free));
                free
            }
        };
        if !free {
            busy.push(ep);
        }
    }
    busy
}

/// Wait until UDP `addr` can be bound, at least one try even past `deadline`.
async fn wait_addr_free(addr: &str, deadline: std::time::Instant) -> bool {
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

    /// What `main` prints for an error it returns: the runtime writes
    /// `Error: {e:?}` to stderr.
    fn start_line(e: &Error) -> String {
        format!("Error: {e:?}")
    }

    /// Audit T7, review of PR #171: a store that does not open at start
    /// prints the line it printed while these errors were strings (the
    /// broker before the typed errors), byte for byte. Each case is a real
    /// `Daemon::open` on a `data_dir` where the store's place is a file.
    #[cfg(unix)]
    #[tokio::test]
    async fn a_store_that_does_not_open_prints_its_old_start_line() {
        let dir = std::env::temp_dir().join(format!("wyrmd-startline-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let open = |name: &str, block: &str, gateway: &str| {
            let data = dir.join(name);
            let block = data.join(block);
            if let Some(parent) = block.parent() {
                std::fs::create_dir_all(parent).unwrap();
            }
            std::fs::write(&block, b"not a directory").unwrap();
            let cfg = Config::from_json5(&format!(
                r#"{{ site: "plant", data_dir: {data:?} {gateway} }}"#
            ))
            .unwrap();
            match Daemon::open(cfg, "wyrmd".into()) {
                Ok(_) => panic!("{name}: the daemon opened"),
                Err(e) => e,
            }
        };
        let e = open("storage", "storage", "");
        assert_eq!(
            start_line(&e),
            r#"Error: "storage: File exists (os error 17)""#
        );
        assert!(!store_held(&*e));
        let e = open(
            "gateway",
            "gateway/users",
            r#", gateway: { listen: "127.0.0.1:0" }"#,
        );
        assert_eq!(
            start_line(&e),
            r#"Error: "gateway: state: io: File exists (os error 17)""#
        );
        assert!(!store_held(&*e));
        let e = open("history", "history", "");
        assert_eq!(
            start_line(&e),
            r#"Error: "history store: Not a directory (os error 20)""#
        );
        assert!(!store_held(&*e));
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// Issue #180: a second `wyrmd` on a `data_dir` fails first on the flows
    /// store. A real `Daemon::open` while another host holds that store: the
    /// line is the cause's text in quotes, as for every other store (it was
    /// the cause's `Debug`, `Error: InUse("<data_dir>/flows/state")`), the
    /// text is the one of main, and the held store is told by its type.
    #[cfg(unix)]
    #[tokio::test]
    async fn a_held_flows_store_prints_its_start_line() {
        let dir = std::env::temp_dir().join(format!("wyrmd-flowsline-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let open = |data: &std::path::Path| {
            let cfg =
                Config::from_json5(&format!(r#"{{ site: "plant", data_dir: {data:?} }}"#)).unwrap();
            match Daemon::open(cfg, "wyrmd".into()) {
                Ok(_) => panic!("the daemon opened in {}", data.display()),
                Err(e) => e,
            }
        };
        let data = dir.join("held");
        let holder = FlowHost::open(&data.join("flows"), b"another-process", "plant").unwrap();
        let e = open(&data);
        let text = format!(
            "{} is in use by another process",
            data.join("flows/state").display()
        );
        assert_eq!(start_line(&e), format!("Error: {text:?}"));
        assert_eq!(e.to_string(), text);
        assert!(store_held(&*e));
        let cause = std::error::Error::source(&*e).and_then(|s| s.downcast_ref());
        assert!(
            matches!(cause, Some(wyrm_flow::HostError::InUse(_))),
            "{cause:?}"
        );
        drop(holder);
        // the store's place is a file: the old text, and nothing is held
        let data = dir.join("file");
        std::fs::create_dir_all(&data).unwrap();
        std::fs::write(data.join("flows"), b"not a directory").unwrap();
        let e = open(&data);
        assert_eq!(start_line(&e), r#"Error: "File exists (os error 17)""#);
        assert!(!store_held(&*e));
        // a flow key that is no key
        let data = dir.join("key");
        std::fs::create_dir_all(data.join("flows")).unwrap();
        std::fs::write(data.join("flows/flow.key"), b"zz").unwrap();
        let e = open(&data);
        assert_eq!(
            start_line(&e),
            r#"Error: "flow.key: expected 32 bytes hex""#
        );
        assert!(!store_held(&*e));
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// `wyrmd user` on a `data_dir` it cannot open: every error on the way to
    /// the gateway's stores prints as its text, not only the ones a store
    /// returns (second review of PR #171).
    #[cfg(unix)]
    #[test]
    fn user_admin_prints_its_old_line_for_an_error_before_the_stores() {
        let dir = std::env::temp_dir().join(format!("wyrmd-userline-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let open = |name: &str, prepare: &dyn Fn(&std::path::Path)| {
            let data = dir.join(name);
            std::fs::create_dir_all(&data).unwrap();
            prepare(&data);
            let cfg = Config::from_json5(&format!(
                r#"{{ site: "plant", data_dir: {data:?}, gateway: {{ listen: "127.0.0.1:0" }} }}"#
            ))
            .unwrap();
            match UserAdmin::open(&cfg) {
                Ok(_) => panic!("{name}: the user stores opened"),
                Err(e) => e,
            }
        };
        // the gateway's directory is a file
        let e = open("file", &|data| {
            std::fs::write(data.join("gateway"), b"not a directory").unwrap();
        });
        assert_eq!(start_line(&e), r#"Error: "File exists (os error 17)""#);
        // its HMAC key is not hex
        let e = open("key", &|data| {
            std::fs::create_dir_all(data.join("gateway")).unwrap();
            std::fs::write(data.join("gateway/hmac.key"), b"zz").unwrap();
        });
        assert_eq!(
            start_line(&e),
            r#"Error: "Invalid character 'z' at position 0""#
        );
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// The same for stores that are held, at every place `wyrmd` opens one:
    /// the old line, and the held store is still found through the wrapper.
    #[test]
    fn a_held_store_prints_its_old_start_line() {
        let dir = std::env::temp_dir().join(format!("wyrmd-heldline-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        // broker storage: `Daemon::open` and the standby
        let storage = wyrm_storage::Store::open(&dir.join("storage")).unwrap();
        let held = wyrm_storage::Store::open(&dir.join("storage"))
            .err()
            .unwrap();
        let held: Error = OpenError::named(held).into();
        assert_eq!(
            start_line(&held),
            r#"Error: "storage: Database already open. Cannot acquire lock.""#
        );
        assert_eq!(
            held.to_string(),
            "storage: Database already open. Cannot acquire lock."
        );
        assert!(store_held(&*held));
        // the historian, through `Control::open`
        let history_dir = dir.join("history");
        let history = wyrm_history::Store::open(&history_dir).unwrap();
        let held = |()| wyrm_history::Store::open(&history_dir).err().unwrap();
        let from_control = control_open_error(held(()).into());
        assert_eq!(
            start_line(&from_control),
            format!(
                "Error: {:?}",
                format!(
                    "history store: {} is in use by another process",
                    history_dir.display()
                )
            )
        );
        assert!(store_held(&*from_control));
        // the standby's history store
        let standby: Error = OpenError::new("history", held(())).into();
        assert_eq!(
            start_line(&standby),
            format!(
                "Error: {:?}",
                format!(
                    "history: history store: {} is in use by another process",
                    history_dir.display()
                )
            )
        );
        assert!(store_held(&*standby));
        // the gateway's user store, and the audit store of `wyrmd user`
        let state = || wyrm_state::StateError::InUse("/var/lib/wyrm/gateway/users".into());
        let gateway: Error = OpenError::new("gateway", wyrm_gateway::Error::State(state())).into();
        assert_eq!(
            start_line(&gateway),
            r#"Error: "gateway: state: /var/lib/wyrm/gateway/users is in use by another process""#
        );
        assert!(store_held(&*gateway));
        let audit: Error = OpenError::named(wyrm_state::StateError::Rejected("x".into())).into();
        assert_eq!(start_line(&audit), r#"Error: "operation rejected: x""#);
        assert!(!store_held(&*audit));
        // another error of `Control::open` is not touched
        let io: Error = std::io::Error::other("x").into();
        let io = control_open_error(io);
        assert!(io.downcast_ref::<std::io::Error>().is_some());
        // a text with a quote or a line break is escaped as a `String` is
        let odd: Error = OpenError::new("gateway", "a \"b\"\n").into();
        let text: Error = String::from("gateway: a \"b\"\n").into();
        assert_eq!(start_line(&odd), start_line(&text));
        drop((storage, history));
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// Audit T7: a store held by a closing daemon is told by its error's
    /// type, through boxes and [`OpenError`], never by its text; the texts
    /// stay as they were.
    #[test]
    fn a_held_store_is_told_by_its_type() {
        let dir = std::env::temp_dir().join(format!("wyrmd-held-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let storage = wyrm_storage::Store::open(&dir.join("storage")).unwrap();
        let held: Error = wyrm_storage::Store::open(&dir.join("storage"))
            .err()
            .unwrap()
            .into();
        assert!(store_held(&*held), "{held}");
        let history = wyrm_history::Store::open(&dir.join("history")).unwrap();
        let held = wyrm_history::Store::open(&dir.join("history"))
            .err()
            .unwrap();
        let held: Error = OpenError::new("history", held).into();
        assert!(store_held(&*held), "{held}");
        assert_eq!(
            held.to_string(),
            format!(
                "history: history store: {} is in use by another process",
                dir.join("history").display()
            )
        );
        // a state store behind the gateway's error, behind OpenError
        let state = wyrm_state::StateError::InUse("users".into());
        let held: Error = OpenError::new("gateway", wyrm_gateway::Error::State(state)).into();
        assert!(store_held(&*held), "{held}");
        assert_eq!(
            held.to_string(),
            "gateway: state: users is in use by another process"
        );
        // the words alone are no longer a held store
        let text: Error = "users is in use by another process".into();
        assert!(!store_held(&*text));
        let other: Error =
            OpenError::new("gateway", wyrm_gateway::Error::Config("x".into())).into();
        assert!(!store_held(&*other));
        drop((storage, history));
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// Review T5: `links.<id>.mode` was an `Option<String>` checked at load and parsed
    /// again where it was used. It is read as a [`Mode`] now; another name, also in
    /// another case, refuses the file, and a left-out mode is embedded.
    #[test]
    fn a_link_mode_is_one_of_three() {
        let parse = |mode: &str| {
            Config::from_json5(&format!(
                r#"{{ site: "s", links: {{ plc: {{ driver: "mock"{mode} }} }} }}"#
            ))
        };
        for (text, mode) in [
            ("", Mode::Embedded),
            (r#", mode: "embedded""#, Mode::Embedded),
            (r#", mode: "process""#, Mode::Process),
            (r#", mode: "external""#, Mode::External),
        ] {
            let cfg = parse(text).unwrap();
            assert_eq!(cfg.config_links()[0].mode, mode, "{text}");
        }
        for bad in [
            r#", mode: "Process""#,
            r#", mode: "remote""#,
            r#", mode: 1"#,
        ] {
            let e = parse(bad).err().map(|e| e.to_string()).unwrap_or_default();
            assert!(!e.is_empty(), "{bad}");
        }
        let e = parse(r#", mode: "remote""#).err().unwrap().to_string();
        assert!(e.contains("link mode: unknown name \"remote\""), "{e}");
    }

    /// Issue #145: the enrollment listener's port is waited for as the peer
    /// listener's is, both under one deadline (`STANDBY_HOLD` counts on one
    /// wait), each address once; a port let go meanwhile ends the wait.
    #[tokio::test]
    async fn quic_ports_wait_under_one_deadline() {
        let a = std::net::UdpSocket::bind("127.0.0.1:0").unwrap();
        let b = std::net::UdpSocket::bind("127.0.0.1:0").unwrap();
        let ea = format!("quic/{}", a.local_addr().unwrap());
        let eb = format!("quic/{}", b.local_addr().unwrap());
        let max = Duration::from_secs(2);
        let t0 = std::time::Instant::now();
        let busy = wait_udp_free(&[&ea, &eb, &ea, "tls/127.0.0.1:1"], max).await;
        let took = t0.elapsed();
        assert_eq!(busy, [ea.as_str(), eb.as_str(), ea.as_str()]);
        // a wait of `max` per address would take at least 2 × max
        assert!(took >= max && took < 2 * max, "{took:?}");

        let release = tokio::spawn(async move {
            tokio::time::sleep(Duration::from_millis(300)).await;
            drop((a, b));
        });
        let busy = wait_udp_free(&[&ea, &eb], Duration::from_secs(30)).await;
        assert!(busy.is_empty(), "{busy:?}");
        release.await.unwrap();
    }

    /// Every QUIC endpoint of the router is one stream; its config stays after `#`.
    #[test]
    fn quic_endpoints_are_one_stream() {
        assert_eq!(
            single_stream("quic/0.0.0.0:7448"),
            "quic/0.0.0.0:7448?multistream=0"
        );
        assert_eq!(
            single_stream("quic/c.example:7448#root_ca_certificate_file=/a/ca.pem"),
            "quic/c.example:7448?multistream=0#root_ca_certificate_file=/a/ca.pem"
        );
        assert_eq!(
            single_stream("quic/h:1#a=b?c"),
            "quic/h:1?multistream=0#a=b?c"
        );
        for kept in [
            "tls/0.0.0.0:7447",
            "tcp/127.0.0.1:7447",
            "quic/h:1?multistream=1",
        ] {
            assert_eq!(single_stream(kept), kept);
        }
        let ep: zenoh::config::EndPoint =
            single_stream("quic/h:1#enable_mtls=false").parse().unwrap();
        assert_eq!(ep.metadata().get("multistream"), Some("0"));
        assert_eq!(ep.config().get("enable_mtls"), Some("false"));
    }

    /// One certificate code everywhere (ADR 0050): `/api/info` `ca_fp`, the `fp` TXT key and
    /// `wyrmd ca fingerprint` all come from [`gateway_ca`]: the site CA that issued the
    /// gateway's certificate, the last of a chain, or `tls_ca`.
    #[test]
    fn one_certificate_code_everywhere() {
        use rustls_pki_types::pem::PemObject;
        let dir = std::env::temp_dir().join(format!("wyrmd-cacode-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let data = dir.join("data");
        let pki = wyrm_admin::secret::Pki::open_or_create(&data.join("pki")).unwrap();
        let f = pki
            .issue(
                "gateway",
                &["127.0.0.1".into(), "gw.plant.example".into()],
                true,
                &dir,
                "gw",
            )
            .unwrap();
        let ca_der = rustls_pki_types::CertificateDer::from_pem_file(pki.ca_path())
            .unwrap()
            .to_vec();
        let cfg_of = |extra: &str| {
            Config::from_json5(&format!(
                r#"{{ site: "plant", data_dir: {:?}, gateway: {{ listen: "127.0.0.1:0",
                    tls_cert: {:?}, tls_key: {:?} {extra} }} }}"#,
                data, f.cert, f.key
            ))
            .unwrap()
        };
        let cfg = cfg_of("");
        let der = gateway_ca(&cfg).expect("the site CA issued it");
        assert_eq!(der, ca_der);
        let fp = wyrm_gateway::devices::ca_fingerprint(&der);
        let txt = announce::txt("plant", true, gateway_ca(&cfg).as_deref(), None, &[]);
        assert!(txt.contains(&("fp".to_owned(), fp.clone())));
        let gw = open_gateway(&cfg, cfg.gateway.as_ref().unwrap(), false).unwrap();
        let info = gw.info();
        let Value::Map(m) = &info else { panic!() };
        assert_eq!(m.get("ca_fp"), Some(&Value::Str(fp.clone())));
        assert_eq!(m.get("ca"), Some(&Value::Bytes(ca_der.clone())));
        assert_eq!(
            m.get("names"),
            Some(&Value::Array(vec![
                Value::from("127.0.0.1"),
                Value::from("gw.plant.example")
            ]))
        );
        drop(gw);
        // a chain in tls_cert: its last certificate
        let chain = dir.join("chain.pem");
        let mut pem = std::fs::read(&f.cert).unwrap();
        pem.extend(std::fs::read(pki.ca_path()).unwrap());
        std::fs::write(&chain, pem).unwrap();
        let mut c = cfg_of("");
        c.gateway.as_mut().unwrap().tls_cert = Some(chain);
        assert_eq!(gateway_ca(&c), Some(ca_der.clone()));
        // tls_ca names it; a leaf no CA known issued has no code
        let mut c = cfg_of("");
        c.gateway.as_mut().unwrap().tls_ca = Some(f.cert.clone());
        assert_ne!(gateway_ca(&c), Some(ca_der.clone()));
        let mut c = cfg_of("");
        c.data_dir = dir.join("elsewhere");
        assert_eq!(gateway_ca(&c), None);
        // another site CA of the same name (`CN=wyrm-ca`, a restore of other keys): the
        // leaf of the first does not chain to it, so it has no code
        let other = dir.join("other");
        let other_pki = wyrm_admin::secret::Pki::open_or_create(&other.join("pki")).unwrap();
        let other_der = rustls_pki_types::CertificateDer::from_pem_file(other_pki.ca_path())
            .unwrap()
            .to_vec();
        assert_ne!(other_der, ca_der);
        let mut c = cfg_of("");
        c.data_dir = other;
        assert_eq!(gateway_ca(&c), None);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn device_policy_is_checked() {
        let p = |d: &str| {
            Config::from_json5(&format!(
                r#"{{ site: "s", gateway: {{ listen: "127.0.0.1:8443", devices: {d} }} }}"#
            ))
        };
        let ok =
            p(r#"{ step_up: "config", max_per_user: 3, origins: ["https://gw.example:8443"] }"#)
                .unwrap();
        let pol = ok.gateway.unwrap().devices.unwrap().policy().unwrap();
        assert_eq!(pol.step_up, wyrm_gateway::StepUp::Config);
        assert_eq!((pol.max_per_user, pol.password_every_days), (3, 30));
        for bad in [
            r#"{ step_up: "always" }"#,
            r#"{ password_every_days: 0 }"#,
            r#"{ max_per_user: 50 }"#,
            r#"{ origins: ["gw.example"] }"#,
            r#"{ nonsense: 1 }"#,
        ] {
            assert!(p(bad).is_err(), "{bad}");
        }
    }

    #[test]
    fn site_ca_is_accepted_off_loopback() {
        let cfg = Config::from_json5(
            r#"{ site: "s", gateway: { listen: "0.0.0.0:8445", tls: "site_ca" } }"#,
        )
        .unwrap();
        assert_eq!(cfg.gateway.unwrap().tls, Some(GatewayTls::SiteCa));
    }

    #[test]
    fn site_ca_excludes_tls_files() {
        for files in [
            r#"tls_cert: "/x.pem""#,
            r#"tls_key: "/x.key""#,
            r#"tls_cert: "/x.pem", tls_key: "/x.key""#,
        ] {
            let e = Config::from_json5(&format!(
                r#"{{ site: "s", gateway: {{ listen: "0.0.0.0:8445", tls: "site_ca", {files} }} }}"#
            ))
            .unwrap_err();
            assert!(
                e.to_string()
                    .contains(r#"gateway: tls "site_ca" excludes tls_cert and tls_key"#),
                "{files}: {e}"
            );
        }
        assert!(Config::from_json5(
            r#"{ site: "s", gateway: { listen: "0.0.0.0:8445", tls: "acme" } }"#
        )
        .is_err());
    }

    #[test]
    fn tls_files_of_site_ca() {
        let g = |gw: &str| {
            Config::from_json5(&format!(r#"{{ site: "s", gateway: {gw} }}"#))
                .unwrap()
                .gateway
                .unwrap()
        };
        let d = std::path::Path::new("/d");
        assert_eq!(
            g(r#"{ listen: "0.0.0.0:8445", tls: "site_ca" }"#).tls_files(d),
            Some((
                PathBuf::from("/d/gateway/tls.pem"),
                PathBuf::from("/d/gateway/tls.key")
            ))
        );
        assert_eq!(
            g(r#"{ listen: "0.0.0.0:8445", tls_cert: "/x.pem", tls_key: "/x.key" }"#).tls_files(d),
            Some((PathBuf::from("/x.pem"), PathBuf::from("/x.key")))
        );
        assert_eq!(g(r#"{ listen: "127.0.0.1:8445" }"#).tls_files(d), None);
    }

    /// The structs `wyrmd.json5` is read into, each with the key path of
    /// its fields.
    const CONFIG_STRUCTS: &[(&str, &str)] = &[
        ("Config", ""),
        ("BackupsSection", "backups"),
        ("AlarmSection", "alarm"),
        ("UplinkSection", "uplink"),
        ("DqlSection", "dql"),
        ("SchedulerSection", "scheduler"),
        ("GatewaySection", "gateway"),
        ("GatewayMcpSection", "gateway.mcp"),
        ("GatewayDevicesSection", "gateway.devices"),
        ("GatewayAnnounceSection", "gateway.announce"),
        ("PeersSection", "peers"),
        ("PackagesSection", "packages"),
        ("UpstreamPeer", "peers.upstream"),
        ("DownstreamPeer", "peers.downstream"),
        ("LinkSection", "links.*"),
        ("LinkLimits", "link_limits"),
        ("StandbySection", "standby"),
        ("UpdatesSection", "updates"),
    ];

    /// `(field, type)` of every `pub` field of `pub struct <name>` in `src`.
    fn fields_of(src: &str, name: &str) -> Option<Vec<(String, String)>> {
        let start = src.find(&format!("pub struct {name} {{"))?;
        let body = &src[start..];
        let body = &body[..body.find("\n}")?];
        Some(
            body.lines()
                .filter_map(|l| {
                    let l = l.trim().strip_prefix("pub ")?.strip_suffix(',')?;
                    let (field, ty) = l.split_once(": ")?;
                    Some((field.to_owned(), ty.to_owned()))
                })
                .collect(),
        )
    }

    /// The choice is made on purpose (ADR 0048 §3.2): every field of the
    /// configuration that holds text is on the list of fields a backup
    /// shows or on the list of fields it masks. A new field that is on
    /// neither fails here (it would be masked: masked is the default, but
    /// `updates.channel` is shown in the config copy of a backup. A channel
    /// with a credential is refused when the configuration is read; a file
    /// that has one all the same loses it in the copy (the second net of
    /// `mask_config`: a shown text keeps no userinfo and nothing after `?`
    /// or `#`).
    #[test]
    fn a_credential_in_the_update_channel_is_never_in_the_config_copy() {
        let dir = std::env::temp_dir().join(format!("wyrmd-channel-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("wyrmd.json5");
        let text = r#"{ site: "s", updates: { mode: "external",
            channel: "https://user:tok@host.example/x?sig=abc" } }"#;
        std::fs::write(&path, text).unwrap();
        let e = Config::from_json5(text).unwrap_err().to_string();
        assert!(e.contains("updates.channel"), "{e}");
        assert!(!e.contains("tok") && !e.contains("abc"), "{e}");
        let copy = masked_config(&path).unwrap();
        // no part of the credential is in the copy (the copy is not printed)
        let leaked = ["user", "tok", "sig", "abc"]
            .iter()
            .filter(|part| copy.contains(*part))
            .count();
        assert_eq!(
            leaked, 0,
            "parts of the URL's credential in the config copy"
        );
        assert!(copy.contains("host.example"), "the host is shown");
        assert!(copy.contains("external"), "the mode is shown");
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// nobody chose). Read from the sources: the structs are `Deserialize`
    /// only.
    #[test]
    fn every_text_field_of_the_config_is_shown_or_masked_on_purpose() {
        let sources = [
            include_str!("lib.rs"),
            include_str!("standby.rs"),
            include_str!("update.rs"),
        ];
        let listed = |path: &str| CONFIG_SHOWN.contains(&path) || CONFIG_MASKED.contains(&path);
        let mut found = std::collections::BTreeSet::new();
        for (name, prefix) in CONFIG_STRUCTS {
            let fields = sources
                .iter()
                .find_map(|s| fields_of(s, name))
                .unwrap_or_else(|| panic!("struct {name} is not in the sources"));
            assert!(!fields.is_empty(), "{name}: no fields read");
            for (field, ty) in fields {
                // not read from the file
                if *name == "Config" && field == "config_file" {
                    continue;
                }
                let path = match prefix {
                    &"" => field.clone(),
                    p => format!("{p}.{field}"),
                };
                // a struct of its own: its fields are checked under its name
                let idents: Vec<&str> = ty
                    .split(|c: char| !c.is_ascii_alphanumeric() && c != '_')
                    .filter(|w| !w.is_empty())
                    .collect();
                let nested: Vec<&&str> = idents
                    .iter()
                    .filter(|w| {
                        w.ends_with("Section") || w.ends_with("Peer") || w.ends_with("Limits")
                    })
                    .collect();
                if !nested.is_empty() {
                    for n in nested {
                        assert!(
                            CONFIG_STRUCTS.iter().any(|(s, _)| **s == **n),
                            "{path}: struct {n} is not in CONFIG_STRUCTS"
                        );
                    }
                    continue;
                }
                // numbers and flags are always shown
                let plain = idents
                    .iter()
                    .all(|w| matches!(*w, "Option" | "bool" | "u16" | "u32" | "u64" | "f64"));
                if plain {
                    continue;
                }
                assert!(
                    listed(&path),
                    "{path} ({ty}) holds text: add it to CONFIG_SHOWN (it never holds a secret) \
                     or to CONFIG_MASKED"
                );
                found.insert(path);
            }
        }
        // the one enum with fields: an entry of `backups.send_links`
        let lib = sources[0];
        let entry = &lib[lib.find("pub enum SendLinkEntry {").unwrap()..];
        let entry = &entry[..entry.find("\n}").unwrap()];
        let inner: Vec<&str> = entry
            .lines()
            .filter_map(|l| l.trim().strip_suffix(": String,"))
            .collect();
        assert_eq!(inner, ["link", "folder"], "SendLinkEntry changed");
        for f in inner {
            let path = format!("backups.send_links.{f}");
            assert!(listed(&path), "{path}");
            found.insert(path);
        }
        // and no entry of the lists names a field that is gone
        for path in CONFIG_SHOWN.iter().chain(CONFIG_MASKED) {
            assert!(found.contains(*path), "{path}: no such field of the config");
        }
        assert!(
            !CONFIG_SHOWN.iter().any(|p| CONFIG_MASKED.contains(p)),
            "a field is on both lists"
        );
    }

    /// The `config` section of a backup, from a real file: what is on the
    /// list is shown, every other text is the mask.
    #[test]
    fn the_config_copy_of_a_backup_is_masked_by_default() {
        let dir = std::env::temp_dir().join(format!("wyrmd-mask-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let file = dir.join("wyrmd.json5");
        std::fs::write(
            &file,
            r#"{
                site: "plant", data_dir: "/var/lib/wyrm", profile: "prod",
                listen: ["tls/0.0.0.0:7447", "quic/0.0.0.0:7448#key=/etc/k.key;tok=hunter2x"],
                connect: ["tls/central.example:7447?token=hunter2y"],
                admin_keys: ["00ff00ff"],
                metrics_interval_ms: 5000,
                links: {
                    plc: { driver: "snmp", params: {
                        community: "hunter2a", conninfo: "host=h password=hunter2b",
                        note: "Password = hunter2c", privkey: "hunter2d", port: 161,
                        connections: { c1: { url: "http://u:hunter2e@h/x", poll_ms: 500 } },
                    } },
                },
                gateway: { listen: "0.0.0.0:8445", tls_cert: "/etc/wyrm/gw.pem",
                           tls_key: "/etc/wyrm/gw.key",
                           mcp: { public_url: "https://broker.example:8445" } },
                packages: { repository: "https://ci:hunter2f@repo.example/index.json?sig=hunter2g" },
                uplink: { net: "broker.example:8883",
                          upstreams: [{ kind: "mqtt", name: "main", host: "broker.example" }] },
                peers: { upstream: [{ site: "central", endpoint: "quic/central.example:7448",
                                      ca: "/etc/wyrm/ca.pem", cert: "/etc/wyrm/b.pem",
                                      key: "/etc/wyrm/b.key" }] },
                backups: { export_secrets: false, send_links: ["s3", { link: "dav", folder: "wyrm" }] },
            }"#,
        )
        .unwrap();
        // the file is a configuration this broker reads
        Config::from_json5(&std::fs::read_to_string(&file).unwrap()).unwrap();
        let text = masked_config(&file).unwrap();
        assert!(!text.contains("hunter2"), "{text}");
        assert!(
            !text.contains("gw.key") && !text.contains("b.key"),
            "{text}"
        );
        let v: serde_json::Value = serde_json::from_str(&text).unwrap();
        let mask = wyrm_admin::secrets::MASK;
        assert_eq!(v["site"], "plant");
        assert_eq!(v["listen"][0], "tls/0.0.0.0:7447");
        assert_eq!(v["listen"][1], "quic/0.0.0.0:7448#***");
        assert_eq!(v["connect"][0], "tls/central.example:7447?***");
        assert_eq!(v["admin_keys"][0], "00ff00ff");
        assert_eq!(v["metrics_interval_ms"], 5000);
        assert_eq!(v["links"]["plc"]["driver"], "snmp");
        let params = &v["links"]["plc"]["params"];
        for name in ["community", "conninfo", "note", "privkey"] {
            assert_eq!(params[name], mask, "{name}");
        }
        assert_eq!(params["port"], 161);
        assert_eq!(params["connections"]["c1"]["url"], mask);
        assert_eq!(params["connections"]["c1"]["poll_ms"], 500);
        assert_eq!(v["gateway"]["tls_cert"], "/etc/wyrm/gw.pem");
        assert_eq!(v["gateway"]["tls_key"], mask);
        assert_eq!(
            v["gateway"]["mcp"]["public_url"],
            "https://broker.example:8445"
        );
        assert_eq!(
            v["packages"]["repository"],
            "https://***@repo.example/index.json?***"
        );
        assert_eq!(v["uplink"]["net"], "broker.example:8883");
        assert_eq!(v["uplink"]["upstreams"][0]["host"], mask);
        assert_eq!(
            v["peers"]["upstream"][0]["endpoint"],
            "quic/central.example:7448"
        );
        assert_eq!(v["peers"]["upstream"][0]["key"], mask);
        assert_eq!(v["backups"]["export_secrets"], false);
        assert_eq!(v["backups"]["send_links"][0], "s3");
        assert_eq!(v["backups"]["send_links"][1]["folder"], "wyrm");
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// ADR 0048 §3.4: the host names where backups may be sent; a folder
    /// that is no plain relative path is refused when the file is read.
    #[test]
    fn send_links_name_a_link_and_its_folder() {
        let cfg = |send: &str| {
            Config::from_json5(&format!(
                r#"{{ site: "s", data_dir: "/tmp/x", backups: {{ send_links: {send} }} }}"#
            ))
        };
        assert!(cfg("[]").unwrap().backups.send_links.is_empty());
        let links = cfg(r#"["files", { link: "s3", folder: "/site/backups/" }, { link: "dav" }]"#)
            .unwrap()
            .backups
            .checked_send_links()
            .unwrap();
        let got: Vec<(&str, &str)> = links
            .iter()
            .map(|l| (l.link.as_str(), l.folder.as_str()))
            .collect();
        assert_eq!(
            got,
            [
                ("files", "backups"),
                ("s3", "site/backups"),
                ("dav", "backups")
            ]
        );
        for bad in [
            r#"[{ link: "files", folder: "../other" }]"#,
            r#"[{ link: "files", folder: "a/../../b" }]"#,
            r#"[{ link: "files", folder: "a//b" }]"#,
            r#"[{ link: "files", folder: "" }]"#,
            r#"[{ link: "a/b", folder: "x" }]"#,
            r#"["files", { link: "files", folder: "x" }]"#,
            r#"[{ folder: "x" }]"#,
        ] {
            assert!(cfg(bad).is_err(), "{bad}");
        }
    }

    /// ADR 0043: a `builtin` form of the official manifest is a driver this
    /// binary hosts (`wyr repo check` cannot see this list).
    #[test]
    fn official_builtin_forms_are_drivers_of_wyrmd() {
        let drivers = Drivers.drivers();
        for l in &wyrm_admin::official::embedded().links {
            if let Some(d) = &l.forms.builtin {
                assert!(
                    drivers.contains(&d.as_str()),
                    "links/official.json: {} says builtin {d}, wyrmd hosts {drivers:?}",
                    l.id
                );
            }
        }
        let cfg =
            Config::from_json5(r#"{ site: "s", packages: { repository: "official" } }"#).unwrap();
        assert_eq!(
            wyrm_admin::official::repository_url(cfg.packages.repository.as_deref()),
            Some(wyrm_admin::official::embedded().index_url())
        );
        // ADR 0048: how long an updated package's previous version is kept
        assert_eq!(cfg.packages.keep_previous_days, 7);
        assert_eq!(
            Config::from_json5(r#"{ site: "s" }"#)
                .unwrap()
                .packages
                .keep_previous_days,
            7
        );
        let cfg =
            Config::from_json5(r#"{ site: "s", packages: { keep_previous_days: 30 } }"#).unwrap();
        assert_eq!(cfg.packages.keep_previous_days, 30);
        // ADR 0051 §1: no seed unless a directory is named
        assert_eq!(cfg.packages.seed_dir, None);
        let cfg =
            Config::from_json5(r#"{ site: "s", packages: { seed_dir: "/usr/share/wyrm/seed" } }"#)
                .unwrap();
        assert_eq!(
            cfg.packages.seed_dir.as_deref(),
            Some(std::path::Path::new("/usr/share/wyrm/seed"))
        );
    }

    #[test]
    fn scheduler_section_and_reserved_ids() {
        let parse = |extra: &str| Config::from_json5(&format!(r#"{{ site: "s", {extra} }}"#));
        let d = parse("").unwrap().scheduler;
        assert!(d.enabled);
        assert_eq!(d.store_mb, 64);
        let q = parse("").unwrap().dql;
        assert!(q.enabled);
        assert_eq!(q.store_mb, 16);
        assert!(!parse("dql: { enabled: false }").unwrap().dql.enabled);
        let a = parse("").unwrap().alarm;
        assert!(a.enabled);
        assert_eq!(
            (a.store_mb, a.retention_days, a.max_records),
            (64, 365, 100_000)
        );
        let a = parse("alarm: { enabled: false, retention_days: 30, max_records: 1000 }")
            .unwrap()
            .alarm;
        assert!(!a.enabled);
        assert_eq!((a.retention_days, a.max_records), (30, 1000));
        let u = parse("").unwrap().uplink;
        assert!(u.enabled && u.net.is_empty() && u.upstreams.is_empty());
        assert_eq!(u.store_mb, 2);
        let u = parse(
            r#"uplink: { net: "*.example:8883", upstreams: [{ name: "x", kind: "mqtt", url: "mqtts://b.example" }] }"#,
        )
        .unwrap()
        .uplink;
        assert_eq!(u.upstreams.len(), 1);
        let p = uplink_params("s", &u);
        let Value::Map(m) = p else { panic!() };
        assert_eq!(m["own"], Value::from("wy/s/downstream/uplink"));
        assert_eq!(m["net"], Value::from("*.example:8883"));
        assert!(matches!(&m["upstreams"], Value::Array(a) if a.len() == 1));
        let off = parse("scheduler: { enabled: false }").unwrap().scheduler;
        assert!(!off.enabled);
        assert_eq!(off.store_mb, 64);
        for bad in [
            "scheduler: { store_mb: 0 }",
            "scheduler: { store_mb: 65 }",
            "scheduler: { other: 1 }",
            r#"links: { scheduler: { driver: "mock" } }"#,
            r#"links: { dql: { driver: "mock" } }"#,
            "dql: { store_mb: 0 }",
            "dql: { nope: true }",
            "alarm: { store_mb: 65 }",
            "alarm: { other: 1 }",
            r#"links: { alarm: { driver: "mock" } }"#,
            r#"links: { uplink: { driver: "mock" } }"#,
            "uplink: { store_mb: 0 }",
            "uplink: { nope: true }",
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

    /// Every refusal reads as it did when these errors were strings, and
    /// `main` prints it as a text in quotes.
    #[test]
    fn errors_read_as_before() {
        let printed = |e: Error| format!("{e:?}");
        let id = || wyrm_admin::registry::validate_link_id("A B").unwrap_err();
        let folder = || wyrm_admin::control::send::check_folder("../x").unwrap_err();
        let io = || std::io::Error::other("cause");
        for (e, want) in [
            (
                SendLinksError::Link(id()).to_string(),
                "backups.send_links: link id: illegal character ' ' in segment A B",
            ),
            (
                SendLinksError::Folder {
                    link: "s3".into(),
                    source: folder(),
                }
                .to_string(),
                "backups.send_links: link s3: folder \"../x\": a relative path of plain names \
                 (no `..`, no empty segment)",
            ),
            (
                SendLinksError::Twice("s3".into()).to_string(),
                "backups.send_links: link s3 twice (one folder a link)",
            ),
            (
                KeyFileError::Read {
                    path: "/d/state.key".into(),
                    source: io(),
                }
                .to_string(),
                "/d/state.key: cause",
            ),
            (
                KeyFileError::NotHex("/d/state.key".into()).to_string(),
                "/d/state.key: not hex",
            ),
            (
                KeyFileError::Length("/d/state.key".into()).to_string(),
                "/d/state.key: expected 32 bytes",
            ),
            (
                VerifyError::Key(KeyFileError::Length("/d/state.key".into())).to_string(),
                "/d/state.key: expected 32 bytes",
            ),
            (
                VerifyError::Store(wyrm_state::StateError::InUse("/d/state".into())).to_string(),
                "/d/state is in use by another process",
            ),
        ] {
            assert_eq!(e, want);
        }
        assert_eq!(
            printed(SendLinksError::Twice("s3".into()).into()),
            "\"backups.send_links: link s3 twice (one folder a link)\""
        );
        assert_eq!(
            printed(KeyFileError::Length("/d/state.key".into()).into()),
            "\"/d/state.key: expected 32 bytes\""
        );
        assert_eq!(
            printed(VerifyError::Key(KeyFileError::Length("/d/state.key".into())).into()),
            "\"/d/state.key: expected 32 bytes\""
        );
        // the configuration is refused with the same line
        let e = Config::from_json5(
            r#"{ site: "s", data_dir: "/tmp/x", backups: { send_links: ["a", "a"] } }"#,
        )
        .unwrap_err();
        assert_eq!(
            format!("{e:?}"),
            "\"backups.send_links: link a twice (one folder a link)\""
        );
        assert!(matches!(
            e.downcast_ref::<SendLinksError>(),
            Some(SendLinksError::Twice(l)) if l == "a"
        ));
        let e = Config::from_json5(r#"{ site: "s", data_dir: "/tmp/x", updates: { trial_s: 5 } }"#)
            .unwrap_err();
        assert_eq!(format!("{e:?}"), "\"updates.trial_s 5: 10 to 3600\"");
        assert!(matches!(
            e.downcast_ref::<update::UpdatesError>(),
            Some(update::UpdatesError::TrialS(5))
        ));
    }

    /// A key file is refused by variant; a file that is not read keeps its
    /// cause.
    #[test]
    fn key_files_are_refused_by_variant() {
        let d = std::env::temp_dir().join(format!("wyrmd-keyfile-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        assert!(matches!(
            read_key(&d.join("none")),
            Err(KeyFileError::Read { source, .. }) if source.kind() == std::io::ErrorKind::NotFound
        ));
        std::fs::write(d.join("k"), "zz").unwrap();
        assert!(matches!(
            read_key(&d.join("k")),
            Err(KeyFileError::NotHex(_))
        ));
        std::fs::write(d.join("k"), "abcd").unwrap();
        assert!(matches!(
            read_key(&d.join("k")),
            Err(KeyFileError::Length(_))
        ));
        std::fs::write(d.join("k"), format!("{}\n", "ab".repeat(32))).unwrap();
        assert_eq!(read_key(&d.join("k")).unwrap().len(), 32);
        let _ = std::fs::remove_dir_all(&d);
    }
}
