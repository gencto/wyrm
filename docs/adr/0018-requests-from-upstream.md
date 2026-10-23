# ADR 0018 — Requests from upstream sites

**Status:** accepted · 2026-10-24 (owner decision, backlog item 1: a downstream accepts `write` from above on `downstream`/`dataflows` always; `config` on `sys` only when that downstream allows it explicitly). Reverses the "read-only upstream" of ADR 0007.

## Context
An upstream broker shows its downstream sites in its tree (ADR 0007, 0015), but nobody there can set a value or run an action on them: the downstream's ACL drops every `~set`/`~act` query from `broker:<upstream>`, the downstream's links trust only their own site's keys, and the upstream's gateway refuses non-read operations on downstream sites.

A DSA broker lets requests through: the downstream names a permission `Group` on each upstream connection (`sys/upstream/<name>/group`), and a request from above is checked twice, by the upstream against its user's permissions and by the downstream against that group. WYRM keeps both checks with the means it has: the router ACL, `ptok` signatures and the `LimitedKey` caps of ADR 0004/0013.

## Decision
- **What a downstream accepts from each upstream** (one flag per upstream entry, as DSA's group, fixed to the owner's two levels):
  - always `write` on `wy/<d>/downstream/**`, `wy/<d>/dataflows/**` and `wy/<d>/storage/**` (the broker storage of ADR 0017 is device-like data; DSA's group covers `/data` too);
  - `config` on `wy/<d>/sys/**` only with `allow_config` on that upstream: `wyrmd.json5` `peers.upstream[].allow_config`, or `sys/upstream/<u>/allow_config` (writable at `config`) for one added at runtime. A change rebuilds the broker (the ACL changes).
- **Router ACL on the downstream.** For the own site and the sites it relays: ingress `query` and egress `reply` on `…/{downstream,dataflows,storage}/**/~set` and `…/**/~act/*` for every upstream (`upstream-write-in`/`-out`); the same on `…/sys/**` only for an upstream with `allow_config` (`upstream-<u>-config-in`/`-out`, subject `upstream-<u>`). A relayed site's `sys` needs `allow_config` at every hop (edge for central, plant for edge), as DSA checks the group at each broker.
- **Keys: the upstream publishes them, the downstream follows them.** A token for a key of site `d` carries `site = d` and is signed at the upstream (its gateway, or an operator's admin key). The upstream's admin publishes `wy/<u>/sys/signing_keys` = `{<site>: [key…]}`: its own admin keys and gateway key, and the keys it learned from its own upstreams (so plant, below edge, trusts central's keys too). Never a flow key: flows do not reach other sites (owner decision 8).
  - The downstream's admin asks each upstream for it every 10 s over the peer link (ACL: `signers-<u>-out`/`-in` here, `signers-<d>-in`/`-out` there, exactly that key). It is checked (at most 16 sites, 8 keys each, 32-byte keys) and stored in the registry (`Registry::signers`, SCHEMA 17). Only a real change rebuilds the broker, so a reconnect does not loop; the first connection to an upstream rebuilds once. Keys of an upstream that is gone are not trusted.
  - Every key is trusted as a `LimitedKey`, never as an admin key: links at `write` under `wy/<d>/downstream`, the flow engine under `wy/<d>/dataflows`, the storage under `wy/<d>/storage`, and the admin at `config` under `wy/<d>/sys` only for an upstream with `allow_config`. The token's own grants and `max` still apply: the effective right is the smaller of the user's grant at the upstream and the downstream's cap.
- **Gateway on the upstream.** `set` and `invoke` on a downstream site are allowed (WebSocket and `POST /api/invoke`). The user's grants are checked as for the own site (`wy/<d>/x` as `wy/<u>/x`, as reads already were), and the token is minted for site `d` with the own-site grants rewritten to `wy/<d>/…` (`wy/**` grants stay) and the subject `user:<name>@<u>`, so the downstream's audit names where the user came from. Grants are therefore a policy for every site below: an operator on the upstream writes every downstream site's devices, as far as each downstream allows.
- **Clocks.** Tokens live 5 minutes (`PTOK_TTL`) and are checked against the downstream's clock: sites must keep their clocks within a few minutes (NTP).

## Consequences
- A downstream that trusts an upstream for `write` trusts every site above it (the keys come through its upstream); refusing that means not connecting to that upstream.
- Requests from above are audited on the downstream like local ones (`sys/audit/<link>`, subject `user:<name>@<site>`) and share the per-caller rate limits.
- An operator at the upstream with an admin key reaches a downstream with a token for that site (`SigningTokens::new(key, "<d>")`); `wyr` keeps the own site by default.
- Rotating a key at the upstream reaches the downstream within about 10 s, with one rebuild.

## Alternatives
- **Keys in the enrollment answer** (ADR 0015): `wyrmd.json5` upstreams never enroll, and a rotated key would need a new enrollment.
- **Keys typed into `sys/upstream`:** manual, and a chain would need central's keys typed at plant.
- **The downstream re-signs requests from its upstream:** Zenoh routes queries end to end; the downstream sees no hop where it could.
