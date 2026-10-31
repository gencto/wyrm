//! WebDAV simulator for demos: one collection in memory, basic auth.

use clap::Parser;

#[derive(Parser, Debug)]
#[command(version, about = "WebDAV simulator for the webdav link")]
struct Args {
    #[arg(long, default_value = "127.0.0.1:9102")]
    listen: String,
    #[arg(long, default_value = "alice")]
    user: String,
    #[arg(long, default_value = "sim-password")]
    password: String,
}

#[tokio::main]
async fn main() -> std::io::Result<()> {
    let args = Args::parse();
    let (addr, state, task) = wyrm_link_webdav::sim::spawn(&args.listen).await?;
    {
        let mut s = state.lock().unwrap_or_else(|e| e.into_inner());
        s.basic = Some((args.user.clone(), args.password));
        s.put("reports/2026/october.csv", b"day,energy\n1,120\n");
        s.put("reports/readme.txt", b"monthly reports\n");
        s.put("config/plant.json", b"{\"units\": 4}\n");
    }
    println!(
        "webdav sim on http://{addr}{} (basic auth {})",
        wyrm_link_webdav::sim::BASE,
        args.user
    );
    tokio::signal::ctrl_c().await?;
    task.abort();
    Ok(())
}
