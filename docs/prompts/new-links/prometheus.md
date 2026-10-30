# Link `prometheus` — scrape Prometheus / OpenMetrics endpoints

**Why:** most modern software and many devices (node_exporter, PLC gateways, inverters, databases, Kubernetes) publish metrics in the Prometheus text format. This link turns selected series into WYRM points, so the historian, flows and alarms work on them.

**Scope**
- Connection = one HTTP(S) endpoint: URL (`http://host:9100/metrics`), timeout, optional basic auth (user + `secret` password) or bearer token (`secret`), TLS with CA PEM / insecure-skip-verify flag (default off), extra headers (non-secret), `scrape_s` (default 15).
- Device = a logical group under the connection (a label filter applied to all its points, e.g. `instance="a"`), so one scrape feeds several devices; the scrape runs once per connection per period, not once per point.
- Point = a series selector: metric name + label matchers (`=`, `!=`, `=~`, `!~` with a small regex engine — use the `regex` crate), plus `aggregate` when several series match: `none` (error if more than one matches), `sum`, `max`, `min`, `avg`, `count`. For counters: `mode` `raw` or `rate_per_s` (difference between scrapes, reset-aware). Histograms/summaries: points may select `_bucket`, `_sum`, `_count`, a `quantile`, or `histogram_quantile {q}` computed from buckets. `scale`/`offset`/`unit`.
- Parser: Prometheus text exposition 0.0.4 and OpenMetrics 1.0 text (comments, `# TYPE`, `# UNIT`, escaped label values, `NaN`/`+Inf`/`-Inf`, timestamps ignored or used for the sample time when present). Bound the body size (default 8 MiB) and the series count (default 100 000); a body over the bound is a connection error with a clear message.
- Use the `plan` to compile all selectors of a connection once; one scrape → all points.
- Gzip response bodies (`Accept-Encoding: gzip`) if cheap (`flate2`, MIT/Apache).
- Actions: on a connection, `list_series {match?, limit = 200}` returning the series names and label sets of the last scrape (commissioning).
- HTTP: `hyper` 1 + `hyper-util` + `tokio-rustls` (ring) as `links/agent` does; no `reqwest` unless it can be configured without aws-lc/native-tls.

**Not in scope**: remote-write receiver, PromQL beyond the selector + aggregation above, exporting WYRM values to Prometheus (separate feature).

**Simulator**: an HTTP server in `src/sim.rs` that serves a text exposition with counters that grow, a gauge, a histogram with buckets, label variants, and failure modes (500, slow body, oversized body, malformed lines).
