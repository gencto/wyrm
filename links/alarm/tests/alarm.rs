//! The alarm link on `SimHost` (ADR 0034): watches and their algorithms, inhibits, records
//! and their life, rights, restarts, escalation, sinks, pages and the purge.

mod common;

use std::collections::BTreeMap;

use common::{engineer, map, started, status, t0, text, SimHost};
use wyrm_core::{Perm, Quality, Status, Value};
use wyrm_link_alarm::limits::{JOURNAL_PAGE, MAX_OPEN, PAGE};
use wyrm_link_api::Who;

const PLC: &str = "wy/s/downstream/plc";

fn fault() -> String {
    format!("{PLC}/fault")
}

fn temp() -> String {
    format!("{PLC}/temp")
}

/// A class `c` with a watch; the watch id.
fn class_with_watch(h: &mut SimHost, args: Value) -> String {
    h.invoke("", "add_class", map([("id", text("c"))])).unwrap();
    let r = h.invoke("c", "add_watch", args).unwrap();
    let Value::Map(m) = r else { panic!("{r:?}") };
    let Value::Str(id) = &m["id"] else { panic!() };
    id.clone()
}

fn boolean_args(source: &str) -> Value {
    map([
        ("source", text(source)),
        ("algorithm", text("boolean")),
        ("type", text("fault")),
    ])
}

fn rows_of(v: Result<Value, wyrm_link_api::AppError>) -> Vec<BTreeMap<String, Value>> {
    let Ok(Value::Map(m)) = v else {
        panic!("{v:?}")
    };
    let Value::Array(rows) = &m["rows"] else {
        panic!("{m:?}")
    };
    rows.iter()
        .map(|r| match r {
            Value::Map(m) => m.clone(),
            _ => panic!("{r:?}"),
        })
        .collect()
}

fn alarms(h: &mut SimHost, args: Value) -> Vec<BTreeMap<String, Value>> {
    rows_of(h.invoke("", "get_alarms", args))
}

fn open_alarms(h: &mut SimHost) -> Vec<BTreeMap<String, Value>> {
    alarms(h, Value::Null)
}

fn id_of(row: &BTreeMap<String, Value>) -> u64 {
    match row["id"] {
        Value::UInt(n) => n,
        _ => panic!("{row:?}"),
    }
}

#[test]
fn boolean_watch_raises_acknowledges_and_closes() {
    let mut h = started();
    let w = class_with_watch(&mut h, boolean_args(&fault()));
    assert_eq!(w, "w1");
    assert_eq!(h.subscribed(&fault()), 1);
    assert_eq!(h.value("c/watches/w1"), Some(text("normal")));
    assert_eq!(h.deliver(&fault(), Value::Bool(false)), 1);
    assert!(open_alarms(&mut h).is_empty());
    h.deliver(&fault(), Value::Bool(true));
    assert_eq!(h.value("c/watches/w1"), Some(text("alarm")));
    let rows = open_alarms(&mut h);
    assert_eq!(rows.len(), 1);
    assert_eq!(rows[0]["state"], text("active"));
    assert_eq!(rows[0]["type"], text("fault"));
    assert_eq!(rows[0]["message"], text("fault: true"));
    assert_eq!(rows[0]["source"], text(fault()));
    assert_eq!(rows[0]["watch"], text("w1"));
    let id = id_of(&rows[0]);
    // the counts and the table are published, coalesced
    h.advance(600);
    assert_eq!(h.value("c/open"), Some(Value::UInt(1)));
    assert_eq!(h.value("c/active"), Some(Value::UInt(1)));
    assert_eq!(h.value("stats/open"), Some(Value::UInt(1)));
    assert_eq!(h.value("stats/raised"), Some(Value::UInt(1)));
    let Some(Value::Array(table)) = h.value("c/alarms") else {
        panic!()
    };
    assert_eq!(table.len(), 1);
    // a second true sample makes no second record
    h.deliver(&fault(), Value::Bool(true));
    assert_eq!(open_alarms(&mut h).len(), 1);
    // back to normal: open (unacknowledged), not active
    h.deliver(&fault(), Value::Bool(false));
    assert_eq!(h.value("c/watches/w1"), Some(text("normal")));
    let rows = open_alarms(&mut h);
    assert_eq!(rows[0]["state"], text("normal"));
    assert!(alarms(&mut h, map([("state", text("active"))])).is_empty());
    // acknowledged: closed, gone from the open set, found on its page
    h.invoke(
        "",
        "acknowledge",
        map([("id", Value::UInt(id)), ("note", text("seen"))]),
    )
    .unwrap();
    assert!(open_alarms(&mut h).is_empty());
    let closed = alarms(&mut h, map([("state", text("closed"))]));
    assert_eq!(closed.len(), 1);
    assert_eq!(closed[0]["ack_by"], text("user:test"));
    assert_eq!(closed[0]["notes"], Value::UInt(1));
    let r = h
        .invoke("", "get_alarm", map([("id", Value::UInt(id))]))
        .unwrap();
    let Value::Map(r) = r else { panic!() };
    assert_eq!(r["state"], text("closed"));
    let (st, _) = status(h.invoke("", "acknowledge", map([("id", Value::UInt(id))])));
    assert_eq!(st, Status::NotFound);
    // a new alarm is a new record
    h.deliver(&fault(), Value::Bool(true));
    let rows = open_alarms(&mut h);
    assert_eq!(rows.len(), 1);
    assert_eq!(id_of(&rows[0]), id + 1);
    h.advance(600);
    assert_eq!(h.value("stats/records"), Some(Value::UInt(2)));
    assert!(h.max_cmds <= 800, "{}", h.max_cmds);
}

#[test]
fn out_of_range_with_inhibits_and_deadband() {
    let mut h = started();
    class_with_watch(
        &mut h,
        map([
            ("source", text(temp())),
            ("algorithm", text("out_of_range")),
            ("max", Value::UInt(25)),
            ("deadband", Value::UInt(2)),
            ("to_alarm_s", Value::UInt(5)),
            ("to_normal_s", Value::UInt(5)),
            ("message", text("{name} at {value}")),
        ]),
    );
    h.deliver(&temp(), Value::Float(30.0));
    assert_eq!(h.value("c/watches/w1"), Some(text("to_alarm")));
    assert!(open_alarms(&mut h).is_empty());
    // back inside before the inhibit ends: nothing
    h.advance(3_000);
    h.deliver(&temp(), Value::Float(20.0));
    assert_eq!(h.value("c/watches/w1"), Some(text("normal")));
    h.advance(5_000);
    assert!(open_alarms(&mut h).is_empty());
    // out for 5 s: a record
    h.deliver(&temp(), Value::Float(30.0));
    h.advance(4_900);
    assert!(open_alarms(&mut h).is_empty());
    h.advance(200);
    let rows = open_alarms(&mut h);
    assert_eq!(rows.len(), 1);
    assert_eq!(rows[0]["message"], text("temp at 30"));
    assert_eq!(h.value("c/watches/w1"), Some(text("alarm")));
    // 24 is inside the limit but within the deadband: still in alarm
    h.deliver(&temp(), Value::Float(24.0));
    assert_eq!(h.value("c/watches/w1"), Some(text("alarm")));
    // 22 is normal, after 5 s
    h.deliver(&temp(), Value::Float(22.0));
    assert_eq!(h.value("c/watches/w1"), Some(text("to_normal")));
    h.advance(2_000);
    h.deliver(&temp(), Value::Float(30.0));
    assert_eq!(h.value("c/watches/w1"), Some(text("alarm")));
    h.advance(10_000);
    assert_eq!(open_alarms(&mut h)[0]["state"], text("active"));
    h.deliver(&temp(), Value::Float(22.0));
    h.advance(5_100);
    assert_eq!(open_alarms(&mut h)[0]["state"], text("normal"));
    assert_eq!(h.value("c/watches/w1"), Some(text("normal")));
}

#[test]
fn staleness_and_quality() {
    let mut h = started();
    h.invoke("", "add_class", map([("id", text("c"))])).unwrap();
    h.invoke(
        "c",
        "add_watch",
        map([
            ("source", text(temp())),
            ("algorithm", text("staleness")),
            ("stale_s", Value::UInt(10)),
        ]),
    )
    .unwrap();
    h.invoke(
        "c",
        "add_watch",
        map([
            ("source", text(fault())),
            ("algorithm", text("quality")),
            ("type", text("warning")),
        ]),
    )
    .unwrap();
    h.deliver(&temp(), Value::UInt(1));
    h.advance(9_000);
    assert!(open_alarms(&mut h).is_empty());
    h.deliver(&temp(), Value::UInt(1));
    h.advance(9_000);
    assert!(
        open_alarms(&mut h).is_empty(),
        "a sample restarts the deadline"
    );
    h.advance(1_100);
    let rows = open_alarms(&mut h);
    assert_eq!(rows.len(), 1);
    assert_eq!(rows[0]["message"], text("temp: no sample for 10 s"));
    assert_eq!(h.value("c/watches/w1"), Some(text("alarm")));
    h.deliver(&temp(), Value::UInt(2));
    assert_eq!(open_alarms(&mut h)[0]["state"], text("normal"));
    assert_eq!(h.value("c/watches/w1"), Some(text("normal")));
    // quality
    h.deliver_q(&fault(), Value::Null, Quality::Uncertain);
    assert_eq!(h.value("c/watches/w2"), Some(text("normal")));
    h.deliver_q(&fault(), Value::Null, Quality::Bad);
    assert_eq!(h.value("c/watches/w2"), Some(text("alarm")));
    let rows = alarms(&mut h, map([("state", text("active"))]));
    assert_eq!(rows.len(), 1);
    assert_eq!(rows[0]["message"], text("fault: quality bad"));
    assert_eq!(rows[0]["type"], text("warning"));
    h.deliver_q(&fault(), Value::Null, Quality::Good);
    assert!(alarms(&mut h, map([("state", text("active"))])).is_empty());
}

#[test]
fn subtree_watch_keeps_a_state_per_key_within_the_author_rights() {
    let mut h = started();
    h.invoke("", "add_class", map([("id", text("c"))])).unwrap();
    // the author reads `plc/ok/**` only
    let author = Who {
        subject: Some("user:narrow".into()),
        grants: vec![("wy/s/downstream/alarm/**".into(), Perm::Config)],
        authority: Some(vec![("wy/s/downstream/plc/ok/**".into(), Perm::Read)]),
    };
    let (r, _) = h.invoke_as(
        &author,
        "c",
        "add_watch",
        boolean_args(&format!("{PLC}/**")),
    );
    r.unwrap();
    assert_eq!(h.subscribed(&format!("{PLC}/**")), 1);
    h.deliver(&format!("{PLC}/ok/a"), Value::Bool(true));
    h.deliver(&format!("{PLC}/ok/b"), Value::Bool(true));
    h.deliver(&format!("{PLC}/secret/x"), Value::Bool(true));
    let rows = open_alarms(&mut h);
    assert_eq!(rows.len(), 2, "{rows:?}");
    assert_eq!(h.attr("c/watches/w1", "keys"), Value::UInt(2));
    assert_eq!(h.attr("c/watches/w1", "in_alarm"), Value::UInt(2));
    h.deliver(&format!("{PLC}/ok/a"), Value::Bool(false));
    assert_eq!(h.attr("c/watches/w1", "in_alarm"), Value::UInt(1));
    assert_eq!(h.value("c/watches/w1"), Some(text("alarm")));
    // a watch outside the author's rights is refused
    let (r, _) = h.invoke_as(&author, "c", "add_watch", boolean_args(&fault()));
    assert_eq!(status(r).0, Status::PermissionDenied);
    // and a caller without `auth` cannot define one at all
    let flow = Who {
        subject: Some("flow".into()),
        grants: vec![("wy/s/downstream/alarm/**".into(), Perm::Config)],
        authority: None,
    };
    let (r, _) = h.invoke_as(&flow, "c", "add_watch", boolean_args(&fault()));
    assert_eq!(status(r).0, Status::PermissionDenied);
    // a reader sees the records of the sources they may read
    let reader = Who {
        subject: Some("user:reader".into()),
        grants: vec![("wy/s/downstream/alarm/**".into(), Perm::Read)],
        authority: Some(vec![("wy/s/downstream/plc/ok/b".into(), Perm::Read)]),
    };
    let (r, _) = h.invoke_as(&reader, "", "get_alarms", Value::Null);
    assert_eq!(rows_of(r).len(), 1);
    let (r, _) = h.invoke_as(&flow, "", "get_alarms", Value::Null);
    assert_eq!(status(r).0, Status::PermissionDenied);
    let a = id_of(&open_alarms(&mut h)[1]);
    let (r, _) = h.invoke_as(&reader, "", "acknowledge", map([("id", Value::UInt(a))]));
    assert_eq!(status(r).0, Status::PermissionDenied);
}

#[test]
fn raise_notes_normal_and_ack_all() {
    let mut h = started();
    h.invoke("", "add_class", map([("id", text("c"))])).unwrap();
    // a dataflow raises without `auth`
    let flow = Who {
        subject: Some("flow:f1".into()),
        grants: vec![("wy/s/downstream/alarm/~act/raise".into(), Perm::Write)],
        authority: None,
    };
    let (r, _) = h.invoke_as(
        &flow,
        "",
        "raise",
        map([
            ("class", text("c")),
            ("source", text(temp())),
            ("type", Value::UInt(2)),
            ("message", text("manual")),
        ]),
    );
    let Ok(Value::Map(m)) = r else {
        panic!("{r:?}")
    };
    let Value::UInt(id) = m["id"] else { panic!() };
    let rows = open_alarms(&mut h);
    assert_eq!(rows[0]["by"], text("flow:f1"));
    assert_eq!(rows[0]["type"], text("fault"));
    assert_eq!(rows[0]["watch"], Value::Null);
    h.invoke(
        "",
        "add_note",
        map([("id", Value::UInt(id)), ("note", text("first"))]),
    )
    .unwrap();
    h.invoke(
        "",
        "add_note",
        map([("id", Value::UInt(id)), ("note", text("second"))]),
    )
    .unwrap();
    let notes = h
        .invoke("", "get_notes", map([("id", Value::UInt(id))]))
        .unwrap();
    let Value::Array(notes) = notes else { panic!() };
    assert_eq!(notes.len(), 2);
    let (st, msg) = status(h.invoke("", "add_note", map([("id", Value::UInt(id))])));
    assert_eq!(
        (st, msg.as_str()),
        (Status::InvalidParameter, "note: required")
    );
    // a second manual record, then Acknowledge All
    h.invoke(
        "",
        "raise",
        map([("class", text("c")), ("source", text(fault()))]),
    )
    .unwrap();
    let r = h.invoke("c", "ack_all", Value::Null).unwrap();
    assert_eq!(r, map([("acknowledged", Value::UInt(2))]));
    assert!(alarms(&mut h, map([("state", text("unacked"))])).is_empty());
    assert_eq!(open_alarms(&mut h).len(), 2, "still active");
    h.invoke("", "normal", map([("id", Value::UInt(id))]))
        .unwrap();
    assert_eq!(open_alarms(&mut h).len(), 1);
    let (st, _) = status(h.invoke("", "normal", map([("id", Value::UInt(id))])));
    assert_eq!(st, Status::NotFound);
    // a closed record keeps taking notes
    h.invoke(
        "",
        "add_note",
        map([("id", Value::UInt(id)), ("note", text("later"))]),
    )
    .unwrap();
    let Value::Array(notes) = h
        .invoke("", "get_notes", map([("id", Value::UInt(id))]))
        .unwrap()
    else {
        panic!()
    };
    assert_eq!(notes.len(), 3);
    // the class cannot go while a record is open
    let (st, msg) = status(h.invoke("c", "remove", Value::Null));
    assert!(
        st == Status::InvalidParameter && msg.contains("open records"),
        "{msg}"
    );
}

#[test]
fn restart_keeps_open_records_and_the_first_sample_decides() {
    let mut h = started();
    class_with_watch(&mut h, boolean_args(&fault()));
    h.deliver(&fault(), Value::Bool(true));
    let id = id_of(&open_alarms(&mut h)[0]);
    h.invoke(
        "",
        "raise",
        map([("class", text("c")), ("source", text(temp()))]),
    )
    .unwrap();
    h.restart().unwrap();
    h.settle();
    assert_eq!(h.subscribed(&fault()), 1);
    let rows = open_alarms(&mut h);
    assert_eq!(rows.len(), 2);
    assert_eq!(h.value("c/watches/w1"), Some(text("alarm")));
    assert_eq!(h.attr("c/watches/w1", "last_record"), Value::UInt(id));
    // the same alarm again makes no second record; the first normal sample closes it
    h.deliver(&fault(), Value::Bool(true));
    assert_eq!(alarms(&mut h, map([("state", text("active"))])).len(), 2);
    h.deliver(&fault(), Value::Bool(false));
    let rows = alarms(&mut h, map([("state", text("active"))]));
    assert_eq!(rows.len(), 1);
    assert_eq!(rows[0]["source"], text(temp()));
    // a third record after the restart gets the next id
    h.deliver(&fault(), Value::Bool(true));
    let rows = alarms(&mut h, map([("state", text("active"))]));
    assert_eq!(rows.iter().map(id_of).max(), Some(id + 2));
    h.advance(600);
    assert_eq!(h.value("stats/open"), Some(Value::UInt(3)));
    assert_eq!(h.value("stats/records"), Some(Value::UInt(3)));
}

#[test]
fn escalation_levels_until_acknowledged() {
    let mut h = started();
    h.invoke(
        "",
        "add_class",
        map([
            ("id", text("c")),
            ("escalation1_s", Value::UInt(60)),
            ("escalation2_s", Value::UInt(120)),
        ]),
    )
    .unwrap();
    let (st, _) = status(h.invoke(
        "",
        "add_class",
        map([
            ("id", text("bad")),
            ("escalation1_s", Value::UInt(60)),
            ("escalation2_s", Value::UInt(30)),
        ]),
    ));
    assert_eq!(st, Status::InvalidParameter);
    h.invoke(
        "",
        "raise",
        map([("class", text("c")), ("source", text(temp()))]),
    )
    .unwrap();
    let id = id_of(&open_alarms(&mut h)[0]);
    let journal = h.app().journal_next();
    h.advance(59_000);
    assert_eq!(open_alarms(&mut h)[0]["escalation"], Value::UInt(0));
    h.advance(2_000);
    assert_eq!(open_alarms(&mut h)[0]["escalation"], Value::UInt(1));
    assert_eq!(
        h.app().journal_next(),
        journal + 1,
        "sinks see the escalation"
    );
    // a restart keeps the next escalation due at the record's time
    h.restart().unwrap();
    h.settle();
    h.advance(58_000);
    assert_eq!(open_alarms(&mut h)[0]["escalation"], Value::UInt(1));
    h.advance(2_000);
    assert_eq!(open_alarms(&mut h)[0]["escalation"], Value::UInt(2));
    // another record, acknowledged before its first escalation: none
    h.invoke(
        "",
        "raise",
        map([("class", text("c")), ("source", text(fault()))]),
    )
    .unwrap();
    let second = id + 1;
    h.advance(30_000);
    h.invoke("", "acknowledge", map([("id", Value::UInt(second))]))
        .unwrap();
    h.advance(120_000);
    let rows = open_alarms(&mut h);
    let r2 = rows.iter().find(|r| id_of(r) == second).unwrap();
    assert_eq!(r2["escalation"], Value::UInt(0));
}

#[test]
fn sinks_hand_out_records_to_their_link_only() {
    let mut h = started();
    class_with_watch(&mut h, boolean_args(&fault()));
    h.deliver(&fault(), Value::Bool(true));
    h.invoke(
        "",
        "add_sink",
        map([("name", text("cloud")), ("link", text("pg"))]),
    )
    .unwrap();
    assert!(h.has("sinks/cloud"));
    assert_eq!(h.attr("sinks/cloud", "link"), text("pg"));
    // a person cannot run `next`
    let (r, _) = h.invoke_as(&engineer("user:test"), "sinks/cloud", "next", Value::Null);
    assert_eq!(status(r).0, Status::PermissionDenied);
    let pg = Who {
        subject: Some("link:pg".into()),
        grants: vec![("wy/s/downstream/alarm/sinks/cloud".into(), Perm::Read)],
        authority: None,
    };
    let (r, _) = h.invoke_as(&pg, "sinks/cloud", "next", Value::Null);
    let Ok(Value::Map(b)) = r else {
        panic!("{r:?}")
    };
    let Value::Array(rows) = &b["rows"] else {
        panic!()
    };
    assert_eq!(rows.len(), 1);
    let Value::Map(row) = &rows[0] else { panic!() };
    assert_eq!(row["key"], text(fault()));
    assert_eq!(row["t"], Value::UInt(t0()));
    assert_eq!(row["q"], Value::UInt(0));
    let Value::Str(json) = &row["v"] else {
        panic!()
    };
    let j: serde_json::Value = serde_json::from_str(json).unwrap();
    assert_eq!(j["format"], "wyrm-alarm/1");
    assert_eq!(j["state"], "active");
    assert_eq!(j["class"], "c");
    let next = b["next"].clone();
    assert_eq!(next, Value::UInt(1));
    // the same batch again until confirmed; `after` confirms it
    let (r, _) = h.invoke_as(&pg, "sinks/cloud", "next", Value::Null);
    assert_eq!(rows_of(r).len(), 1);
    let (r, _) = h.invoke_as(&pg, "sinks/cloud", "next", map([("after", next.clone())]));
    assert!(rows_of(r).is_empty());
    assert_eq!(h.value("sinks/cloud"), Some(Value::UInt(1)));
    // a change is a new row with the record's new state
    h.deliver(&fault(), Value::Bool(false));
    let (r, _) = h.invoke_as(&pg, "sinks/cloud", "next", Value::Null);
    let rows = rows_of(r);
    assert_eq!(rows.len(), 1);
    assert_eq!(rows[0]["seq"], Value::UInt(2));
    let Value::Str(json) = &rows[0]["v"] else {
        panic!()
    };
    assert!(json.contains("\"state\":\"normal\""), "{json}");
    // a sink of another class sees nothing of `c`
    h.invoke(
        "",
        "add_sink",
        map([
            ("name", text("other")),
            ("link", text("pg")),
            ("classes", text("d")),
        ]),
    )
    .unwrap();
    let (r, _) = h.invoke_as(&pg, "sinks/other", "next", Value::Null);
    let Ok(Value::Map(b)) = r else { panic!() };
    assert_eq!(b["rows"], Value::Array(Vec::new()));
    assert_eq!(
        b["next"],
        Value::UInt(2),
        "entries it does not take are passed"
    );
    // `from: now` starts after what exists; reset to start goes back
    h.invoke("sinks/other", "reset", map([("from", text("now"))]))
        .unwrap();
    assert_eq!(h.value("sinks/other"), Some(Value::UInt(2)));
    h.invoke("sinks/other", "reset", map([("from", text("start"))]))
        .unwrap();
    assert_eq!(h.value("sinks/other"), Some(Value::UInt(0)));
    // the sinks survive a restart with their cursors
    h.restart().unwrap();
    h.settle();
    assert_eq!(h.value("sinks/cloud"), Some(Value::UInt(1)));
    h.invoke("sinks/other", "remove", Value::Null).unwrap();
    assert!(!h.has("sinks/other"));
    let (st, _) = status(h.invoke("sinks/other", "remove", Value::Null));
    assert_eq!(st, Status::NotFound);
}

#[test]
fn pages_journal_time_ranges_and_purge() {
    let mut h = started();
    class_with_watch(&mut h, boolean_args(&format!("{PLC}/**")));
    let n = 3 * PAGE + 5;
    for i in 0..n {
        h.deliver(&format!("{PLC}/p{i}"), Value::Bool(true));
        h.advance(60_000);
    }
    assert_eq!(h.app().open_records().count(), n as usize);
    // every change is a journal entry; the journal has pages too
    assert_eq!(h.app().journal_next(), n + 1);
    assert!(h.store_get("p/3").is_some());
    assert!(h.store_get("j/0").is_some());
    // a time range over the pages, newest first
    let from = t0() + 10 * 60_000_000;
    let to = t0() + 20 * 60_000_000;
    let r = h
        .invoke(
            "",
            "get_alarms",
            map([
                ("state", text("all")),
                (
                    "timerange",
                    text(format!(
                        "{}/{}",
                        jiff::Timestamp::from_microsecond(from as i64).unwrap(),
                        jiff::Timestamp::from_microsecond(to as i64).unwrap()
                    )),
                ),
            ]),
        )
        .unwrap();
    let Value::Map(m) = r else { panic!() };
    assert_eq!(m["complete"], Value::Bool(true));
    let Value::Array(rows) = &m["rows"] else {
        panic!()
    };
    assert_eq!(rows.len(), 10);
    let Value::Map(first) = &rows[0] else {
        panic!()
    };
    assert_eq!(first["id"], Value::UInt(19));
    // `limit` cuts, `complete` says so
    let rows = rows_of(h.invoke(
        "",
        "get_alarms",
        map([("state", text("all")), ("limit", Value::UInt(7))]),
    ));
    assert_eq!(rows.len(), 7);
    assert_eq!(id_of(&rows[0]), n - 1);
    // everything back to normal and acknowledged: closed
    for i in 0..n {
        h.deliver(&format!("{PLC}/p{i}"), Value::Bool(false));
    }
    h.invoke("", "ack_all", Value::Null).unwrap();
    assert!(open_alarms(&mut h).is_empty());
    assert_eq!(h.app().journal_next(), 3 * n + 1);
    assert!(h.store_get("j/1").is_some());
    // the purge takes whole pages of closed records created before the instant
    let cut = jiff::Timestamp::from_microsecond((t0() + 130 * 60_000_000) as i64).unwrap();
    let r = h
        .invoke("", "purge", map([("before", text(cut.to_string()))]))
        .unwrap();
    assert_eq!(r, map([("pages", Value::UInt(2))]));
    assert!(h.store_get("p/0").is_none());
    assert!(h.store_get("p/1").is_none());
    assert!(h.store_get("p/2").is_some());
    let rows = rows_of(h.invoke(
        "",
        "get_alarms",
        map([("state", text("closed")), ("limit", Value::UInt(5000))]),
    ));
    assert_eq!(rows.len() as u64, n - 2 * PAGE);
    h.advance(600);
    assert_eq!(h.value("stats/records"), Some(Value::UInt(n - 2 * PAGE)));
    // the next record goes on after the purge
    h.deliver(&format!("{PLC}/p0"), Value::Bool(true));
    assert_eq!(id_of(&open_alarms(&mut h)[0]), n);
    h.restart().unwrap();
    h.settle();
    assert_eq!(h.app().journal_next(), 3 * n + 2);
    h.deliver(&format!("{PLC}/p1"), Value::Bool(true));
    assert_eq!(open_alarms(&mut h).len(), 2);
    assert_eq!(id_of(&open_alarms(&mut h)[0]), n + 1);
    // the journal is bounded: old pages go
    let before = h.app().journal_next();
    let a_lot = JOURNAL_PAGE * 2;
    for _ in 0..a_lot {
        h.deliver(&format!("{PLC}/p0"), Value::Bool(false));
        h.deliver(&format!("{PLC}/p0"), Value::Bool(true));
    }
    assert_eq!(h.app().journal_next(), before + 2 * a_lot);
    assert!(h.max_cmds <= 800, "{}", h.max_cmds);
}

#[test]
fn watches_edit_disable_remove_and_the_class_goes_last() {
    let mut h = started();
    class_with_watch(&mut h, boolean_args(&fault()));
    h.deliver(&fault(), Value::Bool(true));
    // disabling a watch returns its records to normal: nobody watches them
    h.invoke("c/watches/w1", "disable", Value::Null).unwrap();
    assert_eq!(h.subscribed(&fault()), 0);
    assert_eq!(h.value("c/watches/w1"), Some(text("disabled")));
    assert_eq!(open_alarms(&mut h)[0]["state"], text("normal"));
    h.invoke("c/watches/w1", "enable", Value::Null).unwrap();
    assert_eq!(h.subscribed(&fault()), 1);
    // an edit of the algorithm keeps the subscription; of the source makes a new one
    h.invoke(
        "c/watches/w1",
        "edit",
        map([
            ("algorithm", text("boolean")),
            ("alarm_value", Value::Bool(false)),
        ]),
    )
    .unwrap();
    assert_eq!(h.subscribed(&fault()), 1);
    h.deliver(&fault(), Value::Bool(false));
    assert_eq!(h.value("c/watches/w1"), Some(text("alarm")));
    h.invoke("c/watches/w1", "edit", map([("source", text(temp()))]))
        .unwrap();
    assert_eq!(h.subscribed(&fault()), 0);
    assert_eq!(h.subscribed(&temp()), 1);
    assert_eq!(h.attr("c/watches/w1", "source"), text(temp()));
    let (st, msg) = status(h.invoke("c", "remove", Value::Null));
    assert!(
        st == Status::InvalidParameter && msg.contains("watches first"),
        "{msg}"
    );
    h.invoke("c/watches/w1", "remove", Value::Null).unwrap();
    assert!(!h.has("c/watches/w1"));
    assert_eq!(h.sub_keys().len(), 0);
    let ids: Vec<u64> = open_alarms(&mut h).iter().map(id_of).collect();
    for id in ids {
        h.invoke("", "acknowledge", map([("id", Value::UInt(id))]))
            .unwrap();
    }
    h.invoke("c", "remove", Value::Null).unwrap();
    assert!(!h.has("c"));
    assert_eq!(h.store_get("c/c"), None);
}

#[test]
fn export_imports_with_the_importer_rights() {
    let mut h = started();
    class_with_watch(&mut h, boolean_args(&fault()));
    let r = h.invoke("c", "export", Value::Null).unwrap();
    let Value::Map(m) = r else { panic!() };
    let Value::Str(json) = &m["json"] else {
        panic!()
    };
    assert!(!json.contains("rights"));
    let (st, _) = status(h.invoke("", "import", map([("json", text(json))])));
    assert_eq!(st, Status::InvalidParameter, "exists without overwrite");
    let copy = json.replace("\"id\":\"c\"", "\"id\":\"d\"");
    let r = h
        .invoke("", "import", map([("json", text(&copy))]))
        .unwrap();
    assert_eq!(r, map([("id", text("d"))]));
    assert!(h.has("d/watches/w1"));
    assert_eq!(h.subscribed(&fault()), 2);
    // a caller without `auth` cannot import watches
    let flow = Who {
        subject: Some("flow".into()),
        grants: vec![("wy/s/downstream/alarm/**".into(), Perm::Config)],
        authority: None,
    };
    let (r, _) = h.invoke_as(
        &flow,
        "",
        "import",
        map([("json", text(&copy)), ("overwrite", Value::Bool(true))]),
    );
    assert_eq!(status(r).0, Status::PermissionDenied);
    // overwrite replaces the watches
    h.invoke(
        "",
        "import",
        map([("json", text(&copy)), ("overwrite", Value::Bool(true))]),
    )
    .unwrap();
    assert_eq!(h.subscribed(&fault()), 2);
    h.restart().unwrap();
    h.settle();
    assert_eq!(h.subscribed(&fault()), 2);
    assert_eq!(h.attr("d/watches/w1", "created_by"), text("user:test"));
}

#[test]
fn a_backward_clock_step_moves_the_waits() {
    let mut h = started();
    class_with_watch(
        &mut h,
        map([
            ("source", text(fault())),
            ("algorithm", text("boolean")),
            ("to_alarm_s", Value::UInt(10)),
        ]),
    );
    h.deliver(&fault(), Value::Bool(true));
    h.advance(5_000);
    h.step_clock(-3_600_000);
    // the timer measures the step exactly when it fires: the wait ends on time
    h.advance(4_500);
    assert!(h.app().open_records().count() == 0);
    h.advance(1_000);
    assert_eq!(open_alarms(&mut h).len(), 1, "10 s of wall time passed");
    // a step seen by another event first is measured against that event's clock: the wait
    // may be late by the time since it, never more than the watchdog
    h.deliver(&fault(), Value::Bool(false));
    h.deliver(&fault(), Value::Bool(true));
    h.advance(5_000);
    h.step_clock(-3_600_000);
    h.advance(2_000);
    assert_eq!(open_alarms(&mut h).len(), 1, "an event sees the step first");
    h.advance(3_000 + 30_000);
    assert_eq!(alarms(&mut h, map([("state", text("active"))])).len(), 1);
}

#[test]
fn open_records_are_bounded() {
    let mut h = started();
    class_with_watch(&mut h, boolean_args(&format!("{PLC}/**")));
    // the keys bound of a subtree watch
    for i in 0..MAX_OPEN {
        h.deliver(&format!("{PLC}/k{i}"), Value::Bool(true));
    }
    assert_eq!(h.attr("c/watches/w1", "error"), text("more than 2000 keys"));
    assert_eq!(h.app().open_records().count(), 2_000, "keys per watch");
    assert_eq!(h.value("c/watches/w1"), Some(text("error")));
    assert!(h.invoke("", "add_class", map([("id", text("m"))])).is_ok());
    // manual records up to the open bound, then the oldest normal one is acknowledged by overflow
    let mut by_raise = 0;
    for i in 0..(MAX_OPEN - 2_000 + 1) {
        let r = h.invoke(
            "",
            "raise",
            map([
                ("class", text("m")),
                ("source", text(format!("{PLC}/r{i}"))),
            ]),
        );
        r.unwrap();
        by_raise += 1;
    }
    assert_eq!(by_raise, MAX_OPEN - 2_000 + 1);
    assert_eq!(
        h.app().open_records().count(),
        MAX_OPEN + 1,
        "all active: made anyway"
    );
    h.deliver(&format!("{PLC}/k0"), Value::Bool(false));
    let r = h.invoke(
        "",
        "raise",
        map([
            ("class", text("m")),
            ("source", text(format!("{PLC}/last"))),
        ]),
    );
    r.unwrap();
    assert_eq!(h.app().open_records().count(), MAX_OPEN + 1);
    assert!(
        !h.app()
            .open_records()
            .any(|r| r.source == format!("{PLC}/k0")),
        "the normal one was acknowledged by overflow"
    );
    let closed = alarms(&mut h, map([("state", text("closed"))]));
    assert_eq!(closed.len(), 1);
    assert_eq!(closed[0]["ack_by"], text("system:overflow"));
    // the rows of an answer are bounded
    assert_eq!(open_alarms(&mut h).len(), 500);
    assert!(h.max_cmds <= 800, "{}", h.max_cmds);
}
