# spec changelog
- 0.1.0 (2026-10-20): initial — 01–06, tables.json, 22 fixtures.
- 0.1.1 (2026-10-20): 06 — `permissions.maxperm` ≤ `write` (validation step 7). No fixture change.
- 0.1.2 (2026-10-20): 02 — profiles: `"extends"` text key, inheritance rules, `?expand=true`; fixture `profile_extends`.
- 0.1.3 (2026-10-20): 04 — `origin` bound to the token subject (`sub` or `<sub>/...`). No fixture change.
- 0.1.4 (2026-10-21): 06 — flow `~val` gets optional `deployed_by`. No fixture change.
- 0.1.5 (2026-10-21): 01 — peer broker nodes: downstream sites at `down/<d>`, upstream at `up/<u>` (`wy:broker`, `attr.root`, `connected`); `up/` is no longer a reserved virtual prefix. No fixture change.
- 0.1.6 (2026-10-22): 02 — UI fields: action `display`, `group`; param-meta `display`, `description`, `placeholder`, `editor` (`password`, `textarea`); fixture `meta_action_ui`.
