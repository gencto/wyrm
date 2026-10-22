# ADR 0011 — Installing links at runtime (packages, process and WASM)

**Status:** accepted (owner decisions 2026-10-22) · 2026-10-22

## Context
The DSA broker installs links while it runs: `Install Link ▸ from Git | from Url | from Zip | from Repository`, and the link appears under `/sys/links/<name>`. The owner wants the same, with three ways to run a link: as WASM, as a separate process, or in the broker's own space. No other languages for now.

Today a link runs a driver compiled into `wyrmd`: embedded (in-process), process (`wyrmd link <driver>`) or external (a device with a CA certificate).

Rust has no stable ABI, and principle 2 forbids dynamic plugins. Code that arrives at runtime therefore cannot be loaded into the broker as native code. Inside the broker's process, only WASM can run it, in the sandbox of ADR 0010.

## Decision
- **Modes for a runtime-installed link.**
  - `embedded`: built-in drivers only (unchanged, "from Driver").
  - `process`: a built-in driver (`wyrmd link <driver>`, unchanged) or the binary of a **package**. The binary links `wyrm-link-sdk` and calls `process::run::<D>()`. It gets the same supervision as today: mTLS certificate with CN = link id, link token, private data dir, rlimits, cleared environment.
  - `wasm`: a component of the WIT world `wyrm:link/point` (ADR 0010), hosted in-process by the framework driver `wasm` under fuel, memory and time limits. The component has no I/O until host imports exist (a later ADR: `net:tcp` gated by capabilities), so its points are computed.
- **Package** = a zip with `wyrm-link.json` at its root:
  `{ name, version, description?, wyrm_link: <protocol>, kind: "process" | "wasm", entries?: { "<target triple>": "<path>" }, args?: [..], entry?: "<path>.wasm" }`.
  - `wyrm_link` is the link protocol version of `wyrm-link-sdk` (`hello` reply shape, trust lists). A package built for another version is refused (`success: false`), so it cannot misread the trust lists.
  - A `process` package lists one executable per target triple; `args` are its arguments (for example `["link", "mock"]`). Process mode needs the broker's `tls/` listener (`link_endpoint`); without it the install answers `success: false`.
  - Unpacked into a temp dir and renamed to `data_dir/packages/<name>/<version>/`, so a failed install leaves nothing: at most 64 MiB compressed, 256 MiB unpacked and 1000 files; relative paths only, no `..`, no symlinks, regular files only; the entry for this target gets the executable bit.
  - **Upgrade:** a package with an installed name and a new version replaces the old one; the links that use it restart on the new version, then the old directory is removed. The same version again is refused.
  - The registry keeps one active version per name (`Op::PutPackage`, `Op::RemovePackage`) with its kind, entry, SHA-256 of the zip and its source. A link of a package has driver `pkg:<name>`.
  - `sys/packages/<name>` shows version, kind, source and SHA-256; `remove` refuses while a link uses the package.
- **Sources** (actions of `sys/links`, in the group "Install Link", each with `name` = the new link id; each declares a `timeout_ms` long enough for a fetch and unpack):
  - **from Driver** `{id, driver, mode, params}`: the current `install` (same action id, so `wyr install` and `wyrm-mcp` keep working; only its display and group change).
  - **from Zip** `{name, zip}`: the zip as a binary parameter with the `file` editor (spec 02 0.1.7).
  - **from Url** `{name, url}`: HTTPS only, at most 3 redirects, size and time limits, roots from the OS store.
  - **from Git** `{name, url, ref}`: `git -c protocol.allow=never -c protocol.https.allow=always clone --depth 1 --no-recurse-submodules --branch <ref> -- <url> <dir>` with `GIT_TERMINAL_PROMPT=0` and no hooks; a `url` or `ref` that starts with `-` is refused. The checkout root must hold `wyrm-link.json` with built artifacts: the broker does not compile.
  - **from Repository** `{name, package}`: an index at `packages.repository` in `wyrmd.json5` (as DSA's `linkRepositoryUrl`), JSON `[{name, version, description, url, sha256}]`. It is fetched in the background, never on the start path; `package` becomes an enum once it arrives (declared again like the quarantine lists). Without the index the action answers `success: false, "repository unreachable"`. The download must match `sha256`.
  - **from WASM** `{name, wasm}`: one `wyrm:link/driver` component (ADR 0012), wrapped as a `wasm` package; a `wasm` package zip from any other source works the same.
- **Large arguments.** A WebSocket frame of the gateway is at most 64 KiB, so a zip or a component cannot travel over it. The gateway gets `POST /api/invoke?key=…&action=…` (bearer session; body = the CBOR `args` map, at most 64 MiB). Before the body is read it checks the key (downstream sites stay read-only), that the action has an `editor: "file"` parameter (spec 02 0.1.7, from the node's expanded `~meta`) and that the user's grant reaches the action's level; then it counts the CBOR items (at most 10 000, so the size goes to file contents and not to a tree that decodes to many times its size) before decoding, and runs two such calls at a time. The Dart `FrameClient` sends arguments over 60 KiB this way on its own; the explorer picks the file (the macOS app needs the user-selected read-only file entitlement).
- **Rebuilds wait for installs.** A process link install rebuilds the router (ADR 0006). Package installs count as busy (`Control::busy`). Before it stops the broker, `wyrmd` closes the door and waits for them (`Control::quiesce`, at most 180 s), so an install in flight is not cut off halfway on the old broker; an install that arrives meanwhile answers `busy` ("try again") instead of starting, and the new broker opens again (`Control::reopen`).
- **Fetching** (`wyrm_admin::fetch`): webpki roots, ring provider, at most 3 redirects, 64 MiB per package and 4 MiB per index, 90 s; plain `http://` only to loopback. `git` runs with a cleared environment, no system or global config, and `file://` only in the `dev` profile (tests).
- **Result** of every source: `{success: bool, message: string}`, as in DSA, so the explorer shows two output rows; a failed fetch or a bad package is `success: false` with the reason, not an error status.
- **Trust** (owner decision 2026-10-22): no package signing; level `config` is enough, as in DSA. A `process` package is code that runs on the broker host with the link's rights. Every install and removal is audited with the SHA-256 and the source.
- **Requester grants** (2026-10-22, ADR 0013): a package may ask for grants in `wyrm-link.json` `requester: [{path, level}]` (at most `write`, never `sys`). Each new link of the package gets them at install; the install message lists them.

## Consequences
- A `config` user (also through the gateway, ADR 0009) can run arbitrary code on the host as the broker's user, limited by rlimits and the process link's ACL. Recorded in `docs/security/threats.md`; signing, a separate uid and seccomp stay possible later.
- A WASM link cannot reach devices until host imports exist; until then it serves computed points (simulations, conversions, tests).
- "from Git" needs `git` on the host; it fetches built packages, not sources.
- Packages and their files survive broker restarts (`data_dir`); the registry WAL holds their metadata.

## Alternatives
- **Native plugins in the broker (`.so`/`dylib`).** Rejected: principle 2, no stable Rust ABI, a crash takes the broker down.
- **Links in other languages over a stdio protocol.** Deferred by the owner: no other languages for now.
- **Signed packages only.** Rejected by the owner for now: DSA has no signing, and the `config` level already gates installs.
