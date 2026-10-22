#!/usr/bin/env bash
# Three-site demo, a chain over QUIC + mTLS: `plant` → `edge` (connectors)
# → `central`. Each site has a user gateway for the Flutter app; central
# reads edge and, through edge, plant.
#
#   examples/demo/run.sh            build, start everything, Ctrl+C stops it
#   examples/demo/run.sh --clean    also delete ./data first (fresh sites)
#
# App (dart/wyrm_flutter/example): gateway http://127.0.0.1:8445 (central),
# :8444 (edge) or :8446 (plant), user admin, password
# $WYRM_GATEWAY_ADMIN_PASSWORD.
set -euo pipefail
cd "$(dirname "$0")"
ROOT=../..
BIN=$ROOT/target/release
export WYRM_GATEWAY_ADMIN_PASSWORD=${WYRM_GATEWAY_ADMIN_PASSWORD:-wyrm-demo-1}

if [[ "${1:-}" == "--clean" ]]; then rm -rf data; fi
mkdir -p data

(cd $ROOT && cargo build --release -p wyrmd \
  && cargo build --release -p wyrm-link-modbus --features bin --bin wyrm-modbus-sim)

# Each site's CA must exist before the other site trusts it.
$BIN/wyrmd -c central.json5 ca >/dev/null
$BIN/wyrmd -c edge.json5 ca >/dev/null
$BIN/wyrmd -c plant.json5 ca >/dev/null

pids=()
stop() { kill "${pids[@]}" 2>/dev/null || true; wait 2>/dev/null || true; }
trap stop EXIT INT TERM

$BIN/wyrm-modbus-sim --listen 127.0.0.1:5020 >data/modbus-sim.log 2>&1 & pids+=($!)
# Example link packages for "Install Link ▸ from Repository" (edge.json5
# packages.repository); build them first with examples/packages/build.sh.
if [[ -f ../packages/out/index.json ]]; then
  python3 -m http.server 8090 --bind 127.0.0.1 --directory ../packages/out \
    >data/packages-http.log 2>&1 & pids+=($!)
fi
RUST_LOG=info,zenoh=warn $BIN/wyrmd -c central.json5 >data/central.log 2>&1 & pids+=($!)
sleep 1
RUST_LOG=info,zenoh=warn $BIN/wyrmd -c edge.json5 >data/edge.log 2>&1 & pids+=($!)
sleep 1
RUST_LOG=info,zenoh=warn $BIN/wyrmd -c plant.json5 >data/plant.log 2>&1 & pids+=($!)

cat <<MSG
Demo running (logs in examples/demo/data/*.log). Ctrl+C stops it.
  central: zenoh tcp/127.0.0.1:7447, gateway http://127.0.0.1:8445
  edge:    zenoh tcp/127.0.0.1:7457, gateway http://127.0.0.1:8444
  plant:   zenoh tcp/127.0.0.1:7467, gateway http://127.0.0.1:8446
  login:   admin / $WYRM_GATEWAY_ADMIN_PASSWORD
  chain:   plant → edge → central; from central: wy/central/down/edge ▸ down ▸
           plant (read only, sys too), from edge: wy/edge/down/plant
  install: sys/links ▸ Install Link (packages in examples/packages/out, see docs/links.md)
MSG
wait
