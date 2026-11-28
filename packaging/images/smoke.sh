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
#   --assembled <img.gz>  the image of step 3 is assembled by the image builder page's
#                       own code (`node tool/site/test_start.mjs --assemble`: the page's
#                       script and its WebAssembly, built by tool/site/wasm.sh) into
#                       <img.gz> from the gzip of `--base` (required) and the choices of
#                       this run (its SSH key is in them), and booted, instead of an
#                       image of `wyr image build`; step 2 is left out
#   --catalog <file>    the links the page's choices are read against (default: made
#                       from links/official.json by catalog.py)
#   --network <mode>    with --assembled: `dhcp` (default) or `static`, the page's static
#                       address on QEMU's user network (10.0.2.15/24, gateway 10.0.2.2,
#                       DNS 10.0.2.3: the address the forward reaches); the checks add
#                       that uci holds it after each boot, and NTP resolves the pool
#                       names through that DNS server
#   --cache <dir>       the ImageBuilder archives (`wyr image base --cache`)
#   --timeout <s>       how long a boot may take until the gateway answers TLS (default
#                       180 with hvf or kvm, 900 under TCG)
#
# Environment: RUNTIME (docker or podman), QEMU (qemu-system-aarch64), QEMU_EFI (the
# UEFI firmware), SMOKE_PORT (18445, the gateway on the host), SMOKE_SSH (10022),
# SMOKE_ACCEL (`tcg`: TCG even where hvf or kvm is there, as on a CI runner).
#
# 1. `wyr image base` makes the base image; `verify-table.sh` checks its table, and
#    `gzip-readers.sh` that its gzip is one member whose trailer gives the image's size and
#    that gunzip, libarchive, Python and Node read it as the image (with `--base`, only
#    when the directory holds the gzip).
# 2. The base image as it is (no configuration) boots: the console says the broker is
#    not started, and nothing answers on the gateway's port through the forward. The
#    image has no login (SSH off, root locked), so the guest's loopback is not probed:
#    that no broker runs at all is shown by the console line and by the disk, which
#    gets no data partition (the service makes it only for a configuration).
# 3. `wyr image build` assembles the image with a test configuration, a new setup code,
#    an SSH key of this run, a time zone and NTP servers. It boots on a disk with room
#    for the data partition:
#    within the time limit the gateway answers TLS; `wyr setup` (code and password on
#    stdin) checks the `setup_proof` of `/api/info` with the code, pins the CA, makes the
#    first admin with `POST /api/setup` and logs in; over the CA it wrote, the gateway
#    offers no setup any more, refuses a second one, and the login works. NTP set the clock
#    (the marker /var/run/wyrm/time-synced) and the site's CA was made after it. uci
#    holds the zone and the servers of the build; the broker runs as uid 787 in the
#    group dialout on the data partition.
#    With `--assembled`, the page's code assembles the image from choices
#    (`wyrm-choices/1`) with the same site, key, zone and servers, Modbus and the four
#    services on; `gzip-readers.sh` checks the gzip it wrote as the imagers read it, and
#    the same checks follow.
# 4. It is powered off and booted again: the same CA, no setup offered, the login
#    works, NTP set the clock again, the broker runs as uid 787 in the group dialout.
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
# the zone and the servers the assembled image sets (uci, at the first boot): the servers
# replace OpenWrt's list, so they must answer for the clock check to pass
ZONE=Europe/Kyiv
NTP=0.openwrt.pool.ntp.org,1.openwrt.pool.ntp.org,2.openwrt.pool.ntp.org

say() { echo "smoke [$(date -u +%H:%M:%S)] $*"; }
die() {
    say "FAIL: $*"
    exit 1
}
client() { python3 -I "$here/smoke_client.py" "$@"; }

wyr='' wyrmd='' version='' work='' base='' cache='' timeout='' assembled='' catalog='' network=dhcp
while [ $# -gt 0 ]; do
    [ $# -ge 2 ] || die "$1 needs a value"
    case $1 in
    --wyr) wyr=$2 ;;
    --wyrmd) wyrmd=$2 ;;
    --wyrmd-version) version=$2 ;;
    --work) work=$2 ;;
    --base) base=$2 ;;
    --assembled) assembled=$2 ;;
    --catalog) catalog=$2 ;;
    --network) network=$2 ;;
    --cache) cache=$2 ;;
    --timeout) timeout=$2 ;;
    *) die "unknown option $1" ;;
    esac
    shift 2
done
if [ -z "$base" ] && { [ -z "$wyrmd" ] || [ -z "$version" ]; }; then
    die "usage: smoke.sh --wyrmd <aarch64 musl wyrmd> --wyrmd-version <version> [--base <dir>] [--assembled <img.gz> [--network dhcp|static]] [--catalog <file>] [--wyr <path>] [--work <dir>] [--cache <dir>] [--timeout <s>]"
fi
case $network in
dhcp) ;;
static) [ -n "$assembled" ] || die "--network static takes --assembled (the page's choices)" ;;
*) die "--network is dhcp or static" ;;
esac
if [ -n "$assembled" ]; then
    [ -n "$base" ] || die "--assembled takes the base image of --base"
    command -v node > /dev/null 2>&1 || die "node is not installed (--assembled runs the page's code)"
    [ -f "$repo/site/dist/assets/wasm/wyrm_image_web_bg.wasm" ] ||
        die "no WebAssembly of the page: run tool/site/wasm.sh (or tool/site/build.py) first"
    case $assembled in
    /*) ;;
    *) assembled=$(pwd)/$assembled ;;
    esac
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

# Under TCG the CPU is `cortex-a72` (the core of the Raspberry Pi 4), never `max`: the
# UEFI firmware of Ubuntu 26.04 (`qemu-efi-aarch64` 2025.11) prints its banner and then
# stops on a `max` CPU (with QEMU 10.2 and 11.1 alike; with `lpa2=off` it ends in a
# synchronous exception), so the guest never boots on a CI runner.
tcg="-accel tcg,thread=multi -cpu cortex-a72"
case ${SMOKE_ACCEL:-}/$(uname -s)/$(uname -m) in
tcg/*) accel=$tcg ;;
/Darwin/arm64) accel="-accel hvf -cpu host" ;;
/Linux/aarch64)
    if [ -w /dev/kvm ]; then
        accel="-accel kvm -cpu host"
    else
        accel=$tcg
    fi
    ;;
/*) accel=$tcg ;;
*) die "SMOKE_ACCEL is tcg or not set" ;;
esac
# An aarch64 guest under TCG (an x86-64 CI runner) boots and hashes passwords many times
# slower than with hvf or kvm, so it gets five times the plan's limit.
case $accel in
*tcg*) timeout=${timeout:-900} ;;
*) timeout=${timeout:-180} ;;
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
        kill -0 "$qemu_pid" 2> /dev/null || die "qemu ended; $1: $(tail -5 "$1"); qemu: $(tail -5 "$1.qemu")"
        [ "$n" -lt "$3" ] || die "no \"$2\" on the console within $3 s; its last line: $(tail -1 "$1")"
        sleep 2
        n=$((n + 2))
    done
}

key=$work/id_smoke
guest() {
    ssh -i "$key" -p "$SSH_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=10 -o BatchMode=yes -o LogLevel=ERROR root@127.0.0.1 "$@"
}

# What the guest says about its broker: `uid=`, `groups=` (its supplementary groups),
# `dialout=` (the id of that group), `zonename=` and `ntp=` (what the first boot set in
# uci), the mounts of the data partition, `tail=` (sectors from the end of the data
# partition to the end of the disk), the clock (`now=`,
# `synced_at=` and `synced_uptime=` of the NTP marker, `ca_made=`: the site CA's file,
# Unix seconds) and what the log says about NTP and the first boot.
guest_report() {
    guest 'sh -s' << 'EOF'
pid=$(pgrep -f '^/usr/bin/wyrmd( |$)' | head -1)
echo "wyrmd pid ${pid:-none}"
[ -z "$pid" ] || echo "uid=$(sed -n 's/^Uid:[[:space:]]*\([0-9]*\).*/\1/p' "/proc/$pid/status")"
[ -z "$pid" ] || echo "groups=$(sed -n 's/^Groups:[[:space:]]*//p' "/proc/$pid/status" | tr -s ' \t' ' ' | sed 's/ $//')"
echo "dialout=$(sed -n 's/^dialout:[^:]*:\([0-9]*\):.*/\1/p' /etc/group)"
echo "zonename=$(uci -q get system.@system[0].zonename)"
echo "ntp=$(uci -q get system.ntp.server)"
echo "lan=$(uci -q get network.lan.proto) $(uci -q get network.lan.ipaddr) $(uci -q get network.lan.netmask) $(uci -q get network.lan.gateway) $(uci -q get network.lan.dns)"
echo "lan_up=$(ip -4 -o addr show dev br-lan 2> /dev/null | awk '{print $4}' | head -1)"
grep -E ' /srv/wyrm(-part)? ' /proc/mounts
d=$(cat /sys/block/vda/size)
s=$(cat /sys/block/vda/vda4/start)
n=$(cat /sys/block/vda/vda4/size)
echo "vda4: start $s, size $n sectors, disk $d sectors"
echo "tail=$((d - s - n))"
now=$(date +%s)
up=$(cut -d. -f1 /proc/uptime)
echo "now=$now"
if [ -e /var/run/wyrm/time-synced ]; then
    m=$(date -r /var/run/wyrm/time-synced +%s)
    echo "synced_at=$m"
    echo "synced_uptime=$((up - (now - m)))"
fi
[ ! -e /srv/wyrm/pki/ca.pem ] || echo "ca_made=$(date -r /srv/wyrm/pki/ca.pem +%s)"
logread | grep -E 'wyrm: no NTP' | cut -c1-160
logread -e wyrm | grep -E 'first boot|data:|broker up|not started' | cut -c1-160
EOF
}

# clock <report>: NTP set the clock (the marker of /etc/hotplug.d/ntp/20-wyrm-time) and
# the broker did not wait the full 120 s for it; the guest's clock against this host's
value() { sed -n "s/^$1=//p" "$2"; }
clock() {
    host=$(date +%s)
    synced=$(value synced_uptime "$1")
    [ -n "$synced" ] || die "NTP did not set the clock: no /var/run/wyrm/time-synced"
    ! grep -q 'wyrm: no NTP' "$1" || die "the broker waited for NTP in vain"
    say "NTP set the clock $synced s after the boot; the guest's clock is $(($(value now "$1") - host)) s from this host's"
}

# wait_ntp: until NTP set the guest's clock (the marker of /etc/hotplug.d/ntp/20-wyrm-time),
# at most 120 s. Only the first start of the broker waits for it (run.sh): at a later boot
# the gateway may answer before NTP does, the sooner with a static address (no DHCP lease
# to wait for).
wait_ntp() {
    n=0
    until guest test -e /var/run/wyrm/time-synced 2> /dev/null; do
        [ "$n" -lt 120 ] || return 0
        sleep 3
        n=$((n + 3))
    done
}

# broker_groups <report>: the broker is in the group dialout (serial ports: Modbus RTU and
# the like), whose id the guest's /etc/group says
broker_groups() {
    dialout=$(value dialout "$1")
    [ -n "$dialout" ] || die "the guest has no group dialout"
    case " $(value groups "$1") " in
    *" $dialout "*) say "the broker is in the group dialout ($dialout)" ;;
    *) die "the broker's groups '$(value groups "$1")' lack dialout ($dialout)" ;;
    esac
}

# lan <report>: `lan` of uci as the network of the choices: the DHCP client, or the static
# address (and its address on the bridge)
lan() {
    got=$(value lan "$1")
    if [ "$network" = static ]; then
        [ "$got" = "static 10.0.2.15 255.255.255.0 10.0.2.2 10.0.2.3" ] ||
            die "lan in uci is '$got', not the static address of the choices"
        [ "$(value lan_up "$1")" = 10.0.2.15/24 ] ||
            die "br-lan has '$(value lan_up "$1")', not 10.0.2.15/24"
        say "lan: the static address 10.0.2.15/24 (gateway 10.0.2.2, DNS 10.0.2.3) on br-lan"
    else
        case $got in
        dhcp*) say "lan: DHCP client ($(value lan_up "$1") on br-lan)" ;;
        *) die "lan in uci is '$got', not the DHCP client" ;;
        esac
    fi
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
built=no
if [ -z "$base" ]; then
    built=yes
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
# the gzip that is published: every reader an imager uses must give the image from it
gz=$(client entry "$index" "$BOARD" download.file)
if [ -n "$gz" ] && [ -f "$base/$gz" ]; then
    "$here/gzip-readers.sh" "$image" "$base/$gz"
elif [ "$built" = yes ]; then
    die "wyr image base left no gzip of the image (download.file: '$gz')"
else
    say "NOT CHECKED: $base holds no gzip of the image; the gzip readers do not run"
fi
inspect "$image" | tee "$work/inspect-base.txt"
grep -qx 'region: empty' "$work/inspect-base.txt" || die "the base image's region is not empty"

# ---- 2. the base image as it is: no broker --------------------------------------------

if [ -n "$assembled" ]; then
    say "2. left out with --assembled: the run without it boots the base image as it is"
else
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
fi

# ---- 3. the assembled image: the first admin ------------------------------------------

if [ -n "$assembled" ]; then by="the image builder page's code"; else by="wyr image build"; fi
say "3. $by: a test configuration and a new setup code (network: $network)"
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
if [ -n "$assembled" ]; then
    [ -n "$gz" ] && [ -f "$base/$gz" ] || die "--assembled needs the gzip of the base image in $base"
    if [ -z "$catalog" ]; then
        catalog=$work/catalog.json
        python3 -I "$here/catalog.py" --out "$catalog"
    fi
    # the site, key, zone and servers of the configuration above, as the page's choices
    python3 -I -c '
import json, sys
site, zone, ntp, key, mode = sys.argv[1:]
# the user network of QEMU: the guest is 10.0.2.15, the host 10.0.2.2, its DNS 10.0.2.3
network = {"mode": "dhcp"} if mode == "dhcp" else {
    "mode": "static", "address": "10.0.2.15", "prefix": 24,
    "gateway": "10.0.2.2", "dns": ["10.0.2.3"],
}
print(json.dumps({
    "format": "wyrm-choices/1",
    "site": site,
    "network": network,
    "links": ["modbus", "scheduler", "alarm", "dql", "uplink"],
    "timezone": zone,
    "ntp": ntp.split(","),
    "ssh_keys": open(key, encoding="utf-8").read(),
}))
' "$SITE" "$ZONE" "$NTP" "$key.pub" "$network" > "$work/choices.json"
    say "the page's code assembles $(basename "$assembled") from $gz"
    node "$repo/tool/site/test_start.mjs" --assemble "$work/choices.json" "$assembled" \
        --images "$base" --catalog "$catalog" --board "$BOARD" > "$work/build.out"
    # what a person writes to a card: the gzip, read as the imagers read it
    gzip -dc "$assembled" > "$disk"
    "$here/gzip-readers.sh" "$disk" "$assembled"
else
    "$wyr" image build --image "$image" --index "$index" --board "$BOARD" \
        --config "$work/wyrmd.json5" --new-setup-code --authorized-keys "$key.pub" \
        --timezone "$ZONE" --ntp "$NTP" --out "$disk" --force > "$work/build.out"
fi
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
# the first admin as a person makes it: wyr setup reads the code and the password as two
# lines of stdin, proves the CA with the code, pins it and writes it for the checks after
say "wyr setup --gateway https://127.0.0.1:$PORT (the forward of the gateway)"
printf '%s\n%s\n' "$SMOKE_CODE" "$SMOKE_PASSWORD" |
    "$wyr" setup --gateway "https://127.0.0.1:$PORT" --user "$SMOKE_USER" \
        --ca-out "$work/state/ca.pem" > "$work/setup.out" 2>&1 ||
    die "wyr setup: $(cat "$work/setup.out")"
sed 's/^/  wyr setup: /' "$work/setup.out"
client after-setup "$PORT" "$work/state"
say "the guest after the first boot:"
guest_report > "$work/guest-1.txt"
sed 's/^/  guest: /' "$work/guest-1.txt"
uid=$(sed -n 's/^uid=//p' "$work/guest-1.txt")
[ "$uid" = 787 ] || die "the broker runs as uid '$uid', not 787"
broker_groups "$work/guest-1.txt"
[ "$(value zonename "$work/guest-1.txt")" = "$ZONE" ] ||
    die "the zone in uci is '$(value zonename "$work/guest-1.txt")', not $ZONE"
[ "$(value ntp "$work/guest-1.txt")" = "$(echo "$NTP" | tr ',' ' ')" ] ||
    die "the NTP servers in uci are '$(value ntp "$work/guest-1.txt")', not $NTP"
say "uci: zone $ZONE, NTP servers $NTP"
lan "$work/guest-1.txt"
grep -q '^/dev/vda4 /srv/wyrm ' "$work/guest-1.txt" || die "/srv/wyrm is not the data partition"
tail=$(sed -n 's/^tail=//p' "$work/guest-1.txt")
[ "${tail:-0}" -ge 2048 ] || die "the data partition ends ${tail:-?} sectors before the end of the disk (< 1 MiB)"
clock "$work/guest-1.txt"
# the first start makes the site's CA only when the clock is set
made=$(value ca_made "$work/guest-1.txt")
at=$(value synced_at "$work/guest-1.txt")
[ -n "$made" ] && [ "$made" -ge "$at" ] || die "the site CA ($made) was made before NTP set the clock ($at)"
say "the site CA was made $((made - at)) s after NTP set the clock, at $(date -u -r "$made" 2> /dev/null || date -u -d "@$made")"

# ---- 4. power off and boot again ------------------------------------------------------

say "4. power off and boot again"
power_off
boot "$disk" "$work/console-2.log"
up=$(client wait "$PORT" "$timeout")
say "the gateway answers TLS $(since) s after the second boot"
client login "$PORT" "$work/state"
wait_ntp
guest_report > "$work/guest-2.txt"
sed 's/^/  guest: /' "$work/guest-2.txt"
[ "$(sed -n 's/^uid=//p' "$work/guest-2.txt")" = 787 ] || die "the broker does not run as uid 787 after the second boot"
broker_groups "$work/guest-2.txt"
lan "$work/guest-2.txt"
clock "$work/guest-2.txt"
power_off

# ---- 5. the disk: region wiped, table sound -------------------------------------------

say "5. the disk after two boots"
inspect "$disk" | tee "$work/inspect-after.txt"
grep -qx 'region: empty' "$work/inspect-after.txt" || die "the region on the disk is not empty after the first boot"
"$here/verify-table.sh" "$disk"
say "PASS in $(($(date +%s) - start)) s (work: $work)"
