# Minimal container images

One static build per platform (musl, the release profile: thin LTO, one codegen unit,
stripped), then one `scratch` image per binary: the binary, the CA roots, `/etc/passwd` with
an unprivileged user (65532) and empty directories that user owns. No shell, no libc, no
package manager: nothing in an image but what the program reads.

| Image | Dockerfile target | What runs |
|---|---|---|
| `<ns>/wyrmd` | `wyrmd` | the broker (router, admin, flow engine, gateway, embedded links; process links as `wyrmd link <driver>` from the same binary) |
| `<ns>/wyrm-link-<name>` | `link`, `--build-arg LINK=<name>` | one link as an `external` link: `WYRM_*` environment, mTLS to the broker |
| `<ns>/wyrm-sim-<name>` | `sim`, `--build-arg SIM=<name>` | a device simulator (examples) |
| `<ns>/wyrm-tools` | `tools` | `wyr` and `wyrm-agent` on Alpine, with a shell (not minimal: an operator's box) |

`<ns>` is `genctouk` for the images on Docker Hub and `wyrm` for images built on this host
(tag `local`). The links with an image are the `LINKS` of `docker-bake.hcl`: alarm, bacnet,
dql, dynamodb, gdrive, http, influxdb, knx, localfs, modbus, mongodb, mqtt, mysql, opcua,
postgres, prometheus, s3, s7, scheduler, snmp, uplink, webdav. The simulators: modbus, snmp.

## On Docker Hub

| | |
|---|---|
| Namespace | [`genctouk`](https://hub.docker.com/u/genctouk): `genctouk/wyrmd`, `genctouk/wyrm-link-<name>`, `genctouk/wyrm-sim-<name>`, `genctouk/wyrm-tools` |
| Platforms | `linux/amd64`, `linux/arm64`, `linux/arm/v7`, `linux/arm/v6`: one manifest list per image, Docker pulls the host's |
| Tags | `<version>` (for example `0.1.0`), `<major>.<minor>` (`0.1`) and `latest`; a pre-release version (`0.2.0-rc.1`) gets its own tag only |
| Attestations | SLSA provenance (`mode=max`) and an SPDX SBOM per platform: `docker buildx imagetools inspect genctouk/wyrmd:<version> --format '{{json .Provenance}}'` |

No release is published yet: until the first `docker-v<version>` tag, build the images here
(below). Then:

```sh
docker pull genctouk/wyrmd:0.1.0
docker run --rm genctouk/wyrmd:0.1.0 --version
# the example below with the published images, without a build:
export WYRM_GATEWAY_ADMIN_PASSWORD='<a password>'
WYRM_NAMESPACE=genctouk WYRM_TAG=0.1.0 docker compose -f deploy/docker/compose.yaml up -d
```

Every image of a platform comes from one build of that platform, so `wyrmd`, the links and
`wyr` of one tag are the same source. `linux/riscv64` is not a platform: wasmtime 50 does not
build for `riscv64gc-unknown-linux-musl` (packaging/wyrmd/README.md). On 32-bit ARM the WASM
links and the `wasm` flow node run on an interpreter, about 10 times slower.

### How a release is made

The workflow `.github/workflows/docker-images.yml` builds and pushes; nobody pushes from a
laptop.

1. Once: in Docker Hub, make an access token for `genctouk` with **Read & Write**
   (Account settings ▸ Personal access tokens). The first push creates each repository with
   the account's default visibility: keep it public.
2. Once: in GitHub, add the repository secrets `DOCKERHUB_USERNAME` (`genctouk`) and
   `DOCKERHUB_TOKEN` (the token) under Settings ▸ Secrets and variables ▸ Actions.
3. Tag the commit with the workspace version (`version` in `Cargo.toml`, what
   `wyrmd --version` says) and push the tag:
   ```sh
   git tag docker-v0.1.0 && git push origin docker-v0.1.0
   ```

A run without the secrets, or with a tag that is not the workspace version, fails in its first
job and pushes nothing. Actions ▸ docker-images ▸ Run workflow builds every platform and pushes
nothing (push off); a pull request that changes `deploy/docker/**` builds `linux/arm/v7` only.

The shape of the run: one job per platform (`linux/amd64` on an x86-64 runner, the three ARM
platforms on Arm runners) runs `docker buildx bake` once, which compiles once and makes every
image of that platform, and pushes each image by digest with its attestations; one job then
puts the four digests of each image into one manifest list and tags it. The compile runs on the
runner's own architecture in every job (cargo-zigbuild for arm/v7 and arm/v6, no emulation);
only `apk add` of the tools image runs under QEMU. The GitHub Actions cache keeps the toolchain
layers per platform, and the whole build of the same sources (a re-run, or a tag on a commit
that a build-only run on `main` built); cargo's own cache mounts do not outlive a runner, so
changed sources compile from the start.

## Building here

```sh
docker buildx bake -f deploy/docker/docker-bake.hcl --load        # every image: wyrm/*:local
docker build -f deploy/docker/Dockerfile --target wyrmd -t wyrm/wyrmd:local .
docker build -f deploy/docker/Dockerfile --target link --build-arg LINK=modbus -t wyrm/wyrm-link-modbus:local .
```

The build stage compiles every binary once (`LINKS`, `SIMS` build args); each image then
copies one. `JOBS` (default 2) bounds parallel jobs; `wyrmd`'s link alone takes about 3 GB.
A fat-LTO link of `wyrmd` did not fit in 8 GB (killed after 19 min), so the images use the
release profile. A cold build of everything takes about 90 min on 2 jobs (Apple M4 Max, 8 GB
for Docker); `--build-arg LINKS="modbus snmp"` (or `LINKS="modbus snmp"` in the environment of
`bake`) builds only those.

Another platform: add `--platform linux/arm/v7` to `docker build`, or
`--set '*.platform=linux/arm/v7'` to `bake` (with `--load`, one platform at a time). The Rust
build runs on the build host (`$BUILDPLATFORM`): a target of the host's architecture is built
with cargo and `musl-gcc`, any other with cargo-zigbuild (zig 0.17.1, cargo-zigbuild 0.24.1, as
in the wyrmd release). The `tools` stage needs QEMU for a foreign platform (Docker Desktop has
it; on Linux, `docker run --privileged --rm tonistiigi/binfmt --install all`). The compiler is
the image's (`RUST` build arg, 1.100): `RUSTUP_TOOLCHAIN` overrides the repository's
`rust-toolchain.toml`, which names `stable`.

`NAMESPACE` and `TAG` of `bake` name the images (`wyrm` and `local` by default); the compose
file reads `WYRM_NAMESPACE` and `WYRM_TAG`.

Runtime notes:
- The allocator is musl's own. mimalloc was tried and dropped: it reserves a 1 GiB arena at
  start, so a process link under its `RLIMIT_DATA` (`link_limits.memory_mb`, 1024 by default)
  could not start a single thread (Linux CI). The measurements below were taken with the
  mimalloc builds: binary and image sizes differ by a few hundred KiB at most; idle memory
  with musl's allocator was not measured again.
- The runtime runs on a thread with an 8 MiB stack (`wyrm_link_sdk::process::run_on_big_stack`):
  with musl `stacker` cannot tell the main thread's stack bounds, and the JSON5 parser of the
  Zenoh config then refuses every input ("stack limit reached").

## The example: a broker and two links

```sh
export WYRM_GATEWAY_ADMIN_PASSWORD='<a password>'   # required: no default
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
  the broker's network namespace. For the Flutter app on this host, `--profile dev` adds
  `gateway-port`, a plaintext forward to `127.0.0.1:8445`; the other containers of the network
  reach that forward too, so it is for development only. In production give the gateway a
  certificate (`gateway.tls_cert`, `tls_key`) instead.

## Measured

Measured 2026-11-05: linux/arm64, Docker Desktop on Apple M4 Max; idle, two links connected,
the probe run once. Image sizes are compressed layers (what a registry stores and a host pulls).

| Image | Binary (MiB) | Image, compressed (MiB) | Idle memory | Threads |
|---|---|---|---|---|
| `wyrmd` | 61.1 | 26.6 | 91 MiB | 28 |
| `wyrm-link-modbus` | 14.2 | 6.7 | 28 MiB | 21 |
| `wyrm-link-snmp` | 13.9 | 6.6 | 24 MiB | 21 |
| `wyrm-sim-modbus` | 1.3 | 0.7 | 9 MiB | 15 |
| `wyrm-sim-snmp` | 1.2 | 0.7 | 10 MiB | 15 |
| `wyrm-tools` (Alpine) | | 18 | | |

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

