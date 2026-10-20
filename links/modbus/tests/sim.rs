//! Driver against the in-process Modbus TCP simulator.

use std::time::Duration;
use wyrm_core::{Perm, Quality, Status, Value};
use wyrm_link_modbus::{sim, DataKind, Modbus, ModbusConfig, PointConfig, Table};
use wyrm_link_sdk::TestHarness;

fn point(path: &str, table: Table, address: u16, kind: DataKind) -> PointConfig {
    PointConfig {
        path: path.into(),
        table,
        address,
        kind,
        scale: 1.0,
        offset: 0.0,
        writable: false,
        unit: None,
        word_swap: false,
    }
}

fn config(port: u16) -> ModbusConfig {
    ModbusConfig {
        host: "127.0.0.1".into(),
        port,
        unit: 1,
        poll_ms: 30,
        timeout_ms: 200,
        stale_cycles: 2,
        points: vec![
            PointConfig {
                scale: 0.1,
                unit: Some("°C".into()),
                ..point("ahu1/supply_temp", Table::Input, 1, DataKind::I16)
            },
            PointConfig {
                writable: true,
                ..point("ahu1/setpoint", Table::Holding, 10, DataKind::F32)
            },
            PointConfig {
                writable: true,
                ..point("ahu1/fan", Table::Coil, 3, DataKind::Bool)
            },
            point("ahu1/counter", Table::Holding, 20, DataKind::U32),
            point("ahu1/missing", Table::Holding, 5000, DataKind::U16),
        ],
    }
}

fn status(a: &wyrm_core::Attachment) -> Option<Status> {
    match a.status? {
        wyrm_core::status::StatusCode::Known(s) => Some(s),
        _ => None,
    }
}

async fn wait_for(h: &TestHarness<Modbus>, path: &str, f: impl Fn(&wyrm_core::Sample) -> bool) {
    let deadline = tokio::time::Instant::now() + Duration::from_secs(3);
    loop {
        if h.ctx().last(path).is_some_and(|s| f(&s)) {
            return;
        }
        assert!(
            tokio::time::Instant::now() < deadline,
            "timeout waiting for {path}: {:?}",
            h.ctx().last(path)
        );
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn poll_write_and_comm_fail() {
    let (addr, dev, task) = sim::spawn("127.0.0.1:0").await.unwrap();
    {
        let mut t = dev.lock().unwrap();
        t.input[1] = (-25i16) as u16; // -2.5 °C after scale
        t.holding[20] = 1;
        t.holding[21] = 4464; // 70000
    }
    let h = TestHarness::<Modbus>::start(config(addr.port())).await;
    let (_, kids) = h.list("ahu1").await;
    assert_eq!(kids.len(), 5);

    wait_for(&h, "ahu1/supply_temp", |s| {
        s.v == Value::Float(-2.5) && s.q == Quality::Good
    })
    .await;
    wait_for(&h, "ahu1/counter", |s| s.v == Value::Float(70000.0)).await;
    wait_for(&h, "ahu1/missing", |s| s.q == Quality::Bad).await;

    // device changes are picked up
    dev.lock().unwrap().input[1] = 215;
    wait_for(&h, "ahu1/supply_temp", |s| s.v == Value::Float(21.5)).await;

    // writes reach the device and are read back
    let att = h
        .set("ahu1/setpoint", 22.25, Some(h.ptok(Perm::Write)))
        .await;
    assert_eq!(status(&att), Some(Status::Ok), "{att:?}");
    let words = {
        let t = dev.lock().unwrap();
        [t.holding[10], t.holding[11]]
    };
    assert_eq!(DataKind::F32.decode(&words, false), Some(22.25));
    assert_eq!(
        h.ctx().last("ahu1/setpoint").unwrap().v,
        Value::Float(22.25)
    );
    let att = h.set("ahu1/fan", true, Some(h.ptok(Perm::Write))).await;
    assert_eq!(status(&att), Some(Status::Ok));
    assert!(dev.lock().unwrap().coils[3]);
    // read-only point: refused by the SDK before the driver
    let att = h.set("ahu1/counter", 1.0, Some(h.ptok(Perm::Config))).await;
    assert_eq!(status(&att), Some(Status::NotSupported));

    // device gone: uncertain/stale first, then bad/comm_fail
    task.abort();
    wait_for(&h, "ahu1/supply_temp", |s| s.q == Quality::Uncertain).await;
    wait_for(&h, "ahu1/supply_temp", |s| s.q == Quality::Bad).await;
    assert_eq!(
        h.ctx().last("ahu1/supply_temp").unwrap().v,
        Value::Float(21.5),
        "value kept"
    );
    let att = h.set("ahu1/fan", false, Some(h.ptok(Perm::Write))).await;
    assert_eq!(status(&att), Some(Status::Disconnected));
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn bad_config_is_refused() {
    let mut cfg = config(1);
    cfg.points.push(point("x", Table::Coil, 0, DataKind::U16));
    assert!(cfg.validate().is_err());
    let mut cfg = config(1);
    cfg.points.push(PointConfig {
        writable: true,
        ..point("y", Table::Input, 0, DataKind::U16)
    });
    assert!(cfg.validate().is_err());
    assert!(config(1).validate().is_ok());
}
