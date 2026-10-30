//! SNMP agent simulator for demos: community `public`, v3 users
//! `sha1user`, `sha256user` (both with AES) and `authonly` (passphrases
//! `<user>-pass`); the interface octet counters grow every second.

use clap::Parser;
use std::time::Duration;

#[derive(Parser, Debug)]
#[command(version, about = "SNMP v2c/v3 agent simulator")]
struct Args {
    #[arg(long, default_value = "127.0.0.1:1161")]
    listen: String,
}

#[tokio::main]
async fn main() -> std::io::Result<()> {
    let args = Args::parse();
    let (addr, agent, task) = wyrm_link_snmp::sim::spawn(&args.listen).await?;
    println!("snmp sim on udp {addr} (community public; v3 users sha1user, sha256user, authonly)");
    let ticker = tokio::spawn(async move {
        loop {
            tokio::time::sleep(Duration::from_secs(1)).await;
            agent.lock().unwrap_or_else(|p| p.into_inner()).tick(1);
        }
    });
    tokio::signal::ctrl_c().await?;
    ticker.abort();
    task.abort();
    Ok(())
}
