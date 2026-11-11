# ADR 0043 — The official links manifest: one checked-in list, one published index

**Status:** accepted · 2026-11-11 (owner request: one file that lists the official links, their versions and their GitHub release files, read by the broker and Studio; CI builds the packages in every form. Decisions delegated, ADR 0029).

## Context
ADR 0011 and 0021 give a broker a repository: `packages.repository` names an index (`[{name, version, description, url | assets, sha256}]`), the broker fetches it in the background and *Install Link ▸ from Repository* installs a package after it checks the SHA-256. The only index today is the demo's (`examples/packages/build.sh`), with a hand-written list of crates. Nothing says which links the project releases, and nothing publishes them. Studio's *Add a link* reads the drivers and the repository packages from `sys/links` ▸ `install` and ▸ `install_repo` and keeps its own table of titles and categories (`studio/business/lib/wyrm/catalog.dart`).

## Decision

### 1. The manifest: `links/official.json`
One JSON file beside the link crates, `format: "wyrm-official-links/1"`. JSON, not JSON5: every reader is `serde_json` (`wyrm-link-sdk::official`), the same as the index; principle 5 keeps JSON5 for `wyrmd.json5`.

```json
{ "format": "wyrm-official-links/1",
  "releases": "https://github.com/gencto/wyrm/releases",
  "hosts": ["linux-aarch64", "linux-x86_64", "macos-aarch64"],
  "links": [
    { "id": "alarm", "crate": "wyrm-link-alarm", "title": "Alarms",
      "summary": "Alarm classes on points, records, acknowledgement and export",
      "category": "Apps", "version": "0.1.0", "wyrm_link": 1, "min_broker": "0.1.0",
      "forms": { "wasm": "alarm", "process": "alarm-process" } } ] }
```

- `id` is the link's name in lists; `crate` the workspace crate it is built from.
- `forms`: `builtin` (a driver compiled into `wyrmd`, its `install` name), `wasm` (a package name: one component for every host), `process` (a package name: one zip per host of `hosts`). At least one.
- `version` is the crate's; `wyrm_link` the link protocol (`LINK_PROTOCOL`); `min_broker` the oldest broker that runs it.
- The file states **intent**: which links are official, in which forms, at which version. It holds no URL of a file and no hash. Unknown fields are refused (a typo fails).

It lists the links with `[package.metadata.wyrm-link]` and a release purpose (protocol links, file stores, history sync, apps, messengers), plus `agent` (built-in only) and `mockdev` (trials). It leaves out `probe` (a test tool), the examples and the drivers `mock`, `wasm`, `app`, `portable-echo` (hosts for other code, or tests).

### 2. The published index is generated from it, in the ADR 0021 format
The release job builds the packages, hashes them and writes the index: `wyr repo index --tag <tag>` (`Official::index`). One entry per package form, with ADR 0021's fields and a superset: `title`, `category`, `link` (the official id), `kind`, `wyrm_link`, `min_broker`; `description` is the manifest's `summary`. The broker reads it with the parser it has (`parse_index`); there is no second reader and no second format. `wyr repo add` still writes indexes without the new fields.

The index is checked when it is made: every zip must be a form of a listed link, of the listed version, kind and protocol, for a listed host; in a release every form and host must be there (no `--partial`). The result passes the broker's own `parse_index` before it is written.

`RepoEntry` and `Asset` now **ignore unknown fields** (they refused them). An index is read by brokers of many versions and a newer one may say more. Brokers built before this ADR refuse the extended index; no official index existed before it, so no deployed broker is affected.

### 3. Hashes come from CI, after the build; the broker never trusts what it cannot check
The checked-in file has no hashes, so it is never stale and a release cannot depend on a commit that writes them back. The release job computes SHA-256 of each zip it just built and writes them into the index, and publishes the zips, the index, the manifest (`official.json`) and `SHA256SUMS` as the assets of release `<tag>`. The broker installs only an index entry whose zip matches its SHA-256 (ADR 0021, unchanged).

Package zips are reproducible from their inputs (`package::pack`: sorted files, fixed time), but the compiled binaries are not bit-for-bit reproducible across toolchains; the hash is of the file that was published.

### 4. Where the index lives: a fixed release, absolute URLs per tag
- Each links release has tag `links-v*` and keeps its files: `<releases>/download/<tag>/<zip>`. The index written for it uses these **absolute** URLs, so an index read just before the next release still names files that exist and match.
- The index brokers read is the one asset of release `links-index`: `https://github.com/gencto/wyrm/releases/download/links-index/links-index.json`. Each links release replaces that asset (`--clobber`). Not `releases/latest/download/…`: "latest" follows any newest release of the repository (a future `wyrmd` release would make the URL a 404), and links releases are created with `--latest=false`.
- Relative URLs (no `--tag`, no `--base`) are for mirrors: the zips beside the index.

### 5. Trust: what the manifest adds and what it does not
It adds: one reviewed list of what the project releases; packages built by CI from a tagged commit, not by a person; an index whose hashes match those files; HTTPS to `github.com` with the `webpki-roots` store (`fetch.rs`, redirects to the release CDN followed, at most three).

It does not add: a signature. Whoever can replace the `links-index` asset (a repository writer, a stolen token, GitHub itself) can point brokers at other zips with matching hashes. Packages stay unsigned (ADR 0011), and installs still show the requested network and grants before anything runs (security review WASM-1).

**`official` in the catalogue (security review of this ADR, 2026-11-11).** A package name alone proves nothing: any repository can publish a package called `modbus`. A package row is `official: true` only when (1) the configured repository is the official index (`packages.repository: "official"`, or the same URL written out), and (2) the broker's embedded manifest lists that package name, in that form (`wasm` or `process`, from the shape of the entry), at that version. A package row's `title`, `summary`, `category` and `link` come from its own index entry, never from the manifest, so a repository cannot borrow an official description. The manifest holds no hashes (§3), so the hash cannot be compared with it; the SHA-256 of the index entry is checked against the downloaded zip at install, as for every repository. A mirror (another URL) is shown as not official, even with the official files. A built-in driver row is official when the manifest names it: it is compiled into the binary that embeds the manifest. **Next step:** sign the index (Ed25519, a key that is not in CI secrets of the same repository, the public key embedded in `wyrmd`), and refuse an official index that does not verify. Not done here.

### 6. Default: off; one word to opt in
`wyrmd` fetches no index unless `packages.repository` is set (as before). `packages: { repository: "official" }` means the official index URL of the manifest this broker was built with (`wyrm_admin::official::repository_url`). A broker on a plant network must not call the internet because it was installed; an air-gapped site cannot reach GitHub at all and would log an error every start. The demo and the Docker example carry the line as a comment. A site that cannot reach GitHub mirrors the release (docs/operations.md, *Official links offline*).

### 7. The broker is Studio's one reader: `attr.catalog` of `sys/links`
The broker embeds the manifest (`include_str!`, `wyrm_admin::official::EMBEDDED`) and publishes on the `~meta` of `wy/<site>/sys/links` an attribute `catalog`: an array of maps, one per built-in driver this broker hosts and one per repository package built for its host (after the index loads; declared again then):

| key | value |
|---|---|
| `id` | `driver:<code>` or `package:<code>` (Studio's `CatalogItem.id`) |
| `code` | the name `install` (`driver`) or `install_repo` (`package`) takes |
| `link` | the official link id, empty when none |
| `title`, `summary`, `category` | a driver: from the embedded manifest; a package: from its index entry only. Missing: the name, empty, empty |
| `version` | a driver: the broker's version; a package: the index entry's |
| `form` | `builtin`, `wasm` or `process` |
| `official` | a driver: the embedded manifest names it; a package: the rule of §5 |

Built-in drivers get titles with no network. The `install`/`install_repo` enum choices stay as they are; the catalogue only describes them. `attr` is free-form (spec 02), so the spec does not change.

### 8. CI
`packaging/links/release-workflow.yml` (to be copied to `.github/workflows/links-release.yml` by someone with the `workflow` scope, as `packaging/claude-desktop/ci-workflow.yml`): on a `links-v*` tag or a manual run, `check` (`wyr repo check`), `wasm` (`wyr repo build --form wasm`), `process` on three hosts — `x86_64-unknown-linux-musl` (ubuntu-latest), `aarch64-unknown-linux-musl` (ubuntu-24.04-arm), `aarch64-apple-darwin` (macos-latest) — static musl on Linux so a binary runs on any board, and `publish` (the only job with `contents: write`) for a tag. No secrets beyond `GITHUB_TOKEN`; actions pinned by commit; `persist-credentials: false`. The workflow has no link list: `wyr repo build` reads the manifest. A manual run without a tag builds and keeps the zips as artifacts only.

`cargo test` holds the manifest against the workspace (`wyr` test `official_manifest_matches_the_workspace`: crate exists, version is the crate's, a `wasm` form is a `kind = "wasm"` crate with a cdylib under that name, a `process` form has a binary and, for a process crate, its package name) and `wyrmd` test `official_builtin_forms_are_drivers_of_wyrmd`. CI's existing `cargo test --workspace` runs both.

## Consequences
- A link version moves in its `Cargo.toml` and in `links/official.json` together, or the tests fail.
- The demo keeps its own repository (`examples/packages/build.sh`): examples and test tools are not official.
- Studio can drop its table of titles (`catalog.dart`) and read `attr.catalog`; until it does, both agree because both come from the same names.
- Windows and `macos-x86_64` hosts are not built (no broker host key for Windows; Intel Macs are not a target). Adding a host = one line in `hosts` and one matrix row.

## Alternatives
- **Commit the resolved index back to `main`** (raw URL of a tag): reproducible URL, but the release job needs push rights to the default branch and the index commit races other work.
- **`releases/latest/download/links-index.json`:** no extra release, but any other release breaks the URL.
- **The manifest is the index (hashes checked in):** one file, but every release needs a commit with hashes the CI computed, and a hash in review is not a check.
- **On by default:** easier for a first trial; refused for plant and air-gapped sites (§6).
