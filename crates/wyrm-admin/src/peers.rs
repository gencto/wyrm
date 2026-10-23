//! Peer brokers in the tree (ADR 0007): a downstream site (one that
//! connects to this broker) is the node `wy/<site>/downstream/<d>`, beside the
//! links, which connect to it too; an upstream site (one this broker
//! connects to) is `wy/<site>/upstream/<u>`. Each is a reference, not a copy:
//! profile `wy:broker`, `@site`, `@root = wy/<peer>` (the peer's own keys,
//! under their one name, spec 01) and a bool point `connected` from the
//! peer's liveliness token `wy/<peer>/sys/broker`.

use std::time::Duration;
use tokio::task::JoinHandle;
use tracing::warn;
use wyrm_core::meta::Profile;
use wyrm_core::{NodeMeta, Quality, TypeCode};
use wyrm_link_sdk::{now_us, Link, LinkCtx};

/// Profile code of `wy:broker` (`tables.json`).
const BROKER: u32 = 9;

/// One link serving reference nodes: `(path, peer site)`; path `""` is the
/// link root itself (a downstream site at `downstream/<d>`).
pub struct PeerRefs {
    tasks: Vec<JoinHandle<()>>,
}

pub struct PeerRefsConfig {
    pub nodes: Vec<(String, String)>,
}

fn join(path: &str, leaf: &str) -> String {
    if path.is_empty() {
        leaf.to_owned()
    } else {
        format!("{path}/{leaf}")
    }
}

impl Link for PeerRefs {
    const NAME: &'static str = "broker";
    const VERSION: &'static str = env!("CARGO_PKG_VERSION");
    type Config = PeerRefsConfig;

    async fn start(cfg: PeerRefsConfig, ctx: LinkCtx) -> wyrm_link_sdk::Result<Self> {
        let mut tasks = Vec::new();
        for (path, site) in cfg.nodes {
            ctx.declare_node(
                &path,
                NodeMeta {
                    is: Some(Profile::Code(BROKER)),
                    ..Default::default()
                }
                .attr("site", site.as_str())
                .attr("root", format!("wy/{site}").as_str()),
            )
            .await?;
            let point = join(&path, "connected");
            ctx.declare_node(&point, NodeMeta::leaf(TypeCode::Bool))
                .await?;
            ctx.update(&point, false, Quality::Good, now_us()).await?;
            tasks.push(tokio::spawn(watch(ctx.clone(), point, site)));
        }
        Ok(Self { tasks })
    }

    async fn stop(&mut self) {
        for t in &self.tasks {
            t.abort();
        }
    }
}

/// `connected` follows `wy/<site>/sys/broker` (the ACL lets only this
/// liveliness pass between peers).
async fn watch(ctx: LinkCtx, point: String, site: String) {
    let key = format!("wy/{site}/sys/broker");
    let sub = loop {
        match ctx
            .client()
            .liveliness()
            .declare_subscriber(&key)
            .history(true)
            .await
        {
            Ok(s) => break s,
            Err(e) => {
                warn!("cannot watch {key}: {e}");
                tokio::time::sleep(Duration::from_secs(5)).await;
            }
        }
    };
    while let Ok(s) = sub.recv_async().await {
        let up = s.kind() == zenoh::sample::SampleKind::Put;
        let _ = ctx.update(&point, up, Quality::Good, now_us()).await;
    }
}
