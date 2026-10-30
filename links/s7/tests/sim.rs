//! The `s7` driver against its in-process PLC simulator, through the real
//! wire format (`TestHarness`: in-memory Zenoh session, no network).

use std::sync::{Arc, Mutex};
use std::time::Duration;
use wyrm_core::{Perm, Quality, Sample, Status, Value};
use wyrm_link_s7::{sim, Conn, Dev, Point, S7};
use wyrm_link_sdk::driver::{NodeState, Params, Tree};
use wyrm_link_sdk::TestHarness;

type H = TestHarness<S7>;

fn map(kv: &[(&str, Value)]) -> Value {
    Value::Map(
        kv.iter()
            .map(|(k, v)| ((*k).to_owned(), v.clone()))
            .collect(),
    )
}

/// A point at `address`, polled every 50 ms.
fn pt(address: &str, extra: &[(&str, Value)]) -> Value {
    let mut kv = vec![
        ("address", Value::from(address)),
        ("poll_s", Value::Float(0.05)),
    ];
    for (k, v) in extra {
        kv.retain(|(n, _)| n != k);
        kv.push((k, v.clone()));
    }
    map(&kv)
}

/// `c1/d1` on the simulator at `port`: a 300 ms timeout, ping every 100 ms,
/// `conn` and `dev` params beside (or over) those.
fn tree(port: u16, conn: &[(&str, Value)], dev: &[(&str, Value)], points: Value) -> Tree {
    let mut d: Vec<(&str, Value)> = vec![("ping_s", Value::Float(0.1))];
    for (k, v) in dev {
        d.retain(|(n, _)| n != k);
        d.push((k, v.clone()));
    }
    d.push(("points", points));
    let mut c: Vec<(&str, Value)> = vec![
        ("host", "127.0.0.1".into()),
        ("port", Value::UInt(port.into())),
        ("timeout_ms", Value::UInt(300)),
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
        Value::UInt(i) => NodeState::NAMES.get(i as usize).map(|s| (*s).to_owned()),
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

fn q(h: &H, p: &str) -> Option<Quality> {
    h.ctx().last(&format!("c1/d1/{p}")).map(|s| s.q)
}

fn status(a: &wyrm_core::Attachment) -> Option<Status> {
    match a.status? {
        wyrm_core::status::StatusCode::Known(s) => Some(s),
        _ => None,
    }
}

fn err_text(a: &wyrm_core::Attachment) -> String {
    a.err.as_ref().map(|e| format!("{e:?}")).unwrap_or_default()
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

/// Invoke `action` on `path` at `perm`: status, value, error text.
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
    let msg = err_text(&r.att);
    (status(&r.att), r.value(), msg)
}

fn field<'a>(v: &'a Option<Value>, k: &str) -> &'a Value {
    match v {
        Some(Value::Map(m)) => m.get(k).unwrap_or_else(|| panic!("no {k} in {m:?}")),
        other => panic!("not a map: {other:?}"),
    }
}

/// Every data type and area, through the wire.
#[tokio::test(flavor = "multi_thread")]
async fn data_types_and_conversions() {
    let (addr, dev, _sim) = sim::spawn("127.0.0.1:0").await.unwrap();
    {
        let mut p = dev.lock().unwrap();
        let db = p.db(1, 1000);
        db[0] = 0b0000_1000; // DBX0.3
        db[1] = 0xAB;
        db[2..4].copy_from_slice(&0x1234u16.to_be_bytes());
        db[4..8].copy_from_slice(&0xDEAD_BEEFu32.to_be_bytes());
        db[8..10].copy_from_slice(&(-2i16).to_be_bytes());
        db[10..14].copy_from_slice(&(-70_000i32).to_be_bytes());
        db[14..18].copy_from_slice(&21.5f32.to_be_bytes());
        db[18..26].copy_from_slice(&(-1.25e10f64).to_be_bytes());
        db[26..30].copy_from_slice(&[10, 3, b'a', 0xE9]);
        db[30] = b'c';
        db[40..42].copy_from_slice(&0x1020u16.to_be_bytes()); // S5TIME 2 s
        db[42..46].copy_from_slice(&(-1500i32).to_be_bytes()); // TIME -1.5 s
        db[46..54].copy_from_slice(&[0x26, 0x10, 0x30, 0x12, 0x34, 0x56, 0x78, 0x96]);
        db[60..62].copy_from_slice(&315i16.to_be_bytes());
        p.markers[20..22].copy_from_slice(&7u16.to_be_bytes());
        p.markers[1] = 0b1000_0000;
        p.inputs[0] = 0x5A;
        p.outputs[1] = 0b10;
        p.timers[5] = 0x2015; // 15 s
        p.counters[3] = 0x0042; // BCD 42
    }
    let points = map(&[
        ("x", pt("DB1.DBX0.3", &[])),
        ("x_off", pt("DB1.DBX0.2", &[])),
        ("b", pt("DB1.DBB1", &[])),
        ("w", pt("DB1.DBW2", &[])),
        ("d", pt("DB1.DBD4", &[])),
        ("i", pt("DB1.DBW8:INT", &[])),
        ("di", pt("DB1.DBD10", &[("dtype", "dint".into())])),
        ("r", pt("DB1.DBD14:REAL", &[])),
        ("lr", pt("DB1.DBB18:LREAL", &[])),
        ("s", pt("DB1.DBB26:STRING[10]", &[])),
        ("s5", pt("DB1.DBW40:S5TIME", &[])),
        ("t", pt("DB1.DBD42:TIME", &[])),
        ("dt", pt("DB1.DBB46:DATE_AND_TIME", &[])),
        (
            "scaled",
            pt(
                "DB1.DBW60:INT",
                &[
                    ("scale", Value::Float(0.1)),
                    ("offset", Value::Float(-10.0)),
                ],
            ),
        ),
        ("mw", pt("MW20", &[])),
        ("m", pt("M1.7", &[])),
        ("ib", pt("IB0", &[])),
        ("q", pt("QX1.1", &[])),
        ("tm", pt("T5", &[])),
        ("cn", pt("C3:COUNTER", &[])),
        ("cw", pt("C3", &[])),
    ]);
    let h = H::start(tree(addr.port(), &[], &[], points)).await;
    wait("all values", || {
        ["x", "lr", "dt", "mw", "ib", "q", "tm", "cn", "scaled"]
            .iter()
            .all(|p| val(&h, p).is_some())
    })
    .await;
    for (p, want) in [
        ("x", Value::Bool(true)),
        ("x_off", Value::Bool(false)),
        ("b", Value::UInt(0xAB)),
        ("w", Value::UInt(0x1234)),
        ("d", Value::UInt(0xDEAD_BEEF)),
        ("i", Value::Int(-2)),
        ("di", Value::Int(-70_000)),
        ("r", Value::Float(21.5)),
        ("lr", Value::Float(-1.25e10)),
        ("s", Value::from("aéc")),
        ("s5", Value::Float(2.0)),
        ("t", Value::Float(-1.5)),
        ("dt", Value::from("2026-10-30T12:34:56.789Z")),
        ("scaled", Value::Float(21.5)),
        ("mw", Value::UInt(7)),
        ("m", Value::Bool(true)),
        ("ib", Value::UInt(0x5A)),
        ("q", Value::Bool(true)),
        ("tm", Value::Float(15.0)),
        ("cn", Value::UInt(42)),
        ("cw", Value::UInt(0x42)),
    ] {
        assert_eq!(val(&h, p), Some(want), "{p}");
        assert_eq!(q(&h, p), Some(Quality::Good), "{p}");
    }
    // meta: types and the unit
    let (_, m) = h.meta("c1/d1/s").await;
    assert_eq!(m.unwrap().ty, Some(wyrm_core::TypeCode::String));
    let (_, m) = h.meta("c1/d1/x").await;
    assert_eq!(m.unwrap().ty, Some(wyrm_core::TypeCode::Bool));
    h.stop().await;
}

/// Adjacent points merge into one item; DB, M, T and C points share one
/// request.
#[tokio::test(flavor = "multi_thread")]
async fn reads_merge_into_items_and_requests() {
    let (addr, dev, _sim) = sim::spawn("127.0.0.1:0").await.unwrap();
    let mut pts: Vec<(String, Value)> = (0..10)
        .map(|k| (format!("w{k}"), pt(&format!("DB1.DBW{}", k * 2), &[])))
        .collect();
    pts.push(("gap".into(), pt("DB1.DBW24", &[]))); // 4 bytes after w9: merged
    pts.push(("far".into(), pt("DB1.DBW100", &[]))); // own item
    pts.push(("m".into(), pt("MB3", &[])));
    pts.push(("t".into(), pt("T1", &[])));
    pts.push(("c".into(), pt("C2", &[])));
    let points = Value::Map(pts.into_iter().collect());
    let h = H::start(tree(addr.port(), &[], &[("ping", "none".into())], points)).await;
    wait("polled", || {
        val(&h, "c").is_some() && val(&h, "far").is_some()
    })
    .await;
    tokio::time::sleep(Duration::from_millis(200)).await;
    {
        let p = dev.lock().unwrap();
        let last = p.reads().last().cloned().cloned().unwrap();
        // DB1 0..26 and DB1 100..102, MB3, T1, C2: five items, one request
        let mut items: Vec<(u8, u32, u16)> = last
            .items
            .iter()
            .map(|i| (i.area, i.start, i.count))
            .collect();
        items.sort();
        assert_eq!(
            items,
            vec![
                (0x1C, 2, 1),
                (0x1D, 1, 1),
                (0x83, 3, 1),
                (0x84, 0, 26),
                (0x84, 100, 2)
            ]
        );
        assert!(
            last.items.iter().all(|i| i.ts != 0x01),
            "reads use bytes, not bits"
        );
        assert_eq!(p.oversize, 0);
    }
    h.stop().await;
}

/// A small PDU: requests and replies still fit (the simulator refuses any
/// that does not), a long STRING is read in parts, values are right.
#[tokio::test(flavor = "multi_thread")]
async fn a_small_pdu_splits_requests() {
    let (addr, dev, _sim) = sim::spawn("127.0.0.1:0").await.unwrap();
    {
        let mut p = dev.lock().unwrap();
        p.pdu_size = 100;
        p.max_items = 20;
        let db = p.db(1, 1000);
        let text: Vec<u8> = (0..150).map(|i| b'A' + (i % 26) as u8).collect();
        db[300] = 200;
        db[301] = 150;
        db[302..452].copy_from_slice(&text);
        for k in 0..12 {
            db[500 + k * 20] = k as u8;
        }
    }
    let mut pts: Vec<(String, Value)> = (0..12)
        .map(|k| {
            (
                format!("b{k}"),
                pt(&format!("DB1.DBB{}", 500 + k * 20), &[]),
            )
        })
        .collect();
    pts.push(("long".into(), pt("DB1.DBB300:STRING[200]", &[])));
    let points = Value::Map(pts.into_iter().collect());
    let h = H::start(tree(
        addr.port(),
        &[("pdu_size", Value::UInt(240))],
        &[("ping", "none".into())],
        points,
    ))
    .await;
    wait("polled", || {
        val(&h, "long").is_some() && val(&h, "b11").is_some()
    })
    .await;
    let want: String = (0..150)
        .map(|i| char::from(b'A' + (i % 26) as u8))
        .collect();
    assert_eq!(val(&h, "long"), Some(Value::Str(want)));
    for k in 0..12 {
        assert_eq!(val(&h, &format!("b{k}")), Some(Value::UInt(k)), "b{k}");
    }
    {
        let p = dev.lock().unwrap();
        assert_eq!(p.agreed_pdu, 100);
        assert_eq!(p.oversize, 0, "every request and reply fit the PDU");
        // 202 bytes of string at 82 per item, 12 single bytes: several requests
        let per_poll: Vec<usize> = p.reads().iter().map(|j| j.items.len()).collect();
        assert!(
            per_poll.iter().all(|n| *n <= 7),
            "(100 - 12) / 12 items: {per_poll:?}"
        );
        assert!(
            p.reads()
                .iter()
                .any(|j| j.items.iter().any(|i| i.start == 300 && i.count == 82)),
            "the string is cut at the PDU"
        );
    }
    let (s, v, _) = act(&h, "c1", "connection_info", map(&[]), Perm::Read).await;
    assert_eq!(s, Some(Status::Ok));
    assert_eq!(field(&v, "pdu_size"), &Value::UInt(100));
    assert_eq!(field(&v, "remote_tsap"), &Value::from("0x0101"));
    h.stop().await;
}

/// An item's return code fails its point only; a failed merged item is
/// read again point by point, and the bad point is read alone from then on.
#[tokio::test(flavor = "multi_thread")]
async fn an_item_error_fails_that_point_only() {
    let (addr, dev, _sim) = sim::spawn("127.0.0.1:0").await.unwrap();
    {
        let mut p = dev.lock().unwrap();
        p.db(1, 1000)[0..2].copy_from_slice(&7u16.to_be_bytes());
        p.db(2, 100)[96..98].copy_from_slice(&9u16.to_be_bytes());
    }
    let points = map(&[
        ("ok", pt("DB1.DBW0", &[])),
        ("past", pt("DB1.DBW2000", &[])), // DB1 has 1000 bytes
        ("nodb", pt("DB9.DBW0", &[])),
        // merged with `edge`: DB2 has 100 bytes, 98..102 runs past it
        ("near", pt("DB2.DBW96", &[])),
        ("edge", pt("DB2.DBD98", &[])),
    ]);
    let h = H::start(tree(addr.port(), &[], &[], points)).await;
    wait("errors and values", || {
        ["past", "nodb", "edge"]
            .iter()
            .all(|p| q(&h, p) == Some(Quality::Bad))
            && val(&h, "near") == Some(Value::UInt(9))
    })
    .await;
    assert_eq!(val(&h, "ok"), Some(Value::UInt(7)));
    assert_eq!(q(&h, "ok"), Some(Quality::Good));
    assert_eq!(q(&h, "near"), Some(Quality::Good));
    assert_eq!(state(&h, "c1/d1").as_deref(), Some("connected"));
    tokio::time::sleep(Duration::from_millis(300)).await;
    // `edge` is read alone now: no DB2 item spans 96..102 any more
    {
        let p = dev.lock().unwrap();
        let last = p.reads().last().cloned().cloned().unwrap();
        let db2: Vec<(u32, u16)> = last
            .items
            .iter()
            .filter(|i| i.area == 0x84 && i.db == 2)
            .map(|i| (i.start, i.count))
            .collect();
        assert!(db2.contains(&(96, 2)) && db2.contains(&(98, 4)), "{db2:?}");
    }
    // the PLC's text comes back to a reader
    let (s, _, msg) = act(
        &h,
        "c1/d1",
        "read_address",
        map(&[("address", "DB9.DBW0".into())]),
        Perm::Read,
    )
    .await;
    assert_eq!(s, Some(Status::NotAvailable));
    assert!(
        msg.contains("0x0A") && msg.contains("does not exist"),
        "{msg}"
    );
    h.stop().await;
}

/// A header error (the whole request refused: PUT/GET off) fails the points
/// of the request without a read point by point, and merging comes back
/// when the PLC answers again.
#[tokio::test(flavor = "multi_thread")]
async fn a_header_error_does_not_split_merged_items() {
    let (addr, dev, _sim) = sim::spawn("127.0.0.1:0").await.unwrap();
    let points = map(&[("a", pt("DB1.DBW0", &[])), ("b", pt("DB1.DBW2", &[]))]);
    let h = H::start(tree(addr.port(), &[], &[("ping", "none".into())], points)).await;
    wait("good", || {
        q(&h, "a") == Some(Quality::Good) && q(&h, "b") == Some(Quality::Good)
    })
    .await;
    let before = dev.lock().unwrap().reads().len();
    dev.lock().unwrap().deny_put_get = true;
    wait("refused", || {
        q(&h, "a") == Some(Quality::Bad) && q(&h, "b") == Some(Quality::Bad)
    })
    .await;
    tokio::time::sleep(Duration::from_millis(300)).await;
    {
        let p = dev.lock().unwrap();
        let during: Vec<Vec<(u32, u16)>> = p.reads()[before..]
            .iter()
            .map(|j| j.items.iter().map(|i| (i.start, i.count)).collect())
            .collect();
        assert!(during.len() >= 3, "{during:?}");
        assert!(
            during.iter().all(|items| items == &[(0, 4)]),
            "no reads point by point: {during:?}"
        );
    }
    dev.lock().unwrap().deny_put_get = false;
    wait("good again", || {
        q(&h, "a") == Some(Quality::Good) && q(&h, "b") == Some(Quality::Good)
    })
    .await;
    tokio::time::sleep(Duration::from_millis(200)).await;
    {
        let p = dev.lock().unwrap();
        let last = p.reads().last().cloned().cloned().unwrap();
        let items: Vec<(u8, u32, u16)> = last
            .items
            .iter()
            .map(|i| (i.area, i.start, i.count))
            .collect();
        assert_eq!(items, vec![(0x84, 0, 4)], "still merged");
    }
    h.stop().await;
}

/// Write Var per point, read back; a bit with the bit transport size (its
/// byte's other bits stay); a STRING without its maximum-length byte.
#[tokio::test(flavor = "multi_thread")]
async fn writes_and_read_back() {
    let (addr, dev, _sim) = sim::spawn("127.0.0.1:0").await.unwrap();
    dev.lock().unwrap().db(1, 1000)[40] = 20; // STRING[20]: the PLC's max
    dev.lock().unwrap().db(1, 1000)[0] = 0b0000_0001;
    let w = [("writable", Value::Bool(true))];
    let points = map(&[
        ("bit", pt("DB1.DBX0.3", &w)),
        ("int", pt("DB1.DBW2:INT", &w)),
        ("real", pt("DB1.DBD4:REAL", &w)),
        ("text", pt("DB1.DBB40:STRING[20]", &w)),
        ("when", pt("DB1.DBB70:DT", &w)),
        ("s5", pt("DB1.DBW80:S5TIME", &w)),
        ("mw", pt("MW10", &w)),
        ("q", pt("Q0.1", &w)),
        ("ro", pt("DB1.DBW90", &[])),
    ]);
    let h = H::start(tree(addr.port(), &[], &[], points)).await;
    wait("polled", || {
        val(&h, "ro").is_some() && val(&h, "q").is_some()
    })
    .await;
    let tok = || Some(h.ptok(Perm::Write));
    for (p, v, want) in [
        ("bit", Value::Bool(true), Value::Bool(true)),
        ("int", Value::Int(-1234), Value::Int(-1234)),
        ("real", Value::Float(3.25), Value::Float(3.25)),
        ("text", Value::from("hello"), Value::from("hello")),
        (
            "when",
            Value::from("2026-10-30T10:00:00.5+02:00"),
            Value::from("2026-10-30T08:00:00.500Z"),
        ),
        ("s5", Value::Float(12.34), Value::Float(12.3)),
        ("mw", Value::UInt(4321), Value::UInt(4321)),
        ("q", Value::Bool(true), Value::Bool(true)),
    ] {
        let att = h.set(&format!("c1/d1/{p}"), v, tok()).await;
        assert_eq!(status(&att), Some(Status::Ok), "{p}: {}", err_text(&att));
        assert_eq!(val(&h, p), Some(want), "{p} read back");
    }
    {
        let p = dev.lock().unwrap();
        let db = &p.dbs[&1];
        assert_eq!(db[0], 0b0000_1001, "the other bits of the byte stay");
        assert_eq!(
            &db[40..47],
            &[20, 5, b'h', b'e', b'l', b'l', b'o'],
            "max length stays"
        );
        assert_eq!(p.outputs[0], 0b10);
        let bit_write = p
            .writes()
            .into_iter()
            .find(|j| j.items[0].start == 0 && j.items[0].area == 0x84)
            .cloned()
            .unwrap();
        assert_eq!(
            (bit_write.items[0].ts, bit_write.items[0].bit),
            (0x01, 3),
            "BIT transport"
        );
        let text_write = p
            .writes()
            .into_iter()
            .find(|j| j.items[0].start == 41)
            .cloned();
        assert!(
            text_write.is_some(),
            "the string is written from its second byte"
        );
    }
    // read-only and out of range: refused, nothing written
    let n = dev.lock().unwrap().writes().len();
    let att = h.set("c1/d1/ro", 1u64, tok()).await;
    assert_ne!(status(&att), Some(Status::Ok));
    let att = h.set("c1/d1/int", 40_000u64, tok()).await;
    assert_eq!(status(&att), Some(Status::InvalidParameter));
    let att = h
        .set("c1/d1/text", "this text is too long for it", tok())
        .await;
    assert_eq!(status(&att), Some(Status::InvalidParameter));
    assert_eq!(dev.lock().unwrap().writes().len(), n);
    h.stop().await;
}

/// A STRING write is bounded by the PLC's own maximum-length byte, not the
/// configured `[n]`: a text that would run past it is refused before any
/// Write Var, and the data after the string stays.
#[tokio::test(flavor = "multi_thread")]
async fn a_string_write_is_bounded_by_the_plc_max() {
    let (addr, dev, _sim) = sim::spawn("127.0.0.1:0").await.unwrap();
    {
        let mut p = dev.lock().unwrap();
        let db = p.db(1, 1000);
        db[40] = 10; // the PLC's STRING[10]
        db[52..54].copy_from_slice(&0x1234u16.to_be_bytes()); // a setpoint after it
    }
    let points = map(&[(
        "text",
        pt("DB1.DBB40:STRING[20]", &[("writable", Value::Bool(true))]),
    )]);
    let h = H::start(tree(addr.port(), &[], &[("ping", "none".into())], points)).await;
    wait("polled", || val(&h, "text").is_some()).await;
    let before = dev.lock().unwrap().dbs[&1][40..60].to_vec();
    let n = dev.lock().unwrap().writes().len();
    let att = h
        .set("c1/d1/text", "fifteen chars!!", Some(h.ptok(Perm::Write)))
        .await;
    assert_ne!(status(&att), Some(Status::Ok));
    let msg = err_text(&att);
    assert!(msg.contains("STRING[10]"), "{msg}");
    {
        let p = dev.lock().unwrap();
        assert_eq!(p.writes().len(), n, "no Write Var sent");
        assert_eq!(&p.dbs[&1][40..60], &before[..], "the data after it stays");
    }
    // a text that fits the PLC's maximum is written
    let att = h
        .set("c1/d1/text", "ten chars!", Some(h.ptok(Perm::Write)))
        .await;
    assert_eq!(status(&att), Some(Status::Ok), "{}", err_text(&att));
    assert_eq!(val(&h, "text"), Some(Value::from("ten chars!")));
    assert_eq!(&dev.lock().unwrap().dbs[&1][52..54], &[0x12, 0x34]);
    h.stop().await;
}

/// A value longer than one Write Var goes in parts; S7-1200/1500 without
/// PUT/GET answer 0x8104 and the caller sees the hint.
#[tokio::test(flavor = "multi_thread")]
async fn long_writes_in_parts_and_put_get_refused() {
    let (addr, dev, _sim) = sim::spawn("127.0.0.1:0").await.unwrap();
    {
        let mut p = dev.lock().unwrap();
        p.pdu_size = 100;
        p.db(1, 1000)[100] = 200;
    }
    let points = map(&[(
        "long",
        pt("DB1.DBB100:STRING[200]", &[("writable", Value::Bool(true))]),
    )]);
    let h = H::start(tree(addr.port(), &[], &[], points)).await;
    wait("polled", || val(&h, "long").is_some()).await;
    let text: String = (0..150)
        .map(|i| char::from(b'a' + (i % 26) as u8))
        .collect();
    let att = h
        .set("c1/d1/long", text.as_str(), Some(h.ptok(Perm::Write)))
        .await;
    assert_eq!(status(&att), Some(Status::Ok), "{}", err_text(&att));
    assert_eq!(val(&h, "long"), Some(Value::Str(text.clone())));
    {
        let p = dev.lock().unwrap();
        assert_eq!(p.oversize, 0);
        // 151 bytes at 72 per request
        assert_eq!(p.writes().len(), 3);
        assert_eq!(p.dbs[&1][100], 200, "max length stays");
    }
    dev.lock().unwrap().deny_put_get = true;
    wait("refused", || q(&h, "long") == Some(Quality::Bad)).await;
    assert_eq!(
        state(&h, "c1/d1").as_deref(),
        Some("connected"),
        "the PLC answers"
    );
    let att = h.set("c1/d1/long", "x", Some(h.ptok(Perm::Write))).await;
    assert_ne!(status(&att), Some(Status::Ok));
    let msg = err_text(&att);
    assert!(msg.contains("0x8104") && msg.contains("PUT/GET"), "{msg}");
    h.stop().await;
}

/// A silent PLC: `uncertain/stale` first, then `bad/comm_fail`.
#[tokio::test(flavor = "multi_thread")]
async fn a_silent_plc_goes_stale_then_bad() {
    let (addr, dev, _sim) = sim::spawn("127.0.0.1:0").await.unwrap();
    dev.lock().unwrap().db(1, 1000)[1] = 5;
    let points = map(&[("v", pt("DB1.DBW0", &[("poll_s", Value::Float(0.1))]))]);
    let h = H::start(tree(
        addr.port(),
        &[("timeout_ms", Value::UInt(150))],
        &[],
        points,
    ))
    .await;
    wait("good", || q(&h, "v") == Some(Quality::Good)).await;
    let seen = samples(&h, "c1/d1/v").await;
    dev.lock().unwrap().silent = true;
    wait("bad", || q(&h, "v") == Some(Quality::Bad)).await;
    let qs: Vec<Quality> = seen.lock().unwrap().iter().map(|s| s.q).collect();
    let first_bad = qs.iter().position(|x| *x == Quality::Bad).unwrap();
    assert!(
        qs[..first_bad].contains(&Quality::Uncertain),
        "uncertain before bad: {qs:?}"
    );
    assert_eq!(val(&h, "v"), Some(Value::UInt(5)), "the last value is kept");
    h.stop().await;
}

/// The PLC goes away: the connection fails with an `error` leaf, its
/// device is stopped by its parent; the PLC comes back on the same port and
/// the link reconnects.
#[tokio::test(flavor = "multi_thread")]
async fn a_lost_plc_fails_the_connection_and_reconnects() {
    let (addr, dev, sim) = sim::spawn("127.0.0.1:0").await.unwrap();
    dev.lock().unwrap().db(1, 1000)[1] = 1;
    let points = map(&[("v", pt("DB1.DBW0", &[]))]);
    let h = H::start(tree(addr.port(), &[], &[], points)).await;
    wait("good", || val(&h, "v") == Some(Value::UInt(1))).await;
    sim.stop();
    drop(sim);
    wait(
        "connection failed with an error, device stopped by parent",
        || {
            state(&h, "c1").as_deref() == Some("failed")
                && state(&h, "c1/d1").as_deref() == Some("stopped_by_parent")
                && h.ctx().last("c1/error").is_some()
        },
    )
    .await;
    wait("point bad", || q(&h, "v") == Some(Quality::Bad)).await;
    dev.lock().unwrap().db(1, 1000)[1] = 2;
    let (_, _sim) = sim::spawn_with(&addr.to_string(), dev.clone())
        .await
        .unwrap();
    // the framework's backoff: up to a few seconds
    wait("reconnected", || {
        state(&h, "c1").as_deref() == Some("connected") && val(&h, "v") == Some(Value::UInt(2))
    })
    .await;
    assert_eq!(q(&h, "v"), Some(Quality::Good));
    wait("no error, no leaf", || !h.ctx().has_node("c1/error")).await;
    assert!(dev.lock().unwrap().connections >= 2);
    h.stop().await;
}

/// A reply that comes after its timeout is dropped by its PDU reference:
/// it is never taken for the next request (here: another point's).
#[tokio::test(flavor = "multi_thread")]
async fn a_late_reply_is_dropped() {
    let (addr, dev, _sim) = sim::spawn("127.0.0.1:0").await.unwrap();
    {
        let mut p = dev.lock().unwrap();
        let db = p.db(1, 1000);
        db[0..2].copy_from_slice(&111u16.to_be_bytes());
        db[100..102].copy_from_slice(&222u16.to_be_bytes());
    }
    // two poll groups: two requests, each one item of 2 bytes
    let points = map(&[
        ("a", pt("DB1.DBW0", &[("poll_s", Value::Float(0.1))])),
        ("b", pt("DB1.DBW100", &[("poll_s", Value::Float(0.13))])),
    ]);
    let h = H::start(tree(
        addr.port(),
        &[("timeout_ms", Value::UInt(200))],
        &[("ping", "none".into())],
        points,
    ))
    .await;
    wait("both", || val(&h, "a").is_some() && val(&h, "b").is_some()).await;
    let seen_b = samples(&h, "c1/d1/b").await;
    {
        let mut p = dev.lock().unwrap();
        p.delay_at = Some(0);
        p.delay_once = Some(Duration::from_millis(500));
    }
    wait("dropped", || dev.lock().unwrap().delay_once.is_none()).await;
    tokio::time::sleep(Duration::from_millis(1200)).await;
    assert!(
        seen_b
            .lock()
            .unwrap()
            .iter()
            .all(|s| s.v == Value::UInt(222)),
        "b never took a's late reply"
    );
    assert_eq!(val(&h, "a"), Some(Value::UInt(111)));
    assert_eq!(q(&h, "a"), Some(Quality::Good));
    let (_, v, _) = act(&h, "c1", "connection_info", map(&[]), Perm::Read).await;
    assert!(matches!(field(&v, "late_replies"), Value::UInt(n) if *n >= 1));
    // the diagnostics counter
    h.meta("c1").await;
    wait(
        "late_replies leaf",
        || matches!(h.ctx().last("c1/late_replies").map(|s| s.v), Some(Value::UInt(n)) if n >= 1),
    )
    .await;
    h.stop().await;
}

/// Ping by SZL (an answer with an error still means alive) and by a read;
/// `read_szl` returns the order code.
#[tokio::test(flavor = "multi_thread")]
async fn ping_and_commissioning_actions() {
    let (addr, dev, _sim) = sim::spawn("127.0.0.1:0").await.unwrap();
    dev.lock().unwrap().markers[20..22].copy_from_slice(&0x0102u16.to_be_bytes());
    let h = H::start(tree(addr.port(), &[], &[], map(&[]))).await;
    wait("connected", || {
        state(&h, "c1/d1").as_deref() == Some("connected")
    })
    .await;
    let (_, m) = h.meta("c1/d1").await;
    let acts = m.unwrap().actions.unwrap();
    assert_eq!(acts["read_szl"].level, Some(Perm::Read));
    assert_eq!(acts["read_address"].level, Some(Perm::Read));
    let (s, v, msg) = act(
        &h,
        "c1/d1",
        "read_szl",
        map(&[("id", Value::UInt(0x0011))]),
        Perm::Read,
    )
    .await;
    assert_eq!(s, Some(Status::Ok), "{msg}");
    assert_eq!(field(&v, "order_code"), &Value::from("6ES7 315-2EH14-0AB0"));
    assert_eq!(field(&v, "record_length"), &Value::UInt(28));
    let (s, v, _) = act(
        &h,
        "c1/d1",
        "read_address",
        map(&[("address", "MW20".into()), ("dtype", "int".into())]),
        Perm::Read,
    )
    .await;
    assert_eq!(s, Some(Status::Ok));
    assert_eq!(field(&v, "value"), &Value::UInt(0x0102));
    let (s, _, msg) = act(
        &h,
        "c1/d1",
        "read_address",
        map(&[("address", "MW20:REAL".into())]),
        Perm::Read,
    )
    .await;
    assert_eq!(s, Some(Status::InvalidParameter), "{msg}");
    // an SZL the PLC does not have: an error answer, still alive
    dev.lock().unwrap().no_szl = true;
    let (s, _, msg) = act(
        &h,
        "c1/d1",
        "read_szl",
        map(&[("id", Value::UInt(0x11))]),
        Perm::Read,
    )
    .await;
    assert_eq!(s, Some(Status::NotAvailable));
    assert!(msg.contains("0xD401"), "{msg}");
    let szl_before = dev
        .lock()
        .unwrap()
        .log
        .iter()
        .filter(|j| j.function == 0)
        .count();
    tokio::time::sleep(Duration::from_millis(500)).await;
    assert!(
        dev.lock()
            .unwrap()
            .log
            .iter()
            .filter(|j| j.function == 0)
            .count()
            > szl_before,
        "pings go on"
    );
    assert_eq!(state(&h, "c1/d1").as_deref(), Some("connected"));
    h.stop().await;
    // ping by a 1-byte read of a configured address
    let h = H::start(tree(
        addr.port(),
        &[],
        &[("ping", "read".into()), ("ping_address", "DB2.DBB0".into())],
        map(&[]),
    ))
    .await;
    wait("connected", || {
        state(&h, "c1/d1").as_deref() == Some("connected")
    })
    .await;
    tokio::time::sleep(Duration::from_millis(300)).await;
    assert!(dev.lock().unwrap().reads().iter().any(|j| j.items
        == [sim::LogItem {
            area: 0x84,
            db: 2,
            start: 0,
            bit: 0,
            count: 1,
            ts: 0x02
        }]));
    h.stop().await;
}

/// Rack, slot and connection type make the remote TSAP.
#[tokio::test(flavor = "multi_thread")]
async fn rack_slot_and_type_make_the_tsap() {
    let (addr, dev, _sim) = sim::spawn("127.0.0.1:0").await.unwrap();
    let h = H::start(tree(
        addr.port(),
        &[
            ("rack", Value::UInt(1)),
            ("slot", Value::UInt(3)),
            ("conn_type", "s7_basic".into()),
        ],
        &[],
        map(&[]),
    ))
    .await;
    wait("connected", || {
        state(&h, "c1").as_deref() == Some("connected")
    })
    .await;
    assert_eq!(dev.lock().unwrap().tsaps.last(), Some(&0x0323));
    h.stop().await;
}

fn point(kv: &[(&str, Value)]) -> wyrm_link_sdk::Result<Point> {
    Point::from_value(&map(kv))
}

/// Bounds and cross-field rules, with a clear error each.
#[test]
fn params_bounds_and_address_errors() {
    let conn = |kv: &[(&str, Value)]| {
        let mut all = vec![("host", Value::from("10.0.0.1"))];
        all.extend_from_slice(kv);
        Conn::from_value(&map(&all))
    };
    let c = conn(&[]).unwrap();
    assert_eq!(
        (c.port, c.rack, c.slot, c.pdu_size, c.timeout_ms),
        (102, 0, 1, 480, 2000)
    );
    for bad in [
        ("rack", Value::UInt(8)),
        ("slot", Value::UInt(32)),
        ("pdu_size", Value::UInt(100)),
        ("pdu_size", Value::UInt(1000)),
        ("timeout_ms", Value::UInt(50)),
        ("conn_type", "tcp".into()),
    ] {
        assert!(conn(std::slice::from_ref(&bad)).is_err(), "{bad:?}");
    }
    assert!(Dev::from_value(&map(&[("ping_address", "XYZ".into())]))
        .unwrap_err()
        .message
        .contains("ping_address"));
    assert!(Dev::from_value(&map(&[("max_items", Value::UInt(21))])).is_err());
    assert!(Dev::from_value(&map(&[("tz_offset_min", Value::Int(-721))])).is_err());
    let p = point(&[("address", "DB1.DBD8:REAL".into())]).unwrap();
    assert_eq!(p.ty, wyrm_link_s7::addr::DType::Real);
    assert_eq!(Point::from_value(&p.to_value()).unwrap(), p, "round trip");
    for (kv, why) in [
        (vec![("address", Value::from("DB1.DBX0"))], "bit number"),
        (vec![("address", Value::from("DB1.DBW0:REAL"))], "D address"),
        (
            vec![
                ("address", Value::from("DB1.DBD0:REAL")),
                ("dtype", "dint".into()),
            ],
            "says REAL",
        ),
        (
            vec![
                ("address", Value::from("IB0")),
                ("writable", Value::Bool(true)),
            ],
            "inputs",
        ),
        (
            vec![
                ("address", Value::from("T1")),
                ("writable", Value::Bool(true)),
            ],
            "timers",
        ),
        (
            vec![
                ("address", Value::from("M0.0")),
                ("scale", Value::Float(2.0)),
            ],
            "numbers only",
        ),
        (
            vec![
                ("address", Value::from("MW0")),
                ("scale", Value::Float(0.0)),
            ],
            "scale",
        ),
        (
            vec![("address", Value::from("MW0")), ("dtype", "float".into())],
            "dtype",
        ),
        (vec![], "address"),
    ] {
        let e = point(&kv).unwrap_err();
        assert!(e.message.contains(why), "{kv:?}: {}", e.message);
    }
}

/// `add_point` refuses a bad address with the parser's text; no secrets
/// exist in this link, so nothing is hidden from `~meta`.
#[tokio::test(flavor = "multi_thread")]
async fn add_point_validates_the_address() {
    let (addr, _dev, _sim) = sim::spawn("127.0.0.1:0").await.unwrap();
    let h = H::start(tree(addr.port(), &[], &[], map(&[]))).await;
    wait("connected", || {
        state(&h, "c1/d1").as_deref() == Some("connected")
    })
    .await;
    let (s, _, msg) = act(
        &h,
        "c1/d1",
        "add_point",
        map(&[("name", "x".into()), ("address", "DB1.DBX9".into())]),
        Perm::Config,
    )
    .await;
    assert_eq!(s, Some(Status::InvalidParameter));
    assert!(msg.contains("bit number"), "{msg}");
    let (s, _, msg) = act(
        &h,
        "c1/d1",
        "add_point",
        map(&[
            ("name", "x".into()),
            ("address", "DB1.DBX9.1".into()),
            ("poll_s", Value::Float(0.05)),
        ]),
        Perm::Config,
    )
    .await;
    assert_eq!(s, Some(Status::Ok), "{msg}");
    wait("polled", || val(&h, "x") == Some(Value::Bool(false))).await;
    assert!(wyrm_link_sdk::driver::params::all_secret_names::<Conn>().is_empty());
    h.stop().await;
}

/// The PLC closes the connection: the link reconnects and polls on.
#[tokio::test(flavor = "multi_thread")]
async fn a_closed_connection_reconnects() {
    let (addr, dev, _sim) = sim::spawn("127.0.0.1:0").await.unwrap();
    dev.lock().unwrap().db(1, 1000)[1] = 1;
    let points = map(&[("v", pt("DB1.DBW0", &[]))]);
    let h = H::start(tree(addr.port(), &[], &[], points)).await;
    wait("good", || val(&h, "v") == Some(Value::UInt(1))).await;
    {
        let mut p = dev.lock().unwrap();
        p.close_next = true;
        p.db(1, 1000)[1] = 2;
    }
    wait("reconnected", || {
        dev.lock().unwrap().connections >= 2 && val(&h, "v") == Some(Value::UInt(2))
    })
    .await;
    wait("connected", || {
        state(&h, "c1").as_deref() == Some("connected")
    })
    .await;
    h.stop().await;
}
