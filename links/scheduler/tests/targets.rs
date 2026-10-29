//! The scheduler's targets through `SimHost`: the write queue, the three confirm modes,
//! retries with backoff, manual override, the restart rules, and the target nodes and actions
//! (ADR 0022 "Targets", plan Task 4).

mod common;

use common::*;
use wyrm_core::{Perm, Status, Value};
use wyrm_link_api::buffer::Command;
use wyrm_link_api::{AppError, Who};
use wyrm_link_scheduler::limits::{
    COMMANDS_PER_EVENT, CONFIRM_TIMEOUT_MS, FIRST_SAMPLE_MS, MAX_INFLIGHT, MAX_SUBS, RETRY_CAP_MS,
    RETRY_FIRST_MS,
};

const FAN: &str = "wy/s/downstream/plc/fan";
const FAN_STATUS: &str = "wy/s/downstream/plc/fan_status";
const PUMP: &str = "wy/s/downstream/plc/pump";
const FREE: &str = "wy/s/downstream/plc/free";

fn daily(value: Value) -> Value {
    map([
        ("value", value),
        ("start", text("2026-10-29T08:00")),
        ("end", text("2026-10-29T17:00")),
        ("recurrence", text("FREQ=DAILY")),
    ])
}

/// Schedule `id`: `false`, `true` daily 08:00–17:00.
fn add_schedule(h: &mut SimHost, id: &str) {
    h.invoke(
        "",
        "add_schedule",
        map([("id", text(id)), ("default", Value::Bool(false))]),
    )
    .expect("add_schedule");
    h.invoke(id, "add_event", daily(Value::Bool(true)))
        .expect("add_event");
}

/// A started scheduler at 07:00 with schedule `lobby`.
fn lobby() -> SimHost {
    let mut h = started();
    add_schedule(&mut h, "lobby");
    h
}

fn read_back(point: &str) -> Value {
    map([("point", text(point)), ("confirm", text("read_back"))])
}

fn add_target(h: &mut SimHost, sid: &str, args: Value) -> Result<Value, AppError> {
    h.invoke(sid, "add_target", args)
}

/// The one set without a reply.
fn one_set(h: &SimHost) -> (u64, String, Value) {
    let due = h.unreplied();
    assert_eq!(due.len(), 1, "one set waits: {due:?}");
    due.into_iter().next().unwrap()
}

fn state(h: &SimHost, path: &str) -> Value {
    h.value(path).unwrap_or_else(|| panic!("{path}: no value"))
}

fn decode(bytes: &[u8]) -> Value {
    wyrm_core::codec::from_slice::<Value>(bytes).unwrap()
}

fn outcome(h: &SimHost, key: &str) -> Option<Value> {
    h.store_get(key).map(|b| decode(&b))
}

fn record(value: Value, source: &str, outcome: &str) -> Value {
    map([
        ("value", value),
        ("source", text(source)),
        ("outcome", text(outcome)),
    ])
}

fn subscribes(log: &[Command], key: &str) -> usize {
    log.iter()
        .filter(|c| matches!(c, Command::Subscribe(_, k) if k == key))
        .count()
}

fn unsubscribes(log: &[Command]) -> usize {
    log.iter()
        .filter(|c| matches!(c, Command::Unsubscribe(_)))
        .count()
}

fn logged(log: &[Command], text: &str) -> bool {
    log.iter()
        .any(|c| matches!(c, Command::Log(_, m) if m.contains(text)))
}

fn err(status: Status, msg: &str) -> Result<Value, AppError> {
    Err(AppError::new(status, msg))
}

#[test]
fn target_actions_are_config() {
    let mut h = lobby();
    assert_eq!(h.action("lobby", "add_target").level, Some(Perm::Config));
    assert_eq!(h.action("", "import").level, Some(Perm::Config));
    add_target(&mut h, "lobby", read_back(FAN)).unwrap();
    for a in ["edit", "enable", "disable", "remove"] {
        assert_eq!(
            h.action("lobby/targets/t1", a).level,
            Some(Perm::Config),
            "{a}"
        );
    }
    assert_eq!(h.attr("lobby/targets/t1", "created_by"), text("user:test"));
    assert_eq!(h.attr("lobby/targets/t1", "point"), text(FAN));
    assert_eq!(h.attr("lobby/targets/t1", "confirm"), text("read_back"));

    // no subject: created_by is empty
    let anon = Who::default();
    let (r, _) = h.invoke_as(&anon, "lobby", "add_target", read_back(PUMP));
    assert_eq!(r.unwrap(), map([("id", text("t2"))]));
    assert_eq!(h.attr("lobby/targets/t2", "created_by"), text(""));
}

/// The responder hands an enum arg as its index (`read_back | feedback | ack`); an import
/// carries the text.
#[test]
fn confirm_by_enum_index() {
    let mut h = lobby();
    let by_index = |point: &str, i: u64| map([("point", text(point)), ("confirm", Value::UInt(i))]);
    add_target(&mut h, "lobby", by_index(FAN, 2)).unwrap();
    assert_eq!(h.attr("lobby/targets/t1", "confirm"), text("ack"));
    add_target(&mut h, "lobby", by_index(PUMP, 0)).unwrap();
    assert_eq!(h.attr("lobby/targets/t2", "confirm"), text("read_back"));
    for bad in [Value::UInt(3), Value::Bool(true), text("never")] {
        let args = map([("point", text(FREE)), ("confirm", bad.clone())]);
        let (st, msg) = status(add_target(&mut h, "lobby", args));
        assert_eq!(st, Status::InvalidParameter, "{bad:?}");
        assert!(msg.contains("confirm"), "{bad:?}: {msg}");
    }
}

#[test]
fn add_target_checks_the_point() {
    let mut h = lobby();
    let keys_before = h.store_keys();
    let s_before = h.store_get("s/lobby");
    for bad in [
        "wy/s/upstream/x/fan",
        "wy/s/downstream/plc",
        "wy/s/downstream/plc/*",
        "wy/s/downstream/plc/**",
        "wy/s/downstream/plc/~val",
        "wy/s/downstream//fan",
        "wy/s/downstream/plc/fan/",
        "plc/fan",
    ] {
        let (r, cmds) = h.invoke_cmds("lobby", "add_target", read_back(bad));
        let (st, msg) = status(r);
        assert_eq!(st, Status::InvalidParameter, "{bad}");
        assert!(msg.contains("point"), "{bad}: {msg}");
        assert!(cmds.is_empty(), "{bad}: {cmds:?}");
    }
    // the feedback key is checked the same way
    let (st, msg) = status(add_target(
        &mut h,
        "lobby",
        map([
            ("point", text(FAN)),
            ("confirm", text("feedback")),
            ("feedback", text("wy/s/downstream/plc/~x")),
        ]),
    ));
    assert_eq!(st, Status::InvalidParameter);
    assert!(msg.contains("feedback"), "{msg}");
    let (st, msg) = status(add_target(
        &mut h,
        "lobby",
        map([("point", text(FAN)), ("confirm", text("feedback"))]),
    ));
    assert_eq!(st, Status::InvalidParameter);
    assert!(msg.contains("feedback"), "{msg}");

    // outside the site: the host refuses the subscribe, and so the target
    let (r, cmds) = h.invoke_cmds(
        "lobby",
        "add_target",
        read_back("wy/other/downstream/plc/x"),
    );
    let (st, msg) = status(r);
    assert_eq!(st, Status::PermissionDenied, "{msg}");
    assert!(!cmds
        .iter()
        .any(|c| matches!(c, Command::StorePut(..) | Command::DeclareNode(..))));
    assert!(h.subs.is_empty(), "{:?}", h.subs);
    assert!(!h.has("lobby/targets/t1"));
    assert_eq!(h.store_keys(), keys_before);
    assert_eq!(h.store_get("s/lobby"), s_before);

    // one writer per point
    add_target(&mut h, "lobby", read_back(FAN)).unwrap();
    add_schedule(&mut h, "hall");
    let (r, cmds) = h.invoke_cmds("hall", "add_target", read_back(FAN));
    let (st, msg) = status(r);
    assert_eq!(st, Status::InvalidParameter);
    assert!(msg.contains("written by lobby/t1"), "{msg}");
    assert!(cmds.is_empty(), "{cmds:?}");

    // the 21st target
    for i in 1..20 {
        add_target(
            &mut h,
            "lobby",
            read_back(&format!("wy/s/downstream/plc/p{i}")),
        )
        .unwrap();
    }
    let (r, cmds) = h.invoke_cmds("lobby", "add_target", read_back(PUMP));
    let (st, msg) = status(r);
    assert_eq!(st, Status::ResourceExhausted);
    assert!(msg.contains("20 targets"), "{msg}");
    assert!(cmds.is_empty(), "{cmds:?}");
    assert!(!h.has("lobby/targets/t21"));
}

#[test]
fn read_back_confirms() {
    let mut h = lobby();
    let r = add_target(&mut h, "lobby", read_back(FAN)).unwrap();
    assert_eq!(r, map([("id", text("t1"))]));
    assert_eq!(h.subscribed(FAN), 1);
    // a new target gets the value now
    let (_, key, v) = one_set(&h);
    assert_eq!((key.as_str(), v), (FAN, Value::Bool(false)));
    h.confirm_all();
    assert_eq!(state(&h, "lobby/targets/t1"), text("confirmed"));

    h.take_log();
    h.advance_to(at("2026-10-29T08:00:00Z"));
    assert_eq!(
        sets_of(&h.take_log()),
        vec![(FAN.to_owned(), Value::Bool(true))]
    );
    assert_eq!(state(&h, "lobby/targets/t1"), text("writing"));
    let (req, ..) = one_set(&h);
    h.reply(req, Ok(Value::Null));
    assert_eq!(
        state(&h, "lobby/targets/t1"),
        text("writing"),
        "waits for the value"
    );
    // another value is not the confirmation
    h.deliver(FAN, Value::Bool(false));
    assert_eq!(state(&h, "lobby/targets/t1"), text("writing"));
    h.deliver(FAN, Value::Bool(true));
    assert_eq!(state(&h, "lobby/targets/t1"), text("confirmed"));
    assert_eq!(
        outcome(&h, "o/lobby/t1"),
        Some(record(
            Value::Bool(true),
            "event:e1@2026-10-29T08:00:00Z",
            "confirmed"
        ))
    );
    assert_eq!(
        h.attr("lobby/targets/t1", "last_write"),
        text("2026-10-29T08:00:00Z")
    );
    assert_eq!(h.attr("lobby/targets/t1", "attempts"), Value::UInt(1));
    assert_eq!(h.attr("lobby/targets/t1", "last_error"), Value::Null);
    let log = h.take_log();
    assert!(logged(&log, "target lobby/t1 confirmed"), "{log:?}");
    // no value in the log
    assert!(!log
        .iter()
        .any(|c| matches!(c, Command::Log(_, m) if m.contains("true"))));
}

#[test]
fn an_unchanged_value_confirms_on_ok() {
    // links publish a value only when it changes: a write of the value the point shows brings
    // no new sample
    let mut h = lobby();
    add_target(&mut h, "lobby", read_back(FAN)).unwrap();
    h.confirm_all();
    h.set("lobby/enabled", Value::Bool(false)).unwrap();
    h.set("lobby/enabled", Value::Bool(true)).unwrap();
    let (req, _, v) = one_set(&h);
    assert_eq!(v, Value::Bool(false), "turned on: written again");
    h.reply(req, Ok(Value::Null));
    assert_eq!(state(&h, "lobby/targets/t1"), text("confirmed"));
    h.advance(2 * CONFIRM_TIMEOUT_MS);
    assert_eq!(state(&h, "lobby/targets/t1"), text("confirmed"));
    assert!(h.unreplied().is_empty());

    // a different last value still waits for the sample
    h.deliver(FAN, Value::Bool(true));
    assert_eq!(state(&h, "lobby/targets/t1"), text("override"));
    h.advance_to(at("2026-10-29T08:00:00Z"));
    let (req, _, v) = one_set(&h);
    assert_eq!(v, Value::Bool(true));
    h.reply(req, Ok(Value::Null));
    assert_eq!(
        state(&h, "lobby/targets/t1"),
        text("writing"),
        "the new subscription has no sample yet"
    );
}

#[test]
fn feedback_confirms_on_the_other_point() {
    let mut h = lobby();
    add_target(
        &mut h,
        "lobby",
        map([
            ("point", text(FAN)),
            ("confirm", text("feedback")),
            ("feedback", text(FAN_STATUS)),
            (
                "feedback_map",
                map([("true", Value::UInt(1)), ("false", Value::UInt(0))]),
            ),
        ]),
    )
    .unwrap();
    assert_eq!(h.subscribed(FAN), 0, "the point is only checked");
    assert_eq!(h.subscribed(FAN_STATUS), 1);
    assert_eq!(h.attr("lobby/targets/t1", "feedback"), text(FAN_STATUS));
    let (req, key, v) = one_set(&h);
    assert_eq!((key.as_str(), v), (FAN, Value::Bool(false)));
    h.reply(req, Ok(Value::Null));
    h.deliver(FAN_STATUS, Value::UInt(0));
    assert_eq!(state(&h, "lobby/targets/t1"), text("confirmed"));

    h.advance_to(at("2026-10-29T08:00:00Z"));
    let (req, key, v) = one_set(&h);
    assert_eq!((key.as_str(), v), (FAN, Value::Bool(true)));
    h.reply(req, Ok(Value::Null));
    assert_eq!(h.deliver(FAN, Value::Bool(true)), 0, "fan is not watched");
    h.deliver(FAN_STATUS, Value::UInt(0));
    assert_eq!(state(&h, "lobby/targets/t1"), text("writing"));
    h.deliver(FAN_STATUS, Value::UInt(1));
    assert_eq!(state(&h, "lobby/targets/t1"), text("confirmed"));
}

#[test]
fn ack_confirms_on_reply() {
    let mut h = lobby();
    let (r, cmds) = h.invoke_cmds(
        "lobby",
        "add_target",
        map([("point", text(FAN)), ("confirm", text("ack"))]),
    );
    r.unwrap();
    assert_eq!(subscribes(&cmds, FAN), 1, "the site check");
    assert_eq!(unsubscribes(&cmds), 1, "dropped in the same event");
    assert!(h.subs.is_empty());
    let (req, ..) = one_set(&h);
    h.reply(req, Ok(Value::Null));
    assert_eq!(state(&h, "lobby/targets/t1"), text("confirmed"));
    assert!(outcome(&h, "o/lobby/t1").is_some());

    h.advance_to(at("2026-10-29T08:00:00Z"));
    let (req, _, v) = one_set(&h);
    assert_eq!(v, Value::Bool(true));
    assert_eq!(state(&h, "lobby/targets/t1"), text("writing"));
    h.reply(req, Ok(Value::Null));
    assert_eq!(state(&h, "lobby/targets/t1"), text("confirmed"));
    assert!(h.subs.is_empty(), "no subscription kept");
}

#[test]
fn map_and_tolerance() {
    let mut h = lobby();
    add_target(
        &mut h,
        "lobby",
        map([
            ("point", text(FAN)),
            ("confirm", text("read_back")),
            (
                "map",
                map([("true", Value::UInt(1)), ("false", Value::UInt(0))]),
            ),
        ]),
    )
    .unwrap();
    let (_, _, v) = one_set(&h);
    assert_eq!(v, Value::UInt(0));
    h.confirm_all();
    h.advance_to(at("2026-10-29T08:00:00Z"));
    let (req, _, v) = one_set(&h);
    assert_eq!(v, Value::UInt(1));
    h.reply(req, Ok(Value::Null));
    h.deliver(FAN, Value::Float(1.1));
    assert_eq!(
        state(&h, "lobby/targets/t1"),
        text("writing"),
        "1.1 is not 1"
    );
    h.deliver(FAN, Value::Float(1.000_000_1));
    assert_eq!(state(&h, "lobby/targets/t1"), text("confirmed"));

    // a map given as JSON text, a tolerance, and `true` read back as 1
    add_target(
        &mut h,
        "lobby",
        map([
            ("point", text(PUMP)),
            ("confirm", text("read_back")),
            ("map", text(r#"{"true": 50, "false": 0}"#)),
            ("tolerance", Value::Float(0.1)),
        ]),
    )
    .unwrap();
    let (req, _, v) = one_set(&h);
    assert_eq!(v, Value::UInt(50));
    h.reply(req, Ok(Value::Null));
    h.deliver(PUMP, Value::Float(46.0));
    assert_eq!(
        state(&h, "lobby/targets/t2"),
        text("confirmed"),
        "within 10 %"
    );

    add_target(&mut h, "lobby", read_back(FREE)).unwrap();
    let (req, _, v) = one_set(&h);
    assert_eq!(v, Value::Bool(true));
    h.reply(req, Ok(Value::Null));
    h.deliver(FREE, Value::UInt(1));
    assert_eq!(
        state(&h, "lobby/targets/t3"),
        text("confirmed"),
        "true is 1"
    );
}

/// Steps the clock in 10 ms until a set waits; the milliseconds that took.
fn until_set(h: &mut SimHost, max_ms: u64) -> u64 {
    let mut waited = 0;
    while h.unreplied().is_empty() {
        assert!(waited <= max_ms, "no set within {max_ms} ms");
        h.advance(10);
        waited += 10;
    }
    waited
}

#[test]
fn retries_with_backoff() {
    let mut h = lobby();
    add_target(&mut h, "lobby", read_back(FAN)).unwrap();
    let mut base = RETRY_FIRST_MS;
    for attempt in 1..=9u64 {
        let (req, key, v) = one_set(&h);
        assert_eq!((key.as_str(), v), (FAN, Value::Bool(false)));
        let log = h.reply(req, err(Status::Timeout, "no answer from the device"));
        assert_eq!(state(&h, "lobby/targets/t1"), text("retrying"));
        assert_eq!(
            h.attr("lobby/targets/t1", "last_error"),
            text("timeout: no answer from the device")
        );
        assert_eq!(h.attr("lobby/targets/t1", "attempts"), Value::UInt(attempt));
        assert!(
            logged(&log, "target lobby/t1 retrying (timeout)"),
            "{log:?}"
        );
        let delay = base.min(RETRY_CAP_MS);
        let waited = until_set(&mut h, delay * 6 / 5 + 20);
        assert!(
            waited + 10 >= delay * 4 / 5 && waited <= delay * 6 / 5 + 10,
            "attempt {attempt}: {waited} ms for {delay} ms"
        );
        base *= 2;
    }
    // a newer transition cancels the retry and writes the new value
    let (req, ..) = one_set(&h);
    h.reply(req, err(Status::Timeout, "no answer"));
    h.take_log();
    h.set("lobby/default", Value::Bool(true)).unwrap();
    let (req, _, v) = one_set(&h);
    assert_eq!(v, Value::Bool(true));
    h.reply(req, Ok(Value::Null));
    h.deliver(FAN, Value::Bool(true));
    assert_eq!(state(&h, "lobby/targets/t1"), text("confirmed"));
    h.advance(2 * RETRY_CAP_MS);
    assert!(h.unreplied().is_empty(), "the retry of false is gone");
    assert_eq!(h.attr("lobby/targets/t1", "last_error"), Value::Null);

    // no matching value 10 s after `ok`: a retry
    h.set("lobby/default", Value::Bool(false)).unwrap();
    let (req, ..) = one_set(&h);
    h.reply(req, Ok(Value::Null));
    h.advance(CONFIRM_TIMEOUT_MS - 100);
    assert_eq!(state(&h, "lobby/targets/t1"), text("writing"));
    h.advance(100);
    assert_eq!(state(&h, "lobby/targets/t1"), text("retrying"));
    let Value::Str(e) = h.attr("lobby/targets/t1", "last_error") else {
        panic!()
    };
    assert!(e.starts_with("timeout"), "{e}");
    until_set(&mut h, RETRY_FIRST_MS * 6 / 5 + 20);
    let (_, _, v) = one_set(&h);
    assert_eq!(v, Value::Bool(false));
}

#[test]
fn a_retry_survives_a_clock_step() {
    for step_ms in [-300_000i64, 300_000] {
        let mut h = lobby();
        add_target(&mut h, "lobby", read_back(FAN)).unwrap();
        let (req, ..) = one_set(&h);
        h.reply(req, err(Status::Busy, "later"));
        assert_eq!(state(&h, "lobby/targets/t1"), text("retrying"));
        h.step_clock(step_ms);
        let waited = until_set(&mut h, 2 * RETRY_FIRST_MS);
        assert!(waited <= RETRY_FIRST_MS * 6 / 5 + 10, "{step_ms}: {waited}");
        assert!(stepped(&h.take_log()), "{step_ms}: the step is seen");
    }
}

fn stepped(log: &[Command]) -> bool {
    logged(log, "wall clock stepped")
}

#[test]
fn override_is_respected() {
    let mut h = lobby();
    add_target(&mut h, "lobby", read_back(FAN)).unwrap();
    h.confirm_all();
    h.advance_to(at("2026-10-29T08:00:00Z"));
    h.confirm_all();
    assert_eq!(state(&h, "lobby/targets/t1"), text("confirmed"));
    h.take_log();
    h.advance_to(at("2026-10-29T10:00:00Z"));
    // a person switched it off
    h.deliver(FAN, Value::Bool(false));
    assert_eq!(state(&h, "lobby/targets/t1"), text("override"));
    assert_eq!(
        outcome(&h, "o/lobby/t1"),
        Some(record(
            Value::Bool(true),
            "event:e1@2026-10-29T08:00:00Z",
            "override"
        ))
    );
    assert_eq!(
        h.subscribed(FAN),
        0,
        "nothing to watch until the next transition"
    );
    let log = h.take_log();
    assert!(logged(&log, "target lobby/t1 override"), "{log:?}");
    h.advance_to(at("2026-10-29T16:59:00Z"));
    assert!(sets_of(&h.take_log()).is_empty(), "the person wins");

    h.advance_to(at("2026-10-29T17:00:00Z"));
    assert_eq!(
        sets_of(&h.take_log()),
        vec![(FAN.to_owned(), Value::Bool(false))]
    );
    assert_eq!(h.subscribed(FAN), 1);
    h.confirm_all();
    assert_eq!(state(&h, "lobby/targets/t1"), text("confirmed"));
}

#[test]
fn burst_of_1000() {
    let mut h = started();
    for i in 0..1000 {
        let s = format!("s{i}");
        add_schedule(&mut h, &s);
        add_target(&mut h, &s, read_back(&format!("wy/s/downstream/plc/p{i}"))).unwrap();
        h.confirm_all();
    }
    h.take_log();
    h.max_cmds = 0;
    h.max_unreplied = 0;
    h.advance_to(at("2026-10-29T08:00:00Z"));
    let mut written = 0;
    loop {
        h.settle();
        let due = h.unreplied();
        if due.is_empty() {
            break;
        }
        assert!(due.len() <= MAX_INFLIGHT, "{}", due.len());
        for (id, key, v) in due {
            assert_eq!(v, Value::Bool(true));
            h.reply(id, Ok(Value::Null));
            h.deliver(&key, v);
            written += 1;
        }
    }
    assert_eq!(written, 1000);
    assert_eq!(h.max_unreplied, MAX_INFLIGHT, "the queue held the rest");
    assert!(h.max_cmds <= COMMANDS_PER_EVENT, "{}", h.max_cmds);
    for i in 0..1000 {
        assert_eq!(
            state(&h, &format!("s{i}/targets/t1")),
            text("confirmed"),
            "s{i}"
        );
    }
    let log = h.take_log();
    assert!(!logged(&log, "refused"), "no host refusal reaches the app");
    assert!(!logged(&log, "retrying"));
}

#[test]
fn restart_keeps_override_and_confirmed() {
    let mut h = started();
    let point = |s: &str| format!("wy/s/downstream/plc/{s}");
    for s in ["a", "b", "c", "d"] {
        add_schedule(&mut h, s);
        add_target(&mut h, s, read_back(&point(s))).unwrap();
    }
    h.confirm_all();
    h.advance_to(at("2026-10-29T08:00:00Z"));
    h.confirm_all();
    h.deliver(&point("b"), Value::Bool(false));
    assert_eq!(state(&h, "b/targets/t1"), text("override"));
    // c's record is for yesterday's window, d has none
    h.store_put(
        "o/c/t1",
        wyrm_core::codec::to_vec(&record(
            Value::Bool(true),
            "event:e1@2026-10-28T08:00:00Z",
            "confirmed",
        ))
        .unwrap(),
    );
    h.store_delete("o/d/t1");
    h.advance_to(at("2026-10-29T09:00:00Z"));
    h.take_log();

    let cmds = h.restart().unwrap();
    h.settle();
    let mut log = cmds;
    log.extend(h.take_log());
    assert!(sets_of(&log).is_empty(), "{:?}", sets_of(&log));
    assert_eq!(state(&h, "a/targets/t1"), text("confirmed"));
    assert_eq!(h.subscribed(&point("a")), 1, "override watch");
    assert_eq!(state(&h, "b/targets/t1"), text("override"));
    assert_eq!(h.subscribed(&point("b")), 0);
    assert_eq!(h.subscribed(&point("c")), 1);
    assert_eq!(h.subscribed(&point("d")), 1);

    // d already shows the value: confirmed without a write
    h.deliver(&point("d"), Value::Bool(true));
    assert_eq!(state(&h, "d/targets/t1"), text("confirmed"));
    // c: no sample within the wait, so it is written
    h.advance(FIRST_SAMPLE_MS - 10);
    assert!(h.unreplied().is_empty());
    h.advance(10);
    assert_eq!(
        sets_of(&h.take_log()),
        vec![(point("c"), Value::Bool(true))]
    );
    h.confirm_all();
    assert_eq!(state(&h, "c/targets/t1"), text("confirmed"));
    assert_eq!(state(&h, "a/targets/t1"), text("confirmed"));
    assert_eq!(state(&h, "b/targets/t1"), text("override"));

    // a person's change while the link was down is an override at the first sample
    h.deliver(&point("a"), Value::Bool(false));
    assert_eq!(state(&h, "a/targets/t1"), text("override"));
}

#[test]
fn disable_and_remove() {
    let mut h = lobby();
    add_target(&mut h, "lobby", read_back(FAN)).unwrap();
    h.confirm_all();
    h.invoke("lobby/targets/t1", "disable", Value::Null)
        .unwrap();
    assert_eq!(state(&h, "lobby/targets/t1"), text("disabled"));
    assert_eq!(h.subscribed(FAN), 0);
    h.take_log();
    h.advance_to(at("2026-10-29T08:00:00Z"));
    assert!(sets_of(&h.take_log()).is_empty());

    let (r, cmds) = h.invoke_cmds("lobby/targets/t1", "enable", Value::Null);
    r.unwrap();
    assert_eq!(sets_of(&cmds), vec![(FAN.to_owned(), Value::Bool(true))]);
    assert_eq!(state(&h, "lobby/targets/t1"), text("writing"));
    h.confirm_all();
    assert!(outcome(&h, "o/lobby/t1").is_some());

    h.invoke("lobby/targets/t1", "remove", Value::Null).unwrap();
    assert!(!h.has("lobby/targets/t1"));
    assert!(outcome(&h, "o/lobby/t1").is_none());
    assert_eq!(h.subscribed(FAN), 0);

    // ids are not reused; removing the schedule removes its targets
    let r = add_target(&mut h, "lobby", read_back(FAN)).unwrap();
    assert_eq!(r, map([("id", text("t2"))]));
    add_target(&mut h, "lobby", read_back(PUMP)).unwrap();
    h.confirm_all();
    assert!(outcome(&h, "o/lobby/t2").is_some());
    h.invoke("lobby", "remove", Value::Null).unwrap();
    assert!(h.subs.is_empty(), "{:?}", h.subs);
    assert!(!h.has("lobby"));
    assert_eq!(h.store_keys(), vec!["index".to_owned()]);
}

fn export(h: &mut SimHost, sid: &str) -> serde_json::Value {
    let out = h.invoke(sid, "export", Value::Null).unwrap();
    let Value::Map(m) = out else { panic!() };
    let Some(Value::Str(json)) = m.get("json") else {
        panic!()
    };
    serde_json::from_str(json).unwrap()
}

fn import(h: &mut SimHost, json: &serde_json::Value) -> (Result<Value, AppError>, Vec<Command>) {
    let who = Who {
        subject: Some("user:importer".into()),
        grants: vec![],
    };
    h.invoke_as(&who, "", "import", map([("json", text(&json.to_string()))]))
}

#[test]
fn import_with_targets_runs_target_checks() {
    let mut src = lobby();
    add_target(&mut src, "lobby", read_back(FAN)).unwrap();
    let json = export(&mut src, "lobby");
    assert_eq!(json["targets"][0]["point"], FAN);
    assert_eq!(json["targets"][0]["id"], "t1");

    let refused = |json: &serde_json::Value, setup: &dyn Fn(&mut SimHost)| {
        let mut h = started();
        setup(&mut h);
        let keys = h.store_keys();
        let subs = h.subs.clone();
        let (r, cmds) = import(&mut h, json);
        let e = r.expect_err("refused");
        assert!(
            !cmds.iter().any(|c| matches!(
                c,
                Command::StorePut(..) | Command::DeclareNode(..) | Command::Set(..)
            )),
            "{cmds:?}"
        );
        assert_eq!(h.store_keys(), keys, "nothing saved");
        assert_eq!(h.subs, subs, "no subscription left");
        assert!(!h.has("lobby"));
        e
    };

    // outside the site
    let mut outside = json.clone();
    outside["targets"][0]["point"] = "wy/other/downstream/plc/fan".into();
    let e = refused(&outside, &|_| {});
    assert_eq!(e.status, Status::PermissionDenied, "{e}");

    // a point another schedule writes
    let e = refused(&json, &|h| {
        add_schedule(h, "hall");
        add_target(h, "hall", read_back(FAN)).unwrap();
    });
    assert_eq!(e.status, Status::InvalidParameter);
    assert!(e.msg.contains("written by hall/t1"), "{e}");

    // the same point twice in the import
    let mut twice = json.clone();
    let mut t2 = json["targets"][0].clone();
    t2["id"] = "t2".into();
    twice["targets"].as_array_mut().unwrap().push(t2);
    let e = refused(&twice, &|_| {});
    assert_eq!(e.status, Status::InvalidParameter);
    assert!(e.msg.contains("written by lobby/t1"), "{e}");

    // 21 targets
    let mut many = json.clone();
    let list = many["targets"].as_array_mut().unwrap();
    list.clear();
    for i in 1..=21 {
        let mut t = json["targets"][0].clone();
        t["id"] = format!("t{i}").into();
        t["point"] = format!("wy/s/downstream/plc/p{i}").into();
        list.push(t);
    }
    many["next_target"] = 22.into();
    let e = refused(&many, &|_| {});
    assert_eq!(e.status, Status::ResourceExhausted);
    assert!(e.msg.contains("20 targets"), "{e}");

    // a bad target field names it
    let mut bad = json.clone();
    bad["targets"][0]["confirm"] = "maybe".into();
    let e = refused(&bad, &|_| {});
    assert_eq!(e.status, Status::InvalidParameter);
    assert!(e.msg.contains("targets[0].confirm"), "{e}");

    // a valid one
    let mut h = started();
    let (r, _) = import(&mut h, &json);
    assert_eq!(r.unwrap(), map([("id", text("lobby"))]));
    assert_eq!(
        h.attr("lobby/targets/t1", "created_by"),
        text("user:importer")
    );
    assert_eq!(h.subscribed(FAN), 1);
    let (_, key, v) = one_set(&h);
    assert_eq!((key.as_str(), v), (FAN, Value::Bool(false)));
    h.confirm_all();
    // the next id goes on from the export
    let r = add_target(&mut h, "lobby", read_back(PUMP)).unwrap();
    assert_eq!(r, map([("id", text("t2"))]));

    // overwrite: the replaced schedule's own points are free
    let (r, _) = h.invoke_as(
        &Who::default(),
        "",
        "import",
        map([
            ("json", text(&json.to_string())),
            ("overwrite", Value::Bool(true)),
        ]),
    );
    r.unwrap();
    assert!(!h.has("lobby/targets/t2"));
    assert!(
        outcome(&h, "o/lobby/t1").is_none(),
        "the old record is gone"
    );
    assert_eq!(h.subscribed(FAN), 1);
    assert_eq!(h.subscribed(PUMP), 0);
}

#[test]
fn target_edit_rechecks_the_point() {
    let mut h = started();
    add_schedule(&mut h, "lobby");
    add_schedule(&mut h, "hall");
    add_target(&mut h, "lobby", read_back(FAN)).unwrap();
    add_target(&mut h, "hall", read_back(PUMP)).unwrap();
    h.confirm_all();
    let (r, cmds) = h.invoke_cmds("lobby/targets/t1", "edit", map([("point", text(PUMP))]));
    let (st, msg) = status(r);
    assert_eq!(st, Status::InvalidParameter);
    assert!(msg.contains("written by hall/t1"), "{msg}");
    assert!(cmds.is_empty(), "{cmds:?}");

    let (r, cmds) = h.invoke_cmds("lobby/targets/t1", "edit", map([("point", text(FREE))]));
    r.unwrap();
    assert_eq!(subscribes(&cmds, FREE), 1);
    assert_eq!(unsubscribes(&cmds), 1);
    assert_eq!(h.subscribed(FAN), 0);
    assert_eq!(h.subscribed(FREE), 1);
    assert_eq!(sets_of(&cmds), vec![(FREE.to_owned(), Value::Bool(false))]);
    assert_eq!(h.attr("lobby/targets/t1", "point"), text(FREE));
    assert!(
        outcome(&h, "o/lobby/t1").is_none(),
        "the record was for the old point"
    );
    h.confirm_all();
    assert_eq!(state(&h, "lobby/targets/t1"), text("confirmed"));

    // the edit is saved
    h.restart().unwrap();
    h.settle();
    assert_eq!(h.attr("lobby/targets/t1", "point"), text(FREE));
    assert_eq!(state(&h, "lobby/targets/t1"), text("confirmed"));

    // a free point is not taken by a refused edit of another field
    let (st, _) = status(h.invoke(
        "lobby/targets/t1",
        "edit",
        map([("confirm", text("feedback"))]),
    ));
    assert_eq!(st, Status::InvalidParameter);
    assert_eq!(h.attr("lobby/targets/t1", "confirm"), text("read_back"));
}

#[test]
fn shared_subscription() {
    let mut h = started();
    add_schedule(&mut h, "lobby");
    add_schedule(&mut h, "hall");
    let fb = |point: &str| {
        map([
            ("point", text(point)),
            ("confirm", text("feedback")),
            ("feedback", text(FAN_STATUS)),
        ])
    };
    h.take_log();
    add_target(&mut h, "lobby", fb(FAN)).unwrap();
    add_target(&mut h, "hall", fb(PUMP)).unwrap();
    assert_eq!(subscribes(&h.take_log(), FAN_STATUS), 1);
    assert_eq!(h.subscribed(FAN_STATUS), 1);
    // one sample confirms both
    for (id, ..) in h.unreplied() {
        h.reply(id, Ok(Value::Null));
    }
    h.deliver(FAN_STATUS, Value::Bool(false));
    assert_eq!(state(&h, "lobby/targets/t1"), text("confirmed"));
    assert_eq!(state(&h, "hall/targets/t1"), text("confirmed"));

    h.invoke("lobby/targets/t1", "remove", Value::Null).unwrap();
    assert_eq!(h.subscribed(FAN_STATUS), 1);
    h.invoke("hall/targets/t1", "remove", Value::Null).unwrap();
    assert_eq!(h.subscribed(FAN_STATUS), 0);
}

#[test]
fn a_stale_default_record_is_not_taken_for_now() {
    // confirmed for the default at 07:00; the device is offline from 08:00
    let mut h = lobby();
    add_target(&mut h, "lobby", read_back(FAN)).unwrap();
    h.confirm_all();
    assert_eq!(
        outcome(&h, "o/lobby/t1"),
        Some(record(Value::Bool(false), "default", "confirmed"))
    );
    h.advance_to(at("2026-10-29T08:00:00Z"));
    let fail_all = |h: &mut SimHost| {
        for (id, ..) in h.unreplied() {
            h.reply(id, err(Status::Timeout, "offline"));
        }
    };
    fail_all(&mut h);
    while h.now_us() < at("2026-10-29T17:00:00Z") {
        h.advance(RETRY_CAP_MS);
        fail_all(&mut h);
    }
    // the default again: the 07:00 record is not for this time of it
    assert!(outcome(&h, "o/lobby/t1").is_none());
    fail_all(&mut h);
    h.restart().unwrap();
    h.settle();
    h.take_log();
    assert_eq!(state(&h, "lobby/targets/t1"), text("pending"));
    // the device is back, still on: written, not taken for an override
    h.deliver(FAN, Value::Bool(true));
    assert_eq!(
        sets_of(&h.take_log()),
        vec![(FAN.to_owned(), Value::Bool(false))]
    );
}

#[test]
fn enable_rechecks_the_subscription_bound() {
    // 50 schedules × 20 read_back targets = 1 000 keys, the bound
    let mut h = started();
    for s in 0..50 {
        let sid = format!("s{s}");
        h.invoke(
            "",
            "add_schedule",
            map([("id", text(&sid)), ("default", Value::Bool(false))]),
        )
        .unwrap();
        for t in 0..20 {
            let p = format!("wy/s/downstream/plc/p{s}_{t}");
            add_target(&mut h, &sid, read_back(&p)).unwrap();
        }
    }
    assert_eq!(h.subs.len(), MAX_SUBS);
    // off, its key frees a slot that a new target takes
    h.invoke("s0/targets/t1", "disable", Value::Null).unwrap();
    assert_eq!(h.subs.len(), MAX_SUBS - 1);
    add_schedule(&mut h, "extra");
    add_target(&mut h, "extra", read_back(FREE)).unwrap();
    assert_eq!(h.subs.len(), MAX_SUBS);
    let (r, cmds) = h.invoke_cmds("s0/targets/t1", "enable", Value::Null);
    let (st, msg) = status(r);
    assert_eq!(st, Status::ResourceExhausted);
    assert!(msg.contains("1000 subscriptions"), "{msg}");
    assert!(cmds.is_empty(), "{cmds:?}");
    assert_eq!(state(&h, "s0/targets/t1"), text("disabled"));
    // with room again it turns on
    h.invoke("extra/targets/t1", "remove", Value::Null).unwrap();
    h.invoke("s0/targets/t1", "enable", Value::Null).unwrap();
    // queued: 50 writes are in flight
    assert_eq!(state(&h, "s0/targets/t1"), text("pending"));
    assert_eq!(h.subs.len(), MAX_SUBS);
}

#[test]
fn target_ids_never_repeat() {
    let mut src = lobby();
    add_target(&mut src, "lobby", read_back(FAN)).unwrap();
    let json = export(&mut src, "lobby");

    // a next_target that does not fit, or an id that leaves no id after it
    let mut big = json.clone();
    big["next_target"] = 4_294_967_296u64.into();
    let mut h = started();
    let e = import(&mut h, &big).0.expect_err("refused");
    assert_eq!(e.status, Status::InvalidParameter);
    assert!(e.msg.contains("next_target"), "{e}");
    let mut top = json.clone();
    top["targets"][0]["id"] = "t4294967295".into();
    let e = import(&mut h, &top).0.expect_err("refused");
    assert_eq!(e.status, Status::InvalidParameter);
    assert!(e.msg.contains("targets[0].id"), "{e}");
    assert!(!h.has("lobby"));

    // the last number: no id is left for a new target
    let mut last = json.clone();
    last["next_target"] = u64::from(u32::MAX).into();
    import(&mut h, &last).0.unwrap();
    let (r, cmds) = h.invoke_cmds("lobby", "add_target", read_back(PUMP));
    let (st, msg) = status(r);
    assert_eq!(st, Status::ResourceExhausted);
    assert!(msg.contains("no target ids left"), "{msg}");
    assert!(cmds.is_empty(), "{cmds:?}");
}

#[test]
fn one_write_in_flight_per_target() {
    let mut h = lobby();
    add_target(&mut h, "lobby", read_back(FAN)).unwrap();
    h.confirm_all();
    h.set("lobby/default", Value::Bool(true)).unwrap();
    let (first, _, v) = one_set(&h);
    assert_eq!(v, Value::Bool(true));
    // a newer transition before the reply: the newer write waits for it
    h.set("lobby/default", Value::Bool(false)).unwrap();
    h.settle();
    assert_eq!(h.unreplied().len(), 1, "{:?}", h.unreplied());
    let log = h.reply(first, Ok(Value::Null));
    assert_eq!(sets_of(&log), vec![(FAN.to_owned(), Value::Bool(false))]);
    assert_eq!(state(&h, "lobby/targets/t1"), text("writing"));
    let (req, ..) = one_set(&h);
    h.reply(req, Ok(Value::Null));
    h.deliver(FAN, Value::Bool(false));
    assert_eq!(state(&h, "lobby/targets/t1"), text("confirmed"));
    assert_eq!(
        outcome(&h, "o/lobby/t1"),
        Some(record(Value::Bool(false), "default", "confirmed"))
    );
}

#[test]
fn a_sample_that_moved_away_does_not_confirm() {
    let mut h = lobby();
    add_target(&mut h, "lobby", read_back(FAN)).unwrap();
    h.confirm_all();
    h.advance_to(at("2026-10-29T08:00:00Z"));
    let (req, _, v) = one_set(&h);
    assert_eq!(v, Value::Bool(true));
    // the value shows, then goes, before the reply
    h.deliver(FAN, Value::Bool(true));
    h.deliver(FAN, Value::Bool(false));
    h.reply(req, Ok(Value::Null));
    assert_eq!(state(&h, "lobby/targets/t1"), text("writing"));
    assert!(outcome(&h, "o/lobby/t1").is_none(), "no record");
}

#[test]
fn a_record_does_not_survive_a_later_transition() {
    // 07:00 the default confirmed; from 08:00 the device is offline
    let mut h = lobby();
    add_target(&mut h, "lobby", read_back(FAN)).unwrap();
    h.confirm_all();
    h.advance_to(at("2026-10-29T08:00:00Z"));
    assert!(
        outcome(&h, "o/lobby/t1").is_none(),
        "the 07:00 record is gone"
    );
    let fail_all = |h: &mut SimHost| {
        for (id, ..) in h.unreplied() {
            h.reply(id, err(Status::Timeout, "offline"));
        }
    };
    fail_all(&mut h);
    while h.now_us() < at("2026-10-29T12:00:00Z") {
        h.advance(RETRY_CAP_MS);
        fail_all(&mut h);
    }
    // down from 12:00 to 18:00: the link sees the default again only at start
    h.step_clock(6 * 3_600_000);
    h.restart().unwrap();
    h.settle();
    h.take_log();
    assert_eq!(state(&h, "lobby/targets/t1"), text("pending"));
    // the device is back, still on: written, not taken for an override
    h.deliver(FAN, Value::Bool(true));
    assert_eq!(
        sets_of(&h.take_log()),
        vec![(FAN.to_owned(), Value::Bool(false))]
    );
}

#[test]
fn a_record_from_before_a_disabled_start_does_not_pass() {
    // 07:00 the default confirmed; the schedule is off across a restart
    let mut h = lobby();
    add_target(&mut h, "lobby", read_back(FAN)).unwrap();
    h.confirm_all();
    assert!(outcome(&h, "o/lobby/t1").is_some());
    h.set("lobby/enabled", Value::Bool(false)).unwrap();
    h.restart().unwrap();
    h.settle();
    assert_eq!(state(&h, "lobby/targets/t1"), text("pending"));
    // turned on: a transition writes the default, and that write fails
    h.take_log();
    h.set("lobby/enabled", Value::Bool(true)).unwrap();
    let (req, _, v) = one_set(&h);
    assert_eq!(v, Value::Bool(false));
    assert!(
        outcome(&h, "o/lobby/t1").is_none(),
        "the 07:00 record is gone"
    );
    h.reply(req, err(Status::Timeout, "offline"));
    h.restart().unwrap();
    h.settle();
    assert_eq!(state(&h, "lobby/targets/t1"), text("pending"));
    h.take_log();
    h.advance(FIRST_SAMPLE_MS);
    assert_eq!(
        sets_of(&h.take_log()),
        vec![(FAN.to_owned(), Value::Bool(false))]
    );
}

#[test]
fn a_reply_to_a_removed_target_is_ignored() {
    let mut h = lobby();
    add_target(&mut h, "lobby", read_back(FAN)).unwrap();
    h.confirm_all();
    h.set("lobby/default", Value::Bool(true)).unwrap();
    let (w1, ..) = one_set(&h);
    // the schedule goes and comes back with a target of the same id on the same point
    h.invoke("lobby", "remove", Value::Null).unwrap();
    add_schedule(&mut h, "lobby");
    let r = add_target(&mut h, "lobby", read_back(FAN)).unwrap();
    assert_eq!(r, map([("id", text("t1"))]));
    let due = h.unreplied();
    assert_eq!(due.len(), 2, "{due:?}");
    let w2 = due.iter().find(|(id, ..)| *id != w1).unwrap().0;
    // the old write's reply belongs to the removed target
    h.reply(w1, Ok(Value::Null));
    assert_eq!(state(&h, "lobby/targets/t1"), text("writing"));
    h.set("lobby/default", Value::Bool(true)).unwrap();
    h.settle();
    assert_eq!(
        h.unreplied().iter().map(|(id, ..)| *id).collect::<Vec<_>>(),
        vec![w2],
        "no second write while W2 waits"
    );
    let log = h.reply(w2, Ok(Value::Null));
    assert_eq!(sets_of(&log), vec![(FAN.to_owned(), Value::Bool(true))]);
}
