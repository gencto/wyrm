//! Test kit of the messenger links (feature `testkit`): `SimHost<A>` runs a link's app on a
//! `BufferHost` with other links' values in memory and real TCP to loopback, where [`Api`] (a
//! fake Telegram Bot API and Slack Web API) answers in a thread. Each event's commands are
//! applied as the portable runtime does. A new platform adds its routes to [`Api`].

use std::collections::{BTreeMap, HashMap, VecDeque};
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use serde_json::{json, Value as Json};
use wyrm_core::{Perm, Quality, Sample, Status, Value};
use wyrm_link_api::buffer::{store_cost, BufferHost, Command, Counts, Limits, Services};
use wyrm_link_api::{App, AppError, ConnId, ReqId, SubId, TimerId, Who};

pub const SITE: &str = "wy/s";
pub const TG_TOKEN: &str = "123456:AAHdqTcvCH1vGWJxfSeofSAs0K5PALDsaw";
pub const SLACK_TOKEN: &str = "xoxb-1-2-abc";

#[derive(Default)]
struct Shared {
    now_us: u64,
    store: HashMap<String, Vec<u8>>,
    random: u8,
}

struct Sim {
    shared: Arc<Mutex<Shared>>,
    conns: HashMap<u32, TcpStream>,
    next: u32,
}

impl Services for Sim {
    fn now_us(&self) -> u64 {
        self.shared.lock().unwrap().now_us
    }
    fn store_get(&self, key: &str) -> Option<Vec<u8>> {
        self.shared.lock().unwrap().store.get(key).cloned()
    }
    fn store_used(&self) -> u64 {
        let s = self.shared.lock().unwrap();
        s.store
            .iter()
            .map(|(k, v)| store_cost(k.len(), v.len()))
            .sum()
    }
    fn store_keys(&self) -> usize {
        self.shared.lock().unwrap().store.len()
    }
    fn may(&self, key: &str, _perm: Perm) -> bool {
        // the link's grants: the mock link only
        key.starts_with("wy/s/downstream/mock") || key.starts_with("wy/s/downstream/other")
    }
    fn tcp_connect(&mut self, addr: &str, port: u16, t: u32) -> Result<ConnId, AppError> {
        if addr != "127.0.0.1" {
            return Err(AppError::new(
                Status::PermissionDenied,
                format!("{addr}: not in net"),
            ));
        }
        let s = TcpStream::connect_timeout(
            &std::net::SocketAddr::from(([127, 0, 0, 1], port)),
            Duration::from_millis(u64::from(t)),
        )
        .map_err(|e| AppError::new(Status::Disconnected, e.to_string()))?;
        s.set_nodelay(true).unwrap();
        self.next += 1;
        self.conns.insert(self.next, s);
        Ok(ConnId(self.next))
    }
    fn tcp_send(&mut self, c: ConnId, d: &[u8]) -> Result<(), AppError> {
        let s = self
            .conns
            .get_mut(&c.0)
            .ok_or(AppError::new(Status::NotFound, "conn"))?;
        s.write_all(d)
            .map_err(|e| AppError::new(Status::Disconnected, e.to_string()))
    }
    fn tcp_recv(&mut self, c: ConnId, max: u32, t: u32) -> Result<Vec<u8>, AppError> {
        let s = self
            .conns
            .get_mut(&c.0)
            .ok_or(AppError::new(Status::NotFound, "conn"))?;
        s.set_read_timeout(Some(Duration::from_millis(u64::from(t.max(1)))))
            .unwrap();
        let mut b = vec![0u8; max as usize];
        match s.read(&mut b) {
            Ok(n) => {
                b.truncate(n);
                Ok(b)
            }
            Err(e)
                if matches!(
                    e.kind(),
                    std::io::ErrorKind::WouldBlock | std::io::ErrorKind::TimedOut
                ) =>
            {
                Err(AppError::new(Status::Timeout, "recv: timeout"))
            }
            Err(e) => Err(AppError::new(Status::Disconnected, e.to_string())),
        }
    }
    fn tcp_close(&mut self, c: ConnId) {
        self.conns.remove(&c.0);
    }
    fn random_bytes(&mut self, n: u32) -> Result<Vec<u8>, AppError> {
        let mut s = self.shared.lock().unwrap();
        s.random = s.random.wrapping_add(37);
        let seed = s.random;
        Ok((0..n)
            .map(|i| seed.wrapping_mul(7).wrapping_add(i as u8 * 13))
            .collect())
    }
}

enum Ev {
    Value(u64, String, Sample),
    Reply(u64, Result<Value, AppError>),
}

pub struct SimHost<A: App> {
    buf: BufferHost,
    shared: Arc<Mutex<Shared>>,
    pub app: Option<A>,
    pub values: BTreeMap<String, Value>,
    pub nodes: BTreeMap<String, Option<Value>>,
    /// Actions declared per node path.
    pub actions: BTreeMap<String, Vec<(String, wyrm_core::ActionMeta)>>,
    timers: BTreeMap<u64, u64>,
    pub subs: BTreeMap<u64, String>,
    queue: VecDeque<Ev>,
    /// `set` and `invoke` the link asked for: `(key, action, value)`.
    pub requests: Vec<(String, Option<String>, Value)>,
    pub logs: Vec<String>,
    pub params: Value,
}

pub fn engineer() -> Who {
    Who {
        subject: Some("user:eng".into()),
        grants: vec![("wy/s/downstream/**".into(), Perm::Config)],
        authority: Some(vec![("wy/s/**".into(), Perm::Config)]),
    }
}

/// A config user whose own rights end at reading the mock link.
pub fn narrow() -> Who {
    Who {
        subject: Some("user:nina".into()),
        grants: vec![("wy/s/downstream/**".into(), Perm::Config)],
        authority: Some(vec![("wy/s/downstream/mock/**".into(), Perm::Read)]),
    }
}

pub fn map(pairs: &[(&str, Value)]) -> Value {
    Value::Map(
        pairs
            .iter()
            .map(|(k, v)| ((*k).to_owned(), v.clone()))
            .collect(),
    )
}

pub fn s(v: &str) -> Value {
    Value::Str(v.into())
}

impl<A: App> SimHost<A> {
    pub fn new(port: u16) -> Self {
        let shared = Arc::new(Mutex::new(Shared {
            now_us: 1_800_000_000_000_000,
            ..Shared::default()
        }));
        let limits = Limits {
            store_bytes: 2 << 20,
            ..Limits::default()
        };
        let params = map(&[
            ("site", s("s")),
            ("own", s(&format!("wy/s/downstream/{}", A::NAME))),
            ("net", s(&format!("127.0.0.1:{port}"))),
        ]);
        let mut values = BTreeMap::new();
        values.insert("wy/s/downstream/mock/d1/temp".into(), Value::Float(21.456));
        values.insert("wy/s/downstream/mock/d1/name".into(), s("<Boiler & Co>"));
        values.insert("wy/s/downstream/other/x".into(), Value::Int(5));
        Self {
            buf: BufferHost::new(
                Box::new(Sim {
                    shared: shared.clone(),
                    conns: HashMap::new(),
                    next: 0,
                }),
                limits,
                Counts::default(),
                1,
                SITE.into(),
            ),
            shared,
            app: None,
            values,
            nodes: BTreeMap::new(),
            actions: BTreeMap::new(),
            timers: BTreeMap::new(),
            subs: BTreeMap::new(),
            queue: VecDeque::new(),
            requests: Vec::new(),
            logs: Vec::new(),
            params,
        }
    }

    pub fn now(&self) -> u64 {
        self.shared.lock().unwrap().now_us
    }

    fn counts(&self) -> Counts {
        Counts {
            timers: self.timers.len(),
            subs: self.subs.len(),
            lists: 0,
            inflight: 0,
        }
    }

    fn apply(&mut self) {
        let cmds = self.buf.finish().expect("the host would fail this event");
        let now = self.now();
        for c in cmds {
            match c {
                Command::DeclareNode(p, m) => {
                    for (name, a) in m.actions.iter().flatten() {
                        lint_names(name, a);
                    }
                    self.nodes.entry(p).or_insert(None);
                }
                Command::DeclareAction(p, name, meta) => {
                    lint_names(&name, &meta);
                    let list = self.actions.entry(p).or_default();
                    list.retain(|(n, _)| *n != name);
                    list.push((name, meta));
                }
                Command::RemoveNode(p) => {
                    let below = format!("{p}/");
                    self.nodes.retain(|k, _| *k != p && !k.starts_with(&below));
                    self.actions
                        .retain(|k, _| *k != p && !k.starts_with(&below));
                }
                Command::Update(p, smp) => {
                    assert!(
                        self.nodes.contains_key(&p),
                        "update of an undeclared node {p}"
                    );
                    self.nodes.insert(p, Some(smp.v));
                }
                Command::SetTimer(TimerId(id), ms) => {
                    self.timers.insert(id, now + ms * 1000);
                }
                Command::CancelTimer(TimerId(id)) => {
                    self.timers.remove(&id);
                }
                Command::StorePut(k, v) => {
                    self.shared.lock().unwrap().store.insert(k, v);
                }
                Command::StoreDelete(k) => {
                    self.shared.lock().unwrap().store.remove(&k);
                }
                Command::Subscribe(SubId(id), key) => {
                    if let Some(v) = self.values.get(&key) {
                        self.queue
                            .push_back(Ev::Value(id, key.clone(), sample(v.clone(), now)));
                    }
                    self.subs.insert(id, key);
                }
                Command::Unsubscribe(SubId(id)) => {
                    self.subs.remove(&id);
                }
                Command::Set(ReqId(id), key, v) => {
                    self.requests.push((key.clone(), None, v.clone()));
                    self.values.insert(key, v);
                    self.queue.push_back(Ev::Reply(id, Ok(Value::Null)));
                }
                Command::Invoke(ReqId(id), key, action, args) => {
                    self.requests.push((key, Some(action), args));
                    self.queue.push_back(Ev::Reply(id, Ok(Value::Null)));
                }
                Command::List(..) => panic!("a messenger link never lists"),
                Command::Log(_, m) => self.logs.push(m),
            }
        }
        self.buf.set_counts(self.counts());
    }

    pub fn start(&mut self) {
        let app = A::start(&mut self.buf, self.params.clone()).expect("start");
        self.app = Some(app);
        self.apply();
        self.settle();
    }

    pub fn restart(&mut self) {
        if let Some(mut a) = self.app.take() {
            a.stop(&mut self.buf);
            self.apply();
        }
        self.timers.clear();
        self.subs.clear();
        self.queue.clear();
        self.nodes.clear();
        self.actions.clear();
        self.buf.set_counts(self.counts());
        self.start();
    }

    pub fn settle(&mut self) {
        loop {
            if let Some(ev) = self.queue.pop_front() {
                let app = self.app.as_mut().expect("started");
                match ev {
                    Ev::Value(id, key, smp) => {
                        if self.subs.contains_key(&id) {
                            app.on_value(&mut self.buf, SubId(id), &key, smp);
                        }
                    }
                    Ev::Reply(id, r) => app.on_reply(&mut self.buf, ReqId(id), r),
                }
                self.apply();
                continue;
            }
            let now = self.now();
            let due = self
                .timers
                .iter()
                .find(|(_, t)| **t <= now)
                .map(|(id, _)| *id);
            match due {
                Some(id) => {
                    self.timers.remove(&id);
                    self.app
                        .as_mut()
                        .expect("started")
                        .on_timer(&mut self.buf, TimerId(id));
                    self.apply();
                }
                None => return,
            }
        }
    }

    pub fn advance_ms(&mut self, ms: u64) {
        self.shared.lock().unwrap().now_us += ms * 1000;
        self.settle();
    }

    pub fn until(&mut self, what: &str, mut cond: impl FnMut(&Self) -> bool) {
        for _ in 0..400 {
            if cond(self) {
                return;
            }
            std::thread::sleep(Duration::from_millis(2));
            self.advance_ms(250);
        }
        panic!("not in time: {what}; nodes {:?}", self.nodes);
    }

    pub fn invoke(&mut self, path: &str, action: &str, args: Value) -> Result<Value, AppError> {
        self.invoke_as(path, action, args, &engineer())
    }

    pub fn invoke_as(
        &mut self,
        path: &str,
        action: &str,
        args: Value,
        who: &Who,
    ) -> Result<Value, AppError> {
        let r =
            self.app
                .as_mut()
                .expect("started")
                .on_invoke(&mut self.buf, path, action, args, who);
        self.apply();
        self.settle();
        r
    }

    pub fn set(&mut self, path: &str, v: Value) -> Result<(), AppError> {
        let r = self
            .app
            .as_mut()
            .expect("started")
            .on_set(&mut self.buf, path, v, &engineer());
        self.apply();
        self.settle();
        r
    }

    pub fn put_value(&mut self, key: &str, v: Value) {
        self.values.insert(key.to_owned(), v.clone());
        let now = self.now();
        for (id, k) in &self.subs {
            if k == key {
                self.queue
                    .push_back(Ev::Value(*id, key.to_owned(), sample(v.clone(), now)));
            }
        }
        self.settle();
    }

    pub fn leaf(&self, path: &str) -> Value {
        self.nodes
            .get(path)
            .cloned()
            .flatten()
            .unwrap_or(Value::Null)
    }

    pub fn text(&self, path: &str) -> String {
        match self.leaf(path) {
            Value::Str(s) => s,
            _ => String::new(),
        }
    }

    pub fn num(&self, path: &str) -> u64 {
        match self.leaf(path) {
            Value::UInt(n) => n,
            _ => 0,
        }
    }

    pub fn store_has(&self, k: &str) -> bool {
        self.shared.lock().unwrap().store.contains_key(k)
    }

    pub fn store_raw(&self, k: &str) -> Option<Vec<u8>> {
        self.shared.lock().unwrap().store.get(k).cloned()
    }
}

fn sample(v: Value, t: u64) -> Sample {
    Sample {
        v,
        q: Quality::Good,
        t,
    }
}

impl<A: App> Drop for SimHost<A> {
    fn drop(&mut self) {
        if let Some(mut a) = self.app.take() {
            a.stop(&mut self.buf);
            let _ = self.buf.finish();
        }
    }
}

// ---------- a fake Telegram Bot API and Slack Web API ----------

/// One call the API saw.
#[derive(Debug, Clone)]
pub struct Call {
    pub path: String,
    pub method: String,
    pub headers: Vec<(String, String)>,
    pub body: Json,
}

#[derive(Default)]
pub struct ApiState {
    pub calls: Vec<Call>,
    /// Updates `getUpdates` hands out next (update ids are given here).
    pub updates: Vec<Json>,
    next_update: i64,
    /// Replies to the next send calls, instead of `ok`.
    pub script: VecDeque<(u16, String)>,
}

pub struct Api {
    pub port: u16,
    pub state: Arc<Mutex<ApiState>>,
}

impl Api {
    pub fn start() -> Self {
        let l = TcpListener::bind("127.0.0.1:0").unwrap();
        let port = l.local_addr().unwrap().port();
        let state = Arc::new(Mutex::new(ApiState {
            next_update: 100,
            ..ApiState::default()
        }));
        let st = state.clone();
        std::thread::spawn(move || {
            for stream in l.incoming().flatten() {
                let st = st.clone();
                std::thread::spawn(move || serve(stream, st));
            }
        });
        Api { port, state }
    }

    pub fn url(&self) -> String {
        format!("http://127.0.0.1:{}", self.port)
    }

    /// Calls of a method (`sendMessage`, `chat.postMessage`, …).
    pub fn calls(&self, method: &str) -> Vec<Call> {
        self.state
            .lock()
            .unwrap()
            .calls
            .iter()
            .filter(|c| c.method == method)
            .cloned()
            .collect()
    }

    pub fn push_update(&self, mut u: Json) {
        let mut s = self.state.lock().unwrap();
        s.next_update += 1;
        u["update_id"] = json!(s.next_update);
        s.updates.push(u);
    }

    /// A private message from `account`.
    pub fn private(&self, account: i64, text: &str) {
        self.push_update(json!({"message": {
            "chat": {"id": account, "type": "private"},
            "from": {"id": account, "is_bot": false},
            "text": text,
        }}));
    }

    pub fn group(&self, chat: i64, account: i64, text: &str) {
        self.push_update(json!({"message": {
            "chat": {"id": chat, "type": "supergroup"},
            "from": {"id": account, "is_bot": false},
            "text": text,
        }}));
    }

    pub fn script(&self, status: u16, body: &str) {
        self.state
            .lock()
            .unwrap()
            .script
            .push_back((status, body.to_owned()));
    }

    /// Texts sent to `chat`.
    pub fn texts_to(&self, chat: i64) -> Vec<String> {
        self.calls("sendMessage")
            .iter()
            .filter(|c| c.body["chat_id"] == json!(chat))
            .map(|c| c.body["text"].as_str().unwrap_or("").to_owned())
            .collect()
    }
}

fn answer(
    state: &Arc<Mutex<ApiState>>,
    path: &str,
    headers: &[(String, String)],
    body: &Json,
) -> (u16, String) {
    let mut s = state.lock().unwrap();
    let ok = |r: Json| (200, json!({"ok": true, "result": r}).to_string());
    if let Some(rest) = path.strip_prefix("/bot") {
        let (token, method) = rest.rsplit_once('/').unwrap_or((rest, ""));
        if token != TG_TOKEN {
            return (
                401,
                json!({"ok": false, "error_code": 401, "description": "Unauthorized"}).to_string(),
            );
        }
        return match method {
            "getMe" => ok(json!({"id": 1, "is_bot": true, "username": "plant_bot"})),
            "getUpdates" => {
                let offset = body["offset"].as_i64().unwrap_or(0);
                let out: Vec<Json> = s
                    .updates
                    .iter()
                    .filter(|u| u["update_id"].as_i64().unwrap_or(0) >= offset)
                    .cloned()
                    .collect();
                s.updates
                    .retain(|u| u["update_id"].as_i64().unwrap_or(0) >= offset);
                ok(Json::Array(out))
            }
            "answerCallbackQuery" | "leaveChat" => ok(json!(true)),
            _ => s
                .script
                .pop_front()
                .unwrap_or_else(|| ok(json!({"message_id": 1}))),
        };
    }
    if let Some(method) = path.strip_prefix("/api/") {
        let auth = headers
            .iter()
            .find(|(k, _)| k == "authorization")
            .map(|(_, v)| v.as_str());
        if auth != Some(&format!("Bearer {SLACK_TOKEN}")) {
            return (
                200,
                json!({"ok": false, "error": "invalid_auth"}).to_string(),
            );
        }
        return match method {
            "auth.test" => (
                200,
                json!({"ok": true, "user": "plantbot", "team": "Plant"}).to_string(),
            ),
            _ => s
                .script
                .pop_front()
                .unwrap_or_else(|| (200, json!({"ok": true, "ts": "1.2"}).to_string())),
        };
    }
    (404, "{}".into())
}

fn serve(mut stream: TcpStream, state: Arc<Mutex<ApiState>>) {
    stream
        .set_read_timeout(Some(Duration::from_secs(30)))
        .unwrap();
    loop {
        let mut data = Vec::new();
        let mut buf = [0u8; 65536];
        let (head_end, body_len) = loop {
            let n = match stream.read(&mut buf) {
                Ok(0) | Err(_) => return,
                Ok(n) => n,
            };
            data.extend(&buf[..n]);
            if let Some(i) = data.windows(4).position(|w| w == b"\r\n\r\n") {
                let head = String::from_utf8_lossy(&data[..i]).into_owned();
                let len = head
                    .lines()
                    .find_map(|l| {
                        l.to_ascii_lowercase()
                            .strip_prefix("content-length:")
                            .map(|v| v.trim().parse::<usize>().unwrap())
                    })
                    .unwrap_or(0);
                break (i + 4, len);
            }
        };
        while data.len() < head_end + body_len {
            let n = match stream.read(&mut buf) {
                Ok(0) | Err(_) => return,
                Ok(n) => n,
            };
            data.extend(&buf[..n]);
        }
        let head = String::from_utf8_lossy(&data[..head_end]).into_owned();
        let mut lines = head.lines();
        let line = lines.next().unwrap_or_default().to_owned();
        let headers: Vec<(String, String)> = lines
            .filter_map(|l| l.split_once(':'))
            .map(|(k, v)| (k.to_ascii_lowercase(), v.trim().to_owned()))
            .collect();
        let body: Json =
            serde_json::from_slice(&data[head_end..head_end + body_len]).unwrap_or(Json::Null);
        let path = line.split(' ').nth(1).unwrap_or("").to_owned();
        let method = path.rsplit('/').next().unwrap_or("").to_owned();
        let (status, reply) = answer(&state, &path, &headers, &body);
        state.lock().unwrap().calls.push(Call {
            path,
            method,
            headers,
            body,
        });
        let r = format!(
            "HTTP/1.1 {status} X\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n{reply}",
            reply.len()
        );
        if stream.write_all(r.as_bytes()).is_err() {
            return;
        }
    }
}

/// Names people read (ADR 0042): every action this host is handed keeps
/// to the style, so the tests of each app hold it to the rule.
fn lint_names(name: &str, a: &wyrm_core::ActionMeta) {
    let found = wyrm_core::display::lint(name, a);
    assert!(found.is_empty(), "{}", found.join("; "));
}
