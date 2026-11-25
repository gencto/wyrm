//! What the stored read of a pattern `subscribe` costs in the client, with no session: the
//! handler the client gives its `get` is called by hand, once per reply, as Zenoh calls it
//! when the read is final (`wyrm_client::testkit::value_stream_stored`), and the stream is
//! read as a consumer reads it (docs/backlog.md §14).
//!
//! * `a_stored_read_wakes_its_reader_per_chunk` is a check: the wake-ups of a reader that
//!   takes everything each time it is woken.
//! * `perf_stored_read` is a measurement, run by hand:
//!   `cargo test --release -p wyrm-client --test stored_read -- --ignored --nocapture`

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::print_stdout,
    reason = "test code: a failed step fails the test"
)]

use futures_core::Stream;
use std::pin::Pin;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::task::{Context, Poll, Wake, Waker};
use std::time::Instant;
use wyrm_bench::{Allocs, Lat, Perf, Usage};
use wyrm_client::{EventStream, ValEvent};
use wyrm_core::{Quality, Sample, Value};
use zenoh::sample::{Sample as ZSample, SampleBuilder};

#[global_allocator]
static A: wyrm_bench::Counting = wyrm_bench::Counting;

/// The allocator counts the whole process: one test at a time.
static ONE: Mutex<()> = Mutex::new(());

const KEYS: usize = 1000;

fn key(i: usize) -> String {
    format!("wy/perf/downstream/mock/g{}/p{i}/~val", i / 10)
}

fn zsample(key: &str, t: u64) -> ZSample {
    let s = Sample {
        v: Value::Float(t as f64 * 0.5),
        q: Quality::Good,
        t,
    };
    let key = zenoh::key_expr::KeyExpr::try_from(key.to_owned()).unwrap();
    SampleBuilder::put(key, wyrm_core::codec::to_vec(&s).unwrap()).into()
}

/// One sample of every key, all with time `t`.
fn round(keys: &[String], t: u64) -> Vec<ZSample> {
    keys.iter().map(|k| zsample(k, t)).collect()
}

/// A waker that counts its calls.
#[derive(Default)]
struct Wakes(AtomicU64);

impl Wake for Wakes {
    fn wake(self: Arc<Self>) {
        self.0.fetch_add(1, Ordering::Relaxed);
    }
}

/// Read until the stream has nothing more (the reader is parked then); the keys read.
fn take(st: &mut EventStream<ValEvent>, cx: &mut Context<'_>, out: &mut Vec<(String, u64)>) {
    while let Poll::Ready(Some(ev)) = Pin::new(&mut *st).poll_next(cx) {
        if let ValEvent::Sample { key, sample, .. } = ev {
            out.push((key, sample.t));
        }
    }
}

/// One stored read of `n` replies into a parked reader that takes everything each time it
/// is woken: the wake-ups, and what it read.
fn wakes_of_a_read(n: usize) -> (u64, Vec<(String, u64)>) {
    let keys: Vec<String> = (0..n).map(key).collect();
    let (_live, stored, mut st) = wyrm_client::testkit::value_stream_stored();
    let wakes = Arc::new(Wakes::default());
    let waker = Waker::from(wakes.clone());
    let mut cx = Context::from_waker(&waker);
    let mut got = Vec::new();
    take(&mut st, &mut cx, &mut got); // parks the reader
    let mut seen = 0;
    for s in round(&keys, 7) {
        stored.call(s);
        let w = wakes.0.load(Ordering::Relaxed);
        if w != seen {
            seen = w;
            take(&mut st, &mut cx, &mut got);
        }
    }
    drop(stored); // the read is final
    take(&mut st, &mut cx, &mut got);
    (wakes.0.load(Ordering::Relaxed), got)
}

#[test]
#[ignore = "a measurement, run by hand"]
fn perf_stored_read() {
    let _one = ONE.lock().unwrap_or_else(|e| e.into_inner());
    let keys: Vec<String> = (0..KEYS).map(key).collect();

    // (1) the wake-ups of one read
    let (wakes, got) = wakes_of_a_read(KEYS);
    assert_eq!(got.len(), KEYS);
    println!(
        "{}",
        Perf::new("client/stored_read/wakes")
            .n(KEYS as u64)
            .field("wakes", wakes)
            .note("one stored read of 1000 replies into a parked reader that takes all it finds: its wake-ups")
    );

    // (2) one thread: the handler for every reply, then the read; no wake-up
    const ROUNDS: usize = 300;
    let rounds: Vec<Vec<ZSample>> = (0..ROUNDS).map(|_| round(&keys, 7)).collect();
    let total = (ROUNDS * KEYS) as u64;
    let mut cx = Context::from_waker(Waker::noop());
    let mut got = Vec::with_capacity(KEYS);
    let (a0, t0) = (Allocs::read(), Instant::now());
    for r in rounds {
        let (_live, stored, mut st) = wyrm_client::testkit::value_stream_stored();
        for s in r {
            stored.call(s);
        }
        drop(stored);
        got.clear();
        take(&mut st, &mut cx, &mut got);
        assert_eq!(got.len(), KEYS);
    }
    let (wall, a) = (t0.elapsed().as_secs_f64(), Allocs::read().since(a0));
    println!(
        "{}",
        Perf::new("client/stored_read/one_thread")
            .n(total)
            .per_s(total as f64 / wall)
            .allocs(a, total)
            .num("ns_per_reply", wall * 1e9 / total as f64)
            .note("a new stream, its stored read of 1000 replies, all read, on one thread (the event's key included)")
    );

    // (3) the replies come on one thread, a task of a multi-thread runtime reads them
    let rt = tokio::runtime::Builder::new_multi_thread()
        .worker_threads(2)
        .enable_all()
        .build()
        .unwrap();
    let rounds: Vec<Vec<ZSample>> = (0..ROUNDS).map(|_| round(&keys, 7)).collect();
    let mut lat = Lat::with_capacity(ROUNDS);
    let u0 = Usage::read();
    for r in rounds {
        let (_live, stored, mut st) = wyrm_client::testkit::value_stream_stored();
        let reader = rt.spawn(async move {
            let mut n = 0;
            while n < KEYS {
                match st.next().await {
                    Some(_) => n += 1,
                    None => break,
                }
            }
            n
        });
        let t0 = Instant::now();
        for s in r {
            stored.call(s);
        }
        drop(stored);
        assert_eq!(rt.block_on(reader).unwrap(), KEYS);
        lat.push(t0.elapsed());
    }
    let u1 = Usage::read();
    let wall = u1.wall_since(&u0).as_secs_f64();
    println!(
        "{}",
        Perf::new("client/stored_read/task")
            .lat(&mut lat)
            .per_s(total as f64 / wall)
            .cpu_pct(u1.cpu_pct_since(&u0))
            .num(
                "cpu_us_per_read",
                u1.cpu_pct_since(&u0) / 100.0 * wall * 1e6 / ROUNDS as f64
            )
            .note("300 stored reads of 1000 replies, one after another: first reply to the last event read by a tokio task; CPU of the process (feeder + reader)")
    );
}
