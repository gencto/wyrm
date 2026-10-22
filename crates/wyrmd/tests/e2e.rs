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
            match Daemon::open(cfg, env!("CARGO_BIN_EXE_wyrmd").into()) {
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
        let env = Self {
            port,
            tls,
            ctl,
            gateway,
            stop: Some(stop),
            task,
        };
        // wait for both listeners (on a slow CI the tls one comes later)
        for _ in 0..200 {
            let up = |p| std::net::TcpStream::connect(("127.0.0.1", p)).is_ok();
            if up(port) && up(tls) {
                break;
            }
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
        // a listener that has just opened may still refuse the handshake
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
        let c2 = WyrmClient::new(env.try_session().await?);
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
    let meta = c.meta(&format!("{sys}/data_in_per_second")).await.unwrap();
    assert_eq!(
        meta.attr_value("display"),
        Some(&Value::Str("Data In Per Second".into()))
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
    let key = format!("wy/{SITE}/down/dev-1/t/~val");
    eventually("auto-installed link may publish", 15, || async {
        let c2 = WyrmClient::new(env.try_session().await?);
        dev.put(&key, sample(3.0)).await.ok()?;
        tokio::time::sleep(Duration::from_millis(100)).await;
        (last_val(&c2, &format!("wy/{SITE}/down/dev-1/t")).await == Some(Value::Float(3.0)))
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
    assert_eq!(keys, ["wy/edge/down/a/**/~val", "wy/edge/down/ab/**/~val"]);
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
                upstream_val_hz: 5,
            }},
            links: {{
                mock: {{ driver: "mock", params: {{ points: 8, rate_hz: 20, depth: 1, fanout: 2 }} }},
                slow: {{ driver: "mock", params: {{ points: 1, rate_hz: 2, depth: 1, fanout: 1 }} }},
            }},
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
            let mut names: Vec<String> = ch.into_iter().map(|c| c.name).collect();
            names.sort();
            (names.len() == 2).then_some(names)
        }
    })
    .await;
    assert_eq!(names, ["mock", "slow"]);
    // Each broker shows its peer: the downstream edge beside central's
    // links (`down/edge`), the upstream central at `up/central`, both
    // connected (liveliness of `sys/broker`).
    let down = "wy/central/down/edge";
    let kids: Vec<String> = eventually("down/edge beside central's links", 10, || async {
        let ch = c.children("wy/central/down").await.ok()?;
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
        (last_val(&ec, "wy/edge/up/central/connected").await == Some(Value::Bool(true)))
            .then_some(())
    })
    .await;
    let _ = ec.session().close().await;
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
    // One downsampling budget per link: the busy `mock` link (160 samples/s)
    // does not starve `slow` (2 samples/s) under upstream_val_hz: 5.
    let mut busy = c.subscribe("wy/edge/down/mock/**").await.unwrap();
    let drain = tokio::spawn(async move { while busy.next().await.is_some() {} });
    let mut slow = c.subscribe("wy/edge/down/slow/**").await.unwrap();
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
    // The upstream site is read-only: the edge ACL drops its commands.
    assert!(c.set("wy/edge/down/mock/g0/p0", 1.0).await.is_err());

    // Quiet first: a live 160 samples/s stream slows the broker's close.
    drain.abort();
    drop(slow);
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
    // the directory is the operator's (another medium): not created for them
    assert!(Daemon::open(cfg(&anchors).unwrap(), exe.clone()).is_err());
    std::fs::create_dir_all(&anchors).unwrap();
    drop(Daemon::open(cfg(&anchors).unwrap(), exe.clone()).unwrap());
    drop(Daemon::open(cfg(&anchors).unwrap(), exe.clone()).unwrap());
    // the anchor says the registry WAL was longer than it is now
    std::fs::write(
        anchors.join("state.head"),
        format!("999 {}\n", "00".repeat(32)),
    )
    .unwrap();
    let e = Daemon::open(cfg(&anchors).unwrap(), exe.clone())
        .err()
        .expect("refused");
    assert!(e.to_string().contains("anchor"), "{e}");
    // a deleted anchor is refused too, until `wyrmd init-anchors`
    std::fs::remove_file(anchors.join("state.head")).unwrap();
    assert!(Daemon::open(cfg(&anchors).unwrap(), exe.clone()).is_err());
    let mut init = cfg(&anchors).unwrap();
    init.init_anchors = true;
    drop(Daemon::open(init, exe.clone()).unwrap());
    drop(Daemon::open(cfg(&anchors).unwrap(), exe).unwrap());
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
                let ch = c.children(&format!("wy/{SITE}/down/m2")).await.ok()?;
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
    drop(Daemon::open(cfg(), env!("CARGO_BIN_EXE_wyrmd").into()).unwrap());
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
/// `wy/**/~val`, which the link ACL (`wy/S/down/L/**`) does not pass on, so
/// with `poll_unsubscribed: false` the link polls only while a real
/// subscriber (one point or a pattern under `down/**`) exists. Embedded
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
    let node = format!("wy/{SITE}/down/plc1/c1/ahu1/supply_temp");
    let _s = c.subscribe(&node).await.unwrap();
    tokio::time::sleep(Duration::from_secs(2)).await;
    let r1 = reqs();
    tokio::time::sleep(Duration::from_secs(1)).await;
    let exact = reqs() - r1;
    let pat = format!("wy/{SITE}/down/**");
    drop(_s);
    let _p = c.subscribe(&pat).await.unwrap();
    tokio::time::sleep(Duration::from_secs(2)).await;
    let r2 = reqs();
    tokio::time::sleep(Duration::from_secs(1)).await;
    let pattern = reqs() - r2;
    assert_eq!(idle, 0, "no subscriber, no polling");
    assert!(exact >= 5, "one point subscribed: {exact} requests/s");
    assert!(pattern >= 5, "down/** subscribed: {pattern} requests/s");
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
    let root = format!("wy/{SITE}/down/dev1");
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

/// Peer brokers added at runtime (DSA `/sys/upstream`): no peers in either
/// `wyrmd.json5` (central only has `peers.listen`); central trusts the edge
/// with `sys/downstream add`, the edge connects with `sys/upstream add`;
/// disabling the upstream ends the link.
#[tokio::test(flavor = "multi_thread")]
async fn runtime_peers_over_quic() {
    let key = ed25519_dalek::SigningKey::from_bytes(&SEED);
    let admin = hex::encode(key.verifying_key().to_bytes());
    let (c_dir, e_dir) = (temp_dir("rt-central"), temp_dir("rt-edge"));
    let (c_tcp, c_quic, e_tcp) = (free_port(), free_port(), free_port());
    let central = Config::from_json5(&format!(
        r#"{{ site: "central", data_dir: "{}", listen: ["tcp/127.0.0.1:{c_tcp}"],
              admin_keys: ["{admin}"], peers: {{ listen: "quic/127.0.0.1:{c_quic}" }} }}"#,
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
    let central = Daemon::open(central, exe.clone()).unwrap();
    let edge = Daemon::open(edge, exe).unwrap();
    let e_ctl = edge.control();
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
    let pem = |dir: &PathBuf| std::fs::read_to_string(dir.join("pki/ca.pem")).unwrap();
    let up_add = |ca: String, url: String| {
        args(&[
            ("name", Value::from("central")),
            ("url", Value::from(url.as_str())),
            ("ca", Value::from(ca.as_str())),
        ])
    };

    let c = client(c_tcp, "central").await;
    c.invoke_one(
        "wy/central/sys/downstream",
        "add",
        args(&[
            ("name", Value::from("edge")),
            ("ca", Value::from(pem(&e_dir).as_str())),
        ]),
    )
    .await
    .expect("trust the edge");
    let e = client(e_tcp, "edge").await;
    for (ca, url, why) in [
        (
            "not a pem".to_string(),
            format!("quic/127.0.0.1:{c_quic}"),
            "CA",
        ),
        (pem(&c_dir), format!("tcp/127.0.0.1:{c_quic}"), "url"),
    ] {
        let err = e
            .invoke_one("wy/edge/sys/upstream", "add", up_add(ca, url))
            .await
            .expect_err(why);
        assert!(err.is(wyrm_core::Status::InvalidParameter), "{why}: {err}");
    }
    e.invoke_one(
        "wy/edge/sys/upstream",
        "add",
        up_add(pem(&c_dir), format!("quic/127.0.0.1:{c_quic}")),
    )
    .await
    .expect("connect upstream");

    // tokens for the site being read (the edge checks them)
    eventually("edge links seen from central", 20, || async {
        let c = client(c_tcp, "edge").await;
        let ch = c.children("wy/edge/down").await.ok()?;
        ch.iter().any(|c| c.name == "mock").then_some(())
    })
    .await;
    eventually("edge sees central connected", 10, || async {
        let e = client(e_tcp, "edge").await;
        (last_val(&e, "wy/edge/up/central/connected").await == Some(Value::Bool(true)))
            .then_some(())
    })
    .await;
    let peer = e_ctl.registry().peers["central"].clone();
    assert!(peer.enabled && peer.endpoint.ends_with(&c_quic.to_string()));

    // disabled: the edge drops the connection, central loses the edge tree
    let e = client(e_tcp, "edge").await;
    e.set("wy/edge/sys/upstream/central/enabled", false)
        .await
        .unwrap();
    eventually("edge gone from central", 20, || async {
        let c = client(c_tcp, "edge").await;
        match c.children("wy/edge/down").await {
            Ok(ch) if !ch.is_empty() => None,
            _ => Some(()),
        }
    })
    .await;
    assert!(!e_ctl.peers().upstream.contains(&"central".to_string()));
    let audit = e_ctl.audit_tail(50);
    for op in ["peer_add", "peer_enable"] {
        assert!(audit.iter().any(|r| r.op == op), "audit has {op}");
    }
    let e = client(e_tcp, "edge").await;
    e.invoke_one("wy/edge/sys/upstream/central", "remove", args(&[]))
        .await
        .expect("remove");
    assert!(e_ctl.registry().peers.is_empty());

    let _ = c_stop.send(());
    let _ = e_stop.send(());
    c_task.await.unwrap().unwrap();
    e_task.await.unwrap().unwrap();

    // The operator moves the runtime downstream into wyrmd.json5: the config
    // wins, the registry entry goes, and the router (no repeated ACL ids)
    // starts.
    let central = Config::from_json5(&format!(
        r#"{{ site: "central", data_dir: "{}", listen: ["tcp/127.0.0.1:{c_tcp}"],
              admin_keys: ["{admin}"], peers: {{ listen: "quic/127.0.0.1:{c_quic}",
              downstream: [{{ site: "edge", ca: "{}" }}] }} }}"#,
        c_dir.display(),
        e_dir.join("pki/ca.pem").display()
    ))
    .unwrap();
    let central = Daemon::open(central, env!("CARGO_BIN_EXE_wyrmd").into()).unwrap();
    let c_ctl = central.control();
    assert!(c_ctl.registry().peers.is_empty(), "json5 wins");
    assert_eq!(c_ctl.peers().downstream, ["edge"]);
    let (c_stop, c_rx) = oneshot::channel::<()>();
    let c_task = tokio::spawn(central.run_until(async {
        let _ = c_rx.await;
    }));
    eventually("central up with edge from json5", 10, || async {
        let c = client(c_tcp, "central").await;
        c.meta("wy/central/down/edge").await.ok()
    })
    .await;
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
    let d = Daemon::open(cfg, env!("CARGO_BIN_EXE_wyrmd").into()).unwrap();
    let (tx, rx) = oneshot::channel::<()>();
    (
        tx,
        tokio::spawn(d.run_until(async {
            let _ = rx.await;
        })),
    )
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
/// 1. the upstream reads `down/**` of the downstream site, never `sys/**`;
/// 2. the upstream cannot `invoke`, even with a token the edge trusts;
/// 3. the downstream cannot write or query outside its own `wy/<edge>/**`;
/// 4. a broker with a certificate from an untrusted CA cannot join, even
///    with a configured site name (`broker:edge`).
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
                downstream: [{{ site: "edge", ca: "{}" }}],
            }},
        }}"#,
        c_dir.display(),
        e_dir.join("pki/ca.pem").display()
    ))
    .unwrap();
    // The edge runs `dev` so a loopback client there may publish and query
    // anything: the only thing that stops it is the central broker's ACL.
    let edge_cfg = |dir: &std::path::Path, port: u16, link: &str| {
        Config::from_json5(&format!(
            r#"{{
                site: "edge",
                profile: "dev",
                data_dir: "{}",
                listen: ["tcp/127.0.0.1:{port}"],
                admin_keys: ["{admin}"],
                metrics_interval_ms: 200,
                peers: {{
                    upstream: [{{ site: "central", endpoint: "quic/127.0.0.1:{c_quic}", ca: "{}" }}],
                }},
                links: {{ {link}: {{ driver: "mock", params: {{ points: 2, rate_hz: 20, depth: 1, fanout: 2 }} }} }},
            }}"#,
            dir.display(),
            c_dir.join("pki/ca.pem").display()
        ))
        .unwrap()
    };
    // Both CAs exist once both daemons are open; brokers read them at start.
    let exe: PathBuf = env!("CARGO_BIN_EXE_wyrmd").into();
    let central = Daemon::open(central, exe.clone()).unwrap();
    let edge = Daemon::open(edge_cfg(&e_dir, e_tcp, "mock"), exe).unwrap();
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
        async move { (!c.children("wy/edge/down").await.ok()?.is_empty()).then_some(()) }
    })
    .await;

    // 1. down/** is readable from central, sys/** is not.
    assert!(
        !replies(&cs, "wy/edge/down/mock/**/~meta").await.is_empty(),
        "control: central reads the edge's down/**"
    );
    for k in [
        "wy/edge/sys/**",
        "wy/edge/sys/links/**",
        "wy/edge/sys/audit/**",
        "wy/edge/sys/**/~meta",
    ] {
        assert_eq!(replies(&cs, k).await, Vec::<String>::new(), "query {k}");
    }
    // The edge publishes its metrics every 200 ms; none reach central.
    let (down, sys) = tokio::join!(
        samples(&cs, "wy/edge/down/**", 2),
        samples(&cs, "wy/edge/sys/**", 2)
    );
    assert!(!down.is_empty(), "control: edge values reach central");
    assert_eq!(sys, Vec::<String>::new(), "edge sys/** samples at central");

    // 2. No commands across sites, even with a token the edge trusts.
    let args = Value::Map(BTreeMap::from([("n".to_owned(), Value::UInt(1))]));
    assert!(c
        .invoke_one("wy/edge/down/mock", "count", args)
        .await
        .is_err());
    let args = Value::Map(BTreeMap::new());
    assert!(c
        .invoke_one("wy/edge/down/mock", "reset", args)
        .await
        .is_err());

    // 3. The edge's loopback client may do anything on the edge (dev), but
    //    central accepts from `broker:edge` only `wy/edge/**`.
    let es = loopback_session(e_tcp).await;
    assert!(
        !samples(&es, "wy/edge/sys/**", 1).await.is_empty(),
        "control: the edge does publish sys/** (check 1 is not vacuous)"
    );
    let watch_central = samples(&cs, "wy/central/**", 3);
    let watch_other = samples(&cs, "wy/other/**", 3);
    let forge = async {
        tokio::time::sleep(Duration::from_millis(500)).await;
        for _ in 0..10 {
            es.put("wy/central/down/x/~val", sample(1.0)).await.unwrap();
            es.put("wy/other/down/x/~val", sample(1.0)).await.unwrap();
            tokio::time::sleep(Duration::from_millis(100)).await;
        }
    };
    let (central_seen, other_seen, ()) = tokio::join!(watch_central, watch_other, forge);
    assert_eq!(
        central_seen,
        Vec::<String>::new(),
        "edge wrote into wy/central"
    );
    assert_eq!(other_seen, Vec::<String>::new(), "edge wrote into wy/other");
    for k in ["wy/central/sys/**", "wy/central/down/**"] {
        assert_eq!(
            replies(&es, k).await,
            Vec::<String>::new(),
            "edge queried {k}"
        );
    }

    // 4. A rogue broker that calls itself `edge` (CN `broker:edge`), with a
    //    certificate from its own CA, does not get in.
    let (r_stop, r_task) = spawn_daemon(edge_cfg(&r_dir, r_tcp, "evil"));
    let rs = loopback_session(r_tcp).await;
    let (evil, own) = tokio::join!(
        samples(&cs, "wy/edge/down/evil/**", 4),
        samples(&rs, "wy/edge/down/evil/**", 4)
    );
    assert!(
        !own.is_empty(),
        "control: the rogue broker runs and publishes"
    );
    assert_eq!(evil, Vec::<String>::new(), "rogue samples reached central");
    let names: Vec<String> = c
        .children("wy/edge/down")
        .await
        .unwrap()
        .into_iter()
        .map(|c| c.name)
        .collect();
    assert_eq!(names, ["mock"], "rogue link listed at central");

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
