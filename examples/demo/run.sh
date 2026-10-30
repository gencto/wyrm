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

# wyrmd and the device simulators the demo links talk to.
(cd $ROOT && cargo build --release -p wyrmd \
  && cargo build --release -p wyrm-link-modbus --features bin --bin wyrm-modbus-sim \
  && cargo build --release -p wyrm-link-http --features bin --bin wyrm-http-sim \
  && cargo build --release -p wyrm-link-snmp --features bin --bin wyrm-snmp-sim \
  && cargo build --release -p wyrm-link-prometheus --features bin --bin wyrm-prometheus-sim \
  && cargo build --release -p wyrm-link-s7 --features bin --bin wyrm-s7-sim \
  && cargo build --release -p wyrm-link-bacnet --features bin --bin wyrm-bacnet-sim \
  && cargo build --release -p wyrm-link-opcua --features bin --bin wyrm-opcua-sim)

# Each upstream site's CA, and the certificate it issues for the site below
# it (ADR 0015), must exist before that site starts.
$BIN/wyrmd -c central.json5 ca >/dev/null
$BIN/wyrmd -c edge.json5 ca >/dev/null
$BIN/wyrmd -c plant.json5 ca >/dev/null

pids=()
stop() { kill "${pids[@]}" 2>/dev/null || true; wait 2>/dev/null || true; }
trap stop EXIT INT TERM

$BIN/wyrm-modbus-sim --listen 127.0.0.1:5020 >data/modbus-sim.log 2>&1 & pids+=($!)
# edge links http, snmp, prometheus
$BIN/wyrm-http-sim --listen 127.0.0.1:18090 >data/http-sim.log 2>&1 & pids+=($!)
$BIN/wyrm-snmp-sim --listen 127.0.0.1:1161 >data/snmp-sim.log 2>&1 & pids+=($!)
$BIN/wyrm-prometheus-sim --listen 127.0.0.1:19101 >data/prometheus-sim.log 2>&1 & pids+=($!)
# plant links s7, bacnet, opcua
$BIN/wyrm-s7-sim --listen 127.0.0.1:10102 >data/s7-sim.log 2>&1 & pids+=($!)
$BIN/wyrm-bacnet-sim --listen 127.0.0.1:47809 --instance 1234 --extra 20 >data/bacnet-sim.log 2>&1 & pids+=($!)
$BIN/wyrm-opcua-sim --port 4840 --pki data/opcua-sim-pki >data/opcua-sim.log 2>&1 & pids+=($!)
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
  links:   central: mock, scheduler
           edge:  mock, mockdev, modbus (process), modbus_slave (on 127.0.0.1:15502),
                  http, snmp, prometheus, scheduler
           plant: mock, s7, bacnet, opcua, scheduler
  sims:    modbus :5020, http :18090, snmp udp :1161, prometheus :19101, s7 :10102,
           bacnet udp :47809, opcua :4840 (logs in data/*-sim.log)
  chain:   plant → edge → central; from central: wy/central/downstream/edge ▸ downstream ▸
           plant, from edge: wy/edge/downstream/plant
  above:   central's users run every action on edge and plant, sys and link config
           (Export, Edit, Stop) included: allow_config in edge.json5 and plant.json5 (ADR 0018)
  install: sys/links ▸ Install Link (packages in examples/packages/out, see docs/links.md)
  peers:   another broker adds central in its sys/upstream (Url quic/127.0.0.1:7450,
           CA data/central/pki/ca.pem); central ▸ sys/quarantine ▸ Authorize
MSG
wait
