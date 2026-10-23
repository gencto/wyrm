# ADR 0015 — Downstream brokers admitted by the upstream's CA

**Status:** accepted · 2026-10-23 (owner decisions, backlog item 3; revised the same day after a review of how a DSA broker admits a downstream broker). Amends ADR 0007 (trust and admission only; the ACL shape, the read-only upstream and the chains stay).

## Context
ADR 0007 let a downstream broker connect with a certificate of its own CA; the upstream learned that CA from `peers.downstream[].ca` or from `sys/downstream ▸ Add Downstream Broker`. ADR 0007 also accepted a risk: every CA in the shared `peer-trust.pem` could mint `broker:<any site>`.

The owner asked for the DSA layout and behaviour. In a DSA broker:
- the downstream broker adds the connection itself (`/sys/upstream ▸ Add Upstream Connection {Name, Url, Broker Name, Token, Group}`) and connects to the upstream as a link, with its own key pair;
- the upstream admits it as it admits any link: a valid token (`/sys/tokens`, with a count and a time range) puts it straight into `/downstream/<name>`; with `allowAllLinks` it goes there too; with quarantine on it waits in `/sys/quarantine` until Authorize; otherwise it is refused;
- Deauthorize lists every connection under `/downstream`, brokers included; there is no install step and no `/sys/links` entry for a broker.

WYRM brokers talk over QUIC with mTLS, so a downstream broker needs a certificate the upstream trusts before it can open the peer link. A first version of this ADR had the upstream issue it in advance (Install Link ▸ Downstream Broker, files copied by hand). The owner rejected that: a broker must come in on its own, as in DSA.

## Decision
- **One CA on the QUIC peer listener.** `peers.listen` trusts only this broker's CA, as the link listener does; `peer-trust.pem` and per-site downstream CAs are gone. The listener opens whenever `peers.listen` is set.
- **Enrollment listener** (owner decision: a separate port). `peers.enroll: "quic/<host>:<port>"` opens a QUIC listener with server-auth TLS only (`#enable_mtls=false`). The ACL gives any QUIC session one key there: query `wy/<site>/sys/~act/enroll` and its reply (rule `enroll`, a subject without a CN, so it also matches every QUIC broker, which gains nothing). The admin answers it as an open action (as `hello`): no `ptok`, the unverified-caller rate limit, a 16 KiB request.
- **The downstream asks for its certificate.** `sys/upstream ▸ Add Upstream Connection {name, url, ca, token, enabled}`:
  - `url` is the upstream's enrollment endpoint; `ca` its CA (PEM, required: the downstream trusts nothing it was not given); `token` optional, a secret parameter, never shown back.
  - The downstream makes its own key (sealed in the `SecretStore` as `peer:<site>`, written 0600 for Zenoh; it never leaves the site) and sends `{site, csr, token, via}` (`csr` for CN `broker:<own site>`, `via` the sites it relays). It asks again every 10 s while the answer is `pending`.
  - The answer `issued` carries the certificate and the port of `peers.listen`; the downstream connects to the same host on that port with `#root_ca_certificate_file=…;connect_certificate_file=…;connect_private_key_file=…` (files: Zenoh logs endpoint strings).
  - `sys/upstream/<u>` shows `url`, `enabled`, `ca` (subject), `status` (`waiting`, `pending authorization`, `issued`, or the refusal), `key` (SHA-256 of its public key, to compare with the upstream's quarantine entry) and `certificate` (subject, valid until).
- **The upstream admits it as DSA does.** For an enrollment request, in this order:
  1. a downstream already admitted with the same key gets its certificate again; another key is refused;
  2. a held name (Deauthorized) waits in quarantine for a manual Authorize;
  3. a valid token signs at once (its count goes down; `sys/tokens ▸ Add Token {count, hours}` returns the token once, the registry keeps its SHA-256);
  4. `allow_all_links` signs at once (owner decision: as DSA's `allowAllLinks`) when every `via` site is free; otherwise the request goes to quarantine;
  5. with `enable_quarantine` the request waits in `sys/quarantine/<site>` (`kind: broker`, `key`, `via`); Authorize `{via}` signs it, Reject blocks the name;
  6. otherwise it is refused.
  A second request for a waiting name with another key is refused and counted (`conflicts`), never swapped in: the administrator compares the key on both sides before Authorize. A waiting request is written once (and again only when its key or `via` changes); the polls every 10 s are counted in memory and shown in the quarantine node. A request nobody asked again for 10 minutes leaves quarantine (as a DSA link that disconnects); a held broker stays. Every name-related refusal gives the same reason, so the open endpoint does not tell peers, links or relayed sites apart.
- **Where it shows.** Only `wy/<site>/downstream/<d>` (live, `connected`) beside the links, and `sys/quarantine/<d>` while it waits. Deauthorize lists the runtime external links and the runtime downstream brokers; a Deauthorized broker is held in quarantine (its certificate stays valid; its sessions are recorded there; only Authorize admits it again, also with another `via`).
- **`wyrmd.json5`** keeps an offline path: `peers.downstream: [{ site, via }]` on the upstream and `wyrmd ca` issue `data_dir/peers/<d>/broker.{pem,key}`; the downstream's `peers.upstream` entry names `ca`, `cert`, `key`. A name in `peers.downstream` is not enrolled at runtime.
- **Invariants** (each with a test):
  1. The CA never signs `broker:<own site>`, `broker:<an upstream site>` or a name a peer relays. A name signed once (`Registry::issued_brokers`) never becomes an upstream site: its certificate cannot be revoked and would match that upstream's ACL subject.
  2. A Deauthorized broker does not come back by itself (held; Reject: never).
  3. A key never leaves the site that made it; no key or token enters the registry WAL, `~meta`, `~val`, the audit journal or a log (tokens are kept as SHA-256; action arguments are not logged; the gateway audits their SHA-256).
  4. A session without a certificate on the enrollment listener reaches `sys/~act/enroll` only (`enroll_listener_reaches_one_key`).
- **Rebuilds.** A broker start waits (up to 30 s) until the QUIC peer port is free: after a router rebuild (ADR 0006) the old runtime keeps the UDP socket while its connections drain, and Zenoh 1.10.1 tries a listener once.

## Consequences
- ADR 0007's accepted risk is gone: only this broker's CA signs `broker:*` identities on its listener, and it signs one per admitted site.
- The enrollment listener is a new unauthenticated endpoint. It is bounded by the ACL (one key), the rate limit, the request size, the number of waiting requests (64, each gone after 10 minutes without a request) and writes only on change.
- With `allow_all_links` on, anyone who reaches the enrollment port gets a broker certificate for a free name and may serve `wy/<name>/**` on this broker (read-only for our upstream, never our own keys). This is the DSA behaviour the owner chose; keep `allow_all_links` off on exposed brokers.
- A certificate cannot be revoked (Zenoh 1.10 has no CRL); invariants 1 and 2 keep a removed broker from gaining rights. Certificates live one year; renewal (a request with the same key before expiry) is future work.
- `via` is fixed at admission; to change it, Deauthorize and Authorize again with the new list.
- Old configs with `peers.downstream[].ca` fail to parse (`deny_unknown_fields`); old registries replay.
- **Residual (as in ADR 0007):** on our own connection to an upstream site, that site's CA is trusted for the server certificate, and Zenoh 1.10 matches ACL subjects by the CN on either side. An upstream whose CA signs a server certificate `broker:<one of our downstream sites>` would get that downstream's rules. Accepted: an upstream site is chosen by our administrators.

## Alternatives
- **Install the downstream in advance and copy its files** (the first version of this ADR): rejected by the owner, not how DSA works.
- **Each site's own CA, trusted after approval** (ADR 0007): the listener must know the CA before the handshake, so quarantine could not see a new broker, and the peer-CA risk stays.
- **Enrollment through the user gateway (HTTP):** not every broker runs a gateway; a Zenoh query keeps one protocol (principle 4).
