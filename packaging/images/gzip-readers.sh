#!/bin/sh
# Checks that the usual imagers read a published base image right (ADR 0051 §4).
#
#   gzip-readers.sh [--allow-missing] <image.img> <image.img.gz>
#
# First the form of the `.gz` (`size`, by Python's zlib): it is ONE gzip member, nothing
# after it, and its trailer (ISIZE, the last four bytes, little-endian) is the size of the
# image mod 2^32. Raspberry Pi Imager takes the size of a `.gz` image from the last four
# bytes of the file alone (`parseGz` of its `imagesizeparser.cpp`, rounded up by 4 GiB
# steps to the compressed size): a file of several members would be told the size of its
# last member, and a card smaller than that estimate is refused.
#
# Then each reader unpacks the `.gz`, and the SHA-256 of what it gives must be the raw
# image's:
#
#   gunzip    `gunzip -c`
#   bsdcat    libarchive, which Raspberry Pi Imager reads images with
#   python3   the `gzip` module of Python, as `bmaptool` is written in
#   node      `zlib.createGunzip()`, which balenaEtcher reads images with
#
# A reader that is not installed here runs in a throwaway container (alpine 3.24.4 with the
# reader from alpine's packages, or node 26.13.1 on alpine; both by digest), which gets the
# file on its standard input. A reader that can run neither way fails the check;
# `--allow-missing` passes over it instead, and says so (for a quick local run; CI never
# gives it).
#
# The form check runs as the readers do: here, or in the alpine container.
#
# Exit 0 when the form is right and every reader gave the image; 1 naming the form check
# or each reader that gave other bytes, failed or is missing.
#
# RUNTIME           docker (default) or podman
# READERS_CONTAINED  `yes`: every reader runs in its container, also one installed here

set -eu

ALPINE=alpine@sha256:f59abe656b692d901e184be3445e084786602108599d2a51d229c0f5a48c71bf
NODE=node@sha256:6bd9ab43c0ec0190ca7b2d193906cb8b7edf6e7f4afa43ddeccd6452710bffb5
RUNTIME=${RUNTIME:-docker}
CONTAINED=${READERS_CONTAINED:-no}

say() { echo "gzip-readers: $*" >&2; }

allow_missing=no
if [ "${1:-}" = --allow-missing ]; then
    allow_missing=yes
    shift
fi
if [ $# -ne 2 ] || [ ! -f "$1" ] || [ ! -f "$2" ]; then
    say "usage: gzip-readers.sh [--allow-missing] <image.img> <image.img.gz>"
    exit 2
fi
raw=$1
gz=$2

if command -v sha256sum > /dev/null 2>&1; then
    sha() { sha256sum | cut -d' ' -f1; }
elif command -v shasum > /dev/null 2>&1; then
    sha() { shasum -a 256 | cut -d' ' -f1; }
else
    say "neither sha256sum nor shasum is installed"
    exit 2
fi

tmp=$(mktemp -d "${TMPDIR:-/tmp}/gzip-readers.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
trap 'exit 1' INT TERM

# The programs of the readers. Each reads the `.gz` on its standard input and writes the
# image on its standard output; nothing else goes to standard output.
PY='import gzip, shutil, sys
shutil.copyfileobj(gzip.GzipFile(fileobj=sys.stdin.buffer, mode="rb"), sys.stdout.buffer, 1 << 20)'
JS='process.stdin.pipe(require("zlib").createGunzip()).pipe(process.stdout)'
# The form: the `.gz` on standard input, the image's size in RAW_SIZE; a sentence on
# standard error and exit 1 when it is not one member with the image's ISIZE.
FORM='import os, sys, zlib
want = int(os.environ["RAW_SIZE"])
d = zlib.decompressobj(31)
f = sys.stdin.buffer
last = b""
while not d.eof:
    chunk = f.read(1 << 20)
    if not chunk:
        sys.exit("the file ends inside its first gzip member")
    last = (last + chunk)[-4:]
    while chunk and not d.eof:
        try:
            d.decompress(chunk, 1 << 24)
        except zlib.error as e:
            sys.exit(f"the gzip is damaged ({e}): its CRC or its ISIZE is not the one of its data")
        chunk = d.unconsumed_tail
if d.unused_data or f.read(1):
    sys.exit("bytes follow the first gzip member (another member): an imager that takes the size from the last four bytes is told another size")
isize = int.from_bytes(last, "little")
if isize != want % (1 << 32):
    sys.exit(f"the trailer says {isize} bytes (ISIZE); the image has {want}, {want % (1 << 32)} mod 2^32")'

# local <reader>: the reader on this host
local_reader() {
    case $1 in
    gunzip) gunzip -c ;;
    bsdcat) bsdcat ;;
    python3) python3 -I -c "$PY" ;;
    node) node -e "$JS" ;;
    size) python3 -I -c "$FORM" ;;
    esac
}

# contained <reader>: the reader in a throwaway container; the package manager's output
# goes to standard error
contained_reader() {
    # shellcheck disable=SC2016 # $PY, $JS and $FORM are expanded by the container's shell
    case $1 in
    gunzip) "$RUNTIME" run --rm -i "$ALPINE" sh -c 'apk add -q --no-cache gzip >&2 && gunzip -c' ;;
    bsdcat) "$RUNTIME" run --rm -i "$ALPINE" sh -c 'apk add -q --no-cache libarchive-tools >&2 && bsdcat' ;;
    python3) "$RUNTIME" run --rm -i -e PY="$PY" "$ALPINE" sh -c 'apk add -q --no-cache python3 >&2 && python3 -I -c "$PY"' ;;
    node) "$RUNTIME" run --rm -i -e JS="$JS" "$NODE" sh -c 'node -e "$JS"' ;;
    size) "$RUNTIME" run --rm -i -e FORM="$FORM" -e RAW_SIZE "$ALPINE" sh -c 'apk add -q --no-cache python3 >&2 && python3 -I -c "$FORM"' ;;
    esac
}

# runner <reader> <program>: sets `how` and `where` for a reader that runs here (as
# <program>) or in its container; returns 1 when it can run neither way
runner() {
    if [ "$CONTAINED" != yes ] && command -v "$2" > /dev/null 2>&1; then
        how=local_reader
        where=here
    elif command -v "$RUNTIME" > /dev/null 2>&1 && "$RUNTIME" info > /dev/null 2>&1; then
        how=contained_reader
        where="in a container ($RUNTIME)"
    else
        say "MISSING $1: $2 is not installed, and no container runtime ($RUNTIME)"
        return 1
    fi
}

want=$(sha < "$raw")
RAW_SIZE=$(wc -c < "$raw" | tr -d ' ')
export RAW_SIZE
say "the image $(basename "$raw"): $RAW_SIZE bytes, sha256 $want"
bad=''
missing=''
if runner size python3; then
    if "$how" size < "$gz"; then
        say "ok size ($where): one gzip member, its trailer gives the image's size"
    else
        say "FAIL size ($where): the gzip is not one member with the image's size in its trailer"
        bad="$bad size"
    fi
else
    missing="$missing size"
fi
for reader in gunzip bsdcat python3 node; do
    if ! runner "$reader" "$reader"; then
        missing="$missing $reader"
        continue
    fi
    rm -f "$tmp/status"
    got=$( (
        status=0
        "$how" "$reader" < "$gz" || status=$?
        echo "$status" > "$tmp/status"
    ) | sha)
    status=$(cat "$tmp/status" 2> /dev/null || echo '?')
    if [ "$status" != 0 ]; then
        say "FAIL $reader ($where): it ended with status $status"
        bad="$bad $reader"
    elif [ "$got" != "$want" ]; then
        say "FAIL $reader ($where): sha256 $got, not the image's"
        bad="$bad $reader"
    else
        say "ok $reader ($where)"
    fi
done

if [ -n "$bad" ]; then
    say "these checks fail:$bad"
fi
if [ -n "$missing" ]; then
    if [ "$allow_missing" = yes ]; then
        say "NOT CHECKED (--allow-missing):$missing"
    else
        say "these checks did not run:$missing"
        bad="$bad$missing"
    fi
fi
[ -z "$bad" ] || exit 1
if [ -n "$missing" ]; then
    say "every check that ran passes"
else
    say "one gzip member with the image's size; every reader gives the image"
fi
