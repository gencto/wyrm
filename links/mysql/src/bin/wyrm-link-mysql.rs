//! The MySQL history sync as a process link, supervised by `wyrmd`.

use wyrm_link_portable::Portable;

fn main() -> std::process::ExitCode {
    wyrm_link_sdk::process::main::<Portable<wyrm_link_mysql::MySync>>()
}
