# KNX link

The `knx` link reads and writes the group addresses of a KNX installation
(lighting, blinds, heating, room controllers, meters) over KNXnet/IP. It
runs on the driver framework (ADR 0004), so connections, devices and points
have the same actions, states and quality as every framework link
([`docs/links.md`](links.md)).

Code: `links/knx` (`wyrm-link-knx`). The codec is in the crate: KNXnet/IP
frames (`src/proto.rs`), cEMI L_Data telegrams (`src/cemi.rs`) and the
datapoint types (`src/dpt.rs`).

## 1. Run it

| Mode | How |
|---|---|
| Built in | *Install Link ▸ from Driver*, driver `knx`; or `wyrmd link knx` as a process link. |
| Package | `knx` (`wyr link pack --manifest-path links/knx/Cargo.toml`), binary `wyrm-link-knx`. |

## 2. Tree

```
<connection>            a tunnel to one KNXnet/IP interface, or the routing multicast group
  <device>              a group of points for people (a room, a line, a function)
    [<folder>/…]        up to 4 folders deep
      <point>           one group address with a datapoint type
```

KNX sends values to group addresses, not to devices. So a device node of
this link is only a group of points. Its `individual_address` is a label.
The link never sends a telegram to an individual address.

The framework adds to each connection and device the `status` and `error`
leaves and the actions `add_*`, `edit`, `remove`, `restart`, `stop`/`start`,
`copy`, `export` and `import`.

## 3. Parameters

### Tunnel connection (`add_tunnel_connection`)

KNXnet/IP tunnelling over UDP to one interface or IP router. One tunnel
takes one of the interface's tunnelling slots (most interfaces have 1 to 5).

| Param | Default | Bounds | Meaning |
|---|---|---|---|
| `host` | required | name or IPv4 address | The KNXnet/IP interface. |
| `port` | `3671` | 1–65535 | Its UDP port. |
| `nat` | `false` | | NAT mode: the link sends `0.0.0.0:0` as its endpoints, and the interface answers to the address the datagrams come from. Set it when the interface is behind address translation. |
| `timeout_ms` | `3000` | 100–30000 | Bound on the connect answer, on the confirmation of a telegram and on the answer to a read. |
| `heartbeat_s` | `60` | 1–60 | Period of the connection state request. KNXnet/IP says 60. |
| `rate_per_s` | `20` | 1–100 | Telegrams the link sends per second at most. A twisted-pair line carries about 25. |

### Routing connection (`add_routing_connection`)

KNXnet/IP routing: the link is a member of the multicast group, like a KNX
IP device. No interface slot is used and there is no connection to lose.

| Param | Default | Bounds | Meaning |
|---|---|---|---|
| `group` | `224.0.23.12` | multicast IPv4 address | The routing multicast address of the installation. |
| `port` | `3671` | 1–65535 | The UDP port. |
| `interface` | empty | IPv4 address | Address of this host on the KNX network: the interface that joins the group and sends. Empty = the system decides. Set it on a host with more than one network. |
| `individual_address` | `15.15.255` | `area.line.device` | The source address of the link's telegrams. Give it a free address of the IP line. |
| `timeout_ms` | `3000` | 100–30000 | Bound on the answer to a read. |
| `rate_per_s` | `20` | 1–50 | Telegrams the link sends per second at most. KNXnet/IP routing allows 50. |
| `ttl` | `16` | 1–255 | Multicast TTL of the datagrams. |

### Device (`add_device`)

| Param | Default | Bounds | Meaning |
|---|---|---|---|
| `individual_address` | empty | `area.line.device` | A label for people (the device the points belong to). Not used on the bus. |

### Point (`add_point`)

| Param | Default | Bounds | Meaning |
|---|---|---|---|
| `address` | required | see below | The group address. |
| `dpt` | required | see section 4 | The datapoint type: `9.001`, `9`, `DPST-9-1` or `DPT-9`. |
| `read_on_start` | `false` | | Send a GroupValue_Read when the connection opens. |
| `poll_s` | `0` | 0, or 1–86400 | Send a GroupValue_Read this often. 0 = only listen. |
| `writable` | `false` | | The point takes `~set`. |
| `unit` | empty | | Unit of the value. Empty = the unit of the datapoint type. |

A group address is written in one of three forms. All three name the same
16 bits: `1/2/3`, `1/515` and `2563` are one address.

| Form | Parts |
|---|---|
| `1/2/3` | main 0–31, middle 0–7, sub 0–255 |
| `1/515` | main 0–31, sub 0–2047 |
| `2563` | 1–65535 |

`0/0/0` is refused: it is the broadcast address.

## 4. Datapoint types

| DPT | Octets | Value in the tree |
|---|---|---|
| 1.x | 1 bit | bool |
| 2.x | 2 bits | number 0–3: bit 1 = control, bit 0 = value |
| 3.x | 4 bits | number −7…7: the sign is the direction (plus = increase, up), the size is the step code, 0 = stop |
| 5.x | 1 | number 0–255; 5.001 scaled to 0–100 %, 5.003 to 0–360° |
| 6.x | 1 | number −128…127 |
| 7.x | 2 | number 0–65535; 7.003 and 7.004 in ms (×10, ×100) |
| 8.x | 2 | number −32768…32767; 8.003 and 8.004 in ms, 8.010 in % (×0.01) |
| 9.x | 2 | number, KNX 2-octet float (−671088.64…670433.28, resolution from 0.01) |
| 10.x | 3 | text `HH:MM:SS`, or with the day `Mon HH:MM:SS` |
| 11.x | 3 | text `YYYY-MM-DD` (1990–2089) |
| 12.x | 4 | number 0–4294967295 |
| 13.x | 4 | number, signed 32 bits; 13.002 in m³/h (×0.0001) |
| 14.x | 4 | number, IEEE 754 single |
| 16.x | 14 | text of at most 14 characters: 16.000 ASCII, 16.001 ISO 8859-1 |
| 17.x | 1 | number 0–63 (scene; the bus counts scenes from 0) |
| 18.x | 1 | number 0–63 to call a scene, 128–191 to learn it |
| 19.x | 8 | text `YYYY-MM-DDTHH:MM:SS` (1900–2155) |
| 20.x | 1 | number 0–255; 20.102 is an enum: Auto, Comfort, Standby, Economy, Building Protection |
| 232.600 | 3 | text `#RRGGBB` |
| any other | 1–14 | the raw octets (binary; a write also takes text of hex digits) |

- The unit of a point comes from the subtype where the table of the link
  has it (9.001 °C, 9.004 lx, 5.001 %, 13.013 kWh, 14.056 W, …). Set `unit`
  for any other. Every unit and scale in the table was checked against the
  KNX standard (System Specifications, Interworking, Datapoint Types,
  v02.02.01). A subtype that is not in the table shows no unit and the raw
  number.
- A telegram of 6 bits (the form of DPT 1, 2 and 3) is refused by a point
  of any other known type, also a one-octet type: the point is
  `bad/device_error`.
- DPT 9 never sends `0x7FFF`: a value that would encode as it (above
  670433.28) is refused.
- A telegram whose length does not fit the type makes the point
  `bad/device_error` and keeps the last value. The next telegram that fits
  makes it good again.
- DPT 9 value `0x7FFF` and a DPT 19 with the fault flag are "invalid data":
  the same point error.
- A type the link does not know is sent as whole octets after the APCI. To
  send a value of 6 bits or less, use DPT 1, 2 or 3.

## 5. Values, reads and writes

**Values are events.** The connection listens all the time. A point takes
the value of every GroupValue_Write and GroupValue_Response sent to its
address, by any device. No telegram is sent for that. The tree is updated
within 200 ms.

- A telegram that repeats the value the point already has does not publish a
  new sample. `recent_telegrams` shows every telegram.
- A point has no value until a telegram for its address comes. Set
  `read_on_start` when the value must be there after a start.

**Reads** are sent only where a point asks for them:

| Param | The link sends a GroupValue_Read |
|---|---|
| `read_on_start` | once per address when the connection opens (again after a reconnect) |
| `poll_s` | every `poll_s` seconds |

Reads leave one at a time, at most `rate_per_s` per second, so the reads of
a start are spread over time: 500 points at 20 per second take 25 seconds.
A device answers a read only when the group object has the *read* flag in
ETS. Set it on one device per group address.

**Writes.** A `~set` on a writable point sends one GroupValue_Write. The
point takes the new value only when the telegram is on the bus:

| Connection | The telegram is on the bus when |
|---|---|
| Tunnel | the interface confirms it (L_Data.con). A confirmation with the error flag (no device acknowledged the telegram) refuses the write. |
| Routing | the datagram left. KNXnet/IP routing has no confirmation. |

Writes and one-shot reads go before the reads that `read_on_start` and
`poll_s` queue.

## 6. Errors and quality

| What happens | Result |
|---|---|
| A read gets no answer within `timeout_ms` | The point is `uncertain/stale` after the first, `bad/comm_fail` after three in a row. The last value is kept. A `read_on_start` read is sent three times, then not again. |
| A telegram for the address comes (from any device) | The point is `good` again. |
| No point of a device has a value and its reads get no answer | The device is `Failed` with `no answer to GroupValue_Read <address>`. The first telegram for one of its points makes it `Connected`. |
| A telegram does not fit the point's type | `bad/device_error`, last value kept. |
| The interface does not acknowledge a tunnelling request (1 s, one repeat) | The tunnel is closed and opened again (framework backoff, 1 s to 60 s). |
| Three connection state requests get no answer, or the interface sends a disconnect | The same. |
| The interface refuses the tunnel | The connection is `Failed`; `error` says why, for example `all tunnels of the interface are in use`. The link tries again with backoff. |
| The connection is down | Devices are `Stopped by Parent`, points `bad/disconnected`. |

After a reconnect a point that only listens stays `bad/disconnected` until
its next telegram: the link cannot know what it missed. Points with
`read_on_start` are read again.

Statuses of `~set` and of the actions:

| Status | When |
|---|---|
| `not_supported` | `~set` on a point that is not writable. |
| `invalid_parameter` | The value does not fit the datapoint type; an address or type that does not parse; the bus did not acknowledge the telegram. |
| `timeout` | No confirmation from the interface; no answer to a read. |
| `disconnected` | The connection is down or broke during the request. |
| `busy` | Another action runs on the connection. |

## 7. Actions

| Node | Action | Level | What it does |
|---|---|---|---|
| connection | `search_gateways {address?, wait_ms = 3000}` | config | Sends a SEARCH_REQUEST and lists the KNXnet/IP interfaces that answer: `name`, `address`, `medium`, `individual_address`, `serial`, `mac`. Without `address` it asks the connection's own network: the multicast group of a routing connection, the interface of a tunnel. With `address` it asks that host or group (`224.0.23.12`). |
| connection | `recent_telegrams {max = 100}` | config | The last telegrams seen and sent (the link keeps 500 per connection): `time` (µs), `sent`, `source`, `destination`, `service`, `data`, `acknowledged`. |
| connection | `connection_info` | read | The link's individual address, the peer, and for routing the counts of lost-message and busy signals. |
| device | `read_group {address, dpt}` | config | Sends one GroupValue_Read and returns the answer: `value`, `dpt`, `unit`, `data`. |
| device | `write_group {address, dpt, value}` | config | Sends one GroupValue_Write to any group address. |
| device | `import_ets {csv \| file, folder = ets, read_on_start, writable, overwrite}` | config | Section 8. |
| point | `read` | read | Sends a GroupValue_Read for the point's address now and returns the answer. |

Why these levels:

- A device is only a label in KNX. So `read_group` and `write_group` are
  not bound to the points of their device: they reach **any** group address
  of the bus, with any type, and send a telegram to it. `write_group` also
  goes past the `writable` flag of every point. Both need `config`, like the
  commissioning actions of the other links (walk, browse, list objects).
- `recent_telegrams` shows what every device of the installation said, also
  for addresses that are no point. It needs `config`.
- `search_gateways` sends datagrams to an address the caller names, so it
  needs `config`.
- A point's `read` sends a GroupValue_Read to that point's own address. A
  read does not change a value on the bus and the caller may read the point
  anyway, so `read` is enough. `connection_info` shows the link's own
  address and counters: `read`.
- A token with `read` reads values from the points. A token with `write`
  changes values through the `~set` of a writable point only.

No action holds the connection while it waits for the bus. The link sends
the telegram and waits for the answer beside the connection, so the tree
goes on taking telegrams and no point changes its quality. One action runs
on a connection at a time; a second one answers `busy`. A `~set` waits for
its confirmation (at most 1 s for the acknowledge, one repeat, then
`timeout_ms`); the telegrams that come meanwhile are kept and published when
the set has its answer, and no point goes stale for the wait.

A routing connection opens without an interface. To look for interfaces
before a tunnel exists, add a routing connection and run `search_gateways`
on it.

## 8. Import from ETS

`import_ets` on a device reads the group address export of ETS and makes a
folder of points.

1. In ETS, open the *Group Addresses* view.
2. Export the group addresses as CSV. Every format ETS offers is read:
   one name column or three, tab, semicolon or comma, with or without the
   header row, quoted or not.
3. Run `import_ets` on the device. Give the text as `csv`, or the file as
   `file`.

| Argument | Default | Meaning |
|---|---|---|
| `csv` | | The export as text. |
| `file` | | The export as a file (UTF-8, else read as ISO 8859-1). Give `csv` or `file`, not both. |
| `folder` | `ets` | The folder the main groups go into. |
| `read_on_start` | `false` | Every imported point reads its value when the connection opens. |
| `writable` | `false` | Every imported point takes `~set`. |
| `overwrite` | `false` | Replace a folder of that name with everything in it. |

The result:

```
<device>/ets/1_lighting/0_ground_floor/ga_1_0_1     name: "Kitchen light", dpt 1.001
```

- A main or middle group becomes a folder: its number, then its name in
  lower-case ASCII (`1_lighting`). A group address becomes a point
  `ga_<address>`. The name from ETS is the point's name for people.
- The datapoint type comes from the `DatapointType` column (`DPST-9-1`,
  `DPT-9`). A row without a type is left out and listed in `without_type`
  of the reply: the link cannot read a value without its type. Set the
  types in ETS and import again with `overwrite`.
- An address that comes twice is taken once (`repeated` in the reply).
- The address of a row is the first cell written with `/` (`1/0/1`). A
  group whose name is a number (`100`) is not taken for an address. In an
  export with free addresses (plain numbers) the address is the number after
  the name.
- Everything is checked before anything changes. A point id is unique on a
  device, so a second import of the same export needs another device or
  `overwrite`.
- Bounds: the text or file at most 4 MiB (`out_of_range` beyond), 20 000
  rows, 4096 octets per cell, 5000 nodes (folders and points).

The framework's `export` and `import` (format `wyrm-driver-branch/1`) and
`copy` work on KNX connections, devices and folders as on every framework
link.

## 9. Simulator

`wyrm-knx-sim` is a KNXnet/IP tunnelling server over a small table of group
addresses. It answers search requests, confirms writes, answers reads of
the addresses it holds and sends a temperature once per second.

```bash
cargo run -p wyrm-link-knx --features bin --bin wyrm-knx-sim -- --listen 127.0.0.1:13671
```

| Address | DPT | Behaviour |
|---|---|---|
| `1/0/1` | 9.001 | Moves between 18 and 26 °C, sent every second. |
| `1/1/1` | 1.001 | Holds what is written. |
| `1/1/2` | 5.001 | Holds what is written. |
| `1/2/1` | 20.102 | Holds what is written. |

A link for it:

```json5
knx: {
  driver: "knx",
  params: { connections: { sim: {
    kind: "tunnel_connection", host: "127.0.0.1", port: 13671,
    devices: { room: { points: {
      temp: { address: "1/0/1", dpt: "9.001" },
      light: { address: "1/1/1", dpt: "1.001", writable: true, read_on_start: true },
    } } },
  } } },
}
```

The tests (`links/knx/tests/sim.rs`) use the same simulator in process
(`wyrm_link_knx::sim`, feature `sim`): a tunnelling server (`spawn`) and a
routing node (`spawn_router`), with failures on request (no answers, no
acknowledge, no confirmation, a negative confirmation, a refused connect,
reads without an answer, a disconnect by the gateway, routing busy and
lost-message signals).

## 10. Known limits

The link does not do these things:

- **KNX IP Secure and KNX Data Secure.** A secured tunnel, a secured
  routing backbone or a secured group address cannot be used. Use an
  interface or a line without security, or keep the link off that
  installation.
- KNXnet/IP over TCP (core v2) and tunnelling to a specific individual
  address (extended connection request).
- The bus monitor layer. `recent_telegrams` shows group telegrams and marks
  other telegrams as `other`, without decoding them.
- Device management: programming, individual addresses, properties, memory.
- Answering a GroupValue_Read of another device. The link is a client. No
  point has a *respond* flag.
- Extended frames: a value longer than 14 octets.
- KNX USB, TP-UART and other serial interfaces. An IP interface or an IP
  router is needed.
- More than one tunnel per connection, and fail-over between interfaces.

Behaviour to know:

- The link was tested against its simulator only. It was not yet run
  against KNX hardware.
- A routing connection takes every routing datagram that reaches its UDP
  port (3671), multicast or sent to the host directly, from any sender:
  KNXnet/IP routing has no sender check, and KNX IP Secure is not
  supported. Any host that can send to that port can set the value the tree
  shows for a group address. Keep the KNX IP network apart from other
  networks, or use a tunnel connection: a tunnel takes datagrams from its
  interface's address only.
- Multicast must reach the host for a routing connection: the switch (IGMP
  snooping) and a container's network mode decide that. In a container, use
  host networking or a tunnel connection.
- A repeated telegram with the same value publishes no new sample. A flow
  that must see every press of a button reads `recent_telegrams`, or the
  button sends alternating values.
- DPT 2, 3 and 18 are numbers, not maps: see section 4 for their bits.
- Only 20.102 has value names. Every other 20.x subtype is a number.
- There are no diagnostics counters (`requests`, `errors`, …) on KNX nodes.
