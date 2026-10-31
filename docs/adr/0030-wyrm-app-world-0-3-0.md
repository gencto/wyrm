# ADR 0030 — World `wyrm:app@0.3.0`: TLS and a random source for WASM apps

**Status:** accepted · 2026-11-01 (decisions of 2026-11-01: a new world beside the frozen ones, the three imports, the bound on random bytes, the manifest `world` with its version, the SCRAM nonce from the host, the packages rebuilt as 0.3.0, an e2e through an installed package).

## Context
`Host::tls_connect` and `Host::tls_upgrade` exist in `wyrm-link-api` since ADR 0026. The native and process hosts (`wyrm-link-portable`) have them. The WIT worlds `wyrm:app@0.1.0` and `@0.2.0` have no such imports, and both are frozen. So a WASM component answers `not_supported` to TLS. The history sync packages (`postgres`, `mysql`, `mongodb`, `influxdb`, `dynamodb`) are WASM packages by default, so they reached only plain databases.

A component also has no random source. The SCRAM nonce of PostgreSQL and MongoDB is hashed from the clock, a counter and the connection: unique, but guessable.

## Decision
- **A new world `wyrm:app@0.3.0`** (`crates/wyrm-wasm-host/wit/app3/app.wit`). It is 0.2.0 with every function and export unchanged, plus three host imports:
  - `tls-connect(host, port, timeout-ms, ca-pem?) -> result<u32, list<u8>>`;
  - `tls-upgrade(conn, host, timeout-ms, ca-pem?) -> result<_, list<u8>>`;
  - `random-bytes(n) -> result<list<u8>, list<u8>>`.

  Errors are CBOR `{status, msg}`, as in the other imports.
- **0.1.0 and 0.2.0 stay frozen.** The host links all three versions. 0.3.0 has the exports of 0.2.0, so the host tells it by its import `wyrm:app/host@0.3.0` (`AppWorld::pre`, `app_version`). A component that imports no host function is told by its exports, as before. A `wyrm:app/host` version that the host does not run is refused at load (`Denied`).
- **The same services in every mode.** The WASM host forwards the three imports to the `BufferHost` of the call, and so to the `RuntimeServices` that the native engine uses. The `net` allowlist (`NetPolicy::allows_named`), the time budget of the call, the 4 connections and the host-name rules of ADR 0026 are therefore the same. An address outside `net` gives `permission_denied`, as for `tcp-connect`. The keys stay in the host: the guest sees a connection id and plain bytes through `tcp-send` / `tcp-recv`.
- **Random bytes.** `Host::random_bytes(n)` and `Services::random_bytes(n)`, with a default `not_supported`. `BufferHost` refuses `n` above `MAX_RANDOM_BYTES` (1024) with `invalid_parameter`, before the services see it. `RuntimeServices` fills the bytes from the OS (`getrandom`, already in the workspace).
- **The SCRAM nonce** (`wyrm_history_sync::scram::nonce(host, conn)`) takes `random_bytes(18)`. Only a host without a random source (a component of 0.2.0, a test host) falls back to the clock hash (`nonce_from_clock`).
- **The guest and the packages.** `wyrm-link-guest` builds components of 0.3.0, so the scheduler, DQL, the five history sync links and `examples/links/portable` build as 0.3.0. `wyr link pack` writes the version into the manifest: `world: "wyrm:app@0.3.0"`. The broker checks a versioned `world` against the component's version. A plain `app` still takes any version, so old packages install as before.

## Consequences
- A WASM history sync package reaches a TLS database through the same host code as its process twin.
- SCRAM nonces in every mode built since this ADR come from the OS.
- A package built for 0.2.0 keeps working, but has no TLS. It must be rebuilt to get it. Its manifest may say `app` or `wyrm:app@0.2.0`.
- A broker older than this ADR refuses a manifest that says `wyrm:app@0.3.0` (an unknown world). It could not run such a component anyway.
- Tests: `every_app_world_version_loads` and `an_unknown_app_world_version_is_refused` (`wyrm-wasm-host`), `tls_and_random_as_native` (`links/wasm`: the same component and native app against a local TLS server), `wasm_app_world_0_3_0_has_tls_and_random` (`wyrmd` e2e: an app package built from source and installed from Zip).

## Alternatives
- **Change 0.2.0 in place.** Components built on 0.2.0 import the old interface; a changed 0.2.0 would refuse them or make two different 0.2.0 worlds. Refused.
- **WASI (`wasi:sockets`, `wasi:random`).** A second, larger import surface beside `wyrm:app/host`, and TLS would then live in the guest with its keys. Refused: the host already has rustls and the allowlist.
- **Randomness in the guest** (a seeded generator). The seed would still come from the clock. Refused.
