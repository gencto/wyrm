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
| `verify-table.sh` | checks the partition table of an image with `sfdisk` and `sgdisk` in a throwaway container |
| `smoke.sh`, `smoke_client.py` | the smoke test: the image of `qemu-armsr` built, assembled and booted in QEMU, the first admin made through the gateway ("Tests" below) |
| `workflow.yml` | the release of the images on a tag `images-v<wyrmd version>`; copy it to `.github/workflows/images-release.yml` |

## Build a base image

```
wyr image base --board qemu-armsr --wyrmd target/aarch64-unknown-linux-musl/release/wyrmd \
    --wyrmd-version 0.9.0 --seed-dir dist/seed --out dist/images
```

Run it from the repository root (`--packaging` names the `packaging`
directory otherwise). It needs `docker` or `podman` (`--runtime`), no root
and about 2 GB of disk. With `podman` it is not tried yet. `--wyrmd` is the static `aarch64-unknown-linux-musl`
binary (`deploy/docker/Dockerfile` builds it); a file that is no ELF for
aarch64 is refused. `--wyrmd-version` is required: it goes into the names,
the index and `/etc/wyrm/image.json`. The binary is not run to ask it (it
is built for the board, not for this host); its SHA-256 is recorded beside
the version (`wyrmd_sha256`), so the index says which build it is.

In `--out` it leaves:

| File | What |
|---|---|
| `wyrm-<board>-<wyrmd>-openwrt-<release>.img` | the raw image; `config_offset` counts in its bytes |
| `….img.gz` | the same image as gzip, to publish (no name and no time in its header) |
| `….partitions.txt` | the partitions of the image |
| `….manifest` | the packages in the image, as the ImageBuilder lists them |
| `index.json` | `wyrm-images/1`: the entry of the board is written (with `wyrmd_sha256` and `manifest_sha256`), entries of other boards stay |

The gzip, the manifest and the index are written first and the raw image
last: a run that is cut leaves no raw image of that build in `--out`.

The steps:

1. `boards.json` is read and checked. Every name that reaches a command
   line or a URL is made of plain characters, an archive is the one OpenWrt
   publishes for the release and the target, and the container is named by
   digest.
2. The files of the image are staged. The package `wyrmd` goes in as the
   section `Package/wyrmd/install` of `packaging/openwrt/wyrmd/Makefile`
   says: its directories, each file with the mode of its line
   (`INSTALL_BIN` 0755, `INSTALL_DATA` 0644, `INSTALL_CONF` 0600), the
   binary as `/usr/bin/wyrmd`. That section is the one source of the modes
   for a feed package and for an image. A file of `files/` that it does not
   install, a file installed elsewhere than at its path, a link or a
   special file is refused. Then the files of `--seed-dir` in
   `/usr/share/wyrm/seed/` (0644; `seed.json` is refused: that list is the
   person's) and `/etc/wyrm/image.json`.
3. The container runs `build.sh`: it downloads the ImageBuilder archive
   into the cache (`--cache`, default `<out>/.cache`) unless it is there,
   compares its SHA-256 with `boards.json`, and runs `make image` with
   `PROFILE`, `PACKAGES`, `FILES` and `ROOTFS_PARTSIZE`.
4. `wyr` appends the config partition to the image (below) and reads the
   region back. The offset of the region must be the board's
   `config_offset` of `boards.json` ("The layout never changes" below).
   Then it writes the gzip and the index entry.

The container gets no capability (`--cap-drop ALL`, `no-new-privileges`),
runs as the owner of `--out`, and has three mounts: the cache, the staged
files (read only) and one output directory.

### What is pinned and what is not

The container has the runtime's default network.

- **Pinned by a hash**: the build container (digest) and the ImageBuilder
  archive (SHA-256 in `boards.json`, compared before it is used). The
  archive holds the kernel, the base packages and the key of the release.
- **Signed, not pinned**: the packages the ImageBuilder downloads from the
  feeds of the release on `downloads.openwrt.org` (here `zoneinfo-*`, the
  kernel modules, `sfdisk` and the like). `apk` checks each feed's index
  against the key in the archive (`keys/openwrt-25.12.pem`); `build.sh`
  stops when the ImageBuilder has that check off
  (`CONFIG_SIGNATURE_CHECK=y`) and prints the line
  `apk checks the feeds of … against the keys of the archive`. OpenWrt may
  publish a newer build of a package inside a release, so **two builds of
  one `boards.json` may differ** in package versions.
- **Recorded**: the manifest (every package with its version) is published
  beside the image, and its SHA-256 is `manifest_sha256` of the index
  entry. Two images of one release with the same `manifest_sha256` hold the
  same packages.

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
| `-odhcpd-ipv6only` | no DHCPv6 server and no router advertisements |
| `-ppp`, `-ppp-mod-pppoe` | a host has no WAN dial-up |
| `zoneinfo-all` | the first boot reads the POSIX rule of the person's time zone from the zone's file |
| `kmod-usb-acm`, `kmod-usb-serial-ch341`, `-cp210x`, `-ftdi`, `-pl2303` | the usual USB serial adapters (Modbus RTU and the like) |

`dnsmasq` stays as the local resolver, with its DHCP server off on `lan`
(`90-wyrm-host`). OpenWrt runs `ntpd` in a jail that binds the file behind
`/etc/resolv.conf` when `ntpd` starts. Without `dnsmasq` that file is
`/tmp/resolv.conf.d/resolv.conf.auto`, which `netifd` replaces when the
DHCP lease comes: the jail keeps the old, empty file, `ntpd` resolves no
server name and the clock is never set until `ntpd` is restarted. With
`dnsmasq` the file says `nameserver 127.0.0.1` from the start, and the clock
is set at the first boot without waiting (in QEMU 19 s after the boot).
The firewall opens no port 53.

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
A GPT gets one entry (type "Linux reserved", name `wyrm-config`; its unique
id is the disk's id with the partition's number as the last byte, as
OpenWrt names the partitions of its own images), the checksums of its
header, and its second table at the new end of the image. A second table
the ImageBuilder left between the last partition and the config partition
is zeroed. The first sector of a GPT image is never
written, so the hybrid MBR of a `mediatek/filogic` image stays byte for
byte. No entry that was there is changed. The image grows to the end of the
config partition (plus 1 MiB for the second table of a GPT): OpenWrt's own
image ends where its root file system ends, before the end of the root
partition (the `sdcard.img` of `mediatek/filogic` even ends 4 bytes into a
sector). **An image ends at most 1 MiB after its config partition**
(`DATA_GAP` of `image_base.rs`): the data partition of a card starts there
(`DATA_GAP_SECTORS` of `data-part.sh`), so an image written again over the
card never reaches its file system. `wyr image base` refuses an image that
goes further ("must end by byte …").

Two checks by tools that are not ours:

- **In the tests.** `tools/wyr/tests/vectors/` holds tables that `sgdisk`
  1.0.10 and `sfdisk` 2.41 wrote, before and after they added the same
  partition (`make.sh` there makes them). `image_part` must give the GPT
  byte for byte (both headers with their checksums, both arrays) and the
  MBR entry but for its CHS address.
- **On a built image.** `verify-table.sh <image>` runs `sfdisk -V` and,
  for a GPT, `sgdisk -v` in a throwaway container, and wants exactly one
  config partition that starts with the magic. For `bpi-r4` give
  `--hybrid-mbr`: `sgdisk -v` counts the two overlapping entries of
  OpenWrt's hybrid MBR as one problem, and that one is accepted.

## The layout never changes

Two things fix where the config partition and, after it, the data
partition of a card start:

- `rootfs_partsize_mb` of the board (256 for every board today). The test
  `rootfs_partsize_never_changes` (`tools/wyr/tests/boards.rs`) compares
  each board with the base of the change (`BOARDS_BASE`, else
  `origin/main`) and fails on another value. In CI the base is fetched
  before the test, and a base that cannot be read fails the test.
- what OpenWrt puts before the root partition (the boot partition: 64 MiB
  at 4 MiB on `bcm27xx`, 128 MiB on `armsr`). That is not ours to set, so
  `config_offset` of each board records where a real build put the region
  (`null` until a board was built once; such a board is not `listed`), and
  `wyr image base` refuses a build that gives another offset: "the layout
  of board … moved". The same test refuses a change of a recorded
  `config_offset` against the base (a `null` may become a number once).

A later image with another layout, written over a card in the field, adds
the data partition at another place: the data of that card is not found.

The root partition holds the squashfs (about 35 MiB with `wyrmd`) and the
overlay for `/etc`.

## The broker's user

An image takes the package as files, so `USERID` of the package's
`Makefile` makes no user. `/etc/uci-defaults/80-wyrm-user` (a file of the
package) makes the user
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

## The data partition

`data_dir` lies on an ext4 partition of its own, `data_part` of
`/etc/wyrm/image.json` (the number after the config partition; `data_dev`
of `boards.json` is its usual path). It is made at the first boot and not
in the image, because an image does not know the size of the card:
`/usr/libexec/wyrm/data-part.sh` adds it in the rest of the card, formats
it, and mounts it at every boot before the broker starts (the partition
at `/srv/wyrm-part`, root's; its `broker` directory at `/srv/wyrm`)
(`packaging/openwrt/README.md`, "The data partition", has the rules: which
disk, when it formats, the site rule). The image carries what the script
needs: `sfdisk`, `partx-utils`, `e2fsprogs`, `tune2fs`, `blkid`,
`kmod-fs-ext4`.

- **The data partition starts 1 MiB after the end of the config
  partition.** That MiB is where a GPT image keeps its second table: an
  image written whole over the card (`dd`, an imager) writes those bytes
  too, so a data partition right after the config partition would lose the
  start of its file system, and with it the label.
- **It ends at least 1 MiB before the end of the card** (after a GPT's
  second table), on a 1 MiB boundary. Imagers zero the first and the last
  MiB of a drive when they write it: Raspberry Pi Imager does on every
  write, and `balenaEtcher` and `bmaptool` may clear the ends too. A file
  system that reached the end of the card would lose its last MiB to a
  rewrite while its label survived. Start and size are counted the same
  way at every boot, so the entry the first boot of a rewritten card adds
  ends where the old one did.
- **A card written again with a newer image of the same layout keeps its
  data.** The new image's table has no data partition; the first boot adds
  the entry at the same place, finds the label `wyrm-data` and formats
  nothing. With the same site in the configuration the broker goes on with
  its data; with another site the old data is set aside as
  `/srv/wyrm-part/.replaced-<site>-<n>`.
- **The card must be larger than the image** by at least 34 MiB. A disk
  that is exactly the image gets no data partition, and the broker does not
  start (the console says so). **In QEMU, grow the disk file before the
  first boot**: `qemu-img resize -f raw plant.img 1G`.

## Boards

- **`rpi4`**: the SD card. The scripts find the config region and the data
  partition on the disk the root file system is on, so a board that starts
  from a USB stick has them there; that is not tried on a board.
- **`rpi5`**: as `rpi4` (another archive, the same layout: the config
  partition at byte 343 932 928). Built and its table checked; not booted
  on a board.
- **`bpi-r4`**: **this version runs from the SD card only.** Leave the
  card in; do not install onto the eMMC. OpenWrt's install writes its own
  partition table there (`emmc-gpt.bin`), without a config partition, and
  the SD slot and the eMMC share one controller, so the configuration does
  not go with that install. Planned (owner, 2026-11-27): the system goes
  onto the eMMC by OpenWrt's own path (SD → SPI-NAND → eMMC from the U-Boot
  menu), the configuration arrives from a USB stick that carries the same
  4 MiB region (`wyr image build --region-only`, to be built) at the first
  boot from the eMMC, and `data-part.sh` makes the data partition on the
  eMMC. Nothing of this is built or tried on the board.
- **`bpi-r4-8g`**: not built (`unavailable`). OpenWrt 25.12.6 publishes no
  image for the 8 GB board.
- **`qemu-armsr`**: for the smoke test; `listed: false`, the page does not
  show it.

```
qemu-img resize -f raw plant.img 1G     # room for the data partition
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
packaging/images/verify-table.sh dist/images/wyrm-rpi4-….img     # needs docker or podman
```

### The smoke test in QEMU

```
packaging/images/smoke.sh --wyrmd target/aarch64-unknown-linux-musl/release/wyrmd \
    --wyrmd-version 0.9.0 [--work dir] [--cache dir] [--base dir]
```

It needs `docker` (or `RUNTIME=podman`), `qemu-system-aarch64` with UEFI
firmware for aarch64 (`QEMU_EFI` names it; Homebrew's `edk2-aarch64-code.fd`
and Ubuntu's `qemu-efi-aarch64` are found), `python3`, `ssh` and
`truncate`. With `--base` it takes a directory with `index.json` and the
raw image of `qemu-armsr` and builds nothing. In this order:

1. `wyr image base --board qemu-armsr`; `verify-table.sh` on the image;
   `wyr image inspect` says `region: empty`.
2. The base image as it is boots: the console says `the broker is not
   started: no configuration is applied on this device`, nothing answers
   TLS on the gateway's port through the forward, and the disk gets no data
   partition. The image has no login, so the guest's loopback is not
   probed: that no broker runs is shown by the console line and the disk.
3. `wyr image build` with a test configuration (`gateway: {listen:
   "0.0.0.0:8445", tls: "site_ca", setup_file: …}`), `--new-setup-code`,
   an SSH key of the run, `--timezone Europe/Kyiv` and three
   `*.openwrt.pool.ntp.org` servers as `--ntp`, on a disk of 1 GiB.
   `smoke_client.py` takes `/api/info` without trust, wants `setup: true`, checks `setup_proof`
   against the code and the CA it presents (and that another code or CA
   fails), pins that CA and from then on verifies the certificate by the
   name `wyrm-smoke.local`: `POST /api/setup` (204), no setup offered, a
   second setup refused (`no_setup`), login and `/api/me`. Through SSH: the
   broker runs as uid 787 and is in the group `dialout` (its id read from
   the guest's `/etc/group`, the broker's groups from `/proc/<pid>/status`),
   uci holds the zone and the NTP servers of the build, `/srv/wyrm` is the
   data partition, which ends at least 1 MiB before the end of the disk; NTP set the clock (the marker
   `/var/run/wyrm/time-synced`), the broker did not wait the full 120 s for
   it, and the site's CA was made after the clock was set.
4. Powered off and booted again: the same CA, no setup offered, the login
   works, NTP set the clock again.
5. On the disk file: `wyr image inspect` says `region: empty`, and
   `verify-table.sh` passes the table the first boot wrote.

A boot may take `--timeout` seconds until the gateway answers TLS: 180 with
`hvf` or `kvm`, 900 under TCG (an aarch64 guest on an x86-64 host boots and
hashes passwords many times slower). With `hvf` on an Apple M4 the first
boot answers after about 32 s, NTP included. The console logs and QEMU's
own output (`<console log>.qemu`) stay in the work directory.

Under TCG the guest's CPU is `cortex-a72`, not `max`. The UEFI firmware of
Ubuntu 26.04 (`qemu-efi-aarch64` 2025.11, `QEMU_EFI.fd`) prints its banner
and then stops on a `max` CPU, with QEMU 10.2 and 11.1 alike, so no guest
boots on a CI runner; with `cortex-a72` it boots. `SMOKE_ACCEL=tcg` runs
TCG on a host that has `hvf` or `kvm`: with `QEMU_EFI` set to Ubuntu's
firmware that is the closest local copy of the CI run.
`.github/workflows/images-smoke.yml` runs it on pull requests that change
`packaging/openwrt`, `packaging/images`, `crates/wyrm-image` or
`tools/wyr/src/image*.rs`: `wyrmd` is built on an arm64 runner, the image
and the boot (TCG) on an x86-64 runner.

### Rust tests

`tools/wyr/tests/boards.rs` reads `boards.json` as any reader does;
`src/image_base.rs` and `src/image_part.rs` have the tests of the strict
reader, the container's arguments, the package's install section and the
tables (MBR, GPT, a GPT image shorter than its partitions with a hybrid
MBR, the vectors of `sgdisk` and `sfdisk`). No test runs a container.
