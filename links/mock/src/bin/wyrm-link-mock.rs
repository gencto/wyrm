//! Standalone mock connector: connects to a router and serves the mock tree.

use clap::Parser;
use wyrm_link_mock::{Mock, MockConfig};
use wyrm_link_sdk::{LinkConfig, VerifyingKey};

#[derive(Parser, Debug)]
#[command(version, about = "WYRM mock connector")]
struct Args {
    /// Router endpoint.
    #[arg(long, default_value = "tcp/127.0.0.1:7447")]
    connect: String,
    #[arg(long, default_value = "local")]
    site: String,
    #[arg(long, default_value = "mock")]
    link: String,
    #[arg(long, default_value_t = 10)]
    points: usize,
    /// Updates per point per second (0 = static).
    #[arg(long, default_value_t = 1.0)]
    rate: f64,
    #[arg(long, default_value_t = 1)]
    depth: usize,
    #[arg(long, default_value_t = 4)]
    fanout: usize,
    /// Admin ptok public key, 32 bytes hex. Repeat for the previous key.
    #[arg(long = "admin-key")]
    admin_keys: Vec<String>,
}

#[tokio::main]
async fn main() -> Result<(), zenoh::Error> {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .init();
    let args = Args::parse();

    let mut zc = zenoh::Config::default();
    zc.insert_json5("mode", r#""client""#)?;
    zc.insert_json5("connect/endpoints", &format!("[\"{}\"]", args.connect))?;
    zc.insert_json5("scouting/multicast/enabled", "false")?;
    let session = zenoh::open(zc).await?;

    let mut lcfg = LinkConfig::new(args.site, args.link);
    for k in &args.admin_keys {
        let bytes: [u8; 32] = hex::decode(k)?
            .try_into()
            .map_err(|_| "admin key must be 32 bytes")?;
        lcfg.admin_keys.push(VerifyingKey::from_bytes(&bytes)?);
    }
    if lcfg.admin_keys.is_empty() {
        tracing::warn!("no --admin-key: every set/invoke will be denied");
    }
    let cfg = MockConfig {
        points: args.points,
        rate_hz: args.rate,
        depth: args.depth,
        fanout: args.fanout,
        writable: true,
    };
    let handle = wyrm_link_sdk::spawn::<Mock>(session.clone(), lcfg, cfg).await?;
    tracing::info!(prefix = %handle.ctx().key("", ""), "mock link up");
    tokio::signal::ctrl_c().await?;
    handle.stop().await;
    session.close().await?;
    Ok(())
}
