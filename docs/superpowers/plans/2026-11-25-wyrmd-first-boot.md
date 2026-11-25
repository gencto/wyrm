# wyrmd first boot (ADR 0051, part 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A `wyrmd` started from an image with no secrets in it serves its gateway over TLS from the site CA, lets the first admin in with a one-time setup code, and installs the link packages the image carries — all on the first start, all testable on a laptop.

**Architecture:** Three independent features. (1) `gateway.tls: "site_ca"`: `wyrmd` issues the gateway certificate from the site CA (`wyrm_admin::secret::Pki::issue`) with names from the host, and issues it again when an address changes (hot reload through `axum_server`'s `RustlsConfig`). (2) Setup code: a SHA-256 of a 128-bit code sits in a private file of the gateway; `POST /api/setup` turns it into the first admin once. (3) Seed: on first start the admin installs each package listed in a seed file through the same path as `sys/links ▸ install_zip`, and records that it did.

**Tech Stack:** Rust 1.89+, tokio, axum + axum-server (rustls/ring), rcgen (through `Pki`), `if-addrs` (already in the lock file through `mdns-sd`; take its latest version), sha2, data-encoding or an in-crate base32, serde/serde_json (seed file = a user file, principle 5).

**Spec:** `docs/adr/0051-broker-images-and-image-builder.md` §3 (and §1 "Seed packages").

## Global Constraints

- Root CLAUDE.md "Conventions" and `docs/rust-rules.md`: no `unwrap`/`expect` in product code, typed errors (no new `Result<_, String>`), an action's arguments are one `#[derive(Args)]` struct, `python3 tool/check_rust_rules.py` passes and no count goes up.
- `wyrmd.json5` sections are `#[serde(deny_unknown_fields)]`; `wyrmd` never writes `wyrmd.json5`.
- Never log secrets: not the setup code, not its hash, not keys.
- Setup code: 128 random bits, shown as RFC 4648 base32 without padding (26 characters), in groups; hash = SHA-256 over `b"wyrm-setup-v1\n"` + the 16 code bytes.
- Gateway certificate names: `<hostname>.local`, `wyrm-<site>.local`, and every non-loopback address of the host (IPv4 and global IPv6; not link-local IPv6) — or only the listen address when `gateway.listen` is not unspecified.
- `WYRM_GATEWAY_ADMIN_PASSWORD` keeps working as today.
- Each feature updates `docs/operations.md` and the config reference in the same task that adds it; ADR 0051 gets a "Built" line per feature in the last task.
- Checks before each commit: `cargo fmt --all --check`, `cargo clippy --workspace --all-targets -- -D warnings`, the crate's tests, `python3 tool/check_rust_rules.py`. Before the PR also `cargo +1.99.0 clippy --workspace --all-targets --all-features -- -D warnings` and `cargo test -p wyrmd --test e2e`.

## Review Focus

1. A setup code typed in lowercase, with spaces or dashes between groups, is accepted; a code of the wrong length or alphabet is `setup_code_wrong`, never a panic. → Task 4 test `code_is_read_as_typed`.
2. A setup file present while a user already exists (a restored backup, a crash between creating the admin and removing the file) never makes a second admin: the pending setup is dropped at start and `/api/setup` answers `no_setup`. → Task 5 test `setup_is_void_once_a_user_exists`.
3. Guessing on `/api/setup` is limited like `/api/login` (same limiter, same `429`). → Task 5 test `setup_is_rate_limited_like_login`.
4. A host whose address comes late (DHCP after `wyrmd` starts) or changes gets a certificate that names the new address within one check period, without a restart. → Task 3 test `certificate_follows_the_addresses`.
5. A seed where one package is broken installs the others, records the failure, and is not run again at the next start; a seed link whose id already exists (a restored backup) is skipped. → Task 6 tests `a_broken_seed_entry_does_not_stop_the_others`, `seed_runs_once`, `seed_skips_an_existing_link`.

---

### Task 1: `gateway.tls: "site_ca"` in the config

**Files:**
- Modify: `crates/wyrmd/src/lib.rs` (`GatewaySection` ~line 563, config validation ~line 1142, `gateway_ca` ~line 700)
- Test: `crates/wyrmd/src/lib.rs` `mod tests`

**Interfaces:**
- Produces: `pub enum GatewayTls { SiteCa }` (serde `"site_ca"`), field `GatewaySection.tls: Option<GatewayTls>`; `impl GatewaySection { pub fn tls_files(&self, data_dir: &Path) -> Option<(PathBuf, PathBuf)> }` — `Some((tls_cert, tls_key))` when set, `Some((data_dir/gateway/tls.pem, data_dir/gateway/tls.key))` for `site_ca`, `None` otherwise. Every reader of `tls_cert`/`tls_key` (gateway open ~line 2196, `gateway_ca`) goes through it.

- [ ] **Step 1: Write the failing tests** `site_ca_is_accepted_off_loopback` (config with `gateway: {listen: "0.0.0.0:8445", tls: "site_ca"}` loads), `site_ca_excludes_tls_files` (with `tls_cert` too → error text `gateway: tls "site_ca" excludes tls_cert and tls_key`), `tls_files_of_site_ca` (`tls_files(Path::new("/d"))` = `("/d/gateway/tls.pem", "/d/gateway/tls.key")`).
- [ ] **Step 2: Run** `cargo test -p wyrmd --lib site_ca` — FAIL (unknown field `tls`).
- [ ] **Step 3: Implement** the enum, the field, `tls_files`, the validation branch (site_ca: both files absent required; off-loopback check satisfied), and switch the readers to `tls_files`.
- [ ] **Step 4: Run** `cargo test -p wyrmd --lib` — PASS, the existing gateway config tests unchanged.
- [ ] **Step 5: Commit** `wyrmd: gateway.tls "site_ca" in the config (ADR 0051 §3)`.

### Task 2: Issue the gateway certificate from the site CA at start

**Files:**
- Create: `crates/wyrmd/src/gateway_tls.rs`
- Modify: `crates/wyrmd/src/lib.rs` (gateway open, before `Gateway::open`), `crates/wyrmd/Cargo.toml` (`if-addrs`)
- Test: `crates/wyrmd/src/gateway_tls.rs` unit tests, `crates/wyrmd/tests/e2e.rs`
- Docs: `docs/operations.md` (gateway TLS), the config reference in `wyrmd.json5` examples

**Interfaces:**
- Consumes: `GatewaySection::tls_files` (Task 1), `wyrm_admin::secret::Pki::{open_or_create, issue}` (`issue` already keeps a certificate whose CN and names still match, and issues a new one otherwise).
- Produces: `pub fn names(site: &str, hostname: &str, listen: SocketAddr, addrs: &[IpAddr]) -> Vec<String>` (pure, sorted, deduplicated; rules in Global Constraints); `pub fn host_addrs() -> Vec<IpAddr>` (non-loopback, IPv4 + global IPv6, via `if-addrs`); `pub fn issue(cfg: &Config, names: &[String]) -> Result<(PathBuf, PathBuf), GatewayTlsError>` (CN `gateway:<site>`, server auth, out `data_dir/gateway`, name `tls`).

- [ ] **Step 1: Write the failing unit tests** `names_of_an_unspecified_listen` (site `plant`, hostname `bpi`, listen `0.0.0.0:8445`, addrs `[10.0.0.5, fe80::1, 2001:db8::5]` → `["10.0.0.5", "2001:db8::5", "bpi.local", "wyrm-plant.local"]`), `names_of_a_bound_listen` (listen `10.0.0.5:8445` → `["10.0.0.5", "bpi.local", "wyrm-plant.local"]`).
- [ ] **Step 2: Run** `cargo test -p wyrmd --lib gateway_tls` — FAIL.
- [ ] **Step 3: Implement** `names`, `host_addrs`, `issue`; call `issue` in the gateway open path when `tls == SiteCa` (hostname from `gethostname`/`/proc/sys/kernel/hostname` through a safe API, fallback `wyrm-<site>`).
- [ ] **Step 4: Write the failing e2e test** `gateway_site_ca_serves_tls` in `crates/wyrmd/tests/e2e.rs`: a broker with `gateway: {listen: "127.0.0.1:0", tls: "site_ca"}`; an HTTPS client that trusts only `data_dir/pki/ca.pem` reads `/api/info`; `ca_fp` = first 16 bytes of SHA-256 of that CA's DER; a second start keeps the same certificate file (mtime unchanged).
- [ ] **Step 5: Run** `cargo test -p wyrmd --test e2e gateway_site_ca` — PASS after Step 3; then `cargo test -p wyrmd --lib`.
- [ ] **Step 6: Docs and commit** `wyrmd: the gateway's certificate from the site CA (ADR 0051 §3)`.

### Task 3: Issue it again when the addresses change

**Files:**
- Modify: `crates/wyrm-gateway/src/http.rs` (keep the `RustlsConfig`), `crates/wyrm-gateway/src/lib.rs` (`Gateway::reload_tls`), `crates/wyrmd/src/gateway_tls.rs` (watch task), `crates/wyrmd/src/lib.rs` (spawn it with the gateway)
- Test: `crates/wyrm-gateway` test, `crates/wyrmd/src/gateway_tls.rs` unit test

**Interfaces:**
- Consumes: Task 2 `names`, `host_addrs`, `issue`.
- Produces: `impl Gateway { pub async fn reload_tls(&self, cert_pem: Vec<u8>, key_pem: Vec<u8>) -> Result<()> }` (through `RustlsConfig::reload_from_pem`; `Error::Config` when the gateway serves plain HTTP); `pub async fn watch(cfg: Arc<Config>, gw: Arc<Gateway>, every: Duration)` — every `every` (30 s) compute `names(…, host_addrs())`; when they differ from the last issued, `issue` and `reload_tls`; log `gateway: certificate issued for <n> names` at info (names are not secret).

- [ ] **Step 1: Write the failing test** in wyrm-gateway `reloaded_certificate_is_served`: start a TLS gateway with cert A, `reload_tls(B)`, a new connection sees B's serial.
- [ ] **Step 2: Run** it — FAIL (no `reload_tls`).
- [ ] **Step 3: Implement** `reload_tls` (keep the `RustlsConfig` in the gateway's state).
- [ ] **Step 4: Write the failing unit test** `certificate_follows_the_addresses`: `watch` driven by an injected address source (make `watch` take `addrs: impl Fn() -> Vec<IpAddr>` internally; the public entry passes `host_addrs`) — first call `[]` → names without IPs; second call `[10.0.0.7]` → a new certificate whose SANs include `10.0.0.7`, and the gateway serves it.
- [ ] **Step 5: Implement** `watch`; spawn it in `wyrmd` for `site_ca` only, ended with the gateway.
- [ ] **Step 6: Run** `cargo test -p wyrm-gateway`, `cargo test -p wyrmd --lib` — PASS. Commit `gateway: a site-CA certificate follows the host's addresses`.

### Task 4: The setup code in wyrm-gateway

**Files:**
- Create: `crates/wyrm-gateway/src/setup.rs`
- Modify: `crates/wyrm-gateway/src/lib.rs` (module, `Gateway` methods)
- Test: `crates/wyrm-gateway/src/setup.rs` unit tests

**Interfaces:**
- Produces:
  - `pub fn code_hash(code: &str) -> Option<[u8; 32]>` — uppercase, drop spaces and `-`, base32 (RFC 4648, no padding) to exactly 16 bytes, then the hash of Global Constraints; `None` otherwise.
  - `pub fn new_code() -> (String, [u8; 32])` — for tests and `wyrmd setup-code` (Task 5): 16 bytes from the OS RNG, the code in groups of 4 separated by `-`, and its hash.
  - `pub enum SetupError { NoSetup, WrongCode, Rejected(String), Store(…) }` (`thiserror`; wire codes `no_setup`, `setup_code_wrong`, the existing ones for `Rejected`).
  - `impl Gateway { pub fn import_setup(&self, hash_hex: &str) -> Result<bool, SetupError>; pub fn setup_pending(&self) -> bool; pub fn complete_setup(&self, code: &str, user: &str, password: &str) -> Result<(), SetupError> }` — the pending hash lives in `<gateway dir>/setup.hash` (0600, written through the private-dir helpers the gateway already uses for `hmac.key`). `import_setup` refuses (returns `false`, writes nothing) when any user exists. `complete_setup`: `NoSetup` without a file or when a user exists (and removes the file); compare hashes in constant time; then `add_user(user, password, ["admin"])`, then remove the file.

- [ ] **Step 1: Write the failing tests** `code_is_read_as_typed` (the code from `new_code`, lowercased with spaces → same hash; 25 or 27 chars → `None`; a `1` in it → `None`), `setup_makes_one_admin` (import, `complete_setup` with the right code → user is admin, `setup_pending()` false, a second call → `NoSetup`), `wrong_code_keeps_the_setup` (wrong code → `WrongCode`, still pending), `import_is_refused_with_a_user`.
- [ ] **Step 2: Run** `cargo test -p wyrm-gateway setup` — FAIL.
- [ ] **Step 3: Implement** the module and the three methods.
- [ ] **Step 4: Run** `cargo test -p wyrm-gateway` — PASS. Commit `gateway: one-time setup code for the first admin (ADR 0051 §3)`.

### Task 5: `/api/setup`, `/api/info`, and `wyrmd` importing the setup file

**Files:**
- Modify: `crates/wyrm-gateway/src/http.rs` (route, `/api/info`), `crates/wyrmd/src/lib.rs` (`GatewaySection.setup_file: Option<PathBuf>`, bootstrap next to `WYRM_GATEWAY_ADMIN_PASSWORD`), `crates/wyrmd/src/cli.rs` (`wyrmd setup-code`), `spec/` only if `/api/info` is described there (then fixtures + `spec/CHANGELOG.md`)
- Test: `crates/wyrm-gateway` HTTP tests, `crates/wyrmd/tests/e2e.rs`
- Docs: `docs/operations.md` "First admin from a setup code", gateway API doc where `/api/login` is described

**Interfaces:**
- Consumes: Task 4.
- Produces: `POST /api/setup` CBOR body `{code, user, password}` → `204`; `409 no_setup`; `403 setup_code_wrong`; `400` for a rejected user/password (same texts as `add_user`); `429` from the `/api/login` limiter. `/api/info` gains `setup: true` while a setup is pending (absent otherwise). At start, when `gateway.setup_file` names an existing file: read 64 hex chars, `import_setup`, then try to remove the file (a failure to remove is a warning; the file is ignored once a user exists). CLI `wyrmd setup-code` prints a new code and, on the next line, its hash in hex (for images and tests).

- [ ] **Step 1: Write the failing tests** (wyrm-gateway HTTP): `setup_over_http` (pending → `/api/info` has `setup: true` → `POST /api/setup` right code → `204` → `/api/login` with that user works → `/api/info` without `setup`), `setup_is_rate_limited_like_login` (the login limiter's limit of wrong codes → `429`), `setup_is_void_once_a_user_exists` (a user added after import → `409 no_setup`, file gone).
- [ ] **Step 2: Run** — FAIL.
- [ ] **Step 3: Implement** the route, the `/api/info` field, the config field, the bootstrap import, `wyrmd setup-code`.
- [ ] **Step 4: Write the failing e2e test** `first_admin_from_a_setup_file`: `wyrmd setup-code` → write the hash to a temp file → start with `gateway.setup_file` → the file is removed → `POST /api/setup` with the code → login works.
- [ ] **Step 5: Run** `cargo test -p wyrm-gateway`, `cargo test -p wyrmd --test e2e first_admin` — PASS. Docs. Commit `wyrmd: first admin from a setup file (ADR 0051 §3)`.

### Task 6: Seed packages on the first start

**Files:**
- Create: `crates/wyrm-admin/src/control/seed.rs`
- Modify: `crates/wyrm-admin/src/control.rs` (module, call after the admin is up), `crates/wyrm-admin` `ControlConfig` (`seed_dir: Option<PathBuf>`), `crates/wyrmd/src/lib.rs` (`PackagesSection.seed_dir`, passed through)
- Test: `crates/wyrmd/tests/e2e.rs` (reuse the helper the existing `install_zip` e2e tests use to build a package zip)
- Docs: `docs/operations.md` "Seed packages", `docs/links.md` where `install_zip` is described

**Interfaces:**
- Consumes: `Admin::install_package(link, zip, source, sub, opts)` (`control.rs` ~4772; `opts: updates::UpdateOpts` with `accept`).
- Produces: seed file `<seed_dir>/seed.json`: `{"format": "wyrm-seed/1", "links": [{"link": "<id>", "file": "<name>.zip", "accept": true}]}` (`file` is a plain name inside `seed_dir`, no `/`, no `..`). Marker `data_dir/seed.done` (JSON: per link `ok` or the message of `success: false`, and the time). `impl Admin { pub(super) async fn apply_seed(&self, dir: &Path) }`: runs once (no marker → run → write marker); per entry: skip when the link id exists, else `install_package(link, bytes, "seed:<file>", "broker:seed", opts{accept, ..default})`; one failure does not stop the others; audit records as for `install_zip` with subject `broker:seed`.

- [ ] **Step 1: Write the failing e2e tests** `seed_installs_packages_once` (two good entries → both links run; marker exists; restart → nothing installed again), `a_broken_seed_entry_does_not_stop_the_others` (a missing file and a good one → the good one runs; marker records the error), `seed_skips_an_existing_link`, `seed_file_names_stay_in_the_seed_dir` (`"file": "../x.zip"` → refused in the marker, nothing read).
- [ ] **Step 2: Run** `cargo test -p wyrmd --test e2e seed` — FAIL.
- [ ] **Step 3: Implement** `seed.rs` (serde types with `deny_unknown_fields`, typed `SeedError`), the config fields, the call after the admin's start (once the link endpoint exists, so process packages can start).
- [ ] **Step 4: Run** `cargo test -p wyrm-admin`, `cargo test -p wyrmd --test e2e seed` — PASS. Docs. Commit `admin: seed packages on the first start (ADR 0051 §1)`.

### Task 7: Close the part

**Files:**
- Modify: `docs/adr/0051-broker-images-and-image-builder.md` (a "Built" section: the three features, with the config names), root `CLAUDE.md` (one line under `crates/wyrmd`), `docs/backlog.md` only if it tracks ADR 0051

- [ ] **Step 1:** Run the full checks of Global Constraints, including `cargo test -p wyrmd --test e2e` and `cargo +1.99.0 clippy … --all-features`.
- [ ] **Step 2:** Update the docs above; commit `ADR 0051: first-boot features built (part 1)`.
- [ ] **Step 3:** Open the PR (body: the three features, config names, the tests that pin the Review Focus items), then an independent audit, green CI, merge.

## Next plans (not in this one)

- Part 2: OpenWrt packages (`wyrmd`, procd script with the guard, `respawn_retry` ≥ 8, data partition), `packaging/images/boards.json`, `wyr image build` (ImageBuilder in a container), QEMU `armsr/armv8` smoke test.
- Part 3: the build service and the page `wyrm.gencto.uk/start` (needs the home site and the hosting decision).
- The home site on `wyrm.gencto.uk` built from the repo (own short plan; needs where DNS for `gencto.uk` lives).
- Studio: the setup screen (code + new admin, pins the CA in the same session) and later the "New device" builder.
