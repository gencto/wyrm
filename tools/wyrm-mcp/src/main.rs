//! `wyrm-mcp` — MCP server over the WYRM tree. stdio by default (Claude Code,
//! Claude Desktop); `--http <loopback addr>` serves streamable HTTP on `/mcp`.
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

async fn serve_stdio(server: WyrmMcp) -> Result<(), Error> {
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
async fn serve_http(server: WyrmMcp, addr: std::net::SocketAddr) -> Result<(), Error> {
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
    let router = axum::Router::new().nest_service("/mcp", service);
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

#[cfg(not(feature = "http"))]
async fn serve_http(_server: WyrmMcp, _addr: std::net::SocketAddr) -> Result<(), Error> {
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
    }
}
