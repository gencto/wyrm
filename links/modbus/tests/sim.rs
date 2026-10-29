//! The modbus framework driver against the in-process simulator.

use std::time::Duration;
use wyrm_core::{Perm, Quality, Status, Value};
use wyrm_link_modbus::{codec, sim, Conn, Device, Modbus, Point};
use wyrm_link_sdk::driver::{ParamSpec, Params, Tree};
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
    let mut d: Vec<(&str, Value)> = vec![("unit", Value::UInt(1)), ("ping_s", Value::Float(0.1))];
    d.extend_from_slice(dev);
    d.push(("points", points));
    Tree(map(&[(
        "connections",
        map(&[(
            "c1",
            map(&[
                ("host", "127.0.0.1".into()),
                ("port", Value::UInt(port.into())),
                ("timeout_ms", Value::UInt(200)),
                ("devices", map(&[("d1", map(&d))])),
            ]),
        )]),
    )]))
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
