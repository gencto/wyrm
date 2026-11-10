//! `wyrm-mcp` — MCP server over the WYRM tree. stdio by default (Claude Code,
//! Claude Desktop); `--http <loopback addr>` serves streamable HTTP on `/mcp`.
//!
//! Two ways to the tree: with `--gateway <url>` (the Claude Desktop connector,
//! ADR 0041) it logs in to a user gateway as `--user` (password from
//! `WYR_GATEWAY_PASSWORD`) and that user's role decides; without it, it talks
//! Zenoh to a router as the service account `ai:<agent>` (ADR 0005).
//!
//! stdout is the JSON-RPC channel on stdio: logs go to stderr only.

use clap::Parser;
use std::path::{Path, PathBuf};
use std::time::Duration;
use tracing::Level;
use tracing_subscriber::filter::filter_fn;
use tracing_subscriber::prelude::*;
use tracing_subscriber::EnvFilter;
use wyrm_client::WyrmClient;
use wyrm_mcp::{Options, WyrmMcp};
use zeroize::Zeroizing;

type Error = Box<dyn std::error::Error + Send + Sync>;

#[derive(Parser, Debug)]
#[command(version, about = "WYRM MCP server (tools over the node tree)")]
struct Cli {
    /// Router endpoint.
    #[arg(long, env = "WYRM_CONNECT", default_value = "tcp/127.0.0.1:7447")]
    connect: String,
    /// Site to work on (`wy/<site>/…`).
    #[arg(long, env = "WYRM_SITE", default_value = "local")]
    site: String,
    /// Service signing key file (hex seed, as for `wyr --key`). Without it the
    /// server is read-only.
    #[arg(long, env = "WYRM_MCP_KEY")]
    key: Option<PathBuf>,
    /// Agent name: requests are signed with subject `ai:<name>`.
    #[arg(long = "agent-name", env = "WYRM_AGENT_NAME", default_value = "claude")]
    agent_name: String,
    /// CA certificate for `tls/`/`quic/` endpoints.
    #[arg(long, env = "WYR_CA")]
    ca: Option<PathBuf>,
    /// Client certificate for `tls/`/`quic/` endpoints.
    #[arg(long, env = "WYR_CERT")]
    cert: Option<PathBuf>,
    /// Private key of `--cert`.
    #[arg(long = "tls-key", env = "WYR_TLS_KEY")]
    tls_key: Option<PathBuf>,
    /// Request timeout, seconds.
    #[arg(long, default_value_t = 10)]
    timeout: u64,
    /// Serve streamable HTTP on this loopback address (e.g. 127.0.0.1:8765)
    /// instead of stdio. There is no client authentication: every local
    /// process that reaches the port acts as the service account.
    #[arg(long)]
    http: Option<std::net::SocketAddr>,
    /// Work through this user gateway (`https://host[:port]`, or
    /// `http://127.0.0.1:<port>` on this host) as `--user`; the password comes
    /// from WYR_GATEWAY_PASSWORD. Replaces --connect/--key.
    #[arg(long, env = "WYR_GATEWAY")]
    gateway: Option<String>,
    /// Gateway user (with --gateway).
    #[arg(long, env = "WYR_GATEWAY_USER", default_value = "admin")]
    user: String,
    /// PEM roots of the gateway's TLS certificate (a broker CA or a
    /// self-signed one); without it the public web roots. Empty = none.
    #[arg(long = "gateway-ca", env = "WYR_GATEWAY_CA")]
    gateway_ca: Option<String>,
    /// Refuse every change (with --gateway; also WYRM_MCP_READ_ONLY=true).
    #[arg(long)]
    read_only: bool,
    /// Let config-level changes through (with --gateway; the role still
    /// decides; also WYRM_MCP_ALLOW_CONFIG=true).
    #[arg(long)]
    allow_config: bool,
}

#[tokio::main]
async fn main() {
    // stderr only. rmcp logs whole requests (with approval tokens) at debug,
    // so its events are dropped below warn whatever RUST_LOG says (a more
    // specific directive such as `rmcp::service=debug` cannot re-enable them).
    let filter = EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("warn"));
    let no_rmcp_debug = filter_fn(|m| !m.target().starts_with("rmcp") || *m.level() <= Level::WARN);
    tracing_subscriber::registry()
        .with(
            tracing_subscriber::fmt::layer()
                .with_writer(std::io::stderr)
                .with_ansi(false)
                .with_filter(no_rmcp_debug),
        )
        .with(filter)
        .init();
    let cli = Cli::parse();
    if let Err(e) = run(cli).await {
        eprintln!("wyrm-mcp: {e}");
        std::process::exit(1);
    }
}

async fn run(cli: Cli) -> Result<(), Error> {
    if let Some(addr) = cli.http {
        check_http_addr(addr)?;
    }
    if let Some(url) = cli.gateway.as_deref().and_then(given).map(str::to_owned) {
        return run_gateway(cli, url).await;
    }
    let key = cli.key.as_deref().map(load_key).transpose()?;
    if key.is_none() {
        tracing::warn!("no --key: read-only (set/invoke/deploy are refused)");
    }
    let session = zenoh::open(zenoh_config(&cli)?).await?;
    let client = WyrmClient::new(session).with_timeout(Duration::from_secs(cli.timeout));
    let server = WyrmMcp::new(
        client,
        Options {
            site: cli.site.clone(),
            agent_name: cli.agent_name.clone(),
            key,
            timeout: Duration::from_secs(cli.timeout),
        },
    );
    match cli.http {
        None => serve_stdio(server).await,
        Some(addr) => serve_http(server, addr).await,
    }
}

#[cfg(feature = "gateway")]
async fn run_gateway(cli: Cli, url: String) -> Result<(), Error> {
    use wyrm_mcp::gateway::{GatewayMcp, GatewayOptions};
    let password = Zeroizing::new(std::env::var("WYR_GATEWAY_PASSWORD").map_err(|_| {
        "--gateway: set WYR_GATEWAY_PASSWORD to the gateway user's password".to_owned()
    })?);
    if password.is_empty() {
        return Err("--gateway: WYR_GATEWAY_PASSWORD is empty".into());
    }
    let ca = cli.gateway_ca.as_deref().and_then(given).map(PathBuf::from);
    let endpoint = wyrm_gateway_client::Endpoint::parse(&url, ca.as_deref())?;
    let server = GatewayMcp::new(GatewayOptions {
        endpoint,
        url: url.clone(),
        user: cli.user.clone(),
        password,
        read_only: cli.read_only || env_flag("WYRM_MCP_READ_ONLY"),
        allow_config: cli.allow_config || env_flag("WYRM_MCP_ALLOW_CONFIG"),
    });
    // A wrong password or an unreachable gateway is only a warning: the
    // client shows the error of the first tool call, and a gateway that comes
    // up later is found then.
    match server.check().await {
        Ok(me) => tracing::warn!(
            "gateway {url}: logged in as {} (site {}, max {})",
            me.sub,
            me.site,
            me.max
        ),
        Err(e) => tracing::warn!("{e}"),
    }
    match cli.http {
        None => serve_stdio(server).await,
        Some(addr) => serve_http(server, addr).await,
    }
}

/// A setting as given, `None` when empty or a placeholder a client left
/// unfilled (`${user_config.x}` of a Claude Desktop extension).
fn given(s: &str) -> Option<&str> {
    let s = s.trim();
    (!s.is_empty() && !s.starts_with("${")).then_some(s)
}

/// On only for `true`, `1`, `yes`, `on`: anything else (unset, a typo, an
/// unfilled placeholder) leaves the switch off.
fn env_flag(name: &str) -> bool {
    std::env::var(name).is_ok_and(|v| {
        matches!(
            v.trim().to_ascii_lowercase().as_str(),
            "true" | "1" | "yes" | "on"
        )
    })
}

#[cfg(not(feature = "gateway"))]
async fn run_gateway(_cli: Cli, _url: String) -> Result<(), Error> {
    Err("built without the `gateway` feature".into())
}

async fn serve_stdio<S>(server: S) -> Result<(), Error>
where
    S: rmcp::ServerHandler,
{
    use rmcp::ServiceExt;
    let running = server.serve(rmcp::transport::stdio()).await?;
    running.waiting().await?;
    Ok(())
}

/// Only loopback: the HTTP transport has neither TLS nor client auth.
fn check_http_addr(addr: std::net::SocketAddr) -> Result<(), Error> {
    if addr.ip().is_loopback() {
        Ok(())
    } else {
        Err(format!(
            "--http {addr}: only loopback addresses are served (no TLS and no client \
             authentication on the MCP HTTP transport)"
        )
        .into())
    }
}

#[cfg(feature = "http")]
async fn serve_http<S>(server: S, addr: std::net::SocketAddr) -> Result<(), Error>
where
    S: rmcp::ServerHandler + Clone + Send + Sync + 'static,
{
    use rmcp::transport::streamable_http_server::{
        session::local::LocalSessionManager, StreamableHttpServerConfig, StreamableHttpService,
    };
    let config = StreamableHttpServerConfig::default();
    let ct = config.cancellation_token.clone();
    let service = StreamableHttpService::new(
        move || Ok(server.clone()),
        LocalSessionManager::default().into(),
        config,
    );
    // Loopback is not enough: a web page can reach it via DNS rebinding.
    // Every request needs the right Host, no browser Origin, and a bearer
    // token (from WYRM_MCP_HTTP_TOKEN, or random and printed once here).
    let token = match std::env::var(HTTP_TOKEN_ENV) {
        Ok(t) if t.len() >= 32 => t,
        Ok(_) => return Err(format!("{HTTP_TOKEN_ENV}: at least 32 characters").into()),
        Err(_) => {
            let mut raw = [0u8; 32];
            getrandom::fill(&mut raw).map_err(|e| format!("no randomness: {e}"))?;
            let t: String = raw.iter().map(|b| format!("{b:02x}")).collect();
            eprintln!("wyrm-mcp: HTTP bearer token (send as Authorization: Bearer): {t}");
            t
        }
    };
    let port = addr.port();
    let token = std::sync::Arc::new(token);
    let router =
        axum::Router::new()
            .nest_service("/mcp", service)
            .layer(axum::middleware::from_fn(
                move |req: axum::extract::Request, next: axum::middleware::Next| {
                    let token = token.clone();
                    async move {
                        if http_allowed(req.headers(), port, &token) {
                            next.run(req).await
                        } else {
                            axum::response::IntoResponse::into_response(
                                axum::http::StatusCode::FORBIDDEN,
                            )
                        }
                    }
                },
            ));
    let listener = tokio::net::TcpListener::bind(addr).await?;
    eprintln!("wyrm-mcp: streamable HTTP on http://{addr}/mcp");
    axum::serve(listener, router)
        .with_graceful_shutdown(async move {
            let _ = tokio::signal::ctrl_c().await;
            ct.cancel();
        })
        .await?;
    Ok(())
}

#[cfg(feature = "http")]
const HTTP_TOKEN_ENV: &str = "WYRM_MCP_HTTP_TOKEN";

/// Host is a loopback name with our port, no `Origin` (browsers send one;
/// MCP clients do not), and `Authorization: Bearer <token>` (constant-time).
#[cfg(feature = "http")]
fn http_allowed(h: &axum::http::HeaderMap, port: u16, token: &str) -> bool {
    use axum::http::header::{AUTHORIZATION, HOST, ORIGIN};
    let host_ok = h.get(HOST).and_then(|v| v.to_str().ok()).is_some_and(|v| {
        [
            format!("127.0.0.1:{port}"),
            format!("localhost:{port}"),
            format!("[::1]:{port}"),
        ]
        .iter()
        .any(|ok| ok == v)
    });
    let bearer = h
        .get(AUTHORIZATION)
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.strip_prefix("Bearer "))
        .unwrap_or("");
    let token_ok = bearer.len() == token.len()
        && bearer
            .bytes()
            .zip(token.bytes())
            .fold(0u8, |acc, (a, b)| acc | (a ^ b))
            == 0;
    host_ok && h.get(ORIGIN).is_none() && token_ok
}

#[cfg(not(feature = "http"))]
async fn serve_http<S>(_server: S, _addr: std::net::SocketAddr) -> Result<(), Error> {
    Err("built without the `http` feature".into())
}

fn zenoh_config(cli: &Cli) -> Result<zenoh::Config, Error> {
    let mut zc = zenoh::Config::default();
    zc.insert_json5("mode", r#""client""#)?;
    zc.insert_json5("connect/endpoints", &format!("[{:?}]", cli.connect))?;
    zc.insert_json5("scouting/multicast/enabled", "false")?;
    if let Some(tls) = tls_config(&cli.connect, &cli.ca, &cli.cert, &cli.tls_key)? {
        zc.insert_json5("transport/link/tls", &tls)?;
    }
    Ok(zc)
}

/// `transport/link/tls` for `tls/`/`quic/` endpoints (mTLS); `None` otherwise.
fn tls_config(
    endpoint: &str,
    ca: &Option<PathBuf>,
    cert: &Option<PathBuf>,
    key: &Option<PathBuf>,
) -> Result<Option<String>, Error> {
    if !(endpoint.starts_with("tls/") || endpoint.starts_with("quic/")) {
        return Ok(None);
    }
    let (Some(ca), Some(cert), Some(key)) = (ca, cert, key) else {
        return Err("tls/quic endpoints need --ca, --cert and --tls-key".into());
    };
    Ok(Some(format!(
        "{{ root_ca_certificate: {:?}, connect_certificate: {:?}, connect_private_key: {:?}, enable_mtls: true }}",
        ca.display().to_string(),
        cert.display().to_string(),
        key.display().to_string()
    )))
}

fn load_key(path: &Path) -> Result<ed25519_dalek::SigningKey, Error> {
    let text = Zeroizing::new(
        std::fs::read_to_string(path).map_err(|e| format!("{}: {e}", path.display()))?,
    );
    let seed = Zeroizing::new(hex::decode(text.trim())?);
    let seed: [u8; 32] = seed
        .as_slice()
        .try_into()
        .map_err(|_| "key file must hold a 32-byte hex seed")?;
    Ok(ed25519_dalek::SigningKey::from_bytes(&seed))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    #[cfg(feature = "http")]
    fn http_guard() {
        use axum::http::{HeaderMap, HeaderValue};
        let tok = "t".repeat(64);
        let mk = |host: &str, origin: Option<&str>, bearer: &str| {
            let mut h = HeaderMap::new();
            h.insert("host", HeaderValue::from_str(host).unwrap());
            if let Some(o) = origin {
                h.insert("origin", HeaderValue::from_str(o).unwrap());
            }
            h.insert(
                "authorization",
                HeaderValue::from_str(&format!("Bearer {bearer}")).unwrap(),
            );
            h
        };
        assert!(http_allowed(&mk("127.0.0.1:8765", None, &tok), 8765, &tok));
        assert!(http_allowed(&mk("localhost:8765", None, &tok), 8765, &tok));
        // DNS rebinding: foreign Host, or a browser Origin
        assert!(!http_allowed(
            &mk("evil.example:8765", None, &tok),
            8765,
            &tok
        ));
        assert!(!http_allowed(
            &mk("127.0.0.1:8765", Some("http://evil.example"), &tok),
            8765,
            &tok
        ));
        assert!(!http_allowed(
            &mk("127.0.0.1:8765", None, "wrong"),
            8765,
            &tok
        ));
        assert!(!http_allowed(&mk("127.0.0.1:9999", None, &tok), 8765, &tok));
    }

    #[test]
    fn http_only_on_loopback() {
        assert!(check_http_addr("127.0.0.1:8765".parse().unwrap()).is_ok());
        assert!(check_http_addr("[::1]:8765".parse().unwrap()).is_ok());
        assert!(check_http_addr("0.0.0.0:8765".parse().unwrap()).is_err());
        assert!(check_http_addr("192.168.1.10:8765".parse().unwrap()).is_err());
    }

    #[test]
    fn cli_parses() {
        let c = Cli::try_parse_from([
            "wyrm-mcp",
            "--site",
            "plant",
            "--key",
            "k",
            "--agent-name",
            "ops",
        ])
        .unwrap();
        assert_eq!(c.site, "plant");
        assert_eq!(c.agent_name, "ops");
        assert!(c.http.is_none());
        assert!(tls_config("tls/h:1", &None, &None, &None).is_err());
        assert!(c.gateway.is_none());
    }

    #[test]
    fn gateway_cli_parses() {
        let c = Cli::try_parse_from([
            "wyrm-mcp",
            "--gateway",
            "https://broker.example",
            "--user",
            "claude",
            "--read-only",
        ])
        .unwrap();
        assert_eq!(c.gateway.as_deref(), Some("https://broker.example"));
        assert_eq!(c.user, "claude");
        assert!(c.read_only && !c.allow_config);
    }

    #[test]
    fn unfilled_settings_are_absent() {
        assert_eq!(given("  "), None);
        assert_eq!(given("${user_config.gateway_ca}"), None);
        assert_eq!(given(" /etc/ca.pem "), Some("/etc/ca.pem"));
    }
}
