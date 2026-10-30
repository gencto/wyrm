#!/usr/bin/env bash
# Build the example link packages into a repository in examples/packages/out/
# (ADR 0011, 0021) with `wyr link pack` and `wyr repo add`:
#
#   out/index.json                     repository index, urls relative to it
#   out/<name>/<version>/<zip>         one zip per package and host:
#     example-link   responder: the mockdev driver as its own binary
#                    (examples/links/responder)
#     recorder       requester: records another link's values to CSV
#                    (examples/links/requester; asks for a read grant)
#     average        both: serves statistics of another link and writes its
#                    points (examples/links/both; asks for a write grant)
#     probe          test tool: runs scenarios through the site's gateway as
#                    one of its users (links/probe)
#     modbus, mqtt   the protocol links (links/modbus, links/mqtt)
#     mockdev        simulated devices on the driver framework (links/mock)
#     register       WASM package: the register component
#     portable-echo  portable link (ADR 0023, examples/links/portable) as a
#                    WASM package: the crate built for wasm32
#     portable-echo-process
#                    the same app as a process package
#     scheduler      the scheduler link (ADR 0022, links/scheduler) as a WASM
#                    package; no grants: an operator grants write on each
#                    target link (sys/links/<id>/~act/grant)
#     scheduler-process
#                    the same app as a process package
#   out/register.wasm, out/tcp-ping.wasm   components for "Install Link ▸ from WASM"
#
# Each crate describes its package in [package.metadata.wyrm-link].
# examples/demo/run.sh serves out/ on http://127.0.0.1:${REPO_PORT:-8090}.
set -euo pipefail
cd "$(dirname "$0")"
ROOT=../..
OUT=out
ZIPS=$OUT/.zips
rm -rf "$OUT"
mkdir -p "$ZIPS"

(cd $ROOT && cargo build -q --release -p wyr)
WYR=$ROOT/target/release/wyr

for crate in examples/links/responder examples/links/requester examples/links/both \
             links/probe links/modbus links/mqtt links/mock links/snmp; do
  $WYR link pack --manifest-path "$ROOT/$crate/Cargo.toml" --out "$ZIPS"
done

# one portable link, two packages: the component (kind = "wasm" in its
# metadata) and the binary (--kind process, under another name)
PORTABLE=$ROOT/examples/links/portable/Cargo.toml
$WYR link pack --manifest-path "$PORTABLE" --out "$ZIPS"
$WYR link pack --manifest-path "$PORTABLE" --kind process --name portable-echo-process --out "$ZIPS"
# the scheduler, packed the same way
SCHEDULER=$ROOT/links/scheduler/Cargo.toml
$WYR link pack --manifest-path "$SCHEDULER" --out "$ZIPS"
$WYR link pack --manifest-path "$SCHEDULER" --kind process --name scheduler-process --out "$ZIPS"

(cd $ROOT && cargo run -q -p wyrm-link-wasm --example components -- examples/packages/$OUT)
$WYR link pack --component "$OUT/register.wasm" --name register --version 1.0.0 \
  --description "Example WASM link: one writable register per point, no network" --out "$ZIPS"

$WYR repo add "$ZIPS"/*.zip --repo "$OUT"
rm -rf "$ZIPS"
find "$OUT" -type f | sort
