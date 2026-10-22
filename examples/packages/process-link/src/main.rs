//! A link package binary (ADR 0011): the broker starts it as a process
//! link and hands it everything through the environment (`WYRM_SITE`,
//! `WYRM_LINK_ID`, `WYRM_ENDPOINT`, certificate, token file, data dir,
//! limits). `process::run` connects with mTLS, says `hello` (params,
//! secrets, trusted keys) and serves the link's tree until the broker
//! goes away.
//!
//! This one runs the `mockdev` framework driver: connections, devices and
//! points come from its own Add actions in the tree. A real package puts its
//! own driver here.

use wyrm_link_mock::df::MockDev;
use wyrm_link_sdk::driver::Framework;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "info,zenoh=warn".into()),
        )
        .init();
    // Before the runtime: some limits reach only threads created later.
    wyrm_link_sdk::limits::apply_from_env()?;
    tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()?
        .block_on(wyrm_link_sdk::process::run::<Framework<MockDev>>())?;
    Ok(())
}
