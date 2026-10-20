//! Mock connector: `points` numeric points on a tree of `depth` folder levels
//! with `fanout` folders per level, each updated `rate_hz` times per second.
//!
//! Layout (`depth = 2`, `fanout = 2`): `g0/g0/p0`, `g0/g1/p1`, `g1/g0/p2`, …
//! Points go round-robin over the leaf folders. Paths are deterministic, see
//! [`point_paths`], so tests and `wyr bench` can address points directly.
//!
//! Writable points hold a written value until `reset`. Root actions:
//! `reset` (drop all written values) and `count` (stream `0..n`).

#![forbid(unsafe_code)]

use std::collections::HashMap;
use std::f64::consts::TAU;
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tracing::debug;
use wyrm_core::meta::{ActionResult, ParamMeta, Writable};
use wyrm_core::{ActionMeta, NodeMeta, Perm, Quality, Status, TypeCode, Value};
use wyrm_link_sdk::params::narrow;
use wyrm_link_sdk::{
    now_us, Caller, Fields, FromParams, Link, LinkCtx, LinkError, PointPublisher, ReplySink, Result,
};

#[derive(Debug, Clone)]
pub struct MockConfig {
    pub points: usize,
    /// Updates per point per second; `0` publishes once and stays static.
    pub rate_hz: f64,
    pub depth: usize,
    pub fanout: usize,
    pub writable: bool,
}

impl Default for MockConfig {
    fn default() -> Self {
        Self {
            points: 10,
            rate_hz: 1.0,
            depth: 1,
            fanout: 4,
            writable: true,
        }
    }
}

impl FromParams for MockConfig {
    /// `{points, rate_hz, depth, fanout, writable}`, all optional.
    fn from_params(v: &Value) -> Result<Self> {
        let f = Fields::new(v)?;
        f.only(&["points", "rate_hz", "depth", "fanout", "writable"])?;
        let d = MockConfig::default();
        Ok(Self {
            points: narrow(f.u64_or("points", d.points as u64)?, "points")?,
            rate_hz: f.f64_or("rate_hz", d.rate_hz)?.max(0.0),
            depth: narrow(f.u64_or("depth", d.depth as u64)?, "depth")?,
            fanout: narrow(f.u64_or("fanout", d.fanout as u64)?, "fanout")?,
            writable: f.bool_or("writable", d.writable)?,
        })
    }
}

/// Folder paths, parents before children.
pub fn folder_paths(cfg: &MockConfig) -> Vec<String> {
    let mut out = Vec::new();
    let mut level = vec![String::new()];
    for _ in 0..cfg.depth {
        let mut next = Vec::new();
        for parent in &level {
            for i in 0..cfg.fanout.max(1) {
                let p = if parent.is_empty() {
                    format!("g{i}")
                } else {
                    format!("{parent}/g{i}")
                };
                out.push(p.clone());
                next.push(p);
            }
        }
        level = next;
    }
    out
}

/// Point paths, index = point number.
pub fn point_paths(cfg: &MockConfig) -> Vec<String> {
    let leaves: Vec<String> = if cfg.depth == 0 {
        vec![String::new()]
    } else {
        let all = folder_paths(cfg);
        let leaf_count = cfg.fanout.max(1).pow(cfg.depth as u32);
        all[all.len() - leaf_count..].to_vec()
    };
    (0..cfg.points)
        .map(|k| {
            let leaf = &leaves[k % leaves.len()];
            if leaf.is_empty() {
                format!("p{k}")
            } else {
                format!("{leaf}/p{k}")
            }
        })
        .collect()
}

/// Value of point `k` at time `t_us`: a slow sine around 20, phase per point.
pub fn wave(k: usize, t_us: u64) -> f64 {
    let t = t_us as f64 / 1e6;
    20.0 + 10.0 * (TAU * t / 60.0 + k as f64).sin()
}

type Held = Arc<Mutex<HashMap<String, f64>>>;

pub struct Mock {
    ctx: LinkCtx,
    held: Held,
    ticker: Option<tokio::task::JoinHandle<()>>,
}

impl Link for Mock {
    const NAME: &'static str = "mock";
    const VERSION: &'static str = env!("CARGO_PKG_VERSION");
    type Config = MockConfig;

    async fn start(cfg: MockConfig, ctx: LinkCtx) -> Result<Self> {
        for f in folder_paths(&cfg) {
            ctx.declare_node(&f, NodeMeta::folder()).await?;
        }
        let paths = point_paths(&cfg);
        let writable = if cfg.writable {
            Writable::Write
        } else {
            Writable::Never
        };
        for p in &paths {
            ctx.declare_node(p, NodeMeta::number().unit("°C").writable(writable))
                .await?;
        }
        ctx.declare_action("", "reset", ActionMeta::new().level(Perm::Write))
            .await?;
        ctx.declare_action(
            "",
            "count",
            ActionMeta::new()
                .param("n", ParamMeta::of(TypeCode::Number).required(true))
                .result(ActionResult::Stream)
                .stream(true)
                .level(Perm::Read),
        )
        .await?;

        let mut pubs = Vec::with_capacity(paths.len());
        for p in &paths {
            pubs.push(ctx.publisher(p).await?);
        }
        let held = Held::default();
        publish_all(&pubs, &paths, &held).await?;
        let ticker = (cfg.rate_hz > 0.0).then(|| {
            let held = held.clone();
            let period = Duration::from_secs_f64(1.0 / cfg.rate_hz);
            tokio::spawn(tick(pubs, paths, held, period))
        });
        Ok(Self { ctx, held, ticker })
    }

    async fn on_set(&mut self, path: &str, value: Value, _who: &Caller) -> Result<()> {
        // Type and range are already checked by the SDK.
        let v = value
            .as_f64()
            .ok_or_else(|| LinkError::internal("not a number"))?;
        self.held
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .insert(path.to_owned(), v);
        self.ctx.update(path, v, Quality::Good, now_us()).await
    }

    async fn on_invoke(
        &mut self,
        _path: &str,
        action: &str,
        args: Value,
        _who: &Caller,
        out: ReplySink,
    ) -> Result<()> {
        match action {
            "reset" => {
                self.held.lock().unwrap_or_else(|p| p.into_inner()).clear();
                Ok(())
            }
            "count" => {
                let n = match &args {
                    Value::Map(m) => m.get("n").and_then(Value::as_f64).unwrap_or(0.0),
                    _ => 0.0,
                };
                if !(0.0..=1_000_000.0).contains(&n) {
                    return Err(LinkError::new(Status::OutOfRange, "n must be 0..=1000000"));
                }
                tokio::spawn(async move {
                    for i in 0..n as u64 {
                        if out.reply(i).await.is_err() {
                            return;
                        }
                    }
                    let _ = out.done(None).await;
                });
                Ok(())
            }
            other => Err(LinkError::not_supported(other)),
        }
    }

    async fn stop(&mut self) {
        if let Some(t) = self.ticker.take() {
            t.abort();
        }
    }
}

/// One sample per point; `t` is taken per point (the moment it is "read").
async fn publish_all(pubs: &[PointPublisher], paths: &[String], held: &Held) -> Result<()> {
    for (k, (p, path)) in pubs.iter().zip(paths).enumerate() {
        let t = now_us();
        let v = held
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .get(path)
            .copied()
            .unwrap_or_else(|| wave(k, t));
        p.put(v, Quality::Good, t).await?;
    }
    Ok(())
}

async fn tick(pubs: Vec<PointPublisher>, paths: Vec<String>, held: Held, period: Duration) {
    let mut iv = tokio::time::interval(period);
    iv.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
    iv.tick().await;
    loop {
        iv.tick().await;
        if let Err(e) = publish_all(&pubs, &paths, &held).await {
            debug!("mock ticker stops: {e}");
            return;
        }
    }
}
