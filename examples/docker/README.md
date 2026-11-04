# Docker test bench

A Linux container with the CI toolchain, Mosquitto and PostgreSQL. It runs the
three-site demo (`examples/demo`) on loopback inside the container, so the
gateways, the uplink (ADR 0035) and the alarm sinks (ADR 0034) can be tested
end to end with `wyrm-agent` (ADR 0033).

The repository is mounted read-only at `/src`. Builds go to the named volume
`/target`, the demo runs in `/work` (its own `data/`, never the host's
`examples/demo/data`).

```sh
docker compose -f examples/docker/compose.yaml up -d --build
docker compose -f examples/docker/compose.yaml exec wyrm examples/docker/demo.sh
docker compose -f examples/docker/compose.yaml exec wyrm bash
```

Inside the container:

```sh
# the probe on every site
for s in central:8445 edge:8444 plant:8446; do
  wyr probe --gateway http://127.0.0.1:${s##*:} --site ${s%%:*}
done
# alarms on edge, then the uplink and the alarm export (check, then --apply)
wyrm-agent --gateway http://127.0.0.1:8445 run /src/examples/agent/alarms.json --apply
wyrm-agent --gateway http://127.0.0.1:8445 run /src/examples/agent/uplink-and-alarm-export.json --apply
# what reached the platforms
mosquitto_sub -h 127.0.0.1 -u uplink -P mq-pass-1 -t 'plant/#' -v --retained-only
mosquitto_sub -h 127.0.0.1 -u uplink -P mq-pass-1 -t 'spBv1.0/#' -F '%t %l'
PGPASSWORD=wyrm-pg-1 psql -h 127.0.0.1 -U wyrm wyrm \
  -c "select key, value_text::jsonb->>'state', value_text::jsonb->>'message' from alarms"
# the CI steps on Linux
CARGO_TARGET_DIR=/target/ci cargo clippy --locked --workspace --all-targets --all-features -- -D warnings
CARGO_TARGET_DIR=/target/ci cargo test --locked --workspace --all-features
```

| Service | Address | Credentials |
|---|---|---|
| Gateways | central `127.0.0.1:8445`, edge `:8444`, plant `:8446` | `admin` / `wyrm-demo-1` |
| Mosquitto | `127.0.0.1:1883` | `uplink` / `mq-pass-1` |
| PostgreSQL 15 | `127.0.0.1:5432`, database `wyrm` | `wyrm` / `wyrm-pg-1` |
| Package repository | `http://127.0.0.1:8090/index.json` | `postgres-process` |

The tests that build WASM fixtures (`wyrm-link-guest`, `wyrm-link-wasm`, the `portable_app_*`
and `wasm_app_*` e2e tests) copy `Cargo.lock` into the repository and fail on the read-only
mount; GitHub CI runs them. One test binary links at a time in 8 GB: use
`CARGO_BUILD_JOBS=1` for `cargo test` if `ld` is killed.

`demo.sh stop` stops everything; `demo.sh clean` also deletes `/work`. Right
after a start, wait about 10 s before you command edge or plant from central:
a site below polls the keys of the site above every 10 s.
