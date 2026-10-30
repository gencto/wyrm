//! The `http` driver against its in-process HTTP server, through the real
//! wire format (`TestHarness`: in-memory Zenoh session, sockets on
//! loopback).

use serde_json::json;
use std::sync::Arc;
use std::time::Duration;
use wyrm_core::{Perm, Quality, Status, Value};
use wyrm_link_http::sim::{self, Mode, Shared, SimAuth};
use wyrm_link_http::Http;
use wyrm_link_sdk::driver::Tree;
use wyrm_link_sdk::{Secret, TestHarness};

type H = TestHarness<Http>;

fn map(kv: &[(&str, Value)]) -> Value {
    Value::Map(
        kv.iter()
            .map(|(k, v)| ((*k).to_owned(), v.clone()))
            .collect(),
    )
}

/// A point at `path`, polled every 0.1 s.
fn pt(path: &str, extra: &[(&str, Value)]) -> Value {
    let mut kv = vec![("path", Value::from(path)), ("poll_s", Value::Float(0.1))];
    kv.extend_from_slice(extra);
    map(&kv)
}

fn dev(kv: &[(&str, Value)], points: Value) -> Value {
    let mut kv = kv.to_vec();
    kv.push(("points", points));
    map(&kv)
}

fn base(port: u16) -> Value {
    Value::from(format!("http://127.0.0.1:{port}/api"))
}

/// `c1` on `base_url` with `conn` params and the devices `devs`. Tests
/// poll fast: rate limit 1000/s, timeout 1 s unless given.
fn tree(base_url: Value, conn: &[(&str, Value)], devs: &[(&str, Value)]) -> Tree {
    let mut c = vec![
        ("base_url", base_url),
        ("timeout_ms", Value::UInt(1000)),
        ("rate_limit", Value::Float(1000.0)),
    ];
    for (k, v) in conn {
        c.retain(|(n, _)| n != k);
        c.push((k, v.clone()));
    }
    c.push(("devices", map(devs)));
    Tree(map(&[
        ("poll_unsubscribed", Value::Bool(true)),
        ("connections", map(&[("c1", map(&c))])),
    ]))
}

/// `c1/d1` = `GET /api/data` with `points`.
fn data_tree(port: u16, conn: &[(&str, Value)], points: Value) -> Tree {
    tree(
        base(port),
        conn,
        &[("d1", dev(&[("path", "/data".into())], points))],
    )
}

fn state(h: &H, base: &str) -> Option<String> {
    match h.ctx().last(&format!("{base}/status"))?.v {
        Value::UInt(i) => wyrm_link_sdk::driver::NodeState::NAMES
            .get(i as usize)
            .map(|s| (*s).to_owned()),
        _ => None,
    }
}

fn error(h: &H, base: &str) -> Option<String> {
    match h.ctx().last(&format!("{base}/error"))?.v {
        Value::Str(s) => Some(s),
        _ => None,
    }
}

fn val(h: &H, p: &str) -> Option<Value> {
    h.ctx().last(p).map(|s| s.v)
}

fn qual(h: &H, p: &str) -> Option<Quality> {
    h.ctx().last(p).map(|s| s.q)
}

fn good(h: &H, p: &str, v: Value) -> bool {
    h.ctx()
        .last(p)
        .is_some_and(|s| s.q == Quality::Good && s.v == v)
}

async fn wait(what: &str, mut f: impl FnMut() -> bool) {
    // Generous: the workspace suite runs many sessions in parallel.
    let deadline = tokio::time::Instant::now() + Duration::from_secs(10);
    while !f() {
        assert!(tokio::time::Instant::now() < deadline, "timeout: {what}");
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
}

fn status(a: &wyrm_core::Attachment) -> Option<Status> {
    match a.status? {
        wyrm_core::status::StatusCode::Known(s) => Some(s),
        _ => None,
    }
}

fn st(s: &Shared) -> std::sync::MutexGuard<'_, sim::State> {
    s.lock().unwrap()
}

/// Invoke `action` on `path` at `perm`: status, value, error text.
async fn act(
    h: &H,
    path: &str,
    action: &str,
    args: Value,
    perm: Perm,
) -> (Option<Status>, Option<Value>, String) {
    let mut r = h.invoke(path, action, args, Some(h.ptok(perm))).await;
    assert_eq!(r.len(), 1, "{path} {action}: one reply");
    let r = r.remove(0);
    let msg = r
        .att
        .err
        .as_ref()
        .map(|e| format!("{e:?}"))
        .unwrap_or_default();
    (status(&r.att), r.value(), msg)
}

fn field<'a>(v: &'a Option<Value>, k: &str) -> &'a Value {
    match v {
        Some(Value::Map(m)) => m.get(k).unwrap_or_else(|| panic!("no {k} in {m:?}")),
        other => panic!("not a map: {other:?}"),
    }
}

/// Every value type and conversion, filters and aggregates; the points of
/// a device with one rate share one request; a selector that finds
/// nothing fails its point only.
#[tokio::test(flavor = "multi_thread")]
async fn values_types_and_one_request_per_group() {
    let (addr, s, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    let slow = |path: &str, extra: &[(&str, Value)]| {
        let mut kv = extra.to_vec();
        kv.push(("poll_s", Value::Float(30.0)));
        pt(path, &kv)
    };
    let points = map(&[
        ("power", slow("$.meter.power", &[("unit", "W".into())])),
        ("kw", slow("$.meter.power", &[("scale", Value::Float(0.5))])),
        ("energy", slow("$.meter.energy", &[])),
        ("voltage", slow("$.meter.voltage", &[])),
        ("on", slow("$.meter.on", &[("type", "bool".into())])),
        (
            "state",
            slow(
                "$.meter.state",
                &[("type", "bool".into()), ("bool_true", "on".into())],
            ),
        ),
        (
            "name",
            slow("$.meter['name']", &[("type", "string".into())]),
        ),
        ("b", slow("$.items[?(@.id==\"b\")].v", &[])),
        ("first", slow("$.items[0].v", &[])),
        ("last", slow("$.items[-1].v", &[])),
        ("sum", slow("$.items[*].v", &[("aggregate", "sum".into())])),
        ("avg", slow("$.items[*].v", &[("aggregate", "avg".into())])),
        ("n", slow("$.items[*]", &[("aggregate", "count".into())])),
        ("deep", slow("$.nested.deep.x", &[])),
        ("json", slow("$.nested", &[("type", "string".into())])),
        // point errors
        ("missing", slow("$.meter.nope", &[])),
        ("many", slow("$.items[*].v", &[])),
        ("null", slow("$.nothing", &[])),
        ("notnum", slow("$.meter.name", &[])),
    ]);
    let h = H::start(data_tree(addr.port(), &[], points)).await;
    let f = Value::Float;
    let want = [
        ("power", f(1200.5)),
        ("kw", f(600.25)),
        ("energy", f(5000.0)),
        ("voltage", f(230.1)),
        ("on", Value::Bool(true)),
        ("state", Value::Bool(true)),
        ("name", "sim-1".into()),
        ("b", f(2.5)),
        ("first", f(1.5)),
        ("last", f(3.0)),
        ("sum", f(7.0)),
        ("avg", f(7.0 / 3.0)),
        ("n", f(3.0)),
        ("deep", f(42.0)),
        ("json", "{\"deep\":{\"x\":42}}".into()),
    ];
    for (p, v) in &want {
        let path = format!("c1/d1/{p}");
        wait(&path, || good(&h, &path, v.clone())).await;
    }
    for p in ["missing", "many", "null", "notnum"] {
        let path = format!("c1/d1/{p}");
        wait(&path, || qual(&h, &path) == Some(Quality::Bad)).await;
    }
    assert_eq!(state(&h, "c1/d1").as_deref(), Some("connected"));
    // 19 points, one rate: one request (30 s period)
    let seen = st(&s).seen.clone();
    assert_eq!(seen.len(), 1, "{seen:?}");
    assert_eq!(
        (seen[0].method.as_str(), seen[0].path.as_str()),
        ("GET", "/api/data")
    );
    assert_eq!(seen[0].header("accept"), Some("application/json"));
    let (_, m) = h.meta("c1/d1/power").await;
    assert!(format!("{:?}", m.unwrap().unit).contains("\"W\""));
    h.stop().await;
}

/// Two rates on one device: two groups, two requests per their periods.
#[tokio::test(flavor = "multi_thread")]
async fn each_rate_is_one_request() {
    let (addr, s, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    let rate = |p: &str, r: f64| map(&[("path", p.into()), ("poll_s", Value::Float(r))]);
    let points = map(&[
        ("a", rate("$.meter.power", 30.0)),
        ("b", rate("$.meter.energy", 30.0)),
        ("c", rate("$.nested.deep.x", 60.0)),
    ]);
    let h = H::start(data_tree(addr.port(), &[], points)).await;
    for p in ["c1/d1/a", "c1/d1/b", "c1/d1/c"] {
        wait(p, || qual(&h, p) == Some(Quality::Good)).await;
    }
    tokio::time::sleep(Duration::from_millis(300)).await;
    assert_eq!(st(&s).seen.len(), 2);
    h.stop().await;
}

/// `poll_s` moves values; a changed reply is published.
#[tokio::test(flavor = "multi_thread")]
async fn changing_values_are_published() {
    let (addr, s, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    st(&s).tick = true;
    let h = H::start(data_tree(
        addr.port(),
        &[],
        map(&[("e", pt("$.meter.energy", &[]))]),
    ))
    .await;
    wait("energy counts up", || {
        val(&h, "c1/d1/e").and_then(|v| v.as_f64()).unwrap_or(0.0) >= 5003.0
    })
    .await;
    h.stop().await;
}

/// A device may POST a JSON body; the reply feeds its points.
#[tokio::test(flavor = "multi_thread")]
async fn post_device_with_a_body() {
    let (addr, s, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    let points = map(&[
        ("q", pt("$.got.q", &[])),
        ("power", pt("$.data.meter.power", &[])),
    ]);
    let d = dev(
        &[
            ("method", "post".into()),
            ("path", "/query".into()),
            ("body", "{\"q\": 7}".into()),
        ],
        points,
    );
    let h = H::start(tree(base(addr.port()), &[], &[("d1", d)])).await;
    wait("q", || good(&h, "c1/d1/q", Value::Float(7.0))).await;
    wait("power", || good(&h, "c1/d1/power", Value::Float(1200.5))).await;
    let seen = st(&s).seen[0].clone();
    assert_eq!(seen.method, "POST");
    assert_eq!(seen.header("content-type"), Some("application/json"));
    assert_eq!(seen.body, "{\"q\": 7}");
    h.stop().await;
}

/// Writes: the template with `{{value}}`, 2xx = done, the value comes from
/// the read-back; a refused write and read-only points fail.
#[tokio::test(flavor = "multi_thread")]
async fn writes_and_read_back() {
    let (addr, s, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    let w = |path: &str, extra: &[(&str, Value)]| {
        let mut kv = vec![
            ("writable", Value::Bool(true)),
            ("write_path", "/resource".into()),
            ("poll_s", Value::Float(30.0)),
        ];
        kv.extend_from_slice(extra);
        pt(path, &kv)
    };
    let points = map(&[
        (
            "sp",
            w(
                "$.setpoint",
                &[
                    ("write_body", "{\"setpoint\": {{value}}}".into()),
                    ("scale", Value::Float(0.5)),
                ],
            ),
        ),
        (
            "enabled",
            w(
                "$.enabled",
                &[
                    ("type", "bool".into()),
                    ("write_method", "patch".into()),
                    ("write_body", "{\"enabled\": {{value}}}".into()),
                ],
            ),
        ),
        (
            "mode",
            w(
                "$.mode",
                &[
                    ("type", "string".into()),
                    ("write_method", "post".into()),
                    ("write_body", "{\"mode\": {{value}}}".into()),
                ],
            ),
        ),
        // the server answers 400: the body is not an object
        ("refused", w("$.label", &[("type", "string".into())])),
        ("ro", pt("$.label", &[("type", "string".into())])),
    ]);
    let h = H::start(tree(
        base(addr.port()),
        &[],
        &[("d1", dev(&[("path", "/resource".into())], points))],
    ))
    .await;
    wait("sp", || good(&h, "c1/d1/sp", Value::Float(10.0))).await;
    let ok = Some(Status::Ok);
    let att = h.set("c1/d1/sp", 21.0, Some(h.ptok(Perm::Write))).await;
    assert_eq!(status(&att), ok);
    assert_eq!(st(&s).resource["setpoint"], json!(42));
    // read back at once (no poll for 30 s)
    wait("sp read back", || good(&h, "c1/d1/sp", Value::Float(21.0))).await;
    let put = st(&s)
        .seen
        .iter()
        .find(|r| r.method == "PUT")
        .cloned()
        .unwrap();
    assert_eq!(
        (put.path.as_str(), put.body.as_str()),
        ("/api/resource", "{\"setpoint\": 42}")
    );
    let att = h
        .set("c1/d1/enabled", true, Some(h.ptok(Perm::Write)))
        .await;
    assert_eq!(status(&att), ok);
    wait("enabled", || good(&h, "c1/d1/enabled", Value::Bool(true))).await;
    let att = h
        .set("c1/d1/mode", "manual", Some(h.ptok(Perm::Write)))
        .await;
    assert_eq!(status(&att), ok);
    wait("mode", || good(&h, "c1/d1/mode", "manual".into())).await;
    assert!(st(&s).seen.iter().any(|r| r.method == "PATCH"));
    // a 400: the write fails, the value stays what the server holds
    let att = h.set("c1/d1/refused", "y", Some(h.ptok(Perm::Write))).await;
    assert_eq!(status(&att), Some(Status::InvalidParameter));
    assert_eq!(val(&h, "c1/d1/refused"), Some("x".into()));
    // read-only
    let att = h.set("c1/d1/ro", "y", Some(h.ptok(Perm::Write))).await;
    assert_ne!(status(&att), ok);
    assert_eq!(st(&s).resource["label"], json!("x"));
    let (_, m) = h.meta("c1/d1/ro").await;
    assert_eq!(m.unwrap().writable, Some(wyrm_core::meta::Writable::Never));
    h.stop().await;
}

/// A write that is redirected: 301 and 302 fail ("write not applied"),
/// whatever the method, since a client may send it on as a GET without a
/// body; 307 is followed with the method and the body; 303 (the write is
/// applied, see the result) is a success.
#[tokio::test(flavor = "multi_thread")]
async fn redirected_writes() {
    let (addr, s, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    let w = |to: &str, method: &str| {
        pt(
            "$.mode",
            &[
                ("type", "string".into()),
                ("writable", true.into()),
                ("write_method", method.into()),
                ("write_path", to.into()),
                ("write_body", "{\"mode\": {{value}}}".into()),
                ("poll_s", Value::Float(30.0)),
            ],
        )
    };
    let points = map(&[
        ("moved", w("/moved", "post")),
        ("found", w("/found", "put")),
        ("temp", w("/temp", "post")),
        ("done", w("/done", "patch")),
    ]);
    let h = H::start(tree(
        base(addr.port()),
        &[],
        &[("d1", dev(&[("path", "/resource".into())], points))],
    ))
    .await;
    wait("read", || good(&h, "c1/d1/moved", "auto".into())).await;
    let tok = || Some(h.ptok(Perm::Write));
    for p in ["moved", "found"] {
        let att = h.set(&format!("c1/d1/{p}"), "lost", tok()).await;
        assert_eq!(status(&att), Some(Status::InvalidParameter), "{p}");
        let e = format!("{:?}", att.err);
        assert!(e.contains("write not applied"), "{p}: {e}");
        assert_eq!(st(&s).resource["mode"], json!("auto"), "{p}");
    }
    let att = h.set("c1/d1/temp", "t", tok()).await;
    assert_eq!(status(&att), Some(Status::Ok));
    assert_eq!(st(&s).resource["mode"], json!("t"));
    let sent = st(&s).seen.iter().filter(|r| r.method == "POST").count();
    assert_eq!(sent, 3, "307: POST /temp, POST /resource; 301: POST /moved");
    let att = h.set("c1/d1/done", "d", tok()).await;
    assert_eq!(status(&att), Some(Status::Ok));
    assert_eq!(st(&s).resource["mode"], json!("d"));
    wait("read back", || good(&h, "c1/d1/done", "d".into())).await;
    h.stop().await;
}

/// Basic, bearer, and an API key in a header or a query parameter; a
/// wrong one is "authentication failed" on the device, never with the key.
#[tokio::test(flavor = "multi_thread")]
async fn auth_kinds() {
    let cases: Vec<(SimAuth, Vec<(&str, Value)>)> = vec![
        (
            SimAuth::Basic("wyrm".into(), "pw-basic".into()),
            vec![
                ("auth", "basic".into()),
                ("username", "wyrm".into()),
                ("password", "pw-basic".into()),
            ],
        ),
        (
            SimAuth::Bearer("tok-bearer".into()),
            vec![("auth", "bearer".into()), ("token", "tok-bearer".into())],
        ),
        (
            SimAuth::Header("x-api-key".into(), "key-header".into()),
            vec![("auth", "api_key".into()), ("token", "key-header".into())],
        ),
        (
            SimAuth::Query("apikey".into(), "key-query".into()),
            vec![
                ("auth", "api_key".into()),
                ("api_key_in", "query".into()),
                ("api_key_name", "apikey".into()),
                ("token", "key-query".into()),
            ],
        ),
        (
            SimAuth::Header("x-api-secret".into(), "sec-header".into()),
            vec![
                ("secret_header_name", "X-Api-Secret".into()),
                ("secret_header_value", "sec-header".into()),
            ],
        ),
    ];
    for (auth, conn) in cases {
        let (addr, s, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
        st(&s).auth = auth.clone();
        let points = map(&[("p", pt("$.meter.power", &[]))]);
        let h = H::start(data_tree(addr.port(), &conn, points.clone())).await;
        wait(&format!("{auth:?}"), || {
            good(&h, "c1/d1/p", Value::Float(1200.5))
        })
        .await;
        h.stop().await;
        // the server wants another secret now
        let secret = match &auth {
            SimAuth::Basic(..) => "pw-basic".to_owned(),
            SimAuth::Bearer(t) | SimAuth::Header(_, t) | SimAuth::Query(_, t) => t.clone(),
            SimAuth::None => unreachable!(),
        };
        st(&s).auth = match auth {
            SimAuth::Basic(u, _) => SimAuth::Basic(u, "other".into()),
            SimAuth::Bearer(_) => SimAuth::Bearer("other".into()),
            SimAuth::Header(n, _) => SimAuth::Header(n, "other".into()),
            SimAuth::Query(n, _) => SimAuth::Query(n, "other".into()),
            SimAuth::None => SimAuth::None,
        };
        let h = H::start(data_tree(addr.port(), &conn, points)).await;
        wait("authentication failed", || {
            error(&h, "c1/d1").is_some_and(|e| e.contains("authentication failed"))
                && qual(&h, "c1/d1/p") != Some(Quality::Good)
        })
        .await;
        let e = error(&h, "c1/d1").unwrap();
        assert!(e.contains("HTTP 401") && e.contains("GET /api/data"), "{e}");
        assert!(!e.contains(&secret), "{e}");
        assert_eq!(state(&h, "c1/d1").as_deref(), Some("failed"));
        assert_eq!(state(&h, "c1").as_deref(), Some("connected"));
        h.stop().await;
    }
}

/// No reply: `uncertain/stale`, then `bad/comm_fail` and the device
/// failed; the connection stays up; recovery is good again.
#[tokio::test(flavor = "multi_thread")]
async fn silent_server_degrades_quality() {
    let (addr, s, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    let h = H::start(data_tree(
        addr.port(),
        &[("timeout_ms", Value::UInt(200))],
        map(&[("p", pt("$.meter.power", &[]))]),
    ))
    .await;
    wait("good", || qual(&h, "c1/d1/p") == Some(Quality::Good)).await;
    let samples = Arc::new(std::sync::Mutex::new(Vec::new()));
    st(&s).mode = Mode::Silent;
    let seen = samples.clone();
    wait("uncertain then bad", || {
        if let Some(q) = qual(&h, "c1/d1/p") {
            let mut v = seen.lock().unwrap();
            if v.last() != Some(&q) {
                v.push(q);
            }
        }
        qual(&h, "c1/d1/p") == Some(Quality::Bad)
    })
    .await;
    assert!(samples.lock().unwrap().contains(&Quality::Uncertain));
    assert_eq!(state(&h, "c1/d1").as_deref(), Some("failed"));
    assert!(error(&h, "c1/d1").unwrap().contains("no reply in 200 ms"));
    assert_eq!(state(&h, "c1").as_deref(), Some("connected"));
    // the value is kept, never invented
    assert_eq!(val(&h, "c1/d1/p"), Some(Value::Float(1200.5)));
    st(&s).mode = Mode::Normal;
    wait("recovered", || qual(&h, "c1/d1/p") == Some(Quality::Good)).await;
    assert_eq!(state(&h, "c1/d1").as_deref(), Some("connected"));
    h.stop().await;
}

/// 5xx, a status outside `expect_status`, invalid JSON and a body over
/// the bound are device misses with a reason; recovery after.
#[tokio::test(flavor = "multi_thread")]
async fn server_errors_and_bad_bodies() {
    let (addr, s, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    let h = H::start(data_tree(
        addr.port(),
        &[("max_body_kib", Value::UInt(16))],
        map(&[("p", pt("$.meter.power", &[]))]),
    ))
    .await;
    wait("good", || qual(&h, "c1/d1/p") == Some(Quality::Good)).await;
    for (mode, why) in [
        (Mode::Status(500), "HTTP 500"),
        (Mode::Status(404), "HTTP 404"),
        (Mode::InvalidJson, "not JSON"),
        (Mode::Huge(64 * 1024), "body over 16384 bytes"),
    ] {
        st(&s).mode = mode.clone();
        wait(&format!("{mode:?}"), || {
            error(&h, "c1/d1").is_some_and(|e| e.contains(why))
                && qual(&h, "c1/d1/p") == Some(Quality::Bad)
        })
        .await;
        st(&s).mode = Mode::Normal;
        wait("recovered", || {
            qual(&h, "c1/d1/p") == Some(Quality::Good)
                && state(&h, "c1/d1").as_deref() == Some("connected")
        })
        .await;
    }
    h.stop().await;
    // 204 is not in the default 200-299? It is; a device that wants 200 only
    let points = map(&[("p", pt("$.meter.power", &[]))]);
    let d = dev(
        &[("path", "/data".into()), ("expect_status", "201".into())],
        points,
    );
    let h = H::start(tree(base(addr.port()), &[], &[("d1", d)])).await;
    wait("200 not expected", || {
        error(&h, "c1/d1").is_some_and(|e| e.contains("HTTP 200"))
    })
    .await;
    h.stop().await;
}

/// Server gone: the connection fails with an `error`, its devices are
/// stopped by the parent and the points `bad`; it reconnects when the
/// server is back.
#[tokio::test(flavor = "multi_thread")]
async fn connection_down_and_reconnect() {
    let (addr, _s, task) = sim::spawn("127.0.0.1:0").await.unwrap();
    let h = H::start(data_tree(
        addr.port(),
        &[],
        map(&[("p", pt("$.meter.power", &[]))]),
    ))
    .await;
    wait("good", || qual(&h, "c1/d1/p") == Some(Quality::Good)).await;
    assert_eq!(state(&h, "c1").as_deref(), Some("connected"));
    task.abort();
    let _ = task.await;
    wait("connection failed", || {
        state(&h, "c1").as_deref() == Some("failed")
            && state(&h, "c1/d1").as_deref() == Some("stopped_by_parent")
    })
    .await;
    assert!(error(&h, "c1").is_some_and(|e| e.contains("connect")));
    assert_eq!(qual(&h, "c1/d1/p"), Some(Quality::Bad));
    let att = h.set("c1/d1/p", 1.0, Some(h.ptok(Perm::Write))).await;
    assert_ne!(status(&att), Some(Status::Ok));
    // back on the same port
    let (_, s2, _task2) = sim::spawn(&addr.to_string()).await.unwrap();
    st(&s2).data["meter"]["power"] = json!(99);
    wait("reconnected", || {
        good(&h, "c1/d1/p", Value::Float(99.0)) && state(&h, "c1").as_deref() == Some("connected")
    })
    .await;
    h.stop().await;
}

/// A server that closes after each reply: the link reconnects quietly.
#[tokio::test(flavor = "multi_thread")]
async fn connection_close_is_not_a_failure() {
    let (addr, s, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    st(&s).close = true;
    st(&s).tick = true;
    let h = H::start(data_tree(
        addr.port(),
        &[],
        map(&[("e", pt("$.meter.energy", &[]))]),
    ))
    .await;
    wait("several polls", || {
        val(&h, "c1/d1/e").and_then(|v| v.as_f64()).unwrap_or(0.0) >= 5005.0
    })
    .await;
    assert!(st(&s).connections >= 5);
    assert_eq!(state(&h, "c1").as_deref(), Some("connected"));
    h.stop().await;
}

/// A reply that comes after its timeout is never taken for a later
/// request: the timed-out connection is closed.
#[tokio::test(flavor = "multi_thread")]
async fn a_late_reply_is_not_taken() {
    let (addr, s, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    {
        let mut t = st(&s);
        t.data["meter"]["power"] = json!(1);
        t.slow_ms = 600;
    }
    let h = H::start(data_tree(
        addr.port(),
        &[("timeout_ms", Value::UInt(300))],
        map(&[("p", pt("$.meter.power", &[]))]),
    ))
    .await;
    wait("a request timed out", || {
        qual(&h, "c1/d1/p") == Some(Quality::Uncertain) || error(&h, "c1/d1").is_some()
    })
    .await;
    {
        let mut t = st(&s);
        t.data["meter"]["power"] = json!(2);
        t.slow_ms = 0;
    }
    wait("the new value", || {
        assert_ne!(
            val(&h, "c1/d1/p"),
            Some(Value::Float(1.0)),
            "late reply taken"
        );
        good(&h, "c1/d1/p", Value::Float(2.0))
    })
    .await;
    assert!(
        st(&s).connections >= 2,
        "the timed-out connection was dropped"
    );
    h.stop().await;
}

/// Up to three redirects on the same host; more, or another host, fail
/// the device.
#[tokio::test(flavor = "multi_thread")]
async fn redirects() {
    let (addr, s, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    let points = || map(&[("p", pt("$.meter.power", &[]))]);
    let d = |path: &str| dev(&[("path", path.into())], points());
    // `/redirect/n` is outside the base URL's /api prefix
    let h = H::start(tree(
        Value::from(format!("http://127.0.0.1:{}", addr.port())),
        &[],
        &[
            ("ok", d("/redirect/2")),
            ("many", d("/redirect/3")),
            ("off", d("/offsite")),
        ],
    ))
    .await;
    wait("three hops", || good(&h, "c1/ok/p", Value::Float(1200.5))).await;
    wait("four hops", || {
        error(&h, "c1/many").is_some_and(|e| e.contains("more than 3 redirects"))
    })
    .await;
    wait("another host", || {
        error(&h, "c1/off").is_some_and(|e| e.contains("redirect refused: another host"))
    })
    .await;
    assert!(!st(&s).seen.iter().any(|r| r.path.contains("other")));
    h.stop().await;
}

/// The rate limit spaces requests on a connection.
#[tokio::test(flavor = "multi_thread")]
async fn rate_limit_spaces_requests() {
    let (addr, s, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    let h = H::start(data_tree(
        addr.port(),
        &[("rate_limit", Value::Float(4.0))],
        map(&[("p", pt("$.meter.power", &[]))]),
    ))
    .await;
    wait("five requests", || st(&s).seen.len() >= 5).await;
    let at: Vec<_> = st(&s).seen.iter().map(|r| r.at).collect();
    for w in at.windows(2) {
        let gap = w[1] - w[0];
        assert!(gap >= Duration::from_millis(230), "{gap:?}");
    }
    h.stop().await;
}

/// TLS: a CA in `ca_pem`; another CA is refused (connection failed);
/// `insecure_skip_verify` connects and shows a warning.
#[tokio::test(flavor = "multi_thread")]
async fn tls_with_ca_pem_and_skip_verify() {
    use rcgen::{BasicConstraints, CertificateParams, IsCa, Issuer, KeyPair};
    let ca = |name: &str| {
        let key = KeyPair::generate().unwrap();
        let mut p = CertificateParams::new(Vec::<String>::new()).unwrap();
        p.is_ca = IsCa::Ca(BasicConstraints::Unconstrained);
        p.distinguished_name
            .push(rcgen::DnType::CommonName, name.to_owned());
        let cert = p.self_signed(&key).unwrap();
        (cert.pem(), Issuer::new(p, key))
    };
    let (ca_pem, issuer) = ca("test ca");
    let (other_pem, _) = ca("other ca");
    let key = KeyPair::generate().unwrap();
    let cert = CertificateParams::new(vec!["localhost".to_owned()])
        .unwrap()
        .signed_by(&key, &issuer)
        .unwrap();
    let provider = Arc::new(rustls::crypto::ring::default_provider());
    let cfg = rustls::ServerConfig::builder_with_provider(provider)
        .with_safe_default_protocol_versions()
        .unwrap()
        .with_no_client_auth()
        .with_single_cert(
            vec![cert.der().clone()],
            rustls_pki_types::PrivateKeyDer::Pkcs8(key.serialize_der().into()),
        )
        .unwrap();
    let (addr, _s, _task) = sim::spawn_tls("127.0.0.1:0", Arc::new(cfg)).await.unwrap();
    let url = Value::from(format!("https://localhost:{}/api", addr.port()));
    let points = || map(&[("p", pt("$.meter.power", &[]))]);
    let d = || [("d1", dev(&[("path", "/data".into())], points()))];
    let h = H::start(tree(url.clone(), &[("ca_pem", ca_pem.into())], &d())).await;
    wait("over tls", || good(&h, "c1/d1/p", Value::Float(1200.5))).await;
    let (_, m) = h.meta("c1/status").await;
    assert!(m.unwrap().attr_value("warning").is_none());
    h.stop().await;
    let h = H::start(tree(url.clone(), &[("ca_pem", other_pem.into())], &d())).await;
    wait("untrusted", || {
        state(&h, "c1").as_deref() == Some("failed")
            && error(&h, "c1").is_some_and(|e| e.contains("tls"))
    })
    .await;
    h.stop().await;
    let h = H::start(tree(url, &[("insecure_skip_verify", true.into())], &d())).await;
    wait("not verified", || good(&h, "c1/d1/p", Value::Float(1200.5))).await;
    let (_, m) = h.meta("c1/status").await;
    let warning = format!("{:?}", m.unwrap().attr_value("warning"));
    assert!(warning.contains("not checked"), "{warning}");
    h.stop().await;
}

/// `try_request` and `test_selector` on a device at level config: they
/// send real requests (a POST device too), show reply headers and the
/// whole reply, and share the rate limit with the polls.
#[tokio::test(flavor = "multi_thread")]
async fn commissioning_actions() {
    let (addr, s, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    let h = H::start(data_tree(
        addr.port(),
        &[],
        map(&[("p", pt("$.meter.power", &[("poll_s", Value::Float(60.0))]))]),
    ))
    .await;
    let (_, m) = h.meta("c1/d1").await;
    let acts = m.unwrap().actions.unwrap();
    assert_eq!(acts["try_request"].level, Some(Perm::Config));
    assert_eq!(acts["test_selector"].level, Some(Perm::Config));
    wait("polled", || st(&s).seen.len() == 1).await;
    for a in ["try_request", "test_selector"] {
        let args = map(&[("path", "$".into())]);
        for perm in [Perm::Read, Perm::Write] {
            let (r, _, _) = act(&h, "c1/d1", a, args.clone(), perm).await;
            assert_eq!(r, Some(Status::PermissionDenied), "{a} at {perm:?}");
        }
    }
    assert_eq!(st(&s).seen.len(), 1, "a refused try_request sends nothing");
    let (s0, v, e) = act(&h, "c1/d1", "try_request", map(&[]), Perm::Config).await;
    assert_eq!(s0, Some(Status::Ok), "{e}");
    assert_eq!(field(&v, "status"), &Value::UInt(200));
    assert_eq!(field(&v, "truncated"), &Value::Bool(false));
    let Value::Str(body) = field(&v, "body") else {
        panic!("body")
    };
    assert!(body.contains("sim-1"));
    let Value::Map(headers) = field(&v, "headers") else {
        panic!("headers")
    };
    assert_eq!(
        headers.get("content-type"),
        Some(&Value::Str("application/json".into()))
    );
    let args = map(&[
        ("path", "$.items[*].v".into()),
        ("type", "number".into()),
        ("aggregate", "sum".into()),
    ]);
    let (s1, v, _) = act(&h, "c1/d1", "test_selector", args, Perm::Config).await;
    assert_eq!(s1, Some(Status::Ok));
    assert_eq!(field(&v, "count"), &Value::UInt(3));
    assert_eq!(field(&v, "value"), &Value::Float(7.0));
    let args = map(&[("path", "$.items[*].v".into()), ("type", "number".into())]);
    let (_, v, _) = act(&h, "c1/d1", "test_selector", args, Perm::Config).await;
    assert!(matches!(field(&v, "error"), Value::Str(e) if e.contains("selects 3")));
    let (s2, _, _) = act(
        &h,
        "c1/d1",
        "test_selector",
        map(&[("path", "nope".into())]),
        Perm::Config,
    )
    .await;
    assert_eq!(s2, Some(Status::InvalidParameter));
    // a 401 is a reply too; its cookie is not shown
    st(&s).auth = SimAuth::Bearer("x".into());
    let (_, v, _) = act(&h, "c1/d1", "try_request", map(&[]), Perm::Config).await;
    assert_eq!(field(&v, "status"), &Value::UInt(401));
    let Value::Map(headers) = field(&v, "headers") else {
        panic!("headers")
    };
    assert!(headers.contains_key("www-authenticate"));
    assert!(!headers.contains_key("set-cookie"));
    // a large body is cut at 64 KiB
    st(&s).auth = SimAuth::None;
    st(&s).mode = Mode::Huge(100 * 1024);
    let (_, v, _) = act(&h, "c1/d1", "try_request", map(&[]), Perm::Config).await;
    assert_eq!(field(&v, "truncated"), &Value::Bool(true));
    assert_eq!(field(&v, "bytes"), &Value::UInt(100 * 1024));
    h.stop().await;
}

/// As in DSA, credentials come with the connection: secret params of
/// `add_connection`, sealed by the framework, never in `~meta`, `export`,
/// errors or `try_request`; kept by an edit to the same destination and
/// dropped by one that changes the base URL.
#[tokio::test(flavor = "multi_thread")]
async fn secrets_are_never_shown() {
    let (addr, s, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    const TOKEN: &str = "tok-5555555";
    st(&s).auth = SimAuth::Bearer(TOKEN.into());
    let dir = std::env::temp_dir().join(format!(
        "wyrm-http-sec-{}-{}",
        std::process::id(),
        addr.port()
    ));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let start = || {
        let dir = dir.clone();
        H::start_with(Tree(map(&[("connections", map(&[]))])), move |c| {
            c.data_dir = Some(dir);
            c.secrets.insert(
                wyrm_link_sdk::driver::persist::STORE_KEY,
                Secret::new(vec![5u8; 32]),
            );
        })
    };
    let cfg = Perm::Config;
    let h = start().await;
    let conn = |url: Value, token: Option<&str>| {
        let mut kv = vec![
            ("base_url", url),
            ("auth", Value::from("bearer")),
            ("rate_limit", Value::Float(1000.0)),
        ];
        if let Some(t) = token {
            kv.push(("token", t.into()));
        }
        kv
    };
    let mut add = conn(base(addr.port()), Some(TOKEN));
    add.push(("name", "c1".into()));
    let (r, _, e) = act(&h, "", "add_connection", map(&add), cfg).await;
    assert_eq!(r, Some(Status::Ok), "{e}");
    let (r, _, e) = act(
        &h,
        "c1",
        "add_device",
        map(&[("name", "d1".into()), ("path", "/echo".into())]),
        cfg,
    )
    .await;
    assert_eq!(r, Some(Status::Ok), "{e}");
    let p = map(&[
        ("name", "auth".into()),
        // the server echoes the credential: the point shows it masked
        ("path", "$.headers.authorization".into()),
        ("type", "string".into()),
        ("poll_s", Value::Float(0.2)),
    ]);
    let (r, _, e) = act(&h, "c1/d1", "add_point", p, cfg).await;
    assert_eq!(r, Some(Status::Ok), "{e}");
    wait("authorized", || good(&h, "c1/d1/auth", "Bearer ***".into())).await;
    let (_, m) = h.meta("c1").await;
    assert!(!format!("{m:?}").contains(TOKEN), "~meta hides it");
    let (_, v, _) = act(&h, "", "export", map(&[]), cfg).await;
    assert!(!format!("{v:?}").contains(TOKEN), "export hides it");
    let (_, v, _) = act(&h, "c1/d1", "try_request", map(&[]), Perm::Config).await;
    let shown = format!("{v:?}");
    assert!(
        !shown.contains(TOKEN) && shown.contains("Bearer ***"),
        "{shown}"
    );
    for path in ["$.headers.authorization", "$.headers.*", "$"] {
        let args = map(&[
            ("path", path.into()),
            ("type", "string".into()),
            ("aggregate", "first".into()),
        ]);
        let (r, v, e) = act(&h, "c1/d1", "test_selector", args, Perm::Config).await;
        assert_eq!(r, Some(Status::Ok), "{e}");
        let shown = format!("{v:?}");
        assert!(
            !shown.contains(TOKEN) && shown.contains("***"),
            "{path}: {shown}"
        );
    }
    // a plaintext token to a host that is not loopback is refused
    let mut far = conn(Value::from("http://192.0.2.1/api"), Some(TOKEN));
    far.push(("name", "c2".into()));
    let (r, _, e) = act(&h, "", "add_connection", map(&far), cfg).await;
    assert_eq!(r, Some(Status::InvalidParameter));
    assert!(!e.contains(TOKEN), "{e}");
    h.stop().await;
    let sealed = std::fs::read(dir.join("framework.tree")).unwrap();
    assert!(!sealed.windows(TOKEN.len()).any(|w| w == TOKEN.as_bytes()));

    // restart: the connection and its token come back
    let h = start().await;
    wait("authorized after restart", || {
        state(&h, "c1/d1").as_deref() == Some("connected")
    })
    .await;
    // an edit without the token, same destination: kept
    let (r, _, e) = act(&h, "c1", "edit", map(&conn(base(addr.port()), None)), cfg).await;
    assert_eq!(r, Some(Status::Ok), "{e}");
    tokio::time::sleep(Duration::from_millis(300)).await;
    let before = st(&s).seen.len();
    wait("still authorized", || {
        st(&s).seen.len() > before + 2 && state(&h, "c1/d1").as_deref() == Some("connected")
    })
    .await;
    // another base URL without the token: dropped (the add form wants it)
    let moved = Value::from(format!("http://localhost:{}/api", addr.port()));
    let (r, _, _) = act(&h, "c1", "edit", map(&conn(moved, None)), cfg).await;
    assert_eq!(r, Some(Status::InvalidParameter), "token required again");
    h.stop().await;
    let _ = std::fs::remove_dir_all(&dir);
}

/// The secret header, echoed by the server, is masked in a point and in
/// `try_request`, and never in `~meta` or `export`.
#[tokio::test(flavor = "multi_thread")]
async fn a_secret_header_is_masked() {
    let (addr, s, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    const SEC: &str = "sec-4242424";
    st(&s).auth = SimAuth::Header("x-api-secret".into(), SEC.into());
    let points = map(&[(
        "h",
        pt("$.headers['x-api-secret']", &[("type", "string".into())]),
    )]);
    let h = H::start(tree(
        base(addr.port()),
        &[
            ("secret_header_name", "X-Api-Secret".into()),
            ("secret_header_value", SEC.into()),
        ],
        &[("d1", dev(&[("path", "/echo".into())], points))],
    ))
    .await;
    wait("masked", || good(&h, "c1/d1/h", "***".into())).await;
    let cfg = Perm::Config;
    let (_, v, _) = act(&h, "c1/d1", "try_request", map(&[]), cfg).await;
    let shown = format!("{v:?}");
    assert!(!shown.contains(SEC) && shown.contains("***"), "{shown}");
    let (_, m) = h.meta("c1").await;
    assert!(!format!("{m:?}").contains(SEC), "~meta hides it");
    let (_, v, _) = act(&h, "", "export", map(&[]), cfg).await;
    let shown = format!("{v:?}");
    assert!(
        !shown.contains(SEC) && shown.contains("X-Api-Secret"),
        "{shown}"
    );
    h.stop().await;
}

/// Bounds and rules of the params, through the generated actions; a bad
/// stored point is kept as a failed node.
#[tokio::test(flavor = "multi_thread")]
async fn params_bounds_and_bad_nodes() {
    let (addr, _s, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    let points = map(&[
        ("ok", pt("$.meter.power", &[])),
        ("bad", pt("meter.power", &[])),
    ]);
    let h = H::start(data_tree(addr.port(), &[], points)).await;
    wait("ok", || qual(&h, "c1/d1/ok") == Some(Quality::Good)).await;
    let (_, m) = h.meta("c1/d1/bad").await;
    assert!(m.is_some(), "kept");
    let cfg = Perm::Config;
    for (args, why) in [
        (vec![("timeout_ms", Value::UInt(50))], "timeout_ms"),
        (vec![("rate_limit", Value::Float(5000.0))], "rate_limit"),
        (vec![("base_url", "ftp://x".into())], "base_url"),
        // a multi-byte host character: refused, the link keeps running
        (
            vec![("base_url", "http://über.local/api".into())],
            "base_url",
        ),
        (vec![("headers", "Cookie: a=1".into())], "headers"),
    ] {
        let mut kv = vec![("name", Value::from("cx")), ("base_url", base(addr.port()))];
        for (k, v) in args {
            kv.retain(|(n, _)| *n != k);
            kv.push((k, v));
        }
        let (r, _, e) = act(&h, "", "add_connection", map(&kv), cfg).await;
        assert_eq!(r, Some(Status::InvalidParameter), "{why}");
        assert!(e.contains(why), "{why}: {e}");
    }
    for (args, why) in [
        (vec![("path", "$..a".into())], "path"),
        (
            vec![("path", "$.a".into()), ("poll_s", Value::Float(0.0))],
            "poll_s",
        ),
        (
            vec![
                ("path", "$.a".into()),
                ("writable", true.into()),
                ("write_body", "{\"a\": 1}".into()),
            ],
            "write_body",
        ),
    ] {
        let mut kv = vec![("name", Value::from("px"))];
        kv.extend(args);
        let (r, _, e) = act(&h, "c1/d1", "add_point", map(&kv), cfg).await;
        assert_eq!(r, Some(Status::InvalidParameter), "{why}");
        assert!(e.contains(why), "{why}: {e}");
    }
    let (r, _, e) = act(
        &h,
        "c1",
        "add_device",
        map(&[("name", "dx".into()), ("body", "{}".into())]),
        cfg,
    )
    .await;
    assert_eq!(r, Some(Status::InvalidParameter));
    assert!(e.contains("body"), "{e}");
    h.stop().await;
}

/// Diagnostics: requests, replies with an error status, reconnects.
#[tokio::test(flavor = "multi_thread")]
async fn diagnostics_count_requests() {
    let (addr, s, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    st(&s).close = true;
    let h = H::start(data_tree(
        addr.port(),
        &[],
        map(&[("p", pt("$.meter.power", &[]))]),
    ))
    .await;
    wait("polls", || st(&s).seen.len() >= 4).await;
    st(&s).mode = Mode::Status(503);
    wait("errors", || error(&h, "c1/d1").is_some()).await;
    // reading the node publishes its counters at once
    let n = |p: &str| h.ctx().last(p).and_then(|s| s.v.as_f64()).unwrap_or(0.0);
    let deadline = tokio::time::Instant::now() + Duration::from_secs(10);
    loop {
        let _ = h.meta("c1").await;
        if n("c1/requests") >= 4.0 && n("c1/exceptions") >= 1.0 && n("c1/reconnects") >= 2.0 {
            break;
        }
        assert!(tokio::time::Instant::now() < deadline, "counted");
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
    h.stop().await;
}

/// An API key in the query, echoed by the server, is masked in a polled
/// string point, in `try_request` and in `test_selector`.
#[tokio::test(flavor = "multi_thread")]
async fn an_echoed_query_key_is_masked() {
    let (addr, s, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    const KEY: &str = "key-9876543";
    st(&s).auth = SimAuth::Query("apikey".into(), KEY.into());
    let points = map(&[("q", pt("$.query", &[("type", "string".into())]))]);
    let h = H::start(tree(
        base(addr.port()),
        &[
            ("auth", "api_key".into()),
            ("api_key_in", "query".into()),
            ("api_key_name", "apikey".into()),
            ("token", KEY.into()),
        ],
        &[(
            "d1",
            dev(&[("path", "/echo".into()), ("query", "a=1".into())], points),
        )],
    ))
    .await;
    wait("masked", || good(&h, "c1/d1/q", "a=1&apikey=***".into())).await;
    let (_, v, _) = act(&h, "c1/d1", "try_request", map(&[]), Perm::Config).await;
    let shown = format!("{v:?}");
    assert!(
        !shown.contains(KEY) && shown.contains("apikey=***"),
        "{shown}"
    );
    let args = map(&[("path", "$.query".into())]);
    let (_, v, _) = act(&h, "c1/d1", "test_selector", args, Perm::Config).await;
    let shown = format!("{v:?}");
    assert!(
        !shown.contains(KEY) && shown.contains("apikey=***"),
        "{shown}"
    );
    h.stop().await;
}

/// A secret echoed in a JSON escape (`\/`, `\u0031`), as a member name or
/// as a JSON number is masked in polled points, `try_request` and
/// `test_selector`.
#[tokio::test(flavor = "multi_thread")]
async fn escaped_numeric_and_key_secrets_are_masked() {
    let cases = [
        // token "ab/c1-tok": escaped in a string, plain as a member name
        (
            "ab/c1-tok",
            r#"{"esc": "x ab\/c\u0031-tok y", "k": {"ab/c1-tok": 1}, "n": 5}"#,
            vec![("e", "$.esc", "x *** y"), ("k", "$.k", "{\"***\":1}")],
        ),
        // a numeric token echoed as a number
        (
            "98765432",
            r#"{"esc": "a", "k": {}, "n": 98765432}"#,
            vec![("n", "$.n", "***")],
        ),
    ];
    for (token, raw, points) in cases {
        let (addr, s, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
        st(&s).raw = Some(raw.to_owned());
        let pts: Vec<(&str, Value)> = points
            .iter()
            .map(|(n, p, _)| (*n, pt(p, &[("type", "string".into())])))
            .collect();
        let h = H::start(tree(
            base(addr.port()),
            &[("auth", "bearer".into()), ("token", token.into())],
            &[("d1", dev(&[("path", "/raw".into())], map(&pts)))],
        ))
        .await;
        for (n, _, want) in &points {
            let p = format!("c1/d1/{n}");
            wait(&format!("{p} masked"), || good(&h, &p, (*want).into())).await;
        }
        let (_, v, _) = act(&h, "c1/d1", "try_request", map(&[]), Perm::Config).await;
        let shown = format!("{v:?}");
        assert!(!shown.contains(token) && shown.contains("***"), "{shown}");
        assert!(!shown.contains("\\u0031"), "shown as masked JSON: {shown}");
        let (_, v, _) = act(
            &h,
            "c1/d1",
            "test_selector",
            map(&[("path", "$".into())]),
            Perm::Config,
        )
        .await;
        let shown = format!("{v:?}");
        assert!(!shown.contains(token) && shown.contains("***"), "{shown}");
        h.stop().await;
    }
}

/// `test_selector` replies stay bounded (each value cut at 2 KiB of JSON
/// text, a string value at 8 KiB); a reply over 1 MiB is not kept.
#[tokio::test(flavor = "multi_thread")]
async fn test_selector_is_bounded() {
    let (addr, s, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    let big = "x".repeat(200 * 1024);
    st(&s).raw = Some(format!(r#"{{"s": "{big}", "n": 1}}"#));
    let h = H::start(tree(
        base(addr.port()),
        &[],
        &[(
            "d1",
            dev(&[("path", "/raw".into())], map(&[("p", pt("$.n", &[]))])),
        )],
    ))
    .await;
    wait("polled", || good(&h, "c1/d1/p", Value::Float(1.0))).await;
    let cfg = Perm::Config;
    let args = map(&[("path", "$".into()), ("type", "string".into())]);
    let (r, v, e) = act(&h, "c1/d1", "test_selector", args, cfg).await;
    assert_eq!(r, Some(Status::Ok), "{e}");
    assert_eq!(field(&v, "truncated"), &Value::Bool(true));
    let Value::Array(vs) = field(&v, "values") else {
        panic!("values")
    };
    assert!(matches!(&vs[0], Value::Str(t) if t.len() < 3 * 1024 && t.ends_with('…')));
    assert!(matches!(field(&v, "value"), Value::Str(t) if t.len() < 9 * 1024));
    let args = map(&[("path", "$.n".into())]);
    let (_, v, _) = act(&h, "c1/d1", "test_selector", args, cfg).await;
    assert_eq!(field(&v, "truncated"), &Value::Bool(false));
    // over 1 MiB: polled, but not kept for test_selector
    st(&s).raw = Some(format!(r#"{{"s": "{}", "n": 2}}"#, "y".repeat(1536 * 1024)));
    wait("polled again", || good(&h, "c1/d1/p", Value::Float(2.0))).await;
    let args = map(&[("path", "$.n".into())]);
    let (r, _, e) = act(&h, "c1/d1", "test_selector", args, cfg).await;
    assert_eq!(r, Some(Status::NotAvailable));
    assert!(e.contains("not kept"), "{e}");
    h.stop().await;
}

/// `try_request` on a body that is not JSON: a plain echo is masked; an
/// echo in a JSON escape (an anti-XSSI prefix makes serde refuse the body)
/// hides the body whole. A long numeric secret echoed as a JSON number (an
/// f64 once parsed) is still hidden.
#[tokio::test(flavor = "multi_thread")]
async fn bodies_that_are_not_json_are_masked() {
    let token = "ab/c1-tok";
    let cases = [
        (
            token,
            r#")]}'{"t": "Bearer ab\/c1-tok"}"#,
            None,
            "body hidden",
        ),
        (token, "plain ab/c1-tok text", Some("plain *** text"), "***"),
        (token, "no secret here", Some("no secret here"), "here"),
        (
            "1234567890123456789012",
            r#"{"n": 1234567890123456789012, "m": 7}"#,
            Some(r#"{"m":7,"n":"***"}"#),
            "***",
        ),
    ];
    for (token, raw, want, has) in cases {
        let (addr, s, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
        st(&s).raw = Some(raw.to_owned());
        let h = H::start(tree(
            base(addr.port()),
            &[("auth", "bearer".into()), ("token", token.into())],
            &[(
                "d1",
                dev(
                    &[("path", "/raw".into())],
                    map(&[("p", pt("$.m", &[("poll_s", Value::Float(60.0))]))]),
                ),
            )],
        ))
        .await;
        let (r, v, e) = act(&h, "c1/d1", "try_request", map(&[]), Perm::Config).await;
        assert_eq!(r, Some(Status::Ok), "{e}");
        let Value::Str(body) = field(&v, "body") else {
            panic!("body")
        };
        assert!(!body.contains(token) && !body.contains("c1-tok"), "{body}");
        assert!(!body.contains("23456789012345"), "{body}");
        assert!(body.contains(has), "{body}");
        if let Some(w) = want {
            assert_eq!(body, w);
        }
        h.stop().await;
    }
}

/// A secret hides only the values that hold it: a reading, a string or a
/// member name that only contains its characters stays as it is (review
/// finding 2). A number point equal to the secret fails explicitly.
#[tokio::test(flavor = "multi_thread")]
async fn unrelated_values_stay_intact() {
    let num = |path: &str, extra: &[(&str, Value)]| pt(path, extra);
    let string = |path: &str| pt(path, &[("type", "string".into())]);
    let cases = [
        (
            "1234",
            r#"{"power": 51234.5, "big": 12345, "pin": 1234, "pin_s": " 1234 ",
                "label": "x1234y", "n": [1234, 5]}"#,
            vec![
                ("power", num("$.power", &[]), Some(Value::Float(51234.5))),
                ("big", num("$.big", &[]), Some(Value::Float(12345.0))),
                ("label", string("$.label"), Some("x***y".into())),
                (
                    "cnt",
                    num("$.n[*]", &[("aggregate", "count".into())]),
                    Some(Value::Float(2.0)),
                ),
                ("pin", num("$.pin", &[]), None),
                ("pin_s", num("$.pin_s", &[]), None),
                ("sum", num("$.n[*]", &[("aggregate", "sum".into())]), None),
            ],
        ),
        (
            "admin",
            r#"{"adminState": "up", "role": "administrator",
                "k": {"admin-x": 1, "***-x": 2}}"#,
            vec![
                ("st", string("$.adminState"), Some("up".into())),
                ("role", string("$.role"), Some("***istrator".into())),
            ],
        ),
        (
            // a zero-led PIN echoed as a JSON number (no leading zeros)
            "0123",
            r#"{"pin": 123, "near": 1234, "power": 51234.5, "zero": 0}"#,
            vec![
                ("pin", num("$.pin", &[]), None),
                ("near", num("$.near", &[]), Some(Value::Float(1234.0))),
                ("power", num("$.power", &[]), Some(Value::Float(51234.5))),
                ("zero", num("$.zero", &[]), Some(Value::Float(0.0))),
                ("pin_s", string("$.pin"), Some("***".into())),
            ],
        ),
    ];
    for (password, raw, points) in cases {
        let (addr, s, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
        {
            let mut t = st(&s);
            t.raw = Some(raw.to_owned());
            t.auth = SimAuth::Basic("u".into(), password.into());
        }
        let pts: Vec<(&str, Value)> = points.iter().map(|(n, p, _)| (*n, p.clone())).collect();
        let h = H::start(tree(
            base(addr.port()),
            &[
                ("auth", "basic".into()),
                ("username", "u".into()),
                ("password", password.into()),
            ],
            &[("d1", dev(&[("path", "/raw".into())], map(&pts)))],
        ))
        .await;
        for (n, _, want) in &points {
            let p = format!("c1/d1/{n}");
            match want {
                Some(v) => wait(&p, || good(&h, &p, v.clone())).await,
                None => {
                    wait(&p, || qual(&h, &p) == Some(Quality::Bad)).await;
                    assert_eq!(val(&h, &p), Some(Value::Null), "{p}: no value shown");
                }
            }
        }
        assert_eq!(state(&h, "c1/d1").as_deref(), Some("connected"));
        let sel = |path: &str, ty: Option<&str>| {
            let mut kv = vec![("path", Value::from(path))];
            if let Some(t) = ty {
                kv.push(("type", t.into()));
            }
            map(&kv)
        };
        let cfg = Perm::Config;
        let (_, v, _) = act(&h, "c1/d1", "try_request", map(&[]), cfg).await;
        let body = format!("{:?}", field(&v, "body"));
        if password == "1234" {
            assert!(body.contains("51234.5") && body.contains("12345"), "{body}");
            assert!(!body.contains("5***"), "{body}");
            let (_, v, _) = act(&h, "c1/d1", "test_selector", sel("$.power", None), cfg).await;
            assert_eq!(
                field(&v, "values"),
                &Value::Array(vec![Value::Float(51234.5)])
            );
            let args = sel("$.pin", Some("number"));
            let (_, v, _) = act(&h, "c1/d1", "test_selector", args, cfg).await;
            let e = format!("{:?}", field(&v, "error"));
            assert!(e.contains("value hidden"), "{e}");
            assert!(!format!("{v:?}").contains("1234"), "{v:?}");
        } else if password == "0123" {
            assert!(body.contains("\\\"pin\\\":\\\"***\\\""), "{body}");
            assert!(body.contains("1234") && body.contains("51234.5"), "{body}");
        } else {
            assert!(
                body.contains("***State") && !body.contains("admin"),
                "{body}"
            );
            let args = sel("$.adminState", None);
            let (_, v, _) = act(&h, "c1/d1", "test_selector", args, cfg).await;
            assert_eq!(field(&v, "values"), &Value::Array(vec!["up".into()]));
            // two members that mask alike are both shown
            let (_, v, _) = act(&h, "c1/d1", "test_selector", sel("$.k", None), cfg).await;
            let Value::Array(vs) = field(&v, "values") else {
                panic!("values")
            };
            let Some(Value::Map(k)) = vs.first() else {
                panic!("{vs:?}")
            };
            assert_eq!(k.len(), 2, "{k:?}");
            assert!(!format!("{k:?}").contains("admin"), "{k:?}");
        }
        h.stop().await;
    }
}
