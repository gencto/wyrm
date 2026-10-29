//! Calendar and DST fixtures of the evaluator (ADR 0022 "Model"). Expected DST instants are UTC
//! literals, not computed with the zone.

use std::time::{Duration, Instant};

use jiff::tz::TimeZone;
use jiff::Timestamp;
use wyrm_core::Value;
use wyrm_schedule::*;

/// A local time that is neither in a gap nor in a fold.
fn at(tz: &str, local: &str) -> Micros {
    let dt = parse_local("at", local).unwrap();
    let tz = TimeZone::get(tz).unwrap();
    tz.to_ambiguous_timestamp(dt)
        .unambiguous()
        .unwrap()
        .as_microsecond()
}

fn utc(text: &str) -> Micros {
    text.parse::<Timestamp>().unwrap().as_microsecond()
}

struct Ev(Event);

impl Ev {
    fn new(n: u32, start: &str, end: &str, rec: Option<&str>) -> Ev {
        Ev(Event {
            id: format!("e{n}"),
            display: String::new(),
            value: Value::Int(i64::from(n)),
            priority: 1,
            special: false,
            start: parse_local("start", start).unwrap(),
            end: parse_local("end", end).unwrap(),
            recurrence: rec.map(|r| r.parse().unwrap()),
        })
    }
    fn priority(mut self, p: u8) -> Ev {
        self.0.priority = p;
        self
    }
    fn special(mut self) -> Ev {
        self.0.special = true;
        self
    }
}

fn compile(tz: &str, events: Vec<Ev>) -> Compiled {
    let events: Vec<Event> = events.into_iter().map(|e| e.0).collect();
    let next = events
        .iter()
        .map(|e| e.id[1..].parse::<u32>().unwrap())
        .max()
        .unwrap_or(0)
        + 1;
    Compiled::new(&Schedule {
        id: "s".into(),
        display: String::new(),
        tz: tz.into(),
        default: Value::Int(0),
        enabled: true,
        next_event: next,
        events,
    })
    .unwrap()
}

fn default() -> State {
    State {
        value: Value::Int(0),
        source: Source::Default,
    }
}

fn event(n: i64, at: Micros) -> State {
    State {
        value: Value::Int(n),
        source: Source::Event {
            id: format!("e{n}"),
            at,
        },
    }
}

fn starts(c: &Compiled, from: Micros, to: Micros) -> Vec<Micros> {
    occurrences(c, from, to, 1000)
        .iter()
        .map(|o| o.start)
        .collect()
}

#[test]
fn daily_window_across_midnight() {
    let z = "UTC";
    let c = compile(
        z,
        vec![Ev::new(
            1,
            "2026-10-01T22:00",
            "2026-10-02T06:00",
            Some("FREQ=DAILY"),
        )],
    );
    assert_eq!(
        state_at(&c, at(z, "2026-10-10T23:00")),
        event(1, at(z, "2026-10-10T22:00"))
    );
    assert_eq!(
        state_at(&c, at(z, "2026-10-10T05:59")),
        event(1, at(z, "2026-10-09T22:00"))
    );
    assert_eq!(state_at(&c, at(z, "2026-10-10T06:00")), default());
    assert_eq!(
        next_transition(&c, at(z, "2026-10-10T12:00")),
        Some((
            at(z, "2026-10-10T22:00"),
            event(1, at(z, "2026-10-10T22:00"))
        ))
    );
}

#[test]
fn hourly_window_across_the_hour() {
    let z = "UTC";
    let c = compile(
        z,
        vec![Ev::new(
            1,
            "2026-10-10T10:50",
            "2026-10-10T11:10",
            Some("FREQ=HOURLY"),
        )],
    );
    assert_eq!(
        state_at(&c, at(z, "2026-10-10T12:05")),
        event(1, at(z, "2026-10-10T11:50"))
    );
    assert_eq!(
        next_transition(&c, at(z, "2026-10-10T12:05")),
        Some((at(z, "2026-10-10T12:10"), default()))
    );
}

#[test]
fn weekly_wrap() {
    let z = "UTC";
    // Sunday 20:00 to Monday 04:00.
    let c = compile(
        z,
        vec![Ev::new(
            1,
            "2026-11-01T20:00",
            "2026-11-02T04:00",
            Some("FREQ=WEEKLY;BYDAY=SU"),
        )],
    );
    assert_eq!(
        state_at(&c, at(z, "2026-11-09T03:00")),
        event(1, at(z, "2026-11-08T20:00"))
    );
    assert_eq!(state_at(&c, at(z, "2026-11-09T05:00")), default());
}

#[test]
fn day_31_is_skipped() {
    let z = "UTC";
    let c = compile(
        z,
        vec![Ev::new(
            1,
            "2027-01-31T09:00",
            "2027-01-31T10:00",
            Some("FREQ=MONTHLY;BYMONTHDAY=31"),
        )],
    );
    assert_eq!(
        starts(&c, at(z, "2027-01-01T00:00"), at(z, "2027-07-01T00:00")),
        vec![
            at(z, "2027-01-31T09:00"),
            at(z, "2027-03-31T09:00"),
            at(z, "2027-05-31T09:00"),
        ]
    );
}

#[test]
fn last_day_of_month() {
    let z = "UTC";
    let c = compile(
        z,
        vec![Ev::new(
            1,
            "2027-01-31T09:00",
            "2027-01-31T10:00",
            Some("FREQ=MONTHLY;BYMONTHDAY=-1"),
        )],
    );
    assert_eq!(
        starts(&c, at(z, "2027-02-01T00:00"), at(z, "2027-03-01T00:00")),
        vec![at(z, "2027-02-28T09:00")]
    );
    assert_eq!(
        starts(&c, at(z, "2028-02-01T00:00"), at(z, "2028-03-01T00:00")),
        vec![at(z, "2028-02-29T09:00")]
    );
}

#[test]
fn feb_29_yearly() {
    let z = "UTC";
    let c = compile(
        z,
        vec![Ev::new(
            1,
            "2028-02-29T10:00",
            "2028-02-29T11:00",
            Some("FREQ=YEARLY"),
        )],
    );
    assert_eq!(
        starts(&c, at(z, "2028-01-01T00:00"), at(z, "2033-01-01T00:00")),
        vec![at(z, "2028-02-29T10:00"), at(z, "2032-02-29T10:00")]
    );
    assert_eq!(
        occurrences(&c, at(z, "2028-03-01T00:00"), at(z, "2040-01-01T00:00"), 1)[0].start,
        at(z, "2032-02-29T10:00")
    );
}

#[test]
fn byday_ordinals() {
    let z = "UTC";
    let c = compile(
        z,
        vec![
            Ev::new(
                1,
                "2026-10-05T09:00",
                "2026-10-05T10:00",
                Some("FREQ=MONTHLY;BYDAY=1MO"),
            ),
            Ev::new(
                2,
                "2026-10-30T09:00",
                "2026-10-30T10:00",
                Some("FREQ=MONTHLY;BYDAY=-1FR"),
            ),
        ],
    );
    let nov = occurrences(&c, at(z, "2026-11-01T00:00"), at(z, "2026-12-01T00:00"), 10);
    let got: Vec<(&str, Micros)> = nov.iter().map(|o| (o.event.as_str(), o.start)).collect();
    assert_eq!(
        got,
        vec![
            ("e1", at(z, "2026-11-02T09:00")),
            ("e2", at(z, "2026-11-27T09:00")),
        ]
    );
}

#[test]
fn three_overlaps() {
    let z = "UTC";
    let c = compile(
        z,
        vec![
            Ev::new(1, "2026-10-10T08:00", "2026-10-10T18:00", None).priority(0),
            Ev::new(2, "2026-10-10T09:00", "2026-10-10T17:00", None).priority(3),
            Ev::new(10, "2026-10-10T10:00", "2026-10-10T12:00", None).priority(3),
        ],
    );
    assert_eq!(
        state_at(&c, at(z, "2026-10-10T08:30")),
        event(1, at(z, "2026-10-10T08:00"))
    );
    assert_eq!(
        state_at(&c, at(z, "2026-10-10T11:00")),
        event(10, at(z, "2026-10-10T10:00"))
    );
    assert_eq!(
        state_at(&c, at(z, "2026-10-10T13:00")),
        event(2, at(z, "2026-10-10T09:00"))
    );
    assert_eq!(
        next_transition(&c, at(z, "2026-10-10T11:00")),
        Some((
            at(z, "2026-10-10T12:00"),
            event(2, at(z, "2026-10-10T09:00"))
        ))
    );
    // Equal start: the lower event number wins, in numeric order (e2 before e10).
    let c = compile(
        z,
        vec![
            Ev::new(10, "2026-10-10T09:00", "2026-10-10T12:00", None).priority(3),
            Ev::new(2, "2026-10-10T09:00", "2026-10-10T17:00", None).priority(3),
            Ev::new(1, "2026-10-10T08:00", "2026-10-10T18:00", None).priority(0),
        ],
    );
    assert_eq!(
        state_at(&c, at(z, "2026-10-10T10:00")),
        event(2, at(z, "2026-10-10T09:00"))
    );
}

#[test]
fn priority_zero_is_lowest() {
    let z = "UTC";
    let c = compile(
        z,
        vec![
            Ev::new(1, "2026-10-10T08:00", "2026-10-10T18:00", None).priority(9),
            Ev::new(2, "2026-10-10T09:00", "2026-10-10T17:00", None).priority(0),
        ],
    );
    assert_eq!(
        state_at(&c, at(z, "2026-10-10T10:00")),
        event(1, at(z, "2026-10-10T08:00"))
    );
}

#[test]
fn special_day_blocks_the_whole_local_day() {
    let z = "Europe/Kyiv";
    let c = compile(
        z,
        vec![
            Ev::new(
                1,
                "2026-12-01T08:00",
                "2026-12-01T17:00",
                Some("FREQ=DAILY"),
            ),
            Ev::new(2, "2026-12-25T12:00", "2026-12-25T13:00", None).special(),
        ],
    );
    assert_eq!(state_at(&c, at(z, "2026-12-25T09:00")), default());
    assert_eq!(
        state_at(&c, at(z, "2026-12-25T12:30")),
        event(2, at(z, "2026-12-25T12:00"))
    );
    assert_eq!(
        state_at(&c, at(z, "2026-12-26T09:00")),
        event(1, at(z, "2026-12-26T08:00"))
    );
    assert_eq!(
        next_transition(&c, at(z, "2026-12-24T16:00")),
        Some((at(z, "2026-12-24T17:00"), default()))
    );
    assert_eq!(
        next_transition(&c, at(z, "2026-12-24T17:00")),
        Some((
            at(z, "2026-12-25T12:00"),
            event(2, at(z, "2026-12-25T12:00"))
        ))
    );
    assert_eq!(
        next_transition(&c, at(z, "2026-12-25T12:00")),
        Some((at(z, "2026-12-25T13:00"), default()))
    );
    assert_eq!(
        next_transition(&c, at(z, "2026-12-25T13:00")),
        Some((
            at(z, "2026-12-26T08:00"),
            event(1, at(z, "2026-12-26T08:00"))
        ))
    );
}

#[test]
fn special_day_blocks_a_normal_moment() {
    let z = "UTC";
    let c = compile(
        z,
        vec![
            Ev::new(1, "2026-12-25T06:00", "2026-12-25T06:00", None).priority(1),
            Ev::new(2, "2026-12-25T20:00", "2026-12-25T21:00", None)
                .priority(9)
                .special(),
        ],
    );
    assert_eq!(
        next_transition(&c, at(z, "2026-12-25T00:00")),
        Some((
            at(z, "2026-12-25T20:00"),
            event(2, at(z, "2026-12-25T20:00"))
        ))
    );
}

#[test]
fn dst_spring_forward_kyiv() {
    let z = "Europe/Kyiv";
    let c = compile(
        z,
        vec![Ev::new(
            1,
            "2027-03-20T03:30",
            "2027-03-20T05:00",
            Some("FREQ=DAILY"),
        )],
    );
    // 2027-03-28: 03:00 → 04:00 local; 03:30 does not exist and starts at 04:00 (01:00 UTC).
    assert_eq!(state_at(&c, utc("2027-03-28T00:45Z")), default());
    assert_eq!(
        state_at(&c, utc("2027-03-28T01:30Z")),
        event(1, utc("2027-03-28T01:00Z"))
    );
    assert_eq!(
        next_transition(&c, utc("2027-03-28T00:45Z")),
        Some((utc("2027-03-28T01:00Z"), event(1, utc("2027-03-28T01:00Z"))))
    );
    assert_eq!(
        next_transition(&c, utc("2027-03-28T01:30Z")),
        Some((utc("2027-03-28T02:00Z"), default()))
    );
    assert_eq!(
        next_transition(&c, utc("2027-03-28T02:00Z")),
        Some((utc("2027-03-29T00:30Z"), event(1, utc("2027-03-29T00:30Z"))))
    );
    assert_eq!(
        next_transition(&c, utc("2027-03-29T00:30Z")),
        Some((utc("2027-03-29T02:00Z"), default()))
    );
}

#[test]
fn dst_fall_back_kyiv() {
    let z = "Europe/Kyiv";
    let c = compile(
        z,
        vec![Ev::new(
            1,
            "2026-10-20T03:30",
            "2026-10-20T05:00",
            Some("FREQ=DAILY"),
        )],
    );
    // 2026-10-25: 04:00 → 03:00 local; 03:30 takes the earlier instant (00:30 UTC).
    assert_eq!(
        next_transition(&c, utc("2026-10-24T12:00Z")),
        Some((utc("2026-10-25T00:30Z"), event(1, utc("2026-10-25T00:30Z"))))
    );
    assert_eq!(
        state_at(&c, utc("2026-10-25T01:45Z")),
        event(1, utc("2026-10-25T00:30Z"))
    );
    assert_eq!(
        next_transition(&c, utc("2026-10-25T00:30Z")),
        Some((utc("2026-10-25T03:00Z"), default()))
    );
}

#[test]
fn dst_new_york() {
    let z = "America/New_York";
    let c = compile(
        z,
        vec![Ev::new(
            1,
            "2026-03-01T08:00",
            "2026-03-01T17:00",
            Some("FREQ=DAILY"),
        )],
    );
    for (from, start, end) in [
        (
            "2026-03-08T05:00Z",
            "2026-03-08T12:00Z",
            "2026-03-08T21:00Z",
        ),
        (
            "2026-11-01T05:00Z",
            "2026-11-01T13:00Z",
            "2026-11-01T22:00Z",
        ),
    ] {
        assert_eq!(
            next_transition(&c, utc(from)),
            Some((utc(start), event(1, utc(start))))
        );
        assert_eq!(next_transition(&c, utc(start)), Some((utc(end), default())));
    }
}

#[test]
fn moment_fires_and_is_not_replayed() {
    let z = "UTC";
    let c = compile(
        z,
        vec![Ev::new(1, "2026-10-10T06:00", "2026-10-10T06:00", None).priority(0)],
    );
    let six = at(z, "2026-10-10T06:00");
    assert_eq!(
        next_transition(&c, at(z, "2026-10-10T05:00")),
        Some((
            six,
            State {
                value: Value::Int(1),
                source: Source::Moment {
                    id: "e1".into(),
                    at: six
                },
            }
        ))
    );
    assert_eq!(state_at(&c, at(z, "2026-10-10T06:30")), default());
    assert_eq!(next_transition(&c, six), None);
}

#[test]
fn moment_loses_to_higher_window() {
    let z = "UTC";
    let c = compile(
        z,
        vec![
            Ev::new(1, "2026-10-10T05:00", "2026-10-10T07:00", None).priority(1),
            Ev::new(2, "2026-10-10T06:00", "2026-10-10T06:00", None).priority(2),
        ],
    );
    assert_eq!(
        next_transition(&c, at(z, "2026-10-10T05:30")),
        Some((at(z, "2026-10-10T07:00"), default()))
    );
}

#[test]
fn no_transition_inside_horizon() {
    let z = "UTC";
    let c = compile(
        z,
        vec![Ev::new(1, "2020-01-01T08:00", "2020-01-01T09:00", None)],
    );
    assert_eq!(state_at(&c, at(z, "2026-10-10T08:30")), default());
    assert_eq!(next_transition(&c, at(z, "2026-10-10T08:30")), None);
    // An event beyond the horizon is not reported either.
    let c = compile(
        z,
        vec![Ev::new(1, "2028-01-01T08:00", "2028-01-01T09:00", None)],
    );
    assert_eq!(next_transition(&c, at(z, "2026-10-10T08:30")), None);
}

#[test]
fn count_ends_rule() {
    let z = "UTC";
    let c = compile(
        z,
        vec![Ev::new(
            1,
            "2026-10-01T08:00",
            "2026-10-01T09:00",
            Some("FREQ=DAILY;COUNT=3"),
        )],
    );
    assert_eq!(
        starts(&c, at(z, "2026-09-01T00:00"), at(z, "2027-01-01T00:00")),
        vec![
            at(z, "2026-10-01T08:00"),
            at(z, "2026-10-02T08:00"),
            at(z, "2026-10-03T08:00"),
        ]
    );
    assert_eq!(
        state_at(&c, at(z, "2026-10-03T08:30")),
        event(1, at(z, "2026-10-03T08:00"))
    );
    assert_eq!(state_at(&c, at(z, "2026-10-04T08:30")), default());
    assert_eq!(next_transition(&c, at(z, "2026-10-03T10:00")), None);
}

#[test]
fn count_counts_from_the_start_not_the_week() {
    let z = "UTC";
    // 2026-10-07 is a Wednesday: the Monday and Tuesday of that first week do not count.
    let c = compile(
        z,
        vec![Ev::new(
            1,
            "2026-10-07T08:00",
            "2026-10-07T09:00",
            Some("FREQ=WEEKLY;COUNT=3;BYDAY=MO,WE"),
        )],
    );
    assert_eq!(
        starts(&c, at(z, "2026-10-01T00:00"), at(z, "2027-01-01T00:00")),
        vec![
            at(z, "2026-10-07T08:00"),
            at(z, "2026-10-12T08:00"),
            at(z, "2026-10-14T08:00"),
        ]
    );
}

#[test]
fn windows_of_one_event_overlap() {
    let z = "UTC";
    // Day 1 08:00 to day 2 14:00, on days 1 and 2: the two windows overlap on day 2.
    let c = compile(
        z,
        vec![Ev::new(
            1,
            "2026-11-01T08:00",
            "2026-11-02T14:00",
            Some("FREQ=MONTHLY;BYMONTHDAY=1,2"),
        )],
    );
    assert_eq!(
        state_at(&c, at(z, "2026-12-02T10:00")),
        event(1, at(z, "2026-12-02T08:00"))
    );
    // The end of the day-1 window changes nothing; the end of the day-2 window does.
    assert_eq!(
        next_transition(&c, at(z, "2026-12-02T10:00")),
        Some((at(z, "2026-12-03T14:00"), default()))
    );
}

/// One positive case per BY* semantics of Ruling R5.
#[test]
fn by_parts_expand_and_filter() {
    let z = "UTC";
    let one = |start: &str, rule: &str, from: &str, to: &str| {
        let end = format!("{}T23:00", &start[..10]);
        let c = compile(z, vec![Ev::new(1, start, &end, Some(rule))]);
        starts(&c, at(z, from), at(z, to))
    };
    let days = |list: &[&str]| -> Vec<Micros> { list.iter().map(|d| at(z, d)).collect() };
    // DAILY: BYDAY filters.
    assert_eq!(
        one(
            "2026-11-02T22:00",
            "FREQ=DAILY;BYDAY=MO,FR",
            "2026-11-01T00:00",
            "2026-11-15T00:00"
        ),
        days(&[
            "2026-11-02T22:00",
            "2026-11-06T22:00",
            "2026-11-09T22:00",
            "2026-11-13T22:00",
        ])
    );
    // WEEKLY: BYDAY expands, BYMONTH filters.
    assert_eq!(
        one(
            "2026-11-03T22:00",
            "FREQ=WEEKLY;BYMONTH=12;BYDAY=TU",
            "2026-11-01T00:00",
            "2027-01-01T00:00"
        ),
        days(&[
            "2026-12-01T22:00",
            "2026-12-08T22:00",
            "2026-12-15T22:00",
            "2026-12-22T22:00",
            "2026-12-29T22:00",
        ])
    );
    // MONTHLY: BYMONTHDAY and BYDAY both given → their intersection (Friday the 13th).
    assert_eq!(
        one(
            "2026-10-01T22:00",
            "FREQ=MONTHLY;BYMONTHDAY=13;BYDAY=FR",
            "2026-10-01T00:00",
            "2028-01-01T00:00"
        ),
        days(&["2026-11-13T22:00", "2027-08-13T22:00"])
    );
    // YEARLY: BYMONTH expands; no day part → the start's day of month.
    assert_eq!(
        one(
            "2026-03-15T22:00",
            "FREQ=YEARLY;BYMONTH=3,9",
            "2026-01-01T00:00",
            "2027-12-31T00:00"
        ),
        days(&[
            "2026-03-15T22:00",
            "2026-09-15T22:00",
            "2027-03-15T22:00",
            "2027-09-15T22:00",
        ])
    );
}

#[test]
fn rules_that_never_match_end() {
    let z = "UTC";
    let c = compile(
        z,
        vec![
            Ev::new(
                1,
                "2026-10-01T08:00",
                "2026-10-01T08:30",
                Some("FREQ=HOURLY;BYMONTH=2;BYMONTHDAY=30"),
            ),
            Ev::new(
                2,
                "2026-10-01T08:00",
                "2026-10-01T08:30",
                Some("FREQ=DAILY;COUNT=5;BYMONTH=4;BYMONTHDAY=31"),
            ),
            Ev::new(
                3,
                "2026-10-01T08:00",
                "2026-10-01T08:30",
                Some("FREQ=YEARLY;BYDAY=6MO"),
            ),
        ],
    );
    let t = at(z, "2026-10-10T08:15");
    assert_eq!(state_at(&c, t), default());
    assert_eq!(next_transition(&c, t), None);
    assert!(occurrences(&c, t, at(z, "2030-01-01T00:00"), 10).is_empty());
}

#[test]
fn occurrences_over_a_year() {
    let z = "Europe/Kyiv";
    let c = compile(
        z,
        vec![Ev::new(
            1,
            "2026-10-05T08:00",
            "2026-10-05T17:00",
            Some("FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR"),
        )],
    );
    let from = at(z, "2027-01-01T00:00");
    let to = at(z, "2028-01-01T00:00");
    let all = occurrences(&c, from, to, 1000);
    assert_eq!(all.len(), 261);
    assert!(all.windows(2).all(|w| w[0].start < w[1].start));
    let ten = occurrences(&c, from, to, 10);
    assert_eq!(ten.len(), 10);
    assert_eq!(ten[0].start, at(z, "2027-01-01T08:00"));
    assert_eq!(ten[0].end, at(z, "2027-01-01T17:00"));
    assert_eq!(ten[..], all[..10]);
}

#[test]
fn old_dtstart_is_fast() {
    let z = "UTC";
    let c = compile(
        z,
        vec![Ev::new(
            1,
            "2000-01-01T00:10",
            "2000-01-01T00:20",
            Some("FREQ=HOURLY"),
        )],
    );
    let t = at(z, "2026-10-10T12:15");
    let begin = Instant::now();
    let s = state_at(&c, t);
    let took = begin.elapsed();
    assert_eq!(s, event(1, at(z, "2026-10-10T12:10")));
    assert!(took < Duration::from_millis(250), "state_at took {took:?}");
    let begin = Instant::now();
    let n = next_transition(&c, t);
    let took = begin.elapsed();
    assert_eq!(n, Some((at(z, "2026-10-10T12:20"), default())));
    assert!(
        took < Duration::from_millis(250),
        "next_transition took {took:?}"
    );
}

/// `next_transition` agrees with `state_at` sampled every 5 minutes: the window state changes
/// only at a reported transition, and is the reported state there.
#[test]
fn transitions_agree_with_state_at() {
    let z = "Europe/Kyiv";
    let c = compile(
        z,
        vec![
            Ev::new(
                1,
                "2027-03-01T08:00",
                "2027-03-01T17:00",
                Some("FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR"),
            )
            .priority(5),
            Ev::new(
                2,
                "2027-03-01T03:15",
                "2027-03-01T03:45",
                Some("FREQ=DAILY"),
            )
            .priority(2),
            Ev::new(
                3,
                "2027-03-01T00:40",
                "2027-03-01T01:20",
                Some("FREQ=HOURLY;INTERVAL=5"),
            )
            .priority(0),
            Ev::new(
                4,
                "2027-03-06T10:00",
                "2027-03-06T11:00",
                Some("FREQ=WEEKLY;BYDAY=SA"),
            )
            .special(),
            Ev::new(
                5,
                "2027-03-02T12:00",
                "2027-03-02T12:00",
                Some("FREQ=DAILY"),
            ),
            Ev::new(
                6,
                "2027-03-07T23:00",
                "2027-03-08T02:00",
                Some("FREQ=MONTHLY;BYDAY=1SU,-1SU"),
            )
            .priority(1)
            .special(),
        ],
    );
    let mut t = utc("2027-03-01T00:00Z");
    let end = utc("2027-04-15T00:00Z");
    let step = 5 * 60 * 1_000_000;
    let mut state = state_at(&c, t);
    let mut checked = 0;
    let mut moments = 0;
    while t < end {
        let (p, s) = next_transition(&c, t).unwrap();
        assert!(p > t);
        let mut x = t + step - t.rem_euclid(step);
        while x < p.min(end) {
            assert_eq!(state_at(&c, x), state, "at {x} between {t} and {p}");
            x += step;
            checked += 1;
        }
        if let Source::Moment { .. } = s.source {
            assert_eq!(state_at(&c, p), state, "a moment leaves the window state");
            moments += 1;
        } else {
            assert_ne!(s, state);
            assert_eq!(state_at(&c, p), s);
            state = s;
        }
        t = p;
    }
    assert!(checked > 10_000);
    // e5 fires daily except on the special Saturdays and on the special days of e6.
    assert!(moments > 30, "{moments} moments");
}
