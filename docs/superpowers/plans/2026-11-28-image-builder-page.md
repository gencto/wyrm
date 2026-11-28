# Image builder page (ADR 0051 part 3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The page `https://wyrm.gencto.uk/start/`: pick a board, a site name, the network, the links, the time zone and NTP; the browser writes that configuration into the board's base image and hands back a finished `.img.gz` with a one-time setup code. Nothing the person chooses leaves the browser.

**Architecture:** The choices become the region's files in Rust (`wyrm_image::choices`, pure, also used by `wyr image build --choices`), compiled to WebAssembly by a thin binding crate `wyrm-image-web`. CI publishes every base image as one gzip member (ruling 2026-11-28: Raspberry Pi Imager sizes a `.gz` from the last member's ISIZE, so a multi-member file is refused on small cards). The page checks the download's SHA-256, then streams it: `DecompressionStream` → the region's bytes replaced at `config_offset` → `CompressionStream('gzip')` → a `Blob`, never holding the raw image. Base images and their index are served from the site's own origin (GitHub Pages), copied there from the latest `images-v*` release at deploy.

**Tech Stack:** Rust (`wyrm-image`, `wasm-bindgen`, `qrcode`), plain JavaScript (no framework, as `site/assets/install.js`), Web Crypto (`crypto.getRandomValues`, `crypto.subtle.digest`), `CompressionStream('gzip')`, Cache API, GitHub Pages, GitHub Actions.

**Spec:** `docs/adr/0051-broker-images-and-image-builder.md` §4 "The builder", §3 "First admin", "Answers of the owner"; `docs/operations.md` "Board images" (the region's files and the device's rules).

## Global Constraints

- Nothing of the person's choices, the setup code or its hash is sent anywhere: the page makes requests only to its own origin, for the page, its assets, `start/images/index.json` and the image files. No analytics, no third-party script or font.
- The page assembles only from a base image whose download matches its index entry (`download.size`, `download.sha256`); every byte outside the region is passed through unchanged; only the region's `CONFIG_SIZE` bytes at `config_offset` are new; the output is one gzip member whose ISIZE is the image size.
- The setup code: 16 bytes from `crypto.getRandomValues`, turned into the code and its hash by `wyrm_core::setup::code_of` (the same function `wyrmd setup-code` uses); only the hash goes into the image; the code is shown once on the page (text and QR) and is never stored by the page (no storage, no URL, no history).
- One writer of the region: `wyrm_image::region` (ADR 0051 §4). The page and `wyr image build --choices` produce byte-identical regions for the same choices and setup bytes.
- The device's rules are checked before anything is written: `ConfigFiles::check` (site 1–64 of `A-Za-z0-9_.-` not starting with `.`, `data_dir` `/srv/wyrm`, time zone, NTP ≤ 16).
- `wyrm-image` stays pure (no I/O, clock or randomness) and builds for `wasm32-unknown-unknown`; randomness comes in as bytes.
- Index format stays `wyrm-images/1`: new fields are optional and additive; an old reader ignores them.
- Index trust: the page trusts the index because it comes from the page's own HTTPS origin. A signature over the index waits for the project's release key (`RELEASE_KEYS` is empty); record this in ADR 0051.
- Network choices in this version: DHCP (default) and a static IPv4 address. No Wi-Fi (record in ADR 0051).
- Latest versions of every new dependency and tool (owner rule); `cargo` deps pinned the workspace way; `wasm-bindgen` crate and `wasm-bindgen-cli` at the same exact version.
- Rust rules: `docs/rust-rules.md`, `python3 tool/check_rust_rules.py` (counts only go down). Code, comments, commits in English. Public repo: no security wording in commits or PR text.
- Browsers: current Chrome, Edge, Firefox, Safari (all have `CompressionStream`, `DecompressionStream`, Web Crypto, Cache API). The page works when storage is refused (private window): it just downloads again.

## Review Focus

1. **A download that is cut, stale or of another release** (network drop, an old cached file, the index changed under an open page): refused by size and SHA-256 before any byte is used, with a plain message and a "try again"; never a finished image from it. → Task 4 test `a_download_that_does_not_match_is_refused`.
2. **Gzip readers the person's imager uses must read the page's file and size it right**: Raspberry Pi Imager (libarchive; sizes by the trailer ISIZE), balenaEtcher (Node zlib), `gunzip`, `bmaptool` (Python). → Task 2's `gzip-readers.sh` (four readers, one member, ISIZE) runs on base images; Task 5 runs it on an image the page's code assembled.
3. **A site name or option the device refuses** typed into the form: refused on the page with the device's words before the download starts, never a finished image that boots into "no broker". → Task 1 tests on `Choices::files` errors; Task 4 test that the page shows the error and offers no download.
4. **Memory on a phone or small laptop**: the page holds at most the compressed download and the compressed result, never the raw image: it streams. → Task 4 test `assembly_streams` asserts no chunk larger than 1 MiB is buffered by the replace step and the result is built from `Blob` parts.
5. **The setup code shown once and then lost** (reload, tab closed before writing it down): the page says so before it shows the code, and asks for confirmation ("I wrote it down") before the download button. → Task 4 test on the order: code shown → confirmation → download enabled.

---

### Task 1: Choices → region files (`wyrm_image::choices`) and `wyr image build --choices`

**Files:**
- Create: `crates/wyrm-image/src/choices.rs`
- Modify: `crates/wyrm-image/src/lib.rs` (module, re-exports, crate doc), `crates/wyrm-image/src/index.rs` (`ImageEntry.lan`, `ImageEntry.title`, `ImageEntry.notes`), `tools/wyr/src/image.rs` (`--choices`), `tools/wyr/src/image_base.rs` (copy `title`, `notes`, `lan` from `boards.json` into the entry), `packaging/images/boards.json` (`lan` per board)
- Test: `crates/wyrm-image/src/choices.rs` (unit), `crates/wyrmd/tests/image_choices.rs` (the generated `wyrmd.json5` is a config `wyrmd` loads), `tools/wyr/tests/image.rs`

**Interfaces:**
- Produces:
  - `pub struct Choices { pub site: String, pub network: Network, pub links: Vec<String>, pub timezone: Option<String>, pub ntp: Vec<String>, pub ssh_keys: Option<String> }` — serde, `deny_unknown_fields`, JSON format tag `"format": "wyrm-choices/1"`.
  - `pub enum Network { Dhcp, Static { address: String, prefix: u8, gateway: Option<String>, dns: Vec<String> } }` — serde tag `"mode"`: `"dhcp"` / `"static"`.
  - `pub enum Lan { Device { device: String }, Bridge { bridge: String, ports: Vec<String> } }` — serde, in `ImageEntry.lan: Option<Lan>`.
  - `pub struct Catalog { pub links: Vec<CatalogLink> }`, `pub struct CatalogLink { pub id: String, pub form: LinkForm, pub driver: Option<String>, pub file: Option<String> }`, `pub enum LinkForm { Builtin, Service, Seed }` — what the page offers, built from `links/official.json` + the image's seed files (Task 5 publishes it as `start/images/catalog.json`).
  - `impl Choices { pub fn files(&self, entry: &ImageEntry, catalog: &Catalog, setup_hash: &[u8; 32]) -> Result<ConfigFiles, ChoicesError> }` — the result has passed `ConfigFiles::check`.
  - `pub enum ChoicesError` (thiserror): `Format`, `UnknownLink(String)`, `NoLan` (static network on an entry without `lan`), `BadAddress(String)`, `BadPrefix(u8)`, `Device(ImageError)`. Each message is a sentence for a person (the page shows it as is).
- Consumes: `ConfigFiles`, `ConfigFiles::check`, `DATA_DIR`, `SETUP_FILE`, `SEED_DIR`, `ImageEntry`.

What `files` writes (the device and `wyrmd` take exactly this; read `site/assets/install.js` lines 160–262 for the shape the install page already shows for an image):
- `wyrmd.json5`: `site`, `data_dir: "/srv/wyrm"`, `gateway: { listen: "0.0.0.0:8443", tls: "site_ca", setup_file: "/etc/wyrm/setup.d/setup" }`, `updates: { mode: "off" }`, `packages: { repository: "official", seed_dir: "/usr/share/wyrm/seed" }` (seed_dir only when a `Seed` link is chosen), each `Service` link (`scheduler`, `alarm`, `dql`, `uplink`) as `<id>: { enabled: true|false }`, each `Builtin` link as `links: { <id>: { driver: "<driver>" } }`. Strings are written as JSON string literals (escaped), never pasted raw.
- `network` (only for `Static`): UCI text with `config interface 'loopback'` (as OpenWrt's default) and `config interface 'lan'` with `proto 'static'`, `ipaddr`, `netmask` (from `prefix`), `gateway`, `dns`; for `Lan::Bridge` also the `config device` section of the bridge with its ports. DHCP writes no `network` file (the device stays a DHCP client).
- `seed.json`: `wyrm-seed/1` with one `{link, file, accept: false}` per chosen `Seed` link.
- `setup`: the 64 lower-case hex digits of `setup_hash`.
- `timezone`, `ntp`, `authorized_keys` as `wyr image build` writes them (one name + newline; one server per line).

- [ ] **Step 1: Write the failing tests** in `choices.rs`: `dhcp_writes_no_network_file`, `static_on_a_bridge_board_writes_the_bridge` (entry with `Lan::Bridge { bridge: "br-lan", ports: ["lan1","lan2","lan3"] }` → network text contains `option name 'br-lan'`, each `list ports 'lanN'`, `option device 'br-lan'`, `option netmask '255.255.255.0'` for prefix 24), `static_without_lan_is_refused` (`ChoicesError::NoLan`), `a_site_the_device_refuses_is_refused` (`".plant"` → `ChoicesError::Device(_)`), `a_quote_in_the_site_cannot_break_the_config` (site `pla"nt` → refused by the device rule; and a test that every string goes through a JSON encoder: an NTP server or time zone is never pasted into `wyrmd.json5`), `seed_lists_only_seed_links`, `service_links_are_switched`, `unknown_link_is_refused`, `the_setup_file_is_the_hash`, `the_same_choices_give_the_same_region` (`region(&files)` twice → equal bytes).
- [ ] **Step 2: Run** `cargo test -p wyrm-image choices` — expect compile failure (no module).
- [ ] **Step 3: Implement** `choices.rs` with the interfaces above; `ImageEntry` gains `title: Option<String>`, `notes: Option<String>`, `lan: Option<Lan>` (serde default, skip when none).
- [ ] **Step 4: Run** `cargo test -p wyrm-image` — all pass; `cargo build -p wyrm-image --target wasm32-unknown-unknown` — builds.
- [ ] **Step 5: Write** `crates/wyrmd/tests/image_choices.rs`: for DHCP, static, every link form, the generated `wyrmd.json5` loads with `wyrmd`'s own config loader (the function `wyrmd check` uses) without error. Run `cargo test -p wyrmd --test image_choices` — pass.
- [ ] **Step 6: Add `lan` to `boards.json`** for `qemu-armsr`, `rpi4`, `rpi5`, `bpi-r4`, each read from OpenWrt 25.12's `target/linux/<target>/<subtarget>/base-files/etc/board.d/02_network` (or the target's equivalent) for that profile — cite the file and line in the commit message; `image_base.rs` copies `title`, `notes`, `lan` into the entry; `tools/wyr/tests/boards.rs` asserts every listed board has `lan`.
- [ ] **Step 7: `wyr image build --choices <file>`** (conflicts with `--config`, `--network`, `--seed`, `--timezone`, `--ntp`, `--authorized-keys`; needs `--catalog <file>`; with `--new-setup-code` or `--setup-hash-file`): reads the choices, calls `Choices::files`, then the existing assembly. Test in `tools/wyr/tests/image.rs`: `choices_build_the_same_region_as_the_files` (the same choices through `--choices` and through the equivalent file flags → identical output images).
- [ ] **Step 8: Run** `cargo fmt --all -- --check`, `cargo clippy --workspace --all-targets --all-features -- -D warnings`, `cargo test -p wyrm-image -p wyr`, `python3 tool/check_rust_rules.py` — all pass.
- [ ] **Step 9: Commit** `wyrm-image: choices become the files of a region; wyr image build --choices (ADR 0051 §4)`.

### Task 2: Base images as three gzip members (superseded by the ruling of 2026-11-28: one member + `gzip-readers.sh`; see the ledger)

**Files:**
- Modify: `tools/wyr/src/image_base.rs` (write the `.gz` as three members), `crates/wyrm-image/src/index.rs` (`Download.members`), `tools/wyr/src/image.rs` (`build` and `inspect` accept it — they already use `MultiGzDecoder`; check), `packaging/images/README.md`, `docs/operations.md` ("Board images": the file is a normal gzip any tool reads)
- Create: `packaging/images/gzip-readers.sh` (the reader check), and a CI step that runs it in `.github/workflows/images-smoke.yml`
- Test: `tools/wyr/tests/image.rs`, `crates/wyrm-image/src/index.rs` (unit)

**Interfaces:**
- Produces: `pub struct Member { pub offset: u64, pub size: u64 }` and `Download.members: Option<[Member; 3]>` (head, region, tail; byte ranges in the `.gz`; serde default). `Index::check` refuses members that do not tile the file exactly (`members[0].offset == 0`, contiguous, last ends at `download.size`). The head member decompresses to exactly `config_offset` bytes, the region member to `CONFIG_SIZE`, the tail to the rest.
- Consumes: Task 1's `ImageEntry`.

- [ ] **Step 1: Write the failing tests**: in `index.rs` `members_must_tile_the_download` (gap, overlap, short → refused); in `tools/wyr/tests/image.rs` `the_download_is_three_members_that_read_as_the_image` (a small fake base image through the `.gz` writer: concatenated members decompress with `MultiGzDecoder` to the raw bytes; the middle member alone decompresses to `WYRMCFG0` + zeros of `CONFIG_SIZE`), and `a_region_member_swapped_in_gives_the_assembled_image` (gzip a region from `region(&files)`, join head + it + tail, decompress → equals `wyr image build`'s raw output for the same files).
- [ ] **Step 2: Run** them — expect failure.
- [ ] **Step 3: Implement**: the base image's gzip is written as three independent members at the region's boundaries (flate2 `GzEncoder` per member, level 9); `Download.members` recorded in the entry; the `download.sha256` and `size` stay those of the whole `.gz`.
- [ ] **Step 4: Run** the tests — pass.
- [ ] **Step 5: Write `packaging/images/gzip-readers.sh <image.img> <image.img.gz>`**: decompresses the three-member file with `gunzip -c`, `bsdcat` (libarchive, what Raspberry Pi Imager uses), `python3 -c 'import gzip,sys; …'` (what `bmaptool` uses) and `node -e` with `zlib.createGunzip()` (what balenaEtcher uses); each output's SHA-256 must equal the raw image's; exit 1 naming the reader that differs. Run it locally on a `qemu-armsr` base image built with `wyr image base` — all four equal. Add it to the smoke job before the boot.
- [ ] **Step 6: Run** `cargo fmt --all -- --check`, clippy, `cargo test -p wyrm-image -p wyr`, the checker, shellcheck on the new script — pass.
- [ ] **Step 7: Commit** `images: the base image's gzip in three members, the region alone (ADR 0051 §4)`.

### Task 3: `wyrm-image-web` — the WebAssembly the page calls

**Files:**
- Create: `crates/wyrm-image-web/Cargo.toml` (`crate-type = ["cdylib", "rlib"]`, deps `wyrm-image`, `wyrm-core`, `wasm-bindgen`, `qrcode` (no default features, SVG only), `serde_json`), `crates/wyrm-image-web/src/lib.rs`, `tool/site/wasm.sh` (build: `cargo build --release --target wasm32-unknown-unknown -p wyrm-image-web` then `wasm-bindgen --target web --out-dir site/dist/assets/wasm`), `crates/wyrm-image-web/tests/web.rs` (native tests of the same functions)
- Modify: workspace `Cargo.toml` (member; `wasm-bindgen`, `qrcode` versions), `CLAUDE.md` (one line for the crate), `tool/check_rust_rules.py` only if a rule needs a scoped exception for `#[wasm_bindgen]` items (prefer none)

**Interfaces:**
- Produces (all `#[wasm_bindgen]`, errors as `JsError` with the `ChoicesError`/`ImageError` sentence):
  - `pub fn check_index(text: &str) -> Result<JsValue, JsError>` — parses and checks the index, returns the entries the page may offer (listed boards that have a `download`), as plain objects.
  - `pub fn new_setup(random: &[u8]) -> Result<Setup, JsError>` — `random` must be 16 bytes; `Setup { code: String, hash_hex: String, qr_svg: String }` (`qr_svg`: an SVG of the code, error correction M, dark modules `currentColor`, no width/height so CSS sizes it). Uses `wyrm_core::setup::code_of`.
  - `pub fn region_for(choices_json: &str, entry_json: &str, catalog_json: &str, setup_hash_hex: &str) -> Result<Vec<u8>, JsError>` — `Choices::files` then `region`; returns the 4 MiB region.
  - `pub fn check_choices(choices_json: &str, entry_json: &str, catalog_json: &str) -> Result<(), JsError>` — the same checks without a hash, for the form's live validation.
- Consumes: Task 1 (`Choices`, `Catalog`, `ImageEntry`), `wyrm_image::region`, `wyrm_core::setup::code_of`.

- [ ] **Step 1: Write the failing native tests** in `tests/web.rs` (call the plain Rust functions under the bindings): `a_setup_from_16_bytes_matches_wyrmd` (same code and hash as `code_of`), `fewer_than_16_bytes_are_refused`, `the_qr_is_svg_of_the_code` (starts with `<svg`, no `width=`), `region_for_matches_wyr` (same bytes as `region(&choices.files(...))`), `check_index_offers_only_listed_boards_with_a_download`.
- [ ] **Step 2: Run** `cargo test -p wyrm-image-web` — fail.
- [ ] **Step 3: Implement** the crate; keep logic out of it (only conversion between JS values and Task 1/2 types).
- [ ] **Step 4: Run** the tests — pass. Run `tool/site/wasm.sh` — `site/dist/assets/wasm/wyrm_image_web_bg.wasm` exists; record its size (gzip) in the commit message; budget ≤ 600 KiB gzip (if over, `opt-level = "z"`, `lto`, `wasm-opt` from `binaryen` at its latest release).
- [ ] **Step 5: Run** fmt, clippy (also `--target wasm32-unknown-unknown -p wyrm-image-web`), the checker — pass.
- [ ] **Step 6: Commit** `wyrm-image-web: the image builder's WebAssembly (ADR 0051 §4)`.

### Task 4: The page `/start/`

**Files:**
- Create: `site/start/index.html` (the design of `site/install/index.html`: same header, fonts, tokens, light/dark; template filled by `tool/site/build.py` like the install page), `site/assets/start.js`, `tool/site/test_start.mjs` (Node test: runs `start.js`'s assembly functions with the built wasm against a fixture index and a small fake base image as one gzip member)
- Modify: `tool/site/build.py` (render `start/`; `RESERVED` already holds `start`; run `wasm.sh` or check its output exists), `site/README.md`

**Interfaces:**
- Consumes: Task 3's exports; `start/images/index.json` and `start/images/catalog.json` (Task 5 publishes them; when absent the page shows "No image is published yet" and the link to `wyr image build`).
- Produces (functions in `start.js`, exported for the Node test through `globalThis.wyrmStart` when `globalThis.process` exists): `fetchImage(entry, onProgress) -> Promise<Blob>` (Cache API first, keyed by `download.sha256`; else `fetch`; checks size and SHA-256; puts it in the cache on success, ignores a cache that throws), `assemble(blob, entry, region) -> Promise<Blob>` (pipes `blob.stream()` through `DecompressionStream('gzip')`, a `TransformStream` that replaces bytes `[config_offset, config_offset + CONFIG_SIZE)` with `region` and checks the total equals `entry.size`, then `CompressionStream('gzip')`; collects the chunks into a `Blob`), `fileName(entry, site) -> string` (`wyrm-<board>-<site>.img.gz`).

The flow on the page (one column, steps numbered like the install page): 1 Board (cards from the index: title, notes, size) · 2 Site name · 3 Network (DHCP / static: address, prefix, gateway, DNS) · 4 Links (from the catalog, grouped by category as on the install page; services on by default as `wyrmd` defaults) · 5 Time zone (`Intl.supportedValuesOf('timeZone')`, default the browser's) and NTP (default empty: the device uses DHCP's, then the pool) · 6 SSH key (optional) · **Build**: validates with `check_choices` (error shown at its field), makes the setup with `new_setup(crypto.getRandomValues(new Uint8Array(16)))`, shows the code (groups + QR) with "Write this code down. It is shown once and is not stored anywhere.", a checkbox "I wrote it down", then enables **Download** which fetches (progress bar), assembles and saves the file. Then the steps to write the card (from the entry's `notes` and `docs/operations.md` "Write the card"), and links: the OpenWrt source of the release (`https://github.com/openwrt/openwrt/tree/v<openwrt>`), the WYRM tag of `wyrmd`, the image's manifest file.

- [ ] **Step 1: Write the failing Node tests** in `tool/site/test_start.mjs`: `a_download_that_does_not_match_is_refused` (wrong size; right size wrong SHA-256 → rejected with the page's message, no cache write), `assembly_replaces_only_the_region` (`gunzip` of the result equals the fixture raw image with the region written; one gzip member; its ISIZE equals the raw size; the original blob is untouched), `a_download_of_the_wrong_length_is_refused` (decompressed length ≠ `entry.size` → rejected), `assembly_streams` (the replace step never buffers more than one input chunk plus the region), `the_file_name_is_plain` (site and board end up as `[A-Za-z0-9_.-]` only), `the_download_waits_for_the_confirmation` (DOM via a minimal stub: the download button is disabled until the checkbox), `a_refused_site_shows_the_device_words_and_no_download`.
- [ ] **Step 2: Run** `node tool/site/test_start.mjs` — fail.
- [ ] **Step 3: Implement** `start/index.html` and `start.js` (no framework, no third-party code, the CSS tokens of `site/assets/site.css`; phone width without horizontal scroll; the code shown in monospace groups; nothing written to `localStorage`/`sessionStorage`/URL except the cached image).
- [ ] **Step 4: Run** the Node tests — pass. Run `python3 tool/site/build.py && mdbook build site && python3 tool/site/build.py --check site/dist` and `node tool/site/test_install.js` — pass.
- [ ] **Step 5: Check by hand in a browser** (Chrome and Firefox; `python3 -m http.server` on `site/dist` with a locally built `qemu-armsr` base image, its index and catalog under `start/images/`): build an image, the code shows once, the download lands; `wyr image inspect --image <download> --index … --board qemu-armsr` shows the region's files; a second build reuses the cached download (no network request in DevTools). Note what you saw in the commit message.
- [ ] **Step 6: Commit** `site: the image builder page /start/ (ADR 0051 §4)`.

### Task 5: Hosting, release workflow, end-to-end boot, docs

**Files:**
- Create: `.github/workflows/images-release.yml` (from `packaging/images/workflow.yml`: on a tag `images-v*`, builds every listed board, publishes the release; plus `catalog.json` from `links/official.json` and the seed files actually in the images); `tool/site/fetch_images.py` (download the latest `images-v*` release's `index.json`, `catalog.json` and every listed `download.file` into `site/dist/start/images/`, check each against the index, fail when the total passes 900 MiB)
- Modify: `.github/workflows/site.yml` (run `wasm.sh` with pinned `wasm-bindgen-cli` (checksum-checked binary as mdBook is) and the wasm32 target; run `fetch_images.py` before `build.py`; trigger on `release: published` for `images-v*` too; the PR build runs without images and checks the "no image yet" state), `packaging/images/smoke.sh` (`--assembled <img.gz>`: boot an image assembled elsewhere, skipping `wyr image build`), `site/assets/install.js` + `tool/site/build.py` (the install page's "USB or SD image" path links to `/start/` and is no longer "planned" once the deploy carries images; the build knows from `start/images/index.json`), `docs/operations.md` ("Board images": the page), `docs/adr/0051-broker-images-and-image-builder.md` ("Built (part 3)", the index trust decision, no Wi-Fi, hosting on Pages), `CLAUDE.md` (the `wyrm-image` line: choices, the page), `packaging/images/README.md`
- Test: the smoke job gains a step: assemble a `qemu-armsr` image with `node tool/site/test_start.mjs --assemble <choices.json> <out>` (the page's own code under Node) and boot it with `smoke.sh --assembled`; the same assertions as today (setup proof with the printed code, login, second boot).

- [ ] **Step 1: Write the smoke step** first (it fails: no `--assembled`, no `--assemble`).
- [ ] **Step 2: Implement** `--assembled` in `smoke.sh` and `--assemble` in `test_start.mjs`; run the smoke test locally under HVF with an image the page's code assembled — PASS (first boot, setup with the code, login, second boot).
- [ ] **Step 3: Implement** `fetch_images.py`, the `site.yml` and `images-release.yml` changes; run `actionlint` (Docker `rhysd/actionlint`) — clean; run `fetch_images.py` against a fixture directory in a test (`tool/site/test_fetch_images.py`: a mismatching file is refused, the size cap holds).
- [ ] **Step 4: Docs and ADR** as listed; every claim checked against the code.
- [ ] **Step 5: Full checks**: fmt, clippy (workspace, all features; and `-p wyrm-image-web --target wasm32-unknown-unknown`), `cargo test -p wyrm-image -p wyrm-image-web -p wyr`, `cargo test -p wyrmd --test image_choices`, the checker, shellcheck, the site build + check, both Node tests.
- [ ] **Step 6: Commit** `site: base images on the site, the images release workflow, the page's image booted in QEMU (ADR 0051 part 3)`; push; open the PR (what is built, how verified, what the owner does: tag `images-v<version>` to publish the first images, which also deploys them to `/start/`); independent whole-branch review; green CI; merge.

## Not in this plan

- Studio's "New device" screen (ADR 0051 §5).
- Wi-Fi on the page; IPv6 static addresses.
- A signature over the index (waits for the release key).
- `wyr image build --region-only` for the BPI-R4 eMMC path.
