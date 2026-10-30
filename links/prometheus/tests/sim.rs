//! The `prometheus` driver against its in-process exporter simulator,
//! through the real wire format (`TestHarness`: in-memory Zenoh session,
//! real HTTP on loopback).

use std::sync::Arc;
use std::time::Duration;
use tokio::net::{TcpListener, TcpStream};
use wyrm_core::{Perm, Quality, Status, Value};
use wyrm_link_sdk::driver::Tree;
use wyrm_link_sdk::TestHarness;

use wyrm_link_prometheus::sim::{self, Fail, Shared};
use wyrm_link_prometheus::Prometheus;

type H = TestHarness<Prometheus>;

fn map(kv: &[(&str, Value)]) -> Value {
    Value::Map(
        kv.iter()
            .map(|(k, v)| ((*k).to_owned(), v.clone()))
            .collect(),
    )
}

fn pt(selector: &str, extra: &[(&str, Value)]) -> Value {
    let mut kv = vec![("selector", Value::Str(selector.into()))];
    kv.extend_from_slice(extra);
    map(&kv)
}

fn dev(labels: &str, points: Value) -> Value {
    map(&[("labels", labels.into()), ("points", points)])
}

/// `c1` on `url` (scrape every second, 500 ms timeout) with `devices`.
fn tree_url(url: &str, extra: &[(&str, Value)], devices: Value) -> Tree {
    let mut kv = vec![
        ("url", Value::Str(url.into())),
        ("scrape_s", Value::Float(1.0)),
        ("timeout_ms", Value::UInt(500)),
    ];
    kv.extend_from_slice(extra);
    kv.push(("devices", devices));
    Tree(map(&[
        // Tests have no subscribers; poll anyway.
        ("poll_unsubscribed", Value::Bool(true)),
        ("connections", map(&[("c1", map(&kv))])),
    ]))
}

fn tree(port: u16, extra: &[(&str, Value)], devices: Value) -> Tree {
    tree_url(&format!("http://127.0.0.1:{port}/metrics"), extra, devices)
}

/// One device `d1` without a filter and one gauge point `t`.
fn simple(port: u16, extra: &[(&str, Value)]) -> Tree {
    tree(
        port,
        extra,
        map(&[(
            "d1",
            dev(
                "",
                map(&[("t", pt("sim_temperature_celsius{instance=\"a\"}", &[]))]),
            ),
        )]),
    )
}

/// The `status` enum leaf as a state name (`connected`, `failed`, …).
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

/// A point's value while its quality is good.
fn good(h: &H, p: &str) -> Option<f64> {
    let s = h.ctx().last(p)?;
    match (s.q, s.v) {
        (Quality::Good, Value::Float(f)) => Some(f),
        _ => None,
    }
}

fn quality(h: &H, p: &str) -> Option<Quality> {
    h.ctx().last(p).map(|s| s.q)
}

async fn wait(what: &str, mut f: impl FnMut() -> bool) {
    // Generous: the workspace suite runs many sessions in parallel.
    let deadline = tokio::time::Instant::now() + Duration::from_secs(15);
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

async fn act(h: &H, path: &str, action: &str, args: Value) -> Option<Status> {
    h.invoke(path, action, args, Some(h.ptok(Perm::Config)))
        .await
        .first()
        .and_then(|r| status(&r.att))
}

fn exporter(s: &Shared) -> std::sync::MutexGuard<'_, sim::Exporter> {
    s.lock().unwrap()
}

fn near(a: Option<f64>, b: f64) -> bool {
    a.is_some_and(|a| (a - b).abs() < 1e-9)
}

#[tokio::test(flavor = "multi_thread")]
async fn values_selectors_and_aggregates() {
    let (addr, _e, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    let temp = "sim_temperature_celsius";
    let all = map(&[
        ("max", pt(temp, &[("aggregate", "max".into())])),
        ("avg", pt(temp, &[("aggregate", "avg".into())])),
        ("count", pt(temp, &[("aggregate", "count".into())])),
        ("min", pt(temp, &[("aggregate", "min".into())])),
        (
            "re",
            pt(
                "sim_temperature_celsius{instance=~\"a|b\", sensor!~\"x.*\"}",
                &[("aggregate", "sum".into())],
            ),
        ),
        ("two", pt(temp, &[])),
        ("missing", pt("sim_nope", &[])),
        (
            "missing_count",
            pt("sim_nope", &[("aggregate", "count".into())]),
        ),
        ("req_b", pt("sim_requests_total{path=\"/b\"}", &[])),
        ("p50", pt("sim_rpc_seconds{quantile=\"0.5\"}", &[])),
        ("rpc_count", pt("sim_rpc_seconds_count", &[])),
        ("bucket", pt("sim_latency_seconds_bucket{le=\"0.5\"}", &[])),
        ("hsum", pt("sim_latency_seconds_sum", &[])),
        (
            "hq",
            pt(
                "sim_latency_seconds",
                &[
                    ("function", "histogram_quantile".into()),
                    ("q", Value::Float(0.75)),
                ],
            ),
        ),
        (
            "escaped",
            pt(r#"sim_escaped{text="a \"quoted\" \\ value\nnext"}"#, &[]),
        ),
        ("nan", pt("sim_nan", &[])),
        (
            "scaled",
            pt(
                "sim_temperature_celsius{instance=\"a\"}",
                &[("scale", Value::Float(10.0)), ("offset", Value::Float(1.0))],
            ),
        ),
    ]);
    let devices = map(&[
        (
            "a",
            dev(
                "instance=\"a\"",
                map(&[("temp", pt(temp, &[("unit", "°C".into())]))]),
            ),
        ),
        (
            "b",
            dev("{instance=\"b\"}", map(&[("temp", pt(temp, &[]))])),
        ),
        ("all", dev("", all)),
    ]);
    let h = H::start(tree(addr.port(), &[], devices)).await;
    wait("values", || {
        good(&h, "c1/all/hq").is_some() && good(&h, "c1/b/temp").is_some()
    })
    .await;
    // one scrape feeds every device; the device filter picks the series
    assert_eq!(good(&h, "c1/a/temp"), Some(21.5));
    assert_eq!(good(&h, "c1/b/temp"), Some(19.0));
    assert_eq!(good(&h, "c1/all/max"), Some(21.5));
    assert_eq!(good(&h, "c1/all/min"), Some(19.0));
    assert_eq!(good(&h, "c1/all/avg"), Some(20.25));
    assert_eq!(good(&h, "c1/all/count"), Some(2.0));
    assert_eq!(good(&h, "c1/all/re"), Some(40.5));
    assert_eq!(good(&h, "c1/all/missing_count"), Some(0.0));
    assert!(good(&h, "c1/all/req_b").is_some());
    assert_eq!(good(&h, "c1/all/p50"), Some(0.05));
    assert_eq!(good(&h, "c1/all/rpc_count"), Some(100.0));
    assert_eq!(good(&h, "c1/all/bucket"), Some(20.0));
    assert_eq!(good(&h, "c1/all/hsum"), Some(4.5));
    assert!(
        near(good(&h, "c1/all/hq"), 0.3),
        "{:?}",
        good(&h, "c1/all/hq")
    );
    assert_eq!(good(&h, "c1/all/escaped"), Some(1.0));
    assert_eq!(good(&h, "c1/all/scaled"), Some(216.0));
    // point errors stay with their points; the device answered
    for p in ["two", "missing", "nan"] {
        let path = format!("c1/all/{p}");
        wait(&format!("{p} bad"), || {
            quality(&h, &path) == Some(Quality::Bad)
        })
        .await;
    }
    assert_eq!(state(&h, "c1/all").as_deref(), Some("connected"));
    assert_eq!(state(&h, "c1").as_deref(), Some("connected"));
    // meta: unit, read-only
    let (_, m) = h.meta("c1/a/temp").await;
    assert!(format!("{m:?}").contains("°C"), "{m:?}");
    // points are read-only: a write is refused, nothing changes
    let att = h.set("c1/a/temp", 1.0, Some(h.ptok(Perm::Write))).await;
    assert_ne!(status(&att), Some(Status::Ok));
    assert_eq!(good(&h, "c1/a/temp"), Some(21.5));
    h.stop().await;
}

/// The scrape runs once per connection per `scrape_s`, whatever the number
/// of devices and points.
#[tokio::test(flavor = "multi_thread")]
async fn one_scrape_per_interval() {
    let (addr, e, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    let points = || {
        map(&[
            (
                "t",
                pt("sim_temperature_celsius", &[("aggregate", "max".into())]),
            ),
            (
                "r",
                pt("sim_requests_total", &[("aggregate", "sum".into())]),
            ),
        ])
    };
    let devices = map(&[
        ("d1", dev("", points())),
        ("d2", dev("", points())),
        ("d3", dev("", points())),
    ]);
    let h = H::start(tree(
        addr.port(),
        &[("scrape_s", Value::Float(2.0))],
        devices,
    ))
    .await;
    wait("values", || {
        good(&h, "c1/d1/t").is_some() && good(&h, "c1/d3/r").is_some()
    })
    .await;
    let r0 = exporter(&e).requests;
    tokio::time::sleep(Duration::from_millis(8_200)).await;
    let n = exporter(&e).requests - r0;
    assert!((3..=5).contains(&n), "{n} scrapes in 8.2 s at scrape_s 2");
    h.stop().await;
}

/// A failing endpoint: one attempt per round of polls, not one per device
/// (each attempt takes the whole timeout here).
#[tokio::test(flavor = "multi_thread")]
async fn failed_scrapes_are_shared_by_devices() {
    let (addr, e, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    let names = ["d1", "d2", "d3", "d4", "d5"];
    let devices = Value::Map(
        names
            .iter()
            .map(|d| {
                (
                    (*d).to_owned(),
                    dev(
                        "",
                        map(&[(
                            "t",
                            pt("sim_temperature_celsius", &[("aggregate", "max".into())]),
                        )]),
                    ),
                )
            })
            .collect(),
    );
    let h = H::start(tree(
        addr.port(),
        &[("timeout_ms", Value::UInt(550))],
        devices,
    ))
    .await;
    wait("values", || {
        names
            .iter()
            .all(|d| good(&h, &format!("c1/{d}/t")).is_some())
    })
    .await;
    exporter(&e).fail = Fail::Silent;
    wait("all bad", || {
        names
            .iter()
            .all(|d| quality(&h, &format!("c1/{d}/t")) == Some(Quality::Bad))
    })
    .await;
    let r0 = exporter(&e).requests;
    tokio::time::sleep(Duration::from_millis(6_000)).await;
    let n = exporter(&e).requests - r0;
    // one per second; one per device would keep the owner busy: about 10
    assert!((3..=8).contains(&n), "{n} attempts in 6 s with 5 devices");
    for d in names {
        assert_eq!(state(&h, &format!("c1/{d}")).as_deref(), Some("failed"));
    }
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn rate_per_s_counter_reset_and_histogram_rate() {
    let (addr, e, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    let rate = [("mode", Value::Str("rate_per_s".into()))];
    let hq = |mode: &str| {
        pt(
            "sim_latency_seconds_bucket",
            &[
                ("function", "histogram_quantile".into()),
                ("q", Value::Float(0.5)),
                ("mode", mode.into()),
            ],
        )
    };
    let devices = map(&[(
        "d1",
        dev(
            "",
            map(&[
                ("a", pt("sim_requests_total{path=\"/a\"}", &rate)),
                (
                    "both",
                    pt(
                        "sim_requests_total",
                        &[rate[0].clone(), ("aggregate", "sum".into())],
                    ),
                ),
                ("hq_raw", hq("raw")),
                ("hq_rate", hq("rate_per_s")),
            ]),
        ),
    )]);
    let h = H::start(tree(addr.port(), &[], devices)).await;
    // +1 per scrape, one scrape per second: about 1/s; /a and /b: 3/s
    wait("rate", || {
        good(&h, "c1/d1/a").is_some_and(|r| (0.4..2.5).contains(&r))
            && good(&h, "c1/d1/both").is_some_and(|r| (1.2..7.5).contains(&r))
    })
    .await;
    // a reset (the exporter restarted): never a negative rate
    exporter(&e).counter_a = 0.0;
    for _ in 0..30 {
        if let Some(r) = good(&h, "c1/d1/a") {
            assert!(r >= 0.0, "rate {r} after a reset");
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
    // histogram over the last interval vs since the start
    wait("raw quantile", || near(good(&h, "c1/d1/hq_raw"), 0.1)).await;
    exporter(&e).buckets = [10.0, 30.0, 40.0, 40.0];
    wait("quantiles after new observations", || {
        near(good(&h, "c1/d1/hq_raw"), 0.3) && near(good(&h, "c1/d1/hq_rate"), 0.5)
    })
    .await;
    h.stop().await;
}

/// No answer: `uncertain/stale`, then `bad/comm_fail` with the device
/// failed; the connection stays up. Then recovery.
#[tokio::test(flavor = "multi_thread")]
async fn silent_endpoint_degrades_quality() {
    let (addr, e, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    let h = H::start(simple(addr.port(), &[("timeout_ms", Value::UInt(300))])).await;
    wait("good value", || good(&h, "c1/d1/t").is_some()).await;
    exporter(&e).fail = Fail::Silent;
    wait("uncertain/stale", || {
        quality(&h, "c1/d1/t") == Some(Quality::Uncertain)
    })
    .await;
    wait("bad/comm_fail", || {
        quality(&h, "c1/d1/t") == Some(Quality::Bad)
    })
    .await;
    assert_eq!(state(&h, "c1/d1").as_deref(), Some("failed"));
    assert!(error(&h, "c1/d1").is_some_and(|e| e.contains("300 ms")));
    assert_eq!(state(&h, "c1").as_deref(), Some("connected"));
    exporter(&e).fail = Fail::None;
    wait("recovered", || {
        good(&h, "c1/d1/t").is_some() && state(&h, "c1/d1").as_deref() == Some("connected")
    })
    .await;
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn http_500_and_slow_body_are_device_misses() {
    let (addr, e, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    let h = H::start(simple(addr.port(), &[("timeout_ms", Value::UInt(400))])).await;
    wait("good value", || good(&h, "c1/d1/t").is_some()).await;
    exporter(&e).fail = Fail::Error500;
    wait("bad after 500s", || {
        quality(&h, "c1/d1/t") == Some(Quality::Bad)
    })
    .await;
    assert!(
        error(&h, "c1/d1").is_some_and(|e| e.contains("HTTP 500")),
        "{:?}",
        error(&h, "c1/d1")
    );
    assert_eq!(state(&h, "c1").as_deref(), Some("connected"));
    exporter(&e).fail = Fail::None;
    wait("recovered", || good(&h, "c1/d1/t").is_some()).await;
    // a body slower than the timeout
    exporter(&e).fail = Fail::SlowBody;
    wait("bad after slow bodies", || {
        quality(&h, "c1/d1/t") == Some(Quality::Bad)
    })
    .await;
    assert_eq!(state(&h, "c1/d1").as_deref(), Some("failed"));
    h.stop().await;
}

/// A broken connection: the connection fails with its reason, the devices
/// are stopped by their parent, points `bad`; it reconnects.
#[tokio::test(flavor = "multi_thread")]
async fn disconnect_fails_the_connection_and_reconnects() {
    let (addr, e, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    let h = H::start(simple(addr.port(), &[])).await;
    wait("good value", || good(&h, "c1/d1/t").is_some()).await;
    exporter(&e).fail = Fail::Disconnect;
    wait("connection failed", || {
        state(&h, "c1").as_deref() == Some("failed")
    })
    .await;
    assert!(error(&h, "c1").is_some());
    wait("device stopped by parent", || {
        state(&h, "c1/d1").as_deref() == Some("stopped_by_parent")
    })
    .await;
    assert_eq!(quality(&h, "c1/d1/t"), Some(Quality::Bad));
    exporter(&e).fail = Fail::None;
    wait("reconnected", || {
        state(&h, "c1").as_deref() == Some("connected") && good(&h, "c1/d1/t").is_some()
    })
    .await;
    assert!(error(&h, "c1").is_none());
    // the endpoint is gone: connection refused
    let (addr2, _e2, task2) = sim::spawn("127.0.0.1:0").await.unwrap();
    task2.abort();
    tokio::time::sleep(Duration::from_millis(100)).await;
    h.stop().await;
    let h = H::start(simple(addr2.port(), &[])).await;
    wait("refused", || {
        error(&h, "c1").is_some_and(|e| e.contains("connect"))
    })
    .await;
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn oversized_body_and_too_many_series_are_connection_errors() {
    let (addr, e, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    {
        let mut x = exporter(&e);
        x.fail = Fail::Oversize;
        x.oversize_bytes = 2 * 1024 * 1024;
    }
    let h = H::start(simple(
        addr.port(),
        &[
            ("max_body_mib", Value::UInt(1)),
            ("timeout_ms", Value::UInt(5000)),
        ],
    ))
    .await;
    wait("over max_body_mib", || {
        error(&h, "c1").is_some_and(|e| e.contains("max_body_mib"))
    })
    .await;
    assert_eq!(state(&h, "c1").as_deref(), Some("failed"));
    h.stop().await;
    // a gzip body that inflates past the bound (lots of identical lines)
    {
        let mut x = exporter(&e);
        x.fail = Fail::None;
        x.extra = vec![
            "sim_filler{a=\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"} 1".into();
            40_000
        ];
    }
    let h = H::start(simple(addr.port(), &[("max_body_mib", Value::UInt(1))])).await;
    wait("inflated over max_body_mib", || {
        error(&h, "c1").is_some_and(|e| e.contains("max_body_mib"))
    })
    .await;
    h.stop().await;
    exporter(&e).extra.clear();
    let h = H::start(simple(addr.port(), &[("max_series", Value::UInt(5))])).await;
    wait("over max_series", || {
        error(&h, "c1").is_some_and(|e| e.contains("max_series"))
    })
    .await;
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn malformed_lines_are_skipped_and_counted() {
    let (addr, e, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    exporter(&e).fail = Fail::Malformed;
    let h = H::start(simple(addr.port(), &[])).await;
    wait("good value", || good(&h, "c1/d1/t").is_some()).await;
    h.meta("c1").await;
    wait(
        "parse_errors counted",
        || matches!(h.ctx().last("c1/parse_errors").map(|s| s.v), Some(Value::UInt(n)) if n >= 3),
    )
    .await;
    assert!(matches!(
        h.ctx().last("c1/requests").map(|s| s.v),
        Some(Value::UInt(n)) if n >= 1
    ));
    h.stop().await;
}

/// Bearer token and extra headers on the request; gzip when accepted;
/// the token never shows in `~meta` or `export`; a wrong one fails.
#[tokio::test(flavor = "multi_thread")]
async fn auth_headers_and_gzip() {
    let (addr, e, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    exporter(&e).require_auth = Some("Bearer tok-1234567".into());
    let extra = [
        ("bearer_token", Value::Str("tok-1234567".into())),
        ("headers", "X-Scope-OrgID: plant\nX-Other: 1".into()),
    ];
    let h = H::start(simple(addr.port(), &extra)).await;
    wait("good value", || good(&h, "c1/d1/t").is_some()).await;
    {
        let x = exporter(&e);
        let has = |n: &str, v: &str| {
            x.last_headers
                .iter()
                .any(|(k, val)| k == n && val.contains(v))
        };
        assert!(has("accept-encoding", "gzip"));
        assert!(has("x-scope-orgid", "plant"));
        assert!(has("authorization", "Bearer"));
        assert!(has("accept", "openmetrics"));
    }
    let (_, m) = h.meta("c1").await;
    assert!(!format!("{m:?}").contains("tok-1234567"), "~meta hides it");
    let export = h
        .invoke("c1", "export", map(&[]), Some(h.ptok(Perm::Config)))
        .await;
    let exported = format!("{:?}", export.first().and_then(|r| r.value()));
    assert!(exported.contains("X-Scope-OrgID"), "{exported}");
    assert!(!exported.contains("tok-1234567"), "{exported}");
    h.stop().await;
    // without gzip: identity body
    let mut no_gzip = extra.to_vec();
    no_gzip.push(("gzip", Value::Bool(false)));
    let h = H::start(simple(addr.port(), &no_gzip)).await;
    wait("good value", || good(&h, "c1/d1/t").is_some()).await;
    assert!(!exporter(&e)
        .last_headers
        .iter()
        .any(|(k, _)| k == "accept-encoding"));
    h.stop().await;
    // a wrong token: the first scrape fails the connection
    let h = H::start(simple(
        addr.port(),
        &[("bearer_token", Value::Str("wrong".into()))],
    ))
    .await;
    wait("refused", || {
        error(&h, "c1").is_some_and(|e| e.contains("HTTP 401"))
    })
    .await;
    h.stop().await;
    // basic auth
    exporter(&e).require_auth = Some("Basic dXNlcjpwYXNz".into());
    let h = H::start(simple(
        addr.port(),
        &[("username", "user".into()), ("password", "pass".into())],
    ))
    .await;
    wait("basic auth", || good(&h, "c1/d1/t").is_some()).await;
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn params_are_checked() {
    let (addr, _e, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    let h = H::start(simple(addr.port(), &[])).await;
    wait("good value", || good(&h, "c1/d1/t").is_some()).await;
    let url = format!("http://127.0.0.1:{}/metrics", addr.port());
    let conn = |extra: &[(&str, Value)]| {
        let mut kv = vec![
            ("name", Value::Str("c2".into())),
            ("url", url.clone().into()),
        ];
        kv.extend_from_slice(extra);
        map(&kv)
    };
    let invalid = Some(Status::InvalidParameter);
    for (why, extra) in [
        ("timeout below 100", vec![("timeout_ms", Value::UInt(50))]),
        ("scrape below 1 s", vec![("scrape_s", Value::Float(0.5))]),
        ("scrape above 1 h", vec![("scrape_s", Value::Float(3601.0))]),
        ("body above 64 MiB", vec![("max_body_mib", Value::UInt(65))]),
        ("series 0", vec![("max_series", Value::UInt(0))]),
        ("not http", vec![("url", "ftp://h/metrics".into())]),
        ("user info", vec![("url", "http://u:p@127.0.0.1/".into())]),
        (
            "plaintext token far away",
            vec![
                ("url", "http://192.0.2.1:9100/metrics".into()),
                ("bearer_token", "t".into()),
            ],
        ),
        (
            "basic and bearer",
            vec![
                ("username", "u".into()),
                ("password", "p".into()),
                ("bearer_token", "t".into()),
            ],
        ),
        ("password without user", vec![("password", "p".into())]),
        (
            "authorization header",
            vec![("headers", "Authorization: Bearer x".into())],
        ),
        ("ca_pem over http", vec![("ca_pem", "x".into())]),
        (
            "bad ca_pem",
            vec![
                ("url", "https://127.0.0.1/".into()),
                (
                    "ca_pem",
                    "-----BEGIN CERTIFICATE-----\nnope\n-----END CERTIFICATE-----\n".into(),
                ),
            ],
        ),
        (
            "cert without key",
            vec![
                ("url", "https://127.0.0.1/".into()),
                ("cert_pem", "x".into()),
            ],
        ),
    ] {
        assert_eq!(
            act(&h, "", "add_connection", conn(&extra)).await,
            invalid,
            "{why}"
        );
    }
    assert_eq!(
        act(
            &h,
            "",
            "add_connection",
            conn(&[("bearer_token", "t".into())])
        )
        .await,
        Some(Status::Ok),
        "a token over plaintext to loopback is allowed"
    );
    let (_, m) = h.meta("c2").await;
    let m = m.expect("meta");
    assert!(m.cfg_value("bearer_token").is_none() && m.cfg_value("url").is_some());
    // devices and points
    let add_dev = |labels: &str| map(&[("name", "d2".into()), ("labels", labels.into())]);
    assert_eq!(
        act(&h, "c1", "add_device", add_dev("a=~\"(\"")).await,
        invalid
    );
    assert_eq!(
        act(&h, "c1", "add_device", add_dev("up{a=\"b\"}")).await,
        invalid
    );
    let add_pt = |kv: &[(&str, Value)]| {
        let mut v = vec![("name", Value::Str("p2".into()))];
        v.extend_from_slice(kv);
        map(&v)
    };
    for (why, kv) in [
        (
            "no name",
            vec![("selector", Value::Str("{a=\"b\"}".into()))],
        ),
        ("bad regex", vec![("selector", "up{a=~\"[\"}".into())]),
        ("bad op", vec![("selector", "up{a<\"b\"}".into())]),
        (
            "q above 1",
            vec![("selector", "h".into()), ("q", Value::Float(1.5))],
        ),
        (
            "quantile with aggregate",
            vec![
                ("selector", "h".into()),
                ("function", "histogram_quantile".into()),
                ("aggregate", "sum".into()),
            ],
        ),
        (
            "unknown mode",
            vec![("selector", "h".into()), ("mode", "delta".into())],
        ),
    ] {
        assert_eq!(
            act(&h, "c1/d1", "add_point", add_pt(&kv)).await,
            invalid,
            "{why}"
        );
    }
    assert_eq!(
        act(
            &h,
            "c1/d1",
            "add_point",
            add_pt(&[("selector", "sim_requests_total{path=\"/a\"}".into())])
        )
        .await,
        Some(Status::Ok)
    );
    wait("new point", || good(&h, "c1/d1/p2").is_some()).await;
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn list_series_for_commissioning() {
    let (addr, _e, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    let h = H::start(simple(addr.port(), &[])).await;
    wait("good value", || good(&h, "c1/d1/t").is_some()).await;
    let call = |args: Value| {
        let h = &h;
        async move {
            let r = h
                .invoke("c1", "list_series", args, Some(h.ptok(Perm::Config)))
                .await;
            let r = r.first().expect("a reply");
            assert_eq!(status(&r.att), Some(Status::Ok));
            match r.value() {
                Some(Value::Map(m)) => m,
                v => panic!("{v:?}"),
            }
        }
    };
    // it holds the connection: a commissioning action at config
    let r = h
        .invoke("c1", "list_series", map(&[]), Some(h.ptok(Perm::Write)))
        .await;
    let refused = r.first().and_then(|r| status(&r.att));
    assert!(
        refused.is_some() && refused != Some(Status::Ok),
        "{refused:?}"
    );
    let m = call(map(&[
        ("match", "sim_temperature_celsius".into()),
        ("limit", Value::UInt(1)),
    ]))
    .await;
    assert_eq!(m.get("total"), Some(&Value::UInt(2)));
    assert_eq!(m.get("truncated"), Some(&Value::Bool(true)));
    let Some(Value::Array(rows)) = m.get("series") else {
        panic!("{m:?}")
    };
    assert_eq!(rows.len(), 1);
    let row = format!("{:?}", rows[0]);
    assert!(row.contains("gauge") && row.contains("instance"), "{row}");
    let m = call(map(&[])).await;
    assert!(
        matches!(m.get("total"), Some(Value::UInt(n)) if *n >= 15),
        "{m:?}"
    );
    assert_eq!(m.get("truncated"), Some(&Value::Bool(false)));
    let m = call(map(&[("match", "sim_nan".into())])).await;
    assert!(format!("{m:?}").contains("NaN"), "{m:?}");
    // a bad selector is refused
    let r = h
        .invoke(
            "c1",
            "list_series",
            map(&[("match", "{a=~\"(\"}".into())]),
            Some(h.ptok(Perm::Config)),
        )
        .await;
    assert_eq!(
        r.first().and_then(|r| status(&r.att)),
        Some(Status::InvalidParameter)
    );
    h.stop().await;
}

#[tokio::test(flavor = "multi_thread")]
async fn openmetrics_exposition() {
    let (addr, e, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    exporter(&e).openmetrics = true;
    let devices = map(&[(
        "d1",
        dev(
            "",
            map(&[
                ("t", pt("sim_temperature_celsius{instance=\"b\"}", &[])),
                (
                    "r",
                    pt("sim_requests_total", &[("aggregate", "sum".into())]),
                ),
            ]),
        ),
    )]);
    let h = H::start(tree(addr.port(), &[], devices)).await;
    wait("values", || {
        good(&h, "c1/d1/t") == Some(19.0) && good(&h, "c1/d1/r").is_some()
    })
    .await;
    h.stop().await;
}

/// A TLS front for the simulator with its own CA (PEM).
async fn tls_proxy(target: u16) -> (u16, String) {
    use rcgen::{BasicConstraints, CertificateParams, IsCa, Issuer, KeyPair};
    let ca_key = KeyPair::generate().expect("ca key");
    let mut p = CertificateParams::new(Vec::<String>::new()).expect("ca params");
    p.is_ca = IsCa::Ca(BasicConstraints::Unconstrained);
    let ca = p.self_signed(&ca_key).expect("ca cert");
    let issuer = Issuer::new(p, ca_key);
    let key = KeyPair::generate().expect("server key");
    let cert = CertificateParams::new(vec!["localhost".to_owned()])
        .expect("server params")
        .signed_by(&key, &issuer)
        .expect("server cert");
    let provider = Arc::new(rustls::crypto::ring::default_provider());
    let cfg = rustls::ServerConfig::builder_with_provider(provider)
        .with_safe_default_protocol_versions()
        .expect("tls versions")
        .with_no_client_auth()
        .with_single_cert(
            vec![cert.der().clone()],
            rustls::pki_types::PrivateKeyDer::Pkcs8(key.serialize_der().into()),
        )
        .expect("server config");
    let acceptor = tokio_rustls::TlsAcceptor::from(Arc::new(cfg));
    let l = TcpListener::bind("127.0.0.1:0").await.expect("bind");
    let port = l.local_addr().expect("addr").port();
    tokio::spawn(async move {
        while let Ok((s, _)) = l.accept().await {
            let acc = acceptor.clone();
            tokio::spawn(async move {
                if let Ok(mut a) = acc.accept(s).await {
                    if let Ok(mut b) = TcpStream::connect(("127.0.0.1", target)).await {
                        let _ = tokio::io::copy_bidirectional(&mut a, &mut b).await;
                    }
                }
            });
        }
    });
    (port, ca.pem())
}

#[tokio::test(flavor = "multi_thread")]
async fn https_with_ca_pem_or_insecure() {
    let (addr, _e, _task) = sim::spawn("127.0.0.1:0").await.unwrap();
    let (tport, ca_pem) = tls_proxy(addr.port()).await;
    let url = format!("https://localhost:{tport}/metrics");
    let one = || {
        map(&[(
            "d1",
            dev(
                "",
                map(&[("t", pt("sim_temperature_celsius{instance=\"a\"}", &[]))]),
            ),
        )])
    };
    let h = H::start(tree_url(&url, &[("ca_pem", ca_pem.clone().into())], one())).await;
    wait("value over https", || good(&h, "c1/d1/t") == Some(21.5)).await;
    let (_, m) = h.meta("c1/status").await;
    assert!(m.and_then(|m| m.attr_value("warning").cloned()).is_none());
    h.stop().await;
    // another CA: the certificate is refused
    let (_, other_ca) = tls_proxy(addr.port()).await;
    let h = H::start(tree_url(&url, &[("ca_pem", other_ca.into())], one())).await;
    wait("refused certificate", || {
        error(&h, "c1").is_some_and(|e| e.contains("tls"))
    })
    .await;
    h.stop().await;
    // no check at all: works, with a warning on the status leaf
    let h = H::start(tree_url(
        &url,
        &[("insecure_skip_verify", Value::Bool(true))],
        one(),
    ))
    .await;
    wait("value without a check", || {
        good(&h, "c1/d1/t") == Some(21.5)
    })
    .await;
    let (_, m) = h.meta("c1/status").await;
    let warning = m.and_then(|m| m.attr_value("warning").cloned());
    assert!(
        format!("{warning:?}").contains("insecure_skip_verify"),
        "{warning:?}"
    );
    h.stop().await;
}
