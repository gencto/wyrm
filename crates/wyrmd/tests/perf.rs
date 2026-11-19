//! What the broker carries (performance audit items 1, 2, 12, 13 and the gateway): an
//! in-process `wyrmd` with the embedded `mock` link at a set rate, a client session over
//! loopback TCP that counts the samples. Not checks: run them by hand, one at a time.
//!
//! `cargo test --release -p wyrmd --test perf -- --ignored --nocapture --test-threads=1`
//!
//! * `perf_a_base`: 1000 points at 10, 20 and 50 Hz (10k, 20k, 50k samples/s), 10 s each.
//! * `perf_b_wildcard`: 1000 points at 20 Hz while a second client opens
//!   `WyrmClient::subscribe("wy/<site>/downstream/**")` again and again (its storage `get`,
//!   item 2); then one `subscribe("wy/**")`, timed to its first event.
//! * `perf_c_trace`: as the base at 20 Hz with the mock link's log level at `trace` (item 12).
//! * `perf_d_historian`: 10 000 points at 2 Hz, the historian recording all of them (All
//!   Data, flush 1 s, item 13). The watches go to the historian directly
//!   (`Control::historian`, feature `testkit`); the cost of the action that adds one watch
//!   is measured beside it for the first 300, and the time the group takes to start. Today
//!   the start stalls the broker (docs/backlog.md §14); a watchdog thread then aborts the
//!   test after 360 s with `started=false`.
//! * `perf_e_audit`: 1000 `invoke`s of the mock's `reset`, one after another, from 50
//!   subjects in turn (the link's own rate limit is per subject): latency, and audit records
//!   per second (`Control::audit_lsn`, feature `testkit`, item 1).
//! * `perf_f_gateway`: 1000 points at 10 Hz, 10 gateway WebSocket clients each subscribed to
//!   the mock's whole tree: frames per second and frame latency.
//!
//! "lost" is expected (points × Hz × seconds) minus received: the mock's ticker skips a
//! missed tick (`MissedTickBehavior::Skip`) without a trace, so a skipped tick shows only as
//! a shortfall. CPU is this process (broker, links and the counting client) in % of one core.
//! No OS counts `fsync` calls: the audit's are derived from `wyrm-state` (`apply` =
//! `sync_data` of the WAL + `sync_all` of the anchor + `sync_all` of the directory, 3 per
//! record); on Linux `/proc/self/io` adds write calls and bytes.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::unreachable,
    clippy::print_stdout,
    reason = "test code: a failed step fails the test"
)]

use std::collections::BTreeMap;
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use tokio::sync::oneshot;
use wyrm_admin::Control;
use wyrm_bench::{Lat, Perf, Usage};
use wyrm_client::{SigningTokens, WyrmClient};
use wyrm_core::{Sample, Value};
use wyrm_link_mock::{point_paths, MockConfig};
use wyrmd::{Config, Daemon};

const SEED: [u8; 32] = [9; 32];
const SITE: &str = "perf";

/// A loopback port nobody listens on now (the e2e tests keep a stricter scheme; these
/// tests run one at a time).
fn free_port() -> u16 {
    let l = std::net::TcpListener::bind(("127.0.0.1", 0)).unwrap();
    l.local_addr().unwrap().port()
}

fn temp_dir(name: &str) -> PathBuf {
    let d = std::env::temp_dir().join(format!("wyrmd-perf-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&d);
    d
}

struct Env {
    port: u16,
    ctl: Arc<Control>,
    gateway: Option<Arc<wyrm_gateway::Gateway>>,
    stop: Option<oneshot::Sender<()>>,
    task: tokio::task::JoinHandle<Result<(), wyrmd::Error>>,
}

impl Env {
    async fn start(name: &str, extra: &str) -> Self {
        let _ = wyrm_admin::logs::install_quiet();
        let port = free_port();
        let key = ed25519_dalek::SigningKey::from_bytes(&SEED);
        let text = format!(
            r#"{{
                site: "{SITE}",
                data_dir: "{}",
                listen: ["tcp/127.0.0.1:{port}"],
                admin_keys: ["{}"],
                metrics_interval_ms: 1000,
                {extra}
            }}"#,
            temp_dir(name).display(),
            hex::encode(key.verifying_key().to_bytes())
        );
        let daemon = Daemon::open(
            Config::from_json5(&text).unwrap(),
            env!("CARGO_BIN_EXE_wyrmd").into(),
        )
        .unwrap();
        let ctl = daemon.control();
        let gateway = daemon.gateway();
        let (stop, rx) = oneshot::channel();
        let task = tokio::spawn(daemon.run_until(async {
            let _ = rx.await;
        }));
        let deadline = Instant::now() + Duration::from_secs(30);
        while std::net::TcpStream::connect(("127.0.0.1", port)).is_err() {
            assert!(!task.is_finished(), "wyrmd ended before it listened");
            assert!(Instant::now() < deadline, "wyrmd not up in 30 s");
            tokio::time::sleep(Duration::from_millis(30)).await;
        }
        Self {
            port,
            ctl,
            gateway,
            stop: Some(stop),
            task,
        }
    }

    async fn session(&self) -> zenoh::Session {
        let mut zc = zenoh::Config::default();
        zc.insert_json5("mode", r#""client""#).unwrap();
        zc.insert_json5(
            "connect/endpoints",
            &format!(r#"["tcp/127.0.0.1:{}"]"#, self.port),
        )
        .unwrap();
        zc.insert_json5("scouting/multicast/enabled", "false")
            .unwrap();
        zenoh::open(zc).await.unwrap()
    }

    async fn client(&self, sub: &str) -> WyrmClient {
        let key = ed25519_dalek::SigningKey::from_bytes(&SEED);
        WyrmClient::new(self.session().await)
            .with_tokens(Arc::new(SigningTokens::new(key, SITE).subject(sub)))
            .with_timeout(Duration::from_secs(10))
    }

    async fn stop(mut self) {
        let _ = self.stop.take().unwrap().send(());
        self.task.await.unwrap().unwrap();
    }
}

fn mock(points: usize, hz: f64) -> (String, MockConfig) {
    let cfg = MockConfig {
        points,
        rate_hz: hz,
        depth: 1,
        fanout: 10,
        writable: false,
    };
    let text = format!(
        r#"links: {{ mock: {{ driver: "mock", params: {{ points: {points}, rate_hz: {hz}, depth: 1, fanout: 10 }} }} }},"#
    );
    (text, cfg)
}

/// Samples of the mock seen by one raw subscriber: count and `now − t`.
struct Counter {
    n: Arc<AtomicU64>,
    lat: Arc<Mutex<Lat>>,
    _sub: zenoh::pubsub::Subscriber<()>,
}

impl Counter {
    async fn on(session: &zenoh::Session) -> Self {
        let n = Arc::new(AtomicU64::new(0));
        let lat = Arc::new(Mutex::new(Lat::new()));
        let (n2, l2) = (n.clone(), lat.clone());
        let sub = session
            .declare_subscriber(format!("wy/{SITE}/downstream/mock/**/~val"))
            .callback(move |s| {
                let now = wyrm_core::clock::now_us();
                if let Ok(x) = wyrm_core::codec::from_slice::<Sample>(&s.payload().to_bytes()) {
                    l2.lock().unwrap().push_us(now.saturating_sub(x.t) as f64);
                }
                n2.fetch_add(1, Ordering::Relaxed);
            })
            .await
            .unwrap();
        Self { n, lat, _sub: sub }
    }

    fn count(&self) -> u64 {
        self.n.load(Ordering::Relaxed)
    }

    /// Wait until the mock has published every point once.
    async fn ready(&self, points: usize) {
        let deadline = Instant::now() + Duration::from_secs(180);
        while self.count() < points as u64 {
            assert!(Instant::now() < deadline, "mock not publishing");
            tokio::time::sleep(Duration::from_millis(100)).await;
        }
        tokio::time::sleep(Duration::from_secs(1)).await;
    }

    fn reset(&self) -> u64 {
        *self.lat.lock().unwrap() = Lat::new();
        self.count()
    }

    fn take_lat(&self) -> Lat {
        std::mem::take(&mut *self.lat.lock().unwrap())
    }
}

/// `secs` of samples: the figure line for them.
async fn window(name: &str, c: &Counter, points: usize, hz: f64, secs: f64, note: &str) -> Perf {
    let base = c.reset();
    let u0 = Usage::read();
    tokio::time::sleep(Duration::from_secs_f64(secs)).await;
    let u1 = Usage::read();
    let got = c.count() - base;
    let wall = u1.wall_since(&u0).as_secs_f64();
    let expected = (points as f64 * hz * wall).round() as u64;
    let mut lat = c.take_lat();
    let mut p = Perf::new(name)
        .lat(&mut lat)
        .per_s(got as f64 / wall)
        .cpu_pct(u1.cpu_pct_since(&u0))
        .rss(u1.rss_bytes)
        .field("expected", expected)
        .field("lost", expected.saturating_sub(got))
        .note(note);
    if let Some(io) = u1.io_since(&u0) {
        p = p
            .field("syscw", io.syscw)
            .field("write_bytes", io.write_bytes);
    }
    p
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
#[ignore = "a measurement, run by hand"]
async fn perf_a_base() {
    let points = 1000;
    for hz in [10.0, 20.0, 50.0] {
        let (links, _) = mock(points, hz);
        let env = Env::start(&format!("a{hz}"), &links).await;
        let s = env.session().await;
        let c = Counter::on(&s).await;
        c.ready(points).await;
        let p = window(
            &format!("broker/base/{points}x{hz}hz"),
            &c,
            points,
            hz,
            10.0,
            "mock to a TCP client, samples counted",
        )
        .await;
        println!("{p}");
        drop(c);
        drop(s);
        env.stop().await;
    }
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
#[ignore = "a measurement, run by hand"]
async fn perf_b_wildcard() {
    let (points, hz) = (1000, 20.0);
    let (links, _) = mock(points, hz);
    let env = Env::start("b", &links).await;
    let s = env.session().await;
    let c = Counter::on(&s).await;
    c.ready(points).await;
    let w = env.client("svc:perf-wild").await;
    let stop = Arc::new(std::sync::atomic::AtomicBool::new(false));
    let stop2 = stop.clone();
    let snaps = tokio::spawn(async move {
        // each round: subscribe to everything, read until every mock point has come once;
        // the first event and the whole set are timed apart
        let (mut first, mut all) = (Lat::new(), Lat::new());
        let (mut short, mut most) = (0u64, 0usize);
        while !stop2.load(Ordering::Relaxed) {
            let t0 = Instant::now();
            let mut st = w
                .subscribe(&format!("wy/{SITE}/downstream/**"))
                .await
                .unwrap();
            let mut seen = std::collections::HashSet::new();
            let deadline = t0 + Duration::from_secs(15);
            let mut got_first = false;
            while seen.len() < points {
                match tokio::time::timeout_at(deadline.into(), st.next()).await {
                    Ok(Some(ev)) => {
                        if !got_first {
                            first.push(t0.elapsed());
                            got_first = true;
                        }
                        if let wyrm_client::ValEvent::Sample { key, .. } = ev {
                            if key.contains("/downstream/mock/") {
                                seen.insert(key);
                            }
                        }
                    }
                    _ => {
                        short += 1;
                        break;
                    }
                }
            }
            most = most.max(seen.len());
            if seen.len() >= points {
                all.push(t0.elapsed());
            }
        }
        (first, all, short, most)
    });
    let p = window(
        &format!("broker/wildcard/{points}x{hz}hz"),
        &c,
        points,
        hz,
        10.0,
        "base rate while another client subscribes wy/<site>/downstream/** in a loop",
    )
    .await;
    stop.store(true, Ordering::Relaxed);
    let (mut first, mut all, short, most) = snaps.await.unwrap();
    println!("{p}");
    println!(
        "{}",
        Perf::new("broker/wildcard/first_event")
            .lat(&mut first)
            .note("subscribe wy/<site>/downstream/**: time to its first event")
    );
    println!(
        "{}",
        Perf::new("broker/wildcard/snapshot")
            .lat(&mut all)
            .field("short", short)
            .field("most_points", most)
            .note("subscribe wy/<site>/downstream/** until every mock point came once (storage get + live), 15 s at most")
    );
    // the whole key space once: the first event of `wy/**`
    let all = env.client("svc:perf-all").await;
    let t0 = Instant::now();
    let mut st = all.subscribe("wy/**").await.unwrap();
    let got = tokio::time::timeout(Duration::from_secs(15), st.next())
        .await
        .ok()
        .flatten()
        .is_some();
    let mut one = Lat::new();
    if got {
        one.push(t0.elapsed());
    }
    println!(
        "{}",
        Perf::new("broker/wildcard/all_first_event")
            .lat(&mut one)
            .field("got", got)
            .note("subscribe wy/** once: time to its first event, 15 s at most")
    );
    drop(c);
    env.stop().await;
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
#[ignore = "a measurement, run by hand"]
async fn perf_c_trace() {
    let (points, hz) = (1000, 20.0);
    let (links, _) = mock(points, hz);
    let env = Env::start("c", &links).await;
    let s = env.session().await;
    let c = Counter::on(&s).await;
    c.ready(points).await;
    let admin = env.client("svc:perf").await;
    let level = format!("wy/{SITE}/sys/links/mock/log_level");
    // choices: default, error, warn, info, debug, trace (an enum takes its index)
    admin.set(&level, Value::UInt(5)).await.unwrap();
    tokio::time::sleep(Duration::from_secs(1)).await;
    let p = window(
        &format!("broker/trace/{points}x{hz}hz"),
        &c,
        points,
        hz,
        10.0,
        "base rate with the mock link at trace log level",
    )
    .await;
    println!("{p}");
    admin.set(&level, Value::UInt(0)).await.unwrap();
    drop(c);
    env.stop().await;
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
#[ignore = "a measurement, run by hand"]
async fn perf_d_historian() {
    let (points, hz) = (10_000, 2.0);
    let (links, cfg) = mock(points, hz);
    let t_start = Instant::now();
    let env = Env::start("d", &links).await;
    let s = env.session().await;
    let c = Counter::on(&s).await;
    c.ready(points).await;
    println!(
        "{}",
        Perf::new("broker/historian/mock_start")
            .n(points as u64)
            .num("total_ms", t_start.elapsed().as_secs_f64() * 1e3)
            .note("wyrmd open + mock declares 10000 points + first sample of each")
    );
    let paths = point_paths(&cfg);
    // the action that adds one watch: a registry write, the watch's node, every overlay again
    let admin = env.client("svc:perf").await;
    let hist = format!("wy/{SITE}/sys/history");
    let m = |kv: &[(&str, Value)]| {
        Value::Map(
            kv.iter()
                .map(|(k, v)| ((*k).to_owned(), v.clone()))
                .collect::<BTreeMap<_, _>>(),
        )
    };
    admin
        .invoke_one(
            &hist,
            "add_watch_group",
            m(&[
                ("name", Value::from("a")),
                ("logging_type", Value::from("None")),
            ]),
        )
        .await
        .unwrap();
    let (mut first, mut last) = (Lat::new(), Lat::new());
    // the admin link's rate limit is per subject (50/s, burst 100): ten subjects in turn
    let mut adders = Vec::new();
    for k in 0..10 {
        adders.push(env.client(&format!("svc:perf{k}")).await);
    }
    for (i, p) in paths.iter().take(300).enumerate() {
        let t = Instant::now();
        adders[i % 10]
            .invoke_one(
                &format!("{hist}/a"),
                "add_watch_path",
                m(&[("path", Value::from(format!("downstream/mock/{p}")))]),
            )
            .await
            .unwrap();
        if i < 50 {
            first.push(t.elapsed());
        } else if i >= 250 {
            last.push(t.elapsed());
        }
    }
    println!(
        "{}",
        Perf::new("broker/historian/add_watch_first50")
            .lat(&mut first)
            .note("sys/history add_watch_path, watches 1-50")
    );
    println!(
        "{}",
        Perf::new("broker/historian/add_watch_251_300")
            .lat(&mut last)
            .note("sys/history add_watch_path, watches 251-300")
    );
    // 10 000 watches straight into the historian
    let h = env.ctl.historian().clone();
    h.configure(vec![wyrm_history::GroupCfg {
        name: "perf".into(),
        logging: wyrm_history::Logging::AllData,
        interval_ms: 1000,
        flush_ms: 1000,
        watches: paths
            .iter()
            .enumerate()
            .map(|(i, p)| wyrm_history::WatchCfg {
                id: format!("w{i}"),
                key: format!("wy/{SITE}/downstream/mock/{p}"),
                enabled: true,
            })
            .collect(),
    }]);
    // The group start can stall the broker (docs/backlog.md §14: the follows' gets
    // block in a local queryable's full FIFO), and then this test makes no progress: a
    // thread of its own ends the process with a figure that says so.
    let done = Arc::new(std::sync::atomic::AtomicBool::new(false));
    let done2 = done.clone();
    std::thread::spawn(move || {
        std::thread::sleep(Duration::from_secs(360));
        if !done2.load(Ordering::Relaxed) {
            println!(
                "{}",
                Perf::new("broker/historian/group_start")
                    .n(10_000)
                    .field("started", false)
                    .note("no progress in 360 s: the group start stalled (docs/backlog.md 14)")
            );
            std::process::abort();
        }
    });
    // the group starts when every series is in the store and every point is followed
    let t_group = Instant::now();
    let deadline = t_group + Duration::from_secs(300);
    while h.counters().rows_written.load(Ordering::Relaxed) == 0 && Instant::now() < deadline {
        tokio::time::sleep(Duration::from_millis(200)).await;
    }
    let started = h.counters().rows_written.load(Ordering::Relaxed) > 0;
    println!(
        "{}",
        Perf::new("broker/historian/group_start")
            .n(points as u64)
            .num("total_ms", t_group.elapsed().as_secs_f64() * 1e3)
            .field("started", started)
            .note("configure 10000 new watches to the first row written (300 s at most)")
    );
    tokio::time::sleep(Duration::from_secs(2)).await;
    let rows0 = h.counters().rows_written.load(Ordering::Relaxed);
    let dropped0 = h.counters().dropped.load(Ordering::Relaxed);
    let mut p = window(
        &format!("broker/historian/{points}x{hz}hz"),
        &c,
        points,
        hz,
        10.0,
        "historian All Data on every point, flush 1 s",
    )
    .await;
    let rows = h.counters().rows_written.load(Ordering::Relaxed) - rows0;
    let dropped = h.counters().dropped.load(Ordering::Relaxed) - dropped0;
    p = p
        .num("rows_per_s", rows as f64 / 10.0)
        .field("rows_dropped", dropped)
        .num(
            "last_flush_ms",
            h.counters().last_flush_us.load(Ordering::Relaxed) as f64 / 1e3,
        )
        .field("fsync", "not_counted_redb_commit");
    println!("{p}");
    done.store(true, Ordering::Relaxed);
    drop(c);
    env.stop().await;
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
#[ignore = "a measurement, run by hand"]
async fn perf_e_audit() {
    let (links, _) = mock(100, 1.0);
    let env = Env::start("e", &links).await;
    let s = env.session().await;
    let c = Counter::on(&s).await;
    c.ready(100).await;
    let mut clients = Vec::new();
    for i in 0..50 {
        clients.push(env.client(&format!("user:perf{i}")).await);
    }
    let root = format!("wy/{SITE}/downstream/mock");
    // warm up: every client once
    for cl in &clients {
        cl.invoke_one(&root, "reset", Value::Map(Default::default()))
            .await
            .unwrap();
    }
    tokio::time::sleep(Duration::from_secs(2)).await;
    let n = 1000u64;
    let lsn0 = env.ctl.audit_lsn();
    let u0 = Usage::read();
    let mut lat = Lat::with_capacity(1000);
    let mut refused = 0u64;
    for i in 0..n {
        let cl = &clients[(i % 50) as usize];
        let t = Instant::now();
        if cl
            .invoke_one(&root, "reset", Value::Map(Default::default()))
            .await
            .is_err()
        {
            refused += 1;
        }
        lat.push(t.elapsed());
    }
    let u_sent = Usage::read();
    // records land after the answers: the admin writes them from a subscriber
    let deadline = Instant::now() + Duration::from_secs(60);
    while env.ctl.audit_lsn() - lsn0 < n && Instant::now() < deadline {
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
    let u1 = Usage::read();
    let records = env.ctl.audit_lsn() - lsn0;
    let wall = u1.wall_since(&u0).as_secs_f64();
    println!(
        "{}",
        Perf::new("broker/audit/invoke")
            .lat(&mut lat)
            .per_s(n as f64 / u_sent.wall_since(&u0).as_secs_f64())
            .cpu_pct(u_sent.cpu_pct_since(&u0))
            .rss(u_sent.rss_bytes)
            .field("refused", refused)
            .note("invoke mock reset over TCP, 50 subjects in turn, one after another")
    );
    let mut p = Perf::new("broker/audit/records")
        .n(records)
        .per_s(records as f64 / wall)
        .cpu_pct(u1.cpu_pct_since(&u0))
        .num("fsync_per_s_derived", 3.0 * records as f64 / wall)
        .note("audit records written per second (first invoke to the last record)");
    if let Some(io) = u1.io_since(&u0) {
        p = p
            .field("syscw", io.syscw)
            .field("write_bytes", io.write_bytes);
    }
    println!("{p}");
    drop(c);
    env.stop().await;
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
#[ignore = "a measurement, run by hand"]
async fn perf_f_gateway() {
    let (points, hz, clients) = (1000, 10.0, 10);
    let (links, _) = mock(points, hz);
    let gw_port = free_port();
    let env = Env::start(
        "f",
        &format!(r#"{links} gateway: {{ listen: "127.0.0.1:{gw_port}", admin_user: "nobody" }},"#),
    )
    .await;
    let gw = env.gateway.clone().expect("gateway");
    // a user has 8 sockets at most (SOCKETS_PER_USER): one user per client, with a password
    // made for this run
    let password = wyrm_core::hex::encode(wyrm_core::rand::bytes::<16>().unwrap());
    for k in 0..clients {
        gw.add_user(&format!("perf{k}"), &password, vec!["viewer".into()])
            .unwrap();
    }
    let s = env.session().await;
    let c = Counter::on(&s).await;
    c.ready(points).await;
    let n = Arc::new(AtomicU64::new(0));
    let lat = Arc::new(Mutex::new(Lat::new()));
    let mut conns = Vec::new();
    let mut tasks = Vec::new();
    for k in 0..clients {
        let g = wyrm_gateway_client::Gateway::login(
            &format!("http://127.0.0.1:{gw_port}"),
            &format!("perf{k}"),
            &password,
        )
        .await
        .unwrap();
        let conn = g.connect().await.unwrap();
        let mut st = conn
            .subscribe(&format!("wy/{SITE}/downstream/mock/**"))
            .await
            .unwrap();
        let (n2, l2) = (n.clone(), lat.clone());
        tasks.push(tokio::spawn(async move {
            while let Some(ev) = st.next().await {
                if let wyrm_gateway_client::Event::Sample { t, .. } = ev {
                    let now = wyrm_core::clock::now_us();
                    l2.lock().unwrap().push_us(now.saturating_sub(t) as f64);
                    n2.fetch_add(1, Ordering::Relaxed);
                }
            }
        }));
        conns.push((g, conn));
    }
    tokio::time::sleep(Duration::from_secs(3)).await;
    *lat.lock().unwrap() = Lat::new();
    let base = n.load(Ordering::Relaxed);
    let u0 = Usage::read();
    tokio::time::sleep(Duration::from_secs(10)).await;
    let u1 = Usage::read();
    let got = n.load(Ordering::Relaxed) - base;
    let wall = u1.wall_since(&u0).as_secs_f64();
    let expected = (points as f64 * hz * wall * clients as f64).round() as u64;
    let mut l = std::mem::take(&mut *lat.lock().unwrap());
    println!(
        "{}",
        Perf::new(&format!("gateway/ws/{clients}x{points}x{hz}hz"))
            .lat(&mut l)
            .per_s(got as f64 / wall)
            .cpu_pct(u1.cpu_pct_since(&u0))
            .rss(u1.rss_bytes)
            .field("expected", expected)
            .field("lost", expected.saturating_sub(got))
            .note("samples to gateway WebSocket clients; latency = arrival - sample t")
    );
    for t in tasks {
        t.abort();
    }
    drop(conns);
    drop(c);
    env.stop().await;
}
