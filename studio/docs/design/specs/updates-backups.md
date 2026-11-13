# Updates, restore points and backups

Boards (canvas row *Updates, restore points, backups*): `LinkUpdate` with `LinkUpdateProgress`, `LinkUpdateDone`, `LinkUpdateRolledBack`; `LinkBackup`; `BrokerUpdate` with `BrokerUpdateRestart`, `BrokerUpdateDone`, `BrokerUpdateRolledBack`, `BrokerUpdateExternal`; `Backup` (clickable checkboxes) with `BackupProgress`, `BackupDone`, `BackupRestore`. Broker side: **ADR 0048** (proposed). The boards win for what is visible; this spec says where each screen sits, what it reads and calls, and its states.

**Order of work.** The broker parts come first. ADR 0048 §1 (package updates) and §3 (backups, link backup, broker restore, `send`) are built: §1, §2 and §4 below name the broker's values and actions as they are in the code (guides `docs/links.md` §5a and `docs/backups.md`). ADR 0048 §2 (broker self-update) is not built: §3 below is the plan, and its entry points stay hidden, never shown disabled with a promise.

## 1. Updating links (`LinkUpdate*`)

### Where
- Links page: a filter tab `Updates` with the count from the **attribute** `updates_available` of `sys/links` (in its `~meta`, beside `catalog`; it is not a child value: a child there would list as a link). Hidden at 0. It counts links, the rows of the tab. A row shows `from → to` in the version column (`to` in `emberSoft`); custom packages show `Update from file…` instead of a version.
- `Update all official…` in the page header: one review for every official package with an update, then the same progress per package, one after another.
- Link inspector: `Update to <v>` (primary) when its package has an update (`sys/packages/<name>/update_available`); under *Versions*: restore points (`sys/links/<id>/restore_points`, rows `{at, version, size}`, newest first; a link replaced from a backup has one with an empty `version`) and `Roll back to <v>…` while the package has a `previous` (`{version, keep_until, changes_state}`). The broker has no download of a restore point: it is sealed for the broker and stays on it.

### Review (drawer 460 wide, board `LinkUpdate`)
- Title `Update <package> <from> → <to>`, pill `official` / `custom`, sub-line: source, how many links run it, release date.
- `What is new in <to>`: the repository index carries no release notes yet, so the block shows the `title` and `summary` of the package's `catalog` row; `notes` lines and `Full changelog ›` appear when the index has them. Custom: the archive's `wyrm-link.json` `description` and version; no notes.
- `What changes for the broker`, one card each (dot: `warn` when it needs attention, `good` otherwise):
  - the links that restart (all links of the package, by id) and the expected pause; a WASM app with a hot start says `hot start, no restart`;
  - `Settings and nodes are kept` with the counts read from the links now (connections, devices, points from the framework tree; or the key count);
  - new rights or network asked by the new version (diff of `requester` and `net` against the installed one);
  - store format: `sys/packages/<name>/changes_state` (the update to `latest` changes it; ADR 0048 §1.7). A custom archive: its manifest's `reads_state` does not hold the installed `state`.
- `Before it starts` (checkboxes): `Save a restore point …` (on; locked on when the store format changes) with its size estimate and `keep_previous_days`; `Roll back by itself if a link does not come back with all its nodes in 2 min` (on; `auto_rollback_s` 120 / 0); `Accept the new rights …` only when it asks for any (off; Update disabled until ticked).
- Footer: `Needs config on sys/links`, `Cancel`, `Update <n> links` → `sys/packages/<name>/~act/update {version, accept, restore_point, auto_rollback_s}`; custom → `sys/links/~act/install_zip` (file picked first; also `install_url`, `install_git`) with the same three arguments. Both answer `{success, message}` at once; without `accept` and with new rights the message lists them and nothing is installed.

### Progress (`LinkUpdateProgress`)
The action answers once the links restarted; there is no progress stream. The steps before the answer (restore point saved, package fetched and checked, unpacked beside the old version, links restarted) show as one spinner, then done from the answer's `message` and the new row of `sys/links/<id>/restore_points` (`at`, `size`). After it, Studio watches `sys/packages/<name>/last_update`: `result` is `checking` while the health check runs and `kept`, `new`, `gone` move (`n of m` nodes declared again, up to `auto_rollback_s`); it ends as `ok`, `rolled_back` or `failed`. While `checking`, another install of the package and its links' Start, Stop and Remove answer `busy`. Done = `good` ring, current = `ember` spinner, to do = `line3`. Footer: `You can leave this screen; it goes on.`, `Stop and roll back` (→ `sys/packages/<name>/~act/rollback`, which stops the check), primary disabled `Updating…`.

### Result (`LinkUpdateDone`, `LinkUpdateRolledBack`)
- Banner by `last_update.result`: `ok` → `Both links run 0.5.0` (good; warn with `reason` when `gone` > 0, which happens with `auto_rollback_s: 0`); `rolled_back` → `Rolled back to 0.4.2` (warn) with `reason` (which link, how many nodes came back, or `rolled back by <who>`); `failed` → the new version stays, a link did not answer (warn, offer Roll back). `checking` is the progress screen, never a result.
- `Nodes before and after`: three tiles `kept`, `new`, `gone` and up to 10 of `new_keys` / `gone_keys` (`<link>/<path>`; `+` good, `!` warn), from `last_update`.
- `Restore points`: newest first; `Roll back to <v>…` (confirm dialog naming the links that restart, `last_update.links`) → `rollback {to}`. After a rollback `previous` is empty: no second rollback.
- Footer: audit names, `Close`, `Open <link>` or `Open the log of <v>` (System › Log, source the link, time of the update).

## 2. Backing up and restoring one link (`LinkBackup`)
- Link inspector ▸ `Back up…` → the backup dialog with link sections (`sections` names in brackets): `Settings` (`settings`, always), `Private data` (`data`: secrets and the private directory, the runtime edits of a driver among them), `Package <name> <v>` (`package`), `History of its points` (`history`, range chips → `history_days`). Passphrase field: without one, `data` is sealed for this site and opens only on a broker with its keys (say so); with one it opens anywhere, and the field is disabled while `sys/backups` `export_secrets` is `false`. Footer `<size> · config on sys/links`, `Back up <link>` → `sys/links/<id>/~act/backup {sections, history_days, passphrase}` → `{id}`: a job in `sys/backups` with `kind: link`; then the job's progress and download as §4.
- Restore: Links ▸ `Add a link` ▸ a third source `From backup` (beside official and custom, board `LinkInstall`): pick a `.wyrm-link`, see its link, package, rights and net (accept as with any install), choose `id` (its own or a new one; replacing an existing link warns that a restore point is taken first), passphrase → upload in parts (`sys/backups/~act/restore_begin {size}`, `restore_part {upload, offset, data}`) then `sys/links/~act/install_backup {upload, id, accept, passphrase}` (a small file goes as `file`) → `{success, message}`.

## 3. Updating the broker (`BrokerUpdate*`)

### Where
System › Maintenance: a card `Broker version` (first on the tab): `0.1.0 · 0.2.0 is available` (from `sys` `latest`, `update_available`) with `Update…`; when `update_state` is `trial` or a rollback is still possible, the card shows that state and `Roll back to <v>…` until `keep_days`. The System attention panel adds `Broker update available` (info) and `Update rolled back` (warn).

### Review (dialog 640, board `BrokerUpdate`)
- Title `Update <site> to wyrmd <v>`, pill `<from> → <to>`, sub-line: release date, channel, `the broker restarts once`.
- `Checked before anything changes` (from a dry run: `sys/~act/update?check` with ADR 0047): signature and SHA-256, the new binary's `check` of the configuration, room on disk, SCHEMA moves (warn: rollback restores the pre-update backup, later changes lost), links built for this broker (`wyrm_link`), standby (warn: update the standby first, with a link to it).
- `How it goes`: the five steps of ADR 0048 §2.4–2.6 in plain words.
- `Type <site> to confirm` (input; the primary stays disabled until it matches) → `sys/~act/update {version, confirm_site}`.
- Downstream sites: the same dialog from Sites › site ▸ `Update broker…` when the upstream has `allow_config` (else not shown).

### Restarting (`BrokerUpdateRestart`)
Studio loses the gateway on purpose. The dialog stays, with a spinner card `<site> is restarting on <v>` and a counter, and the steps as they are known (before the restart from the action; after, from `sys` `update_state` once the socket is back). `WyrmGateway.loginAny` logs in again by itself (ADR 0036 option 2); the shell's offline banner says `Updating <site>` instead of `Connection lost`. The text under the steps says what links and devices do meanwhile.

### Result (`BrokerUpdateDone`, `BrokerUpdateRolledBack`, `BrokerUpdateExternal`)
- Confirmed: banner (good), facts `Version`, `Without the broker`, `Links back`, `Roll back` (until), `Audit`; buttons `Close`, `Roll back to <from>…` (neutral; its own confirm with `Changes made after the update are lost`).
- Rolled back: banner (warn) with the reason from `update_last`, facts `Tried`, `Reason`, `Now`, `Log of <v>`, `Audit`; `Open the log of <v>`.
- External (`updates.mode: "external"`): no update button; the dialog says the image is changed where the container is defined, shows the two commands, and offers `Make the backup` (§4 with `control` + `keys`).

## 4. Backing up and restoring the broker (`Backup*`)

### Where
System › Maintenance: the card `Back up and restore` (today the copyable commands of `system.md`) becomes `Backups`: the kept backups (`sys/backups/<id>`: attributes `name`, `kind` (`full`, `link`, `pre-update`, `pre-restore`), `sections`, `sealed`, `link`; values `status`, `size`, `created`, `expires`, `sent_to`; `Download`, `Send…`, `Remove`), `Back up…` (primary) and `Restore…`. The offline commands move under a disclosure `When the broker does not start`.

### Back up (board `Backup`, clickable)
- Sections as checkboxes with their sizes (`sys/backups/~act/estimate {sections, links, history_days}` → `{sections: {name: bytes}, total}`); names from the attribute `sections` of `sys/backups`: `Control plane` (`control`, always, locked), `Keys and secrets` (`keys`, tag `passphrase`), `Dataflows` (`dataflows`), `Broker storage` (`storage`), `History` (`history`, range chips 7 / 30 / all / custom → `history_days`), `Links` (`links`, chips per link, all on → `links`; alarm records are the private data of the link `alarm`), `Installed packages` (`packages`), `wyrmd.json5 (read only)` (`config`: secrets masked, never restored). Unticked rows dim to 55 %.
- `Passphrase for the keys and secrets` (password field; without it `Keys and secrets` is unticked and disabled with the reason).
- `export_secrets` is an **attribute of `sys/backups`** (`backups.export_secrets` in `wyrmd.json5`, set on the host): while `false`, `Keys and secrets` and the passphrase field are disabled with that reason; link secrets are then sealed for the site and the file opens only on a broker with its keys. A session that reaches the site through an upstream never gets `keys` or a passphrase, whatever the attribute says: the refusal's message is shown.
- `Where`: `This computer` (`download_part {offset, len}` until `eof`), `File store link…` (only when the attribute `send_links` of `sys/backups` is not empty: pick one of those links and a folder node under it, `<connection>/files[/<folder>]`; after the job is done → `sys/backups/<id>/~act/send {link, path, name}`, then `send_status` `sending` / `done` / `failed` with `send_progress`, `send_error`; not offered for a backup with `Keys and secrets`), `Keep on the broker` (kept `keep_days`, attribute of `sys/backups`).
- Footer: total size, `config on sys`, `Back up` → `sys/backups/~act/create {sections, links, history_days, passphrase}` → `{id}`.
- Progress (`BackupProgress`): a bar (`progress`), the current section (`step`), per-section rows (done good, current ember, to do muted), the line about one consistent moment. Closing the dialog leaves the job running; the Backups card shows it.
- Done (`BackupDone`): file name, size, sections, SHA-256, broker version and registry SCHEMA, the warning that the file and passphrase make an administrator; `Show in Backups`.

### Restore (board `BackupRestore`)
- `Restore…` ▸ pick a `.wyrm-backup` (upload in parts: `restore_begin {size}` → `{upload, part_size}`, `restore_part {upload, offset, data}`; `restore_abort {upload}` on cancel) → `restore_check {upload, passphrase}` → the checks, from its answer: `same_site`, `keys` (`none`, `same`, `differ`, `other`) with `keys_differ` (the key files that are not this broker's), `control_opens_here`, `schemas` (`backup` / `here`), `links` (`new` / `exists`), `problems` (each blocks `replace`), `notes`; and the file's `sections` as checkboxes (history off by default).
- `How`: `Replace what is ticked and restart the broker once (a backup of what it replaces is made first)` (`mode: replace`: `control`, `keys`, `dataflows`, `storage`, `history`, `links`, `packages`) or `Add only …; nothing replaced, no restart` (`mode: add`: `links`, `storage`).
- `Keys and secrets` in a restore is enabled only with `export_secrets`, a passphrase and a session on the site's own gateway. When `keys` is `differ` or `other`, a checkbox `Replace the site's keys` (`replace_keys`) names `keys_differ`; for `other` it warns that links, operators and peer brokers enrol again.
- `Accept the rights …` (`accept`) when the answer of `restore_apply` lists what links (`add`) or packages (`replace`) ask for.
- `mode: replace` is not offered to a session that reaches the site through an upstream (the broker refuses it); `add` is.
- Footer: `Restore and restart` / `Add` → `restore_apply {upload, sections, mode, passphrase, accept, replace_keys}` → `add`: `{done, skipped, restart: false}`; `replace`: `{sections, restart: true}`, then the restart pattern of §3 (reconnect, then a result banner).

## 5. Data and calls (summary)
| Screen | Reads | Calls |
|---|---|---|
| Links › Updates | `sys/links` attributes `updates_available`, `catalog`; `sys/packages/<name>` values `version`, `latest`, `update_available`, `state`, `changes_state`, `previous`, `last_update` (`result`: `checking`, `ok`, `rolled_back`, `failed`) | `sys/packages/<name>` `update`, `rollback`; `sys/links` `install_zip`, `install_url`, `install_git` (custom) |
| Link inspector | `sys/links/<id>/restore_points` | `sys/links/<id>` `backup`; `sys/packages/<name>` `rollback` |
| Add a link ▸ From backup | the uploaded file's manifest | `sys/backups` `restore_begin`, `restore_part`, `restore_abort`; `sys/links` `install_backup` |
| System › Broker version | `sys` `version`, `latest`, `update_available`, `update_state`, `update_last` | `update` (`?check` first), `rollback_update` |
| System › Backups | `sys/backups` attributes `export_secrets`, `send_links`, `sections`, `keep_days`, `max_mb`; `sys/backups/<id>` attributes `kind`, `name`, `sections`, `sealed`, `link`, values `status`, `progress`, `step`, `size`, `sha256`, `created`, `expires`, `error`, `sent_to`, `send_status`, `send_progress`, `send_error` | `sys/backups` `estimate`, `create`, `restore_begin`, `restore_part`, `restore_abort`, `restore_check`, `restore_apply`; `sys/backups/<id>` `download_part`, `send`, `remove` |

All are config; the views check `site.needs('config', …)` and hide the buttons for others (Studio's rule). Every long call shows its progress and survives closing the screen; errors follow `errors.md` (a timeout on `update` says the update may be running: Studio re-reads `update_state` before offering anything).

## 6. Checklist
- [ ] Updates tab and count; official and custom rows; Update all official.
- [ ] Review: notes, what changes, rights diff, store format, restore point and auto rollback options.
- [ ] Progress from the broker; leaving and coming back shows the same job.
- [ ] Result: kept/new/gone, restore points, rollback.
- [ ] Link backup and restore (same id, new id, another broker).
- [ ] Broker update: checks, confirm by site name, restart with reconnect, confirmed / rolled back / external.
- [ ] Backups: sections with sizes, passphrase, three destinations, progress, done, list, download, remove.
- [ ] Restore: checks, sections, replace / add, restart.
- [ ] Goldens for the 14 frames.
