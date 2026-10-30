//! `import_dsa` (Task 7): a dslink-java-modbus `nodes.json` as Modbus
//! connections, with a report of what could not be mapped. The fixture and
//! the Java sources it follows: `fixtures/dsa-nodes.{json,md}`.

use serde_json::{json, Value as Json};
use std::collections::BTreeMap;
use std::time::Duration;
use wyrm_core::{Perm, Status, Value};
use wyrm_link_modbus::{dsa, sim, Modbus};
use wyrm_link_sdk::driver::branch::{Level, Node};
use wyrm_link_sdk::driver::{Converted, Tree};
use wyrm_link_sdk::TestHarness;

type H = TestHarness<Modbus>;
type Map = BTreeMap<String, Value>;

fn fixture() -> Json {
    serde_json::from_str(include_str!("fixtures/dsa-nodes.json")).expect("fixture")
}

fn conv(j: &Json) -> Converted {
    dsa::convert(&j.to_string(), None).expect("converts")
}

/// The node at `path` (`conn/dev/...`, our ids).
fn find<'a>(c: &'a Converted, path: &str) -> Option<&'a Node> {
    let mut parts = path.split('/');
    let first = parts.next()?;
    let mut n = c.connections.iter().find(|n| n.name == first)?;
    for p in parts {
        n = n.children.iter().find(|c| c.name == p)?;
    }
    Some(n)
}

fn node<'a>(c: &'a Converted, path: &str) -> &'a Node {
    find(c, path).unwrap_or_else(|| panic!("no {path} in {:#?}", c.connections))
}

fn param<'a>(n: &'a Node, k: &str) -> &'a Value {
    n.params
        .get(k)
        .unwrap_or_else(|| panic!("{}: no {k} in {:?}", n.name, n.params))
}

fn f64_of(v: &Value) -> f64 {
    v.as_f64().unwrap_or_else(|| panic!("not a number: {v:?}"))
}

/// The entries of the report list `key`.
fn entries(c: &Converted, key: &str) -> Vec<Map> {
    match c.report.get(key) {
        Some(Value::Array(a)) => a
            .iter()
            .map(|e| match e {
                Value::Map(m) => m.clone(),
                other => panic!("{key}: not a map: {other:?}"),
            })
            .collect(),
        other => panic!("{key}: not a list: {other:?}"),
    }
}

fn s(m: &Map, k: &str) -> String {
    match m.get(k) {
        Some(Value::Str(s)) => s.clone(),
        other => panic!("{k}: {other:?} in {m:?}"),
    }
}

/// `(path, field)` of every dropped entry, sorted.
fn dropped(c: &Converted) -> Vec<(String, String)> {
    let mut v: Vec<(String, String)> = entries(c, "dropped")
        .iter()
        .map(|m| (s(m, "path"), s(m, "field")))
        .collect();
    v.sort();
    v
}

fn reason(c: &Converted, path: &str, field: &str) -> String {
    entries(c, "dropped")
        .iter()
        .find(|m| s(m, "path") == path && s(m, "field") == field)
        .map(|m| s(m, "reason"))
        .unwrap_or_else(|| panic!("no drop {path} {field} in {:?}", dropped(c)))
}

fn owned(v: &[(&str, &str)]) -> Vec<(String, String)> {
    v.iter()
        .map(|(a, b)| ((*a).to_owned(), (*b).to_owned()))
        .collect()
}

/// A DSA point with the attributes `SlaveFolder.java:149-150` requires,
/// `over` replacing or adding some.
fn dsa_point(over: Json) -> Json {
    let mut p = json!({
        "$is": "node",
        "@restoreType": "point",
        "@type": "HOLDING",
        "@offset": 0,
        "@number of registers": 1,
        "@data type": "UINT16",
        "@bit": -1,
        "@scaling": 1.0,
        "@scaling offset": 0.0,
        "@writable": false
    });
    for (k, v) in over.as_object().unwrap() {
        p[k] = v.clone();
    }
    p
}

/// A whole `nodes.json`: IP connection `C` with device `D` (unit 1, 1 s)
/// holding `children`.
fn one_device(children: Json) -> Json {
    let mut d = json!({
        "$is": "node",
        "@restoreType": "folder",
        "@slave id": 1,
        "@polling interval": 1000
    });
    for (k, v) in children.as_object().unwrap() {
        d[k] = v.clone();
    }
    json!({
        "C": {
            "$is": "node",
            "@restoreType": "conn",
            "@transport type": "TCP",
            "@host": "h",
            "@port": 502,
            "D": d
        }
    })
}

fn map(kv: &[(&str, Value)]) -> Value {
    Value::Map(
        kv.iter()
            .map(|(k, v)| ((*k).to_owned(), v.clone()))
            .collect(),
    )
}

fn status(a: &wyrm_core::Attachment) -> Option<Status> {
    match a.status? {
        wyrm_core::status::StatusCode::Known(s) => Some(s),
        _ => None,
    }
}

/// `import_dsa {json}` through the link at `config`: the reply map.
async fn import(h: &H, j: &Json) -> Map {
    let mut r = h
        .invoke(
            "",
            dsa::ACTION,
            map(&[("json", Value::Str(j.to_string()))]),
            Some(h.ptok(Perm::Config)),
        )
        .await;
    assert_eq!(r.len(), 1);
    let r = r.remove(0);
    assert_eq!(status(&r.att), Some(Status::Ok), "{:?}", r.att.err);
    match r.value() {
        Some(Value::Map(m)) => m,
        other => panic!("{other:?}"),
    }
}

async fn wait(what: &str, mut f: impl FnMut() -> bool) {
    let deadline = tokio::time::Instant::now() + Duration::from_secs(10);
    while !f() {
        assert!(tokio::time::Instant::now() < deadline, "timeout: {what}");
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
}

/// Review Focus 3: DSA `scaling 10`, `scaling offset 2` on raw 250 shows
/// 250 / 10 + 2 = 27.0 (`SlaveNode.java:326`). Imported as `scale 0.1,
/// offset 2` it shows exactly 27.0, and 27.0 is written back as raw 250
/// (the inverse; DSA itself would write 27 × 10 − 2 = 268,
/// `SlaveFolder.java:640`).
#[tokio::test(flavor = "multi_thread")]
async fn scaled_point_reads_and_writes_exactly() {
    let (addr, dev, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    dev.lock().unwrap().holding[10] = 250;
    let mut j = fixture();
    j["Plant TCP"]["@host"] = json!("127.0.0.1");
    j["Plant TCP"]["@port"] = json!(addr.port());
    j["Plant TCP"]["Meter 1"]["@polling interval"] = json!(100);
    let h = H::start(Tree(Value::Null)).await;
    let reply = import(&h, &j).await;
    for k in ["created", "dropped", "disabled", "renamed", "reenter"] {
        assert!(reply.contains_key(k), "{k} in {reply:?}");
    }
    let created = &reply["created"];
    assert!(
        matches!(created, Value::Array(a) if a.contains(&Value::from("Plant_TCP/Meter_1/Setpoint"))),
        "{created:?}"
    );
    let sp = node(&conv(&j), "Plant_TCP/Meter_1/Setpoint").clone();
    assert_eq!(param(&sp, "addr"), &Value::UInt(10));
    assert_eq!(f64_of(param(&sp, "scale")), 0.1);
    assert_eq!(f64_of(param(&sp, "offset")), 2.0);
    // Imported stopped (P18): start the connection.
    let mut r = h
        .invoke("Plant_TCP", "start", map(&[]), Some(h.ptok(Perm::Config)))
        .await;
    assert_eq!(status(&r.remove(0).att), Some(Status::Ok));
    let val = |h: &H| h.ctx().last("Plant_TCP/Meter_1/Setpoint").map(|s| s.v);
    wait("27.0", || val(&h) == Some(Value::Float(27.0))).await;
    let tok = || Some(h.ptok(Perm::Write));
    let att = h.set("Plant_TCP/Meter_1/Setpoint", 30.0, tok()).await;
    assert_eq!(status(&att), Some(Status::Ok));
    assert_eq!(dev.lock().unwrap().holding[10], 280);
    let att = h.set("Plant_TCP/Meter_1/Setpoint", 27.0, tok()).await;
    assert_eq!(status(&att), Some(Status::Ok));
    assert_eq!(dev.lock().unwrap().holding[10], 250);
    assert_eq!(val(&h), Some(Value::Float(27.0)), "read back");
    h.stop().await;
}

/// DSA divides by `scaling` (`SlaveNode.java:326`): 0 is refused on a
/// numeric point and the point is reported; a boolean or text point ignores
/// scaling in DSA too, so it is imported.
#[test]
fn scaling_zero_refused() {
    let c = conv(&fixture());
    assert!(find(&c, "Line_2_RS485/VFD_7/Ratio").is_none());
    assert!(find(&c, "Line_2_RS485/VFD_7/Speed").is_some());
    let r = reason(&c, "Line 2 RS485/VFD 7/Ratio", "scaling");
    assert!(r.contains('0'), "{r}");
    let c = conv(&one_device(json!({
        "A": dsa_point(json!({"@type": "COIL", "@data type": "BOOLEAN", "@scaling": 0.0})),
        "N": dsa_point(json!({"@scaling": 0.0})),
    })));
    assert_eq!(param(node(&c, "C/D/A"), "dtype"), &Value::from("binary"));
    assert!(find(&c, "C/D/N").is_none());
    assert_eq!(dropped(&c), owned(&[("C/D/N", "scaling")]));
}

/// Every name of `DataType.java:4-31` maps to one of ours (modbus4j:
/// a 16-bit SWAP swaps the bytes, a 32/64-bit SWAP the words, SWAPSWAP
/// both); an unknown name is refused with the name.
#[test]
fn every_dsa_type_maps() {
    const TYPES: [(&str, &str); 28] = [
        ("BOOLEAN", "bits16"),
        ("INT16", "i16"),
        ("UINT16", "u16"),
        ("INT16SWAP", "i16_bswap"),
        ("UINT16SWAP", "u16_bswap"),
        ("INT32", "i32"),
        ("UINT32", "u32"),
        ("INT32SWAP", "i32_wswap"),
        ("UINT32SWAP", "u32_wswap"),
        ("INT32SWAPSWAP", "i32_wbswap"),
        ("UINT32SWAPSWAP", "u32_wbswap"),
        ("FLOAT32", "f32"),
        ("FLOAT32SWAP", "f32_wswap"),
        ("INT64", "i64"),
        ("UINT64", "u64"),
        ("INT64SWAP", "i64_wswap"),
        ("UINT64SWAP", "u64_wswap"),
        ("FLOAT64", "f64"),
        ("FLOAT64SWAP", "f64_wswap"),
        ("BCD16", "bcd16"),
        ("BCD32", "bcd32"),
        ("BCD32SWAP", "bcd32_wswap"),
        ("CHARSTRING", "char"),
        ("VARCHARSTRING", "varchar"),
        ("INT32M10K", "i32_m10k"),
        ("UINT32M10K", "u32_m10k"),
        ("INT32M10KSWAP", "i32_m10k_wswap"),
        ("UINT32M10KSWAP", "u32_m10k_wswap"),
    ];
    let all = TYPES.iter().copied();
    let mut points = serde_json::Map::new();
    for (i, (name, _)) in all.clone().enumerate() {
        points.insert(
            format!("P{i}"),
            dsa_point(json!({"@data type": name, "@number of registers": 4, "@offset": i * 4})),
        );
    }
    let c = conv(&one_device(Json::Object(points)));
    assert_eq!(dropped(&c), vec![]);
    for (i, (name, ours)) in all.enumerate() {
        let p = node(&c, &format!("C/D/P{i}"));
        assert_eq!(param(p, "dtype"), &Value::from(ours), "{name}");
    }
    let c = conv(&one_device(json!({
        "Bit": dsa_point(json!({"@data type": "BOOLEAN", "@bit": 3})),
        "Coil": dsa_point(json!({"@type": "COIL", "@data type": "UINT16"})),
        "Lower": dsa_point(json!({"@data type": "uint16"})),
        "Wide": dsa_point(json!({"@data type": "BOOLEAN", "@bit": 16})),
        "Odd": dsa_point(json!({"@data type": "INT128"})),
    })));
    let bit = node(&c, "C/D/Bit");
    assert_eq!(param(bit, "dtype"), &Value::from("binary"));
    assert_eq!(param(bit, "bit"), &Value::UInt(3));
    // Coil and discrete hold bits whatever the data type says
    // (SlaveFolder.java:317-319).
    assert_eq!(param(node(&c, "C/D/Coil"), "dtype"), &Value::from("binary"));
    assert_eq!(param(node(&c, "C/D/Lower"), "dtype"), &Value::from("u16"));
    assert_eq!(
        dropped(&c),
        owned(&[("C/D/Odd", "data type"), ("C/D/Wide", "bit")])
    );
    assert!(reason(&c, "C/D/Odd", "data type").contains("INT128"));
}

/// DSA folders become folders (at most 4 deep; a deeper chain lands in the
/// 4th, reported). A point id is unique on the device, so the same DSA
/// name in two folders gets a suffix; names our tree reserves too.
#[tokio::test(flavor = "multi_thread")]
async fn folders_kept() {
    let c = conv(&fixture());
    let diag = node(&c, "Plant_TCP/Meter_1/Diagnostics");
    assert_eq!(diag.level, Level::Folder);
    let mut names: Vec<&str> = diag.children.iter().map(|n| n.name.as_str()).collect();
    names.sort();
    assert_eq!(names, ["Fault", "Run_Hours", "Temperature"]);

    let p = |a: u64| dsa_point(json!({"@offset": a}));
    let f = |inner: Json| {
        let mut m = json!({"$is": "node", "@restoreType": "folder"});
        for (k, v) in inner.as_object().unwrap() {
            m[k] = v.clone();
        }
        m
    };
    let deep = f(json!({"F2": f(json!({"F3": f(json!({"F4": f(json!({
        "P4": p(4),
        "F5": f(json!({"P5": p(5), "F6": f(json!({"P6": p(6)}))})),
    }))}))}))}));
    let j = one_device(json!({
        "F1": deep,
        "A": f(json!({"Temp": p(10)})),
        "B": f(json!({"Temp": p(11)})),
        "requests": p(12),
        "export": f(json!({"status": p(13)})),
    }));
    let c = conv(&j);
    let f4 = node(&c, "C/D/F1/F2/F3/F4");
    let mut names: Vec<&str> = f4.children.iter().map(|n| n.name.as_str()).collect();
    names.sort();
    assert_eq!(names, ["P4", "P5", "P6"], "flattened into the 4th folder");
    assert!(f4.children.iter().all(|n| n.level == Level::Point));
    assert_eq!(
        dropped(&c),
        owned(&[
            ("C/D/F1/F2/F3/F4/F5", "folder"),
            ("C/D/F1/F2/F3/F4/F5/F6", "folder")
        ])
    );
    let temps: Vec<&str> = ["C/D/A", "C/D/B"]
        .iter()
        .map(|f| node(&c, f).children[0].name.as_str())
        .collect();
    assert!(
        temps == ["Temp", "Temp_2"] || temps == ["Temp_2", "Temp"],
        "{temps:?}"
    );
    assert!(find(&c, "C/D/requests_2").is_some());
    assert!(find(&c, "C/D/export_2/status_2").is_some());
    let renamed: Vec<(String, String)> = entries(&c, "renamed")
        .iter()
        .map(|m| (s(m, "from"), s(m, "to")))
        .collect();
    assert!(renamed.contains(&("C/D/requests".into(), "C/D/requests_2".into())));

    // Both import through the link: the framework takes every name.
    let h = H::start(Tree(Value::Null)).await;
    import(&h, &fixture()).await;
    assert!(h
        .meta("Plant_TCP/Meter_1/Diagnostics/Temperature")
        .await
        .1
        .is_some());
    import(&h, &j).await;
    assert!(h.meta("C/D/F1/F2/F3/F4/P6").await.1.is_some());
    assert!(h.meta("C/D/export_2/status_2").await.1.is_some());
    h.stop().await;
}

/// The DSA polling interval is a device attribute in ms
/// (`IpConnection.java:173-181`); ours is `poll_s` on each point.
#[test]
fn poll_interval_moves_to_points() {
    let c = conv(&fixture());
    let meter = node(&c, "Plant_TCP/Meter_1");
    assert!(!meter.params.contains_key("poll_s"));
    for p in [
        "Plant_TCP/Meter_1/Setpoint",
        "Plant_TCP/Meter_1/Alarm",
        "Plant_TCP/Meter_1/Diagnostics/Temperature",
    ] {
        assert_eq!(f64_of(param(node(&c, p), "poll_s")), 5.0, "{p}");
    }
    assert_eq!(
        f64_of(param(node(&c, "Line_2_RS485/VFD_7/Speed"), "poll_s")),
        2.5
    );
    let mut j = one_device(json!({"P": dsa_point(json!({}))}));
    j["C"]["D"]["@polling interval"] = json!(5);
    let c = conv(&j);
    assert_eq!(f64_of(param(node(&c, "C/D/P"), "poll_s")), 0.01);
    assert_eq!(dropped(&c), owned(&[("C/D", "polling interval")]));
}

/// Ruling 14: Modbus UDP and ASCII are not supported; such a connection is
/// imported (as TCP, as RTU) disabled, with the reason in `disabled`.
#[test]
fn transport_udp_or_ascii_reported() {
    let c = conv(&fixture());
    assert_eq!(entries(&c, "disabled"), vec![]);
    let mut j = fixture();
    j["Plant TCP"]["@transport type"] = json!("UDP");
    j["Line 2 RS485"]["@transport type"] = json!("ASCII");
    let c = conv(&j);
    let ip = node(&c, "Plant_TCP");
    assert!(!ip.enabled);
    assert_eq!(param(ip, "kind"), &Value::from("ip_connection"));
    assert_eq!(param(ip, "transport"), &Value::from("tcp"));
    let serial = node(&c, "Line_2_RS485");
    assert!(!serial.enabled);
    assert_eq!(param(serial, "kind"), &Value::from("serial_connection"));
    let disabled: BTreeMap<String, String> = entries(&c, "disabled")
        .iter()
        .map(|m| (s(m, "path"), s(m, "reason")))
        .collect();
    assert_eq!(disabled.len(), 2, "{disabled:?}");
    assert!(disabled["Plant_TCP"].contains("UDP"));
    assert!(disabled["Line_2_RS485"].contains("ASCII"));
}

/// Parity MARK/SPACE (ruling 14) and unit 0 on RTU (P3) do not work as
/// imported either: disabled with the reason.
#[test]
fn parity_mark_and_rtu_unit_0_are_disabled() {
    let mut j = fixture();
    j["Line 2 RS485"]["@parity"] = json!("MARK");
    j["Line 2 RS485"]["VFD 7"]["@slave id"] = json!(0);
    let c = conv(&j);
    let serial = node(&c, "Line_2_RS485");
    assert!(!serial.enabled);
    assert_eq!(param(serial, "parity"), &Value::from("none"));
    let vfd = node(&c, "Line_2_RS485/VFD_7");
    assert!(!vfd.enabled);
    assert_eq!(param(vfd, "unit"), &Value::UInt(0));
    let paths: Vec<String> = entries(&c, "disabled")
        .iter()
        .map(|m| s(m, "path"))
        .collect();
    assert_eq!(paths, ["Line_2_RS485", "Line_2_RS485/VFD_7"]);
    // Unit 0 on Modbus TCP is an ordinary unit (ruling 2).
    let mut j = fixture();
    j["Plant TCP"]["Meter 1"]["@slave id"] = json!(0);
    assert!(node(&conv(&j), "Plant_TCP/Meter_1").enabled);
}

/// Ruling 14: "zero on failed poll" is not done (honest quality instead);
/// a device with it set is imported and the setting reported as dropped.
#[test]
fn zero_on_failed_poll_reported_as_dropped() {
    let c = conv(&fixture());
    assert!(find(&c, "Line_2_RS485/VFD_7").is_some());
    let r = reason(&c, "Line 2 RS485/VFD 7", "zero on failed poll");
    assert!(r.contains("quality"), "{r}");
    assert!(!dropped(&c).contains(&("Plant TCP/Meter 1".into(), "zero on failed poll".into())));
}

/// Everything not mapped is in `dropped` (path in DSA names, the DSA
/// attribute, why), and nothing else is.
#[test]
fn report_lists_every_drop() {
    let c = conv(&fixture());
    assert_eq!(
        dropped(&c),
        owned(&[
            ("Line 2 RS485", "max write register count"),
            ("Line 2 RS485/VFD 7", "zero on failed poll"),
            ("Line 2 RS485/VFD 7/Ratio", "scaling"),
            ("Plant TCP", "max write register count"),
        ])
    );
    // What was mapped instead of dropped.
    let serial = node(&c, "Line_2_RS485");
    assert_eq!(param(serial, "write_mode"), &Value::from("single"));
    assert_eq!(param(serial, "parity"), &Value::from("even"));
    assert_eq!(param(serial, "retries"), &Value::UInt(1));
    assert_eq!(param(serial, "timeout_ms"), &Value::UInt(1000));
    let vfd = node(&c, "Line_2_RS485/VFD_7");
    assert_eq!(param(vfd, "max_regs"), &Value::UInt(1), "batch polling off");
    assert_eq!(param(vfd, "max_bits"), &Value::UInt(1));
    assert_eq!(param(vfd, "contiguous_only"), &Value::Bool(true));
    assert_eq!(f64_of(param(vfd, "republish_s")), 1.25, "0 = every poll");
    let meter = node(&c, "Plant_TCP/Meter_1");
    assert_eq!(param(meter, "max_regs"), &Value::UInt(125));
    assert_eq!(f64_of(param(meter, "republish_s")), 60.0);
    assert_eq!(
        param(node(&c, "Plant_TCP"), "write_mode"),
        &Value::from("auto")
    );
    let renamed: Vec<(String, String)> = entries(&c, "renamed")
        .iter()
        .map(|m| (s(m, "from"), s(m, "to")))
        .collect();
    assert!(renamed.contains(&("Plant TCP".into(), "Plant_TCP".into())));
    assert!(renamed.contains(&(
        "Plant TCP/Meter 1/Serial No".into(),
        "Plant_TCP/Meter_1/Serial_No".into()
    )));

    // Every kind of drop at once.
    let mut j = one_device(json!({
        "W": dsa_point(json!({"@type": "INPUT", "@writable": true})),
        "M": dsa_point(json!({})),
        "X": {"$is": "node", "$type": "number"},
        "Device Status": {"$is": "node", "$type": "string", "?value": "Ready"},
    }));
    j["C"]["D"]["M"].as_object_mut().unwrap().remove("@scaling");
    j["C"]["D"]["@zero on failed poll"] = json!(true);
    j["C"]["D"]["@suppress non-cov update duration"] = json!(7_200_000);
    let k = &mut j["C"];
    k["@Timeout"] = json!(50);
    k["@retries"] = json!(9);
    k["@discard data delay"] = json!(10);
    k["@max write register count"] = json!(120);
    k["@max read register count"] = json!(500);
    k["@use multiple write commands"] = json!("Sometimes");
    k["U"] = json!({"$is": "node", "@restoreType": "folder", "@slave id": 300, "@polling interval": 1000});
    j["Slave"] = json!({"$is": "node", "@restoreType": "editable folder", "@transport type": "TCP", "@port": 1025, "@slave id": 1});
    j["Junk"] = json!({"$is": "node"});
    let c = conv(&j);
    assert_eq!(
        dropped(&c),
        owned(&[
            ("C", "Timeout"),
            ("C", "discard data delay"),
            ("C", "max read register count"),
            ("C", "max write register count"),
            ("C", "retries"),
            ("C", "use multiple write commands"),
            ("C/D", "suppress non-cov update duration"),
            ("C/D", "zero on failed poll"),
            ("C/D/M", "scaling"),
            ("C/D/W", "writable"),
            ("C/D/X", "restoreType"),
            ("C/U", "slave id"),
            ("Junk", "restoreType"),
            ("Slave", "restoreType"),
        ])
    );
    let conn = node(&c, "C");
    assert_eq!(param(conn, "timeout_ms"), &Value::UInt(100));
    assert_eq!(param(conn, "retries"), &Value::UInt(5));
    assert_eq!(param(conn, "write_mode"), &Value::from("auto"));
    assert_eq!(param(node(&c, "C/D"), "max_regs"), &Value::UInt(125));
    assert_eq!(f64_of(param(node(&c, "C/D"), "republish_s")), 3600.0);
    assert_eq!(param(node(&c, "C/D/W"), "writable"), &Value::Bool(false));
    assert!(find(&c, "C/U").is_none() && find(&c, "C/D/M").is_none());

    // A serial connection without the attributes DSA needs to load it
    // (`ModbusLink.java:391-393`): our defaults, each reported.
    let mut j = fixture();
    let line = j["Line 2 RS485"].as_object_mut().unwrap();
    for k in ["@baud rate", "@data bits", "@stop bits", "@parity"] {
        line.remove(k);
    }
    let c = conv(&j);
    let serial = node(&c, "Line_2_RS485");
    assert_eq!(param(serial, "parity"), &Value::from("none"));
    assert!(!serial.params.contains_key("baud_rate"), "the default");
    let line: Vec<(String, String)> = dropped(&c)
        .into_iter()
        .filter(|(p, _)| p == "Line 2 RS485")
        .collect();
    assert_eq!(
        line,
        owned(&[
            ("Line 2 RS485", "baud rate"),
            ("Line 2 RS485", "data bits"),
            ("Line 2 RS485", "max write register count"),
            ("Line 2 RS485", "parity"),
            ("Line 2 RS485", "stop bits"),
        ])
    );
}

/// The export of one DSA connection (`ModbusConnection.java:342-353`: the
/// node itself, without its name) needs `name`; `name` renames the only
/// connection of a whole file and is refused for several.
#[test]
fn one_connection_export_takes_a_name() {
    let one = fixture()["Plant TCP"].to_string();
    let c = dsa::convert(&one, Some("plant")).unwrap();
    assert_eq!(c.connections.len(), 1);
    assert!(find(&c, "plant/Meter_1/Setpoint").is_some());
    let e = dsa::convert(&one, None).unwrap_err();
    assert!(e.message.contains("name"), "{}", e.message);
    let e = dsa::convert(&fixture().to_string(), Some("x")).unwrap_err();
    assert!(e.message.contains("name"), "{}", e.message);
    let c = dsa::convert(&one_device(json!({})).to_string(), Some("only")).unwrap();
    assert!(find(&c, "only/D").is_some());
    assert!(dsa::convert("[]", None).is_err());
    assert!(dsa::convert("{", None).is_err());
}

/// The two-tier project of old DSA versions: an IP device at the top with
/// the connection's attributes (`ModbusLink.java:399-436`); devices on the
/// same host and port share one connection (`IpConnectionWithDevice`).
#[test]
fn legacy_ip_devices_share_a_connection() {
    let dev = |id: u64, host: &str| {
        json!({
            "$is": "node",
            "@restoreType": "folder",
            "@transport type": "TCP",
            "@host": host,
            "@port": 502,
            "@slave id": id,
            "@polling interval": 1000,
            "@Timeout": 700,
            "@retries": 0,
            "@max read bit count": 2000,
            "@max read register count": 125,
            "@max write register count": 120,
            "@discard data delay": 0,
            "@use multiple write commands": "Always",
            "P": dsa_point(json!({})),
        })
    };
    let j = json!({"A": dev(1, "h1"), "B": dev(2, "h1"), "Z": dev(3, "h2")});
    let c = conv(&j);
    let names: Vec<&str> = c.connections.iter().map(|n| n.name.as_str()).collect();
    assert_eq!(names, ["A", "Z"]);
    let a = node(&c, "A");
    assert_eq!(param(a, "host"), &Value::from("h1"));
    assert_eq!(param(a, "timeout_ms"), &Value::UInt(700));
    assert_eq!(param(a, "write_mode"), &Value::from("multiple"));
    assert_eq!(param(node(&c, "A/B"), "unit"), &Value::UInt(2));
    assert!(find(&c, "A/A/P").is_some() && find(&c, "Z/Z/P").is_some());
}
