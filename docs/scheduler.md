# Scheduler

The scheduler link keeps **schedules** in the broker and writes their values
to equipment at the times they give. It works offline, for months, with no
upstream connection: a restart, a power cut or a clock step does not miss or
repeat a transition. People (explorer) and AI (the `agent` link, through
actions) make the schedules. Decisions: ADR 0022 (the scheduler), ADR 0023
(portable links).

Code: `crates/wyrm-schedule` (the model and the evaluator; no I/O, no clock)
and `links/scheduler` (`wyrm-link-scheduler`, the link as a portable `App`).

## 1. Words

| Word | Meaning |
|---|---|
| **Schedule** | A value that changes with time: a default, a time zone, events and targets. Its value now is `<s>/current`. |
| **Default** | The value when no event is active. |
| **Event** | A value for a time: a **window** (`start` < `end`) or a **moment** (`start` = `end`), once or with a recurrence. |
| **Window** | The event's value counts from `start` up to `end`; at `end` the next value takes over. |
| **Moment** | The event's value is written once, at that instant. It has no end and no return to default: the schedule keeps the moment's value until its next transition. |
| **Priority** | 1 (highest) to 9; 0 = none, the lowest. Decides between events active at the same time (section 6). |
| **Special day** | A local day (midnight to midnight in the schedule's zone) that an occurrence of a **special** event touches. On that day only special events count. |
| **Transition** | A change of the schedule's state: its value or the occurrence it comes from. Each transition writes the targets. |
| **Target** | A point the schedule writes on each transition, with a way to confirm the write (section 9). |

## 2. Where it runs

One source runs in three modes (ADR 0023). They behave the same.

| Mode | Where | How you get it |
|---|---|---|
| Embedded (the default) | `wy/<site>/downstream/scheduler` | Every `wyrmd` runs it. `wyrmd.json5` `scheduler: { enabled: true, store_mb: 64 }` (both optional) turns it off or sizes its store (1–64 MiB). |
| WASM package | `wy/<site>/downstream/<id>` | Package `scheduler` (a component), *Install Link ▸ from Repository / Zip / Url*. Store 16 MiB (`capabilities`). |
| Process package | `wy/<site>/downstream/<id>` | Package `scheduler-process`, the same app as a supervised process. Store 16 MiB. |

`examples/packages/build.sh` builds both packages
(`wyr link pack --manifest-path links/scheduler/Cargo.toml`, the second
with `--kind process --name scheduler-process`).

- The id `scheduler` belongs to the embedded instance. A new link cannot
  take it, and `wyrmd` refuses to start with a stored link of that id (as
  with `storage`). The embedded scheduler is not in `sys/links`.
- **Default zone.** The param `default_tz` (an IANA name, default `UTC`) is
  the zone of a schedule added without `tz` and of a DSA import. The
  embedded scheduler takes the system zone (`UTC` when the system zone has
  no IANA name). A package uses its param: add `default_tz` to the link's
  params, beside its capabilities, with the link's `update` (`sys/links/<id>`
  or `wyr update`). An update replaces the params: give the others again,
  as `sys/links/<id>` ▸ History shows them. For the WASM package:
  `update {params: {net: "", store_mb: 16, memory_mb: 64, call_ms: 2000,
  component: "scheduler", default_tz: "Europe/Kyiv"}}` (the process package
  has no `component`). Without `store_mb` the store falls to 1 MiB.
- **Without its keys.** The embedded scheduler signs its writes with keys
  the admin keeps as link secrets. When the admin cannot save them (a full
  or read-only disk), `wyrmd` logs it at `error` and runs without the
  scheduler; the next router rebuild or restart tries again.
- **Grants of a package.** A package has no grants of its own. Before a
  package scheduler can write a point, give it `write` on that point's link:
  `sys/links/<id>` ▸ Grant Access `{path: wy/<site>/downstream/<link>,
  level: write}` (ADR 0013). A running process link restarts to get the new
  grant; a WASM link gets it with the router rebuild. Without the grant,
  `add_target` fails with `permission_denied` (no message).

## 3. Make a schedule

In the explorer, open `wy/<site>/downstream/scheduler`.

1. ▸ **Add Schedule**: Id `lobby`, Default `false`, Time Zone
   `Europe/Kyiv` (empty: `default_tz`).
2. Open `lobby` ▸ **Add Event**: Value `true`, Start `2026-11-02T08:00`,
   End `2026-11-02T17:00`, Recurrence `FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR`.
   The result is the event's id, `e1`.
3. `lobby` ▸ **Add Target**: Point
   `wy/<site>/downstream/modbus/line1/ahu1/fan`, Confirm `read_back`.
   This needs `config` (section 10). The target writes the state now at once.
4. `lobby/current` shows `true` from 08:00 to 17:00 on weekdays, else
   `false`. `lobby` ▸ **Get Events** with a Timerange shows the
   occurrences ahead.

The same through `wyrm-client` or `wyr probe`: `invoke
wy/<site>/downstream/scheduler add_schedule {id, default, tz}`, and so on
(section 8).

## 4. Time

- **Local times.** `start`, `end` and `UNTIL` are local wall-clock times in
  the schedule's zone: `YYYY-MM-DDTHH:MM` or `YYYY-MM-DDTHH:MM:SS`, no offset.
  Text with an offset or `Z` is refused (`invalid_parameter`, field named).
  Only a DSA import converts instants with an offset.
- **Zones** are IANA names (`Europe/Kyiv`, `America/New_York`, `UTC`) from
  the time zone database bundled in the link: a WASM scheduler never reads
  the host's zone. A native build may use the host's newer database.
- **Occurrences are local.** Each occurrence's start and end are computed as
  local date-times, then mapped to instants with the zone's rules:

| Case | What happens |
|---|---|
| A local time in the spring-forward gap (02:30 on the night 02:00 → 03:00) | It moves to the first instant after the gap (03:00). |
| A local time in the fall-back overlap (the hour that comes twice) | It takes the first (earlier) instant. |
| A window on a DST day | It keeps its wall-clock length: 08:00–17:00 stays 08:00–17:00 (8 or 10 hours of real time for a window across the change). |
| Day 29–31 in a month without it, Feb 29 in another year | That occurrence is skipped, never rolled into the next month. |
| A window across midnight, the hour or the week | Allowed; every occurrence is the same window. |

- Instants in the tree and in `get_events` are RFC 3339 UTC
  (`2026-11-02T06:00:00Z`).

## 5. Recurrence (RRULE subset)

`recurrence` is RRULE text: parts `NAME=VALUE` joined by `;`. Empty means
once. The rule walks periods of `FREQ × INTERVAL` from the event's first
window (`start`, `end`).

| Part | Values |
|---|---|
| `FREQ` | `HOURLY`, `DAILY`, `WEEKLY`, `MONTHLY`, `YEARLY` (required) |
| `INTERVAL` | 1 to 1 000 (default 1) |
| `COUNT` | 1 to 10 000 occurrences, or |
| `UNTIL` | a local time: the last occurrence starts at or before it (not with `COUNT`) |
| `BYDAY` | `MO,TU,…,SU`; with `MONTHLY` and `YEARLY` an ordinal in the month, 1 to 5 or -1 to -5: `1MO` (first Monday), `-1FR` (last Friday) |
| `BYMONTHDAY` | 1 to 31, or `-1` (the last day of the month) |
| `BYMONTH` | 1 to 12 |

How the `BY…` parts act:

| FREQ | `BYDAY` | `BYMONTHDAY` | `BYMONTH` |
|---|---|---|---|
| `HOURLY`, `DAILY` | filter (no ordinals) | filter | filter |
| `WEEKLY` | the days in each week (Monday first) | filter | filter |
| `MONTHLY` | the days in each month | the days in each month; with `BYDAY` both must match | filter |
| `YEARLY` | the days in each month of the year | the days in each month | the months (default: the start's month) |

Examples:

| Recurrence | Occurs |
|---|---|
| `FREQ=DAILY` | every day |
| `FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR` | weekdays |
| `FREQ=WEEKLY;INTERVAL=2;BYDAY=SA` | every second Saturday |
| `FREQ=HOURLY;INTERVAL=3` | every 3 hours from the start |
| `FREQ=MONTHLY;BYMONTHDAY=1,15,-1` | the 1st, the 15th and the last day of each month |
| `FREQ=MONTHLY;BYDAY=-1FR` | the last Friday of each month |
| `FREQ=YEARLY;BYMONTH=12;BYMONTHDAY=25` | December 25 |
| `FREQ=DAILY;COUNT=10` | the next 10 days |
| `FREQ=DAILY;UNTIL=2026-12-31T23:59` | every day up to the end of 2026 |
| `FREQ=DAILY;BYMONTH=6,7,8` | every day in summer |

Checks: a window must not be longer than its period (the shortest gap
between two occurrences; `WEEKLY;BYDAY=MO,TU` gives one day), `end` must not
be before `start`, `UNTIL` not before `start`, a part only once.

## 6. Which value wins

At any instant:

1. On a special day only special events count, for the whole local day.
2. Among the active windows, the highest priority wins (1 > 2 > … > 9 > 0).
3. On equal priority, the occurrence that started later wins.
4. On an equal start, the lower event id wins (`e2` before `e10`).
5. No active window: `default`.

The rules hold for any number of overlaps, also between occurrences of one
event.

**Moments** follow the same rules: a moment writes its value only if no
window that would beat it is active at its instant. After it the schedule
keeps the moment's value (`source` = its id) until its next transition, also
across a restart. A moment missed while the link was down is not written
later (section 11).

## 7. The tree

Paths under the link root (`wy/<site>/downstream/scheduler`):

| Path | Value | Attributes |
|---|---|---|
| `<s>` | folder | `display`, `tz`, `source` (`default` or the event id), `next_time` (RFC 3339 or null), `next_value` |
| `<s>/current` | the schedule's value now (read-only) | |
| `<s>/default` | writable value; saved | |
| `<s>/enabled` | writable bool; saved | |
| `<s>/events/<e>` | folder | `display`, `value`, `start`, `end`, `recurrence`, `priority`, `special` |
| `<s>/targets/<t>` | the target's state (text) | `point`, `confirm`, `feedback`, `last_error`, `last_write`, `attempts`, `created_by` |

- `next_time` and `next_value` are the next **transition** (an event start,
  an event end, a day under a special day, a moment), up to 366 days ahead;
  null when nothing changes in that time or the schedule is off. An enabled
  schedule with nothing in that time is evaluated again 365 days on, so an
  event further ahead still fires, with no edit or restart.
- `enabled` off: the schedule shows its value but wakes and writes nothing.
  Turned on, it is a transition: every target is written.
- Writing `default` changes the definition (saved at once); a different
  state now is a transition.
- The tree publishes only on a change: at idle, between transitions, the
  link sends nothing.

## 8. Actions

Levels: `read` < `write` < `config` (section 10). Every action checks all
its fields before it saves anything; the change is on disk before the
action answers.

| Node | Action | Level | Params | Result |
|---|---|---|---|---|
| root | `add_schedule` | write | `id` (required), `display`, `tz`, `default` (required), `enabled` (default true) | — |
| root | `import` | config | `json` (required), `id`, `overwrite` | `{id}` |
| `<s>` | `add_event` | write | `value`, `start`, `end` (required), `display`, `recurrence`, `priority` (default 0), `special` (default false) | `{id}` (`e<n>`) |
| `<s>` | `get_events` | read | `timerange` (required), `limit` (1 000, at most 5 000) | rows `{start, end, event, value, priority, special}` |
| `<s>` | `export` | read | — | `{json}` |
| `<s>` | `edit` | write | `display`, `tz`, `default` | — |
| `<s>` | `remove` | write | — (refused while it has targets: remove them first, at `config`) | — |
| `<s>` | `add_target` | config | `point`, `confirm` (required), `feedback`, `map`, `feedback_map`, `tolerance` | `{id}` (`t<n>`) |
| `<s>/events/<e>` | `edit` | write | the fields of `add_event`; absent or null keeps a field; an empty `recurrence` makes it once | — |
| `<s>/events/<e>` | `remove` | write | — | — |
| `<s>/targets/<t>` | `edit` | config | the fields of `add_target`; absent keeps a field | — |
| `<s>/targets/<t>` | `enable`, `disable`, `remove` | config | — | — |

- **Ids.** A schedule id is 1 to 64 of `A-Z a-z 0-9 _ -`. Event ids `e<n>`
  and target ids `t<n>` come from the link and are never used again in that
  schedule.
- **`get_events`** `timerange` is `<from>/<to>` (or `<from>..<to>`) in
  RFC 3339; a date alone is its midnight UTC. The rows are every event's
  occurrences that touch the range, by start, precedence not applied (a
  timeline). A moment exactly at `from` is in.
- **`confirm`** is an enum: an action takes the index of the choice (0
  `read_back`, 1 `feedback`, 2 `ack`; the explorer sends it); an import
  JSON takes the text.
- **`map`** and **`feedback_map`** are JSON object text (or a map).
- **Edits that change the state now** (an event added, edited or removed, a
  new `default` or `tz`) are a transition. An edit that leaves the state as
  it was writes nothing.

Errors (the status, then `<field>: <rule>`):

| Status | When |
|---|---|
| `invalid_parameter` | A field is missing or wrong: `end: end is before start`, `recurrence: COUNT: must be 1 to 10000`, `tz: unknown IANA time zone "Kyiv"`, `id: lobby exists`, `point: … is written by lobby/t1`, `default: a number must be finite (no NaN or infinity)` (also an event `value`, `map`, `feedback_map`). A schedule `remove` while it has targets: `lobby has 1 targets: remove its targets first`. |
| `resource_exhausted` | A cap (section 13), named: `lobby: at most 100 events per schedule`, `at most 9500 nodes in the scheduler (9496 used)`. Also a full store. Nothing is saved or declared. |
| `not_found` | No such schedule, event or target. |
| `busy` | `import`, `add_target`, a target's `edit`, and `enable` of a disabled target, while the link still loads its schedules after a start (`N schedules are still loading`): they check one writer per point against every schedule. Try again. |
| `not_supported` | No such action on that node. |
| `permission_denied` | The caller's level is too low, or a package scheduler has no grant on the target's link. No message (spec 04). |

## 9. Targets

A target is `{point, confirm, feedback?, map?, feedback_map?, tolerance?}`:
the point is `wy/<site>/downstream/<link>/<path>` on this site (no `*`, `~`
or empty segment; never `sys/**` or another site).

On each transition (and when a target is added, edited or enabled) the link
writes the schedule value to the point with `~set`, mapped by `map` when it
has an entry. Then it confirms the write:

| Confirm | Confirmed when |
|---|---|
| `read_back` | the point's value equals what was written |
| `feedback` | the `feedback` point's value equals the expected value (`feedback_map[value]`, else the written value). For devices whose write register is not the one read back: a Modbus coil written, a status register read. |
| `ack` | the target link answers `ok` |

- **Equal** means: numbers within `tolerance` (default 1e-6, relative;
  absolute when the expected value is 0); `true`/`false` and 1/0 are equal;
  other values exactly.
- A value with quality `uncertain` or `bad` (a device offline) confirms
  nothing, and the link forgets the key's last value: a later `ok` does not
  confirm on a value from before it.
- **`map` keys** are the schedule value as text: `true`, `false`, a number
  in its shortest form (`1`, `0.5`), text as it is. Example:
  `{"true": 1, "false": 0}` writes 1 for `true`. A value without an entry is
  written as it is.
- A matching value counts while the write waits for its reply or after the
  `ok`. Links publish a value only when it changes, so a point that already
  shows the value confirms on the `ok`. No matching value 10 s after the
  `ok`: the write failed.
- **Retries.** A failed or refused write is tried again after 1 s, then
  2 s, 4 s … up to 60 s, each ±20 %. It never gives up within a transition;
  the next transition replaces it.
- **Override.** After a target is confirmed, a different value on its
  confirm point marks it `override`: a person changed the device by hand and
  wins. The link does not write it again until the next transition. In
  `ack` mode nothing reads the point back, so no override is seen.
- **One writer per point.** A point is the target of one schedule of this
  link only (`point: … is written by <s>/<t>`). A flow that writes the same
  point is not detected: do not do that.
- **The write queue.** At most 50 writes wait for a reply at a time; the
  others wait in order. A burst (1 000 schedules at 08:00) is written in
  full, 50 at a time.
- **Subscriptions.** A target holds a subscription on its confirm key while
  it is enabled, not `override` and not `ack`. Targets that confirm on the
  same key share one.

The target node's value is its state:

| State | Meaning |
|---|---|
| `pending` | waiting to write (in the queue, or waiting for a first sample at start) |
| `writing` | written, waiting for the reply and the confirmation |
| `confirmed` | the point shows the value |
| `retrying` | the write failed; `last_error` says why, `attempts` counts |
| `override` | changed by hand after it was confirmed |
| `disabled` | the target is off |

**Audit.** Every write is a `~set` and the target link audits it as any
other: `sys/audit/<target link>` with the subject `link:<scheduler id>`
(`link:scheduler` for the embedded one). Confirmations and overrides go to
the link log at `info` (ids and states only, never values) and to the
target node.

## 10. Who may do what

| Level on the scheduler | Allows |
|---|---|
| `read` | see the tree, `get_events`, `export` |
| `write` | schedules and events: `add_schedule`, `add_event`, `edit`, `remove` (a schedule without targets), `default`, `enabled` |
| `config` | targets and import: `add_target`, a target's `edit`/`enable`/`disable`/`remove`, `import` |

**Targets are configuration, within the author's rights.** Adding,
editing and importing targets needs `config` on the scheduler. A target
also writes only what its author may write (ADR 0029, decision 10):

1. The scheduler keeps the caller's own rights (the token's `auth`, spec 04)
   with each target it adds, edits or imports.
2. It refuses a target whose point the caller may not write, or whose
   `feedback` key the caller may not read (`permission_denied`, "outside the
   rights of the target's author").
3. It checks the point again before every write.
4. A token without `auth` (an old client, a flow) cannot define targets.
5. The editor of a target becomes its author: `created_by` and the rights
   are the editor's from then on.
6. The export leaves the rights out. An import takes the importer's.
7. The rights are read as at the gateway: the first grant of the role list
   whose key pattern matches decides (spec 04). Put a narrow grant before a
   wider one (ADR 0031, DQL-2).

УВАГА: a target made before this rule has no stored rights. It writes
nothing and stays `retrying` with "its author's rights are unknown" until
someone with `config` edits it once (an `edit` with no fields is enough).

With the gateway's default roles:

| Role | Can |
|---|---|
| `viewer` | read |
| `operator` | make and edit schedules and events, turn them on and off; not add targets |
| `engineer`, `admin` | all, targets and import too |

- The `agent` link is capped at `write`: it edits schedules and events, it
  cannot add targets.
- Users of an upstream site (ADR 0018) write at `write` on this site:
  schedules and events, not targets.
- A target keeps `created_by` (the subject that added or last edited it)
  and that subject's rights at that time. A schedule keeps writing after its
  author loses rights later (as flows do).
- **The link's own writes.** The embedded scheduler signs its writes with
  its own key (a link secret made by the admin). Links trust that key at
  `write`, only under `wy/<site>/downstream`, only with the subject
  `link:scheduler`. A package scheduler signs with its requester key, up
  to its grants (section 2).
- **Not itself.** The embedded scheduler does not trust its own key, so a
  schedule cannot write the scheduler's own nodes (`<s>/default`,
  `<s>/enabled`) in a loop. The app does not know its own link id, so
  `add_target` accepts such a point; its writes fail with
  `permission_denied` and the target stays `retrying`. Do not do that.
- **Removing a schedule.** `remove` is at `write`, its targets are at
  `config`: a schedule with targets is refused until someone with `config`
  removes them.

## 11. Clock steps and restarts

The link computes the state from the definition alone; it never replays
what it missed.

- **One timer** for all schedules: the earliest next transition. The timer
  is monotonic.
- **Clock watchdog.** The timer fires at least every 30 s. When the wall
  clock and the monotonic time differ by more than 2 s (an NTP step either
  way, a host resumed from sleep), the link evaluates every schedule at
  "now". A schedule whose state is the same is not written. A step back
  inside a window writes nothing, and the window's end still fires.
- **Late work.** A burst is done in batches of at most 800 commands per
  event. Work that goes on more than 30 s late counts as a clock step: the
  link goes to the state now, and moments inside that lag are not written.
- **Restart.** The link loads every schedule and evaluates it at "now".
  For each target:

| Stored record for the target | At start |
|---|---|
| `confirmed` or `override` for this same state (value and occurrence), and no transition since (`valid_until`) | left as it was: no write; a manual change survives a restart inside the same window |
| none, for another state, or past its `valid_until`; `ack` | written |
| none, for another state, or past its `valid_until`; `read_back`/`feedback` | waits 2 s for a first value of its confirm key: a value that already shows the expected one confirms without a write, else it is written |

- **`valid_until`.** A record keeps the instant of the next transition after
  its state (365 days on when there is none). A record past it is stale: the
  link was down across a transition and back, and an override from before
  does not pass for the state now. An edit that moves the next transition
  puts the records again. Records of an older version have no `valid_until`
  and are stale once, at the first start after the upgrade.
- **Held moments.** A moment that fired and is still the schedule's state is
  kept across a restart (store key `h/<s>`, deleted when the next
  transition replaces it): the schedule shows it, and its targets follow the
  rules above. A moment missed while the link was down is still not
  written.
- Records are kept only for `confirmed` and `override`; a target edit,
  disable or remove drops its record.

## 12. Import and export

`export` gives the schedule with its targets as JSON, format
`wyrm-schedule/1`:

```json
{
  "format": "wyrm-schedule/1", "id": "lobby", "display": "Lobby", "tz": "Europe/Kyiv",
  "default": false, "enabled": true, "next_event": 2,
  "events": [{ "id": "e1", "display": "", "value": true, "priority": 0, "special": false,
               "start": "2026-11-02T08:00", "end": "2026-11-02T17:00",
               "recurrence": "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR" }],
  "targets": [{ "id": "t1", "point": "wy/edge/downstream/modbus/line1/ahu1/fan",
                "confirm": "read_back", "enabled": true, "created_by": "user:admin" }],
  "next_target": 2
}
```

`import {json, id?, overwrite?}` (level `config`) takes this format or a
DSA `dslink-dart-localschedule` (2.0.4) export:

- `id` names the new schedule; default: the export's `id` (DSA: its `name`,
  when that is a valid id, else `id` is required).
- A schedule with that id exists: refused, unless `overwrite: true`
  replaces it as a whole (its old targets and records go).
- Own format: every target is checked as by `add_target` (one writer per
  point, the caps, the grants); `created_by` becomes the importer.
- Export and import round-trip: an import of an export gives the same rows
  in `get_events`. Remove `targets` to copy a schedule (each point has one
  writer).

DSA mapping:

| DSA | WYRM |
|---|---|
| `name` | `display` (and the id when `id` is not given) |
| `value` | `default` |
| — | `tz` = the link's `default_tz`; `enabled` = true |
| `events[]` | events `e1`, `e2`, … in file order |
| `events[].name`, `value`, `priority`, `special` | `display`, `value`, `priority`, `special` |
| `timeRange.sDate` + `sTime` | `start` (the date of `sDate`, the time of `sTime`) |
| `timeRange.eTime` − `sTime` | the window length: `end` = `start` + it; equal times = a moment |
| `timeRange.freq` 0 | once |
| `timeRange.freq` 1–5 | `FREQ=HOURLY`, `DAILY`, `WEEKLY`, `MONTHLY`, `YEARLY`, `INTERVAL=1`, `UNTIL` = the date of `eDate` with the time of `sTime` |
| times with `Z` or an offset | converted to the zone; times without one are local |

DSA has no targets: add them after the import.

## 13. Limits

| What | Limit |
|---|---|
| Events per schedule | 100 |
| Targets per schedule | 20 |
| Nodes of the link | 9 500 (6 per schedule, 1 per event, 1 per target): 1 000 schedules with 2 events and 1 target each fit |
| Subscriptions | 1 000 (one per confirm key) |
| Writes waiting for a reply | 50; the rest wait in the queue |
| `COUNT` | 10 000 |
| `INTERVAL` | 1 to 1 000 |
| Next transition | 366 days ahead; with none, evaluated again 365 days on |
| `get_events` | 5 000 rows (1 000 without `limit`) |
| Store | embedded 64 MiB (`scheduler.store_mb`), packages 16 MiB; each schedule, held moment and target record takes at least 4 KiB. Keys at most `1 + 2 × schedules + targets` (8 031 within the node budget), below the host's 10 000 |
| Requests | 50 per second per caller (burst 100), as every link |

## 14. Measurements

Apple M4 Max, release builds.

`cargo bench -p wyrm-schedule --bench eval` (the evaluator, per call):

| Schedules × events | `state_at` p50 | `next_transition` p50 |
|---|---|---|
| any × 1 | 0.21 µs | 0.62–0.67 µs |
| any × 10 | 5.5 µs | 11.6 µs |
| any × 100 | 53.7 µs | 113 µs |

- The evaluator's cold start (`Compiled::new` + `state_at`), 1 000 schedules
  × 10 events: p50 8.96 ms.
- `occurrences` over a year, 10 events (7 198 rows): p50 0.83 ms.
- The worst `COUNT` compile (100 events whose rule never matches, 400
  years each): 17–84 ms.

`cargo bench -p wyrm-link-scheduler --bench cold_start` (the link on
`SimHost`, 1 000 schedules × 2 events × 1 target, 10 rounds, p50 / max, from
the start of `Scheduler::start`):

| Confirm | `start` event | tree complete | last write sent | all confirmed |
|---|---|---|---|---|
| `ack` | 1.71 / 1.94 ms | 26.22 / 29.96 ms | 40.34 / 45.50 ms | 40.85 / 46.03 ms |
| `read_back` | 1.67 / 1.76 ms | 25.84 / 26.53 ms | 44.27 / 45.02 ms | 44.92 / 45.74 ms |

With `read_back` or `feedback`, a real host adds the 2 000 ms first-sample
wait before the writes.

On the demo (`examples/demo/scheduler-load.sh`; Apple M4 Max, demo edge
site, embedded scheduler, release build, 2026-10-29):

| Measurement | Result |
|---|---|
| Samples in 60 s at idle, 1 000 schedules | 0 (target 0); 3 000 stored values at subscribe |
| Making and removing the 1 000 schedules | 47.1 s and 42.8 s (50 requests per second per caller) |
| Transition latency, 100 moments, `current` | p50 16.0 ms, p99 23.7 ms, max 26.7 ms (target < 50 ms) |
| Transition latency, the written mock point (`ack` target) | p50 16.9 ms, p99 24.8 ms, max 27.6 ms |
| `feedback` target on `modbus/line1/ahu1/fan` with `fan_status` | `confirmed` after 390 ms; a write of `false` by hand: `override` after 973 ms; the next transition wrote `true` again: `confirmed` |

WASM package, 200 schedules × 10 events × 1 target: `start` answered in
0.29 s, all 200 back in the tree in 1.7 s (e2e `scheduler_three_modes`).

## 15. Known limits

- An audit record put while the target link reconnects (a router rebuild)
  can be lost: records are sent once.
- `rustls` is pinned to 0.23.45: `zenoh-link-tls` 1.10.1 races its reader
  and writer on newer versions.
- A forward clock step under 30 s while a long burst still runs replays the
  transitions of that span (moments too) instead of skipping them.
- An event `edit` cannot set the value to null (null keeps the old value).
- A definition the link cannot read from its store stays in the index and
  cannot be removed with `remove`.
- A target's `feedback` key may be another target's point; only the
  written points are checked for one writer.
- `permission_denied` has no message: a missing grant shows only the status.

## 16. Try it in the demo

1. Run `examples/demo/run.sh`. Every site (central, edge, plant) has its
   embedded scheduler.
2. Log in to the edge gateway (`http://127.0.0.1:8444`, user `admin`) and
   open `wy/edge/downstream/scheduler`. Make a schedule as in section 3 with
   the target `modbus/line1/ahu1/fan`, Confirm `feedback`, Feedback Point
   `wy/edge/downstream/modbus/line1/ahu1/fan_status`.
3. Write `false` to `fan` by hand: the target turns `override`.
4. `wyr probe --gateway http://127.0.0.1:8444 --site edge scheduler` runs
   the built-in scenario (`links/probe/scenarios/scheduler.json`).
5. `examples/demo/scheduler-load.sh` runs the measurements of section 14 on
   edge and removes what it made (`N=3 MOMENTS=5 IDLE_S=5` for a short run).
