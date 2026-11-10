//! The OAuth 2.1 authorization server of the remote MCP endpoint (ADR 0041 stage B).
//!
//! Claude (web, Desktop, mobile) adds a connector by URL. It finds this server through
//! `/.well-known/oauth-protected-resource` (RFC 9728) and
//! `/.well-known/oauth-authorization-server` (RFC 8414), registers itself (RFC 7591), sends
//! the person to `/oauth/authorize` (PKCE S256 only), and trades the code at `/oauth/token`.
//!
//! * **Clients** are stateless: the `client_id` is a sealed token of the registered redirect
//!   URIs and name. Only redirect URIs on the allowlist (`McpConfig::redirect_uris`) register.
//! * **Login** is the gateway's own: the same users, argon2id, failure limits and audit.
//!   The person also chooses there whether Claude may change anything, and whether it may make
//!   config-level changes.
//! * **Codes** live in memory, 60 s, single use, bound to the client, the redirect URI and the
//!   PKCE challenge.
//! * **Access tokens** (≤ 1 h) and **refresh tokens** are sealed, carry the user's generation
//!   and are checked against the user store on every use: a password change, a disabled user
//!   or a removed one ends them. They are valid only on `/mcp`, never as a gateway session.
//!
//! OAuth and MCP are JSON by their own standards; this is the edge, the WYRM wire stays CBOR.

use crate::http::AppState;
use crate::session::{now_s, Sealer};
use crate::LoginError;
use axum::extract::{ConnectInfo, Query, State};
use axum::http::header::{CACHE_CONTROL, CONTENT_TYPE, LOCATION};
use axum::http::{HeaderMap, HeaderValue, StatusCode};
use axum::response::{Html, IntoResponse, Response};
use axum::Form;
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;
use serde::Deserialize;
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::net::SocketAddr;
use std::sync::Mutex;
use std::time::Duration;
use wyrm_core::Value;
use zeroize::Zeroizing;

/// The redirect URIs of Claude's connectors.
pub const CLAUDE_REDIRECTS: [&str; 2] = [
    "https://claude.ai/api/mcp/auth_callback",
    "https://claude.com/api/mcp/auth_callback",
];
/// An allowlist entry that admits loopback redirects on any port (RFC 8252 §7.3): MCP clients
/// on the person's own computer (Claude Code).
pub const LOOPBACK: &str = "loopback";
/// The one scope.
pub const SCOPE: &str = "wyrm";

const KIND_CLIENT: u8 = 0x21;
const KIND_ACCESS: u8 = 0x22;
const KIND_REFRESH: u8 = 0x23;
const CODE_TTL_S: u64 = 60;
/// Codes waiting to be traded.
const CODES_MAX: usize = 1024;
const ACCESS_TTL_MAX: Duration = Duration::from_secs(3600);
const URI_MAX: usize = 512;
const REDIRECTS_MAX: usize = 8;

#[derive(Debug, Clone)]
pub struct McpConfig {
    /// The gateway as Claude reaches it, `https://broker.example[:port]` (no path): the
    /// issuer; the protected resource is `<public_url>/mcp`. `http://` only on loopback.
    pub public_url: String,
    /// Redirect URIs a client may register: exact URIs, and [`LOOPBACK`].
    pub redirect_uris: Vec<String>,
    /// Access token lifetime, at most 1 h.
    pub access_ttl: Duration,
    /// Refresh token lifetime.
    pub refresh_ttl: Duration,
}

impl McpConfig {
    /// Claude's callbacks and loopback, 1 h access, 30 days refresh.
    pub fn new(public_url: impl Into<String>) -> Self {
        let mut redirect_uris: Vec<String> =
            CLAUDE_REDIRECTS.iter().map(|s| s.to_string()).collect();
        redirect_uris.push(LOOPBACK.into());
        Self {
            public_url: public_url.into(),
            redirect_uris,
            access_ttl: ACCESS_TTL_MAX,
            refresh_ttl: Duration::from_secs(30 * 24 * 3600),
        }
    }
}

/// `scheme://host[:port]` of a URL without query or fragment: `(scheme, authority, path)`.
fn split_url(u: &str) -> Option<(&str, &str, &str)> {
    if u.len() > URI_MAX || u.contains(['#', ' ', '"', '<', '>', '\\']) {
        return None;
    }
    let (scheme, rest) = u.split_once("://")?;
    if !matches!(scheme, "http" | "https") {
        return None;
    }
    let (auth, path) = match rest.find(['/', '?']) {
        Some(i) => (&rest[..i], &rest[i..]),
        None => (rest, ""),
    };
    if auth.is_empty() || auth.contains('@') {
        return None;
    }
    Some((scheme, auth, path))
}

fn host_of(authority: &str) -> &str {
    if authority.starts_with('[') {
        return authority
            .split_once(']')
            .map(|(h, _)| &h[1..])
            .unwrap_or(authority);
    }
    authority
        .rsplit_once(':')
        .map(|(h, _)| h)
        .unwrap_or(authority)
}

fn is_loopback_host(h: &str) -> bool {
    matches!(h, "127.0.0.1" | "localhost" | "::1")
}

/// What the person allowed on the consent page.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Consent {
    pub write: bool,
    pub config: bool,
}

/// A verified access token.
#[derive(Debug, Clone)]
pub struct Access {
    pub sub: String,
    pub gen: u64,
    pub exp: u64,
    pub iat: u64,
    pub jti: [u8; 16],
    pub consent: Consent,
    /// The client's name as it registered.
    pub client: String,
}

/// Who a token is for, and what was allowed.
#[derive(Clone, Copy)]
struct Granted<'a> {
    sub: &'a str,
    gen: u64,
    consent: Consent,
    client: &'a str,
    client_id: &'a str,
}

struct Code {
    client_id: String,
    redirect_uri: String,
    challenge: String,
    sub: String,
    gen: u64,
    consent: Consent,
    client: String,
    exp: u64,
}

pub(crate) struct OAuth {
    cfg: McpConfig,
    issuer: String,
    sealer: Sealer,
    codes: Mutex<HashMap<String, Code>>,
}

fn random_b64(n: usize) -> String {
    let mut b = vec![0u8; n];
    // a failing OS RNG would give guessable codes: refuse instead
    getrandom::fill(&mut b).expect("OS random source");
    URL_SAFE_NO_PAD.encode(b)
}

fn map<const N: usize>(kv: [(&str, Value); N]) -> Value {
    Value::Map(kv.into_iter().map(|(k, v)| (k.to_owned(), v)).collect())
}

fn field<'a>(v: &'a Value, k: &str) -> Option<&'a Value> {
    match v {
        Value::Map(m) => m.get(k),
        _ => None,
    }
}

fn text_of(v: &Value, k: &str) -> Option<String> {
    match field(v, k) {
        Some(Value::Str(s)) => Some(s.clone()),
        _ => None,
    }
}

fn uint_of(v: &Value, k: &str) -> Option<u64> {
    match field(v, k) {
        Some(Value::UInt(u)) => Some(*u),
        _ => None,
    }
}

fn bool_of(v: &Value, k: &str) -> bool {
    matches!(field(v, k), Some(Value::Bool(true)))
}

impl OAuth {
    pub(crate) fn new(cfg: McpConfig, state_key: &[u8]) -> Result<Self, String> {
        let issuer = cfg.public_url.trim_end_matches('/').to_owned();
        let (scheme, auth, path) = split_url(&issuer)
            .ok_or_else(|| format!("mcp.public_url {issuer:?}: https://host[:port]"))?;
        if !path.is_empty() {
            return Err(format!("mcp.public_url {issuer:?}: no path"));
        }
        if scheme == "http" && !is_loopback_host(host_of(auth)) {
            return Err(format!(
                "mcp.public_url {issuer:?}: https (plain http only on loopback)"
            ));
        }
        if cfg.redirect_uris.is_empty() {
            return Err("mcp.redirect_uris: empty".into());
        }
        for r in &cfg.redirect_uris {
            if r == LOOPBACK {
                continue;
            }
            match split_url(r) {
                Some(("https", ..)) => {}
                Some(("http", a, _)) if is_loopback_host(host_of(a)) => {}
                _ => {
                    return Err(format!(
                        "mcp.redirect_uris {r:?}: https URL or \"loopback\""
                    ))
                }
            }
        }
        if cfg.access_ttl.is_zero() || cfg.access_ttl > ACCESS_TTL_MAX {
            return Err("mcp.access_ttl: 1 s … 1 h".into());
        }
        if cfg.refresh_ttl < cfg.access_ttl {
            return Err("mcp.refresh_ttl: at least the access lifetime".into());
        }
        Ok(Self {
            cfg,
            issuer,
            sealer: Sealer::derive(state_key, "wyrm-gateway/oauth/v1"),
            codes: Mutex::new(HashMap::new()),
        })
    }

    pub(crate) fn issuer(&self) -> &str {
        &self.issuer
    }

    pub(crate) fn resource(&self) -> String {
        format!("{}/mcp", self.issuer)
    }

    /// `host` and `host:port` of the public URL, for the MCP endpoint's `Host` check.
    pub(crate) fn hosts(&self) -> Vec<String> {
        let (_, auth, _) = split_url(&self.issuer).expect("checked at start");
        let host = host_of(auth).to_owned();
        let mut v = vec![auth.to_owned()];
        if host != auth {
            v.push(host);
        }
        v
    }

    pub(crate) fn resource_metadata_url(&self) -> String {
        format!("{}/.well-known/oauth-protected-resource", self.issuer)
    }

    fn redirect_allowed(&self, uri: &str) -> bool {
        if self.cfg.redirect_uris.iter().any(|r| r == uri) {
            return true;
        }
        self.cfg.redirect_uris.iter().any(|r| r == LOOPBACK)
            && matches!(split_url(uri), Some(("http", a, _)) if is_loopback_host(host_of(a)) && a.contains(':'))
    }

    fn client(&self, client_id: &str) -> Option<(Vec<String>, String)> {
        let v = self.sealer.open(KIND_CLIENT, client_id)?;
        let uris = match field(&v, "u") {
            Some(Value::Array(a)) => a
                .iter()
                .filter_map(|x| match x {
                    Value::Str(s) => Some(s.clone()),
                    _ => None,
                })
                .collect(),
            _ => return None,
        };
        Some((uris, text_of(&v, "n").unwrap_or_default()))
    }

    /// Check an authorization request; `Err` = show an error page, never redirect.
    fn check_request(&self, q: &AuthorizeQuery) -> Result<String, String> {
        let (uris, name) = self
            .client(&q.client_id)
            .ok_or("unknown client: add the connector again")?;
        if !uris.contains(&q.redirect_uri) || !self.redirect_allowed(&q.redirect_uri) {
            return Err("this redirect address is not registered for the client".into());
        }
        if q.response_type != "code" {
            return Err("response_type must be code".into());
        }
        if q.code_challenge_method.as_deref() != Some("S256")
            || !(43..=128).contains(&q.code_challenge.len())
        {
            return Err("PKCE with S256 is required".into());
        }
        if let Some(r) = q.resource.as_deref().filter(|r| !r.is_empty()) {
            if r.trim_end_matches('/') != self.resource() {
                return Err(format!("this server is the resource {}", self.resource()));
            }
        }
        Ok(name)
    }

    fn new_code(&self, c: Code) -> Option<String> {
        let mut m = self.codes.lock().unwrap_or_else(|p| p.into_inner());
        let now = now_s();
        m.retain(|_, c| c.exp > now);
        if m.len() >= CODES_MAX {
            return None;
        }
        let code = random_b64(32);
        m.insert(code.clone(), c);
        Some(code)
    }

    fn take_code(&self, code: &str) -> Option<Code> {
        let mut m = self.codes.lock().unwrap_or_else(|p| p.into_inner());
        m.remove(code).filter(|c| c.exp > now_s())
    }

    fn mint(&self, kind: u8, g: &Granted<'_>, ttl: Duration) -> (String, u64) {
        let Granted {
            sub,
            gen,
            consent,
            client,
            client_id,
        } = *g;
        let iat = now_s();
        let exp = iat + ttl.as_secs().max(1);
        let mut jti = [0u8; 16];
        getrandom::fill(&mut jti).expect("OS random source");
        let v = map([
            ("s", Value::from(sub)),
            ("g", Value::UInt(gen)),
            ("e", Value::UInt(exp)),
            ("i", Value::UInt(iat)),
            ("j", Value::Bytes(jti.to_vec())),
            ("w", Value::Bool(consent.write)),
            ("c", Value::Bool(consent.config)),
            ("n", Value::from(client)),
            // a refresh token is bound to its client
            (
                "k",
                Value::from(if kind == KIND_REFRESH { client_id } else { "" }),
            ),
        ]);
        (self.sealer.seal(kind, &v), exp)
    }

    fn open_token(&self, kind: u8, token: &str) -> Option<(Access, String)> {
        let v = self.sealer.open(kind, token)?;
        let exp = uint_of(&v, "e")?;
        if now_s() >= exp {
            return None;
        }
        let jti = match field(&v, "j") {
            Some(Value::Bytes(b)) => b.as_slice().try_into().ok()?,
            _ => return None,
        };
        Some((
            Access {
                sub: text_of(&v, "s")?,
                gen: uint_of(&v, "g")?,
                exp,
                iat: uint_of(&v, "i")?,
                jti,
                consent: Consent {
                    write: bool_of(&v, "w"),
                    config: bool_of(&v, "c"),
                },
                client: text_of(&v, "n").unwrap_or_default(),
            },
            text_of(&v, "k").unwrap_or_default(),
        ))
    }

    /// A verified access token (MAC, expiry); the user is checked by the caller.
    pub(crate) fn access(&self, token: &str) -> Option<Access> {
        self.open_token(KIND_ACCESS, token).map(|(a, _)| a)
    }
}

// ---------- discovery ----------

fn json(status: StatusCode, v: serde_json::Value) -> Response {
    let mut r = (status, v.to_string()).into_response();
    let h = r.headers_mut();
    h.insert(CONTENT_TYPE, HeaderValue::from_static("application/json"));
    h.insert(CACHE_CONTROL, HeaderValue::from_static("no-store"));
    r
}

fn oauth_error(status: StatusCode, error: &str, description: &str) -> Response {
    json(
        status,
        serde_json::json!({ "error": error, "error_description": description }),
    )
}

fn not_enabled() -> Response {
    oauth_error(
        StatusCode::NOT_FOUND,
        "not_found",
        "the MCP endpoint is off",
    )
}

pub(crate) async fn protected_resource(State(st): State<AppState>) -> Response {
    let Some(o) = st.gw.oauth.as_ref() else {
        return not_enabled();
    };
    json(
        StatusCode::OK,
        serde_json::json!({
            "resource": o.resource(),
            "authorization_servers": [o.issuer()],
            "bearer_methods_supported": ["header"],
            "scopes_supported": [SCOPE],
            "resource_name": format!("WYRM {}", st.gw.site()),
        }),
    )
}

pub(crate) async fn authorization_server(State(st): State<AppState>) -> Response {
    let Some(o) = st.gw.oauth.as_ref() else {
        return not_enabled();
    };
    let i = o.issuer();
    json(
        StatusCode::OK,
        serde_json::json!({
            "issuer": i,
            "authorization_endpoint": format!("{i}/oauth/authorize"),
            "token_endpoint": format!("{i}/oauth/token"),
            "registration_endpoint": format!("{i}/oauth/register"),
            "response_types_supported": ["code"],
            "grant_types_supported": ["authorization_code", "refresh_token"],
            "code_challenge_methods_supported": ["S256"],
            "token_endpoint_auth_methods_supported": ["none"],
            "scopes_supported": [SCOPE],
            "authorization_response_iss_parameter_supported": true,
        }),
    )
}

// ---------- registration (RFC 7591) ----------

pub(crate) async fn register(State(st): State<AppState>, body: axum::body::Bytes) -> Response {
    let Some(o) = st.gw.oauth.as_ref() else {
        return not_enabled();
    };
    let Ok(req) = serde_json::from_slice::<serde_json::Value>(&body) else {
        return oauth_error(
            StatusCode::BAD_REQUEST,
            "invalid_client_metadata",
            "a JSON object",
        );
    };
    let uris: Vec<String> = match req.get("redirect_uris").and_then(|u| u.as_array()) {
        Some(a) if !a.is_empty() && a.len() <= REDIRECTS_MAX => {
            match a
                .iter()
                .map(|u| u.as_str().map(str::to_owned))
                .collect::<Option<Vec<_>>>()
            {
                Some(v) => v,
                None => {
                    return oauth_error(
                        StatusCode::BAD_REQUEST,
                        "invalid_redirect_uri",
                        "text URIs",
                    )
                }
            }
        }
        _ => {
            return oauth_error(
                StatusCode::BAD_REQUEST,
                "invalid_redirect_uri",
                "redirect_uris: 1 to 8 URIs",
            )
        }
    };
    if let Some(bad) = uris.iter().find(|u| !o.redirect_allowed(u)) {
        return oauth_error(
            StatusCode::BAD_REQUEST,
            "invalid_redirect_uri",
            &format!("{bad}: not on this gateway's allowlist (gateway.mcp.redirect_uris)"),
        );
    }
    let name: String = req
        .get("client_name")
        .and_then(|n| n.as_str())
        .unwrap_or("MCP client")
        .chars()
        .filter(|c| !c.is_control())
        .take(64)
        .collect();
    let now = now_s();
    let client_id = o.sealer.seal(
        KIND_CLIENT,
        &map([
            (
                "u",
                Value::Array(uris.iter().map(|u| Value::from(u.as_str())).collect()),
            ),
            ("n", Value::from(name.as_str())),
            ("i", Value::UInt(now)),
        ]),
    );
    json(
        StatusCode::CREATED,
        serde_json::json!({
            "client_id": client_id,
            "client_id_issued_at": now,
            "client_name": name,
            "redirect_uris": uris,
            "token_endpoint_auth_method": "none",
            "grant_types": ["authorization_code", "refresh_token"],
            "response_types": ["code"],
            "scope": SCOPE,
        }),
    )
}

// ---------- authorization ----------

#[derive(Deserialize, Clone, Default)]
pub(crate) struct AuthorizeQuery {
    #[serde(default)]
    response_type: String,
    #[serde(default)]
    client_id: String,
    #[serde(default)]
    redirect_uri: String,
    #[serde(default)]
    code_challenge: String,
    code_challenge_method: Option<String>,
    state: Option<String>,
    scope: Option<String>,
    resource: Option<String>,
}

#[derive(Deserialize)]
pub(crate) struct AuthorizeForm {
    #[serde(flatten)]
    q: AuthorizeQuery,
    #[serde(default)]
    user: String,
    #[serde(default)]
    password: String,
    /// Checkboxes: present = on.
    write: Option<String>,
    config: Option<String>,
    /// `allow` or `deny`.
    #[serde(default)]
    decision: String,
}

fn esc(s: &str) -> String {
    let mut o = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            '&' => o.push_str("&amp;"),
            '<' => o.push_str("&lt;"),
            '>' => o.push_str("&gt;"),
            '"' => o.push_str("&quot;"),
            '\'' => o.push_str("&#39;"),
            c => o.push(c),
        }
    }
    o
}

fn page(status: StatusCode, body: String) -> Response {
    let html = format!(
        "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\">\
<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"><title>WYRM sign in</title>\
<style>body{{font:16px system-ui,sans-serif;max-width:26rem;margin:3rem auto;padding:0 1rem;color:#1b1b1f;background:#fafafa}}\
h1{{font-size:1.3rem}}label{{display:block;margin:.8rem 0 .2rem}}input[type=text],input[type=password]{{width:100%;padding:.5rem;box-sizing:border-box;font:inherit}}\
.c{{display:flex;gap:.5rem;align-items:flex-start;margin:.6rem 0}}.c input{{margin-top:.3rem}}\
button{{font:inherit;padding:.5rem 1.2rem;margin:1rem .5rem 0 0}}.e{{color:#b3261e}}small{{color:#555}}\
@media (prefers-color-scheme:dark){{body{{background:#121214;color:#e6e6ea}}small{{color:#aaa}}.e{{color:#f2b8b5}}}}</style>\
</head><body>{body}</body></html>"
    );
    let mut r = (status, Html(html)).into_response();
    let h = r.headers_mut();
    h.insert(CACHE_CONTROL, HeaderValue::from_static("no-store"));
    h.insert("x-frame-options", HeaderValue::from_static("DENY"));
    h.insert("referrer-policy", HeaderValue::from_static("no-referrer"));
    h.insert(
        "content-security-policy",
        HeaderValue::from_static(
            "default-src 'none'; style-src 'unsafe-inline'; frame-ancestors 'none'",
        ),
    );
    r
}

fn error_page(msg: &str) -> Response {
    page(
        StatusCode::BAD_REQUEST,
        format!("<h1>Cannot connect</h1><p class=\"e\">{}</p>", esc(msg)),
    )
}

fn login_form(
    st: &AppState,
    q: &AuthorizeQuery,
    client: &str,
    error: Option<&str>,
    user: &str,
) -> Response {
    let hidden = [
        ("response_type", q.response_type.as_str()),
        ("client_id", q.client_id.as_str()),
        ("redirect_uri", q.redirect_uri.as_str()),
        ("code_challenge", q.code_challenge.as_str()),
        (
            "code_challenge_method",
            q.code_challenge_method.as_deref().unwrap_or(""),
        ),
        ("state", q.state.as_deref().unwrap_or("")),
        ("scope", q.scope.as_deref().unwrap_or("")),
        ("resource", q.resource.as_deref().unwrap_or("")),
    ]
    .iter()
    .map(|(k, v)| format!("<input type=\"hidden\" name=\"{k}\" value=\"{}\">", esc(v)))
    .collect::<String>();
    let err = error
        .map(|e| format!("<p class=\"e\">{}</p>", esc(e)))
        .unwrap_or_default();
    let redirect_host = split_url(&q.redirect_uri)
        .map(|(_, a, _)| a.to_owned())
        .unwrap_or_default();
    page(
        if error.is_some() { StatusCode::UNAUTHORIZED } else { StatusCode::OK },
        format!(
            "<h1>Connect {client} to WYRM {site}</h1>\
<p><small>{client} (returns to {rh}) asks to work on this broker network as a gateway user. \
It can do what that user's role allows, and no more.</small></p>{err}\
<form method=\"post\" action=\"/oauth/authorize\">{hidden}\
<label for=\"u\">User</label><input id=\"u\" type=\"text\" name=\"user\" value=\"{user}\" autocomplete=\"username\" required>\
<label for=\"p\">Password</label><input id=\"p\" type=\"password\" name=\"password\" autocomplete=\"current-password\" required>\
<div class=\"c\"><input id=\"w\" type=\"checkbox\" name=\"write\" value=\"on\" checked><label for=\"w\">Allow changes: write values, run actions (after a dry run you approve in the chat)</label></div>\
<div class=\"c\"><input id=\"g\" type=\"checkbox\" name=\"config\" value=\"on\"><label for=\"g\">Allow config-level changes: devices, anything under <code>sys</code>, dataflow deploys</label></div>\
<button type=\"submit\" name=\"decision\" value=\"allow\">Sign in and allow</button>\
<button type=\"submit\" name=\"decision\" value=\"deny\" formnovalidate>Deny</button></form>",
            client = esc(client),
            site = esc(st.gw.site()),
            rh = esc(&redirect_host),
            user = esc(user),
        ),
    )
}

fn redirect(o: &OAuth, q: &AuthorizeQuery, params: &[(&str, &str)]) -> Response {
    let mut url = q.redirect_uri.clone();
    url.push(if url.contains('?') { '&' } else { '?' });
    let mut all: Vec<(&str, &str)> = params.to_vec();
    if let Some(s) = q.state.as_deref() {
        all.push(("state", s));
    }
    all.push(("iss", o.issuer()));
    url.push_str(
        &all.iter()
            .map(|(k, v)| format!("{k}={}", pct(v)))
            .collect::<Vec<_>>()
            .join("&"),
    );
    let mut r = StatusCode::FOUND.into_response();
    if let Ok(v) = HeaderValue::from_str(&url) {
        r.headers_mut().insert(LOCATION, v);
    }
    r.headers_mut()
        .insert(CACHE_CONTROL, HeaderValue::from_static("no-store"));
    r
}

/// Percent-encode everything but the unreserved characters (RFC 3986).
fn pct(s: &str) -> String {
    let mut o = String::new();
    for b in s.bytes() {
        if b.is_ascii_alphanumeric() || matches!(b, b'-' | b'.' | b'_' | b'~') {
            o.push(b as char);
        } else {
            o.push_str(&format!("%{b:02X}"));
        }
    }
    o
}

pub(crate) async fn authorize_page(
    State(st): State<AppState>,
    Query(q): Query<AuthorizeQuery>,
) -> Response {
    let Some(o) = st.gw.oauth.as_ref() else {
        return not_enabled();
    };
    match o.check_request(&q) {
        Ok(name) => login_form(&st, &q, &name, None, ""),
        Err(e) => error_page(&e),
    }
}

pub(crate) async fn authorize_submit(
    State(st): State<AppState>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
    Form(f): Form<AuthorizeForm>,
) -> Response {
    let Some(o) = st.gw.oauth.as_ref() else {
        return not_enabled();
    };
    let name = match o.check_request(&f.q) {
        Ok(n) => n,
        Err(e) => return error_page(&e),
    };
    if f.decision != "allow" {
        return redirect(o, &f.q, &[("error", "access_denied")]);
    }
    let user = f.user.trim().to_owned();
    let password = Zeroizing::new(f.password);
    if user.is_empty() || user.len() > 64 || password.len() > crate::users::MAX_PASSWORD {
        return login_form(&st, &f.q, &name, Some("wrong user or password"), &user);
    }
    let r = match st.gw.check_limit(&user, peer.ip()) {
        Err(e) => Err(e),
        Ok(()) => {
            let Ok(_permit) = st.gw.hashing.acquire().await else {
                return error_page("the gateway is stopping");
            };
            let gw = st.gw.clone();
            let u = user.clone();
            match tokio::task::spawn_blocking(move || gw.verify_login(&u, password, peer.ip()))
                .await
            {
                Ok(r) => r,
                Err(_) => return error_page("login failed"),
            }
        }
    };
    let gen = match r {
        Ok((_, gen)) => gen,
        Err(LoginError::Invalid) => {
            return login_form(&st, &f.q, &name, Some("wrong user or password"), &user)
        }
        Err(LoginError::RateLimited) => {
            return login_form(
                &st,
                &f.q,
                &name,
                Some("too many failed logins: wait a minute"),
                &user,
            )
        }
    };
    let consent = Consent {
        write: f.write.is_some(),
        config: f.write.is_some() && f.config.is_some(),
    };
    let Some(code) = o.new_code(Code {
        client_id: f.q.client_id.clone(),
        redirect_uri: f.q.redirect_uri.clone(),
        challenge: f.q.code_challenge.clone(),
        sub: user.clone(),
        gen,
        consent,
        client: name.clone(),
        exp: now_s() + CODE_TTL_S,
    }) else {
        return error_page("too many sign-ins in progress: try again in a minute");
    };
    st.gw.audit(crate::AuditEvent::McpGranted {
        user: user.clone(),
        client: name.clone(),
        write: consent.write,
        config: consent.config,
    });
    redirect(o, &f.q, &[("code", &code)])
}

// ---------- token ----------

#[derive(Deserialize)]
pub(crate) struct TokenForm {
    #[serde(default)]
    grant_type: String,
    code: Option<String>,
    redirect_uri: Option<String>,
    client_id: Option<String>,
    code_verifier: Option<String>,
    refresh_token: Option<String>,
}

fn s256(verifier: &str) -> String {
    URL_SAFE_NO_PAD.encode(Sha256::digest(verifier.as_bytes()))
}

/// Constant time on equal lengths.
fn same(a: &str, b: &str) -> bool {
    a.len() == b.len() && a.bytes().zip(b.bytes()).fold(0u8, |x, (p, q)| x | (p ^ q)) == 0
}

pub(crate) async fn token(
    State(st): State<AppState>,
    headers: HeaderMap,
    body: axum::body::Bytes,
) -> Response {
    let Some(o) = st.gw.oauth.as_ref() else {
        return not_enabled();
    };
    let form_ok = headers
        .get(CONTENT_TYPE)
        .and_then(|v| v.to_str().ok())
        .is_some_and(|v| v.starts_with("application/x-www-form-urlencoded"));
    let Some(f) = form_ok
        .then(|| serde_urlencoded::from_bytes::<TokenForm>(&body).ok())
        .flatten()
    else {
        return oauth_error(StatusCode::BAD_REQUEST, "invalid_request", "a form body");
    };
    let client_id = f.client_id.clone().unwrap_or_default();
    let (sub, gen, consent, client) = match f.grant_type.as_str() {
        "authorization_code" => {
            let Some(c) = f.code.as_deref().and_then(|c| o.take_code(c)) else {
                return oauth_error(
                    StatusCode::BAD_REQUEST,
                    "invalid_grant",
                    "unknown or used code",
                );
            };
            let verifier = f.code_verifier.as_deref().unwrap_or("");
            if !same(&c.client_id, &client_id)
                || f.redirect_uri.as_deref() != Some(c.redirect_uri.as_str())
                || !(43..=128).contains(&verifier.len())
                || !same(&s256(verifier), &c.challenge)
            {
                return oauth_error(
                    StatusCode::BAD_REQUEST,
                    "invalid_grant",
                    "code, client, redirect URI or PKCE verifier do not match",
                );
            }
            (c.sub, c.gen, c.consent, c.client)
        }
        "refresh_token" => {
            let Some((a, bound)) = f
                .refresh_token
                .as_deref()
                .and_then(|t| o.open_token(KIND_REFRESH, t))
            else {
                return oauth_error(
                    StatusCode::BAD_REQUEST,
                    "invalid_grant",
                    "unknown or expired refresh token",
                );
            };
            if !same(&bound, &client_id) {
                return oauth_error(
                    StatusCode::BAD_REQUEST,
                    "invalid_grant",
                    "another client's token",
                );
            }
            (a.sub, a.gen, a.consent, a.client)
        }
        _ => {
            return oauth_error(
                StatusCode::BAD_REQUEST,
                "unsupported_grant_type",
                "authorization_code or refresh_token",
            )
        }
    };
    // the user as now: removed, disabled or a new password ends the grant
    match st.gw.user(&sub) {
        Some(u) if !u.disabled && u.gen == gen => {}
        _ => {
            return oauth_error(
                StatusCode::BAD_REQUEST,
                "invalid_grant",
                "the user's sign-in is no longer valid",
            )
        }
    }
    let g = Granted {
        sub: &sub,
        gen,
        consent,
        client: &client,
        client_id: &client_id,
    };
    let (access, exp) = o.mint(KIND_ACCESS, &g, o.cfg.access_ttl);
    let (refresh, _) = o.mint(KIND_REFRESH, &g, o.cfg.refresh_ttl);
    json(
        StatusCode::OK,
        serde_json::json!({
            "access_token": access,
            "token_type": "Bearer",
            "expires_in": exp.saturating_sub(now_s()),
            "refresh_token": refresh,
            "scope": SCOPE,
        }),
    )
}

/// `{access_token…}` claims for tests and the MCP endpoint.
pub(crate) fn session_claims(a: &Access) -> crate::SessionClaims {
    crate::SessionClaims {
        sub: a.sub.clone(),
        roles: Vec::new(),
        exp: a.exp,
        iat: a.iat,
        jti: a.jti,
        gen: a.gen,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn o() -> OAuth {
        OAuth::new(McpConfig::new("https://broker.example"), b"k").unwrap()
    }

    #[test]
    fn config_is_checked() {
        for bad in [
            "http://broker.example",
            "https://broker.example/x",
            "ftp://x",
            "https://",
        ] {
            assert!(OAuth::new(McpConfig::new(bad), b"k").is_err(), "{bad}");
        }
        assert!(OAuth::new(McpConfig::new("http://127.0.0.1:8445"), b"k").is_ok());
        let mut c = McpConfig::new("https://b.example");
        c.redirect_uris = vec!["http://evil.example/cb".into()];
        assert!(OAuth::new(c, b"k").is_err());
        assert_eq!(o().hosts(), vec!["broker.example".to_owned()]);
        assert_eq!(
            OAuth::new(McpConfig::new("https://b.example:8445"), b"k")
                .unwrap()
                .hosts(),
            vec!["b.example:8445".to_owned(), "b.example".to_owned()]
        );
    }

    #[test]
    fn redirects_on_the_allowlist_only() {
        let o = o();
        assert!(o.redirect_allowed("https://claude.ai/api/mcp/auth_callback"));
        assert!(o.redirect_allowed("http://localhost:33418/callback"));
        assert!(o.redirect_allowed("http://127.0.0.1:5000/cb?x=1"));
        for bad in [
            "https://claude.ai/api/mcp/auth_callback/x",
            "https://evil.example/api/mcp/auth_callback",
            "http://localhost/callback",
            "http://localhost.evil.example:80/cb",
            "http://user@127.0.0.1:1/cb",
            "https://claude.ai/api/mcp/auth_callback#f",
        ] {
            assert!(!o.redirect_allowed(bad), "{bad}");
        }
    }

    #[test]
    fn tokens_do_not_cross() {
        let o = o();
        let c = Consent {
            write: true,
            config: false,
        };
        let (a, _) = o.mint(
            KIND_ACCESS,
            &Granted {
                sub: "olena",
                gen: 3,
                consent: c,
                client: "Claude",
                client_id: "cid",
            },
            Duration::from_secs(60),
        );
        let (r, _) = o.mint(
            KIND_REFRESH,
            &Granted {
                sub: "olena",
                gen: 3,
                consent: c,
                client: "Claude",
                client_id: "cid",
            },
            Duration::from_secs(60),
        );
        let got = o.access(&a).unwrap();
        assert_eq!((got.sub.as_str(), got.gen, got.consent), ("olena", 3, c));
        assert!(o.access(&r).is_none(), "a refresh token is no access token");
        assert_eq!(o.open_token(KIND_REFRESH, &r).unwrap().1, "cid");
        assert!(o.client(&a).is_none());
    }

    #[test]
    fn pkce_and_escaping() {
        // RFC 7636 appendix B
        assert_eq!(
            s256("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
            "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        );
        assert_eq!(
            esc("<a href=\"x\">&'"),
            "&lt;a href=&quot;x&quot;&gt;&amp;&#39;"
        );
        assert_eq!(pct("a b/c?d"), "a%20b%2Fc%3Fd");
    }
}
