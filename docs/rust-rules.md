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
   C1–C11 and C13, the exceptions A1–A5 and seven costly clippy lints per file against
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
`wyrm_core::files::discard`, `discard_dir`, `discard_empty_dir`), every text
field that rule 6's pattern counts and that is open on purpose (A4: the list
`C3_OPEN` in the checker, one reason per entry) and every call of a library
that draws randomness by itself (A5, rule 10). Prefer a restructure: an
exception is for the place where the code is provably right as it is.

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
// bad — crates/wyrm-admin/src/audit.rs (before): any text is an audit op
/// `install|start|stop|remove|hello|approve|reject|quarantine|acl_denied`.
pub op: String,
ctl.record(sub, "peer_remvoe", key, Status::Ok, "");   // compiles

// good — crates/wyrm-admin/src/audit.rs: a record is made only from an `AuditOp`
wyrm_core::name_enum! { pub enum AuditOp as "audit op" { Install => "install", … } }
pub fn record(&self, sub: &str, op: AuditOp, key: &str, status: Status, detail: &str)

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
`AuditEvent::Denied.op`, now `DeniedFor`). A list counts when it lists values: backticked or quoted
alternatives, `one of` or `either` with values after them (the words alone are
prose: "one of this site's sections", "in either case"), and, for an argument,
a list in the sentence that names the argument.

C3 reads doc comments, so it still counts a text field whose doc gives
*examples* of an open value (`w1`, `w2`, …). Such a hit is not fixed by
rewording the doc and not hidden by a marker: the checker's list `C3_OPEN`
names it as `(file, "Struct.field" | "fn name")` with the reason its values
are open (an id, a key, a URL, a label, a name another crate or another
repository chooses). An entry takes exactly one hit: a second field of the
same name in another struct of the file, or a second function of the name,
stays in C3. Each entry is counted as A4 `open-text` (21), an entry that no
longer matches a C3 hit fails the check, and a field whose values are a fixed
list never goes there: it becomes a `name_enum!`. One C3 hit is left: the flow
catalog's `Param.editor` (spec 02 `editor`), which takes the type
`ParamMeta.editor` gets.

**Decided: a repository entry's `category` is open text**
(`wyrm-link-sdk/src/package.rs`, `RepoEntry.category`; this rule named it as
the "bad" example until 2026-11-17). The official manifest uses six
categories, but the field is read from the index of *any* repository
(`packages.repository`, ADR 0021; ADR 0043 gives a package row the category of
its own index entry, never the manifest's). Another repository may name
categories of its own, the broker shows the text in `attr.catalog` and
branches on nothing, and an enum with `OrUnknown` would add a set the broker
never uses. So it is an entry of `C3_OPEN`, with this reason, not an enum.

**Unknown names.** `wyrm_core::named::OrUnknown<T>` is for a record this build
did not write and must still read: a store or journal that outlives the build
(`AuditRecord.op`: the WAL holds every earlier version's records, a standby
follows a newer active, a rollback reads what the newer version wrote), an
entry of a file many versions read (a repository index), the word of another
process (a link's own audit event). The type alias says why at its
declaration. It is never used for an argument, a config field or a state this
build makes itself: there an unknown name is refused. C6 `string-set`: inline `["a", "b"]` (with or
without `&`, `vec![…]`; not the key list of `only(&[…])`), `matches!(x, "a" |
"b")`, `x == "a" || x == "b"`, and `const`/`static` tables of `&str` (also of
tuples). The bodies of the `name_enum!` and `wire_enum!` macros (in
`wyrm-core/src/named.rs`, `wire.rs`; the rest of those files is counted) are
exempt from C6: their `NAMES` is the one declaration of a set.

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

**Check.** C4 `value-field-read`: `Some(Value::…`, `if let Value::…(`,
`let Value::…(..) =`, `.get`/`.get_mut`/`.remove`/`.contains_key` with a
literal or a `CONST` key, `m["x"]`, `Value::as_*`, and the argument helpers
(`arg_str(&args, "x")`, `opt_str`, `get_u64`, …). Files named `decode.rs`,
`decode/` and the codec in `wyrm-core/src/value.rs` are exempt.

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
items that allow them, each with its own `allow`. The standard library's hash
seed is OS randomness too: the type `std::hash::RandomState` is banned
(`disallowed-types`; `RandomState::new` also as a method). Five things were
made of it, three of them through `Default::default()`, which a ban of `new`
does not see: the historian's store id, the portable runtime's restart jitter,
the file store's upload id, localfs's temporary file name and the SDK's read
shard seed. All read `wyrm_core::rand` now. A plain `HashMap`'s own seed is not
named in code and is not a source of ours.

**The broker's certificate keys.** rcgen's own `KeyPair` opens a
`ring::rand::SystemRandom` to make a key, to read one and for every signature.
rcgen signs with any `SigningKey`, so the CA key, every leaf key and the
broker keys are a `wyrm_admin::eckey::EcKey`: ring makes the P-256 key pair
(`EcdsaKeyPair::generate_pkcs8`) and each signature (`sign`) with
`wyrm_core::rand::secure_random()`. The algorithm
(`PKCS_ECDSA_P256_SHA256`) and the key file (PKCS#8 in a `PRIVATE KEY` PEM
block) are the ones rcgen wrote: a key written before reads as before, and
rcgen reads a key written now (tests in both directions).

**Libraries that draw randomness themselves.** One call takes no random source
and cannot be routed. It is the named exception, and A5 `library-rng` counts
it (1):

| Library call | What it draws | Call site |
|---|---|---|
| `opcua::crypto::X509::cert_and_pkey` | the RSA key of the OPC UA application certificate | `links/opcua/src/pki.rs`: `generated` |

It fails closed (a `Result` the caller refuses with). A5 also counts, at zero,
what would be a second source of ours: any use of rcgen's `KeyPair` (a path, an
import, a constructor), `generate_simple_self_signed`, any mention of
`RandomState`, `SigningKey::generate`/`random`, `SecretKey::random`,
`RsaPrivateKey::new`, `Uuid::new_v4`, `thread_rng`, `rand::random`,
`rand::rng`, `fastrand`. Protocol libraries draw randomness with no call of
ours that could be counted: rustls and quinn (handshakes), Zenoh (its ids),
tungstenite (frame masks), async-opcua (session nonces). They are libraries'
internals behind a `Result`, not sources of ours. A value that must not be
guessed is never made of the clock: a `ptok` `jti` and an MQTT client id are
`wyrm_core::rand` bytes. A portable link takes randomness from its host
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

**Rule.** These helpers live once, in `wyrm-core`, and a crate does not write
its own:

| Helper | Where |
|---|---|
| the wall clock: `now_us`, `now_ms`, `now_s`, `since_epoch`, `unix(SystemTime)` | `wyrm_core::clock` |
| hex: `encode`, `encode_upper`, `encode_sep`, `decode`, `decode_array::<N>`, `decode_byte`, `is_hex`, `is_lower_hex` | `wyrm_core::hex` (over the `hex` crate, which a crate may also call) |
| SHA-256: `sha256`, `sha256_hex`, `sha256_parts` (a label and a key), `Sha256Stream` (bytes hashed as they are copied), `sha256_reader` (a file) | `wyrm_core::hex` |
| percent-encoding: `percent_encode`, `percent_encode_keep` | `wyrm_core::weburl` |
| a read that fills its buffer: `read_full` | `wyrm_core::files` |

A portable link reads the clock of its host (`Host::now_us`): that trait is the
clock behind a trait, and its implementations are not copies. A crate that
exported a helper under its own name re-exports the one, among its imports at
the top of the file and under the helper's own name (`pub use
wyrm_core::clock::now_us;`); no alias gives the one helper another name.

**Why.** **X2**: 33 clock helpers, each with its own `as u64` from `u128`; 12
hex helpers (one named `wyrm_core_hex` in `wyrm-flow`), with three rules for
case and length; 4 `sha256_hex`; 7 percent-encoders; 2 `read_full`.

**Check.** C9 `duplicate-helper` goes by the name: a free `fn` or a closure
(`let now = || …`) outside `wyrm-core` named `now`, `now_us`/`_ms`/`_s`/…,
`unix_…`, `timestamp…`, or holding `hex`, `sha256` or `digest`. A method is not
counted (an implementation of `Host::now_us`, an artifact's `sha256()`), nor a
name with `now` in another sense (`first_tick_now`, `backup_now`). Seven are
left, none a copy: `release::sha256_file` and `parts::file_sha256` (a file's
digest by `sha256_reader`, with their crate's error type), the flow block
`hash`'s `digest` (MD5, SHA-1 or SHA-256 by name), `hex4` (the four digits of
a JSON `\uXXXX`), two closures that read or write a hex *number* (`0x{:04X}`
of a TSAP, a hex text as an integer) and `hex_text` (a SQL literal over
`encode_upper`).

C13 `helper-body` goes by what a helper does, whatever its name: a read of the
system clock (`SystemTime::now()`, `UNIX_EPOCH`) outside `wyrm_core::clock`; a
two-digit hex format (`{b:02x}`, `%{b:02X}`), two hex digits read by hand
(`to_digit(16)`, `u8::from_str_radix(.., 16)`) and a SHA-256 made by hand
(`Sha256::new()`, `Sha256::digest(..)`) outside `wyrm_core::hex` (and
`wyrm_core::mac`, which brings a long HMAC key to one block). It is 0. Not
counted: a digest generic over its hash (`localize::<D>` of SNMP USM, RFC
3414) and `Hmac<Sha256>`, which are not this helper.

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

**Check.** C10 `plain-secret` (a type alias of the file is followed to its
type).

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
