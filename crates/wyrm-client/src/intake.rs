//! Zenoh handlers that never block the session.
//!
//! The default Zenoh handler is a FIFO of 256 items, and a full FIFO
//! blocks the session's receive path: every other reply and sample of that
//! session waits too (`zenoh/src/api/handlers/fifo.rs`). A stream whose
//! consumer is slow, or that is not read while another query runs, would
//! freeze the whole session — for the gateway, every user at once.
//!
//! An [`Intake`] is state owned by the stream. A [`Feed`] is the Zenoh
//! handler that writes into it: one short lock per item, no await, no I/O,
//! and the state decides what a full buffer does with one more item (each
//! stream kind has its own policy, see `streams.rs` and `lib.rs`). The
//! reader polls the same state and parks its waker there.
//!
//! A `Feed` holds its intake weakly: once the reader (the stream, or its
//! task) is gone, the state is freed and later items are dropped at once,
//! even while Zenoh still holds the handler (a long `get`).

use std::sync::{Arc, Mutex, MutexGuard, Weak};
use std::task::{Context, Poll, Waker};
use zenoh::handlers::{Callback, IntoHandler};

pub(crate) struct Intake<S> {
    inner: Mutex<Inner<S>>,
}

struct Inner<S> {
    state: S,
    waker: Option<Waker>,
}

impl<S: Send + 'static> Intake<S> {
    pub(crate) fn new(state: S) -> Arc<Self> {
        Arc::new(Self {
            inner: Mutex::new(Inner { state, waker: None }),
        })
    }

    fn lock(&self) -> MutexGuard<'_, Inner<S>> {
        // a panic in a policy must not turn every later push into one
        self.inner.lock().unwrap_or_else(|e| e.into_inner())
    }

    /// Change the state and wake the reader.
    pub(crate) fn update(&self, f: impl FnOnce(&mut S)) {
        let waker = {
            let mut g = self.lock();
            f(&mut g.state);
            g.waker.take()
        };
        if let Some(w) = waker {
            w.wake();
        }
    }

    /// `f` returns `Some` when it has an answer for the reader; `None`
    /// parks the reader until the next [`update`](Self::update).
    pub(crate) fn poll<T>(
        &self,
        cx: &mut Context<'_>,
        f: impl FnOnce(&mut S) -> Option<T>,
    ) -> Poll<T> {
        let mut g = self.lock();
        match f(&mut g.state) {
            Some(t) => Poll::Ready(t),
            None => {
                g.waker = Some(cx.waker().clone());
                Poll::Pending
            }
        }
    }

    /// Read the state.
    pub(crate) fn with<T>(&self, f: impl FnOnce(&S) -> T) -> T {
        f(&self.lock().state)
    }

    pub(crate) async fn next<T>(&self, mut f: impl FnMut(&mut S) -> Option<T>) -> T {
        std::future::poll_fn(|cx| self.poll(cx, &mut f)).await
    }

    /// A Zenoh handler: `push` runs for every item, `done` once, when Zenoh
    /// drops the handler (the query is final, the subscriber undeclared or
    /// the session closed). Neither runs after the last `Arc` is gone.
    pub(crate) fn feed<T>(
        self: &Arc<Self>,
        push: impl Fn(&mut S, T) + Send + Sync + 'static,
        done: impl FnOnce(&mut S) + Send + Sync + 'static,
    ) -> Feed<S, T> {
        Feed {
            intake: Arc::downgrade(self),
            push: Box::new(push),
            done: Box::new(done),
        }
    }
}

type Push<S, T> = Box<dyn Fn(&mut S, T) + Send + Sync>;
type Done<S> = Box<dyn FnOnce(&mut S) + Send + Sync>;

pub(crate) struct Feed<S, T> {
    intake: Weak<Intake<S>>,
    push: Push<S, T>,
    done: Done<S>,
}

/// Runs `done` when the callback (and so this guard) is dropped by Zenoh.
struct OnDrop<S: Send + 'static> {
    intake: Weak<Intake<S>>,
    done: Option<Done<S>>,
}

impl<S: Send + 'static> Drop for OnDrop<S> {
    fn drop(&mut self) {
        if let (Some(done), Some(intake)) = (self.done.take(), self.intake.upgrade()) {
            intake.update(done);
        }
    }
}

impl<S: Send + 'static, T: Send + 'static> IntoHandler<T> for Feed<S, T> {
    type Handler = ();

    fn into_handler(self) -> (Callback<T>, ()) {
        let guard = OnDrop {
            intake: self.intake,
            done: Some(self.done),
        };
        let push = self.push;
        let cb = move |t: T| {
            if let Some(intake) = guard.intake.upgrade() {
                intake.update(|s| push(s, t));
            }
        };
        (Callback::from(cb), ())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn feed_pushes_and_reports_its_end() {
        let intake = Intake::new((Vec::<u32>::new(), false));
        let (cb, ()) = intake
            .feed(|s: &mut (Vec<u32>, bool), t| s.0.push(t), |s| s.1 = true)
            .into_handler();
        cb.call(1);
        cb.call(2);
        drop(cb);
        let (items, done) = intake.next(|s| Some(s.clone())).await;
        assert_eq!(items, [1, 2]);
        assert!(done);
    }

    #[test]
    fn a_feed_without_its_reader_keeps_nothing() {
        let intake = Intake::new(Vec::<u32>::new());
        let weak = Arc::downgrade(&intake);
        let (cb, ()) = intake
            .feed(|s: &mut Vec<u32>, t| s.push(t), |_| {})
            .into_handler();
        cb.call(1);
        drop(intake); // the reader is gone, Zenoh still holds the handler
        assert!(weak.upgrade().is_none(), "the buffer is freed");
        for t in 0..1000 {
            cb.call(t); // dropped at once
        }
        drop(cb);
    }
}
