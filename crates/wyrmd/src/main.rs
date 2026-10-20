use clap::{Parser, Subcommand};
use wyrmd::{Config, Daemon, Error};

#[derive(Parser, Debug)]
#[command(version, about = "WYRM broker")]
struct Args {
    /// Path to wyrmd.json5.
    #[arg(short, long, default_value = "wyrmd.json5", global = true)]
    config: std::path::PathBuf,
    #[command(subcommand)]
    cmd: Option<Cmd>,
}

#[derive(Subcommand, Debug)]
enum Cmd {
    /// Validate the config and exit.
    Check,
    /// Host one driver as a supervised link process (started by wyrmd).
    Link { driver: String },
}

#[tokio::main]
async fn main() -> Result<(), Error> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "info,zenoh=warn".into()),
        )
        .init();
    let args = Args::parse();
    if let Some(Cmd::Link { driver }) = &args.cmd {
        return wyrmd::run_link(driver).await;
    }
    let text = std::fs::read_to_string(&args.config)
        .map_err(|e| format!("{}: {e}", args.config.display()))?;
    let cfg = Config::from_json5(&text)?;
    if matches!(args.cmd, Some(Cmd::Check)) {
        println!("ok");
        return Ok(());
    }
    if cfg.admin_keys.is_empty() {
        tracing::warn!("no admin_keys: every set/invoke will be denied");
    }
    let daemon = Daemon::open(cfg, std::env::current_exe()?)?;
    daemon
        .run_until(async {
            let _ = tokio::signal::ctrl_c().await;
            tracing::info!("stopping");
        })
        .await
}
