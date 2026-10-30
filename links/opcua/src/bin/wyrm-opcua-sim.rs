//! OPC UA server simulator for demos: the variables of
//! `wyrm_link_opcua::sim` (a Double that counts up every 100 ms, writable
//! Setpoint/Small/Text/Flags, a Bad and an Uncertain node), endpoints None
//! and Basic256Sha256 (Sign, SignAndEncrypt), anonymous or
//! `operator`/`sim-password`.

use clap::Parser;
use std::path::PathBuf;
use wyrm_link_opcua::sim;

#[derive(Parser, Debug)]
#[command(version, about = "OPC UA server simulator")]
struct Args {
    /// Port on 127.0.0.1.
    #[arg(long, default_value_t = 4840)]
    port: u16,
    /// The server's certificate and trust lists (made on first start).
    #[arg(long, default_value = "opcua-sim-pki")]
    pki: PathBuf,
    /// Refuse client certificates the server does not trust yet (they go
    /// to `<pki>/rejected`; move one to `<pki>/trusted` to trust it).
    #[arg(long)]
    strict_clients: bool,
}

#[tokio::main]
async fn main() -> std::io::Result<()> {
    let args = Args::parse();
    let s = sim::spawn(sim::Options {
        port: args.port,
        pki_dir: args.pki,
        strict_clients: args.strict_clients,
        ..Default::default()
    })
    .await?;
    println!(
        "opc ua sim on {} (namespace {} = {})",
        s.url(),
        s.ns,
        sim::NS
    );
    tokio::signal::ctrl_c().await?;
    s.stop().await;
    Ok(())
}
