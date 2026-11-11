//! The gateway MCP server (ADR 0041) end to end: a real `wyrm-gateway` over TLS with its own
//! self-signed certificate (the `--gateway-ca` path), the mock link and a link with a
//! config-level point, and an rmcp client over an in-memory pipe.

use rmcp::model::{CallToolRequestParams, ClientConfig};
use rmcp::service::RunningService;
use rmcp::{ClientHandler, RoleClient, ServiceExt};
use serde_json::{json, Value as Json};
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::oneshot;
use wyrm_core::meta::Writable;
use wyrm_core::{NodeMeta, Quality, Value};
use wyrm_gateway::{Gateway, GatewayConfig};
use wyrm_gateway_client::Endpoint;
use wyrm_link_mock::{Mock, MockConfig};
use wyrm_link_sdk::harness::{isolated_config, SITE};
use wyrm_link_sdk::{now_us, Caller, Link, LinkConfig, LinkCtx, LinkHandle};
use wyrm_mcp::gateway::{GatewayMcp, GatewayOptions};
use zeroize::Zeroizing;

/// One config-level point `sp`.
struct Plant {
    ctx: LinkCtx,
}

impl Link for Plant {
    const NAME: &'static str = "plant";
    const VERSION: &'static str = "0.0.0";
    type Config = ();

    async fn start(_cfg: (), ctx: LinkCtx) -> wyrm_link_sdk::Result<Self> {
        ctx.declare_node("sp", NodeMeta::number().writable(Writable::Config))
            .await?;
        ctx.update("sp", 20.0, Quality::Good, now_us()).await?;
        Ok(Self { ctx })
    }

    async fn on_set(&mut self, path: &str, v: Value, _who: &Caller) -> wyrm_link_sdk::Result<()> {
        self.ctx.update(path, v, Quality::Good, now_us()).await
    }
}

#[derive(Clone, Default)]
struct TestClient;

impl ClientHandler for TestClient {
    fn get_info(&self) -> ClientConfig {
        ClientConfig::default()
    }
}

struct Env {
    url: String,
    ca: PathBuf,
    stop: Option<oneshot::Sender<()>>,
    mock: Option<LinkHandle<Mock>>,
    plant: Option<LinkHandle<Plant>>,
}

impl Env {
    async fn start(name: &str) -> Self {
        let dir = std::env::temp_dir().join(format!("wyrm-mcp-gw-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let ck = rcgen::generate_simple_self_signed(vec!["localhost".into()]).unwrap();
        let (cert, key, ca) = (dir.join("gw.pem"), dir.join("gw.key"), dir.join("ca.pem"));
        std::fs::write(&cert, ck.cert.pem()).unwrap();
        std::fs::write(&key, ck.signing_key.serialize_pem()).unwrap();
        std::fs::write(&ca, ck.cert.pem()).unwrap();

        let mut cfg = GatewayConfig::new(SITE, dir.join("gw"), "127.0.0.1:0".parse().unwrap());
        cfg.tls = Some((cert, key));
        let gw: Arc<Gateway> = Gateway::open(cfg, b"test state key").unwrap();
        gw.ensure_admin("root", "root password").unwrap();
        gw.add_user("claude", "operator password", vec!["operator".into()])
            .unwrap();
        gw.add_user("eng", "engineer password", vec!["engineer".into()])
            .unwrap();

        let session = zenoh::open(isolated_config()).await.unwrap();
        let link_cfg = |id: &str| {
            let mut lc = LinkConfig::new(SITE, id);
            lc.admin_keys = vec![gw.verifying_key()];
            lc.answer_val = true;
            lc
        };
        let mock = wyrm_link_sdk::spawn::<Mock>(
            session.clone(),
            link_cfg("mock"),
            MockConfig {
                points: 2,
                rate_hz: 0.0,
                depth: 0,
                fanout: 1,
                writable: true,
            },
        )
        .await
        .unwrap();
        let plant = wyrm_link_sdk::spawn::<Plant>(session.clone(), link_cfg("plant"), ())
            .await
            .unwrap();
        let (stop, rx) = oneshot::channel::<()>();
        tokio::spawn(gw.clone().serve(session, async {
            let _ = rx.await;
        }));
        let addr = tokio::time::timeout(Duration::from_secs(5), gw.local_addr())
            .await
            .unwrap();
        Self {
            url: format!("https://localhost:{}", addr.port()),
            ca,
            stop: Some(stop),
            mock: Some(mock),
            plant: Some(plant),
        }
    }

    async fn mcp(
        &self,
        user: &str,
        password: &str,
        read_only: bool,
        allow_config: bool,
    ) -> RunningService<RoleClient, TestClient> {
        let server = GatewayMcp::new(GatewayOptions {
            endpoint: Endpoint::parse(&self.url, Some(&self.ca)).unwrap(),
            url: self.url.clone(),
            user: user.into(),
            password: Zeroizing::new(password.into()),
            read_only,
            allow_config,
        });
        let (a, b) = tokio::io::duplex(1 << 20);
        tokio::spawn(async move {
            if let Ok(s) = server.serve(a).await {
                let _ = s.waiting().await;
            }
        });
        TestClient.serve(b).await.unwrap()
    }

    async fn stop(mut self) {
        if let Some(s) = self.stop.take() {
            let _ = s.send(());
        }
        if let Some(l) = self.mock.take() {
            l.stop().await;
        }
        if let Some(l) = self.plant.take() {
            l.stop().await;
        }
    }
}

/// `(is_error, body)`.
async fn call(
    mcp: &RunningService<RoleClient, TestClient>,
    tool: &str,
    args: Json,
) -> (bool, Json) {
    let r = mcp
        .call_tool(
            CallToolRequestParams::new(tool.to_owned())
                .with_arguments(args.as_object().unwrap().clone()),
        )
        .await
        .unwrap();
    let text = r
        .content
        .first()
        .and_then(|c| c.as_text())
        .map(|t| t.text.clone())
        .unwrap_or_default();
    (
        r.is_error == Some(true),
        serde_json::from_str(&text).unwrap_or(Json::String(text)),
    )
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn claude_works_through_the_gateway_as_its_user() {
    let env = Env::start("user").await;
    let mcp = env.mcp("claude", "operator password", false, false).await;

    let tools = mcp.list_all_tools().await.unwrap();
    let names: Vec<_> = tools.iter().map(|t| t.name.to_string()).collect();
    for t in [
        "whoami",
        "tree_list",
        "node_meta",
        "value_get",
        "node_set",
        "action_invoke",
        "plan_run",
    ] {
        assert!(names.contains(&t.to_owned()), "{t} in {names:?}");
    }
    let ro = |n: &str| {
        tools
            .iter()
            .find(|t| t.name == n)
            .and_then(|t| t.annotations.as_ref())
            .and_then(|a| a.read_only_hint)
    };
    assert_eq!(ro("tree_list"), Some(true));
    assert_eq!(ro("node_set"), Some(false));

    let (e, me) = call(&mcp, "whoami", json!({})).await;
    assert!(!e, "{me}");
    assert_eq!(me["user"], json!("claude"));
    assert_eq!(me["site"], json!(SITE));
    assert_eq!(me["max"], json!("write"));

    let (e, t) = call(&mcp, "tree_list", json!({ "path": "downstream/mock" })).await;
    assert!(!e, "{t}");
    let keys: Vec<_> = t["nodes"]
        .as_array()
        .unwrap()
        .iter()
        .map(|n| n["key"].as_str().unwrap().to_owned())
        .collect();
    assert!(
        keys.contains(&format!("wy/{SITE}/downstream/mock/p0")),
        "{keys:?}"
    );

    // a dry run sends nothing
    let (e, d) = call(
        &mcp,
        "node_set",
        json!({ "path": "downstream/mock/p0", "value": 42.5 }),
    )
    .await;
    assert!(!e, "{d}");
    assert_eq!(d["dry_run"], json!(true));
    assert_eq!(d["would_send"]["level"], json!("write"));
    assert_eq!(d["would_send"]["as_user"], json!("claude"));

    let (e, r) = call(
        &mcp,
        "node_set",
        json!({ "path": "downstream/mock/p0", "value": 42.5, "dry_run": false }),
    )
    .await;
    assert!(!e, "{r}");
    let mut v = Json::Null;
    for _ in 0..20 {
        let (_, g) = call(
            &mcp,
            "value_get",
            json!({ "paths": ["downstream/mock/p0"] }),
        )
        .await;
        v = g["downstream/mock/p0"]["v"].clone();
        if v == json!(42.5) {
            break;
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
    assert_eq!(v, json!(42.5));

    // config-level: the role (operator = write) refuses it at the gateway, and the connector
    // refuses it first without allow_config
    let (e, r) = call(
        &mcp,
        "node_set",
        json!({ "path": "downstream/plant/sp", "value": 30, "dry_run": false }),
    )
    .await;
    assert!(e, "{r}");
    assert!(r.as_str().unwrap().contains("allow_config"), "{r}");

    // a key outside wy/<site> and a wildcard in a node key
    let (e, _) = call(&mcp, "node_meta", json!({ "path": "downstream/*" })).await;
    assert!(e);
    env.stop().await;
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn read_only_and_allow_config_and_a_wrong_password() {
    let env = Env::start("modes").await;

    let ro = env.mcp("claude", "operator password", true, false).await;
    let (e, d) = call(
        &ro,
        "node_set",
        json!({ "path": "downstream/mock/p1", "value": 1 }),
    )
    .await;
    assert!(!e, "{d}");
    assert!(d["refused_by_connector"]
        .as_str()
        .unwrap()
        .contains("read-only"));
    let (e, r) = call(
        &ro,
        "node_set",
        json!({ "path": "downstream/mock/p1", "value": 1, "dry_run": false }),
    )
    .await;
    assert!(e && r.as_str().unwrap().contains("read-only"), "{r}");

    // an engineer with allow_config writes the config-level point
    let eng = env.mcp("eng", "engineer password", false, true).await;
    let (e, r) = call(
        &eng,
        "node_set",
        json!({ "path": "downstream/plant/sp", "value": 30, "dry_run": false }),
    )
    .await;
    assert!(!e, "{r}");
    assert_eq!(r["sent"]["level"], json!("config"));

    // plan: check, then apply
    let plan = json!({ "steps": [
        { "set": format!("wy/{SITE}/downstream/mock/p1"), "value": 7 },
        { "expect": format!("wy/{SITE}/downstream/mock/p1"), "equals": 7, "timeout_s": 5 },
    ]});
    let (e, c) = call(&eng, "plan_run", json!({ "plan": plan })).await;
    assert!(!e && c["checked"] == json!(true), "{c}");
    let (e, a) = call(&eng, "plan_run", json!({ "plan": plan, "apply": true })).await;
    assert!(!e && a["applied"] == json!(true), "{a}");

    let bad = env.mcp("claude", "wrong password", false, false).await;
    let (e, r) = call(&bad, "whoami", json!({})).await;
    assert!(e, "{r}");
    assert!(
        r.as_str().unwrap().contains("wrong user or password"),
        "{r}"
    );

    // a gateway certificate nobody trusts
    let server = GatewayMcp::new(GatewayOptions {
        endpoint: Endpoint::parse(&env.url, None).unwrap(),
        url: env.url.clone(),
        user: "claude".into(),
        password: Zeroizing::new("operator password".into()),
        read_only: false,
        allow_config: false,
    });
    let err = server.check().await.unwrap_err();
    assert!(err.contains("TLS"), "{err}");
    env.stop().await;
}
