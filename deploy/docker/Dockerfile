# syntax=docker/dockerfile:1.29
#
# Minimal container images of WYRM (deploy/docker/README.md): one static musl build per
# platform (the release profile: thin LTO, one codegen unit, stripped), then one `scratch`
# image per binary: no shell, no libc, no package manager.
#
#   docker build -f deploy/docker/Dockerfile --target wyrmd -t wyrm/wyrmd:local .
#   docker build -f deploy/docker/Dockerfile --target link --build-arg LINK=modbus -t wyrm/wyrm-link-modbus:local .
#   docker buildx bake -f deploy/docker/docker-bake.hcl        # every image, one build stage
#
# Platforms: linux/amd64, linux/arm64, linux/arm/v7, linux/arm/v6. The Rust build runs on the
# build host ($BUILDPLATFORM, no emulation): a target of the host's architecture is built with
# cargo and musl-gcc, any other with cargo-zigbuild, as the wyrmd release workflow does. Only
# the `tools` stage runs a command on the target platform (apk, under QEMU elsewhere).
#
# The build context is the repository root (.dockerignore keeps it to the sources).

ARG RUST=1.100
ARG DEBIAN=trixie
ARG ALPINE=3.24

# ---- toolchain: the Rust target of $TARGETPLATFORM and, for a cross build, zig -------------
# hadolint ignore=DL3029
FROM --platform=$BUILDPLATFORM rust:${RUST}-${DEBIAN} AS toolchain
ARG TARGETPLATFORM
# zig and cargo-zigbuild as in .github/workflows/ci.yml and packaging/wyrmd/release-workflow.yml
ARG ZIG=0.17.1
ARG ZIGBUILD=0.24.1
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
# /etc/wyrm-build names the target (TRIPLE), the cargo subcommand (CARGO_BUILD) and the toolchain
# of this image: RUSTUP_TOOLCHAIN overrides the repository's rust-toolchain.toml ("stable"), which
# would otherwise download the newest stable at every build, without the target added here.
# hadolint ignore=DL3008
RUN --mount=type=cache,target=/usr/local/cargo/registry,sharing=locked \
    set -eu; \
    case "$TARGETPLATFORM" in \
      linux/amd64) t=x86_64-unknown-linux-musl ;; \
      linux/arm64|linux/arm64/v8) t=aarch64-unknown-linux-musl ;; \
      linux/arm/v7) t=armv7-unknown-linux-musleabihf ;; \
      linux/arm/v6) t=arm-unknown-linux-musleabihf ;; \
      *) echo "unsupported platform: $TARGETPLATFORM (linux/amd64, linux/arm64, linux/arm/v7, linux/arm/v6)" >&2; exit 1 ;; \
    esac; \
    host="$(rustc -vV | sed -n 's/^host: //p')"; \
    toolchain="$(rustup default | cut -d' ' -f1)"; \
    rustup target add "$t"; \
    printf 'TRIPLE=%s\nexport RUSTUP_TOOLCHAIN=%s\n' "$t" "$toolchain" > /etc/wyrm-build; \
    apt-get update -q; \
    if [ "${t%%-*}" = "${host%%-*}" ]; then \
      apt-get install -y -q --no-install-recommends musl-tools; \
      printf 'CARGO_BUILD=build\nexport CC_%s=musl-gcc\n' "$(echo "$t" | tr - _)" >> /etc/wyrm-build; \
    else \
      apt-get install -y -q --no-install-recommends python3-pip; \
      pip3 install --no-cache-dir --break-system-packages "ziglang==$ZIG"; \
      cargo install --locked cargo-zigbuild --version "$ZIGBUILD"; \
      printf 'CARGO_BUILD=zigbuild\n' >> /etc/wyrm-build; \
    fi; \
    rm -rf /var/lib/apt/lists/*; \
    cat /etc/wyrm-build

# ---- build: every binary at once, so dependencies compile once per platform ----------------
FROM toolchain AS build
WORKDIR /src
COPY . .
# The links built as their own binaries (process / external mode), by package suffix.
ARG LINKS="modbus snmp s7 bacnet knx opcua http prometheus mqtt postgres mysql mongodb influxdb dynamodb s3 gdrive webdav localfs uplink alarm dql scheduler"
# Device simulators for the compose example.
ARG SIMS="modbus snmp"
# Jobs at a time; wyrmd's link alone takes about 3 GB (fat LTO would need more than 8 GB).
ARG JOBS=2
# One target directory for every platform: cargo keeps each target apart under it and shares
# the build scripts and proc-macros of the host; `locked` runs one platform's build at a time.
# hadolint ignore=SC1091,SC2086
RUN --mount=type=cache,target=/usr/local/cargo/registry,sharing=locked \
    --mount=type=cache,target=/target,id=wyrm-target,sharing=locked \
    set -eu; \
    . /etc/wyrm-build; \
    pkgs="-p wyrmd -p wyr -p wyrm-link-agent"; bins="--bin wyrmd --bin wyr --bin wyrm-agent"; \
    feats="wyrm-link-agent/cli"; \
    for l in $LINKS; do \
      pkgs="$pkgs -p wyrm-link-$l"; bins="$bins --bin wyrm-link-$l"; feats="$feats,wyrm-link-$l/process"; \
    done; \
    for s in $SIMS; do bins="$bins --bin wyrm-$s-sim"; feats="$feats,wyrm-link-$s/bin"; done; \
    CARGO_TARGET_DIR=/target cargo "$CARGO_BUILD" --locked --release --target "$TRIPLE" -j "$JOBS" \
      $pkgs $bins --features "$feats"; \
    o="/target/$TRIPLE/release"; \
    mkdir -p /out; \
    cp "$o/wyrmd" "$o/wyr" "$o/wyrm-agent" /out/; \
    for l in $LINKS; do cp "$o/wyrm-link-$l" /out/; done; \
    for s in $SIMS; do cp "$o/wyrm-$s-sim" /out/; done; \
    ls -l /out

# ---- what every image needs besides its binary -----------------------------------------------
# The CA roots (TLS to platforms and repositories), an unprivileged user, and writable
# directories owned by it (a named volume mounted there takes their owner). Nothing here
# depends on the platform, so it is made once on the build host.
# hadolint ignore=DL3029
FROM --platform=$BUILDPLATFORM alpine:${ALPINE} AS rootfs
RUN set -eu; mkdir -p /rootfs/etc/ssl/certs /rootfs/data /rootfs/state /rootfs/tmp; \
    cp /etc/ssl/certs/ca-certificates.crt /rootfs/etc/ssl/certs/; \
    echo 'wyrm:x:65532:65532:wyrm:/data:/sbin/nologin' > /rootfs/etc/passwd; \
    echo 'wyrm:x:65532:' > /rootfs/etc/group; \
    chown 65532:65532 /rootfs/data /rootfs/state; chmod 1777 /rootfs/tmp

# ---- the broker -----------------------------------------------------------------------------
FROM scratch AS wyrmd
COPY --from=rootfs /rootfs/ /
COPY --from=build /out/wyrmd /wyrmd
USER 65532:65532
ENV TZ=UTC
VOLUME /data
# 7448 TLS for links and operators; 7449/7450 QUIC for peer brokers (when configured)
EXPOSE 7448 7449/udp 7450/udp
ENTRYPOINT ["/wyrmd"]
CMD ["-c", "/etc/wyrm/wyrmd.json5"]

# ---- one link, external mode (WYRM_* environment, mTLS to the broker) -----------------------
FROM scratch AS link
ARG LINK=modbus
COPY --from=rootfs /rootfs/ /
COPY --from=build /out/wyrm-link-${LINK} /wyrm-link
USER 65532:65532
ENV TZ=UTC WYRM_DATA_DIR=/state
VOLUME /state
ENTRYPOINT ["/wyrm-link"]

# ---- a device simulator (examples only) -----------------------------------------------------
FROM scratch AS sim
ARG SIM=modbus
COPY --from=rootfs /rootfs/ /
COPY --from=build /out/wyrm-${SIM}-sim /wyrm-sim
USER 65532:65532
ENTRYPOINT ["/wyrm-sim"]

# ---- tools: wyr and wyrm-agent with a shell, for the broker's loopback gateway --------------
FROM alpine:${ALPINE} AS tools
# hadolint ignore=DL3018
RUN apk add --no-cache jq ca-certificates
COPY --from=build /out/wyr /out/wyrm-agent /usr/local/bin/
USER 65532:65532
ENTRYPOINT ["/bin/sh"]
