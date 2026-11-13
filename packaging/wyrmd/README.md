# wyrmd releases (ADR 0048 §2.3)

`release-workflow.yml` builds, packs and signs a `wyrmd` release. It is not
enabled: copy it to `.github/workflows/wyrmd-release.yml` when the project
has a release key. Until then a broker updates from a signed archive that
is brought to it (`docs/operations.md` §2, "A broker that updates itself").

## What a release is

| File | What |
|---|---|
| `wyrmd-<version>-<target>.tar.gz` | the binary `wyrmd`, nothing else; `<target>` is `<arch>-<os>[-musl]` as the binary says (`wyrmd release-info`) |
| `wyrmd-<version>.release.json` | the release document: version, date, notes URL, `min_from`, the SCHEMA of each control-plane store, the replication protocol, and per target the archive's name, size, SHA-256 and URL, and the SHA-256 of the binary in it (`bin_sha256`: what a host checks before every start) |
| `wyrmd-<version>.release.json.sig` | Ed25519 signature (hex) over `wyrmd-release-v1\n` + the document's bytes |
| `releases.json` | the channel file (`updates.channel` is its URL): `{wyrmd_channel, index, signature}`. `index` is the text of the index: `wyrmd_releases`, `sequence` (one higher with every index published), `created`, and the entries `{release, signature}`, each a release document as text with its own signature. `signature` signs that text (over `wyrmd-releases-v1\n` + the bytes). One file: a reader never has the index without its signature |

A broker checks the signature against the keys pinned in its binary
(`wyrm_admin::release::RELEASE_KEYS`) and in `updates.keys`, then the
archive's SHA-256 against the signed document, before it unpacks anything.
No key comes from a release file. An index entry is trusted only by its
own signature, which covers the version, the SCHEMA numbers and each
archive's size and SHA-256: a signed list does not make an unsigned entry
good, and one bad entry refuses the whole index.

`wyrmd release index --from <channel file>` writes the next index only
when the release, the published channel file and every entry of it verify
(`--key` adds keys to the built-in ones) and when the published index
holds every version given with `--have` (the release tags that exist): an
older index that was put back is refused. The sequence goes up by one.
`--new` starts an index and refuses to replace one. `release doc` checks
each archive against its description and the binary in it against the
hash that will be signed. `release bundle` makes the channel file from an
index and its signature, after checking both. The workflow therefore
never signs an index it did not check, and a broker refuses an index with
a lower sequence than it has read.

The workflow signs in a job of its own (`sign`): it builds the tool from
the tagged source without a build cache, has no write access to the
repository and is the only job with the key (environment
`wyrmd-release`: require a reviewer). The job that publishes has no key.

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
# a channel file for a mirror: --new the first time, then --from releases.json
target/release/wyrmd release index --new dist/wyrmd-0.2.0.release.json index.json --key <public key>
WYRMD_RELEASE_KEY=<seed> target/release/wyrmd release sign --index index.json
target/release/wyrmd release bundle index.json releases.json --key <public key>
```

Bring the archive, the release document and its signature to the broker:
upload the archive in parts (`sys/backups/~act/restore_begin`,
`restore_part`), then `sys/~act/update {upload, release, signature,
confirm_site}`.
