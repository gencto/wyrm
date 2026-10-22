# Links: install, run and package them

A **link** connects devices or services to the WYRM tree. It serves the
subtree `wy/<site>/down/<link>/**`: nodes, values, `set` and actions. This
page tells you how to install a link while the broker runs, what the broker
does with it, what goes in a package, and what the limits are.

Decisions behind this page: ADR 0004 (driver framework), ADR 0006 (ACL and
quarantine), ADR 0010 (WASM host), ADR 0011 (installing links at runtime),
ADR 0012 (network for WASM links).

## 1. How a link runs

| Mode | Where the code runs | Where the code comes from | Isolation | Typical use |
|---|---|---|---|---|
| `embedded` | in the broker process | a driver built into `wyrmd` | none: same process | the built-in drivers |
| `process` | a child process the broker starts and watches | a built-in driver (`wyrmd link <driver>`) or a **process package** | own process, mTLS identity, ACL on its own branch, rlimits, cleared environment | your own driver in Rust |
| WASM | in the broker process, in a sandbox | a **WASM package** or one component (`.wasm`) | WebAssembly sandbox: no files, no clock, only the TCP addresses you list, fuel, memory and time limits | small protocol drivers, computed points |
| `external` | on another machine | anything that speaks the link protocol with a certificate from the broker's CA | mTLS identity, ACL on its own branch | gateways and devices in the field |

New code that arrives while the broker runs never loads into the broker as
native code: Rust has no stable plugin ABI, and a crash would take the broker
down. In the broker's own process it runs only as WASM.

## 2. What WYRM ships

- **Built-in drivers** (in `wyrmd`): `mock`, `mockdev` (the mock on the driver
  framework), `modbus`, `mqtt`, `agent`, `wasm`. Install them with
  *from Driver*.
- **Link SDK** (`crates/wyrm-link-sdk`): the raw link layer, the driver
  framework (Connection → Device → Point with `Add`/`Edit`/`Remove` actions)
  and `process::run` for a link that runs as its own binary.
- **WASM host and WIT** (`crates/wyrm-wasm-host/wit/link/point.wit`): the
  component worlds `wyrm:link/point` and `wyrm:link/driver`.
- **Example packages** (`examples/packages`): a process package (the
  `mockdev` driver as its own binary), a WASM package and two components,
  and a repository index. `examples/packages/build.sh` builds them.

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

*Name* is the new link's id: `wy/<site>/down/<Name>`. It is a key segment
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
     present (`wasm`).
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
     `<data_dir>/packages/.wasm/<package>.wasm` and starts an embedded link
     on the `wasm` driver with one connection `main`.
6. **Answer** `success: true` and a message such as
   `package example-link 1.0.0 installed; link ex1 installed`.

A link from a package starts with an empty tree if its driver is a
framework driver: add connections, devices and points with its *Add* actions.
The framework keeps that tree in the link's data directory.

## 5. Upgrade, reinstall, remove

| You do | Result |
|---|---|
| Install the same package (same version, same bytes) under another *Name* | A second link of the same package. The files are reused. |
| Install the same version with other bytes | Refused: `… is installed with other content`. Raise the version. |
| Install a new version (any *Name* that runs the package, or a new one) | The new version replaces the old one. Every link of the package restarts on it. The old files are deleted. Links keep their devices and points. |
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
| `entry` | `wasm` | The component file. |

Unknown fields are refused, so a typo does not pass silently.

## 7. Build a process package

A process package is a binary built on `wyrm-link-sdk` with
`process::run`. See `examples/packages/process-link`:

```rust
fn main() -> Result<(), Box<dyn std::error::Error>> {
    wyrm_link_sdk::limits::apply_from_env()?; // before the runtime
    tokio::runtime::Builder::new_multi_thread().enable_all().build()?
        .block_on(wyrm_link_sdk::process::run::<Framework<MyDriver>>())?;
    Ok(())
}
```

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

Build for each target host, put each binary under its `entries` path, and
zip it with `wyrm-link.json`. `examples/packages/build.sh` does this for the
host it runs on. Process mode needs a `tls/` listener in `wyrmd.json5`.

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
component new`). WYRM does not ship a guest template yet: the example
components in `examples/packages` are written by hand in the component text
format.

## 9. Repository

Set `packages: { repository: "https://…/index.json" }` in `wyrmd.json5` (as
DSA's `linkRepositoryUrl`). The index is a JSON array:

```json
[{ "name": "example-link", "version": "1.0.0", "description": "…",
   "url": "https://…/example-link-linux-x86_64.zip", "sha256": "<64 hex>" }]
```

The broker fetches the index in the background on every start and rebuild;
*from Repository* lists its packages when it arrives. A broker without the
network starts as usual: the field then says why the list is empty. Without
`packages.repository` the item is still in the menu and says how to set it.

## 10. Trust and security

- **Who can install:** users with `config` on `wy/<site>/sys/**`. Each
  install and removal is in the audit journal (`sys/audit`) with the user,
  the package SHA-256 and the source.
- **No signing** (owner decision, as in DSA). A process package is code that
  runs on the broker host as the broker's user, limited by rlimits, its own
  data directory and the ACL of its own branch. Install only packages you
  trust.
- **Fetching** makes the broker connect to the URL you give. Credentials in
  a URL (`https://user:token@…`) are refused: the source is shown under
  `sys/packages` and kept in the audit. *from Git* takes public repositories
  only.
- WASM links run in the sandbox described in section 8.
- Threat model entries: `docs/security/threats.md` (Link packages, WASM
  links).

## 11. Limits

| What | Limit |
|---|---|
| Package zip | 64 MiB; 256 MiB unpacked; 1000 files |
| A file from the app (*from Zip*, *from WASM*) | 64 MiB, sent over `POST /api/invoke`; two uploads at a time, one per user, 120 s to send |
| Download (*from Url*, *from Repository*) | 64 MiB, 90 s, 3 redirects, HTTPS (HTTP to loopback only) |
| Repository index | 4 MiB, 1000 packages |
| Install action | 120 s |
| `git clone` | 120 s, depth 1, HTTPS only, needs `git` on the broker host |
| WASM component | 16 MiB |
| WASM call | `call_ms` (2 s, at most 10 s), 100 M fuel, 16 MiB memory |
| WASM network | 4 connections, 64 KiB per send or receive, IP literals only |

## 12. When an install fails

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

## 13. Try it in the demo

1. Run `examples/packages/build.sh`. It writes the packages to
   `examples/packages/out/`.
2. Run `examples/demo/run.sh`. It serves `out/` on `127.0.0.1:8090`; the
   edge site's `packages.repository` points there.
3. Log in to the edge gateway (`http://127.0.0.1:8444`, user `admin`).
4. Open `wy/edge/sys/links` ▸ Install Link ▸ from Zip, choose
   `example-link-<os>-<arch>.zip`, Name `ex1`, Invoke. Then open
   `wy/edge/down/ex1` ▸ Add Connection, Add Device, Add Point.
5. Install Link ▸ from WASM, choose `register.wasm`, Name `reg`. Open
   `wy/edge/down/reg/main` ▸ Add Device, then Add Point with Writable on.
   The point reads 7; write a number below 24 and read it back.
6. Install Link ▸ from Repository, Package `register`, Name `reg2`.

The macOS example app needs the entitlement
`com.apple.security.files.user-selected.read-only` in
`macos/Runner/DebugProfile.entitlements` and `Release.entitlements` for the
file picker. `dart/wyrm_flutter/example/macos/` is generated by
`flutter create` and not in git: add the key after you create it.
