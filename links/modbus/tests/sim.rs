//! The modbus framework driver against the in-process simulator.

use std::time::Duration;
use wyrm_core::{Perm, Quality, Status, Value};
use wyrm_link_modbus::{codec, sim, Modbus};
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
        ("poll_s", Value::Float(0.05)),
    ];
    kv.extend_from_slice(extra);
    map(&kv)
}

fn tree(port: u16, dev: &[(&str, Value)], points: Value) -> Tree {
    let mut d: Vec<(&str, Value)> = vec![("unit", Value::UInt(1)), ("ping_s", Value::Float(0.1))];
    d.extend_from_slice(dev);
    d.push(("points", points));
    Tree(map(&[
        ("poll_unsubscribed", Value::Bool(true)),
        (
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
        ),
    ]))
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
