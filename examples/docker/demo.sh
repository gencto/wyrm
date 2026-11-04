#!/usr/bin/env bash
# The three-site demo (examples/demo) inside the container, with Mosquitto and
# PostgreSQL on loopback for the uplink (ADR 0035) and the alarm sinks
# (ADR 0034). Everything runs in /work; the repository stays read-only.
#
#   examples/docker/demo.sh          build, start, return (processes keep running)
#   examples/docker/demo.sh stop     stop everything
#   examples/docker/demo.sh clean    stop and delete /work
#
# Then, in the same container: wyrm-agent --gateway http://127.0.0.1:8445 …,
# wyr probe --gateway http://127.0.0.1:8445 --site central, mosquitto_sub …
set -euo pipefail
SRC=/src
W=/work
BIN=${CARGO_TARGET_DIR:-/target}/release

stop() {
  [[ -f $W/pids ]] && xargs -r kill <"$W/pids" 2>/dev/null || true
  rm -f "$W/pids"
  pg_ctlcluster 15 main stop 2>/dev/null || true
}
case "${1:-}" in
  stop) stop; exit 0 ;;
  clean) stop; rm -rf "$W"; exit 0 ;;
esac

cd $SRC
cargo build --locked --release -p wyrmd -p wyr \
  -p wyrm-link-modbus -p wyrm-link-http -p wyrm-link-snmp -p wyrm-link-prometheus \
  -p wyrm-link-s7 -p wyrm-link-bacnet -p wyrm-link-opcua \
  --features wyrm-link-modbus/bin,wyrm-link-http/bin,wyrm-link-snmp/bin,wyrm-link-prometheus/bin \
  --features wyrm-link-s7/bin,wyrm-link-bacnet/bin,wyrm-link-opcua/bin \
  --bin wyrmd --bin wyr --bin wyrm-modbus-sim --bin wyrm-http-sim --bin wyrm-snmp-sim \
  --bin wyrm-prometheus-sim --bin wyrm-s7-sim --bin wyrm-bacnet-sim --bin wyrm-opcua-sim
cargo build --locked --release -p wyrm-link-agent --features cli --bin wyrm-agent

mkdir -p $W/data $W/zips $W/repo
cd $W
# A package repository with the PostgreSQL history sync link (a process
# package) for the alarm sink; edge.json5 reads it from :8090.
if [[ ! -f repo/index.json ]]; then
  $BIN/wyr link pack --manifest-path $SRC/links/postgres/Cargo.toml --kind process \
    --name postgres-process --out zips
  $BIN/wyr repo add zips/*.zip --repo repo
fi

# The demo's configs, each with the uplink's network: Mosquitto on loopback.
for s in central edge plant; do
  python3 - "$SRC/examples/demo/$s.json5" "$s.json5" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
t = open(src).read().rstrip()
assert t.endswith('}')
t = t[:-1].rstrip() + '\n  uplink: { net: "127.0.0.1:1883" },\n}\n'
open(dst, 'w').write(t)
PY
done

# PostgreSQL 15: database and user `wyrm`, SCRAM password.
pg_ctlcluster 15 main start
su postgres -c "psql -qtAc \"select 1 from pg_roles where rolname='wyrm'\"" | grep -q 1 || {
  su postgres -c "psql -qc \"create user wyrm password 'wyrm-pg-1'\""
  su postgres -c "psql -qc 'create database wyrm owner wyrm'"
}

# Mosquitto: loopback, one user (the uplink's Set Password).
cat >mosquitto.conf <<'CONF'
listener 1883 127.0.0.1
allow_anonymous false
password_file /work/mosquitto.passwd
CONF
mosquitto_passwd -b -c mosquitto.passwd uplink mq-pass-1 2>/dev/null
chmod 0644 mosquitto.passwd

$BIN/wyrmd -c central.json5 ca >/dev/null
$BIN/wyrmd -c edge.json5 ca >/dev/null
$BIN/wyrmd -c plant.json5 ca >/dev/null

: >pids
bg() { local log=$1; shift; setsid "$@" >"data/$log.log" 2>&1 & echo $! >>pids; }
bg mosquitto mosquitto -c mosquitto.conf
bg modbus-sim $BIN/wyrm-modbus-sim --listen 127.0.0.1:5020
bg http-sim $BIN/wyrm-http-sim --listen 127.0.0.1:18090
bg snmp-sim $BIN/wyrm-snmp-sim --listen 127.0.0.1:1161
bg prometheus-sim $BIN/wyrm-prometheus-sim --listen 127.0.0.1:19101
bg s7-sim $BIN/wyrm-s7-sim --listen 127.0.0.1:10102
bg bacnet-sim $BIN/wyrm-bacnet-sim --listen 127.0.0.1:47809 --instance 1234 --extra 20
bg opcua-sim $BIN/wyrm-opcua-sim --port 4840 --pki data/opcua-sim-pki
bg packages-http python3 -m http.server 8090 --bind 127.0.0.1 --directory repo
export RUST_LOG=info,zenoh=warn
bg central $BIN/wyrmd -c central.json5
sleep 1
bg edge $BIN/wyrmd -c edge.json5
sleep 1
bg plant $BIN/wyrmd -c plant.json5

for port in 8445 8444 8446; do
  for _ in $(seq 60); do
    curl -s -o /dev/null "http://127.0.0.1:$port/" && break
    sleep 1
  done
done
cat <<MSG
Demo running in $W (logs in $W/data/*.log); stop with: examples/docker/demo.sh stop
  gateways: central http://127.0.0.1:8445, edge :8444, plant :8446 (admin / $WYRM_GATEWAY_ADMIN_PASSWORD)
  mqtt:     127.0.0.1:1883, user uplink / mq-pass-1
  postgres: 127.0.0.1:5432, database wyrm, user wyrm / wyrm-pg-1
  packages: http://127.0.0.1:8090/index.json (postgres-process)
MSG
