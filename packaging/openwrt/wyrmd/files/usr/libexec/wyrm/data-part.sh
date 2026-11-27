#!/bin/sh
# The data partition of a WYRM board (ADR 0051 §3): made at the first boot in the rest of
# the card, mounted at every boot, before the broker starts.
#
#   data-part.sh                      on the device, from /etc/init.d/wyrmd
#   data-part.sh site <part> <config> the site rule alone, on a directory (tests)
#
# The data partition starts 1 MiB after the end of the config partition and reaches to
# the end of the card.
#
# The layout. The partition is mounted at /srv/wyrm-part, which is root's (0700). In it:
# `.site` (root's), `broker` (the broker's user's, 0700: its data_dir) and the data of
# other sites set aside as `.replaced-<site>-<n>`. `broker` is bind-mounted at /srv/wyrm,
# the data_dir of the configuration. Root never acts inside a directory the broker's
# user can write: it renames `broker` as a whole, and writes `.site`, in the root-owned
# directory above it.
#
# Exit 0: /srv/wyrm is `broker` of the mounted data partition and holds the data of the
# site of /etc/wyrm/wyrmd.json5. Any other exit: the broker must not start; the reason is
# on stderr. It runs only while no broker runs (/etc/init.d/wyrmd).
#
# What it never does:
#   - touch a disk it cannot prove to be the image's: the disk is the one that holds the
#     root file system, and the config partition on it (its number is in
#     /etc/wyrm/image.json) must be 4 MiB and start with WYRMCFG0 or WYRMCFG1
#   - format a partition that was there before this boot. A partition this run adds to
#     the table is formatted, unless it already holds the label `wyrm-data`: that is the
#     data of a card whose image was written again, and it is kept
#   - leave a half-made file system under the name: mkfs gives the label `wyrm-new`, and
#     the label `wyrm-data` is set when mkfs has ended well
#
# A card whose partition was made and not formatted (a power loss in between) is not
# repaired here: write the image again, then the partition is this run's own again.
#
# The site rule. `.site` names the site whose data `broker` holds. When the configuration
# names another site (a card written again with another configuration), `broker` is
# renamed to `.replaced-<site>-<n>`, never merged and never deleted, and the broker starts
# on a new, empty `broker`. The same site keeps its data.
#
# Environment (tests): WYRM_IMAGE_JSON, WYRM_CONFIG, WYRM_DATA, WYRM_PART, WYRM_OWNER,
# WYRM_SYS, WYRM_MOUNTS, WYRM_DISK_SH, WYRM_SITE_SH, WYRM_CONFIG_PART, WYRM_DATA_PART, and
# the commands WYRM_SFDISK, WYRM_PARTX, WYRM_BLKID, WYRM_MKFS, WYRM_TUNE2FS, WYRM_FSCK,
# WYRM_MOUNT, WYRM_UMOUNT.

set -u
umask 022
LC_ALL=C
export LC_ALL

IMAGE_JSON=${WYRM_IMAGE_JSON:-/etc/wyrm/image.json}
CONFIG=${WYRM_CONFIG:-/etc/wyrm/wyrmd.json5}
DATA=${WYRM_DATA:-/srv/wyrm}
PART=${WYRM_PART:-/srv/wyrm-part}
OWNER=${WYRM_OWNER:-wyrm:wyrm}
SYS=${WYRM_SYS:-/sys}
MOUNTS=${WYRM_MOUNTS:-/proc/mounts}
# two commands, each split into its words where it is called
DISK_SH=${WYRM_DISK_SH:-/usr/libexec/wyrm/disk.sh}
SITE_SH=${WYRM_SITE_SH:-/usr/libexec/wyrm/site.sh}
SFDISK=${WYRM_SFDISK:-sfdisk}
PARTX=${WYRM_PARTX:-partx}
BLKID=${WYRM_BLKID:-blkid}
MKFS=${WYRM_MKFS:-mkfs.ext4}
TUNE2FS=${WYRM_TUNE2FS:-tune2fs}
FSCK=${WYRM_FSCK:-e2fsck}
MOUNT=${WYRM_MOUNT:-mount}
UMOUNT=${WYRM_UMOUNT:-umount}

REGION_SECTORS=8192 # the config partition: 4 MiB
# The data partition starts 1 MiB after the end of the config partition. A base image
# ends at most there (a GPT image keeps that MiB for its second table; `wyr image base`
# refuses an image that goes further), so an image written again over the card never
# reaches the data partition's file system.
DATA_GAP_SECTORS=2048
MIN_SECTORS=65536   # no data partition below 32 MiB
LABEL=wyrm-data
LABEL_NEW=wyrm-new
GPT_LINUX=0FC63DAF-8483-4772-8E79-3D69D8477DE4

say() { echo "wyrm data: $*" >&2; }
no() {
	say "$*"
	say "the broker is not started"
	exit 1
}

# ---- the site rule --------------------------------------------------------------------

# a name that is safe as a part of a file name
plain_site() {
	case $1 in
	'' | .* | *[!A-Za-z0-9_.-]*) return 1 ;;
	esac
	[ "${#1}" -le 64 ]
}

# site_rule PART CONFIG: PART is root's; root acts on the names directly in it only
site_rule() {
	s_part=$1
	s_broker=$s_part/broker
	s_site=$($SITE_SH "$2") || s_site=
	plain_site "$s_site" || no "$2 names no site"
	if [ -L "$s_broker" ] || { [ -e "$s_broker" ] && [ ! -d "$s_broker" ]; }; then
		no "$s_broker is no directory"
	fi
	s_old=
	if [ -f "$s_part/.site" ] && [ ! -L "$s_part/.site" ]; then
		IFS= read -r s_old < "$s_part/.site" || true
		plain_site "$s_old" || s_old=unknown
	elif [ -e "$s_part/.site" ] || [ -L "$s_part/.site" ]; then
		s_old=unknown
	fi
	# no `.site` beside a `broker`: data from before the rule, nothing says it is another
	# site's
	if [ -n "$s_old" ] && [ "$s_old" != "$s_site" ] && [ -d "$s_broker" ]; then
		s_n=1
		while [ -e "$s_part/.replaced-$s_old-$s_n" ] || [ -L "$s_part/.replaced-$s_old-$s_n" ]; do
			s_n=$((s_n + 1))
		done
		s_aside=$s_part/.replaced-$s_old-$s_n
		# one rename of the directory as a whole: nothing inside it is opened
		mv "$s_broker" "$s_aside" || no "cannot move $s_broker to $s_aside"
		say "this card held the data of the site \`$s_old\`; the configuration is of the site \`$s_site\`"
		say "the old data is kept in $s_aside and the broker starts new"
	fi
	# `.site` before the new `broker`: a run that was cut in between makes `broker` next
	# time, and sets nothing aside twice
	if [ "$s_old" != "$s_site" ]; then
		rm -f "$s_part/.site.new"
		(
			set -C
			printf '%s\n' "$s_site" > "$s_part/.site.new"
		) 2> /dev/null || no "cannot write $s_part/.site"
		mv -f "$s_part/.site.new" "$s_part/.site" || no "cannot write $s_part/.site"
	fi
	if [ ! -d "$s_broker" ]; then
		mkdir -m 700 "$s_broker" || no "cannot make $s_broker"
		chown -h "$OWNER" "$s_broker" || no "cannot give $s_broker to $OWNER"
	fi
	sync
}

if [ "${1:-}" = site ]; then
	[ $# -eq 3 ] || exit 2
	site_rule "$2" "$3"
	exit 0
fi

# ---- the disk -------------------------------------------------------------------------

number_of() {
	if [ -n "$2" ]; then
		echo "$2"
	else
		jsonfilter -i "$IMAGE_JSON" -e "@.$1" 2> /dev/null
	fi
}
config_part=$(number_of config_part "${WYRM_CONFIG_PART:-}") || config_part=
data_part=$(number_of data_part "${WYRM_DATA_PART:-}") || data_part=
case "$config_part:$data_part" in
: | *: | :* | *[!0-9:]*) no "$IMAGE_JSON does not name the config and the data partition" ;;
esac

disk=$($DISK_SH disk) || no "the disk of the root file system cannot be told: nothing is touched"
config_dev=$($DISK_SH part "$config_part") ||
	no "the disk $disk has no partition $config_part: it is not the card of a WYRM image, nothing is touched"
config_name=${config_dev##*/}
if [ "$(cat "$SYS/class/block/$config_name/size" 2> /dev/null)" != "$REGION_SECTORS" ]; then
	no "partition $config_part of $disk is not a config region of 4 MiB: nothing is touched"
fi
case $(dd if="$config_dev" bs=8 count=1 2> /dev/null) in
WYRMCFG0 | WYRMCFG1) ;;
*) no "partition $config_part of $disk does not start as a config region: nothing is touched" ;;
esac
disk_dev=${config_dev%/*}/$disk

# mounted_on DIR: the device that is mounted at DIR, empty when none is
mounted_on() {
	awk -v at="$1" '$2 == at { dev = $1 } END { print dev }' "$MOUNTS"
}

existed=1
data_dev=$($DISK_SH part "$data_part") || data_dev=
if [ -z "$data_dev" ]; then
	existed=0
	# ---- a new entry in the table ------------------------------------------------------
	config_start=$(cat "$SYS/class/block/$config_name/start" 2> /dev/null) || config_start=
	disk_sectors=$(cat "$SYS/block/$disk/size" 2> /dev/null) || disk_sectors=
	case "$config_start:$disk_sectors" in
	: | *: | :* | *[!0-9:]*) no "the size of $disk cannot be read: nothing is touched" ;;
	esac
	start=$((config_start + REGION_SECTORS + DATA_GAP_SECTORS))
	table=$("$SFDISK" -d "$disk_dev" 2> /dev/null | sed -n 's/^label: //p')
	case $table in
	dos) spare=0 ;;
	gpt) spare=34 ;; # the second table at the end of the card
	*) no "the partition table of $disk cannot be read: nothing is touched" ;;
	esac
	if [ $((disk_sectors - start - spare)) -lt "$MIN_SECTORS" ]; then
		no "the card has no room for the data partition after the image ($((disk_sectors / 2048)) MiB in all)"
	fi
	tmp=$(mktemp -d /tmp/wyrm-data.XXXXXX) || no "cannot make a temporary directory"
	dd if="$disk_dev" of="$tmp/sector0" bs=512 count=1 2> /dev/null ||
		no "cannot read $disk_dev"
	if [ "$table" = gpt ]; then
		# A GPT image ends before the card does: its second table moves to the end of the
		# card. A hybrid MBR (the boot ROM of mediatek/filogic reads it) has a partition
		# entry beside the one of type EE; sfdisk writes a protective MBR over it, so the
		# first sector is put back as it was.
		hybrid=0
		for at in 450 466 482 498; do
			type=$(dd if="$tmp/sector0" bs=1 skip="$at" count=1 2> /dev/null | hexdump -v -e '1/1 "%02x"')
			case $type in
			00 | ee) ;;
			*) hybrid=1 ;;
			esac
		done
		"$SFDISK" --no-reread --no-tell-kernel --relocate gpt-bak-std "$disk_dev" > "$tmp/log" 2>&1 || {
			cat "$tmp/log" >&2
			rm -rf "$tmp"
			no "the partition table of $disk could not be moved to the end of the card"
		}
		line="start=$start, type=$GPT_LINUX, name=\"$LABEL\""
	else
		hybrid=0
		line="start=$start, type=83"
	fi
	echo "$line" | "$SFDISK" --no-reread --no-tell-kernel --append "$disk_dev" > "$tmp/log" 2>&1 || {
		cat "$tmp/log" >&2
		rm -rf "$tmp"
		no "the data partition could not be added to the table of $disk"
	}
	if [ "$hybrid" -eq 1 ]; then
		dd if="$tmp/sector0" of="$disk_dev" bs=512 count=1 conv=notrunc 2> /dev/null
		if ! dd if="$disk_dev" bs=512 count=1 2> /dev/null | cmp -s - "$tmp/sector0"; then
			rm -rf "$tmp"
			no "the first sector of $disk could not be put back"
		fi
	fi
	rm -rf "$tmp"
	sync
	"$PARTX" -a --nr "$data_part" "$disk_dev" > /dev/null 2>&1
	waited=0
	while :; do
		data_dev=$($DISK_SH part "$data_part") && [ -e "$data_dev" ] && break
		[ "$waited" -lt 10 ] || no "partition $data_part of $disk was added to the table, and the kernel does not show it"
		sleep 1
		waited=$((waited + 1))
	done
	data_name=${data_dev##*/}
	if [ "$(cat "$SYS/class/block/$data_name/start" 2> /dev/null)" != "$start" ]; then
		no "partition $data_part of $disk does not start 1 MiB after the config region: it is not used"
	fi
	say "partition $data_part of $disk is new: $data_dev"
fi

# the bind mount of a start before: made again after the site rule (no broker runs)
if [ -n "$(mounted_on "$DATA")" ]; then
	"$UMOUNT" "$DATA" || no "$DATA cannot be unmounted"
	[ -z "$(mounted_on "$DATA")" ] || no "$DATA is still mounted"
fi

at=$(mounted_on "$PART")
if [ -n "$at" ] && [ "$at" != "$data_dev" ]; then
	no "$PART is the mount of $at, not of $data_dev"
fi
if [ -z "$at" ]; then
	# ---- the file system -------------------------------------------------------------
	label=$("$BLKID" -s LABEL -o value "$data_dev" 2> /dev/null) || label=
	if [ "$label" != "$LABEL" ]; then
		if [ "$existed" -eq 1 ]; then
			say "$data_dev was there before this boot and does not hold the label \`$LABEL\`."
			say "It is never formatted here. Write the image to the card again."
			no "no data partition"
		fi
		say "formatting $data_dev"
		"$MKFS" -q -F -L "$LABEL_NEW" "$data_dev" > /dev/null 2>&1 || no "$data_dev could not be formatted"
		"$TUNE2FS" -L "$LABEL" "$data_dev" > /dev/null 2>&1 || no "$data_dev could not be given its label"
		sync
	else
		[ "$existed" -eq 1 ] || say "$data_dev holds data of a WYRM broker: it is kept"
	fi

	# 0: clean, 1: errors corrected, 2: corrected, a restart is asked for (not of this
	# disk's root); from 4 on the file system is not sound
	rc=0
	"$FSCK" -p "$data_dev" > /dev/null 2>&1 || rc=$?
	[ "$rc" -lt 4 ] || no "the file system of $data_dev has errors e2fsck does not repair by itself (exit $rc)"

	mkdir -p "$PART" || no "cannot make $PART"
	if [ -L "$PART" ] || [ ! -d "$PART" ]; then
		no "$PART is no directory"
	fi
	"$MOUNT" -t ext4 -o nosuid,nodev,noatime "$data_dev" "$PART" || no "$data_dev could not be mounted at $PART"
	[ "$(mounted_on "$PART")" = "$data_dev" ] || no "$PART is not the mount of $data_dev"
fi
# the top of the file system is root's alone
chmod 700 "$PART" || no "cannot set the mode of $PART"

site_rule "$PART" "$CONFIG"

mkdir -p "$DATA" || no "cannot make $DATA"
if [ -L "$DATA" ] || [ ! -d "$DATA" ]; then
	no "$DATA is no directory"
fi
"$MOUNT" -o bind "$PART/broker" "$DATA" || no "$PART/broker could not be mounted at $DATA"
[ "$(mounted_on "$DATA")" = "$data_dev" ] || no "$DATA is not the mount of $data_dev"
exit 0
