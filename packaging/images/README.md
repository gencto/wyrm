# Board images (ADR 0051 §2, §4)

One **base image** per board: OpenWrt as published, the package `wyrmd` as
files (`packaging/openwrt`), the seed packages, and an empty config region.
A person's tool writes a configuration into that region (`wyr image build`,
`docs/operations.md`, "Board images"); the device reads it at its first
boot.

| File | What |
|---|---|
| `boards.json` | the boards, the pinned OpenWrt release, the ImageBuilder archives and the build container |
| `build.sh` | what runs in the container: the ImageBuilder for one board |
| `files/` | files of every image beside the package's: `/etc/uci-defaults/80-wyrm-user` |

## Build a base image

```
wyr image base --board qemu-armsr --wyrmd target/aarch64-unknown-linux-musl/release/wyrmd \
    --seed-dir dist/seed --out dist/images
```

Run it from the repository root (`--packaging` names the `packaging`
directory otherwise). It needs `docker` or `podman` (`--runtime`), no root
and about 2 GB of disk. With `podman` it is not tried yet. `--wyrmd` is the static `aarch64-unknown-linux-musl`
binary (`deploy/docker/Dockerfile` builds it); a file that is no ELF for
aarch64 is refused. `--wyrmd-version` goes into the names and the index
(default: the version of `wyr`).

In `--out` it leaves:

| File | What |
|---|---|
| `wyrm-<board>-<wyrmd>-openwrt-<release>.img` | the raw image; `config_offset` counts in its bytes |
| `….img.gz` | the same image as gzip, to publish (no name and no time in its header) |
| `….partitions.txt` | the partitions of the image |
| `….manifest` | the packages in the image, as the ImageBuilder lists them |
| `index.json` | `wyrm-images/1`: the entry of the board is written, entries of other boards stay |

The steps:

1. `boards.json` is read and checked. Every name that reaches a command
   line or a URL is made of plain characters, an archive is the one OpenWrt
   publishes for the release and the target, and the container is named by
   digest.
2. The files of the image are staged: `packaging/openwrt/wyrmd/files`,
   `files/` of this directory, the binary as `/usr/bin/wyrmd`, the files of
   `--seed-dir` in `/usr/share/wyrm/seed/` and `/etc/wyrm/image.json`.
   A file is 0755 when its source is executable, else 0644. A link or a
   special file in a source directory is refused. `seed.json` in
   `--seed-dir` is refused: that list is the person's.
3. The container runs `build.sh`: it downloads the ImageBuilder archive
   into the cache (`--cache`, default `<out>/.cache`) unless it is there,
   compares its SHA-256 with `boards.json`, and runs `make image` with
   `PROFILE`, `PACKAGES`, `FILES` and `ROOTFS_PARTSIZE`.
4. `wyr` appends the config partition to the image (below), reads the
   region back, writes the gzip and the index entry.

The container gets no capability (`--cap-drop ALL`, `no-new-privileges`),
runs as the owner of `--out`, and has three mounts: the cache, the staged
files (read only) and one output directory. It uses the network for the
ImageBuilder archive (checked by its SHA-256) and for the packages of the
pinned release that the ImageBuilder downloads from `downloads.openwrt.org`
and checks against the release's signing key, which the archive carries.

## The pinned release

**OpenWrt 25.12.6** (pinned 2026-11-27): the latest stable release, and it
has an ImageBuilder for all four targets. Packages are `apk` packages.

| Target | Archive (SHA-256 from the release's `sha256sums`) |
|---|---|
| `bcm27xx/bcm2711` | `78191c19…604d2a` |
| `bcm27xx/bcm2712` | `5a379d82…3867ab` |
| `mediatek/filogic` | `8ce0da1e…19daf83` |
| `armsr/armv8` | `3d012814…2301cf` |

The full URLs and sums are in `boards.json`. To move to another release,
change `openwrt`, the four archives and the `image` names together; the
tests refuse a list that mixes releases.

The **build container** is OpenWrt's own build worker,
`ghcr.io/openwrt/buildbot/buildworker-v3.11.8` (tag `v29`), by digest. It is
the base of OpenWrt's ImageBuilder containers and has what the ImageBuilder
needs. OpenWrt publishes the ImageBuilder for x86-64 only, so the container
runs as `linux/amd64` (emulated on an arm64 host: a build takes about
3 minutes on an Apple M4).

## What is in an image

OpenWrt's default packages of the target and the profile, with these
changes (`packages` in `boards.json`):

| Change | Why |
|---|---|
| `-dnsmasq` | no DHCP server; names are resolved by the servers the network gives (`/tmp/resolv.conf.d/resolv.conf.auto`) |
| `-odhcpd-ipv6only` | no DHCPv6 server and no router advertisements |
| `-ppp`, `-ppp-mod-pppoe` | a host has no WAN dial-up |
| `zoneinfo-all` | the first boot reads the POSIX rule of the person's time zone from the zone's file |
| `kmod-usb-acm`, `kmod-usb-serial-ch341`, `-cp210x`, `-ftdi`, `-pl2303` | the usual USB serial adapters (Modbus RTU and the like) |

`dropbear` and `firewall4` stay: the first boot refuses `authorized_keys`
in an image without an SSH server, and the host role is firewall rules.
LuCI is not in the ImageBuilder's default set and is not added.

## The config partition

The ImageBuilder's image gets one more partition, right after its last one
(start on 1 MiB), of exactly 4 MiB (`wyrm_image::CONFIG_SIZE`), filled with
`WYRMCFG0` and zeros. Its byte offset is `config_offset` of the index entry;
its device path on the board is `config_dev` of `boards.json` and of
`/etc/wyrm/image.json`. `wyr image base` fails when the partition's number
is not the one `config_dev` names.

| Board | Table | Partitions of the image | `config_dev` |
|---|---|---|---|
| `rpi4`, `rpi5` | MBR | 1 boot (FAT, 64 MiB), 2 root (256 MiB), **3 config** (type `DA`) | `/dev/mmcblk0p3` |
| `qemu-armsr` | GPT | 1 EFI (128 MiB), 2 root (256 MiB), **3 `wyrm-config`**, 128 BIOS boot | `/dev/vda3` |
| `bpi-r4` | GPT, hybrid MBR | 1 `bl2` … 6 `install`, 7 `production` (256 MiB), **8 `wyrm-config`** | `/dev/mmcblk0p8` |

`wyr` edits the table in the image file (`tools/wyr/src/image_part.rs`);
that needs no root. The build container has neither `sfdisk` nor `sgdisk`,
and no other container is trusted for one step. An MBR gets its third entry.
A GPT gets one entry (type "Linux reserved", the same unique id in every
image, name `wyrm-config`), the checksums of its header, and its second
table at the new end of the image. The first sector of a GPT image is never
written, so the hybrid MBR of a `mediatek/filogic` image stays byte for
byte. No entry that was there is changed. The image grows to the end of the
config partition (plus 1 MiB for the second table of a GPT): OpenWrt's own
image ends where its root file system ends, before the end of the root
partition (the `sdcard.img` of `mediatek/filogic` even ends 4 bytes into a
sector).

Checked on images of 2026-11-27 with tools that are not ours: `sfdisk -V`
finds no error in the `rpi4` image, `sgdisk -v` none in the `qemu-armsr`
image, and the Linux kernel lists `vda1 vda2 vda3 vda128` there. For
`bpi-r4`, `sgdisk -v` reports one thing, "MBR partitions 1 and 2 overlap":
that is OpenWrt's hybrid MBR as the ImageBuilder wrote it.

## `ROOTFS_PARTSIZE` never changes

`rootfs_partsize_mb` of a board is fixed for the life of the board (256 for
every board today). The config partition and the data partition start
where this value puts them. A later image with another value, written over
a device, moves both: the data of that device is lost. The test
`rootfs_partsize_never_changes` (`tools/wyr/tests/boards.rs`) compares each
board with `origin/main` and fails on a change; `wyr image base` prints the
rule with every image.

The root partition holds the squashfs (about 35 MiB with `wyrmd`) and the
overlay for `/etc`.

## The broker's user

An image takes the package as files, so `USERID` of the package's
`Makefile` makes no user. `/etc/uci-defaults/80-wyrm-user` makes the user
and the group `wyrm` with uid and gid **787** at the first boot, before
`90-wyrm-host` uses them. It refuses to go on when 787 belongs to another
name.

787 is free in OpenWrt 25.12.6: `package/base-files/files/etc/passwd` and
`group` of the tag `v25.12.6` use 0, 1, 4, 8, 20, 29, 33, 55, 100, 101 and
65534, and no `USERID` of the feeds `packages`, `luci`, `routing`,
`telephony` and `video` (branch `openwrt-25.12`, read on 2026-11-27, 101
`USERID` lines) names 787. Check again when the release changes:

```
grep -rh "USERID:=" --include=Makefile . | grep -E "=787\b"
```

## The data partition: not made yet

ADR 0051 §3 wants `data_dir` on an ext4 partition of its own, made at the
first boot and sized to the rest of the card. **No script makes it today.**
`/etc/init.d/wyrmd` makes the directory `/srv/wyrm` and nothing mounts a
partition there, so the broker's data lies in the overlay of the root
partition (about 190 MiB free in a 256 MiB root; seen in QEMU). `data_dev`
of `boards.json` and `image.json` names where the partition will be: the
one after the config partition.

It is made at the first boot and not in the image, because an image does
not know the size of the card. What it needs is in the report of this step
(a script in `packaging/openwrt/wyrmd/files`, a partition tool and a mount
in the image, and a service that starts no broker on an unmounted
`/srv/wyrm`).

## Boards

- **`rpi4`, `rpi5`**: the SD card. `config_dev` is a path of the SD slot;
  a board that boots from USB or NVMe finds no config region.
- **`bpi-r4`**: runs from the SD card in this version. OpenWrt's install
  onto the eMMC writes its own partition table there (`emmc-gpt.bin`),
  without a config partition, and the SD slot and the eMMC share one
  controller: the configuration does not travel with that install.
- **`bpi-r4-8g`**: not built (`unavailable`). OpenWrt 25.12.6 publishes no
  image for the 8 GB board.
- **`qemu-armsr`**: for the smoke test; `listed: false`, the page does not
  show it.

```
qemu-system-aarch64 -M virt -cpu host -accel hvf -m 1024 -display none \
    -bios edk2-aarch64-code.fd -drive file=plant.img,format=raw,if=virtio \
    -netdev user,id=n0,hostfwd=tcp:127.0.0.1:18445-:8445 \
    -device virtio-net-pci,netdev=n0 -serial file:console.log
```

## Not reproducible bit for bit

`image.json` carries the build time, and the ImageBuilder makes a signing
key of its own at each run. Two builds of the same inputs give two images
with other SHA-256 sums. The index is what binds an image to its offset.

## Tests

```
cargo test -p wyr          # boards.json, the argv, the partition tables, the index
```

`tools/wyr/tests/boards.rs` reads `boards.json` as any reader does;
`src/image_base.rs` and `src/image_part.rs` have the tests of the strict
reader, the container's arguments and the tables (MBR, GPT, a GPT image
shorter than its partitions with a hybrid MBR). No test runs a container.
