#!/bin/sh
# Checks the partition table of a base image with tools that are not ours: `sfdisk -V`
# and, for a GPT, `sgdisk -v`, in a throwaway container. `wyr image base` edits the table
# itself (tools/wyr/src/image_part.rs); this is the second opinion.
#
#   verify-table.sh <image> [--hybrid-mbr]
#
# It also wants the config partition: 8192 sectors, of the type `wyr` gives it, starting
# with `WYRMCFG0` or `WYRMCFG1`.
#
# --hybrid-mbr  the image of a board whose boot ROM reads the MBR (mediatek/filogic):
#               OpenWrt writes a hybrid MBR there, and `sgdisk -v` counts its two
#               overlapping entries as one problem. With this option that one problem,
#               and no other, is accepted.
#
# The container gets one capability, DAC_READ_SEARCH: an assembled image is its owner's
# alone (0600, `wyr image build`), and root without capabilities cannot read it through
# the read-only mount (Linux; Docker Desktop's file sharing does not show this).
#
# RUNTIME   docker (default) or podman
# The container is alpine by digest; it installs `sfdisk` and `sgdisk` from alpine's
# packages at each run (a check, not a build: nothing of it goes into an image).

set -eu

IMAGE=alpine@sha256:49340b346798875b5592e5d420241f2f9cfba5f47e62ebb1446a1b34734e898f
RUNTIME=${RUNTIME:-docker}

if [ "${1:-}" != --inside ]; then
    if [ $# -lt 1 ] || [ ! -f "$1" ]; then
        echo "usage: verify-table.sh <image> [--hybrid-mbr]" >&2
        exit 2
    fi
    dir=$(cd "$(dirname "$1")" && pwd)
    self=$(cd "$(dirname "$0")" && pwd)/verify-table.sh
    exec "$RUNTIME" run --rm --cap-drop ALL --cap-add DAC_READ_SEARCH \
        --security-opt no-new-privileges \
        -v "$dir":/image:ro -v "$self":/verify-table.sh:ro "$IMAGE" \
        sh /verify-table.sh --inside "/image/$(basename "$1")" "${2:-}"
fi

img=$2
hybrid=${3:-}
apk add -q sfdisk sgdisk > /dev/null
fail() {
    echo "verify-table: $*" >&2
    exit 1
}

[ -r "$img" ] || fail "cannot read $img in the container"
table=$(sfdisk -d "$img") || fail "sfdisk reads no partition table"
echo "$table"
label=$(echo "$table" | sed -n 's/^label: //p')
sfdisk -V "$img" || fail "sfdisk -V finds an error"
case $label in
dos)
    type='type=da'
    ;;
gpt)
    type='type=8DA63339-0007-60C0-C436-083AC8230908'
    out=$(sgdisk -v "$img" 2>&1) || true
    echo "$out"
    case $out in
    *'No problems found'*) ;;
    *'Identified 1 problems'*)
        if [ "$hybrid" != --hybrid-mbr ] ||
            ! echo "$out" | grep -q '^Problem: MBR partitions .* overlap'; then
            fail "sgdisk -v finds a problem"
        fi
        echo "verify-table: accepted: the overlap is OpenWrt's hybrid MBR"
        ;;
    *) fail "sgdisk -v finds problems" ;;
    esac
    ;;
*) fail "the table is neither MBR nor GPT" ;;
esac

line=$(echo "$table" | grep "size= *8192, $type" || true)
[ "$(echo "$line" | grep -c .)" -eq 1 ] || fail "not exactly one config partition of 8192 sectors ($type)"
start=$(echo "$line" | sed -n 's/.*start= *\([0-9]*\),.*/\1/p')
magic=$(dd if="$img" bs=512 skip="$start" count=1 2> /dev/null | head -c 8)
case $magic in
WYRMCFG0 | WYRMCFG1) ;;
*) fail "the config partition at sector $start does not start with WYRMCFG0 or WYRMCFG1" ;;
esac
echo "verify-table: ok: $label, the config partition starts at sector $start (byte $((start * 512))), $magic"
