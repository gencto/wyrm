use jiff::civil::datetime;
use wyrm_core::Value;
use wyrm_schedule::*;

fn rule(t: &str) -> Result<Rule, Invalid> {
    t.parse()
}

#[test]
fn rrule_round_trips() {
    for t in [
        "FREQ=DAILY;INTERVAL=1",
        "FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE,FR",
        "FREQ=MONTHLY;INTERVAL=1;BYDAY=-1FR",
        "FREQ=MONTHLY;INTERVAL=1;BYMONTHDAY=-1,15",
        "FREQ=YEARLY;INTERVAL=1;BYMONTH=3;BYDAY=-1SU",
        "FREQ=YEARLY;INTERVAL=1;BYMONTH=5;BYDAY=-5MO,5SU",
        "FREQ=HOURLY;INTERVAL=4;COUNT=6",
        "FREQ=DAILY;INTERVAL=1;UNTIL=2027-03-01T00:00",
    ] {
        assert_eq!(rule(t).unwrap().to_string(), t);
    }
    assert_eq!(
        rule("byday=fr,mo;interval=2;freq=weekly")
            .unwrap()
            .to_string(),
        "FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,FR"
    );
}

#[test]
fn rrule_refusals() {
    for (t, part) in [
        ("FREQ=DAILY;COUNT=2;UNTIL=2027-03-01T00:00", "COUNT"),
        ("FREQ=DAILY;INTERVAL=0", "INTERVAL"),
        ("FREQ=DAILY;INTERVAL=1001", "INTERVAL"),
        ("FREQ=DAILY;COUNT=10001", "COUNT"),
        ("FREQ=WEEKLY;BYDAY=1MO", "BYDAY"),
        ("FREQ=MONTHLY;BYDAY=-128MO", "BYDAY"),
        ("FREQ=YEARLY;BYDAY=-128MO", "BYDAY"),
        // ordinals count within a month (ruling R5): 6MO never matches
        ("FREQ=YEARLY;BYDAY=6MO", "BYDAY"),
        ("FREQ=YEARLY;BYDAY=-6FR", "BYDAY"),
        ("FREQ=YEARLY;BYMONTH=3;BYDAY=20MO", "BYDAY"),
        ("FREQ=MONTHLY;BYMONTHDAY=0", "BYMONTHDAY"),
        ("FREQ=MONTHLY;BYMONTHDAY=32", "BYMONTHDAY"),
        ("FREQ=MONTHLY;BYMONTHDAY=-2", "BYMONTHDAY"),
        ("FREQ=YEARLY;BYMONTH=13", "BYMONTH"),
        ("FREQ=SECONDLY", "FREQ"),
        ("FREQ=WEEKLY;WKST=SU", "WKST"),
        ("FREQ=DAILY;UNTIL=2027-03-01T00:00Z", "UNTIL"),
    ] {
        let e = rule(t).unwrap_err();
        assert_eq!(e.field, part, "{t}: {e}");
    }
}

fn event(id: &str, start: &str, end: &str, rec: Option<&str>) -> Event {
    Event {
        id: id.into(),
        display: String::new(),
        value: Value::Bool(true),
        priority: 1,
        special: false,
        start: parse_local("start", start).unwrap(),
        end: parse_local("end", end).unwrap(),
        recurrence: rec.map(|r| r.parse().unwrap()),
    }
}

fn sched(events: Vec<Event>) -> Schedule {
    Schedule {
        id: "lobby".into(),
        display: "Lobby".into(),
        tz: "Europe/Kyiv".into(),
        default: Value::Bool(false),
        enabled: true,
        next_event: u32::try_from(events.len() + 1).unwrap(),
        events,
    }
}

fn field(s: &Schedule) -> String {
    validate(s).unwrap_err().field
}

#[test]
fn validate_refusals() {
    let ok = || event("e1", "2026-10-05T08:00", "2026-10-05T09:00", None);
    for id in ["", "a/b", &"x".repeat(65)] {
        let mut s = sched(vec![]);
        s.id = id.into();
        assert_eq!(field(&s), "id", "{id:?}");
    }
    let mut s = sched(vec![]);
    s.tz = "Mars/Base".into();
    assert_eq!(field(&s), "tz");
    let mut e = ok();
    e.priority = 10;
    assert_eq!(field(&sched(vec![e])), "events[0].priority");
    let e = event("e1", "2026-10-05T09:00", "2026-10-05T08:00", None);
    assert_eq!(field(&sched(vec![e])), "events[0].end");
    let e = event(
        "e1",
        "2026-10-05T08:00",
        "2026-10-06T09:00",
        Some("FREQ=DAILY"),
    );
    let err = validate(&sched(vec![e])).unwrap_err();
    assert_eq!(err.field, "events[0].end");
    assert!(err.rule.contains("longer than its period"));
    let e = event(
        "e1",
        "2026-10-05T08:00",
        "2026-10-06T14:00",
        Some("FREQ=WEEKLY;BYDAY=MO,TU"),
    );
    assert_eq!(field(&sched(vec![e])), "events[0].end");
    let mut s = sched(vec![]);
    s.events = (1..=101)
        .map(|n| {
            event(
                &format!("e{n}"),
                "2026-10-05T08:00",
                "2026-10-05T09:00",
                None,
            )
        })
        .collect();
    s.next_event = 102;
    assert_eq!(field(&s), "events");
    assert_eq!(field(&sched(vec![ok(), ok()])), "events[1].id");
    let mut s = sched(vec![event(
        "e5",
        "2026-10-05T08:00",
        "2026-10-05T09:00",
        None,
    )]);
    s.next_event = 3;
    assert_eq!(field(&s), "events[0].id");
}

/// A number that is not finite is no value to write (T2a): refused in the default and in
/// event values, also inside an array or a map.
#[test]
fn validate_refuses_non_finite_numbers() {
    let ok = || event("e1", "2026-10-05T08:00", "2026-10-05T09:00", None);
    let bad = [
        Value::Float(f64::NAN),
        Value::Float(f64::INFINITY),
        Value::Float(f64::NEG_INFINITY),
        Value::Array(vec![Value::UInt(1), Value::Float(f64::NAN)]),
        Value::Map([("k".to_owned(), Value::Float(f64::INFINITY))].into()),
    ];
    for v in &bad {
        let mut s = sched(vec![ok()]);
        s.default = v.clone();
        let e = validate(&s).unwrap_err();
        assert_eq!(e.field, "default", "{v:?}");
        assert!(e.rule.contains("finite"), "{e}");
        let mut e1 = ok();
        e1.value = v.clone();
        assert_eq!(field(&sched(vec![e1])), "events[0].value", "{v:?}");
    }
    let mut s = sched(vec![ok()]);
    s.default = Value::Float(-1.5e300);
    s.events[0].value = Value::Array(vec![Value::Float(0.0), Value::Int(-1)]);
    assert!(validate(&s).is_ok());
}

#[test]
fn validate_accepts() {
    let night = event(
        "e1",
        "2026-10-05T22:00",
        "2026-10-06T06:00",
        Some("FREQ=DAILY;INTERVAL=1"),
    );
    let moment = event("e2", "2026-11-01T06:00", "2026-11-01T06:00", None);
    let work = event(
        "e3",
        "2026-10-05T08:00",
        "2026-10-05T17:00",
        Some("FREQ=WEEKLY;INTERVAL=1;BYDAY=MO,TU,WE,TH,FR"),
    );
    validate(&sched(vec![night, moment, work])).unwrap();
}

#[test]
fn local_time_text() {
    assert_eq!(
        parse_local("t", "2026-10-05T08:00").unwrap(),
        datetime(2026, 10, 5, 8, 0, 0, 0)
    );
    assert_eq!(
        format_local(parse_local("t", "2026-10-05T08:00:30").unwrap()),
        "2026-10-05T08:00:30"
    );
    for bad in [
        "2026-10-05T08:00Z",
        "2026-10-05T08:00+02:00",
        "2026-10-05 08:00",
        "2026-13-05T08:00",
        "x",
    ] {
        assert_eq!(parse_local("t", bad).unwrap_err().field, "t", "{bad}");
    }
}

#[test]
fn export_round_trip() {
    let mut a = event(
        "e1",
        "2026-10-05T08:00",
        "2026-10-05T17:00",
        Some("FREQ=DAILY;INTERVAL=1;UNTIL=2027-01-01T00:00"),
    );
    a.display = "Open".into();
    let mut b = event("e3", "2026-11-01T06:00", "2026-11-01T06:00", None);
    b.value = Value::Float(1.5);
    b.special = true;
    let mut s = sched(vec![a, b]);
    s.next_event = 4;
    let v = schedule_to_value(&s);
    let Value::Map(m) = &v else { panic!() };
    assert_eq!(m["format"], Value::Str("wyrm-schedule/1".into()));
    let (back, targets) = schedule_from_value(&v).unwrap();
    assert_eq!(back, s);
    assert_eq!(targets, Value::Array(vec![]));
    assert_eq!(value_from_json(&value_to_json(&v)), v);
    let text = serde_json::to_string(&value_to_json(&v)).unwrap();
    let j: serde_json::Value = serde_json::from_str(&text).unwrap();
    assert_eq!(value_from_json(&j), v);

    let mut bad = m.clone();
    bad.insert("format".into(), Value::Str("wyrm-schedule/2".into()));
    assert_eq!(
        schedule_from_value(&Value::Map(bad)).unwrap_err().field,
        "format"
    );
}

const DSA: &str = r#"{"name":"Lobby","value":false,"events":[
 {"name":"Open","id":"k3Jd9","priority":2,"special":false,"value":true,
  "timeRange":{"sTime":"2026-10-05T08:00:00.000","eTime":"2026-10-05T17:00:00.000",
               "sDate":"2026-10-05T00:00:00.000","eDate":"2027-10-05T00:00:00.000","freq":2}},
 {"name":"Holiday","id":"x1","priority":1,"special":true,"value":false,
  "timeRange":{"sTime":"2026-12-25T00:00:00.000Z","eTime":"2026-12-25T23:59:00.000Z",
               "sDate":"2026-12-25T00:00:00.000Z","eDate":"2026-12-25T00:00:00.000Z","freq":0}},
 {"name":"Pulse","id":"m","priority":0,"special":false,"value":1,
  "timeRange":{"sTime":"2026-11-01T06:00:00.000","eTime":"2026-11-01T06:00:00.000",
               "sDate":"2026-11-01T06:00:00.000","eDate":"2026-11-01T06:00:00.000","freq":0}}]}"#;

#[test]
fn dsa_import() {
    let s = wyrm_schedule::dsa::import(DSA, "lobby", "Europe/Kyiv").unwrap();
    assert_eq!(
        (s.display.as_str(), &s.default, s.next_event),
        ("Lobby", &Value::Bool(false), 4)
    );
    let [open, hol, pulse] = &s.events[..] else {
        panic!()
    };
    assert_eq!(open.id, "e1");
    assert_eq!(open.display, "Open");
    assert_eq!(open.priority, 2);
    assert_eq!(format_local(open.start), "2026-10-05T08:00");
    assert_eq!(format_local(open.end), "2026-10-05T17:00");
    assert_eq!(
        open.recurrence.as_ref().unwrap().to_string(),
        "FREQ=DAILY;INTERVAL=1;UNTIL=2027-10-05T08:00"
    );
    assert_eq!(hol.id, "e2");
    assert!(hol.special && hol.recurrence.is_none());
    assert_eq!(format_local(hol.start), "2026-12-25T02:00");
    assert_eq!(format_local(hol.end), "2026-12-26T01:59");
    assert_eq!(pulse.id, "e3");
    assert_eq!(pulse.start, pulse.end);
    assert_eq!(format_local(pulse.start), "2026-11-01T06:00");
    assert_eq!(pulse.value, Value::UInt(1));

    let bad = DSA.replacen("\"freq\":2", "\"freq\":6", 1);
    let e = wyrm_schedule::dsa::import(&bad, "lobby", "Europe/Kyiv").unwrap_err();
    assert_eq!(e.field, "events[0].timeRange.freq");
}
