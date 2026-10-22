# ADR 0006 — ACL changes rebuild the router runtime

**Status:** accepted · 2026-10-20

## Context
`wyrm-admin` generates the Zenoh `access_control` section from the link registry (and, since iteration 4, from the `peers` section, ADR 0007). Zenoh 1.10.1 has no public live reload of it: `TablesLock::update_config` is `pub(crate)` and only Zenoh's own tests call it.

## Decision
- **Rebuild on ACL change.** Install/remove of a process or external link and quarantine `approve` call `Control::schedule_reload`, which waits 300 ms (so the current reply leaves first) and sends a signal on the reload channel. `Daemon::run_until` stops the current `Broker` and starts a new one with a freshly generated ACL. Embedded installs/removes do not rebuild: embedded links have no ACL rule.
- **What survives a rebuild** is owned by the `Daemon`: the admin `Control` (registry, audit, CA, link secrets, supervisor with its child processes), the `FlowHost` (flow store, flow signing key) and the `Gateway` (user store, signing key, sessions, WebSocket tickets). **What is rebuilt** is the `Broker`: router runtime, storage/REST plugins, one in-process session, the admin responder with its watchers, embedded links, the flow engine and the gateway's HTTP/WS server.
- **Order.** Start: build the runtime, open the in-process session, attach admin + embedded links + process supervision, spawn the flow engine, then `runtime.start()` opens the listeners (so the first remote query finds their queryables and tokens), then the gateway server. Stop: gateway server, flow engine, admin (watchers, embedded links, responder), then `session.close()` before `runtime.close()`.
- **Process links are not restarted.** `Attached::stop` leaves processes running; on the next attach `Supervisor::start` is a no-op for a live process. The processes reconnect by themselves and re-publish `~meta`/`~val` when the `wy/<site>/sys/broker` liveliness token returns (`LinkConfig::republish_on`).
- **Coalescing is partial.** After the old broker has stopped, `run_until` drains the reload signals already queued (e.g. several installs in a row) and rebuilds once. A signal that arrives after the drain causes one more rebuild.
- **ACL shape.** Default deny.
  - Each remote link gets, by certificate CN and only over `tls`: everything on `wy/<site>/down/<id>/**`, `query`/`reply` on its own `sys/links/<id>/~act/hello`, ingress `put` on `sys/audit/<id>`, and liveliness on `sys/broker` (`broker-watch`).
  - Loopback (`tcp`, `unixsock-stream`) in `prod` and operator CNs (over `tls`) are requesters only: they ask (query, subscribe, liveliness) and receive (put, delete, reply, liveliness token) on `wy/<site>/**` and on `wy/<d>/**` of every downstream site, but cannot put, serve queries or declare tokens outside `**/@adv/sub/**` (advanced subscriber bookkeeping; `@adv/pub` belongs to the owning link only).
  - In `dev`, loopback has full rights on `wy/<site>/**`.
  - Peer brokers get the rules of ADR 0007.
  - In-process sessions (admin, embedded links, flow engine, gateway, plugins) bypass the ACL.
- **Local process links use loopback mTLS** with their own CN, not UDS + uid as the wiki describes, because the Zenoh ACL has no uid subject. UDS stays for later.
- **Removed ids are retired.** Without a CRL a removed link's certificate stays valid until it expires, so its id is never installed again and its CN is not quarantined again (`Registry::retired`). **Exception, 2026-10-22 (owner decision, DSA Deauthorize):** `sys/quarantine/~act/deauthorize {link}` puts a runtime external link back into quarantine instead (`Op::Deauthorize`, `Registry::held`): its token, secrets and ACL rules go, the CN keeps no rights, and only a manual Authorize admits it again — `allow_all_links` skips held CNs. Remove still retires.
- **Authorize** (DSA form, 2026-10-22): `sys/quarantine/~act/authorize {dsid, group, name, driver, params}`; `dsid` is an enum of the quarantined CNs, re-declared on every change (as are the link list of Deauthorize and the role list of `group`). `name` is the link's display name (the id stays the CN, which the ACL matches). `group` gives that gateway role `write` on `wy/{site}/down/<id>/**` (as Update Permissions, audited). Each `quarantine/<cn>` node keeps its own `approve` with the same form. Test: `authorize_and_deauthorize`.
- **Quarantine.** An unknown CA-signed CN is seen through `link_events_listener()` → `auth_identifier()`. Default deny already blocks it (stricter than the wiki's "may put `sys/quarantine/<cn>`"). `approve` installs it as an external link and triggers a rebuild. Only sessions on the `tls` link listener count (it trusts our CA alone; a peer site's CA on QUIC can sign any CN).
- **Admission options** (2026-10-22, DSA `allowAllLinks` / `quarantine`), persisted in the registry (`Op::SetOption`, SCHEMA 5), set as `config` values `sys/allow_all_links` (default off) and `sys/enable_quarantine` (default on), audited (`set_option`). With `allow_all_links` an admissible CN (`admissible`: not a known, rejected or retired id, an operator, a peer broker or a downstream site name) is installed as an external link on first sight (audit `auto_install`), then the runtime rebuilds; the link token goes only to `links/<id>/token` on the broker, and the operator copies it to the device as after `approve`. With both off, unknown CNs are ignored. Setting an option does not rebuild by itself. The broker logs a warning at start while `allow_all_links` is on.
- **`acl_denied_total`** = sum of `zenoh_{rx,tx}_network_message_dropped_payload_bytes_count{reason="access-control"}` read from `@/<zid>/router/metrics` (gzip). It needs the Zenoh `stats` feature and a read-only admin space; remote sessions cannot read `@/**` under the ACL.

## Consequences
- A rebuild drops all Zenoh sessions for about 1 s. The memory `~val` storage starts empty and the owners refill it.
- A rebuild also closes every user WebSocket. Gateway sessions and unspent tickets survive (they live in `Gateway`), so clients reconnect without a new login.
- ACL changes are rare (lifecycle operations), so the cost is acceptable for one site.
- On a clean shutdown `Control::shutdown` stops the supervised children; they are not adopted by PID on the next start. The wiki wants process links to survive a broker restart (systemd `KillMode=process`); that needs PID adoption and is not done yet.
- Revisit when Zenoh exposes a public live ACL reload.

## Open
- ~~Failed rebuild orphans process links~~ — fixed: `run_until` calls `Control::shutdown` also when `Broker::start`/`stop` fails.
- **Coalescing** relies on a fixed 300 ms delay plus one drain; there is no debounce window.
- PID adoption of process links (see Consequences).

## Alternatives
- **Patch Zenoh to expose `TablesLock::update_config`.** Rejected: principle 1 (Zenoh is never patched or forked).
- **Permissive ACL plus authorization only in the responder SDK.** Rejected: the SDK checks `ptok` on `~set/~act`, but cannot stop a session from publishing into another link's `~val` or declaring its liveliness token.
- **A second router per link class.** Rejected: more processes and hops for a rare event.
