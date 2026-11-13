# wyrmd releases (ADR 0048 §2.3)

`release-workflow.yml` builds, packs and signs a `wyrmd` release. It is not
enabled: copy it to `.github/workflows/wyrmd-release.yml` when the project
has a release key. Until then a broker updates from a signed archive that
is brought to it (`docs/operations.md` §2, "A broker that updates itself").

## What a release is

| File | What |
|---|---|
| `wyrmd-<version>-<target>.tar.gz` | the binary `wyrmd`, nothing else; `<target>` is `<arch>-<os>[-musl]` as the binary says (`wyrmd release-info`) |
| `wyrmd-<version>.release.json` | the release document: version, date, notes URL, `min_from`, the SCHEMA of each control-plane store, the replication protocol, and per target the archive's name, size, SHA-256 and URL |
| `wyrmd-<version>.release.json.sig` | Ed25519 signature (hex) over `wyrmd-release-v1\n` + the document's bytes |
| `releases.json`, `releases.json.sig` | the index: a list of entries `{release, signature}`, each a release document as text with its own signature, and the signature of the whole file (over `wyrmd-releases-v1\n` + the bytes); `updates.channel` is its URL |

A broker checks the signature against the keys pinned in its binary
(`wyrm_admin::release::RELEASE_KEYS`) and in `updates.keys`, then the
archive's SHA-256 against the signed document, before it unpacks anything.
No key comes from a release file. An index entry is trusted only by its
own signature, which covers the version, the SCHEMA numbers and each
archive's size and SHA-256: a signed list does not make an unsigned entry
good, and one bad entry refuses the whole index.

`wyrmd release index` adds a release to an index only when the release,
the index that is there and every entry of it verify (`--key` adds keys to
the built-in ones); `--new` starts an empty index and refuses to replace
one. The workflow therefore never signs an index it did not check.

## The release key

1. Make it once, on a computer that is not a build host:
   ```bash
   wyrmd release keygen
   ```
   It prints the secret seed and the public key.
2. Keep the seed in the repository's environment `wyrmd-release` as the
   secret `WYRMD_RELEASE_KEY` (require a reviewer for that environment), and
   a copy offline. Whoever holds it can make every broker in
   `updates.mode: "self"` run their binary.
3. Pin the public key: add it to `RELEASE_KEYS` in
   `crates/wyrm-admin/src/release.rs` (it is empty today, so a broker trusts
   only its `updates.keys`). Until a release with the built-in key is out,
   sites put the public key into `updates.keys`.
4. To replace a key, ship one release that pins both keys, signed by the
   old one; sign the releases after it with the new one. A signature file
   may hold several signatures, one a line: one good one is enough.

## By hand (no workflow)

```bash
cargo build --release -p wyrmd
target/release/wyrmd release pack dist            # the archive and what it is
target/release/wyrmd release doc dist --date 2026-11-13
WYRMD_RELEASE_KEY=<seed> target/release/wyrmd release sign dist/wyrmd-0.2.0.release.json
target/release/wyrmd release verify dist/wyrmd-0.2.0.release.json --key <public key>
# an index for a mirror: --new the first time, then without it
target/release/wyrmd release index --new dist/wyrmd-0.2.0.release.json releases.json --key <public key>
WYRMD_RELEASE_KEY=<seed> target/release/wyrmd release sign --index releases.json
```

Bring the archive, the release document and its signature to the broker:
upload the archive in parts (`sys/backups/~act/restore_begin`,
`restore_part`), then `sys/~act/update {upload, release, signature,
confirm_site}`.
