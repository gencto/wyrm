# System

Boards: `System` (clickable: the tabs and the traffic measure switch), `SystemAvail`, `SystemAvailLag`, `SystemAvailNone`, `SystemLog`, `SystemMaint` (canvas row "Details"). The board wins for what is visible; this spec says where every value comes from, what every control calls, and every state.

One rule shapes the whole screen: **it shows only what the broker serves under `sys`**. Nothing is computed by Studio that the broker could contradict, except where marked (Studio-side).

## Regions
- Shell as every screen (top bar, rail with System at the bottom, current).
- **Title row**: `wyrmd on <site>`, a pill, one meta line, and the tab bar on the right (`Overview`, `Availability`, `Log`, `Maintenance`; role `tablist`). The Availability tab carries a dot: amber when the standby is behind or a fork was moved aside, grey when no standby is connected, none when all is well.
- **Main column**: the selected tab.
- **Attention panel** (right, 300–340 px; below 1100 px wide it moves under the main column): `Needs a look · <n>` with one card per item, then `This broker` facts at the bottom. Same on every tab.

## Data
Watch `wy/<site>/sys/*` while the screen is shown (as today), unwatch when hidden.

| Shown | Key under `sys` | Notes |
|---|---|---|
| meta line | `version`, `zenoh_version`, `distribution`, `start_time`, `uptime` | `0.1.0 · Zenoh 1.10.1 · rust (prod) · started 2026-11-04 21:58 UTC · up 6 d 4 h` |
| pill | liveliness of `sys/broker`, `standby_connected` | `Running · active`; see States |
| Links connected | `links_connected`, `links_total` | value `4`, unit `of 5` |
| In quarantine | `quarantined` | |
| Packages | `packages_total` | |
| Upstream / Downstream | `upstream_connected`, `downstream_connected` | unit `connected` |
| Sessions | `sessions` | |
| CPU | `cpu` | `%`, sub `100 = one core` |
| Memory | `memory` | MiB, GiB from 1024 |
| Free disk | `disk_free` | MiB → GiB |
| data_dir | `data_size` | MiB → GiB |
| ACL denials | `acl_denied` | sub `since the router started` |
| Audit records | `audit_records` | |
| Traffic | `{messages,frames,data}_{in,out}_per_second` | Bytes shown as kB/s |
| Availability | `standby_connected`, `standby_lag`, `arbiter_lease_s`, `standby_forks` | |
| Log level | `log_level` (enum `error`…`trace`, writable, config) | |

Every tile shows its key at the top right (`links_connected`, …) in mono 11 px, and the node's `description` attribute as its tooltip. Units come from the node's `unit`; the conversions above are the only ones Studio makes.

## Words
Labels word for word from the board: tiles `Links connected`, `In quarantine`, `Packages`, `Upstream`, `Downstream`, `Sessions`, `CPU`, `Memory`, `Free disk`, `data_dir`, `ACL denials`, `Audit records`; groups `Links and sites`, `Process and disk`; traffic `Router traffic`, measures `Messages`, `Frames`, `Bytes`, legend `in`, `out` with their keys. Availability tiles `Standby connected`, `Lag`, `Arbiter lease`, `Forks moved aside`; section `What the standby holds` with its four rows. Log toolbar `Source`, `Level and more severe`, `Filter`, `Lines`, `every 5 s`, `Get log`; `Copy`, `Save as .log`; `Broker log level`. Maintenance `Disconnected links`, `Device profiles`, `Back up and restore`.

## Controls

### Overview
- A tile with a destination is a link (whole card): Links connected → Links; In quarantine → Links › Quarantine; Packages → Links; Upstream, Downstream → Sites; data_dir → History; ACL denials, Audit records → Access › Audit. Tiles without one are not focusable.
- A tile's sub line names the problem when there is one: `bacnet failed · open Links` (coral) is the first link whose `sys/links/<id>/state` is failed; `field-gw waits · open Quarantine` (amber) is the oldest entry under `sys/quarantine`; `edge · open Sites` names the connected peer when there is one.
- **Traffic** (Studio-side): a ring of samples taken from the watched rates, one per metrics interval, kept while Studio runs (not only while the screen is shown), at most one hour. Before two samples: `Collecting…`. The time axis shows the first and last sample and the latest reconnect of a peer (from the log, if one is in the ring). The measure switch changes both lines and the two figures.

### Availability
- No controls: everything here is set in `wyrmd.json5` on the hosts (ADR 0036). Studio never offers to change it.
- `Open the audit record ›` (lagging state) → Access › Audit filtered to `standby_forked`.
- `Guide: docs/operations.md › Warm standby ›` (no standby) opens the guide on GitHub at the section.

### Log
- `Source`: `broker (all)` and one entry per embedded link (`sys/links/*` with `mode` embedded); a link sends `link: <id>` (param `link`).
- `Level and more severe` → param `level`; `Filter` → `filter`; `Lines` 1–2000 → `lines` (default 200).
- `Get log` → `sys/~act/get_log {lines, level, filter, link}`. `every 5 s` (on by default) repeats it while the tab is shown; any change of the toolbar fetches at once.
- Rows newest first; `ERROR` rows on `#1A1110`, `WARN` on `#16140C`. Wide rows scroll in their box, never the page.
- `Copy` puts the shown lines on the clipboard as text, one per line: `<time> <LEVEL> <target> <message>`. `Save as .log` saves the same text as `wyrm-<site>-<yyyymmdd-hhmm>.log`.
- **Broker log level**: picking a level stages `sys/log_level` in Review and apply (as every write in Studio); it takes effect when applied, without a restart. A link's own level is in Links › the link › Log.

### Maintenance
- **Disconnected links** lists what `clear_conns` would remove, computed from `sys/links/*`: `mode` external, `origin` runtime, `state` not connected. Row: id (mono), `external · CN link:<id>`, `not connected`. The button `Clear <n> disconnected links…` asks first (the confirm repeats the ids and `Their ids are retired and cannot be used again.`), then calls `sys/~act/clear_conns`; the answer is the list of removed ids, shown as a toast. With none: the list says `No disconnected links.` and the button is disabled.
- **Device profiles**: rows from the profiles the admin publishes, `wy/<site>/pub/*` (keys only), with the point count from each `pub/<name>/~meta`. `Put profile…` asks for a name and a file and calls `sys/profiles/~act/put {name, profile}`, where `profile` is the CBOR `ProfileDef` bytes (spec 02); a `.cbor` file is sent as it is, a JSON file is encoded by Studio first (proposed). `Remove` asks, then `sys/profiles/~act/remove {name}`. Both are audited by the broker (`profile_put`, `profile_remove`).
- **Back up and restore**: three command cards (back up with the broker stopped, `verify`, `check`), each with a copy button (copies the code exactly). The commands carry the site's `data_dir` and config path when Studio knows them, else `/var/lib/wyrm` and `/etc/wyrm/wyrmd.json5`. Studio runs none of them.
- The `Elsewhere` line links to Links › Quarantine, Sites, Access, History.

All config-level controls are disabled with the reason when the user's grants do not reach `config` on `sys` (`site.needs('config', sys)`, as today).

## Attention panel
Built from values already watched; one card per item, in this order:
1. standby behind (`standby_lag` > 0 or `standby_forks` > 0) → Availability;
2. each failed link (`sys/links/<id>/state` failed, with its `error`) → Links, that link selected;
3. each quarantine entry → Links › Quarantine;
4. each downstream broker waiting for Authorize → Sites, that site selected;
5. `acl_denied` grown since the screen was last shown → Access › Audit;
6. no standby connected (`standby_connected` = 0) → Availability (grey, last).

Dot colours: coral for failures, amber for waiting or behind, grey for information. Empty: `Nothing needs a look.` under the heading, count 0.

`This broker`: `Site`, `Liveliness` (the token `wy/<site>/sys/broker`, teal while present), `Started`, `Build`.

## States
| State | Shows |
|---|---|
| loading (no `sys` value yet) | tiles with `—`, traffic `Collecting…` |
| no `config` on `sys` | values shown; controls disabled with the reason |
| broker token gone | pill `Unreachable` coral; values greyed, last-known kept; the shell's connection banner takes over |
| Availability, standby following (`SystemAvail`) | teal pair, lag 0, lease `8 s left`, forks 0 |
| Availability, standby behind (`SystemAvailLag`) | dashed amber line, `Standby · behind`, the four tiles amber/coral, the warning banner |
| Availability, none (`SystemAvailNone`) | the empty card with the three host steps |
| `arbiter_lease_s` = 0 with a standby | tile value `—`, sub `no arbiter configured` (proposed) |
| Log empty | `No lines at this level.` |
| `get_log` fails | the broker's message in the log box, `Get log` stays enabled |

The standby itself serves no gateway, so Studio never shows a standby's own view; after a takeover the new active is just `plant` again (the pill and `started` change).

## Checklist
- [ ] Four tabs; the Availability dot follows the three states.
- [ ] Every Overview tile shows its `sys` key and the node description as tooltip; tiles with a destination navigate.
- [ ] Traffic switch Messages / Frames / Bytes, ring kept across tab switches.
- [ ] Availability: three frames match; no control writes anything.
- [ ] Log: source, level, filter, lines, auto-refresh, copy, save; level change goes through Review and apply.
- [ ] Maintenance: the clear list matches `clear_conns`' own rule; confirm before; result toast.
- [ ] Profiles: put from file, remove with confirm.
- [ ] Backup commands copy exactly.
- [ ] Attention panel order and destinations.
- [ ] Goldens: one per frame (`System`, `SystemAvail`, `SystemAvailLag`, `SystemAvailNone`, `SystemLog`, `SystemMaint`).

## Found in the app (2026-11-10)
- One page, no tabs: tiles, a messages-only rate chart, the log and an inspector with "Set log level to …" rows and `Clear Conns`. Split it into the four tabs and the attention panel.
- The inspector shows `allow_all_links` and `enable_quarantine`; they belong to Links › Quarantine (where the board has their switches). Drop them here.
- Tiles do not show their keys, tooltips or destinations; Upstream/Downstream are one tile (`1 / 1`): make two.
- Standby is one tile; it becomes the Availability tab.
- `RetrieveSystemLogAction` has no `link` param and a fixed 300 lines: add `link` and take `lines` from the toolbar (default 200).
- No Copy / Save as .log, no auto-refresh.
- `Clear Conns` confirms without saying which links: show the computed list.
- No profiles section, no backup commands.

## Built (2026-11-10)
Every item above is closed in `studio/system-screen`. Where the broker serves less than this spec asks, the app shows what it has and says so (list: `docs/studio.md` §10, items 14–18):
- **Profiles list**: `pub` has no list through the gateway, so the rows are empty with the broker's answer; `Put profile…` works, `Remove` needs a row.
- **A failed link's `error`**: not served; the card says the state and points at the link's log.
- **Liveliness**: the gateway connection stands in for the token `sys/broker`.
- **Traffic axis**: first and last sample only; the reconnect mark from the log is not drawn.
- **`Open the audit record ›`**: opens Access › Audit unfiltered (`tail` has no filter).
- **The guide link**: copies the GitHub address to the clipboard (the app has no URL opener yet).
- **Backup commands**: always the default paths (the broker serves neither path).
- **(proposed)** `arbiter_lease_s` at or below 3 s reads "renewing late"; a JSON profile is `{extends, type, unit, enum, display, children, cfg, attr}`.

## Not served by the broker (left out on purpose)
Shown on the old board, removed because `sys` has no such value or action: taking a snapshot, exporting the state as JSON5, WAL record counts, the HMAC chain check, restore time, the site CA fingerprint and expiry. Each would need a new `sys` value or action in `wyrm-admin` first (a broker change, its own ADR line), then a line here.
