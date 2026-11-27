#!/bin/sh
# Tests of the data partition script, the disk finder and the site reader (ADR 0051 §3).
#
#   SH=dash packaging/openwrt/tests/data_part.sh                 # a developer's machine
#   SH="busybox sh" BB=busybox packaging/openwrt/tests/data_part.sh   # CI, as on the device
#
# SH   the shell that runs the scripts (default: sh)
# BB   empty: the system's tools; `busybox`: busybox's applets in front of PATH
#
# The scripts decide; the tools that touch a disk (sfdisk, partx, blkid, mkfs.ext4,
# tune2fs, e2fsck, mount) are stand-ins here that record how they were called and act on
# a device made of files: a tree like /sys, a directory like /dev. What the real tools
# do on a real disk is tried in an image that boots (packaging/images/README.md).

set -u
LC_ALL=C
export LC_ALL

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../.." && pwd)
lib=$root/packaging/openwrt/wyrmd/files/usr/libexec/wyrm
SH=${SH:-sh}
BB=${BB:-}

work=$(mktemp -d "${TMPDIR:-/tmp}/wyrm-data-part.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT

if [ -n "$BB" ]; then
    bb=$(command -v "$BB") || { echo "no $BB" >&2; exit 1; }
    mkdir "$work/bin"
    for applet in awk cat chmod chown cmp cut dd grep head hexdump ln ls mkdir mktemp mv rm \
        sed sleep sort sync tr; do
        "$bb" --list | grep -qx "$applet" || { echo "$BB has no $applet" >&2; exit 1; }
        ln -s "$bb" "$work/bin/$applet"
    done
    PATH=$work/bin:$PATH
    export PATH
fi

# One stand-in for every disk tool, told apart by its name. It records the call in
# $TOOL_LOG and acts on the device of files below $T.
mkdir "$work/tools"
cat > "$work/tools/tool" <<'EOF'
#!/bin/sh
name=${0##*/}
echo "$name $*" >> "$TOOL_LOG"
case $name in
sfdisk)
    case " $* " in
    *" -d "*)
        echo "label: $TABLE"
        ;;
    *" --append "*)
        cat >> "$T/appended"
        # as sfdisk does on a GPT: the first sector becomes a protective MBR
        if [ "$TABLE" = gpt ]; then
            printf 'PROTECTIVE' | dd of="$T/dev/vda" bs=1 seek=446 conv=notrunc 2> /dev/null
        fi
        [ -z "${SFDISK_FAIL:-}" ] || exit 1
        ;;
    esac
    ;;
partx)
    # the kernel learns of the partition the table got
    start=$(sed -n 's/^start=\([0-9]*\),.*/\1/p' "$T/appended")
    size=$(sed -n 's/^start=[0-9]*, size=\([0-9]*\),.*/\1/p' "$T/appended")
    mkdir -p "$T/sys/block/vda/vda4"
    echo 4 > "$T/sys/block/vda/vda4/partition"
    echo "${PARTX_START:-$start}" > "$T/sys/block/vda/vda4/start"
    echo "$size" > "$T/sys/block/vda/vda4/size"
    ln -s ../../block/vda/vda4 "$T/sys/class/block/vda4"
    : > "$T/dev/vda4"
    ;;
blkid)
    for last; do :; done
    name=${last##*/}
    # IMAGE_END: an image of that many sectors was written over the card since the file
    # system was made; what lay before its end is gone
    start=$(cat "$T/sys/block/vda/$name/start" 2> /dev/null) || start=
    if [ -n "${IMAGE_END:-}" ] && [ -n "$start" ] && [ "$start" -lt "$IMAGE_END" ]; then
        exit 2
    fi
    cat "$T/label.$name" 2> /dev/null
    ;;
mkfs.ext4)
    [ -z "${MKFS_FAIL:-}" ] || exit 1
    for last; do :; done
    while [ $# -gt 1 ]; do
        [ "$1" != -L ] || echo "$2" > "$T/label.${last##*/}"
        shift
    done
    ;;
tune2fs)
    echo "$2" > "$T/label.${3##*/}"
    ;;
e2fsck)
    exit "${FSCK_RC:-0}"
    ;;
mount)
    for last; do :; done
    if [ "$1 $2" = "-o bind" ]; then
        # a bind mount shows the device of the file system it comes from
        dev=$(awk -v at="${3%/*}" '$2 == at { print $1 }' "$T/mounts")
        echo "$dev $last ext4 rw 0 0" >> "$T/mounts"
    else
        shift 4
        echo "$1 $last ext4 rw 0 0" >> "$T/mounts"
    fi
    ;;
umount)
    awk -v at="$1" '$2 != at' "$T/mounts" > "$T/mounts.new" && mv "$T/mounts.new" "$T/mounts"
    ;;
esac
exit 0
EOF
chmod 755 "$work/tools/tool"
for name in sfdisk partx blkid mkfs.ext4 tune2fs e2fsck mount umount; do
    ln -s tool "$work/tools/$name"
done

CONFIG='{ site: "plant", gateway: { listen: "0.0.0.0:8445" } }'
# the broker's user: here the one who runs the tests
OWNER="$(id -u):$(id -g)"

# A device after its first boot: the disk `vda` of 1 GiB with the root as partition 2 and
# the config region as partition 3, as `qemu-armsr` has them; no partition 4.
setup_device() {
    t=$work/t/$1
    mkdir -p "$t/sys/block/vda/vda2" "$t/sys/block/vda/vda3" "$t/sys/class/block" \
        "$t/sys/dev/block" "$t/dev" "$t/data" "$t/part" "$t/etc"
    echo 2097152 > "$t/sys/block/vda/size"
    echo 2 > "$t/sys/block/vda/vda2/partition"
    echo 3 > "$t/sys/block/vda/vda3/partition"
    echo 8192 > "$t/sys/block/vda/vda3/size"
    echo 788480 > "$t/sys/block/vda/vda3/start"
    ln -s ../../block/vda "$t/sys/class/block/vda"
    ln -s ../../block/vda/vda2 "$t/sys/class/block/vda2"
    ln -s ../../block/vda/vda3 "$t/sys/class/block/vda3"
    ln -s ../../block/vda/vda2 "$t/sys/dev/block/254:2"
    echo '20 1 254:2 / /rom ro,relatime - squashfs /dev/root ro' > "$t/mountinfo"
    echo '21 1 0:19 / / rw - overlay overlayfs:/overlay rw' >> "$t/mountinfo"
    # the first sector of a GPT disk: one entry of the type EE
    dd if=/dev/zero bs=512 count=1 2> /dev/null > "$t/dev/vda"
    printf '\356' | dd of="$t/dev/vda" bs=1 seek=450 conv=notrunc 2> /dev/null
    printf 'WYRMCFG0' > "$t/dev/vda3"
    printf '%s\n' "$CONFIG" > "$t/etc/wyrmd.json5"
    : > "$t/mounts"
    : > "$t/log"
    table=gpt
}

# a partition 4 that the table had before this boot
with_data_partition() {
    mkdir -p "$t/sys/block/vda/vda4"
    echo 4 > "$t/sys/block/vda/vda4/partition"
    echo 798720 > "$t/sys/block/vda/vda4/start"
    ln -s ../../block/vda/vda4 "$t/sys/class/block/vda4"
    : > "$t/dev/vda4"
}

# data_part: runs the script; its exit code in $rc, its messages in $t/err
data_part() {
    rc=0
    T=$t TOOL_LOG=$t/log TABLE=$table \
        WYRM_SYS=$t/sys WYRM_MOUNTINFO=$t/mountinfo WYRM_DEV=$t/dev WYRM_MOUNTS=$t/mounts \
        WYRM_DATA=$t/data WYRM_PART=$t/part WYRM_OWNER="$OWNER" WYRM_CONFIG=$t/etc/wyrmd.json5 WYRM_CONFIG_PART=3 WYRM_DATA_PART=4 \
        WYRM_DISK_SH="$SH $lib/disk.sh" WYRM_SITE_SH="$SH $lib/site.sh" \
        WYRM_SFDISK=$work/tools/sfdisk WYRM_PARTX=$work/tools/partx \
        WYRM_BLKID=$work/tools/blkid WYRM_MKFS=$work/tools/mkfs.ext4 \
        WYRM_TUNE2FS=$work/tools/tune2fs WYRM_FSCK=$work/tools/e2fsck \
        WYRM_MOUNT=$work/tools/mount WYRM_UMOUNT=$work/tools/umount \
        $SH "$lib/data-part.sh" 2> "$t/err" || rc=$?
}

failed=0
fail() {
    echo "  FAILED: $*" >&2
    failed=1
}
want() { # want WHAT GOT EXPECTED
    [ "$2" = "$3" ] || fail "$1: got \`$2\`, expected \`$3\`"
}
called() { grep -q -- "$1" "$t/log" || fail "no call \`$1\`: $(cat "$t/log")"; }
not_called() { ! grep -q -- "$1" "$t/log" || fail "a call \`$1\`: $(cat "$t/log")"; }
# nothing that changes a disk was called
untouched() {
    for call in '--append' '--relocate' '^partx' '^mkfs' '^tune2fs' '^mount'; do
        not_called "$call"
    done
    want "mounts" "$(cat "$t/mounts")" ""
    [ "$rc" -ne 0 ] || fail "exit 0"
    grep -q 'the broker is not started' "$t/err" || fail "no message: $(cat "$t/err")"
}

# end_ok SPARE: the appended entry ends on 1 MiB, 2048 sectors or more before the end of
# the disk and its SPARE sectors of a second table
end_ok() {
    e_start=$(sed -n 's/^start=\([0-9]*\),.*/\1/p' "$t/appended")
    e_size=$(sed -n 's/^start=[0-9]*, size=\([0-9]*\),.*/\1/p' "$t/appended")
    e_end=$((e_start + e_size))
    e_disk=$(cat "$t/sys/block/vda/size")
    [ $((e_end % 2048)) -eq 0 ] || fail "the end $e_end is not on 1 MiB"
    [ $((e_disk - e_end - $1)) -ge 2048 ] || fail "the end $e_end leaves less than 1 MiB before $e_disk"
}

# ---- the partition --------------------------------------------------------------------

a_new_card_gets_its_partition() {
    setup_device new
    data_part
    want "exit code ($(cat "$t/err"))" "$rc" 0
    # the second table moves to the end of the card, then the entry after the region
    called '^sfdisk --no-reread --no-tell-kernel --relocate gpt-bak-std .*/dev/vda$'
    called '^sfdisk --no-reread --no-tell-kernel --append .*/dev/vda$'
    want "the entry" "$(cat "$t/appended")" \
        'start=798720, size=1294336, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name="wyrm-data"'
    # the end: on a 1 MiB boundary, with at least 1 MiB unused after the second table
    # (34 sectors): imagers zero the last MiB of a drive
    end_ok 34
    called '^partx -a --nr 4 '
    # formatted under another label, named when mkfs has ended
    called '^mkfs.ext4 -q -F -L wyrm-new .*/dev/vda4$'
    called '^tune2fs -L wyrm-data .*/dev/vda4$'
    called '^blkid -p -s LABEL -o value .*/dev/vda4$'
    called '^e2fsck -p .*/dev/vda4$'
    called "^mount -t ext4 -o nosuid,nodev,noatime $t/dev/vda4 $t/part\$"
    called "^mount -o bind $t/part/broker $t/data\$"
    want "label" "$(cat "$t/label.vda4")" wyrm-data
    want ".site" "$(cat "$t/part/.site")" plant
    [ -d "$t/part/broker" ] || fail "no broker directory"
    want "mounts" "$(cat "$t/mounts")" "$t/dev/vda4 $t/part ext4 rw 0 0
$t/dev/vda4 $t/data ext4 rw 0 0"
    # the order: the label of the data comes after mkfs, the check before the mount, the
    # broker's directory is mounted last
    want "order" "$(grep -oE '^(mkfs.ext4|tune2fs|e2fsck|mount) (-t|-o bind)?' "$t/log" | tr ' ' _ | tr '\n' ' ')" \
        "mkfs.ext4_ tune2fs_ e2fsck_ mount_-t mount_-o_bind "
}

an_mbr_card_gets_a_primary_partition() {
    setup_device mbr
    table=dos
    dd if=/dev/zero bs=512 count=1 2> /dev/null > "$t/dev/vda"
    data_part
    want "exit code ($(cat "$t/err"))" "$rc" 0
    not_called '--relocate'
    want "the entry" "$(cat "$t/appended")" 'start=798720, size=1296384, type=83'
    end_ok 0
    called '^mount '
}

the_second_boot_formats_nothing() {
    setup_device second
    with_data_partition
    echo wyrm-data > "$t/label.vda4"
    # what the partition holds since the first boot
    mkdir "$t/part/broker"
    echo other > "$t/part/broker/kept"
    echo plant > "$t/part/.site"
    data_part
    want "exit code ($(cat "$t/err"))" "$rc" 0
    for call in '--append' '--relocate' '^partx' '^mkfs' '^tune2fs'; do
        not_called "$call"
    done
    called '^e2fsck -p '
    called '^mount '
    [ -f "$t/part/broker/kept" ] || fail "the data is gone"
}

a_card_written_again_keeps_its_data() {
    # the new image's table has no entry 4; the file system of the old one is still there.
    # The image was written whole: a GPT image ends 1 MiB after its config region (its
    # second table), and the file system must start beyond that
    setup_device again
    echo wyrm-data > "$t/label.vda4"
    IMAGE_END=$((788480 + 8192 + 2048))
    export IMAGE_END
    data_part
    unset IMAGE_END
    want "exit code ($(cat "$t/err"))" "$rc" 0
    called '--append'
    not_called '^mkfs'
    not_called '^tune2fs'
    called '^mount '
    grep -q 'it is kept' "$t/err" || fail "no message: $(cat "$t/err")"
}

a_partition_that_was_there_is_never_formatted() {
    for label in '' wyrm-new something; do
        setup_device "old-$label"
        with_data_partition
        [ -z "$label" ] || echo "$label" > "$t/label.vda4"
        data_part
        untouched
        grep -q 'never formatted' "$t/err" || fail "no message: $(cat "$t/err")"
    done
}

another_disk_is_not_touched() {
    # partition 3 is no config region: of another size, or without the magic
    setup_device size
    echo 16384 > "$t/sys/block/vda/vda3/size"
    data_part
    untouched
    setup_device magic
    printf 'hsqs\0\0\0\0' > "$t/dev/vda3"
    data_part
    untouched
    # no partition 3 at all
    setup_device none
    rm -rf "$t/sys/block/vda/vda3" "$t/sys/class/block/vda3"
    data_part
    untouched
    # the root file system is on no disk this script can name
    setup_device noroot
    echo '21 1 0:19 / / rw - overlay overlayfs:/overlay rw' > "$t/mountinfo"
    data_part
    untouched
    grep -q 'nothing is touched' "$t/err" || fail "no message: $(cat "$t/err")"
}

a_card_without_room_is_left_alone() {
    # the image fills the disk: 5 MiB after the config region, less than a data partition
    setup_device full
    echo $((798720 + 8192)) > "$t/sys/block/vda/size"
    data_part
    untouched
    grep -q 'no room' "$t/err" || fail "no message: $(cat "$t/err")"
}

a_failed_mkfs_leaves_no_data_label() {
    setup_device mkfs
    rc=0
    MKFS_FAIL=1
    export MKFS_FAIL
    data_part
    unset MKFS_FAIL
    [ "$rc" -ne 0 ] || fail "exit 0"
    not_called '^tune2fs'
    not_called '^mount'
    [ ! -e "$t/label.vda4" ] || fail "a label: $(cat "$t/label.vda4")"
    # the next boot finds an entry that was there and no data label: it formats nothing
    : > "$t/log"
    data_part
    untouched
}

a_file_system_with_errors_is_not_mounted() {
    setup_device fsck
    with_data_partition
    echo wyrm-data > "$t/label.vda4"
    FSCK_RC=4
    export FSCK_RC
    data_part
    unset FSCK_RC
    [ "$rc" -ne 0 ] || fail "exit 0"
    not_called '^mount'
    # errors that were corrected are no reason to stop
    setup_device fsck1
    with_data_partition
    echo wyrm-data > "$t/label.vda4"
    FSCK_RC=1
    export FSCK_RC
    data_part
    unset FSCK_RC
    want "exit code ($(cat "$t/err"))" "$rc" 0
}

a_partition_that_was_there_elsewhere_is_not_used() {
    # partition 4 of the table, not where this script puts it: not the image's
    setup_device elsewhere
    with_data_partition
    echo 999424 > "$t/sys/block/vda/vda4/start"
    echo wyrm-data > "$t/label.vda4"
    data_part
    untouched
    not_called '^e2fsck'
    not_called '^blkid'
    grep -q 'does not start at sector 798720' "$t/err" || fail "no message: $(cat "$t/err")"
}

a_partition_at_another_place_is_not_used() {
    setup_device place
    PARTX_START=999424
    export PARTX_START
    data_part
    unset PARTX_START
    [ "$rc" -ne 0 ] || fail "exit 0"
    not_called '^mkfs'
    not_called '^mount'
}

a_hybrid_mbr_is_put_back() {
    setup_device hybrid
    # mediatek/filogic: an entry of the boot loader beside the one of type EE
    printf '\203' | dd of="$t/dev/vda" bs=1 seek=466 conv=notrunc 2> /dev/null
    cp "$t/dev/vda" "$t/sector0"
    data_part
    want "exit code ($(cat "$t/err"))" "$rc" 0
    cmp -s "$t/dev/vda" "$t/sector0" || fail "the first sector changed"
    # a protective MBR is the tool's to write
    setup_device protective
    cp "$t/dev/vda" "$t/sector0"
    data_part
    ! cmp -s "$t/dev/vda" "$t/sector0" || fail "the stand-in did not write the first sector"
}

a_mounted_partition_is_not_mounted_again() {
    setup_device mounted
    with_data_partition
    echo wyrm-data > "$t/label.vda4"
    # a start after a stop: the partition and the broker's directory are mounted
    mkdir "$t/part/broker"
    echo plant > "$t/part/.site"
    printf '%s\n' "$t/dev/vda4 $t/part ext4 rw 0 0" "$t/dev/vda4 $t/data ext4 rw 0 0" > "$t/mounts"
    data_part
    want "exit code ($(cat "$t/err"))" "$rc" 0
    not_called '^mount -t'
    not_called '^e2fsck'
    # the bind mount is made again after the site rule
    called "^umount $t/data\$"
    called "^mount -o bind $t/part/broker $t/data\$"
    want ".site" "$(cat "$t/part/.site")" plant
    want "mounts" "$(cat "$t/mounts")" "$t/dev/vda4 $t/part ext4 rw 0 0
$t/dev/vda4 $t/data ext4 rw 0 0"
    # another device at the place: no broker
    setup_device foreign
    with_data_partition
    echo wyrm-data > "$t/label.vda4"
    echo "/dev/sdb1 $t/part ext4 rw 0 0" > "$t/mounts"
    data_part
    [ "$rc" -ne 0 ] || fail "exit 0"
    not_called '^mount'
}

# ---- the site rule --------------------------------------------------------------------

# site_rule: the rule alone on $t/part with the configuration $t/etc/wyrmd.json5
site_rule() {
    rc=0
    WYRM_SITE_SH="$SH $lib/site.sh" WYRM_OWNER="$OWNER" \
        $SH "$lib/data-part.sh" site "$t/part" "$t/etc/wyrmd.json5" 2> "$t/err" || rc=$?
}
# shellcheck disable=SC2012 # the names are the tests' own
entries() { ls -A "$1" | sort | tr '\n' ' '; }

the_same_site_keeps_its_data() {
    setup_device same
    site_rule
    want "exit code ($(cat "$t/err"))" "$rc" 0
    want ".site" "$(cat "$t/part/.site")" plant
    want "entries" "$(entries "$t/part")" ".site broker "
    mkdir -p "$t/part/broker/pki" "$t/part/lost+found"
    echo key > "$t/part/broker/pki/ca.key"
    echo secret > "$t/part/broker/.store_key"
    site_rule
    want "exit code" "$rc" 0
    want "entries" "$(entries "$t/part")" ".site broker lost+found "
    want "the data" "$(entries "$t/part/broker")" ".store_key pki "
    want "messages" "$(cat "$t/err")" ""
}

another_site_sets_the_old_data_aside() {
    setup_device other
    site_rule
    mkdir -p "$t/part/broker/pki" "$t/part/lost+found"
    echo key > "$t/part/broker/pki/ca.key"
    echo secret > "$t/part/broker/.store_key"
    printf '%s\n' '{ site: "mill" }' > "$t/etc/wyrmd.json5"
    site_rule
    want "exit code ($(cat "$t/err"))" "$rc" 0
    want "entries" "$(entries "$t/part")" ".replaced-plant-1 .site broker lost+found "
    want "set aside" "$(entries "$t/part/.replaced-plant-1")" ".store_key pki "
    want "the old key" "$(cat "$t/part/.replaced-plant-1/pki/ca.key")" key
    want "the new data" "$(entries "$t/part/broker")" ""
    want ".site" "$(cat "$t/part/.site")" mill
    grep -q 'kept in .*replaced-plant-1' "$t/err" || fail "no message: $(cat "$t/err")"
    # back to the first site: its old data is not merged in, the second site's goes aside
    echo flows > "$t/part/broker/flows.key"
    printf '%s\n' "$CONFIG" > "$t/etc/wyrmd.json5"
    site_rule
    want "entries" "$(entries "$t/part")" ".replaced-mill-1 .replaced-plant-1 .site broker lost+found "
    want "set aside" "$(entries "$t/part/.replaced-mill-1")" "flows.key "
    # and once more: a second directory of the site, the first one as it was
    printf '%s\n' '{ site: "mill" }' > "$t/etc/wyrmd.json5"
    site_rule
    want "entries" "$(entries "$t/part")" \
        ".replaced-mill-1 .replaced-plant-1 .replaced-plant-2 .site broker lost+found "
    want "the first" "$(entries "$t/part/.replaced-plant-1")" ".store_key pki "
}

data_without_a_name_is_set_aside() {
    # a `broker` without a `.site` this rule can read: no record says it is this site's
    setup_device unnamed
    mkdir -p "$t/part/broker/pki"
    site_rule
    want "exit code ($(cat "$t/err"))" "$rc" 0
    want "entries" "$(entries "$t/part")" ".replaced-unknown-1 .site broker "
    want "set aside" "$(entries "$t/part/.replaced-unknown-1")" "pki "
    want "the new data" "$(entries "$t/part/broker")" ""
    grep -q 'not recorded' "$t/err" || fail "no message: $(cat "$t/err")"
    # a site named `unknown` is a site like any other: an unreadable `.site` is not it
    for bad in '../x' '' 'two words'; do
        setup_device "unknown-$bad"
        printf '%s\n' '{ site: "unknown" }' > "$t/etc/wyrmd.json5"
        mkdir -p "$t/part/broker/pki"
        printf '%s\n' "$bad" > "$t/part/.site"
        site_rule
        want "exit code ($(cat "$t/err"))" "$rc" 0
        want "entries" "$(entries "$t/part")" ".replaced-unknown-1 .site broker "
        want ".site" "$(cat "$t/part/.site")" unknown
        # and its own data is kept
        mkdir "$t/part/broker/flows"
        site_rule
        want "entries" "$(entries "$t/part")" ".replaced-unknown-1 .site broker "
        want "kept" "$(entries "$t/part/broker")" "flows "
    done
}

the_broker_s_links_are_never_followed() {
    # the broker's user writes its own directory: links there, at the names a site change
    # meets, lead nowhere; root renames the directory as a whole and opens nothing in it
    setup_device link
    echo victim > "$t/victim"
    mkdir "$t/victimdir"
    echo inside > "$t/victimdir/file"
    mkdir "$t/part/broker"
    echo plant > "$t/part/.site"
    ln -s "$t/victim" "$t/part/broker/.site"
    ln -s "$t/victim" "$t/part/broker/.site.new"
    ln -s "$t/victimdir" "$t/part/broker/pki"
    ln -s "$t/victimdir" "$t/part/broker/.replaced-plant-1"
    ln -s / "$t/part/broker/root"
    printf '%s\n' '{ site: "mill" }' > "$t/etc/wyrmd.json5"
    site_rule
    want "exit code ($(cat "$t/err"))" "$rc" 0
    want "the victim" "$(cat "$t/victim")" victim
    want "the victim's directory" "$(entries "$t/victimdir")" "file "
    want "entries" "$(entries "$t/part")" ".replaced-plant-1 .site broker "
    # the links went aside as they were, still links
    want "set aside" "$(entries "$t/part/.replaced-plant-1")" ".replaced-plant-1 .site .site.new pki root "
    for name in .site .site.new pki root .replaced-plant-1; do
        [ -L "$t/part/.replaced-plant-1/$name" ] || fail "$name is no link"
    done
    want ".site" "$(cat "$t/part/.site")" mill
    if [ -L "$t/part/broker" ] || [ ! -d "$t/part/broker" ]; then
        fail "broker is no new directory"
    fi
    # a link at a name of the root-owned directory (nobody but root writes there) is no
    # directory of the broker: nothing is done through it
    setup_device link2
    echo victim > "$t/victim"
    ln -s "$t/victimdir" "$t/part/broker"
    site_rule
    [ "$rc" -ne 0 ] || fail "exit 0"
    [ ! -e "$t/part/.site" ] || fail "a .site: $(cat "$t/part/.site")"
    ln -s "$t/victim" "$t/part/.site"
    rm "$t/part/broker"
    site_rule
    want "exit code ($(cat "$t/err"))" "$rc" 0
    want "the victim" "$(cat "$t/victim")" victim
    [ ! -L "$t/part/.site" ] || fail ".site is still a link"
    want ".site" "$(cat "$t/part/.site")" plant
}

a_configuration_without_a_site_starts_no_broker() {
    setup_device nosite
    mkdir -p "$t/part/broker/pki"
    long=$(printf '%065d' 0)
    for config in '{ gateway: { site: "inner" } }' '{ site: 7 }' '{ site: "a/b" }' '{ site: "../x" }' '' \
        '{ site: ".plant" }' "{ site: \"$long\" }"; do
        printf '%s\n' "$config" > "$t/etc/wyrmd.json5"
        site_rule
        [ "$rc" -ne 0 ] || fail "exit 0 for \`$config\`"
        want "entries" "$(entries "$t/part")" "broker "
        want "the data" "$(entries "$t/part/broker")" "pki "
    done
}

# ---- the site reader and the disk finder ----------------------------------------------

site_of() {
    printf '%s\n' "$1" > "$work/site.json5"
    $SH "$lib/site.sh" "$work/site.json5"
}

the_site_is_the_key_of_the_outermost_object() {
    want "one line" "$(site_of '{ site: "plant", data_dir: "/srv/wyrm" }')" plant
    want "quoted key" "$(site_of '{ "data_dir": "/srv/wyrm", "site" : "plant-2" }')" plant-2
    want "single quotes" "$(site_of "{ 'site': 'plant_3' }")" plant_3
    want "lines" "$(site_of '{
  // site: "comment"
  /* site: "block",
     site: "comment" */
  listen: ["tcp/0.0.0.0:7447"],
  peers: { upstream: [{ site: "central", url: "quic/c:7449" }] },
  note: "site: \"text\"",
  site: "plant", // the name
}')" plant
    want "after an inner site" "$(site_of '{ upstream: { site: "central" }, site: "edge" }')" edge
    for none in '{ }' '{ upstream: { site: "central" } }' '{ site: 12 }' '{ site: true, x: "y" }' \
        '{ site: "pl\x61nt" }' '{ note: "site", x: "plant" }' '[ { site: "x" } ]' 'site: "x"'; do
        if out=$(site_of "$none"); then
            fail "a site \`$out\` in \`$none\`"
        fi
    done
    if $SH "$lib/site.sh" "$work/no-such-file" 2> /dev/null; then
        fail "a site of no file"
    fi
    # the rule of a name (wyrm-image `plain_site`), also for a name in a file
    want "64 characters" "$(site_of "{ site: \"$(printf '%064d' 0)\" }")" "$(printf '%064d' 0)"
    for name in plant Plant-2 a.b -x _ x. "$(printf '%064d' 0)"; do
        $SH "$lib/site.sh" --name "$name" || fail "the name \`$name\` is refused"
    done
    for name in '' .x . .. a/b 'a b' 'a;b' '~x' "$(printf '%065d' 0)"; do
        if $SH "$lib/site.sh" --name "$name"; then fail "the name \`$name\` is taken"; fi
        if out=$(site_of "{ site: \"$name\" }"); then fail "a site \`$out\` of \`$name\`"; fi
    done
    if out=$(site_of '{ site: "a
b" }'); then fail "a site over two lines: \`$out\`"; fi
}

disk_sh() {
    WYRM_SYS=$t/sys WYRM_MOUNTINFO=$t/mountinfo WYRM_DEV=/dev $SH "$lib/disk.sh" "$@"
}

the_disk_is_the_one_of_the_root() {
    setup_device disk
    want "disk" "$(disk_sh disk)" vda
    want "partition 3" "$(disk_sh part 3)" /dev/vda3
    if out=$(disk_sh part 4); then fail "a partition 4: $out"; fi
    for bad in '' 0 03 x '3 4'; do
        if out=$(disk_sh part "$bad"); then fail "a partition \`$bad\`: $out"; fi
    done
    # an NVMe disk and a card: the name of a partition is the kernel's, not made up here
    t=$work/t/nvme
    mkdir -p "$t/sys/block/nvme0n1/nvme0n1p2" "$t/sys/block/nvme0n1/nvme0n1p3" \
        "$t/sys/block/mmcblk0/mmcblk0p3" "$t/sys/dev/block" "$t/sys/class/block"
    echo 2 > "$t/sys/block/nvme0n1/nvme0n1p2/partition"
    echo 3 > "$t/sys/block/nvme0n1/nvme0n1p3/partition"
    echo 3 > "$t/sys/block/mmcblk0/mmcblk0p3/partition"
    ln -s ../../block/nvme0n1/nvme0n1p2 "$t/sys/dev/block/259:2"
    # a root without an overlay: mounted at /
    echo '1 0 259:2 / / rw - ext4 /dev/root rw' > "$t/mountinfo"
    want "disk" "$(disk_sh disk)" nvme0n1
    want "partition 3" "$(disk_sh part 3)" /dev/nvme0n1p3
    # mediatek/filogic: the root is a FIT block device, the boot loader names the partition
    t=$work/t/fit
    mkdir -p "$t/sys/block/fit0" "$t/sys/block/mmcblk0/mmcblk0p7/of_node" \
        "$t/sys/block/mmcblk0/mmcblk0p8" "$t/sys/dev/block" "$t/sys/class/block" \
        "$t/sys/firmware/devicetree/base/chosen"
    echo 7 > "$t/sys/block/mmcblk0/mmcblk0p7/partition"
    echo 8 > "$t/sys/block/mmcblk0/mmcblk0p8/partition"
    printf '\0\0\0\052' > "$t/sys/block/mmcblk0/mmcblk0p7/of_node/phandle"
    printf '\0\0\0\052' > "$t/sys/firmware/devicetree/base/chosen/rootdisk"
    ln -s ../../block/fit0 "$t/sys/dev/block/259:0"
    ln -s ../../block/fit0 "$t/sys/class/block/fit0"
    ln -s ../../block/mmcblk0/mmcblk0p7 "$t/sys/class/block/mmcblk0p7"
    echo '20 1 259:0 / /rom ro - squashfs /dev/fit0 ro' > "$t/mountinfo"
    want "disk" "$(disk_sh disk)" mmcblk0
    want "partition 8" "$(disk_sh part 8)" /dev/mmcblk0p8
    # no such name in the device tree: not told
    printf '\0\0\0\053' > "$t/sys/firmware/devicetree/base/chosen/rootdisk"
    if out=$(disk_sh disk); then fail "a disk: $out"; fi
}

for test in a_new_card_gets_its_partition an_mbr_card_gets_a_primary_partition \
    the_second_boot_formats_nothing a_card_written_again_keeps_its_data \
    a_partition_that_was_there_is_never_formatted another_disk_is_not_touched \
    a_card_without_room_is_left_alone a_failed_mkfs_leaves_no_data_label \
    a_file_system_with_errors_is_not_mounted a_partition_at_another_place_is_not_used \
    a_partition_that_was_there_elsewhere_is_not_used \
    a_hybrid_mbr_is_put_back a_mounted_partition_is_not_mounted_again \
    the_same_site_keeps_its_data another_site_sets_the_old_data_aside \
    data_without_a_name_is_set_aside the_broker_s_links_are_never_followed \
    a_configuration_without_a_site_starts_no_broker \
    the_site_is_the_key_of_the_outermost_object the_disk_is_the_one_of_the_root; do
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
