# BACnet link

The `bacnet` link reads and writes BACnet/IP devices: controllers, chillers,
air handling units, lighting and energy meters in buildings. It runs on the
driver framework (ADR 0004), so connections, devices and points have the
same actions, states and quality as every framework link
([`docs/links.md`](links.md)).

Code: `links/bacnet` (`wyrm-link-bacnet`). The BACnet codec (BVLC, NPDU,
APDU, application tags) is in the crate (`src/codec.rs`): no maintained
async BACnet crate with a fitting licence covers this.

## 1. Run it

| Mode | How |
|---|---|
| Built in | *Install Link ▸ from Driver*, driver `bacnet`; or `wyrmd link bacnet` as a process link. |
| Package | `bacnet` (`wyr link pack --manifest-path links/bacnet/Cargo.toml`), binary `wyrm-link-bacnet`. |

## 2. Tree

```
<connection>            a BACnet/IP port (one UDP socket)
  <device>              a BACnet device (device instance)
    <point>             one property of one object
```

The framework adds to each connection and device the `status` and `error`
leaves, the actions `add_*`, `edit`, `remove`, `restart`, `stop`/`start`,
`copy`, `export`, `import` and the diagnostics leaves (section 8).

## 3. Parameters

### Connection (`add_connection`)

| Param | Default | Bounds | Meaning |
|---|---|---|---|
| `bind_host` | `0.0.0.0` | IPv4 address | Local address of the UDP socket. |
| `bind_port` | `47808` | 0–65535 | Local UDP port (0 = any). |
| `broadcast` | `255.255.255.255:47808` | IPv4[:port] | Where Who-Is goes (the subnet's broadcast address), when no BBMD is set. |
| `bbmd` | empty | IPv4[:port] | Register as a foreign device at this BBMD. Empty = no registration. |
| `bbmd_ttl_s` | `300` | 30–65535 | Time to live of the registration. The link renews it at half of it. |
| `apdu_timeout_ms` | `3000` | 100–60000 | Bound on each confirmed request. |
| `apdu_retries` | `1` | 0–5 | Repeats of a request after a timeout (not after an error reply). |
| `max_apdu` | `1476` | 50–1476 | The largest reply the link accepts. |

### Device (`add_device`)

| Param | Default | Bounds | Meaning |
|---|---|---|---|
| `instance` | required | 0–4194302 | Device instance. |
| `address` | empty | IPv4[:port] | Address of the device, or of its BACnet router. Empty = find the device by Who-Is. Port default 47808. |
| `network` | `0` | 0–65534 | Network number of a device behind a BACnet router (MS/TP behind an IP router). 0 = on this IP network. Needs `address` and `mac`. |
| `mac` | empty | 1–7 hex octets | MAC address of the device on that network (MS/TP: one octet, `0A`). |
| `use_rpm` | `true` | | Read with ReadPropertyMultiple. `false` = ReadProperty per property. |
| `max_apdu` | `0` | 0 or 50–1476 | Largest APDU the device takes. 0 = from its I-Am (480 if it does not answer Who-Is). |
| `ping_s` | `10` | 0–3600 | Ping period. 0 = no ping. |
| `republish_s` | `0` | 0–3600 | Publish unchanged values again after this long. 0 = on change only. |

### Point (`add_point`)

| Param | Default | Bounds | Meaning |
|---|---|---|---|
| `object_type` | required | see below | Object type. |
| `instance` | required | 0–4194303 | Object instance (4194303 = the device object's wildcard). |
| `property` | `present_value` | see below | Property to read. |
| `property_id` | `0` | 0–4194303 | Property identifier, only with `property = other`. |
| `array_index` | `-1` | -1–4294967294 | Array index; -1 = the whole property. Index 0 is the array length. |
| `dtype` | `auto` | see section 4 | Type of the value. |
| `check_status` | `true` | | Read `status-flags` beside `present_value` (section 6). |
| `poll_s` | `5` | 0.05–86400 | Poll period. |
| `scale`, `offset` | `1`, `0` | scale ≠ 0 | Read: `value × scale + offset`. Write: the reverse. Numbers only. |
| `writable` | `false` | | The point takes `~set` (level write). |
| `priority` | `16` | 1–16 | Write priority (1 is the highest). |
| `unit` | empty | | Unit shown in `~meta`. `list_objects` suggests one per object. |

Object types: `analog_input`, `analog_output`, `analog_value`,
`binary_input`, `binary_output`, `binary_value`, `multi_state_input`,
`multi_state_output`, `multi_state_value`, `accumulator`,
`pulse_converter`, `integer_value`, `positive_integer_value`,
`large_analog_value`, `characterstring_value`, `loop`, `averaging`,
`calendar`, `command`, `schedule`, `device`.

Properties: `present_value`, `status_flags`, `reliability`, `units`,
`out_of_service`, `event_state`, `object_name`, `description`,
`relinquish_default`, `priority_array`, `min_pres_value`,
`max_pres_value`, `high_limit`, `low_limit`, `cov_increment`,
`system_status`, `relinquish` (section 5), `other` (with `property_id`).

BACnet/IP has no secrets: no param is a secret.

## 4. Data types

`dtype = auto` takes the type from the object type and the property:

| Object type / property | BACnet tag | WYRM value |
|---|---|---|
| analog_*, loop, pulse_converter, averaging: `present_value`, `relinquish_default`, limits, `cov_increment` | REAL | number (float) |
| large_analog_value | DOUBLE | number (float) |
| binary_*: `present_value` | ENUMERATED inactive/active | bool |
| multi_state_*, accumulator, command, positive_integer_value | UNSIGNED | number (whole) |
| integer_value | SIGNED | number (whole, signed) |
| calendar, `out_of_service` | BOOLEAN | bool |
| characterstring_value, `object_name`, `description` | CHARACTER STRING | string |
| `status_flags` | BIT STRING | map `{in_alarm, fault, overridden, out_of_service}` |
| `reliability`, `units`, `event_state`, `system_status` | ENUMERATED | number |
| `priority_array`, `other`, schedule and device `present_value` | any | dynamic: the value as sent; several values as an array; NULL as null |

An explicit `dtype` (`real`, `double`, `unsigned`, `signed`, `enumerated`,
`boolean`, `character_string`, `bit_string`) sets the tag for writes and
the type in `~meta`. A read takes any compatible tag (an ENUMERATED for a
bool point, a REAL for a number). Other conversions:

- A REAL is shown as the shortest decimal that reads back as the same
  32-bit float (`0.1`, not `0.10000000149011612`).
- With `scale` or `offset`, every number is a float.
- Character sets: UTF-8 (and ANSI X3.4), UCS-2, UCS-4, ISO 8859-1. Others
  are a point error.
- A value of another type than the point's, or NULL on a typed point, is a
  point error. The link never makes up a value.
- Dates and times (dynamic points) are strings, `*` for an unspecified field.

## 5. Writes

- `~set` on a point with `writable = true` sends WriteProperty with the
  point's `priority`. A SimpleACK is success; the framework then reads the
  point back. The link never updates `~val` itself.
- A REAL write checks the range of a 32-bit float; UNSIGNED, ENUMERATED and
  SIGNED round and check their range. A value out of range is refused
  before it is sent.
- An Error, Reject or Abort reply fails the write with its text (for
  example `write: property: write-access-denied`).
- A point that is not writable refuses the write; nothing is sent.
- `status_flags` and bit strings cannot be writable.
- **Relinquish** (NULL at a priority):
  - A point with `property = relinquish` (on the object, with `writable` and
    the `priority` to free) is a bool. It reads `true` while that slot of
    the priority array is empty. Writing `true` writes NULL to the object's
    `present-value` at that priority; `false` is refused. So a user with
    write rights frees only the priority that this point names.
  - The device action `relinquish {object_type, instance, priority = 16}`
    frees any object at any priority. It needs level `config` (a write user
    must not free, for example, priority 1, life safety).

## 6. Errors and quality

| What happens | Result |
|---|---|
| Error PDU for one property (inside an RPM-ACK, or a ReadProperty) | That point is `bad`, with the class and code text, for example `object: unknown-object`. |
| Error or Reject for a whole RPM of several properties | Each property is read again with ReadProperty, so one bad point does not fail the others. |
| Reject `unrecognized-service` (or Error `services`) for RPM | The device is read with ReadProperty from then on. |
| Abort `segmentation-not-supported`, `buffer-overflow` or `apdu-too-long` for an RPM | The request is split in two; the limit on properties per request is kept for that poll group only (until the connection reopens), so a group of long strings does not slow the others. A single property that does not fit is a point error. |
| No reply after `apdu_retries` | A device miss: points `uncertain/stale`, after 3 misses `bad/comm_fail` and the device `failed`. A poll stops at its first timeout. The last value stays. |
| One RPM of a poll has no reply, the others do | Only the points of the requests without a reply (and those after it: the poll stops) go `uncertain/stale`, then `bad/comm_fail` after 3 polls in a row; the device stays `connected`. A point whose `status-flags` request has no reply is treated the same. |
| The socket does not bind, the BBMD refuses or does not answer | The connection is `failed` with the reason in `error`; its devices are `stopped_by_parent`. The framework reopens it with backoff. |
| `status-flags` with `fault` set (`check_status`) | The point is `bad`: `status-flags: fault`. |

Out-of-service and overridden values are published as `good`: the driver
framework has no way for a driver to mark one point `uncertain`. Read the
`status_flags` point beside the value to see them.

Invoke ids are counted per remote device, for the life of the link
process: a connection that reopens on the same port goes on from the last
id. A reply is taken only from the device's address (and network) with the
request's invoke id and (in an ACK or Error) its service; a reply that
comes after its timeout is dropped and counted in `late_replies`.

## 7. Discovery and bindings

- **Who-Is.** The connection action `who_is {low?, high?, wait_ms = 3000}`
  (level config) sends a global Who-Is (through the BBMD when one is set)
  and returns every I-Am in the window: `[{instance, address, network?,
  mac?, vendor_id, max_apdu, segmentation}]`. `low` and `high` go together;
  `wait_ms` is 100–30000.
- **A device without an address** is bound by its own Who-Is: the link
  waits the whole window, exactly one address must answer, and that address
  must answer a read of the device's `object-identifier`. The binding stays
  until the device stops answering; an I-Am that comes at another time does
  not change it. Two answers for one device are refused (`set its
  address`). For devices with writable points, prefer a fixed `address`.
- **A device with an address** gets one unicast Who-Is per connection open
  to learn its max APDU (when `max_apdu = 0`). Its I-Am ends the wait; a
  device that does not answer costs one `apdu_timeout_ms` and gets 480. Set
  `max_apdu` to skip the Who-Is.
- **Forwarded-NPDU** (from a BBMD) names the original source. The link
  believes it only from the configured `bbmd`; from anyone else it is
  dropped.
- **BBMD.** With `bbmd`, the link registers as a foreign device when the
  connection opens and renews the registration before a request once half
  of the TTL has passed.

## 8. Actions and diagnostics

| Node | Action | Level | Result |
|---|---|---|---|
| connection | `who_is {low?, high?, wait_ms}` | config | Devices that answered (section 7). |
| device | `list_objects {limit = 1000}` | config | `{objects: [{object_type, instance, name, units?, unit?}], count, truncated}`. Reads `object-list` whole, or index by index when it does not fit one reply, then the names (and the units of analog objects). Stops at 160 s with `truncated = true`. |
| device | `read_property {object_type, instance, property = present_value, array_index?}` | read | `{value}` as sent; for `units` also `units` (name) and `unit` (symbol). `property` takes the point names and `object_list`, `object_identifier`, `object_type`, `vendor_identifier`, `max_apdu_length_accepted`, `segmentation_supported`, `number_of_states`, or a number. |
| device | `relinquish {object_type, instance, priority = 16}` | config | NULL at that priority (section 5). |

Diagnostics on each connection and device: `requests`, `errors`,
`timeouts`, `exceptions` (Error, Reject and Abort replies), `late_replies`,
`rpm_splits`, `who_is_sent`, `last_rtt_ms`, `avg_rtt_ms`.

Ping: ReadProperty of the device object's `system-status`. Any reply, an
Error too, means the device is alive.

## 9. Simulator

`src/sim.rs` (feature `sim`) is a BACnet/IP device on its own UDP port:
device object, analog-input 1, analog-value 1 (commandable), binary-input
1, binary-value 1 (commandable), multi-state-value 1 (commandable),
integer-value 1 and large-analog-value 1. It answers Who-Is (unicast I-Am),
ReadProperty, ReadPropertyMultiple and WriteProperty with priorities, can be
a BBMD for one foreign device, or sit behind a router. Failure modes:
silence, dropped requests, slow replies, Reject, RPM not supported, an Error
for a whole RPM, a small max APDU (aborts), a second (forwarded) I-Am and a
wrong device identifier.

Run it for a demo:

```
cargo run -p wyrm-link-bacnet --features bin --bin wyrm-bacnet-sim -- \
  --listen 127.0.0.1:47809 --instance 1234 --extra 20
```

Analog-input 1 moves between 18 and 26 °C once per second. A link tree for
it (the link on its own port, Who-Is straight to the simulator):

```json5
{connections: {sim: {
  bind_host: "127.0.0.1", bind_port: 47810, broadcast: "127.0.0.1:47809",
  devices: {d1: {instance: 1234, address: "127.0.0.1:47809",
    points: {
      temp: {object_type: "analog_input", instance: 1, unit: "°C"},
      sp:   {object_type: "analog_value", instance: 1, writable: true, priority: 8},
      sp_free: {object_type: "analog_value", instance: 1, property: "relinquish",
                writable: true, priority: 8},
    }}}}}}
```

Tests: `cargo test -p wyrm-link-bacnet --all-features` (codec unit tests on
byte sequences of the standard's examples; the driver against the
simulator).

## 10. Known limits

- **Discovery needs the BACnet port.** Many devices answer Who-Is with a
  broadcast I-Am to port 47808 (the simulator answers unicast). Keep
  `bind_host = 0.0.0.0` and `bind_port = 47808` for discovery: on Linux a
  socket bound to one address does not get the subnet's broadcasts.
- **One BACnet stack per port.** Another BACnet program on the host that
  holds UDP 47808 makes the connection `failed` (`bind … address in use`).
  Use another `bind_port` and a fixed `address` for each device then.
- The BBMD registration is renewed only while requests flow: a connection
  without devices lets it lapse.
- No segmentation: long replies are split into more requests; one property
  longer than the max APDU cannot be read.
- Not supported: BACnet MS/TP on a serial port (a routed MS/TP device behind
  a BACnet/IP router is supported), COV subscriptions (follow-up), alarms
  and events, BACnet/SC, BACnet/IPv6, the link's own device object (it
  does not answer Who-Is or ReadProperty).
- The unit comes from the `unit` param, not from the device: `~meta` is
  fixed by the params. `list_objects` and `read_property` show the device's
  units to copy.
- UDP sources can be forged on the network. The link checks addresses,
  invoke ids and identities, but BACnet/IP has no authentication: keep the
  BACnet network separate (BACnet/SC is not supported).
