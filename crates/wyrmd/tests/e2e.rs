//! Broker end to end: external sessions (loopback TCP, mTLS) talk to links
//! through the router, under the generated ACL.

#[path = "../../wyrm-wasm-host/tests/guests/mod.rs"]
mod guests;

use std::collections::BTreeMap;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::oneshot;
use wyrm_admin::Control;
use wyrm_client::{ListEvent, SigningTokens, ValEvent, WyrmClient};
use wyrm_core::Value;
use wyrmd::{Config, Daemon};

const SEED: [u8; 32] = [9; 32];

/// Held while a test opens a daemon with a gateway: `Daemon::open` reads and
/// clears `WYRM_GATEWAY_ADMIN_PASSWORD`, a process-wide variable.
static GATEWAY_ENV: tokio::sync::Mutex<()> = tokio::sync::Mutex::const_new(());
const SITE: &str = "e2e";

/// A loopback port for a broker listener (`tcp/`, `tls/` or `quic/`): free
/// for TCP and UDP, never handed out twice in this process.
///
/// Not "bind port 0 and let it go": Linux hands out `bind(0)` ports at random
/// from a pool of about 7 000, so a released port comes back to another test
/// of this process within seconds. Both brokers then listen on it, the
/// second one fails to start ("address in use"), and its test cannot connect
/// (CI on 195b971 and 62a0a4c). The window is open from here until the
/// broker binds, and again while a rebuild has its listeners closed.
///
/// The ports come from below the ephemeral ranges (Linux from 32768, macOS
/// from 49152), which the kernel never assigns on its own, so no `bind(0)`
/// or outgoing socket takes one. A lock file per port keeps e2e processes
/// run side by side apart; the lock goes with the process.
fn free_port() -> u16 {
    use std::sync::atomic::{AtomicU32, Ordering};
    const FIRST: u32 = 20_000;
    const COUNT: u32 = 12_000;
    static NEXT: AtomicU32 = AtomicU32::new(0);
    static LOCKS: std::sync::Mutex<Vec<std::fs::File>> = std::sync::Mutex::new(Vec::new());
    let dir = std::env::temp_dir().join("wyrmd-e2e-ports");
    std::fs::create_dir_all(&dir).unwrap();
    // processes start at different places, so they rarely meet a lock
    let start = std::process::id().wrapping_mul(7_919) % COUNT;
    for _ in 0..COUNT {
        let n = NEXT.fetch_add(1, Ordering::Relaxed);
        let port = (FIRST + (start + n) % COUNT) as u16;
        let Ok(lock) = std::fs::File::create(dir.join(port.to_string())) else {
            continue;
        };
        if lock.try_lock().is_err() {
            continue;
        }
        let free = std::net::TcpListener::bind(("127.0.0.1", port)).is_ok()
            && std::net::UdpSocket::bind(("127.0.0.1", port)).is_ok();
        if free {
            LOCKS.lock().unwrap().push(lock);
            return port;
        }
    }
    panic!("no free port in {FIRST}..{}", FIRST + COUNT);
}

/// What two tests on one port did on CI: the second broker cannot open its
/// listener, and the daemon ends with that error (Zenoh tries a listener
/// once and gives up).
#[tokio::test(flavor = "multi_thread")]
async fn a_listener_port_in_use_ends_the_daemon() {
    let port = free_port();
    let _held = std::net::TcpListener::bind(("127.0.0.1", port)).unwrap();
    let cfg = Config::from_json5(&format!(
        r#"{{ site: "busy", data_dir: "{}", listen: ["tcp/127.0.0.1:{port}"] }}"#,
        temp_dir("busy").display()
    ))
    .unwrap();
    let d = open_daemon(cfg, env!("CARGO_BIN_EXE_wyrmd").into()).unwrap();
    let r = tokio::time::timeout(Duration::from_secs(30), d.run_until(std::future::pending()))
        .await
        .expect("the daemon ends by itself");
    let e = r.expect_err("a port in use is an error").to_string();
    assert!(e.contains(&port.to_string()), "{e}");
}

#[test]
fn ports_are_unique_and_never_kernel_assigned() {
    let ports: Vec<u16> = (0..200).map(|_| free_port()).collect();
    let unique: std::collections::BTreeSet<_> = ports.iter().collect();
    assert_eq!(unique.len(), ports.len(), "a port handed out twice");
    // below Linux's default ephemeral range (and macOS's)
    assert!(
        ports.iter().all(|p| (20_000..32_000).contains(p)),
        "{ports:?}"
    );
    // and below this machine's, where it can be read
    if let Ok(range) = std::fs::read_to_string("/proc/sys/net/ipv4/ip_local_port_range") {
        let low: u32 = range.split_whitespace().next().unwrap().parse().unwrap();
        assert!(low >= 32_000, "ephemeral ports start at {low}: {range}");
    }
}

fn temp_dir(name: &str) -> PathBuf {
    let d = std::env::temp_dir().join(format!("wyrmd-e2e-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&d);
    d
}

/// `Daemon::open` after the broker's log subscriber is in place. Zenoh's
/// storage plugin installs its own global subscriber when a router starts
/// if none is set yet, and `wyrmd`'s main installs ours first; tests in one
/// process must do the same, or the log tests' level control has no
/// subscriber behind it.
fn open_daemon(cfg: Config, exe: PathBuf) -> Result<Daemon, wyrmd::Error> {
    let _ = wyrm_admin::logs::install_quiet();
    Daemon::open(cfg, exe)
}

struct Env {
    port: u16,
    tls: u16,
    ctl: Arc<Control>,
    gateway: Option<Arc<wyrm_gateway::Gateway>>,
    stop: Option<oneshot::Sender<()>>,
    task: tokio::task::JoinHandle<Result<(), wyrmd::Error>>,
}

impl Env {
    /// `extra`: more json5 fields (without braces).
    async fn start(name: &str, extra: &str) -> Self {
        Self::start_in(&temp_dir(name), extra).await
    }

    /// Like `start`, in `dir` as it is (a restart keeps the state).
    async fn start_in(dir: &std::path::Path, extra: &str) -> Self {
        let (port, tls) = (free_port(), free_port());
        let key = ed25519_dalek::SigningKey::from_bytes(&SEED);
        let text = format!(
            r#"{{
                site: "{SITE}",
                data_dir: "{}",
                listen: ["tcp/127.0.0.1:{port}", "tls/127.0.0.1:{tls}"],
                admin_keys: ["{}"],
                metrics_interval_ms: 200,
                {extra}
            }}"#,
            dir.display(),
            hex::encode(key.verifying_key().to_bytes())
        );
        // After a restart, tasks of the previous broker may still hold the
        // state lock for a moment.
        let mut tries = 0;
        let daemon = loop {
            let cfg = Config::from_json5(&text).unwrap();
            match open_daemon(cfg, env!("CARGO_BIN_EXE_wyrmd").into()) {
                Ok(d) => break d,
                Err(e) if tries < 50 && e.to_string().contains("in use") => {
                    tries += 1;
                    tokio::time::sleep(Duration::from_millis(100)).await;
                }
                Err(e) => panic!("open: {e}"),
            }
        };
        let ctl = daemon.control();
        let gateway = daemon.gateway();
        let (stop, rx) = oneshot::channel();
        let task = tokio::spawn(daemon.run_until(async {
            let _ = rx.await;
        }));
        let mut env = Self {
            port,
            tls,
            ctl,
            gateway,
            stop: Some(stop),
            task,
        };
        // Wait for both listeners (on a slow CI the tls one comes later). A
        // broker that cannot open one ends at once: say why, instead of a
        // connect error later.
        let deadline = tokio::time::Instant::now() + Duration::from_secs(30);
        loop {
            let up = |p| std::net::TcpStream::connect(("127.0.0.1", p)).is_ok();
            if up(port) && up(tls) {
                break;
            }
            if env.task.is_finished() {
                let r = (&mut env.task).await;
                panic!("wyrmd ended before its listeners opened: {r:?}");
            }
            assert!(
                tokio::time::Instant::now() < deadline,
                "wyrmd listeners tcp {port} and tls {tls} not up in 30 s"
            );
            tokio::time::sleep(Duration::from_millis(30)).await;
        }
        env
    }

    async fn session(&self) -> zenoh::Session {
        self.try_session().await.unwrap()
    }

    /// `None` while the router is being rebuilt (ACL change).
    async fn try_session(&self) -> Option<zenoh::Session> {
        let mut zc = zenoh::Config::default();
        zc.insert_json5("mode", r#""client""#).unwrap();
        zc.insert_json5(
            "connect/endpoints",
            &format!(r#"["tcp/127.0.0.1:{}"]"#, self.port),
        )
        .unwrap();
        zc.insert_json5("scouting/multicast/enabled", "false")
            .unwrap();
        zenoh::open(zc).await.ok()
    }

    /// mTLS session presenting a CA-issued certificate with CN `cn`.
    async fn tls_session(&self, cn: &str) -> zenoh::Session {
        let files = self.ctl.link_cert(cn).unwrap();
        let mut zc = zenoh::Config::default();
        zc.insert_json5("mode", r#""client""#).unwrap();
        zc.insert_json5(
            "connect/endpoints",
            &format!(r#"["tls/127.0.0.1:{}"]"#, self.tls),
        )
        .unwrap();
        zc.insert_json5("scouting/multicast/enabled", "false")
            .unwrap();
        zc.insert_json5(
            "transport/link/tls",
            &serde_json::json!({
                "root_ca_certificate": self.ctl.ca_path(),
                "connect_certificate": files.cert,
                "connect_private_key": files.key,
                "enable_mtls": true,
            })
            .to_string(),
        )
        .unwrap();
        // the listeners are closed while an ACL change rebuilds the router
        for _ in 0..10 {
            if let Ok(s) = zenoh::open(zc.clone()).await {
                return s;
            }
            tokio::time::sleep(Duration::from_millis(300)).await;
        }
        zenoh::open(zc).await.unwrap()
    }

    async fn client(&self) -> WyrmClient {
        let key = ed25519_dalek::SigningKey::from_bytes(&SEED);
        WyrmClient::new(self.session().await)
            .with_tokens(Arc::new(SigningTokens::new(key, SITE)))
            .with_timeout(Duration::from_secs(3))
    }

    async fn stop(mut self) {
        let _ = self.stop.take().unwrap().send(());
        self.task.await.unwrap().unwrap();
    }
}

async fn eventually<T, F, Fut>(what: &str, secs: u64, mut f: F) -> T
where
    F: FnMut() -> Fut,
    Fut: std::future::Future<Output = Option<T>>,
{
    let deadline = tokio::time::Instant::now() + Duration::from_secs(secs);
    loop {
        if let Some(v) = f().await {
            return v;
        }
        assert!(tokio::time::Instant::now() < deadline, "timeout: {what}");
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
}

async fn last_val(c: &WyrmClient, node: &str) -> Option<Value> {
    let r = c.session().get(format!("{node}/~val")).await.ok()?;
    let reply = r.recv_async().await.ok()?;
    let s = reply.result().ok()?;
    wyrm_core::codec::from_slice::<wyrm_core::Sample>(&s.payload().to_bytes())
        .ok()
        .map(|s| s.v)
}

fn sample(v: f64) -> Vec<u8> {
    wyrm_core::codec::to_vec(&wyrm_core::Sample {
        v: Value::Float(v),
        q: wyrm_core::Quality::Good,
        t: 1,
    })
    .unwrap()
}

const MOCK: &str = r#"links: { mock: { driver: "mock", params: { points: 8, rate_hz: 20, depth: 1, fanout: 2 } } },"#;

#[tokio::test(flavor = "multi_thread")]
async fn list_resolve_set_invoke_over_router() {
    let env = Env::start("basic", MOCK).await;
    let c = env.client().await;
    let root = format!("wy/{SITE}/downstream/mock");

    let mut links = c.list(&format!("wy/{SITE}/downstream")).await.unwrap();
    let Some(ListEvent::Refreshed(snap)) = links.next().await else {
        panic!()
    };
    // and the embedded scheduler (ADR 0022)
    assert_eq!(
        snap.iter().map(|c| c.name.as_str()).collect::<Vec<_>>(),
        ["mock", "scheduler"]
    );
    assert_eq!(c.children(&format!("{root}/g1")).await.unwrap().len(), 4);
    // multi-term match: the raw selector survives the router hop
    let keys = c
        .resolve(&root, Some("type:1;unit:°C"), Some(2))
        .await
        .unwrap();
    assert_eq!(keys.len(), 8);

    c.set(&format!("{root}/g0/p0"), 33.0).await.unwrap();
    let mut args = BTreeMap::new();
    args.insert("n".to_owned(), Value::UInt(3));
    let mut s = c.invoke(&root, "count", Value::Map(args)).await.unwrap();
    let mut got = Vec::new();
    while let Some(v) = s.next().await {
        got.push(v.unwrap().unwrap());
    }
    assert_eq!(got.len(), 3);
    env.stop().await;
}

/// Broker storage (ADR 0017): nodes and values made over the router come
/// back after a restart of wyrmd.
#[tokio::test(flavor = "multi_thread")]
async fn storage_keeps_nodes_and_values_across_restarts() {
    let dir = temp_dir("data-storage");
    let env = Env::start_in(&dir, "").await;
    let c = env.client().await;
    let root = format!("wy/{SITE}/storage");
    let args = |kv: &[(&str, Value)]| {
        Value::Map(
            kv.iter()
                .map(|(k, v)| ((*k).to_owned(), v.clone()))
                .collect(),
        )
    };
    c.invoke_one(&root, "add_node", args(&[("name", "plant".into())]))
        .await
        .unwrap();
    let number = args(&[("name", "temp".into()), ("type", Value::from("number"))]);
    c.invoke_one(&format!("{root}/plant"), "add_value", number)
        .await
        .unwrap();
    c.set(&format!("{root}/plant/temp"), 21.5).await.unwrap();
    let publish = args(&[("path", "plant/count".into()), ("value", Value::UInt(3))]);
    c.invoke_one(&root, "publish", publish).await.unwrap();
    assert_eq!(
        last_val(&c, &format!("{root}/plant/temp")).await,
        Some(Value::Float(21.5))
    );
    let wrong = c.set(&format!("{root}/plant/temp"), "warm").await;
    assert!(wrong.is_err(), "a number node refuses text");
    drop(c);
    env.stop().await;

    let env = Env::start_in(&dir, "").await;
    let c = env.client().await;
    let names: Vec<String> = c
        .children(&format!("{root}/plant"))
        .await
        .unwrap()
        .into_iter()
        .map(|n| n.name)
        .collect();
    assert_eq!(names, ["count", "temp"]);
    let temp = format!("{root}/plant/temp");
    let v = eventually("value after restart", 5, || async {
        last_val(&c, &temp).await
    })
    .await;
    assert_eq!(v, Value::Float(21.5));
    env.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn subscribe_reads_storage_first() {
    let env = Env::start("storage", MOCK).await;
    let c = env.client().await;
    tokio::time::sleep(Duration::from_millis(300)).await;
    let mut vals = c
        .subscribe(&format!("wy/{SITE}/downstream/mock/**"))
        .await
        .unwrap();
    let mut keys = std::collections::BTreeSet::new();
    let deadline = tokio::time::Instant::now() + Duration::from_secs(3);
    while keys.len() < 8 && tokio::time::Instant::now() < deadline {
        if let Ok(Some(ValEvent::Sample { key, .. })) =
            tokio::time::timeout(Duration::from_secs(1), vals.next()).await
        {
            keys.insert(key);
        }
    }
    assert_eq!(keys.len(), 8);
    env.stop().await;
}

/// prod profile: a loopback session is a requester; it cannot publish into
/// a link's branch (that would let any local process pose as a link).
#[tokio::test(flavor = "multi_thread")]
async fn loopback_cannot_publish_into_down() {
    let env = Env::start("loopback", MOCK).await;
    let s = env.session().await;
    let key = format!("wy/{SITE}/downstream/fake/x/~val");
    s.put(&key, sample(1.0)).await.unwrap();
    tokio::time::sleep(Duration::from_millis(300)).await;
    let r = s.get(&key).await.unwrap();
    assert!(
        r.recv_async().await.is_err(),
        "storage must not have the forged value"
    );
    env.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn embedded_modbus_from_json5() {
    let (addr, dev, _task) = wyrm_link_modbus::sim::spawn("127.0.0.1:0").await.unwrap();
    dev.lock().unwrap().input[1] = 215;
    let env = Env::start(
        "modbus",
        &format!(
            r#"links: {{ plc1: {{ driver: "modbus", params: {{ connections: {{ c1: {{
                host: "127.0.0.1", port: {},
                devices: {{ ahu1: {{ unit: 1, points: {{
                  supply_temp: {{ table: "input", addr: 1, dtype: "i16", scale: 0.1, unit: "°C", poll_s: 0.05 }},
                }} }} }},
            }} }} }} }} }},"#,
            addr.port()
        ),
    )
    .await;
    let c = env.client().await;
    let node = format!("wy/{SITE}/downstream/plc1/c1/ahu1/supply_temp");
    let v = eventually("modbus value", 5, || async { last_val(&c, &node).await }).await;
    assert_eq!(v, Value::Float(21.5));
    env.stop().await;
}

/// Wiki iteration 2, criterion 1: the same modbus driver as a supervised process.
#[tokio::test(flavor = "multi_thread")]
async fn modbus_as_process() {
    let (addr, dev, _task) = wyrm_link_modbus::sim::spawn("127.0.0.1:0").await.unwrap();
    dev.lock().unwrap().input[1] = 215;
    let env = Env::start(
        "process",
        &format!(
            r#"links: {{ plc1: {{ driver: "modbus", mode: "process", params: {{ connections: {{ c1: {{
                host: "127.0.0.1", port: {},
                devices: {{ ahu1: {{ unit: 1, points: {{
                  supply_temp: {{ table: "input", addr: 1, dtype: "i16", scale: 0.1, poll_s: 0.05 }},
                  fan: {{ table: "coil", addr: 3, dtype: "binary", writable: true, poll_s: 0.05 }},
                }} }} }},
            }} }} }} }} }},"#,
            addr.port()
        ),
    )
    .await;
    let c = env.client().await;
    let state = format!("wy/{SITE}/sys/links/plc1/state");
    eventually("plc1 connected", 15, || async {
        (last_val(&c, &state).await == Some(Value::UInt(2))).then_some(())
    })
    .await;
    let node = format!("wy/{SITE}/downstream/plc1/c1/ahu1/supply_temp");
    let v = eventually("value from the process", 15, || async {
        last_val(&c, &node).await
    })
    .await;
    assert_eq!(v, Value::Float(21.5));
    // a write goes through the router into the process and the device
    c.set(&format!("wy/{SITE}/downstream/plc1/c1/ahu1/fan"), true)
        .await
        .unwrap();
    assert!(dev.lock().unwrap().coils[3]);
    env.stop().await;
}

/// Wiki iteration 2, criteria 2 and 3: an unknown CA-signed certificate is
/// quarantined, its attempts show in `acl_denied_total`; approve lets it in.
#[tokio::test(flavor = "multi_thread")]
async fn unknown_cert_quarantine_and_acl_denied() {
    let env = Env::start("quarantine", MOCK).await;
    let c = env.client().await;
    let mcu = env.tls_session("mcu-7").await;
    let qnode = format!("wy/{SITE}/sys/quarantine/mcu-7");
    eventually("quarantine entry", 5, || async {
        c.meta(&qnode).await.ok()
    })
    .await;

    // the unknown session cannot publish into downstream/**
    let key = format!("wy/{SITE}/downstream/mcu-7/t/~val");
    mcu.put(&key, sample(1.0)).await.unwrap();
    let total = format!("wy/{SITE}/sys/acl_denied");
    eventually("acl_denied_total > 0", 5, || async {
        match last_val(&c, &total).await {
            Some(Value::UInt(n)) if n > 0 => Some(()),
            _ => None,
        }
    })
    .await;
    assert!(last_val(&c, &format!("wy/{SITE}/downstream/mcu-7/t"))
        .await
        .is_none());

    // approve → ACL rebuilt → the same certificate may publish its branch
    let reply = c
        .invoke_one(&qnode, "approve", Value::Map(Default::default()))
        .await
        .unwrap();
    assert!(matches!(reply, Some(Value::Map(m)) if m.contains_key("token")));
    eventually("approved link may publish", 15, || async {
        let c2 = WyrmClient::new(env.try_session().await?);
        mcu.put(&key, sample(2.0)).await.ok()?;
        tokio::time::sleep(Duration::from_millis(100)).await;
        (last_val(&c2, &format!("wy/{SITE}/downstream/mcu-7/t")).await == Some(Value::Float(2.0)))
            .then_some(())
    })
    .await;
    let audit = env.ctl.audit_tail(50);
    for op in ["quarantine", "acl_denied", "approve"] {
        assert!(audit.iter().any(|r| r.op == op), "audit has {op}");
    }
    env.stop().await;
}

/// DSA-style `sys` values (broker info, traffic rates) and
/// the two options that decide what happens to an unknown certificate.
#[tokio::test(flavor = "multi_thread")]
async fn sys_values_and_admission_options() {
    let env = Env::start("sysvals", MOCK).await;
    let c = env.client().await;
    let sys = format!("wy/{SITE}/sys");
    let text = |v: Option<Value>| match v {
        Some(Value::Str(s)) => s,
        other => panic!("not a string: {other:?}"),
    };
    assert!(!text(last_val(&c, &format!("{sys}/version")).await).is_empty());
    assert!(text(last_val(&c, &format!("{sys}/zenoh_version")).await).starts_with("v1."));
    let started = text(last_val(&c, &format!("{sys}/start_time")).await);
    assert!(started.len() == 20 && started.ends_with('Z'), "{started}");
    assert_eq!(
        text(last_val(&c, &format!("{sys}/distribution")).await),
        "rust (prod)"
    );
    // A node's name is its key: no display names in sys (actions and their
    // parameters keep theirs; a link keeps the name given at Authorize).
    let mut todo = vec![sys.clone()];
    let mut walked = 0;
    let links = format!("{sys}/links/");
    while let Some(key) = todo.pop() {
        let meta = c.meta(&key).await.unwrap();
        let link = key.strip_prefix(&links).is_some_and(|id| !id.contains('/'));
        if !link {
            assert_eq!(meta.attr_value("display"), None, "{key}");
        }
        assert_eq!(key, key.to_lowercase());
        for name in meta.children.unwrap_or_default() {
            todo.push(format!("{key}/{name}"));
        }
        walked += 1;
    }
    assert!(walked > 40, "{walked} nodes");
    // sys itself carries the protocol version; no broker or metrics nodes,
    // but the broker's liveliness token is there
    let root = c.meta(&sys).await.unwrap();
    assert_eq!(
        root.attr_value("proto"),
        Some(&Value::UInt(wyrm_core::PROTO_VERSION.into()))
    );
    for gone in ["broker", "metrics", "downstream"] {
        assert!(c.meta(&format!("{sys}/{gone}")).await.is_err(), "{gone}");
    }
    let token = c
        .session()
        .liveliness()
        .get(format!("{sys}/broker"))
        .await
        .unwrap()
        .recv_async()
        .await;
    assert!(token.is_ok(), "broker liveliness token");
    eventually("status values", 5, || async {
        for key in [
            "uptime",
            "links_total",
            "links_connected",
            "sessions",
            "cpu",
            "memory",
            "disk_free",
            "data_size",
            "audit_records",
        ] {
            last_val(&c, &format!("{sys}/{key}")).await?;
        }
        Some(())
    })
    .await;
    assert_eq!(
        last_val(&c, &format!("{sys}/links_total")).await,
        Some(Value::UInt(1))
    );
    eventually("traffic rates", 5, || async {
        match last_val(&c, &format!("{sys}/data_in_per_second")).await {
            Some(Value::Float(r)) if r > 0.0 => Some(()),
            _ => None,
        }
    })
    .await;

    // Quarantine off: an unknown certificate is ignored.
    let quarantine = format!("{sys}/enable_quarantine");
    assert_eq!(last_val(&c, &quarantine).await, Some(Value::Bool(true)));
    c.set(&quarantine, false).await.unwrap();
    assert_eq!(last_val(&c, &quarantine).await, Some(Value::Bool(false)));
    let ghost = env.tls_session("ghost-1").await;
    tokio::time::sleep(Duration::from_secs(1)).await;
    assert!(c.meta(&format!("{sys}/quarantine/ghost-1")).await.is_err());
    // closed first: once allow-all is on, its reconnect would be admitted
    ghost.close().await.unwrap();

    // Allow all links: the next unknown certificate becomes an external link.
    let allow = format!("{sys}/allow_all_links");
    assert_eq!(last_val(&c, &allow).await, Some(Value::Bool(false)));
    c.set(&allow, true).await.unwrap();
    let dev = env.tls_session("dev-1").await;
    let key = format!("wy/{SITE}/downstream/dev-1/t/~val");
    eventually("auto-installed link may publish", 15, || async {
        let c2 = WyrmClient::new(env.try_session().await?);
        dev.put(&key, sample(3.0)).await.ok()?;
        tokio::time::sleep(Duration::from_millis(100)).await;
        (last_val(&c2, &format!("wy/{SITE}/downstream/dev-1/t")).await == Some(Value::Float(3.0)))
            .then_some(())
    })
    .await;
    let reg = env.ctl.registry();
    assert!(reg.links.contains_key("dev-1"));
    assert!(
        !reg.links.contains_key("ghost-1"),
        "seen while quarantine was off"
    );
    assert!(reg.options.allow_all_links && !reg.options.enable_quarantine);
    let audit = env.ctl.audit_tail(50);
    for op in ["set_option", "auto_install"] {
        assert!(audit.iter().any(|r| r.op == op), "audit has {op}");
    }

    // Clear Conns forgets the external link once it is gone (DSA clearConns).
    dev.close().await.unwrap();
    let cleared = eventually("clear conns removes dev-1", 15, || async {
        let c2 = env.try_session().await?;
        let key = ed25519_dalek::SigningKey::from_bytes(&SEED);
        let c2 = WyrmClient::new(c2)
            .with_tokens(Arc::new(SigningTokens::new(key, SITE)))
            .with_timeout(Duration::from_secs(3));
        match c2
            .invoke_one(&sys, "clear_conns", Value::Map(Default::default()))
            .await
        {
            Ok(Some(v)) => Some(v),
            _ => None,
        }
    })
    .await;
    assert_eq!(cleared, Value::Array(vec![Value::from("dev-1")]));
    let reg = env.ctl.registry();
    assert!(!reg.links.contains_key("dev-1") && reg.retired.contains("dev-1"));
    assert!(reg.links.contains_key("mock"), "embedded links stay");
    env.stop().await;
}

/// DSA Authorize / Deauthorize on `sys/quarantine` (owner decisions
/// 2026-10-22): `dsid` lists the quarantined CNs, `name` is the display
/// name, `group` gives a gateway role write on the link; Deauthorize puts
/// the link back into quarantine (not retired), and allow-all does not
/// re-admit it.
#[tokio::test(flavor = "multi_thread")]
async fn authorize_and_deauthorize() {
    let gw_port = free_port();
    let env_lock = GATEWAY_ENV.lock().await;
    let env = Env::start(
        "authz",
        &format!(r#"{MOCK} gateway: {{ listen: "127.0.0.1:{gw_port}", admin_user: "nobody" }},"#),
    )
    .await;
    drop(env_lock);
    let gw = env.gateway.clone().expect("gateway");
    gw.add_user("boss", "boss-password-1", vec!["admin".into()])
        .unwrap();
    let c = env.client().await;
    let q = format!("wy/{SITE}/sys/quarantine");
    let _dev = env.tls_session("dev-7").await;
    let meta = eventually("dev-7 in the Authorize list", 5, || async {
        let m = c.meta(&q).await.ok()?;
        let a = m.actions.as_ref()?.get("authorize")?.clone();
        let cns = a.params.get("dsid")?.enum_values.clone()?;
        cns.contains(&"dev-7".to_owned()).then_some(a)
    })
    .await;
    let groups = meta.params["group"].enum_values.clone().unwrap();
    assert!(groups.contains(&"operator".to_owned()) && groups[0] == "-");

    let args = |pairs: &[(&str, &str)]| {
        Value::Map(
            pairs
                .iter()
                .map(|(k, v)| (k.to_string(), Value::from(*v)))
                .collect(),
        )
    };
    let reply = c
        .invoke_one(
            &q,
            "authorize",
            args(&[("dsid", "dev-7"), ("name", "Pump 7"), ("group", "viewer")]),
        )
        .await
        .unwrap();
    assert!(
        matches!(&reply, Some(Value::Map(m)) if m.contains_key("token") && !m.contains_key("warning")),
        "{reply:?}"
    );
    let def = env.ctl.registry().links["dev-7"].clone();
    assert_eq!(def.display.as_deref(), Some("Pump 7"));
    assert!(gw.role_table().get("viewer").unwrap().contains(&(
        "wy/{site}/downstream/dev-7/**".to_string(),
        wyrm_core::Perm::Write
    )));

    // a restrictive grant made by hand (operator: list only on this link)
    gw.set_grant(
        "operator",
        "wy/{site}/downstream/dev-7/**",
        wyrm_core::Perm::List,
    )
    .unwrap();

    // Deauthorize (after the ACL rebuild): back to quarantine, not retired
    eventually("deauthorize", 15, || async {
        let c = env.client().await;
        c.invoke_one(&q, "deauthorize", args(&[("link", "dev-7")]))
            .await
            .ok()
    })
    .await;
    let reg = env.ctl.registry();
    assert!(!reg.links.contains_key("dev-7") && !reg.retired.contains("dev-7"));
    assert!(
        !gw.role_table()
            .get("viewer")
            .unwrap()
            .iter()
            .any(|(k, _)| k.contains("dev-7")),
        "the widening group grant goes with the link"
    );
    assert!(
        gw.role_table().get("operator").unwrap().contains(&(
            "wy/{site}/downstream/dev-7/**".to_string(),
            wyrm_core::Perm::List
        )),
        "a restrictive grant made by hand stays"
    );
    assert!(reg.quarantine.contains_key("dev-7") && reg.held.contains("dev-7"));

    // allow-all does not re-admit a deauthorized CN
    eventually("allow all on", 15, || async {
        let c = env.client().await;
        c.set(&format!("wy/{SITE}/sys/allow_all_links"), true)
            .await
            .ok()
    })
    .await;
    let _again = env.tls_session("dev-7").await;
    tokio::time::sleep(Duration::from_secs(1)).await;
    assert!(!env.ctl.registry().links.contains_key("dev-7"));
    assert!(env.ctl.audit_tail(50).iter().any(|r| r.op == "deauthorize"));
    env.stop().await;
}

/// A link package (ADR 0011) whose entry is a shell script running this
/// test's `wyrmd link mock`: the script path is absolute because the
/// supervisor clears the environment.
fn mock_package(version: &str) -> Vec<u8> {
    driver_package("mockpkg", version, "mock link as a package", "mock")
}

/// A process package `name` whose entry runs `wyrmd link <driver>`.
fn driver_package(name: &str, version: &str, description: &str, driver: &str) -> Vec<u8> {
    driver_package_with(name, version, description, driver, None)
}

/// [`driver_package`] with `capabilities` in its manifest (a portable app as a process).
fn driver_package_with(
    name: &str,
    version: &str,
    description: &str,
    driver: &str,
    capabilities: Option<serde_json::Value>,
) -> Vec<u8> {
    use std::io::Write;
    use zip::write::SimpleFileOptions;
    let mut manifest = serde_json::json!({
        "name": name,
        "version": version,
        "description": description,
        "wyrm_link": wyrm_link_sdk::LINK_PROTOCOL,
        "kind": "process",
        "entries": { wyrm_admin::packages::platform(): "bin/run" },
    });
    if let Some(c) = capabilities {
        manifest["capabilities"] = c;
    }
    let script = format!(
        "#!/bin/sh\nexec \"{}\" link {driver}\n",
        env!("CARGO_BIN_EXE_wyrmd")
    );
    let mut w = zip::ZipWriter::new(std::io::Cursor::new(Vec::new()));
    let opt = SimpleFileOptions::default();
    w.start_file(wyrm_admin::packages::MANIFEST, opt).unwrap();
    w.write_all(manifest.to_string().as_bytes()).unwrap();
    w.start_file("bin/run", opt.unix_permissions(0o644))
        .unwrap();
    w.write_all(script.as_bytes()).unwrap();
    w.finish().unwrap().into_inner()
}

/// DSA "Install Link ▸ from Zip": a package runs as a process link; a second
/// link reuses it; a new version replaces it and restarts its links; a bad
/// zip answers `success: false`.
#[tokio::test(flavor = "multi_thread")]
async fn install_link_from_zip() {
    let env = Env::start("pkgzip", "").await;
    let links = format!("wy/{SITE}/sys/links");
    let install = |name: &str, zip: Vec<u8>| {
        Value::Map(BTreeMap::from([
            ("name".to_owned(), Value::from(name)),
            ("zip".to_owned(), Value::Bytes(zip)),
        ]))
    };
    let outcome = |v: Option<Value>| -> (bool, String) {
        let Some(Value::Map(m)) = v else {
            panic!("result map: {v:?}")
        };
        let ok = m.get("success") == Some(&Value::Bool(true));
        let msg = match m.get("message") {
            Some(Value::Str(s)) => s.clone(),
            other => panic!("message: {other:?}"),
        };
        (ok, msg)
    };
    // Each process link install rebuilds the router: every call retries
    // until the broker answers (Ok, or an error from the admin itself).
    let call = |key: String, action: &'static str, args: Value| {
        let env = &env;
        async move {
            eventually(action, 20, || {
                let (key, args) = (key.clone(), args.clone());
                async move {
                    let s = env.try_session().await?;
                    let seed = ed25519_dalek::SigningKey::from_bytes(&SEED);
                    let c = WyrmClient::new(s)
                        .with_tokens(Arc::new(SigningTokens::new(seed, SITE)))
                        .with_timeout(Duration::from_secs(3));
                    match c.invoke_one(&key, action, args).await {
                        Ok(v) => Some(Ok(v)),
                        Err(e) if e.is(wyrm_core::Status::InvalidParameter) => Some(Err(e)),
                        Err(_) => None,
                    }
                }
            })
            .await
        }
    };
    let (ok, msg) = outcome(
        call(
            links.clone(),
            "install_zip",
            install("pk1", mock_package("1.0.0")),
        )
        .await
        .unwrap(),
    );
    assert!(ok, "{msg}");
    let pkg = env.ctl.registry().packages["mockpkg"].clone();
    assert_eq!(pkg.version, "1.0.0");
    assert_eq!(env.ctl.registry().links["pk1"].driver, "pkg:mockpkg");
    eventually("pk1 runs as a process", 20, || async {
        let c = WyrmClient::new(env.try_session().await?);
        let ch = c
            .children(&format!("wy/{SITE}/downstream/pk1"))
            .await
            .ok()?;
        (!ch.is_empty()).then_some(())
    })
    .await;

    // a second link of the same package bytes
    let (ok, msg) = outcome(
        call(
            links.clone(),
            "install_zip",
            install("pk2", mock_package("1.0.0")),
        )
        .await
        .unwrap(),
    );
    assert!(
        ok && msg.contains("is installed") && msg.contains("pk2"),
        "{msg}"
    );

    // a new version replaces the old one
    let (ok, msg) = outcome(
        call(
            links.clone(),
            "install_zip",
            install("pk1", mock_package("1.1.0")),
        )
        .await
        .unwrap(),
    );
    assert!(ok && msg.contains("1.0.0 → 1.1.0"), "{msg}");
    let root = env.ctl.packages_root();
    assert!(!root.join("mockpkg/1.0.0").exists() && root.join("mockpkg/1.1.0/bin/run").exists());

    // a bad zip is success: false, not an error
    let (ok, msg) = outcome(
        call(
            links.clone(),
            "install_zip",
            install("pk3", b"not a zip".to_vec()),
        )
        .await
        .unwrap(),
    );
    assert!(!ok && msg.contains("zip"), "{msg}");
    // the package cannot go while links run it
    let err = call(
        format!("wy/{SITE}/sys/packages/mockpkg"),
        "remove",
        Value::Map(Default::default()),
    )
    .await
    .expect_err("in use");
    assert!(err.is(wyrm_core::Status::InvalidParameter), "{err}");
    assert!(env
        .ctl
        .audit_tail(50)
        .iter()
        .any(|r| r.op == "package_install"));
    env.stop().await;
}

/// A tiny HTTP/1.1 server on loopback: `path → (status, extra headers, body)`.
async fn serve_files(files: std::collections::HashMap<String, (u16, String, Vec<u8>)>) -> u16 {
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    let l = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = l.local_addr().unwrap().port();
    let files = Arc::new(files);
    tokio::spawn(async move {
        while let Ok((mut s, _)) = l.accept().await {
            let files = files.clone();
            tokio::spawn(async move {
                let mut buf = vec![0u8; 4096];
                let n = s.read(&mut buf).await.unwrap_or(0);
                let req = String::from_utf8_lossy(&buf[..n]);
                let path = req.split_whitespace().nth(1).unwrap_or("/").to_owned();
                let (status, headers, body) =
                    files
                        .get(&path)
                        .cloned()
                        .unwrap_or((404, String::new(), Vec::new()));
                let head = format!(
                    "HTTP/1.1 {status} X\r\nContent-Length: {}\r\nConnection: close\r\n{headers}\r\n",
                    body.len()
                );
                let _ = s.write_all(head.as_bytes()).await;
                let _ = s.write_all(&body).await;
            });
        }
    });
    port
}

/// "Install Link ▸ from Url | from Repository | from Git" (ADR 0011): the
/// same package checks as from Zip; Url follows a redirect; Repository
/// lists its index in the background and checks the SHA-256; Git clones
/// (file:// only in the dev profile) without `.git`.
#[tokio::test(flavor = "multi_thread")]
async fn install_link_from_url_repository_git() {
    use sha2::Digest;
    let v1 = mock_package("1.0.0");
    let v2 = mock_package("2.0.0");
    let sha = |b: &[u8]| hex::encode(sha2::Sha256::digest(b));
    // one server for the zips; the index (with their URLs) on a second one
    let mut files = std::collections::HashMap::new();
    files.insert("/v1.zip".to_owned(), (200, String::new(), v1.clone()));
    files.insert("/v2.zip".to_owned(), (200, String::new(), v2.clone()));
    files.insert(
        "/moved".to_owned(),
        (302, "Location: /v1.zip\r\n".to_owned(), Vec::new()),
    );
    let port = serve_files(files.clone()).await;
    let url = |p: &str| format!("http://127.0.0.1:{port}{p}");
    // ADR 0021: a file per host in `assets`, relative to the index
    let host = wyrm_admin::packages::platform();
    let other = if host == "linux-x86_64" {
        "macos-aarch64"
    } else {
        "linux-x86_64"
    };
    let index = serde_json::json!([
        { "name": "mockpkg", "version": "2.0.0", "url": url("/v2.zip"), "sha256": sha(&v2) },
        { "name": "tampered", "version": "1.0.0", "url": url("/v1.zip"), "sha256": sha(&v2) },
        { "name": "hosted", "version": "1.0.0",
          "assets": { host.clone(): { "url": "v1.zip", "sha256": sha(&v1) } } },
        { "name": "elsewhere", "version": "1.0.0",
          "assets": { other: { "url": "v1.zip", "sha256": sha(&v1) } } },
    ]);
    files.insert(
        "/index.json".to_owned(),
        (200, String::new(), index.to_string().into_bytes()),
    );
    let port = serve_files(files).await;
    let url = |p: &str| format!("http://127.0.0.1:{port}{p}");

    let env = Env::start(
        "pkgsrc",
        &format!(
            r#"profile: "dev", packages: {{ repository: "{}" }},"#,
            url("/index.json")
        ),
    )
    .await;
    let links = format!("wy/{SITE}/sys/links");
    let args = |pairs: &[(&str, &str)]| {
        Value::Map(
            pairs
                .iter()
                .map(|(k, v)| (k.to_string(), Value::from(*v)))
                .collect(),
        )
    };
    let call = |action: &'static str, a: Value| {
        let env = &env;
        let links = links.clone();
        async move {
            eventually(action, 30, || {
                let (links, a) = (links.clone(), a.clone());
                async move {
                    let s = env.try_session().await?;
                    let seed = ed25519_dalek::SigningKey::from_bytes(&SEED);
                    let c = WyrmClient::new(s)
                        .with_tokens(Arc::new(SigningTokens::new(seed, SITE)))
                        .with_timeout(Duration::from_secs(10));
                    let Some(Value::Map(m)) = c.invoke_one(&links, action, a).await.ok()? else {
                        return None;
                    };
                    let ok = m.get("success") == Some(&Value::Bool(true));
                    let Some(Value::Str(msg)) = m.get("message").cloned() else {
                        return None;
                    };
                    // the index loads in the background: wait for it
                    (!msg.contains("loading")).then_some((ok, msg))
                }
            })
            .await
        }
    };

    // from Url, through a redirect
    let (ok, msg) = call(
        "install_url",
        args(&[("name", "u1"), ("url", &url("/moved"))]),
    )
    .await;
    assert!(ok, "{msg}");
    assert_eq!(env.ctl.registry().packages["mockpkg"].version, "1.0.0");
    assert!(env.ctl.registry().packages["mockpkg"]
        .source
        .starts_with("url "));
    // plain http off loopback is refused
    let (ok, msg) = call(
        "install_url",
        args(&[("name", "u2"), ("url", "http://pkg.example/x.zip")]),
    )
    .await;
    assert!(!ok && msg.contains("loopback"), "{msg}");

    // from Repository: the index lists mockpkg 2.0.0 → an upgrade
    let (ok, msg) = call(
        "install_repo",
        args(&[("name", "r1"), ("package", "mockpkg")]),
    )
    .await;
    assert!(ok && msg.contains("1.0.0 → 2.0.0"), "{msg}");
    let (ok, msg) = call(
        "install_repo",
        args(&[("name", "r2"), ("package", "tampered")]),
    )
    .await;
    assert!(!ok && msg.contains("does not match"), "{msg}");
    // this host's asset at a url relative to the index: mockpkg 1.0.0
    // inside, so it takes the place of the 2.0.0 installed above
    let (ok, msg) = call(
        "install_repo",
        args(&[("name", "r3"), ("package", "hosted")]),
    )
    .await;
    assert!(ok, "{msg}");
    let (ok, msg) = call(
        "install_repo",
        args(&[("name", "r4"), ("package", "elsewhere")]),
    )
    .await;
    assert!(!ok && msg.contains("no build for this host"), "{msg}");

    // from Git (file:// in dev): a checkout of a built package
    let repo = temp_dir("pkg-git");
    std::fs::create_dir_all(repo.join("bin")).unwrap();
    let manifest = serde_json::json!({
        "name": "gitpkg",
        "version": "3.0.0",
        "wyrm_link": wyrm_link_sdk::LINK_PROTOCOL,
        "kind": "process",
        "entries": { wyrm_admin::packages::platform(): "bin/run" },
    });
    std::fs::write(
        repo.join(wyrm_admin::packages::MANIFEST),
        manifest.to_string(),
    )
    .unwrap();
    std::fs::write(
        repo.join("bin/run"),
        format!(
            "#!/bin/sh\nexec \"{}\" link mock\n",
            env!("CARGO_BIN_EXE_wyrmd")
        ),
    )
    .unwrap();
    let git = |a: &[&str]| {
        let out = std::process::Command::new("git")
            .arg("-C")
            .arg(&repo)
            .args(a)
            .output()
            .expect("git is installed");
        assert!(
            out.status.success(),
            "git {a:?}: {}",
            String::from_utf8_lossy(&out.stderr)
        );
    };
    git(&["init", "-q", "-b", "main"]);
    git(&["add", "."]);
    git(&[
        "-c",
        "user.name=t",
        "-c",
        "user.email=t@t",
        "commit",
        "-q",
        "-m",
        "pkg",
    ]);
    let file_url = format!("file://{}", repo.display());
    let (ok, msg) = call(
        "install_git",
        args(&[("name", "g1"), ("url", &file_url), ("ref", "main")]),
    )
    .await;
    assert!(ok, "{msg}");
    let p = env.ctl.registry().packages["gitpkg"].clone();
    assert!(p.source.starts_with("git file://"), "{}", p.source);
    let (ok, msg) = call(
        "install_git",
        args(&[
            ("name", "g2"),
            ("url", &file_url),
            ("ref", "--upload-pack=x"),
        ]),
    )
    .await;
    assert!(!ok && msg.contains("ref"), "{msg}");
    env.stop().await;
}

/// "Install Link ▸ from WASM" (ADR 0011, 0012): a component runs as an
/// embedded `wasm` link; its connection's `net` lets it read a TCP device on
/// loopback; a new component for the same name replaces it and keeps the
/// link's devices and points.
#[tokio::test(flavor = "multi_thread")]
async fn wasm_link_reads_a_device_over_tcp() {
    use std::io::{Read, Write};
    // a device answering every request with CBOR uint 42
    let l = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    let port = l.local_addr().unwrap().port();
    std::thread::spawn(move || {
        for s in l.incoming().flatten() {
            std::thread::spawn(move || {
                let mut s = s;
                let mut buf = [0u8; 64];
                while let Ok(n) = s.read(&mut buf) {
                    if n == 0 || s.write_all(&[0x18, 0x2a]).is_err() {
                        return;
                    }
                }
            });
        }
    });
    let env = Env::start("wasmlink", "").await;
    let c = env.client().await;
    let args = |pairs: Vec<(&str, Value)>| {
        Value::Map(pairs.into_iter().map(|(k, v)| (k.to_owned(), v)).collect())
    };
    let ok = |r: Option<Value>| match r {
        Some(Value::Map(m)) => {
            assert_eq!(m.get("success"), Some(&Value::Bool(true)), "{m:?}");
            match m.get("message") {
                Some(Value::Str(s)) => s.clone(),
                _ => String::new(),
            }
        }
        other => panic!("{other:?}"),
    };
    let links = format!("wy/{SITE}/sys/links");
    let install = |wasm: Vec<u8>| {
        args(vec![
            ("name", Value::from("w1")),
            ("wasm", Value::Bytes(wasm)),
        ])
    };
    ok(
        c.invoke_one(&links, "install_wasm", install(guests::tcp_ping()))
            .await
            .unwrap(),
    );
    let reg = env.ctl.registry();
    assert_eq!(reg.packages["w1"].kind.name(), "wasm");
    assert_eq!(reg.links["w1"].driver, "pkg:w1");
    assert_eq!(reg.links["w1"].mode, wyrm_admin::Mode::Embedded);
    assert!(env.ctl.component_store().join("w1.wasm").is_file());

    let main = format!("wy/{SITE}/downstream/w1/main");
    eventually("main declared", 10, || async { c.meta(&main).await.ok() }).await;
    c.invoke_one(
        &main,
        "edit",
        args(vec![
            ("component", Value::from("w1")),
            ("net", Value::from(format!("127.0.0.1:{port}").as_str())),
            ("config", Value::from(port.to_string().as_str())),
        ]),
    )
    .await
    .expect("edit main");
    eventually("main reopened", 10, || async {
        c.invoke_one(&main, "add_device", args(vec![("name", Value::from("d1"))]))
            .await
            .ok()
    })
    .await;
    c.invoke_one(
        &format!("{main}/d1"),
        "add_point",
        args(vec![
            ("name", Value::from("p")),
            ("poll_s", Value::Float(0.1)),
        ]),
    )
    .await
    .expect("add point");
    let p = format!("{main}/d1/p");
    eventually("p = 42 from the device", 10, || async {
        (last_val(&c, &p).await == Some(Value::UInt(42))).then_some(())
    })
    .await;

    // another component for the same name: the link restarts on it and
    // keeps its device and point (`register` answers 7 without a network)
    let msg = ok(c
        .invoke_one(&links, "install_wasm", install(guests::register()))
        .await
        .unwrap());
    assert!(msg.contains("→"), "{msg}");
    eventually("p = 7 from the new component", 10, || async {
        let c = env.client().await;
        (last_val(&c, &p).await == Some(Value::UInt(7))).then_some(())
    })
    .await;
    // a number point (the default type): written, then read back
    let meta = c.meta(&p).await.unwrap();
    assert_eq!(meta.ty, Some(wyrm_core::TypeCode::Number));
    c.invoke_one(
        &format!("{main}/d1/p"),
        "edit",
        args(vec![("writable", Value::Bool(true))]),
    )
    .await
    .expect("make p writable");
    eventually("p = 9 after set", 10, || async {
        c.set(&p, Value::UInt(9)).await.ok()?;
        (last_val(&c, &p).await == Some(Value::UInt(9))).then_some(())
    })
    .await;
    env.stop().await;
}

/// The `Echo` app of `links/wasm/tests/app_fixture` built for wasm32 and made a component, as
/// `wyr link pack` does for `kind = "wasm"`; `None` without the wasm32 target.
fn echo_app_component() -> Option<Vec<u8>> {
    echo_app_component_with("")
}

/// The fixture app with cargo `features` (`v2`: the "new code", which also declares `v2`).
fn echo_app_component_with(features: &str) -> Option<Vec<u8>> {
    use std::process::Command;
    let libdir = Command::new("rustc")
        .args([
            "--print",
            "target-libdir",
            "--target",
            "wasm32-unknown-unknown",
        ])
        .output()
        .ok()
        .filter(|o| o.status.success())
        .map(|o| PathBuf::from(String::from_utf8_lossy(&o.stdout).trim()));
    if !libdir.is_some_and(|d| d.exists()) {
        return None;
    }
    let repo = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let fixture = repo.join("links/wasm/tests/app_fixture");
    // its own workspace: seed the lock file from the main one (same versions)
    std::fs::copy(repo.join("Cargo.lock"), fixture.join("Cargo.lock")).expect("copy Cargo.lock");
    let target = std::path::Path::new(env!("CARGO_TARGET_TMPDIR"))
        .join(format!(
            "app-fixture{}",
            if features.is_empty() { "" } else { "-" }
        ))
        .join(features);
    let out = Command::new(env!("CARGO"))
        .args([
            "build",
            "--release",
            "--target",
            "wasm32-unknown-unknown",
            "--features",
            features,
            "--manifest-path",
        ])
        .arg(fixture.join("Cargo.toml"))
        .arg("--target-dir")
        .arg(&target)
        .env_remove("RUSTFLAGS")
        .env_remove("CARGO_ENCODED_RUSTFLAGS")
        .output()
        .expect("run cargo");
    assert!(
        out.status.success(),
        "fixture build failed:\n{}",
        String::from_utf8_lossy(&out.stderr)
    );
    let core = std::fs::read(
        target.join("wasm32-unknown-unknown/release/wyrm_link_wasm_app_fixture.wasm"),
    )
    .expect("fixture wasm");
    Some(
        wit_component::ComponentEncoder::default()
            .module(&core)
            .expect("component type")
            .validate(true)
            .encode()
            .expect("componentize"),
    )
}

/// A portable link packed as a WASM package (ADR 0023): installed from Zip it
/// runs as an app with its capabilities, answers its action, and an upgrade
/// (a new version) restarts it on the same store.
#[tokio::test(flavor = "multi_thread")]
async fn portable_app_installs_as_wasm() {
    use wyrm_link_sdk::package::{self, Capabilities, Manifest, PackFile};
    let Some(component) = echo_app_component() else {
        eprintln!(
            "SKIP portable_app_installs_as_wasm: target wasm32-unknown-unknown is not installed \
             (rustup target add wasm32-unknown-unknown)"
        );
        return;
    };
    let zip = |version: &str, world: &str| {
        let m = Manifest {
            name: "echoapp".into(),
            version: version.into(),
            description: "the echo app".into(),
            wyrm_link: wyrm_link_sdk::LINK_PROTOCOL,
            kind: "wasm".into(),
            entries: Default::default(),
            args: Vec::new(),
            entry: Some("echoapp.wasm".into()),
            requester: Vec::new(),
            world: Some(world.into()),
            capabilities: (world == "app").then(|| Capabilities {
                store_mb: Some(2),
                ..Capabilities::default()
            }),
        };
        let files = [PackFile {
            path: "echoapp.wasm".into(),
            data: component.clone(),
            mode: 0o644,
        }];
        package::pack(&m, &files).unwrap()
    };
    let env = Env::start("appwasm", "").await;
    let c = env.client().await.with_timeout(Duration::from_secs(60));
    let links = format!("wy/{SITE}/sys/links");
    let install = |zip: Vec<u8>| {
        Value::Map(BTreeMap::from([
            ("name".to_owned(), Value::from("e1")),
            ("zip".to_owned(), Value::Bytes(zip)),
        ]))
    };
    let outcome = |v: Option<Value>| -> (bool, String) {
        let Some(Value::Map(m)) = v else {
            panic!("result map: {v:?}")
        };
        let msg = match m.get("message") {
            Some(Value::Str(s)) => s.clone(),
            other => panic!("message: {other:?}"),
        };
        (m.get("success") == Some(&Value::Bool(true)), msg)
    };

    // a manifest that says another world than the component's is refused
    let (ok, msg) = outcome(
        c.invoke_one(&links, "install_zip", install(zip("1.0.0", "driver")))
            .await
            .unwrap(),
    );
    assert!(
        !ok && msg.contains(r#""driver""#) && msg.contains(r#""app""#),
        "{msg}"
    );

    let t = std::time::Instant::now();
    let (ok, msg) = outcome(
        c.invoke_one(&links, "install_zip", install(zip("1.0.0", "app")))
            .await
            .unwrap(),
    );
    eprintln!("install_zip of the app took {:?}", t.elapsed());
    assert!(ok, "{msg}");
    assert!(
        msg.contains("capabilities net none, store 2 MiB, memory 64 MiB, call 2000 ms"),
        "{msg}"
    );
    let reg = env.ctl.registry();
    assert_eq!(reg.links["e1"].driver, "pkg:echoapp");
    assert_eq!(reg.links["e1"].mode, wyrm_admin::Mode::Embedded);
    assert_eq!(reg.packages["echoapp"].kind.name(), "wasm");

    let root = format!("wy/{SITE}/downstream/e1");
    let pong = eventually("ping answers pong", 20, || async {
        c.invoke_one(&root, "ping", Value::Map(BTreeMap::new()))
            .await
            .ok()
    })
    .await;
    assert_eq!(pong, Some(Value::Str("pong".into())));
    c.set(&format!("{root}/n"), Value::UInt(5)).await.unwrap();
    let starts = format!("{root}/starts");
    eventually("first start", 10, || async {
        (last_val(&c, &starts).await == Some(Value::Float(1.0))).then_some(())
    })
    .await;

    // an upgrade restarts the link on the new version; its store is kept: `n` comes back from
    // it, `starts` counts two starts and `stopped` the old instance's stop
    let (ok, msg) = outcome(
        c.invoke_one(&links, "install_zip", install(zip("1.0.1", "app")))
            .await
            .unwrap(),
    );
    assert!(ok && msg.contains("1.0.0 → 1.0.1"), "{msg}");
    eventually("second start on the kept store", 20, || async {
        (last_val(&c, &starts).await == Some(Value::Float(2.0))).then_some(())
    })
    .await;
    assert_eq!(
        last_val(&c, &format!("{root}/stopped")).await,
        Some(Value::Float(1.0))
    );
    assert_eq!(
        last_val(&c, &format!("{root}/n")).await,
        Some(Value::UInt(5))
    );
    let pong = c
        .invoke_one(&root, "ping", Value::Map(BTreeMap::new()))
        .await
        .unwrap();
    assert_eq!(pong, Some(Value::Str("pong".into())));
    env.stop().await;
}

/// A `wasm` package `name` of the app fixture, world `app`, with `capabilities`.
fn echo_app_zip(
    name: &str,
    version: &str,
    component: &[u8],
    capabilities: wyrm_link_sdk::package::Capabilities,
) -> Vec<u8> {
    use wyrm_link_sdk::package::{self, Manifest, PackFile};
    let entry = format!("{name}.wasm");
    let m = Manifest {
        name: name.into(),
        version: version.into(),
        description: "the echo app".into(),
        wyrm_link: wyrm_link_sdk::LINK_PROTOCOL,
        kind: "wasm".into(),
        entries: Default::default(),
        args: Vec::new(),
        entry: Some(entry.clone()),
        requester: Vec::new(),
        world: Some("app".into()),
        capabilities: Some(capabilities),
    };
    let files = [PackFile {
        path: entry,
        data: component.to_vec(),
        mode: 0o644,
    }];
    package::pack(&m, &files).unwrap()
}

/// `install_zip {name, zip}` and its `(success, message)`.
async fn install_zip(c: &WyrmClient, name: &str, zip: Vec<u8>) -> (bool, String) {
    let args = Value::Map(BTreeMap::from([
        ("name".to_owned(), Value::from(name)),
        ("zip".to_owned(), Value::Bytes(zip)),
    ]));
    let t = std::time::Instant::now();
    let v = c
        .invoke_one(&format!("wy/{SITE}/sys/links"), "install_zip", args)
        .await
        .unwrap();
    eprintln!("install_zip {name} took {:?}", t.elapsed());
    let Some(Value::Map(m)) = v else {
        panic!("result map: {v:?}")
    };
    let msg = match m.get("message") {
        Some(Value::Str(s)) => s.clone(),
        other => panic!("message: {other:?}"),
    };
    (m.get("success") == Some(&Value::Bool(true)), msg)
}

fn status_of(e: &wyrm_client::ClientError) -> Option<wyrm_core::Status> {
    match e.status {
        wyrm_core::status::StatusCode::Known(s) => Some(s),
        _ => None,
    }
}

/// I1: `update` and `rollback` of an app package link (`pkg:<name>`) are checked by the driver
/// it runs on (`app`) and take effect: `store_mb: 0` refuses the store write of `set n`, the
/// rollback gives the store back; params the `app` driver refuses are refused.
#[tokio::test(flavor = "multi_thread")]
async fn portable_app_update_and_rollback() {
    use wyrm_link_sdk::package::Capabilities;
    let Some(component) = echo_app_component() else {
        eprintln!("SKIP portable_app_update_and_rollback: no wasm32-unknown-unknown target");
        return;
    };
    let env = Env::start("appupd", "").await;
    let c = env.client().await.with_timeout(Duration::from_secs(60));
    let caps = Capabilities {
        store_mb: Some(1),
        ..Capabilities::default()
    };
    let (ok, msg) = install_zip(&c, "u1", echo_app_zip("echoupd", "1.0.0", &component, caps)).await;
    assert!(ok, "{msg}");
    let root = format!("wy/{SITE}/downstream/u1");
    let node = format!("wy/{SITE}/sys/links/u1");
    let set_n = |v: u64| {
        let c = &c;
        let key = format!("{root}/n");
        async move { c.set(&key, Value::UInt(v)).await }
    };
    eventually("set n on the first start", 20, || async {
        set_n(5).await.ok()
    })
    .await;
    let params = |store_mb: Value| {
        Value::Map(BTreeMap::from([(
            "params".to_owned(),
            Value::Map(BTreeMap::from([
                ("net".to_owned(), Value::from("")),
                ("store_mb".to_owned(), store_mb),
                ("call_ms".to_owned(), Value::UInt(2000)),
            ])),
        )]))
    };

    // the `app` driver checks the params: over the bound, or another package's component
    let err = c
        .invoke_one(&node, "update", params(Value::UInt(65)))
        .await
        .unwrap_err();
    assert_eq!(
        status_of(&err),
        Some(wyrm_core::Status::InvalidParameter),
        "{err}"
    );
    let mut other = params(Value::UInt(1));
    if let Value::Map(m) = &mut other {
        if let Some(Value::Map(p)) = m.get_mut("params") {
            p.insert("component".into(), Value::from("someone-else"));
        }
    }
    let err = c.invoke_one(&node, "update", other).await.unwrap_err();
    assert_eq!(
        status_of(&err),
        Some(wyrm_core::Status::InvalidParameter),
        "{err}"
    );

    // store_mb 0: the restarted link refuses the store write
    let rev = c
        .invoke_one(&node, "update", params(Value::UInt(0)))
        .await
        .unwrap();
    assert_eq!(rev, Some(Value::UInt(2)));
    let refused = eventually("set n refused by the empty store", 20, || async {
        match set_n(6).await {
            Err(e) if status_of(&e) == Some(wyrm_core::Status::ResourceExhausted) => Some(e),
            _ => None,
        }
    })
    .await;
    assert!(refused.to_string().contains("store"), "{refused}");

    // rollback to rev 1: the store takes writes again, and kept `n`
    let rev = c
        .invoke_one(
            &node,
            "rollback",
            Value::Map(BTreeMap::from([("rev".to_owned(), Value::UInt(1))])),
        )
        .await
        .unwrap();
    assert_eq!(rev, Some(Value::UInt(3)));
    eventually("n from the store after the rollback", 20, || async {
        (last_val(&c, &format!("{root}/n")).await == Some(Value::UInt(5))).then_some(())
    })
    .await;
    eventually("set n after the rollback", 20, || async {
        set_n(7).await.ok()
    })
    .await;
    env.stop().await;
}

/// M1: an upgrade of an app package is a hot start (ADR 0023): the link's code is swapped in
/// place, the link is never removed (its liveliness token stays), the old instance's `stop`
/// runs, the store carries over and the new code answers (it declares `v2`).
#[tokio::test(flavor = "multi_thread")]
async fn portable_app_upgrade_is_a_hot_start() {
    use wyrm_link_sdk::package::Capabilities;
    let (Some(v1), Some(v2)) = (echo_app_component(), echo_app_component_with("v2")) else {
        eprintln!("SKIP portable_app_upgrade_is_a_hot_start: no wasm32-unknown-unknown target");
        return;
    };
    let env = Env::start("apphot", "").await;
    let c = env.client().await.with_timeout(Duration::from_secs(10));
    let caps = Capabilities::default;
    let (ok, msg) = install_zip(&c, "h1", echo_app_zip("echohot", "1.0.0", &v1, caps())).await;
    assert!(ok, "{msg}");
    let root = format!("wy/{SITE}/downstream/h1");
    let ping = || {
        let c = &c;
        let root = root.clone();
        async move {
            c.invoke_one(&root, "ping", Value::Map(BTreeMap::new()))
                .await
                .ok()
                .flatten()
        }
    };
    assert_eq!(
        eventually("ping on v1", 20, || async { ping().await }).await,
        Value::Str("pong".into())
    );
    c.set(&format!("{root}/n"), Value::UInt(5)).await.unwrap();
    let starts = format!("{root}/starts");
    eventually("first start", 10, || async {
        (last_val(&c, &starts).await == Some(Value::Float(1.0))).then_some(())
    })
    .await;
    assert!(!c
        .children(&root)
        .await
        .unwrap()
        .iter()
        .any(|ch| ch.name == "v2"));

    // the link's presence, watched across the upgrade
    let s = env.session().await;
    let presence = s
        .liveliness()
        .declare_subscriber(root.as_str())
        .await
        .unwrap();
    let (ok, msg) = install_zip(&c, "h1", echo_app_zip("echohot", "1.0.1", &v2, caps())).await;
    assert!(ok && msg.contains("1.0.0 → 1.0.1"), "{msg}");
    assert!(!msg.contains("not restarted"), "{msg}");
    eventually("the new code declares v2", 20, || async {
        c.children(&root)
            .await
            .ok()?
            .iter()
            .any(|ch| ch.name == "v2")
            .then_some(())
    })
    .await;
    eventually("second start on the kept store", 20, || async {
        (last_val(&c, &starts).await == Some(Value::Float(2.0))).then_some(())
    })
    .await;
    assert_eq!(
        last_val(&c, &format!("{root}/stopped")).await,
        Some(Value::Float(1.0))
    );
    assert_eq!(
        last_val(&c, &format!("{root}/n")).await,
        Some(Value::UInt(5))
    );
    assert_eq!(ping().await, Some(Value::Str("pong".into())));
    // never removed: no liveliness delete for the link
    while let Ok(Some(sample)) = presence.try_recv() {
        assert_ne!(
            sample.kind(),
            zenoh::sample::SampleKind::Delete,
            "the link went away during the upgrade"
        );
    }
    let audit = env.ctl.audit_tail(50);
    assert!(
        audit.iter().any(|r| r.op == "hot_start" && r.key == "h1"),
        "{audit:?}"
    );
    assert!(
        !audit.iter().any(|r| r.op == "stop" && r.key == "h1"),
        "{audit:?}"
    );
    // the install record names what the links may use (M6)
    assert!(
        audit.iter().any(|r| r.op == "package_install"
            && r.key == "echohot"
            && r.detail.contains("capabilities net none, store 1 MiB")),
        "{audit:?}"
    );
    env.stop().await;
}

/// I1 (round 2): a process package's capabilities reach its link: with `store_mb: 0` the
/// portable app's `set n` is refused (`resource_exhausted`); an `update` to `store_mb: 1` (not
/// checked by the broker: the binary parses it) lets it write, a `rollback` refuses it again.
#[tokio::test(flavor = "multi_thread")]
async fn process_app_capabilities_reach_the_link() {
    let env = Env::start("proccaps", "").await;
    let links = format!("wy/{SITE}/sys/links");
    let zip = driver_package_with(
        "portable-echo-caps",
        "1.0.0",
        "the portable example as a process, no store",
        "portable-echo",
        Some(serde_json::json!({ "store_mb": 0 })),
    );
    let r = invoke_retry(
        &env,
        &links,
        "install_zip",
        Value::Map(BTreeMap::from([
            ("name".to_owned(), Value::from("q0")),
            ("zip".to_owned(), Value::Bytes(zip)),
        ])),
    )
    .await;
    assert!(
        matches!(&r, Some(Value::Map(m)) if m.get("success") == Some(&Value::Bool(true))),
        "{r:?}"
    );
    let n = format!("wy/{SITE}/downstream/q0/n");
    // `Ok(status)` of one `set n`; `None` while the link or the router is not there
    let set = |v: u64| {
        let (env, n) = (&env, n.clone());
        async move {
            let c = client_now(env).await?;
            match c.set(&n, Value::UInt(v)).await {
                Ok(()) => Some(wyrm_core::Status::Ok),
                Err(e) => match status_of(&e) {
                    Some(s @ wyrm_core::Status::ResourceExhausted) => Some(s),
                    _ => None,
                },
            }
        }
    };
    let refused =
        || async { (set(5).await? == wyrm_core::Status::ResourceExhausted).then_some(()) };
    let taken = || async { (set(6).await? == wyrm_core::Status::Ok).then_some(()) };
    eventually("set n refused: store_mb 0 from the manifest", 30, refused).await;

    let node = format!("{links}/q0");
    let params = Value::Map(BTreeMap::from([(
        "params".to_owned(),
        Value::Map(BTreeMap::from([("store_mb".to_owned(), Value::UInt(1))])),
    )]));
    assert_eq!(
        invoke_retry(&env, &node, "update", params).await,
        Some(Value::UInt(2))
    );
    eventually("set n taken after update store_mb 1", 30, taken).await;
    let rollback = Value::Map(BTreeMap::from([("rev".to_owned(), Value::UInt(1))]));
    assert_eq!(
        invoke_retry(&env, &node, "rollback", rollback).await,
        Some(Value::UInt(3))
    );
    eventually("set n refused again after the rollback", 30, refused).await;
    env.stop().await;
}

/// The portable app of workspace package `package` (`wyrm-example-portable`,
/// `wyrm-link-scheduler`) for wasm32 with feature `wasm`, made a component, as `wyr link pack`
/// builds it; `None` without the wasm32 target.
fn portable_component(package: &str) -> Option<Vec<u8>> {
    use std::process::Command;
    let libdir = Command::new("rustc")
        .args([
            "--print",
            "target-libdir",
            "--target",
            "wasm32-unknown-unknown",
        ])
        .output()
        .ok()
        .filter(|o| o.status.success())
        .map(|o| PathBuf::from(String::from_utf8_lossy(&o.stdout).trim()));
    if !libdir.is_some_and(|d| d.exists()) {
        return None;
    }
    let repo = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let target = std::path::Path::new(env!("CARGO_TARGET_TMPDIR")).join(package);
    // a workspace member: the workspace's lock file and release profile
    let out = Command::new(env!("CARGO"))
        .args(["build", "--release", "--lib", "-p", package])
        .args(["--target", "wasm32-unknown-unknown", "--features", "wasm"])
        .arg("--manifest-path")
        .arg(repo.join("Cargo.toml"))
        .arg("--target-dir")
        .arg(&target)
        .env_remove("RUSTFLAGS")
        .env_remove("CARGO_ENCODED_RUSTFLAGS")
        .output()
        .expect("run cargo");
    assert!(
        out.status.success(),
        "{package} build failed:\n{}",
        String::from_utf8_lossy(&out.stderr)
    );
    let core = std::fs::read(target.join(format!(
        "wasm32-unknown-unknown/release/{}.wasm",
        package.replace('-', "_")
    )))
    .expect("component core wasm");
    Some(
        wit_component::ComponentEncoder::default()
            .module(&core)
            .expect("component type")
            .validate(true)
            .encode()
            .expect("componentize"),
    )
}

/// A client on a new session; `None` while the router is rebuilt.
async fn client_now(env: &Env) -> Option<WyrmClient> {
    let s = env.try_session().await?;
    let key = ed25519_dalek::SigningKey::from_bytes(&SEED);
    Some(
        WyrmClient::new(s)
            .with_tokens(Arc::new(SigningTokens::new(key, SITE)))
            .with_timeout(Duration::from_secs(5)),
    )
}

/// `invoke_one` retried on new sessions until it answers (installs rebuild the router).
async fn invoke_retry(env: &Env, key: &str, action: &str, args: Value) -> Option<Value> {
    eventually(&format!("{action} on {key}"), 40, || {
        let args = args.clone();
        async move {
            let c = client_now(env).await?;
            c.invoke_one(key, action, args).await.ok()
        }
    })
    .await
}

/// The last sample of `node` (on a new session each try).
async fn last_sample(env: &Env, node: &str) -> Option<wyrm_core::Sample> {
    let c = client_now(env).await?;
    let r = c.session().get(format!("{node}/~val")).await.ok()?;
    let reply = r.recv_async().await.ok()?;
    let s = reply.result().ok()?;
    wyrm_core::codec::from_slice(&s.payload().to_bytes()).ok()
}

/// What one mode of the portable example shows in the scenario of `one_app_three_modes`.
#[derive(Debug, PartialEq)]
struct EchoRun {
    pong: Option<Value>,
    echo: Option<Value>,
    n: Value,
    ticks: Value,
    /// `starts` after the link's restart minus before it: the store kept the count.
    starts_added: f64,
    /// `n` published again by the new instance (a good sample newer than the restart).
    n_after: Value,
}

/// `set n`, `invoke ping` and `echo`, `ticks` after the timer, then `sys/links/<id>` stop and
/// start and `n` from the store.
async fn echo_scenario(env: &Env, id: &str) -> EchoRun {
    let root = format!("wy/{SITE}/downstream/{id}");
    let pong = invoke_retry(env, &root, "ping", Value::Map(BTreeMap::new())).await;
    let echo = invoke_retry(
        env,
        &root,
        "echo",
        Value::Map(BTreeMap::from([("value".to_owned(), Value::UInt(7))])),
    )
    .await;
    let n_node = format!("{root}/n");
    eventually(&format!("set {n_node}"), 20, || async {
        client_now(env)
            .await?
            .set(&n_node, Value::UInt(5))
            .await
            .ok()
    })
    .await;
    let n = eventually(&format!("{id}: n"), 10, || async {
        last_sample(env, &n_node).await
    })
    .await;
    let ticks_node = format!("{root}/ticks");
    let ticks = eventually(&format!("{id}: ticks after the ping timer"), 10, || async {
        last_sample(env, &ticks_node).await
    })
    .await;
    let starts_node = format!("{root}/starts");
    let before = eventually(&format!("{id}: starts"), 10, || async {
        last_sample(env, &starts_node).await?.v.as_f64()
    })
    .await;

    let link = format!("wy/{SITE}/sys/links/{id}");
    let restarted = wyrm_link_sdk::now_us();
    invoke_retry(env, &link, "stop", Value::Map(BTreeMap::new())).await;
    invoke_retry(env, &link, "start", Value::Map(BTreeMap::new())).await;
    let after = eventually(&format!("{id} starts again"), 30, || async {
        let s = last_sample(env, &starts_node).await?;
        (s.t > restarted && s.q == wyrm_core::Quality::Good)
            .then(|| s.v.as_f64())
            .flatten()
    })
    .await;
    let n_after = eventually(&format!("{id}: n from the store"), 10, || async {
        let s = last_sample(env, &n_node).await?;
        (s.t > restarted && s.q == wyrm_core::Quality::Good).then_some(s.v)
    })
    .await;
    EchoRun {
        pong,
        echo,
        n: n.v,
        ticks: ticks.v,
        starts_added: after - before,
        n_after,
    }
}

/// ADR 0023: one app (`examples/links/portable`), three modes — embedded (driver
/// `portable-echo`), a process package (its entry runs `Portable<Echo>` as `wyrmd link
/// portable-echo`) and a WASM package (the crate built for wasm32) — answer the same scenario
/// with the same results.
#[tokio::test(flavor = "multi_thread")]
async fn one_app_three_modes() {
    use wyrm_link_sdk::package::{self, Capabilities, Manifest, PackFile};
    let env = Env::start(
        "threemodes",
        r#"links: { pe: { driver: "portable-echo" } },"#,
    )
    .await;
    let links = format!("wy/{SITE}/sys/links");
    let install = |name: &str, zip: Vec<u8>| {
        Value::Map(BTreeMap::from([
            ("name".to_owned(), Value::from(name)),
            ("zip".to_owned(), Value::Bytes(zip)),
        ]))
    };
    let ok = |v: Option<Value>| {
        let Some(Value::Map(m)) = &v else {
            panic!("result map: {v:?}")
        };
        assert_eq!(m.get("success"), Some(&Value::Bool(true)), "{v:?}");
    };

    // the WASM package: an embedded link, no router rebuild
    let mut ids = vec!["pe"];
    match portable_component("wyrm-example-portable") {
        Some(component) => {
            let m = Manifest {
                name: "portable-echo".into(),
                version: "1.0.0".into(),
                description: "the portable example as a component".into(),
                wyrm_link: wyrm_link_sdk::LINK_PROTOCOL,
                kind: "wasm".into(),
                entries: Default::default(),
                args: Vec::new(),
                entry: Some("portable-echo.wasm".into()),
                requester: Vec::new(),
                world: Some("app".into()),
                capabilities: Some(Capabilities {
                    store_mb: Some(1),
                    ..Capabilities::default()
                }),
            };
            let files = [PackFile {
                path: "portable-echo.wasm".into(),
                data: component,
                mode: 0o644,
            }];
            let zip = package::pack(&m, &files).unwrap();
            ok(invoke_retry(&env, &links, "install_zip", install("pw", zip)).await);
            ids.push("pw");
        }
        None => eprintln!(
            "SKIP one_app_three_modes (WASM mode): target wasm32-unknown-unknown is not \
             installed (rustup target add wasm32-unknown-unknown)"
        ),
    }
    // the process package last: its install rebuilds the router (which restarts the embedded
    // links); the process link answers only through the new router, so once it does, the
    // broker has settled
    // with the same capabilities as its WASM twin: they become its params (I1)
    let zip = driver_package_with(
        "portable-echo-process",
        "1.0.0",
        "the portable example as a process",
        "portable-echo",
        Some(serde_json::json!({ "store_mb": 1 })),
    );
    let r = invoke_retry(&env, &links, "install_zip", install("pp", zip)).await;
    assert!(
        matches!(&r, Some(Value::Map(m)) if matches!(m.get("message"),
            Some(Value::Str(s)) if s.contains("capabilities net none, store 1 MiB"))),
        "{r:?}"
    );
    ok(r);
    ids.push("pp");
    invoke_retry(
        &env,
        &format!("wy/{SITE}/downstream/pp"),
        "echo",
        Value::Map(BTreeMap::new()),
    )
    .await;
    let reg = env.ctl.registry();
    assert_eq!(reg.links["pe"].driver, "portable-echo");
    assert_eq!(reg.links["pp"].mode, wyrm_admin::Mode::Process);
    if ids.contains(&"pw") {
        assert_eq!(reg.links["pw"].driver, "pkg:portable-echo");
        assert_eq!(reg.links["pw"].mode, wyrm_admin::Mode::Embedded);
    }

    let want = EchoRun {
        pong: Some(Value::Str("pong".into())),
        echo: Some(Value::UInt(7)),
        n: Value::UInt(5),
        ticks: Value::UInt(1),
        starts_added: 1.0,
        n_after: Value::UInt(5),
    };
    for id in ids {
        assert_eq!(echo_scenario(&env, id).await, want, "mode of {id}");
    }
    env.stop().await;
}

/// Logs in sys (owner request 2026-10-22): the broker's ring and level, an
/// embedded link's lines by its span and its own level, a process link's
/// output and its RUST_LOG (applied by a restart).
#[tokio::test(flavor = "multi_thread")]
async fn logs_and_log_levels() {
    let lc = wyrm_admin::logs::install_quiet();
    let env = Env::start(
        "logs",
        r#"links: {
            logmock: { driver: "mock", params: { points: 2, rate_hz: 1, depth: 1, fanout: 1 } },
            pm: { driver: "mock", mode: "process", params: { points: 2, rate_hz: 1, depth: 1, fanout: 1 } },
        },"#,
    )
    .await;
    // The broker at debug makes every test in this process log more: give
    // its own requests room.
    let c = env.client().await.with_timeout(Duration::from_secs(10));
    let sys = format!("wy/{SITE}/sys");
    let args = |pairs: Vec<(&str, Value)>| {
        Value::Map(pairs.into_iter().map(|(k, v)| (k.to_owned(), v)).collect())
    };
    let rows = |v: Option<Value>| -> Vec<BTreeMap<String, Value>> {
        match v {
            Some(Value::Array(a)) => a
                .into_iter()
                .filter_map(|r| match r {
                    Value::Map(m) => Some(m),
                    _ => None,
                })
                .collect(),
            other => panic!("rows: {other:?}"),
        }
    };
    let text = |m: &BTreeMap<String, Value>, k: &str| match m.get(k) {
        Some(Value::Str(s)) => s.clone(),
        _ => String::new(),
    };

    // the broker: level debug, saved; its log has the admin's lines
    c.set(&format!("{sys}/log_level"), Value::UInt(3))
        .await
        .unwrap();
    assert_eq!(lc.level(), "debug");
    assert_eq!(env.ctl.registry().log_level.as_deref(), Some("debug"));
    let all = rows(
        c.invoke_one(&sys, "get_log", args(vec![("lines", Value::UInt(2000))]))
            .await
            .unwrap(),
    );
    assert!(
        all.iter()
            .any(|r| text(r, "message").contains("admin attached")),
        "{all:?}"
    );
    assert!(all
        .iter()
        .all(|r| !text(r, "time").is_empty() && !text(r, "level").is_empty()));
    let warns = rows(
        c.invoke_one(&sys, "get_log", args(vec![("level", Value::from("warn"))]))
            .await
            .unwrap(),
    );
    assert!(warns
        .iter()
        .all(|r| ["warn", "error"].contains(&text(r, "level").as_str())));

    // an embedded link: back to info for the broker, debug for `logmock` alone;
    // a refused token (debug, inside the link's span) shows under its id. Link
    // levels are process-wide and keyed by link id, and every broker start in
    // this process sets the levels of its own embedded links: an id no other
    // test uses keeps this one from being reset by another test's `mock`.
    c.set(&format!("{sys}/log_level"), Value::UInt(2))
        .await
        .unwrap();
    // choices: default, error, warn, info, debug, trace (an enum takes its index)
    c.set(&format!("{sys}/links/logmock/log_level"), Value::UInt(4))
        .await
        .unwrap();
    assert_eq!(
        env.ctl.registry().links["logmock"].log_level.as_deref(),
        Some("debug")
    );
    let stranger = WyrmClient::new(env.session().await)
        .with_tokens(Arc::new(SigningTokens::new(
            ed25519_dalek::SigningKey::from_bytes(&[7; 32]),
            SITE,
        )))
        .with_timeout(Duration::from_secs(3));
    // The log ring is shared by the whole test process and keeps the last
    // lines only: refuse one set per try, so the line is fresh when it is read.
    let mine = eventually("the link's debug line", 10, || async {
        let _ = stranger
            .set(&format!("wy/{SITE}/downstream/logmock/g0/p0"), 1.0)
            .await;
        let r = rows(
            c.invoke_one(&format!("{sys}/links/logmock"), "get_log", args(vec![]))
                .await
                .ok()?,
        );
        r.iter()
            .any(|r| text(r, "message").contains("ptok rejected"))
            .then_some(r)
    })
    .await;
    assert!(mine.iter().all(|r| text(r, "link") == "logmock"));

    // a process link: its output, and RUST_LOG from its level
    eventually("process output", 15, || async {
        let r = rows(
            c.invoke_one(&format!("{sys}/links/pm"), "get_log", args(vec![]))
                .await
                .ok()?,
        );
        r.iter()
            .any(|r| text(r, "message").contains("link process up"))
            .then_some(())
    })
    .await;
    c.set(&format!("{sys}/links/pm/log_level"), Value::UInt(2))
        .await
        .unwrap();
    assert_eq!(
        env.ctl.registry().links["pm"].log_level.as_deref(),
        Some("warn")
    );
    assert!(env
        .ctl
        .audit_tail(50)
        .iter()
        .any(|r| r.op == "log_level" && r.key == "pm"));
    env.stop().await;
}

/// The `secrets` map of a `hello` reply; `None` when no reply came (the
/// session met a router that a rebuild was closing).
async fn hello_secrets(
    s: &zenoh::Session,
    id: &str,
    token: &str,
) -> Option<BTreeMap<String, Value>> {
    let mut args = BTreeMap::new();
    args.insert("token".to_owned(), Value::Bytes(token.as_bytes().to_vec()));
    let r = s
        .get(format!("wy/{SITE}/sys/links/{id}/~act/hello"))
        .payload(wyrm_core::codec::to_vec(&Value::Map(args)).unwrap())
        .timeout(Duration::from_secs(5))
        .await
        .unwrap();
    let reply = r.recv_async().await.ok()?;
    let v: Value =
        wyrm_core::codec::from_slice(&reply.result().unwrap().payload().to_bytes()).unwrap();
    match v {
        Value::Map(mut m) => match m.remove("secrets") {
            Some(Value::Map(s)) => Some(s),
            other => panic!("secrets: {other:?}"),
        },
        other => panic!("hello: {other:?}"),
    }
}

/// The `grants` of a `hello` reply as `(path, perm code)`.
async fn hello_grants(s: &zenoh::Session, id: &str, token: &str) -> Option<Vec<(String, u64)>> {
    let mut args = BTreeMap::new();
    args.insert("token".to_owned(), Value::Bytes(token.as_bytes().to_vec()));
    let r = s
        .get(format!("wy/{SITE}/sys/links/{id}/~act/hello"))
        .payload(wyrm_core::codec::to_vec(&Value::Map(args)).unwrap())
        .timeout(Duration::from_secs(5))
        .await
        .unwrap();
    let reply = r.recv_async().await.ok()?;
    let v: Value =
        wyrm_core::codec::from_slice(&reply.result().unwrap().payload().to_bytes()).unwrap();
    let Value::Map(mut m) = v else { return None };
    let Some(Value::Array(rows)) = m.remove("grants") else {
        return None;
    };
    rows.into_iter()
        .map(|r| match r {
            Value::Array(g) => match (&g[0], g[1].as_f64()) {
                (Value::Str(p), Some(c)) => Some((p.clone(), c as u64)),
                _ => None,
            },
            _ => None,
        })
        .collect()
}

/// A link as a requester (DSA `isRequester`, owner decision 2026-10-22):
/// grants open the ACL to other branches and make every link trust its
/// requester key up to the grant's level and under the grant's path.
#[tokio::test(flavor = "multi_thread")]
async fn link_grants_make_a_requester() {
    let env = Env::start(
        "requester",
        &format!(r#"{MOCK} links: {{ rec: {{ driver: "x", mode: "external" }} }},"#)
            .replace("}, links: {", ","),
    )
    .await;
    let token = std::fs::read_to_string(env.ctl.config().data_dir.join("links/rec/token")).unwrap();
    let mock = format!("wy/{SITE}/downstream/mock");
    let sys = format!("wy/{SITE}/sys/links/rec");
    let grant = |level: &str| {
        Value::Map(BTreeMap::from([
            ("path".to_owned(), Value::from("wy/{site}/downstream/mock")),
            ("level".to_owned(), Value::from(level)),
        ]))
    };
    // as link `rec`: tokens signed with its requester key
    let as_rec = |key: Option<ed25519_dalek::SigningKey>| {
        let env = &env;
        async move {
            let s = env.tls_session("rec").await;
            let c = WyrmClient::new(s).with_timeout(Duration::from_secs(2));
            match key {
                Some(k) => c.with_tokens(Arc::new(
                    SigningTokens::new(k, SITE).subject("link:rec".to_owned()),
                )),
                None => c,
            }
        }
    };
    let rec = as_rec(None).await;
    assert!(rec.meta(&mock).await.is_err(), "no grant: the ACL drops it");

    env.client()
        .await
        .invoke_one(&sys, "grant", grant("read"))
        .await
        .unwrap();
    assert_eq!(env.ctl.registry().links["rec"].grants.len(), 1);
    let key = eventually("read after the rebuild", 15, || async {
        let s = env.tls_session("rec").await;
        let secrets = hello_secrets(&s, "rec", &token).await?;
        let Some(Value::Bytes(seed)) = secrets.get(wyrm_link_sdk::REQUESTER_KEY) else {
            return None;
        };
        let key = ed25519_dalek::SigningKey::from_bytes(&seed[..].try_into().ok()?);
        let rec = as_rec(Some(key.clone())).await;
        rec.meta(&mock).await.ok()?;
        Some(key)
    })
    .await;
    let rec = as_rec(Some(key.clone())).await;
    assert!(
        rec.set(&format!("{mock}/g0/p0"), 5.0).await.is_err(),
        "read: no set"
    );
    // the link itself learns its grants with `{site}` expanded (ADR 0023)
    let s = env.tls_session("rec").await;
    assert_eq!(
        hello_grants(&s, "rec", &token).await,
        Some(vec![(
            mock.clone(),
            u64::from(wyrm_core::Perm::Read.code())
        )]),
        "hello carries the grants"
    );

    env.client()
        .await
        .invoke_one(&sys, "grant", grant("write"))
        .await
        .unwrap();
    eventually("set after the rebuild", 15, || async {
        let rec = as_rec(Some(key.clone())).await;
        rec.set(&format!("{mock}/g0/p0"), 6.0).await.ok()
    })
    .await;
    // the key signs only as `link:rec` (the audit names the real caller)
    let spoof = WyrmClient::new(env.tls_session("rec").await)
        .with_timeout(Duration::from_secs(2))
        .with_tokens(Arc::new(
            SigningTokens::new(key.clone(), SITE).subject("user:admin".to_owned()),
        ));
    assert!(
        spoof.set(&format!("{mock}/g0/p0"), 7.0).await.is_err(),
        "another subject: refused"
    );
    // the grant does not reach sys
    let rec = as_rec(Some(key.clone())).await;
    assert!(
        rec.meta(&format!("wy/{SITE}/sys/links")).await.is_err(),
        "never sys"
    );
    // grants show in Get Permissions and in the audit
    let rows = env
        .client()
        .await
        .invoke_one(
            &format!("wy/{SITE}/sys"),
            "get_permissions",
            Value::Map(Default::default()),
        )
        .await
        .unwrap();
    assert!(format!("{rows:?}").contains("wy/{site}/downstream/mock"));
    assert!(env.ctl.audit_tail(50).iter().any(|r| r.op == "link_grant"));
    env.stop().await;
}

async fn hello(s: &zenoh::Session, id: &str, token: &str) -> Option<wyrm_core::status::StatusCode> {
    let mut args = BTreeMap::new();
    args.insert("token".to_owned(), Value::Bytes(token.as_bytes().to_vec()));
    let r = s
        .get(format!("wy/{SITE}/sys/links/{id}/~act/hello"))
        .payload(wyrm_core::codec::to_vec(&Value::Map(args)).unwrap())
        .timeout(Duration::from_secs(5)) // argon2 in a debug build on a busy CI runner
        .await
        .unwrap();
    let reply = r.recv_async().await.ok()?;
    let s = reply.result().ok()?;
    wyrm_core::codec::from_slice::<wyrm_core::Attachment>(&s.attachment()?.to_bytes())
        .ok()?
        .status
}

/// `hello` is reachable only by the link's own certificate.
#[tokio::test(flavor = "multi_thread")]
async fn hello_is_bound_to_the_cn() {
    use wyrm_core::status::StatusCode::Known;
    use wyrm_core::Status;
    let env = Env::start(
        "hello",
        r#"links: { a: { driver: "x", mode: "external" }, b: { driver: "x", mode: "external" } },"#,
    )
    .await;
    let dir = env.ctl.config().data_dir.join("links");
    let tok_a = std::fs::read_to_string(dir.join("a/token")).unwrap();
    let sb = env.tls_session("b").await;
    assert_eq!(
        hello(&sb, "a", &tok_a).await,
        None,
        "b cannot reach a's hello"
    );
    let sa = env.tls_session("a").await;
    assert_eq!(hello(&sa, "a", &tok_a).await, Some(Known(Status::Ok)));
    assert_eq!(
        hello(&sa, "a", "wrong").await,
        Some(Known(Status::PermissionDenied))
    );
    env.stop().await;
}

#[test]
fn upstream_downsampling_has_one_rule_per_link() {
    use wyrmd::upstream_downsampling as ds;
    assert!(ds("edge", &[], 5.0).is_none());
    let d = ds("edge", &["a".into(), "ab".into()], 5.0).unwrap();
    let keys: Vec<&str> = d[0]["rules"]
        .as_array()
        .unwrap()
        .iter()
        .map(|r| r["key_expr"].as_str().unwrap())
        .collect();
    // No overlap: `a` does not cover `ab`.
    assert_eq!(
        keys,
        [
            "wy/edge/downstream/a/**/~val",
            "wy/edge/downstream/ab/**/~val"
        ]
    );
    assert_eq!(d[0]["link_protocols"], serde_json::json!(["quic"]));
}

#[test]
fn plaintext_off_loopback_is_refused() {
    use wyrmd::plaintext_off_loopback as off;
    assert!(!off("tcp/127.0.0.1:7447"));
    assert!(!off("tcp/[::1]:7447"));
    assert!(!off("tcp/localhost:7447"));
    assert!(!off("tls/0.0.0.0:7447"));
    assert!(!off("unixsock-stream//tmp/wyrm.sock"));
    assert!(off("tcp/0.0.0.0:7447"));
    assert!(off("tcp/192.168.1.10:7447#iface=eth0"));
    assert!(off("udp/[fe80::1]:7447"));

    let cfg = Config::from_json5(r#"{ site: "x" }"#).unwrap();
    assert_eq!(cfg.listen, ["tcp/127.0.0.1:7447"]);
    let e = Config::from_json5(r#"{ site: "x", listen: ["tcp/0.0.0.0:7447"] }"#).unwrap_err();
    assert!(e.to_string().contains("plaintext"), "{e}");
    assert!(Config::from_json5(r#"{ site: "x", connect: ["tcp/10.0.0.2:7447"] }"#).is_err());
    assert!(Config::from_json5(
        r#"{ site: "x", listen: ["tcp/0.0.0.0:7447"], insecure_plaintext: true }"#
    )
    .is_ok());
    assert!(Config::from_json5(r#"{ site: "x", rest: "0.0.0.0:8000" }"#).is_err());
    // REST bypasses the ACL: refused in prod even on loopback
    let e = Config::from_json5(r#"{ site: "x", rest: "127.0.0.1:8000" }"#).unwrap_err();
    assert!(e.to_string().contains("bypasses the ACL"), "{e}");
    assert!(Config::from_json5(r#"{ site: "x", profile: "dev", rest: "127.0.0.1:8000" }"#).is_ok());
    assert!(
        Config::from_json5(r#"{ site: "x", links: { a: { driver: "mock", bogus: 1 } } }"#).is_err()
    );
}

#[test]
fn example_config_parses() {
    let text = include_str!("../../../examples/wyrmd.json5");
    let cfg = Config::from_json5(text).unwrap();
    assert!(cfg.links.contains_key("plc1"));
}

/// The flow engine runs in wyrmd, and links trust its key: a flow command
/// (alarm → `reset` on the mock) succeeds. A bare `put` on `~def` deploys
/// nothing.
#[tokio::test(flavor = "multi_thread")]
async fn flow_commands_a_link_through_wyrmd() {
    let env = Env::start("flow", MOCK).await;
    let c = env.client().await;
    let m = |kv: &[(&str, Value)]| {
        Value::Map(
            kv.iter()
                .map(|(k, v)| ((*k).to_owned(), v.clone()))
                .collect(),
        )
    };
    let s = |x: &str| Value::from(x);
    let edge = |a: &str, b: &str| Value::Array(vec![s(a), s(b)]);
    let def = m(&[
        ("id", s("shed")),
        (
            "nodes",
            m(&[
                (
                    "a",
                    m(&[
                        ("type", s("subscribe")),
                        ("key", s("downstream/mock/g0/p0")),
                    ]),
                ),
                (
                    "al",
                    m(&[("type", s("alarm")), ("high", Value::Float(-1e9))]),
                ),
                (
                    "cmd",
                    m(&[
                        ("type", s("invoke")),
                        ("path", s("downstream/mock")),
                        ("action", s("reset")),
                        ("on", s("rising")),
                    ]),
                ),
                ("res", m(&[("type", s("publish")), ("node", s("res"))])),
                // a flow may write broker storage too (ADR 0017)
                (
                    "keep",
                    m(&[("type", s("set")), ("path", s("storage/plant/copy"))]),
                ),
            ]),
        ),
        (
            "edges",
            Value::Array(vec![
                edge("a.out", "al.in"),
                edge("al.out", "cmd.in"),
                edge("cmd.out", "res.in"),
                edge("a.out", "keep.in"),
            ]),
        ),
        ("permissions", m(&[("maxperm", s("write"))])),
    ]);
    let storage = format!("wy/{SITE}/storage");
    c.invoke_one(&storage, "add_node", m(&[("name", s("plant"))]))
        .await
        .unwrap();
    let number = m(&[("name", s("copy")), ("type", Value::from("number"))]);
    c.invoke_one(&format!("{storage}/plant"), "add_value", number)
        .await
        .unwrap();
    let flows = format!("wy/{SITE}/dataflows");
    let proofs = wyrm_flow::command_targets(&def, SITE)
        .unwrap()
        .into_iter()
        .map(|t| {
            let p = c.proof(&t).unwrap();
            (t, Value::Bytes(p))
        })
        .collect();
    let args = m(&[("def", def.clone()), ("proofs", Value::Map(proofs))]);
    c.invoke_one(&flows, "deploy", args).await.unwrap();
    let res = format!("{flows}/shed/nodes/res/~val");
    let q = eventually("flow command result", 10, || {
        let (session, key) = (c.session().clone(), res.clone());
        async move {
            let r = session.get(&key).await.ok()?;
            let reply = r.recv_async().await.ok()?;
            let smp = reply.result().ok()?;
            wyrm_core::codec::from_slice::<wyrm_core::Sample>(&smp.payload().to_bytes())
                .ok()
                .map(|s| s.q)
        }
    })
    .await;
    assert_eq!(
        q,
        wyrm_core::Quality::Good,
        "the mock accepted the flow token"
    );
    let copy = format!("{storage}/plant/copy");
    let v = eventually("flow set into storage", 10, || last_val(&c, &copy)).await;
    assert!(v.as_f64().is_some(), "{v:?}");

    // `put ~def` is not a deploy path
    let mut other = def;
    if let Value::Map(mm) = &mut other {
        mm.insert("id".into(), s("sneaky"));
    }
    c.session()
        .put(
            format!("{flows}/sneaky/~def"),
            wyrm_core::codec::to_vec(&other).unwrap(),
        )
        .await
        .unwrap();
    tokio::time::sleep(Duration::from_millis(500)).await;
    let names: Vec<String> = c
        .children(&flows)
        .await
        .unwrap()
        .into_iter()
        .map(|c| c.name)
        .collect();
    assert_eq!(names, ["shed"]);
    env.stop().await;
}

/// Iteration 4: an edge broker connects to a central broker over QUIC with
/// mTLS, each side trusting the other's CA only on that link. A client of
/// the central broker lists and reads the edge's links; it cannot write.
/// Sites in `level` (`write` or `config`) of `wy/<site>/sys/signing_keys`.
async fn signer_sites(c: &WyrmClient, site: &str, level: &str) -> Vec<String> {
    match last_val(c, &format!("wy/{site}/sys/signing_keys")).await {
        Some(Value::Map(m)) => match m.get(level) {
            Some(Value::Map(sites)) => sites.keys().cloned().collect(),
            _ => Vec::new(),
        },
        _ => Vec::new(),
    }
}

/// A `peers.upstream` entry: the upstream's CA and the certificate it
/// issued for `me` (ADR 0015), from its data_dir.
fn upstream_entry(site: &str, quic: u16, dir: &std::path::Path, me: &str) -> String {
    format!(
        r#"{{ site: "{site}", endpoint: "quic/127.0.0.1:{quic}", ca: "{ca}", cert: "{cert}", key: "{key}" }}"#,
        ca = dir.join("pki/ca.pem").display(),
        cert = dir.join(format!("peers/{me}/broker.pem")).display(),
        key = dir.join(format!("peers/{me}/broker.key")).display(),
    )
}

#[tokio::test(flavor = "multi_thread")]
async fn two_brokers_over_quic() {
    // central's admin key signs the client's tokens; edge has its own
    let key = ed25519_dalek::SigningKey::from_bytes(&SEED);
    let admin = hex::encode(key.verifying_key().to_bytes());
    let edge_admin = hex::encode(
        ed25519_dalek::SigningKey::from_bytes(&[11; 32])
            .verifying_key()
            .to_bytes(),
    );
    let (c_dir, e_dir) = (temp_dir("central"), temp_dir("edge"));
    let (c_tcp, c_quic, e_tcp, c_gw, e_tls) = (
        free_port(),
        free_port(),
        free_port(),
        free_port(),
        free_port(),
    );
    let central = Config::from_json5(&format!(
        r#"{{
            site: "central",
            data_dir: "{}",
            listen: ["tcp/127.0.0.1:{c_tcp}"],
            admin_keys: ["{admin}"],
            peers: {{
                listen: "quic/127.0.0.1:{c_quic}",
                downstream: [{{ site: "edge" }}],
            }},
            gateway: {{ listen: "127.0.0.1:{c_gw}", admin_user: "root" }},
        }}"#,
        c_dir.display(),
    ))
    .unwrap();
    let up = upstream_entry("central", c_quic, &c_dir, "edge");
    let edge = Config::from_json5(&format!(
        r#"{{
            site: "edge",
            data_dir: "{}",
            listen: ["tcp/127.0.0.1:{e_tcp}", "tls/127.0.0.1:{e_tls}"],
            admin_keys: ["{edge_admin}"],
            peers: {{
                upstream: [{up}],
                upstream_val_hz: 5,
            }},
            links: {{
                mock: {{ driver: "mock", params: {{ points: 8, rate_hz: 20, depth: 1, fanout: 2 }} }},
                slow: {{ driver: "mock", params: {{ points: 1, rate_hz: 2, depth: 1, fanout: 1 }} }},
                pm: {{ driver: "mock", mode: "process", params: {{ points: 1, rate_hz: 1, depth: 1, fanout: 1 }} }},
            }},
        }}"#,
        e_dir.display(),
    ))
    .unwrap();
    // Central first: opening it issues the edge's certificate.
    let exe: PathBuf = env!("CARGO_BIN_EXE_wyrmd").into();
    let env_lock = GATEWAY_ENV.lock().await;
    std::env::set_var(wyrmd::GATEWAY_ADMIN_PASSWORD_ENV, "two-brokers-root");
    let central = open_daemon(central, exe.clone()).unwrap();
    drop(env_lock);
    let gw = central.gateway().expect("central gateway");
    let edge = open_daemon(edge, exe).unwrap();
    let e_ctl = edge.control();
    let (c_stop, c_rx) = oneshot::channel::<()>();
    let (e_stop, e_rx) = oneshot::channel::<()>();
    let c_task = tokio::spawn(central.run_until(async {
        let _ = c_rx.await;
    }));
    let e_task = tokio::spawn(edge.run_until(async {
        let _ = e_rx.await;
    }));

    let mut zc = zenoh::Config::default();
    zc.insert_json5("mode", r#""client""#).unwrap();
    zc.insert_json5(
        "connect/endpoints",
        &format!(r#"["tcp/127.0.0.1:{c_tcp}"]"#),
    )
    .unwrap();
    zc.insert_json5("scouting/multicast/enabled", "false")
        .unwrap();
    zc.insert_json5("connect/timeout_ms", "5000").unwrap();
    let session = zenoh::open(zc).await.unwrap();
    let c = WyrmClient::new(session.clone())
        .with_tokens(Arc::new(SigningTokens::new(key, "edge")))
        .with_timeout(Duration::from_secs(3));
    // Edge follows central's signing keys (ADR 0018); learning them rebuilds
    // edge once, so wait for that before timing anything.
    eventually("edge trusts central's keys", 30, || async {
        signer_sites(&c, "edge", "write")
            .await
            .contains(&"central".to_owned())
            .then_some(())
    })
    .await;
    // edge does not allow central `config`: it passes central's keys on
    // for `write` only (ADR 0018)
    assert_eq!(signer_sites(&c, "edge", "config").await, ["edge"]);

    let names = eventually("edge links seen from central", 15, || {
        let c = &c;
        async move {
            let ch = c.children("wy/edge/downstream").await.ok()?;
            let mut names: Vec<String> = ch.into_iter().map(|c| c.name).collect();
            names.sort();
            (names.len() == 4).then_some(names)
        }
    })
    .await;
    // and edge's embedded scheduler (ADR 0022)
    assert_eq!(names, ["mock", "pm", "scheduler", "slow"]);
    // Each broker shows its peer: the downstream edge beside central's
    // links (`downstream/edge`), the upstream central at `upstream/central`, both
    // connected (liveliness of `sys/broker`).
    let down = "wy/central/downstream/edge";
    let kids: Vec<String> = eventually("downstream/edge beside central's links", 10, || async {
        let ch = c.children("wy/central/downstream").await.ok()?;
        let names: Vec<String> = ch.into_iter().map(|c| c.name).collect();
        names.contains(&"edge".to_owned()).then_some(names)
    })
    .await;
    assert!(kids.contains(&"edge".to_owned()), "{kids:?}");
    let meta = c.meta(down).await.expect("downstream node");
    assert_eq!(
        meta.attr.as_ref().and_then(|a| a.get("root")),
        Some(&Value::from("wy/edge"))
    );
    eventually("central sees edge connected", 10, || async {
        (last_val(&c, &format!("{down}/connected")).await == Some(Value::Bool(true))).then_some(())
    })
    .await;
    let mut ez = zenoh::Config::default();
    ez.insert_json5("mode", r#""client""#).unwrap();
    ez.insert_json5(
        "connect/endpoints",
        &format!(r#"["tcp/127.0.0.1:{e_tcp}"]"#),
    )
    .unwrap();
    ez.insert_json5("scouting/multicast/enabled", "false")
        .unwrap();
    let ec = WyrmClient::new(zenoh::open(ez).await.unwrap()).with_timeout(Duration::from_secs(3));
    eventually("edge sees central connected", 10, || async {
        (last_val(&ec, "wy/edge/upstream/central/connected").await == Some(Value::Bool(true)))
            .then_some(())
    })
    .await;
    let _ = ec.session().close().await;
    let mut vals = c.subscribe("wy/edge/downstream/mock/g0/p0").await.unwrap();
    let got = tokio::time::timeout(Duration::from_secs(5), async {
        while let Some(ev) = vals.next().await {
            if let ValEvent::Sample { .. } = ev {
                return true;
            }
        }
        false
    })
    .await;
    assert_eq!(got, Ok(true), "edge samples reach the central client");
    // One downsampling budget per link: the busy `mock` link (160 samples/s)
    // does not starve `slow` (2 samples/s) under upstream_val_hz: 5.
    let mut busy = c.subscribe("wy/edge/downstream/mock/**").await.unwrap();
    let drain = tokio::spawn(async move { while busy.next().await.is_some() {} });
    let mut slow = c.subscribe("wy/edge/downstream/slow/**").await.unwrap();
    let mut n = 0;
    let _ = tokio::time::timeout(Duration::from_secs(4), async {
        while let Some(ev) = slow.next().await {
            if let ValEvent::Sample { .. } = ev {
                n += 1;
            }
        }
    })
    .await;
    assert!(n >= 5, "slow link starved: {n} samples in 4 s");
    // Commands from above (ADR 0018): write on edge's devices with
    // central's key; sys only with allow_config (not set here); a key
    // neither site signs with is refused.
    eventually("central sets an edge point", 20, || async {
        c.set("wy/edge/downstream/mock/g0/p0", 1.0).await.ok()
    })
    .await;
    // a process link takes the keys from its hello after the rebuild
    eventually(
        "central sets a point of an edge process link",
        30,
        || async { c.set("wy/edge/downstream/pm/g0/p0", 1.0).await.ok() },
    )
    .await;
    assert!(c
        .invoke_one(
            "wy/edge/sys",
            "get_permissions",
            Value::Map(Default::default())
        )
        .await
        .is_err());
    let stranger = WyrmClient::new(session.clone())
        .with_tokens(Arc::new(SigningTokens::new(
            ed25519_dalek::SigningKey::from_bytes(&[13; 32]),
            "edge",
        )))
        .with_timeout(Duration::from_secs(3));
    let e = stranger
        .set("wy/edge/downstream/mock/g0/p0", 1.0)
        .await
        .expect_err("an unknown key");
    assert!(e.is(wyrm_core::Status::PermissionDenied), "{e}");
    // A user of central's gateway: the token for edge carries the role's
    // own-site grants rewritten to edge; edge trusts the gateway's key
    // through central and records where the user came from.
    let user = |role: &str| {
        let p = wyrm_gateway::Principal {
            name: format!("{role}1"),
            roles: vec![role.to_owned()],
            grants: wyrm_gateway::RoleTable::default().grants("central", &[role.to_owned()]),
            claims: wyrm_gateway::SessionClaims {
                sub: format!("{role}1"),
                roles: vec![role.to_owned()],
                exp: u64::MAX,
                iat: 0,
                jti: [0; 16],
                gen: 0,
            },
        };
        WyrmClient::new(session.clone())
            .with_tokens(Arc::new(gw.tokens_for(&p)))
            .with_timeout(Duration::from_secs(3))
    };
    eventually("an operator at central sets an edge point", 20, || async {
        user("operator")
            .set("wy/edge/downstream/mock/g0/p0", 2.0)
            .await
            .ok()
    })
    .await;
    let e = user("viewer")
        .set("wy/edge/downstream/mock/g0/p0", 3.0)
        .await
        .expect_err("a viewer");
    assert!(e.is(wyrm_core::Status::PermissionDenied), "{e}");
    eventually("edge's audit names the central user", 10, || async {
        e_ctl
            .audit_tail(200)
            .iter()
            .any(|r| r.sub == "claimed:user:operator1@central")
            .then_some(())
    })
    .await;

    // Quiet first: a live 160 samples/s stream slows the broker's close.
    drain.abort();
    drop(slow);
    let _ = c.session().close().await;
    let _ = c_stop.send(());
    let _ = e_stop.send(());
    e_task.await.unwrap().unwrap();
    c_task.await.unwrap().unwrap();
    drop(e_ctl);
}

/// A chain `plant → edge → central` (owner decision 2026-10-22): central
/// lists `via: ["plant"]` for edge, so it reads plant through edge; every
/// upstream reads `sys` and `upstream` of the sites below it, never commands them.
#[tokio::test(flavor = "multi_thread")]
async fn chain_of_three_brokers() {
    // one admin key per site: central's signs the client's tokens
    let key = ed25519_dalek::SigningKey::from_bytes(&SEED);
    let admin = hex::encode(key.verifying_key().to_bytes());
    let own = |seed: u8| {
        hex::encode(
            ed25519_dalek::SigningKey::from_bytes(&[seed; 32])
                .verifying_key()
                .to_bytes(),
        )
    };
    let (edge_admin, plant_admin) = (own(11), own(12));
    let (c_dir, e_dir, p_dir) = (
        temp_dir("ch-central"),
        temp_dir("ch-edge"),
        temp_dir("ch-plant"),
    );
    let (c_tcp, c_quic, e_tcp, e_quic, p_tcp) = (
        free_port(),
        free_port(),
        free_port(),
        free_port(),
        free_port(),
    );
    let cfg = |text: String| Config::from_json5(&text).unwrap();
    let central = cfg(format!(
        r#"{{ site: "central", data_dir: "{}", listen: ["tcp/127.0.0.1:{c_tcp}"],
              admin_keys: ["{admin}"],
              peers: {{ listen: "quic/127.0.0.1:{c_quic}",
                        downstream: [{{ site: "edge", via: ["plant"] }}] }} }}"#,
        c_dir.display(),
    ));
    // edge lets central run sys actions; plant does not let edge (ADR 0018)
    let up =
        upstream_entry("central", c_quic, &c_dir, "edge").replace(" }", ", allow_config: true }");
    let edge = cfg(format!(
        r#"{{ site: "edge", data_dir: "{}", listen: ["tcp/127.0.0.1:{e_tcp}"],
              admin_keys: ["{edge_admin}"],
              peers: {{ listen: "quic/127.0.0.1:{e_quic}",
                        upstream: [{up}],
                        downstream: [{{ site: "plant" }}] }},
              links: {{ mock: {{ driver: "mock", params: {{ points: 2, rate_hz: 5, depth: 1, fanout: 1 }} }} }} }}"#,
        e_dir.display(),
    ));
    let up = upstream_entry("edge", e_quic, &e_dir, "plant");
    let plant = cfg(format!(
        r#"{{ site: "plant", data_dir: "{}", listen: ["tcp/127.0.0.1:{p_tcp}"],
              admin_keys: ["{plant_admin}"],
              peers: {{ upstream: [{up}] }},
              links: {{ pm: {{ driver: "mock", params: {{ points: 2, rate_hz: 5, depth: 1, fanout: 1 }} }} }} }}"#,
        p_dir.display(),
    ));
    // Upstream sites first: opening one issues its downstream's certificate.
    let exe: PathBuf = env!("CARGO_BIN_EXE_wyrmd").into();
    let mut stops = Vec::new();
    let mut tasks = Vec::new();
    for d in [central, edge, plant] {
        let d = open_daemon(d, exe.clone()).unwrap();
        stops.push(d);
    }
    let mut senders = Vec::new();
    for d in stops.drain(..) {
        let (tx, rx) = oneshot::channel::<()>();
        senders.push(tx);
        tasks.push(tokio::spawn(d.run_until(async {
            let _ = rx.await;
        })));
    }
    let mut zc = zenoh::Config::default();
    zc.insert_json5("mode", r#""client""#).unwrap();
    zc.insert_json5(
        "connect/endpoints",
        &format!(r#"["tcp/127.0.0.1:{c_tcp}"]"#),
    )
    .unwrap();
    zc.insert_json5("scouting/multicast/enabled", "false")
        .unwrap();
    zc.insert_json5("connect/timeout_ms", "5000").unwrap();
    let session = zenoh::open(zc).await.unwrap();
    let c = WyrmClient::new(session.clone())
        .with_tokens(Arc::new(SigningTokens::new(key.clone(), "plant")))
        .with_timeout(Duration::from_secs(3));
    // plant learns central's keys through edge (two rebuilds: edge, then
    // plant); wait before timing anything
    eventually("plant trusts central's keys", 40, || async {
        (signer_sites(&c, "plant", "write").await == ["central", "edge", "plant"]).then_some(())
    })
    .await;
    // edge allows central `config`, so it passes central's keys on for
    // `config` too; plant does not allow edge, which it decides itself
    assert_eq!(
        signer_sites(&c, "edge", "config").await,
        ["central", "edge"]
    );
    let names = |key: &'static str| {
        let c = &c;
        async move {
            let mut n: Vec<String> = c
                .children(key)
                .await
                .ok()?
                .into_iter()
                .map(|c| c.name)
                .collect();
            n.sort();
            Some(n)
        }
    };
    // two hops down: plant's links, through edge
    let pm = eventually("plant's links seen from central", 20, || async {
        names("wy/plant/downstream")
            .await
            .filter(|n| n.contains(&"pm".to_owned()))
    })
    .await;
    assert_eq!(pm, ["pm", "scheduler"]);
    // edge shows plant beside its links, connected
    eventually(
        "edge's downstream/plant connected, seen from central",
        10,
        || async {
            (last_val(&c, "wy/edge/downstream/plant/connected").await == Some(Value::Bool(true)))
                .then_some(())
        },
    )
    .await;
    // sys and up of the sites below, readable
    let sys = names("wy/edge/sys").await.expect("edge sys from central");
    // the folder `packages` and the count `packages_total`: two nodes
    for n in ["links", "packages", "packages_total"] {
        assert!(sys.contains(&n.to_owned()), "{n}: {sys:?}");
    }
    // a downstream broker is not a sys/links entry (as in DSA, ADR 0015)
    assert_eq!(names("wy/edge/sys/links").await.unwrap(), ["mock"]);
    assert_eq!(names("wy/plant/sys/links").await.unwrap(), ["pm"]);
    assert_eq!(names("wy/plant/upstream").await.unwrap(), ["edge"]);
    assert_eq!(
        names("wy/central/upstream").await.unwrap(),
        Vec::<String>::new(),
        "up always there"
    );
    // samples come up two hops
    let mut vals = c.subscribe("wy/plant/downstream/pm/g0/p0").await.unwrap();
    let got = tokio::time::timeout(Duration::from_secs(8), async {
        while let Some(ev) = vals.next().await {
            if let ValEvent::Sample { .. } = ev {
                return true;
            }
        }
        false
    })
    .await;
    assert_eq!(got, Ok(true), "plant samples reach central");
    // Commands two hops down (ADR 0018): plant's devices take central's
    // key; edge's sys too (edge allows central); plant's sys does not
    // (plant does not allow edge, through which central comes).
    eventually("central sets a plant point", 20, || async {
        c.set("wy/plant/downstream/pm/g0/p0", 1.0).await.ok()
    })
    .await;
    let none = || Value::Map(Default::default());
    let ce = WyrmClient::new(session.clone())
        .with_tokens(Arc::new(SigningTokens::new(key, "edge")))
        .with_timeout(Duration::from_secs(3));
    eventually("central runs an edge sys action", 20, || async {
        ce.invoke_one("wy/edge/sys", "get_permissions", none())
            .await
            .ok()
    })
    .await;
    // hello checks a link token, not a ptok: never from above, even with
    // allow_config (edge's ACL drops it, so no answer comes)
    let hello = Value::Map(BTreeMap::from([(
        "token".to_owned(),
        Value::Bytes(b"guess".to_vec()),
    )]));
    let e = ce
        .invoke_one("wy/edge/sys/links/mock", "hello", hello)
        .await
        .expect_err("hello from above");
    assert!(e.is(wyrm_core::Status::Timeout), "{e}");
    // a route copied from central's tree is plant's key (as DSA's Copy Path)
    let cc = WyrmClient::new(session.clone())
        .with_tokens(Arc::new(SigningTokens::new(
            ed25519_dalek::SigningKey::from_bytes(&SEED),
            "central",
        )))
        .with_timeout(Duration::from_secs(3));
    let arg = |k: &str, v: &str| Value::Map(BTreeMap::from([(k.to_owned(), Value::from(v))]));
    cc.invoke_one(
        "wy/central/sys/history",
        "add_watch_group",
        arg("name", "g"),
    )
    .await
    .unwrap();
    cc.invoke_one(
        "wy/central/sys/history/g",
        "add_watch_path",
        arg(
            "path",
            "wy/central/downstream/edge/downstream/plant/downstream/pm/g0/p0",
        ),
    )
    .await
    .unwrap();
    let w = cc.meta("wy/central/sys/history/g/w1").await.unwrap();
    assert_eq!(
        w.attr_value("path"),
        Some(&Value::from("wy/plant/downstream/pm/g0/p0"))
    );
    assert!(c
        .invoke_one("wy/plant/sys", "get_permissions", none())
        .await
        .is_err());
    drop(vals);
    let _ = c.session().close().await;
    for tx in senders.into_iter().rev() {
        let _ = tx.send(());
    }
    for t in tasks.into_iter().rev() {
        t.await.unwrap().unwrap();
    }
}

/// Backlog item 6: the first queries of edge nodes from central, right
/// after the peer link comes up, all answer (no lost first query).
#[tokio::test(flavor = "multi_thread")]
async fn first_queries_across_peers_answer() {
    let key = ed25519_dalek::SigningKey::from_bytes(&SEED);
    let admin = hex::encode(key.verifying_key().to_bytes());
    let (c_dir, e_dir) = (temp_dir("fq-central"), temp_dir("fq-edge"));
    let (c_tcp, c_quic, e_tcp) = (free_port(), free_port(), free_port());
    let central = Config::from_json5(&format!(
        r#"{{ site: "central", data_dir: "{}", listen: ["tcp/127.0.0.1:{c_tcp}"],
              admin_keys: ["{admin}"],
              peers: {{ listen: "quic/127.0.0.1:{c_quic}", downstream: [{{ site: "edge" }}] }} }}"#,
        c_dir.display(),
    ))
    .unwrap();
    let up = upstream_entry("central", c_quic, &c_dir, "edge");
    let edge = Config::from_json5(&format!(
        r#"{{ site: "edge", data_dir: "{}", listen: ["tcp/127.0.0.1:{e_tcp}"],
              admin_keys: ["{admin}"],
              peers: {{ upstream: [{up}] }},
              links: {{ mock: {{ driver: "mock", params: {{ points: 2, rate_hz: 5, depth: 1, fanout: 1 }} }} }} }}"#,
        e_dir.display(),
    ))
    .unwrap();
    let exe: PathBuf = env!("CARGO_BIN_EXE_wyrmd").into();
    let central = open_daemon(central, exe.clone()).unwrap();
    let edge = open_daemon(edge, exe).unwrap();
    let (c_stop, c_rx) = oneshot::channel::<()>();
    let (e_stop, e_rx) = oneshot::channel::<()>();
    let c_task = tokio::spawn(central.run_until(async {
        let _ = c_rx.await;
    }));
    let e_task = tokio::spawn(edge.run_until(async {
        let _ = e_rx.await;
    }));
    let c = WyrmClient::new(loopback_session(c_tcp).await).with_timeout(Duration::from_secs(5));
    eventually("edge connected at central", 15, || async {
        (last_val(&c, "wy/central/downstream/edge/connected").await == Some(Value::Bool(true)))
            .then_some(())
    })
    .await;
    // every key once, in order, as an explorer opening the tree would
    let keys = [
        "wy/edge/sys",
        "wy/edge/sys/upstream",
        "wy/edge/sys/upstream/central",
        "wy/edge/sys/links",
        "wy/edge/sys/links/mock",
        "wy/edge/sys/history",
        "wy/edge/sys/packages",
        "wy/edge/sys/quarantine",
        "wy/edge/upstream",
        "wy/edge/upstream/central",
        "wy/edge/downstream/mock",
    ];
    let mut failed = Vec::new();
    for k in keys {
        let started = std::time::Instant::now();
        if let Err(e) = c.children(k).await {
            failed.push(format!("{k}: {e} after {:?}", started.elapsed()));
        }
    }
    let mut lists = Vec::new();
    for k in keys {
        match c.list(k).await {
            Ok(mut s) => lists.push(s.next().await.is_some()),
            Err(e) => failed.push(format!("list {k}: {e}")),
        }
    }
    assert!(failed.is_empty(), "first queries lost: {failed:#?}");
    assert!(lists.iter().all(|ok| *ok));
    let _ = c.session().close().await;
    let _ = c_stop.send(());
    let _ = e_stop.send(());
    e_task.await.unwrap().unwrap();
    c_task.await.unwrap().unwrap();
}

/// Iteration 5: the user gateway runs in wyrmd. The first admin comes from
/// the environment; a login is audited; the gateway's per-user tokens are
/// accepted by links and by the admin, within each user's grants.
#[tokio::test(flavor = "multi_thread")]
async fn gateway_in_wyrmd() {
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    let port = free_port();
    let env_lock = GATEWAY_ENV.lock().await;
    std::env::set_var(
        wyrmd::GATEWAY_ADMIN_PASSWORD_ENV,
        "correct-horse-battery-staple",
    );
    let env = Env::start(
        "gateway",
        &format!(r#"{MOCK} gateway: {{ listen: "127.0.0.1:{port}", admin_user: "root" }},"#),
    )
    .await;
    drop(env_lock);
    let gw = env.gateway.clone().expect("gateway configured");
    let addr = gw.local_addr().await;
    assert_eq!(addr.port(), port);

    let mut body = BTreeMap::new();
    body.insert("user".to_owned(), Value::from("root"));
    body.insert(
        "password".to_owned(),
        Value::from("correct-horse-battery-staple"),
    );
    let body = wyrm_core::codec::to_vec(&Value::Map(body)).unwrap();
    let req = format!(
        "POST /api/login HTTP/1.1\r\nHost: gw\r\nConnection: close\r\nContent-Type: application/cbor\r\nContent-Length: {}\r\n\r\n",
        body.len()
    );
    let mut s = tokio::net::TcpStream::connect(addr).await.unwrap();
    s.write_all(req.as_bytes()).await.unwrap();
    s.write_all(&body).await.unwrap();
    let mut resp = Vec::new();
    tokio::time::timeout(Duration::from_secs(10), s.read_to_end(&mut resp))
        .await
        .unwrap()
        .unwrap();
    let split = resp.windows(4).position(|w| w == b"\r\n\r\n").unwrap();
    assert!(resp.starts_with(b"HTTP/1.1 200"), "login ok");
    let Value::Map(m) = wyrm_core::codec::from_slice::<Value>(&resp[split + 4..]).unwrap() else {
        panic!("login body is a map")
    };
    let Some(Value::Str(session)) = m.get("session") else {
        panic!("session token")
    };

    let p = gw.authenticate(session).expect("session verifies");
    // The probe's scenarios through this gateway, as the explorer works:
    // actions, the list callbacks they cause and values (links/probe).
    let probe_gw = wyrm_gateway_client::Gateway::login(
        &format!("http://{addr}"),
        "root",
        "correct-horse-battery-staple",
    )
    .await
    .expect("probe login");
    for (name, text) in wyrm_link_probe::BUILTIN {
        let sc = wyrm_link_probe::Scenario::parse(text).unwrap();
        let conn = probe_gw.connect().await.unwrap();
        let vars = BTreeMap::from([("site".to_owned(), SITE.to_owned())]);
        let report = wyrm_link_probe::run(&conn, &sc, vars).await;
        assert!(report.passed(), "probe {name}:\n{}", report.text());
    }
    let c = WyrmClient::new(env.session().await)
        .with_tokens(Arc::new(gw.tokens_for(&p)))
        .with_timeout(Duration::from_secs(3));
    c.set(&format!("wy/{SITE}/downstream/mock/g0/p0"), 5.0)
        .await
        .expect("a gateway token is accepted by the link");
    // The control plane trusts the gateway too; the user's grants decide:
    // the admin role reaches sys/**, viewer and engineer do not.
    let history = format!("wy/{SITE}/sys/links/mock");
    let none = || Value::Map(BTreeMap::new());
    c.invoke_one(&history, "history", none())
        .await
        .expect("an admin user runs a control-plane action");
    // sys/audit keeps its tail action (regression in 0f3bab6)
    let mut n = BTreeMap::new();
    n.insert("n".to_owned(), Value::UInt(3));
    let tail = c
        .invoke_one(&format!("wy/{SITE}/sys/audit"), "tail", Value::Map(n))
        .await
        .expect("audit tail");
    assert!(matches!(tail, Some(Value::Array(_))), "{tail:?}");
    for role in ["viewer", "engineer"] {
        let mut q = p.clone();
        q.name = format!("{role}-user");
        q.grants = wyrm_gateway::RoleTable::default().grants(SITE, &[role.to_owned()]);
        let cu = WyrmClient::new(env.session().await)
            .with_tokens(Arc::new(gw.tokens_for(&q)))
            .with_timeout(Duration::from_secs(3));
        let e = cu
            .invoke_one(&history, "history", none())
            .await
            .expect_err("no grant on sys/**");
        assert!(e.is(wyrm_core::Status::PermissionDenied), "{role}: {e}");
    }
    // Storage (ADR 0017): the users' grants decide; an import larger than a
    // WebSocket frame comes as a file over `POST /api/invoke`.
    let storage = format!("wy/{SITE}/storage");
    for (role, allowed) in [("viewer", false), ("operator", true)] {
        let mut q = p.clone();
        q.name = format!("{role}-user");
        q.grants = wyrm_gateway::RoleTable::default().grants(SITE, &[role.to_owned()]);
        let cu = WyrmClient::new(env.session().await)
            .with_tokens(Arc::new(gw.tokens_for(&q)))
            .with_timeout(Duration::from_secs(3));
        let name = BTreeMap::from([("name".to_owned(), Value::from(format!("{role}_dir")))]);
        let r = cu.invoke_one(&storage, "add_node", Value::Map(name)).await;
        assert_eq!(r.is_ok(), allowed, "{role}: {r:?}");
    }
    let one = format!(
        r#"{{"$type": "string", "?value": "{}"}}"#,
        "z".repeat(30_000)
    );
    let json = format!(r#"{{"a": {one}, "b": {one}, "c": {one}}}"#);
    let file = BTreeMap::from([("file".to_owned(), Value::Bytes(json.into_bytes()))]);
    let (st, v) = http_post(
        addr,
        &format!("/api/invoke?key={storage}&action=import"),
        session,
        wyrm_core::codec::to_vec(&Value::Map(file)).unwrap(),
    )
    .await;
    assert_eq!(st, 200, "{v:?}");
    let exported = c.invoke_one(&storage, "export", none()).await.unwrap();
    assert!(
        matches!(&exported, Some(Value::Str(t)) if t.len() > 64 * 1024 && t.contains(r#""c":"#)),
        "the import is there and exports back"
    );
    // sys Update/Get Permissions edit the gateway's role grants (DSA style)
    let sys = format!("wy/{SITE}/sys");
    let grant = |role: &str, path: &str, level: &str| {
        let mut m = BTreeMap::new();
        m.insert("role".to_owned(), Value::from(role));
        m.insert("path".to_owned(), Value::from(path));
        m.insert("level".to_owned(), Value::from(level));
        Value::Map(m)
    };
    let reply = c
        .invoke_one(
            &sys,
            "update_permissions",
            grant("viewer", "wy/{site}/sys/audit/**", "read"),
        )
        .await
        .expect("update permissions");
    assert!(reply.is_none(), "{reply:?}");
    assert_eq!(
        gw.grants_of(&["viewer".to_owned()])
            .perm(&format!("{sys}/audit/~meta")),
        wyrm_core::Perm::Read,
        "applied to the role at once"
    );
    let Some(Value::Array(rows)) = c.invoke_one(&sys, "get_permissions", none()).await.unwrap()
    else {
        panic!("permission rows")
    };
    let has = |source: &str, subject: &str, path: &str| {
        rows.iter().any(|r| {
            let Value::Map(m) = r else { return false };
            m.get("source") == Some(&Value::from(source))
                && m.get("subject") == Some(&Value::from(subject))
                && m.get("path")
                    .is_some_and(|p| matches!(p, Value::Str(p) if p.contains(path)))
        })
    };
    assert!(has("gateway", "viewer", "wy/{site}/sys/audit/**"));
    assert!(has("gateway", "admin", "wy/**"));
    assert!(has("acl", "local", &format!("wy/{SITE}/**")));
    let e = c
        .invoke_one(&sys, "update_permissions", grant("admin", "wy/**", "none"))
        .await
        .expect_err("the last admin grant stays");
    assert!(e.is(wyrm_core::Status::InvalidParameter), "{e}");
    let audit = env.ctl.audit_tail(50);
    assert!(audit
        .iter()
        .any(|r| r.op == "login" && r.sub == "user:root"));
    assert!(audit
        .iter()
        .any(|r| r.op == "update_permissions" && r.sub == "user:root"));
    env.stop().await;
}

/// `POST` with a CBOR body to the gateway as `session`; the status and the
/// CBOR answer. One write, so a refusal before the body is read still
/// reaches us (no reset).
async fn http_post(
    addr: std::net::SocketAddr,
    path: &str,
    session: &str,
    body: Vec<u8>,
) -> (u16, Value) {
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    let mut msg = format!(
        "POST {path} HTTP/1.1\r\nHost: gw\r\nConnection: close\r\nContent-Type: application/cbor\r\nAuthorization: Bearer {session}\r\nContent-Length: {}\r\n\r\n",
        body.len()
    )
    .into_bytes();
    msg.extend_from_slice(&body);
    let mut s = tokio::net::TcpStream::connect(addr).await.unwrap();
    s.write_all(&msg).await.unwrap();
    let mut resp = Vec::new();
    tokio::time::timeout(Duration::from_secs(10), s.read_to_end(&mut resp))
        .await
        .unwrap()
        .unwrap();
    let split = resp.windows(4).position(|w| w == b"\r\n\r\n").unwrap();
    let head = String::from_utf8_lossy(&resp[..split]).to_string();
    let status = head.split(' ').nth(1).unwrap().parse().unwrap();
    let v = wyrm_core::codec::from_slice(&resp[split + 4..]).unwrap_or(Value::Null);
    (status, v)
}

/// `wyrmd user …` manages gateway users on a stopped broker (password from
/// stdin) and is refused while the broker holds the stores.
#[tokio::test(flavor = "multi_thread")]
async fn user_cli_offline_only() {
    use std::io::Write;
    use std::process::{Command, Stdio};
    let dir = temp_dir("usercli");
    std::fs::create_dir_all(&dir).unwrap();
    let cfg_path = dir.join("wyrmd.json5");
    std::fs::write(
        &cfg_path,
        format!(
            r#"{{ site: "{SITE}", data_dir: "{}", listen: ["tcp/127.0.0.1:{}"],
                 gateway: {{ listen: "127.0.0.1:{}" }} }}"#,
            dir.join("data").display(),
            free_port(),
            free_port()
        ),
    )
    .unwrap();
    let wyrmd = |args: &[&str], stdin: Option<&str>| {
        let mut c = Command::new(env!("CARGO_BIN_EXE_wyrmd"))
            .arg("-c")
            .arg(&cfg_path)
            .args(args)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .unwrap();
        if let Some(s) = stdin {
            c.stdin.take().unwrap().write_all(s.as_bytes()).unwrap();
        }
        c.wait_with_output().unwrap()
    };
    let out = wyrmd(
        &["user", "add", "bob", "--roles", "viewer"],
        Some("long enough pw\n"),
    );
    assert!(
        out.status.success(),
        "{}",
        String::from_utf8_lossy(&out.stderr)
    );
    let out = wyrmd(&["user", "list"], None);
    let list = String::from_utf8_lossy(&out.stdout);
    assert!(list.contains("bob") && list.contains("viewer"), "{list}");

    // While the broker runs, the stores are locked.
    let cfg = Config::from_json5(&std::fs::read_to_string(&cfg_path).unwrap()).unwrap();
    let daemon = open_daemon(cfg, env!("CARGO_BIN_EXE_wyrmd").into()).unwrap();
    let gw = daemon.gateway().unwrap();
    assert!(gw.list_users().iter().any(|(n, _, _)| n == "bob"));
    let out = wyrmd(&["user", "list"], None);
    assert!(!out.status.success());
    assert!(String::from_utf8_lossy(&out.stderr).contains("in use"));
    drop(gw);
    drop(daemon);
}

/// The `tls/` listener needs a client certificate from our own CA: a client
/// without one, or with one from a foreign CA, does not get a session.
#[tokio::test(flavor = "multi_thread")]
async fn tls_listener_refuses_missing_and_foreign_certificates() {
    let env = Env::start("tlsneg", MOCK).await;
    let foreign_dir = temp_dir("foreign-ca");
    let foreign = wyrm_admin::secret::Pki::open_or_create(&foreign_dir).unwrap();
    let foreign_cert = foreign
        .issue("plc1", &[], false, &foreign_dir, "plc1")
        .unwrap();
    let open = |cert: Option<&wyrm_admin::secret::CertFiles>| {
        let mut zc = zenoh::Config::default();
        zc.insert_json5("mode", r#""client""#).unwrap();
        zc.insert_json5(
            "connect/endpoints",
            &format!(r#"["tls/127.0.0.1:{}"]"#, env.tls),
        )
        .unwrap();
        zc.insert_json5("scouting/multicast/enabled", "false")
            .unwrap();
        zc.insert_json5("connect/timeout_ms", "2000").unwrap();
        let mut tls = serde_json::json!({ "root_ca_certificate": env.ctl.ca_path() });
        if let Some(c) = cert {
            tls["connect_certificate"] = serde_json::json!(c.cert);
            tls["connect_private_key"] = serde_json::json!(c.key);
            tls["enable_mtls"] = serde_json::json!(true);
        }
        zc.insert_json5("transport/link/tls", &tls.to_string())
            .unwrap();
        zenoh::open(zc)
    };
    assert!(open(None).await.is_err(), "no client certificate");
    assert!(open(Some(&foreign_cert)).await.is_err(), "foreign CA");
    // control: a certificate from our CA connects
    let ours = env.ctl.link_cert("plc1").unwrap();
    let s = open(Some(&ours)).await.expect("own CA");
    s.close().await.unwrap();
    env.stop().await;
}

/// Profiles (spec 01/02): the admin stores and serves `pub/<name>/~meta`;
/// built-ins are fixed; `expand` folds `extends` in; links read profiles
/// through the ACL but cannot write them.
#[tokio::test(flavor = "multi_thread")]
async fn profiles_stored_served_and_inherited() {
    use wyrm_core::meta::{TextOrCode, TypeCode};
    use wyrm_core::profile::ProfileDef;
    let env = Env::start(
        "profiles",
        r#"links: { ext: { driver: "x", mode: "external" } },"#,
    )
    .await;
    let c = env.client().await;
    let sys = format!("wy/{SITE}/sys/profiles");
    let put = |name: &str, p: &ProfileDef| {
        let mut a = BTreeMap::new();
        a.insert("name".to_owned(), Value::from(name));
        a.insert(
            "profile".to_owned(),
            Value::Bytes(wyrm_core::codec::to_vec(p).unwrap()),
        );
        c.invoke_one(&sys, "put", Value::Map(a))
    };
    let temp = ProfileDef {
        meta: wyrm_core::NodeMeta {
            unit: Some(TextOrCode::Text("°C".into())),
            ..Default::default()
        },
        extends: Some("wy:number".into()),
    };
    put("acme:temp", &temp).await.unwrap();
    // built-ins are fixed; unknown parents and bad names are refused
    assert!(put("wy:number", &temp).await.is_err());
    let orphan = ProfileDef {
        extends: Some("acme:nothing".into()),
        ..temp.clone()
    };
    assert!(put("acme:orphan", &orphan).await.is_err());
    assert!(put("nocolon", &temp).await.is_err());

    assert_eq!(c.profile(SITE, "acme:temp", false).await.unwrap(), temp);
    let e = c.profile(SITE, "acme:temp", true).await.unwrap();
    assert_eq!(e.meta.ty, Some(TypeCode::Number), "from wy:number");
    assert_eq!(e.extends, None);
    assert!(c.profile(SITE, "acme:missing", false).await.is_err());
    // wildcard: built-ins and stored ones
    let r = c
        .session()
        .get(format!("wy/{SITE}/pub/*/~meta"))
        .await
        .unwrap();
    let mut n = 0;
    while let Ok(rep) = r.recv_async().await {
        if rep.result().is_ok() {
            n += 1;
        }
    }
    assert_eq!(n, 11, "10 built-ins + acme:temp");

    // a link reads profiles through the ACL, but cannot put into pub/**
    let s = env.tls_session("ext").await;
    let got = s
        .get(format!("wy/{SITE}/pub/acme:temp/~meta"))
        .await
        .unwrap()
        .recv_async()
        .await
        .ok()
        .and_then(|r| r.result().ok().map(|s| s.payload().to_bytes().to_vec()));
    assert_eq!(
        got.map(|b| wyrm_core::codec::from_slice::<ProfileDef>(&b).unwrap()),
        Some(temp.clone())
    );
    let sub = c
        .session()
        .declare_subscriber(format!("wy/{SITE}/pub/**"))
        .await
        .unwrap();
    s.put(format!("wy/{SITE}/pub/acme:temp/~meta"), vec![0u8])
        .await
        .unwrap();
    assert!(
        tokio::time::timeout(Duration::from_millis(500), sub.recv_async())
            .await
            .is_err(),
        "the ACL drops a link's put into pub/**"
    );

    let mut a = BTreeMap::new();
    a.insert("name".to_owned(), Value::from("acme:temp"));
    c.invoke_one(&sys, "remove", Value::Map(a)).await.unwrap();
    assert!(c.profile(SITE, "acme:temp", false).await.is_err());
    env.stop().await;
}

/// ADR 0005: an agent link gets a signing key as a link secret, and every
/// other link trusts it capped at `write` and only under the agent's
/// `allowed_prefixes` (the `hello` reply carries it in `limited_keys`, not in
/// `admin_keys`). Agent links cannot be external.
#[tokio::test(flavor = "multi_thread")]
async fn agent_key_is_trusted_capped_at_write() {
    let env = Env::start(
        "agentkey",
        r#"links: {
            ai: { driver: "agent", params: { allowed_prefixes: ["wy/e2e/downstream/mock"] } },
            ext: { driver: "x", mode: "external" },
        },"#,
    )
    .await;
    let keys = env.ctl.agent_keys();
    assert_eq!(keys.len(), 1, "agent key created at start");
    let dir = env.ctl.config().data_dir.join("links");
    let tok = std::fs::read_to_string(dir.join("ext/token")).unwrap();
    let s = env.tls_session("ext").await;
    let mut args = BTreeMap::new();
    args.insert("token".to_owned(), Value::Bytes(tok.as_bytes().to_vec()));
    let r = s
        .get(format!("wy/{SITE}/sys/links/ext/~act/hello"))
        .payload(wyrm_core::codec::to_vec(&Value::Map(args)).unwrap())
        .timeout(Duration::from_secs(2))
        .await
        .unwrap();
    let reply = r.recv_async().await.unwrap();
    let Value::Map(m) =
        wyrm_core::codec::from_slice::<Value>(&reply.result().unwrap().payload().to_bytes())
            .unwrap()
    else {
        panic!("hello reply is a map")
    };
    let agent = Value::Bytes(keys[0].to_bytes().to_vec());
    let Some(Value::Array(admin)) = m.get("admin_keys") else {
        panic!("admin_keys")
    };
    assert!(!admin.contains(&agent), "the agent key is not an admin key");
    let Some(Value::Array(limited)) = m.get("limited_keys") else {
        panic!("limited_keys")
    };
    // capped at write and scoped to the agent's allowed_prefixes
    let write = Value::UInt(wyrm_core::Perm::Write.code().into());
    let scopes = Value::Array(vec![Value::from("wy/e2e/downstream/mock")]);
    assert!(
        limited.contains(&Value::Array(vec![agent, write, scopes])),
        "{limited:?}"
    );
    // an external agent link is refused
    let c = env.client().await;
    let mut args = BTreeMap::new();
    args.insert("id".to_owned(), Value::from("ai2"));
    args.insert("driver".to_owned(), Value::from("agent"));
    args.insert("mode".to_owned(), Value::from("external"));
    assert!(c
        .invoke_one(&format!("wy/{SITE}/sys/links"), "install", Value::Map(args))
        .await
        .is_err());
    // the agent key never reaches the reply as a secret of another link
    assert!(m
        .get("secrets")
        .is_none_or(|s| !matches!(s, Value::Map(x) if x.contains_key("agent_key"))));
    env.stop().await;
}

/// A supervised link process exits when its broker process is gone
/// (`WYRM_PARENT_PID`), so a crashed wyrmd leaves no orphan links.
#[tokio::test(flavor = "multi_thread")]
async fn link_process_exits_without_its_parent() {
    let env = Env::start(
        "orphan",
        r#"links: { pp: { driver: "mock", mode: "external" } },"#,
    )
    .await;
    let token = env.ctl.config().data_dir.join("links/pp/token");
    let spawn = |parent: u32| {
        std::process::Command::new(env!("CARGO_BIN_EXE_wyrmd"))
            .args(["link", "mock"])
            .env("WYRM_SITE", SITE)
            .env("WYRM_LINK_ID", "pp")
            .env("WYRM_ENDPOINT", format!("tcp/127.0.0.1:{}", env.port))
            .env("WYRM_TOKEN_FILE", &token)
            .env("WYRM_PARENT_PID", parent.to_string())
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .spawn()
            .unwrap()
    };
    // our own pid is its parent: it keeps running
    let mut alive = spawn(std::process::id());
    tokio::time::sleep(Duration::from_secs(3)).await;
    assert!(
        alive.try_wait().unwrap().is_none(),
        "runs while the parent lives"
    );
    let _ = alive.kill();
    let _ = alive.wait();
    // a parent pid that is not its parent: it exits on its own
    let mut orphan = spawn(1);
    let mut exited = false;
    for _ in 0..50 {
        if orphan.try_wait().unwrap().is_some() {
            exited = true;
            break;
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
    if !exited {
        let _ = orphan.kill();
    }
    assert!(exited, "exits when its parent is gone");
    env.stop().await;
}

/// T11: with `state_anchor_dir` the control-plane WALs keep their head on
/// another medium; a WAL that is shorter than its anchor is refused.
#[test]
fn state_anchor_refuses_a_cut_wal() {
    let dir = temp_dir("anchor");
    let anchors = temp_dir("anchor-heads");
    let cfg = |anchor: &std::path::Path| {
        Config::from_json5(&format!(
            r#"{{ site: "{SITE}", data_dir: "{}", listen: ["tcp/127.0.0.1:{}"],
                 state_anchor_dir: "{}", {MOCK} }}"#,
            dir.display(),
            free_port(),
            anchor.display()
        ))
    };
    // an anchor inside data_dir protects nothing
    assert!(cfg(&dir.join("heads")).is_err());
    let exe: PathBuf = env!("CARGO_BIN_EXE_wyrmd").into();
    // the directory is the operator's (another medium): not created for them
    assert!(open_daemon(cfg(&anchors).unwrap(), exe.clone()).is_err());
    std::fs::create_dir_all(&anchors).unwrap();
    drop(open_daemon(cfg(&anchors).unwrap(), exe.clone()).unwrap());
    drop(open_daemon(cfg(&anchors).unwrap(), exe.clone()).unwrap());
    // the anchor says the registry WAL was longer than it is now
    std::fs::write(
        anchors.join("state.head"),
        format!("999 {}\n", "00".repeat(32)),
    )
    .unwrap();
    let e = open_daemon(cfg(&anchors).unwrap(), exe.clone())
        .err()
        .expect("refused");
    assert!(e.to_string().contains("anchor"), "{e}");
    // a deleted anchor is refused too, until `wyrmd init-anchors`
    std::fs::remove_file(anchors.join("state.head")).unwrap();
    assert!(open_daemon(cfg(&anchors).unwrap(), exe.clone()).is_err());
    let mut init = cfg(&anchors).unwrap();
    init.init_anchors = true;
    drop(open_daemon(init, exe.clone()).unwrap());
    drop(open_daemon(cfg(&anchors).unwrap(), exe).unwrap());
}

/// T11 / runtime edits: a runtime-installed link's params can be updated
/// (validated, linted, restarted), listed and rolled back; config links are
/// edited in wyrmd.json5.
#[tokio::test(flavor = "multi_thread")]
async fn link_params_update_history_rollback() {
    let env = Env::start("linkhist", MOCK).await;
    let c = env.client().await;
    let links = format!("wy/{SITE}/sys/links");
    let m = |kv: &[(&str, Value)]| {
        Value::Map(
            kv.iter()
                .map(|(k, v)| ((*k).to_owned(), v.clone()))
                .collect(),
        )
    };
    let mock = |points: u64| {
        m(&[
            ("points", Value::UInt(points)),
            ("rate_hz", Value::Float(1.0)),
            ("depth", Value::UInt(0)),
            ("fanout", Value::UInt(1)),
        ])
    };
    let install = m(&[
        ("id", Value::from("m2")),
        ("driver", Value::from("mock")),
        ("params", mock(2)),
    ]);
    c.invoke_one(&links, "install", install).await.unwrap();
    let node = format!("{links}/m2");
    let count = |n: usize| {
        let c = &c;
        async move {
            eventually("children", 10, || async {
                let ch = c.children(&format!("wy/{SITE}/downstream/m2")).await.ok()?;
                (ch.len() == n).then_some(())
            })
            .await
        }
    };
    count(2).await;
    let rev = c
        .invoke_one(&node, "update", m(&[("params", mock(3))]))
        .await
        .unwrap();
    assert_eq!(rev, Some(Value::UInt(2)));
    count(3).await;
    // secret-like params are refused, nothing changes
    let bad = m(&[("params", m(&[("password", Value::from("x"))]))]);
    assert!(c.invoke_one(&node, "update", bad).await.is_err());
    let Some(Value::Array(h)) = c.invoke_one(&node, "history", m(&[])).await.unwrap() else {
        panic!("history")
    };
    assert_eq!(h.len(), 2, "rev 1 and current rev 2");
    let rev = c
        .invoke_one(&node, "rollback", m(&[("rev", Value::UInt(1))]))
        .await
        .unwrap();
    assert_eq!(rev, Some(Value::UInt(3)));
    count(2).await;
    // a link from wyrmd.json5 is edited there
    assert!(c
        .invoke_one(
            &format!("{links}/mock"),
            "update",
            m(&[("params", mock(1))])
        )
        .await
        .is_err());
    env.stop().await;
}

/// `wyrmd verify`: every store checks out after a normal run; one flipped
/// byte in the audit WAL is reported (T11, P29).
#[test]
fn verify_state_finds_a_tampered_wal() {
    let dir = temp_dir("verify");
    let cfg = || {
        Config::from_json5(&format!(
            r#"{{ site: "{SITE}", data_dir: "{}", listen: ["tcp/127.0.0.1:{}"], {MOCK} }}"#,
            dir.display(),
            free_port()
        ))
        .unwrap()
    };
    drop(open_daemon(cfg(), env!("CARGO_BIN_EXE_wyrmd").into()).unwrap());
    let checks = wyrmd::verify_state(&cfg());
    assert!(checks.iter().any(|c| c.name == "registry"));
    assert!(checks.iter().all(|c| c.ok()), "clean stores");
    // flip one byte of the first audit WAL record's payload
    let wal = std::fs::read_dir(dir.join("audit"))
        .unwrap()
        .flatten()
        .map(|e| e.path())
        .find(|p| p.extension().is_some_and(|x| x == "wyw"))
        .unwrap();
    let mut b = std::fs::read(&wal).unwrap();
    if b.len() > 50 {
        b[45] ^= 1;
        std::fs::write(&wal, b).unwrap();
        let checks = wyrmd::verify_state(&cfg());
        let audit = checks.iter().find(|c| c.name == "audit").unwrap();
        assert!(!audit.ok(), "tampering found");
    }
}

/// The subscriber gate of a process link: the `~val` storage subscribes to
/// `wy/**/~val`, which the link ACL (`wy/S/downstream/L/**`) does not pass on, so
/// with `poll_unsubscribed: false` the link polls only while a real
/// subscriber (one point or a pattern under `downstream/**`) exists. Embedded
/// links share the router with the storage, so for them the gate is
/// always open (the default is to poll all the time anyway).
#[tokio::test(flavor = "multi_thread")]
async fn process_link_polls_only_while_subscribed() {
    let (addr, dev, _task) = wyrm_link_modbus::sim::spawn("127.0.0.1:0").await.unwrap();
    let env = Env::start(
        "gate",
        &format!(
            r#"links: {{ plc1: {{ driver: "modbus", mode: "process", params: {{ poll_unsubscribed: false, connections: {{ c1: {{
                host: "127.0.0.1", port: {},
                devices: {{ ahu1: {{ unit: 1, points: {{
                  supply_temp: {{ table: "input", addr: 1, dtype: "i16", scale: 0.1, poll_s: 0.05 }},
                }} }} }},
            }} }} }} }} }},"#,
            addr.port()
        ),
    )
    .await;
    let c = env.client().await;
    let state = format!("wy/{SITE}/sys/links/plc1/state");
    eventually("plc1 connected", 15, || async {
        (last_val(&c, &state).await == Some(Value::UInt(2))).then_some(())
    })
    .await;
    let reqs = || dev.lock().unwrap().requests;
    tokio::time::sleep(Duration::from_secs(2)).await;
    let r0 = reqs();
    tokio::time::sleep(Duration::from_secs(1)).await;
    let idle = reqs() - r0;
    let node = format!("wy/{SITE}/downstream/plc1/c1/ahu1/supply_temp");
    let _s = c.subscribe(&node).await.unwrap();
    tokio::time::sleep(Duration::from_secs(2)).await;
    let r1 = reqs();
    tokio::time::sleep(Duration::from_secs(1)).await;
    let exact = reqs() - r1;
    let pat = format!("wy/{SITE}/downstream/**");
    drop(_s);
    let _p = c.subscribe(&pat).await.unwrap();
    tokio::time::sleep(Duration::from_secs(2)).await;
    let r2 = reqs();
    tokio::time::sleep(Duration::from_secs(1)).await;
    let pattern = reqs() - r2;
    assert_eq!(idle, 0, "no subscriber, no polling");
    assert!(exact >= 5, "one point subscribed: {exact} requests/s");
    assert!(
        pattern >= 5,
        "downstream/** subscribed: {pattern} requests/s"
    );
    env.stop().await;
}

/// Principle 3: a framework link keeps its runtime edits (and the secrets
/// in them) in its own `data_dir`, sealed with the store key the admin
/// hands it; a broker restart brings them back.
#[tokio::test(flavor = "multi_thread")]
async fn process_link_keeps_runtime_edits() {
    let dir = temp_dir("keep-edits");
    let links =
        r#"links: { dev1: { driver: "mockdev", mode: "process", params: { connections: {} } } },"#;
    let env = Env::start_in(&dir, links).await;
    let c = env.client().await;
    let root = format!("wy/{SITE}/downstream/dev1");
    eventually("dev1 up", 15, || async { c.meta(&root).await.ok() }).await;
    let args = Value::Map(BTreeMap::from([
        ("name".to_owned(), Value::from("c2")),
        ("need_token".to_owned(), Value::Bool(true)),
        ("token".to_owned(), Value::from("pw-123456")),
    ]));
    c.invoke_one(&root, "add_connection", args).await.unwrap();
    env.stop().await;
    let sealed = std::fs::read(dir.join("links/dev1/data/framework.tree")).unwrap();
    assert!(!sealed.windows(9).any(|w| w == b"pw-123456"));

    let env = Env::start_in(&dir, links).await;
    let c = env.client().await;
    let status = format!("{root}/c2/status");
    eventually("c2 back and connected", 15, || async {
        match last_val(&c, &status).await {
            // `status` is an enum leaf; 2 = Connected
            Some(Value::UInt(2)) => Some(()),
            _ => None,
        }
    })
    .await;
    env.stop().await;
}

/// Downstream brokers come in as DSA links do (ADR 0015). No peers in
/// either `wyrmd.json5` (central has `peers.listen` and `peers.enroll`).
/// The edge adds central (Add Upstream Connection), asks for its
/// certificate and waits in central's quarantine with its key's SHA-256;
/// another key for that name only counts; Authorize lets it in. Deauthorize
/// holds it (its certificate still connects, gets nothing; the name never
/// becomes an upstream); Authorize again. A token admits at once (once);
/// `allow_all_links` admits a broker whose relayed sites are free.
#[tokio::test(flavor = "multi_thread")]
async fn runtime_peers_over_quic() {
    let key = ed25519_dalek::SigningKey::from_bytes(&SEED);
    let admin = hex::encode(key.verifying_key().to_bytes());
    let (c_dir, e_dir) = (temp_dir("rt-central"), temp_dir("rt-edge"));
    let (c_tcp, c_quic, c_enroll, e_tcp) = (free_port(), free_port(), free_port(), free_port());
    let central = Config::from_json5(&format!(
        r#"{{ site: "central", data_dir: "{}", listen: ["tcp/127.0.0.1:{c_tcp}"],
              admin_keys: ["{admin}"],
              peers: {{ listen: "quic/127.0.0.1:{c_quic}", enroll: "quic/127.0.0.1:{c_enroll}" }} }}"#,
        c_dir.display()
    ))
    .unwrap();
    let edge = Config::from_json5(&format!(
        r#"{{ site: "edge", data_dir: "{}", listen: ["tcp/127.0.0.1:{e_tcp}"],
              admin_keys: ["{admin}"], {MOCK} }}"#,
        e_dir.display()
    ))
    .unwrap();
    let exe: PathBuf = env!("CARGO_BIN_EXE_wyrmd").into();
    let central = open_daemon(central, exe.clone()).unwrap();
    let edge = open_daemon(edge, exe).unwrap();
    let (c_ctl, e_ctl) = (central.control(), edge.control());
    let (c_stop, c_rx) = oneshot::channel::<()>();
    let (e_stop, e_rx) = oneshot::channel::<()>();
    let c_task = tokio::spawn(central.run_until(async {
        let _ = c_rx.await;
    }));
    let e_task = tokio::spawn(edge.run_until(async {
        let _ = e_rx.await;
    }));
    // a fresh client per try: every peer change rebuilds that router
    let client = |port: u16, site: &'static str| {
        let key = key.clone();
        async move {
            WyrmClient::new(loopback_session(port).await)
                .with_tokens(Arc::new(SigningTokens::new(key, site)))
                .with_timeout(Duration::from_secs(3))
        }
    };
    let args = |pairs: &[(&str, Value)]| {
        Value::Map(
            pairs
                .iter()
                .map(|(k, v)| (k.to_string(), v.clone()))
                .collect(),
        )
    };
    let text = |v: Option<Value>| match v {
        Some(Value::Str(s)) => s,
        other => panic!("{other:?}"),
    };
    let edge_seen = |what: &'static str| {
        eventually(what, 20, move || async move {
            let c = client(c_tcp, "edge").await;
            let ch = c.children("wy/edge/downstream").await.ok()?;
            ch.iter().any(|c| c.name == "mock").then_some(())
        })
    };
    let edge_gone = |what: &'static str| {
        eventually(what, 20, move || async move {
            let c = client(c_tcp, "edge").await;
            match c.children("wy/edge/downstream").await {
                Ok(ch) if !ch.is_empty() => None,
                _ => Some(()),
            }
        })
    };
    let ca = std::fs::read_to_string(c_dir.join("pki/ca.pem")).unwrap();
    let enroll_url = format!("quic/127.0.0.1:{c_enroll}");
    // A broker without a session of its own: one request on the enrollment
    // endpoint, as a downstream broker sends it.
    let ask_with = |site: &'static str,
                    key: Option<String>,
                    token: Option<String>,
                    via: &'static [&'static str]| {
        let (ca_file, url) = (c_dir.join("pki/ca.pem"), enroll_url.clone());
        async move {
            let key = match key {
                Some(k) => k,
                None => wyrm_admin::secret::new_broker_key().unwrap().0.to_string(),
            };
            let csr = wyrm_admin::secret::broker_csr(site, &key).unwrap();
            let mut zc = zenoh::Config::default();
            zc.insert_json5("mode", r#""client""#).unwrap();
            zc.insert_json5("connect/endpoints", &format!(r#"["{url}"]"#))
                .unwrap();
            zc.insert_json5("scouting/multicast/enabled", "false")
                .unwrap();
            zc.insert_json5(
                "transport/link/tls",
                &serde_json::json!({ "root_ca_certificate": ca_file, "enable_mtls": false })
                    .to_string(),
            )
            .unwrap();
            let s = zenoh::open(zc).await.unwrap();
            let mut a = vec![
                ("site".to_string(), Value::from(site)),
                ("csr".to_string(), Value::from(csr.as_str())),
                (
                    "via".to_string(),
                    Value::Array(via.iter().map(|v| Value::from(*v)).collect()),
                ),
            ];
            if let Some(t) = token {
                a.push(("token".to_string(), Value::from(t.as_str())));
            }
            let r = WyrmClient::new(s.clone())
                .with_timeout(Duration::from_secs(3))
                .invoke_one(
                    "wy/central/sys",
                    "enroll",
                    Value::Map(a.into_iter().collect()),
                )
                .await;
            let _ = s.close().await;
            r
        }
    };
    let ask = |site: &'static str, token: Option<String>, via: &'static [&'static str]| {
        ask_with(site, None, token, via)
    };
    let status = |r: &Result<Option<Value>, wyrm_client::ClientError>| match r {
        Ok(Some(Value::Map(m))) => match m.get("status") {
            Some(Value::Str(s)) => s.clone(),
            other => format!("{other:?}"),
        },
        other => format!("{other:?}"),
    };

    // 1. The edge adds central: wrong inputs are refused.
    let e = client(e_tcp, "edge").await;
    let up_add = |ca: &str, url: &str, token: Option<&str>| {
        let mut a = vec![
            ("name", Value::from("central")),
            ("url", Value::from(url)),
            ("ca", Value::from(ca)),
        ];
        if let Some(t) = token {
            a.push(("token", Value::from(t)));
        }
        args(&a)
    };
    for (ca, url, why) in [
        ("not a pem", enroll_url.as_str(), "CA"),
        (ca.as_str(), "tcp/127.0.0.1:1", "url"),
    ] {
        let err = e
            .invoke_one("wy/edge/sys/upstream", "add", up_add(ca, url, None))
            .await
            .expect_err(why);
        assert!(err.is(wyrm_core::Status::InvalidParameter), "{why}: {err}");
    }
    e.invoke_one(
        "wy/edge/sys/upstream",
        "add",
        up_add(&ca, &enroll_url, None),
    )
    .await
    .expect("add the upstream");

    // 2. It waits in central's quarantine, the same key on both sides.
    eventually("the edge waits in quarantine", 20, || async {
        c_ctl
            .registry()
            .enrollments
            .contains_key("edge")
            .then_some(())
    })
    .await;
    let e = client(e_tcp, "edge").await;
    let edge_key = text(last_val(&e, "wy/edge/sys/upstream/central/key").await);
    let c = client(c_tcp, "central").await;
    let q = c.meta("wy/central/sys/quarantine/edge").await.unwrap();
    assert_eq!(q.attr_value("kind"), Some(&Value::Str("broker".into())));
    assert_eq!(q.attr_value("key"), Some(&Value::Str(edge_key.clone())));
    eventually("the edge shows it waits", 20, || async {
        let e = client(e_tcp, "edge").await;
        let s = text(last_val(&e, "wy/edge/sys/upstream/central/status").await);
        s.starts_with("pending").then_some(())
    })
    .await;
    // another key for a waiting name: refused, counted (in memory: shown,
    // not written), never swapped in
    for _ in 0..2 {
        assert_eq!(status(&ask("edge", None, &[]).await), "refused");
    }
    let waiting = c_ctl.registry().enrollments["edge"].clone();
    assert_eq!(
        (waiting.key_sha256.as_str(), waiting.conflicts),
        (edge_key.as_str(), 0)
    );
    let q = c.meta("wy/central/sys/quarantine/edge").await.unwrap();
    assert_eq!(q.attr_value("conflicts"), Some(&Value::UInt(2)));
    // polls of a waiting request write nothing after the first
    let (cell_key, _) = wyrm_admin::secret::new_broker_key().unwrap();
    for _ in 0..3 {
        let r = ask_with("cell5", Some(cell_key.to_string()), None, &[]).await;
        assert_eq!(status(&r), "pending");
    }
    assert_eq!(c_ctl.registry().quarantine["broker:cell5"].attempts, 1);

    // 3. Authorize, bound to the key the administrator compared: another
    // key is refused; with it the edge gets its certificate and connects.
    let wrong = c
        .invoke_one(
            "wy/central/sys/quarantine/edge",
            "approve",
            args(&[("key", Value::from("00"))]),
        )
        .await;
    assert!(wrong.is_err(), "authorize with another key");
    c.invoke_one(
        "wy/central/sys/quarantine/edge",
        "approve",
        args(&[("key", Value::from(edge_key.as_str()))]),
    )
    .await
    .expect("authorize");
    edge_seen("edge links seen from central").await;
    let e = client(e_tcp, "edge").await;
    let mut shown: Vec<String> = e
        .children("wy/edge/sys/upstream/central")
        .await
        .unwrap()
        .into_iter()
        .map(|c| c.name)
        .collect();
    shown.sort();
    assert_eq!(
        shown,
        [
            "allow_config",
            "ca",
            "certificate",
            "enabled",
            "key",
            "status",
            "url"
        ]
    );
    assert_eq!(
        text(last_val(&e, "wy/edge/sys/upstream/central/status").await),
        "issued"
    );
    let summary = text(last_val(&e, "wy/edge/sys/upstream/central/certificate").await);
    assert!(
        summary.starts_with("broker:edge, valid until "),
        "{summary}"
    );
    assert!(!format!("{:?}", e_ctl.registry()).contains("PRIVATE KEY"));
    assert_eq!(c_ctl.registry().peers["edge"].key_sha256, edge_key);

    // 4. Disabled: the edge drops the connection; enabled: back.
    e.set("wy/edge/sys/upstream/central/enabled", false)
        .await
        .unwrap();
    edge_gone("edge gone from central").await;
    let e = client(e_tcp, "edge").await;
    e.set("wy/edge/sys/upstream/central/enabled", true)
        .await
        .unwrap();
    edge_seen("edge back after enable").await;

    // 5. Deauthorize (a downstream broker is in its list): held.
    let c = client(c_tcp, "central").await;
    c.invoke_one(
        "wy/central/sys/quarantine",
        "deauthorize",
        args(&[("link", Value::from("edge"))]),
    )
    .await
    .expect("deauthorize the edge");
    assert!(c_ctl.registry().held.contains("broker:edge"));
    edge_gone("deauthorized edge gone from central").await;
    eventually("the edge's sessions land in quarantine", 20, || async {
        let q = c_ctl.registry().quarantine.get("broker:edge").cloned()?;
        (q.attempts > 0).then_some(())
    })
    .await;
    let c = client(c_tcp, "central").await;
    let err = c
        .invoke_one(
            "wy/central/sys/upstream",
            "add",
            args(&[
                ("name", Value::from("edge")),
                ("url", Value::from(enroll_url.as_str())),
                ("ca", Value::from(ca.as_str())),
            ]),
        )
        .await
        .expect_err("an issued name is never an upstream");
    assert!(err.to_string().contains("downstream broker"), "{err}");
    c.invoke_one(
        "wy/central/sys/quarantine/edge",
        "approve",
        args(&[("key", Value::from(edge_key.as_str()))]),
    )
    .await
    .expect("authorize again");
    edge_seen("edge back after Authorize").await;

    // 6. A token admits at once, once.
    let c = client(c_tcp, "central").await;
    let token = match c
        .invoke_one(
            "wy/central/sys/tokens",
            "add",
            args(&[("count", Value::UInt(1))]),
        )
        .await
        .unwrap()
    {
        Some(Value::Map(m)) => text(m.get("token").cloned()),
        other => panic!("{other:?}"),
    };
    assert!(!format!("{:?}", c_ctl.registry()).contains(&token));
    let r = ask("plant", Some(token.clone()), &[]).await;
    assert_eq!(status(&r), "issued");
    assert!(c_ctl.registry().peers.contains_key("plant"));
    assert!(c_ctl.registry().tokens.is_empty(), "used up");
    assert_eq!(status(&ask("cell", Some(token), &[]).await), "pending");

    // 7. allow_all_links admits a broker whose relayed sites are free.
    c.set("wy/central/sys/allow_all_links", true).await.unwrap();
    assert_eq!(status(&ask("cell2", None, &["far"]).await), "issued");
    assert_eq!(c_ctl.registry().peers["cell2"].via, ["far"]);
    assert_eq!(status(&ask("cell3", None, &["edge"]).await), "pending");
    c.set("wy/central/sys/allow_all_links", false)
        .await
        .unwrap();

    let e_audit = e_ctl.audit_tail(50);
    for op in ["peer_add", "peer_enable", "peer_cert"] {
        assert!(e_audit.iter().any(|r| r.op == op), "edge audit has {op}");
    }
    let c_audit = c_ctl.audit_tail(100);
    for op in [
        "quarantine",
        "approve",
        "deauthorize",
        "enroll_token",
        "auto_install",
    ] {
        assert!(c_audit.iter().any(|r| r.op == op), "central audit has {op}");
    }
    // 8. allow_config at runtime (ADR 0018): edge lets central run its sys
    //    actions once it rebuilds.
    let from_central = || async {
        client(c_tcp, "edge")
            .await
            .invoke_one("wy/edge/sys", "get_permissions", args(&[]))
            .await
    };
    assert!(from_central().await.is_err(), "not allowed yet");
    client(e_tcp, "edge")
        .await
        .set("wy/edge/sys/upstream/central/allow_config", true)
        .await
        .expect("allow_config");
    assert!(e_ctl.registry().peers["central"].allow_config);
    eventually("central runs an edge sys action", 30, || async {
        from_central().await.ok()
    })
    .await;

    let e = client(e_tcp, "edge").await;
    e.invoke_one("wy/edge/sys/upstream/central", "remove", args(&[]))
        .await
        .expect("remove");
    assert!(e_ctl.registry().peers.is_empty());
    assert!(!e_dir.join("pki/peers/central.key").exists());

    let _ = c_stop.send(());
    let _ = e_stop.send(());
    c_task.await.unwrap().unwrap();
    e_task.await.unwrap().unwrap();
    drop((c_ctl, e_ctl));

    // The operator moves the runtime downstream into wyrmd.json5: the config
    // wins, the registry entry goes, and the router (no repeated ACL ids)
    // starts.
    let central = Config::from_json5(&format!(
        r#"{{ site: "central", data_dir: "{}", listen: ["tcp/127.0.0.1:{c_tcp}"],
              admin_keys: ["{admin}"], peers: {{ listen: "quic/127.0.0.1:{c_quic}",
              downstream: [{{ site: "edge" }}] }} }}"#,
        c_dir.display(),
    ))
    .unwrap();
    let central = open_daemon(central, env!("CARGO_BIN_EXE_wyrmd").into()).unwrap();
    let c_ctl = central.control();
    assert!(!c_ctl.registry().peers.contains_key("edge"), "json5 wins");
    assert_eq!(
        c_ctl.peers().downstream.first().map(String::as_str),
        Some("edge")
    );
    let (c_stop, c_rx) = oneshot::channel::<()>();
    let c_task = tokio::spawn(central.run_until(async {
        let _ = c_rx.await;
    }));
    eventually("central up with edge from json5", 10, || async {
        let c = client(c_tcp, "central").await;
        c.meta("wy/central/downstream/edge").await.ok()
    })
    .await;
    let _ = c_stop.send(());
    c_task.await.unwrap().unwrap();
}

/// The enrollment listener (ADR 0015): server-auth TLS only. A session
/// there without a client certificate may ask `sys/~act/enroll` and get the
/// reply, nothing else: no other query, subscription or put.
#[tokio::test(flavor = "multi_thread")]
async fn enroll_listener_reaches_one_key() {
    let (c_dir, c_tcp, c_quic, c_enroll) =
        (temp_dir("enroll"), free_port(), free_port(), free_port());
    let central = Config::from_json5(&format!(
        r#"{{ site: "central", data_dir: "{}", listen: ["tcp/127.0.0.1:{c_tcp}"],
              peers: {{ listen: "quic/127.0.0.1:{c_quic}", enroll: "quic/127.0.0.1:{c_enroll}" }},
              {MOCK} }}"#,
        c_dir.display()
    ))
    .unwrap();
    let (c_stop, c_task) = spawn_daemon(central);
    let local = loopback_session(c_tcp).await;
    eventually("central up", 10, || async {
        (!replies(&local, "wy/central/sys/~meta").await.is_empty()).then_some(())
    })
    .await;

    let mut zc = zenoh::Config::default();
    zc.insert_json5("mode", r#""client""#).unwrap();
    zc.insert_json5(
        "connect/endpoints",
        &format!(r#"["quic/127.0.0.1:{c_enroll}"]"#),
    )
    .unwrap();
    zc.insert_json5("scouting/multicast/enabled", "false")
        .unwrap();
    zc.insert_json5(
        "transport/link/tls",
        &serde_json::json!({
            "root_ca_certificate": c_dir.join("pki/ca.pem"),
            "enable_mtls": false,
        })
        .to_string(),
    )
    .unwrap();
    let anon = zenoh::open(zc).await.unwrap();
    // the one key: the admin answers (here an error: no such action yet)
    assert!(
        !replies(&anon, "wy/central/sys/~act/enroll")
            .await
            .is_empty(),
        "enroll query answered"
    );
    for key in [
        "wy/central/sys/~meta",
        "wy/central/downstream/**",
        "wy/central/downstream/mock/~meta",
        "wy/central/sys/~act/hello",
    ] {
        assert_eq!(replies(&anon, key).await, Vec::<String>::new(), "{key}");
    }
    let (seen, control) = tokio::join!(
        samples(&anon, "wy/central/downstream/**", 2),
        samples(&local, "wy/central/downstream/**", 2)
    );
    assert!(!control.is_empty(), "control: the mock publishes");
    assert_eq!(
        seen,
        Vec::<String>::new(),
        "no samples without a certificate"
    );
    let watch = local
        .declare_subscriber("wy/central/downstream/mock/forged/**")
        .await
        .unwrap();
    anon.put("wy/central/downstream/mock/forged/~val", "x")
        .await
        .unwrap();
    let forged = tokio::time::timeout(Duration::from_secs(1), watch.recv_async()).await;
    assert!(forged.is_err(), "a put without a certificate arrived");

    let _ = anon.close().await;
    let _ = local.close().await;
    let _ = c_stop.send(());
    c_task.await.unwrap().unwrap();
}

/// Runs one daemon until the returned sender fires.
fn spawn_daemon(
    cfg: Config,
) -> (
    oneshot::Sender<()>,
    tokio::task::JoinHandle<Result<(), wyrmd::Error>>,
) {
    let d = open_daemon(cfg, env!("CARGO_BIN_EXE_wyrmd").into()).unwrap();
    let (tx, rx) = oneshot::channel::<()>();
    let task = tokio::spawn(async move {
        let r = d
            .run_until(async {
                let _ = rx.await;
            })
            .await;
        // A test that fails to connect shows why the broker is gone (for
        // example a listener port in use) next to its own panic.
        if let Err(e) = &r {
            eprintln!("wyrmd ended with an error: {e}");
        }
        r
    });
    (tx, task)
}

/// Plain client session to a loopback `tcp/` listener.
async fn loopback_session(port: u16) -> zenoh::Session {
    let mut zc = zenoh::Config::default();
    zc.insert_json5("mode", r#""client""#).unwrap();
    zc.insert_json5("connect/endpoints", &format!(r#"["tcp/127.0.0.1:{port}"]"#))
        .unwrap();
    zc.insert_json5("scouting/multicast/enabled", "false")
        .unwrap();
    zc.insert_json5("connect/timeout_ms", "5000").unwrap();
    zenoh::open(zc).await.unwrap()
}

/// Ok replies to `get key` within 2 s.
async fn replies(s: &zenoh::Session, key: &str) -> Vec<String> {
    let r = s
        .get(key)
        .consolidation(zenoh::query::ConsolidationMode::None)
        .timeout(Duration::from_secs(2))
        .await
        .unwrap();
    let mut out = Vec::new();
    while let Ok(reply) = r.recv_async().await {
        if let Ok(smp) = reply.result() {
            out.push(smp.key_expr().to_string());
        }
    }
    out
}

/// Samples seen on `key` during `secs` seconds.
async fn samples(s: &zenoh::Session, key: &str, secs: u64) -> Vec<String> {
    let sub = s.declare_subscriber(key).await.unwrap();
    let mut seen = Vec::new();
    let _ = tokio::time::timeout(Duration::from_secs(secs), async {
        while let Ok(smp) = sub.recv_async().await {
            seen.push(smp.key_expr().to_string());
        }
    })
    .await;
    let _ = sub.undeclare().await;
    seen
}

/// ADR 0007 boundaries between real brokers (T12):
/// 1. the upstream reads `downstream/**` and `sys/**` (`~meta`, `~val`) of the
///    downstream site, never a `sys` action (owner decision 2026-10-22);
/// 2. the upstream's commands reach the edge's devices (ADR 0018) with a
///    token the edge trusts, never its `sys` without `allow_config`;
/// 3. the downstream cannot write or query outside its own `wy/<edge>/**`;
/// 4. a broker with a certificate from an untrusted CA cannot join, even
///    with a configured site name (`broker:edge`);
/// 5. a certificate of central's own CA for a link name (not `broker:*`)
///    over QUIC gets nothing and is not quarantined (ADR 0015).
#[tokio::test(flavor = "multi_thread")]
async fn two_brokers_isolation() {
    let key = ed25519_dalek::SigningKey::from_bytes(&SEED);
    let admin = hex::encode(key.verifying_key().to_bytes());
    let (c_dir, e_dir, r_dir) = (
        temp_dir("iso-central"),
        temp_dir("iso-edge"),
        temp_dir("iso-rogue"),
    );
    let (c_tcp, c_quic, e_tcp, r_tcp) = (free_port(), free_port(), free_port(), free_port());
    let central = Config::from_json5(&format!(
        r#"{{
            site: "central",
            data_dir: "{}",
            listen: ["tcp/127.0.0.1:{c_tcp}"],
            admin_keys: ["{admin}"],
            peers: {{
                listen: "quic/127.0.0.1:{c_quic}",
                downstream: [{{ site: "edge" }}],
            }},
        }}"#,
        c_dir.display(),
    ))
    .unwrap();
    // The edge runs `dev` so a loopback client there may publish and query
    // anything: the only thing that stops it is the central broker's ACL.
    // `id`: the certificate it connects with, `<dir>/<id>.{pem,key}`.
    let edge_cfg = |dir: &std::path::Path, port: u16, link: &str, id: &std::path::Path| {
        Config::from_json5(&format!(
            r#"{{
                site: "edge",
                profile: "dev",
                data_dir: "{}",
                listen: ["tcp/127.0.0.1:{port}"],
                admin_keys: ["{admin}"],
                metrics_interval_ms: 200,
                peers: {{
                    upstream: [{{ site: "central", endpoint: "quic/127.0.0.1:{c_quic}", ca: "{}",
                                  cert: "{}.pem", key: "{}.key" }}],
                }},
                links: {{ {link}: {{ driver: "mock", params: {{ points: 2, rate_hz: 20, depth: 1, fanout: 2 }} }} }},
            }}"#,
            dir.display(),
            c_dir.join("pki/ca.pem").display(),
            id.display(),
            id.display(),
        ))
        .unwrap()
    };
    // Central first: opening it issues the edge's certificate.
    let exe: PathBuf = env!("CARGO_BIN_EXE_wyrmd").into();
    let central = open_daemon(central, exe.clone()).unwrap();
    let c_ctl = central.control();
    let issued = c_dir.join("peers/edge/broker");
    let edge = open_daemon(edge_cfg(&e_dir, e_tcp, "mock", &issued), exe).unwrap();
    let (c_stop, c_rx) = oneshot::channel::<()>();
    let (e_stop, e_rx) = oneshot::channel::<()>();
    let c_task = tokio::spawn(central.run_until(async {
        let _ = c_rx.await;
    }));
    let e_task = tokio::spawn(edge.run_until(async {
        let _ = e_rx.await;
    }));

    let cs = loopback_session(c_tcp).await;
    let c = WyrmClient::new(cs.clone())
        .with_tokens(Arc::new(SigningTokens::new(key.clone(), "edge")))
        .with_timeout(Duration::from_secs(3));
    eventually("edge links seen from central", 15, || {
        let c = &c;
        async move { (!c.children("wy/edge/downstream").await.ok()?.is_empty()).then_some(()) }
    })
    .await;

    // 1. downstream/** and sys/** are readable from central (~meta, ~val), sys
    //    actions and any other suffix are not.
    assert!(
        !replies(&cs, "wy/edge/downstream/mock/**/~meta")
            .await
            .is_empty(),
        "control: central reads the edge's downstream/**"
    );
    assert!(
        !replies(&cs, "wy/edge/sys/**/~meta").await.is_empty(),
        "central reads the edge's sys/** (DSA upstream)"
    );
    for k in [
        "wy/edge/sys/**",
        "wy/edge/sys/links/**",
        "wy/edge/sys/audit/**",
        "wy/edge/sys/~act/get_log",
        "wy/edge/sys/audit/~act/tail",
    ] {
        assert_eq!(replies(&cs, k).await, Vec::<String>::new(), "query {k}");
    }
    // The edge publishes its metrics every 200 ms: their values reach
    // central (as clients subscribe, `<pattern>/~val`); a subscription to
    // all of sys/** gets nothing else, so no other key under sys (audit
    // records, checked in 3.) goes up.
    let (down, sys, raw) = tokio::join!(
        samples(&cs, "wy/edge/downstream/**", 2),
        samples(&cs, "wy/edge/sys/**/~val", 2),
        samples(&cs, "wy/edge/sys/**", 2)
    );
    assert!(!down.is_empty(), "control: edge values reach central");
    assert!(!sys.is_empty(), "edge sys values reach central");
    assert!(
        raw.iter()
            .all(|k| k.ends_with("/~val") || k.ends_with("/~meta")),
        "only values and metadata of edge sys/** at central: {:?}",
        raw.iter().find(|k| !k.ends_with("/~val"))
    );

    // 2. Commands from above reach the edge's devices (ADR 0018); its sys
    //    actions stay closed (no allow_config, the queries in 1.).
    let args = Value::Map(BTreeMap::from([("n".to_owned(), Value::UInt(1))]));
    eventually("a command from above", 20, || async {
        c.invoke_one("wy/edge/downstream/mock", "count", args.clone())
            .await
            .ok()
    })
    .await;
    assert!(c
        .invoke_one(
            "wy/edge/sys",
            "get_permissions",
            Value::Map(BTreeMap::new())
        )
        .await
        .is_err());

    // 3. The edge's loopback client may do anything on the edge (dev), but
    //    central accepts from `broker:edge` only `wy/edge/**`.
    let es = loopback_session(e_tcp).await;
    assert!(
        !samples(&es, "wy/edge/sys/**", 1).await.is_empty(),
        "control: the edge does publish sys/**"
    );
    let watch_central = samples(&cs, "wy/central/**", 3);
    let watch_other = samples(&cs, "wy/other/**", 3);
    // audit records of the edge's links stay on the edge (only ~val and
    // ~meta of sys go up)
    let watch_audit = samples(&cs, "wy/edge/sys/audit/**", 3);
    let forge = async {
        tokio::time::sleep(Duration::from_millis(500)).await;
        for _ in 0..10 {
            es.put("wy/central/downstream/x/~val", sample(1.0))
                .await
                .unwrap();
            es.put("wy/other/downstream/x/~val", sample(1.0))
                .await
                .unwrap();
            es.put("wy/edge/sys/audit/mock", sample(1.0)).await.unwrap();
            tokio::time::sleep(Duration::from_millis(100)).await;
        }
    };
    let (central_seen, other_seen, audit_seen, ()) =
        tokio::join!(watch_central, watch_other, watch_audit, forge);
    assert_eq!(
        audit_seen,
        Vec::<String>::new(),
        "edge audit records at central"
    );
    assert_eq!(
        central_seen,
        Vec::<String>::new(),
        "edge wrote into wy/central"
    );
    assert_eq!(other_seen, Vec::<String>::new(), "edge wrote into wy/other");
    for k in ["wy/central/sys/**", "wy/central/downstream/**"] {
        assert_eq!(
            replies(&es, k).await,
            Vec::<String>::new(),
            "edge queried {k}"
        );
    }

    // 4. A rogue broker that calls itself `edge` (CN `broker:edge`), with a
    //    certificate from its own CA, does not get in.
    let own_ca = r_dir.join("pki/broker-client");
    let (r_stop, r_task) = spawn_daemon(edge_cfg(&r_dir, r_tcp, "evil", &own_ca));
    let rs = loopback_session(r_tcp).await;
    let (evil, own) = tokio::join!(
        samples(&cs, "wy/edge/downstream/evil/**", 4),
        samples(&rs, "wy/edge/downstream/evil/**", 4)
    );
    assert!(
        !own.is_empty(),
        "control: the rogue broker runs and publishes"
    );
    assert_eq!(evil, Vec::<String>::new(), "rogue samples reached central");
    let names: Vec<String> = c
        .children("wy/edge/downstream")
        .await
        .unwrap()
        .into_iter()
        .map(|c| c.name)
        .collect();
    assert_eq!(names, ["mock", "scheduler"], "rogue link listed at central");
    let _ = rs.close().await;
    let _ = r_stop.send(());
    r_task.await.unwrap().unwrap();

    // 5. The same rogue with a certificate of central's CA for a link name:
    //    TLS passes, but no QUIC subject matches it and it is no broker.
    let link = c_ctl.link_cert("plc9").unwrap();
    let id = link.cert.with_extension("");
    let (r_stop, r_task) = spawn_daemon(edge_cfg(&r_dir, r_tcp, "evil", &id));
    let rs = loopback_session(r_tcp).await;
    let (evil, own) = tokio::join!(
        samples(&cs, "wy/edge/downstream/evil/**", 4),
        samples(&rs, "wy/edge/downstream/evil/**", 4)
    );
    assert!(!own.is_empty(), "control: the second rogue runs");
    assert_eq!(evil, Vec::<String>::new(), "link certificate over QUIC");
    assert!(
        c_ctl.registry().quarantine.is_empty(),
        "nothing quarantined: {:?}",
        c_ctl.registry().quarantine
    );

    let _ = rs.close().await;
    let _ = es.close().await;
    let _ = cs.close().await;
    let _ = r_stop.send(());
    let _ = e_stop.send(());
    r_task.await.unwrap().unwrap();
    e_task.await.unwrap().unwrap();
    let _ = c_stop.send(());
    c_task.await.unwrap().unwrap();
}

/// The embedded historian (ADR 0014): a watch group records a mock point,
/// Get History answers raw rows and rollups, recording goes on across a
/// router rebuild and the rows survive a restart.
#[tokio::test(flavor = "multi_thread")]
async fn history_records_and_answers() {
    let dir = temp_dir("history");
    let env = Env::start_in(&dir, MOCK).await;
    let c = env.client().await;
    let m = |kv: &[(&str, Value)]| {
        Value::Map(
            kv.iter()
                .map(|(k, v)| ((*k).to_owned(), v.clone()))
                .collect(),
        )
    };
    let hist = format!("wy/{SITE}/sys/history");
    c.invoke_one(
        &hist,
        "add_watch_group",
        m(&[
            ("name", Value::from("g")),
            ("logging_type", Value::from("All Data")),
            ("buffer_flush_time", Value::Float(0.2)),
        ]),
    )
    .await
    .unwrap();
    let group = format!("{hist}/g");
    let watch = |path: &str| m(&[("path", Value::from(path))]);
    c.invoke_one(&group, "add_watch_path", watch("downstream/mock/g0/p0"))
        .await
        .unwrap();
    for bad in [
        "wy/other/downstream/mock/p",
        "wy/e2e/sys/links/mock",
        "downstream/mock/**",
    ] {
        assert!(
            c.invoke_one(&group, "add_watch_path", watch(bad))
                .await
                .is_err(),
            "{bad}"
        );
    }
    let w1 = format!("{group}/w1");
    let all = || m(&[("timerange", Value::from("2020-01-01/"))]);
    let rows = |c: WyrmClient, args: Value| {
        let w1 = w1.clone();
        async move {
            match c.invoke_one(&w1, "get_history", args).await {
                Ok(Some(Value::Array(r))) => Some(r),
                _ => None,
            }
        }
    };
    let first = eventually("rows recorded", 15, || async {
        rows(c.clone(), all()).await.filter(|r| r.len() >= 5)
    })
    .await;
    let Value::Map(row) = &first[0] else {
        panic!("a record")
    };
    assert!(row.contains_key("time") && row.contains_key("value"));
    assert_eq!(row.get("quality"), Some(&Value::from("good")));
    let avg = rows(
        c.clone(),
        m(&[
            ("timerange", Value::from("2020-01-01/")),
            ("interval", Value::from("1d")),
            ("rollup", Value::from("avg")),
        ]),
    )
    .await
    .unwrap();
    assert!(!avg.is_empty() && avg.len() <= 2, "{avg:?}");
    assert!(matches!(&avg[0], Value::Map(r) if matches!(r.get("value"), Some(Value::Float(_)))));
    eventually("database values", 10, || async {
        let n = last_val(&c, &format!("{hist}/rows_written"))
            .await?
            .as_f64()?;
        let size = last_val(&c, &format!("{hist}/database_size"))
            .await?
            .as_f64()?;
        (n >= 5.0 && size > 0.0).then_some(())
    })
    .await;
    // spec 03 through the router: `get <point>/~val?history=`
    let point = format!("wy/{SITE}/downstream/mock/g0/p0");
    let since = wyrm_client::HistoryQuery::since("2020-01-01");
    let h = c.history(&point, &since).await.unwrap();
    assert!(h.len() >= 5 && h.iter().all(|r| r.q.is_some()), "{h:?}");
    assert!(h.windows(2).all(|w| w[0].t <= w[1].t), "time order");
    // the same rows at the watch key (ADR 0020), where a downstream site's
    // point is read
    let at_watch = c.history(&w1, &since).await.unwrap();
    assert!(at_watch.len() >= h.len(), "{at_watch:?}");
    assert_eq!(at_watch[..h.len()], h[..]);
    let counted = c
        .history(
            &point,
            &wyrm_client::HistoryQuery {
                agg: Some("count".into()),
                ..since.clone()
            },
        )
        .await
        .unwrap();
    assert!(
        matches!(counted.as_slice(), [r] if r.q.is_none()),
        "{counted:?}"
    );
    assert!(
        c.history(&format!("wy/{SITE}/downstream/mock/g0/p2"), &since)
            .await
            .unwrap()
            .is_empty(),
        "not recorded"
    );
    let bad = c
        .history(&point, &wyrm_client::HistoryQuery::since("yesterday"))
        .await
        .expect_err("bad range");
    assert!(bad.is(wyrm_core::Status::InvalidParameter), "{bad}");
    // a watch made with no rows gets both dates once it records, not only
    // after a restart
    eventually("watch dates", 10, || async {
        let start = last_val(&c, &format!("{w1}/start_date")).await;
        let end = last_val(&c, &format!("{w1}/end_date")).await;
        matches!((start, end), (Some(Value::Str(_)), Some(Value::Str(_)))).then_some(())
    })
    .await;

    // A router rebuild (a new external link changes the ACL): the watch
    // records into the same store afterwards.
    let before = first.len();
    c.invoke_one(
        &format!("wy/{SITE}/sys/links"),
        "install",
        m(&[
            ("id", Value::from("ext")),
            ("driver", Value::from("x")),
            ("mode", Value::from("external")),
        ]),
    )
    .await
    .unwrap();
    let grown = eventually("rows after the rebuild", 20, || async {
        let s = env.try_session().await?;
        let c = WyrmClient::new(s)
            .with_tokens(Arc::new(SigningTokens::new(
                ed25519_dalek::SigningKey::from_bytes(&SEED),
                SITE,
            )))
            .with_timeout(Duration::from_secs(3));
        let r = rows(c, all()).await?;
        (r.len() > before + 5).then_some(r.len())
    })
    .await;

    // A restart keeps the rows; Unsubscribe and Purge deletes them.
    env.stop().await;
    let env = Env::start_in(&dir, MOCK).await;
    let c = env.client().await;
    let after = eventually("rows after the restart", 15, || async {
        rows(c.clone(), all()).await.filter(|r| r.len() >= grown)
    })
    .await;
    assert!(after.len() >= grown);
    let r = c
        .invoke_one(&w1, "unsubscribe_purge", Value::Map(Default::default()))
        .await
        .unwrap();
    assert!(
        matches!(&r, Some(Value::Map(d)) if d.get("deleted").and_then(Value::as_f64).unwrap_or(0.0) >= grown as f64),
        "{r:?}"
    );
    assert!(env.ctl.registry().historian.groups["g"].watches.is_empty());
    assert!(env
        .ctl
        .audit_tail(50)
        .iter()
        .any(|r| r.op == "history_watch"));
    env.stop().await;
}

/// ADR 0016: a watch lays `attr.history` (the watch key) over the point it
/// records, for an embedded and a process link; the list summary carries
/// `has_history`; Unsubscribe clears it; a router rebuild publishes it again;
/// a loopback put on the overlay key (prod) changes nothing.
#[tokio::test(flavor = "multi_thread")]
async fn history_overlays_mark_recorded_points() {
    let env = Env::start(
        "overlays",
        r#"links: {
            mock: { driver: "mock", params: { points: 2, rate_hz: 1, depth: 1, fanout: 1 } },
            pm: { driver: "mock", mode: "process", params: { points: 2, rate_hz: 1, depth: 1, fanout: 1 } },
        },"#,
    )
    .await;
    let c = env.client().await;
    let m = |kv: &[(&str, Value)]| {
        Value::Map(
            kv.iter()
                .map(|(k, v)| ((*k).to_owned(), v.clone()))
                .collect(),
        )
    };
    let hist = format!("wy/{SITE}/sys/history");
    c.invoke_one(
        &hist,
        "add_watch_group",
        m(&[
            ("name", Value::from("g")),
            ("logging_type", Value::from("All Data")),
        ]),
    )
    .await
    .unwrap();
    let group = format!("{hist}/g");
    for link in ["mock", "pm"] {
        eventually("the link is up", 20, || async {
            c.meta(&format!("wy/{SITE}/downstream/{link}/g0/p0"))
                .await
                .ok()
        })
        .await;
        c.invoke_one(
            &group,
            "add_watch_path",
            m(&[("path", Value::from(format!("downstream/{link}/g0/p0")))]),
        )
        .await
        .unwrap();
    }
    let history = |key: String| {
        let c = &c;
        async move {
            c.meta(&key)
                .await
                .ok()
                .and_then(|m| m.attr_value("history").cloned())
        }
    };
    for (link, w) in [("mock", "w1"), ("pm", "w2")] {
        let want = Value::Array(vec![Value::from(format!("{group}/{w}"))]);
        eventually("the watch key in the point's meta", 20, || async {
            (history(format!("wy/{SITE}/downstream/{link}/g0/p0"))
                .await
                .as_ref()
                == Some(&want))
            .then_some(())
        })
        .await;
        let kids = c
            .children(&format!("wy/{SITE}/downstream/{link}/g0"))
            .await
            .unwrap();
        let flag = |name: &str| {
            kids.iter()
                .find(|k| k.name == name)
                .and_then(|k| k.meta.has_history)
        };
        assert_eq!((flag("p0"), flag("p1")), (Some(true), None), "{link}");
    }

    // a storage value (ADR 0017): recorded, marked and answered like a point
    let storage = format!("wy/{SITE}/storage");
    let number = m(&[
        ("name", Value::from("setpoint")),
        ("type", Value::from("number")),
    ]);
    c.invoke_one(&storage, "add_value", number).await.unwrap();
    c.invoke_one(
        &group,
        "add_watch_path",
        m(&[("path", Value::from("storage/setpoint"))]),
    )
    .await
    .unwrap();
    let sp = format!("{storage}/setpoint");
    let want = Value::Array(vec![Value::from(format!("{group}/w3"))]);
    eventually("the watch key on the storage value", 20, || async {
        (history(sp.clone()).await.as_ref() == Some(&want)).then_some(())
    })
    .await;
    let mut n = 0.0;
    let since = wyrm_client::HistoryQuery::since("2020-01-01");
    eventually("the storage value recorded", 20, || {
        n += 1.0;
        let (c, sp, since) = (&c, sp.clone(), since.clone());
        async move {
            c.set(&sp, n).await.ok()?;
            let rows = c.history(&sp, &since).await.ok()?;
            (!rows.is_empty()).then_some(())
        }
    })
    .await;

    // a loopback client cannot put the broker's attributes (prod)
    let raw = loopback_session(env.port).await;
    let forged = wyrm_core::Sample {
        v: m(&[("g0/p1", m(&[("history", Value::Array(vec!["x".into()]))]))]),
        q: wyrm_core::Quality::Good,
        t: 1,
    };
    let _ = raw
        .put(
            format!("wy/{SITE}/sys/overlays/mock/~val"),
            wyrm_core::codec::to_vec(&forged).unwrap(),
        )
        .await;
    tokio::time::sleep(Duration::from_secs(1)).await;
    assert_eq!(
        history(format!("wy/{SITE}/downstream/mock/g0/p1")).await,
        None
    );
    let _ = raw.close().await;

    // Unsubscribe clears it
    c.invoke_one(&format!("{group}/w2"), "unsubscribe", m(&[]))
        .await
        .unwrap();
    eventually("the process link's overlay cleared", 20, || async {
        history(format!("wy/{SITE}/downstream/pm/g0/p0"))
            .await
            .is_none()
            .then_some(())
    })
    .await;

    // a router rebuild (a new link) publishes it again
    c.invoke_one(
        &format!("wy/{SITE}/sys/links"),
        "install",
        m(&[
            ("id", Value::from("extra")),
            ("driver", Value::from("mock")),
            ("mode", Value::from("embedded")),
            (
                "params",
                m(&[
                    ("points", Value::UInt(1)),
                    ("rate_hz", Value::UInt(1)),
                    ("depth", Value::UInt(1)),
                    ("fanout", Value::UInt(1)),
                ]),
            ),
        ]),
    )
    .await
    .unwrap();
    eventually("the overlay after a rebuild", 30, || async {
        let c = env.client().await;
        let key = format!("wy/{SITE}/downstream/mock/g0/p0");
        let h = c.meta(&key).await.ok()?.attr_value("history").cloned()?;
        (h == Value::Array(vec![Value::from(format!("{group}/w1"))])).then_some(())
    })
    .await;
    env.stop().await;
}

/// The embedded scheduler (ADR 0022) at `downstream/scheduler` writes a
/// process link's point with its own key: the link's `hello` reply carried
/// that key, its responder audits the write under `link:scheduler`. Targets
/// are config (ruling 6): a user with `write` on the scheduler alone (or the
/// built-in `operator`, `write` on all devices) adds schedules and events,
/// never targets or imports; an `engineer` (`config`) adds targets.
/// The id is reserved for new links.
#[tokio::test(flavor = "multi_thread")]
async fn embedded_scheduler_drives_a_process_link() {
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    let port = free_port();
    let env_lock = GATEWAY_ENV.lock().await;
    std::env::set_var(
        wyrmd::GATEWAY_ADMIN_PASSWORD_ENV,
        "correct-horse-battery-staple",
    );
    let env = Env::start(
        "scheduler",
        &format!(
            r#"links: {{ pm: {{ driver: "mock", mode: "process", params: {{ points: 2, rate_hz: 1, depth: 1, fanout: 1 }} }} }},
            gateway: {{ listen: "127.0.0.1:{port}", admin_user: "root" }},"#
        ),
    )
    .await;
    drop(env_lock);
    let gw = env.gateway.clone().expect("gateway configured");
    // CI's debug build is slow on the first calls
    let c = env.client().await.with_timeout(Duration::from_secs(60));
    let m = |kv: &[(&str, Value)]| {
        Value::Map(
            kv.iter()
                .map(|(k, v)| ((*k).to_owned(), v.clone()))
                .collect(),
        )
    };
    let state = format!("wy/{SITE}/sys/links/pm/state");
    eventually("pm connected", 60, || async {
        (last_val(&c, &state).await == Some(Value::UInt(2))).then_some(())
    })
    .await;
    let sched = format!("wy/{SITE}/downstream/scheduler");
    eventually("scheduler up", 60, || async { c.meta(&sched).await.ok() }).await;

    // a schedule whose event holds 1 now
    // local wall-clock minutes in `tz`
    let minute = |tz: &str, offset: i64| {
        (jiff::Timestamp::now() + jiff::SignedDuration::from_mins(offset))
            .to_zoned(jiff::tz::TimeZone::get(tz).unwrap())
            .strftime("%Y-%m-%dT%H:%M")
            .to_string()
    };
    c.invoke_one(
        &sched,
        "add_schedule",
        m(&[
            ("id", Value::from("s1")),
            ("tz", Value::from("UTC")),
            ("default", Value::UInt(0)),
        ]),
    )
    .await
    .expect("add_schedule");
    let s1 = format!("{sched}/s1");
    c.invoke_one(
        &s1,
        "add_event",
        m(&[
            ("value", Value::UInt(1)),
            ("start", Value::from(minute("UTC", -1))),
            ("end", Value::from(minute("UTC", 60))),
        ]),
    )
    .await
    .expect("add_event");
    let current = format!("{s1}/current");
    eventually("s1 current is 1", 15, || async {
        last_val(&c, &current)
            .await
            .filter(|v| v.as_f64() == Some(1.0))
    })
    .await;
    let point = format!("wy/{SITE}/downstream/pm/g0/p0");
    let added = c
        .invoke_one(
            &s1,
            "add_target",
            m(&[
                ("point", Value::from(point.as_str())),
                // enum `read_back | feedback | ack`, by index
                ("confirm", Value::UInt(0)),
            ]),
        )
        .await
        .expect("add_target");
    assert!(
        matches!(&added, Some(Value::Map(r)) if r.get("id") == Some(&Value::from("t1"))),
        "{added:?}"
    );
    eventually("the point is written", 15, || async {
        last_val(&c, &point)
            .await
            .filter(|v| v.as_f64() == Some(1.0))
    })
    .await;
    let t1 = format!("{s1}/targets/t1");
    eventually("t1 confirmed", 15, || async {
        last_val(&c, &t1)
            .await
            .filter(|v| *v == Value::from("confirmed"))
    })
    .await;
    // ruling 2: the target link's responder audits the write
    let audited = |status: wyrm_core::Status| {
        env.ctl.audit_tail(1000).iter().any(|r| {
            r.op == "set"
                && r.sub == "claimed:link:scheduler"
                && r.key.starts_with(&point)
                && r.status == status.code()
                && r.detail.starts_with("link:pm ")
        })
    };
    let deadline = tokio::time::Instant::now() + Duration::from_secs(30);
    while !audited(wyrm_core::Status::Ok) {
        if tokio::time::Instant::now() > deadline {
            let seen: Vec<_> = env
                .ctl
                .audit_tail(1000)
                .into_iter()
                .filter(|r| r.key.contains("/pm/") || r.detail.starts_with("link:pm "))
                .map(|r| format!("{} {} {} {} {}", r.sub, r.op, r.key, r.status, r.detail))
                .collect();
            panic!("no audit record of the write; pm records: {seen:#?}");
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
    }

    // users through the gateway: their grants decide
    let mut body = BTreeMap::new();
    body.insert("user".to_owned(), Value::from("root"));
    body.insert(
        "password".to_owned(),
        Value::from("correct-horse-battery-staple"),
    );
    let body = wyrm_core::codec::to_vec(&Value::Map(body)).unwrap();
    let req = format!(
        "POST /api/login HTTP/1.1\r\nHost: gw\r\nConnection: close\r\nContent-Type: application/cbor\r\nContent-Length: {}\r\n\r\n",
        body.len()
    );
    let mut s = tokio::net::TcpStream::connect(gw.local_addr().await)
        .await
        .unwrap();
    s.write_all(req.as_bytes()).await.unwrap();
    s.write_all(&body).await.unwrap();
    let mut resp = Vec::new();
    tokio::time::timeout(Duration::from_secs(30), s.read_to_end(&mut resp))
        .await
        .unwrap()
        .unwrap();
    assert!(resp.starts_with(b"HTTP/1.1 200"), "login ok");
    let split = resp.windows(4).position(|w| w == b"\r\n\r\n").unwrap();
    let Value::Map(lm) = wyrm_core::codec::from_slice::<Value>(&resp[split + 4..]).unwrap() else {
        panic!("login body is a map")
    };
    let Some(Value::Str(session)) = lm.get("session") else {
        panic!("session token")
    };
    let p = gw.authenticate(session).expect("session verifies");
    c.invoke_one(
        &format!("wy/{SITE}/sys"),
        "update_permissions",
        m(&[
            ("role", Value::from("sched")),
            ("path", Value::from("wy/{site}/downstream/scheduler/**")),
            ("level", Value::from("write")),
        ]),
    )
    .await
    .expect("a role with write on the scheduler alone");
    let user = |name: &str, grants: wyrm_gateway::Grants| {
        let mut q = p.clone();
        q.name = name.to_owned();
        q.grants = grants;
        q
    };
    let writer = user("sched-user", gw.grants_of(&["sched".to_owned()]));
    let cw = WyrmClient::new(env.session().await)
        .with_tokens(Arc::new(gw.tokens_for(&writer)))
        .with_timeout(Duration::from_secs(60));
    cw.invoke_one(
        &sched,
        "add_schedule",
        m(&[("id", Value::from("s2")), ("default", Value::UInt(0))]),
    )
    .await
    .expect("write adds a schedule");
    let s2 = format!("{sched}/s2");
    // ruling 3: without `tz` the schedule has the system zone
    let zone = c
        .meta(&s2)
        .await
        .unwrap()
        .attr_value("tz")
        .cloned()
        .unwrap();
    // as wyrmd picks it: the system's IANA name if known, else UTC
    let want = jiff::tz::TimeZone::system()
        .iana_name()
        .filter(|n| jiff::tz::TimeZone::get(n).is_ok())
        .unwrap_or("UTC")
        .to_owned();
    assert_eq!(zone, Value::from(want.as_str()), "the system zone");
    cw.invoke_one(
        &s2,
        "add_event",
        m(&[
            ("value", Value::UInt(1)),
            ("start", Value::from(minute(&want, -1))),
            ("end", Value::from(minute(&want, 60))),
        ]),
    )
    .await
    .expect("write adds an event");
    let p1 = format!("wy/{SITE}/downstream/pm/g0/p1");
    let target = m(&[
        ("point", Value::from(p1.as_str())),
        ("confirm", Value::UInt(0)),
    ]);
    let e = cw
        .invoke_one(&s2, "add_target", target.clone())
        .await
        .expect_err("targets are config");
    assert!(e.is(wyrm_core::Status::PermissionDenied), "add_target: {e}");
    let e = cw
        .invoke_one(&sched, "import", m(&[("json", Value::from("{}"))]))
        .await
        .expect_err("import carries targets: config");
    assert!(e.is(wyrm_core::Status::PermissionDenied), "import: {e}");
    // a target's edit is config too (M4); `t1` stays as it was
    let e = cw
        .invoke_one(
            &t1,
            "edit",
            m(&[(
                "point",
                Value::from(format!("wy/{SITE}/downstream/pm/g0/p1").as_str()),
            )]),
        )
        .await
        .expect_err("a target edit is config");
    assert!(
        e.is(wyrm_core::Status::PermissionDenied),
        "target edit: {e}"
    );
    let e = cw
        .invoke_one(&t1, "disable", Value::Map(BTreeMap::new()))
        .await
        .expect_err("a target disable is config");
    assert!(
        e.is(wyrm_core::Status::PermissionDenied),
        "target disable: {e}"
    );
    assert_eq!(
        c.meta(&t1).await.unwrap().attr_value("point"),
        Some(&Value::from(point.as_str())),
        "the target is unchanged"
    );
    // the built-in roles: `operator` has write on downstream/**, `engineer`
    // config
    let env_ref = &env;
    let role_client = |role: &str| {
        let u = user(
            &format!("{role}-user"),
            wyrm_gateway::RoleTable::default().grants(SITE, &[role.to_owned()]),
        );
        let tokens = Arc::new(gw.tokens_for(&u));
        async move {
            WyrmClient::new(env_ref.session().await)
                .with_tokens(tokens)
                .with_timeout(Duration::from_secs(60))
        }
    };
    let e = role_client("operator")
        .await
        .invoke_one(&s2, "add_target", target.clone())
        .await
        .expect_err("write on downstream/** is not config");
    assert!(e.is(wyrm_core::Status::PermissionDenied), "operator: {e}");
    role_client("engineer")
        .await
        .invoke_one(&s2, "add_target", target)
        .await
        .expect("config on downstream/** adds a target");
    eventually("the engineer's target writes", 15, || async {
        last_val(&c, &p1).await.filter(|v| v.as_f64() == Some(1.0))
    })
    .await;

    // reserved for new links
    let e = c
        .invoke_one(
            &format!("wy/{SITE}/sys/links"),
            "install",
            m(&[
                ("id", Value::from("scheduler")),
                ("driver", Value::from("mock")),
                ("mode", Value::from("embedded")),
            ]),
        )
        .await
        .expect_err("the id is the broker's");
    assert!(e.to_string().contains("reserved"), "{e}");
    env.stop().await;
}

/// ADR 0013 grants reach every link (ruling R13): the rebuild after `grant` starts embedded
/// links again with the new grants; a running process link takes its grants and requester key
/// only in its first `hello`, so the grant restarts it (not when it repeats a grant the link
/// has); a stopped one is not started by it.
#[tokio::test(flavor = "multi_thread")]
async fn grant_restarts_a_running_process_link() {
    let mock = |mode: &str| {
        format!(
            r#"{{ driver: "mock", mode: "{mode}", params: {{ points: 1, rate_hz: 0, depth: 0 }} }}"#
        )
    };
    let env = Env::start(
        "grantrestart",
        &format!(
            "links: {{ pm: {}, ps: {}, em: {} }},",
            mock("process"),
            mock("process"),
            mock("embedded")
        ),
    )
    .await;
    let c = env.client().await.with_timeout(Duration::from_secs(60));
    let state = |id: &str| format!("wy/{SITE}/sys/links/{id}/state");
    for id in ["pm", "ps"] {
        eventually(&format!("{id} connected"), 60, || async {
            (last_val(&c, &state(id)).await == Some(Value::UInt(2))).then_some(())
        })
        .await;
    }
    c.invoke_one(
        &format!("wy/{SITE}/sys/links/ps"),
        "stop",
        Value::Map(BTreeMap::new()),
    )
    .await
    .expect("stop ps");
    eventually("ps stopped", 30, || async {
        last_val(&c, &state("ps"))
            .await
            .filter(|v| *v != Value::UInt(2))
    })
    .await;
    // `stop`/`start` records of link `id` after its `link_grant` record
    let restarted = |id: &str| {
        let tail = env.ctl.audit_tail(1000);
        let Some(at) = tail
            .iter()
            .position(|r| r.op == "link_grant" && r.key == id)
        else {
            return Vec::new();
        };
        tail[at..]
            .iter()
            .filter(|r| r.key == id && (r.op == "stop" || r.op == "start"))
            .map(|r| r.op.clone())
            .collect::<Vec<_>>()
    };
    // `ps` first: the rebuild after any grant starts every process link of the registry again;
    // `pm` twice: the same grant again changes nothing
    for id in ["ps", "pm", "em", "pm"] {
        let watch = BrokerWatch::new(&env).await;
        slow_client(&env)
            .await
            .invoke_one(
                &format!("wy/{SITE}/sys/links/{id}"),
                "grant",
                args_map(&[
                    ("path", Value::from("wy/{site}/downstream/em")),
                    ("level", Value::from("read")),
                ]),
            )
            .await
            .unwrap_or_else(|e| panic!("grant {id}: {e}"));
        watch
            .rebuilt(&format!("the rebuild after the grant to {id}"))
            .await;
    }
    assert_eq!(
        restarted("pm"),
        ["stop", "start"],
        "the running process link, once"
    );
    assert_eq!(
        env.ctl
            .audit_tail(1000)
            .iter()
            .filter(|r| r.op == "link_grant" && r.key == "pm")
            .count(),
        2,
        "pm got the grant twice"
    );
    assert!(restarted("ps").is_empty(), "the stopped process link");
    assert!(
        restarted("em").is_empty(),
        "the embedded link: the rebuild starts it"
    );
    let c = slow_client(&env).await;
    eventually("pm connected again", 60, || async {
        (last_val(&c, &state("pm")).await == Some(Value::UInt(2))).then_some(())
    })
    .await;
    eventually("em connected again", 60, || async {
        (last_val(&c, &state("em")).await == Some(Value::UInt(2))).then_some(())
    })
    .await;
    env.stop().await;
}

/// What one mode of the scheduler shows in the scenario of `scheduler_three_modes`.
#[derive(Debug, PartialEq)]
struct SchedRun {
    /// `s1/targets/t1` once written: `confirmed`.
    state: Value,
    /// The target point's value then: the event's.
    point: Option<f64>,
    /// Rows of `get_events` for the next 24 h, without their instants (they follow the clock).
    rows: Vec<EventRow>,
    /// The export imported under a new id gives the same rows.
    same_rows: bool,
    /// After `sys/links/<id>` stop and start (a package link; the embedded one has no such node):
    /// the target's state, the writes of its point the audit saw meanwhile, and whether the
    /// point's sample stayed the one from before (the static mock publishes only when written).
    restart: Option<(Value, usize, bool)>,
}

/// A `get_events` row as the modes must agree on it: the window's length, not its instants.
#[derive(Debug, PartialEq)]
struct EventRow {
    event: Value,
    value: Value,
    priority: Value,
    special: Value,
    length: jiff::SignedDuration,
}

impl EventRow {
    fn of(row: &Value) -> Self {
        let Value::Map(m) = row else {
            panic!("a get_events row: {row:?}")
        };
        let field = |k: &str| m.get(k).cloned().unwrap_or(Value::Null);
        let instant = |k: &str| match m.get(k) {
            Some(Value::Str(t)) => t
                .parse::<jiff::Timestamp>()
                .unwrap_or_else(|e| panic!("{k} {t:?}: {e}")),
            other => panic!("{k}: {other:?}"),
        };
        EventRow {
            event: field("event"),
            value: field("value"),
            priority: field("priority"),
            special: field("special"),
            length: instant("end").duration_since(instant("start")),
        }
    }
}

/// `{k: v, …}`.
fn args_map(kv: &[(&str, Value)]) -> Value {
    Value::Map(
        kv.iter()
            .map(|(k, v)| ((*k).to_owned(), v.clone()))
            .collect(),
    )
}

/// Local wall-clock minutes in UTC, `offset` minutes from now.
fn utc_minute(offset: i64) -> String {
    (jiff::Timestamp::now() + jiff::SignedDuration::from_mins(offset))
        .to_zoned(jiff::tz::TimeZone::UTC)
        .strftime("%Y-%m-%dT%H:%M")
        .to_string()
}

/// A client on a new session that waits as long as a slow debug build needs.
async fn slow_client(env: &Env) -> WyrmClient {
    eventually("a session", 40, || client_now(env))
        .await
        .with_timeout(Duration::from_secs(60))
}

/// `set` records of the audit for `point` (its own key, not `…/p1` for `…/p10`), any caller.
fn point_writes(env: &Env, point: &str) -> usize {
    let below = format!("{point}/");
    env.ctl
        .audit_tail(10_000)
        .iter()
        .filter(|r| r.op == "set" && (r.key == point || r.key.starts_with(&below)))
        .count()
}

/// The broker's liveliness token, watched from before an action that rebuilds the router.
struct BrokerWatch {
    _session: zenoh::Session,
    sub: zenoh::pubsub::Subscriber<zenoh::handlers::FifoChannelHandler<zenoh::sample::Sample>>,
}

impl BrokerWatch {
    async fn new(env: &Env) -> Self {
        let session = env.session().await;
        let sub = session
            .liveliness()
            .declare_subscriber(format!("wy/{SITE}/sys/broker"))
            .await
            .unwrap();
        BrokerWatch {
            _session: session,
            sub,
        }
    }

    /// Waits for the old broker to go and a new one to come (as a process link sees it).
    async fn rebuilt(self, what: &str) {
        use zenoh::sample::SampleKind;
        let deadline = tokio::time::Instant::now() + Duration::from_secs(90);
        let mut gone = false;
        loop {
            let s = tokio::time::timeout_at(deadline, self.sub.recv_async())
                .await
                .unwrap_or_else(|_| panic!("timeout: {what}"))
                .unwrap();
            match s.kind() {
                SampleKind::Delete => gone = true,
                SampleKind::Put if gone => return,
                SampleKind::Put => {}
            }
        }
    }
}

/// A package link without a grant on the mock: `add_target` is refused `permission_denied`
/// (the host refuses the probe `subscribe` of the point).
async fn refused_without_grant(env: &Env, id: &str, point: &str) {
    let root = format!("wy/{SITE}/downstream/{id}");
    let c = slow_client(env).await;
    eventually(&format!("{id}: add_schedule ng"), 60, || async {
        let r = client_now(env)
            .await?
            .with_timeout(Duration::from_secs(60))
            .invoke_one(
                &root,
                "add_schedule",
                args_map(&[("id", Value::from("ng")), ("default", Value::UInt(0))]),
            )
            .await;
        match r {
            Ok(_) => Some(()),
            // an earlier try that timed out on the caller's side
            Err(e) if e.to_string().contains("exists") => Some(()),
            Err(_) => None,
        }
    })
    .await;
    let e = c
        .invoke_one(
            &format!("{root}/ng"),
            "add_target",
            args_map(&[("point", Value::from(point)), ("confirm", Value::UInt(0))]),
        )
        .await
        .expect_err("no grant on the mock");
    // the responder sends no message with `permission_denied` (`wyrm-link-sdk` `err_att`)
    assert!(e.is(wyrm_core::Status::PermissionDenied), "{id}: {e}");
}

/// On scheduler link `id`: a schedule `s1` with an event active now and a `read_back` target on
/// `point`; `get_events`; export and import as `s1copy` (without its target: one writer per
/// point); with `restart`, `sys/links/<id>` stop and start.
async fn sched_scenario(env: &Env, id: &str, point: &str, restart: bool) -> SchedRun {
    let root = format!("wy/{SITE}/downstream/{id}");
    let c = slow_client(env).await;
    c.invoke_one(
        &root,
        "add_schedule",
        args_map(&[
            ("id", Value::from("s1")),
            ("tz", Value::from("UTC")),
            ("default", Value::UInt(0)),
        ]),
    )
    .await
    .unwrap_or_else(|e| panic!("{id}: add_schedule: {e}"));
    let s1 = format!("{root}/s1");
    c.invoke_one(
        &s1,
        "add_event",
        args_map(&[
            ("value", Value::UInt(1)),
            ("start", Value::from(utc_minute(-1))),
            ("end", Value::from(utc_minute(60))),
        ]),
    )
    .await
    .unwrap_or_else(|e| panic!("{id}: add_event: {e}"));
    c.invoke_one(
        &s1,
        "add_target",
        // enum `read_back | feedback | ack`, by index
        args_map(&[("point", Value::from(point)), ("confirm", Value::UInt(0))]),
    )
    .await
    .unwrap_or_else(|e| panic!("{id}: add_target: {e}"));
    let t1 = format!("{s1}/targets/t1");
    let state = eventually(&format!("{id}: t1 confirmed"), 30, || async {
        last_val(&c, &t1)
            .await
            .filter(|v| *v == Value::from("confirmed"))
    })
    .await;
    let point_v = last_val(&c, point).await.and_then(|v| v.as_f64());
    // the target link's responder audits the write (ruling 2); the record is a put of its
    // own, so it may land after the reply
    eventually(&format!("{id}: the write audited"), 30, || async {
        (point_writes(env, point) > 0).then_some(())
    })
    .await;

    let day = format!(
        "{}/{}",
        jiff::Timestamp::now(),
        jiff::Timestamp::now() + jiff::SignedDuration::from_hours(24)
    );
    let events = |node: String| {
        let (c, day) = (&c, &day);
        async move {
            match c
                .invoke_one(
                    &node,
                    "get_events",
                    args_map(&[("timerange", Value::from(day.as_str()))]),
                )
                .await
                .unwrap_or_else(|e| panic!("get_events on {node}: {e}"))
            {
                Some(Value::Array(rows)) => rows,
                other => panic!("get_events on {node}: {other:?}"),
            }
        }
    };
    let rows = events(s1.clone()).await;
    let exported = c
        .invoke_one(&s1, "export", Value::Map(BTreeMap::new()))
        .await
        .unwrap_or_else(|e| panic!("{id}: export: {e}"));
    let Some(Value::Map(x)) = exported else {
        panic!("{id}: export result: {exported:?}")
    };
    let Some(Value::Str(json)) = x.get("json") else {
        panic!("{id}: export json: {x:?}")
    };
    // the target stays with s1: its point has one writer
    let mut def: serde_json::Value = serde_json::from_str(json).unwrap();
    def.as_object_mut().unwrap().remove("targets");
    c.invoke_one(
        &root,
        "import",
        args_map(&[
            ("json", Value::from(def.to_string().as_str())),
            ("id", Value::from("s1copy")),
        ]),
    )
    .await
    .unwrap_or_else(|e| panic!("{id}: import: {e}"));
    let same_rows = events(format!("{root}/s1copy")).await == rows;

    let restart = if restart {
        let before = point_writes(env, point);
        let sample = eventually(&format!("{id}: the point's sample"), 10, || async {
            last_sample(env, point).await
        })
        .await;
        let link = format!("wy/{SITE}/sys/links/{id}");
        let restarted = wyrm_link_sdk::now_us();
        invoke_retry(env, &link, "stop", Value::Map(BTreeMap::new())).await;
        invoke_retry(env, &link, "start", Value::Map(BTreeMap::new())).await;
        let state = eventually(&format!("{id}: t1 after the restart"), 60, || async {
            let s = last_sample(env, &t1).await?;
            (s.t > restarted && s.q == wyrm_core::Quality::Good).then_some(s.v)
        })
        .await;
        // the first-sample wait at start, then time for a write that should not come
        tokio::time::sleep(Duration::from_secs(5)).await;
        let now = eventually(&format!("{id}: the point's sample again"), 10, || async {
            last_sample(env, point).await
        })
        .await;
        let unchanged = now == sample;
        Some((
            state,
            point_writes(env, point).saturating_sub(before),
            unchanged,
        ))
    } else {
        None
    };
    SchedRun {
        state,
        point: point_v,
        rows: rows.iter().map(EventRow::of).collect(),
        same_rows,
        restart,
    }
}

/// The store at the planned size (brief step 6): 200 schedules × 10 events × 1 target in the
/// WASM link `sw`; a stop and start keeps it `running` (`start` and each batch within `call_ms`
/// and the fuel bound, never restarting) and brings every schedule back within 60 s (a loaded
/// CI runner; the demo measures 1.7 s).
async fn wasm_store_at_size(env: &Env) {
    const N: usize = 200;
    let root = format!("wy/{SITE}/downstream/sw");
    let c = slow_client(env).await;
    let point = |i: usize| format!("wy/{SITE}/downstream/m/p{}", 10 + i);
    c.invoke_one(
        &root,
        "add_schedule",
        args_map(&[
            ("id", Value::from("b0")),
            ("tz", Value::from("UTC")),
            ("default", Value::UInt(0)),
        ]),
    )
    .await
    .expect("add_schedule b0");
    let b0 = format!("{root}/b0");
    // ten daily windows that began a month ago
    let day = (jiff::Timestamp::now() - jiff::SignedDuration::from_hours(30 * 24))
        .to_zoned(jiff::tz::TimeZone::UTC)
        .date();
    for h in 0..10 {
        c.invoke_one(
            &b0,
            "add_event",
            args_map(&[
                ("value", Value::UInt(h + 1)),
                (
                    "start",
                    Value::from(format!("{day}T{:02}:00", 2 * h).as_str()),
                ),
                (
                    "end",
                    Value::from(format!("{day}T{:02}:30", 2 * h).as_str()),
                ),
                ("recurrence", Value::from("FREQ=DAILY")),
            ]),
        )
        .await
        .expect("add_event");
    }
    c.invoke_one(
        &b0,
        "add_target",
        args_map(&[
            ("point", Value::from(point(0).as_str())),
            ("confirm", Value::UInt(0)),
        ]),
    )
    .await
    .expect("add_target b0");
    let Some(Value::Map(x)) = c
        .invoke_one(&b0, "export", Value::Map(BTreeMap::new()))
        .await
        .expect("export b0")
    else {
        panic!("export result")
    };
    let Some(Value::Str(json)) = x.get("json") else {
        panic!("export json")
    };
    let mut def: serde_json::Value = serde_json::from_str(json).unwrap();
    let t = std::time::Instant::now();
    for i in 1..N {
        def["targets"][0]["point"] = serde_json::Value::from(point(i));
        c.invoke_one(
            &root,
            "import",
            args_map(&[
                ("json", Value::from(def.to_string().as_str())),
                ("id", Value::from(format!("b{i}").as_str())),
            ]),
        )
        .await
        .unwrap_or_else(|e| panic!("import b{i}: {e}"));
    }
    eprintln!("sw: {N} schedules added in {:?}", t.elapsed());
    eventually("every b target confirmed", 120, || async {
        for i in 0..N {
            let v = last_val(&c, &format!("{root}/b{i}/targets/t1")).await?;
            if v != Value::from("confirmed") {
                return None;
            }
        }
        Some(())
    })
    .await;

    let link = format!("wy/{SITE}/sys/links/sw");
    let log = || async {
        let lines = c
            .invoke_one(&link, "get_log", args_map(&[("lines", Value::UInt(40))]))
            .await;
        format!("{lines:#?}")
    };
    let schedules = || async {
        c.children(&root).await.ok().map(|ch| {
            ch.iter()
                .filter(|k| k.name.starts_with('b') && k.name[1..].parse::<usize>().is_ok())
                .count()
        })
    };
    let status = || async {
        c.meta(&root)
            .await
            .ok()
            .and_then(|m| m.attr_value("status").cloned())
    };
    c.invoke_one(&link, "stop", Value::Map(BTreeMap::new()))
        .await
        .expect("stop sw");
    let t = std::time::Instant::now();
    c.invoke_one(&link, "start", Value::Map(BTreeMap::new()))
        .await
        .expect("start sw");
    let started = t.elapsed();
    let mut back = None;
    let mut seen = Vec::new();
    while t.elapsed() < Duration::from_secs(60) {
        let s = status().await;
        if let Some(Value::Str(s)) = &s {
            if seen.last() != Some(s) {
                seen.push(s.clone());
            }
            assert_eq!(
                s,
                "running",
                "sw after {:?} (start answered after {started:?}); log: {}",
                t.elapsed(),
                log().await
            );
        }
        if back.is_none() && schedules().await == Some(N) {
            back = Some(t.elapsed());
        }
        // a few more seconds of `running` once every schedule is back
        if back.is_some_and(|b| t.elapsed() > b + Duration::from_secs(5)) {
            break;
        }
        tokio::time::sleep(Duration::from_millis(150)).await;
    }
    let Some(back) = back else {
        panic!(
            "sw: {:?} of {N} schedules back within 60 s (statuses {seen:?}); log: {}",
            schedules().await,
            log().await
        )
    };
    eprintln!("sw: start answered after {started:?}, {N} schedules back after {back:?}, statuses {seen:?}");
}

/// ADR 0022 run modes: the scheduler embedded in `wyrmd`, as a WASM package (`sw`) and as a
/// process package (`sp`) answer the same scenario with the same results. A package carries
/// no grants: until an operator grants `write` on the target link (ADR 0013, ruling 10) its
/// `add_target` is refused.
#[tokio::test(flavor = "multi_thread")]
async fn scheduler_three_modes() {
    use wyrm_link_sdk::package::{self, Capabilities, Manifest, PackFile};
    // static points: `p0`–`p2` the scenario's (one writer each), `p3`/`p4` the refusals,
    // `p10`–`p209` the WASM store at size
    let env = Env::start(
        "schedmodes",
        r#"links: { m: { driver: "mock", params: { points: 210, rate_hz: 0, depth: 0 } } },"#,
    )
    .await;
    let c = env.client().await.with_timeout(Duration::from_secs(60));
    let point = |k: usize| format!("wy/{SITE}/downstream/m/p{k}");
    eventually("mock up", 60, || async {
        last_sample(&env, &point(209)).await
    })
    .await;
    eventually("scheduler up", 60, || async {
        c.meta(&format!("wy/{SITE}/downstream/scheduler"))
            .await
            .ok()
    })
    .await;
    let grant = |id: &str| {
        let env = &env;
        let id = id.to_owned();
        async move {
            let watch = BrokerWatch::new(env).await;
            slow_client(env)
                .await
                .invoke_one(
                    &format!("wy/{SITE}/sys/links/{id}"),
                    "grant",
                    args_map(&[
                        ("path", Value::from("wy/{site}/downstream/m")),
                        ("level", Value::from("write")),
                    ]),
                )
                .await
                .unwrap_or_else(|e| panic!("grant {id}: {e}"));
            watch
                .rebuilt(&format!("the rebuild after the grant to {id}"))
                .await;
        }
    };

    // the WASM package: an embedded link, no router rebuild
    let mut runs = vec![("scheduler", point(0), false)];
    let wasm = portable_component("wyrm-link-scheduler");
    match &wasm {
        Some(component) => {
            let m = Manifest {
                name: "scheduler".into(),
                version: "1.0.0".into(),
                description: "the scheduler as a component".into(),
                wyrm_link: wyrm_link_sdk::LINK_PROTOCOL,
                kind: "wasm".into(),
                entries: Default::default(),
                args: Vec::new(),
                entry: Some("scheduler.wasm".into()),
                requester: Vec::new(),
                world: Some("app".into()),
                capabilities: Some(Capabilities {
                    store_mb: Some(16),
                    ..Capabilities::default()
                }),
            };
            let files = [PackFile {
                path: "scheduler.wasm".into(),
                data: component.clone(),
                mode: 0o644,
            }];
            let (ok, msg) = install_zip(&c, "sw", package::pack(&m, &files).unwrap()).await;
            assert!(ok, "install sw: {msg}");
            refused_without_grant(&env, "sw", &point(3)).await;
            grant("sw").await;
            runs.push(("sw", point(1), true));
        }
        None => eprintln!(
            "SKIP scheduler_three_modes (WASM mode): target wasm32-unknown-unknown is not \
             installed (rustup target add wasm32-unknown-unknown)"
        ),
    }
    // the process package last: its install rebuilds the router
    let zip = driver_package_with(
        "scheduler-process",
        "1.0.0",
        "the scheduler as a process",
        "scheduler",
        Some(serde_json::json!({ "store_mb": 16 })),
    );
    let watch = BrokerWatch::new(&env).await;
    let (ok, msg) = install_zip(&slow_client(&env).await, "sp", zip).await;
    assert!(ok, "install sp: {msg}");
    assert!(msg.contains("store 16 MiB"), "{msg}");
    watch.rebuilt("the rebuild after the install of sp").await;
    refused_without_grant(&env, "sp", &point(4)).await;
    // the grant restarts the running process link: it takes grants in its first `hello`
    grant("sp").await;
    runs.push(("sp", point(2), true));
    let reg = env.ctl.registry();
    assert_eq!(reg.links["sp"].mode, wyrm_admin::Mode::Process);
    if wasm.is_some() {
        assert_eq!(reg.links["sw"].driver, "pkg:scheduler");
        assert_eq!(reg.links["sw"].mode, wyrm_admin::Mode::Embedded);
    }

    let mut seen: Vec<(&str, SchedRun)> = Vec::new();
    for (id, point, restart) in runs {
        let run = sched_scenario(&env, id, &point, restart).await;
        // the modes agree with each other row for row …
        if let Some((first, r)) = seen.first() {
            assert_eq!(run.rows, r.rows, "get_events of {id} and of {first}");
        }
        // … and with the scenario
        let want = SchedRun {
            state: Value::from("confirmed"),
            point: Some(1.0),
            // the event of the scenario: now − 1 min … now + 60 min, whole minutes
            rows: vec![EventRow {
                event: Value::from("e1"),
                value: Value::UInt(1),
                priority: Value::UInt(0),
                special: Value::Bool(false),
                length: jiff::SignedDuration::from_mins(61),
            }],
            same_rows: true,
            restart: restart.then(|| (Value::from("confirmed"), 0, true)),
        };
        assert_eq!(run, want, "mode of {id}");
        seen.push((id, run));
    }
    if wasm.is_some() {
        wasm_store_at_size(&env).await;
    }
    env.stop().await;
}
