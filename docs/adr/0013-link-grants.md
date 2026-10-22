# ADR 0013 — Links as requesters (link grants)

**Status:** accepted (owner decision 2026-10-22: grants per link) · 2026-10-22

## Context
A DSA link can be a responder (it serves nodes), a requester (it reads and commands other nodes) or both (`isRequester`). In WYRM a link served only its own branch: the generated ACL let a link's certificate reach `wy/<site>/down/<id>/**` and nothing else, and a link held no key that other links trust. Historians, bridges and aggregators need to read, and sometimes command, other links.

## Decision
- **Grants per link**, as gateway roles have them: `LinkDef::grants` = `(path, level)`. The path is a node key prefix with `{site}`: `wy/{site}/down[/…]` or `wy/{site}/flows[/…]`, plain segments only (no wildcards, no suffixes), never `sys/**`. Levels: `list`, `read`, `write`; `config` stays with people (`MAX_LINK_GRANT`), and `flows` grants stop at `read`.
- **Set** with `sys/links/<id>/~act/grant {path, level}` (the caller needs `config`; level `none` removes), audited (`link_grant`), shown in `sys/~act/get_permissions` (source `link`). A package asks for its grants in `wyrm-link.json` `requester: [{path, level}]`; each new link of the package gets them at install, and the install result lists them. A package cannot ask for a whole root (`wy/{site}/down`, `wy/{site}/flows`): only an operator grants that, with Grant Access.
- **ACL** (process and external links, by their certificate CN; `acl::grant_rules`): `list` → `~meta` queries and liveliness under the path; `read` → also `~val` queries and subscriptions; `write` → any query (`~set`, `~act`) under the path; the answers flow back (egress `put`, `delete`, `reply`, `liveliness_token`).
- **Requester key.** A link with grants gets a signing key as the link secret `.requester_key` (`wyrm_link_sdk::REQUESTER_KEY`), created by the broker, delivered like its other secrets (`hello` for a process link). Every link trusts it as one `LimitedKey` per grant: up to that grant's level, only under that grant's path, and only for the subject `link:<id>` (`LimitedKey::subject`; `Verifier` takes the highest cap among the keys that cover a request and accept its `sub`), so the audit names the real caller. `hello` sends such keys in `bound_keys` (`[key, cap, scopes, subject]`); a link built before this ignores the field and does not trust them. The link signs its `ptok`s with it (`LinkCtx::requester_key`, subject `link:<id>`); reads of `~meta`/`~val` need no token.
- A grant change rebuilds the router (ACL) and so every link's trust list (embedded links restart, process links say `hello` again).

## Consequences
- **Embedded links** run on the broker's in-process session and bypass the ACL: they can read every branch already. A grant gives them only the trusted key for `~set`/`~act`.
- The flow engine and the admin do not trust requester keys: a link cannot deploy flows or reach the control plane.
- Grants are additive; a link has no "deny" grant. Removing the link removes its grants and its key.
- Examples: `examples/links/requester` (read grant), `examples/links/both` (write grant); tests `link_grants`, `link_grants_open_other_branches`, `link_grants_make_a_requester`.

## Alternatives
- **Read-only requesters.** Rejected by the owner: bridges must command.
- **Requesters only as separate clients** (operator certificates, gateway users). Kept for tools; a link that is both responder and requester would need two identities.
