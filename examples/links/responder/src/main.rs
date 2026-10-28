//! A link package binary (ADR 0011): the broker starts it as a process
//! link and hands it everything through the environment (`WYRM_SITE`,
//! `WYRM_LINK_ID`, `WYRM_ENDPOINT`, certificate, token file, data dir,
//! limits). `process::main` sets up logs, the limits and a runtime;
//! `process::run` connects with mTLS, says `hello` (params, secrets,
//! trusted keys) and serves the link's tree until the broker goes away.
//!
//! This one runs the `mockdev` framework driver: connections, devices and
//! points come from its own Add actions in the tree. A real package puts its
//! own driver here.

use wyrm_link_mock::df::MockDev;
use wyrm_link_sdk::driver::Framework;

fn main() -> std::process::ExitCode {
    // logs, the supervisor's limits, a runtime, then `process::run`
    wyrm_link_sdk::process::main::<Framework<MockDev>>()
}
