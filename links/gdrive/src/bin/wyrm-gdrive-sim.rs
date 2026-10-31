//! Google Drive simulator for demos: the Drive API v3 and a token endpoint
//! taking one OAuth client and refresh token.

use clap::Parser;

#[derive(Parser, Debug)]
#[command(version, about = "Google Drive simulator for the gdrive link")]
struct Args {
    #[arg(long, default_value = "127.0.0.1:9101")]
    listen: String,
    #[arg(long, default_value = "sim-client")]
    client_id: String,
    #[arg(long, default_value = "sim-client-secret")]
    client_secret: String,
    #[arg(long, default_value = "sim-refresh-token")]
    refresh_token: String,
}

#[tokio::main]
async fn main() -> std::io::Result<()> {
    let args = Args::parse();
    let (addr, state, task) = wyrm_link_gdrive::sim::spawn(&args.listen).await?;
    {
        let mut s = state.lock().unwrap_or_else(|e| e.into_inner());
        s.refresh = Some((args.client_id, args.client_secret, args.refresh_token));
        s.put_path("reports/2026/october.csv", b"day,energy\n1,120\n");
        s.put_path("reports/readme.txt", b"monthly reports\n");
        s.put_path("config/plant.json", b"{\"units\": 4}\n");
    }
    println!(
        "gdrive sim: api_url http://{addr}, token_url http://{addr}/token (auth refresh_token)"
    );
    tokio::signal::ctrl_c().await?;
    task.abort();
    Ok(())
}
