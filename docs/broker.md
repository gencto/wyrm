# Broker reference

The broker's own trees and endpoints in one place: the control plane `sys/**`,
profiles, broker storage, two or more brokers, and the user gateway. The root
[README](../README.md) says what WYRM is; [operations.md](operations.md) says how
to run it. The normative protocol is [`spec/`](../spec/README.md).

## Control plane
`wyrm-admin` serves `wy/<site>/sys/**` with the same `list`/`subscribe`/`invoke` as devices. Actions need a `ptok` with `config`, except `hello`, which checks the link token.

| Node | Actions / value |
|---|---|
| `sys` | values as on a DSA broker (versions, start time, traffic per second, `allow_all_links`, `enable_quarantine`); `~act/clear_conns`, `get_permissions`, `update_permissions {role, path, level}` |
| `sys/links` | Install Link ▸ `~act/install {id, driver, mode, params}` (from Driver), `install_zip {name, zip}`, `install_url {name, url}`, `install_git {name, url, ref}`, `install_repo {name, package}`, `install_wasm {name, wasm}` — packages run as process or WASM links; see [`docs/links.md`](links.md) |
| `sys/packages/<name>` | installed link package (version, kind, source, SHA-256); `~act/remove` |
| `sys/upstream` | brokers this one connects to (as DSA's): `~act/add {name, url, ca, token, enabled}` with `url` the upstream's `peers.enroll`; this broker makes its own key and asks for its certificate; `<site>` shows `url`, `ca`, `certificate`, `key` (SHA-256 of our public key), `status` (`pending authorization`, `issued`, a refusal), writable `enabled`; `~act/remove` (ADR 0015) |
| `sys/overlays/<link>` | attributes the broker lays over that link's nodes (ADR 0016): today `attr.history` of each recorded point (its watch keys); the link's SDK merges them into `~meta` and the `view=list` summary (`has_history`) |
| `sys/tokens` | `~act/add {count, hours}` → a token (shown once) that admits a downstream broker at once; `<id>` shows `uses` and `expires`, `~act/remove` |
| `sys/~act/enroll` | open action on the `peers.enroll` listener: a downstream broker's `{site, csr, token, via}` → `{status: issued, certificate, port}`, `pending` or `refused` |
| `sys/links/<id>` | `~act/start`, `stop`, `remove`, `hello {token}`, `set_secret {name, value}`, `delete_secret {name}`, `update {params}`, `history`, `rollback {rev}` (runtime-installed links; the last 10 params revisions are kept), `grant {path, level}` (requester grants, ADR 0013); child `state` (`installed`, `starting`, `connected`, `stopping`, `stopped`, `failed`) |
| `sys/quarantine` | `~act/authorize {dsid, group, name, via}`, `deauthorize {link}` (a runtime external link or downstream broker goes back to quarantine) |
| `sys/quarantine/<cn>` | unknown CA-signed certificate (a link over `tls`, or a downstream broker `broker:<site>` over `quic`, `attr.kind`); `~act/approve {driver, params, group, name}` (`{via}` for a broker), `reject` |
| `sys/log_level`, `sys/~act/get_log {lines, level, filter, link}` | broker log level (saved) and its last log lines; `sys/links/<id>/log_level` and `~act/get_log` for each embedded or process link |
| `sys/acl_denied` | router access-control drops (with the other broker status values: uptime, links, sessions, CPU, memory, disk) |
| `sys/history` | embedded historian (ADR 0014): database values, `auto_purge`, `disk_space_remaining`, `retention_days`; `~act/add_watch_group {name, logging_type, interval, buffer_flush_time}`, `purge {timerange}`; `sys/history/<group>`: `edit`, `add_watch_path {path}`, `remove {purge}`; `sys/history/<group>/w<N>`: `enabled`, `start_date`, `end_date`, `get_history {timerange, interval, rollup, limit}`, `purge`, `unsubscribe`, `unsubscribe_purge` — see [`docs/history.md`](history.md) |
| `sys/audit` | `~act/tail {n}` — HMAC-chained audit records |
| `wy/<site>/sys/broker` | liveliness token of the broker (no node); `sys` `~meta` carries `attr.proto`, `version`, `site` |

`wyr` gets admin commands as well (links, install, set-secret, …) — see `wyr --help`. ACL changes rebuild the router runtime (ADR 0006).

Link secrets (device passwords, keys) live in `data_dir/secrets.bin` (ChaCha20-Poly1305, key file 0600), never in the tree, `~def` or logs. `install` refuses params that look like secrets. Embedded links get them at start, process links in the `hello` reply; a link sees a new secret on its next start. `wyr admin set-secret <site> <id> <name>` reads the value from stdin.

## Profiles
A node's `~meta.is` names a profile; absent fields come from it, through `extends` (spec 02). The admin serves `wy/<site>/pub/<profile>/~meta` (10 built-ins such as `wy:number`, `wy:folder`, `wy:link`; others stored in its WAL) and changes them with `sys/profiles/~act/put {name, profile}` and `remove {name}` (`config`). `?expand=true` returns a profile with its chain folded in; `WyrmClient::meta_expanded(node)` returns a node's `~meta` with its profile applied. Links and upstream sites may read `pub/**`; nobody but the admin writes it.

## Storage
`wy/<site>/storage` keeps nodes and values people create, as a DSA broker's `/data` (ADR 0017). The root offers `add_node {name}`, `add_value {name, type, editor}`, `publish {path, value}` (creates the missing folders and a `dynamic` value), `export` and `import {data | file}` (JSON: `$type`, `@editor`, `?value`, children as objects, binary as `{"$hex": …}`; a `file` larger than a WebSocket frame goes over `POST /api/invoke`); a folder also offers `delete {recursive}`, `rename {name}` and `duplicate {name}`, a value `~set`, `delete`, `rename` and `duplicate`. Types: `string`, `number`, `bool`, `array`, `map`, `binary`, `dynamic`. Every action and `~set` needs `write`; the admin keys, users through the gateway (viewer `read`, operator `write`, engineer `config`) and flows (at `write`) are trusted. The tree lives in `data_dir/storage/storage.redb`: structure at once, values at most once a second. Limits: 10 000 nodes, 16 levels, 32 KiB per value, 64 MiB in all, 4 MiB per import or export. A link stored under the id `storage` (before spec 0.2.2) stops `wyrmd` from starting: remove it with the previous version. The historian may watch storage values (`add_watch_path {path: "storage/…"}`); an upstream site reads them.

## Two brokers
```json5
// central: brokers connect on 7449; they ask for their certificate on 7450
peers: { listen: "quic/0.0.0.0:7449", enroll: "quic/0.0.0.0:7450" },
```
As in DSA (ADR 0015), the downstream broker adds the connection itself: on edge, `sys/upstream` ▸ **Add Upstream Connection** {Name `central`, Url `quic/central.example:7450`, CA (central's `data_dir/pki/ca.pem`), Token (optional)}. Edge makes its own key and asks central for a certificate. Central admits it:
1. at once with a token from its `sys/tokens` ▸ Add Token, when edge relays no sites;
2. at once with `sys/allow_all_links` on, when edge relays no sites;
3. else edge waits in `sys/quarantine/edge` (`kind: broker`): compare its `key` with edge's `sys/upstream/central/key`, then **Authorize** (Via: the sites edge relays).

A broker that names relayed sites (`via`, at most 16) always waits for Authorize, token or not: only an administrator gives a downstream broker the right to publish under other sites' names (security review ADM-2, ADR 0031).

Edge then connects on 7449 and shows up in `wy/central/downstream/edge`; **Deauthorize** sends it back to quarantine. Central's QUIC listeners trust its own CA alone (certificate CN `broker:<site>`); edge trusts central's CA only on that connection.

Without runtime steps (`wyrmd.json5` on both sides): central lists `downstream: [{ site: "edge" }]` and `wyrmd -c central.json5 ca` issues `data_dir/peers/edge/broker.{pem,key}`; edge names them: `upstream: [{ site: "central", endpoint: "quic/central.example:7449", ca, cert, key }]`. The upstream site may subscribe and query `~meta|~val` under `wy/<edge>/{downstream,dataflows,sys,upstream,storage}/**` (and `~def|~state` under `downstream`/`dataflows`). Requesters at the central broker may read `wy/<edge>/**`.

Commands from above (ADR 0018): central's users (through its gateway) and operators (with central's admin key, `SigningTokens::new(key, "edge")`) may `set` and `invoke` on edge's `downstream`, `dataflows` and `storage` at `write`, as far as their grants at central go (`wy/central/x` grants count as `wy/edge/x`); `config` there (link actions such as Export, Edit, Stop) and edge's `sys` only when edge allows it: `allow_config: true` on the `peers.upstream` entry, or `sys/upstream/central/allow_config`. Edge learns the keys that sign these requests from `wy/central/sys/signing_keys` (central's admin keys and gateway key, and the keys above central; for `config` only those every hop allows) and trusts them only within its own site, at those levels; learning new keys rebuilds edge once. A `sys` action that edge does not allow is dropped on the way, so the caller sees a timeout. Edge's audit names the user as `user:<name>@central`. Clocks must agree within a few minutes (tokens live 5 minutes).

Certificates last 365 days. The broker issues its own again (listener, client, process links, `data_dir/peers/<d>/broker.*`) when one has less than 30 days left: at a start, at each rebuild and in an hourly check that rebuilds when one was renewed. A downstream broker that enrolled asks its upstream again with the same key in those 30 days, and the upstream signs a new certificate for that key (audit `renew`); if the upstream does not renew, `sys/upstream/<u>/status` says so and the downstream asks again every hour (security review D-1, ADR 0031). УВАГА: files issued for `peers.downstream` without enrollment (`wyrmd ca`) are renewed only in the upstream's `data_dir/peers/<d>/`: copy them to the downstream again before the old ones end.

A chain `plant → edge → central`: edge lists plant as its downstream (and listens on QUIC), central adds `via: ["plant"]` to its edge entry, and then reads `wy/plant/**` through edge (ADR 0007) and commands it as plant allows (`allow_config` at each hop for `sys`).

Demo with a chain of three sites and connectors:
`examples/demo/run.sh` starts `central`, `edge` (`mock`, `mockdev`, `modbus`
as a process link, `modbus_slave`, `http`, `snmp`, `prometheus`) and `plant`
(`mock`, `s7`, `bacnet`, `opcua`; connected to edge), each link against its
simulator, each with a gateway (`:8445`, `:8444`, `:8446`, user
`admin`, password `wyrm-demo-1`); central reads plant through edge. `wyrmd -c <cfg> ca` creates a site's CA
and the certificates of the sites below it before they start. The app is
WYRM Studio (`studio/`, [studio.md](studio.md)); it logs in to
any of the three gateways.

## Gateway
```json5
gateway: { listen: "0.0.0.0:8443", tls_cert: "gw.pem", tls_key: "gw.key", admin_user: "admin" },
```
Start `wyrmd` once with `WYRM_GATEWAY_ADMIN_PASSWORD` set to create the first admin. On a stopped broker, `wyrmd -c wyrmd.json5 user list|add <name> --roles a,b|passwd|roles|disable|enable|remove` manages users (passwords from stdin, changes audited as `local:cli`); while it runs, the stores are locked and the gateway's `/api/users` endpoints do the same. `POST /api/login {user, password}` (CBOR) returns a session; `POST /api/ws-ticket` (bearer session) returns a single-use 30 s ticket, and `GET /api/ws?ticket=…` opens the WebSocket proxy (`list`, `subscribe`, `set`, `invoke`, `doc`, filtered by the user's grants). `doc {key, suffix}` reads a node's document (`suffix`: `~state` or `~def`, at most 1 MiB) with the rights of `list` on the node; a restricted node (an agent's `tasks`) decides by the user's own token. `invoke … approve {steps: [n…], plan}` on an agent task is signed by the gateway: one token per named step, for the plan it reads itself, within the user's grants (ADR 0049, `docs/agent.md`). The gateway signs one `ptok` per request with its own key, which links, the flow engine and the admin (`sys/**`) trust; the user's grants decide what each request may do, and only the `admin` role has grants on `sys/**` (ADR 0009). Whoever can read `data_dir/gateway/gateway.key` is therefore a full administrator: keep `data_dir` readable by the broker user only. One user holds at most 8 WebSockets and sends at most 100 requests per second over all of them (burst 200; `rate_limited` past it); a `history` request asks for at most 10 000 rows (security review GW-2).

### Device keys, step-up and finding the gateway (ADR 0050)

```json5
gateway: {
  listen: "0.0.0.0:8443", tls_cert: "gw.pem", tls_key: "gw.key",
  tls_ca: "ca.pem",            // optional: the CA whose code people compare (default below)
  devices: { enabled: true, max_per_user: 5, password_every_days: 30, idle_lock_max_min: 30,
             step_up: "none",  // "config": config changes need a confirm in the last 5 min
             allow_device_credential: false,
             origins: [] },    // default: the names of gw.pem on this port
  announce: { enabled: true, interfaces: [], pair: "gw-b.plant.example:8443" },
}
```

A person turns on *Unlock with Touch ID* (or Windows Hello, Face ID, fingerprint) in Studio after a password login. The device makes a key in its secure hardware; the gateway keeps only the public key, in the users store (SCHEMA 5, replicated to a standby like the users). A later login is a signature over a single-use 60 s challenge: `POST /api/device/challenge {device}` → `{nonce}`, then `POST /api/device/login {device, origin, nonce, signature}` → the session a password login gives, with the same roles. The gateway refuses with a `code`: `device_removed` (an admin removed it), `password_changed` (a new password, *Sign out everywhere* or a disable signs every device out), `password_due` (no password on that device for `password_every_days`; a password login that names the device, `POST /api/login {…, device}`, clears it) and `devices_off`. An unknown device, a bad signature, a used or old nonce and an origin not in `devices.origins` all get the same bare `401`, limited like password logins. `GET /api/devices` lists a user's own devices, `DELETE /api/devices/<id>` turns one off (an admin's removal of another user's device leaves a tombstone that names the admin), `GET /api/users/<name>/devices` lists anyone's for an admin, and `POST /api/me/sign-out` ends every session and signs every device out. With `step_up: "config"`, a `config` change (a `config` action or point, user management, removing someone's device) of a session that did not log in or confirm in the last 5 minutes answers `confirm_required` with a `nonce` and the request's hash: sign them with `POST /api/device/confirm` or send `POST /api/confirm {password}`, then send the request again. MCP tokens cannot confirm, so a site with the step-up on gives the MCP endpoint no `config`. Audit: `device_added`, `device_login`, `device_refused`, `step_up`, `device_removed`; never a key, nonce or signature. The signed bytes and the full rules: ADR 0050, last section.

`GET /api/info` (no session, 60 a minute per address) tells a log-in page `{site, version, tls, role, pair?, up, devices: {policy}, min_studio, ca_fp?, ca?}`. When the gateway listens off loopback, `wyrmd` also announces it by DNS-SD (`_wyrm._tcp`, instance = site, TXT `v`, `site`, `tls`, `fp`, `role`, `pair`, `up`; no users, no secrets) while it serves; `announce: {enabled: false}` turns that off. Finding a gateway never means trusting it: Studio shows the CA's code (`ca_fp`, 8 groups of 4) and the person compares it with `wyrmd ca fingerprint` on the broker before Studio pins that CA. The code is of `gateway.tls_ca`, else the last certificate of a chain in `tls_cert`, else the site CA when it issued `tls_cert`.

## Flows

`wy/<site>/dataflows/~act/deploy {def, proofs}` deploys a flow (spec 06); `~def` is read-only. Links trust the flow engine's key, so the deployer sends one token per command target (`proofs`: target key → token with at least the flow's `maxperm`, same subject). Targets must be exact keys under `wy/<site>/downstream/` or `wy/<site>/storage/`. `wyrm_flow::command_targets` and `WyrmClient::proof` build the proofs; through the gateway, the gateway adds them (ADR 0008, 0033).
```
wyr --key admin.key flow validate local peak.json5     # compile only
wyr --key admin.key flow deploy   local peak.json5     # signs one proof per invoke/set target
wyr flow list local                                     # id, state (running|stopped|error), version
wyr --key admin.key flow show local peak                # state + ~def
wyr --key admin.key flow stop|start|reload|remove local peak
```
`dataflows/<id>/~val` holds the flow's state, version, deployer and, since spec 06 0.2.31, its counters `stats` (samples in and out, dropped, restarts, commands sent/ok/error; ADR 0045). The blocks are in [flow-blocks.md](flow-blocks.md); ready-made flows in [`examples/flows`](../examples/flows/README.md).
