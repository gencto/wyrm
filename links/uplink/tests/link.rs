//! The uplink against a fake MQTT broker and HTTP server on loopback: every kind's wire form,
//! credentials, the rate and the queue, births and rebirths, restarts and config entries.

mod common;

use common::{map, s, Broker, HttpServer, SimHost};
use wyrm_core::Value;
use wyrm_link_uplink::sparkplug;

fn json(p: &[u8]) -> serde_json::Value {
    serde_json::from_slice(p).unwrap_or_else(|_| panic!("not JSON: {}", String::from_utf8_lossy(p)))
}

#[test]
fn mqtt_uns_publishes_json_per_topic() {
    let broker = Broker::start();
    let mut h = SimHost::new(broker.port).with_mock(3);
    h.start();
    h.invoke(
        "",
        "add_mqtt",
        map(&[
            ("name", s("uns")),
            ("url", s(&format!("mqtt://127.0.0.1:{}", broker.port))),
            ("select", s("wy/s/downstream/mock")),
            ("flush_ms", Value::UInt(100)),
        ]),
    )
    .expect("add");
    assert!(h.nodes.contains_key("uns/status"));
    h.until("connected", |h| h.status("uns") == "connected");
    // the current values came with the subscription: one topic per point
    h.until("3 published", |h| h.published("uns") == 3);
    h.until("the broker saw them", |_| {
        broker.seen().publishes.len() == 3
    });
    let seen = broker.publishes("wyrm/s/downstream/mock/d1/temp");
    assert_eq!(seen.len(), 1);
    assert_eq!(json(&seen[0].1)["v"], 1);
    assert_eq!(json(&seen[0].1)["q"], "good");
    assert!(
        broker
            .seen()
            .publishes
            .iter()
            .all(|(_, _, q, r)| *q == 0 && *r),
        "QoS 0, retained"
    );
    let c = broker.seen().connects[0].clone();
    assert_eq!(c.client_id, "wyrm-s-uns");
    assert_eq!((c.username, c.password), (None, None));
    // a change goes up; the link's own nodes never do
    h.put_value("wy/s/downstream/mock/d1/temp", Value::Float(7.5));
    h.put_value("wy/s/downstream/uplink/uns/published", Value::UInt(99));
    h.until("4 published", |h| h.published("uns") == 4);
    h.until("the broker saw it", |_| {
        broker.publishes("mock/d1/temp").len() == 2
    });
    let seen = broker.publishes("mock/d1/temp");
    assert_eq!(json(&seen[1].1)["v"], 7.5);
    assert!(broker.publishes("uplink").is_empty());
    // a value payload is the value alone
    h.invoke(
        "uns",
        "edit",
        map(&[("payload", s("value")), ("retain", Value::Bool(false))]),
    )
    .expect("edit");
    h.until("reconnected", |h| {
        h.status("uns") == "connected" && broker.seen().connects.len() == 2
    });
    h.put_value("wy/s/downstream/mock/d2/temp", s("hot"));
    h.until("value payload", |_| {
        broker
            .publishes("mock/d2/temp")
            .iter()
            .any(|(_, p)| p == b"hot")
    });
    // keep-alive pings go out while nothing is sent (keep_alive 60 s → every 30 s)
    h.advance_ms(31_000);
    h.until("ping", |_| broker.seen().pings >= 1);
    assert_eq!(h.leaf("uns", "enabled"), Value::Bool(true));
}

#[test]
fn credentials_refused_until_set_password() {
    let broker = Broker::start();
    *broker.connack.lock().unwrap() = 5;
    let mut h = SimHost::new(broker.port).with_mock(1);
    h.start();
    h.invoke(
        "",
        "add_mqtt",
        map(&[
            ("name", s("x")),
            ("url", s(&format!("mqtt://127.0.0.1:{}", broker.port))),
            ("username", s("edge")),
            ("flush_ms", Value::UInt(100)),
        ]),
    )
    .expect("add");
    h.until("failed", |h| h.status("x") == "failed");
    assert_eq!(h.leaf("x", "error"), s("CONNACK: not authorized"));
    let before = broker.seen().connects.len();
    h.advance_ms(120_000);
    assert_eq!(
        broker.seen().connects.len(),
        before,
        "failed: no more attempts"
    );
    // the password unblocks it; the broker sees it in CONNECT
    *broker.connack.lock().unwrap() = 0;
    h.invoke("x", "set_password", map(&[("password", s("pw"))]))
        .expect("set_password");
    h.until("connected", |h| h.status("x") == "connected");
    let c = broker.seen().connects.last().unwrap().clone();
    assert_eq!(c.username.as_deref(), Some("edge"));
    assert_eq!(c.password.as_deref(), Some(b"pw".as_slice()));
    // the queue kept what came while it was down
    h.until("published", |h| h.published("x") >= 1);
    // a stopped broker: waiting, then back
    let r = h.invoke("x", "test_connection", Value::Null).expect("test");
    assert_eq!(
        r,
        map(&[
            (
                "message",
                s(&format!("connected to 127.0.0.1:{}", broker.port))
            ),
            ("success", Value::Bool(true))
        ])
    );
}

#[test]
fn rate_and_queue_bounds() {
    let broker = Broker::start();
    let mut h = SimHost::new(broker.port).with_mock(1);
    h.start();
    h.invoke(
        "",
        "add_mqtt",
        map(&[
            ("name", s("slow")),
            ("url", s(&format!("mqtt://127.0.0.1:{}", broker.port))),
            ("max_hz", Value::Float(1.0)),
            ("queue_max", Value::UInt(5)),
            ("flush_ms", Value::UInt(100)),
        ]),
    )
    .expect("add");
    h.until("connected", |h| h.status("slow") == "connected");
    h.until("the first value", |h| h.published("slow") == 1);
    // a burst within one second: only the latest value goes, after the period
    for i in 0..10 {
        h.put_value("wy/s/downstream/mock/d0/temp", Value::Int(100 + i));
    }
    h.advance_ms(300);
    assert_eq!(h.published("slow"), 1);
    h.until("the latest of the burst", |h| h.published("slow") == 2);
    let seen = broker.publishes("d0/temp");
    assert_eq!(json(&seen[1].1)["v"], 109);
    // the queue holds 5: values beyond it go, counted
    h.set("slow/enabled", Value::Bool(false)).expect("disable");
    assert_eq!(h.status("slow"), "disabled");
    h.invoke(
        "slow",
        "edit",
        map(&[("max_hz", Value::UInt(0)), ("enabled", Value::Bool(false))]),
    )
    .expect("edit");
    h.set("slow/enabled", Value::Bool(true)).expect("enable");
    h.until("connected again", |h| h.status("slow") == "connected");
    let base = h.published("slow");
    // disconnect the broker side: make the link wait, then fill the queue
    *broker.connack.lock().unwrap() = 3;
    h.invoke("slow", "edit", map(&[("flush_ms", Value::UInt(100))]))
        .expect("edit again");
    h.until("waiting", |h| h.status("slow") == "waiting");
    for i in 0..12 {
        h.put_value("wy/s/downstream/mock/d0/temp", Value::Int(i));
    }
    // the counters show on the next tick
    h.advance_ms(5_000);
    assert_eq!(h.leaf("slow", "dropped"), Value::UInt(7));
    assert_eq!(h.leaf("slow", "queued"), Value::UInt(5));
    *broker.connack.lock().unwrap() = 0;
    h.until("the 5 kept go", |h| h.published("slow") == base + 5);
    assert_eq!(h.leaf("slow", "queued"), Value::UInt(0));
}

#[test]
fn sparkplug_births_data_and_rebirth() {
    let broker = Broker::start();
    let mut h = SimHost::new(broker.port).with_mock(2);
    h.values
        .insert("wy/s/downstream/mock/name".into(), s("plc"));
    h.start();
    h.invoke(
        "",
        "add_sparkplug",
        map(&[
            ("name", s("ign")),
            ("url", s(&format!("mqtt://127.0.0.1:{}", broker.port))),
            ("group_id", s("Plant")),
            ("select", s("wy/s/downstream/mock")),
            ("flush_ms", Value::UInt(100)),
        ]),
    )
    .expect("add");
    h.until("connected", |h| h.status("ign") == "connected");
    h.until("born", |_| !broker.publishes("DBIRTH").is_empty());
    let c = broker.seen().connects[0].clone();
    assert_eq!(c.will_topic.as_deref(), Some("spBv1.0/Plant/NDEATH/s"));
    let topics: Vec<String> = broker
        .seen()
        .publishes
        .iter()
        .map(|(t, ..)| t.clone())
        .collect();
    assert_eq!(topics[0], "spBv1.0/Plant/NBIRTH/s");
    assert_eq!(topics[1], "spBv1.0/Plant/DBIRTH/s/mock");
    // the DBIRTH carries every metric of the device, with types
    let birth = broker.publishes("DBIRTH")[0].1.clone();
    let names = metric_names(&birth);
    assert_eq!(names, ["d0/temp", "d1/temp", "name"]);
    // a change is DDATA; a new metric makes a DBIRTH again
    h.put_value("wy/s/downstream/mock/d0/temp", Value::Float(2.5));
    h.until("DDATA", |_| !broker.publishes("DDATA").is_empty());
    assert_eq!(metric_names(&broker.publishes("DDATA")[0].1), ["d0/temp"]);
    h.put_value("wy/s/downstream/mock/d9/temp", Value::Int(9));
    h.until("DBIRTH again", |_| broker.publishes("DBIRTH").len() == 2);
    assert!(metric_names(&broker.publishes("DBIRTH")[1].1).contains(&"d9/temp".to_owned()));
    // NCMD rebirth: a new NBIRTH and DBIRTH on the same session
    let before = broker.publishes("NBIRTH").len();
    let on = Value::Bool(true);
    let cmd = sparkplug::payload(
        1,
        Some(0),
        None,
        &[sparkplug::Metric {
            name: sparkplug::REBIRTH,
            t_ms: 1,
            value: &on,
            datatype: None,
            with_type: true,
        }],
    );
    *broker.inject.lock().unwrap() = Some(("spBv1.0/Plant/NCMD/s".into(), cmd));
    // the command comes after the next NBIRTH: a new session has one, then the rebirth
    h.invoke("ign", "set_password", map(&[("password", s(""))]))
        .expect("restart");
    h.until("reborn", |_| broker.publishes("NBIRTH").len() >= before + 2);
    assert_eq!(broker.seen().connects.len(), 2);
    let wills: Vec<Vec<u8>> = broker
        .seen()
        .connects
        .iter()
        .map(|c| c.will_payload.clone())
        .collect();
    assert!(wills[1] != wills[0], "bdSeq moved on");
    assert_eq!(
        broker.publishes("DBIRTH").len(),
        4,
        "the device is born again with each NBIRTH"
    );
}

/// The metric names of a Sparkplug payload, through the command reader's field walk.
fn metric_names(p: &[u8]) -> Vec<String> {
    // every metric has a name; booleans only for commands: read names with a tiny walk
    let mut out = Vec::new();
    let mut b = p;
    let varint = |b: &[u8]| -> (u64, usize) {
        let mut v = 0u64;
        for (i, x) in b.iter().enumerate() {
            v |= u64::from(x & 0x7f) << (7 * i);
            if x & 0x80 == 0 {
                return (v, i + 1);
            }
        }
        panic!("varint")
    };
    while !b.is_empty() {
        let (k, n) = varint(b);
        b = &b[n..];
        match k & 7 {
            0 => {
                let (_, n) = varint(b);
                b = &b[n..];
            }
            1 => b = &b[8..],
            2 => {
                let (len, n) = varint(b);
                let val = &b[n..n + len as usize];
                if k >> 3 == 2 {
                    let (k2, n2) = varint(val);
                    if k2 == (1 << 3) | 2 {
                        let (len2, n3) = varint(&val[n2..]);
                        out.push(
                            String::from_utf8_lossy(&val[n2 + n3..n2 + n3 + len2 as usize])
                                .into_owned(),
                        );
                    }
                }
                b = &b[n + len as usize..];
            }
            _ => panic!("wire"),
        }
    }
    out.retain(|n| n != "bdSeq" && n != sparkplug::REBIRTH);
    out
}

#[test]
fn thingsboard_gateway_connect_and_telemetry() {
    let broker = Broker::start();
    let mut h = SimHost::new(broker.port).with_mock(2);
    h.start();
    h.invoke(
        "",
        "add_thingsboard",
        map(&[
            ("name", s("tb")),
            ("url", s(&format!("mqtt://127.0.0.1:{}", broker.port))),
            ("flush_ms", Value::UInt(100)),
        ]),
    )
    .expect("add");
    h.until("failed without a token", |h| h.status("tb") == "failed");
    h.invoke("tb", "set_password", map(&[("password", s("TOKEN1"))]))
        .expect("token");
    h.until("connected", |h| h.status("tb") == "connected");
    h.until("telemetry", |_| {
        !broker.publishes("v1/gateway/telemetry").is_empty()
    });
    let c = broker.seen().connects.last().unwrap().clone();
    assert_eq!(c.username.as_deref(), Some("TOKEN1"));
    assert_eq!(c.password, None);
    let connect = broker.publishes("v1/gateway/connect");
    assert_eq!(json(&connect[0].1), serde_json::json!({"device": "s-mock"}));
    let t = json(&broker.publishes("v1/gateway/telemetry")[0].1);
    let rows = t["s-mock"].as_array().unwrap();
    assert_eq!(rows.len(), 2);
    assert_eq!(rows[0]["values"]["d0/temp"], 0);
    assert!(
        broker.seen().publishes.iter().all(|(_, _, q, _)| *q == 1),
        "QoS 1"
    );
}

#[test]
fn azure_username_sas_and_events_topic() {
    let broker = Broker::start();
    let mut h = SimHost::new(broker.port).with_mock(1);
    h.start();
    let r = h.invoke(
        "",
        "add_azure",
        map(&[
            ("name", s("az")),
            ("hub", s("myhub")),
            ("device_id", s("edge-01")),
        ]),
    );
    assert!(
        r.unwrap_err().msg.contains("not in the link's net"),
        "the hub is not in net"
    );
    h.invoke(
        "",
        "add_azure",
        map(&[
            ("name", s("az")),
            ("hub", s("myhub")),
            ("device_id", s("edge-01")),
            ("url", s(&format!("mqtt://127.0.0.1:{}", broker.port))),
            ("flush_ms", Value::UInt(100)),
            ("sas_ttl_s", Value::UInt(300)),
        ]),
    )
    .expect("add");
    h.invoke(
        "az",
        "set_password",
        map(&[("password", s("c2VjcmV0a2V5"))]),
    )
    .expect("key");
    h.until("connected", |h| h.status("az") == "connected");
    h.until("events", |_| {
        !broker.publishes("messages/events").is_empty()
    });
    let c = broker.seen().connects.last().unwrap().clone();
    assert_eq!(c.client_id, "edge-01");
    assert_eq!(
        c.username.as_deref(),
        Some("myhub.azure-devices.net/edge-01/?api-version=2021-04-12")
    );
    let pw = String::from_utf8(c.password.unwrap()).unwrap();
    assert!(
        pw.starts_with("SharedAccessSignature sr=myhub.azure-devices.net%2Fdevices%2Fedge-01&sig=")
    );
    let (topic, payload) = broker.publishes("messages/events")[0].clone();
    assert_eq!(
        topic,
        "devices/edge-01/messages/events/%24.ct=application%2Fjson&%24.ce=utf-8"
    );
    let a = json(&payload);
    assert_eq!(a[0]["key"], "s/downstream/mock/d0/temp");
    // the token is renewed before it runs out: a new session
    h.advance_ms(200_000);
    h.until("renewed", |_| broker.seen().connects.len() == 2);
}

#[test]
fn aws_https_publish_is_signed() {
    let server = HttpServer::start(200);
    let mut h = SimHost::new(server.port).with_mock(2);
    h.start();
    h.invoke(
        "",
        "add_aws",
        map(&[
            ("name", s("aws")),
            ("url", s(&format!("http://127.0.0.1:{}", server.port))),
            ("region", s("eu-central-1")),
            ("access_key_id", s("AKIAEXAMPLE")),
            ("flush_ms", Value::UInt(100)),
        ]),
    )
    .expect("add");
    h.invoke(
        "aws",
        "set_password",
        map(&[("password", s("wJalrXUtnFEMI"))]),
    )
    .expect("secret");
    h.until("published", |h| h.published("aws") == 2);
    let reqs = server.requests.lock().unwrap().clone();
    assert_eq!(reqs[0].0, "POST /topics/wyrm%2Fs?qos=1 HTTP/1.1");
    let auth = reqs[0]
        .1
        .iter()
        .find(|(k, _)| k == "authorization")
        .unwrap()
        .1
        .clone();
    assert!(auth.starts_with("AWS4-HMAC-SHA256 Credential=AKIAEXAMPLE/"));
    assert!(auth.contains("/eu-central-1/iotdata/aws4_request"));
    assert!(auth.contains("SignedHeaders=host;x-amz-content-sha256;x-amz-date"));
    let body = json(&reqs[0].2);
    assert_eq!(body.as_array().unwrap().len(), 2);
    let r = h
        .invoke("aws", "test_connection", Value::Null)
        .expect("test");
    assert!(matches!(r, Value::Map(m) if m.get("success") == Some(&Value::Bool(true))));
}

#[test]
fn definitions_survive_restarts_and_config_entries_are_fixed() {
    let broker = Broker::start();
    let mut h = SimHost::new(broker.port).with_mock(1);
    let url = format!("mqtt://127.0.0.1:{}", broker.port);
    h.params = map(&[
        ("site", s("s")),
        ("own", s("wy/s/downstream/uplink")),
        ("net", s(&h.net)),
        (
            "upstreams",
            Value::Array(vec![map(&[
                ("name", s("fixed")),
                ("kind", s("mqtt")),
                ("url", s(&url)),
                ("topic_prefix", s("cfg")),
            ])]),
        ),
    ]);
    h.start();
    assert_eq!(h.status("fixed"), "connecting");
    assert!(
        h.invoke("fixed", "remove", Value::Null).is_err(),
        "config entries stay"
    );
    assert!(h
        .invoke("fixed", "edit", map(&[("qos", Value::UInt(1))]))
        .is_err());
    assert!(h.set("fixed/enabled", Value::Bool(false)).is_err());
    h.invoke("", "add_mqtt", map(&[("name", s("rt")), ("url", s(&url))]))
        .expect("add");
    assert!(
        h.invoke("", "add_mqtt", map(&[("name", s("rt")), ("url", s(&url))]))
            .is_err(),
        "names are unique"
    );
    assert!(h
        .invoke(
            "",
            "add_mqtt",
            map(&[("name", s("fixed")), ("url", s(&url))])
        )
        .is_err());
    h.invoke("rt", "set_password", map(&[("password", s("pw"))]))
        .expect("pw");
    h.until("both connected", |h| {
        h.status("rt") == "connected" && h.status("fixed") == "connected"
    });
    assert!(h.store_has("u/rt") && h.store_has("secret/rt") && !h.store_has("u/fixed"));
    h.restart();
    assert!(h.nodes.contains_key("rt/status") && h.nodes.contains_key("fixed/status"));
    h.until("connected after the restart", |h| {
        h.status("rt") == "connected"
    });
    let c = broker
        .seen()
        .connects
        .iter()
        .find(|c| c.client_id == "wyrm-s-rt")
        .unwrap()
        .clone();
    assert_eq!(
        c.password.as_deref(),
        Some(b"pw".as_slice()),
        "the secret came back"
    );
    h.invoke("rt", "remove", Value::Null).expect("remove");
    assert!(
        !h.nodes.contains_key("rt/status") && !h.store_has("u/rt") && !h.store_has("secret/rt")
    );
    assert_eq!(h.leaf("stats", "upstreams"), Value::UInt(1));
}
