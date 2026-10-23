# ADR 0015 — Downstream brokers admitted by the upstream's CA

**Status:** accepted · 2026-10-23 (owner decision, backlog item 3). Amends ADR 0007 (trust and admission only; the ACL shape, the read-only upstream and the chains stay).

## Context
ADR 0007 let a downstream broker connect with a certificate of its own CA; the upstream learned that CA from `peers.downstream[].ca` or from `sys/downstream ▸ Add Downstream Broker`. The owner asked for the DSA layout: `sys/upstream` (where this broker connects) stays, `sys/downstream` goes, and a downstream broker comes in as links do, through installation and quarantine. Quarantine cannot see a broker whose CA is unknown: the QUIC TLS handshake fails before any link event, ACL or registry code runs. ADR 0007 also accepted a risk: every CA in the shared `peer-trust.pem` could mint `broker:<any site>`.

## Decision
- **One CA on the QUIC listener.** The `peers.listen` endpoint trusts only this broker's CA, as the link listener does; `peer-trust.pem` and per-site downstream CAs are gone. The listener opens whenever `peers.listen` is set, so an unknown broker can reach quarantine.
- **The upstream issues the downstream's certificate.** CN `broker:<d>`, client auth, signed by the upstream's CA, written to `data_dir/peers/<d>/broker.{pem,key}` (key 0600) beside the CA `data_dir/pki/ca.pem`. The operator copies the three files to the downstream site.
  - `wyrmd.json5`: `peers.downstream: [{ site, via }]` (no `ca`): the certificate is issued at start.
  - Runtime: `sys/links ▸ Install Link ▸ Downstream Broker {name, via}`: the same; the result names the files, it never carries the key (`wyrmd ca` issues them offline for the sites in `wyrmd.json5`).
  - Quarantine: a `broker:<x>` session that came in on the QUIC peer listener (its local port) with a certificate of this CA and an unknown `x` is recorded in `sys/quarantine/<x>` (`attr.kind = broker`); Authorize `{via}` admits it after the same name checks as Install (not this site, a peer or a relayed site). Our own links to upstream sites never count: there the CN is the upstream server's. Brokers are never admitted automatically (`allow_all_links` covers links only), because `via` decides which sites the broker may serve.
- **The downstream presents that certificate.** Its upstream entry carries `ca`, `cert` and `key` (`wyrmd.json5`: paths; `sys/upstream ▸ Add Upstream Connection`: PEM, the key a secret parameter sealed in the `SecretStore` and written 0600 for Zenoh). The connect endpoint gets `#root_ca_certificate_file=…;connect_certificate_file=…;connect_private_key_file=…`, always the certificate and the key together, as files (Zenoh logs endpoint strings; `*_base64` would put the key in the log).
- **Invariants** (each with a test):
  1. The CA never issues or admits `broker:<own site>` or `broker:<an upstream site>`. A name issued once (`Registry::issued_brokers`) is never accepted as an upstream site later: its certificate cannot be revoked and would match that upstream's ACL subject.
  2. A removed downstream broker does not come back by itself: Remove puts its name in `held`; its next session lands in quarantine, and only Authorize admits it again (Reject: never again).
  3. The downstream's private key never enters the registry WAL, `~meta`, `~val`, the audit journal or a log. Action arguments are not logged anywhere (the gateway audits their SHA-256; the SDK logs no arguments); an MCP dry run echoes arguments only to the caller that sent them. A runtime upstream entry without our certificate from it (added before this ADR) is not connected; a warning says to add it again.
- **Where it shows.** `wy/<site>/downstream/<d>` (live, `connected`) beside the links; `sys/links/<d>` with `driver = broker`, `via` and Remove (runtime ones).
- **Rebuilds.** A broker start waits (up to 30 s) until the QUIC peer port is free: after a router rebuild (ADR 0006) the old runtime keeps the UDP socket while its connections drain, and Zenoh 1.10.1 tries a listener once, so downstream brokers would otherwise stay out until a restart (found with `runtime_peers_over_quic`; it affected ADR 0007 too). `sys/upstream/<u>` shows `url`, `enabled`, `ca` (subject) and `certificate` (subject, valid until), never the key; entries from `wyrmd.json5` are read-only.

## Consequences
- ADR 0007's accepted risk is gone: only this broker's CA signs `broker:*` identities on its listener, and it signs one per admitted site.
- A certificate cannot be revoked (Zenoh 1.10 has no CRL). A removed broker keeps a valid certificate for up to a year; invariants 1 and 2 keep it from gaining rights.
- Broker certificates live one year (`Pki::issue`) and are not renewed yet; a new issue needs the old files deleted. Renewal is future work, as for link certificates.
- Old configs with `peers.downstream[].ca` fail to parse (`deny_unknown_fields`); old registries replay (`AddPeer` with a `ca_pem` keeps working; the PEM is no longer trusted).
- The upstream site must be set up first: the downstream needs its CA and the issued certificate.
- **Residual (as in ADR 0007):** on our own connection to an upstream site, that site's CA is trusted for the server certificate, and Zenoh 1.10 matches ACL subjects by the CN on either side. An upstream whose CA signs a server certificate `broker:<one of our downstream sites>` would get that downstream's rules (publish under `wy/<d>/**`) instead of its own. Accepted: an upstream site is chosen by our administrators; binding a subject to the link's direction or issuer needs Zenoh support.

## Alternatives
- **Install as a link with the downstream's CA** (keep ADR 0007 trust): rejected by the owner — brokers would never reach quarantine.
- **Enrollment** (the downstream sends a CSR, the upstream signs after approval): needs a channel without mTLS on the listener or through the gateway; more moving parts for the same result.
