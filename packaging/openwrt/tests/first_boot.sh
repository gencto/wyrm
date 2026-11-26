#!/bin/sh
# Tests of the first-boot script (ADR 0051 §4, "On the device").
#
#   SH=dash packaging/openwrt/tests/first_boot.sh                 # a developer's machine
#   SH="busybox sh" BB=busybox packaging/openwrt/tests/first_boot.sh   # CI, as on the device
#
# SH   the shell that runs first-boot.sh (default: sh)
# BB   empty: the script and the tests use the system's dd, tar, sha256sum, hexdump …
#      `busybox`: they use busybox's applets (a directory of links in front of PATH)
# VERBOSE  not empty: print why each refused region was refused
# WYR  the built `wyr` (default: `cargo build -p wyr`, then target/debug/wyr)
#
# The regions the device must accept are written by `wyr image build`, so a run with
# BB=busybox proves that busybox unpacks what the crate `wyrm-image` writes. The regions
# it must refuse come from mkregion.py: the crate does not write them.

set -u
LC_ALL=C
export LC_ALL

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../.." && pwd)
script=$root/packaging/openwrt/wyrmd/files/usr/libexec/wyrm/first-boot.sh
SH=${SH:-sh}
BB=${BB:-}

work=$(mktemp -d "${TMPDIR:-/tmp}/wyrm-first-boot.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT

if [ -z "${WYR:-}" ]; then
    (cd "$root" && cargo build -q -p wyr) || exit 1
    WYR=${CARGO_TARGET_DIR:-$root/target}/debug/wyr
fi
case $WYR in
/*) ;;
*) WYR=$PWD/$WYR ;;
esac

if [ -n "$BB" ]; then
    bb=$(command -v "$BB") || { echo "no $BB" >&2; exit 1; }
    mkdir "$work/bin"
    # every tool the script and the tests call; one this busybox does not have fails the run
    for applet in cat chmod cmp cp cut dd dirname find grep head hexdump ls mkdir mv \
        rm sha256sum sort sync tail tar tr wc; do
        "$bb" --list | grep -qx "$applet" || { echo "$BB has no $applet" >&2; exit 1; }
        ln -s "$bb" "$work/bin/$applet"
    done
    PATH=$work/bin:$PATH
    export PATH
fi

CONFIG='{ site: "plant", gateway: { listen: "0.0.0.0:8445", tls: "site_ca", setup_file: "/etc/wyrm/setup" } }'
DEFAULT='{ site: "unconfigured" }'
NETWORK="config interface 'lan'
	option proto 'static'
	option ipaddr '10.0.0.7'"
SEED='{"format": "wyrm-seed/1", "links": []}'
HASH=3f0a9c1e5b7d2468ace013579bdf02468ace13579bdf0246813579bdf02468ac
KEYS='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOnlyThePersonsKey person@host'
POSIX_TZ='EET-2EEST,M3.5.0/3,M10.5.0/4'

# the empty region of a base image, and the index that describes it as an image
{
    printf 'WYRMCFG0'
    dd if=/dev/zero bs=4088 count=1 2>/dev/null
    dd if=/dev/zero bs=4096 count=1023 2>/dev/null
} > "$work/base.img"
sum=$(sha256sum < "$work/base.img" | cut -d' ' -f1)
cat > "$work/index.json" <<EOF
{"format": "wyrm-images/1", "images": [
  {"board": "rpi4", "file": "base.img", "size": 4194304, "sha256": "$sum",
   "config_offset": 0, "openwrt": "24.10.4", "wyrmd": "0.9.0"}]}
EOF
printf '%s\n' "$CONFIG" > "$work/wyrmd.json5"
printf '%s\n' "$NETWORK" > "$work/network"
printf '%s\n' "$SEED" > "$work/seed.json"
printf '%s\n' "$HASH" > "$work/setup.hash"
printf '%s\n' "$KEYS" > "$work/keys"

# a stand-in for `uci`: records every call, and refuses a network file that says BROKEN
cat > "$work/uci" <<'EOF'
#!/bin/sh
echo "$*" >> "$UCI_LOG"
dir=
while [ $# -gt 0 ]; do
    case $1 in
    -c) dir=$2; shift ;;
    show) if grep -q BROKEN "$dir/$2"; then exit 1; fi ;;
    esac
    shift
done
exit 0
EOF
chmod 755 "$work/uci"

# wyr_region OUT [more arguments of `wyr image build`]
wyr_region() {
    out=$1
    shift
    "$WYR" image build --image "$work/base.img" --index "$work/index.json" --board rpi4 \
        --config "$work/wyrmd.json5" --out "$out" "$@" > /dev/null
}

full_region() {
    wyr_region "$1" --network "$work/network" --seed "$work/seed.json" \
        --setup-hash-file "$work/setup.hash" --authorized-keys "$work/keys" \
        --timezone Europe/Kyiv --ntp ntp1.example,ntp2.example
}

bad_region() {
    out=$1
    shift
    python3 "$here/mkregion.py" "$out" "$@"
}

# A device before its first boot: the image's default config and network, zone data.
setup_device() {
    t=$work/t/$1
    mkdir -p "$t/etc/wyrm" "$t/etc/config" "$t/zoneinfo/Europe" "$t/seed"
    printf '%s\n' "$DEFAULT" > "$t/etc/wyrm/wyrmd.json5"
    printf 'config interface lan\n' > "$t/etc/config/network"
    printf 'TZif2 binary\n%s\n' "$POSIX_TZ" > "$t/zoneinfo/Europe/Kyiv"
    : > "$t/uci.log"
}

# first_boot: runs the script on $t/region; its exit code in $rc, its messages in $t/err
first_boot() {
    rc=0
    UCI_LOG=$t/uci.log WYRM_UCI=$work/uci WYRM_SEED_DIR=$t/seed WYRM_ZONEINFO=$t/zoneinfo \
        $SH "$script" "$t/region" "$t/stage" "$t/etc" 2> "$t/err" || rc=$?
}

# what the script may change, as text: every file with its mode and its hash
# shellcheck disable=SC2012 # the mode as `ls` shows it; the names are the tests' own
state() {
    (cd "$t" && find etc seed | sort | while IFS= read -r f; do
        if [ -f "$f" ]; then
            echo "$(ls -ld "$f" | cut -c1-10) $f $(sha256sum < "$f" | cut -d' ' -f1)"
        else
            echo "dir $f"
        fi
    done)
}

# shellcheck disable=SC2012
mode() { ls -ld "$1" | cut -c1-10; }

failed=0
fail() {
    echo "  FAILED: $*" >&2
    failed=1
}
want() { # want WHAT GOT EXPECTED
    [ "$2" = "$3" ] || fail "$1: got \`$2\`, expected \`$3\`"
}
want_file() { # want_file PATH CONTENT MODE
    if [ ! -f "$1" ]; then
        fail "$1 is missing"
        return
    fi
    want "content of $1" "$(cat "$1")" "$2"
    want "mode of $1" "$(mode "$1")" "$3"
}
want_uci() {
    grep -qxF -- "$1" "$t/uci.log" || fail "no uci call \`$1\`"
}
want_empty_region() {
    cmp -s "$t/region" "$work/base.img" || fail "the region is not WYRMCFG0 and zeros"
}
# The run was refused: exit 4, and the device and the region are as they were.
want_refused() {
    want "exit code ($(cat "$t/err"))" "$rc" 4
    want "state" "$(state)" "$before"
    cmp -s "$t/region" "$t/region.before" || fail "a refused run changed the region"
    [ ! -e "$t/stage" ] || fail "the staging directory stays"
    [ ! -e "$t/etc/wyrm/.first-boot-done" ] || fail "a refused run left the marker"
    grep -q 'nothing was applied' "$t/err" || fail "no message: $(cat "$t/err")"
}
# refused NAME: runs the script on the region the caller wrote and wants it refused
refused() {
    cp "$t/region" "$t/region.before"
    before=$(state)
    first_boot
    want_refused
    if [ -n "${VERBOSE:-}" ]; then
        echo "  ${t##*/}: $(head -n 1 "$t/err")"
    fi
}

applies_all_files() {
    setup_device applies
    full_region "$t/region"
    first_boot
    want "exit code ($(cat "$t/err"))" "$rc" 0
    want_file "$t/etc/wyrm/wyrmd.json5" "$CONFIG" "-rw-r-----"
    want_file "$t/etc/wyrm/setup" "$HASH" "-rw-------"
    want_file "$t/etc/config/network" "$NETWORK" "-rw-------"
    want_file "$t/seed/seed.json" "$SEED" "-rw-r--r--"
    want_file "$t/etc/dropbear/authorized_keys" "$KEYS" "-rw-------"
    want_uci "-q set system.@system[0].zonename=Europe/Kyiv"
    want_uci "-q set system.@system[0].timezone=$POSIX_TZ"
    want_uci "-q add_list system.ntp.server=ntp1.example"
    want_uci "-q add_list system.ntp.server=ntp2.example"
    want_uci "-q commit system"
    want_uci "-q set dropbear.@dropbear[0].enable=1"
    want_uci "-q set dropbear.@dropbear[0].PasswordAuth=off"
    want_uci "-q set dropbear.@dropbear[0].RootPasswordAuth=off"
    want_uci "-q set firewall.wyrm_ssh.enabled=1"
    want_empty_region
    [ -e "$t/etc/wyrm/.first-boot-done" ] || fail "no marker"
    [ -e "$t/etc/wyrm/.first-boot-applied" ] || fail "no record that the files are in place"
    [ ! -e "$t/stage" ] || fail "the staging directory stays"
    want "temporary files" "$(find "$t/etc" "$t/seed" -name '*.wyrm-new')" ""
}

setup_is_0600() {
    setup_device modes
    # the archive says 0777 for every file: the script sets the modes itself
    bad_region "$t/region" --mode 777 "wyrmd.json5=$CONFIG" "setup=$HASH\\n" "authorized_keys=$KEYS\\n"
    first_boot
    want "exit code ($(cat "$t/err"))" "$rc" 0
    want_file "$t/etc/wyrm/setup" "$HASH" "-rw-------"
    want_file "$t/etc/wyrm/wyrmd.json5" "$CONFIG" "-rw-r-----"
    want_file "$t/etc/dropbear/authorized_keys" "$KEYS" "-rw-------"
    want "mode of dropbear's directory" "$(mode "$t/etc/dropbear")" "drwx------"
}

only_the_config() {
    setup_device only
    wyr_region "$t/region"
    first_boot
    want "exit code ($(cat "$t/err"))" "$rc" 0
    want_file "$t/etc/wyrm/wyrmd.json5" "$CONFIG" "-rw-r-----"
    want "the image's network" "$(cat "$t/etc/config/network")" "config interface lan"
    [ ! -e "$t/etc/wyrm/setup" ] || fail "a setup hash from nowhere"
    [ ! -e "$t/etc/dropbear" ] || fail "SSH keys from nowhere"
    want "uci calls" "$(cat "$t/uci.log")" ""
    want_empty_region
}

first_boot_twice() {
    setup_device twice
    full_region "$t/region"
    first_boot
    want "first exit code" "$rc" 0
    after=$(state)
    : > "$t/uci.log"
    first_boot
    want "second exit code" "$rc" 3
    want "state after the second run" "$(state)" "$after"
    want "uci calls of the second run" "$(cat "$t/uci.log")" ""
    want_empty_region
}

empty_region_exits_3() {
    setup_device empty
    cp "$work/base.img" "$t/region"
    before=$(state)
    first_boot
    want "exit code" "$rc" 3
    want "state" "$(state)" "$before"
    want_empty_region
    [ ! -e "$t/stage" ] || fail "the staging directory was made"
    [ ! -e "$t/etc/wyrm/.first-boot-done" ] || fail "an empty region left the marker"
    grep -q 'wyr image build' "$t/err" || fail "no word about wyr image build"
    grep -q 'https://wyrm.gencto.uk/docs/operations.html' "$t/err" || fail "no link to the guide"
    # an empty region is told by its magic: what follows is not read
    printf 'x' | dd of="$t/region" bs=1 seek=100000 conv=notrunc 2>/dev/null
    first_boot
    want "exit code with bytes after the empty magic" "$rc" 3
}

# A power loss after some files were put and before the wipe: the next boot applies again.
half_applied_is_applied_again() {
    setup_device half
    full_region "$t/region"
    cp "$t/region" "$t/region.full"
    first_boot
    want "first exit code" "$rc" 0
    after=$(state)
    cp "$t/region.full" "$t/region"
    rm "$t/etc/wyrm/.first-boot-done" "$t/etc/wyrm/.first-boot-applied" "$t/etc/wyrm/setup"
    printf '%s\n' "$DEFAULT" > "$t/etc/wyrm/wyrmd.json5"
    : > "$t/etc/config/network.wyrm-new"
    first_boot
    want "second exit code ($(cat "$t/err"))" "$rc" 0
    want "state" "$(state)" "$after"
    want_empty_region
}

# A power loss between the wipe and the marker: the next boot finds an empty region. It
# writes the marker and does not call the device unconfigured.
a_power_loss_after_the_wipe() {
    setup_device afterwipe
    full_region "$t/region"
    first_boot
    want "first exit code" "$rc" 0
    after=$(state)
    rm "$t/etc/wyrm/.first-boot-done"
    first_boot
    want "second exit code" "$rc" 3
    want "state" "$(state)" "$after"
    grep -q 'was applied before' "$t/err" || fail "message: $(cat "$t/err")"
    if grep -q 'wyr image build' "$t/err"; then
        fail "a configured device is called unconfigured"
    fi
}

a_flipped_byte_applies_nothing() {
    # in the payload, in the hash, in the length and after the payload
    for at in 700 20 9 2000000; do
        setup_device "flip$at"
        full_region "$t/region"
        printf '\377' | dd of="$t/region" bs=1 seek="$at" conv=notrunc 2>/dev/null
        refused
    done
    setup_device magic
    full_region "$t/region"
    printf 'X' | dd of="$t/region" bs=1 seek=7 conv=notrunc 2>/dev/null
    refused
}

a_bad_member_name_applies_nothing() {
    setup_device dotdot
    mkdir "$t/etc/victim"
    bad_region "$t/region" "wyrmd.json5=$CONFIG" "../etc/victim/passwd=root::0:0"
    refused
    setup_device absolute
    bad_region "$t/region" "wyrmd.json5=$CONFIG" "/tmp/wyrm-first-boot-victim.$$=x"
    refused
    [ ! -e "/tmp/wyrm-first-boot-victim.$$" ] || fail "a file outside the staging directory"
    setup_device extra
    bad_region "$t/region" "wyrmd.json5=$CONFIG" "extra=x"
    refused
    setup_device subdir
    bad_region "$t/region" "wyrmd.json5=$CONFIG" "wyrm/setup=$HASH"
    refused
    setup_device twice-in
    bad_region "$t/region" "wyrmd.json5=$CONFIG" "setup=$HASH" "setup=$HASH"
    refused
    setup_device noconfig
    bad_region "$t/region" "network=$NETWORK"
    refused
}

a_link_applies_nothing() {
    setup_device symlink
    bad_region "$t/region" "wyrmd.json5=$CONFIG" "network->wyrmd.json5"
    refused
    setup_device hardlink
    bad_region "$t/region" "wyrmd.json5=$CONFIG" "network=>wyrmd.json5"
    refused
}

a_bad_region_applies_nothing() {
    setup_device toolong
    bad_region "$t/region" --len 4194257 "wyrmd.json5=$CONFIG"
    refused
    setup_device huge
    bad_region "$t/region" --len 72057594037927936 "wyrmd.json5=$CONFIG"
    refused
    setup_device garbage
    bad_region "$t/region" --garbage "wyrmd.json5=$CONFIG"
    refused
    setup_device nomagic
    dd if=/dev/zero of="$t/region" bs=4096 count=1024 2>/dev/null
    refused
    setup_device nodevice
    before=$(state)
    first_boot
    want "exit code without a device" "$rc" 4
    want "state" "$(state)" "$before"
}

bad_content_applies_nothing() {
    setup_device emptyconfig
    bad_region "$t/region" "wyrmd.json5="
    refused
    setup_device nul
    bad_region "$t/region" "wyrmd.json5={ site: 'a\\x00b' }"
    refused
    setup_device shorthash
    bad_region "$t/region" "wyrmd.json5=$CONFIG" "setup=abc\\n"
    refused
    setup_device nothex
    bad_region "$t/region" "wyrmd.json5=$CONFIG" "setup=zz0a9c1e5b7d2468ace013579bdf02468ace13579bdf0246813579bdf02468ac\\n"
    refused
    setup_device network
    bad_region "$t/region" "wyrmd.json5=$CONFIG" "network=BROKEN"
    refused
    setup_device zone
    bad_region "$t/region" "wyrmd.json5=$CONFIG" "timezone=../../etc/passwd\\n"
    refused
    setup_device ntp
    bad_region "$t/region" "wyrmd.json5=$CONFIG" "ntp=good.example\\n-x; reboot\\n"
    refused
}

# A zone the image has no data for: the configuration is applied, the clock stays UTC.
an_unknown_zone_is_a_warning() {
    setup_device nozone
    wyr_region "$t/region" --timezone Mars/Olympus
    first_boot
    want "exit code ($(cat "$t/err"))" "$rc" 0
    grep -q 'Mars/Olympus' "$t/err" || fail "no warning: $(cat "$t/err")"
    want "uci calls" "$(cat "$t/uci.log")" ""
    want_empty_region
}

for test in applies_all_files setup_is_0600 only_the_config first_boot_twice \
    empty_region_exits_3 half_applied_is_applied_again a_power_loss_after_the_wipe a_flipped_byte_applies_nothing \
    a_bad_member_name_applies_nothing a_link_applies_nothing a_bad_region_applies_nothing \
    bad_content_applies_nothing an_unknown_zone_is_a_warning; do
    failed=0
    $test
    if [ "$failed" -eq 0 ]; then
        echo "ok   $test"
    else
        echo "FAIL $test"
        failures="${failures:-} $test"
    fi
done
if [ -n "${failures:-}" ]; then
    echo "failed:$failures" >&2
    exit 1
fi
echo "all tests passed ($SH${BB:+, $BB applets})"
