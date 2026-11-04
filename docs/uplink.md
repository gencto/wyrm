# Uplink: platform upstreams

The uplink sends a site's **live values** to the platforms the rest of the plant uses: an MQTT
broker as a Unified Namespace (HiveMQ, EMQX, Mosquitto, …), a Sparkplug B host (Ignition's MQTT
Engine and others), ThingsBoard, Azure IoT Hub and AWS IoT Core. An upstream is added with one
action, as an upstream broker is added on `sys/upstream`, and shows as a node with its status
and counters. Design: ADR 0035.

For complete, ordered data (every row, replayed after an outage) use a history sink instead
(ADR 0026, [`history.md`](history.md) §6): the uplink is live and at most once.

## Where it runs

| Mode | What | Rights and network |
|---|---|---|
| Embedded (default) | `wy/<site>/downstream/uplink` in every `wyrmd` | reads this site's `downstream`, `dataflows`, `storage` and the readable sections of downstream sites; network from `uplink.net` |
| WASM package `uplink` | the same link, installed from a repository or zip | what an operator grants (`sys/links/<id>/~act/grant`): `read` on each root an upstream selects; `net` from the package's capabilities or the link's params |
| Process package `uplink-process` | the same link as a process | as the WASM package |

`wyrmd.json5`:

```json5
uplink: {
  enabled: true,            // default
  store_mb: 2,              // definitions and secrets
  // the platforms it may reach (ADR 0012 syntax, host names allowed); empty = none
  net: "broker.plant.example:8883, *.azure-devices.net:8883, *.iot.eu-central-1.amazonaws.com:8443",
  // upstreams fixed here (origin: config): the Add fields plus kind and name
  upstreams: [
    { name: "uns", kind: "mqtt", url: "mqtts://broker.plant.example", topic_prefix: "plant" },
  ],
}
```

The id `uplink` is reserved. A host that `net` does not cover is refused at Add, with the entry
to add; the secret of a config-file upstream still goes in with Set Password.

## The link's tree

```
uplink/
  add_mqtt, add_sparkplug, add_thingsboard, add_azure, add_aws   config
  stats/upstreams, connected, published, dropped
  <name>/                attrs: kind, origin (runtime | config), select
    status               connecting | connected | waiting | failed | disabled
    error                the last error
    url, connected_since, published, dropped, queued, last_publish
    enabled              writable at config (not for a config-file upstream)
    set_password         the one secret, kept in the link's sealed store
    test_connection      a whole handshake now → {success, message}
    edit, remove         not for a config-file upstream
```

- **`failed`** means the platform refused the credentials (or a secret is missing): nothing is
  tried again until Edit, Set Password or Enable. **`waiting`** means a network error: the
  link connects again after a back-off (1 s, ×2, up to `retry_s`). The queue stays through both.
- Definitions come back after a restart; secrets with them.

## Fields every kind takes

| Field | Meaning |
|---|---|
| `name` | one key segment: the upstream's node |
| `url` | `mqtt://host:1883`, `mqtts://host:8883` (Azure: made from `hub` when empty; AWS: `https://<endpoint>:8443`) |
| `select` | full node keys whose values go up, one per line or comma: everything under each; default `wy/<site>/downstream`; the link's own subtree never goes |
| `max_hz` | at most this many values per point per second, the latest kept while over; 0 = every change |
| `queue_max` | values held while the platform is slower than the site (10 000; up to 100 000); the oldest go, counted in `dropped` |
| `flush_ms` | how often queued values are sent (250) |
| `ca_pem` | trust only this CA (TLS) |
| `timeout_ms`, `retry_s` | a connect or request; the longest wait between attempts |
| `insecure_plaintext` | send the secret over `mqtt://` or `http://` to a host that is not loopback |
| `enabled` | |

A plaintext URL to a host that is not loopback is refused without `insecure_plaintext`: the
secret would go in the clear.

## The kinds

### `mqtt` — a Unified Namespace

One topic per point: `<topic_prefix>/<site>/<path>` (the key below `wy/`), e.g.
`plant/edge1/downstream/plc1/d0/temp`. Payload `json` (default): `{"v": 21.5, "q": "good",
"t": 1700000000000000}` (`t` in UTC µs, as the tree has it); `payload: value` sends the value
alone (`21.5`, `true`, `hot`). `retain` is on by default so a consumer reads the last value at
once; `qos` 0 (default) or 1. Fields: `topic_prefix` (`wyrm`), `qos`, `retain`, `payload`,
`client_id` (`wyrm-<site>-<name>`), `username` (the password with Set Password),
`keep_alive_s` (60).

### `sparkplug` — Sparkplug B 3.0

The site is the edge node (`edge_node_id`, default the site's name) in `group_id` (`wyrm`); a
link under `downstream` is a device (`<link>`; another site's `<site>.<link>`); `dataflows` and
`storage` are devices of their own; a metric is the path below the device (`d0/temp`).
Numbers are `Double`, bools `Boolean`, text `String`, so a metric's type never changes between
an integer and a float. On every connect: `NBIRTH` (with `bdSeq` from the store and `Node
Control/Rebirth`), then a `DBIRTH` per device with every metric seen so far; changes are
`DDATA`; a device that shows a new metric (or a metric whose type changed) is born again;
`NDEATH` is the will. `Node Control/Rebirth` on `NCMD` (and `Device Control/Rebirth` on
`DCMD`) answers with a full rebirth. Same MQTT fields as `mqtt`.

### `thingsboard` — the gateway API

The link is a ThingsBoard **gateway**; `username` is the gateway's access token (Set Password).
A link is a device named `<device_prefix>-<link>` (`device_prefix` defaults to the site's
name), announced with `v1/gateway/connect` once per session and fed with
`v1/gateway/telemetry` `{"<device>": [{"ts": <ms>, "values": {"<path>": v}}]}` per flush,
QoS 1. Devices are created on first sight.

### `azure` — IoT Hub

Fields `hub` (`myhub` or `myhub.azure-devices.net`), `device_id`, `sas_ttl_s` (3600). The
device key (base64, from the hub) goes in with Set Password; the link makes a SAS token from it
and connects again with a new one before it runs out. Username `<hub>/<device>/?api-version=…`,
topic `devices/<device>/messages/events/$.ct=application%2Fjson&$.ce=utf-8`, payload a JSON
array of `{"key", "v", "q", "t"}` per flush (`key` below `wy/`), QoS 1. X.509 devices are not
supported (no client certificates in the host yet).

### `aws` — IoT Core over HTTPS

Fields `url` (`https://<endpoint>-ats.iot.<region>.amazonaws.com:8443`, the account's data
endpoint), `region`, `access_key_id`, `topic` (`wyrm/<site>`); the secret access key goes in
with Set Password. Every flush is one `POST /topics/<topic>?qos=1` signed with Signature V4
(service `iotdata`) with a JSON array of samples. The IAM policy needs `iot:Publish` on the
topic. MQTT with mTLS is not supported (no client certificates in the host yet).

## Rights

Every action and the `enabled` leaf are `config` on the uplink (the built-in roles `engineer`
and `admin`). The link never writes to other links; its one key is its store key.

## Limits

16 upstreams per link; `select` ≤ 32 keys per upstream; one `tcp_send` ≤ 64 KiB and at most 8
per flush; 32 unacknowledged QoS 1 packets; a `CONNACK` within 10 s; a `PUBACK` within 30 s;
MQTT 3.1.1, QoS 0 and 1. Counters reset when the link starts.
