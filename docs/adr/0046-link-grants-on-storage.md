# ADR 0046 — Link grants on the site's storage

Status: accepted (2026-11-13; decisions delegated under ADR 0029).

## Context

A link gets rights on other parts of its site through grants (`sys/links/<id>`
▸ Grant Access, a package's `requester`; ADR 0013): a path under
`wy/{site}/downstream` (any level up to `write`) or `wy/{site}/dataflows` (at
most `read`). `check_grant` refused every other root, `storage` included.

The demo bot of 2026-11-13 (DVPSM, `links/telegram`) needed storage: its
buttons and `/set` from the chat write the points of `storage/dvpsm/cmd`, and
its templates and chat users read `storage/dvpsm/**`. A flow reads and writes
storage with its deployer's rights; a link could not, so the buttons did
nothing and Invite User with a storage key failed with an empty
`PermissionDenied`. The only way round was a register link in `downstream`
mirrored into storage by a flow.

Storage (ADR 0017) is the site's shared folder tree, not one link's branch:
several flows, users and links keep values there side by side.

## Decision

1. `check_grant` takes `wy/{site}/storage[/…]` as a third root.
   - `list` and `read` on any path in it, the root included.
   - `write` only on a folder below the root (`wy/{site}/storage/<folder>[/…]`):
     one grant never lets a link write the whole of the site's storage. A link
     that writes several folders gets one grant each.
   - `config` stays for people, as everywhere.
2. The router ACL needs no change: grant rules are built from the path
   (`grant-<id>-*`).
3. The embedded storage link trusts a link's requester key (subject
   `link:<id>`) at the grant's level and only under the grant's path, beside
   the admin keys, the gateway, the flow key and upstream sites
   (`Control::requester_keys_under`). A grant change rebuilds the router, and
   the storage link starts again with the new keys.
4. A package may ask for storage in `requester` with the same rules.

## Consequences

- A chat bot, a report link or any requester can keep its working values in
  storage without a mirror flow.
- An operator who grants `write` on a folder lets that link change every value
  under it; the grant shows in Get Permissions and in the audit
  (`link_grant`) as before.
- Not changed: a link still never reaches `sys/**` and never writes flows.
- Tests: `registry::tests::link_grants` (paths and levels), e2e
  `link_grant_on_a_storage_folder` (writes its folder, refused in another,
  refused on all of storage).
