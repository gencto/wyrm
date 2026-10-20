//! The mqtt link against an in-process rumqttd broker.

use prost::Message;
use rumqttc::{AsyncClient, Event, MqttOptions, Packet, QoS};
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::mpsc;
use tokio::task::JoinHandle;
use wyrm_core::{Attachment, Perm, Quality, Status, Value};
use wyrm_link_mqtt::sparkplug::{self, DataType, Metric, MetricValue, Payload};
use wyrm_link_mqtt::Mqtt;
use wyrm_link_sdk::driver::Tree;
use wyrm_link_sdk::{Secret, SecretStore, TestHarness};

type H = TestHarness<Mqtt>;

// ---------- broker, proxy, test client ----------

fn free_port() -> u16 {
    std::net::TcpListener::bind("127.0.0.1:0")
        .and_then(|l| l.local_addr())
        .map(|a| a.port())
        .expect("free port")
}

/// rumqttd on 127.0.0.1 in its own thread (it has no stop API; it ends
/// with the test process).
fn broker(auth: Option<(&str, &str)>) -> u16 {
    let port = free_port();
    let connections = rumqttd::ConnectionSettings {
        connection_timeout_ms: 5000,
        max_payload_size: 256 * 1024,
        max_inflight_count: 100,
        auth: auth.map(|(u, p)| HashMap::from([(u.to_owned(), p.to_owned())])),
        external_auth: None,
        dynamic_filters: true,
    };
    let server = rumqttd::ServerSettings {
        name: "v4".into(),
        listen: format!("127.0.0.1:{port}").parse().expect("addr"),
        tls: None,
        next_connection_delay_ms: 1,
        connections,
    };
    let config = rumqttd::Config {
        router: rumqttd::RouterConfig {
            max_connections: 100,
            max_outgoing_packet_count: 200,
            max_segment_size: 1 << 20,
            max_segment_count: 10,
            ..Default::default()
        },
        v4: Some(HashMap::from([("1".to_owned(), server)])),
        ..Default::default()
    };
    std::thread::spawn(move || {
        let _ = rumqttd::Broker::new(config).start();
    });
    for _ in 0..250 {
        if std::net::TcpStream::connect(("127.0.0.1", port)).is_ok() {
            return port;
        }
        std::thread::sleep(Duration::from_millis(20));
    }
    panic!("rumqttd did not start on {port}");
}

/// TCP proxy to the broker; aborting it drops every proxied connection.
async fn proxy(listen: u16, target: u16) -> (u16, JoinHandle<()>) {
    let l = TcpListener::bind(("127.0.0.1", listen))
        .await
        .expect("bind proxy");
    let port = l.local_addr().expect("addr").port();
    let task = tokio::spawn(async move {
        let mut conns = tokio::task::JoinSet::new();
        while let Ok((mut a, _)) = l.accept().await {
            conns.spawn(async move {
                if let Ok(mut b) = TcpStream::connect(("127.0.0.1", target)).await {
                    let _ = tokio::io::copy_bidirectional(&mut a, &mut b).await;
                }
            });
        }
    });
    (port, task)
}

type Inbox = mpsc::UnboundedReceiver<(String, Vec<u8>)>;

/// A plain MQTT client for the test side (publisher and command sink).
async fn client(port: u16, id: &str, subscribe: &[&str]) -> (AsyncClient, Inbox) {
    let mut o = MqttOptions::new(id, "127.0.0.1", port);
    o.set_max_packet_size(256 * 1024, 256 * 1024);
    let (c, mut el) = AsyncClient::new(o, 64);
    let (tx, rx) = mpsc::unbounded_channel();
    let (ready_tx, mut ready) = mpsc::unbounded_channel();
    let want = subscribe.len();
    tokio::spawn(async move {
        let mut acks = 0;
        loop {
            match el.poll().await {
                Ok(Event::Incoming(Packet::Publish(p))) => {
                    let _ = tx.send((p.topic.clone(), p.payload.to_vec()));
                }
                Ok(Event::Incoming(Packet::ConnAck(_))) if want == 0 => {
                    let _ = ready_tx.send(());
                }
                Ok(Event::Incoming(Packet::SubAck(_))) => {
                    acks += 1;
                    if acks == want {
                        let _ = ready_tx.send(());
                    }
                }
                Ok(_) => {}
                Err(_) => tokio::time::sleep(Duration::from_millis(50)).await,
            }
        }
    });
    for t in subscribe {
        c.subscribe(*t, QoS::AtLeastOnce).await.expect("subscribe");
    }
    tokio::time::timeout(Duration::from_secs(10), ready.recv())
        .await
        .expect("test client ready");
    (c, rx)
}

async fn recv(inbox: &mut Inbox, topic: &str) -> Vec<u8> {
    let deadline = tokio::time::Instant::now() + Duration::from_secs(10);
    loop {
        let left = deadline.saturating_duration_since(tokio::time::Instant::now());
        match tokio::time::timeout(left, inbox.recv()).await {
            Ok(Some((t, body))) if t == topic => return body,
            Ok(Some(_)) => {}
            _ => panic!("nothing on {topic}"),
        }
    }
}

// ---------- tree and harness helpers ----------

fn map(kv: &[(&str, Value)]) -> Value {
    Value::Map(
        kv.iter()
            .map(|(k, v)| ((*k).to_owned(), v.clone()))
            .collect(),
    )
}

fn conn(port: u16, extra: &[(&str, Value)], devices: Value) -> Tree {
    let mut c = vec![
        ("host", Value::from("127.0.0.1")),
        ("port", Value::UInt(port.into())),
        ("timeout_ms", Value::UInt(2000)),
    ];
    c.extend_from_slice(extra);
    c.push(("devices", devices));
    Tree(map(&[("connections", map(&[("c1", map(&c))]))]))
}

fn plain(points: Value) -> Value {
    map(&[(
        "d1",
        map(&[("ping_s", Value::Float(0.1)), ("points", points)]),
    )])
}

fn pt(kv: &[(&str, Value)]) -> Value {
    let mut v = vec![("poll_s", Value::Float(0.05))];
    v.extend_from_slice(kv);
    map(&v)
}

fn state(h: &H, base: &str) -> Option<String> {
    match h.ctx().last(&format!("{base}/status"))?.v {
        Value::Map(m) => match m.get("state") {
            Some(Value::Str(s)) => Some(s.clone()),
            _ => None,
        },
        _ => None,
    }
}

fn error(h: &H, base: &str) -> Option<String> {
    match h.ctx().last(&format!("{base}/status"))?.v {
        Value::Map(m) => match m.get("error") {
            Some(Value::Str(s)) => Some(s.clone()),
            _ => None,
        },
        _ => None,
    }
}

fn val(h: &H, p: &str) -> Option<Value> {
    h.ctx().last(p).map(|s| s.v)
}

fn qual(h: &H, p: &str) -> Option<Quality> {
    h.ctx().last(p).map(|s| s.q)
}

async fn wait(what: &str, mut f: impl FnMut() -> bool) {
    let deadline = tokio::time::Instant::now() + Duration::from_secs(10);
    while !f() {
        assert!(tokio::time::Instant::now() < deadline, "timeout: {what}");
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
}

/// Publish `body` every 100 ms until `f` holds (no reliance on retained
/// messages or on subscription timing).
async fn publish_until(
    c: &AsyncClient,
    topic: &str,
    body: &[u8],
    what: &str,
    mut f: impl FnMut() -> bool,
) {
    let deadline = tokio::time::Instant::now() + Duration::from_secs(10);
    while !f() {
        assert!(tokio::time::Instant::now() < deadline, "timeout: {what}");
        c.publish(topic, QoS::AtLeastOnce, false, body.to_vec())
            .await
            .expect("publish");
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
}

/// Every `~val` qualifier published for `path`.
async fn quals(h: &H, path: &str) -> Arc<Mutex<Vec<String>>> {
    let seen = Arc::new(Mutex::new(Vec::new()));
    let s = seen.clone();
    h.session()
        .declare_subscriber(h.key(path, "~val"))
        .callback(move |sample| {
            let att = sample
                .attachment()
                .and_then(|a| wyrm_core::codec::from_slice::<Attachment>(&a.to_bytes()).ok());
            if let Some(q) = att.and_then(|a| a.qual) {
                s.lock().unwrap().push(q);
            }
        })
        .background()
        .await
        .expect("subscriber");
    seen
}

fn has(q: &Arc<Mutex<Vec<String>>>, s: &str) -> bool {
    q.lock().unwrap().iter().any(|x| x == s)
}

fn status(a: &Attachment) -> Option<Status> {
    match a.status? {
        wyrm_core::status::StatusCode::Known(s) => Some(s),
        _ => None,
    }
}

// ---------- tests ----------

#[tokio::test(flavor = "multi_thread")]
async fn plain_reads_json_pointer_and_bad_payload() {
    let port = broker(None);
    let points = map(&[
        (
            "temp",
            pt(&[("topic", "plant/temp".into()), ("unit", "°C".into())]),
        ),
        (
            "on",
            pt(&[
                ("topic", "plant/json".into()),
                ("format", "json".into()),
                ("pointer", "/a/b/1/c".into()),
                ("kind", "bool".into()),
            ]),
        ),
        (
            "name",
            pt(&[
                ("topic", "plant/json".into()),
                ("format", "json".into()),
                ("pointer", "/name".into()),
                ("kind", "string".into()),
            ]),
        ),
        (
            "text",
            pt(&[("topic", "plant/text".into()), ("kind", "string".into())]),
        ),
    ]);
    let h = H::start(conn(port, &[], plain(points))).await;
    let (pubc, _) = client(port, "pub1", &[]).await;
    publish_until(&pubc, "plant/temp", b"21.5", "temp", || {
        val(&h, "c1/d1/temp") == Some(Value::Float(21.5))
    })
    .await;
    publish_until(
        &pubc,
        "plant/json",
        br#"{"a":{"b":[0,{"c":true}]},"name":"pump 1"}"#,
        "json",
        || val(&h, "c1/d1/name").is_some(),
    )
    .await;
    assert_eq!(val(&h, "c1/d1/on"), Some(Value::Bool(true)));
    assert_eq!(val(&h, "c1/d1/name"), Some(Value::from("pump 1")));
    publish_until(&pubc, "plant/text", b"hello", "text", || {
        val(&h, "c1/d1/text").is_some()
    })
    .await;
    assert_eq!(val(&h, "c1/d1/text"), Some(Value::from("hello")));
    assert_eq!(state(&h, "c1/d1").as_deref(), Some("connected"));
    // a new message updates the value
    publish_until(&pubc, "plant/temp", b"22", "update", || {
        val(&h, "c1/d1/temp") == Some(Value::UInt(22))
    })
    .await;
    // an undecodable payload: point bad, value kept, device still fine
    publish_until(&pubc, "plant/temp", b"oops", "bad payload", || {
        qual(&h, "c1/d1/temp") == Some(Quality::Bad)
    })
    .await;
    assert_eq!(val(&h, "c1/d1/temp"), Some(Value::UInt(22)));
    assert_eq!(qual(&h, "c1/d1/text"), Some(Quality::Good));
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn writes_publish_to_command_topic() {
    let port = broker(None);
    let points = map(&[
        (
            "sp",
            pt(&[
                ("topic", "plant/sp".into()),
                ("cmd_topic", "plant/sp/set".into()),
                ("writable", true.into()),
            ]),
        ),
        (
            "js",
            pt(&[
                ("topic", "plant/js".into()),
                ("format", "json".into()),
                ("pointer", "/set/v".into()),
                ("cmd_topic", "plant/js/set".into()),
                ("writable", true.into()),
            ]),
        ),
        ("ro", pt(&[("topic", "plant/ro".into())])),
    ]);
    let h = H::start(conn(port, &[], plain(points))).await;
    let (sink, mut inbox) = client(port, "sink", &["plant/+/set"]).await;
    wait("device connected", || {
        state(&h, "c1/d1").as_deref() == Some("connected")
    })
    .await;
    let tok = || Some(h.ptok(Perm::Write));
    assert_eq!(
        status(&h.set("c1/d1/sp", 42u64, tok()).await),
        Some(Status::Ok)
    );
    assert_eq!(recv(&mut inbox, "plant/sp/set").await, b"42");
    assert_eq!(val(&h, "c1/d1/sp"), None, "no optimistic update");
    assert_eq!(
        status(&h.set("c1/d1/js", 1.5, tok()).await),
        Some(Status::Ok)
    );
    assert_eq!(
        recv(&mut inbox, "plant/js/set").await,
        br#"{"set":{"v":1.5}}"#
    );
    // the device reports back on its state topic
    publish_until(&sink, "plant/sp", b"42", "read back", || {
        val(&h, "c1/d1/sp") == Some(Value::UInt(42))
    })
    .await;
    // not writable: refused by the SDK
    assert_ne!(
        status(&h.set("c1/d1/ro", 1u64, tok()).await),
        Some(Status::Ok)
    );
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn password_from_link_secret() {
    let port = broker(Some(("wyrm", "s3cret-pw")));
    let auth = [
        ("username", Value::from("wyrm")),
        ("auth_ref", Value::from("mqtt_pw")),
    ];
    let tree = || {
        conn(
            port,
            &auth,
            plain(map(&[("t", pt(&[("topic", "a/t".into())]))])),
        )
    };
    let h = H::start_with(tree(), |c| {
        c.secrets = [("mqtt_pw", Secret::new("s3cret-pw"))]
            .into_iter()
            .collect();
    })
    .await;
    wait("connected with the secret", || {
        state(&h, "c1").as_deref() == Some("connected")
    })
    .await;
    let (_, m) = h.meta("c1").await;
    let shown = format!("{:?}", m.expect("meta").cfg);
    assert!(
        shown.contains("mqtt_pw") && !shown.contains("s3cret"),
        "{shown}"
    );
    let export = h
        .invoke("", "export", map(&[]), Some(h.ptok(Perm::Config)))
        .await;
    let exported = format!("{:?}", export.first().and_then(|r| r.value()));
    assert!(
        exported.contains("auth_ref") && !exported.contains("s3cret"),
        "{exported}"
    );
    // an edit keeps resolving the password from the store
    let edit = map(&[
        ("host", "127.0.0.1".into()),
        ("port", Value::UInt(port.into())),
        ("timeout_ms", Value::UInt(1500)),
        ("username", "wyrm".into()),
        ("auth_ref", "mqtt_pw".into()),
    ]);
    let r = h
        .invoke("c1", "edit", edit, Some(h.ptok(Perm::Config)))
        .await;
    assert_eq!(r.first().and_then(|r| status(&r.att)), Some(Status::Ok));
    wait("connected after edit", || {
        state(&h, "c1").as_deref() == Some("connected")
    })
    .await;
    h.stop().await;

    // wrong password: the broker refuses (rumqttd closes the socket instead
    // of a CONNACK refusal), the connection fails at open
    let h = H::start_with(tree(), |c| {
        c.secrets = [("mqtt_pw", Secret::new("wrong"))].into_iter().collect();
    })
    .await;
    wait("refused", || {
        error(&h, "c1").is_some_and(|e| e.starts_with("transport: connect"))
    })
    .await;
    h.stop().await;

    // missing secret: the node is kept as failed with the reason
    let h = H::start_with(tree(), |c| c.secrets = SecretStore::default()).await;
    wait("config error", || {
        error(&h, "c1").is_some_and(|e| e.contains("auth_ref"))
    })
    .await;
    assert_eq!(state(&h, "c1").as_deref(), Some("failed"));
    let (_, m) = h.meta("c1").await;
    assert!(m.is_some(), "node kept");
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn broker_loss_marks_points_bad_and_recovers() {
    let port = broker(None);
    let (pport, ptask) = proxy(0, port).await;
    let points = map(&[("t", pt(&[("topic", "plant/t".into())]))]);
    let h = H::start(conn(pport, &[], plain(points))).await;
    let q = quals(&h, "c1/d1/t").await;
    let (pubc, _) = client(port, "pub2", &[]).await;
    publish_until(&pubc, "plant/t", b"7", "value", || {
        val(&h, "c1/d1/t") == Some(Value::UInt(7))
    })
    .await;
    // the broker goes away
    ptask.abort();
    wait("point bad", || qual(&h, "c1/d1/t") == Some(Quality::Bad)).await;
    assert_eq!(val(&h, "c1/d1/t"), Some(Value::UInt(7)), "value kept");
    wait("disconnected qualifier", || has(&q, "bad/disconnected")).await;
    assert!(matches!(
        state(&h, "c1").as_deref(),
        Some("failed" | "connecting")
    ));
    assert_eq!(state(&h, "c1/d1").as_deref(), Some("stopped_by_parent"));
    let att = h.set("c1/d1/t", 1u64, Some(h.ptok(Perm::Config))).await;
    assert_ne!(status(&att), Some(Status::Ok));
    // the broker comes back on the same address: reconnect with backoff
    let (_, _ptask) = proxy(pport, port).await;
    publish_until(&pubc, "plant/t", b"8", "recovered", || {
        val(&h, "c1/d1/t") == Some(Value::UInt(8))
    })
    .await;
    assert_eq!(qual(&h, "c1/d1/t"), Some(Quality::Good));
    h.stop().await;
}

fn sp_metric(name: Option<&str>, alias: u64, dt: DataType, v: MetricValue) -> Metric {
    Metric {
        name: name.map(str::to_owned),
        alias: Some(alias),
        datatype: Some(dt.code()),
        value: Some(v),
        ..Default::default()
    }
}

fn sp_payload(seq: u64, metrics: Vec<Metric>) -> Vec<u8> {
    Payload {
        timestamp: Some(1),
        seq: Some(seq),
        metrics,
        ..Default::default()
    }
    .encode_to_vec()
}

#[tokio::test(flavor = "multi_thread")]
async fn sparkplug_birth_data_death_and_commands() {
    let port = broker(None);
    let dev = |device: &str, points: Value| {
        map(&[
            ("kind", "sparkplug".into()),
            ("group", "G".into()),
            ("edge", "E".into()),
            ("device", device.into()),
            ("ping_s", Value::Float(0.1)),
            ("points", points),
        ])
    };
    let devices = map(&[
        (
            "node",
            dev("", map(&[("temp", pt(&[("metric", "Temp".into())]))])),
        ),
        (
            "pump",
            dev(
                "D1",
                map(&[
                    (
                        "run",
                        pt(&[
                            ("metric", "Run".into()),
                            ("kind", "bool".into()),
                            ("writable", true.into()),
                        ]),
                    ),
                    ("speed", pt(&[("metric", "Speed".into())])),
                ]),
            ),
        ),
    ]);
    let (edge, mut cmds) = client(port, "edge", &["spBv1.0/G/NCMD/E", "spBv1.0/G/DCMD/E/D1"]).await;
    let h = H::start(conn(port, &[], devices)).await;
    let qnode = quals(&h, "c1/node/temp").await;
    let qpump = quals(&h, "c1/pump/run").await;
    // BIRTH is not retained: a new subscription asks the edge to rebirth
    let req = Payload::decode(recv(&mut cmds, "spBv1.0/G/NCMD/E").await.as_slice()).unwrap();
    assert_eq!(req.metrics[0].name.as_deref(), Some(sparkplug::REBIRTH));
    let nbirth = sp_payload(
        0,
        vec![
            sp_metric(Some("bdSeq"), 0, DataType::UInt64, MetricValue::Long(1)),
            sp_metric(Some("Temp"), 1, DataType::Double, MetricValue::Double(20.5)),
        ],
    );
    publish_until(&edge, "spBv1.0/G/NBIRTH/E", &nbirth, "node birth", || {
        val(&h, "c1/node/temp") == Some(Value::Float(20.5))
    })
    .await;
    let dbirth = sp_payload(
        1,
        vec![
            sp_metric(
                Some("Run"),
                2,
                DataType::Boolean,
                MetricValue::Boolean(true),
            ),
            // Int32 -5, two's complement in int_value
            sp_metric(
                Some("Speed"),
                3,
                DataType::Int32,
                MetricValue::Int((-5i32) as u32),
            ),
        ],
    );
    publish_until(
        &edge,
        "spBv1.0/G/DBIRTH/E/D1",
        &dbirth,
        "device birth",
        || val(&h, "c1/pump/speed").is_some(),
    )
    .await;
    assert_eq!(val(&h, "c1/pump/run"), Some(Value::Bool(true)));
    assert_eq!(val(&h, "c1/pump/speed"), Some(Value::Int(-5)));
    // DATA by alias only
    let ndata = sp_payload(
        2,
        vec![sp_metric(
            None,
            1,
            DataType::Double,
            MetricValue::Double(21.0),
        )],
    );
    let ndata = {
        let mut p = Payload::decode(ndata.as_slice()).unwrap();
        p.metrics[0].datatype = None;
        p.encode_to_vec()
    };
    publish_until(&edge, "spBv1.0/G/NDATA/E", &ndata, "node data", || {
        val(&h, "c1/node/temp") == Some(Value::Float(21.0))
    })
    .await;
    // write → DCMD with the BIRTH data type
    let tok = Some(h.ptok(Perm::Write));
    assert_eq!(
        status(&h.set("c1/pump/run", false, tok).await),
        Some(Status::Ok)
    );
    let cmd = Payload::decode(recv(&mut cmds, "spBv1.0/G/DCMD/E/D1").await.as_slice()).unwrap();
    assert_eq!(cmd.metrics.len(), 1);
    assert_eq!(cmd.metrics[0].name.as_deref(), Some("Run"));
    assert_eq!(cmd.metrics[0].datatype, Some(DataType::Boolean.code()));
    assert_eq!(cmd.metrics[0].value, Some(MetricValue::Boolean(false)));
    assert_eq!(
        val(&h, "c1/pump/run"),
        Some(Value::Bool(true)),
        "no optimistic update"
    );
    // DDEATH: the device goes stale, then bad/comm_fail; the node stays good
    edge.publish(
        "spBv1.0/G/DDEATH/E/D1",
        QoS::AtLeastOnce,
        false,
        sp_payload(3, vec![]),
    )
    .await
    .unwrap();
    wait("device comm_fail", || has(&qpump, "bad/comm_fail")).await;
    assert!(has(&qpump, "uncertain/stale"), "stale before comm_fail");
    assert_eq!(qual(&h, "c1/pump/run"), Some(Quality::Bad));
    assert_eq!(state(&h, "c1/pump").as_deref(), Some("failed"));
    assert_eq!(qual(&h, "c1/node/temp"), Some(Quality::Good));
    assert_eq!(state(&h, "c1").as_deref(), Some("connected"));
    // a write to an offline device is refused
    let att = h.set("c1/pump/run", true, Some(h.ptok(Perm::Write))).await;
    assert_ne!(status(&att), Some(Status::Ok));
    // NDEATH with the session's bdSeq: the node goes bad/comm_fail too
    let ndeath = sp_payload(
        0,
        vec![sp_metric(
            Some("bdSeq"),
            0,
            DataType::UInt64,
            MetricValue::Long(1),
        )],
    );
    edge.publish("spBv1.0/G/NDEATH/E", QoS::AtLeastOnce, false, ndeath)
        .await
        .unwrap();
    wait("node comm_fail", || has(&qnode, "bad/comm_fail")).await;
    assert_eq!(state(&h, "c1/node").as_deref(), Some("failed"));
    // DATA without a BIRTH: the driver asks the edge node to rebirth
    while cmds.try_recv().is_ok() {}
    edge.publish("spBv1.0/G/NDATA/E", QoS::AtLeastOnce, false, ndata.clone())
        .await
        .unwrap();
    let req = Payload::decode(recv(&mut cmds, "spBv1.0/G/NCMD/E").await.as_slice()).unwrap();
    assert_eq!(req.metrics[0].name.as_deref(), Some(sparkplug::REBIRTH));
    assert_eq!(req.metrics[0].value, Some(MetricValue::Boolean(true)));
    // rebirth: good again
    publish_until(&edge, "spBv1.0/G/NBIRTH/E", &nbirth, "rebirth", || {
        qual(&h, "c1/node/temp") == Some(Quality::Good)
    })
    .await;
    wait("node connected", || {
        state(&h, "c1/node").as_deref() == Some("connected")
    })
    .await;
    h.stop().await;
}

/// TLS terminator in front of the broker with a certificate for
/// `localhost` signed by a fresh CA. Returns the port and the CA PEM.
async fn tls_proxy(target: u16) -> (u16, String) {
    use rcgen::{BasicConstraints, CertificateParams, IsCa, Issuer, KeyPair};
    let ca_key = KeyPair::generate().expect("ca key");
    let mut p = CertificateParams::new(Vec::<String>::new()).expect("ca params");
    p.is_ca = IsCa::Ca(BasicConstraints::Unconstrained);
    let ca = p.self_signed(&ca_key).expect("ca cert");
    let issuer = Issuer::new(p, ca_key);
    let key = KeyPair::generate().expect("server key");
    let cert = CertificateParams::new(vec!["localhost".to_owned()])
        .expect("server params")
        .signed_by(&key, &issuer)
        .expect("server cert");
    let provider = Arc::new(rustls::crypto::ring::default_provider());
    let cfg = rustls::ServerConfig::builder_with_provider(provider)
        .with_safe_default_protocol_versions()
        .expect("tls versions")
        .with_no_client_auth()
        .with_single_cert(
            vec![cert.der().clone()],
            rustls_pki_types::PrivateKeyDer::Pkcs8(key.serialize_der().into()),
        )
        .expect("server config");
    let acceptor = tokio_rustls::TlsAcceptor::from(Arc::new(cfg));
    let l = TcpListener::bind("127.0.0.1:0").await.expect("bind");
    let port = l.local_addr().expect("addr").port();
    tokio::spawn(async move {
        while let Ok((s, _)) = l.accept().await {
            let acc = acceptor.clone();
            tokio::spawn(async move {
                if let Ok(mut a) = acc.accept(s).await {
                    if let Ok(mut b) = TcpStream::connect(("127.0.0.1", target)).await {
                        let _ = tokio::io::copy_bidirectional(&mut a, &mut b).await;
                    }
                }
            });
        }
    });
    (port, ca.pem())
}

#[tokio::test(flavor = "multi_thread")]
async fn tls_with_ca_file() {
    let port = broker(None);
    let (tport, ca_pem) = tls_proxy(port).await;
    let (_, other_ca) = tls_proxy(port).await;
    let dir = std::env::temp_dir().join(format!("wyrm-mqtt-tls-{}-{tport}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let good = dir.join("ca.pem");
    let wrong = dir.join("other.pem");
    std::fs::write(&good, ca_pem).unwrap();
    std::fs::write(&wrong, other_ca).unwrap();
    let tree = |ca: &std::path::Path| {
        conn(
            tport,
            &[
                ("host", "localhost".into()),
                ("tls", true.into()),
                ("ca_file", ca.to_string_lossy().as_ref().into()),
            ],
            plain(map(&[("t", pt(&[("topic", "tls/t".into())]))])),
        )
    };
    let h = H::start(tree(&good)).await;
    let (pubc, _) = client(port, "pub-tls", &[]).await;
    publish_until(&pubc, "tls/t", b"5", "value over tls", || {
        val(&h, "c1/d1/t") == Some(Value::UInt(5))
    })
    .await;
    assert_eq!(state(&h, "c1").as_deref(), Some("connected"));
    h.stop().await;
    // a server certificate from another CA is rejected
    let h = H::start(tree(&wrong)).await;
    wait("untrusted server", || {
        error(&h, "c1").is_some_and(|e| e.starts_with("transport: connect"))
    })
    .await;
    h.stop().await;
    let _ = std::fs::remove_dir_all(&dir);
}

/// As in DSA, credentials come with the connection: `password` (and
/// `key_pem`) are secret parameters of `add_connection`, kept sealed by the
/// link, never shown, dropped by an edit that changes the destination.
#[tokio::test(flavor = "multi_thread")]
async fn password_in_the_connection() {
    let port = broker(Some(("wyrm", "pw-7777777")));
    let dir = std::env::temp_dir().join(format!("wyrm-mqtt-pw-{}-{port}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let start = || {
        let dir = dir.clone();
        H::start_with(Tree(map(&[("connections", map(&[]))])), move |c| {
            c.data_dir = Some(dir);
            c.secrets.insert(
                wyrm_link_sdk::driver::persist::STORE_KEY,
                Secret::new(vec![3u8; 32]),
            );
        })
    };
    let h = start().await;
    let add = map(&[
        ("name", "c1".into()),
        ("host", "127.0.0.1".into()),
        ("port", Value::UInt(port.into())),
        ("timeout_ms", Value::UInt(1500)),
        ("username", "wyrm".into()),
        ("password", "pw-7777777".into()),
    ]);
    assert_eq!(act(&h, "", "add_connection", add).await, Some(Status::Ok));
    wait("connected with the password", || {
        state(&h, "c1").as_deref() == Some("connected")
    })
    .await;
    let (_, m) = h.meta("c1").await;
    assert!(!format!("{m:?}").contains("pw-7777777"), "~meta hides it");
    let export = h
        .invoke("", "export", map(&[]), Some(h.ptok(Perm::Config)))
        .await;
    let exported = format!("{:?}", export.first().and_then(|r| r.value()));
    assert!(!exported.contains("pw-7777777"), "{exported}");
    // a plaintext password to a non-loopback host is refused
    let far = map(&[
        ("name", "c2".into()),
        ("host", "192.0.2.1".into()),
        ("username", "wyrm".into()),
        ("password", "pw-7777777".into()),
    ]);
    assert_eq!(
        act(&h, "", "add_connection", far).await,
        Some(Status::InvalidParameter)
    );
    h.stop().await;
    assert!(!std::fs::read(dir.join("framework.tree"))
        .unwrap()
        .windows(10)
        .any(|w| w == b"pw-7777777"));

    // restart: the connection and its password come back
    let h = start().await;
    wait("connected after restart", || {
        state(&h, "c1").as_deref() == Some("connected")
    })
    .await;
    // an edit without the password, same destination: kept
    let same = map(&[
        ("host", "127.0.0.1".into()),
        ("port", Value::UInt(port.into())),
        ("timeout_ms", Value::UInt(1600)),
        ("username", "wyrm".into()),
    ]);
    assert_eq!(act(&h, "c1", "edit", same).await, Some(Status::Ok));
    wait("still connected", || {
        state(&h, "c1").as_deref() == Some("connected")
    })
    .await;
    // another destination without the password: dropped, the broker refuses
    let moved = map(&[
        ("host", "localhost".into()),
        ("port", Value::UInt(port.into())),
        ("timeout_ms", Value::UInt(1500)),
        ("username", "wyrm".into()),
    ]);
    assert_eq!(act(&h, "c1", "edit", moved).await, Some(Status::Ok));
    wait("refused without the password", || {
        error(&h, "c1").is_some_and(|e| e.starts_with("transport: connect"))
    })
    .await;
    h.stop().await;
    let _ = std::fs::remove_dir_all(&dir);
}

async fn act(h: &H, path: &str, action: &str, args: Value) -> Option<Status> {
    h.invoke(path, action, args, Some(h.ptok(Perm::Config)))
        .await
        .first()
        .and_then(|r| status(&r.att))
}

/// The CA can come as PEM text in the connection instead of a file.
#[tokio::test(flavor = "multi_thread")]
async fn tls_with_ca_pem() {
    let port = broker(None);
    let (tport, ca_pem) = tls_proxy(port).await;
    let tree = |ca: &str| {
        conn(
            tport,
            &[
                ("host", "localhost".into()),
                ("tls", true.into()),
                ("ca_pem", ca.into()),
            ],
            plain(map(&[("t", pt(&[("topic", "tlspem/t".into())]))])),
        )
    };
    let h = H::start(tree(&ca_pem)).await;
    let (pubc, _) = client(port, "pub-tlspem", &[]).await;
    publish_until(&pubc, "tlspem/t", b"7", "value over tls", || {
        val(&h, "c1/d1/t") == Some(Value::UInt(7))
    })
    .await;
    h.stop().await;
    // a PEM that does not parse is a config error, kept as failed
    let h = H::start(tree(
        "-----BEGIN CERTIFICATE-----\nnope\n-----END CERTIFICATE-----\n",
    ))
    .await;
    wait("bad ca_pem", || {
        error(&h, "c1").is_some_and(|e| e.contains("ca_pem"))
    })
    .await;
    h.stop().await;
}
