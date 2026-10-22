# ADR 0012 — Network for WASM links (`wyrm:link/tcp`)

**Status:** accepted (owner decision 2026-10-22: WASM links get network in this iteration) · 2026-10-22

## Context
ADR 0011 lets a link run as a WASM component inside the broker. The component world `wyrm:link/point` (ADR 0010) imports nothing, so such a link cannot reach a device: it only computes. The owner wants WASM links that talk to devices now. A WASM component has no ambient rights; every capability is a host import.

## Decision
- **WIT.** Package `wyrm:link@0.1.0` gets `interface tcp` and world `driver`:
  - `connect(addr: string, port: u16, timeout-ms: u32) -> result<u32, string>` — `addr` is an IP literal (`192.168.1.20`, `fd00::5`), never a host name;
  - `send(conn: u32, data: list<u8>) -> result<_, string>` — at most 64 KiB per call; the time left is checked again before each piece written;
  - `recv(conn: u32, max: u32, timeout-ms: u32) -> result<list<u8>, string>` — at most 64 KiB per call, an empty list at EOF;
  - `close(conn: u32)`;
  - world `driver` = world `point` (`init`, `read`, `write`) plus `import tcp`. A `point` component (no imports) runs as a `driver` too. The linker defines exactly this interface: any other import is still refused at load (`Error::Denied`).
- **Allowlist (capability).** Each instance has a list of `<ip>/<prefix>:<port>` entries (`10.0.5.0/24:502`, `[fd00::]/64:502`); empty = no network. `connect` passes only when the address is inside one entry and the port is that entry's port. IP literals only, in the list and in `connect`: `std` resolution has no timeout, and resolve-then-check invites rebinding. Special addresses pass only an entry of the same class that is no wider than the class: loopback, link-local (and IPv6 site-local), multicast, broadcast, "this network" (`0.0.0.0/8`), IPv6 that carries an IPv4 address (IPv4-compatible, NAT64 `64:ff9b::/96` and `64:ff9b:1::/48`, 6to4 `2002::/16`) and cloud metadata (`169.254.169.254` is link-local; `fd00:ec2::/32`). So `0.0.0.0/0` or `[::]/0` never reaches the broker's own listeners (in `dev`, loopback has full rights). Private ranges (`10/8`, `172.16/12`, `192.168/16`, ULA) are ordinary: field devices live there. IPv4-mapped IPv6 is checked as IPv4.
- **Who sets it.** The list is a connection parameter of the `wasm` framework driver (`net`). The framework's `add_*` and `edit` actions need `config` (ADR 0004), so only `config` widens it; the parameter is a destination field (`dest`), so a stored secret does not follow a changed list.
- **Time.** Epoch deadlines count wall time inside host calls too. A link call has its own budget: 2 s by default, at most 10 s (`call_ms`); flow nodes keep theirs (ADR 0010). Every host I/O timeout is capped at the time left in the call, so a blocking `recv` cannot outlive the call; the next guest instruction after the deadline traps, the instance is dropped (its connections closed) and the next call instantiates it again.
- **Handles.** At most 4 open connections per instance, kept in the store; they close when the instance drops (trap, slot swap, link stop).
- **Threads.** Host I/O is blocking `std::net`. Each WASM connection of the driver runs on its own OS thread that owns the store; the framework's per-connection owner task sends it `read`/`write` requests over a bounded channel. No `async` in wasmtime, no blocked tokio workers.
- **Driver `wasm`** (`links/wasm`, a framework driver, embedded): connection params `component` (the package name: the admin puts each `wasm` package's entry at `data_dir/packages/.wasm/<package>.wasm`, replacing it in one rename on an upgrade, and restarts the package's links so they load the new file; naming another installed package only selects that one), `net`, `config` (JSON, passed to `init` as CBOR), `call_ms`; device `note` (devices only group points: no ping); point `value` (`number`, `bool`, `text`, `any`: the node type, so an app sends the right type on `set`), `cfg` (JSON, passed to `read`/`write` as CBOR), `poll_s`, `writable`, `unit`. A `wasm` package (or one component through "Install Link ▸ from WASM", wrapped as package `<name>`, version `0+<sha256 prefix>`) installs as an embedded link with driver `pkg:<name>` and one connection `main`; its devices and points come from the connection's `Add` actions and survive upgrades (the framework keeps its tree). Test: `wasm_link_reads_a_device_over_tcp`.

## Consequences
- A WASM link implements its protocol (Modbus framing, …) inside the guest, with the network limited to the listed addresses and ports.
- Not in v1: TLS, DNS, UDP, serial ports, clocks. Each would be another explicit import.
- A guest can still use its time and fuel on network waits; the per-call budget bounds it.

## Alternatives
- **WASI sockets** (`wasi:sockets`): rejected for now; a deny-all WASI policy is harder to audit than one small interface (ADR 0010).
- **Host names with a resolver**: deferred; needs a resolver with timeouts and a resolve-once rule.
- **Async host functions** (`async_support`): rejected; it would change the flow-node path too.
