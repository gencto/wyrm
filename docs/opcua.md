# OPC UA link

The `opcua` link is an **OPC UA client**. It reads and writes the Value
attribute of nodes on OPC UA servers (PLCs, SCADA servers, machines) and
shows them as points in the WYRM tree. It runs on the driver framework
(ADR 0004): the framework gives the tree, the `add_*` / `edit` / `remove` /
`restart` / `stop` / `start` actions, the states, polling, read-back writes
and the quality ladder. The link does the OPC UA part.

Code: `links/opcua` (`wyrm-link-opcua`), on `async-opcua` 0.19 (MPL-2.0;
its crypto is RustCrypto, so no OpenSSL). Driver name: `opcua`, embedded in
`wyrmd` or as a process (`wyrmd link opcua`, package `opcua`).

## 1. Tree

```
wy/<site>/downstream/<link>/
  <connection>/            one session to one endpoint
    status, error          (framework) state and error text
    requests, errors, …    (framework) diagnostics
    ~act/get_endpoints
    <device>/              a group of nodes, optional namespace URI
      status, error, requests, …
      ~act/browse
      <point>              the Value attribute of one node
```

## 2. Parameters

### Connection (`add_connection`)

| Param | Default | Bounds | Meaning |
|---|---|---|---|
| `endpoint` | required | `opc.tcp://host:port/path`; no user info, query or fragment | The endpoint URL. The link connects to this URL even when the server advertises another host or port (NAT, relays). |
| `security_policy` | `None` | `None`, `Basic256Sha256`, `Aes128_Sha256_RsaOaep`, `Aes256_Sha256_RsaPss` | Security policy of the secure channel. |
| `security_mode` | `none` | `none`, `sign`, `sign_and_encrypt` | `none` goes only with policy `None`; `sign`/`sign_and_encrypt` only with the others. |
| `identity` | `anonymous` | `anonymous`, `username`, `certificate` | The user identity token. |
| `username` | `""` | required for `username` | A user identity to another host needs security mode `sign` or `sign_and_encrypt` (section 5). |
| `password` | `""` | **secret** | |
| `user_cert_pem` | `""` | PEM | The X.509 user certificate (`certificate`). |
| `user_key_pem` | `""` | **secret**, PEM | Its RSA key. Sealed by the framework like every secret; the link gives it to the library in memory and never writes it to a file. |
| `cert_pem` | `""` | PEM | The application instance certificate. Empty: the link makes a self-signed one (section 5). |
| `key_pem` | `""` | **secret**, PEM | Its RSA key. With `cert_pem` or not at all. Written to a plain-text file while the connection is open (section 5). |
| `server_cert_pem` | `""` | PEM | Pin: only this server certificate is trusted. |
| `trust_on_first_use` | `false` | | Trust the first server certificate seen, then only that one. |
| `application_uri` | `urn:wyrm:opcua:client` | a URI | The client's application URI (in the certificate it makes). |
| `session_timeout_ms` | 60000 | 10000…3600000 | Requested session timeout. Keep-alive reads run every third of it (1…30 s). |
| `request_timeout_ms` | 5000 | 100…60000 | Bound on each service request (Read, Write, Browse). |
| `connect_timeout_ms` | 15000 | 1000…120000 | Bound on one open (GetEndpoints, CreateSession, ActivateSession) and on one ping. |

Secret params are entered in `add_connection` and `edit`, kept sealed by
the framework in the link's `data_dir`, and never shown in `~meta`,
`export`, replies or logs. `endpoint`, `security_policy`, `security_mode`,
`server_cert_pem` and `trust_on_first_use` are destinations: an `edit` that
changes one drops the stored secrets unless it gives them again.

### Device (`add_device`)

| Param | Default | Bounds | Meaning |
|---|---|---|---|
| `namespace_uri` | `""` | | Points without `ns=`/`nsu=` are in this namespace. The link finds its index by URI on every connect, so a server restart that reorders its namespaces does not break the points. Empty: namespace 0. |
| `max_nodes_per_read` | 500 | 1…10000 | Nodes per Read request. The link lowers it to the server's `MaxNodesPerRead` (read at connect, i=11705). |
| `ping_s` | 5.0 | 0.1…3600 | Ping period: a Read of `Server_ServerStatus_State` (i=2259). |

### Point (`add_point`)

| Param | Default | Bounds | Meaning |
|---|---|---|---|
| `node_id` | required | | `ns=2;s=Line1.Temp`, `ns=3;i=1001`, `nsu=<uri>;s=…`, `g=<guid>`, `b=<base64>`, or `s=…` / `i=…` in the device's namespace. |
| `poll_s` | 1.0 | 0.01…86400 | Poll period. Points with one period on one device are read together. |
| `writable` | `false` | | `~set` allowed. |
| `scale` | 1.0 | not 0 | Value = raw × `scale` + `offset` (numbers and arrays of numbers). |
| `offset` | 0.0 | | |
| `unit` | `""` | | `~meta.unit`. |

A point without a namespace part uses the device's `namespace_uri`; give
`ns=0;i=…` for a standard node on such a device. `nsu=<uri>;…` is always
found by URI; `ns=<n>;…` is taken as it is.

## 3. Values

Reads ask for the Value attribute with `maxAge` 0. The type comes from the
server; `~meta.type` is `dynamic`, or `number` when `scale`/`offset` is set.

| OPC UA | WYRM |
|---|---|
| Boolean | bool |
| SByte, Int16, Int32, Int64 | integer (`Int`, or `UInt` when ≥ 0) |
| Byte, UInt16, UInt32, UInt64 | `UInt` |
| Float, Double | float |
| String | string (null string → null) |
| DateTime | RFC 3339 string |
| ByteString | bytes |
| LocalizedText | its text |
| NodeId, ExpandedNodeId, QualifiedName, Guid | their text form |
| StatusCode | `UInt` (the code) |
| arrays of these | array (a matrix is flattened) |
| empty | null |
| ExtensionObject, XmlElement, DataValue, DiagnosticInfo | point error ("not supported") |

With `scale`/`offset` a number becomes a float. Without them integers stay
integers.

## 4. Writes

`~set` on a point with `writable: true`:

1. The link reads the node's DataType and ValueRank once per session (and
   the current value when the DataType is not a built-in type). The target
   type is that DataType (Duration → Double, UtcTime → DateTime), else the
   type of the current value; ValueRank 0 or 1 means an array, and
   ValueRank 2 or more (a matrix) is refused: multi-dimensional writes are
   not supported.
2. It undoes `scale`/`offset`: raw = (value − `offset`) / `scale`.
3. It converts and **refuses lossy conversions** with `invalid_parameter`
   and a clear text: a fraction to an integer type (only rounding noise of
   a few ulps, relative to the number, counts as a whole number, so that
   the scaled write 21.5 / 0.1 = 214.99999999999997 lands on 215; a real
   fraction such as 600000000.4 is refused at any size), a number out of
   the type's range, an integer above 2^53 to Double or above 2^24 to
   Float, a nonzero number too small for Float (it would become 0), a
   number to Boolean or String, a text that is not RFC 3339 to DateTime.
   Other numbers to Float are rounded to f32 precision (0.1 is not exact
   in either type, so an exact round trip cannot be the rule).
4. It sends one Write. A non-Good result (BadNotWritable,
   BadUserAccessDenied, BadTypeMismatch, …) is the write's error. There is
   no optimistic update: the framework reads the point back.

A point with `writable: false` refuses `~set` before any request.

## 5. Security and certificates

The link's PKI is in its `data_dir`, in `opcua-pki/`:

| Path | Content |
|---|---|
| `own/app-<hash>.der`, `private/app-<hash>.pem` | The generated application certificate (self-signed, RSA 2048, 10 years, SAN: `application_uri` and this host's names) and its key (mode 0600). Made on the first open of a connection without `cert_pem` when the link has a `data_dir` (also for policy `None`, which does not use it), then reused. One per `application_uri`. |
| `own/user-<hash>.der`, `private/user-<hash>.pem` | `cert_pem` and `key_pem` as files, named by a hash of both: the library reads its certificate and key from files on every secure channel open and renewal. The key file is **plain text** (not sealed), mode 0600 in the 0700 `private/` inside the 0700 `data_dir`. The files exist only while a connection that uses them opens or has a session: they are removed when the last such session ends (also after an `edit` that changes `cert_pem`, a `remove`, or a failed open), and at link start the link removes any that a stopped process left. |
| `servers/<url hash>-<trust>/trusted`, `…/rejected` | Server certificates per endpoint and trust mode. `<url hash>` is of the endpoint with a lower-case host, the port (4840 when absent) and the path (`/` when empty), so `opc.tcp://PLC1:4840` and `opc.tcp://plc1/` are one endpoint; `localhost` and `127.0.0.1` are two. `<trust>` is `pin-<hash>`, `tofu` or `strict`. |
| `servers/<url hash>-tofu/tofu-ok` | Marks that a session was made with the certificate in `trusted/` (first use done). |

The **thumbprint** (SHA-1, hex, as server trust lists show it) of the
application certificate is logged at `info` when the certificate is made
and on every secured open that fails (with the server's thumbprint), and
it is in the connection's `error` leaf when a secured open fails. The
advice in `error` comes from the server certificate of GetEndpoints and
the link's trust store, so it stays the same on every retry:

- The link does not trust the server certificate: `… the server
  certificate (thumbprint 9C02…) is not trusted: pin it (server_cert_pem)
  or set trust_on_first_use`.
- The link trusts it, but a host name, application URI or validity check
  failed (BadCertificateHostNameInvalid, …): both thumbprints.
- Otherwise the server refused this client, for example: `connect to
  opc.tcp://plc1:4840/: BadSecurityChecksFailed; if the server does not
  trust this client yet, trust its application certificate (thumbprint
  5A1F…) on the server`. Trust that certificate on the server (most
  servers put it in a "rejected" list) and the next attempt connects.

**Server certificate trust** (for policies other than `None`; the library
always checks the certificate's validity time, host name and application
URI):

| Setting | What is trusted |
|---|---|
| `server_cert_pem` (pin) | Only that certificate. |
| `trust_on_first_use: true` | The first certificate with which a session was made at that endpoint, then only it. |
| neither (the default) | Nothing: the open fails with the server certificate's thumbprint in `error` (`… is not trusted: pin it (server_cert_pem) or set trust_on_first_use`). |

Trust on first use:

- First use counts only after a session was made. The library stores an
  unknown certificate in `trusted/` before it checks its host name,
  validity and application URI; until the store has `tofu-ok`, the link
  empties `trusted/` before each attempt, so a refused (or cut) first
  attempt does not pin a certificate that never validates.
- To reset it (the server got a new certificate), delete the directory
  `<data_dir>/opcua-pki/servers/<url hash>-tofu/` while the link runs or
  is stopped; the next open is a first use again. Or set a pin.
- The first answer at the endpoint is trusted without a check of who
  sent it. With a `username` or `certificate` identity, the first use
  sends that identity to whoever answers first (a man in the middle on
  the first connect gets the password). Pin the server certificate for a
  connection with a user identity on a network you do not control.

Rules:

- A secured connection needs the link's `data_dir`. Without one only policy
  `None` works (the error says so).
- A user identity (`username` or `certificate`) to another host needs
  security mode `sign` or `sign_and_encrypt`; `add_connection`/`edit`
  refuse it with mode `none`, and only loopback takes one without. The
  link does not trust a server's user token policy that says it encrypts
  the password on a channel without security: that policy comes from
  GetEndpoints, before any checked channel, so a man in the middle could
  name its own certificate.
- On a `sign` channel (signed, not encrypted) to another host, the user
  token policy protects the identity. Before ActivateSession the link
  refuses a token policy with security policy None (a password in clear
  text, an X.509 token without a signature) or a deprecated or unknown
  one; it takes an empty one (the channel's policy encrypts the password,
  OPC UA Part 4, 7.41) and Basic256Sha256, Aes128_Sha256_RsaOaep,
  Aes256_Sha256_RsaPss. The token policy comes from GetEndpoints (the
  library offers no hook between CreateSession and ActivateSession), so
  whatever a man in the middle writes there ends in a refusal or in a
  password encrypted with a strong policy to the server certificate that
  CreateSession checked. `sign_and_encrypt` has no such limit: the channel
  encrypts the token.
- `key_pem` must be the key of `cert_pem`, and `user_key_pem` the key of
  `user_cert_pem` (a test signature must verify with the certificate);
  `add_connection`/`edit` refuse another key.
- `endpoint` is parsed with the URL parser the library connects with, and
  a URL with user info (`opc.tcp://a@b/`), a query or a fragment is
  refused, so the host the link checks (loopback rules above) is the host
  it connects to.
- Keys are written only into `private/`, created with mode 0700; a key
  file is created with mode 0600 (the generated key is made in memory and
  written by the link, never by the library with default permissions).
- A connection with security mode `none` to another host shows a warning
  on its `status` leaf (`attr.warning`): values travel unsigned and
  unencrypted.

## 6. Errors and quality

| What happens | Result |
|---|---|
| The item's status is Good | the value, quality `good` |
| The item's status is Uncertain or Bad (BadNodeIdUnknown, BadSensorFailure, UncertainLastUsableValue, …) | that point `bad/device_error`, its last value kept; other points and the device are not affected |
| The namespace URI of a point is not on the server | that point `bad/device_error` |
| One Read request of a poll times out (`request_timeout_ms`) while another answers | the points of that request `uncertain/stale`, then after 3 misses in a row `bad/comm_fail`, last value kept; the device stays `connected` and its other points `good` |
| Every Read request of a poll times out | device miss: `uncertain/stale`, then after 3 misses the device `failed` and its points `bad/comm_fail` |
| The session or connection is lost (closed socket, BadSessionIdInvalid, BadSecureChannelClosed, …) | the connection `failed` with `error`, its devices `stopped_by_parent`, points `bad/disconnected`; the framework reopens with backoff (1 s … 60 s, ±20 %) |
| A whole Read answers BadTooManyOperations (the server enforces a lower limit than it publishes, or publishes none) | the link halves the nodes per Read for this session and reads that batch again in halves; a single node that still gets it fails `bad/device_error` with the remedy in the text (lower `max_nodes_per_read`) |
| Another service fault for a whole Read | those points `bad/device_error` |

**Uncertain** values: the framework has no `uncertain` quality for a fresh
value from a driver, so an Uncertain status fails the point like a Bad one.
The link never shows a non-Good status as `good`.

Late replies: the library matches replies to requests by request handle,
so a reply that comes after its timeout is dropped and never taken for a
later request.

Reconnect: the library's own reconnect is off. A lost session ends the
session's event loop; the next call answers "transport", and the framework
opens a new session, which reads the namespace array and `MaxNodesPerRead`
again. Secure channel renewals run inside the session and do not drop
values.

## 7. Actions

| Node | Action | Level | Args | Result |
|---|---|---|---|---|
| device | `browse` | config | `node` (default `i=85`, the Objects folder; without `ns=` it is namespace 0), `depth` 1…5 (default 1), `limit` 1…5000 (default 500) | `[{node_id, namespace_uri, browse_name, display_name, node_class, data_type}]`, hierarchical references forward, breadth first, each node once; `data_type` for variables (built-in name or node id) |
| connection | `get_endpoints` | config | — | `[{endpoint_url, security_policy, security_mode, security_level, user_tokens, server_certificate_thumbprint}]` |

Both are commissioning actions at level `config`: `browse` walks the
server's address space (not only the configured points) on the
connection's owner task, so polls of that connection wait behind it (at
most 30 s); `get_endpoints` opens a second TCP connection.

## 8. Simulator

`wyrm-opcua-sim` (feature `bin`) is an OPC UA server made with the same
library:

```
cargo run -p wyrm-link-opcua --features bin --bin wyrm-opcua-sim -- --port 4840
```

It serves, in namespace `urn:wyrm:opcua-sim:data`, folder `Line1` under
Objects: `Double` (counts up every 100 ms), `Int32` (42), `Boolean`,
`String`, `Array` (Double[]), `Time`, `Bytes`, writable `Setpoint`
(Double), `Small` (Int16), `Text` and `Flags` (Int32[]), `Locked`
(read-only on the server), `Bad` (BadSensorFailure), `Uncertain`
(UncertainLastUsableValue), `Slow` (7.0; tests make its reads wait) and
writable `Matrix` (ValueRank 2). `Line1` also has a second reference to
`Int32`. Endpoints at `/`: None, Basic256Sha256 Sign and
SignAndEncrypt; users anonymous and `operator` / `sim-password`. Its
certificate is made in `--pki` (default `opcua-sim-pki`) on the first start.
`--strict-clients` makes it refuse client certificates it does not know.

A link on it (`wyrmd.json5` link params):

```json5
{
  connections: {
    sim: {
      endpoint: "opc.tcp://127.0.0.1:4840/",
      devices: {
        line1: {
          namespace_uri: "urn:wyrm:opcua-sim:data",
          points: {
            counter: { node_id: "s=Line1.Double" },
            setpoint: { node_id: "s=Line1.Setpoint", writable: true },
          },
        },
      },
    },
  },
}
```

The tests (`links/opcua/tests/sim.rs`) also use `sim::relay`, a TCP relay
in front of the server that goes silent, slow or drops connections.

## 9. Known limits

- **No subscriptions.** OPC UA Subscriptions with MonitoredItems (values
  pushed by the server) are not used: the driver framework has no way for
  a client connection to deliver values between polls. The link polls with
  batched Read requests. (Framework hook needed.)
- **Uncertain is shown as bad** (section 6). (Framework hook needed: a
  quality with a fresh value.)
- **No certificate leaf.** The thumbprint is in the `error` leaf, the log
  and the PKI files, not in a leaf of its own: the framework has no
  driver-owned leaf on a connection. (Framework hook needed.)
- Only the Value attribute; no other attributes as points, no `IndexRange`.
- No Method calls, History Read, events and alarms, or node management.
- Structured values (ExtensionObject) and XmlElement are not decoded.
- Writes to other than built-in types (an enumeration DataType with no
  current value, structures) are refused.
- No reverse connect, no discovery server (FindServers), no `opc.https` or
  WebSockets transports, only `opc.tcp`.
- Security policies Basic128Rsa15 and Basic256 (deprecated) are not
  offered; CA-signed trust chains and CRLs are not checked beyond the
  library (a pin or trust on first use trusts one certificate).
- The application certificate is not renewed before it expires (10 years).
- **RUSTSEC-2023-0071 ("Marvin", `rsa` 0.9 under `async-opcua`)**: a
  timing side channel in RSA decryption; no 0.9 release fixes it. Where
  the link uses its private key:
  - Decryption (the exposed operation): the response to every
    OpenSecureChannel, on the first open and on every token renewal, in
    both `sign` and `sign_and_encrypt` (the library decrypts before it
    checks the signature). Anyone who answers at the endpoint, or a man in
    the middle, can send ciphertexts, before the server certificate is
    checked in CreateSession, at one per open (the framework's backoff
    limits the rate). A trusted server also sets the renewal rate through
    the token lifetime it grants.
  - Signatures (not exposed by this advisory): the OpenSecureChannel
    request, the client signature of CreateSession/ActivateSession, the
    X.509 user token signature.
  - Not on the client: the decryption of user tokens is server side (the
    simulator only).

  What is at stake is the application key, which every connection with
  the same `application_uri` shares; with it an attacker can act as this
  client to every server that trusts it. The practical risk is low (remote
  timing, one query per handshake). Give each trust domain its own
  `application_uri` (so its own key), or its own `cert_pem`/`key_pem`.
  Basic128Rsa15 (PKCS#1 v1.5 padding, the classic padding oracle) is not
  offered. When `cargo audit` or `cargo deny` runs in CI, this advisory
  needs a tracked ignore with this rationale (neither runs in CI today).
- The bound on one poll is (`request_timeout_ms` + 1 s) per Read request.
  It counts the requests with the server's `MaxNodesPerRead` as the last
  open of that endpoint read it (the framework's `poll_timeout` gets no
  transport, so the link keeps that limit per endpoint in the process).
