#!/bin/sh
# Builds the WebAssembly of the image builder page (crates/wyrm-image-web, ADR 0051 §4)
# into site/dist/assets/wasm: wyrm_image_web.js (an ES module, `--target web`) and
# wyrm_image_web_bg.wasm. site/dist is a build output: nothing of it is committed.
#
#     tool/site/wasm.sh
#
# The `wasm-bindgen` CLI reads only what the crate of its own version wrote, so both are
# WASM_BINDGEN: the workspace pins the crate (`wasm-bindgen = "=<version>"`), this script
# checks Cargo.lock against it and installs the CLI of that version when the one on PATH
# is missing or another (`cargo install wasm-bindgen-cli --locked`).
set -eu

WASM_BINDGEN=0.2.130
OUT=site/dist/assets/wasm

cd "$(dirname "$0")/../.."

locked=$(awk '$0 == "name = \"wasm-bindgen\"" { getline; gsub(/version = |"/, ""); print }' Cargo.lock)
if [ "$locked" != "$WASM_BINDGEN" ]; then
    echo "Cargo.lock has wasm-bindgen $locked, tool/site/wasm.sh pins $WASM_BINDGEN" >&2
    exit 1
fi
if [ "$(wasm-bindgen --version 2>/dev/null || true)" != "wasm-bindgen $WASM_BINDGEN" ]; then
    cargo install wasm-bindgen-cli --version "$WASM_BINDGEN" --locked
fi

# The release profile strips symbols, and with them the `target_features` section that
# tells wasm-bindgen which WebAssembly features the module uses: strip debug info only.
CARGO_PROFILE_RELEASE_STRIP=debuginfo \
    cargo build --locked --release --target wasm32-unknown-unknown -p wyrm-image-web
wasm-bindgen --target web --no-typescript --out-dir "$OUT" \
    target/wasm32-unknown-unknown/release/wyrm_image_web.wasm
ls -l "$OUT"
