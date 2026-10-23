# ADR 0001 — Zenoh as transport, WYRM as semantics

**Status:** accepted · 2026-10-19

## Decision
Eclipse Zenoh 1.x is the transport and data fabric (routing, pub/sub, query/reply, liveliness, storage, TLS/ACL, mesh). WYRM adds DSA semantics strictly on top: key-space conventions, CBOR attachment header, SDKs, and three static plugins compiled into a single `wyrmd` binary. Zenoh itself is never patched or forked.

## Consequences
- Dynamic Zenoh plugins (`.so`) are not used (ABI lock-step with the router).
- Extension happens through data (`dataflows/**`) and processes (connectors), not plugins.
- Per-message authorization is done in the responder SDK and gateway, not in the router (no public interceptor hook).
