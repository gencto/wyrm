//! The agent connector as a supervised process (`wyrm-link-sdk::process`):
//! params, admin keys and secrets (`anthropic_api_key`, `agent_key`) come
//! from the admin's `hello` reply.

use wyrm_link_agent::Agent;

#[tokio::main]
async fn main() -> std::process::ExitCode {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .init();
    match wyrm_link_sdk::process::run::<Agent>().await {
        Ok(()) => std::process::ExitCode::SUCCESS,
        Err(e) => {
            tracing::error!("agent link: {e}");
            std::process::ExitCode::FAILURE
        }
    }
}
