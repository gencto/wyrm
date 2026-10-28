//! A **requester** link (as DSA `isRequester`): it serves no nodes of its
//! own, it reads another link's values and records them.
//!
//! Every sample under `source` (default `wy/<site>/downstream/mock`) becomes a
//! line `time,key,value,quality` in `values.csv` in the link's data
//! directory, rotated to `values.1.csv` at `max_mb`. Its package asks for
//! the grant it needs (`wyrm-link.json`: `requester: [{path, level: read}]`);
//! without it the broker's ACL drops its requests.
//!
//! Params (`sys/links/<id>/~act/update`): `source`, `max_mb`.

use std::path::PathBuf;
use tokio::io::AsyncWriteExt;
use wyrm_client::{ValEvent, WyrmClient};
use wyrm_core::Value;
use wyrm_link_sdk::params::Fields;
use wyrm_link_sdk::{FromParams, Link, LinkCtx, LinkError, Result};

struct Config {
    source: Option<String>,
    max_mb: u64,
}

impl FromParams for Config {
    fn from_params(v: &Value) -> Result<Self> {
        let f = Fields::new(v)?;
        f.only(&["source", "max_mb"])?;
        Ok(Self {
            source: f.opt_str("source")?.map(str::to_owned),
            max_mb: f.u64_or("max_mb", 10)?.clamp(1, 1024),
        })
    }
}

struct Recorder {
    task: tokio::task::JoinHandle<()>,
}

/// A CSV field: quoted when it holds a comma, a quote or a new line.
fn csv(s: &str) -> String {
    if s.contains([',', '"', '\n']) {
        format!("\"{}\"", s.replace('"', "\"\""))
    } else {
        s.to_owned()
    }
}

fn value_text(v: &Value) -> String {
    match v {
        Value::Null => String::new(),
        Value::Bool(b) => b.to_string(),
        Value::Int(i) => i.to_string(),
        Value::UInt(u) => u.to_string(),
        Value::Float(f) => f.to_string(),
        Value::Str(s) => s.clone(),
        other => format!("{other:?}"),
    }
}

async fn record(c: WyrmClient, source: String, dir: PathBuf, max: u64) {
    let pattern = format!("{source}/**");
    let mut events = match c.subscribe(&pattern).await {
        Ok(s) => s,
        Err(e) => {
            tracing::error!("subscribe {pattern}: {e} (does the link have a read grant?)");
            return;
        }
    };
    tracing::info!(%pattern, file = %dir.join("values.csv").display(), "recording");
    let path = dir.join("values.csv");
    let mut n: u64 = 0;
    while let Some(ev) = events.next().await {
        let ValEvent::Sample { key, sample, .. } = ev else {
            continue;
        };
        let line = format!(
            "{},{},{},{}\n",
            sample.t,
            csv(&key),
            csv(&value_text(&sample.v)),
            sample.q.name()
        );
        if tokio::fs::metadata(&path)
            .await
            .map(|m| m.len())
            .unwrap_or(0)
            > max << 20
        {
            let _ = tokio::fs::rename(&path, dir.join("values.1.csv")).await;
        }
        let file = tokio::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(&path)
            .await;
        match file {
            Ok(mut f) => {
                if let Err(e) = f.write_all(line.as_bytes()).await {
                    tracing::warn!("write: {e}");
                }
            }
            Err(e) => tracing::warn!("open {}: {e}", path.display()),
        }
        n += 1;
        if n.is_power_of_two() {
            tracing::info!(samples = n, "recorded");
        }
    }
    tracing::warn!("the subscription ended");
}

impl Link for Recorder {
    const NAME: &'static str = "recorder";
    const VERSION: &'static str = env!("CARGO_PKG_VERSION");
    type Config = Config;

    async fn start(cfg: Config, ctx: LinkCtx) -> Result<Self> {
        let dir = ctx
            .data_dir()
            .ok_or_else(|| LinkError::internal("no data directory"))?
            .to_owned();
        let source = cfg
            .source
            .unwrap_or_else(|| format!("wy/{}/downstream/mock", ctx.site()));
        // Reads need no token: the read grant opens the ACL.
        let c = WyrmClient::new(ctx.client().clone());
        let task = tokio::spawn(record(c, source, dir, cfg.max_mb));
        Ok(Recorder { task })
    }

    async fn stop(&mut self) {
        self.task.abort();
    }
}

fn main() -> std::process::ExitCode {
    // logs, the supervisor's limits, a runtime, then `process::run`
    wyrm_link_sdk::process::main::<Recorder>()
}
