# SNMP link

The `snmp` link polls SNMP agents — switches, routers, UPS, PDUs, printers,
controllers — like any other device. It speaks SNMPv2c (community) and
SNMPv3 (USM: HMAC-SHA-1 or HMAC-192-SHA-256, AES-128 privacy). It runs on
the driver framework (ADR 0004): the tree, the `add_*` / `edit` / `remove` /
`restart` / `stop` / `start` actions, states, scheduling, read-back writes
and the quality ladder are the framework's, as in every framework link
([links.md](links.md)).

Install it with Install Link ▸ *from Driver*, driver `snmp` (embedded or
process), or as the package `snmp` (`wyr link pack`, binary
`wyrm-link-snmp`).

## 1. The tree

```
downstream/<link>/
  <connection>        Add SNMP v2c | Add SNMP v3  (one agent address)
    status, error     the framework's state leaves
    requests, errors, timeouts, exceptions, late_replies, rejected_replies,
    undecodable_replies, last_rtt_ms, avg_rtt_ms
    ▸ Reset Engine Clock  (snmp_v3 only, config; §7)
    <device>          Add Device   (one view of the agent: a v3 context or a v2c community)
      status, error, diagnostics as above
      ▸ Walk
      <point>         Add Point    (one OID)
```

A connection is one agent (`host:port`, one UDP socket). A device is one view
of it: usually one device per connection with the defaults; add more when the
agent shows other data under another v3 context or another v2c community (some
switches select a VLAN by community).

## 2. Parameters

### Connection `snmp_v2c` (Add SNMP v2c)

| Param | Default | Bounds | Meaning |
|---|---|---|---|
| `host` | — (required) | | Agent host name or address. The addresses of a name are tried in turn, IPv4 first, then IPv6, while the bound of opening the connection (the lookup and two addresses) has room; the error lists each address tried. |
| `port` | 161 | 1…65535 | Agent UDP port. |
| `community` | — (required, secret) | | Community string. Entered in `add_snmp_v2c`/`edit`, kept sealed; never shown. |
| `timeout_ms` | 1000 | 100…10000 | Bound on each request. |
| `retries` | 1 | 0…5 | Repeats of a request after a timeout. |

### Connection `snmp_v3` (Add SNMP v3)

| Param | Default | Bounds | Meaning |
|---|---|---|---|
| `host`, `port` | —, 161 | 1…65535 | As above. |
| `user` | — (required) | 1…32 characters | USM user name. |
| `auth_protocol` | `sha256` | `sha1`, `sha256` | `usmHMACSHAAuthProtocol` (HMAC-SHA-96) or `usmHMAC192SHA256AuthProtocol` (RFC 7860). |
| `auth_passphrase` | — (required, secret) | ≥ 8 characters | Authentication passphrase. |
| `priv_protocol` | `aes128` | `aes128`, `none` | AES-128-CFB (RFC 3826), or `none` for authNoPriv. |
| `priv_passphrase` | `""` (secret) | ≥ 8 characters with `aes128` | Privacy passphrase. |
| `engine_id` | `""` | 5…32 octets in hex (`0x8000…`, `80:00:…` or plain) | Optional: the agent's `snmpEngineID`, as net-snmp `-e`. When set, a discovered engine id that is another fails the connection, and a report naming another engine never starts a rediscovery. |
| `timeout_ms`, `retries` | 1000, 1 | as above | |

The engine id is discovered when the connection opens (RFC 3414 §4) and the
keys are localized for it. The agent's boots and time come from authenticated
messages only, never from the unauthenticated discovery report. The link keeps
them across reconnects (per agent address, engine id and user, for as long as
the link runs); the first time, they come from the authenticated answer to
the first request, sent at boots/time 0/0: a `usmStatsNotInTimeWindows`
report, or, from an agent that skips that check, a response whose values are
not used (the request is sent again). noAuthNoPriv is not offered.

`host`, `port`, `user`, the protocols and `context` are the destination of the
secrets: an `edit` that changes one of them drops the stored secrets unless it
gives them again (the framework's rule).

### Device

| Param | Default | Bounds | Meaning |
|---|---|---|---|
| `context` | `""` | | SNMPv3 `contextName`; empty = the default context. |
| `community` | `""` (secret) | | v2c only: this device's community instead of the connection's; empty = the connection's. |
| `max_varbinds` | 20 | 1…100 | Scalars per GET request. |
| `max_repetitions` | 25 | 1…100 | Rows per GETBULK request (table columns, `walk`). |
| `max_pages` | 20 | 1…200 | GETBULK requests per table column and poll. |
| `ping` | true | | Ping the device. |
| `ping_s` | 10 | 0.1…3600 | Ping period (s). |
| `republish_s` | 0 | 0…3600 | Publish an unchanged value again after this long (0 = on a change only). |

### Point

| Param | Default | Bounds | Meaning |
|---|---|---|---|
| `oid` | — (required) | ≤ 128 arcs | Numeric OID: `1.3.6.1…`, `.1.3.6.1…` or `iso.3.6.1…` (stored as `1.3.6.1…`). For `table_column`: the column's OID. |
| `kind` | `scalar` | `scalar`, `table_column` | `scalar`: GET of `oid`. `table_column`: the cell `oid.index`, read by GETBULK. |
| `index` | `""` | dotted numbers | Row index of a `table_column` point (`3`, `1.4.192.0.2.1`); refused on a scalar. |
| `conv` | `auto` | see §3 | Value conversion. |
| `scale`, `offset` | 1, 0 | `scale` ≠ 0 | `value = raw × scale + offset`, numeric conversions only. |
| `unit` | `""` | | Shown in `~meta.unit`. |
| `poll_s` | 10 | 0.01…86400 | Poll period (s). |
| `writable` | false | | The point takes `~set` (SET). |
| `set_type` | `integer` | `integer`, `octet_string`, `gauge32` | SMI type of a SET. |

Rules checked when a point is added or edited: `table_column` needs an
`index`; `scale`/`offset` only on `auto` and numeric conversions; a writable
`integer`/`gauge32` point uses `auto` or `gauge`, a writable `octet_string`
point `auto` or `string`.

## 3. Conversions

| `conv` | Takes | Gives |
|---|---|---|
| `auto` | any | INTEGER → integer; Counter32/Gauge32/TimeTicks/Counter64 → unsigned; OCTET STRING → text (UTF-8 without trailing NULs, else hex `de:ad:be:ef`); IpAddress → `192.0.2.1`; OBJECT IDENTIFIER → `1.3.6.1…`; Opaque → bytes. `~meta.type` is `dynamic`. |
| `counter32` | Counter32 | the raw counter |
| `counter64` | Counter64 or Counter32 | the raw counter |
| `rate_per_s` | Counter32 or Counter64 | `(new − old) / seconds` between two polls; see below |
| `gauge` | Gauge32, INTEGER, TimeTicks, counters | the number |
| `timeticks_s` | TimeTicks | seconds (hundredths / 100) |
| `string` | any but NULL | text, as `auto` gives it |
| `ip` | IpAddress, OCTET STRING of 4 or 16 octets | IPv4 or IPv6 text |
| `mac` | OCTET STRING of 6 octets | `00:1b:21:0a:0b:0c` |

Numbers are scaled with `scale`/`offset`. With `scale = 1` and `offset = 0` an
integer stays an integer; otherwise the value is a float.

`rate_per_s`: the first poll gives no value (a rate needs two samples). A
Counter32 that goes down wrapped once (`new + 2³² − old`); a Counter64 that
goes down was reset, and that poll gives no value. A plan with rate points
also reads `sysUpTime.0`; when it goes down the agent restarted, and every
rate starts again without a value. The time base is the link's clock: the
time each answer came (the answer of the request that carried that varbind,
not the end of the poll). `scale = 8` turns octets per second into bits per
second.

A Counter32 can wrap more than once between two samples, and the link cannot
see it: a 1 Gbit/s `ifInOctets` wraps every 34 s. So a Counter32 sample older
than `max(2 × poll_s, poll_s + 5 s)` (after an outage) gives no rate; the rate
starts again from the new sample. Keep `poll_s` well below the wrap time, and
use the 64-bit `ifHC*` counters for links faster than about 100 Mbit/s. A
counter that is cleared without an agent restart (`clear counters`, an
interface reset) looks like one wrap to the link: one rate up to
`2³² / seconds`. The link does not read `ifCounterDiscontinuityTime`.

A varbind of the wrong type for its conversion is a point error (`conv mac:
cannot convert a counter32`), never a made-up value. A varbind whose value
does not fit its own type (an INTEGER of 5 octets or of none, a Counter32
above 2³², a known agent bug) is a point error too ("malformed INTEGER
encoding from the agent"); the other varbinds of that answer keep their
values.

## 4. Reads

* Scalars of one device and poll period are read with GET, at most
  `max_varbinds` per request.
* Cells of a table column are read with GETBULK, from just below the first
  wanted row, jumping over the gaps between wanted rows, at most `max_pages`
  requests per column and poll. Rows the column does not have are point errors
  (`noSuchInstance`).
* An answer with `tooBig` splits the request in two; a single varbind that is
  still too big is a point error. An error status with an index (`genErr`)
  fails that point and reads the others again.
* `noSuchObject`, `noSuchInstance` and `endOfMibView` fail that point only.
* A request without an answer (after its retries) fails the points it asked
  for, and the poll goes on with the next request: an agent whose handler for
  one OID hangs does not stop the other points. Two requests in a row without
  an answer stop the poll; every point not read yet misses with them.

Every request has a new request id (v3: and msgID). Only an answer with one of
the ids of that request is taken; an answer that comes after its timeout is
dropped and counted in `late_replies`. A timeout sends the request again (a new
id) up to `retries` times. Two more counters show datagrams the link drops:

| Counter | Counts |
|---|---|
| `late_replies` | Answers to an earlier request (their id is not one of this request's). A late v3 answer is authenticated first, and its boots and time move the link's notion of the agent's clock forward. |
| `rejected_replies` | v3 answers that are not taken: the MAC does not verify, the authoritative engine id is another, the security level is lower than the request's (no MAC, or not encrypted for an authPriv request), it does not decrypt, it is outside the time window (§7). |
| `undecodable_replies` | Datagrams that are not an SNMP message the link reads (framing, header or PDU malformed). |

## 5. Writes

A writable point takes `~set`: the link sends one SET of `set_type` and the
framework reads the point back; the value is never updated before the
read-back. A number is scaled back (`(value − offset) / scale`, rounded) and
must fit the type (INTEGER: 32 bits signed, Gauge32: 0…4294967295). The
agent's refusal (`notWritable`, `wrongType`, `noAccess`, `authorizationError`,
…) is the error of the `~set` and changes nothing. A read-only point refuses
the write. Only INTEGER, OCTET STRING and Gauge32 are written.

## 6. Errors and quality

| What happens | Result |
|---|---|
| `noSuchObject` / `noSuchInstance` / `endOfMibView`, a conversion that does not fit, a value whose encoding does not fit its type, an error status for one varbind | That point `bad`; the device stays connected. |
| No answer within `timeout_ms × (1 + retries)` to any request of a poll | A device miss: points `uncertain/stale`, after 3 misses `bad/comm_fail` and the device `failed`. |
| No answer to one request while others of the poll are answered | The points of that request `uncertain/stale`, after 3 polls in a row `bad/comm_fail`; the device stays connected. |
| `authorizationError` on a poll or ping | The device `failed`: "authorizationError: the agent's access control (VACM) refuses this request; check the community, user or context". |
| v3 report `usmStatsWrongDigests`, `usmStatsUnknownUserNames`, `usmStatsUnsupportedSecLevels`, `usmStatsDecryptionErrors` | When the connection opens: the connection `failed` with the reason (e.g. "the agent refused the authentication digest (usmStatsWrongDigests): check auth_protocol and auth_passphrase"); later: the device fails with it. |
| v3 report `snmpUnknownContexts` | The device's `context` is not one the agent has: the device fails with "the agent does not know this context (snmpUnknownContexts): check the device's context". Another report names its OID in the error. |
| v3 report `usmStatsNotInTimeWindows` (authenticated) | The agent restarted or its clock moved: the link takes the agent's boots/time (forward only) and sends again once. |
| v3 answer outside the time window (lower boots, or more than 150 s behind) | Dropped (`rejected_replies`): a replay. When no answer is taken the device misses with "the agent's answers are outside the time window …". An agent whose boots counter went down is refused (RFC 3414) until **Reset Engine Clock** runs on the connection; a connection that opens with only such answers stays connected, says so in `attr.warning` of its `status`, and its devices fail. |
| v3 report `usmStatsUnknownEngineIDs` with another engine id | The engine id changed (a replaced device): the connection reopens and discovers it again. The report is not authenticated, so this happens at most once per 30 s per agent (the wait doubles up to 15 min while such reports keep coming); within the wait the device fails with "… not discovering it again for N s". |
| v3 report `usmStatsUnknownEngineIDs` with the engine id the link has | Not authenticated and not true (a forged or broken report): the device fails with it; the connection stays. |
| ICMP port unreachable (nothing listens on the port) | The connection drops; it reopens with backoff and stays `failed` with `error` while nothing answers; its devices are `stopped_by_parent`. |
| No answer when the connection opens | The connection `failed` ("no answer from the agent …"). |

A **wrong v2c community gets no answer at all**: agents drop such requests
without a reply (RFC 3584). It shows as an agent that does not answer, not as
an authentication error.

The connection opens with a GET of `sysUpTime.0` (v3: after engine discovery)
with the connection's community and the default context: UDP has no
connection, so this is how an agent that cannot be reached fails the
connection. The device ping is the same GET in the device's view; any answer,
`noSuchObject` included, means alive.

## 7. Security

* The community and both passphrases are secret parameters: entered in
  `add_*`/`edit`, kept sealed in the link's `data_dir`, never in `~meta`,
  `export`, replies or logs. No datagram is ever logged (a v2c datagram holds
  the community). Bootstrap params in `wyrmd.json5` are plain text in that file:
  prefer the actions.
* SNMPv2c sends the community and the values in clear text. A v2c connection
  beyond loopback says so in `attr.warning` of its `status` leaf; use
  `snmp_v3` with `aes128` beyond a trusted network. A v3 connection with
  `priv_protocol: none` beyond loopback says that values travel unencrypted.
* An answer to a v3 request is taken only when its MAC verifies, its
  authoritative engine id is the agent's, its security level is the request's
  and it is in the time window (RFC 3414 §3.2 7b): lower boots, or a time more
  than 150 s behind the link's notion of the agent's clock, is a replayed old
  message and is dropped. The clock moves forward only, and only on
  authenticated messages, late ones included (RFC 3412 §7.2: authentication
  and timeliness come before the msgID); the unauthenticated discovery report
  sets the engine id, never the clock. The values of a response to a request
  sent before the clock is known are never taken (it may be a replay): only
  its boots and time, and the request is sent again.
* Discovery is not authenticated: an on-path attacker can redirect the
  requests to another agent that has the same user and passphrases (common
  across a fleet) and relay them; every check then passes, and that device's
  values show as this one's. Set `engine_id` (the agent's `snmpEngineID`,
  e.g. from `snmpget -v3 … 1.3.6.1.6.3.10.2.1.1.0`) to refuse any other
  engine. A replaced device then needs its new id in `engine_id`.
* The clock is kept across reconnects, so a forced reconnect (a forged ICMP
  error or report) does not open a window for replays. **Reset Engine Clock**
  (connection action, `config`, v3) forgets it; run it only when the agent
  really lost its boots counter (it was reinstalled or reset). A connection
  restart does not forget it: to the link a restart is one more open, like
  any reconnect, and a reconnect can be forced from the network. The kept
  clock is in the link's memory: restarting the link process (or `wyrmd` for
  an embedded link) forgets it too.
* **Walk** is a `config` action: it reads any subtree of the agent with the
  link's credentials (interface, ARP, vendor tables beyond the configured
  points) and costs the agent up to hundreds of requests, so a `read` or
  `write` caller is refused.

## 8. Walk

Device action **Walk** (`walk {oid, max = 500}`, level `config`, at most 60 s):
GETBULK from `oid` while the answers stay below it, at most `max` (1…10000)
entries → `[{oid, type, value}]`, `type` the SMI type (`integer`,
`octet_string`, `counter32`, …) and `value` as `auto` converts it. Use it to
find the OIDs and row indexes for points. The walk holds the connection's
owner while it runs: the connection's polls wait.

## 9. Common OIDs

| Object | OID | Point |
|---|---|---|
| sysDescr | `1.3.6.1.2.1.1.1.0` | scalar, `string` |
| sysUpTime | `1.3.6.1.2.1.1.3.0` | scalar, `timeticks_s` |
| sysName | `1.3.6.1.2.1.1.5.0` | scalar |
| ifDescr | `1.3.6.1.2.1.2.2.1.2` | table_column, index = ifIndex |
| ifOperStatus | `1.3.6.1.2.1.2.2.1.8` | table_column (1 up, 2 down, …) |
| ifInOctets / ifOutOctets | `1.3.6.1.2.1.2.2.1.10` / `.16` | table_column, `rate_per_s` (Counter32) |
| ifName | `1.3.6.1.2.1.31.1.1.1.1` | table_column |
| ifHCInOctets / ifHCOutOctets | `1.3.6.1.2.1.31.1.1.1.6` / `.10` | table_column, `rate_per_s`, `scale: 8` for bit/s |
| hrProcessorLoad (HOST-RESOURCES-MIB) | `1.3.6.1.2.1.25.3.3.1.2` | table_column, `gauge`, unit `%` |
| hrStorageUsed / hrStorageSize | `1.3.6.1.2.1.25.2.3.1.6` / `.5` | table_column, `gauge` (× hrStorageAllocationUnits `.4`) |
| upsBatteryStatus (UPS-MIB) | `1.3.6.1.2.1.33.1.2.1.0` | scalar (2 normal, 3 low, 4 depleted) |
| upsEstimatedChargeRemaining | `1.3.6.1.2.1.33.1.2.4.0` | scalar, unit `%` |
| upsInputVoltage | `1.3.6.1.2.1.33.1.3.3.1.3` | table_column, index 1, unit `V` |
| upsOutputPercentLoad | `1.3.6.1.2.1.33.1.4.4.1.5` | table_column, index 1, unit `%` |

## 10. Try it with the simulator

`wyrm-snmp-sim` is an SNMP agent with community `public` and the v3 users
`sha1user` (SHA-1, AES), `sha256user` (SHA-256, AES) and `authonly`
(SHA-256, no privacy), each with the passphrase `<user>-pass`. Its MIB: the
system group (writable `sysContact`), `ifNumber`, an `ifTable` and `ifXTable`
of 4 rows whose octet counters grow every second (row 1's `ifInOctets` starts
just below the Counter32 wrap), and one object of each SMI type under
`1.3.6.1.4.1.64999.1` (`.1.0` INTEGER and `.2.0` Gauge32 writable, `.3.0`
IpAddress, `.4.0` TimeTicks, `.5.0` Opaque, `.6.0` Counter64, `.7.0` binary
OCTET STRING, `.8.0` writable text).

```sh
cargo run -p wyrm-link-snmp --features bin --bin wyrm-snmp-sim -- --listen 127.0.0.1:1161
snmpwalk -v2c -c public 127.0.0.1:1161 1.3.6.1.2.1.2.2.1.2      # net-snmp, if installed
```

A link in `wyrmd.json5` against it (the community in the file is for the demo
only; enter real ones with `add_snmp_v2c`):

```json5
links: {
  net1: {
    driver: "snmp",
    params: {
      connections: {
        sim: {
          kind: "snmp_v2c", host: "127.0.0.1", port: 1161, community: "public",
          devices: {
            agent: {
              points: {
                uptime: { oid: "1.3.6.1.2.1.1.3.0", conv: "timeticks_s", unit: "s" },
                eth0_in: { oid: "1.3.6.1.2.1.31.1.1.1.6", kind: "table_column", index: "1",
                           conv: "rate_per_s", scale: 8, unit: "bit/s", poll_s: 5 },
                contact: { oid: "1.3.6.1.2.1.1.4.0", conv: "string", writable: true,
                           set_type: "octet_string" },
              },
            },
          },
        },
      },
    },
  },
}
```

Or add the connection at run time: `downstream/net1` ▸ Add SNMP v3 with host
`127.0.0.1`, port `1161`, user `sha256user`, both passphrases
`sha256user-pass`; then Add Device, ▸ Walk `1.3.6.1.2.1.2.2.1`, and Add Point
for the OIDs found.

The simulator's failure modes (tests, `links/snmp/src/sim.rs`): silence, a
reply delayed past the timeout, `authorizationError`, `tooBig` above a number
of varbinds, `genErr` on one OID, a restart (new boots, `sysUpTime` from 0),
unknown OIDs and communities.

Against a real agent (net-snmp `snmpd`):

```sh
WYRM_SNMP_AGENT=127.0.0.1:16163 WYRM_SNMP_USER=sha1user WYRM_SNMP_PASS=sha1user-pass \
  cargo test -p wyrm-link-snmp --test interop -- --ignored
```

## 11. Known limits

* **No trap or inform receiver** (follow-up): the link polls only.
* **No MIB files**: OIDs are numeric; §9 lists common ones.
* **No SNMPv1**, no noAuthNoPriv v3, no MD5 or SHA-224/384/512, no DES, 3DES,
  AES-192 or AES-256 privacy.
* No v3 key change (`usmUserTable`) or user management on the agent.
* One OID per point; no table point that publishes a whole column as an array.
* A SET carries one varbind; INTEGER, OCTET STRING and Gauge32 only.
* `rate_per_s` uses the link's clock at each answer, not the agent's
  `sysUpTime` deltas; a counter cleared without a restart gives one spike
  (§3).
* SNMP over TCP, TLS (RFC 6353) or DTLS is not supported; UDP only.
* Interop was checked against net-snmp 5.6 (v2c, v3 SHA-1/AES-128); SHA-256 is
  checked against the built-in simulator and an independent key derivation.
