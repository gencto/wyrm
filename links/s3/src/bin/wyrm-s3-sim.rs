//! S3 simulator for demos: one bucket in memory, SigV4 checked.

use clap::Parser;

#[derive(Parser, Debug)]
#[command(version, about = "S3 simulator for the s3 link")]
struct Args {
    #[arg(long, default_value = "127.0.0.1:9100")]
    listen: String,
    #[arg(long, default_value = "plant")]
    bucket: String,
    #[arg(long, default_value = "AKIASIM")]
    access_key: String,
    #[arg(long, default_value = "sim-secret-key")]
    secret_key: String,
}

#[tokio::main]
async fn main() -> std::io::Result<()> {
    let args = Args::parse();
    let (addr, state, task) = wyrm_link_s3::sim::spawn(&args.listen).await?;
    {
        let mut s = state.lock().unwrap_or_else(|e| e.into_inner());
        s.bucket = args.bucket.clone();
        s.access = args.access_key;
        s.secret = args.secret_key;
        s.put("reports/2026/october.csv", b"day,energy\n1,120\n");
        s.put("reports/readme.txt", b"monthly reports\n");
        s.put("config/plant.json", b"{\"units\": 4}\n");
    }
    println!(
        "s3 sim on http://{addr} bucket {} (path-style)",
        args.bucket
    );
    tokio::signal::ctrl_c().await?;
    task.abort();
    Ok(())
}
