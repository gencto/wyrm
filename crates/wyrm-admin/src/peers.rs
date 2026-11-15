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

/// One probe waits this long for its answer.
const PROBE_TIMEOUT: Duration = Duration::from_secs(3);
/// The first pause between two probes; it doubles up to [`PROBE_PAUSE_MAX`].
const PROBE_PAUSE_FIRST: Duration = Duration::from_millis(50);
const PROBE_PAUSE_MAX: Duration = Duration::from_secs(5);

/// `connected` means that queries reach the peer: its token
/// `wy/<site>/sys/broker` is there (the ACL lets only this liveliness pass
/// between peers) and a query to it has an answer. The token alone is not
/// enough: a router that has just connected has its tokens routed about one
/// routing-tree computation before queries to it are (the route gap,
/// `docs/backlog.md` §6), and in that gap every query to it ends at once
/// with no reply.
async fn watch(ctx: LinkCtx, point: String, site: String) {
    let key = format!("wy/{site}/sys/broker");
    let mut sub = loop {
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
    let probe_key = crate::acl::signing_keys_key(&site);
    let session = ctx.client().clone();
    follow(
        &mut sub,
        || reaches(&session, &probe_key),
        |up| {
            let ctx = ctx.clone();
            let point = point.clone();
            async move {
                let _ = ctx.update(&point, up, Quality::Good, now_us()).await;
            }
        },
    )
    .await;
}

/// `true` once a query to the peer has an answer. The key is the peer's
/// `sys/signing_keys` (ADR 0018): its own complete queryable answers it, the
/// ACL lets it through both ways (downstream: `site-<d>` here and the
/// upstream reads there; upstream: `signers-<u>`), and nothing local does
/// (`AllComplete` skips the `~val` storage).
async fn reaches(session: &zenoh::Session, key: &str) -> bool {
    let Ok(replies) = session
        .get(key)
        .target(zenoh::query::QueryTarget::AllComplete)
        .timeout(PROBE_TIMEOUT)
        .await
    else {
        return false;
    };
    matches!(replies.recv_async().await, Ok(r) if r.result().is_ok())
}

/// Presence of a peer: `Some(true)` its token appeared, `Some(false)` it
/// went, `None` the watch ended.
pub(crate) trait Presence {
    fn next(&mut self) -> impl std::future::Future<Output = Option<bool>> + Send;
}

impl Presence
    for zenoh::pubsub::Subscriber<zenoh::handlers::FifoChannelHandler<zenoh::sample::Sample>>
{
    async fn next(&mut self) -> Option<bool> {
        let s = self.recv_async().await.ok()?;
        Some(s.kind() == zenoh::sample::SampleKind::Put)
    }
}

/// `set(false)` when the token goes; when it is there, `set(true)` only
/// after `probe` has said `true`. Probes run one at a time with a pause
/// (doubled up to [`PROBE_PAUSE_MAX`]) between them for as long as the
/// token stays; the next presence change ends them.
pub(crate) async fn follow<P, Fut, S, SFut>(presence: &mut impl Presence, probe: P, mut set: S)
where
    P: Fn() -> Fut,
    Fut: std::future::Future<Output = bool>,
    S: FnMut(bool) -> SFut,
    SFut: std::future::Future<Output = ()>,
{
    let mut next = presence.next().await;
    while let Some(up) = next.take() {
        if !up {
            set(false).await;
            next = presence.next().await;
            continue;
        }
        let mut pause = PROBE_PAUSE_FIRST;
        next = loop {
            tokio::select! {
                ev = presence.next() => break ev,
                ok = probe() => if ok {
                    set(true).await;
                    break presence.next().await;
                },
            }
            tokio::select! {
                ev = presence.next() => break ev,
                _ = tokio::time::sleep(pause) => {}
            }
            pause = (pause * 2).min(PROBE_PAUSE_MAX);
        };
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{Arc, Mutex};
    use tokio::sync::mpsc;
    use tokio::time::Instant;

    impl Presence for mpsc::UnboundedReceiver<bool> {
        async fn next(&mut self) -> Option<bool> {
            self.recv().await
        }
    }

    /// What `connected` was set to, and when.
    type Log = Arc<Mutex<Vec<(bool, Duration)>>>;

    /// A peer whose queries have no answer for `gap` after its token
    /// appears (the route gap), then answer.
    async fn run(gap: Duration, events: Vec<(Duration, bool)>) -> (Vec<(bool, Duration)>, usize) {
        let start = Instant::now();
        let (tx, mut rx) = mpsc::unbounded_channel();
        let log: Log = Arc::default();
        let probes = Arc::new(Mutex::new(0usize));
        let up_since = Arc::new(Mutex::new(None::<Instant>));
        let feeder = {
            let up_since = up_since.clone();
            tokio::spawn(async move {
                for (at, up) in events {
                    tokio::time::sleep_until(start + at).await;
                    *up_since.lock().unwrap() = up.then(Instant::now);
                    tx.send(up).unwrap();
                }
                // the watch ends a while after the last event
                tokio::time::sleep(Duration::from_secs(60)).await;
            })
        };
        let probe = || {
            let (probes, up_since) = (probes.clone(), up_since.clone());
            async move {
                *probes.lock().unwrap() += 1;
                // a query in the gap ends at once with no reply
                tokio::time::sleep(Duration::from_millis(2)).await;
                up_since.lock().unwrap().is_some_and(|t| t.elapsed() >= gap)
            }
        };
        let set = |up: bool| {
            let log = log.clone();
            async move { log.lock().unwrap().push((up, start.elapsed())) }
        };
        follow(&mut rx, probe, set).await;
        feeder.await.unwrap();
        let log = log.lock().unwrap().clone();
        let n = *probes.lock().unwrap();
        (log, n)
    }

    #[tokio::test(start_paused = true)]
    async fn connected_only_once_a_query_reaches_the_peer() {
        let gap = Duration::from_millis(120);
        let (log, probes) = run(gap, vec![(Duration::ZERO, true)]).await;
        assert_eq!(log.len(), 1, "{log:?}");
        let (up, at) = log[0];
        assert!(up);
        assert!(at >= gap, "true at {at:?}, before the gap ended");
        assert!(at < gap + Duration::from_millis(150), "{at:?}");
        assert!(probes >= 2, "probed through the gap: {probes}");
    }

    #[tokio::test(start_paused = true)]
    async fn a_token_that_goes_while_probing_ends_the_probes() {
        let gap = Duration::from_secs(3600); // never reachable
        let (log, probes) = run(
            gap,
            vec![(Duration::ZERO, true), (Duration::from_secs(20), false)],
        )
        .await;
        assert_eq!(log, [(false, Duration::from_secs(20))]);
        // 50 ms doubled to 5 s: about a dozen probes in 20 s, then none
        assert!((5..=15).contains(&probes), "{probes}");
    }

    #[tokio::test(start_paused = true)]
    async fn back_after_a_drop_probes_again() {
        let gap = Duration::from_millis(80);
        let (log, _) = run(
            gap,
            vec![
                (Duration::ZERO, true),
                (Duration::from_secs(1), false),
                (Duration::from_secs(2), true),
            ],
        )
        .await;
        let ups: Vec<bool> = log.iter().map(|(u, _)| *u).collect();
        assert_eq!(ups, [true, false, true]);
        assert!(log[2].1 >= Duration::from_secs(2) + gap, "{log:?}");
    }
}
