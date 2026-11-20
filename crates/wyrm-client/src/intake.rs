//! Zenoh handlers that never block the session.
//!
//! The default Zenoh handler is a FIFO of 256 items, and a full FIFO
//! blocks the session's receive path: every other reply and sample of that
//! session waits too (`zenoh/src/api/handlers/fifo.rs`). A stream whose
//! consumer is slow, or that is not read while another query runs, would
//! freeze the whole session — for the gateway, every user at once.
//!
//! An [`Intake`] is state owned by the stream. A [`Feed`] is the Zenoh
//! handler that writes into it: one short lock per item (an item is decoded
//! before the lock, [`Intake::feed_map`]), no await, no I/O, and the state
//! decides what a full buffer does with one more item (each stream kind has
//! its own policy, see `streams.rs` and `lib.rs`). The reader polls the same
//! state and parks its waker there.
//!
//! A `Feed` holds its intake weakly: once the reader (the stream, or its
//! task) is gone, the state is freed and later items are dropped at once,
//! even while Zenoh still holds the handler (a long `get`).

use std::sync::{Arc, Mutex, MutexGuard, TryLockError, Weak};
use std::task::{Context, Poll, Waker};
use zenoh::handlers::{Callback, IntoHandler};

/// Tries of the lock before a thread waits for it in the kernel.
const SPINS: u32 = 64;

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

    /// The lock is held for one push or one pop, some tens of nanoseconds,
    /// by two threads that meet there at the rate of the samples: Zenoh's
    /// receive thread and the reader's. A thread that finds it taken tries
    /// again a few times before it waits: the standard lock of macOS waits
    /// in the kernel at once, and in a profile of a pattern subscription at
    /// 50 000 samples/s more than half of the handler's time was that wait
    /// (docs/backlog.md §14). It never yields its turn (a yield on a loaded
    /// host costs a scheduler quantum, 10 ms measured): after [`SPINS`]
    /// tries it waits as before.
    fn lock(&self) -> MutexGuard<'_, Inner<S>> {
        for _ in 0..SPINS {
            match self.inner.try_lock() {
                Ok(g) => return g,
                // a panic in a policy must not turn every later push into one
                Err(TryLockError::Poisoned(e)) => return e.into_inner(),
                Err(TryLockError::WouldBlock) => std::hint::spin_loop(),
            }
        }
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
    pub(crate) fn feed<T: 'static>(
        self: &Arc<Self>,
        push: impl Fn(&mut S, T) + Send + Sync + 'static,
        done: impl FnOnce(&mut S) + Send + Sync + 'static,
    ) -> Feed<S, T> {
        self.feed_map(Some, push, done)
    }

    /// A [`feed`](Self::feed) whose items are prepared before the lock is
    /// taken: `prepare` runs on Zenoh's thread with the state unlocked
    /// (decoding, a filter), and only what it returns is pushed. The reader
    /// never waits for a `prepare`, and it runs for no item once the reader
    /// is gone.
    pub(crate) fn feed_map<T: 'static, U: 'static>(
        self: &Arc<Self>,
        prepare: impl Fn(T) -> Option<U> + Send + Sync + 'static,
        push: impl Fn(&mut S, U) + Send + Sync + 'static,
        done: impl FnOnce(&mut S) + Send + Sync + 'static,
    ) -> Feed<S, T> {
        Feed {
            intake: Arc::downgrade(self),
            push: Box::new(move |intake, t| {
                if let Some(u) = prepare(t) {
                    intake.update(|s| push(s, u));
                }
            }),
            done: Box::new(done),
        }
    }
}

type Push<S, T> = Box<dyn Fn(&Intake<S>, T) + Send + Sync>;
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
                push(&intake, t);
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

    #[test]
    fn an_item_is_prepared_before_the_lock_and_only_for_a_reader() {
        let intake = Intake::new(Vec::<u32>::new());
        let prepared = Arc::new(std::sync::atomic::AtomicU32::new(0));
        let (p2, i2) = (prepared.clone(), Arc::downgrade(&intake));
        let (cb, ()) = intake
            .feed_map(
                move |t: u32| {
                    p2.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                    // the state is free while an item is prepared: the reader could take it
                    let free = i2.upgrade().is_some_and(|i| i.inner.try_lock().is_ok());
                    assert!(free, "prepare ran with the buffer locked");
                    t.is_multiple_of(2).then_some(t * 10)
                },
                |s: &mut Vec<u32>, u| s.push(u),
                |_| {},
            )
            .into_handler();
        for t in 0..6 {
            cb.call(t);
        }
        // what `prepare` refused never reached the state
        assert_eq!(intake.with(Vec::clone), [0, 20, 40]);
        assert_eq!(prepared.load(std::sync::atomic::Ordering::Relaxed), 6);
        drop(intake);
        cb.call(8); // no reader: not even prepared
        assert_eq!(prepared.load(std::sync::atomic::Ordering::Relaxed), 6);
    }

    #[test]
    fn a_panic_in_a_policy_does_not_break_the_buffer() {
        let intake = Intake::new(Vec::<u32>::new());
        let i2 = intake.clone();
        let r = std::thread::spawn(move || i2.update(|_| panic!("a policy panics"))).join();
        assert!(r.is_err());
        intake.update(|s| s.push(1));
        assert_eq!(intake.with(Vec::clone), [1]);
    }

    /// Two threads at the lock at once: every push arrives, in each thread's order.
    #[test]
    fn pushes_of_two_threads_all_arrive() {
        const N: u32 = 50_000;
        let intake = Intake::new(Vec::<(u8, u32)>::new());
        let threads: Vec<_> = (0..2u8)
            .map(|who| {
                let i = intake.clone();
                std::thread::spawn(move || {
                    for n in 0..N {
                        i.update(|s| s.push((who, n)));
                    }
                })
            })
            .collect();
        // a reader that takes what is there meanwhile
        let mut got = Vec::new();
        while got.len() < 2 * N as usize {
            intake.update(|s| got.append(s));
            std::hint::spin_loop();
        }
        for t in threads {
            t.join().unwrap();
        }
        for who in 0..2u8 {
            let of: Vec<u32> = got.iter().filter(|x| x.0 == who).map(|x| x.1).collect();
            assert!(of.iter().copied().eq(0..N), "thread {who}");
        }
    }
}
