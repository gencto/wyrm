#!/bin/sh
# The first boot of a WYRM board image (ADR 0051 §4, "On the device").
#
# Reads the config region of the image, checks it, puts its files in place and wipes it.
# The region is what the crate `wyrm-image` writes (`wyr image build`):
#
#   offset  size  content
#        0     8  magic: "WYRMCFG1" (a configuration) or "WYRMCFG0" (empty)
#        8     8  payload length, u64 little-endian
#       16    32  SHA-256 of the payload
#       48     n  payload: a ustar archive of regular files
#     48+n     …  zeros, to 4 MiB
#
# usage: first-boot.sh                                  on the device
#        first-boot.sh <config_dev> <stage_dir> <etc_dir>   (tests)
#
# Without arguments the region is partition `config_part` of /etc/wyrm/image.json on the
# disk of the root file system (else the device `config_dev` of that file), the
# staging directory is /tmp/wyrm-first-boot (RAM) and the files go below /etc.
#
# Exit codes:
#   0  applied: every file is in place, the region is wiped, the marker is written
#   3  the region is empty: nothing to do, nothing changed (but when a first boot lost
#      power between its wipe and its marker: the wipe is done again, the marker written)
#   4  refused: the region is damaged or holds what is not allowed (also keys for an
#      image without an SSH server); nothing was applied
#   5  not finished: a file could not be put, SSH could not be set up for the keys or
#      the region could not be wiped; the region is kept and the next boot applies it again
#
# Applying is safe to repeat. A file is written beside its place and renamed over it, and
# the region is wiped only when every file is in place, so a power loss at any moment
# leaves a region that the next boot applies as a whole. Nothing of the archive is
# trusted: names are checked before it is unpacked, it is unpacked only into the staging
# directory, links are refused, and every file is copied into a new file with the mode
# this script gives it.
#
# The broker runs as the user `wyrm`. What it reads is given to the group `wyrm`
# (`wyrmd.json5` and the setup hash 0640 root:wyrm), and the setup hash lies in a
# directory that group may write, because the broker removes the file when it has the
# hash. The paths are those of the crate wyrm-image (`SETUP_FILE`, `SEED_DIR`).
#
# What is checked of the files is what the crate wyrm-image checks before it writes a
# region (`ConfigFiles::check_device`): the site (site.sh), the time zone (TZ_CHARS) and
# the NTP servers (NTP_CHARS, NTP_MAX). The crate's tests read these lines.
#
# Environment (tests): WYRM_UCI (the `uci` to call), WYRM_SEED_DIR, WYRM_ZONEINFO,
# WYRM_IMAGE_JSON, WYRM_DISK_SH, WYRM_SITE_SH, WYRM_GROUP (the broker's group; empty:
# files keep their group).

set -u
umask 077
LC_ALL=C
export LC_ALL

REGION_SIZE=4194304
HEADER_SIZE=48
MAX_PAYLOAD=$((REGION_SIZE - HEADER_SIZE))
MAGIC_FULL=5759524d43464731  # WYRMCFG1
MAGIC_EMPTY=5759524d43464730 # WYRMCFG0
NAMES="wyrmd.json5, network, seed.json, setup, authorized_keys, timezone, ntp"
# a time zone: one IANA name of these characters, not starting with `/`, without `..`
TZ_CHARS='A-Za-z0-9_+/-'
# an NTP server: a host name or an address (IPv6 without brackets), not starting with `-`
NTP_CHARS='A-Za-z0-9.:_-'
NTP_MAX=16
DOCS=https://wyrm.gencto.uk/docs/operations.html

UCI=${WYRM_UCI:-uci}
SEED_DIR=${WYRM_SEED_DIR:-/usr/share/wyrm/seed}
ZONEINFO=${WYRM_ZONEINFO:-/usr/share/zoneinfo}
IMAGE_JSON=${WYRM_IMAGE_JSON:-/etc/wyrm/image.json}
DISK_SH=${WYRM_DISK_SH:-/usr/libexec/wyrm/disk.sh}
# a command, split into its words where it is called
SITE_SH=${WYRM_SITE_SH:-/usr/libexec/wyrm/site.sh}
GROUP=${WYRM_GROUP-wyrm}

say() { echo "wyrm first boot: $*" >&2; }

stage=
cleanup() {
    if [ -n "$stage" ]; then
        rm -rf "$stage"
    fi
}
refuse() {
    say "$*"
    say "nothing was applied"
    cleanup
    exit 4
}
unfinished() {
    say "$*"
    say "the config region is kept: the next boot applies it again"
    cleanup
    exit 5
}

case $# in
0)
    # the partition of the image's record on the disk the root file system is on (a card,
    # a USB stick, an NVMe disk); the path of the record where that disk cannot be told
    dev=
    part=$(jsonfilter -i "$IMAGE_JSON" -e '@.config_part' 2> /dev/null) || part=
    if [ -n "$part" ]; then
        dev=$($DISK_SH part "$part" 2> /dev/null) || dev=
    fi
    if [ -z "$dev" ]; then
        dev=$(jsonfilter -i "$IMAGE_JSON" -e '@.config_dev' 2> /dev/null) || dev=
    fi
    stage_dir=/tmp/wyrm-first-boot
    etc=/etc
    [ -n "$dev" ] || refuse "$IMAGE_JSON names no config region"
    ;;
3)
    dev=$1
    stage_dir=$2
    etc=$3
    ;;
*)
    echo "usage: first-boot.sh [<config_dev> <stage_dir> <etc_dir>]" >&2
    exit 2
    ;;
esac
case $stage_dir in
'' | /) refuse "no staging directory" ;;
esac
marker=$etc/wyrm/.first-boot-done
# written when every file is in place, before the wipe: an empty region beside it is a
# first boot that lost power between the wipe and the marker, not an image without a
# configuration
applied=$etc/wyrm/.first-boot-applied

# range OFFSET LENGTH: these bytes of the region, to stdout. busybox `dd` counts in
# blocks, so the part before a 4096-byte boundary and the part after the last whole
# block are read byte by byte and the rest in blocks.
range() {
    r_off=$1
    r_len=$2
    r_head=$(((4096 - r_off % 4096) % 4096))
    if [ "$r_head" -gt "$r_len" ]; then
        r_head=$r_len
    fi
    if [ "$r_head" -gt 0 ]; then
        dd if="$dev" bs=1 skip="$r_off" count="$r_head" 2> /dev/null
    fi
    r_off=$((r_off + r_head))
    r_len=$((r_len - r_head))
    r_blocks=$((r_len / 4096))
    if [ "$r_blocks" -gt 0 ]; then
        dd if="$dev" bs=4096 skip=$((r_off / 4096)) count="$r_blocks" 2> /dev/null
    fi
    r_off=$((r_off + r_blocks * 4096))
    r_len=$((r_len - r_blocks * 4096))
    if [ "$r_len" -gt 0 ]; then
        dd if="$dev" bs=1 skip="$r_off" count="$r_len" 2> /dev/null
    fi
}
hex() { hexdump -v -e '1/1 "%02x"'; }
count() { wc -c | tr -d ' '; }
size_of() { wc -c < "$1" | tr -d ' '; }
# what is shown of a name the archive gave
shown() { printf '%s' "$1" | tr -c 'A-Za-z0-9._/-' '?'; }
no_nul() { [ "$(tr -d '\000' < "$1" | count)" -eq "$(size_of "$1")" ]; }

# One write over the whole region: the empty magic and zeros. The setup hash is then on
# the medium only in its file, which the broker removes when it has taken it. The read
# back goes through the page cache: it shows that the write was taken, not what the
# medium holds; `sync` asks the kernel for that.
wipe() {
    {
        printf 'WYRMCFG0'
        dd if=/dev/zero bs=$((4096 - 8)) count=1 2> /dev/null
        dd if=/dev/zero bs=4096 count=$((REGION_SIZE / 4096 - 1)) 2> /dev/null
    } | dd of="$dev" bs=4096 conv=notrunc 2> /dev/null
    sync
    [ "$(range 0 8 | hex)" = "$MAGIC_EMPTY" ] &&
        [ "$(range 8 $((REGION_SIZE - 8)) | tr -d '\000' | count)" -eq 0 ]
}

# ---- 1. the region --------------------------------------------------------------------

if [ ! -b "$dev" ] && [ ! -f "$dev" ]; then
    refuse "no config region: $dev is no device"
fi
magic=$(range 0 8 | hex)
if [ "$magic" = "$MAGIC_EMPTY" ]; then
    # told by the magic alone: the rest of an empty region is not read
    if [ -e "$applied" ]; then
        if [ ! -e "$marker" ]; then
            # the wipe may have been cut after its first bytes: the magic is written
            # first, so the old payload can lie behind it. Wipe as a whole again.
            wipe || {
                say "the config region at $dev could not be wiped"
                exit 5
            }
            : > "$marker"
            sync
        fi
        say "the config region is empty: its configuration was applied before"
        exit 3
    fi
    say "the config region is empty: this image carries no configuration."
    say "The broker does not start and nothing listens on the network."
    say "Write a configuration into the base image and write the card again:"
    say "  wyr image build --image <base image> --index index.json --board <board> \\"
    say "      --config wyrmd.json5 --new-setup-code --out <image>"
    say "Guide: $DOCS (\"Board images\")"
    exit 3
fi
if [ "$magic" != "$MAGIC_FULL" ]; then
    refuse "no config region at $dev: neither WYRMCFG1 nor WYRMCFG0"
fi

# the length: eight bytes, the lowest first; a payload fits three of them
set -f
# shellcheck disable=SC2046 # eight numbers, split on purpose
set -- $(range 8 8 | hexdump -v -e '1/1 "%u "')
if [ $# -ne 8 ] || [ "$(($4 + $5 + $6 + $7 + $8))" -ne 0 ]; then
    refuse "the config region is damaged: its length does not fit the region"
fi
len=$(($1 + $2 * 256 + $3 * 65536))
if [ "$len" -gt "$MAX_PAYLOAD" ]; then
    refuse "the config region is damaged: its length does not fit the region"
fi
want_sum=$(range 16 32 | hex)

rm -rf "$stage_dir"
# a new directory of this run: `mkdir` fails when something is at the name again
mkdir -p "$(dirname "$stage_dir")" || refuse "cannot make $stage_dir"
mkdir "$stage_dir" || refuse "cannot make $stage_dir"
stage=$stage_dir
chmod 700 "$stage"
files=$stage/files
mkdir "$files"

range "$HEADER_SIZE" "$len" > "$stage/payload.tar"
if [ "$(size_of "$stage/payload.tar")" -ne "$len" ]; then
    refuse "the config region cannot be read from $dev"
fi
sum=$(sha256sum < "$stage/payload.tar" | cut -d' ' -f1)
if [ "$sum" != "$want_sum" ]; then
    refuse "the config region is damaged: the SHA-256 of its payload does not match"
fi
rest=$((REGION_SIZE - HEADER_SIZE - len))
if [ "$(range $((HEADER_SIZE + len)) "$rest" | tr -d '\000' | count)" -ne 0 ]; then
    refuse "the config region is damaged: bytes after its payload"
fi

# ---- 2. the archive -------------------------------------------------------------------

# names first: nothing is unpacked from an archive with a name outside the list
list=$(tar -tf "$stage/payload.tar" 2> /dev/null) || refuse "the config archive cannot be read"
seen=" "
old_ifs=$IFS
IFS='
'
for name in $list; do
    # the whole name, exactly: no pattern, no part of the list
    case $name in
    wyrmd.json5 | network | seed.json | setup | authorized_keys | timezone | ntp) ;;
    *) refuse "the config archive holds \`$(shown "$name")\`: only $NAMES are taken" ;;
    esac
    case $seen in
    *" $name "*) refuse "the config archive holds \`$name\` twice" ;;
    esac
    seen="$seen$name "
done
IFS=$old_ifs
case $seen in
*" wyrmd.json5 "*) ;;
*) refuse "the config archive holds no wyrmd.json5" ;;
esac

tar -xf "$stage/payload.tar" -C "$files" 2> /dev/null || refuse "the config archive cannot be unpacked"
rm -f "$stage/payload.tar"

# every listed name is now a regular file of its own: no symbolic link, no hard link
for name in $seen; do
    f=$files/$name
    if [ -L "$f" ] || [ ! -f "$f" ]; then
        refuse "\`$name\` of the config archive is no regular file"
    fi
    # shellcheck disable=SC2012,SC2046 # the link count is the second field of `ls -ln`
    set -- $(ls -ln "$f")
    if [ "$2" != 1 ]; then
        refuse "\`$name\` of the config archive is a link"
    fi
    no_nul "$f" || refuse "\`$name\` of the config archive is not text"
done
has() {
    case $seen in
    *" $1 "*) return 0 ;;
    esac
    return 1
}

[ -s "$files/wyrmd.json5" ] || refuse "wyrmd.json5 of the config archive is empty"
# the site names the broker's data on the data partition (data-part.sh): a site it does
# not take would start no broker after the region is wiped, so it is refused now
# shellcheck disable=SC2086 # $SITE_SH is a command and its words
$SITE_SH "$files/wyrmd.json5" > /dev/null ||
    refuse "wyrmd.json5 names no site this device takes: \`site: \"<name>\"\` once in its outermost object, 1 to 64 of A-Z a-z 0-9 _ . -, not starting with \`.\`"

if has setup; then
    # 64 hex digits and at most one newline
    size=$(size_of "$files/setup")
    hash=
    IFS= read -r hash < "$files/setup" || [ -n "$hash" ] || true
    if [ "$size" -ne 64 ] && [ "$size" -ne 65 ] || [ "${#hash}" -ne 64 ]; then
        refuse "\`setup\` is not the SHA-256 of a setup code (64 hex digits)"
    fi
    case $hash in
    *[!0-9a-fA-F]*) refuse "\`setup\` is not the SHA-256 of a setup code (64 hex digits)" ;;
    esac
fi

if has network; then
    $UCI -q -c "$files" show network > /dev/null 2>&1 ||
        refuse "\`network\` of the config archive is no UCI file"
fi

if has authorized_keys && [ -s "$files/authorized_keys" ]; then
    # keys need the SSH server of the image and the firewall rule the host role made:
    # told now, before anything is put, not after the person is locked out
    if ! $UCI -q get "dropbear.@dropbear[0]" > /dev/null 2>&1 ||
        ! $UCI -q get firewall.wyrm_ssh > /dev/null 2>&1; then
        refuse "the config archive holds authorized_keys, but this image has no SSH server"
    fi
fi

tz=
if has timezone; then
    IFS= read -r tz < "$files/timezone" || [ -n "$tz" ] || true
    size=$(size_of "$files/timezone")
    if [ "$size" -ne "${#tz}" ] && [ "$size" -ne $((${#tz} + 1)) ]; then
        refuse "\`timezone\` is not one IANA name"
    fi
    case $tz in
    '' | /* | *..* | *[!$TZ_CHARS]*) refuse "\`timezone\` is not one IANA name" ;;
    esac
fi

ntp=
if has ntp; then
    while IFS= read -r server || [ -n "$server" ]; do
        case $server in
        '' | -* | *[!$NTP_CHARS]*) refuse "\`ntp\` holds a line that is no host name or address" ;;
        esac
        ntp="$ntp $server"
    done < "$files/ntp"
    # shellcheck disable=SC2086 # the servers, split on purpose
    set -- $ntp
    [ $# -le "$NTP_MAX" ] || refuse "\`ntp\` holds more than $NTP_MAX servers"
fi

# ---- 3. apply -------------------------------------------------------------------------

# for_broker PATH: the group of the broker's user, when there is one. Never through a
# symbolic link.
for_broker() {
    [ -z "$GROUP" ] || chgrp -h "$GROUP" "$1"
}
# put NAME PLACE MODE [broker]: a new file beside the place, then one rename over it.
# Every place is in a directory only root writes while this runs (the setup directory is
# made new and opened to the broker's group after its file is in place). A directory at
# the place is refused: `mv` would move into it.
put() {
    p_dir=${2%/*}
    mkdir -p "$p_dir" || return 1
    if [ -d "$2" ] && [ ! -L "$2" ]; then
        return 1
    fi
    rm -f "$2.wyrm-new"
    cat "$files/$1" > "$2.wyrm-new" || return 1
    if [ "${4:-}" = broker ]; then
        for_broker "$2.wyrm-new" || return 1
    fi
    chmod "$3" "$2.wyrm-new" && mv -f "$2.wyrm-new" "$2" || return 1
    # the place is now the file this wrote, not a link to another
    [ -f "$2" ] && [ ! -L "$2" ]
}
warned=0
# a setting the device works without (the clock's zone, the NTP servers)
uci_do() {
    if ! $UCI -q "$@"; then
        say "warning: uci $* failed"
        warned=1
    fi
}
# a setting the person needs to get in: without it the region is kept
uci_must() {
    $UCI -q "$@" || unfinished "uci $* failed: SSH is not set up for the keys of the image"
}

# the broker's configuration goes last: until every other file is in place, a boot
# that cannot read the region again does not start a broker on half of a configuration
if has setup; then
    # The broker removes the file when it has the hash, so its group may write the
    # directory. Root never writes into a directory another user may write: whatever is
    # there goes (a link planted at the file's name would lead the write elsewhere), the
    # directory is made new and root's alone (umask 077), the file is put, and only then
    # the directory is opened to the group.
    setup_dir=$etc/wyrm/setup.d
    rm -rf "$setup_dir"
    mkdir "$setup_dir" || unfinished "cannot make $setup_dir"
    put setup "$setup_dir/setup" 640 broker || unfinished "cannot write $setup_dir/setup"
    for_broker "$setup_dir" || unfinished "cannot give $setup_dir to the group $GROUP"
    chmod 770 "$setup_dir" || unfinished "cannot open $setup_dir to the group $GROUP"
fi
if has seed.json; then
    put seed.json "$SEED_DIR/seed.json" 644 || unfinished "cannot write $SEED_DIR/seed.json"
fi
if has network; then
    put network "$etc/config/network" 600 || unfinished "cannot write $etc/config/network"
fi
if has authorized_keys && [ -s "$files/authorized_keys" ]; then
    # SSH is on only with keys, and then for keys only
    put authorized_keys "$etc/dropbear/authorized_keys" 600 ||
        unfinished "cannot write $etc/dropbear/authorized_keys"
    uci_must set "dropbear.@dropbear[0].enable=1"
    uci_must set "dropbear.@dropbear[0].PasswordAuth=off"
    uci_must set "dropbear.@dropbear[0].RootPasswordAuth=off"
    uci_must commit dropbear
    uci_must set firewall.wyrm_ssh.enabled=1
    uci_must commit firewall
fi
if [ -n "$tz" ]; then
    # OpenWrt wants the POSIX rule of the zone: it is the last line of the zone's file
    posix=
    if [ -f "$ZONEINFO/$tz" ]; then
        posix=$(tail -n 1 "$ZONEINFO/$tz" | tr -d '\000')
    fi
    case $posix in
    '' | *[!A-Za-z0-9\<\>+,./:-]*)
        say "warning: this image has no data for the time zone $tz: the clock stays UTC"
        tz=
        ;;
    esac
fi
if [ -n "$tz" ]; then
    uci_do set "system.@system[0].zonename=$tz"
    uci_do set "system.@system[0].timezone=$posix"
fi
if [ -n "$ntp" ]; then
    $UCI -q delete system.ntp.server > /dev/null 2>&1 || true
    for server in $ntp; do
        uci_do add_list "system.ntp.server=$server"
    done
    uci_do set system.ntp.enabled=1
fi
if [ -n "$tz$ntp" ]; then
    uci_do commit system
fi
put wyrmd.json5 "$etc/wyrm/wyrmd.json5" 640 broker || unfinished "cannot write $etc/wyrm/wyrmd.json5"
: > "$applied" || unfinished "cannot write $applied"
sync

# ---- 4. wipe --------------------------------------------------------------------------

wipe ||
    unfinished "the configuration is applied, but the config region at $dev could not be wiped"

: > "$marker"
sync
cleanup
if [ "$warned" -ne 0 ]; then
    say "the configuration is applied, with the warnings above"
else
    say "the configuration is applied"
fi
exit 0
