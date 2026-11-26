# OpenWrt package and first boot (ADR 0051 §1, §3, §4)

What a WYRM board image carries beside OpenWrt as published: the package
`wyrmd` (the broker as a prebuilt binary, its service, the first boot and
the role of the device on the network). The images themselves are built
from `packaging/images` (a later step); the person's side is `wyr image
build` (`docs/operations.md`, "Board images").

| File of the package | What |
|---|---|
| `/usr/bin/wyrmd` | the broker: one static `aarch64-unknown-linux-musl` binary, given to the package as `WYRMD_BIN` |
| `/etc/wyrm/wyrmd.json5` | the default while the image has no configuration: site `unconfigured`, everything on loopback, no setup file |
| `/usr/libexec/wyrm/first-boot.sh` | reads the config region, checks it, puts its files in place, wipes it |
| `/etc/uci-defaults/90-wyrm-host` | the role of a plain host, once; then runs the first boot before the network starts |
| `/etc/init.d/wyrmd` | the procd service (`START=95`); runs the first boot again while its marker is absent |
| `/usr/libexec/wyrm/run.sh` | what procd runs: waits for NTP on the first start (≤ 120 s), then `exec wyrmd -c /etc/wyrm/wyrmd.json5` |
| `/etc/hotplug.d/ntp/20-wyrm-time` | writes `/var/run/wyrm/time-synced` when busybox `ntpd` has the time |
| `/lib/upgrade/keep.d/wyrm` | what a `sysupgrade` keeps: the configuration and the markers, never the setup hash |
| `/usr/share/wyrm/seed/`, `/srv/wyrm/` | the seed packages of the image; the mount point of the data partition |

An image adds `/etc/wyrm/image.json` with `config_dev`, the device path of
the config region (a partition of 4 MiB). The package depends on
`jsonfilter` to read it.

## The first boot

`first-boot.sh` takes what the crate `wyrm-image` writes and refuses what
its reader refuses. In this order, and nothing is changed before step 4:

1. The magic. `WYRMCFG0` is an empty region: exit 3, nothing else is read.
   Neither magic: exit 4.
2. The length (at most 4 MiB − 48), the SHA-256 of the payload, zeros
   after it.
3. The archive. `tar -t` first: only the names `wyrmd.json5`, `network`,
   `seed.json`, `setup`, `authorized_keys`, `timezone`, `ntp`, each once,
   `wyrmd.json5` present. Then `tar -x` into a new staging directory (0700,
   in RAM). Every file must be a regular file with one link and without a
   NUL; `setup` is 64 hex digits; `network` must load as UCI; `timezone`
   is one IANA name; `ntp` holds host names or addresses, at most 16.
4. Apply. Each file is copied into a new file beside its place, given its
   mode by the script and renamed over the place. The modes and owners of
   the archive are never used.

   | File | Place | Mode |
   |---|---|---|
   | `setup` | `/etc/wyrm/setup` | 0600 |
   | `seed.json` | `/usr/share/wyrm/seed/seed.json` | 0644 |
   | `network` | `/etc/config/network` | 0600 |
   | `authorized_keys` | `/etc/dropbear/authorized_keys` | 0600; SSH on, keys only; firewall rule `wyrm_ssh` on |
   | `timezone` | UCI `system.@system[0].zonename` and `.timezone` | |
   | `ntp` | UCI `system.ntp.server` | |
   | `wyrmd.json5` | `/etc/wyrm/wyrmd.json5` | 0640; last |

5. `/etc/wyrm/.first-boot-applied` records that every file is in place.
6. Wipe: one `dd` writes `WYRMCFG0` and zeros over the whole region, then
   `sync`, then a read back. Then the marker `/etc/wyrm/.first-boot-done`.

| Exit code | Meaning |
|---|---|
| 0 | applied, region wiped, marker written |
| 3 | empty region: nothing to do, nothing changed |
| 4 | refused: damaged, or something not allowed; nothing applied |
| 5 | not finished: a file could not be put or the region could not be wiped; the region is kept |

A power loss before the wipe leaves a full region and no marker, and the
next boot applies the region again as a whole: renames overwrite.
`wyrmd.json5` goes last, so a device that cannot read its region a second
time still has the safe default. A power loss between the wipe and the
marker leaves an empty region beside `.first-boot-applied`: the next boot
writes the marker and exits 3.

Rules for the person's configuration (`wyr image build`):

- `setup` is taken by the broker only when `wyrmd.json5` says
  `gateway: { setup_file: "/etc/wyrm/setup" }`. The broker removes the file
  when it has the hash.
- `seed.json` is used only with `packages: { seed_dir: "/usr/share/wyrm/seed" }`.
- `data_dir` is `/srv/wyrm` (the data partition). A relative `data_dir`
  is relative to `/srv/wyrm`.
- The time zone needs the zone's file in the image (`zoneinfo-*`
  packages): its last line is the POSIX rule OpenWrt wants. Without the
  file the first boot warns and the clock stays UTC. The broker's own
  schedules use the tzdb inside `wyrmd` and do not depend on this.
- A `network` file replaces `/etc/config/network` as a whole. Keep the
  interface names `lan`, `wan` and `wan6`: the firewall opens the broker's
  ports for those names only.

## The role of the device

`90-wyrm-host` makes the device a plain host (owner's answer 1 of ADR 0051):

- `lan` is a DHCP client. No DHCP server, no router advertisements.
- One firewall zone (OpenWrt's `wan`, input REJECT) holds `lan`, `wan` and
  `wan6`. Open: 8445/tcp (gateway), 7448/tcp+udp (peer and TLS listeners),
  5353/udp (mDNS: how Studio finds the gateway). A configuration that
  listens on another port is not reachable until a firewall rule is added
  on the device; the config region carries no firewall file.
- SSH is off, the console asks for a login and the password of `root` is
  locked. With `authorized_keys` in the region SSH is on for those keys
  only (`PasswordAuth off`, `RootPasswordAuth off`).
- The broker runs as `root` in this version. A user of its own needs rules
  for serial ports and the setup file; that is a later step.

The script leaves `/etc/wyrm/.host-role-done`. A `sysupgrade` keeps that
file while the script comes back with the new image, so the role is not
applied over a network that is set up.

## The service

`/etc/init.d/wyrmd` starts `run.sh` under procd with `respawn 3600 5 8`,
20 s for a clean stop on SIGTERM and 16 384 open files. The broker is not
started through `wyrmd update-guard`: self-update is off in images
(ADR 0051 §3). Logs: `logread -e wyrm`.

## Tests

```
SH=dash packaging/openwrt/tests/first_boot.sh
SH="busybox sh" BB=busybox packaging/openwrt/tests/first_boot.sh   # as CI runs it
```

The regions the script must accept are made by `wyr image build`, so the
busybox run proves that busybox unpacks what `wyrm-image` writes. The
regions it must refuse come from `tests/mkregion.py`. Every script passes
`shellcheck -s sh`.

Not tested here, only in an image that boots (the QEMU smoke test of
`packaging/images`): the procd service, `90-wyrm-host`, the hotplug script,
the package `Makefile`, and `first-boot.sh` on OpenWrt's own busybox with a
real `uci` and a block device.
