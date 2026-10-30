//! HTTP JSON server for demos: `GET /api/data` with a power value that
//! moves on every request, a writable `/api/resource`, redirects.

use clap::Parser;
use wyrm_link_http::sim::SimAuth;

#[derive(Parser, Debug)]
#[command(version, about = "HTTP JSON simulator for the http link")]
struct Args {
    #[arg(long, default_value = "127.0.0.1:8090")]
    listen: String,
    /// Require basic auth `user:password`.
    #[arg(long)]
    basic: Option<String>,
    /// Require `Authorization: Bearer <token>`.
    #[arg(long)]
    bearer: Option<String>,
}

#[tokio::main]
async fn main() -> std::io::Result<()> {
    let args = Args::parse();
    let (addr, state, task) = wyrm_link_http::sim::spawn(&args.listen).await?;
    {
        let mut s = state.lock().unwrap_or_else(|e| e.into_inner());
        s.tick = true;
        s.auth = match (args.basic, args.bearer) {
            (Some(b), _) => match b.split_once(':') {
                Some((u, p)) => SimAuth::Basic(u.into(), p.into()),
                None => SimAuth::Basic(b, String::new()),
            },
            (None, Some(t)) => SimAuth::Bearer(t),
            (None, None) => SimAuth::None,
        };
    }
    println!("http sim on http://{addr}/api (GET /api/data, /api/resource)");
    tokio::signal::ctrl_c().await?;
    task.abort();
    Ok(())
}
