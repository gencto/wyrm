//! `scheduler` as a process link, supervised by `wyrmd` (`wyr link pack --kind process`).
//! The broker hands it everything through the environment; `process::main` sets up logs, the
//! supervisor's limits and a runtime, then serves the app on the native adapter.

use wyrm_link_portable::Portable;

fn main() -> std::process::ExitCode {
    wyrm_link_sdk::process::main::<Portable<wyrm_link_scheduler::Scheduler>>()
}
