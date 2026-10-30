//! Diagnostics counters of connections and devices (ruling 12): value
//! leaves `requests`, `errors`, `timeouts`, `exceptions`, the driver's
//! [`Driver::DIAG_EXTRA`], `last_rtt_ms` and `avg_rtt_ms` (EWMA, α = 0.1).
//!
//! The owner task counts the [`Outcome`]s of each operation into a
//! [`Book`] shared with one flusher task per connection. The flusher
//! publishes a leaf only when its value changed, at most once every
//! [`PERIOD`], and at once when a requester reads the node (`~meta` of the
//! connection, the device or one of their leaves). A connection's book
//! starts empty whenever the connection (re)starts; a device's on its own
//! `restart` and `start`. A reconnect after a failure keeps the counts.

use super::{Driver, Outcome};
use crate::ctx::{now_us, LinkCtx};
use std::collections::BTreeMap;
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tokio::sync::{broadcast, mpsc, watch};
use wyrm_core::meta::Profile;
use wyrm_core::{NodeMeta, Quality, TypeCode, Value};

/// Shortest time between two publishes of a changed leaf (reads aside).
pub(crate) const PERIOD: Duration = Duration::from_secs(10);

/// Profile of a diagnostics leaf.
pub(crate) const PROFILE: &str = "wy:df-diag";

const COUNTS: [&str; 4] = ["requests", "errors", "timeouts", "exceptions"];
const RTT: [&str; 2] = ["last_rtt_ms", "avg_rtt_ms"];
const ALPHA: f64 = 0.1;

/// Leaf names, in order, for driver `D`.
pub(crate) fn names<D: Driver>() -> Vec<&'static str> {
    COUNTS
        .iter()
        .chain(D::DIAG_EXTRA)
        .chain(RTT.iter())
        .copied()
        .collect()
}

/// The meta of a diagnostics leaf.
pub(crate) fn leaf_meta(name: &str) -> NodeMeta {
    let m = NodeMeta::leaf(TypeCode::Number).is(PROFILE);
    if name.ends_with("_ms") {
        m.unit("ms")
    } else {
        m
    }
}

/// The counters of one node.
#[derive(Debug, Clone, Default, PartialEq)]
pub(crate) struct Stats {
    /// [`COUNTS`] then [`Driver::DIAG_EXTRA`].
    counts: Vec<u64>,
    last_rtt_ms: Option<f64>,
    avg_rtt_ms: Option<f64>,
}

impl Stats {
    fn bump(&mut self, i: usize) {
        if self.counts.len() <= i {
            self.counts.resize(i + 1, 0);
        }
        self.counts[i] += 1;
    }

    fn rtt(&mut self, d: Duration) {
        let ms = d.as_secs_f64() * 1000.0;
        self.last_rtt_ms = Some(ms);
        self.avg_rtt_ms = Some(match self.avg_rtt_ms {
            None => ms,
            Some(a) => a + ALPHA * (ms - a),
        });
    }

    /// Count `o`; `extra` = [`Driver::DIAG_EXTRA`].
    fn apply(&mut self, o: Outcome, extra: &[&str]) {
        match o {
            Outcome::Reply(d) => {
                self.bump(0);
                self.rtt(d);
            }
            Outcome::Exception(d) => {
                self.bump(0);
                self.bump(3);
                self.rtt(d);
            }
            Outcome::Timeout => {
                self.bump(0);
                self.bump(2);
            }
            Outcome::Error => {
                self.bump(0);
                self.bump(1);
            }
            Outcome::Count(name) => match extra.iter().position(|n| *n == name) {
                Some(i) => self.bump(COUNTS.len() + i),
                None => tracing::debug!("unknown diagnostics counter {name}"),
            },
        }
    }

    /// Leaf values in the order of [`names`]; no RTT yet = 0.
    fn values<D: Driver>(&self) -> Vec<Value> {
        let n = COUNTS.len() + D::DIAG_EXTRA.len();
        (0..n)
            .map(|i| Value::UInt(self.counts.get(i).copied().unwrap_or(0)))
            .chain([
                Value::Float(self.last_rtt_ms.unwrap_or(0.0)),
                Value::Float(self.avg_rtt_ms.unwrap_or(0.0)),
            ])
            .collect()
    }
}

/// The counters of one connection and its devices.
#[derive(Debug, Default)]
pub(crate) struct Book {
    conn: Stats,
    devs: BTreeMap<String, Stats>,
}

pub(crate) type SharedBook = Arc<Mutex<Book>>;

fn lock(b: &SharedBook) -> std::sync::MutexGuard<'_, Book> {
    b.lock().unwrap_or_else(|p| p.into_inner())
}

/// Count `outcomes` for the connection and, when given, the device.
pub(crate) fn record<D: Driver>(book: &SharedBook, dev: Option<&str>, outcomes: &[Outcome]) {
    if outcomes.is_empty() {
        return;
    }
    let mut b = lock(book);
    for o in outcomes {
        b.conn.apply(*o, D::DIAG_EXTRA);
    }
    if let Some(d) = dev {
        let s = b.devs.entry(d.to_owned()).or_default();
        for o in outcomes {
            s.apply(*o, D::DIAG_EXTRA);
        }
    }
}

/// A device's counters from zero (new device, `restart`, `start`).
pub(crate) fn reset_dev(book: &SharedBook, dev: &str) {
    lock(book).devs.insert(dev.to_owned(), Stats::default());
}

pub(crate) fn remove_dev(book: &SharedBook, dev: &str) {
    lock(book).devs.remove(dev);
}

/// A book with these devices at zero.
pub(crate) fn new_book<'a>(devs: impl IntoIterator<Item = &'a String>) -> SharedBook {
    let b = Book {
        conn: Stats::default(),
        devs: devs
            .into_iter()
            .map(|d| (d.clone(), Stats::default()))
            .collect(),
    };
    Arc::new(Mutex::new(b))
}

/// Publish the changed leaves of `node` (`conn` or `conn/dev`).
async fn flush_node<D: Driver>(ctx: &LinkCtx, node: &str, stats: &Stats) {
    for (name, v) in names::<D>().into_iter().zip(stats.values::<D>()) {
        let path = format!("{node}/{name}");
        // A stored child of the same name keeps its node: no leaf there.
        let is_leaf = ctx
            .meta(&path)
            .is_some_and(|m| m.is == Some(Profile::Name(PROFILE.into())));
        if !is_leaf || ctx.last(&path).is_some_and(|s| s.v == v) {
            continue;
        }
        let _ = ctx.update(&path, v, Quality::Good, now_us()).await;
    }
}

/// What to flush: the connection (`None`) or one device.
fn node_of(conn: &str, path: &str, leaves: &[&str]) -> Option<Option<String>> {
    let rest = path.strip_prefix(conn)?;
    if rest.is_empty() {
        return Some(None);
    }
    let parts: Vec<&str> = rest.strip_prefix('/')?.split('/').collect();
    match parts.as_slice() {
        [leaf] if leaves.contains(leaf) => Some(None),
        [dev] => Some(Some((*dev).to_owned())),
        [dev, leaf] if leaves.contains(leaf) => Some(Some((*dev).to_owned())),
        _ => None,
    }
}

/// Flush requests from the framework (`None` = the connection, or a device).
pub(crate) type Nudge = mpsc::Sender<Option<String>>;

/// One per running connection: publishes the book's changes every
/// [`PERIOD`], and at once on a read of a node or a nudge.
pub(crate) async fn flusher<D: Driver>(
    ctx: LinkCtx,
    conn: String,
    book: SharedBook,
    mut nudges: mpsc::Receiver<Option<String>>,
    mut stop: watch::Receiver<bool>,
) {
    let mut reads = ctx.reads();
    let leaves = names::<D>();
    let mut iv = tokio::time::interval(PERIOD);
    iv.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
    loop {
        let only: Option<Option<String>> = tokio::select! {
            _ = iv.tick() => None,
            n = nudges.recv() => match n {
                Some(n) => Some(n),
                None => return,
            },
            r = reads.recv() => match r {
                Ok(p) => match node_of(&conn, &p, &leaves) {
                    Some(n) => Some(n),
                    None => continue,
                },
                Err(broadcast::error::RecvError::Lagged(_)) => None,
                Err(broadcast::error::RecvError::Closed) => return,
            },
            _ = stop.changed() => return,
        };
        // Copy out: no lock across a publish.
        let (conn_stats, devs) = {
            let b = lock(&book);
            (b.conn.clone(), b.devs.clone())
        };
        match only {
            None => {
                flush_node::<D>(&ctx, &conn, &conn_stats).await;
                for (d, s) in &devs {
                    flush_node::<D>(&ctx, &format!("{conn}/{d}"), s).await;
                }
            }
            Some(None) => flush_node::<D>(&ctx, &conn, &conn_stats).await,
            Some(Some(d)) => {
                if let Some(s) = devs.get(&d) {
                    flush_node::<D>(&ctx, &format!("{conn}/{d}"), s).await;
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ewma_and_disjoint_counts() {
        let mut s = Stats::default();
        let ms = Duration::from_millis;
        for o in [
            Outcome::Reply(ms(10)),
            Outcome::Reply(ms(20)),
            Outcome::Exception(ms(30)),
            Outcome::Timeout,
            Outcome::Error,
            Outcome::Count("reopens"),
            Outcome::Count("unknown"),
        ] {
            s.apply(o, &["reopens"]);
        }
        assert_eq!(s.counts, vec![5, 1, 1, 1, 1]);
        assert_eq!(s.last_rtt_ms, Some(30.0));
        // 10 → 10 + 0.1·10 = 11 → 11 + 0.1·19 = 12.9
        assert!((s.avg_rtt_ms.unwrap() - 12.9).abs() < 1e-9);
    }

    #[test]
    fn reads_map_to_nodes() {
        let leaves = ["requests", "avg_rtt_ms"];
        assert_eq!(node_of("c1", "c1", &leaves), Some(None));
        assert_eq!(node_of("c1", "c1/requests", &leaves), Some(None));
        assert_eq!(node_of("c1", "c1/d1", &leaves), Some(Some("d1".into())));
        assert_eq!(
            node_of("c1", "c1/d1/avg_rtt_ms", &leaves),
            Some(Some("d1".into()))
        );
        assert_eq!(node_of("c1", "c1/d1/p", &leaves), None);
        assert_eq!(node_of("c1", "c10", &leaves), None);
        assert_eq!(node_of("c1", "c2/d1", &leaves), None);
    }
}
