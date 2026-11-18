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
   C1–C12, the exceptions A1–A3 and seven costly clippy lints per file against
   `tool/rust_rules_baseline.json`. **A count may only go down. A file that is
   not in the baseline starts at zero.** The check fails on a count above its
   baseline and also on a count below it: after you remove hits, run
   `python3 tool/check_rust_rules.py --lower` and commit the smaller baseline
   with the change, so the fixed hit cannot be spent again by the next one.
   Never raise a number by hand; a re-measure after a wider pattern goes in its
   own commit that says so.

Useful runs:

```sh
python3 tool/check_rust_rules.py --no-clippy   # patterns only, about 2 s
python3 tool/check_rust_rules.py --show C4     # list the hits of one pattern
python3 tool/check_rust_rules.py               # what CI runs (one clippy run in JSON)
```

**Exceptions.** A denied lint is allowed only at the narrowest item, with a
reason that says why the code is right: `#[allow(clippy::expect_used, reason =
"…")]` (rule 3). A pattern hit that is right on purpose carries `// rust-rules:
allow(C4) <why>` on its line or the line above. A reason under 12 characters
does not count (A2), and every exception is itself counted (A1), so none is
invisible; so is every removal whose error is only logged (A3: each call of
`wyrm_core::files::discard`, `discard_dir`, `discard_empty_dir`). Prefer a restructure: an exception is for the place where the code
is provably right as it is.

Test code (`#[test]`, `#[cfg(test)]`) may unwrap, expect, panic and print
(`clippy.toml`). Integration tests, benches and examples are crates of their
own: they say so once at their crate root (also for `unreachable`, which clippy
lints in tests too); test kits (`testkit`, `harness`) at their module, and a
test kit is behind a `cfg(test)` or a feature, never in a release build. The
pattern rules skip `tests/`, `benches/`, `examples/`, `#[cfg(test)]` and
`#[cfg(all(test, …))]` items and the files of `#[cfg(test)] mod x;`.

---

## 1. No `unwrap`, `expect` or `panic!` in product code

**Rule.** Product code returns an error or takes the other branch. It does not
call `unwrap()`, `expect()`, `panic!`, `unreachable!`, `todo!`,
`unimplemented!` or `dbg!`, and it does not write the same panic another way
(`unwrap_or_else(|_| unreachable!())`). Where a value is known to be there,
restructure so the type says it: a `let … else`, a slice pattern, an array from
`get(..)`, a `to_map()` that returns the map instead of a `Value` matched back,
an `Infallible` future. A lookup that "cannot" miss returns its error or logs
(`tracing::error!`), never a silent `continue`. `expect`/`unreachable!` stay
only where the code is provably right and no type can say it, with
`#[allow(…, reason = "…")]` that gives the proof (today: `encode_to_vec` and
the embedded manifest; the last three `unreachable!` went by a restructure on
2026-11-15). An HMAC is made with
`wyrm_core::mac::hmac_sha256` (infallible); an RNG failure is never an
`expect`: the function returns `None`/`Err` and its caller refuses (rule 10).

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

A `Value`, `NodeMeta`, `Attachment` or `PtokClaims` encodes with
`wyrm_core::codec::encode_to_vec` (one documented `expect` for the whole
workspace), never `to_vec(v).expect(…)` and never
`to_vec(v).unwrap_or_default()`, which writes empty bytes (an empty sealed
secret, an empty history row, an HMAC over nothing) where an error was.

**Check.** clippy `unwrap_used`, `expect_used`, `panic`, `unreachable`, `todo`,
`unimplemented`, `dbg_macro`: deny. C8 counts `to_vec(..).unwrap_or_default()`
and `.ok()`.

## 2. `unsafe` only where it is listed, one `// SAFETY:` per operation

**Rule.** `unsafe` is denied in the workspace. It is allowed in these places
only, each with its reason:

| Where | Why |
|---|---|
| `wyrm-ffi` (crate) | the C ABI: raw pointers and `#[no_mangle]` entry points |
| `wyrm-link-guest/src/lib.rs`, the `bindings` module | code generated by `wit-bindgen`: the component model's canonical ABI exports are `unsafe` |
| `wyrm-flow/tests/preview_cost.rs` | a counting `GlobalAlloc` (an `unsafe` trait) |
| `wyrm-ffi/tests/abi.rs` | calls the C ABI as a C program does |

`wyrm-ffi` also denies `unsafe_op_in_unsafe_fn` and
`clippy::undocumented_unsafe_blocks`: every unsafe operation sits in its own
`unsafe {}` block, also inside an `unsafe fn`, with a `// SAFETY:` line that
names the caller contract (the function's `# Safety` section) it relies on and
why it holds, not what the line does. A thread-safety claim is checked by the
compiler: `WyrmHandle` is asserted `Send + Sync` at compile time, because C
calls in from any thread.

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
`unsafe_op_in_unsafe_fn` and clippy `undocumented_unsafe_blocks`: deny. A1
counts each of the allows above.

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

**Check.** clippy `allow_attributes_without_reason`: deny; A2 counts a reason
under 12 characters; A1 counts every `allow`/`expect` and `rust-rules` marker
per file, so a new exception shows in the review as a count that went up.

## 4. Output and exit codes belong to command lines

**Rule.** A library or service logs through `tracing`; it never prints to
stdout. Command lines (`tools/wyr`, `wyrm-agent`, `wyrmd`'s `cli` module and
`wyrmd release`, the `wyrm-*-sim` simulators) allow `print_stdout` once, at
their crate or module root. An exit code goes back to `main` as a
`std::process::ExitCode` (`wyrmd`: `check` → 1, a given-up update trial →
`TRIAL_EXIT`; `wyrm-agent`, `wyrm-mcp`, `wyr` on an error), so the runtime
shuts down and every `Drop` runs first. clippy does not lint `exit` inside
`main`, so this holds there too by review. `std::process::exit` stays only in
`wyr`'s `out!`, where a closed stdout ends the CLI and nothing is open.

**Why.** stdout of a broker or a link process is captured by the supervisor as
its log; a stray `println!` there is a log line without level or span. An
`exit` deep in a library skips every `Drop` (WAL flush, socket close).

**Check.** clippy `print_stdout`, `exit`: deny.

## 5. A wire code is a `wire_enum!`, never `as u8` or a name search

**Rule.** Codes cross the wire only through the code table
(CONTRIBUTING "Wire enums"): `.code()` out, `T::try_from(u8)` in, `T::from_name`
or `str::parse::<T>()` from a spec name. No `as u8|u16|u32` outside the code
tables, no `as <int>` on a number that came from `as_f64`, no
`T::ALL.iter().find(|x| x.name() == s)`. A whole number from a `Value` (an
action argument, a `cfg` or stored field, a code in a reply) is read by the one
decoder `Value::to_int::<T>()` (`wyrm_core::value`): an integer as it is, a float
only when it is whole and at most 2^53 (a JSON client's `20.0`); a fraction,
NaN, an infinity, a negative number for an unsigned `T` or one out of range is
an error, never truncated, saturated or `0`. A float the code made itself
(seconds × 1000, rounded) becomes an integer through `wyrm_core::value::whole`,
never `as`. A code that does not decode is refused or read as the safe value
(`bad`, `internal_error`), never as `0`.

**Why.** **T1**: `Quality::try_from(x as u8)` made a script's `q: 0.9`, `-1` or
`NaN` into `0` = `Good`, and a missing status `code` into `Ok`: quality and
status failed open. The final verification of 2026-11-16 found the same in
`sys/tokens ▸ add {count: 0.5}`: `0.5 as u32` is `0`, and a count of 0 means no
limit; three integer decoders disagreed (one took `1.7` as `1`, one let `2^64`
saturate). **T6**: 14 hand-written name searches, some taking two or
three forms of input.

```rust
// bad — crates/wyrm-flow/src/nodes.rs (before #105)
Some(x) => Quality::try_from(x as u8).unwrap_or(Quality::Bad),
let level = Perm::ALL.iter().copied().find(|p| p.name() == level)

// good — crates/wyrm-flow/src/codes.rs, crates/wyrm-admin/src/control.rs
Value::UInt(u) => u8::try_from(*u).ok(),          // then Quality::try_from(c)
let count: u32 = int_arg(args, "count")?.unwrap_or(1); // Value::to_int: 0.5 is refused
let level = Perm::from_name(level)
```

**Check.** C1 `int-cast`: `as u8/u16/u32/i8/i16/i32`, `as _`, and any
`as <int>` within six lines after a float (`as_f64`, `f64`, `Float(`,
`.round()`…). C2 `name-lookup`: any `.name() == s`, `.name().eq(s)` or
`name(*x) == s` comparison, and a `match` whose string arms give enum variants
(`"read" => Perm::Read`), once per `match`. No function is exempt by its name:
a plain enum's own hand-written lookup counts too, until its names are
declared once by a macro that generates the lookup: `wire_enum!` for a set
with codes, `name_enum!` (`wyrm_core`, names only: `ALL`, `name`,
`from_name`, `FromStr`) for one without. Either takes its one name and no
other form; a second form (another case, a display text) is mapped by the
caller in one place that says why (`Freq`: RFC 5545 names are
case-insensitive, so the text is upper-cased first). Left in C2 (15 after
#127): lookups that build a variant with data (`Answer::Granted
{left}`, `DType::String(n)`), names of other crates' types (`tracing`
levels), comparisons that are not a lookup, and the closed sets of T5 still
open.

## 6. A closed set is an enum, not a `String`

**Rule.** A field, argument or state whose values are a fixed list is an enum
(`wire_enum!` when it has wire codes, `ParamEnum` for an action argument,
otherwise `wyrm_core::name_enum!`, which generates `name()`, `from_name()`,
`NAMES` and the codecs). The string becomes the enum once, where it is
decoded. A `name_enum!` type is kept as its name in CBOR, postcard and JSON,
the bytes a `String` field wrote, so a store needs no migration; a name that
is not in the set is a decode error, never a default. A `wire_enum!` type
kept by its name in a store says so on the field
(`#[cbor(with = "wyrm_core::named::cbor")]`,
`#[serde(with = "wyrm_core::named::serde")]`). No `String` field documented as "`a`, `b` or
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
// bad — crates/wyrm-link-sdk/src/package.rs (a repository entry; still in the
// code, C3 counts it)
/// `Equipment`, `Apps`, `History sync`, `File stores`, …
pub category: String,

// good — crates/wyrm-admin/src/control/backups.rs (#125)
wyrm_core::name_enum! { pub enum JobStatus as "backup job status" { Running => "running", Done => "done", Failed => "failed" } }
pub status: JobStatus,
if job.status != JobStatus::Done { … }
```

**Check.** C3 `string-closed-set`: a text field (`String`, `&str`,
`Box<str>`, `Cow<str>`, in `Option` too, the last field of a struct too) or a
`fn` argument whose doc lists its values (backticked or quoted alternatives,
"one of …", "a, b or c"); and a text field of a struct or of an enum's brace
variant, documented or not, that the crate fills from an enum's `name()` (`mode: def.mode.name().to_owned()`
in a literal of the struct, `x.mode = m.name().into()`, `String::from(m.name())`):
its set is that enum (`LinkInfo.mode` was one, now `Mode`; the gateway's
`AuditEvent::Denied.op`, now `DeniedFor`). C6 `string-set`: inline `["a", "b"]` (with or
without `&`, `vec![…]`; not the key list of `only(&[…])`), `matches!(x, "a" |
"b")`, `x == "a" || x == "b"`, and `const`/`static` tables of `&str` (also of
tuples). The bodies of the `name_enum!` and `wire_enum!` macros (in
`wyrm-core/src/named.rs`, `wire.rs`; the rest of those files is counted) are
exempt from C6: their `NAMES` is the one declaration of a set.

## 7. One typed decoder per `Value` shape

**Rule.** Action arguments, stored records and reply maps are decoded once,
into a struct, by one decoder (`#[derive(Args)]` for an action's arguments,
`#[derive(Params)]` for a driver node, a `FromValue`-style function in a
`decode.rs`). Handlers use the struct. They do not take
`Some(Value::Bool(..))` or `.get("field")` apart by hand, each with its own
default.

An action's arguments are one struct with `#[derive(Args)]`
(`wyrm_core::args`, re-exported by `wyrm-link-sdk` and `wyrm-link-api`): the
struct is what `~meta` declares (`X::action()`) and what the handler gets
(`X::decode(args)?`; the arguments are taken, so a large binary argument moves
into the struct and is never copied). A field `T` is required, `Option<T>`
optional; whole numbers go through `Value::to_int`; a closed set is a
`name_enum!` type with `#[param(choice)]` (by name) or `#[param(enum)]` (by
index); a name that is no field is refused; every refusal names its field. A
name is one field: two fields of one struct with one name do not compile, and
neither does a name that comes again through `flatten` (the derive asserts it
in a `const` over `Args::NAMES`, in every crate, with no list to keep).
`flatten` stands alone: another attribute beside it does not compile.
`#[param(nonempty)]` is the empty text only; a text of white space is empty
only with `trim`. What a refused call leaves in the map is zeroed. The caller
is checked before its arguments are decoded (a stranger is told
`permission_denied`, never that its arguments were wrong), and so is the state
the action is about: what does not exist is `not_found`, and a broker that is
closing is `busy`, whatever the arguments are. What a form shows from the
state of the moment (the choices of a list, the value in force) is set with
`ActionMeta::shown`, which cannot change a type or add a parameter. In
`wyrm-admin` this is the only way (C12): no argument reader, no `ParamMeta`
written out.

**Why.** **T3**: ≈508 `Some(Value::…(` matches and ≈343 `.get("literal")`
reads; the schema is declared twice (`ParamMeta`, which the SDK validates, and
the hand reads, which can disagree with it). For stored maps no check runs
first, so a wrong type silently reads as the default.

```rust
// bad — crates/wyrm-admin/src/control.rs: anything but `false` is "true"
let enabled = !matches!(arg(args, "enabled"), Some(Value::Bool(false)));

// good — crates/wyrm-admin/src/control/actions.rs: one struct is the declaration and the decoder
#[derive(Args)]
struct AddUpstream {
    #[param(display = "Enabled", absent = true)]
    enabled: bool,
    // …
}
let a = AddUpstream::decode(args)?; // `enabled: "no"` is refused, with the field's name
```

**Check.** C4 `value-field-read`: `Some(Value::…`, `if let Value::…(`,
`let Value::…(..) =`, `.get`/`.get_mut`/`.remove`/`.contains_key` with a
literal or a `CONST` key, `m["x"]`, `Value::as_*`, and the argument helpers
(`arg_str(&args, "x")`, `opt_str`, `get_u64`, …). Files named `decode.rs`,
`decode/`, the codec in `wyrm-core/src/value.rs` and the decoder behind
`#[derive(Args)]` (`wyrm-core/src/args.rs`) are exempt.

C12 `admin-arg-read`, in `crates/wyrm-admin/src` (baseline 0; the other crates
follow as they move, audit T3). There `args` names an action's arguments and
nothing else (a process's arguments are `argv`, a call built for another link
is a `request`), and it has three uses: the parameter (`args: Value`), the
one argument of a struct's decoder (`X::decode(args)`, `<()>::decode(args)`),
and a whole hand-over to a dispatcher of the crate (`history::invoke(…, args,
…)`: a lower-case module path, never a bare or a closure `invoke`). The
decoder is that of a struct of the crate that derives `Args` (the script
collects the names) or `<()>`: `Raw::decode(args)`, `Self::decode(args)`, a
type of another crate and a second read (`X::decode(args.clone())`) count.
**Every other `args` counts**: a helper called with it, a method on it, a
macro, a new name for it (`let a = args`, `let args: T = …`), a `match`. Also
counted: a function that takes the arguments (`on_invoke`, `on_check`,
`invoke`, `decode`) with any `Value` in its parameters or generics other than
`args: Value` / `args: &Value` (`&'a Value`, `impl Into<Value>`,
`Option<Value>`, `Arc<Value>`, a full path), or without it; `invoke` and
`decode` as a closure or a method; a `Value` taken apart in a parameter; a
type alias of `Value`; `let a: ActionMeta = Default::default()`; an argument
reader by name
(`arg(…)`, `…_arg(…)`, `from_args(…)`); a parameter or an action written out
(`ParamMeta`, `.param(…)`, `ActionMeta::new()`, `ActionMeta { … }`: an action
is `X::action()`); a change of an action's declared parameters
(`a.params.insert(…)`, `.entry`, `.retain`, `.values_mut()`, `&mut a.params`,
`a.params = …`); a decoder written by hand (`impl Args for`, `fn decode(v:
Value)`). A file named `decode.rs` is no decoder module inside `wyrm-admin`:
C4 counts its reads. C4 also counts, in every crate, a map view of a value
(`.as_map()`) and a key that is a variable or a call (`m.get(k)?.as_str()`).

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

**Check.** C5 `string-error`: a `pub`/`pub(crate)` `fn` or a method of a
`pub trait` whose error is text (`String`, `std::string::String`, `&str`,
`Box<str>`, `Cow<str>`), also through an alias of the same file (`type Out =
Result<_, String>`) or a text error type of the crate (`pub type Error =
String;`); clippy `map_err_ignore` (baselined).

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

// good — crates/wyrm-core/src/history.rs (#108)
pub struct HistoryQuery { pub from: TimeUs, pub to: Option<TimeUs>, pub rollup: Rollup,
                          pub window: Option<Window>, pub limit: Option<NonZeroUsize> }
let mut p = format!("history={}..", iso_us_exact(self.from.0)); // only typed values go in
```

**Check.** C7 `selector-format`: a `format!`/`write!`/`writeln!` string (raw
too) with `?x={…}`, `&x={…}`, `;x={…}`, `?{p}={…}` or `history={…}`, and a
text piece that ends a parameter for a value to follow (`"&x="` in a
`push_str` or a `concat`). It also counts URL queries; review each.

## 10. A security or persistence result is never dropped

**Rule.** The result of an RNG fill, a store `apply`, a `save`, `persist`,
`sync_all`, `flush`, `rename` or `write_all`, a seal (`seal`, `seal_stream`,
`seal_bytes`), a file mode (`set_permissions`, `write_private`,
`private_dir`), a secret store change (`secrets.set/remove/drop_link`), a
removal or a directory made (`remove_file`, `remove_dir_all`, `remove_dir`,
`create_dir_all`, wyrm-admin's `nofollow::remove_any`) or a portable app's
store write (`Host::store_put`) is handled: `?`, a refusal, or a logged error
with the state it leaves. A file that holds state (a key, a certificate, a
role or update marker, a backup, a package, a link's data, a trust list) is
never removed silently. A *scratch* file (a temporary file before or after a
write, a staging or download directory, an upload part) is removed through
`wyrm_core::files::discard` (a file), `discard_dir` (a directory) or
`discard_empty_dir` (a directory only when it is empty): absent is done, any
other failure is logged with the path. They are the only removals whose error
is not returned, never for a file that holds state, and each call is counted
(A3);
`files::gone_ok` turns "not there" into done where the error is returned
(`remove_file(p).or_else(gone_ok)?`). A
failing RNG fails closed: the workspace has one source, `wyrm_core::rand`
(feature `rand`: `fill`, `bytes::<N>`; `ring` adds `secure_random` for the ring
calls that take a `SecureRandom`), whose `NoRandomness` the caller refuses
with; a link refuses the session or the call (the SNMP link opens no session
without a random salt). `clippy.toml` bans the direct calls
(`getrandom::fill`, `fill_uninit`, `u32`, `u64`, `ring::rand::SystemRandom::new`,
`password_hash::SaltString::generate` and the type `rand_core::OsRng`, which
panic without randomness); the three functions of `wyrm_core::rand` are the only
items that allow them, each with its own `allow`. Randomness inside a library
call that returns a `Result` (rustls, `rcgen::KeyPair::generate`) is that
library's, not a second source of ours. A portable link takes randomness from its host
(`Host::random_bytes`); the SCRAM clock nonce of `wyrm-history-sync`, for a host
that answers `not_supported`, calls no random source.

**Why.** **S3**: three RNG-failure policies; `let _ = getrandom::fill(key)`
leaves the device nonce MAC key at zero, and `new_jti` leaves every session's
`jti` at zero. `let _ = store.apply(…)` hides a write failure.

```rust
// bad — crates/wyrm-gateway/src/devices.rs (before): a zero MAC key on failure
let _ = getrandom::fill(key.as_mut());

// good — crates/wyrm-gateway/src/devices.rs: the gateway does not start without it
// (`crate::rng` logs and calls `wyrm_core::rand`, the one source)
pub(crate) fn new() -> Result<Self, crate::rng::NoRandomness> {
    let mut key = Zeroizing::new([0u8; 32]);
    crate::rng::fill(key.as_mut())?;
```

**Check.** C8 `dropped-result`: `let _ =`, `let _x =`, `let _: T =`, `_ =`,
`drop(…)`, `….ok();` (also after `.await`), `if ….is_err() {}`,
`.unwrap_or_default()`, `.unwrap_or(false|true|0|None|())`,
`.unwrap_or_else(|_| …)`, `if let Ok(..) = … { … }` and `if ….is_ok() { … }`
without `else` (bodies nested to any depth), `match … { …, Err(_) => {} }`
(or `=> ()`, `continue`, `break`, `None`, `return`, `return None`, `return
Ok(..)`), `let ok = ….is_ok();`, `.ok().is_some()` and `matches!(…, Ok(_))`
on such a call, and `to_vec(..).unwrap_or_default()` / `.ok()`. The secret
store counts under any receiver (`.drop_link(`, `.unstash(`, `set`/`remove`
on a receiver named for secrets). The calls are a name list in `tool/check_rust_rules.py`
(`PERSIST_CALLS`); a new security or persistence call that returns `Result`
goes there with a sample in `PROBE_CALLS`. Every run first checks that list
against samples (`probe()`): each call in each dropped form is counted, none
in a handled form, or the check fails. clippy `let_underscore_must_use`
(baselined) counts every dropped `Result` whatever its name. The list was
too short until 2026-11-15: C8 read 0 while a backup dropped a failed seal
(audit B1–B4). Measured on a copy of `main` (756075c1) with the rule as it
is now, C8 counts 14: B1–B5, the AI-3 `remove(..).unwrap_or(false)`, the
localfs mode, the guard stamp, the OPC UA first-use marker, and two refused
`apply` calls taken as "nothing to do" (`RemovePeer`, `DropEnrollment`); the
first widening counted 10 of them. All are fixed in PR #125. The final
verification of 2026-11-16 widened it to removals, `create_dir_all` and
`store_put`: 102 drops, among them a peer's key files, a removed link's
directory (its certificate and key are in it), the OPC UA first-use marker and trust list, a backup that
`remove` answered done for, the update state file, the standby's active
marker, the messenger's read position (a lost write ran chat commands again
after a restart) and the uplink's `bdSeq`; `nofollow::remove_any` hid 14 more
inside a helper. Each is handled or, for a scratch file, goes through
`files::discard`; C8 is 0 again. A form's `[^;]*?` no longer runs past the `}`
of a function whose last expression has no `;` (it read the next function's
`.unwrap_or(None)` as a drop).

## 11. One clock and one hex helper

**Rule.** `now_us`/`now_s`/`now_ms`, hex and `sha256_hex` live once, in
`wyrm-core` (the clock behind a trait where tests need it). A crate does not
define its own.

**Why.** **X2**: 33 clock helpers, each with its own `as u64` from `u128`; 12
hex helpers (one named `wyrm_core_hex` in `wyrm-flow`), 4 `sha256_hex`.

**Check.** C9 `duplicate-helper`: a `fn` or a closure (`let now = || …`)
outside `wyrm-core` named `now…`, `…_now`, `unix_…`, `timestamp…`, or holding
`hex`, `sha256` or `digest`.

**URLs.** A configured URL (an HTTP target, a file store, a sync target, an
uplink, the gateway's origins and public URL, a release channel, a
repository) is read by `wyrm_core::weburl` (`Url::parse`, `HttpUrl::parse`)
and the place applies its policy to the typed parts; a place that only tells
a URL from other text, or takes what follows the authority of a URL a server
wrote (a messenger button's target, a WebDAV `href`), uses
`weburl::split_scheme`. No `split_once("://")` or `strip_prefix("https://")`
splitting by hand (review S4: fifteen splitters with different rules). Left
as text on purpose: the secrets redactor (`wyrm-admin/src/secrets.rs`, it
must find `://` in any text, a malformed scheme too, or a secret would show;
the one C11 hit in the baseline) and Zenoh locators (`quic/host:port`, not
URLs).

**Check.** C11 `url-split`: `split_once`/`find`/`contains`/`strip_prefix`/
`starts_with`/`split_terminator`/`match_indices`/`trim_start_matches`/
`replace`/`replacen`/… with `"…://"` or `"http…"`, and `splitn`/`rsplitn`
with a count before it (`splitn(2, "://")`), outside `wyrm-core/src/weburl.rs`.
The checker runs its probes (samples each pattern must count or leave)
before every run.

## 12. A secret parameter is a `Secret`

**Rule.** A `#[param(secret)]` field has the type
`wyrm_link_sdk::support::Secret` (redacted `Debug`, zeroized on drop), not
`String`.

An action argument (`#[derive(Args)]`) takes `Secret` (a text parameter) and
`SecretBytes` (a binary one), and nothing else: `#[param(secret)]` on a
`String` or a `Vec<u8>` does not compile (`wyrm_core::args::SecretArg`), and a
secret is never trimmed (`nonempty` drops only the empty text, so a passphrase
of spaces is a passphrase). **One named exception:** a token a person pastes
as one line (an enrolment token of `upstream ▸ add`) is a `SecretLine`, whose
type cuts the white space around it: a pasted line often ends with a newline,
and a token holds none. `secret` with `trim` compiles only on that type
(`PastedSecretArg`); never use it for a passphrase or a key.

A field of an `Args` struct that is named `token`, `passphrase`, `password`,
`secret` or `key` has a secret type, with or without the attribute. What is
not a secret is called what it is (`key_sha256` with `name = "key"`). The driver derive (`#[derive(Params)]`) does not
take `Secret` yet; until then its count only goes down as links move.

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

**Check.** C10 `plain-secret` (a type alias of the file is followed to its
type): a `#[param(secret)]` field, and a field of an `Args` struct with one
of the five names above.

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
file (test code is not counted). The counts must not depend on the platform:
code that differs per target is written so both count the same (`nofollow`
compares `stat(2)` with `stat(2)` instead of casting a `dev_t` that is `i32` on
macOS and `u64` on Linux: that one cast made macOS count 121 `cast_sign_loss`
and Linux 120). The check fails on a difference in either direction, so a
platform drift shows at once. When a new stable clippy counts differently,
re-measure the baseline in its own commit and say why.

---

## Before you call a Rust change done

1. `cargo fmt --all`
2. `cargo clippy --workspace --all-targets --all-features -- -D warnings`
3. `python3 tool/check_rust_rules.py`; after removing hits, `--lower` and
   commit the baseline with the change.
4. `cargo test --workspace --all-features`
