//! Cold start of the scheduler link (ADR 0022 "Benchmarks"): `cargo bench -p
//! wyrm-link-scheduler --bench cold_start`.
//!
//! A store of 1 000 schedules × 2 events × 1 target (9 000 nodes: the node budget forbids
//! 10 events each at this size, ruling R3), as the app saves it. Each round starts a new
//! instance on it at 07:00Z, when every schedule is in a window, and measures on the wall clock
//! of this process:
//!
//! 1. **`start`**: the first event (root, index, the first batch);
//! 2. **tree**: until every schedule is declared (the `0` ms continuations run);
//! 3. **last write**: until the 1 000th `set` is sent; the host answers each `ok` at once, so
//!    the write queue (at most 50 in flight) drains as fast as the app can;
//! 4. **confirmed**: until every target is `confirmed`.
//!
//! Targets confirm with `ack`, so no target waits for a first sample. With `read_back` or
//! `feedback`, a target without a record waits [`FIRST_SAMPLE_MS`] (2 s) for a sample that
//! already shows the value before it writes: the second table adds that wait on top of the
//! work. `SimHost` (`tests/common`) applies each event's commands as the portable runtime does;
//! its bookkeeping is in the numbers.

#[path = "../tests/common/mod.rs"]
mod common;

use std::collections::BTreeMap;
use std::time::{Duration, Instant};

use common::{at, text, SimHost};
use wyrm_core::Value;
use wyrm_link_scheduler::limits::{FIRST_SAMPLE_MS, MAX_INFLIGHT};
use wyrm_schedule::{parse_local, schedule_to_value, Event, Schedule};

const SCHEDULES: usize = 1000;
const ROUNDS: usize = 10;

fn event(n: u32, start: &str, end: &str, rule: &str) -> Event {
    Event {
        id: format!("e{n}"),
        display: String::new(),
        value: Value::Bool(true),
        priority: 0,
        special: false,
        start: parse_local("start", start).unwrap(),
        end: parse_local("end", end).unwrap(),
        recurrence: Some(rule.parse().unwrap()),
    }
}

/// Schedule `i` as saved: two events and one target on its own point.
fn definition(i: usize, confirm: &str) -> Value {
    let s = Schedule {
        id: format!("s{i}"),
        display: format!("s{i}"),
        tz: "UTC".into(),
        default: Value::Bool(false),
        enabled: true,
        events: vec![
            event(1, "2026-10-29T06:00", "2026-10-29T08:00", "FREQ=DAILY"),
            event(
                2,
                "2026-10-29T12:00",
                "2026-10-29T13:00",
                "FREQ=WEEKLY;BYDAY=MO,TH",
            ),
        ],
        next_event: 3,
    };
    let Value::Map(mut m) = schedule_to_value(&s) else {
        unreachable!("an export is a map")
    };
    let target = BTreeMap::from([
        ("id".to_owned(), text("t1")),
        (
            "point".to_owned(),
            text(&format!("wy/s/downstream/plc/p{i}")),
        ),
        ("confirm".to_owned(), text(confirm)),
        ("enabled".to_owned(), Value::Bool(true)),
        ("created_by".to_owned(), text("user:bench")),
    ]);
    m.insert("targets".into(), Value::Array(vec![Value::Map(target)]));
    m.insert("next_target".into(), Value::UInt(2));
    Value::Map(m)
}

/// A host at 07:00Z whose store holds the 1 000 definitions.
fn seeded(confirm: &str) -> SimHost {
    let mut h = SimHost::new(at("2026-10-29T07:00:00Z"));
    let ids = (0..SCHEDULES).map(|i| text(&format!("s{i}"))).collect();
    h.store_put(
        "index",
        wyrm_core::codec::to_vec(&Value::Array(ids)).unwrap(),
    );
    for i in 0..SCHEDULES {
        h.store_put(
            &format!("s/s{i}"),
            wyrm_core::codec::to_vec(&definition(i, confirm)).unwrap(),
        );
    }
    h
}

#[derive(Default)]
struct Round {
    start: Duration,
    tree: Duration,
    last_write: Duration,
    confirmed: Duration,
}

/// Answers every write `ok` (and, with `read_back`, shows it on the point) until none waits;
/// the time of the last write sent and the writes counted.
fn drain(h: &mut SimHost, began: Instant, read_back: bool) -> (Duration, usize) {
    let mut written = 0;
    let mut last = Duration::ZERO;
    loop {
        h.settle();
        let due = h.unreplied();
        if due.is_empty() {
            return (last, written);
        }
        written += due.len();
        last = began.elapsed();
        for (id, key, v) in due {
            h.reply(id, Ok(Value::Null));
            if read_back {
                h.deliver(&key, v);
            }
        }
    }
}

fn round(confirm: &str) -> Round {
    let read_back = confirm != "ack";
    let mut h = seeded(confirm);
    let began = Instant::now();
    h.start(Value::Null).expect("start");
    let start = began.elapsed();
    h.settle();
    let tree = began.elapsed();
    assert_eq!(h.nodes.len(), SCHEDULES * 9, "every schedule declared");
    if read_back {
        // no sample comes: each target writes when its wait ends (simulated time)
        h.advance(FIRST_SAMPLE_MS);
    }
    let (last_write, written) = drain(&mut h, began, read_back);
    let confirmed = began.elapsed();
    assert_eq!(written, SCHEDULES, "one write per target");
    assert!(h.max_unreplied <= MAX_INFLIGHT, "{}", h.max_unreplied);
    for i in [0, SCHEDULES / 2, SCHEDULES - 1] {
        assert_eq!(
            h.value(&format!("s{i}/targets/t1")),
            Some(text("confirmed")),
            "s{i}"
        );
    }
    Round {
        start,
        tree,
        last_write,
        confirmed,
    }
}

/// One measured step of a [`Round`].
type Step = fn(&Round) -> Duration;

fn ms(d: Duration) -> String {
    format!("{:.2} ms", d.as_secs_f64() * 1e3)
}

/// p50 and the largest of `xs` (with 10 rounds the p99 is the largest).
fn stats(mut xs: Vec<Duration>) -> (Duration, Duration) {
    xs.sort();
    (xs[xs.len() / 2], xs[xs.len() - 1])
}

fn table(confirm: &str) {
    round(confirm); // warm-up
    let rounds: Vec<Round> = (0..ROUNDS).map(|_| round(confirm)).collect();
    println!(
        "\n{SCHEDULES} schedules × 2 events × 1 target, confirm {confirm}, {ROUNDS} rounds \
         (from the start of `Scheduler::start`):"
    );
    println!("| step                 |        p50 |        max |");
    println!("|:---------------------|-----------:|-----------:|");
    let rows: [(&str, Step); 4] = [
        ("`start` event", |r| r.start),
        ("tree complete", |r| r.tree),
        ("last write sent", |r| r.last_write),
        ("all confirmed", |r| r.confirmed),
    ];
    for (name, f) in rows {
        let (p50, max) = stats(rounds.iter().map(f).collect());
        println!("| {name:<20} | {:>10} | {:>10} |", ms(p50), ms(max));
    }
    if confirm != "ack" {
        println!(
            "(plus the {FIRST_SAMPLE_MS} ms first-sample wait before the writes, real time on a \
             real host)"
        );
    }
}

fn main() {
    // `cargo test --benches` runs the bench binary once with `--bench` absent: keep it short
    if !std::env::args().any(|a| a == "--bench") {
        round("ack");
        return;
    }
    table("ack");
    table("read_back");
}
