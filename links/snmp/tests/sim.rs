//! The SNMP driver against its in-process agent, through the real wire
//! format (`TestHarness`: in-memory Zenoh session, UDP on loopback).

use std::sync::{Arc, Mutex};
use std::time::Duration;
use wyrm_core::{Perm, Quality, Sample, Status, TypeCode, Value};
use wyrm_link_sdk::driver::{NodeState, Tree};
use wyrm_link_sdk::{Secret, TestHarness};
use wyrm_link_snmp::ber::{Oid, SnmpValue};
use wyrm_link_snmp::{sim, Snmp};

type H = TestHarness<Snmp>;

fn map(kv: &[(&str, Value)]) -> Value {
    Value::Map(
        kv.iter()
            .map(|(k, v)| ((*k).to_owned(), v.clone()))
            .collect(),
    )
}

fn with(base: &[(&str, Value)], extra: &[(&str, Value)]) -> Value {
    let mut kv: Vec<(&str, Value)> = base.to_vec();
    for (k, v) in extra {
        kv.retain(|(n, _)| n != k);
        kv.push((k, v.clone()));
    }
    map(&kv)
}

/// A scalar point polled every 50 ms.
fn scalar(oid: &str, extra: &[(&str, Value)]) -> Value {
    with(
        &[("oid", oid.into()), ("poll_s", Value::Float(0.05))],
        extra,
    )
}

/// A table cell polled every 50 ms.
fn cell(column: &str, index: &str, extra: &[(&str, Value)]) -> Value {
    with(
        &[
            ("oid", column.into()),
            ("kind", "table_column".into()),
            ("index", index.into()),
            ("poll_s", Value::Float(0.05)),
        ],
        extra,
    )
}

const IF_DESCR: &str = "1.3.6.1.2.1.2.2.1.2";
const IF_SPEED: &str = "1.3.6.1.2.1.2.2.1.5";
const IF_PHYS: &str = "1.3.6.1.2.1.2.2.1.6";
const IF_IN: &str = "1.3.6.1.2.1.2.2.1.10";
const IF_HC_IN: &str = "1.3.6.1.2.1.31.1.1.1.6";
const SYS_DESCR: &str = "1.3.6.1.2.1.1.1.0";
const SYS_OBJECT_ID: &str = "1.3.6.1.2.1.1.2.0";
const SYS_UPTIME: &str = "1.3.6.1.2.1.1.3.0";
const SYS_CONTACT: &str = "1.3.6.1.2.1.1.4.0";
const SYS_NAME: &str = "1.3.6.1.2.1.1.5.0";

fn t(n: u32) -> String {
    format!("1.3.6.1.4.1.64999.1.{n}.0")
}

/// v2c connection params on the agent at `port`.
fn v2c(port: u16, extra: &[(&'static str, Value)]) -> Vec<(&'static str, Value)> {
    let mut c = vec![
        ("kind", Value::from("snmp_v2c")),
        ("host", "127.0.0.1".into()),
        ("port", Value::UInt(port.into())),
        ("community", "public".into()),
        ("timeout_ms", Value::UInt(200)),
        ("retries", Value::UInt(0)),
    ];
    for (k, v) in extra {
        c.retain(|(n, _)| n != k);
        c.push((k, v.clone()));
    }
    c
}

/// v3 connection params for `user` (passphrases `<user>-pass`).
fn v3(port: u16, user: &str, auth: &str, privp: &str) -> Vec<(&'static str, Value)> {
    let pass = format!("{user}-pass");
    vec![
        ("kind", Value::from("snmp_v3")),
        ("host", "127.0.0.1".into()),
        ("port", Value::UInt(port.into())),
        ("user", user.into()),
        ("auth_protocol", auth.into()),
        ("auth_passphrase", pass.clone().into()),
        ("priv_protocol", privp.into()),
        ("priv_passphrase", pass.into()),
        ("timeout_ms", Value::UInt(500)),
        ("retries", Value::UInt(0)),
    ]
}

/// `c1/d1` with connection params `conn`, device params `dev` and `points`.
fn tree(conn: &[(&str, Value)], dev: &[(&str, Value)], points: Value) -> Tree {
    let mut d: Vec<(&str, Value)> = vec![("ping_s", Value::Float(0.1))];
    d.extend_from_slice(dev);
    d.push(("points", points));
    let mut c = conn.to_vec();
    c.push(("devices", map(&[("d1", map(&d))])));
    Tree(map(&[("connections", map(&[("c1", map(&c))]))]))
}

fn state(h: &H, base: &str) -> Option<String> {
    match h.ctx().last(&format!("{base}/status"))?.v {
        Value::UInt(i) => NodeState::NAMES.get(i as usize).map(|s| (*s).to_owned()),
        _ => None,
    }
}

fn error(h: &H, base: &str) -> Option<String> {
    match h.ctx().last(&format!("{base}/error"))?.v {
        Value::Str(s) => Some(s),
        _ => None,
    }
}

fn val(h: &H, p: &str) -> Option<Value> {
    h.ctx().last(&format!("c1/d1/{p}")).map(|s| s.v)
}

fn qual(h: &H, p: &str) -> Option<Quality> {
    h.ctx().last(&format!("c1/d1/{p}")).map(|s| s.q)
}

async fn wait(what: &str, mut f: impl FnMut() -> bool) {
    // Generous: the workspace suite runs many sessions in parallel.
    let deadline = tokio::time::Instant::now() + Duration::from_secs(10);
    while !f() {
        assert!(tokio::time::Instant::now() < deadline, "timeout: {what}");
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
}

fn status(a: &wyrm_core::Attachment) -> Option<Status> {
    match a.status? {
        wyrm_core::status::StatusCode::Known(s) => Some(s),
        _ => None,
    }
}

/// Every `~val` sample published for `path`, in order.
async fn samples(h: &H, path: &str) -> Arc<Mutex<Vec<Sample>>> {
    let seen = Arc::new(Mutex::new(Vec::new()));
    let s = seen.clone();
    h.session()
        .declare_subscriber(h.key(path, "~val"))
        .callback(move |sample| {
            if let Ok(v) = wyrm_core::codec::from_slice(&sample.payload().to_bytes()) {
                s.lock().unwrap().push(v);
            }
        })
        .background()
        .await
        .expect("subscriber");
    seen
}

/// Invoke `action` on `path` with a token of `perm`.
async fn act(
    h: &H,
    path: &str,
    action: &str,
    args: Value,
    perm: Perm,
) -> (Option<Status>, Option<Value>) {
    let mut r = h.invoke(path, action, args, Some(h.ptok(perm))).await;
    assert_eq!(r.len(), 1, "{path} {action}: one reply");
    let r = r.remove(0);
    (status(&r.att), r.value())
}

#[tokio::test(flavor = "multi_thread")]
async fn conversions_of_every_type() {
    let (addr, _agent, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    let points = map(&[
        ("descr", scalar(SYS_DESCR, &[])),
        ("objid", scalar(SYS_OBJECT_ID, &[("conv", "string".into())])),
        (
            "uptime",
            scalar(SYS_UPTIME, &[("conv", "timeticks_s".into())]),
        ),
        (
            "temp",
            scalar(
                &t(1),
                &[
                    ("conv", "gauge".into()),
                    ("scale", Value::Float(0.5)),
                    ("offset", Value::Float(10.0)),
                    ("unit", "°C".into()),
                ],
            ),
        ),
        ("gauge", scalar(&t(2), &[("conv", "gauge".into())])),
        ("ip", scalar(&t(3), &[("conv", "ip".into())])),
        ("ticks", scalar(&t(4), &[("conv", "timeticks_s".into())])),
        ("opaque", scalar(&t(5), &[])),
        ("c64", scalar(&t(6), &[("conv", "counter64".into())])),
        ("hex", scalar(&t(7), &[])),
        ("ifdescr", cell(IF_DESCR, "2", &[])),
        ("speed", cell(IF_SPEED, "1", &[("conv", "gauge".into())])),
        ("mac", cell(IF_PHYS, "3", &[("conv", "mac".into())])),
        ("in2", cell(IF_IN, "2", &[("conv", "counter32".into())])),
        ("hcin", cell(IF_HC_IN, "2", &[("conv", "counter64".into())])),
    ]);
    let h = H::start(tree(&v2c(addr.port(), &[]), &[], points)).await;
    wait("all values", || {
        ["descr", "uptime", "c64", "hcin", "mac", "opaque"]
            .iter()
            .all(|p| val(&h, p).is_some())
    })
    .await;
    assert_eq!(val(&h, "descr"), Some(Value::from("WYRM SNMP simulator")));
    assert_eq!(val(&h, "objid"), Some(Value::from("1.3.6.1.4.1.64999")));
    assert!(matches!(val(&h, "uptime"), Some(Value::Float(s)) if (0.0..60.0).contains(&s)));
    assert_eq!(val(&h, "temp"), Some(Value::Float(-10.0)));
    assert_eq!(val(&h, "gauge"), Some(Value::UInt(650)));
    assert_eq!(val(&h, "ip"), Some(Value::from("192.0.2.1")));
    assert_eq!(val(&h, "ticks"), Some(Value::Float(123.45)));
    assert_eq!(val(&h, "opaque"), Some(Value::Bytes(vec![1, 2])));
    assert_eq!(val(&h, "c64"), Some(Value::UInt(u64::MAX - 1)));
    assert_eq!(val(&h, "hex"), Some(Value::from("de:ad:be:ef")));
    assert_eq!(val(&h, "ifdescr"), Some(Value::from("eth1")));
    assert_eq!(val(&h, "speed"), Some(Value::UInt(1_000_000_000)));
    assert_eq!(val(&h, "mac"), Some(Value::from("02:00:00:00:00:03")));
    assert_eq!(val(&h, "in2"), Some(Value::UInt(2000)));
    assert_eq!(val(&h, "hcin"), Some(Value::UInt(20_000_000_000)));
    let (_, m) = h.meta("c1/d1/temp").await;
    let m = m.unwrap();
    assert_eq!(m.ty, Some(TypeCode::Number));
    assert!(format!("{:?}", m.unit).contains("°C"));
    let (_, m) = h.meta("c1/d1/descr").await;
    assert_eq!(m.unwrap().ty, Some(TypeCode::Dynamic));
    let (_, m) = h.meta("c1/d1/mac").await;
    assert_eq!(m.unwrap().ty, Some(TypeCode::String));
    h.stop().await;
}

/// Scalars go in GETs of at most `max_varbinds`; table cells by GETBULK.
#[tokio::test(flavor = "multi_thread")]
async fn batches_of_max_varbinds_and_getbulk_columns() {
    let (addr, agent, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    let slow = [("poll_s", Value::Float(0.3))];
    let mut pts: Vec<(String, Value)> = (1..=7)
        .map(|n| (format!("t{n}"), scalar(&t(n), &slow)))
        .collect();
    for row in 1..=4 {
        pts.push((format!("d{row}"), cell(IF_DESCR, &row.to_string(), &slow)));
    }
    let refs: Vec<(&str, Value)> = pts.iter().map(|(k, v)| (k.as_str(), v.clone())).collect();
    let h = H::start(tree(
        &v2c(addr.port(), &[]),
        &[
            ("ping", Value::Bool(false)),
            ("max_varbinds", Value::UInt(3)),
            ("max_repetitions", Value::UInt(10)),
        ],
        map(&refs),
    ))
    .await;
    wait("all polled", || {
        (1..=7).all(|n| val(&h, &format!("t{n}")).is_some())
            && (1..=4).all(|r| val(&h, &format!("d{r}")).is_some())
    })
    .await;
    assert_eq!(val(&h, "d4"), Some(Value::from("eth3")));
    let gets = agent.lock().unwrap().gets.clone();
    // the open probe (1 varbind), then per poll: GETs of 3, 3, 1 and one GETBULK
    assert_eq!(gets[0], 1, "probe");
    let per_poll = &gets[1..5];
    assert_eq!(per_poll, [3, 3, 1, -1], "{gets:?}");
    assert!(gets.iter().all(|n| *n <= 3), "{gets:?}");
    h.stop().await;
}

/// `noSuchObject`, `noSuchInstance`, a missing row, `genErr` on one OID and
/// a conversion that does not fit fail their point only; `tooBig` splits.
#[tokio::test(flavor = "multi_thread")]
async fn point_errors_are_isolated() {
    let (addr, agent, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    {
        let mut a = agent.lock().unwrap();
        a.gen_err = Some(Oid::parse(&t(4)).unwrap());
        a.max_varbinds = Some(2);
    }
    let points = map(&[
        ("ok", scalar(SYS_NAME, &[])),
        ("ok2", scalar(&t(2), &[])),
        ("ok3", scalar(&t(3), &[])),
        ("noobj", scalar("1.3.6.1.2.1.99.1.0", &[])),
        ("noinst", scalar("1.3.6.1.2.1.1.4.7", &[])),
        ("generr", scalar(&t(4), &[])),
        ("wrongconv", scalar(SYS_NAME, &[("conv", "mac".into())])),
        ("norow", cell(IF_DESCR, "9", &[])),
        ("row1", cell(IF_DESCR, "1", &[])),
    ]);
    let h = H::start(tree(&v2c(addr.port(), &[]), &[], points)).await;
    wait("good values", || {
        val(&h, "ok") == Some(Value::from("sim"))
            && val(&h, "ok2").is_some()
            && val(&h, "ok3").is_some()
            && val(&h, "row1") == Some(Value::from("eth0"))
    })
    .await;
    for p in ["noobj", "noinst", "generr", "wrongconv", "norow"] {
        wait(p, || qual(&h, p) == Some(Quality::Bad)).await;
    }
    for p in ["ok", "ok2", "ok3", "row1"] {
        assert_eq!(qual(&h, p), Some(Quality::Good), "{p}");
    }
    assert_eq!(state(&h, "c1/d1").as_deref(), Some("connected"));
    h.stop().await;
}

/// A diagnostics counter of `c1` (published when `~meta` is read).
async fn diag(h: &H, name: &str) -> u64 {
    h.meta("c1").await;
    match h.ctx().last(&format!("c1/{name}")).map(|s| s.v) {
        Some(Value::UInt(x)) => x,
        _ => 0,
    }
}

/// Wait until the diagnostics counter `name` of `c1` is at least `n`.
async fn wait_diag(h: &H, name: &str, n: u64) {
    let deadline = tokio::time::Instant::now() + Duration::from_secs(10);
    while diag(h, name).await < n {
        assert!(tokio::time::Instant::now() < deadline, "{name} >= {n}");
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
}

/// One varbind whose value does not fit its type (an INTEGER of no
/// octets) fails that point only: the other points of the same GET keep
/// their values, the device stays connected, and nothing is counted as a
/// late or undecodable reply.
#[tokio::test(flavor = "multi_thread")]
async fn a_malformed_value_fails_its_point_only() {
    let (addr, _agent, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    let points = map(&[
        ("a", scalar(SYS_NAME, &[])),
        ("broken", scalar(&t(9), &[])),
        ("c", scalar(&t(2), &[])),
    ]);
    let h = H::start(tree(&v2c(addr.port(), &[]), &[], points)).await;
    wait("good values", || {
        val(&h, "a") == Some(Value::from("sim")) && val(&h, "c") == Some(Value::UInt(650))
    })
    .await;
    wait("broken is bad", || qual(&h, "broken") == Some(Quality::Bad)).await;
    tokio::time::sleep(Duration::from_millis(300)).await;
    for p in ["a", "c"] {
        assert_eq!(qual(&h, p), Some(Quality::Good), "{p}");
    }
    assert_eq!(state(&h, "c1/d1").as_deref(), Some("connected"));
    assert_eq!(diag(&h, "late_replies").await, 0, "no late reply");
    assert_eq!(
        diag(&h, "undecodable_replies").await,
        0,
        "nothing undecodable"
    );
    h.stop().await;
}

/// SET is a request/response; the value comes from the read-back.
#[tokio::test(flavor = "multi_thread")]
async fn writes_and_read_back() {
    let (addr, agent, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    let wr = ("writable", Value::Bool(true));
    let points = map(&[
        (
            "contact",
            scalar(
                SYS_CONTACT,
                &[
                    wr.clone(),
                    ("conv", "string".into()),
                    ("set_type", "octet_string".into()),
                ],
            ),
        ),
        (
            "temp",
            scalar(
                &t(1),
                &[
                    wr.clone(),
                    ("conv", "gauge".into()),
                    ("scale", Value::Float(0.5)),
                    ("offset", Value::Float(10.0)),
                ],
            ),
        ),
        (
            "limit",
            scalar(&t(2), &[wr.clone(), ("set_type", "gauge32".into())]),
        ),
        // the agent's sysName is read-only: notWritable
        (
            "name",
            scalar(SYS_NAME, &[wr.clone(), ("set_type", "octet_string".into())]),
        ),
        // an INTEGER object written as Gauge32: wrongType
        (
            "wrongtype",
            scalar(&t(1), &[wr.clone(), ("set_type", "gauge32".into())]),
        ),
        ("ro", scalar(SYS_DESCR, &[])),
    ]);
    let h = H::start(tree(&v2c(addr.port(), &[]), &[], points)).await;
    wait("polled", || {
        val(&h, "contact").is_some() && val(&h, "limit").is_some()
    })
    .await;
    let w = || Some(h.ptok(Perm::Write));
    let att = h.set("c1/d1/contact", "noc@example.net", w()).await;
    assert_eq!(status(&att), Some(Status::Ok));
    wait("contact read back", || {
        val(&h, "contact") == Some(Value::from("noc@example.net"))
    })
    .await;
    // 30 °C = (30 - 10) / 0.5 = 40 on the wire
    let att = h.set("c1/d1/temp", 30.0, w()).await;
    assert_eq!(status(&att), Some(Status::Ok));
    assert_eq!(
        agent.lock().unwrap().get(&Oid::parse(&t(1)).unwrap().0),
        Some(SnmpValue::Integer(40))
    );
    wait("temp read back", || {
        val(&h, "temp") == Some(Value::Float(30.0))
    })
    .await;
    let att = h.set("c1/d1/limit", 700u64, w()).await;
    assert_eq!(status(&att), Some(Status::Ok));
    wait("limit", || val(&h, "limit") == Some(Value::UInt(700))).await;
    // refused by the agent, or by the link
    let n = agent.lock().unwrap().sets.len();
    for (p, v) in [
        ("name", Value::from("x")),
        ("wrongtype", Value::UInt(1)),
        ("ro", Value::from("x")),
        ("limit", Value::Int(-1)),
    ] {
        let att = h.set(&format!("c1/d1/{p}"), v, w()).await;
        assert_ne!(status(&att), Some(Status::Ok), "{p}");
    }
    assert_eq!(agent.lock().unwrap().sets.len(), n, "nothing applied");
    assert_eq!(val(&h, "name"), Some(Value::from("sim")));
    h.stop().await;
}

/// `rate_per_s`: no value from the first sample; a Counter32 that wraps
/// gives the true rate, not 4 G/s.
#[tokio::test(flavor = "multi_thread")]
async fn rates_wrap_and_start_again() {
    let (addr, agent, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    let rate = |extra: &[(&'static str, Value)]| {
        let mut e = vec![
            ("conv", Value::from("rate_per_s")),
            ("poll_s", Value::Float(0.2)),
        ];
        e.extend_from_slice(extra);
        e
    };
    let points = map(&[
        // row 1 starts just below the Counter32 wrap
        ("in1", cell(IF_IN, "1", &rate(&[]))),
        (
            "hc1_bits",
            cell(IF_HC_IN, "1", &rate(&[("scale", Value::Float(8.0))])),
        ),
    ]);
    let h = H::start(tree(&v2c(addr.port(), &[]), &[], points)).await;
    let seen = samples(&h, "c1/d1/in1").await;
    // 1000 octets per tick for row 1, a tick every 100 ms: about 10 000 /s
    let ticker = {
        let agent = agent.clone();
        tokio::spawn(async move {
            loop {
                tokio::time::sleep(Duration::from_millis(100)).await;
                agent.lock().unwrap().tick(1);
            }
        })
    };
    wait("wrapped", || {
        matches!(
            agent.lock().unwrap().get(&[1, 3, 6, 1, 2, 1, 2, 2, 1, 10, 1]),
            Some(SnmpValue::Counter32(x)) if x < 1_000_000
        )
    })
    .await;
    wait("rates", || {
        seen.lock().unwrap().len() >= 5 && val(&h, "hc1_bits").is_some()
    })
    .await;
    // No spike from the wrap (a wrong wrap is about 4e9 / 0.2 s); a loaded
    // host may miss a tick in one poll window, so only one sample has to
    // be in range.
    let rates: Vec<f64> = seen
        .lock()
        .unwrap()
        .iter()
        .map(|s| match s.v {
            Value::Float(r) => r,
            ref v => panic!("rate {v:?}"),
        })
        .collect();
    assert!(
        rates.iter().all(|r| (0.0..=40_000.0).contains(r)),
        "{rates:?}"
    );
    assert!(
        rates.iter().any(|r| (1000.0..=40_000.0).contains(r)),
        "{rates:?}"
    );
    let Some(Value::Float(bits)) = val(&h, "hc1_bits") else {
        panic!("bits")
    };
    assert!((8000.0..=320_000.0).contains(&bits), "bits {bits}");
    // the agent restarts (sysUpTime goes down): no spike, rates go on
    agent.lock().unwrap().restart();
    let before = seen.lock().unwrap().len();
    wait("rates after restart", || {
        seen.lock().unwrap().len() >= before + 3
    })
    .await;
    for s in seen.lock().unwrap().iter() {
        assert!(matches!(s.v, Value::Float(r) if r <= 40_000.0), "{s:?}");
    }
    ticker.abort();
    h.stop().await;
}

/// No answer: `uncertain/stale`, then `bad/comm_fail` and the device fails.
#[tokio::test(flavor = "multi_thread")]
async fn silent_agent_degrades_quality() {
    let (addr, agent, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    let points = map(&[("name", scalar(SYS_NAME, &[]))]);
    let h = H::start(tree(&v2c(addr.port(), &[]), &[], points)).await;
    wait("good", || qual(&h, "name") == Some(Quality::Good)).await;
    let seen = samples(&h, "c1/d1/name").await;
    agent.lock().unwrap().silent = true;
    wait("bad", || qual(&h, "name") == Some(Quality::Bad)).await;
    assert!(
        seen.lock()
            .unwrap()
            .iter()
            .any(|s| s.q == Quality::Uncertain),
        "uncertain/stale first"
    );
    assert_eq!(val(&h, "name"), Some(Value::from("sim")), "value kept");
    wait("device failed", || {
        state(&h, "c1/d1").as_deref() == Some("failed")
    })
    .await;
    // back again
    agent.lock().unwrap().silent = false;
    wait("good again", || qual(&h, "name") == Some(Quality::Good)).await;
    h.stop().await;
}

/// A reply after its timeout is dropped (request ids), counted, and its
/// values are never published.
#[tokio::test(flavor = "multi_thread")]
async fn a_late_reply_is_never_taken() {
    let (addr, agent, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    let points = map(&[("name", scalar(SYS_NAME, &[("poll_s", Value::Float(0.1))]))]);
    let h = H::start(tree(
        &v2c(addr.port(), &[]),
        &[("ping", Value::Bool(false))],
        points,
    ))
    .await;
    let seen = samples(&h, "c1/d1/name").await;
    wait("good", || qual(&h, "name") == Some(Quality::Good)).await;
    let marker = SnmpValue::OctetString(b"LATE".to_vec());
    agent.lock().unwrap().late_next = Some((Duration::from_millis(300), marker));
    // Diagnostics are published when read.
    let deadline = tokio::time::Instant::now() + Duration::from_secs(10);
    loop {
        h.meta("c1").await;
        let late = h.ctx().last("c1/late_replies").map(|s| s.v);
        if matches!(late, Some(Value::UInt(x)) if x >= 1) {
            break;
        }
        assert!(tokio::time::Instant::now() < deadline, "late reply counted");
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
    wait("good after", || {
        let s = seen.lock().unwrap();
        s.last().is_some_and(|s| s.q == Quality::Good)
    })
    .await;
    assert!(
        !seen
            .lock()
            .unwrap()
            .iter()
            .any(|s| s.v == Value::from("LATE")),
        "the late value was published"
    );
    h.stop().await;
}

/// Nothing listens: `open` fails (connection `failed` with `error`, the
/// device `stopped_by_parent`); an agent that comes up is connected.
#[tokio::test(flavor = "multi_thread")]
async fn unreachable_agent_then_reconnect() {
    let port = {
        let s = std::net::UdpSocket::bind("127.0.0.1:0").unwrap();
        s.local_addr().unwrap().port()
    };
    let points = map(&[("name", scalar(SYS_NAME, &[]))]);
    let h = H::start(tree(&v2c(port, &[]), &[], points)).await;
    wait("connection failed", || {
        state(&h, "c1").as_deref() == Some("failed") && error(&h, "c1").is_some()
    })
    .await;
    wait("device stopped by parent", || {
        state(&h, "c1/d1").as_deref() == Some("stopped_by_parent")
    })
    .await;
    let e = error(&h, "c1").unwrap();
    assert!(e.starts_with("transport:"), "{e}");
    let agent = sim::Shared::new(Mutex::new(sim::Agent::new()));
    let (_, task) = sim::spawn_with(&format!("127.0.0.1:{port}"), agent)
        .await
        .unwrap();
    wait("reconnected", || {
        state(&h, "c1").as_deref() == Some("connected") && qual(&h, "name") == Some(Quality::Good)
    })
    .await;
    // the agent goes away: ICMP port unreachable on the connected socket
    // drops the connection; it reopens and fails (nothing answers)
    task.abort();
    wait("connection down", || {
        state(&h, "c1").as_deref() != Some("connected")
            && state(&h, "c1/d1").as_deref() == Some("stopped_by_parent")
    })
    .await;
    wait("bad", || qual(&h, "name") == Some(Quality::Bad)).await;
    h.stop().await;
}

/// A wrong community gets no answer (agents drop such requests).
#[tokio::test(flavor = "multi_thread")]
async fn wrong_community_is_silence() {
    let (addr, agent, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    let points = map(&[("name", scalar(SYS_NAME, &[]))]);
    let h = H::start(tree(
        &v2c(addr.port(), &[("community", "wrong".into())]),
        &[],
        points,
    ))
    .await;
    wait("failed", || {
        error(&h, "c1").is_some_and(|e| e.contains("no answer"))
    })
    .await;
    assert!(agent.lock().unwrap().bad_community >= 1);
    let e = error(&h, "c1").unwrap();
    assert!(
        !e.contains("wrong"),
        "the community is not in the error: {e}"
    );
    h.stop().await;
}

/// A device's community override (an agent view of its own).
#[tokio::test(flavor = "multi_thread")]
async fn device_community_override() {
    let (addr, agent, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    agent.lock().unwrap().communities.push("vlan10".into());
    let pts = || map(&[("name", scalar(SYS_NAME, &[]))]);
    let mut c = v2c(addr.port(), &[]);
    c.push((
        "devices",
        map(&[
            (
                "own",
                map(&[("community", "vlan10".into()), ("points", pts())]),
            ),
            (
                "bogus",
                map(&[
                    ("community", "nope".into()),
                    ("ping_s", Value::Float(0.1)),
                    ("points", pts()),
                ]),
            ),
        ]),
    ));
    let h = H::start(Tree(map(&[("connections", map(&[("c1", map(&c))]))]))).await;
    wait("own community", || {
        h.ctx()
            .last("c1/own/name")
            .is_some_and(|s| s.q == Quality::Good)
    })
    .await;
    wait("bogus community fails", || {
        state(&h, "c1/bogus").as_deref() == Some("failed")
    })
    .await;
    let (_, m) = h.meta("c1/own").await;
    assert!(!format!("{m:?}").contains("vlan10"), "override hidden");
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn authorization_error_fails_the_device() {
    let (addr, agent, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    let points = map(&[("name", scalar(SYS_NAME, &[]))]);
    let h = H::start(tree(&v2c(addr.port(), &[]), &[], points)).await;
    wait("good", || qual(&h, "name") == Some(Quality::Good)).await;
    agent.lock().unwrap().auth_error = true;
    wait("device failed", || {
        state(&h, "c1/d1").as_deref() == Some("failed")
            && error(&h, "c1/d1").is_some_and(|e| e.contains("authorizationError"))
    })
    .await;
    wait("bad", || qual(&h, "name") == Some(Quality::Bad)).await;
    h.stop().await;
}

/// SHA-1 and SHA-256 with AES-128, and authNoPriv.
#[tokio::test(flavor = "multi_thread")]
async fn v3_users_read_and_write() {
    let (addr, agent, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    for (user, auth, privp) in [
        ("sha1user", "sha1", "aes128"),
        ("sha256user", "sha256", "aes128"),
        ("authonly", "sha256", "none"),
    ] {
        let points = map(&[
            ("name", scalar(SYS_NAME, &[])),
            ("hcin", cell(IF_HC_IN, "3", &[])),
            (
                "contact",
                scalar(
                    SYS_CONTACT,
                    &[
                        ("writable", Value::Bool(true)),
                        ("set_type", "octet_string".into()),
                    ],
                ),
            ),
        ]);
        let h = H::start(tree(
            &v3(addr.port(), user, auth, privp),
            &[("context", "ctx1".into())],
            points,
        ))
        .await;
        wait(user, || {
            val(&h, "name") == Some(Value::from("sim"))
                && val(&h, "hcin") == Some(Value::UInt(30_000_000_000))
        })
        .await;
        let att = h
            .set("c1/d1/contact", user, Some(h.ptok(Perm::Write)))
            .await;
        assert_eq!(status(&att), Some(Status::Ok), "{user}");
        wait("read back", || {
            val(&h, "contact") == Some(Value::from(user))
        })
        .await;
        let (_, m) = h.meta("c1").await;
        let shown = format!("{m:?}");
        assert!(!shown.contains(&format!("{user}-pass")), "{shown}");
        h.stop().await;
    }
    assert_eq!(agent.lock().unwrap().sets.len(), 3);
}

/// Wrong credentials fail the connection with a clear message (and no
/// secret in it).
#[tokio::test(flavor = "multi_thread")]
async fn v3_refusals_are_clear() {
    let (addr, _agent, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    let mut wrong_auth = v3(addr.port(), "sha1user", "sha1", "aes128");
    wrong_auth.retain(|(k, _)| *k != "auth_passphrase");
    wrong_auth.push(("auth_passphrase", "not-the-pass".into()));
    let mut wrong_proto = v3(addr.port(), "sha1user", "sha256", "aes128");
    wrong_proto.retain(|(k, _)| *k != "timeout_ms");
    wrong_proto.push(("timeout_ms", Value::UInt(300)));
    let cases = [
        (wrong_auth, "usmStatsWrongDigests"),
        (wrong_proto, "usmStatsWrongDigests"),
        (
            v3(addr.port(), "nobody", "sha1", "aes128"),
            "usmStatsUnknownUserNames",
        ),
        (
            v3(addr.port(), "authonly", "sha256", "aes128"),
            "usmStatsUnsupportedSecLevels",
        ),
    ];
    for (conn, want) in cases {
        let h = H::start(tree(&conn, &[], map(&[]))).await;
        wait(want, || error(&h, "c1").is_some_and(|e| e.contains(want))).await;
        let e = error(&h, "c1").unwrap();
        assert!(!e.contains("-pass") && !e.contains("not-the"), "{e}");
        h.stop().await;
    }
}

/// An agent restart (new boots) is a `notInTimeWindow` report: the link
/// takes the new clock and sends again; values stay good.
#[tokio::test(flavor = "multi_thread")]
async fn v3_time_window_resync() {
    let (addr, agent, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    let points = map(&[("name", scalar(SYS_NAME, &[("poll_s", Value::Float(0.1))]))]);
    let h = H::start(tree(
        &v3(addr.port(), "sha256user", "sha256", "aes128"),
        &[],
        points,
    ))
    .await;
    wait("good", || qual(&h, "name") == Some(Quality::Good)).await;
    let seen = samples(&h, "c1/d1/name").await;
    agent.lock().unwrap().restart();
    agent.lock().unwrap().set(
        &Oid::parse(SYS_NAME).unwrap().0,
        SnmpValue::OctetString(b"after".to_vec()),
    );
    wait("after restart", || {
        val(&h, "name") == Some(Value::from("after"))
    })
    .await;
    assert!(
        seen.lock().unwrap().iter().all(|s| s.q == Quality::Good),
        "no miss"
    );
    assert_eq!(state(&h, "c1").as_deref(), Some("connected"));
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn walk_action() {
    let (addr, agent, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    for conn in [
        v2c(addr.port(), &[]),
        v3(addr.port(), "sha1user", "sha1", "aes128"),
    ] {
        let h = H::start(tree(
            &conn,
            &[("max_repetitions", Value::UInt(3))],
            map(&[]),
        ))
        .await;
        wait("connected", || {
            state(&h, "c1/d1").as_deref() == Some("connected")
        })
        .await;
        let (_, m) = h.meta("c1/d1").await;
        let acts = m.unwrap().actions.unwrap();
        assert_eq!(acts["walk"].level, Some(Perm::Config));
        // a reader or writer may not walk the agent with the link's credentials
        let requests = agent.lock().unwrap().requests;
        for perm in [Perm::Read, Perm::Write] {
            let (s, v) = act(&h, "c1/d1", "walk", map(&[("oid", "1.3.6.1".into())]), perm).await;
            assert_eq!(s, Some(Status::PermissionDenied), "{perm:?}");
            assert_eq!(v, None);
        }
        assert!(
            agent.lock().unwrap().requests <= requests + 20,
            "a refused walk sends nothing (a full walk would be ~170 requests; pings aside)"
        );
        let (s, v) = act(
            &h,
            "c1/d1",
            "walk",
            map(&[("oid", IF_DESCR.into())]),
            Perm::Config,
        )
        .await;
        assert_eq!(s, Some(Status::Ok));
        let Some(Value::Array(rows)) = v else {
            panic!("rows")
        };
        assert_eq!(rows.len(), 4);
        let Value::Map(first) = &rows[0] else {
            panic!("row")
        };
        assert_eq!(first["oid"], Value::from("1.3.6.1.2.1.2.2.1.2.1"));
        assert_eq!(first["type"], Value::from("octet_string"));
        assert_eq!(first["value"], Value::from("eth0"));
        // `max` stops it; the whole interfaces table
        let (_, v) = act(
            &h,
            "c1/d1",
            "walk",
            map(&[("oid", "1.3.6.1.2.1.2".into()), ("max", Value::UInt(10))]),
            Perm::Config,
        )
        .await;
        assert!(matches!(v, Some(Value::Array(r)) if r.len() == 10));
        let (s, _) = act(
            &h,
            "c1/d1",
            "walk",
            map(&[("oid", "nope".into())]),
            Perm::Config,
        )
        .await;
        assert_eq!(s, Some(Status::InvalidParameter));
        h.stop().await;
    }
}

/// Params are checked when added; secrets never show in `~meta`, `export`
/// or the sealed tree file.
#[tokio::test(flavor = "multi_thread")]
async fn add_bounds_and_secrets() {
    let (addr, agent, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    agent
        .lock()
        .unwrap()
        .communities
        .push("s3cret-community".into());
    let dir = std::env::temp_dir().join(format!(
        "wyrm-snmp-secrets-{}-{}",
        std::process::id(),
        addr.port()
    ));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let start = || {
        let d = dir.clone();
        H::start_with(Tree(map(&[("connections", map(&[]))])), move |c| {
            c.data_dir = Some(d);
            c.secrets.insert(
                wyrm_link_sdk::driver::persist::STORE_KEY,
                Secret::new(vec![5u8; 32]),
            );
        })
    };
    let h = start().await;
    let cfg = Perm::Config;
    let base = |kv: &[(&str, Value)]| {
        let mut m = vec![
            ("name", Value::from("c1")),
            ("host", "127.0.0.1".into()),
            ("port", Value::UInt(addr.port().into())),
            ("community", "s3cret-community".into()),
        ];
        for (k, v) in kv {
            m.retain(|(n, _)| n != k);
            m.push((k, v.clone()));
        }
        map(&m)
    };
    for bad in [
        base(&[("port", Value::UInt(0))]),
        base(&[("timeout_ms", Value::UInt(50))]),
        base(&[("retries", Value::UInt(9))]),
        base(&[("bogus", Value::UInt(1))]),
    ] {
        let (s, _) = act(&h, "", "add_snmp_v2c", bad, cfg).await;
        assert_eq!(s, Some(Status::InvalidParameter));
    }
    let short = map(&[
        ("name", "c3".into()),
        ("host", "127.0.0.1".into()),
        ("user", "u".into()),
        ("auth_passphrase", "short".into()),
        ("priv_passphrase", "long-enough-1".into()),
    ]);
    let (s, _) = act(&h, "", "add_snmp_v3", short, cfg).await;
    assert_eq!(s, Some(Status::InvalidParameter));
    let (s, _) = act(&h, "", "add_snmp_v2c", base(&[]), cfg).await;
    assert_eq!(s, Some(Status::Ok));
    wait("connected", || {
        state(&h, "c1").as_deref() == Some("connected")
    })
    .await;
    let v3add = map(&[
        ("name", "c2".into()),
        ("host", "127.0.0.1".into()),
        ("port", Value::UInt(addr.port().into())),
        ("user", "sha1user".into()),
        ("auth_protocol", "sha1".into()),
        ("auth_passphrase", "sha1user-pass".into()),
        ("priv_passphrase", "sha1user-pass".into()),
    ]);
    let (s, _) = act(&h, "", "add_snmp_v3", v3add, cfg).await;
    assert_eq!(s, Some(Status::Ok));
    wait("v3 connected", || {
        state(&h, "c2").as_deref() == Some("connected")
    })
    .await;
    // a device and a table cell (the point param `kind` is the driver's)
    for c in ["c1", "c2"] {
        let (s, _) = act(&h, c, "add_device", map(&[("name", "d1".into())]), cfg).await;
        assert_eq!(s, Some(Status::Ok));
        let mut p = match cell(IF_DESCR, "2", &[]) {
            Value::Map(m) => m,
            _ => unreachable!(),
        };
        p.insert("name".into(), "if2".into());
        let (s, _) = act(&h, &format!("{c}/d1"), "add_point", Value::Map(p), cfg).await;
        assert_eq!(s, Some(Status::Ok));
    }
    let cell_good = |h: &H, c: &str| {
        h.ctx()
            .last(&format!("{c}/d1/if2"))
            .is_some_and(|s| s.q == Quality::Good && s.v == Value::from("eth1"))
    };
    wait("cells", || cell_good(&h, "c1") && cell_good(&h, "c2")).await;
    for node in ["c1", "c2"] {
        let (_, m) = h.meta(node).await;
        let shown = format!("{m:?}");
        assert!(!shown.contains("s3cret-community") && !shown.contains("sha1user-pass"));
    }
    let (_, export) = act(&h, "", "export", map(&[]), cfg).await;
    let exported = format!("{export:?}");
    assert!(
        !exported.contains("s3cret-community") && !exported.contains("sha1user-pass"),
        "{exported}"
    );
    h.stop().await;
    let sealed = std::fs::read(dir.join("framework.tree")).unwrap();
    for secret in [&b"s3cret-community"[..], b"sha1user-pass"] {
        assert!(!sealed.windows(secret.len()).any(|w| w == secret));
    }
    // a restart: connections, their sealed secrets and the cells come back
    let h = start().await;
    wait("back after restart", || {
        cell_good(&h, "c1") && cell_good(&h, "c2")
    })
    .await;
    let (_, m) = h.meta("c1/d1/if2").await;
    assert!(format!("{:?}", m.unwrap().cfg).contains("table_column"));
    h.stop().await;
    let _ = std::fs::remove_dir_all(&dir);
}
