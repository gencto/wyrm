# ADR 0034 — Updating `wyrmd` through the tree (signed releases, restart by exec, rollback)

**Status:** proposed (draft for the owner) · 2026-11-01

## Context
A WYRM network is a chain of brokers (`plant → edge → central`, ADR 0007, 0015, 0018), often on boards that nobody visits. Today a new `wyrmd` reaches such a board by hand: copy the binary, restart the service, watch the log. Link packages already update at runtime (ADR 0011: a new version replaces the old one, the links restart on it, the old directory goes), and an upstream may command a downstream's `sys` when that site allows it (`allow_config`, ADR 0018). The owner asked whether updating the software itself through these means is reasonable.

Constraints that shape the answer:
- Principle 2: no dynamic plugins. A new version is a whole new binary, nothing finer.
- Principle 3: the broker owns only itself. Its control-plane state (WAL + postcard snapshot, `SCHEMA` migrations forward only) is the one thing an update must carry over and a rollback must not corrupt.
- Process links run `wyrmd link <driver>` from the broker's own binary (`current_exe`, `Daemon::open`), so a new broker binary is at once a new binary for every built-in process link. Package links bring their own binaries; they depend on the link protocol version only (`LINK_PROTOCOL`).
- Every ACL change already ends the router runtime and starts it again in the same process (ADR 0006): `Control::quiesce` → `Broker::stop` → `Broker::start`. An update is that path with a different binary at the end.
- A `config` user may today run arbitrary code on the host through a `process` package (ADR 0011, owner decision: no package signing). The broker binary is different: it holds every secret, so a bad one is the whole site. ADR 0031 (WASM-1) left signed repository indexes undone.

## Decision

### 1. A release is a signed manifest plus one binary per target
`wyrm-release.json` (JSON, a user file, `serde_json` as for packages):
```
{ "name": "wyrmd", "version": "0.2.0", "released": "2026-11-15T10:00:00Z",
  "min_from": "0.1.0",          // the oldest running version this one upgrades from
  "schema": 19,                 // registry SCHEMA the binary writes
  "link_protocol": 1,           // LINK_PROTOCOL of its wyrm-link-sdk
  "artifacts": { "aarch64-unknown-linux-gnu": { "url": "…/wyrmd", "sha256": "…", "size": 41234567 }, … },
  "notes": "…" }
```
- `wyrm-release.sig` = Ed25519 signature over the manifest file's bytes, by a **release key**. The public keys live in `wyrmd.json5` `update.keys` (hex, like `signers`); the private key never touches a broker. `wyr release sign` (a dev command) makes the pair and signs; CI signs with a secret. Without `update.keys` every update answers `success: false, "no release keys"`.
- The artifact is the bare executable (not a zip): the manifest's `sha256` and `size` pin it. Fetched with `wyrm_admin::fetch` (HTTPS, webpki roots, 3 redirects), at most 256 MiB and 10 min.
- `update.repository` (optional, like `packages.repository`): an index `[{version, released, manifest, sig}]` fetched in the background every `update.check_h` (default 24 h), never on the start path. It fills `sys/update/available`; nothing is applied on its own (policy `manual`; see open question 2).

### 2. Node `sys/update` (admin only, as all of `sys`)
Values: `version` (running), `previous` (the kept binary, or none), `state` (`idle | downloading | verifying | staged | restarting | settling | failed`), `error`, `staged` (version, sha256, source), `available` (from the repository), `last_check`.

Actions (level `config`, group "Update", each `{success, message}` as the install actions; `dry_run` as on every `sys/**/~act/*`):
- `check`: fetch the index now.
- `stage {version | manifest_url | manifest + sig + file}`: fetch (or take) the manifest, verify the signature against `update.keys`, pick this host's target, fetch the binary, verify `sha256` and `size`, write it to `data_dir/update/staged/wyrmd` (0700 dir, 0755 file, fsync). Then **preflight** the staged binary as a child process: `wyrmd --version` (a wrong architecture or a missing libc fails here, not after the restart) and `wyrmd -c <cfg> check-config` (a new subcommand: parse the configuration, open nothing). Refused: `version` not above the running one (`allow_downgrade: true` overrides; `rollback` is the separate way back), running version below `min_from`, a `link_protocol` other than the running one unless `accept_breaking: true` (the message lists the installed packages that would stop at `hello`), free space under 2 × size + 1 GiB. The message names the version, the SHA-256 and the packages affected.
- `apply`: restart on the staged binary (§3). `update {…}` = `stage` + `apply` in one call for the simple case.
- `abort`: drop the staged binary. `rollback`: restart on `previous` (§4), if there is one.
- Large arguments (`file`) travel as every other file: the gateway's `POST /api/invoke` for one piece (≤ 64 MiB), or in parts for an offline site: `update_begin {size, sha256}`, `update_part {index, data}`, `update_status`, `update_commit` — the spool of ADR 0028 on `sys/update` (parts ≤ 16 MiB, one upload at a time, dropped after an hour idle or on a restart). Each part is an ordinary action, so a chain of brokers carries it as any other.

### 3. Restart by `exec`, in place
- The staged binary replaces the one the broker was started from (`current_exe`): `<exe>.prev` ← current (kept), `<exe>` ← staged, by rename on the same file system, after the swap directory is fsynced. The broker must own that path; a path it cannot write (a binary installed by the OS package manager under `/usr/bin`) answers `success: false, "binary not writable: update it with the package manager"`. The broker never keeps a second copy under `data_dir` as the live one, so service files, `wyr` and operators keep one path.
- Then the same sequence as a rebuild: `Control::quiesce` (installs and uploads in flight finish, new ones answer `busy`), `Broker::stop`, `Control::shutdown` (every process link ends: the new binary starts them again from itself), the WAL flushed. `data_dir/update/pending.json` is written: `{from, to, sha256, started, attempts: 0, subject}`.
- The process then **`execv`s the new binary with its own arguments and environment** (Unix). The pid, the service unit, the terminal and the supervisor's view do not change; no `Restart=` policy is needed. If `execv` itself fails the old binary is still running: it restores `<exe>` from `.prev`, marks `failed` and starts its broker again. Windows has no `exec`: `apply` answers `not_supported` there until a spawn-and-exit path is written.
- Before the swap the old binary copies the control-plane stores (`data_dir/{registry,users,…}`: WAL + snapshot, small; not `history/`, not `packages/`, not link `data`) to `data_dir/update/state-<from>/`. This is what a rollback restores (§4).

### 4. Health check and rollback
- At every start `wyrmd` reads `pending.json` first. `attempts` is raised and written back before anything else opens. The new binary runs as usual and is **confirmed** when, within `update.health_s` (default 120 s), its broker is up, every store opened, every embedded and built-in process link reached `hello`, and the upstream connected when one is configured; then it stays up for `update.settle_s` (default 300 s). Confirmed: `pending.json` removed, `.prev` kept, audit `update_confirmed`.
- Not confirmed: the new binary itself **rolls back** when the health check fails (it has the stores and the audit log); a start that finds `attempts ≥ 2` (the new binary died twice before confirming) rolls back blindly. Rollback = `<exe>` ← `.prev`, the state copy of §3 restored over the stores (changes made during the failed run are lost: minutes at most, named in the audit record with both versions), `execv` of the old binary. A rollback that cannot restore (the copy is gone) stays on the new binary, `failed`, with the reason: it never leaves the site with no binary.
- A rolled-back version is remembered (`data_dir/update/refused.json`): `stage` of the same `sha256` answers `success: false` until `force: true`.
- `sys/update/state` and `sys/version` tell an operator or a plan what happened; every step is an audit record (`update_staged`, `update_applied`, `update_confirmed`, `update_rolled_back`, `update_failed`) with versions, SHA-256, source and the `ptok` subject.

### 5. A fleet from the upstream
- `sys/update/~act/*` of a downstream site is reachable from above only with `allow_config` (ADR 0018, spec 01 0.2.3): the same rule as every other `sys` action, nothing new in the ACL. Without it a site updates itself only (its own gateway, admin role).
- A rollout is a `wyrm-agent` plan (ADR 0033): `stage` on every site, then `apply` one site at a time with `wait`/`expect` on `sys/version` and `downstream/<d>/connected`; the sites that relay others (`via`) last, so a failed leaf is still seen through a healthy relay. Nothing in the broker orders sites: the plan does, and it stops at the first failure.
- An offline site (no HTTPS out) gets the binary in parts through the chain (§2), from a central that fetched it once.

### 6. Limits and what is not in this ADR
- One update at a time per broker (`stage` while `staged`/`restarting`/`settling` answers `busy`); a rebuild waits for a stage in flight as it waits for installs.
- The configuration file is never edited by an update. A version that refuses the old file fails preflight (`check-config`), not the restart.
- Not here: RTOS targets and device firmware (a driver-level action per protocol, ADR 0028 parts, later and case by case); signed link packages and repository indexes (ADR 0031 leftover; the same key and signature format fit, a short follow-up); automatic updates (open question 2); Windows.

## Consequences
- An operator or central updates a site with one action, and a broken release comes back by itself within `health_s + settle_s`; no visit to the board, no `Restart=` policy to get right.
- The trust anchor moves: a stolen **release key** is every broker that trusts it (full host compromise, every secret). It is held offline or in CI only; rotation is a `wyrmd.json5` edit on every site (or a `sys/update` config action once the keys may come from above, open question 1). Recorded in `docs/security/threats.md`. A `config` user alone cannot update: the signature is mandatory, and `config` does not add keys.
- Downgrades are refused by default, so a signed old release cannot be replayed onto a patched site by a `config` user.
- A rollback restores a copy of the control-plane state: writes made during the failed run (an added link, a token) are lost and the audit says so. History files are never touched (append-only day files; rollback within the pinned redb version).
- Process links restart on every apply (they do on every rebuild already); their packages keep running unless `link_protocol` changed, which `stage` says in advance.
- `wyrmd` gains `check-config`, `wyr` gains `release sign`; the admin gains `update.rs` (stage, preflight, swap, exec, health), the registry nothing (the pending state is a file: it must be readable before the stores open).

## Alternatives
- **The OS package manager (apt, rpm, a container image) and nothing in the tree.** Right where it exists; the owner's boards and the chain of brokers have no such channel to every site, and it cannot be driven from `central`. Kept as the path for a binary the broker does not own (§3).
- **A separate supervisor binary (`wyrm-launcher`) that swaps and watches `wyrmd`.** One more process to keep up to date and secure; `execv` keeps one.
- **A/B binaries under `data_dir/bin/<version>` with a `current` link.** Clean layout, but the service unit then points into `data_dir`, and every tool that finds `wyrmd` on `PATH` sees the old one. In place, with `.prev`, keeps one path.
- **Restart by exit code and `Restart=always`.** Depends on how each site runs the service; `exec` does not.
- **No state copy, rollback only before the first write.** Simpler, but a `SCHEMA` written by the new binary is not readable by the old one, and the health window needs the stores open. The copy is small and the loss is bounded and audited.

## Open questions for the owner
1. Release keys: in `wyrmd.json5` only (every site edited by hand to rotate), or also learned from the upstream through `sys/signing_keys` under `allow_config` (central rotates the fleet, a compromised central then also picks the release key)? Proposal: file only in the first version.
2. Policy: manual only, or `update.policy: "auto"` with a window (`apply` at night, after `stage` from the index)? Proposal: manual; a scheduled `wyrm-agent` plan covers "at night" without new broker code.
3. Downgrade: refused unless `allow_downgrade` (proposal), or always allowed for a signed release?
4. Rollback restores the state copy (proposal) or refuses to roll back once the new binary wrote the stores?
5. Linux and macOS only for the first version (proposal); Windows later.
