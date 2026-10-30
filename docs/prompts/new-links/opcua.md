# Link `opcua` — OPC UA client

**Why:** OPC UA is the standard data interface of modern PLCs, SCADA servers and machines. Without it the broker cannot reach most new industrial equipment.

**Scope**
- Connection = an OPC UA endpoint (`opc.tcp://host:4840/path`), security policy (None, Basic256Sha256, Aes128_Sha256_RsaOaep, Aes256_Sha256_RsaPss) and mode (None, Sign, SignAndEncrypt), user identity (anonymous, user + `secret` password, X.509 user cert PEM + key `secret`), application instance certificate (PEM + key `secret`; generate a self-signed one in the link's `data_dir` on first start when none is given, and show its thumbprint in a status leaf so the server admin can trust it), server certificate trust (pinned PEM or "trust on first use" flag, default off), session timeout, request timeout.
- Device = a logical group of nodes (an optional namespace URI to resolve `ns=` indexes by URI, so a server restart that reorders namespaces does not break points).
- Point = a NodeId (`ns=2;s=Line1.Temp`, `ns=3;i=1001`, `nsu=<uri>;s=…`) + attribute Value; data type from the server (Boolean, integers, Float, Double, String, DateTime → RFC 3339 string, ByteString → bytes, arrays of these → array); `scale`/`offset`/`unit` for numbers. Quality: map OPC UA StatusCode Good/Uncertain/Bad to WYRM quality (`good` / `uncertain` / `bad`) — never report Good for a non-Good status.
- Reads: batched Read service requests (max nodes per request from the server's operation limits, default 500). Polling is the framework's model; also offer `subscribe: bool` per device (default false): when true, use a Subscription with MonitoredItems (sampling interval = the point's poll period) and push data changes instead of polling — only if the framework lets a driver deliver values asynchronously; otherwise leave it out and say so.
- Writes: Write service with the server's data type (convert the WYRM value; refuse lossy conversions with a clear error); read-back.
- Ping: read `Server_ServerStatus_State` (i=2259).
- Reconnect: session re-activation / new session with backoff from the framework; a secure channel renewal must not drop values.
- Actions: on a device, `browse {node = "i=85", depth = 1, limit = 500}` → `[{node_id, browse_name, display_name, node_class, data_type}]`; on a connection, `get_endpoints` → the server's endpoints and policies (commissioning).

**Crate**: `async-opcua` (the maintained fork of `opcua`, MPL-2.0) client features only; check it builds without OpenSSL (it can use RustCrypto); if it needs OpenSSL, stop and report — do not add OpenSSL.

**Simulator**: an OPC UA server in `src/sim.rs` from the same crate's server feature (dev/test only), with a few variables (changing Double, Int32, Boolean, String, an array, a writable variable, a node that returns Bad status), security None and Basic256Sha256, a user/password; failure modes: server stop/start, a node removed.
