# ADR 0042 — Names people read: one rule for actions, parameters and nodes

**Status:** accepted · 2026-11-11 (spec 02 0.2.28). Decided under ADR 0029 (owner delegates: decide, write the rule down). Owner: "Some actions have names in snake style like `a_ab`; that does not read well, while part of them have normal readable names. Go through all of Studio and the links to fix such things. Nodes can have such names too, and they are paths, let them stay so, but maybe we add a `name` field that lets us replace or style nodes and actions."

## Context
- Spec 02 0.1.6 gave actions and parameters an optional `display`. Most links set one, in Title Case ("Add Device", "Poll Rate (s)"). Some left it out, and a client then showed the key (`add_class`, `timeout_ms`).
- A node already has a name for people: `attr.display`, sent as key 12 in `view=list` rows (spec 02 from 0.1.0; fixture `meta_view_list`). Links set it at declare time (scheduler, alarm, DQL, storage). The driver framework had no way for a user to set it on a connection, device or point.
- The texts had no common style: Title Case beside sentence case, `Url` beside `URL`, `Id` beside `ID`.

## Decision

### 1. Keys stay; people read `display`
A key (of a node, an action, a parameter) is a wire name: a path segment or an `args` name. It never changes for style; plans, tests, ACL grants and docs use it. What a person sees is `display`. Enum values (param-meta key 3) and `group` are wire values too: they are not renamed.

### 2. One rule, in `wyrm_core::display`
- `humanize(key)` derives a name from a key: tokens split at `_`, `-`, `.`; the first word capitalised, the others lower case; words of `WORDS` written as listed (`url` → `URL`, `id` → `ID`, `mqtt` → `MQTT`, `bacnet` → `BACnet`); a last token of `UNITS` (`ms`, `s`, `hz`, `kb`, `kib`, `mb`, `mib`, `pct`, `days`, `us`) in brackets. `add_device` → `Add device`, `unit_id` → `Unit ID`, `timeout_ms` → `Timeout (ms)`.
- `check(text)` is the style of an explicit `display`: sentence case, no `_`, no trailing dot, acronyms as `WORDS` writes them, names only from `WORDS`, `NAMES` (one word) and `PHRASES` (`IoT Hub`, `Socket Mode`, `Block Kit`). Text in brackets is free (units, `(GETBULK)`).
- `sentence(text)` turns a Title Case text into sentence case under the same lists; the framework uses it where it builds a name (`Add ` + a kind's display).

### 3. The SDK fills what a link leaves out
`NodeTree` (the responder SDK, so every native, process, portable and WASM link served by the SDK) fills a missing action `display` and a missing param-meta `display` with `humanize` of the key, on `declare`, `declare_action` and the root. An explicit `display` wins. A new link gets readable names without writing any; it writes a `display` only where the derived text is wrong or too thin. A link built before this change and not rebuilt sends no `display`: a client may derive one from the key (Studio does; the exact rule with the acronym list lives in `wyrm_core::display`).

### 4. A user-made node gets a name: `display` in Add and Edit
The driver framework takes an optional `display` on `add_*` and `edit` of connections, devices and points and shows it as `attr.display` (key 12 in `view=list`). It is structural like `kind`: kept beside the params in the sealed tree, in Export, Import and Copy, never in `~meta.cfg`, never a driver param (no driver has a field named `display`; the name is reserved). `edit` without `display` keeps the name, `null` or `""` clears it; at most 128 bytes. An `edit` with `display` alone is a rename: the stored params stay as they are (nothing goes back to a default). A rename, or the full form with unchanged params and a new name, re-declares the node and restarts nothing (no rebuild, the connection stays up, stored secrets stay). The sealed tree is saved after it like after any edit. Folders (names only, `add_folder`) get no display name: a folder is its key.

No twin field: the node's name is the existing `attr.display`. Points with an own description keep it beside (`attr.description` is a hint, `display` the name).

### 5. The tests hold every link to it
- `wyrm_core::display` unit tests: the derive rule with acronyms and units, sentence case, the check.
- `wyrmd` e2e `every_action_has_a_name_people_read`: a broker with every embedded driver (each framework driver with one connection, device and point), the embedded apps (scheduler, alarm, DQL, uplink), `sys/**`, `storage` and `dataflows`; it walks every node and fails on any action or parameter whose `display` breaks the check (433 actions, 1 122 parameters today).
- The test hosts of the apps that `wyrmd` does not embed (messenger links, history sync targets) lint every action they are handed.

## Consequences
- 295 hand-written texts went from Title Case to sentence case by a script, and about 30 were fixed by hand (`Url`, `Id`, `Clear conns`, `from zip`, `Poll s`). Error messages that name an action follow the new names (`use Set password`).
- Docs still quote some menu paths in the old case (`Install Link ▸ from Zip`); they are fixed as each guide is touched.
- Not covered: enum choices have no `display` (they are wire values; a client may humanize them), and action results have no column names in spec 02.
