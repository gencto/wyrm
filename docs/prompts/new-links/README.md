# New links in parallel — common brief

Each file next to this one describes one new link (protocol connector) for data collection and metrics. Each is meant for one Claude Code session on the web, working in parallel with the others. This file holds the rules every session follows; the link's own file holds what is specific to it.

## Read first, in this order
1. `CLAUDE.md` — project rules (principles, conventions, "Never log secrets, `ptok`, or `~val` values above `trace`", `wire_enum!`).
2. `.claude/skills/wyrm-link/SKILL.md` — how to build a link on the driver framework. Follow its steps; scaffold with `cargo run -p wyr -- new link <name> --proto generic` (never write the crate skeleton by hand).
3. `docs/adr/0004-driver-framework.md` — what the framework owns (tree, generated `add_*`/`edit`/`remove`/`restart`/`stop`/`start` actions, states, scheduling, polling, read-back writes, quality ladder `good → uncertain/stale → bad/comm_fail`). Do not re-implement any of it.
4. Reference drivers: `links/modbus` (batched plan, hand-written `Params` for cross-field rules, simulator in `src/sim.rs` behind feature `sim`, tests in `tests/sim.rs`) and `links/mqtt` (a link that parses JSON payloads with `serde_json`, TLS with PEM params and a `secret` key).
5. `docs/links.md` — the user guide for links; your link gets its own guide `docs/<name>.md` in the same style.

## Rules
- **Driver framework, not the raw layer**: `Connection → Device → Point` with `#[derive(Params)]` per level; several node kinds on a level as a `Params` enum (see modbus `Conn`).
- **Every I/O has a timeout** from the params; no `unwrap`/`expect` on network paths; a protocol error answer from the device is `DriverError::Point` for that point only; a broken connection is `DriverError::Transport`; no answer is `DriverError::Device`. A late reply after a timeout must never be taken for a later request (match request ids, sequence numbers or invoke ids).
- **Honest quality**: never invent values (no "zero on failure"); let the framework's quality ladder show staleness.
- **Secrets** (passwords, community strings, tokens, private keys) are `#[param(secret)]`; they are never logged, never in `~meta`, never in errors. TLS: CA and client certificate as PEM text params, the key as a secret, `rustls` with the `ring` provider (as `links/mqtt`), never `aws-lc`; no `native-tls`/OpenSSL.
- **Logging**: ids, states and counts only; values at `trace` at most.
- **Dependencies**: pin new crates in the root `[workspace.dependencies]` with an exact minor (`"x.y"`), `default-features = false` where it makes sense. Licenses: MIT, Apache-2.0, BSD, ISC, MPL-2.0, Zlib only — no GPL/LGPL/AGPL, no "commercial use requires a license". Prefer a small in-crate codec over an immature crate; say which you chose and why in the PR.
- **Writes** (when the protocol has them): no optimistic update; read-back; read-only points refuse writes.
- **A simulator** of the device/server in `src/sim.rs` (feature `sim`) with failure modes (error replies, silence, disconnect, slow replies), used by `tests/sim.rs`, and a bin `wyrm-<name>-sim` like `wyrm-modbus-sim` so the demo can run it.
- **Tests** cover: every data type/conversion, batching plan, point error isolation, write + read-back, silent device → `uncertain/stale` then `bad/comm_fail`, connection down → connection `failed` with `error` and children `stopped_by_parent`, reconnect, params bounds, secrets not in `~meta`.

## Framework boundaries
- Do **not** change `crates/wyrm-link-sdk` (the driver framework). A Modbus plan running at the same time adds framework hooks (driver actions, diagnostics, folders, copy/export/import, server kinds); a second change there would conflict. If your link needs a hook that does not exist yet — for example the commissioning actions named in your brief — leave that part out, and list it in the PR under "Follow-up after the framework hooks land".
- Known CI flakes may still show in `cargo test -p wyrmd --test e2e` (connection to a just-started listener). Re-run once; if the same test fails twice, report it in the PR with the log lines instead of changing unrelated tests.

## Registration (shared files — keep these edits minimal and append-only)
These files are touched by every parallel session; keep your edit to the lines below so the merges stay trivial:
- root `Cargo.toml`: one line in `[workspace] members`, one line in `[workspace.dependencies]` (`wyrm-link-<name> = { path = "links/<name>" }`), plus your new third-party crates.
- `crates/wyrmd/Cargo.toml`: one dependency line (and `features = ["sim"]` in dev-dependencies only if an e2e test needs it).
- `crates/wyrmd/src/lib.rs`: one arm each in `Drivers::validate` (params check), the embedded `start` match (`start_boxed::<…>`) and the process-mode `run` match; update the doc comment listing the drivers.
- `CLAUDE.md`: one line in the workspace layout block for your link.
- `docs/links.md`: one row/line pointing at `docs/<name>.md`.
- Packaging (ADR 0021): `[package.metadata.wyrm-link]` in your crate's `Cargo.toml` (copy `links/modbus/Cargo.toml`), feature `process`, bin `wyrm-link-<name>`; one line in `examples/packages/build.sh` if it lists links.
Do not reformat, reorder or "fix" anything else in these files.

## Done means
- `cargo fmt --all -- --check`
- `cargo clippy --workspace --all-targets --all-features -- -D warnings` (CI uses the newest stable clippy)
- `cargo test -p wyrm-link-<name> --all-features`
- `cargo test -p wyrmd --all-features --test e2e` (you changed `wyrmd`) — all green
- `docs/<name>.md`: what the link does, the tree, every param with its default and bound, data types and conversions, writes, errors and quality, how to run the simulator, known limits (what the protocol has that this link does not do).
- A PR from branch `link/<name>` to `main`, titled `link: <name> — <one line>`, rebased on the latest `main` just before you open it, with: what is supported, what is not and why, the crates added with their licenses, how you tested (counts), and how to try it with the simulator. Do not merge it; the owner merges.
