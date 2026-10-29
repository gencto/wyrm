//! Benchmarks of the schedule evaluator (ADR 0022): `cargo bench -p wyrm-schedule --bench eval`.
//!
//! 1. **`state_at` and `next_transition`** per call, for S schedules × E recurring events
//!    (S ∈ {1, 10, 100, 1000}, E ∈ {1, 10, 100}; S·E ≤ 100 000). E = 1000 is not measured: a
//!    schedule holds at most [`MAX_EVENTS`] (100) events and `Compiled::new` refuses more.
//! 2. **Cold start**: `Compiled::new` + `state_at` for 1000 schedules × 10 events, as a link start
//!    evaluates every schedule.
//! 3. **`occurrences` over one year** for one schedule of 10 events (the timeline, `get_events`).
//! 4. **Worst `COUNT` compile**: `Compiled::new` of 100 events whose `COUNT` rule never matches:
//!    each walks its full 400-year bound.
//!
//! The events mix daily, weekday, hourly, monthly and yearly rules with all priorities, so
//! windows overlap and precedence has work to do. Times are in `Europe/Kyiv`.

use std::time::{Duration, Instant};

use jiff::civil::DateTime;
use jiff::Timestamp;
use wyrm_core::Value;
use wyrm_schedule::{
    next_transition, occurrences, state_at, Compiled, Event, Micros, Rule, Schedule, MAX_EVENTS,
};

/// Calls measured per (S, E) cell, at least (whole rounds over the S schedules).
const CALLS: usize = 5_000;
/// Rounds of the cold start.
const COLD_ROUNDS: usize = 10;
/// Calls of `occurrences` over a year.
const YEAR_CALLS: usize = 200;

const MINUTE: Micros = 60_000_000;

fn dt(text: &str) -> DateTime {
    text.parse().unwrap()
}

/// Event `n` (1-based) of schedule `s`: a rule from a cycle of shapes, shifted by `s` and `n`.
fn event(s: usize, n: usize) -> Event {
    let shift = i8::try_from((s + n) % 50).unwrap();
    let (start, end, rule) = match n % 5 {
        0 => (
            "2026-01-05T08:00",
            "2026-01-05T17:00",
            "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR",
        ),
        1 => ("2026-01-01T22:00", "2026-01-02T06:00", "FREQ=DAILY"),
        2 => (
            "2026-01-01T00:05",
            "2026-01-01T00:35",
            "FREQ=HOURLY;INTERVAL=3",
        ),
        3 => (
            "2026-01-01T09:00",
            "2026-01-01T12:00",
            "FREQ=MONTHLY;BYMONTHDAY=1,15,-1",
        ),
        _ => (
            "2026-01-01T06:00",
            "2026-01-01T20:00",
            "FREQ=YEARLY;BYMONTH=1,5,10;BYDAY=1MO,-1FR",
        ),
    };
    let first = dt(start);
    let span = dt(end).duration_since(first);
    let start = first.with().minute(shift).build().unwrap();
    Event {
        id: format!("e{n}"),
        display: String::new(),
        value: Value::Int(i64::try_from(n).unwrap()),
        priority: u8::try_from(n % 10).unwrap(),
        special: false,
        start,
        end: start.checked_add(span).unwrap(),
        recurrence: Some(rule.parse::<Rule>().unwrap()),
    }
}

fn schedule(s: usize, events: usize) -> Compiled {
    Compiled::new(&Schedule {
        id: format!("s{s}"),
        display: String::new(),
        tz: "Europe/Kyiv".into(),
        default: Value::Int(0),
        enabled: true,
        next_event: u32::try_from(events + 1).unwrap(),
        events: (1..=events).map(|n| event(s, n)).collect(),
    })
    .unwrap()
}

fn base() -> Micros {
    "2026-10-29T08:00Z"
        .parse::<Timestamp>()
        .unwrap()
        .as_microsecond()
}

struct Stats {
    p50: Duration,
    p99: Duration,
}

fn stats(mut d: Vec<Duration>) -> Stats {
    d.sort();
    // The quantile in per mille, rounded to the nearest sample.
    let at = |q: usize| d[((d.len() - 1) * q + 500) / 1000];
    Stats {
        p50: at(500),
        p99: at(990),
    }
}

fn us(d: Duration) -> String {
    format!("{:.2} µs", d.as_secs_f64() * 1e6)
}

/// Per-call durations of `f` over the schedules, `CALLS` at least, at times spread over a week.
fn per_call<R>(all: &[Compiled], f: impl Fn(&Compiled, Micros) -> R) -> Stats {
    let rounds = CALLS.div_ceil(all.len());
    let mut d = Vec::with_capacity(rounds * all.len());
    let mut t = base();
    for _ in 0..rounds {
        for c in all {
            t += 7 * MINUTE;
            let begin = Instant::now();
            std::hint::black_box(f(c, t));
            d.push(begin.elapsed());
        }
    }
    stats(d)
}

fn main() {
    println!("wyrm-schedule evaluator (ADR 0022), zone Europe/Kyiv, per call");
    println!(
        "| {:>5} | {:>4} | {:>14} | {:>14} | {:>16} | {:>16} |",
        "S", "E", "state_at p50", "state_at p99", "next_trans. p50", "next_trans. p99"
    );
    println!(
        "|------:|-----:|---------------:|---------------:|-----------------:|-----------------:|"
    );
    for s in [1usize, 10, 100, 1000] {
        for e in [1usize, 10, 100, 1000] {
            if e > MAX_EVENTS || s * e > 100_000 {
                continue;
            }
            let all: Vec<Compiled> = (0..s).map(|i| schedule(i, e)).collect();
            let st = per_call(&all, state_at);
            let nt = per_call(&all, next_transition);
            println!(
                "| {:>5} | {:>4} | {:>14} | {:>14} | {:>16} | {:>16} |",
                s,
                e,
                us(st.p50),
                us(st.p99),
                us(nt.p50),
                us(nt.p99)
            );
        }
    }
    println!("(E = 1000 skipped: at most {MAX_EVENTS} events per schedule)");

    let mut cold = Vec::with_capacity(COLD_ROUNDS);
    for _ in 0..COLD_ROUNDS {
        let begin = Instant::now();
        for i in 0..1000 {
            let c = schedule(i, 10);
            std::hint::black_box(state_at(&c, base()));
        }
        cold.push(begin.elapsed());
    }
    let cold = stats(cold);
    println!(
        "cold start, Compiled::new + state_at, 1000 schedules × 10 events: p50 {:.2} ms, p99 {:.2} ms",
        cold.p50.as_secs_f64() * 1e3,
        cold.p99.as_secs_f64() * 1e3
    );

    let c = schedule(0, 10);
    let year = 366 * 24 * 60 * MINUTE;
    let n = occurrences(&c, base(), base() + year, usize::MAX).len();
    let mut d = Vec::with_capacity(YEAR_CALLS);
    for _ in 0..YEAR_CALLS {
        let begin = Instant::now();
        std::hint::black_box(occurrences(&c, base(), base() + year, usize::MAX));
        d.push(begin.elapsed());
    }
    let y = stats(d);
    println!(
        "occurrences over one year, 1 schedule × 10 events ({n} rows): p50 {}, p99 {}",
        us(y.p50),
        us(y.p99)
    );

    // The last rule never matches through its grid: every 7th day from a Monday or a Thursday.
    for text in [
        "FREQ=DAILY;COUNT=10000;BYMONTH=2;BYMONTHDAY=30",
        "FREQ=HOURLY;COUNT=10000;BYMONTH=2;BYMONTHDAY=30",
        "FREQ=DAILY;INTERVAL=7;COUNT=10000;BYDAY=TU",
    ] {
        let rule: Rule = text.parse().unwrap();
        let events: Vec<Event> = (1..=MAX_EVENTS)
            .map(|n| Event {
                recurrence: Some(rule.clone()),
                ..event(0, n)
            })
            .collect();
        let s = Schedule {
            id: "worst".into(),
            display: String::new(),
            tz: "Europe/Kyiv".into(),
            default: Value::Int(0),
            enabled: true,
            next_event: u32::try_from(MAX_EVENTS + 1).unwrap(),
            events: events
                .into_iter()
                .map(|mut e| {
                    e.end = e
                        .start
                        .checked_add(jiff::SignedDuration::from_mins(10))
                        .unwrap();
                    e
                })
                .collect(),
        };
        let begin = Instant::now();
        std::hint::black_box(Compiled::new(&s).unwrap());
        println!(
            "worst COUNT compile, {MAX_EVENTS} events {text} (never matches): {:.2} ms",
            begin.elapsed().as_secs_f64() * 1e3
        );
    }
}
