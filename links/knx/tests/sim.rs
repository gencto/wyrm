//! The `knx` driver against its simulator over real UDP on loopback,
//! through the wire format (`TestHarness`: in-memory Zenoh session).

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::unreachable,
    clippy::print_stdout,
    reason = "test code: a failed step fails the test"
)]

use std::net::Ipv4Addr;
use std::time::Duration;
use wyrm_core::meta::TextOrCode;
use wyrm_core::{Perm, Quality, Status, TypeCode, Value};
use wyrm_link_knx::addr::GroupAddr;
use wyrm_link_knx::cemi::Data;
use wyrm_link_knx::proto::ErrorCode;
use wyrm_link_knx::sim::{self, Gateway};
use wyrm_link_knx::Knx;
use wyrm_link_sdk::driver::Tree;
use wyrm_link_sdk::TestHarness;

type H = TestHarness<Knx>;

fn map(kv: &[(&str, Value)]) -> Value {
    Value::Map(
        kv.iter()
            .map(|(k, v)| ((*k).to_owned(), v.clone()))
            .collect(),
    )
}

fn ga(text: &str) -> GroupAddr {
    GroupAddr::parse(text).unwrap()
}

/// A point on `address` of type `dpt`.
fn pt(address: &str, dpt: &str, extra: &[(&str, Value)]) -> Value {
    let mut kv = vec![("address", Value::from(address)), ("dpt", Value::from(dpt))];
    kv.extend_from_slice(extra);
    map(&kv)
}

const READ_ON_START: (&str, Value) = ("read_on_start", Value::Bool(true));
const WRITABLE: (&str, Value) = ("writable", Value::Bool(true));

/// `c1/d1` as connection `conn` (its `kind` included) with `points`.
fn tree_of(conn: &[(&str, Value)], points: Value) -> Tree {
    let mut c = conn.to_vec();
    c.push(("devices", map(&[("d1", map(&[("points", points)]))])));
    Tree(map(&[("connections", map(&[("c1", map(&c))]))]))
}

/// `c1/d1` as a tunnel to `gw`: 300 ms timeout, a heartbeat every second,
/// 100 telegrams per second; `conn` over those.
fn tree(gw: &Gateway, conn: &[(&str, Value)], points: Value) -> Tree {
    let mut c: Vec<(&str, Value)> = vec![
        ("kind", "tunnel_connection".into()),
        ("host", Value::Str(gw.addr().ip().to_string())),
        ("port", Value::UInt(gw.addr().port().into())),
        ("timeout_ms", Value::UInt(300)),
        ("heartbeat_s", Value::UInt(1)),
        ("rate_per_s", Value::UInt(100)),
    ];
    for (k, v) in conn {
        c.retain(|(n, _)| n != k);
        c.push((k, v.clone()));
    }
    tree_of(&c, points)
}

/// The `status` enum leaf as a state name.
fn state(h: &H, base: &str) -> Option<String> {
    match h.ctx().last(&format!("{base}/status"))?.v {
        Value::UInt(i) => wyrm_link_sdk::driver::NodeState::NAMES
            .get(usize::try_from(i).unwrap())
            .map(|s| (*s).to_owned()),
        _ => None,
    }
}

async fn wait(what: &str, mut f: impl FnMut() -> bool) {
    // Generous: the workspace suite runs many sessions in parallel.
    let deadline = tokio::time::Instant::now() + Duration::from_secs(15);
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

fn rows(v: Option<Value>) -> Vec<Value> {
    match v {
        Some(Value::Array(a)) => a,
        other => panic!("not a list: {other:?}"),
    }
}

async fn connected(h: &H) {
    wait("connected", || {
        state(h, "c1").as_deref() == Some("connected")
    })
    .await;
}

#[tokio::test(flavor = "multi_thread")]
async fn values_arrive_as_telegrams() {
    let gw = sim::spawn("127.0.0.1:0").await.unwrap();
    let mut text = b"Hall 2".to_vec();
    text.resize(14, 0);
    let points = map(&[
        ("temp", pt("1/0/1", "9.001", &[])),
        ("light", pt("1/1/1", "DPST-1-1", &[])),
        ("blind", pt("1/1/2", "5.001", &[])),
        ("mode", pt("1/2/1", "20.102", &[])),
        ("energy", pt("2/0/1", "13.013", &[])),
        ("name", pt("2/0/2", "16.001", &[])),
        ("raw", pt("2/0/3", "240.800", &[])),
        ("flow", pt("2563", "14", &[("unit", "l/s".into())])),
    ]);
    let dev = map(&[
        ("individual_address", "1.1.5".into()),
        ("points", points),
        (
            "folders",
            map(&[(
                "floor1",
                map(&[("points", map(&[("lamp", pt("3/1/7", "1.001", &[]))]))]),
            )]),
        ),
    ]);
    let h = H::start(Tree(map(&[(
        "connections",
        map(&[(
            "c1",
            map(&[
                ("kind", "tunnel_connection".into()),
                ("host", Value::Str(gw.addr().ip().to_string())),
                ("port", Value::UInt(gw.addr().port().into())),
                ("timeout_ms", Value::UInt(300)),
                ("devices", map(&[("d1", dev)])),
            ]),
        )]),
    )])))
    .await;
    connected(&h).await;
    wait("device connected", || {
        state(&h, "c1/d1").as_deref() == Some("connected")
    })
    .await;
    assert_eq!(val(&h, "temp"), None, "no value before a telegram");
    gw.inject(ga("1/0/1"), Data::long(vec![0x0C, 0x33]));
    gw.inject(ga("1/1/1"), Data::short(1));
    gw.inject(ga("1/1/2"), Data::long(vec![0x80]));
    gw.inject(ga("1/2/1"), Data::long(vec![3]));
    gw.inject(ga("2/0/1"), Data::long(vec![0, 0, 0x30, 0x39]));
    gw.inject(ga("2/0/2"), Data::long(text));
    gw.inject(ga("2/0/3"), Data::long(vec![1, 2, 3]));
    gw.inject(ga("1/2/3"), Data::long(vec![0x3F, 0xC0, 0, 0]));
    gw.inject(ga("3/1/7"), Data::short(1));
    wait("all values", || {
        [
            "temp",
            "light",
            "blind",
            "mode",
            "energy",
            "name",
            "raw",
            "flow",
            "floor1/lamp",
        ]
        .iter()
        .all(|p| qual(&h, p) == Some(Quality::Good))
    })
    .await;
    assert_eq!(val(&h, "temp"), Some(Value::Float(21.5)));
    assert_eq!(val(&h, "light"), Some(Value::Bool(true)));
    let Some(Value::Float(blind)) = val(&h, "blind") else {
        panic!("blind")
    };
    assert!((blind - 50.196).abs() < 0.001, "{blind}");
    assert_eq!(val(&h, "mode"), Some(Value::UInt(3)));
    assert_eq!(val(&h, "energy"), Some(Value::UInt(12345)));
    assert_eq!(val(&h, "name"), Some(Value::from("Hall 2")));
    assert_eq!(val(&h, "raw"), Some(Value::Bytes(vec![1, 2, 3])));
    assert_eq!(val(&h, "flow"), Some(Value::Float(1.5)));
    assert_eq!(val(&h, "floor1/lamp"), Some(Value::Bool(true)));
    // a new telegram is a new value
    gw.inject(ga("1/0/1"), Data::long(vec![0x8A, 0x24]));
    wait("temp changed", || {
        val(&h, "temp") == Some(Value::Float(-30.0))
    })
    .await;
    // meta: type, unit and enum names come from the datapoint type
    let meta = |p: &'static str| {
        let h = &h;
        async move { h.meta(&format!("c1/d1/{p}")).await.1.unwrap() }
    };
    let m = meta("temp").await;
    assert_eq!(m.ty, Some(TypeCode::Number));
    assert_eq!(m.unit, Some(TextOrCode::Text("°C".into())));
    assert_eq!(meta("light").await.ty, Some(TypeCode::Bool));
    assert_eq!(meta("blind").await.unit, Some(TextOrCode::Text("%".into())));
    let m = meta("mode").await;
    assert_eq!(m.ty, Some(TypeCode::Enum));
    assert_eq!(m.enum_values.unwrap()[3], "Economy");
    assert_eq!(
        meta("energy").await.unit,
        Some(TextOrCode::Text("kWh".into()))
    );
    assert_eq!(meta("name").await.ty, Some(TypeCode::String));
    assert_eq!(meta("raw").await.ty, Some(TypeCode::Binary));
    assert_eq!(
        meta("flow").await.unit,
        Some(TextOrCode::Text("l/s".into()))
    );
    // the link only listened
    assert!(gw.table().reads.is_empty(), "{:?}", gw.table().reads);
    assert!(gw.table().writes.is_empty());
    // a telegram that does not fit the type is a point error; the others stay
    gw.inject(ga("1/0/1"), Data::long(vec![1, 2, 3]));
    wait("temp bad", || qual(&h, "temp") == Some(Quality::Bad)).await;
    assert_eq!(val(&h, "temp"), Some(Value::Float(-30.0)), "value kept");
    assert_eq!(qual(&h, "light"), Some(Quality::Good));
    gw.inject(ga("1/0/1"), Data::long(vec![0x0C, 0x1A]));
    wait("temp good again", || {
        val(&h, "temp") == Some(Value::Float(21.0)) && qual(&h, "temp") == Some(Quality::Good)
    })
    .await;
    h.stop().await;
    // the tunnel is given back to the interface
    wait("disconnected", || gw.table().disconnects == 1).await;
    assert_eq!(gw.table().tunnels, 0);
}

#[tokio::test(flavor = "multi_thread")]
async fn reads_on_start_and_cyclic() {
    let gw = sim::spawn("127.0.0.1:0").await.unwrap();
    gw.set(ga("1/0/1"), Data::long(vec![0x0C, 0x33]));
    gw.set(ga("1/1/1"), Data::short(1));
    gw.set(ga("1/1/2"), Data::long(vec![0xFF]));
    let points = map(&[
        ("temp", pt("1/0/1", "9.001", &[READ_ON_START])),
        (
            "light",
            pt("1/1/1", "1.001", &[("poll_s", Value::Float(1.0))]),
        ),
        ("blind", pt("1/1/2", "5.001", &[])),
        // the same address twice: one start read serves both
        ("temp2", pt("1/0/1", "9", &[READ_ON_START])),
    ]);
    let h = H::start(tree(&gw, &[], points)).await;
    wait("values", || {
        ["temp", "temp2", "light"]
            .iter()
            .all(|p| qual(&h, p) == Some(Quality::Good))
    })
    .await;
    assert_eq!(val(&h, "temp"), Some(Value::Float(21.5)));
    assert_eq!(val(&h, "temp2"), Some(Value::Float(21.5)));
    assert_eq!(val(&h, "light"), Some(Value::Bool(true)));
    // a point that asks for no read has no value until a telegram comes
    assert_eq!(val(&h, "blind"), None);
    wait("cyclic reads", || {
        gw.table()
            .reads
            .iter()
            .filter(|a| **a == ga("1/1/1"))
            .count()
            >= 3
    })
    .await;
    let reads = gw.table().reads.clone();
    assert_eq!(
        reads.iter().filter(|a| **a == ga("1/0/1")).count(),
        1,
        "one start read per address: {reads:?}"
    );
    assert!(!reads.contains(&ga("1/1/2")), "{reads:?}");
    // an edit of the group (a new plan) does not read the start again
    let (st, _, msg) = act(
        &h,
        "c1/d1/blind",
        "edit",
        map(&[("address", "1/1/2".into()), ("dpt", "5.010".into())]),
        Perm::Config,
    )
    .await;
    assert_eq!(st, Some(Status::Ok), "{msg}");
    tokio::time::sleep(Duration::from_millis(600)).await;
    let reads = gw.table().reads.clone();
    assert_eq!(reads.iter().filter(|a| **a == ga("1/0/1")).count(), 1);
    assert!(gw.table().heartbeats >= 1, "connection state requests");
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn start_reads_are_spread_by_the_rate_limit() {
    let gw = sim::spawn("127.0.0.1:0").await.unwrap();
    let mut kv = Vec::new();
    let names: Vec<String> = (1..=6).map(|i| format!("p{i}")).collect();
    for (i, name) in names.iter().enumerate() {
        let address = format!("4/0/{}", i + 1);
        gw.set(ga(&address), Data::short(1));
        kv.push((name.as_str(), pt(&address, "1.001", &[READ_ON_START])));
    }
    let h = H::start(tree(&gw, &[("rate_per_s", Value::UInt(4))], map(&kv))).await;
    wait("first read", || !gw.table().reads.is_empty()).await;
    let begin = tokio::time::Instant::now();
    assert!(gw.table().reads.len() < 6, "not all at once");
    wait("all read", || gw.table().reads.len() == 6).await;
    // 5 more telegrams at 4 per second
    assert!(
        begin.elapsed() >= Duration::from_millis(900),
        "{:?}",
        begin.elapsed()
    );
    wait("values", || {
        names.iter().all(|p| val(&h, p) == Some(Value::Bool(true)))
    })
    .await;
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn a_write_is_shown_once_the_bus_confirms_it() {
    let gw = sim::spawn("127.0.0.1:0").await.unwrap();
    let points = map(&[
        ("light", pt("1/1/1", "1.001", &[WRITABLE])),
        ("sp", pt("1/0/2", "9.001", &[WRITABLE])),
        ("mode", pt("1/2/1", "20.102", &[WRITABLE])),
        ("temp", pt("1/0/1", "9.001", &[])),
    ]);
    let h = H::start(tree(&gw, &[], points)).await;
    connected(&h).await;
    let tok = || Some(h.ptok(Perm::Write));
    assert_eq!(
        status(&h.set("c1/d1/light", true, tok()).await),
        Some(Status::Ok)
    );
    assert_eq!(val(&h, "light"), Some(Value::Bool(true)), "read back");
    assert_eq!(
        status(&h.set("c1/d1/sp", 21.5, tok()).await),
        Some(Status::Ok)
    );
    assert_eq!(val(&h, "sp"), Some(Value::Float(21.5)));
    assert_eq!(
        status(&h.set("c1/d1/mode", 1u64, tok()).await),
        Some(Status::Ok)
    );
    assert_eq!(
        gw.table().writes,
        vec![
            (ga("1/1/1"), Data::short(1)),
            (ga("1/0/2"), Data::long(vec![0x0C, 0x33])),
            (ga("1/2/1"), Data::long(vec![1])),
        ]
    );
    // refused before anything is sent
    assert_eq!(
        status(&h.set("c1/d1/temp", 1.0, tok()).await),
        Some(Status::NotSupported),
        "read-only"
    );
    assert_eq!(
        status(&h.set("c1/d1/sp", 1e9, tok()).await),
        Some(Status::InvalidParameter),
        "out of the type's range"
    );
    assert_eq!(gw.table().writes.len(), 3);
    // nothing on the bus acknowledged the telegram: the value stays
    gw.table().faults.not_acknowledged = true;
    let a = h.set("c1/d1/light", false, tok()).await;
    assert_eq!(status(&a), Some(Status::InvalidParameter), "{:?}", a.err);
    assert!(a.err.unwrap_or_default().contains("acknowledge"));
    assert_eq!(val(&h, "light"), Some(Value::Bool(true)));
    gw.table().faults.not_acknowledged = false;
    // no confirmation at all: a timeout, and the value stays
    gw.table().faults.no_confirm = true;
    let a = h.set("c1/d1/light", false, tok()).await;
    assert_eq!(status(&a), Some(Status::Timeout), "{:?}", a.err);
    assert_eq!(val(&h, "light"), Some(Value::Bool(true)));
    gw.table().faults.no_confirm = false;
    assert_eq!(
        status(&h.set("c1/d1/light", false, tok()).await),
        Some(Status::Ok)
    );
    assert_eq!(val(&h, "light"), Some(Value::Bool(false)));
    assert_eq!(state(&h, "c1").as_deref(), Some("connected"));
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn an_unanswered_read_goes_stale_then_bad() {
    let gw = sim::spawn("127.0.0.1:0").await.unwrap();
    gw.set(ga("1/0/1"), Data::long(vec![0x0C, 0x33]));
    let points = map(&[
        (
            "temp",
            pt("1/0/1", "9.001", &[("poll_s", Value::Float(1.0))]),
        ),
        ("light", pt("1/1/1", "1.001", &[])),
        // nothing answers this address
        ("ghost", pt("5/0/1", "1.001", &[READ_ON_START])),
    ]);
    let h = H::start(tree(&gw, &[], points)).await;
    wait("temp", || qual(&h, "temp") == Some(Quality::Good)).await;
    gw.inject(ga("1/1/1"), Data::short(1));
    wait("light", || qual(&h, "light") == Some(Quality::Good)).await;
    gw.table().faults.mute.insert(ga("1/0/1").0);
    let mut seen_uncertain = false;
    wait("uncertain/stale then bad/comm_fail", || {
        let q = qual(&h, "temp");
        seen_uncertain |= q == Some(Quality::Uncertain);
        q == Some(Quality::Bad)
    })
    .await;
    assert!(seen_uncertain, "stale before bad");
    assert_eq!(val(&h, "temp"), Some(Value::Float(21.5)), "value kept");
    // the other point and the device are not touched
    assert_eq!(qual(&h, "light"), Some(Quality::Good));
    assert_eq!(state(&h, "c1/d1").as_deref(), Some("connected"));
    assert_eq!(state(&h, "c1").as_deref(), Some("connected"));
    // a start read is asked three times, then left
    wait("ghost asked three times", || {
        gw.table()
            .reads
            .iter()
            .filter(|a| **a == ga("5/0/1"))
            .count()
            == 3
    })
    .await;
    tokio::time::sleep(Duration::from_millis(900)).await;
    assert_eq!(
        gw.table()
            .reads
            .iter()
            .filter(|a| **a == ga("5/0/1"))
            .count(),
        3
    );
    // the next telegram of the address makes the point good again
    gw.table().faults.mute.clear();
    wait("good again", || qual(&h, "temp") == Some(Quality::Good)).await;
    gw.inject(ga("5/0/1"), Data::short(1));
    wait("ghost", || {
        val(&h, "ghost") == Some(Value::Bool(true)) && qual(&h, "ghost") == Some(Quality::Good)
    })
    .await;
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn a_device_whose_reads_all_fail_is_failed() {
    let gw = sim::spawn("127.0.0.1:0").await.unwrap();
    let points = map(&[("ghost", pt("5/0/1", "1.001", &[READ_ON_START]))]);
    let h = H::start(tree(&gw, &[], points)).await;
    wait("device failed", || {
        state(&h, "c1/d1").as_deref() == Some("failed")
    })
    .await;
    let err = h.ctx().last("c1/d1/error").map(|s| s.v);
    assert_eq!(err, Some(Value::from("no answer to GroupValue_Read 5/0/1")),);
    assert_eq!(state(&h, "c1").as_deref(), Some("connected"));
    gw.inject(ga("5/0/1"), Data::short(0));
    wait("device connected", || {
        state(&h, "c1/d1").as_deref() == Some("connected")
            && qual(&h, "ghost") == Some(Quality::Good)
    })
    .await;
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn a_closed_tunnel_is_opened_again() {
    let gw = sim::spawn("127.0.0.1:0").await.unwrap();
    gw.set(ga("1/0/1"), Data::long(vec![0x0C, 0x33]));
    let points = map(&[
        ("temp", pt("1/0/1", "9.001", &[READ_ON_START])),
        ("light", pt("1/1/1", "1.001", &[])),
    ]);
    let h = H::start(tree(&gw, &[], points)).await;
    wait("temp", || qual(&h, "temp") == Some(Quality::Good)).await;
    gw.inject(ga("1/1/1"), Data::short(1));
    wait("light", || qual(&h, "light") == Some(Quality::Good)).await;
    gw.set(ga("1/0/1"), Data::long(vec![0x0C, 0x1A]));
    gw.close_tunnels();
    wait("children stopped by parent", || {
        state(&h, "c1/d1").as_deref() == Some("stopped_by_parent")
            && qual(&h, "light") == Some(Quality::Bad)
    })
    .await;
    let err = h.ctx().last("c1/error").map(|s| s.v);
    assert_eq!(err, Some(Value::from("the interface closed the tunnel")));
    wait("connected again", || {
        gw.table().connects == 2 && state(&h, "c1").as_deref() == Some("connected")
    })
    .await;
    // the start read is sent again on the new connection
    wait("temp read again", || {
        val(&h, "temp") == Some(Value::Float(21.0)) && qual(&h, "temp") == Some(Quality::Good)
    })
    .await;
    // a point that only listens knows nothing until its next telegram
    assert_eq!(qual(&h, "light"), Some(Quality::Bad));
    gw.inject(ga("1/1/1"), Data::short(0));
    wait("light again", || {
        val(&h, "light") == Some(Value::Bool(false)) && qual(&h, "light") == Some(Quality::Good)
    })
    .await;
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn a_silent_interface_ends_the_tunnel() {
    let gw = sim::spawn("127.0.0.1:0").await.unwrap();
    let points = map(&[("light", pt("1/1/1", "1.001", &[WRITABLE]))]);
    let h = H::start(tree(&gw, &[], points)).await;
    connected(&h).await;
    // no answer to three connection state requests
    gw.table().faults.silent = true;
    wait("failed", || {
        matches!(
            state(&h, "c1").as_deref(),
            Some("failed") | Some("connecting")
        ) && h.ctx().last("c1/error").is_some()
    })
    .await;
    gw.table().faults.silent = false;
    connected(&h).await;
    // no acknowledge of a tunnelling request: one repeat, then the tunnel ends
    gw.table().faults.no_ack = true;
    let a = h.set("c1/d1/light", true, Some(h.ptok(Perm::Write))).await;
    assert!(
        matches!(status(&a), Some(Status::Disconnected | Status::Timeout)),
        "{:?} {:?}",
        a.status,
        a.err
    );
    gw.table().faults.no_ack = false;
    wait("writes again", || {
        gw.table().connects >= 3 && state(&h, "c1").as_deref() == Some("connected")
    })
    .await;
    // a set may meet the reconnect: try until one goes through
    let mut ok = false;
    for _ in 0..50 {
        let a = h.set("c1/d1/light", true, Some(h.ptok(Perm::Write))).await;
        if status(&a) == Some(Status::Ok) {
            ok = true;
            break;
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
    assert!(ok, "a write goes through on the new tunnel");
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn a_refused_tunnel_shows_why() {
    let gw = sim::spawn("127.0.0.1:0").await.unwrap();
    gw.table().faults.refuse = Some(ErrorCode::NoMoreConnections);
    let h = H::start(tree(
        &gw,
        &[("nat", Value::Bool(true))],
        map(&[("light", pt("1/1/1", "1.001", &[]))]),
    ))
    .await;
    wait("error shown", || {
        h.ctx().last("c1/error").map(|s| s.v)
            == Some(Value::from(
                "transport: the interface refused the tunnel: all tunnels of the interface are in use",
            ))
    })
    .await;
    assert_eq!(gw.table().connects, 0);
    gw.table().faults.refuse = None;
    // NAT mode: the interface answers to where the datagrams come from
    connected(&h).await;
    gw.inject(ga("1/1/1"), Data::short(1));
    wait("light", || val(&h, "light") == Some(Value::Bool(true))).await;
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn invalid_points_are_kept_as_failed() {
    let gw = sim::spawn("127.0.0.1:0").await.unwrap();
    let points = map(&[
        ("ok", pt("1/1/1", "1.001", &[])),
        ("zero", pt("0/0/0", "1.001", &[])),
        ("deep", pt("1/2/3/4", "1.001", &[])),
        ("type", pt("1/1/2", "temperature", &[])),
        (
            "fast",
            pt("1/1/3", "1.001", &[("poll_s", Value::Float(0.1))]),
        ),
    ]);
    let h = H::start(tree(&gw, &[], points)).await;
    connected(&h).await;
    gw.inject(ga("1/1/1"), Data::short(1));
    wait("ok", || val(&h, "ok") == Some(Value::Bool(true))).await;
    for (p, why) in [
        ("zero", "broadcast"),
        ("deep", "one, two or three parts"),
        ("type", "not a datapoint type"),
        ("fast", "at least 1 second"),
    ] {
        let s = h.ctx().last(&format!("c1/d1/{p}")).unwrap();
        assert_eq!(s.q, Quality::Bad, "{p}");
        let Value::Str(text) = s.v else {
            panic!("{p}: {:?}", s.v)
        };
        assert!(text.contains(why), "{p}: {text}");
    }
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn connection_actions() {
    let gw = sim::spawn("127.0.0.1:0").await.unwrap();
    let points = map(&[("light", pt("1/1/1", "1.001", &[WRITABLE]))]);
    let h = H::start(tree(&gw, &[], points)).await;
    connected(&h).await;
    // the tunnel's own interface answers a search
    let (st, v, msg) = act(
        &h,
        "c1",
        "search_gateways",
        map(&[("wait_ms", Value::UInt(300))]),
        Perm::Config,
    )
    .await;
    assert_eq!(st, Some(Status::Ok), "{msg}");
    let found = rows(v);
    assert_eq!(found.len(), 1, "{found:?}");
    assert_eq!(field(&found[0], "name"), &Value::from("WYRM KNX simulator"));
    assert_eq!(
        field(&found[0], "address"),
        &Value::Str(gw.addr().to_string())
    );
    assert_eq!(field(&found[0], "medium"), &Value::from("TP1"));
    assert_eq!(
        field(&found[0], "individual_address"),
        &Value::from("1.1.0")
    );
    assert_eq!(field(&found[0], "serial"), &Value::from("00FA5759524D"));
    assert_eq!(field(&found[0], "mac"), &Value::from("02:00:57:59:52:4d"));
    // one host by its address; nobody there: an empty list, not an error
    let (st, v, msg) = act(
        &h,
        "c1",
        "search_gateways",
        map(&[
            ("address", Value::Str(gw.addr().to_string())),
            ("wait_ms", Value::UInt(200)),
        ]),
        Perm::Config,
    )
    .await;
    assert_eq!(st, Some(Status::Ok), "{msg}");
    assert_eq!(rows(v).len(), 1);
    let (st, _, _) = act(
        &h,
        "c1",
        "search_gateways",
        map(&[("address", "not an address".into())]),
        Perm::Config,
    )
    .await;
    assert_eq!(st, Some(Status::InvalidParameter));
    let (st, _, _) = act(&h, "c1", "search_gateways", map(&[]), Perm::Write).await;
    assert_eq!(st, Some(Status::PermissionDenied), "a search needs config");

    // the telegram ring: what was seen and what was sent
    gw.inject(ga("1/0/1"), Data::long(vec![0x0C, 0x33]));
    assert_eq!(
        status(&h.set("c1/d1/light", true, Some(h.ptok(Perm::Write))).await),
        Some(Status::Ok)
    );
    let (st, v, msg) = act(&h, "c1", "recent_telegrams", map(&[]), Perm::Read).await;
    assert_eq!(st, Some(Status::Ok), "{msg}");
    let seen = rows(v);
    assert_eq!(seen.len(), 2, "{seen:?}");
    assert_eq!(field(&seen[0], "sent"), &Value::Bool(false));
    assert_eq!(field(&seen[0], "source"), &Value::from("1.1.10"));
    assert_eq!(field(&seen[0], "destination"), &Value::from("1/0/1"));
    assert_eq!(field(&seen[0], "service"), &Value::from("GroupValue_Write"));
    assert_eq!(field(&seen[0], "data"), &Value::Bytes(vec![0x0C, 0x33]));
    assert!(matches!(field(&seen[0], "time"), Value::UInt(t) if *t > 0));
    assert_eq!(field(&seen[1], "sent"), &Value::Bool(true));
    assert_eq!(field(&seen[1], "destination"), &Value::from("1/1/1"));
    assert_eq!(field(&seen[1], "data"), &Value::Bytes(vec![1]));
    assert_eq!(field(&seen[1], "acknowledged"), &Value::Bool(true));
    let (_, v, _) = act(
        &h,
        "c1",
        "recent_telegrams",
        map(&[("max", Value::UInt(1))]),
        Perm::Read,
    )
    .await;
    let last = rows(v);
    assert_eq!(last.len(), 1);
    assert_eq!(field(&last[0], "destination"), &Value::from("1/1/1"));
    let (st, _, _) = act(
        &h,
        "c1",
        "recent_telegrams",
        map(&[("max", Value::UInt(0))]),
        Perm::Read,
    )
    .await;
    assert_eq!(st, Some(Status::InvalidParameter));

    let (st, v, msg) = act(&h, "c1", "connection_info", map(&[]), Perm::Read).await;
    assert_eq!(st, Some(Status::Ok), "{msg}");
    let info = v.unwrap();
    assert_eq!(field(&info, "peer"), &Value::Str(gw.addr().to_string()));
    assert!(matches!(field(&info, "individual_address"), Value::Str(a) if a.starts_with("1.1.24")));
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn device_actions() {
    let gw = sim::spawn("127.0.0.1:0").await.unwrap();
    gw.set(ga("1/0/1"), Data::long(vec![0x0C, 0x33]));
    let h = H::start(tree(&gw, &[], map(&[("light", pt("1/1/1", "1.001", &[]))]))).await;
    connected(&h).await;
    wait("device", || {
        state(&h, "c1/d1").as_deref() == Some("connected")
    })
    .await;
    let read = |address: &'static str, dpt: &'static str| {
        map(&[("address", address.into()), ("dpt", dpt.into())])
    };
    let (st, v, msg) = act(
        &h,
        "c1/d1",
        "read_group",
        read("1/0/1", "9.001"),
        Perm::Read,
    )
    .await;
    assert_eq!(st, Some(Status::Ok), "{msg}");
    let v = v.unwrap();
    assert_eq!(field(&v, "value"), &Value::Float(21.5));
    assert_eq!(field(&v, "dpt"), &Value::from("9.001"));
    assert_eq!(field(&v, "unit"), &Value::from("°C"));
    assert_eq!(field(&v, "data"), &Value::Bytes(vec![0x0C, 0x33]));
    // nothing answers: a timeout
    let (st, _, msg) = act(
        &h,
        "c1/d1",
        "read_group",
        read("7/0/1", "1.001"),
        Perm::Read,
    )
    .await;
    assert_eq!(st, Some(Status::Timeout), "{msg}");
    assert!(msg.contains("7/0/1"), "{msg}");
    // the answer does not fit the type asked for
    let (st, _, msg) = act(
        &h,
        "c1/d1",
        "read_group",
        read("1/0/1", "14.056"),
        Perm::Read,
    )
    .await;
    assert_eq!(st, Some(Status::InvalidMessage), "{msg}");
    let (st, _, msg) = act(
        &h,
        "c1/d1",
        "read_group",
        read("1/2/3/4", "1.001"),
        Perm::Read,
    )
    .await;
    assert_eq!(st, Some(Status::InvalidParameter), "{msg}");
    assert!(msg.starts_with("address:"), "{msg}");
    let (st, _, msg) = act(&h, "c1/d1", "read_group", read("1/0/1", "x"), Perm::Read).await;
    assert_eq!(st, Some(Status::InvalidParameter), "{msg}");
    assert!(msg.starts_with("dpt:"), "{msg}");

    let write = |address: &'static str, dpt: &'static str, value: Value| {
        map(&[
            ("address", address.into()),
            ("dpt", dpt.into()),
            ("value", value),
        ])
    };
    let (st, v, msg) = act(
        &h,
        "c1/d1",
        "write_group",
        write("1/1/1", "1.001", Value::Bool(true)),
        Perm::Write,
    )
    .await;
    assert_eq!(st, Some(Status::Ok), "{msg}");
    assert_eq!(field(&v.unwrap(), "data"), &Value::Bytes(vec![1]));
    assert_eq!(gw.table().writes, vec![(ga("1/1/1"), Data::short(1))]);
    // the point on that address shows what was written
    wait("light", || val(&h, "light") == Some(Value::Bool(true))).await;
    let (st, _, msg) = act(
        &h,
        "c1/d1",
        "write_group",
        write("1/1/2", "5.001", Value::Float(120.0)),
        Perm::Write,
    )
    .await;
    assert_eq!(st, Some(Status::InvalidParameter), "{msg}");
    assert!(msg.starts_with("value:"), "{msg}");
    let (st, _, _) = act(
        &h,
        "c1/d1",
        "write_group",
        write("1/1/1", "1.001", Value::Bool(false)),
        Perm::Read,
    )
    .await;
    assert_eq!(st, Some(Status::PermissionDenied), "a write needs write");
    assert_eq!(gw.table().writes.len(), 1);
    h.stop().await;
}

/// A UDP port nobody listens on.
fn free_port() -> u16 {
    std::net::UdpSocket::bind("127.0.0.1:0")
        .unwrap()
        .local_addr()
        .unwrap()
        .port()
}

/// `c1/d1` as a routing connection on loopback at `port`.
fn routing_tree(port: u16, conn: &[(&str, Value)], points: Value) -> Tree {
    let mut c: Vec<(&str, Value)> = vec![
        ("kind", "routing_connection".into()),
        ("port", Value::UInt(port.into())),
        ("interface", "127.0.0.1".into()),
        ("individual_address", "1.1.50".into()),
        ("timeout_ms", Value::UInt(300)),
        ("rate_per_s", Value::UInt(50)),
        ("ttl", Value::UInt(1)),
    ];
    for (k, v) in conn {
        c.retain(|(n, _)| n != k);
        c.push((k, v.clone()));
    }
    tree_of(&c, points)
}

const GROUP: Ipv4Addr = Ipv4Addr::new(224, 0, 23, 12);

#[tokio::test(flavor = "multi_thread")]
async fn routing_values_reads_and_writes() {
    let port = free_port();
    let router = sim::spawn_router(GROUP, port, Ipv4Addr::LOCALHOST).unwrap();
    router.set(ga("1/0/1"), Data::long(vec![0x0C, 0x33]));
    let points = map(&[
        ("temp", pt("1/0/1", "9.001", &[READ_ON_START])),
        ("light", pt("1/1/1", "1.001", &[WRITABLE])),
        ("blind", pt("1/1/2", "5.001", &[])),
    ]);
    let h = H::start(routing_tree(port, &[], points)).await;
    connected(&h).await;
    wait("start read answered", || {
        val(&h, "temp") == Some(Value::Float(21.5))
    })
    .await;
    assert_eq!(router.table().reads, vec![ga("1/0/1")]);
    router.inject(ga("1/1/2"), Data::long(vec![0xFF]));
    wait("blind", || val(&h, "blind") == Some(Value::Float(100.0))).await;
    // a write: on the wire with our address, shown at once (no confirmation)
    assert_eq!(
        status(&h.set("c1/d1/light", true, Some(h.ptok(Perm::Write))).await),
        Some(Status::Ok)
    );
    assert_eq!(val(&h, "light"), Some(Value::Bool(true)));
    wait("router got the write", || {
        router.table().writes == vec![(ga("1/1/1"), Data::short(1))]
    })
    .await;
    // our own telegram comes back from the group and is not counted twice
    let (_, v, _) = act(&h, "c1", "recent_telegrams", map(&[]), Perm::Read).await;
    let seen = rows(v);
    let ours: Vec<&Value> = seen
        .iter()
        .filter(|g| field(g, "sent") == &Value::Bool(true))
        .collect();
    assert_eq!(ours.len(), 2, "the read and the write: {seen:?}");
    assert!(ours
        .iter()
        .all(|g| field(g, "source") == &Value::from("1.1.50")));
    assert_eq!(
        seen.iter()
            .filter(|g| field(g, "destination") == &Value::from("1/1/1"))
            .count(),
        1,
        "{seen:?}"
    );
    let (_, v, _) = act(&h, "c1", "connection_info", map(&[]), Perm::Read).await;
    assert_eq!(
        field(&v.unwrap(), "individual_address"),
        &Value::from("1.1.50")
    );
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn routing_busy_and_lost_messages() {
    let port = free_port();
    let router = sim::spawn_router(GROUP, port, Ipv4Addr::LOCALHOST).unwrap();
    let points = map(&[("light", pt("1/1/1", "1.001", &[WRITABLE]))]);
    let h = H::start(routing_tree(port, &[], points)).await;
    connected(&h).await;
    let info = || async {
        let (_, v, _) = act(&h, "c1", "connection_info", map(&[]), Perm::Read).await;
        v.unwrap()
    };
    router.lost(3);
    router.busy(800);
    let mut seen = Value::Null;
    for _ in 0..100 {
        seen = info().await;
        if field(&seen, "busy_signals") == &Value::UInt(1)
            && field(&seen, "lost_telegrams") == &Value::UInt(3)
        {
            break;
        }
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
    assert_eq!(field(&seen, "busy_signals"), &Value::UInt(1));
    assert_eq!(field(&seen, "lost_telegrams"), &Value::UInt(3));
    // our telegrams wait while the router is busy
    let begin = tokio::time::Instant::now();
    assert_eq!(
        status(&h.set("c1/d1/light", true, Some(h.ptok(Perm::Write))).await),
        Some(Status::Ok)
    );
    assert!(
        begin.elapsed() >= Duration::from_millis(400),
        "{:?}",
        begin.elapsed()
    );
    wait("router got the write", || router.table().writes.len() == 1).await;
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn routing_params_are_checked() {
    let port = free_port();
    let points = map(&[("light", pt("1/1/1", "1.001", &[]))]);
    for (conn, why) in [
        (("group", Value::from("192.168.1.1")), "not a multicast"),
        (("interface", Value::from("eth0")), "interface"),
        (("individual_address", Value::from("1.1")), "three parts"),
    ] {
        let h = H::start(routing_tree(
            port,
            std::slice::from_ref(&conn),
            points.clone(),
        ))
        .await;
        wait("failed", || state(&h, "c1").as_deref() == Some("failed")).await;
        let Some(Value::Str(text)) = h.ctx().last("c1/error").map(|s| s.v) else {
            panic!("no error for {conn:?}")
        };
        assert!(text.contains(why), "{text}");
        h.stop().await;
    }
}
