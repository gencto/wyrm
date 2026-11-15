//! History reads: the selector of `get <point>/~val?history=…` (spec 01/03),
//! the bounded read behind it and behind `sys/history` Get History, and the
//! queryable that answers it beside the memory storage.

use crate::engine::{now_us, Historian};
use crate::rollup::{Folder, Out, Rollup};
use std::sync::Arc;
use std::time::Duration;
use tracing::debug;
use wyrm_core::history::{HistoryParamError, HistoryQuery};
use wyrm_core::{codec, Attachment, HistRow, Status};
use zenoh::query::Query;
use zenoh::Session;

/// Rows of one answer: by default and at most (spec 01 `limit`).
pub const DEFAULT_LIMIT: usize = 10_000;
pub const MAX_LIMIT: usize = 100_000;
/// Rows one query may read from disk; a longer range is refused, not cut
/// (a rollup over part of a range would be wrong).
pub const MAX_SCAN: u64 = 5_000_000;
/// Queries reading at the same time; others wait up to [`QUEUE_WAIT`].
pub const MAX_QUERIES: usize = 4;
pub const QUEUE_WAIT: Duration = Duration::from_secs(5);
/// Rows per reply of `~val?history=`: several replies, each an array.
pub const CHUNK: usize = 5_000;

/// One history read with its range resolved: what a `~val?history=`
/// selector ([`HistoryQuery`]) asks at the time it came, or a Get History of
/// `sys/history`.
#[derive(Debug, Clone, PartialEq)]
pub struct HistoryRead {
    pub from: u64,
    pub to: u64,
    pub interval: Option<u64>,
    pub rollup: Rollup,
    pub limit: usize,
}

impl HistoryRead {
    /// The read of `q` at `now`: an open end is now, no limit is
    /// [`DEFAULT_LIMIT`], and no limit is above [`MAX_LIMIT`].
    pub fn of(q: &HistoryQuery, now: u64) -> Result<Self, HistoryParamError> {
        let (from, to) = q.range(now)?;
        Ok(Self {
            from,
            to,
            interval: q.window.map(|w| w.us()),
            rollup: q.rollup,
            limit: q.limit.map_or(DEFAULT_LIMIT, |l| l.get().min(MAX_LIMIT)),
        })
    }

    /// Raw rows `[t, v, q]` (no interval, no rollup).
    pub fn raw(&self) -> bool {
        self.interval.is_none() && self.rollup == Rollup::None
    }
}

#[derive(Debug, thiserror::Error)]
pub enum QueryError {
    #[error("history: too many reads at once; try again")]
    Busy,
    #[error("history: the range has more than {MAX_SCAN} rows; ask for a shorter one")]
    TooLarge,
    #[error(transparent)]
    Store(#[from] crate::store::Error),
}

impl QueryError {
    pub fn status(&self) -> Status {
        match self {
            QueryError::Busy => Status::Busy,
            QueryError::TooLarge => Status::InvalidParameter,
            QueryError::Store(_) => Status::InternalError,
        }
    }
}

/// The read a `~val` selector asks for (spec 01), at `now`; `None` when it
/// asks for no history (the storage answers it). Each parameter at most
/// once, and no other: a duplicate or unknown one is `invalid_parameter`
/// (spec 01 0.2.35, review S2).
pub fn parse_selector(params: &str, now: u64) -> Result<Option<HistoryRead>, HistoryParamError> {
    HistoryQuery::parse(params)?
        .map(|q| HistoryRead::of(&q, now))
        .transpose()
}

impl Historian {
    /// Rows of `key` for `q`; `None` if the point was never recorded.
    pub async fn query(&self, key: &str, q: &HistoryRead) -> Result<Option<Vec<Out>>, QueryError> {
        let _permit = tokio::time::timeout(QUEUE_WAIT, self.reads.acquire())
            .await
            .map_err(|_| QueryError::Busy)?
            .map_err(|_| QueryError::Busy)?;
        let st = self.store().clone();
        let (k, q) = (key.to_owned(), q.clone());
        tokio::task::spawn_blocking(move || {
            let Some(series) = st.series_id(&k, false)? else {
                return Ok(None);
            };
            let mut f = Folder::new(q.from, q.interval, q.rollup, q.limit.min(MAX_LIMIT));
            let (mut scanned, mut over) = (0u64, false);
            st.scan(series, q.from, q.to, |r| {
                scanned += 1;
                if scanned > MAX_SCAN {
                    over = true;
                    return false;
                }
                f.push(r)
            })?;
            if over {
                return Err(QueryError::TooLarge);
            }
            Ok(Some(f.finish()))
        })
        .await
        .map_err(|_| QueryError::Busy)?
    }
}

fn status_att(status: Status, err: Option<String>) -> Vec<u8> {
    let mut a = Attachment::with_status(status);
    a.err = err;
    codec::encode_to_vec(&a)
}

/// Answer `get <point>/~val?history=…` on `key_exprs` until the session
/// closes. Only points the historian records get an answer: one or more
/// replies, each an array of rows in time order (spec 03); a selector
/// without `history`/`since` is left to the storage. With `watches` (the
/// `sys/history` node) each watch answers for its point at
/// `<watches>/<group>/<watch>/~val` (ADR 0020).
pub(crate) async fn serve(
    h: Arc<Historian>,
    session: Session,
    mut key_exprs: Vec<String>,
    watches: Option<String>,
) {
    let watches = watches.map(|w| {
        key_exprs.push(format!("{w}/*/*/~val"));
        format!("{w}/")
    });
    let mut set = tokio::task::JoinSet::new();
    for ke in key_exprs {
        let qa = match session.declare_queryable(&ke).await {
            Ok(qa) => qa,
            Err(e) => {
                tracing::warn!(%ke, "history queryable: {e}");
                continue;
            }
        };
        let h = h.clone();
        let watches = watches.clone();
        set.spawn(async move {
            while let Ok(q) = qa.recv_async().await {
                tokio::spawn(answer(h.clone(), q, watches.clone()));
            }
        });
    }
    while set.join_next().await.is_some() {}
}

async fn answer(h: Arc<Historian>, q: Query, watches: Option<String>) {
    let parsed = parse_selector(q.parameters().as_str(), now_us());
    if matches!(parsed, Ok(None)) {
        return; // a plain `~val` read: the storage answers it
    }
    let ke = q.key_expr().as_str().to_owned();
    let Some(key) = ke.strip_suffix("/~val") else {
        return;
    };
    if key.contains(['*', '$']) {
        let err = status_att(
            Status::InvalidParameter,
            Some("history: one point, no wildcards".into()),
        );
        let _ = q.reply(&ke, Vec::<u8>::new()).attachment(err).await;
        return;
    }
    // A watch key reads its point's rows.
    let point = match watches.as_deref().and_then(|w| key.strip_prefix(w)) {
        Some(rest) => match rest
            .split_once('/')
            .and_then(|(g, id)| h.watch_point(g, id))
        {
            Some(p) => p,
            None => return,
        },
        None => key.to_owned(),
    };
    // Points it does not record get no answer from the historian.
    if !matches!(h.store().series_id(&point, false), Ok(Some(_))) {
        return;
    }
    let rows = match parsed {
        Ok(Some(hq)) => h.query(&point, &hq).await.map(|r| (r, hq.raw())),
        Ok(None) => return,
        Err(e) => {
            let err = status_att(e.status(), Some(e.to_string()));
            let _ = q.reply(&ke, Vec::<u8>::new()).attachment(err).await;
            return;
        }
    };
    let (rows, raw) = match rows {
        Ok((Some(rows), raw)) => (rows, raw),
        Ok((None, _)) => return,
        Err(e) => {
            let err = status_att(e.status(), Some(e.to_string()));
            let _ = q.reply(&ke, Vec::<u8>::new()).attachment(err).await;
            return;
        }
    };
    let ok = status_att(Status::Ok, None);
    let rows: Vec<HistRow> = rows
        .into_iter()
        .map(|(t, v, quality)| HistRow {
            t,
            v,
            q: raw.then_some(quality),
        })
        .collect();
    // An empty answer is one empty array: recorded, nothing in the range.
    let chunks: Vec<&[HistRow]> = if rows.is_empty() {
        vec![&[]]
    } else {
        rows.chunks(CHUNK).collect()
    };
    for chunk in chunks {
        let Ok(payload) = codec::to_vec(&chunk.to_vec()) else {
            return;
        };
        if let Err(e) = q.reply(&ke, payload).attachment(ok.clone()).await {
            debug!(%ke, "history reply: {e}");
            return;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::time::{parse_iso, US_PER_S};

    #[test]
    fn selectors() {
        let now = parse_iso("2026-10-22T12:00:00Z").unwrap();
        assert_eq!(parse_selector("", now), Ok(None));
        assert_eq!(parse_selector("view=full", now), Ok(None));
        let q = parse_selector("history=2026-10-22T11:00:00Z..&agg=avg&window=5m", now)
            .unwrap()
            .unwrap();
        assert_eq!((q.to - q.from) / US_PER_S, 3600);
        assert_eq!(q.rollup, Rollup::Avg);
        assert_eq!(q.interval, Some(300 * US_PER_S));
        assert_eq!(q.limit, DEFAULT_LIMIT);
        let q = parse_selector("since=2026-10-22T11:59:00Z&limit=999999", now)
            .unwrap()
            .unwrap();
        assert_eq!((q.to - q.from) / US_PER_S, 60);
        assert_eq!(q.limit, MAX_LIMIT);
        assert!(q.raw());
        for bad in [
            "history=yesterday..",
            "history=2026-10-22..&agg=median",
            "history=2026-10-22..&window=1M",
            "history=2026-10-22..&limit=0",
            "since=2027-01-01",
            "history=2027-01-01..",
            // review S2: the selector the gateway sent for an injected `from`
            "history=2026-01-01T00:00:00Z..&limit=100000&x=..&limit=10000",
            "history=2026-01-01T00:00:00Z..&limit=100000&limit=10000",
            "history=2026-01-01T00:00:00Z..&agg=avg&agg=sum",
        ] {
            assert!(parse_selector(bad, now).is_err(), "{bad}");
        }
    }
}
