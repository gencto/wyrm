# ADR 0006 — ACL changes rebuild the router runtime

**Status:** proposed · 2026-10-20

## Context
`wyrm-admin` generates the Zenoh `access_control` section from the link registry. Zenoh 1.10.1 has no public live reload of it: `TablesLock::update_config` is `pub(crate)` and only Zenoh's own tests call it.

## Decision
- **Rebuild on ACL change.** Install/remove of a process or external link and quarantine `approve` ask `wyrmd` to close and rebuild the router runtime with a new ACL. The daemon owns what survives a rebuild: the admin `Control` (registry, CA, supervisor with its child processes, audit). Sessions close before `runtime.close()`. Admin and embedded links attach before `runtime.start()` opens the listeners. Process links reconnect by themselves and re-publish `~meta`/`~val` when the `wy/<site>/sys/broker` liveliness token returns.
- **ACL shape.** Default deny. Each remote link gets, by certificate CN, everything on `wy/<site>/down/<id>/**` plus `query`/`reply` on its own `sys/links/<id>/~act/hello`. Loopback (`tcp`, `unixsock-stream`) and operator CNs are requesters only in `prod`: they ask and receive, but cannot put, serve queries or declare tokens outside `**/@adv/sub/**` (advanced subscriber bookkeeping; `@adv/pub` belongs to the owning link only). In `dev`, loopback has full rights. In-process sessions (admin, embedded links, plugins) bypass the ACL.
- **Local process links use loopback mTLS** with their own CN, not UDS + uid as the wiki describes, because the Zenoh ACL has no uid subject. UDS stays for later.
- **Removed ids are retired.** Without a CRL a removed link's certificate stays valid until it expires, so its id is never installed again and its CN is not quarantined again.
- **Quarantine.** An unknown CA-signed CN is seen through `link_events_listener()` → `auth_identifier()`. Default deny already blocks it (stricter than the wiki's "may put `sys/quarantine/<cn>`"). `approve` installs it as an external link and triggers a rebuild.
- **`acl_denied_total`** = sum of `zenoh_{rx,tx}_network_message_dropped_payload_bytes_count{reason="access-control"}` read from `@/<zid>/router/metrics` (gzip). It needs the Zenoh `stats` feature and a read-only admin space; remote sessions cannot read `@/**` under the ACL.

## Consequences
- A rebuild drops all sessions for about 1 s. The memory `~val` storage starts empty and the owners refill it.
- ACL changes are rare (lifecycle operations), so the cost is acceptable for one site.
- Supervised children stop when `wyrmd` exits and are not adopted by PID on the next start. The wiki wants process links to survive a broker restart (systemd `KillMode=process`); that needs PID adoption and is not done yet.
- Revisit when Zenoh exposes a public live ACL reload.
