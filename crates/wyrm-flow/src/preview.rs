//! Live preview of an undeployed draft (ADR 0038 §5): `dataflows/~act/preview {def, nodes,
//! max_hz}` compiles the draft and runs it in a sandbox, streaming `watch`'s rows.
//!
//! The sandbox:
//! - is a real runtime instance of the draft ([`runtime::start`]) that nothing persists: no
//!   store, no `~def`, no node states, no tree node; its id is the preview's place in the
//!   registry, never a flow of [`crate::Engine`], so a draft with the id of a deployed flow
//!   touches neither that flow nor its watches;
//! - builds its nodes in [`Mode::Preview`]: `set`, `invoke` and `publish` are capture nodes
//!   with no client and no writer, so they cannot write by construction; what they would do
//!   goes into the rows as `sinks`;
//! - reads through a client without tokens: even a bug that reached it could not prove the
//!   flow key's rights to a link;
//! - records every port from the start (the probe is held before the first node runs), and
//!   the first row waits until the nodes settled ([`Probe::settle`]), so it shows what the
//!   variables sent at start.
//!
//! It ends after [`TTL`], when a newer preview of the same subject takes its place, on a node
//! panic (the stream ends with `internal_error`; never restarted) and when the engine stops.

use crate::artifacts::Artifacts;
use crate::def::FlowDef;
use crate::nodes::{Io, Mode, Ports, Sandbox};
use crate::runtime::{self, Running};
use crate::watch::{self as live, Probe, Ticket, Watches};
use std::collections::{BTreeMap, BTreeSet};
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::mpsc;
use tokio::task::JoinHandle;
use tracing::warn;
use wyrm_client::WyrmClient;
use wyrm_link_sdk::{LinkCtx, LinkError, ReplySink};

/// Previews of one subject at most: a newer one ends that subject's oldest.
pub const PER_SUBJECT: usize = 2;
/// Previews of one site at most (`busy` beyond).
pub const PER_SITE: usize = 16;
/// A preview ends after this long; the editor opens it again with its latest draft.
pub const TTL: Duration = Duration::from_secs(10 * 60);
/// The longest wait for the draft's nodes to settle before the first row.
const SETTLE: Duration = Duration::from_millis(500);

/// The registry of a site's previews: the subject in place of the flow, so a subject has at
/// most [`PER_SUBJECT`] and the site [`PER_SITE`].
pub fn registry() -> Watches {
    Watches::with_caps(PER_SUBJECT, PER_SITE, "previews")
}

/// A draft running in its sandbox, before its stream starts.
pub struct Preview {
    run: Running,
    probe: Arc<Probe>,
    hold: live::Hold,
    panics: mpsc::UnboundedReceiver<String>,
    nodes: usize,
}

/// Start `def` (compiled, its rights checked) in a sandbox of this site.
pub fn start(
    def: &FlowDef,
    ports: &BTreeMap<String, Ports>,
    ctx: &LinkCtx,
    site: &str,
    artifacts: &Artifacts,
) -> Result<Preview, LinkError> {
    let probe = Probe::new(def);
    // recording from the start: the first row holds what the nodes sent when they started
    let hold = probe.hold();
    let mode = Mode::Preview(Sandbox {
        probe: probe.clone(),
        site: site.to_owned(),
        flow: def.id.clone(),
    });
    // reads only: no tokens, so not even a stray command could prove a right
    let client = WyrmClient::new(ctx.client().clone());
    let (ptx, prx) = mpsc::unbounded_channel();
    let run = runtime::start(
        def,
        ports,
        &BTreeMap::new(),
        |_node, inject| Io {
            client: client.clone(),
            ctx: ctx.clone(),
            site: site.to_owned(),
            flow: format!("~preview/{}", def.id),
            inject,
        },
        ptx,
        Some(artifacts),
        probe.clone(),
        &mode,
    )
    .map_err(LinkError::invalid_parameter)?;
    Ok(Preview {
        run,
        probe,
        hold,
        panics: prx,
        nodes: def.nodes.len(),
    })
}

impl Preview {
    /// Stream its rows through `out` until it ends; `ticket` holds its place in the registry.
    pub fn spawn(
        self,
        only: Option<BTreeSet<String>>,
        period: Duration,
        ticket: Ticket,
        out: ReplySink,
    ) -> JoinHandle<()> {
        let Preview {
            run,
            probe,
            hold,
            mut panics,
            nodes,
        } = self;
        tokio::spawn(async move {
            let cancel = ticket.cancelled();
            probe.settle(nodes, SETTLE).await;
            let rows = out.clone();
            let stream = live::run(probe, only, period, TTL, cancel, move |v| {
                let rows = rows.clone();
                async move { rows.reply(v).await.is_ok() }
            });
            let end = tokio::select! {
                last = stream => Ok(last),
                Some(why) = panics.recv() => Err(why),
            };
            // nothing persists: the node states go with the run
            let _ = run.stop().await;
            drop(hold);
            match end {
                Ok(last) => {
                    let _ = out.done(last).await;
                }
                Err(why) => {
                    warn!("flow preview ended: {why}");
                    let _ = out.error(LinkError::internal(why)).await;
                }
            }
            drop(ticket);
        })
    }
}
