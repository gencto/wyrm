# WYRM Rust workspace — typing, security and structure audit (2026-11-15)

**Status (2026-11-15).** S1, S2 and T4 are fixed by PR #108 (one commit each; decisions in ADR 0029 items 12 and 13, spec 01 0.2.35). Every other finding is open; §6 gives the order of work. Line numbers below are those of the audited tree.

## 0. Scope and method

- **Tree audited.** Worktree `.claude/worktrees/studio-rules` at `4934ff29`. Its Rust tree is byte-identical to `origin/main` `ab02ead7` (`git diff --stat origin/main HEAD` touches only `studio/**` and one CI line). The local `main` checkout is 4 commits behind `origin/main` and was not used. Nothing in the repository was changed; clippy ran with `CARGO_TARGET_DIR` and `CLIPPY_CONF_DIR` in the scratch area.
- **Tools.** clippy 0.1.99 / rustc 1.99.1. Three runs:
  1. `cargo clippy --workspace --all-targets --all-features --message-format=json -- -W <31 lints>` (all targets);
  2. the same with `--lib --bins` (production targets);
  3. `--lib --bins` with 25 more candidate lints.
  The scratch `clippy.toml` sets `allow-{unwrap,expect,indexing-slicing,panic,print,dbg}-in-tests = true`. "Prod" counts below also drop `testkit.rs`, `harness.rs`, `sim.rs`, `*-sim` bins and `examples/` (they compile under `--all-features` but are test support). Hits are de-duplicated by `(lint, file, line, column)`. `too_many_lines` uses the default threshold of 100 lines.
- **Greps.** A scanner over non-test source (`#[cfg(test)] mod` cut off, `tests/` skipped) counted patterns that clippy cannot see. The counts are labelled "grep" and are approximate.
- **Prior work.** The findings of `docs/security/review-2026-10-31.md` and ADR 0031 are not repeated. The open ones touch this audit in places: ADM-1 and AI-2 (gaps); SDK-3, SDK-4, WASM-2, D-6, GW-4..6 (Low, "next"). They are referenced where they apply.
- **Not done.** No fuzzing (the S1 fix adds a fixed-seed fuzz table of the date parsers). No runtime test against a live gateway: the two network findings (S1, S2) were confirmed by reading the code path and by a mirror of the exact string logic (S2) or a standalone reproduction of the slicing (S1).

## 1. Summary

The code is **much better on panics and I/O than the owner fears**. There are only 14 production `unwrap()` calls, and each one is guarded right above. Network clients run under timeouts. The CBOR decoder bounds depth and never pre-allocates from a header. Logs carry no secrets. Driver, portable and flow hosts contain panics.

The real debt is **typing at the edges between components**:

- Action arguments and stored records are read field by field from `wyrm_core::Value` maps (≈508 `Some(Value::…(` matches, ≈343 `.get("literal")` reads, ≈127 `arg(args, "x")`/`arg_str` calls). The argument schema is declared twice: once as `ParamMeta` (which the SDK validates) and once as these hand reads. The repo already has a typed answer, `#[derive(Params)]`/`ParamEnum`, but only drivers use it.
- Closed sets are carried as `String` and `&[&str]` (31 fields documented as a closed set, ≈146 inline `&["a","b"]` sets, 114 `const X: [&str; N]`). Enum indices from the wire are turned back into strings and matched again.
- Numbers from the wire go through `f64` and `as` (774 `as` conversions, 308 possibly truncating). Twice this makes a quality or status **fail open**: a missing or fractional code becomes `0`, which is `Good`/`Ok`.
- Errors are `String` (≈630 `Result<_, String>`, ≈497 `map_err(|e| e.to_string()/format!)`), so callers and tests can only match text.

Two concrete defects came out of the typing debt and reach the network: **S1** (a panic from gateway input) and **S2** (a bypass of the GW-2 history row cap by text injection into a selector).

| ID | Sev | Area | Finding | Status |
|---|---|---|---|---|
| S2 | Medium/Low | gateway → historian | `from`/`to` text is pasted into the Zenoh selector unescaped: `&limit=100000` in `from` lifts the 10 000-row cap (GW-2) to 100 000 | fixed |
| T1 | Medium | flow | `q` and status codes read as `f64 as u8`: missing, negative, NaN or fractional values become `Good` / `Ok` (fail-open quality) | open (§6 step 2) |
| T2 | Medium (latent security) | gateway | WS `op` is a `String` matched in 7 separate places; authorization and dispatch are two different `match` blocks | open (§6 step 6) |
| T3 | Medium | admin, gateway, links | Action args read field by field; schema declared twice (`ParamMeta` + hand reads); 15+ copies of the same helpers | open (§6 step 7) |
| T4 | Low/Medium (latent security) | gateway | Role grants stored as `(String, u8)`; on read an unknown code silently **drops** the grant, and in a first-match list a dropped restrictive grant widens access | fixed |
| S1 | Low | historian | `parse_iso` slices at fixed byte offsets after checking only some bytes: a multibyte char in `from` panics the answer task | fixed |
| T5 | Low/Medium | everywhere | Closed sets as `String` (`Device.platform/alg`, `TaskRec.state`, `Job.kind/status/sealed`, `UpdateReport.result`, `Manifest.kind`, `Grant.level`, flow `on_bad/quality/func`, `UpdatesSection.mode`) | open (§6 step 8) |
| T6 | Low | core | `wire_enum!` has no `from_name`/`FromStr`: 14 hand-written `ALL…find(name ==)` lookups, with two- and three-form inputs (code, name, display) | open (§6 step 5) |
| T7 | Low | everywhere | Typed errors missing: 13 files define error types, ≈630 `Result<_, String>` | open (§6 step 10) |
| S3 | Low | gateway | Three RNG-failure policies: `expect` (oauth), refuse (`register`), silently zero (`Nonces` key, `new_jti`) | open (§6 step 11) |
| S4 | Low | links, admin | 8 hand-written URL splitters with different rules; `url` is already a dependency | open (§6 step 11) |
| S5 | Low | ffi | 39 unsafe operations in `unsafe fn` bodies without `// SAFETY:`; `unsafe_op_in_unsafe_fn` not denied | open (§6 step 4) |
| X1 | — | structure | 101 production functions over 100 lines; the top 3 are 600, 599 and 413 lines | open (§6 step 10) |

## 2. Typing

### T1 — Medium — quality and status codes through `f64 as u8` fail open

Evidence:
- `crates/wyrm-flow/src/nodes.rs:752-754` (expression node, `quality: custom`):
  ```rust
  let q = match m.get("q").and_then(Value::as_f64) {
      Some(x) => Quality::try_from(x as u8).unwrap_or(Quality::Bad),
      None => q,            // q is Quality::Good for "custom" (line 746)
  };
  ```
  `Quality::Good = 0` (`crates/wyrm-core/src/value.rs:13`). A rhai script that returns `q: 0.9`, `q: -1` or `q: NaN` gives `0 as u8` → **Good**. A script that returns `q: "bad"` (a string) gives `None` → the default, which for `custom` is **Good**. Lost or bad data is published as good, which breaks the "honest quality" rule in `CLAUDE.md`.
- `crates/wyrm-flow/src/readers.rs:605-606`: `let code = r.get("code").and_then(Value::as_f64).unwrap_or(0.0) as u8; Status::try_from(code)`. A failed read (`m.q == Bad`) without a `code` field becomes `Status::Ok` (`0x00`, `status.rs:5`). The project's own refusal rule (codes below `0x20` read as success) makes this the wrong way round.
- `crates/wyrm-flow/src/readers.rs:616` and `crates/wyrm-flow/src/commands.rs:488` follow the same pattern.
- The pattern in general: 56 `and_then(Value::as_f64)` reads in production code. Integer arguments that come in as `Value::UInt` are read as floats and cast: `control.rs:4178` (`rev` → `as u32`: −1 → 0, 1.7 → 1, 5e9 → `u32::MAX`), `control.rs:2458`, `history.rs:149/165/645/652/663`. The SDK's own `Fields::u64_or` and alarm's `get_u64` accept a float with a zero fraction, so the "integer from a float" rule exists in three variants.

Why it matters: CONTRIBUTING "Wire enums" rule 3 says an unknown code must be refused, never widened. `as u8` saturates (300 → 255) and truncates (1.9 → 1) silently. NaN → 0.

Fix:
- One decoder per code field: `fn quality_of(v: &Value) -> Option<Quality>` that accepts `Value::UInt` only, calls `u8::try_from` and `Quality::try_from`, and gives **Bad** for anything else.
- The same for `Status`, with `InternalError` as the fallback.
- A typed `ActionResult { code: Status, message: String }` decoder for the reply maps in `commands.rs`/`readers.rs`.
- Ban `as u8`/`as u16`/`as u32` on a value that came from `as_f64` (the checker rule C1 below).

### T2 — Medium (latent security) — gateway WS `op` as `String`, matched seven times

`crates/wyrm-gateway/src/ws.rs:259-269` `struct Req { op: String, action: Option<String>, suffix: Option<String>, … }`. The op string is compared at lines 456 (rate limit: `!= "unsubscribe"`), 465, 476 (`== "subscribe"`), 485 (authorization), 551, 604 (`at_config`) and 659 (dispatch). The authorization `match` (485) refuses unknown ops, so it fails closed today. But authorization and execution are two independent string matches. An op added to the dispatch at 659 and to `at_config` without the matching arm at 485, or a typo in one arm, changes what is checked. `suffix` is the same: `Some(s @ ("~state" | "~def"))`.

Fix: decode the frame once into `enum Op { Meta, Children, List, Subscribe, Unsubscribe, History, Set, Doc(DocSuffix), Invoke(Segment), Check(Segment) }`. Then write `fn required(&self, own) -> (KeyExpr, Perm)` and `fn dispatch(&self)` as exhaustive matches on the enum. A new op does not compile until it has a permission. The MCP path (`ws::serve_frames`) gets the same type for free.

### T3 — Medium — action arguments read field by field; the schema is declared twice

Evidence (grep, non-test source):
- `Some(Value::Str|UInt|Int|Bool|Float|Map|Array|Bytes(` in field reads: **508**. Top files: `wyrm-admin/src/control.rs` 42, `control/replication.rs` 22, `wyrm-filestore/src/store.rs` 18, `wyrm-messenger/src/model.rs` 17, `links/agent/src/lib.rs` 16, `wyrm-flow/src/nodes.rs` 16.
- `.get("literal")`: **343**. Top: `wyrm-flow/src/def.rs` 22, `links/alarm/src/model.rs` 20, `tools/wyrm-mcp/src/gw.rs` 18.
- `arg(&args, "…")` 58, `arg_str(` 69, `opt_str(` 25, `get_str(m, "` 21.
- Copies of the same readers: `arg`/`arg_str` in `wyrm-admin/src/control.rs:2642,2649`, `wyrm-admin/src/history.rs:126,133`, `wyrm-storage/src/lib.rs:239,246`, `links/agent/src/lib.rs:1435`. `opt_str`/`req_str` are identical in `links/dql/src/lib.rs:57,66` and `links/scheduler/src/lib.rs:92,100`. `get_str`/`req_str`/`get_bool`/`get_u64`/`enum_arg` are in `links/alarm/src/model.rs:26-76`. `text(cfg, key)` appears five times in `links/{mongodb,influxdb,postgres,mysql,dynamodb}/src/lib.rs`, plus `links/uplink/src/platform.rs:335`. The shared ones are not used: `wyrm_link_sdk::params::Fields` (has `only()` for unknown keys) and `wyrm_link_api::args::enum_name` (used by 2 crates).
- The SDK already validates arguments against the declared `ActionMeta` (`crates/wyrm-link-sdk/src/runtime.rs:1395` `validate_args`: unknown names, `required`, type, enum range). The handler then reads the same names again by hand, with its own defaults. These can disagree with the declaration:
  - `control.rs:4018,4038` `arg_str(&args, "name").unwrap_or_default()`;
  - `control.rs:5376` `enabled = !matches!(arg(args, "enabled"), Some(Value::Bool(false)))`. The same idiom appears in `driver/framework.rs:1078`, `filestore/store.rs:194,1402`, `links/dql/src/store.rs:66`, `links/{mongodb,postgres,mysql}`. For stored maps and history-sync `cfg`, no SDK check runs before it, so a wrong type is silently "true".
- Enum params round-trip through strings. The SDK accepts an enum argument only as its index (`runtime.rs:1575-1586`). `links/alarm/src/model.rs:72` `enum_arg` turns the index into a `String`. `links/alarm/src/lib.rs:1841` `cursor_from` then matches `"start" | "now" | _ => Err(…)`, an arm that cannot be reached. `admin/src/history.rs:144` `arg_logging` accepts "display name, name or index". `wyrm-history/src/engine.rs:78` accepts name or display. `wyrm-flow/src/def.rs:165` `perm` accepts code or name.
- What the owner saw tonight belongs here too: `restore_part`'s `data` lacked `editor: file` until today (`crates/wyrm-admin/src/control/restore.rs:1083-1090`, amended 2026-11-15). Gateway behaviour (a binary argument may travel outside the WS frame) hangs on `ParamMeta.editor: Option<String>` (`crates/wyrm-core/src/meta.rs:76`) and six string constants (`meta.rs:714-726`).

Fix:
- Make the typed derive the only way an action reads its arguments. Extend `#[derive(Params)]` (or add a sibling `#[derive(Args)]`) so that one struct gives both `ActionMeta` (the declaration) and `from_value` (the decoder). Fields are typed `Option<T>`, `ParamEnum` enums, `Bytes` with `#[param(editor = file)]`, and so on.
- Admin, gateway HTTP/WS bodies, alarm, scheduler, dql, messenger, uplink, agent and the history-sync `cfg` move onto it.
- `editor` becomes a `ParamEnum` (`Password | Textarea | File | Daterange | Date | Duration`). Unknown strings in a received `~meta` decode to `Other(String)`, so spec "UIs ignore others" still holds.

### T4 — Low/Medium (latent security) — role grants stored as `(String, u8)`; unknown codes dropped

**Status: fixed** (PR #108). `Op::SetRole` and `UserDb::roles` hold `RoleGrant { key, perm: Perm }`, encoded in the old tuple layout (SCHEMA stays 5; older stores open unchanged). An unknown code is a decode error of the WAL record and of the snapshot: the store does not open, and the error names the key and the code (ADR 0029 item 12: refuse, never drop a grant or empty a role). Before the fix a SCHEMA 5 snapshot with an unknown code opened (replay alone refused it through `apply`). Tests: `unknown_level_code_refuses_the_store`, `grants_of_an_older_store_load_typed` in `crates/wyrm-gateway/src/users.rs`. Still open here: `wyrm_link_sdk::package::Grant.level` as a name (below; goes with T5).

- `crates/wyrm-gateway/src/users.rs:159`: `pub roles: BTreeMap<String, Vec<(String, u8)>>`.
- `crates/wyrm-gateway/src/lib.rs:837-847` `table_of`: `.filter_map(|(k, c)| Some((k.clone(), Perm::try_from(*c).ok()?)))`.
- Grants are evaluated first-intersect (`wyrm_core::ptok::level_on`, ADR 0031 DQL-2). A restrictive grant listed before a broad one only works while it is present. If its code does not decode, `filter_map` removes it and the broad grant below decides: access widens.
- Today `users.rs:316` refuses unknown codes when an op is applied, so the drop is not reachable from the API. It is reachable from a store written by a newer version (a new `Perm` code), from a restore, or from a later change to the check.

Fix: store `Vec<Grant { key: String, perm: Perm }>` with `Perm` encoded through `wire_enum!`. On load, an unknown code is a load error (refuse the store, or keep the role with its grants `None` on that key), never a silent removal. The same applies to `wyrm_link_sdk::package::Grant { path, level: String }` (`package.rs:177`): its level is matched by name in `wyrm-admin/src/packages.rs:421`.

### T5 — Low/Medium — closed sets as `String`

Mechanical count: **31** `String`/`Option<String>` fields whose doc comment lists backticked alternatives (checker C3 below; about 20 of them are true closed sets on inspection). Examples:

| Where | Field | Values |
|---|---|---|
| `crates/wyrm-gateway/src/users.rs:140-141` | `Device.platform`, `Device.alg` | `PLATFORMS: [&str;4]` (`devices.rs:54`); `alg` is parsed to `KeyAlg` at registration, stored back as `String`, and re-parsed with `KeyAlg::of(&d.alg)` at every login (`devices.rs:881,982`) |
| `links/agent/src/store.rs:39` | `TaskRec.state` | the typed `TaskState` already exists; `state_from_name` at `:465` turns it back |
| `crates/wyrm-admin/src/control/backups.rs:140,145,162,172` | `Job.kind/status/sealed/send_status` | `full|link|pre-update|pre-restore`, `running|done|failed`, `none|passphrase|broker`; compared as `job.status != "done"` (`:1563`) |
| `crates/wyrm-admin/src/registry.rs:656` | `UpdateReport.result` | `checking|ok|rolled_back|failed` |
| `crates/wyrm-admin/src/release.rs:1350`, `control/broker_update.rs:119` | `state` | release states |
| `crates/wyrm-link-sdk/src/package.rs:31,177` | `Manifest.kind`, `Grant.level` | `process|wasm`; a `Perm` name |
| `crates/wyrm-flow/src/nodes.rs:1048,1093` | `on_bad: String` | `hold|clear|raise`, written 4 times: `catalog.rs:335`, `nodes.rs:434`, `nodes.rs:1433`, and the match at `nodes.rs:1093` (`_ => {}` = hold) |
| `crates/wyrm-flow/src/nodes.rs:744` | `quality: String` | `worst|ignore|custom` |
| `crates/wyrmd/src/update.rs:73` | `UpdatesSection.mode: String` | parsed by hand on every call although serde could reject it at load |

Supporting counts (grep): ≈146 inline `&["a", "b", …]` literal sets, 114 `const/static X: [&str; N]`, 101 `match <x>.as_str()|as_deref()` dispatches.

Fix: one `enum` per set, with `name()`/`from_name()` (a `wire_enum!`-like `name_enum!` for sets without wire codes, or `ParamEnum`). The flow catalog, the validator and the runtime then read from `Enum::ALL`. Serde and minicbor derive on the enum; the store keeps the enum.

### T6 — Low — `wire_enum!` has no name lookup

`crates/wyrm-core/src/wire.rs:30-77` generates `code`, `name`, `ALL` and `TryFrom<u8>`, but not the way back from a name. Result: 14 hand-written `X::ALL.iter().find(|p| p.name() == s)`:
- `gateway/approve.rs:177`
- `admin/packages.rs:421`
- `admin/control.rs:4150,4258`
- `history/rollup.rs:60`
- `history/engine.rs:78`
- `flow/def.rs:170`
- `flow/engine.rs:258`
- `messenger/model.rs:101`
- `agent/store.rs:465`
- `agent/tools.rs:180,746`
- `uplink/platform.rs:61`
- `wyr/main.rs:625`

Fix: generate `pub fn from_name(&str) -> Option<Self>` and `impl FromStr`, then replace the 14 sites.

### T7 — Low — errors as `String`

- ≈630 `Result<_, String>` (top: `admin/release.rs` 35, `control/backups.rs` 26, `restore_broker.rs` 23, `messenger/model.rs` 22, `flow/nodes.rs` 21).
- ≈497 `map_err(|e| e.to_string()/format!(…))`.
- clippy `map_err_ignore`: 263 in production code. The original error is dropped, so the cause chain is lost.
- Only 13 files derive an error type; 6 use `Box<dyn Error>`.
- Tests can only assert on text, for example `backup.rs:1384` (`e.contains("changed")`), `release.rs:2339`, `updates.rs:2416` and `restore_broker.rs:1905`.

Fix: one `thiserror` enum per crate boundary, starting with `wyrm-admin` (`AdminError { Io{path, source}, Invalid(&'static str, String), Busy, … }`) with `From<AdminError> for LinkError`. Ban `Result<_, String>` in `pub fn` (checker C5).

## 3. Security

### S2 — Medium/Low — history selector built from raw user text (GW-2 cap bypass)

**Status: fixed** (PR #108). `wyrm_core::history::HistoryQuery` holds `from: TimeUs`, `to: Option<TimeUs>`, `rollup: Rollup`, `window: Option<Window>`, `limit: Option<NonZeroUsize>`; `from_text`/`from_args` parse the request and `params()` writes only typed values. The historian parses into the same type and refuses a repeated parameter, `history` with `since`, and any other parameter except Zenoh's `_…` (spec 01 0.2.35, ADR 0029 item 13). The gateway caps the typed `limit` (`capped_history`); a refused argument answers before a selector exists (gateway and FFI). `time.rs` moved to `wyrm_core::time` and `Rollup` to `wyrm_core::history`, one parser for both sides. Tests: `injected_parameters_are_refused` (wyrm-core), `selectors` (wyrm-history; it failed on the old parser with limit 100 000), `history_reads_are_capped_and_typed` (gateway `ws.rs`), and the e2e `history_records_and_answers` asks the running historian with a repeated and an unknown parameter.

Other places that put request text into a selector (checker rule C7), checked with the fix:
- `WyrmClient::history(node, …)`: now refuses a `node` that is no key expression (a `?` or `#` would add parameters). The gateway (`check_key`) and the agent link (`node_key`) already refused them; the FFI passes the caller's key unchecked to every other client call (the caller is the session's owner, so it can only change its own query).
- `WyrmClient::resolve(node, matcher, …)`: `matcher` was pasted after `&match=`; it now refuses `&`, `=`, `?` and `#`. It comes from the caller in `wyrm-mcp` `tree_resolve` and in the agent link's `tree_resolve`.
- Action names become a key segment (`<node>/~act/<action>`, `?check` after it): the gateway WS and `POST /api/invoke`, `wyrm-mcp` and the agent link check them with `keyspace::validate_segment` (no `?`, `#`, `/`, wildcards); the FFI does not (its own session, as above).
- Not changed, listed: `WyrmClient::meta_raw` (and so `meta`, `children`, `resolve`) and `doc` build `<node>/~meta?…` from `node` without a check of their own (the callers above check it); `WyrmClient::profile(site, name)` puts `name` into a key, and `meta_expanded` takes that name from a responder's `~meta` (`is`); `wyrm-link-sdk` `harness.rs` uses constants (test support).

Path:
1. Gateway WS `history` (`crates/wyrm-gateway/src/ws.rs:667-675`) builds `wyrm_client::HistoryQuery::from_args(req.args)` and caps `q.limit` at `HISTORY_LIMIT = 10_000` (`gateway/src/lib.rs:384`, review GW-2).
2. `HistoryQuery::from_args` (`crates/wyrm-client/src/lib.rs:204`) takes `from`/`to`/`agg`/`window` as free text.
3. `HistoryQuery::params` (`lib.rs:229`) pastes the text into the selector: `format!("history={}..{}", self.from.trim(), self.to.trim())` + `&limit=…`.
4. The historian (`crates/wyrm-history/src/query.rs:67-100`) splits on `&` and `;` and takes the **first** `limit=`, capped at `MAX_LIMIT = 100_000` (`query.rs:17`).

With `from = "2026-01-01T00:00:00Z..&limit=100000&x="`, the selector is `history=2026-01-01T00:00:00Z..&limit=100000&x=..&limit=10000`. `history` parses as `<from>..now` and `limit` reads 100000. This was checked by mirroring the two functions. Any user with `read` on a recorded point gets 10× the per-request cap that GW-2 set. `agg` and `window` can be injected the same way. The FFI (`wyrm_history`) and `wyrm-mcp` use the same builder.

Fix (typing): parse `from`/`to` to `u64` µs in `from_args` (`wyrm_history::time::parse_iso`, after S1 is fixed) and refuse otherwise. Make `HistoryQuery` hold `from_us: u64, to_us: Option<u64>, agg: Option<Rollup>, window: Option<Interval>, limit: Option<NonZeroUsize>`, and have `params()` write only those typed values. As a stopgap, refuse `&`, `;`, `=` and control characters in the four text fields. Add a test.

### S1 — Low — char-boundary panic in RFC 3339 parsing (reachable from the gateway)

**Status: fixed** (PR #108). `parse_iso` and `parse_day` match the input as byte slices and read digits with checked arithmetic. Tests: `non_ascii_text_is_refused_not_a_panic` (the two inputs below panicked before) and `arbitrary_text_never_panics`, a fixed-seed fuzz table: every valid stamp cut at each byte, each byte replaced by and preceded by twelve hard characters, and 200 000 random strings of ASCII and multibyte characters, through `parse_iso`, `parse_day`, `parse_range` and `parse_interval` (the workspace has no `proptest`). The parsers now live in `crates/wyrm-core/src/time.rs`.

`crates/wyrm-history/src/time.rs:82-87`. `parse_iso` checks `b.len() >= 8 && b[2] == b':' && b[5] == b':'`, then slices `rest[6..8]`. If byte 7 starts a 2-byte character, index 8 is not a char boundary and the slice panics. Input `2026-10-22T00:00:0é` was reproduced in a scratch program (`rest[6..8] panics: true`). A second instance is `time.rs:104` `&o[3..4]` with `o.len() == 6` (for example `+0é00`).

Reach:
- `parse_selector` (`query.rs:67`) runs for every `~val?history=` query on the historian's keys, before any series check.
- Through S2's path, any gateway user can put the text in `from`.
- Admin Get History `timerange` (`admin/src/history.rs:619-620` → `parse_range`, config level) is another path.

Effect: `answer` runs in `tokio::spawn` (`query.rs:178`), so the task panics, the query gets no reply, and the client waits for its timeout. The process lives (no `panic = "abort"` in `[profile.release]`). The defect is Low, but it is real and remote.

Fix: parse on bytes (`b[6..8]` after `b[..8].is_ascii()`), or use `split_at_checked`/`get(..)`. Run the parser under `proptest` (arbitrary strings, no panic). clippy `string_slice` flags 152 such slices in production code. Most index after an ASCII `find()` and are sound, but the fixed-offset ones on input text need this review: `history/time.rs`, `flow/blocks/date.rs:185-190` (sound: ASCII-checked), `messenger/lib.rs:84-89` and `uplink/lib.rs:98-103` (sound: own formatted date).

### S3 — Low — three policies for an RNG failure

- `crates/wyrm-gateway/src/oauth.rs:176` uses `expect("OS random source")` (panic).
- `devices.rs:823` refuses with `Busy`.
- `devices.rs:427` `let _ = getrandom::fill(key.as_mut())` leaves the nonce MAC key at **zero**. Anyone can then mint valid challenges, which stay single use.
- `session.rs:204` `new_jti` leaves `jti` at zero. That `jti` is also bound into the device-registration purpose (`devices.rs:813-816`), so all sessions of a user then share it.

On a supported OS, `getrandom` practically never fails, so this is a consistency rule, not an exploit. Fix: one `wyrm_core::rand::fill(&mut [u8]) -> Result<(), RngError>` that fails closed. Ban direct `getrandom::fill` through `clippy::disallowed_methods` (32 call sites).

### S4 — Low — eight hand-written URL splitters

They are in:
- `wyrm-admin/src/fetch.rs:30-60`
- `wyrm-filestore/src/http.rs:51-58`
- `wyrm-history-sync/src/http.rs:223`
- `links/agent/src/llm.rs:88`
- `links/http/src/client.rs:49-80` and `:628`
- `links/prometheus/src/http.rs:72-88`
- `wyrm-gateway/src/oauth.rs:99-112`

The rules differ. `fetch.rs` ends the authority at `/` only, `http/client.rs` at `/?#`. IPv6 handling differs. Some strip the scheme case-insensitively, some do not. `fetch.rs` echoes the whole URL in its errors (`"{url}: bad port"`), which can carry a query-string token (compare HS-4, fixed for history sync; ADM-6 open). No SSRF bypass was found: `outbound` checks the resolved address that is then connected. Fix: one `Origin::parse` in `wyrm_link_sdk::outbound` (on `url`, already a workspace dependency), used by all eight, and errors that name only the host.

### S5 — Low — FFI unsafe without SAFETY notes

`crates/wyrm-ffi/src/lib.rs` is the only production crate with unsafe code (40 `unsafe_code` hits). It has 39 unsafe operations inside `unsafe fn` bodies (`E0133` under `-W unsafe_op_in_unsafe_fn`) and no `// SAFETY:` comment. `wyrm_buf_free(p, len)` (`:394`) is sound only if `len` is the exact length that was handed out. Fix: `#![deny(unsafe_op_in_unsafe_fn, clippy::undocumented_unsafe_blocks, clippy::multiple_unsafe_ops_per_block)]` in that crate. Write one `// SAFETY:` per block and a `# Safety` paragraph on each exported function.

### Info (no action needed, or covered elsewhere)

- Link admission tokens and remote link tokens are compared by `==` on their SHA-256 (`wyrm-admin/src/control.rs:833`, `:1381`). A timing leak of the hash does not help to find the token. `oauth.rs:821` hand-rolls a constant-time compare. Recommend one helper (`ring::constant_time::verify_slices_are_equal`).
- Secrets in driver params are plain `String`. They are kept out of `Debug` by convention (comment "No `Debug`: it holds secrets", `links/http/src/lib.rs:90`). `wyrm_link_sdk::support::Secret` redacts `Debug` and zeroizes; making `#[param(secret)]` require `Secret` turns the convention into a type rule.
- CBOR decoder (`crates/wyrm-core/src/value.rs:138-204`): duplicate map keys are accepted (last wins). The decoder is the same on every side, so there is no known differential. It is not "canonical" on input.

### Checked and sound

- **`unwrap`/`expect`/`panic`.** 14 production `unwrap()`. They are in `wyrm-state/src/lib.rs:398-468`, after length checks plus HMAC/CRC, and in `links/alarm/src/lib.rs:1892-2026` (`get_mut` after `contains_key`). The 43 `expect` are on invariants (HMAC any key length, encode of an in-memory `Value`).
- **I/O timeouts.**
  - Every outbound client wraps the whole exchange: `admin/fetch.rs:168`, `filestore/http.rs:622`, `http/client.rs:335,495`, `agent/llm.rs:204`, `prometheus` (connection timeout), `wyrmd/arbiter.rs:466`, `standby.rs:87`, `gateway-client` (`REQUEST_TIMEOUT`), `modbus/lib.rs:709`, `s7/client.rs:74`.
  - Portable/WASM hosts use `connect_timeout`.
- **Allocation from input.**
  - `Value` decode: depth ≤ 32, no capacity from headers.
  - Sealed parts are bounded (`backup.rs:719`), the arbiter bounds its frames (`arbiter.rs:181`), and download parts are clamped (`backups.rs:1569-1585`, `replication.rs:614`).
  - `read_full` callers pass the constant `SEAL_PART`.
- **Wire decoders.** snmp `ber.rs`, s7 `proto.rs` and bacnet check lengths before they index (sampled). Panics in drivers, portable apps and flows are caught (`catch_unwind` in `driver/framework.rs`, `runtime.rs`, `link-portable/native.rs`, `flow/runtime.rs`).
- **Paths.** Zip entries use `enclosed_name` (`packages.rs:349`). The backup reader refuses entries that are not in the signed manifest, directories and symlinks (`backup.rs:1035-1046`). Restore places files by `place_of` (`restore_broker.rs:168`).
- **Logs.** No `tracing` macro takes a token, password or secret. `Secret` redacts `Debug`. mqtt `Conn` holds `Secret`.

## 4. Structure

### X1 — functions too large to review

101 production functions exceed 100 lines; 15 exceed 200 and 3 exceed 400.

| Lines | Function |
|---:|---|
| 600 | `crates/wyrm-flow/src/blocks.rs:1311` `calculate` (one match over all block kinds) |
| 599 | `crates/wyrm-admin/src/registry.rs:1040` (`Op` apply) |
| 413 | `crates/wyrm-flow/src/blocks/tables.rs:439` |
| 343 | `crates/wyrm-admin/src/control.rs:4000` `on_invoke` (≈45 `(path, action)` string arms) |
| 340 | `crates/wyrm-flow/src/engine.rs:1297` |
| 270 | `links/probe/src/runner.rs:218` |
| 265 | `crates/wyrm-flow/src/blocks.rs:500` |
| 255 | `crates/wyrmd/src/lib.rs:1510` |
| 254 | `crates/wyrm-link-sdk/src/driver/framework.rs:2526` |
| 228 | `crates/wyrm-admin/src/control/updates.rs:1350` |
| 213 | `crates/wyrm-admin/src/control/restore_broker.rs:918` |
| 210 | `crates/wyrmd/src/update.rs:677` |
| 201 | `crates/wyrm-link-sdk/src/driver/framework.rs:3199` |
| 189 | `crates/wyrmd/src/lib.rs:2226` |
| 189 | `crates/wyrm-admin/src/history.rs:745` |

Largest production files: `wyrm-admin/src/control.rs` 7 463 lines, `driver/framework.rs` 4 131, `bacnet/lib.rs` 3 408, `agent/lib.rs` 3 207, `wyrmd/lib.rs` 3 081, `admin/release.rs` 3 034. `cognitive_complexity` flags 55 functions (20 of them in `wyrm-admin`).

`on_invoke` is the structural twin of T2/T3. With one typed `Action` enum per node (`enum SysAction { Install(InstallArgs), Enroll(EnrollArgs), … }`, decoded by the derive in T3), the 343-line match becomes a table, and each handler takes its own typed struct.

### X2 — duplicated helpers (counts of definitions)

- `now_us`/`now_s`/`now_ms`: 33 definitions, each with an `as u64` from `u128`. `SystemTime::now()` is called directly 33 times.
- Hex encode/decode: 12, including `wyrm-flow/src/engine.rs:157` named `wyrm_core_hex`.
- `sha256_hex`: 4.
- URL splitters: 8 (S4).
- Argument readers: 15+ (T3).
- `read_full`: 2.

Put one copy of each in `wyrm-core` (clock behind a trait where tests need it).

### X3 — clones on hot paths

Nothing obvious stands out. `redundant_clone` gives 12 hits and `needless_pass_by_value` 52, none on a sample/value path that was checked. No action.

## 5. Enforceable rules

### 5.1 Workspace lints (measured cost)

No member manifest has a `[lints]` table today. Step 0 is to add `[workspace.lints]` to the root `Cargo.toml` and `[lints] workspace = true` to the 55 member manifests. Per-crate opt-outs go in the crate's own `[lints]` or `#![allow(…, reason = "…")]`.

Hit counts are production code (see §0). "All" includes tests with the `allow-*-in-tests` settings.

| Lint | Level proposed | Prod | All | Main crates (prod) | Note |
|---|---|---:|---:|---|---|
| `clippy::unwrap_used` | deny (non-test) | 14 | 626 | wyrm-state 7, alarm 7 | cheap: replace with `expect("why")` or `?` |
| `clippy::expect_used` | warn → deny in network crates | 43 | 257 | gateway 15, link-sdk 9 | most are invariants; `expect` with a reason is fine where `unwrap_used` is denied |
| `clippy::panic`, `todo`, `unimplemented`, `dbg_macro` | deny | 1 / 0 / 0 / 0 | 169 | — | nearly free |
| `clippy::unreachable` | warn | 15 | 28 | uplink 5 | |
| `clippy::string_slice` | deny, with a baseline | 152 | 175 | flow 25, filestore 18, admin 18, messenger 15, prometheus 14, history 12 | catches S1-type bugs |
| `clippy::cast_possible_truncation` | deny, with a baseline | 308 | 376 | flow 47, admin 43, s7 24, modbus 24, bacnet 17, link-sdk 16 | prefer this to `as_conversions` |
| `clippy::cast_sign_loss` | deny, with a baseline | 127 | 145 | flow 29, admin 21, modbus 12 | |
| `clippy::cast_possible_wrap` | deny, with a baseline | 49 | 65 | flow 15 | |
| `clippy::cast_lossless` | warn | 31 | 34 | | auto-fixable (`From`) |
| `clippy::cast_precision_loss` | allow | 107 | — | | mostly intentional `u64 → f64` |
| `clippy::as_conversions` | **only** in `wyrm-core`, `wyrm-state`, wire codecs | 774 | 1042 | admin 124, flow 108 | too broad for the workspace |
| `clippy::indexing_slicing` | **only** in decoder modules (snmp `ber`, s7 `proto`, bacnet/modbus codecs, `wyrm-core` value/ptok, `wyrm-state` WAL), with a baseline | 707 | 900 | flow 78, bacnet 66, dql 66, s7 49 | most hits are sound after a length check |
| `clippy::arithmetic_side_effects` | **only** in the same decoder modules | 1458 | 1778 | flow 152, admin 146, s7 93 | too broad for the workspace |
| `clippy::let_underscore_must_use` | warn, with a baseline | 345 | 741 | admin 129, link-sdk 51, wyrmd 24 | most are `reply`/cleanup; `let _ = store.apply(…)` (`gateway/devices.rs:1125`) hides a write failure |
| `clippy::map_err_ignore` | warn | 263 | 267 | admin 32, link-sdk 22 | goes with T7 |
| `clippy::print_stdout` / `print_stderr` | deny outside `wyrmd/src/cli.rs` and `tools/*` | 33 / 20 | 67 / 28 | wyrmd 24, wyr 8 | |
| `clippy::exit` | deny outside `main` | 4 | 4 | | |
| `clippy::allow_attributes_without_reason` | deny | 17 | — | gateway 4, client 3, flow 3 | cheap; makes every exception explain itself |
| `clippy::too_many_lines` (threshold 150) | warn, with a baseline | 101 (at 100) | 203 | admin 30, flow 22, wyrmd 8 | |
| `clippy::cognitive_complexity` | warn, with a baseline | 55 | 74 | admin 20 | |
| `clippy::struct_excessive_bools` / `fn_params_excessive_bools` | warn | 8 / 0 | 10 | | the "bool flags that should be enums" pattern is rare |
| `clippy::wildcard_enum_match_arm` | allow | 461 | 638 | | too noisy |
| `clippy::significant_drop_in_scrutinee` | warn | 7 | — | | checked: no lock held across an await |
| `clippy::float_cmp` | allow | 19 | — | | sentinel `scale == 1.0` |
| `clippy::disallowed_methods` (clippy.toml) | deny | — | — | | ban `getrandom::fill` (32), `SystemTime::now` (33), `serde_json::to_vec/from_slice` in wire crates, `std::fs::*` in admin modules that must use `nofollow` |
| `unsafe_code` (rustc) | **deny** workspace-wide | 40 (all `wyrm-ffi`) | 68 | | `forbid` breaks `wyrm-link-guest` (`#[allow(unsafe_code)]` on generated bindings, `lib.rs:24`) and `wyrm-flow/tests/preview_cost.rs` (GlobalAlloc); `wyrm-ffi` opts out |
| `unsafe_op_in_unsafe_fn` (rustc) + `clippy::undocumented_unsafe_blocks` | deny in `wyrm-ffi` | 39 | 39 | ffi | |

`#![forbid(unsafe_code)]` is present in 31 crates. These 27 have neither `forbid` nor `deny`:
- crates: `wyrm-dql`, `wyrm-history`, `wyrm-history-sync`, `wyrm-link-sdk-derive`, `wyrm-messenger`, `wyrm-schedule`, `wyrmd`, `wyrm-ffi`;
- links: `alarm`, `dql`, `dynamodb`, `influxdb`, `mongodb`, `mysql`, `postgres`, `probe`, `scheduler`, `slack`, `telegram`, `uplink`, `wasm`;
- tools: `wyr`, `wyrm-mcp`;
- the 4 example links.

None of them except `wyrm-ffi` has an unsafe block, so the workspace `deny` costs 0 edits outside ffi.

A suggested starting set for `[workspace.lints.clippy]` with zero or near-zero edits: `panic`, `todo`, `unimplemented`, `dbg_macro`, `exit`, `allow_attributes_without_reason` (17 edits), `unwrap_used` (14 edits). Then the baselined set: `string_slice`, `cast_possible_truncation`, `cast_sign_loss`, `cast_possible_wrap`, `let_underscore_must_use`, `too_many_lines`.

### 5.2 A Rust rules checker (patterns clippy cannot see)

Model it on `studio/tool/check_rules.dart`: a small script (`tools/check-rules`, Rust or Python) that runs in CI next to clippy. It keeps a per-file baseline (`tools/rules_baseline.json`). A count may only go down, and a new file starts at zero. Every rule has an `allow` marker (`// rules: allow(C2) <reason>`). Counts below are from this audit's scan of non-test source.

| Rule | Pattern | Allowed in | Count today |
|---|---|---|---:|
| C1 | `as u8` / `as u16` / `as u32` outside `wyrm-core/src/wire.rs` (code tables), and any `as <int>` within 3 lines after `as_f64` | wire.rs, byte-packing modules with a reason | 33 (`as u8`); 56 `and_then(Value::as_f64)` sites |
| C2 | `ALL` … `.name() ==` (hand lookup of a name) | none, after T6 | 14 |
| C3 | a `String`/`Option<String>` field whose doc line lists backticked alternatives | none | 31 |
| C4 | `Some(Value::<Variant>(` or `.get("<literal>")` on a `Value` map outside a decoder module (`decode.rs`, `impl FromValue`, `#[derive(Params)]` output) | decoders | 508 / 343 |
| C5 | `pub fn … -> Result<…, String>` | private helpers only | ≈630 (all, not only `pub`) |
| C6 | inline string sets `&["a", "b", …]` and `const X: [&str; N]` used with `contains`/`one_of`/`enum_arg` | key lists for `only()` | 146 / 114 |
| C7 | `format!(…{…}…)` into a Zenoh selector or key with a value that comes from a request (`format!("…?{}", …)`, `history=`) | typed builders | the S2 site, plus review |
| C8 | `let _ = getrandom::` / `let _ = store.apply(` / `let _ = …save(` (a dropped security or persistence result) | none | 2 RNG + review |
| C9 | `fn now_us|now_s|now_ms|hex|unhex|sha256_hex` defined outside `wyrm-core` | none | 33 + 12 + 4 |
| C10 | a `#[param(secret)]` field whose type is not `Secret` | none | ≈15 fields (http, opcua, s3, snmp, webdav, mock) |

## 6. Order of work

Steps 1 and 3 are done (see the status at the top). The others are open, in this order.

1. **Done:** **S2 + S1 (one PR, `wyrm-client` + `wyrm-history`).** Make `HistoryQuery` typed (parsed µs, `Rollup`, interval, `NonZeroUsize`). Make `parse_iso` byte-safe. Add a test for the injection and a proptest for "never panics".
2. **T1 (`wyrm-flow`).** Add `quality_of`/`status_of` decoders that fail to Bad / InternalError, and a typed `ActionResult`. Add a test for `q: 0.5`, `q: "bad"` and a missing `code`.
3. **Done:** **T4 (`wyrm-gateway`).** Store `Perm` in role grants and refuse unknown codes at load.
4. **Lint step 0.** Add `[workspace.lints]` and `lints.workspace = true` in 55 manifests, `unsafe_code = "deny"` (ffi opts out), and the zero-cost clippy set. Write SAFETY notes in `wyrm-ffi` (S5).
5. **T6.** Add `from_name`/`FromStr` to `wire_enum!` and replace the 14 lookups.
6. **T2.** Make the gateway `Op` enum one exhaustive permission table.
7. **T3 core.** Extend `#[derive(Params)]` to actions (declaration and decoder from one struct; `editor` as an enum). Move `wyrm-admin` `sys/**` actions first, then gateway HTTP bodies, alarm, scheduler, dql, messenger, uplink and agent. Delete the copied readers.
8. **T5.** Make closed-set fields enums (start with `Device.platform/alg`, `TaskRec.state`, `Job.*`, `UpdateReport.result`, `Manifest.kind/Grant.level`, flow `on_bad/quality/func`). Write a store migration only where the stored form changes (CBOR string → same string via a name enum needs none).
9. **Checker C1–C10 with a baseline in CI.** Then the baselined clippy set (`string_slice`, `cast_*`, `let_underscore_must_use`, `too_many_lines` at 150).
10. **T7 + X1.** Typed errors per crate. Split `on_invoke`, `registry::apply` and `blocks::calculate` along the new typed enums.
11. **S3, S4, X2.** One RNG helper, one URL parser and one clock/hex module, enforced by `disallowed_methods` and C9.

## Appendix A — production hits per crate (selected lints)

| crate | unwrap | expect | index | strslice | as_conv | trunc | sign | wrap | arith | let_ | map_err | long_fn | allow_nr | print |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `crates/wyrm-admin` | 0 | 3 | 41 | 18 | 124 | 43 | 21 | 6 | 146 | 129 | 32 | 30 | 1 | 0 |
| `crates/wyrm-flow` | 0 | 1 | 78 | 25 | 108 | 47 | 29 | 15 | 152 | 17 | 6 | 22 | 3 | 0 |
| `links/s7` | 0 | 0 | 49 | 0 | 36 | 24 | 8 | 0 | 93 | 1 | 11 | 0 | 0 | 0 |
| `crates/wyrm-link-sdk` | 0 | 9 | 31 | 3 | 31 | 16 | 4 | 1 | 38 | 51 | 22 | 6 | 1 | 0 |
| `links/bacnet` | 0 | 0 | 66 | 0 | 28 | 17 | 3 | 0 | 50 | 0 | 10 | 1 | 0 | 0 |
| `crates/wyrm-filestore` | 0 | 0 | 8 | 18 | 44 | 12 | 4 | 2 | 54 | 19 | 6 | 1 | 1 | 0 |
| `crates/wyrm-dql` | 0 | 1 | 66 | 4 | 2 | 1 | 0 | 0 | 86 | 0 | 3 | 1 | 0 | 0 |
| `links/modbus` | 0 | 1 | 24 | 0 | 32 | 24 | 12 | 5 | 37 | 4 | 6 | 1 | 0 | 0 |
| `links/uplink` | 0 | 0 | 13 | 8 | 32 | 14 | 8 | 0 | 46 | 4 | 4 | 3 | 0 | 0 |
| `links/alarm` | 7 | 0 | 23 | 0 | 21 | 6 | 2 | 2 | 59 | 0 | 3 | 2 | 2 | 0 |
| `crates/wyrmd` | 0 | 2 | 2 | 2 | 15 | 8 | 0 | 0 | 33 | 24 | 7 | 8 | 0 | 24 |
| `links/snmp` | 0 | 0 | 37 | 0 | 12 | 3 | 2 | 1 | 56 | 1 | 11 | 1 | 0 | 0 |
| `crates/wyrm-state` | 7 | 3 | 18 | 0 | 16 | 4 | 0 | 0 | 63 | 0 | 1 | 0 | 0 | 0 |
| `crates/wyrm-schedule` | 0 | 0 | 24 | 2 | 0 | 0 | 0 | 0 | 67 | 0 | 9 | 3 | 0 | 0 |
| `links/agent` | 0 | 0 | 16 | 4 | 19 | 6 | 0 | 0 | 36 | 5 | 11 | 3 | 0 | 1 |
| `crates/wyrm-history` | 0 | 0 | 5 | 12 | 14 | 5 | 3 | 5 | 48 | 4 | 4 | 0 | 0 | 0 |
| `crates/wyrm-core` | 0 | 0 | 26 | 5 | 27 | 1 | 1 | 0 | 34 | 0 | 5 | 0 | 0 | 0 |
| `crates/wyrm-gateway` | 0 | 15 | 12 | 4 | 5 | 0 | 0 | 0 | 22 | 11 | 15 | 3 | 4 | 0 |
| `links/prometheus` | 0 | 0 | 18 | 14 | 12 | 3 | 1 | 0 | 31 | 1 | 7 | 0 | 1 | 0 |
| `crates/wyrm-messenger` | 0 | 0 | 6 | 15 | 14 | 2 | 2 | 0 | 36 | 2 | 1 | 7 | 0 | 0 |
| `links/opcua` | 0 | 0 | 13 | 0 | 16 | 6 | 1 | 0 | 8 | 14 | 15 | 2 | 0 | 0 |
| `links/http` | 0 | 0 | 4 | 6 | 7 | 1 | 0 | 0 | 37 | 1 | 14 | 1 | 0 | 0 |
| `links/mongodb` | 0 | 0 | 23 | 0 | 11 | 9 | 2 | 4 | 7 | 0 | 6 | 0 | 0 | 0 |
| `tools/wyr` | 0 | 1 | 6 | 0 | 13 | 5 | 2 | 0 | 12 | 7 | 3 | 3 | 0 | 8 |
| `crates/wyrm-history-sync` | 0 | 0 | 14 | 3 | 10 | 2 | 2 | 1 | 20 | 0 | 2 | 0 | 0 | 0 |
| `crates/wyrm-link-portable` | 0 | 0 | 1 | 0 | 7 | 2 | 1 | 0 | 21 | 19 | 2 | 0 | 0 | 0 |
| `links/dql` | 0 | 0 | 5 | 0 | 12 | 3 | 2 | 0 | 29 | 0 | 2 | 0 | 0 | 0 |
| `tools/wyrm-mcp` | 0 | 0 | 15 | 0 | 8 | 3 | 0 | 0 | 13 | 5 | 5 | 0 | 0 | 0 |
| `links/scheduler` | 0 | 0 | 7 | 0 | 8 | 2 | 1 | 3 | 22 | 0 | 3 | 0 | 0 | 0 |
| `links/mqtt` | 0 | 0 | 0 | 1 | 15 | 12 | 5 | 4 | 0 | 0 | 4 | 0 | 0 | 0 |
| `links/mysql` | 0 | 0 | 12 | 0 | 5 | 4 | 2 | 0 | 12 | 1 | 3 | 0 | 0 | 0 |
| `links/gdrive` | 0 | 0 | 12 | 1 | 1 | 0 | 0 | 0 | 13 | 0 | 6 | 0 | 0 | 0 |
| `crates/wyrm-link-sdk-derive` | 0 | 1 | 4 | 0 | 15 | 2 | 1 | 0 | 4 | 0 | 3 | 1 | 0 | 0 |
| `links/postgres` | 0 | 0 | 11 | 0 | 6 | 5 | 2 | 0 | 3 | 1 | 0 | 1 | 0 | 0 |
| `crates/wyrm-client` | 0 | 2 | 5 | 0 | 4 | 2 | 1 | 0 | 6 | 1 | 1 | 0 | 3 | 0 |
| `crates/wyrm-link-api` | 0 | 0 | 0 | 0 | 7 | 1 | 1 | 0 | 9 | 3 | 3 | 0 | 0 | 0 |
| `crates/wyrm-storage` | 0 | 1 | 0 | 1 | 1 | 1 | 0 | 0 | 16 | 1 | 2 | 0 | 0 | 0 |
| `links/mock` | 0 | 0 | 2 | 0 | 9 | 2 | 1 | 0 | 2 | 1 | 1 | 0 | 0 | 0 |
| `links/s3` | 0 | 0 | 0 | 2 | 4 | 1 | 0 | 0 | 10 | 1 | 0 | 0 | 0 | 0 |
| `crates/wyrm-wasm-host` | 0 | 3 | 1 | 0 | 5 | 1 | 0 | 0 | 5 | 1 | 1 | 0 | 0 | 0 |
| `crates/wyrm-gateway-client` | 0 | 0 | 2 | 0 | 0 | 0 | 0 | 0 | 1 | 5 | 9 | 0 | 0 | 0 |
| `links/probe` | 0 | 0 | 0 | 0 | 6 | 4 | 0 | 0 | 5 | 1 | 0 | 1 | 0 | 0 |
| `links/webdav` | 0 | 0 | 0 | 4 | 2 | 0 | 0 | 0 | 8 | 0 | 1 | 0 | 0 | 0 |
| `links/localfs` | 0 | 0 | 0 | 0 | 4 | 1 | 0 | 0 | 4 | 4 | 0 | 0 | 0 | 0 |
| `links/telegram` | 0 | 0 | 5 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 1 | 0 | 0 | 0 |
| `links/dynamodb` | 0 | 0 | 0 | 0 | 2 | 2 | 2 | 0 | 1 | 0 | 0 | 0 | 0 | 0 |
| `links/wasm` | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 2 | 4 | 1 | 0 | 0 | 0 |
| `links/influxdb` | 0 | 0 | 0 | 0 | 3 | 1 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| `crates/wyrm-ffi` | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 0 | 0 | 2 | 1 | 0 | 0 | 0 |
| `links/slack` | 0 | 0 | 2 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| `crates/wyrm-link-guest` | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 0 |
| **total** | **14** | **43** | **707** | **152** | **774** | **308** | **127** | **49** | **1458** | **345** | **263** | **101** | **17** | **33** |

## Appendix B — reproduce

```sh
# from the repo root; S = a scratch directory
printf 'allow-unwrap-in-tests = true\nallow-expect-in-tests = true\nallow-indexing-slicing-in-tests = true\nallow-panic-in-tests = true\nallow-print-in-tests = true\nallow-dbg-in-tests = true\n' > $S/clippy.toml
CLIPPY_CONF_DIR=$S CARGO_TARGET_DIR=$S/target \
  cargo clippy --workspace --lib --bins --all-features --message-format=json -- \
  -W clippy::unwrap_used -W clippy::expect_used -W clippy::string_slice \
  -W clippy::cast_possible_truncation -W clippy::cast_sign_loss -W clippy::cast_possible_wrap \
  -W clippy::let_underscore_must_use -W clippy::allow_attributes_without_reason \
  -W clippy::too_many_lines -W unsafe_code > $S/clippy.json
# count: de-duplicate compiler-message spans by (code, file, line, column)
```
