//! Modbus TCP device simulator for demos: holding register 0 counts up once
//! per second, input register 1 holds 215 (21.5 with scale 0.1).

use clap::Parser;
use std::time::Duration;

#[derive(Parser, Debug)]
#[command(version, about = "Modbus TCP simulator (diagslave stand-in)")]
struct Args {
    #[arg(long, default_value = "127.0.0.1:5020")]
    listen: String,
}

#[tokio::main]
async fn main() -> std::io::Result<()> {
    let args = Args::parse();
    let (addr, device, task) = wyrm_link_modbus::sim::spawn(&args.listen).await?;
    device.lock().unwrap().input[1] = 215;
    println!("modbus sim on {addr}");
    let ticker = tokio::spawn(async move {
        loop {
            tokio::time::sleep(Duration::from_secs(1)).await;
            let mut t = device.lock().unwrap();
            t.holding[0] = t.holding[0].wrapping_add(1);
        }
    });
    tokio::signal::ctrl_c().await?;
    ticker.abort();
    task.abort();
    Ok(())
}
