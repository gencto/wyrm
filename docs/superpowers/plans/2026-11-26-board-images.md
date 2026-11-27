# Board images (ADR 0051, part 2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** CI can build a base OpenWrt image per board that carries `wyrmd`, and one tool turns a base image plus a person's choices into a finished image that boots as a configured WYRM broker — with the same assembly code ready to run in a browser.

**Architecture:** One pure Rust crate `wyrm-image` owns the **config region** format and the assembly (find the region in an image, write the archive); it builds natively (used by `wyr image`) and for `wasm32-unknown-unknown` (used by the page in part 3), so there is one implementation. The device side is a POSIX shell first-boot script in an OpenWrt package, reading the same format with busybox tools. Base images come from OpenWrt's ImageBuilder run in a container, described by `packaging/images/boards.json`.

**Tech Stack:** Rust (no new heavy deps: `sha2`, `serde`/`serde_json` for the index and `boards.json` as user files), POSIX sh + busybox (`dd`, `tar`, `sha256sum`), OpenWrt ImageBuilder (pinned release), QEMU `armsr/armv8` for the smoke test, GitHub Actions.

**Spec:** `docs/adr/0051-broker-images-and-image-builder.md` §1–§4 (as amended 2026-11-26: assembly in the browser, no build server).

## Global Constraints

- Root CLAUDE.md "Conventions" and `docs/rust-rules.md` (no `unwrap`/`expect` in product code, typed errors, rule checker at baseline, no `allow` markers).
- No secret of a site is in a base image or passes through CI: the config archive is written by the person's tool (later: browser). The setup hash is private to the image (ADR 0051 "Built", T14).
- OpenWrt is used as published: a pinned release (`OPENWRT_RELEASE` in `boards.json`), no patches, no fork.
- **Config region format** (decided here, ADR amended in Task 1): a fixed byte range of the image, `CONFIG_SIZE` = 4 MiB, at an offset recorded per image in the index. Content: magic `WYRMCFG1` (8 bytes) · payload length (u64 little-endian) · SHA-256 of the payload (32 bytes) · payload = a ustar archive · zero padding. An empty region is magic `WYRMCFG0` followed by zeros (written by CI; an assembler refuses a region that has neither magic). Files in the archive (all optional except the first): `wyrmd.json5`, `network` (UCI text), `seed.json`, `setup` (64 hex chars), `authorized_keys`, `timezone`, `ntp`.
- The region is located by its recorded offset, not by a partition label (Raspberry Pi images are MBR, filogic images GPT). On the device it is a partition whose device path the image records in `/etc/wyrm/image.json` (`config_dev`).
- Device role (owner answer 1): a plain host — DHCP client by default, no DHCP server, no LuCI, firewall open only for the gateway and peer ports and 5353/udp (mDNS: DNS-SD is how Studio finds the device, ADR 0050), root login and SSH off unless `authorized_keys` is present (then key-only).
- `ROOTFS_PARTSIZE` of a board is fixed for the life of the board (kept in `boards.json`; a test refuses a change of an existing row's value).
- Boards of the first version: `rpi4` (`bcm27xx/bcm2711`), `rpi5` (`bcm27xx/bcm2712`), `bpi-r4` and `bpi-r4-8g` (`mediatek/filogic`, SD installs to eMMC), plus `qemu-armsr` (`armsr/armv8`) for tests only.
- Workflows that need secrets or publish are added under `packaging/images/` and copied to `.github/workflows/` by the owner (as the other release workflows are); the smoke test runs in normal CI only when its paths change.
- Checks before each commit: `cargo fmt --all --check`, `cargo clippy --workspace --all-targets -- -D warnings`, the touched crates' tests, `python3 tool/check_rust_rules.py`; shell scripts pass `shellcheck -s sh` and run under `busybox sh`.

## Review Focus

1. A config archive larger than the region, or with a file name outside the allowed list, or with `..`/absolute paths, is refused by the assembler AND ignored by the device script (never unpacked outside its staging dir). → Tasks 1 and 3.
2. Power loss during first boot: the script is idempotent — it applies from a staging dir with renames, and wipes the region only after everything is in place; a second boot with a wiped region changes nothing. → Task 3 test `first_boot_twice`.
3. An image with an empty region (`WYRMCFG0`) boots to a safe state: the broker does not start, nothing listens, the console says how to assemble. → Task 3 + smoke test.
4. Assembling the wrong board's config or writing at a wrong offset is caught: the assembler checks the magic at the offset and the image's SHA-256 against the index before writing. → Task 1 tests.
5. The data partition survives a re-flash of the same board's newer base image only if the layout is unchanged; the tool says so and the test pins `ROOTFS_PARTSIZE`. → Task 4.

---

### Task 1: Crate `wyrm-image` — the config region and the assembly

**Files:** Create `crates/wyrm-image/{Cargo.toml,src/lib.rs,src/region.rs,src/tar.rs,src/index.rs}`, tests `crates/wyrm-image/tests/assemble.rs`; modify workspace `Cargo.toml`, `docs/adr/0051-…md` (format amendment), `.github/workflows/ci.yml` (one line: `cargo build -p wyrm-image --target wasm32-unknown-unknown`).

**Interfaces — Produces:**
- `pub const CONFIG_SIZE: u64 = 4 * 1024 * 1024; pub const MAGIC_FULL: &[u8; 8] = b"WYRMCFG1"; pub const MAGIC_EMPTY: &[u8; 8] = b"WYRMCFG0";`
- `pub struct ConfigFiles { pub wyrmd_json5: String, pub network: Option<String>, pub seed_json: Option<String>, pub setup: Option<String>, pub authorized_keys: Option<String>, pub timezone: Option<String>, pub ntp: Option<String> }` with `pub fn check(&self) -> Result<(), ImageError>` (`setup` = 64 hex chars; sizes; no NUL).
- `pub fn region(files: &ConfigFiles) -> Result<Vec<u8>, ImageError>` — the full 4 MiB region bytes.
- `pub fn read_region(bytes: &[u8]) -> Result<Option<ConfigFiles>, ImageError>` — `None` for an empty region; verifies length and SHA-256; refuses unknown names.
- `pub struct ImageEntry { pub board: String, pub file: String, pub size: u64, pub sha256: String, pub config_offset: u64, pub openwrt: String, pub wyrmd: String }`, `pub struct Index { pub format: String /* "wyrm-images/1" */, pub images: Vec<ImageEntry> }` (serde).
- `pub fn check_slot(at_offset: &[u8; 8]) -> Result<(), ImageError>` (either magic, else `ImageError::NoRegion`).
- `pub enum ImageError` (thiserror): `TooLarge`, `BadName`, `BadSetup`, `NoRegion`, `Damaged`, `Index(..)`.
- The crate has no I/O and no `std::fs`: callers give bytes and write bytes (so it runs in a browser).

- [ ] Write failing tests: `region_round_trips` (all files), `empty_region_reads_as_none`, `a_region_too_large_is_refused` (4 MiB + 1 of payload), `names_outside_the_list_are_refused` (hand-built tar with `../x` and `extra`), `a_flipped_byte_is_damaged`, `check_slot_knows_both_magics`, `index_parses_and_refuses_another_format`.
- [ ] Implement (own minimal ustar writer/reader: regular files only, names ≤ 100 bytes, mode 0600).
- [ ] `cargo test -p wyrm-image`; `cargo build -p wyrm-image --target wasm32-unknown-unknown`.
- [ ] Amend ADR 0051 §4 with the format of Global Constraints (replace "GPT label `wyrm-config`… length-prefixed archive" by the exact layout and "located by offset from the index").
- [ ] Commit `wyrm-image: the config region of a board image (ADR 0051 §4)`.

### Task 2: `wyr image build` and `wyr image inspect`

**Files:** Create `tools/wyr/src/image.rs`; modify `tools/wyr/src/main.rs`, `tools/wyr/Cargo.toml`; test `tools/wyr/tests/image.rs`; docs `docs/operations.md` ("Board images").

**Interfaces — Consumes:** Task 1. **Produces:** `wyr image build --image <base.img[.gz]> --index <index.json> --board <id> --config <wyrmd.json5> [--network <file>] [--seed <seed.json>] [--setup-hash <hex> | --new-setup-code] [--authorized-keys <file>] [--timezone <tz>] [--ntp <servers>] --out <file.img>`: checks the image's SHA-256 and size against the index entry, `check_slot` at `config_offset`, writes the region, prints the output path; with `--new-setup-code` prints the code once (uses `wyrm_gateway::setup::new_code`). `wyr image inspect --image <file> --index <index.json> --board <id>`: prints the file names in the region (never `setup`'s value).

- [ ] Failing tests with a synthetic 8 MiB "image" (zeros, `WYRMCFG0` at a chosen offset, an index made for it): `build_writes_the_region`, `a_wrong_sha_is_refused`, `a_wrong_offset_is_refused` (index offset pointing at zeros), `gz_input_is_unpacked` (flate2 is already a workspace dep — check; else read `.img` only and say so), `inspect_hides_the_setup_hash`.
- [ ] Implement; streaming copy, the region patched in place in the output file.
- [ ] Docs; commit `wyr: image build and inspect (ADR 0051 §4)`.

### Task 3: The OpenWrt side — package files and the first-boot script

**Files:** Create `packaging/openwrt/wyrmd/files/etc/init.d/wyrmd` (procd, through `wyrmd-guard`… see below), `packaging/openwrt/wyrmd/files/usr/libexec/wyrm/first-boot.sh`, `…/files/etc/uci-defaults/90-wyrm-host`, `…/files/etc/wyrm/wyrmd.json5` (safe default: gateway on loopback), `packaging/openwrt/wyrmd/Makefile` (OpenWrt package of a prebuilt binary), `packaging/openwrt/README.md`; tests `packaging/openwrt/tests/first_boot.sh` + a CI step.

**Interfaces — Consumes:** the region format (Global Constraints). **Produces:** `first-boot.sh <config_dev> <stage_dir> <etc_dir>` (arguments so the test runs it against plain files): reads magic/length/hash with `dd`+`sha256sum`, unpacks with `tar -x` into `<stage_dir>` only after checking every member name against the allowed list (`tar -t` first; any other name → abort, nothing applied), moves files into place by rename (`wyrmd.json5` → `<etc_dir>/wyrm/wyrmd.json5`, `setup` → `<etc_dir>/wyrm/setup` 0600, `seed.json` → `/usr/share/wyrm/seed/seed.json` path given by a variable, `network` → UCI import, `authorized_keys` → dropbear's file + enable key-only SSH, `timezone`/`ntp` → UCI), then overwrites the region with `WYRMCFG0` + zeros and syncs. Exit codes: 0 applied, 3 empty region (nothing to do), 4 damaged/refused (nothing applied, message on the console).
The init script: `START=95`, `USE_PROCD=1`, runs `first-boot.sh` once before the service when `/etc/wyrm/.first-boot-done` is absent, waits up to 120 s for NTP (`ntpd` stratum check or `/var/state/ntp` — builder's choice, bounded), sets `respawn 3600 5 8`, starts `wyrmd -c /etc/wyrm/wyrmd.json5` with `data_dir` on `/srv/wyrm` (through `wyrmd update-guard` only when the install layout exists; plain `wyrmd` otherwise — self-update is off in images per ADR §3).
`90-wyrm-host`: DHCP client on the LAN/WAN bridge, `dnsmasq` DHCP server off, no LuCI packages assumed, firewall zone input REJECT except the ports in `/etc/wyrm/ports` (gateway 8445, peers), dropbear disabled unless `authorized_keys` was applied (then `PasswordAuth off`, `RootPasswordAuth off`).

- [ ] Write `tests/first_boot.sh` (runs under `busybox sh` and `dash`): builds regions with a tiny helper (`cargo run -p wyr -- image build` on a synthetic image, or a 30-line Python writer in the test dir), then checks: `applies_all_files`, `first_boot_twice` (second run exits 3, files unchanged), `empty_region_exits_3`, `a_flipped_byte_applies_nothing` (exit 4), `a_bad_member_name_applies_nothing` (`../etc/passwd`, `extra`), `setup_is_0600`.
- [ ] Implement the script and files; `shellcheck -s sh` clean.
- [ ] CI: a job step in `ci.yml` (paths `packaging/openwrt/**`, `crates/wyrm-image/**`) running the tests with busybox (apt `busybox-static`) and shellcheck.
- [ ] Commit `packaging/openwrt: wyrmd package files and the first boot (ADR 0051 §1, §3)`.

### Task 4: `boards.json` and `wyr image base`

**Files:** Create `packaging/images/boards.json`, `packaging/images/README.md`, `tools/wyr/src/image_base.rs`; modify `tools/wyr/src/image.rs`; test `tools/wyr/tests/boards.rs`.

**Interfaces — Produces:** `boards.json`: `{"format":"wyrm-boards/1","openwrt":"<pinned release>","boards":[{"id","title","target","profile","arch","image" (the ImageBuilder output file to take, e.g. `…-sdcard.img.gz` / `…-factory.img.gz`),"rootfs_partsize_mb","config_part" (how the reserved region is added: `"append"`),"config_dev" (device path on the board),"data_dev","boot_from","notes"}]}`. `wyr image base --board <id> --wyrmd <binary> --seed-dir <dir> --out <dir>`: runs the pinned ImageBuilder in a container (`docker`/`podman`), with `FILES=` the overlay from `packaging/openwrt` + the binary + the seed files, `PACKAGES` minus LuCI/dnsmasq-dhcp as the host role needs, `ROOTFS_PARTSIZE`; then appends the 4 MiB config region as a partition after the root (MBR partition 3 on `bcm27xx`, a GPT partition on `filogic`/`armsr` — done with `sfdisk`/`sgdisk` inside the container on the unpacked image), writes `WYRMCFG0`, recompresses, and writes the index entry (size, SHA-256, `config_offset`) into `<out>/index.json`. Also writes `/etc/wyrm/image.json` into the overlay before the build.

- [ ] Failing tests (no container needed): `boards_json_is_valid` (every board has a target/profile/positive sizes, ids unique), `rootfs_partsize_never_changes` (compares with the same file at `origin/main` when a board id exists there; skipped when git has no such ref), `the_command_line_is_built_right` (unit test of the ImageBuilder argv for `rpi4`, no execution).
- [ ] Implement; verify the real run for `qemu-armsr` locally if a container runtime is present (report honestly if not).
- [ ] Commit `packaging/images: boards and wyr image base (ADR 0051 §2)`.

### Task 5: Smoke test in QEMU and the images workflow

**Files:** Create `packaging/images/smoke.sh`, `packaging/images/workflow.yml` (build all boards on a tag, attach images + `index.json` to the release; to be copied to `.github/workflows/` by the owner), `.github/workflows/images-smoke.yml` (runs on PRs touching `packaging/openwrt/**`, `packaging/images/**`, `crates/wyrm-image/**`, `tools/wyr/src/image*.rs`).

**Interfaces — Consumes:** Tasks 2–4. `smoke.sh`: `wyr image base --board qemu-armsr` → `wyr image build` with a test config (`gateway: {listen: "0.0.0.0:8445", tls: "site_ca", setup_file: "/etc/wyrm/setup.d/setup"}`, `--new-setup-code`) → boot in `qemu-system-aarch64` (user networking, port forward 8445) → within 180 s: `/api/info` over TLS answers with `setup: true` and a `setup_proof` that `wyr`/a test helper verifies with the code → `POST /api/setup` → login works → reboot once → still logged-in-able, region empty (`wyr image inspect` on the disk file shows nothing). A second case boots the unassembled base image and asserts the gateway does not listen off loopback.

- [ ] Write the script and workflows; run locally where QEMU + a container runtime exist; otherwise let CI judge and say so.
- [ ] Commit `images: QEMU smoke test and the build workflow (ADR 0051)`.

### Task 6: Close the part

- [ ] `docs/operations.md` "Board images": build a base image, assemble, flash (per board, from `boards.json` notes), first boot, what `sysupgrade`/re-flash keeps; `docs/adr/0051` "Built (part 2)"; root CLAUDE.md one line; `site/install` texts untouched (part 3 turns the planned image path on).
- [ ] Full checks; PR; independent audit; green CI; merge.

## Next plans

- Part 3: the page `wyrm.gencto.uk/start` — `wyrm-image` compiled to wasm, base image kept in OPFS, SHA-256 check, region written in the browser, setup code + QR, download; hosting of base images with CORS.
- Studio: the setup screen (verify `setup_proof`, send the code, pin the CA) and later "New device".
- Real boards: flash and measure when the hardware arrives (`bpi-r4` SD → eMMC install path is written from OpenWrt's docs, unverified until then).
