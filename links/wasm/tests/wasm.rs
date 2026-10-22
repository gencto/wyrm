//! The `wasm` driver on the framework: a WAT guest reads a point over TCP
//! within the connection's `net` list (ADR 0012).

#[path = "../../../crates/wyrm-wasm-host/tests/guests/mod.rs"]
mod guests;

use std::io::{Read, Write};
use std::path::PathBuf;
use std::sync::OnceLock;
use std::time::Duration;
use wyrm_core::{Quality, Value};
use wyrm_link_sdk::driver::{Framework, Tree};
use wyrm_link_sdk::TestHarness;
use wyrm_link_wasm::Wasm;

type H = TestHarness<Framework<Wasm>>;

fn map(kv: &[(&str, Value)]) -> Value {
    Value::Map(
        kv.iter()
            .map(|(k, v)| ((*k).to_owned(), v.clone()))
            .collect(),
    )
}

/// The component store of this test process, with the ping guest in it as
/// package `ping`.
fn component() -> &'static str {
    static READY: OnceLock<()> = OnceLock::new();
    READY.get_or_init(|| {
        let root: PathBuf =
            std::env::temp_dir().join(format!("wyrm-wasm-link-{}", std::process::id()));
        std::fs::create_dir_all(&root).unwrap();
        std::fs::write(root.join("ping.wasm"), guests::tcp_ping()).unwrap();
        wyrm_link_wasm::set_component_root(root);
    });
    "ping"
}

/// A device on loopback that answers every request with CBOR uint 42.
fn device() -> u16 {
    let l = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    let port = l.local_addr().unwrap().port();
    std::thread::spawn(move || {
        for s in l.incoming().flatten() {
            std::thread::spawn(move || {
                let mut s = s;
                let mut buf = [0u8; 64];
                while let Ok(n) = s.read(&mut buf) {
                    if n == 0 || s.write_all(&[0x18, 0x2a]).is_err() {
                        return;
                    }
                }
            });
        }
    });
    port
}

fn tree(component: &str, net: &str, port: u16) -> Tree {
    let point = map(&[("poll_s", Value::Float(0.1))]);
    let dev = map(&[("points", map(&[("p", point)]))]);
    let conn = map(&[
        ("component", Value::from(component)),
        ("net", Value::from(net)),
        ("config", Value::from(port.to_string().as_str())),
        ("devices", map(&[("d1", dev)])),
    ]);
    Tree(map(&[("connections", map(&[("c1", conn)]))]))
}

async fn wait(what: &str, mut f: impl FnMut() -> bool) {
    let deadline = tokio::time::Instant::now() + Duration::from_secs(6);
    while !f() {
        assert!(tokio::time::Instant::now() < deadline, "timeout: {what}");
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn reads_a_point_over_the_allowed_network() {
    let port = device();
    let h = H::start(tree(component(), &format!("127.0.0.1:{port}"), port)).await;
    wait("p = 42", || {
        h.ctx()
            .last("c1/d1/p")
            .is_some_and(|s| s.v == Value::UInt(42) && s.q == Quality::Good)
    })
    .await;
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn without_the_network_the_point_goes_bad() {
    let port = device();
    // the list names another port: the component may not connect
    let h = H::start(tree(component(), &format!("127.0.0.1:{}", port ^ 1), port)).await;
    wait("p bad", || {
        h.ctx().last("c1/d1/p").is_some_and(|s| s.q == Quality::Bad)
    })
    .await;
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn an_unknown_component_fails_the_connection() {
    let _ = component();
    let h = H::start(tree("nope", "", 1)).await;
    wait("c1 failed", || {
        matches!(h.ctx().last("c1/status").map(|s| s.v), Some(Value::UInt(i))
            if wyrm_link_sdk::driver::NodeState::NAMES.get(i as usize) == Some(&"failed"))
    })
    .await;
    h.stop().await;
}
