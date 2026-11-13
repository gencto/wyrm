# ADR 0048 — Updates, restore points and backups from Studio

Status: proposed (2026-11-13, owner request). Design: canvas row *Updates, restore points, backups* (`LinkUpdate*`, `BrokerUpdate*`, `Backup*`, `LinkBackup`); Studio side: `studio/docs/design/specs/updates-backups.md`.

## Context

What exists today:
- **Packages** (ADR 0011, 0043). Installing a newer version of a package (from the repository, a zip, a URL or git) replaces the old one: `install_package` unpacks the new version, restarts every link that runs it (`upgrade_links`; a WASM app gets a hot start) and **deletes the old version's directory**. There is no way back and no check that a link came back with its nodes. The repository index is read every hour, but nothing says that an installed package has a newer version.
- **Link state.** A framework link keeps its runtime edits and secrets sealed in `data_dir/links/<id>/data` (`framework.tree`, ADR 0004); a portable app keeps its sealed store there (ADR 0023). Framework links export and import their settings as JSON (`wyrm-driver-branch/1`); there is no export of a link as a whole (settings, private data, package, grants, net).
- **The broker.** `wyrmd` is updated by hand: replace the binary, restart under systemd (`docs/operations.md` §2). No release index, no signature, no way back once the registry SCHEMA moved (today 19).
- **Backups** are offline copies of `data_dir` with the broker stopped (`docs/operations.md` §3), plus `wyrmd keys export` for the keys. The standby (ADR 0036) already knows how to copy every store consistently while the broker runs: WAL records, sealed files in parts, the storage journal and history rows (`control/replication.rs`, `sys/replication/**`).

The owner asks (2026-11-13): update links and the broker from Studio by a remote command, with a way back that restores the state; official links update from the repository, custom ones by bringing a new archive, and the nodes and state of the previous version are kept; export a link as one zip; back up the broker from Studio with checkboxes per section (history, storage, dataflows, links, …).

## Decision

### 1. Package updates with restore points

1. `sys/packages/<name>` shows `version`, `latest` (from the repository index; empty for custom packages), `update_available` (bool), `previous` (the version kept for a rollback, with `keep_until`) and `last_update` (a map: `from`, `to`, `at`, `result` = `ok | rolled_back | failed`, `kept`, `new`, `gone` counts and up to 200 keys of `new` and `gone`). `sys/links` gains `updates_available` (count) so Studio can badge it.
2. Action `sys/packages/<name>/~act/update {version?, accept, restore_point = true, auto_rollback_s = 120}` (config, audited): installs `version` (default `latest`) from the repository with its SHA-256, the same flow as `install_repo`. A custom package is updated by the existing `install_zip` / `install_url` / `install_git` with the same package name; they take the same three new arguments.
3. Before anything stops, for every link that runs the package: a **restore point**, which is a link backup (§3.5) without history, written to `data_dir/restore/<link>/<UTC>.wyrm-link`, and the link's current key list (`~meta?view=keys` of its root). Restore points are listed at `sys/links/<id>/restore_points` (`at`, `version`, `size`) and pruned after `packages.keep_previous_days` (default 7).
4. The previous version's directory is **kept** (no `remove_dir_all`) until `keep_until`; the registry's `PackageDef` keeps `previous`.
5. Health after the restart: every link of the package must say `hello` and declare at least every key it had, within `auto_rollback_s`. Keys that do not come back are `gone`; new ones are `new`. With `auto_rollback_s > 0` and anything `gone` (or a link that never says hello), the broker rolls back by itself (§1.6) and audits `update_rollback` with the reason. With `0`, it keeps the new version and reports.
6. `sys/packages/<name>/~act/rollback {to?}` (config): reinstalls `previous` from its kept directory, stops the links, restores each link's private data from its newest restore point taken before that update, starts them. A rollback is itself recorded in `last_update`.
7. Store format: the package manifest gains `state` (integer, default 1) and `reads_state` (list, default `[state]`). An update whose `reads_state` does not contain the installed `state` is shown as *changes the store format* (Studio's review says so); the rollback then needs the restore point and Studio does not let the person untick it.
8. One version per package stays the rule: every link of a package is updated together (Studio lists them).

### 2. Broker updates

1. Install layout for self-updating brokers: `<prefix>/versions/<v>/wyrmd`, `<prefix>/current` → `versions/<v>`, `<prefix>/bin/wyrmd-guard` (a copy of the running binary, refreshed only after an update is confirmed). The systemd unit runs `ExecStartPre=<prefix>/bin/wyrmd-guard update-guard` and `ExecStart=<prefix>/current/wyrmd`. `docs/operations.md` gains the layout and the unit.
2. Config: `updates: {mode: "self" | "external" (default), channel: <URL of the releases index>, keys: [<Ed25519 public keys>], trial_s: 180, keep_days: 7}`. The WYRM release key is built in; `keys` adds others (a company mirror). `external` (containers, distribution packages) refuses `update` with a message and shows how to update outside.
3. Releases: a new release workflow publishes `wyrmd-<version>-<target>.tar.zst`, its SHA-256 and an Ed25519 signature, and a signed `releases.json` (version, date, notes URL, targets, min `from` version, `schemas` it writes, replication protocol version). Until that workflow exists, `update {file}` takes an uploaded archive with its signature (parts, as ADR 0028).
4. `sys` shows `update_available`, `latest`, `update_state` (`none | staged | trial | confirmed | rolled_back`) and `update_last` (map). Action `sys/~act/update {version, confirm_site}` (config, audited; `confirm_site` must equal the site name):
   1. download into `versions/<v>.part`, check signature and SHA-256;
   2. run `versions/<v>/wyrmd check -c <config>` (the new binary checks this configuration);
   3. pre-update backup of the control plane and keys (§3 sections `control` and `keys`, sealed with a key derived from `secrets.key`, so no passphrase is needed) into `data_dir/backups/pre-update-<v>.wyrm-backup`;
   4. write `data_dir/update.json` `{from, to, state: "trial", attempts: 0, deadline, backup}`, point `current` at `versions/<v>`, copy the running binary to `bin/wyrmd-guard`, and stop cleanly (exit 0; systemd `Restart=always` starts the new one).
5. Trial: the new `wyrmd` increments `attempts` first thing. It is healthy when the router is up, the gateway listens, the admin answers and every link that was connected before the update says `hello` (process links get `trial_s`). Healthy → `state: confirmed`, audit `update_confirmed`, the guard binary is replaced by the new one. Not healthy by `deadline`, or `attempts ≥ 3`: it exits with code 76.
6. `update-guard` (the previous binary) runs before every start: with `state: trial` and (`attempts ≥ 3` or the deadline passed or a 76 recorded), it points `current` back at `from`, restores the control-plane files from the pre-update backup when the new version moved a SCHEMA, sets `state: rolled_back` and lets systemd start the old binary. Audit `update_rollback` is written by the old binary at start.
7. `sys/~act/rollback_update` (config) after a confirmed update, until `keep_days`: same as §2.6, on purpose. Changes made after the update are lost (the pre-update backup is restored); the review says so.
8. Standby pair (ADR 0036): `update` refuses on the active while the standby runs an older version and the release changes the replication protocol; Studio offers to update the standby first (through its own `sys`, reached via the peer link). The same action reaches a downstream broker through its upstream with `allow_config` (ADR 0018).

### 3. Backups

1. Format: `.wyrm-backup`, a zip with `manifest.json` first: `wyrm_backup: 1`, `site`, `broker` (version), `created`, `schemas` (registry, users, flows, audit), `sealed` (how keys and secrets are sealed: `passphrase` with Argon2id parameters, or `broker`), and `sections[]`, each with its files, sizes and SHA-256. A link backup is the same format with `kind: "link"`, extension `.wyrm-link`. The format lives in `wyrm_admin::backup` (`wyrmd` reaches it too). Rules of the `sealed` field and of the reader (2026-11-13, after the security review of the first commit):
   - `sealed: {how, kdf?, check, id, mac}`. `how` is `none`, `passphrase` (Argon2id, parameters in `kdf`, bounded by the reader) or `broker` (a key derived from `secrets.key`). `id` is 16 random bytes per backup; it is part of every file key, so a sealed part of another backup under the same passphrase does not open. `mac` is HMAC-SHA-256 over the whole manifest (every path, size, SHA-256, `sealed` and `exec` flag, every `info`) under a key from the master key and `id`.
   - A manifest with `how: passphrase | broker` and no `id`, `check` or `mac` is refused. The master key is handed out only after the MAC matches (`Manifest::key`); a restore of a sealed backup always asks for the key, also for its plain sections.
   - The reader, not the file, decides what must be sealed: every file of `keys`; in `links` each link's `secrets`, `token` and `files/**`; every file of a link backup's `data`. A manifest that lists one of them with `sealed: false` is refused, and so is any such file in a backup with `how: none`. `link.cbor` holds no secret (no token hash; params are linted at install).
   - A sealed file is a stream of parts of 1 MiB, each ChaCha20-Poly1305 under a key of its own file and backup, bound to its index and to the end of the stream.
   - Bounds: at most 100 000 entries, a manifest of 16 MiB, a path of 512 bytes and 24 segments without `.`, `..`, `\`, `:`; each file at most 1 TiB; sizes are added with an overflow check; every zip entry must be listed with its size, and every file is hashed as it is read.
   - A backup with `how: none` has no secret in it and no MAC: its SHA-256 (shown in `sys/backups/<id>`) is what proves it unchanged.
2. Sections: `control` (registry, users, flows store and audit: their WAL and snapshot as of one sequence number; always included, needed by the others), `keys` (CA, `state.key`, `secrets.key`, `flows.key`, gateway keys, `secrets.bin`, link tokens; sealed, never in clear), `dataflows` (the flow store; also inside `control`, listed for restore by itself), `storage` (the storage tree as `wyrm_storage` export plus its redb file), `history` (day files of a chosen range and `index.redb`), `links` (per chosen link: its `LinkDef`, the framework `export` when it has one, its private data dir sealed, its package archive), `packages` (all package archives), `config` (a copy of `wyrmd.json5`, never restored).
3. Consistency while running: WAL stores are copied as of one sequence; redb files are copied from inside one read transaction each; history days are copied whole (closed days) or through `Store::changes` for today; the storage journal fixes the storage at one `rev`. These are the standby's primitives (`control/replication.rs`), reused, not copied.
4. API at `sys/backups` (config, audited; the arguments never carry the passphrase into the audit):
   - `create {sections, links?, history_days?, passphrase?}` → `{id}`; a job, one at a time; `sys/backups/<id>` shows `status`, `progress`, `size`, `sha256`, `created`, `expires`;
   - `download_part {offset, len ≤ 16 MiB}` (as ADR 0028), `remove`;
   - `send {link, path}`: the broker writes the file through a file-store link (S3, WebDAV, localfs) with its own key; that link must grant the admin `write` (ADR 0046 style), else refused;
   - kept under `data_dir/backups` for `backups.keep_days` (7) within `backups.max_mb` (oldest removed first; pre-update backups of an unconfirmed update are never removed).
5. Link backup: `sys/links/<id>/~act/backup {sections: [settings, data, package, history], history_days?, passphrase?}` → a job in `sys/backups` with `kind: link`. Restore: `sys/links/~act/install_backup` (Add a link ▸ From backup) with the file in parts, `id` (same or new), `accept` (its grants and net, as `install_*`), `passphrase`; replacing an existing link takes a restore point first.
6. Restore of a broker backup: `restore_begin` / `restore_part` / `restore_check {passphrase}` (returns the checks: site, keys, versions, what differs) / `restore_apply {sections, mode}`:
   - `mode: add`: live, no restart; only links, dataflows and storage nodes that do not exist yet;
   - `mode: replace`: a backup of what is replaced is made first, the chosen sections are staged into `data_dir/restore.pending`, the broker stops, and the next start applies them before opening any store (and removes the folder).
   - The `keys` section of another site is refused unless `replace_keys: true` (it changes the site's identity: peers and process links must enrol again; the check says which).

### 4. Rights and audit

Every action here is `config` on `sys` (or on `sys/links` / `sys/packages`), only the `admin` role reaches it through the gateway (ADR 0009), and an upstream only with `allow_config`. Audit records: `package_update`, `update_rollback`, `restore_point`, `update_start`, `update_confirmed`, `backup_create`, `backup_download`, `backup_send`, `restore_apply`, `link_backup`, `link_restore`. A backup is as sensitive as `data_dir`: Studio says so where it is made and downloaded.

## Consequences

- Package updates stop being one-way; the kept previous version and the restore points cost disk (a few MiB per link) for `keep_previous_days`.
- The package manifest gains `state` / `reads_state` (ADR 0011 format note); older packages read as `state: 1`.
- `wyrmd` gains `update-guard`, a release workflow and a signed index; self-update is opt-in (`updates.mode: "self"`) and needs the new install layout.
- Backups no longer need the broker stopped; `docs/operations.md` §3 keeps the offline copy as the way for a dead broker.
- New tests: e2e update of a package with a link that loses keys (rolls back), an update that changes `state`, a broker update whose trial fails (guard rolls back, SCHEMA restored), backup while writing and restore into a fresh `data_dir`, a link backup restored on a second broker under a new id.

## Not decided here

- Scheduled backups (a scheduler target can call `sys/backups/~act/create` once this exists; ADR 0022).
- Updates of many sites at once from a central broker (one action per site for now).
- Delta backups of history.
