# ADR 0024 — Server kinds in the driver framework (Modbus slave)

**Status:** accepted · 2026-10-30 (Modbus DSA parity plan, ruling 15; master writes as ruling P4).

## Context
DSA's Modbus link can also be a slave: it serves values from its tree to Modbus masters (SCADA, PLCs) and takes their writes. ADR 0004 sketched an optional `ServerKind` trait with a shared listener per port and a process image per unit, but nothing was built. The framework knew only connections that poll devices: an owner task per connection holds the transport, tickers send polls and pings, a `~set` is a device write followed by a read-back.

A server has the same shape seen from the other side: a listener (or a serial port) instead of a socket to a device, unit ids instead of devices, and points that a master reads instead of points the link reads. What differs is where values come from and that they flow both ways.

## Decision
- **A server is a connection kind.** `Driver::is_server(conn) -> bool` (default `false`) marks it; the Modbus link adds the kinds `ip_slave {listen_host, listen_port}` and `serial_slave {serial params}` beside `ip_connection` and `serial_connection`. Its devices are the units it serves, its points are what it serves. Nothing new in the tree, the actions or the stored config: `add_*`, `edit`, `remove`, `start`/`stop`, folders, `copy`, `export` and `import` work as for any connection (a copy or import starts stopped, so two servers never fight for a port). `open` returns the running server; dropping the transport closes it.
- **Not polled, not pinged.** A server connection gets no tickers. Its devices are `Connected` while it runs.
- **Values from the tree.** Every point of a server takes `~set` at level write, whatever the driver's `point_meta` says (Modbus: input registers and discrete inputs too, which a master cannot write). `Driver::write` puts the value into what the server serves; there is no device read-back: the framework publishes what the driver now serves (`Driver::take_changed`), which is the value a master reads (after its encoding: an `f32`, a scale). Before the framework hands a plan to the server (`Driver::serve`; at once: a re-plan wakes the owner), it writes the tree's last value of every point that is new to the server or whose params or device params changed (after open: every point). So a restarted or edited connection, a device started again and a point edited to another scale serve the tree's value; a point that stays as it was keeps what it serves (a master may have written it).
- **Values from the remote side, in one order.** A master's request goes through a channel to the connection's owner task (`Driver::remote`, cancel-safe: it awaits only the receipt), the same task that applies the tree's sets. So the last writer wins, and the value published is what the next master read returns. The remote side gets its answer only after the framework published what the request changed. A master write is logged at info by point (never the value) and counted in the device's and the connection's diagnostics; there is no `sys/audit` record (no WYRM caller).
- **Listener on loopback by default** (`listen_host = "127.0.0.1"`). Modbus has no authentication: anyone who reaches the port reads every served value and writes those a master may write. Another address is allowed (adding a connection is already a `config` action), but the bound address is checked: one that is not loopback is logged at warn when the server opens and shown as `attr.warning` on the connection's `status` leaf (`Driver::status_note`; no new leaf, so no new reserved name).
- **Driver actions of their own.** A server connection and its devices offer `Driver::server_actions` instead of `Driver::actions` (Modbus: none; the commissioning actions are a master's).

Modbus rules (the driver's, in `links/modbus/src/slave.rs`): points are views on the served registers and bits of their unit, so devices with the same unit and overlapping points share them; an address no point covers answers exception 2, a write touching a point without `writable_by_master` exception 3, and a refused request changes nothing. A unit not served gets no reply on RTU (another slave on the bus may have it; unit 0, the broadcast, is never answered or applied) and exception 0x0B on TCP.

## Consequences
- Every hook has a default; drivers without server kinds compile and behave as before.
- One request at a time per server connection: a master's reads wait behind the tree's sets (in-memory work, no I/O).
- A stored point loads unchanged: `writable_by_master` defaults to `false`; it does nothing under a master connection, and `poll_s` and the device's ping and batch params do nothing under a slave.
- The served values live in memory: a restart of the link starts from the tree's values it has, a fresh link process from zero.
- The tree's last value is the source of truth only while the link runs; a value a master wrote is in the tree like any other.

## Alternatives
- **A `ServerKind` trait beside `Driver`, one listener per port shared by connections** (the ADR 0004 sketch): a second registration path, ref-counting and overlap rules across connections, for a case (two connections on one port) that a second device under one connection already covers.
- **Answering reads in the server task from a shared image (a mutex):** faster reads, but tree sets and master writes would be ordered in two places, and the diagnostics would miss the reads.
- **Showing the warning in the `error` leaf:** that leaf means the node failed; a running server is not failed.
