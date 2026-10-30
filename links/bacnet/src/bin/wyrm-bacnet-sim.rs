//! BACnet/IP device simulator for demos: analog-input 1 (°C) moves once
//! per second between 18 and 26; analog-value 1, binary-value 1 and
//! multi-state-value 1 are writable with priorities.

use clap::Parser;
use std::time::Duration;
use wyrm_link_bacnet::codec::AppValue;
use wyrm_link_bacnet::sim::{self, objects};

#[derive(Parser, Debug)]
#[command(version, about = "BACnet/IP device simulator")]
struct Args {
    /// UDP address to listen on.
    #[arg(long, default_value = "127.0.0.1:47809")]
    listen: String,
    /// Device instance.
    #[arg(long, default_value_t = 1234)]
    instance: u32,
    /// Extra analog inputs (instances 100…) for batching demos.
    #[arg(long, default_value_t = 0)]
    extra: u32,
}

#[tokio::main]
async fn main() -> std::io::Result<()> {
    let args = Args::parse();
    let (addr, device, task) = sim::spawn(&args.listen, args.instance).await?;
    if let Ok(mut d) = device.lock() {
        d.add_analog_inputs(args.extra);
    }
    println!("bacnet sim: device {} on {addr}", args.instance);
    let ticker = tokio::spawn(async move {
        let mut step = 0u32;
        loop {
            tokio::time::sleep(Duration::from_secs(1)).await;
            step = (step + 1) % 80;
            let t = if step < 40 { step } else { 80 - step };
            if let Ok(mut d) = device.lock() {
                d.set_pv(objects::AI1, AppValue::Real(18.0 + t as f32 * 0.2));
            }
        }
    });
    tokio::signal::ctrl_c().await?;
    ticker.abort();
    task.abort();
    Ok(())
}
