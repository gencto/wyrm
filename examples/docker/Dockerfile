# Linux test bench for WYRM (examples/docker/README.md): the CI toolchain,
# plus an MQTT broker and PostgreSQL for the uplink and the alarm sinks.
FROM rust:1.99-bookworm
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      mosquitto mosquitto-clients postgresql postgresql-client python3 jq procps \
 && rm -rf /var/lib/apt/lists/*
RUN rustup component add rustfmt clippy && rustup target add wasm32-unknown-unknown
# target/ and the cargo registry live in named volumes, never the host's; three
# jobs and line tables only keep the linker within 8 GB (GNU ld was killed
# linking wyrmd's tests with full debug info).
ENV CARGO_TARGET_DIR=/target CARGO_BUILD_JOBS=3 CARGO_PROFILE_DEV_DEBUG=line-tables-only \
    WYRM_GATEWAY_ADMIN_PASSWORD=wyrm-demo-1 \
    WYR_GATEWAY_PASSWORD=wyrm-demo-1 PATH=/target/release:$PATH
WORKDIR /src
