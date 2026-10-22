//! Write the example components to a directory (used by
//! `examples/packages/build.sh`):
//!
//! - `register.wasm`: no network; `read` gives a register (initially 7),
//!   `write` stores a CBOR uint below 24.
//! - `tcp-ping.wasm`: `init` takes the port (JSON number); `read` connects
//!   to `127.0.0.1:<port>`, sends `ping` and returns the reply as the
//!   reading (needs `127.0.0.1:<port>` in the connection's `net` list).
//!
//! Both are written by hand in the component text format (the WAT test
//! guests of `wyrm-wasm-host`); a real component comes from a guest
//! toolchain for the WIT world `wyrm:link/driver`.

#[path = "../../../crates/wyrm-wasm-host/tests/guests/mod.rs"]
mod guests;

fn main() -> std::io::Result<()> {
    let dir = std::path::PathBuf::from(std::env::args().nth(1).unwrap_or_else(|| ".".into()));
    std::fs::create_dir_all(&dir)?;
    std::fs::write(dir.join("register.wasm"), guests::register())?;
    std::fs::write(dir.join("tcp-ping.wasm"), guests::tcp_ping())?;
    println!("{}", dir.display());
    Ok(())
}
