#!/bin/sh
# Builds the WebAssembly of the image builder page (crates/wyrm-image-web, ADR 0051 §4)
# into site/dist/assets/wasm, or into <out dir>: wyrm_image_web.js (an ES module,
# `--target web`) and wyrm_image_web_bg.wasm. site/dist is a build output: nothing of it
# is committed. CI builds it into a directory of its own and hands it to
# `tool/site/build.py --wasm-from <dir>` (build.py deletes site/dist first).
#
#     tool/site/wasm.sh [<out dir>]
#
# The `wasm-bindgen` CLI reads only what the crate of its own version wrote, so both are
# WASM_BINDGEN: the workspace pins the crate (`wasm-bindgen = "=<version>"`), this script
# checks Cargo.lock against it and installs the CLI of that version when the one on PATH
# is missing or another (`cargo install wasm-bindgen-cli --locked`), then checks it again.
set -eu

WASM_BINDGEN=0.2.130
# <out dir> is read from where the script is started; the default from the repository
OUT=${1:-}
case $OUT in
'' | /*) ;;
*) OUT=$(pwd)/$OUT ;;
esac
cd "$(dirname "$0")/../.."
OUT=${OUT:-site/dist/assets/wasm}

locked=$(awk '$0 == "name = \"wasm-bindgen\"" { getline; gsub(/version = |"/, ""); print }' Cargo.lock)
if [ "$locked" != "$WASM_BINDGEN" ]; then
    echo "Cargo.lock has wasm-bindgen $locked, tool/site/wasm.sh pins $WASM_BINDGEN" >&2
    exit 1
fi
if [ "$(wasm-bindgen --version 2>/dev/null || true)" != "wasm-bindgen $WASM_BINDGEN" ]; then
    cargo install wasm-bindgen-cli --version "$WASM_BINDGEN" --locked
    have=$(wasm-bindgen --version 2>/dev/null || true)
    if [ "$have" != "wasm-bindgen $WASM_BINDGEN" ]; then
        echo "wasm-bindgen on PATH is '$have' after the install, not $WASM_BINDGEN" >&2
        exit 1
    fi
fi

# The release profile strips symbols, and with them the `target_features` section that
# tells wasm-bindgen which WebAssembly features the module uses: strip debug info only.
CARGO_PROFILE_RELEASE_STRIP=debuginfo \
    cargo build --locked --release --target wasm32-unknown-unknown -p wyrm-image-web
wasm-bindgen --target web --no-typescript --out-dir "$OUT" \
    target/wasm32-unknown-unknown/release/wyrm_image_web.wasm
ls -l "$OUT"
