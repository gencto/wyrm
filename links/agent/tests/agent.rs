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
const P0: &str = "wy/test/downstream/mock/p0";

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
    json!({"content": content, "stop_reason": "tool_use", "usage": {"input_tokens": 5000, "output_tokens": 10}})
}

fn end(text: &str) -> Json {
    json!({"content": [{"type": "text", "text": text}], "stop_reason": "end_turn", "usage": {"input_tokens": 6000, "output_tokens": 20}})
}

/// Read p0, propose `p0 := 42`, finish.
fn set_p0_script(value: f64) -> Vec<Json> {
    vec![
        tool_use(&[
            ("t1", "node_meta", json!({"path": "downstream/mock/p0"})),
            (
                "t2",
                "propose",
                json!({"op": "set", "path": "downstream/mock/p0", "value": value, "reason": "operator asked"}),
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
        let mut s = client
            .invoke("wy/test/downstream/agent", "ask", args)
            .await?;
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
        let key = format!("wy/test/downstream/agent/tasks/{id}/~state");
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
        let key = format!("wy/test/downstream/agent/tasks/{id}/~state");
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
            .invoke_one(
                &format!("wy/test/downstream/agent/tasks/{id}"),
                action,
                args,
            )
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
    let env = Env::start(params(&["downstream/mock"]), set_p0_script(42.0)).await;
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
            &env.human(Perm::Write),
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
    let env = Env::start(params(&["downstream/mocky"]), set_p0_script(42.0)).await;
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
    let env = Env::start(params(&["downstream/mock"]), script).await;
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
        budget_tokens_day: 10_000,
        ..params(&["downstream/mock"])
    };
    // 5010 + 6020 tokens: the first task spends the whole budget.
    let env = Env::start(p, set_p0_script(42.0)).await;
    let (id, _) = env.ask("set p0 to 42").await.unwrap();
    let v = env.wait_state(&id, "awaiting_approval").await;
    assert!(matches!(&v, Value::Map(m) if m.get("tokens") == Some(&Value::UInt(11_030))));
    let e = env.ask("again").await.unwrap_err();
    assert!(e.is(Status::RateLimited), "{e}");
    assert_eq!(env.llm.seen().len(), 2, "no LLM call for a refused ask");
    env.stop().await;
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn approve_needs_write_and_the_same_human() {
    let env = Env::start(params(&["downstream/mock"]), set_p0_script(42.0)).await;
    let before = env.p0();
    let (id, _) = env.ask("set p0 to 42").await.unwrap();
    env.wait_state(&id, "awaiting_approval").await;
    let key = format!("{P0}/~set");

    // Caller with read only: refused by the SDK before the driver runs. `write` on the task
    // is enough (ADR 0049 §3): the tokens decide what a person may approve.
    let e = env
        .task_action(
            &env.human(Perm::Read),
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
            &env.human(Perm::Write),
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
            &env.human(Perm::Write),
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
            &env.human(Perm::Write),
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
        ..params(&["downstream/mock"])
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
            ("t2", "tree_list", json!({"path": "downstream"})),
            (
                "t3",
                "value_get",
                json!({"paths": ["downstream/mock/p0", "downstream/agent/tasks"]}),
            ),
            ("t4", "flow_get", json!({"id": "f1"})),
            ("t5", "tree_list", json!({"path": "downstream/mock"})),
        ]),
        end("done"),
    ];
    let env = Env::start(params(&["downstream/mock"]), script).await;
    let (id, _) = env.ask("look around").await.unwrap();
    env.wait_state(&id, "done").await;
    let seen = env.llm.seen();
    let r = seen[1]["messages"][2]["content"].as_array().unwrap();
    for i in [0, 1, 3] {
        assert_eq!(r[i]["is_error"], true, "tool {i}: {}", r[i]);
        assert!(r[i]["content"].as_str().unwrap().contains("may not read"));
    }
    let vals: Json = serde_json::from_str(r[2]["content"].as_str().unwrap()).unwrap();
    assert!(vals["downstream/mock/p0"]["v"].is_number());
    assert!(vals["downstream/agent/tasks"]["error"].is_string());
    assert_eq!(r[4]["is_error"], false);

    // The public ~val carries the state and where the run is; the record needs `list`.
    let pv = env.task(&id);
    assert!(
        matches!(&pv, Value::Map(m) if m.keys().all(|k| ["state", "step", "of"].contains(&k.as_str()))),
        "{pv:?}"
    );
    let e = env.doc_with(&id, None).await.unwrap_err();
    assert!(e.contains("PermissionDenied"), "{e}");
    let rec = env.doc(&id).await;
    assert_eq!(field(&rec, "owner").as_deref(), Some("user:op"));
    let (att, _) = {
        let key = "wy/test/downstream/agent/tasks/~meta";
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
    let env = Env::start(params(&["downstream/mock"]), set_p0_script(1.0)).await;
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
        &["wy/test/downstream/mock".to_owned()],
    );
    // No token at all outside the grants; `none` on its own subtree and sys.
    assert!(toks.token("wy/test/downstream/other/p0/~set").is_none());
    assert!(toks.token("wy/test/dataflows/~act/deploy").is_none());
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
    let e = svc
        .set("wy/test/downstream/other/p0", 5.0)
        .await
        .unwrap_err();
    assert!(e.is(Status::PermissionDenied), "{e}");
    let (id, _) = env.ask("set p0 to 1").await.unwrap();
    env.wait_state(&id, "awaiting_approval").await;
    let key = format!("wy/test/downstream/agent/tasks/{id}/~state");
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
    let env = Env::start(params(&["downstream/mock"]), set_p0_script(42.0)).await;
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
async fn restart_keeps_tasks_and_budget() {
    let dir = temp_dir("restart");
    let p = AgentParams {
        budget_tokens_day: 10_000,
        ..params(&["downstream/mock"])
    };
    let mut env = Env::start_in(p, set_p0_script(42.0), Some(dir.clone())).await;
    let (id, _) = env.ask("set p0 to 42").await.unwrap();
    env.wait_state(&id, "awaiting_approval").await;

    env.restart_agent(Vec::new()).await;
    // Listed again and still awaiting approval, with its plan and tokens.
    let v = env.wait_state(&id, "awaiting_approval").await;
    assert_eq!(plan_len(&v), 1);
    assert!(matches!(&v, Value::Map(m) if m.get("tokens") == Some(&Value::UInt(11_030))));
    assert_eq!(field(&v, "owner").as_deref(), Some("user:op"));
    let human = env.human(Perm::Config);
    let ctx = env.agent.as_ref().unwrap().ctx();
    assert!(
        ctx.meta(&format!("tasks/{id}")).is_some(),
        "task node re-declared"
    );
    // The budget (11030 of 10000 used) survived: no LLM call for a new ask.
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
        params(&["downstream/mock"]),
        set_p0_script(42.0),
        Some(dir.clone()),
    )
    .await;
    *env.llm.delay.lock().unwrap() = Duration::from_secs(30);
    let args = Value::Map(BTreeMap::from([("task".to_owned(), Value::from("slow"))]));
    let mut s = env
        .human(Perm::Config)
        .invoke("wy/test/downstream/agent", "ask", args)
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
        budget_tokens_day: 10_000,
        ..params(&["downstream/mock"])
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

/// ADR 0049 §4: approvals are named by step number, so two steps on one key both work; by
/// request key only when one step alone has it.
#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn two_steps_on_one_key_and_only_the_asker_may_cancel() {
    let script = vec![
        tool_use(&[
            (
                "t1",
                "propose",
                json!({"op": "set", "path": "downstream/mock/p0", "value": 1}),
            ),
            (
                "t2",
                "propose",
                json!({"op": "set", "path": "downstream/mock/p0", "value": 2}),
            ),
        ]),
        end("Plan: set p0 twice."),
    ];
    let env = Env::start(params(&["downstream/mock"]), script).await;
    let (id, _) = env.ask("set p0").await.unwrap();
    let rec = env.wait_state(&id, "awaiting_approval").await;
    assert_eq!(plan_len(&rec), 2);
    // ADR 0049 §8: what `propose` answers
    let seen = env.llm.seen();
    let r = &seen[1]["messages"][2]["content"][1];
    assert_eq!(r["is_error"], false);
    let a: Json = serde_json::from_str(r["content"].as_str().unwrap()).unwrap();
    assert_eq!(
        (&a["ok"], &a["n"], &a["check"]),
        (&json!(true), &json!(2), &json!("now"))
    );
    // the second change on the node needs the first
    assert_eq!(a["after"], json!([1]));

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

    let key = format!("{P0}/~set");
    let human = env.human(Perm::Write);
    // the key names two steps
    let e = env
        .task_action(
            &human,
            &id,
            "approve",
            approvals(&[(&key, human_token("user:op", &key))]),
        )
        .await
        .unwrap_err();
    assert!(e.is(Status::InvalidParameter), "{e}");
    assert!(e.message.contains("several steps"), "{e}");
    // a step number the plan does not have
    let e = env
        .task_action(
            &human,
            &id,
            "approve",
            approvals(&[("3", human_token("user:op", &key))]),
        )
        .await
        .unwrap_err();
    assert!(e.is(Status::InvalidParameter), "{e}");
    env.task_action(
        &human,
        &id,
        "approve",
        approvals(&[
            ("1", human_token("user:op", &key)),
            ("2", human_token("user:op", &key)),
        ]),
    )
    .await
    .unwrap();
    env.wait_state(&id, "done").await;
    assert_eq!(env.p0(), 2.0, "both steps ran, in order");
    env.stop().await;
}

fn plan_step(doc: &Value, i: usize) -> Value {
    match doc {
        Value::Map(m) => match m.get("plan") {
            Some(Value::Array(a)) => a[i].clone(),
            _ => panic!("no plan in {doc:?}"),
        },
        _ => panic!("not a record: {doc:?}"),
    }
}

fn result_of(step: &Value) -> Option<(String, String)> {
    let Value::Map(m) = step else { return None };
    let r = m.get("result")?;
    Some((field(r, "status")?, field(r, "message")?))
}

fn with(mut args: Value, k: &str, v: Value) -> Value {
    if let Value::Map(m) = &mut args {
        m.insert(k.to_owned(), v);
    }
    args
}

fn get<'a>(v: &'a Value, k: &str) -> &'a Value {
    match v {
        Value::Map(m) => m.get(k).unwrap_or(&Value::Null),
        _ => &Value::Null,
    }
}

/// SHA-256 of a request body, as the `args` claim holds it.
fn sha256(b: &[u8]) -> [u8; 32] {
    let hex = wyrm_mcp::check::payload_sha256(b);
    let mut out = [0u8; 32];
    for (i, o) in out.iter_mut().enumerate() {
        *o = u8::from_str_radix(&hex[2 * i..2 * i + 2], 16).unwrap();
    }
    out
}

/// The model asks which point, then plans: set p0, wait, expect; set p1, expect.
fn ask_then_plan_script() -> Vec<Json> {
    vec![
        tool_use(&[(
            "q",
            "ask_user",
            json!({"question": "Which point first?", "options": [
                {"id": "p0", "label": "point 0", "detail": "downstream/mock/p0"},
                {"id": "p1", "label": "point 1"},
            ]}),
        )]),
        tool_use(&[
            (
                "t1",
                "propose",
                json!({"op": "set", "path": "downstream/mock/p0", "value": 7, "reason": "first"}),
            ),
            (
                "t2",
                "propose",
                json!({"op": "wait", "path": "downstream/mock/p0", "timeout_s": 5}),
            ),
            (
                "t3",
                "propose",
                json!({"op": "expect", "path": "downstream/mock/p0", "equals": 7, "timeout_s": 5}),
            ),
            (
                "t4",
                "propose",
                json!({"op": "set", "path": "downstream/mock/p1", "value": 9, "reason": "second"}),
            ),
            (
                "t5",
                "propose",
                json!({"op": "expect", "path": "downstream/mock/p1", "equals": 9, "timeout_s": 5}),
            ),
        ]),
        end("Plan: set both and prove it."),
    ]
}

/// ADR 0049, "Consequences": ask → ask_user → answer → plan → partial approve (one step
/// skipped, its dependant skipped) → wait/expect → done. Also what stays refused: an
/// approval of another plan, one bound to other arguments, one from a caller without the
/// level of the step.
#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn ask_answer_plan_partial_approve_prove_done() {
    let env = Env::start(params(&["downstream/mock"]), ask_then_plan_script()).await;
    let human = env.human(Perm::Write);
    let (id, items) = env.ask("set the points").await.unwrap();
    assert_eq!(
        field(items.last().unwrap(), "state").as_deref(),
        Some("awaiting_answer"),
        "the ask stream ends when the model asks back: {items:?}"
    );
    let doc = env.wait_state(&id, "awaiting_answer").await;
    let Value::Array(qs) = get(&doc, "questions") else {
        panic!("questions: {doc:?}")
    };
    assert_eq!(qs.len(), 1);
    assert_eq!(field(&qs[0], "id").as_deref(), Some("q1"));
    assert_eq!(field(&qs[0], "text").as_deref(), Some("Which point first?"));
    assert!(matches!(get(&qs[0], "options"), Value::Array(o) if o.len() == 2));

    // an option the question does not have; a question that does not wait; another caller
    let answers = |q: &str, v: Value| {
        Value::Map(BTreeMap::from([(
            "answers".to_owned(),
            Value::Map(BTreeMap::from([(q.to_owned(), v)])),
        )]))
    };
    let pick = |o: &str| Value::Array(vec![Value::from(o)]);
    for bad in [
        answers("q1", pick("p9")),
        answers("q2", pick("p0")),
        answers(
            "q1",
            Value::Array(vec![Value::from("p0"), Value::from("p1")]),
        ),
        answers("q1", Value::from("my own words")),
        Value::Map(BTreeMap::new()),
    ] {
        let e = env
            .task_action(&human, &id, "answer", bad)
            .await
            .unwrap_err();
        assert!(e.is(Status::InvalidParameter), "{e}");
    }
    let stranger = WyrmClient::new(env.session.clone())
        .with_timeout(Duration::from_secs(5))
        .with_tokens(Arc::new(
            SigningTokens::new(test_key(), SITE)
                .subject("user:x")
                .max(Perm::Write),
        ));
    let e = env
        .task_action(&stranger, &id, "answer", answers("q1", pick("p0")))
        .await
        .unwrap_err();
    assert!(e.is(Status::PermissionDenied), "{e}");
    env.wait_state(&id, "awaiting_answer").await;

    // the answer resumes the model; its stream carries the progress and ends with the state
    let mut s = human
        .invoke(
            &format!("wy/test/downstream/agent/tasks/{id}"),
            "answer",
            answers("q1", pick("p0")),
        )
        .await
        .unwrap();
    let mut items = Vec::new();
    while let Some(i) = s.next().await {
        if let Some(v) = i.unwrap() {
            items.push(v);
        }
    }
    assert_eq!(
        field(items.last().unwrap(), "state").as_deref(),
        Some("awaiting_approval"),
        "{items:?}"
    );
    // the model got the answer as the result of its question
    let seen = env.llm.seen();
    let r = &seen[1]["messages"][2]["content"][0];
    assert_eq!(r["tool_use_id"], "q");
    assert_eq!(r["content"], "point 0 (p0)");

    let doc = env.wait_state(&id, "awaiting_approval").await;
    assert_eq!(plan_len(&doc), 5);
    let hash = field(&doc, "plan_hash").expect("plan_hash");
    // the plan is a plan of `wyrm-agent run` as it stands (ADR 0049 §6)
    let as_run = wyrm_mcp::gw::parse_plan(&wyrm_mcp::json::value_to_json(get(&doc, "plan")))
        .expect("a wyrm-agent run plan");
    assert!(matches!(as_run[0], wyrm_mcp::gw::Step::Set { .. }));
    assert!(matches!(as_run[1], wyrm_mcp::gw::Step::Wait { .. }));
    assert!(matches!(
        &as_run[2],
        wyrm_mcp::gw::Step::Expect { test: wyrm_mcp::gw::Test::Equals(v), .. } if v == &json!(7)
    ));
    let step = plan_step(&doc, 0);
    // the plan is in the `wyrm-agent run` format
    assert_eq!(field(&step, "set").as_deref(), Some(P0));
    assert_eq!(get(&step, "value"), &Value::UInt(7));
    assert_eq!(get(&step, "n"), &Value::UInt(1));
    assert_eq!(get(&step, "approval"), &Value::Bool(true));
    assert_eq!(field(&step, "check").as_deref(), Some("now"));
    assert_eq!(result_of(&step), None);
    let proof = plan_step(&doc, 2);
    assert_eq!(field(&proof, "expect").as_deref(), Some(P0));
    assert_eq!(get(&proof, "equals"), &Value::UInt(7));
    assert_eq!(get(&proof, "approval"), &Value::Bool(false));
    assert_eq!(field(&proof, "level").as_deref(), Some("read"));
    assert_eq!(get(&proof, "after"), &Value::Array(vec![Value::UInt(1)]));
    assert_eq!(
        get(&plan_step(&doc, 4), "after"),
        &Value::Array(vec![Value::UInt(4)])
    );
    // the public value says where the task is, and nothing the model wrote
    let pv = env.task(&id);
    assert_eq!(get(&pv, "of"), &Value::UInt(5));
    assert_eq!(get(&pv, "step"), &Value::UInt(0));

    let p1 = || {
        let v = env.mock.as_ref().unwrap().ctx().last("p1").unwrap().v;
        v.as_f64().unwrap()
    };
    let p1_before = p1();
    let k0 = format!("{P0}/~set");
    let one = || approvals(&[("1", human_token("user:op", &k0))]);

    // nothing approved at all
    let e = env
        .task_action(&human, &id, "approve", approvals(&[]))
        .await
        .unwrap_err();
    assert!(e.is(Status::InvalidParameter), "{e}");
    // an approval of a step that only reads
    let e = env
        .task_action(
            &human,
            &id,
            "approve",
            approvals(&[("3", human_token("user:op", &k0))]),
        )
        .await
        .unwrap_err();
    assert!(e.is(Status::InvalidParameter), "{e}");
    // an approval made for another plan
    let args = with(one(), "plan", Value::from("0".repeat(64)));
    let e = env
        .task_action(&human, &id, "approve", args)
        .await
        .unwrap_err();
    assert!(e.is(Status::InvalidParameter), "{e}");
    assert!(e.message.contains("read it again"), "{e}");
    // an approval bound to other arguments is found before anything runs
    let bound = SigningTokens::new(test_key(), SITE)
        .subject("user:op")
        .bound_to([3; 32])
        .token(&k0)
        .unwrap();
    let e = env
        .task_action(&human, &id, "approve", approvals(&[("1", bound)]))
        .await
        .unwrap_err();
    assert!(e.is(Status::PermissionDenied), "{e}");
    // a token below the level of the step: the person may not approve it
    let weak = SigningTokens::new(test_key(), SITE)
        .subject("user:op")
        .max(Perm::Read)
        .token(&k0)
        .unwrap();
    let e = env
        .task_action(&human, &id, "approve", approvals(&[("1", weak)]))
        .await
        .unwrap_err();
    assert!(e.is(Status::PermissionDenied), "{e}");
    assert!(e.message.contains("step 1"), "{e}");
    env.wait_state(&id, "awaiting_approval").await;
    assert_ne!(env.p0(), 7.0);

    // step 1 with a token for exactly its arguments; step 4 left out, step 5 needs it
    let body = wyrm_client::set_payload(Value::UInt(7)).unwrap();
    let tok = SigningTokens::new(test_key(), SITE)
        .subject("user:op")
        .bound_to(sha256(&body))
        .token(&k0)
        .unwrap();
    let args = with(approvals(&[("1", tok)]), "plan", Value::from(hash.as_str()));
    env.task_action(&human, &id, "approve", args).await.unwrap();
    let doc = env.wait_state(&id, "done").await;
    assert_eq!(env.p0(), 7.0);
    assert_eq!(p1(), p1_before, "the skipped step was never sent");
    let status = |i: usize| result_of(&plan_step(&doc, i)).unwrap();
    assert_eq!(status(0).0, "ok");
    assert_eq!(status(1).0, "ok", "wait: {:?}", status(1));
    assert_eq!(status(2).0, "ok", "expect: {:?}", status(2));
    assert_eq!(
        status(3),
        ("skipped".to_owned(), "skipped by user:op".to_owned())
    );
    assert_eq!(
        status(4),
        ("skipped".to_owned(), "skipped: needs step 4".to_owned())
    );
    assert!(matches!(get(get(&plan_step(&doc, 0), "result"), "time"), Value::UInt(t) if *t > 0));
    assert_eq!(
        field(&doc, "plan_hash"),
        Some(hash),
        "results do not move the hash"
    );
    // progress in the public value (ADR 0049 §7)
    let pv = env.task(&id);
    assert_eq!(field(&pv, "state").as_deref(), Some("done"));
    assert_eq!(
        (get(&pv, "step"), get(&pv, "of")),
        (&Value::UInt(5), &Value::UInt(5))
    );
    // `last` holds the link's fixed words only: no text of a result, no value, no key
    assert_eq!(
        get(&pv, "last"),
        &Value::Map(BTreeMap::from([
            ("n".to_owned(), Value::UInt(5)),
            ("ok".to_owned(), Value::Bool(true)),
            ("result".to_owned(), Value::from("skipped")),
        ]))
    );
    let public = format!("{pv:?}");
    assert!(
        !public.contains("mock") && !public.contains("user:"),
        "{public}"
    );
    // the tokens used today are readable (ADR 0049 §10)
    let used = env.agent.as_ref().unwrap().ctx().last("budget_used_today");
    assert!(used.unwrap().v.as_f64().unwrap() > 0.0);
    env.stop().await;
}

/// A cancelled question ends the task; a failed proof stops the run and says where.
#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn a_question_can_be_cancelled_and_a_failed_proof_stops_the_run() {
    let env = Env::start(params(&["downstream/mock"]), ask_then_plan_script()).await;
    let human = env.human(Perm::Write);
    let (id, _) = env.ask("set the points").await.unwrap();
    env.wait_state(&id, "awaiting_answer").await;
    env.task_action(&human, &id, "cancel", Value::Map(BTreeMap::new()))
        .await
        .unwrap();
    env.wait_state(&id, "failed").await;
    env.stop().await;

    // the value never becomes what the plan expects; a step on a node that an earlier
    // step was to make is checked when it runs
    let script = vec![
        tool_use(&[
            (
                "t1",
                "propose",
                json!({"op": "set", "path": "downstream/mock/p0", "value": 3}),
            ),
            (
                "t2",
                "propose",
                json!({"op": "set", "path": "downstream/mock/p0/made", "value": 1}),
            ),
            (
                "t3",
                "propose",
                json!({"op": "expect", "path": "downstream/mock/p0", "min": 100, "timeout_s": 0.5, "after": []}),
            ),
            ("t4", "propose", json!({"op": "sleep", "seconds": 0.1})),
            // a node nothing makes
            (
                "t5",
                "propose",
                json!({"op": "set", "path": "downstream/mock/nowhere", "value": 1, "after": []}),
            ),
        ]),
        end("Plan."),
    ];
    let env = Env::start(params(&["downstream/mock"]), script).await;
    let human = env.human(Perm::Write);
    let (id, _) = env.ask("set and prove").await.unwrap();
    let doc = env.wait_state(&id, "awaiting_approval").await;
    assert_eq!(
        plan_len(&doc),
        4,
        "the step on a node nothing makes is refused"
    );
    assert_eq!(
        field(&plan_step(&doc, 1), "check").as_deref(),
        Some("at_run")
    );
    let seen = env.llm.seen();
    let refused = &seen[1]["messages"][2]["content"][4];
    assert_eq!(refused["is_error"], true, "{refused}");
    let k0 = format!("{P0}/~set");
    // only step 1: step 2 (at_run, needs 1) is left out; the proof fails
    env.task_action(
        &human,
        &id,
        "approve",
        approvals(&[("1", human_token("user:op", &k0))]),
    )
    .await
    .unwrap();
    let doc = env.wait_state(&id, "failed").await;
    assert_eq!(result_of(&plan_step(&doc, 0)).unwrap().0, "ok");
    assert_eq!(result_of(&plan_step(&doc, 1)).unwrap().0, "skipped");
    let (st, msg) = result_of(&plan_step(&doc, 2)).unwrap();
    assert_eq!(st, "failed");
    assert!(msg.contains("not as expected"), "{msg}");
    assert_eq!(result_of(&plan_step(&doc, 3)), None, "never reached");
    let pv = env.task(&id);
    assert_eq!(get(get(&pv, "last"), "n"), &Value::UInt(3));
    assert_eq!(get(get(&pv, "last"), "ok"), &Value::Bool(false));
    assert_eq!(get(get(&pv, "last"), "result"), &Value::from("failed"));
    assert!(!format!("{pv:?}").contains("not as expected"), "{pv:?}");
    assert!(field(&doc, "error").unwrap().contains("step 3"));
    env.stop().await;
}

/// ADR 0049 §9: a follow-up ask hands the model the task it follows; attached keys are read
/// first, inside the agent's bounds and the asker's rights.
#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn a_follow_up_ask_carries_its_parent_and_the_attached_keys() {
    let mut script = set_p0_script(42.0);
    script.push(end("Nothing more to do."));
    let env = Env::start(params(&["downstream/mock"]), script).await;
    let human = env.human(Perm::Write);
    let (id, _) = env.ask("set p0 to 42").await.unwrap();
    env.wait_state(&id, "awaiting_approval").await;
    let ask = |extra: Vec<(&str, Value)>| {
        let mut m = BTreeMap::from([("task".to_owned(), Value::from("and now undo it"))]);
        for (k, v) in extra {
            m.insert(k.to_owned(), v);
        }
        Value::Map(m)
    };
    let agent = "wy/test/downstream/agent";
    let keys = |k: &[&str]| Value::Array(k.iter().map(|k| Value::from(*k)).collect());
    // a parent that is not there; a key outside what the agent may read; a key the asker
    // may not read; a parent of somebody else
    for (args, want) in [
        (ask(vec![("parent", Value::from("t0-0"))]), Status::NotFound),
        (
            ask(vec![("context", keys(&["sys/links"]))]),
            Status::InvalidParameter,
        ),
    ] {
        let e = human.invoke_one(agent, "ask", args).await.unwrap_err();
        assert!(e.is(want), "{e}");
    }
    let narrow = WyrmClient::new(env.session.clone())
        .with_timeout(Duration::from_secs(5))
        .with_tokens(Arc::new(
            SigningTokens::new(test_key(), SITE)
                .subject("user:x")
                .grants(vec![wyrm_core::ptok::Grant {
                    k: "wy/test/downstream/agent/**".into(),
                    p: Perm::Write,
                }]),
        ));
    let e = narrow
        .invoke_one(agent, "ask", ask(vec![("context", keys(&[P0]))]))
        .await
        .unwrap_err();
    assert!(e.is(Status::PermissionDenied), "{e}");
    let e = narrow
        .invoke_one(
            agent,
            "ask",
            ask(vec![("parent", Value::from(id.as_str()))]),
        )
        .await
        .unwrap_err();
    assert!(e.is(Status::PermissionDenied), "{e}");

    let args = ask(vec![
        ("parent", Value::from(id.as_str())),
        ("context", keys(&["downstream/mock/p1"])),
    ]);
    let mut s = human.invoke(agent, "ask", args).await.unwrap();
    let mut next = None;
    while let Some(i) = s.next().await {
        if let Some(v) = i.unwrap() {
            next = field(&v, "task").or(next);
        }
    }
    let next = next.unwrap();
    let doc = env.wait_state(&next, "done").await;
    assert_eq!(field(&doc, "parent"), Some(id.clone()));
    assert_eq!(
        get(&doc, "context"),
        &Value::Array(vec![Value::from("wy/test/downstream/mock/p1")])
    );
    let seen = env.llm.seen();
    let first = seen[2]["messages"][0]["content"].as_str().unwrap();
    assert!(first.starts_with("and now undo it"), "{first}");
    assert!(first.contains("set p0 to 42"), "the parent's ask: {first}");
    assert!(first.contains("awaiting_approval"), "{first}");
    assert!(
        first.contains("wy/test/downstream/mock/p1: meta"),
        "{first}"
    );
    env.stop().await;
}

/// Review of ADR 0049 §2: an approval is a short-lived token made when the person approves
/// and spent when its step is sent. A step that needs a person is not taken into a plan
/// behind waits longer than an approval lives, and an approval that cannot outlive the
/// waits before its step is refused while the task still waits (the person leaves the
/// step for a follow-up), never found dead at the step.
#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn an_approval_must_outlive_the_waits_before_its_step() {
    let set = |v: u64| json!({"op": "set", "path": "downstream/mock/p1", "value": v});
    let script = vec![
        // 1. a sleep longer than an approval lives: the set after it is not taken
        tool_use(&[
            ("t0", "propose", set(5)),
            ("t1", "propose", json!({"op": "sleep", "seconds": 250})),
            ("t2", "propose", set(6)),
        ]),
        end("Plan."),
        // 2. a wait an approval of 5 min outlives, and one of 60 s does not
        tool_use(&[
            (
                "t1",
                "propose",
                json!({"op": "wait", "path": "downstream/mock/p0", "timeout_s": 40}),
            ),
            ("t2", "propose", set(7)),
        ]),
        end("Plan."),
    ];
    let env = Env::start(params(&["downstream/mock"]), script).await;
    let human = env.human(Perm::Config);
    let k1 = "wy/test/downstream/mock/p1/~set";

    let (id, _) = env.ask("sleep, then set").await.unwrap();
    let doc = env.wait_state(&id, "awaiting_approval").await;
    assert_eq!(plan_len(&doc), 2, "the second set is no step: {doc:?}");
    // the model is told why, in the answer to its proposal
    let refusal = env.llm.seen()[1].to_string();
    assert!(
        refusal.contains("add up to 250 s") && refusal.contains("follow-up"),
        "{refusal}"
    );

    let (id, _) = env.ask("wait, then set").await.unwrap();
    let doc = env.wait_state(&id, "awaiting_approval").await;
    assert_eq!(plan_len(&doc), 2);
    // the tokens of this file live 60 s: 40 s of waits and the margin do not fit
    let e = env
        .task_action(
            &human,
            &id,
            "approve",
            approvals(&[("2", human_token("user:op", k1))]),
        )
        .await
        .unwrap_err();
    assert!(e.is(Status::InvalidParameter), "{e}");
    assert!(
        e.message.contains("step 2 may be sent 40 s after") && e.message.contains("follow-up"),
        "{e}"
    );
    assert_eq!(
        field(&env.task(&id), "state").as_deref(),
        Some("awaiting_approval")
    );
    // one that lives as long as the gateway's does
    let long = SigningTokens::new(test_key(), SITE)
        .subject("user:op")
        .ttl(Duration::from_secs(300))
        .token(k1)
        .unwrap();
    env.task_action(&human, &id, "approve", approvals(&[("2", long)]))
        .await
        .unwrap();
    env.wait_state(&id, "done").await;

    // `steps` alone is the form of a gateway user: no gateway signed these
    let args = Value::Map(BTreeMap::from([(
        "steps".to_owned(),
        Value::Array(vec![Value::UInt(1)]),
    )]));
    let e = env
        .task_action(&human, &id, "approve", args)
        .await
        .unwrap_err();
    assert!(e.is(Status::InvalidParameter), "{e}");
    assert!(e.message.contains("gateway"), "{e}");
    env.stop().await;
}

/// Review of ADR 0049 §3: `approve` is `write` on the task, so a caller who is neither the
/// asker nor a `config` caller may call it. Such a caller decides only for the steps they
/// sign: a step without their token is skipped, never run with the agent's key. The asker
/// keeps the steps that need no human.
#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn a_stranger_approves_only_what_they_sign() {
    // Under mode `config` the two writes need no human and run with the agent's key; the
    // flow deploy (config) makes the task wait.
    let def = json!({"id": "shed", "nodes": {"a": {"type": "subscribe", "key": "downstream/mock/p0"}}, "edges": []});
    let script = || {
        vec![
            tool_use(&[
                (
                    "t1",
                    "propose",
                    json!({"op": "set", "path": "downstream/mock/p0", "value": 5}),
                ),
                (
                    "t2",
                    "propose",
                    json!({"op": "set", "path": "downstream/mock/p1", "value": 6}),
                ),
                (
                    "t3",
                    "propose",
                    json!({"op": "invoke", "path": "dataflows", "action": "deploy", "args": {"def": def}}),
                ),
                (
                    "t4",
                    "propose",
                    json!({"op": "expect", "path": "downstream/mock/p1", "equals": 6, "timeout_s": 3}),
                ),
            ]),
            end("Plan."),
        ]
    };
    let p = AgentParams {
        allowed_prefixes: vec!["downstream/mock".into(), "dataflows".into()],
        require_approval: wyrm_link_agent::tools::ApprovalMode::Config,
        ..AgentParams::default()
    };
    let mut all = script();
    all.extend(script());
    all.extend(script());
    let env = Env::start(p, all).await;
    let dir = temp_dir("who-flows");
    let host = wyrm_flow::FlowHost::open(&dir, b"flow-test-hmac-key", SITE).unwrap();
    let mut lc = LinkConfig::new(SITE, "dataflows");
    lc.root = Some(format!("wy/{SITE}/dataflows"));
    lc.admin_keys = vec![test_key().verifying_key()];
    let engine = wyrm_link_sdk::spawn::<wyrm_flow::Engine>(
        env.session.clone(),
        lc,
        wyrm_flow::EngineStart {
            host,
            admin_keys: vec![test_key().verifying_key()],
            proof_keys: Vec::new(),
        },
    )
    .await
    .unwrap();
    let p1 = || {
        let v = env.mock.as_ref().unwrap().ctx().last("p1").unwrap().v;
        v.as_f64().unwrap()
    };
    let (k0, k1) = (
        format!("{P0}/~set"),
        "wy/test/downstream/mock/p1/~set".to_owned(),
    );
    let k2 = "wy/test/dataflows/~act/deploy".to_owned();
    // a writer who is not the asker, with `write` and no more on the agent link
    let other = |sub: &'static str| {
        WyrmClient::new(env.session.clone())
            .with_timeout(Duration::from_secs(5))
            .with_tokens(Arc::new(
                SigningTokens::new(test_key(), SITE)
                    .subject(sub)
                    .max(Perm::Write),
            ))
    };
    let msg = |doc: &Value, i: usize| result_of(&plan_step(doc, i)).unwrap();

    // 1. a stranger signs step 2 alone: step 1 does not run with the agent's key
    let (id, _) = env.ask("set and deploy").await.unwrap();
    let doc = env.wait_state(&id, "awaiting_approval").await;
    assert_eq!(get(&plan_step(&doc, 0), "approval"), &Value::Bool(false));
    assert_eq!(get(&plan_step(&doc, 2), "approval"), &Value::Bool(true));
    let p0_before = env.p0();
    env.task_action(
        &other("user:x"),
        &id,
        "approve",
        approvals(&[("2", human_token("user:x", &k1))]),
    )
    .await
    .unwrap();
    let doc = env.wait_state(&id, "done").await;
    assert_eq!(msg(&doc, 0), ("skipped".into(), "skipped by user:x".into()));
    assert_eq!(env.p0(), p0_before, "nothing ran under the agent's key");
    let (st, text) = msg(&doc, 1);
    assert_eq!(st, "ok");
    assert!(
        text.ends_with("(approval)"),
        "sent with the stranger's token: {text}"
    );
    assert_eq!(p1(), 6.0);
    assert_eq!(msg(&doc, 2).0, "skipped");
    assert_eq!(
        msg(&doc, 3).0,
        "ok",
        "a proof reads; it needs nobody's token"
    );

    // 2. an engineer of the devices, not the asker and without `config` on the agent link,
    //    signs both writes: they run with the engineer's tokens
    env.mock
        .as_ref()
        .unwrap()
        .ctx()
        .update("p1", Value::Float(0.0), wyrm_core::Quality::Good, 1)
        .await
        .ok();
    let (id, _) = env.ask("set and deploy").await.unwrap();
    env.wait_state(&id, "awaiting_approval").await;
    env.task_action(
        &other("user:eng"),
        &id,
        "approve",
        approvals(&[
            ("1", human_token("user:eng", &k0)),
            ("2", human_token("user:eng", &k1)),
        ]),
    )
    .await
    .unwrap();
    let doc = env.wait_state(&id, "done").await;
    for i in [0, 1] {
        let (st, text) = msg(&doc, i);
        assert_eq!(st, "ok");
        assert!(text.ends_with("(approval)"), "{text}");
    }
    assert_eq!(env.p0(), 5.0);
    assert_eq!(
        msg(&doc, 2),
        ("skipped".into(), "skipped by user:eng".into())
    );

    // 3. the asker signs the config step alone: the writes that need no human run with the
    //    agent's key, as before
    let (id, _) = env.ask("set and deploy").await.unwrap();
    env.wait_state(&id, "awaiting_approval").await;
    env.task_action(
        &env.human(Perm::Write),
        &id,
        "approve",
        approvals(&[("3", human_token("user:op", &k2))]),
    )
    .await
    .unwrap();
    let mut doc = Value::Null;
    for _ in 0..400 {
        doc = env.doc(&id).await;
        if matches!(field(&doc, "state").as_deref(), Some("done" | "failed")) {
            break;
        }
        tokio::time::sleep(Duration::from_millis(25)).await;
    }
    for i in [0, 1] {
        let (st, text) = msg(&doc, i);
        assert_eq!(st, "ok");
        assert!(text.ends_with("(service token)"), "{text}");
    }
    let (_, text) = msg(&doc, 2);
    assert!(
        text.contains("(approval)") || field(&doc, "state").as_deref() == Some("failed"),
        "{text}"
    );
    engine.stop().await;
    env.stop().await;
}

/// `ask {task, parent}` → the new task's id.
async fn follow_up(client: &WyrmClient, text: &str, parent: &str) -> String {
    let args = Value::Map(BTreeMap::from([
        ("task".to_owned(), Value::from(text)),
        ("parent".to_owned(), Value::from(parent)),
    ]));
    let mut s = client
        .invoke("wy/test/downstream/agent", "ask", args)
        .await
        .unwrap();
    let mut id = None;
    while let Some(i) = s.next().await {
        if let Some(v) = i.unwrap() {
            id = field(&v, "task").or(id);
        }
    }
    id.expect("the stream names the task")
}

fn items<'a>(v: &'a Value, k: &str) -> &'a [Value] {
    match get(v, k) {
        Value::Array(a) => a,
        _ => &[],
    }
}

/// ADR 0049, amendment of 2026-11-14 (gaps 1 and 3): the model's warning on a step, its
/// fixes and the rows for "the same for more" are data in the record; a run that stops at
/// a step gets one more read-only turn whose ways out replace them. The public `~val`
/// carries their count and no word of them.
#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn a_stopped_run_gets_ways_out_and_a_step_gets_fixes() {
    let script = vec![
        tool_use(&[
            (
                "t1",
                "propose",
                json!({"op": "set", "path": "downstream/mock/p0", "value": 3,
                       "warn": "p0 is read by another loop"}),
            ),
            (
                "t2",
                "propose",
                json!({"op": "expect", "path": "downstream/mock/p0", "min": 100, "timeout_s": 0.3}),
            ),
            (
                "s1",
                "suggest",
                json!({"label": "Write p1 instead", "detail": "nothing reads p1", "changes": 1, "step": 1}),
            ),
            (
                "s2",
                "suggest",
                json!({"label": "Same for more points", "changes": 1, "rows": [
                    {"path": "downstream/mock/p1", "label": "point 1", "detail": "same kind"},
                ]}),
            ),
            // a fix for a step that is not there
            ("s3", "suggest", json!({"label": "x", "step": 9})),
        ]),
        end("Plan: set p0 and prove it."),
        // the turn after the run stopped
        tool_use(&[
            ("r1", "value_get", json!({"paths": ["downstream/mock/p0"]})),
            (
                "r2",
                "suggest",
                json!({"label": "Expect 3 instead", "detail": "the point holds 3", "changes": 0}),
            ),
            (
                "r3",
                "suggest",
                json!({"label": "Set p0 to 100", "detail": "then the proof passes", "changes": 1}),
            ),
            // nothing is planned and nobody is asked in this turn
            (
                "r4",
                "propose",
                json!({"op": "set", "path": "downstream/mock/p0", "value": 100}),
            ),
            ("r5", "ask_user", json!({"question": "again?"})),
        ]),
        end("p0 holds 3, below what the plan expects."),
    ];
    let env = Env::start(params(&["downstream/mock"]), script).await;
    let human = env.human(Perm::Write);
    let (id, _) = env.ask("set p0 and prove it").await.unwrap();
    let doc = env.wait_state(&id, "awaiting_approval").await;

    // gap 3: the warning is on the step, its fix names the step
    let warn = field(&plan_step(&doc, 0), "warn").unwrap();
    assert!(warn.contains("read by another loop"), "{warn}");
    let offered = items(&doc, "suggestions");
    assert_eq!(offered.len(), 2, "{offered:?}");
    assert_eq!(field(&offered[0], "id").as_deref(), Some("s1"));
    assert_eq!(get(&offered[0], "step"), &Value::UInt(1));
    assert_eq!(get(&offered[0], "changes"), &Value::UInt(1));
    assert_eq!(
        field(&offered[0], "label").as_deref(),
        Some("Write p1 instead")
    );
    // the rows of "the same for more" are full node keys
    let rows = items(&offered[1], "rows");
    assert_eq!(
        field(&rows[0], "key").as_deref(),
        Some("wy/test/downstream/mock/p1")
    );
    assert_eq!(get(&offered[1], "step"), &Value::Null);
    let seen = env.llm.seen();
    let results = &seen[1]["messages"][2]["content"];
    assert_eq!(results[2]["is_error"], false, "{results}");
    assert_eq!(results[4]["is_error"], true, "{results}");
    // the public value: a count, no word of the model
    let pv = env.task(&id);
    assert_eq!(get(&pv, "suggestions"), &Value::UInt(2));
    let shown = format!("{pv:?}");
    assert!(
        !shown.contains("Write p1") && !shown.contains("another loop"),
        "{shown}"
    );
    // what is said about a step is no part of the plan's hash
    assert!(field(&doc, "plan_hash").is_some());

    // gap 1: the run stops at step 2; the model reads and offers ways out
    let k0 = format!("{P0}/~set");
    env.task_action(
        &human,
        &id,
        "approve",
        approvals(&[("1", human_token("user:op", &k0))]),
    )
    .await
    .unwrap();
    env.wait_state(&id, "failed").await;
    let mut doc = Value::Null;
    for _ in 0..400 {
        doc = env.doc(&id).await;
        if field(&doc, "review").is_some() {
            break;
        }
        tokio::time::sleep(Duration::from_millis(25)).await;
    }
    assert_eq!(
        field(&doc, "review").as_deref(),
        Some("p0 holds 3, below what the plan expects.")
    );
    assert_eq!(field(&doc, "state").as_deref(), Some("failed"));
    assert!(
        field(&doc, "error").unwrap().contains("step 2"),
        "the run's error stays"
    );
    let ways = items(&doc, "suggestions");
    let labels: Vec<_> = ways.iter().map(|w| field(w, "label").unwrap()).collect();
    assert_eq!(
        labels,
        ["Expect 3 instead", "Set p0 to 100"],
        "what planning offered is gone"
    );
    assert_eq!(get(&ways[0], "changes"), &Value::UInt(0));
    assert_eq!(get(&ways[1], "changes"), &Value::UInt(1));
    assert_eq!(get(&doc, "reviewing"), &Value::Null);
    let pv = env.task(&id);
    assert_eq!(get(&pv, "suggestions"), &Value::UInt(2));
    assert_eq!(get(&pv, "reviewing"), &Value::Null);
    assert!(!format!("{pv:?}").contains("Expect 3"), "{pv:?}");
    // the turn had the read tools and `suggest` only, and was told what stopped
    let seen = env.llm.seen();
    let names: Vec<&str> = seen[2]["tools"]
        .as_array()
        .unwrap()
        .iter()
        .filter_map(|t| t["name"].as_str())
        .collect();
    assert!(names.contains(&"suggest") && names.contains(&"value_get"));
    assert!(
        !names.contains(&"propose") && !names.contains(&"ask_user"),
        "{names:?}"
    );
    let first = seen[2]["messages"][0]["content"].as_str().unwrap();
    assert!(
        first.contains("stopped") && first.contains("not as expected"),
        "{first}"
    );
    let results = &seen[3]["messages"][2]["content"];
    assert_eq!(results[3]["is_error"], true, "propose: {results}");
    assert_eq!(results[4]["is_error"], true, "ask_user: {results}");
    assert_eq!(env.p0(), 3.0, "the turn changed nothing");
    // a way out is a follow-up ask: the model gets what it offered
    env.llm
        .script
        .lock()
        .unwrap()
        .push_back(end("Nothing to change."));
    let next = follow_up(&human, "Expect 3 instead. the point holds 3", &id).await;
    env.wait_state(&next, "done").await;
    let seen = env.llm.seen();
    let first = seen[4]["messages"][0]["content"].as_str().unwrap();
    assert!(first.contains("Set p0 to 100"), "{first}");
    assert_eq!(
        field(&env.doc(&id).await, "replaced_by"),
        None,
        "a follow-up of a task that ended replaces nothing"
    );
    env.stop().await;

    // no turn with `review_turns: 0`, and none after a cancel or a reject
    let p = AgentParams {
        review_turns: 0,
        ..params(&["downstream/mock"])
    };
    let script = vec![
        tool_use(&[(
            "t1",
            "propose",
            json!({"op": "expect", "path": "downstream/mock/p0", "min": 100, "timeout_s": 0.2}),
        )]),
        end("Plan."),
        end("never asked"),
    ];
    let env = Env::start(p, script).await;
    let (id, _) = env.ask("prove p0").await.unwrap();
    let doc = env.wait_state(&id, "failed").await;
    tokio::time::sleep(Duration::from_millis(200)).await;
    assert_eq!(env.llm.seen().len(), 2);
    assert_eq!(field(&doc, "review"), None);
    env.stop().await;
}

/// A suggestion is bounded and stays inside the rights of the task's asker: a row names a
/// node the agent may read and the asker may read.
#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn a_suggestion_is_bounded_and_inside_the_askers_rights() {
    let row = |path: &str| json!({"label": "more", "rows": [{"path": path, "label": "a point"}]});
    let long = "x".repeat(500);
    let mut calls: Vec<(String, Json)> = vec![
        // the asker may not read p1; outside what the agent reads; a row twice; no label
        ("b1".into(), row("downstream/mock/p1")),
        ("b2".into(), row("sys/links")),
        (
            "b3".into(),
            json!({"label": "twice", "rows": [
                {"path": "downstream/mock/p0", "label": "a"},
                {"path": "wy/test/downstream/mock/p0", "label": "b"},
            ]}),
        ),
        ("b4".into(), json!({"detail": "no label"})),
        ("b5".into(), json!({"label": "many", "changes": 51})),
        ("ok1".into(), row("downstream/mock/p0")),
        ("ok2".into(), json!({"label": long, "detail": long})),
    ];
    for i in 3..=9 {
        calls.push((format!("ok{i}"), json!({"label": format!("way {i}")})));
    }
    let calls: Vec<(&str, &str, Json)> = calls
        .iter()
        .map(|(id, input)| (id.as_str(), "suggest", input.clone()))
        .collect();
    let env = Env::start(
        params(&["downstream/mock"]),
        vec![tool_use(&calls), end("Nothing to change.")],
    )
    .await;
    let g = |k: &str, p: Perm| wyrm_core::ptok::Grant { k: k.into(), p };
    let narrow = WyrmClient::new(env.session.clone())
        .with_timeout(Duration::from_secs(5))
        .with_tokens(Arc::new(
            SigningTokens::new(test_key(), SITE)
                .subject("user:x")
                .grants(vec![
                    g("wy/test/downstream/agent/**", Perm::Write),
                    g("wy/test/downstream/mock/p0/**", Perm::Read),
                ]),
        ));
    let (id, _) = env.ask_with(&narrow, "what else?").await.unwrap();
    env.wait_state(&id, "done").await;
    let key = format!("wy/test/downstream/agent/tasks/{id}/~state");
    let doc = env
        .doc_with(&id, Some(human_token("user:op", &key)))
        .await
        .unwrap();
    let seen = env.llm.seen();
    let results = seen[1]["messages"][2]["content"].as_array().unwrap();
    let refused: Vec<bool> = results
        .iter()
        .map(|r| r["is_error"].as_bool().unwrap())
        .collect();
    // five bad ones, eight taken, the ninth is one too many
    let mut want = vec![true; 5];
    want.extend([false; 8]);
    want.push(true);
    assert_eq!(refused, want, "{results:?}");
    assert!(
        results[0]["content"]
            .as_str()
            .unwrap()
            .contains("may not read"),
        "{}",
        results[0]
    );
    let offered = items(&doc, "suggestions");
    assert_eq!(offered.len(), 8);
    assert_eq!(
        field(&items(&offered[0], "rows")[0], "key").as_deref(),
        Some(P0)
    );
    let (label, detail) = (
        field(&offered[1], "label").unwrap(),
        field(&offered[1], "detail").unwrap(),
    );
    assert!(label.len() < 100 && detail.len() < 320, "{label} {detail}");
    assert_eq!(get(&env.task(&id), "suggestions"), &Value::UInt(8));
    env.stop().await;
}

/// ADR 0049, amendment of 2026-11-14 (gap 2): a follow-up of a task that waits for a
/// person takes its place. The old task ends as `failed` with `replaced_by`, in the record
/// and in the public value, and its plan cannot be approved any more; a follow-up of a
/// task that ended replaces nothing. The mark survives a restart.
#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn a_follow_up_replaces_a_task_that_waits_for_a_person() {
    let mut script = set_p0_script(42.0);
    script.extend(set_p0_script(43.0));
    // a follow-up of the done task asks back; the follow-up of that one ends at once
    script.push(tool_use(&[(
        "q",
        "ask_user",
        json!({"question": "Which one?", "options": [{"id": "a", "label": "p0"}]}),
    )]));
    script.push(end("Nothing to do."));
    let dir = temp_dir("replaced");
    let mut env = Env::start_in(params(&["downstream/mock"]), script, Some(dir.clone())).await;
    let human = env.human(Perm::Write);
    let before = env.p0();
    let (old, _) = env.ask("set p0 to 42").await.unwrap();
    env.wait_state(&old, "awaiting_approval").await;

    let new = follow_up(&human, "make it 43", &old).await;
    env.wait_state(&new, "awaiting_approval").await;
    let doc = env.wait_state(&old, "failed").await;
    assert_eq!(field(&doc, "replaced_by"), Some(new.clone()));
    assert_eq!(field(&doc, "error"), Some(format!("replaced by {new}")));
    assert_eq!(plan_len(&doc), 1, "the old plan stays readable");
    let pv = env.task(&old);
    assert_eq!(field(&pv, "replaced_by"), Some(new.clone()));
    assert_eq!(field(&env.doc(&new).await, "parent"), Some(old.clone()));
    assert_eq!(field(&env.task(&new), "replaced_by"), None);

    // the old plan is not approved, with a good token and by its asker
    let k0 = format!("{P0}/~set");
    let approve = || approvals(&[("1", human_token("user:op", &k0))]);
    let e = env
        .task_action(&human, &old, "approve", approve())
        .await
        .unwrap_err();
    assert!(e.is(Status::InvalidParameter), "{e}");
    assert!(e.to_string().contains(&format!("replaced by {new}")), "{e}");
    assert_eq!(env.p0(), before);
    for action in ["reject", "cancel"] {
        let e = env
            .task_action(&human, &old, action, Value::Map(BTreeMap::new()))
            .await
            .unwrap_err();
        assert!(e.is(Status::InvalidParameter), "{action}: {e}");
    }

    // after a restart too
    env.restart_agent(vec![
        tool_use(&[(
            "q",
            "ask_user",
            json!({"question": "Which one?", "options": [{"id": "a", "label": "p0"}]}),
        )]),
        end("Nothing to do."),
    ])
    .await;
    let doc = env.doc(&old).await;
    assert_eq!(field(&doc, "state").as_deref(), Some("failed"));
    assert_eq!(field(&doc, "replaced_by"), Some(new.clone()));
    assert_eq!(field(&env.task(&old), "replaced_by"), Some(new.clone()));
    let e = env
        .task_action(&human, &old, "approve", approve())
        .await
        .unwrap_err();
    assert!(e.to_string().contains("replaced by"), "{e}");

    // the new plan runs
    env.task_action(&human, &new, "approve", approve())
        .await
        .unwrap();
    env.wait_state(&new, "done").await;
    assert_eq!(env.p0(), 43.0);

    // a follow-up of a task that ended replaces nothing; one of a task that waits for an
    // answer ends the wait
    let asks = follow_up(&human, "and one more", &new).await;
    env.wait_state(&asks, "awaiting_answer").await;
    let doc = env.doc(&new).await;
    assert_eq!(field(&doc, "state").as_deref(), Some("done"));
    assert_eq!(field(&doc, "replaced_by"), None);
    let last = follow_up(&human, "never mind", &asks).await;
    env.wait_state(&last, "done").await;
    let doc = env.wait_state(&asks, "failed").await;
    assert_eq!(field(&doc, "replaced_by"), Some(last.clone()));
    let answers = Value::Map(BTreeMap::from([(
        "text".to_owned(),
        Value::from("the first one"),
    )]));
    let e = human
        .invoke_one(
            &format!("wy/test/downstream/agent/tasks/{asks}"),
            "answer",
            answers,
        )
        .await
        .unwrap_err();
    assert!(e.is(Status::InvalidParameter), "{e}");
    env.stop().await;
    let _ = std::fs::remove_dir_all(dir);
}
