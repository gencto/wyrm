//! Prometheus exporter simulator for demos: counters that grow on every
//! scrape, gauges that drift once per second, a histogram and a summary
//! (see `wyrm_link_prometheus::sim`).

use clap::Parser;
use std::time::Duration;
use wyrm_link_prometheus::sim::Fail;

#[derive(Parser, Debug)]
#[command(version, about = "Prometheus exporter simulator")]
struct Args {
    #[arg(long, default_value = "127.0.0.1:9101")]
    listen: String,
    /// Serve OpenMetrics 1.0 text instead of the 0.0.4 text format.
    #[arg(long)]
    openmetrics: bool,
    /// Add broken lines to the exposition.
    #[arg(long)]
    malformed: bool,
}

#[tokio::main]
async fn main() -> std::io::Result<()> {
    let args = Args::parse();
    let (addr, exporter, task) = wyrm_link_prometheus::sim::spawn(&args.listen).await?;
    {
        let mut e = exporter.lock().unwrap_or_else(|p| p.into_inner());
        e.openmetrics = args.openmetrics;
        if args.malformed {
            e.fail = Fail::Malformed;
        }
    }
    println!("prometheus sim on http://{addr}/metrics");
    let ticker = tokio::spawn(async move {
        let mut step = 0u64;
        loop {
            tokio::time::sleep(Duration::from_secs(1)).await;
            step += 1;
            let mut e = exporter.lock().unwrap_or_else(|p| p.into_inner());
            e.temp_a = 21.5 + ((step % 20) as f64 - 10.0) / 10.0;
            e.temp_b = 19.0 + ((step % 10) as f64) / 10.0;
            e.buckets[0] += 3.0;
            e.buckets[1] += 5.0;
            e.buckets[2] += 6.0;
            e.buckets[3] += 6.0;
        }
    });
    tokio::signal::ctrl_c().await?;
    ticker.abort();
    task.abort();
    Ok(())
}
