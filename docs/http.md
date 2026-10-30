# HTTP link

The `http` link polls JSON REST APIs: energy meters, inverters, weather
stations, building gateways and cloud services that offer only HTTP. One
generic link covers them without code per vendor. It runs on the driver
framework (ADR 0004), so its tree, actions, states and quality work as in
every framework link ([`links.md`](links.md)).

Code: `links/http` (`wyrm-link-http`): `src/lib.rs` (params and driver),
`src/client.rs` (the HTTP/1.1 client), `src/select.rs` (the selector),
`src/sim.rs` (the simulator).

## 1. The tree

```
<link>/<connection>/<device>/<point>
```

| Level | Is | Example |
|---|---|---|
| Connection | A base URL with its authentication, TLS, default headers and rate limit. | `https://10.0.1.20/api`, bearer token |
| Device | One request below the base URL: method, path, query, body. | `GET /v1/status` |
| Point | A selector into the JSON reply of its device, with a value type. | `$.meter.power` → number, W |

The framework adds to each connection and device the `status` and `error`
leaves, the actions `add_*`, `edit`, `remove`, `restart`, `stop`/`start`,
`export`/`import`, and the diagnostics leaves (section 7). A device may hold
folders (`add_folder`) between it and its points.

**One request per period.** The points of one device with the same
`poll_s` form one group. Each group sends **one** request per period and
all its points take their values from that reply. Give the points of a
device the same `poll_s` (the default is 10 s) to send one request. Two
rates on one device send two requests.

## 2. Parameters

### Connection (`add_connection`)

| Param | Default | Bounds | Meaning |
|---|---|---|---|
| `base_url` | required | — | `http://` or `https://`, host, port, path prefix. No user, password, query or fragment in it. |
| `timeout_ms` | 5000 | 100…60000 | Bound on connecting, and on each request (reply and body). |
| `auth` | `none` | `none`, `basic`, `bearer`, `api_key` | How requests authenticate. |
| `username` | `""` | — | User for `basic`. |
| `password` | `""` | secret | Password for `basic`. |
| `token` | `""` | secret | The token for `bearer`; the key for `api_key`. |
| `api_key_in` | `header` | `header`, `query` | Where `api_key` puts the key. |
| `api_key_name` | `X-API-Key` | — | The header or query parameter name of the key. |
| `ca_pem` | `""` | — | https: trust only these CA certificates (PEM). Empty = the host's CA certificates (`rustls-native-certs`, loaded once; section 9). |
| `cert_pem` | `""` | — | https: the client certificate chain for mTLS (PEM). |
| `key_pem` | `""` | secret | The private key of `cert_pem` (PEM). |
| `insecure_skip_verify` | `false` | — | https: accept any server certificate. The handshake signatures are still checked. |
| `insecure_plaintext` | `false` | — | Allow credentials over `http://` to a host that is not loopback. |
| `headers` | `""` | 32 lines, 8 KiB | Default headers, one `Name: value` per line, sent with every request. Not secret: no credentials. |
| `secret_header_name` | `""` | — | One more credential header (for an API that needs two), sent with every request. |
| `secret_header_value` | `""` | secret | Its value. |
| `rate_limit` | 5 | 0.1…1000 | Requests per second on this connection (all its devices and actions). |
| `max_body_kib` | 4096 | 1…65536 | A longer reply is a device error. |

Rules (an `add_*` or `edit` that breaks one is refused with
`invalid_parameter` and changes nothing):

- `basic` needs `username` (no `:` in it); `bearer` and `api_key` need
  `token`.
- `ca_pem`, `cert_pem` and `insecure_skip_verify` only with `https://`;
  `ca_pem` and `insecure_skip_verify` not together; `cert_pem` needs
  `key_pem`. A PEM that does not parse is refused at once.
- Credentials are never sent over `http://` to a host that is not loopback,
  unless `insecure_plaintext` is set. The connection then shows a warning on
  its `status` leaf (`attr.warning`), as with `insecure_skip_verify`.
- `headers` may not set `Host`, `Content-Length`, `Transfer-Encoding`,
  `Connection`, `Upgrade`, `TE`, `Trailer`, `Keep-Alive`, `Range`,
  `If-Range`, `Accept-Encoding`, `Content-Encoding` (a partial or
  compressed body could not be masked; every request sends
  `Accept-Encoding: identity`), `Authorization`,
  `Proxy-Authorization`, `Cookie`, the API key header or the secret header,
  nor a header whose name holds `auth`, `token`, `key`, `secret`,
  `session`, `cookie`, `password`, `passwd` or `credential`: `headers` is
  not secret (it shows in `~meta` and `export`, and it is not masked).
  Credentials belong in `auth`, or in `secret_header_name` and
  `secret_header_value`.
- `secret_header_name` needs `secret_header_value`, and it may not be a
  framing header, the API key header, or `Authorization` with `basic` or
  `bearer`. A secret header counts as credentials for the plaintext rule.
- The device `query` and a point's `write_path` are not secret either:
  never put a key in them (use `api_key_in: query`).

**Secrets.** `password`, `token`, `secret_header_value` and `key_pem` are
entered in `add_connection` or `edit` and kept sealed by the framework in
the link's `data_dir`. They never show in `~meta`, `export`, errors or
logs. An `edit` that leaves a secret empty keeps the stored one while
`base_url`, `auth`, `api_key_in`, `api_key_name`, `secret_header_name`,
`headers` (a header changes what the server sends back), `ca_pem`,
`insecure_skip_verify` and `insecure_plaintext` stay the same; an
edit that changes one of them drops the stored secrets unless it gives
them again.

### Device (`add_device`)

| Param | Default | Bounds | Meaning |
|---|---|---|---|
| `method` | `get` | `get`, `post` | The request's method. |
| `path` | `""` | — | Path below the base URL's prefix, starting with `/`; percent-encoded. No `?`. |
| `query` | `""` | — | Query without `?` (`a=1&b=2`); percent-encoded. |
| `body` | `""` | 64 KiB | JSON body, `post` only (sent as is, with `Content-Type: application/json`). |
| `expect_status` | `200-299` | 100…599, 16 ranges | Status codes that count as a good reply: `200-299,304`. |

### Point (`add_point`)

| Param | Default | Bounds | Meaning |
|---|---|---|---|
| `path` | required | 512 characters, 32 segments | Selector into the reply (section 3). |
| `type` | `number` | `number`, `bool`, `string` | The value type (section 4). |
| `aggregate` | `none` | `none`, `first`, `sum`, `max`, `min`, `avg`, `count` | How several matches become one value. `none` = exactly one match. |
| `scale` | 1 | ≠ 0 | Numbers: value = raw × scale + offset. |
| `offset` | 0 | — | See `scale`. |
| `unit` | `""` | — | Shown as `~meta.unit`. |
| `bool_true` | `""` | — | `bool`: a string equal to this (any case) is true. |
| `bool_false` | `""` | — | `bool`: a string equal to this is false; empty = every other string. |
| `poll_s` | 10 | 0.1…86400 | Poll period. Points of a device with one period share one request. |
| `writable` | `false` | — | The point takes `~set` (level write). |
| `write_method` | `put` | `put`, `post`, `patch` | Method of a write. |
| `write_path` | `""` | — | Path and query of a write below the base URL; empty = the device's. |
| `write_body` | `{{value}}` | 64 KiB | JSON body of a write; `{{value}}` becomes the value. |

Rules: `sum`, `max`, `min`, `avg` and `count` need `type` `number`;
`bool_true`/`bool_false` need `type` `bool`; a writable point has
`aggregate` `none` or `first`, a `write_body` with `{{value}}` that is JSON
once it is replaced, and a writable `bool` with strings needs both
`bool_true` and `bool_false`. A stored point that breaks a rule is kept as
a failed node (quality `bad`) and is never deleted.

## 3. Selectors

A subset of JSONPath (RFC 9535 syntax), parsed when the point is added:

| Selector | Selects |
|---|---|
| `$` | the whole reply |
| `$.a.b` | member `b` of member `a` (names: letters, digits, `_`, `-`) |
| `$['a b']`, `$["a"]` | a member with any name |
| `$.items[0]`, `$.items[-1]` | an array element (negative: from the end) |
| `$.items[*]`, `$.a.*` | every element, or every member value |
| `$.items[?(@.id=="x")].v` | `v` of the elements whose `id` is `"x"` |
| `$.items[?@.v > 2]` | elements by a comparison: `==`, `!=`, `<`, `<=`, `>`, `>=` with a string, number, `true`, `false` or `null` |
| `$.items[?(@.ok)]` | elements that have `ok` |

Numbers compare by value (`1 == 1.0`). An element without the compared
member is unequal to every literal. `<` and friends compare two numbers or
two strings; other pairs never match.

Not supported: recursive descent (`..`), slices (`[1:3]`), unions
(`[0,1]`), functions (`length()`), `&&`/`||` in filters.

**Several matches.** A wildcard or a filter can find several values. With
`aggregate` `none` the point needs exactly one; `first` takes the first;
`sum`, `max`, `min` and `avg` need numbers and at least one match; `count`
is the number of matches (0 is a value, not an error).

## 4. Values and conversions

| `type` | From JSON | Result |
|---|---|---|
| `number` | number; string with a number (`" 230.1 "`); `true`/`false` as 1/0 | float, × `scale` + `offset` |
| `bool` | `true`/`false`; number (≠ 0 = true); string: `bool_true`/`bool_false`, or `"true"`/`"false"` (any case) when they are empty | bool |
| `string` | string; a number, bool, object or array as its JSON text | string |

`null` is an error for every type. A `count` is never scaled. Numbers are
floats: an integer above 2^53 loses precision.

## 5. Writes

`~set` on a writable point sends `write_method` to `write_path` (or the
device's path and query) with `write_body`, where every `{{value}}` is the
value as JSON:

- `number`: `(value − offset) / scale`, sent as an integer when it is whole
  (`{"setpoint": {{value}}}` with scale 0.1 and value 21.5 → `{"setpoint": 215}`);
- `bool`: `true`/`false`, or the text of `bool_true`/`bool_false` as a JSON
  string when they are set;
- `string`: a JSON string with escapes.

Put `{{value}}` where a JSON value goes, never inside quotes. A 2xx reply
is success; then the framework reads the point back at once (one request of
the device) and the tree shows what the server holds. There is no
optimistic update. Any other status fails the write (`invalid_parameter`,
"HTTP 400"; 401/403 "authentication failed"), a timeout answers `timeout`.
A point without `writable` refuses `~set`.

## 6. Errors and quality

| What happens | Class | Effect |
|---|---|---|
| Connection refused, DNS, TLS failure, a broken socket | transport | The connection goes `failed` with `error`, its devices `stopped_by_parent`, points `bad/disconnected`; reconnect with backoff (1 s…60 s). |
| No reply within `timeout_ms` | device miss | First miss: points `uncertain/stale`; after 3 misses the device `failed` with `error`, points `bad/comm_fail`. |
| Status outside `expect_status` (4xx, 5xx, …) | device miss | As above; `error` = `GET /api/v1/status: HTTP 503`, 401/403 `…: HTTP 401: authentication failed`. |
| Body over `max_body_kib`, a reply that is not JSON, more than 3 redirects, a redirect to another host | device miss | As above, with the reason. |
| A partial reply (HTTP 206) or an encoded one (`Content-Encoding` other than `identity`) | device miss | `…: partial reply (HTTP 206): not read`, `…: encoded reply (Content-Encoding): not read`: the masker cannot see into such a body, so it is never read; `try_request` hides it with its length. |
| Selector finds nothing, several values without `aggregate`, wrong type, `null`, a number equal to a secret ("value hidden") | point | That point only: quality `bad` with its last value; the device stays `connected`. |

Values are never invented: a failed point keeps its last value with a bad
quality.

**Echoed secrets.** Some servers echo the request (its headers or its
query) in the reply. The connection's secrets are `password`, `token`,
`secret_header_value` (and, when it is a scheme and a token such as
`Bearer abc…`, the token alone), the basic credentials in base64 and the
percent-encoded query key.

Selectors run on a view of the reply in which every **value** that holds
a secret is masked; **member names stay raw**. So a filter (`<`, `>`,
`==`, `!=`) compares `***` or `Bearer ***`, never the secret, and a count,
"nothing found" or "selects N values" cannot depend on the secret's
characters: a secret cannot be read back one character at a time. Two
limits remain (section 9): masking still tells whether a text equals or
holds a secret, so a short secret can be guessed through an echoing
server, and member names stay raw. `$.adminState` with the password
`admin` still selects, and `51234.5` with the PIN `1234` stays a number.
The masking rules, the same for selectors and for what is shown:

- a text: every secret in it (longest first) is shown as `***`. The JSON
  is parsed first, so a JSON escape (`\/`, a unicode escape) cannot hide a
  secret. A text that still holds a secret once JSON-unescaped (JSON inside
  a string) is hidden whole: `*** hidden: it holds a connection secret`;
- numbers, and numeric texts (`"230.1"`): a secret that is a plain
  decimal number (a PIN, a numeric key) is matched by value, with its
  leading zeros stripped, and only by equality, never by substring: the
  PIN `0123` hides the number `123` (and the text `"0123"`), but not
  `1234` or `51234.5`. The values 0 to 9 are too common and are never
  matched as numbers (the PIN `0000` leaves the reading `0` alone; the
  text `"0000"` is still hidden). A matched number shows as `"***"`;
- a `number` point whose match is masked fails with "value hidden: it
  holds a connection secret" (quality `bad`). This also happens to a
  reading that equals a numeric secret by chance, as long as it holds that
  value: with the PIN `0100`, a level of `100` goes `bad` each time it is
  100 (an explicit error, never a wrong value). A `count` of masked
  matches is not hidden;
- a point whose filter compared a masked value (`[?(@.id == 1234)]` with
  the PIN `1234`, `[?(@.level > 50)]` on a level equal to it) fails with
  "value hidden: a filter compared a value that holds a connection secret"
  (`test_selector` gives it as `error`), never a count one too low or
  another element;
- member names in what is shown (a `string` point of an object,
  `try_request`, `test_selector` values) are masked too, and two names
  that mask alike are both shown (`***`, `***#2`). An object of more than
  10 000 members, or more than 10 000 renamed names in all, is not masked
  name by name: the value is hidden ("value hidden: too many member names
  to mask"), and so is a `try_request` body;
- a `bool` shows no secret and is never masked.

`try_request` on a body that is not JSON: after a BOM or an anti-XSSI
prefix (`)]}'`) the JSON is masked as above; otherwise the text is masked,
and the body is hidden whole (`*** body hidden: it holds a connection
secret`) when it still holds a secret once JSON-unescaped, or when a
number in it equals a numeric secret. Every run of digits is tried on its
own too (`code123`, `id-123`, `v1234.5`, `1.0123.4`), with the same
leading-zero and 0 to 9 rules. A masked reply reports `masked: true` and
the masked length in `bytes`, and it shows only the headers
`Content-Type`, `Date`, `Cache-Control`, `Server`, `Vary`, `Retry-After`
and `Location` (masked like the body). Every other header may give the
raw length, a range, a hash or a checksum of the raw body
(`Content-Length`, `Content-Range`, `ETag`, `Digest`, `X-Checksum-*`, …):
they are left out and counted in `hidden_headers`.

Secrets shorter than 3 characters are not masked. Errors name the method
and the path; they never hold the query (an API key may be in it),
headers, bodies or selected values.

**Redirects**: 301, 302, 303, 307, 308, at most 3 per request, to the same
scheme, host and port only (the scheme in any case). On a poll, 303, and
301/302 after a POST, continue as GET without a body. A write never
follows 301 or 302 (the write fails: "redirected (HTTP 301); write not
applied"; put the target in `write_path`), takes 303 as applied without
following it, and follows 307 and 308 with its method and body.

**Connections**: one keep-alive HTTP/1.1 connection per link connection,
one request on it at a time. A connection the server closed while idle is
opened again without a failure (counted in `reconnects`). A request that
timed out or was cut drops its connection, so a late reply arrives on a
closed socket and is never taken for a later request.

## 7. Actions and diagnostics

On each device, at level `config`: they send real requests (also on a
`post` device), show reply headers and the whole reply, and share the
connection's rate limit with the polls, so they are commissioning tools,
not reading.

- **Try Request** (`try_request`): sends the device's request now and
  returns `{status, headers, body, truncated, masked, hidden_headers,
  bytes}`: any status,
  the body up to 64 KiB as text. `Set-Cookie`, `Authorization` and every
  header named like one the connection sends with a credential are left
  out; the other headers and the body are masked as in section 6 (on a
  connection with secrets a JSON reply is shown as its masked, compact
  JSON). `bytes` is the reply's length, or the masked text's length when
  `masked`; a masked reply shows the allowlisted headers only
  (section 6), and `hidden_headers` counts the others. A JSON reply is
  also kept for `test_selector`.
- **Test Selector** (`test_selector {path, type?, aggregate?}`): runs a
  selector against the last JSON reply of the device's request (a poll's
  or `try_request`'s), without I/O, on the same masked view as the points
  (section 6). Returns `{count, values, truncated}` (the first 20 matches;
  a match whose JSON text is longer than 2 KiB is shown as that text, cut)
  and, with `type`, `value` (a string cut at 8 KiB) or `error` as a point
  would show it (unscaled). Replies are kept up to 1 MiB each and 4 MiB per
  connection (the last 16 requests); a longer reply answers
  `not_available` "… is not kept".

Diagnostics leaves on the connection and each device (framework, ruling
12): `requests`, `errors`, `timeouts`, `exceptions` (replies with a status
≥ 400), `reconnects`, `redirects`, `last_rtt_ms`, `avg_rtt_ms`.

## 8. Run it with the simulator

The simulator `wyrm-http-sim` (`src/sim.rs`, feature `sim`) serves:

| Endpoint | Reply |
|---|---|
| `GET /api/data` | `{"meter": {"power", "energy", "voltage", "on", "state", "name"}, "items": [{"id", "v"}…], "nested": {"deep": {"x": 42}}, "nothing": null}`; `power` and `energy` move on each request |
| `POST /api/query` | `{"got": <the request body>, "data": …}` |
| `GET /api/echo` | the request's headers and query |
| `GET /api/resource`, `PUT`/`POST`/`PATCH /api/resource` | a writable object (`setpoint`, `mode`, `enabled`, `label`); a write merges a JSON object, anything else is 400 |
| `PUT`/`POST`/`PATCH /api/moved`, `/api/found`, `/api/temp`, `/api/done` | writes redirected with 301, 302, 307 (nothing applied); `done` merges, then 303 |
| `GET /redirect/<n>`, `GET /offsite` | redirect chains, a redirect to another host |

Tests also use its failure modes: a fixed status (401, 500, …), silence,
slow replies, invalid JSON, a huge body, a close after each reply, and TLS.

```
cargo run -p wyrm-link-http --features bin --bin wyrm-http-sim -- --listen 127.0.0.1:8090
# with auth: --basic user:password, or --bearer <token>
```

Then add the link (embedded) in `wyrmd.json5`:

```json5
links: {
  meter: {
    driver: "http",
    params: {
      connections: {
        sim: {
          base_url: "http://127.0.0.1:8090/api",
          devices: {
            data: {
              path: "/data",
              points: {
                power: { path: "$.meter.power", unit: "W", poll_s: 2 },
                energy: { path: "$.meter.energy", unit: "Wh", poll_s: 2 },
                b: { path: "$.items[?(@.id==\"b\")].v", poll_s: 2 },
                total: { path: "$.items[*].v", aggregate: "sum", poll_s: 2 },
              },
            },
            resource: {
              path: "/resource",
              points: {
                setpoint: {
                  path: "$.setpoint", writable: true, poll_s: 5,
                  write_body: "{\"setpoint\": {{value}}}",
                },
              },
            },
          },
        },
      },
    },
  },
},
```

or install it from *Install Link ▸ from Driver* (driver `http`) and build
the tree with the `add_*` actions. As a package (ADR 0021):
`wyr link pack --manifest-path links/http/Cargo.toml` (binary
`wyrm-link-http`, feature `process`).

## 9. Known limits

- **Poll period on the point**, not the device: the framework groups points
  by the point's period (`Driver::poll_period` sees only the point). Points
  of a device with different `poll_s` send one request per period.
- **No OAuth2 flows** (client credentials, refresh tokens): a static bearer
  token works. A follow-up.
- No XML/SOAP, no WebSockets, no server-sent events, no webhooks (push in).
- No HTTP/2; no compression (`Accept-Encoding` is not sent); no proxies; no
  cookies or sessions (a `Cookie` header is refused: it is a credential).
- No digest or NTLM authentication.
- Device requests are GET or POST; the body has no placeholders.
- Numbers are floats (`f64`).
- Selector subset only (section 3).
- **Masking is by text** (section 6): a string shown that holds a secret
  is masked even when the match is by chance (`administrator` with the
  password `admin` shows `***istrator`, and a filter on it compares
  `***istrator`). Secrets shorter than 3 characters are not masked.
- **A reading equal to a numeric secret** fails "value hidden" while it
  holds that value (the PIN `0100` and a level of `100`), and so does a
  point whose filter compares such a reading: the point flaps `bad`.
  Choose a PIN that is not a likely reading, or keep the echo endpoint
  apart from the readings.
- **Masking tells whether a text holds a secret, so guesses can be
  tested.** A `config` user who can put candidates into a device's `query`
  or `headers` on an endpoint of the same origin that echoes the request
  sees `***` in place of the one candidate that equals the secret: a
  4-digit PIN falls in about 10 requests, a 6-digit one in about 1000, a
  common password to a dictionary. A long random token does not fall this
  way. Use long random secrets; a PIN or a short password is not protected
  from a `config` user of an echoing server.
- **Member names stay raw** for selectors (so `$.adminState` works). When
  a server uses a secret as a member name, `$['<guess>']` is an equality
  test, and the order of `$.obj.*` follows the raw names. Only a server
  that puts a configured secret into a member name is affected.
- **Other encodings of a secret** are not masked: a query key re-encoded by
  the server (`%2f` in lower case, `+` for a space) or HTML entities in an
  error page.
- **System CAs** (`ca_pem` empty) are loaded once per process, at the first
  `https://` connection; CAs the host adds later need a restart. The first
  load reads the host's store (files, or the macOS keychain) on the thread
  that parses the connection. `SSL_CERT_FILE` and `SSL_CERT_DIR` work in an
  embedded link; a process link gets a cleared environment, so there they
  do not apply: give `ca_pem`.
