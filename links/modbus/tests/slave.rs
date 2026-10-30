//! Slave (server) mode (ruling 15, ADR 0024): a `tokio-modbus` master
//! against the link's `ip_slave` connection.

use std::net::SocketAddr;
use std::time::Duration;
use tokio_modbus::client::{tcp, Client, Context};
use tokio_modbus::prelude::{Reader, Writer};
use tokio_modbus::{ExceptionCode, Request, Slave};
use wyrm_core::meta::Writable;
use wyrm_core::{Perm, Status, Value};
use wyrm_link_modbus::{codec, Modbus};
use wyrm_link_sdk::driver::Tree;
use wyrm_link_sdk::TestHarness;

type H = TestHarness<Modbus>;

fn map(kv: &[(&str, Value)]) -> Value {
    Value::Map(
        kv.iter()
            .map(|(k, v)| ((*k).to_owned(), v.clone()))
            .collect(),
    )
}

fn pt(table: &str, addr: u64, dtype: &str, extra: &[(&str, Value)]) -> Value {
    let mut kv = vec![
        ("table", Value::from(table)),
        ("addr", Value::UInt(addr)),
        ("dtype", Value::from(dtype)),
    ];
    kv.extend_from_slice(extra);
    map(&kv)
}

/// A port that was free a moment ago.
fn free_port() -> u16 {
    std::net::TcpListener::bind("127.0.0.1:0")
        .and_then(|l| l.local_addr())
        .map(|a| a.port())
        .expect("a free port")
}

/// `s1` (an `ip_slave` on `port`) serving unit 1 as `d1` with `points`.
fn slave_tree(port: u16, points: Value) -> Tree {
    slave_tree_with(port, &[], points)
}

/// [`slave_tree`] with device params `dev` beside the unit.
fn slave_tree_with(port: u16, dev: &[(&str, Value)], points: Value) -> Tree {
    let mut d = vec![("unit", Value::UInt(1)), ("points", points)];
    d.extend_from_slice(dev);
    let dev = map(&d);
    let conn = map(&[
        ("kind", "ip_slave".into()),
        ("listen_port", Value::UInt(port.into())),
        ("devices", map(&[("d1", dev)])),
    ]);
    Tree(map(&[("connections", map(&[("s1", conn)]))]))
}

fn state(h: &H, base: &str) -> Option<String> {
    match h.ctx().last(&format!("{base}/status"))?.v {
        Value::UInt(i) => wyrm_link_sdk::driver::NodeState::NAMES
            .get(i as usize)
            .map(|s| (*s).to_owned()),
        _ => None,
    }
}

async fn wait(what: &str, mut f: impl FnMut() -> bool) {
    let deadline = tokio::time::Instant::now() + Duration::from_secs(10);
    while !f() {
        assert!(tokio::time::Instant::now() < deadline, "timeout: {what}");
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
}

fn val(h: &H, p: &str) -> Option<Value> {
    h.ctx().last(&format!("s1/d1/{p}")).map(|s| s.v)
}

fn status(a: &wyrm_core::Attachment) -> Option<Status> {
    match a.status? {
        wyrm_core::status::StatusCode::Known(s) => Some(s),
        _ => None,
    }
}

/// The link serving `points` on a free port, connected; and that port.
async fn start(points: Value) -> (H, u16) {
    let port = free_port();
    let h = H::start(slave_tree(port, points)).await;
    wait("slave listening", || {
        state(&h, "s1").as_deref() == Some("connected")
            && state(&h, "s1/d1").as_deref() == Some("connected")
    })
    .await;
    (h, port)
}

async fn master(port: u16, unit: u8) -> Context {
    let addr: SocketAddr = ([127, 0, 0, 1], port).into();
    tcp::connect_slave(addr, Slave(unit))
        .await
        .expect("master connects")
}

/// `n` holding registers from `addr` as a new master reads them once the
/// slave answers (a reopened listener may take a moment to bind).
async fn read_when_up(port: u16, addr: u16, n: u16) -> Vec<u16> {
    let deadline = tokio::time::Instant::now() + Duration::from_secs(10);
    loop {
        let addr_ = SocketAddr::from(([127, 0, 0, 1], port));
        if let Ok(mut m) = tcp::connect_slave(addr_, Slave(1)).await {
            let r = tokio::time::timeout(Duration::from_secs(1), m.read_holding_registers(addr, n));
            if let Ok(Ok(Ok(w))) = r.await {
                return w;
            }
        }
        assert!(
            tokio::time::Instant::now() < deadline,
            "timeout: slave answers"
        );
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
}

async fn set(h: &H, point: &str, v: impl Into<Value>) -> Option<Status> {
    status(
        &h.set(&format!("s1/d1/{point}"), v, Some(h.ptok(Perm::Write)))
            .await,
    )
}

/// A tree value is what a master reads: an `f32` with scaling, an input
/// register and a discrete input (tables a master cannot write but the tree
/// can), and a bit of a holding register.
#[tokio::test(flavor = "multi_thread")]
async fn master_reads_tree_values() {
    let scaled = [("scale", Value::Float(0.5)), ("offset", Value::Float(1.0))];
    let points = map(&[
        ("temp", pt("holding", 10, "f32", &scaled)),
        ("level", pt("input", 3, "u16", &[])),
        ("door", pt("discrete", 4, "binary", &[])),
        (
            "flag",
            pt("holding", 20, "binary", &[("bit", Value::UInt(2))]),
        ),
    ]);
    let (h, port) = start(points).await;
    assert_eq!(set(&h, "temp", 21.5).await, Some(Status::Ok));
    assert_eq!(set(&h, "level", 7u64).await, Some(Status::Ok));
    assert_eq!(set(&h, "door", true).await, Some(Status::Ok));
    assert_eq!(set(&h, "flag", true).await, Some(Status::Ok));
    // The value set is the value published (no device read-back).
    assert_eq!(val(&h, "temp"), Some(Value::Float(21.5)));
    assert_eq!(val(&h, "level"), Some(Value::UInt(7)));

    let mut m = master(port, 1).await;
    let w = m.read_holding_registers(10, 2).await.unwrap().unwrap();
    // raw = (21.5 - 1) / 0.5
    assert_eq!(
        codec::decode(codec::DType::F32, &w, 0, 1.0, 0.0),
        Ok(Value::Float(41.0))
    );
    assert_eq!(
        codec::decode(codec::DType::F32, &w, 0, 0.5, 1.0),
        Ok(Value::Float(21.5))
    );
    assert_eq!(m.read_input_registers(3, 1).await.unwrap(), Ok(vec![7]));
    assert_eq!(m.read_discrete_inputs(4, 1).await.unwrap(), Ok(vec![true]));
    assert_eq!(
        m.read_holding_registers(20, 1).await.unwrap(),
        Ok(vec![0b100])
    );
    // a value out of the point's range is refused and not served
    assert_eq!(
        set(&h, "level", 70_000u64).await,
        Some(Status::InvalidParameter)
    );
    assert_eq!(m.read_input_registers(3, 1).await.unwrap(), Ok(vec![7]));
    h.stop().await;
}

/// Ruling P4: a master write to a `writable_by_master` point is published
/// as the point's new value before the master gets its reply, and counted
/// in the diagnostics of the device and the connection.
#[tokio::test(flavor = "multi_thread")]
async fn master_write_updates_the_tree() {
    let w = [("writable_by_master", Value::Bool(true))];
    let points = map(&[
        ("sp", pt("holding", 20, "u16", &w)),
        ("big", pt("holding", 30, "i32", &w)),
        ("fan", pt("coil", 5, "binary", &w)),
        // shares holding 20 with `sp` (a read-only one there would refuse
        // a master's write to holding 20)
        ("sp_bit0", pt("holding", 20, "binary", &w)),
    ]);
    let (h, port) = start(points).await;
    let mut m = master(port, 1).await;
    m.write_single_register(20, 77).await.unwrap().unwrap();
    // published before the reply: no wait
    assert_eq!(val(&h, "sp"), Some(Value::UInt(77)));
    assert_eq!(val(&h, "sp_bit0"), Some(Value::Bool(true)), "overlap");
    let words = codec::encode(codec::DType::I32, &Value::Int(-70_000), 1, 1.0, 0.0).unwrap();
    m.write_multiple_registers(30, &words)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(val(&h, "big"), Some(Value::Int(-70_000)));
    m.write_single_coil(5, true).await.unwrap().unwrap();
    assert_eq!(val(&h, "fan"), Some(Value::Bool(true)));
    // FC22 on a writable register
    m.masked_write_register(20, 0xFFFE, 0x0000)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(val(&h, "sp"), Some(Value::UInt(76)));
    // the tree's value is what the master reads back
    assert_eq!(m.read_holding_registers(20, 1).await.unwrap(), Ok(vec![76]));

    // 5 requests: 4 writes and a read
    let n = |p: &str| h.ctx().last(p).map(|s| s.v);
    for node in ["s1/d1", "s1"] {
        h.meta(node).await;
        wait("diagnostics published on a read", || {
            n(&format!("{node}/requests")) == Some(Value::UInt(5))
        })
        .await;
        assert_eq!(n(&format!("{node}/exceptions")), Some(Value::UInt(0)));
    }
    h.stop().await;
}

/// A master write touching a point without `writable_by_master` answers
/// exception 3 and changes nothing (the whole request is refused).
#[tokio::test(flavor = "multi_thread")]
async fn read_only_point_written_by_master_gets_exception_3() {
    let w = [("writable_by_master", Value::Bool(true))];
    let points = map(&[
        ("ro", pt("holding", 40, "u16", &[])),
        ("rw", pt("holding", 41, "u16", &w)),
        ("coil", pt("coil", 2, "binary", &[])),
    ]);
    let (h, port) = start(points).await;
    assert_eq!(set(&h, "ro", 5u64).await, Some(Status::Ok));
    assert_eq!(set(&h, "rw", 6u64).await, Some(Status::Ok));
    let mut m = master(port, 1).await;
    assert_eq!(
        m.write_single_register(40, 9).await.unwrap(),
        Err(ExceptionCode::IllegalDataValue)
    );
    // a span over a read-only and a writable point: neither changes
    assert_eq!(
        m.write_multiple_registers(40, &[9, 9]).await.unwrap(),
        Err(ExceptionCode::IllegalDataValue)
    );
    assert_eq!(
        m.write_single_coil(2, true).await.unwrap(),
        Err(ExceptionCode::IllegalDataValue)
    );
    assert_eq!(
        m.masked_write_register(40, 0, 0).await.unwrap(),
        Err(ExceptionCode::IllegalDataValue)
    );
    assert_eq!(
        m.read_holding_registers(40, 2).await.unwrap(),
        Ok(vec![5, 6])
    );
    assert_eq!(val(&h, "ro"), Some(Value::UInt(5)));
    assert_eq!(val(&h, "rw"), Some(Value::UInt(6)));
    assert_eq!(
        val(&h, "coil"),
        None,
        "never set, and the master's write refused"
    );
    // counted as exceptions
    h.meta("s1/d1").await;
    wait("exceptions counted", || {
        h.ctx().last("s1/d1/exceptions").map(|s| s.v) == Some(Value::UInt(4))
    })
    .await;
    h.stop().await;
}

/// An address no point covers answers exception 2, a read past one point
/// too; a function the slave lacks answers 1, a unit it does not serve
/// 0x0B (TCP), more registers than one request carries 3.
#[tokio::test(flavor = "multi_thread")]
async fn unknown_address_gets_exception_2() {
    let w = [("writable_by_master", Value::Bool(true))];
    let points = map(&[("sp", pt("holding", 10, "u16", &w))]);
    let (h, port) = start(points).await;
    assert_eq!(set(&h, "sp", 3u64).await, Some(Status::Ok));
    let mut m = master(port, 1).await;
    assert_eq!(m.read_holding_registers(10, 1).await.unwrap(), Ok(vec![3]));
    for (addr, n) in [(11, 1), (9, 2), (10, 2)] {
        assert_eq!(
            m.read_holding_registers(addr, n).await.unwrap(),
            Err(ExceptionCode::IllegalDataAddress),
            "read {addr}+{n}"
        );
    }
    // another table at the same address
    assert_eq!(
        m.read_input_registers(10, 1).await.unwrap(),
        Err(ExceptionCode::IllegalDataAddress)
    );
    assert_eq!(
        m.read_coils(10, 1).await.unwrap(),
        Err(ExceptionCode::IllegalDataAddress)
    );
    assert_eq!(
        m.write_single_register(11, 1).await.unwrap(),
        Err(ExceptionCode::IllegalDataAddress)
    );
    assert_eq!(
        m.write_multiple_registers(10, &[1, 2]).await.unwrap(),
        Err(ExceptionCode::IllegalDataAddress)
    );
    assert_eq!(val(&h, "sp"), Some(Value::UInt(3)), "nothing written");
    assert_eq!(
        m.call(Request::Custom(0x41, Vec::new().into()))
            .await
            .unwrap(),
        Err(ExceptionCode::IllegalFunction)
    );
    assert_eq!(
        m.read_holding_registers(10, 126).await.unwrap(),
        Err(ExceptionCode::IllegalDataValue)
    );
    let mut other = master(port, 9).await;
    assert_eq!(
        other.read_holding_registers(10, 1).await.unwrap(),
        Err(ExceptionCode::GatewayTargetDevice)
    );
    h.stop().await;
}

/// Review Focus 4: tree sets and master writes of the same point race; the
/// last writer wins, and the published value is what the next master read
/// returns.
#[tokio::test(flavor = "multi_thread")]
async fn tree_set_and_master_write_race() {
    let w = [("writable_by_master", Value::Bool(true))];
    let points = map(&[("sp", pt("holding", 30, "u16", &w))]);
    let (h, port) = start(points).await;
    let mut m = master(port, 1).await;
    let mut reader = master(port, 1).await;
    // within the SDK's burst of sets per caller
    const N: u16 = 60;
    let tree = async {
        for i in 0..N {
            assert_eq!(set(&h, "sp", u64::from(1000 + i)).await, Some(Status::Ok));
        }
    };
    let wire = async {
        for i in 0..N {
            m.write_single_register(30, 5000 + i)
                .await
                .unwrap()
                .unwrap();
        }
    };
    tokio::join!(tree, wire);
    // Both sides are done: nothing is in flight.
    let read = m.read_holding_registers(30, 1).await.unwrap().unwrap()[0];
    assert!(
        read == 1000 + N - 1 || read == 5000 + N - 1,
        "the last writer wins: {read}"
    );
    assert_eq!(val(&h, "sp"), Some(Value::UInt(read.into())));
    // and it stays so
    tokio::time::sleep(Duration::from_millis(100)).await;
    assert_eq!(
        reader.read_holding_registers(30, 1).await.unwrap(),
        Ok(vec![read])
    );
    assert_eq!(val(&h, "sp"), Some(Value::UInt(read.into())));
    h.stop().await;
}

async fn act(h: &H, path: &str, action: &str, args: Value) -> Option<Status> {
    let r = h
        .invoke(path, action, args, Some(h.ptok(Perm::Config)))
        .await;
    assert_eq!(r.len(), 1, "{path} {action}: one reply");
    status(&r[0].att)
}

/// A slave is a server kind: every point takes `~set`, nothing is polled
/// or pinged, and the commissioning actions of master connections are not
/// offered.
#[tokio::test(flavor = "multi_thread")]
async fn slave_kinds_are_served_not_polled() {
    // Fast polls and pings, were they run: a slave's `poll` and `ping` fail
    // (it is never polled), so one tick would fail the device.
    let fast = [("poll_s", Value::Float(0.05))];
    let points = map(&[
        ("level", pt("input", 3, "u16", &fast)),
        ("sp", pt("holding", 4, "u16", &fast)),
    ]);
    let port = free_port();
    let h = H::start(slave_tree_with(
        port,
        &[("ping_s", Value::Float(0.1))],
        points,
    ))
    .await;
    wait("slave listening", || {
        state(&h, "s1/d1").as_deref() == Some("connected")
    })
    .await;
    let (_, root) = h.meta("").await;
    let root = root.unwrap().actions.unwrap();
    assert_eq!(
        root["add_ip_slave"].display.as_deref(),
        Some("Add IP Slave")
    );
    assert_eq!(
        root["add_serial_slave"].display.as_deref(),
        Some("Add Serial Slave")
    );
    let (_, conn) = h.meta("s1").await;
    let conn = conn.unwrap();
    assert!(!conn.actions.as_ref().unwrap().contains_key("scan_units"));
    assert_eq!(
        conn.cfg.as_ref().unwrap()["listen_host"],
        Value::from("127.0.0.1"),
        "loopback by default"
    );
    let (_, dev) = h.meta("s1/d1").await;
    let acts = dev.unwrap().actions.unwrap();
    for a in ["read_registers", "read_device_id"] {
        assert!(!acts.contains_key(a), "{a} on a slave device");
    }
    for p in ["level", "sp"] {
        let (_, meta) = h.meta(&format!("s1/d1/{p}")).await;
        assert_eq!(meta.unwrap().writable, Some(Writable::Write), "{p}");
    }
    assert_eq!(set(&h, "level", 4u64).await, Some(Status::Ok));
    // no poll and no ping: the device stays connected, the value good, and
    // no request is counted
    tokio::time::sleep(Duration::from_millis(500)).await;
    assert_eq!(state(&h, "s1/d1").as_deref(), Some("connected"));
    let level = h.ctx().last("s1/d1/level").unwrap();
    assert_eq!(
        (level.v, level.q),
        (Value::UInt(4), wyrm_core::Quality::Good)
    );
    h.meta("s1/d1").await;
    wait("diagnostics published", || {
        h.ctx().last("s1/d1/requests").is_some()
    })
    .await;
    assert_eq!(
        h.ctx().last("s1/d1/requests").map(|s| s.v),
        Some(Value::UInt(0))
    );
    // `writable_by_master` on a table no master can write is refused
    let bad = map(&[
        ("name", "x".into()),
        ("table", "input".into()),
        ("addr", Value::UInt(9)),
        ("writable_by_master", Value::Bool(true)),
    ]);
    assert_eq!(
        act(&h, "s1/d1", "add_point", bad).await,
        Some(Status::InvalidParameter)
    );
    h.stop().await;
}

/// The served values survive a re-plan (a point added in a folder is served
/// at once) and a restart of the connection (the listener closes, opens
/// again on the same port, and serves the tree's last values).
#[tokio::test(flavor = "multi_thread")]
async fn slave_values_survive_a_replan_and_a_restart() {
    let points = map(&[("a", pt("holding", 1, "u16", &[]))]);
    let (h, port) = start(points).await;
    assert_eq!(set(&h, "a", 7u64).await, Some(Status::Ok));
    let folder = map(&[("name", "f1".into())]);
    assert_eq!(
        act(&h, "s1/d1", "add_folder", folder).await,
        Some(Status::Ok)
    );
    let b = map(&[
        ("name", "b".into()),
        ("table", "holding".into()),
        ("addr", Value::UInt(2)),
    ]);
    assert_eq!(act(&h, "s1/d1/f1", "add_point", b).await, Some(Status::Ok));
    let mut m = master(port, 1).await;
    // b is served at once, without a value until the tree sets one
    assert_eq!(
        m.read_holding_registers(1, 2).await.unwrap(),
        Err(ExceptionCode::ServerDeviceFailure)
    );
    assert_eq!(m.read_holding_registers(1, 1).await.unwrap(), Ok(vec![7]));
    assert_eq!(h.ctx().last("s1/d1/f1/b"), None);
    assert_eq!(
        status(&h.set("s1/d1/f1/b", 8u64, Some(h.ptok(Perm::Write))).await),
        Some(Status::Ok)
    );
    assert_eq!(act(&h, "s1", "restart", map(&[])).await, Some(Status::Ok));
    assert_eq!(read_when_up(port, 1, 2).await, vec![7, 8]);
    assert_eq!(val(&h, "a"), Some(Value::UInt(7)));
    h.stop().await;
}

/// A device stopped and started serves the tree's value again (not 0), and
/// a point edited to another scale serves the tree's value re-encoded.
#[tokio::test(flavor = "multi_thread")]
async fn slave_values_survive_a_device_stop_and_an_edit() {
    let points = map(&[("a", pt("holding", 1, "u16", &[]))]);
    let (h, port) = start(points).await;
    assert_eq!(set(&h, "a", 7u64).await, Some(Status::Ok));
    assert_eq!(act(&h, "s1/d1", "stop", map(&[])).await, Some(Status::Ok));
    let mut m = master(port, 1).await;
    assert_eq!(
        m.read_holding_registers(1, 1).await.unwrap(),
        Err(ExceptionCode::GatewayTargetDevice),
        "a stopped device is not served"
    );
    assert_eq!(act(&h, "s1/d1", "start", map(&[])).await, Some(Status::Ok));
    wait("device served again", || {
        state(&h, "s1/d1").as_deref() == Some("connected")
    })
    .await;
    assert_eq!(m.read_holding_registers(1, 1).await.unwrap(), Ok(vec![7]));
    assert_eq!(val(&h, "a"), Some(Value::UInt(7)));

    let edit = map(&[
        ("table", "holding".into()),
        ("addr", Value::UInt(1)),
        ("dtype", "u16".into()),
        ("scale", Value::Float(0.5)),
    ]);
    assert_eq!(act(&h, "s1/d1/a", "edit", edit).await, Some(Status::Ok));
    // raw = 7 / 0.5; the edit's re-plan reaches the server at once
    assert_eq!(m.read_holding_registers(1, 1).await.unwrap(), Ok(vec![14]));
    assert_eq!(val(&h, "a"), Some(Value::Float(7.0)));
    h.stop().await;
}

/// A slave connection copies, exports and imports like any connection; the
/// copy and the import start stopped, so neither takes the port.
#[tokio::test(flavor = "multi_thread")]
async fn slave_copy_export_import() {
    let points = map(&[("a", pt("holding", 1, "u16", &[]))]);
    let (h, port) = start(points).await;
    assert_eq!(set(&h, "a", 7u64).await, Some(Status::Ok));
    let copy = map(&[("name", "s2".into())]);
    assert_eq!(act(&h, "s1", "copy", copy).await, Some(Status::Ok));
    let mut r = h
        .invoke("s1", "export", map(&[]), Some(h.ptok(Perm::Config)))
        .await;
    let json = match r.remove(0).value() {
        Some(Value::Map(m)) => m["json"].clone(),
        other => panic!("export: {other:?}"),
    };
    let import = map(&[("json", json), ("name", "s3".into())]);
    assert_eq!(act(&h, "", "import", import).await, Some(Status::Ok));
    for c in ["s2", "s3"] {
        wait("stopped", || state(&h, c).as_deref() == Some("stopped")).await;
        let (_, meta) = h.meta(c).await;
        assert_eq!(
            meta.unwrap().cfg.unwrap()["kind"],
            Value::from("ip_slave"),
            "{c}"
        );
        let (_, p) = h.meta(&format!("{c}/d1/a")).await;
        assert_eq!(p.unwrap().writable, Some(Writable::Write), "{c}");
    }
    // s1 still serves its port alone
    assert_eq!(read_when_up(port, 1, 1).await, vec![7]);
    h.stop().await;
}

/// Ruling P24: a point the tree never set has no value. Nothing is
/// published for it, a master read touching it answers exception 0x04, and
/// a new point does not take over the words of a removed one.
#[tokio::test(flavor = "multi_thread")]
async fn unset_points_have_no_value() {
    let points = map(&[
        ("a", pt("holding", 1, "u16", &[])),
        ("b", pt("holding", 2, "u16", &[])),
    ]);
    let (h, port) = start(points).await;
    let mut m = master(port, 1).await;
    assert_eq!(
        m.read_holding_registers(1, 1).await.unwrap(),
        Err(ExceptionCode::ServerDeviceFailure)
    );
    assert_eq!(h.ctx().last("s1/d1/a"), None, "no invented value");
    assert_eq!(set(&h, "a", 7u64).await, Some(Status::Ok));
    assert_eq!(m.read_holding_registers(1, 1).await.unwrap(), Ok(vec![7]));
    assert_eq!(
        m.read_holding_registers(1, 2).await.unwrap(),
        Err(ExceptionCode::ServerDeviceFailure),
        "b is unset"
    );
    assert_eq!(h.ctx().last("s1/d1/b"), None);
    // a removed point's words do not pass to a new point at its address
    assert_eq!(
        act(&h, "s1/d1/a", "remove", map(&[])).await,
        Some(Status::Ok)
    );
    let c = map(&[
        ("name", "c".into()),
        ("table", "holding".into()),
        ("addr", Value::UInt(1)),
    ]);
    assert_eq!(act(&h, "s1/d1", "add_point", c).await, Some(Status::Ok));
    assert_eq!(
        m.read_holding_registers(1, 1).await.unwrap(),
        Err(ExceptionCode::ServerDeviceFailure)
    );
    assert_eq!(h.ctx().last("s1/d1/c"), None);
    h.stop().await;
}

/// Ruling P25: a master write that a point it touches cannot decode
/// (invalid BCD) or that makes a float not finite answers exception 3 and
/// changes nothing; a valid partial write of a set value goes through.
#[tokio::test(flavor = "multi_thread")]
async fn undecodable_master_write_gets_exception_3() {
    let w = [("writable_by_master", Value::Bool(true))];
    let points = map(&[
        ("bcd", pt("holding", 50, "bcd16", &w)),
        ("temp", pt("holding", 60, "f32", &w)),
    ]);
    let (h, port) = start(points).await;
    assert_eq!(set(&h, "bcd", 12u64).await, Some(Status::Ok));
    assert_eq!(set(&h, "temp", 1.0).await, Some(Status::Ok));
    let mut m = master(port, 1).await;
    assert_eq!(
        m.write_single_register(50, 0x00FA).await.unwrap(),
        Err(ExceptionCode::IllegalDataValue),
        "0x00FA is no BCD"
    );
    assert_eq!(
        m.read_holding_registers(50, 1).await.unwrap(),
        Ok(vec![0x0012])
    );
    assert_eq!(val(&h, "bcd"), Some(Value::UInt(12)));
    let one = m.read_holding_registers(60, 2).await.unwrap().unwrap();
    for words in [[0x7FC0, 0x0000], [0x7F80, 0x0000]] {
        assert_eq!(
            m.write_multiple_registers(60, &words).await.unwrap(),
            Err(ExceptionCode::IllegalDataValue),
            "NaN or Inf: {words:x?}"
        );
    }
    assert_eq!(m.read_holding_registers(60, 2).await.unwrap(), Ok(one));
    assert_eq!(val(&h, "temp"), Some(Value::Float(1.0)));
    // the high word of 2.0 alone: a valid value
    m.write_single_register(60, 0x4000).await.unwrap().unwrap();
    assert_eq!(val(&h, "temp"), Some(Value::Float(2.0)));
    h.stop().await;
}

/// `listen_host = "localhost"` listens on every address it resolves to:
/// an IPv4 master reaches it (macOS resolves `::1` first), and so does an
/// IPv6 one where the host has `::1`.
#[tokio::test(flavor = "multi_thread")]
async fn localhost_listens_on_every_address() {
    let port = free_port();
    let dev = map(&[
        ("unit", Value::UInt(1)),
        ("points", map(&[("a", pt("holding", 1, "u16", &[]))])),
    ]);
    let conn = map(&[
        ("kind", "ip_slave".into()),
        ("listen_host", "localhost".into()),
        ("listen_port", Value::UInt(port.into())),
        ("devices", map(&[("d1", dev)])),
    ]);
    let h = H::start(Tree(map(&[("connections", map(&[("s1", conn)]))]))).await;
    wait("slave listening", || {
        state(&h, "s1/d1").as_deref() == Some("connected")
    })
    .await;
    assert_eq!(set(&h, "a", 5u64).await, Some(Status::Ok));
    assert_eq!(read_when_up(port, 1, 1).await, vec![5], "IPv4");
    let v6: SocketAddr = (std::net::Ipv6Addr::LOCALHOST, port).into();
    let has_v6 = std::net::TcpListener::bind((std::net::Ipv6Addr::LOCALHOST, 0)).is_ok();
    let resolves_v6 = tokio::net::lookup_host(("localhost", port))
        .await
        .is_ok_and(|mut a| a.any(|a| a.is_ipv6()));
    if has_v6 && resolves_v6 {
        let mut m = tcp::connect_slave(v6, Slave(1)).await.expect("IPv6 master");
        assert_eq!(m.read_holding_registers(1, 1).await.unwrap(), Ok(vec![5]));
    }
    h.stop().await;
}

fn bit(addr: u64, bit: u64) -> Value {
    pt("holding", addr, "binary", &[("bit", Value::UInt(bit))])
}

/// Ruling P28: bits of one register are known one by one. Setting one bit
/// point publishes nothing for its siblings or for a word view of the
/// register, and a master read answers 0x04 until every bit its points read
/// is known; bits no point reads may stay unknown.
#[tokio::test(flavor = "multi_thread")]
async fn bit_points_share_a_register_without_invented_bits() {
    let points = map(&[
        ("b0", bit(5, 0)),
        ("b1", bit(5, 1)),
        ("f", bit(6, 2)),
        ("w", pt("holding", 6, "u16", &[])),
    ]);
    let (h, port) = start(points).await;
    let mut m = master(port, 1).await;
    assert_eq!(set(&h, "b0", true).await, Some(Status::Ok));
    assert_eq!(val(&h, "b0"), Some(Value::Bool(true)));
    assert_eq!(val(&h, "b1"), None, "a sibling bit is not invented");
    assert_eq!(
        m.read_holding_registers(5, 1).await.unwrap(),
        Err(ExceptionCode::ServerDeviceFailure),
        "b1 unknown"
    );
    assert_eq!(set(&h, "b1", false).await, Some(Status::Ok));
    // bits 2..15 are read by no point: they may stay unknown (served 0)
    assert_eq!(
        m.read_holding_registers(5, 1).await.unwrap(),
        Ok(vec![0b01])
    );
    // a word view stays unset until all its bits are known
    assert_eq!(set(&h, "f", true).await, Some(Status::Ok));
    assert_eq!(val(&h, "w"), None, "one bit is not a word");
    assert_eq!(
        m.read_holding_registers(6, 1).await.unwrap(),
        Err(ExceptionCode::ServerDeviceFailure)
    );
    assert_eq!(set(&h, "w", 0x00F0u64).await, Some(Status::Ok));
    assert_eq!(
        m.read_holding_registers(6, 1).await.unwrap(),
        Ok(vec![0x00F0])
    );
    assert_eq!(val(&h, "f"), Some(Value::Bool(false)), "bit 2 of 0x00F0");
    h.stop().await;
}

/// Ruling P28: a new bit point at the address of a removed one does not
/// take over its bit, while the kept sibling keeps its own.
#[tokio::test(flavor = "multi_thread")]
async fn a_new_bit_point_does_not_inherit_a_removed_bit() {
    let points = map(&[("c0", bit(7, 0)), ("c1", bit(7, 1))]);
    let (h, port) = start(points).await;
    assert_eq!(set(&h, "c0", true).await, Some(Status::Ok));
    assert_eq!(set(&h, "c1", true).await, Some(Status::Ok));
    assert_eq!(
        act(&h, "s1/d1/c1", "remove", map(&[])).await,
        Some(Status::Ok)
    );
    let c2 = map(&[
        ("name", "c2".into()),
        ("table", "holding".into()),
        ("addr", Value::UInt(7)),
        ("dtype", "binary".into()),
        ("bit", Value::UInt(1)),
    ]);
    assert_eq!(act(&h, "s1/d1", "add_point", c2).await, Some(Status::Ok));
    let mut m = master(port, 1).await;
    assert_eq!(
        m.read_holding_registers(7, 1).await.unwrap(),
        Err(ExceptionCode::ServerDeviceFailure),
        "c2's bit is unknown"
    );
    assert_eq!(h.ctx().last("s1/d1/c2"), None);
    assert_eq!(val(&h, "c0"), Some(Value::Bool(true)));
    h.stop().await;
}

/// N4: a tree set whose words an overlapping view of another type cannot
/// decode (invalid BCD) or would make not finite (Inf) is refused, and
/// nothing changes.
#[tokio::test(flavor = "multi_thread")]
async fn a_tree_set_that_breaks_an_overlapping_view_is_refused() {
    let points = map(&[
        ("bcd", pt("holding", 50, "bcd16", &[])),
        ("raw", pt("holding", 50, "u16", &[])),
        ("temp", pt("holding", 60, "f32", &[])),
        ("hi14", bit(60, 14)),
    ]);
    let (h, port) = start(points).await;
    assert_eq!(set(&h, "bcd", 12u64).await, Some(Status::Ok));
    assert_eq!(val(&h, "raw"), Some(Value::UInt(0x12)));
    assert_eq!(
        set(&h, "raw", 0x00FAu64).await,
        Some(Status::InvalidParameter),
        "0x00FA is no BCD"
    );
    assert_eq!(set(&h, "temp", 1.0).await, Some(Status::Ok));
    // 1.0 = 0x3F80 0x0000; bit 14 of the high word makes 0x7F80: Inf
    assert_eq!(set(&h, "hi14", true).await, Some(Status::InvalidParameter));
    let mut m = master(port, 1).await;
    assert_eq!(
        m.read_holding_registers(50, 1).await.unwrap(),
        Ok(vec![0x12])
    );
    assert_eq!(
        m.read_holding_registers(60, 2).await.unwrap(),
        Ok(vec![0x3F80, 0])
    );
    assert_eq!(val(&h, "raw"), Some(Value::UInt(0x12)));
    assert_eq!(val(&h, "temp"), Some(Value::Float(1.0)));
    assert_eq!(val(&h, "hi14"), Some(Value::Bool(false)));
    h.stop().await;
}

/// N2: an address in use (not merely missing on this host) fails the
/// connection with that error, instead of listening on the others only.
#[tokio::test(flavor = "multi_thread")]
async fn a_port_in_use_fails_the_connection() {
    let taken = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    let port = taken.local_addr().unwrap().port();
    let dev = map(&[
        ("unit", Value::UInt(1)),
        ("points", map(&[("a", pt("holding", 1, "u16", &[]))])),
    ]);
    let conn = map(&[
        ("kind", "ip_slave".into()),
        ("listen_host", "localhost".into()),
        ("listen_port", Value::UInt(port.into())),
        ("devices", map(&[("d1", dev)])),
    ]);
    let h = H::start(Tree(map(&[("connections", map(&[("s1", conn)]))]))).await;
    wait("failed", || state(&h, "s1").as_deref() == Some("failed")).await;
    let err = h.ctx().last("s1/error").map(|s| s.v);
    let Some(Value::Str(err)) = err else {
        panic!("no error: {err:?}");
    };
    assert!(err.contains("127.0.0.1"), "{err}");
    drop(taken);
    h.stop().await;
}

/// The quality codes (attachment key 1) published on `s1/d1/<p>/~val`,
/// in order, from now on.
async fn quals(h: &H, p: &str) -> std::sync::Arc<std::sync::Mutex<Vec<Option<String>>>> {
    let seen = std::sync::Arc::new(std::sync::Mutex::new(Vec::new()));
    let sub = h
        .session()
        .declare_subscriber(h.key(&format!("s1/d1/{p}"), "~val"))
        .await
        .expect("subscriber");
    let sink = seen.clone();
    tokio::spawn(async move {
        while let Ok(s) = sub.recv_async().await {
            let qual = s
                .attachment()
                .and_then(|a| {
                    wyrm_core::codec::from_slice::<wyrm_core::Attachment>(&a.to_bytes()).ok()
                })
                .and_then(|a| a.qual);
            sink.lock().unwrap().push(qual);
        }
    });
    seen
}

/// 50000 on a u16 point, then the point edited to `i16`.
fn to_i16() -> Value {
    map(&[
        ("table", "holding".into()),
        ("addr", Value::UInt(1)),
        ("dtype", "i16".into()),
    ])
}

/// O1 (ruling P29): a point edited to a data type its tree value does not
/// fit (50000 as `i16`) serves nothing; the broker's old value is marked
/// bad with the reason `bad/config_error`, not left good, until the tree
/// sets one.
#[tokio::test(flavor = "multi_thread")]
async fn a_tree_value_the_edited_point_cannot_serve_is_bad() {
    let points = map(&[("a", pt("holding", 1, "u16", &[]))]);
    let (h, port) = start(points).await;
    assert_eq!(set(&h, "a", 50_000u64).await, Some(Status::Ok));
    let seen = quals(&h, "a").await;
    assert_eq!(act(&h, "s1/d1/a", "edit", to_i16()).await, Some(Status::Ok));
    let last = || h.ctx().last("s1/d1/a").expect("a sample");
    wait("marked bad", || last().q == wyrm_core::Quality::Bad).await;
    wait("reason config_error", || {
        seen.lock().unwrap().last() == Some(&Some("bad/config_error".to_owned()))
    })
    .await;
    assert_eq!(last().v, Value::UInt(50_000), "the old value kept");
    let mut m = master(port, 1).await;
    assert_eq!(
        m.read_holding_registers(1, 1).await.unwrap(),
        Err(ExceptionCode::ServerDeviceFailure),
        "nothing served"
    );
    assert_eq!(set(&h, "a", Value::Int(-5)).await, Some(Status::Ok));
    assert_eq!(last().q, wyrm_core::Quality::Good);
    assert_eq!(last().v, Value::Int(-5));
    assert_eq!(
        m.read_holding_registers(1, 1).await.unwrap(),
        Ok(vec![0xFFFB]),
        "-5 as i16"
    );
    h.stop().await;
}

/// O1 on a reopened server: the point is already bad (`bad/disconnected`,
/// the connection stopped) when it is edited; after `start` the reason
/// becomes `bad/config_error`, as the quality alone would not change.
#[tokio::test(flavor = "multi_thread")]
async fn a_reopened_server_shows_config_error_on_an_already_bad_point() {
    let points = map(&[("a", pt("holding", 1, "u16", &[]))]);
    let (h, _port) = start(points).await;
    assert_eq!(set(&h, "a", 50_000u64).await, Some(Status::Ok));
    let seen = quals(&h, "a").await;
    assert_eq!(act(&h, "s1", "stop", map(&[])).await, Some(Status::Ok));
    let last = || h.ctx().last("s1/d1/a").expect("a sample");
    wait("disconnected", || {
        seen.lock().unwrap().last() == Some(&Some("bad/disconnected".to_owned()))
    })
    .await;
    assert_eq!(act(&h, "s1/d1/a", "edit", to_i16()).await, Some(Status::Ok));
    assert_eq!(act(&h, "s1", "start", map(&[])).await, Some(Status::Ok));
    wait("served again", || {
        state(&h, "s1/d1").as_deref() == Some("connected")
    })
    .await;
    wait("reason config_error", || {
        seen.lock().unwrap().last() == Some(&Some("bad/config_error".to_owned()))
    })
    .await;
    assert_eq!(last().q, wyrm_core::Quality::Bad);
    assert_eq!(last().v, Value::UInt(50_000), "the old value kept");
    h.stop().await;
}

/// Final review M9: an `ip_slave` serves at most 16 masters at once; the
/// 17th is closed at once (it reads end of stream), and once a master
/// leaves, a new one is served.
#[tokio::test(flavor = "multi_thread")]
async fn at_most_16_masters_are_served() {
    use tokio::io::AsyncReadExt;
    let (h, port) = start(map(&[("v", pt("holding", 0, "u16", &[]))])).await;
    assert_eq!(set(&h, "v", 5u64).await, Some(Status::Ok));
    let mut masters = Vec::new();
    for i in 0..16 {
        let mut m = master(port, 1).await;
        let r = tokio::time::timeout(Duration::from_secs(2), m.read_holding_registers(0, 1));
        assert_eq!(
            r.await.ok().and_then(Result::ok),
            Some(Ok(vec![5])),
            "master {i}"
        );
        masters.push(m);
    }
    let addr = SocketAddr::from(([127, 0, 0, 1], port));
    let mut extra = tokio::net::TcpStream::connect(addr).await.unwrap();
    let mut buf = [0u8; 8];
    let r = tokio::time::timeout(Duration::from_secs(2), extra.read(&mut buf)).await;
    assert!(
        matches!(r, Ok(Ok(0)) | Ok(Err(_))),
        "the 17th master is closed: {r:?}"
    );
    // One leaves: a new master is served.
    let mut gone = masters.pop().unwrap();
    let _ = gone.disconnect().await;
    drop(gone);
    assert_eq!(read_when_up(port, 0, 1).await, vec![5]);
    h.stop().await;
}

/// Final review M10: `listen_port` 0 (a port no master can know) is refused.
#[tokio::test(flavor = "multi_thread")]
async fn listen_port_0_is_refused() {
    let (h, _) = start(map(&[])).await;
    let args = map(&[("name", "s2".into()), ("listen_port", Value::UInt(0))]);
    assert_eq!(
        act(&h, "", "add_ip_slave", args).await,
        Some(Status::InvalidParameter)
    );
    let edit = map(&[("listen_port", Value::UInt(0))]);
    assert_eq!(
        act(&h, "s1", "edit", edit).await,
        Some(Status::InvalidParameter)
    );
    assert_eq!(state(&h, "s1").as_deref(), Some("connected"));
    h.stop().await;
}

/// Security review (M9 follow-up): a master that sends no complete request
/// for `master_idle_s` is closed and frees its place, so 16 idle sockets do
/// not lock real masters out; a master that keeps asking stays connected.
#[tokio::test(flavor = "multi_thread")]
async fn idle_masters_are_closed() {
    use tokio::io::AsyncReadExt;
    let port = free_port();
    let dev = map(&[
        ("unit", Value::UInt(1)),
        ("points", map(&[("v", pt("holding", 0, "u16", &[]))])),
    ]);
    let conn = map(&[
        ("kind", "ip_slave".into()),
        ("listen_port", Value::UInt(port.into())),
        ("master_idle_s", Value::UInt(1)),
        ("devices", map(&[("d1", dev)])),
    ]);
    let h = H::start(Tree(map(&[("connections", map(&[("s1", conn)]))]))).await;
    wait("slave listening", || {
        state(&h, "s1").as_deref() == Some("connected")
    })
    .await;
    assert_eq!(set(&h, "v", 9u64).await, Some(Status::Ok));
    let addr = SocketAddr::from(([127, 0, 0, 1], port));
    // A master that asks every 300 ms is served all along.
    let mut busy = master(port, 1).await;
    // 16 sockets that never send a request fill every place.
    let mut idle = Vec::new();
    for _ in 0..16 {
        idle.push(tokio::net::TcpStream::connect(addr).await.unwrap());
    }
    let start = std::time::Instant::now();
    while start.elapsed() < Duration::from_millis(2500) {
        let r = tokio::time::timeout(Duration::from_secs(1), busy.read_holding_registers(0, 1));
        assert_eq!(
            r.await.ok().and_then(Result::ok),
            Some(Ok(vec![9])),
            "an active master after {:?}",
            start.elapsed()
        );
        tokio::time::sleep(Duration::from_millis(300)).await;
    }
    // The idle ones were closed after about 1 s ...
    let mut closed = 0;
    for s in &mut idle {
        let mut buf = [0u8; 8];
        let r = tokio::time::timeout(Duration::from_secs(1), s.read(&mut buf)).await;
        if matches!(r, Ok(Ok(0)) | Ok(Err(_))) {
            closed += 1;
        }
    }
    // ... (15 of them: the active master took the 16th place first)
    assert!(closed >= 15, "{closed} idle masters closed");
    // ... and new masters are served.
    assert_eq!(read_when_up(port, 0, 1).await, vec![9]);
    h.stop().await;
}

/// Security review: a master that sends requests but never reads the
/// replies fills its window, and the slave's write waits; the idle
/// deadline holds on the write path too, so the master is dropped and its
/// place freed.
#[tokio::test(flavor = "multi_thread")]
async fn a_master_that_never_reads_is_dropped() {
    use tokio::io::AsyncWriteExt;
    let port = free_port();
    let dev = map(&[
        ("unit", Value::UInt(1)),
        (
            "points",
            map(&[
                ("v", pt("holding", 200, "u16", &[])),
                ("s", pt("holding", 0, "char", &[("regs", Value::UInt(125))])),
            ]),
        ),
    ]);
    let conn = map(&[
        ("kind", "ip_slave".into()),
        ("listen_port", Value::UInt(port.into())),
        ("master_idle_s", Value::UInt(1)),
        ("devices", map(&[("d1", dev)])),
    ]);
    let h = H::start(Tree(map(&[("connections", map(&[("s1", conn)]))]))).await;
    wait("slave listening", || {
        state(&h, "s1").as_deref() == Some("connected")
    })
    .await;
    assert_eq!(set(&h, "v", 9u64).await, Some(Status::Ok));
    assert_eq!(set(&h, "s", "x".repeat(250)).await, Some(Status::Ok));
    let addr = SocketAddr::from(([127, 0, 0, 1], port));
    // A small receive window that this master never reads.
    let sock = tokio::net::TcpSocket::new_v4().unwrap();
    sock.set_recv_buffer_size(4096).unwrap();
    let stream = sock.connect(addr).await.unwrap();
    let (unread, mut tx) = stream.into_split();
    // Reads of 125 registers (259-byte replies) without end: the replies
    // outgrow every socket buffer, so the slave's write waits (and the
    // master never goes idle while the slave keeps up).
    let flood = tokio::spawn(async move {
        let mut i = 0u16;
        loop {
            let mut frames = Vec::new();
            for _ in 0..1000 {
                i = i.wrapping_add(1);
                frames.extend_from_slice(&i.to_be_bytes());
                frames.extend_from_slice(&[0, 0, 0, 6, 1, 3, 0, 0, 0, 125]);
            }
            if tx.write_all(&frames).await.is_err() {
                return;
            }
        }
    });
    // One second after its last complete request (its writes wait) the
    // master is dropped: then 16 new masters are served at once (well
    // inside their own idle time, so none of them frees a place).
    let deadline = tokio::time::Instant::now() + Duration::from_secs(30);
    loop {
        let mut served = 0;
        let mut masters = Vec::new();
        for _ in 0..16 {
            let mut m = master(port, 1).await;
            let r =
                tokio::time::timeout(Duration::from_millis(500), m.read_holding_registers(200, 1));
            if r.await.ok().and_then(Result::ok) == Some(Ok(vec![9])) {
                served += 1;
            }
            masters.push(m);
        }
        if served == 16 {
            break;
        }
        assert!(
            tokio::time::Instant::now() < deadline,
            "{served} masters served at once: the never-reading one holds a place"
        );
        drop(masters);
        tokio::time::sleep(Duration::from_millis(300)).await;
    }
    flood.abort();
    // And its socket was closed: past the replies it got, it reads the end.
    let drained = tokio::time::timeout(Duration::from_secs(10), async move {
        use tokio::io::AsyncReadExt;
        let mut unread = unread;
        let mut buf = vec![0u8; 65536];
        loop {
            match unread.read(&mut buf).await {
                Ok(0) | Err(_) => break,
                Ok(_) => {}
            }
        }
    });
    assert!(drained.await.is_ok(), "the never-reading master stays open");
    h.stop().await;
}
