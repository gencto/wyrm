# Links: install, run and package them

A **link** connects devices or services to the WYRM tree. It serves the
subtree `wy/<site>/downstream/<link>/**`: nodes, values, `set` and actions. This
page tells you how to install a link while the broker runs, what the broker
does with it, what goes in a package, and what the limits are.

Decisions behind this page: ADR 0004 (driver framework), ADR 0006 (ACL and
quarantine), ADR 0010 (WASM host), ADR 0011 (installing links at runtime),
ADR 0012 (network for WASM links), ADR 0013 (links as requesters), ADR 0021
(packaging with `wyr`), ADR 0023 (portable links).

## 1. How a link runs

| Mode | Where the code runs | Where the code comes from | Isolation | Typical use |
|---|---|---|---|---|
| `embedded` | in the broker process | a driver built into `wyrmd` | none: same process | the built-in drivers |
| `process` | a child process the broker starts and watches | a built-in driver (`wyrmd link <driver>`) or a **process package** | own process, mTLS identity, ACL on its own branch, rlimits, cleared environment | your own driver in Rust |
| WASM | in the broker process, in a sandbox | a **WASM package** or one component (`.wasm`) | WebAssembly sandbox: no files, no WASI, only the imports of its world (an app also gets the host's clock, timers and its store), only the TCP addresses you list, fuel, memory and time limits | small protocol drivers, computed points, portable links (section 9) |
| `external` | on another machine | anything that speaks the link protocol with a certificate from the broker's CA | mTLS identity, ACL on its own branch | gateways and devices in the field |

New code that arrives while the broker runs never loads into the broker as
native code: Rust has no stable plugin ABI, and a crash would take the broker
down. In the broker's own process it runs only as WASM.

## 2. What WYRM ships

- **Built-in drivers** (in `wyrmd`): `mock`, `mockdev` (the mock on the driver
  framework), `modbus`, `mqtt`, `agent`, `wasm`, `app` (a portable link on a
  WASM component, section 9) and `portable-echo` (the example portable link,
  native). Install them with *from Driver*.
- **`snmp`** (built in, from Driver): SNMP v2c/v3 poller; guide [snmp.md](snmp.md).
- **`s7`** (built in): Siemens S7-300/400/1200/1500 PLCs over S7comm (ISO-on-TCP); guide: [`docs/s7.md`](s7.md).
- **Link SDK** (`crates/wyrm-link-sdk`): the raw link layer, the driver
  framework (Connection → Device → Point with `Add`/`Edit`/`Remove` actions)
  and `process::run` for a link that runs as its own binary.
- **WASM host and WIT** (`crates/wyrm-wasm-host/wit/link/point.wit`): the
  component worlds `wyrm:link/point` and `wyrm:link/driver`.
- **Example links** (`examples/links`): a responder (the `mockdev` driver
  as its own binary), a requester (records another link's values to CSV)
  and a link that is both (serves statistics of another link and writes its
  points), and a portable link (`examples/links/portable`, section 9) in its
  three modes. `examples/packages/build.sh` packages them with `wyr link pack`
  and makes a repository with `wyr repo add` (ADR 0021).
- **Scheduler** (`links/scheduler`, ADR 0022): schedules of events that write
  values to points at times. Every broker runs one at
  `wy/<site>/downstream/scheduler`; it is also a portable link in the
  packages `scheduler` (WASM) and `scheduler-process`. Guide:
  [`docs/scheduler.md`](scheduler.md).
- **Modbus** (`links/modbus`, built-in driver `modbus`, package `modbus`):
  a master of Modbus TCP, RTU over TCP and serial RTU devices, and a slave
  that serves the tree's values to masters (ADR 0024); `import_dsa` takes
  a `dslink-java-modbus` tree. Its `Scaling` multiplies where DSA's
  divides: read the guide first,
  [`docs/modbus.md`](modbus.md).
- **HTTP** (`links/http`, driver `http`): JSON REST APIs polled on the
  driver framework. Guide: [`docs/http.md`](http.md).

## 3. The Install Link menu

Open `sys/links` and its menu **Install Link ▸**. Every item needs `config`
on `wy/<site>/sys/**` (the `admin` role of the gateway). Every item except
*from Driver* answers with two rows, as in DSA: **success** (true or false)
and **message** (what happened, or why it failed).

| Item | Fields | What it does |
|---|---|---|
| from Driver | Link ID, Driver, Mode, Params | A built-in driver as `embedded`, `process` or `external`. |
| from Zip | Name, Zip (a file you choose) | Installs the package in the zip and runs it as link *Name*. |
| from Url | Name, Url | Downloads a package zip, then as *from Zip*. |
| from Git | Name, Url, Ref | Clones a repository that holds a **built** package, then as *from Zip*. |
| from Repository | Name, Package | Takes a package from the index in `packages.repository`, checks its SHA-256, then as *from Zip*. |
| from WASM | Name, Component (a `.wasm` file) | Wraps one component as a WASM package named *Name* and runs it. |

A downstream broker is not installed here: as in DSA, it adds this broker
itself and comes in through a token, `allow_all_links` or quarantine
(README, Two brokers; ADR 0015).

*Name* is the new link's id: `wy/<site>/downstream/<Name>`. It is a key segment
(letters, digits, `.`, `_`, `-`; not starting with `.`), and must not be the
name of an existing link, a removed remote link, a downstream site or an
operator certificate.

## 4. What happens when you install a package

1. **Fetch.** *from Url* and *from Repository* download over HTTPS (plain
   HTTP only to a loopback address), at most 3 redirects, 64 MiB, 90 s.
   *from Git* runs `git clone --depth 1` over HTTPS. *from Zip* and *from
   WASM* take the file you chose.
2. **Unpack and check**, in a temporary directory under
   `<data_dir>/packages/`:
   - at most 64 MiB zipped, 256 MiB unpacked, 1000 files;
   - relative paths only, no `..`, no symlinks, regular files only;
   - `wyrm-link.json` at the zip root, valid (section 6);
   - `wyrm_link` equal to the broker's link protocol version;
   - the entry for this host present (`process`), or the `.wasm` entry
     present (`wasm`);
   - `wasm`: the component's world, read from its exports (`app`, `driver`
     or `point`), matches `world` if the manifest has one; `capabilities`
     only for an `app`, within their bounds (section 9).
3. **Move into place** with one rename:
   `<data_dir>/packages/<name>/<version>/`. A failed install leaves nothing.
4. **Record.** The registry (`<data_dir>/state`, a write-ahead log) stores
   the package: name, version, kind, entry, SHA-256 of the zip, source. The
   audit journal gets `package_install` with the SHA-256 and the source.
5. **Start the link** with driver `pkg:<package>`:
   - `process` package: a process link. The broker issues a certificate with
     CN = the link id and a link token, rebuilds the router ACL (the router
     restarts for about a second, and open app connections reconnect), and
     starts the package entry.
   - `wasm` package: the broker copies the component to
     `<data_dir>/packages/.wasm/<package>.wasm` and starts an embedded link:
     a `driver` or `point` component on the `wasm` driver with one
     connection `main`; an `app` component on the driver `app` with its
     capabilities as params (section 9).
6. **Answer** `success: true` and a message such as
   `package example-link 1.0.0 installed; link ex1 installed` (an app adds
   `; capabilities net none, store 1 MiB, memory 64 MiB, call 2000 ms`).

A link from a package starts with an empty tree if its driver is a
framework driver: add connections, devices and points with its *Add* actions.
The framework keeps that tree in the link's data directory. A connection runs
one driver action (a scan, a register read) at a time: while it is queued or
runs, another action on that connection answers `busy` at once. A set on that
connection answers `busy` during an action at level `write` or `config` (a
scan) and waits for one at level `read`. Send a `busy` call again after the
action. Sets on the link's other connections are not delayed, except while
a set waits behind a `read` action: that wait holds the link for up to 5 s,
and a set whose `read` action outlasts 5 s answers `timeout` and is not
written.

## 5. Upgrade, reinstall, remove

| You do | Result |
|---|---|
| Install the same package (same version, same bytes) under another *Name* | A second link of the same package. The files are reused. |
| Install the same version with other bytes | Refused: `… is installed with other content`. Raise the version. |
| Install a new version (any *Name* that runs the package, or a new one) | The new version replaces the old one. Every link of the package restarts on it; a running link of an app component gets the new code in place instead (hot start, section 9). The old files are deleted. Links keep their devices and points. A link that does not start is named in the result (`not restarted: <id> (<error>)`); the others run the new version. |
| `sys/links/<id>` ▸ Remove | The link stops and goes away. A process or external link's id is **retired**: its certificate stays valid until it expires, so the id cannot be used again (ADR 0006). |
| `sys/packages/<name>` ▸ Remove | Refused while a link runs the package. Otherwise the package files and its WASM component are deleted. |

`sys/packages/<name>` shows the version, kind, source and SHA-256 of each
installed package.

## 6. Package format

A package is a zip with `wyrm-link.json` at its root.

```json
{
  "name": "example-link",
  "version": "1.0.0",
  "description": "Example process link: the mockdev driver as its own binary",
  "wyrm_link": 1,
  "kind": "process",
  "entries": {
    "macos-aarch64": "bin/macos-aarch64/wyrm-example-link",
    "linux-x86_64": "bin/linux-x86_64/wyrm-example-link",
    "linux-aarch64": "bin/linux-aarch64/wyrm-example-link"
  },
  "args": []
}
```

```json
{
  "name": "register",
  "version": "1.0.0",
  "wyrm_link": 1,
  "kind": "wasm",
  "entry": "register.wasm"
}
```

| Field | Required | Meaning |
|---|---|---|
| `name` | yes | Package name: a key segment (as a link id). |
| `version` | yes | 1–32 of `A–Z a–z 0–9 . _ - +`, not starting with `.`. |
| `description` | no | Shown under `sys/packages/<name>`. |
| `wyrm_link` | yes | The link protocol version the package was built for (`LINK_PROTOCOL` in `wyrm-link-sdk`; now `1`). Another value is refused. |
| `kind` | yes | `process` or `wasm`. |
| `entries` | `process` | Executable per host, as `<os>-<arch>`: `linux-x86_64`, `linux-aarch64`, `macos-aarch64`, `macos-x86_64`. One zip can carry several hosts. |
| `args` | no | Arguments for the executable. |
| `requester` | no | Grants the package asks for: `[{"path": "wy/{site}/downstream/mock", "level": "read"}]` (section 10). Name a link or flow: a whole `wy/{site}/downstream` or `wy/{site}/dataflows` is refused. |
| `entry` | `wasm` | The component file. |
| `world` | no | `wasm`: `app`, `driver` or `point`. Informational: the broker reads the world from the component's exports and refuses a package whose `world` says otherwise. |
| `capabilities` | no | A portable app (`wasm` app component or `process`): `{"net": ["10.0.5.0/24:502"], "store_mb": 4, "memory_mb": 64, "call_ms": 2000}` (section 9). |

Unknown fields are refused, so a typo does not pass silently.

## 7. Build a process package

A process package is a binary built on `wyrm-link-sdk` (feature
`process`). Its whole `main` is one call: `process::main` sets up the logs
(`RUST_LOG`), applies the supervisor's limits before the runtime, and runs
`process::run`. See `examples/links/responder` or `links/modbus`:

```rust
fn main() -> std::process::ExitCode {
    wyrm_link_sdk::process::main::<Framework<MyDriver>>()
}
```

The links in `links/` ship this way too: `modbus`, `mqtt` and `mockdev`
(`links/mock`) build their package binaries with the feature `process`.

The broker starts it with a cleared environment (only `RUST_LOG`,
`RUST_BACKTRACE`, `TZ`, `LANG`, `LC_ALL`, `PATH` are kept) plus:

| Variable | Value |
|---|---|
| `WYRM_SITE`, `WYRM_LINK_ID` | Site and link id. |
| `WYRM_ENDPOINT` | The broker's `tls/` listener on loopback. |
| `WYRM_CA`, `WYRM_CERT`, `WYRM_KEY` | mTLS files: broker CA, the link's certificate (CN = link id) and key. |
| `WYRM_TOKEN_FILE` | The link token for `hello`. |
| `WYRM_DATA_DIR` | The link's private directory (`<data_dir>/links/<id>/data`, mode 0700). |
| `WYRM_PARENT_PID` | The broker; the link exits when it is gone. |
| `WYRM_LIMIT_MEMORY_MB`, `WYRM_LIMIT_OPEN_FILES` | Limits the binary applies to itself (`link_limits` in `wyrmd.json5`). |

`process::run` connects, says `hello` (and gets its params, secrets and
trusted keys), then serves the tree. The supervisor restarts a crashed link
with backoff, at most `max_restarts` times (10 by default).

Process mode needs a `tls/` listener in `wyrmd.json5`.

### Pack it with `wyr link pack` (ADR 0021)

Describe the package in the crate's `Cargo.toml`; `wyrm-link.json` is
generated from it and from the crate's version and description:

```toml
[package.metadata.wyrm-link]
name = "recorder"                 # default: the crate name
description = "Records …"         # default: the crate's description
features = ["bin"]                # Cargo features to build with
bin = "wyrm-example-recorder"     # default: the crate's only binary
args = []
requester = [{ path = "wy/{site}/downstream/mock", level = "read" }]
```

```sh
wyr link pack --manifest-path links/acme/Cargo.toml                  # this host
wyr link pack --manifest-path links/acme/Cargo.toml \
  --target x86_64-unknown-linux-musl --target aarch64-unknown-linux-musl
wyr link pack --component register.wasm --name register --version 1.0.0
```

Each build is one zip, `<name>-<version>-<host>.zip`, in
`<target dir>/wyrm-link` (or `--out`); the same input gives the same bytes.
Unknown fields in the section are refused. `--no-build` packs the binaries
built before; `--name` packs the crate under another package name. The
format lives in `wyrm-link-sdk` (feature `package`): the broker checks a
package with the same code that `wyr` writes it with.

## 8. WASM links

A WASM link is the framework driver `wasm` running a component of the WIT
world `wyrm:link/driver` (`crates/wyrm-wasm-host/wit/link/point.wit`):

```wit
interface tcp {
  connect: func(addr: string, port: u16, timeout-ms: u32) -> result<u32, string>;
  send: func(conn: u32, data: list<u8>) -> result<_, string>;
  recv: func(conn: u32, max: u32, timeout-ms: u32) -> result<list<u8>, string>;
  close: func(conn: u32);
}

world driver {
  import tcp;
  export init: func(config: list<u8>) -> result<_, string>;
  export read: func(point: list<u8>) -> result<list<u8>, string>;
  export write: func(point: list<u8>, value: list<u8>) -> result<_, string>;
}
```

A component of the world `wyrm:link/point` (the same exports, no import)
runs too. Any other import is refused when the component loads.

**Parameters** (edit them with the connection's, device's and point's
*Edit* and *Add* actions):

| Level | Parameter | Meaning |
|---|---|---|
| Connection | Package (`component`) | The WASM package that runs (set by the install). |
| Connection | Network (`net`) | Where the component may connect, see below. Empty: no network. |
| Connection | Config (`config`) | JSON, given to `init` as CBOR. |
| Connection | Call ms (`call_ms`) | Time of one call, network included: 2000 by default, 10–10000. |
| Device | Note | Devices only group points (no ping). |
| Point | Type (`value`) | `number` (default), `bool`, `text` or `any`: the value type the app shows and sends on `set`. |
| Point | Point config (`cfg`) | JSON, given to `read` and `write` as CBOR. |
| Point | Poll s, Writable, Unit | How often the point is read; whether `set` is allowed; its unit. |

`read` answers with the `~val` payload `{0: v, 1: q, 2: t}` or a bare CBOR
value. A `write` is not shown at once: the next read shows the result.

**The network list.** Entries `<ip>/<prefix>:<port>` or `<ip>:<port>`,
separated by commas or spaces: `10.0.5.0/24:502, 192.168.1.20:1502,
[fd00::]/64:502`.

- IP literals only, in the list and in `connect`. No host names.
- `connect` passes when the address is inside an entry and the port is that
  entry's port.
- Loopback, link-local (also `169.254.169.254`), multicast, broadcast,
  `0.0.0.0/8`, cloud metadata and IPv6 addresses that carry an IPv4 address
  (NAT64, 6to4, IPv4-compatible) pass only an entry of their own class:
  `0.0.0.0/0` does not reach the broker itself. Private ranges (`10/8`,
  `172.16/12`, `192.168/16`, `fd00::/8`) are ordinary.
- Only users with `config` can change the list.

**Limits per call:** the call time (`call_ms`, also caps every network wait),
100 M fuel, 16 MiB memory, at most 4 open connections, 64 KiB per `send` and
per `recv`. Past a limit the call fails, the instance is dropped with its
connections, and the next call starts a new one.

**Not available to a component:** TLS, DNS, UDP, serial ports, files,
clocks, random numbers, other processes. The component implements its
protocol itself (for example Modbus TCP framing).

**Building a component.** Any toolchain that produces a component for the
world above works (for example Rust with `wit-bindgen` and `wasm-tools
component new`). The example components in `examples/packages` are written
by hand in the component text format. For a new link, a portable link
(section 9) is simpler: `wyr new link --app` scaffolds it and `wyr link
pack` builds its component.

## 9. Portable links

A **portable link** (ADR 0023) is one Rust source, an `App` from
`wyrm-link-api`, that runs in three modes with the same behaviour:

| Mode | How | Built with |
|---|---|---|
| Embedded | `wyrm_link_portable::Portable<App>`, compiled into a broker | the crate as a dependency |
| Process | `wyrm_link_sdk::process::main::<Portable<App>>()`, supervised | `--features process` |
| WASM | a component of the world `wyrm:app` on the driver `app` | `--features wasm`, `wasm32-unknown-unknown` |

The app declares its nodes and actions in `start`, answers `on_set` and
`on_invoke`, and keeps its state in the host: the tree and a sealed store
in the link's data directory. The host restarts a crashed instance with
backoff; the store stays. `wyrm-link-guest` (`export!`) makes the WASM
glue; `crates/wyrm-wasm-host/wit/app/app.wit` is the world.

**The reference link** is `examples/links/portable` (`wyrm-example-portable`,
app `Echo`). `wyrmd` runs it embedded as the driver `portable-echo`;
`examples/packages/build.sh` packs it twice from the same crate:

```sh
wyr link pack --manifest-path examples/links/portable/Cargo.toml            # portable-echo-1.0.0.zip (wasm)
wyr link pack --manifest-path examples/links/portable/Cargo.toml \
  --kind process --name portable-echo-process                                # portable-echo-process-1.0.0-<os>-<arch>.zip
```

`--name` gives the process form its own package name: a broker keeps one
package per name. The e2e test `one_app_three_modes` runs one scenario on
the three modes and compares the results.

**Cost of the modes** (`cargo bench -p wyrm-link-portable --bench roundtrip`,
Apple M4 Max, release): one event round trip through the engine is about
0.1 µs native and 1.4 µs WASM; a WASM instance starts again after a trap in
20–30 µs (median; the backoff of 1 s, ×2, comes on top); one instance of the
example has 1.1 MiB of linear memory, about 70 KiB of it resident.

**Start a crate:**

```sh
wyr new link acme --app        # links/acme: lib (the App), src/bin, tests
cargo test -p wyrm-link-acme   # the app on the native adapter
```

The crate has `crate-type = ["cdylib", "rlib"]`, the features `process`
and `wasm`, and this section in its `Cargo.toml`:

```toml
[package.metadata.wyrm-link]
name = "acme"
kind = "wasm"                      # `wyr link pack --kind process` overrides
features = ["process"]             # features of a process build
capabilities = { net = ["10.0.5.0/24:502"], store_mb = 4, memory_mb = 64, call_ms = 2000 }
requester = [{ path = "wy/{site}/downstream/mock", level = "read" }]
```

**Pack it:**

```sh
wyr link pack --manifest-path links/acme/Cargo.toml    # acme-<version>.zip
```

For `kind = "wasm"`, `wyr link pack`:
1. runs `cargo build --release --lib --target wasm32-unknown-unknown
   --features wasm` (`strip = true` is fine: it keeps the component type,
   a custom section of the module);
2. makes the module a component in-process (`wit-component`) and checks
   that its world is `app`;
3. writes one zip for every host, `<name>-<version>.zip`, with
   `world: "app"` and the `capabilities` in `wyrm-link.json`.

Add the target first: `rustup target add wasm32-unknown-unknown`.

**Capabilities**, granted at install (*Install Link ▸ from Zip*, *Url*,
*Git* or *Repository*). The install result lists them, for example
`capabilities net none, store 1 MiB, memory 64 MiB, call 2000 ms`. They
become the link's params:

| Capability | Default | Bounds | Meaning |
|---|---|---|---|
| `net` | none | entries as in section 8 | Where the app may connect (`tcp_connect`). |
| `store_mb` | 1 | 0–64 | Size of the store; 0 refuses every write. |
| `memory_mb` | 64 | 1–512 | Linear memory of one instance (all its memories together). |
| `call_ms` | 2000 | 1–10000 | Time of one call (also caps network waits). |

The install result and the `package_install` audit record list the
capabilities and the `requester` grants. A `process` package of the same
app may carry the same `capabilities` (`wyr link pack --kind process`
keeps them): they become its params too, without `component`.

`requester` grants (section 10) apply as for a process package. Later
changes go the usual ways: grants with Grant Access, the others with the
link's `update` (params) or `rollback`. The broker checks the new params
with the driver the link runs on (`app` for an app component); it does not
check a process package's params: its binary parses them when it starts.

An upgrade (a new version of the package) keeps the params of the links on
it. A running app link gets the new code in place (**hot start**): the
link is not stopped and its tree stays, the old instance's `stop` runs (at
most 2 s), requests in flight get `busy`, and the new code starts at once
on the same store (audit op `hot_start`). *Install Link ▸ from WASM* with
an app component installs it with the default capabilities.

**Bounds of the store:** each entry counts its key and value rounded up to
4 KiB, and at least 4 KiB (a 1 MiB store holds at most 256 entries); at
most 10 000 keys; a key is 1 to 256 bytes. Over a bound, `store_put` fails
with `resource_exhausted`. A write that does not grow the store passes even
over a smaller `store_mb`.

**Call time:** a `set` or `invoke` of a portable link may take `call_ms`;
the broker waits at least `call_ms` + 1 s (and at least 5 s) before it
answers `timeout`. A request that was answered `timeout` while it waited in
the queue is not run, and one that waited in the link's queue so long that
`call_ms` more would pass that bound gets `timeout` at once instead of
running. A
caller's own timeout must be longer than the app's `call_ms` + 1 s: the
`wyrm-client` waits 10 s by default (`DEFAULT_TIMEOUT`), so with `call_ms` above 9000 give the
caller a longer timeout, or it sees `timeout` for a call that still runs.

The broker tells the world from the component's exports: an `app`
component runs on the driver `app`; a `driver` or `point` component on the
framework `wasm` driver (section 8). A manifest whose `world` is not the
component's, and capabilities on a driver or point component, are refused.

## 10. Requester links

A link that only serves its own branch is a **responder**. A link can also
read and command other links (a **requester**, as `isRequester` in DSA), or
do both. Give it **grants**, as a role has them:

| Level | The link can |
|---|---|
| `list` | list the nodes under the path (`~meta`) and see them come and go |
| `read` | also read and subscribe to their values (`~val`) |
| `write` | also `set` them and invoke their actions |

- **Path:** `wy/{site}/downstream` (every link), `wy/{site}/downstream/<link>[/…]` (one
  link or a part of it), or `wy/{site}/dataflows[/…]` (at most `read`). Plain
  segments only: no wildcards, no `~` suffixes, never `sys`. A grant covers
  the path and everything under it. `config` is for people only.
- **Who grants:** a package asks in `wyrm-link.json` (`requester`, section
  6); every link installed from it gets these grants, and the install
  message lists them (`…; grant wy/{site}/downstream/mock read`). Change them with
  `sys/links/<id>` ▸ **Grant Access** `{path, level}` (`none` removes).
  `sys` ▸ Get Permissions lists them (source `link`). Each change is in the
  audit journal (`link_grant`) and rebuilds the router.
- **How the link uses them:** with its own session, `ctx.client()`, and
  `wyrm_client::WyrmClient` over it. The router ACL lets the link's
  certificate reach the granted paths. For `set` and actions the client
  signs a `ptok` with the link's requester key, `LinkCtx::requester_key()`
  (the link secret `.requester_key`, made by the broker for a link with
  grants). Every link trusts that key up to the grant's level, only
  under its path and only with the subject `link:<id>`:

```rust
let key = ctx.requester_key().ok_or("no grants")?;
let tokens = SigningTokens::new(key, ctx.site()).subject(format!("link:{}", ctx.link()));
let client = WyrmClient::new(ctx.client().clone()).with_tokens(Arc::new(tokens));
client.set(&point, value).await?;
```

- **Embedded links** run on the broker's own session and bypass the router
  ACL, so they read every branch already. A grant gives them the requester
  key for `set` and actions.
- A requester key never opens `sys/**`, never deploys a flow, and never
  passes `config`.

`examples/links/requester` (a `read` grant) and `examples/links/both` (a
`write` grant) show both kinds; `examples/links/README.md` tells how to
install them.

## 11. Logs

- `sys/links/<id>` ▸ **Get Log** `{lines, level, filter}` shows the link's
  last lines: an embedded link's lines in the broker log (they carry its
  id), a process link's stdout and stderr (the last 2000 lines, also
  written to the broker's stderr). An external link logs on its own host.
- `sys/links/<id>/log_level`: `default` or a level. For an embedded link it
  sets the level of its lines alone; for a process link it sets its
  `RUST_LOG` and restarts it. Saved in the registry.
- The broker's own: `sys/log_level` and `sys` ▸ Get Log (filter by `link`
  to see one embedded link).
- A process package should log with `tracing-subscriber` (as the crates in
  `examples/links`): the level names in its lines become the level column.

## 12. Repository

Set `packages: { repository: "https://…/index.json" }` in `wyrmd.json5` (as
DSA's `linkRepositoryUrl`). The index is a JSON array, one entry per
package (ADR 0021):

```json
[{ "name": "example-link", "version": "1.0.0", "description": "…",
   "assets": {
     "linux-aarch64": { "url": "example-link/1.0.0/example-link-1.0.0-linux-aarch64.zip", "sha256": "<64 hex>" },
     "macos-aarch64": { "url": "example-link/1.0.0/example-link-1.0.0-macos-aarch64.zip", "sha256": "<64 hex>" } } },
 { "name": "register", "version": "1.0.0",
   "url": "register/1.0.0/register-1.0.0.zip", "sha256": "<64 hex>" }]
```

A process package has a file per host in `assets`; the broker installs the
file of its own host and lists only packages built for it. A package that
runs on any host (WASM) has `url` and `sha256`. A `url` without a scheme is
relative to the index, so the repository directory can be copied or
mirrored as it is.

Make a repository with `wyr repo add`: it puts each zip in
`<repo>/<name>/<version>/` and updates `<repo>/index.json` (a new version
replaces the entry, the same version adds the zip's host). Serve the
directory over HTTPS.

```sh
wyr repo add target/wyrm-link/*.zip --repo /srv/wyrm-repo
```

The broker fetches the index in the background on every start and rebuild;
*from Repository* lists its packages when it arrives. A broker without the
network starts as usual: the field then says why the list is empty. Without
`packages.repository` the item is still in the menu and says how to set it.

## 13. Trust and security

- **Who can install:** users with `config` on `wy/<site>/sys/**`. Each
  install and removal is in the audit journal (`sys/audit`) with the user,
  the package SHA-256 and the source.
- **No signing** (owner decision, as in DSA). A process package is code that
  runs on the broker host as the broker's user, limited by rlimits, its own
  data directory and the ACL of its own branch and its grants. Install only
  packages you trust, and read the grants an install lists.
- **Fetching** makes the broker connect to the URL you give. Credentials in
  a URL (`https://user:token@…`) are refused: the source is shown under
  `sys/packages` and kept in the audit. *from Git* takes public repositories
  only.
- WASM links run in the sandbox described in section 8.
- Threat model entries: `docs/security/threats.md` (Link packages, WASM
  links).

## 14. Limits

| What | Limit |
|---|---|
| Package zip | 64 MiB; 256 MiB unpacked; 1000 files |
| A file from the app (*from Zip*, *from WASM*) | 64 MiB, sent over `POST /api/invoke`; two uploads at a time, one per user, 120 s to send |
| Download (*from Url*, *from Repository*) | 64 MiB, 90 s, 3 redirects, HTTPS (HTTP to loopback only) |
| Repository index | 4 MiB, 1000 packages |
| Install action | 120 s |
| `git clone` | 120 s, depth 1, HTTPS only, needs `git` on the broker host |
| WASM component | 16 MiB |
| WASM call, `driver`/`point` component (section 8) | `call_ms` (2 s, at most 10 s), 100 M fuel, 16 MiB memory |
| WASM call, `app` component (section 9) | `call_ms` (2 s, at most 10 s), fuel 1 M per ms of `call_ms`, `memory_mb` per instance (64 MiB, at most 512 MiB) |
| Portable link (every mode) | 10 000 nodes, 64 actions per node, 1 000 timers, 1 000 subscriptions, 100 requests in flight, 1 000 commands per event; a `set`/`invoke` waits `call_ms` + 1 s |
| Portable link store | `store_mb` (1 MiB, at most 64 MiB); each entry at least 4 KiB (rounded up to 4 KiB); 10 000 keys; key 1–256 bytes |
| WASM network | 4 connections, 64 KiB per send or receive, IP literals only |

## 15. When an install fails

| Message | Meaning |
|---|---|
| `no wyrm-link.json at the zip root` | The manifest is missing or in a subdirectory. |
| `built for link protocol N, this broker speaks M` | Rebuild the package with this broker's `wyrm-link-sdk`. |
| `no entry for this host (linux-aarch64)` | Add a binary for this host to `entries`. |
| `unsafe path …`, `symlinks are not allowed` | The zip has a path that leaves its directory, or a symlink. |
| `… is installed with other content` | Same version, different bytes: raise the version. |
| `link … exists and runs …` | *Name* is taken by another link. |
| `process links need a tls/ listener on the broker` | Add a `tls/` listener to `listen` in `wyrmd.json5`. |
| `url: no credentials in the URL` | Remove `user:token@` from the URL. |
| `… plain http only to a loopback address` | Use HTTPS. |
| `repository unreachable: …` | The index could not be fetched; check `packages.repository`. |
| `the broker is restarting; try again` | Another install rebuilt the router; repeat the action. |
| `… is not in the link's net list` (point error) | Add the device address and port to the connection's Network. |

## 16. Try it in the demo

1. Run `examples/packages/build.sh`. It writes the packages to
   `examples/packages/out/`.
2. Run `examples/demo/run.sh`. It serves `out/` on `127.0.0.1:8090`; the
   edge site's `packages.repository` points there.
3. Log in to the edge gateway (`http://127.0.0.1:8444`, user `admin`).
4. Open `wy/edge/sys/links` ▸ Install Link ▸ from Zip, choose
   `example-link-<os>-<arch>.zip`, Name `example`, Invoke. Then open
   `wy/edge/downstream/example` ▸ Add Connection, Add Device, Add Point.
5. Install Link ▸ from WASM, choose `register.wasm`, Name `reg`. Open
   `wy/edge/downstream/reg/main` ▸ Add Device, then Add Point with Writable on.
   The point reads 7; write a number below 24 and read it back. The zips are
   under `out/<name>/<version>/`.
6. Install Link ▸ from Repository, Package `register`, Name `reg2`.
7. Install Link ▸ from Repository, Package `portable-echo`, Name `echo` (the
   portable link as WASM), and Package `portable-echo-process`, Name `echop`
   (the same app as a process). Install Link ▸ from Driver, Driver
   `portable-echo`, Name `echoe` (embedded). In each, set `n`, ▸ Ping, then
   `sys/links/<id>` ▸ Stop and ▸ Start: `n` comes back from the store and
   `starts` goes up by one.
8. Install Link ▸ from Repository, Package `recorder`, Name `rec` (a
   requester), and ▸ from Url
   `http://127.0.0.1:8090/average/1.0.0/average-1.0.0-<os>-<arch>.zip`,
   Name `avg` (both). See
   `examples/links/README.md` for what they do.

The macOS example app needs the entitlement
`com.apple.security.files.user-selected.read-only` in
`macos/Runner/DebugProfile.entitlements` and `Release.entitlements` for the
file picker. `dart/wyrm_flutter/example/macos/` is generated by
`flutter create` and not in git: add the key after you create it.
