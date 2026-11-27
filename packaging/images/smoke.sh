#!/bin/sh
# The smoke test of a board image in QEMU (ADR 0051 §2, §3): the base image of the board
# `qemu-armsr` is built, its table checked, and two images of it are booted.
#
#   smoke.sh --wyrmd <aarch64 musl wyrmd> --wyrmd-version <version> [options]
#
#   --wyr <path>        the `wyr` that builds and assembles (default: target/debug/wyr,
#                       else `wyr` on PATH)
#   --work <dir>        where everything goes (default: a new directory under $TMPDIR);
#                       kept at the end, with the console logs
#   --base <dir>        a directory with `index.json` and the raw base image of
#                       qemu-armsr made before: no build
#   --cache <dir>       the ImageBuilder archives (`wyr image base --cache`)
#   --timeout <s>       how long a boot may take until the gateway answers TLS (default
#                       300 with hvf or kvm, 900 without: the first start waits up to
#                       120 s for NTP before it makes the site's CA)
#
# Environment: RUNTIME (docker or podman), QEMU (qemu-system-aarch64), QEMU_EFI (the
# UEFI firmware), SMOKE_PORT (18445, the gateway on the host), SMOKE_SSH (10022).
#
# 1. `wyr image base` makes the base image; `verify-table.sh` checks its table.
# 2. The base image as it is (no configuration) boots: the console says the broker is
#    not started, and nothing answers on the gateway's port through the forward. The
#    image has no login (SSH off, root locked), so the guest's loopback is not probed:
#    that no broker runs at all is shown by the console line and by the disk, which
#    gets no data partition (the service makes it only for a configuration).
# 3. `wyr image build` assembles the image with a test configuration, a new setup code
#    and an SSH key of this run. It boots on a disk with room for the data partition:
#    within the time limit `/api/info` answers over TLS with `setup: true` and a
#    `setup_proof` that verifies with the code and the presented CA; the CA is pinned;
#    `POST /api/setup` makes the first admin; the login works.
# 4. It is powered off and booted again: the same CA, no setup offered, the login
#    works. The broker runs as uid 787 on the data partition.
# 5. The region on the disk is empty (`wyr image inspect`), and the table the first
#    boot wrote (data partition, GPT moved to the end) passes `verify-table.sh`.

set -eu

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
BOARD=qemu-armsr
QEMU=${QEMU:-qemu-system-aarch64}
PORT=${SMOKE_PORT:-18445}
SSH_PORT=${SMOKE_SSH:-10022}
SITE=smoke

say() { echo "smoke [$(date -u +%H:%M:%S)] $*"; }
die() {
    say "FAIL: $*"
    exit 1
}
client() { python3 -I "$here/smoke_client.py" "$@"; }

wyr='' wyrmd='' version='' work='' base='' cache='' timeout=''
while [ $# -gt 0 ]; do
    [ $# -ge 2 ] || die "$1 needs a value"
    case $1 in
    --wyr) wyr=$2 ;;
    --wyrmd) wyrmd=$2 ;;
    --wyrmd-version) version=$2 ;;
    --work) work=$2 ;;
    --base) base=$2 ;;
    --cache) cache=$2 ;;
    --timeout) timeout=$2 ;;
    *) die "unknown option $1" ;;
    esac
    shift 2
done
if [ -z "$base" ] && { [ -z "$wyrmd" ] || [ -z "$version" ]; }; then
    die "usage: smoke.sh --wyrmd <aarch64 musl wyrmd> --wyrmd-version <version> [--base <dir>] [--wyr <path>] [--work <dir>] [--cache <dir>] [--timeout <s>]"
fi
if [ -z "$wyr" ]; then
    if [ -x "$repo/target/debug/wyr" ]; then
        wyr=$repo/target/debug/wyr
    else
        wyr=$(command -v wyr) || die "no wyr: give --wyr"
    fi
fi
for tool in "$QEMU" python3 ssh ssh-keygen truncate; do
    command -v "$tool" > /dev/null 2>&1 || die "$tool is not installed"
done
if [ -z "$work" ]; then
    work=$(mktemp -d "${TMPDIR:-/tmp}/wyrm-smoke.XXXXXX")
fi
mkdir -p "$work"
work=$(cd "$work" && pwd)

# ---- QEMU: the accelerator and the firmware -------------------------------------------

case $(uname -s)/$(uname -m) in
Darwin/arm64) accel="-accel hvf -cpu host" ;;
Linux/aarch64)
    if [ -w /dev/kvm ]; then
        accel="-accel kvm -cpu host"
    else
        accel="-accel tcg,thread=multi -cpu max,pauth-impdef=on"
    fi
    ;;
*) accel="-accel tcg,thread=multi -cpu max,pauth-impdef=on" ;;
esac
case $accel in
*tcg*) timeout=${timeout:-900} ;;
*) timeout=${timeout:-300} ;;
esac
efi=${QEMU_EFI:-}
if [ -z "$efi" ]; then
    for f in /opt/homebrew/share/qemu/edk2-aarch64-code.fd /usr/local/share/qemu/edk2-aarch64-code.fd \
        /usr/share/qemu-efi-aarch64/QEMU_EFI.fd /usr/share/qemu/edk2-aarch64-code.fd \
        /usr/share/edk2/aarch64/QEMU_EFI.fd /usr/share/AAVMF/AAVMF_CODE.fd; do
        if [ -f "$f" ]; then
            efi=$f
            break
        fi
    done
fi
[ -n "$efi" ] && [ -f "$efi" ] || die "no UEFI firmware for aarch64: set QEMU_EFI"
say "work $work; qemu: $accel, firmware $efi; boot limit $timeout s"

qemu_pid=
stop_qemu() {
    if [ -n "$qemu_pid" ] && kill -0 "$qemu_pid" 2> /dev/null; then
        kill "$qemu_pid" 2> /dev/null || true
        sleep 1
        kill -9 "$qemu_pid" 2> /dev/null || true
    fi
    qemu_pid=
}
trap stop_qemu EXIT
trap 'exit 1' INT TERM

# boot <disk> <console log>: in the background, the gateway and SSH forwarded to loopback
boot() {
    # shellcheck disable=SC2086 # $accel is a list of words
    "$QEMU" -M virt $accel -smp 2 -m 1024 -display none -monitor none -nodefaults \
        -bios "$efi" -drive "file=$1,format=raw,if=virtio" \
        -netdev "user,id=n0,hostfwd=tcp:127.0.0.1:$PORT-:8445,hostfwd=tcp:127.0.0.1:$SSH_PORT-:22" \
        -device virtio-net-pci,netdev=n0 -serial "file:$2" > "$2.qemu" 2>&1 &
    qemu_pid=$!
    booted=$(date +%s)
    say "booted $(basename "$1") (qemu $qemu_pid), console $2"
}

# the seconds since the last boot
since() { echo $(($(date +%s) - booted)); }

# wait_console <log> <text> <seconds>
wait_console() {
    n=0
    until grep -qF "$2" "$1" 2> /dev/null; do
        kill -0 "$qemu_pid" 2> /dev/null || die "qemu ended; $1: $(tail -5 "$1")"
        [ "$n" -lt "$3" ] || die "no \"$2\" on the console within $3 s"
        sleep 2
        n=$((n + 2))
    done
}

key=$work/id_smoke
guest() {
    ssh -i "$key" -p "$SSH_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=10 -o BatchMode=yes -o LogLevel=ERROR root@127.0.0.1 "$@"
}

# What the guest says about its broker: `uid=`, the mounts of the data partition, `tail=`
# (sectors from the end of the data partition to the end of the disk), the clock and
# what the log says about NTP and the first boot.
guest_report() {
    guest 'sh -s' << 'EOF'
pid=$(pgrep -f '^/usr/bin/wyrmd( |$)' | head -1)
echo "wyrmd pid ${pid:-none}"
[ -z "$pid" ] || echo "uid=$(sed -n 's/^Uid:[[:space:]]*\([0-9]*\).*/\1/p' "/proc/$pid/status")"
grep -E ' /srv/wyrm(-part)? ' /proc/mounts
d=$(cat /sys/block/vda/size)
s=$(cat /sys/block/vda/vda4/start)
n=$(cat /sys/block/vda/vda4/size)
echo "vda4: start $s, size $n sectors, disk $d sectors"
echo "tail=$((d - s - n))"
echo "time: $(date -u); NTP marker: $(ls /var/run/wyrm/time-synced 2>&1)"
logread | grep -iE 'ntpd|ntp:|wyrm: no NTP' | tail -5 | cut -c1-160
logread -e wyrm | grep -E 'first boot|data:|broker up|not started' | cut -c1-160
EOF
}

# poweroff through SSH; qemu ends with the guest
power_off() {
    guest poweroff || true
    n=0
    while kill -0 "$qemu_pid" 2> /dev/null; do
        [ "$n" -lt 90 ] || {
            say "the guest did not power off in 90 s: qemu is stopped"
            break
        }
        sleep 1
        n=$((n + 1))
    done
    stop_qemu
}

# inspect <disk>: `wyr image inspect` of the image's own bytes (the disk grew past them)
inspect() {
    head -c "$size" "$1" > "$work/inspect.img"
    "$wyr" image inspect --image "$work/inspect.img" --index "$index" --board "$BOARD"
    rm -f "$work/inspect.img"
}

# grow <disk>: room for the data partition, as a card larger than the image
grow() { truncate -s 1G "$1"; }

# ---- 1. the base image ----------------------------------------------------------------

start=$(date +%s)
if [ -z "$base" ]; then
    base=$work/base
    say "1. wyr image base --board $BOARD (wyrmd $version)"
    set -- --board "$BOARD" --wyrmd "$wyrmd" --wyrmd-version "$version" --out "$base" \
        --packaging "$repo/packaging"
    [ -z "$cache" ] || set -- "$@" --cache "$cache"
    "$wyr" image base "$@"
fi
index=$base/index.json
file=$(client entry "$index" "$BOARD" file)
size=$(client entry "$index" "$BOARD" size)
image=$base/$file
[ -f "$image" ] || die "no $image"
say "base image $file ($size bytes) after $(($(date +%s) - start)) s"
"$here/verify-table.sh" "$image"
inspect "$image" | tee "$work/inspect-base.txt"
grep -qx 'region: empty' "$work/inspect-base.txt" || die "the base image's region is not empty"

# ---- 2. the base image as it is: no broker --------------------------------------------

say "2. the base image without a configuration"
cp "$image" "$work/bare.img"
grow "$work/bare.img"
boot "$work/bare.img" "$work/console-bare.log"
wait_console "$work/console-bare.log" "wyrm: the broker is not started: no configuration is applied on this device" "$timeout"
say "console after $(since) s: $(grep -F 'wyrm: the broker is not started' "$work/console-bare.log" | head -1)"
grep -F 'wyrm' "$work/console-bare.log" | sed 's/^/  console: /'
# the network is up by now (the service starts after it); the firewall opens 8445
sleep 10
client closed "$PORT"
stop_qemu
# the table as the image had it: the service never reached the data partition script,
# which adds partition 4 to the primary GPT (the protective MBR and 32 sectors of table)
head -c 17408 "$image" > "$work/table-base"
head -c 17408 "$work/bare.img" > "$work/table-bare"
cmp "$work/table-base" "$work/table-bare" ||
    die "the table of the disk without a configuration changed: a data partition was made"
rm -f "$work/table-base" "$work/table-bare"
say "no data partition was made: the service stopped before it"
rm -f "$work/bare.img"

# ---- 3. the assembled image: the first admin ------------------------------------------

say "3. wyr image build with a test configuration and a new setup code"
rm -f "$key" "$key.pub"
ssh-keygen -q -t ed25519 -N '' -C wyrm-smoke -f "$key"
cat > "$work/wyrmd.json5" << EOF
{
  site: "$SITE",
  data_dir: "/srv/wyrm",
  listen: ["tcp/127.0.0.1:7447"],
  gateway: { listen: "0.0.0.0:8445", tls: "site_ca", setup_file: "/etc/wyrm/setup.d/setup" },
}
EOF
disk=$work/disk.img
"$wyr" image build --image "$image" --index "$index" --board "$BOARD" \
    --config "$work/wyrmd.json5" --new-setup-code --authorized-keys "$key.pub" \
    --out "$disk" --force > "$work/build.out"
SMOKE_CODE=$(sed -n 's/^setup code: //p' "$work/build.out")
[ -n "$SMOKE_CODE" ] || die "wyr image build printed no setup code"
rm -f "$work/build.out"
SMOKE_USER='admin'
SMOKE_PASSWORD=$(od -An -N12 -tx1 /dev/urandom | tr -d ' \n')
export SMOKE_CODE SMOKE_USER SMOKE_PASSWORD
inspect "$disk" | tee "$work/inspect-built.txt"
grep -qx 'region: assembled' "$work/inspect-built.txt" || die "the assembled image's region is not assembled"
grow "$disk"

boot "$disk" "$work/console-1.log"
up=$(client wait "$PORT" "$timeout")
say "the gateway answers TLS $(since) s after the boot (TLS up after $up s of polling)"
grep -F 'wyrm' "$work/console-1.log" | sed 's/^/  console: /'
mkdir -p "$work/state"
client setup "$PORT" "$work/state"
say "the guest after the first boot:"
guest_report > "$work/guest-1.txt"
sed 's/^/  guest: /' "$work/guest-1.txt"
uid=$(sed -n 's/^uid=//p' "$work/guest-1.txt")
[ "$uid" = 787 ] || die "the broker runs as uid '$uid', not 787"
grep -q '^/dev/vda4 /srv/wyrm ' "$work/guest-1.txt" || die "/srv/wyrm is not the data partition"
tail=$(sed -n 's/^tail=//p' "$work/guest-1.txt")
[ "${tail:-0}" -ge 2048 ] || die "the data partition ends ${tail:-?} sectors before the end of the disk (< 1 MiB)"

# ---- 4. power off and boot again ------------------------------------------------------

say "4. power off and boot again"
power_off
boot "$disk" "$work/console-2.log"
up=$(client wait "$PORT" "$timeout")
say "the gateway answers TLS $(since) s after the second boot"
client login "$PORT" "$work/state"
guest_report > "$work/guest-2.txt"
sed 's/^/  guest: /' "$work/guest-2.txt"
[ "$(sed -n 's/^uid=//p' "$work/guest-2.txt")" = 787 ] || die "the broker does not run as uid 787 after the second boot"
power_off

# ---- 5. the disk: region wiped, table sound -------------------------------------------

say "5. the disk after two boots"
inspect "$disk" | tee "$work/inspect-after.txt"
grep -qx 'region: empty' "$work/inspect-after.txt" || die "the region on the disk is not empty after the first boot"
"$here/verify-table.sh" "$disk"
say "PASS in $(($(date +%s) - start)) s (work: $work)"
