# ADR 0021 — Link packaging from Cargo, one package format, per-host assets in the repository

**Status:** accepted · 2026-10-28 (owner decisions: packaging and the repository standard first; the CLI and the SDK share the format; per-host `assets`).

## Context
A link package (ADR 0011) is a zip with `wyrm-link.json`. The format was parsed only in `wyrm-admin` (`packages.rs`); packages were written by hand or by the Python in `examples/packages/build.sh`, which also wrote the repository index. A link kept in its own repository had no tool to build its package, and an index entry had one `url`, so one repository could not serve a macOS and a Linux build of the same link (names are unique in the index).

DSA described a link with `dslink.json` next to its code and listed links in a repository index for "Install Link".

## Decision
- **One format, in the SDK.** `wyrm-link-sdk` feature `package`: the manifest (`Manifest`, `wyrm-link.json`), the repository index (`RepoEntry`, `parse_index`), the host key (`platform()`), a reproducible zip writer (`pack`: sorted files, fixed time) and `sha256_hex`. The broker checks installs with it; `wyr` builds packages with it. Link crates do not pay for it: the feature is off by default.
- **The manifest comes from Cargo.** `[package.metadata.wyrm-link]` in the link's `Cargo.toml` holds what Cargo does not: `kind` (`process`, default), `name` (default: the crate name), `bin` (default: the crate's only binary), `args`, `requester`. Version and description are Cargo's. `wyrm-link.json` is generated, never written by hand.
- **`wyr link pack`** builds the release binary (for each `--target`, default the host) and writes one zip per host, `<name>-<version>-<host>.zip`, whose manifest names that host's entry. `--component <file.wasm> --name --version` packs a WASM component (no Cargo).
- **`wyr repo add <zip>… --repo <dir> [--url <base>]`** copies each zip to `<repo>/<name>/<version>/` and updates `<repo>/index.json`: a new version replaces the entry; the same version adds the zip's host to it.
- **Index entry:** `{name, version, description, assets: {<host>: {url, sha256}}}` for process packages; `{…, url, sha256}` for a package that runs on any host (WASM). A broker installs the asset of its own host and lists only packages it can install. A `url` without a scheme is relative to the index URL, so a repository directory can move or be mirrored as it is.

## Consequences
- An index written for ADR 0011 (`url` + `sha256`) still loads.
- One zip per host keeps downloads small; a zip with several hosts' entries stays valid for Url and Zip installs.
- `examples/packages/build.sh` runs `wyr link pack` and `wyr repo add`.

## Alternatives
- **One zip with every host's binary:** no index change, but each broker downloads every binary.
- **A separate packaging CLI next to the SDK:** a second place for the format, and one more tool to install.
