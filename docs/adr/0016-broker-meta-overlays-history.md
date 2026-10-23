# ADR 0016 — Broker-held meta overlays; `attr.history`

**Status:** accepted · 2026-10-23 (owner decisions, backlog item 10: overlays, an array of keys, existing watches included).

## Context
The owner asked that a recorded point carry the path of the store that records it (`@history`), and that the explorer mark such a node with an icon that opens its history. A point's `~meta` belongs to its link; the historian lives in the broker.

A DSA broker does this with attributes it holds itself: `setAttribute` on a node of a link is stored by the broker (override attributes, persisted per path) and merged into that node's attributes in every answer; the historian sets `@@getHistory = {"@": "merge", "val": [<path of its Get History action>]}` on each watched node, the UI marks the node (`hasHistory`), and the broker aliases `<node>/getHistory` to the store's action.

WYRM requests reach a link's queryable directly; the broker does not proxy them, so it cannot merge on the way.

## Decision
- **Overlays are broker state, merged by the link's SDK.** The admin publishes one CBOR map per link at `wy/<site>/sys/overlays/<link>/~val`: `{<node path>: {<attr name>: value}}`. The SDK reads it (`get`, then subscribe) and keeps it as a separate layer: a re-declared node keeps its overlay (principle 3: links re-declare their tree). On output it merges the layer into `~meta` (`attr`) and into the `view=list` summary; a change bumps the node's `rev` (and its parent's, whose list changed) and republishes `~meta`.
- **Today's only source is the historian, and the content is derived.** `attr.history` of a point is the array of the watch node keys that record it (`wy/<site>/sys/history/<group>/<watch>`), computed from the registry's watches; nothing new is persisted, existing watches show up at once, and every broker build publishes the maps again (the memory storage starts empty). A disabled watch stays in the list; Unsubscribe removes it. A link's own `attr.history` (a link that records points itself) is merged with it as a union.
- **The SDK accepts only known names** (`history`): a forged sample on the overlay key cannot rewrite `display` or anything else. Only the admin writes `sys/**` in `prod`; each process or external link may query and subscribe its own overlay key and nothing else under `sys`.
- **Spec 02 0.2.1:** `view=list` summaries carry key 16 `has_history` (true when `attr.history` is not empty), so a tree or a Metrics row shows the icon without a `~meta` per row. `attr.history` is an array of store keys: a key under `wy/<site>/sys/history/` is that site's historian, which answers at the point's own key (`<point>/~val?history=`, rights as reading the value, D2); any other store key answers `<store>/~val?history=` itself.
- **Explorer:** a history icon after the name of a node with `has_history`/`attr.history`, in the tree and in Metrics rows; a click opens the history window (as View History) on that point, with the store's name; several stores: a picker.
- **General channel, one source:** any attribute the broker holds for a node can use it later (`~set?field=attr.<name>` from people, the ADR 0003 TODO); it is not built now.

## Consequences
- A point on a downstream site recorded by our historian gets no `attr.history`: its link belongs to another broker. Revisit with backlog item 1 (actions on downstream brokers).
- One map per link: 10 000 watches on one link make a map of about 1 MB, sent again on each watch change (rare).
- Clients that cache `~meta` by `rev` see the change: the overlay bumps `rev`.

## Alternatives
- **A history index next to the tree** (`<point>/~hist`): not in the meta, a new suffix in spec 01.
- **Links set it themselves:** cannot cover the broker's historian.
- **The explorer asks the historian per row:** a query per row, and every other client would need the same code.
