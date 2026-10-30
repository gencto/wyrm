# Modbus

The `modbus` link reads and writes Modbus devices as a **master** (Modbus
TCP, RTU over TCP, RTU on a serial port) and serves the tree's values to
Modbus masters as a **slave** (Modbus TCP, RTU on a serial port). It runs
on the driver framework of `wyrm-link-sdk`, so its tree, actions, states
and quality work like those of every framework driver. Decisions: ADR 0004
(the driver framework) and ADR 0024 (server kinds, the slave mode).

Code: `links/modbus` (`wyrm-link-modbus`): `src/lib.rs` (the driver and
its params), `src/codec.rs` (data types, batches), `src/slave.rs` (slave
mode), `src/dsa.rs` (`import_dsa`), `src/sim.rs` (the test simulator).
The link is a built-in driver of `wyrmd` (*Install Link ▸ from Driver*,
driver `modbus`) and the package `modbus` (`wyr link pack`).

## 1. Read this first: scaling is not DSA's

A DSA (`dslink-java-modbus`) user who types the same numbers into the same
labels gets **wrong values without an error**. Our `Scaling` multiplies;
DSA's divides. Use `import_dsa` (section 11) to move a DSA tree: it
converts every point.

| DSA attribute | DSA meaning | Our form label | Our key (json5, `~def`, export) | Our meaning |
|---|---|---|---|---|
| `offset` | register or bit address | Offset | `addr` | register or bit address |
| `scaling` | divisor: `raw / scaling` | Scaling | `scale` | **multiplier**: `raw × scale` |
| `scaling offset` | added after the division | Scaling Offset | `offset` | added after the multiplication |
| write of `v` | `v × scaling − scaling offset` (not the inverse when `scaling offset` ≠ 0) | | | `(v − offset) / scale`, rounded for integer types (the exact inverse) |

- **Read:** value = raw × `scale` + `offset`. DSA: value = raw / `scaling` +
  `scaling offset`.
- **In json5 and in an export, the key `offset` is the added offset,** not
  the address. The address is `addr`.
- **Example.** A DSA point has `scaling = 10`, `scaling offset = 2`, raw
  250. DSA shows 27.0. The same numbers typed into our form show
  250 × 10 + 2 = 2502. `import_dsa` sets `scale = 0.1`, `offset = 2`: the
  point shows 27.0, and a write of 27.0 sends raw 250.
- **Writes of imported points differ from DSA** when `scaling offset` is
  not 0. A write of 27.0 sends 250 here; DSA sent 27 × 10 − 2 = 268. A
  device or a procedure tuned around DSA's raw values sees other raw
  values after the move.
- **Float noise.** `scale = 1 / scaling` is not exact in binary: with
  `scaling = 10`, raw 3 shows `0.30000000000000004` where DSA showed `0.3`,
  and raw 7 shows `0.7000000000000001`. Trends and equality tests in flows
  see this. Writes to integer types are not affected: the raw value is
  rounded.
- `scale = 0` is refused (`scale: must not be 0`); DSA `scaling = 0` is not
  imported.

## 2. Tree and actions

```
wy/<site>/downstream/<link>/<connection>/<device>/[<folder>/…]/<point>
```

A connection is a socket or a serial port (or, for a slave, a listener).
A device is one unit id on it. A point is a value at an address. Folders
(section 10) group points below a device. Connections and devices have a
`status` leaf (Unknown, Connecting, Connected, Failed, Stopped, Stopped by
Parent), an `error` leaf while there is an error, and the diagnostics
leaves (section 12).

| Node | Actions | Level |
|---|---|---|
| link root | `add_ip_connection`, `add_serial_connection`, `add_ip_slave`, `add_serial_slave`, `export` (the whole tree), `import` (a connection branch), `import_dsa`, `rescan` (Rescan For Serial Ports) | config |
| connection | `add_device`, `edit`, `remove`, `copy`, `restart`, `stop` / `start`, `export`, `import` (a device branch) | config |
| master connection | `scan_units` | config |
| device | `add_point`, `add_folder`, `edit`, `remove`, `copy`, `restart`, `stop` / `start`, `export`, `import` (a folder branch) | config |
| master device | `read_registers`, `read_device_id` | read |
| folder | `add_point`, `add_folder` (while less than 4 deep), `remove`, `copy`, `export`, `import` (a folder branch) | config |
| point | `edit`, `remove`, `copy` | config |
| point value | `~set` (writable points; every point of a slave) | write |

Only the action that applies is declared: `stop` while a node runs,
`start` while it is stopped. DSA puts every action at `READ`, so anyone
who can read can reconfigure; here a change of the tree needs `config`.

## 3. Parameters

Every default and bound below is the code's (`links/modbus/src/lib.rs`).
A param with a default may be left out. Edits are checked first: a refused
edit changes nothing.

### IP connection (`ip_connection`)

| Key | Label | Default | Bounds | Notes |
|---|---|---|---|---|
| `host` | Host | (required) | | name or IP literal; the first address it resolves to |
| `port` | Port | 502 | 0…65535 | |
| `transport` | Transport Type | `tcp` | `tcp`, `rtu_over_tcp` | `rtu_over_tcp`: RTU frames (CRC, no MBAP header), as serial-to-Ethernet gateways send |
| `timeout_ms` | Timeout (ms) | 1000 | 100…10000 | bound on each request |
| `write_mode` | Write Mode | `auto` | `auto`, `single`, `multiple` | section 6 |
| `retries` | Retries | 0 | 0…5 | repeats after a timeout only (section 7) |

### Serial connection (`serial_connection`)

| Key | Label | Default | Bounds | Notes |
|---|---|---|---|---|
| `serial_port` | Serial Port | (required) | a serial device path | `/dev/ttyS*`, `ttyUSB*`, `ttyACM*`, `ttyAMA*`, `ttySC*`, `ttyM*`, `ttyMXUSB*` and other numbered Linux UART names, `/dev/tty.*` and `/dev/cu.*` (macOS), `/dev/serial/by-id/*`, `/dev/serial/by-path/*`, `/dev/rfcomm*`; `COMn` on Windows. Another path is refused (some device files have side effects on open). `rescan` lists the ports found. |
| `baud_rate` | Baud Rate | 9600 | 300…4000000 | |
| `data_bits` | Data Bits | 8 | 5…8 | |
| `stop_bits` | Stop Bits | 1 | 1…2 | |
| `parity` | Parity | `none` | `none`, `odd`, `even` | |
| `timeout_ms` | Timeout (ms) | 1000 | 100…10000 | |
| `write_mode` | Write Mode | `auto` | as above | |
| `retries` | Retries | 0 | 0…5 | 1 is a good value on RS485 |

### Slave connections (`ip_slave`, `serial_slave`)

| Key | Label | Default | Bounds | Notes |
|---|---|---|---|---|
| `listen_host` | Listen Host | `127.0.0.1` | | `ip_slave`: every address the name resolves to (section 13) |
| `listen_port` | Listen Port | 502 | 0…65535 | `ip_slave`; 502 needs privileges on Linux |
| `serial_port`, `baud_rate`, `data_bits`, `stop_bits`, `parity` | | as the serial connection | | `serial_slave` |

### Device

| Key | Label | Default | Bounds | Notes |
|---|---|---|---|---|
| `unit` | Slave ID | 1 | 0…255 | 0 and 255 are ordinary units on Modbus TCP; on RTU 0 is the broadcast address and is refused (section 6) |
| `ping` | Ping | `probe` | `probe`, `fc17`, `none` | `probe` reads `probe_table`/`probe_addr`, and an exception reply means alive; `fc17` sends Report Server ID (often unsupported); `none` sends no ping |
| `probe_table` | Probe Table | `holding` | `coil`, `discrete`, `input`, `holding` | |
| `probe_addr` | Probe Address | 0 | 0…65535 | |
| `ping_s` | Ping Rate (s) | 5.0 | 0.1…3600 | |
| `contiguous_only` | Contiguous Batch Reads Only | false | | false: a read may span gaps between points |
| `max_regs` | Max Registers per Read | 125 | 1…125 | 1 = each register point read alone |
| `max_bits` | Max Bits per Read | 2000 | 1…2000 | 1 = each bit point read alone |
| `republish_s` | Republish Unchanged Values (s) | 0 | 0…3600 | 0 = publish on a change only; DSA republishes every 60 s |

### Point

| Key | Label | Default | Bounds | Notes |
|---|---|---|---|---|
| `table` | Object Type | (required) | `coil`, `discrete`, `input`, `holding` | |
| `addr` | Offset | (required) | 0…65535 | the value may not run past 65535 |
| `dtype` | Data Type | `u16`; `binary` on `coil` and `discrete` | section 4 | a bit table holds `binary` only |
| `bit` | Bit | 0 | 0…15 | the bit of a register for `binary` on `input`/`holding` |
| `regs` | Number of Registers | 1 | 1…125 | registers of a `char`/`varchar` value |
| `poll_s` | Poll Rate (s) | 1.0 | 0.01…86400 | |
| `scale` | Scaling | 1.0 | not 0 | multiplier (section 1) |
| `offset` | Scaling Offset | 0.0 | | added after `scale` |
| `writable` | Writable | false | | `coil` and `holding` only |
| `unit` | Unit | `""` | | shown beside the value |
| `writable_by_master` | Writable by Master | false | | slave connections only (coil and holding) |

- `writable_by_master` shows in every point form but **does nothing under
  a master connection**.
- Under a slave connection `poll_s` and `writable` do nothing, and so do
  the device's `ping`, `probe_table`, `probe_addr`, `ping_s`,
  `contiguous_only`, `max_regs`, `max_bits` and `republish_s`. Every
  point of a slave takes `~set` (section 13).
- The link root takes `poll_unsubscribed` (default true: points are
  polled all the time; false polls a group only while one of its points
  has a subscriber, which only process links can see).

## 4. Data types

Register words are big-endian on the wire. A multi-word value puts the
most significant word first. `_wswap` reverses the word order, `_bswap`
swaps the two bytes in each word, `_wbswap` does both (all bytes in
reverse order). For the 32-bit value `0x11223344` (bytes A B C D) the
registers are:

| Order | Registers | Our suffix |
|---|---|---|
| ABCD | `0x1122 0x3344` | none |
| CDAB | `0x3344 0x1122` | `_wswap` |
| BADC | `0x2211 0x4433` | `_bswap` |
| DCBA | `0x4433 0x2211` | `_wbswap` |

| Ours | Registers | Value | DSA name |
|---|---|---|---|
| `binary` | a bit, or bit `bit` of 1 | bool | `BOOLEAN` (any type on a coil or discrete table) |
| `bits16` | 1 | array of 16 bools, bit 0 first | `BOOLEAN` with `bit = -1` on a register |
| `u16`, `i16` | 1 | number | `UINT16`, `INT16` |
| `u16_bswap`, `i16_bswap` | 1 | number | `UINT16SWAP`, `INT16SWAP` |
| `u32`, `i32` | 2 | number | `UINT32`, `INT32` |
| `u32_wswap`, `i32_wswap` | 2 | number | `UINT32SWAP`, `INT32SWAP` |
| `u32_wbswap`, `i32_wbswap` | 2 | number | `UINT32SWAPSWAP`, `INT32SWAPSWAP` |
| `u32_bswap`, `i32_bswap` | 2 | number | none |
| `u32_m10k`, `i32_m10k` | 2 | `hi × 10000 + lo` | `UINT32M10K`, `INT32M10K` |
| `u32_m10k_wswap`, `i32_m10k_wswap` | 2 | as above, words swapped | `UINT32M10KSWAP`, `INT32M10KSWAP` |
| `f32` | 2 | IEEE 754 | `FLOAT32` |
| `f32_wswap` | 2 | | `FLOAT32SWAP` |
| `f32_wbswap` | 2 | | none |
| `u64`, `i64`, `f64` | 4 | | `UINT64`, `INT64`, `FLOAT64` |
| `u64_wswap`, `i64_wswap`, `f64_wswap` | 4 | the four words reversed | `UINT64SWAP`, `INT64SWAP`, `FLOAT64SWAP` |
| `bcd16` | 1 | 4 BCD digits | `BCD16` |
| `bcd32` | 2 | 8 BCD digits | `BCD32` |
| `bcd32_wswap` | 2 | words swapped | `BCD32SWAP` |
| `char` | `regs` | ASCII, trailing spaces and NULs cut | `CHARSTRING` |
| `varchar` | `regs` | ASCII up to the first NUL | `VARCHARSTRING` |

- An unscaled integer (`scale` 1, `offset` 0) publishes exactly as an
  unsigned or signed integer; 64-bit values never pass through a float.
  A scaled value publishes as a float.
- `bits16`, `char` and `varchar` ignore `scale`, `offset` and `bit`
  (without an error).
- `m10k`: `lo` must be 0…9999, else the point shows `bad/device_error`.
  The signed types read both words as `i16`, as DSA does, so halves of
  mixed signs are accepted.
- An invalid BCD digit or a non-ASCII text is a point error
  (`bad/device_error`), not a value.

## 5. Reads

- Points are grouped by `(device, poll_s)`. One ticker per group; a tick
  is skipped while the group's last poll is still running (no pile-up).
- A group's reads are planned once per table and kept until an edit:
  points merge into requests of at most `max_regs` registers or `max_bits`
  bits; gaps are read too unless `contiguous_only`. There is no batch
  switch: `max_regs = 1` and `max_bits = 1` read each point alone.
- An exception reply to one request fails only the points of that request
  (`bad/device_error`, the last value kept). A timeout of every request is
  a device miss (section 8). An I/O or protocol error drops the
  connection; it reconnects.

## 6. Writes

A `~set` is a request with a reply. The value is not shown before the
device has it: after a write the point is read back, and after a failed
write too (a series of writes may have stopped part-way), so the point
shows what the device holds.

| Point | `auto` | `single` | `multiple` |
|---|---|---|---|
| coil | FC5 | FC5 | FC15 |
| holding, 1 register | FC6 | FC6 | FC16 |
| holding, more registers | FC16 | a series of FC6, lowest address first (DSA "Never") | FC16 |
| `binary` bit of a holding register | FC22 mask write; if the unit answers Illegal Function, read and FC6 from then on (remembered per unit while the connection lives) | same | same |

- The read-modify-write of a bit always sends FC6, also in `multiple` mode.
- One FC16 carries at most 123 registers. A writable `char`/`varchar`
  point with more `regs` loads and polls, but each write of it is refused
  (`regs: a value of N registers cannot be written`).
- A value outside its type's range, of the wrong kind or longer than its
  text writes nothing (`invalid_parameter`).
- In `single` mode a failure part-way names how many registers went out.
- **Unit 0 on RTU** (serial and RTU over TCP) is the broadcast address,
  which needs a request without a reply. `tokio-modbus` 0.17 always waits
  for a reply, so such a device sends nothing. It is accepted at `add`
  (the device does not know its connection's kind), then shows `Failed`
  with `broadcast (unit 0) is not supported on RTU`; a write answers the
  same.
- A write that waited behind a long action (`scan_units`) until its
  caller stopped waiting is dropped and answers `timeout`: equipment is
  never written late.
- A write to a device that does not answer, with a long `timeout_ms` and
  `retries`, and its read-back can take longer than a client waits (10 s
  by default). The client then gets `timeout`; the point still shows what
  the read-back finds. A write or action that arrives during a
  configuration change of the same connection answers `busy`: send it
  again.

## 7. Timeouts, retries and RTU timing

- Every request is bounded by `timeout_ms`. After a timeout it is sent
  again up to `retries` times; an exception or an I/O error is not
  retried. The last timeout counts as a device miss.
- **After an unanswered request the transport is reopened before the next
  request,** on every transport. On RTU a late reply would be taken for
  the next request of the same unit and function (`tokio-modbus` cannot
  drain input). On Modbus TCP its old transaction id would fail the next
  request and drop the connection. A reopened serial port first waits a
  guard (3.5 character times, at least 50 ms, plus the rest of the
  unanswered request's window), then clears its input. Each reopen counts
  in the `reopens` diagnostic.
- **The cost of a dead unit:** each of its timed-out requests costs one
  reopen. Behind a TCP gateway with few client slots, or on a serial port
  that toggles DTR on open, this can disturb the other units. Stop a dead
  device (`stop`) instead of leaving it polled.
- Bounds on whole operations: opening the connection and a ping
  `4 × timeout_ms × (1 + retries)`; a poll `timeout_ms × (1 + retries) ×
  requests + 1 s`; a write the same with its requests (one per register in
  a FC6 series, up to three for a bit), never less than the open bound.
  The 1 s covers the reopens; a poll with very many timed-out requests
  (about 20 or more) can still reach its bound. It is then cut and counts
  as a miss.
- A failed connection reconnects after `1 s × 2^n`, at most 60 s, ±20 %
  jitter, for ever. An edit of the connection closes it completely before
  the new one opens.

## 8. Quality

| What happened | Value | Quality |
|---|---|---|
| read | the value read | `good` |
| first poll of the device missed (timeout) | last value | `uncertain/stale` |
| 3 polls missed | last value; the device `Failed` | `bad/comm_fail` |
| exception reply for the point's request, or a value that does not decode | last value | `bad/device_error` |
| connection down | last value; devices `Stopped by Parent` | `bad/disconnected` |
| slave: the tree's value does not fit the point after an edit | last value | `bad/config_error` |
| the next good read | the value read | `good` |

**There is no "zero on failed poll"** (DSA writes 0, false or "" when a
poll fails). A made-up value at good quality cannot be told from a real
one. Here the last value stays and its quality says that it is old. A
consumer checks the quality first: a flow or a display that needs a value
it can act on treats `uncertain/*` as "may be old" and `bad/*` as "do not
use", and acts on its own fallback (an alarm, a safe default) if it needs
one.

`republish_s` is a heartbeat: a value read again unchanged is published
again once its last publish is that old. It follows reads, so a device
that does not answer is never republished as good.

## 9. RS485 advice

- Set `retries = 1`: one lost frame on a noisy line then does not make the
  points stale.
- Give each unit a `timeout_ms` that fits the slowest device on the line;
  the whole line waits for it.
- Stop devices that are gone (section 7).
- `serial_slave` must be the only slave on its line (section 13).

## 10. Folders, copy, export, import

### Folders

- `add_folder {name}` on a device or folder. Folders nest at most 4 deep
  below the device. They have no params and no `edit` (no rename: ids are
  keys of history watches, ACL rules and flows; `copy` and `remove` move a
  branch).
- A point id is unique on its device, in every folder. Its key gains the
  folder path; polls and writes do not see folders.
- A folder may not take the name `status` or `error`, a diagnostics leaf
  name (section 12) or an action name.
- `remove` of a folder removes everything in it, stops its polling and
  removes it from the stored tree.
- **A stored tree with a wrong folder structure stops the link from
  starting** (a point id twice on a device, folders deeper than 4, an
  unknown key in a folder, an invalid name). This is unlike a node whose
  params fail: that node stays, `Failed`, and can be edited.

### Copy

`copy {name}` on a connection, device, folder or point puts a deep copy
beside the source.

- A copied connection or device starts stopped: it does not poll a device
  twice, and a copied slave does not take its port.
- A folder copy gives its points new ids `<id>_<n>` and replies with the
  `renamed` map (flows and history that name copied ids need it).
- A copy keeps the sealed secrets (the destination is the same).

### Export and import

`export` on a connection, device or folder replies `{json}`:

```json
{"format": "wyrm-driver-branch/1", "driver": "modbus", "kind": "device",
 "name": "ahu1", "params": {…}, "enabled": true, "children": [ … ]}
```

- Secrets are never exported: a secret with a value is `"<not exported>"`.
- `import {json, name?, overwrite?}`: a connection branch at the root, a
  device branch on a connection, a folder branch on a device or folder.
  `name` renames the top node; `overwrite: true` replaces a node of that
  name. It replies `{name, reenter}`: `reenter` lists the secrets to enter
  again with `edit` (an import never takes secrets from the text).
  Overwrite keeps a stored secret while the node's destination fields stay
  the same.
- An imported connection or device starts stopped. A folder imported into
  a running device is polled at once (folders have no stop).
- Bounds: 4 MiB of text, 5000 nodes, 60 s per call. The text is checked
  like `add_*` before anything changes.
- The file format is JSON (`serde_json`), as the storage export of ADR
  0017: a user file, not the wire codec (principle 5 keeps CBOR on the
  wire).

## 11. Import from DSA (`import_dsa`)

`import_dsa {json, name?}` at the link root takes the `nodes.json` of
`dslink-java-modbus` (commit `0745d7d`), or the DSA export of one
connection (then `name` is required). Every connection is checked before
the first one is imported; each imports stopped (start it after you read
the report).

### The report

| Key | Holds |
|---|---|
| `created` | the connections imported |
| `reenter` | secrets to enter again (none in DSA Modbus) |
| `dropped` | `[{path, field, reason}]`: what is not carried, or not as it was (with what was set instead) |
| `disabled` | `[{path, reason}]`: nodes imported stopped that would only fail as they are |
| `renamed` | `[{from, to}]`: names changed |

### What is converted

| DSA | Ours |
|---|---|
| `scaling`, `scaling offset`, `offset` | `scale = 1 / scaling`, `offset = scaling offset`, `addr = offset` (section 1) |
| `polling interval` of a device (**ms**) | `poll_s` of each of its points (10 ms…24 h) |
| `suppress non-cov update duration` (**ms**) | `republish_s`; missing: 60 s; 0 (publish on every poll): half the interval; at most 3600 s |
| `Timeout` (**ms**), `retries` | `timeout_ms` (100…10000), `retries` (0…5) |
| `use multiple write commands` Always / Never / As Appropriate | `write_mode` `multiple` / `single` / `auto` |
| `max read register count`, `max read bit count` (connection) | `max_regs`, `max_bits` (each device) |
| `use batch polling` false | `max_regs = 1`, `max_bits = 1` |
| data types | section 4 |
| folders | folders; deeper than 4 go into the deepest |
| two-tier IP devices (no connection node) | one connection per host and port; the first device's connection attributes win, and the differing ones of the others are reported |

- **Units are ms.** `polling interval`, `suppress non-cov update duration`
  and `Timeout` are stored in ms by DSA.
- **Missing attributes** get the defaults DSA restores with, not ours:
  `Timeout` 500 ms, `retries` 2, `contiguous batch requests only` true,
  `use batch polling` true; each is reported. A new connection made here
  has `timeout_ms` 1000 and `retries` 0.
- **Not imported, reported in `dropped` with the connection's devices:**
  UDP and ASCII transports, parity MARK and SPACE, 1.5 stop bits (section
  14). No node is made, so a `start` cannot run them on another framing.
- **Not carried, reported in `dropped`:** `zero on failed poll` set
  (section 8), `discard data delay` above 0, `max write register count`
  (one write carries up to 123 registers), values outside our bounds
  (clamped), local slaves ("setup local slave": add an `ip_slave` by
  hand), nodes DSA itself does not load.
- **Imported stopped, reported in `disabled`:** a serial connection whose
  port is not a serial device path on this host (`COM3` on Linux or
  macOS): `edit` its `serial_port`, then `start`; a device with unit 0 on a
  serial connection (section 6).
- **Names:** characters outside `[A-Za-z0-9_.-]` become `_`; a reserved
  name (`status`, `error`, a diagnostics leaf, an action name) or a taken
  one gets `_2`, `_3`, …; each change is in `renamed`.
- **A name clash refuses the whole import** (a connection of that name
  exists): remove it, or give `name` for a one-connection file.
- **A failure while saving** (a full disk) after some connections were
  imported leaves those connections imported; the error does not list
  them. Look at the tree before you run the import again.

## 12. Diagnostics and commissioning

### Diagnostics

Each connection and each device has the value leaves `requests`, `errors`,
`timeouts`, `exceptions`, `reopens`, `last_rtt_ms` and `avg_rtt_ms`
(moving average, α = 0.1). Every request sent counts, a retry too.

- A leaf is published when it changes, at most once every 10 s, and at
  once when someone reads the node (its `~meta` or a leaf's).
- A connection's counts start at 0 when it starts or restarts, a device's
  on its own `start` and `restart`. A reconnect after a failure keeps
  them.
- They are ordinary values: the historian can watch them.

### Commissioning actions (master connections)

| Action | Node | Level | Args | Reply |
|---|---|---|---|---|
| `read_registers` | device | read | `table`, `addr`, `count` (1…125, default 1), `dtype` (optional) | `{words}` or `{bits}`; with `dtype` also `value`, decoded from the first registers and unscaled (or `error`) |
| `read_device_id` | device | read | | FC43/14 basic objects, and the regular ones when the device's conformity level has them: `{vendor_name, product_code, revision, vendor_url, product_name, model_name, user_application_name}` (others as `object_<id>`) |
| `scan_units` | connection | config | `from` (default 1), `to` (default 247), `timeout_ms` (20…1000, default 200) | the unit ids that answer |

- The actions run on the connection's owner task, between polls, one
  request at a time. `read_registers` and `read_device_id` send each
  request once at the connection's `timeout_ms`; the action is bounded by
  12 s. A device that does not support FC43 answers `not_supported`.
  An action that finds the connection's queue full answers `busy`.
- `scan_units` sends one read of holding register 0 per unit. Any reply,
  an exception too, counts as an answer, except a gateway's "target did
  not respond" or "path unavailable". A transport error stops the scan
  (`disconnected`, naming the units found so far). Unit 0 is skipped on
  RTU. A scan whose worst case is above 165 s is refused: scan a smaller
  range or use a shorter `timeout_ms`.
- **A scan pauses the polling of its connection** for its whole run:
  about 62 s for 247 silent units at the defaults (up to 165 s). Point
  values stay `good` but are not refreshed, and they do not go stale.
  Writes wait too (section 6).
- **A scan shows in the diagnostics:** a full scan of a silent range adds
  about one timeout and one reopen per silent unit (about 245 for the
  default range). That is the scan, not a failing bus.

## 13. Slave mode

An `ip_slave` (Modbus TCP) or `serial_slave` (RTU) connection serves its
devices to masters. A device is a unit id served; a point is a view on the
served coils, discrete inputs, input or holding registers of its unit
(devices with the same unit, and overlapping points, share them).

### Values

- A point's value comes from the tree: every point takes `~set` (level
  write), input registers and discrete inputs too. What a master reads is
  the value after its encoding (data type, `scale`, `offset`).
- A master may write a point with `writable_by_master` (coil and holding
  only). The written value is published as the point's new value. The
  write is logged at info by point (never the value) and counted in the
  diagnostics; it is not in the site's audit trail (no WYRM caller).
- Tree sets and master requests go through one queue, so the last writer
  wins and the published value is what the next master read returns.
- **A point the tree never set has no value.** Nothing is published for
  it, and a master read that touches it answers exception 4 (server device
  failure), never a made-up 0. The served values live in memory: a fresh
  link process serves nothing until the tree sets values.
- **A register of flags** (`binary` points with different `bit` on one
  register): each bit is known when its point is set. A master read of
  that register answers exception 4 until every flag point on it is set;
  bits that no point reads are served as 0. A word view of a register
  needs all 16 bits.
- A point edited to another data type gets the tree's last value again;
  when that value does not fit (50000 for an `i16`), the point serves
  nothing and shows its old value as `bad/config_error` until it is set
  again.

### Answers

| Request | Answer |
|---|---|
| an address no point covers | exception 2 (illegal data address) |
| a write touching a point without `writable_by_master` | exception 3 (illegal data value) |
| a write that a point it touches cannot decode (invalid BCD, non-ASCII text, `m10k` low word ≥ 10000) or that makes a float NaN or infinite | exception 3; nothing changes |
| more registers or bits than one request carries | exception 3 |
| a read touching a point without a value | exception 4 |
| FC22 on a register whose points' bits are not all known | exception 4 |
| FC8, FC17, FC23, FC43 and every function code but FC1–6, 15, 16 and 22 | exception 1 (illegal function) |
| a unit no device serves | TCP: exception 0x0B (gateway target failed to respond); RTU: no reply (another slave may have it) |
| the queue is full, or the answer takes more than 1 s | TCP: exception 6 (busy); RTU: no reply. The request is never applied late. |
| RTU broadcast (unit 0) write | applied to every served unit that takes it, no reply; counted once on the connection |
| RTU broadcast read | ignored |

- **Many TCP masters send unit 255 or 0** by default. They get 0x0B unless
  a device has that unit: add a device with `unit` 255 (or 0), or set the
  master's unit id. Unit 0 is refused under `serial_slave` (it is the
  broadcast).

### Exposure

- **Modbus has no authentication.** Anyone who reaches the port reads
  every served value and writes every point with `writable_by_master`.
- `listen_host` is `127.0.0.1` by default. Another address is allowed:
  the link logs a warning at `warn` when the listener opens and shows it
  as `attr.warning` on the connection's `status` leaf. Open the port only
  to the network of the masters (firewall, VLAN).
- `ip_slave` listens on every address the host name resolves to
  (`localhost`: `::1` and `127.0.0.1`). An address the host lacks, or an
  address family it lacks (IPv6 turned off), is left out; no address left
  is an error. Any other bind error fails the connection: a port in use
  (after 1.5 s of retries), or no permission.
- **Port 502 needs privileges on Linux** (ports below 1024): the
  connection shows `Failed` with "Permission denied". Use a port above
  1023 (for example 1502) and point the master there, or give the binary
  `CAP_NET_BIND_SERVICE`.
- **`serial_slave` must be the only slave on its line** (point to point
  to one master). The `tokio-modbus` 0.17 RTU server reads every frame on
  the line as a request; other slaves' replies on a shared RS485 bus end
  it, and the connection fails and reopens after backoff, losing the
  masters' requests meanwhile.
- A copy or import of a slave connection starts stopped, so two slaves
  never fight for a port.

## 14. Not supported, and why

| What | Why | Instead |
|---|---|---|
| Modbus ASCII, Modbus UDP | `tokio-modbus` has neither; rare in the field | a gateway to TCP or RTU |
| parity MARK and SPACE, 1.5 stop bits | the serial library lacks them | |
| `rename` | ids are keys: history watches, ACL rules and flows would break | `copy`, then `remove` |
| "zero on failed poll" | a dishonest value at good quality | the quality ladder (section 8) |
| a batch polling switch | | `max_regs = 1`, `max_bits = 1` |
| RTU broadcast writes from a master (unit 0) | `tokio-modbus` 0.17 always waits for a reply | write each unit |
| `serial_slave` on a shared RS485 bus | the RTU server decoder (section 13) | one slave per line |
| `discard data delay`, `max write register count` (DSA) | reopen and guard after a timeout (section 7); one write carries up to 123 registers | |
| local slave over UDP (DSA) | no UDP | `ip_slave` |

## 15. Better than DSA

What the DSA link (`dslink-java-modbus`, commit `0745d7d`) does wrong and
this link does not. These come from reading the DSA source, not from
running it.

- **Rights:** every DSA action is at `READ`, so a read-only user can add,
  edit and remove connections. Here a tree change needs `config`.
- **Reconnects:** a DSA connection that fails at link start is never
  retried, and a serial one reconnects once only. Here a connection
  retries for ever with capped, jittered backoff.
- **Bit writes:** DSA writes a bit in a register without FC22 or a
  read-modify-write, so it overwrites the other bits. Here: FC22, or read
  and FC6.
- **Inverse scaling on write:** DSA writes `v × scaling − scaling offset`,
  which is not the inverse of its read when the offset is not 0. Here a
  write is the exact inverse of the read.
- **Writes:** DSA writes fire and forget (an error goes only to the log)
  and the node shows the new value even when the write fails. Here a write
  has a reply and the point shows what the device holds.
- **Non-batch polling:** in DSA one missing point ends the poll cycle for
  every point after it. Here each point is its own request.
- **Bad config:** DSA silently deletes a node with incomplete attributes
  at start, and a failed add or edit only logs. Here a node that fails
  validation stays `Failed` and editable, and a refused add or edit
  answers `invalid_parameter` naming the field.
- **Edits:** a DSA connection edit always stops and restores, even without
  a change, and does not validate. Here an edit is checked first, does
  nothing when nothing changed, and closes the old connection before the
  new one opens.
- **Storage:** DSA keeps node attributes in plain `nodes.json`. Here the
  tree is sealed (ChaCha20-Poly1305) in the link's `data_dir`.
- **Request order:** DSA writes go outside its master lock. Here one owner
  task per connection sends every request in order.
- **Late replies:** after a timeout DSA can take a late reply for the
  next request; here the transport is reopened (section 7).
- **Quality:** DSA's "zero on failed poll" publishes invented values; here
  the quality ladder tells the truth (section 8).
- **Integers:** DSA passes every value through `double`, so a `UINT64`
  above 2^53 loses precision. Here unscaled integers are exact.
- **DSA local slave:** a write from a master after a link restart throws
  (the address map is not restored), an edit changes the listener only
  when the transport changes (not the port), a holding write takes one
  register as a raw `short`, and a UDP listener is made again for each
  slave on the same port. Here the slave mode serves the tree's values in
  one order with the tree's sets (section 13).

## 16. Test without hardware

- `wyrm-modbus-sim` (`cargo run -p wyrm-link-modbus --features bin --bin
  wyrm-modbus-sim -- --listen 127.0.0.1:5020`): a Modbus TCP device with
  1000 coils, discrete inputs, input and holding registers (all 0 at
  start), FC1–6, 15, 16, 17, 22 and 43/14. The demo's edge site runs one
  for its link `plc1`.
- The probe scenario `modbus` (`links/probe/scenarios/modbus.json`) runs on
  every site with `plc1/line1` and skips the others (a site whose `plc1`
  is not connected skips it too): `wyr probe modbus --gateway
  http://127.0.0.1:8444 --site edge`.
- The driver is tested against this simulator only. It is not yet
  verified against `diagslave` or a real device.
