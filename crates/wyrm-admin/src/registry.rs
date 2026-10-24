//! The link registry: control-plane state persisted with `wyrm-state`.

use minicbor::{Decode, Encode};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};
use wyrm_core::keyspace::{self, validate_segment};
use wyrm_core::profile::{self, ProfileDef};

/// A link id is a key segment, a certificate CN and a directory name under
/// `data_dir/links`: no leading `.` (rejects `.` and `..`), no reserved names.
pub fn validate_link_id(id: &str) -> Result<(), String> {
    validate_segment(id).map_err(|e| format!("link id: {e}"))?;
    if id.starts_with('.') {
        return Err(format!("link id {id:?} may not start with '.'"));
    }
    if matches!(id, "admin" | "broker" | "dataflows") {
        return Err(format!("link id {id:?} is reserved"));
    }
    Ok(())
}

/// Ids taken by a later broker version, refused for new links only: a link
/// stored under one still replays (`storage`: spec 01 0.2.2, ADR 0017).
const RESERVED_NEW: [&str; 1] = [crate::control::STORAGE_LINK];

/// [`validate_link_id`] for a link that does not exist yet.
pub fn validate_new_link_id(id: &str) -> Result<(), String> {
    validate_link_id(id)?;
    if RESERVED_NEW.contains(&id) {
        return Err(format!("link id {id:?} is reserved"));
    }
    Ok(())
}

/// Certificate CN of a downstream broker (ADR 0015): `broker:<site>`.
pub fn broker_cn(site: &str) -> String {
    format!("broker:{site}")
}

/// The site of a `broker:<site>` CN.
pub fn broker_site(cn: &str) -> Option<&str> {
    cn.strip_prefix("broker:")
        .filter(|s| validate_segment(s).is_ok())
}

/// How a link runs (wiki "Режими розгортання").
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Encode, Decode)]
#[cbor(index_only)]
pub enum Mode {
    /// In-process, started by the broker.
    #[n(0)]
    Embedded,
    /// Child process supervised by the broker (mTLS client, CN = link id).
    #[n(1)]
    Process,
    /// Runs elsewhere (MCU, remote host) with a CA-issued certificate.
    #[n(2)]
    External,
}

impl Mode {
    pub fn parse(s: &str) -> Option<Self> {
        Some(match s {
            "embedded" => Mode::Embedded,
            "process" => Mode::Process,
            "external" => Mode::External,
            _ => return None,
        })
    }

    pub fn name(self) -> &'static str {
        match self {
            Mode::Embedded => "embedded",
            Mode::Process => "process",
            Mode::External => "external",
        }
    }

    /// Connects over the network with its own certificate (gets an ACL rule).
    pub fn is_remote(self) -> bool {
        !matches!(self, Mode::Embedded)
    }
}

/// Where a registry entry came from: `wyrmd.json5` entries follow the file,
/// runtime entries follow `sys/links/~act/*`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Encode, Decode)]
#[cbor(index_only)]
pub enum Origin {
    #[n(0)]
    Config,
    #[n(1)]
    Runtime,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Encode, Decode)]
pub struct LinkDef {
    #[n(0)]
    pub id: String,
    #[n(1)]
    pub driver: String,
    #[n(2)]
    pub mode: Mode,
    /// `~def.params` as canonical CBOR (a `Value` map).
    #[n(3)]
    #[cbor(with = "minicbor::bytes")]
    pub params: Vec<u8>,
    /// argon2id PHC string of the link token; empty for embedded links.
    #[n(4)]
    pub token_hash: String,
    #[n(5)]
    pub rev: u32,
    #[n(6)]
    pub origin: Origin,
    /// Unix seconds.
    #[n(7)]
    pub created: u64,
    /// Name for people (`sys/links/<id>` display); the id stays the
    /// certificate CN.
    #[n(8)]
    #[serde(default)]
    pub display: Option<String>,
    /// Gateway role that Authorize `group` gave `write` on this link's
    /// branch; that one grant is revoked with the link.
    #[n(9)]
    #[serde(default)]
    pub granted: Option<String>,
    /// Log level of this link (one of `logs::LEVELS`); `None`: the broker's
    /// (embedded) or the process default.
    #[n(10)]
    #[serde(default)]
    pub log_level: Option<String>,
    /// What this link may reach as a requester (as DSA `isRequester`):
    /// `(path, Perm code)`, the path a node key prefix with `{site}`.
    #[n(11)]
    #[cbor(default)]
    #[serde(default)]
    pub grants: Vec<(String, u8)>,
}

/// Highest level a link grant gives: `config` stays with people.
pub const MAX_LINK_GRANT: wyrm_core::Perm = wyrm_core::Perm::Write;

/// A link grant path: `wy/{site}/downstream[/…]` or `wy/{site}/dataflows[/…]`, plain
/// segments (no wildcards, no suffixes). `dataflows` grants stop at `read`.
pub fn check_grant(path: &str, level: wyrm_core::Perm) -> Result<(), String> {
    use wyrm_core::Perm;
    let rest = path.strip_prefix("wy/{site}/").ok_or_else(|| {
        format!("{path}: starts with wy/{{site}}/downstream or wy/{{site}}/dataflows")
    })?;
    let mut segs = rest.split('/');
    let root = segs.next().unwrap_or_default();
    if !matches!(root, "downstream" | "dataflows") {
        return Err(format!("{path}: only downstream or dataflows (never sys)"));
    }
    for seg in segs {
        validate_segment(seg).map_err(|e| format!("{path}: {e}"))?;
        if seg.starts_with('~') {
            return Err(format!("{path}: a node path, no suffix"));
        }
    }
    if level > MAX_LINK_GRANT {
        return Err(format!("level {}: at most write", level.name()));
    }
    if root == "dataflows" && level > Perm::Read {
        return Err("flows: at most read (flows are commanded by people)".into());
    }
    Ok(())
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct QuarantineEntry {
    pub first_seen: u64,
    pub last_seen: u64,
    pub attempts: u64,
}

#[derive(Debug, Encode, Decode)]
pub enum Op {
    #[n(0)]
    Install(#[n(0)] LinkDef),
    #[n(1)]
    Remove(#[n(0)] String),
    /// Replace params (and mode) of an existing link; bumps `rev`.
    #[n(2)]
    Update {
        #[n(0)]
        id: String,
        #[n(1)]
        mode: Mode,
        #[n(2)]
        #[cbor(with = "minicbor::bytes")]
        params: Vec<u8>,
    },
    #[n(3)]
    SetTokenHash {
        #[n(0)]
        id: String,
        #[n(1)]
        hash: String,
    },
    /// A session with an unknown CN was seen at `seen`.
    #[n(4)]
    Quarantine {
        #[n(0)]
        cn: String,
        #[n(1)]
        seen: u64,
    },
    /// Leave quarantine (followed by an `Install` of the same id).
    #[n(5)]
    Approve(#[n(0)] String),
    /// Leave quarantine and never record this CN again.
    #[n(6)]
    Reject(#[n(0)] String),
    /// Add or replace a profile (`pub/<name>/~meta`, CBOR `ProfileDef`).
    #[n(7)]
    PutProfile {
        #[n(0)]
        name: String,
        #[n(1)]
        #[cbor(with = "minicbor::bytes")]
        cbor: Vec<u8>,
    },
    #[n(8)]
    RemoveProfile(#[n(0)] String),
    /// A broker option (`sys/<name>`, see [`Options`]).
    #[n(9)]
    SetOption {
        #[n(0)]
        name: String,
        #[n(1)]
        on: bool,
    },
    /// Add a peer broker: an upstream site (`sys/upstream`), or a downstream
    /// broker installed or authorized (`sys/links`, quarantine; ADR 0015).
    #[n(10)]
    AddPeer(#[n(0)] PeerDef),
    #[n(11)]
    RemovePeer(#[n(0)] String),
    /// Connect to an upstream site or not (it stays configured).
    #[n(12)]
    SetPeerEnabled {
        #[n(0)]
        site: String,
        #[n(1)]
        on: bool,
    },
    /// DSA Deauthorize: an external runtime link goes back to quarantine
    /// (not retired); only a manual Authorize admits it again.
    #[n(13)]
    Deauthorize {
        #[n(0)]
        id: String,
        #[n(1)]
        seen: u64,
    },
    /// Install or replace a link package (ADR 0011).
    #[n(14)]
    PutPackage(#[n(0)] PackageDef),
    /// Refused while a link runs the package.
    #[n(15)]
    RemovePackage(#[n(0)] String),
    /// Log level of the broker (`link: None`) or of one link; `level: None`
    /// goes back to the default.
    #[n(16)]
    SetLogLevel {
        #[n(0)]
        link: Option<String>,
        #[n(1)]
        level: Option<String>,
    },
    /// Add, change or (level `none`) remove one grant of a link.
    #[n(17)]
    SetLinkGrant {
        #[n(0)]
        id: String,
        #[n(1)]
        path: String,
        #[n(2)]
        level: u8,
    },
    /// Add a history watch group or change its settings (its watches stay).
    #[n(18)]
    PutWatchGroup {
        #[n(0)]
        name: String,
        /// `wyrm_history::Logging` code.
        #[n(1)]
        logging: u8,
        #[n(2)]
        interval_ms: u64,
        #[n(3)]
        flush_ms: u64,
    },
    #[n(19)]
    RemoveWatchGroup(#[n(0)] String),
    /// Watch a point key in a group; the watch gets the next id `w<N>`.
    #[n(20)]
    AddWatch {
        #[n(0)]
        group: String,
        #[n(1)]
        key: String,
    },
    #[n(21)]
    SetWatchEnabled {
        #[n(0)]
        group: String,
        #[n(1)]
        id: String,
        #[n(2)]
        on: bool,
    },
    #[n(22)]
    RemoveWatch {
        #[n(0)]
        group: String,
        #[n(1)]
        id: String,
    },
    #[n(23)]
    SetHistoryOptions {
        #[n(0)]
        auto_purge: bool,
        #[n(1)]
        keep_free_mib: u64,
        #[n(2)]
        retention_days: u32,
    },
    /// Our CA issued `broker:<site>` (ADR 0015); the name never becomes an
    /// upstream site.
    #[n(24)]
    IssueBroker(#[n(0)] String),
    /// Remove a runtime downstream broker: its CN goes to quarantine and is
    /// admitted again only by a manual Authorize (its certificate stays
    /// valid).
    #[n(25)]
    HoldBroker {
        #[n(0)]
        site: String,
        #[n(1)]
        seen: u64,
    },
    /// A downstream broker asks for a certificate and waits in quarantine.
    /// A request with another key for a waiting name only counts as a
    /// conflict; the first request stays.
    #[n(26)]
    EnrollRequest {
        #[n(0)]
        site: String,
        #[n(1)]
        csr_pem: String,
        #[n(2)]
        key_sha256: String,
        #[n(3)]
        via: Vec<String>,
        #[n(4)]
        seen: u64,
    },
    /// Admit a downstream broker with the certificate our CA signed for it
    /// (or by name, empty): it leaves quarantine and becomes a runtime peer.
    #[n(27)]
    AdmitBroker {
        #[n(0)]
        site: String,
        #[n(1)]
        via: Vec<String>,
        #[n(2)]
        key_sha256: String,
        #[n(3)]
        cert_pem: String,
        #[n(4)]
        seen: u64,
    },
    /// Our certificate from an upstream site arrived (enrollment).
    #[n(28)]
    SetPeerCert {
        #[n(0)]
        site: String,
        #[n(1)]
        endpoint: String,
        #[n(2)]
        cert_pem: String,
    },
    #[n(29)]
    AddToken {
        #[n(0)]
        id: String,
        #[n(1)]
        def: TokenDef,
    },
    /// One admission with the token; at its last use it goes.
    #[n(30)]
    UseToken(#[n(0)] String),
    #[n(31)]
    RemoveToken(#[n(0)] String),
    /// A request nobody asked again for a while: it leaves quarantine (not
    /// a held broker's).
    #[n(32)]
    DropEnrollment(#[n(0)] String),
    /// Let an upstream site run `config` actions on our `sys` or not.
    #[n(33)]
    SetPeerAllowConfig {
        #[n(0)]
        site: String,
        #[n(1)]
        on: bool,
    },
    /// The keys an upstream site signs requests with, by signing site (its
    /// own and those above it), as it publishes them; empty: none
    /// (ADR 0018).
    #[n(34)]
    SetSigners {
        #[n(0)]
        upstream: String,
        /// Signing site → Ed25519 public keys (hex), for `write`.
        #[n(1)]
        keys: BTreeMap<String, Vec<String>>,
        /// The keys it lets reach `config`: its own, and those of upstream
        /// sites it allows `config` (so no hop is skipped).
        #[n(2)]
        #[cbor(default)]
        config: BTreeMap<String, Vec<String>>,
    },
    /// A watch's key, as a route copied from an explorer's tree (stored
    /// before routes resolved) becomes the key of its site.
    #[n(35)]
    SetWatchKey {
        #[n(0)]
        group: String,
        #[n(1)]
        id: String,
        #[n(2)]
        key: String,
    },
}

/// At most this many signing sites per upstream site, and keys per site.
pub const MAX_SIGNER_SITES: usize = 16;
pub const MAX_SIGNER_KEYS: usize = 8;

/// Signing keys as an upstream publishes them: valid site names, at most
/// [`MAX_SIGNER_SITES`] sites of at most [`MAX_SIGNER_KEYS`] Ed25519 keys
/// (hex), each a valid point.
pub fn check_signers(keys: &BTreeMap<String, Vec<String>>) -> Result<(), String> {
    if keys.len() > MAX_SIGNER_SITES {
        return Err(format!("more than {MAX_SIGNER_SITES} signing sites"));
    }
    for (site, ks) in keys {
        validate_segment(site).map_err(|e| format!("signing site: {e}"))?;
        if ks.is_empty() || ks.len() > MAX_SIGNER_KEYS {
            return Err(format!("{site}: 1 to {MAX_SIGNER_KEYS} keys"));
        }
        for k in ks {
            let raw: [u8; 32] = hex::decode(k)
                .ok()
                .and_then(|b| b.try_into().ok())
                .ok_or_else(|| format!("{site}: a key is not 32 bytes of hex"))?;
            ed25519_dalek::VerifyingKey::from_bytes(&raw)
                .map_err(|_| format!("{site}: not an Ed25519 key"))?;
        }
    }
    Ok(())
}

/// How a package's links run (ADR 0011).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Encode, Decode)]
#[cbor(index_only)]
pub enum PackageKind {
    /// A binary on `wyrm-link-sdk`, supervised as a process link.
    #[n(0)]
    Process,
    /// A `wyrm:link/point` component in the broker (ADR 0010).
    #[n(1)]
    Wasm,
}

impl PackageKind {
    pub fn name(self) -> &'static str {
        match self {
            PackageKind::Process => "process",
            PackageKind::Wasm => "wasm",
        }
    }
}

/// An installed link package, unpacked under
/// `data_dir/packages/<name>/<version>/` (ADR 0011).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Encode, Decode)]
pub struct PackageDef {
    #[n(0)]
    pub name: String,
    #[n(1)]
    pub version: String,
    #[n(2)]
    pub kind: PackageKind,
    /// Entry for this host, relative to the package directory.
    #[n(3)]
    pub entry: String,
    #[n(4)]
    pub args: Vec<String>,
    /// SHA-256 (hex) of the zip it came from.
    #[n(5)]
    pub sha256: String,
    /// `zip`, `url <url>`, `git <url> <ref>` or `repository <url>`.
    #[n(6)]
    pub source: String,
    #[n(7)]
    pub description: String,
    /// Unix seconds.
    #[n(8)]
    pub installed: u64,
    /// Grants the package asks for (`wyrm-link.json` `requester`): each new
    /// link of the package gets them, shown in the install result.
    #[n(9)]
    #[cbor(default)]
    #[serde(default)]
    pub requester: Vec<(String, u8)>,
}

/// The embedded historian's settings (`sys/history`, ADR 0014). The rows
/// live in `data_dir/history`, not here.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct HistorianDef {
    pub groups: BTreeMap<String, WatchGroupDef>,
    /// Delete the oldest day while the disk has less than `keep_free_mib`.
    pub auto_purge: bool,
    pub keep_free_mib: u64,
    /// Delete days older than this many days; 0 keeps them.
    pub retention_days: u32,
}

impl Default for HistorianDef {
    fn default() -> Self {
        Self {
            groups: BTreeMap::new(),
            auto_purge: true,
            keep_free_mib: 1024,
            retention_days: 0,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct WatchGroupDef {
    /// `wyrm_history::Logging` code.
    pub logging: u8,
    pub interval_ms: u64,
    pub flush_ms: u64,
    /// By id (`w1`, `w2`, …).
    pub watches: BTreeMap<String, WatchDef>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct WatchDef {
    /// Point key `wy/<site>/downstream/…` or `wy/<site>/dataflows/…`.
    pub key: String,
    pub enabled: bool,
}

/// At most this many watch groups and watches in all.
pub const MAX_WATCH_GROUPS: usize = 64;
pub const MAX_WATCHES: usize = 10_000;
/// Bounds of a group's intervals (ms).
pub const INTERVAL_MS: std::ops::RangeInclusive<u64> = 100..=86_400_000;
pub const FLUSH_MS: std::ops::RangeInclusive<u64> = 100..=600_000;

/// A watch key: `wy/<site>/downstream/<link>[/…]`, `wy/<site>/dataflows/<flow>[/…]`
/// or `wy/<site>/storage/<node>[/…]`, plain segments (no wildcards, no `~`
/// suffixes). Which sites are allowed is the caller's check.
pub fn check_watch_key(key: &str) -> Result<(), String> {
    let segs: Vec<&str> = key.split('/').collect();
    if segs.len() < 4
        || segs[0] != "wy"
        || !matches!(segs[2], "downstream" | "dataflows" | "storage")
    {
        return Err(format!(
            "{key}: a point under wy/<site>/downstream/<link>, wy/<site>/dataflows/<flow> or wy/<site>/storage"
        ));
    }
    for s in &segs[1..] {
        validate_segment(s).map_err(|e| format!("{key}: {e}"))?;
        if s.starts_with('~') {
            return Err(format!("{key}: a node key, no suffix"));
        }
    }
    Ok(())
}

/// Which side a peer broker is on (ADR 0007).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Encode, Decode)]
#[cbor(index_only)]
pub enum PeerDir {
    /// We connect to it and it reads our `downstream/**`, `dataflows/**`.
    #[n(0)]
    Upstream,
    /// It connects to us and serves its own `wy/<site>/**`.
    #[n(1)]
    Downstream,
}

/// A peer broker added at runtime, as DSA's `/sys/upstream` (peers from
/// `wyrmd.json5` are not stored here).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Encode, Decode)]
pub struct PeerDef {
    #[n(0)]
    pub site: String,
    #[n(1)]
    pub dir: PeerDir,
    /// `quic/<host>:<port>` of an upstream site; empty for downstream.
    #[n(2)]
    pub endpoint: String,
    /// Upstream: that site's CA certificate (PEM), trusted only on its
    /// connect endpoint. Downstream entries before ADR 0015 carry their CA;
    /// it is no longer trusted.
    #[n(3)]
    pub ca_pem: String,
    /// Upstream only: connect to it.
    #[n(4)]
    pub enabled: bool,
    #[n(5)]
    pub created: u64,
    /// Downstream only: sites it relays from further down (a chain); it may
    /// serve their keys, and our upstream may read them.
    #[n(6)]
    #[cbor(default)]
    #[serde(default)]
    pub via: Vec<String>,
    /// Upstream only: the certificate that site issued for this broker
    /// (`broker:<site>`, ADR 0015); its key is in the secret store.
    #[n(7)]
    #[cbor(default)]
    #[serde(default)]
    pub cert_pem: String,
    /// Upstream added at runtime: its enrollment endpoint (`peers.enroll`
    /// there), where this broker asks for `cert_pem` (ADR 0015).
    #[n(8)]
    #[cbor(default)]
    #[serde(default)]
    pub enroll: String,
    /// SHA-256 (hex) of the broker key: ours towards an upstream site, the
    /// admitted one of a downstream broker (empty: admitted by name).
    #[n(9)]
    #[cbor(default)]
    #[serde(default)]
    pub key_sha256: String,
    /// Upstream only: its users may run `config` actions on our `sys`
    /// (ADR 0018); `write` on devices, flows and storage they always have.
    #[n(10)]
    #[cbor(default)]
    #[serde(default)]
    pub allow_config: bool,
}

/// A downstream broker's request for a certificate, waiting in quarantine
/// (`broker:<site>`, ADR 0015), or a Deauthorized broker's last grant.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct Enrollment {
    /// The request (empty for a held broker that did not ask again).
    pub csr_pem: String,
    pub key_sha256: String,
    /// Sites it says it relays.
    pub via: Vec<String>,
    /// Requests for this name with another key: refused, never swapped in.
    pub conflicts: u64,
    /// The certificate it held when it was Deauthorized (same key).
    pub cert_pem: String,
}

/// A token that admits a downstream broker at once (DSA `/sys/tokens`),
/// kept as the SHA-256 of the whole token.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Encode, Decode)]
pub struct TokenDef {
    #[n(0)]
    pub sha256: String,
    /// Admissions left; 0 = no limit.
    #[n(1)]
    pub uses: u32,
    /// Unix seconds after which it is refused; 0 = never.
    #[n(2)]
    pub expires: u64,
    #[n(3)]
    pub created: u64,
    #[n(4)]
    pub by: String,
}

/// At most this many brokers wait in quarantine at a time.
pub const MAX_ENROLLMENTS: usize = 64;

/// Broker options changed at runtime, as DSA's `allowAllLinks` and
/// `quarantine` (`wy/<site>/sys/allow_all_links`, `.../enable_quarantine`).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Options {
    /// Install every unknown certificate CN signed by our CA as an
    /// external link, without quarantine. Off by default.
    pub allow_all_links: bool,
    /// Record unknown CNs in `sys/quarantine` (off: drop them unrecorded).
    pub enable_quarantine: bool,
}

impl Default for Options {
    fn default() -> Self {
        Self {
            allow_all_links: false,
            enable_quarantine: true,
        }
    }
}

impl Options {
    /// The option `name` (one of [`OPTION_NAMES`]).
    pub fn get(&self, name: &str) -> Option<bool> {
        match name {
            "allow_all_links" => Some(self.allow_all_links),
            "enable_quarantine" => Some(self.enable_quarantine),
            _ => None,
        }
    }
}

/// Names of the [`Options`] fields, as `SetOption` takes them.
pub const OPTION_NAMES: [&str; 2] = ["allow_all_links", "enable_quarantine"];

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct Registry {
    pub links: BTreeMap<String, LinkDef>,
    pub quarantine: BTreeMap<String, QuarantineEntry>,
    pub blocklist: BTreeSet<String>,
    /// Ids of removed links. Their certificates stay valid until expiry (no
    /// CRL yet), so an id is never handed out again.
    #[serde(default)]
    pub retired: BTreeSet<String>,
    /// Profiles beside the built-in ones: name → CBOR `ProfileDef`.
    #[serde(default)]
    pub profiles: BTreeMap<String, Vec<u8>>,
    /// Replaced params per link, oldest first: `(rev, params CBOR)`, at most
    /// [`LINK_HISTORY`] (T11: version history and rollback).
    #[serde(default)]
    pub history: BTreeMap<String, Vec<(u32, Vec<u8>)>>,
    #[serde(default)]
    pub options: Options,
    /// Peer brokers added at runtime, by site.
    #[serde(default)]
    pub peers: BTreeMap<String, PeerDef>,
    /// Deauthorized CNs: in quarantine, admitted again only by a manual
    /// Authorize (never by `allow_all_links`).
    #[serde(default)]
    pub held: BTreeSet<String>,
    /// Link packages by name (ADR 0011).
    #[serde(default)]
    pub packages: BTreeMap<String, PackageDef>,
    /// Log level of the broker set from `sys/log_level`; `None`: `RUST_LOG`.
    #[serde(default)]
    pub log_level: Option<String>,
    /// Watch groups and purge settings of the embedded historian.
    #[serde(default)]
    pub historian: HistorianDef,
    /// Sites our CA issued a `broker:<site>` certificate for (ADR 0015).
    #[serde(default)]
    pub issued_brokers: BTreeSet<String>,
    /// Downstream brokers waiting in quarantine (or held), by site.
    #[serde(default)]
    pub enrollments: BTreeMap<String, Enrollment>,
    /// Admission tokens for downstream brokers, by id.
    #[serde(default)]
    pub tokens: BTreeMap<String, TokenDef>,
    /// Upstream site → the keys it signs requests with, by signing site
    /// (hex), as last published there (ADR 0018).
    #[serde(default)]
    pub signers: BTreeMap<String, BTreeMap<String, Vec<String>>>,
    /// Upstream site → those of its keys it lets reach `config`.
    #[serde(default)]
    pub config_signers: BTreeMap<String, BTreeMap<String, Vec<String>>>,
}

/// Replaced params kept per link.
pub const LINK_HISTORY: usize = 10;

impl Registry {
    /// A profile by name: built-in or stored.
    pub fn profile(&self, name: &str) -> Option<ProfileDef> {
        if let Some((_, p)) = profile::builtins().into_iter().find(|(n, _)| *n == name) {
            return Some(p);
        }
        self.profiles
            .get(name)
            .and_then(|b| wyrm_core::codec::from_slice(b).ok())
    }

    fn check_profile(&self, name: &str, def: &ProfileDef) -> Result<(), String> {
        profile::validate_name(name)?;
        if profile::builtins().iter().any(|(n, _)| *n == name) {
            return Err(format!("profile {name} is built in"));
        }
        // the parent exists and the chain does not come back to `name`
        let mut next = def.extends.clone();
        for _ in 0..profile::MAX_DEPTH {
            let Some(p) = next.take() else {
                return Ok(());
            };
            if p == name {
                return Err(format!("profile {name}: extends cycle"));
            }
            next = self
                .profile(&p)
                .ok_or_else(|| format!("profile {name}: extends unknown {p}"))?
                .extends;
        }
        Err(format!(
            "profile {name}: extends chain longer than {}",
            profile::MAX_DEPTH
        ))
    }
}

/// An op with keys stored before spec 0.2.0 (`down`, `up`, `flows`) under
/// their new names, so old WAL records replay as current ones; `None` when
/// the op carries no key.
fn renamed_keys(op: &Op) -> Option<Op> {
    let rn = |p: &str| keyspace::renamed(p).into_owned();
    let grants = |g: &[(String, u8)]| g.iter().map(|(p, l)| (rn(p), *l)).collect();
    match op {
        Op::Install(def) if !def.grants.is_empty() => Some(Op::Install(LinkDef {
            grants: grants(&def.grants),
            ..def.clone()
        })),
        Op::PutPackage(def) if !def.requester.is_empty() => Some(Op::PutPackage(PackageDef {
            requester: grants(&def.requester),
            ..def.clone()
        })),
        Op::SetLinkGrant { id, path, level } => Some(Op::SetLinkGrant {
            id: id.clone(),
            path: rn(path),
            level: *level,
        }),
        Op::AddWatch { group, key } => Some(Op::AddWatch {
            group: group.clone(),
            key: rn(key),
        }),
        _ => None,
    }
}

impl wyrm_state::State for Registry {
    // 14: keys renamed by spec 0.2.0 (snapshots rebuilt through `renamed_keys`);
    // 15: `PeerDef::cert_pem`; 16: enrollments and tokens (ADR 0015);
    // 17: `PeerDef::allow_config`, `signers`; 18: `config_signers` (ADR 0018)
    const SCHEMA: u32 = 18;
    type Op = Op;

    fn apply(&mut self, op: &Op) -> Result<(), String> {
        let renamed = renamed_keys(op);
        match renamed.as_ref().unwrap_or(op) {
            Op::Install(def) => {
                validate_link_id(&def.id)?;
                if self
                    .peers
                    .get(&def.id)
                    .is_some_and(|p| p.dir == PeerDir::Downstream)
                {
                    return Err(format!("{} is a downstream site", def.id));
                }
                if self.retired.contains(&def.id) {
                    return Err(format!(
                        "link id {} was removed before; its certificate may still be valid, choose a new id",
                        def.id
                    ));
                }
                if self.links.contains_key(&def.id) {
                    return Err(format!("link {} already installed", def.id));
                }
                if def.mode.is_remote() && def.token_hash.is_empty() {
                    return Err(format!("{} link needs a token", def.mode.name()));
                }
                if let Some(p) = def.driver.strip_prefix("pkg:") {
                    if !self.packages.contains_key(p) {
                        return Err(format!("no package {p}"));
                    }
                }
                self.quarantine.remove(&def.id);
                self.held.remove(&def.id);
                self.links.insert(def.id.clone(), def.clone());
            }
            Op::Remove(id) => {
                self.history.remove(id);
                let def = self
                    .links
                    .remove(id)
                    .ok_or_else(|| format!("no link {id}"))?;
                // A token hash exists iff the link was ever remote, i.e. a
                // certificate was issued (Update to embedded keeps it).
                if def.mode.is_remote() || !def.token_hash.is_empty() {
                    self.retired.insert(id.clone());
                }
            }
            Op::Update { id, mode, params } => {
                let def = self
                    .links
                    .get_mut(id)
                    .ok_or_else(|| format!("no link {id}"))?;
                if mode.is_remote() && def.token_hash.is_empty() {
                    return Err(format!("{} link needs a token", mode.name()));
                }
                let h = self.history.entry(id.clone()).or_default();
                h.push((def.rev, def.params.clone()));
                if h.len() > LINK_HISTORY {
                    h.remove(0);
                }
                def.mode = *mode;
                def.params = params.clone();
                def.rev += 1;
            }
            Op::SetTokenHash { id, hash } => {
                self.links
                    .get_mut(id)
                    .ok_or_else(|| format!("no link {id}"))?
                    .token_hash = hash.clone();
            }
            Op::Quarantine { cn, seen } => {
                match broker_site(cn) {
                    Some(site) if self.peers.contains_key(site) => {
                        return Err(format!("{site} is a peer"));
                    }
                    Some(_) => {}
                    None => validate_link_id(cn)?,
                }
                if self.links.contains_key(cn)
                    || self.blocklist.contains(cn)
                    || self.retired.contains(cn)
                {
                    return Err(format!("{cn} is known"));
                }
                let e = self
                    .quarantine
                    .entry(cn.clone())
                    .or_insert(QuarantineEntry {
                        first_seen: *seen,
                        ..Default::default()
                    });
                e.last_seen = *seen;
                e.attempts += 1;
            }
            Op::Approve(cn) => {
                self.held.remove(cn);
                self.quarantine
                    .remove(cn)
                    .ok_or_else(|| format!("{cn} is not in quarantine"))?;
            }
            Op::Reject(cn) => {
                self.quarantine
                    .remove(cn)
                    .ok_or_else(|| format!("{cn} is not in quarantine"))?;
                self.held.remove(cn);
                if let Some(site) = broker_site(cn) {
                    self.enrollments.remove(site);
                }
                self.blocklist.insert(cn.clone());
            }
            Op::SetLinkGrant { id, path, level } => {
                let level =
                    wyrm_core::Perm::try_from(*level).map_err(|c| format!("bad level code {c}"))?;
                let def = self
                    .links
                    .get_mut(id)
                    .ok_or_else(|| format!("no link {id}"))?;
                def.grants.retain(|(p, _)| p != path);
                if level != wyrm_core::Perm::None {
                    check_grant(path, level)?;
                    def.grants.push((path.clone(), level.code()));
                    def.grants.sort();
                }
            }
            Op::PutWatchGroup {
                name,
                logging,
                interval_ms,
                flush_ms,
            } => {
                validate_segment(name).map_err(|e| format!("group: {e}"))?;
                if name.starts_with('.') || name.starts_with('~') {
                    return Err(format!("group {name:?}: starts with a letter or digit"));
                }
                if wyrm_history::Logging::from_code(*logging).is_none() {
                    return Err(format!("logging code {logging}?"));
                }
                if !INTERVAL_MS.contains(interval_ms) || !FLUSH_MS.contains(flush_ms) {
                    return Err(format!(
                        "interval {interval_ms} ms (100 ms to 1 day), flush {flush_ms} ms (100 ms to 10 min)"
                    ));
                }
                let h = &mut self.historian;
                if !h.groups.contains_key(name) && h.groups.len() >= MAX_WATCH_GROUPS {
                    return Err(format!("at most {MAX_WATCH_GROUPS} watch groups"));
                }
                let g = h.groups.entry(name.clone()).or_insert(WatchGroupDef {
                    logging: *logging,
                    interval_ms: *interval_ms,
                    flush_ms: *flush_ms,
                    watches: BTreeMap::new(),
                });
                g.logging = *logging;
                g.interval_ms = *interval_ms;
                g.flush_ms = *flush_ms;
            }
            Op::RemoveWatchGroup(name) => {
                self.historian
                    .groups
                    .remove(name)
                    .ok_or_else(|| format!("no watch group {name}"))?;
            }
            Op::SetWatchKey { group, id, key } => {
                check_watch_key(key)?;
                let g = self
                    .historian
                    .groups
                    .get_mut(group)
                    .ok_or_else(|| format!("no watch group {group}"))?;
                if g.watches.iter().any(|(i, w)| i != id && w.key == *key) {
                    return Err(format!("{key} is watched in {group}"));
                }
                g.watches
                    .get_mut(id)
                    .ok_or_else(|| format!("no watch {group}/{id}"))?
                    .key = key.clone();
            }
            Op::AddWatch { group, key } => {
                check_watch_key(key)?;
                let total: usize = self
                    .historian
                    .groups
                    .values()
                    .map(|g| g.watches.len())
                    .sum();
                if total >= MAX_WATCHES {
                    return Err(format!("at most {MAX_WATCHES} watches"));
                }
                let g = self
                    .historian
                    .groups
                    .get_mut(group)
                    .ok_or_else(|| format!("no watch group {group}"))?;
                if g.watches.values().any(|w| w.key == *key) {
                    return Err(format!("{key} is watched in {group}"));
                }
                let next = g
                    .watches
                    .keys()
                    .filter_map(|id| id.strip_prefix('w')?.parse::<u32>().ok())
                    .max()
                    .unwrap_or(0)
                    + 1;
                g.watches.insert(
                    format!("w{next}"),
                    WatchDef {
                        key: key.clone(),
                        enabled: true,
                    },
                );
            }
            Op::SetWatchEnabled { group, id, on } => {
                self.historian
                    .groups
                    .get_mut(group)
                    .and_then(|g| g.watches.get_mut(id))
                    .ok_or_else(|| format!("no watch {group}/{id}"))?
                    .enabled = *on;
            }
            Op::RemoveWatch { group, id } => {
                self.historian
                    .groups
                    .get_mut(group)
                    .and_then(|g| g.watches.remove(id))
                    .ok_or_else(|| format!("no watch {group}/{id}"))?;
            }
            Op::SetHistoryOptions {
                auto_purge,
                keep_free_mib,
                retention_days,
            } => {
                let h = &mut self.historian;
                h.auto_purge = *auto_purge;
                h.keep_free_mib = *keep_free_mib;
                h.retention_days = *retention_days;
            }
            Op::SetLogLevel { link, level } => {
                if let Some(l) = level {
                    if crate::logs::parse_level(l).is_none() {
                        return Err(format!("level {l:?}: one of {:?}", crate::logs::LEVELS));
                    }
                }
                match link {
                    None => self.log_level = level.clone(),
                    Some(id) => {
                        self.links
                            .get_mut(id)
                            .ok_or_else(|| format!("no link {id}"))?
                            .log_level = level.clone();
                    }
                }
            }
            Op::PutPackage(def) => {
                validate_link_id(&def.name).map_err(|e| format!("package {e}"))?;
                self.packages.insert(def.name.clone(), def.clone());
            }
            Op::RemovePackage(name) => {
                let driver = format!("pkg:{name}");
                if let Some(l) = self.links.values().find(|l| l.driver == driver) {
                    return Err(format!("link {} runs package {name}", l.id));
                }
                self.packages
                    .remove(name)
                    .ok_or_else(|| format!("no package {name}"))?;
            }
            Op::Deauthorize { id, seen } => {
                let def = self.links.get(id).ok_or_else(|| format!("no link {id}"))?;
                if def.mode != Mode::External || def.origin != Origin::Runtime {
                    return Err(format!(
                        "{id} is not an authorized external link (installed at runtime)"
                    ));
                }
                self.links.remove(id);
                self.history.remove(id);
                self.quarantine.insert(
                    id.clone(),
                    QuarantineEntry {
                        first_seen: *seen,
                        last_seen: *seen,
                        attempts: 0,
                    },
                );
                self.held.insert(id.clone());
            }
            Op::PutProfile { name, cbor } => {
                let def: ProfileDef = wyrm_core::codec::from_slice(cbor)
                    .map_err(|e| format!("profile {name}: {e}"))?;
                self.check_profile(name, &def)?;
                self.profiles.insert(name.clone(), cbor.clone());
            }
            Op::RemoveProfile(name) => {
                if !self.profiles.contains_key(name) {
                    return Err(format!("no profile {name}"));
                }
                let child = self.profiles.iter().find(|(n, b)| {
                    *n != name
                        && wyrm_core::codec::from_slice::<ProfileDef>(b)
                            .is_ok_and(|p| p.extends.as_deref() == Some(name.as_str()))
                });
                if let Some((c, _)) = child {
                    return Err(format!("profile {c} extends {name}"));
                }
                self.profiles.remove(name);
            }
            Op::AddPeer(def) => {
                validate_segment(&def.site).map_err(|e| format!("site: {e}"))?;
                if self.peers.contains_key(&def.site) {
                    return Err(format!("peer {} exists", def.site));
                }
                if self.peers.values().any(|p| p.via.contains(&def.site)) {
                    return Err(format!("{} is relayed by another peer", def.site));
                }
                if def.dir == PeerDir::Downstream && self.links.contains_key(&def.site) {
                    return Err(format!(
                        "{} is a link id (downstream/{} would be both)",
                        def.site, def.site
                    ));
                }
                let reach = !def.endpoint.is_empty() || !def.enroll.is_empty();
                if (def.dir == PeerDir::Upstream) != reach {
                    return Err("an upstream peer needs an endpoint, a downstream one none".into());
                }
                if def.dir == PeerDir::Upstream && !def.via.is_empty() {
                    return Err("only a downstream peer relays sites".into());
                }
                // its certificate would match this upstream's ACL subject
                if def.dir == PeerDir::Upstream && self.issued_brokers.contains(&def.site) {
                    return Err(format!(
                        "{} was a downstream broker of ours (its certificate stays valid)",
                        def.site
                    ));
                }
                for v in &def.via {
                    validate_segment(v).map_err(|e| format!("via: {e}"))?;
                    let taken = *v == def.site
                        || self
                            .peers
                            .values()
                            .any(|p| p.site == *v || p.via.contains(v))
                        || def.via.iter().filter(|x| *x == v).count() > 1;
                    if taken {
                        return Err(format!("via {v}: already a peer site or relayed"));
                    }
                }
                self.peers.insert(def.site.clone(), def.clone());
            }
            Op::RemovePeer(site) => {
                self.peers
                    .remove(site)
                    .ok_or_else(|| format!("no peer {site}"))?;
                self.signers.remove(site);
                self.config_signers.remove(site);
            }
            Op::IssueBroker(site) => {
                validate_segment(site).map_err(|e| format!("site: {e}"))?;
                if self
                    .peers
                    .get(site)
                    .is_some_and(|p| p.dir == PeerDir::Upstream)
                {
                    return Err(format!("{site} is an upstream site"));
                }
                self.issued_brokers.insert(site.clone());
            }
            Op::HoldBroker { site, seen } => {
                let def = match self.peers.get(site) {
                    Some(p) if p.dir == PeerDir::Downstream => p.clone(),
                    _ => return Err(format!("{site} is not a runtime downstream broker")),
                };
                self.peers.remove(site);
                // what Authorize gives back: the same key and certificate
                self.enrollments.insert(
                    site.clone(),
                    Enrollment {
                        key_sha256: def.key_sha256,
                        via: def.via,
                        cert_pem: def.cert_pem,
                        ..Default::default()
                    },
                );
                let cn = broker_cn(site);
                self.quarantine.insert(
                    cn.clone(),
                    QuarantineEntry {
                        first_seen: *seen,
                        last_seen: *seen,
                        attempts: 0,
                    },
                );
                self.held.insert(cn);
            }
            Op::EnrollRequest {
                site,
                csr_pem,
                key_sha256,
                via,
                seen,
            } => {
                validate_segment(site).map_err(|e| format!("site: {e}"))?;
                let cn = broker_cn(site);
                if self.peers.contains_key(site) {
                    return Err(format!("{site} is a peer"));
                }
                if self.blocklist.contains(&cn) || self.links.contains_key(site) {
                    return Err(format!("{site} is refused here"));
                }
                if !self.enrollments.contains_key(site) && self.enrollments.len() >= MAX_ENROLLMENTS
                {
                    return Err(format!("at most {MAX_ENROLLMENTS} brokers wait"));
                }
                let e = self.enrollments.entry(site.clone()).or_default();
                if e.key_sha256.is_empty() || e.key_sha256 == *key_sha256 {
                    e.key_sha256 = key_sha256.clone();
                    e.csr_pem = csr_pem.clone();
                    e.via = via.clone();
                } else {
                    e.conflicts += 1;
                }
                let q = self.quarantine.entry(cn).or_insert(QuarantineEntry {
                    first_seen: *seen,
                    ..Default::default()
                });
                q.last_seen = *seen;
                q.attempts += 1;
            }
            Op::AdmitBroker {
                site,
                via,
                key_sha256,
                cert_pem,
                seen,
            } => {
                validate_segment(site).map_err(|e| format!("site: {e}"))?;
                if self.peers.contains_key(site) || self.links.contains_key(site) {
                    return Err(format!("{site} is a peer or a link"));
                }
                for v in via {
                    validate_segment(v).map_err(|e| format!("via: {e}"))?;
                    let taken = v == site
                        || self
                            .peers
                            .values()
                            .any(|p| p.site == *v || p.via.contains(v))
                        || via.iter().filter(|x| *x == v).count() > 1;
                    if taken {
                        return Err(format!("via {v}: already a peer site or relayed"));
                    }
                }
                let cn = broker_cn(site);
                self.quarantine.remove(&cn);
                self.held.remove(&cn);
                self.enrollments.remove(site);
                self.issued_brokers.insert(site.clone());
                self.peers.insert(
                    site.clone(),
                    PeerDef {
                        site: site.clone(),
                        dir: PeerDir::Downstream,
                        endpoint: String::new(),
                        ca_pem: String::new(),
                        enabled: true,
                        created: *seen,
                        via: via.clone(),
                        cert_pem: cert_pem.clone(),
                        enroll: String::new(),
                        key_sha256: key_sha256.clone(),
                        allow_config: false,
                    },
                );
            }
            Op::SetPeerCert {
                site,
                endpoint,
                cert_pem,
            } => {
                let p = self
                    .peers
                    .get_mut(site)
                    .filter(|p| p.dir == PeerDir::Upstream)
                    .ok_or_else(|| format!("no upstream peer {site}"))?;
                p.endpoint = endpoint.clone();
                p.cert_pem = cert_pem.clone();
            }
            Op::AddToken { id, def } => {
                validate_segment(id).map_err(|e| format!("token id: {e}"))?;
                if self.tokens.contains_key(id) {
                    return Err(format!("token {id} exists"));
                }
                self.tokens.insert(id.clone(), def.clone());
            }
            Op::UseToken(id) => {
                let t = self
                    .tokens
                    .get_mut(id)
                    .ok_or_else(|| format!("no token {id}"))?;
                match t.uses {
                    0 => {}
                    1 => {
                        self.tokens.remove(id);
                    }
                    _ => t.uses -= 1,
                }
            }
            Op::DropEnrollment(site) => {
                let cn = broker_cn(site);
                if self.held.contains(&cn) {
                    return Err(format!("{site} is held"));
                }
                self.enrollments
                    .remove(site)
                    .ok_or_else(|| format!("{site} does not wait"))?;
                self.quarantine.remove(&cn);
            }
            Op::RemoveToken(id) => {
                self.tokens
                    .remove(id)
                    .ok_or_else(|| format!("no token {id}"))?;
            }
            Op::SetPeerEnabled { site, on } => {
                self.peers
                    .get_mut(site)
                    .ok_or_else(|| format!("no peer {site}"))?
                    .enabled = *on;
            }
            Op::SetPeerAllowConfig { site, on } => {
                let p = self
                    .peers
                    .get_mut(site)
                    .filter(|p| p.dir == PeerDir::Upstream)
                    .ok_or_else(|| format!("no upstream peer {site}"))?;
                p.allow_config = *on;
            }
            Op::SetSigners {
                upstream,
                keys,
                config,
            } => {
                validate_segment(upstream).map_err(|e| format!("upstream: {e}"))?;
                check_signers(keys)?;
                check_signers(config)?;
                for (map, v) in [
                    (&mut self.signers, keys),
                    (&mut self.config_signers, config),
                ] {
                    if v.is_empty() {
                        map.remove(upstream);
                    } else {
                        map.insert(upstream.clone(), v.clone());
                    }
                }
            }
            Op::SetOption { name, on } => match name.as_str() {
                "allow_all_links" => self.options.allow_all_links = *on,
                "enable_quarantine" => self.options.enable_quarantine = *on,
                other => return Err(format!("no option {other}")),
            },
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use wyrm_state::State;

    fn def(id: &str, mode: Mode) -> LinkDef {
        LinkDef {
            id: id.into(),
            driver: "d".into(),
            mode,
            params: vec![0xa0],
            token_hash: "h".into(),
            rev: 1,
            origin: Origin::Runtime,
            created: 0,
            display: None,
            granted: None,
            log_level: None,
            grants: Vec::new(),
        }
    }

    /// ADR 0018: an upstream's signing keys are checked, stored by
    /// upstream, cleared by an empty map and dropped with the peer.
    #[test]
    fn signers_are_checked_and_follow_the_peer() {
        let key = hex::encode(
            ed25519_dalek::SigningKey::from_bytes(&[3; 32])
                .verifying_key()
                .to_bytes(),
        );
        let one = |site: &str, keys: Vec<String>| BTreeMap::from([(site.to_owned(), keys)]);
        let mut r = Registry::default();
        let set = |r: &mut Registry, keys: BTreeMap<String, Vec<String>>| {
            r.apply(&Op::SetSigners {
                upstream: "hq".into(),
                keys: keys.clone(),
                config: keys,
            })
        };
        assert!(
            set(&mut r, one("hq", vec!["00".into()])).is_err(),
            "not a key"
        );
        assert!(set(&mut r, one("h q", vec![key.clone()])).is_err(), "site");
        assert!(set(&mut r, one("hq", vec![key.clone(); MAX_SIGNER_KEYS + 1])).is_err());
        let many = (0..=MAX_SIGNER_SITES)
            .map(|i| (format!("s{i}"), vec![key.clone()]))
            .collect();
        assert!(set(&mut r, many).is_err(), "too many sites");
        set(&mut r, one("hq", vec![key.clone()])).unwrap();
        assert_eq!(r.signers["hq"]["hq"], std::slice::from_ref(&key));
        assert_eq!(r.config_signers["hq"]["hq"], std::slice::from_ref(&key));
        set(&mut r, BTreeMap::new()).unwrap();
        assert!(r.signers.is_empty() && r.config_signers.is_empty());
        r.apply(&Op::AddPeer(PeerDef {
            site: "hq".into(),
            dir: PeerDir::Upstream,
            endpoint: "quic/hq:1".into(),
            ca_pem: String::new(),
            enabled: true,
            created: 0,
            via: Vec::new(),
            cert_pem: String::new(),
            enroll: String::new(),
            key_sha256: String::new(),
            allow_config: false,
        }))
        .unwrap();
        set(&mut r, one("hq", vec![key])).unwrap();
        r.apply(&Op::SetPeerAllowConfig {
            site: "hq".into(),
            on: true,
        })
        .unwrap();
        assert!(r.peers["hq"].allow_config);
        r.apply(&Op::RemovePeer("hq".into())).unwrap();
        assert!(r.signers.is_empty(), "gone with the peer");
        assert!(r.config_signers.is_empty());
    }

    /// A watch stored with a route gets its key; a key already watched in
    /// the group is refused.
    #[test]
    fn watch_keys_change_in_place() {
        let mut r = Registry::default();
        r.apply(&Op::PutWatchGroup {
            name: "g".into(),
            logging: 2,
            interval_ms: 1000,
            flush_ms: 1000,
        })
        .unwrap();
        for key in [
            "wy/c/downstream/edge/downstream/lab/x",
            "wy/edge/downstream/lab/y",
        ] {
            r.apply(&Op::AddWatch {
                group: "g".into(),
                key: key.into(),
            })
            .unwrap();
        }
        r.apply(&Op::SetWatchKey {
            group: "g".into(),
            id: "w1".into(),
            key: "wy/edge/downstream/lab/x".into(),
        })
        .unwrap();
        assert_eq!(
            r.historian.groups["g"].watches["w1"].key,
            "wy/edge/downstream/lab/x"
        );
        assert!(r
            .apply(&Op::SetWatchKey {
                group: "g".into(),
                id: "w1".into(),
                key: "wy/edge/downstream/lab/y".into(),
            })
            .is_err());
    }

    #[test]
    fn link_ids() {
        assert!(validate_link_id("plc1").is_ok());
        for bad in [".", "..", ".hidden", "a/b", "admin", "broker", "~x", ""] {
            assert!(validate_link_id(bad).is_err(), "{bad:?}");
        }
        assert!(validate_link_id("storage").is_ok(), "replays");
        assert!(validate_new_link_id("storage").is_err());
    }

    #[test]
    fn peers_and_link_ids_do_not_overlap() {
        let mut r = Registry::default();
        let peer = |site: &str, dir, endpoint: &str| PeerDef {
            site: site.into(),
            dir,
            endpoint: endpoint.into(),
            ca_pem: "pem".into(),
            enabled: true,
            created: 0,
            via: Vec::new(),
            cert_pem: String::new(),
            enroll: String::new(),
            key_sha256: String::new(),
            allow_config: false,
        };
        r.apply(&Op::AddPeer(peer("edge", PeerDir::Downstream, "")))
            .unwrap();
        // a site edge relays cannot become a peer of its own
        let mut relay = peer("hub", PeerDir::Downstream, "");
        relay.via = vec!["cell".into()];
        r.apply(&Op::AddPeer(relay)).unwrap();
        assert!(r
            .apply(&Op::AddPeer(peer("cell", PeerDir::Downstream, "")))
            .is_err());
        let mut twice = peer("hub2", PeerDir::Downstream, "");
        twice.via = vec!["cell".into()];
        assert!(r.apply(&Op::AddPeer(twice)).is_err(), "relayed twice");
        r.apply(&Op::AddPeer(peer(
            "cloud",
            PeerDir::Upstream,
            "quic/c:7448",
        )))
        .unwrap();
        assert!(r
            .apply(&Op::AddPeer(peer("x", PeerDir::Upstream, "")))
            .is_err());
        assert!(r
            .apply(&Op::AddPeer(peer("edge", PeerDir::Downstream, "")))
            .is_err());
        let mut d = def("edge", Mode::External);
        assert!(r.apply(&Op::Install(d.clone())).is_err(), "downstream name");
        d.id = "plc".into();
        r.apply(&Op::Install(d)).unwrap();
        assert!(r
            .apply(&Op::AddPeer(peer("plc", PeerDir::Downstream, "")))
            .is_err());
        r.apply(&Op::SetPeerEnabled {
            site: "cloud".into(),
            on: false,
        })
        .unwrap();
        assert!(!r.peers["cloud"].enabled);
        r.apply(&Op::RemovePeer("edge".into())).unwrap();
        assert!(r.apply(&Op::RemovePeer("edge".into())).is_err());
    }

    /// Fields added later must not break older WAL records (a field that
    /// is not an `Option` needs `#[cbor(default)]`).
    #[test]
    fn older_records_still_decode() {
        #[derive(minicbor::Encode)]
        struct LinkDefV1 {
            #[n(0)]
            id: String,
            #[n(1)]
            driver: String,
            #[n(2)]
            mode: Mode,
            #[n(3)]
            #[cbor(with = "minicbor::bytes")]
            params: Vec<u8>,
            #[n(4)]
            token_hash: String,
            #[n(5)]
            rev: u32,
            #[n(6)]
            origin: Origin,
            #[n(7)]
            created: u64,
        }
        let old = LinkDefV1 {
            id: "plc1".into(),
            driver: "modbus".into(),
            mode: Mode::Process,
            params: vec![0xa0],
            token_hash: "h".into(),
            rev: 3,
            origin: Origin::Runtime,
            created: 7,
        };
        let bytes = minicbor::to_vec(&old).unwrap();
        let d: LinkDef = minicbor::decode(&bytes).expect("an older LinkDef decodes");
        assert_eq!((d.id.as_str(), d.rev), ("plc1", 3));
        assert!(d.grants.is_empty() && d.display.is_none() && d.log_level.is_none());

        #[derive(minicbor::Encode)]
        struct PackageDefV1 {
            #[n(0)]
            name: String,
            #[n(1)]
            version: String,
            #[n(2)]
            kind: PackageKind,
            #[n(3)]
            entry: String,
            #[n(4)]
            args: Vec<String>,
            #[n(5)]
            sha256: String,
            #[n(6)]
            source: String,
            #[n(7)]
            description: String,
            #[n(8)]
            installed: u64,
        }
        let old = PackageDefV1 {
            name: "p".into(),
            version: "1".into(),
            kind: PackageKind::Process,
            entry: "bin/x".into(),
            args: vec![],
            sha256: "00".into(),
            source: "zip".into(),
            description: String::new(),
            installed: 1,
        };
        let p: PackageDef = minicbor::decode(&minicbor::to_vec(&old).unwrap()).unwrap();
        assert!(p.requester.is_empty());
    }

    #[test]
    fn link_grants() {
        use wyrm_core::Perm;
        let mut r = Registry::default();
        r.apply(&Op::Install(def("rec", Mode::External))).unwrap();
        let grant = |path: &str, level: Perm| Op::SetLinkGrant {
            id: "rec".into(),
            path: path.into(),
            level: level.code(),
        };
        r.apply(&grant("wy/{site}/downstream/mock", Perm::Read))
            .unwrap();
        r.apply(&grant("wy/{site}/downstream/plc1/c1", Perm::Write))
            .unwrap();
        r.apply(&grant("wy/{site}/dataflows", Perm::List)).unwrap();
        assert_eq!(r.links["rec"].grants.len(), 3);
        // a new level replaces, none removes
        r.apply(&grant("wy/{site}/downstream/mock", Perm::Write))
            .unwrap();
        r.apply(&grant("wy/{site}/dataflows", Perm::None)).unwrap();
        assert_eq!(
            r.links["rec"].grants,
            [
                ("wy/{site}/downstream/mock".to_string(), Perm::Write.code()),
                (
                    "wy/{site}/downstream/plc1/c1".to_string(),
                    Perm::Write.code()
                )
            ]
        );
        for (path, level) in [
            ("wy/{site}/sys/links", Perm::Read),
            ("wy/other/downstream/x", Perm::Read),
            ("wy/{site}/downstream/**", Perm::Read),
            ("wy/{site}/downstream/x/~set", Perm::Read),
            ("wy/{site}/downstream/x", Perm::Config),
            ("wy/{site}/dataflows/f1", Perm::Write),
        ] {
            assert!(r.apply(&grant(path, level)).is_err(), "{path} {level:?}");
        }
    }

    /// ADR 0015: a name our CA issued `broker:<site>` for never becomes an
    /// upstream site; a removed downstream broker waits in quarantine, held.
    /// ADR 0015: a request waits; another key for the same name only
    /// counts; admission clears it; held brokers keep their grant; tokens.
    #[test]
    fn enrollments_and_tokens() {
        let mut r = Registry::default();
        let ask = |site: &str, key: &str| Op::EnrollRequest {
            site: site.into(),
            csr_pem: format!("csr-{key}"),
            key_sha256: key.into(),
            via: vec!["cell".into()],
            seen: 1,
        };
        r.apply(&ask("edge", "k1")).unwrap();
        r.apply(&ask("edge", "k2")).unwrap();
        let e = &r.enrollments["edge"];
        assert_eq!(
            (e.key_sha256.as_str(), e.csr_pem.as_str(), e.conflicts),
            ("k1", "csr-k1", 1)
        );
        assert_eq!(r.quarantine["broker:edge"].attempts, 2);
        for i in 1..MAX_ENROLLMENTS {
            r.apply(&ask(&format!("s{i}"), "k")).unwrap();
        }
        assert!(
            r.apply(&ask("one-more", "k")).is_err(),
            "at most {MAX_ENROLLMENTS}"
        );
        r.apply(&Op::AdmitBroker {
            site: "edge".into(),
            via: vec!["cell".into()],
            key_sha256: "k1".into(),
            cert_pem: "cert".into(),
            seen: 2,
        })
        .unwrap();
        assert!(!r.enrollments.contains_key("edge") && !r.quarantine.contains_key("broker:edge"));
        assert!(r.issued_brokers.contains("edge"));
        assert!(r.apply(&ask("edge", "k1")).is_err(), "a peer does not wait");
        r.apply(&Op::HoldBroker {
            site: "edge".into(),
            seen: 3,
        })
        .unwrap();
        let held = &r.enrollments["edge"];
        assert_eq!(
            (held.key_sha256.as_str(), held.cert_pem.as_str()),
            ("k1", "cert")
        );
        r.apply(&Op::Reject("broker:edge".into())).unwrap();
        assert!(!r.enrollments.contains_key("edge"));
        assert!(r.apply(&ask("edge", "k1")).is_err(), "rejected");

        let token = |uses| TokenDef {
            sha256: "h".into(),
            uses,
            expires: 0,
            created: 0,
            by: "admin".into(),
        };
        r.apply(&Op::AddToken {
            id: "t1".into(),
            def: token(2),
        })
        .unwrap();
        r.apply(&Op::UseToken("t1".into())).unwrap();
        assert_eq!(r.tokens["t1"].uses, 1);
        r.apply(&Op::UseToken("t1".into())).unwrap();
        assert!(!r.tokens.contains_key("t1"), "used up");
        r.apply(&Op::AddToken {
            id: "t2".into(),
            def: token(0),
        })
        .unwrap();
        r.apply(&Op::UseToken("t2".into())).unwrap();
        assert_eq!(r.tokens["t2"].uses, 0, "no limit");
        r.apply(&Op::RemoveToken("t2".into())).unwrap();
        assert!(r.tokens.is_empty());
    }

    #[test]
    fn downstream_brokers_issued_and_held() {
        let mut r = Registry::default();
        let peer = |site: &str, dir, endpoint: &str| PeerDef {
            site: site.into(),
            dir,
            endpoint: endpoint.into(),
            ca_pem: String::new(),
            enabled: true,
            created: 0,
            via: Vec::new(),
            cert_pem: String::new(),
            enroll: String::new(),
            key_sha256: String::new(),
            allow_config: false,
        };
        r.apply(&Op::IssueBroker("edge".into())).unwrap();
        r.apply(&Op::AddPeer(peer("edge", PeerDir::Downstream, "")))
            .unwrap();
        // its certificate would match an upstream subject `broker:edge`
        r.apply(&Op::RemovePeer("edge".into())).unwrap();
        assert!(r
            .apply(&Op::AddPeer(peer("edge", PeerDir::Upstream, "quic/e:1")))
            .is_err());
        r.apply(&Op::AddPeer(peer("cloud", PeerDir::Upstream, "quic/c:1")))
            .unwrap();
        assert!(
            r.apply(&Op::IssueBroker("cloud".into())).is_err(),
            "upstream"
        );

        r.apply(&Op::AddPeer(peer("edge", PeerDir::Downstream, "")))
            .unwrap();
        assert!(
            r.apply(&Op::Quarantine {
                cn: "broker:edge".into(),
                seen: 1
            })
            .is_err(),
            "a peer is not quarantined"
        );
        r.apply(&Op::HoldBroker {
            site: "edge".into(),
            seen: 2,
        })
        .unwrap();
        assert!(!r.peers.contains_key("edge"));
        assert!(r.quarantine.contains_key("broker:edge") && r.held.contains("broker:edge"));
        assert!(
            r.apply(&Op::HoldBroker {
                site: "cloud".into(),
                seen: 3
            })
            .is_err(),
            "upstream sites are not held"
        );
        r.apply(&Op::Approve("broker:edge".into())).unwrap();
        assert!(!r.held.contains("broker:edge"));
        assert!(r
            .apply(&Op::Quarantine {
                cn: "broker:no/site".into(),
                seen: 4
            })
            .is_err());
    }

    /// WAL records written before spec 0.2.0 replay under the new section
    /// names: grants, package requests and watches.
    #[test]
    fn keys_before_spec_0_2_replay_renamed() {
        use wyrm_core::Perm;
        let mut r = Registry::default();
        let mut d = def("rec", Mode::External);
        d.grants = vec![("wy/{site}/flows/f1".into(), Perm::Read.code())];
        r.apply(&Op::Install(d)).unwrap();
        r.apply(&Op::SetLinkGrant {
            id: "rec".into(),
            path: "wy/{site}/down/plc1".into(),
            level: Perm::Write.code(),
        })
        .unwrap();
        assert_eq!(
            r.links["rec"].grants,
            [
                ("wy/{site}/dataflows/f1".to_string(), Perm::Read.code()),
                ("wy/{site}/downstream/plc1".to_string(), Perm::Write.code())
            ]
        );
        r.apply(&Op::PutWatchGroup {
            name: "g".into(),
            logging: 2,
            interval_ms: 1000,
            flush_ms: 1000,
        })
        .unwrap();
        r.apply(&Op::AddWatch {
            group: "g".into(),
            key: "wy/s/down/mock/p0".into(),
        })
        .unwrap();
        let w: Vec<&str> = r.historian.groups["g"]
            .watches
            .values()
            .map(|w| w.key.as_str())
            .collect();
        assert_eq!(w, ["wy/s/downstream/mock/p0"]);
    }

    #[test]
    fn watch_groups_and_watches() {
        let mut r = Registry::default();
        let group = |name: &str, logging: u8, interval_ms: u64| Op::PutWatchGroup {
            name: name.into(),
            logging,
            interval_ms,
            flush_ms: 1000,
        };
        let watch = |key: &str| Op::AddWatch {
            group: "g".into(),
            key: key.into(),
        };
        r.apply(&group("g", 2, 60_000)).unwrap();
        r.apply(&watch("wy/s/downstream/mock/g0/p0")).unwrap();
        r.apply(&watch("wy/s/dataflows/f1/out")).unwrap();
        assert!(
            r.apply(&watch("wy/s/downstream/mock/g0/p0")).is_err(),
            "twice"
        );
        for bad in [
            "wy/s/sys/links",
            "wy/s/downstream",
            "wy/s/downstream/mock/**",
            "wy/s/downstream/mock/p/~val",
            "downstream/mock/p",
        ] {
            assert!(r.apply(&watch(bad)).is_err(), "{bad}");
        }
        let g = &r.historian.groups["g"];
        assert_eq!(g.watches.keys().collect::<Vec<_>>(), ["w1", "w2"]);
        // ids are not reused after a removal of an earlier one
        r.apply(&Op::RemoveWatch {
            group: "g".into(),
            id: "w1".into(),
        })
        .unwrap();
        r.apply(&watch("wy/s/downstream/mock/g0/p1")).unwrap();
        assert!(r.historian.groups["g"].watches.contains_key("w3"));
        r.apply(&Op::SetWatchEnabled {
            group: "g".into(),
            id: "w3".into(),
            on: false,
        })
        .unwrap();
        assert!(!r.historian.groups["g"].watches["w3"].enabled);
        // an edit keeps the watches
        r.apply(&group("g", 1, 5_000)).unwrap();
        assert_eq!(r.historian.groups["g"].watches.len(), 2);
        assert_eq!(r.historian.groups["g"].logging, 1);
        assert!(r.apply(&group("bad", 9, 1000)).is_err(), "logging code");
        assert!(r.apply(&group("bad", 1, 10)).is_err(), "interval");
        assert!(r.apply(&group("~x", 1, 1000)).is_err(), "name");
        r.apply(&Op::RemoveWatchGroup("g".into())).unwrap();
        assert!(r.historian.groups.is_empty());
        r.apply(&Op::SetHistoryOptions {
            auto_purge: false,
            keep_free_mib: 10,
            retention_days: 30,
        })
        .unwrap();
        assert_eq!(r.historian.retention_days, 30);
    }

    #[test]
    fn deauthorized_links_go_back_to_quarantine() {
        let mut r = Registry::default();
        r.apply(&Op::Install(def("dev", Mode::External))).unwrap();
        r.apply(&Op::Install(def("emb", Mode::Embedded))).unwrap();
        assert!(r
            .apply(&Op::Deauthorize {
                id: "emb".into(),
                seen: 5
            })
            .is_err());
        r.apply(&Op::Deauthorize {
            id: "dev".into(),
            seen: 5,
        })
        .unwrap();
        assert!(!r.links.contains_key("dev") && !r.retired.contains("dev"));
        assert!(r.quarantine.contains_key("dev") && r.held.contains("dev"));
        // a manual Authorize (approve + install) clears the hold
        r.apply(&Op::Approve("dev".into())).unwrap();
        assert!(!r.held.contains("dev"));
        r.apply(&Op::Install(def("dev", Mode::External))).unwrap();
    }

    #[test]
    fn removed_remote_ids_are_retired() {
        let mut r = Registry::default();
        r.apply(&Op::Install(def("plc1", Mode::Process))).unwrap();
        r.apply(&Op::Remove("plc1".into())).unwrap();
        assert!(r.apply(&Op::Install(def("plc1", Mode::Process))).is_err());
        assert!(r
            .apply(&Op::Quarantine {
                cn: "plc1".into(),
                seen: 1
            })
            .is_err());
        // embedded links have no certificate: the id may come back
        let mut e = def("emb", Mode::Embedded);
        e.token_hash.clear();
        r.apply(&Op::Install(e.clone())).unwrap();
        r.apply(&Op::Remove("emb".into())).unwrap();
        r.apply(&Op::Install(e)).unwrap();
        assert!(r.apply(&Op::Install(def("..", Mode::External))).is_err());
        // remote, then switched to embedded: the certificate still exists
        r.apply(&Op::Install(def("sw", Mode::Process))).unwrap();
        r.apply(&Op::Update {
            id: "sw".into(),
            mode: Mode::Embedded,
            params: vec![0xa0],
        })
        .unwrap();
        r.apply(&Op::Remove("sw".into())).unwrap();
        assert!(r.retired.contains("sw"));
    }
}
