//! Reactive `list` and `subscribe`. Each stream owns a task; dropping the
//! stream ends the task and undeclares its subscribers.

use crate::{decode, is_links_root, owner_key, Child, ClientError, Result, WyrmClient};
use std::collections::HashMap;
use std::pin::Pin;
use std::task::{Context, Poll};
use tokio::sync::mpsc;
use tracing::debug;
use wyrm_core::keyspace::{SUFFIX_META, SUFFIX_VAL};
use wyrm_core::{Attachment, NodeMeta, Sample};
use zenoh::sample::{Sample as ZSample, SampleKind};

/// A stream of events backed by a task. Use [`next`](Self::next) or the
/// `futures_core::Stream` impl.
pub struct EventStream<T> {
    rx: mpsc::Receiver<T>,
}

impl<T> EventStream<T> {
    pub(crate) fn new(rx: mpsc::Receiver<T>) -> Self {
        Self { rx }
    }

    pub async fn next(&mut self) -> Option<T> {
        self.rx.recv().await
    }
}

impl<T> futures_core::Stream for EventStream<T> {
    type Item = T;
    fn poll_next(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Option<T>> {
        self.rx.poll_recv(cx)
    }
}

#[derive(Debug, Clone, PartialEq)]
pub enum ListEvent {
    /// Full snapshot: first event, and again after the owner reconnects.
    Refreshed(Vec<Child>),
    Added(Child),
    Changed(Child),
    Removed(String),
    /// `None`: the owning link is gone; `Some(name)`: a dynamic child is gone.
    Disconnected(Option<String>),
    /// A dynamic child is back.
    Connected(String),
}

#[derive(Debug, Clone, PartialEq)]
pub enum ValEvent {
    Sample {
        /// Node key (without `/~val`).
        key: String,
        sample: Sample,
        /// Extended quality from the attachment (`bad/comm_fail`, …).
        qual: Option<String>,
    },
    Removed(String),
}

/// `prefix/<name>/suffix` → `name` (single segment), else `None`.
fn child_name<'a>(key: &'a str, prefix: &str, suffix: &str) -> Option<&'a str> {
    let rest = key.strip_prefix(prefix)?.strip_prefix('/')?;
    let name = if suffix.is_empty() {
        rest
    } else {
        rest.strip_suffix(suffix)?.strip_suffix('/')?
    };
    (!name.is_empty() && !name.contains('/')).then_some(name)
}

pub(crate) async fn list(client: WyrmClient, node: String) -> Result<EventStream<ListEvent>> {
    let s = client.session();
    // Subscribe first, snapshot second: nothing between them is lost.
    let meta_sub = s
        .declare_subscriber(format!("{node}/*/{SUFFIX_META}"))
        .await?;
    let live_sub = s
        .liveliness()
        .declare_subscriber(format!("{node}/*"))
        .await?;
    let owner = (!is_links_root(&node)).then(|| owner_key(&node)).flatten();
    let owner_sub = match &owner {
        Some(o) => Some(s.liveliness().declare_subscriber(o.clone()).await?),
        None => None,
    };
    let snapshot = client.children(&node).await?;

    let (tx, rx) = mpsc::channel(256);
    let mut known: HashMap<String, u32> = snapshot
        .iter()
        .map(|c| (c.name.clone(), c.meta.rev.unwrap_or(0)))
        .collect();
    tx.send(ListEvent::Refreshed(snapshot))
        .await
        .map_err(|_| ClientError::new(wyrm_core::Status::Closed, "stream dropped"))?;
    let links_root = is_links_root(&node);

    tokio::spawn(async move {
        let owner_next = || async {
            match &owner_sub {
                Some(o) => o.recv_async().await.ok(),
                None => std::future::pending().await,
            }
        };
        loop {
            let ev = tokio::select! {
                Ok(smp) = meta_sub.recv_async() => on_meta(&node, &smp, &mut known),
                Ok(smp) = live_sub.recv_async() => {
                    on_child_liveliness(&client, &node, links_root, &smp, &mut known).await
                }
                Some(smp) = owner_next() => match smp.kind() {
                    SampleKind::Delete => Some(ListEvent::Disconnected(None)),
                    SampleKind::Put => match client.children(&node).await {
                        Ok(snap) => {
                            known = snap.iter().map(|c| (c.name.clone(), c.meta.rev.unwrap_or(0))).collect();
                            Some(ListEvent::Refreshed(snap))
                        }
                        Err(e) => {
                            debug!("re-list after reconnect failed: {e}");
                            None
                        }
                    },
                },
                else => return,
            };
            if let Some(ev) = ev {
                if tx.send(ev).await.is_err() {
                    return;
                }
            }
        }
    });
    Ok(EventStream::new(rx))
}

fn on_meta(node: &str, smp: &ZSample, known: &mut HashMap<String, u32>) -> Option<ListEvent> {
    let name = child_name(smp.key_expr().as_str(), node, SUFFIX_META)?.to_owned();
    match smp.kind() {
        SampleKind::Delete => known.remove(&name).map(|_| ListEvent::Removed(name)),
        SampleKind::Put => {
            let meta: NodeMeta = decode(&smp.payload().to_bytes()).ok()?;
            let rev = meta.rev.unwrap_or(0);
            match known.insert(name.clone(), rev) {
                None => Some(ListEvent::Added(Child { name, meta })),
                Some(old) if rev > old => Some(ListEvent::Changed(Child { name, meta })),
                Some(old) => {
                    known.insert(name, old);
                    None
                }
            }
        }
    }
}

async fn on_child_liveliness(
    client: &WyrmClient,
    node: &str,
    links_root: bool,
    smp: &ZSample,
    known: &mut HashMap<String, u32>,
) -> Option<ListEvent> {
    let name = child_name(smp.key_expr().as_str(), node, "")?.to_owned();
    match (smp.kind(), links_root) {
        (SampleKind::Put, true) => {
            if known.contains_key(&name) {
                return None;
            }
            let meta = client
                .meta(&format!("{node}/{name}"))
                .await
                .unwrap_or_default();
            known.insert(name.clone(), meta.rev.unwrap_or(0));
            Some(ListEvent::Added(Child { name, meta }))
        }
        (SampleKind::Delete, true) => known.remove(&name).map(|_| ListEvent::Removed(name)),
        (SampleKind::Put, false) => Some(ListEvent::Connected(name)),
        (SampleKind::Delete, false) => Some(ListEvent::Disconnected(Some(name))),
    }
}

pub(crate) async fn subscribe(
    client: WyrmClient,
    pattern: String,
) -> Result<EventStream<ValEvent>> {
    let ke = format!("{pattern}/{SUFFIX_VAL}");
    let s = client.session();
    let sub = s.declare_subscriber(&ke).await?;
    let stored = s.get(&ke).timeout(client.timeout).await?;

    let (tx, rx) = mpsc::channel(1024);
    tokio::spawn(async move {
        let mut last_t: HashMap<String, u64> = HashMap::new();
        while let Ok(reply) = stored.recv_async().await {
            if let Ok(smp) = reply.result() {
                if let Some(ev) = on_val(smp, &mut last_t) {
                    if tx.send(ev).await.is_err() {
                        return;
                    }
                }
            }
        }
        while let Ok(smp) = sub.recv_async().await {
            if let Some(ev) = on_val(&smp, &mut last_t) {
                if tx.send(ev).await.is_err() {
                    return;
                }
            }
        }
    });
    Ok(EventStream::new(rx))
}

/// QoS 2/3: AdvancedSubscriber with history (cached samples of publishers
/// with `cfg.qos >= 2`, also late-joining ones) and gap recovery.
#[cfg(feature = "advanced")]
pub(crate) async fn subscribe_reliable(
    client: WyrmClient,
    pattern: String,
) -> Result<EventStream<ValEvent>> {
    use zenoh_ext::{AdvancedSubscriberBuilderExt, HistoryConfig, RecoveryConfig};
    let sub = client
        .session()
        .declare_subscriber(format!("{pattern}/{SUFFIX_VAL}"))
        .advanced()
        .history(HistoryConfig::default().detect_late_publishers())
        .recovery(RecoveryConfig::default().heartbeat())
        .subscriber_detection()
        .await?;
    let (tx, rx) = mpsc::channel(1024);
    tokio::spawn(async move {
        let mut last_t: HashMap<String, u64> = HashMap::new();
        while let Ok(smp) = sub.recv_async().await {
            if let Some(ev) = on_val(&smp, &mut last_t) {
                if tx.send(ev).await.is_err() {
                    return;
                }
            }
        }
    });
    Ok(EventStream::new(rx))
}

fn on_val(smp: &ZSample, last_t: &mut HashMap<String, u64>) -> Option<ValEvent> {
    let key = smp
        .key_expr()
        .as_str()
        .strip_suffix(SUFFIX_VAL)?
        .strip_suffix('/')?
        .to_owned();
    if smp.kind() == SampleKind::Delete {
        last_t.remove(&key);
        return Some(ValEvent::Removed(key));
    }
    let sample: Sample = decode(&smp.payload().to_bytes()).ok()?;
    if last_t.get(&key).is_some_and(|t| *t > sample.t) {
        return None;
    }
    last_t.insert(key.clone(), sample.t);
    let qual = smp
        .attachment()
        .and_then(|a| decode::<Attachment>(&a.to_bytes()).ok())
        .and_then(|a| a.qual);
    Some(ValEvent::Sample { key, sample, qual })
}

#[cfg(test)]
mod tests {
    use super::child_name;

    #[test]
    fn child_names() {
        assert_eq!(child_name("a/b/x/~meta", "a/b", "~meta"), Some("x"));
        assert_eq!(child_name("a/b/x/y/~meta", "a/b", "~meta"), None);
        assert_eq!(child_name("a/b/x", "a/b", ""), Some("x"));
        assert_eq!(child_name("a/bx/~meta", "a/b", "~meta"), None);
    }
}
