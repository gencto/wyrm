# Example link packages

Packages to install with `sys/links` ▸ Install Link (ADR 0011). The guide is
[`docs/links.md`](../../docs/links.md).

| Path | What it is |
|---|---|
| `process-link/` | Crate `wyrm-example-link`: the `mockdev` framework driver as its own binary on `wyrm-link-sdk::process::run`. The model for a process package. |
| `build.sh` | Builds everything below into `out/` (not in git). |

`build.sh` writes:

| File | Install with |
|---|---|
| `out/example-link-<os>-<arch>.zip` | from Zip: a process package for this host. |
| `out/register-wasm.zip` | from Zip: a WASM package (no network; one writable register per point, initially 7). |
| `out/register.wasm` | from WASM. |
| `out/tcp-ping.wasm` | from WASM: `init` takes a port (Config `5020`); `read` sends `ping` to `127.0.0.1:<port>` and returns the reply (needs `127.0.0.1:<port>` in Network). |
| `out/index.json` | from Repository: the index of both zips on `http://127.0.0.1:8090` (`REPO_PORT`). `examples/demo/run.sh` serves `out/` there. |

The process package carries a binary for the host that built it only. For
other hosts, build `wyrm-example-link` for each target and add each binary
to `entries` in `wyrm-link.json`.
