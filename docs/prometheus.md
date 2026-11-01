# Prometheus link

The `prometheus` link scrapes endpoints that publish metrics in the
Prometheus text format (0.0.4) or OpenMetrics 1.0 text: `node_exporter`,
databases, Kubernetes components, PLC gateways, inverters and more. It
turns the series you select into WYRM points, so the historian, flows and
alarms work on them. Crate: `links/prometheus`, on the driver framework
(ADR 0004). Points are read-only.

## 1. The tree

```
downstream/<link>/
  <connection>        one HTTP(S) endpoint, e.g. http://host:9100/metrics
    <device>          a label filter applied to all its points
      <point>         a series selector and what to compute from it
```

- **Connection** = one endpoint. The link scrapes it once per `scrape_s`,
  whatever the number of devices and points. Each scrape uses a new HTTP
  connection.
- **Device** = a logical group under the connection: a label filter such
  as `instance="a"`. Use one device per instance, job or machine behind a
  federating endpoint.
- **Point** = a series selector (`node_cpu_seconds_total{mode="idle"}`),
  with an aggregate when several series match, a mode (`raw` or
  `rate_per_s`) and a function (`value` or `histogram_quantile`).

The framework gives every connection and device the `status` and `error`
leaves, the actions `add_*`, `edit`, `remove`, `restart`, `stop`/`start`,
`copy`, `export` and `import`, and the diagnostics leaves (section 6).

## 2. Add it

1. Install the driver: `sys/links` ▸ Install Link ▸ from Driver, driver
   `prometheus` (or the package `prometheus` from a repository).
2. On the link ▸ **Add Connection**: name, URL, and the other params in
   section 3.
3. On the connection ▸ **List Series** shows what the endpoint serves.
4. On the connection ▸ **Add Device**: name, Label Filter (empty = all
   series).
5. On the device ▸ **Add Point**: name, Selector, and the other params.

A `wyrmd.json5` example (one link, two devices fed by one scrape):

```json5
links: [{
  id: "metrics", driver: "prometheus",
  params: { connections: { node: {
    url: "http://10.0.0.5:9100/metrics", scrape_s: 15,
    devices: {
      host: { labels: "", points: {
        load1: { selector: "node_load1" },
        cpu_idle: { selector: "node_cpu_seconds_total{mode=\"idle\"}",
                    aggregate: "sum", mode: "rate_per_s" },
        rx: { selector: "node_network_receive_bytes_total{device=\"eth0\"}",
              mode: "rate_per_s", scale: 8, unit: "bit/s" },
      }},
      disk_root: { labels: "mountpoint=\"/\"", points: {
        free: { selector: "node_filesystem_avail_bytes", scale: 1e-9, unit: "GB" },
      }},
    },
  }}},
}]
```

## 3. Parameters

### Connection

| Param | Default | Bounds | Meaning |
|---|---|---|---|
| `url` | (required) | `http://` or `https://`, no user info | The endpoint. IPv6 as `[::1]`. |
| `timeout_ms` | 5000 | 100 … 60 000 | Bound on one scrape: connect, TLS, headers and body. |
| `scrape_s` | 15 | 1 … 3600 | Time between two scrapes. |
| `username` | `""` | no `:` | Basic auth user. |
| `password` | `""` | secret | Basic auth password. |
| `bearer_token` | `""` | secret | `Authorization: Bearer …` instead of basic auth. |
| `ca_pem` | `""` | PEM | CA certificates for `https`; empty = the system roots. |
| `cert_pem` | `""` | PEM | Client certificate for mutual TLS. |
| `key_pem` | `""` | secret, PEM | Private key of `cert_pem`. |
| `insecure_skip_verify` | `false` | | Accept any server certificate. For tests only: the `status` leaf shows a warning while it is on. |
| `headers` | `""` | at most 32 | Extra request headers, one `Name: value` per line. Not for credentials. |
| `gzip` | `true` | | Send `Accept-Encoding: gzip` and decode gzip bodies. |
| `max_body_mib` | 8 | 1 … 64 | Bound on the body, on the wire and after gzip decoding. The parsed exposition may take up to 16 times this in memory (section 9). |
| `max_series` | 100 000 | 1 … 1 000 000 | Bound on the series of one scrape, and on its `# TYPE` and `# UNIT` entries. |

Rules checked when you add or edit a connection (the edit is refused and
nothing changes):

- `ca_pem`, `cert_pem` and `insecure_skip_verify` need an `https://` URL.
  `cert_pem` and `key_pem` go together. A PEM that does not parse is
  refused.
- Give `username`/`password` or `bearer_token`, not both. A password needs
  a username.
- Credentials are never sent in plaintext to a host that is not loopback:
  use `https://`.
- `headers` may not set `Authorization`, `Proxy-Authorization`, `Cookie`,
  `Host`, `Content-Length`, `Transfer-Encoding`, `Connection`,
  `Accept-Encoding` or `TE`.

Secrets (`password`, `bearer_token`, `key_pem`) are entered in
`add_connection` or `edit`. The framework keeps them sealed in the link's
`data_dir`. They never show in `~meta`, `export`, replies or logs. An edit
that changes `url`, `ca_pem` or `insecure_skip_verify` drops the stored
secrets unless the edit gives them again.

### Device

| Param | Default | Meaning |
|---|---|---|
| `labels` | `""` | Label matchers applied to every point of the device, with or without braces: `instance="a", job=~"node.*"`. Empty = all series. |

### Point

| Param | Default | Bounds | Meaning |
|---|---|---|---|
| `selector` | (required) | a metric name is required | `name` or `name{matchers}`. |
| `aggregate` | `none` | `none`, `sum`, `max`, `min`, `avg`, `count` | How the matching series become one value. |
| `mode` | `raw` | `raw`, `rate_per_s` | `rate_per_s`: increase per second between two scrapes. |
| `function` | `value` | `value`, `histogram_quantile` | `histogram_quantile`: the `q` quantile from the `_bucket` series. |
| `q` | 0.5 | 0 … 1 | The quantile for `histogram_quantile`. |
| `scale` | 1 | | The point value is `value · scale + offset`. |
| `offset` | 0 | | |
| `unit` | `""` | | Shown in `~meta.unit`. |

## 4. Selectors and values

**Matchers** are as in PromQL: `=`, `!=`, `=~` and `!~`. Label values are
quoted strings with the escapes `\\`, `\"` and `\n`. A regex matches the
whole value (`^(?:re)$`) and uses the `regex` crate (no backreferences;
compiled size at most 1 MiB). A missing label has the value `""`, so
`l=""` matches series without `l`. A series matches a point when it has
the point's metric name, matches the point's matchers and the device's
filter.

**Names** are the exposed series names. In OpenMetrics a counter `foo`
is exposed as `foo_total`; select `foo_total`. Histograms and summaries:
select `<name>_bucket{le="0.5"}`, `<name>_sum`, `<name>_count` or a summary
quantile `<name>{quantile="0.99"}` like any other series.

**Aggregate:**

| `aggregate` | Value | No series matches |
|---|---|---|
| `none` | the one matching series; more than one is a point error | point error |
| `sum`, `max`, `min`, `avg` | over all matching series | point error |
| `count` | the number of matching series | 0 |

**`rate_per_s`** computes, per series, the increase since the last scrape
divided by the time between the two scrapes (the time each request
started). A counter reset (the value goes down, for example after the
exporter restarts) counts as an increase from 0, as in PromQL. The rates
of all series are then aggregated. A point has no value until its second
scrape. A series new since the last scrape is left out for one scrape.

**`histogram_quantile`**: the selector names the histogram (`<name>` or
`<name>_bucket`). The link sums the buckets of all matching series by `le`
(PromQL `histogram_quantile(q, sum by (le) (…))`), then interpolates
linearly inside the bucket of the rank. A `le="+Inf"` bucket and two
buckets at least are required. A rank in the `+Inf` bucket gives the
highest finite bound. With `mode: rate_per_s` the buckets are the
increases since the last scrape, so the quantile is that of the last
interval; with `raw` it is that of all observations since the exporter
started. `aggregate` must stay `none`. With `rate_per_s`, a point gets no
new value (it keeps its last one) while a bucket is new since the last
scrape, and for an interval with no observations (PromQL gives `NaN`
there): a quiet service does not flap to `bad`.

**Value type:** every point is a number (`f64`). Exposition values `NaN`,
`+Inf` and `-Inf` are parsed; a point whose result is not a finite number
is a point error (`bad`), never a made-up value.

**Timestamps** in the exposition are checked and then ignored. The sample
time of a point is the time the link publishes it.

## 5. Scrapes, errors and quality

Every point is evaluated once per second on the last good scrape. The
connection scrapes again when that scrape is `scrape_s` old (a poll up to
0.5 s early, at most a quarter of `scrape_s`, takes the next scrape: two
scrapes are never closer than that). Polls of several devices in the same
second share one attempt. A value is
published only when it changes.

| What happens | Class | Effect |
|---|---|---|
| connect refused, DNS, TLS or I/O error, broken response | connection | connection `failed` with the `error` leaf; devices `Stopped by Parent`; points `bad/disconnected`; reconnect with backoff (1 s … 60 s) |
| body over `max_body_mib`, more than `max_series` series, a parsed exposition over 16 × `max_body_mib` of memory | connection | as above; the error names the param |
| no complete response within `timeout_ms` | device miss | points `uncertain/stale`; after 3 misses in a row the device is `failed` and points are `bad/comm_fail` |
| HTTP status other than 2xx (500, 404, …) | device miss | as above; the device `error` leaf shows `HTTP <code>` |
| no series matches, several match with `none`, not a finite number, broken histogram (no `le="+Inf"` bucket, fewer than two buckets, a bad `le`, no observations at all with `raw`) | point | that point `bad`; its device stays `connected` |
| `histogram_quantile` with `rate_per_s`: a new bucket, or no observations in the interval | none | no new value; the point keeps its last value and quality |
| a line of the exposition that does not parse or is over a line bound (section 9) | none | the line is skipped and counted in `parse_errors` |

A failed scrape is not kept: the next second tries again, so each failed
attempt is one miss. After 3 misses the link tries again only `scrape_s`
after the end of the last attempt (polls and List Series alike), however
long `timeout_ms` is.
Opening the connection is a first scrape: a 401, a 404 or a timeout there
fails the connection with that reason.

Each scrape opens its own HTTP connection and closes it after the body. A
reply that comes after a timeout dies with its connection and is never
taken for a later scrape.

Gzip decoding and parsing run on a blocking thread, not on the broker's
async workers. A poll is bounded by `timeout_ms` + 5 s + 250 ms per MiB of
`max_body_mib`. A poll cut while the body is parsed is a miss, and the
next poll waits for that same parse instead of fetching a second body.

A device without points stays `Connecting`: the link has no device ping,
because a ping would mark a device good between failed scrapes.

## 6. Actions and diagnostics

- **List Series** (`list_series {match?, limit = 200}`, level `config`: it may scrape and holds the connection) on a
  connection: the series of the last scrape (or a new one when it is
  old): `total`, `truncated`, `bad_lines`, `age_ms` and `series`, each
  with `name`, `type` (from `# TYPE`), `labels` and `value` (`"NaN"`,
  `"+Inf"`, `"-Inf"` as text). `match` is a selector (empty = all),
  `limit` 1 … 10 000.
- **Diagnostics** on connections and devices: `requests` (scrapes),
  `errors` (I/O, oversize), `timeouts`, `exceptions` (non-2xx replies),
  `parse_errors` (skipped lines), `last_rtt_ms`, `avg_rtt_ms`. A scrape
  counts for the connection and for the device whose poll started it.

## 7. Writes

Prometheus endpoints are read-only. Every point has `writable: never`, and
a `~set` is refused; the value does not change.

## 8. Simulator

`wyrm-prometheus-sim` serves a test exposition on
`http://127.0.0.1:9101/metrics`:

```
cargo run -p wyrm-link-prometheus --features bin --bin wyrm-prometheus-sim -- \
    --listen 127.0.0.1:9101 [--openmetrics] [--malformed]
```

It serves `sim_requests_total{path="/a"|"/b"}` (counters that grow on
every scrape), `sim_temperature_celsius{instance="a"|"b",sensor="t1"}`
(gauges that drift), the histogram `sim_latency_seconds` (buckets 0.1,
0.5, 1, +Inf, growing every second), the summary `sim_rpc_seconds`,
`sim_escaped` (escaped label values) and `sim_nan`. In tests
(`links/prometheus/tests/sim.rs`, feature `sim`) the shared state also
gives the failure modes: 500 replies, silence, a slow body, an oversized
body (with or without `Content-Length`), malformed lines and a disconnect, plus basic or bearer auth and
gzip.

Try it with the simulator and a link:

1. Start the simulator (above).
2. Add a link with driver `prometheus` and a connection with URL
   `http://127.0.0.1:9101/metrics` and `scrape_s` 5.
3. Run ▸ List Series on the connection.
4. Add a device with Label Filter `instance="a"`, and a point with
   Selector `sim_temperature_celsius`.
5. Add a point with Selector `sim_requests_total`, Aggregate `sum`, Mode
   `rate_per_s`.

## 9. Limits

- **Addresses the link never connects to:** link-local (`169.254.0.0/16`, `fe80::/10`,
  where cloud instance metadata hands out credentials), other cloud metadata endpoints
  (`fd00:ec2::254`, `100.100.100.200`, `168.63.129.16`, `192.0.0.192`), unspecified,
  multicast and broadcast addresses, also inside IPv6 forms that carry an IPv4 address. The check runs on the address the host name
  resolves to, so DNS cannot lead there either. Loopback and private networks stay
  reachable: devices and simulators live there (security review LNK-1, ADR 0031).

What Prometheus has that this link does not do:

- **PromQL** beyond one selector with an aggregate, a rate and
  `histogram_quantile`: no `by`/`without` grouping, no arithmetic between
  series, no range functions other than the rate between two scrapes, no
  `offset`.
- **Exposition timestamps** do not become the sample time: the driver
  framework publishes a point with the time it publishes it.
- **Native histograms** and the protobuf exposition format are not read
  (only text). Quoted UTF-8 metric names (Prometheus 3) are skipped as
  malformed lines. Exemplars are skipped.
- No **remote-write** receiver, no service discovery, no relabelling, no
  `honor_labels`, no export of WYRM values to Prometheus.
- One endpoint per connection; HTTP/1.1 only (no HTTP/2), no proxy, no
  keep-alive between scrapes.
- An edit of a device or point re-plans its connection's points, and
  their rates start again: the first scrape after it gives no rate.
- An HTTP redirect (3xx) is a device miss; the link does not follow it.
- **Memory.** One scrape is bounded at 16 × `max_body_mib` of memory: the
  decoded body, a copy of it when it has invalid UTF-8, and the parsed
  exposition. The link counts the parsed exposition while it parses: the
  vector slots it holds (spare capacity too) and every non-empty name or
  value as one allocation of at least 32 bytes. Over the bound is a
  connection error that names `max_body_mib`. The real heap is within
  about 1.3 times this count (allocator headers). A typical exposition
  takes 4 to 8 times its size, so the default 8 MiB uses about 30 to
  70 MiB, and never more than about 128 MiB counted (about 170 MiB of
  heap). At 64 MiB the bound is 1 GiB counted (about 1.3 GiB of heap):
  keep `max_body_mib` at 16 or less on a 2 GB board. The last scrape is
  dropped before the next one arrives, and a parse whose connection was
  edited, stopped or failed to open stops within milliseconds, so two
  never live at once.
- **Line bounds.** A line over 1 MiB, a sample with more than 128 labels,
  a metric or label name over 1 KiB and a label value over 16 KiB are
  skipped and counted in `parse_errors`. `# TYPE` and `# UNIT` lines past
  `max_series` names are skipped the same way.
