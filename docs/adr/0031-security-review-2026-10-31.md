# ADR 0031 — What we do with the security review of 2026-10-31

**Status:** accepted · 2026-11-01 (decided under ADR 0029: the owner delegates the decisions; each rule is written down here and in the guide it touches).

## Context
`docs/security/review-2026-10-31.md` lists the findings of a code review at `b97d0b2`, with an addendum for `d68c415`. Four commits made after `d68c415` and before this ADR (`86d5f69`, `84e2e87`, `e355391`, `9208b8a`) already changed some of them. This ADR gives every finding one disposition:

- **fixed**: a control and a test that shows it are in `main` (the commit is named);
- **next**: will be fixed, in the order of the table;
- **accepted**: stays as it is, for the reason given (*if wrong* says what it costs);
- **gap**: needs platform work, listed in `docs/backlog.md` §12 "Known gaps".

The table is updated in the commit that changes a status.

## Dispositions

| ID | Disposition | Note |
|---|---|---|
| DEP-1 | next (1) | wasmtime `=36.0.20` (LTS, `rust-version` 1.86): fixes every advisory that applies (RUSTSEC-2026-0327 needs `component-model-async`, which is off). `cargo audit` in CI with each ignored ID explained in `.cargo/audit.toml`. |
| DEP-2 | accepted / next (1) | rsa (Marvin) and the rustls pin: ADR 0029 items 8 and 6. tokio and rustls-webpki 0.103: `cargo update`. webpki 0.102 (rumqttc) and lz4_flex (Zenoh compression is off), lru (panic inside the LRU only), unmaintained crates: accepted, tracked by `cargo audit`. |
| ADM-1 | gap | One uid per process link needs a privileged broker or systemd `DynamicUser=`. Until then: run `wyrmd` as its own user, keep process links to trusted packages. |
| AI-1 | next (9) | Approval bound to the payload: claim `h` (spec 04), checked by the MCP server and the SDK. |
| D-1 | next (3) | Re-issue a certificate 30 days before `not_after`; enrollment re-signs the stored CSR. |
| SDK-1 | fixed (this commit) | Grant before replay check, quarter of the cache per `sub` (spec 04 0.2.12, ADR 0029 item 3 amended). |
| FLOW-1 | next (8) | Flow sources only under the own site's `downstream`, `dataflows`, `storage`. |
| ADM-2 | next (10) | `via = []` on the token and auto paths; relays only through Authorize; `via` ≤ 16. |
| ADM-3 | next (7) | Audit text fields ≤ 256 B, per-link token bucket with a `suppressed` record. |
| GW-1, GW-7 | fixed (this commit) | A refused login is audited once per `(user, ip)` and window; the limiter runs before a hashing permit. |
| GW-2 | next (12) | Per-user caps on sockets, stream opens and one-shots; server cap on `history.limit`. |
| SCH-1 | fixed (`86d5f69`) | Targets write only within their author's rights. DQL-2 still applied to it until item 2. |
| WASM-1 | next (11) | Install shows the package's `capabilities` and `requester`; widening them needs `accept: true`. |
| LNK-1, FS-4, AI-3 | next (13) | One outbound-address policy: loopback, link-local, metadata and private addresses only with `allow_internal`, checked on the resolved address. AI-3 also: `api_base` a `dest` of the API key. |
| LNK-2 | next (6) | `catch_unwind` around driver calls in the owner task; a panic marks the connection failed, values bad, then reconnects. |
| AI-2 | gap | MCP service identity (a `LimitedKey` like agent keys). Until then the guide says `ai.key` is an admin key. |
| AI-4 | next (14, docs) | The guide calls `config` and `never` modes "autonomous writes from text in the tree". |
| NET-1 | next (5) | Private ranges are a class that a name entry does not open. |
| DQL-1 | next (4) | One evaluation budget per event, regex compiled once, function calls counted. |
| DQL-2 | next (2) | One grant evaluator (first intersecting grant, as spec 04) in `wyrm_core::ptok`, used by `Rights::may` and DQL; other sites only through peers. |
| FS-1 | partly fixed (`e355391`), next (15) | Disk floor 1 GiB done. Open: link-level spool budget, periodic sweep, `max_file_mib` ≤ 65 536. |
| HS-1 | next (2b) | A refused batch is retried row by row; refused rows are skipped and counted; InfluxDB writes a stable schema. |
| HS-2 | next (16) | `changes` merges day files by `seq` and stops early. |
| HS-3 | fixed (`9208b8a`, this commit) | Host random nonce (world 0.3.0); server signature compared in constant time. |
| HS-4 | fixed (this commit) | A refused URL is not echoed. |
| ADM-7 | fixed (this commit) | Only a missing `secrets.bin` is an empty store. |
| LNK-3 | fixed (this commit) | A response is private only when its scopedPDU was encrypted. |
| ADM-4, ADM-5, ADM-6, GW-3, GW-4, GW-5, GW-6, D-2, D-3, D-4, D-5, D-6, D-7, D-8, SDK-2..7, WASM-2, WASM-3, LNK-4..6, AI-5..8, NET-2..5, PORT-1..3, DQL-3..5, FS-2, FS-3, FS-5, FS-6, HS-5..8, DQL-TRUST-1 | next (after the items above) | Low. Each gets a line in this table when it is fixed or accepted. |
| I-GW-1 | fixed (this commit) | README and CLAUDE.md say the admin trusts the gateway key. |

## Rules
1. A finding is closed only with a control and a test (as in `threats.md`).
2. A spec change goes with a CHANGELOG line, as always.
3. An accepted finding says what it costs if the decision is wrong.
