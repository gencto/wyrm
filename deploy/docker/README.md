# Minimal container images

One static build (musl, the release profile: thin LTO, one codegen unit, stripped; mimalloc
as the allocator), then one `scratch` image per binary: the binary, the CA roots, `/etc/passwd`
with an unprivileged user (65532) and empty directories that user owns. No shell, no libc,
no package manager: nothing in an image but what the program reads.

| Image | Target | What runs |
|---|---|---|
| `wyrm/wyrmd` | `wyrmd` | the broker (router, admin, flow engine, gateway, embedded links; process links as `wyrmd link <driver>` from the same binary) |
| `wyrm/link-<name>` | `link`, `--build-arg LINK=<name>` | one link as an `external` link: `WYRM_*` environment, mTLS to the broker |
| `wyrm/sim-<name>` | `sim`, `--build-arg SIM=<name>` | a device simulator (examples) |
| `wyrm/tools` | `tools` | `wyr` and `wyrm-agent` on Alpine, with a shell (not minimal: an operator's box) |

```sh
docker build -f deploy/docker/Dockerfile --target wyrmd -t wyrm/wyrmd .
docker build -f deploy/docker/Dockerfile --target link --build-arg LINK=modbus -t wyrm/link-modbus .
```

The build stage compiles every binary once (`LINKS`, `SIMS` build args); each image then
copies one. `JOBS` (default 2) bounds parallel jobs; `wyrmd`'s link alone takes about 3 GB.
A fat-LTO link of `wyrmd` did not fit in 8 GB (killed after 19 min), so the images use the
release profile. A cold build of everything takes about 90 min on 2 jobs (Apple M4 Max, 8 GB
for Docker); `--build-arg LINKS="modbus snmp"` builds only those.

Runtime notes:
- mimalloc (feature `wyrmd/mimalloc`, `wyrm-link-sdk/mimalloc`): musl's malloc is slow under
  many threads.
- The runtime runs on a thread with an 8 MiB stack (`wyrm_link_sdk::process::run_on_big_stack`):
  with musl `stacker` cannot tell the main thread's stack bounds, and the JSON5 parser of the
  Zenoh config then refuses every input ("stack limit reached").

## The example: a broker and two links

```sh
docker compose -f deploy/docker/compose.yaml up -d --build
docker compose -f deploy/docker/compose.yaml run --rm tools
$ wyr probe --gateway http://127.0.0.1:8445 --site site1
$ wyrm-agent tree wy/site1/downstream --depth 1
```

- `wyrmd` (`wyrmd.json5`): site `site1`, TLS for links on `tls/0.0.0.0:7448` (the server
  certificate names `wyrmd`), two `external` links: `modbus` and `snmp`, each against a
  simulator container.
- `provision` waits until the broker has issued each link's certificate and token
  (`/data/links/<id>`) and copies only that link's files and the CA *certificate* into its
  own sub-volume; the link containers mount that, read-only, and never see the broker's
  volume or its CA key. Run it again after the broker renews a link certificate.
- Every WYRM container runs read-only, as user 65532, with no capabilities and
  `no-new-privileges`.
- The gateway listens on the broker's loopback (it requires TLS elsewhere). `tools` runs in
  the broker's network namespace; `gateway-port` forwards it to `127.0.0.1:8445` on this host
  for the Flutter app. Leave `gateway-port` out in production and give the gateway a
  certificate (`gateway.tls_cert`, `tls_key`) instead.

## Measured

Measured 2026-11-05: linux/arm64, Docker Desktop on Apple M4 Max; idle, two links connected,
the probe run once. Image sizes are compressed layers (what a registry stores and a host pulls).

| Image | Binary (MiB) | Image, compressed (MiB) | Idle memory | Threads |
|---|---|---|---|---|
| `wyrm/wyrmd` | 61.1 | 26.6 | 91 MiB | 28 |
| `wyrm/link-modbus` | 14.2 | 6.7 | 28 MiB | 21 |
| `wyrm/link-snmp` | 13.9 | 6.6 | 24 MiB | 21 |
| `wyrm/sim-modbus` | 1.3 | 0.7 | 9 MiB | 15 |
| `wyrm/sim-snmp` | 1.2 | 0.7 | 10 MiB | 15 |
| `wyrm/tools` (Alpine) | | 18 | | |

Every link binary of the full build (stripped, static; built before the stack fix, which adds
nothing measurable):

| Link | Binary (MiB) | Link | Binary (MiB) |
|---|---|---|---|
| alarm | 14.4 | mysql | 13.9 |
| bacnet | 13.9 | opcua | 18.6 |
| dql | 15.9 | postgres | 13.9 |
| dynamodb | 13.9 | prometheus | 14.8 |
| gdrive | 14.2 | s3 | 14.2 |
| http | 14.4 | s7 | 13.9 |
| influxdb | 13.9 | scheduler | 14.7 |
| localfs | 13.7 | snmp | 13.9 |
| modbus | 14.2 | uplink | 14.2 |
| mongodb | 13.9 | webdav | 14.2 |
| mqtt | 14.1 | `wyrm-agent` | 2.0 |

About 13.5 MiB of every link is the shared base: Zenoh with TLS and QUIC, tokio, rustls/ring
and the link SDK; a protocol adds 0.2-5 MiB (OPC UA the most). The broker carries the WASM
runtime (wasmtime), the flow engine, the gateway and every built-in driver.

