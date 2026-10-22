//! A link that is **both a responder and a requester**.
//!
//! - Requester (read): it follows every numeric value under `source`
//!   (default `wy/<site>/down/mock`).
//! - Responder: it serves `average`, `min`, `max` and `count` of the last
//!   value of each point, and the action `write_all {value}`.
//! - Requester (write): `write_all` sets every point it has seen to
//!   `value`, with `ptok`s signed by its requester key (the broker trusts
//!   that key only up to the grant's level, under the grant's path).
//!
//! Its package asks for `requester: [{path: wy/{site}/down/mock, level:
//! write}]`.

use std::collections::BTreeMap;
use std::sync::{Arc, Mutex};
use std::time::Duration;
use wyrm_client::{SigningTokens, ValEvent, WyrmClient};
use wyrm_core::meta::{ActionResult, ParamMeta};
use wyrm_core::{ActionMeta, NodeMeta, Perm, Quality, TypeCode, Value};
use wyrm_link_sdk::params::Fields;
use wyrm_link_sdk::{now_us, Caller, FromParams, Link, LinkCtx, LinkError, ReplySink, Result};

struct Config {
    source: Option<String>,
}

impl FromParams for Config {
    fn from_params(v: &Value) -> Result<Self> {
        let f = Fields::new(v)?;
        f.only(&["source"])?;
        Ok(Self {
            source: f.opt_str("source")?.map(str::to_owned),
        })
    }
}

/// The last numeric value of each point under `source`.
type Last = Arc<Mutex<BTreeMap<String, f64>>>;

struct Average {
    last: Last,
    /// Writes with the requester key; `None` without a write grant.
    writer: Option<WyrmClient>,
    tasks: Vec<tokio::task::JoinHandle<()>>,
}

const STATS: [(&str, &str); 4] = [
    ("average", "Average"),
    ("min", "Min"),
    ("max", "Max"),
    ("count", "Points"),
];

async fn follow(c: WyrmClient, source: String, last: Last) {
    let pattern = format!("{source}/**");
    let mut events = match c.subscribe(&pattern).await {
        Ok(s) => s,
        Err(e) => {
            tracing::error!("subscribe {pattern}: {e} (does the link have a read grant?)");
            return;
        }
    };
    tracing::info!(%pattern, "following");
    while let Some(ev) = events.next().await {
        let mut l = last.lock().unwrap_or_else(|p| p.into_inner());
        match ev {
            ValEvent::Sample { key, sample, .. } => match sample.v.as_f64() {
                Some(x) if sample.q == Quality::Good => {
                    l.insert(key, x);
                }
                _ => {
                    l.remove(&key);
                }
            },
            ValEvent::Removed(key) => {
                l.remove(&key);
            }
        }
    }
}

/// Publish the statistics twice a second.
async fn publish(ctx: LinkCtx, last: Last) {
    let mut tick = tokio::time::interval(Duration::from_millis(500));
    loop {
        tick.tick().await;
        let values: Vec<f64> = last
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .values()
            .copied()
            .collect();
        let n = values.len();
        let stats = if n == 0 {
            [Value::Null, Value::Null, Value::Null, Value::UInt(0)]
        } else {
            let sum: f64 = values.iter().sum();
            let min = values.iter().copied().fold(f64::INFINITY, f64::min);
            let max = values.iter().copied().fold(f64::NEG_INFINITY, f64::max);
            [
                Value::Float((sum / n as f64 * 100.0).round() / 100.0),
                Value::Float(min),
                Value::Float(max),
                Value::UInt(n as u64),
            ]
        };
        for ((key, _), v) in STATS.iter().zip(stats) {
            let q = if matches!(v, Value::Null) {
                Quality::Uncertain
            } else {
                Quality::Good
            };
            if ctx.update(key, v, q, now_us()).await.is_err() {
                return; // the link stopped
            }
        }
    }
}

impl Link for Average {
    const NAME: &'static str = "average";
    const VERSION: &'static str = env!("CARGO_PKG_VERSION");
    type Config = Config;

    async fn start(cfg: Config, ctx: LinkCtx) -> Result<Self> {
        for (key, display) in STATS {
            ctx.declare_node(key, NodeMeta::number().display(display))
                .await?;
        }
        ctx.declare_action(
            "",
            "write_all",
            ActionMeta::new()
                .display("Write All")
                .param(
                    "value",
                    ParamMeta::of(TypeCode::Number)
                        .required(true)
                        .display("Value"),
                )
                .result(ActionResult::Type(TypeCode::Map))
                .level(Perm::Write),
        )
        .await?;
        let source = cfg
            .source
            .unwrap_or_else(|| format!("wy/{}/down/mock", ctx.site()));
        let reader = WyrmClient::new(ctx.client().clone());
        // `ptok`s for other links: signed with this link's requester key.
        let writer = ctx.requester_key().map(|key| {
            WyrmClient::new(ctx.client().clone()).with_tokens(Arc::new(
                SigningTokens::new(key, ctx.site()).subject(format!("link:{}", ctx.link())),
            ))
        });
        if writer.is_none() {
            tracing::warn!("no requester key: write_all needs a write grant");
        }
        let last: Last = Default::default();
        let tasks = vec![
            tokio::spawn(follow(reader, source, last.clone())),
            tokio::spawn(publish(ctx.clone(), last.clone())),
        ];
        Ok(Average {
            last,
            writer,
            tasks,
        })
    }

    async fn on_invoke(
        &mut self,
        _path: &str,
        action: &str,
        args: Value,
        _who: &Caller,
        out: ReplySink,
    ) -> Result<()> {
        if action != "write_all" {
            return Err(LinkError::not_supported(action.to_owned()));
        }
        let value = Fields::new(&args)?
            .get("value")
            .and_then(Value::as_f64)
            .ok_or_else(|| LinkError::invalid_parameter("value: a number"))?;
        let writer = self
            .writer
            .clone()
            .ok_or_else(|| LinkError::not_supported("no write grant"))?;
        let keys: Vec<String> = self
            .last
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .keys()
            .cloned()
            .collect();
        let (mut written, mut failed) = (0u64, Vec::new());
        for key in keys {
            match writer.set(&key, value).await {
                Ok(()) => written += 1,
                Err(e) => failed.push(Value::Str(format!("{key}: {}", e.message))),
            }
        }
        tracing::info!(written, failed = failed.len(), "write_all {value}");
        out.reply(Value::Map(BTreeMap::from([
            ("written".to_owned(), Value::UInt(written)),
            ("failed".to_owned(), Value::Array(failed)),
        ])))
        .await
    }

    async fn stop(&mut self) {
        for t in &self.tasks {
            t.abort();
        }
    }
}

fn main() -> std::result::Result<(), Box<dyn std::error::Error>> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "info,zenoh=warn".into()),
        )
        .init();
    wyrm_link_sdk::limits::apply_from_env()?;
    tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()?
        .block_on(wyrm_link_sdk::process::run::<Average>())?;
    Ok(())
}
