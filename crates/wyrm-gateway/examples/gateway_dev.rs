//! Development gateway for SDK tests (Dart `wyrm_client`): one isolated
//! Zenoh session (no network), the mock link, and the gateway on
//! `127.0.0.1:<port>` with a known admin user.
//!
//! ```text
//! cargo run -p wyrm-gateway --example gateway_dev [-- --port 0]
//! ```
//! Prints `PORT=<n>` on stdout when it serves. Exits when stdin closes
//! (so a crashed test leaves no process behind) or on a line `quit`.
//!
//! Site `test`, link `mock` (6 writable points at 20 Hz on `g0`, `g1`;
//! root actions `reset`, `count {n}`), admin user `admin` / `admin password`.
//! For tests only: the state directory is a fresh temp directory.

use std::io::{BufRead, Write};
use std::time::Duration;
use wyrm_gateway::{Gateway, GatewayConfig};
use wyrm_link_mock::{Mock, MockConfig};
use wyrm_link_sdk::harness::{isolated_config, SITE};
use wyrm_link_sdk::LinkConfig;

const ADMIN_USER: &str = "admin";
const ADMIN_PASSWORD: &str = "admin password";

#[tokio::main(flavor = "multi_thread", worker_threads = 2)]
async fn main() -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let mut port = 0u16;
    let mut args = std::env::args().skip(1);
    while let Some(a) = args.next() {
        match a.as_str() {
            "--port" => port = args.next().ok_or("--port needs a value")?.parse()?,
            other => return Err(format!("unknown argument {other}").into()),
        }
    }
    let dir = std::env::temp_dir().join(format!("wyrm-gateway-dev-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);

    let cfg = GatewayConfig::new(SITE, &dir, ([127, 0, 0, 1], port).into());
    let gw = Gateway::open(cfg, b"gateway dev state key")?;
    gw.ensure_admin(ADMIN_USER, ADMIN_PASSWORD)?;

    let session = zenoh::open(isolated_config()).await?;
    let mut lc = LinkConfig::new(SITE, "mock");
    lc.admin_keys = vec![gw.verifying_key()];
    lc.answer_val = true;
    let mock = MockConfig {
        points: 6,
        rate_hz: 20.0,
        depth: 1,
        fanout: 2,
        writable: true,
    };
    let link = wyrm_link_sdk::spawn::<Mock>(session.clone(), lc, mock).await?;

    // stdin EOF or `quit` → stop.
    let (stop_tx, stop_rx) = tokio::sync::oneshot::channel::<()>();
    std::thread::spawn(move || {
        for line in std::io::stdin().lock().lines() {
            match line {
                Ok(l) if l.trim() == "quit" => break,
                Ok(_) => {}
                Err(_) => break,
            }
        }
        let _ = stop_tx.send(());
    });

    let server = tokio::spawn(gw.clone().serve(session.clone(), async {
        let _ = stop_rx.await;
    }));
    let addr = tokio::time::timeout(Duration::from_secs(10), gw.local_addr()).await?;
    {
        let mut out = std::io::stdout().lock();
        writeln!(out, "PORT={}", addr.port())?;
        out.flush()?;
    }
    server.await??;
    link.stop().await;
    let _ = session.close().await;
    let _ = std::fs::remove_dir_all(&dir);
    Ok(())
}
