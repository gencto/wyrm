# Scheduler link (ADR 0022) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A scheduler that drives equipment from the broker offline: schedules with prioritised, recurring events in a named time zone, written to points with confirmation, retries and manual override, as one portable `App` that runs embedded in `wyrmd` (fixed instance `wy/<site>/downstream/scheduler`), as a process package and as a WASM package.

**Architecture:** A pure crate `wyrm-schedule` (no I/O, no async, builds for `wasm32-unknown-unknown`) holds the model, validation, import/export and the evaluation core (`state_at`, `next_transition`, `occurrences`). The link crate `links/scheduler` (`wyrm-link-scheduler`) is an `App` on the portable API (ADR 0023): tree and actions, the host store, one wake heap behind one host timer, targets with a bounded write queue. `wyrmd` starts it per router build like `storage`, with its own requester key that every link trusts at `write` under `wy/<site>/downstream`.

**Tech Stack:** Rust 2021, `wyrm-core` (Value, NodeMeta, codec), `wyrm-link-api` (`App`, `Host`, `BufferHost`), `wyrm-link-portable` (`Portable<A>`), `wyrm-link-guest` (`export!`), `jiff` 0.2 (civil date-times and bundled tzdb), `serde_json` (import/export text only).

**Spec:** `docs/adr/0022-scheduler-link.md` (the scheduler) together with `docs/adr/0023-portable-links-and-wasm-world-v2.md` (the host it runs on). Where this plan rules on a gap between them and the code, the ruling is in "Rulings" below and goes into ADR 0022 in Task 7.

## Global Constraints

- Code, comments, commit messages: English. Commit straight to `main` and push after each task; no branches.
- Before each push run, and fix until clean:
  - `cargo fmt --all -- --check`
  - `CARGO_TARGET_DIR=target/r199 cargo +1.99.0 clippy --workspace --all-targets --all-features -- -D warnings`
  - `cargo test -p <every crate the task touched> --all-features`
  - `cargo test -p wyrmd --all-features --test e2e` when the task touches a link, the SDK, `wyrm-link-*`, the admin or `wyrmd`.
  - `cargo build -p wyrm-schedule -p wyrm-link-scheduler --features wyrm-link-scheduler/wasm --lib --target wasm32-unknown-unknown` from Task 3 on (Task 1–2: `cargo build -p wyrm-schedule --target wasm32-unknown-unknown`).
- After the push, check `gh run list --limit 3`; a red run is fixed before the next task starts.
- Never log secrets, `ptok`, or `~val` values above `trace`. Scheduler logs name schedule, event and target ids and states, never the values written or read.
- Wire enums go through `wyrm_core::wire_enum!`; no `as u8`. Status codes are `wyrm_core::Status` variants (there is no "already exists": use `InvalidParameter` with a message that says the id exists).
- `wyrm-schedule` and the `wasm` build of `wyrm-link-scheduler` must not call `jiff::Timestamp::now()`, `jiff::tz::TimeZone::system()` or anything that reads the OS clock or zone: time comes from `Host::now_us`, zones from the bundled tzdb.
- Instants are `i64` microseconds since the Unix epoch, UTC (`type Micros = i64`). Local wall-clock date-times in definitions are text `YYYY-MM-DDTHH:MM[:SS]` with no offset; text with an offset or `Z` is refused in `add_event`/`edit` (`invalid_parameter`, field named) and converted only on DSA import.
- Constants (one place each, in `links/scheduler/src/limits.rs` unless stated):
  - clock watchdog: one wake at most every `30_000` ms; a wall-clock step is a difference of more than `2_000` ms between wall and expected elapsed time;
  - retry backoff `1_000` ms, ×2, cap `60_000` ms, jitter ±20 %;
  - confirm timeout `10_000` ms after an `ok` reply to `~set`;
  - start-up first-sample wait `2_000` ms;
  - writes in flight at most `50` (the host allows 100);
  - commands per event at most `800` (the host allows 1 000);
  - node budget `9_500` (the host bounds 10 000; the root and its two actions are outside it);
  - subscriptions at most `1_000` (the host bound); targets with `read_back`/`feedback` share one subscription per key;
  - next-transition horizon `366` days (in `wyrm-schedule`);
  - `COUNT` at most `10_000`; `INTERVAL` 1 … `1_000`; at most `100` events per schedule and `20` targets per schedule;
  - number tolerance default `1e-6`, relative (absolute when the expected value is 0).
- Store keys: `index` (CBOR array of schedule ids; the store has no key listing), `s/<schedule>` (definition, CBOR of the export map), `o/<schedule>/<target>` (last outcome). Embedded store `store_mb = 64`; the package capability `store_mb = 16`.

## Rulings (gaps between ADR 0022/0023 and the code; the owner checks these)

1. **Tree shape (node budget).** ADR 0022's tree needs 9+ nodes per schedule; the host caps a link at 10 000 nodes, so 1 000 schedules (the ADR benchmark) do not fit. The schedule node's own value is `current`; `source`, `tz`, `next_time`, `next_value` and `display` are its attributes; an event is one node with its fields as attributes; a target is one node whose value is its `state` and whose other fields are attributes. Five nodes per schedule plus one per event and per target. The app counts its nodes and refuses an add over `9_500` with `resource_exhausted`, so the host never fails the event (which would restart the instance).
2. **Audit.** The `Host` API has no audit call and the `wyrm:app@0.1.0` WIT stays frozen. Every write is audited by the target link's responder (`sys/audit/<target link>`, subject `link:<scheduler id>`), as any `~set`. Confirmations and overrides go to the link log at `info` (ids and states only) and to the target node. Task 5 tests the audit record.
3. **Default zone.** A WASM app cannot read the host zone. The app param `default_tz` (IANA name, default `UTC`) is the zone of `add_schedule` without `tz`. Embedded `wyrmd` fills it from the system zone (`jiff::tz::TimeZone::system().iana_name()`, else `UTC`); packages use their params.
4. **Jitter** comes from a hash of `now_us` and the target id (FNV-1a 64), not `rand`.
5. **Host bounds.** The host allows 1 000 commands per event and fails the event (and restarts the instance) when a void call goes over. Every event of the app spends at most `800` commands: `start` declares the root and loads the definitions, then declares and evaluates schedules in batches; a timer burst handles due wakes in batches; leftover work continues on a `0` ms timer. Retries and confirm timeouts go through the one wake heap (no timer per target). Writes beyond 50 in flight wait in a FIFO queue drained by `on_reply`. A target whose subscription the host refuses is refused at `add_target` with `resource_exhausted`. The guide states the caps.
6. **Who may point the scheduler at a device (owner decision; this plan's default).** ADR 0022 wants `add_target` to check the caller's own `write` on the target point from the request's `ptok`. That is not possible: every token carries one grant, narrowed to the request key (`wyrm_client::SigningTokens::scoped`, also used by the gateway), so a request to `…/scheduler/s1/~act/add_target` says nothing about the caller's rights on `…/plc/fan`. Default ruling: **targets are configuration**. `add_target`, a target's `edit`/`enable`/`disable`/`remove`, and `import` (it carries targets) are `config` actions; the responder enforces the level before the app runs. Schedules and events stay at `write`. Who has `config` on the scheduler may point it at any device the scheduler can reach (embedded: all of `wy/<site>/downstream`; packages: their grants). The agent link (capped at `write`) can edit events but cannot add targets. The app does not read `Who` grants; `created_by` = `who.subject`. Alternative for the owner (not in this plan): a signed claim in `ptok` with the caller's full grants (spec 04 change, all SDKs).
7. **Site check.** The app does not know its site. The host refuses a key outside the link's site at `subscribe`/`set` (`BufferHost` site prefix). `add_target` calls `host.subscribe(point)` (and `subscribe(feedback)`) inside the action: an error refuses the target with that error. In `ack` mode it unsubscribes in the same event.
8. **Moments and `state_at`.** `state_at` is the window state only (`Default` or `Event`); it never returns a past moment (ADR: a missed moment is not replayed). `next_transition` returns moments as transitions (`Source::Moment`); the link holds a moment's state until the next transition.
9. **Reserved id and visibility.** `scheduler` joins `RESERVED_NEW`; `Daemon::open` refuses a stored link with it, as with `storage`. It is not in `sys/links` (not a registry link); it is in `publish_overlays` (so history marks show). `wyrmd.json5` `scheduler: { enabled: true, store_mb: 64 }` (both optional) turns it off or sizes it.
10. **Package grants.** The package carries no `requester` grants (a package cannot ask for a root); an operator grants `write` on each target link with `sys/links/<id>/~act/grant` (ADR 0013). Task 6 tests it.

## Review Focus

1. **08:00 burst:** 1 000 schedules with one target each transition in the same instant → all written, none dropped, never more than 50 `set` in flight, no event over 800 commands; the host never fails an event. Test in Task 4.
2. **Clock step backward inside a window** (NTP correction of −5 min at 09:00 in an 08:00–17:00 window) → no write (same state), no transition missed afterwards, the 17:00 end still fires. Test in Task 3.
3. **Restart after a manual override inside the same window** → the overridden target is not written again; a target whose state changed while down is written. Test in Task 4.
4. **A caller with `write` but not `config` on the scheduler** (a gateway role with `write` on `downstream/scheduler/**`, or the agent) tries `add_target`, a target `edit` or an `import` with targets → `permission_denied` from the responder; schedules and events still work for that caller. Test in Task 5 (e2e).
5. **Budgets reached** (node budget, store full, 20 targets, 100 events) → the action fails with `resource_exhausted` naming the bound; the instance is not restarted; nothing half-saved. Test in Task 3.

---

### Task 1: `wyrm-schedule` model, validation, RRULE subset, import/export

**Files:**
- Create: `crates/wyrm-schedule/Cargo.toml`, `src/lib.rs`, `src/model.rs`, `src/rrule.rs`, `src/convert.rs` (Value ↔ model, Value ↔ JSON), `src/dsa.rs`
- Create: `crates/wyrm-schedule/tests/model.rs`
- Modify: `Cargo.toml` (workspace member, `wyrm-schedule = { path = "crates/wyrm-schedule" }`, `jiff = { version = "0.2.38", default-features = false }`), `.github/workflows/ci.yml` (add `-p wyrm-schedule` to the wasm32 build line)

**Interfaces:**
- Produces (exact names; later tasks use them):
  ```rust
  pub type Micros = i64;
  pub struct Schedule { pub id: String, pub display: String, pub tz: String, pub default: Value,
                        pub enabled: bool, pub events: Vec<Event>, pub next_event: u32 }
  pub struct Event { pub id: String, pub display: String, pub value: Value, pub priority: u8,
                     pub special: bool, pub start: jiff::civil::DateTime, pub end: jiff::civil::DateTime,
                     pub recurrence: Option<Rule> }
  pub enum Freq { Hourly, Daily, Weekly, Monthly, Yearly }
  pub enum RuleEnd { Never, Count(u32), Until(jiff::civil::DateTime) }
  pub struct DaySpec { pub ordinal: Option<i8>, pub day: jiff::civil::Weekday }
  pub struct Rule { pub freq: Freq, pub interval: u32, pub end: RuleEnd, pub by_day: Vec<DaySpec>,
                    pub by_month_day: Vec<i8>, pub by_month: Vec<u8> }
  impl std::str::FromStr for Rule  // "FREQ=WEEKLY;INTERVAL=1;BYDAY=MO,TU;UNTIL=2027-01-01T00:00"
  impl std::fmt::Display for Rule  // canonical: FREQ, INTERVAL, COUNT|UNTIL, BYDAY, BYMONTHDAY, BYMONTH
  pub struct Invalid { pub field: String, pub rule: String }   // Display: "<field>: <rule>"
  pub fn validate(s: &Schedule) -> Result<(), Invalid>;
  pub fn valid_id(id: &str) -> bool;            // a key segment: [A-Za-z0-9_-], 1..=64 bytes
  pub fn parse_local(field: &str, text: &str) -> Result<jiff::civil::DateTime, Invalid>;
  pub fn schedule_to_value(s: &Schedule) -> Value;          // own export map, "format": "wyrm-schedule/1"
  /// The schedule and its `targets` array (`Value::Null` when absent; the link models targets).
  pub fn schedule_from_value(v: &Value) -> Result<(Schedule, Value), Invalid>;
  pub fn value_to_json(v: &Value) -> serde_json::Value;
  pub fn value_from_json(j: &serde_json::Value) -> Value;
  pub fn dsa::import(json: &str, id: &str, tz: &str) -> Result<Schedule, Invalid>;
  pub const FORMAT: &str = "wyrm-schedule/1";
  ```
- Event ids are `e<n>`; `next_event` is the next `n` and never goes down (an id is never reused).

- [ ] **Step 1: Make the crate build for wasm32 first.** `Cargo.toml` deps: `wyrm-core`, `jiff` with features `["std", "tzdb-bundle-always"]`, `serde_json`. Add a stub `lib.rs` that resolves `jiff::tz::TimeZone::get("Europe/Kyiv")` in a test. Run `cargo build -p wyrm-schedule --target wasm32-unknown-unknown` → builds. Run `cargo test -p wyrm-schedule` → the stub test passes. If jiff's bundled tzdb does not build for wasm32, switch to `chrono` + `chrono-tz` and keep the same public types (civil date-time = `chrono::NaiveDateTime`); record the switch in the ledger.

- [ ] **Step 2: Write the failing tests** in `tests/model.rs`:
  - `rrule_round_trips`: each of `FREQ=DAILY;INTERVAL=1`, `FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE,FR`, `FREQ=MONTHLY;INTERVAL=1;BYDAY=-1FR`, `FREQ=MONTHLY;INTERVAL=1;BYMONTHDAY=-1,15`, `FREQ=YEARLY;INTERVAL=1;BYMONTH=3;BYDAY=-1SU`, `FREQ=HOURLY;INTERVAL=4;COUNT=6`, `FREQ=DAILY;INTERVAL=1;UNTIL=2027-03-01T00:00` parses and `to_string()` gives the same text back. Lower case and reordered parts parse to the same canonical text.
  - `rrule_refusals` (each `Err` names the part): `COUNT` with `UNTIL`; `INTERVAL=0`; `INTERVAL=1001`; `COUNT=10001`; `BYDAY=1MO` with `FREQ=WEEKLY` (ordinals only with MONTHLY/YEARLY); `BYMONTHDAY=0`, `32`, `-2`; `BYMONTH=13`; `FREQ=SECONDLY`; an unknown part `WKST=SU`; `UNTIL=2027-03-01T00:00Z`.
  - `validate_refusals`, each `Invalid.field` as given: `id` (empty, `a/b`, 65 bytes); `tz` (`Mars/Base`); `events[0].priority` (10); `events[0].end` (before start); `events[0].end` (a `FREQ=DAILY` window of 25 h: "window longer than its period"); `events[0].end` (`FREQ=WEEKLY;BYDAY=MO,TU` window of 30 h: longer than the shortest gap between its days); `events` (101 events); `events[1].id` (duplicate id); `events[0].id` (`e5` with `next_event` 3: id not below `next_event`).
  - `validate_accepts`: a window 22:00 → 06:00 next day daily; a moment (`start == end`); a 08:00–17:00 weekday window.
  - `export_round_trip`: a schedule with two events, one recurring → `schedule_from_value(&schedule_to_value(&s))?.0 == s`; the map has `"format": "wyrm-schedule/1"`; `value_to_json` then `value_from_json` gives the same `Value`. A map with `"format": "wyrm-schedule/2"` is refused (`format`).
  - `dsa_import`: this fixture (a DSA localschedule 2.0.4 export, `Schedule.toJson`):
    ```json
    {"name":"Lobby","value":false,"events":[
     {"name":"Open","id":"k3Jd9","priority":2,"special":false,"value":true,
      "timeRange":{"sTime":"2026-10-05T08:00:00.000","eTime":"2026-10-05T17:00:00.000",
                   "sDate":"2026-10-05T00:00:00.000","eDate":"2027-10-05T00:00:00.000","freq":2}},
     {"name":"Holiday","id":"x1","priority":1,"special":true,"value":false,
      "timeRange":{"sTime":"2026-12-25T00:00:00.000Z","eTime":"2026-12-25T23:59:00.000Z",
                   "sDate":"2026-12-25T00:00:00.000Z","eDate":"2026-12-25T00:00:00.000Z","freq":0}},
     {"name":"Pulse","id":"m","priority":0,"special":false,"value":1,
      "timeRange":{"sTime":"2026-11-01T06:00:00.000","eTime":"2026-11-01T06:00:00.000",
                   "sDate":"2026-11-01T06:00:00.000","eDate":"2026-11-01T06:00:00.000","freq":0}}]}
    ```
    imported with `id = "lobby"`, `tz = "Europe/Kyiv"` gives: display `Lobby`, default `false`, events `e1` (`Open`, start `2026-10-05T08:00`, end `2026-10-05T17:00`, rule `FREQ=DAILY;INTERVAL=1;UNTIL=2027-10-05T08:00`, priority 2), `e2` (`Holiday`, special, start `2026-12-25T02:00`, end `2026-12-26T01:59` — the `Z` times converted to Kyiv, no rule), `e3` (`Pulse`, a moment at `2026-11-01T06:00`), `next_event` 4. A `freq` of 6 is refused (`events[0].timeRange.freq`).

- [ ] **Step 3: Run the tests** — `cargo test -p wyrm-schedule --test model` → FAIL (types missing).

- [ ] **Step 4: Implement** `model.rs`, `rrule.rs`, `convert.rs`, `dsa.rs`.
  - Period length for "window longer than its period": HOURLY `interval` h; DAILY `interval` d; WEEKLY with several `BYDAY`: the shortest gap between consecutive listed days (wrapping the week), else `7 × interval` d; MONTHLY `28 × interval` d; YEARLY `365 × interval` d. Window length is the civil span `end − start`.
  - DSA mapping: `freq` index 0…5 = Single, Hourly, Daily, Weekly, Monthly, Yearly; Single = no rule. Start = date of `sDate` + time of `sTime`; end = start + (`eTime` − `sTime`); for a rule, `UNTIL` = date of `eDate` + time of `sTime`. A string with `Z` or an offset is converted to `tz` local time; one without is taken as `tz` local. The DSA `id` is dropped; the DSA `name` becomes `display`; ids are `e1…` in file order.
  - The own map keys: `format`, `id`, `display`, `tz`, `default`, `enabled`, `next_event`, `events` (array of maps `id`, `display`, `value`, `priority`, `special`, `start`, `end`, `recurrence` (RRULE text or absent)), `targets` (array; carried as an opaque `Value` here: `Schedule` does not model targets, the link does; `schedule_to_value` writes an empty array, the link puts its targets in).

- [ ] **Step 5: Run** `cargo test -p wyrm-schedule` → PASS; `cargo build -p wyrm-schedule --target wasm32-unknown-unknown` → builds.

- [ ] **Step 6: Commit** `wyrm-schedule: model, validation, RRULE subset, export and DSA import (ADR 0022)`.

---

### Task 2: `wyrm-schedule` evaluation core and benchmarks

**Files:**
- Create: `crates/wyrm-schedule/src/occur.rs`, `src/eval.rs`, `tests/eval.rs`, `benches/eval.rs`
- Modify: `crates/wyrm-schedule/src/lib.rs`, `Cargo.toml` of the crate (`[[bench]] name = "eval" harness = false`, as `crates/wyrm-link-portable/benches/roundtrip.rs`)

**Interfaces:**
- Consumes: Task 1 types.
- Produces:
  ```rust
  pub struct Compiled { /* schedule + resolved jiff::tz::TimeZone + per-event span */ }
  impl Compiled { pub fn new(s: &Schedule) -> Result<Compiled, Invalid>; pub fn schedule(&self) -> &Schedule; }
  pub enum Source { Default, Event { id: String, at: Micros }, Moment { id: String, at: Micros } }
  pub struct State { pub value: Value, pub source: Source }        // PartialEq
  pub struct Occurrence { pub event: String, pub start: Micros, pub end: Micros, pub value: Value,
                          pub priority: u8, pub special: bool }
  pub fn state_at(c: &Compiled, t: Micros) -> State;
  pub fn next_transition(c: &Compiled, t: Micros) -> Option<(Micros, State)>;
  pub fn occurrences(c: &Compiled, from: Micros, to: Micros, limit: usize) -> Vec<Occurrence>;
  pub const HORIZON_DAYS: i64 = 366;
  ```

- [ ] **Step 1: Write the failing tests** in `tests/eval.rs`. Helper `at(tz, "2026-03-29T03:00") -> Micros`. Each test names its case; assert `state_at` values/sources and `next_transition` instants exactly:
  - `daily_window_across_midnight`: 22:00–06:00 daily from 2026-10-01 in UTC → on 2026-10-10 at 23:00 and 05:59 active (source start = the 22:00 of the right day), at 06:00 default; `next_transition` from 12:00 is 22:00 the same day.
  - `hourly_window_across_the_hour`: `FREQ=HOURLY` 10:50–11:10 → active at 12:05 (occurrence 11:50), next transition 12:10.
  - `weekly_wrap`: `FREQ=WEEKLY;BYDAY=SU` 20:00 → Monday 04:00 → active Monday 03:00, not Monday 05:00.
  - `day_31_is_skipped`: `FREQ=MONTHLY;BYMONTHDAY=31` 09:00–10:00 from 2027-01-31 → occurrences in Jan–Jun 2027: Jan 31, Mar 31, May 31 only (no rollover).
  - `last_day_of_month`: `BYMONTHDAY=-1` → Feb 28 2027, Feb 29 2028.
  - `feb_29_yearly`: `FREQ=YEARLY` from 2028-02-29 → next occurrence 2032-02-29.
  - `byday_ordinals`: `FREQ=MONTHLY;BYDAY=1MO` and `-1FR` → Nov 2026: Mon 2nd, Fri 27th.
  - `three_overlaps`: priorities 0, 3, 3 overlapping → the priority-3 event that started later wins; equal start → the lower event number wins (`e2` before `e10`, numeric order).
  - `priority_zero_is_lowest`: priority 9 beats 0.
  - `special_day_blocks_the_whole_local_day`: a special event 12:00–13:00 on 2026-12-25 in `Europe/Kyiv`, a normal daily 08:00–17:00 → on 2026-12-25 at 09:00 default (the normal event is blocked all day), at 12:30 the special value; on 2026-12-26 09:00 the normal value. `next_transition` from 2026-12-24T16:00 local is 17:00 (window end), then 2026-12-25T12:00.
  - `dst_spring_forward_kyiv`: daily 03:30–05:00 in `Europe/Kyiv`; on 2027-03-28 (gap 03:00→04:00) the start 03:30 does not exist and maps to the first instant after the gap (04:00 local = 01:00 UTC); the end is 05:00 local (02:00 UTC); at 00:45 UTC default, at 01:30 UTC active; on 2027-03-29 the window is 03:30–05:00 local again (00:30–02:00 UTC).
  - `dst_fall_back_kyiv`: daily 03:30–05:00 on 2026-10-25 (03:00–04:00 repeats) → start = the earlier 03:30 (00:30 UTC); length stays wall-clock 03:30–05:00.
  - `dst_new_york`: daily 08:00–17:00 on 2026-03-08 and 2026-11-01 → 08:00 local both days (12:00 / 13:00 UTC); the window keeps 08:00–17:00.
  - `moment_fires_and_is_not_replayed`: moment at 06:00 priority 0 over default → `next_transition` from 05:00 = `(06:00, Moment(e1, 06:00))`; `state_at(06:30)` = default (ruling 8).
  - `moment_loses_to_higher_window`: window priority 1 active 05:00–07:00, moment priority 2 at 06:00 → `next_transition` from 05:30 is 07:00 (the moment does not fire).
  - `no_transition_inside_horizon`: a one-off event in the past → `next_transition` = `None`.
  - `count_ends_rule`: `FREQ=DAILY;COUNT=3` → three occurrences, then default for ever.
  - `occurrences_over_a_year`: weekday 08:00–17:00 → `occurrences(c, 2027-01-01, 2028-01-01, 1000).len() == 261`; `limit` cuts the list.
  - `old_dtstart_is_fast`: `FREQ=HOURLY` from 2000-01-01, `state_at` in 2026 — the test asserts the result and that one call takes under 1 ms (release-insensitive bound: 20 ms in debug).

- [ ] **Step 2: Run** `cargo test -p wyrm-schedule --test eval` → FAIL.

- [ ] **Step 3: Implement** `occur.rs` and `eval.rs` with these rules (they are not all pinned by the tests):
  - **Occurrence generation is in civil (local) time**: walk periods of `freq × interval` from the period that holds `start`; in each period expand `BYMONTH`/`BYMONTHDAY`/`BYDAY` (defaults: the start's month, day of month, weekday); skip dates that do not exist; keep candidates `≥ start`; stop at `COUNT` or `UNTIL` (a candidate start `≤ UNTIL` is kept). Each window end is `local start + span` (civil span, so wall-clock length is kept). Map each local date-time to an instant: in a gap, the instant of the transition (first instant after the gap); in a fold, the earlier instant.
  - **Jump, do not scan from the start**: without `COUNT`, compute the period index of `t` arithmetically (hours, days, weeks, months, years since the first period) and start one period before it (a window may reach into the next period). With `COUNT`, enumerate from the first period (bounded by `COUNT ≤ 10_000`).
  - **Window state at `t`** (`state_at`): local day `D` of `t` in the zone; special day = some special event has an occurrence (window or moment) that intersects `[D 00:00, D+1 00:00)` (both ends mapped to instants). Active = windows with `start ≤ t < end` (moments are never active), only special events on a special day. Winner = minimum of `(rank, -start, event number)` where `rank` is the priority for 1…9 and 10 for 0. No winner → `Default`.
  - **`next_transition(t)`**: merge, in time order, the boundaries after `t` up to `t + HORIZON_DAYS`: every window start and end, every moment, and the start and end of every special day. At each boundary `p`: if a moment at `p` beats every window active at `p` (same ordering; a moment's start is `p`), return `(p, Moment)`; else if `state_at(p) != state_at(t)` (value or source), return `(p, state_at(p))`. Only the boundaries from the lazily generated occurrences are visited; stop at the first change.
  - **`occurrences`**: all events' occurrences with `end > from` and `start < to`, by start, at most `limit`.

- [ ] **Step 4: Run** `cargo test -p wyrm-schedule` → PASS.

- [ ] **Step 5: Benchmarks** in `benches/eval.rs` (same style as `crates/wyrm-link-portable/benches/roundtrip.rs`: plain `main`, `Instant`, p50/p99 printed): `state_at` and `next_transition` for S schedules × E recurring events with S, E ∈ {1, 10, 100, 1000} (skip S·E > 100 000); `Compiled::new` + `state_at` for 1000 schedules × 10 events (cold start); `occurrences` over one year for one schedule of 10 events. Run `cargo bench -p wyrm-schedule --bench eval` and paste the table into the commit message.

- [ ] **Step 6: Commit** `wyrm-schedule: state_at, next_transition, occurrences; DST and calendar fixtures; benches`.

---

### Task 3: The scheduler `App`: tree, schedules and events, store, wake heap, clock watchdog

**Files:**
- Create: `links/scheduler/Cargo.toml` (crate `wyrm-link-scheduler`, `crate-type = ["cdylib", "rlib"]`, features `process` and `wasm` as `examples/links/portable/Cargo.toml`; deps `wyrm-core`, `wyrm-link-api`, `wyrm-schedule`, `serde_json`; optional `wyrm-link-guest`, `wyrm-link-sdk`, `wyrm-link-portable`)
- Create: `links/scheduler/src/lib.rs` (`pub struct Scheduler`, `impl App`), `src/limits.rs`, `src/tree.rs` (node and action meta), `src/wake.rs` (the heap and the watchdog), `src/store.rs` (keys `s/…`, `o/…`)
- Create: `links/scheduler/tests/common/mod.rs` (`SimHost`), `tests/schedules.rs`
- Modify: `Cargo.toml` (member, `wyrm-link-scheduler = { path = "links/scheduler" }`)

**Interfaces:**
- Consumes: Task 1–2 API; `wyrm_link_api::{App, Host, Who, TimerId, buffer::{BufferHost, Services, Command, Limits, Counts}}`.
- Produces:
  - `impl App for Scheduler { const NAME = "scheduler"; … }`; params map: `default_tz` (string, default `"UTC"`); any other key → `invalid_parameter` `params.<k>: unknown`.
  - `SimHost` (tests): wraps a `BufferHost` over a `Services` with a settable wall clock and an in-memory store; `fn event<R>(&mut self, f: impl FnOnce(&mut Scheduler, &mut dyn Host) -> R) -> (R, Vec<Command>)` applies `StorePut`/`StoreDelete`, records `SetTimer` (the last armed `(TimerId, ms)`), records `Subscribe`/`Set`; `fn advance(&mut self, ms: u64)` moves wall time and, when the armed timer is due, calls `on_timer`; `fn step_clock(&mut self, delta_ms: i64)` moves wall time only.
  - Tree (ruling 1), all paths relative to the link root:
    ```
    ""            actions add_schedule {id, display?, tz?, default, enabled?}, import {json, overwrite?} (config)
    <s>           value = current; attrs display, tz, source ("default" | <event id>), next_time (RFC 3339 | null), next_value
                  actions add_event {display?, value, start, end, recurrence?, priority?, special?} -> {id},
                          add_target (Task 4), get_events {timerange, limit?} (read, editor daterange),
                          export -> {json} (read), edit {display?, tz?, default?}, remove
    <s>/default   writable value (saved)
    <s>/enabled   writable bool (saved)
    <s>/events    folder
    <s>/events/<e>  attrs value, start, end, recurrence, priority, special, display; actions edit {…same fields…}, remove
    <s>/targets   folder (Task 4)
    ```
    Actions at `write` except `get_events` and `export` at `read`, and `import`, `add_target` and every action under `targets/` at `config` (ruling 6).

- [ ] **Step 1: Write the failing tests** in `tests/schedules.rs` (all through `SimHost`, wall clock starting 2026-10-29T07:00Z, zone `UTC` unless stated):
  - `add_schedule_declares_and_saves`: `add_schedule {id: "lobby", default: false}` → nodes `lobby`, `lobby/default`, `lobby/enabled`, `lobby/events`, `lobby/targets` declared; store key `s/lobby` present; `current` false, `source` `default`. A second `add_schedule` with id `lobby` → `invalid_parameter` "lobby exists". `id: "a/b"` → `invalid_parameter` naming `id`.
  - `add_event_moves_current_and_arms_the_timer`: event 08:00–17:00 daily, value true → reply `{id: "e1"}`; armed timer ≤ 30 000 ms (watchdog) and the heap's next wake is 08:00; `advance` to 08:00 → `lobby` value true, `source` `e1`, `next_time` `2026-10-29T17:00:00Z`; `advance` to 17:00 → false.
  - `edits_survive_a_restart`: add schedule, two events, `edit` an event, `set lobby/default 3`, `set lobby/enabled false`; build a new `Scheduler::start` over the same store → same tree, same attributes, same `current`. Remove one event → its node removed and store updated; event ids continue (`e3`, never `e2` again).
  - `get_events_lists_occurrences`: `get_events {timerange: "2026-11-02T00:00:00Z/2026-11-09T00:00:00Z"}` for weekday 08:00–17:00 → 5 rows `{start, end, event, value, priority, special}` with RFC 3339 instants; a bad range → `invalid_parameter` naming `timerange`.
  - `export_import_round_trip`: `export` → `{json}`; `import {json}` under a new link state → same schedule; `import` of an existing id without `overwrite` → `invalid_parameter`; with `overwrite: true` → replaced. DSA JSON (the Task 1 fixture) imports with `tz` = `default_tz`.
  - `clock_step_backward_inside_a_window` (Review Focus 2): in a 08:00–17:00 window at 09:00, `step_clock(-300_000)` then `advance(30_000)` → no new `Update` of `current`'s value (same state), the heap re-built; `advance` to 17:00 wall → false.
  - `clock_step_forward_over_a_boundary`: at 16:00, `step_clock(+7_200_000)` then the watchdog fires → `current` false (17:00 passed), `next_time` tomorrow 08:00.
  - `budgets_refuse_cleanly` (Review Focus 5): 100 events then the 101st → `resource_exhausted` "at most 100 events"; node budget: `add_schedule` until 9 500 nodes would be passed → `resource_exhausted`, no `DeclareNode` in that event's commands, no store write; a `Services::store_used` near the quota so `store_put` fails → the action answers `resource_exhausted` and the schedule is not in the tree.
  - `command_budget_at_start`: a store with 1 000 schedules × 10 events → `start` and the `0` ms timer events that follow each return at most 800 commands; after them all 1 000 schedules are in the tree with the right `current`; `BufferHost::finish` never returns an error.
  - `zero_messages_at_idle`: 1000 schedules with one daily event each at different hours; `advance` over a quiet hour with no transition → only watchdog wakes, no `Update` commands.
  - `default_tz_param`: params `{default_tz: "Europe/Kyiv"}` → `add_schedule` without `tz` stores `Europe/Kyiv`; `{default_tz: "Nowhere/X"}` → `start` fails `invalid_parameter` naming `params.default_tz`.

- [ ] **Step 2: Run** `cargo test -p wyrm-link-scheduler` → FAIL.

- [ ] **Step 3: Implement.**
  - Each action validates fully (`wyrm_schedule::validate` on the edited copy) before any `Host` command; then `store_put` of `s/<id>`, then tree commands. A failed `store_put` returns its error and leaves the in-memory model unchanged.
  - Node count is the app's own counter (5 per schedule, 1 per event, 1 per target); check it before declaring.
  - **Wake heap** (`wake.rs`): a `BinaryHeap` of `(Micros, Wake)` with `Wake::Transition(schedule)` (Task 4 adds `Retry(schedule, target)` and `ConfirmTimeout(…)`); stale entries are skipped by a per-schedule generation number. One host timer: armed for `min(earliest − now, 30_000 ms)`; re-armed (cancel then set) whenever the earliest changes. Keep `(armed_at_wall, armed_ms)`; on `on_timer`, if `|now − armed_at_wall − armed_ms| > 2_000 ms` → clock step: re-evaluate every enabled schedule at `now` and rebuild the heap; then pop due entries.
  - **Command budget** (ruling 5): a counter of the commands this event has buffered; work that would pass `800` goes to a pending queue (schedules to declare, due wakes to apply), continued by `host.set_timer(0)`; `start` only declares the root, loads `s/*` keys (the app keeps its own index key `index` with the list of schedule ids, written with each add/remove, since the store has no key listing) and starts the queue.
  - **Transition** (`apply(schedule, state)`): set `current`, `source`, `next_time`, `next_value` (update attrs by re-declaring the node meta), then (Task 4) the targets. `next_transition` from the transition instant decides the next heap entry. An edit, import, `enabled` turned on or `default` changed → evaluate `state_at(now)`; a different state is a transition.
  - A disabled schedule shows `current` as computed but schedules no wakes and writes nothing.

- [ ] **Step 4: Run** `cargo test -p wyrm-link-scheduler` → PASS; the wasm32 build of the crate with `--features wasm` → builds (add the `#[cfg(all(feature = "wasm", target_arch = "wasm32"))] wyrm_link_guest::export!(Scheduler);` line as in the Echo example).

- [ ] **Step 5: Commit** `Scheduler link: schedules and events as a portable App, store, one wake heap, clock watchdog`.

---

### Task 4: Targets: writes, confirmation, retries, override, restart

**Files:**
- Create: `links/scheduler/src/targets.rs`, `links/scheduler/tests/targets.rs`
- Modify: `links/scheduler/src/{lib.rs, tree.rs, wake.rs, store.rs}`

**Interfaces:**
- Consumes: Task 3 `SimHost`, wake heap, `apply`, the command budget.
- Produces:
  - `add_target {point, confirm: "read_back" | "feedback" | "ack", feedback?, map?, feedback_map?, tolerance?} -> {id}` on `<s>`; target ids `t<n>` (per schedule, never reused); actions on `<s>/targets/<t>`: `edit {…same…}`, `enable`, `disable`, `remove` (all `write`).
  - Target node: value = state, one of `pending | writing | confirmed | retrying | override | disabled` (a `wire_enum!`-free string enum in `targets.rs` with `as_str`); attrs `point`, `confirm`, `feedback`, `last_error`, `last_write` (RFC 3339), `attempts`, `created_by`.
  - `map` / `feedback_map` keys are `value_key(&Value) -> String`: `true`/`false`, numbers in shortest decimal (`1`, `0.5`), strings as they are; other values have no key.
  - Outcome record `o/<s>/<t>`: CBOR map `{value, source, outcome: "confirmed" | "override"}`, written only on confirm and on override.

- [ ] **Step 1: Write the failing tests** in `tests/targets.rs` (`SimHost` answers `Set` with `on_reply` when the test says, and delivers samples with `on_value`):
  - `target_actions_are_config` (ruling 6): the declared `ActionMeta` of `add_target`, `import` and the target actions has level `config`; `created_by` = `who.subject` (`""` when absent).
  - `add_target_checks_the_point`: not under `wy/<seg>/downstream/<seg>/…`, with `*`, `~`, or an empty segment → `invalid_parameter` naming `point`; `SimHost` refusing the `subscribe` (outside the site) → that error; a point another schedule already writes → `invalid_parameter` "written by <schedule>/<target>"; the 21st target → `resource_exhausted`.
  - `read_back_confirms`: transition at 08:00 → `Set(point, true)`, state `writing`; `on_reply ok` then a sample `true` → `confirmed`, outcome record stored, `last_write` set, `attempts` 1.
  - `feedback_confirms_on_the_other_point`: write coil `fan`, expect `fan_status` = `feedback_map["true"]` (`1`) → a sample `1` on `fan_status` confirms; a sample on `fan` does not.
  - `ack_confirms_on_reply`: `ok` reply → `confirmed`; no subscription kept.
  - `map_and_tolerance`: `map {"true": 1, "false": 0}` writes `1`; read back `1.0000001` with default tolerance → confirmed; `1.1` → not.
  - `retries_with_backoff`: error replies → `retrying`, re-writes at 1 s, 2 s, 4 s … capped at 60 s, each delay within ±20 %; `last_error` holds the status name and message; a newer transition cancels the retry and writes the new value. A confirm timeout (no matching sample 10 s after `ok`) → retry.
  - `override_is_respected`: after `confirmed`, a sample `false` → `override`, outcome record `override`, no write; the next transition (17:00) writes again.
  - `burst_of_1000` (Review Focus 1): 1 000 schedules with one target each, all transitioning at 08:00 → never more than 50 `Set` without a reply, no event over 800 commands; after replies all 1 000 written and confirmed; no `Host::set` error reaches the app.
  - `restart_keeps_override_and_confirmed` (Review Focus 3): confirmed target A and overridden target B in the 08:00–17:00 window; new `Scheduler::start` at 09:00 over the same store → no `Set` for A or B, A subscribed (override watch), B unsubscribed; a target C whose record is for yesterday's state → after the 2 s first-sample wait with no sample, `Set` written; a target D whose first sample already equals the value → `confirmed` with no `Set`.
  - `disable_and_remove`: `disable` → `disabled`, unsubscribed, no writes; `enable` → a transition for that target; `remove` → node, outcome record and subscription gone; removing the schedule removes all its targets.
  - `import_with_targets_runs_target_checks`: an own-format JSON with a target outside the site (the `SimHost` refuses its `subscribe`), or on a point another schedule writes, or with 21 targets → the import is refused with that error and nothing is saved; a valid one → targets declared, `created_by` = the importer.
  - `target_edit_rechecks_the_point`: `edit {point}` to a point another schedule writes → refused; to a free point → the old subscription dropped, the new one made, a write for the current state.
  - `shared_subscription`: two targets of different schedules with the same feedback key → one `Subscribe`; removing one keeps it.

- [ ] **Step 2: Run** `cargo test -p wyrm-link-scheduler --test targets` → FAIL.

- [ ] **Step 3: Implement** `targets.rs`:
  - Write queue: FIFO of `(schedule, target)`; `pump()` sends while fewer than 50 are in flight; `on_reply` frees a slot and pumps. A queued write for a target that got a newer transition is replaced, not doubled.
  - Equality: numbers within tolerance; `Bool` equals a number 1/0; otherwise `Value` equality.
  - Wakes: `Retry` and `ConfirmTimeout` entries in the Task 3 heap, invalidated by the target's generation number.
  - Logs at `info`: `target <s>/<t> confirmed|override|retrying (<status>)`; no values.

- [ ] **Step 4: Run** `cargo test -p wyrm-link-scheduler` → PASS; wasm32 build → builds.

- [ ] **Step 5: Commit** `Scheduler link: targets with caller rights, write queue, confirmation, retries, override`.

---

### Task 5: The embedded scheduler in `wyrmd`

**Files:**
- Modify: `crates/wyrm-admin/src/control.rs` (`pub const SCHEDULER_LINK: &str = "scheduler"`; `ensure_builtin_keys(id)` creating `wyrm_link_sdk::REQUESTER_KEY` and the store key for `SCHEDULER_LINK` once; `scheduler_limited_key()` in `link_trust()` as `LimitedKey { key, cap: Write, scopes: ["wy/<site>/downstream"], subject: Some("link:scheduler") }`; `publish_overlays` adds `SCHEDULER_LINK`)
- Modify: `crates/wyrm-admin/src/registry.rs` (`RESERVED_NEW` gains `SCHEDULER_LINK`)
- Modify: `crates/wyrmd/src/lib.rs` (config section `scheduler: { enabled: bool = true, store_mb: u32 = 64 }`; `Daemon::open` refuses a stored link `scheduler` as it does `storage` (line ~1269); per router build after `storage`, spawn `Portable<Scheduler>` with `LinkConfig` built like `start_embedded` in `control.rs`: `link_trust()`, `link_secrets(SCHEDULER_LINK)`, `link_data_dir(SCHEDULER_LINK)`, `grants = [("wy/<site>/downstream", Write)]`; `PortableConfig { params: {default_tz: <system zone>}, store_mb, ..Default }`; stop it with the others; process mode `"scheduler" => wyrm_link_sdk::process::run::<Portable<Scheduler>>()`)
- Modify: `crates/wyrmd/Cargo.toml` (`wyrm-link-scheduler`, `jiff` with `tz-system`)
- Test: `crates/wyrmd/tests/e2e.rs` (`embedded_scheduler_drives_a_process_link`)

**Interfaces:**
- Consumes: Task 3–4 `Scheduler`; `Control::{link_trust, link_secrets, link_data_dir}`.
- Produces: `wy/<site>/downstream/scheduler` on every broker with `scheduler.enabled`; `wyrmd link scheduler` runs it as a process link (Task 6).

- [ ] **Step 1: Write the failing e2e test** `embedded_scheduler_drives_a_process_link`: an `Env` with a `mock` link in `mode: "process"` that has a writable point (find the e2e test that `set`s a process mock point and copy its config). With the admin client:
  1. `add_schedule {id: "s1", tz: "UTC", default: 0}` on `wy/<SITE>/downstream/scheduler`.
  2. `add_event {value: 1, start: <now − 1 min, UTC, minutes>, end: <now + 1 h>}`.
  3. `add_target {point: <the mock point>, confirm: "read_back"}`.
  4. Within 15 s: the mock point's `~val` is 1; `targets/t1` value `confirmed`.
  5. `sys/audit/<mock id>` has a record for the point with subject `link:scheduler` (ruling 2).
  6. Through the gateway (use the helpers other e2e tests use): a user whose role has `write` on `wy/{site}/downstream/scheduler/**` only (made with `sys/~act/update_permissions`) → `add_schedule` and `add_event` accepted, `add_target` and `import` refused `permission_denied` (the actions are at `config`, Review Focus 4); a user with the built-in `operator` role (`config` on `downstream/**`) → `add_target` accepted.
  7. `sys/links` `install {id: "scheduler", …}` → refused "reserved".

Use a client with `with_timeout(Duration::from_secs(60))` for installs and the first calls (CI's debug build is slow; see `portable_app_installs_as_wasm`).

- [ ] **Step 2: Run** `cargo test -p wyrmd --all-features --test e2e embedded_scheduler` → FAIL.

- [ ] **Step 3: Implement.** The process mock answers the scheduler's `~set` only if its responder trusts the scheduler key: the `hello` reply's `limited_keys` come from `link_trust()`, so the key must be created before the first link connects (call `ensure_builtin_keys` in `Control` open/attach, before links start).

- [ ] **Step 4: Run** the full wyrmd e2e suite → PASS. Restart the demo (`examples/demo/run.sh`, stop the old run first) and run `target/release/wyr probe --gateway http://127.0.0.1:<port> --site <site>` on central (8445), edge (8444) and plant (8446) → 0 failed; `wyr list wy/edge/downstream/scheduler` shows the root with its two actions.

- [ ] **Step 5: Commit** `wyrmd: the embedded scheduler at downstream/scheduler with its own key (ADR 0022)`.

---

### Task 6: Process and WASM packages; one scenario in three modes

**Files:**
- Create: `links/scheduler/src/bin/wyrm-link-scheduler.rs` (`process::main::<Portable<Scheduler>>()`, as the Echo example's bin)
- Modify: `links/scheduler/Cargo.toml` (`[package.metadata.wyrm-link]` `name = "scheduler"`, `kind = "wasm"`, `features = ["process"]`, `capabilities = { store_mb = 16 }`, no `requester`)
- Modify: `examples/packages/build.sh` (pack `scheduler` (wasm) and `scheduler-process` (`--kind process --name scheduler-process`))
- Modify: `crates/wyrmd/tests/e2e.rs` (generalise `portable_example_component()` to take the package name; add `scheduler_three_modes`)

**Interfaces:**
- Consumes: Task 5 `wyrmd link scheduler`; ADR 0013 `sys/links/<id>/~act/grant`.

- [ ] **Step 1: Write the failing e2e test** `scheduler_three_modes`, modelled on `one_app_three_modes`: the embedded `scheduler`, the WASM package installed as link `sw`, the process package (`driver_package_with(..., "scheduler", Some(json!({"store_mb": 16})))`) installed as `sp`, last (its install rebuilds the router). For each package link, grant `write` on the mock link with `sys/links/<id>/~act/grant` before adding targets. Scenario per link (a `SchedRun` struct compared across modes, as `EchoRun`):
  1. `add_schedule`, `add_event` active now, `add_target` (`read_back`) on its own mock point (one point per mode: one writer per point).
  2. Target `confirmed`, point value written.
  3. `get_events` for the next 24 h → one row.
  4. `export` → `import` under a new id → same `get_events` rows.
  5. `sys/links/<id>` `stop` and `start` (the embedded one: skip) → target still `confirmed`, no new audit record for the point (no second write).
  A package link without the grant → `add_target` refused `permission_denied` naming the point.

  6. (WASM only) A store at the planned size: `import` 200 schedules × 10 events × 1 target into `sw`, `stop`/`start` it → the link status stays `running` (no `restarting`: `start` and each batch fit in `call_ms` 2000 and the fuel bound), all 200 schedules back in the tree within 30 s. If it fails, make the batches smaller (Task 3 command budget) before raising any host limit.

Use a client with `with_timeout(Duration::from_secs(60))` for installs (the component carries the tzdb and is larger than Echo).

- [ ] **Step 2: Run** `cargo test -p wyrmd --all-features --test e2e scheduler_three_modes` → FAIL.

- [ ] **Step 3: Implement** the bin, metadata and build script. `bash examples/packages/build.sh` → the two scheduler zips appear in the demo repository.

- [ ] **Step 4: Run** the full wyrmd e2e suite → PASS; the wasm32 build → builds.

- [ ] **Step 5: Commit** `Scheduler link: process and WASM packages; one scenario in three modes`.

---

### Task 7: Guide, ADR, demo, probe and measurements

**Files:**
- Create: `docs/scheduler.md` (user guide), `links/probe/scenarios/scheduler.json`, `examples/demo/scheduler-load.sh`, `links/scheduler/benches/cold_start.rs`
- Modify: `docs/adr/0022-scheduler-link.md` (status `accepted · 2026-10-29, built`; the tree of ruling 1; rulings 2–10 under "Decision" where each belongs; the measured numbers), `docs/links.md` (a pointer to the guide), `CLAUDE.md` (lines for `crates/wyrm-schedule` and `links/scheduler`), `examples/demo/edge.json5` (point `fan_status: { table: "coil", addr: 3, dtype: "binary", poll_s: 1 }` beside `fan`)

- [ ] **Step 1: Guide** `docs/scheduler.md`: what a schedule, event, priority, special day and moment are; time zones and DST rules (gap, fold, wall-clock length); the RRULE subset with examples; the tree and every action with its params and errors; targets, the three confirm modes, `map`/`feedback_map`, retries, override; who may add a target; caps (100 events, 20 targets per schedule, 50 writes in flight, 1 000 subscriptions, node budget 9 500); DSA import mapping; the three run modes and the grants packages need.

- [ ] **Step 2: Probe scenario** `links/probe/scenarios/scheduler.json` (built-in, as `storage.json`): `require` the scheduler root; `invoke add_schedule` (id `probe_sched`, `cleanup` removes it); `invoke add_event` with a window from now; `value` of `probe_sched` equals the event value `within_ms` 2000; `invoke get_events`; `invoke export`; `removed` after cleanup. Run `wyr probe` on the three demo sites → 0 failed.

- [ ] **Step 3: Cold-start bench** `links/scheduler/benches/cold_start.rs` with `SimHost` (move `SimHost` into the crate behind a `sim` feature if the bench needs it): store with 1 000 schedules × 10 events × 1 target → time of `Scheduler::start` to the last queued write. Run it and note p50.

- [ ] **Step 4: Demo measurements** on edge, with `examples/demo/scheduler-load.sh` (uses `wyr invoke`):
  1. Create 1 000 schedules with one daily event each at minute offsets away from now; subscribe `wy/edge/downstream/scheduler/**` for 60 s with `wyr sub` and count samples → expected 0.
  2. Create 100 moment events one second apart on one mock point; record arrival − scheduled time of each `~val` → p50/p99 (target < 50 ms).
  3. A target on `plc1/line1/ahu1/fan` with `confirm: feedback`, `feedback: …/fan_status` → `confirmed`; `wyr set …/fan false` by hand → target `override`; the next transition writes again.
  4. Remove the load schedules.
  Put the numbers in `docs/scheduler.md` and ADR 0022.

- [ ] **Step 5: Run** the pre-push checks; `wyr probe` on central, edge, plant → 0 failed.

- [ ] **Step 6: Commit** `Scheduler: guide, ADR 0022 accepted with rulings, probe scenario, demo measurements`.
