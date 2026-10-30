# Link `snmp` — SNMP poller for network and power equipment

**Why:** switches, routers, UPS, PDUs, printers and many controllers expose metrics only over SNMP. This link polls them like any other device.

**Scope**
- Connection kinds: `snmp_v2c` (host, port 161, community as a `secret`, timeout, retries) and `snmp_v3` (USM: user, auth protocol SHA-1/SHA-256, auth and privacy passphrases as `secret`s, privacy AES-128, engine id discovery). `snmp_v1` only if the chosen crate gives it for free.
- Device = one SNMP agent context (the connection is the agent address; a device holds context/community overrides when needed, else one device per connection named by the user).
- Point = one OID (numeric dotted form; accept `iso.3.6…` and `.1.3.6…`), with `kind`: `scalar` (GET of one OID) or `table_column` (a column of a table, the point gives an index suffix), and a value conversion: `auto` (from the varbind type), `counter32/64` (raw), `rate_per_s` (difference of a counter over time, wrap-aware for Counter32), `gauge`, `timeticks_s`, `string`, `ip`, `mac`, with `scale`/`offset` for numbers and a `unit`.
- Plan: batch scalar points into GET requests of at most `max_varbinds` (default 20) per PDU; use GETBULK for table columns.
- Writes: SET for points marked writable (INTEGER, OCTET STRING, Gauge32 only), read-back as usual.
- Ping: GET `sysUpTime.0` (1.3.6.1.2.1.1.3.0); a `noSuchObject` reply still means alive.
- Actions: `walk {oid, max = 500}` on a device returning `[{oid, type, value}]` for commissioning.
- Error mapping: `noSuchObject`/`noSuchInstance`/`endOfMibView` → point error; `authorizationError`/USM report PDUs → device error with a clear message; timeout → device miss.

**Not in scope**: traps/informs receiver (note it in the guide as a follow-up), MIB file parsing (OIDs are numeric; the guide lists common OIDs: IF-MIB ifHCInOctets/ifHCOutOctets/ifOperStatus, HOST-RESOURCES-MIB, UPS-MIB).

**Crate**: evaluate `snmp2` and `csnmp` (and any maintained async SNMP crate) for v2c + v3 support, async/tokio, license; if none supports v3 USM properly, implement BER + v2c/v3 in-crate (USM HMAC with `hmac`/`sha2`, AES with `aes`+`cfb-mode` — RustCrypto, MIT/Apache). Request ids must be matched; a late reply is dropped.

**Simulator**: an SNMP agent in `src/sim.rs` with a small MIB (system group, an `ifTable` with 4 rows whose counters grow, a writable `sysContact`), v2c and v3 users, and failure modes (silence, wrong community, `noSuchObject`).
