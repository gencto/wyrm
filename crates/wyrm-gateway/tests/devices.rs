//! Device keys, the step-up and `/api/info` (ADR 0050) end to end: a gateway on an isolated
//! Zenoh session, raw HTTP/1.1, keys made with ring as a device's secure hardware would.

use futures_util::{SinkExt, StreamExt};
use ring::rand::SystemRandom;
use ring::signature::{EcdsaKeyPair, KeyPair, RsaKeyPair, ECDSA_P256_SHA256_ASN1_SIGNING};
use std::collections::BTreeMap;
use std::net::SocketAddr;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use tokio::sync::oneshot;
use tokio_tungstenite::tungstenite::Message;
use wyrm_core::codec::{from_slice, to_vec};
use wyrm_core::{Perm, Status, Value};
use wyrm_gateway::devices::{confirm_message, login_message, register_message};
use wyrm_gateway::{AuditEvent, DevicePolicy, Gateway, GatewayConfig, InfoConfig, StepUp};
use wyrm_link_sdk::harness::{isolated_config, SITE};
use wyrm_link_sdk::{LinkConfig, LinkHandle};

const ADMIN_PW: &str = "admin password";
const USER_PW: &str = "user password";

fn temp_dir(name: &str) -> PathBuf {
    let d = std::env::temp_dir().join(format!("wyrm-gw-dev-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&d);
    d
}

/// A link with one action at `config` and one at `read`.
struct Plant;

impl wyrm_link_sdk::Link for Plant {
    const NAME: &'static str = "plant";
    const VERSION: &'static str = "0";
    type Config = ();

    async fn start(_: (), ctx: wyrm_link_sdk::LinkCtx) -> wyrm_link_sdk::Result<Self> {
        use wyrm_core::meta::ActionResult;
        use wyrm_core::{ActionMeta, TypeCode};
        for (name, level) in [("wipe", Perm::Config), ("look", Perm::Read)] {
            ctx.declare_action(
                "",
                name,
                ActionMeta::new()
                    .result(ActionResult::Type(TypeCode::String))
                    .level(level),
            )
            .await?;
        }
        Ok(Plant)
    }

    async fn on_invoke(
        &mut self,
        _path: &str,
        action: &str,
        _args: Value,
        _who: &wyrm_link_sdk::Caller,
        out: wyrm_link_sdk::ReplySink,
    ) -> wyrm_link_sdk::Result<()> {
        out.reply(Value::from(action)).await
    }
}

struct Env {
    gw: Arc<Gateway>,
    addr: SocketAddr,
    session: zenoh::Session,
    link: Option<LinkHandle<Plant>>,
    stop: Option<oneshot::Sender<()>>,
    audit: Arc<Mutex<Vec<AuditEvent>>>,
}

impl Env {
    async fn start(dir: &Path, policy: DevicePolicy, info: InfoConfig) -> Self {
        let mut cfg = GatewayConfig::new(SITE, dir, "127.0.0.1:0".parse().unwrap());
        cfg.devices = policy;
        cfg.info = info;
        let gw = Gateway::open(cfg, b"test state key").unwrap();
        let audit = Arc::new(Mutex::new(Vec::new()));
        let sink = audit.clone();
        gw.set_audit(move |e| sink.lock().unwrap().push(e));
        gw.ensure_admin("root", ADMIN_PW).unwrap();
        let session = zenoh::open(isolated_config()).await.unwrap();
        let mut lc = LinkConfig::new(SITE, "plant");
        lc.admin_keys = vec![gw.verifying_key()];
        let link = wyrm_link_sdk::spawn::<Plant>(session.clone(), lc, ())
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
            addr,
            session,
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
        let _ = self.session.close().await;
        // the store's lock goes with the gateway
        let gw = self.gw;
        for _ in 0..100 {
            if Arc::strong_count(&gw) == 1 {
                break;
            }
            tokio::time::sleep(Duration::from_millis(20)).await;
        }
    }

    fn origin(&self) -> String {
        format!("http://127.0.0.1:{}", self.addr.port())
    }

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

    async fn post(&self, path: &str, token: Option<&str>, body: Value) -> (u16, Value) {
        self.http("POST", path, token, Some(body)).await
    }

    async fn login(&self, user: &str, password: &str, device: Option<&str>) -> (u16, Value) {
        let mut m = vec![
            ("user", Value::from(user)),
            ("password", Value::from(password)),
        ];
        if let Some(d) = device {
            m.push(("device", Value::from(d)));
        }
        self.post("/api/login", None, obj(m)).await
    }

    async fn session(&self, user: &str, password: &str) -> String {
        let (st, v) = self.login(user, password, None).await;
        assert_eq!(st, 200, "login {user}: {v:?}");
        text(&v, "session")
    }

    async fn add_user(&self, admin: &str, name: &str, roles: &[&str]) {
        let (st, v) = self
            .post(
                "/api/users",
                Some(admin),
                obj(vec![
                    ("name", Value::from(name)),
                    ("password", Value::from(USER_PW)),
                    (
                        "roles",
                        Value::Array(roles.iter().map(|r| Value::from(*r)).collect()),
                    ),
                ]),
            )
            .await;
        assert_eq!(st, 200, "add {name}: {v:?}");
    }

    /// A nonce: for a login of `device`, or with a session for `purpose`.
    async fn challenge(&self, device: Option<&str>, session: Option<(&str, &str)>) -> Vec<u8> {
        let body = match (device, session) {
            (Some(d), _) => obj(vec![("device", Value::from(d))]),
            (None, Some((_, purpose))) => obj(vec![("purpose", Value::from(purpose))]),
            _ => panic!("device or session"),
        };
        let (st, v) = self
            .post("/api/device/challenge", session.map(|s| s.0), body)
            .await;
        assert_eq!(st, 200, "challenge: {v:?}");
        bytes(&v, "nonce")
    }

    /// Register `key` for the session's user; `(status, body)`.
    async fn register(&self, session: &str, key: &Key, name: &str) -> (u16, Value) {
        let nonce = self.challenge(None, Some((session, "register"))).await;
        let user = self.whoami(session).await;
        let pk = key.public();
        let sig = key.sign(&register_message(SITE, &self.origin(), &user, &nonce, &pk));
        self.post(
            "/api/devices",
            Some(session),
            obj(vec![
                ("name", Value::from(name)),
                ("platform", Value::from(key.platform())),
                ("alg", Value::from(key.alg())),
                ("public_key", Value::Bytes(pk)),
                ("origin", Value::from(self.origin())),
                ("nonce", Value::Bytes(nonce)),
                ("signature", Value::Bytes(sig)),
            ]),
        )
        .await
    }

    async fn register_ok(&self, session: &str, key: &Key) -> String {
        let (st, v) = self.register(session, key, "Olena's Mac").await;
        assert_eq!(st, 200, "register: {v:?}");
        text(&v, "device")
    }

    async fn whoami(&self, session: &str) -> String {
        let (st, v) = self.http("GET", "/api/me", Some(session), None).await;
        assert_eq!(st, 200, "me: {v:?}");
        text(&v, "sub")
    }

    /// A device login signed by `key` for `user`, with `origin` and an optional kept session.
    async fn device_login_as(
        &self,
        key: &Key,
        device: &str,
        user: &str,
        origin: &str,
        keep: Option<&str>,
    ) -> (u16, Value) {
        let nonce = self.challenge(Some(device), None).await;
        let sig = key.sign(&login_message(SITE, origin, user, device, &nonce));
        self.login_with(device, origin, &nonce, &sig, keep).await
    }

    async fn login_with(
        &self,
        device: &str,
        origin: &str,
        nonce: &[u8],
        sig: &[u8],
        keep: Option<&str>,
    ) -> (u16, Value) {
        let mut m = vec![
            ("device", Value::from(device)),
            ("origin", Value::from(origin)),
            ("nonce", Value::Bytes(nonce.to_vec())),
            ("signature", Value::Bytes(sig.to_vec())),
        ];
        if let Some(s) = keep {
            m.push(("session", Value::from(s)));
        }
        self.post("/api/device/login", None, obj(m)).await
    }

    async fn device_login(&self, key: &Key, device: &str, user: &str) -> (u16, Value) {
        self.device_login_as(key, device, user, &self.origin(), None)
            .await
    }

    async fn ws(&self, session: &str) -> Ws {
        let (st, v) = self
            .http("POST", "/api/ws-ticket", Some(session), None)
            .await;
        assert_eq!(st, 200, "ticket: {v:?}");
        let url = format!("ws://{}/api/ws?ticket={}", self.addr, text(&v, "ticket"));
        let (s, _) = tokio_tungstenite::connect_async(url).await.unwrap();
        Ws { s, next_id: 1 }
    }

    fn audit(&self) -> Vec<AuditEvent> {
        self.audit.lock().unwrap().clone()
    }
}

type WsStream = tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<TcpStream>>;

struct Ws {
    s: WsStream,
    next_id: u64,
}

impl Ws {
    async fn invoke(&mut self, key: &str, action: &str) -> Value {
        let id = self.next_id;
        self.next_id += 1;
        let m: BTreeMap<String, Value> = BTreeMap::from([
            ("id".to_owned(), Value::UInt(id)),
            ("op".to_owned(), Value::from("invoke")),
            ("key".to_owned(), Value::from(key)),
            ("action".to_owned(), Value::from(action)),
        ]);
        self.s
            .send(Message::Binary(to_vec(&Value::Map(m)).unwrap().into()))
            .await
            .unwrap();
        loop {
            let m = tokio::time::timeout(Duration::from_secs(10), self.s.next())
                .await
                .expect("frame in time")
                .expect("socket open")
                .unwrap();
            if let Message::Binary(b) = m {
                let f: Value = from_slice(&b).unwrap();
                if get(&f, "id") == &Value::UInt(id) && has(&f, "ok") {
                    return f;
                }
            }
        }
    }
}

/// A device key as the secure hardware holds it.
enum Key {
    P256(Box<EcdsaKeyPair>),
    Rsa(Box<RsaKeyPair>),
}

impl Key {
    fn p256() -> Self {
        let rng = SystemRandom::new();
        let pkcs8 = EcdsaKeyPair::generate_pkcs8(&ECDSA_P256_SHA256_ASN1_SIGNING, &rng).unwrap();
        Key::P256(Box::new(
            EcdsaKeyPair::from_pkcs8(&ECDSA_P256_SHA256_ASN1_SIGNING, pkcs8.as_ref(), &rng)
                .unwrap(),
        ))
    }

    /// The RSA-2048 key a Windows Hello `KeyCredential` would be (a fixed test key).
    fn rsa() -> Self {
        let der = std::fs::read(
            Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/test-rsa2048.der"),
        )
        .unwrap();
        Key::Rsa(Box::new(RsaKeyPair::from_der(&der).unwrap()))
    }

    fn public(&self) -> Vec<u8> {
        match self {
            Key::P256(k) => k.public_key().as_ref().to_vec(),
            Key::Rsa(k) => k.public().as_ref().to_vec(),
        }
    }

    fn alg(&self) -> &'static str {
        match self {
            Key::P256(_) => "es256",
            Key::Rsa(_) => "rs256",
        }
    }

    fn platform(&self) -> &'static str {
        match self {
            Key::P256(_) => "macos",
            Key::Rsa(_) => "windows",
        }
    }

    fn sign(&self, msg: &[u8]) -> Vec<u8> {
        let rng = SystemRandom::new();
        match self {
            Key::P256(k) => k.sign(&rng, msg).unwrap().as_ref().to_vec(),
            Key::Rsa(k) => {
                let mut sig = vec![0; k.public().modulus_len()];
                k.sign(&ring::signature::RSA_PKCS1_SHA256, &rng, msg, &mut sig)
                    .unwrap();
                sig
            }
        }
    }
}

fn obj(f: Vec<(&str, Value)>) -> Value {
    Value::Map(f.into_iter().map(|(k, v)| (k.to_owned(), v)).collect())
}

fn get<'a>(v: &'a Value, k: &str) -> &'a Value {
    match v {
        Value::Map(m) => m.get(k).unwrap_or(&Value::Null),
        _ => &Value::Null,
    }
}

fn has(v: &Value, k: &str) -> bool {
    matches!(v, Value::Map(m) if m.contains_key(k))
}

fn text(v: &Value, k: &str) -> String {
    match get(v, k) {
        Value::Str(s) => s.clone(),
        o => panic!("{k}: {o:?} in {v:?}"),
    }
}

fn bytes(v: &Value, k: &str) -> Vec<u8> {
    match get(v, k) {
        Value::Bytes(b) => b.clone(),
        o => panic!("{k}: {o:?} in {v:?}"),
    }
}

fn code(v: &Value) -> Option<String> {
    match get(v, "code") {
        Value::Str(s) => Some(s.clone()),
        _ => None,
    }
}

fn status(v: &Value) -> Option<Status> {
    match get(v, "status") {
        Value::UInt(c) => Status::try_from(*c as u8).ok(),
        _ => None,
    }
}

async fn start(name: &str, policy: DevicePolicy) -> (Env, PathBuf) {
    let dir = temp_dir(name);
    (Env::start(&dir, policy, InfoConfig::default()).await, dir)
}

/// Consequences: register and log in with a device key (ES256 and RS256); the session is
/// the user's own, with the roles of a password login; `/api/devices` lists it.
#[tokio::test(flavor = "multi_thread")]
async fn a_device_registers_and_logs_in() {
    let (env, _) = start("register", DevicePolicy::default()).await;
    let admin = env.session("root", ADMIN_PW).await;
    env.add_user(&admin, "olena", &["operator"]).await;
    let pw = env.session("olena", USER_PW).await;
    for key in [Key::p256(), Key::rsa()] {
        let id = env.register_ok(&pw, &key).await;
        let (st, v) = env.device_login(&key, &id, "olena").await;
        assert_eq!(st, 200, "{} login: {v:?}", key.alg());
        let s = text(&v, "session");
        let (st, me) = env.http("GET", "/api/me", Some(&s), None).await;
        assert_eq!(st, 200);
        assert_eq!(text(&me, "sub"), "olena");
        assert_eq!(
            get(&me, "roles"),
            &Value::Array(vec![Value::from("operator")])
        );
        // the list marks the device of the session
        let (_, list) = env.http("GET", "/api/devices", Some(&s), None).await;
        let Value::Array(rows) = &list else {
            panic!("{list:?}")
        };
        let row = rows.iter().find(|r| text(r, "id") == id).unwrap();
        assert_eq!(get(row, "this"), &Value::Bool(true));
        assert_eq!(text(row, "state"), "active");
        assert_eq!(text(row, "alg"), key.alg());
    }
    // an admin sees the user's devices, and the count in the user list
    let (st, list) = env
        .http("GET", "/api/users/olena/devices", Some(&admin), None)
        .await;
    assert_eq!(st, 200);
    assert!(matches!(&list, Value::Array(a) if a.len() == 2));
    let (_, users) = env.http("GET", "/api/users", Some(&admin), None).await;
    let Value::Array(users) = users else { panic!() };
    let o = users.iter().find(|u| text(u, "name") == "olena").unwrap();
    assert_eq!(get(o, "devices"), &Value::UInt(2));
    // no secret in the audit: names and ids only
    let a = env.audit();
    assert!(a
        .iter()
        .any(|e| matches!(e, AuditEvent::DeviceAdded { user, .. } if user == "olena")));
    assert!(a
        .iter()
        .any(|e| matches!(e, AuditEvent::DeviceLogin { user, .. } if user == "olena")));
    let dump = format!("{a:?}");
    assert!(!dump.contains(USER_PW) && !dump.contains("signature"));
    env.stop().await;
}

/// Consequences: every refusal code (`device_removed`, `password_changed`, `password_due`,
/// `devices_off`), each after a good signature; and a removed device's sessions end.
#[tokio::test(flavor = "multi_thread")]
async fn every_refusal_code() {
    let (env, dir) = start("codes", DevicePolicy::default()).await;
    let admin = env.session("root", ADMIN_PW).await;
    env.add_user(&admin, "olena", &["operator"]).await;
    let pw = env.session("olena", USER_PW).await;

    // device_removed: an admin removes it; its session ends with it
    let key = Key::p256();
    let id = env.register_ok(&pw, &key).await;
    let (_, v) = env.device_login(&key, &id, "olena").await;
    let dev_session = text(&v, "session");
    let (st, v) = env
        .http("DELETE", &format!("/api/devices/{id}"), Some(&admin), None)
        .await;
    assert_eq!(st, 200, "{v:?}");
    let (st, v) = env.device_login(&key, &id, "olena").await;
    assert_eq!((st, code(&v).as_deref()), (403, Some("device_removed")));
    assert_eq!(status(&v), Some(Status::PermissionDenied));
    let (st, _) = env.http("GET", "/api/me", Some(&dev_session), None).await;
    assert_eq!(st, 401, "the removed device's session ended");
    let (_, list) = env.http("GET", "/api/devices", Some(&pw), None).await;
    let Value::Array(rows) = &list else { panic!() };
    let row = rows.iter().find(|r| text(r, "id") == id).unwrap();
    assert_eq!(text(row, "state"), "removed");
    assert_eq!(text(row, "removed_by"), "user:root");
    // Forget: the owner deletes the tombstone; then the id is unknown (bare)
    let (st, _) = env
        .http("DELETE", &format!("/api/devices/{id}"), Some(&pw), None)
        .await;
    assert_eq!(st, 200);
    let (st, v) = env.device_login(&key, &id, "olena").await;
    assert_eq!((st, code(&v)), (401, None));

    // password_due: the policy asks for the password every 0 days (a restart on the same
    // store; only refusals are expected under it, never a login inside one second)
    let key = Key::p256();
    let id = env.register_ok(&pw, &key).await;
    env.stop().await;
    let due = DevicePolicy {
        password_every_days: 0,
        ..DevicePolicy::default()
    };
    let env = Env::start(&dir, due, InfoConfig::default()).await;
    let pw = env.session("olena", USER_PW).await;
    tokio::time::sleep(Duration::from_millis(1100)).await;
    let (st, v) = env.device_login(&key, &id, "olena").await;
    assert_eq!((st, code(&v).as_deref()), (403, Some("password_due")));
    // a password login on that device starts the interval again (`password_at` moves;
    // with an interval of 0 days the next second makes it due again, so no login here)
    let password_at = |list: &Value| match list {
        Value::Array(rows) => rows
            .iter()
            .find(|r| text(r, "id") == id)
            .map(|r| get(r, "password_at").clone()),
        _ => None,
    };
    let (_, before) = env.http("GET", "/api/devices", Some(&pw), None).await;
    let (st, _) = env.login("olena", USER_PW, Some(&id)).await;
    assert_eq!(st, 200);
    let (_, after) = env.http("GET", "/api/devices", Some(&pw), None).await;
    match (password_at(&before), password_at(&after)) {
        (Some(Value::UInt(b)), Some(Value::UInt(a))) => assert!(a > b, "{b} → {a}"),
        o => panic!("{o:?}"),
    }
    env.stop().await;

    // devices_off: the records stay, the logins are refused
    let off = DevicePolicy {
        enabled: false,
        ..DevicePolicy::default()
    };
    let env = Env::start(&dir, off, InfoConfig::default()).await;
    let (st, v) = env.device_login(&key, &id, "olena").await;
    assert_eq!((st, code(&v).as_deref()), (403, Some("devices_off")));
    let pw = env.session("olena", USER_PW).await;
    let (st, v) = env.register(&pw, &Key::p256(), "x").await;
    assert_eq!((st, code(&v).as_deref()), (403, Some("devices_off")));
    let a = env.audit();
    assert!(a.iter().any(
        |e| matches!(e, AuditEvent::DeviceRefused { code: "devices_off", user: Some(u), .. } if u == "olena")
    ));
    env.stop().await;
}

/// Consequences: a password change signs every device out (`password_changed`), and so
/// does Sign out everywhere.
#[tokio::test(flavor = "multi_thread")]
async fn a_password_change_signs_devices_out() {
    let (env, _) = start("pwchange", DevicePolicy::default()).await;
    let admin = env.session("root", ADMIN_PW).await;
    env.add_user(&admin, "olena", &["operator"]).await;
    let pw = env.session("olena", USER_PW).await;
    let key = Key::p256();
    let id = env.register_ok(&pw, &key).await;
    let (_, v) = env.device_login(&key, &id, "olena").await;
    let dev_session = text(&v, "session");
    let (st, _) = env
        .post(
            "/api/users/olena/password",
            Some(&admin),
            obj(vec![("password", Value::from("a new password"))]),
        )
        .await;
    assert_eq!(st, 200);
    let (st, v) = env.device_login(&key, &id, "olena").await;
    assert_eq!((st, code(&v).as_deref()), (403, Some("password_changed")));
    let (st, _) = env.http("GET", "/api/me", Some(&dev_session), None).await;
    assert_eq!(st, 401);
    // registered again after the new password, then Sign out everywhere
    let pw = env.session("olena", "a new password").await;
    let key = Key::p256();
    let id = env.register_ok(&pw, &key).await;
    assert_eq!(env.device_login(&key, &id, "olena").await.0, 200);
    let (st, _) = env
        .post("/api/me/sign-out", Some(&pw), Value::Map(BTreeMap::new()))
        .await;
    assert_eq!(st, 200);
    let (st, _) = env.http("GET", "/api/me", Some(&pw), None).await;
    assert_eq!(st, 401, "every session ends");
    let (st, v) = env.device_login(&key, &id, "olena").await;
    assert_eq!((st, code(&v).as_deref()), (403, Some("password_changed")));
    env.stop().await;
}

/// Consequences: challenge reuse refused; negatives: an expired-or-unknown nonce, a wrong
/// signature, another user's name, a nonce of another device, a foreign origin, and the
/// rate limit. All bare (no code), counted by the login limiter.
#[tokio::test(flavor = "multi_thread")]
async fn replays_and_forgeries_are_refused() {
    let (env, _) = start("negatives", DevicePolicy::default()).await;
    let admin = env.session("root", ADMIN_PW).await;
    env.add_user(&admin, "olena", &["operator"]).await;
    env.add_user(&admin, "taras", &["viewer"]).await;
    let pw = env.session("olena", USER_PW).await;
    let key = Key::p256();
    let id = env.register_ok(&pw, &key).await;
    let origin = env.origin();

    // a nonce for an unknown device looks like one for a known device (security review of
    // PR 86, item 2), and nonces anyone asks for the device do not replace the one held
    let held = env.challenge(Some(&id), None).await;
    let unknown = env
        .challenge(Some("0123456789abcdef0123456789abcdef"), None)
        .await;
    assert_eq!(held.len(), unknown.len());
    for _ in 0..8 {
        env.challenge(Some(&id), None).await;
    }
    let sig = key.sign(&login_message(SITE, &origin, "olena", &id, &held));
    assert_eq!(env.login_with(&id, &origin, &held, &sig, None).await.0, 200);

    // a nonce is single use: the same signed login again is refused
    let nonce = env.challenge(Some(&id), None).await;
    let sig = key.sign(&login_message(SITE, &origin, "olena", &id, &nonce));
    assert_eq!(
        env.login_with(&id, &origin, &nonce, &sig, None).await.0,
        200
    );
    let (st, v) = env.login_with(&id, &origin, &nonce, &sig, None).await;
    assert_eq!((st, code(&v)), (401, None), "replayed challenge");

    // a nonce the gateway never gave (or one that expired: gone the same way)
    let fake = [9u8; wyrm_gateway::devices::NONCE_LEN];
    let sig = key.sign(&login_message(SITE, &origin, "olena", &id, &fake));
    assert_eq!(env.login_with(&id, &origin, &fake, &sig, None).await.0, 401);
    // a signature by another key
    let other = Key::p256();
    let (st, _) = env.device_login(&other, &id, "olena").await;
    assert_eq!(st, 401, "wrong signature");
    // the device's key signing as another user
    let (st, _) = env.device_login(&key, &id, "taras").await;
    assert_eq!(st, 401, "wrong user");
    // (four failures on `id` so far: the limit is five per device and address)
    // the nonce of another device
    let k3 = Key::p256();
    let id3 = env.register_ok(&pw, &k3).await;
    let id2 = env.register_ok(&pw, &other).await;
    let nonce = env.challenge(Some(&id2), None).await;
    let sig = k3.sign(&login_message(SITE, &origin, "olena", &id3, &nonce));
    assert_eq!(
        env.login_with(&id3, &origin, &nonce, &sig, None).await.0,
        401
    );
    // signed for an origin this gateway does not serve (a relay)
    let (st, _) = env
        .device_login_as(&k3, &id3, "olena", "https://evil.example", None)
        .await;
    assert_eq!(st, 401, "foreign origin");
    // a session of a device cannot register another one (no fresh password)
    let (_, v) = env.device_login(&key, &id, "olena").await;
    let dev = text(&v, "session");
    let (st, v) = env.register(&dev, &Key::p256(), "x").await;
    assert_eq!((st, code(&v).as_deref()), (403, Some("password_required")));
    // past the limit even a good login is refused for a while
    let mut limited = false;
    for _ in 0..6 {
        let (st, _) = env.device_login(&other, &id, "olena").await;
        if st == 429 {
            limited = true;
            break;
        }
    }
    assert!(limited, "rate limit");
    assert_eq!(env.device_login(&key, &id, "olena").await.0, 429);
    let a = env.audit();
    for why in ["bad_nonce", "bad_signature", "rate_limited"] {
        assert!(
            a.iter()
                .any(|e| matches!(e, AuditEvent::DeviceRefused { code, .. } if *code == why)),
            "{why} audited"
        );
    }
    env.stop().await;
}

/// A registration needs a nonce of the same session, a signature by the new key and a
/// valid key; `max_per_user` holds.
#[tokio::test(flavor = "multi_thread")]
async fn registration_proves_the_key() {
    let policy = DevicePolicy {
        max_per_user: 1,
        ..DevicePolicy::default()
    };
    let (env, _) = start("regcheck", policy).await;
    let admin = env.session("root", ADMIN_PW).await;
    env.add_user(&admin, "olena", &["operator"]).await;
    let pw = env.session("olena", USER_PW).await;
    let pw2 = env.session("olena", USER_PW).await;
    let key = Key::p256();
    // the nonce of another session of the same user
    let nonce = env.challenge(None, Some((&pw2, "register"))).await;
    let pk = key.public();
    let sig = key.sign(&register_message(SITE, &env.origin(), "olena", &nonce, &pk));
    let body = |nonce: Vec<u8>, pk: Vec<u8>, sig: Vec<u8>| {
        obj(vec![
            ("name", Value::from("Mac")),
            ("platform", Value::from("macos")),
            ("alg", Value::from("es256")),
            ("public_key", Value::Bytes(pk)),
            ("origin", Value::from(env.origin())),
            ("nonce", Value::Bytes(nonce)),
            ("signature", Value::Bytes(sig)),
        ])
    };
    let (st, _) = env
        .post("/api/devices", Some(&pw), body(nonce, pk.clone(), sig))
        .await;
    assert_eq!(st, 401, "another session's nonce");
    // a key that does not sign what it claims
    let nonce = env.challenge(None, Some((&pw, "register"))).await;
    let sig = Key::p256().sign(&register_message(SITE, &env.origin(), "olena", &nonce, &pk));
    assert_eq!(
        env.post("/api/devices", Some(&pw), body(nonce, pk.clone(), sig))
            .await
            .0,
        401
    );
    // not a key at all
    let nonce = env.challenge(None, Some((&pw, "register"))).await;
    let (st, _) = env
        .post("/api/devices", Some(&pw), body(nonce, vec![4; 10], vec![1]))
        .await;
    assert_eq!(st, 400);
    env.register_ok(&pw, &key).await;
    let (st, v) = env.register(&pw, &Key::p256(), "second").await;
    assert_eq!((st, code(&v).as_deref()), (403, Some("too_many_devices")));
    // without a session there is no register nonce
    let (st, _) = env
        .post(
            "/api/device/challenge",
            None,
            obj(vec![("purpose", Value::from("register"))]),
        )
        .await;
    assert_eq!(st, 401);
    env.stop().await;
}

/// Consequences: step-up refused, then confirmed (with the device key over HTTP and the
/// WebSocket, and with the password); a request below `config` passes; a confirm nonce of
/// another user's session is refused.
#[tokio::test(flavor = "multi_thread")]
async fn step_up_is_refused_then_confirmed() {
    let policy = DevicePolicy {
        step_up: StepUp::Config,
        fresh_s: 3,
        ..DevicePolicy::default()
    };
    let (env, _) = start("stepup", policy).await;
    let admin = env.session("root", ADMIN_PW).await;
    let key = Key::p256();
    let id = env.register_ok(&admin, &key).await;
    env.add_user(&admin, "taras", &["engineer"]).await;
    tokio::time::sleep(Duration::from_secs(4)).await;

    // HTTP: user management is config
    let add = obj(vec![
        ("name", Value::from("ivan")),
        ("password", Value::from(USER_PW)),
        ("roles", Value::Array(vec![Value::from("viewer")])),
    ]);
    let (st, v) = env.post("/api/users", Some(&admin), add.clone()).await;
    assert_eq!(
        (st, code(&v).as_deref()),
        (403, Some("confirm_required")),
        "{v:?}"
    );
    let nonce = bytes(&v, "nonce");
    let request = bytes(&v, "request");
    assert_eq!(request.len(), 32);
    // another user's session cannot spend that nonce
    let taras = env.session("taras", USER_PW).await;
    let tkey = Key::p256();
    let tid = env.register_ok(&taras, &tkey).await;
    let sig = tkey.sign(&confirm_message(
        SITE,
        &env.origin(),
        "taras",
        &tid,
        &nonce,
        &request,
    ));
    let confirm = |device: &str, nonce: &[u8], sig: Vec<u8>| {
        obj(vec![
            ("device", Value::from(device)),
            ("origin", Value::from(env.origin())),
            ("nonce", Value::Bytes(nonce.to_vec())),
            ("request", Value::Bytes(request.clone())),
            ("signature", Value::Bytes(sig)),
        ])
    };
    let (st, _) = env
        .post(
            "/api/device/confirm",
            Some(&taras),
            confirm(&tid, &nonce, sig),
        )
        .await;
    assert_eq!(st, 401, "wrong user");
    // (the nonce is spent now: the admin asks again)
    let (_, v) = env.post("/api/users", Some(&admin), add.clone()).await;
    let nonce = bytes(&v, "nonce");
    let sig = key.sign(&confirm_message(
        SITE,
        &env.origin(),
        "root",
        &id,
        &nonce,
        &request,
    ));
    let (st, v) = env
        .post(
            "/api/device/confirm",
            Some(&admin),
            confirm(&id, &nonce, sig),
        )
        .await;
    assert_eq!(st, 200, "confirm: {v:?}");
    let (st, v) = env.post("/api/users", Some(&admin), add).await;
    assert_eq!(st, 200, "sent again: {v:?}");

    // WebSocket: an action at config is refused, one at read is not
    tokio::time::sleep(Duration::from_secs(4)).await;
    let mut ws = env.ws(&admin).await;
    let root = format!("wy/{SITE}/downstream/plant");
    let f = ws.invoke(&root, "look").await;
    assert_eq!(get(&f, "ok"), &Value::Bool(true), "{f:?}");
    let f = ws.invoke(&root, "wipe").await;
    let err = get(&f, "error");
    assert_eq!(code(err).as_deref(), Some("confirm_required"), "{f:?}");
    assert_eq!(status(err), Some(Status::PermissionDenied));
    // confirmed with the password this time
    let (st, v) = env
        .post(
            "/api/confirm",
            Some(&admin),
            obj(vec![("password", Value::from("wrong one!"))]),
        )
        .await;
    assert_eq!((st, code(&v).as_deref()), (403, Some("bad_password")));
    let (st, _) = env
        .post(
            "/api/confirm",
            Some(&admin),
            obj(vec![("password", Value::from(ADMIN_PW))]),
        )
        .await;
    assert_eq!(st, 200);
    let f = ws.invoke(&root, "wipe").await;
    assert_eq!(get(&f, "result"), &Value::from("wipe"), "{f:?}");
    // an idle unlock keeps the session and confirms it
    tokio::time::sleep(Duration::from_secs(4)).await;
    let (st, v) = env
        .device_login_as(&key, &id, "root", &env.origin(), Some(&admin))
        .await;
    assert_eq!(st, 200);
    assert_eq!(text(&v, "session"), admin, "the session is kept");
    let f = ws.invoke(&root, "wipe").await;
    assert_eq!(get(&f, "ok"), &Value::Bool(true), "{f:?}");
    let a = env.audit();
    assert!(a.iter().any(|e| matches!(
        e,
        AuditEvent::StepUp {
            method: "device",
            ..
        }
    )));
    assert!(a.iter().any(|e| matches!(
        e,
        AuditEvent::StepUp {
            method: "password",
            ..
        }
    )));
    env.stop().await;
}

/// Consequences: `/api/info` without a session, and nothing in it a session would tell.
#[tokio::test(flavor = "multi_thread")]
async fn info_answers_without_a_session() {
    let dir = temp_dir("info");
    let info = InfoConfig {
        ca: Some(b"not shown over plain http".to_vec()),
        pair: Some("10.0.0.2:8443".into()),
        up: vec!["central".into()],
    };
    let env = Env::start(&dir, DevicePolicy::default(), info).await;
    let (st, v) = env.http("GET", "/api/info", None, None).await;
    assert_eq!(st, 200, "{v:?}");
    assert_eq!(text(&v, "site"), SITE);
    assert_eq!(text(&v, "version"), env!("CARGO_PKG_VERSION"));
    assert_eq!(get(&v, "tls"), &Value::Bool(false));
    assert_eq!(text(&v, "role"), "active");
    assert_eq!(text(&v, "pair"), "10.0.0.2:8443");
    assert_eq!(text(&v, "min_studio"), wyrm_gateway::MIN_STUDIO);
    assert_eq!(get(&v, "up"), &Value::Array(vec![Value::from("central")]));
    let d = get(&v, "devices");
    assert_eq!(get(d, "enabled"), &Value::Bool(true));
    assert_eq!(text(d, "step_up"), "none");
    assert_eq!(get(d, "password_every_days"), &Value::UInt(30));
    // a CA only over TLS; no users, grants or keys at all
    assert!(!has(&v, "ca") && !has(&v, "ca_fp"));
    let Value::Map(m) = &v else { panic!() };
    let keys: Vec<&str> = m.keys().map(String::as_str).collect();
    assert_eq!(
        keys,
        [
            "devices",
            "min_studio",
            "pair",
            "role",
            "site",
            "tls",
            "up",
            "version"
        ]
    );
    // rate limited per address
    let mut last = 200;
    for _ in 0..wyrm_gateway::INFO_PER_MIN {
        last = env.http("GET", "/api/info", None, None).await.0;
    }
    assert_eq!(last, 429);
    env.stop().await;
}

/// Consequences: a standby accepts a device registered on the active: the users store
/// travels (here copied, as ADR 0036 replicates it) and the standby's origin is listed.
#[tokio::test(flavor = "multi_thread")]
async fn a_standby_accepts_a_device_of_the_active() {
    let (active, dir) = start("active", DevicePolicy::default()).await;
    let admin = active.session("root", ADMIN_PW).await;
    active.add_user(&admin, "olena", &["operator"]).await;
    let pw = active.session("olena", USER_PW).await;
    let key = Key::p256();
    let id = active.register_ok(&pw, &key).await;
    active.stop().await;

    let copy = temp_dir("standby");
    std::fs::create_dir_all(copy.join("users")).unwrap();
    for f in std::fs::read_dir(dir.join("users")).unwrap() {
        let f = f.unwrap();
        if f.file_name() != "LOCK" {
            std::fs::copy(f.path(), copy.join("users").join(f.file_name())).unwrap();
        }
    }
    std::fs::copy(dir.join("gateway.key"), copy.join("gateway.key")).unwrap();
    let standby_origin = "https://standby.plant.example:8443";
    let policy = DevicePolicy {
        origins: vec![
            "https://broker.plant.example:8443".into(),
            standby_origin.into(),
        ],
        ..DevicePolicy::default()
    };
    let standby = Env::start(&copy, policy, InfoConfig::default()).await;
    let (st, v) = standby
        .device_login_as(&key, &id, "olena", standby_origin, None)
        .await;
    assert_eq!(st, 200, "{v:?}");
    // an origin outside the list is not served
    let (st, _) = standby
        .device_login_as(&key, &id, "olena", &standby.origin(), None)
        .await;
    assert_eq!(st, 401);
    standby.stop().await;
}

/// A users store written before ADR 0050 (SCHEMA 4, with a snapshot) opens: its users log
/// in, and devices can be added.
#[tokio::test(flavor = "multi_thread")]
async fn a_schema_4_users_store_opens() {
    let fixture = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/users-schema4");
    let dir = temp_dir("schema4");
    std::fs::create_dir_all(dir.join("users")).unwrap();
    for f in std::fs::read_dir(&fixture).unwrap() {
        let f = f.unwrap();
        std::fs::copy(f.path(), dir.join("users").join(f.file_name())).unwrap();
    }
    let mut cfg = GatewayConfig::new(SITE, &dir, "127.0.0.1:0".parse().unwrap());
    cfg.devices = DevicePolicy::default();
    let gw = Gateway::open(cfg, b"fixture state key").unwrap();
    let mut names: Vec<_> = gw.list_users().into_iter().map(|u| u.0).collect();
    names.sort();
    assert_eq!(names, ["olena", "root", "taras"]);
    assert!(gw.user("olena").unwrap().hash.starts_with("$argon2id$"));
    assert!(gw.role_table().contains("ops"));
    assert_eq!(gw.active_devices("olena"), 0);
    // the fixture's password still checks out
    assert!(wyrm_gateway::users::verify_password(
        "fixture password",
        Some(&gw.user("olena").unwrap().hash)
    ));
    drop(gw);
    // a different state key: the store refuses it rather than losing its users
    let mut cfg = GatewayConfig::new(SITE, &dir, "127.0.0.1:0".parse().unwrap());
    cfg.devices = DevicePolicy::default();
    assert!(
        Gateway::open(cfg, b"another key").is_err(),
        "the HMAC chain holds"
    );
}

/// Security review of PR 86, item 3: the hash a `confirm_required` names (signed by the
/// device, kept by the audit) does not depend on a new password in the request.
#[tokio::test(flavor = "multi_thread")]
async fn a_step_up_hash_holds_no_password() {
    let policy = DevicePolicy {
        step_up: StepUp::Config,
        fresh_s: 1,
        ..DevicePolicy::default()
    };
    let (env, _) = start("stepup-hash", policy).await;
    let admin = env.session("root", ADMIN_PW).await;
    tokio::time::sleep(Duration::from_secs(2)).await;
    let mut seen = Vec::new();
    for pw in ["first new password", "second new password"] {
        let (st, v) = env
            .post(
                "/api/users/root/password",
                Some(&admin),
                obj(vec![("password", Value::from(pw))]),
            )
            .await;
        assert_eq!((st, code(&v).as_deref()), (403, Some("confirm_required")));
        seen.push(bytes(&v, "request"));
    }
    assert_eq!(seen[0], seen[1]);
    env.stop().await;
}
