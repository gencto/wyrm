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
| 3, 4 (2026-10-23) | Keys `down` → `downstream`, `up` → `upstream` and `flows` → `dataflows` in one spec 0.2.0 with one migration of stored paths; done before the item 3 admission work. |
| 3 (2026-10-23, revised) | As in DSA: the downstream broker adds its upstream itself and asks the upstream's CA for a `broker:<d>` certificate on a separate enrollment port (`peers.enroll`); a token or `allow_all_links` admits at once, else quarantine → Authorize `{via}`; no install step, no `sys/links` entry. |
| 5 | The section is `storage`. |
| 8 | Deauthorize is a list (no text box). Revised 2026-10-23: as in DSA it lists every runtime connection downstream, downstream brokers included. |
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

**Done (2026-10-24, ADR 0018, spec 01 0.2.3):** as DSA's per-upstream
`Group`, fixed to the decided levels. Every upstream gets `write` on
`downstream`, `dataflows` and `storage` (storage added: DSA's group covers
`/data`); `sys` at `config` only with `allow_config` on that upstream
(`peers.upstream[].allow_config`, `sys/upstream/<u>/allow_config`), at every
hop of a chain. The upstream publishes the keys that sign requests
(`sys/signing_keys`: its admin and gateway keys and those above it); the
downstream follows them over the peer link and trusts them as capped,
scoped keys. The gateway mints tokens for the downstream site with the
user's grants rewritten to it and the subject `user:<name>@<site>`.

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

**Done (2026-10-23, ADR 0015, revised the same day):** `sys/downstream` is
gone; `sys/upstream` stays. The first version (Install Link ▸ Downstream
Broker, brokers in `sys/links`) was not how DSA works (owner); now, as in
DSA, the downstream broker adds its upstream itself (`sys/upstream` ▸ Add
Upstream Connection {url, ca, token}), makes its own key and asks for a
certificate on the upstream's `peers.enroll` port (owner decision: a
separate port); the upstream signs at once for a `sys/tokens` token or with
`allow_all_links` (owner decision: as DSA), else the broker waits in
`sys/quarantine/<d>` with its key's SHA-256 until Authorize `{via}`.
Deauthorize lists downstream brokers too (as DSA's). The QUIC listeners
trust the site's own CA alone, which closes ADR 0007's accepted peer-CA
risk. Found on the way: after a router rebuild the QUIC listener could not
bind (the old runtime drains its UDP socket), so downstream brokers never
came back; a broker start now waits for the port.

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

**Done (2026-10-23), with the key part of item 3:** spec 0.2.0 names the
site sections in full: `wy/<site>/downstream`, `upstream`, `dataflows`
(before: `down`, `up`, `flows`). Fixture `ptok_claims_v1`; both SDKs, the
ACL, the gateway roles, the flow engine (link id `dataflows`), the
historian, `wyr`, MCP, the agent, the skills and the explorer (sections
shown by their keys). Stored keys move by themselves: the registry (link
grants, package requests, history watches; SCHEMA 14) and the gateway's
users (role grants; SCHEMA 4) replay old WAL records under the new names
(`keyspace::renamed`). Not moved: deployed flows (their proofs are signed
for the old keys: deploy them again) and the agent's stored tasks. The
flow store keeps `data_dir/flows`, and `wyr dev` keeps its `flows/` folder
of definition files (directories, not keys).

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

**Done (2026-10-24, ADR 0017):** as a DSA broker's `/data`, not the proposal
above: crate `wyrm-storage`, a link inside `wyrmd` rooted at
`wy/<site>/storage` (spec 01 0.2.2). Root `add_node`, `add_value {name, type,
editor}`, `publish {path, value}`, `export`, `import {data}`; folders also
`delete {recursive}`, `rename`, `duplicate`; values `~set`. Every action needs
`write` (as DSA). One redb file, values flushed once a second; limits 10 000
nodes, 16 levels, 32 KiB per value, 64 MiB in all. Flows may `set`/`invoke` into it, the
historian may watch it (`attr.history` too), upstream sites read it, the
explorer shows it as a site section. The link id `storage` is reserved for
new links.

**Follow-up:** the explorer sends text for every value that is not a number:
a storage value of type `map`, `array` or `binary` can be created but not
set from the UI, and `publish` from the UI always stores text.

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

**Found (2026-11-14):** the e2e failed in CI the same way (`list
wy/edge/sys/links: timeout: no reply` after its `children` answered). Zenoh
1.10 opens a QUIC link with one stream per priority (`multistream=auto`), and
the order between streams is lost. A `list` declares a subscriber on a new
prefix (its key expression goes on the `Control` stream), then queries that
prefix (`DataHigh`): the query can reach the downstream broker first, which
cannot resolve the key and drops it (its ACL interceptor). The two-try read
cannot help: both tries come before the declaration. Peer QUIC endpoints now
use one stream (`?multistream=0`, `wyrmd::single_stream`): a subscriber on a
fresh prefix and a query at once lost 37 and 168 of 200 queries with `auto`,
none with one stream.

**Found (2026-11-15):** after #94 the e2e failed in CI in four of five runs in
a new way: every query to edge, and then every `list`, ended at once (1–7 ms)
with no reply, while edge's liveliness said it was there. The test waited for
edge's token to come back after its rebuild for central's signing keys, and
then for `downstream/edge/connected`, which follows the same token. But a
token is no sign of a route. When a router connects, central's router routes
its liveliness tokens about one routing-tree computation before it routes
queries to it (Zenoh 1.10.1 computes the trees on a worker with a 100 ms
debounce, `TREES_COMPUTATION_DELAY_MS`). In that gap every query to edge ends
with no reply, the two tries of a `~meta` read too. In a Linux container (4
CPUs, six copies at once) a probe right at the token found the gap, 50–100 ms
long, in 13 of 66 runs, and in none of 12 with the debounce set to 1000 ms
(the computations then merge); the test failed 7 of 78 there, 0 of 48 with
the change below (5 of them waited for the gap). A watch of 20 s after the gap saw no later loss, so it is not a second rebuild. macOS
did not show it in 48 runs. The test now starts once a query to edge (on a key
outside the measured ones) answers. Open then: the same gap reaches a live
list of `wy/<d>/downstream` from above (`wyrm-client` `on_child_liveliness`):
when a link's token comes back with its broker, the list reads that link's
`~meta` at once and can get the empty default. `connected` also turns true up
to that gap early.

**Done (2026-11-15):** decided (ADR 0029) and built:
- A read under a link (`wy/<site>/downstream/<link>/…`) that has no reply
  while the link's token is there is sent again after a pause of 25 ms,
  doubled up to 200 ms, until it has an answer, the token is gone
  (`disconnected`), or the timeout is spent (`read_through_gap`). The token
  proves that the responder exists, so a no-reply right after it is the gap.
  Other keys keep two tries: a key that no queryable serves fails at once.
- Zenoh's own `"Timeout"` error reply (a query that timed out) is now no
  reply (`timeout` or `disconnected`, spec 05), not `internal_error`.
- A list of the links root lists a link only with the meta the link
  answered. It reads every link on a task of its own, at once, each read
  bounded by `LIST_READ_WINDOW` (1.5 s; the gap is one tree computation
  with a 100 ms debounce), so a silent link never holds up the first
  `Refreshed` or another link. A link silent through its window is left out
  and read again (1 s, doubled up to 30 s) until it answers or its token
  goes; a link that refuses the read is listed with an empty meta
  (`docs/links.md`, "A link that has just appeared").
- `downstream/<d>/connected` and `upstream/<u>/connected` mean that queries
  reach the peer: the token is there and a probe of the peer's
  `sys/signing_keys` has an answer (`wyrm_admin::peers::follow`).
Tests: `crates/wyrm-client/tests/route_gap.rs` (a fake link that drops or
holds its first queries; the first four fail on the old code, the sibling
test waits 10 s for the snapshot on the first version of this fix),
`wyrm-client` `gap_tests` and the list's pending-read tests and `wyrm-admin`
`peers::tests` on paused time,
e2e `a_live_list_from_above_never_lists_an_empty_link`. Other places that
see a token before a route: the process link `hello` and the standby's polls
retry anyway; `follow_signers` loses one 10 s round; the flow `liveliness`
source and `live_tokens` (`*_connected` counts) report tokens, not routes;
reads of a peer's own sections (`wy/<d>/sys`, `storage`, `dataflows`) have
no link token, so they keep two tries and can still fail once in the gap.

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

**Done (2026-10-23, ADR 0016):** as a DSA broker keeps override attributes
(`@@getHistory`), the admin publishes the attributes it holds for each
link's nodes at `sys/overlays/<link>` and the link's SDK lays them over its
`~meta` (a layer of its own, kept across re-declares; `rev` moves). Today
the only source is the historian: `attr.history` = the watch keys that
record a point, derived from the watches (existing ones included, nothing
new stored). Spec 02 0.2.1: `view=list` key 16 `has_history`. Explorer: a
history mark after a recorded point's name (tree and Metrics); a click
opens its history, with the store shown (a choice when several); a site's
historian is read at the point itself. Not covered: points of downstream
sites (another broker's links).

## 11. Portable links: review items left for later (ADR 0023, 2026-10-29)

Found by the reviews of the portable-links plan; none breaks a scenario
that was tested, all are hardening.

- Runtime: an app's `log` has no rate limit; `set_timer(0)` has no floor
  and there is no per-link event or publish budget; the store fsyncs every
  put (up to 1 000 per event) instead of once per event; `store_after` is
  quadratic over the event's pending puts; a native app that runs past
  `call_ms` is not stopped (only WASM is).
- Lifecycle: `hot_start` is audited `ok` before the new code started; the
  upgrade branch that goes on past a failed link has no test; swaps of
  driver `app` links with `component: <pkg>` are not audited; an upgrade
  keeps each link's params, so changed manifest capabilities do not reach
  existing links (only the audit shows them).
- Install and pack: a world change on upgrade (driver ↔ app) is not
  refused; `wyr link pack --component` always writes `world` (older
  brokers refuse it); `--version`/`--description` are ignored for crate
  packs; the scaffold's wasm32 build runs only in an `#[ignore]` test.
- Tests and benches: the bench's panic hook hides every panic; no
  "commands per second" number (ADR Tests); the e2e WASM mode skips
  silently without the wasm32 target; SDK `set` has no deadline for its
  wait in the SDK command queue (before the portable work, too).

## 12. Known gaps (2026-10-31)

Work that is known and not done. The decisions around it are in ADR 0029.

- Evidence: `wyr bench` on the reference board (4-core ARM64, 2 GB, LAN);
  each protocol link against a real device or a third-party simulator
  (`diagslave` for Modbus); the pentest checklist T1–T12 of
  `docs/security/threats.md`.
- Platform: a TPM-backed `SecretStore`; the cloud profile (OIDC,
  ClickHouse, Postgres); the flow node `llm`; history watches on a whole
  subtree; an MCP `history` tool.
- Framework hooks that links asked for: per-point quality, a
  `poll_period` that sees connection and device params, the sample time
  from the driver, `~meta` from device data, a driver-owned connection
  leaf.
- Portable apps: flows that define DQL queries (they have no `auth`).
- Audit: an acknowledged path so that records put during a reconnect are
  sent again (ADR 0029, decision 7).
- Security review of 2026-10-31 (ADR 0031): one unprivileged uid per
  process link and a `data_dir` split so a link cannot read `ca.key`,
  `secrets.key`, `state.key` (ADM-1); an MCP service identity as a limited
  key instead of an admin key (AI-2); the Low items listed in ADR 0031 as
  "next"; signed repository indexes.

## 13. Broker fault tolerance (ADR 0036, 2026-11-05)

Owner choice: options 1 + 2 + 3 of the assessment in ADR 0036; options 4
(a mesh of two routers for direct readers) and 5 (a Raft cluster) refused
before 1.0. Estimates in person-days, tests included.

- Option 1, supervised restart: done 2026-11-05 (`docs/operations.md`,
  SIGTERM handled, back-off cap 5 s, e2e `broker_restart_rto`). Figures
  from `cargo test --release -p wyrmd --test e2e broker_restart_rto --
  --nocapture`, one embedded and one process mock link, restart at once:

  | Host | start → ready | kill → ready | `wyrmd` without links, RSS |
  |---|---|---|---|
  | reference board (4-core ARM64, 2 GB) | not measured yet | | |
  | x86_64 cloud container, debug build, 2026-11-05 | 1.6 s | 1.6 s | 97 MiB |
- Option 2, endpoint lists: done 2026-11-05 (`WYRM_ENDPOINT` list with
  `WYRM_BROKER_WAIT_S`, `wyr --connect` and FFI lists, Dart
  `WyrmGateway.loginAny`, e2e `link_process_walks_its_endpoints`). Left:
  the supervisor passes only the broker's own endpoint to the links it
  starts (stage A of option 3 adds the standby's); the Flutter explorer's
  login form takes one URL.
- Option 3, warm standby, stage A: done 2026-11-05 (`standby` section,
  `wyrmd keys export|import`, `sys/replication/**`, `wyrm_state::replicate`,
  `wyrmd::standby`, e2e `standby_follows_the_wal` and
  `standby_takes_over_and_the_old_active_demotes`). Left from stage A:
  a test of two active brokers stepping down; the leader reads its whole
  segment files on every poll (an offset index would spare that on a long
  WAL); the Flutter explorer does not show the standby.
- Stage B: done 2026-11-05 as file replication (`sys/replication/files`,
  `file/<offset>/<len>/<name>` in parts of 1 MiB, deletions) plus the
  storage change journal (`wyrm_storage::Store::changes_since`,
  `storage/<epoch>/<since>/<max>`); e2e `standby_follows_stores`. Left:
  files over 64 MiB are skipped; the file list is walked with `stat` every
  5 s (fine up to a few thousand files, an index would be better beyond);
  a package or store file written without a rename could be copied torn
  (every writer in the tree renames today).
- Stage C: done 2026-11-06 (`sys/replication/history/<after>/<max>` from
  the historian's journal, the cursor kept under the sink name
  `standby-<store id>`; e2e `standby_follows_history`). Left: the
  standby's own purge follows the registry's retention only after a
  promotion (it stores what the active sends while it follows).
- Review 2026-11-06, fixed 2026-11-07: a split no longer makes both
  brokers active when one side is cut off from the plant (required
  `standby.witness`, the cut-off active steps down); an ACL rebuild holds
  the standby; no failback (documented as such). The three items left
  open by that review are done 2026-11-08: history-sync cursors are
  carried to the standby in its own journal numbers (a sink sends again at
  most one page after a failover); the losing side of a healed split moves
  aside its WAL records, files and storage tree and reports each set to
  the active (audit `standby_forked`, `sys/standby_forks`); lease arbiters
  (`standby.arbiter`, `wyrmd arbiter issue|serve`) keep a split where both
  hosts reach a witness to one active (`sys/arbiter_lease_s`). Left: the
  arbiter is optional (a pair without one keeps the old gap, with a
  warning); the standby's history marks are in memory, so after a restart
  of the standby a sink further behind than its first new page keeps its
  older cursor; a sink created on the other host during a split may miss
  the former active's own rows that never reached the other host; the
  arbiter is not in the Docker compose files.
- Option 4 (10–15 on top of 3) stays here until reader scaling is asked for.

## 14. Performance baseline (slice P0, 2026-11-19)

The measurements of the performance work. Every later optimization runs
them before and after and puts both figures here. They are benches or
ignored tests: CI does not run them.

How to run (release builds; the first build takes long):

```sh
tool/perf.sh                 # all groups; the table goes to target/perf/table.txt
tool/perf.sh sdk flow broker # one or more groups
tool/perf.sh --existing      # also the older benches (their own output)
```

`perf_d_historian` ended by its watchdog after about 6 min before the fix of
the stall below; it now takes about 30 s.

Every figure prints one line `PERF name=… n=… p50_us=… p95_us=… p99_us=…
per_s=… cpu_pct=… rss_mib=… allocs_op=… bytes_op=… <extra>` (`-` where a
column does not apply). The kit is the dev-only crate `wyrm-bench`: a
counting allocator (calls, frees, bytes; a bench or test installs it as its
`#[global_allocator]`), nearest-rank percentiles, process CPU time and
resident memory. CPU is the whole process (broker, links, the measuring
client) in % of one core. No OS counts `fsync` calls: the audit figure gives
the journal's own count of batches (`batches=`, one `sync_data` of the WAL
each; with `state_anchor_dir` a batch adds the anchor's `sync_all` and its
directory's, twice for a batch of two or more records; the perf tests set no
anchor directory, so the first figure's "3 per record" was 1 per record); on
Linux `/proc/self/io` adds write calls and bytes; on macOS nothing more is
measured.

| Group | Measurement | Audit item | What it covers |
|---|---|---|---|
| sdk | `cargo bench -p wyrm-link-sdk --bench verify` | 3 | one `ptok` check with 1 admin + 1/4/10/30 limited keys: signed by the admin key, by the first and by the last limited key, by a key nobody trusts (refused), a new `sub` in every token, the limited keys in turn with their own `sub` and with a new `sub` each time |
| sdk | `cargo bench -p wyrm-link-sdk --bench tree` | 4, 5, 17 | declare 1k/10k/30k points (time, `~meta` puts and bytes, the parent's apart, bytes kept, peak RSS; pure `NodeTree` with one parent put per child, and through `LinkCtx` over Zenoh; `TREE_DECLARE_ONLY=<n>` runs one size in a process of its own); a wildcard `get` that hits one node of 10k; `view=list` of 1000 children with and without a profile name |
| flow | `cargo test --release -p wyrm-flow --test throughput -- --ignored --nocapture` | 7–10 | `subscribe → (scale, add) × n → publish`, a paced rate ladder on one key and on 1000 keys, default and deep inbox; allocations per hop (9 hops minus 3); 10 000-row tables through `table_sort` ×1/×3 and `table_filter` + `table_aggregate` |
| flow | `cargo test --release -p wyrm-flow --test copies -- --ignored --nocapture` | flow copies | the runtime started directly, no session and no `publish`: samples pushed into the first node's inbox, the end read from the flow's counters; a chain of 10 pure blocks, one output with 16 edges, one `expression` (rhai), a 1000-row table of 3 columns through 3 `table_sort`; median of 7 rounds: samples/s, CPU per sample, allocations and bytes per sample |
| broker | `cargo test --release -p wyrmd --test perf -- --ignored --nocapture --exact <test>` | 1, 2, 12, 13, gateway | an in-process broker with the embedded mock: (a) base rate, (b) a client that subscribes `wy/<site>/downstream/**` in a loop and one `wy/**`, (c) the mock at `trace`, (d) the historian on 10 000 points, (e) 1000 invokes one after another, then 2000 from 50 subjects at once: latency, audit records/s, batches, and how late a 1 ms timer of the broker's runtime fires, (f) 10 gateway WebSocket clients × 1000 points × 10 Hz, (g) a steady pattern consumer of 1000 points × 50 Hz, raw and through the client |
| broker | `cargo test --release -p wyrm-client --test fan_in -- --ignored --nocapture` | pattern consumer | the client's value stream with no session: handler + read on one thread, and 1000 samples every 20 ms read by a task |

Test hooks: `wyrm-admin`'s `testkit` feature (dev only) gives the perf tests
`Control::audit_lsn`, `Control::audit_batches` and `Control::historian`. Slice
P0 changed no product code.

First figures. Machine: Apple M4 Max (14 cores, 36 GB), macOS, release
build, commit `9b95c288`/`c938a6b4` (the measurements only), 2026-11-19. The
machine ran other agents' builds at the same time (load average 7–27): the
figures are **M4 Max, loaded, rough**; the clean baseline is recorded later,
and the reference board (4-core ARM64, 2 GB) is not measured yet.

| Machine | Build | Figure | Value | Date |
|---|---|---|---|---|
| M4 Max, loaded, rough | release | `verify`, admin key (1 verify), any n | p50 22.8 µs, 7 allocs | 2026-11-19 |
| M4 Max, loaded, rough | release | `verify`, last of 4 / 10 / 30 limited keys | p50 111 / 243 / 684 µs (p99 1.27 ms at 30), 14 / 20 / 40 allocs | 2026-11-19 |
| M4 Max, loaded, rough | release | one Ed25519 `verify_strict` | p50 21.6 µs | 2026-11-19 |
| M4 Max, loaded, rough | release | declare 1k / 5k / 10k points (`LinkCtx`) | 85 ms / 2.1 s / 8.9 s; `~meta` 2.3 / 67 / 276 MiB in 2 puts per point; 2.6k / 12.6k / 25k allocs per point | 2026-11-19 |
| M4 Max, load 12–20, rough | release | the same before the fix below, `origin/main` `32cfee50`, 1k / 10k / 30k points, one process per size | 84 ms / 8.4 s / 104 s; `~meta` put 2.3 / 276 / 2735 MiB, all but 0.01 / 0.1 / 0.4 MiB of it the parent's (1 parent put per point); 2.6k / 25k / 75k allocs per point; kept 0.78 / 6.5 / 25.0 MiB; peak RSS 9.0 / 20.9 / 51.6 MiB | 2026-11-20 |
| M4 Max, load 12–18, rough | release | the same after the fix (`perf/declare-on`) | 2.8 ms / 29 ms / 89 ms (2.0 µs per point at every size); `~meta` put 0.07 / 1.1 / 4.1 MiB in 1 put per point + 43 / 82 / 102 parent puts in all; 50 / 55 / 57 allocs per point; kept 0.44 / 4.5 / 13.6 MiB; peak RSS 7.7 / 13.4 / 26.2 MiB | 2026-11-20 |
| M4 Max, loaded, rough | release | wildcard `get` hitting 1 node of 10k vs. the plain `get` | p50 1.98 ms vs. 10.9 µs; 20 070 vs. 50 allocs | 2026-11-19 |
| M4 Max, loaded, rough | release | `view=list` of 1000 children, plain vs. `is: "wy:number"` | p50 195 µs vs. 795 µs; 3.1k vs. 29k allocs; 0.58 vs. 6.6 MB allocated | 2026-11-19 |
| M4 Max, loaded, rough | release | flow chain, 3 hops, one key, 2000/s | 7 % of samples thinned (the source keeps the latest sample per key) | 2026-11-19 |
| M4 Max, loaded, rough | release | flow chain, 3 hops, 1000 keys, inbox 64 / 65 536 | lossless up to 5 000/s / 20 000/s (the next step lost 85 / 103 samples); noisy under the load: an earlier run on the same machine kept 100 000/s lossless with inbox 64 | 2026-11-19 |
| M4 Max, loaded, rough | release | flow chain, 9 hops, 1000 keys, inbox 65 536 | lossless at 50 000/s, p99 2.2 ms, 309 % CPU | 2026-11-19 |
| M4 Max, loaded, rough | release | flow allocations per sample and hop | 6.0 allocs, 425 B | 2026-11-19 |
| M4 Max, loaded, rough | release | 10 000-row table, `table_sort` ×1 / ×3 | lossless at 50 / 20 tables/s; p50 10 / 23 ms; per sort hop 140k allocs, 40.6 MB | 2026-11-19 |
| M4 Max, loaded, rough | release | 10 000-row table, `table_filter` (rhai) + `table_aggregate` | 4 of 8 tables lost at 2/s, 2 of them by the filter's 100 ms script budget | 2026-11-19 |
| M4 Max, loaded, rough | release | broker base, 1000 points at 10 / 20 / 50 Hz | 10k / 20k / 50k samples/s, no loss beyond one tick at the window edge; p99 2.4–2.5 ms; 5 / 10.5 / 24.5 % CPU; RSS 36–48 MiB | 2026-11-19 |
| M4 Max, loaded, rough | release | broker at 20k/s + `downstream/**` subscribe loop | rate kept; CPU 10.5 → 121 %; each subscribe to all 1000 points p50 3.9 ms, p99 6.4 ms | 2026-11-19 |
| M4 Max, loaded, rough | release | `subscribe("wy/**")` | no event in 15 s (not diagnosed yet) | 2026-11-19 |
| M4 Max, loaded, rough | release | broker at 20k/s, mock link at `trace` | rate kept; CPU 10.5 → 26 %; p99 2.4 → 4.0 ms | 2026-11-19 |
| M4 Max, loaded, rough | release | wyrmd open + mock with 10 000 points ready | 3.1–3.9 s | 2026-11-19 |
| M4 Max, loaded, rough | release | `add_watch_path`, watches 1–50 / 251–300 | p50 8.0 / 12.0 ms | 2026-11-19 |
| M4 Max, loaded, rough | release | historian, 10 000 points at 2 Hz | not measured: the broker stalls when the group starts (below) | 2026-11-19 |
| M4 Max, loaded (load 14–19), rough | release | historian group start, 10 000 new watches, after the fix | first row 0.6 / 1.6 s, a row of every point 8.6 / 9.5 s (two runs; before: stalled, `started=false` after 360 s) | 2026-11-19 |
| M4 Max, loaded (load 14–19), rough | release | historian, 10 000 points at 2 Hz, All Data, after the fix | 20k samples/s kept (lost 125 / 157 of 200k), p99 3.0–3.5 ms, 67–74 % CPU, RSS 165–168 MiB; 18 000 rows/s, 0 dropped, flush 139–149 ms | 2026-11-19 |
| M4 Max, load 7–12, rough | release | the same two after the merge of main and the bounded query tasks (two runs) | group start: first row 0.2 / 1.2 s, a row of every point 4.2 / 4.2 s; 20k samples/s kept (lost 67 / 75 of 200k), p99 2.4–2.5 ms, 37–39 % CPU, RSS 166–167 MiB; 20 000 rows/s, 0 dropped, flush 52–53 ms | 2026-11-20 |
| M4 Max, load 5–14, rough | release | the same two with every subscriber declared at once and 16 stored reads per link (audit of #146; two runs) | group start: first row 5.2 / 3.2 s (all 10 000 declarations now run at once, so the first row comes later), a row of every point 6.4 / 4.2 s; 20k samples/s kept (lost 734 / 135 of 200k), p99 6.7 / 2.7 ms, 58 / 40 % CPU, RSS 172–176 MiB; 20 000 rows/s, 0 dropped, flush 52–66 ms | 2026-11-20 |
| M4 Max, load 6–9, rough | release | `verify` before the key index (`d642a85a`), last of 1 / 4 / 10 / 30 limited keys | p50 44.9 / 111 / 242 / 672 µs, 11 / 14 / 20 / 40 allocs; the same for the first limited key and for every other token of a limited key; admin key 22.6 µs | 2026-11-20 |
| M4 Max, load 6–9, rough | release | `verify` before, refused token (unknown signer), 1 / 4 / 10 / 30 limited keys | p50 44.2 / 110 / 243 / 678 µs | 2026-11-20 |
| M4 Max, load 12–19, rough | release | `verify` with the key index, first or last of 1 / 4 / 10 / 30 limited keys, also in turn with a `sub` each and with a new `sub` per token from one key | p50 21.8 / 21.7 / 21.8 / 21.7 µs (p99 28–36 µs), 9 allocs with a known `sub`; admin key 21.8 µs, 7 allocs | 2026-11-20 |
| M4 Max, load 12–19, rough | release | `verify` with the key index, refused token, 1 / 4 / 10 / 30 limited keys | p50 42.4 / 105 / 231 / 645 µs (one verify per distinct key, as before) | 2026-11-20 |
| M4 Max, load 12–19, rough | release | `verify` with the key index, the limited keys in turn and a new `sub` in every token (nothing tells the signer), 1 / 4 / 10 / 30 keys | p50 21.9 / 85.5 / 208 / 630 µs (before: 45.5 / 111 / 242 / 681 µs) | 2026-11-20 |
| M4 Max, loaded, rough | release | 1000 invokes, audit | invoke p50 4.0 ms, p99 7.1 ms, 312/s; 233 audit records/s; derived 700 fsync/s (1 per record in fact: no anchor directory) | 2026-11-19 |
| M4 Max, load 4–33, rough | release | 1000 invokes, audit, with the journal's group commit (table below) | four runs: invoke p50 0.10–0.31 ms, p99 0.20–6.1 ms, 1 330–8 169 per s; 1 289–6 836 audit records/s, 8–33 records per `fsync` | 2026-11-20 |
| M4 Max, loaded, rough | release | gateway, 10 WS clients × 1000 points × 10 Hz | 100k frames/s, p50 4.0 ms, p99 8.1 ms, 84 % CPU, RSS 85 MiB | 2026-11-19 |

**Done: the audit journal's write path (item 1, 2026-11-20,
`perf/audit-write`).**

*Cause, measured first.* Each audit record was one `Store::apply` under a
`std::sync::Mutex`, called on a runtime worker: the `watch_audit` task for a
link's records, any handler for the broker's own. `apply` writes the record
and calls `fsync` (`F_FULLFSYNC` on macOS, about 4 ms on this machine). So
the journal took 1 / 4 ms = 240 records/s whatever the load, a worker stood
in the system call for all of that time, and a 1 ms timer of the same
runtime fired 2.9 ms late at the median with one caller and 127–282 ms late
at p95–p99 with 50. An `invoke` took the same 4 ms. The link puts its audit
record before it answers; which step waited for the write (the put, or the
task that answers) was not taken apart.

*The contract, as it was and as it stays* (`docs/operations.md` §1):

- a record the broker makes itself is on disk before the operation goes on
  (`Control::record` returns after the `fsync`);
- a record a link reports for its own `set`/`invoke` is not acknowledged to
  anyone (ADR 0029, decision 7): the command's answer never waited for the
  record to be durable, only for the put. It is written in arrival order;
- nothing is dropped to make room, and a failed write is logged.

*The change.* One thread (`wyrm-audit`) owns the store. Callers put records
in a bounded queue (1024; a full queue makes the caller wait) and the thread
writes what waits, at most 256 records, as one batch
(`wyrm_state::Store::apply_batch`): one write, one `fsync`, then the anchor.
`Control::record` waits for the batch that holds its record (a runtime
worker is handed back with `block_in_place` meanwhile; `record_async` waits
as a task); `watch_audit` only queues. Readers (`tail`, `audit_records`) see
a copy that the writer updates after each batch and before it answers.
`Control::shutdown` and the drop of the journal write the whole queue before
the store closes. The bytes on disk are the same: same records, LSNs, CRC,
HMAC chain, SCHEMA (test `a_batch_writes_the_bytes_of_single_applies`).

One rule moved, in the anchor file, not in the WAL: the anchor let the WAL
be one record ahead (a crash between the WAL write and the anchor write). A
batch of n ≥ 2 first writes the anchor as `<lsn> <mac> +<n>`; open and
`verify` then accept at most n records after it, and the anchor is the plain
head again when the batch is done. Without the announcement the rule is the
old one, so a cut of the tail is found as before (tests
`a_crash_inside_a_batch_leaves_a_valid_prefix`: the WAL cut at every byte of
a batch; `the_anchor_of_a_batch_refuses_every_other_cut`). A batch of one is
written exactly as before.

*Figures.* `perf_e_audit`, M4 Max, release, the same hour, other agents'
builds running (load average in the table; the second run after the change
had the highest load, and shows it):

| Figure | Before (2 runs, load 23 → 11) | After (4 runs: load 18, 33, then two at 4 → 22) |
|---|---|---|
| invoke, one after another: p50 / p99 | 3.96 / 4.84 ms; 3.96 / 5.62 ms | 0.12 / 0.20 ms; 0.31 / 6.1 ms; 0.11 / 0.28 ms; 0.10 / 0.34 ms |
| invokes per second, one after another | 335; 322 | 7 991; 1 330; 8 169; 7 689 |
| audit records per second, one caller | 242; 240 | 6 717; 1 289; 6 836; 6 551 |
| records per `fsync`, one caller | 1; 1 | 32; 7.8; 33; 32 |
| 1 ms timer late, one caller: p50 / p99 | 2.92 / 3.74 ms; 2.87 / 4.40 ms | 1.03 / 1.28 ms; 1.28 / 6.0 ms; 1.05 / 1.48 ms; 1.05 / 2.05 ms |
| invoke from 50 subjects at once: p50 / p99 | 160 / 539 ms; 156 / 501 ms | 1.1 / 2.4 ms; 4.1 / 18.7 ms; 1.0 / 2.2 ms; 1.0 / 2.2 ms |
| invokes per second, 50 subjects | 267; 280 | 39 215; 9 347; 41 845; 41 463 |
| audit records per second, 50 subjects | 233; 243 | 27 685; 8 080; 32 655; 31 479 |
| records per `fsync`, 50 subjects | 1; 1 | 182; 69; 182; 182 |
| 1 ms timer late, 50 subjects: p50 / p95 / p99 | 1.27 / 127 / 267 ms; 1.26 / 141 / 282 ms | 1.26 / 1.93 / 2.03 ms; 1.41 / 3.47 / 4.37 ms; 1.26 / 1.83 / 2.01 ms; 1.26 / 1.86 / 2.15 ms |

A 1 ms `tokio::time::sleep` fires about 1 ms late on an idle runtime (the
timer's own step), so 1.0–1.3 ms is the floor of that figure. The journal
is no longer what bounds commands: with 50 callers the CPU of the whole
process (broker, mock, 50 clients) is 200–690 % of a core.

*Left.* The reference board and a quiet machine. Not changed: the other
`wyrm-state` stores (registry, flows, users) write one record per `fsync`
from the caller's thread, as before; they are not on the command path.
`wyrmd user …` (the offline command line) writes its audit record with a
plain `apply`.

*After the audit of #152 (2026-11-20).*

- A kill inside a batch left the anchor with its announcement, which a
  version from before group commit refuses: the automatic rollback of a
  broker update (ADR 0048 §2.5) then could not start the previous version.
  Rule: while `update.json` says `trial`, the journal writes record by
  record, in the form every earlier version opens
  (`Journal::one_by_one`, set at `Control::open`, when an update is staged
  and when it is confirmed). Tests
  `in_a_trial_the_files_are_what_the_previous_version_opens` (the files at
  every step of every write pass the old rule),
  `the_audit_journal_follows_the_update_state`. Second audit: the same
  from the moment `rollback_update` is asked (the state stays `confirmed`
  and names who asked); the switch waits for a batch in flight before the
  action answers. Test `a_rollback_asked_switches_the_journal_before_it_answers`
  (through the action).
- A failed write left its bytes in the WAL and the next record followed
  them (the note above; with batches the window was larger). `Store::append`
  cuts the file back; when it cannot, or when the `fsync` failed, the store
  refuses every later write (`StateError::Broken`) until it is opened
  again. For `apply` too, so for every store. Tests
  `a_failed_batch_leaves_no_bytes_and_moves_nothing`,
  `a_failed_apply_leaves_no_bytes`,
  `a_store_that_cannot_undo_a_write_takes_no_more`.
- The crash test wrote the announcement itself. Now a probe
  (`Store::with_probe`, feature `testkit`) copies the files before each
  step of a real batch: `a_kill_at_each_step_of_a_batch_leaves_a_store_that_opens`
  fails when `commit` does not announce.
- A panic of the writer thread left callers waiting for ever: the thread's
  end closes the queue (`WriterEnd`); test
  `a_writer_that_panics_fails_its_callers`.

`perf_e_audit` after these changes and the merge of main (two runs, load
15–22, outside a trial): invoke p50 0.12 / 0.11 ms, p99 0.20 / 0.35 ms,
7 968 / 7 558 per s; 6 749 / 6 415 audit records/s in 31 / 31 batches; 50
subjects: p50 1.10 / 0.99 ms, p99 2.2 / 2.3 ms, 40 085 / 43 489 invokes/s,
34 500 / 33 177 records/s in 11 / 11 batches; 1 ms timer late p99 2.1 /
1.9 ms and 2.2 / 1.8 ms. No change against the table above. Follow-ups:
issue #153.

**Found: the historian's group start stalls the broker** (called a
deadlock here: 0 % CPU and no progress for 9 min, twice; a symbolized
`sample` of the second run). A group of 10 000 new watches first makes each
series with one durable redb commit (on the blocking pool, under the store's
series lock), then starts one `follow` task per point, and each runs
`WyrmClient::subscribe`, a `get` of the point's `~val`. On the in-process
session Zenoh hands a query to a local queryable on the caller's thread, and
the default handler of a queryable is a bounded FIFO (256) whose send blocks
when it is full. What the sample shows: four runtime threads stood in that
send (`wyrm_history::engine::follow` → `Session::query` → `handle_query` →
`FifoChannel` callback, waiting on a semaphore); two other runtime threads
were idle (one on a condvar, one in the time/IO driver); the test thread was
parked in `block_on`, and its own 300 s deadline never printed. Not known
yet: which local queryable's FIFO filled, and why its consumer did not drain
it. Not fixed here (P0 changes no product code). The perf test aborts by a
watchdog after 360 s with `started=false`.

**Fixed (2026-11-19, `fix/historian-stall`).** The FIFO was the
historian's own: `query::serve` declares `~val` queryables on
`wy/<site>/{downstream,dataflows,storage}/**/~val` to answer
`?history=`, so every plain `get ~val` of a follow matched it too, was
queued and then dropped by `answer`. The cycle: a `follow` on a broker
worker calls `Session::get` → Zenoh's `handle_query` runs the local
queryable's handler on that worker → the FIFO send blocks while the queue
is full → the task that drains it (`recv_async` in `serve`) needs a worker
of the same runtime → every worker stands in the send, nobody drains. A
sample of the regression test before the fix shows all four workers 100 %
in `flume::Sender<Query>::send` → `send_sync`, monomorphized in
`wyrm_history`, with no storage in that test at all. The `~val` storage
drains its own FIFO on the storage manager's runtime (2 workers): it
slows a caller but cannot close this cycle.

The fix, by rule (CLAUDE.md, Zenoh facts):

- no in-process queryable handler blocks the querier's thread:
  `wyrm_client::queryable::bounded` filters and `try_send`s into a bounded
  queue; a query it does not keep is dropped (Zenoh ends it at once). The
  historian keeps only selectors with `history`/`since` (a plain read never
  takes room) and answers a full queue `busy` from one task with a queue
  of its own (256, then dropped); at most 256 history queries have a task
  at once. The admin's profiles, signing keys and replication queryables
  use it too (queue 256, as the FIFO held; full = dropped). The link SDK's queryable already did this;
- a client that follows many points bounds its stored reads, and only
  those: with `WyrmClient::with_stored_reads` a `subscribe` declares its
  subscriber and returns at once, and the stream takes a turn before it
  sends the stored read (held until the read's last reply or its timeout).
  The historian has one window of 64 over all its groups (below the
  storage's 256) and, before it, one of 16 per owner (a link, or a site
  section). A `get <point>/~val` also reaches the point's link, so a link
  that answers no query holds its reads for their 10 s: it holds 16 turns,
  its own points' stored values come late, and no other point waits.
  (Audit of #146: with the turn taken before the subscriber, such a link
  left every other point without a subscriber, 64 points per 10 s.)
- a group's new series go into the index in one commit
  (`Store::series_ids`), not one durable commit per key.

Chosen by measurement: with the bounded reads the whole group of 10 000 is
followed in about 9 s (4 to 6 s on 2026-11-20) and the steady state is unchanged (one subscriber per
point, as ADR 0014 records it). Most of those 9 s are Zenoh's own:
each `declare_subscriber` of a new key registers a resource and walks the
existing ones (`declare_nonwild_prefix` → `Resource::get_matches`), so the
cost grows with the square of the points. One subscription per link
(`<link>/**`, filtered to the watched keys) would remove that, but every
sample of an unwatched sibling would then pass through the historian's
handler for as long as the group runs; not done, a candidate if 10 000
watches must start faster. Regression test
`many_new_watches_do_not_stall_the_runtime` (4 workers, 3000 watches, it
fails after 30 s without progress): 5 runs of 5 stalled before, about 7 s
(debug build) after.

Seen beside it on 2026-11-19 (load 14–19): with All Data on 10 000 points
at 2 Hz the historian wrote 18 000 rows/s of the 20 000 samples/s, with 0
counted as dropped. On 2026-11-20 (load 7–12) it wrote 20 000 rows/s in
both runs; the cause of the lower figure under the heavier load is not
diagnosed.

**Fixed (2026-11-20, `perf/declare-on`): declaring n points under one
node cost n².** Audit item 4. The cause, by the counters of the bench (no
`samply`/`cargo flamegraph` on the machine; a `sample` of the stripped
bench shows only `malloc`, `free` and `memmove` on top): every new child
put its parent's whole `~meta`, and that lists every child. Of the 276 MiB
put for 10 000 points, all but 0.1 MiB were the parent's 10 000 puts (27.6 kB
each on average); a point's own `~meta` is about 10 bytes. Each of those puts
also copied the child list twice and built two keys per child (2.5
allocations per child and declare). The 276 MiB were bytes put, never
memory held: the process peaked at 21 MiB. Nothing of it was Zenoh's: the
broker stores `~val` only, and of the 6.5 MiB kept after 10 000 declares
6.4 MiB are the link's own tree (the same figure without Zenoh).

The rule now (`LinkCtx`, `Parents` in `crates/wyrm-link-sdk/src/ctx.rs`):

- a child's own `~meta` is put by its declare, as before: a `list` client
  gets `Added` for every child from that put, and a snapshot
  (`view=full|list|keys`) is answered from the tree, which the declare has
  already changed. Wire, keys and payloads are unchanged;
- the parent's `~meta` for a changed child list (a child declared or
  removed) is put at once when no such put was made just before. After
  one, the next waits 4 times as long as that put took (at most 500 ms);
  a parent that changes meanwhile is noted in a set (a path once, so never
  more than the tree holds: no queue) and one task puts each noted parent
  when the wait ends, once, with the list as it is then. The parent puts
  take at most 1/5 of a burst's time, so n children cost O(n). A single
  Add in a quiet link is put by the declare itself, as before;
- a requester that follows the parent's `~meta` sees fewer puts in a
  burst, with `rev` rising by more than 1; the last put always carries
  the whole list (spec 02 Patch already tells a requester what a gap
  means). All `~meta` puts of a link take turns, and each reads the tree
  inside its turn, so the last put of a node is its newest meta also when
  two tasks put it (before, two tasks could leave the older one last);
- a put made later by the task cannot fail the declare that asked for it
  (it is logged at `debug`); a stopped link drops what waited;
- a removal takes a turn of the `~meta` puts (audit of #154): `remove_node`
  takes the nodes out of the tree and sends their deletes inside one turn.
  A put of a removed node, or of a parent that still lists it, is out
  before the delete, or its turn comes after and it reads a tree without
  the node. Before, a put that had read the tree could follow the delete,
  and a `list` client showed the removed node again (5–11 of 20 000
  add/remove cycles). `remove_node` is the only place that deletes keys and
  `put_meta` the only one that puts a `~meta`; a link's stop deletes
  nothing and puts nothing more;
- a changed child list is noted before its put, also when the put is made
  at once, and the note goes only with a put that carried it: a put that
  failed, or whose caller gave up half-way, is made again by the task
  after 250 ms (before, the list stayed old until the next change);
  Measured again with both (2026-11-21, M4 Max, load 5–7, three runs
  each): 1k / 10k / 30k points in 2.8 / 28–33 / 91–92 ms, `~meta` put
  0.07 / 1.0–1.1 / 4.1–4.4 MiB, 41–42 / 72–81 / 106–109 parent puts: the
  figures of the table above did not move;
- the tree keeps its nodes boxed: the hash table holds a key and a pointer
  per slot instead of a 352-byte node in every slot, used or not (kept
  25.0 → 13.6 MiB at 30 000 points, and no 12 + 24 MiB copy when the
  table grows); `NodeTree::full` reads each child once.

Tests: `crates/wyrm-link-sdk/tests/declare_burst.rs` (5000 children put
the parent at most 500 times, it was 5000; the last put is the whole list
with the tree's `rev`, also with two declaring tasks and for removals; a
single child is put at once; a stopped link puts nothing; a put of a
folder stopped by a test gate after its read of the tree, then the folder
removed: the removal waits and the folder's samples end with the one
delete, with no sleep that decides the result; a failed and a dropped
parent put are made again) and
`crates/wyrm-client/tests/declare_burst.rs` (lists opened before and
during a burst of 10 000 children all end with every child, each added
once; the folder's last put, seen by its parent's list, carries all).

Left as it is: a `list` opened while children are declared faster than
its snapshot is read answers `busy` ("children kept changing"), as
before; the caller asks again, and the bursts are now some 300 times
shorter at 10 000 points. A node is still 352 bytes for a 10-byte meta (`NodeMeta` is a
struct of many optional fields: a change of `wyrm-core`, not done here).
Removing n children one at a time still searches the parent's list each
time (n² short string compares; not measured apart). A `~val` put is outside the turns (as before this change): `update` checks
the tree and then puts, so a value published while its node is removed can
follow the delete of `~val`; a turn per value would put every sample of a
link in one queue. The framework's four own `~meta` puts per point (the point,
then each action) are a constant per point and are not merged.

**Pattern (fan-in) consumer (2026-11-20, `perf/fan-in`): partly done.**
The figure "CPU 10.5 → 121 %" above is not what a pattern consumer costs.
`perf_b_wildcard` opens `subscribe("wy/<site>/downstream/**")` again and
again, about 250 times a second, and each one is a declaration and a stored
read of 1000 points. Two measurements were missing and are added:

- `perf_g_fan_in` (`wyrmd`): 1000 points at 50 Hz and a second session that
  takes every sample, once with a raw Zenoh callback and once as
  `WyrmClient::subscribe` of the whole `downstream` section read to its end;
- `tests/fan_in.rs` (`wyrm-client`, feature `testkit`): the handler of a
  value stream called by hand and the stream read, with no session; the
  counting allocator; one thread, and 1000 samples every 20 ms read by a
  task.

What they show (M4 Max, release, load 3–44 from other builds, rough; before
and after run in turn; ranges over 2–5 runs each):

| Figure | Before | After |
|---|---|---|
| base, 50k samples/s to one raw subscriber | 23–31 % CPU | the same |
| + a second session, raw callback | +15–27 % | the same |
| + a second session, `WyrmClient::subscribe("…/downstream/**")` | +30–44 %; consumer p50 2.3–2.6 ms, p99 3.4–12 ms; 0 dropped | +23–43 %; p50 2.0–2.3 ms, p99 2.9–8.1 ms; 0 dropped |
| the value stream alone, one thread (handler + read) | 153–179 ns per sample (5.6–6.5 M samples/s on one core), 2.0 allocations, 63.6 B | 136–155 ns (6.4–7.4 M/s), 1.0 allocation, 31.8 B |
| the value stream alone at 50k/s, read by a task | 4.0–8.7 % CPU; p50 10–22 µs, p95 38–154 µs, p99 76–342 µs | 5.2–6.0 % CPU; p50 4–13 µs, p95 17–150 µs, p99 42–335 µs |
| profile of the consumer (1 ms samples, 6 s): the handler on Zenoh's receive threads | 186 samples of 3340 (5.6 % of a core), 108 of them waiting for the buffer's lock in the kernel | 47 of 3095 (1.5 %), 2 waiting |
| the same profile: kernel waits for the buffer's lock, handler and reader | 137 samples (4.1 % of a core) | 6 (0.2 %) |
| SDK, the stored read of a subscriber (`…/**/~val`) at a link of 10 000 nodes (`tree/fan_in_val/10000`) | p50 1.84 ms, 20 059 allocations, no reply | p50 12.2 µs, 39 allocations, no reply |
| SDK, wildcard `get` hitting 1 node of 10k (`tree/fan_in/10000`) | p50 1.64 ms, 20 070 allocations | p50 1.41 ms, 53 allocations |
| `perf_b_wildcard`, the subscribe loop at 20k/s | 112–116 % CPU, snapshot p50 3.7–3.9 ms | 107–113 % CPU, p50 3.7–3.9 ms: not changed |

So a steady pattern consumer at 50 000 samples/s was under half a core
before, and is now: about 20 % of a core is Zenoh's delivery to one more
session (a raw callback pays it too), the rest is the client's stream and
the task that reads it. The process CPU of that case did not change beyond
the noise of the loaded machine; the profile, the allocations and the
latency did.

Where the profile pointed, and what changed (no change of the events, their
order, the bounds or the counters; `the_same_input_gives_the_same_output`
runs four recorded inputs through the old buffer, kept as a model, and the
new one):

- `wyrm-client`: a sample was copied, decoded and filtered inside the
  buffer's lock, and the standard lock of macOS waits in the kernel as soon
  as it is taken: more than half of the handler's time was that wait, and
  the reader waited there too. Now the key filter runs first, on the key as
  Zenoh holds it (a refused sample is not decoded), the decode runs before
  the lock (`Intake::feed_map`), and a thread that finds the lock taken
  tries 64 times before it waits. `parking_lot`'s lock was tried and
  refused: it yields its turn, and on a loaded host a yield cost a scheduler
  quantum (p95 of the stream 10 ms, measured).
- `wyrm-client`: `pop` looked the key up three times and copied it for every
  sample; one lookup, a copy only for a key seen first. One allocation per
  sample is left, the key `String` of the event
  (`one_allocation_per_sample`).
- `wyrm-link-sdk`: every wildcard `get` walked the link's whole tree under
  its lock and built two keys per node. The stored read of every pattern
  subscriber reaches every link, and a link whose values the storage
  answers has nothing for it. `fan_in` now tries the pattern against
  `<prefix>/**/~meta` and `<prefix>/**/~val` first and ends at once when it
  meets neither; a walk builds its keys in one buffer
  (`fan_in_answers_what_the_pattern_meets`,
  `a_fan_in_read_does_not_pay_per_node`).

Not done:

- the subscribe loop itself (`perf_b_wildcard`): the link's walk was a small
  part of it (about 0.2 ms of CPU per subscribe on 1000 points). The rest is
  Zenoh's: the declaration of a wildcard subscriber, the storage's answer of
  1000 keys and its consolidation in the session. Audit item 2 stays open;
- one wake-up of the reading task per sample when the samples come spread
  out: most of what the stream costs beside Zenoh now. Fewer wake-ups need
  a delay before a wake (tokio's timer has 1 ms steps), which changes the
  latency of every consumer; a candidate as an opt-in of the client, not
  done. Reading several events in one lock was tried (no gain in the
  measurement) and removed;
- `tree/fan_in/10000` still walks 10 000 nodes for one hit (a key check per
  node, 0.14 µs each); the tree has no index by pattern;
- the consumers above the client (the flow engine's sources, the portable
  runtime's event queue, the gateway's frames) are not profiled apart;
- `sample` stalls a process the first time it reads a new binary's symbols
  (17 samples in 6 s, 350 000 samples of the window lost): run a profile
  twice and keep the second (build with `CARGO_PROFILE_RELEASE_STRIP=false
  CARGO_PROFILE_RELEASE_DEBUG=line-tables-only` into a target directory of
  its own).

**Done (2026-11-20, `perf/ptok-verify`): one signature check per token
(audit item 3).** A `ptok` names no key (spec 04), so the responder tried the
admin keys and then **every** limited key, one Ed25519 `verify_strict` each:
a token of a limited key cost 1 + n verifications wherever its key stood
in the list (first and last measure the same above), on every `~set` and
`~act`. Now (`wyrm-link-sdk` `auth.rs`, `Trust`; the wire format and
`spec/` did not change):

- the trust list is kept as one entry per distinct public key, with all it
  is trusted as (admin, and every limited entry of it in list order);
- the verifier remembers `sub` → the key that signed the last **accepted**
  token of that subject (at most 1024 subjects of at most 128 bytes, an
  arbitrary one goes when it is full), reads the `sub` of the token at hand
  before the signature is checked (`wyrm_core::ptok::peek_sub`: a walk over
  the CBOR heads with a counter, no decoder and no allocation; an
  indefinite length or more than 4096 items before `sub` give no hint), and
  tries that key first;
- without a remembered key, or when it does not verify, every other key is
  tried, the last used first; the search ends at the first key that
  verifies (`verify_strict` binds a signature to one public key).

The remembered key is a hint only. The signature is always checked in full
against the key that is tried, so a wrong or forged `sub` costs time and
changes no answer; a refused token is checked against every distinct key
once, whatever it claims (the refused figures above: unchanged). What a
signer is trusted with is read as before: an admin key wins over its
limited entries, several limited entries of one key count together (widest
cap that covers the request, scopes of all in list order). A new trust list
(`set_trust`: `hello`, a rebuild, the signers poll) is a new index with no
remembered subjects; the replay cache stays, as before. Tests in `auth.rs`:
the old sequential search is kept as the oracle and 2400 random tokens on 40
random trust lists (keys named twice, different limits, lists replaced on
the way; good, unknown signer, damaged, expired, replayed) get the same
answer from both; a key trusted twice; one verification for a known subject
with 31 keys and 31 for a refused token; a wrong hint; a new list; the
bound. With it (security audit of #150, spec 04
0.2.36): a `ptok` longer than 64 KiB is refused before any other work
(`Denied::TooLarge`, `permission_denied` as every refusal). Before, the
length had no bound, and a refused token was hashed whole once per trusted
key, on the old path too. Test `tests/ptok_alloc.rs` runs on the counting
allocator: nested and 16 MiB claims allocate nothing in the peek and under
8 KiB in a refused check. Left as it is: a signer whose every token has a new `sub` while
other signers work in turn (the last row above) is found by the search;
only a key id in the token would remove that, and that is a spec change
nobody needs yet.

**Flow copies (2026-11-21, `perf/flow-copies`): partly done.** What one
sample costs inside the flow runtime was not measured apart: `throughput`
puts every sample through a session and a `publish` node. `tests/copies.rs`
(`wyrm-flow`) starts the runtime directly (`runtime::start`), pushes the
samples of a round into the first node's inbox in one burst and reads the
end from the flow's own `samples_in`; the counting allocator; each case is
the median of 7 rounds, and the table gives the median of 5 such runs. No
profiler is installed on this machine (`samply`, `cargo flamegraph`): the
copies were ranked by the allocation count of each stage, one change at a
time.

M4 Max, release, loaded by other agents' builds (load 25–46 before, 12–14
after; rough). The allocation counts do not move with the load; the rates
and the CPU do.

| Figure | Before | After |
|---|---|---|
| chain of 10 pure blocks (`add`, `multiply`), one number per sample | 123 800 samples/s; 16.8 µs CPU and 90 allocations (4 960 B) per sample | 305 900 samples/s; 6.7 µs, 1.0 allocation (24–50 B) |
| one `add` whose output has 16 edges, each into an `abs` | 53 500 samples/s; 64.6 µs, 121 allocations (6 580 B) | 196 900 samples/s; 16.6 µs, 1.0 allocation (24–234 B) |
| one `expression` (rhai, `x.v * 2.0 + 1.0`) | 991 700 samples/s; 1.00 µs, 15 allocations (1 234 B) | 1 103 000 samples/s; 0.97 µs, 11 allocations (897 B) |
| a 1000-row table of 3 columns through 3 `table_sort` | 375 tables/s; 2 695 µs, 97 190 allocations (12.0 MB) per table | 523 tables/s; 1 930 µs, 60 100 allocations (8.25 MB); two runs, load 11 |
| `throughput`, `flow/per_hop` (`scale`, `add`; one run) | 6.0 allocations, 425 B per sample and hop | 0.002 allocations, 0.3 B |
| `throughput`, `flow/table/per_hop` (10 000 rows as lists, `table_sort`; one run) | 140 000 allocations, 40.6 MB | 80 000 allocations, 27.1 MB |
| `throughput`, 10 000-row table through 3 `table_sort` (one run, load 6–10) | lossless at 20 tables/s | lossless at 50 tables/s, the top of the ladder |

The one allocation left per sample in the first two rows is the test's own
push into the first inbox (a port name given as text, as a source's
`inject` gives it).

Where the copies were, per block and sample, and what changed (no change of
a sample, of the order of samples on an edge, of the `start`/`constant`
marks, of `watch` or of the counters; `spec/` did not change):

- `runtime.rs`: an inbox kept the input's name as a `String` made for every
  sample. An edge now holds the name once (`Arc<str>`) and every sample
  pushed there shares it. A name given as text (`Inbox::push_now`: a
  source's `inject`, `~act/trigger`) is still copied once.
- `runtime.rs`: `route` copied the sample for every edge and dropped the
  original. The last edge of an output now takes the sample itself, so an
  output with one edge copies nothing: one deep copy less per table and hop.
  The edges are served in the same order (`route_keeps_the_order_of_edges_and_samples`).
- `runtime.rs`: the list of what a call emitted was allocated for every
  call; a node task now keeps one and `route` empties it.
- `nodes.rs`: `Out::emit` copied the output's name for every sample. An
  output is named in the code: `Out` holds `Cow<'static, str>` (`PortName`),
  and only a name made while the flow runs (`router`'s `out.<name>`, an
  input's echo, a `wasm` node's outputs) is owned.
- `blocks.rs`: a block copied the input's name three times for every sample
  (the name, the key of `seen`, the key of `values` or `params`) and the
  output's name once (the key of `sent`). Each slot is now found by the name
  and its key is made only for the first sample (`put`). `add`, `subtract`,
  `multiply`, `divide`, `max`, `min` read their inputs in place instead of
  copying all of them into a list and the numbers into a second one.
- `nodes.rs`: `expression` copied the input's name twice per sample.
- `blocks/table.rs`, `blocks/tables.rs`: a table block parsed its input
  into rows (one copy, needed: the block keeps its input) and then copied
  every row again into the output value. `Table::into_value` moves a row
  that holds exactly the table's columns (`into_value_is_to_value`). The
  parser copied every key of every row to ask whether the column was
  known; it now copies a key only for a new column.
- test `a_number_through_ten_blocks_allocates_next_to_nothing`
  (`tests/copies.rs`, runs with the other tests): under 3 allocations per
  sample through 10 blocks.

Dropped: nothing. Each change was measured alone or with its neighbours in
the same file, and each took at least one allocation of the nine per block
and sample, or a copy of a table per block.

Not done:

- a table is still copied four times per block: the parse of the input the
  block keeps, the last value sent per output (`sent`, for "send only when
  it differs"), and the last sample of the input and of the output in the
  probe (`watch` keeps them with no watch open, spec 06 0.2.18). An output
  with n edges adds n − 1. All of them need a payload that is shared
  (`Arc`, copy on write), and `Msg.v` is a `wyrm_core::Value`, read in
  about 60 places of the engine and 120 of its tests: a slice of its own.
  Expected from it: one copy per table and block instead of four;
- rhai: 11 allocations per call are left (the variables' map and scope, the
  `state` map boxed and read back, the evaluation itself). A value that is a
  map or a list is converted to `Dynamic` and back on every call; a scope
  kept between calls was not tried;
- the per-row scripts of `table_filter` and the other row blocks (a row
  converted to a rhai map per row) and `flow/table/filter_sum`, which still
  loses tables to its 100 ms script budget;
- what is left of a hop, about 0.7 µs of CPU per sample, was not profiled.
  It is not an allocation. In the code of a hop: a wake-up of the next
  node's task, the probe's lock and compare twice per call, a clock read for
  `last_sample_t`;
- the sources and the sinks (`subscribe`, `publish` and its encode, the
  commands) are not in this measurement;
- the reference board and a quiet machine.

Not covered yet:

- the reference board, a LAN between broker and clients, and a quiet
  machine;
- `fsync` counts (no OS counts them; the audit's are its batches);
- the historian's flush cost per row (its start and rate under 10 000
  watches are above);
- musl and its system allocator (audit item 6): the container images are
  not measured;
- the storage manager's own lock (item 2) apart from the subscribe that
  reads it, and process links (only embedded links are measured);
- the SDK value path and the log filter per event apart (items 11, 12 are
  seen only through the broker's CPU);
- the framework's five `~meta` puts per point (item 4 is measured on the raw
  layer only).
