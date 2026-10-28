# ADR 0022 — Scheduler link: broker-side schedules that drive equipment

**Status:** proposed · 2026-10-28 (owner decisions in this conversation: the link writes to equipment itself, retries until confirmed, respects a manual change until the next transition; confirmation may come from another data path).

## Context
The owner needs a scheduler that controls equipment from the broker when the site has no connection upstream: people (explorer) and AI (the `agent` link, through actions) create schedules; the broker turns devices on and off by them, offline, for months. Dataflows may edit schedules later; that needs other changes and is not part of this work.

The reference is DSA `dslink-dart-localschedule` (2.0.4, analysed 2026-10-28). Kept: a schedule with a default value and events; event priority 1 (highest) … 9, 0 = none; special days that block other events; Add/Edit/Remove/Import/Export; `current`, `next` value and time. Not kept, because they are its defects:
- windows across midnight, the hour or the week wrap break after the first occurrence; day 29–31 and Feb 29 roll over into the next month;
- edits through writable child nodes are not saved; a restart loses them;
- `next` shows the next event start, not the next transition (a return to default is missed);
- timers do not follow wall-clock steps; DST shifts window ends; time zone = host zone, stored times have no offset;
- a 1 Hz countdown node per schedule (N updates per second at idle);
- restart and import are O(n² log n); the whole state file is rewritten on every edit;
- it never writes to equipment (consumers bind its value).

## Goals
1. Correct state at any instant, from the definition alone: after a restart, a power cut or a clock step the link computes "now" and acts; it does not replay missed transitions.
2. Writes to equipment, confirmed, with retries, visible state per target, audit.
3. A manual change after a confirmed write wins until the next transition.
4. An action API people and AI can use safely: validated parameters, stable ids, errors that say what is wrong, a preview of what will happen (`get_events`).
5. Zero messages between transitions at idle; one timer for all schedules.
6. One evaluation core for every way the link runs.

## Non-goals
- iCal/Outlook/Google import or remote calendars (not how schedules arrive).
- Dataflows editing schedules (later, separate change).
- Targets on other sites or under `sys/**` (no upstream needed offline; same rule as flow `set`, owner decision 8).

## Anti-goals (a failure even if it works)
- A missed or wrong transition after a restart, a clock step or a DST change.
- An edit accepted but not on disk.
- Fighting a person who changed a device by hand.
- Load at idle that grows with the number of schedules.

## Decision

### Model (crate `wyrm-schedule`, no I/O, no async)
- **Schedule:** `id` (key segment), `display`, `tz` (IANA name, required; default the broker's zone at creation, stored explicitly), `default` (Value), `events`, `targets`, `enabled`.
- **Event:** `id` (stable, generated `e<n>`, never reused in a schedule), `display`, `value`, `priority` (0–9, integer, validated), `special` (bool), `start` and `end` as **local wall-clock date-times in the schedule's zone** (the first occurrence's window), and `recurrence`.
- **Recurrence:** an RRULE subset — `FREQ` (`HOURLY|DAILY|WEEKLY|MONTHLY|YEARLY`), `INTERVAL` (≥ 1), `COUNT` or `UNTIL` (not both), `BYDAY` (weekdays; with MONTHLY an ordinal, e.g. `1MO`, `-1FR`), `BYMONTHDAY` (1…31, −1 = last), `BYMONTH`. `None` = one-off. DSA's `Single/Hourly/…/Yearly` import as `FREQ` with `INTERVAL=1`. A moment event (DSA "Add Moment Event") is an event with `start == end`: the value is written once at that instant; there is no window and no return to default from it.
- **Occurrence arithmetic is in local wall time, then mapped to UTC:** each occurrence's start and end are computed as local date-times (day 31 in a month without it is skipped, not rolled over; `BYMONTHDAY=-1` gives the last day), then each end of the window is mapped to an instant with the zone's rules. A local time in the spring-forward gap moves to the first instant after the gap; in the fall-back overlap it takes the first (earlier) instant. Windows keep their wall-clock length (08:00–17:00 stays 08:00–17:00 on a DST day). A window may cross midnight or the period boundary.
- **Moment events** obey the same precedence: a moment fires (writes its value) only if no window of higher precedence is active at that instant; after it, `current` keeps the moment's value (`source: Moment(id, t)`) until the next transition. A moment missed while the link was down is not replayed (goal 1); at a start, `state_at` looks back only to the last window change, never to a past moment.
- **Precedence at an instant:** if any special event has an occurrence that touches that local day, only special events count for the whole local day (midnight to midnight in the schedule's zone; this is the DSA promise, which DSA did not keep). Among active events: higher priority wins (1 > 2 > … > 9 > 0); on equal priority, the later-starting occurrence wins; on equal start, the lower event id wins. No active event → `default`. The result is defined for any number of overlaps.
- **Core API:**
  - `state_at(def, t) -> State { value, source: Default | Event(id, occurrence_start) | Moment(id, at) }`
  - `next_transition(def, t) -> Option<(Instant, State)>` — the first instant after `t` where `state_at` changes (an event start, an event end, a day boundary under a special day, a moment).
  - `occurrences(def, from, to, limit) -> Vec<Occurrence>` for the timeline.
  - Bounded work: scanning stops at the horizon of `next_transition` (one year ahead, then "none").

### The link (`links/scheduler`, raw `Link` layer, not the driver framework: it does not poll)
- **One timer** for all schedules: a min-heap of each schedule's next transition; sleep until the earliest; on wake, compute `state_at(now)` for due schedules, write their targets, push their next transition.
- **Wall-clock steps:** besides the heap timer, a 30 s check compares the wall clock with the monotonic clock; a step of more than 2 s (either way) re-evaluates every schedule at "now" and rebuilds the heap. This also covers a host resumed from sleep.
- **What a transition is:** a change of `state_at` (value or source occurrence), an edit or import that changes the current state, `enabled` turned on, or a change of a target. A re-evaluation after a clock step that finds the same state is not a transition.
- **Restart:** load, evaluate every schedule at "now". A target whose stored record says it was confirmed or overridden for this same state (value and source occurrence) is left alone; the others are written (a target already showing the value confirms without a write in `read_back`/`feedback` mode). So a manual change survives a restart inside the same window.
- **Persistence:** `wyrm-state` (WAL + snapshot, as the agent link) in the link's `data_dir`; every accepted edit is in the WAL before the action replies. Per target the WAL also keeps the last outcome `(state it was for, confirmed | override)`, written when it changes. No `data_dir` → the link refuses edits (a scheduler that forgets is worse than none).

### Targets: writes, confirmation, override
- A target is `{ point: <key under wy/<site>/downstream/>, confirm: read_back | feedback <key> | ack, map?: {<schedule value>: <value to write>}, tolerance? }`. Several targets per schedule.
- **On each transition** (and at start), for each enabled target: `~set` the value (mapped if `map`). Confirmation:
  - `read_back`: the next `~val` of the same point equals it (numbers within `tolerance`, default 1e-6 relative);
  - `feedback <key>`: a `~val` of another point equals the expected value (`map` may name the expected feedback value) — for devices whose write register is not the one read back (Modbus coil written, status register read);
  - `ack`: an `ok` reply to the `~set` is enough (no feedback path).
  The link subscribes to the confirm point while a target waits.
- **Retry** until confirmed: exponential backoff 1 s → 60 s cap with jitter; never gives up within a transition; a newer transition cancels it.
- **Override:** after a target is confirmed, a `~val` on its confirm point that differs from the expected value marks it `override` (the person wins); the link does not write it again until the next transition. In `ack` mode there is no feedback, so no override is detected.
- **Per-target state in the tree:** `state` enum `pending | writing | confirmed | retrying | override | disabled`, `last_error`, `last_write` (time), `attempts`.
- **Audit:** every write and every confirmation/override goes to the site audit (`sys/audit/<link>`), as gateway writes do.
- **Who may point a schedule at a device:** `add_target` and a target `edit` check the caller's own rights: the request's `ptok` (gateway users carry their grants in it; admin keys and the agent's key carry theirs) must grant `write` on the target point's `~set`, else `permission_denied` naming the point. A request without verified grants cannot add targets. Without this, `write` on the scheduler would be `write` on every device of the site (the hole ADR 0008 closed for flows with proofs; gateway users cannot send proofs, so proofs are not used here). The target keeps `created_by`; as with flows (decided 2026-10-21), a schedule keeps writing after its author loses rights.
- **One writer per point:** a point may be the target of one schedule only; `add_target` refuses a point another schedule of this link already writes (two schedules would see each other's writes as overrides). A flow that also writes the point is not detected; the guide says not to.
- **Rights of the writes:** the embedded link signs its writes with its own key, created as a link secret by the admin (as the agent's); links trust it as a `LimitedKey` at `write`, scoped to `wy/<site>/downstream`. As a process package it is a requester link (ADR 0013) and needs an operator's Grant Access on the target links (a whole root cannot be asked for by a package).

### Tree and actions (all actions at `write` except where noted; ids are key segments)
```
<link>/
  add_schedule {id, display?, tz?, default, enabled?}
  import {json, overwrite?}            # DSA localschedule JSON or this link's own export
  <schedule>/
    current (value, read-only), source (string: default | <event id>)
    next_time (RFC 3339 instant | null), next_value
    default (writable value; saved), enabled (writable bool; saved), tz (string)
    add_event {display, value, start, end, recurrence?, priority?, special?}   -> {id}
    add_target {point, confirm, feedback?, map?, tolerance?}                   -> {id}
    get_events {timerange, limit?}  (read)   -> rows {start, end, event, value, priority, special}
    export -> {json}; edit {display?, tz?, default?}; remove
    events/<e>/  value, start, end, recurrence, priority, special (read-only values) ; edit {…}, remove
    targets/<t>/ state, last_error, last_write, attempts ; edit {…}, enable, disable, remove
```
- Writable values are only `default` and `enabled`, and they are saved. Event fields change only through `edit` (one validated, saved step; DSA's unsaved writable fields are not repeated).
- Every action validates fully before saving: ids, zone name, RRULE, priority range, `end >= start`, window not longer than its period, targets under `wy/<site>/downstream/`. Errors name the field and the rule.
- `get_events` uses `editor: daterange` (spec 02 0.2.4).

### Run modes (one core, three hosts)
- **Embedded in `wyrmd`** — the default: one fixed instance at `wy/<site>/downstream/scheduler`, started by `Daemon::open` like the storage link (id `scheduler` reserved for new links, `validate_new_link_id`), its key created by the admin; not an operator-created driver instance.
- **Process package** — the same crate with `process::main` and `[package.metadata.wyrm-link]` (ADR 0021); writes need Grant Access.
- **WASM** — a component on a new world `wyrm:link/scheduler` = `point` exports plus one new import `clock { now-us: func() -> u64 }` (no WASI). Each point is one schedule (its definition in the point's cfg); `read` returns `state_at(now)`; the transition latency is the point's poll period. The component cannot write other points (no requester path for WASM links), so in this mode targets are a dataflow's job. The `wyrm-schedule` crate must build for `wasm32-wasip2` (no std time, tz data compiled in).

### Benchmarks and tests (in the crate and on the demo)
- Correctness fixtures: windows across midnight, the hour, the week wrap; day 31 and Feb 29; `BYDAY` ordinals; three or more overlaps; special days; DST spring-forward and fall-back in `Europe/Kyiv` and `America/New_York` (window boundaries, the missing and the repeated hour); clock step forward and backward.
- `cargo bench`: `next_transition` and `state_at` for S schedules × E recurring events (S, E ∈ {1, 10, 100, 1000}); cold start (load + evaluate all); `get_events` over a year.
- On the demo: idle messages per second with 1000 schedules (target 0 between transitions); transition latency p50/p99 (target < 50 ms embedded); restart time to all targets written; a target on the Modbus simulator with `feedback` on another register; override by a manual write.

## Left to the builder
- Crate layout inside `links/scheduler` and `crates/wyrm-schedule`; the tz library (`chrono-tz` or `jiff`), provided it builds for `wasm32-wasip2`.
- The exact JSON of the own export format (it must round-trip and carry the format version).
- Node `$is` names and display names.
- Whether the WASM world is built in this change or as a follow-up step after the embedded and process modes (the core must already build for WASM).

## Consequences
- The link id `scheduler` is reserved like `storage`.
- The WIT gains a `clock` interface in a new world; existing components are unchanged.
- Spec 02 does not change (only existing editors and value types are used).
