//! Node type rules (wiki "Типи нод"), driven directly through `input`/`tick`.

use std::collections::BTreeMap;
use std::sync::Arc;
use wyrm_client::WyrmClient;
use wyrm_core::{Quality, Value};
use wyrm_flow::nodes::{self, Io, Msg, Node, Out};
use wyrm_link_mock::{Mock, MockConfig};
use wyrm_link_sdk::harness::isolated_config;
use wyrm_link_sdk::{LinkConfig, LinkHandle};

struct Env {
    io: Io,
    _h: LinkHandle<Mock>,
}

async fn env() -> Env {
    let session = zenoh::open(isolated_config()).await.unwrap();
    let h = wyrm_link_sdk::spawn::<Mock>(
        session.clone(),
        LinkConfig::new("test", "m"),
        MockConfig {
            points: 1,
            rate_hz: 0.0,
            depth: 0,
            fanout: 1,
            writable: false,
        },
    )
    .await
    .unwrap();
    let io = Io {
        client: WyrmClient::new(session),
        ctx: h.ctx().clone(),
        site: "test".into(),
        flow: "f".into(),
        inject: Arc::new(|_, _| {}),
    };
    Env { io, _h: h }
}

fn cfg(kv: &[(&str, Value)]) -> BTreeMap<String, Value> {
    kv.iter()
        .map(|(k, v)| ((*k).to_owned(), v.clone()))
        .collect()
}

fn build(ty: &str, kv: &[(&str, Value)]) -> Box<dyn Node> {
    let c = cfg(kv);
    nodes::ports(ty, &c).unwrap();
    nodes::build(ty, "f", "n", &c).unwrap()
}

fn m(v: impl Into<Value>, q: Quality, t: u64) -> Msg {
    Msg::new(v.into(), q, t)
}

fn g(v: f64, t: u64) -> Msg {
    m(v, Quality::Good, t)
}

fn feed(n: &mut dyn Node, io: &Io, port: &str, msg: Msg) -> Vec<(String, Msg)> {
    let mut out = Out::default();
    n.input(port, msg, io, &mut out);
    out.0
}

fn tick(n: &mut dyn Node, now: u64) -> Vec<(String, Msg)> {
    let mut out = Out::default();
    n.tick(now, &mut out);
    out.0
}

fn num(o: &(String, Msg)) -> f64 {
    o.1.v.as_f64().unwrap()
}

const S: u64 = 1_000_000;

#[tokio::test(flavor = "multi_thread")]
async fn alarm_high_low_hysteresis_and_event() {
    let e = env().await;
    let mut a = build(
        "alarm",
        &[
            ("high", Value::Float(100.0)),
            ("low", Value::Float(10.0)),
            ("hysteresis", Value::Float(5.0)),
        ],
    );
    assert!(feed(a.as_mut(), &e.io, "in", g(50.0, 1)).is_empty());
    let out = feed(a.as_mut(), &e.io, "in", g(101.0, 2));
    assert_eq!(out.len(), 2);
    assert_eq!(out[0].0, "out");
    assert_eq!(out[0].1.v, Value::Bool(true));
    assert_eq!(out[1].0, "event");
    let Value::Map(ev) = &out[1].1.v else {
        panic!()
    };
    assert_eq!(ev["edge"], Value::from("rising"));
    assert_eq!(ev["value"], Value::Float(101.0));
    assert_eq!(ev["t"], Value::UInt(2));
    // inside hysteresis band: still active
    assert!(feed(a.as_mut(), &e.io, "in", g(97.0, 3)).is_empty());
    let out = feed(a.as_mut(), &e.io, "in", g(94.0, 4));
    assert_eq!(out[0].1.v, Value::Bool(false));
    let Value::Map(ev) = &out[1].1.v else {
        panic!()
    };
    assert_eq!(ev["edge"], Value::from("falling"));
    // low side
    assert_eq!(
        feed(a.as_mut(), &e.io, "in", g(5.0, 5))[0].1.v,
        Value::Bool(true)
    );
    assert!(feed(a.as_mut(), &e.io, "in", g(14.0, 6)).is_empty());
    assert_eq!(
        feed(a.as_mut(), &e.io, "in", g(16.0, 7))[0].1.v,
        Value::Bool(false)
    );
}

#[tokio::test(flavor = "multi_thread")]
async fn alarm_delays() {
    let e = env().await;
    let mut a = build(
        "alarm",
        &[
            ("high", Value::Float(100.0)),
            ("delay_s", Value::Float(2.0)),
            ("return_delay_s", Value::Float(1.0)),
        ],
    );
    assert!(a.tick_every().is_some());
    assert!(
        feed(a.as_mut(), &e.io, "in", g(150.0, 10 * S)).is_empty(),
        "pending"
    );
    assert!(tick(a.as_mut(), 11 * S).is_empty());
    let out = tick(a.as_mut(), 12 * S);
    assert_eq!(out[0].1.v, Value::Bool(true));
    assert_eq!(out[0].1.t, 12 * S);
    // return delay; a relapse cancels the pending clear
    assert!(feed(a.as_mut(), &e.io, "in", g(50.0, 20 * S)).is_empty());
    assert!(feed(a.as_mut(), &e.io, "in", g(150.0, 20 * S + 1)).is_empty());
    assert!(
        tick(a.as_mut(), 22 * S).is_empty(),
        "pending clear cancelled"
    );
    assert!(feed(a.as_mut(), &e.io, "in", g(50.0, 30 * S)).is_empty());
    assert_eq!(tick(a.as_mut(), 31 * S)[0].1.v, Value::Bool(false));
}

#[tokio::test(flavor = "multi_thread")]
async fn alarm_on_bad() {
    let e = env().await;
    let bad = m(0.0, Quality::Bad, 5);
    let mut hold = build("alarm", &[("high", Value::Float(1.0))]);
    feed(hold.as_mut(), &e.io, "in", g(5.0, 1));
    assert!(
        feed(hold.as_mut(), &e.io, "in", bad.clone()).is_empty(),
        "hold"
    );
    let mut clear = build(
        "alarm",
        &[("high", Value::Float(1.0)), ("on_bad", "clear".into())],
    );
    feed(clear.as_mut(), &e.io, "in", g(5.0, 1));
    assert_eq!(
        feed(clear.as_mut(), &e.io, "in", bad.clone())[0].1.v,
        Value::Bool(false)
    );
    let mut raise = build(
        "alarm",
        &[("high", Value::Float(1.0)), ("on_bad", "raise".into())],
    );
    assert_eq!(
        feed(raise.as_mut(), &e.io, "in", bad)[0].1.v,
        Value::Bool(true)
    );
}

#[tokio::test(flavor = "multi_thread")]
async fn latch_manual_and_auto() {
    let e = env().await;
    let mut man = build("latch", &[]);
    assert_eq!(
        feed(man.as_mut(), &e.io, "in", m(true, Quality::Good, 1))[0]
            .1
            .v,
        Value::Bool(true)
    );
    assert!(
        feed(man.as_mut(), &e.io, "in", m(false, Quality::Good, 2)).is_empty(),
        "manual holds"
    );
    assert_eq!(
        feed(man.as_mut(), &e.io, "reset", m(true, Quality::Good, 3))[0]
            .1
            .v,
        Value::Bool(false)
    );
    let mut auto = build("latch", &[("reset", "auto".into())]);
    feed(auto.as_mut(), &e.io, "in", m(true, Quality::Good, 1));
    assert_eq!(
        feed(auto.as_mut(), &e.io, "in", m(false, Quality::Good, 2))[0]
            .1
            .v,
        Value::Bool(false)
    );
}

#[tokio::test(flavor = "multi_thread")]
async fn deadband_abs_pct_quality() {
    let e = env().await;
    let mut d = build("deadband", &[("abs", Value::Float(1.0))]);
    assert_eq!(feed(d.as_mut(), &e.io, "in", g(10.0, 1)).len(), 1);
    assert!(feed(d.as_mut(), &e.io, "in", g(10.5, 2)).is_empty());
    assert_eq!(feed(d.as_mut(), &e.io, "in", g(11.0, 3)).len(), 1);
    assert_eq!(
        feed(d.as_mut(), &e.io, "in", m(11.0, Quality::Uncertain, 4)).len(),
        1,
        "quality change passes"
    );
    let mut p = build("deadband", &[("pct", Value::Float(10.0))]);
    feed(p.as_mut(), &e.io, "in", g(100.0, 1));
    assert!(feed(p.as_mut(), &e.io, "in", g(105.0, 2)).is_empty());
    assert_eq!(feed(p.as_mut(), &e.io, "in", g(111.0, 3)).len(), 1);
}

#[tokio::test(flavor = "multi_thread")]
async fn window_tumbling() {
    let e = env().await;
    let mut w = build(
        "window",
        &[("size_s", Value::Float(10.0)), ("fn", "avg".into())],
    );
    assert!(w.tick_every().is_some());
    assert!(feed(w.as_mut(), &e.io, "in", g(1.0, 100 * S)).is_empty());
    feed(w.as_mut(), &e.io, "in", g(3.0, 105 * S));
    assert!(tick(w.as_mut(), 109 * S).is_empty());
    let out = tick(w.as_mut(), 110 * S);
    assert_eq!(num(&out[0]), 2.0);
    assert_eq!(out[0].1.t, 110 * S, "t = window end");
    assert_eq!(out[0].1.q, Quality::Good);
    // <50 % good → uncertain
    feed(w.as_mut(), &e.io, "in", m(1.0, Quality::Uncertain, 111 * S));
    feed(w.as_mut(), &e.io, "in", m(1.0, Quality::Uncertain, 112 * S));
    feed(w.as_mut(), &e.io, "in", g(1.0, 113 * S));
    assert_eq!(tick(w.as_mut(), 120 * S)[0].1.q, Quality::Uncertain);
}

#[tokio::test(flavor = "multi_thread")]
async fn window_sliding_fns() {
    let e = env().await;
    let run = |f: &str| {
        let mut w = build(
            "window",
            &[
                ("kind", "sliding".into()),
                ("size_s", Value::Float(10.0)),
                ("fn", f.into()),
            ],
        );
        let mut last = 0.0;
        for (i, x) in [2.0, 8.0, 5.0].iter().enumerate() {
            let out = feed(w.as_mut(), &e.io, "in", g(*x, (i as u64) * S));
            // `rate` needs two samples
            if let Some(o) = out.first() {
                last = num(o);
            }
        }
        last
    };
    assert_eq!(run("avg"), 5.0);
    assert_eq!(run("min"), 2.0);
    assert_eq!(run("max"), 8.0);
    assert_eq!(run("sum"), 15.0);
    assert_eq!(run("count"), 3.0);
    assert_eq!(run("rate"), 1.5, "(5-2)/2 s");
    // old samples leave the sliding window
    let mut w = build(
        "window",
        &[
            ("kind", "sliding".into()),
            ("size_s", Value::Float(1.0)),
            ("fn", "count".into()),
        ],
    );
    feed(w.as_mut(), &e.io, "in", g(1.0, 0));
    let out = feed(w.as_mut(), &e.io, "in", g(1.0, 5 * S));
    assert_eq!(num(&out[0]), 1.0);
}

#[tokio::test(flavor = "multi_thread")]
async fn delay_filter_scale_timer() {
    let e = env().await;
    let mut d = build("delay", &[("ms", Value::UInt(50))]);
    assert!(feed(d.as_mut(), &e.io, "in", g(7.0, 1)).is_empty());
    let now = wyrm_link_sdk::now_us();
    assert!(tick(d.as_mut(), now).is_empty());
    let out = tick(d.as_mut(), now + 60_000);
    assert_eq!(num(&out[0]), 7.0);

    let mut f = build("filter", &[("expr", "v > 10".into())]);
    assert!(feed(f.as_mut(), &e.io, "in", g(5.0, 1)).is_empty());
    assert_eq!(feed(f.as_mut(), &e.io, "in", g(15.0, 1)).len(), 1);

    let mut s = build(
        "scale",
        &[("k", Value::Float(2.0)), ("b", Value::Float(1.0))],
    );
    let out = feed(s.as_mut(), &e.io, "in", m(3.0, Quality::Uncertain, 9));
    assert_eq!(num(&out[0]), 7.0);
    assert_eq!(out[0].1.q, Quality::Uncertain);
    assert_eq!(out[0].1.t, 9);

    let mut t = build("timer", &[("period_ms", Value::UInt(100))]);
    assert_eq!(t.tick_every(), Some(std::time::Duration::from_millis(100)));
    assert_eq!(tick(t.as_mut(), 1)[0].1.v, Value::UInt(1));
    assert_eq!(tick(t.as_mut(), 2)[0].1.v, Value::UInt(2));
}

fn expr(e: &str, trigger: &str, quality: &str) -> Box<dyn Node> {
    build(
        "expression",
        &[
            ("inputs", Value::Array(vec!["a".into(), "b".into()])),
            ("expr", e.into()),
            ("trigger", trigger.into()),
            ("quality", quality.into()),
        ],
    )
}

#[tokio::test(flavor = "multi_thread")]
async fn expression_trigger_quality_time() {
    let e = env().await;
    let mut any = expr("a.v + b.v", "any", "worst");
    assert!(
        feed(any.as_mut(), &e.io, "in.a", g(1.0, 5)).is_empty(),
        "b not seen yet"
    );
    let out = feed(any.as_mut(), &e.io, "in.b", m(2.0, Quality::Uncertain, 9));
    assert_eq!(num(&out[0]), 3.0);
    assert_eq!(out[0].1.q, Quality::Uncertain, "worst");
    assert_eq!(out[0].1.t, 9, "t = max input t");
    assert_eq!(
        feed(any.as_mut(), &e.io, "in.a", g(10.0, 7)).len(),
        1,
        "any: one fresh input"
    );

    let mut all = expr("a.v + b.v", "all", "ignore");
    feed(all.as_mut(), &e.io, "in.a", g(1.0, 1));
    let out = feed(all.as_mut(), &e.io, "in.b", m(1.0, Quality::Bad, 1));
    assert_eq!(out[0].1.q, Quality::Good, "ignore");
    assert!(
        feed(all.as_mut(), &e.io, "in.a", g(2.0, 2)).is_empty(),
        "all: b not fresh"
    );
    assert_eq!(feed(all.as_mut(), &e.io, "in.b", g(2.0, 3)).len(), 1);

    let mut custom = expr("#{ v: a.v * 10, q: 1 }", "any", "custom");
    feed(custom.as_mut(), &e.io, "in.a", g(2.0, 1));
    let out = feed(custom.as_mut(), &e.io, "in.b", g(0.0, 1));
    assert_eq!(num(&out[0]), 20.0);
    assert_eq!(out[0].1.q, Quality::Uncertain);

    let mut unit = expr("if a.v > 100 { a.v } else { () }", "any", "worst");
    feed(unit.as_mut(), &e.io, "in.a", g(1.0, 1));
    assert!(
        feed(unit.as_mut(), &e.io, "in.b", g(1.0, 1)).is_empty(),
        "() emits nothing"
    );
}

#[tokio::test(flavor = "multi_thread")]
async fn expression_state_persists_and_restores() {
    let e = env().await;
    let mut x = expr("state.n = (state.n ?? 0) + 1; state.n", "any", "worst");
    feed(x.as_mut(), &e.io, "in.a", g(0.0, 1));
    for i in 1..=3 {
        let out = feed(x.as_mut(), &e.io, "in.b", g(0.0, 1));
        assert_eq!(out[0].1.v, Value::UInt(i));
    }
    let st = x.state().unwrap();
    let mut y = expr("state.n = (state.n ?? 0) + 1; state.n", "any", "worst");
    y.restore(&st);
    feed(y.as_mut(), &e.io, "in.a", g(0.0, 1));
    assert_eq!(
        feed(y.as_mut(), &e.io, "in.b", g(0.0, 1))[0].1.v,
        Value::UInt(4)
    );
}

#[tokio::test(flavor = "multi_thread")]
async fn state_round_trips() {
    let e = env().await;
    // alarm
    let mut a = build("alarm", &[("high", Value::Float(1.0))]);
    feed(a.as_mut(), &e.io, "in", g(5.0, 1));
    let mut a2 = build("alarm", &[("high", Value::Float(1.0))]);
    a2.restore(&a.state().unwrap());
    assert!(
        feed(a2.as_mut(), &e.io, "in", g(5.0, 2)).is_empty(),
        "already active"
    );
    // latch
    let mut l = build("latch", &[]);
    feed(l.as_mut(), &e.io, "in", m(true, Quality::Good, 1));
    let mut l2 = build("latch", &[]);
    l2.restore(&l.state().unwrap());
    assert_eq!(
        feed(l2.as_mut(), &e.io, "reset", m(true, Quality::Good, 2))[0]
            .1
            .v,
        Value::Bool(false)
    );
    // deadband
    let mut d = build("deadband", &[("abs", Value::Float(1.0))]);
    feed(d.as_mut(), &e.io, "in", g(10.0, 1));
    let mut d2 = build("deadband", &[("abs", Value::Float(1.0))]);
    d2.restore(&d.state().unwrap());
    assert!(feed(d2.as_mut(), &e.io, "in", g(10.2, 2)).is_empty());
    // window
    let mut w = build(
        "window",
        &[("size_s", Value::Float(10.0)), ("fn", "sum".into())],
    );
    feed(w.as_mut(), &e.io, "in", g(4.0, 100 * S));
    let mut w2 = build(
        "window",
        &[("size_s", Value::Float(10.0)), ("fn", "sum".into())],
    );
    w2.restore(&w.state().unwrap());
    feed(w2.as_mut(), &e.io, "in", g(6.0, 101 * S));
    assert_eq!(num(&tick(w2.as_mut(), 110 * S)[0]), 10.0);
}
