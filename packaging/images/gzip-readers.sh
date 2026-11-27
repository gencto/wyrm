#!/bin/sh
# Checks that the gzip readers of the usual imagers read a published base image whole
# (ADR 0051 §4). `wyr image base` writes the `.img.gz` as three gzip members (head, config
# region, tail), so that the image builder page can put a member of its own region in the
# middle; a reader that stops after the first member would write only the head to the card.
#
#   gzip-readers.sh [--allow-missing] <image.img> <image.img.gz>
#
# Each reader unpacks the `.gz`, and the SHA-256 of what it gives must be the raw image's:
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
# Exit 0 when every reader gave the image; 1 naming each reader that gave other bytes,
# failed or is missing.
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

# local <reader>: the reader on this host
local_reader() {
    case $1 in
    gunzip) gunzip -c ;;
    bsdcat) bsdcat ;;
    python3) python3 -I -c "$PY" ;;
    node) node -e "$JS" ;;
    esac
}

# contained <reader>: the reader in a throwaway container; the package manager's output
# goes to standard error
contained_reader() {
    # shellcheck disable=SC2016 # $PY and $JS are expanded by the container's shell
    case $1 in
    gunzip) "$RUNTIME" run --rm -i "$ALPINE" sh -c 'apk add -q --no-cache gzip >&2 && gunzip -c' ;;
    bsdcat) "$RUNTIME" run --rm -i "$ALPINE" sh -c 'apk add -q --no-cache libarchive-tools >&2 && bsdcat' ;;
    python3) "$RUNTIME" run --rm -i -e PY="$PY" "$ALPINE" sh -c 'apk add -q --no-cache python3 >&2 && python3 -I -c "$PY"' ;;
    node) "$RUNTIME" run --rm -i -e JS="$JS" "$NODE" sh -c 'node -e "$JS"' ;;
    esac
}

want=$(sha < "$raw")
say "the image $(basename "$raw"): sha256 $want"
bad=''
missing=''
for reader in gunzip bsdcat python3 node; do
    if [ "$CONTAINED" != yes ] && command -v "$reader" > /dev/null 2>&1; then
        how=local_reader
        where=here
    elif command -v "$RUNTIME" > /dev/null 2>&1 && "$RUNTIME" info > /dev/null 2>&1; then
        how=contained_reader
        where="in a container ($RUNTIME)"
    else
        say "MISSING $reader: not installed, and no container runtime ($RUNTIME)"
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
    say "these readers do not give the image:$bad"
fi
if [ -n "$missing" ]; then
    if [ "$allow_missing" = yes ]; then
        say "NOT CHECKED (--allow-missing):$missing"
    else
        say "these readers did not run:$missing"
        bad="$bad$missing"
    fi
fi
[ -z "$bad" ] || exit 1
if [ -n "$missing" ]; then
    say "every reader that ran gives the image"
else
    say "every reader gives the image"
fi
