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
    gateway: Option<Arc<wyrm_gateway::Gateway>>,
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
        let gateway = daemon.gateway();
        let (stop, rx) = oneshot::channel();
        let task = tokio::spawn(daemon.run_until(async {
            let _ = rx.await;
        }));
        let env = Self {
            port,
            tls,
            ctl,
            gateway,
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
    let v = eventually("value from the process", 15, || async {
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
                    m(&[("type", s("subscribe")), ("key", s("down/mock/g0/p0"))]),
                ),
                (
                    "al",
                    m(&[("type", s("alarm")), ("high", Value::Float(-1e9))]),
                ),
                (
                    "cmd",
                    m(&[
                        ("type", s("invoke")),
                        ("path", s("down/mock")),
                        ("action", s("reset")),
                        ("on", s("rising")),
                    ]),
                ),
                ("res", m(&[("type", s("publish")), ("node", s("res"))])),
            ]),
        ),
        (
            "edges",
            Value::Array(vec![
                edge("a.out", "al.in"),
                edge("al.out", "cmd.in"),
                edge("cmd.out", "res.in"),
            ]),
        ),
        ("permissions", m(&[("maxperm", s("write"))])),
    ]);
    let flows = format!("wy/{SITE}/flows");
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
#[tokio::test(flavor = "multi_thread")]
async fn two_brokers_over_quic() {
    let key = ed25519_dalek::SigningKey::from_bytes(&SEED);
    let admin = hex::encode(key.verifying_key().to_bytes());
    let (c_dir, e_dir) = (temp_dir("central"), temp_dir("edge"));
    let (c_tcp, c_quic, e_tcp) = (free_port(), free_port(), free_port());
    let central = Config::from_json5(&format!(
        r#"{{
            site: "central",
            data_dir: "{}",
            listen: ["tcp/127.0.0.1:{c_tcp}"],
            admin_keys: ["{admin}"],
            peers: {{
                listen: "quic/127.0.0.1:{c_quic}",
                downstream: [{{ site: "edge", ca: "{}" }}],
            }},
        }}"#,
        c_dir.display(),
        e_dir.join("pki/ca.pem").display()
    ))
    .unwrap();
    let edge = Config::from_json5(&format!(
        r#"{{
            site: "edge",
            data_dir: "{}",
            listen: ["tcp/127.0.0.1:{e_tcp}"],
            admin_keys: ["{admin}"],
            peers: {{
                upstream: [{{ site: "central", endpoint: "quic/127.0.0.1:{c_quic}", ca: "{}" }}],
                upstream_val_hz: 50,
            }},
            {MOCK}
        }}"#,
        e_dir.display(),
        c_dir.join("pki/ca.pem").display()
    ))
    .unwrap();
    // Both CAs exist once both daemons are open; brokers read them at start.
    let exe: PathBuf = env!("CARGO_BIN_EXE_wyrmd").into();
    let central = Daemon::open(central, exe.clone()).unwrap();
    let edge = Daemon::open(edge, exe).unwrap();
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
    let c = WyrmClient::new(session)
        .with_tokens(Arc::new(SigningTokens::new(key, "edge")))
        .with_timeout(Duration::from_secs(3));

    let names = eventually("edge links seen from central", 15, || {
        let c = &c;
        async move {
            let ch = c.children("wy/edge/down").await.ok()?;
            let names: Vec<String> = ch.into_iter().map(|c| c.name).collect();
            (!names.is_empty()).then_some(names)
        }
    })
    .await;
    assert_eq!(names, ["mock"]);
    let mut vals = c.subscribe("wy/edge/down/mock/g0/p0").await.unwrap();
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
    // The upstream site is read-only: the edge ACL drops its commands.
    assert!(c.set("wy/edge/down/mock/g0/p0", 1.0).await.is_err());

    let _ = c_stop.send(());
    let _ = e_stop.send(());
    e_task.await.unwrap().unwrap();
    c_task.await.unwrap().unwrap();
}

/// Iteration 5: the user gateway runs in wyrmd. The first admin comes from
/// the environment; a login is audited; the gateway's per-user tokens are
/// accepted by links (its key is trusted like an admin key).
#[tokio::test(flavor = "multi_thread")]
async fn gateway_in_wyrmd() {
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    let port = free_port();
    std::env::set_var(
        wyrmd::GATEWAY_ADMIN_PASSWORD_ENV,
        "correct-horse-battery-staple",
    );
    let env = Env::start(
        "gateway",
        &format!(r#"{MOCK} gateway: {{ listen: "127.0.0.1:{port}", admin_user: "root" }},"#),
    )
    .await;
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
    let c = WyrmClient::new(env.session().await)
        .with_tokens(Arc::new(gw.tokens_for(&p)))
        .with_timeout(Duration::from_secs(3));
    c.set(&format!("wy/{SITE}/down/mock/g0/p0"), 5.0)
        .await
        .expect("a gateway token is accepted by the link");
    assert!(env
        .ctl
        .audit_tail(50)
        .iter()
        .any(|r| r.op == "login" && r.sub == "user:root"));
    env.stop().await;
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
    let daemon = Daemon::open(cfg, env!("CARGO_BIN_EXE_wyrmd").into()).unwrap();
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
            ai: { driver: "agent", params: { allowed_prefixes: ["wy/e2e/down/mock"] } },
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
    let scopes = Value::Array(vec![Value::from("wy/e2e/down/mock")]);
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
    drop(Daemon::open(cfg(&anchors).unwrap(), exe.clone()).unwrap());
    drop(Daemon::open(cfg(&anchors).unwrap(), exe.clone()).unwrap());
    // the anchor says the registry WAL was longer than it is now
    std::fs::write(
        anchors.join("state.head"),
        format!("999 {}\n", "00".repeat(32)),
    )
    .unwrap();
    let e = Daemon::open(cfg(&anchors).unwrap(), exe)
        .err()
        .expect("refused");
    assert!(e.to_string().contains("anchor"), "{e}");
}
