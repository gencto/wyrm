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

const ROOT: &str = "wy/test/down/mock";
const ADMIN_PW: &str = "admin password";

fn temp_dir(name: &str) -> PathBuf {
    let d = std::env::temp_dir().join(format!("wyrm-gateway-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&d);
    d
}

struct Env {
    _gw: Arc<Gateway>,
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
                ("wy/{site}/down/mock/g1/**".into(), Perm::None),
                ("wy/{site}/down/**".into(), Perm::Read),
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
        tokio::spawn(gw.clone().serve(session, async {
            let _ = rx.await;
        }));
        let addr = tokio::time::timeout(Duration::from_secs(5), gw.local_addr())
            .await
            .unwrap();
        Self {
            _gw: gw,
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
        let mut s = TcpStream::connect(self.addr).await.unwrap();
        s.write_all(req.as_bytes()).await.unwrap();
        s.write_all(&body).await.unwrap();
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

    async fn ws(&self, token: &str) -> Ws {
        let url = format!("ws://{}/api/ws?session={token}", self.addr);
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
    assert!(audit
        .iter()
        .any(|e| matches!(e, AuditEvent::LoginFailed { reason, .. } if *reason == "rate_limited")));
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
    let r = ws.call("meta", "wy/other/down/mock", vec![]).await;
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
    let url = format!("ws://{}/api/ws?session={bad}", env.addr);
    assert!(tokio_tungstenite::connect_async(url).await.is_err());

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
    let url = format!("ws://{}/api/ws?session={tok}", env.addr);
    assert!(tokio_tungstenite::connect_async(url).await.is_err());
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
