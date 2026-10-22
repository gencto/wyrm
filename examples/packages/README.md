# Example link packages

Packages to install with `sys/links` ▸ Install Link (ADR 0011). The guide is
[`docs/links.md`](../../docs/links.md); the link crates and how to install
each one are in [`examples/links`](../links/README.md).

`build.sh` builds the crates in `examples/links` and the WASM components,
and writes into `out/` (not in git):

| File | What it is | Install with |
|---|---|---|
| `out/example-link-<os>-<arch>.zip` | Responder: the `mockdev` framework driver as its own binary (`examples/links/responder`). | from Zip |
| `out/recorder-<os>-<arch>.zip` | Requester: records `wy/{site}/down/mock` to CSV (`examples/links/requester`); asks for a `read` grant. | from Repository, Package `recorder` |
| `out/average-<os>-<arch>.zip` | Responder and requester: statistics of `wy/{site}/down/mock` and Write All (`examples/links/both`); asks for a `write` grant. | from Url `http://127.0.0.1:8090/average-<os>-<arch>.zip` |
| `out/register-wasm.zip` | A WASM package (no network; one writable register per point, initially 7). | from Zip, or from Repository, Package `register` |
| `out/register.wasm` | The same component alone. | from WASM |
| `out/tcp-ping.wasm` | `init` takes a port (Config `5020`); `read` sends `ping` to `127.0.0.1:<port>` and returns the reply (needs `127.0.0.1:<port>` in Network). | from WASM |
| `out/index.json` | The repository index of the four zips on `http://127.0.0.1:8090` (`REPO_PORT`). `examples/demo/run.sh` serves `out/` there. | `packages.repository` |

A process package carries a binary for the host that built it only. For
other hosts, build the crate for each target and add each binary to
`entries` in `wyrm-link.json`.
