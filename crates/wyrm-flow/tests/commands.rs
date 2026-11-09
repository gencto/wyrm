//! The command blocks `invoke` and `set` (ADR 0040 §2), driven through `input`/`tick` in a
//! preview's capture mode: the node decides as a deployed one does and reports what it would
//! send, so every rule is checked without a device.

use std::collections::BTreeMap;
use std::sync::Arc;
use std::time::Duration;
use wyrm_client::WyrmClient;
use wyrm_core::{Quality, Value};
use wyrm_flow::def;
use wyrm_flow::nodes::{self, Io, Mode, Msg, Node, Out, Sandbox};
use wyrm_flow::watch::{self, Probe};
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

fn map(kv: &[(&str, Value)]) -> Value {
    Value::Map(
        kv.iter()
            .map(|(k, v)| ((*k).to_owned(), v.clone()))
            .collect(),
    )
}

/// A capture node `n` of `ty` and the probe it reports to.
fn capture(ty: &str, kv: &[(&str, Value)]) -> (Box<dyn Node>, Arc<Probe>) {
    let mut cfg: BTreeMap<String, Value> = kv
        .iter()
        .map(|(k, v)| ((*k).to_owned(), v.clone()))
        .collect();
    cfg.entry("path".into())
        .or_insert_with(|| Value::from("downstream/m/p0"));
    if ty == "invoke" {
        cfg.entry("action".into())
            .or_insert_with(|| Value::from("count"));
    }
    nodes::ports(ty, &cfg).unwrap();
    let mut node = cfg.clone();
    node.insert("type".into(), Value::from(ty));
    let d = def::parse(&map(&[
        ("id", Value::from("f")),
        ("nodes", map(&[("n", Value::Map(node))])),
    ]))
    .unwrap();
    let probe = Probe::new(&d);
    let mode = Mode::Preview(Sandbox {
        probe: probe.clone(),
        site: "test".into(),
        flow: "f".into(),
    });
    (
        nodes::build_with(ty, "f", "n", &cfg, None, &mode).unwrap(),
        probe,
    )
}

fn good(v: impl Into<Value>) -> Msg {
    Msg::new(v.into(), Quality::Good, 1)
}

fn event(id: u64) -> Msg {
    good(map(&[
        ("event", Value::from("on_change")),
        ("id", Value::UInt(id)),
    ]))
}

/// The ports a call sent on.
fn feed(n: &mut dyn Node, io: &Io, port: &str, msg: Msg) -> Vec<String> {
    let mut out = Out::default();
    n.input(port, msg, io, &mut out);
    out.0.into_iter().map(|(p, _)| p).collect()
}

fn ran(sent: &[String]) -> bool {
    sent.iter().any(|p| p == "sent")
}

/// What the node would send, as the preview reports it.
async fn sink(probe: &Arc<Probe>) -> Option<Value> {
    let row = watch::ports(probe, None).await;
    let Value::Map(m) = row else { return None };
    match m.get("sinks") {
        Some(Value::Array(a)) => match a.first() {
            Some(Value::Map(s)) => s.get("value").cloned(),
            _ => None,
        },
        _ => None,
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn a_trigger_runs_on_a_change_and_never_on_a_start_value() {
    let e = env().await;
    let io = &e.io;
    let (mut n, probe) = capture("invoke", &[("args", map(&[("n", Value::UInt(3))]))]);
    // born at the start: the port gets its value, nothing runs
    assert!(!ran(&feed(&mut *n, io, "trigger", good(true).at_start())));
    assert_eq!(sink(&probe).await, None);
    // the same value again is no change
    assert!(!ran(&feed(&mut *n, io, "trigger", good(true))));
    // a change runs it; it sends `sent` and `last_run`, and in a preview never `ok`
    let sent = feed(&mut *n, io, "trigger", good(false));
    assert_eq!(sent, ["sent", "last_run"]);
    assert_eq!(sink(&probe).await, Some(map(&[("n", Value::UInt(3))])));
    assert!(ran(&feed(&mut *n, io, "trigger", good(true))));
    // null runs nothing; a bad sample neither
    assert!(!ran(&feed(&mut *n, io, "trigger", good(Value::Null))));
    assert!(!ran(&feed(
        &mut *n,
        io,
        "trigger",
        Msg::new(Value::UInt(9), Quality::Bad, 1)
    )));
    // an event runs it every time, also the first one after the start
    let (mut n, _) = capture("invoke", &[]);
    assert!(ran(&feed(&mut *n, io, "trigger", event(1))));
    assert!(ran(&feed(&mut *n, io, "trigger", event(2))));
    // but not an event born at the start (a hub fed by a variable)
    let (mut n, _) = capture("invoke", &[]);
    assert!(!ran(&feed(&mut *n, io, "trigger", event(1).at_start())));
    // the first real value after the start runs it: there is no value before to compare
    let (mut n, _) = capture("invoke", &[]);
    assert!(ran(&feed(&mut *n, io, "trigger", good(true))));
    // with allow_bad a bad sample runs it
    let (mut n, _) = capture("invoke", &[("allow_bad", Value::Bool(true))]);
    assert!(ran(&feed(
        &mut *n,
        io,
        "trigger",
        Msg::new(Value::UInt(9), Quality::Bad, 1)
    )));
    // the engine's action comes on an internal port and always runs
    let (mut n, _) = capture("invoke", &[]);
    assert!(ran(&feed(&mut *n, io, "__trigger", good(Value::Null))));
}

#[tokio::test(flavor = "multi_thread")]
async fn auto_run_runs_on_a_changed_argument_and_ignores_the_start_values() {
    let e = env().await;
    let io = &e.io;
    let args = map(&[("n", Value::UInt(3)), ("mode", Value::Null)]);
    let (mut n, probe) = capture(
        "invoke",
        &[("args", args.clone()), ("auto_run", Value::Bool(true))],
    );
    // the constants show as the inputs' values from the start
    assert_eq!(n.seeds(), vec![("arg.n".to_owned(), Value::UInt(3))]);
    // a start value fills the argument and runs nothing
    assert!(!ran(&feed(
        &mut *n,
        io,
        "arg.mode",
        good("auto").at_start()
    )));
    assert_eq!(sink(&probe).await, None);
    // a change of an argument runs it with every argument's value
    assert!(ran(&feed(&mut *n, io, "arg.n", good(5u64))));
    assert_eq!(
        sink(&probe).await,
        Some(map(&[("n", Value::UInt(5)), ("mode", Value::from("auto"))]))
    );
    // the same value again does not; an argument the block does not have is ignored
    assert!(!ran(&feed(&mut *n, io, "arg.n", good(5u64))));
    assert!(feed(&mut *n, io, "arg.other", good(1u64)).is_empty());
    // the effective arguments are a parameter the editor reads
    let (_, live) = n.live_params().unwrap();
    assert_eq!(
        live.get("args"),
        Some(&map(&[
            ("n", Value::UInt(5)),
            ("mode", Value::from("auto"))
        ]))
    );
    // auto_run off (the default): an argument only takes its value
    let (mut n, probe) = capture("invoke", &[("args", args)]);
    assert!(!ran(&feed(&mut *n, io, "arg.n", good(7u64))));
    assert_eq!(sink(&probe).await, None);
    // switched on by its port, it runs from the next change
    feed(&mut *n, io, "in.auto_run", good(true));
    assert!(ran(&feed(&mut *n, io, "arg.n", good(8u64))));
    // `"$in"` stands for the last value on `in`; `in` runs it as before
    let (mut n, probe) = capture("invoke", &[("args", map(&[("v", Value::from("$in"))]))]);
    assert!(ran(&feed(&mut *n, io, "in", good(42u64))));
    assert_eq!(sink(&probe).await, Some(map(&[("v", Value::UInt(42))])));
    assert!(ran(&feed(&mut *n, io, "trigger", good(1u64))));
    assert_eq!(sink(&probe).await, Some(map(&[("v", Value::UInt(42))])));
}

#[tokio::test(flavor = "multi_thread")]
async fn interval_runs_first_after_one_full_period() {
    let e = env().await;
    let io = &e.io;
    let (mut n, _) = capture("invoke", &[]);
    assert_eq!(n.tick_every(), None, "0: off");
    let (mut n2, probe) = capture("invoke", &[("interval_ms", Value::UInt(250))]);
    n2.start(io);
    assert_eq!(n2.tick_every(), Some(Duration::from_millis(250)));
    assert!(
        !n2.first_tick_now(),
        "the first run is one period after the start"
    );
    assert_eq!(sink(&probe).await, None);
    let mut out = Out::default();
    n2.tick(1, &mut out);
    assert!(out.0.iter().any(|(p, _)| p == "sent"));
    // a period from a port: 0 switches it off, a value below 100 ms is ignored
    feed(&mut *n, io, "in.interval_ms", good(500u64));
    assert_eq!(n.tick_every(), Some(Duration::from_millis(500)));
    feed(&mut *n, io, "in.interval_ms", good(50u64));
    assert_eq!(n.tick_every(), Some(Duration::from_millis(500)));
    feed(&mut *n, io, "in.interval_ms", good(0u64));
    assert_eq!(n.tick_every(), None);
    // disabled: no clock, and neither a trigger nor the action runs it
    feed(&mut *n2, io, "in.enabled", good(false));
    assert_eq!(n2.tick_every(), None);
    assert!(!ran(&feed(&mut *n2, io, "trigger", good(1u64))));
    assert!(!ran(&feed(&mut *n2, io, "__trigger", good(Value::Null))));
    feed(&mut *n2, io, "in.enabled", good(true));
    assert_eq!(n2.tick_every(), Some(Duration::from_millis(250)));
    // the config is checked
    for bad in [Value::UInt(50), Value::Int(-1), Value::UInt(100_000_000)] {
        let cfg: BTreeMap<String, Value> = [
            ("path".to_owned(), Value::from("downstream/m/p0")),
            ("interval_ms".to_owned(), bad.clone()),
        ]
        .into();
        assert!(nodes::ports("set", &cfg).is_err(), "{bad:?}");
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn set_writes_on_in_by_default_and_on_trigger() {
    let e = env().await;
    let io = &e.io;
    // auto_run is true by default: a value on `in` is written, as before (also at the start)
    let (mut n, probe) = capture("set", &[]);
    assert!(ran(&feed(&mut *n, io, "in", good(1.5).at_start())));
    assert_eq!(sink(&probe).await, Some(Value::Float(1.5)));
    // on: change — the same value is not written again, a trigger writes it again
    assert!(!ran(&feed(&mut *n, io, "in", good(1.5))));
    assert!(ran(&feed(&mut *n, io, "trigger", good(true))));
    // auto_run false: `in` only holds the value
    let (mut n, probe) = capture("set", &[("auto_run", Value::Bool(false))]);
    assert!(
        !ran(&feed(&mut *n, io, "trigger", good(1u64))),
        "nothing to write yet"
    );
    assert!(!ran(&feed(&mut *n, io, "in", good(7u64))));
    assert_eq!(sink(&probe).await, None);
    assert!(!ran(&feed(&mut *n, io, "trigger", good(1u64))), "no change");
    assert!(ran(&feed(&mut *n, io, "trigger", good(2u64))));
    assert_eq!(sink(&probe).await, Some(Value::UInt(7)));
    // a start value on trigger never writes; a bad value on `in` is not held
    let (mut n, probe) = capture("set", &[("auto_run", Value::Bool(false))]);
    feed(&mut *n, io, "in", Msg::new(Value::UInt(9), Quality::Bad, 1));
    feed(&mut *n, io, "in", good(3u64).at_start());
    assert!(!ran(&feed(&mut *n, io, "trigger", good(true).at_start())));
    assert_eq!(sink(&probe).await, None);
    assert!(ran(&feed(&mut *n, io, "__trigger", good(Value::Null))));
    assert_eq!(sink(&probe).await, Some(Value::UInt(3)));
    // the interval writes the held value again
    let (mut n, _) = capture(
        "set",
        &[
            ("auto_run", Value::Bool(false)),
            ("interval_ms", Value::UInt(100)),
        ],
    );
    n.start(io);
    let mut out = Out::default();
    n.tick(1, &mut out);
    assert!(out.0.is_empty(), "no value yet");
    feed(&mut *n, io, "in", good(4u64));
    n.tick(2, &mut out);
    assert!(out.0.iter().any(|(p, _)| p == "sent"));
}

#[test]
fn the_action_block_names_its_ports() {
    let cfg: BTreeMap<String, Value> = [
        ("path".to_owned(), Value::from("downstream/m")),
        ("action".to_owned(), Value::from("count")),
        (
            "args".to_owned(),
            map(&[("n", Value::UInt(1)), ("mode", Value::Null)]),
        ),
    ]
    .into();
    let p = nodes::ports("invoke", &cfg).unwrap();
    let ins: Vec<&str> = p.inputs.iter().map(|(n, _)| n.as_str()).collect();
    assert_eq!(
        ins,
        [
            "in",
            "trigger",
            "in.interval_ms",
            "in.auto_run",
            "in.enabled",
            "arg.mode",
            "arg.n"
        ]
    );
    let outs: Vec<&str> = p.outputs.iter().map(|(n, _)| n.as_str()).collect();
    assert_eq!(
        outs,
        ["out", "result", "sent", "ok", "error", "running", "last_run"]
    );
    // an argument is a field: it has an echo output of its name
    assert!(p.echo("arg.n").is_some() && p.echo("trigger").is_some());
    assert!(p.echo("interval_ms").is_some());
    // args is a map of at most 64 names
    let bad = |args: Value| {
        let mut c = cfg.clone();
        c.insert("args".into(), args);
        nodes::ports("invoke", &c).unwrap_err()
    };
    assert!(bad(Value::UInt(1)).contains("args"));
    assert!(bad(map(&[("__x", Value::Null)])).contains("args.__x"));
    let many: Vec<(String, Value)> = (0..65).map(|i| (format!("a{i}"), Value::Null)).collect();
    assert!(bad(Value::Map(many.into_iter().collect())).contains("at most 64"));
}
