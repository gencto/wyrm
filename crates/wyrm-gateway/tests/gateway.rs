//! Gateway end to end: mock link + gateway on one isolated Zenoh session,
//! raw HTTP/1.1 over TCP and a WebSocket client, CBOR everywhere.

use futures_util::{SinkExt, StreamExt};
use std::collections::BTreeMap;
use std::net::SocketAddr;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use tokio::sync::oneshot;
use tokio_tungstenite::tungstenite::Message;
use wyrm_core::codec::{from_slice, to_vec};
use wyrm_core::{NodeMeta, Perm, Status, Value};
use wyrm_gateway::{AuditEvent, Gateway, GatewayConfig, RoleTable};
use wyrm_link_mock::{Mock, MockConfig};
use wyrm_link_sdk::harness::{isolated_config, SITE};
use wyrm_link_sdk::{LinkConfig, LinkHandle};

const ROOT: &str = "wy/test/downstream/mock";
const ADMIN_PW: &str = "admin password";

fn temp_dir(name: &str) -> PathBuf {
    let d = std::env::temp_dir().join(format!("wyrm-gateway-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&d);
    d
}

struct Env {
    gw: Arc<Gateway>,
    session: zenoh::Session,
    addr: SocketAddr,
    link: Option<LinkHandle<Mock>>,
    stop: Option<oneshot::Sender<()>>,
    audit: Arc<Mutex<Vec<AuditEvent>>>,
}

impl Env {
    async fn start(name: &str, ttl: Duration) -> Self {
        let mut roles = RoleTable::default();
        roles.insert(
            "limited",
            vec![
                ("wy/{site}/downstream/mock/g1/**".into(), Perm::None),
                ("wy/{site}/downstream/**".into(), Perm::Read),
            ],
        );
        // config on flows, no rights on devices
        roles.insert(
            "flows_only",
            vec![("wy/{site}/dataflows/**".into(), Perm::Config)],
        );
        // writes on the agent (asks, approves), on one branch of the devices and on flows
        roles.insert(
            "approver",
            vec![
                ("wy/{site}/downstream/agent/**".into(), Perm::Write),
                ("wy/{site}/downstream/mock/g1/**".into(), Perm::Read),
                ("wy/{site}/downstream/mock/**".into(), Perm::Write),
                ("wy/{site}/dataflows/**".into(), Perm::Write),
            ],
        );
        let mut cfg = GatewayConfig::new(SITE, temp_dir(name), "127.0.0.1:0".parse().unwrap());
        cfg.session_ttl = ttl;
        cfg.roles = roles;
        let gw = Gateway::open(cfg, b"test state key").unwrap();
        let audit = Arc::new(Mutex::new(Vec::new()));
        let sink = audit.clone();
        gw.set_audit(move |e| sink.lock().unwrap().push(e));
        assert!(gw.ensure_admin("root", ADMIN_PW).unwrap());
        assert!(!gw.ensure_admin("root", "other password").unwrap());

        let session = zenoh::open(isolated_config()).await.unwrap();
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
        let link = wyrm_link_sdk::spawn::<Mock>(session.clone(), lc, mock)
            .await
            .unwrap();
        let (stop, rx) = oneshot::channel::<()>();
        tokio::spawn(gw.clone().serve(session.clone(), async {
            let _ = rx.await;
        }));
        let addr = tokio::time::timeout(Duration::from_secs(5), gw.local_addr())
            .await
            .unwrap();
        Self {
            gw,
            session,
            addr,
            link: Some(link),
            stop: Some(stop),
            audit,
        }
    }

    async fn stop(mut self) {
        if let Some(s) = self.stop.take() {
            let _ = s.send(());
        }
        if let Some(l) = self.link.take() {
            l.stop().await;
        }
    }

    /// Raw HTTP/1.1 request; returns `(status, CBOR body or Null)`.
    async fn http(
        &self,
        method: &str,
        path: &str,
        token: Option<&str>,
        body: Option<Value>,
    ) -> (u16, Value) {
        let body = body.map(|b| to_vec(&b).unwrap()).unwrap_or_default();
        let mut req = format!(
            "{method} {path} HTTP/1.1\r\nHost: gw\r\nConnection: close\r\nContent-Type: application/cbor\r\nContent-Length: {}\r\n",
            body.len()
        );
        if let Some(t) = token {
            req.push_str(&format!("Authorization: Bearer {t}\r\n"));
        }
        req.push_str("\r\n");
        // One write: a request the server refuses before reading its body
        // (401) would otherwise leave the body unread in the socket, and
        // closing it then resets the connection before we read the answer.
        let mut msg = req.into_bytes();
        msg.extend_from_slice(&body);
        let mut s = TcpStream::connect(self.addr).await.unwrap();
        s.write_all(&msg).await.unwrap();
        let mut resp = Vec::new();
        tokio::time::timeout(Duration::from_secs(10), s.read_to_end(&mut resp))
            .await
            .expect("http response in time")
            .unwrap();
        let split = resp
            .windows(4)
            .position(|w| w == b"\r\n\r\n")
            .expect("header end");
        let head = String::from_utf8_lossy(&resp[..split]).to_string();
        let status: u16 = head.split(' ').nth(1).unwrap().parse().unwrap();
        let body = &resp[split + 4..];
        let v = if body.is_empty() {
            Value::Null
        } else {
            from_slice(body).expect("CBOR body")
        };
        (status, v)
    }

    async fn login(&self, user: &str, password: &str) -> (u16, Value) {
        self.http(
            "POST",
            "/api/login",
            None,
            Some(map([
                ("user", Value::from(user)),
                ("password", Value::from(password)),
            ])),
        )
        .await
    }

    async fn session(&self, user: &str, password: &str) -> String {
        let (st, v) = self.login(user, password).await;
        assert_eq!(st, 200, "login {user}: {v:?}");
        match get(&v, "session") {
            Value::Str(s) => s.clone(),
            v => panic!("session: {v:?}"),
        }
    }

    async fn add_user(&self, admin: &str, name: &str, roles: &[&str]) -> String {
        let (st, v) = self
            .http(
                "POST",
                "/api/users",
                Some(admin),
                Some(map([
                    ("name", Value::from(name)),
                    ("password", Value::from("user password")),
                    (
                        "roles",
                        Value::Array(roles.iter().map(|r| Value::from(*r)).collect()),
                    ),
                ])),
            )
            .await;
        assert_eq!(st, 200, "add {name}: {v:?}");
        self.session(name, "user password").await
    }

    /// A single-use WebSocket ticket for a session (`None` = refused).
    async fn ticket(&self, token: &str) -> Option<String> {
        let (st, v) = self.http("POST", "/api/ws-ticket", Some(token), None).await;
        match (st, get(&v, "ticket")) {
            (200, Value::Str(t)) => Some(t.clone()),
            _ => None,
        }
    }

    async fn ws(&self, token: &str) -> Ws {
        let t = self.ticket(token).await.expect("ws ticket");
        let url = format!("ws://{}/api/ws?ticket={t}", self.addr);
        let (s, _) = tokio_tungstenite::connect_async(url).await.unwrap();
        Ws { s, next_id: 1 }
    }
}

type WsStream = tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<TcpStream>>;

struct Ws {
    s: WsStream,
    next_id: u64,
}

impl Ws {
    async fn send(&mut self, op: &str, key: &str, extra: Vec<(&str, Value)>) -> u64 {
        let id = self.next_id;
        self.next_id += 1;
        let mut m: BTreeMap<String, Value> = BTreeMap::from([
            ("id".to_owned(), Value::UInt(id)),
            ("op".to_owned(), Value::from(op)),
            ("key".to_owned(), Value::from(key)),
        ]);
        for (k, v) in extra {
            m.insert(k.to_owned(), v);
        }
        self.s
            .send(Message::Binary(to_vec(&Value::Map(m)).unwrap().into()))
            .await
            .unwrap();
        id
    }

    async fn frame(&mut self) -> Value {
        loop {
            let m = tokio::time::timeout(Duration::from_secs(5), self.s.next())
                .await
                .expect("frame in time")
                .expect("socket open")
                .unwrap();
            if let Message::Binary(b) = m {
                return from_slice(&b).unwrap();
            }
        }
    }

    /// The final reply (`ok` key) for `id`, skipping everything else.
    async fn reply(&mut self, id: u64) -> Value {
        loop {
            let f = self.frame().await;
            if get(&f, "id") == &Value::UInt(id) && f_has(&f, "ok") {
                return f;
            }
        }
    }

    /// The next event for `id`.
    async fn event(&mut self, id: u64) -> Value {
        loop {
            let f = self.frame().await;
            if get(&f, "id") == &Value::UInt(id) && f_has(&f, "event") {
                return get(&f, "event").clone();
            }
        }
    }

    async fn call(&mut self, op: &str, key: &str, extra: Vec<(&str, Value)>) -> Value {
        let id = self.send(op, key, extra).await;
        self.reply(id).await
    }
}

fn map<const N: usize>(f: [(&str, Value); N]) -> Value {
    Value::Map(f.into_iter().map(|(k, v)| (k.to_owned(), v)).collect())
}

fn get<'a>(v: &'a Value, k: &str) -> &'a Value {
    match v {
        Value::Map(m) => m.get(k).unwrap_or(&Value::Null),
        _ => &Value::Null,
    }
}

fn f_has(v: &Value, k: &str) -> bool {
    matches!(v, Value::Map(m) if m.contains_key(k))
}

fn is_ok(reply: &Value) -> bool {
    get(reply, "ok") == &Value::Bool(true)
}

fn err_status(reply: &Value) -> Option<Status> {
    match get(get(reply, "error"), "status") {
        Value::UInt(c) => Status::try_from(*c as u8).ok(),
        _ => None,
    }
}

fn names(children: &Value) -> Vec<String> {
    let Value::Array(a) = children else {
        panic!("children: {children:?}")
    };
    a.iter()
        .map(|c| match get(c, "name") {
            Value::Str(s) => s.clone(),
            v => panic!("name: {v:?}"),
        })
        .collect()
}

#[tokio::test(flavor = "multi_thread")]
async fn login_bad_password_and_rate_limit() {
    let env = Env::start("login", wyrm_gateway::SESSION_TTL).await;
    let tok = env.session("root", ADMIN_PW).await;
    let (st, me) = env.http("GET", "/api/me", Some(&tok), None).await;
    assert_eq!(st, 200);
    assert_eq!(get(&me, "sub"), &Value::from("root"));
    assert_eq!(get(&me, "max"), &Value::from("config"));
    assert_eq!(env.http("GET", "/api/me", None, None).await.0, 401);

    for _ in 0..wyrm_gateway::LOGIN_FAILURES {
        let (st, v) = env.login("root", "wrong password").await;
        assert_eq!(st, 401);
        assert_eq!(err_status_body(&v), Some(Status::PermissionDenied));
    }
    // Locked for this user and address, even with the right password.
    let (st, v) = env.login("root", ADMIN_PW).await;
    assert_eq!(st, 429);
    assert_eq!(err_status_body(&v), Some(Status::RateLimited));
    // More refused attempts add no audit records (one per window).
    for _ in 0..5 {
        assert_eq!(env.login("root", "wrong password").await.0, 429);
    }
    // Unknown users get the same answer as wrong passwords.
    let (st, v) = env.login("nobody", "whatever pw").await;
    assert_eq!(
        (st, get(&v, "message")),
        (401, &Value::from("invalid credentials"))
    );

    let audit = env.audit.lock().unwrap().clone();
    assert!(audit
        .iter()
        .any(|e| matches!(e, AuditEvent::LoginOk { user, .. } if user == "root")));
    assert_eq!(
        audit
            .iter()
            .filter(
                |e| matches!(e, AuditEvent::LoginFailed { reason, .. } if *reason == "rate_limited")
            )
            .count(),
        1,
        "one record per window"
    );
    assert!(
        !format!("{audit:?}").contains("wrong password"),
        "no passwords in audit"
    );
    env.stop().await;
}

fn err_status_body(v: &Value) -> Option<Status> {
    match get(v, "status") {
        Value::UInt(c) => Status::try_from(*c as u8).ok(),
        _ => None,
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn viewer_lists_and_subscribes_but_cannot_set() {
    let env = Env::start("viewer", wyrm_gateway::SESSION_TTL).await;
    let admin = env.session("root", ADMIN_PW).await;
    let tok = env.add_user(&admin, "olena", &["viewer"]).await;
    let mut ws = env.ws(&tok).await;

    let r = ws.call("meta", ROOT, vec![]).await;
    assert!(is_ok(&r), "{r:?}");
    let Value::Bytes(b) = get(&r, "result") else {
        panic!("meta bytes: {r:?}")
    };
    let meta: NodeMeta = from_slice(b).unwrap();
    assert_eq!(meta.children.unwrap(), ["g0", "g1"]);

    let r = ws.call("children", &format!("{ROOT}/g0"), vec![]).await;
    assert_eq!(names(get(&r, "result")), ["p0", "p2", "p4"]);

    let id = ws.send("list", ROOT, vec![]).await;
    assert!(is_ok(&ws.reply(id).await));
    let ev = ws.event(id).await;
    assert_eq!(get(&ev, "type"), &Value::from("refreshed"));
    assert_eq!(names(get(&ev, "children")), ["g0", "g1"]);

    let sid = ws.send("subscribe", &format!("{ROOT}/**"), vec![]).await;
    assert!(is_ok(&ws.reply(sid).await));
    let ev = ws.event(sid).await;
    assert_eq!(get(&ev, "type"), &Value::from("sample"));
    assert!(matches!(get(&ev, "v"), Value::Float(_)));

    let r = ws
        .call(
            "set",
            &format!("{ROOT}/g0/p0"),
            vec![("value", Value::Float(1.0))],
        )
        .await;
    assert_eq!(err_status(&r), Some(Status::PermissionDenied), "{r:?}");

    // `count` is a read-level action; `reset` needs write, refused by the link.
    let r = ws
        .call(
            "invoke",
            ROOT,
            vec![
                ("action", Value::from("count")),
                ("args", map([("n", Value::UInt(3))])),
            ],
        )
        .await;
    assert!(is_ok(&r), "{r:?}");
    let r = ws
        .call("invoke", ROOT, vec![("action", Value::from("reset"))])
        .await;
    assert_eq!(err_status(&r), Some(Status::PermissionDenied), "{r:?}");

    let r = ws
        .call("unsubscribe", "", vec![("sub", Value::UInt(sid))])
        .await;
    assert!(is_ok(&r));
    // Other sites and suffixed keys never reach Zenoh.
    let r = ws.call("meta", "wy/other/downstream/mock", vec![]).await;
    assert_eq!(err_status(&r), Some(Status::InvalidParameter));
    let r = ws.call("meta", &format!("{ROOT}/~set"), vec![]).await;
    assert_eq!(err_status(&r), Some(Status::InvalidParameter));
    assert!(env
        .audit
        .lock()
        .unwrap()
        .iter()
        .any(|e| matches!(e, AuditEvent::Denied { op, .. } if op == "set")));
    env.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn operator_sets() {
    let env = Env::start("operator", wyrm_gateway::SESSION_TTL).await;
    let admin = env.session("root", ADMIN_PW).await;
    let tok = env.add_user(&admin, "ivan", &["operator"]).await;
    let mut ws = env.ws(&tok).await;
    let key = format!("{ROOT}/g0/p0");
    let r = ws
        .call("set", &key, vec![("value", Value::Float(42.0))])
        .await;
    assert!(is_ok(&r), "{r:?}");
    let r = ws.call("set", &key, vec![]).await;
    assert_eq!(err_status(&r), Some(Status::InvalidParameter));
    let r = ws
        .call("invoke", ROOT, vec![("action", Value::from("reset"))])
        .await;
    assert!(is_ok(&r), "{r:?}");
    env.stop().await;
}

/// ADR 0018: writes reach a downstream site through the WebSocket and
/// `POST /api/invoke`, checked under the own site's roles and signed for
/// that site; the site's links trust the gateway key only at `write` under
/// its `downstream` (as from `sys/signing_keys`).
#[tokio::test(flavor = "multi_thread")]
async fn writes_reach_a_downstream_site() {
    let env = Env::start("downwrite", Duration::from_secs(600)).await;
    let trust = || {
        vec![wyrm_link_sdk::LimitedKey {
            key: env.gw.verifying_key(),
            cap: Perm::Write,
            scopes: vec!["wy/edge/downstream".into()],
            subject: None,
        }]
    };
    let mut lc = LinkConfig::new("edge", "mock");
    lc.limited_keys = trust();
    let mock = MockConfig {
        points: 2,
        rate_hz: 5.0,
        depth: 1,
        fanout: 1,
        writable: true,
    };
    let m = wyrm_link_sdk::spawn::<Mock>(env.session.clone(), lc, mock)
        .await
        .unwrap();
    let mut lc = LinkConfig::new("edge", "upload");
    lc.limited_keys = trust();
    let up = wyrm_link_sdk::spawn::<Upload>(env.session.clone(), lc, ())
        .await
        .unwrap();
    env.gw.set_downstream_sites(vec!["edge".into()]);
    let admin = env.session("root", ADMIN_PW).await;
    let op = env.add_user(&admin, "olha", &["operator"]).await;
    let viewer = env.add_user(&admin, "petro", &["viewer"]).await;

    let point = "wy/edge/downstream/mock/g0/p0";
    let mut ws = env.ws(&op).await;
    let r = ws
        .call("set", point, vec![("value", Value::Float(7.0))])
        .await;
    assert!(is_ok(&r), "{r:?}");
    let r = ws
        .call(
            "invoke",
            "wy/edge/downstream/mock",
            vec![("action", Value::from("reset"))],
        )
        .await;
    assert!(is_ok(&r), "{r:?}");
    let mut ws = env.ws(&viewer).await;
    let r = ws
        .call("set", point, vec![("value", Value::Float(8.0))])
        .await;
    assert_eq!(err_status(&r), Some(Status::PermissionDenied), "{r:?}");

    let put = "/api/invoke?key=wy/edge/downstream/upload&action=put";
    let data = map([("data", Value::Bytes(vec![1; 70 * 1024]))]);
    let (st, v) = env.http("POST", put, Some(&op), Some(data)).await;
    assert_eq!(st, 200, "{v:?}");
    assert_eq!(get(&v, "result"), &Value::UInt(70 * 1024));
    let (st, _) = env
        .http(
            "POST",
            put,
            Some(&viewer),
            Some(map([("data", Value::Bytes(vec![1]))])),
        )
        .await;
    assert_eq!(st, 403);
    up.stop().await;
    m.stop().await;
    env.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn samples_and_children_are_filtered_per_point() {
    let env = Env::start("filter", wyrm_gateway::SESSION_TTL).await;
    let admin = env.session("root", ADMIN_PW).await;
    let tok = env.add_user(&admin, "guest", &["limited"]).await;
    let mut ws = env.ws(&tok).await;

    let sid = ws.send("subscribe", &format!("{ROOT}/**"), vec![]).await;
    assert!(is_ok(&ws.reply(sid).await));
    let mut keys = std::collections::BTreeSet::new();
    for _ in 0..30 {
        let ev = ws.event(sid).await;
        let Value::Str(k) = get(&ev, "key") else {
            panic!("key: {ev:?}")
        };
        keys.insert(k.clone());
    }
    assert!(keys.iter().all(|k| !k.contains("/g1/")), "{keys:?}");
    assert!(keys.iter().any(|k| k.contains("/g0/")), "{keys:?}");

    let r = ws.call("children", ROOT, vec![]).await;
    assert_eq!(names(get(&r, "result")), ["g0"]);
    let r = ws.call("meta", &format!("{ROOT}/g1/p1"), vec![]).await;
    assert_eq!(err_status(&r), Some(Status::PermissionDenied));
    // Subscribing only to the hidden branch is refused outright.
    let r = ws.call("subscribe", &format!("{ROOT}/g1/**"), vec![]).await;
    assert_eq!(err_status(&r), Some(Status::PermissionDenied));
    env.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn expired_and_tampered_sessions_are_rejected() {
    // Whole-second `iat`: a 2 s session lives for more than 1 s.
    let env = Env::start("expiry", Duration::from_secs(2)).await;
    let tok = env.session("root", ADMIN_PW).await;
    let mut open = env.ws(&tok).await;
    assert_eq!(env.http("GET", "/api/me", Some(&tok), None).await.0, 200);

    let mut bad = tok.clone().into_bytes();
    let i = bad.len() / 2;
    bad[i] = if bad[i] == b'A' { b'B' } else { b'A' };
    let bad = String::from_utf8(bad).unwrap();
    assert_eq!(env.http("GET", "/api/me", Some(&bad), None).await.0, 401);
    assert!(
        env.ticket(&bad).await.is_none(),
        "no ticket for a tampered session"
    );
    // the session itself is never accepted in the URL; a ticket works once
    let url = format!("ws://{}/api/ws?session={tok}", env.addr);
    assert!(tokio_tungstenite::connect_async(url).await.is_err());
    let t = env.ticket(&tok).await.unwrap();
    let url = format!("ws://{}/api/ws?ticket={t}", env.addr);
    assert!(tokio_tungstenite::connect_async(url.clone()).await.is_ok());
    assert!(
        tokio_tungstenite::connect_async(url).await.is_err(),
        "single use"
    );

    // An open socket is closed when the session expires.
    let closed = tokio::time::timeout(Duration::from_secs(4), async {
        loop {
            match open.s.next().await {
                Some(Ok(Message::Close(f))) => return f.map(|f| u16::from(f.code)),
                Some(Ok(_)) => continue,
                other => panic!("expected a close frame, got {other:?}"),
            }
        }
    })
    .await
    .expect("closed at expiry");
    assert_eq!(closed, Some(4001));
    assert_eq!(env.http("GET", "/api/me", Some(&tok), None).await.0, 401);
    assert!(env.ticket(&tok).await.is_none(), "no ticket after expiry");
    env.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn admin_manages_users() {
    let env = Env::start("admin", wyrm_gateway::SESSION_TTL).await;
    let admin = env.session("root", ADMIN_PW).await;
    let viewer = env.add_user(&admin, "olena", &["viewer"]).await;

    // Only `config` on wy/<site>/sys/** may manage users.
    let (st, _) = env.http("GET", "/api/users", Some(&viewer), None).await;
    assert_eq!(st, 403);
    let eng = env.add_user(&admin, "eng", &["engineer"]).await;
    assert_eq!(env.http("GET", "/api/users", Some(&eng), None).await.0, 403);
    let (st, list) = env.http("GET", "/api/users", Some(&admin), None).await;
    assert_eq!(st, 200);
    assert_eq!(names(&list), ["eng", "olena", "root"]);

    let roles = |r: &[&str]| {
        Some(map([(
            "roles",
            Value::Array(r.iter().map(|s| Value::from(*s)).collect()),
        )]))
    };
    let (st, _) = env
        .http(
            "POST",
            "/api/users/olena/roles",
            Some(&admin),
            roles(&["nope"]),
        )
        .await;
    assert_eq!(st, 400, "unknown role");
    let (st, _) = env
        .http(
            "POST",
            "/api/users/olena/roles",
            Some(&admin),
            roles(&["operator"]),
        )
        .await;
    assert_eq!(st, 200);
    // Roles come from the store, so the old session already has them.
    let (_, me) = env.http("GET", "/api/me", Some(&viewer), None).await;
    assert_eq!(
        get(&me, "roles"),
        &Value::Array(vec![Value::from("operator")])
    );

    // An open socket notices a disable on its next request.
    let mut ws = env.ws(&viewer).await;
    assert!(is_ok(&ws.call("meta", ROOT, vec![]).await));
    let (st, _) = env
        .http(
            "POST",
            "/api/users/olena/disabled",
            Some(&admin),
            Some(map([("disabled", Value::Bool(true))])),
        )
        .await;
    assert_eq!(st, 200);
    let r = ws.call("meta", ROOT, vec![]).await;
    assert_eq!(err_status(&r), Some(Status::PermissionDenied));
    assert_eq!(env.http("GET", "/api/me", Some(&viewer), None).await.0, 401);
    assert_eq!(env.login("olena", "user password").await.0, 401);
    let (st, _) = env
        .http(
            "POST",
            "/api/users/olena/disabled",
            Some(&admin),
            Some(map([("disabled", Value::Bool(false))])),
        )
        .await;
    assert_eq!(st, 200);

    // A new password ends the sessions issued before it.
    let before = env.session("olena", "user password").await;
    let (st, _) = env
        .http(
            "POST",
            "/api/users/olena/password",
            Some(&admin),
            Some(map([("password", Value::from("new password"))])),
        )
        .await;
    assert_eq!(st, 200);
    assert_eq!(env.http("GET", "/api/me", Some(&before), None).await.0, 401);
    env.session("olena", "new password").await;

    let (st, _) = env
        .http(
            "POST",
            "/api/users/olena/password",
            Some(&admin),
            Some(map([("password", Value::from("short"))])),
        )
        .await;
    assert_eq!(st, 400, "password policy");
    assert_eq!(
        env.http("DELETE", "/api/users/olena", Some(&admin), None)
            .await
            .0,
        200
    );
    let (st, v) = env
        .http("DELETE", "/api/users/olena", Some(&admin), None)
        .await;
    assert_eq!((st, err_status_body(&v)), (404, Some(Status::NotFound)));
    assert!(env.audit.lock().unwrap().iter().any(
        |e| matches!(e, AuditEvent::UserChanged { change, user, .. } if *change == "remove" && user == "olena")
    ));
    env.stop().await;
}

#[test]
fn plain_http_only_on_loopback() {
    let cfg = GatewayConfig::new(SITE, temp_dir("tls"), "0.0.0.0:0".parse().unwrap());
    assert!(Gateway::open(cfg, b"k").is_err());
}

/// `sys` Update Permissions: grants of a role change at runtime, persist,
/// apply to existing users, and never leave the gateway without an admin.
#[test]
fn role_grants_change_persist_and_keep_an_admin() {
    let dir = temp_dir("roles");
    let cfg = GatewayConfig::new(SITE, &dir, "127.0.0.1:0".parse().unwrap());
    let gw = Gateway::open(cfg.clone(), b"k").unwrap();
    gw.ensure_admin("root", ADMIN_PW).unwrap();
    gw.add_user("op", "operator pw", vec!["operator".into()])
        .unwrap();
    let key = format!("wy/{SITE}/downstream/plc1/p/~set");
    let op = || gw.grants_of(&gw.user("op").unwrap().roles);
    assert_eq!(op().perm(&key), Perm::Write);

    // narrower grant goes first, so it is not shadowed by downstream/**
    gw.set_grant("operator", "wy/{site}/downstream/plc1/**", Perm::Read)
        .unwrap();
    assert_eq!(op().perm(&key), Perm::Read);
    assert_eq!(
        op().perm(&format!("wy/{SITE}/downstream/plc2/p/~set")),
        Perm::Write
    );

    // a new role, then a user with it
    gw.set_grant("auditor", "wy/{site}/sys/audit/**", Perm::Read)
        .unwrap();
    gw.add_user("aud", "auditor pw", vec!["auditor".into()])
        .unwrap();

    // lockout: the only admin's grant cannot go
    assert!(gw.set_grant("admin", "wy/**", Perm::Write).is_err());
    assert!(gw.set_grant("admin", "wy/**", Perm::None).is_err());
    assert!(gw.set_grant("operator", "nope/**", Perm::Read).is_err());
    assert!(gw.set_grant("bad role", "wy/**", Perm::Read).is_err());

    // persisted
    drop(gw);
    let gw = Gateway::open(cfg, b"k").unwrap();
    let t = gw.role_table();
    assert_eq!(
        t.get("operator").unwrap()[0],
        ("wy/{site}/downstream/plc1/**".to_string(), Perm::Read)
    );
    assert!(t.contains("auditor"));
    // removing it brings the default back
    gw.set_grant("operator", "wy/{site}/downstream/plc1/**", Perm::None)
        .unwrap();
    assert_eq!(
        gw.role_table().get("operator"),
        RoleTable::default().get("operator")
    );
}

/// A link with one action that takes a file (`editor: file`).
struct Upload;

/// Result of `big`: past the 64 KiB cap on frames the gateway reads.
const BIG: usize = 100 * 1024;

impl wyrm_link_sdk::Link for Upload {
    const NAME: &'static str = "upload";
    const VERSION: &'static str = "0";
    type Config = ();

    async fn start(_: (), ctx: wyrm_link_sdk::LinkCtx) -> wyrm_link_sdk::Result<Self> {
        use wyrm_core::meta::{ActionResult, ParamMeta, EDITOR_FILE};
        use wyrm_core::{ActionMeta, TypeCode};
        ctx.declare_action(
            "",
            "put",
            ActionMeta::new()
                .param(
                    "data",
                    ParamMeta::of(TypeCode::Binary)
                        .editor(EDITOR_FILE)
                        .required(true),
                )
                .result(ActionResult::Type(TypeCode::Number))
                .level(Perm::Write),
        )
        .await?;
        // a result larger than an incoming frame may be (an export)
        ctx.declare_action(
            "",
            "big",
            ActionMeta::new()
                .result(ActionResult::Type(TypeCode::String))
                .level(Perm::Write),
        )
        .await?;
        // longer than the 10 s default wait; declares its own
        ctx.declare_action(
            "",
            "slow",
            ActionMeta::new()
                .result(ActionResult::Type(TypeCode::String))
                .timeout_ms(20_000)
                .level(Perm::Write),
        )
        .await?;
        Ok(Upload)
    }

    async fn on_invoke(
        &mut self,
        _path: &str,
        action: &str,
        args: Value,
        _who: &wyrm_link_sdk::Caller,
        out: wyrm_link_sdk::ReplySink,
    ) -> wyrm_link_sdk::Result<()> {
        if action == "slow" {
            tokio::time::sleep(Duration::from_secs(11)).await;
            return out.reply(Value::from("done")).await;
        }
        if action == "big" {
            return out.reply(Value::Str("x".repeat(BIG))).await;
        }
        let n = match &args {
            Value::Map(m) => match m.get("data") {
                Some(Value::Bytes(b)) => b.len(),
                _ => 0,
            },
            _ => 0,
        };
        out.reply(Value::UInt(n as u64)).await
    }
}

/// `POST /api/invoke?key=…&action=…` (ADR 0011): file arguments larger than
/// a WebSocket frame; key, file parameter and the action's level are checked
/// before the body is read; the body's item count is bounded.
#[tokio::test(flavor = "multi_thread")]
async fn http_invoke_takes_large_arguments() {
    let env = Env::start("httpinvoke", Duration::from_secs(600)).await;
    let mut lc = LinkConfig::new(SITE, "upload");
    lc.admin_keys = vec![env.gw.verifying_key()];
    let up = wyrm_link_sdk::spawn::<Upload>(env.session.clone(), lc, ())
        .await
        .unwrap();
    let root = env.session("root", ADMIN_PW).await;
    env.gw
        .add_user("viewer1", "viewer pw 1", vec!["viewer".into()])
        .unwrap();
    let viewer = env.session("viewer1", "viewer pw 1").await;
    let put = format!("/api/invoke?key=wy/{SITE}/downstream/upload&action=put");
    let data = |n: usize| map([("data", Value::Bytes(vec![7u8; n]))]);

    let (st, v) = env
        .http("POST", &put, Some(&root), Some(data(300 * 1024)))
        .await;
    assert_eq!(st, 200, "{v:?}");
    assert_eq!(get(&v, "result"), &Value::UInt(300 * 1024));
    // read rights pass the first check, not the action's level (write)
    let (st, _) = env.http("POST", &put, Some(&viewer), Some(data(10))).await;
    assert_eq!(st, 403);
    assert!(env
        .audit
        .lock()
        .unwrap()
        .iter()
        .any(|e| matches!(e, AuditEvent::Denied { op, .. } if op == "invoke")));
    // an action without a file parameter goes over the WebSocket
    let reset = format!("/api/invoke?key={ROOT}&action=reset");
    let (st, v) = env.http("POST", &reset, Some(&root), Some(map([]))).await;
    assert_eq!(st, 400, "{v:?}");
    // a body that would decode to a big tree is refused before decoding
    let many = map([
        ("data", Value::Bytes(vec![1])),
        ("x", Value::Array(vec![Value::UInt(1); 20_000])),
    ]);
    let (st, v) = env.http("POST", &put, Some(&root), Some(many)).await;
    assert_eq!(st, 400, "{v:?}");
    // no session
    let (st, _) = env.http("POST", &put, None, Some(data(10))).await;
    assert_eq!(st, 401);

    // the frame cap is on what the gateway reads, not on what it sends
    let mut ws = env.ws(&root).await;
    let id = ws
        .send(
            "invoke",
            &format!("wy/{SITE}/downstream/upload"),
            vec![("action", Value::from("big"))],
        )
        .await;
    let f = ws.reply(id).await;
    assert!(
        matches!(get(&f, "result"), Value::Str(s) if s.len() == BIG),
        "a large result reaches the client"
    );
    // a WebSocket invoke waits for the action's own timeout_ms (spec 05),
    // not the 10 s default
    let id = ws
        .send(
            "invoke",
            &format!("wy/{SITE}/downstream/upload"),
            vec![("action", Value::from("slow"))],
        )
        .await;
    let f = tokio::time::timeout(Duration::from_secs(30), async {
        loop {
            let m = ws.s.next().await.expect("socket open").unwrap();
            if let Message::Binary(b) = m {
                let f: Value = from_slice(&b).unwrap();
                if get(&f, "id") == &Value::UInt(id) {
                    return f;
                }
            }
        }
    })
    .await
    .expect("an answer");
    assert_eq!(get(&f, "ok"), &Value::Bool(true), "{f:?}");
    assert_eq!(get(&f, "result"), &Value::from("done"), "{f:?}");
    up.stop().await;
    env.stop().await;
}

/// When a link goes, grants that widen a role on its branch are revoked;
/// neutral and restrictive ones stay (ADR 0006).
#[test]
fn revoke_widening_keeps_restrictive_grants() {
    let cfg = GatewayConfig::new(SITE, temp_dir("revoke"), "127.0.0.1:0".parse().unwrap());
    let gw = Gateway::open(cfg, b"k").unwrap();
    gw.ensure_admin("root", ADMIN_PW).unwrap();
    let key = "wy/{site}/downstream/d1/**".to_string();
    gw.set_grant("viewer", &key, Perm::Write).unwrap(); // widens read
    gw.set_grant("operator", &key, Perm::List).unwrap(); // restricts write
    gw.set_grant("engineer", &key, Perm::Config).unwrap(); // neutral
    let gone = gw
        .revoke_widening(
            &[key.clone(), format!("wy/{SITE}/downstream/d1/**")],
            &format!("wy/{SITE}/downstream/d1/~val"),
        )
        .unwrap();
    assert_eq!(gone, vec![("viewer".to_string(), key.clone(), Perm::Write)]);
    let t = gw.role_table();
    assert!(!t.get("viewer").unwrap().iter().any(|(k, _)| *k == key));
    assert!(t
        .get("operator")
        .unwrap()
        .contains(&(key.clone(), Perm::List)));
    assert!(t.get("engineer").unwrap().contains(&(key, Perm::Config)));
}

#[test]
fn signing_key_persists() {
    let dir = temp_dir("key");
    let cfg = GatewayConfig::new(SITE, &dir, "127.0.0.1:0".parse().unwrap());
    let a = Gateway::open(cfg.clone(), b"k").unwrap().verifying_key();
    let b = Gateway::open(cfg, b"k").unwrap().verifying_key();
    assert_eq!(a, b);
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mode = std::fs::metadata(dir.join("gateway.key"))
            .unwrap()
            .permissions()
            .mode();
        assert_eq!(mode & 0o777, 0o600);
    }
}

/// One user holds at most 8 live tickets: a 9th replaces the oldest, so a
/// single user cannot fill the table for everyone.
#[tokio::test(flavor = "multi_thread")]
async fn tickets_are_capped_per_user() {
    let env = Env::start("tickets", wyrm_gateway::SESSION_TTL).await;
    let admin = env.session("root", ADMIN_PW).await;
    let mut ts = Vec::new();
    for _ in 0..9 {
        ts.push(env.ticket(&admin).await.expect("ticket"));
    }
    let ok = |t: &String| {
        let url = format!("ws://{}/api/ws?ticket={t}", env.addr);
        async move { tokio_tungstenite::connect_async(url).await.is_ok() }
    };
    let mut live = 0;
    for t in &ts {
        if ok(t).await {
            live += 1;
        }
    }
    assert_eq!(live, 8, "one ticket was evicted");
    assert!(!ok(&ts[8]).await, "spent");
    // another user still gets a ticket
    let other = env.add_user(&admin, "olha", &["viewer"]).await;
    assert!(env.ticket(&other).await.is_some());
    env.stop().await;
}

/// A flow deploy through the gateway carries the user's own per-target
/// proofs (ADR 0008): an engineer deploys; a user with `config` on flows but
/// no rights on the target device is refused.
#[tokio::test(flavor = "multi_thread")]
async fn flow_deploy_proofs_come_from_the_user() {
    let env = Env::start("dataflows", wyrm_gateway::SESSION_TTL).await;
    let dir = temp_dir("flows-engine");
    let host = wyrm_flow::FlowHost::open(&dir, b"flow-test-hmac-key", SITE).unwrap();
    let mut lc = LinkConfig::new(SITE, "dataflows");
    lc.root = Some(format!("wy/{SITE}/dataflows"));
    lc.admin_keys = vec![env.gw.verifying_key()];
    let engine = wyrm_link_sdk::spawn::<wyrm_flow::Engine>(
        env.session.clone(),
        lc,
        wyrm_flow::EngineStart {
            host,
            admin_keys: vec![env.gw.verifying_key()],
            proof_keys: Vec::new(),
        },
    )
    .await
    .unwrap();
    let def = map([
        ("id", Value::from("shed")),
        (
            "nodes",
            map([
                (
                    "a",
                    map([
                        ("type", Value::from("subscribe")),
                        ("key", Value::from("downstream/mock/g0/p0")),
                    ]),
                ),
                (
                    "cmd",
                    map([
                        ("type", Value::from("invoke")),
                        ("path", Value::from("downstream/mock")),
                        ("action", Value::from("reset")),
                    ]),
                ),
            ]),
        ),
        (
            "edges",
            Value::Array(vec![Value::Array(vec![
                Value::from("a.out"),
                Value::from("cmd.in"),
            ])]),
        ),
        ("permissions", map([("maxperm", Value::from("write"))])),
    ]);
    let flows = format!("wy/{SITE}/dataflows");
    let admin = env.session("root", ADMIN_PW).await;

    let eng = env.add_user(&admin, "eng", &["engineer"]).await;
    let mut ws = env.ws(&eng).await;
    // a forged proof from the client is replaced by the gateway's
    let r = ws
        .call(
            "invoke",
            &flows,
            vec![
                ("action", Value::from("deploy")),
                (
                    "args",
                    map([
                        ("def", def.clone()),
                        ("proofs", Value::Map(BTreeMap::new())),
                    ]),
                ),
            ],
        )
        .await;
    assert!(is_ok(&r), "engineer deploys: {r:?}");

    let fo = env.add_user(&admin, "fo", &["flows_only"]).await;
    let mut ws = env.ws(&fo).await;
    let r = ws
        .call(
            "invoke",
            &flows,
            vec![
                ("action", Value::from("deploy")),
                ("args", map([("def", def)])),
            ],
        )
        .await;
    assert_eq!(err_status(&r), Some(Status::PermissionDenied), "{r:?}");
    engine.stop().await;
    env.stop().await;
}

/// ADR 0007: a downstream site in `downstream_sites` is checked under the own
/// site's roles; a token for it names that site, the user with our site,
/// and the own-site grants rewritten to it (ADR 0018); other sites stay out
/// of reach.
#[test]
fn downstream_sites_map_to_own_roles() {
    use wyrm_client::TokenSource;
    let mut cfg = GatewayConfig::new(SITE, temp_dir("readsites"), "127.0.0.1:0".parse().unwrap());
    cfg.downstream_sites = vec!["edge".into()];
    let gw = Gateway::open(cfg, b"k").unwrap();
    assert_eq!(
        gw.downstream_site_of("wy/edge/downstream/m/p").as_deref(),
        Some("edge")
    );
    assert_eq!(gw.downstream_site_of("wy/edgex/downstream"), None);
    assert_eq!(gw.downstream_site_of("wy/other/downstream"), None);
    assert_eq!(
        gw.as_own("wy/edge/downstream/m/p"),
        format!("wy/{SITE}/downstream/m/p")
    );
    assert_eq!(gw.as_own("wy/edge"), format!("wy/{SITE}"));
    assert_eq!(gw.as_own("wy/other/downstream"), "wy/other/downstream");
    let p = wyrm_gateway::Principal {
        name: "op".into(),
        roles: vec!["admin".into()],
        grants: RoleTable::default().grants(SITE, &["admin".into()]),
        claims: wyrm_gateway::SessionClaims {
            sub: "op".into(),
            roles: vec!["admin".into()],
            exp: u64::MAX,
            iat: 0,
            jti: [0; 16],
            gen: 0,
        },
    };
    let mut p = p;
    p.grants = RoleTable::default().grants(SITE, &["operator".into()]);
    let t = gw.tokens_for(&p);
    let claims = |tok: Vec<u8>| -> wyrm_core::PtokClaims {
        let parts = wyrm_core::ptok::split(&tok).unwrap();
        from_slice(parts.claims).unwrap()
    };
    let own = claims(t.token(&format!("wy/{SITE}/downstream/m/p/~set")).unwrap());
    assert_eq!((own.site.as_str(), own.sub.as_str()), (SITE, "user:op"));
    let down = claims(t.token("wy/edge/downstream/m/p/~set").unwrap());
    assert_eq!(down.site, "edge");
    assert_eq!(down.sub, format!("user:op@{SITE}"));
    // one grant, on the key, at the level of the rewritten operator grant
    assert_eq!(down.grants.len(), 1);
    assert_eq!(
        (down.grants[0].k.as_str(), down.grants[0].p),
        ("wy/edge/downstream/m/p/~set", Perm::Write)
    );
    assert!(
        t.token("wy/edge/sys/~act/install").is_none(),
        "no operator grant on sys"
    );
    assert!(t.token(&format!("wy/{SITE}x/downstream/~meta")).is_none());
    assert!(t.token("wy/other/downstream/m/p/~set").is_none());
    // downstream brokers installed or removed at runtime change the list
    gw.set_downstream_sites(vec!["plant".into()]);
    assert_eq!(
        gw.downstream_site_of("wy/plant/downstream").as_deref(),
        Some("plant")
    );
    assert_eq!(gw.downstream_site_of("wy/edge/downstream/m/p"), None);
}

/// `history` (spec 01 `~val?history=`) needs read on the point itself:
/// a user without read on a branch gets none of its history.
#[tokio::test(flavor = "multi_thread")]
async fn history_follows_point_grants() {
    use wyrm_history::{GroupCfg, Historian, Logging, WatchCfg};
    let env = Env::start("history", wyrm_gateway::SESSION_TTL).await;
    let dir = temp_dir("history-store");
    let h = Historian::open(&dir).unwrap();
    let watch = |id: &str, key: String| WatchCfg {
        id: id.into(),
        key,
        enabled: true,
    };
    h.attach(
        env.session.clone(),
        vec![GroupCfg {
            name: "g".into(),
            logging: Logging::AllData,
            interval_ms: 1000,
            flush_ms: 100,
            watches: vec![
                watch("w1", format!("{ROOT}/g0/p0")),
                watch("w2", format!("{ROOT}/g1/p1")),
            ],
        }],
        vec![format!("{ROOT}/**/~val")],
        Some(format!("wy/{SITE}/sys/history")),
    );
    let admin = env.session("root", ADMIN_PW).await;
    let tok = env.add_user(&admin, "guest", &["limited"]).await;
    let mut ws = env.ws(&tok).await;
    let args = || vec![("args", map([("from", Value::from("2020-01-01"))]))];
    let mut rows = Vec::new();
    for _ in 0..50 {
        let r = ws.call("history", &format!("{ROOT}/g0/p0"), args()).await;
        assert!(is_ok(&r), "{r:?}");
        if let Value::Array(a) = get(&r, "result") {
            if a.len() >= 3 {
                rows = a.clone();
                break;
            }
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
    assert!(rows.len() >= 3, "rows recorded: {rows:?}");
    assert!(
        matches!(&rows[0], Value::Array(r) if r.len() == 3 && matches!(r[0], Value::UInt(_))),
        "[t, v, q]: {:?}",
        rows[0]
    );
    let agg = ws
        .call(
            "history",
            &format!("{ROOT}/g0/p0"),
            vec![(
                "args",
                map([
                    ("from", Value::from("2020-01-01")),
                    ("agg", Value::from("count")),
                ]),
            )],
        )
        .await;
    assert!(
        matches!(get(&agg, "result"), Value::Array(a) if a.len() == 1),
        "{agg:?}"
    );
    // no read on g1: refused before the query leaves the gateway
    let r = ws.call("history", &format!("{ROOT}/g1/p1"), args()).await;
    assert_eq!(err_status(&r), Some(Status::PermissionDenied));
    // bad arguments come back from the historian
    let r = ws
        .call(
            "history",
            &format!("{ROOT}/g0/p0"),
            vec![("args", map([("from", Value::from("yesterday"))]))],
        )
        .await;
    assert_eq!(err_status(&r), Some(Status::InvalidParameter), "{r:?}");

    // ADR 0020: the site lays its stores on points it records for others
    // (`sys/overlays/.sites`); here the mock stands for such points.
    let w1 = format!("wy/{SITE}/sys/history/g/w1");
    let w2 = format!("wy/{SITE}/sys/history/g/w2");
    let hist = |w: &str| map([("history", Value::Array(vec![Value::from(w)]))]);
    let put_sites = |v: Value| {
        let session = env.session.clone();
        async move {
            let payload = to_vec(&wyrm_core::Sample {
                v,
                q: wyrm_core::Quality::Good,
                t: wyrm_history::engine::now_us(),
            })
            .unwrap();
            session
                .put(format!("wy/{SITE}/sys/overlays/.sites/~val"), payload)
                .await
                .unwrap();
        }
    };
    let id = ws.send("list", &format!("{ROOT}/g0"), vec![]).await;
    assert!(is_ok(&ws.reply(id).await));
    assert_eq!(get(&ws.event(id).await, "type"), &Value::from("refreshed"));
    let sites = Value::Map(
        [
            (format!("{ROOT}/g0/p0"), hist(&w1)),
            (format!("{ROOT}/g1/p1"), hist(&w2)),
        ]
        .into(),
    );
    put_sites(sites).await;
    // the open list gets p0 again, marked, without asking
    let ev = ws.event(id).await;
    assert_eq!(get(&ev, "type"), &Value::from("changed"), "{ev:?}");
    assert_eq!(get(&ev, "name"), &Value::from("p0"));
    let Value::Bytes(b) = get(&ev, "meta") else {
        panic!("{ev:?}")
    };
    let m: wyrm_core::NodeMeta = from_slice(b).unwrap();
    assert_eq!(m.has_history, Some(true));
    assert_eq!(
        m.attr.unwrap()["history"],
        Value::Array(vec![Value::from(w1.as_str())])
    );
    // meta too
    let r = ws.call("meta", &format!("{ROOT}/g0/p0"), vec![]).await;
    let Value::Bytes(b) = get(&r, "result") else {
        panic!("{r:?}")
    };
    let m: wyrm_core::NodeMeta = from_slice(b).unwrap();
    assert_eq!(m.has_history, Some(true));
    // the store at the watch key: rights of the point it records
    let r = ws.call("history", &w1, args()).await;
    assert!(
        matches!(get(&r, "result"), Value::Array(a) if a.len() >= rows.len()),
        "{r:?}"
    );
    let r = ws.call("history", &w2, args()).await;
    assert_eq!(
        err_status(&r),
        Some(Status::PermissionDenied),
        "no read on g1"
    );
    let r = ws
        .call("history", &format!("wy/{SITE}/sys/history/g/w9"), args())
        .await;
    assert_eq!(
        err_status(&r),
        Some(Status::PermissionDenied),
        "a watch not laid on anything: as its Get History (config)"
    );
    // the overlay goes: p0 again, without the mark
    put_sites(Value::Map(BTreeMap::new())).await;
    let ev = ws.event(id).await;
    assert_eq!(get(&ev, "name"), &Value::from("p0"));
    let Value::Bytes(b) = get(&ev, "meta") else {
        panic!("{ev:?}")
    };
    let m: wyrm_core::NodeMeta = from_slice(b).unwrap();
    assert_eq!(m.has_history, None);

    h.detach().await;
    env.stop().await;
    let _ = std::fs::remove_dir_all(dir);
}

/// Security review GW-2: one user holds at most `SOCKETS_PER_USER` WebSockets; closing one
/// frees its place.
#[tokio::test(flavor = "multi_thread")]
async fn sockets_per_user_are_bounded() {
    let env = Env::start("sockets", wyrm_gateway::SESSION_TTL).await;
    let tok = env.session("root", ADMIN_PW).await;
    let mut open = Vec::new();
    for _ in 0..wyrm_gateway::SOCKETS_PER_USER {
        open.push(env.ws(&tok).await);
    }
    let t = env.ticket(&tok).await.unwrap();
    let url = format!("ws://{}/api/ws?ticket={t}", env.addr);
    assert!(
        tokio_tungstenite::connect_async(url).await.is_err(),
        "one more is refused"
    );
    drop(open.pop());
    let mut again = None;
    for _ in 0..50 {
        let t = env.ticket(&tok).await.unwrap();
        let url = format!("ws://{}/api/ws?ticket={t}", env.addr);
        if let Ok((s, _)) = tokio_tungstenite::connect_async(url).await {
            again = Some(s);
            break;
        }
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
    assert!(again.is_some(), "a closed socket frees its place");
}

/// A model that answers from a script (no network).
struct ScriptedLlm(Mutex<std::collections::VecDeque<serde_json::Value>>);

impl wyrm_link_agent::llm::LlmClient for ScriptedLlm {
    fn messages(&self, _body: serde_json::Value) -> wyrm_link_agent::llm::LlmFuture<'_> {
        let r = self
            .0
            .lock()
            .unwrap()
            .pop_front()
            .ok_or_else(|| "script exhausted".to_owned());
        Box::pin(async move { r })
    }
}

const AGENT: &str = "wy/test/downstream/agent";

/// An agent link whose model proposes: `g0/p0 := 42` (write), `g1/p1 := 7` (write) and a
/// flow deploy (config), then a proof of each point.
async fn spawn_agent(env: &Env) -> LinkHandle<wyrm_link_agent::Agent> {
    use serde_json::json;
    let propose = |id: &str, input: serde_json::Value| json!({"type": "tool_use", "id": id, "name": "propose", "input": input});
    let def = json!({"id": "shed", "nodes": {"a": {"type": "subscribe", "key": "downstream/mock/g0/p0"}}, "edges": []});
    let script = vec![
        json!({"content": [
            propose("t1", json!({"op": "set", "path": "downstream/mock/g0/p0", "value": 42.5, "reason": "asked"})),
            propose("t2", json!({"op": "set", "path": "downstream/mock/g1/p1", "value": 7, "reason": "asked"})),
            propose("t3", json!({"op": "invoke", "path": "dataflows", "action": "deploy", "args": {"def": def}, "reason": "asked"})),
            propose("t4", json!({"op": "expect", "path": "downstream/mock/g0/p0", "equals": 42.5, "timeout_s": 5})),
            propose("t5", json!({"op": "expect", "path": "downstream/mock/g1/p1", "equals": 7, "timeout_s": 5})),
        ], "stop_reason": "tool_use", "usage": {"input_tokens": 10, "output_tokens": 10}}),
        json!({"content": [{"type": "text", "text": "Plan: three steps."}], "stop_reason": "end_turn", "usage": {"input_tokens": 10, "output_tokens": 10}}),
    ];
    let mut lc = LinkConfig::new(SITE, "agent");
    lc.admin_keys = vec![env.gw.verifying_key()];
    lc.answer_val = true;
    let params = wyrm_link_agent::AgentParams {
        allowed_prefixes: vec!["downstream/mock".into(), "dataflows".into()],
        ..Default::default()
    };
    wyrm_link_sdk::spawn::<wyrm_link_agent::Agent>(
        env.session.clone(),
        lc,
        wyrm_link_agent::AgentConfig {
            params,
            llm: Some(Arc::new(ScriptedLlm(Mutex::new(script.into())))),
        },
    )
    .await
    .unwrap()
}

fn text(v: &Value, k: &str) -> String {
    match get(v, k) {
        Value::Str(s) => s.clone(),
        other => panic!("{k}: {other:?} in {v:?}"),
    }
}

fn err_message(reply: &Value) -> String {
    text(get(reply, "error"), "message")
}

fn approve_args(steps: &[u64], plan: &str) -> Vec<(&'static str, Value)> {
    vec![
        ("action", Value::from("approve")),
        (
            "args",
            map([
                (
                    "steps",
                    Value::Array(steps.iter().map(|s| Value::UInt(*s)).collect()),
                ),
                ("plan", Value::from(plan)),
            ]),
        ),
    ]
}

/// ADR 0049 §1–4 (docs/studio.md §10 items 1, 6 and 11): a user reads a task's record with
/// `doc` and approves the steps they tick; the gateway signs those steps only, within the
/// user's grants, for the plan the link stores; `write` on the task is enough to approve.
#[tokio::test(flavor = "multi_thread")]
async fn a_user_reads_a_plan_and_approves_the_ticked_steps() {
    let env = Env::start("approve", wyrm_gateway::SESSION_TTL).await;
    let dir = temp_dir("approve-flows");
    let host = wyrm_flow::FlowHost::open(&dir, b"flow-test-hmac-key", SITE).unwrap();
    let mut lc = LinkConfig::new(SITE, "dataflows");
    lc.root = Some(format!("wy/{SITE}/dataflows"));
    lc.admin_keys = vec![env.gw.verifying_key()];
    let engine = wyrm_link_sdk::spawn::<wyrm_flow::Engine>(
        env.session.clone(),
        lc,
        wyrm_flow::EngineStart {
            host,
            admin_keys: vec![env.gw.verifying_key()],
            proof_keys: Vec::new(),
        },
    )
    .await
    .unwrap();
    let agent = spawn_agent(&env).await;
    let admin = env.session("root", ADMIN_PW).await;
    let mut root = env.ws(&admin).await;

    // Ask: the stream ends with the task and its state
    let r = root
        .call(
            "invoke",
            AGENT,
            vec![
                ("action", Value::from("ask")),
                ("args", map([("task", Value::from("set two points"))])),
            ],
        )
        .await;
    assert!(is_ok(&r), "{r:?}");
    let id = text(get(&r, "result"), "task");
    assert_eq!(text(get(&r, "result"), "state"), "awaiting_approval");
    let task = format!("{AGENT}/tasks/{id}");

    // §1: the record through `doc`
    let state = vec![("suffix", Value::from("~state"))];
    let r = root.call("doc", &task, state.clone()).await;
    assert!(is_ok(&r), "{r:?}");
    let rec = get(&r, "result").clone();
    assert_eq!(text(&rec, "state"), "awaiting_approval");
    assert_eq!(text(&rec, "ask"), "set two points");
    let Value::Array(plan) = get(&rec, "plan") else {
        panic!("plan: {rec:?}")
    };
    assert_eq!(plan.len(), 5, "{plan:?}");
    // the hash a client makes from the plan it shows is the link's
    let hash = wyrm_gateway::approve::plan_hash(plan).unwrap();
    assert_eq!(text(&rec, "plan_hash"), hash);
    let (k0, k1) = (format!("{ROOT}/g0/p0/~set"), format!("{ROOT}/g1/p1/~set"));
    let k2 = format!("wy/{SITE}/dataflows/~act/deploy");
    assert_eq!(text(&plan[0], "set"), format!("{ROOT}/g0/p0"));
    assert_eq!(get(&plan[0], "value"), &Value::Float(42.5));
    assert_eq!(text(&plan[0], "level"), "write");
    assert_eq!(get(&plan[0], "approval"), &Value::Bool(true));
    assert_eq!(text(&plan[2], "invoke"), format!("wy/{SITE}/dataflows"));
    assert_eq!(text(&plan[2], "action"), "deploy");
    assert_eq!(text(&plan[2], "level"), "config");
    assert_eq!(text(&plan[3], "expect"), format!("{ROOT}/g0/p0"));

    // a closed set of documents; a node without one; a user without `list` on the node
    for bad in [None, Some("~meta"), Some("~val"), Some("state")] {
        let extra = bad.map(|s| vec![("suffix", Value::from(s))]);
        let r = root.call("doc", &task, extra.unwrap_or_default()).await;
        assert_eq!(err_status(&r), Some(Status::InvalidParameter), "{bad:?}");
    }
    let r = root
        .call("doc", &format!("{ROOT}/g0/p0"), state.clone())
        .await;
    assert_eq!(err_status(&r), Some(Status::NotSupported), "{r:?}");
    let fo = env.add_user(&admin, "fo", &["flows_only"]).await;
    let mut fo = env.ws(&fo).await;
    let r = fo.call("doc", &task, state.clone()).await;
    assert_eq!(err_status(&r), Some(Status::PermissionDenied), "{r:?}");
    let r = fo.call("invoke", &task, approve_args(&[1], &hash)).await;
    assert_eq!(err_status(&r), Some(Status::PermissionDenied), "{r:?}");

    // the client names steps of the stored plan and nothing else
    for (steps, plan_hash, want) in [
        (vec![9], hash.as_str(), "no step 9"),
        (vec![4], hash.as_str(), "sends nothing"),
        (vec![1], "0000", "read it again"),
        (vec![], hash.as_str(), "no step"),
    ] {
        let r = root
            .call("invoke", &task, approve_args(&steps, plan_hash))
            .await;
        assert_eq!(err_status(&r), Some(Status::InvalidParameter), "{r:?}");
        assert!(err_message(&r).contains(want), "{r:?}");
    }
    // a token of the client's own making goes to the link as it is, and the link refuses it
    let forged = vec![
        ("action", Value::from("approve")),
        (
            "args",
            map([
                ("steps", Value::Array(vec![Value::UInt(1)])),
                ("plan", Value::from(hash.as_str())),
                ("approvals", map([("1", Value::Bytes(vec![1; 80]))])),
            ]),
        ),
    ];
    let r = root.call("invoke", &task, forged).await;
    assert!(!is_ok(&r), "{r:?}");

    // §2: a step outside the user's grants, and a config step for a user with write:
    // refused whole before anything is sent, the step and the missing right named
    let ap = env.add_user(&admin, "ap", &["approver"]).await;
    let mut ap = env.ws(&ap).await;
    let r = ap.call("invoke", &task, approve_args(&[1, 2], &hash)).await;
    assert_eq!(err_status(&r), Some(Status::PermissionDenied), "{r:?}");
    assert_eq!(
        err_message(&r),
        format!("step 2 needs write on {k1}; you have read")
    );
    let r = ap.call("invoke", &task, approve_args(&[1, 3], &hash)).await;
    assert_eq!(err_status(&r), Some(Status::PermissionDenied), "{r:?}");
    assert_eq!(
        err_message(&r),
        format!("step 3 needs config on {k2}; you have write")
    );
    assert!(env.audit.lock().unwrap().iter().any(
        |e| matches!(e, AuditEvent::Denied { op, user, .. } if op == "approve" && user == "ap")
    ));
    let r = ap.call("doc", &task, state.clone()).await;
    assert_eq!(text(get(&r, "result"), "state"), "awaiting_approval");
    let p0 = || {
        let v = env.link.as_ref().unwrap().ctx().last("g0/p0").unwrap().v;
        v.as_f64().unwrap()
    };
    assert_ne!(p0(), 42.5);

    // §3 and §4: `write` on the task is enough; the one ticked step runs with the user's
    // rights, the others are skipped, and so is the proof that needs one of them
    let r = ap.call("invoke", &task, approve_args(&[1], &hash)).await;
    assert!(is_ok(&r), "{r:?}");
    assert_eq!(text(get(&r, "result"), "state"), "running");
    let mut rec = Value::Null;
    for _ in 0..400 {
        let r = ap.call("doc", &task, state.clone()).await;
        rec = get(&r, "result").clone();
        if text(&rec, "state") != "running" {
            break;
        }
        tokio::time::sleep(Duration::from_millis(25)).await;
    }
    assert_eq!(text(&rec, "state"), "done", "{rec:?}");
    assert_eq!(p0(), 42.5);
    let Value::Array(plan) = get(&rec, "plan") else {
        panic!("plan: {rec:?}")
    };
    let result = |i: usize| {
        let r = get(&plan[i], "result");
        (text(r, "status"), text(r, "message"))
    };
    assert_eq!(result(0).0, "ok");
    assert_eq!(result(1), ("skipped".into(), "skipped by user:ap".into()));
    assert_eq!(result(2), ("skipped".into(), "skipped by user:ap".into()));
    assert_eq!(result(3).0, "ok", "the proof of step 1: {:?}", result(3));
    assert_eq!(
        result(4),
        ("skipped".into(), "skipped: needs step 2".into())
    );
    let Value::Array(log) = get(&rec, "log") else {
        panic!("log: {rec:?}")
    };
    assert!(
        log.iter()
            .any(|l| matches!(l, Value::Str(s) if s.contains("approved by user:ap"))),
        "{log:?}"
    );
    assert!(env.audit.lock().unwrap().iter().any(|e| matches!(
        e,
        AuditEvent::Approved { user, steps, skipped, .. }
            if user == "ap" && steps == std::slice::from_ref(&k0) && *skipped == 2
    )));
    // a second approve finds a task that no longer waits
    let r = ap.call("invoke", &task, approve_args(&[1], &hash)).await;
    assert_eq!(err_status(&r), Some(Status::InvalidParameter), "{r:?}");

    agent.stop().await;
    engine.stop().await;
    env.stop().await;
}

/// ADR 0049 rule 5: an approval is a token for exactly one request key, capped at the level
/// the step needs, bound to its request body, short-lived, the user as its subject.
#[test]
fn an_approval_token_is_for_one_step_and_one_body() {
    let mut cfg = GatewayConfig::new(
        SITE,
        temp_dir("approval-token"),
        "127.0.0.1:0".parse().unwrap(),
    );
    cfg.downstream_sites = vec!["edge".into()];
    let gw = Gateway::open(cfg, b"k").unwrap();
    let p = wyrm_gateway::Principal {
        name: "eng".into(),
        roles: vec!["engineer".into()],
        grants: RoleTable::default().grants(SITE, &["engineer".into()]),
        claims: wyrm_gateway::SessionClaims {
            sub: "eng".into(),
            roles: vec!["engineer".into()],
            exp: u64::MAX,
            iat: 0,
            jti: [0; 16],
            gen: 0,
        },
    };
    let claims = |tok: Vec<u8>| -> wyrm_core::PtokClaims {
        let parts = wyrm_core::ptok::split(&tok).unwrap();
        from_slice(parts.claims).unwrap()
    };
    let t = gw.tokens_for(&p);
    let key = format!("wy/{SITE}/downstream/m/p/~set");
    let a = claims(t.approval(&key, Perm::Write, [7; 32]).unwrap());
    assert_eq!(a.sub, "user:eng");
    assert_eq!(a.site, SITE);
    assert_eq!(a.grants.len(), 1);
    assert_eq!(a.grants[0].k, key);
    // an engineer has config there; the approval carries the step's level and no more
    assert_eq!(a.max, Perm::Write);
    assert_eq!(a.args, Some([7; 32]));
    assert_eq!(a.auth, None, "a `~set` token names no further rights");
    assert_eq!(a.exp - a.iat, wyrm_gateway::approve::APPROVAL_TTL.as_secs());
    let b = claims(t.approval(&key, Perm::Write, [7; 32]).unwrap());
    assert_ne!(a.jti, b.jti, "single use: a new jti each");
    // a site below: its own name, the user with ours
    let d = claims(
        t.approval("wy/edge/downstream/m/p/~act/go", Perm::Config, [1; 32])
            .unwrap(),
    );
    assert_eq!((d.site.as_str(), d.max), ("edge", Perm::Config));
    assert_eq!(d.sub, format!("user:eng@{SITE}"));
    assert_eq!(d.grants[0].k, "wy/edge/downstream/m/p/~act/go");
    // out of the user's grants or out of reach: no token at all
    assert!(t
        .approval(&format!("wy/{SITE}/sys/~act/x"), Perm::Config, [0; 32])
        .is_none());
    assert!(t
        .approval("wy/other/downstream/m/p/~set", Perm::Write, [0; 32])
        .is_none());
    // a viewer: the token cannot give more than the user's own level
    let mut v = p.clone();
    v.grants = RoleTable::default().grants(SITE, &["viewer".into()]);
    let c = claims(
        gw.tokens_for(&v)
            .approval(&key, Perm::Config, [0; 32])
            .unwrap(),
    );
    assert_eq!(c.grants[0].p.min(c.max), Perm::Read);
}
