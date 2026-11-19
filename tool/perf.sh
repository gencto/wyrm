#!/usr/bin/env bash
# The WYRM performance baseline (docs/backlog.md §14): runs every measurement of slice P0,
# collects their `PERF` lines and prints one table.
#
#   tool/perf.sh            # all: sdk, flow, broker
#   tool/perf.sh sdk flow   # some groups only
#   tool/perf.sh --existing # also the older benches (their own output, not in the table)
#
# Groups:
#   sdk     cargo bench -p wyrm-link-sdk --bench verify / --bench tree   (audit items 3, 4, 5, 17)
#   flow    cargo test --release -p wyrm-flow --test throughput          (items 7-10)
#   broker  cargo test --release -p wyrmd --test perf, one test at a time (items 1, 2, 12, 13, gateway)
#
# Every run writes its whole output to target/perf/<group>.log and the table to
# target/perf/table.txt. The machine and its load (`uptime`) head the table: record both
# with the figures. Release builds take long the first time.
set -euo pipefail

cd "$(dirname "$0")/.."
out=target/perf
mkdir -p "$out"

groups=()
existing=0
for a in "$@"; do
  case "$a" in
    sdk | flow | broker) groups+=("$a") ;;
    --existing) existing=1 ;;
    -h | --help)
      sed -n '2,20p' "$0"
      exit 0
      ;;
    *)
      echo "unknown argument: $a (sdk, flow, broker, --existing)" >&2
      exit 2
      ;;
  esac
done
[ ${#groups[@]} -eq 0 ] && groups=(sdk flow broker)

machine() {
  if [ "$(uname)" = Darwin ]; then
    sysctl -n machdep.cpu.brand_string 2>/dev/null || uname -m
  else
    grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2- | sed 's/^ //' || uname -m
  fi
}

run() { # group, command...
  local g=$1
  shift
  echo "== $g: $*" >&2
  "$@" 2>&1 | tee -a "$out/$g.log" | grep '^PERF ' >>"$out/perf.lines" || true
}

: >"$out/perf.lines"
{
  echo "machine: $(machine), $(uname -sm)"
  echo "commit:  $(git rev-parse --short HEAD 2>/dev/null || echo '?')"
  echo "date:    $(date -u +%Y-%m-%dT%H:%MZ)"
  echo "load before: $(uptime)"
} >"$out/head.txt"

for g in "${groups[@]}"; do
  : >"$out/$g.log"
  case "$g" in
    sdk)
      run sdk cargo bench -p wyrm-link-sdk --bench verify
      run sdk cargo bench -p wyrm-link-sdk --bench tree
      ;;
    flow)
      run flow cargo test --release -p wyrm-flow --test throughput -- --ignored --nocapture
      ;;
    broker)
      for t in perf_a_base perf_b_wildcard perf_c_trace perf_d_historian perf_e_audit perf_f_gateway; do
        run broker cargo test --release -p wyrmd --test perf -- --ignored --nocapture --exact "$t"
      done
      ;;
  esac
done

if [ "$existing" = 1 ]; then
  : >"$out/existing.log"
  for c in "cargo bench -p wyrm-link-portable --bench roundtrip" \
    "cargo bench -p wyrm-dql --bench engine" \
    "cargo bench -p wyrm-schedule --bench eval" \
    "cargo bench -p wyrm-link-scheduler --bench cold_start" \
    "cargo test --release -p wyrm-flow --test preview_cost -- --ignored --nocapture"; do
    echo "== existing: $c" >&2
    $c 2>&1 | tee -a "$out/existing.log" >/dev/null || true
  done
fi

echo "load after:  $(uptime)" >>"$out/head.txt"

# PERF name=… k=v …  →  one row per line: the fixed columns, then the extra fields
awk '
  {
    delete f; extra = ""
    for (i = 2; i <= NF; i++) {
      k = substr($i, 1, index($i, "=") - 1); v = substr($i, index($i, "=") + 1)
      if (k ~ /^(name|n|p50_us|p95_us|p99_us|per_s|cpu_pct|rss_mib|allocs_op|bytes_op)$/) f[k] = v
      else if (k != "note") extra = extra (extra == "" ? "" : " ") k "=" v
    }
    printf "%-44s %7s %9s %9s %9s %10s %7s %7s %9s %11s  %s\n",
      f["name"], f["n"], f["p50_us"], f["p95_us"], f["p99_us"], f["per_s"],
      f["cpu_pct"], f["rss_mib"], f["allocs_op"], f["bytes_op"], extra
  }
' "$out/perf.lines" >"$out/rows.txt"

{
  cat "$out/head.txt"
  echo
  printf "%-44s %7s %9s %9s %9s %10s %7s %7s %9s %11s  %s\n" \
    figure n p50_us p95_us p99_us per_s cpu_pct rss_mib allocs_op bytes_op extra
  cat "$out/rows.txt"
} | tee "$out/table.txt"
