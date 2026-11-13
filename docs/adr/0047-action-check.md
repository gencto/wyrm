# ADR 0047 — Checking an action without running it (`~act/<a>?check`)

Status: accepted (2026-11-13; decisions delegated under ADR 0029).

## Context

The MCP connector runs every change dry first: it reads the node's `~meta`, checks the
arguments against the action's schema (types, enums, required, bounds) and shows the person
what would be sent. A link that parses its arguments further found errors only when the
action ran. In the DVPSM demo (2026-11-13) the dry run of `add_bot {format: "html"}` was "ok",
and the bot refused the real call (`format: one of html, markdown, plain`: the messenger read a
typed enum by name). A dry run that says "ok" for what the link then refuses gives the person
a false sense that all is well.

The link is the only one that knows its own rules (its form parsing, the author's rights of a
template, its recipients, its network allowlist). It must be asked. Asking an older link is the
danger: a selector parameter it does not know is ignored, and it would run the action.

## Decision

1. Spec 05 0.2.33: `get path/~act/<a>?check` with the action's arguments. The responder checks
   the call as the action would take it: `ptok` and the level, the arguments against the
   action's meta, then its driver's own check. It does nothing: no write, no command, no change
   of state. The answer is `status=ok` without a payload, or the refusal the action would give
   (same status, same text). The audit records `check`.
2. A responder that answers `check` says so: `attr.check = true` on its root `~meta`
   (`wy/<site>/downstream/<link>`, `sys`, `dataflows`, `storage`). The SDK sets it on every
   root it declares, so every link built with this SDK has it. A requester sends `?check` only
   where the root says so; without it the check ends at the action's meta on the requester's
   side, as before.
3. SDK: `Link::on_check(path, action, args, who)`, default `Ok` (the SDK's checks are all
   there is). Portable links: `App::on_check`, default `Ok`; the runtime runs it on the engine
   thread like an event and drops whatever the app asked of the host during it. The messenger
   implements it with the same parsing as its actions (bots, recipients, templates and their
   sends, chat users).
4. A WASM component of world `wyrm:app` 0.3.0 has no check call: its check ends at the meta
   (the host checks that). A component gets its own check with the next world; the world stays
   frozen until then (ADR 0030).
5. Gateway op `check {key, action, args}` (rights as `invoke`); `WyrmClient::invoke_check`;
   `wyrm-gateway-client::Conn::check`. The MCP connector's dry runs of `action_invoke` and of a
   plan's `invoke` steps ask the link when it says it can and show `checked_by_link`.

## Consequences

- A dry run catches what the link would refuse, before anything runs.
- Links built before this have no `attr.check` and are never asked; they behave as before.
- `check` costs one request to the link and one audit record; it is rate limited as any call.
- Tests: telegram `a_check_refuses_what_the_action_would_and_does_nothing`, e2e
  `a_check_does_nothing`, wyrm-mcp gateway test (dry run with `checked_by_link`).
