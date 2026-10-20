# ADR 0007 — Peer brokers: QUIC + mTLS, read-only upstream

**Status:** accepted · 2026-10-20

## Context
Iteration 4 connects brokers of different sites (plant → central, edge → cloud). Each site has its own CA (`wyrm-admin` PKI) and its own ACL (ADR 0006). An upstream site must see a downstream site's tree and values without becoming able to command its devices, and a peer CA must not be able to mint identities that the local ACL treats as links or operators. Full site names are used everywhere (spec 01), so routing needs no prefix rewriting.

## Decision
- **Config.** `wyrmd.json5` gets a `peers` section (`PeersSection` in `crates/wyrmd/src/lib.rs`):
  ```json5
  peers: {
    listen: "quic/0.0.0.0:7448",                  // only with downstream
    downstream: [{ site: "edge", ca: "edge-ca.pem" }],
    upstream: [{ site: "central", endpoint: "quic/central.example:7448", ca: "central-ca.pem" }],
    upstream_val_hz: 1.0,                         // optional
  }
  ```
  Validation: sites are valid segments, unique and not our own; endpoints are `quic/<host>:<port>` without `#`/`?`; CA paths are UTF-8 without `;#?` (they become endpoint parameters); `listen` and `downstream` come together; `upstream_val_hz > 0`.
- **Transport: QUIC + mTLS.** Any non-empty `peers` turns on broker certificates. The broker has CN `broker:<site>` for both its server certificate (SANs = `tls_names`) and its client certificate, both issued by its own CA.
- **Per-endpoint trust.** The global `transport/link/tls/root_ca_certificate` stays our own CA alone. Peer CAs are trusted only on the QUIC broker endpoints, through the endpoint parameter `#root_ca_certificate_file=`. Zenoh merges endpoint config over the global link config, and the endpoint wins:
  - the `peers.listen` endpoint gets `data_dir/pki/peer-trust.pem` (a bundle of all downstream CAs, written by `Control::configure_zenoh` on every broker build);
  - each upstream `connect` endpoint gets that site's `ca` file.
  The main `tls/` listener for links and operators therefore never trusts a peer CA.
- **ACL** (`access_control_with_peers` in `crates/wyrm-admin/src/acl.rs`). Peer subjects match `cert_common_names: ["broker:<site>"]` and `link_protocols: ["quic"]`; link and operator subjects are `tls` only. The two cannot overlap.
  - **Upstream sites are read-only** on our `wy/<site>/{down,flows}/**`: ingress `declare_subscriber`, `declare_liveliness_subscriber`, `liveliness_query`; ingress `query` only on `…/**/{~meta,~val,~def,~state}`; egress `put`, `delete`, `reply`, `liveliness_token`, `declare_queryable`, `declare_subscriber`. No `~set`/`~act` query passes, and nothing under `sys/**` is visible.
  - **Downstream sites serve their own `wy/<d>/**`**: all messages, both directions, on that key space only.
  - **Our requesters may read downstream sites.** Loopback and operator requester rules extend to `wy/<d>/**` (and `wy/<d>/**/@adv/sub/**`). The downstream broker's own ACL keeps them read-only there.
- **Egress downsampling.** With `upstream_val_hz`, the router config gets one Zenoh `downsampling` item (`link_protocols: ["quic"]`, `flows: ["egress"]`, `messages: ["put"]`) with **one rule per link**: `key_expr: wy/<site>/down/<link>/**/~val`, `freq: upstream_val_hz` (`wyrmd::upstream_downsampling`). Amended 2026-10-21 (owner decision): before, one rule for `wy/<site>/down/**/~val` gave all links one shared budget. With `upstream_val_hz` set, installing or removing any link (also embedded) rebuilds the broker, so the rules follow the registry.
- **Test.** `two_brokers_over_quic` in `crates/wyrmd/tests/e2e.rs`: `central` (downstream `edge`) and `edge` (upstream `central`, mock link, `upstream_val_hz: 50`). A client on central lists `wy/edge/down`, receives samples of `wy/edge/down/mock/g0/p0`, and its `set` on that point fails at the edge ACL.

## Consequences
- **No write across sites.** An upstream site cannot `set`/`invoke` on a downstream site, even with a valid `ptok`: the edge ACL drops the query before it reaches the SDK. Cross-site commands need a later design (e.g. a relay on the downstream site that re-signs with a local token).
- **Downsampling selects by link protocol, not by peer CN.** Zenoh downsampling has no certificate subject. Any `quic/` session (also a link or operator if `listen` ever contains `quic/`) gets the same rate limit on our `~val`.
- **The rate is per rule, so per link, not per key.** Zenoh 1.10.1 keeps one timestamp per rule per transport (`TimeState` in `interceptor/downsampling.rs`) and picks one matching rule per key (so the rules must not overlap). Each link gets `upstream_val_hz` samples/s towards each peer: a busy link cannot starve another link, but a busy point can still starve a slow point of the same link. Keys of a link that is not in the registry (`dev` profile only) are not limited. Per-key limits would need a WYRM-side relay. Test: `two_brokers_over_quic` (a 160 samples/s link and a 2 samples/s link under `upstream_val_hz: 5`; the slow one gets its samples).
- **Trusting a peer CA means trusting that site not to impersonate others.** All downstream CAs share one `peer-trust.pem`, and ACL subjects match the CN, not the issuer. A trusted downstream CA can mint `broker:<other-downstream>` (and receive that site's `site-<d>` rule) or `broker:<upstream>` (and read our `down/**` and `flows/**`). Zenoh 1.10 cannot bind a CN to a CA. **Accepted (owner decision 2026-10-21):** each site runs its own PKI and the operators exchange CA certificates on purpose; adding a downstream CA is a trust decision about that site's administrators. A federation CA and certificate pinning were considered and rejected as more operational work than the risk warrants. Note: quarantine does not cover this case, because an impersonating certificate carries a CN that is already configured (`broker:<site>`).
- The e2e tests use `tcp/` main listeners, so the isolation of peer CAs from a `tls/` main listener is not covered by a test yet. `two_brokers_isolation` covers the rest between real brokers: no upstream read of `sys/**`, no upstream `invoke`, no downstream put or query outside its `wy/<d>/**`, and no peer from an untrusted CA.
- A change of `peers` needs a broker restart (the section is read at `Daemon::open`); peer CA files are re-read on every broker build.

## Alternatives
- **Broker links on a separate `tls/…:7448` listener** (the wiki's design). Rejected: link, operator and broker subjects would all be `tls`, so a peer CA could mint a CN that matches a link rule. QUIC keeps the subjects apart by `link_protocols`, and suits WAN/4G better.
- **Add peer CAs to the global root.** Rejected: every peer CA could then authenticate on the link listener.
- **Upstream gets write with `ptok` checks only.** Rejected for now: when sites share an admin key (as in the e2e test), a valid token would pass the SDK check. The ACL is a boundary that does not depend on how keys are distributed.
- **Prefix rewriting (virtual site names).** Rejected by spec 01: full site names everywhere.
