#!/usr/bin/env bash
# Build the demo's link repository in examples/packages/out/ (ADR 0011, 0021,
# 0043): every link of links/official.json in every form it lists, built
# from this workspace, plus the example packages that are not official links.
#
#   out/index.json        repository index, urls relative to it
#   out/<zip>             the official links, from `wyr repo build` (wasm,
#                         and process for this host) and `wyr repo index`:
#                         title, summary, category and link id from the
#                         manifest, so Studio's list reads as the release's
#   out/<name>/<version>/<zip>  the examples, from `wyr link pack` and
#                         `wyr repo add`:
#     example-link   responder: the mockdev driver as its own binary
#                    (examples/links/responder)
#     recorder       requester: records another link's values to CSV
#                    (examples/links/requester; asks for a read grant)
#     average        both: serves statistics of another link and writes its
#                    points (examples/links/both; asks for a write grant)
#     probe          test tool: runs scenarios through the site's gateway as
#                    one of its users (links/probe)
#     portable-echo  portable link (ADR 0023, examples/links/portable) as a
#                    WASM package: the crate built for wasm32
#     portable-echo-process
#                    the same app as a process package
#     register       WASM package: the register component
#   out/register.wasm, out/tcp-ping.wasm   components for "Install Link ▸ from WASM"
#
# The repository is not the official index, so Studio shows these packages
# without the official mark; `packages: { repository: "official" }` reads
# the released ones instead (fetched from github.com).
#
#   examples/packages/build.sh             everything (several minutes)
#   examples/packages/build.sh telegram s7 only these official links (and the examples)
#
# examples/demo/run.sh serves out/ on http://127.0.0.1:18070.
set -euo pipefail
cd "$(dirname "$0")"
ROOT=../..
OUT=out
ZIPS=$OUT/.zips
rm -rf "$OUT"
mkdir -p "$ZIPS"

(cd $ROOT && cargo build -q --release -p wyr)
WYR=$(cd $ROOT && pwd)/target/release/wyr

# Every official link in every form, from the manifest (the one list).
OFFICIAL=$OUT/.official
ONLY=()
for id in "$@"; do ONLY+=(--only "$id"); done
(cd $ROOT && $WYR repo build --form wasm --out "examples/packages/$OFFICIAL" ${ONLY[@]+"${ONLY[@]}"})
(cd $ROOT && $WYR repo build --form process --out "examples/packages/$OFFICIAL" ${ONLY[@]+"${ONLY[@]}"})
# --partial: one host here, not every host the manifest lists
(cd $ROOT && $WYR repo index --zips "examples/packages/$OFFICIAL" \
  --out "examples/packages/$OUT/index.json" --partial)
mv "$OFFICIAL"/*.zip "$OUT"/
rm -rf "$OFFICIAL"

# The examples that are not official links.
for crate in examples/links/responder examples/links/requester examples/links/both links/probe; do
  $WYR link pack --manifest-path "$ROOT/$crate/Cargo.toml" --out "$ZIPS"
done
# one portable link, two packages: the component (kind = "wasm" in its
# metadata) and the binary (--kind process, under another name)
PORTABLE=$ROOT/examples/links/portable/Cargo.toml
$WYR link pack --manifest-path "$PORTABLE" --out "$ZIPS"
$WYR link pack --manifest-path "$PORTABLE" --kind process --name portable-echo-process --out "$ZIPS"

(cd $ROOT && cargo run -q -p wyrm-link-wasm --example components -- examples/packages/$OUT)
$WYR link pack --component "$OUT/register.wasm" --name register --version 1.0.0 \
  --description "Example WASM link: one writable register per point, no network" --out "$ZIPS"

$WYR repo add "$ZIPS"/*.zip --repo "$OUT"
rm -rf "$ZIPS"
find "$OUT" -type f | sort
