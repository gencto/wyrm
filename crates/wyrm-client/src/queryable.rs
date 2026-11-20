//! A queryable whose handler never blocks the thread that delivers the query.
//!
//! Zenoh calls a queryable's handler on the querier's thread when both are in
//! one process: a `get` on a tokio worker runs the handler on that worker. The
//! default handler (a FIFO of 256) blocks that thread while it is full, and if
//! the task that drains it waits for a worker of the same runtime, every
//! worker can end up blocked in the send with nobody left to drain it
//! (docs/backlog.md §14: the historian's 10 000 `get ~val` into its own
//! `~val?history=` queryable). Every in-process responder of the broker
//! declares its queryable here instead: the handler only filters and
//! `try_send`s, and a query it does not keep is dropped, which ends it for
//! the querier at once (Zenoh sends the final reply on drop).

use tokio::sync::mpsc;
use tracing::debug;
use zenoh::query::{Query, Queryable};
use zenoh::Session;

type Keep = Box<dyn Fn(&Query) -> bool + Send + Sync>;
type OnFull = Box<dyn Fn(Query) + Send + Sync>;

/// A queryable to declare: the key expression, `complete`, the depth of its
/// queue, the filter that runs in the handler and what a full queue does.
pub struct Bounded {
    key: String,
    complete: bool,
    depth: usize,
    keep: Keep,
    on_full: OnFull,
}

/// A queryable on `key` with a queue of `depth` queries (at least 1).
pub fn bounded(key: impl Into<String>, depth: usize) -> Bounded {
    Bounded {
        key: key.into(),
        complete: false,
        depth: depth.max(1),
        keep: Box::new(|_| true),
        on_full: Box::new(|q| {
            debug!(key = %q.key_expr(), "the responder's query queue is full: query dropped");
        }),
    }
}

impl Bounded {
    /// Zenoh's `complete` flag of the queryable.
    pub fn complete(mut self, complete: bool) -> Self {
        self.complete = complete;
        self
    }

    /// Only queries `keep` accepts take room in the queue; the others are
    /// dropped (answered with nothing) in the handler. `keep` runs on the
    /// querier's thread: short, no I/O, no lock that a reply waits for.
    pub fn keep(mut self, keep: impl Fn(&Query) -> bool + Send + Sync + 'static) -> Self {
        self.keep = Box::new(keep);
        self
    }

    /// What happens to a query that finds the queue full (default: dropped,
    /// logged at `debug`). It runs on the querier's thread as `keep` does:
    /// hand the query to a task (`Handle::spawn`), never reply in it.
    pub fn on_full(mut self, on_full: impl Fn(Query) + Send + Sync + 'static) -> Self {
        self.on_full = Box::new(on_full);
        self
    }

    /// Declare it on `session`; the queries it keeps come out of the receiver.
    pub async fn declare(
        self,
        session: &Session,
    ) -> zenoh::Result<(Queryable<()>, mpsc::Receiver<Query>)> {
        let (tx, rx) = mpsc::channel::<Query>(self.depth);
        let (keep, on_full) = (self.keep, self.on_full);
        let queryable = session
            .declare_queryable(&self.key)
            .complete(self.complete)
            .callback(move |q| {
                if !keep(&q) {
                    return;
                }
                if let Err(mpsc::error::TrySendError::Full(q)) = tx.try_send(q) {
                    on_full(q);
                }
            })
            .await?;
        Ok((queryable, rx))
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used, clippy::expect_used, reason = "test code")]
    use super::*;
    use std::time::Duration;

    async fn session() -> Session {
        let mut c = zenoh::Config::default();
        for (k, v) in [
            ("mode", r#""peer""#),
            ("listen/endpoints", "[]"),
            ("connect/endpoints", "[]"),
            ("scouting/multicast/enabled", "false"),
            ("scouting/gossip/enabled", "false"),
        ] {
            c.insert_json5(k, v).unwrap();
        }
        zenoh::open(c).await.unwrap()
    }

    /// Many more gets than the queue holds, from a runtime of one worker,
    /// while nobody reads the queue: every get ends, none blocks.
    #[tokio::test(flavor = "multi_thread", worker_threads = 1)]
    async fn a_full_queue_never_blocks_the_querier() {
        let s = session().await;
        let (_q, mut rx) = bounded("t/**", 4)
            .keep(|q| q.parameters().as_str() != "skip")
            .declare(&s)
            .await
            .unwrap();
        let all = async {
            for i in 0..600 {
                let params = if i % 2 == 0 { "skip" } else { "" };
                let replies = s
                    .get(format!("t/{i}?{params}"))
                    .timeout(Duration::from_secs(5))
                    .await
                    .unwrap();
                // a skipped or dropped query ends without a reply
                if i % 2 == 0 || i > 20 {
                    assert!(replies.recv_async().await.is_err(), "get {i}");
                }
            }
        };
        tokio::time::timeout(Duration::from_secs(20), all)
            .await
            .expect("gets ended");
        // the queue kept the first four that were not skipped
        let mut kept = 0;
        while let Ok(q) = rx.try_recv() {
            assert_ne!(q.parameters().as_str(), "skip");
            kept += 1;
        }
        assert_eq!(kept, 4);
    }
}
