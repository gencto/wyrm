//! `wyrm-link-probe`: the probe link as a process (a link package).

fn main() -> std::result::Result<(), Box<dyn std::error::Error>> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "info,zenoh=warn".into()),
        )
        .init();
    wyrm_link_sdk::limits::apply_from_env()?;
    tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()?
        .block_on(wyrm_link_sdk::process::run::<wyrm_link_probe::Probe>())?;
    Ok(())
}
