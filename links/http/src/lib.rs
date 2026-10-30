//! Generic HTTP/REST JSON poller on the driver framework (ADR 0004).
//!
//! Tree: `<conn>/<device>/<point>`. A connection ([`Conn`]) is a base URL
//! with its auth, TLS, default headers and rate limit; a device ([`Dev`])
//! is one request (method, path, query, JSON body, expected status); a
//! point ([`Point`]) is a selector into the JSON reply ([`select`], a
//! JSONPath subset) with a value type, an optional aggregate over several
//! matches, scaling and a unit. A point may be writable with a write
//! template (method, path, JSON body with `{{value}}`).
//!
//! The framework owns states, scheduling, edits and the quality ladder;
//! this driver only does protocol I/O:
//!
//! * the points of a device with the same `poll_s` form one group: one
//!   request per group and period feeds all of them (the framework groups
//!   by the point's period, so the period is a point param);
//! * a reply outside `expect_status` (401/403: "authentication failed"), a
//!   timeout, a body over `max_body_kib` or a body that is not JSON is a
//!   device miss (`DriverError::Device`); a selector that finds nothing, a
//!   value of the wrong type or several values without `aggregate` fail
//!   that point only (`DriverError::Point`); a refused connection, a TLS
//!   failure or a broken socket is `DriverError::Transport`;
//! * a write sends the template and succeeds on 2xx; the framework reads
//!   the point back (one request of the device);
//! * at most [`client::MAX_REDIRECTS`] redirects, to the same scheme, host
//!   and port only.
//!
//! Late replies: one request at a time per connection; a request that is
//! cut drops its connection ([`client`]).
//!
//! Commissioning actions on a device (level config): `try_request` (the
//! device's request now → status, headers, body up to 64 KiB, secrets
//! masked) and `test_selector {path, type?, aggregate?}` (a selector
//! against the last JSON reply of the device's request, no I/O).

#![forbid(unsafe_code)]

pub mod client;
pub mod select;
#[cfg(feature = "sim")]
pub mod sim;

use base64::Engine as _;
use bytes::Bytes;
use client::{check_chars, check_path, encode_query, Client, Fail, Origin, Prepared, Req};
use hyper::header::{HeaderName, HeaderValue};
use hyper::Method;
use select::Selector;
use serde_json::Value as Json;
use std::borrow::Cow;
use std::collections::{BTreeMap, VecDeque};
use std::sync::Arc;
use std::time::Duration;
use wyrm_core::meta::{ActionResult, ParamMeta, Writable};
use wyrm_core::{ActionMeta, NodeMeta, Perm, Status, TypeCode, Value};
use wyrm_link_sdk::driver::params::ParamSpec;
// Traits (type namespace) beside the derive macros of the same name.
use wyrm_link_sdk::driver::{
    Driver, DriverError, Framework, Level, Outcome, ParamEnum, Params, PointId, Target,
};
use wyrm_link_sdk::LinkError;
use wyrm_link_sdk::{ParamEnum, Params};

/// The `http` link: the framework running [`HttpDriver`].
pub type Http = Framework<HttpDriver>;

fn bad(name: &str, what: impl std::fmt::Display) -> LinkError {
    LinkError::invalid_parameter(format!("{name}: {what}"))
}

// ---------- connection ----------

#[derive(Debug, Clone, Copy, PartialEq, Eq, ParamEnum)]
pub enum Auth {
    None,
    /// `Authorization: Basic` with `username` and `password`.
    Basic,
    /// `Authorization: Bearer <token>`.
    Bearer,
    /// `token` in the header or query parameter `api_key_name`.
    ApiKey,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, ParamEnum)]
pub enum KeyIn {
    Header,
    Query,
}

/// The connection's params as entered. No `Debug`: it holds secrets.
#[derive(Clone, PartialEq, Params)]
pub struct ConnParams {
    #[param(
        display = "Base URL",
        placeholder = "https://10.0.1.20:8443/api",
        desc = "http:// or https://, host, port and a path prefix; no user, query or fragment",
        dest
    )]
    pub base_url: String,
    /// Bound on connecting and on each request (reply and body).
    #[param(default = 5000, min = 100, max = 60000, display = "Timeout (ms)")]
    pub timeout_ms: u32,
    #[param(enum, default = "none", display = "Authentication", dest)]
    pub auth: Auth,
    #[param(default = "", display = "Username", desc = "auth basic")]
    pub username: String,
    #[param(default = "", secret, display = "Password", desc = "auth basic")]
    pub password: String,
    #[param(
        default = "",
        secret,
        display = "Token",
        desc = "auth bearer: the token; auth api_key: the key"
    )]
    pub token: String,
    #[param(enum, default = "header", display = "API Key In", dest)]
    pub api_key_in: KeyIn,
    #[param(default = "X-API-Key", display = "API Key Name", dest)]
    pub api_key_name: String,
    #[param(
        default = "",
        editor = "textarea",
        display = "CA Certificates (PEM)",
        desc = "https: trust these CAs only; empty = the CA certificates of the host",
        dest
    )]
    pub ca_pem: String,
    #[param(
        default = "",
        editor = "textarea",
        display = "Client Certificate (PEM)",
        desc = "https: client certificate chain for mTLS"
    )]
    pub cert_pem: String,
    #[param(
        default = "",
        secret,
        display = "Client Key (PEM)",
        desc = "private key of the client certificate"
    )]
    pub key_pem: String,
    #[param(
        default = false,
        display = "Skip Certificate Check",
        desc = "https: accept any server certificate (insecure)",
        dest
    )]
    pub insecure_skip_verify: bool,
    #[param(
        default = false,
        display = "Allow Credentials over HTTP",
        desc = "send credentials over http:// to a host that is not loopback (insecure)",
        dest
    )]
    pub insecure_plaintext: bool,
    #[param(
        default = "",
        editor = "textarea",
        display = "Headers",
        placeholder = "Accept-Language: en",
        desc = "one 'Name: value' per line, sent with every request; not secret: no credentials"
    )]
    pub headers: String,
    #[param(
        default = "",
        display = "Secret Header Name",
        placeholder = "X-Api-Secret",
        desc = "one more credential header, sent with every request",
        dest
    )]
    pub secret_header_name: String,
    #[param(
        default = "",
        secret,
        display = "Secret Header Value",
        desc = "the value of secret_header_name"
    )]
    pub secret_header_value: String,
    #[param(
        default = 5.0,
        min = 0.1,
        max = 1000.0,
        display = "Rate Limit (requests/s)"
    )]
    pub rate_limit: f64,
    #[param(
        default = 4096,
        min = 1,
        max = 65536,
        display = "Max Body (KiB)",
        desc = "a longer reply is a device error"
    )]
    pub max_body_kib: u32,
}

/// A connection: its params and what every request carries.
#[derive(Clone)]
pub struct Conn {
    pub params: ConnParams,
    prep: Arc<Prepared>,
}

impl PartialEq for Conn {
    fn eq(&self, o: &Self) -> bool {
        self.params == o.params
    }
}

impl std::fmt::Debug for Conn {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Conn")
            .field("base_url", &self.params.base_url)
            .field("auth", &self.params.auth)
            .finish_non_exhaustive()
    }
}

/// Headers a `headers` line may not set: framing, and credentials (they
/// belong in secret params).
const FORBIDDEN_HEADERS: &[&str] = &[
    "host",
    "content-length",
    "transfer-encoding",
    "connection",
    "upgrade",
    "te",
    "trailer",
    "keep-alive",
    "authorization",
    "proxy-authorization",
    "cookie",
];

const MAX_HEADERS: usize = 32;

/// Parts of header names that carry credentials: refused in the
/// non-secret `headers` (shown in `~meta` and `export`, never masked).
const CREDENTIAL_PARTS: &[&str] = &[
    "auth",
    "token",
    "key",
    "secret",
    "session",
    "cookie",
    "password",
    "passwd",
    "credential",
];

fn credential_like(name: &HeaderName) -> bool {
    CREDENTIAL_PARTS.iter().any(|p| name.as_str().contains(p))
}

impl Params for Conn {
    fn schema() -> Vec<ParamSpec> {
        ConnParams::schema()
    }

    fn from_map(m: &BTreeMap<String, Value>) -> wyrm_link_sdk::Result<Self> {
        let params = ConnParams::from_map(m)?;
        let prep = Arc::new(prepare(&params)?);
        Ok(Conn { params, prep })
    }

    fn to_map(&self) -> BTreeMap<String, Value> {
        self.params.to_map()
    }
}

fn api_key_header(name: &str) -> wyrm_link_sdk::Result<HeaderName> {
    let h = HeaderName::from_bytes(name.as_bytes())
        .map_err(|_| bad("api_key_name", "not a header name"))?;
    if FORBIDDEN_HEADERS.contains(&h.as_str()) && h != hyper::header::AUTHORIZATION {
        return Err(bad("api_key_name", "not this header"));
    }
    Ok(h)
}

fn sensitive(v: String, param: &str) -> wyrm_link_sdk::Result<HeaderValue> {
    // Never echo the value in the error.
    let mut h = HeaderValue::from_str(&v).map_err(|_| bad(param, "not a valid header value"))?;
    h.set_sensitive(true);
    Ok(h)
}

/// Check the cross-field rules and build what every request carries.
fn prepare(p: &ConnParams) -> wyrm_link_sdk::Result<Prepared> {
    let origin = Origin::parse(&p.base_url).map_err(|e| bad("base_url", e))?;
    if !origin.tls && (!p.ca_pem.is_empty() || !p.cert_pem.is_empty() || p.insecure_skip_verify) {
        return Err(bad(
            "ca_pem",
            "ca_pem, cert_pem and insecure_skip_verify only with https://",
        ));
    }
    let key_header = match (p.auth, p.api_key_in) {
        (Auth::ApiKey, KeyIn::Header) => Some(api_key_header(p.api_key_name.trim())?),
        _ => None,
    };
    // Never echo the value in an error.
    let secret_header = match p.secret_header_name.trim() {
        "" if p.secret_header_value.is_empty() => None,
        "" => {
            return Err(bad(
                "secret_header_name",
                "required with secret_header_value",
            ))
        }
        n => {
            let name = HeaderName::from_bytes(n.as_bytes())
                .map_err(|_| bad("secret_header_name", "not a header name"))?;
            let auth_sets = key_header.as_ref() == Some(&name)
                || (name == hyper::header::AUTHORIZATION
                    && matches!(p.auth, Auth::Basic | Auth::Bearer));
            if auth_sets
                || (FORBIDDEN_HEADERS.contains(&name.as_str())
                    && name != hyper::header::AUTHORIZATION)
            {
                return Err(bad("secret_header_name", format!("not {name}")));
            }
            if p.secret_header_value.is_empty() {
                return Err(bad(
                    "secret_header_value",
                    "required with secret_header_name",
                ));
            }
            Some((
                name,
                sensitive(p.secret_header_value.clone(), "secret_header_value")?,
            ))
        }
    };
    let creds = p.auth != Auth::None || secret_header.is_some();
    if creds && !origin.tls && !origin.is_loopback() && !p.insecure_plaintext {
        return Err(bad(
            "base_url",
            "credentials are never sent over http:// to a host that is not loopback \
             (use https://, or set insecure_plaintext)",
        ));
    }
    let mut headers = Vec::new();
    let mut lines = 0;
    if p.headers.len() > 8192 {
        return Err(bad("headers", "longer than 8 KiB"));
    }
    for (n, line) in p.headers.lines().enumerate() {
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        lines += 1;
        if lines > MAX_HEADERS {
            return Err(bad("headers", format!("more than {MAX_HEADERS} headers")));
        }
        let (k, v) = line
            .split_once(':')
            .ok_or_else(|| bad("headers", format!("line {}: expected 'Name: value'", n + 1)))?;
        let name = HeaderName::from_bytes(k.trim().as_bytes())
            .map_err(|_| bad("headers", format!("line {}: not a header name", n + 1)))?;
        if FORBIDDEN_HEADERS.contains(&name.as_str()) || key_header.as_ref() == Some(&name) {
            return Err(bad(
                "headers",
                format!(
                    "line {}: {} is not allowed here (credentials go in auth)",
                    n + 1,
                    name
                ),
            ));
        }
        if credential_like(&name) || secret_header.as_ref().is_some_and(|(h, _)| *h == name) {
            return Err(bad(
                "headers",
                format!(
                    "line {}: {name} looks like a credential: headers are not secret \
                     (use auth, or secret_header_name and secret_header_value)",
                    n + 1
                ),
            ));
        }
        let value = HeaderValue::from_str(v.trim())
            .map_err(|_| bad("headers", format!("line {}: not a header value", n + 1)))?;
        headers.push((name, value));
    }
    let mut masks = Vec::new();
    let mut mask = |s: &str| {
        if s.len() >= 3 {
            masks.push(s.to_owned());
        }
    };
    let mut query_key = None;
    match p.auth {
        Auth::None => {}
        Auth::Basic => {
            if p.username.is_empty() {
                return Err(bad("username", "required with auth basic"));
            }
            if p.username.contains(':') {
                return Err(bad("username", "no ':' in a basic auth user"));
            }
            let b64 = base64::engine::general_purpose::STANDARD
                .encode(format!("{}:{}", p.username, p.password));
            mask(&p.password);
            mask(&b64);
            headers.push((
                hyper::header::AUTHORIZATION,
                sensitive(format!("Basic {b64}"), "password")?,
            ));
        }
        Auth::Bearer => {
            if p.token.is_empty() {
                return Err(bad("token", "required with auth bearer"));
            }
            mask(&p.token);
            headers.push((
                hyper::header::AUTHORIZATION,
                sensitive(format!("Bearer {}", p.token), "token")?,
            ));
        }
        Auth::ApiKey => {
            if p.token.is_empty() {
                return Err(bad("token", "required with auth api_key"));
            }
            mask(&p.token);
            match key_header {
                Some(h) => headers.push((h, sensitive(p.token.clone(), "token")?)),
                None => {
                    let name = p.api_key_name.trim();
                    if name.is_empty()
                        || !name
                            .bytes()
                            .all(|b| b.is_ascii_alphanumeric() || b"-._~".contains(&b))
                    {
                        return Err(bad("api_key_name", "a query name: [A-Za-z0-9-._~]+"));
                    }
                    let enc = encode_query(&p.token);
                    mask(&enc);
                    query_key = Some((name.to_owned(), enc));
                }
            }
        }
    }
    if let Some((name, value)) = secret_header {
        mask(&p.secret_header_value);
        // `Bearer <token>`, `Token <key>`: an echo of the token alone too
        if let Some((_, rest)) = p.secret_header_value.trim().split_once(' ') {
            mask(rest.trim());
        }
        headers.push((name, value));
    }
    let tls = if origin.tls {
        Some(Arc::new(tls_config(p)?))
    } else {
        None
    };
    // Longest first: a password inside its own base64 never leaves part of
    // the base64 readable.
    masks.sort_by_key(|m| std::cmp::Reverse(m.len()));
    masks.dedup();
    let numbers = masks.iter().filter_map(|m| numeric(m)).collect();
    let note = if origin.tls && p.insecure_skip_verify {
        Some("the server certificate is not checked (insecure_skip_verify)".to_owned())
    } else if creds && !origin.tls && !origin.is_loopback() {
        Some("credentials are sent in plaintext (insecure_plaintext)".to_owned())
    } else {
        None
    };
    Ok(Prepared {
        origin,
        tls,
        headers,
        query_key,
        timeout: Duration::from_millis(p.timeout_ms.into()),
        interval: Duration::from_secs_f64(1.0 / p.rate_limit),
        max_body: usize::try_from(p.max_body_kib)
            .unwrap_or(usize::MAX)
            .saturating_mul(1024),
        masks,
        numbers,
        note,
    })
}

/// Accepts any server certificate but still checks the handshake
/// signatures (`insecure_skip_verify`).
#[derive(Debug)]
struct NoVerify(Arc<rustls::crypto::CryptoProvider>);

impl rustls::client::danger::ServerCertVerifier for NoVerify {
    fn verify_server_cert(
        &self,
        _end_entity: &rustls_pki_types::CertificateDer<'_>,
        _intermediates: &[rustls_pki_types::CertificateDer<'_>],
        _server_name: &rustls_pki_types::ServerName<'_>,
        _ocsp: &[u8],
        _now: rustls_pki_types::UnixTime,
    ) -> Result<rustls::client::danger::ServerCertVerified, rustls::Error> {
        Ok(rustls::client::danger::ServerCertVerified::assertion())
    }

    fn verify_tls12_signature(
        &self,
        message: &[u8],
        cert: &rustls_pki_types::CertificateDer<'_>,
        dss: &rustls::DigitallySignedStruct,
    ) -> Result<rustls::client::danger::HandshakeSignatureValid, rustls::Error> {
        rustls::crypto::verify_tls12_signature(
            message,
            cert,
            dss,
            &self.0.signature_verification_algorithms,
        )
    }

    fn verify_tls13_signature(
        &self,
        message: &[u8],
        cert: &rustls_pki_types::CertificateDer<'_>,
        dss: &rustls::DigitallySignedStruct,
    ) -> Result<rustls::client::danger::HandshakeSignatureValid, rustls::Error> {
        rustls::crypto::verify_tls13_signature(
            message,
            cert,
            dss,
            &self.0.signature_verification_algorithms,
        )
    }

    fn supported_verify_schemes(&self) -> Vec<rustls::SignatureScheme> {
        self.0.signature_verification_algorithms.supported_schemes()
    }
}

/// The host's CA certificates (`rustls-native-certs`), loaded once per
/// process (CAs the host adds later need a restart), and the first
/// error of the load, if any.
type Roots = (
    Vec<rustls_pki_types::CertificateDer<'static>>,
    Option<String>,
);

static SYSTEM_ROOTS: std::sync::LazyLock<Roots> = std::sync::LazyLock::new(|| {
    let r = rustls_native_certs::load_native_certs();
    (r.certs, r.errors.first().map(|e| e.to_string()))
});

fn tls_config(p: &ConnParams) -> wyrm_link_sdk::Result<rustls::ClientConfig> {
    use rustls_pki_types::pem::PemObject;
    use rustls_pki_types::{CertificateDer, PrivateKeyDer};
    // ring only: never the process default provider (aws-lc is forbidden).
    let provider = Arc::new(rustls::crypto::ring::default_provider());
    let b = rustls::ClientConfig::builder_with_provider(provider.clone())
        .with_safe_default_protocol_versions()
        .map_err(|e| bad("tls", e))?;
    let b = if p.insecure_skip_verify {
        if !p.ca_pem.is_empty() {
            return Err(bad(
                "ca_pem",
                "give ca_pem or insecure_skip_verify, not both",
            ));
        }
        b.dangerous()
            .with_custom_certificate_verifier(Arc::new(NoVerify(provider)))
    } else {
        let mut roots = rustls::RootCertStore::empty();
        if p.ca_pem.trim().is_empty() {
            let (certs, err) = &*SYSTEM_ROOTS;
            roots.add_parsable_certificates(certs.iter().cloned());
            if roots.is_empty() {
                let why = err
                    .as_deref()
                    .map(|e| format!(" ({e})"))
                    .unwrap_or_default();
                return Err(bad(
                    "ca_pem",
                    format!("no system CA certificates found{why}: give ca_pem"),
                ));
            }
        } else {
            for cert in CertificateDer::pem_slice_iter(p.ca_pem.as_bytes()) {
                let cert = cert.map_err(|e| bad("ca_pem", e))?;
                roots.add(cert).map_err(|e| bad("ca_pem", e))?;
            }
            if roots.is_empty() {
                return Err(bad("ca_pem", "no certificate"));
            }
        }
        b.with_root_certificates(roots)
    };
    let mut cfg = if p.cert_pem.trim().is_empty() {
        b.with_no_client_auth()
    } else {
        let chain = CertificateDer::pem_slice_iter(p.cert_pem.as_bytes())
            .collect::<Result<Vec<_>, _>>()
            .map_err(|e| bad("cert_pem", e))?;
        if chain.is_empty() {
            return Err(bad("cert_pem", "no certificate"));
        }
        if p.key_pem.is_empty() {
            return Err(bad("key_pem", "required with cert_pem"));
        }
        // Never echo the key's content in an error.
        let key = PrivateKeyDer::from_pem_slice(p.key_pem.as_bytes())
            .map_err(|_| bad("key_pem", "not a PEM private key"))?;
        b.with_client_auth_cert(chain, key)
            .map_err(|_| bad("key_pem", "does not match cert_pem"))?
    };
    cfg.alpn_protocols = vec![b"http/1.1".to_vec()];
    Ok(cfg)
}

// ---------- device ----------

#[derive(Debug, Clone, Copy, PartialEq, Eq, ParamEnum)]
pub enum DevMethod {
    Get,
    Post,
}

#[derive(Debug, Clone, PartialEq, Params)]
pub struct DevParams {
    #[param(enum, default = "get", display = "Method")]
    pub method: DevMethod,
    #[param(
        default = "",
        display = "Path",
        placeholder = "/v1/status",
        desc = "below the base URL; percent-encoded"
    )]
    pub path: String,
    #[param(
        default = "",
        display = "Query",
        placeholder = "fields=power,energy",
        desc = "without '?'; percent-encoded"
    )]
    pub query: String,
    #[param(
        default = "",
        editor = "textarea",
        display = "Body (JSON)",
        desc = "post only"
    )]
    pub body: String,
    #[param(
        default = "200-299",
        display = "Expected Status",
        desc = "codes and ranges, as 200-299,304"
    )]
    pub expect_status: String,
}

/// A device: one request.
#[derive(Debug, Clone, PartialEq)]
pub struct Dev {
    pub params: DevParams,
    req: Req,
    expect: Vec<(u16, u16)>,
}

/// Longest device body template.
const MAX_TEMPLATE: usize = 64 * 1024;

/// `200-299,304` → ranges.
fn parse_status(s: &str) -> Result<Vec<(u16, u16)>, String> {
    let mut out = Vec::new();
    for part in s.split(',') {
        let part = part.trim();
        let (a, b) = part.split_once('-').unwrap_or((part, part));
        let n = |x: &str| {
            x.trim()
                .parse::<u16>()
                .ok()
                .filter(|c| (100..=599).contains(c))
                .ok_or_else(|| format!("{x:?} is not a status code (100-599)"))
        };
        let (a, b) = (n(a)?, n(b)?);
        if a > b {
            return Err(format!("{a}-{b} is empty"));
        }
        out.push((a, b));
    }
    if out.len() > 16 {
        return Err("more than 16 ranges".into());
    }
    Ok(out)
}

impl Params for Dev {
    fn schema() -> Vec<ParamSpec> {
        DevParams::schema()
    }

    fn from_map(m: &BTreeMap<String, Value>) -> wyrm_link_sdk::Result<Self> {
        let params = DevParams::from_map(m)?;
        check_path(&params.path).map_err(|e| bad("path", e))?;
        if params.path.contains('?') {
            return Err(bad("path", "the query goes in query"));
        }
        let query = params.query.trim_start_matches('?');
        check_chars(query).map_err(|e| bad("query", e))?;
        let body = if params.body.trim().is_empty() {
            None
        } else {
            if params.method != DevMethod::Post {
                return Err(bad("body", "only with method post"));
            }
            if params.body.len() > MAX_TEMPLATE {
                return Err(bad("body", "longer than 64 KiB"));
            }
            serde_json::from_str::<Json>(&params.body).map_err(|e| bad("body", e))?;
            Some(Bytes::from(params.body.clone()))
        };
        let expect = parse_status(&params.expect_status).map_err(|e| bad("expect_status", e))?;
        let mut target = params.path.clone();
        if !query.is_empty() {
            target = format!("{}?{query}", if target.is_empty() { "/" } else { &target });
        }
        let method = match params.method {
            DevMethod::Get => Method::GET,
            DevMethod::Post => Method::POST,
        };
        Ok(Dev {
            req: Req {
                method,
                target,
                body,
            },
            expect,
            params,
        })
    }

    fn to_map(&self) -> BTreeMap<String, Value> {
        self.params.to_map()
    }
}

// ---------- point ----------

#[derive(Debug, Clone, Copy, PartialEq, Eq, ParamEnum)]
pub enum ValueType {
    Number,
    Bool,
    String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, ParamEnum)]
pub enum Aggregate {
    /// Exactly one value must be found.
    None,
    First,
    Sum,
    Max,
    Min,
    Avg,
    Count,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, ParamEnum)]
pub enum WriteMethod {
    Put,
    Post,
    Patch,
}

#[derive(Debug, Clone, PartialEq, Params)]
pub struct PointParams {
    #[param(
        display = "JSON Path",
        placeholder = "$.meter.power",
        desc = "$.a.b, $.items[0].v, $.items[?(@.id==\"x\")].v, $.items[*].v"
    )]
    pub path: String,
    #[param(name = "type", enum, default = "number", display = "Value Type")]
    pub vtype: ValueType,
    #[param(
        enum,
        default = "none",
        display = "Aggregate",
        desc = "several matches ([*], filters): none = exactly one value"
    )]
    pub aggregate: Aggregate,
    #[param(default = 1.0, display = "Scaling")]
    pub scale: f64,
    #[param(default = 0.0, display = "Scaling Offset")]
    pub offset: f64,
    #[param(default = "", display = "Unit")]
    pub unit: String,
    #[param(
        default = "",
        display = "True Text",
        desc = "type bool: a string equal to this (any case) is true"
    )]
    pub bool_true: String,
    #[param(
        default = "",
        display = "False Text",
        desc = "type bool: a string equal to this is false; empty = every other string"
    )]
    pub bool_false: String,
    #[param(
        default = 10.0,
        min = 0.1,
        max = 86400.0,
        display = "Poll Rate (s)",
        desc = "points of a device with the same rate share one request"
    )]
    pub poll_s: f64,
    #[param(default = false, display = "Writable")]
    pub writable: bool,
    #[param(enum, default = "put", display = "Write Method")]
    pub write_method: WriteMethod,
    #[param(
        default = "",
        display = "Write Path",
        placeholder = "/v1/setpoint?unit=1",
        desc = "path and query below the base URL; empty = the device's"
    )]
    pub write_path: String,
    #[param(
        default = "{{value}}",
        editor = "textarea",
        display = "Write Body (JSON)",
        placeholder = "{\"setpoint\": {{value}}}",
        desc = "{{value}} becomes the JSON value written"
    )]
    pub write_body: String,
}

/// A point: its params and its parsed selector.
#[derive(Debug, Clone, PartialEq)]
pub struct Point {
    pub params: PointParams,
    sel: Selector,
}

const PLACEHOLDER: &str = "{{value}}";

impl Params for Point {
    fn schema() -> Vec<ParamSpec> {
        PointParams::schema()
    }

    fn from_map(m: &BTreeMap<String, Value>) -> wyrm_link_sdk::Result<Self> {
        let p = PointParams::from_map(m)?;
        let sel = Selector::parse(&p.path).map_err(|e| bad("path", e))?;
        if p.scale == 0.0 {
            return Err(bad("scale", "must not be 0"));
        }
        let numeric = matches!(
            p.aggregate,
            Aggregate::Sum | Aggregate::Max | Aggregate::Min | Aggregate::Avg | Aggregate::Count
        );
        if numeric && p.vtype != ValueType::Number {
            return Err(bad(
                "aggregate",
                "sum, max, min, avg and count give numbers",
            ));
        }
        if (!p.bool_true.is_empty() || !p.bool_false.is_empty()) && p.vtype != ValueType::Bool {
            return Err(bad(
                "bool_true",
                "bool_true and bool_false only with type bool",
            ));
        }
        if p.writable {
            if p.aggregate != Aggregate::None && p.aggregate != Aggregate::First {
                return Err(bad("writable", "an aggregate cannot be written"));
            }
            if p.vtype == ValueType::Bool && p.bool_true.is_empty() != p.bool_false.is_empty() {
                return Err(bad(
                    "bool_false",
                    "a writable bool needs both bool_true and bool_false, or neither",
                ));
            }
            check_path(&p.write_path).map_err(|e| bad("write_path", e))?;
            if !p.write_body.contains(PLACEHOLDER) {
                return Err(bad("write_body", "must contain {{value}}"));
            }
            if p.write_body.len() > MAX_TEMPLATE {
                return Err(bad("write_body", "longer than 64 KiB"));
            }
            let point = Point {
                params: p.clone(),
                sel: sel.clone(),
            };
            let sample = match p.vtype {
                ValueType::Number => Value::Float(1.5),
                ValueType::Bool => Value::Bool(true),
                ValueType::String => Value::Str("x\"y".into()),
            };
            let body = point.body(&sample).map_err(|e| bad("write_body", e))?;
            serde_json::from_slice::<Json>(&body).map_err(|e| {
                bad(
                    "write_body",
                    format!("not JSON once {{{{value}}}} is replaced ({e})"),
                )
            })?;
        }
        Ok(Point { params: p, sel })
    }

    fn to_map(&self) -> BTreeMap<String, Value> {
        self.params.to_map()
    }
}

/// How a point turns JSON into its value.
struct Conv<'a> {
    path: &'a str,
    vtype: ValueType,
    aggregate: Aggregate,
    scale: f64,
    offset: f64,
    bool_true: &'a str,
    bool_false: &'a str,
}

impl Point {
    fn conv(&self) -> Conv<'_> {
        let p = &self.params;
        Conv {
            path: &p.path,
            vtype: p.vtype,
            aggregate: p.aggregate,
            scale: p.scale,
            offset: p.offset,
            bool_true: &p.bool_true,
            bool_false: &p.bool_false,
        }
    }

    /// The write body for `v`: the template with `{{value}}` replaced by
    /// the JSON value (numbers unscaled: `(v - offset) / scale`).
    fn body(&self, v: &Value) -> Result<Vec<u8>, String> {
        let p = &self.params;
        let json = match p.vtype {
            ValueType::Number => {
                let x = v.as_f64().ok_or("expected a number")?;
                let raw = (x - p.offset) / p.scale;
                if !raw.is_finite() {
                    return Err("value out of range".into());
                }
                if raw.fract() == 0.0 && raw.abs() < 9.0e15 {
                    Json::from(raw as i64)
                } else {
                    Json::from(raw)
                }
            }
            ValueType::Bool => {
                let Value::Bool(b) = v else {
                    return Err("expected true or false".into());
                };
                if p.bool_true.is_empty() {
                    Json::Bool(*b)
                } else if *b {
                    Json::String(p.bool_true.clone())
                } else {
                    Json::String(p.bool_false.clone())
                }
            }
            ValueType::String => match v {
                Value::Str(s) => Json::String(s.clone()),
                _ => return Err("expected a string".into()),
            },
        };
        let text = serde_json::to_string(&json).map_err(|e| e.to_string())?;
        Ok(p.write_body.replace(PLACEHOLDER, &text).into_bytes())
    }
}

impl Conv<'_> {
    fn number(&self, j: &Json) -> Result<f64, String> {
        let x = match j {
            Json::Number(n) => n.as_f64(),
            Json::String(s) => s.trim().parse::<f64>().ok(),
            Json::Bool(b) => Some(f64::from(u8::from(*b))),
            Json::Null => return Err(format!("{}: is null", self.path)),
            _ => None,
        };
        x.filter(|x| x.is_finite())
            .ok_or_else(|| format!("{}: not a number", self.path))
    }

    fn one(&self, j: &Json) -> Result<Value, String> {
        match self.vtype {
            ValueType::Number => Ok(Value::Float(self.number(j)? * self.scale + self.offset)),
            ValueType::Bool => match j {
                Json::Bool(b) => Ok(Value::Bool(*b)),
                Json::Number(n) => Ok(Value::Bool(n.as_f64().is_some_and(|x| x != 0.0))),
                Json::String(s) => {
                    let s = s.trim();
                    if !self.bool_true.is_empty() {
                        if s.eq_ignore_ascii_case(self.bool_true) {
                            Ok(Value::Bool(true))
                        } else if self.bool_false.is_empty()
                            || s.eq_ignore_ascii_case(self.bool_false)
                        {
                            Ok(Value::Bool(false))
                        } else {
                            Err(format!(
                                "{}: neither {:?} nor {:?}",
                                self.path, self.bool_true, self.bool_false
                            ))
                        }
                    } else if s.eq_ignore_ascii_case("true") {
                        Ok(Value::Bool(true))
                    } else if s.eq_ignore_ascii_case("false") {
                        Ok(Value::Bool(false))
                    } else {
                        Err(format!("{}: not a bool (set bool_true)", self.path))
                    }
                }
                Json::Null => Err(format!("{}: is null", self.path)),
                _ => Err(format!("{}: not a bool", self.path)),
            },
            ValueType::String => match j {
                Json::String(s) => Ok(Value::Str(s.clone())),
                Json::Null => Err(format!("{}: is null", self.path)),
                other => Ok(Value::Str(other.to_string())),
            },
        }
    }

    /// The value of the matches of the selector.
    fn eval(&self, found: &[&Json]) -> Result<Value, String> {
        let nothing = || format!("{}: nothing found", self.path);
        match self.aggregate {
            Aggregate::None => match found {
                [] => Err(nothing()),
                [one] => self.one(one),
                many => Err(format!(
                    "{}: selects {} values; set aggregate",
                    self.path,
                    many.len()
                )),
            },
            Aggregate::First => self.one(found.first().ok_or_else(nothing)?),
            Aggregate::Count => Ok(Value::Float(found.len() as f64)),
            agg => {
                let xs = found
                    .iter()
                    .map(|j| self.number(j))
                    .collect::<Result<Vec<f64>, _>>()?;
                if xs.is_empty() {
                    return Err(nothing());
                }
                let x = match agg {
                    Aggregate::Sum => xs.iter().sum(),
                    Aggregate::Max => xs.iter().copied().fold(f64::MIN, f64::max),
                    Aggregate::Min => xs.iter().copied().fold(f64::MAX, f64::min),
                    _ => xs.iter().sum::<f64>() / xs.len() as f64,
                };
                Ok(Value::Float(x * self.scale + self.offset))
            }
        }
    }
}

/// JSON as a tree value (for the actions).
fn json_value(j: &Json) -> Value {
    match j {
        Json::Null => Value::Null,
        Json::Bool(b) => Value::Bool(*b),
        Json::Number(n) => n
            .as_u64()
            .map(Value::UInt)
            .or_else(|| n.as_i64().map(Value::Int))
            .unwrap_or_else(|| Value::Float(n.as_f64().unwrap_or(f64::NAN))),
        Json::String(s) => Value::Str(s.clone()),
        Json::Array(a) => Value::Array(a.iter().map(json_value).collect()),
        Json::Object(o) => Value::Map(o.iter().map(|(k, v)| (k.clone(), json_value(v))).collect()),
    }
}

// ---------- driver ----------

/// Last JSON replies kept for `test_selector` (by request).
const MAX_BODIES: usize = 16;
/// A reply longer than this is not kept for `test_selector`.
const KEEP_BODY: usize = 1024 * 1024;
/// Bound on the bytes of all replies kept on a connection.
const KEEP_TOTAL: usize = 4 * 1024 * 1024;

/// The last JSON reply to a request, as received (masking applies to what
/// `test_selector` shows), or only its size when it is over [`KEEP_BODY`].
struct Kept {
    key: String,
    body: Option<Bytes>,
    len: usize,
}

/// The open connection: the client and the last replies.
pub struct Transport {
    client: Client,
    bodies: VecDeque<Kept>,
}

impl Transport {
    fn remember(&mut self, key: String, body: &Bytes) {
        self.bodies.retain(|k| k.key != key);
        let len = body.len();
        let body = (len <= KEEP_BODY).then(|| body.clone());
        let size = body.as_ref().map_or(0, Bytes::len);
        let kept = |b: &VecDeque<Kept>| -> usize {
            b.iter()
                .map(|k| k.body.as_ref().map_or(0, Bytes::len))
                .sum()
        };
        while !self.bodies.is_empty()
            && (self.bodies.len() >= MAX_BODIES || kept(&self.bodies) + size > KEEP_TOTAL)
        {
            self.bodies.pop_front();
        }
        self.bodies.push_back(Kept { key, body, len });
    }

    fn last(&self, key: &str) -> Option<&Kept> {
        self.bodies.iter().find(|k| k.key == key)
    }
}

/// One group of points of a device: one request.
pub struct Plan {
    req: Req,
    expect: Vec<(u16, u16)>,
    points: Vec<(PointId, Point)>,
}

fn expected(expect: &[(u16, u16)], code: u16) -> bool {
    expect.iter().any(|(a, b)| (*a..=*b).contains(&code))
}

fn status_err(what: &str, code: u16) -> String {
    match code {
        401 | 403 => format!("{what}: HTTP {code}: authentication failed"),
        _ => format!("{what}: HTTP {code}"),
    }
}

fn poll_err(f: Fail) -> DriverError {
    match f {
        Fail::Transport(e) => DriverError::Transport(e),
        Fail::Timeout(e) | Fail::Bad(e) => DriverError::Device(e),
    }
}

fn action_err(f: Fail) -> LinkError {
    match f {
        Fail::Transport(e) => LinkError::new(Status::Disconnected, e),
        Fail::Timeout(e) => LinkError::timeout(e),
        Fail::Bad(e) => LinkError::new(Status::NotAvailable, e),
    }
}

/// Bound on one request on the wire: the rate limit's wait, a reconnect
/// and the reply (each within the timeout).
fn per_request(c: &Conn) -> Duration {
    c.prep.timeout * 2 + c.prep.interval
}

/// Text shown by `try_request`.
const SHOW_BODY: usize = 64 * 1024;
const TRY_MS: u32 = 120_000;
/// `test_selector`: values shown.
const SHOW_VALUES: usize = 20;
/// `test_selector`: a value whose JSON text is longer is shown as that
/// text, cut (20 values stay far below a 64 KiB frame).
const SHOW_VALUE: usize = 2 * 1024;
/// `test_selector`: a converted string `value` longer than this is cut.
const SHOW_TEXT: usize = 8 * 1024;

/// The only headers `try_request` shows when it masked the body (masked
/// like it): any other may give the raw length, a range, a hash or a
/// checksum of the raw body (`Content-Length`, `ETag`, `Digest`,
/// `X-Checksum-*`, …). An allowlist: a denylist always misses one.
const SAFE_HEADERS: &[&str] = &[
    "content-type",
    "date",
    "cache-control",
    "server",
    "vary",
    "retry-after",
    "location",
];

/// Headers never shown by `try_request`.
const HIDDEN_HEADERS: &[&str] = &["set-cookie", "set-cookie2", "authorization"];

/// What a secret in a shown text becomes.
const HIDDEN: &str = "***";
/// A text that still holds a secret once JSON-unescaped is shown as this.
const HIDDEN_WHOLE: &str = "*** hidden: it holds a connection secret";

/// The value of a mask that is a plain decimal number (`[-+]?\d+(\.\d+)?`;
/// not `1e5`, `inf`): a JSON number equal to this value is hidden. Leading
/// zeros are stripped, as a JSON number never has them, so the PIN `0123`
/// hides the number 123 (and never 1234 or 51234.5: equality, not
/// substring). The values 0 to 9 are too common to hide and are never
/// matched as numbers (the PIN `0000` leaves the reading 0 alone; the text
/// `"0000"` is still hidden).
fn numeric(m: &str) -> Option<f64> {
    let d = m.strip_prefix(['-', '+']).unwrap_or(m);
    let (int, frac) = d.split_once('.').unwrap_or((d, "0"));
    let digits = |s: &str| !s.is_empty() && s.bytes().all(|b| b.is_ascii_digit());
    if !digits(int) || !digits(frac) {
        return None;
    }
    // `f64` parsing takes leading zeros as they are: "0123" is 123.
    m.parse::<f64>()
        .ok()
        .filter(|x| x.is_finite() && !(x.fract() == 0.0 && x.abs() <= 9.0))
}

fn holds_secret(prep: &Prepared, s: &str) -> bool {
    prep.masks.iter().any(|m| s.contains(m.as_str()))
}

/// Four hex digits of a JSON unicode escape.
fn hex4(it: &mut std::str::Chars<'_>) -> Option<u32> {
    let h: String = it.by_ref().take(4).collect();
    if h.len() == 4 && h.bytes().all(|b| b.is_ascii_hexdigit()) {
        u32::from_str_radix(&h, 16).ok()
    } else {
        None
    }
}

/// `s` with its JSON escapes decoded (slash, backslash, quote, control
/// letters, unicode escapes with surrogate pairs), to find a secret that
/// an escape hides. Other backslashes stay as they are.
fn unescape(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut it = s.chars();
    while let Some(c) = it.next() {
        if c != '\\' {
            out.push(c);
            continue;
        }
        let rest = it.clone();
        let decoded = match it.next() {
            Some('/') => Some('/'),
            Some('\\') => Some('\\'),
            Some('"') => Some('"'),
            Some('b') => Some('\x08'),
            Some('f') => Some('\x0c'),
            Some('n') => Some('\n'),
            Some('r') => Some('\r'),
            Some('t') => Some('\t'),
            Some('u') => match hex4(&mut it) {
                Some(hi @ 0xD800..=0xDBFF) => {
                    let mut look = it.clone();
                    let pair = look.next() == Some('\\') && look.next() == Some('u');
                    match pair.then(|| hex4(&mut look)).flatten() {
                        Some(lo @ 0xDC00..=0xDFFF) => {
                            it = look;
                            char::from_u32(0x10000 + ((hi - 0xD800) << 10) + (lo - 0xDC00))
                        }
                        _ => Some(char::REPLACEMENT_CHARACTER),
                    }
                }
                Some(cp) => Some(char::from_u32(cp).unwrap_or(char::REPLACEMENT_CHARACTER)),
                None => None,
            },
            _ => None,
        };
        match decoded {
            Some(d) => out.push(d),
            None => {
                out.push('\\');
                it = rest;
            }
        }
    }
    out
}

/// `s` as a user sees it: every secret in it (longest first) replaced by
/// `***`; a text that still holds one once JSON-unescaped (an escaped
/// echo in a body that is not JSON, or JSON inside a string) is hidden
/// whole. Borrowed when nothing is masked.
fn shown<'a>(prep: &Prepared, s: &'a str) -> Cow<'a, str> {
    if prep.masks.is_empty() {
        return Cow::Borrowed(s);
    }
    let mut out = Cow::Borrowed(s);
    for m in &prep.masks {
        if out.contains(m.as_str()) {
            out = Cow::Owned(out.replace(m.as_str(), HIDDEN));
        }
    }
    if out.contains('\\') && holds_secret(prep, &unescape(&out)) {
        return Cow::Owned(HIDDEN_WHOLE.to_owned());
    }
    out
}

/// A JSON number, or a numeric text, equal as a whole to a numeric secret
/// (a PIN, a numeric key), or a text equal to a secret (`"0000"`).
/// `51234.5` never equals the secret `1234`.
fn secret_number(prep: &Prepared, j: &Json) -> bool {
    match j {
        Json::Number(n) => n.as_f64().is_some_and(|x| prep.numbers.contains(&x)),
        Json::String(s) => {
            let t = s.trim();
            prep.masks.iter().any(|m| m == t)
                || t.parse::<f64>().is_ok_and(|x| prep.numbers.contains(&x))
        }
        _ => false,
    }
}

/// A text that is a plain decimal number (`[-+]?\d+(\.\d+)?`, spaces
/// around it allowed): masked like a number, by equality only.
fn numeric_text(s: &str) -> bool {
    let t = s.trim();
    let d = t.strip_prefix(['-', '+']).unwrap_or(t);
    let (int, frac) = d.split_once('.').unwrap_or((d, "0"));
    let digits = |s: &str| !s.is_empty() && s.bytes().all(|b| b.is_ascii_digit());
    digits(int) && digits(frac)
}

/// Mask the values of `j` (and, with `keys`, its member names) as a user
/// and a selector see them:
///
/// * a number, or a numeric text, equal to a numeric secret, and a text
///   equal to a secret, become the string `***` (equality only, so
///   `51234.5` stays with the PIN `1234`);
/// * any other text masks every secret in it ([`shown`]);
/// * with `keys`, every member name as [`shown`]; two names that mask
///   alike are both kept (`***#2`).
///
/// Depth is bounded by `serde_json`'s 128.
fn mask_tree(prep: &Prepared, j: &mut Json, keys: bool) {
    if prep.masks.is_empty() {
        return;
    }
    if matches!(j, Json::Number(_) | Json::String(_)) && secret_number(prep, j) {
        *j = Json::String(HIDDEN.to_owned());
        return;
    }
    match j {
        Json::String(s) if !numeric_text(s) => {
            if let Cow::Owned(m) = shown(prep, s) {
                *s = m;
            }
        }
        Json::Array(a) => a.iter_mut().for_each(|v| mask_tree(prep, v, keys)),
        Json::Object(o) if keys => {
            let old = std::mem::take(o);
            for (k, mut v) in old {
                mask_tree(prep, &mut v, keys);
                let k = shown(prep, &k).into_owned();
                let mut key = k.clone();
                let mut n = 2;
                while o.contains_key(&key) {
                    key = format!("{k}#{n}");
                    n += 1;
                }
                o.insert(key, v);
            }
        }
        Json::Object(o) => o.values_mut().for_each(|v| mask_tree(prep, v, keys)),
        _ => {}
    }
}

/// Mask `j` for showing: values and member names ([`mask_tree`]).
fn mask_json(prep: &Prepared, j: &mut Json) {
    mask_tree(prep, j, true);
}

/// The reply as a selector sees it: every value that holds a secret in its
/// masked form, member names raw. A filter (`<`, `>`, `==`, `!=`) then
/// compares `***` or `Bearer ***`, never the secret, so a count, "nothing
/// found" or "selects N values" cannot depend on the secret's characters
/// (no oracle to read it back one character at a time; a filter that met a
/// masked value fails the point, [`select_view`]); `$.adminState` with the
/// password `admin` still selects, and `51234.5` with the PIN `1234` stays
/// a number. Limits (guide, known limits): masking still tells whether a
/// text equals or holds a secret, so a short secret can be guessed through
/// an echoing server, and member names stay raw.
fn selection_view(prep: &Prepared, j: &mut Json) {
    mask_tree(prep, j, false);
}

/// Select from the [`selection_view`]; `true` when a filter compared a
/// masked value: its answer says nothing true about the reading (a level
/// equal to the PIN is `***` there), so the point fails ("value hidden")
/// rather than show a count one too low or another element.
fn select_view<'a>(prep: &Prepared, sel: &Selector, json: &'a Json) -> (Vec<&'a Json>, bool) {
    if prep.masks.is_empty() {
        return (sel.select(json), false);
    }
    sel.select_masked(
        json,
        &|j| matches!(j, Json::String(s) if s.contains(HIDDEN)),
    )
}

fn filter_hidden(path: &str) -> String {
    format!("{path}: value hidden: a filter compared a value that holds a connection secret")
}

/// The value of a point (or of `test_selector`) from the matches in the
/// [`selection_view`], as a user sees it: a number point whose match was
/// masked fails ("value hidden"); a string point masks the member names of
/// an object or array it shows as text (the values are masked already). A
/// count or a bool shows no secret.
fn shown_value(prep: &Prepared, conv: &Conv<'_>, found: &[&Json]) -> Result<Value, String> {
    if prep.masks.is_empty() {
        return conv.eval(found);
    }
    match conv.vtype {
        ValueType::Number if conv.aggregate != Aggregate::Count => {
            let masked = |j: &&Json| matches!(j, Json::String(s) if s.contains(HIDDEN));
            if found.iter().any(masked) {
                return Err(format!(
                    "{}: value hidden: it holds a connection secret",
                    conv.path
                ));
            }
            conv.eval(found)
        }
        ValueType::String => {
            let masked: Vec<Json> = found
                .iter()
                .map(|j| {
                    let mut c = (*j).clone();
                    mask_json(prep, &mut c);
                    c
                })
                .collect();
            conv.eval(&masked.iter().collect::<Vec<_>>())
        }
        _ => conv.eval(found),
    }
}

/// `try_request`'s body when a text that is not JSON holds a secret.
const HIDDEN_BODY: &str = "*** body hidden: it holds a connection secret";

/// A body that is JSON after a BOM and/or an anti-XSSI prefix (`)]}'`,
/// `)]}',`): the prefix and the JSON.
fn prefixed_json(text: &str) -> Option<(&str, Json)> {
    let rest = text.strip_prefix('\u{feff}').unwrap_or(text);
    let rest = match rest.strip_prefix(")]}'") {
        Some(r) => r.strip_prefix(',').unwrap_or(r),
        None => rest,
    };
    let rest = rest.trim_start();
    if rest.len() == text.len() {
        return None;
    }
    let json = serde_json::from_str(rest).ok()?;
    Some((&text[..text.len() - rest.len()], json))
}

/// A number in a text that is not JSON (NDJSON, JSONP, a form) equal to a
/// numeric secret.
/// Three passes: as a number with a sign and an exponent (`1.2e21`), as a
/// decimal (`code123`, `id-123`, `123-`), and as each run of digits alone
/// (`1.0123.4`, `v1234.5`). The leading-zero and 0–9 rules hold as for
/// JSON numbers (`prep.numbers` excludes 0 to 9; a parse strips zeros).
fn holds_secret_number(prep: &Prepared, s: &str) -> bool {
    let hit = |sep: &dyn Fn(char) -> bool| {
        s.split(sep)
            .filter_map(|t| t.parse::<f64>().ok())
            .any(|x| prep.numbers.contains(&x))
    };
    !prep.numbers.is_empty()
        && (hit(&|c| !(c.is_ascii_digit() || matches!(c, '.' | '-' | '+' | 'e' | 'E')))
            || hit(&|c| !(c.is_ascii_digit() || c == '.'))
            || hit(&|c| !c.is_ascii_digit()))
}

/// `s` cut to at most `n` bytes at a char boundary; `true` when cut.
fn cut(s: &str, n: usize) -> (&str, bool) {
    let mut at = s.len().min(n);
    while !s.is_char_boundary(at) {
        at -= 1;
    }
    (&s[..at], at < s.len())
}

async fn try_request(t: &mut Transport, dev: &Dev) -> Result<Value, LinkError> {
    let reply = t.client.request(&dev.req).await.map_err(action_err)?;
    let prep = t.client.prep.clone();
    // Cookies, and any header named like one that carries our credentials.
    let hidden = |n: &str| {
        HIDDEN_HEADERS.contains(&n)
            || prep
                .headers
                .iter()
                .any(|(h, v)| v.is_sensitive() && h.as_str() == n)
    };
    let mut headers = BTreeMap::new();
    for (name, v) in &reply.headers {
        if hidden(name.as_str()) {
            continue;
        }
        let v = String::from_utf8_lossy(v.as_bytes());
        headers
            .entry(name.as_str().to_owned())
            .and_modify(|e: &mut String| {
                e.push_str(", ");
                e.push_str(&v);
            })
            .or_insert_with(|| v.into_owned());
    }
    let mut headers: BTreeMap<String, Value> = headers
        .into_iter()
        .map(|(k, v)| (k, Value::Str(shown(&prep, &v).into_owned())))
        .collect();
    // A JSON reply is shown as its masked JSON (parsed, so an escape cannot
    // hide a secret); any other body as its masked text, hidden whole when
    // it still holds a secret once JSON-unescaped. Masked whole before the
    // cut: a cut never splits a secret.
    // A JSON reply after an anti-XSSI prefix or a BOM is masked as JSON
    // too (the prefix shown as it is).
    let raw = String::from_utf8_lossy(&reply.body);
    let parsed = serde_json::from_slice::<Json>(&reply.body).ok();
    let is_json = parsed.is_some();
    let parsed = parsed.map(|j| ("", j)).or_else(|| prefixed_json(&raw));
    let (text, masked) = match parsed {
        Some((prefix, json)) if !prep.masks.is_empty() => {
            let mut shown_json = json.clone();
            mask_json(&prep, &mut shown_json);
            let text = serde_json::to_string(&shown_json).unwrap_or_default();
            (format!("{prefix}{text}"), shown_json != json)
        }
        // Not JSON: masked as text; hidden whole when it still holds a
        // secret once JSON-unescaped, or holds a number equal to a numeric
        // secret (the PIN 0123 echoed as 123 in NDJSON or JSONP).
        _ => match shown(&prep, &raw) {
            Cow::Owned(s) if s == HIDDEN_WHOLE => (HIDDEN_BODY.to_owned(), true),
            _ if holds_secret_number(&prep, &raw) => (HIDDEN_BODY.to_owned(), true),
            Cow::Owned(s) => (s, true),
            Cow::Borrowed(s) => (s.to_owned(), false),
        },
    };
    let (body, truncated) = cut(&text, SHOW_BODY);
    let body = body.to_owned();
    if is_json {
        t.remember(dev.req.key(), &reply.body);
    }
    // A masked body shows the masked length: the raw one would give the
    // length of an echoed secret.
    let bytes = if masked { text.len() } else { reply.body.len() };
    // A masked body: the safe headers only, the others counted. The raw
    // length, a range or a hash of the raw body would give the length of a
    // secret or allow an offline guess.
    let mut hidden_headers = 0u64;
    if masked {
        headers.retain(|k, _| {
            let keep = SAFE_HEADERS.contains(&k.as_str());
            hidden_headers += u64::from(!keep);
            keep
        });
    }
    Ok(Value::Map(BTreeMap::from([
        ("status".into(), Value::UInt(reply.status.as_u16().into())),
        ("headers".into(), Value::Map(headers)),
        ("body".into(), Value::Str(body)),
        ("truncated".into(), Value::Bool(truncated)),
        ("masked".into(), Value::Bool(masked)),
        ("hidden_headers".into(), Value::UInt(hidden_headers)),
        (
            "bytes".into(),
            Value::UInt(u64::try_from(bytes).unwrap_or(u64::MAX)),
        ),
    ])))
}

fn arg_enum<E: ParamEnum>(
    args: &BTreeMap<String, Value>,
    name: &str,
) -> Result<Option<E>, LinkError> {
    match args.get(name) {
        None => Ok(None),
        Some(Value::Str(s)) if s.is_empty() => Ok(None),
        Some(Value::Str(s)) => E::from_name(s)
            .map(Some)
            .ok_or_else(|| bad(name, format!("unknown {s}"))),
        Some(_) => Err(bad(name, "expected a name")),
    }
}

fn test_selector(
    t: &Transport,
    dev: &Dev,
    args: &BTreeMap<String, Value>,
) -> Result<Value, LinkError> {
    let path = match args.get("path") {
        Some(Value::Str(s)) => s.clone(),
        _ => return Err(bad("path", "required")),
    };
    let sel = Selector::parse(&path).map_err(|e| bad("path", e))?;
    let vtype: Option<ValueType> = arg_enum(args, "type")?;
    let aggregate: Aggregate = arg_enum(args, "aggregate")?.unwrap_or(Aggregate::None);
    let kept = t.last(&dev.req.key()).ok_or_else(|| {
        LinkError::new(
            Status::NotAvailable,
            "no JSON reply to this device's request yet: wait for a poll or run try_request",
        )
    })?;
    let body = kept.body.as_ref().ok_or_else(|| {
        LinkError::new(
            Status::NotAvailable,
            format!(
                "the last reply ({} bytes) is over {} KiB and is not kept",
                kept.len,
                KEEP_BODY / 1024
            ),
        )
    })?;
    let mut json: Json = serde_json::from_slice(body)
        .map_err(|_| LinkError::new(Status::NotAvailable, "the last reply is not JSON"))?;
    // Selected from the view with secret values masked (no filter oracle);
    // member names are masked as shown.
    let prep = &t.client.prep;
    selection_view(prep, &mut json);
    let (found, compared) = select_view(prep, &sel, &json);
    let mut truncated = found.len() > SHOW_VALUES;
    let values = found
        .iter()
        .take(SHOW_VALUES)
        .map(|j| {
            let mut c = (*j).clone();
            mask_json(prep, &mut c);
            let text = serde_json::to_string(&c).unwrap_or_default();
            if text.len() <= SHOW_VALUE {
                json_value(&c)
            } else {
                // Shown as its JSON text, cut: the reply stays bounded.
                truncated = true;
                Value::Str(format!("{}…", cut(&text, SHOW_VALUE).0))
            }
        })
        .collect();
    let mut out = BTreeMap::from([
        (
            "count".into(),
            Value::UInt(u64::try_from(found.len()).unwrap_or(u64::MAX)),
        ),
        ("values".into(), Value::Array(values)),
    ]);
    if compared {
        out.insert("error".into(), Value::Str(filter_hidden(&path)));
    } else if let Some(vtype) = vtype {
        let conv = Conv {
            path: &path,
            vtype,
            aggregate,
            scale: 1.0,
            offset: 0.0,
            bool_true: "",
            bool_false: "",
        };
        match shown_value(prep, &conv, &found) {
            Ok(Value::Str(s)) if s.len() > SHOW_TEXT => {
                truncated = true;
                out.insert(
                    "value".into(),
                    Value::Str(format!("{}…", cut(&s, SHOW_TEXT).0)),
                )
            }
            Ok(v) => out.insert("value".into(), v),
            Err(e) => out.insert("error".into(), Value::Str(e)),
        };
    }
    out.insert("truncated".into(), Value::Bool(truncated));
    Ok(Value::Map(out))
}

pub struct HttpDriver;

impl Driver for HttpDriver {
    const NAME: &'static str = "http";
    const VERSION: &'static str = env!("CARGO_PKG_VERSION");
    type Conn = Conn;
    type Dev = Dev;
    type Point = Point;
    type Transport = Transport;
    type Plan = Plan;

    async fn open(conn: &Conn) -> Result<Transport, DriverError> {
        let client = Client::open(conn.prep.clone()).await.map_err(poll_err)?;
        Ok(Transport {
            client,
            bodies: VecDeque::new(),
        })
    }

    /// No ping: a device is connected once a request is answered.
    async fn ping(_t: &mut Transport, _dev: &Dev) -> Result<(), DriverError> {
        Ok(())
    }

    fn ping_period(_dev: &Dev) -> Option<Duration> {
        None
    }

    fn plan(dev: &Dev, points: &[(PointId, Point)]) -> Plan {
        Plan {
            req: dev.req.clone(),
            expect: dev.expect.clone(),
            points: points.to_vec(),
        }
    }

    async fn poll(
        t: &mut Transport,
        _dev: &Dev,
        plan: &Plan,
    ) -> Vec<(PointId, Result<Value, DriverError>)> {
        let all = |e: DriverError| {
            plan.points
                .iter()
                .map(|(id, _)| (id.clone(), Err(e.clone())))
                .collect()
        };
        let what = t.client.what(&plan.req);
        let reply = match t.client.request(&plan.req).await {
            Ok(r) => r,
            Err(f) => return all(poll_err(f)),
        };
        let code = reply.status.as_u16();
        if !expected(&plan.expect, code) {
            return all(DriverError::Device(status_err(&what, code)));
        }
        let Ok(mut json) = serde_json::from_slice::<Json>(&reply.body) else {
            return all(DriverError::Device(format!("{what}: reply is not JSON")));
        };
        // Selected from the view with secret values masked, member names
        // raw: a filter never compares a secret (no oracle).
        let prep = t.client.prep.clone();
        selection_view(&prep, &mut json);
        let out = plan
            .points
            .iter()
            .map(|(id, p)| {
                let (found, compared) = select_view(&prep, &p.sel, &json);
                let v = if compared {
                    Err(filter_hidden(&p.params.path))
                } else {
                    shown_value(&prep, &p.conv(), &found)
                };
                (id.clone(), v.map_err(DriverError::Point))
            })
            .collect();
        t.remember(plan.req.key(), &reply.body);
        out
    }

    async fn write(
        t: &mut Transport,
        dev: &Dev,
        _id: &str,
        p: &Point,
        v: &Value,
    ) -> Result<(), DriverError> {
        if !p.params.writable {
            return Err(DriverError::Point("point is not writable".into()));
        }
        let body = p.body(v).map_err(DriverError::Point)?;
        let target = if p.params.write_path.is_empty() {
            dev.req.target.clone()
        } else {
            p.params.write_path.clone()
        };
        let req = Req {
            method: match p.params.write_method {
                WriteMethod::Put => Method::PUT,
                WriteMethod::Post => Method::POST,
                WriteMethod::Patch => Method::PATCH,
            },
            target,
            body: Some(Bytes::from(body)),
        };
        match t.client.write(&req).await {
            Ok(r) if r.status.is_success() || r.status == hyper::StatusCode::SEE_OTHER => Ok(()),
            Ok(r) => Err(DriverError::Point(status_err(
                &t.client.what(&req),
                r.status.as_u16(),
            ))),
            Err(Fail::Transport(e)) => Err(DriverError::Transport(e)),
            Err(Fail::Timeout(e)) => Err(DriverError::Device(e)),
            Err(Fail::Bad(e)) => Err(DriverError::Point(e)),
        }
    }

    fn point_meta(p: &Point) -> NodeMeta {
        let mut m = match p.params.vtype {
            ValueType::Number => NodeMeta::number(),
            ValueType::Bool => NodeMeta::leaf(TypeCode::Bool),
            ValueType::String => NodeMeta::leaf(TypeCode::String),
        };
        if !p.params.unit.is_empty() {
            m = m.unit(p.params.unit.clone());
        }
        m.writable(if p.params.writable {
            Writable::Write
        } else {
            Writable::Never
        })
    }

    fn poll_period(p: &Point) -> Duration {
        Duration::from_secs_f64(p.params.poll_s)
    }

    /// Bound on opening the connection (TCP and TLS within the timeout).
    fn io_timeout(conn: &Conn) -> Duration {
        conn.prep.timeout + Duration::from_secs(1)
    }

    /// The request, its redirects and one resend on a new connection.
    fn poll_timeout(conn: &Conn, _plan: &Plan) -> Duration {
        let n = u32::try_from(client::MAX_REDIRECTS + 2).unwrap_or(u32::MAX);
        per_request(conn) * n + Duration::from_secs(1)
    }

    fn write_timeout(conn: &Conn, _p: &Point) -> Duration {
        let n = u32::try_from(client::MAX_REDIRECTS + 2).unwrap_or(u32::MAX);
        per_request(conn) * n + Duration::from_secs(1)
    }

    fn actions(level: Level, _kind: &str) -> Vec<(&'static str, ActionMeta)> {
        if level != Level::Device {
            return Vec::new();
        }
        let enum_param = |display: &str, names: &[&str]| {
            ParamMeta::of(TypeCode::String)
                .enum_values(names.iter().copied())
                .display(display)
        };
        vec![
            (
                "try_request",
                ActionMeta::new()
                    .level(Perm::Config)
                    .display("Try Request")
                    .timeout_ms(TRY_MS)
                    .result(ActionResult::Type(TypeCode::Map)),
            ),
            (
                "test_selector",
                ActionMeta::new()
                    .level(Perm::Config)
                    .display("Test Selector")
                    .timeout_ms(5_000)
                    .result(ActionResult::Type(TypeCode::Map))
                    .param(
                        "path",
                        ParamMeta::of(TypeCode::String)
                            .display("JSON Path")
                            .description("against the last JSON reply of this device")
                            .required(true),
                    )
                    .param(
                        "type",
                        enum_param("Value Type", ValueType::NAMES)
                            .description("also convert the matches to one value"),
                    )
                    .param("aggregate", enum_param("Aggregate", Aggregate::NAMES)),
            ),
        ]
    }

    async fn invoke(
        t: &mut Transport,
        _conn: &Conn,
        target: Target<'_, Self>,
        action: &str,
        args: &Value,
    ) -> Result<Value, LinkError> {
        let empty = BTreeMap::new();
        let args = match args {
            Value::Map(m) => m,
            _ => &empty,
        };
        match (target, action) {
            (Target::Device { dev, .. }, "try_request") => try_request(t, dev).await,
            (Target::Device { dev, .. }, "test_selector") => test_selector(t, dev, args),
            _ => Err(LinkError::not_supported(format!("action {action}"))),
        }
    }

    const DIAGNOSTICS: bool = true;
    const DIAG_EXTRA: &'static [&'static str] = &[client::RECONNECTS, client::REDIRECTS];
    const FOLDERS: bool = true;

    fn take_outcomes(t: &mut Transport) -> Vec<Outcome> {
        std::mem::take(&mut t.client.outcomes)
    }

    fn status_note(t: &Transport) -> Option<String> {
        t.client.prep.note.clone()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn m(kv: &[(&str, Value)]) -> Value {
        Value::Map(
            kv.iter()
                .map(|(k, v)| ((*k).to_owned(), v.clone()))
                .collect(),
        )
    }

    fn point(kv: &[(&str, Value)]) -> wyrm_link_sdk::Result<Point> {
        Point::from_value(&m(kv))
    }

    fn value(p: &Point, doc: &Json) -> Result<Value, String> {
        p.conv().eval(&p.sel.select(doc))
    }

    #[test]
    fn numbers_bools_and_strings() {
        let doc = json!({"n": 21.5, "s": " 7 ", "i": 3, "b": true, "t": "ON", "f": "off",
            "x": "no", "z": null, "o": {"a": [1, 2]}, "bad": "x1"});
        let num = |path: &str| point(&[("path", path.into())]).unwrap();
        assert_eq!(value(&num("$.n"), &doc), Ok(Value::Float(21.5)));
        assert_eq!(value(&num("$.s"), &doc), Ok(Value::Float(7.0)));
        assert_eq!(value(&num("$.b"), &doc), Ok(Value::Float(1.0)));
        assert!(value(&num("$.z"), &doc).unwrap_err().contains("null"));
        assert!(value(&num("$.bad"), &doc)
            .unwrap_err()
            .contains("not a number"));
        assert!(value(&num("$.o"), &doc).is_err());
        assert_eq!(
            value(&num("$.missing"), &doc),
            Err("$.missing: nothing found".into())
        );
        let scaled = point(&[
            ("path", "$.i".into()),
            ("scale", Value::Float(0.5)),
            ("offset", Value::Float(1.0)),
        ])
        .unwrap();
        assert_eq!(value(&scaled, &doc), Ok(Value::Float(2.5)));
        let b = |path: &str, t: &str, f: &str| {
            point(&[
                ("path", path.into()),
                ("type", "bool".into()),
                ("bool_true", t.into()),
                ("bool_false", f.into()),
            ])
            .unwrap()
        };
        assert_eq!(value(&b("$.b", "", ""), &doc), Ok(Value::Bool(true)));
        assert_eq!(value(&b("$.i", "", ""), &doc), Ok(Value::Bool(true)));
        assert_eq!(value(&b("$.t", "on", ""), &doc), Ok(Value::Bool(true)));
        assert_eq!(value(&b("$.f", "on", ""), &doc), Ok(Value::Bool(false)));
        assert_eq!(value(&b("$.x", "on", ""), &doc), Ok(Value::Bool(false)));
        assert_eq!(value(&b("$.f", "on", "OFF"), &doc), Ok(Value::Bool(false)));
        assert!(value(&b("$.x", "on", "off"), &doc).is_err());
        assert!(value(&b("$.t", "", ""), &doc).is_err());
        let s = |path: &str| point(&[("path", path.into()), ("type", "string".into())]).unwrap();
        assert_eq!(value(&s("$.t"), &doc), Ok(Value::Str("ON".into())));
        assert_eq!(value(&s("$.n"), &doc), Ok(Value::Str("21.5".into())));
        assert_eq!(value(&s("$.b"), &doc), Ok(Value::Str("true".into())));
        assert_eq!(
            value(&s("$.o"), &doc),
            Ok(Value::Str("{\"a\":[1,2]}".into()))
        );
        assert!(value(&s("$.z"), &doc).is_err());
    }

    #[test]
    fn aggregates() {
        let doc =
            json!({"items": [{"v": 1}, {"v": 2.5}, {"v": "4"}], "none": [], "mixed": [1, "x"]});
        let agg =
            |path: &str, a: &str| point(&[("path", path.into()), ("aggregate", a.into())]).unwrap();
        let f = Value::Float;
        assert_eq!(value(&agg("$.items[*].v", "sum"), &doc), Ok(f(7.5)));
        assert_eq!(value(&agg("$.items[*].v", "max"), &doc), Ok(f(4.0)));
        assert_eq!(value(&agg("$.items[*].v", "min"), &doc), Ok(f(1.0)));
        assert_eq!(value(&agg("$.items[*].v", "avg"), &doc), Ok(f(2.5)));
        assert_eq!(value(&agg("$.items[*].v", "count"), &doc), Ok(f(3.0)));
        assert_eq!(value(&agg("$.items[*].v", "first"), &doc), Ok(f(1.0)));
        assert_eq!(value(&agg("$.none[*]", "count"), &doc), Ok(f(0.0)));
        assert!(value(&agg("$.none[*]", "sum"), &doc)
            .unwrap_err()
            .contains("nothing found"));
        assert!(value(&agg("$.none[*]", "first"), &doc).is_err());
        assert!(value(&agg("$.mixed[*]", "sum"), &doc).is_err());
        let e = value(&agg("$.items[*].v", "none"), &doc).unwrap_err();
        assert!(e.contains("selects 3 values"), "{e}");
        assert_eq!(
            value(&agg("$.items[?(@.v == 2.5)].v", "none"), &doc),
            Ok(f(2.5))
        );
    }

    #[test]
    fn point_rules() {
        assert!(point(&[("path", "a.b".into())]).is_err());
        assert!(point(&[("path", "$.a".into()), ("scale", Value::Float(0.0))]).is_err());
        assert!(point(&[
            ("path", "$.a".into()),
            ("type", "bool".into()),
            ("aggregate", "sum".into())
        ])
        .is_err());
        assert!(point(&[("path", "$.a".into()), ("bool_true", "on".into())]).is_err());
        assert!(point(&[("path", "$.a".into()), ("poll_s", Value::Float(0.01))]).is_err());
        let w = |body: &str, ty: &str| {
            point(&[
                ("path", "$.a".into()),
                ("type", ty.into()),
                ("writable", true.into()),
                ("write_body", body.into()),
            ])
        };
        assert!(w("{\"sp\": {{value}}}", "number").is_ok());
        assert!(w("{\"sp\": {{value}}}", "string").is_ok());
        assert!(w("{{value}}", "bool").is_ok());
        assert!(w("{\"sp\": 1}", "number").is_err(), "no placeholder");
        assert!(
            w("{\"sp\": \"{{value}}\"}", "string").is_err(),
            "inside a string"
        );
        assert!(w("{\"sp\": {{value}}", "number").is_err(), "not JSON");
        assert!(point(&[
            ("path", "$.a".into()),
            ("writable", true.into()),
            ("write_path", "nope".into())
        ])
        .is_err());
        assert!(point(&[
            ("path", "$.a".into()),
            ("type", "bool".into()),
            ("bool_true", "on".into()),
            ("writable", true.into())
        ])
        .is_err());
    }

    #[test]
    fn write_bodies() {
        let p = point(&[
            ("path", "$.a".into()),
            ("writable", true.into()),
            ("scale", Value::Float(0.1)),
            ("write_body", "{\"sp\": {{value}}}".into()),
        ])
        .unwrap();
        assert_eq!(p.body(&Value::Float(21.5)).unwrap(), b"{\"sp\": 215}");
        assert_eq!(p.body(&Value::UInt(2)).unwrap(), b"{\"sp\": 20}");
        let p = point(&[
            ("path", "$.a".into()),
            ("writable", true.into()),
            ("write_body", "[{{value}}, {{value}}]".into()),
        ])
        .unwrap();
        assert_eq!(p.body(&Value::Float(0.25)).unwrap(), b"[0.25, 0.25]");
        assert!(p.body(&Value::Str("x".into())).is_err());
        let p = point(&[
            ("path", "$.a".into()),
            ("type", "bool".into()),
            ("bool_true", "ON".into()),
            ("bool_false", "OFF".into()),
            ("writable", true.into()),
            ("write_body", "{\"state\": {{value}}}".into()),
        ])
        .unwrap();
        assert_eq!(
            p.body(&Value::Bool(false)).unwrap(),
            b"{\"state\": \"OFF\"}"
        );
        let p = point(&[
            ("path", "$.a".into()),
            ("type", "string".into()),
            ("writable", true.into()),
        ])
        .unwrap();
        assert_eq!(p.body(&Value::Str("a\"b".into())).unwrap(), b"\"a\\\"b\"");
    }

    #[test]
    fn masking_helpers() {
        let (b, u) = ('\\', 'u');
        let esc =
            format!("a{b}/b{b}{b}c{b}\"d{b}n{b}{u}0041{b}{u}d83d{b}{u}de00{b}{u}d800z{b}x{b}");
        assert_eq!(
            unescape(&esc),
            format!(
                "a/b{b}c\"d\nA\u{1F600}{}z{b}x{b}",
                char::REPLACEMENT_CHARACTER
            )
        );
        assert_eq!(unescape(&format!("{b}{u}12")), format!("{b}{u}12"));
        for (m, want) in [
            ("1234", Some(1234.0)),
            ("-12.5", Some(-12.5)),
            ("1e5", None),
            ("inf", None),
            ("NaN", None),
            ("1.", None),
            (".5", None),
            ("12a", None),
            // leading zeros stripped: a JSON number never has them
            ("0123", Some(123.0)),
            ("000123456", Some(123456.0)),
            ("0012.50", Some(12.5)),
            // 0 to 9 are too common to hide: never matched as numbers
            ("0000", None),
            ("0", None),
            ("+7", None),
            ("-05", None),
            ("9", None),
            ("10", Some(10.0)),
            ("0.5", Some(0.5)),
        ] {
            assert_eq!(numeric(m), want, "{m}");
        }
        let pin = |p: &str| {
            Conn::from_value(&m(&[
                ("base_url", "http://127.0.0.1".into()),
                ("auth", "basic".into()),
                ("username", "u".into()),
                ("password", p.into()),
            ]))
            .unwrap()
        };
        let zeros = pin("0000");
        assert!(!secret_number(&zeros.prep, &json!(0)), "0 stays a reading");
        assert!(
            secret_number(&zeros.prep, &json!(" 0000 ")),
            "echoed as text"
        );
        let p = pin("0123");
        assert!(
            secret_number(&p.prep, &json!(123)),
            "echoed as the number 123"
        );
        assert!(secret_number(&p.prep, &json!(123.0)));
        for other in [json!(1234), json!(51234.5), json!(12), json!(1230)] {
            assert!(!secret_number(&p.prep, &other), "{other}");
        }
        let p = pin("000123456");
        assert!(secret_number(&p.prep, &json!(123456)));
        assert!(!secret_number(&p.prep, &json!(1234567)));
        // masks longest first, numbers found
        let c = Conn::from_value(&m(&[
            ("base_url", "http://127.0.0.1".into()),
            ("auth", "basic".into()),
            ("username", "u".into()),
            ("password", "1234".into()),
        ]))
        .unwrap();
        assert_eq!(c.prep.masks, vec!["dToxMjM0".to_owned(), "1234".to_owned()]);
        assert_eq!(c.prep.numbers, vec![1234.0]);
        let prep = &c.prep;
        assert_eq!(shown(prep, "x1234y"), "x***y");
        assert_eq!(
            shown(prep, "51234.5"),
            "5***.5",
            "a text masks by substring"
        );
        assert!(!secret_number(prep, &json!(51234.5)));
        assert!(secret_number(prep, &json!(1234)));
        assert!(secret_number(prep, &json!(" 1234.0 ")));
        // the selection view: values masked, member names raw; a numeric
        // text masks like a number (equality only)
        let mut j = json!({"a1234": "x1234y", "s": "51234.5", "t": " 1234 ", "n": [1234, 12]});
        selection_view(prep, &mut j);
        assert_eq!(
            j,
            json!({"a1234": "x***y", "s": "51234.5", "t": "***", "n": ["***", 12]})
        );
        let mut j = json!({"a1234": 51234.5, "b": 1234, "a***": 0});
        mask_json(prep, &mut j);
        assert_eq!(j, json!({"a***": 0, "a***#2": 51234.5, "b": "***"}));
    }

    fn dev(kv: &[(&str, Value)]) -> wyrm_link_sdk::Result<Dev> {
        Dev::from_value(&m(kv))
    }

    #[test]
    fn device_rules() {
        let d = dev(&[("path", "/v1/s".into()), ("query", "a=1&b=2".into())]).unwrap();
        assert_eq!(d.req.target, "/v1/s?a=1&b=2");
        assert_eq!(d.req.method, Method::GET);
        assert_eq!(dev(&[("query", "a=1".into())]).unwrap().req.target, "/?a=1");
        assert_eq!(dev(&[]).unwrap().req.target, "");
        assert_eq!(d.expect, vec![(200, 299)]);
        assert!(dev(&[("path", "v1".into())]).is_err());
        assert!(dev(&[("path", "/a?b".into())]).is_err());
        assert!(dev(&[("query", "a b".into())]).is_err());
        assert!(dev(&[("body", "{}".into())]).is_err(), "body with get");
        assert!(dev(&[("method", "post".into()), ("body", "{".into())]).is_err());
        let p = dev(&[("method", "post".into()), ("body", "{\"q\": 1}".into())]).unwrap();
        assert_eq!(p.req.body.as_deref(), Some(&b"{\"q\": 1}"[..]));
        assert_eq!(
            parse_status("200, 204-206,304").unwrap(),
            vec![(200, 200), (204, 206), (304, 304)]
        );
        for bad in ["", "99", "600", "300-200", "abc", "200-"] {
            assert!(parse_status(bad).is_err(), "{bad}");
        }
    }

    fn conn(kv: &[(&str, Value)]) -> wyrm_link_sdk::Result<Conn> {
        Conn::from_value(&m(kv))
    }

    #[test]
    fn connection_rules() {
        let url = |u: &str| ("base_url", Value::from(u));
        assert!(conn(&[url("http://192.0.2.1/api")]).is_ok());
        assert!(conn(&[url("http://u:p@192.0.2.1/api")]).is_err());
        // credentials in plaintext beyond loopback
        let basic = [
            ("auth", Value::from("basic")),
            ("username", "u".into()),
            ("password", "pw-1".into()),
        ];
        let mut far = vec![url("http://192.0.2.1")];
        far.extend_from_slice(&basic);
        let e = conn(&far).unwrap_err();
        assert!(!format!("{e:?}").contains("pw-1"));
        far.push(("insecure_plaintext", true.into()));
        let c = conn(&far).unwrap();
        assert!(c.prep.note.as_deref().unwrap().contains("plaintext"));
        let mut near = vec![url("http://127.0.0.1:1")];
        near.extend_from_slice(&basic);
        assert!(conn(&near).unwrap().prep.note.is_none());
        // no system roots needed (CI containers may have none)
        let mut tls = vec![
            url("https://192.0.2.1"),
            ("insecure_skip_verify", true.into()),
        ];
        tls.extend_from_slice(&basic);
        let c = conn(&tls).unwrap();
        assert!(c.prep.tls.is_some());
        assert_eq!(c.prep.headers[0].0, hyper::header::AUTHORIZATION);
        assert!(c.prep.headers[0].1.is_sensitive());
        // required secrets
        assert!(conn(&[url("https://h"), ("auth", "bearer".into())]).is_err());
        assert!(conn(&[url("https://h"), ("auth", "basic".into())]).is_err());
        // TLS params only with https
        assert!(conn(&[url("http://h"), ("insecure_skip_verify", true.into())]).is_err());
        let c = conn(&[url("https://h"), ("insecure_skip_verify", true.into())]).unwrap();
        assert!(c.prep.note.is_some());
        assert!(conn(&[url("https://h"), ("ca_pem", "nope".into())]).is_err());
        // API key in a query
        let c = conn(&[
            url("http://127.0.0.1"),
            ("auth", "api_key".into()),
            ("api_key_in", "query".into()),
            ("api_key_name", "key".into()),
            ("token", "a b".into()),
        ])
        .unwrap();
        assert_eq!(c.prep.query_key, Some(("key".into(), "a%20b".into())));
        // headers: no credentials, no framing
        let h = |text: &str| conn(&[url("http://127.0.0.1"), ("headers", text.into())]);
        let c = h("Accept-Language: en\n\nX-Site: 7").unwrap();
        assert_eq!(c.prep.headers.len(), 2);
        for bad in [
            "Authorization: Bearer x",
            "cookie: a=1",
            "Host: x",
            "no colon",
            "Bad Name: x",
        ] {
            assert!(h(bad).is_err(), "{bad}");
        }
        assert!(conn(&[
            url("http://127.0.0.1"),
            ("auth", "api_key".into()),
            ("token", "k123".into()),
            ("headers", "x-api-key: other".into()),
        ])
        .is_err());
        // credential-like names never in the non-secret headers
        for bad in [
            "X-API-Key: k",
            "X-Auth-Token: t",
            "X-Api-Secret: s",
            "X-Session-Id: 1",
            "X-CSRF-Token: c",
            "X-Password: p",
        ] {
            let e = h(bad).err().map(|e| format!("{e:?}")).unwrap_or_default();
            assert!(e.contains("secret_header"), "{bad}: {e}");
        }
        // one more credential header: a secret, masked, sensitive
        let sh = |name: &str, value: &str, base: &str| {
            conn(&[
                url(base),
                ("auth", "api_key".into()),
                ("token", "key-1".into()),
                ("secret_header_name", name.into()),
                ("secret_header_value", value.into()),
            ])
        };
        let c = sh("X-Api-Secret", "sec-777", "http://127.0.0.1").unwrap();
        let (n, v) = c.prep.headers.last().unwrap();
        assert_eq!((n.as_str(), v.is_sensitive()), ("x-api-secret", true));
        assert!(c.prep.masks.contains(&"sec-777".to_owned()));
        assert!(!format!("{c:?}").contains("sec-777"));
        assert!(!Conn::public_map(&c).contains_key("secret_header_value"));
        // a scheme and a token: the token alone is masked too
        let c = sh("Authorization", "Bearer abc-123", "http://127.0.0.1").unwrap();
        assert!(c.prep.masks.contains(&"Bearer abc-123".to_owned()));
        assert!(c.prep.masks.contains(&"abc-123".to_owned()));
        for (name, value, base) in [
            ("X-Api-Secret", "", "http://127.0.0.1"),
            ("Host", "x", "http://127.0.0.1"),
            ("X-API-Key", "x", "http://127.0.0.1"),
            ("Bad Name", "x", "http://127.0.0.1"),
            ("X-Api-Secret", "sec-777", "http://192.0.2.1"),
        ] {
            let e = sh(name, value, base).unwrap_err();
            assert!(!format!("{e:?}").contains("sec-777"), "{name}");
        }
        // a secret header alone counts as credentials (plaintext rule)
        assert!(conn(&[
            url("http://192.0.2.1"),
            ("secret_header_name", "X-Sig".into()),
            ("secret_header_value", "sig-1".into()),
        ])
        .is_err());
        // bounds
        assert!(conn(&[url("https://h"), ("timeout_ms", Value::UInt(50))]).is_err());
        assert!(conn(&[url("https://h"), ("rate_limit", Value::Float(0.0))]).is_err());
        assert!(conn(&[url("https://h"), ("max_body_kib", Value::UInt(0))]).is_err());
        // Debug never prints secrets
        let c = conn(&tls).unwrap();
        assert!(!format!("{c:?}").contains("pw-1"));
        assert!(!Conn::public_map(&c).contains_key("password"));
    }
}
