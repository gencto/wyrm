# Links: install, run and package them

A **link** connects devices or services to the WYRM tree. It serves the
subtree `wy/<site>/downstream/<link>/**`: nodes, values, `set` and actions. This
page tells you how to install a link while the broker runs, what the broker
does with it, what goes in a package, and what the limits are.

Decisions behind this page: ADR 0004 (driver framework), ADR 0006 (ACL and
quarantine), ADR 0010 (WASM host), ADR 0011 (installing links at runtime),
ADR 0012 (network for WASM links), ADR 0013 (links as requesters), ADR 0021
(packaging with `wyr`), ADR 0023 (portable links), ADR 0030 (TLS and random
bytes for WASM apps, world `wyrm:app@0.3.0`), ADR 0043 (the official links
manifest and its index).

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

### A refusal is an error

Spec 04 puts every status below `0x20` in the success or closed groups, and
requesters (`wyrm-client`, the gateway, Studio, `wyr`) read those as done. So
a link never answers a refused `set` or `invoke` with one. `not_available`
(`0x08`) is the status of a value that has none yet, never of a refused
request. The SDK enforces it: a `LinkError` with a closed-group status leaves
as `disconnected`, one with a success-group status as `internal_error` with a
warning in the log. The built-in drivers use these codes:

| The refusal | Status |
|---|---|
| The device answered with an error for this request (a protocol exception, an SZL error, an SNMP `error-status`, a BACnet Error/Reject/Abort, an HTTP error reply) | `invalid_parameter` |
| The device's reply cannot be read (a value that does not decode, a reply that is not JSON) | `invalid_message` |
| What the request needs is not there yet (no scrape, no reply kept) | `not_found` |
| The link cannot do it as configured (the agent without an LLM API key) | `not_supported` |
| The device does not answer | `timeout` |
| The connection is broken | `disconnected` |

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
- **Alarms** (`links/alarm`, ADR 0034): watches on points (boolean, out of
  range, staleness, quality) that raise alarm records, acknowledged, noted,
  kept in the broker's store and sent to a central database through the
  history sync links. Every broker runs one at `wy/<site>/downstream/alarm`;
  also the packages `alarm` (WASM) and `alarm-process`. Guide:
  [`docs/alarm.md`](alarm.md).
- **Uplink** (`links/uplink`, ADR 0035): platform upstreams, the site's live
  values to an MQTT broker (a Unified Namespace), a Sparkplug B host,
  ThingsBoard, Azure IoT Hub or AWS IoT Core, added with one action each as
  an upstream broker is. Every broker runs one at
  `wy/<site>/downstream/uplink` (`uplink.net` lists the platforms); it is
  also a portable link in the packages `uplink` (WASM) and
  `uplink-process`. Guide: [`docs/uplink.md`](uplink.md).
- **Telegram** (`links/telegram`) and **Slack** (`links/slack`), ADR 0039: one
  link per chat platform on the shared core `crates/wyrm-messenger`. Recipients and message
  templates are nodes (text, photo, document, location, buttons, Block Kit on Slack, live
  values escaped for the markup), each template with its own Send action; Telegram users
  pair their account with a one-time code and get `/get`, `/set`, `/do` within their level,
  their inviter's rights and the link's grants. Not embedded: packages `telegram`,
  `telegram-process`, `slack`, `slack-process`. Guides: [`docs/messenger.md`](messenger.md),
  [`docs/telegram.md`](telegram.md), [`docs/slack.md`](slack.md).
- **Modbus** (`links/modbus`, built-in driver `modbus`, package `modbus`):
  a master of Modbus TCP, RTU over TCP and serial RTU devices, and a slave
  that serves the tree's values to masters (ADR 0024); `import_dsa` takes
  a `dslink-java-modbus` tree. Its `Scaling` multiplies where DSA's
  divides: read the guide first,
  [`docs/modbus.md`](modbus.md).
- **HTTP** (`links/http`, driver `http`): JSON REST APIs polled on the
  driver framework. Guide: [`docs/http.md`](http.md).
- **BACnet** (`links/bacnet`): BACnet/IP devices (driver `bacnet`, package `bacnet`). Guide: [`docs/bacnet.md`](bacnet.md).
- **OPC UA client** (`links/opcua`, driver `opcua`, package `opcua`): nodes of OPC UA servers as points, with security and certificates. Guide: [`docs/opcua.md`](opcua.md).
- **Prometheus** (`links/prometheus`, driver and package `prometheus`): scrapes Prometheus / OpenMetrics endpoints and turns series selectors into points. Guide: [`docs/prometheus.md`](prometheus.md).
- **File stores** (`links/s3`, `links/gdrive`, `links/webdav`, `links/localfs`; drivers and packages `s3`, `gdrive`, `webdav`, `localfs`): a bucket, a Google Drive folder, a WebDAV collection or a directory of the host (disk, USB/SD, NFS/SMB mount) as a tree of folders and files, with Create Folder, Upload File, Download and Delete. Guide: [`docs/filestores.md`](filestores.md).

## 3. The Install Link menu

Open `sys/links` and its menu **Install Link ▸**. Every item needs `config`
on `wy/<site>/sys/**` (the `admin` role of the gateway). Every item except
*from Driver* answers with two rows, as in DSA: **success** (true or false)
and **message** (what happened, or why it failed).

| Item | Fields | What it does |
|---|---|---|
| from Driver | Link ID, Driver (the drivers this broker hosts, as choices), Mode, Params | A built-in driver as `embedded`, `process` or `external`. |
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
3. **Rights the package asks for.** A new link of the package gets its
   network allowlist (`capabilities.net`) and its `requester` grants. Without
   **Accept Requested Rights** (`accept: true`) such an install answers
   `success: false` with the list (`… asks for: network 10.0.5.0/24:502; read
   on wy/plant/downstream/mock`) and installs nothing. Read the list, then
   install again with it on (security review WASM-1, ADR 0031). An upgrade of
   a package keeps the rights its links already have.
4. **Move into place** with one rename:
   `<data_dir>/packages/<name>/<version>/`. A failed install leaves nothing.
5. **Record.** The registry (`<data_dir>/state`, a write-ahead log) stores
   the package: name, version, kind, entry, SHA-256 of the zip, source. The
   audit journal gets `package_install` with the SHA-256 and the source.
6. **Start the link** with driver `pkg:<package>`:
   - `process` package: a process link. The broker issues a certificate with
     CN = the link id and a link token, rebuilds the router ACL (the router
     restarts for about a second, and open app connections reconnect), and
     starts the package entry.
   - `wasm` package: the broker copies the component to
     `<data_dir>/packages/.wasm/<package>.wasm` and starts an embedded link:
     a `driver` or `point` component on the `wasm` driver with one
     connection `main`; an `app` component on the driver `app` with its
     capabilities as params (section 9).
7. **Answer** `success: true` and a message such as
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
| `world` | no | `wasm`: `app`, `driver` or `point`, or an app world with its version: `wyrm:app@0.1.0`, `wyrm:app@0.2.0` or `wyrm:app@0.3.0` (`wyr link pack` writes the version). Informational: the broker reads the world (and an app's version) from the component and refuses a package whose `world` says otherwise; plain `app` takes any version. |
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
| `WYRM_ENDPOINT` | The broker's `tls/` listener on loopback. A link started by hand (an external link, a package on another host) may list several endpoints, comma-separated, in the order to try: `tls/10.0.0.1:7448,tls/10.0.0.2:7448` (a site with a standby broker, ADR 0036). One session per endpoint: the link connects to the first that answers, and serves it only when the site's broker is there (the liveliness token `wy/<site>/sys/broker`); a router without it, or whose broker has been gone for `WYRM_BROKER_WAIT_S`, is left for the next endpoint. |
| `WYRM_BROKER_WAIT_S` | With several endpoints: seconds a router without the site's broker is kept before the next endpoint (15 by default). |
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

- A WASM driver (`wyrm:link/tcp`): IP literals only, in the list and in `connect`.
- A portable app (ADR 0026; native and process forms, and WASM components of world
  `wyrm:app@0.3.0`, ADR 0030) may also name hosts: `db.example.com:5432`, `*.example.com:443`, in `tcp_connect`,
  `tls_connect`, and `tls_upgrade` (TLS on an open connection, as PostgreSQL's and MySQL's
  `SSLRequest`). The host resolves the name and connects only to an address that an IP entry
  allows, or to a public address when the name is listed: a listed name never reaches
  loopback, link-local, metadata or private addresses (`10/8`, `172.16/12`, `192.168/16`,
  `100.64/10`, `fc00::/7`) by itself. A database on the LAN needs its address or range as an
  IP entry too (`db.lan:5432, 10.0.5.0/24:5432`): whoever answers for a name in DNS could
  otherwise point the link at any host of the LAN (security review NET-1).
- `connect` passes when the address is inside an entry and the port is that
  entry's port.
- Loopback, link-local (also `169.254.169.254`), multicast, broadcast,
  `0.0.0.0/8`, cloud metadata and IPv6 addresses that carry an IPv4 address
  (NAT64, 6to4, IPv4-compatible) pass only an entry of their own class:
  `0.0.0.0/0` does not reach the broker itself. Private ranges (`10/8`,
  `172.16/12`, `192.168/16`, `fd00::/8`) are ordinary for IP entries; a host name
  entry does not reach them (above).
- Only users with `config` can change the list.

**Limits per call:** the call time (`call_ms`, also caps every network wait),
100 M fuel, 16 MiB memory, at most 4 open connections, 64 KiB per `send` and
per `recv`. Past a limit the call fails, the instance is dropped with its
connections, and the next call starts a new one.

**Not available to a driver component** (`wyrm:link/driver`): TLS, DNS,
UDP, serial ports, files, clocks, random numbers, other processes. The
component implements its protocol itself (for example Modbus TCP framing).
A portable app (section 9) gets more from its host.

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
glue for the world `wyrm:app@0.3.0` (`crates/wyrm-wasm-host/wit/app3/app.wit`).

**What a WASM app may call** (the one import `wyrm:app/host`; no WASI):

| World | Adds |
|---|---|
| `wyrm:app@0.1.0` (`wit/app`, frozen) | the tree (`declare-node`, `declare-action`, `remove-node`, `update`), the clock, timers, the store, `subscribe`, `set`, `invoke`, plain TCP (`tcp-connect`, `tcp-send`, `tcp-recv`, `tcp-close`), `log` |
| `wyrm:app@0.2.0` (`wit/app2`, frozen) | `list` and the export `on-list` (ADR 0025); `subscribe` of `<prefix>/**` |
| `wyrm:app@0.3.0` (`wit/app3`) | `tls-connect`, `tls-upgrade` (TLS within `net`, the certificate verified against the system roots or a given CA; the keys stay in the host) and `random-bytes` (at most 1024 bytes per call, from the OS) (ADR 0030) |

A broker runs all three. The calls go to the same host code as the native
and process forms, under the same `net` list, call time and bounds; a
capability not granted fails with `permission_denied`. A package needs
`wyrm:app@0.3.0` for TLS (a history sync link to a cloud database, for
example): one built for 0.2.0 still runs, but answers `not_supported` to
TLS and gets no random bytes. Rebuild it with `wyr link pack`.

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
   `world: "wyrm:app@0.3.0"` (the version the component was built for) and
   the `capabilities` in `wyrm-link.json`.

Add the target first: `rustup target add wasm32-unknown-unknown`.

**Capabilities**, granted at install (*Install Link ▸ from Zip*, *Url*,
*Git* or *Repository*). The install result lists them, for example
`capabilities net none, store 1 MiB, memory 64 MiB, call 2000 ms`. They
become the link's params:

| Capability | Default | Bounds | Meaning |
|---|---|---|---|
| `net` | none | entries as in section 8 | Where the app may connect (`tcp_connect`, `tls_connect`). |
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
framework `wasm` driver (section 8). An app's version comes from its import
`wyrm:app/host@<version>`. A manifest whose `world` is not the component's
(with a version: not its version), an app world version the broker does not
run, and capabilities on a driver or point component, are refused.

## 10. Requester links

A link that only serves its own branch is a **responder**. A link can also
read and command other links (a **requester**, as `isRequester` in DSA), or
do both. Give it **grants**, as a role has them:

| Level | The link can |
|---|---|
| `list` | list the nodes under the path (`~meta`) and see them come and go |
| `read` | also read and subscribe to their values (`~val`) and call `next` on a sink under the path (a history sync link reading a link's sink, ADR 0034) |
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

### Streams and a slow consumer

`WyrmClient::list`, `subscribe`, `subscribe_reliable` and `invoke` return an
`EventStream`. A stream never holds up the Zenoh session, also when its
consumer stops reading: it keeps its own bounded buffer, and a full buffer
follows the policy of its kind. `EventStream::dropped()` counts what the
stream did not deliver; it stays 0 while the consumer keeps up.

| Stream | When the consumer is behind |
|---|---|
| `subscribe` (`~val`) | Every sample, in arrival order, while at most `VALUE_BUFFER` (4096) wait: a consumer that is a little behind loses nothing. Only one more switches the stream to overflow mode until the consumer has taken what waits: one pending value per key, a newer `t` replaces an older one (values are state), and the replaced values count. After the stall the consumer gets the queued samples, then the latest value, quality and time of every key, in time order per key. At most `MAX_PENDING_KEYS` (4096) keys wait: a sample of one more key is dropped and counted, and when the consumer has taken what waits, the stream reads the stored values again, so that key still gets its newest stored value. If more than 4096 keys wait again after `MAX_RESYNCS` (3) such reads in a row, without the consumer catching up in between, the stream ends with `resource_exhausted` ("consumer too slow"). |
| `subscribe_reliable` (QoS 2/3) | A queue of `RELIABLE_BUFFER` (4096) samples; the oldest beyond it is dropped and counted. |
| `list` (`~meta`, liveliness) | Up to `LIST_BUFFER` (1024) events are held. One more discards them (counted), and the stream reads the children again and sends `Refreshed`, so the consumer's view is whole again. If the owner is gone, it sends `Disconnected(None)` and lists again when the owner is back. |
| `invoke` (a stream action) | Up to `INVOKE_BUFFER` (1024) replies are held. One more ends the stream: the held replies, then `resource_exhausted` ("consumer too slow"). Results are never dropped one by one. |

`subscribe` still subscribes before it reads the stored values (no lost
update), and per key it never hands out a sample as old as or older than
one it already gave. One stream hands out at most `MAX_STREAM_KEYS`
(16 384) distinct keys, gateway subscriptions included; one more ends it
with `resource_exhausted` ("the pattern matches more than 16384 keys"):
subscribe narrower patterns. `EventStream::error()` tells, after the
stream ended, which limit ended it; the gateway sends it to the
WebSocket as the stream's error frame instead of `closed`.
`subscribe_filtered(pattern, keep)` drops the keys
`keep` refuses before they take room; the gateway passes the user's read
grants, so a point the user may not read uses no memory. A consumer
that must see every sample (a historian with All Data logging, a flow
counter) gets every sample unless more than 4096 wait; only then are
intermediate samples lost, counted in `dropped()`; before this rule it
stopped the session instead. The gateway forwards each stream to its WebSocket and
waits there for room, so a slow socket only slows its own streams.

A stream holds its buffer only while it lives: dropping it undeclares its
subscribers, cancels the query of an `invoke`, and frees the buffer at
once; Zenoh's later replies to that query are dropped on arrival.

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

An index may carry more fields than these (the official index does, §12a);
the broker ignores fields it does not know.

## 12a. Official links

`links/official.json` is the one list of the links this project releases
(ADR 0043): per link its `id`, `crate`, `title`, `summary`, `category`,
`version` (the crate's), `wyrm_link` (link protocol), `min_broker` and
`forms`: `builtin` (a driver of `wyrmd`), `wasm` (one package for every
host), `process` (one package per host of `hosts`: `linux-aarch64`,
`linux-x86_64`, `macos-aarch64`). It holds no URLs and no hashes: CI adds
them when it publishes.

**Use it on a broker.** It is off by default: a broker fetches nothing
until you set the repository.

```json5
packages: { repository: "official" },
```

`"official"` is the index of the manifest this broker was built with,
`https://github.com/gencto/wyrm/releases/download/links-index/links-index.json`.
*Install Link ▸ from Repository* then lists the official packages built for
this host, and installs one after it checks its SHA-256. A site without
internet access uses a mirror (docs/operations.md, *Official links offline*).

**What a client reads.** The `~meta` of `wy/<site>/sys/links` has
`attr.catalog`: one map per built-in driver of this broker and per
repository package for this host, with `id` (`driver:<code>` or
`package:<code>`), `code`, `link`, `title`, `summary`, `category`,
`version`, `form` (`builtin`, `wasm`, `process`) and `official`. A driver's
version is the broker's, a package's is the index's. The broker fills in
titles from its own copy of the manifest, so built-in drivers have them
without the network. WYRM Studio's *Add a link* reads this list.

**Change it.** A new official link or a new version is one edit of
`links/official.json` together with the crate's `Cargo.toml`.
`cargo test` fails when they disagree (`wyr` test
`official_manifest_matches_the_workspace`, `wyrmd` test
`official_builtin_forms_are_drivers_of_wyrmd`). Check it by hand:

```sh
wyr repo check                                   # the manifest against the workspace
wyr repo build --form wasm --out dist            # every wasm form
wyr repo build --form process --target x86_64-unknown-linux-musl --out dist
wyr repo index --zips dist --tag links-v2026.11.11 --out dist/links-index.json
```

`wyr repo index` refuses a zip that is not a listed form, of another
version, kind, protocol or host, and a form or host with no zip
(`--partial` allows the last one, for a local run). Without `--tag` or
`--base` the URLs are relative: the zips beside the index (a mirror).

**Release.** Push a tag `links-v<anything>`. The workflow
`packaging/links/release-workflow.yml` (copied to
`.github/workflows/links-release.yml`) builds every form on GitHub runners,
publishes the zips, `links-index.json`, `official.json` and `SHA256SUMS` as
release `<tag>`, and replaces the one asset of release `links-index`. The
index of a release names the files of that release, so a broker that read
the index just before the next release still installs matching files.

**Trust.** The index is fetched over HTTPS from github.com and every zip is
checked against its SHA-256. Neither the index nor the packages are signed
yet: whoever can write release assets of the repository can change what
brokers install. The install still shows the network and grants a package
asks for before it runs anything (§13).

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
| WASM network | 4 connections, 64 KiB per send or receive, IP literals only (host names: TLS of portable apps) |

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

WYRM Studio on macOS needs the entitlement
`com.apple.security.files.user-selected.read-only` in
`studio/app/macos/Runner/DebugProfile.entitlements` and
`Release.entitlements` for the file picker, and `network.client` to reach a
gateway ([`docs/studio.md`](studio.md)).
