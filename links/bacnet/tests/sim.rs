//! The `bacnet` driver against its simulator over real UDP on loopback,
//! through the wire format (`TestHarness`: in-memory Zenoh session).

use std::net::SocketAddr;
use std::time::Duration;
use wyrm_core::meta::TextOrCode;
use wyrm_core::{Perm, Quality, Status, TypeCode, Value};
use wyrm_link_bacnet::codec::{service, AppValue, NetAddr, ObjectId};
use wyrm_link_bacnet::sim::{self, objects};
use wyrm_link_bacnet::Bacnet;
use wyrm_link_sdk::driver::Tree;
use wyrm_link_sdk::TestHarness;

type H = TestHarness<Bacnet>;

const DEV: u32 = 1234;

fn map(kv: &[(&str, Value)]) -> Value {
    Value::Map(
        kv.iter()
            .map(|(k, v)| ((*k).to_owned(), v.clone()))
            .collect(),
    )
}

/// A point on `object_type` `instance`, polled every 50 ms.
fn pt(object_type: &str, instance: u64, extra: &[(&str, Value)]) -> Value {
    let mut kv = vec![
        ("object_type", Value::from(object_type)),
        ("instance", Value::UInt(instance)),
        ("poll_s", Value::Float(0.05)),
    ];
    for (k, v) in extra {
        kv.retain(|(n, _)| n != k);
        kv.push((k, v.clone()));
    }
    map(&kv)
}

/// `c1/d1` on the simulator at `sim`: connection params `conn` over the
/// test defaults (loopback, any port, Who-Is to the simulator, 200 ms, no
/// retries), device params `dev` over (instance 1234 at `sim`).
fn tree(sim: SocketAddr, conn: &[(&str, Value)], dev: &[(&str, Value)], points: Value) -> Tree {
    let mut d: Vec<(&str, Value)> = vec![
        ("instance", Value::UInt(DEV.into())),
        ("address", Value::Str(sim.to_string())),
        ("ping_s", Value::Float(0.1)),
    ];
    for (k, v) in dev {
        d.retain(|(n, _)| n != k);
        d.push((k, v.clone()));
    }
    d.push(("points", points));
    let mut c: Vec<(&str, Value)> = vec![
        ("bind_host", "127.0.0.1".into()),
        ("bind_port", Value::UInt(0)),
        ("broadcast", Value::Str(sim.to_string())),
        ("apdu_timeout_ms", Value::UInt(200)),
        ("apdu_retries", Value::UInt(0)),
    ];
    for (k, v) in conn {
        c.retain(|(n, _)| n != k);
        c.push((k, v.clone()));
    }
    c.push(("devices", map(&[("d1", map(&d))])));
    Tree(map(&[("connections", map(&[("c1", map(&c))]))]))
}

/// The `status` enum leaf as a state name.
fn state(h: &H, base: &str) -> Option<String> {
    match h.ctx().last(&format!("{base}/status"))?.v {
        Value::UInt(i) => wyrm_link_sdk::driver::NodeState::NAMES
            .get(i as usize)
            .map(|s| (*s).to_owned()),
        _ => None,
    }
}

async fn wait(what: &str, mut f: impl FnMut() -> bool) {
    // Generous: the workspace suite runs many sessions in parallel.
    let deadline = tokio::time::Instant::now() + Duration::from_secs(10);
    while !f() {
        assert!(tokio::time::Instant::now() < deadline, "timeout: {what}");
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
}

fn val(h: &H, p: &str) -> Option<Value> {
    h.ctx().last(&format!("c1/d1/{p}")).map(|s| s.v)
}

fn qual(h: &H, p: &str) -> Option<Quality> {
    h.ctx().last(&format!("c1/d1/{p}")).map(|s| s.q)
}

fn status(a: &wyrm_core::Attachment) -> Option<Status> {
    match a.status? {
        wyrm_core::status::StatusCode::Known(s) => Some(s),
        _ => None,
    }
}

/// Invoke `action` on `path` with a token of `perm`: status, value, error.
async fn act(
    h: &H,
    path: &str,
    action: &str,
    args: Value,
    perm: Perm,
) -> (Option<Status>, Option<Value>, String) {
    let mut r = h.invoke(path, action, args, Some(h.ptok(perm))).await;
    assert_eq!(r.len(), 1, "{path} {action}: one reply");
    let r = r.remove(0);
    let msg = r.att.err.clone().unwrap_or_default();
    (status(&r.att), r.value(), msg)
}

fn field<'a>(v: &'a Value, k: &str) -> &'a Value {
    match v {
        Value::Map(m) => m.get(k).unwrap_or_else(|| panic!("no {k} in {m:?}")),
        other => panic!("not a map: {other:?}"),
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn data_types_in_one_rpm_per_cycle() {
    let (addr, dev, _task) = sim::spawn("127.0.0.1:0", DEV).await.unwrap();
    dev.lock()
        .unwrap()
        .set_flags(objects::AI1, [false, false, true, true]);
    let points = map(&[
        ("temp", pt("analog_input", 1, &[("unit", "°C".into())])),
        ("sp", pt("analog_value", 1, &[])),
        ("fan", pt("binary_input", 1, &[])),
        ("mode", pt("multi_state_value", 1, &[])),
        ("count", pt("integer_value", 1, &[])),
        (
            "energy",
            pt("large_analog_value", 1, &[("scale", Value::Float(0.001))]),
        ),
        (
            "flags",
            pt("analog_input", 1, &[("property", "status_flags".into())]),
        ),
        (
            "units",
            pt("analog_input", 1, &[("property", "units".into())]),
        ),
        (
            "rel",
            pt("analog_input", 1, &[("property", "reliability".into())]),
        ),
        (
            "name",
            pt("device", DEV.into(), &[("property", "object_name".into())]),
        ),
        (
            "prio",
            pt(
                "analog_value",
                1,
                &[
                    ("property", "priority_array".into()),
                    ("array_index", Value::UInt(16)),
                ],
            ),
        ),
    ]);
    let h = H::start(tree(addr, &[], &[], points)).await;
    wait("all values", || {
        [
            "temp", "sp", "fan", "mode", "count", "energy", "flags", "units", "rel", "name",
        ]
        .iter()
        .all(|p| qual(&h, p) == Some(Quality::Good))
    })
    .await;
    assert_eq!(val(&h, "temp"), Some(Value::Float(21.5)));
    assert_eq!(val(&h, "sp"), Some(Value::Float(20.0)));
    assert_eq!(val(&h, "fan"), Some(Value::Bool(true)));
    assert_eq!(val(&h, "mode"), Some(Value::UInt(1)));
    assert_eq!(val(&h, "count"), Some(Value::Int(-5)));
    let Some(Value::Float(e)) = val(&h, "energy") else {
        panic!("energy")
    };
    assert!((e - 123_456.789_25).abs() < 1e-6, "{e}");
    let flags = val(&h, "flags").unwrap();
    assert_eq!(field(&flags, "overridden"), &Value::Bool(true));
    assert_eq!(field(&flags, "out_of_service"), &Value::Bool(true));
    assert_eq!(field(&flags, "fault"), &Value::Bool(false));
    assert_eq!(val(&h, "units"), Some(Value::UInt(62)));
    assert_eq!(val(&h, "rel"), Some(Value::UInt(0)));
    assert_eq!(val(&h, "name"), Some(Value::from("WYRM BACnet Simulator")));
    // an empty slot of the priority array is NULL (a dynamic point)
    wait("prio", || qual(&h, "prio") == Some(Quality::Good)).await;
    assert_eq!(val(&h, "prio"), Some(Value::Null));
    // meta: types and the unit
    let (_, m) = h.meta("c1/d1/temp").await;
    let m = m.unwrap();
    assert_eq!(m.ty, Some(TypeCode::Number));
    assert_eq!(m.unit, Some(TextOrCode::Text("°C".into())));
    let (_, m) = h.meta("c1/d1/fan").await;
    assert_eq!(m.unwrap().ty, Some(TypeCode::Bool));
    let (_, m) = h.meta("c1/d1/flags").await;
    assert_eq!(m.unwrap().ty, Some(TypeCode::Map));
    wait("device connected", || {
        state(&h, "c1/d1").as_deref() == Some("connected")
    })
    .await;
    // batching: every point (and the status-flags beside each present
    // value) in one RPM per cycle: ai1 pv/sf/units/reliability, av1 pv/sf
    // and its priority-array[16], bi1, msv1, iv1 and lav1 pv/sf, the
    // device name
    let sizes: Vec<usize> = dev.lock().unwrap().rpm_sizes.iter().copied().collect();
    assert!(!sizes.is_empty());
    assert!(sizes.iter().all(|n| *n == 16), "{sizes:?}");
    {
        let s = dev.lock().unwrap();
        // ReadProperty only for the pings (system-status)
        assert!(s.count(service::READ_PROPERTY) > 0);
        assert!(s.count(service::READ_PROPERTY_MULTIPLE) > 0);
    }
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn writes_with_priority_read_back_and_relinquish() {
    let (addr, dev, _task) = sim::spawn("127.0.0.1:0", DEV).await.unwrap();
    let w = |p: u64| {
        vec![
            ("writable", Value::Bool(true)),
            ("priority", Value::UInt(p)),
        ]
    };
    let points = map(&[
        ("sp", pt("analog_value", 1, &w(8))),
        ("cmd", pt("binary_value", 1, &w(16))),
        ("mode", pt("multi_state_value", 1, &w(10))),
        ("count", pt("integer_value", 1, &w(16))),
        ("temp", pt("analog_input", 1, &[])),
        // relinquish point of sp: its object, its priority 8
        (
            "sp_free",
            pt(
                "analog_value",
                1,
                &[
                    ("property", "relinquish".into()),
                    ("writable", Value::Bool(true)),
                    ("priority", Value::UInt(8)),
                ],
            ),
        ),
        // the device refuses this one: write-access-denied
        (
            "rel",
            pt(
                "analog_input",
                1,
                &[
                    ("property", "reliability".into()),
                    ("writable", Value::Bool(true)),
                ],
            ),
        ),
    ]);
    let h = H::start(tree(addr, &[], &[], points)).await;
    wait("polled", || {
        ["sp", "cmd", "mode", "count", "temp", "rel"]
            .iter()
            .all(|p| val(&h, p).is_some())
    })
    .await;
    let tok = || Some(h.ptok(Perm::Write));
    assert_eq!(
        status(&h.set("c1/d1/sp", 23.5, tok()).await),
        Some(Status::Ok)
    );
    {
        let s = dev.lock().unwrap();
        let prio = s.priorities(objects::AV1).unwrap();
        assert_eq!(prio[7], Some(AppValue::Real(23.5)));
        assert_eq!(s.writes.last().unwrap().3, Some(8));
    }
    assert_eq!(val(&h, "sp"), Some(Value::Float(23.5)), "read back");
    assert_eq!(
        status(&h.set("c1/d1/cmd", true, tok()).await),
        Some(Status::Ok)
    );
    assert_eq!(
        dev.lock().unwrap().pv(objects::BV1),
        Some(AppValue::Enumerated(1))
    );
    assert_eq!(val(&h, "cmd"), Some(Value::Bool(true)));
    assert_eq!(
        status(&h.set("c1/d1/mode", 3u64, tok()).await),
        Some(Status::Ok)
    );
    assert_eq!(
        dev.lock().unwrap().pv(objects::MSV1),
        Some(AppValue::Unsigned(3))
    );
    assert_eq!(
        status(&h.set("c1/d1/count", -42i64, tok()).await),
        Some(Status::Ok)
    );
    assert_eq!(val(&h, "count"), Some(Value::Int(-42)));
    // read-only point: refused by the link, nothing sent
    let n = dev.lock().unwrap().writes.len();
    assert_ne!(
        status(&h.set("c1/d1/temp", 1.0, tok()).await),
        Some(Status::Ok)
    );
    assert_eq!(dev.lock().unwrap().writes.len(), n);
    // refused by the device: the BACnet error text
    let att = h.set("c1/d1/rel", 3u64, tok()).await;
    assert_ne!(status(&att), Some(Status::Ok));
    assert!(
        att.err
            .as_deref()
            .unwrap_or_default()
            .contains("write-access-denied"),
        "{:?}",
        att.err
    );
    // the relinquish point: false while priority 8 holds a value
    wait("slot 8 taken", || {
        val(&h, "sp_free") == Some(Value::Bool(false))
    })
    .await;
    // writing false commands nothing
    let n = dev.lock().unwrap().writes.len();
    assert_ne!(
        status(&h.set("c1/d1/sp_free", false, tok()).await),
        Some(Status::Ok)
    );
    assert_eq!(dev.lock().unwrap().writes.len(), n);
    // a write user relinquishes the point's own priority (8) only
    assert_eq!(
        status(&h.set("c1/d1/sp_free", true, tok()).await),
        Some(Status::Ok)
    );
    {
        let s = dev.lock().unwrap();
        assert_eq!(s.priorities(objects::AV1).unwrap()[7], None);
        let w = s.writes.last().unwrap();
        assert_eq!(
            (w.0, w.1, &w.2, w.3),
            (objects::AV1, 85, &AppValue::Null, Some(8))
        );
    }
    assert_eq!(val(&h, "sp_free"), Some(Value::Bool(true)), "read back");
    wait("relinquished", || val(&h, "sp") == Some(Value::Float(20.0))).await;
    // security: the free-form device action (any object, any priority,
    // e.g. 1 = life safety) needs config, not write
    assert_eq!(
        status(&h.set("c1/d1/sp", 30.0, tok()).await),
        Some(Status::Ok)
    );
    let free = |prio: u64| {
        map(&[
            ("object_type", "analog_value".into()),
            ("instance", Value::UInt(1)),
            ("priority", Value::UInt(prio)),
        ])
    };
    let n = dev.lock().unwrap().writes.len();
    let (st, _, _) = act(&h, "c1/d1", "relinquish", free(8), Perm::Write).await;
    assert_ne!(st, Some(Status::Ok));
    assert_eq!(dev.lock().unwrap().writes.len(), n, "nothing sent");
    let (st, _, msg) = act(&h, "c1/d1", "relinquish", free(8), Perm::Config).await;
    assert_eq!(st, Some(Status::Ok), "{msg}");
    assert_eq!(dev.lock().unwrap().writes.last().unwrap().2, AppValue::Null);
    wait("relinquished by config", || {
        val(&h, "sp") == Some(Value::Float(20.0))
    })
    .await;
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn point_errors_are_isolated() {
    let (addr, dev, _task) = sim::spawn("127.0.0.1:0", DEV).await.unwrap();
    let points = map(&[
        ("ok", pt("analog_input", 1, &[])),
        ("ghost", pt("analog_input", 99, &[])),
        (
            "noprop",
            pt("binary_input", 1, &[("property", "cov_increment".into())]),
        ),
    ]);
    let h = H::start(tree(addr, &[], &[], points)).await;
    wait("ok good, others bad", || {
        qual(&h, "ok") == Some(Quality::Good)
            && qual(&h, "ghost") == Some(Quality::Bad)
            && qual(&h, "noprop") == Some(Quality::Bad)
    })
    .await;
    assert_eq!(state(&h, "c1/d1").as_deref(), Some("connected"));
    // an older device answers a whole RPM with one Error when an object is
    // unknown: the link reads each property then
    let rp0 = {
        let mut s = dev.lock().unwrap();
        s.rpm_error_whole = true;
        s.set_pv(objects::AI1, AppValue::Real(30.0));
        s.count(service::READ_PROPERTY)
    };
    wait("ok still read", || {
        val(&h, "ok") == Some(Value::Float(30.0))
    })
    .await;
    assert!(dev.lock().unwrap().count(service::READ_PROPERTY) > rp0 + 2);
    assert_eq!(qual(&h, "ghost"), Some(Quality::Bad));
    // a status-flags fault makes the value bad
    dev.lock()
        .unwrap()
        .set_flags(objects::AI1, [false, true, false, false]);
    wait("fault", || qual(&h, "ok") == Some(Quality::Bad)).await;
    dev.lock().unwrap().set_flags(objects::AI1, [false; 4]);
    wait("fault cleared", || qual(&h, "ok") == Some(Quality::Good)).await;
    assert_eq!(state(&h, "c1/d1").as_deref(), Some("connected"));
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn rpm_not_supported_falls_back_to_read_property() {
    let (addr, dev, _task) = sim::spawn("127.0.0.1:0", DEV).await.unwrap();
    dev.lock().unwrap().rpm_unsupported = true;
    let points = map(&[
        ("temp", pt("analog_input", 1, &[])),
        ("fan", pt("binary_input", 1, &[])),
    ]);
    let h = H::start(tree(addr, &[], &[("ping_s", Value::Float(0.0))], points)).await;
    wait("values", || {
        val(&h, "temp") == Some(Value::Float(21.5)) && val(&h, "fan") == Some(Value::Bool(true))
    })
    .await;
    let rp = dev.lock().unwrap().count(service::READ_PROPERTY);
    tokio::time::sleep(Duration::from_millis(300)).await;
    {
        let s = dev.lock().unwrap();
        assert_eq!(
            s.count(service::READ_PROPERTY_MULTIPLE),
            1,
            "RPM tried once"
        );
        assert!(
            s.count(service::READ_PROPERTY) > rp,
            "ReadProperty from then on"
        );
    }
    // a device with use_rpm off never gets an RPM
    let (addr2, dev2, _t2) = sim::spawn("127.0.0.1:0", DEV).await.unwrap();
    let h2 = H::start(tree(
        addr2,
        &[],
        &[("use_rpm", Value::Bool(false))],
        map(&[("temp", pt("analog_input", 1, &[]))]),
    ))
    .await;
    wait("value", || {
        h2.ctx().last("c1/d1/temp").map(|s| s.v) == Some(Value::Float(21.5))
    })
    .await;
    assert_eq!(
        dev2.lock().unwrap().count(service::READ_PROPERTY_MULTIPLE),
        0
    );
    h.stop().await;
    h2.stop().await;
}

/// The device's max APDU from I-Am (128) sizes the batches; a device that
/// claims more than it takes is split on its aborts and remembered.
#[tokio::test(flavor = "multi_thread")]
async fn batches_fit_the_max_apdu() {
    let (addr, dev, _task) = sim::spawn("127.0.0.1:0", DEV).await.unwrap();
    {
        let mut s = dev.lock().unwrap();
        s.max_apdu = 128;
        s.add_analog_inputs(40);
    }
    let no_flags = [("check_status", Value::Bool(false))];
    let pts: Vec<(String, Value)> = (100..140)
        .map(|i| (format!("ai{i}"), pt("analog_input", i, &no_flags)))
        .collect();
    let points = Value::Map(pts.into_iter().collect());
    let h = H::start(tree(addr, &[], &[], points.clone())).await;
    wait("all 40", || {
        (100..140).all(|i| val(&h, &format!("ai{i}")) == Some(Value::Float(i as f64)))
    })
    .await;
    {
        let s = dev.lock().unwrap();
        let max = s.rpm_sizes.iter().max().copied().unwrap();
        assert!(max <= 8 && s.rpm_sizes.len() >= 5, "{:?}", s.rpm_sizes);
    }
    h.stop().await;

    // the device param says 1476, the device takes 206: aborts split the
    // requests until they fit, and the limit is kept
    let (addr, dev, _task) = sim::spawn("127.0.0.1:0", DEV).await.unwrap();
    {
        let mut s = dev.lock().unwrap();
        s.max_apdu = 206;
        s.add_analog_inputs(40);
    }
    let h = H::start(tree(addr, &[], &[("max_apdu", Value::UInt(1476))], points)).await;
    wait("all 40 again", || {
        (100..140).all(|i| val(&h, &format!("ai{i}")) == Some(Value::Float(i as f64)))
    })
    .await;
    h.meta("c1/d1").await;
    wait(
        "splits counted",
        || matches!(h.ctx().last("c1/d1/rpm_splits").map(|s| s.v), Some(Value::UInt(n)) if n > 0),
    )
    .await;
    let before = dev.lock().unwrap().rpm_sizes.len();
    tokio::time::sleep(Duration::from_millis(300)).await;
    {
        let s = dev.lock().unwrap();
        let recent: Vec<usize> = s.rpm_sizes.iter().skip(before).copied().collect();
        assert!(!recent.is_empty());
        assert!(recent.iter().all(|n| *n <= 20), "learned cap: {recent:?}");
    }
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn silent_device_goes_stale_then_bad() {
    let (addr, dev, _task) = sim::spawn("127.0.0.1:0", DEV).await.unwrap();
    let h = H::start(tree(
        addr,
        &[],
        &[],
        map(&[("temp", pt("analog_input", 1, &[]))]),
    ))
    .await;
    wait("good", || qual(&h, "temp") == Some(Quality::Good)).await;
    dev.lock().unwrap().silent = true;
    let mut seen_uncertain = false;
    wait("uncertain/stale then bad/comm_fail", || {
        let q = qual(&h, "temp");
        seen_uncertain |= q == Some(Quality::Uncertain);
        q == Some(Quality::Bad)
    })
    .await;
    assert!(seen_uncertain, "stale before bad");
    assert_eq!(
        val(&h, "temp"),
        Some(Value::Float(21.5)),
        "the last value is kept"
    );
    wait("device failed", || {
        state(&h, "c1/d1").as_deref() == Some("failed")
    })
    .await;
    assert_eq!(
        state(&h, "c1").as_deref(),
        Some("connected"),
        "the port is fine"
    );
    // it answers again
    dev.lock().unwrap().silent = false;
    wait("good again", || qual(&h, "temp") == Some(Quality::Good)).await;
    wait("device connected", || {
        state(&h, "c1/d1").as_deref() == Some("connected")
    })
    .await;
    h.stop().await;
}

/// The device answers the first RPM of a poll but not the last: the points
/// of the request without an answer take the ladder alone (framework,
/// `DriverError::Device` per point), the others stay good and the device
/// connected.
#[tokio::test(flavor = "multi_thread")]
async fn a_batch_without_an_answer_goes_stale_alone() {
    let (addr, dev, _task) = sim::spawn("127.0.0.1:0", DEV).await.unwrap();
    {
        let mut s = dev.lock().unwrap();
        s.max_apdu = 128;
        s.add_analog_inputs(16);
    }
    let no_flags = [("check_status", Value::Bool(false))];
    let pts: Vec<(String, Value)> = (100..116)
        .map(|i| (format!("ai{i}"), pt("analog_input", i, &no_flags)))
        .collect();
    let h = H::start(tree(
        addr,
        &[],
        &[("ping_s", Value::Float(0.0))],
        Value::Map(pts.into_iter().collect()),
    ))
    .await;
    wait("all 16", || {
        (100..116).all(|i| qual(&h, &format!("ai{i}")) == Some(Quality::Good))
    })
    .await;
    assert!(dev.lock().unwrap().rpm_sizes.iter().all(|n| *n < 16));
    dev.lock().unwrap().drop_object = Some(ObjectId::new(0, 115));
    let mut seen_uncertain = false;
    wait("ai115 uncertain/stale then bad/comm_fail", || {
        let q = qual(&h, "ai115");
        seen_uncertain |= q == Some(Quality::Uncertain);
        q == Some(Quality::Bad)
    })
    .await;
    assert!(seen_uncertain, "stale before bad");
    assert_eq!(qual(&h, "ai100"), Some(Quality::Good), "the first batch");
    assert_eq!(state(&h, "c1/d1").as_deref(), Some("connected"));
    // it answers again
    dev.lock().unwrap().drop_object = None;
    wait("good again", || qual(&h, "ai115") == Some(Quality::Good)).await;
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn port_in_use_fails_the_connection_then_reconnects() {
    let (addr, _dev, _task) = sim::spawn("127.0.0.1:0", DEV).await.unwrap();
    let taken = std::net::UdpSocket::bind("127.0.0.1:0").unwrap();
    let port = taken.local_addr().unwrap().port();
    let h = H::start(tree(
        addr,
        &[("bind_port", Value::UInt(port.into()))],
        &[],
        map(&[("temp", pt("analog_input", 1, &[]))]),
    ))
    .await;
    wait("connection failed with an error", || {
        state(&h, "c1").as_deref() == Some("failed")
            && h.ctx()
                .last("c1/error")
                .is_some_and(|s| matches!(&s.v, Value::Str(e) if e.contains(&port.to_string())))
    })
    .await;
    wait("device stopped by parent", || {
        state(&h, "c1/d1").as_deref() == Some("stopped_by_parent")
    })
    .await;
    drop(taken);
    wait("reconnected", || {
        state(&h, "c1").as_deref() == Some("connected")
    })
    .await;
    wait("value", || qual(&h, "temp") == Some(Quality::Good)).await;
    h.stop().await;
}

/// A reply that comes after its timeout carries an older invoke id: it is
/// dropped (and counted), never taken for the next request.
#[tokio::test(flavor = "multi_thread")]
async fn late_reply_counted_and_values_kept_apart() {
    let (addr, dev, _task) = sim::spawn("127.0.0.1:0", DEV).await.unwrap();
    dev.lock()
        .unwrap()
        .set_pv(objects::AI1, AppValue::Real(11.0));
    let once = [("check_status", Value::Bool(false))];
    let points = map(&[
        ("a", pt("analog_input", 1, &once)),
        ("b", pt("analog_value", 1, &once)),
    ]);
    let h = H::start(tree(
        addr,
        &[],
        &[
            ("use_rpm", Value::Bool(false)),
            ("ping_s", Value::Float(0.0)),
            ("max_apdu", Value::UInt(1476)),
        ],
        points,
    ))
    .await;
    wait("both read", || {
        val(&h, "a") == Some(Value::Float(11.0)) && val(&h, "b") == Some(Value::Float(20.0))
    })
    .await;
    // one reply 300 ms late: the next request on that device sees it first
    dev.lock().unwrap().delay_next = Some(Duration::from_millis(300));
    let deadline = tokio::time::Instant::now() + Duration::from_secs(10);
    loop {
        // diagnostics are published on a read of the node
        h.meta("c1/d1").await;
        if h.ctx().last("c1/d1/late_replies").map(|s| s.v) == Some(Value::UInt(1)) {
            break;
        }
        assert!(
            tokio::time::Instant::now() < deadline,
            "timeout: late reply counted"
        );
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
    for _ in 0..20 {
        assert_eq!(val(&h, "a"), Some(Value::Float(11.0)));
        assert_eq!(val(&h, "b"), Some(Value::Float(20.0)));
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn who_is_finds_devices_and_resolves_addresses() {
    let (addr, dev, _task) = sim::spawn("127.0.0.1:0", DEV).await.unwrap();
    // no address: found by Who-Is (the "broadcast" goes to the simulator)
    let h = H::start(tree(
        addr,
        &[],
        &[("address", "".into())],
        map(&[("temp", pt("analog_input", 1, &[]))]),
    ))
    .await;
    wait("value via Who-Is", || {
        val(&h, "temp") == Some(Value::Float(21.5))
    })
    .await;
    assert!(dev.lock().unwrap().who_is >= 1);
    // the action
    let (st, v, msg) = act(
        &h,
        "c1",
        "who_is",
        map(&[("wait_ms", Value::UInt(300))]),
        Perm::Config,
    )
    .await;
    assert_eq!(st, Some(Status::Ok), "{msg}");
    let Some(Value::Array(found)) = v else {
        panic!("{v:?}")
    };
    assert_eq!(found.len(), 1);
    assert_eq!(field(&found[0], "instance"), &Value::UInt(DEV.into()));
    assert_eq!(field(&found[0], "address"), &Value::Str(addr.to_string()));
    assert_eq!(field(&found[0], "vendor_id"), &Value::UInt(999));
    assert_eq!(field(&found[0], "max_apdu"), &Value::UInt(1476));
    // a range without the device: nobody
    let (st, v, _) = act(
        &h,
        "c1",
        "who_is",
        map(&[
            ("low", Value::UInt(1)),
            ("high", Value::UInt(10)),
            ("wait_ms", Value::UInt(200)),
        ]),
        Perm::Config,
    )
    .await;
    assert_eq!(st, Some(Status::Ok));
    assert_eq!(v, Some(Value::Array(vec![])));
    // low without high is refused
    let (st, _, _) = act(
        &h,
        "c1",
        "who_is",
        map(&[("low", Value::UInt(1))]),
        Perm::Config,
    )
    .await;
    assert_eq!(st, Some(Status::InvalidParameter));
    // who_is is a config action
    let (st, _, _) = act(&h, "c1", "who_is", map(&[]), Perm::Read).await;
    assert_ne!(st, Some(Status::Ok));
    // a device that does not exist is not found: device failed, not the port
    let h2 = H::start(tree(
        addr,
        &[],
        &[("address", "".into()), ("instance", Value::UInt(77))],
        map(&[("temp", pt("analog_input", 1, &[]))]),
    ))
    .await;
    wait("not found", || {
        state(&h2, "c1/d1").as_deref() == Some("failed")
    })
    .await;
    assert_eq!(state(&h2, "c1").as_deref(), Some("connected"));
    h.stop().await;
    h2.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn list_objects_whole_and_index_by_index() {
    let (addr, dev, _task) = sim::spawn("127.0.0.1:0", DEV).await.unwrap();
    let h = H::start(tree(addr, &[], &[], map(&[]))).await;
    wait("connected", || {
        state(&h, "c1/d1").as_deref() == Some("connected")
    })
    .await;
    let (st, v, msg) = act(&h, "c1/d1", "list_objects", map(&[]), Perm::Read).await;
    assert_eq!(st, Some(Status::Ok), "{msg}");
    let v = v.unwrap();
    assert_eq!(field(&v, "count"), &Value::UInt(8));
    assert_eq!(field(&v, "truncated"), &Value::Bool(false));
    let Value::Array(objs) = field(&v, "objects") else {
        panic!()
    };
    let ai = objs
        .iter()
        .find(|o| field(o, "object_type") == &Value::from("analog_input"))
        .unwrap();
    assert_eq!(field(ai, "name"), &Value::from("Zone Temp"));
    assert_eq!(field(ai, "units"), &Value::from("degrees-celsius"));
    assert_eq!(field(ai, "unit"), &Value::from("°C"));
    h.stop().await;

    // a long list does not fit one reply at 480: index by index, batched
    {
        let mut s = dev.lock().unwrap();
        s.max_apdu = 480;
        s.add_analog_inputs(150);
    }
    let h = H::start(tree(addr, &[], &[], map(&[]))).await;
    wait("connected", || {
        state(&h, "c1/d1").as_deref() == Some("connected")
    })
    .await;
    let (st, v, msg) = act(
        &h,
        "c1/d1",
        "list_objects",
        map(&[("limit", Value::UInt(120))]),
        Perm::Read,
    )
    .await;
    assert_eq!(st, Some(Status::Ok), "{msg}");
    let v = v.unwrap();
    assert_eq!(field(&v, "count"), &Value::UInt(158));
    assert_eq!(field(&v, "truncated"), &Value::Bool(true));
    let Value::Array(objs) = field(&v, "objects") else {
        panic!()
    };
    assert_eq!(objs.len(), 120);
    assert!(objs
        .iter()
        .all(|o| matches!(field(o, "name"), Value::Str(_))));
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn read_property_action_and_error_texts() {
    let (addr, dev, _task) = sim::spawn("127.0.0.1:0", DEV).await.unwrap();
    let h = H::start(tree(addr, &[], &[], map(&[]))).await;
    wait("connected", || {
        state(&h, "c1/d1").as_deref() == Some("connected")
    })
    .await;
    let rp = |args: &[(&str, Value)]| map(args);
    let (st, v, msg) = act(
        &h,
        "c1/d1",
        "read_property",
        rp(&[
            ("object_type", "analog_input".into()),
            ("instance", Value::UInt(1)),
            ("property", "units".into()),
        ]),
        Perm::Read,
    )
    .await;
    assert_eq!(st, Some(Status::Ok), "{msg}");
    let v = v.unwrap();
    assert_eq!(field(&v, "value"), &Value::UInt(62));
    assert_eq!(field(&v, "unit"), &Value::from("°C"));
    // the priority array as it is
    let (_, v, _) = act(
        &h,
        "c1/d1",
        "read_property",
        rp(&[
            ("object_type", "analog_value".into()),
            ("instance", Value::UInt(1)),
            ("property", "priority_array".into()),
        ]),
        Perm::Read,
    )
    .await;
    let Value::Array(slots) = field(&v.unwrap(), "value").clone() else {
        panic!()
    };
    assert_eq!(slots.len(), 16);
    // Error PDU: the class and code text
    let (st, _, msg) = act(
        &h,
        "c1/d1",
        "read_property",
        rp(&[
            ("object_type", "analog_input".into()),
            ("instance", Value::UInt(42)),
        ]),
        Perm::Read,
    )
    .await;
    assert_ne!(st, Some(Status::Ok));
    assert!(msg.contains("object: unknown-object"), "{msg}");
    // Reject PDU: the reason text
    dev.lock().unwrap().reject_next = Some(4);
    let (st, _, msg) = act(
        &h,
        "c1/d1",
        "read_property",
        rp(&[
            ("object_type", "analog_input".into()),
            ("instance", Value::UInt(1)),
        ]),
        Perm::Read,
    )
    .await;
    assert_ne!(st, Some(Status::Ok));
    assert!(msg.contains("reject: invalid-tag"), "{msg}");
    // Abort: a reply too big for 50 octets
    dev.lock().unwrap().max_apdu = 50;
    let (st, _, msg) = act(
        &h,
        "c1/d1",
        "read_property",
        rp(&[
            ("object_type", "device".into()),
            ("instance", Value::UInt(DEV.into())),
            ("property", "object_list".into()),
        ]),
        Perm::Read,
    )
    .await;
    assert_ne!(st, Some(Status::Ok));
    assert!(msg.contains("abort: segmentation-not-supported"), "{msg}");
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn foreign_device_through_a_bbmd() {
    let (addr, dev, _task) = sim::spawn("127.0.0.1:0", DEV).await.unwrap();
    // the simulator is the BBMD too; Who-Is goes there as
    // Distribute-Broadcast-To-Network, the I-Am comes back forwarded
    let h = H::start(tree(
        addr,
        &[
            ("bbmd", Value::Str(addr.to_string())),
            ("broadcast", "127.0.0.1:9".into()),
        ],
        &[("address", "".into())],
        map(&[("temp", pt("analog_input", 1, &[]))]),
    ))
    .await;
    wait("value via the BBMD", || {
        val(&h, "temp") == Some(Value::Float(21.5))
    })
    .await;
    {
        let s = dev.lock().unwrap();
        assert_eq!(s.registrations, 1);
        assert!(s.foreign.is_some());
        assert!(s.who_is >= 1);
    }
    h.stop().await;
    // a BBMD that refuses: the connection fails with the reason
    let (addr, dev, _task) = sim::spawn("127.0.0.1:0", DEV).await.unwrap();
    dev.lock().unwrap().fd_nak = true;
    let h = H::start(tree(
        addr,
        &[("bbmd", Value::Str(addr.to_string()))],
        &[],
        map(&[]),
    ))
    .await;
    wait("refused", || {
        state(&h, "c1").as_deref() == Some("failed")
            && h.ctx()
                .last("c1/error")
                .is_some_and(|s| matches!(&s.v, Value::Str(e) if e.contains("refused")))
    })
    .await;
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn routed_device_behind_a_router() {
    let (addr, dev, _task) = sim::spawn("127.0.0.1:0", DEV).await.unwrap();
    dev.lock().unwrap().routed = Some(NetAddr {
        net: 5,
        mac: vec![0x07],
    });
    let h = H::start(tree(
        addr,
        &[],
        &[("network", Value::UInt(5)), ("mac", "07".into())],
        map(&[("temp", pt("analog_input", 1, &[]))]),
    ))
    .await;
    wait("value through the router", || {
        val(&h, "temp") == Some(Value::Float(21.5))
    })
    .await;
    // the same device without its network is not reached
    let h2 = H::start(tree(
        addr,
        &[],
        &[],
        map(&[("temp", pt("analog_input", 1, &[]))]),
    ))
    .await;
    wait("unreachable without DNET", || {
        state(&h2, "c1/d1").as_deref() == Some("failed")
    })
    .await;
    // Who-Is reports its network and MAC
    let (_, v, _) = act(
        &h,
        "c1",
        "who_is",
        map(&[("wait_ms", Value::UInt(300))]),
        Perm::Config,
    )
    .await;
    let Some(Value::Array(found)) = v else {
        panic!()
    };
    assert_eq!(field(&found[0], "network"), &Value::UInt(5));
    assert_eq!(field(&found[0], "mac"), &Value::from("07"));
    h.stop().await;
    h2.stop().await;
    let _ = ObjectId::new(0, 0);
}

#[tokio::test(flavor = "multi_thread")]
async fn params_bounds_forms_and_no_secrets() {
    let (addr, _dev, _task) = sim::spawn("127.0.0.1:0", DEV).await.unwrap();
    let h = H::start(tree(addr, &[], &[], map(&[]))).await;
    wait("connected", || {
        state(&h, "c1/d1").as_deref() == Some("connected")
    })
    .await;
    // device instance above 4194302
    let r = h
        .invoke(
            "c1",
            "add_device",
            map(&[("name", "d2".into()), ("instance", Value::UInt(4_194_303))]),
            Some(h.ptok(Perm::Config)),
        )
        .await;
    assert_eq!(status(&r[0].att), Some(Status::InvalidParameter));
    // priority 17, status-flags writable
    for bad in [
        vec![("priority", Value::UInt(17))],
        vec![("priority", Value::UInt(0))],
        vec![
            ("property", "status_flags".into()),
            ("writable", Value::Bool(true)),
        ],
        vec![("instance", Value::UInt(4_194_304))],
    ] {
        let mut kv = vec![
            ("name", Value::from("p")),
            ("object_type", "analog_value".into()),
            ("instance", Value::UInt(1)),
        ];
        kv.extend(bad.clone());
        let r = h
            .invoke("c1/d1", "add_point", map(&kv), Some(h.ptok(Perm::Config)))
            .await;
        assert_eq!(status(&r[0].att), Some(Status::InvalidParameter), "{bad:?}");
    }
    // a good one through the form
    let r = h
        .invoke(
            "c1/d1",
            "add_point",
            map(&[
                ("name", "sp".into()),
                ("object_type", "analog_value".into()),
                ("instance", Value::UInt(1)),
                ("poll_s", Value::Float(0.05)),
            ]),
            Some(h.ptok(Perm::Config)),
        )
        .await;
    assert_eq!(status(&r[0].att), Some(Status::Ok));
    wait("added point read", || {
        val(&h, "sp") == Some(Value::Float(20.0))
    })
    .await;
    // forms and actions: the commissioning actions and their levels
    let (_, c1) = h.meta("c1").await;
    let actions = c1.unwrap().actions.unwrap();
    assert!(actions.contains_key("who_is"));
    assert_eq!(actions["who_is"].level, Some(Perm::Config));
    let (_, d1) = h.meta("c1/d1").await;
    let d1 = d1.unwrap();
    let actions = d1.actions.as_ref().unwrap();
    assert_eq!(actions["list_objects"].level, Some(Perm::Read));
    assert_eq!(actions["relinquish"].level, Some(Perm::Config));
    assert_eq!(
        d1.cfg.as_ref().unwrap()["instance"],
        Value::UInt(DEV.into())
    );
    // BACnet/IP has no secrets: nothing in the schema is one
    let (_, root) = h.meta("").await;
    let add = &root.unwrap().actions.unwrap()["add_connection"];
    assert!(add
        .params
        .values()
        .all(|p| p.editor.as_deref() != Some("password")));
    assert!(add.params.contains_key("bbmd"));
    h.stop().await;
}

/// Security: a Forwarded-NPDU names its own origin; only the configured
/// BBMD is believed. Without a BBMD the forged I-Am (claiming another
/// address for the device) is dropped, and the device binds to the
/// address that answered.
#[tokio::test(flavor = "multi_thread")]
async fn a_forged_forwarded_i_am_is_dropped() {
    let (addr, dev, _task) = sim::spawn("127.0.0.1:0", DEV).await.unwrap();
    dev.lock().unwrap().spoof_i_am = Some("127.0.0.1:9".parse().unwrap());
    let h = H::start(tree(
        addr,
        &[],
        &[("address", "".into())],
        map(&[("temp", pt("analog_input", 1, &[]))]),
    ))
    .await;
    wait("bound to the simulator", || {
        val(&h, "temp") == Some(Value::Float(21.5))
    })
    .await;
    let (st, v, _) = act(
        &h,
        "c1",
        "who_is",
        map(&[("wait_ms", Value::UInt(300))]),
        Perm::Config,
    )
    .await;
    assert_eq!(st, Some(Status::Ok));
    let Some(Value::Array(found)) = v else {
        panic!()
    };
    assert_eq!(found.len(), 1, "{found:?}");
    assert_eq!(field(&found[0], "address"), &Value::Str(addr.to_string()));
    h.stop().await;
}

/// Security: two addresses answering Who-Is for one device (here the
/// BBMD forwards a second answer) is not a binding: the device fails and
/// asks for its address.
#[tokio::test(flavor = "multi_thread")]
async fn two_answers_for_one_device_are_refused() {
    let (addr, dev, _task) = sim::spawn("127.0.0.1:0", DEV).await.unwrap();
    dev.lock().unwrap().spoof_i_am = Some("127.0.0.1:9".parse().unwrap());
    let h = H::start(tree(
        addr,
        &[("bbmd", Value::Str(addr.to_string()))],
        &[("address", "".into())],
        map(&[("temp", pt("analog_input", 1, &[]))]),
    ))
    .await;
    wait("refused", || {
        state(&h, "c1/d1").as_deref() == Some("failed")
            && h.ctx()
                .last("c1/d1/error")
                .is_some_and(|s| matches!(&s.v, Value::Str(e) if e.contains("set its address")))
    })
    .await;
    assert_eq!(val(&h, "temp"), None, "nothing read from either");
    h.stop().await;
}

/// Security: a new binding must answer a read of its own device
/// identifier; one that does not is not used.
#[tokio::test(flavor = "multi_thread")]
async fn a_binding_is_confirmed_before_use() {
    let (addr, dev, _task) = sim::spawn("127.0.0.1:0", DEV).await.unwrap();
    dev.lock().unwrap().bad_identity = true;
    let h = H::start(tree(
        addr,
        &[],
        &[("address", "".into())],
        map(&[("temp", pt("analog_input", 1, &[]))]),
    ))
    .await;
    wait("not confirmed", || {
        state(&h, "c1/d1").as_deref() == Some("failed")
            && h.ctx()
                .last("c1/d1/error")
                .is_some_and(|s| matches!(&s.v, Value::Str(e) if e.contains("does not confirm")))
    })
    .await;
    assert_eq!(
        dev.lock().unwrap().count(service::READ_PROPERTY_MULTIPLE),
        0,
        "no point read before the binding is confirmed"
    );
    h.stop().await;
}

/// Security: an unsolicited I-Am (no Who-Is pending) does not move a
/// device's binding: writes keep going to the device.
#[tokio::test(flavor = "multi_thread")]
async fn an_unsolicited_i_am_does_not_move_a_binding() {
    use wyrm_link_bacnet::codec::{self, IAm};
    let (addr, dev, _task) = sim::spawn("127.0.0.1:0", DEV).await.unwrap();
    let port = {
        let s = std::net::UdpSocket::bind("127.0.0.1:0").unwrap();
        s.local_addr().unwrap().port()
    };
    let h = H::start(tree(
        addr,
        &[("bind_port", Value::UInt(port.into()))],
        &[("address", "".into())],
        map(&[(
            "sp",
            pt("analog_value", 1, &[("writable", Value::Bool(true))]),
        )]),
    ))
    .await;
    wait("bound", || val(&h, "sp") == Some(Value::Float(20.0))).await;
    // an impersonator announces the device from its own address
    let evil = tokio::net::UdpSocket::bind("127.0.0.1:0").await.unwrap();
    let mut n = Vec::new();
    codec::npdu_header(&mut n, None, false);
    n.extend(codec::i_am(&IAm {
        device: ObjectId::new(ObjectId::DEVICE, DEV),
        max_apdu: 1476,
        segmentation: 3,
        vendor_id: 1,
    }));
    let frame = codec::bvlc_wrap(codec::bvlc::ORIGINAL_UNICAST, &n);
    for _ in 0..5 {
        evil.send_to(&frame, ("127.0.0.1", port)).await.unwrap();
        tokio::time::sleep(Duration::from_millis(30)).await;
    }
    assert_eq!(
        status(&h.set("c1/d1/sp", 25.0, Some(h.ptok(Perm::Write))).await),
        Some(Status::Ok)
    );
    assert_eq!(
        dev.lock().unwrap().priorities(objects::AV1).unwrap()[15],
        Some(AppValue::Real(25.0)),
        "the write reached the device"
    );
    let mut buf = [0u8; 1500];
    let got = tokio::time::timeout(Duration::from_millis(300), evil.recv_from(&mut buf)).await;
    assert!(got.is_err(), "the impersonator got a request");
    h.stop().await;
}
