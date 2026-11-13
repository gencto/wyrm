# Backups (ADR 0048 §3)

A broker makes backups of itself and of one link while it runs. Every action is `config` on `sys` (the `admin` role through the gateway) and is in the audit. A backup is as sensitive as `data_dir`: with its passphrase it makes an administrator.

## 1. The file

A `.wyrm-backup` (broker) or `.wyrm-link` (one link) is a zip. Its first entry is `manifest.json`: `wyrm_backup: 1`, `kind`, `site`, `broker` (version), `created`, `schemas` (registry, users, flows, audit), `sealed`, and `sections[]` with each file's path, size and SHA-256. The format is in `wyrm_admin::backup`.

- Files with secrets are always sealed: everything in `keys`, each link's `secrets`, `token` and `files/**`, and a link backup's `data`. The reader refuses a file that lists one of them as not sealed.
- Without a passphrase they are sealed for the site (`sealed.how: "broker"`, a key from `secrets.key`). Such a file opens only on a broker that holds this site's keys. Restore points and pre-update backups are made this way.
- With a passphrase (Argon2id, at least 12 characters) the file opens anywhere. This needs `backups.export_secrets: true` (§1.1).
- A sealed backup carries a MAC over its whole manifest. The broker opens nothing of it before the key proves the manifest unchanged.
- A backup with no secret-bearing part is not sealed. Its SHA-256 (`sys/backups/<id>/sha256`) proves it unchanged.

### 1.1 Secrets leave the broker only when the host allows it

`config` on `sys` must not be enough to take the site's identity. The option `backups.export_secrets` in `wyrmd.json5` (default `false`) is set on the host alone.

| | `export_secrets: false` | `export_secrets: true` |
|---|---|---|
| section `keys` | refused | made with a passphrase |
| a passphrase | refused, the message names the option | seals `keys`, link secrets and private data |
| link secrets and private data | sealed for the site | sealed for the site, or with the passphrase |
| everything else | works | works |

- A caller whose authority comes from another site (an upstream with `allow_config`) never gets `keys` or a passphrase-sealed file, whatever the option says. The admin tells such a caller by its token: a limited key signed it.
- The audit record `backup_create` carries `keys: true|false` and `secrets: true|false`, and the broker logs a warning for a passphrase-sealed backup.
- `sys/backups` has the attribute `export_secrets` for UIs.
- Secrets a broker makes for a link's identity (its requester key, an agent's signing key) are in no link data of any backup. A link's token is only in `keys`.
- The `config` section is `wyrmd.json` with every secret masked (`***`): fields named like a secret, PEM private keys and long hex strings, except `admin_keys`.

## 2. Back up the broker

| Node | Action | Result |
|---|---|---|
| `sys/backups` | `estimate {sections, links?, history_days?}` | `{sections: {name: bytes}, total}` before compression |
| `sys/backups` | `create {sections, links?, history_days?, passphrase?}` | `{id}`; one job at a time (`busy` beyond) |
| `sys/backups/<id>` | values `status` (`running`, `done`, `failed`), `progress` (%), `step`, `size`, `sha256`, `created`, `expires`, `error`, `sent_to`, `send_status`, `send_progress` (%), `send_error`; attributes `kind` (`full`, `link`, `pre-update`, `pre-restore`), `name`, `sections`, `sealed`, `link` | |
| `sys/backups/<id>` | `download_part {offset, len?}` | `{data, offset, size, eof}`; `len` at most 16 MiB, default 4 MiB |
| `sys/backups/<id>` | `remove` | |
| `sys/backups/<id>` | `send {link, connection, path?}` | `{to, upload, parts}`; the file goes to a file store in the background (§2.1) |

Sections:

| Section | Holds | Consistent because |
|---|---|---|
| `control` (always) | the WALs of the registry, the flow store, the gateway users and the audit | each is copied as of one sequence number, checked against its HMAC chain |
| `keys` | the site CA, `state.key`, `secrets.key`, `flows.key`, the gateway keys, the flow signing key, `secrets.bin`, link tokens; all sealed | needs the passphrase |
| `dataflows` | the flow engine's artifacts; the flow store itself is `control/flows` | content-addressed files |
| `storage` | the storage tree (`tree.cbor`) and its JSON export | the whole tree at one revision |
| `history` | the day files of the last `history_days` days (all without it) and the index | each file is copied inside one read transaction; days first, the index last |
| `links` | per link of `links` (all without it): `link.cbor` (its definition, without the token hash), its secrets and private data, sealed | files as the standby copies them |
| `packages` | every installed package as its files (`wyrm-link.json` among them). Without this section, the packages of the chosen links still go in | versions are immutable |
| `config` | `wyrmd.json`, the configuration with secrets masked; never restored | |

The job stages its files in `data_dir/backups/.stage-*`, then writes the zip. It needs about twice the estimate on the disk of `data_dir` and is refused (`resource_exhausted`) when that is not free. Links, flows and the historian go on while it runs.

Backups stay in `data_dir/backups` for `backups.keep_days` (default 7) within `backups.max_mb` (default 2048). The oldest are removed first; the newest one and a pinned one (the pre-update backup of an update not yet confirmed) never.

```json5
backups: { keep_days: 7, max_mb: 2048, export_secrets: false, send_links: [] },
```

A client loop: `create`, read `status` until `done`, `download_part` from offset 0 until `eof`, compare the SHA-256.

### 2.1 Send a backup to a file store

`sys/backups/<id>/~act/send {link, connection, path?}` writes a kept backup into a file store (S3, WebDAV, Google Drive, a local directory: [filestores.md](filestores.md)) through a file-store link of this broker.

1. On the host, name the link and the folder in `wyrmd.json5`, then restart the broker:
   ```json5
   backups: { send_links: [{ link: "files", folder: "site/backups" }] },
   ```
   A link id alone (`send_links: ["files"]`) means the folder `backups`. One folder for each link. The default is an empty list: `send` is refused. `sys/backups` shows the list as the attribute `send_links` (`[{link, folder}]`).
2. Make the folder in the store (Create Folder on the link, or in the store itself). `send` does not create it.
3. Call `send` with `link` (one of the list) and `connection` (a connection of that link). The file goes to `<connection>/files/<folder>/` under the backup's own file name.
4. To give another name or a sub-folder, set `path`: `nightly.wyrm-backup`, or `2026/nightly.wyrm-backup` (the sub-folder must exist).
5. The broker begins an upload on the link (`upload_begin` with the size and SHA-256), answers `{to, upload, parts}`, and sends the parts (1 MiB each) in the background, then `upload_commit`.
6. Read `send_status` of `sys/backups/<id>`: `sending` (with `send_progress`), `done`, or `failed` (with `send_error`). `sent_to` is `<link>/<connection>/files/<folder>/<path>`.

The broker writes with its own key, for any caller with `config` on `sys`. So the host decides where the files go, not the caller:

- **Only below the host's folder.** `path` is a file name or a sub-path of plain names. An absolute path, `..`, an empty segment, `\` or `:` is refused before the link is called. `connection` is one name.
- **A narrow token.** The broker signs these calls with its backup sender key. Only the links in `send_links` trust that key (at `write`, on their own subtree, for the subject `broker:backup`). Each token of a send is good for the keys of `<connection>/files/<folder>/**` and the connection's four upload actions only. The broker makes the key on first use; it is no link's secret and is in no link backup.
- **Nothing is overwritten.** A name that exists in the folder is refused. Give another `path`.
- **The audit names the caller.** `backup_send` in the admin's journal, at the start and at the end: who called, the backup, the link, the path, the size and the SHA-256. The link's own audit records each upload call under `claimed:broker:backup`; the upload actions carry no note, so the caller's name is only in the admin's journal.
- A backup that holds the `keys` section is never sent. Download it on the broker's own gateway.
- A caller that reaches the site through an upstream may send a backup without `keys`: the host named the destination.
- One send runs at a time (`busy` beyond). A backup that is being sent is not removed or pruned. If the broker stops during a send, start `send` again.
- The link spools the file on its own disk before it goes to the store (`<data_dir>/links/<id>/data/uploads/`), so that disk needs room for it.

## 3. Back up and restore one link

`sys/links/<id>/~act/backup {sections, history_days?, passphrase?}` → `{id}`: a job in `sys/backups` with `kind: link`.

| Section | Holds |
|---|---|
| `settings` (always) | the link's definition: driver, mode, params, grants |
| `data` | its secrets and its private directory (`framework.tree`, a portable app's store), sealed for the site, or with the passphrase for another broker (§1.1). An external link has none here |
| `package` | the package it runs, as its files |
| `history` | the rows of its points (the last `history_days` days, all without it), keys relative to the link |

The framework's runtime edits (connections, devices, points) are in `data`. A backup of `settings` alone restores the link as it was installed.

Restore: `sys/links/~act/install_backup {file | upload, id?, accept, passphrase?}` → `{success, message}`.

1. Give the file as `file` (up to 64 MiB through the gateway's `POST /api/invoke`), or upload it in parts: `sys/backups/~act/restore_begin {size}` → `{upload, part_size}`, then `restore_part {upload, offset, data}` in order (at most 16 MiB each), and give `upload`. `restore_abort {upload}` drops it. An upload without a new part for an hour is removed.
2. `id` is the new link's id. Without it, the id in the backup is used.
3. `accept: true` is needed when the link has requester grants or a network allowlist. Without it, the answer lists them and nothing is installed.
4. The whole file is checked first. The link's definition passes the checks of a new link: its id (reserved ids refused), its driver, its params, every grant. The package's files pass the validator of every install (`packages::unpack`): the entry inside the package, requester grants, WASM world and capabilities. Its registry record is built from the files, never read from the backup. `accept` covers what the link and a package this install brings ask for. Then the package is installed when this broker does not have it. A broker that has it in the same version must hold the same files; another version is refused: one version per package.
5. A new link is installed, stopped, given its secrets and private data, and started. Its token, certificate and requester key are new: they belong to the broker.
6. An existing link of that `id` must run the same driver in the same mode. A restore point of it is taken first (`data_dir/restore/<id>/<UTC>.wyrm-link`, as before a package update: [links.md](links.md) §5a), shown in `sys/links/<id>/restore_points` and pruned after `packages.keep_previous_days`. Then the link is stopped, replaced in place and started. To go back, install that file with `install_backup` on this broker: it is sealed for it and needs no passphrase.

Not carried over: the link's display name and log level, the history watches (only the rows), and the secrets a broker makes for a link's identity.

## 4. Restore the broker

Upload the `.wyrm-backup` (`restore_begin`, `restore_part`), then:

| Action | Result |
|---|---|
| `sys/backups/~act/restore_check {upload, passphrase?}` | `{site, same_site, created, broker, sealed, schemas: {name: {backup, here}}, sections: {name: bytes}, keys: none|same|differ|other, keys_differ[], control_opens_here, links: {id: new|exists}, problems[], notes[]}` |
| `sys/backups/~act/restore_apply {upload, sections, mode, passphrase?, accept?, replace_keys?}` | `add`: `{done[], skipped[], restart: false}`; `replace`: `{sections, restart: true}` |

- **`mode: add`** works live. Sections `links` and `storage`. Links that do not exist are installed as `install_backup` does; storage nodes that do not exist are added. Nothing is replaced. `dataflows` is skipped with a note: a flow is deployed with proofs of its deployer.
- **`mode: replace`** takes `control`, `keys`, `dataflows`, `storage`, `history`, `links`, `packages`. A caller whose authority comes from an upstream (`allow_config`) is refused `replace` altogether, before the file is read: it would replace this site's control state, links and packages. `add` stays open to it, with its `accept`.
  1. The broker makes a `pre-restore` backup of the same sections.
  2. It stages the sections in `data_dir/restore.pending` (written whole or not at all) and checks that each WAL opens with the keys that will be in place.
  3. It answers, then stops. The supervisor starts it again (`Restart=always`).
  4. The next start applies the folder before any store opens, then removes it. A start that stops halfway is taken up by the next one. The audit gets `restore_applied`.
- A backup of another site name is refused. Set `site` in `wyrmd.json5` to the backup's first.
- A backup whose store SCHEMA is newer than this broker reads is refused.
- **The `keys` section** is restored only through three gates, whatever the keys are (also the keys of this very broker): `backups.export_secrets: true` on the host, a caller of this site, and the passphrase.
- **`replace_keys: true`** is needed too unless every key file of the backup is byte for byte this broker's. `restore_check` answers `keys`: `same` (all identical), `differ` (this CA, other key files: `state.key`, `secrets.key`, a gateway key, `secrets.bin`, a link token), `other` (another CA), and lists the files in `keys_differ`. With another CA, the certificates it issued are removed; link processes, operators and peer brokers enrol again. The `pre-restore` backup holds the old keys, under the same passphrase, whenever keys are replaced.
- **Only defined files are restored.** Each file of a backup must be one its section defines, or the whole backup is refused by the check and by both modes: under `keys/` exactly the key files (`pki/ca.pem`, `pki/ca.key`, `state.key`, `secrets.key`, `flows.key`, `gateway/hmac.key`, `gateway/gateway.key`, `flows/flow.key`), `secrets.bin` and `links/<link id>/token`; `control/<store>/<file>` of the four WAL stores; `dataflows/artifacts/**`; `storage/tree.cbor` and `export.json`; `history/index.redb` and `history/days/<day>.redb`; `links/<link id>/{link.cbor, secrets, files/**}`; `packages/<name>/files/**`; `config/wyrmd.json`. The broker builds every destination from these checked parts; it never joins a path of the archive to a directory.
- **Packages** of a `replace` pass the validator of every install (`packages::unpack`). What a package asks for (requester grants, network) needs `accept: true`, unless this broker has the same version with the same files; without it the answer lists them and nothing is staged.
- **Link secrets.** Without `keys`, a link's secrets go into this broker's store, and the ones a broker makes for a link's identity (requester key, agent signing key) are dropped, as in `install_backup`. With `keys`, `secrets.bin` of the backup comes back whole, the broker-made ones among them: they are that site's own identity, restored under the gates above.
- `control` of a backup under other keys is restored only together with `keys`.
- With `state_anchor_dir` set, `control` is restored offline (`docs/operations.md` §3).
- `links` with `control` restores the private data of every link of the backup; without `control`, of the links this broker has.
- The audit journal is replaced only when `state.key` is.

To move a site to a new host: install `wyrmd` with the same `site` and `backups.export_secrets: true`, start it, upload the backup, `restore_apply` with `mode: replace`, `replace_keys: true` and every section.

## 5. For code

- `Control::link_backup_to(id, path)` writes a link backup without history to `path`, sealed for this broker (no passphrase, no `export_secrets`). The link keeps running.
- `Control::link_restore_data(id, path)` gives a stopped link the secrets and private data of such a file. The data directory is built new and swapped in.
- Restore points (`wyrm_admin::restore_point`, `Control::restore_point_now`) are such files without the package, with a `.meta` beside them.
- A link's private data is read only through `wyrm_admin::nofollow`: the link may run and owns the directory, so no symlink is followed and every file is sealed from the handle the walk opened. Entries that are not files or directories are skipped; the section's `info.skipped` counts them.
