//! Device keys (ADR 0050 §1): a person unlocks a key in the device's secure hardware with a
//! biometric, the device signs a single-use challenge, and the gateway checks the signature
//! against the public key it stored at registration. The gateway decides who is in; the
//! device only decides that the person is there.
//!
//! * `POST /api/device/challenge {device}` → `{nonce, exp}` for a login; with a bearer
//!   session and `{purpose: "register" | "confirm"}` → a nonce bound to that session's user.
//!   A nonce is single use (taken on its first use, also when that use fails) and lives
//!   [`CHALLENGE_TTL_S`].
//! * `POST /api/devices {name, platform, alg, public_key, attestation?, origin, nonce,
//!   signature}` (bearer session that checked the password in the last [`FRESH_S`]) → `{device}`
//! * `POST /api/device/login {device, origin, nonce, signature, session?}` → `{session, exp}`
//!   as `/api/login`; with a `session` of the same user that one is kept (the idle lock).
//! * `POST /api/device/confirm {device, origin, nonce, request, signature}` and
//!   `POST /api/confirm {password}` (bearer session): the step-up (`step_up: "config"`).
//! * `GET /api/devices`, `DELETE /api/devices/{id}`, `GET /api/users/{name}/devices` (admin).
//!
//! Signed bytes are canonical CBOR arrays with a label first ([`login_message`],
//! [`register_message`], [`confirm_message`]): no field can run into the next one.
//!
//! Refusals carry `status: permission_denied` (spec 04) and a `code` (see [`Refused`]). An
//! unknown device, a bad signature, an origin this gateway does not serve and a nonce that
//! is unknown, used or old get one bare refusal without a code, counted by the login
//! limiter: they tell a caller nothing about which device ids exist.

use crate::session::{self, Amr, SessionClaims};
use crate::users::{Device, Op};
use crate::{AuditEvent, Gateway, Principal};
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::net::IpAddr;
use std::sync::Mutex;
use wyrm_core::Value;
use zeroize::Zeroizing;

/// Lifetime of a challenge.
pub const CHALLENGE_TTL_S: u64 = 60;
/// How recent the password must be to register a device, and how long a step-up holds.
pub const FRESH_S: u64 = 300;
/// Live challenges in all; past it new ones are refused (`busy`) until old ones expire.
const MAX_CHALLENGES: usize = 10_000;
/// Live challenges per device (logins) or per session (register, confirm); a new one
/// replaces the oldest.
const CHALLENGES_PER_KEY: usize = 4;
/// Sessions whose confirmations are remembered.
const MAX_FRESH: usize = 10_000;
/// Longest device name and platform text, in bytes.
const MAX_NAME: usize = 64;
/// Largest attestation kept (recorded, not checked: ADR 0050 "Not decided here").
const MAX_ATTESTATION: usize = 16 * 1024;
/// Largest public key accepted (an RSA-4096 key in SPKI DER is about 550 bytes).
const MAX_PUBLIC_KEY: usize = 1024;

pub const LOGIN_LABEL: &str = "wyrm-device-login/1";
pub const REGISTER_LABEL: &str = "wyrm-device-register/1";
pub const CONFIRM_LABEL: &str = "wyrm-device-confirm/1";

/// Platforms a device record may name (`web` is for passkeys later).
pub const PLATFORMS: [&str; 4] = ["macos", "windows", "ios", "android"];

/// `gateway.devices.step_up`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum StepUp {
    /// Nothing more than the session.
    #[default]
    None,
    /// Every request at `config` level needs a session confirmed in the last [`FRESH_S`].
    Config,
}

impl StepUp {
    pub fn name(self) -> &'static str {
        match self {
            StepUp::None => "none",
            StepUp::Config => "config",
        }
    }
}

/// `gateway.devices` in `wyrmd.json5` (ADR 0050 §1.6).
#[derive(Debug, Clone, PartialEq)]
pub struct DevicePolicy {
    /// `false` refuses device logins (`devices_off`) and keeps the records.
    pub enabled: bool,
    /// Devices that can log in, per user.
    pub max_per_user: usize,
    /// A device must see the password at least this often (`password_due`).
    pub password_every_days: u64,
    /// Studio's idle lock may be set up to this.
    pub idle_lock_max_min: u64,
    pub step_up: StepUp,
    /// A screen PIN or a computer's login password may stand in for biometrics (told to
    /// the client; the gateway cannot see which one unlocked the key).
    pub allow_device_credential: bool,
    /// The origins (`https://host[:port]`) a device may sign for. Empty: the DNS and IP
    /// names of the gateway's own certificate on the port it listens on, or the loopback
    /// names over plain HTTP on loopback.
    pub origins: Vec<String>,
    /// How long a login, a step-up or a password check counts as fresh: [`FRESH_S`]
    /// (`wyrmd` keeps it there; tests shorten it).
    pub fresh_s: u64,
}

impl Default for DevicePolicy {
    fn default() -> Self {
        Self {
            enabled: true,
            max_per_user: 5,
            password_every_days: 30,
            idle_lock_max_min: 30,
            step_up: StepUp::None,
            allow_device_credential: false,
            origins: Vec::new(),
            fresh_s: FRESH_S,
        }
    }
}

impl DevicePolicy {
    pub fn to_value(&self) -> Value {
        map([
            ("enabled", Value::Bool(self.enabled)),
            ("max_per_user", Value::UInt(self.max_per_user as u64)),
            ("password_every_days", Value::UInt(self.password_every_days)),
            ("idle_lock_max_min", Value::UInt(self.idle_lock_max_min)),
            ("step_up", Value::from(self.step_up.name())),
            (
                "allow_device_credential",
                Value::Bool(self.allow_device_credential),
            ),
        ])
    }
}

/// The signature scheme of a device key.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum KeyAlg {
    /// ECDSA P-256 with SHA-256, signature in ASN.1 DER (Secure Enclave, Android Keystore).
    /// The key is kept as the 65-byte uncompressed point.
    Es256,
    /// RSASSA-PKCS1-v1_5 with SHA-256, 2048 bits or more (Windows Hello's
    /// `KeyCredentialManager` makes RSA-2048 keys only). The key is kept as PKCS#1
    /// `RSAPublicKey` DER.
    Rs256,
}

impl KeyAlg {
    pub fn of(s: &str) -> Option<Self> {
        match s {
            "es256" => Some(KeyAlg::Es256),
            "rs256" => Some(KeyAlg::Rs256),
            _ => None,
        }
    }

    pub fn name(self) -> &'static str {
        match self {
            KeyAlg::Es256 => "es256",
            KeyAlg::Rs256 => "rs256",
        }
    }

    /// The key as the gateway keeps it: an ES256 key as the uncompressed point (also from
    /// SPKI DER), an RS256 key as PKCS#1 DER (also from SPKI DER). Whether it is a valid
    /// key shows at the registration's signature check.
    pub fn normalize(self, raw: &[u8]) -> Result<Vec<u8>, String> {
        if raw.is_empty() || raw.len() > MAX_PUBLIC_KEY {
            return Err("public_key: wrong size".into());
        }
        let spki = || {
            use x509_parser::prelude::FromDer;
            x509_parser::x509::SubjectPublicKeyInfo::from_der(raw)
                .ok()
                .filter(|(rest, _)| rest.is_empty())
                .map(|(_, k)| k)
        };
        match self {
            KeyAlg::Es256 => {
                if raw.len() == 65 && raw[0] == 0x04 {
                    return Ok(raw.to_vec());
                }
                let k = spki().ok_or("public_key: a P-256 point or SPKI DER")?;
                let ec = x509_parser::oid_registry::OID_KEY_TYPE_EC_PUBLIC_KEY;
                let p256 = x509_parser::oid_registry::OID_EC_P256;
                let curve = k
                    .algorithm
                    .parameters
                    .as_ref()
                    .and_then(|p| p.as_oid().ok());
                let point = k.subject_public_key.data.as_ref();
                if k.algorithm.algorithm != ec
                    || curve.as_ref() != Some(&p256)
                    || point.len() != 65
                    || point[0] != 0x04
                {
                    return Err("public_key: not a P-256 key".into());
                }
                Ok(point.to_vec())
            }
            KeyAlg::Rs256 => match spki() {
                Some(k) => {
                    if k.algorithm.algorithm != x509_parser::oid_registry::OID_PKCS1_RSAENCRYPTION {
                        return Err("public_key: not an RSA key".into());
                    }
                    Ok(k.subject_public_key.data.to_vec())
                }
                // PKCS#1 RSAPublicKey: a SEQUENCE; ring checks the rest
                None if raw[0] == 0x30 => Ok(raw.to_vec()),
                None => Err("public_key: PKCS#1 or SPKI DER".into()),
            },
        }
    }

    /// Check `sig` over `msg` with a key in the form of [`KeyAlg::normalize`].
    pub fn verify(self, public_key: &[u8], msg: &[u8], sig: &[u8]) -> bool {
        use ring::signature::{
            UnparsedPublicKey, ECDSA_P256_SHA256_ASN1, RSA_PKCS1_2048_8192_SHA256,
        };
        match self {
            KeyAlg::Es256 => UnparsedPublicKey::new(&ECDSA_P256_SHA256_ASN1, public_key)
                .verify(msg, sig)
                .is_ok(),
            KeyAlg::Rs256 => UnparsedPublicKey::new(&RSA_PKCS1_2048_8192_SHA256, public_key)
                .verify(msg, sig)
                .is_ok(),
        }
    }
}

fn array(items: Vec<Value>) -> Vec<u8> {
    wyrm_core::codec::to_vec(&Value::Array(items)).expect("arrays always encode")
}

/// What a device signs to log in: `["wyrm-device-login/1", site, origin, user, device,
/// nonce]`, canonical CBOR (nonce as a byte string).
pub fn login_message(site: &str, origin: &str, user: &str, device: &str, nonce: &[u8]) -> Vec<u8> {
    array(vec![
        Value::from(LOGIN_LABEL),
        Value::from(site),
        Value::from(origin),
        Value::from(user),
        Value::from(device),
        Value::Bytes(nonce.to_vec()),
    ])
}

/// What a new key signs at registration (proof that the device holds it):
/// `["wyrm-device-register/1", site, origin, user, nonce, public_key]` with the key bytes as
/// sent.
pub fn register_message(
    site: &str,
    origin: &str,
    user: &str,
    nonce: &[u8],
    public_key: &[u8],
) -> Vec<u8> {
    array(vec![
        Value::from(REGISTER_LABEL),
        Value::from(site),
        Value::from(origin),
        Value::from(user),
        Value::Bytes(nonce.to_vec()),
        Value::Bytes(public_key.to_vec()),
    ])
}

/// What a device signs for a step-up: `["wyrm-device-confirm/1", site, origin, user,
/// device, nonce, request]` with `request` the 32-byte hash the `confirm_required` refusal
/// named.
pub fn confirm_message(
    site: &str,
    origin: &str,
    user: &str,
    device: &str,
    nonce: &[u8],
    request: &[u8],
) -> Vec<u8> {
    array(vec![
        Value::from(CONFIRM_LABEL),
        Value::from(site),
        Value::from(origin),
        Value::from(user),
        Value::from(device),
        Value::Bytes(nonce.to_vec()),
        Value::Bytes(request.to_vec()),
    ])
}

/// The hash a step-up names: SHA-256 of the canonical CBOR of the refused request.
pub fn request_hash(request: &Value) -> [u8; 32] {
    Sha256::digest(wyrm_core::codec::to_vec(request).unwrap_or_default()).into()
}

/// `first 16 bytes of SHA-256(DER)` in lower-case hex: the code a person compares on the
/// Trust screen (`ca_fp`, the `fp` TXT key, `wyrmd ca fingerprint`).
pub fn ca_fingerprint(der: &[u8]) -> String {
    hex(&Sha256::digest(der)[..16])
}

/// [`ca_fingerprint`] in 8 groups of 4, as people read it.
pub fn grouped(fp: &str) -> String {
    fp.as_bytes()
        .chunks(4)
        .map(|c| String::from_utf8_lossy(c).into_owned())
        .collect::<Vec<_>>()
        .join(" ")
}

pub(crate) fn hex(b: &[u8]) -> String {
    b.iter().map(|x| format!("{x:02x}")).collect()
}

fn map<const N: usize>(fields: [(&str, Value); N]) -> Value {
    Value::Map(fields.into_iter().map(|(k, v)| (k.to_owned(), v)).collect())
}

/// Why the gateway refused a device request.
#[derive(Debug, Clone, PartialEq)]
pub(crate) enum Refused {
    /// The same answer for an unknown device, a bad signature, a foreign origin and an
    /// unknown, used or old nonce (counted by the login limiter).
    Bare,
    /// A known device with a good signature that may not log in (`device_removed`,
    /// `password_changed`, `password_due`, `devices_off`), or another refusal a client acts
    /// on (`password_required`, `too_many_devices`, `bad_password`).
    Code(&'static str),
    /// `confirm_required`: the client signs `nonce` and `request` (or asks for the
    /// password) and sends the request again. No `nonce` for a session that cannot confirm
    /// (an MCP token).
    ConfirmRequired {
        nonce: Option<[u8; 32]>,
        request: [u8; 32],
    },
    RateLimited,
    Busy,
    Bad(String),
    NotFound,
}

/// The live challenges: nonce → what it may be used for.
#[derive(Default)]
pub(crate) struct Challenges(Mutex<HashMap<[u8; 32], Challenge>>);

#[derive(Debug, Clone, PartialEq)]
pub(crate) enum Purpose {
    Login { device: String },
    Register { user: String, jti: [u8; 16] },
    Confirm { user: String, jti: [u8; 16] },
}

impl Purpose {
    /// What the per-key bound counts.
    fn key(&self) -> String {
        match self {
            Purpose::Login { device } => format!("d:{device}"),
            Purpose::Register { jti, .. } | Purpose::Confirm { jti, .. } => {
                format!("s:{}", hex(jti))
            }
        }
    }
}

pub(crate) struct Challenge {
    purpose: Purpose,
    exp: u64,
}

impl Challenges {
    fn lock(&self) -> std::sync::MutexGuard<'_, HashMap<[u8; 32], Challenge>> {
        self.0.lock().unwrap_or_else(|p| p.into_inner())
    }

    /// A new nonce for `purpose`; `None` when the table is full of live ones.
    pub(crate) fn issue(&self, purpose: Purpose, now: u64) -> Option<([u8; 32], u64)> {
        let mut nonce = [0u8; 32];
        getrandom::fill(&mut nonce).ok()?;
        let mut m = self.lock();
        m.retain(|_, c| c.exp > now);
        let key = purpose.key();
        let mut mine: Vec<(u64, [u8; 32])> = m
            .iter()
            .filter(|(_, c)| c.purpose.key() == key)
            .map(|(n, c)| (c.exp, *n))
            .collect();
        if mine.len() >= CHALLENGES_PER_KEY {
            mine.sort();
            for (_, n) in &mine[..=mine.len() - CHALLENGES_PER_KEY] {
                m.remove(n);
            }
        }
        if m.len() >= MAX_CHALLENGES {
            return None;
        }
        let exp = now + CHALLENGE_TTL_S;
        m.insert(nonce, Challenge { purpose, exp });
        Some((nonce, exp))
    }

    /// Spend `nonce`: what it was for, if it is live. It is gone after this call either way.
    pub(crate) fn take(&self, nonce: &[u8], now: u64) -> Option<Purpose> {
        let n: [u8; 32] = nonce.try_into().ok()?;
        let c = self.lock().remove(&n)?;
        (c.exp > now).then_some(c.purpose)
    }
}

/// What a session proved after its login: a step-up, the password again. In memory: a
/// restart asks again.
#[derive(Default)]
pub(crate) struct Fresh(Mutex<HashMap<[u8; 16], Proved>>);

#[derive(Clone, Copy, Default)]
struct Proved {
    confirmed_at: u64,
    password_at: u64,
}

impl Fresh {
    fn lock(&self) -> std::sync::MutexGuard<'_, HashMap<[u8; 16], Proved>> {
        self.0.lock().unwrap_or_else(|p| p.into_inner())
    }

    fn note(&self, jti: [u8; 16], now: u64, password: bool) {
        let mut m = self.lock();
        if !m.contains_key(&jti) && m.len() >= MAX_FRESH {
            m.retain(|_, p| now.saturating_sub(p.confirmed_at) < FRESH_S);
            if m.len() >= MAX_FRESH {
                return; // the session asks again; nothing is given away
            }
        }
        let p = m.entry(jti).or_default();
        p.confirmed_at = now;
        if password {
            p.password_at = now;
        }
    }

    fn get(&self, jti: &[u8; 16]) -> Proved {
        self.lock().get(jti).copied().unwrap_or_default()
    }
}

/// An origin as `(scheme, host, port)`, host in lower case, IPv6 without brackets.
pub fn parse_origin(s: &str) -> Option<(String, String, u16)> {
    let (scheme, rest) = s.split_once("://")?;
    let scheme = scheme.to_ascii_lowercase();
    let default = match scheme.as_str() {
        "https" => 443,
        "http" => 80,
        _ => return None,
    };
    if rest.is_empty() || rest.contains(['/', '?', '#', '@']) {
        return None;
    }
    let (host, port) = if let Some(v6) = rest.strip_prefix('[') {
        let (h, after) = v6.split_once(']')?;
        let port = match after {
            "" => default,
            p => p.strip_prefix(':')?.parse().ok()?,
        };
        (h.to_owned(), port)
    } else {
        match rest.rsplit_once(':') {
            Some((h, p)) => (h.to_owned(), p.parse().ok()?),
            None => (rest.to_owned(), default),
        }
    };
    if host.is_empty() {
        return None;
    }
    Some((scheme, host.to_ascii_lowercase(), port))
}

/// The names of a certificate (its DNS and IP subject alternative names, lower case), the
/// default origins of device keys.
pub(crate) fn cert_names(pem: &[u8]) -> Vec<String> {
    use rustls_pki_types::pem::PemObject;
    let Some(Ok(der)) = rustls_pki_types::CertificateDer::pem_slice_iter(pem).next() else {
        return Vec::new();
    };
    let Ok((_, cert)) = x509_parser::parse_x509_certificate(&der) else {
        return Vec::new();
    };
    let Ok(Some(san)) = cert.subject_alternative_name() else {
        return Vec::new();
    };
    san.value
        .general_names
        .iter()
        .filter_map(|n| match n {
            x509_parser::extensions::GeneralName::DNSName(d) => Some(d.to_ascii_lowercase()),
            x509_parser::extensions::GeneralName::IPAddress(b) => match b.len() {
                4 => Some(IpAddr::from(<[u8; 4]>::try_from(*b).ok()?).to_string()),
                16 => Some(IpAddr::from(<[u8; 16]>::try_from(*b).ok()?).to_string()),
                _ => None,
            },
            _ => None,
        })
        .collect()
}

/// `host` matches a certificate name, `*.example.com` covering one label.
fn name_matches(name: &str, host: &str) -> bool {
    match name.strip_prefix("*.") {
        Some(base) => host
            .split_once('.')
            .is_some_and(|(label, rest)| !label.is_empty() && rest == base),
        None => name == host,
    }
}

impl Gateway {
    pub fn device_policy(&self) -> &DevicePolicy {
        &self.cfg.devices
    }

    /// May a device sign for `origin` on this gateway (see [`DevicePolicy::origins`]).
    pub(crate) fn origin_allowed(&self, origin: &str) -> bool {
        let Some(o) = parse_origin(origin) else {
            return false;
        };
        if !self.cfg.devices.origins.is_empty() {
            return self
                .cfg
                .devices
                .origins
                .iter()
                .filter_map(|a| parse_origin(a))
                .any(|a| a == o);
        }
        let Some(port) = self.bound_addr().map(|a| a.port()) else {
            return false;
        };
        let (scheme, host, p) = o;
        if p != port {
            return false;
        }
        if self.cfg.tls.is_some() {
            scheme == "https" && self.cert_names.iter().any(|n| name_matches(n, &host))
        } else {
            scheme == "http" && matches!(host.as_str(), "127.0.0.1" | "localhost" | "::1")
        }
    }

    /// The session proved who the person is in the last [`FRESH_S`]: its login (password or
    /// device), a step-up, or the password again. An MCP token never has.
    pub(crate) fn confirmed(&self, p: &Principal) -> bool {
        if p.claims.amr == Amr::OAuth {
            return false;
        }
        let (now, fresh) = (session::now_s(), self.cfg.devices.fresh_s);
        now.saturating_sub(p.claims.auth_at) < fresh
            || now.saturating_sub(self.fresh.get(&p.claims.jti).confirmed_at) < fresh
    }

    /// The session checked the password in the last [`FRESH_S`] (to register a device).
    pub(crate) fn password_fresh(&self, p: &Principal) -> bool {
        let (now, fresh) = (session::now_s(), self.cfg.devices.fresh_s);
        (p.claims.amr == Amr::Password && now.saturating_sub(p.claims.auth_at) < fresh)
            || now.saturating_sub(self.fresh.get(&p.claims.jti).password_at) < fresh
    }

    /// `Ok` when `p` may send a request at `config` level now; else the refusal that tells
    /// the client what to sign. `request` is the refused request (its hash travels).
    pub(crate) fn step_up(&self, p: &Principal, request: &Value) -> Result<(), Refused> {
        if self.cfg.devices.step_up == StepUp::None || self.confirmed(p) {
            return Ok(());
        }
        let nonce = (p.claims.amr != Amr::OAuth)
            .then(|| {
                self.challenges.issue(
                    Purpose::Confirm {
                        user: p.name.clone(),
                        jti: p.claims.jti,
                    },
                    session::now_s(),
                )
            })
            .flatten()
            .map(|(n, _)| n);
        Err(Refused::ConfirmRequired {
            nonce,
            request: request_hash(request),
        })
    }

    pub(crate) fn step_up_on(&self) -> bool {
        self.cfg.devices.step_up == StepUp::Config
    }

    /// `POST /api/device/challenge`: a login nonce for `device` (whether or not it exists),
    /// or with a session a nonce to register or confirm.
    pub(crate) fn device_challenge(
        &self,
        purpose: Purpose,
        ip: IpAddr,
    ) -> Result<([u8; 32], u64), Refused> {
        if !self.challenge_limit.allowed(ip) {
            return Err(Refused::RateLimited);
        }
        self.challenges
            .issue(purpose, session::now_s())
            .ok_or(Refused::Busy)
    }

    /// A bare refusal of a device request, counted against `(device, ip)` and audited.
    fn bare(&self, device: &str, user: Option<&str>, ip: IpAddr, why: &'static str) -> Refused {
        self.limiter.failed(&limit_key(device), ip);
        self.audit(AuditEvent::DeviceRefused {
            user: user.map(str::to_owned),
            device: device.to_owned(),
            ip,
            code: why,
        });
        Refused::Bare
    }

    fn device_limited(&self, device: &str, ip: IpAddr) -> Result<(), Refused> {
        if self.limiter.allowed(&limit_key(device), ip) {
            return Ok(());
        }
        if self.limiter.note_refusal(&limit_key(device), ip) {
            self.audit(AuditEvent::DeviceRefused {
                user: None,
                device: device.to_owned(),
                ip,
                code: "rate_limited",
            });
        }
        Err(Refused::RateLimited)
    }

    fn device(&self, id: &str) -> Option<Device> {
        self.store().state().devices.get(id).cloned()
    }

    pub(crate) fn devices_owner(&self, id: &str) -> Option<String> {
        self.store().state().devices.get(id).map(|d| d.user.clone())
    }

    /// `POST /api/devices`: register a key of `p`'s device. The key signs a `register`
    /// challenge of this session, so it is a valid key the device holds.
    #[allow(clippy::too_many_arguments)]
    pub(crate) fn register_device(
        &self,
        p: &Principal,
        name: &str,
        platform: &str,
        alg: &str,
        public_key: &[u8],
        attestation: Option<Vec<u8>>,
        origin: &str,
        nonce: &[u8],
        signature: &[u8],
        ip: IpAddr,
    ) -> Result<String, Refused> {
        if p.claims.amr == Amr::OAuth {
            return Err(Refused::Code("password_required"));
        }
        if !self.cfg.devices.enabled {
            return Err(Refused::Code("devices_off"));
        }
        if !self.password_fresh(p) {
            return Err(Refused::Code("password_required"));
        }
        if name.trim().is_empty() || name.len() > MAX_NAME || name.chars().any(char::is_control) {
            return Err(Refused::Bad("name: 1 to 64 bytes of text".into()));
        }
        if !PLATFORMS.contains(&platform) {
            return Err(Refused::Bad(format!(
                "platform: one of {}",
                PLATFORMS.join(", ")
            )));
        }
        let alg = KeyAlg::of(alg).ok_or_else(|| Refused::Bad("alg: es256 or rs256".into()))?;
        let key = alg.normalize(public_key).map_err(Refused::Bad)?;
        if attestation
            .as_ref()
            .is_some_and(|a| a.len() > MAX_ATTESTATION)
        {
            return Err(Refused::Bad("attestation: larger than 16 KiB".into()));
        }
        let now = session::now_s();
        let ours = Purpose::Register {
            user: p.name.clone(),
            jti: p.claims.jti,
        };
        let msg = register_message(&self.cfg.site, origin, &p.name, nonce, public_key);
        if self.challenges.take(nonce, now) != Some(ours)
            || !self.origin_allowed(origin)
            || !alg.verify(&key, &msg, signature)
        {
            return Err(self.bare("(new)", Some(&p.name), ip, "bad_registration"));
        }
        let mut raw = [0u8; 16];
        getrandom::fill(&mut raw).map_err(|_| Refused::Busy)?;
        let id = hex(&raw);
        {
            let mut store = self.store();
            let db = store.state();
            let active = db
                .devices
                .values()
                .filter(|d| d.user == p.name && db.device_active(d))
                .count();
            if active >= self.cfg.devices.max_per_user {
                return Err(Refused::Code("too_many_devices"));
            }
            store
                .apply(Op::AddDevice {
                    id: id.clone(),
                    user: p.name.clone(),
                    name: name.to_owned(),
                    platform: platform.to_owned(),
                    alg: alg.name().to_owned(),
                    public_key: key,
                    attestation,
                    at: now,
                })
                .map_err(|e| Refused::Bad(e.to_string()))?;
        }
        self.audit(AuditEvent::DeviceAdded {
            user: p.name.clone(),
            device: id.clone(),
            name: name.to_owned(),
            platform: platform.to_owned(),
            ip,
        });
        Ok(id)
    }

    /// `POST /api/device/login`. Order: limiter, nonce (spent), record, origin and
    /// signature, then the coded refusals; a good login mints the claims a password login
    /// would (same roles, same generation), with `amr: dev`.
    #[allow(clippy::too_many_arguments)]
    pub(crate) fn device_login(
        &self,
        device: &str,
        origin: &str,
        nonce: &[u8],
        signature: &[u8],
        keep: Option<&str>,
        ip: IpAddr,
    ) -> Result<(String, u64), Refused> {
        self.device_limited(device, ip)?;
        let now = session::now_s();
        let ours = Purpose::Login {
            device: device.to_owned(),
        };
        if self.challenges.take(nonce, now) != Some(ours) {
            return Err(self.bare(device, None, ip, "bad_nonce"));
        }
        let Some(d) = self.device(device) else {
            return Err(self.bare(device, None, ip, "unknown_device"));
        };
        let alg = KeyAlg::of(&d.alg);
        let msg = login_message(&self.cfg.site, origin, &d.user, device, nonce);
        if !self.origin_allowed(origin)
            || !alg.is_some_and(|a| a.verify(&d.public_key, &msg, signature))
        {
            return Err(self.bare(device, Some(&d.user), ip, "bad_signature"));
        }
        // a good signature from a known key: the refusals that say why
        let user = self.user(&d.user);
        let code = if !self.cfg.devices.enabled {
            Some("devices_off")
        } else if d.removed.is_some() {
            Some("device_removed")
        } else if user
            .as_ref()
            .is_none_or(|u| u.disabled || u.gen != d.user_gen)
        {
            Some("password_changed")
        } else if now.saturating_sub(d.password_at)
            > self.cfg.devices.password_every_days.saturating_mul(86_400)
        {
            Some("password_due")
        } else {
            None
        };
        if let Some(code) = code {
            self.audit(AuditEvent::DeviceRefused {
                user: Some(d.user.clone()),
                device: device.to_owned(),
                ip,
                code,
            });
            return Err(Refused::Code(code));
        }
        let u = user.expect("checked above");
        self.limiter.succeeded(&limit_key(device), ip);
        self.store()
            .apply(Op::DeviceUsed {
                id: device.to_owned(),
                at: now,
            })
            .map_err(|e| Refused::Bad(e.to_string()))?;
        self.audit(AuditEvent::DeviceLogin {
            user: d.user.clone(),
            device: device.to_owned(),
            ip,
        });
        // the idle lock: the session stays, now confirmed
        if let Some(p) = keep.and_then(|t| self.authenticate(t)) {
            if p.name == d.user {
                self.fresh.note(p.claims.jti, now, false);
                return Ok((keep.unwrap_or_default().to_owned(), p.claims.exp));
            }
        }
        let exp = now + self.cfg.session_ttl.as_secs().max(1);
        let claims = SessionClaims {
            sub: d.user.clone(),
            roles: u.roles,
            exp,
            iat: now,
            jti: session::new_jti(),
            gen: u.gen,
            amr: Amr::Device,
            auth_at: now,
            dev: Some(device.to_owned()),
        };
        Ok((self.session_key.mint(&claims), exp))
    }

    /// `POST /api/device/confirm`: a step-up of `p`'s session with one of `p`'s devices.
    #[allow(clippy::too_many_arguments)]
    pub(crate) fn confirm_device(
        &self,
        p: &Principal,
        device: &str,
        origin: &str,
        nonce: &[u8],
        request: &[u8],
        signature: &[u8],
        ip: IpAddr,
    ) -> Result<(), Refused> {
        self.device_limited(device, ip)?;
        let now = session::now_s();
        let ours = Purpose::Confirm {
            user: p.name.clone(),
            jti: p.claims.jti,
        };
        if p.claims.amr == Amr::OAuth
            || request.len() != 32
            || self.challenges.take(nonce, now) != Some(ours)
        {
            return Err(self.bare(device, Some(&p.name), ip, "bad_nonce"));
        }
        let d = match self.device(device) {
            Some(d) if d.user == p.name => d,
            _ => return Err(self.bare(device, Some(&p.name), ip, "unknown_device")),
        };
        let msg = confirm_message(&self.cfg.site, origin, &p.name, device, nonce, request);
        if !self.origin_allowed(origin)
            || !KeyAlg::of(&d.alg).is_some_and(|a| a.verify(&d.public_key, &msg, signature))
        {
            return Err(self.bare(device, Some(&p.name), ip, "bad_signature"));
        }
        if !self.cfg.devices.enabled {
            return Err(Refused::Code("devices_off"));
        }
        if !self.store().state().device_active(&d) {
            return Err(Refused::Code(if d.removed.is_some() {
                "device_removed"
            } else {
                "password_changed"
            }));
        }
        self.limiter.succeeded(&limit_key(device), ip);
        self.fresh.note(p.claims.jti, now, false);
        self.audit(AuditEvent::StepUp {
            user: p.name.clone(),
            method: "device",
            request: hex(request),
        });
        Ok(())
    }

    /// `POST /api/confirm {password}`: a step-up with the password, which also lets the
    /// session register a device for [`FRESH_S`]. On a blocking thread (argon2).
    pub(crate) fn confirm_password(
        &self,
        p: &Principal,
        password: Zeroizing<String>,
        ip: IpAddr,
    ) -> Result<(), Refused> {
        if p.claims.amr == Amr::OAuth {
            return Err(Refused::Code("password_required"));
        }
        self.check_limit(&p.name, ip)
            .map_err(|_| Refused::RateLimited)?;
        if self.verify_login(&p.name, password, ip).is_err() {
            return Err(Refused::Code("bad_password"));
        }
        self.fresh.note(p.claims.jti, session::now_s(), true);
        self.audit(AuditEvent::StepUp {
            user: p.name.clone(),
            method: "password",
            request: String::new(),
        });
        Ok(())
    }

    /// The device records of `user`, as `GET /api/devices` shows them; `this` marks the
    /// caller's own device.
    pub fn devices_of(&self, user: &str, this: Option<&str>) -> Vec<Value> {
        let store = self.store();
        let db = store.state();
        let every = self.cfg.devices.password_every_days.saturating_mul(86_400);
        db.devices
            .iter()
            .filter(|(_, d)| d.user == user)
            .map(|(id, d)| {
                let state = if d.removed.is_some() {
                    "removed"
                } else if db.device_active(d) {
                    "active"
                } else {
                    "signed_out"
                };
                let mut m = vec![
                    ("id", Value::from(id.as_str())),
                    ("name", Value::from(d.name.as_str())),
                    ("platform", Value::from(d.platform.as_str())),
                    ("alg", Value::from(d.alg.as_str())),
                    ("added", Value::UInt(d.added)),
                    ("last_used", Value::UInt(d.last_used)),
                    ("password_at", Value::UInt(d.password_at)),
                    ("password_due_at", Value::UInt(d.password_at + every)),
                    ("state", Value::from(state)),
                    ("this", Value::Bool(this == Some(id.as_str()))),
                ];
                if let Some((by, at)) = &d.removed {
                    m.push(("removed_by", Value::from(by.as_str())));
                    m.push(("removed_at", Value::UInt(*at)));
                }
                Value::Map(m.into_iter().map(|(k, v)| (k.to_owned(), v)).collect())
            })
            .collect()
    }

    /// Devices of `user` that can log in now.
    pub fn active_devices(&self, user: &str) -> usize {
        let store = self.store();
        let db = store.state();
        db.devices
            .values()
            .filter(|d| d.user == user && db.device_active(d))
            .count()
    }

    /// `DELETE /api/devices/{id}` by `by`: its owner (or anyone on a tombstone) forgets the
    /// record; an admin removing another user's device leaves a tombstone that names them.
    /// Either way the device's sessions end. `NotFound` for a device `by` may not see.
    pub(crate) fn remove_device(&self, by: &Principal, id: &str) -> Result<(), Refused> {
        let d = self.device(id).ok_or(Refused::NotFound)?;
        let own = d.user == by.name;
        if !own && !self.is_admin(by) {
            return Err(Refused::NotFound);
        }
        let op = if own || d.removed.is_some() {
            Op::ForgetDevice(id.to_owned())
        } else {
            Op::RemoveDevice {
                id: id.to_owned(),
                by: format!("user:{}", by.name),
                at: session::now_s(),
            }
        };
        self.store()
            .apply(op)
            .map_err(|e| Refused::Bad(e.to_string()))?;
        self.audit(AuditEvent::DeviceRemoved {
            user: d.user,
            device: id.to_owned(),
            by: format!("user:{}", by.name),
        });
        Ok(())
    }

    /// Sign out everywhere (`POST /api/me/sign-out`): every session of the user ends and
    /// every device is signed out.
    pub fn end_sessions(&self, user: &str) -> crate::Result<()> {
        self.store().apply(Op::EndSessions(user.to_owned()))?;
        Ok(())
    }

    /// A password login that names its device: the device saw the password now.
    pub(crate) fn password_seen(&self, user: &str, device: &str) {
        let mut store = self.store();
        let ok = store
            .state()
            .devices
            .get(device)
            .is_some_and(|d| d.user == user && d.removed.is_none());
        if ok {
            let _ = store.apply(Op::DevicePassword {
                id: device.to_owned(),
                at: session::now_s(),
            });
        }
    }
}

fn limit_key(device: &str) -> String {
    format!("device:{device}")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn origins_parse() {
        assert_eq!(
            parse_origin("https://Broker.Example:8443"),
            Some(("https".into(), "broker.example".into(), 8443))
        );
        assert_eq!(
            parse_origin("https://broker.example"),
            Some(("https".into(), "broker.example".into(), 443))
        );
        assert_eq!(
            parse_origin("http://[::1]:8080"),
            Some(("http".into(), "::1".into(), 8080))
        );
        for bad in [
            "broker.example",
            "ftp://x",
            "https://x/path",
            "https://user@x",
            "https://:1",
            "https://x:port",
        ] {
            assert_eq!(parse_origin(bad), None, "{bad}");
        }
        assert!(name_matches("*.plant.example", "gw.plant.example"));
        assert!(!name_matches("*.plant.example", "a.gw.plant.example"));
        assert!(!name_matches("*.plant.example", "plant.example"));
    }

    #[test]
    fn challenges_are_single_use_bounded_and_expire() {
        let c = Challenges::default();
        let login = || Purpose::Login {
            device: "d1".into(),
        };
        let (n, exp) = c.issue(login(), 100).unwrap();
        assert_eq!(exp, 100 + CHALLENGE_TTL_S);
        assert_eq!(c.take(&n, 101), Some(login()));
        assert_eq!(c.take(&n, 101), None, "single use");
        let (old, _) = c.issue(login(), 100).unwrap();
        assert_eq!(c.take(&old, 100 + CHALLENGE_TTL_S), None, "expired");
        let first = c.issue(login(), 200).unwrap().0;
        for _ in 0..CHALLENGES_PER_KEY {
            c.issue(login(), 201).unwrap();
        }
        assert_eq!(c.take(&first, 202), None, "the oldest of a device goes");
        assert_eq!(c.take(&[0; 5], 202), None, "not a nonce");
    }

    #[test]
    fn messages_are_canonical_cbor_arrays() {
        // the vector Studio's encoder is checked against (docs/broker.md, device keys)
        let m = login_message("plant", "https://gw:8443", "olena", "d1", &[7; 4]);
        assert_eq!(
            hex(&m),
            "86737779726d2d6465766963652d6c6f67696e2f3165706c616e746f68747470733a2f2f67773a3834\
             3433656f6c656e616264314407070707"
        );
        assert_ne!(
            confirm_message("plant", "https://gw:8443", "olena", "d1", &[7; 4], &[1; 32]),
            m
        );
    }

    #[test]
    fn keys_normalize_and_verify() {
        use ring::rand::SystemRandom;
        use ring::signature::{EcdsaKeyPair, KeyPair, ECDSA_P256_SHA256_ASN1_SIGNING};
        let rng = SystemRandom::new();
        let pkcs8 = EcdsaKeyPair::generate_pkcs8(&ECDSA_P256_SHA256_ASN1_SIGNING, &rng).unwrap();
        let kp = EcdsaKeyPair::from_pkcs8(&ECDSA_P256_SHA256_ASN1_SIGNING, pkcs8.as_ref(), &rng)
            .unwrap();
        let point = kp.public_key().as_ref().to_vec();
        assert_eq!(KeyAlg::Es256.normalize(&point).unwrap(), point);
        // the SPKI DER Android exports
        let mut spki = vec![
            0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01, 0x06,
            0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03, 0x42, 0x00,
        ];
        spki.extend(&point);
        assert_eq!(KeyAlg::Es256.normalize(&spki).unwrap(), point);
        assert!(KeyAlg::Es256.normalize(&point[..64]).is_err());
        assert!(KeyAlg::Rs256.normalize(&[1, 2, 3]).is_err());
        let sig = kp.sign(&rng, b"hello").unwrap();
        assert!(KeyAlg::Es256.verify(&point, b"hello", sig.as_ref()));
        assert!(!KeyAlg::Es256.verify(&point, b"hellO", sig.as_ref()));
        assert!(!KeyAlg::Rs256.verify(&point, b"hello", sig.as_ref()));
    }

    #[test]
    fn fingerprints() {
        let fp = ca_fingerprint(b"der");
        assert_eq!(fp.len(), 32);
        assert_eq!(&fp, &hex(&Sha256::digest(b"der")[..16]));
        let g = grouped(&fp);
        assert_eq!(g.split(' ').count(), 8);
        assert!(g.split(' ').all(|p| p.len() == 4));
    }
}
