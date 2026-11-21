//! What one value frame costs the gateway itself, with no socket and no session: the
//! client's value stream is fed by hand (`wyrm_client::testkit::value_stream`; with the
//! gateway's own read filter in its callback, `ws::testkit::serve_values`) and the frames
//! end in a counting sink (`wyrm_gateway::ws::testkit`; docs/backlog.md §14).
//!
//! * `perf_frame_path` is a measurement, run by hand:
//!   `cargo test --release -p wyrm-gateway --test frame_path -- --ignored --nocapture`
//!   - `gateway/frame/encode`: a value event → the bytes of its frame;
//!   - `gateway/frame/rights`: the rights check of one sample (the path runs it once, in
//!     the stream's filter; the pump runs it again only after the grants changed);
//!   - `gateway/frame/stream_only`: the client's stream read by a task that drops the
//!     events (what is not the gateway's);
//!   - `gateway/frame/one_thread`: rights → stream → frame → queue → writer → sink on one
//!     thread, and how many flushes of the transport the frames took;
//!   - `gateway/frame/10x1000x10hz`: ten connections of 1000 points at 10 Hz (100 000
//!     frames/s) on a runtime of two workers, with the producer's own cost beside it.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::print_stdout,
    reason = "test code: a failed step fails the test"
)]

use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use wyrm_bench::{Allocs, Perf, Usage};
use wyrm_client::ValEvent;
use wyrm_core::{Quality, Sample, Value};
use wyrm_gateway::ws::testkit::{self, Wire};
use wyrm_gateway::{Gateway, GatewayConfig, Grants};
use zenoh::handlers::Callback;
use zenoh::sample::{Sample as ZSample, SampleBuilder};

#[global_allocator]
static A: wyrm_bench::Counting = wyrm_bench::Counting;

/// The allocator counts the whole process: one test at a time.
static ONE: Mutex<()> = Mutex::new(());

const SITE: &str = "perf";
const KEYS: usize = 1000;

fn key(i: usize) -> String {
    format!("wy/{SITE}/downstream/mock/g{}/p{i}", i / 10)
}

fn sample(t: u64) -> Sample {
    Sample {
        v: Value::Float(t as f64 * 0.5),
        q: Quality::Good,
        t,
    }
}

fn zsample(key: &str, t: u64) -> ZSample {
    let key = zenoh::key_expr::KeyExpr::try_from(format!("{key}/~val")).unwrap();
    SampleBuilder::put(key, wyrm_core::codec::to_vec(&sample(t)).unwrap()).into()
}

/// One sample of every key, all with time `t`.
fn round(keys: &[String], t: u64) -> Vec<ZSample> {
    keys.iter().map(|k| zsample(k, t)).collect()
}

/// A gateway of its own (no server, no session) and the grants of a `viewer`.
fn gateway(name: &str) -> (Arc<Gateway>, Grants, std::path::PathBuf) {
    let dir =
        std::env::temp_dir().join(format!("wyrm-gateway-frames-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    let cfg = GatewayConfig::new(SITE, &dir, "127.0.0.1:0".parse().unwrap());
    let gw = Gateway::open(cfg, b"test state key").unwrap();
    let grants = gw.grants_of(&["viewer".to_owned()]);
    (gw, grants, dir)
}

/// Wait (on the runtime's own thread) until `wire` has `n` frames.
async fn frames(wire: &Wire, n: u64) {
    let deadline = Instant::now() + Duration::from_secs(60);
    while wire.frames() < n {
        assert!(Instant::now() < deadline, "{} of {n} frames", wire.frames());
        tokio::task::yield_now().await;
    }
}

/// A producer thread that calls every callback with 1000 fresh samples every 100 ms for
/// `secs` (10 Hz); the sample's `t` is the moment it was made.
fn produce(cbs: Vec<Callback<ZSample>>, secs: u64) -> std::thread::JoinHandle<u64> {
    std::thread::spawn(move || {
        let keys: Vec<String> = (0..KEYS).map(key).collect();
        let tick = Duration::from_millis(100);
        let start = Instant::now();
        let (mut sent, mut i) = (0u64, 0u32);
        while start.elapsed() < Duration::from_secs(secs) {
            for cb in &cbs {
                for k in &keys {
                    cb.call(zsample(k, wyrm_core::clock::now_us()));
                    sent += 1;
                }
            }
            i += 1;
            if let Some(d) = (tick * i).checked_sub(start.elapsed()) {
                std::thread::sleep(d);
            }
        }
        sent
    })
}

/// The node keys of the frames on `wire`, in order.
fn frame_keys(wire: &Wire) -> Vec<String> {
    wire.take()
        .iter()
        .map(|b| {
            let Value::Map(m) = wyrm_core::codec::from_slice::<Value>(b).unwrap() else {
                panic!("a map")
            };
            let Some(Value::Map(ev)) = m.get("event") else {
                panic!("an event")
            };
            let Some(Value::Str(k)) = ev.get("key") else {
                panic!("a key")
            };
            k.clone()
        })
        .collect()
}

/// Values the filter let through wait in the stream's buffer while the user's grants
/// change (or the downstream sites do): what may no longer be read never goes out. With
/// no change, everything the filter let through goes out; what it refused never does.
#[test]
fn values_that_waited_across_a_change_of_rights_are_checked_again() {
    use wyrm_core::ptok::Grant;
    use wyrm_core::Perm;
    let _one = ONE.lock().unwrap_or_else(|e| e.into_inner());
    let (gw, _, dir) = gateway("recheck");
    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    let all = || {
        Grants::new(vec![Grant {
            k: format!("wy/{SITE}/**"),
            p: Perm::Read,
        }])
    };
    let mine = |k: &str| format!("wy/{SITE}/downstream/mock/{k}");
    let edge = "wy/edge/downstream/mock/e0".to_owned();
    gw.set_downstream_sites(vec!["edge".into()]);
    // `run` the stream after `feed`, with `change` between them
    let serve = |change: &dyn Fn(&testkit::Served)| {
        let wire = Wire::keeping();
        let sv = testkit::serve_values(gw.clone(), all(), 3, wire.clone());
        for k in [mine("a"), mine("b"), edge.clone(), "wy/other/x".to_owned()] {
            sv.feed.call(zsample(&k, 5));
        }
        change(&sv);
        drop(sv.feed);
        assert!(rt.block_on(sv.run));
        frame_keys(&wire)
    };
    // no change: the other site's key was refused by the filter, the rest goes out
    assert_eq!(serve(&|_| {}), [mine("a"), mine("b"), edge.clone()]);
    // `b` is taken away while its value waits
    let b_gone = |sv: &testkit::Served| {
        sv.grants.send_replace(Arc::new(Grants::new(vec![
            Grant {
                k: format!("wy/{SITE}/downstream/mock/b/**"),
                p: Perm::None,
            },
            Grant {
                k: format!("wy/{SITE}/**"),
                p: Perm::Read,
            },
        ])));
    };
    assert_eq!(serve(&b_gone), [mine("a"), edge.clone()]);
    // everything is taken away
    let none = |sv: &testkit::Served| {
        sv.grants.send_replace(Arc::new(Grants::new(vec![])));
    };
    assert!(serve(&none).is_empty());
    // the site `edge` is no longer a downstream one: its key is no longer this site's
    let edge_gone = |_: &testkit::Served| gw.set_downstream_sites(vec![]);
    assert_eq!(serve(&edge_gone), [mine("a"), mine("b")]);
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
#[ignore = "a measurement, run by hand"]
fn perf_frame_path() {
    let _one = ONE.lock().unwrap_or_else(|e| e.into_inner());
    let keys: Vec<String> = (0..KEYS).map(key).collect();
    let (gw, grants, dir) = gateway("perf");
    const ROUNDS: u64 = 300;
    let total = ROUNDS * KEYS as u64;

    // (1) a value event → the bytes of its frame
    let events: Vec<ValEvent> = (0..ROUNDS)
        .flat_map(|t| {
            keys.iter().map(move |k| ValEvent::Sample {
                key: k.clone(),
                sample: sample(t + 1),
                qual: None,
            })
        })
        .collect();
    let (a0, t0) = (Allocs::read(), Instant::now());
    let mut bytes = 0u64;
    for ev in events {
        bytes += testkit::value_frame(7, ev).len() as u64;
    }
    let (wall, a) = (t0.elapsed().as_secs_f64(), Allocs::read().since(a0));
    println!(
        "{}",
        Perf::new("gateway/frame/encode")
            .n(total)
            .per_s(total as f64 / wall)
            .allocs(a, total)
            .num("ns_per_frame", wall * 1e9 / total as f64)
            .num("frame_bytes", bytes as f64 / total as f64)
            .note("a value event to the bytes of its frame (the event's key is freed in it)")
    );

    // (2) the rights check of one sample
    let (a0, t0) = (Allocs::read(), Instant::now());
    let (mut ok, mut own) = (0u64, String::new());
    for _ in 0..ROUNDS {
        for k in &keys {
            ok += u64::from(testkit::may_read(&gw, &grants, k, &mut own));
        }
    }
    let (wall, a) = (t0.elapsed().as_secs_f64(), Allocs::read().since(a0));
    assert_eq!(ok, total);
    println!(
        "{}",
        Perf::new("gateway/frame/rights")
            .n(total)
            .per_s(total as f64 / wall)
            .allocs(a, total)
            .num("ns_per_check", wall * 1e9 / total as f64)
            .note("one rights check of a sample, with the buffer the path keeps for it")
    );

    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();

    // (3) the client's stream alone, read by a task that drops the events
    {
        let (cb, mut st) = wyrm_client::testkit::value_stream();
        let n = Arc::new(AtomicU64::new(0));
        let n2 = n.clone();
        let reader = rt.spawn(async move {
            while let Some(ev) = st.next().await {
                drop(ev);
                n2.fetch_add(1, Ordering::Relaxed);
            }
        });
        let rounds: Vec<Vec<ZSample>> = (0..=ROUNDS).map(|t| round(&keys, t + 1)).collect();
        let (wall, a) = rt.block_on(async {
            let mut rounds = rounds.into_iter();
            let mut want = 0u64;
            let feed = |r: Vec<ZSample>| {
                for s in r {
                    cb.call(s);
                }
            };
            // the first round makes the stream's own state
            feed(rounds.next().unwrap());
            want += KEYS as u64;
            while n.load(Ordering::Relaxed) < want {
                tokio::task::yield_now().await;
            }
            let (a0, t0) = (Allocs::read(), Instant::now());
            for r in rounds {
                feed(r);
                want += KEYS as u64;
                while n.load(Ordering::Relaxed) < want {
                    tokio::task::yield_now().await;
                }
            }
            (t0.elapsed().as_secs_f64(), Allocs::read().since(a0))
        });
        drop(cb);
        rt.block_on(reader).unwrap();
        println!(
            "{}",
            Perf::new("gateway/frame/stream_only")
                .n(total)
                .per_s(total as f64 / wall)
                .allocs(a, total)
                .num("ns_per_frame", wall * 1e9 / total as f64)
                .note("the client's value stream read by a task that drops the events")
        );
    }

    // (4) the whole value path of one subscribe on one thread
    {
        let wire = Wire::new();
        let sv = testkit::serve_values(gw.clone(), grants.clone(), 7, wire.clone());
        let (cb, _grants) = (sv.feed, sv.grants);
        let served = rt.spawn(sv.run);
        let rounds: Vec<Vec<ZSample>> = (0..=ROUNDS).map(|t| round(&keys, t + 1)).collect();
        let (wall, a, flushes, bytes) = rt.block_on(async {
            let mut rounds = rounds.into_iter();
            let mut want = KEYS as u64;
            for s in rounds.next().unwrap() {
                cb.call(s);
            }
            frames(&wire, want).await;
            let (f0, b0) = (wire.flushes(), wire.bytes());
            let (a0, t0) = (Allocs::read(), Instant::now());
            for r in rounds {
                for s in r {
                    cb.call(s);
                }
                want += KEYS as u64;
                frames(&wire, want).await;
            }
            (
                t0.elapsed().as_secs_f64(),
                Allocs::read().since(a0),
                wire.flushes() - f0,
                wire.bytes() - b0,
            )
        });
        drop(cb);
        assert!(rt.block_on(served).unwrap());
        println!(
            "{}",
            Perf::new("gateway/frame/one_thread")
                .n(total)
                .per_s(total as f64 / wall)
                .allocs(a, total)
                .num("ns_per_frame", wall * 1e9 / total as f64)
                .num("flushes_per_frame", flushes as f64 / total as f64)
                .num("frame_bytes", bytes as f64 / total as f64)
                .note("stream, rights, frame, queue, writer and sink on one thread, 1000 keys")
        );
    }
    drop(rt);

    // (5) the producer alone: what the test itself costs at 100 000 samples/s
    let (secs, conns) = (10, 10);
    let n = Arc::new(AtomicU64::new(0));
    let raw: Vec<Callback<ZSample>> = (0..conns)
        .map(|_| {
            let n2 = n.clone();
            Callback::from(move |s: ZSample| {
                if wyrm_core::codec::from_slice::<Sample>(&s.payload().to_bytes()).is_ok() {
                    n2.fetch_add(1, Ordering::Relaxed);
                }
            })
        })
        .collect();
    let u0 = Usage::read();
    let sent = produce(raw, secs).join().unwrap();
    let u1 = Usage::read();
    let raw_cpu = u1.cpu_pct_since(&u0);
    println!(
        "{}",
        Perf::new("gateway/frame/producer_only")
            .n(sent)
            .per_s(sent as f64 / u1.wall_since(&u0).as_secs_f64())
            .cpu_pct(raw_cpu)
            .note("the producer thread with callbacks that only decode the payload")
    );

    // (6) ten connections of 1000 points at 10 Hz on two workers
    let rt = tokio::runtime::Builder::new_multi_thread()
        .worker_threads(2)
        .enable_all()
        .build()
        .unwrap();
    let wire = Wire::new();
    let mut cbs = Vec::new();
    let mut served = Vec::new();
    let mut keep = Vec::new();
    for id in 0..conns {
        let sv = testkit::serve_values(gw.clone(), grants.clone(), id, wire.clone());
        cbs.push(sv.feed);
        keep.push(sv.grants);
        served.push(rt.spawn(sv.run));
    }
    let (a0, u0) = (Allocs::read(), Usage::read());
    // the callbacks go with the producer thread: the streams end when it is done
    let sent = produce(cbs, secs).join().unwrap();
    let u1 = Usage::read();
    for s in served {
        assert!(rt.block_on(s).unwrap());
    }
    let a = Allocs::read().since(a0);
    let cpu = u1.cpu_pct_since(&u0);
    println!(
        "{}",
        Perf::new(&format!("gateway/frame/{conns}x{KEYS}x10hz"))
            .n(wire.frames())
            .per_s(wire.frames() as f64 / u1.wall_since(&u0).as_secs_f64())
            .cpu_pct(cpu)
            .rss(u1.rss_bytes)
            .allocs(a, sent)
            .num("cpu_less_producer", cpu - raw_cpu)
            .num(
                "flushes_per_frame",
                wire.flushes() as f64 / wire.frames().max(1) as f64
            )
            .field("sent", sent)
            .note(
                "ten subscribes, one connection each; allocations include the producer's samples"
            )
    );
    drop(rt);
    let _ = std::fs::remove_dir_all(&dir);
}
