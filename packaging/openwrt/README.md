# OpenWrt package and first boot (ADR 0051 §1, §3, §4)

What a WYRM board image carries beside OpenWrt as published: the package
`wyrmd` (the broker as a prebuilt binary, its service, the first boot and
the role of the device on the network). The images themselves are built
by `wyr image base` from `packaging/images` (its `README.md`); the person's
side is `wyr image build` (`docs/operations.md`, "Board images").

| File of the package | What |
|---|---|
| `/usr/bin/wyrmd` | the broker: one static `aarch64-unknown-linux-musl` binary, given to the package as `WYRMD_BIN` |
| `/etc/wyrm/wyrmd.json5` | a placeholder until the first boot puts the person's file; the broker never runs with it (valid and loopback-only all the same) |
| `/usr/libexec/wyrm/first-boot.sh` | reads the config region, checks it, puts its files in place, wipes it |
| `/usr/libexec/wyrm/data-part.sh` | makes the data partition at the first boot, mounts it at `/srv/wyrm-part` and its `broker` directory at `/srv/wyrm` at every boot, keeps the data of another site apart |
| `/usr/libexec/wyrm/disk.sh` | tells the disk the root file system is on and its partitions by number |
| `/usr/libexec/wyrm/site.sh` | reads the site of a `wyrmd.json5` |
| `/etc/uci-defaults/80-wyrm-user` | makes the user and the group `wyrm` (787) where the package's `USERID` did not (an image takes the package as files) |
| `/etc/uci-defaults/90-wyrm-host` | the role of a plain host, once; then runs the first boot before the network starts |
| `/etc/init.d/wyrmd` | the procd service (`START=95`); runs the first boot again while its marker is absent; starts the broker only on a device with an applied configuration and a mounted data partition; the first boot and the data partition script run only while no broker runs (asked of procd through `ubus`): a start beside a running broker changes nothing, a stop waits until the broker has ended (at most 30 s), and `reload` is a restart |
| `/usr/libexec/wyrm/run.sh` | what procd runs as the user `wyrm`: waits for NTP on the first start (≤ 120 s), then `exec wyrmd -c /etc/wyrm/wyrmd.json5` |
| `/etc/hotplug.d/ntp/20-wyrm-time` | writes `/var/run/wyrm/time-synced` when busybox `ntpd` has the time |
| `/lib/upgrade/keep.d/wyrm` | what a `sysupgrade` keeps: the configuration and the markers, never the setup hash |
| `/usr/share/wyrm/seed/`, `/srv/wyrm/` | the seed packages of the image; the broker's `data_dir` (the `broker` directory of the data partition) |

An image adds `/etc/wyrm/image.json` with `config_part` and `data_part`,
the numbers of the config region (a partition of 4 MiB) and of the data
partition, and `config_dev`, the usual device path of the region. The
package depends on `jsonfilter` to read it and on `sfdisk`, `partx-utils`,
`e2fsprogs`, `tune2fs`, `blkid` and `kmod-fs-ext4` for the data partition.

The modes of the files are those of the package's `Makefile`
(`INSTALL_BIN` 0755, `INSTALL_DATA` 0644, `INSTALL_CONF` 0600). `wyr image
base` reads that section and stages an image's files from it, so a feed
package and an image hold the same files with the same modes; a file of
`files/` that the section does not install fails the build.

## Which disk

The scripts never take a device by a fixed name. `disk.sh` finds the disk
from the device the root file system is mounted from (`/rom` below the
overlay, else `/`), and a partition by its number on that disk, as the
kernel names it. A Raspberry Pi that starts from a USB stick or an NVMe
disk finds its config region and its data partition there. On
`mediatek/filogic` the root is a FIT block device and no partition; there
the disk is the one the boot loader names in the device tree
(`/chosen/rootdisk`). That path is written from OpenWrt's own sysupgrade
code and is not tried on a board. The first boot falls back to `config_dev`
of `image.json` when the disk cannot be told (the region's magic and
SHA-256 are checked whatever the path); the data partition script touches
nothing then.

## The first boot

`first-boot.sh` takes what the crate `wyrm-image` writes, and refuses a
region its reader (`read_region`) refuses for its structure: the magic,
the length, the SHA-256, the zeros, the names, links, a NUL, a `setup`
that is no hash. Two things differ. The script does not check UTF-8
(`wyrmd` refuses such a configuration itself), and it checks more of the
content (`network` as UCI, `timezone`, `ntp`, keys without an SSH
server). Whether `wyrmd.json5` names the setup file and the seed
directory is checked by the assembler only, neither by the reader nor
here. In this order, and nothing is changed before step 4:

1. The magic. `WYRMCFG0` is an empty region: exit 3, nothing else is read.
   Neither magic: exit 4.
2. The length (at most 4 MiB − 48), the SHA-256 of the payload, zeros
   after it.
3. The archive. `tar -t` first: only the names `wyrmd.json5`, `network`,
   `seed.json`, `setup`, `authorized_keys`, `timezone`, `ntp`, each once,
   `wyrmd.json5` present. Then `tar -x` into a new staging directory (0700,
   in RAM). Every file must be a regular file with one link and without a
   NUL; `setup` is 64 hex digits; `network` must load as UCI; `timezone`
   is one IANA name; `ntp` holds host names or addresses, at most 16;
   `authorized_keys` needs the image's dropbear and the firewall rule
   `wyrm_ssh` ("this image has no SSH server", exit 4).
4. Apply. Each file is copied into a new file beside its place, given its
   mode by the script and renamed over the place. The modes and owners of
   the archive are never used.

   | File | Place | Mode |
   |---|---|---|
   | `setup` | `/etc/wyrm/setup.d/setup` | 0640 `root:wyrm`; the directory 0770 `root:wyrm` |
   | `seed.json` | `/usr/share/wyrm/seed/seed.json` | 0644 |
   | `network` | `/etc/config/network` | 0600 |
   | `authorized_keys` | `/etc/dropbear/authorized_keys` | 0600; SSH on, keys only; firewall rule `wyrm_ssh` on; a `uci` call that fails here is exit 5 |
   | `timezone` | UCI `system.@system[0].zonename` and `.timezone` | |
   | `ntp` | UCI `system.ntp.server` | |
   | `wyrmd.json5` | `/etc/wyrm/wyrmd.json5` | 0640 `root:wyrm`; last |

5. `/etc/wyrm/.first-boot-applied` records that every file is in place.
6. Wipe: one `dd` writes `WYRMCFG0` and zeros over the whole region, then
   `sync`. The script reads the region back, but through the page cache:
   that shows the write was taken, it does not verify the medium. Then the
   marker `/etc/wyrm/.first-boot-done`.

| Exit code | Meaning |
|---|---|
| 0 | applied, region wiped, marker written |
| 3 | empty region: nothing to do, nothing changed |
| 4 | refused: damaged, or something not allowed; nothing applied |
| 5 | not finished: a file could not be put, SSH could not be set up for the keys, or the region could not be wiped; the region is kept |

A power loss before the wipe leaves a full region and no marker, and the
next boot applies the region again as a whole: renames overwrite.
`wyrmd.json5` goes last and `.first-boot-applied` after it, so a device
that cannot read its region a second time starts no broker on half of a
configuration. A power loss during the wipe or between the wipe and the
marker leaves an empty magic beside `.first-boot-applied` (the magic is
written first, the old payload may lie behind it): the next boot wipes the
whole region again, writes the marker and exits 3.

The name check is of the whole name, one `case` per line of `tar -t`. A
name with a space, a pattern character or a line break is refused.

The setup hash lies in a directory of its own because the broker removes
the file when it has the hash, and a user removes a file only from a
directory it may write. `/etc/wyrm` itself stays root's, so the broker
cannot replace its own configuration. Root does not write into a
directory another user may write: the first boot removes `setup.d` with
whatever is in it, makes it new and root's alone, puts the file, and only
then opens the directory to the group `wyrm`. Group changes never follow
a link (`chgrp -h`), a directory at a file's place is exit 5, and the
init script gives `/srv/wyrm` itself to `wyrm` (`chown -h`, never
recursive) and starts nothing when it is a link.

Rules for the person's configuration (`wyr image build`):

- `setup` is taken by the broker only when `wyrmd.json5` says
  `gateway: { setup_file: "/etc/wyrm/setup.d/setup" }`. The broker removes
  the file when it has the hash.
- `seed.json` is used only with `packages: { seed_dir: "/usr/share/wyrm/seed" }`.
- Both paths are constants of the crate `wyrm-image` (`SETUP_FILE`,
  `SEED_DIR`), and `wyr image build` refuses a configuration that carries
  `setup` or `seed.json` without naming its path. The check reads the text
  as tokens, without a JSON5 parser: a comment or the content of a string
  does not count; the section that holds the key is not looked at.
- `data_dir: "/srv/wyrm"` (the data partition) in the outermost object.
  `wyr image build` refuses another path, a relative one and none
  (`wyrmd`'s default is `./data`): `run.sh` tells a first start by
  `/srv/wyrm/pki`.
- `site` in the outermost object, once: 1 to 64 of `A-Z a-z 0-9 _ . -`,
  not starting with `.` (`site.sh`; the broker takes every such name).
  `data-part.sh` names a directory after it, so the first boot refuses a
  configuration without such a site (exit 4, the region kept) before it
  applies anything; `wyr image build` refuses it first.
- `timezone`: one IANA name of `A-Z a-z 0-9 _ + / -`, not starting with
  `/`, without `..`. `ntp`: at most 16 lines, each a host name or an
  address of `A-Z a-z 0-9 . : _ -`, not starting with `-` (an IPv6 address
  without brackets). The first boot refuses anything else (exit 4).
- These rules are written once on each side: `site.sh` (`SITE_CHARS`,
  `SITE_MAX`) and `first-boot.sh` (`TZ_CHARS`, `NTP_CHARS`, `NTP_MAX`) on
  the device, `ConfigFiles::check_device` of the crate `wyrm-image` in the
  tool. The crate's test `a_rule_is_the_one_of_the_device` reads the
  scripts and fails when the two differ.
- The time zone needs the zone's file in the image (`zoneinfo-*`
  packages): its last line is the POSIX rule OpenWrt wants. Without the
  file the first boot warns and the clock stays UTC. The broker's own
  schedules use the tzdb inside `wyrmd` and do not depend on this.
- A `network` file replaces `/etc/config/network` as a whole. Keep the
  interface names `lan`, `wan` and `wan6`: the firewall opens the broker's
  ports for those names only.

## The data partition

`data-part.sh` runs from the service before the broker, at every boot.
Its exit 0 means: `/srv/wyrm` is the `broker` directory of the mounted
data partition and holds the data of the site of `/etc/wyrm/wyrmd.json5`.
Otherwise the service starts no broker and the console says why. The
service runs it only while no broker runs.

The layout. The partition is mounted at `/srv/wyrm-part`, which belongs to
root (0700). It holds `.site` (root's), `broker` (`wyrm:wyrm` 0700, the
broker's data) and the data of other sites as `.replaced-<site>-<n>`.
`broker` is bind-mounted at `/srv/wyrm`, the `data_dir` of the
configuration; the broker's user cannot reach the rest. **Root never acts
inside a directory the broker's user can write**: it renames `broker` as a
whole and writes `.site`, both in the directory above, which only root
writes.

1. **The disk is proven.** The disk of the root file system must have the
   partition `config_part`, of exactly 8192 sectors, starting with
   `WYRMCFG0` or `WYRMCFG1`. If not, nothing is touched.
2. **The partition.** When the table has no partition `data_part`, the
   script adds it from 1 MiB after the end of the config region to at least
   1 MiB before the end of the card, after a GPT's second table, on a 1 MiB
   boundary (`sfdisk --append` with `start=` and `size=`; imagers zero the
   last MiB of a drive). A partition `data_part` that was there must start
   at that sector, else nothing is touched and no broker starts. A base image ends at most there (a GPT
   image keeps that MiB for its second table), so an image written again
   over the card leaves the file system whole. On a GPT it first moves the second table to the end
   of the card (`sfdisk --relocate gpt-bak-std`); a hybrid MBR (the entry
   of a boot loader beside the one of type `EE`, as on `mediatek/filogic`)
   is read before and put back after, byte for byte. A card where the
   partition would be smaller than 32 MiB gets none (console message, no
   broker).
3. **Formatting has two rules.** A partition that was there before this
   boot is **never** formatted. A partition this run added is formatted,
   unless it already holds the label `wyrm-data`: that is the data of a
   card whose image was written again, and it is kept. `mkfs.ext4` gives
   the label `wyrm-new`; `wyrm-data` is set when it has ended well.
4. `e2fsck -p` before every mount; from exit 4 on, no mount and no broker.
5. Mounted at `/srv/wyrm-part` with `nosuid,nodev,noatime`; then the site
   rule; then `broker` is bind-mounted at `/srv/wyrm` (a bind mount of an
   earlier start is unmounted first, so it never follows a renamed
   directory). The service starts the broker only when `/srv/wyrm` is the
   mount of that device.

A power loss between step 2 and the end of step 3 leaves a partition
without the label: the next boot formats nothing and starts no broker.
Write the image to the card again; the partition is then a new entry of
that run.

**The site rule.** `/srv/wyrm-part/.site` names the site whose data
`broker` holds. When the configuration names another site (a card written
again with another configuration), `broker` is renamed to
`/srv/wyrm-part/.replaced-<old site>-<n>`: never merged, never deleted, and
nothing inside it is opened. The console says so and the broker starts on a
new, empty `broker`. The same site keeps its data. A `broker` without a
`.site` that names a site is set aside as `.replaced-unknown-<n>`, never
adopted; a site that is called `unknown` is told apart from that by a flag,
not by the name. `.site` is written before
the new `broker` is made, so a run that is cut sets nothing aside twice.

`ROOTFS_PARTSIZE` and the layout before the config region must not change
between two images of a board, or the partition the new image's first boot
adds starts elsewhere and the old data is not found
(`packaging/images/README.md`).

## The role of the device

`90-wyrm-host` makes the device a plain host (owner's answer 1 of ADR 0051):

- `lan` is a DHCP client. No DHCP server, no router advertisements.
- One firewall zone (OpenWrt's `wan`, input REJECT) holds `lan`, `wan` and
  `wan6`; the default rules into the removed zone `lan` go with it. Open:
  8445/tcp (gateway), 7448/tcp+udp (peer and TLS listeners), 5353/udp
  (mDNS: the gateway announces itself by DNS-SD, and that is how Studio
  finds the device, ADR 0050). A configuration that
  listens on another port is not reachable until a firewall rule is added
  on the device; the config region carries no firewall file.
- SSH is off, the console asks for a login and the password of `root` is
  locked. With `authorized_keys` in the region SSH is on for those keys
  only (`PasswordAuth off`, `RootPasswordAuth off`).
- The broker runs as the user `wyrm` (uid and gid 787), with
  `no_new_privs`, as the systemd unit of
  `docs/operations.md` runs it. `/srv/wyrm` is `wyrm:wyrm` 0700. The user
  is in the group `dialout` for serial ports. The first boot and this
  script run as root. The user is made by `USERID` when the package is
  installed from a feed. An image takes the package as files, and there
  `/etc/uci-defaults/80-wyrm-user` of this package makes it, before this
  script runs (`packaging/images/README.md`, "The broker's
  user": 787 is free in the pinned release).

The service names the device `wyrm-<site>` before the broker starts, so the
gateway's certificate from the site CA and the network show which broker it
is. Only OpenWrt's own name (`OpenWrt`) and a name of this form are
replaced; a name a person gave stays. A site that is no host name (an
underscore, a dot) leaves the name alone.

The script leaves `/etc/wyrm/.host-role-done`. A `sysupgrade` keeps that
file while the script comes back with the new image, so the role is not
applied over a network that is set up.

## The service

**No configuration, no broker.** While `/etc/wyrm/.first-boot-applied` is
absent (a base image written as it is, a region that was refused) the
service starts no instance: nothing listens, and no CA or store of a site
nobody chose is made on the data partition, where an assembled image
written later would meet it. The console and the log say, once per boot,
that the image has no configuration and how to assemble one (`wyr image
build`, the guide's URL).

Otherwise `/etc/init.d/wyrmd` starts `run.sh` under procd as `wyrm` with
`respawn 3600 5 8`, 20 s for a clean stop on SIGTERM, 16 384 open
files and `NO_COLOR=1` (the log daemon takes the lines). The broker is not
started through `wyrmd update-guard`: self-update is off in images
(ADR 0051 §3). Logs: `logread -e wyrm`.

## Tests

```
SH=dash packaging/openwrt/tests/first_boot.sh
SH="busybox sh" BB=busybox packaging/openwrt/tests/first_boot.sh   # as CI runs it
SH=dash packaging/openwrt/tests/data_part.sh
SH="busybox sh" BB=busybox packaging/openwrt/tests/data_part.sh
```

`data_part.sh` tests what the data partition script decides (which disk,
when it formats, the order of its steps, the hybrid MBR, the site rule),
the disk finder and the site reader. The tools that touch a disk are
stand-ins there that record their calls; the real tools run in an image
that boots.

The regions the script must accept are made by `wyr image build`, so the
busybox run proves that busybox unpacks what `wyrm-image` writes. The
regions it must refuse come from `tests/mkregion.py`. Every script passes
`shellcheck -s sh`.

Not tested here, only in an image that boots (the QEMU smoke test of
`packaging/images`): the procd service, `90-wyrm-host`, the hotplug script,
the package `Makefile`, and `first-boot.sh` on OpenWrt's own busybox with a
real `uci` and a block device.
