//! S7 PLC simulator for demos: DB1.DBW0 (INT) counts up once per second,
//! DB1.DBD2 (REAL) holds 21.5, DB1.DBX6.0 toggles every second,
//! DB1.DBB8 holds a STRING[16] "WYRM", MW10 holds 1234.

use clap::Parser;
use std::time::Duration;

#[derive(Parser, Debug)]
#[command(version, about = "S7 PLC simulator (S7comm over ISO-on-TCP)")]
struct Args {
    /// Port 102 needs privileges; the demo uses 10102.
    #[arg(long, default_value = "127.0.0.1:10102")]
    listen: String,
    /// The largest PDU the simulator agrees on.
    #[arg(long, default_value_t = 480)]
    pdu: u16,
}

#[tokio::main]
async fn main() -> std::io::Result<()> {
    let args = Args::parse();
    let (addr, device, sim) = wyrm_link_s7::sim::spawn(&args.listen).await?;
    {
        let mut p = device.lock().unwrap_or_else(|p| p.into_inner());
        p.pdu_size = args.pdu;
        let db = p.db(1, 1000);
        db[2..6].copy_from_slice(&21.5f32.to_be_bytes());
        db[8] = 16;
        db[9] = 4;
        db[10..14].copy_from_slice(b"WYRM");
        p.markers[10..12].copy_from_slice(&1234u16.to_be_bytes());
    }
    println!("s7 sim on {addr} (rack 0, any slot)");
    let ticker = tokio::spawn(async move {
        loop {
            tokio::time::sleep(Duration::from_secs(1)).await;
            let mut p = device.lock().unwrap_or_else(|p| p.into_inner());
            let db = p.db(1, 1000);
            let n = i16::from_be_bytes([db[0], db[1]]).wrapping_add(1);
            db[0..2].copy_from_slice(&n.to_be_bytes());
            db[6] ^= 1;
        }
    });
    tokio::signal::ctrl_c().await?;
    ticker.abort();
    sim.stop();
    Ok(())
}
