//! A slave listening beyond loopback (ruling 15): logged at warn and shown
//! on the connection's `status` leaf. Its own test binary: the log capture
//! is the process's global subscriber (the owner task logs on any thread).

use std::fmt::Write as _;
use std::sync::Mutex;
use std::time::Duration;
use tokio_modbus::client::tcp;
use tokio_modbus::prelude::Reader;
use tokio_modbus::{ExceptionCode, Slave};
use tracing_subscriber::layer::{Context, SubscriberExt};
use tracing_subscriber::Layer;
use wyrm_core::{Perm, Status, Value};
use wyrm_link_modbus::Modbus;
use wyrm_link_sdk::driver::Tree;
use wyrm_link_sdk::TestHarness;

type H = TestHarness<Modbus>;

/// Warnings logged, as `field=value` text.
static WARNINGS: Mutex<Vec<String>> = Mutex::new(Vec::new());

struct Capture;

struct Text(String);

impl tracing::field::Visit for Text {
    fn record_debug(&mut self, f: &tracing::field::Field, v: &dyn std::fmt::Debug) {
        let _ = write!(self.0, "{}={v:?} ", f.name());
    }
}

impl<S: tracing::Subscriber> Layer<S> for Capture {
    fn on_event(&self, e: &tracing::Event<'_>, _: Context<'_, S>) {
        if *e.metadata().level() == tracing::Level::WARN {
            let mut t = Text(String::new());
            e.record(&mut t);
            WARNINGS.lock().unwrap().push(t.0);
        }
    }
}

fn map(kv: &[(&str, Value)]) -> Value {
    Value::Map(
        kv.iter()
            .map(|(k, v)| ((*k).to_owned(), v.clone()))
            .collect(),
    )
}

fn free_port() -> u16 {
    std::net::TcpListener::bind("127.0.0.1:0")
        .and_then(|l| l.local_addr())
        .map(|a| a.port())
        .expect("a free port")
}

fn slave(host: &str, port: u16) -> Value {
    map(&[
        ("kind", "ip_slave".into()),
        ("listen_host", host.into()),
        ("listen_port", Value::UInt(port.into())),
    ])
}

fn connected(h: &H, conn: &str) -> bool {
    h.ctx().last(&format!("{conn}/status")).map(|s| s.v) == Some(Value::UInt(2))
}

async fn wait(what: &str, mut f: impl FnMut() -> bool) {
    let deadline = tokio::time::Instant::now() + Duration::from_secs(10);
    while !f() {
        assert!(tokio::time::Instant::now() < deadline, "timeout: {what}");
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
}

async fn warning(h: &H, conn: &str) -> Option<Value> {
    let (_, meta) = h.meta(&format!("{conn}/status")).await;
    meta.and_then(|m| m.attr_value("warning").cloned())
}

#[tokio::test(flavor = "multi_thread")]
async fn non_loopback_listen_is_flagged() {
    tracing::subscriber::set_global_default(tracing_subscriber::registry().with(Capture))
        .expect("the only subscriber");
    let (wide, local) = (free_port(), free_port());
    let tree = Tree(map(&[(
        "connections",
        map(&[
            ("open", slave("0.0.0.0", wide)),
            ("lo", slave("127.0.0.1", local)),
        ]),
    )]));
    let h = H::start(tree).await;
    wait("both listening", || {
        connected(&h, "open") && connected(&h, "lo")
    })
    .await;

    let Some(Value::Str(note)) = warning(&h, "open").await else {
        panic!("no warning on open/status");
    };
    assert!(note.contains("not loopback"), "{note}");
    assert!(note.contains("no authentication"), "{note}");
    assert_eq!(warning(&h, "lo").await, None, "loopback: no warning");
    let logged: Vec<String> = WARNINGS
        .lock()
        .unwrap()
        .iter()
        .filter(|w| w.contains("not loopback"))
        .cloned()
        .collect();
    assert_eq!(logged.len(), 1, "{logged:?}");
    assert!(logged[0].contains("conn=open"), "{logged:?}");

    // back to loopback: the warning goes
    let edit = map(&[
        ("listen_host", "127.0.0.1".into()),
        ("listen_port", Value::UInt(wide.into())),
    ]);
    let r = h
        .invoke("open", "edit", edit, Some(h.ptok(Perm::Config)))
        .await;
    assert_eq!(
        r[0].att.status,
        Some(wyrm_core::status::StatusCode::Known(Status::Ok))
    );
    // The new listener answers (no device: exception 0x0B), so its owner
    // has opened and shown a note if it had one.
    let deadline = tokio::time::Instant::now() + Duration::from_secs(10);
    loop {
        let addr = std::net::SocketAddr::from(([127, 0, 0, 1], wide));
        if let Ok(mut m) = tcp::connect_slave(addr, Slave(1)).await {
            let r = tokio::time::timeout(Duration::from_secs(1), m.read_holding_registers(0, 1));
            if let Ok(Ok(Err(ExceptionCode::GatewayTargetDevice))) = r.await {
                break;
            }
        }
        assert!(
            tokio::time::Instant::now() < deadline,
            "timeout: listening on loopback"
        );
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
    assert!(connected(&h, "open"));
    assert_eq!(warning(&h, "open").await, None);
    h.stop().await;
}
