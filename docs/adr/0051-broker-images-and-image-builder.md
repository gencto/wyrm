# ADR 0051 — Broker images for boards, and a web image builder

Status: proposed (2026-11-25, owner request). Approach D (OpenWrt) and the answers below chosen by the owner on 2026-11-25. Part 1 (the three `wyrmd` features of §1 and §3) built on 2026-11-25, see "Built" below; the rest is not built yet.

## Context

An integrator or an engineer wants a working broker on a device quickly, without building a Linux system by hand (owner, 2026-11-25). Today `wyrmd` ships as a static musl binary, as `scratch` container images (`deploy/docker`) and as signed releases with self-update (`packaging/wyrmd`, ADR 0048). There is no operating system image for a board, and no way to make one.

The owner asks for:
1. A web page, like start.spring.io: pick a board, the links and a few settings, and download an image to write to an SD card or a USB stick. The device then starts as a WYRM broker.
2. Several board implementations, not one. First: Raspberry Pi and Banana Pi BPI-R4 (MediaTek MT7988A).
3. Later, a screen in Studio's login that leads to the same builder, with more detail (links' settings, standby, upstream, history, flows).

The page lives on `wyrm.gencto.uk`, the project's home page, which moves there from a claude.ai artifact (owner, 2026-11-25). That site is a separate piece of work and comes first; this ADR covers the images and the builder.

## Approaches

| | Base | For | Against |
|---|---|---|---|
| A | Debian/Armbian per board, systemd | familiar, `apt` | 400–700 MB, not atomic; no Armbian for BPI-R4 (only the vendor's Debian/Ubuntu on its own 6.12 kernel) |
| B | Buildroot per board, read-only root, A/B slots (RAUC) | 60–120 MB, atomic OS updates | no Buildroot support found for BPI-R4: we would port the vendor's kernel and U-Boot ourselves; ~1 h CI per board |
| C | Alpine Linux | small, musl | weak Banana Pi support |
| **D** | **OpenWrt + a WYRM package feed + OpenWrt ImageBuilder** | supports both boards today (BPI-R4: target `mediatek/filogic`, profile `bananapi_bpi-r4`; Raspberry Pi: target `bcm27xx`); musl like our binaries; small (squashfs + overlay); the ImageBuilder assembles an image from prebuilt packages in minutes without compiling; OpenWrt's own Firmware Selector + ASU server is the same "pick and download" pattern, proven on thousands of devices | init is procd, not systemd; `sysupgrade` replaces the system whole, no A/B rollback of the OS by default; a router OS, less usual on a Raspberry Pi |

Yocto was dropped (heavy for two or three boards), Ubuntu Core and balena too (tied to a vendor store or cloud).

**Chosen: D** (owner, 2026-11-25, on the maintainer's recommendation). One build system covers both boards and new boards come almost free; the pick-and-download mechanism exists. Atomic OS updates can come later if needed; `wyrmd` itself already updates and rolls back through `wyrmd-guard` (ADR 0048).

## Goals

- An integrator goes from "I have a board" to "Studio shows my site" in minutes: open the page, choose, download, write the card, power on, find the broker in Studio.
- The same image works without internet at the plant (links are in the image).
- No secret of the site (CA key, state keys, gateway key, admin password) is made on or passes through our servers.
- Boards are data: adding a board is a row in a board list plus its OpenWrt target/profile, not new code.
- Each image is reproducible: a pinned OpenWrt release, pinned WYRM package versions, recorded in the image.

## Non-goals

- Updating the OS in the field (first version). `wyrmd` updates itself; an OS update is a new image written by hand. Recorded for later.
- Boards OpenWrt does not support.
- x86 mini PCs (possible later through OpenWrt `x86/64`; not asked for now).
- A Studio screen in the first version (it comes after the web builder, on the same backend).

## Anti-goals

- An image that starts with a default password, a shared CA or keys made by the builder: every device makes its own secrets.
- A builder that needs an account or collects data about the person.
- Forking or patching OpenWrt. We add packages and files; the OpenWrt release is used as published.

## Design

### 1. Packages (the WYRM feed)

- Most links are inside `wyrmd` already: the twelve with the form `builtin` in `links/official.json` (modbus, opcua, bacnet, s7, snmp, mqtt, http, prometheus, s3, gdrive, webdav, localfs) and the embedded scheduler, alarm, dql and uplink. For them, choosing a link on the page means a configured instance in the config, not a package.
- The seven links that are packages only (postgres, mysql, mongodb, influxdb, dynamodb, telegram, slack) go into the image in their `wasm` form: one file for every CPU, no per-architecture build. *(maintainer's call)*
- OpenWrt gives each target its own package architecture (`bcm2711` → `aarch64_cortex-a72`, `bcm2712` → `aarch64_cortex-a76`, `filogic` → `aarch64_cortex-a53`). `wyrmd` is one static `aarch64-unknown-linux-musl` binary that runs on all of them; CI packs it once per package architecture of the boards in `boards.json`. *(maintainer's call)*
- Package `wyrmd`: the binary (the first version for the self-update layout, §3), `wyrmd-guard`, a procd init script (`/etc/init.d/wyrmd`: starts through the guard, stop on SIGTERM as `wyrmd` expects, `respawn_retry` at least 8 as ADR 0048 needs), a default `/etc/wyrm/wyrmd.json5`.
- **Seed packages.** A package can not be dropped into `data_dir/packages` at build time: `data_dir` exists only after the first boot, and `Control::open` removes every package directory without a registry record (`packages::clean_orphans`). So the image carries link packages as `.wyrm-link`/zip files in `/usr/share/wyrm/seed/` with a list of the instances to make; on its first start `wyrmd` installs each through the same checks as `install_zip` (registry `PackageDef` + `LinkDef`) and records that the seed is done. New in `wyrmd`. *(maintainer's call)*
- The feed is signed with a key of the project (OpenWrt's own package signing) and published with the release assets.

### 2. Boards

A list `packaging/images/boards.json`: per board an id, a title, the OpenWrt target and profile, the storage it boots from (SD/eMMC/USB), the data partition to make, and notes for the page (how to write the card, which slot to boot from). First rows: `rpi4` (`bcm27xx/bcm2711`), `rpi5` (`bcm27xx/bcm2712`, if the pinned release has it), `bpi-r4` (`mediatek/filogic`, `bananapi_bpi-r4`).

### 3. Storage and first boot

- OpenWrt keeps its root read-only (squashfs) with a small overlay for `/etc`. Broker data (`data_dir`: stores, history, packages, versions for self-update) goes to a separate ext4 data partition, mounted at `/srv/wyrm`, made and sized to the rest of the card on first boot. `sysupgrade` keeps it on both targets (`bcm27xx` writes partition by partition while the layout is the same; `filogic` writes only `production`) **as long as `ROOTFS_PARTSIZE` of a board never changes**: that value is fixed per board in `boards.json` for the life of the board.
- The self-update layout of ADR 0048 (`versions/<v>/wyrmd`, `current`, `bin/wyrmd-guard`) lives on the data partition. The packaged binary only seeds the first version; after a `sysupgrade` the guard keeps starting `current`, even when the new image carries an older binary. *(maintainer's call)*
- Self-update is off in images (`updates.mode: off`) until the project has a release key in `RELEASE_KEYS` (empty today); then images ship `mode: external` with the project channel. *(maintainer's call)*
- **Time.** A Raspberry Pi 4 has no clock and the Pi 5's needs a battery; without NTP the clock starts near the build date. The first start waits up to 2 minutes for NTP before `wyrmd` makes the CA, then goes on and logs a warning; the CA's `notBefore` is the build date minus one day, so a later correct clock does not void it. The page asks for NTP servers (default: the network's DHCP option, then `pool.ntp.org`). *(maintainer's call)*
- **Secrets.** On first boot `wyrmd` makes the site's CA and its keys, as it already does for a new `data_dir` (`Pki::open_or_create`). Nothing of that is in the image.
- **Gateway certificate.** Today `wyrmd` does not make one: a gateway that listens beyond loopback needs `tls_cert`/`tls_key`, and without them DNS-SD and `ca_fp` are off too. New in `wyrmd`: `gateway.tls: "site_ca"` issues the gateway's certificate from the site's CA on first start with the names `<hostname>.local`, `wyrm-<site>.local` and the addresses it has, and issues it again when an address changes. *(maintainer's call)*
- **First admin.** The page makes a one-time **setup code** of 128 random bits in the browser (shown as base32 groups and a QR code), shows it once, and puts only a hash of it into the image, in `/etc/wyrm/setup` (not in `wyrmd.json5`, which `wyrmd` never writes and which refuses unknown fields). On its first start `wyrmd` moves the hash into the users store as a pending setup and deletes the file (as built: into `data_dir/gateway/setup.hash`, 0600, beside the users store and not replicated to a standby, see "Built"); the file is not in the `sysupgrade` keep list. On the first login Studio asks for the code and the new admin password; the gateway checks it, creates the admin and ends the setup (one use). Until then the gateway accepts no other login. 128 bits make an offline guess of the hash useless. (`WYRM_GATEWAY_ADMIN_PASSWORD` stays for other installs.) *(maintainer's call)*
- **Discovery.** The gateway announces itself by DNS-SD (`_wyrm._tcp`, ADR 0050); Studio finds it; the first trust goes through the setup code (answer 3 below).

### 4. The builder

- **Page** `wyrm.gencto.uk/start`: board, site name, network (DHCP / static address / Wi-Fi where the board has it), links (from `official.json`, with their category and summary), time zone, NTP servers. It shows the setup code and the steps to write the card. No login.
- **Assembly in the browser, no build server** (owner, 2026-11-26; replaces the build service of the first draft). CI builds one **base image** per board and release with OpenWrt's ImageBuilder: OpenWrt, `wyrmd`, the guard, and every package-only link in its `wasm` form under `/usr/share/wyrm/seed/`. The image has a small reserved **config region** (4 MiB, raw: no file system to write from JavaScript; the format is below). The page downloads the base image as a static file, keeps it in the browser's storage (OPFS or the Cache API, keyed by its SHA-256 from a signed index, checked after download), writes the chosen configuration into the config region, and hands the person the finished image. Nothing of the person's choices leaves the browser. On first boot a script reads the region, writes `/etc/wyrm/wyrmd.json5`, the network config, `seed.json` (which of the carried links to install) and the setup hash, then wipes the region.
- **The config region** (amended 2026-11-26; replaces "GPT label `wyrm-config` … a length-prefixed archive" of the first text). One implementation writes it: the crate `wyrm-image` (pure, no I/O; it builds for `wasm32-unknown-unknown`, so the page and `wyr image build` run the same code).
  - **Layout.** A fixed byte range of the image, `CONFIG_SIZE` = 4 MiB (4 194 304 bytes): the magic `WYRMCFG1` (8 bytes) · the payload length (u64 little-endian, 8 bytes) · the SHA-256 of the payload (32 bytes) · the payload · zeros to the end of the region. The header is 48 bytes, so the payload is at most `CONFIG_SIZE` − 48 bytes.
  - **Empty region.** The magic `WYRMCFG0` followed by zeros. CI writes it into every base image, and the device leaves it after the first boot.
  - **Payload.** A ustar archive that busybox `tar` reads: regular files only, mode 0600, names without a directory. The names are exactly `wyrmd.json5` (required), `network` (UCI text), `seed.json`, `setup` (the 64 hex digits of the setup hash and one newline), `authorized_keys`, `timezone`, `ntp`. A reader refuses any other name, a name with `/` or `..`, an entry that is no regular file, a name twice and an archive without `wyrmd.json5`.
  - **Found by its offset, not by a label.** The signed index (`wyrm-images/1`: per board `file`, `size`, `sha256`, `config_offset`, `openwrt`, `wyrmd`) records where the region starts in each image. Raspberry Pi images are MBR and filogic images are GPT, so no partition label is common to all boards. Before it writes, an assembler checks the image's size and SHA-256 against its index entry and the eight bytes at the offset: either magic passes, anything else is refused (a wrong offset, another board's entry, a file that is no WYRM image). An image is assembled only from a base image (2026-11-26): the assembler requires the empty magic `WYRMCFG0` at the offset and refuses a region that already holds `WYRMCFG1` (an assembled image is not a base image, and its SHA-256 is no longer the entry's); there is no way to replace a written configuration but to take the base image again. The index may also name the compressed file of an image (`download`: `file`, `size`, `sha256` of the `.gz`), while `file`, `size` and `sha256` stay those of the raw image, in whose bytes the offset counts; a board and a file are plain names without `/`, `\` and `..`.
  - **On the device** the region is a partition, and the image records its device path as `config_dev` in `/etc/wyrm/image.json`. The first-boot script reads the region from that path only. It checks the magic, the length and the SHA-256, unpacks the archive into a staging directory, takes only the listed names from there, and writes `WYRMCFG0` and zeros over the region after everything is in place.
- **Static hosting.** The base images and their signed index are plain files; the host must allow the page's origin to fetch them (CORS) and serve ranges. Where they are hosted is left to the builder (the site's own origin if sizes allow, else an object store behind the same domain).
- **Licences.** The page links each image to the source of the OpenWrt release it was built from and to the WYRM tag of its packages (GPL obligations for the kernel, busybox and board firmware). *(maintainer's call)*
- **Offline**: `wyr image build --board <id> --config <file>` does the same assembly from a downloaded base image, and `wyr image base --board <id>` runs the ImageBuilder steps locally (in a container) from the published feed.
- **Record**: each image carries `/etc/wyrm/image.json` (board, OpenWrt release, package versions, build date, request hash, `config_dev`) so support can tell what is on a device.

### 5. Studio (later)

A screen in the login flow, "New device", that drives the same build service with the detailed settings Studio already edits (links' connections, standby, upstream, history watches, flows), and writes the result into the image's config. It reuses §3 and §4.

## Consequences

- New CI jobs: the feed (per release, per package architecture) and a smoke test that boots OpenWrt `armsr/armv8` in QEMU and starts `wyrmd` from a package of that target. It checks `wyrmd` on OpenWrt, not the board packages; those are checked on the boards.
- `docs/operations.md` gains a section "OpenWrt" beside "systemd": procd script, data partition, logs through `logread`.
- No service to run: CI publishes base images; the page is static (§4).
- `wyrmd` gains: the setup-code first admin, `gateway.tls: "site_ca"`, seed packages on first start (each with tests and `docs/operations.md`).

## Left to the builder

- Package naming inside the feed, the exact procd script, partition layout per board (within §3), the service's language and hosting, cache size, queue limits.
- How the page writes nothing into the image itself (all goes through the ImageBuilder's `FILES` overlay).

## Built (part 1, 2026-11-25)

The three features `wyrmd` needed for an image (Consequences, last line). The OpenWrt packages, `boards.json`, `wyr image build`, the build service, the page and the Studio screen are not built; the status stays `proposed` for them.

- **Gateway certificate from the site CA** (§3). `gateway.tls: "site_ca"` (excludes `tls_cert`/`tls_key`): the broker issues the gateway's certificate from the site CA with the names `<hostname>.local`, `wyrm-<site>.local` and the host's non-loopback addresses (IPv4 and global IPv6; on Linux without temporary, deprecated or tentative IPv6 addresses, read from `/proc/net/if_inet6`, since `if-addrs` gives no flags), or only the listen address when `gateway.listen` is not unspecified. It reads the addresses every 30 s while the gateway serves and issues a new certificate, served from the next connection without a restart, when the names change or less than 30 days are left; a key that does not match its certificate (a torn write) makes a new pair. Files of the operator (`tls_cert`/`tls_key`) are read again at each router rebuild; at the start a pair that cannot be read or does not match stops the broker. A certificate the current site CA did not sign is issued again (a key restore from another site's backup also sets `gateway/tls.{pem,key}` aside). `ca_fp`, the DNS-SD `fp` and `wyrmd ca fingerprint` name the site CA. Documented in `docs/operations.md` ("Gateway TLS from the site CA") and `docs/broker.md`. Tests: `certificate_follows_the_addresses`, `a_due_certificate_is_renewed` and the other tests of `crates/wyrmd/src/gateway_tls.rs`.
- **First admin from a one-time setup code** (§3). `gateway.setup_file` names a file with the SHA-256 (`"wyrm-setup-v1\n"` ‖ the 16 code bytes, 64 hex digits) of a 128-bit code; `wyrmd setup-code` makes a code (26 base32 characters in groups) and its hash. While no user exists, the first start moves the hash into `data_dir/gateway/setup.hash` (0600, not replicated to a standby) and deletes the file; `GET /api/info` shows `setup: true`; `POST /api/setup {code, user, password}` makes that user an admin once (`204`; `409 no_setup`, `403 setup_code_wrong`, `400`, `429` from the login limiter). A setup is void once a user exists (dropped at start). Deviation from §3: the pending hash is kept in `data_dir/gateway/setup.hash`, not in the users store, so it never reaches a standby or a backup of users. The first trust goes through the code in both directions (answer 3): while a setup is pending and the gateway presents a CA, `/api/info` also carries `setup_proof` = HMAC-SHA-256 keyed with the hash over `"wyrm-setup-proof-v1\n"` and the DER of that CA (`ca`); a client verifies it from the typed code (`wyrm_gateway::setup::verify_setup_proof`) and checks that the connection chains to that CA before it sends the code, then pins the CA. The hash is therefore kept like a secret of the image (the device, the image, the build service). Tests: `setup_proof_binds_the_presented_ca`, `setup_proof_is_the_spec`. `WYRM_GATEWAY_ADMIN_PASSWORD` works as before. Documented in `docs/operations.md` ("First admin from a setup code") and `docs/broker.md`. Tests: `code_is_read_as_typed`, `setup_is_void_once_a_user_exists`, `setup_is_rate_limited_like_login`.
- **Seed packages on the first start** (§1). `packages.seed_dir` names a directory with `seed.json` (`format: "wyrm-seed/1"`, `links: [{link, file, accept}]`, ≤ 256 links) and the package zips; each entry is installed once as `install_zip` does, subject `broker:seed`, with the same checks. An existing link is skipped; a failed entry does not stop the others. `data_dir/seed.progress.json` records each install while the seed runs; `data_dir/seed.done` records the outcomes when it ends, and the seed never runs again. Both files are replicated to a standby. Documented in `docs/operations.md` ("Seed packages"), `docs/links.md` and `docs/broker.md`. Tests: `a_broken_seed_entry_does_not_stop_the_others`, `seed_runs_once`, `seed_skips_an_existing_link`.

## Built (part 2, 2026-11-26): the device side

`packaging/openwrt` (package `wyrmd`, guide `packaging/openwrt/README.md`). Decisions of the builder:

- **The first boot runs twice at most per boot**: from `/etc/uci-defaults/90-wyrm-host`, before the network starts, so the device never asks for an address against the person's `network`; and from `/etc/init.d/wyrmd` while the marker `/etc/wyrm/.first-boot-done` is absent, followed by `reload_config`. Exit codes of `first-boot.sh`: 0 applied, 3 empty, 4 refused (nothing applied), 5 not finished (a file could not be put or the region could not be wiped; the region is kept and applied again).
- **Nothing of the archive is trusted.** Names are checked on `tar -t` before `tar -x`; the archive is unpacked only into a staging directory in RAM; a symbolic or hard link is refused; each file is copied into a new file with the mode the script gives. An empty region is told by its magic alone. The wipe is one write of `WYRMCFG0` and zeros over the whole region, read back.
- **`wyrmd.json5` is put last**, so a device that applied half and cannot read its region again still runs the safe default.
- **The broker is started directly**, not through `wyrmd update-guard`, and the package carries no guard, while self-update is off in images (§3). It runs as `root` in this version.
- **Ports.** The firewall opens 8445/tcp, 7448/tcp+udp and mDNS (5353/udp, for the DNS-SD of the gateway). The ports are not read from the configuration; another port needs a rule on the device. The one zone holds the networks `lan`, `wan` and `wan6`.
- **Root.** The password of `root` is locked and the console asks for a login; with `authorized_keys` SSH is on for keys only.
- **Time.** `run.sh` waits for a file that `/etc/hotplug.d/ntp/20-wyrm-time` writes, at most 120 s, only while `data_dir/pki` does not exist.
- **Open:** a boot without a configuration makes the CA and the stores of site `unconfigured` in `/srv/wyrm`. Whether an assembled image written to the same card afterwards may meet that data partition is decided with the image layout (the data partition, `ROOTFS_PARTSIZE`).

Tested: `packaging/openwrt/tests/first_boot.sh` under `dash` and, in CI, under busybox on regions that `wyr image build` writes. Not tested until an image boots in QEMU: the procd service, `90-wyrm-host`, the hotplug script, the package `Makefile`.

## Answers of the owner (2026-11-25)

The owner accepted the maintainer's proposals ("в цілому пропозиція зрозуміла"):
1. **Role on the network: a plain host.** DHCP client by default (static address on the page), no DHCP server, no LuCI, firewall open only for the gateway and the peer ports in the config. Root login and SSH are off unless the page is given an SSH public key; then SSH accepts that key only. A router/firewall role for the BPI-R4 (WAN ↔ equipment network) is a later option.
2. **BPI-R4 storage: the SD card installs onto the eMMC**, the device then runs from the eMMC (OpenWrt's usual path); the data partition is on the eMMC. Both RAM variants are rows in `boards.json` (`bpi-r4` 4 GB `sdcard.img.gz`, `bpi-r4-8g` `sdcard_8g.img.gz`); the PoE variant (`bananapi_bpi-r4-poe`) is a row when someone needs it. Raspberry Pi runs from its SD card (or USB where the board boots from it).
3. **First trust: through the setup code.** (Since the assembly moved into the browser on 2026-11-26, the setup hash is written there and no server sees it; the sentences below about trusting the build service describe the first draft.) The person trusts the build service, which sees the image (not the code). Studio's first login proves the code and pins the CA the device presents in the same session. Next step (later): the page writes the setup secret into the downloaded image in the browser, so the service never sees anything of it. The CA code stays visible in Studio and in `wyrmd ca fingerprint` (console) for those who compare it.

## Not decided here

- OS updates in the field (A/B, or OpenWrt's attended sysupgrade against our feed).
- Hardware tests on the real boards: neither board has been measured yet.
