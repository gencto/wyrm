# Backups (ADR 0048 §3)

A broker makes backups of itself and of one link while it runs. Every action is `config` on `sys` (the `admin` role through the gateway) and is in the audit. A backup is as sensitive as `data_dir`: with its passphrase it makes an administrator.

## 1. The file

A `.wyrm-backup` (broker) or `.wyrm-link` (one link) is a zip. Its first entry is `manifest.json`: `wyrm_backup: 1`, `kind`, `site`, `broker` (version), `created`, `schemas` (registry, users, flows, audit), `sealed`, and `sections[]` with each file's path, size and SHA-256. The format is in `wyrm_admin::backup`.

- Files with secrets are sealed with a key from the passphrase (Argon2id, at least 12 characters): everything in `keys`, each link's `secrets`, `token` and `files/**`, and a link backup's `data`. The reader refuses a file that lists one of them as not sealed.
- A sealed backup carries a MAC over its whole manifest. The broker opens nothing of it before the passphrase proves the manifest unchanged.
- A backup without a passphrase holds no secret. Its SHA-256 (`sys/backups/<id>/sha256`) proves it unchanged.
- Restore points and pre-update backups are sealed with a key from the broker's `secrets.key` (`sealed.how: "broker"`). Only the broker that made them opens them, without a passphrase.

## 2. Back up the broker

| Node | Action | Result |
|---|---|---|
| `sys/backups` | `estimate {sections, links?, history_days?}` | `{sections: {name: bytes}, total}` before compression |
| `sys/backups` | `create {sections, links?, history_days?, passphrase?}` | `{id}`; one job at a time (`busy` beyond) |
| `sys/backups/<id>` | values `status` (`running`, `done`, `failed`), `progress` (%), `step`, `size`, `sha256`, `created`, `expires`, `error`; attributes `kind` (`full`, `link`, `pre-update`, `pre-restore`), `name`, `sections`, `sealed`, `link` | |
| `sys/backups/<id>` | `download_part {offset, len?}` | `{data, offset, size, eof}`; `len` at most 16 MiB, default 4 MiB |
| `sys/backups/<id>` | `remove` | |

Sections:

| Section | Holds | Consistent because |
|---|---|---|
| `control` (always) | the WALs of the registry, the flow store, the gateway users and the audit | each is copied as of one sequence number, checked against its HMAC chain |
| `keys` | the site CA, `state.key`, `secrets.key`, `flows.key`, the gateway keys, the flow signing key, `secrets.bin`, link tokens; all sealed | needs the passphrase |
| `dataflows` | the flow engine's artifacts; the flow store itself is `control/flows` | content-addressed files |
| `storage` | the storage tree (`tree.cbor`) and its JSON export | the whole tree at one revision |
| `history` | the day files of the last `history_days` days (all without it) and the index | each file is copied inside one read transaction; days first, the index last |
| `links` | per link of `links` (all without it): `link.cbor` (its definition, without the token hash), and with a passphrase its secrets and private data, sealed | files as the standby copies them |
| `packages` | every installed package: `package.cbor` and its files. Without this section, the packages of the chosen links still go in | versions are immutable |
| `config` | a copy of `wyrmd.json5`; never restored | |

The job stages its files in `data_dir/backups/.stage-*`, then writes the zip. It needs about twice the estimate on the disk of `data_dir` and is refused (`resource_exhausted`) when that is not free. Links, flows and the historian go on while it runs.

Backups stay in `data_dir/backups` for `backups.keep_days` (default 7) within `backups.max_mb` (default 2048). The oldest are removed first; the newest one and a pinned one (the pre-update backup of an update not yet confirmed) never.

```json5
backups: { keep_days: 7, max_mb: 2048 },
```

A client loop: `create`, read `status` until `done`, `download_part` from offset 0 until `eof`, compare the SHA-256.

## 3. Back up and restore one link

`sys/links/<id>/~act/backup {sections, history_days?, passphrase?}` → `{id}`: a job in `sys/backups` with `kind: link`.

| Section | Holds |
|---|---|
| `settings` (always) | the link's definition: driver, mode, params, grants |
| `data` | its secrets and its private directory (`framework.tree`, a portable app's store), sealed. Needs the passphrase. An external link has none here |
| `package` | the package it runs: `package.cbor` and the files |
| `history` | the rows of its points (the last `history_days` days, all without it), keys relative to the link |

The framework's runtime edits (connections, devices, points) are in `data`. A backup of `settings` alone restores the link as it was installed.

Restore: `sys/links/~act/install_backup {file | upload, id?, accept, passphrase?}` → `{success, message}`.

1. Give the file as `file` (up to 64 MiB through the gateway's `POST /api/invoke`), or upload it in parts: `sys/backups/~act/restore_begin {size}` → `{upload, part_size}`, then `restore_part {upload, offset, data}` in order (at most 16 MiB each), and give `upload`. `restore_abort {upload}` drops it. An upload without a new part for an hour is removed.
2. `id` is the new link's id. Without it, the id in the backup is used.
3. `accept: true` is needed when the link has requester grants or a network allowlist. Without it, the answer lists them and nothing is installed.
4. The whole file is checked first. Then the package is installed when this broker does not have it. A broker that has the package in another version refuses: one version per package.
5. A new link is installed, stopped, given its secrets and private data, and started. Its token, certificate and requester key are new: they belong to the broker.
6. An existing link of that `id` must run the same driver in the same mode. A restore point of it is written to `data_dir/restore/<id>/<UTC>.wyrm-link` first, then it is stopped, replaced in place and started.

Not carried over: the link's display name and log level, the history watches (only the rows), and the secrets a broker makes for a link's identity.

## 4. For code

- `Control::link_backup_to(id, path)` writes a link backup without history to `path`, sealed for this broker. Package updates use it for restore points.
- `Control::link_restore_data(id, path)` gives a stopped link the secrets and private data of such a file.
- `Control::restore_point_path(link)` is the path of the next restore point.
