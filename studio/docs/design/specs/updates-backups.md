# Updates, restore points and backups

Boards (canvas row *Updates, restore points, backups*): `LinkUpdate` with `LinkUpdateProgress`, `LinkUpdateDone`, `LinkUpdateRolledBack`; `LinkBackup`; `BrokerUpdate` with `BrokerUpdateRestart`, `BrokerUpdateDone`, `BrokerUpdateRolledBack`, `BrokerUpdateExternal`; `Backup` (clickable checkboxes) with `BackupProgress`, `BackupDone`, `BackupRestore`. Broker side: **ADR 0048** (proposed). The boards win for what is visible; this spec says where each screen sits, what it reads and calls, and its states.

**Order of work.** The broker parts come first. ADR 0048 §1 (package updates) and §3 (backups, link backup, broker restore, `send`) are built: §1, §2 and §4 below name the broker's values and actions as they are in the code (guides `docs/links.md` §5a and `docs/backups.md`). ADR 0048 §2 (broker self-update) is built too: §3 below names its values and actions as they are in the code (guide `docs/operations.md` §2 "A broker that updates itself"). It is opt-in on the host (`updates.mode`); with `off` the card is not shown.

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
System › Maintenance: a card `Broker version` (first on the tab), by `sys/update_mode` (`off`, `external`, `self`): hidden for `off`. `0.1.0 · 0.2.0 is available` (from `sys` `version`, `latest`, `update_available`) with `Update…` (`self`) or `How to update…` (`external`); `Check now` → `sys/~act/check_updates` → `{latest, update_available}`. When `sys/update_hint` is not empty in `self` mode (the layout or the guard is missing, the index cannot be read, no channel), the card shows that text and `Update…` opens the file path below (no channel) or is disabled (layout, guard). When `update_state` is `trial`, or `confirmed` with `update_last.keep_until` in the future, the card shows that state and `Roll back to <update_last.from>…`. The System attention panel adds `Broker update available` (info) and `Update rolled back` (warn; `failed`: the new version stays).

### Review (dialog 640, board `BrokerUpdate`)
- Title `Update <site> to wyrmd <v>`, pill `<from> → <to>`, sub-line: release date (`update_last.latest_date`), channel, `the broker restarts once`.
- `Checked before anything changes`: a dry run `sys/~act/update?check` with the same arguments (ADR 0047). It answers `ok` or one refusal (its message is shown as the failed check): mode, site name, layout and guard, another job, the release's signature, version and SCHEMA rules, the standby. It does not fetch the archive; the archive's hash, the new binary's `check` of the configuration and state, and the room on disk are checked by `update` itself and show in the progress. The broker returns no list of checks.
- `How it goes`: the steps of `docs/operations.md` in plain words.
- `Type <site> to confirm` (input; the primary stays disabled until it matches) → `sys/~act/update {version, confirm_site}` → `{success, message, version, restart}` at once.
- Without a channel (`update_hint` says so; today's way): `Update from file…` picks the archive, its `.release.json` and `.sig`; the archive goes up in parts (`sys/backups/~act/restore_begin {size}`, `restore_part {upload, offset, data}`), then `update {upload, release, signature, confirm_site}` (`release` and `signature` as text).
- A standby pair (`sys/standby_version` exists): two steps. `Update the standby` → `update {target: "standby", upload, release, signature, confirm_site}`, then `sys/standby_update` (`ordered <v>`, `<v> trial`, `<v> confirmed`, `<v> rolled_back`, `<v> failed`); `Update this broker` is enabled when `standby_version` is the target and `standby_update` is `<v> confirmed`. `without_standby: true` only behind its own confirm, when the standby is not connected. The standby step needs the file path.
- Downstream sites: the same dialog from Sites › site ▸ `Update broker…` when the upstream has `allow_config` (else not shown). `Roll back` is not offered there (the broker refuses it for such a session).

### Restarting (`BrokerUpdateRestart`)
Before the restart the steps come from `update_last.step` (`fetching`, `checking`, `staged`, `backup`) while `update_state` is `none` or `staged`; an update that ends there shows `update_last.result: failed` with `reason` and nothing changed. Then Studio loses the gateway on purpose. The dialog stays, with a spinner card `<site> is restarting on <v>` and a counter. `WyrmGateway.loginAny` logs in again by itself (ADR 0036 option 2); the shell's offline banner says `Updating <site>` instead of `Connection lost`. After the socket is back: `update_state` `trial` (a countdown to `update_last.deadline`, `attempts`), then `confirmed`, or `rolled_back` on the old version. The text under the steps says what links and devices do meanwhile.

### Result (`BrokerUpdateDone`, `BrokerUpdateRolledBack`, `BrokerUpdateExternal`)
- Confirmed: banner (good), facts `Version` (`to`), `Without the broker` (`without_s`), `Links back` (`links`), `Roll back` (until `keep_until`), `Audit` (`update_start`, `update_confirmed`); buttons `Close`, `Roll back to <from>…` (neutral; its own confirm with the site name and `Changes made after the update are lost` when `schemas_moved` is not empty) → `sys/~act/rollback_update {confirm_site}`.
- Rolled back: banner (warn) with `update_last.reason`, facts `Tried` (`to`), `Reason`, `Now` (`from`), `Control plane restored` (`restored`), `Audit` (`update_rollback`); `Open the log`.
- External (`update_mode: external`): no update button; the dialog shows `sys/update_hint` (what to run outside the broker) and offers `Make the backup` (§4 with `control`).

## 4. Backing up and restoring the broker (`Backup*`)

### Where
System › Maintenance: the card `Back up and restore` (today the copyable commands of `system.md`) becomes `Backups`: the kept backups (`sys/backups/<id>`: attributes `name`, `kind` (`full`, `link`, `pre-update`, `pre-restore`), `sections`, `sealed`, `link`; values `status`, `size`, `created`, `expires`, `sent_to`; `Download`, `Send…`, `Remove`), `Back up…` (primary) and `Restore…`. The offline commands move under a disclosure `When the broker does not start`.

### Back up (board `Backup`, clickable)
- Sections as checkboxes with their sizes (`sys/backups/~act/estimate {sections, links, history_days}` → `{sections: {name: bytes}, total}`); names from the attribute `sections` of `sys/backups`: `Control plane` (`control`, always, locked), `Keys and secrets` (`keys`, tag `passphrase`), `Dataflows` (`dataflows`), `Broker storage` (`storage`), `History` (`history`, range chips 7 / 30 / all / custom → `history_days`), `Links` (`links`, chips per link, all on → `links`; alarm records are the private data of the link `alarm`), `Installed packages` (`packages`), `wyrmd.json5 (read only)` (`config`: secrets masked, never restored). Unticked rows dim to 55 %.
- `Passphrase for the keys and secrets` (password field; without it `Keys and secrets` is unticked and disabled with the reason).
- `export_secrets` is an **attribute of `sys/backups`** (`backups.export_secrets` in `wyrmd.json5`, set on the host): while `false`, `Keys and secrets` and the passphrase field are disabled with that reason; link secrets are then sealed for the site and the file opens only on a broker with its keys. A session that reaches the site through an upstream never gets `keys` or a passphrase, whatever the attribute says: the refusal's message is shown.
- `Where`: `This computer` (`download_part {offset, len}` until `eof`), `File store link…` (only when the attribute `send_links` of `sys/backups` is not empty; its rows are `{link, folder}`: pick one of those links and one of its connections, show the folder the host named (read only), optionally a file name or sub-path below it; after the job is done → `sys/backups/<id>/~act/send {link, connection, path}`, then `send_status` `sending` / `done` / `failed` with `send_progress`, `send_error`; an existing name is refused, never replaced; not offered for a backup with `Keys and secrets`), `Keep on the broker` (kept `keep_days`, attribute of `sys/backups`).
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
| System › Broker version | `sys` `version`, `latest`, `update_available`, `update_state` (`none`, `staged`, `trial`, `confirmed`, `rolled_back`, `failed`), `update_last`, `update_mode`, `update_hint`, `standby_version`, `standby_update` | `sys` `update` (`?check` first), `rollback_update`, `check_updates`; `sys/backups` `restore_begin`, `restore_part` (the archive) |
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
