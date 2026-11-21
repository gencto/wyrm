//! What one sample costs on a pattern (fan-in) value stream, with no session: the handler
//! the client gives Zenoh is called by hand (`wyrm_client::testkit::value_stream`) and the
//! stream is read as a consumer reads it (docs/backlog.md §14).
//!
//! * `one_allocation_per_sample` is a check: a sample of a key the stream already knows
//!   costs one allocation, the key `String` its event hands to the consumer.
//! * `perf_fan_in_stream` is a measurement, run by hand:
//!   `cargo test --release -p wyrm-client --test fan_in -- --ignored --nocapture`

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::print_stdout,
    reason = "test code: a failed step fails the test"
)]

use futures_core::Stream;
use std::pin::Pin;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::task::{Context, Poll, Waker};
use std::time::{Duration, Instant};
use wyrm_bench::{Allocs, Lat, Perf, Usage};
use wyrm_client::{EventStream, ValEvent};
use wyrm_core::{Quality, Sample, Value};
use zenoh::handlers::Callback;
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

/// Read what the stream holds now.
fn drain(st: &mut EventStream<ValEvent>, mut each: impl FnMut(ValEvent)) -> usize {
    let mut cx = Context::from_waker(Waker::noop());
    let mut n = 0;
    while let Poll::Ready(Some(ev)) = Pin::new(&mut *st).poll_next(&mut cx) {
        each(ev);
        n += 1;
    }
    n
}

#[test]
fn one_allocation_per_sample() {
    let _one = ONE.lock().unwrap_or_else(|e| e.into_inner());
    let keys: Vec<String> = (0..KEYS).map(key).collect();
    let (cb, mut st) = wyrm_client::testkit::value_stream();
    // the first round makes the stream's own state (its queue, the keys it knows)
    for s in round(&keys, 1) {
        cb.call(s);
    }
    assert_eq!(drain(&mut st, drop), KEYS);
    let rounds: Vec<Vec<ZSample>> = (2..12).map(|t| round(&keys, t)).collect();
    let total = (rounds.len() * KEYS) as u64;
    let a0 = Allocs::read();
    let mut got = 0;
    for r in rounds {
        for s in r {
            cb.call(s);
        }
        got += drain(&mut st, drop);
    }
    let a = Allocs::read().since(a0);
    assert_eq!(got as u64, total);
    assert_eq!(st.dropped(), 0);
    // the key of each event, and nothing else (a few calls of slack for the test harness)
    assert!(
        a.calls <= total + 16,
        "{} allocations for {total} samples ({:.2} per sample)",
        a.calls,
        a.calls_per(total)
    );
}

/// A producer thread that calls `cb` with 1000 fresh samples every 20 ms (50 000/s) for
/// `secs`; the sample's `t` is the moment it was made.
fn produce(cb: Callback<ZSample>, secs: u64) -> std::thread::JoinHandle<u64> {
    std::thread::spawn(move || {
        let keys: Vec<String> = (0..KEYS).map(key).collect();
        let tick = Duration::from_millis(20);
        let start = Instant::now();
        let (mut sent, mut i) = (0u64, 0u32);
        while start.elapsed() < Duration::from_secs(secs) {
            for k in &keys {
                cb.call(zsample(k, wyrm_core::clock::now_us()));
                sent += 1;
            }
            i += 1;
            if let Some(d) = (tick * i).checked_sub(start.elapsed()) {
                std::thread::sleep(d);
            }
        }
        sent
    })
}

#[test]
#[ignore = "a measurement, run by hand"]
fn perf_fan_in_stream() {
    let _one = ONE.lock().unwrap_or_else(|e| e.into_inner());
    let keys: Vec<String> = (0..KEYS).map(key).collect();

    // (1) one thread: handler + read, no wake-up
    let (cb, mut st) = wyrm_client::testkit::value_stream();
    for s in round(&keys, 1) {
        cb.call(s);
    }
    drain(&mut st, drop);
    let rounds: Vec<Vec<ZSample>> = (2..502).map(|t| round(&keys, t)).collect();
    let total = (rounds.len() * KEYS) as u64;
    let (a0, t0) = (Allocs::read(), Instant::now());
    let mut got = 0;
    for r in rounds {
        for s in r {
            cb.call(s);
        }
        got += drain(&mut st, drop);
    }
    let (wall, a) = (t0.elapsed().as_secs_f64(), Allocs::read().since(a0));
    assert_eq!(got as u64, total);
    println!(
        "{}",
        Perf::new("client/fan_in/one_thread")
            .n(total)
            .per_s(total as f64 / wall)
            .allocs(a, total)
            .num("ns_per_sample", wall * 1e9 / total as f64)
            .field("dropped", st.dropped())
            .note("handler + read on one thread, 1000 keys: what one core takes")
    );
    drop((cb, st));

    // (2) the producer alone: what the test itself costs at 50 000/s
    let secs = 10;
    let n = Arc::new(AtomicU64::new(0));
    let n2 = n.clone();
    let raw = Callback::from(move |s: ZSample| {
        if wyrm_core::codec::from_slice::<Sample>(&s.payload().to_bytes()).is_ok() {
            n2.fetch_add(1, Ordering::Relaxed);
        }
    });
    let u0 = Usage::read();
    let sent = produce(raw, secs).join().unwrap();
    let u1 = Usage::read();
    let raw_cpu = u1.cpu_pct_since(&u0);
    println!(
        "{}",
        Perf::new("client/fan_in/producer_only")
            .n(sent)
            .per_s(sent as f64 / u1.wall_since(&u0).as_secs_f64())
            .cpu_pct(raw_cpu)
            .note("the producer thread with a callback that only decodes the payload")
    );

    // (3) the stream at 50 000/s, read by a task of a multi-thread runtime
    let rt = tokio::runtime::Builder::new_multi_thread()
        .worker_threads(2)
        .enable_all()
        .build()
        .unwrap();
    let (cb, mut st) = wyrm_client::testkit::value_stream();
    let lat = Arc::new(Mutex::new(Lat::with_capacity(600_000)));
    let (got, dropped) = (Arc::new(AtomicU64::new(0)), Arc::new(AtomicU64::new(0)));
    let done = Arc::new(AtomicBool::new(false));
    let (l2, g2, d2, done2) = (lat.clone(), got.clone(), dropped.clone(), done.clone());
    let reader = rt.spawn(async move {
        let mut local = Lat::with_capacity(600_000);
        while let Some(ev) = st.next().await {
            if let ValEvent::Sample { sample, .. } = ev {
                let now = wyrm_core::clock::now_us();
                local.push_us(now.saturating_sub(sample.t) as f64);
                g2.fetch_add(1, Ordering::Relaxed);
            }
        }
        d2.store(st.dropped(), Ordering::Relaxed);
        *l2.lock().unwrap() = local;
        done2.store(true, Ordering::Relaxed);
    });
    let (a0, u0) = (Allocs::read(), Usage::read());
    // the callback goes with the producer thread: the stream ends when it is done
    let sent = produce(cb, secs).join().unwrap();
    let u1 = Usage::read();
    rt.block_on(reader).unwrap();
    assert!(done.load(Ordering::Relaxed));
    let a = Allocs::read().since(a0);
    let cpu = u1.cpu_pct_since(&u0);
    let mut l = std::mem::take(&mut *lat.lock().unwrap());
    println!(
        "{}",
        Perf::new("client/fan_in/stream_50k")
            .lat(&mut l)
            .per_s(got.load(Ordering::Relaxed) as f64 / u1.wall_since(&u0).as_secs_f64())
            .cpu_pct(cpu)
            .allocs(a, sent)
            .field("sent", sent)
            .field("dropped", dropped.load(Ordering::Relaxed))
            .num("stream_cpu_pct", cpu - raw_cpu)
            .note("1000 samples every 20 ms into the handler, read by a tokio task; stream_cpu_pct = minus the producer alone; allocations include the producer's 3 per sample")
    );
}
