# Link `http` — generic HTTP/REST JSON poller

**Why:** many energy meters, inverters, weather stations, cloud APIs and building gateways offer only a JSON REST API. One generic link covers them without code per vendor.

**Scope**
- Connection = a base URL (`https://host:port/api`), timeout, auth: none / basic (user + `secret` password) / bearer token (`secret`) / API key in a named header or query parameter (`secret`), TLS (CA PEM, client cert PEM + key `secret`, insecure-skip-verify default off), default headers (non-secret), rate limit (requests per second, default 5).
- Device = one request: method GET/POST, path, query, optional JSON body template, `poll_s`, `expect_status` (default 200–299). One request per device per period feeds all its points.
- Point = a selector into the JSON reply: a JSONPath subset — `$.a.b`, `$.items[0].v`, `$.items[?(@.id=="x")].v`, wildcard `[*]` with an `aggregate` (`sum|max|min|avg|count|first`) — use a maintained crate such as `serde_json_path` (MIT/Apache) if its license and size fit, else a small in-crate subset with tests. Value types: number, bool, string; `scale`/`offset`/`unit`; `bool_true` text for string→bool mapping.
- Writes: a point may be writable with a `write` template: method, path and a JSON body where `{{value}}` is replaced by the JSON-encoded value; success = 2xx; then read-back on the next poll.
- Errors: HTTP 4xx → device error with the status (401/403 → "authentication failed"); 5xx and timeouts → device miss; a selector that finds nothing → point error naming the path; body over the bound (default 4 MiB) → device error.
- HTTP stack: `hyper` 1 + `hyper-util` + `tokio-rustls` (ring), as `links/agent`; follow at most 3 redirects to the same host only.
- Actions: on a device, `try_request` → `{status, headers (non-secret), body (truncated to 64 KiB)}`, and `test_selector {path}` → the selected value from the last body (commissioning).

**Not in scope**: OAuth2 flows (note as follow-up; a static bearer token works), XML/SOAP, websockets, webhooks in (push).

**Simulator**: an HTTP server in `src/sim.rs` with JSON endpoints (nested objects, arrays, changing numbers), basic and bearer auth checks, a writable resource (PUT/POST), and failure modes (401, 500, slow, invalid JSON, huge body).
