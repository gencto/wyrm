//! The MCP server end to end: an rmcp client over an in-memory duplex pipe,
//! the server on an isolated Zenoh session with the mock link, a small link
//! with config-level points and actions, and the flow engine.

use base64::Engine as _;
use rmcp::model::{CallToolRequestParams, ClientConfig, ReadResourceRequestParams};
use rmcp::service::RunningService;
use rmcp::{ClientHandler, RoleClient, ServiceExt};
use serde_json::{json, Value as Json};
use std::path::PathBuf;
use std::time::Duration;
use wyrm_client::{SigningTokens, TokenSource, WyrmClient};
use wyrm_core::meta::{ParamMeta, Writable};
use wyrm_core::{ActionMeta, NodeMeta, Perm, Quality, TypeCode, Value};
use wyrm_flow::{Engine, EngineStart, FlowHost};
use wyrm_link_mock::{Mock, MockConfig};
use wyrm_link_sdk::harness::{isolated_config, TEST_KEY_SEED};
use wyrm_link_sdk::{now_us, Caller, Link, LinkConfig, LinkCtx, LinkHandle, ReplySink};
use wyrm_mcp::{Options, WyrmMcp};

const SITE: &str = "test";

/// A link with one config-level point (`sp`), one enum point (`mode`) and a
/// config-level action (`reboot`) that answers with the caller's subject.
struct Plant {
    ctx: LinkCtx,
}

impl Link for Plant {
    const NAME: &'static str = "plant";
    const VERSION: &'static str = "0.0.0";
    type Config = ();

    async fn start(_cfg: (), ctx: LinkCtx) -> wyrm_link_sdk::Result<Self> {
        ctx.declare_node(
            "sp",
            NodeMeta::number()
                .unit("°C")
                .writable(Writable::Config)
                .cfg("min", 0.0)
                .cfg("max", 100.0),
        )
        .await?;
        ctx.declare_node(
            "mode",
            NodeMeta::leaf(TypeCode::Enum)
                .enum_values(["auto", "manual"])
                .writable(Writable::Write),
        )
        .await?;
        ctx.update("sp", 20.0, Quality::Good, now_us()).await?;
        ctx.update("mode", 0u64, Quality::Good, now_us()).await?;
        ctx.declare_action(
            "",
            "reboot",
            ActionMeta::new()
                .param("delay", ParamMeta::of(TypeCode::Number))
                .level(Perm::Config),
        )
        .await?;
        Ok(Self { ctx })
    }

    async fn on_set(
        &mut self,
        path: &str,
        value: Value,
        _who: &Caller,
    ) -> wyrm_link_sdk::Result<()> {
        self.ctx.update(path, value, Quality::Good, now_us()).await
    }

    async fn on_invoke(
        &mut self,
        _path: &str,
        _action: &str,
        _args: Value,
        who: &Caller,
        out: ReplySink,
    ) -> wyrm_link_sdk::Result<()> {
        let sub = who
            .claims
            .as_ref()
            .map(|c| c.sub.clone())
            .unwrap_or_default();
        out.reply(sub).await
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
    mcp: RunningService<RoleClient, TestClient>,
    mock: Option<LinkHandle<Mock>>,
    plant: Option<LinkHandle<Plant>>,
    engine: Option<LinkHandle<Engine>>,
    /// A human operator's token source (admin key, `max = config`).
    human: SigningTokens,
    dir: PathBuf,
}

fn key() -> ed25519_dalek::SigningKey {
    ed25519_dalek::SigningKey::from_bytes(&TEST_KEY_SEED)
}

fn link_cfg(link: &str, extra: Option<ed25519_dalek::VerifyingKey>) -> LinkConfig {
    let mut c = LinkConfig::new(SITE, link);
    c.admin_keys = vec![key().verifying_key()];
    c.admin_keys.extend(extra);
    c.answer_val = true;
    c
}

impl Env {
    async fn start(name: &str) -> Self {
        let dir = std::env::temp_dir().join(format!("wyrm-mcp-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let session = zenoh::open(isolated_config()).await.unwrap();
        let host = FlowHost::open(&dir, b"mcp-test-hmac-key", SITE).unwrap();
        let flow_key = host.verifying_key();
        let mock = wyrm_link_sdk::spawn::<Mock>(
            session.clone(),
            link_cfg("mock", Some(flow_key)),
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
        let plant = wyrm_link_sdk::spawn::<Plant>(session.clone(), link_cfg("plant", None), ())
            .await
            .unwrap();
        let mut ecfg = LinkConfig::new(SITE, "dataflows");
        ecfg.root = Some(format!("wy/{SITE}/dataflows"));
        ecfg.admin_keys = vec![key().verifying_key()];
        ecfg.answer_val = true;
        let engine = wyrm_link_sdk::spawn::<Engine>(
            session.clone(),
            ecfg,
            EngineStart {
                host,
                admin_keys: vec![key().verifying_key()],
            },
        )
        .await
        .unwrap();

        let client = WyrmClient::new(session.clone()).with_timeout(Duration::from_secs(3));
        let server = WyrmMcp::new(
            client,
            Options {
                site: SITE.into(),
                agent_name: "test".into(),
                key: Some(key()),
                timeout: Duration::from_secs(3),
            },
        );
        let (a, b) = tokio::io::duplex(1 << 20);
        tokio::spawn(async move {
            if let Ok(s) = server.serve(a).await {
                let _ = s.waiting().await;
            }
        });
        let mcp = TestClient.serve(b).await.unwrap();
        Self {
            mcp,
            mock: Some(mock),
            plant: Some(plant),
            engine: Some(engine),
            human: SigningTokens::new(key(), SITE).subject("user:op"),
            dir,
        }
    }

    /// `(is_error, body)`: body is the JSON text parsed, or the raw text.
    async fn call(&self, tool: &str, args: Json) -> (bool, Json) {
        let r = self
            .mcp
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
        let body = serde_json::from_str(&text).unwrap_or(Json::String(text));
        (r.is_error == Some(true), body)
    }

    async fn ok(&self, tool: &str, args: Json) -> Json {
        let (e, b) = self.call(tool, args).await;
        assert!(!e, "{tool} failed: {b}");
        b
    }

    async fn fails(&self, tool: &str, args: Json) -> String {
        let (e, b) = self.call(tool, args).await;
        assert!(e, "{tool} should fail: {b}");
        b.as_str()
            .map(str::to_owned)
            .unwrap_or_else(|| b.to_string())
    }

    /// A human approval for exactly `key`, base64, not bound to arguments (a flow's proof).
    fn approve(&self, key: &str) -> String {
        b64(&self.human.token(key).unwrap())
    }

    /// A human approval for exactly `key` and the payload a dry run hashed (`args_sha256`).
    fn approve_args(&self, k: &str, sha: &Json) -> String {
        let h: [u8; 32] = hex::decode(sha.as_str().expect("args_sha256"))
            .unwrap()
            .try_into()
            .unwrap();
        b64(&SigningTokens::new(key(), SITE)
            .subject("user:op")
            .bound_to(h)
            .token(k)
            .unwrap())
    }

    async fn value(&self, path: &str) -> Json {
        let r = self.ok("value_get", json!({ "paths": [path] })).await;
        r[path]["v"].clone()
    }

    async fn stop(mut self) {
        let _ = self.mcp.cancel().await;
        if let Some(e) = self.engine.take() {
            e.stop().await;
        }
        if let Some(p) = self.plant.take() {
            p.stop().await;
        }
        if let Some(m) = self.mock.take() {
            m.stop().await;
        }
        let _ = std::fs::remove_dir_all(&self.dir);
    }
}

fn b64(b: &[u8]) -> String {
    base64::engine::general_purpose::STANDARD.encode(b)
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn browse_and_read() {
    let env = Env::start("browse").await;
    let tools = env.mcp.list_all_tools().await.unwrap();
    let names: Vec<&str> = tools.iter().map(|t| t.name.as_ref()).collect();
    for n in [
        "tree_list",
        "tree_resolve",
        "node_meta",
        "value_get",
        "node_set",
        "action_invoke",
        "profiles",
        "flow_get",
        "flow_validate",
        "flow_apply",
        "link_status",
        "spec",
    ] {
        assert!(names.contains(&n), "missing tool {n}: {names:?}");
    }

    let links = env
        .ok("tree_list", json!({ "path": "wy/test/downstream" }))
        .await;
    let ids: Vec<&str> = links["children"]
        .as_array()
        .unwrap()
        .iter()
        .map(|c| c["name"].as_str().unwrap())
        .collect();
    assert!(ids.contains(&"mock") && ids.contains(&"plant"), "{links}");

    let kids = env
        .ok(
            "tree_list",
            json!({ "path": "downstream/mock", "limit": 1 }),
        )
        .await;
    assert_eq!(kids["total"], 2);
    assert_eq!(kids["next"], 1);
    assert_eq!(kids["children"][0]["name"], "p0");
    assert_eq!(kids["children"][0]["path"], "wy/test/downstream/mock/p0");
    assert_eq!(kids["children"][0]["type"], "number");

    let keys = env
        .ok("tree_resolve", json!({ "path": "wy/test/downstream/mock" }))
        .await;
    let keys: Vec<&str> = keys["keys"]
        .as_array()
        .unwrap()
        .iter()
        .map(|k| k.as_str().unwrap())
        .collect();
    assert!(keys.contains(&"p0") && keys.contains(&"p1"), "{keys:?}");

    let meta = env
        .ok(
            "node_meta",
            json!({ "path": "wy/test/downstream/plant/sp" }),
        )
        .await;
    assert_eq!(meta["writable"], "config");
    assert_eq!(meta["unit"], "°C");
    assert_eq!(meta["cfg"]["max"], 100.0);
    let root = env
        .ok(
            "node_meta",
            json!({ "path": "wy/test/downstream/mock", "expand": true }),
        )
        .await;
    assert_eq!(root["actions"]["count"]["params"]["n"]["required"], true);
    assert_eq!(root["actions"]["reset"]["level"], "write");

    let vals = env
        .ok(
            "value_get",
            json!({ "paths": ["wy/test/downstream/plant/sp", "downstream/plant/mode", "downstream/plant/nope"] }),
        )
        .await;
    assert_eq!(vals["wy/test/downstream/plant/sp"]["v"], 20.0);
    assert_eq!(vals["wy/test/downstream/plant/sp"]["q"], "good");
    assert_eq!(vals["downstream/plant/mode"]["v"], 0);
    assert!(vals["downstream/plant/nope"]["error"].is_string(), "{vals}");

    // other sites and suffixes are refused before anything is sent
    let e = env
        .fails("node_meta", json!({ "path": "wy/other/downstream/x" }))
        .await;
    assert!(e.contains("serves site"), "{e}");
    let e = env
        .fails(
            "node_meta",
            json!({ "path": "wy/test/downstream/mock/~meta" }),
        )
        .await;
    assert!(e.contains("node key"), "{e}");

    let st = env.ok("link_status", json!({ "link": "mock" })).await;
    assert_eq!(st["alive"], true);
    let st = env.ok("link_status", json!({ "link": "gone" })).await;
    assert_eq!(st["alive"], false);

    env.stop().await;
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn set_and_invoke_at_write_level() {
    let env = Env::start("write").await;
    let p0 = "wy/test/downstream/mock/p0";
    let before = env.value(p0).await;

    // dry_run defaults to true: validated, nothing sent
    let r = env
        .ok("node_set", json!({ "path": p0, "value": 42.5 }))
        .await;
    assert_eq!(r["dry_run"], true);
    assert_eq!(r["level"], "write");
    assert_eq!(r["requires_approval"], false);
    assert_eq!(r["would_send"]["key"], "wy/test/downstream/mock/p0/~set");
    assert_eq!(r["would_send"]["payload"]["v"], 42.5);
    assert!(r["would_send"]["ptok"]
        .as_str()
        .unwrap()
        .contains("ai:test"));
    assert_eq!(env.value(p0).await, before);

    // invalid values fail in the dry run already
    let e = env
        .fails("node_set", json!({ "path": p0, "value": "hot" }))
        .await;
    assert!(e.contains("expected number"), "{e}");

    // real write as the service account
    let r = env
        .ok(
            "node_set",
            json!({ "path": p0, "value": 42.5, "dry_run": false }),
        )
        .await;
    assert_eq!(r["ok"], true);
    assert_eq!(env.value(p0).await, 42.5);

    // enum by name
    let r = env
        .ok(
            "node_set",
            json!({ "path": "downstream/plant/mode", "value": "manual", "dry_run": false }),
        )
        .await;
    assert_eq!(r["value"], 1);
    assert_eq!(env.value("downstream/plant/mode").await, 1);
    let e = env
        .fails(
            "node_set",
            json!({ "path": "downstream/plant/mode", "value": "off" }),
        )
        .await;
    assert!(e.contains("manual"), "{e}");

    // actions: argument schema in the dry run, stream results for real
    let e = env
        .fails(
            "action_invoke",
            json!({ "path": "downstream/mock", "action": "count" }),
        )
        .await;
    assert!(e.contains("missing n"), "{e}");
    let e = env
        .fails(
            "action_invoke",
            json!({ "path": "downstream/mock", "action": "count", "args": { "n": 2, "x": 1 } }),
        )
        .await;
    assert!(e.contains("unknown param x"), "{e}");
    let r = env
        .ok(
            "action_invoke",
            json!({ "path": "downstream/mock", "action": "count", "args": { "n": 3 } }),
        )
        .await;
    assert_eq!(r["dry_run"], true);
    assert_eq!(r["level"], "read");
    let r = env
        .ok(
            "action_invoke",
            json!({ "path": "downstream/mock", "action": "count", "args": { "n": 3 }, "dry_run": false }),
        )
        .await;
    assert_eq!(r["results"], json!([0, 1, 2]));

    env.stop().await;
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn config_level_needs_a_human_approval() {
    let env = Env::start("config").await;
    let sp = "wy/test/downstream/plant/sp";
    let set_key = format!("{sp}/~set");

    let r = env.ok("node_set", json!({ "path": sp, "value": 50 })).await;
    assert_eq!(r["level"], "config");
    assert_eq!(r["requires_approval"], true);
    let h50 = r["would_send"]["args_sha256"].clone();
    let h60 = env.ok("node_set", json!({ "path": sp, "value": 60 })).await["would_send"]
        ["args_sha256"]
        .clone();

    // refused without approval, nothing sent
    let e = env
        .fails(
            "node_set",
            json!({ "path": sp, "value": 50, "dry_run": false }),
        )
        .await;
    assert!(e.contains("config-level") && e.contains("approval"), "{e}");
    assert_eq!(env.value(sp).await, 20.0);

    // review AI-1: an approval not bound to the arguments is refused, with how to mint one
    let e = env
        .fails(
            "node_set",
            json!({ "path": sp, "value": 50, "dry_run": false, "approval": env.approve(&set_key) }),
        )
        .await;
    assert!(e.contains("--args-sha256"), "{e}");

    // a dry run with an approval checks it but does not spend it
    let tok = env.approve_args(&set_key, &h50);
    let r = env
        .ok(
            "node_set",
            json!({ "path": sp, "value": 50, "approval": tok }),
        )
        .await;
    assert_eq!(r["approval"]["sub"], "user:op");
    assert_eq!(r["approval"]["level"], "config");
    assert_eq!(env.value(sp).await, 20.0);

    // review AI-1: the approval of 50 cannot send 60
    let e = env
        .fails(
            "node_set",
            json!({ "path": sp, "value": 60, "dry_run": false, "approval": tok }),
        )
        .await;
    assert!(e.contains("other arguments"), "{e}");
    assert_eq!(env.value(sp).await, 20.0);

    // the same token now goes out for real
    let r = env
        .ok(
            "node_set",
            json!({ "path": sp, "value": 50, "dry_run": false, "approval": tok }),
        )
        .await;
    assert!(r["sent_as"].as_str().unwrap().contains("user:op"), "{r}");
    assert_eq!(env.value(sp).await, 50);

    // tokens are single-use: the link refuses a replay
    let e = env
        .fails(
            "node_set",
            json!({ "path": sp, "value": 50, "dry_run": false, "approval": tok }),
        )
        .await;
    assert!(e.contains("permission_denied"), "{e}");
    assert_eq!(env.value(sp).await, 50);

    // an approval for another key is refused before sending
    let other = env.approve_args("wy/test/downstream/plant/mode/~set", &h60);
    let e = env
        .fails(
            "node_set",
            json!({ "path": sp, "value": 60, "dry_run": false, "approval": other }),
        )
        .await;
    assert!(e.contains("exactly"), "{e}");

    let bound60: [u8; 32] = hex::decode(h60.as_str().unwrap())
        .unwrap()
        .try_into()
        .unwrap();
    // an approval capped at write cannot do a config write
    let weak = SigningTokens::new(key(), SITE)
        .subject("user:op")
        .max(Perm::Write)
        .bound_to(bound60)
        .token(&set_key)
        .unwrap();
    let e = env
        .fails(
            "node_set",
            json!({ "path": sp, "value": 60, "dry_run": false, "approval": b64(&weak) }),
        )
        .await;
    assert!(e.contains("config is needed"), "{e}");

    // an AI cannot approve itself
    let ai = SigningTokens::new(key(), SITE)
        .subject("ai:test")
        .bound_to(bound60)
        .token(&set_key)
        .unwrap();
    let e = env
        .fails(
            "node_set",
            json!({ "path": sp, "value": 60, "dry_run": false, "approval": b64(&ai) }),
        )
        .await;
    assert!(e.contains("AI agent"), "{e}");

    // signed by a key the link does not trust: passes the pre-check, the link refuses
    let rogue = SigningTokens::new(ed25519_dalek::SigningKey::from_bytes(&[9; 32]), SITE)
        .subject("user:op")
        .bound_to(bound60)
        .token(&set_key)
        .unwrap();
    let e = env
        .fails(
            "node_set",
            json!({ "path": sp, "value": 60, "dry_run": false, "approval": b64(&rogue) }),
        )
        .await;
    assert!(e.contains("permission_denied"), "{e}");
    assert_eq!(env.value(sp).await, 50);

    // config-level action: refused without approval, runs as the human with it
    let act_key = "wy/test/downstream/plant/~act/reboot";
    let e = env
        .fails("action_invoke", json!({ "path": "downstream/plant", "action": "reboot", "args": { "delay": 1 }, "dry_run": false }))
        .await;
    assert!(e.contains("config-level"), "{e}");
    let dry = env
        .ok(
            "action_invoke",
            json!({ "path": "downstream/plant", "action": "reboot", "args": { "delay": 1 } }),
        )
        .await;
    let r = env
        .ok(
            "action_invoke",
            json!({
                "path": "downstream/plant", "action": "reboot", "args": { "delay": 1 },
                "dry_run": false,
                "approval": env.approve_args(act_key, &dry["would_send"]["args_sha256"])
            }),
        )
        .await;
    assert_eq!(r["result"], "user:op");

    env.stop().await;
}

fn flow_def() -> Json {
    json!({
        "id": "shed",
        "version": 1,
        "nodes": {
            "a": { "type": "subscribe", "key": "downstream/mock/p0" },
            "alarm": { "type": "alarm", "high": 1000.0 },
            "shed": { "type": "invoke", "path": "downstream/mock", "action": "reset", "on": "rising" }
        },
        "edges": [["a.out", "alarm.in"], ["alarm.out", "shed.in"]],
        "permissions": { "maxperm": "write" }
    })
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn flow_apply_with_operator_proofs() {
    let env = Env::start("flow").await;
    let target = "wy/test/downstream/mock/~act/reset";
    let deploy = "wy/test/dataflows/~act/deploy";

    let v = env.ok("flow_validate", json!({ "def": flow_def() })).await;
    assert_eq!(v["ok"], true, "{v}");

    let r = env.ok("flow_apply", json!({ "def": flow_def() })).await;
    assert_eq!(r["dry_run"], true);
    assert_eq!(r["command_targets"], json!([target]));
    assert_eq!(r["missing_proofs"], json!([target]));
    assert_eq!(r["approval_key"], deploy);

    let e = env
        .fails("flow_apply", json!({ "def": flow_def(), "dry_run": false }))
        .await;
    assert!(e.contains("approval"), "{e}");
    let bare = r["args_sha256"].clone();
    let e = env
        .fails(
            "flow_apply",
            json!({ "def": flow_def(), "dry_run": false, "approval": env.approve_args(deploy, &bare) }),
        )
        .await;
    assert!(e.contains("missing proofs"), "{e}");

    // proofs from another operator than the approval are refused
    let other = SigningTokens::new(key(), SITE).subject("user:eve");
    let eve = b64(&other.token(target).unwrap());
    let dry = env
        .ok(
            "flow_apply",
            json!({ "def": flow_def(), "proofs": { target: eve } }),
        )
        .await;
    let e = env
        .fails(
            "flow_apply",
            json!({
                "def": flow_def(), "dry_run": false,
                "approval": env.approve_args(deploy, &dry["args_sha256"]),
                "proofs": { target: eve }
            }),
        )
        .await;
    assert!(e.contains("same operator"), "{e}");

    let proof = env.approve(target);
    let dry = env
        .ok(
            "flow_apply",
            json!({ "def": flow_def(), "proofs": { target: proof } }),
        )
        .await;
    let r = env
        .ok(
            "flow_apply",
            json!({
                "def": flow_def(), "dry_run": false,
                "approval": env.approve_args(deploy, &dry["args_sha256"]),
                "proofs": { target: proof }
            }),
        )
        .await;
    assert_eq!(r["ok"], true, "{r}");

    let mut got = Json::Null;
    for _ in 0..50 {
        let (e, b) = env.call("flow_get", json!({ "id": "shed" })).await;
        if !e {
            got = b;
            break;
        }
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
    assert_eq!(got["def"]["id"], "shed", "{got}");

    env.stop().await;
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn spec_tool_and_resources() {
    let env = Env::start("spec").await;
    let list = env.ok("spec", json!({})).await;
    assert!(list.as_array().unwrap().len() >= 7);
    let (e, text) = env.call("spec", json!({ "section": "04" })).await;
    assert!(!e);
    assert!(text.as_str().unwrap().contains("ptok"));
    assert!(env
        .fails("spec", json!({ "section": "99" }))
        .await
        .contains("no spec"));

    let res = env.mcp.list_all_resources().await.unwrap();
    assert!(res.iter().any(|r| r.uri == "wy://spec/01-keyspace.md"));
    let r = env
        .mcp
        .read_resource(ReadResourceRequestParams::new("wy://spec/01-keyspace.md"))
        .await
        .unwrap();
    let body = serde_json::to_value(&r.contents[0]).unwrap();
    assert!(
        body["text"].as_str().unwrap().contains("wy/<site>"),
        "{body}"
    );
    assert!(env
        .mcp
        .read_resource(ReadResourceRequestParams::new("wy://spec/nope.md"))
        .await
        .is_err());

    env.stop().await;
}

/// Without a signing key the server only reads.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn read_only_without_key() {
    let session = zenoh::open(isolated_config()).await.unwrap();
    let mock = wyrm_link_sdk::spawn::<Mock>(
        session.clone(),
        link_cfg("mock", None),
        MockConfig {
            points: 1,
            rate_hz: 0.0,
            depth: 0,
            fanout: 1,
            writable: true,
        },
    )
    .await
    .unwrap();
    let server = WyrmMcp::new(
        WyrmClient::new(session.clone()).with_timeout(Duration::from_secs(3)),
        Options {
            site: SITE.into(),
            agent_name: "ro".into(),
            key: None,
            timeout: Duration::from_secs(3),
        },
    );
    let (a, b) = tokio::io::duplex(1 << 16);
    tokio::spawn(async move {
        if let Ok(s) = server.serve(a).await {
            let _ = s.waiting().await;
        }
    });
    let mcp = TestClient.serve(b).await.unwrap();
    let r = mcp
        .call_tool(
            CallToolRequestParams::new("node_set").with_arguments(
                json!({ "path": "downstream/mock/p0", "value": 1, "dry_run": false })
                    .as_object()
                    .unwrap()
                    .clone(),
            ),
        )
        .await
        .unwrap();
    assert_eq!(r.is_error, Some(true));
    let _ = mcp.cancel().await;
    mock.stop().await;
}
