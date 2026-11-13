# Updates, restore points and backups

Boards (canvas row *Updates, restore points, backups*): `LinkUpdate` with `LinkUpdateProgress`, `LinkUpdateDone`, `LinkUpdateRolledBack`; `LinkBackup`; `BrokerUpdate` with `BrokerUpdateRestart`, `BrokerUpdateDone`, `BrokerUpdateRolledBack`, `BrokerUpdateExternal`; `Backup` (clickable checkboxes) with `BackupProgress`, `BackupDone`, `BackupRestore`. Broker side: **ADR 0048** (proposed). The boards win for what is visible; this spec says where each screen sits, what it reads and calls, and its states.

**Order of work.** The broker parts of ADR 0048 come first (they do not exist yet). Studio builds each screen when its broker part is merged; until then the entry points are hidden, never shown disabled with a promise.

## 1. Updating links (`LinkUpdate*`)

### Where
- Links page: a filter tab `Updates` with the count from `sys/links` `updates_available` (hidden at 0). A row shows `from → to` in the version column (`to` in `emberSoft`); custom packages show `Update from file…` instead of a version.
- `Update all official…` in the page header: one review for every official package with an update, then the same progress per package, one after another.
- Link inspector: `Update to <v>` (primary) when its package has an update; under *Versions*: restore points (`sys/links/<id>/restore_points`) with `Roll back to <v>…` on the newest and `Download` on each.

### Review (drawer 460 wide, board `LinkUpdate`)
- Title `Update <package> <from> → <to>`, pill `official` / `custom`, sub-line: source, how many links run it, release date.
- `What is new in <to>`: the release notes from the repository index (`notes` lines, ≤ 5) and `Full changelog ›` (its URL). Custom: the archive's `wyrm-link.json` `description` and version; no notes.
- `What changes for the broker`, one card each (dot: `warn` when it needs attention, `good` otherwise):
  - the links that restart (all links of the package, by id) and the expected pause; a WASM app with a hot start says `hot start, no restart`;
  - `Settings and nodes are kept` with the counts read from the links now (connections, devices, points from the framework tree; or the key count);
  - new rights or network asked by the new version (diff of `requester` and `net` against the installed one);
  - store format: same (`state` in `reads_state`) or `changes` (§ ADR 0048 1.7).
- `Before it starts` (checkboxes): `Save a restore point …` (on; locked on when the store format changes) with its size estimate and `keep_previous_days`; `Roll back by itself if a link does not come back with all its nodes in 2 min` (on; `auto_rollback_s` 120 / 0); `Accept the new rights …` only when it asks for any (off; Update disabled until ticked).
- Footer: `Needs config on sys/links`, `Cancel`, `Update <n> links` → `sys/packages/<name>/~act/update {version, accept, restore_point, auto_rollback_s}`; custom → `install_zip` (file picked first) with the same three arguments.

### Progress (`LinkUpdateProgress`)
Steps from the action's progress stream (or by watching `sys/packages/<name>/last_update` and the links' state): restore point saved (path, size), package fetched and checked (file, SHA-256), unpacked beside the old version, then per link `restarted on <v>` (hello time) and `nodes declared again` (`n of m`, waiting up to `auto_rollback_s`), then `Health`. Done = `good` ring, current = `ember` spinner, to do = `line3`. Footer: `You can leave this screen; it goes on.`, `Stop and roll back` (→ `rollback`), primary disabled `Updating…`.

### Result (`LinkUpdateDone`, `LinkUpdateRolledBack`)
- Banner: `Both links run 0.5.0` (good) or `Rolled back to 0.4.2` (warn) with the reason from `last_update` (which link, how many nodes came back).
- `Nodes before and after`: three tiles `kept`, `new`, `gone` and up to 10 keys of `new`/`gone` (`+` good, `!` warn), from `last_update`.
- `Restore points`: newest first; `Roll back to <v>…` (confirm dialog naming the links that restart) → `rollback`.
- Footer: audit names, `Close`, `Open <link>` or `Open the log of <v>` (System › Log, source the link, time of the update).

## 2. Backing up and restoring one link (`LinkBackup`)
- Link inspector ▸ `Back up…` → the backup dialog with link sections: `Settings and nodes` (always), `Private data` (passphrase), `Package <name> <v>`, `History of its points` (range chips). Footer `<size> · config on sys/links`, `Back up <link>` → `sys/links/<id>/~act/backup {sections, history_days, passphrase}`; then the job's progress and download as §4.
- Restore: Links ▸ `Add a link` ▸ a third source `From backup` (beside official and custom, board `LinkInstall`): pick a `.wyrm-link`, see its link, package, rights and net (accept as with any install), choose `id` (its own or a new one; replacing an existing link warns that a restore point is taken first), passphrase → `sys/links/~act/install_backup`.

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
System › Maintenance: the card `Back up and restore` (today the copyable commands of `system.md`) becomes `Backups`: the kept backups (`sys/backups/*`: name, size, created, kind `full`, `pre-update`, `link`; `Download`, `Remove`), `Back up…` (primary) and `Restore…`. The offline commands move under a disclosure `When the broker does not start`.

### Back up (board `Backup`, clickable)
- Sections as checkboxes with their sizes (from the job's estimate, `sys/backups` `estimate {sections}`): `Control plane` (always, locked), `Keys and secrets` (tag `passphrase`), `Dataflows`, `Broker storage`, `History` (range chips 7 / 30 / all / custom), `Alarms`, `Links` (chips per link, all on), `Installed packages`, `wyrmd.json5 (read only)`. Unticked rows dim to 55 %.
- `Passphrase for the keys and secrets` (password field; without it `Keys and secrets` is unticked and disabled with the reason).
- `sys/backups` attribute `export_secrets` (`backups.export_secrets` in `wyrmd.json5`, set on the host): while `false`, `Keys and secrets` and the passphrase field are disabled with that reason; link secrets are then sealed for the site and the file opens only on a broker with its keys.
- `Where`: `This computer` (download in parts), `File store link…` (pick a file-store link and a folder; `send`), `Keep on the broker` (kept `keep_days`).
- Footer: total size, `config on sys`, `Back up` → `sys/backups/~act/create`.
- Progress (`BackupProgress`): a bar, the current section and day, per-section rows (done good, current ember, to do muted), the line about one consistent moment. Closing the dialog leaves the job running; the Backups card shows it.
- Done (`BackupDone`): file name, size, sections, SHA-256, broker version and registry SCHEMA, the warning that the file and passphrase make an administrator; `Show in Backups`.

### Restore (board `BackupRestore`)
- `Restore…` ▸ pick a `.wyrm-backup` (upload in parts) → `restore_check {passphrase}` → the checks (file and SHA-256, site and keys, links that differ, restart needed) and the file's sections as checkboxes (history off by default).
- `How`: `Replace what is ticked and restart the broker once (a backup of what it replaces is made first)` or `Add only …; nothing replaced, no restart`.
- Footer: `Restore and restart` / `Add` → `restore_apply {sections, mode}`; replace follows the restart pattern of §3 (reconnect, then a result banner).

## 5. Data and calls (summary)
| Screen | Reads | Calls |
|---|---|---|
| Links › Updates | `sys/links` `updates_available`, `sys/packages/*` `version`, `latest`, `update_available`, `previous`, `last_update` | `update`, `rollback`, `install_zip` (custom) |
| Link inspector | `sys/links/<id>/restore_points` | `backup`, `rollback` |
| Add a link ▸ From backup | the uploaded file's manifest | `install_backup` |
| System › Broker version | `sys` `version`, `latest`, `update_available`, `update_state`, `update_last` | `update` (`?check` first), `rollback_update` |
| System › Backups | `sys/backups/*` | `estimate`, `create`, `download_part`, `send`, `remove`, `restore_begin/part/check/apply` |

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
