#!/bin/sh
# The base image of one board, made inside the build container (ADR 0051 §2, §4).
# `wyr image base` runs this script; it is not run by hand.
#
#   build.sh <archive url> <sha256> <image file> <make arguments>...
#
# Mounted by the caller:
#   /cache          the ImageBuilder archives, kept between runs
#   /work/overlay   the files of the image (the ImageBuilder's FILES), read only here
#   /work/out       what this script leaves: base.img (the image, unpacked) and manifest
#                   (the packages in it)
#
# Steps:
#   1. the ImageBuilder archive of the pinned OpenWrt release: downloaded when the cache
#      has none, and used only when its SHA-256 is the one of boards.json
#   2. `make image` with the arguments of the caller (PROFILE, PACKAGES, FILES,
#      ROOTFS_PARTSIZE)
#
# The config region is added to base.img by the caller (tools/wyr/src/image_part.rs): the
# container is OpenWrt's own build worker, which has no tool for partition tables.
# Nothing here needs root or a capability.

set -eu
umask 022

say() { echo "build.sh: $*" >&2; }
die() {
    say "$*"
    exit 1
}

[ $# -ge 3 ] || die "usage: build.sh <archive url> <sha256> <image file> <make arguments>..."
url=$1
sha=$2
image=$3
shift 3

out=/work/out
if [ ! -d /work/overlay ] || [ ! -d "$out" ] || [ ! -d /cache ]; then
    die "/work/overlay, /work/out and /cache must be mounted"
fi
# the ImageBuilder and its tools write below $HOME and $TMPDIR
tmp=$(mktemp -d /tmp/wyrm-image.XXXXXX)
HOME=$tmp/home
TMPDIR=$tmp/tmp
export HOME TMPDIR
mkdir -p "$HOME" "$TMPDIR"

# ---- 1. the ImageBuilder ---------------------------------------------------------------

archive=/cache/${url##*/}
sum_of() { sha256sum "$1" | cut -d' ' -f1; }
if [ -f "$archive" ] && [ "$(sum_of "$archive")" != "$sha" ]; then
    say "the cached $archive is not the pinned archive: it is downloaded again"
    rm -f "$archive"
fi
if [ ! -f "$archive" ]; then
    say "downloading $url"
    part=$archive.part.$$
    rm -f "$part"
    if command -v curl > /dev/null 2>&1; then
        curl -fL --retry 3 -o "$part" "$url" || die "cannot download $url"
    else
        wget -q -O "$part" "$url" || die "cannot download $url"
    fi
    if [ "$(sum_of "$part")" != "$sha" ]; then
        rm -f "$part"
        die "the SHA-256 of $url is not $sha: nothing of it is used"
    fi
    mv -f "$part" "$archive"
fi

ib=$tmp/imagebuilder
mkdir "$ib"
say "unpacking the ImageBuilder"
tar --zstd -xf "$archive" -C "$ib" --strip-components=1

# The packages of the release are not pinned by a hash: the ImageBuilder downloads them
# from the feeds its `repositories` file names and `apk` checks each index against the
# keys of the archive (which is pinned). That check must be on.
grep -qx 'CONFIG_SIGNATURE_CHECK=y' "$ib/.config" ||
    die "this ImageBuilder does not check the signatures of its package feeds"
keys=$(cd "$ib/keys" && echo *)
say "apk checks the feeds of $(sed -n 's|^\(https://[^/]*/releases/[^/]*\)/.*|\1|p' "$ib/repositories" | sort -u | tr '\n' ' ')against the keys of the archive: $keys (CONFIG_SIGNATURE_CHECK=y)"

# ---- 2. the image ----------------------------------------------------------------------

bin=$tmp/bin
say "make image $*"
make -C "$ib" image "$@" FILES=/work/overlay BIN_DIR="$bin" || die "the ImageBuilder failed"
[ -f "$bin/$image" ] || {
    ls -l "$bin" >&2
    die "the ImageBuilder made no $image"
}
img=$out/base.img
# OpenWrt appends its metadata after the gzip stream of some images: gzip then unpacks
# the image, warns about what follows and exits 2
rc=0
gzip -dc "$bin/$image" > "$img" 2> "$tmp/gzip.err" || rc=$?
if [ "$rc" -ne 0 ] && { [ "$rc" -ne 2 ] || ! grep -q 'trailing garbage' "$tmp/gzip.err"; }; then
    cat "$tmp/gzip.err" >&2
    die "cannot unpack $image"
fi
# the list of packages with their versions: its hash goes into the index, so an image
# without one is not published
set -- "$bin"/*.manifest
[ -f "$1" ] || die "the ImageBuilder left no *.manifest in $bin"
cat "$@" > "$out/manifest" || die "cannot copy the manifest"
[ -s "$out/manifest" ] || die "the manifest of the ImageBuilder is empty"

say "the image is $img"
rm -rf "$tmp"
