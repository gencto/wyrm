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
| DEP-1 | fixed (`bd4b0f6`) | wasmtime `=36.0.20` (LTS line, `rust-version` 1.86): `cargo audit` reports no wasmtime advisory. CI job `audit` runs `cargo audit`; each ignored ID has its reason in `.cargo/audit.toml`. |
| DEP-2 | fixed / accepted (`bd4b0f6`) | tokio 1.54.1 and rustls-webpki 0.103.16 by `cargo update`. Accepted, with reasons in `.cargo/audit.toml`: rsa (Marvin, ADR 0029 item 8), the rustls pin (ADR 0029 item 6), webpki 0.102 (rumqttc names only its error type), lz4_flex (Zenoh compression is off), lru (unsound only on a panic inside it). Unmaintained crates are warnings. *If wrong:* an advisory we judged unreachable is reachable; `cargo audit` keeps listing it until the entry is removed. |
| ADM-1 | gap | One uid per process link needs a privileged broker or systemd `DynamicUser=`. Until then: run `wyrmd` as its own user, keep process links to trusted packages. |
| AI-1 | next (9) | Approval bound to the payload: claim `h` (spec 04), checked by the MCP server and the SDK. |
| D-1 | fixed (`ae78b65`) | `Pki::issue` keeps a certificate only while it is for the same CN and SANs and has more than 30 days left; an hourly check renews due ones and rebuilds. Enrollment: a downstream asks again with the same key within 30 days, the upstream re-signs (`Op::RenewBroker`, audit `renew`). Files for `peers.downstream` issued by `wyrmd ca` are renewed in place only: copy them again (README). Not yet: a `sys` value with the expiry. |
| SDK-1 | fixed (`cb9875a`) | Grant before replay check, quarter of the cache per `sub` (spec 04 0.2.12, ADR 0029 item 3 amended). |
| FLOW-1 | fixed (`d5d2548`, this commit) | Spec 06 0.2.13 step 9: `subscribe` and `liveliness` keys only under the own site's `downstream`, `dataflows`, `storage`; checked at deploy, validate and when a stored flow starts. At deploy the deployer must also read each source: the first grant of its `auth` that touches the key must give `read` and cover all of it (a pattern too). *If wrong:* a flow that read another site or `upstream` must be deployed on that site instead (ADR 0018 lets an upstream deploy below). |
| ADM-2 | fixed (this commit) | A token or `allow_all_links` admits a downstream broker only when it names no relayed sites; with `via` it waits for Authorize. `via` ≤ 16 valid names, checked before anything is kept and again at admission. |
| ADM-3 | fixed (`d5d2548`, this commit) | `watch_audit` drops a record over 8 KiB unread, cuts `sub`/`op` to 256 B and `key` to 1 KiB. Links over the network (and unknown ids) get at most 50 records per second each (burst 200); in-process links (flows, storage, scheduler, DQL, embedded drivers) are not limited, as their SDK already limits the requests. Dropped records are reported as `audit_dropped` every 10 s and in the link's next record. |
| GW-1, GW-7 | fixed (`cb9875a`) | A refused login is audited once per `(user, ip)` and window; the limiter runs before a hashing permit. |
| GW-2 | next (12) | Per-user caps on sockets, stream opens and one-shots; server cap on `history.limit`. |
| SCH-1 | fixed (`86d5f69`, DQL-2 fix) | Targets write only within their author's rights, read with the first intersecting grant. |
| WASM-1 | next (11) | Install shows the package's `capabilities` and `requester`; widening them needs `accept: true`. |
| LNK-1, FS-4, AI-3 | next (13) | One outbound-address policy: loopback, link-local, metadata and private addresses only with `allow_internal`, checked on the resolved address. AI-3 also: `api_base` a `dest` of the API key. |
| LNK-2 | fixed (`15f43c8`) | The owner task runs `open`, `poll`, `ping` and the whole serve loop under `catch_unwind`: a panic is a connection failure (`failed`, error `driver panicked: …`, points `bad`), then the usual backoff and reconnect. Test `driver_panic`. |
| AI-2 | gap | MCP service identity (a `LimitedKey` like agent keys). Until then the guide says `ai.key` is an admin key. |
| AI-4 | next (14, docs) | The guide calls `config` and `never` modes "autonomous writes from text in the tree". |
| NET-1 | fixed (`e4a2a43`) | `NetPolicy::allows_named`: a name entry reaches public addresses only; private (RFC 1918, `100.64/10`, `fc00::/7`) and special addresses need an IP entry. Plain TCP by name stays allowed under the same rule. *If wrong:* a link that reached a LAN database by name alone fails to connect until its `net` gets the address. |
| DQL-1 | fixed (`234b5de`) | One event runs at most 2 000 CEL evaluations per query (natively also 100 ms); the rest of the dependent rows wait in a backlog that the next ticks drain at once. `matches()` needs a literal pattern of at most 16 KiB compiled. Not done: counting function calls inside one evaluation (bounded by the per-row lookup and time limits). |
| DQL-2 | fixed (`f8a5d6c`) | `wyrm_core::ptok::level_on`: the first intersecting grant decides, as the gateway and the SDK (a test compares it with Zenoh's `intersects`); `Who::may`, `Who::may_for` and so `Rights::may` and DQL use it. A grant with `$*` that may touch the key gives `none`. Accepted: own-site grants are still read for another site's key (as the gateway does for downstream sites); the host admits another site only within the link's grants, which the admin gives for reachable sites only. *If wrong:* a user's own-site grants count on a reachable downstream site in a query, as they do at that site's gateway path. |
| FS-1 | partly fixed (`e355391`), next (15) | Disk floor 1 GiB done. Open: link-level spool budget, periodic sweep, `max_file_mib` ≤ 65 536. |
| HS-1 | fixed (`ca1bff2`) | `TargetError::Refused` for data errors (InfluxDB 400/413/422, PostgreSQL classes 22/23 and 54000, MySQL data codes, MongoDB 2/14/10334/17280, DynamoDB item size): the batch is written again row by row, refused rows are skipped, counted in `rows_refused` and logged by key and time. The very first rows since start all refused is still a stop. InfluxDB writes one float `value` and a string `value_text`. *If wrong:* a refusal we class as data hides a schema problem; the rows are skipped, and `rows_refused` and `error` show it. |
| HS-2 | next (16) | `changes` merges day files by `seq` and stops early. |
| HS-3 | fixed (`9208b8a`, `cb9875a`) | Host random nonce (world 0.3.0); server signature compared in constant time. |
| HS-4 | fixed (`cb9875a`) | A refused URL is not echoed. |
| HS-6 | fixed (`ca1bff2`) | InfluxDB `measurement` may not start with `#` or `_`. |
| ADM-7 | fixed (`cb9875a`) | Only a missing `secrets.bin` is an empty store. |
| LNK-3 | fixed (`cb9875a`) | A response is private only when its scopedPDU was encrypted. |
| ADM-4, ADM-5, ADM-6, GW-3, GW-4, GW-5, GW-6, D-2, D-3, D-4, D-5, D-6, D-7, D-8, SDK-2..7, WASM-2, WASM-3, LNK-4..6, AI-5..8, NET-2..5, PORT-1..3, DQL-3..5, FS-2, FS-3, FS-5, FS-6, HS-5, HS-7, HS-8, DQL-TRUST-1 | next (after the items above) | Low. Each gets a line in this table when it is fixed or accepted. |
| I-GW-1 | fixed (`cb9875a`) | README and CLAUDE.md say the admin trusts the gateway key. |

## Rules
1. A finding is closed only with a control and a test (as in `threats.md`).
2. A spec change goes with a CHANGELOG line, as always.
3. An accepted finding says what it costs if the decision is wrong.
