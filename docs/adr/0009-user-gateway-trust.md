# ADR 0009 — User gateway: sessions, per-request ptok, trust boundary

**Status:** accepted · 2026-10-20

## Context
People use WYRM through a browser or app, not with an Ed25519 key or a client certificate (wiki "Користувачі — gateway чи mTLS"). Links already authorize every `~set`/`~act` by `ptok` (spec 04). The gateway must turn a password login into such tokens without becoming a master key for the whole broker, and without leaking long-lived credentials into URLs or logs.

## Decision
- **Hosting.** `crates/wyrm-gateway` runs inside `wyrmd` when `wyrmd.json5` has a `gateway` section (`GatewaySection`: `listen`, `tls_cert`/`tls_key`, `session_ttl_s` clamped to 60 s … 7 d, `admin_user` default `admin`). TLS (rustls) is required off loopback, checked in both `Config::from_json5` and `Gateway::open`. State lives in `data_dir/gateway/`: `hmac.key`, `users/` (`wyrm-state` WAL + snapshot, ADR 0003) and `gateway.key` (Ed25519, 0600). The `Gateway` survives broker rebuilds; its HTTP/WS server is per broker (ADR 0006) and talks to Zenoh through the in-process session.
- **API.** Canonical CBOR bodies and frames: `POST /api/login`, `GET /api/me`, `POST /api/ws-ticket`, `GET /api/ws`, and user management under `/api/users` for users with `config` on `wy/<site>/sys/**`.
- **Users.** argon2id PHC hashes (hashed before the WAL sees the operation), passwords 8–1024 bytes, names `[A-Za-z0-9._-]{1,64}`. Unknown names run a dummy verify of the same cost. At most 4 argon2 runs at once.
- **Sessions.** Stateless token `base64url(0x01 ‖ cbor{sub, roles, exp, iat, jti, gen} ‖ HMAC-SHA256)`; the MAC key is derived from `hmac.key` (`HMAC(key, "wyrm-gateway/session/v1")`), never the key itself. Default lifetime 8 h. On every request the token is resolved against the store: the user must exist, be enabled and have the same `gen`; grants come from the user's roles **now**, not from the token.
- **Generation counter is store-wide.** `UserDb.next_gen` only grows and survives `RemoveUser`. Creation, password change and disable take a new value, so they end older sessions, including those of an earlier user with the same name: a re-created name never revives a session.
- **Per-request `ptok`.** `Gateway::tokens_for` signs one token per request with `gateway.key`: subject `user:<name>`, the user's grants and max permission, scoped to the request key, 5 min lifetime. The gateway checks grants itself before sending (`list`/`meta`/`children` ≥ list, `subscribe` ≥ read on part of the pattern, `set` ≥ write, `invoke` ≥ read with the action level left to the responder) and drops samples and children the user may not see. Refusals are audited as `Denied`.
- **Trust boundary.** Links (`ControlConfig.link_keys`) and the flow engine trust the gateway key. **The admin does not**: the control plane (`sys/**`: link install, quarantine, secrets, tokens) needs operator keys. Gateway user management is local to the gateway store, not an admin operation.
- **WebSocket tickets.** `POST /api/ws-ticket` (bearer session) returns a random 128-bit ticket, single use, 30 s; `GET /api/ws?ticket=…` spends it and re-resolves the session. The long-lived session never appears in a URL. At most 8 live tickets per user; a new one replaces that user's oldest, so one user cannot crowd out the others. `Authorization: Bearer` is also accepted for non-browser clients. Open sockets re-read the user every 15 s and close at session expiry.
- **First admin.** At start, if `WYRM_GATEWAY_ADMIN_PASSWORD` is set and `admin_user` does not exist, that user is created with the `admin` role. The variable is removed from the process environment right after reading, and the supervisor starts link processes with a cleared environment (`env_clear` plus `RUST_LOG`, `RUST_BACKTRACE`, `TZ`, `LANG`, `LC_ALL`, `PATH`). The password never comes from `wyrmd.json5`.
- **Login rate limit.** At most 5 failed logins per `(user, ip)` in a sliding 60 s window; a success clears it; expired records are pruned once 10 000 are held.
- **Audit.** `AuditEvent`s (`LoginOk`, `LoginFailed{reason}`, `UserChanged`, `Denied`) go into the admin journal through `Control::record`: logins and refusals with subject `user:<name>`, user changes with the acting user's name as subject. They never carry passwords or tokens.

## Consequences
- A stolen gateway key gives `write`/`config` on devices and flows of this site, but not on the control plane and not on other sites (their links do not trust it).
- Role changes take effect on the next request without a new login; sessions can only be ended by password change, disable or removal (no logout list).
- The default `engineer` role's `write` on `wy/<site>/sys/links/**` lets the gateway show those nodes, but its write part has no effect, because the admin does not trust gateway tokens. The `admin` role's `config` on `sys/**` likewise only governs gateway user management.
- Gateway users cannot deploy flows with command sinks: proofs (ADR 0008) are tokens the gateway never hands out.
- The rate limit is per `(user, ip)`: password spraying over many user names from one address is not bounded.
- A broker rebuild (ADR 0006) closes all WebSockets; sessions and tickets stay valid.

## Alternatives
- **Users with client certificates (mTLS) and an operator CN each.** Rejected for people: certificate handling in browsers and phones; kept for engineering tools (`operators`).
- **The admin trusts the gateway key.** Rejected: a web-facing process would then hold the control plane.
- **Server-side session table.** Rejected: the store-wide `gen` gives revocation without per-session state.
- **Session token in the WebSocket URL.** Rejected: URLs end up in proxy and browser logs; replaced by single-use tickets.
