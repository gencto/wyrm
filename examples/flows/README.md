# Ready-made flows

Each file is a flow definition (spec 06, `dataflows/<id>/~def`) in the JSON form that
`dataflows ▸ deploy` takes as `def`. The block reference is `docs/flow-blocks.md`; how to
write and check a flow is in `.claude/skills/wyrm-flow/SKILL.md`.

The points are those of the mock link (`downstream/mock/p0` … `p3`, numbers in °C,
writable; the action `downstream/mock ▸ reset`), so every file compiles and deploys on a
test site. `crates/wyrm-flow/tests/recipes.rs` checks that, and runs most of them on the
mock. Before you deploy one on a real site, replace the keys with your points.

| File | What it solves | Inputs | What to change |
|---|---|---|---|
| `threshold_alarm.json` | A high alarm with a deadband (hysteresis) and a debounce (raise and clear delays). | `p0`: a temperature. | `high`, `hysteresis`, `delay_s`, `return_delay_s`; `low` for a low alarm. An `alarm` sends `out` only when it changes, so `active` has no value until the first raise. |
| `average_min_max.json` | The average, the highest and the lowest of several points. | `p0`, `p1`, `p2`. | The keys; add a name to `inputs` of the three blocks and an edge per new point. |
| `running_hours.json` | Running hours of a pump (seconds and hours), kept across hot swaps and restarts. | `p0`: here "runs" means above 20. | Use the pump's run feedback; with a bool point, wire it into `clock.in.enabled` and remove `running`. A sample on `clock.reset` sets the count back to 0. |
| `daily_energy.json` | Energy of today in kWh from a power point in kW, back to 0 at local midnight. | `p0`: power in kW. | `time_zone` of `day`; a power in W needs a `scale` with `k: 0.001` first. A gap over 15 min between two samples adds nothing. |
| `rate_of_change.json` | The slope of a value over the last 60 s, in units per minute, and a flag for a fast rise. | `p0`: a level. | `size_s` of `rate`; `k` of `per_min` (60: per minute, 3600: per hour); `high` of `fast`. |
| `unit_conversion.json` | °C to °F, and a 4–20 mA signal to 0–10 bar with a sensor fault flag. | `p0` (°C), `p1` (mA). | `k`/`b`, or the four range fields of `to_bar`, and `min`/`max` of `clamp`. |
| `stale_watchdog.json` | No-data watchdog: `stale` is true when the last sample is older than 30 s; `link_up` from the link's liveliness. | `p0`, the node `downstream/mock`. | `30000` in `expr` (ms); `period_ms` of `tick`; the link key. Nothing is published until the point sent its first sample. |
| `setpoint_schedule.json` | A day and night setpoint (21 from 07:00 to 18:59, else 17) written to a point when the period changes. | The clock; target `p3`. | `time_zone`, the hours in `values`, `then`/`else`, `path`. A deploy writes nothing: run the block's `Run` (`dataflows/<id>/~act/trigger {node: "write"}`) to write the current setpoint at once. |
| `condition_setpoint.json` | Write 1 to a command point when a temperature stays high, write 0 when it is back. | `p0`; target `p3`. | `high`, `hysteresis`, `delay_s`; the values in `on_value`/`off_value`; `path` of both `set` blocks. |
| `alarm_action.json` | Run an action (the action block `invoke`) when an alarm is raised; publish its errors and the last run. | `p0`; action `downstream/mock ▸ reset`. | `path`, `action`, and `args` (`{name: constant}`, a wire on `arg.<name>` replaces one). |
| `edge_counter.json` | Count the rising edges of a digital input, in all and since local midnight. | `p0`: here "on" means above 25. | With a bool point, wire it into `edge.in` and remove `as_bool`; `time_zone` of `day`. |
| `rolling_table.json` | A table of the last 60 samples (at most one per second) and their average. | `p0`. | `ms` of `one_per_s`; `buffer_size` (at most 10 000) or `time_window_s` of `rec`; `method` of `avg`. |
| `status_text.json` | A status line from a value: `Tank 1: 25.0 °C, OK`. | `p0`. | The texts in `line.values`, `format` of `number`, the cases of `state`. |
| `json_fields.json` | Split a JSON text into fields: temperature, status, first alarm, and `parse_error`. | `storage/plant/status_json`: a text point. | The key; `path` of each `get` (`a.b.0`: keys and list indexes). |

## Deploy

1. Copy the file and replace the keys. Raise `version` on every new deploy of the same `id`.
2. Check it on the broker: `wyr flow validate <site> examples/flows/<name>.json`.
3. Deploy it: `wyr --key admin.key flow deploy <site> examples/flows/<name>.json`. Through a
   gateway, use a `wyrm-agent` plan step `{"deploy": "wy/<site>/dataflows", "def": {…}}`.
4. Read the results under `wy/<site>/dataflows/<id>/nodes/<node>`, or open the flow in WYRM
   Studio.

A flow with a `set` or an `invoke` needs `permissions: {maxperm: "write"}`, and the
deployer must hold `write` on every target. No recipe sets `run_on_start`: a deploy, a hot
swap and a restart never run their commands.
