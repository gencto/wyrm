# ADR 0020 — History of a downstream site's point, as seen through this site

**Status:** accepted · 2026-10-28 (owner decision: support it as DSA does).

## Context
A site's historian may watch a point of a downstream site (central records `wy/edge/downstream/lab/bench/rig1/wave`). ADR 0016 left such points without `attr.history` (their link belongs to another broker), and the historian answers `~val?history=` only on its own site's keys, so the rows were recorded but could not be read, and the explorer had nothing to show.

A DSA broker keeps override attributes on the node as the broker sees it (`RemoteNode.overrideAttributes`, persisted per path by that broker, not forwarded below), so `@@getHistory` set through central shows to central's clients only. A Get History on the point is an alias: the broker runs the store's action named in `@@getHistory`, after checking the caller's permission on the point and on the store (`broker-dart/lib/src/broker/responder.dart`, `invoke`).

## Decision
- **The overlay lives in the site that records.** The admin publishes the points of other sites its historian records at `wy/<site>/sys/overlays/.sites/~val`: `{<point key>: {"history": [<watch keys>]}}`. `.sites` cannot be a link id (they may not start with `.`).
- **The gateway lays it on**, as the DSA broker does for its remote nodes: on `meta`, `children` and `list` of a key of another site, it merges `attr.history` (union) and `has_history` (spec 02 key 16). A change of the map sends `changed` for each affected child of an open `list`, so the mark shows without selecting the node again.
- **The store is read at the watch key.** The historian answers `wy/<site>/sys/history/<group>/<watch>/~val?history=` for every watch (the rows of its point). Points of the own site keep answering at the point key too (ADR 0016, D2). Spec 02 0.2.7: a `sys/history` store of another site's point is read at its own key.
- **Rights are the DSA double check, in the gateway:** a `history` read at a watch key in this map needs Read on the point's `~val` (as reading it at the point); any other key under `sys` keeps its own check. Nothing reaches the downstream site: the rows are this site's.

## Consequences
- Clients that do not go through a gateway (`wyr`, FFI, MCP) do not see foreign overlays; they can read `sys/overlays/.sites` (admin) and the watch key.
- A point recorded both here and on its own site shows both stores; the explorer offers the choice (ADR 0016).
- No queryable of this site lives in another site's keys: a read of that point's value never waits on this broker.

## Alternatives
- **Answer at the point's key on the downstream site's keys** (`wy/edge/…/~val`): every value read of that point would also route to this broker and wait for it; two historians could answer one query.
- **Forbid watches on other sites' points:** simpler, but not as DSA, and the owner chose support.
