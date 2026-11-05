# syntax=docker/dockerfile:1.7
#
# Minimal container images of WYRM (deploy/docker/README.md): one static musl build (the
# release profile: thin LTO, one codegen unit, stripped; mimalloc), then one `scratch` image per
# binary: no shell, no libc, no package manager.
#
#   docker build -f deploy/docker/Dockerfile --target wyrmd -t wyrm/wyrmd .
#   docker build -f deploy/docker/Dockerfile --target link --build-arg LINK=modbus -t wyrm/link-modbus .
#
# The build context is the repository root (.dockerignore keeps it to the sources).

ARG RUST=1.99

# ---- build: every binary at once, so dependencies compile once -------------------------------
FROM rust:${RUST}-alpine AS build
RUN apk add --no-cache musl-dev build-base ca-certificates
WORKDIR /src
COPY . .
# The links built as their own binaries (process / external mode), by package suffix.
ARG LINKS="modbus snmp s7 bacnet opcua http prometheus mqtt postgres mysql mongodb influxdb dynamodb s3 gdrive webdav localfs uplink alarm dql scheduler"
# Device simulators for the compose example.
ARG SIMS="modbus snmp"
# Jobs at a time; wyrmd's link alone takes about 3 GB (fat LTO would need more than 8 GB).
ARG JOBS=2
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/target,id=wyrm-musl-target \
    set -eu; \
    pkgs="-p wyrmd -p wyr -p wyrm-link-agent"; bins="--bin wyrmd --bin wyr --bin wyrm-agent"; \
    feats="wyrmd/mimalloc,wyrm-link-agent/cli"; \
    for l in $LINKS; do \
      pkgs="$pkgs -p wyrm-link-$l"; bins="$bins --bin wyrm-link-$l"; feats="$feats,wyrm-link-$l/process"; \
    done; \
    for s in $SIMS; do bins="$bins --bin wyrm-$s-sim"; feats="$feats,wyrm-link-$s/bin"; done; \
    CARGO_TARGET_DIR=/target cargo build --locked --release -j "$JOBS" \
      $pkgs $bins --features "$feats"; \
    mkdir -p /out; \
    cp /target/release/wyrmd /target/release/wyr /target/release/wyrm-agent /out/; \
    for l in $LINKS; do cp /target/release/wyrm-link-$l /out/; done; \
    for s in $SIMS; do cp /target/release/wyrm-$s-sim /out/; done; \
    ls -l /out
# What every image needs besides its binary: the CA roots (TLS to platforms and repositories),
# an unprivileged user, and writable directories owned by it (a named volume mounted there takes
# their owner).
RUN set -eu; mkdir -p /rootfs/etc/ssl/certs /rootfs/data /rootfs/state /rootfs/tmp; \
    cp /etc/ssl/certs/ca-certificates.crt /rootfs/etc/ssl/certs/; \
    echo 'wyrm:x:65532:65532:wyrm:/data:/sbin/nologin' > /rootfs/etc/passwd; \
    echo 'wyrm:x:65532:' > /rootfs/etc/group; \
    chown 65532:65532 /rootfs/data /rootfs/state; chmod 1777 /rootfs/tmp

# ---- the broker -----------------------------------------------------------------------------
FROM scratch AS wyrmd
COPY --from=build /rootfs/ /
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
COPY --from=build /rootfs/ /
COPY --from=build /out/wyrm-link-${LINK} /wyrm-link
USER 65532:65532
ENV TZ=UTC WYRM_DATA_DIR=/state
VOLUME /state
ENTRYPOINT ["/wyrm-link"]

# ---- a device simulator (examples only) -----------------------------------------------------
FROM scratch AS sim
ARG SIM=modbus
COPY --from=build /rootfs/ /
COPY --from=build /out/wyrm-${SIM}-sim /wyrm-sim
USER 65532:65532
ENTRYPOINT ["/wyrm-sim"]

# ---- tools: wyr and wyrm-agent with a shell, for the broker's loopback gateway --------------
FROM alpine:3.22 AS tools
RUN apk add --no-cache jq ca-certificates
COPY --from=build /out/wyr /out/wyrm-agent /usr/local/bin/
USER 65532:65532
ENTRYPOINT ["/bin/sh"]
