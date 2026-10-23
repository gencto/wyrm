# Backlog: owner remarks for the next iteration

Recorded 2026-10-22 from the owner's review of the demo chain
(`plant → edge → central`) in the Flutter explorer. Each item: what the
owner saw or asked for, what we know of the cause, a proposal, and the
decisions it needs. Numbers follow the owner's list (9 and 10 added the
same day: meta elements `@unit` and `@history`).

## Decided (owner, 2026-10-23)

Order: stage 1 — items 7, 8, 6, 9; stage 2 — items 2, 3, 4; stage 3 — items
10, 5, 1 (each with its ADR).

| Item | Decision |
|---|---|
| 1 | A downstream accepts `write` from above on `down`/`dataflows` always; `config` on `sys` only when that downstream allows it explicitly. |
| 2 | Nodes and site sections lowercase; actions keep readable display names (`Add Device`). |
| 3 | Superseded 2026-10-23 (owner): `sys/upstream` stays (Add Upstream Connection → `sys/upstream/<name>` with its parameters); `sys/downstream` goes; the root sections `upstream` (where this broker connects) and `downstream` (everything that connects to it: links and downstream brokers) show the live connections, under their full names. Downstream brokers come in through link install and quarantine only; no actions on `downstream`. |
| 4 | Rename the key: `flows` → `dataflows` (spec change, before 1.0). |
| 5 | The section is `storage`. |
| 8 | Deauthorize lists links only. How a downstream broker is removed follows item 3 (link install and quarantine). |
| 9 | Spec 02: `unit` (key 2) joins the `view=list` summary. |
| 10 | Broker-held meta overlays (option 1); `attr.history` is an array of keys; existing watches get it automatically. |

Already fixed on the day: the Metrics panel showed
`WyrmException(disconnected): wy/central/down/~meta is not connected` when
`downstream` was selected (commit `bfa3c88`: no `~meta` for a site root or
its `down`).

## 1. Actions on downstream brokers and their links

**Asked:** run actions (and `set`) on downstream brokers and on their links
from the upstream, not only read them.

**Today:** ADR 0007 keeps an upstream read-only: the downstream ACL drops
every `~set`/`~act` query from `broker:<upstream>`, and the gateway refuses
non-read ops on `read_sites`. `sys` actions are closed too (2026-10-22).

**Proposal:** an ADR that reverses "no write across sites" with the same
two layers as on one site:
- ACL: the downstream lets its upstream send `~set`/`~act` queries under
  `wy/<d>/{down,sys,dataflows}/**` (and the sites it relays).
- `ptok`: the downstream trusts the upstream gateway's key (and admin keys)
  as `LimitedKey`s scoped to `wy/<d>/**`, capped by a level the downstream
  chooses (`write` for devices; `config` for `sys` only if allowed), so the
  user's grants on the upstream decide, and the downstream can still refuse.
- Gateway: `read_sites` become `sites` with a per-site level.

**Decide:** which levels a downstream accepts from above (write only, or
config on `sys` too: install links, purge, peers); whether the trust is per
peer in `wyrmd.json5` / `sys/upstream`.

## 2. One form for all node names, lowercase

**Asked:** go through every node of the broker and give the names one form,
lowercase.

**Today:** keys are lowercase, but many nodes carry DSA-style display names
in title case (`WYRM Version`, `Allow All Links`, `Log Level`,
`Rows Written`, `Add Watch Group`), and the explorer shows site sections as
`downstream`/`upstream` while the keys are `down`/`up`.

**Proposal:** an audit of `wyrm-admin` (sys values, peers, links, history,
packages), `wyrm-flow`, the peer reference nodes and the driver framework:
drop display names on nodes (the key is the name), keep display names on
actions and parameters only if the owner wants them (decide), and make the
explorer's section labels the keys or one lowercase set. A test that walks
`sys` and fails on an uppercase node name.

**Decide:** actions and parameters too (`Add Watch Group` → `add watch
group`?), or nodes only.

**Done (2026-10-23):** nodes of the broker carry no display names: `sys`
values and settings, `sys/history` (values, settings, a group's
`logging_type`/`interval`/`buffer_flush_time`, a watch's `enabled`/
`start_date`/`end_date`), a link's `log_level`, a peer's `url`/`enabled`.
Kept: actions and parameters, a link's name given at Authorize, a watch's
point key, a flow's description. e2e `sys_values_and_admission_options`
walks `sys` and fails on a display name or an uppercase key. The section
labels follow item 3 (keys `downstream`/`upstream`).

## 3. No `downstream` node in `sys`

**Asked:** `sys/downstream` should not be in `sys`.

**Today:** the admin declares `sys/downstream` (Add Downstream Broker, the
list of downstream peers) when `peers.listen` is set; `sys/upstream` holds
the upstream peers.

**Proposal:** move downstream peer management to the site section
`wy/<site>/down` itself (as a DSA broker's `/downstream` carries its own
actions): the admin answers `wy/<site>/down/~meta` and
`wy/<site>/down/~act/add_broker` with one extra queryable on exactly those
keys (the links root is listed by liveliness today), and the per-peer
remove/edit actions move to the `down/<d>` reference nodes.

**Decide:** the same for `sys/upstream` (move to `wy/<site>/up`)?

**Owner, 2026-10-23 (replaces the proposal above):** `sys/upstream` stays as
it is (as DSA's `/sys/upstream`); `sys/downstream` goes. The site root has
`upstream` and `downstream` (full names, not `up`/`down`) with the live
connections. A downstream broker is not added by an action: it comes in as
links do, through install and quarantine.

## 4. Rename `flows` to `dataflows`

**Asked:** the section `flows` becomes `dataflows`.

**Today:** the key `wy/<site>/flows/<id>` is normative (spec 01, spec 06),
used by the flow engine, the ACL, the gateway, `wyr flow`, the MCP server,
the skills and the Dart packages.

**Proposal:** a spec change (0.2.0, breaking) `flows` → `dataflows` with the
full procedure (gen.py, fixtures, both SDKs, CHANGELOG), one migration of
stored flow definitions (`data_dir/flows` keeps its name or moves), and a
pass over docs and skills. A label-only change in the explorer is the cheap
alternative.

**Decide:** the key (spec) or only the label.

## 5. A broker storage node

**Asked:** a storage node where people create nodes of any structure and
set their values: the broker's own store, for preprocessing.

**Proposal:** a section `wy/<site>/storage` (name to confirm) served by the
admin, as a DSA broker's `/data`:
- actions `add_folder`, `add_value {name, type, writable, unit, initial}`,
  `remove`, `rename`, `export`/`import` (a subtree as JSON);
- values are settable (`~set`, level `write`), published as `~val`, and
  persist across restarts (a WAL store beside the registry; principle 3
  gets a second documented exception, as the historian);
- flows read and write them (`subscribe`/`set` sinks), so a dataflow can
  keep intermediate results there; the historian can watch them.

**Decide:** the name (`storage`, `data`); limits (nodes, value size); who may
create nodes (`config`) and who may set values (`write`).

## 6. `wy/edge/sys/upstream` from central: "no reply"

**Seen:** expanding `edge ▸ sys ▸ upstream` in the explorer connected to
central showed `WyrmException(timeout): no reply`.

**Found:** reproduced once with the gateway op `list` on
`wy/edge/sys/upstream/central` from central (`no reply`); repeated
`children`, `list` and `meta` on the same keys answer in milliseconds. So
the first query of some keys across the peer link can time out.

**Proposal:** reproduce in an e2e (fresh chain, first `list` of a deep `sys`
node from the upstream, several keys); check whether the first query races
the propagation of the downstream's queryable declaration over QUIC (the
ACL's `declare_queryable` egress), and whether the client should retry
once on a timeout when the owner's liveliness token is present.

**Done (2026-10-23):** not reproduced — e2e `first_queries_across_peers_answer`
(fresh pair, first `children`/`list` of eleven edge keys from central) and
four rounds of sixteen parallel `list`s through the demo's central gateway
all answered within 10 ms. A query a responder drops ends at once in Zenoh
(no reply), so the loss was one dropped query, not a slow one. The client
now asks a `~meta` read twice, each try with half the timeout
(`a_lost_meta_query_is_asked_again`): one lost query costs at most half a
timeout, a node nobody serves fails within one. Writes and actions are not
repeated.

## 7. Config values cannot be changed in Metrics

**Seen:** `Log Level : info` and `Allow All Links : false` cannot be edited.

**Found:** the Metrics panel edits a value only when `writable` is `write`
(`NodeMeta.isWritable`); `sys/log_level`, `sys/allow_all_links`,
`sys/enable_quarantine`, `sys/history/auto_purge`,
`sys/history/disk_space_remaining`, `sys/history/retention_days`, a
watch's `enabled` and a link's `log_level` are `config`. Enum values
(`log_level`) also need a choice list, not a text box.

**Proposal:** edit `write` and `config` values (the responder checks the
level), with a toggle for `bool`, a drop-down for `enum`, a number box for
`number`; show the error message under the row when the broker refuses.

## 8. Deauthorize: a list, not a text box

**Seen:** `sys/quarantine ▸ Deauthorize` shows a text box with
`no external links`.

**Found:** the `link` parameter is an enum of the runtime external links;
with none, the explorer falls back to a text box with the placeholder.

**Proposal:** always a drop-down of what is connected downstream that can
be deauthorized (runtime external links; downstream brokers, if the owner
wants them here too), disabled with "nobody connected" when empty; the
same for every enum parameter with no values.

**Decide:** downstream brokers in the list (Deauthorize = remove the peer
and quarantine its CN)?

## 9. The unit beside the value (explorer only)

**Asked:** when a node has a unit (`@unit`, the DSA name; key 2 `unit` in
spec 02, shown as `$unit` today), the explorer writes it after the value:
`21.5 °C`. Display only; the value itself stays a number.

**Today:** `formatValue` already appends a text unit to numbers, but the
Metrics rows take their meta from `~meta?view=list`, whose summaries carry
no unit (spec 02: keys 0, 1, 4, 10, 11, 12, 13), so no unit shows. A unit
can also be an interned code (`tables.json`) or come from the node's
profile (`is`), and some drivers may put it in `attr.unit`.

**Proposal:**
- Spec 02: add key 2 (`unit`) to the `view=list` summary (one more field
  per row; fixture `meta_view_list` changes; both SDKs), so every list
  shows units without one `~meta` per row.
- Explorer: the unit from, in order, the node's `unit`, its profile's
  `unit`, `attr.unit`; codes resolved through the units table; shown after
  numbers (also in the tree and the history table and chart axis), never
  after enum labels, bools or text.

**Decide:** spec change (unit in `view=list`) or the explorer loads the
full `~meta` of the rows it shows.

**Done (2026-10-23):** spec 02 0.1.11 — `view=list` summaries carry `unit`
(and `writable`, which the SDK already sent); fixture `meta_view_list`; the
SDK summary adds it. The explorer writes the node's unit, else `attr.unit`,
after numbers in Metrics, the tree and the history window (rows and chart
labels). Units come as text: spec 01 names no unit code table yet, and a
profile's unit is not in the list (own fields only).

## 10. `@history`: where a point's history lives, and an icon for it

**Asked:** history can be kept by the broker's historian or by a link
(a requester that records, as `examples/links/requester`). To tie a point
to its history, its meta carries `@history`: the path of the store that
records it. When a node has `@history`, the explorer marks it as recorded
with an icon, and the icon opens the history view of that store.

**Contract (proposal):** `attr.history` = a node key, or an array of keys,
each answering `get <key>/~val?history=…` (spec 01/03) for this point:
- the broker's historian: the watch node `wy/<site>/sys/history/<group>/w<N>`
  (it answers `~val?history=` for its point, as the point key does today);
- a link that records: a node of its own tree that answers the same query
  (one protocol for every store; the explorer needs no store-specific code).

**Who writes `@history`:** the owner of a node's `~meta` is its link; the
historian lives in the broker. Options:
1. **Broker-held meta overlays** (the ADR 0003 TODO for `~set?field=`):
   `~set?field=attr.<name>` stores an overlay in the admin's registry; the
   admin hands each link its overlays (embedded: at start; process: in
   `hello`; changes: a `sys/overlays/<link>` key the SDK follows), and the
   SDK merges them into `~meta` replies and publications. Adding a watch
   sets `attr.history`; removing it clears it. Survives link restarts and
   re-declarations. General: also for `cfg` overrides by people.
2. **A history index next to the tree:** the historian serves
   `<point>/~hist` (a new suffix, spec 01) or a fan-in index; the explorer
   asks it for the points it shows. No change to links, but not "in the
   meta".
3. **Links set it themselves** (a recorder declares `attr.history` on the
   points it records via a requester grant with `config`): cannot cover
   the broker's historian.

Option 1 matches "we write the path into the meta"; it needs an ADR
(overlays are control-plane state the broker owns; links merge, never
own them) and a spec 02 note on `attr.history`.

**Explorer:** a small history icon after the name of a recorded node (tree
and Metrics rows); click → the history window (as View History) on the
`@history` key(s), with a store picker when there are several.

**Decide:** option 1 (overlays) or 2 (index); a single key or an array;
whether watches added before the change get `@history` by a one-time
pass.
