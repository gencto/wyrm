//! Broker end to end: external sessions (loopback TCP, mTLS) talk to links
//! through the router, under the generated ACL.

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
const SITE: &str = "e2e";

fn free_port() -> u16 {
    std::net::TcpListener::bind("127.0.0.1:0")
        .unwrap()
        .local_addr()
        .unwrap()
        .port()
}

fn temp_dir(name: &str) -> PathBuf {
    let d = std::env::temp_dir().join(format!("wyrmd-e2e-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&d);
    d
}

struct Env {
    port: u16,
    tls: u16,
    ctl: Arc<Control>,
    stop: Option<oneshot::Sender<()>>,
    task: tokio::task::JoinHandle<Result<(), wyrmd::Error>>,
}

impl Env {
    /// `extra`: more json5 fields (without braces).
    async fn start(name: &str, extra: &str) -> Self {
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
            temp_dir(name).display(),
            hex::encode(key.verifying_key().to_bytes())
        );
        let cfg = Config::from_json5(&text).unwrap();
        let daemon = Daemon::open(cfg, env!("CARGO_BIN_EXE_wyrmd").into()).unwrap();
        let ctl = daemon.control();
        let (stop, rx) = oneshot::channel();
        let task = tokio::spawn(daemon.run_until(async {
            let _ = rx.await;
        }));
        let env = Self {
            port,
            tls,
            ctl,
            stop: Some(stop),
            task,
        };
        // wait for the listener
        for _ in 0..100 {
            if std::net::TcpStream::connect(("127.0.0.1", port)).is_ok() {
                break;
            }
            tokio::time::sleep(Duration::from_millis(30)).await;
        }
        env
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
    let root = format!("wy/{SITE}/down/mock");

    let mut links = c.list(&format!("wy/{SITE}/down")).await.unwrap();
    let Some(ListEvent::Refreshed(snap)) = links.next().await else {
        panic!()
    };
    assert_eq!(
        snap.iter().map(|c| c.name.as_str()).collect::<Vec<_>>(),
        ["mock"]
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

#[tokio::test(flavor = "multi_thread")]
async fn subscribe_reads_storage_first() {
    let env = Env::start("storage", MOCK).await;
    let c = env.client().await;
    tokio::time::sleep(Duration::from_millis(300)).await;
    let mut vals = c
        .subscribe(&format!("wy/{SITE}/down/mock/**"))
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
    let key = format!("wy/{SITE}/down/fake/x/~val");
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
    let node = format!("wy/{SITE}/down/plc1/c1/ahu1/supply_temp");
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
            // poll_unsubscribed: under the ACL a process link never sees the
            // storage's `wy/**/~val` subscription, so the subscriber gate
            // would never open (framework issue, reported).
            r#"links: {{ plc1: {{ driver: "modbus", mode: "process", params: {{ poll_unsubscribed: true, connections: {{ c1: {{
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
    let node = format!("wy/{SITE}/down/plc1/c1/ahu1/supply_temp");
    let v = eventually("value from the process", 5, || async {
        last_val(&c, &node).await
    })
    .await;
    assert_eq!(v, Value::Float(21.5));
    // a write goes through the router into the process and the device
    c.set(&format!("wy/{SITE}/down/plc1/c1/ahu1/fan"), true)
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

    // the unknown session cannot publish into down/**
    let key = format!("wy/{SITE}/down/mcu-7/t/~val");
    mcu.put(&key, sample(1.0)).await.unwrap();
    let total = format!("wy/{SITE}/sys/metrics/broker/acl_denied_total");
    eventually("acl_denied_total > 0", 5, || async {
        match last_val(&c, &total).await {
            Some(Value::UInt(n)) if n > 0 => Some(()),
            _ => None,
        }
    })
    .await;
    assert!(last_val(&c, &format!("wy/{SITE}/down/mcu-7/t"))
        .await
        .is_none());

    // approve → ACL rebuilt → the same certificate may publish its branch
    let reply = c
        .invoke_one(&qnode, "approve", Value::Map(Default::default()))
        .await
        .unwrap();
    assert!(matches!(reply, Some(Value::Map(m)) if m.contains_key("token")));
    eventually("approved link may publish", 15, || async {
        let c2 = env.client().await;
        mcu.put(&key, sample(2.0)).await.ok()?;
        tokio::time::sleep(Duration::from_millis(100)).await;
        (last_val(&c2, &format!("wy/{SITE}/down/mcu-7/t")).await == Some(Value::Float(2.0)))
            .then_some(())
    })
    .await;
    let audit = env.ctl.audit_tail(50);
    for op in ["quarantine", "acl_denied", "approve"] {
        assert!(audit.iter().any(|r| r.op == op), "audit has {op}");
    }
    env.stop().await;
}

async fn hello(s: &zenoh::Session, id: &str, token: &str) -> Option<wyrm_core::status::StatusCode> {
    let mut args = BTreeMap::new();
    args.insert("token".to_owned(), Value::Bytes(token.as_bytes().to_vec()));
    let r = s
        .get(format!("wy/{SITE}/sys/links/{id}/~act/hello"))
        .payload(wyrm_core::codec::to_vec(&Value::Map(args)).unwrap())
        .timeout(Duration::from_secs(1))
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
