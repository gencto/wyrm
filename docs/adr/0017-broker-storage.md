# ADR 0017 — Broker storage: `wy/<site>/storage`

**Status:** accepted · 2026-10-24 (owner decisions, backlog item 5: the section is `storage`; it works as a DSA broker's `/data`).

## Context
The owner asked for a store in the broker where people create nodes of any structure and set their values, for preprocessing. A DSA broker has it at `/data`: the root offers Add Node, Add Value {Name, Type, Editor}, Publish {Path, Value, Timestamp} (creates the path and sets the value), Export and Import (JSON); every data node offers the same Add actions plus Delete Node {Recursive}, Rename Node, Duplicate Node, Export and Import; values are writable (`write`), every action needs `write`, and the broker keeps the tree and the values across restarts.

## Decision
- **A site section of its own:** `wy/<site>/storage/**` (spec 01 0.2.2), served by a responder inside `wyrmd` (crate `wyrm-storage`, a link with root `wy/<site>/storage`, link id `storage`). It is broker data, not control-plane state: like the historian (ADR 0014) it is a second documented exception to principle 3, in its own file.
- **Nodes as in DSA**, names are key segments (no display names, backlog item 2):
  - root: `add_node {name}`, `add_value {name, type, editor}`, `publish {path, value}`, `export`, `import {data | file}`;
  - a folder: `add_node`, `add_value`, `delete {recursive}`, `rename {name}`, `duplicate {name}`, `export`, `import {data | file}`;
  - a value: `~set` (writable `write`), `delete`, `rename {name}`, `duplicate {name}`. A value has no children (a WYRM leaf), unlike a DSA node.
  - `type`: `string`, `number`, `bool`, `array`, `map`, `binary`, `dynamic` (spec 02 type codes); a set of another type is refused, `dynamic` takes any. `editor` (`none`, `textarea`, `date`) is kept as `attr.editor` for UIs. No `password` editor: anyone with `read` reads a storage value, and secrets never go in the tree (principle 6).
  - `delete` of a folder with children needs `recursive` (as DSA). `rename` and `duplicate` refuse a name a sibling has.
  - `publish` creates the missing folders and a `dynamic` value at the end of `path` (relative to `storage`), then sets the value; a path through a value, or to a folder, is refused. No timestamp and no open stream (DSA's `CloseStream`).
  - `export` answers the subtree as JSON text (`{"<child>": {"$type": "number", "@editor": "textarea", "?value": 21.5}, "<folder>": {...}}`, as DSA); binary values are `{"$hex": "…"}`. `import` replaces a folder's children with such a JSON, given as text (`data`) or as a file (`file`, `editor: file`, so the gateway takes it over `POST /api/invoke` when it is larger than a WebSocket frame, ADR 0011); other `$`/`@` keys (a DSA export's `$is`, `$name`) are ignored. The whole import is checked (names, types, values, limits) before anything changes. `type` and `editor` travel as text, as every action's choices.
- **Rights as in DSA:** every action and every `~set` needs `write` on the node. Trusted keys: the admin keys; the user gateway's (users' grants decide; default roles: viewer `read`, operator `write`, engineer `config`); the flow engine's at `write` (a flow's `set`/`invoke` sinks may target `wy/<site>/storage/**`, ADR 0008 amended); an upstream site reads it (`~meta`, `~val`) like the other sections. Roles already changed in a users store keep their grants; an admin adds `storage` grants to them.
- **Persistence:** `data_dir/storage/storage.redb`, one record per node (`path → {type, editor, value, t}`); structure changes are written at once, values at most once a second (a crash loses at most the last second of values, as DSA's debounce). `wyrmd` opens the file once (redb allows one open per file) and hands it to every start of the link; it is flushed when the link stops and when the store is dropped. On start the tree is declared again and the last values are published with their times.
- **Limits:** 10 000 nodes, 16 levels, 32 KiB per value (CBOR; half the gateway's 64 KiB WebSocket frame), 64 MiB for all records together (CBOR), 4 MiB per import and per export. `add_*`, `duplicate`, `publish` and `import` count toward the node and size limits; an export stops as soon as its text passes the limit.
- **Reserved id:** a new link may not be called `storage`. A registry that holds a link of that name (installed before spec 0.2.2) still loads, but `wyrmd` refuses to start: the link would share the storage's audit records, overlays and logs. Remove it with the previous `wyrmd` first.
- **History:** the historian can watch storage values (`wy/<site>/storage/…`), and they get `attr.history` (ADR 0016).

## Consequences
- Anyone with `write` on `storage` can grow it up to the limits; the SDK's rate limits apply to `~set` and actions (50 per second per caller, burst 100). A flow is one caller: all its `set` and `invoke` sinks into `storage` share that budget, and requests above it are refused (`rate_limited`) and counted in the next audit record.
- Every `~set` and action is audited (one record in the HMAC-chained audit journal, arguments as SHA-256), as on every link. A flow that writes a storage value 20 times a second adds 20 records a second, as one that writes a device does; the audit journal is not trimmed today. That growth is the audit's, not the storage's: the storage file holds one record per node.
- Values written faster than once a second keep only the last one per second on disk; every value is still published at once.
- Attributes set by people (`~set?field=attr.`) are not supported yet (as for links, ADR 0003 TODO); `editor` comes from `add_value` and `import`.

## Alternatives
- **Registry WAL for values:** every set would append a record that is never deleted.
- **A link package:** the store belongs to the broker (backup, rights, the flow engine's targets), not to a replaceable connector.
