# Rust code rules

These rules hold for every crate of the Cargo workspace. They come from the
audit of 2026-11-15 (typing, security and structure); its finding IDs (S1, S2,
T1–T7, X1, X2) are cited as the evidence for each rule. Each rule has the rule,
why, a bad/good pair from this code, and its check.

Two checks run in CI job `check`:

1. **Denied lints.** `[workspace.lints]` in the root `Cargo.toml`; every member
   has `lints.workspace = true`. `cargo clippy --workspace --all-targets
   --all-features -- -D warnings` fails on one hit.
2. **Baselined rules.** `python3 tool/check_rust_rules.py` counts the patterns
   C1–C10 and seven costly clippy lints per file against
   `tool/rust_rules_baseline.json`. **A count may only go down. A file that is
   not in the baseline starts at zero.** After you remove hits, run
   `python3 tool/check_rust_rules.py --lower` and commit the smaller baseline.
   Never raise a number by hand.

Useful runs:

```sh
python3 tool/check_rust_rules.py --no-clippy   # patterns only, about 2 s
python3 tool/check_rust_rules.py --show C4     # list the hits of one pattern
python3 tool/check_rust_rules.py               # what CI runs (one clippy run in JSON)
```

**Exceptions.** A denied lint is allowed only at the narrowest item, with a
reason: `#[allow(clippy::expect_used, reason = "…")]` (rule 3). A pattern hit
that is right on purpose carries `// rust-rules: allow(C4) <why>` on its line
or the line above; the reason is required. Prefer a restructure: an exception
is for the place where the restructure reads worse.

Test code (`#[test]`, `#[cfg(test)]`) may unwrap, expect, panic and print
(`clippy.toml`). Integration tests, benches and examples are crates of their
own: they say so once at their crate root; test kits (`testkit`, `harness`) at
their module. The pattern rules skip `tests/`, `benches/`, `examples/` and
`#[cfg(test)]` items.

---

## 1. No `unwrap`, `expect` or `panic!` in product code

**Rule.** Product code returns an error or takes the other branch. It does not
call `unwrap()`, `expect()`, `panic!`, `todo!`, `unimplemented!` or `dbg!`.
Where a value is known to be there, restructure so the type says it: a
`let … else`, a slice pattern, an array from `get(..)`, `if let Some` after a
lookup. `expect` stays only for a true invariant that no restructure states
better (an HMAC key of any length, an encode into memory, build-time data
that a test parses), with `#[allow(clippy::expect_used, reason = "…")]`. An
RNG failure is never an `expect`: the function returns `None`/`Err` and its
caller refuses (rule 10).

**Why.** The audit found the code "much better on panics than feared": 14
guarded `unwrap()` in product code. The rule keeps it that way. A panic
reachable from input is a remote defect: **S1** is one (a char-boundary slice
in `parse_iso` panics the answer task of a gateway user's history query). A
guard "right above" is true today and false after the next edit; the type is
true after both.

```rust
// bad — crates/wyrm-state/src/lib.rs (before): guarded by a length check 12 lines up
let schema = u32::from_le_bytes(data[4..8].try_into().unwrap());

// good — the read itself says what happens when the bytes are not there
fn bytes_at<const N: usize>(b: &[u8], at: usize) -> Option<[u8; N]> {
    b.get(at..at.checked_add(N)?)?.try_into().ok()
}
let schema = u32::from_le_bytes(bytes_at(data, 4).ok_or("bad header")?);
```

```rust
// bad — links/alarm/src/lib.rs (before): get_mut after contains_key
let old = std::mem::replace(&mut self.sinks.get_mut(name).unwrap().def, def);

// good
let Some(s) = self.sinks.get_mut(name) else {
    return Err(not_found(format!("sinks/{name}")));
};
let old = std::mem::replace(&mut s.def, def);
```

An in-memory `Value` encodes with `wyrm_core::codec::value_to_vec` (one
documented `expect` for the whole workspace), not `to_vec(v).expect(…)`.

**Check.** clippy `unwrap_used`, `expect_used`, `panic`, `todo`,
`unimplemented`, `dbg_macro`: deny.

## 2. `unsafe` only in `wyrm-ffi`, one `// SAFETY:` per operation

**Rule.** `unsafe` is denied in the workspace. `wyrm-ffi` (the C ABI) allows it
and denies `unsafe_op_in_unsafe_fn` and `clippy::undocumented_unsafe_blocks`:
every unsafe operation sits in its own `unsafe {}` block, also inside an
`unsafe fn`, with a `// SAFETY:` line that names the caller contract (the
function's `# Safety` section) it relies on. A new test helper that needs
`unsafe` (a counting `GlobalAlloc`) allows it on that item with a reason and
the same SAFETY lines.

**Why.** **S5**: 39 unsafe operations in `unsafe fn` bodies had no SAFETY note;
`wyrm_buf_free(p, len)` is sound only if `len` is the exact length handed
out, and nothing said so at the free. A SAFETY line is where a reviewer checks
the contract against the code.

```rust
// bad — the whole body is an unsafe context; nothing says why it holds
pub unsafe extern "C" fn wyrm_buf_free(p: *mut u8, len: usize) {
    drop(Box::from_raw(std::ptr::slice_from_raw_parts_mut(p, len)));
}

// good — crates/wyrm-ffi/src/lib.rs
// SAFETY: `p`/`len` are, by the caller's contract, exactly the pointer and
// length one `wyrm_next_event` call wrote, freed once. That call made them with
// `Box::into_raw` of a `Box<[u8]>` of `len` bytes, so the rebuilt box has the
// layout it was allocated with. A wrong `len` breaks this; the contract names it.
drop(unsafe { Box::from_raw(std::ptr::slice_from_raw_parts_mut(p, len)) });
```

**Check.** rustc `unsafe_code`: deny (workspace); in `wyrm-ffi`
`unsafe_op_in_unsafe_fn` and clippy `undocumented_unsafe_blocks`: deny.

## 3. Every exception says why

**Rule.** `#[allow(…)]` carries `reason = "…"`. A comment next to it is not
enough: move it into the reason.

**Why.** An exception without a reason cannot be reviewed or removed when the
reason goes away; 17 allows in product code had none.

```rust
// bad — crates/wyrm-client/src/streams.rs (before)
// moved once per event; boxing would cost an allocation each
#[allow(clippy::large_enum_variant)]

// good — crates/wyrm-client/src/streams.rs
#[allow(
    clippy::large_enum_variant,
    reason = "moved once per event; boxing would cost an allocation each"
)]
```

**Check.** clippy `allow_attributes_without_reason`: deny.

## 4. Output and exit codes belong to command lines

**Rule.** A library or service logs through `tracing`; it never prints to
stdout. Command lines (`tools/wyr`, `wyrm-agent`, `wyrmd`'s `cli` module and
`wyrmd release`, the `wyrm-*-sim` simulators) allow `print_stdout` once, at
their crate or module root. `std::process::exit` is called only where the exit
code is the answer (`wyrmd check`, the update trial exit), with that reason.

**Why.** stdout of a broker or a link process is captured by the supervisor as
its log; a stray `println!` there is a log line without level or span. An
`exit` deep in a library skips every `Drop` (WAL flush, socket close).

**Check.** clippy `print_stdout`, `exit`: deny.

## 5. A wire code is a `wire_enum!`, never `as u8` or a name search

**Rule.** Codes cross the wire only through the code table
(CONTRIBUTING "Wire enums"): `.code()` out, `T::try_from(u8)` in, `T::from_name`
or `str::parse::<T>()` from a spec name. No `as u8|u16|u32` outside the code
tables, no `as <int>` on a number that came from `as_f64`, no
`T::ALL.iter().find(|x| x.name() == s)`. A number from a `Value` goes through
`u8::try_from(u64)`, and a code that does not decode is refused or read as
the safe value (`bad`, `internal_error`), never as `0`.

**Why.** **T1**: `Quality::try_from(x as u8)` made a script's `q: 0.9`, `-1` or
`NaN` into `0` = `Good`, and a missing status `code` into `Ok`: quality and
status failed open. **T6**: 14 hand-written name searches, some taking two or
three forms of input.

```rust
// bad — crates/wyrm-flow/src/nodes.rs (before #105)
Some(x) => Quality::try_from(x as u8).unwrap_or(Quality::Bad),
let level = Perm::ALL.iter().copied().find(|p| p.name() == level)

// good — crates/wyrm-flow/src/codes.rs, crates/wyrm-admin/src/control.rs
Value::UInt(u) => u8::try_from(*u).ok(),          // then Quality::try_from(c)
let level = Perm::from_name(level)
```

**Check.** C1 `int-cast`, C2 `name-lookup` (C2 is at zero: keep it there; a
plain enum's own `from_name` over `Self::ALL` is its one definition and is not
counted).

## 6. A closed set is an enum, not a `String`

**Rule.** A field, argument or state whose values are a fixed list is an enum
(`wire_enum!` when it has wire codes, `ParamEnum` for an action argument,
otherwise a plain enum with `name()`/`from_name()`). The string becomes the
enum once, where it is decoded. No `String` field documented as "`a`, `b` or
`c`", no inline `&["a", "b"]` set, no `const NAMES: [&str; N]` checked by
hand. The key list of `Fields::only(&[…])` (the names an argument map may
hold) is not a set of values and is not counted.

**Why.** **T5**: 31 `String` fields documented as closed sets
(`Job.status` compared as `job.status != "done"`, `Device.alg` parsed again at
every login). **T2**: the gateway's WS `op` is a string matched in seven places;
authorization and dispatch are two separate matches that can drift. **T4**:
role grants stored as `(String, u8)` silently drop a grant whose code does not
decode, which in a first-match list widens access.

```rust
// bad — crates/wyrm-admin/src/control/backups.rs
/// `running`, `done` or `failed`.
pub status: String,
if job.status != "done" { … }

// good (the target design, audit T5)
pub enum JobStatus { Running, Done, Failed }
pub status: JobStatus,
if job.status != JobStatus::Done { … }
```

**Check.** C3 `string-closed-set`, C6 `string-set`.

## 7. One typed decoder per `Value` shape

**Rule.** Action arguments, stored records and reply maps are decoded once,
into a struct, by one decoder (`#[derive(Params)]`, a `FromValue`-style
function in a `decode.rs`). Handlers use the struct. They do not take
`Some(Value::Bool(..))` or `.get("field")` apart by hand, each with its own
default.

**Why.** **T3**: ≈508 `Some(Value::…(` matches and ≈343 `.get("literal")`
reads; the schema is declared twice (`ParamMeta`, which the SDK validates, and
the hand reads, which can disagree with it). For stored maps no check runs
first, so a wrong type silently reads as the default.

```rust
// bad — crates/wyrm-admin/src/control.rs: anything but `false` is "true"
let enabled = !matches!(arg(args, "enabled"), Some(Value::Bool(false)));

// good (the target design, audit T3) — one struct is both the declaration and the decoder
#[derive(Params)]
struct EnableArgs { #[param(default = true)] enabled: bool }
let a = EnableArgs::from_value(&args)?;
```

**Check.** C4 `value-field-read` (files named `decode.rs`, `decode/` and the
codec in `wyrm-core/src/value.rs` are exempt).

## 8. A public error is a type, not a `String`

**Rule.** A `pub fn` returns `Result<T, E>` with a typed `E` (one `thiserror`
enum per crate boundary, `From` into `LinkError` where it meets the SDK).
`String` errors stay in private helpers.

**Why.** **T7**: ≈630 `Result<_, String>`; callers and tests can only match
text (`e.contains("changed")`), and `map_err(|_| …)` (263 hits) drops the
cause.

```rust
// bad — crates/wyrm-link-sdk/src/package.rs
pub fn read_manifest(zip: &[u8]) -> Result<Manifest, String>

// good (the target design, audit T7)
#[derive(Debug, thiserror::Error)]
pub enum PackageError { #[error("manifest: {0}")] Manifest(#[from] serde_json::Error), … }
pub fn read_manifest(zip: &[u8]) -> Result<Manifest, PackageError>
```

**Check.** C5 `string-error`; clippy `map_err_ignore` (baselined).

## 9. A selector or query is written from typed values

**Rule.** A Zenoh selector parameter, key or URL query is built from parsed,
typed values (`u64` micro-seconds, an enum, a `NonZeroUsize`), never by
`format!` of text a request carried. Text that must pass is escaped or refused
(`&`, `;`, `=`, control characters).

**Why.** **S2**: `HistoryQuery::params` pasted `from`/`to` into the selector;
`from = "…..&limit=100000&x="` lifted the gateway's 10 000-row cap (GW-2) to
100 000.

```rust
// bad — crates/wyrm-client/src/lib.rs
let mut p = format!("history={}..{}", self.from.trim(), self.to.trim());

// good (the target design, audit S2 fix)
struct HistoryQuery { from_us: u64, to_us: Option<u64>, agg: Option<Rollup>, limit: Option<NonZeroUsize> }
let mut p = format!("history={}..", iso(self.from_us)); // only typed values go in
```

**Check.** C7 `selector-format` (it also counts URL queries; review each).

## 10. A security or persistence result is never dropped

**Rule.** The result of an RNG fill, a store `apply`, a `save`, `persist`,
`sync_all` or `flush` is handled: `?`, a refusal, or a logged error with the
state it leaves. A failing RNG fails closed.

**Why.** **S3**: three RNG-failure policies; `let _ = getrandom::fill(key)`
leaves the device nonce MAC key at zero, and `new_jti` leaves every session's
`jti` at zero. `let _ = store.apply(…)` hides a write failure.

```rust
// bad — crates/wyrm-gateway/src/devices.rs
let _ = getrandom::fill(key.as_mut());

// good
getrandom::fill(key.as_mut()).map_err(|_| Error::NoRandomness)?;
```

**Check.** C8 `dropped-result`; clippy `let_underscore_must_use` (baselined).

## 11. One clock and one hex helper

**Rule.** `now_us`/`now_s`/`now_ms`, hex and `sha256_hex` live once, in
`wyrm-core` (the clock behind a trait where tests need it). A crate does not
define its own.

**Why.** **X2**: 33 clock helpers, each with its own `as u64` from `u128`; 12
hex helpers (one named `wyrm_core_hex` in `wyrm-flow`), 4 `sha256_hex`.

**Check.** C9 `duplicate-helper`.

## 12. A secret parameter is a `Secret`

**Rule.** A `#[param(secret)]` field has the type
`wyrm_link_sdk::support::Secret` (redacted `Debug`, zeroized on drop), not
`String`.

The derive does not take `Secret` as a parameter type yet (audit T3 extends
it); until then the count only goes down as links move.

**Why.** Today secrets stay out of `Debug` by a comment ("No `Debug`: it holds
secrets"); a type makes the convention a rule the compiler keeps.

```rust
// bad — links/opcua/src/lib.rs
#[param(default = "", secret, display = "Password")]
password: String,

// good
#[param(default = "", secret, display = "Password")]
password: Secret,
```

**Check.** C10 `plain-secret`.

## 13. Baselined clippy lints

**Rule.** No new hit of:

| Lint | Why |
|---|---|
| `cast_possible_truncation`, `cast_sign_loss`, `cast_possible_wrap` | **T1**: `as` saturates (300 → 255), truncates (1.9 → 1) and turns NaN into 0 without a word; use `try_from` |
| `string_slice` | **S1**: `&s[a..b]` on text from input panics on a char boundary; slice bytes after `is_ascii()`, or use `get(..)` |
| `let_underscore_must_use` | **S3**: a dropped `Result` hides a failed write |
| `map_err_ignore` | **T7**: `map_err(\|_\| …)` drops the cause |
| `too_many_lines` (150, `clippy.toml`) | **X1**: 101 functions over 100 lines, the largest 600; split along the typed enums of rules 6 and 7 |

**Check.** `tool/check_rust_rules.py` runs `cargo clippy --workspace --lib
--bins --all-features` with these lints as warnings, in JSON, and counts per
file (test code is not counted). The counts depend on the platform and the
clippy version (`cfg(target_os)` code, libc field widths, new lint behaviour),
so the baseline is the measurement of CI's platform: Linux x86_64, newest
stable. When a new stable clippy counts differently, lower or re-measure the
baseline in its own commit and say why.

---

## Before you call a Rust change done

1. `cargo fmt --all`
2. `cargo clippy --workspace --all-targets --all-features -- -D warnings`
3. `python3 tool/check_rust_rules.py`; after removing hits, `--lower`.
4. `cargo test --workspace --all-features`
