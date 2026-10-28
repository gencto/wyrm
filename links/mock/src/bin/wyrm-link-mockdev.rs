//! The framework mock (mockdev) as a package binary (ADR 0011, 0021).

fn main() -> std::process::ExitCode {
    wyrm_link_sdk::process::main::<wyrm_link_sdk::driver::Framework<wyrm_link_mock::df::MockDev>>()
}
