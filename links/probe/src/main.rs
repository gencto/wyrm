//! `wyrm-link-probe`: the probe link as a process (a link package).

fn main() -> std::process::ExitCode {
    // logs, the supervisor's limits, a runtime, then `process::run`
    wyrm_link_sdk::process::main::<wyrm_link_probe::Probe>()
}
