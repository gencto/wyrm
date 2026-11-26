//! KNXnet/IP gateway simulator for demos: a tunnelling server over a few
//! group addresses. `1/0/1` (DPT 9.001, °C) moves once per second between
//! 18 and 26 and is sent on every change; `1/1/1` (DPT 1.001), `1/1/2`
//! (DPT 5.001) and `1/2/1` (DPT 20.102) hold what is written to them.

use clap::Parser;
use std::net::{Ipv4Addr, SocketAddr};
use std::time::Duration;
use wyrm_core::Value;
use wyrm_link_knx::addr::GroupAddr;
use wyrm_link_knx::cemi::Data;
use wyrm_link_knx::dpt::Dpt;
use wyrm_link_knx::proto::PORT;
use wyrm_link_knx::sim;

#[derive(Parser, Debug)]
#[command(version, about = "KNXnet/IP gateway simulator")]
struct Args {
    /// UDP address to listen on.
    #[arg(long, default_value_t = SocketAddr::from((Ipv4Addr::LOCALHOST, PORT)))]
    listen: SocketAddr,
}

/// The telegram octets of a temperature (DPT 9.001).
fn temperature(celsius: f64) -> Option<Data> {
    Dpt::new(9, 1).encode(&Value::Float(celsius)).ok()
}

#[tokio::main]
async fn main() -> std::io::Result<()> {
    let args = Args::parse();
    let gateway = sim::spawn(&args.listen.to_string()).await?;
    gateway.set(GroupAddr(0x0901), Data::short(0));
    gateway.set(GroupAddr(0x0902), Data::long(vec![0]));
    gateway.set(GroupAddr(0x0A01), Data::long(vec![1]));
    // the one line for people goes to stderr, where the logs go
    eprintln!("knx sim: tunnelling server on {}", gateway.addr());
    let mut step = 0u32;
    let mut tick = tokio::time::interval(Duration::from_secs(1));
    loop {
        tokio::select! {
            _ = tick.tick() => {
                step = (step + 1) % 80;
                let up = if step < 40 { step } else { 80 - step };
                if let Some(data) = temperature(18.0 + f64::from(up) * 0.2) {
                    gateway.inject(GroupAddr(0x0801), data);
                }
            }
            stop = tokio::signal::ctrl_c() => return stop,
        }
    }
}
