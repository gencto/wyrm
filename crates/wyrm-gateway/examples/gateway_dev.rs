//! Development gateway for SDK tests (Dart `wyrm_client`): one isolated
//! Zenoh session (no network), the mock link, and the gateway on
//! `127.0.0.1:<port>` with a known admin user.
//!
//! ```text
//! cargo run -p wyrm-gateway --example gateway_dev [-- --port 0]
//! ```
//! `--step-up config` asks for a fresh confirmation before config changes
//! (ADR 0050 §1.3), and `--fresh-s <n>` shortens how long a login or a
//! confirmation counts as fresh (default 300 s), for the device tests.
//! Prints `PORT=<n>` on stdout when it serves. Exits when stdin closes
//! (so a crashed test leaves no process behind) or on a line `quit`. A line
//! `restart` closes every socket and serves again on the same port, as
//! `wyrmd` does when it rebuilds its router.
//!
//! Site `test`, link `mock` (6 writable points at 20 Hz on `g0`, `g1`;
//! root actions `reset`, `count {n}`), admin user `admin` / `admin password`.
//! Link `agent`: the AI agent link with a scripted model (no network, no API
//! key). Every `ask` gets the plan `g0/p0 := 42.5`, `g1/p1 := 7`,
//! `expect g0/p0 = 42.5`, `expect g1/p1 = 7`, which waits for approval; an ask
//! that holds `ask me` first asks back with two options (ADR 0049).
//! For tests only: the state directory is a fresh temp directory.

use std::io::{BufRead, Write};
use std::time::Duration;
use wyrm_gateway::{Gateway, GatewayConfig, StepUp};
use wyrm_link_mock::{Mock, MockConfig};
use wyrm_link_sdk::harness::{isolated_config, SITE};
use wyrm_link_sdk::LinkConfig;

/// The model of the `agent` link: the same plan for every ask, then a summary; a question
/// first when the ask holds `ask me`.
struct Scripted;

impl wyrm_link_agent::llm::LlmClient for Scripted {
    fn messages(&self, body: serde_json::Value) -> wyrm_link_agent::llm::LlmFuture<'_> {
        use serde_json::json;
        let usage = json!({"input_tokens": 10, "output_tokens": 10});
        let messages = body["messages"].as_array().cloned().unwrap_or_default();
        let asks = messages
            .first()
            .and_then(|m| m["content"].as_str())
            .is_some_and(|t| t.contains("ask me"));
        // the turns the model has had so far
        let turn = messages.len() / 2;
        let tools = |calls: Vec<serde_json::Value>| json!({"content": calls, "stop_reason": "tool_use", "usage": usage});
        let call = |id: &str, name: &str, input: serde_json::Value| json!({"type": "tool_use", "id": id, "name": name, "input": input});
        let r = match (asks, turn) {
            (true, 0) => tools(vec![call(
                "q1",
                "ask_user",
                json!({"question": "Which branch first?", "options": [
                    {"id": "g0", "label": "g0", "detail": "downstream/mock/g0"},
                    {"id": "g1", "label": "g1", "detail": "downstream/mock/g1"},
                ]}),
            )]),
            (true, 1) | (false, 0) => tools(vec![
                call(
                    "t1",
                    "propose",
                    json!({"op": "set", "path": "downstream/mock/g0/p0", "value": 42.5, "reason": "the operator asked"}),
                ),
                call(
                    "t2",
                    "propose",
                    json!({"op": "set", "path": "downstream/mock/g1/p1", "value": 7, "reason": "the operator asked"}),
                ),
                call(
                    "t3",
                    "propose",
                    json!({"op": "expect", "path": "downstream/mock/g0/p0", "equals": 42.5, "timeout_s": 5}),
                ),
                call(
                    "t4",
                    "propose",
                    json!({"op": "expect", "path": "downstream/mock/g1/p1", "equals": 7, "timeout_s": 5}),
                ),
            ]),
            _ => {
                json!({"content": [{"type": "text", "text": "Plan: set two points and prove it."}],
                        "stop_reason": "end_turn", "usage": usage})
            }
        };
        Box::pin(async move { Ok(r) })
    }
}

const ADMIN_USER: &str = "admin";
const ADMIN_PASSWORD: &str = "admin password";

#[tokio::main(flavor = "multi_thread", worker_threads = 2)]
async fn main() -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let mut port = 0u16;
    let mut step_up = StepUp::None;
    let mut fresh_s = None;
    let mut args = std::env::args().skip(1);
    while let Some(a) = args.next() {
        match a.as_str() {
            "--port" => port = args.next().ok_or("--port needs a value")?.parse()?,
            "--step-up" => {
                step_up = match args.next().as_deref() {
                    Some("config") => StepUp::Config,
                    Some("none") => StepUp::None,
                    _ => return Err("--step-up config | none".into()),
                }
            }
            "--fresh-s" => fresh_s = Some(args.next().ok_or("--fresh-s needs a value")?.parse()?),
            other => return Err(format!("unknown argument {other}").into()),
        }
    }
    if port == 0 {
        // the same port after a restart
        port = std::net::TcpListener::bind(("127.0.0.1", 0))?
            .local_addr()?
            .port();
    }
    let dir = std::env::temp_dir().join(format!("wyrm-gateway-dev-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);

    let mut cfg = GatewayConfig::new(SITE, &dir, ([127, 0, 0, 1], port).into());
    cfg.devices.step_up = step_up;
    if let Some(s) = fresh_s {
        cfg.devices.fresh_s = s;
    }
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
    gw.set_agent_links(vec!["agent".into()]);
    let mut lc = LinkConfig::new(SITE, "agent");
    lc.admin_keys = vec![gw.verifying_key()];
    lc.answer_val = true;
    let agent = wyrm_link_sdk::spawn::<wyrm_link_agent::Agent>(
        session.clone(),
        lc,
        wyrm_link_agent::AgentConfig {
            params: wyrm_link_agent::AgentParams {
                allowed_prefixes: vec!["downstream/mock".into()],
                ..Default::default()
            },
            llm: Some(std::sync::Arc::new(Scripted)),
        },
    )
    .await?;

    // stdin: `restart` → true; EOF or `quit` → false.
    let (cmd_tx, mut cmd_rx) = tokio::sync::mpsc::unbounded_channel::<bool>();
    std::thread::spawn(move || {
        for line in std::io::stdin().lock().lines() {
            match line.as_deref().map(str::trim) {
                Ok("quit") | Err(_) => break,
                Ok("restart") => {
                    let _ = cmd_tx.send(true);
                }
                Ok(_) => {}
            }
        }
        let _ = cmd_tx.send(false);
    });

    let mut first = true;
    loop {
        let (stop_tx, stop_rx) = tokio::sync::oneshot::channel::<()>();
        let server = tokio::spawn(gw.clone().serve(session.clone(), async {
            let _ = stop_rx.await;
        }));
        if first {
            first = false;
            let addr = tokio::time::timeout(Duration::from_secs(10), gw.local_addr()).await?;
            let mut out = std::io::stdout().lock();
            writeln!(out, "PORT={}", addr.port())?;
            out.flush()?;
        }
        let restart = cmd_rx.recv().await.unwrap_or(false);
        let _ = stop_tx.send(());
        server.await??;
        if !restart {
            break;
        }
    }
    agent.stop().await;
    link.stop().await;
    let _ = session.close().await;
    let _ = std::fs::remove_dir_all(&dir);
    Ok(())
}
