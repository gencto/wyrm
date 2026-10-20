//! The agent connector as a supervised process (`wyrm-link-sdk::process`):
//! params, admin keys and secrets (`anthropic_api_key`, `agent_key`) come
//! from the admin's `hello` reply.

use wyrm_link_agent::Agent;

fn main() -> std::process::ExitCode {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .init();
    // Before the runtime: no_new_privs reaches only later threads.
    if let Err(e) = wyrm_link_sdk::limits::apply_from_env() {
        tracing::error!("agent link: {e}");
        return std::process::ExitCode::FAILURE;
    }
    let rt = match tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()
    {
        Ok(rt) => rt,
        Err(e) => {
            tracing::error!("agent link: runtime: {e}");
            return std::process::ExitCode::FAILURE;
        }
    };
    match rt.block_on(wyrm_link_sdk::process::run::<Agent>()) {
        Ok(()) => std::process::ExitCode::SUCCESS,
        Err(e) => {
            tracing::error!("agent link: {e}");
            std::process::ExitCode::FAILURE
        }
    }
}
