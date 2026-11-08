//! `slack` as a process link, supervised by `wyrmd` (`wyr link pack --kind process`).

use wyrm_link_portable::Portable;

fn main() -> std::process::ExitCode {
    wyrm_link_sdk::process::main::<Portable<wyrm_link_slack::SlackLink>>()
}
