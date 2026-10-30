# Link `bacnet` — BACnet/IP client

**Why:** BACnet is the protocol of building automation (HVAC, chillers, AHUs, lighting, energy meters in buildings). Data collection in buildings needs it.

**Scope**
- Connection = a BACnet/IP port: local bind address and UDP port (default 0.0.0.0:47808), broadcast address for discovery, optional BBMD for foreign-device registration (address, TTL), APDU timeout and retries, max APDU length accepted (1476).
- Device = a BACnet device: device instance (0…4194302) and address (IP:port, or resolved by Who-Is/I-Am), max APDU and segmentation from I-Am, `use_rpm` (ReadPropertyMultiple, default true; falls back to ReadProperty per point when the device rejects RPM).
- Point = object type (analog-input/output/value, binary-input/output/value, multi-state-input/output/value, accumulator, …) + instance + property (default present-value; also status-flags, reliability, units) + optional array index; data types from the application tags (REAL, DOUBLE, UNSIGNED, SIGNED, ENUMERATED, BOOLEAN, CHARACTER STRING, BIT STRING); `scale`/`offset`; the BACnet engineering unit shown as `unit` when present. Quality: status-flags fault/out-of-service → `uncertain`/`bad` as documented.
- Reads: ReadPropertyMultiple batched to fit the device's max APDU (no segmentation needed in the first version: split requests instead; if a reply would be segmented, request fewer properties).
- Writes: WriteProperty with `priority` (1…16, default 16) per point, and `relinquish` (write NULL at that priority) as a point action or a special value; read-back.
- Invoke ids per device; a late reply is dropped; Reject/Abort/Error PDUs → point errors with the BACnet error class/code text.
- Ping: ReadProperty device object `system-status`.
- Actions: on a connection, `who_is {low?, high?, wait_ms = 3000}` → `[{instance, address, vendor_id, max_apdu}]`; on a device, `list_objects {limit = 1000}` reading `object-list` (array index by index when large) and the object names (commissioning).

**Not in scope**: BACnet MS/TP (serial), COV subscriptions (note as follow-up), segmentation, alarms/events, BACnet/SC.

**Crate**: no mature async BACnet crate is assumed; implement BVLC + NPDU + the needed APDU services and the application-tag codec in-crate, with unit tests built from byte sequences in the standard's annex/examples. If you find a maintained crate with a fitting license that covers this, you may use it — justify it in the PR.

**Simulator**: a BACnet/IP device in `src/sim.rs` (UDP, own port so tests do not need 47808) answering Who-Is, ReadProperty, ReadPropertyMultiple and WriteProperty with priorities, with a few objects (AI changing, AV writable, BI, MSV, device object), and failure modes (silence, Reject, Error unknown-object, RPM not supported).
