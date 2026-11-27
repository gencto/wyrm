#!/bin/sh
# The disk a WYRM board image runs from, and its partitions by number.
#
#   disk.sh disk        prints the name of the disk that holds the root file system (`mmcblk0`)
#   disk.sh part <n>    prints the device of partition <n> of that disk (`/dev/mmcblk0p3`)
#
# Exit 1 when it cannot be told: nothing is guessed from a name. The disk is found from
# the device the root file system is mounted from (`/rom` below the overlay, else `/`),
# so a board that starts from a USB stick or an NVMe disk finds its own partitions. Where
# the root is no partition of a disk (a FIT block device on mediatek/filogic), the disk is
# the one the boot loader names in the device tree (`/chosen/rootdisk`).
#
# Environment (tests): WYRM_SYS (/sys), WYRM_MOUNTINFO (/proc/self/mountinfo),
# WYRM_DEV (/dev).

SYS=${WYRM_SYS:-/sys}
MOUNTINFO=${WYRM_MOUNTINFO:-/proc/self/mountinfo}
DEV=${WYRM_DEV:-/dev}

# disk_of NAME: the disk of a block device of sysfs, itself when it is a disk
disk_of() {
	d_path=$(cd -P "$SYS/class/block/$1" 2> /dev/null && pwd) || return 1
	if [ -f "$d_path/partition" ]; then
		d_path=${d_path%/*}
	fi
	echo "${d_path##*/}"
}

root_disk() {
	devno=
	for point in /rom /; do
		devno=$(awk -v p="$point" '$5 == p { print $3; exit }' "$MOUNTINFO" 2> /dev/null)
		[ -z "$devno" ] || break
	done
	[ -n "$devno" ] || return 1
	path=$(cd -P "$SYS/dev/block/$devno" 2> /dev/null && pwd) || return 1
	if [ -f "$path/partition" ]; then
		path=${path%/*}
		echo "${path##*/}"
		return 0
	fi
	# the device the boot loader names: a partition of the disk, or the disk
	[ -f "$SYS/firmware/devicetree/base/chosen/rootdisk" ] || return 1
	for handle in "$SYS"/class/block/*/of_node/phandle "$SYS"/class/block/*/device/of_node/phandle; do
		[ -f "$handle" ] || continue
		if cmp -s "$handle" "$SYS/firmware/devicetree/base/chosen/rootdisk"; then
			name=${handle#"$SYS"/class/block/}
			disk_of "${name%%/*}"
			return
		fi
	done
	return 1
}

case ${1:-} in
disk)
	root_disk
	;;
part)
	case ${2:-} in
	'' | 0* | *[!0-9]*) exit 1 ;;
	esac
	disk=$(root_disk) || exit 1
	for part in "$SYS/block/$disk"/*/partition; do
		[ -f "$part" ] || continue
		if [ "$(cat "$part")" = "$2" ]; then
			name=${part%/partition}
			echo "$DEV/${name##*/}"
			exit 0
		fi
	done
	exit 1
	;;
*)
	echo "usage: disk.sh disk | part <n>" >&2
	exit 2
	;;
esac
