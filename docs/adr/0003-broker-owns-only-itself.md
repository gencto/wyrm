# ADR 0003 — The broker owns only itself

**Status:** accepted · 2026-10-20

## Decision
`wyrmd` persists and restores only control-plane state (connector registry, ACL, PKI, profiles, flow definitions, users) via WAL + postcard snapshot. The node tree is owned by connectors, which re-declare it on every (re)connect; last values are owned by storage and refilled by live owners. What is not re-declared does not exist.

## Why
Instant restart without a zero-copy index; no second source of truth; the same liveliness signal that requesters see defines "connected".
