//! `SimHost`: the uplink on a `BufferHost` with a tree of other links in memory and real TCP to
//! loopback (a fake MQTT broker or HTTP server in a thread). Each event's commands are applied
//! as the portable runtime does; an event the host would fail (over 1 000 commands) panics.

#![allow(dead_code)]

use std::collections::{BTreeMap, HashMap, VecDeque};
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use wyrm_core::{Perm, Quality, Sample, Status, Value};
use wyrm_link_api::buffer::{store_cost, BufferHost, Command, Counts, Limits, Services};
use wyrm_link_api::{App, AppError, ConnId, SubId, TimerId, Who};
use wyrm_link_uplink::mqtt::{self, Packet, Parser};
use wyrm_link_uplink::Uplink;

pub const SITE: &str = "wy/s";

#[derive(Default)]
struct Shared {
    now_us: u64,
    store: HashMap<String, Vec<u8>>,
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
    fn may(&self, _key: &str, _perm: Perm) -> bool {
        true
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
}

enum Ev {
    Value(u64, String, Sample),
}

pub struct SimHost {
    buf: BufferHost,
    shared: Arc<Mutex<Shared>>,
    pub app: Option<Uplink>,
    pub values: BTreeMap<String, Value>,
    /// The link's own nodes and their values.
    pub nodes: BTreeMap<String, Option<Value>>,
    timers: BTreeMap<u64, u64>,
    pub subs: BTreeMap<u64, String>,
    queue: VecDeque<Ev>,
    pub net: String,
    pub params: Value,
}

pub fn engineer() -> Who {
    Who {
        subject: Some("user:eng".into()),
        grants: vec![("wy/s/downstream/uplink/**".into(), Perm::Config)],
        authority: Some(vec![("wy/s/**".into(), Perm::Config)]),
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

impl SimHost {
    /// A host whose `net` allows loopback on `port`.
    pub fn new(port: u16) -> Self {
        let shared = Arc::new(Mutex::new(Shared {
            now_us: 1_800_000_000_000_000,
            ..Shared::default()
        }));
        let limits = Limits {
            store_bytes: 2 << 20,
            ..Limits::default()
        };
        let net = format!("127.0.0.1:{port}");
        let params = map(&[
            ("site", s("s")),
            ("own", s("wy/s/downstream/uplink")),
            ("net", s(&net)),
        ]);
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
            values: BTreeMap::new(),
            nodes: BTreeMap::new(),
            timers: BTreeMap::new(),
            subs: BTreeMap::new(),
            queue: VecDeque::new(),
            net,
            params,
        }
    }

    pub fn now(&self) -> u64 {
        self.shared.lock().unwrap().now_us
    }

    /// `n` numbers `wy/s/downstream/mock/d<i>/temp` with values `i`.
    pub fn with_mock(mut self, n: usize) -> Self {
        for i in 0..n {
            self.values.insert(
                format!("wy/s/downstream/mock/d{i}/temp"),
                Value::Int(i as i64),
            );
        }
        self
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
                Command::DeclareNode(p, _) => {
                    self.nodes.entry(p).or_insert(None);
                }
                Command::RemoveNode(p) => {
                    let below = format!("{p}/");
                    self.nodes.retain(|k, _| *k != p && !k.starts_with(&below));
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
                    let prefix = key.trim_end_matches("/**").to_owned();
                    for (k, v) in &self.values {
                        if k == &prefix || k.starts_with(&format!("{prefix}/")) {
                            self.queue
                                .push_back(Ev::Value(id, k.clone(), sample(v.clone(), now)));
                        }
                    }
                    self.subs.insert(id, key);
                }
                Command::Unsubscribe(SubId(id)) => {
                    self.subs.remove(&id);
                }
                Command::List(..) | Command::Set(..) | Command::Invoke(..) => {
                    panic!("the uplink never lists, sets or invokes")
                }
                Command::DeclareAction(..) | Command::Log(..) => {}
            }
        }
        self.buf.set_counts(self.counts());
    }

    pub fn start(&mut self) {
        let app = Uplink::start(&mut self.buf, self.params.clone()).expect("start");
        self.app = Some(app);
        self.apply();
        self.settle();
    }

    /// A restart: a new instance on the same store.
    pub fn restart(&mut self) {
        if let Some(mut a) = self.app.take() {
            a.stop(&mut self.buf);
            self.apply();
        }
        self.timers.clear();
        self.subs.clear();
        self.queue.clear();
        self.nodes.clear();
        self.buf.set_counts(self.counts());
        self.start();
    }

    /// Delivers queued events and due timers until nothing is left (time does not move).
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

    /// Moves the clock and runs what became due.
    pub fn advance_ms(&mut self, ms: u64) {
        self.shared.lock().unwrap().now_us += ms * 1000;
        self.settle();
    }

    /// Steps of 250 ms (with a little real time for the broker thread) until `cond` holds.
    pub fn until(&mut self, what: &str, mut cond: impl FnMut(&Self) -> bool) {
        for _ in 0..400 {
            if cond(self) {
                return;
            }
            std::thread::sleep(Duration::from_millis(5));
            self.advance_ms(250);
        }
        panic!("not in time: {what}; nodes {:?}", self.nodes);
    }

    pub fn invoke(&mut self, path: &str, action: &str, args: Value) -> Result<Value, AppError> {
        let r = self.app.as_mut().expect("started").on_invoke(
            &mut self.buf,
            path,
            action,
            args,
            &engineer(),
        );
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

    /// A value of another link changes.
    pub fn put_value(&mut self, key: &str, v: Value) {
        self.values.insert(key.to_owned(), v.clone());
        let now = self.now();
        for (id, k) in &self.subs {
            let prefix = k.trim_end_matches("/**");
            if key == prefix || key.starts_with(&format!("{prefix}/")) {
                self.queue
                    .push_back(Ev::Value(*id, key.to_owned(), sample(v.clone(), now)));
            }
        }
        self.settle();
    }

    pub fn leaf(&self, name: &str, l: &str) -> Value {
        self.nodes
            .get(&format!("{name}/{l}"))
            .cloned()
            .flatten()
            .unwrap_or(Value::Null)
    }

    pub fn status(&self, name: &str) -> String {
        match self.leaf(name, "status") {
            Value::Str(s) => s,
            _ => String::new(),
        }
    }

    pub fn published(&self, name: &str) -> u64 {
        match self.leaf(name, "published") {
            Value::UInt(n) => n,
            _ => 0,
        }
    }

    pub fn store_has(&self, k: &str) -> bool {
        self.shared.lock().unwrap().store.contains_key(k)
    }
}

fn sample(v: Value, t: u64) -> Sample {
    Sample {
        v,
        q: Quality::Good,
        t,
    }
}

impl Drop for SimHost {
    fn drop(&mut self) {
        if let Some(mut a) = self.app.take() {
            a.stop(&mut self.buf);
            let _ = self.buf.finish();
        }
    }
}

// ---------- a fake MQTT broker ----------

/// What the broker saw.
#[derive(Default, Debug)]
pub struct Seen {
    pub connects: Vec<ConnectSeen>,
    /// `(topic, payload, qos, retain)`, in order.
    pub publishes: Vec<(String, Vec<u8>, u8, bool)>,
    pub subscribes: Vec<String>,
    pub pings: usize,
}

#[derive(Debug, Clone)]
pub struct ConnectSeen {
    pub client_id: String,
    pub username: Option<String>,
    pub password: Option<Vec<u8>>,
    pub will_topic: Option<String>,
    pub will_payload: Vec<u8>,
    pub keep_alive: u16,
}

/// A PUBLISH to send to a client: `(topic, payload)`.
pub type Injected = Arc<Mutex<Option<(String, Vec<u8>)>>>;
/// One HTTP request: `(request line, headers, body)`.
pub type Requests = Arc<Mutex<Vec<(String, Vec<(String, String)>, Vec<u8>)>>>;

pub struct Broker {
    pub port: u16,
    pub seen: Arc<Mutex<Seen>>,
    /// The CONNACK code to answer with.
    pub connack: Arc<Mutex<u8>>,
    /// A PUBLISH the broker sends to a client after its next NBIRTH (once).
    pub inject: Injected,
}

/// CONNECT's variable header and payload, read back.
fn parse_connect(body: &[u8]) -> ConnectSeen {
    let str_at = |b: &[u8], at: usize| -> (Vec<u8>, usize) {
        let n = u16::from_be_bytes([b[at], b[at + 1]]) as usize;
        (b[at + 2..at + 2 + n].to_vec(), at + 2 + n)
    };
    let (_, at) = str_at(body, 0); // "MQTT"
    let flags = body[at + 1];
    let keep_alive = u16::from_be_bytes([body[at + 2], body[at + 3]]);
    let (cid, mut at) = str_at(body, at + 4);
    let mut c = ConnectSeen {
        client_id: String::from_utf8_lossy(&cid).into_owned(),
        username: None,
        password: None,
        will_topic: None,
        will_payload: Vec::new(),
        keep_alive,
    };
    if flags & 0x04 != 0 {
        let (t, a) = str_at(body, at);
        let (p, a) = str_at(body, a);
        c.will_topic = Some(String::from_utf8_lossy(&t).into_owned());
        c.will_payload = p;
        at = a;
    }
    if flags & 0x80 != 0 {
        let (u, a) = str_at(body, at);
        c.username = Some(String::from_utf8_lossy(&u).into_owned());
        at = a;
    }
    if flags & 0x40 != 0 {
        let (p, _) = str_at(body, at);
        c.password = Some(p);
    }
    c
}

impl Broker {
    pub fn start() -> Self {
        let l = TcpListener::bind("127.0.0.1:0").unwrap();
        let port = l.local_addr().unwrap().port();
        let seen = Arc::new(Mutex::new(Seen::default()));
        let connack = Arc::new(Mutex::new(0u8));
        let inject: Injected = Arc::new(Mutex::new(None));
        let (s2, c2, i2) = (seen.clone(), connack.clone(), inject.clone());
        std::thread::spawn(move || {
            for stream in l.incoming().flatten() {
                let (seen, connack, inject) = (s2.clone(), c2.clone(), i2.clone());
                std::thread::spawn(move || serve(stream, seen, connack, inject));
            }
        });
        Broker {
            port,
            seen,
            connack,
            inject,
        }
    }

    pub fn seen(&self) -> std::sync::MutexGuard<'_, Seen> {
        self.seen.lock().unwrap()
    }

    pub fn publishes(&self, topic_part: &str) -> Vec<(String, Vec<u8>)> {
        self.seen()
            .publishes
            .iter()
            .filter(|(t, ..)| t.contains(topic_part))
            .map(|(t, p, ..)| (t.clone(), p.clone()))
            .collect()
    }
}

fn serve(mut stream: TcpStream, seen: Arc<Mutex<Seen>>, connack: Arc<Mutex<u8>>, inject: Injected) {
    stream
        .set_read_timeout(Some(Duration::from_secs(30)))
        .unwrap();
    let mut parser = Parser::default();
    let mut buf = [0u8; 65536];
    loop {
        let n = match stream.read(&mut buf) {
            Ok(0) | Err(_) => return,
            Ok(n) => n,
        };
        // the raw CONNECT is read here: the client parser has no CONNECT
        if buf[0] >> 4 == mqtt::CONNECT && parser_is_empty(&parser) {
            let (len, head) = {
                let mut v = 0usize;
                let mut m = 1usize;
                let mut i = 1;
                loop {
                    v += usize::from(buf[i] & 0x7f) * m;
                    if buf[i] & 0x80 == 0 {
                        break;
                    }
                    m *= 128;
                    i += 1;
                }
                (v, i + 1)
            };
            let c = parse_connect(&buf[head..head + len]);
            seen.lock().unwrap().connects.push(c);
            let code = *connack.lock().unwrap();
            stream.write_all(&[0x20, 2, 0, code]).unwrap();
            if code != 0 {
                return;
            }
            if n > head + len {
                parser.feed(&buf[head + len..n]).unwrap();
            }
        } else {
            parser.feed(&buf[..n]).unwrap();
        }
        while let Some(p) = parser.packet().unwrap() {
            match p {
                Packet::Publish {
                    topic,
                    payload,
                    qos,
                    retain,
                    id,
                } => {
                    let birth = topic.contains("NBIRTH");
                    seen.lock()
                        .unwrap()
                        .publishes
                        .push((topic, payload, qos, retain));
                    if let (1, Some(id)) = (qos, id) {
                        stream.write_all(&mqtt::puback(id)).unwrap();
                    }
                    // a command for the edge node, once it is born
                    if birth {
                        if let Some((t, p)) = inject.lock().unwrap().take() {
                            stream
                                .write_all(&mqtt::publish(&t, &p, 0, false, None))
                                .unwrap();
                        }
                    }
                }
                Packet::Other(mqtt::SUBSCRIBE) => {
                    // the client parser gives SUBSCRIBE as Other: answer every subscription
                    seen.lock().unwrap().subscribes.push("?".into());
                }
                Packet::Other(mqtt::PINGREQ) => {
                    seen.lock().unwrap().pings += 1;
                    stream.write_all(&[0xd0, 0]).unwrap();
                }
                Packet::Other(mqtt::DISCONNECT) => return,
                _ => {}
            }
        }
    }
}

fn parser_is_empty(p: &Parser) -> bool {
    format!("{p:?}").contains("buf: []")
}

// ---------- a fake HTTP server (AWS IoT Core's publish) ----------

/// What the HTTP server saw: `(request line, headers, body)`.
pub struct HttpServer {
    pub port: u16,
    pub requests: Requests,
}

impl HttpServer {
    pub fn start(status: u16) -> Self {
        let l = TcpListener::bind("127.0.0.1:0").unwrap();
        let port = l.local_addr().unwrap().port();
        let requests = Arc::new(Mutex::new(Vec::new()));
        let r2 = requests.clone();
        std::thread::spawn(move || {
            for mut stream in l.incoming().flatten() {
                let requests = r2.clone();
                std::thread::spawn(move || {
                    stream
                        .set_read_timeout(Some(Duration::from_secs(30)))
                        .unwrap();
                    loop {
                        let mut data = Vec::new();
                        let mut buf = [0u8; 65536];
                        let (head_end, mut body_len) = loop {
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
                        let body = data[head_end..head_end + body_len].to_vec();
                        body_len = 0;
                        let _ = body_len;
                        requests.lock().unwrap().push((line, headers, body));
                        let reply = format!("HTTP/1.1 {status} X\r\nContent-Length: 2\r\n\r\n{{}}");
                        if stream.write_all(reply.as_bytes()).is_err() {
                            return;
                        }
                    }
                });
            }
        });
        HttpServer { port, requests }
    }
}
