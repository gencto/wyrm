//! The `opcua` link against the in-process OPC UA simulator (`sim`),
//! through the real wire format (`TestHarness`: in-memory Zenoh session)
//! and real OPC UA over TCP on loopback.

use opcua::crypto::{CertificateStore, X509Data};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::OnceLock;
use std::time::Duration;
use wyrm_core::{Perm, Quality, Status, Value};
use wyrm_link_opcua::sim::{self, Options, RelayMode, NS};
use wyrm_link_opcua::Opcua;
use wyrm_link_sdk::driver::Tree;
use wyrm_link_sdk::TestHarness;

type H = TestHarness<Opcua>;

const CLIENT_URI: &str = "urn:wyrm:opcua:client";

fn map(kv: &[(&str, Value)]) -> Value {
    Value::Map(
        kv.iter()
            .map(|(k, v)| ((*k).to_owned(), v.clone()))
            .collect(),
    )
}

// ---------- files ----------

/// A directory removed at the end of the test.
struct Dir(PathBuf);

impl Drop for Dir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

fn dir() -> Dir {
    static N: AtomicU32 = AtomicU32::new(0);
    let d = std::env::temp_dir().join(format!(
        "wyrm-opcua-test-{}-{}",
        std::process::id(),
        N.fetch_add(1, Ordering::Relaxed)
    ));
    let _ = std::fs::remove_dir_all(&d);
    std::fs::create_dir_all(&d).unwrap();
    Dir(d)
}

fn copy_dir(from: &Path, to: &Path) {
    std::fs::create_dir_all(to).unwrap();
    for e in std::fs::read_dir(from).unwrap().flatten() {
        let p = e.path();
        if p.is_dir() {
            copy_dir(&p, &to.join(e.file_name()));
        } else {
            std::fs::copy(&p, to.join(e.file_name())).unwrap();
        }
    }
}

/// RSA keys are slow in debug builds: one server key pair per test binary,
/// copied into each simulator's PKI.
fn server_pki(into: &Path) -> PathBuf {
    static TEMPLATE: OnceLock<PathBuf> = OnceLock::new();
    let t = TEMPLATE.get_or_init(|| {
        let d = std::env::temp_dir().join(format!("wyrm-opcua-srv-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        sim::ensure_server_cert(&d).unwrap();
        d
    });
    let p = into.join("server-pki");
    copy_dir(&t.join("own"), &p.join("own"));
    copy_dir(&t.join("private"), &p.join("private"));
    p
}

/// A certificate (PEM) and key (PEM) for `uri`.
fn keypair(uri: &str) -> (String, String) {
    let d = std::env::temp_dir().join(format!(
        "wyrm-opcua-kp-{}-{}",
        std::process::id(),
        uri.replace(':', "_")
    ));
    let cert = d.join("cert.der");
    let key = d.join("key.pem");
    let alt = X509Data::alt_host_names(uri, Some(vec!["localhost".into()]), false, false, false);
    let data = X509Data {
        key_size: 2048,
        common_name: uri.into(),
        organization: "test".into(),
        organizational_unit: String::new(),
        country: String::new(),
        state: String::new(),
        alt_host_names: alt,
        certificate_duration_days: 30,
    };
    CertificateStore::create_certificate_and_key(&data, true, &cert, &key).unwrap();
    let pem = sim::pem("CERTIFICATE", &std::fs::read(&cert).unwrap());
    let key = std::fs::read_to_string(&key).unwrap();
    let _ = std::fs::remove_dir_all(&d);
    (pem, key)
}

/// The client's application certificate, once per test binary.
fn client_cert() -> &'static (String, String) {
    static C: OnceLock<(String, String)> = OnceLock::new();
    C.get_or_init(|| keypair(CLIENT_URI))
}

/// An X.509 user certificate, once per test binary.
fn user_cert() -> &'static (String, String) {
    static C: OnceLock<(String, String)> = OnceLock::new();
    C.get_or_init(|| keypair("urn:wyrm:test:user"))
}

async fn spawn(d: &Path, tune: impl FnOnce(&mut Options)) -> sim::Sim {
    let mut o = Options {
        pki_dir: server_pki(d),
        ..Default::default()
    };
    tune(&mut o);
    sim::spawn(o).await.unwrap()
}

// ---------- trees ----------

fn pt(node: &str, extra: &[(&str, Value)]) -> Value {
    let mut kv = vec![
        ("node_id", Value::from(node)),
        ("poll_s", Value::Float(0.1)),
    ];
    kv.extend_from_slice(extra);
    map(&kv)
}

fn line(name: &str) -> String {
    format!("s=Line1.{name}")
}

/// `c1/d1` at `url` in the simulator's namespace (by URI) with `points`.
fn tree(url: &str, conn: &[(&str, Value)], dev: &[(&str, Value)], points: Value) -> Tree {
    let mut d = vec![
        ("namespace_uri", Value::from(NS)),
        ("ping_s", Value::Float(0.2)),
        ("points", points),
    ];
    d.extend_from_slice(dev);
    let mut c = vec![
        ("endpoint", Value::from(url)),
        ("request_timeout_ms", Value::UInt(1000)),
        ("connect_timeout_ms", Value::UInt(10_000)),
        ("devices", map(&[("d1", map(&d))])),
    ];
    c.extend_from_slice(conn);
    Tree(map(&[
        ("poll_unsubscribed", Value::Bool(true)),
        ("connections", map(&[("c1", map(&c))])),
    ]))
}

fn secured(extra: &[(&str, Value)]) -> Vec<(&'static str, Value)> {
    let (cert, key) = client_cert();
    let mut v = vec![
        ("security_policy", Value::from("Basic256Sha256")),
        ("security_mode", Value::from("sign_and_encrypt")),
        ("cert_pem", Value::from(cert.as_str())),
        ("key_pem", Value::from(key.as_str())),
    ];
    for (k, x) in extra {
        let k: &'static str = match *k {
            "server_cert_pem" => "server_cert_pem",
            "trust_on_first_use" => "trust_on_first_use",
            "identity" => "identity",
            "username" => "username",
            "password" => "password",
            "user_cert_pem" => "user_cert_pem",
            "user_key_pem" => "user_key_pem",
            "security_mode" => "security_mode",
            other => panic!("{other}"),
        };
        v.retain(|(n, _)| *n != k);
        v.push((k, x.clone()));
    }
    v
}

async fn start_in(tree: Tree, data: &Path) -> H {
    let data = data.to_path_buf();
    H::start_with(tree, move |c| c.data_dir = Some(data)).await
}

// ---------- observing ----------

/// The `status` enum leaf as a state name (`connected`, `failed`, …).
fn state(h: &H, base: &str) -> Option<String> {
    match h.ctx().last(&format!("{base}/status"))?.v {
        Value::UInt(i) => wyrm_link_sdk::driver::NodeState::NAMES
            .get(i as usize)
            .map(|s| (*s).to_owned()),
        _ => None,
    }
}

fn error(h: &H, base: &str) -> String {
    match h.ctx().last(&format!("{base}/error")).map(|s| s.v) {
        Some(Value::Str(s)) => s,
        _ => String::new(),
    }
}

fn val(h: &H, path: &str) -> Option<(Value, Quality)> {
    h.ctx().last(path).map(|s| (s.v, s.q))
}

async fn wait(what: &str, mut f: impl FnMut() -> bool) {
    // Generous: the workspace suite runs many sessions in parallel.
    let deadline = tokio::time::Instant::now() + Duration::from_secs(20);
    while !f() {
        assert!(tokio::time::Instant::now() < deadline, "timeout: {what}");
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
}

async fn connected(h: &H) {
    let deadline = tokio::time::Instant::now() + Duration::from_secs(20);
    while state(h, "c1/d1").as_deref() != Some("connected") {
        assert!(
            tokio::time::Instant::now() < deadline,
            "timeout: connected; c1 {:?}: {}",
            state(h, "c1"),
            error(h, "c1")
        );
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
}

fn status(a: &wyrm_core::Attachment) -> Option<Status> {
    match a.status? {
        wyrm_core::status::StatusCode::Known(s) => Some(s),
        _ => None,
    }
}

/// Invoke at level `config` (browse and get_endpoints are commissioning).
async fn act(h: &H, path: &str, action: &str, args: Value) -> (Option<Status>, Option<Value>) {
    act_as(h, Perm::Config, path, action, args).await
}

async fn act_as(
    h: &H,
    perm: Perm,
    path: &str,
    action: &str,
    args: Value,
) -> (Option<Status>, Option<Value>) {
    let mut r = h.invoke(path, action, args, Some(h.ptok(perm))).await;
    assert_eq!(r.len(), 1, "{path} {action}: one reply");
    let r = r.remove(0);
    (status(&r.att), r.value())
}

// ---------- tests ----------

#[tokio::test(flavor = "multi_thread")]
async fn values_types_and_point_errors() {
    logs();
    let d = dir();
    let s = spawn(&d.0, |_| {}).await;
    let points = map(&[
        ("double", pt(&line("Double"), &[])),
        ("int32", pt(&line("Int32"), &[])),
        ("boolean", pt(&line("Boolean"), &[])),
        ("string", pt(&line("String"), &[])),
        ("array", pt(&line("Array"), &[])),
        ("time", pt(&line("Time"), &[])),
        ("bytes", pt(&line("Bytes"), &[])),
        (
            "scaled",
            pt(
                &line("Int32"),
                &[
                    ("scale", 0.5.into()),
                    ("offset", 1.0.into()),
                    ("unit", "°C".into()),
                ],
            ),
        ),
        ("by_uri", pt(&format!("nsu={NS};s=Line1.Int32"), &[])),
        ("by_index", pt(&format!("ns={};s=Line1.Int32", s.ns), &[])),
        ("std", pt("ns=0;i=2259", &[])),
        ("bad", pt(&line("Bad"), &[])),
        ("uncertain", pt(&line("Uncertain"), &[])),
        ("missing", pt(&line("Nope"), &[])),
        ("bad_ns", pt("nsu=urn:not-there;s=x", &[])),
    ]);
    // no data_dir: security None needs no files
    let h = H::start(tree(&s.url(), &[], &[], points)).await;
    connected(&h).await;
    let good = |p: &str| val(&h, &format!("c1/d1/{p}")).filter(|(_, q)| *q == Quality::Good);
    let all = [
        "double", "int32", "boolean", "string", "array", "time", "bytes", "scaled", "by_uri",
        "by_index", "std",
    ];
    let deadline = tokio::time::Instant::now() + Duration::from_secs(20);
    while !all.iter().all(|p| good(p).is_some()) {
        assert!(
            tokio::time::Instant::now() < deadline,
            "not good: {:?}",
            all.iter()
                .filter(|p| good(p).is_none())
                .map(|p| (p, val(&h, &format!("c1/d1/{p}"))))
                .collect::<Vec<_>>()
        );
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
    assert_eq!(good("int32").unwrap().0, Value::UInt(42));
    assert_eq!(good("by_uri").unwrap().0, Value::UInt(42));
    assert_eq!(good("by_index").unwrap().0, Value::UInt(42));
    assert_eq!(good("boolean").unwrap().0, Value::Bool(true));
    assert_eq!(good("string").unwrap().0, Value::Str("hello".into()));
    assert_eq!(
        good("array").unwrap().0,
        Value::Array(vec![
            Value::Float(1.0),
            Value::Float(2.0),
            Value::Float(3.0)
        ])
    );
    match good("time").unwrap().0 {
        Value::Str(t) => assert!(t.starts_with("2026-10-30T12:00:00"), "{t}"),
        v => panic!("{v:?}"),
    }
    assert_eq!(good("bytes").unwrap().0, Value::Bytes(vec![1, 2, 3]));
    assert_eq!(good("scaled").unwrap().0, Value::Float(42.0 * 0.5 + 1.0));
    assert_eq!(
        good("std").unwrap().0,
        Value::UInt(0),
        "ServerState Running"
    );
    // the changing double moves
    let first = good("double").unwrap().0;
    wait("double changes", || {
        good("double").is_some_and(|(v, _)| v != first)
    })
    .await;
    // a non-Good status is never good: Bad and Uncertain fail the point only
    for p in ["bad", "uncertain", "missing", "bad_ns"] {
        wait(&format!("{p} bad"), || {
            val(&h, &format!("c1/d1/{p}")).is_some_and(|(_, q)| q == Quality::Bad)
        })
        .await;
    }
    assert_eq!(state(&h, "c1/d1").as_deref(), Some("connected"));
    // meta: the type is the server's, a scaled point is a number with a unit
    let (_, m) = h.meta("c1/d1/scaled").await;
    let m = m.unwrap();
    assert_eq!(m.ty, Some(wyrm_core::TypeCode::Number));
    assert!(format!("{:?}", m.unit).contains("°C"), "{:?}", m.unit);
    let (_, m) = h.meta("c1/d1/string").await;
    assert_eq!(m.unwrap().ty, Some(wyrm_core::TypeCode::Dynamic));
    // a node removed on the server fails that point only
    s.remove("Int32");
    wait("removed node bad", || {
        val(&h, "c1/d1/int32").is_some_and(|(_, q)| q == Quality::Bad)
    })
    .await;
    assert!(good("boolean").is_some());
    assert_eq!(state(&h, "c1/d1").as_deref(), Some("connected"));
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn writes_convert_to_the_server_type_and_read_back() {
    let d = dir();
    let s = spawn(&d.0, |_| {}).await;
    let w = [("writable", Value::Bool(true))];
    let points = map(&[
        ("sp", pt(&line("Setpoint"), &w)),
        ("small", pt(&line("Small"), &w)),
        (
            "small_scaled",
            pt(
                &line("Small"),
                &[("writable", Value::Bool(true)), ("scale", 0.1.into())],
            ),
        ),
        ("text", pt(&line("Text"), &w)),
        ("flags", pt(&line("Flags"), &w)),
        ("locked", pt(&line("Locked"), &w)),
        ("ro", pt(&line("Setpoint"), &[])),
        ("matrix", pt(&line("Matrix"), &w)),
    ]);
    let h = H::start(tree(&s.url(), &[], &[], points)).await;
    connected(&h).await;
    wait("sp read", || val(&h, "c1/d1/sp").is_some()).await;
    let set = |p: &'static str, v: Value| {
        let h = &h;
        async move {
            status(
                &h.set(&format!("c1/d1/{p}"), v, Some(h.ptok(Perm::Write)))
                    .await,
            )
        }
    };
    assert_eq!(set("sp", Value::Float(42.5)).await, Some(Status::Ok));
    assert_eq!(s.get("Setpoint"), Some(opcua::types::Variant::Double(42.5)));
    wait("sp read back", || {
        val(&h, "c1/d1/sp").map(|(v, _)| v) == Some(Value::Float(42.5))
    })
    .await;
    // integers: whole numbers in range only
    assert_eq!(set("small", Value::UInt(7)).await, Some(Status::Ok));
    assert_eq!(s.get("Small"), Some(opcua::types::Variant::Int16(7)));
    assert_ne!(set("small", Value::UInt(40_000)).await, Some(Status::Ok));
    assert_ne!(set("small", Value::Float(1.5)).await, Some(Status::Ok));
    assert_ne!(set("small", Value::Str("7".into())).await, Some(Status::Ok));
    assert_eq!(s.get("Small"), Some(opcua::types::Variant::Int16(7)));
    // a scaled write: 2.5 at scale 0.1 is raw 25
    assert_eq!(
        set("small_scaled", Value::Float(2.5)).await,
        Some(Status::Ok)
    );
    assert_eq!(s.get("Small"), Some(opcua::types::Variant::Int16(25)));
    assert_eq!(
        set("text", Value::Str("abc".into())).await,
        Some(Status::Ok)
    );
    assert_eq!(
        s.get("Text"),
        Some(opcua::types::Variant::String("abc".into()))
    );
    assert_eq!(
        set("flags", Value::Array(vec![Value::UInt(1), Value::Int(-2)])).await,
        Some(Status::Ok)
    );
    wait("flags read back", || {
        val(&h, "c1/d1/flags").map(|(v, _)| v)
            == Some(Value::Array(vec![Value::UInt(1), Value::Int(-2)]))
    })
    .await;
    // the server refuses: not writable there
    assert_ne!(set("locked", Value::Float(2.0)).await, Some(Status::Ok));
    assert_eq!(s.get("Locked"), Some(opcua::types::Variant::Double(1.0)));
    // a multi-dimensional node (ValueRank 2): refused, never sent flat
    let before = s.get("Matrix");
    assert_eq!(
        set(
            "matrix",
            Value::Array(vec![Value::Float(9.0), Value::Float(8.0)])
        )
        .await,
        Some(Status::InvalidParameter)
    );
    assert_eq!(s.get("Matrix"), before);
    // read-only in the tree
    assert_ne!(set("ro", Value::Float(1.0)).await, Some(Status::Ok));
    assert_eq!(s.get("Setpoint"), Some(opcua::types::Variant::Double(42.5)));
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn reads_are_batched_by_the_server_limit() {
    let d = dir();
    // The server takes at most 2 nodes per Read; 7 points need 4 requests.
    let s = spawn(&d.0, |o| o.max_nodes_per_read = 2).await;
    let names = [
        "Double", "Int32", "Boolean", "String", "Array", "Time", "Bytes",
    ];
    let points = Value::Map(
        names
            .iter()
            .map(|n| {
                (
                    n.to_lowercase(),
                    pt(&line(n), &[("poll_s", Value::Float(0.5))]),
                )
            })
            .collect(),
    );
    let h = H::start(tree(
        &s.url(),
        &[],
        &[("ping_s", Value::Float(3600.0))],
        points,
    ))
    .await;
    connected(&h).await;
    wait("all points good", || {
        names.iter().all(|n| {
            val(&h, &format!("c1/d1/{}", n.to_lowercase())).is_some_and(|(_, q)| q == Quality::Good)
        })
    })
    .await;
    // diagnostics count the requests: several per poll
    // (published when the node is read)
    let reqs = || match h.ctx().last("c1/d1/requests").map(|s| s.v) {
        Some(Value::UInt(n)) => n,
        _ => 0,
    };
    h.meta("c1/d1").await;
    wait("requests published", || reqs() > 0).await;
    let r0 = reqs();
    tokio::time::sleep(Duration::from_millis(1600)).await;
    h.meta("c1/d1").await;
    // 3 polls at 0.5 s of 4 requests each: at least 8 more
    wait("requests counted", || reqs() >= r0 + 8).await;
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn silent_server_degrades_quality() {
    let d = dir();
    let s = spawn(&d.0, |_| {}).await;
    let r = sim::relay(s.addr).await.unwrap();
    let points = map(&[("int32", pt(&line("Int32"), &[]))]);
    let h = H::start(tree(
        &r.url(),
        &[("request_timeout_ms", Value::UInt(300))],
        &[("ping_s", Value::Float(3600.0))],
        points,
    ))
    .await;
    connected(&h).await;
    wait("good", || {
        val(&h, "c1/d1/int32").is_some_and(|(_, q)| q == Quality::Good)
    })
    .await;
    r.set_mode(RelayMode::Silent);
    let mut seen_uncertain = false;
    wait("uncertain/stale, then bad/comm_fail", || {
        let q = val(&h, "c1/d1/int32").map(|(_, q)| q);
        seen_uncertain |= q == Some(Quality::Uncertain);
        q == Some(Quality::Bad)
    })
    .await;
    assert!(seen_uncertain, "uncertain/stale before bad");
    // the value stays the last one read (never invented)
    assert_eq!(val(&h, "c1/d1/int32").unwrap().0, Value::UInt(42));
    h.stop().await;
}

/// One Read request (chunk) of a poll times out while the other answers:
/// the points of the late chunk take the quality ladder on their own
/// (`uncertain/stale`, then `bad/comm_fail`, last value kept), the points
/// of the chunk that answered stay `good`, and the device stays connected.
/// (Four workers: the simulator's slow read blocks one, and its ticker
/// waits for the address space on another.)
#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn a_timed_out_chunk_goes_stale_while_the_other_answers() {
    let d = dir();
    let s = spawn(&d.0, |_| {}).await;
    // one node per Read request: two chunks, one of them with `Slow`
    let points = map(&[
        (
            "int32",
            pt(&line("Int32"), &[("poll_s", Value::Float(1.0))]),
        ),
        ("slow", pt(&line("Slow"), &[("poll_s", Value::Float(1.0))])),
    ]);
    let h = H::start(tree(
        &s.url(),
        &[("request_timeout_ms", Value::UInt(300))],
        &[
            ("ping_s", Value::Float(3600.0)),
            ("max_nodes_per_read", Value::UInt(1)),
        ],
        points,
    ))
    .await;
    connected(&h).await;
    let good = |h: &H, p: &str| val(h, p).is_some_and(|(_, q)| q == Quality::Good);
    wait("both good", || {
        good(&h, "c1/d1/int32") && good(&h, "c1/d1/slow")
    })
    .await;
    // the Read request that holds `Slow` answers after the request timeout
    s.set_slow(Duration::from_millis(450));
    let mut seen_uncertain = false;
    let deadline = tokio::time::Instant::now() + Duration::from_secs(20);
    loop {
        let q = val(&h, "c1/d1/slow").map(|(_, q)| q);
        seen_uncertain |= q == Some(Quality::Uncertain);
        assert!(
            good(&h, "c1/d1/int32"),
            "the chunk that answered stays good"
        );
        assert_eq!(state(&h, "c1/d1").as_deref(), Some("connected"));
        if q == Some(Quality::Bad) {
            break;
        }
        assert!(
            tokio::time::Instant::now() < deadline,
            "timeout: slow {:?}",
            val(&h, "c1/d1/slow")
        );
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
    assert!(seen_uncertain, "uncertain/stale before bad");
    // the last value read, never invented
    assert_eq!(val(&h, "c1/d1/slow").unwrap().0, Value::Float(7.0));
    s.set_slow(Duration::ZERO);
    wait("good again", || good(&h, "c1/d1/slow")).await;
    assert!(good(&h, "c1/d1/int32"));
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn server_down_fails_the_connection_then_reconnects() {
    let d = dir();
    let s = spawn(&d.0, |_| {}).await;
    let port = s.addr.port();
    let url = s.url();
    let points = map(&[("int32", pt(&line("Int32"), &[]))]);
    let h = H::start(tree(&url, &[], &[], points)).await;
    connected(&h).await;
    wait("good", || {
        val(&h, "c1/d1/int32").is_some_and(|(_, q)| q == Quality::Good)
    })
    .await;
    s.stop().await;
    wait("connection failed", || {
        state(&h, "c1").as_deref() == Some("failed") && !error(&h, "c1").is_empty()
    })
    .await;
    wait("device stopped by parent", || {
        state(&h, "c1/d1").as_deref() == Some("stopped_by_parent")
    })
    .await;
    assert_eq!(val(&h, "c1/d1/int32").unwrap().1, Quality::Bad);
    // the server comes back on the same port, with namespaces reordered:
    // points found by URI keep working
    let s2 = spawn(&d.0, |o| {
        o.port = port;
        o.extra_namespace = true;
    })
    .await;
    assert_ne!(s2.ns, 2, "the namespace index moved");
    connected(&h).await;
    wait("good again", || {
        val(&h, "c1/d1/int32").is_some_and(|(_, q)| q == Quality::Good)
    })
    .await;
    assert_eq!(val(&h, "c1/d1/int32").unwrap().0, Value::UInt(42));
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn dropped_connection_reconnects() {
    let d = dir();
    let s = spawn(&d.0, |_| {}).await;
    let r = sim::relay(s.addr).await.unwrap();
    let points = map(&[("int32", pt(&line("Int32"), &[]))]);
    let h = H::start(tree(&r.url(), &[], &[], points)).await;
    connected(&h).await;
    r.set_mode(RelayMode::Drop);
    wait("connection not connected", || {
        state(&h, "c1").as_deref() != Some("connected")
    })
    .await;
    r.set_mode(RelayMode::Pass);
    connected(&h).await;
    wait("good again", || {
        val(&h, "c1/d1/int32").is_some_and(|(_, q)| q == Quality::Good)
    })
    .await;
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn secured_channel_trust_pin_and_first_use() {
    let d = dir();
    let s = spawn(&d.0, |_| {}).await;
    let points = || map(&[("int32", pt(&line("Int32"), &[]))]);

    // strict: an unknown server certificate is refused, with its thumbprint
    let data = d.0.join("strict");
    let h = start_in(tree(&s.url(), &secured(&[]), &[], points()), &data).await;
    let server_thumb = opcua::crypto::X509::from_pem(s.certificate_pem().as_bytes())
        .unwrap()
        .thumbprint()
        .as_hex_string();
    wait("refused", || error(&h, "c1").contains("not trusted")).await;
    assert!(
        error(&h, "c1").contains(&server_thumb),
        "{}",
        error(&h, "c1")
    );
    // the same advice after retries (the refused certificate is already in
    // rejected/, and the library does not write it again)
    for _ in 0..2 {
        wait("a new attempt", || error(&h, "c1").is_empty()).await;
        wait("refused again", || !error(&h, "c1").is_empty()).await;
    }
    let e = error(&h, "c1");
    assert!(
        e.contains("not trusted") && e.contains(&server_thumb),
        "after retries: {e}"
    );
    h.stop().await;

    // pinned: connected, values good
    let pin = s.certificate_pem();
    let data = d.0.join("pin");
    let h = start_in(
        tree(
            &s.url(),
            &secured(&[("server_cert_pem", pin.as_str().into())]),
            &[],
            points(),
        ),
        &data,
    )
    .await;
    connected(&h).await;
    wait("good", || {
        val(&h, "c1/d1/int32").is_some_and(|(_, q)| q == Quality::Good)
    })
    .await;
    h.stop().await;

    // first use: trusted, then a server with another key is refused
    let data = d.0.join("tofu");
    let tofu = secured(&[("trust_on_first_use", Value::Bool(true))]);
    let h = start_in(tree(&s.url(), &tofu, &[], points()), &data).await;
    connected(&h).await;
    h.stop().await;
    let port = s.addr.port();
    s.stop().await;
    let other = d.0.join("other");
    std::fs::create_dir_all(&other).unwrap();
    let (cert, key) = keypair(sim::APP_URI);
    std::fs::create_dir_all(other.join("own")).unwrap();
    std::fs::create_dir_all(other.join("private")).unwrap();
    // a server with another key pair on the same port
    let der = opcua::crypto::X509::from_pem(cert.as_bytes())
        .unwrap()
        .to_der()
        .unwrap();
    std::fs::write(other.join("own/cert.der"), der).unwrap();
    std::fs::write(other.join("private/private.pem"), key).unwrap();
    let _s2 = sim::spawn(Options {
        port,
        pki_dir: other,
        ..Default::default()
    })
    .await
    .unwrap();
    let h = start_in(
        tree(
            &format!("opc.tcp://127.0.0.1:{port}/"),
            &tofu,
            &[],
            points(),
        ),
        &data,
    )
    .await;
    wait("another server refused", || {
        error(&h, "c1").contains("not trusted")
    })
    .await;
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn generated_certificate_is_shown_when_the_server_refuses_it() {
    let d = dir();
    let s = spawn(&d.0, |o| o.strict_clients = true).await;
    let pin = s.certificate_pem();
    let data = d.0.join("data");
    let conn = vec![
        ("security_policy", Value::from("Basic256Sha256")),
        ("security_mode", Value::from("sign")),
        ("server_cert_pem", Value::from(pin.as_str())),
    ];
    let points = map(&[("int32", pt(&line("Int32"), &[]))]);
    let t0 = std::time::Instant::now();
    let h = start_in(tree(&s.url(), &conn, &[], points), &data).await;
    let deadline = tokio::time::Instant::now() + Duration::from_secs(60);
    while !error(&h, "c1").contains("trust its application certificate") {
        assert!(
            tokio::time::Instant::now() < deadline,
            "refused by the server: {:?} {}",
            state(&h, "c1"),
            error(&h, "c1")
        );
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
    eprintln!("generated + refused after {:?}", t0.elapsed());
    // the generated certificate and its key are in the data_dir
    let own: Vec<_> = std::fs::read_dir(data.join("opcua-pki/own"))
        .unwrap()
        .flatten()
        .map(|e| e.path())
        .collect();
    assert_eq!(own.len(), 1, "{own:?}");
    let thumb = CertificateStore::read_cert(&own[0])
        .unwrap()
        .thumbprint()
        .as_hex_string();
    assert!(error(&h, "c1").contains(&thumb), "{}", error(&h, "c1"));
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let key = std::fs::read_dir(data.join("opcua-pki/private"))
            .unwrap()
            .flatten()
            .next()
            .unwrap()
            .path();
        let mode = std::fs::metadata(key).unwrap().permissions().mode() & 0o777;
        assert_eq!(mode, 0o600);
    }
    assert!(s.rejected_clients() >= 1);
    // the operator trusts it on the server: the next attempt connects
    s.trust_rejected_clients();
    connected(&h).await;
    wait("good", || {
        val(&h, "c1/d1/int32").is_some_and(|(_, q)| q == Quality::Good)
    })
    .await;
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn user_identities_and_secrets() {
    let d = dir();
    let (ucert, ukey) = user_cert();
    let upath = d.0.join("user.der");
    std::fs::write(
        &upath,
        opcua::crypto::X509::from_pem(ucert.as_bytes())
            .unwrap()
            .to_der()
            .unwrap(),
    )
    .unwrap();
    let s = spawn(&d.0, |o| o.x509_user = Some(upath.clone())).await;
    let pin = s.certificate_pem();
    let points = || map(&[("int32", pt(&line("Int32"), &[]))]);

    // user + password over an encrypted channel
    let user = secured(&[
        ("server_cert_pem", pin.as_str().into()),
        ("identity", "username".into()),
        ("username", sim::USER.into()),
        ("password", sim::PASSWORD.into()),
    ]);
    let h = start_in(tree(&s.url(), &user, &[], points()), &d.0.join("u")).await;
    connected(&h).await;
    // secrets never in ~meta
    let (_, m) = h.meta("c1").await;
    let text = format!("{:?}", m.unwrap());
    assert!(!text.contains(sim::PASSWORD), "password in meta");
    assert!(!text.contains("PRIVATE KEY"), "key in meta");
    h.stop().await;

    // a wrong password: refused, and the error does not show it
    let wrong = secured(&[
        ("server_cert_pem", pin.as_str().into()),
        ("identity", "username".into()),
        ("username", sim::USER.into()),
        ("password", "wrong-pass-123".into()),
    ]);
    let h = start_in(tree(&s.url(), &wrong, &[], points()), &d.0.join("w")).await;
    wait("refused", || state(&h, "c1").as_deref() == Some("failed")).await;
    assert!(!error(&h, "c1").contains("wrong-pass-123"));
    h.stop().await;

    // X.509 user identity
    let x = secured(&[
        ("server_cert_pem", pin.as_str().into()),
        ("identity", "certificate".into()),
        ("user_cert_pem", ucert.as_str().into()),
        ("user_key_pem", ukey.as_str().into()),
    ]);
    let h = start_in(tree(&s.url(), &x, &[], points()), &d.0.join("x")).await;
    connected(&h).await;
    wait("good", || {
        val(&h, "c1/d1/int32").is_some_and(|(_, q)| q == Quality::Good)
    })
    .await;
    h.stop().await;

    // a secured connection without a data_dir is refused
    let h = H::start(tree(&s.url(), &secured(&[]), &[], points())).await;
    wait("needs a data_dir", || error(&h, "c1").contains("data_dir")).await;
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn channel_renewal_keeps_values() {
    let d = dir();
    // tokens live 1 s: the client renews its channel about every 0.75 s
    let s = spawn(&d.0, |o| o.channel_lifetime_ms = 1000).await;
    let points = map(&[("double", pt(&line("Double"), &[]))]);
    let pin = s.certificate_pem();
    let conn = secured(&[("server_cert_pem", pin.as_str().into())]);
    let h = start_in(tree(&s.url(), &conn, &[], points), &d.0.join("data")).await;
    connected(&h).await;
    // values keep coming and the connection never leaves `connected`
    let mut last = None;
    let mut changes = 0;
    let until = tokio::time::Instant::now() + Duration::from_secs(3);
    while tokio::time::Instant::now() < until {
        assert_eq!(state(&h, "c1").as_deref(), Some("connected"));
        let v = val(&h, "c1/d1/double");
        if v != last {
            changes += 1;
            last = v;
        }
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
    assert!(changes >= 5, "{changes} changes in 3 s");
    assert_eq!(last.unwrap().1, Quality::Good);
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn browse_and_get_endpoints() {
    let d = dir();
    let s = spawn(&d.0, |_| {}).await;
    let h = H::start(tree(&s.url(), &[], &[], map(&[]))).await;
    connected(&h).await;
    // commissioning: config, not read (they hold the connection and show
    // the server's whole address space)
    let (st, _) = act_as(&h, Perm::Read, "c1/d1", "browse", map(&[])).await;
    assert_eq!(st, Some(Status::PermissionDenied));
    let (st, _) = act_as(&h, Perm::Read, "c1", "get_endpoints", map(&[])).await;
    assert_eq!(st, Some(Status::PermissionDenied));
    // the Objects folder has Line1
    let (st, v) = act(&h, "c1/d1", "browse", map(&[])).await;
    assert_eq!(st, Some(Status::Ok), "{v:?}");
    let names = |v: &Option<Value>| -> Vec<(String, String, String)> {
        let Some(Value::Array(a)) = v else {
            panic!("{v:?}")
        };
        a.iter()
            .map(|e| {
                let Value::Map(m) = e else { panic!("{e:?}") };
                let s = |k: &str| match m.get(k) {
                    Some(Value::Str(s)) => s.clone(),
                    o => panic!("{k}: {o:?}"),
                };
                (s("browse_name"), s("node_class"), s("data_type"))
            })
            .collect()
    };
    assert!(
        names(&v)
            .iter()
            .any(|(n, c, _)| n == "Line1" && c == "Object"),
        "{v:?}"
    );
    // two levels: Line1's variables with their data types
    let (st, v) = act(
        &h,
        "c1/d1",
        "browse",
        map(&[("node", "i=85".into()), ("depth", Value::UInt(2))]),
    )
    .await;
    assert_eq!(st, Some(Status::Ok));
    let n = names(&v);
    assert!(
        n.contains(&("Double".into(), "Variable".into(), "Double".into())),
        "{n:?}"
    );
    assert!(
        n.contains(&("Int32".into(), "Variable".into(), "Int32".into())),
        "{n:?}"
    );
    // the folder itself, by the device's namespace
    let (st, v) = act(
        &h,
        "c1/d1",
        "browse",
        map(&[
            ("node", format!("nsu={NS};s=Line1").into()),
            ("limit", Value::UInt(3)),
        ]),
    )
    .await;
    assert_eq!(st, Some(Status::Ok));
    assert_eq!(names(&v).len(), 3, "limit");
    // a node reached by two references is listed once
    let (st, v) = act(
        &h,
        "c1/d1",
        "browse",
        map(&[("node", format!("nsu={NS};s=Line1").into())]),
    )
    .await;
    assert_eq!(st, Some(Status::Ok));
    let Some(Value::Array(all)) = &v else {
        panic!("{v:?}")
    };
    let mut ids: Vec<String> = all
        .iter()
        .map(|e| match e {
            Value::Map(m) => format!("{:?}", m.get("node_id")),
            o => panic!("{o:?}"),
        })
        .collect();
    let n = ids.len();
    ids.sort();
    ids.dedup();
    assert_eq!(ids.len(), n, "no node twice: {v:?}");
    // bounds
    let (st, _) = act(&h, "c1/d1", "browse", map(&[("depth", Value::UInt(9))])).await;
    assert_eq!(st, Some(Status::InvalidParameter));
    let (st, _) = act(&h, "c1/d1", "browse", map(&[("node", "nonsense".into())])).await;
    assert_eq!(st, Some(Status::InvalidParameter));
    // endpoints of the server
    let (st, v) = act(&h, "c1", "get_endpoints", map(&[])).await;
    assert_eq!(st, Some(Status::Ok));
    let Some(Value::Array(eps)) = v else {
        panic!("{v:?}")
    };
    assert_eq!(eps.len(), 3, "{eps:?}");
    let text = format!("{eps:?}");
    assert!(
        text.contains("Basic256Sha256") && text.contains("sign_and_encrypt"),
        "{text}"
    );
    assert!(text.contains("username"), "{text}");
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn add_connection_checks_params() {
    let h = H::start(Tree(map(&[("poll_unsubscribed", Value::Bool(true))]))).await;
    let add = |args: Value| {
        let h = &h;
        async move {
            let mut r = h
                .invoke("", "add_connection", args, Some(h.ptok(Perm::Config)))
                .await;
            status(&r.remove(0).att)
        }
    };
    for bad in [
        map(&[("name", "c".into())]),
        map(&[("name", "c".into()), ("endpoint", "tcp://x".into())]),
        map(&[
            ("name", "c".into()),
            ("endpoint", "opc.tcp://h:1/".into()),
            ("request_timeout_ms", Value::UInt(10)),
        ]),
        map(&[
            ("name", "c".into()),
            ("endpoint", "opc.tcp://h:1/".into()),
            ("security_policy", "Basic256Sha256".into()),
        ]),
        // a password without channel security to another host, whatever
        // the server would advertise
        map(&[
            ("name", "c".into()),
            ("endpoint", "opc.tcp://plc1:4840/".into()),
            ("identity", "username".into()),
            ("username", "u".into()),
            ("password", "p".into()),
        ]),
        // user info hides the real host
        map(&[
            ("name", "c".into()),
            ("endpoint", "opc.tcp://127.0.0.1@plc1:4840/".into()),
        ]),
        map(&[
            ("name", "c".into()),
            ("endpoint", "opc.tcp://plc1:4840/?x".into()),
        ]),
    ] {
        assert_eq!(
            add(bad.clone()).await,
            Some(Status::InvalidParameter),
            "{bad:?}"
        );
    }
    assert_eq!(
        add(map(&[
            ("name", "c".into()),
            ("endpoint", "opc.tcp://127.0.0.1:1/".into())
        ]))
        .await,
        Some(Status::Ok)
    );
    h.stop().await;
}

/// A secured connection added at runtime (`add_connection`, then
/// `add_device` and `add_point`) finds the link's PKI directory: the
/// parse runs with the `data_dir` in scope.
#[tokio::test(flavor = "multi_thread")]
async fn secured_connection_added_at_runtime() {
    let d = dir();
    let s = spawn(&d.0, |_| {}).await;
    let data = d.0.join("data");
    let h = start_in(
        Tree(map(&[("poll_unsubscribed", Value::Bool(true))])),
        &data,
    )
    .await;
    let pin = s.certificate_pem();
    let mut args = vec![
        ("name", Value::from("c1")),
        ("endpoint", Value::from(s.url().as_str())),
        ("request_timeout_ms", Value::UInt(1000)),
    ];
    args.extend(secured(&[("server_cert_pem", pin.as_str().into())]));
    let call = |path: &'static str, action: &'static str, args: Value| {
        let h = &h;
        async move {
            let mut r = h
                .invoke(path, action, args, Some(h.ptok(Perm::Config)))
                .await;
            status(&r.remove(0).att)
        }
    };
    assert_eq!(
        call("", "add_connection", map(&args)).await,
        Some(Status::Ok)
    );
    assert_eq!(
        call(
            "c1",
            "add_device",
            map(&[
                ("name", "d1".into()),
                ("namespace_uri", NS.into()),
                ("ping_s", Value::Float(0.2)),
            ])
        )
        .await,
        Some(Status::Ok)
    );
    assert_eq!(
        call(
            "c1/d1",
            "add_point",
            map(&[
                ("name", "int32".into()),
                ("node_id", line("Int32").as_str().into()),
                ("poll_s", Value::Float(0.1)),
            ])
        )
        .await,
        Some(Status::Ok)
    );
    connected(&h).await;
    wait("good", || {
        val(&h, "c1/d1/int32").is_some_and(|(_, q)| q == Quality::Good)
    })
    .await;
    assert!(data.join("opcua-pki/servers").is_dir());
    h.stop().await;
}

/// Replies later than the request timeout: the points go stale, and a late
/// reply is never taken for a later request (the library matches request
/// handles), so each point shows its own value once replies are fast again.
#[tokio::test(flavor = "multi_thread")]
async fn slow_replies_go_stale_and_late_replies_are_dropped() {
    let d = dir();
    let s = spawn(&d.0, |_| {}).await;
    let r = sim::relay(s.addr).await.unwrap();
    // two poll periods: two Read requests one after the other
    let points = map(&[
        ("int32", pt(&line("Int32"), &[])),
        (
            "boolean",
            pt(&line("Boolean"), &[("poll_s", Value::Float(0.15))]),
        ),
    ]);
    let h = H::start(tree(
        &r.url(),
        &[("request_timeout_ms", Value::UInt(300))],
        &[("ping_s", Value::Float(3600.0))],
        points,
    ))
    .await;
    connected(&h).await;
    let both_good = |h: &H| {
        val(h, "c1/d1/int32").is_some_and(|(_, q)| q == Quality::Good)
            && val(h, "c1/d1/boolean").is_some_and(|(_, q)| q == Quality::Good)
    };
    wait("good", || both_good(&h)).await;
    r.set_delay(Duration::from_millis(600));
    wait("stale", || {
        val(&h, "c1/d1/int32").is_some_and(|(_, q)| q != Quality::Good)
    })
    .await;
    r.set_delay(Duration::ZERO);
    connected(&h).await;
    wait("good again", || both_good(&h)).await;
    for _ in 0..10 {
        assert_eq!(val(&h, "c1/d1/int32").unwrap().0, Value::UInt(42));
        assert_eq!(val(&h, "c1/d1/boolean").unwrap().0, Value::Bool(true));
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
    h.stop().await;
}

/// Logs of a test run: `RUST_LOG=…`.
#[allow(dead_code)]
fn logs() {
    let _ = tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .with_test_writer()
        .try_init();
}
