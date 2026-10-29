//! The scheduler app through `SimHost`: tree, schedules and events, the store, the wake heap,
//! the clock watchdog and the bounds (ADR 0022, plan Task 3).

mod common;

use common::*;
use wyrm_core::{Perm, Status, Value};
use wyrm_link_api::buffer::Command;
use wyrm_link_scheduler::limits::{COMMANDS_PER_EVENT, NODE_BUDGET, WATCHDOG_MS};
use wyrm_schedule::{parse_local, schedule_to_value, Event, Schedule};

fn add_lobby(h: &mut SimHost) {
    h.invoke(
        "",
        "add_schedule",
        map([("id", text("lobby")), ("default", Value::Bool(false))]),
    )
    .expect("add_schedule");
}

fn daily(value: Value, start: &str, end: &str) -> Value {
    map([
        ("value", value),
        ("start", text(start)),
        ("end", text(end)),
        ("recurrence", text("FREQ=DAILY")),
    ])
}

/// The log line of a detected wall-clock step.
fn stepped(log: &[Command]) -> bool {
    log.iter()
        .any(|c| matches!(c, Command::Log(_, m) if m.starts_with("wall clock stepped")))
}

fn decode(bytes: &[u8]) -> Value {
    wyrm_core::codec::from_slice::<Value>(bytes).unwrap()
}

fn field<'a>(v: &'a Value, k: &str) -> &'a Value {
    match v {
        Value::Map(m) => m.get(k).unwrap_or_else(|| panic!("no {k} in {v:?}")),
        _ => panic!("not a map: {v:?}"),
    }
}

#[test]
fn add_schedule_declares_and_saves() {
    let mut h = started();
    add_lobby(&mut h);
    for p in [
        "lobby",
        "lobby/current",
        "lobby/default",
        "lobby/enabled",
        "lobby/events",
        "lobby/targets",
    ] {
        assert!(h.has(p), "{p} declared");
    }
    assert!(h.store_get("s/lobby").is_some());
    assert_eq!(
        decode(&h.store_get("index").unwrap()),
        Value::Array(vec![text("lobby")])
    );
    assert_eq!(h.value("lobby/current"), Some(Value::Bool(false)));
    assert_eq!(h.value("lobby/default"), Some(Value::Bool(false)));
    assert_eq!(h.value("lobby/enabled"), Some(Value::Bool(true)));
    assert_eq!(h.attr("lobby", "source"), text("default"));
    assert_eq!(h.attr("lobby", "tz"), text("UTC"));
    assert_eq!(h.attr("lobby", "next_time"), Value::Null);

    let (st, msg) = status(h.invoke(
        "",
        "add_schedule",
        map([("id", text("lobby")), ("default", Value::Bool(true))]),
    ));
    assert_eq!(st, Status::InvalidParameter);
    assert!(msg.contains("lobby exists"), "{msg}");

    let (r, cmds) = h.invoke_cmds(
        "",
        "add_schedule",
        map([("id", text("a/b")), ("default", Value::Null)]),
    );
    let (st, msg) = status(r);
    assert_eq!(st, Status::InvalidParameter);
    assert!(msg.starts_with("id"), "{msg}");
    assert!(
        cmds.is_empty(),
        "nothing buffered before validation: {cmds:?}"
    );
}

#[test]
fn add_event_moves_current_and_arms_the_timer() {
    let mut h = started();
    add_lobby(&mut h);
    let r = h
        .invoke(
            "lobby",
            "add_event",
            daily(Value::Bool(true), "2026-10-29T08:00", "2026-10-29T17:00"),
        )
        .unwrap();
    assert_eq!(r, map([("id", text("e1"))]));
    assert!(h.has("lobby/events/e1"));
    let (_, ms) = h.armed.expect("a timer is armed");
    assert!(ms <= WATCHDOG_MS, "{ms}");
    assert_eq!(h.app().next_wake(), Some(at("2026-10-29T08:00:00Z") as i64));
    assert_eq!(h.attr("lobby", "next_time"), text("2026-10-29T08:00:00Z"));
    assert_eq!(h.attr("lobby", "next_value"), Value::Bool(true));

    h.advance_to(at("2026-10-29T08:00:00Z"));
    assert_eq!(h.value("lobby/current"), Some(Value::Bool(true)));
    assert_eq!(h.attr("lobby", "source"), text("e1"));
    assert_eq!(h.attr("lobby", "next_time"), text("2026-10-29T17:00:00Z"));
    assert_eq!(h.attr("lobby", "next_value"), Value::Bool(false));

    h.advance_to(at("2026-10-29T17:00:00Z"));
    assert_eq!(h.value("lobby/current"), Some(Value::Bool(false)));
    assert_eq!(h.attr("lobby", "source"), text("default"));
    assert_eq!(h.attr("lobby", "next_time"), text("2026-10-30T08:00:00Z"));
}

#[test]
fn edits_survive_a_restart() {
    let mut h = started();
    add_lobby(&mut h);
    h.invoke(
        "lobby",
        "add_event",
        daily(Value::UInt(1), "2026-10-29T06:00", "2026-10-29T09:00"),
    )
    .unwrap();
    h.invoke(
        "lobby",
        "add_event",
        map([
            ("value", Value::UInt(2)),
            ("start", text("2026-10-30T10:00")),
            ("end", text("2026-10-30T11:00")),
            ("priority", Value::UInt(3)),
            ("display", text("Once")),
        ]),
    )
    .unwrap();
    h.invoke(
        "lobby/events/e1",
        "edit",
        map([
            ("end", text("2026-10-29T10:00")),
            ("priority", Value::UInt(2)),
        ]),
    )
    .unwrap();
    h.set("lobby/default", Value::UInt(3)).unwrap();
    h.set("lobby/enabled", Value::Bool(false)).unwrap();
    assert_eq!(h.value("lobby/current"), Some(Value::UInt(1)));

    let before = h.nodes.clone();
    h.restart().unwrap();
    h.settle();
    assert_eq!(
        before.keys().collect::<Vec<_>>(),
        h.nodes.keys().collect::<Vec<_>>()
    );
    for (p, n) in &before {
        let m = &h.node(p).meta;
        assert_eq!(m.attr, n.meta.attr, "{p} attributes");
        assert_eq!(h.node(p).value, n.value, "{p} value");
    }
    assert_eq!(h.attr("lobby/events/e1", "end"), text("2026-10-29T10:00"));
    assert_eq!(h.attr("lobby/events/e1", "priority"), Value::UInt(2));
    assert_eq!(h.value("lobby/default"), Some(Value::UInt(3)));
    assert_eq!(h.value("lobby/enabled"), Some(Value::Bool(false)));

    h.invoke("lobby/events/e2", "remove", Value::Null).unwrap();
    assert!(!h.has("lobby/events/e2"));
    let stored = decode(&h.store_get("s/lobby").unwrap());
    let Value::Array(events) = field(&stored, "events") else {
        panic!()
    };
    assert_eq!(events.len(), 1);
    let r = h
        .invoke(
            "lobby",
            "add_event",
            daily(Value::UInt(4), "2026-10-29T12:00", "2026-10-29T13:00"),
        )
        .unwrap();
    assert_eq!(r, map([("id", text("e3"))]));
}

#[test]
fn get_events_lists_occurrences() {
    let mut h = started();
    add_lobby(&mut h);
    h.invoke(
        "lobby",
        "add_event",
        map([
            ("value", Value::Bool(true)),
            ("start", text("2026-10-26T08:00")),
            ("end", text("2026-10-26T17:00")),
            ("recurrence", text("FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR")),
            ("priority", Value::UInt(4)),
        ]),
    )
    .unwrap();
    let r = h
        .invoke(
            "lobby",
            "get_events",
            map([(
                "timerange",
                text("2026-11-02T00:00:00Z/2026-11-09T00:00:00Z"),
            )]),
        )
        .unwrap();
    let Value::Array(rows) = r else {
        panic!("{r:?}")
    };
    assert_eq!(rows.len(), 5);
    assert_eq!(
        rows[0],
        map([
            ("start", text("2026-11-02T08:00:00Z")),
            ("end", text("2026-11-02T17:00:00Z")),
            ("event", text("e1")),
            ("value", Value::Bool(true)),
            ("priority", Value::UInt(4)),
            ("special", Value::Bool(false)),
        ])
    );
    assert_eq!(field(&rows[4], "start"), &text("2026-11-06T08:00:00Z"));
    let limited = h
        .invoke(
            "lobby",
            "get_events",
            map([
                (
                    "timerange",
                    text("2026-11-02T00:00:00Z/2026-11-09T00:00:00Z"),
                ),
                ("limit", Value::UInt(2)),
            ]),
        )
        .unwrap();
    assert!(matches!(limited, Value::Array(r) if r.len() == 2));
    for bad in [
        "2026-11-02",
        "2026-11-09T00:00:00Z/2026-11-02T00:00:00Z",
        "x/y",
    ] {
        let (st, msg) = status(h.invoke("lobby", "get_events", map([("timerange", text(bad))])));
        assert_eq!(st, Status::InvalidParameter);
        assert!(msg.starts_with("timerange"), "{bad}: {msg}");
    }
    assert_eq!(h.action("lobby", "get_events").level, Some(Perm::Read));
    assert_eq!(
        h.action("lobby", "get_events").params["timerange"]
            .editor
            .as_deref(),
        Some("daterange")
    );
}

/// The DSA localschedule 2.0.4 export of the `wyrm-schedule` fixture.
const DSA: &str = r#"{"name":"Lobby","value":false,"events":[
 {"name":"Open","id":"x","priority":2,"special":false,"value":true,
  "timeRange":{"sTime":"2026-10-05T08:00:00.000","eTime":"2026-10-05T17:00:00.000",
               "sDate":"2026-10-05T00:00:00.000","eDate":"2027-10-05T00:00:00.000","freq":2}}]}"#;

#[test]
fn export_import_round_trip() {
    let mut h = started();
    add_lobby(&mut h);
    h.invoke(
        "lobby",
        "add_event",
        daily(Value::Bool(true), "2026-10-29T08:00", "2026-10-29T17:00"),
    )
    .unwrap();
    let out = h.invoke("lobby", "export", Value::Null).unwrap();
    let Value::Str(json) = field(&out, "json").clone() else {
        panic!("{out:?}")
    };

    let mut fresh = started();
    let r = fresh
        .invoke("", "import", map([("json", text(&json))]))
        .unwrap();
    assert_eq!(r, map([("id", text("lobby"))]));
    assert!(fresh.has("lobby/events/e1"));
    assert_eq!(
        fresh.invoke("lobby", "export", Value::Null).unwrap(),
        out,
        "the same schedule"
    );
    assert_eq!(fresh.store_get("s/lobby"), h.store_get("s/lobby"));

    let (st, msg) = status(fresh.invoke("", "import", map([("json", text(&json))])));
    assert_eq!(st, Status::InvalidParameter);
    assert!(msg.contains("lobby exists"), "{msg}");

    // overwrite replaces: the copy without events
    let mut other = started();
    add_lobby(&mut other);
    let Value::Str(empty) = field(
        &other.invoke("lobby", "export", Value::Null).unwrap(),
        "json",
    )
    .clone() else {
        panic!()
    };
    fresh
        .invoke(
            "",
            "import",
            map([("json", text(&empty)), ("overwrite", Value::Bool(true))]),
        )
        .unwrap();
    assert!(!fresh.has("lobby/events/e1"));
    assert_eq!(fresh.store_get("s/lobby"), other.store_get("s/lobby"));

    // DSA JSON takes the zone from `default_tz` and its id from `id` (or the name)
    let mut kyiv = SimHost::new(t0());
    kyiv.start(map([("default_tz", text("Europe/Kyiv"))]))
        .unwrap();
    kyiv.settle();
    let r = kyiv
        .invoke("", "import", map([("json", text(DSA))]))
        .unwrap();
    assert_eq!(r, map([("id", text("Lobby"))]));
    assert_eq!(kyiv.attr("Lobby", "tz"), text("Europe/Kyiv"));
    assert_eq!(
        kyiv.attr("Lobby/events/e1", "start"),
        text("2026-10-05T08:00")
    );
    kyiv.invoke(
        "",
        "import",
        map([("json", text(DSA)), ("id", text("hall"))]),
    )
    .unwrap();
    assert!(kyiv.has("hall/events/e1"));
    assert_eq!(kyiv.action("", "import").level, Some(Perm::Config));
    assert_eq!(kyiv.action("", "add_schedule").level, Some(Perm::Write));
    assert_eq!(kyiv.action("hall", "export").level, Some(Perm::Read));
    assert_eq!(kyiv.action("hall", "add_event").level, Some(Perm::Write));
}

/// 08:00–17:00 daily, at 09:00.
fn in_window() -> SimHost {
    let mut h = started();
    add_lobby(&mut h);
    h.invoke(
        "lobby",
        "add_event",
        daily(Value::Bool(true), "2026-10-29T08:00", "2026-10-29T17:00"),
    )
    .unwrap();
    h.advance_to(at("2026-10-29T09:00:00Z"));
    assert_eq!(h.value("lobby/current"), Some(Value::Bool(true)));
    h
}

#[test]
fn clock_step_backward_inside_a_window() {
    let mut h = in_window();
    h.take_log();
    h.step_clock(-300_000);
    h.advance(WATCHDOG_MS);
    let log = h.take_log();
    assert!(
        !log.iter().any(|c| is_update(c, "lobby/current")),
        "same state, no write: {log:?}"
    );
    assert!(stepped(&log), "the step is logged: {log:?}");
    assert_eq!(h.app().next_wake(), Some(at("2026-10-29T17:00:00Z") as i64));
    h.advance_to(at("2026-10-29T17:00:00Z"));
    assert_eq!(h.value("lobby/current"), Some(Value::Bool(false)));
}

#[test]
fn clock_step_forward_over_a_boundary() {
    let mut h = in_window();
    h.advance_to(at("2026-10-29T16:00:00Z"));
    h.step_clock(7_200_000);
    h.advance(WATCHDOG_MS);
    assert_eq!(h.value("lobby/current"), Some(Value::Bool(false)));
    assert_eq!(h.attr("lobby", "next_time"), text("2026-10-30T08:00:00Z"));
}

#[test]
fn budgets_refuse_cleanly() {
    let mut h = started();
    add_lobby(&mut h);
    for i in 0..100u64 {
        h.invoke(
            "lobby",
            "add_event",
            map([
                ("value", Value::UInt(i)),
                ("start", text("2026-11-01T08:00")),
                ("end", text("2026-11-01T09:00")),
            ]),
        )
        .unwrap();
    }
    let (r, cmds) = h.invoke_cmds(
        "lobby",
        "add_event",
        map([
            ("value", Value::Null),
            ("start", text("2026-11-01T08:00")),
            ("end", text("2026-11-01T09:00")),
        ]),
    );
    let (st, msg) = status(r);
    assert_eq!(st, Status::ResourceExhausted);
    assert!(msg.contains("at most 100 events"), "{msg}");
    assert!(cmds.is_empty(), "{cmds:?}");

    // the node budget: 6 nodes per schedule, 1 per event
    let mut used = 6 + 100;
    let mut n = 0;
    loop {
        let id = format!("s{n}");
        let (r, cmds) = h.invoke_cmds(
            "",
            "add_schedule",
            map([("id", text(&id)), ("default", Value::Null)]),
        );
        if used + 6 > NODE_BUDGET {
            let (st, msg) = status(r);
            assert_eq!(st, Status::ResourceExhausted);
            assert!(msg.contains(&NODE_BUDGET.to_string()), "{msg}");
            assert!(
                !cmds
                    .iter()
                    .any(|c| matches!(c, Command::DeclareNode(..) | Command::StorePut(..))),
                "{cmds:?}"
            );
            assert!(!h.has(&id));
            break;
        }
        r.unwrap();
        used += 6;
        n += 1;
    }
    h.invoke("s0", "remove", Value::Null).unwrap();

    // a full store: the action fails and nothing is declared
    h.set_extra_used(STORE_BYTES - h.store_used());
    let (r, cmds) = h.invoke_cmds(
        "",
        "add_schedule",
        map([("id", text("full")), ("default", Value::Null)]),
    );
    let (st, _) = status(r);
    assert_eq!(st, Status::ResourceExhausted);
    assert!(!h.has("full"));
    assert!(h.store_get("s/full").is_none());
    assert!(
        !cmds.iter().any(|c| matches!(c, Command::DeclareNode(..))),
        "{cmds:?}"
    );
    let index = decode(&h.store_get("index").unwrap());
    assert!(!matches!(&index, Value::Array(a) if a.contains(&text("full"))));
}

fn schedule(id: &str, events: Vec<Event>) -> Schedule {
    let next_event = events.len() as u32 + 1;
    Schedule {
        id: id.into(),
        display: id.into(),
        tz: "UTC".into(),
        default: Value::Bool(false),
        enabled: true,
        events,
        next_event,
    }
}

fn event(n: u32, start: &str, end: &str, rule: Option<&str>) -> Event {
    Event {
        id: format!("e{n}"),
        display: String::new(),
        value: Value::Bool(true),
        priority: 0,
        special: false,
        start: parse_local("start", start).unwrap(),
        end: parse_local("end", end).unwrap(),
        recurrence: rule.map(|r| r.parse().unwrap()),
    }
}

/// A store of schedules as the app writes it.
fn seed(h: &mut SimHost, schedules: &[Schedule]) {
    let ids = schedules.iter().map(|s| text(&s.id)).collect();
    h.store_put(
        "index",
        wyrm_core::codec::to_vec(&Value::Array(ids)).unwrap(),
    );
    for s in schedules {
        h.store_put(
            &format!("s/{}", s.id),
            wyrm_core::codec::to_vec(&schedule_to_value(s)).unwrap(),
        );
    }
}

#[test]
fn command_budget_at_start() {
    // 1 000 × (6 + 2) = 8 000 nodes: within the budget (ruling R3)
    let schedules: Vec<Schedule> = (0..1000)
        .map(|i| {
            schedule(
                &format!("s{i}"),
                vec![
                    event(
                        1,
                        "2026-10-29T06:00",
                        "2026-10-29T08:00",
                        Some("FREQ=DAILY"),
                    ),
                    event(
                        2,
                        "2026-10-29T12:00",
                        "2026-10-29T13:00",
                        Some("FREQ=WEEKLY;BYDAY=MO,TH"),
                    ),
                ],
            )
        })
        .collect();
    let mut h = SimHost::new(t0());
    seed(&mut h, &schedules);
    let cmds = h.start(Value::Null).unwrap();
    assert!(cmds.len() <= COMMANDS_PER_EVENT, "{}", cmds.len());
    h.settle();
    assert!(h.max_cmds <= COMMANDS_PER_EVENT, "{}", h.max_cmds);
    assert!(h.events > 10, "several batches: {}", h.events);
    assert_eq!(h.nodes.len(), 8000);
    for i in 0..1000 {
        assert_eq!(
            h.value(&format!("s{i}/current")),
            Some(Value::Bool(true)),
            "s{i}: 07:00 is in 06:00–08:00"
        );
    }
    assert_eq!(h.live_timers(), 1, "one host timer");
    // a burst of 1 000 transitions at 08:00 is batched too
    h.max_cmds = 0;
    h.advance_to(at("2026-10-29T08:00:00Z"));
    assert!(h.max_cmds <= COMMANDS_PER_EVENT, "{}", h.max_cmds);
    for i in 0..1000 {
        assert_eq!(h.value(&format!("s{i}/current")), Some(Value::Bool(false)));
    }
}

#[test]
fn zero_messages_at_idle() {
    let schedules: Vec<Schedule> = (0..1000)
        .map(|i| {
            let hour = 9 + i % 12;
            let minute = i % 60;
            schedule(
                &format!("s{i}"),
                vec![event(
                    1,
                    &format!("2026-10-29T{hour:02}:{minute:02}"),
                    &format!("2026-10-29T{hour:02}:{minute:02}:30"),
                    Some("FREQ=DAILY"),
                )],
            )
        })
        .collect();
    let mut h = SimHost::new(t0());
    seed(&mut h, &schedules);
    h.start(Value::Null).unwrap();
    h.settle();
    assert_eq!(h.nodes.len(), 7000);
    h.take_log();
    let events = h.events;
    h.advance(3_600_000 - 1);
    let log = h.take_log();
    assert!(
        log.iter()
            .all(|c| matches!(c, Command::SetTimer(..) | Command::CancelTimer(..))),
        "only the watchdog: {:?}",
        log.iter()
            .find(|c| !matches!(c, Command::SetTimer(..) | Command::CancelTimer(..)))
    );
    let wakes = h.events - events;
    assert!(
        wakes <= (3_600_000 / WATCHDOG_MS) as usize + 1,
        "{wakes} wakes"
    );
}

#[test]
fn default_tz_param() {
    let mut h = SimHost::new(t0());
    h.start(map([("default_tz", text("Europe/Kyiv"))])).unwrap();
    add_lobby(&mut h);
    let stored = decode(&h.store_get("s/lobby").unwrap());
    assert_eq!(field(&stored, "tz"), &text("Europe/Kyiv"));

    let mut h = SimHost::new(t0());
    let e = h
        .start(map([("default_tz", text("Nowhere/X"))]))
        .expect_err("refused");
    assert_eq!(e.status, Status::InvalidParameter);
    assert!(e.msg.starts_with("params.default_tz"), "{}", e.msg);
    let e = h.start(map([("other", Value::Null)])).expect_err("refused");
    assert_eq!(e.msg, "params.other: unknown");
}

#[test]
fn add_event_refusals_name_the_field() {
    let mut h = started();
    add_lobby(&mut h);
    for (args, field) in [
        (
            daily(Value::Bool(true), "2026-10-29T08:00Z", "2026-10-29T17:00"),
            "start",
        ),
        (
            daily(
                Value::Bool(true),
                "2026-10-29T08:00",
                "2026-10-29T17:00+02:00",
            ),
            "end",
        ),
        (
            daily(Value::Bool(true), "2026-10-29T08:00", "2026-10-29T07:00"),
            "end",
        ),
        (
            daily(Value::Bool(true), "2026-10-29T08:00", "2026-10-30T09:00"),
            "end",
        ),
        (
            map([
                ("value", Value::Bool(true)),
                ("start", text("2026-10-29T08:00")),
                ("end", text("2026-10-29T09:00")),
                ("recurrence", text("FREQ=SECONDLY")),
            ]),
            "recurrence",
        ),
        (
            map([
                ("value", Value::Bool(true)),
                ("start", text("2026-10-29T08:00")),
                ("end", text("2026-10-29T09:00")),
                ("priority", Value::UInt(10)),
            ]),
            "priority",
        ),
        (
            map([
                ("start", text("2026-10-29T08:00")),
                ("end", text("2026-10-29T09:00")),
            ]),
            "value",
        ),
    ] {
        let (r, cmds) = h.invoke_cmds("lobby", "add_event", args);
        let (st, msg) = status(r);
        assert_eq!(st, Status::InvalidParameter);
        assert!(msg.starts_with(&format!("{field}:")), "{field}: {msg}");
        assert!(cmds.is_empty(), "{cmds:?}");
    }
    assert!(!h.has("lobby/events/e1"));
    let (st, _) = status(h.invoke("nowhere", "add_event", Value::Null));
    assert_eq!(st, Status::NotFound);
}

#[test]
fn a_moment_is_held_until_the_next_transition() {
    let mut h = started();
    add_lobby(&mut h);
    h.invoke(
        "lobby",
        "add_event",
        map([
            ("value", Value::UInt(5)),
            ("start", text("2026-10-29T08:00")),
            ("end", text("2026-10-29T08:00")),
        ]),
    )
    .unwrap();
    h.invoke(
        "lobby",
        "add_event",
        daily(Value::UInt(7), "2026-10-29T12:00", "2026-10-29T13:00"),
    )
    .unwrap();
    h.advance_to(at("2026-10-29T08:00:00Z"));
    assert_eq!(h.value("lobby/current"), Some(Value::UInt(5)));
    assert_eq!(h.attr("lobby", "source"), text("e1"));
    h.advance_to(at("2026-10-29T09:00:00Z"));
    // a clock step evaluates again and keeps the moment
    h.step_clock(-300_000);
    h.advance(WATCHDOG_MS);
    assert_eq!(h.value("lobby/current"), Some(Value::UInt(5)));
    assert_eq!(h.attr("lobby", "next_time"), text("2026-10-29T12:00:00Z"));
    h.advance_to(at("2026-10-29T12:00:00Z"));
    assert_eq!(h.value("lobby/current"), Some(Value::UInt(7)));
    // a restart does not replay the moment
    h.advance_to(at("2026-10-29T13:00:00Z"));
    h.restart().unwrap();
    h.settle();
    assert_eq!(h.value("lobby/current"), Some(Value::Bool(false)));
}

#[test]
fn a_backward_step_seen_by_an_action_is_not_lost() {
    let mut h = in_window();
    h.advance_to(at("2026-10-29T18:00:00Z"));
    assert_eq!(h.value("lobby/current"), Some(Value::Bool(false)));
    h.take_log();
    // back to 15:00, inside the window; a read action is the first event to see it
    h.step_clock(-3 * 3_600_000);
    h.invoke("lobby", "export", Value::Null).unwrap();
    h.settle();
    assert!(stepped(&h.take_log()), "the action sees the step");
    assert_eq!(h.value("lobby/current"), Some(Value::Bool(true)));
    assert_eq!(h.attr("lobby", "next_time"), text("2026-10-29T17:00:00Z"));
    // a set sees it too
    h.advance_to(at("2026-10-29T18:00:00Z"));
    assert_eq!(h.value("lobby/current"), Some(Value::Bool(false)));
    h.step_clock(-3 * 3_600_000);
    h.set("lobby/default", Value::Bool(false)).unwrap();
    h.settle();
    assert!(stepped(&h.take_log()));
    assert_eq!(h.value("lobby/current"), Some(Value::Bool(true)));
    h.advance_to(at("2026-10-29T17:00:00Z"));
    assert_eq!(h.value("lobby/current"), Some(Value::Bool(false)));
}

#[test]
fn a_moment_inside_a_long_burst_still_fires() {
    // 1 000 windows from 08:00 and a moment at 08:00:01; the burst is drained in several
    // continuations, each 2 s late in the host's queue, and the app's work takes time too
    let mut schedules: Vec<Schedule> = (0..1000)
        .map(|i| {
            schedule(
                &format!("s{i}"),
                vec![event(
                    1,
                    "2026-10-29T08:00",
                    "2026-10-29T09:00",
                    Some("FREQ=DAILY"),
                )],
            )
        })
        .collect();
    let mut m = schedule(
        "m",
        vec![event(1, "2026-10-29T08:00:01", "2026-10-29T08:00:01", None)],
    );
    m.events[0].value = Value::UInt(5);
    schedules.push(m);
    let mut h = SimHost::new(t0());
    seed(&mut h, &schedules);
    h.start(Value::Null).unwrap();
    h.settle();
    h.take_log();
    h.queue_latency_ms = 2_000;
    h.set_tick(100);
    let events = h.events;
    h.advance_to(at("2026-10-29T08:00:00Z"));
    // the continuations wait 2 s each in the queue: the moment's wake is taken after 08:00:03
    h.advance(20_000);
    assert!(h.events - events >= 4, "{} events", h.events - events);
    assert_eq!(
        h.value("m/current"),
        Some(Value::UInt(5)),
        "the moment fired"
    );
    assert_eq!(h.attr("m", "source"), text("e1"));
    for i in 0..1000 {
        assert_eq!(h.value(&format!("s{i}/current")), Some(Value::Bool(true)));
    }
    assert!(!stepped(&h.take_log()), "queued work is not a clock step");
}

#[test]
fn the_time_budget_splits_batches() {
    // R7: each wall clock read takes 10 ms, so 500 ms of work end the event
    let schedules: Vec<Schedule> = (0..200)
        .map(|i| schedule(&format!("s{i}"), vec![]))
        .collect();
    let mut h = SimHost::new(t0());
    seed(&mut h, &schedules);
    h.set_tick(10_000);
    h.start(Value::Null).unwrap();
    h.settle();
    assert_eq!(h.nodes.len(), 200 * 6, "all loaded");
    assert!(h.events > 10, "{} events", h.events);
    assert!(
        h.max_cmds < COMMANDS_PER_EVENT / 2,
        "time, not commands, split them"
    );
    assert!(h.max_event_us < 700_000, "{} us", h.max_event_us);
    assert!(!stepped(&h.take_log()));
}

#[test]
fn a_moment_due_in_the_last_batch_keeps_its_base() {
    // K windows at 08:00 and a moment at 08:00:03 that falls due while the last batch of the
    // burst runs; its continuation waits 2.2 s in the queue (review probe, fix round 2)
    for (k, tick) in [(200usize, 2_000u64), (400, 1_000), (450, 1_000)] {
        let mut v: Vec<Schedule> = (0..k)
            .map(|i| {
                schedule(
                    &format!("s{i}"),
                    vec![event(
                        1,
                        "2026-10-29T08:00",
                        "2026-10-29T09:00",
                        Some("FREQ=DAILY"),
                    )],
                )
            })
            .collect();
        let mut m = schedule(
            "m",
            vec![event(1, "2026-10-29T08:00:03", "2026-10-29T08:00:03", None)],
        );
        m.events[0].value = Value::UInt(5);
        v.push(m);
        let mut h = SimHost::new(t0());
        seed(&mut h, &v);
        h.start(Value::Null).unwrap();
        h.settle();
        h.advance_to(at("2026-10-29T07:59:00Z"));
        h.take_log();
        h.queue_latency_ms = 2_200;
        h.set_tick(tick);
        h.advance(120_000);
        assert_eq!(
            h.value("m/current"),
            Some(Value::UInt(5)),
            "k {k}, tick {tick}: the moment fired"
        );
        assert!(!stepped(&h.take_log()));
    }
}
