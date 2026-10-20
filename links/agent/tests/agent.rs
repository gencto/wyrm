//! The agent link end to end on one isolated Zenoh session with the mock
//! link and a scripted fake LLM (no network).

use base64::Engine as _;
use serde_json::{json, Value as Json};
use std::collections::{BTreeMap, VecDeque};
use std::sync::{Arc, Mutex};
use std::time::Duration;
use wyrm_client::{SigningTokens, TokenSource, WyrmClient};
use wyrm_core::{Perm, Status, Value};
use wyrm_link_agent::llm::{LlmClient, LlmFuture};
use wyrm_link_agent::{Agent, AgentConfig, AgentParams};
use wyrm_link_mock::{Mock, MockConfig};
use wyrm_link_sdk::harness::{isolated_config, TEST_KEY_SEED};
use wyrm_link_sdk::{LinkConfig, LinkHandle, Secret, SecretStore};

const SITE: &str = "test";
const AGENT_SEED: [u8; 32] = [9; 32];
const P0: &str = "wy/test/down/mock/p0";

/// Scripted Messages API: answers in order, records every request.
#[derive(Default)]
struct FakeLlm {
    script: Mutex<VecDeque<Json>>,
    seen: Mutex<Vec<Json>>,
    /// Latency of every call (a thinking model).
    delay: Mutex<Duration>,
}

impl FakeLlm {
    fn new(script: Vec<Json>) -> Arc<Self> {
        Arc::new(Self {
            script: Mutex::new(script.into()),
            seen: Mutex::default(),
            delay: Mutex::default(),
        })
    }

    fn seen(&self) -> Vec<Json> {
        self.seen.lock().unwrap().clone()
    }
}

impl LlmClient for FakeLlm {
    fn messages(&self, body: Json) -> LlmFuture<'_> {
        self.seen.lock().unwrap().push(body);
        let r = self
            .script
            .lock()
            .unwrap()
            .pop_front()
            .ok_or_else(|| "script exhausted".to_owned());
        let delay = *self.delay.lock().unwrap();
        Box::pin(async move {
            tokio::time::sleep(delay).await;
            r
        })
    }
}

fn tool_use(calls: &[(&str, &str, Json)]) -> Json {
    let content: Vec<Json> = calls
        .iter()
        .map(
            |(id, name, input)| json!({"type": "tool_use", "id": id, "name": name, "input": input}),
        )
        .collect();
    json!({"content": content, "stop_reason": "tool_use", "usage": {"input_tokens": 50, "output_tokens": 10}})
}

fn end(text: &str) -> Json {
    json!({"content": [{"type": "text", "text": text}], "stop_reason": "end_turn", "usage": {"input_tokens": 60, "output_tokens": 20}})
}

/// Read p0, propose `p0 := 42`, finish.
fn set_p0_script(value: f64) -> Vec<Json> {
    vec![
        tool_use(&[
            ("t1", "node_meta", json!({"path": "down/mock/p0"})),
            (
                "t2",
                "propose",
                json!({"op": "set", "path": "down/mock/p0", "value": value, "reason": "operator asked"}),
            ),
        ]),
        end("Plan: set p0."),
    ]
}

fn test_key() -> ed25519_dalek::SigningKey {
    ed25519_dalek::SigningKey::from_bytes(&TEST_KEY_SEED)
}

struct Env {
    session: zenoh::Session,
    mock: Option<LinkHandle<Mock>>,
    agent: Option<LinkHandle<Agent>>,
    llm: Arc<FakeLlm>,
    params: AgentParams,
    data_dir: Option<std::path::PathBuf>,
}

async fn spawn_agent(
    session: &zenoh::Session,
    params: AgentParams,
    llm: Arc<FakeLlm>,
    data_dir: Option<std::path::PathBuf>,
) -> LinkHandle<Agent> {
    let mut acfg = LinkConfig::new(SITE, "agent");
    acfg.admin_keys = vec![test_key().verifying_key()];
    acfg.answer_val = true;
    acfg.secrets = SecretStore::from_iter([("agent_key", Secret::new(AGENT_SEED.to_vec()))]);
    acfg.data_dir = data_dir;
    wyrm_link_sdk::spawn::<Agent>(
        session.clone(),
        acfg,
        AgentConfig {
            params,
            llm: Some(llm),
        },
    )
    .await
    .unwrap()
}

/// A fresh private directory for one test.
fn temp_dir(name: &str) -> std::path::PathBuf {
    let d = std::env::temp_dir().join(format!(
        "wyrm-agent-{name}-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    let _ = std::fs::remove_dir_all(&d);
    d
}

impl Env {
    async fn start(params: AgentParams, script: Vec<Json>) -> Self {
        Self::start_in(params, script, None).await
    }

    async fn start_in(
        params: AgentParams,
        script: Vec<Json>,
        data_dir: Option<std::path::PathBuf>,
    ) -> Self {
        let session = zenoh::open(isolated_config()).await.unwrap();
        let agent_vk = ed25519_dalek::SigningKey::from_bytes(&AGENT_SEED).verifying_key();
        let mut mcfg = LinkConfig::new(SITE, "mock");
        mcfg.admin_keys = vec![test_key().verifying_key(), agent_vk];
        mcfg.answer_val = true;
        let mock = wyrm_link_sdk::spawn::<Mock>(
            session.clone(),
            mcfg,
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
        let llm = FakeLlm::new(script);
        let agent = spawn_agent(&session, params.clone(), llm.clone(), data_dir.clone()).await;
        Self {
            session,
            mock: Some(mock),
            agent: Some(agent),
            llm,
            params,
            data_dir,
        }
    }

    /// Stop the agent link and start it again on the same data_dir with a
    /// new model script.
    async fn restart_agent(&mut self, script: Vec<Json>) {
        if let Some(a) = self.agent.take() {
            a.stop().await;
        }
        self.llm = FakeLlm::new(script);
        self.agent = Some(
            spawn_agent(
                &self.session,
                self.params.clone(),
                self.llm.clone(),
                self.data_dir.clone(),
            )
            .await,
        );
    }

    fn human(&self, max: Perm) -> WyrmClient {
        self.human_with(max, Duration::from_secs(5))
    }

    fn human_with(&self, max: Perm, timeout: Duration) -> WyrmClient {
        WyrmClient::new(self.session.clone())
            .with_timeout(timeout)
            .with_tokens(Arc::new(
                SigningTokens::new(test_key(), SITE)
                    .subject("user:op")
                    .max(max),
            ))
    }

    /// `ask` → `(task id, every streamed item)`.
    async fn ask(&self, text: &str) -> Result<(String, Vec<Value>), wyrm_client::ClientError> {
        self.ask_with(&self.human(Perm::Config), text).await
    }

    async fn ask_with(
        &self,
        client: &WyrmClient,
        text: &str,
    ) -> Result<(String, Vec<Value>), wyrm_client::ClientError> {
        let args = Value::Map(BTreeMap::from([("task".to_owned(), Value::from(text))]));
        let mut s = client.invoke("wy/test/down/agent", "ask", args).await?;
        let mut items = Vec::new();
        while let Some(i) = s.next().await {
            if let Some(v) = i? {
                items.push(v);
            }
        }
        let id = field(&items[0], "task").expect("first item names the task");
        Ok((id, items))
    }

    fn task(&self, id: &str) -> Value {
        self.agent
            .as_ref()
            .unwrap()
            .ctx()
            .last(&format!("tasks/{id}"))
            .expect("task ~val")
            .v
    }

    /// Raw `get` of the task's `~state` document with an optional ptok:
    /// `Ok(record)` or `Err(status name)`.
    async fn doc_with(&self, id: &str, ptok: Option<Vec<u8>>) -> Result<Value, String> {
        let key = format!("wy/test/down/agent/tasks/{id}/~state");
        let att = wyrm_core::Attachment {
            ptok,
            ..Default::default()
        };
        let rx = self
            .session
            .get(&key)
            .attachment(wyrm_core::codec::to_vec(&att).unwrap())
            .timeout(Duration::from_secs(5))
            .await
            .unwrap();
        let reply = rx.recv_async().await.map_err(|_| "no reply".to_owned())?;
        let s = reply.result().map_err(|_| "error reply".to_owned())?;
        let att: wyrm_core::Attachment = s
            .attachment()
            .map(|a| wyrm_core::codec::from_slice(&a.to_bytes()).unwrap())
            .unwrap_or_default();
        match att.status {
            Some(st) if st.group() == wyrm_core::StatusGroup::Error => Err(format!("{st:?}")),
            _ => Ok(wyrm_core::codec::from_slice(&s.payload().to_bytes()).unwrap()),
        }
    }

    /// The full task record, read as a human with `list` rights.
    async fn doc(&self, id: &str) -> Value {
        let key = format!("wy/test/down/agent/tasks/{id}/~state");
        self.doc_with(id, Some(human_token("user:op", &key)))
            .await
            .expect("task ~state")
    }

    /// Wait for `want` on the public `~val`, then return the full record.
    async fn wait_state(&self, id: &str, want: &str) -> Value {
        for _ in 0..400 {
            let v = self.task(id);
            if field(&v, "state").as_deref() == Some(want) {
                return self.doc(id).await;
            }
            tokio::time::sleep(Duration::from_millis(25)).await;
        }
        panic!("task {id} never reached {want}: {:?}", self.task(id));
    }

    fn p0(&self) -> f64 {
        self.mock
            .as_ref()
            .unwrap()
            .ctx()
            .last("p0")
            .unwrap()
            .v
            .as_f64()
            .unwrap()
    }

    async fn task_action(
        &self,
        client: &WyrmClient,
        id: &str,
        action: &str,
        args: Value,
    ) -> Result<Option<Value>, wyrm_client::ClientError> {
        client
            .invoke_one(&format!("wy/test/down/agent/tasks/{id}"), action, args)
            .await
    }

    async fn stop(mut self) {
        if let Some(a) = self.agent.take() {
            a.stop().await;
        }
        if let Some(m) = self.mock.take() {
            m.stop().await;
        }
        let _ = self.session.close().await;
    }
}

fn field(v: &Value, k: &str) -> Option<String> {
    match v {
        Value::Map(m) => match m.get(k) {
            Some(Value::Str(s)) => Some(s.clone()),
            _ => None,
        },
        _ => None,
    }
}

fn plan_len(v: &Value) -> usize {
    match v {
        Value::Map(m) => match m.get("plan") {
            Some(Value::Array(a)) => a.len(),
            _ => 0,
        },
        _ => 0,
    }
}

fn params(allowed: &[&str]) -> AgentParams {
    AgentParams {
        allowed_prefixes: allowed.iter().map(|s| (*s).to_owned()).collect(),
        ..AgentParams::default()
    }
}

fn approvals(kv: &[(&str, Vec<u8>)]) -> Value {
    let b64 = base64::engine::general_purpose::STANDARD;
    let m: BTreeMap<String, Value> = kv
        .iter()
        .map(|(k, t)| ((*k).to_owned(), Value::from(b64.encode(t))))
        .collect();
    Value::Map(BTreeMap::from([("approvals".to_owned(), Value::Map(m))]))
}

/// A token minted by a human for exactly `key`.
fn human_token(sub: &str, key: &str) -> Vec<u8> {
    SigningTokens::new(test_key(), SITE)
        .subject(sub)
        .token(key)
        .unwrap()
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn ask_plan_approve_done() {
    let env = Env::start(params(&["down/mock"]), set_p0_script(42.0)).await;
    let before = env.p0();
    let (id, items) = env.ask("set p0 to 42").await.unwrap();
    assert!(items.len() >= 3, "progress was streamed: {items:?}");
    assert_eq!(
        field(items.last().unwrap(), "state").as_deref(),
        Some("awaiting_approval")
    );
    let v = env.wait_state(&id, "awaiting_approval").await;
    assert_eq!(plan_len(&v), 1);
    assert_ne!(before, 42.0);

    // The read-only tool ran in-process: the real ~meta went back to the model.
    let seen = env.llm.seen();
    assert_eq!(seen.len(), 2);
    assert_eq!(seen[0]["model"], "claude-sonnet-5-5");
    let results = seen[1]["messages"][2]["content"].as_array().unwrap();
    assert!(results[0]["content"].as_str().unwrap().contains("°C"));
    assert_eq!(results[1]["is_error"], false);

    let key = format!("{P0}/~set");
    let r = env
        .task_action(
            &env.human(Perm::Config),
            &id,
            "approve",
            approvals(&[(&key, human_token("user:op", &key))]),
        )
        .await
        .unwrap();
    assert_eq!(field(&r.unwrap(), "state").as_deref(), Some("running"));
    env.wait_state(&id, "done").await;
    assert_eq!(env.p0(), 42.0);
    env.stop().await;
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn proposal_outside_allowed_prefixes_is_refused() {
    let env = Env::start(params(&["down/mocky"]), set_p0_script(42.0)).await;
    let before = env.p0();
    let (id, _) = env.ask("set p0 to 42").await.unwrap();
    let v = env.wait_state(&id, "done").await;
    assert_eq!(plan_len(&v), 0, "nothing was added to the plan");
    let seen = env.llm.seen();
    let r = &seen[1]["messages"][2]["content"][1];
    assert_eq!(r["is_error"], true);
    assert!(r["content"].as_str().unwrap().contains("allowed_prefixes"));
    assert_eq!(env.p0(), before);

    // Empty allowed_prefixes: nothing is writable.
    env.stop().await;
    let env = Env::start(params(&[]), set_p0_script(42.0)).await;
    let (id, _) = env.ask("set p0 to 42").await.unwrap();
    assert_eq!(plan_len(&env.wait_state(&id, "done").await), 0);
    env.stop().await;
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn reject_and_cancel() {
    let mut script = set_p0_script(42.0);
    script.extend(set_p0_script(43.0));
    let env = Env::start(params(&["down/mock"]), script).await;
    let before = env.p0();
    let op = env.human(Perm::Config);

    let (a, _) = env.ask("set p0 to 42").await.unwrap();
    env.wait_state(&a, "awaiting_approval").await;
    let reason = Value::Map(BTreeMap::from([("reason".into(), Value::from("no"))]));
    env.task_action(&op, &a, "reject", reason).await.unwrap();
    let v = env.wait_state(&a, "failed").await;
    assert!(field(&v, "error")
        .unwrap()
        .starts_with("rejected by user:op"));
    // A rejected task cannot be approved any more.
    let key = format!("{P0}/~set");
    let e = env
        .task_action(
            &op,
            &a,
            "approve",
            approvals(&[(&key, human_token("user:op", &key))]),
        )
        .await
        .unwrap_err();
    assert!(e.is(Status::InvalidParameter), "{e}");

    let (b, _) = env.ask("set p0 to 43").await.unwrap();
    env.wait_state(&b, "awaiting_approval").await;
    env.task_action(&op, &b, "cancel", Value::Map(BTreeMap::new()))
        .await
        .unwrap();
    let v = env.wait_state(&b, "failed").await;
    assert!(field(&v, "error")
        .unwrap()
        .starts_with("cancelled by user:op"));
    assert_eq!(env.p0(), before);
    env.stop().await;
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn budget_exhausted() {
    let p = AgentParams {
        budget_tokens_day: 100,
        ..params(&["down/mock"])
    };
    // 60 + 80 tokens: the first task spends the whole budget.
    let env = Env::start(p, set_p0_script(42.0)).await;
    let (id, _) = env.ask("set p0 to 42").await.unwrap();
    let v = env.wait_state(&id, "awaiting_approval").await;
    assert!(matches!(&v, Value::Map(m) if m.get("tokens") == Some(&Value::UInt(140))));
    let e = env.ask("again").await.unwrap_err();
    assert!(e.is(Status::RateLimited), "{e}");
    assert_eq!(env.llm.seen().len(), 2, "no LLM call for a refused ask");
    env.stop().await;
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn approve_needs_config_and_the_same_human() {
    let env = Env::start(params(&["down/mock"]), set_p0_script(42.0)).await;
    let before = env.p0();
    let (id, _) = env.ask("set p0 to 42").await.unwrap();
    env.wait_state(&id, "awaiting_approval").await;
    let key = format!("{P0}/~set");

    // Caller with write only: refused by the SDK before the driver runs.
    let e = env
        .task_action(
            &env.human(Perm::Write),
            &id,
            "approve",
            approvals(&[(&key, human_token("user:op", &key))]),
        )
        .await
        .unwrap_err();
    assert!(e.is(Status::PermissionDenied), "{e}");

    // Approval minted by someone else than the approver.
    let e = env
        .task_action(
            &env.human(Perm::Config),
            &id,
            "approve",
            approvals(&[(&key, human_token("user:other", &key))]),
        )
        .await
        .unwrap_err();
    assert!(e.is(Status::PermissionDenied), "{e}");

    // An AI subject cannot approve.
    let e = env
        .task_action(
            &env.human(Perm::Config),
            &id,
            "approve",
            approvals(&[(&key, human_token("ai:x", &key))]),
        )
        .await
        .unwrap_err();
    assert!(e.is(Status::PermissionDenied), "{e}");

    // Approval for a key that is not in the plan.
    let other = format!("{P0}x/~set");
    let e = env
        .task_action(
            &env.human(Perm::Config),
            &id,
            "approve",
            approvals(&[
                (&key, human_token("user:op", &key)),
                (&other, human_token("user:op", &other)),
            ]),
        )
        .await
        .unwrap_err();
    assert!(e.is(Status::InvalidParameter), "{e}");

    env.wait_state(&id, "awaiting_approval").await;
    assert_eq!(env.p0(), before);
    env.stop().await;
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn write_ops_run_with_the_service_token_when_allowed() {
    let p = AgentParams {
        require_approval: wyrm_link_agent::tools::ApprovalMode::Config,
        ..params(&["down/mock"])
    };
    let env = Env::start(p, set_p0_script(7.0)).await;
    let (id, items) = env.ask("set p0 to 7").await.unwrap();
    assert_eq!(
        field(items.last().unwrap(), "state").as_deref(),
        Some("running")
    );
    env.wait_state(&id, "done").await;
    assert_eq!(env.p0(), 7.0);
    env.stop().await;
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn root_cfg_has_the_defaults() {
    let env = Env::start(AgentParams::default(), Vec::new()).await;
    let m = env.agent.as_ref().unwrap().ctx().meta("").unwrap();
    assert_eq!(
        m.cfg_value("model"),
        Some(&Value::from("claude-sonnet-5-5"))
    );
    assert_eq!(m.cfg_value("require_approval"), Some(&Value::from("write")));
    assert_eq!(
        m.cfg_value("allowed_prefixes"),
        Some(&Value::Array(Vec::new()))
    );
    assert_eq!(m.attr_value("driver"), Some(&Value::from("agent")));
    assert!(m.actions.as_ref().unwrap().contains_key("ask"));
    env.stop().await;
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn read_tools_stay_inside_the_prefixes_and_tasks_are_restricted() {
    let script = vec![
        tool_use(&[
            ("t1", "node_meta", json!({"path": "sys/links"})),
            ("t2", "tree_list", json!({"path": "down"})),
            (
                "t3",
                "value_get",
                json!({"paths": ["down/mock/p0", "down/agent/tasks"]}),
            ),
            ("t4", "flow_get", json!({"id": "f1"})),
            ("t5", "tree_list", json!({"path": "down/mock"})),
        ]),
        end("done"),
    ];
    let env = Env::start(params(&["down/mock"]), script).await;
    let (id, _) = env.ask("look around").await.unwrap();
    env.wait_state(&id, "done").await;
    let seen = env.llm.seen();
    let r = seen[1]["messages"][2]["content"].as_array().unwrap();
    for i in [0, 1, 3] {
        assert_eq!(r[i]["is_error"], true, "tool {i}: {}", r[i]);
        assert!(r[i]["content"].as_str().unwrap().contains("may not read"));
    }
    let vals: Json = serde_json::from_str(r[2]["content"].as_str().unwrap()).unwrap();
    assert!(vals["down/mock/p0"]["v"].is_number());
    assert!(vals["down/agent/tasks"]["error"].is_string());
    assert_eq!(r[4]["is_error"], false);

    // The public ~val carries the state only; the record needs `list`.
    let pv = env.task(&id);
    assert!(matches!(&pv, Value::Map(m) if m.len() == 1));
    let e = env.doc_with(&id, None).await.unwrap_err();
    assert!(e.contains("PermissionDenied"), "{e}");
    let rec = env.doc(&id).await;
    assert_eq!(field(&rec, "owner").as_deref(), Some("user:op"));
    let (att, _) = {
        let key = "wy/test/down/agent/tasks/~meta";
        let rx = env.session.get(key).await.unwrap();
        let s = rx.recv_async().await.unwrap();
        let s = s.result().unwrap();
        let att: wyrm_core::Attachment =
            wyrm_core::codec::from_slice(&s.attachment().unwrap().to_bytes()).unwrap();
        (att, ())
    };
    assert_eq!(
        att.status,
        Some(wyrm_core::status::StatusCode::Known(
            Status::PermissionDenied
        ))
    );
    env.stop().await;
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn service_token_is_scoped() {
    let env = Env::start(params(&["down/mock"]), set_p0_script(1.0)).await;
    // A second link the agent is not allowed to touch; it trusts the agent key.
    let agent_key = ed25519_dalek::SigningKey::from_bytes(&AGENT_SEED);
    let mut cfg = LinkConfig::new(SITE, "other");
    cfg.admin_keys = vec![test_key().verifying_key(), agent_key.verifying_key()];
    let other = wyrm_link_sdk::spawn::<Mock>(
        env.session.clone(),
        cfg,
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
    let toks = wyrm_link_agent::service_tokens(
        agent_key,
        SITE,
        "agent",
        &["wy/test/down/mock".to_owned()],
    );
    // No token at all outside the grants; `none` on its own subtree and sys.
    assert!(toks.token("wy/test/down/other/p0/~set").is_none());
    assert!(toks.token("wy/test/flows/~act/deploy").is_none());
    let claims = |t: Vec<u8>| -> wyrm_core::ptok::PtokClaims {
        wyrm_core::codec::from_slice(wyrm_core::ptok::split(&t).unwrap().claims).unwrap()
    };
    let c = claims(toks.token("wy/test/sys/links/~act/install").unwrap());
    assert_eq!(c.grants[0].p, Perm::None);
    assert_eq!(c.sub, "ai:agent");
    assert_eq!(c.max, Perm::Write);
    let c = claims(toks.token("wy/test/pub/acme:pump/~meta").unwrap());
    assert_eq!(c.grants[0].p, Perm::Read);

    let svc = WyrmClient::new(env.session.clone())
        .with_timeout(Duration::from_secs(5))
        .with_tokens(Arc::new(toks));
    // The links refuse it outside the grants...
    let e = svc.set("wy/test/down/other/p0", 5.0).await.unwrap_err();
    assert!(e.is(Status::PermissionDenied), "{e}");
    let (id, _) = env.ask("set p0 to 1").await.unwrap();
    env.wait_state(&id, "awaiting_approval").await;
    let key = format!("wy/test/down/agent/tasks/{id}/~state");
    let e = env.doc_with(&id, svc.proof(&key)).await.unwrap_err();
    assert!(e.contains("PermissionDenied"), "{e}");
    let e = env
        .task_action(&svc, &id, "cancel", Value::Map(BTreeMap::new()))
        .await
        .unwrap_err();
    assert!(e.is(Status::PermissionDenied), "{e}");
    // ...and accept it inside.
    svc.set(P0, 5.0).await.unwrap();
    assert_eq!(env.p0(), 5.0);
    other.stop().await;
    env.stop().await;
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn slow_model_keeps_the_ask_stream_alive() {
    let env = Env::start(params(&["down/mock"]), set_p0_script(42.0)).await;
    *env.llm.delay.lock().unwrap() = Duration::from_millis(2500);
    let client = env.human_with(Perm::Config, Duration::from_secs(2));
    let (id, items) = env.ask_with(&client, "set p0 to 42").await.unwrap();
    assert!(items
        .iter()
        .any(|i| field(i, "event").as_deref() == Some("wait")));
    assert_eq!(
        field(items.last().unwrap(), "state").as_deref(),
        Some("awaiting_approval")
    );
    env.wait_state(&id, "awaiting_approval").await;
    env.stop().await;
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn one_step_per_key_and_only_the_asker_may_cancel() {
    let script = vec![
        tool_use(&[
            (
                "t1",
                "propose",
                json!({"op": "set", "path": "down/mock/p0", "value": 1}),
            ),
            (
                "t2",
                "propose",
                json!({"op": "set", "path": "down/mock/p0", "value": 2}),
            ),
        ]),
        end("Plan: set p0."),
    ];
    let env = Env::start(params(&["down/mock"]), script).await;
    let (id, _) = env.ask("set p0").await.unwrap();
    let rec = env.wait_state(&id, "awaiting_approval").await;
    assert_eq!(plan_len(&rec), 1);
    let seen = env.llm.seen();
    let r = &seen[1]["messages"][2]["content"][1];
    assert_eq!(r["is_error"], true);
    assert!(r["content"].as_str().unwrap().contains("one step per key"));

    // Another writer may neither cancel nor reject the task.
    let stranger = WyrmClient::new(env.session.clone())
        .with_timeout(Duration::from_secs(5))
        .with_tokens(Arc::new(
            SigningTokens::new(test_key(), SITE)
                .subject("user:x")
                .max(Perm::Write),
        ));
    for a in ["cancel", "reject"] {
        let e = env
            .task_action(&stranger, &id, a, Value::Map(BTreeMap::new()))
            .await
            .unwrap_err();
        assert!(e.is(Status::PermissionDenied), "{a}: {e}");
    }
    env.wait_state(&id, "awaiting_approval").await;
    env.stop().await;
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn restart_keeps_tasks_and_budget() {
    let dir = temp_dir("restart");
    let p = AgentParams {
        budget_tokens_day: 100,
        ..params(&["down/mock"])
    };
    let mut env = Env::start_in(p, set_p0_script(42.0), Some(dir.clone())).await;
    let (id, _) = env.ask("set p0 to 42").await.unwrap();
    env.wait_state(&id, "awaiting_approval").await;

    env.restart_agent(Vec::new()).await;
    // Listed again and still awaiting approval, with its plan and tokens.
    let v = env.wait_state(&id, "awaiting_approval").await;
    assert_eq!(plan_len(&v), 1);
    assert!(matches!(&v, Value::Map(m) if m.get("tokens") == Some(&Value::UInt(140))));
    assert_eq!(field(&v, "owner").as_deref(), Some("user:op"));
    let human = env.human(Perm::Config);
    let ctx = env.agent.as_ref().unwrap().ctx();
    assert!(
        ctx.meta(&format!("tasks/{id}")).is_some(),
        "task node re-declared"
    );
    // The budget (140 of 100 used) survived: no LLM call for a new ask.
    let e = env.ask("again").await.unwrap_err();
    assert!(e.is(Status::RateLimited), "{e}");
    assert!(env.llm.seen().is_empty());
    // And the reloaded task is approvable.
    let key = format!("{P0}/~set");
    env.task_action(
        &human,
        &id,
        "approve",
        approvals(&[(&key, human_token("user:op", &key))]),
    )
    .await
    .unwrap();
    env.wait_state(&id, "done").await;
    assert_eq!(env.p0(), 42.0);

    // Done stays done across another restart.
    env.restart_agent(Vec::new()).await;
    env.wait_state(&id, "done").await;
    env.stop().await;
    let _ = std::fs::remove_dir_all(dir);
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn planning_task_fails_on_restart() {
    let dir = temp_dir("interrupt");
    let mut env = Env::start_in(
        params(&["down/mock"]),
        set_p0_script(42.0),
        Some(dir.clone()),
    )
    .await;
    *env.llm.delay.lock().unwrap() = Duration::from_secs(30);
    let args = Value::Map(BTreeMap::from([("task".to_owned(), Value::from("slow"))]));
    let mut s = env
        .human(Perm::Config)
        .invoke("wy/test/down/agent", "ask", args)
        .await
        .unwrap();
    let first = s.next().await.unwrap().unwrap().unwrap();
    let id = field(&first, "task").unwrap();
    drop(s);
    env.restart_agent(set_p0_script(1.0)).await;
    let v = env.wait_state(&id, "failed").await;
    assert_eq!(
        field(&v, "error").as_deref(),
        Some("interrupted by restart")
    );
    // Never resumed: the new model was not called.
    assert!(env.llm.seen().is_empty());
    // A new task (same second, sequence restored) gets a new id.
    let (id2, _) = env.ask("set p0 to 1").await.unwrap();
    assert_ne!(id2, id);
    env.wait_state(&id2, "awaiting_approval").await;
    env.wait_state(&id, "failed").await;
    env.stop().await;
    let _ = std::fs::remove_dir_all(dir);
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn concurrent_asks_cannot_both_spend_the_last_budget() {
    let p = AgentParams {
        budget_tokens_day: 100,
        ..params(&["down/mock"])
    };
    let env = Env::start(p, set_p0_script(42.0)).await;
    *env.llm.delay.lock().unwrap() = Duration::from_millis(300);
    let (a, b) = tokio::join!(env.ask("one"), env.ask("two"));
    let refused = [&a, &b]
        .iter()
        .filter(|r| matches!(r, Err(e) if e.is(Status::RateLimited)))
        .count();
    assert_eq!(refused, 1, "{a:?} / {b:?}");
    let id = match (a, b) {
        (Ok((id, _)), _) | (_, Ok((id, _))) => id,
        _ => unreachable!(),
    };
    env.wait_state(&id, "awaiting_approval").await;
    assert_eq!(
        env.llm.seen().len(),
        2,
        "only the admitted task called the model"
    );
    env.stop().await;
}
