//! The modbus framework driver against the in-process simulator.

use std::time::Duration;
use wyrm_core::{Perm, Quality, Status, Value};
use wyrm_link_modbus::{codec, sim, Conn, Device, Modbus, ModbusDriver, Point};
use wyrm_link_sdk::driver::{Driver, DriverError, ParamSpec, Params, Tree};
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
        ("poll_s", Value::Float(0.05)),
    ];
    kv.extend_from_slice(extra);
    map(&kv)
}

fn tree(port: u16, dev: &[(&str, Value)], points: Value) -> Tree {
    conn_tree(port, &[], dev, points)
}

/// `c1/d1` like [`tree`], with connection params `conn` beside (or over)
/// host, port and a 200 ms timeout.
fn conn_tree(port: u16, conn: &[(&str, Value)], dev: &[(&str, Value)], points: Value) -> Tree {
    let mut d: Vec<(&str, Value)> = vec![("unit", Value::UInt(1)), ("ping_s", Value::Float(0.1))];
    d.extend_from_slice(dev);
    d.push(("points", points));
    let mut c: Vec<(&str, Value)> = vec![
        ("host", "127.0.0.1".into()),
        ("port", Value::UInt(port.into())),
        ("timeout_ms", Value::UInt(200)),
    ];
    for (k, v) in conn {
        c.retain(|(n, _)| n != k);
        c.push((k, v.clone()));
    }
    c.push(("devices", map(&[("d1", map(&d))])));
    Tree(map(&[("connections", map(&[("c1", map(&c))]))]))
}

/// The `status` enum leaf as a state name (`connected`, `failed`, …).
fn state(h: &H, base: &str) -> Option<String> {
    match h.ctx().last(&format!("{base}/status"))?.v {
        Value::UInt(i) => wyrm_link_sdk::driver::NodeState::NAMES
            .get(i as usize)
            .map(|s| (*s).to_owned()),
        _ => None,
    }
}

async fn wait(what: &str, mut f: impl FnMut() -> bool) {
    // Generous: the full workspace suite runs many brokers in parallel.
    let deadline = tokio::time::Instant::now() + Duration::from_secs(10);
    while !f() {
        assert!(tokio::time::Instant::now() < deadline, "timeout: {what}");
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
}

fn val(h: &H, p: &str) -> Option<Value> {
    h.ctx().last(&format!("c1/d1/{p}")).map(|s| s.v)
}

fn status(a: &wyrm_core::Attachment) -> Option<Status> {
    match a.status? {
        wyrm_core::status::StatusCode::Known(s) => Some(s),
        _ => None,
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn data_types_and_batched_reads() {
    let (addr, dev, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    {
        let mut t = dev.lock().unwrap();
        t.holding[0..2].copy_from_slice(
            &codec::encode(codec::DType::U32WSwap, &Value::UInt(70_000), 1, 1.0, 0.0).unwrap(),
        );
        t.holding[2..4].copy_from_slice(
            &codec::encode(codec::DType::F32, &Value::Float(21.5), 1, 1.0, 0.0).unwrap(),
        );
        t.holding[4] = 0x1234; // bcd16 1234
        t.holding[6..8].copy_from_slice(
            &codec::encode(codec::DType::Char, &Value::from("ABC"), 2, 1.0, 0.0).unwrap(),
        );
        t.holding[8] = 0b100; // bit 2 set
        t.input[10] = 215; // 21.5 with scale 0.1
        t.coils[3] = true;
    }
    let points = map(&[
        ("big", pt("holding", 0, "u32_wswap", &[])),
        ("temp", pt("holding", 2, "f32", &[])),
        ("bcd", pt("holding", 4, "bcd16", &[])),
        (
            "name",
            pt("holding", 6, "char", &[("regs", Value::UInt(2))]),
        ),
        (
            "flag",
            pt("holding", 8, "binary", &[("bit", Value::UInt(2))]),
        ),
        (
            "scaled",
            pt("input", 10, "u16", &[("scale", Value::Float(0.1))]),
        ),
        ("fan", pt("coil", 3, "binary", &[])),
    ]);
    let h = H::start(tree(addr.port(), &[("ping", "none".into())], points)).await;
    wait("all values", || {
        val(&h, "fan").is_some() && val(&h, "scaled").is_some() && val(&h, "big").is_some()
    })
    .await;
    assert_eq!(val(&h, "big"), Some(Value::UInt(70_000)));
    assert_eq!(val(&h, "temp"), Some(Value::Float(21.5)));
    assert_eq!(val(&h, "bcd"), Some(Value::UInt(1234)));
    assert_eq!(val(&h, "name"), Some(Value::from("ABC")));
    assert_eq!(val(&h, "flag"), Some(Value::Bool(true)));
    assert_eq!(val(&h, "scaled"), Some(Value::Float(21.5)));
    assert_eq!(val(&h, "fan"), Some(Value::Bool(true)));
    // batching: holding 0..9 is one span, input and coil one each → 3 reads per cycle
    let r0 = dev.lock().unwrap().requests;
    tokio::time::sleep(Duration::from_millis(500)).await;
    let r1 = dev.lock().unwrap().requests;
    let cycles = (r1 - r0) as f64 / 3.0;
    assert!(
        (3.0..=12.0).contains(&cycles),
        "{} requests in 0.5 s at 50 ms: not batched?",
        r1 - r0
    );
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn write_paths_and_read_back() {
    let (addr, dev, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    fn w(extra: &[(&'static str, Value)]) -> Vec<(&'static str, Value)> {
        let mut e = vec![("writable", Value::Bool(true))];
        e.extend_from_slice(extra);
        e
    }
    let points = map(&[
        ("sp", pt("holding", 10, "u16", &w(&[]))),
        ("big", pt("holding", 20, "i32", &w(&[]))),
        ("coil", pt("coil", 5, "binary", &w(&[]))),
        (
            "bit",
            pt("holding", 30, "binary", &w(&[("bit", Value::UInt(3))])),
        ),
    ]);
    let h = H::start(tree(addr.port(), &[], points)).await;
    wait("polled", || val(&h, "bit").is_some()).await;
    let tok = || Some(h.ptok(Perm::Write));
    assert_eq!(
        status(&h.set("c1/d1/sp", 42u64, tok()).await),
        Some(Status::Ok)
    );
    assert_eq!(dev.lock().unwrap().holding[10], 42);
    assert_eq!(val(&h, "sp"), Some(Value::UInt(42)), "read back");
    assert_eq!(
        status(&h.set("c1/d1/big", -70_000i64, tok()).await),
        Some(Status::Ok)
    );
    assert_eq!(val(&h, "big"), Some(Value::Int(-70_000)));
    assert_eq!(
        status(&h.set("c1/d1/coil", true, tok()).await),
        Some(Status::Ok)
    );
    assert!(dev.lock().unwrap().coils[5]);
    // FC22 mask write keeps the other bits
    dev.lock().unwrap().holding[30] = 0b1;
    assert_eq!(
        status(&h.set("c1/d1/bit", true, tok()).await),
        Some(Status::Ok)
    );
    assert_eq!(dev.lock().unwrap().holding[30], 0b1001);
    // device without FC22: read-modify-write fallback
    dev.lock().unwrap().no_fc22 = true;
    assert_eq!(
        status(&h.set("c1/d1/bit", false, tok()).await),
        Some(Status::Ok)
    );
    assert_eq!(dev.lock().unwrap().holding[30], 0b0001);
    assert_eq!(val(&h, "bit"), Some(Value::Bool(false)));
    // out of range for u16: refused, nothing written
    let att = h.set("c1/d1/sp", 70_000u64, tok()).await;
    assert_eq!(status(&att), Some(Status::InvalidParameter));
    assert_eq!(dev.lock().unwrap().holding[10], 42);
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn exception_point_and_lost_device() {
    let (addr, dev, task) = sim::spawn("127.0.0.1:0").await.unwrap();
    dev.lock().unwrap().holding[1] = 7;
    let points = map(&[
        ("ok", pt("holding", 1, "u16", &[])),
        // beyond the simulator's 1000 registers: IllegalDataAddress
        ("bad", pt("holding", 5000, "u16", &[])),
    ]);
    let h = H::start(tree(
        addr.port(),
        &[("contiguous_only", Value::Bool(true))],
        points,
    ))
    .await;
    wait("ok", || val(&h, "ok") == Some(Value::UInt(7))).await;
    wait("bad point", || {
        h.ctx()
            .last("c1/d1/bad")
            .is_some_and(|s| s.q == Quality::Bad)
    })
    .await;
    wait("device connected", || {
        state(&h, "c1/d1").as_deref() == Some("connected")
    })
    .await;
    // the device goes away
    task.abort();
    wait("ok goes bad", || {
        h.ctx()
            .last("c1/d1/ok")
            .is_some_and(|s| s.q == Quality::Bad)
    })
    .await;
    assert_eq!(val(&h, "ok"), Some(Value::UInt(7)), "value kept");
    wait("connection failed", || {
        matches!(state(&h, "c1").as_deref(), Some("failed" | "connecting"))
    })
    .await;
    let att = h.set("c1/d1/ok", 1u64, Some(h.ptok(Perm::Config))).await;
    assert_ne!(status(&att), Some(Status::Ok));
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn invalid_point_config_keeps_node() {
    let (addr, _dev, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    let points = map(&[
        ("coilnum", pt("coil", 1, "u16", &[])),
        (
            "rowrite",
            pt("input", 1, "u16", &[("writable", Value::Bool(true))]),
        ),
        ("good", pt("holding", 1, "u16", &[])),
    ]);
    let h = H::start(tree(addr.port(), &[("ping", "fc17".into())], points)).await;
    wait("good polled", || val(&h, "good").is_some()).await;
    for p in ["coilnum", "rowrite"] {
        let s = h.ctx().last(&format!("c1/d1/{p}")).expect("node kept");
        assert_eq!(s.q, Quality::Bad, "{p}");
    }
    let (_, m) = h.meta("c1/d1/coilnum").await;
    assert!(m.is_some());
    wait("fc17 ping keeps device connected", || {
        state(&h, "c1/d1").as_deref() == Some("connected")
    })
    .await;
    h.stop().await;
}

/// DSA's connection kinds: `Add IP Connection` (Modbus TCP or RTU over
/// TCP) and `Add Serial Connection`, each with its own form; the kind is
/// kept and shown; `Rescan For Serial Ports` at the root.
#[tokio::test(flavor = "multi_thread")]
async fn connection_kinds_ip_rtu_over_tcp_and_serial() {
    let (addr, dev, _task) = sim::spawn_rtu_over_tcp("127.0.0.1:0").await.unwrap();
    dev.lock().unwrap().input[1] = 215;
    let h = H::start(Tree(map(&[("connections", map(&[]))]))).await;
    let (_, root) = h.meta("").await;
    let actions = root.unwrap().actions.unwrap();
    assert_eq!(
        actions["add_ip_connection"].display.as_deref(),
        Some("Add IP Connection")
    );
    assert_eq!(
        actions["add_serial_connection"].display.as_deref(),
        Some("Add Serial Connection")
    );
    assert_eq!(
        actions["add_serial_connection"].params["serial_port"]
            .display
            .as_deref(),
        Some("Serial Port")
    );
    assert!(
        !actions.contains_key("add_connection"),
        "one action per kind"
    );
    assert_eq!(
        actions["rescan"].display.as_deref(),
        Some("Rescan For Serial Ports")
    );

    // RTU framing over TCP (a serial gateway), then a device and a point
    let add = map(&[
        ("name", "gw".into()),
        ("host", "127.0.0.1".into()),
        ("port", Value::UInt(addr.port().into())),
        ("transport", "rtu_over_tcp".into()),
        ("timeout_ms", Value::UInt(200)),
    ]);
    let r = h
        .invoke("", "add_ip_connection", add, Some(h.ptok(Perm::Config)))
        .await;
    assert_eq!(status(&r[0].att), Some(Status::Ok), "{:?}", r[0].att);
    let dev_args = map(&[
        ("name", "d1".into()),
        ("unit", Value::UInt(1)),
        ("ping", "none".into()),
    ]);
    let r = h
        .invoke("gw", "add_device", dev_args, Some(h.ptok(Perm::Config)))
        .await;
    assert_eq!(status(&r[0].att), Some(Status::Ok), "{:?}", r[0].att);
    let mut p = match pt("input", 1, "i16", &[("scale", Value::Float(0.1))]) {
        Value::Map(m) => m,
        _ => unreachable!(),
    };
    p.insert("name".into(), "temp".into());
    let r = h
        .invoke(
            "gw/d1",
            "add_point",
            Value::Map(p),
            Some(h.ptok(Perm::Config)),
        )
        .await;
    assert_eq!(status(&r[0].att), Some(Status::Ok), "{:?}", r[0].att);
    wait("value over rtu framing", || {
        h.ctx().last("gw/d1/temp").map(|s| s.v) == Some(Value::Float(21.5))
    })
    .await;
    let (_, gw) = h.meta("gw").await;
    let gw = gw.unwrap();
    assert_eq!(
        gw.cfg.as_ref().unwrap()["kind"],
        Value::from("ip_connection")
    );
    assert_eq!(
        gw.cfg.as_ref().unwrap()["transport"],
        Value::from("rtu_over_tcp")
    );
    // the edit form of an IP connection has IP fields only
    let edit = &gw.actions.as_ref().unwrap()["edit"];
    assert!(edit.params.contains_key("host") && !edit.params.contains_key("baud_rate"));

    // a serial port that does not exist: kept, Failed, the error in `error`
    // (a path that is not a serial device is refused before any open)
    let add = map(&[
        ("name", "rs485".into()),
        ("serial_port", "/dev/ttyUSB199".into()),
        ("baud_rate", Value::UInt(19_200)),
    ]);
    let r = h
        .invoke("", "add_serial_connection", add, Some(h.ptok(Perm::Config)))
        .await;
    assert_eq!(status(&r[0].att), Some(Status::Ok), "{:?}", r[0].att);
    wait("serial failed", || {
        state(&h, "rs485").as_deref() == Some("failed")
            && h.ctx()
                .last("rs485/error")
                .is_some_and(|s| matches!(&s.v, Value::Str(e) if e.contains("/dev/ttyUSB199")))
    })
    .await;
    let (_, rs) = h.meta("rs485").await;
    let rs = rs.unwrap();
    assert_eq!(
        rs.cfg.as_ref().unwrap()["kind"],
        Value::from("serial_connection")
    );
    assert!(rs.actions.as_ref().unwrap()["edit"]
        .params
        .contains_key("baud_rate"));

    // the export keeps the kinds
    let ex = h
        .invoke("", "export", map(&[]), Some(h.ptok(Perm::Config)))
        .await
        .remove(0)
        .value()
        .unwrap();
    let conns = match &ex {
        Value::Map(m) => match &m["connections"] {
            Value::Map(c) => c.clone(),
            _ => panic!(),
        },
        _ => panic!(),
    };
    let kind = |n: &str| match &conns[n] {
        Value::Map(c) => c["kind"].clone(),
        _ => Value::Null,
    };
    assert_eq!(kind("gw"), Value::from("ip_connection"));
    assert_eq!(kind("rs485"), Value::from("serial_connection"));

    // rescan replies with the ports found on this host (maybe none)
    let r = h
        .invoke("", "rescan", map(&[]), Some(h.ptok(Perm::Config)))
        .await;
    assert_eq!(status(&r[0].att), Some(Status::Ok), "{:?}", r[0].att);
    assert!(matches!(r[0].value(), Some(Value::Map(_))));
    h.stop().await;
}

/// JSON fixture value → tree value: integers stay `UInt`/`Int`, numbers
/// with a fraction or exponent are `Float` (as `to_map` writes them).
fn from_json(j: &serde_json::Value) -> Value {
    use serde_json::Value as J;
    match j {
        J::Null => Value::Null,
        J::Bool(b) => Value::Bool(*b),
        J::Number(n) => match (n.as_u64(), n.as_i64()) {
            (Some(u), _) => Value::UInt(u),
            (None, Some(i)) => Value::Int(i),
            _ => Value::Float(n.as_f64().expect("number")),
        },
        J::String(s) => Value::Str(s.clone()),
        J::Array(a) => Value::Array(a.iter().map(from_json).collect()),
        J::Object(o) => Value::Map(o.iter().map(|(k, v)| (k.clone(), from_json(v))).collect()),
    }
}

type Map = std::collections::BTreeMap<String, Value>;

/// Every stored key comes back unchanged; a key added since holds its
/// schema default (so the stored config keeps its meaning).
fn same_or_default(what: &str, stored: &Value, now: &Map, schema: &[ParamSpec]) {
    let Value::Map(stored) = stored else {
        panic!("{what}: to_map is not a map")
    };
    for (k, v) in stored {
        assert_eq!(now.get(k), Some(v), "{what}: {k}");
    }
    for (k, v) in now.iter().filter(|(k, _)| !stored.contains_key(*k)) {
        let spec = schema.iter().find(|s| s.name == k.as_str());
        assert_eq!(
            spec.and_then(|s| s.default.as_ref()),
            Some(v),
            "{what}: new param {k} must default"
        );
    }
}

/// Review Focus 1: a config stored by the code before the DSA parity plan
/// (fixture written at 195b971, never regenerated) still loads through the
/// framework's load path (`from_kind_value`: normalize, then `from_map`),
/// gives the same params back, and decodes the same register words to the
/// same values (existing data type names keep their byte order).
#[test]
fn stored_config_still_loads() {
    let doc: serde_json::Value =
        serde_json::from_str(include_str!("fixtures/config-2026-10-29.json"))
            .expect("fixture is JSON");
    let entries = |k: &str| doc[k].as_array().expect(k).clone();
    let name = |e: &serde_json::Value| e["name"].as_str().expect("name").to_owned();

    for e in entries("connections") {
        let (n, kind) = (name(&e), e["kind"].as_str().expect("kind"));
        let c = Conn::from_kind_value(kind, &from_json(&e["given"])).expect(&n);
        assert_eq!(c.kind(), kind, "{n}");
        let schema = Conn::kind_schema(kind).unwrap();
        same_or_default(&n, &from_json(&e["to_map"]), &c.to_map(), &schema);
        // the full stored map loads too (params added since take defaults)
        assert_eq!(
            Conn::from_kind_value(kind, &from_json(&e["to_map"])).expect(&n),
            c,
            "{n}: stored to_map"
        );
    }
    for e in entries("devices") {
        let n = name(&e);
        let d = Device::from_value(&from_json(&e["given"])).expect(&n);
        same_or_default(&n, &from_json(&e["to_map"]), &d.to_map(), &Device::schema());
        assert_eq!(
            Device::from_value(&from_json(&e["to_map"])).expect(&n),
            d,
            "{n}: stored to_map"
        );
    }
    let mut decoded = 0;
    for e in entries("points") {
        let n = name(&e);
        let p = Point::from_value(&from_json(&e["given"])).expect(&n);
        same_or_default(&n, &from_json(&e["to_map"]), &p.to_map(), &Point::schema());
        assert_eq!(
            Point::from_value(&from_json(&e["to_map"])).expect(&n),
            p,
            "{n}: stored to_map"
        );
        let Some(words) = e["words"].as_array() else {
            continue;
        };
        let words: Vec<u16> = words
            .iter()
            .map(|w| u16::try_from(w.as_u64().expect("word")).expect("u16"))
            .collect();
        let value = from_json(&e["value"]);
        assert_eq!(
            codec::decode(p.dtype, &words, p.bit, p.scale, p.offset),
            Ok(value.clone()),
            "{n}: decode"
        );
        if p.dtype != codec::DType::Binary {
            assert_eq!(
                codec::encode(p.dtype, &value, p.regs, p.scale, p.offset),
                Ok(words),
                "{n}: encode"
            );
        }
        decoded += 1;
    }
    // one point of every data type of 195b971 (23) plus a scaled one
    assert_eq!(decoded, 24);
}

fn point(kv: &[(&str, Value)]) -> wyrm_link_sdk::Result<Point> {
    Point::from_value(&map(kv))
}

/// Ruling 4: coil and discrete points default to `binary`; registers keep
/// `u16`; a non-binary type on a bit table stays an error.
#[test]
fn bit_tables_default_to_binary() {
    for table in ["coil", "discrete"] {
        let p = point(&[("table", table.into()), ("addr", Value::UInt(1))]).unwrap();
        assert_eq!(p.dtype, codec::DType::Binary, "{table}");
        let e = point(&[
            ("table", table.into()),
            ("addr", Value::UInt(1)),
            ("dtype", "u16".into()),
        ])
        .unwrap_err();
        assert!(e.message.starts_with("dtype:"), "{e:?}");
    }
    for table in ["holding", "input"] {
        let p = point(&[("table", table.into()), ("addr", Value::UInt(1))]).unwrap();
        assert_eq!(p.dtype, codec::DType::U16, "{table}");
    }
    let e = point(&[
        ("table", "coil".into()),
        ("addr", Value::UInt(1)),
        ("dtype", "bits16".into()),
    ])
    .unwrap_err();
    assert!(e.message.starts_with("dtype:"), "{e:?}");
}

/// Ruling 5: one FC16 write carries at most 123 registers. A longer
/// writable point still parses (a stored one must keep loading); its
/// write is refused (`stored_writable_text_beyond_one_write`).
#[test]
fn writable_points_beyond_one_write_parse() {
    let text = |regs: u64, writable: bool| {
        point(&[
            ("table", "holding".into()),
            ("addr", Value::UInt(0)),
            ("dtype", "varchar".into()),
            ("regs", Value::UInt(regs)),
            ("writable", Value::Bool(writable)),
        ])
    };
    assert!(text(124, true).is_ok());
    assert!(text(125, true).is_ok());
    assert!(text(123, true).is_ok());
    assert!(text(125, false).is_ok());
    let p = point(&[
        ("table", "holding".into()),
        ("addr", Value::UInt(0)),
        ("dtype", "bits16".into()),
        ("writable", Value::Bool(true)),
    ])
    .unwrap();
    assert_eq!(p.dtype, codec::DType::Bits16);
}

/// Ruling 2: unit ids 0…255, default 1.
#[test]
fn unit_ids_0_to_255() {
    let dev = |kv: &[(&str, Value)]| Device::from_value(&map(kv));
    assert_eq!(dev(&[]).unwrap().unit, 1);
    assert_eq!(dev(&[("unit", Value::UInt(0))]).unwrap().unit, 0);
    assert_eq!(dev(&[("unit", Value::UInt(255))]).unwrap().unit, 255);
    assert!(dev(&[("unit", Value::UInt(256))]).is_err());
}

/// A connection `c1` of `transport` with devices `(name, unit, points)`.
fn units_tree(port: u16, transport: &str, devs: &[(&str, u64, Value)]) -> Tree {
    let devices: Vec<(&str, Value)> = devs
        .iter()
        .map(|(n, unit, points)| {
            (
                *n,
                map(&[
                    ("unit", Value::UInt(*unit)),
                    ("ping_s", Value::Float(0.1)),
                    ("points", points.clone()),
                ]),
            )
        })
        .collect();
    Tree(map(&[(
        "connections",
        map(&[(
            "c1",
            map(&[
                ("host", "127.0.0.1".into()),
                ("port", Value::UInt(port.into())),
                ("transport", transport.into()),
                ("timeout_ms", Value::UInt(200)),
                ("devices", map(&devices)),
            ]),
        )]),
    )]))
}

fn writable_u16(addr: u64) -> Value {
    map(&[(
        "sp",
        pt("holding", addr, "u16", &[("writable", Value::Bool(true))]),
    )])
}

/// Ruling 2: on Modbus TCP, units 0 and 255 are ordinary units (many TCP
/// servers ignore the unit or expect 0 or 255).
#[tokio::test(flavor = "multi_thread")]
async fn tcp_units_0_and_255_read_and_write() {
    let (addr, dev, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    {
        let mut t = dev.lock().unwrap();
        t.holding[10] = 7;
        t.holding[20] = 9;
    }
    let h = H::start(units_tree(
        addr.port(),
        "tcp",
        &[("u0", 0, writable_u16(10)), ("u255", 255, writable_u16(20))],
    ))
    .await;
    let v = |p: &str| h.ctx().last(p).map(|s| s.v);
    wait("both units read", || {
        v("c1/u0/sp") == Some(Value::UInt(7)) && v("c1/u255/sp") == Some(Value::UInt(9))
    })
    .await;
    let tok = || Some(h.ptok(Perm::Write));
    assert_eq!(
        status(&h.set("c1/u0/sp", 70u64, tok()).await),
        Some(Status::Ok)
    );
    assert_eq!(
        status(&h.set("c1/u255/sp", 90u64, tok()).await),
        Some(Status::Ok)
    );
    {
        let t = dev.lock().unwrap();
        assert_eq!((t.holding[10], t.holding[20]), (70, 90));
        assert_eq!(t.units.iter().copied().collect::<Vec<u8>>(), [0, 255]);
    }
    for s in ["c1/u0", "c1/u255"] {
        wait(s, || state(&h, s).as_deref() == Some("connected")).await;
    }
    h.stop().await;
}

/// Ruling P3: tokio-modbus 0.17 always awaits a reply on RTU, so a
/// broadcast (unit 0) cannot be sent there: no request goes out for it, a
/// write is refused with `invalid_parameter`, the device fails with the
/// reason; other units on the same bus work.
#[tokio::test(flavor = "multi_thread")]
async fn rtu_unit_0_is_refused() {
    let (addr, dev, _task) = sim::spawn_rtu_over_tcp("127.0.0.1:0").await.unwrap();
    dev.lock().unwrap().holding[20] = 9;
    let h = H::start(units_tree(
        addr.port(),
        "rtu_over_tcp",
        &[("u0", 0, writable_u16(10)), ("u1", 1, writable_u16(20))],
    ))
    .await;
    wait("unit 1 read", || {
        h.ctx().last("c1/u1/sp").map(|s| s.v) == Some(Value::UInt(9))
    })
    .await;
    let att = h.set("c1/u0/sp", 70u64, Some(h.ptok(Perm::Write))).await;
    assert_eq!(status(&att), Some(Status::InvalidParameter), "{att:?}");
    assert!(
        att.err
            .as_deref()
            .is_some_and(|e| e.contains("broadcast (unit 0) is not supported on RTU")),
        "{att:?}"
    );
    wait("unit 0 failed with the reason", || {
        state(&h, "c1/u0").as_deref() == Some("failed")
            && h.ctx()
                .last("c1/u0/error")
                .is_some_and(|s| matches!(&s.v, Value::Str(e) if e.contains("broadcast (unit 0)")))
    })
    .await;
    {
        let t = dev.lock().unwrap();
        assert_eq!(t.holding[10], 0, "nothing written");
        assert_eq!(
            t.units.iter().copied().collect::<Vec<u8>>(),
            [1],
            "no unit 0 request"
        );
    }
    assert_eq!(state(&h, "c1/u1").as_deref(), Some("connected"));
    h.stop().await;
}

/// Ruling 3 end to end: a register as 16 bools (an array value, written
/// as the whole word) and a modulo-10 000 value, polled and written.
#[tokio::test(flavor = "multi_thread")]
async fn bits16_and_m10k_poll_and_write() {
    let (addr, dev, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    {
        let mut t = dev.lock().unwrap();
        t.holding[40] = 0x8005;
        t.holding[50..52].copy_from_slice(&[5678, 1234]);
    }
    let wr = [("writable", Value::Bool(true))];
    let points = map(&[
        ("flags", pt("holding", 40, "bits16", &wr)),
        ("energy", pt("holding", 50, "u32_m10k_wswap", &wr)),
    ]);
    let h = H::start(tree(addr.port(), &[("ping", "none".into())], points)).await;
    let bits =
        |set: &[usize]| Value::Array((0..16).map(|i| Value::Bool(set.contains(&i))).collect());
    wait("polled", || {
        val(&h, "flags") == Some(bits(&[0, 2, 15])) && val(&h, "energy").is_some()
    })
    .await;
    assert_eq!(val(&h, "energy"), Some(Value::UInt(12_345_678)));
    let (_, m) = h.meta("c1/d1/flags").await;
    assert_eq!(m.unwrap().ty, Some(wyrm_core::TypeCode::Array));
    let tok = || Some(h.ptok(Perm::Write));
    assert_eq!(
        status(&h.set("c1/d1/flags", bits(&[1, 3]), tok()).await),
        Some(Status::Ok)
    );
    assert_eq!(dev.lock().unwrap().holding[40], 0b1010);
    assert_eq!(val(&h, "flags"), Some(bits(&[1, 3])), "read back");
    assert_eq!(
        status(&h.set("c1/d1/energy", 87_654_321u64, tok()).await),
        Some(Status::Ok)
    );
    assert_eq!(dev.lock().unwrap().holding[50..52], [4321, 8765]);
    // 16 false bools are fine; a word of the wrong length is refused
    let att = h.set("c1/d1/flags", bits(&[]), tok()).await;
    assert_eq!(status(&att), Some(Status::Ok), "{att:?}");
    assert_eq!(dev.lock().unwrap().holding[40], 0);
    dev.lock().unwrap().holding[40] = 0xBEEF;
    let att = h
        .set(
            "c1/d1/flags",
            Value::Array(vec![Value::Bool(true); 3]),
            tok(),
        )
        .await;
    assert_eq!(status(&att), Some(Status::InvalidParameter), "{att:?}");
    assert_eq!(dev.lock().unwrap().holding[40], 0xBEEF, "nothing written");
    h.stop().await;
}

/// Review Focus 1 with ruling 5: the stored writable varchar of 125
/// registers (fixture entry written by 195b971) loads and polls; its
/// write is refused with the bound named, and nothing is written.
#[tokio::test(flavor = "multi_thread")]
async fn stored_writable_text_beyond_one_write() {
    let doc: serde_json::Value =
        serde_json::from_str(include_str!("fixtures/config-2026-10-29.json")).unwrap();
    let entry = doc["points"]
        .as_array()
        .unwrap()
        .iter()
        .find(|e| e["name"] == "holding_varchar_writable_125")
        .expect("fixture entry");
    let Value::Map(mut stored) = from_json(&entry["to_map"]) else {
        unreachable!()
    };
    stored.insert("poll_s".into(), Value::Float(0.05));
    let (addr, dev, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    dev.lock().unwrap().holding[200..202].copy_from_slice(&[0x4142, 0x4300]);
    let points = map(&[("text", Value::Map(stored))]);
    let h = H::start(tree(addr.port(), &[("ping", "none".into())], points)).await;
    wait("polled", || val(&h, "text") == Some(Value::from("ABC"))).await;
    let att = h
        .set("c1/d1/text", Value::from("XYZ"), Some(h.ptok(Perm::Write)))
        .await;
    assert_eq!(status(&att), Some(Status::InvalidParameter), "{att:?}");
    let err = att.err.as_deref().unwrap_or_default();
    assert!(err.starts_with("regs:") && err.contains("123"), "{att:?}");
    assert_eq!(dev.lock().unwrap().holding[200..202], [0x4142, 0x4300]);
    assert_eq!(val(&h, "text"), Some(Value::from("ABC")));
    h.stop().await;
}

/// Every `~val` sample published for `path`, in order.
async fn samples(h: &H, path: &str) -> std::sync::Arc<std::sync::Mutex<Vec<wyrm_core::Sample>>> {
    let seen = std::sync::Arc::new(std::sync::Mutex::new(Vec::new()));
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

/// Function codes of the writes the simulator served, with their address.
fn writes(dev: &sim::Device) -> Vec<(u8, u16)> {
    dev.lock()
        .unwrap()
        .log
        .iter()
        .filter(|(_, fc, _)| matches!(fc, 5 | 6 | 15 | 16 | 22))
        .map(|(_, fc, a)| (*fc, *a))
        .collect()
}

/// Ruling 5: `write_mode = single` writes a multi-register value as a
/// series of FC6, lowest address first (DSA "Never"); no FC16.
#[tokio::test(flavor = "multi_thread")]
async fn single_mode_writes_a_series_of_fc6() {
    let (addr, dev, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    let wr = [("writable", Value::Bool(true))];
    let points = map(&[
        ("temp", pt("holding", 60, "f32", &wr)),
        ("sp", pt("holding", 70, "u16", &wr)),
    ]);
    let h = H::start(conn_tree(
        addr.port(),
        &[("write_mode", "single".into())],
        &[("ping", "none".into())],
        points,
    ))
    .await;
    wait("polled", || {
        val(&h, "temp").is_some() && val(&h, "sp").is_some()
    })
    .await;
    let tok = || Some(h.ptok(Perm::Write));
    assert_eq!(
        status(&h.set("c1/d1/temp", 21.5, tok()).await),
        Some(Status::Ok)
    );
    assert_eq!(writes(&dev), [(6, 60), (6, 61)]);
    assert_eq!(dev.lock().unwrap().count(16), 0, "no FC16");
    assert_eq!(
        dev.lock().unwrap().holding[60..62],
        codec::encode(codec::DType::F32, &Value::Float(21.5), 1, 1.0, 0.0).unwrap()[..]
    );
    assert_eq!(val(&h, "temp"), Some(Value::Float(21.5)), "read back");
    assert_eq!(
        status(&h.set("c1/d1/sp", 7u64, tok()).await),
        Some(Status::Ok)
    );
    assert_eq!(writes(&dev), [(6, 60), (6, 61), (6, 70)]);
    h.stop().await;
}

/// Ruling 6: with `retries = 1` a request that times out is sent again;
/// the value comes in good and the quality never changes.
#[tokio::test(flavor = "multi_thread")]
async fn a_timeout_is_retried_once() {
    let (addr, dev, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    {
        let mut t = dev.lock().unwrap();
        t.holding[70] = 5;
        t.drop_next = Some((1, 70, 1));
    }
    // One poll only (60 s), no ping: the request counts are exact.
    let points = map(&[(
        "v",
        pt("holding", 70, "u16", &[("poll_s", Value::Float(60.0))]),
    )]);
    let h = H::start(conn_tree(
        addr.port(),
        &[("retries", Value::UInt(1))],
        &[("ping", "none".into())],
        points,
    ))
    .await;
    let seen = samples(&h, "c1/d1/v").await;
    wait("value after one retry", || {
        val(&h, "v") == Some(Value::UInt(5))
    })
    .await;
    tokio::time::sleep(Duration::from_millis(300)).await;
    {
        let t = dev.lock().unwrap();
        assert_eq!(t.dropped, 1);
        assert_eq!(t.log.iter().filter(|r| **r == (1, 3, 70)).count(), 2);
    }
    assert_eq!(h.ctx().last("c1/d1/v").map(|s| s.q), Some(Quality::Good));
    assert!(
        seen.lock().unwrap().iter().all(|s| s.q == Quality::Good),
        "{:?}",
        seen.lock().unwrap()
    );
    assert_eq!(state(&h, "c1/d1").as_deref(), Some("connected"));
    // ruling P8: the retry goes out on a reopened connection
    assert_eq!(dev.lock().unwrap().connections, 2, "one reopen");
    h.stop().await;
}

/// Ruling 6: an exception reply is an answer, not a miss: never retried
/// (neither a read nor a write).
#[tokio::test(flavor = "multi_thread")]
async fn an_exception_is_not_retried() {
    let (addr, dev, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    let points = map(&[(
        "bad",
        // beyond the simulator's 1000 registers: IllegalDataAddress
        pt(
            "holding",
            2000,
            "u16",
            &[
                ("poll_s", Value::Float(60.0)),
                ("writable", Value::Bool(true)),
            ],
        ),
    )]);
    let h = H::start(conn_tree(
        addr.port(),
        &[("retries", Value::UInt(1))],
        &[("ping", "none".into())],
        points,
    ))
    .await;
    wait("bad point", || {
        h.ctx()
            .last("c1/d1/bad")
            .is_some_and(|s| s.q == Quality::Bad)
    })
    .await;
    assert_eq!(
        dev.lock()
            .unwrap()
            .log
            .iter()
            .filter(|r| **r == (1, 3, 2000))
            .count(),
        1,
        "the exception read is not retried"
    );
    let att = h.set("c1/d1/bad", 1u64, Some(h.ptok(Perm::Write))).await;
    assert_eq!(status(&att), Some(Status::InvalidParameter), "{att:?}");
    tokio::time::sleep(Duration::from_millis(500)).await;
    let t = dev.lock().unwrap();
    // one read at start, one write, one read-back (ruling P7); none retried
    assert_eq!(t.log.iter().filter(|r| **r == (1, 3, 2000)).count(), 2);
    assert_eq!(t.log.iter().filter(|r| **r == (1, 6, 2000)).count(), 1);
}

/// Review Focus 2, ruling 7: on RTU (here over TCP) unit 2 answers 300 ms
/// late with a 200 ms timeout. The next read of unit 2 (another address,
/// same function code and length, so tokio-modbus would take the late
/// reply) and the read of unit 3 return their own values: the driver
/// reopens the transport once, and not again without a request.
#[tokio::test(flavor = "multi_thread")]
async fn a_late_reply_is_not_taken() {
    let (addr, dev, _task) = sim::spawn_rtu_over_tcp("127.0.0.1:0").await.unwrap();
    {
        let mut t = dev.lock().unwrap();
        t.holding[10] = 1010;
        t.holding[20] = 2020;
        t.holding[30] = 3030;
        t.delay_once = Some((2, 10, Duration::from_millis(300)));
    }
    let once = |a: u64| pt("holding", a, "u16", &[("poll_s", Value::Float(60.0))]);
    let dev_of = |unit: u64, points: Value| {
        map(&[
            ("unit", Value::UInt(unit)),
            ("ping", "none".into()),
            // a and b in separate requests
            ("contiguous_only", Value::Bool(true)),
            ("points", points),
        ])
    };
    let h = H::start(Tree(map(&[(
        "connections",
        map(&[(
            "c1",
            map(&[
                ("host", "127.0.0.1".into()),
                ("port", Value::UInt(addr.port().into())),
                ("transport", "rtu_over_tcp".into()),
                ("timeout_ms", Value::UInt(200)),
                (
                    "devices",
                    map(&[
                        ("u2", dev_of(2, map(&[("a", once(10)), ("b", once(20))]))),
                        ("u3", dev_of(3, map(&[("c", once(30))]))),
                    ]),
                ),
            ]),
        )]),
    )])))
    .await;
    let (seen_b, seen_c) = (samples(&h, "c1/u2/b").await, samples(&h, "c1/u3/c").await);
    let v = |p: &str| h.ctx().last(p).map(|s| s.v);
    wait("b and c read", || {
        v("c1/u2/b").is_some() && v("c1/u3/c").is_some()
    })
    .await;
    tokio::time::sleep(Duration::from_millis(500)).await;
    assert_eq!(v("c1/u2/b"), Some(Value::UInt(2020)));
    assert_eq!(v("c1/u3/c"), Some(Value::UInt(3030)));
    for (p, seen) in [("b", &seen_b), ("c", &seen_c)] {
        let seen = seen.lock().unwrap();
        assert!(
            seen.iter().all(|s| s.v != Value::UInt(1010)),
            "{p} took the late reply: {seen:?}"
        );
    }
    assert!(v("c1/u2/a").is_none(), "a timed out");
    assert_eq!(dev.lock().unwrap().connections, 2, "exactly one reopen");
    h.stop().await;
}

/// Ruling 8: the poll's whole-operation bound grows with the plan. Ten
/// spans with 100 ms latency each (timeout 200, no retries) take about
/// 1000 ms: more than the default bound (`io_timeout` = 4 × 200 ms), within
/// `poll_timeout` = 200 × 10 + 1000 ms.
#[tokio::test(flavor = "multi_thread")]
async fn poll_bound_grows_with_spans() {
    let (addr, dev, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    {
        let mut t = dev.lock().unwrap();
        for i in 0..10 {
            t.holding[i * 2] = 100 + i as u16;
        }
        t.latency = Duration::from_millis(100);
    }
    let point = |i: u64| pt("holding", i * 2, "u16", &[("poll_s", Value::Float(60.0))]);
    let device = [
        ("ping", "none".into()),
        ("contiguous_only", Value::Bool(true)),
    ];
    // The bounds, and that one poll really takes longer than the default.
    let conn = Conn::from_kind_value(
        "ip_connection",
        &map(&[
            ("host", "127.0.0.1".into()),
            ("port", Value::UInt(addr.port().into())),
            ("timeout_ms", Value::UInt(200)),
        ]),
    )
    .unwrap();
    let d = Device::from_value(&map(&device)).unwrap();
    let members: Vec<(String, Point)> = (0..10u64)
        .map(|i| (format!("p{i}"), Point::from_value(&point(i)).unwrap()))
        .collect();
    let plan = ModbusDriver::plan(&d, &members);
    let default_bound = ModbusDriver::io_timeout(&conn);
    assert_eq!(default_bound, Duration::from_millis(800));
    assert_eq!(
        ModbusDriver::poll_timeout(&conn, &plan),
        Duration::from_millis(3000)
    );
    let mut t = ModbusDriver::open(&conn).await.unwrap();
    let t0 = tokio::time::Instant::now();
    let r = ModbusDriver::poll(&mut t, &d, &plan).await;
    let took = t0.elapsed();
    assert!(r.iter().all(|(_, v)| v.is_ok()), "{r:?}");
    assert!(
        took > default_bound,
        "the default bound would not cut {took:?}"
    );
    drop(t);
    // Through the framework: the poll is not cut.
    let points = Value::Map((0..10u64).map(|i| (format!("p{i}"), point(i))).collect());
    let h = H::start(conn_tree(addr.port(), &[], &device, points)).await;
    wait("all ten spans", || {
        (0..10).all(|i| val(&h, &format!("p{i}")).is_some())
    })
    .await;
    for i in 0..10u64 {
        assert_eq!(
            val(&h, &format!("p{i}")),
            Some(Value::UInt(100 + i)),
            "p{i}"
        );
    }
    assert_eq!(state(&h, "c1/d1").as_deref(), Some("connected"));
    h.stop().await;
}

/// Review Focus 2 across units, in a fixed order (driver calls, no
/// tickers): a dead unit 2 on an RTU bus does not poison unit 3. Unit 3's
/// read right after unit 2's timeout gets its own reply on a reopened
/// transport; without the reopen it would get unit 2's late reply (a
/// header mismatch, and the connection dropped).
#[tokio::test(flavor = "multi_thread")]
async fn a_late_reply_does_not_reach_another_unit() {
    let (addr, dev, _task) = sim::spawn_rtu_over_tcp("127.0.0.1:0").await.unwrap();
    {
        let mut t = dev.lock().unwrap();
        t.holding[10] = 1010;
        t.holding[30] = 3030;
        t.delay_once = Some((2, 10, Duration::from_millis(300)));
    }
    let conn = Conn::from_kind_value(
        "ip_connection",
        &map(&[
            ("host", "127.0.0.1".into()),
            ("port", Value::UInt(addr.port().into())),
            ("transport", "rtu_over_tcp".into()),
            ("timeout_ms", Value::UInt(200)),
        ]),
    )
    .unwrap();
    let unit = |u: u64| Device::from_value(&map(&[("unit", Value::UInt(u))])).unwrap();
    let plan = |d: &Device, a: u64| {
        let p = Point::from_value(&pt("holding", a, "u16", &[])).unwrap();
        ModbusDriver::plan(d, &[("p".to_owned(), p)])
    };
    let (u2, u3) = (unit(2), unit(3));
    let mut t = ModbusDriver::open(&conn).await.unwrap();
    let r = ModbusDriver::poll(&mut t, &u2, &plan(&u2, 10)).await;
    assert!(matches!(r[..], [(_, Err(DriverError::Device(_)))]), "{r:?}");
    let r = ModbusDriver::poll(&mut t, &u3, &plan(&u3, 30)).await;
    assert_eq!(r, [("p".to_owned(), Ok(Value::UInt(3030)))]);
    // the late reply has gone out on the closed transport by now
    tokio::time::sleep(Duration::from_millis(300)).await;
    let r = ModbusDriver::poll(&mut t, &u3, &plan(&u3, 30)).await;
    assert_eq!(r, [("p".to_owned(), Ok(Value::UInt(3030)))]);
    assert_eq!(dev.lock().unwrap().connections, 2, "exactly one reopen");
}

/// The `status` values (state indexes) published for `base`.
async fn states(h: &H, base: &str) -> std::sync::Arc<std::sync::Mutex<Vec<String>>> {
    let seen = std::sync::Arc::new(std::sync::Mutex::new(Vec::new()));
    let s = seen.clone();
    h.session()
        .declare_subscriber(h.key(&format!("{base}/status"), "~val"))
        .callback(move |sample| {
            if let Ok(wyrm_core::Sample {
                v: Value::UInt(i), ..
            }) = wyrm_core::codec::from_slice(&sample.payload().to_bytes())
            {
                if let Some(n) = wyrm_link_sdk::driver::NodeState::NAMES.get(i as usize) {
                    s.lock().unwrap().push((*n).to_owned());
                }
            }
        })
        .background()
        .await
        .expect("subscriber");
    seen
}

/// Ruling P7: after a failed write the framework reads the point back. A
/// single-mode series that fails on its second word shows the first
/// word's change at once (the device's real state), not the old value.
#[tokio::test(flavor = "multi_thread")]
async fn a_partial_series_shows_the_real_state() {
    let (addr, dev, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    let f32_words =
        |x: f64| codec::encode(codec::DType::F32, &Value::Float(x), 1, 1.0, 0.0).unwrap();
    dev.lock().unwrap().holding[60..62].copy_from_slice(&f32_words(1.0));
    let points = map(&[(
        "temp",
        pt(
            "holding",
            60,
            "f32",
            &[
                ("writable", Value::Bool(true)),
                ("poll_s", Value::Float(60.0)),
            ],
        ),
    )]);
    let h = H::start(conn_tree(
        addr.port(),
        &[("write_mode", "single".into())],
        &[("ping", "none".into())],
        points,
    ))
    .await;
    wait("polled", || val(&h, "temp") == Some(Value::Float(1.0))).await;
    dev.lock().unwrap().except_once = Some((1, 61, tokio_modbus::ExceptionCode::IllegalDataValue));
    let att = h.set("c1/d1/temp", 21.5, Some(h.ptok(Perm::Write))).await;
    assert_eq!(status(&att), Some(Status::InvalidParameter), "{att:?}");
    assert!(
        att.err
            .as_deref()
            .is_some_and(|e| e.contains("after 1 of 2")),
        "{att:?}"
    );
    let real = [f32_words(21.5)[0], f32_words(1.0)[1]];
    assert_eq!(dev.lock().unwrap().holding[60..62], real);
    // read back before the reply: the tree already shows the device
    assert_eq!(
        val(&h, "temp"),
        Some(codec::decode(codec::DType::F32, &real, 0, 1.0, 0.0).unwrap())
    );
    h.stop().await;
}

/// Ruling P8: on Modbus TCP a timeout reopens the connection too. With
/// `retries = 1` and a reply 300 ms late (timeout 200), the retry goes out
/// on a fresh connection and gets its own reply: no header mismatch, no
/// framework reconnect, no backoff.
#[tokio::test(flavor = "multi_thread")]
async fn tcp_retry_goes_out_on_a_fresh_connection() {
    let (addr, dev, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    {
        let mut t = dev.lock().unwrap();
        t.holding[70] = 5;
        t.holding[80] = 8;
        t.delay_once = Some((1, 70, Duration::from_millis(300)));
    }
    let once = |a: u64| pt("holding", a, "u16", &[("poll_s", Value::Float(60.0))]);
    let points = map(&[("a", once(70)), ("b", once(80))]);
    let h = H::start(conn_tree(
        addr.port(),
        &[("retries", Value::UInt(1))],
        &[
            ("ping", "none".into()),
            ("contiguous_only", Value::Bool(true)),
        ],
        points,
    ))
    .await;
    let seen = states(&h, "c1").await;
    let t0 = tokio::time::Instant::now();
    wait("both values", || {
        val(&h, "a") == Some(Value::UInt(5)) && val(&h, "b") == Some(Value::UInt(8))
    })
    .await;
    // one timeout (200 ms) and the retry; a reconnect would add ≥ 1 s backoff
    assert!(
        t0.elapsed() < Duration::from_millis(900),
        "{:?}",
        t0.elapsed()
    );
    tokio::time::sleep(Duration::from_millis(400)).await;
    assert!(
        !seen.lock().unwrap().iter().any(|s| s == "failed"),
        "{:?}",
        seen.lock().unwrap()
    );
    assert_eq!(state(&h, "c1").as_deref(), Some("connected"));
    assert_eq!(dev.lock().unwrap().connections, 2, "one reopen");
    h.stop().await;
}

/// Ruling P9: the write bound grows with the FC6 series (`timeout × (1 +
/// retries) × words + 1 s`). An `f64` (4 × FC6) and a 16-character
/// varchar (8 × FC6) written in single mode to a device answering each
/// request after 150 ms (timeout 200) are not cut. The varchar takes
/// 1200 ms, more than the old bound of 4 × 200 ms.
#[tokio::test(flavor = "multi_thread")]
async fn a_slow_series_write_is_not_cut() {
    let (addr, dev, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    let wr = |dtype: &str, a: u64, regs: u64| {
        pt(
            "holding",
            a,
            dtype,
            &[
                ("writable", Value::Bool(true)),
                ("regs", Value::UInt(regs)),
                ("poll_s", Value::Float(60.0)),
            ],
        )
    };
    let points = map(&[("big", wr("f64", 100, 1)), ("text", wr("varchar", 200, 8))]);
    let h = H::start(conn_tree(
        addr.port(),
        &[("write_mode", "single".into())],
        &[("ping", "none".into())],
        points,
    ))
    .await;
    wait("polled", || {
        val(&h, "big").is_some() && val(&h, "text").is_some()
    })
    .await;
    dev.lock().unwrap().latency = Duration::from_millis(150);
    let tok = || Some(h.ptok(Perm::Write));
    let att = h.set("c1/d1/big", 1234.5, tok()).await;
    assert_eq!(status(&att), Some(Status::Ok), "{att:?}");
    assert_eq!(val(&h, "big"), Some(Value::Float(1234.5)));
    let text = "ABCDEFGHIJKLMNOP";
    let att = h.set("c1/d1/text", Value::from(text), tok()).await;
    assert_eq!(status(&att), Some(Status::Ok), "{att:?}");
    assert_eq!(val(&h, "text"), Some(Value::from(text)));
    assert_eq!(dev.lock().unwrap().count(6), 12);
    assert_eq!(dev.lock().unwrap().count(16), 0);
    h.stop().await;
}

/// Ruling 12 and P1: every request is counted for its device and
/// connection (a retry too), by outcome, with its round trip; `reopens`
/// counts the reopens after a timeout. Values come at once on a read.
#[tokio::test(flavor = "multi_thread")]
async fn diagnostics_count_requests_and_reopens() {
    let (addr, dev, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    {
        let mut t = dev.lock().unwrap();
        t.holding[70] = 5;
        t.drop_next = Some((1, 70, 1));
    }
    // One poll (60 s), no ping: a timeout and its retry at 70, then an
    // exception at 2000 (beyond the simulator's registers).
    let once = [("poll_s", Value::Float(60.0))];
    let points = map(&[
        ("v", pt("holding", 70, "u16", &once)),
        ("bad", pt("holding", 2000, "u16", &once)),
    ]);
    let h = H::start(conn_tree(
        addr.port(),
        &[("retries", Value::UInt(1))],
        &[("ping", "none".into())],
        points,
    ))
    .await;
    wait("polled", || {
        val(&h, "v") == Some(Value::UInt(5))
            && h.ctx()
                .last("c1/d1/bad")
                .is_some_and(|s| s.q == Quality::Bad)
    })
    .await;
    let n = |p: &str| h.ctx().last(p).map(|s| s.v);
    for node in ["c1/d1", "c1"] {
        h.meta(node).await;
        wait("published on a read", || {
            n(&format!("{node}/requests")) == Some(Value::UInt(3))
        })
        .await;
        // a flush publishes the leaves in order; `avg_rtt_ms` comes last
        wait(
            "all leaves",
            || matches!(n(&format!("{node}/avg_rtt_ms")), Some(Value::Float(f)) if f > 0.0),
        )
        .await;
        for (leaf, want) in [
            ("timeouts", 1),
            ("exceptions", 1),
            ("errors", 0),
            ("reopens", 1),
        ] {
            assert_eq!(
                n(&format!("{node}/{leaf}")),
                Some(Value::UInt(want)),
                "{node}/{leaf}"
            );
        }
        let Some(Value::Float(last)) = n(&format!("{node}/last_rtt_ms")) else {
            panic!("{node}/last_rtt_ms");
        };
        assert!(last > 0.0 && last < 200.0, "{node}: last_rtt_ms {last}");
    }
    assert_eq!(
        dev.lock().unwrap().connections,
        2,
        "reopens = connections - 1"
    );
    h.stop().await;
}

/// Invoke `action` on `path` with a token of `perm`: the reply's status,
/// its value and its error message.
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
    let msg = r
        .att
        .err
        .as_ref()
        .map(|e| format!("{e:?}"))
        .unwrap_or_default();
    (status(&r.att), r.value(), msg)
}

fn field<'a>(v: &'a Option<Value>, k: &str) -> &'a Value {
    match v {
        Some(Value::Map(m)) => m.get(k).unwrap_or_else(|| panic!("no {k} in {m:?}")),
        other => panic!("not a map: {other:?}"),
    }
}

/// A link on the simulator with `c1/d1` (unit 1, no ping) and no points.
async fn bare(port: u16, conn: &[(&str, Value)]) -> H {
    let h = H::start(conn_tree(port, conn, &[("ping", "none".into())], map(&[]))).await;
    wait("connected", || {
        state(&h, "c1").as_deref() == Some("connected")
    })
    .await;
    h
}

/// Ruling 13: `read_registers` and `read_device_id` on a device at level
/// read, `scan_units` on a connection at level config.
#[tokio::test(flavor = "multi_thread")]
async fn commissioning_action_levels() {
    let (addr, _dev, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    let h = bare(addr.port(), &[]).await;
    let (_, dev) = h.meta("c1/d1").await;
    let acts = dev.unwrap().actions.unwrap();
    assert_eq!(acts["read_registers"].level, Some(Perm::Read));
    assert_eq!(acts["read_device_id"].level, Some(Perm::Read));
    assert!(acts["read_registers"].timeout_ms.is_some());
    assert!(acts["read_device_id"].timeout_ms.is_some());
    let (_, conn) = h.meta("c1").await;
    let acts = conn.unwrap().actions.unwrap();
    assert_eq!(acts["scan_units"].level, Some(Perm::Config));
    // 247 units at 200 ms with a reopen after each silent one
    assert!(acts["scan_units"].timeout_ms.unwrap() >= 247 * 250);
    let (s, _, _) = act(&h, "c1", "scan_units", map(&[]), Perm::Read).await;
    assert_eq!(s, Some(Status::PermissionDenied));
    let (s, _, _) = act(&h, "c1", "scan_units", map(&[]), Perm::Write).await;
    assert_eq!(s, Some(Status::PermissionDenied));
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn read_registers_returns_words_and_value() {
    let (addr, dev, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    let words = codec::encode(codec::DType::F32, &Value::Float(21.5), 1, 1.0, 0.0).unwrap();
    {
        let mut t = dev.lock().unwrap();
        t.holding[10..12].copy_from_slice(&words);
        t.input[3] = 7;
        t.input[4] = 0x00FA; // not BCD
        t.coils[5] = true;
    }
    let h = bare(addr.port(), &[]).await;
    let args = |kv: &[(&str, Value)]| map(kv);
    let (s, v, m) = act(
        &h,
        "c1/d1",
        "read_registers",
        args(&[
            ("table", "holding".into()),
            ("addr", Value::UInt(10)),
            ("count", Value::UInt(2)),
            ("dtype", "f32".into()),
        ]),
        Perm::Read,
    )
    .await;
    assert_eq!(s, Some(Status::Ok), "{m}");
    let want: Vec<Value> = words.iter().map(|w| Value::UInt((*w).into())).collect();
    assert_eq!(field(&v, "words"), &Value::Array(want));
    assert_eq!(field(&v, "value"), &Value::Float(21.5));
    // no dtype: words only; count defaults to 1
    let (s, v, m) = act(
        &h,
        "c1/d1",
        "read_registers",
        args(&[("table", "input".into()), ("addr", Value::UInt(3))]),
        Perm::Read,
    )
    .await;
    assert_eq!(s, Some(Status::Ok), "{m}");
    assert_eq!(field(&v, "words"), &Value::Array(vec![Value::UInt(7)]));
    let Some(Value::Map(m)) = &v else { panic!() };
    assert!(!m.contains_key("value"));
    // words that do not decode as the dtype: the words and why
    let (s, v, m) = act(
        &h,
        "c1/d1",
        "read_registers",
        args(&[
            ("table", "input".into()),
            ("addr", Value::UInt(4)),
            ("dtype", "bcd16".into()),
        ]),
        Perm::Read,
    )
    .await;
    assert_eq!(s, Some(Status::Ok), "{m}");
    assert_eq!(field(&v, "words"), &Value::Array(vec![Value::UInt(0xFA)]));
    assert!(matches!(field(&v, "error"), Value::Str(_)), "{v:?}");
    // bit tables answer bits
    let (s, v, m) = act(
        &h,
        "c1/d1",
        "read_registers",
        args(&[
            ("table", "coil".into()),
            ("addr", Value::UInt(4)),
            ("count", Value::UInt(3)),
        ]),
        Perm::Read,
    )
    .await;
    assert_eq!(s, Some(Status::Ok), "{m}");
    assert_eq!(
        field(&v, "bits"),
        &Value::Array(vec![
            Value::Bool(false),
            Value::Bool(true),
            Value::Bool(false)
        ])
    );
    // an address the device lacks: its exception
    let (s, _, m) = act(
        &h,
        "c1/d1",
        "read_registers",
        args(&[("table", "holding".into()), ("addr", Value::UInt(2000))]),
        Perm::Read,
    )
    .await;
    assert_eq!(s, Some(Status::InvalidParameter), "{m}");
    assert!(m.contains("IllegalDataAddress"), "{m}");
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn read_registers_bounds() {
    let (addr, dev, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    let h = bare(addr.port(), &[]).await;
    let before = dev.lock().unwrap().requests;
    for (kv, why) in [
        (
            vec![("table", "holding".into()), ("count", Value::UInt(126))],
            "count",
        ),
        (
            vec![("table", "holding".into()), ("count", Value::UInt(0))],
            "count",
        ),
        (
            vec![("table", "holding".into()), ("count", Value::Float(1.5))],
            "count",
        ),
        (
            vec![
                ("table", "holding".into()),
                ("addr", Value::UInt(65_535)),
                ("count", Value::UInt(2)),
            ],
            "addr",
        ),
        (
            vec![
                ("table", "holding".into()),
                ("count", Value::UInt(1)),
                ("dtype", "f32".into()),
            ],
            "dtype",
        ),
        (
            vec![("table", "coil".into()), ("dtype", "u16".into())],
            "dtype",
        ),
        (vec![("addr", Value::UInt(1))], "table"),
    ] {
        let mut kv = kv;
        if !kv.iter().any(|(k, _)| *k == "addr") {
            kv.push(("addr", Value::UInt(0)));
        }
        let (s, _, m) = act(&h, "c1/d1", "read_registers", map(&kv), Perm::Read).await;
        assert_eq!(s, Some(Status::InvalidParameter), "{kv:?}: {m}");
        assert!(m.contains(why), "{kv:?}: {m}");
    }
    assert_eq!(
        dev.lock().unwrap().requests,
        before,
        "refused before any request"
    );
    // 125 is the limit
    let (s, v, m) = act(
        &h,
        "c1/d1",
        "read_registers",
        map(&[
            ("table", "holding".into()),
            ("addr", Value::UInt(0)),
            ("count", Value::UInt(125)),
        ]),
        Perm::Read,
    )
    .await;
    assert_eq!(s, Some(Status::Ok), "{m}");
    let Value::Array(w) = field(&v, "words") else {
        panic!()
    };
    assert_eq!(w.len(), 125);
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn read_device_id_returns_objects() {
    let (addr, dev, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    // two objects per reply: the driver follows `more follows`
    dev.lock().unwrap().id_per_reply = 2;
    let h = bare(addr.port(), &[]).await;
    let (s, v, m) = act(&h, "c1/d1", "read_device_id", map(&[]), Perm::Read).await;
    assert_eq!(s, Some(Status::Ok), "{m}");
    for (k, want) in [
        ("vendor_name", "WYRM"),
        ("product_code", "WYRM-SIM"),
        ("revision", "1.0"),
        ("vendor_url", "https://wyrm.invalid"),
        ("product_name", "Modbus Simulator"),
        ("model_name", "SIM-1000"),
    ] {
        assert_eq!(field(&v, k), &Value::from(want), "{k}");
    }
    let Some(Value::Map(m)) = &v else { panic!() };
    assert!(!m.contains_key("user_application_name"));
    let fc43 = dev.lock().unwrap().count(0x2B);
    assert!(
        fc43 >= 3,
        "{fc43} FC43 requests: continuation not followed?"
    );
    // a device without FC43
    dev.lock().unwrap().no_fc43 = true;
    let (s, _, m) = act(&h, "c1/d1", "read_device_id", map(&[]), Perm::Read).await;
    assert_eq!(s, Some(Status::NotSupported), "{m}");
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn scan_units_finds_answering_units() {
    let (addr, dev, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    dev.lock().unwrap().answer_units = Some([1, 7].into());
    let h = bare(addr.port(), &[]).await;
    let t0 = std::time::Instant::now();
    let (s, v, m) = act(
        &h,
        "c1",
        "scan_units",
        map(&[
            ("from", Value::UInt(1)),
            ("to", Value::UInt(8)),
            ("timeout_ms", Value::UInt(100)),
        ]),
        Perm::Config,
    )
    .await;
    assert_eq!(s, Some(Status::Ok), "{m}");
    assert_eq!(v, Some(Value::Array(vec![Value::UInt(1), Value::UInt(7)])));
    // six silent units at 100 ms each, not at the connection's 200 ms
    let took = t0.elapsed();
    assert!(took < Duration::from_millis(1100), "{took:?}");
    {
        let t = dev.lock().unwrap();
        let probed: Vec<u8> = t.log.iter().map(|(u, _, _)| *u).collect();
        assert_eq!(probed, (1..=8).collect::<Vec<u8>>(), "one probe per unit");
    }
    // a gateway's "target did not respond" is no answer; another exception is
    {
        let mut t = dev.lock().unwrap();
        t.answer_units = None;
        t.except_once = Some((2, 0, tokio_modbus::ExceptionCode::GatewayTargetDevice));
    }
    let (s, v, m) = act(
        &h,
        "c1",
        "scan_units",
        map(&[("from", Value::UInt(1)), ("to", Value::UInt(3))]),
        Perm::Config,
    )
    .await;
    assert_eq!(s, Some(Status::Ok), "{m}");
    assert_eq!(v, Some(Value::Array(vec![Value::UInt(1), Value::UInt(3)])));
    dev.lock().unwrap().except_once = Some((3, 0, tokio_modbus::ExceptionCode::IllegalDataAddress));
    let (_, v, _) = act(
        &h,
        "c1",
        "scan_units",
        map(&[("from", Value::UInt(3)), ("to", Value::UInt(3))]),
        Perm::Config,
    )
    .await;
    assert_eq!(v, Some(Value::Array(vec![Value::UInt(3)])));
    // the default range at 200 ms fits the action's bound; at 1000 ms it does not
    let (s, _, m) = act(
        &h,
        "c1",
        "scan_units",
        map(&[("timeout_ms", Value::UInt(1000))]),
        Perm::Config,
    )
    .await;
    assert_eq!(s, Some(Status::InvalidParameter), "{m}");
    assert!(m.contains("smaller range"), "{m}");
    // bad ranges
    for kv in [
        vec![("from", Value::UInt(9)), ("to", Value::UInt(8))],
        vec![("from", Value::UInt(1)), ("to", Value::UInt(256))],
        vec![("timeout_ms", Value::UInt(5))],
    ] {
        let (s, _, m) = act(&h, "c1", "scan_units", map(&kv), Perm::Config).await;
        assert_eq!(s, Some(Status::InvalidParameter), "{kv:?}: {m}");
    }
    h.stop().await;
}

/// P12: while a scan holds the owner, actions queue up to the owner
/// queue's depth (256); the rest are answered `busy` at once, and the link
/// keeps answering.
#[tokio::test(flavor = "multi_thread")]
async fn a_full_owner_queue_answers_busy() {
    let (addr, dev, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    dev.lock().unwrap().answer_units = Some([1].into());
    // Off: the per-caller rate limit would answer first.
    let h = H::start_with(
        conn_tree(addr.port(), &[], &[("ping", "none".into())], map(&[])),
        |c| c.rate_limit = None,
    )
    .await;
    wait("connected", || {
        state(&h, "c1").as_deref() == Some("connected")
    })
    .await;
    let h = std::sync::Arc::new(h);
    // about 3 s of silent units
    let scan = {
        let h = h.clone();
        tokio::spawn(async move {
            let args = map(&[
                ("from", Value::UInt(2)),
                ("to", Value::UInt(31)),
                ("timeout_ms", Value::UInt(100)),
            ]);
            act(&h, "c1", "scan_units", args, Perm::Config).await
        })
    };
    wait("scan running", || dev.lock().unwrap().dropped > 0).await;
    let mut reads = tokio::task::JoinSet::new();
    for _ in 0..300 {
        let h = h.clone();
        reads.spawn(async move {
            let args = map(&[("table", "holding".into()), ("addr", Value::UInt(0))]);
            act(&h, "c1/d1", "read_registers", args, Perm::Read).await
        });
        // Let the link task take each one (its own queue is 256 deep too).
        tokio::task::yield_now().await;
    }
    let (mut ok, mut busy) = (0, 0);
    while let Some(r) = reads.join_next().await {
        let (s, _, m) = r.unwrap();
        match s {
            Some(Status::Ok) => ok += 1,
            Some(Status::Busy) if m.contains("connection busy") => busy += 1,
            other => panic!("{other:?}: {m}"),
        }
    }
    assert!(busy > 0, "no busy answer");
    assert!(ok >= 200, "{ok} reads answered");
    let (s, v, m) = scan.await.unwrap();
    assert_eq!(s, Some(Status::Ok), "{m}");
    assert_eq!(v, Some(Value::Array(vec![])));
    std::sync::Arc::try_unwrap(h).ok().unwrap().stop().await;
}
