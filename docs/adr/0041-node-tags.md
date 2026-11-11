# ADR 0041 — Node tags: `attr.tag`, tags held by the broker, tags in `view=list`

**Status:** proposed · 2026-11-11 (owner question of 2026-11-11: does WYRM need a tag system next to DQL, or is meta enough, "something like Haystack"?). Open questions for the owner at the end.

## Context
People want to find points by what they are, not by where a driver put them: "every supply air temperature on floor 2", "every meter", "everything of AHU 3 across two PLCs". Project Haystack answers this with marker tags (`ahu`, `discharge`, `air`, `temp`, `sensor`) and refs (`equipRef`, `siteRef`, `spaceRef`) on a flat list of records. Brick does it with an RDF class model.

What WYRM has today:
- **`attr.tag`.** `~meta?view=keys&match=tag:<str>` tests membership in `attr.tag` (an array of strings, or one string) (spec 01, `KeyFilter`, `crates/wyrm-link-sdk/src/tree.rs`). The spec has no definition of `attr.tag`. Nothing in the tree sets it except the fixture `meta_number_full` (`["hvac", "floor2"]`).
- **`is` and profiles** (`pub/<profile>/~meta`, `extends`, spec 02): the entity type, with inheritance and with `cfg`/`attr`/`actions`. This is more than a Haystack marker.
- **The tree itself.** Haystack needs `equipRef`/`siteRef` because its records are flat. Here `…/ahu1/supply_temp` already lies under `ahu1`, and the site is the first segment of every key.
- **DQL** (ADR 0025): `list … | where "hvac" in attr.tag` works across sites today.

Three things are missing:
1. **Tags from people do not survive.** A link re-declares its subtree on every (re)connect (principle 3), so an operator cannot keep `hvac` on a Modbus point. `<node>/~set?field=attr.<name>` is in spec 01, but the SDK answers `not_supported` (`runtime.rs`, "needs broker-owned persistence (ADR 0003)"). ADR 0016 built the channel for attributes the broker holds over a link's nodes and named this case as its next use. Today it carries only `history`.
2. **No convention.** Nothing says what a tag looks like, how profile tags combine with a node's own, or how Haystack or Brick names fit.
3. **Finding by tag is expensive.** When DQL reads `attr`, it fetches every listed node's whole `~meta` (`docs/dql.md`). A tree view cannot show tags without a `~meta` per row.

## Decision

### 1. Meta is the carrier; no separate tag service
Tags are part of a node's `~meta`, so every reader that can read the node sees them, with the node's own rights. There is no tag index, no `sys/tags/**` query API and no second store of node descriptions. A store like that would duplicate DQL and break principle 4. Search stays `view=keys&match=` (one link) and DQL (many links and sites).

### 2. `attr.tag` defined (spec 02)
- `attr.tag` is an **array of tag strings**, without duplicates. A responder that holds one string answers an array of one. Readers still accept a string (as `KeyFilter` does today).
- A tag is `[<ns>:]<name>`:
  - `ns`: `[a-z][a-z0-9]{0,15}`;
  - `name`: `[A-Za-z0-9_.-]{1,64}`;
  - the whole tag is at most 80 bytes, compared byte for byte.

  Tags without a namespace are the site's own, lowercase by convention (backlog: lowercase names). `hs:` is reserved for Project Haystack 4 marker names (`hs:ahu`, `hs:discharge`), `brick:` for Brick classes (`brick:Supply_Air_Temperature_Sensor`), and `wy:` for WYRM itself.
- At most 32 tags per node, after merging (§3). Beyond that, the SDK keeps the first 32 in merge order and logs once per node at `warn`.
- **Markers only.** A tag says that something *is* so. A fact with a value (a floor number, a rated power, a phase) is an attribute of its own (`attr.floor = 2`) or a `cfg` field, never `floor2` encoded as a tag. Spec 02 states this as guidance only: the SDK cannot check it.

### 3. Three sources, one union
A node's effective `attr.tag` is the union of the following, in this order, without duplicates:
1. **the node's own**, declared by its link (a driver can derive tags from its params: a Modbus point with `tags: ["hvac"]` in its `Params`);
2. **its profile chain**: `attr.tag` of `is` and of every `extends` above it. This is an exception to "own wins" in spec 02 profiles: for `tag` the chain is a union, so a profile `wy:ahu` with `["hs:ahu", "hs:equip"]` tags every node of that profile;
3. **the broker's**: tags people put on the node (§4), laid on as an overlay (ADR 0016).

Nobody can remove a tag that a link or a profile declares. A person adds tags; to change a link's own tags, they edit the link's config. This keeps principle 3: the link owns what it declares.

### 4. Tags from people: broker state, laid on by the SDK
- **Store.** The admin keeps `tags: {<node key>: [tag…]}` in the registry (`Op::SetTags`, SCHEMA 20, WAL and snapshot as every other registry change). It is part of the control plane the broker owns, and stage A of ADR 0036 replicates it to the standby with no extra code.
- **Scope.** A site holds tags for its own `downstream/<link>/**` (except downstream broker nodes), `dataflows/**` and `storage/**`. It holds none for other sites' nodes: a downstream site tags its own. An upstream operator does that through ADR 0018 requests to the downstream site's `sys/tags` (this needs `allow_config` for that upstream).
- **Write.** `wy/<site>/sys/tags/~act/set {key, tags}` replaces the person-held tags of one node, and `~act/edit {keys, add?, remove?}` changes up to 1 000 nodes at once. The token's `auth` (spec 04 0.2.10) must give `config` on every key (the level `~set?field=` already asks). Without `auth` the request is refused. A key the caller may not configure fails the whole request, and nothing is applied. Every change goes to the audit journal (`sys/audit`, keys and tags; tags are not secrets).
- **Read.** `~act/get {key}` → `{own, profile, broker}` for a caller with `read` on the key, so a UI can show where a tag comes from. `~act/known {prefix?}` → `[{tag, count}]` returns the person-held tags only, for autocompletion; it does not read the tree.
- **`~set?field=attr.tag` on the node** stays `not_supported` in the SDK. The node's responder is the link, and the link may not write the broker's state. Spec 01 points to `sys/tags` for this field.
- **Laying on.** `overlay_maps` adds `tag` beside `history` for each link (`FLOWS_LINK`, `STORAGE_LINK` included). `OVERLAY_NAMES` becomes `["history", "tag"]`, and `merge_attr` takes the union for `tag` as it does for `history`. A re-declared node keeps its overlay. A change bumps the node's `rev` and its parent's, and both are published again (ADR 0016, unchanged).
- **Orphans.** Tags of a key whose node is not declared now stay: the node may come back on the next connect (principle 3). Removing a link from the registry removes its tags. `sys/tags` shows `nodes` and `orphans` (keys of no declared node at the last check, at most every 60 s), and `prune {older_than_days}` removes orphans not seen since then. A renamed node loses its tags. `export` / `import` of `wyrm-tags/1` (JSON, a user file) moves them.
- **Bounds.** 100 000 tagged nodes per site, 32 person-held tags per node, a map of at most 4 MiB per link at `sys/overlays/<link>/~val`. Beyond these limits, `set`/`edit` is refused with `limit`.

### 5. Tags in `view=list` and in `match` (spec 02, spec 01)
- `view=list` summaries carry **key 18 `tags`**: the effective array (§3), absent when empty. With it, a tree, a Metrics row and DQL see tags without a `~meta` per row. The cost: up to about 2.5 KiB per row in the worst case, nothing for a node without tags.
- `match=tag:<t>` may repeat (`tag:hs:ahu;tag:floor2`, AND) and tests the effective tags. The `:` inside a namespaced tag is part of the value: the filter splits a test at its first `:`.

### 6. DQL
- A row gets `tags` (a list of strings) from the `view=list` summary. Reading it does not fetch the whole `~meta`, unlike `attr`.
- In the `filter` syntax, `#<tag>` is a test for a tag (`filter #hs:ahu #floor2 $type="number"`), turned into `"<tag>" in tags`. CEL stays `where "hs:ahu" in tags && "floor2" in tags`.
- No Haystack filter language (`ahu and not elec`): CEL already covers it, and two languages cost more than they give.

### 7. Haystack and Brick are vocabularies, not the model
- WYRM ships no ontology. `hs:`/`brick:` names are plain tags. The broker does not check that a combination makes sense (`hs:sensor` without `hs:point`).
- A vocabulary can be served as data later (`pub/` profiles such as `hs:ahu` that carry `attr.tag`, plus a list of names for autocompletion), without code in the broker.
- Interop (Haystack `read` by filter, Zinc/JSON export, Brick TTL export) is a later link or a `wyr` command over DQL. It is not part of this ADR.

### 8. Not now: refs
Relations across the tree (`hs:spaceRef`: this AHU serves these rooms; `feedsRef`) are what the hierarchy cannot express. When a concrete use comes, they will be `attr.ref.<name> = <full key>` laid on by the same overlay channel (one more name in `OVERLAY_NAMES`, the same `auth` check on both keys). Until then, no ref fields.

## Consequences
- Operators, flows (by `match`/DQL), Studio and the agent find points by tag across links and sites with one request per level.
- A link author gets tags for free from profiles; a person gets them without touching the driver config.
- Tags held by people sit on keys: a node that is renamed, or moved by a driver edit, loses them, and they show as orphans until pruned or re-applied by import.
- `view=list` rows grow by the tags they carry. A tree of 1 000 untagged children does not change.
- Rights stay those of the node: a reader who may not read a node sees none of its tags. `known` lists person-held tag names without keys, which a `read` user on `sys/tags` may see (tag names are not secrets).

## Alternatives
- **A tag index service** (`sys/tags/<tag>/<key>`): fast "all keys with tag X" on one site, but it is a second description of the tree that goes stale with every re-declare, and it does not cross sites. DQL does the same with the tree's own rights.
- **Haystack as the data model** (flat records, refs, defs/Xeto): ties WYRM to one ontology and duplicates the hierarchy. Keeping it as a namespace keeps the door open.
- **Tags only from links** (no broker store): the operator would edit each driver's config to tag a point, and embedded links (`storage`, `dataflows`) would need their own. The overlay channel exists already.
- **Person-held tags stored by each link** (framework `data_dir`): every SDK (native, portable, WASM, process) would need it, and principle 3 says the link owns only what it re-declares.
- **`~set?field=attr.tag` handled by the gateway**: covers only gateway clients, not `wyr` and flows with their own tokens.

## Changes (estimate)
- **spec 02**: `attr.tag` defined (§2), the profile union for `tag` (§3), key 18 `tags` in `view=list` (§5). **spec 01**: repeated `match=tag:`, the `field=attr.tag` write path, `sys/tags`. `gen.py`: `meta_view_list` with `tags`, `profile_extends` with a union of tags; regenerate; the Rust and Dart fixture tests; `CHANGELOG` 0.2.28.
- **wyrm-core**: `NodeMeta.tags` (key 18) in `meta.rs` and `profile.rs` (not inherited as a field; the chain union is computed from `attr.tag`).
- **wyrm-link-sdk**: `OVERLAY_NAMES += "tag"`, the union in `merge_attr`, the profile union on `expand`, tags in the `view=list` summary, `KeyFilter.tag: Vec<String>`, string → array normalization, the 32-tag cap. `Params` attribute `tags` for drivers (framework, optional).
- **wyrm-admin**: registry `tags` (SCHEMA 20, migration empty), `sys/tags` node and actions with the `auth` check, `overlay_maps` with `tag`, removal with the link, orphan check, export/import, audit.
- **wyrm-dql**: row field `tags`, `#tag` in `filter`, `explain` shows that no `~meta` fetch is needed.
- **gateway / Dart / Studio**: `tags` in `ListEntry`; Studio: tag chips in the tree and in properties, a tag editor over `sys/tags`, a filter by tag. MCP: `tags` in `tree` results.
- **Tests**: SDK unit tests (union, overlay survives re-declare, cap); e2e: tag a mock point, restart the link, the tag is back and `match=tag:` finds it; probe scenario `tags`.

## Open questions for the owner
1. Should person-held tags need `config` on the node (proposed, as `~set?field=`) or `write`?
2. Should an upstream site keep tags for downstream nodes itself (like ADR 0020 `.sites` for history), or only through the downstream site's `sys/tags` (proposed)?
3. Should a person be able to hide a link's or a profile's tag (`-tag` in the overlay), or only add (proposed)?
4. Refs (§8): now or when a use comes (proposed)?
