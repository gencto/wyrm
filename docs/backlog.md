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

Every figure prints one line `PERF name=… n=… p50_us=… p95_us=… p99_us=…
per_s=… cpu_pct=… rss_mib=… allocs_op=… bytes_op=… <extra>` (`-` where a
column does not apply). The kit is the dev-only crate `wyrm-bench`: a
counting allocator (calls, frees, bytes; a bench or test installs it as its
`#[global_allocator]`), nearest-rank percentiles, process CPU time and
resident memory. CPU is the whole process (broker, links, the measuring
client) in % of one core. No OS counts `fsync` calls: the audit figure gives
them as derived from `wyrm-state` (3 per record: `sync_data` of the WAL,
`sync_all` of the anchor, `sync_all` of the directory); on Linux
`/proc/self/io` adds write calls and bytes; on macOS nothing more is
measured.

| Group | Measurement | Audit item | What it covers |
|---|---|---|---|
| sdk | `cargo bench -p wyrm-link-sdk --bench verify` | 3 | one `ptok` check with 1 admin + 4/10/30 limited keys: best case (admin key) and worst case (the last limited key, 1 + n Ed25519 verifies) |
| sdk | `cargo bench -p wyrm-link-sdk --bench tree` | 4, 5, 17 | declare 1k/5k/10k points (time, `~meta` puts and bytes; pure `NodeTree` and through `LinkCtx` over Zenoh); a wildcard `get` that hits one node of 10k; `view=list` of 1000 children with and without a profile name |
| flow | `cargo test --release -p wyrm-flow --test throughput -- --ignored --nocapture` | 7–10 | `subscribe → (scale, add) × n → publish`, a paced rate ladder on one key and on 1000 keys, default and deep inbox; allocations per hop (9 hops minus 3); 10 000-row tables through `table_sort` ×1/×3 and `table_filter` + `table_aggregate` |
| broker | `cargo test --release -p wyrmd --test perf -- --ignored --nocapture --exact <test>` | 1, 2, 12, 13, gateway | an in-process broker with the embedded mock: (a) base rate, (b) a client that subscribes `wy/<site>/downstream/**` in a loop and one `wy/**`, (c) the mock at `trace`, (d) the historian on 10 000 points, (e) 1000 invokes and the audit records/s, (f) 10 gateway WebSocket clients × 1000 points × 10 Hz |

Test hooks: `wyrm-admin`'s `testkit` feature (dev only) gives the perf tests
`Control::audit_lsn` and `Control::historian`. No product code changed.

First figures. Machine: Apple M4 Max (14 cores, 36 GB), macOS, release
build, commit `9b95c288`/`c938a6b4` (the measurements only), 2026-11-19. The
machine ran other agents' builds at the same time (load average 7–27): the
figures are **M4 Max, loaded, rough**; the clean baseline is recorded later,
and the reference board (4-core ARM64, 2 GB) is not measured yet.

| Machine, build | Figure | Value |
|---|---|---|
| M4 Max, loaded, rough | `verify`, admin key (1 verify), any n | p50 22.8 µs, 7 allocs |
| M4 Max, loaded, rough | `verify`, last of 4 / 10 / 30 limited keys | p50 111 / 243 / 684 µs (p99 1.27 ms at 30), 14 / 20 / 40 allocs |
| M4 Max, loaded, rough | one Ed25519 `verify_strict` | p50 21.6 µs |
| M4 Max, loaded, rough | declare 1k / 5k / 10k points (`LinkCtx`) | 85 ms / 2.1 s / 8.9 s; `~meta` 2.3 / 67 / 276 MiB in 2 puts per point; 2.6k / 12.6k / 25k allocs per point |
| M4 Max, loaded, rough | wildcard `get` hitting 1 node of 10k vs. the plain `get` | p50 1.98 ms vs. 10.9 µs; 20 070 vs. 50 allocs |
| M4 Max, loaded, rough | `view=list` of 1000 children, plain vs. `is: "wy:number"` | p50 195 µs vs. 795 µs; 3.1k vs. 29k allocs; 0.58 vs. 6.6 MB allocated |
| M4 Max, loaded, rough | flow chain, 3 hops, one key, 2000/s | 7 % of samples thinned (the source keeps the latest sample per key) |
| M4 Max, loaded, rough | flow chain, 3 hops, 1000 keys, inbox 64 / 65 536 | lossless up to 5 000/s / 20 000/s (the next step lost 85 / 103 samples); noisy under the load: an earlier run on the same machine kept 100 000/s lossless with inbox 64 |
| M4 Max, loaded, rough | flow chain, 9 hops, 1000 keys, inbox 65 536 | lossless at 50 000/s, p99 2.2 ms, 309 % CPU |
| M4 Max, loaded, rough | flow allocations per sample and hop | 6.0 allocs, 425 B |
| M4 Max, loaded, rough | 10 000-row table, `table_sort` ×1 / ×3 | lossless at 50 / 20 tables/s; p50 10 / 23 ms; per sort hop 140k allocs, 40.6 MB |
| M4 Max, loaded, rough | 10 000-row table, `table_filter` (rhai) + `table_aggregate` | 4 of 8 tables lost at 2/s, 2 of them by the filter's 100 ms script budget |
| M4 Max, loaded, rough | broker base, 1000 points at 10 / 20 / 50 Hz | 10k / 20k / 50k samples/s, no loss beyond one tick at the window edge; p99 2.4–2.5 ms; 5 / 10.5 / 24.5 % CPU; RSS 36–48 MiB |
| M4 Max, loaded, rough | broker at 20k/s + `downstream/**` subscribe loop | rate kept; CPU 10.5 → 121 %; each subscribe to all 1000 points p50 3.9 ms, p99 6.4 ms |
| M4 Max, loaded, rough | `subscribe("wy/**")` | no event in 15 s (not diagnosed yet) |
| M4 Max, loaded, rough | broker at 20k/s, mock link at `trace` | rate kept; CPU 10.5 → 26 %; p99 2.4 → 4.0 ms |
| M4 Max, loaded, rough | wyrmd open + mock with 10 000 points ready | 3.1–3.9 s |
| M4 Max, loaded, rough | `add_watch_path`, watches 1–50 / 251–300 | p50 8.0 / 12.0 ms |
| M4 Max, loaded, rough | historian, 10 000 points at 2 Hz | not measured: after `configure` of 10 000 new watches the test stood still (0 % CPU) for 9 min; see below |
| M4 Max, loaded, rough | 1000 invokes, audit | invoke p50 4.0 ms, p99 7.1 ms, 312/s; 233 audit records/s; derived 700 fsync/s |
| M4 Max, loaded, rough | gateway, 10 WS clients × 1000 points × 10 Hz | 100k frames/s, p50 4.0 ms, p99 8.1 ms, 84 % CPU, RSS 85 MiB |

Not covered yet:

- the reference board, a LAN between broker and clients, and a quiet
  machine;
- `fsync` counts (no OS counts them; the audit's are derived);
- the historian under 10 000 watches (the group start stood still; it needs a
  look with symbols) and its flush cost per row;
- musl and its system allocator (audit item 6): the container images are
  not measured;
- the storage manager's own lock (item 2) apart from the subscribe that
  reads it, and process links (only embedded links are measured);
- the SDK value path and the log filter per event apart (items 11, 12 are
  seen only through the broker's CPU);
- the framework's five `~meta` puts per point (item 4 is measured on the raw
  layer only).
