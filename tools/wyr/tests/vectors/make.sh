#!/bin/sh
# Makes the partition table vectors of tools/wyr/src/image_part.rs with tools that are not
# ours: `sgdisk` (gptfdisk) for the GPT, `sfdisk` (util-linux) for the MBR. Each table is
# written before and after a partition of 8192 sectors is added where `wyr image base`
# adds the config partition; the tests ask `image_part` for the same step and compare.
#
#   docker run --rm -v "$PWD/tools/wyr/tests/vectors":/v alpine:3.22 sh /v/make.sh
#
# A vector is text: `sectors <n>`, then one line `<sector> <hex of its 512 bytes>` for
# every sector that is not zeros.

set -eu
apk add -q sgdisk sfdisk > /dev/null
cd "$(dirname "$0")"
tmp=$(mktemp -d)

dump() { # dump IMAGE > vector
    size=$(wc -c < "$1")
    echo "sectors $((size / 512))"
    n=0
    while [ "$n" -lt $((size / 512)) ]; do
        hex=$(dd if="$1" bs=512 skip="$n" count=1 2> /dev/null | od -An -v -tx1 | tr -d ' \n')
        case $hex in
        *[!0]*) echo "$n $hex" ;;
        esac
        n=$((n + 1))
    done
}

disk=36EAB844-1898-3BAD-DCBD-FD81AF20EC
g=$tmp/gpt.img
truncate -s 6M "$g"
sgdisk -a 1 -U "${disk}00" \
    -n 1:2048:4095 -t 1:EF00 -c 1:boot -u 1:"${disk}01" \
    -n 2:4096:8191 -t 2:8300 -u 2:"${disk}02" "$g" > /dev/null
dump "$g" > gpt-before.txt
# the image grows to the config partition and 1 MiB for the second table
truncate -s 9M "$g"
sgdisk -e "$g" > /dev/null
sgdisk -a 1 -n 3:8192:16383 -t 3:8DA63339-0007-60C0-C436-083AC8230908 \
    -c 3:wyrm-config -u 3:"${disk}03" "$g" > /dev/null
sgdisk -v "$g" | grep -q 'No problems found'
dump "$g" > gpt-after.txt

m=$tmp/mbr.img
truncate -s 6M "$m"
printf 'label: dos\nlabel-id: 0x5452574f\nstart=2048, size=2048, type=c, bootable\nstart=4096, size=4096, type=83\n' |
    sfdisk -q "$m"
dump "$m" > mbr-before.txt
truncate -s 8M "$m"
echo 'start=8192, size=8192, type=da' | sfdisk -q --append "$m"
dump "$m" > mbr-after.txt

{
    sgdisk --version
    sfdisk --version
} > tools.txt
rm -rf "$tmp"
