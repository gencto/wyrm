//! `wyr bench`: latency percentiles against the iteration 1 targets
//! (subscribe p99 < 2 ms LAN, list of 1000 children < 50 ms).

use crate::Error;
use clap::Subcommand;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use wyrm_client::WyrmClient;
use wyrm_core::Sample;

#[derive(Subcommand, Debug)]
pub enum What {
    /// Repeated `list` snapshot (`~meta` full + `view=list`) of one node.
    List {
        node: String,
        #[arg(short, default_value_t = 100)]
        n: usize,
    },
    /// Live `~val` samples: end-to-end latency (`now - sample.t`) and rate.
    /// Publisher and bench must share a clock (same host or PTP/NTP).
    Sub {
        pattern: String,
        #[arg(long, default_value_t = 10)]
        secs: u64,
    },
}

pub async fn run(c: &WyrmClient, what: What) -> Result<(), Error> {
    match what {
        What::List { node, n } => list(c, &node, n).await,
        What::Sub { pattern, secs } => sub(c, &pattern, secs).await,
    }
}

/// Nearest-rank percentile of sorted data.
fn pct(sorted: &[f64], p: f64) -> f64 {
    if sorted.is_empty() {
        return f64::NAN;
    }
    let rank = ((p / 100.0) * sorted.len() as f64).ceil() as usize;
    sorted[rank.clamp(1, sorted.len()) - 1]
}

fn report(what: &str, unit: &str, mut xs: Vec<f64>) {
    xs.sort_by(f64::total_cmp);
    out!(
        "{what}: n={} p50={:.3}{unit} p95={:.3}{unit} p99={:.3}{unit} max={:.3}{unit}",
        xs.len(),
        pct(&xs, 50.0),
        pct(&xs, 95.0),
        pct(&xs, 99.0),
        xs.last().copied().unwrap_or(f64::NAN),
    );
}

async fn list(c: &WyrmClient, node: &str, n: usize) -> Result<(), Error> {
    let children = c.children(node).await?.len();
    for _ in 0..5 {
        c.children(node).await?;
    }
    let mut ms = Vec::with_capacity(n);
    for _ in 0..n {
        let t0 = Instant::now();
        c.children(node).await?;
        ms.push(t0.elapsed().as_secs_f64() * 1e3);
    }
    report(&format!("list {node} ({children} children)"), "ms", ms);
    Ok(())
}

fn now_us() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_micros() as u64)
        .unwrap_or(0)
}

async fn sub(c: &WyrmClient, pattern: &str, secs: u64) -> Result<(), Error> {
    // Raw subscriber: measures the live path only (no storage snapshot).
    let sub = c
        .session()
        .declare_subscriber(format!("{pattern}/~val"))
        .await?;
    let end = Instant::now() + Duration::from_secs(secs);
    let mut lat_ms = Vec::new();
    let mut bad = 0usize;
    while let Ok(Ok(s)) = tokio::time::timeout_at(end.into(), sub.recv_async()).await {
        let rx = now_us();
        match wyrm_core::codec::from_slice::<Sample>(&s.payload().to_bytes()) {
            Ok(smp) => lat_ms.push(rx.saturating_sub(smp.t) as f64 / 1e3),
            Err(_) => bad += 1,
        }
    }
    let rate = lat_ms.len() as f64 / secs as f64;
    out!("samples/s: {rate:.0} (undecodable: {bad})");
    report(&format!("subscribe {pattern}"), "ms", lat_ms);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::pct;

    #[test]
    fn nearest_rank() {
        let xs: Vec<f64> = (1..=100).map(f64::from).collect();
        assert_eq!(pct(&xs, 50.0), 50.0);
        assert_eq!(pct(&xs, 99.0), 99.0);
        assert_eq!(pct(&xs, 100.0), 100.0);
        assert_eq!(pct(&[7.0], 99.0), 7.0);
    }
}
